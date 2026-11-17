// 真实开局页经 WebSocket 写进隔离存档：页面消失、丢回执、关闭世界后仍接着同一局。
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import { mkdirSync, readFileSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import vm from 'node:vm'
import { createRequire } from 'node:module'
import { randomUUID } from 'node:crypto'
import { createTown, root, startManager, worldQuery } from '../../../scripts/tests/support.mjs'

const require = createRequire(new URL('../package.json', import.meta.url))
const ts = require('typescript')
const plain = (value) => JSON.parse(JSON.stringify(value))
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
async function until(predicate, description) {
  const deadline = Date.now() + 15000
  while (!predicate()) {
    if (Date.now() > deadline) throw Error(description())
    await sleep(20)
  }
}

// 只替换浏览器 DOM/画像，不替换开局、世界设定、选择控件或任何持久化规则。
function page(prefab, endpoint, modelOptions = [], interruptKind, beforeCut, ordinary = false) {
  class Element {
    children = []
    attributes = new Map()
    placeholders = new Map()
    dataset = {}
    style = { setProperty() {} }
    hidden = false
    disabled = false
    open = false
    className = ''
    textContent = ''
    classList = { toggle() {}, add() {}, remove() {} }
    constructor(tag) {
      this.tag = tag
    }
    append(...children) {
      this.children.push(...children)
    }
    prepend(...children) {
      this.children.unshift(...children)
    }
    replaceChildren(...children) {
      this.children = children
    }
    setAttribute(name, value) {
      this.attributes.set(name, value)
    }
    getAttribute(name) {
      return this.attributes.get(name)
    }
    toggleAttribute() {}
    addEventListener() {}
    after() {}
    focus() {}
    select() {}
    showModal() {
      this.open = true
    }
    close() {
      this.open = false
    }
    matches(selector) {
      if (selector.startsWith('.')) return this.className.split(' ').includes(selector.slice(1))
      if (selector.startsWith('#')) return this.id === selector.slice(1)
      const attr = /^\[([^=]+)=['"]?([^'"]+)['"]?\]$/.exec(selector)
      return attr ? this.attributes.get(attr[1]) === attr[2] : this.tag === selector
    }
    querySelectorAll(selector) {
      return this.children
        .filter((child) => child instanceof Element)
        .flatMap((child) => [
          ...(child.matches(selector) ? [child] : []),
          ...child.querySelectorAll(selector),
        ])
    }
    querySelector(selector) {
      const found = this.querySelectorAll(selector)[0]
      if (found || !this.innerHTML) return found ?? null
      // 世界观首次对话框使用固定 innerHTML；这些控件不参与预制流程。
      if (!this.placeholders.has(selector)) this.placeholders.set(selector, new Element(selector))
      return this.placeholders.get(selector)
    }
  }
  const body = new Element('body')
  const flags = new Element('div')
  flags.id = 'hud-flags'
  body.append(flags)
  const document = {
    body,
    createElement: (tag) => new Element(tag),
    getElementById: (id) => body.querySelector(`#${id}`),
    querySelectorAll: (selector) => body.querySelectorAll(selector),
  }
  const timers = new Set()
  const modules = new Map()
  const storage = new Map()
  function load(relative) {
    const filename = path.resolve(root, 'frontend/town-shared/src', relative)
    if (modules.has(filename)) return modules.get(filename)
    const exports = {}
    modules.set(filename, exports)
    const scope = {
      exports,
      document,
      localStorage: {
        getItem: (key) => storage.get(key),
        setItem: (key, value) => storage.set(key, value),
      },
      console,
      crypto: { randomUUID },
      setTimeout(callback, ms) {
        const timer = setTimeout(() => {
          timers.delete(timer)
          callback()
        }, ms)
        timers.add(timer)
        return timer
      },
      clearTimeout(timer) {
        clearTimeout(timer)
        timers.delete(timer)
      },
      require(dependency) {
        if (dependency.endsWith('.css')) return {}
        if (dependency.endsWith('/portraits'))
          return { lookKey: () => '', portraitFor: () => '', templateKey: () => '' }
        if (dependency.endsWith('/game/icons'))
          return { iconLabel() {}, gameIcon: () => new Element('span') }
        if (dependency.endsWith('/platform'))
          return { isTouch: () => false, isCompact: () => false }
        const resolved = path.relative(
          path.join(root, 'frontend/town-shared/src'),
          path.resolve(path.dirname(filename), dependency === '.' ? './index' : dependency)
        )
        return load(`${resolved}.ts`)
      },
    }
    vm.runInNewContext(
      ts.transpileModule(readFileSync(filename, 'utf8'), {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
      }).outputText,
      scope,
      { filename }
    )
    return exports
  }
  const fixture = prefab ?? load('prefabs/swordholder.ts').swordholder
  const messages = []
  const sent = []
  let stopped = false
  let finished
  let interrupted
  let cutRequest
  let firstRuns = 0
  let socket
  const send = (message) => {
    if (stopped) return
    sent.push(plain(message))
    const kind =
      message.type === 'advance_prefab_setup'
        ? worldSettings.state()?.prefab_setup?.plan.steps[message.next_step]?.kind
        : message.type.replace(/^set_/, '')
    if (kind === interruptKind && !cutRequest) {
      cutRequest = message.request_id
      beforeCut?.(worldSettings.state())
    }
    socket?.send(JSON.stringify(message))
  }
  const worldSettings = load('worldSettings.ts').createWorldSettings(
    send,
    fixture.name,
    () => {},
    false
  )
  const setup = load('prefabs/setup.ts').createPrefabSetup({
    send,
    worldSettings,
    modelOptions: () => modelOptions,
    onFinish: (joined) => {
      finished = plain(joined)
    },
  })
  const guide = load('mobile/guide.ts').createGuide({
    send,
    save: () => assert.fail('本测试不调用模型配置保存'),
    suggestions: [],
    townName: fixture.name,
    description: '',
    worldSettings,
    speeds: { current: () => 1, choose() {} },
    normalSpeed: 1,
    onFinish: (_started, joined) => {
      finished = plain(joined)
    },
  })
  const registry = load('shell/panel.ts').createPanelRegistry()
  registry.add(setup.panel, guide.panel, worldSettings)
  load('shell/firstRun.ts').installFirstRun(worldSettings, () => {
    firstRuns++
    if (ordinary) guide.open(load('mobile/guide.ts').guideDone() ? 2 : 0)
    else setup.open(fixture)
  })
  function deliver(message) {
    registry.dispatch(message)
  }
  function connect() {
    socket = new WebSocket(endpoint)
    socket.onopen = () => registry.connected()
    socket.onmessage = ({ data }) => {
      const message = JSON.parse(data)
      messages.push(message)
      if (stopped) return
      if (cutRequest && message.request_id === cutRequest) {
        interrupted = message
        stopped = true
        registry.disconnected()
        socket.close()
        return
      }
      deliver(message)
    }
  }
  if (endpoint) connect()
  const active = () =>
    body.children.find((el) => el.className?.split(' ').includes('guide') && !el.hidden) ?? body
  const find = (predicate) => active().querySelectorAll('button').find(predicate)
  return {
    prefab: fixture,
    body,
    sent,
    messages,
    worldSettings,
    setup,
    guide,
    deliver,
    connect: () => registry.connected(),
    disconnect: () => registry.disconnected(),
    finished: () => finished,
    interrupted: () => interrupted,
    firstRuns: () => firstRuns,
    reconnect(nextKind) {
      stopped = false
      interrupted = undefined
      cutRequest = undefined
      interruptKind = nextKind
      beforeCut = undefined
      connect()
    },
    start() {
      const button = find((b) => /^(开始|继续)这一局$/.test(b.textContent))
      assert.ok(button, '未完成世界应重新打开开局页')
      assert.equal(button.disabled, false)
      button.onclick()
    },
    click(text) {
      const button = find((b) => b.textContent === text)
      assert.ok(button, `没有按钮 ${text}`)
      assert.equal(button.disabled, false)
      button.onclick()
    },
    close() {
      stopped = true
      for (const timer of timers) clearTimeout(timer)
      timers.clear()
      registry.dispose()
      socket?.close()
    },
  }
}

const stateOf = async (town) =>
  (
    await worldQuery(
      town.endpoint,
      { type: 'get_world_settings' },
      (m) => m.type === 'world_settings'
    )
  ).state
const populationOf = async (town) =>
  (await worldQuery(town.endpoint, { type: 'get_population' }, (m) => m.type === 'population'))
    .population
const diagnostic = (p) =>
  JSON.stringify({
    state: p.worldSettings.state(),
    messages: p.messages.slice(-3),
    sent: p.sent.slice(-3),
  })

// 一局跨真实提交边界：冻结选择、世界观、道具、首位入住、玩法。中途只换页面，不重选人数、规则或模型。
test(
  '预制开局丢回执、刷新和关镇重开后恢复原选择，人物道具不重建、已完成玩法不重开',
  { timeout: 90000 },
  async () => {
    const home = await fs.mkdtemp(path.join(os.tmpdir(), 'town-prefab-resume-'))
    let manager
    let current
    let blockedPath
    const pages = []
    const loader = page()
    const prefab = loader.prefab
    loader.close()
    const models = [
      { provider: 'setup-a', model: 'a', name: '测试甲' },
      { provider: 'setup-b', model: 'b', name: '测试乙' },
    ]
    try {
      manager = await startManager(home)
      const existing = (await manager.api('/models')).providers.map(({ id, name, base_url }) => ({
        id,
        name,
        base_url,
      }))
      await manager.api('/models', {
        active: null,
        providers: [
          ...existing,
          ...models.map((model) => ({
            id: model.provider,
            name: model.name,
            base_url: 'http://127.0.0.1:9/v1',
          })),
        ],
        keys: [],
      })
      const town = await createTown(manager, prefab.spec)
      current = await manager.api(`/${town.id}/open`, {})
      let selection
      let firstResident
      for (const kind of ['begin_prefab_setup', 'worldview', 'join_failed', 'join', 'game_mode']) {
        const blocker = path.join(home, 'towns', town.id, 'world.json.tmp')
        let beforeFailure
        const p = page(
          prefab,
          current.endpoint,
          models,
          kind === 'join_failed' ? 'join' : kind,
          kind === 'join_failed'
            ? (state) => {
                beforeFailure = plain(state.prefab_setup)
                mkdirSync(blocker)
                blockedPath = blocker
              }
            : undefined
        )

        pages.push(p)
        await until(
          () => p.firstRuns() > 0,
          () => diagnostic(p)
        )
        if (!selection) {
          p.click('−')
          p.click('−')
          p.click('固定种子')
          p.click('4 小时')
          const seed = p.body.querySelector('.prefab-seed')
          seed.value = '12345'
          seed.onchange()
          const choices = p.body.querySelectorAll('select')
          const second = choices.find(
            (el) => el.getAttribute('aria-label') === `${prefab.cast[1].name}用的模型`
          )
          second.value = 'setup-b\nb'
          second.onchange()
        }
        p.start()
        await until(
          () => p.interrupted(),
          () => diagnostic(p)
        )
        assert.equal(p.interrupted().ok, kind !== 'join_failed', diagnostic(p))
        if (kind === 'join_failed') {
          const failed = await stateOf(current)
          assert.deepEqual(failed.prefab_setup, beforeFailure, '写盘失败不能推进游标或留下入住结果')
          assert.equal((await populationOf(current)).residents.length, 0)
          await fs.rm(blocker, { recursive: true })
          blockedPath = undefined
        }
        const persisted = await stateOf(current)
        assert.ok(persisted.prefab_setup, '开局进度必须来自世界存档，不能只存在旧页面')
        selection ??= plain(persisted.prefab_setup.plan.selection)
        assert.deepEqual(persisted.prefab_setup.plan.selection, selection)
        assert.equal(selection.players, 7)
        assert.equal(selection.models[1].provider, 'setup-b')
        if (kind === 'begin_prefab_setup') {
          const begin = p.sent.find((message) => message.type === 'begin_prefab_setup')
          const competing = await worldQuery(
            current.endpoint,
            {
              ...begin,
              request_id: 'competing-page',
              setup_id: 'other-page',
              expected_revision: persisted.revision,
            },
            (message) => message.type === 'prefab_setup_saved'
          )
          assert.equal(competing.ok, false, JSON.stringify(competing))
          const ordinary = await worldQuery(
            current.endpoint,
            {
              type: 'set_worldview',
              request_id: 'old-worldview-page',
              world_id: persisted.world_id,
              expected_revision: persisted.revision,
              text: '旧页面不能覆盖正在恢复的剧本。',
            },
            (message) => message.type === 'world_settings_saved'
          )
          assert.equal(ordinary.ok, false, JSON.stringify(ordinary))
          assert.deepEqual((await stateOf(current)).prefab_setup, persisted.prefab_setup)
        }
        if (kind === 'game_mode') {
          assert.equal(persisted.ready, true)
          assert.equal(persisted.prefab_setup.next_step, persisted.prefab_setup.plan.steps.length)
        } else {
          assert.equal(persisted.ready, false, '半成品不能运行或被当成完成')
          const speed = await worldQuery(
            current.endpoint,
            { type: 'set_speed', world_id: persisted.world_id, speed: 1 },
            (m) => m.type === 'error'
          )
          assert.ok(speed.message)
        }
        if (kind === 'worldview') {
          // 回执丢失使等待者被 disconnected 取消；同一页面重连回读后继续到道具步骤。
          const received = p.messages.length
          p.reconnect('place_prop')
          await until(
            () =>
              p.worldSettings.online() &&
              p.messages.slice(received).some((m) => m.type === 'world_settings'),
            () => diagnostic(p)
          )
          p.start()
          await until(
            () => p.interrupted(),
            () => diagnostic(p)
          )
          assert.equal(p.interrupted().ok, true, diagnostic(p))
          const resumed = await stateOf(current)
          assert.deepEqual(resumed.prefab_setup.plan.selection, selection)
          assert.ok(resumed.prefab_setup.next_step > persisted.prefab_setup.next_step)
        }
        p.close()
        if (kind === 'join') {
          const population = await populationOf(current)
          assert.equal(population.residents.length, 1)
          firstResident = plain(population.residents[0])
          await manager.api(`/${town.id}/close`, {})
          current = await manager.api(`/${town.id}/open`, {})
          assert.equal(current.worldId, persisted.world_id)
          assert.deepEqual((await stateOf(current)).prefab_setup.plan.selection, selection)
        }
      }
      const finalPopulation = await populationOf(current)
      assert.equal(finalPopulation.residents.length, 7)
      assert.equal(new Set(finalPopulation.residents.map((r) => r.id)).size, 7)
      assert.deepEqual(finalPopulation.residents[0], firstResident)
      assert.equal(finalPopulation.residents[1].model.provider, 'setup-b')
      assert.deepEqual(
        finalPopulation.residents.map((r) => r.appearance.look),
        plain(prefab.cast.slice(0, 7).map((p) => p.look))
      )
      const savePath = path.join(home, 'towns', town.id, 'world.json')
      const saved = JSON.parse(await fs.readFile(savePath, 'utf8'))
      const beforeMode = plain(saved.world.game_mode)
      assert.equal(beforeMode.swordholder.seed, 12345)
      assert.equal(beforeMode.swordholder.day_hours, 4)
      const lastCommand = pages
        .at(-1)
        .sent.filter((message) => message.type === 'advance_prefab_setup')
        .at(-1)
      const repeated = await worldQuery(
        current.endpoint,
        { ...lastCommand, request_id: 'repeat-last-step' },
        (message) => message.type === 'prefab_setup_saved'
      )
      assert.equal(repeated.ok, true, JSON.stringify(repeated))
      for (const changed of [{ world_id: 'different-world' }, { setup_id: 'different-setup' }]) {
        const rejected = await worldQuery(
          current.endpoint,
          { ...lastCommand, ...changed, request_id: 'stale-page' },
          (message) => message.type === 'prefab_setup_saved'
        )
        assert.equal(rejected.ok, false, JSON.stringify(rejected))
      }
      const finished = page(prefab, current.endpoint, models)
      pages.push(finished)
      await until(
        () => finished.worldSettings.state(),
        () => diagnostic(finished)
      )
      assert.equal(finished.firstRuns(), 0, '完成标记持久化后刷新不应再开局')
      assert.equal(
        finished.sent.some((m) => m.type === 'advance_prefab_setup'),
        false
      )
      assert.equal((await stateOf(current)).game_mode, 'swordholder')
      const props = (
        await worldQuery(current.endpoint, { type: 'get_props' }, (m) => m.type === 'props')
      ).catalog
      for (const expected of prefab.furnish.place) {
        assert.equal(props.instances.filter((prop) => prop.id === expected.id).length, 1)
      }
      assert.deepEqual(JSON.parse(await fs.readFile(savePath, 'utf8')).world.game_mode, beforeMode)
      const fresh = await createTown(manager, prefab.spec)
      const next = await manager.api(`/${fresh.id}/open`, {})
      const normal = page(prefab, next.endpoint, models)
      pages.push(normal)
      await until(
        () => normal.firstRuns() > 0,
        () => diagnostic(normal)
      )
      normal.start()
      await until(
        () => normal.finished(),
        () => diagnostic(normal)
      )
      assert.equal(normal.finished().length, prefab.players.default)
      assert.equal((await populationOf(next)).residents.length, prefab.players.default)
      assert.equal((await stateOf(next)).ready, true)
    } finally {
      for (const p of pages) p.close()
      if (blockedPath) await fs.rm(blockedPath, { recursive: true, force: true })
      if (manager) assert.equal(await manager.stop(), 0, manager.output())
      await fs.rm(home, { recursive: true, force: true })
    }
  }
)

test('新预制小镇跳过仍交回普通世界观设置，不生成开局计划', () => {
  const p = page()
  try {
    p.connect()
    p.deliver({
      type: 'world_settings',
      state: { world_id: 'skip', revision: 0, ready: false, worldview: '' },
    })
    p.click('跳过')
    assert.equal(p.body.querySelector('#world-setup').open, true)
    assert.equal(
      p.sent.some((m) => m.type === 'begin_prefab_setup'),
      false
    )
  } finally {
    p.close()
  }
})

test(
  '同页预制完成后重置与跳过后重置都重新开局，人数与规则不沿用旧局',
  { timeout: 60000 },
  async () => {
    const home = await fs.mkdtemp(path.join(os.tmpdir(), 'town-prefab-reset-'))
    let manager
    let p
    try {
      manager = await startManager(home)
      const loader = page()
      const prefab = loader.prefab
      loader.close()
      const town = await createTown(manager, prefab.spec)
      const current = await manager.api(`/${town.id}/open`, {})
      p = page(prefab, current.endpoint)
      await until(
        () => p.firstRuns() === 1,
        () => diagnostic(p)
      )
      p.click('−')
      p.click('−')
      p.click('固定种子')
      p.click('4 小时')
      p.start()
      await until(
        () => p.finished(),
        () => diagnostic(p)
      )
      const old = await stateOf(current)
      assert.equal(p.finished().length, 7)
      for (let run = 2; run <= 3; run++) {
        const previousWorld = p.worldSettings.state().world_id
        await worldQuery(
          current.endpoint,
          { type: 'reset_world', request_id: randomUUID() },
          (m) => m.type === 'world_reset'
        )
        await until(
          () => p.worldSettings.state()?.world_id !== previousWorld && p.worldSettings.state(),
          () => diagnostic(p)
        )
        assert.equal(p.firstRuns(), run, '每个新世界必须重新进入开局入口')
        assert.equal(p.body.querySelector('.prefab-setup').hidden, false)
        assert.equal(p.body.querySelector('#world-setup').open, false)
        assert.equal((await populationOf(current)).residents.length, 0)
        if (run === 2) {
          p.click('跳过')
          assert.equal(p.body.querySelector('#world-setup').open, true)
        }
      }
      p.start()
      await until(
        () => p.worldSettings.state()?.ready,
        () => diagnostic(p)
      )
      const next = await stateOf(current)
      assert.notEqual(next.world_id, old.world_id)
      assert.notEqual(next.prefab_setup.id, old.prefab_setup.id)
      assert.equal(next.prefab_setup.plan.selection.players, prefab.players.default)
      assert.equal((await populationOf(current)).residents.length, prefab.players.default)
      assert.equal(next.game_mode, 'swordholder')
      const saved = JSON.parse(
        await fs.readFile(path.join(home, 'towns', town.id, 'world.json'), 'utf8')
      )
      assert.equal(
        saved.world.game_mode.swordholder.day_hours,
        Number(prefab.options.find((o) => o.label === '白天').initial)
      )
    } finally {
      p?.close()
      if (manager) assert.equal(await manager.stop(), 0, manager.output())
      await fs.rm(home, { recursive: true, force: true })
    }
  }
)

test('普通向导完成、跳过和保存中重置都恢复入口，同世界重连保留当前步骤', async () => {
  const p = page(undefined, undefined, [], undefined, undefined, true)
  const settings = (world_id, ready = false) => ({
    type: 'world_settings',
    state: { world_id, revision: 0, ready, worldview: '' },
  })
  const existing = (world_id) =>
    p.deliver({
      type: 'population',
      population: { world_id, residents: [{ id: `${world_id}-resident` }], homes: [] },
    })
  const acceptWorldview = (world) => {
    const command = p.sent.filter((m) => m.type === 'set_worldview').at(-1)
    assert.equal(command.world_id, world)
    p.deliver(settings(world, true))
    p.deliver({
      type: 'world_settings_saved',
      request_id: command.request_id,
      ok: true,
      message: '已保存',
    })
    return command
  }
  try {
    p.connect()
    p.deliver(settings('first'))
    assert.equal(p.guide.isOpen(), true)
    existing('first')
    p.click('开始准备 · 大约一分钟')
    p.click('先不连接，看看小镇')
    p.click('不再请人，下一步')
    p.click('进入小镇')
    acceptWorldview('first')
    await sleep(0)
    assert.equal(p.guide.isOpen(), false, '普通向导确实完成')
    assert.deepEqual(p.finished(), [])

    p.deliver({ type: 'world_reset', clock: '08:00' })
    p.deliver(settings('second'))
    assert.equal(p.firstRuns(), 2)
    assert.equal(p.guide.isOpen(), true)
    p.click('跳过')
    assert.equal(p.body.querySelector('#world-setup').open, true)
    p.deliver({ type: 'world_reset', clock: '08:00' })
    p.deliver(settings('third'))
    assert.equal(p.firstRuns(), 3)
    assert.equal(p.guide.isOpen(), true)
    assert.equal(p.body.querySelector('#world-setup').open, false)

    // 回执已经 resolve，但续跑前收到新世界；旧成功/失败不能关掉新向导或发下一条入住命令。
    existing('third')
    p.click('不再请人，下一步')
    p.click('用默认的')
    const old = acceptWorldview('third')
    p.deliver({ type: 'world_reset', clock: '08:00' })
    p.deliver(settings('fourth'))
    existing('fourth')
    p.click('不再请人，下一步')
    p.click('用默认的')
    await sleep(0)
    assert.equal(p.guide.isOpen(), true)
    assert.equal(
      p.body.querySelectorAll('button').find((b) => b.textContent === '正在准备…').disabled,
      true
    )
    p.deliver({
      type: 'world_settings_saved',
      request_id: old.request_id,
      ok: false,
      message: '旧局失败',
    })
    await sleep(0)
    assert.equal(p.guide.isOpen(), true)
    // 未收到回执也立即作废；新世界可以先收到设置，再 connected，再回读。
    p.disconnect()
    p.deliver(settings('fifth'))
    assert.equal(p.firstRuns(), 4, '离线先收到设置不打开向导')
    p.connect()
    p.deliver(settings('fifth'))
    assert.equal(p.firstRuns(), 5)
    p.disconnect()
    p.connect()
    p.deliver(settings('fifth'))
    assert.equal(p.firstRuns(), 5, '同世界重连不重置选择')
  } finally {
    p.close()
  }
})

test('预制旧回执与已 resolve 的异步续跑都不能污染重置后立即开始的新局', async () => {
  const p = page()
  const settings = (world_id, prefab_setup) => ({
    type: 'world_settings',
    state: { world_id, revision: 0, ready: false, worldview: '', prefab_setup },
  })
  const latestBegin = () => p.sent.filter((m) => m.type === 'begin_prefab_setup').at(-1)
  const receipt = (command, state) => ({
    type: 'prefab_setup_saved',
    request_id: command.request_id,
    ok: true,
    message: '已保存',
    state,
  })
  const running = () => p.body.querySelectorAll('button').find((b) => b.textContent === '正在开局…')
  try {
    p.connect()
    p.deliver(settings('first'))
    p.click('−')
    p.click('固定种子')
    p.disconnect()
    assert.equal(
      p.body.querySelectorAll('button').find((b) => b.textContent === '开始这一局').disabled,
      true
    )
    p.connect()
    assert.equal(
      p.body.querySelectorAll('button').find((b) => b.textContent === '开始这一局').disabled,
      true,
      '重连仍需回读当前世界'
    )
    p.deliver(settings('first'))
    p.start()
    const first = latestBegin()
    const old = {
      id: first.setup_id,
      plan: first.plan,
      next_step: first.plan.steps.length,
      joined: ['旧局居民'],
    }
    // 同一拍收到回执、重置、新设置和新开局点击，Promise 尚未续跑。
    p.deliver(receipt(first, old))
    p.deliver({ type: 'world_reset', clock: '08:00' })
    p.deliver(settings('second'))
    p.start()
    const second = latestBegin()
    await sleep(0)
    assert.equal(second.world_id, 'second')
    assert.notEqual(second.setup_id, first.setup_id)
    assert.equal(second.plan.selection.players, p.prefab.players.default)
    assert.deepEqual(
      second.plan.selection.picks,
      plain(p.prefab.options.map((o) => [o.label, o.initial]))
    )
    assert.equal(running()?.disabled, true)
    assert.equal(p.finished(), undefined)
    assert.equal(p.body.querySelector('.prefab-status').textContent, '正在保存开局选择…')

    // 第二局仍在等回执时重置，旧 waiter 要拒绝，但旧 catch 不能覆盖第三局 running/status。
    p.deliver({ type: 'world_reset', clock: '08:00' })
    p.deliver(settings('third'))
    p.start()
    const third = latestBegin()
    p.deliver(receipt(second, old))
    await sleep(0)
    assert.equal(running()?.disabled, true)
    assert.equal(p.body.querySelector('.prefab-status').textContent, '正在保存开局选择…')
    assert.equal(p.finished(), undefined)
    assert.equal(p.sent.filter((m) => m.type === 'advance_prefab_setup').length, 0)

    // 当前局的有效回执仍能驱动原路径；下一条命令只能使用第三局的 id 和游标。
    p.deliver(receipt(third, { id: third.setup_id, plan: third.plan, next_step: 0, joined: [] }))
    await sleep(0)
    const advance = p.sent.filter((m) => m.type === 'advance_prefab_setup')
    assert.equal(advance.length, 1)
    assert.equal(advance[0].world_id, 'third')
    assert.equal(advance[0].setup_id, third.setup_id)
    assert.equal(advance[0].next_step, 0)
  } finally {
    p.close()
  }
})
