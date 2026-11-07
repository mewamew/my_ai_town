// 重演模式的开局：game.html?map=<小镇>&replay=1。不开世界：地图和录像由拍摄脚本递进来
// （window.__replay.provide），页面照常建画面，只是连接换成录像，遥控挂在 window.director。
import type { MapDocument, MapEntry } from 'town-shared/mapDocument'
import type { ServerMsg } from 'town-shared/protocol'
import { installClock } from './clock'
import { createDirector, type Director } from './director'
import { createReplaySource } from './source'

/** 拍摄脚本递进来的东西 */
export interface ReplayInput {
  /** 小镇名，标签页标题用 */
  name: string
  /** 录像时的地图（recordings/maps/<摘要>.json.gz 解开的） */
  map: MapDocument
  /** 要重演的那几段原文（已解压），按先后排 */
  segments: string[]
  /** 连上以后先跳到哪（录像毫秒） */
  start: number
}

declare global {
  interface Window {
    __replay?: { provide(input: ReplayInput): void }
    director?: Director
  }
}

export async function startReplay(id: string) {
  // 先接管时钟：之后建的画面、气泡和定时器都认它
  const clock = installClock()
  const input = await new Promise<ReplayInput>((resolve) => {
    window.__replay = { provide: resolve }
  })
  const entry: MapEntry = {
    id,
    name: input.name,
    version: '',
    clientKind: '2d',
    description: '',
    available: true,
    endpoint: '',
    mapHash: input.map.content_hash,
    creation: null,
  }
  let forward: ((msg: ServerMsg) => void) | null = null
  let connected: ((recovered: boolean) => void) | null = null
  const source = createReplaySource(input.segments, {
    message: (msg) => forward?.(msg),
    connected: (recovered) => connected?.(recovered),
    local: () => {},
  })
  const { startGame } = await import('../main')
  const map = await startGame(entry, {
    document: input.map,
    connection: (events) => {
      forward = events.message
      connected = events.connected
      return source.connection(input.start)
    },
  })
  const director = createDirector(map, source, clock)
  director.seek(input.start)
  await director.ready
  window.director = director
}
