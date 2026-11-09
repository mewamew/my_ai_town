import type { Spatial, AssetManifest } from './spatial'
import type { Appearance } from './props/types'
// 地图文档：atlas 提供绘图几何；topology 提供地点名称与物品所属地点；spatial 是三维数据。
// 类型放在共用层，加载逻辑在 town-2d 的 assets 模块。

/** 岛内的一片水：多边形，或者带宽度的折线（河）；都是地图坐标 */
export type IslandWater =
  { polygon: [number, number][] } | { line: [number, number][]; width: number }

/**
 * 画好的海岸（手绘的内置地图才有）：陆地底稿交给引擎扭曲、冲刷出小湾和礁石，岛内的河、湖、港湾等冲刷完
 * 再挖出来，边保持原样，水面平静不起浪。没有它时海岸照镇上东西的凸包往外推（见 map/pixel/island.ts）。
 * 冲刷参数按地面像素和轮数算，不给照引擎的默认：coast 海岸离底稿多远，bay 海岸进出的幅度，
 * warp 扭曲的幅度，erosion 冲刷几轮，rim 镇上东西四周至少留多宽的陆地。
 * 注意任何区域格子都会把陆地钉住，湾里不要放区域；外海的小岛上要有区域（比如林子），不然会被当成礁石
 */
export interface IslandDesign {
  /** 陆地底稿：几块多边形，合起来是岛和外海的小岛 */
  land: [number, number][][]
  water: IslandWater[]
  coast?: number
  bay?: number
  warp?: number
  erosion?: number
  rim?: number
}

export interface Atlas {
  canvas: { width: number; height: number }
  /** 画好的海岸，见 IslandDesign；没有就按镇子的轮廓自动生成 */
  island?: IslandDesign
  regions: {
    id: string
    name: string
    kind: string
    cell_size: number
    cells: [number, number][]
    label_anchor?: [number, number]
    /** 只管样子的区域：woods 成片的林子、allee 一排排的树（行道树、河边柳）、lawn 草坪公园（树稀、少灌木）。
     *  有 decor 的区域不摆这类地点自带的标志物（凉亭、花拱门）；没有名字的区域不标名字 */
    decor?: 'woods' | 'allee' | 'lawn'
    /** 港口朝海的方向（横竖之一）；不给时从镇子中心指向港口算 */
    facing?: [number, number]
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
    /** 路跨过岛内的水时搭什么桥：stone 石拱桥，wood 木板桥（不给时的样子） */
    bridge?: 'stone' | 'wood'
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
    /** 指定这栋房子的样子（手绘的内置地图按街区配色）：屋顶三色（亮、中、暗）、屋面、墙面、屋顶形状，
     *  刷漆木板墙（wall 为 painted）的漆色三档（中、暗、亮，同 walls.ts 的 paints），
     *  取值同 town-2d 的 map/buildings.ts；不给的照风格包按编号挑 */
    look?: {
      roof?: [string, string, string]
      roofing?: string
      wall?: string
      shape?: string
      paint?: [string, string, string]
    }
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
