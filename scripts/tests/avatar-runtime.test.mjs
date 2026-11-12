import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { APPEARANCE_SET } from '../mapgen/budget.mjs'
import { walkingHarness } from './avatar-input-support.mjs'
import { createTown, startManager } from './support.mjs'

test('rotated view maps WASD and stick input to world directions while click routes stay in world space', () => {
  const sent = []
  let turned = true
  const map = {
    avatarSupported: true,
    walkDirection: ([x, y]) => (turned ? [y, -x] : [x, y]),
  }
  const h = walkingHarness(
    () => {},
    () => true,
    {
      map,
      getState: () => ({
        epoch: 'owned',
        speed: 1,
        actor: {
          busy: false,
          locus: { at: { kind: 'free', space: 'outside', position: [0, 0] } },
        },
      }),
      getWorld: () => 'world',
      getHolds: () => [],
      owned: () => true,
      mapVisible: () => true,
      send: (msg) => sent.push(Array.from(msg.direction)),
      execute: async () => true,
      targets: () => [],
      toggleBag() {},
      showToast() {},
    }
  )
  const latest = () => sent.at(-1).map((v) => (v === 0 ? 0 : v))
  try {
    h.event(h.window, 'keydown', { code: 'KeyW' })
    assert.deepEqual(latest(), [-1, 0])
    turned = false
    h.frame()
    assert.deepEqual(latest(), [0, -1], '按住键时也读取最新镜头方向')
    h.event(h.window, 'keyup', { code: 'KeyW' })
    assert.deepEqual(latest(), [0, 0])
    turned = true
    h.navigation.stick([1, 0])
    assert.deepEqual(latest(), [0, -1])
    h.navigation.stick(null)
    assert.deepEqual(latest(), [0, 0])
    map.onAvatarWalkTo({ space: 'outside', position: [10, 0] })
    h.navigation.walk.tick()
    assert.deepEqual(latest(), [1, 0], '点击路线不能被镜头重复旋转')
  } finally {
    h.abort.abort()
  }
})

test('actual WASD input adapter drives a generated world and saves its stopped position', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'town-avatar-runtime-'))
  const m = await startManager(root)
  let ws, input
  try {
    const saved = await createTown(m, {
      schema_version: 2,
      name: '化身输入验收',
      seed: 94,
      appearance_set: APPEARANCE_SET,
      environment: { preset: 'coastal-village', vegetation: 'medium' },
      places: [
        { kind: 'cafe', count: 1, size: 'medium' },
        { kind: 'plaza', count: 1, size: 'small' },
      ],
      resources: 'normal-life',
      constraints: [],
    })
    const town = await m.api(`/${saved.id}/open`, {})
    ws = new WebSocket(town.endpoint)
    await new Promise((resolve, reject) => {
      ws.onopen = resolve
      ws.onerror = reject
    })
    const wait = (predicate) =>
      new Promise((resolve, reject) => {
        const handler = (e) => {
          const v = JSON.parse(e.data)
          if (predicate(v)) {
            clearTimeout(timer)
            ws.removeEventListener('message', handler)
            resolve(v)
          }
        }
        const timer = setTimeout(() => {
          ws.removeEventListener('message', handler)
          reject(Error('化身测试未收到回包'))
        }, 5000)
        ws.addEventListener('message', handler)
      })
    const request = (message, predicate) => {
      const result = wait(predicate)
      ws.send(JSON.stringify(message))
      return result
    }
    const settings = (
      await request({ type: 'get_world_settings' }, (v) => v.type === 'world_settings')
    ).state
    assert.ok(
      (
        await request(
          {
            type: 'set_worldview',
            request_id: 'setup',
            world_id: settings.world_id,
            expected_revision: settings.revision,
            text: '独立的化身移动验收场景。',
          },
          (v) => v.type === 'world_settings_saved'
        )
      ).ok
    )
    const entered = await request(
      {
        type: 'avatar',
        world_id: settings.world_id,
        request_id: 'enter',
        epoch: '',
        sequence: 1,
        command: {
          kind: 'enter',
          name: '验收玩家',
          appearance: { marker: '我', color: '#387963' },
        },
      },
      (v) => v.type === 'avatar_result'
    )
    assert.ok(entered.ok, JSON.stringify(entered))
    const s = entered.state,
      origin = s.actor.locus.at.position
    ws.send(JSON.stringify({ type: 'set_speed', request_id: 'set-speed', speed: 1 }))
    await wait((v) => v.type === 'roster' && v.speed === 1)
    assert.equal(s.client_positions, undefined)
    let sequence = 0
    input = walkingHarness((direction) => {
      ws.send(
        JSON.stringify({
          type: 'avatar_input',
          world_id: s.world_id,
          epoch: s.epoch,
          sequence: ++sequence,
          navigation_revision: s.navigation_revision,
          direction,
        })
      )
    })
    const moving = wait(
      (v) =>
        v.type === 'avatar_state' &&
        Math.hypot(...v.state.actor.locus.at.position.map((n, i) => n - origin[i])) > 0.1
    )
    input.event(input.window, 'keydown', { code: 'KeyW' })
    const pulse = setInterval(() => {
      input.frame()
    }, 50)
    let moved
    try {
      moved = await moving
    } finally {
      clearInterval(pulse)
      input.input.stop()
    }
    assert.ok(moved.state.actor.present)
    const stopped = await wait((v) => v.type === 'avatar_state')
    const p = stopped.state.actor.locus.at.position
    // 输入框与中文组合事件也走同一个输入模块，不会再发送非零方向。
    input.document.activeElement = new input.Element()
    input.event(input.document, 'compositionstart')
    input.event(input.window, 'keydown', { code: 'KeyD' })
    input.frame()
    await new Promise((r) => setTimeout(r, 400))
    const after = await wait((v) => v.type === 'avatar_state')
    assert.deepEqual(after.state.actor.locus.at.position, p)
    const leave = await request(
      {
        type: 'avatar',
        world_id: s.world_id,
        request_id: 'leave',
        epoch: s.epoch,
        sequence: 2,
        command: { kind: 'leave' },
      },
      (v) => v.type === 'avatar_result' && v.request_id === 'leave'
    )
    assert.ok(leave.ok)
    assert.equal(leave.state.actor.present, false)
    input.abort.abort()
    ws.close()
    await m.api(`/${saved.id}/close`, {})
    const disk = JSON.parse(await fs.readFile(path.join(root, 'towns', saved.id, 'world.json')))
    assert.equal(disk.world.actors.player_avatar.locus.at.kind, 'offstage')
    assert.deepEqual(disk.world.actors.player_avatar.avatar.last_locus.at.position, p)
    assert.equal(Object.keys(disk.population.residents).length, 0)
  } finally {
    input?.abort.abort()
    ws?.close()
    await m.stop()
    await fs.rm(root, { recursive: true, force: true })
  }
})
