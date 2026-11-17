// 管理服务（crates/manager）带着真的世界进程：小镇的保存、打开、互相隔离、重启后接着来、删除，和只开一个小镇的规矩。
// 建镇要求、预览改名、建镇说明的校验在 crates/manager/tests/http.rs，不在这里重复。
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { createReadStream } from 'node:fs'
import { once } from 'node:events'
import { seal } from '../mapgen/document.mjs'
import { createTown, draftTown, root as source, startManager, worldQuery } from './support.mjs'
const BUILTIN_TOWNS = ['default-town', 'spring-valley', 'broken-towers']
const spec = {
  name: '隔离地图',
  seed: 51,
  style_id: 'svg-town-v1',
  places: [
    { kind: 'home', count: 2, size: 'medium' },
    { kind: 'library', count: 1, size: 'medium' },
    { kind: 'plaza', count: 1, size: 'medium' },
  ],
  constraints: [],
  resources: 'normal-life',
}
const alive = (pid) => {
  try {
    process.kill(pid, 0)
    return true
  } catch {
    return false
  }
}
test('saved towns open in isolated worlds, come back after a restart, and are deleted only with their world closed', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'town-manager-test-'))
  let m
  try {
    const retired = path.join(root, 'towns/old-3d-town')
    await fs.mkdir(retired, { recursive: true })
    const oldMap = JSON.stringify(
      seal({
        ...JSON.parse(await fs.readFile(path.join(source, 'data/maps/2d-town/map.json'))),
        renderer: 'authored-island-v1',
        views: { available: ['3d'], default: '3d' },
      })
    )
    const oldSave = '{"legacy":"preserve resident memories"}'
    await fs.writeFile(path.join(retired, 'map.json'), oldMap)
    await fs.writeFile(path.join(retired, 'world.json'), oldSave)
    // 访达复制文件夹的默认名：编号不合规的目录不进列表，也不挡住别的小镇
    await fs.mkdir(path.join(root, 'towns/default-town 2'))
    // 这一段同时开两个小镇，验证两个世界互相隔离；产品里同时只运行一个
    m = await startManager(root, { maxRunning: 2 })
    const { api } = m
    // 随应用发的内置小镇第一次运行就都在，排在最前；旧 3D 存档不进列表
    assert.deepEqual(
      (await api('')).towns.map((t) => [t.id, t.deletable]),
      BUILTIN_TOWNS.map((id) => [id, false])
    )
    assert.deepEqual((await api('')).towns[0].views, ['2d'])
    for (const [route, body] of [
      ['/old-3d-town/map', undefined],
      ['/old-3d-town/open', {}],
      ['/old-3d-town/delete', {}],
    ])
      await assert.rejects(api(route, body), /3D 版本/)
    assert((await api('')).towns.every((town) => town.running === false))

    // 保存的就是页面生成、交上来的那一版；同一次保存同时到两遍只建一个小镇
    const { document, draft } = await draftTown(m, spec)
    const body = {
      draft_id: draft.id,
      expected_version: draft.version,
      request_id: 'save-exact-preview',
      creation: { description: '海边的小渔村', worldview: '这里的人想靠海吃饭。', residents: [] },
    }
    const [saved, repeated] = await Promise.all([api('/save', body), api('/save', body)])
    assert.equal(saved.id, repeated.id)
    assert.equal(saved.mapHash, document.content_hash)
    const [a, aa] = await Promise.all([api(`/${saved.id}/open`, {}), api(`/${saved.id}/open`, {})])
    assert.equal(a.endpoint, aa.endpoint)
    // 进镇时带着一句话建镇的世界观建议
    assert.equal(a.creation.worldview, '这里的人想靠海吃饭。')
    assert.equal((await api('')).towns.find((town) => town.id === a.id).running, true)
    const b = await api('/default-town/open', {})
    assert.notEqual(a.worldId, b.worldId)
    assert.notEqual(a.endpoint, b.endpoint)
    const query = (town, command, type) =>
      worldQuery(town.endpoint, command, (msg) => msg.type === type)
    const wa = (await query(a, { type: 'get_world_settings' }, 'world_settings')).state
    assert.equal(wa.ready, false)
    const ack = await query(
      a,
      {
        type: 'set_worldview',
        request_id: 'setup',
        world_id: wa.world_id,
        expected_revision: wa.revision,
        text: '隔离生成的小镇，村民自由生活。',
      },
      'world_settings_saved'
    )
    assert.equal(ack.ok, true)
    assert.equal(
      (await query(b, { type: 'get_world_settings' }, 'world_settings')).state.ready,
      false
    )
    const cross = await query(
      b,
      {
        type: 'set_worldview',
        request_id: 'wrong',
        world_id: wa.world_id,
        expected_revision: 0,
        text: '跨世界写入',
      },
      'world_settings_saved'
    )
    assert.equal(cross.ok, false)
    const preview = (
      await query(a, { type: 'preview_resident_join', template_id: 'builtin_ashu' }, 'join_preview')
    ).preview
    const joined = await query(
      a,
      {
        type: 'join_resident',
        op_id: 'join-a',
        world_id: a.worldId,
        template_id: 'builtin_ashu',
        template_version: preview.template_version,
        name: preview.name,
        home: preview.home,
      },
      'resident_joined'
    )
    assert.equal(joined.outcome.ok, true)
    const id = joined.outcome.resident_id
    const population = (await query(a, { type: 'get_population' }, 'population')).population
    assert.equal(population.residents.length, 1)
    assert.equal(
      (await query(b, { type: 'get_population' }, 'population')).population.residents.length,
      0
    )
    // Dynamic books are real persisted world content, with independent durable display slots.
    const created = await query(
      a,
      {
        type: 'content',
        request_id: 'new-book',
        world_id: a.worldId,
        command: {
          operation: 'create',
          id: 'user:map-book',
          locale: 'library_1',
          title: '地图里的新书',
          author: '测试作者',
          text: '这本书只属于这个运行世界。',
        },
      },
      'prop_result'
    )
    assert.equal(created.ok, true)
    const instances = (await query(a, { type: 'get_props' }, 'props')).catalog.instances.map(
      (p) => ({ id: p.id, locale: p.locale })
    )
    const positions = await api(`/${a.id}/positions`, {
      map_hash: a.mapHash,
      instances,
    })
    const reordered = await api(`/${a.id}/positions`, {
      map_hash: a.mapHash,
      instances: [...instances].reverse(),
    })
    assert.deepEqual(
      positions.positions.find((p) => p.id === 'user:map-book'),
      reordered.positions.find((p) => p.id === 'user:map-book')
    )
    const filesBefore = await fs.readFile(path.join(root, 'towns', a.id, 'map.json'), 'utf8')
    // 管理服务退出前让两个世界都保存退出，没有一个超时被强制结束
    assert.equal(await m.stop(), 0, m.output())
    m = await startManager(root)
    assert.equal((await m.api('')).towns.length, BUILTIN_TOWNS.length + 1)
    let restored = await m.api(`/${a.id}/open`, {})
    assert.equal(restored.worldId, a.worldId)
    assert.equal(
      (await query(restored, { type: 'get_population' }, 'population')).population.residents[0].id,
      id
    )
    assert(
      (await query(restored, { type: 'get_props' }, 'props')).catalog.instances.some(
        (p) => p.id === 'user:map-book'
      )
    )
    await m.api(`/${a.id}/close`, {})
    const closed = (await m.api('')).towns.find((town) => town.id === a.id)
    assert.equal(closed.running, false)
    // 列表带着存档停在哪：选镇页据此画时钟牌、头像和那一刻的天色
    assert.equal(closed.progress.residents, 1)
    assert.equal(closed.progress.cast[0].template_id, 'builtin_ashu')
    assert.equal(closed.progress.minutes, Math.floor(closed.progress.minutes))
    assert.equal(typeof closed.progress.weather, 'string')
    const reopened = await m.api(`/${a.id}/open`, {})
    assert.equal(reopened.worldId, a.worldId)
    assert.notEqual(reopened.endpoint, restored.endpoint)
    restored = reopened
    await query(restored, { type: 'reset_world', request_id: 'reset-world' }, 'world_reset')
    const afterReset = (await query(restored, { type: 'get_world_settings' }, 'world_settings'))
      .state
    assert.notEqual(afterReset.world_id, a.worldId)
    assert.equal(afterReset.ready, false)
    assert.equal(
      (await query(restored, { type: 'get_population' }, 'population')).population.residents.length,
      0
    )
    assert.equal(await fs.readFile(path.join(root, 'towns', a.id, 'map.json'), 'utf8'), filesBefore)
    await assert.rejects(m.api(`/${a.id}/map?hash=wrong`), /地图已变化/)
    await assert.rejects(
      worldQuery(
        restored.endpoint.replace(/session=.*/, 'session=incorrect'),
        null,
        (msg) => msg.type === 'world_identity',
        2000
      )
    )
    // 删除运行中的生成地图：先关掉它的世界再删目录；内置的删不掉，别的存档不变，重启后也不再出现
    const protectedFile = path.join(root, 'towns/default-town/map.json')
    const protectedBefore = await fs.readFile(protectedFile, 'utf8')
    await assert.rejects(m.api('/default-town/delete', {}), /内置地图/)
    const { pid } = JSON.parse(
      await fs.readFile(path.join(root, 'towns', a.id, 'host-ready.json'), 'utf8')
    )
    assert(alive(pid))
    await m.api(`/${a.id}/delete`, {})
    assert(!alive(pid), '删除前要先关掉这个小镇的世界')
    assert.equal(
      (await m.api('')).towns.some((town) => town.id === a.id),
      false
    )
    await assert.rejects(fs.access(path.join(root, 'towns', a.id)), { code: 'ENOENT' })
    await assert.rejects(m.api(`/${a.id}/open`, {}), /不存在/)
    assert.equal(await fs.readFile(protectedFile, 'utf8'), protectedBefore)
    assert.equal(await m.stop(), 0, m.output())
    m = await startManager(root)
    assert.equal((await m.api('')).towns.length, BUILTIN_TOWNS.length)
    assert.equal(await fs.readFile(path.join(retired, 'map.json'), 'utf8'), oldMap)
    assert.equal(await fs.readFile(path.join(retired, 'world.json'), 'utf8'), oldSave)
  } finally {
    await m?.stop()
    await fs.rm(root, { recursive: true, force: true })
  }
})
test('the built-in town shows the shipped name while its stored map stays untouched', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'town-builtin-name-'))
  let m
  try {
    const shipped = JSON.parse(await fs.readFile(path.join(source, 'data/maps/2d-town/map.json')))
    const stored = JSON.stringify(seal({ ...shipped, name: '旧名称', description: '旧简介' }))
    const dir = path.join(root, 'towns/default-town')
    await fs.mkdir(dir, { recursive: true })
    await fs.writeFile(path.join(dir, 'map.json'), stored)
    await fs.writeFile(path.join(dir, 'receipt.json'), '{"origin":"builtin"}')
    m = await startManager(root)
    const { towns } = await m.api('')
    assert.deepEqual([towns[0].name, towns[0].description], [shipped.name, shipped.description])
    // 地图摘要是存档的身份，更新显示名不能改动已有的副本。
    assert.equal(await fs.readFile(path.join(dir, 'map.json'), 'utf8'), stored)
  } finally {
    await m?.stop()
    await fs.rm(root, { recursive: true, force: true })
  }
})
test('only one town runs at a time: entering another town closes the open one, the displaced page does not take it back by itself, a stale close from a reloaded page does not, two towns opened at once leave one running', async () => {
  // 上次没正常退出、小镇还开着时，进另一个小镇不能报「请关闭其他小镇」，而是先把开着的那个存档关掉再换过去
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'town-manager-limit-'))
  let m
  try {
    m = await startManager(root)
    const { api } = m
    const settings = async (town) =>
      (
        await worldQuery(
          town.endpoint,
          { type: 'get_world_settings' },
          (msg) => msg.type === 'world_settings'
        )
      ).state
    const town = await createTown(m, spec)
    const first = await api('/default-town/open', {})
    const state = await settings(first)
    const saved = await worldQuery(
      first.endpoint,
      {
        type: 'set_worldview',
        request_id: 'before-switch',
        world_id: state.world_id,
        expected_revision: state.revision,
        text: '换走之前写下的世界观',
      },
      (msg) => msg.type === 'world_settings_saved'
    )
    assert.equal(saved.ok, true)
    await api(`/${town.id}/open`, {})
    // 只看这两个小镇（别的内置小镇一直没开）
    const running = async () =>
      Object.fromEntries(
        (await api('')).towns
          .filter((t) => t.id === 'default-town' || t.id === town.id)
          .map((t) => [t.id, t.running])
      )
    assert.deepEqual(await running(), { 'default-town': false, [town.id]: true })
    // 被挤掉的页面断线后自动重开：不抢回来（不然两个页面来回互挤），告诉它是另一个页面进了别的小镇
    await assert.rejects(api('/default-town/open', { automatic: true }), /另一个页面打开了/)
    assert.deepEqual(await running(), { 'default-town': false, [town.id]: true })
    // 换回默认小镇：刚才那个被关掉，默认小镇从存档里接着来
    const back = await api('/default-town/open', {})
    assert.deepEqual(await running(), { 'default-town': true, [town.id]: false })
    assert.equal((await settings(back)).worldview, '换走之前写下的世界观')
    // 刷新：新页面先打开，旧页面离开时的关闭后到。旧凭证的关闭不算数，新页面的小镇照常开着
    const reloaded = await api('/default-town/open', {})
    assert.notEqual(reloaded.lease, back.lease)
    assert.equal((await api('/default-town/close', { lease: back.lease })).closed, false)
    assert.equal((await running())['default-town'], true)
    assert.equal((await api('/default-town/close', { lease: reloaded.lease })).closed, true)
    assert.equal((await running())['default-town'], false)
    // 两个页面同时进两个小镇：正在启动的也占着名额，两个请求一个接一个地办，后办的把先开的关掉
    await Promise.all([api('/default-town/open', {}), api(`/${town.id}/open`, {})])
    const open = Object.entries(await running()).filter(([, on]) => on)
    assert.equal(open.length, 1, JSON.stringify(open))
  } finally {
    await m?.stop()
    await fs.rm(root, { recursive: true, force: true })
  }
})
// 关闭回归只用隔离目录和固定回复模型；用真实磁盘故障走 HTTP → manager → host → 存档。
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
const readJson = async (file) => JSON.parse(await fs.readFile(file, 'utf8'))
const roster = (town, command = null) =>
  worldQuery(town.endpoint, command, (msg) => msg.type === 'roster')
