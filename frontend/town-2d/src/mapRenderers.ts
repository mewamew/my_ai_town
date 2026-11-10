import type { GameMap } from 'town-shared/gameMap'
import type { MapDocument } from 'town-shared/mapDocument'
import { dataFromDocument } from './assets'
import type { Ground } from './map/pixel/terrain'
import { TownMap } from './render'

export function assertHd2dDocument(document: MapDocument) {
  if (
    document.renderer ||
    (document.views?.default && document.views.default !== '2d') ||
    document.views?.available?.some((view) => view !== '2d')
  )
    throw new Error('此地图属于已停用的 3D 版本，存档保留，请使用 HD-2D 小镇')
}

export interface TownMapSetup {
  /** 有它才把运行期道具坐标交给小镇服务保存 */
  persistence?: { townId: string; mapHash: string }
  /** 非致命问题（坐标保存失败）的提示 */
  notify?: (message: string) => void
  /** 调用方已经按这份文档算好的地面（建镇预览先用它画缩略图） */
  ground?: Ground
  /** 调用方已经用 dataFromDocument 取过这份文档时传进来，地图和外壳用同一份数据 */
  data?: ReturnType<typeof dataFromDocument>
}

export function createTownMap(
  document: MapDocument,
  container: HTMLElement,
  setup: TownMapSetup = {}
): GameMap {
  assertHd2dDocument(document)
  const data = setup.data ?? dataFromDocument(document)
  return new TownMap({
    atlas: data.atlas,
    topology: data.topology,
    container,
    appearanceFor: data.appearanceFor,
    persistence: setup.persistence,
    spatial: document.spatial,
    notify: setup.notify ?? ((message) => console.error(message)),
    theme: data.theme,
    ground: setup.ground,
    furnished: document.origin === 'builtin',
  })
}

/** 正式游戏与建镇预览都使用 HD-2D。 */
export async function createMapRenderer(
  document: MapDocument,
  container: HTMLElement,
  setup: TownMapSetup = {}
): Promise<GameMap> {
  assertHd2dDocument(document)
  return createTownMap(document, container, setup)
}
