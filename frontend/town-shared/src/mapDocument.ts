import type { Spatial, AssetManifest } from './spatial'
import type { Appearance } from './props/types'
// 地图文档：atlas 提供绘图几何；topology 提供地点名称与物品所属地点；spatial 是三维数据。
// 类型放在共用层，加载逻辑在 town-2d 的 assets 模块。

export interface Atlas {
  canvas: { width: number; height: number }
  regions: {
    id: string
    name: string
    kind: string
    cell_size: number
    cells: [number, number][]
    label_anchor?: [number, number]
  }[]
  nodes: { id: string; kind: string; space: string; x: number; y: number }[]
  edges: {
    id: string
    from_node: string
    to_node: string
    from_locale: string
    to_locale: string
    polyline: [number, number][]
    /** 缺省时后端按 18 个单位算 */
    width?: number
  }[]
  spaces: {
    id: string
    name: string
    /** 房间的功能（建镇模板的种类，如 home、library）；旧地图没有 */
    kind?: string
    bounds: { x: number; y: number; width: number; height: number }
    unfold: { scale: number; offset_x: number; offset_y: number }
    door_outside?: [number, number]
    door_inside_local?: [number, number]
  }[]
  stations: { id: string; space: string; x: number; y: number }[]
  props: {
    id: string
    name: string
    place_name: string
    space: string
    x: number
    y: number
    appearance?: Appearance
  }[]
}

export interface Topology {
  places: { name: string; locale: string; arrival_station: string; residential?: boolean }[]
  locales: { id: string; name: string; kind: string }[]
  /** 处所之间的通道；带「通行」的才真的能走，图上画成门的装饰不算 */
  passages?: { id: string; a: string; b: string; capabilities: string[] }[]
  props: { id: string; locale: string; name?: string; definition?: string }[]
}

export interface MapDocument {
  renderer?: string
  spatial?: Spatial
  assets?: AssetManifest
  views?: { available: string[]; default: string }
  /** 生成的地图带着建镇参数；environment.preset 决定 2D 地图的风格，settlement 为 wild 时路边不立路灯 */
  generation?: {
    spec?: { environment?: { preset?: string }; settlement?: 'town' | 'wild' | 'ring' }
  }

  schema_version: number
  id: string
  name: string
  origin: string
  description: string
  style_id: string
  style_version: number
  content_hash: string
  topology: Topology
  layout: Atlas
}

/** 小镇列表里的一项：由 town-manager 返回，进入游戏时决定连接地址与地图版本。 */
/** 一句话建镇时记下的：玩家那句话、世界观建议、适合住进来的人（一人一句）。存在小镇目录里 */
export interface TownCreation {
  description: string
  worldview: string
  residents: string[]
  /** 从预制小镇开的一局：预制小镇的编号（prefabs/），进镇时出开局设置 */
  prefab?: string
}

export interface MapEntry {
  id: string
  name: string
  version: string
  clientKind: string
  views?: string[]
  description: string
  available: boolean
  endpoint: string
  mapHash: string
  /** 这次打开的凭证：关闭时带上，之后又有页面打开过（比如刷新）就不会被旧页面关掉 */
  lease?: string
  worldId?: string
  running?: boolean
  deletable?: boolean
  origin?: string
  /** 玩到第几天、住了几个人（读存档）；还没开始过的小镇是 null */
  progress?: { day: number; residents: number } | null
  /** 一句话建的小镇才有 */
  creation?: TownCreation | null
}