async function advancingTown(manager, root) {
  const town = await manager.api('/default-town/open', {})
  const state = (
    await worldQuery(
      town.endpoint,
      { type: 'get_world_settings' },
      (m) => m.type === 'world_settings'
    )
  ).state
  const result = await worldQuery(
    town.endpoint,
    {
      type: 'set_worldview',
      request_id: 'close-setup',
      world_id: town.worldId,
      expected_revision: state.revision,
      text: '关闭失败时不能丢掉还没有存盘的时间。',
    },
    (m) => m.type === 'world_settings_saved'
  )
  assert.equal(result.ok, true)
  await worldQuery(
    town.endpoint,
    { type: 'set_speed', request_id: 'run', speed: 1 },
    (m) => m.type === 'roster' && m.speed === 1
  )
  const dir = path.join(root, 'towns/default-town')
  const file = path.join(dir, 'world.json')
  const previous = await readJson(file)
  await worldQuery(
    town.endpoint,
    null,
    (m) => m.type === 'roster' && m.sim_minutes > previous.world.minutes + 0.5
  )
  const { pid } = await readJson(path.join(dir, 'host-ready.json'))
  return { town, file, pid, previous }
}
async function waitGone(pid) {
  const deadline = Date.now() + 20000
  while (alive(pid) && Date.now() < deadline) await delay(50)
  assert.equal(alive(pid), false, `测试世界 ${pid} 没有按时退出`)
}

