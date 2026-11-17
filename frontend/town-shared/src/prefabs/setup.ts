import { button, el } from '../dom'
import { newId } from '../ids'
import type { ModelOption } from '../models/session'
import { lookKey, portraitFor, templateKey } from '../portraits'
import type {
  ClientMsg,
  ModelChoice,
  PhysiologySwitches,
  PrefabSetupPlan,
  PrefabSetupState,
  PrefabSetupStep,
  ServerMsg,
} from '../protocol'
import { segmented, settingRow, switchControl } from '../settings/controls'
import type { ShellPanel } from '../shell/panel'
import type { createWorldSettings } from '../worldSettings'
import type { Prefab, PrefabOption, PrefabPersona } from '.'

// 开局设置：第一次进预制小镇（还没设世界观）时代替开局向导。玩家只改几项：人数、每位选手用的模型、
// 玩法自己的几行（预制小镇的 options：圈的位置、身份、白天长短……）、吃喝睡开不开；
// 世界观、玩法和其余设定由预制小镇写好。
// 开始前先把完整选择与执行计划保存到同一个世界。后端逐步提交副作用与游标，刷新、断线或关闭应用
// 都从已保存的游标继续；页面不凭回执猜测谁已经入住，也不重新生成玩法随机种子。完成后仍保持暂停。
// 跳过就交回原来的首次对话框，像普通小镇一样自己设。

type Waiter = {
  match: (m: ServerMsg) => unknown
  resolve: (v: unknown) => void
  reject: (e: Error) => void
}

/** 固定种子时输入框里先填的数 */
const DEFAULT_SEED = 51

/** 室外行走空间的编号（host 编译地图时定的），开局道具按坐标放时用 */
const OUTDOOR_SPACE = 'town_outdoor'

const ALL_OFF: PhysiologySwitches = {
  fullness: false,
  energy: false,
  water: false,
  health: false,
  weather: false,
}

