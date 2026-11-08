import { newId } from 'town-shared/ids'
import type { MapEntry } from 'town-shared/mapDocument'
import { PREFABS, type Prefab } from 'town-shared/prefabs/index'
import { creationRequest } from './localCreation'

// 预制小镇在选择小镇页上和「我的小镇」一样是内置小镇：固定编号 prefab-<编号>，不能删，只能重新开始。
// 第一次选中时按固定的建镇参数生成这座岛存好；进镇后第一次出开局设置（town-shared/prefabs/setup.ts）。
// 建镇和「创建小镇」走同一条路：电脑版由管理服务生成，手机应用在页面里生成（localCreation.ts）。

export const prefabTownId = (prefab: Prefab) => `prefab-${prefab.id}`

/** 自带的小镇和预制小镇：带「内置」标签、不能删 */
export const isBuiltinTown = (map: MapEntry) =>
  map.origin === 'builtin' || map.id.startsWith('prefab-')

/** 还没生成的预制小镇 */
export const missingPrefabs = (maps: MapEntry[]) =>
  PREFABS.filter((p) => !maps.some((m) => m.id === prefabTownId(p)))

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