test('safe close: failed saves preserve the same live world, block switching, and retry saves the latest progress', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'town-safe-close-'))
  let m
  let tmp
  try {
    m = await startManager(root)
    const { town, file, pid, previous } = await advancingTown(m, root)
    tmp = file + '.tmp'
    await fs.mkdir(tmp)
    const before = await roster(town)
    await assert.rejects(m.api('/default-town/close', { lease: town.lease }), /保存失败.*仍在运行/)
    await assert.rejects(m.api('/spring-valley/open', {}), /保存失败.*仍在运行/)
    const towns = (await m.api('')).towns
    assert.equal(towns.find((t) => t.id === 'default-town').running, true)
    assert.equal(towns.find((t) => t.id === 'spring-valley').running, false)
    assert.equal(alive(pid), true)
    const reopened = await m.api('/default-town/open', { automatic: true })
    assert.equal(reopened.endpoint, town.endpoint)
    assert.equal(reopened.worldId, town.worldId)
    const after = await roster(town)
    assert(after.sim_minutes > before.sim_minutes)
    assert.deepEqual(await readJson(file), previous)
    await fs.rm(tmp, { recursive: true })
    assert.equal((await m.api('/default-town/close', { lease: reopened.lease })).closed, true)
    assert.equal(alive(pid), false)
    const saved = await readJson(file)
    assert(saved.world.minutes >= after.sim_minutes)
    const resumed = await m.api('/default-town/open', {})
    assert.equal(resumed.worldId, town.worldId)
    assert.equal((await roster(resumed)).sim_minutes, saved.world.minutes)
    assert.equal((await m.api('/default-town/close', {})).closed, true)
    assert.equal(await m.stop(), 0, m.output())
  } finally {
    if (tmp) await fs.rm(tmp, { recursive: true, force: true })
    await m?.stop()
    await fs.rm(root, { recursive: true, force: true })
  }
})

