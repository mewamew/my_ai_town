import { newId } from 'town-shared/ids'
import type { MapEntry } from 'town-shared/mapDocument'
import { PREFABS, type Prefab } from 'town-shared/prefabs/index'
import { creationRequest } from './localCreation'

// 预制小镇在选择小镇页上和「我的小镇」一样是内置小镇：固定编号 prefab-<编号>，不能删，只能重新开始。
// 第一次选中时按固定的建镇参数生成这座岛存好；进镇后第一次出开局设置（town-shared/prefabs/setup.ts）。
// 建镇和「创建小镇」走同一条路：在页面里生成，交管理服务校验后保存（localCreation.ts）。

export const prefabTownId = (prefab: Prefab) => `prefab-${prefab.id}`

/** 自带的小镇和预制小镇：带「内置」标签、不能删 */
export const isBuiltinTown = (map: MapEntry) =>
  map.origin === 'builtin' || map.id.startsWith('prefab-')

/** 「剧本」那一排：固定按登记的顺序，生成过的换成存好的小镇，第一次选中生成后不挪位置
 *  （管理服务按名字的编码排，生成前后会换位置，鼠标下面的那张就变了）；登记里已经没有的剧本小镇排在最后 */
export const prefabRow = (maps: MapEntry[]): (MapEntry | Prefab)[] => [
  ...PREFABS.map((prefab) => maps.find((m) => m.id === prefabTownId(prefab)) ?? prefab),
  ...maps.filter(
    (m) => m.id.startsWith('prefab-') && !PREFABS.some((p) => prefabTownId(p) === m.id)
  ),
]

/** 生成预制小镇的岛并存成内置小镇，返回小镇编号 */
export async function generatePrefab(prefab: Prefab) {
  const request = creationRequest()
  const draft = await request<{ id: string; version: string }>('/preview', {
    request_id: newId(),
    spec: prefab.spec,
  })
  const saved = await request<{ id: string }>('/save', {
    draft_id: draft.id,
    expected_version: draft.version,
    request_id: newId(),
    town_id: prefabTownId(prefab),
    name: prefab.name,
    creation: {
      description: prefab.description,
      worldview: prefab.worldview,
      residents: [],
      prefab: prefab.id,
    },
  })
  return saved.id
}
