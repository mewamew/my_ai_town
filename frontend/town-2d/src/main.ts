import type { MapEntry } from 'town-shared/mapDocument'
import { startGameShell } from 'town-shared/gameShell'
import { musicWorldOf } from 'town-shared/audio/scene'
import { $ } from 'town-shared/dom'
import { loadDocument, dataFromDocument } from './assets'
import { createMapRenderer } from './mapRenderers'

/** 加载 HD-2D 地图，启动居民、化身与共用界面。 */
export async function startGame(selectedMap: MapEntry) {
  const doc = await loadDocument(selectedMap.id, selectedMap.mapHash)
  const data = dataFromDocument(doc)
  const map = await createMapRenderer(doc, $('map'), {
    persistence: { townId: selectedMap.id, mapHash: selectedMap.mapHash },
    data,
  })
  const shell = startGameShell(selectedMap, map, data.topology, data.decorate, {
    musicWorld: musicWorldOf(data.theme.id, doc.generation?.spec?.settlement),
  })
  window.addEventListener(
    'pagehide',
    () => {
      shell.dispose()
      map.dispose()
    },
    { once: true }
  )
}
