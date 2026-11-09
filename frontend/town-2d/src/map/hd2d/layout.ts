import type { Atlas } from 'town-shared/mapDocument'
import { PIXEL, roomRect } from '../grid'
import { hash, hashString, mixHex } from '../pixel/noise'
import {
  buildingKind,
  oneOf,
  ROOF_SHAPES,
  ROOFINGS,
  WALL_STYLES,
  type BuildingKind,
  type BuildingStyle,
  type RoofShape,
  type Roofing,
  type WallStyle,
  type WindowKind,
} from '../buildings'
import type { MapTheme } from '../themes/types'
import type { WallColors } from '../themes/walls'
import type { InteriorPalette } from '../themes/interiors'

// 立体场景用正交斜俯视，和演示页一样镜头真的倾斜：地面纵深在屏幕上缩成 sin(俯角)，
// 高度 h 显示为 h·cos(俯角)。SVG 层（点击、名字、气泡）的视口纵向同样按 sin(俯角) 压缩，
// 地面上的点仍和 SVG 对齐；立着的文字和标记再反向拉回原比例。
// 房子的实际高度按原先的 50° 标定，调整默认镜头不改变房屋尺寸；俯角越低墙面越高、地面越扁。

/** 俯角范围（度）：低处看阶地与立面，高处读清道路；保留一点斜角以看见建筑高度 */
export const PITCH_MIN = 30
export const PITCH_MAX = 82
export const DEFAULT_PITCH = 36

export interface Tilt {
  /** 俯角（弧度） */
  pitch: number
  sin: number
  cos: number
  /** 绕地面中心旋转的方位角（弧度） */
  yaw: number
  yawSin: number
  yawCos: number
}
export function tiltOf(degrees: number, yawDegrees = 0): Tilt {
  const pitch = (Math.min(PITCH_MAX, Math.max(PITCH_MIN, degrees)) * Math.PI) / 180
  const yaw = (yawDegrees * Math.PI) / 180
  return {
    pitch,
    sin: Math.sin(pitch),
    cos: Math.cos(pitch),
    yaw,
    yawSin: Math.sin(yaw),
    yawCos: Math.cos(yaw),
  }
}

/** 竖直面上的贴图像素保持原有物理尺度，不随默认取景改变 */
export const WALL_TEXEL = PIXEL / Math.cos((50 * Math.PI) / 180)

type Space = Atlas['spaces'][number]

export interface House {
  id: string
  /** 平面地图上的占地 */
  x: number
  y: number
  w: number
  h: number
  wallTexels: number
  /** 墙高（世界单位） */
  wallH: number
  /** 屋脊高出墙顶多少（世界单位） */
  ridge: number
  /** 屋脊沿东西方向 */
  alongX: boolean
  /** 屋顶形状；cross、dormer 时 alongX 一定为真 */
  shape: RoofShape
  /** 功能类型与这类房子的外观 */
  kind: BuildingKind
  look: BuildingStyle
  /** 墙面材质 */
  style: WallStyle
  /** 这张地图风格的墙面颜色 */
  walls: WallColors
  /** 这栋房子墙面材质的三档底色：住宅在风格包的颜色上按编号微调 */
  wallShades: readonly [string, string, string]
  /** 屋顶三色（亮、中、暗） */
  roof: readonly string[]
  roofing: Roofing
  windows: WindowKind
  /** 门漆；不给是原木色 */
  doorPaint?: string
  /** 掀开屋顶后室内北墙的配色，中间铺的地毯（没有就不铺） */
  interior: InteriorPalette
  rug?: string
  /** 窗下花箱的花色，取风格包地面的花 */
  flowers: readonly string[]
  seed: number
  /** 灯塔：整块占地是石台，塔立在正中（见 lighthouse.ts）；其余房子没有 */
  tower?: Tower
}