test(
  'safe close: a blocked disk times out without killing the world, then a late failure and a repaired retry are distinguished',
  { skip: process.platform === 'win32' },
  async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'town-close-timeout-'))
    let m
    let tmp
    let drain
    let blocked
    try {
      m = await startManager(root)
      const { town, file, pid } = await advancingTown(m, root)
      tmp = file + '.tmp'
      assert.equal(spawnSync('mkfifo', [tmp]).status, 0)
      await assert.rejects(m.api('/default-town/close', {}), /未确认保存并退出.*仍保留世界进程/)
      assert.equal(alive(pid), true)
      assert.equal((await m.api('')).towns.find((t) => t.id === town.id).running, true)
      await assert.rejects(m.api('/default-town/open', {}), /仍在保存关闭/)
      // 阻塞写端已经找到 FIFO；先改名再放开，保证最终 rename 找不到 .tmp 而失败。
      // macOS 的 FIFO fsync 可能成功，不能单靠特殊文件制造失败。晚到回执仍属于原请求。
      blocked = tmp + '.blocked'
      await fs.rename(tmp, blocked)
      drain = createReadStream(blocked)
      const drained = once(drain, 'close')
      drain.resume()
      await drained
      await assert.rejects(m.api('/default-town/close', {}), /保存失败.*仍在运行/)
      assert.equal(alive(pid), true)
      await fs.rm(blocked)
      const latest = await roster(town)
      assert.equal((await m.api('/default-town/close', {})).closed, true)
      assert((await readJson(file)).world.minutes >= latest.sim_minutes)
      assert.equal(await m.stop(), 0, m.output())
    } finally {
      drain?.destroy()
      if (blocked) await fs.rm(blocked, { force: true })
      if (tmp) await fs.rm(tmp, { recursive: true, force: true })
      await m?.stop()
      await fs.rm(root, { recursive: true, force: true })
    }
  }
)

