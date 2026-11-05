import { errorText } from 'town-shared/format'
import { newId } from 'town-shared/ids'
import type { MapEntry } from 'town-shared/mapDocument'
import { PREFABS, type Prefab } from 'town-shared/prefabs/index'
import { creationRequest } from './localCreation'

// 选择小镇页上的预制小镇：点「开一局」按固定的建镇参数生成这座岛，存成新的一局（名字带「第几局」），
// 再像「进入游戏」一样打开、停住世界进游戏页；第一次进镇出开局设置（town-shared/prefabs/setup.ts）。
// 建镇和「创建小镇」走同一条路：电脑版由管理服务生成，手机应用在页面里生成（localCreation.ts）。

export function prefabEntries(deps: {
  /** 已有的小镇：数一数这个预制小镇开过几局 */
  maps: () => MapEntry[]
  /** 状态行 */
  status: (text: string) => void
  /** 打开、停住世界并进游戏页；出错时抛出 */
  enter: (id: string) => Promise<void>
}) {
  let busy = false
  // 和小镇列表里的条目同一个样子，放在内置小镇下面；不另写说明
  function entry(prefab: Prefab) {
    const b = document.createElement('button')
    b.type = 'button'
    b.className = 'map-option prefab-entry'
    b.title = prefab.description
    const text = document.createElement('span'),
      name = document.createElement('strong'),
      status = document.createElement('span')
    name.textContent = prefab.name
    status.className = 'map-option-status'
    status.textContent = '开一局'
    text.append(name, status)
    b.append(text)
    b.onclick = () => void start(prefab, b)
    return b
  }
  return () => PREFABS.map(entry)

  async function start(prefab: Prefab, b: HTMLButtonElement) {
    if (busy) return
    busy = true
    b.disabled = true
    try {
      const request = creationRequest()
      deps.status(`正在生成${prefab.name}…`)
      await request('/options')
      const draft = await request<{ id: string; version: string }>('/preview', {
        request_id: newId(),
        spec: prefab.spec,
      })
      const round = 1 + deps.maps().filter((m) => m.creation?.prefab === prefab.id).length
      const saved = await request<{ id: string }>('/save', {
        draft_id: draft.id,
        expected_version: draft.version,
        request_id: newId(),
        name: `${prefab.name} · 第 ${round} 局`,
        creation: {
          description: prefab.description,
          worldview: prefab.worldview,
          residents: [],
          prefab: prefab.id,
        },
      })
      deps.status('岛建好了，正在进入…')
      await deps.enter(saved.id)
    } catch (error) {
      deps.status(errorText(error))
      busy = false
      b.disabled = false
    }
  }
}
