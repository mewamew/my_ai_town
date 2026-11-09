import type { BuildingKind, BuildingStyle, Roofing } from '../buildings'
import type { LandmarkSet } from '../hd2d/landmarks'
import type { InteriorColors } from './interiors'
import type { ThemeId } from './presets'
import type { WallColors } from './walls'

// 风格包：一张 2D 地图的外观。建镇时选定，写在地图文档的 generation.spec.environment.preset 里，之后不变；
// 预设和风格包的对应见 presets.ts。只管画面；地点、道路、房间和村民看到的名字都不受它影响。
// 平面像素图（pixel/）和立体场景（hd2d/）都从这里取颜色和画法，自己不再写死一套外观。

export type { ThemeId }

/** 平面地面的配色，按 terrain.ts 的地块种类分；各档从暗到亮 */
export interface GroundPalette {
  /** 镇上和镇外的空地 */
  grass: readonly string[]
  park: readonly string[]
  /** 踩出来的土路 */
  dirt: readonly string[]
  /** 土路上零星的石子：[上沿亮色, 石子] */
  pebble: readonly [string, string]
  plaza: readonly string[]
  /** 广场石板缝、石板上沿的亮边、污渍 */
  plazaLine: string
  plazaLight: string
  plazaStain: string
  gate: readonly string[]
  gateLine: string
  /** 港口铺板和栈桥：三档木色、板缝 */
  plank: readonly string[]
  plankLine: string
  /** 栈桥缺板的比例，缺的地方露出下面 */
  pierGaps: number
  /** 市集地砖：两色棋盘、格点、污渍 */
  market: readonly [string, string, string, string]
  /** 花园：土、叶、花（花取 flowers） */
  gardenSoil: string
  gardenLeaf: readonly [string, string]
  /** 孤岛外圈从岸边往外的几档颜色：海水、干掉的海床或冰面（固定六档） */
  outer: readonly string[]
  /** 紧贴外圈的一圈：浪花、旧海岸线的土坎或岸边冻住的浪 */
  outerEdge: string
  /** 外圈画成会动的海时（outer 为 sea）：近岸的白沫、深水里成段的浪纹、偶尔一点闪光。
   *  海的各档颜色取 outer */
  seaSurface?: { foam: string; ripple: string; glint: string }
  /** 外圈上成片的浅色：海床的盐碱、冰面上的积雪；海面不用 */
  outerSpot?: string
  sand: readonly string[]
  wetSand: string
  wetSandDither: string
  sandPebble: string
  /** 草丛尖上的亮色、沙草过渡带里的杂草 */
  tuft: string
  shoreWeed: string
  flowers: readonly string[]
  /** 地面裂缝的颜色；不给就没有裂缝 */
  cracks?: string
  /** 草坪公园（decor 为 lawn）修剪出的条纹：隔一道掺一点这个颜色；不给就和公园的草一样画 */
  lawnStripe?: string
}

/** 住宅屋顶的一种配色（亮、中、暗）；roofing 不给就用住宅风格的屋面 */
export interface HomeRoof {
  colors: readonly [string, string, string]
  roofing?: Roofing
}

/** 远处小岛（废土里是海床上的台地）的配色 */
export interface IsletPalette {
  /** 两档浅水和浪花；不给就不画水圈，露出下面的外圈 */
  shallows?: readonly [string, string, string]
  shore: readonly [string, string]
  ground: readonly [string, string]
  /** 树丛：亮边、暗边、两档中间色 */
  scrub: readonly [string, string, string, string]
  rock: readonly [string, string]
  cliff: readonly [string, string, string]
}

type Rgb = [number, number, number]

/** 光照与调色：白天、傍晚（金色时刻）、蓝调时刻（日落后天没黑透、灯已亮）、夜里四组，
 *  场景按太阳高度在它们之间插值 */
export interface LightPalette {
  sky: { day: string; night: string; golden: string; blue: string }
  top: { day: string; night: string; golden: string; blue: string }
  hill: string
  hemiSky: { day: string; night: string; blue: string }
  hemiGround: { day: string; night: string; blue: string }
  sun: { day: string; low: string }
  /** 调色：整幅画面各乘一层 */
  tint: { day: Rgb; golden: Rgb; blue: Rgb; night: Rgb }
  /** 暗部偏色：只乘在暗部，亮部不动（傍晚亮处暖、暗处偏青就是它） */
  shade: { day: Rgb; golden: Rgb; blue: Rgb; night: Rgb }
  saturation: number
  /** 雾的浓度倍数 */
  fog: number
  lamp: string
  /** 夜里天幕上极光的强度，0 是没有 */
  aurora: number
  /** 这个风格整体的胶片色调，启动时烘成一张 3D LUT（见 hd2d/post.ts 的 lookTexture） */
  look: LookParams
}

/** 胶片色调的几个参数，都在 0 附近，0 是不改 */
export interface LookParams {
  /** 黑位抬起多少（0～0.05） */
  lift: number
  /** 高光往暖色偏 */
  warm: number
  /** 暗部往青色偏 */
  teal: number
  /** 草绿：正数往黄绿偏、负数往青绿偏，同时按绝对值稍微降饱和 */
  greens: number
  /** S 形对比（0 不变，0.2 明显） */
  contrast: number
}

export interface MapTheme {
  id: ThemeId
  ground: GroundPalette
  /** 外圈画成会动的海、干海床，还是冻住的冰原 */
  outer: 'sea' | 'seabed' | 'ice'
  /** 树冠配色（每种三到五档）；乔木画成圆冠树、枯树或压雪的松树，
   *  枯树的灌木是稀疏的干灌丛，雪松的灌木是雪堆 */
  flora: {
    canopy: readonly (readonly string[])[]
    tree: 'round' | 'dead' | 'pine'
    density: number
  }
  buildings: Record<BuildingKind, BuildingStyle>
  /** 墙面材质的颜色（buildings 里按名字选材质） */
  walls: WallColors
  /** 室内的墙纸、护墙板、地毯和地板 */
  interiors: InteriorColors
  /** 住宅没有指定屋顶色时，从这几种里按编号挑 */
  homeRoofs: readonly HomeRoof[]
  /** 户外地点的立牌、栈桥边的船、野地和外圈的散落物 */
  landmarks: LandmarkSet
  islet: IsletPalette
  light: LightPalette
  /** 空气里的微粒：颜色、白天的浓度、夜里的浓度、横向漂移和一生里的升降（地图像素，负数是往下落）；
   *  fireflies 为 false 时公园夜里没有萤火虫 */
  motes: {
    dust: [number, number, number]
    strength: number
    night: number
    drift: number
    lift: number
    fireflies: boolean
  }
  /** 路灯画法（none 是不立路灯：野外小径）、旗子配色；灯塔是红白条纹、积雪的红塔，还是塌了顶烧着一盆火
   *  （见 hd2d/lighthouse.ts） */
  lamp: 'street' | 'scrap' | 'none'
  /** 沿路两盏路灯隔多远（地面像素），不给是 80；废土隔得远，留出暗处给火盆和霓虹 */
  lampGap?: number
  flag: { colors: readonly [string, string]; torn: boolean }
  lighthouse: 'striped' | 'snowy' | 'ruined'
  /** 秃鹫：白天在骨头、沉船上空盘旋（地图给了 flocks 就照它）；不要就不给 */
  vultures?: boolean
}