test('safe close: an unexpected host exit is not forgotten by status reads or reported as a successful close', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'town-close-crash-'))
  let m
  try {
    m = await startManager(root)
    const { town, pid } = await advancingTown(m, root)
    process.kill(pid, 'SIGKILL')
    await delay(100)
    assert.equal((await m.api('')).towns.find((t) => t.id === town.id).running, false)
    await assert.rejects(m.api('/default-town/close', { lease: town.lease }), /意外退出.*无法确认/)
    // 玩家明确重开才恢复盘上的检查点，并替换异常实例的登记。
    const reopened = await m.api('/default-town/open', {})
    assert.equal(reopened.worldId, town.worldId)
    assert.equal((await m.api('/default-town/close', {})).closed, true)
    assert.equal(await m.stop(), 0, m.output())
  } finally {
    await m?.stop()
    await fs.rm(root, { recursive: true, force: true })
  }
})

test('safe close: manager shutdown reports failure and parent loss only gets a bounded rescue, never a hidden orphan', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'town-close-parent-'))
  let m
  let tmp
  let pid
  try {
    m = await startManager(root)
    const running = await advancingTown(m, root)
    pid = running.pid
    tmp = running.file + '.tmp'
    await fs.mkdir(tmp)
    assert.equal(await m.stop(), 1)
    assert.match(m.output(), /保存失败/)
    // 父进程已经真的退出，持续写失败不能无限挂着世界；此边界不能承诺保存未提交进度。
    await waitGone(pid)
    assert.deepEqual(await readJson(running.file), running.previous)
  } finally {
    if (tmp) await fs.rm(tmp, { recursive: true, force: true })
    await m?.stop()
    if (pid && alive(pid)) process.kill(pid, 'SIGKILL')
    await fs.rm(root, { recursive: true, force: true })
  }
})

