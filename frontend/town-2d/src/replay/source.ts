// 录像代替 WebSocket：把录下的消息按录像里的时刻交给各面板，和连着世界时收到的一样；
// 命令一律不发（只读：不开世界、不调模型）。录像怎么读见 scripts/replay/reel.mjs，
// 时刻由导演（director.ts）推着走，单位是离这一卷开头的毫秒。
import type { ServerMsg } from 'town-shared/protocol'
import type { Receipt } from 'town-shared/connection'
import { createRosterState, parseSegment } from '../../../../scripts/replay/reel.mjs'

/** 连着世界时名册每 0.1 秒一份；录像里跟上一份一样的名册不写，重演时照这个节奏重发上一份 */
const TICK_MS = 100
/** 页面开局要的消息：跳到哪一刻都先交给面板最近的一份 */
const STATE_TYPES = new Set(['world_settings', 'props', 'population'])

interface Line {
  t: number
  m?: ServerMsg
  k?: unknown
  d?: unknown
}

interface Events {
  message(msg: ServerMsg): void
  connected(recovered: boolean): void
  local(text: string, warning?: boolean): void
}

export type ReplaySource = ReturnType<typeof createReplaySource>

/** segments：一卷里要重演的那几段原文（已解压），按先后排；每段开头都有完整名册 */
export function createReplaySource(segments: string[], events: Events) {
  const lines: Line[] = segments.flatMap((text) => parseSegment(text) as Line[])
  if (!lines.some((l) => l.k)) throw Error('录像里没有完整的名册，放不了')
  let rosters = createRosterState()
  let roster: ServerMsg | null = null
  let next = 0
  /** 最近一次交出名册的时刻 */
  let lastRoster = -Infinity
  const latest = new Map<string, ServerMsg>()

  const read = (line: Line, deliver: boolean) => {
    if (line.m) {
      if (STATE_TYPES.has(line.m.type)) latest.set(line.m.type, line.m)
      if (deliver) events.message(line.m)
      return
    }
    roster = (line.k ? rosters.key(line.k) : rosters.delta(line.d)) as ServerMsg
    if (deliver) {
      events.message(roster)
      lastRoster = line.t
    }
  }

  const source = {
    /** 录像里第一行和最后一行的时刻 */
    span: () => [lines[0].t, lines[lines.length - 1].t] as const,
    /** 跳到 t：从 t 之前最近的完整名册还原到 t，先交出最近的设定、道具和人口，再交出这一刻的名册 */
    seek(t: number) {
      // t 之前最近的完整名册；t 比录像开头还早时用第一份
      let key = -1
      for (let i = 0; i < lines.length && lines[i].t <= t; i++) if (lines[i].k) key = i
      if (key < 0) key = lines.findIndex((l) => l.k)
      rosters = createRosterState()
      latest.clear()
      for (let i = 0; i < key; i++) {
        const m = lines[i].m
        if (m && STATE_TYPES.has(m.type)) latest.set(m.type, m)
      }
      next = key
      while (next < lines.length && (next === key || lines[next].t <= t)) read(lines[next++], false)
      for (const msg of latest.values()) events.message(msg)
      if (roster) events.message(roster)
      lastRoster = Math.max(lines[key].t, t)
    },
    /** 交出到 t 为止的消息；名册有一阵没变时照 0.1 秒一份重发，画面的走动节奏和连着世界时一样 */
    pump(t: number) {
      while (next < lines.length && lines[next].t <= t) read(lines[next++], true)
      if (roster && t - lastRoster >= TICK_MS) {
        lastRoster += Math.floor((t - lastRoster) / TICK_MS) * TICK_MS
        events.message(roster)
      }
    },
    /** 此刻的名册 */
    roster: () => roster,
    /** 给外壳的连接：和 WebSocket 那个同样的几个方法；连上就跳到 start，命令一律不发 */
    connection(start: number) {
      return {
        connect() {
          events.connected(false)
          source.seek(start)
        },
        send() {},
        save(_: unknown, receipt: Receipt) {
          receipt(false, '这是录像，改不了世界')
        },
        resume() {},
        disconnect() {},
      }
    },
  }
  return source
}