/** 灯塔各段的尺寸，世界单位：半径从塔中心量，高度从地面量 */
export interface Tower {
  /** 石台：底下一圈粗石脚的顶、台面、沿边矮栏墙的顶 */
  ledge: number
  deck: number
  parapet: number
  /** 塔身：底和顶的半径、起止高度（下面是喇叭形的塔脚，上面是托着瞭望台的一圈牛腿） */
  foot: number
  top: number
  base: number
  neck: number
  /** 瞭望台：台面高、外沿半径 */
  gallery: number
  rim: number
  /** 灯室：玻璃的起止高度、半径 */
  glass: readonly [number, number]
  lantern: number
  /** 圆顶顶上、风向标尖（最高点） */
  dome: number
  height: number
  /** 塔上最宽处的半径：点选、摆台上的东西都按它让开 */
  reach: number
}

/** 灯塔的尺寸按占地短边定，大中小三档同一个比例：塔身约为塔脚直径的一倍半高，连灯室、圆顶比普通房子高一倍多 */
export function towerOf(w: number, h: number): Tower {
  const T = WALL_TEXEL
  const foot = Math.min(17, Math.max(11, Math.round((Math.min(w, h) / PIXEL) * 0.19)))
  const top = Math.round(foot * 0.74) * PIXEL
  const deck = 6 * T
  const base = deck + 4 * T
  const neck = base + Math.round(foot * 3.1) * T
  const gallery = neck + 4.5 * T
  const glass = [gallery + 4 * T, gallery + 13 * T] as const
  const dome = glass[1] + 6 * T
  return {
    ledge: 2 * T,
    deck,
    parapet: deck + 2.5 * T,
    foot: foot * PIXEL,
    top,
    base,
    neck,
    gallery,
    rim: top + 4 * PIXEL,
    glass,
    lantern: top - PIXEL,
    dome,
    height: dome + 7 * T,
    reach: Math.max(top + 4 * PIXEL, foot * PIXEL + 4 * PIXEL),
  }
}

/** 屋脊在屏幕上至少高出墙顶这么多像素，才放得下老虎窗 */
const DORMER_RISE = 11
/** 住宅屋顶色微调时混进去的色相：暖黄、灰蓝、草绿、砖红 */
const ROOF_TINTS = ['#d8a060', '#6a7fa0', '#8aa060', '#b06a6a']
/** 住宅墙色微调时混进去的色相：暖、冷 */
const WALL_TINTS = ['#e0b070', '#8090a8']

/** 按编号挑一个；salt 不同的挑法彼此独立 */
function choose<T>(list: readonly T[], seed: number, salt: number) {
  return list[Math.floor(hash(seed, salt, 7) * list.length)]
}

/** 住宅颜色的微调：明暗浮动 ±amount，再混一点 tints 里的色相 */
function nudge(
  colors: readonly string[],
  seed: number,
  salt: number,
  amount: number,
  tints: readonly string[]
) {
  const shift = (hash(seed, salt, 9) - 0.5) * 2 * amount
  const tint = choose(tints, seed, salt + 1)
  return colors.map((c) =>
    mixHex(mixHex(c, shift > 0 ? '#ffffff' : '#000000', Math.abs(shift)), tint, 0.08)
  ) as [string, string, string]
}

/** 屋顶形状：地图指定了就用它，不然风格给了几种就按编号挑；十字脊和老虎窗只放在横长的房子上，
 *  不够横长就退成四坡或山墙朝街 */
function roofShape(
  look: BuildingStyle,
  seed: number,
  w: number,
  h: number,
  wanted?: RoofShape
): RoofShape {
  const shape = wanted ?? (look.roofs ? choose(look.roofs, seed, 3) : 'gable')
  if ((shape === 'cross' || shape === 'dormer') && w < h * 1.15) return w < h ? 'front' : 'hip'
  return shape
}

