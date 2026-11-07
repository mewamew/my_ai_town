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
