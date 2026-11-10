import type { Spatial, AssetManifest } from './spatial'
import type { Appearance } from './props/types'
import type { VillagerLook } from './protocol'
// 地图文档：atlas 提供绘图几何；topology 提供地点名称与物品所属地点；spatial 是三维数据。
// 类型放在共用层，加载逻辑在 town-2d 的 assets 模块。

/** 岛内的一片水：多边形，或者带宽度的折线（河）；都是地图坐标。kind 为 spring 的是温泉：
 *  青绿的热水，池边一圈压雪的黑石头，水面冒白汽，夜里透出青光。kind 为 mirror 的是镜池：
 *  水色深、不透底，平得像镜子，岸上的树、亭子和灯清清楚楚映在里面 */
export type IslandWater = (
  { polygon: [number, number][] } | { line: [number, number][]; width: number }
) & { kind?: 'spring' | 'mirror' }

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
    /** 只管样子的区域：woods 成片的林子、allee 一排排的树（行道树、河边柳）、lawn 草坪公园（树稀、少灌木；
     *  风格包给了修剪条纹色的画成修剪过的草坪，中间开阔、树只种在北沿）、meadow 花甸（不种树，满地野花）、
     *  clearing 空地（不种树，只零星几丛草，雪橇坡这类）、asphalt 裂开积沙的旧沥青路面、
     *  rubble 碎水泥块撒了一地的废墟地（这两种都不长树）。
     *  有 decor 的区域不摆这类地点自带的标志物（凉亭、花拱门）；没有名字的区域不标名字 */
    decor?: 'woods' | 'allee' | 'lawn' | 'meadow' | 'clearing' | 'asphalt' | 'rubble'
    /** 港口朝海的方向（横竖之一）；不给时从镇子中心指向港口算。看台（court）敞开的一面朝哪，不给朝南 */
    facing?: [number, number]
    /** 这处户外地点立什么地标：风格包 landmarks.plans 里的名字（如冰雪的 icefishing 冰钓场、sledding 雪橇坡），
     *  给了就不按 kind 挑，有 decor 也照立；风格包里没有这一种就不立 */
    landmark?: string
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
    /** 这段路边的灯：none 不立，lantern 立矮石灯（公园里的步道）；不给照风格包立路灯 */
    lamp?: 'none' | 'lantern'
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
  /** 只看不进的楼（废墟里的断楼）：画成立体的楼壳，没有门和室内，不是地点，点不中，村民也不进去。
   *  x、y、w、h 是占地（地图坐标），height 是墙高（贴图像素，普通房子二三十），一层一排窗；
   *  look 同 spaces 的 look（屋顶三色、屋面、墙面、屋顶形状），不给照风格包的高楼 */
  ruins?: {
    id: string
    x: number
    y: number
    w: number
    h: number
    height: number
    look?: { roof?: [string, string, string]; roofing?: string; wall?: string; shape?: string }
  }[]
  /** 按坐标立的立牌，不占区域格子，可以立在干海床、冰面上（骨架、火盆、霓虹招牌、广告牌）：
   *  kind 是风格包 landmarks.plans 里的名字（风格包里没有这一种就不立），x、y 是立牌底边中点；
   *  flip 左右翻过来；on 是一栋房子或 ruins 里一栋楼的编号，立牌蹲到它的墙顶上（楼顶的秃鹫）。
   *  kind 为 court 的是立体的看台（见 town-2d 的 map/pixel/stands.ts）：x、y 是舞台中心，size 是外半径
   *  （地图单位，不给 160），facing 是敞开的一面朝哪（不给朝南，正对缺省镜头）。
   *  kind 为 pavilion 的是立体的八角凉亭（见 town-2d 的 map/hd2d/gazebo.ts）：x、y 是亭子正中，facing 同上 */
  standees?: {
    kind: string
    x: number
    y: number
    flip?: boolean
    on?: string
    size?: number
    facing?: [number, number]
  }[]
  /** 在一处上空盘旋的鸟群（废土是秃鹫）：中心 x、y，离地高度（地图单位），几只。
   *  不给时风格包要秃鹫的，自己在干海床的骨头、沉船上空摆几群 */
  flocks?: { x: number; y: number; height: number; count: number }[]
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
  /** 手绘的内置地图没有建镇参数，风格写在这里，取值同 generation.spec.environment */
  environment?: { preset?: string }
  /** 随地图带的世界观：第一次进这个小镇时开局向导、首次对话框默认用它（一句话建镇的建议优先） */
  worldview?: string

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
  /** 存档停在哪（读存档）：第几天、住了几个人、世界分钟、天气，住着谁（按入住先后，最多 8 位）；
   *  还没开始过的小镇是 null。后三项旧的管理服务不带 */
  progress?: {
    day: number
    residents: number
    minutes?: number
    weather?: string
    cast?: { name: string; template_id: string | null; look: VillagerLook | null }[]
  } | null
  /** 一句话建的小镇才有 */
  creation?: TownCreation | null
}
