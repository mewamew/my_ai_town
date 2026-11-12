// 在电脑上读小镇目录里的录像：几卷、每卷的段、地图，以及一卷里谁在什么时候说了什么、想了什么。
// 拍摄工具（shoot.mjs）和读剧本（script.mjs）共用；一行行怎么还原见 reel.mjs。
import fs from 'node:fs'
import path from 'node:path'
import zlib from 'node:zlib'
import { dataRoot } from '../data-root.mjs'
import { FORMATS, createRosterState, messages, parseSegment, segmentFiles } from './reel.mjs'

/** 小镇目录：AI_TOWN_HOME（或系统默认的数据目录）下的 towns/<小镇> */
export function townDir(town) {
  if (!/^[a-z0-9-]+$/.test(town)) throw Error(`小镇编号不对：${town}`)
  return path.join(dataRoot(), 'towns', town)
}

/** 小镇名（建镇说明里的）；没有时用编号 */
export function townName(town) {
  try {
    const map = JSON.parse(fs.readFileSync(path.join(townDir(town), 'map.json'), 'utf8'))
    return map.name ?? map.layout?.name ?? town
  } catch {
    return town
  }
}

/** 录下的几卷，新的在前：{ id, header } */
export function listReels(town) {
  const root = path.join(townDir(town), 'recordings')
  if (!fs.existsSync(root)) return []
  return fs
    .readdirSync(root)
    .filter((id) => id !== 'maps' && fs.existsSync(path.join(root, id, 'header.json')))
    .map((id) => ({
      id,
      header: JSON.parse(fs.readFileSync(path.join(root, id, 'header.json'), 'utf8')),
    }))
    .sort((a, b) => b.header.started_at - a.header.started_at)
}

/** 读一卷：说明和每一段（原文、第一行的时刻）；reel 不给时读最新的一卷 */
export function loadReel(town, reel) {
  const root = path.join(townDir(town), 'recordings')
  const id = reel ?? listReels(town)[0]?.id
  if (!id) throw Error(`小镇 ${town} 还没有录像`)
  const dir = path.join(root, id)
  const header = JSON.parse(fs.readFileSync(path.join(dir, 'header.json'), 'utf8'))
  if (!FORMATS.includes(header.format))
    throw Error(`录像格式 ${header.format} 读不了（只认 ${FORMATS.join('、')}）`)
  const segments = segmentFiles(fs.readdirSync(dir)).map((name) => {
    const raw = fs.readFileSync(path.join(dir, name))
    const text = (name.endsWith('.gz') ? zlib.gunzipSync(raw) : raw).toString('utf8')
    const first = text.slice(0, text.indexOf('\n'))
    return { name, text, start: first ? JSON.parse(first).t : 0 }
  })
  return { id, dir, header, segments }
}

/** 录像时的地图（按摘要另存的那份） */
export function loadMap(town, hash) {
  const file = path.join(townDir(town), 'recordings', 'maps', `${hash}.json.gz`)
  return JSON.parse(zlib.gunzipSync(fs.readFileSync(file)).toString('utf8'))
}

/** 覆盖 [from, to] 这段时间要的那几段：从 from 所在的那一段起（每段开头都有完整名册） */
export function segmentsFor(reel, from, to) {
  const list = reel.segments
  let first = 0
  for (let i = 0; i < list.length; i++) if (list[i].start <= from) first = i
  let last = first
  while (last + 1 < list.length && list[last + 1].start <= to) last++
  return list.slice(first, last + 1)
}

/** 一卷里按先后的消息 {t, msg}（名册是完整的） */
export function* reelMessages(reel) {
  const state = createRosterState()
  for (const segment of reel.segments) yield* messages(parseSegment(segment.text), state)
}

/** 小镇时钟「D2 05:42」→ 分钟 */
export function clockMinutes(clock) {
  const match = /^D(\d+)\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(clock.trim())
  if (!match) throw Error(`时钟写法不对：${clock}（像 D2 05:42 这样）`)
  return (
    (Number(match[1]) - 1) * 1440 +
    Number(match[2]) * 60 +
    Number(match[3]) +
    Number(match[4] ?? 0) / 60
  )
}

/** 录像里小镇时间到了 clock 的那一刻（毫秒）；录像里没有这个时间时报错 */
export function timeOfClock(reel, clock) {
  const minutes = clockMinutes(clock)
  for (const { t, msg } of reelMessages(reel))
    if (msg.type === 'roster' && msg.sim_minutes >= minutes) return t
  throw Error(`这一卷录到 ${reel.header.to_clock} 为止，没有 ${clock}`)
}

/** 开录以前就说过、想过的，名册里还挂着；比这一卷开头早这么多分钟的不算进剧本 */
const STALE_MINUTES = 5

/**
 * 一卷里的「剧本」：谁在什么时候说了什么（speech）、想了什么（thought）、世界日志（event）。
 * 每条 { t, clock, kind, who, text }；台词按 chat_id+seq、想法按正文去重，只记新出现的那一刻。
 */
export function scriptOf(reel) {
  const beats = []
  const said = new Set()
  const thought = new Map()
  const names = new Map()
  let opened = null
  for (const { t, msg } of reelMessages(reel)) {
    if (msg.type === 'event') {
      if (msg.kind !== 'model')
        beats.push({
          t,
          clock: msg.clock,
          kind: 'event',
          who: msg.actor?.name ?? '',
          text: msg.text,
        })
      continue
    }
    if (msg.type !== 'roster') continue
    opened ??= msg.sim_minutes - STALE_MINUTES
    for (const locale of msg.locales)
      for (const m of locale.members) {
        names.set(m.id, m.name)
        if (m.speech) {
          const key = `${m.speech.chat_id}/${m.speech.seq}`
          if (!said.has(key) && m.speech.at >= opened)
            beats.push({
              t,
              clock: msg.clock,
              kind: 'speech',
              who: m.name,
              id: m.id,
              text: m.speech.text,
            })
          said.add(key)
        }
        if (m.thought && thought.get(m.id) !== m.thought.text) {
          if (m.thought.sim_minutes >= opened)
            beats.push({
              t,
              clock: msg.clock,
              kind: 'thought',
              who: m.name,
              id: m.id,
              text: m.thought.text,
            })
          thought.set(m.id, m.thought.text)
        }
      }
  }
  return { beats, names }
}