test(
  'safe close: killing the manager during a blocked save also ends the orphan within the rescue deadline',
  { skip: process.platform === 'win32' },
  async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'town-close-killed-parent-'))
    let m
    let pid
    try {
      m = await startManager(root)
      const running = await advancingTown(m, root)
      pid = running.pid
      const tmp = running.file + '.tmp'
      assert.equal(spawnSync('mkfifo', [tmp]).status, 0)
      const closing = m.api('/default-town/close', {}).catch((error) => error)
      // 主循环已经阻塞在 FIFO 写入，不能自行观察父进程退出。
      await delay(500)
      const managerPid = (await readJson(path.join(root, 'manager-ready.json'))).pid
      process.kill(managerPid, 'SIGKILL')
      assert((await closing) instanceof Error)
      await waitGone(pid)
      assert.deepEqual(await readJson(running.file), running.previous)
    } finally {
      await m?.stop()
      if (pid && alive(pid)) process.kill(pid, 'SIGKILL')
      await fs.rm(root, { recursive: true, force: true })
    }
  }
)

test('home settings save a key only into the data root config, read back only its mask, and cannot delete a service', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'town-models-'))
  const repoConfig = ['config/providers.json', 'config/credentials.json'].map((p) =>
    path.join(source, p)
  )
  const before = await Promise.all(repoConfig.map((p) => fs.readFile(p, 'utf8').catch(() => null)))
  let m
  try {
    m = await startManager(root)
    const { api } = m
    const key = 'sk-home-settings-0123456789'
    const kept = (await api('/models')).providers.map(({ id, name, base_url }) => ({
      id,
      name,
      base_url,
    }))
    const added = { id: 'home-test', name: '首页测试', base_url: 'http://127.0.0.1:9/v1' }
    const saved = await api('/models', {
      active: { provider: added.id, model: 'm' },
      providers: [...kept, added],
      keys: [{ provider: added.id, api_key: key }],
    })
    const read = await api('/models')
    for (const reply of [saved, read]) {
      assert.equal(reply.providers.find((p) => p.id === added.id)?.key_mask, 'sk-h…6789')
      assert.ok(!JSON.stringify(reply).includes(key), '回读里不能有明文密钥')
    }
    // 密钥只进数据目录的 credentials.json，不进 providers.json，也不碰仓库里的配置
    const config = path.join(root, 'config')
    assert.ok((await fs.readFile(path.join(config, 'credentials.json'), 'utf8')).includes(key))
    assert.ok(!(await fs.readFile(path.join(config, 'providers.json'), 'utf8')).includes(key))
    // 首页只能加和改：少带一个服务商就拒绝，免得用着它的村民找不到模型
    await assert.rejects(api('/models', { active: null, providers: kept, keys: [] }), /不能删除/)
    assert.ok((await api('/models')).providers.some((p) => p.id === added.id))
  } finally {
    await m?.stop()
    await fs.rm(root, { recursive: true, force: true })
  }
  const after = await Promise.all(repoConfig.map((p) => fs.readFile(p, 'utf8').catch(() => null)))
  assert.deepEqual(after, before)
})
test('model settings saved at the same moment from the home page and an open town keep a readable file and every key', async () => {
  // 首页的设定和小镇里的设定存的是同一对文件：几次保存同时到，配置不能写坏，每次带来的密钥都要留下
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'town-models-race-'))
  let m
  try {
    m = await startManager(root)
    const { api } = m
    const town = await api('/default-town/open', {})
    const kept = (await api('/models')).providers
      .filter((p) => p.id !== 'builtin')
      .map(({ id, name, base_url }) => ({ id, name, base_url }))
    const config = path.join(root, 'config')
    const ids = Array.from({ length: 8 }, (_, i) => `race-${i}`)
    for (let round = 0; round < 5; round++) {
      const key = (i) => `sk-race-${round}-${i}-0123456789`
      // 服务商表都一样，只有自己那一项的名字长短不同，写出的文件长短跟着变；密钥只带自己那一项
      const body = (i) => ({
        active: null,
        providers: [
          ...kept,
          ...ids.map((id, j) => ({
            id,
            name: j === i ? 'x'.repeat(4 + 9 * i) : id,
            base_url: 'http://127.0.0.1:9/v1',
          })),
        ],
        keys: [{ provider: ids[i], api_key: key(i) }],
      })
      // 双数从首页存，单数从开着的小镇里存
      await Promise.all(
        ids.map(async (_, i) => {
          if (i % 2 === 0) return api('/models', body(i))
          const request_id = `race-${round}-${i}`
          const ack = await worldQuery(
            town.endpoint,
            { type: 'set_model_config', request_id, ...body(i) },
            (msg) => msg.type === 'config_saved' && msg.request_id === request_id
          )
          assert.equal(ack.ok, true, ack.message)
        })
      )
      const saved = JSON.parse(await fs.readFile(path.join(config, 'providers.json'), 'utf8'))
      assert.deepEqual(
        saved.providers.map((p) => p.id),
        [...kept.map((p) => p.id), ...ids]
      )
      const keys = JSON.parse(await fs.readFile(path.join(config, 'credentials.json'), 'utf8'))
      assert.deepEqual(
        ids.map((id) => keys[id]),
        ids.map((_, i) => key(i))
      )
    }
  } finally {
    await m?.stop()
    await fs.rm(root, { recursive: true, force: true })
  }
})
