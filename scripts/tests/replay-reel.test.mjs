// 录像的读法。host 集成测试（crates/host/tests/recording.rs）开着录像跑一段，把收起的那一卷和页面当时
// 收到的消息放进 target/tmp/recording-sample；这里用重演画面和拍摄工具共用的 scripts/replay/reel.mjs
// 读回来：页面收到的名册要原样、按先后出现在录像里（跟上一份一样的不写，所以比的是去掉连续重复以后的），
// 广播的世界日志一条不少。
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import zlib from 'node:zlib'
import { root } from './support.mjs'
import { FORMAT, createRosterState, messages, parseSegment, segmentFiles } from '../replay/reel.mjs'

const target = path.resolve(root, process.env.CARGO_TARGET_DIR ?? 'target')
const sample = path.join(target, 'tmp/recording-sample')

/** 键按字母序的 JSON：两边各自的键序不同也能比 */
const canonical = (value) =>
  JSON.stringify(value, (_, v) =>
    v && typeof v === 'object' && !Array.isArray(v)
      ? Object.fromEntries(
          Object.keys(v)
            .sort()
            .map((k) => [k, v[k]])
        )
      : v
  )
const distinct = (list) => list.filter((item, i) => i === 0 || item !== list[i - 1])

test('录下的一卷读回来，页面当时收到的名册和世界日志一份不差', () => {
  assert.ok(
    fs.existsSync(sample),
    `缺少 ${sample}：先运行 cargo test -p host --test host recording`
  )
  const dir = path.join(sample, 'reel')
  const header = JSON.parse(fs.readFileSync(path.join(dir, 'header.json'), 'utf8'))
  assert.equal(header.format, FORMAT)
  const recorded = []
  const state = createRosterState()
  for (const name of segmentFiles(fs.readdirSync(dir))) {
    const raw = fs.readFileSync(path.join(dir, name))
    const text = (name.endsWith('.gz') ? zlib.gunzipSync(raw) : raw).toString('utf8')
    for (const item of messages(parseSegment(text), state)) recorded.push(item.msg)
  }
  const received = fs
    .readFileSync(path.join(sample, 'received.jsonl'), 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line))
  const rosters = (list) => distinct(list.filter((m) => m.type === 'roster').map(canonical))
  const reel = rosters(recorded)
  const live = rosters(received)
  assert.ok(live.length >= 10, `页面只收到 ${live.length} 份不同的名册`)
  const from = reel.indexOf(live[0])
  assert.ok(from >= 0, '录像里找不到页面收到的第一份名册')
  assert.deepEqual(reel.slice(from, from + live.length), live)
  const events = (list) => list.filter((m) => m.type === 'event').map(canonical)
  const recordedEvents = events(recorded)
  let at = 0
  for (const event of events(received)) {
    at = recordedEvents.indexOf(event, at)
    assert.ok(at >= 0, `录像里少了这条世界日志：${event}`)
  }
  const last = reel.at(-1) && JSON.parse(reel.at(-1))
  assert.equal(header.to_clock, last.clock)
})

test('格式 3 以前的录像：名册里带着整份角色卡细节，画面要的两个记号照当时的找法补上', () => {
  const agent = {
    state: 'waiting',
    reason: '',
    goals: [
      { id: 'g1', status: 'active', updated_at: 10 },
      { id: 'g2', status: 'completed', updated_at: 30 },
      { id: 'g3', status: 'active', updated_at: 20 },
    ],
    // 参与者第一位是自己才算自己被拒
    interactions: [
      { id: 'i2', status: 'declined', participants: ['小禾', '阿树'] },
      { id: 'i1', status: 'declined', participants: ['阿树', '小禾'] },
    ],
    results: [],
    memories: [],
  }
  const state = createRosterState()
  const member = (roster) => roster.locales[0].members[0]
  const first = member(
    state.key({
      type: 'roster',
      locales: [{ locale: 'plaza', members: [{ id: 'a', name: '阿树', resident_agent: agent }] }],
    })
  )
  assert.deepEqual(first.resident_agent.latest_goal, { id: 'g3', updated_at: 20 })
  assert.equal(first.resident_agent.declined_invitation, 'i1')
  assert.equal(first.resident_agent.memories, agent.memories, '原来的列表留着')
  // 变化里换了整份 Agent 状态：记号跟着重找，没有了的不留
  const next = member(
    state.delta({
      m: {
        a: {
          resident_agent: {
            ...agent,
            goals: [{ id: 'g4', status: 'active', updated_at: 40 }],
            interactions: [],
          },
        },
      },
    })
  )
  assert.deepEqual(next.resident_agent.latest_goal, { id: 'g4', updated_at: 40 })
  assert.equal(next.resident_agent.declined_invitation, undefined)
})

test('重演跳到录像里任意一刻，交出的名册和顺着放到那一刻的一样', async () => {
  const { createReplaySource } = await import('../../frontend/town-2d/src/replay/source.ts')
  const dir = path.join(sample, 'reel')
  const segments = segmentFiles(fs.readdirSync(dir)).map((name) => {
    const raw = fs.readFileSync(path.join(dir, name))
    return (name.endsWith('.gz') ? zlib.gunzipSync(raw) : raw).toString('utf8')
  })
  const play = (texts, start) => {
    const got = []
    const source = createReplaySource(texts, {
      message: (msg) => msg.type === 'roster' && got.push(msg),
      connected: () => {},
      local: () => {},
    })
    source.seek(start)
    return { source, got }
  }
  const check = (texts) => {
    const [first, last] = play(texts, 0).source.span()
    // 顺着放：每 50 毫秒交一次，记下每一刻的名册
    const forward = play(texts, first)
    const at = new Map()
    for (let t = first; t <= last; t += 50) {
      forward.source.pump(t)
      at.set(t, forward.got.at(-1))
    }
    // 跳到中间各处：拿到的名册和顺着放到那里时的一样
    const times = [...at.keys()]
    for (const t of times.filter((_, i) => i % 7 === 3))
      assert.equal(canonical(play(texts, t).got.at(-1)), canonical(at.get(t)), `跳到 ${t} 毫秒`)
    return at
  }
  const at = check(segments)
  // 录像长了，中间会有别的完整名册：在中间插一份，跳转要从它之前最近的那份接起
  const lines = segments.flatMap((text) => text.split('\n').filter(Boolean))
  const middle = Math.floor(lines.length / 2)
  const t = JSON.parse(lines[middle]).t
  const before = [...at.keys()].filter((k) => k <= t).at(-1)
  lines.splice(middle, 0, JSON.stringify({ t, k: at.get(before) }))
  check([lines.join('\n') + '\n'])
})
