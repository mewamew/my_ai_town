import type { MapDocument, MapEntry } from 'town-shared/mapDocument'
import type { ConnectionEvents, GameConnection } from 'town-shared/connection'
import { startGameShell } from 'town-shared/gameShell'
import { musicWorldOf } from 'town-shared/audio/scene'
import { $ } from 'town-shared/dom'
import { loadDocument, dataFromDocument } from './assets'
import { createMapRenderer } from './mapRenderers'

/** 加载 HD-2D 地图，启动居民、化身与共用界面。重演录像时（replay/boot.ts）地图由调用方递进来、
 *  连接换成录像，也不把道具坐标交给小镇服务保存。 */
export async function startGame(
  selectedMap: MapEntry,
  replay?: {
    document: MapDocument
    connection: (events: ConnectionEvents) => GameConnection
  }
) {
  const doc = replay?.document ?? (await loadDocument(selectedMap.id, selectedMap.mapHash))
  const data = dataFromDocument(doc)
  const map = await createMapRenderer(doc, $('map'), {
    persistence: replay ? undefined : { townId: selectedMap.id, mapHash: selectedMap.mapHash },
    data,
  })
  const shell = startGameShell(selectedMap, map, data.topology, data.decorate, {
    musicWorld: musicWorldOf(data.theme.id, doc.generation?.spec?.settlement),
    connection: replay?.connection,
  })
  window.addEventListener(
    'pagehide',
    () => {
      shell.dispose()
      map.dispose()
    },
    { once: true }
  )
  return map
}