/** 房间的外观：功能从名字判断，这种功能长什么样按风格包；住宅没指定屋顶色时按编号挑一种，
 *  屋顶形状、窗型、门漆也按编号挑。地图给了 look（手绘的内置地图按街区配色）就照它的屋顶色、屋面、
 *  墙面和屋顶形状，屋顶和住宅的墙色照样按编号微调明暗 */
export function houseOf(s: Space, theme: MapTheme): House {
  const { x, y, w, h } = roomRect(s)
  const seed = hashString(s.id)
  const kind = buildingKind(s)
  const look = theme.buildings[kind]
  const style = oneOf(WALL_STYLES, s.look?.wall) ?? look.walls[seed % look.walls.length]
  const wallTexels = look.height + Math.floor(hash(seed, 1, 2) * 5)
  // 有多种形状可挑时坡度也错开，相邻房子的屋脊高低不齐
  const vary = look.roofs && look.roofs.length > 1 ? 0.9 + hash(seed, 4, 7) * 0.4 : 1
  let shape = roofShape(look, seed, w, h, oneOf(ROOF_SHAPES, s.look?.shape))
  const alongX = shape === 'front' ? false : shape === 'gable' || shape === 'hip' ? w >= h : true
  // 默认俯角下屋脊在屏幕上高出墙顶的像素数，取屋脊两侧进深的一部分并设上限
  const depth = (alongX ? h : w) / PIXEL
  let rise = Math.min(depth * 0.3, 20) * look.rise * vary
  if (shape === 'hip') rise *= 1.1
  // 老虎窗要屋脊够高；进深太浅、抬到那么高就太陡时改成十字脊
  if (shape === 'dormer') {
    if (depth * 0.45 < DORMER_RISE) shape = 'cross'
    else rise = Math.max(rise, DORMER_RISE)
  }
  // 没指定屋顶色的是住宅：配色按编号挑，屋顶和墙的颜色再按编号微调
  const homeRoof = look.roof ? undefined : theme.homeRoofs[seed % theme.homeRoofs.length]
  const roofColors = s.look?.roof?.length === 3 ? s.look.roof : undefined
  const shades = theme.walls.shades[style]
  return {
    id: s.id,
    x,
    y,
    w,
    h,
    wallTexels,
    wallH: wallTexels * WALL_TEXEL,
    ridge: rise * WALL_TEXEL,
    alongX,
    shape,
    kind,
    look,
    style,
    walls: theme.walls,
    wallShades: homeRoof ? nudge(shades, seed, 11, 0.05, WALL_TINTS) : shades,
    roof: roofColors
      ? nudge(roofColors, seed, 13, 0.09, ROOF_TINTS)
      : (look.roof ?? nudge(homeRoof!.colors, seed, 13, 0.09, ROOF_TINTS)),
    roofing:
      oneOf(ROOFINGS, s.look?.roofing) ??
      (roofColors ? undefined : homeRoof?.roofing) ??
      look.roofing ??
      'tile',
    windows: typeof look.windows === 'string' ? look.windows : choose(look.windows, seed, 5),
    doorPaint: look.doorPaints && choose(look.doorPaints, seed, 6),
    interior: theme.interiors.walls[kind],
    rug: theme.interiors.rugs[kind],
    flowers: theme.ground.flowers,
    seed,
    ...(look.tower ? { tower: towerOf(w, h) } : {}),
  }
}

/** 高 height 的一点在屏幕上高出它脚下多少，折成地图纵深：屏幕上高出 H·cos，压扁的地图纵深要再除以 sin */
export const riseOf = (height: number, tilt: Tilt) => (height * tilt.cos) / tilt.sin

/** 房屋在地图坐标里最高点的 y（屋脊或屋顶最北的屋檐，灯塔是塔尖），名字放在它上面 */
export function houseTop(house: House, tilt: Tilt) {
  if (house.tower) return house.y + house.h / 2 - riseOf(house.tower.height, tilt)
  return house.y - riseOf(house.wallH + house.ridge, tilt) + (house.alongX ? house.h / 2 : 0)
}
