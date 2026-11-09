import type { Atlas } from 'town-shared/mapDocument'

// 按房间的功能定外观：墙面、墙高、屋顶颜色和坡度、窗、门，再加一两个认得出的特征（招牌、雨棚、旗杆）。
// 每种功能具体长什么样由风格包给（themes/），这里只有类型、门的尺寸和判断功能的规则。
// 功能取地图里房间的 kind（建镇生成的地图都有）；默认小镇这类旧地图没有 kind，按编号和名字判断。
// 平面图的地板、海岸收进的海塔和立体场景的房子都用这里的判断，同一间房只有一种功能。
// 剧院是拱顶，柱廊图书馆门前一排石柱；海塔不盖房子，整块占地是石台、正中立灯塔。
// 屋顶形状、屋面、窗型给了多种的，按房间编号挑一种；同一张地图每次打开都一样。

export const WALL_STYLES = [
  'plaster',
  'wood',
  'stone',
  'brick',
  'clean',
  'pastel',
  'plank',
  // 废土：波纹铁皮、集装箱、打了补丁的水泥、拼起来的废料板
  'tin',
  'container',
  'concrete',
  'scrap',
  // 冰雪：刷了漆的竖木板，漆色按房子编号挑
  'painted',
] as const
export type WallStyle = (typeof WALL_STYLES)[number]
/** 屋顶形状：gable 是沿长边的双坡（原来唯一的一种），hip 四坡（方形占地就成了攒尖），
 *  front 屋脊南北向、山墙朝南对着街；cross 在双坡的南坡上叠一个朝南的小山墙（十字脊），
 *  dormer 是南坡上开的老虎窗。cross 和 dormer 只用在横长的房子上，放不下时退成别的形状 */
export const ROOF_SHAPES = ['gable', 'hip', 'front', 'cross', 'dormer'] as const
export type RoofShape = (typeof ROOF_SHAPES)[number]

/** 屋面：瓦、石板瓦、木瓦、生锈的波纹铁皮、厚雪 */
export const ROOFINGS = ['tile', 'slate', 'shingle', 'tin', 'snow'] as const
export type Roofing = (typeof ROOFINGS)[number]

/** 地图上写的取值是不是这几种之一 */
export const oneOf = <T extends string>(list: readonly T[], value: string | undefined) =>
  list.find((item) => item === value)

/** boarded：一部分窗钉了木板，其余是带铁栏的脏玻璃；frost：白窗框，窗台上积雪，窗角结霜；
 *  casement：不带百叶的双扇窗；tower：高楼一层一排窗，有的炸成黑洞、有的砌死，零星几扇夜里还亮 */
export type WindowKind =
  | 'shutter'
  | 'casement'
  | 'plain'
  | 'tall'
  | 'arched'
  | 'shop'
  | 'wide'
  | 'high'
  | 'rows'
  | 'boarded'
  | 'frost'
  | 'tower'

const BUILDING_KINDS = [
  'home',
  'townhall',
  'library',
  'clinic',
  'canteen',
  'cafe',
  'shop',
  'workshop',
  'warehouse',
  'inn',
  'club',
  'theatre',
  'hotel',
  'colonnade',
  'lighthouse',
] as const
export type BuildingKind = (typeof BUILDING_KINDS)[number]

export interface BuildingStyle {
  /** 给了多个就按房间编号挑一个 */
  walls: WallStyle[]
  /** 墙高（贴图像素），实际再随机加 0～4 */
  height: number
  /** 屋顶三色（亮、中、暗）；不给就按房间编号从常见配色里挑 */
  roof?: readonly [string, string, string]
  /** 屋脊高度的倍数：仓库平缓，公所陡一些；给了多种屋顶形状时再按编号浮动 */
  rise: number
  /** 屋顶形状，不给就是沿长边的双坡（见 RoofShape） */
  roofs?: readonly RoofShape[]
  /** 屋面：瓦片（默认）、生锈的波纹铁皮，或者盖满了雪；住宅的配色可以另配屋面（MapTheme.homeRoofs） */
  roofing?: Roofing
  /** 屋檐下挂一排冰柱 */
  icicles?: boolean
  chimney: 'never' | 'sometimes' | 'always'
  /** 有烟囱时冒烟（饭堂、工作坊一直生着火） */
  smoke?: boolean
  /** 窗型，给了多种就按编号挑 */
  windows: WindowKind | readonly WindowKind[]
  door: 'single' | 'double' | 'grand' | 'barn'
  /** 门漆，按编号挑；不给是原木色 */
  doorPaints?: readonly string[]
  /** 门口的条纹雨棚：两种条纹色，whole 为 true 时铺满整面墙 */
  awning?: { colors: readonly [string, string]; whole: boolean }
  sign?: 'cross' | 'book' | 'hammer' | 'inn' | 'emblem' | 'mask'
  flowers?: boolean
  lanterns?: boolean
  flag?: boolean
  /** 屋顶形状：默认双坡，剧院是半圆的拱顶 */
  vault?: boolean
  /** 不盖房子：整块占地是石台，正中立一座灯塔（hd2d/lighthouse.ts）；墙高只用来定掀开后的室内墙高 */
  tower?: boolean
  /** 南墙前一排石柱 */
  columns?: boolean
}

/** 门的宽和高（贴图像素） */
export const DOORS: Record<BuildingStyle['door'], [number, number]> = {
  single: [7, 12],
  double: [11, 13],
  grand: [11, 15],
  barn: [16, 17],
}

/** 旧地图按名字判断，先匹配更具体的：dining_hall 是食堂，不能被 hall 当成公所；workshop 里有 shop，
 *  要排在商店前面；柱廊图书馆排在图书馆前面，酒店排在旅舍前面 */
const RULES: [RegExp, BuildingKind][] = [
  [/dining|canteen|食堂|餐/, 'canteen'],
  [/town_?hall|公所|镇政|市政|议事/, 'townhall'],
  [/colonnade|柱廊/, 'colonnade'],
  [/library|图书|书/, 'library'],
  [/theatre|theater|剧院|戏院|剧场/, 'theatre'],
  [/lighthouse|灯塔|海塔/, 'lighthouse'],
  [/hotel|酒店|宾馆/, 'hotel'],
  [/clinic|hospital|诊所|医/, 'clinic'],
  [/cafe|coffee|咖啡|茶/, 'cafe'],
  [/workshop|工作坊|工坊|作坊|铁匠|木匠/, 'workshop'],
  [/market|shop|store|市集|商店|杂货|铺/, 'shop'],
  [/warehouse|仓库|货栈|库房/, 'warehouse'],
  [/inn|旅舍|旅馆|客栈/, 'inn'],
  [/club|俱乐部|会所/, 'club'],
]

/** 房间的功能：有 kind 就用它（不认识的种类按住宅画），没有才按编号和名字判断 */
export function buildingKind(space: Atlas['spaces'][number]): BuildingKind {
  if (space.kind !== undefined)
    return (BUILDING_KINDS as readonly string[]).includes(space.kind)
      ? (space.kind as BuildingKind)
      : 'home'
  const text = `${space.id} ${space.name}`.toLowerCase()
  return RULES.find(([pattern]) => pattern.test(text))?.[1] ?? 'home'
}