export function createPrefabSetup(d: {
  send: (msg: ClientMsg) => void
  worldSettings: ReturnType<typeof createWorldSettings>
  /** 能用的模型；没连模型时为空，选手先住下，连上模型后才行动 */
  modelOptions: () => ModelOption[]
  /** 做完时：请进来的居民编号（按号码） */
  onFinish: (joined: string[]) => void
}) {
  const root = el('div', '', 'guide prefab-setup')
  root.hidden = true
  root.setAttribute('role', 'dialog')
  root.setAttribute('aria-label', '开局设置')
  const card = el('section', '', 'guide-card')
  const top = el('div', '', 'guide-top')
  const title = el('b', '', 'prefab-title')
  const skip = button('跳过', () => close(), 'guide-skip')
  top.append(title, skip)
  const body = el('div', '', 'guide-body')
  const foot = el('div', '', 'guide-foot one')
  card.append(top, body, foot)
  root.append(card)
  document.body.append(root)

  let prefab: Prefab | null = null
  let players = 0
  /** 每个号码的模型；null 是没连模型、先住下 */
  let models: (ModelChoice | null)[] = []
  /** 玩法自己那几行选了什么、填的种子（按行名） */
  const picks = new Map<string, string>()
  const seeds = new Map<string, number>()
  let needs = true
  /** 村民库里的名字和头像编号（模板编号 → …），读到之前显示号码 */
  const names = new Map<string, string>()
  const keys = new Map<string, string>()
  let running = false
  let status = ''
  let worldId = ''
  let generation = 0
  let setup: PrefabSetupState | undefined
  let joined: string[] = []
  let joining = -1
  const locked = () => running || !!setup
  const waiters = new Set<Waiter>()
  function waitFor<T>(match: (m: ServerMsg) => T | undefined, ms = 15000) {
    return new Promise<T>((resolve, reject) => {
      const finish = (done: () => void) => {
        clearTimeout(timer)
        waiters.delete(waiter)
        done()
      }
      const waiter: Waiter = {
        match,
        resolve: (v) => finish(() => resolve(v as T)),
        reject: (e) => finish(() => reject(e)),
      }
      const timer = setTimeout(
        () => waiter.reject(Error('小镇没有及时回应，请检查连接后再继续')),
        ms
      )
      waiters.add(waiter)
    })
  }
  function stopWaiting(message: string) {
    for (const w of waiters) w.reject(Error(message))
  }

  function restore(state: PrefabSetupState) {
    if (state.plan.prefab !== prefab?.id) throw Error('存档的开局剧本与当前小镇不一致')
    if (setup?.id === state.id && setup.next_step > state.next_step) return
    setup = state
    const selection = state.plan.selection
    players = selection.players
    models = selection.models
    needs = selection.needs
    picks.clear()
    seeds.clear()
    for (const [key, value] of selection.picks) picks.set(key, value)
    for (const [key, value] of selection.seeds) seeds.set(key, value)
    joined = state.joined
  }

  function slotModel(i: number) {
    if (setup) return models[i] ?? null
    const options = d.modelOptions()
    const chosen = models[i]
    return (
      options.find((o) => o.provider === chosen?.provider && o.model === chosen.model) ??
      options[0] ??
      null
    )
  }

  /** 下拉框里一个模型的取值 */
  const choiceValue = (m: ModelChoice) => `${m.provider}\n${m.model}`
  const parseChoice = (value: string): ModelChoice => {
    const [provider, model] = value.split('\n')
    return { provider, model }
  }
  /** 模型的叫法：可选的模型一个服务一个，写服务名就分得清；有同名的服务才带上模型名 */
  const modelLabel = (choice: ModelChoice, options: ModelOption[]) => {
    const o = options.find((x) => choiceValue(x) === choiceValue(choice))
    if (!o) return `${choice.provider} · ${choice.model}`
    return options.filter((x) => x.name === o.name).length > 1 ? `${o.name} · ${o.model}` : o.name
  }
  function modelSelect(options: ModelOption[]) {
    const select = el('select')
    for (const o of options) {
      const option = el('option', modelLabel(o, options))
      option.value = choiceValue(o)
      select.append(option)
    }
    return select
  }

  // 卡片从上到下：名字和一句话简介；一排选手头像（人数加减只是点亮、熄灭，卡片高度不变）；
  // 三行设置用设定页的同款控件（settings/controls.ts）。不再一组一个框，一屏放得下、不用滚动。
  function render() {
    if (!prefab) return
    const p = prefab
    title.textContent = '开局设置'
    skip.hidden = locked()
    const head = el('header', '', 'prefab-head')
    head.append(el('h2', p.name), el('p', p.description))
    const options = d.modelOptions()
    // 上场的人用了哪几个模型：不止一个时头像下面写各自的模型，都一样就不写（下面「模型」一行写了）
    const used = new Set(
      Array.from({ length: players }, (_, i) => slotModel(i)).map((m) => m && choiceValue(m))
    )
    const rows = el('div', '', 'set-rows prefab-settings')
    rows.append(modelRow(p, options, used), ...p.options.map(optionRow), needsRow(p))
    body.replaceChildren(head, lineup(p, options, used.size > 1), rows)

    const go = button(
      running ? '正在开局…' : setup ? '继续这一局' : '开始这一局',
      () => void start(),
      'primary'
    )
    go.disabled = running || !d.worldSettings.online()
    foot.replaceChildren(...(status ? [el('p', status, 'prefab-status')] : []), go)
  }

  /** 选手：所有号码排成两行，前 players 位亮着；模型不止一个时，点头像给这一位换模型 */
  function lineup(p: Prefab, options: ModelOption[], mixed: boolean) {
    const section = el('section', '', 'prefab-lineup')
    const bar = el('div', '', 'prefab-lineup-bar')
    const stepper = el('div', '', 'prefab-stepper')
    stepper.setAttribute('role', 'group')
    stepper.setAttribute('aria-label', '人数')
    const less = button('−', () => setPlayers(players - 1))
    const more = button('+', () => setPlayers(players + 1))
    less.disabled = locked() || players <= p.players.min
    more.disabled = locked() || players >= p.players.max
    less.setAttribute('aria-label', '少一个人')
    more.setAttribute('aria-label', '多一个人')
    stepper.append(less, el('b', `${players} 人`), more)
    bar.append(el('h3', '选手'), el('small', `${p.players.min}～${p.players.max} 人`), stepper)

    const grid = el('div', '', 'prefab-players')
    const pickable = options.length > 1
    for (let i = 0; i < p.players.max; i++) {
      const id = p.roster[i]
      const name = p.cast?.[i]?.name ?? names.get(id) ?? ''
      const on = i < players
      const cell = el('div', '', 'prefab-player')
      cell.classList.toggle('off', !on)
      cell.classList.toggle('joined', !!joined[i])
      cell.classList.toggle('joining', running && joining === i)
      const face = el('span', '', 'prefab-face')
      const look = p.cast?.[i]?.look
      const key = look ? lookKey(look) : keys.get(id)
      const url = key ? portraitFor(key) : undefined
      if (url) {
        const img = el('img')
        img.src = url
        img.alt = ''
        face.append(img)
      } else face.textContent = name.slice(0, 1)
      face.append(el('i', joined[i] ? '✓' : String(i + 1), 'prefab-no'))
      cell.append(face, el('b', name || `${i + 1} 号`))
      const model = on ? slotModel(i) : null
      // 各用各的时名字下面写用哪个模型；没上场的空着，格子一样高
      if (mixed) cell.append(el('small', model ? modelLabel(model, options) : ''))
      if (pickable && model) {
        // 整格盖一个透明下拉框：点头像就弹出统一样式的模型列表
        const select = modelSelect(options)
        select.className = 'prefab-pick'
        select.value = choiceValue(model)
        select.disabled = locked()
        select.setAttribute('aria-label', `${name || `${i + 1} 号`}用的模型`)
        select.onchange = () => {
          models[i] = parseChoice(select.value)
          render()
        }
        cell.append(select)
      }
      grid.append(cell)
    }
    section.append(bar, grid)
    return section
  }

  /** 模型：只有一个时写出来；多个时下拉框一次给所有人换，各用各的时框里写「各用各的」 */
  function modelRow(p: Prefab, options: ModelOption[], used: Set<string | null>) {
    if (setup) {
      const choice = slotModel(0)
      const label = used.size > 1 ? '各用各的' : choice ? modelLabel(choice, options) : '未连接'
      return settingRow('模型', '沿用开局时保存的选择', el('span', label, 'prefab-model'))
    }
    if (!options.length)
      return settingRow(
        '模型',
        '还没连接模型：选手先住下，连上后才会行动',
        el('span', '未连接', 'ui-chip')
      )
    if (options.length === 1)
      return settingRow(
        '模型',
        '所有选手都用它',
        el('span', `${options[0].name} · ${options[0].model}`, 'prefab-model')
      )
    const select = modelSelect(options)
    if (used.size > 1) {
      const mixed = el('option', '各用各的')
      mixed.value = ''
      mixed.hidden = true
      select.prepend(mixed)
      select.value = ''
    } else select.value = [...used][0] ?? choiceValue(options[0])
    select.disabled = locked()
    select.setAttribute('aria-label', '所有选手用的模型')
    select.onchange = () => {
      const choice = parseChoice(select.value)
      // 已经住进来的人模型定了，不跟着换
      models = Array.from({ length: p.players.max }, (_, i) =>
        joined[i] ? (models[i] ?? slotModel(i)) : choice
      )
      render()
    }
    return settingRow('模型', '点头像可以给某一位单独换', select)
  }

  /** 玩法自己的一行：分段选择；选到要种子的取值时下面多一个种子输入框 */
  function optionRow(o: PrefabOption) {
    const picked = picks.get(o.label) ?? o.initial
    const seg = segmented(
      o.label,
      o.choices.map(({ value, label }) => ({ value, label })),
      (value) => {
        if (picked === value) return
        picks.set(o.label, value)
        render()
        if (value === o.seed) body.querySelector<HTMLInputElement>('.prefab-seed')?.select()
      }
    )
    seg.set(picked)
    seg.el.querySelectorAll('button').forEach((b) => (b.disabled = locked()))
    const hint = o.choices.find((c) => c.value === picked)?.hint ?? ''
    const row = settingRow(o.label, hint, seg.el)
    if (o.seed && picked === o.seed) {
      const line = el('label', '', 'set-row-desc prefab-seed-line')
      const input = el('input', '', 'prefab-seed')
      input.type = 'number'
      input.min = '1'
      input.max = '4294967295'
      input.value = String(seeds.get(o.label) ?? DEFAULT_SEED)
      input.disabled = locked()
      input.onchange = () => {
        const n = Math.floor(Number(input.value))
        if (Number.isFinite(n) && n >= 1 && n <= 4294967295) seeds.set(o.label, n)
        input.value = String(seeds.get(o.label) ?? DEFAULT_SEED)
      }
      line.append('种子', input)
      row.querySelector('.set-row-text')?.append(line)
    }
    return row
  }

  function needsRow(p: Prefab) {
    const toggle = switchControl('吃喝睡', (on) => {
      needs = on
      render()
    })
    toggle.set(needs)
    toggle.el.disabled = locked()
    return settingRow('吃喝睡', needs ? p.needsHint.on : p.needsHint.off, toggle.el)
  }

  function setPlayers(n: number) {
    if (!prefab) return
    players = Math.min(prefab.players.max, Math.max(prefab.players.min, n))
    render()
  }

  /** 固化具体执行计划，后续版本或其他页面不能重解释一局已经选好的参数。 */
  function plan(p: Prefab): PrefabSetupPlan {
    const chosenModels = Array.from({ length: players }, (_, i) => {
      const model = slotModel(i)
      return model ? { provider: model.provider, model: model.model } : null
    })
    const steps: PrefabSetupStep[] = [
      { kind: 'worldview', text: p.worldview },
      { kind: 'physiology', switches: needs ? p.needs : ALL_OFF },
    ]
    if (p.climate) steps.push({ kind: 'climate', climate: p.climate })
    if (p.weather) steps.push({ kind: 'weather', weather: p.weather })
    for (const id of p.furnish?.remove ?? []) steps.push({ kind: 'remove_prop', id })
    for (const { id, definition, locale, near } of p.furnish?.place ?? [])
      steps.push({
        kind: 'place_prop',
        instance: { id, definition, locale },
        ...(near && { near: { space: OUTDOOR_SPACE, position: near } }),
      })
    if (p.limits) steps.push({ kind: 'limits', limits: p.limits })
    for (let i = 0; i < players; i++) {
      const model = chosenModels[i]
      const persona = p.cast?.[i]
      steps.push({
        kind: 'join',
        template_id: p.roster[i],
        ...(model && { model }),
        ...(persona && { persona: personaFields(persona), look: persona.look }),
      })
    }
    const choice = p.options.reduce((c, o) => {
      const value = picks.get(o.label) ?? o.initial
      const seed = o.seed && value === o.seed ? (seeds.get(o.label) ?? DEFAULT_SEED) : null
      return o.apply(c, value, seed)
    }, p.gameMode)
    steps.push({ kind: 'game_mode', choice })
    return {
      prefab: p.id,
      selection: {
        players,
        models: chosenModels,
        needs,
        picks: p.options.map((o) => [o.label, picks.get(o.label) ?? o.initial]),
        seeds: p.options.map((o) => [o.label, seeds.get(o.label) ?? DEFAULT_SEED]),
      },
      steps,
    }
  }

  function personaFields({ look: _look, ...fields }: PrefabPersona) {
    return fields
  }

  // 一次开局绑定不可变代次与世界编号。取消等待还不够：已 resolve 的旧 Promise 也可能尚未续跑。
  function assertCurrent(run: number, world: string) {
    if (run !== generation || world !== worldId || d.worldSettings.state()?.world_id !== world)
      throw Error('世界已更换，旧开局已取消')
  }

  async function submit(msg: ClientMsg & { request_id: string }, run: number, world: string) {
    assertCurrent(run, world)
    const reply = waitFor((m) =>
      (m.type === 'prefab_setup_saved' || m.type === 'error') && m.request_id === msg.request_id
        ? m
        : undefined
    )
    d.send(msg)
    const result = await reply
    assertCurrent(run, world)
    if (result.type === 'prefab_setup_saved' && result.state) restore(result.state)
    if (result.type === 'error' || !result.ok) throw Error(result.message)
  }

  function changeWorld(world: string) {
    generation++
    stopWaiting('世界已更换，旧开局已取消')
    worldId = world
    prefab = null
    setup = undefined
    joined = []
    joining = -1
    running = false
    status = ''
    players = 0
    models = []
    picks.clear()
    seeds.clear()
    root.hidden = true
  }

  const labels: Record<PrefabSetupStep['kind'], string> = {
    worldview: '正在写世界观…',
    physiology: '正在设定吃喝睡…',
    climate: '正在定气候…',
    weather: '正在设定开局天气…',
    remove_prop: '正在布置地图上的东西…',
    place_prop: '正在布置地图上的东西…',
    limits: '正在调额度…',
    join: '正在请选手入住…',
    game_mode: '正在打开玩法…',
  }

  async function start() {
    const p = prefab
    if (!p || running || !d.worldSettings.online()) return
    const run = generation
    const world = worldId
    running = true
    status = '正在保存开局选择…'
    render()
    try {
      assertCurrent(run, world)
      const current = d.worldSettings.state()
      if (!current || current.world_id !== worldId) throw Error('世界已更换，请刷新页面')
      if (current.prefab_setup) restore(current.prefab_setup)
      if (!setup) {
        await submit(
          {
            type: 'begin_prefab_setup',
            request_id: newId(),
            setup_id: newId(),
            world_id: world,
            expected_revision: current.revision,
            plan: plan(p),
          },
          run,
          world
        )
      }
      assertCurrent(run, world)
      while (setup && setup.next_step < setup.plan.steps.length) {
        const step = setup.plan.steps[setup.next_step]
        status = labels[step.kind]
        joining = step.kind === 'join' ? joined.length : -1
        render()
        await submit(
          {
            type: 'advance_prefab_setup',
            request_id: newId(),
            setup_id: setup.id,
            world_id: world,
            next_step: setup.next_step,
          },
          run,
          world
        )
        assertCurrent(run, world)
      }
      running = false
      root.hidden = true
      d.onFinish(joined)
    } catch (error) {
      if (run !== generation) return
      running = false
      joining = -1
      status = `${error instanceof Error ? error.message : String(error)}。连接恢复后可继续这一局，已保存的选择和进度不会重做。`
      render()
    }
  }

  function close() {
    if (locked()) return
    root.hidden = true
    // 跳过：交回首次对话框，像普通小镇一样自己设
    d.worldSettings.skipFirstRun()
  }

  const unsubscribeWorld = d.worldSettings.subscribe(() => {
    if (!root.hidden) render()
  })

  const panel: ShellPanel = {
    disconnected() {
      generation++
      stopWaiting('连接断开，开局结果以重新连接后的存档为准')
      running = false
      joining = -1
      status = '连接断开，重新连接后可继续这一局。'
      if (!root.hidden) render()
    },
    dispose() {
      unsubscribeWorld()
      changeWorld('')
    },
    handleMsg(m: ServerMsg) {
      if (m.type === 'world_reset') changeWorld('')
      if (m.type === 'world_settings' && m.state.world_id !== worldId) changeWorld(m.state.world_id)
      if (
        m.type === 'world_settings' &&
        m.state.world_id === worldId &&
        prefab &&
        m.state.prefab_setup
      ) {
        restore(m.state.prefab_setup)
        if (!root.hidden) render()
      }
      if (m.type === 'resident_library') {
        for (const t of m.templates) {
          names.set(t.template_id, t.name)
          keys.set(t.template_id, templateKey(t))
        }
        if (!root.hidden) render()
      }
      for (const w of [...waiters]) {
        const value = w.match(m)
        if (value !== undefined) {
          w.resolve(value)
        }
      }
    },
  }

  return {
    panel,
    /** 打开这个预制小镇的开局设置 */
    open(p: Prefab) {
      const world = d.worldSettings.state()?.world_id ?? ''
      if (world !== worldId || (prefab && prefab.id !== p.id)) changeWorld(world)
      if (!prefab) {
        prefab = p
        players = p.players.default
        needs = p.needsDefault
      }
      const saved = d.worldSettings.state()?.prefab_setup
      if (saved) {
        restore(saved)
        status = '上次开局尚未完成，继续时会沿用已保存的选择。'
      }
      root.hidden = false
      d.send({ type: 'get_resident_library', filter: { kind: 'builtin' } })
      render()
    },
    /** 模型配置变了（连上了新模型）：重画选择框 */
    refresh() {
      if (!root.hidden && !running) render()
    },
  }
}
