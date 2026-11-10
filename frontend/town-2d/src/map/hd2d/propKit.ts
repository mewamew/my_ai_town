import * as THREE from 'three'
import { PIXEL } from '../grid'
import { mixHex } from '../pixel/noise'
import { WALL_TEXEL } from './layout'
import { Mesher } from './pier'

// 立体道具的积木：道具和房子、凉亭一样是搭出来的，一格一个色块，没有贴图。
// 水平一格是一个地图像素（P），竖直一格是一个墙面像素（T），所以道具的像素和地面、墙面一样大。
// 原点在道具落点的地面上，x 朝东、z 朝南（正对缺省镜头的是「正面」）、y 朝上；尺寸都用地图单位。
// 各件道具怎么搭见 propBuilds.ts，搭好的东西怎么进场景见 propModels.ts。

export const P = PIXEL
export const T = WALL_TEXEL
export type Vec = [number, number, number]

/** 一个面的画法：一个颜色，或者逐格给色（u 从左到右、v 从上到下，都从外面看）；返回 null 的格子空着 */
export type Paint = string | ((u: number, v: number, nu: number, nv: number) => string | null)

/** 一块料各个面的画法：没单独给的面用 all，写 false 的面不画（贴着别的料、看不见的面） */
export interface Faces {
  all?: Paint
  top?: Paint | false
  south?: Paint | false
  north?: Paint | false
  east?: Paint | false
  west?: Paint | false
}

/** 道具上的一盏灯：at 是灯的位置，reach 是照亮地面的半径，size 是光晕贴片的大小，strength 是亮度 */
export interface PropLamp {
  at: Vec
  color: string
  reach: number
  size: number
  strength: number
}

const UV: [number, number][] = [
  [0, 0],
  [1, 0],
  [1, 1],
  [0, 1],
]
const WHITE: Vec[] = [
  [1, 1, 1],
  [1, 1, 1],
  [1, 1, 1],
  [1, 1, 1],
]

const colors = new Map<string, Vec[]>()
/** 四个顶点同色；颜色先按面的明暗调过 */
function flat(hex: string, tone: number): Vec[] {
  const key = `${hex}${tone}`
  let c = colors.get(key)
  if (!c) {
    const mixed = tone >= 0 ? mixHex(hex, '#fff6e2', tone) : mixHex(hex, '#241c2c', -tone)
    const { r, g, b } = new THREE.Color(mixed)
    c = [
      [r, g, b],
      [r, g, b],
      [r, g, b],
      [r, g, b],
    ]
    colors.set(key, c)
  }
  return c
}

/** 同一个颜色在各个面上的明暗：顶面最亮，朝南正对镜头的是本色，东面和北面背光。
 *  太阳和灯另外照，这里只保证没有阳光时也分得出面 */
const TONE = { top: 0.1, south: 0, west: -0.07, east: -0.16, north: -0.22 }

export class Kit {
  /** 朝上的面按地面受灯光，立着的面按墙受灯光 */
  readonly top = new Mesher()
  readonly side = new Mesher()
  /** 自己发光的面，按颜色分：night 入夜才亮（灯罩、柜里的灯），always 白天也亮（屏幕、指示灯） */
  readonly night = new Map<string, Mesher>()
  readonly always = new Map<string, Mesher>()
  readonly lamps: PropLamp[] = []
  /** 冒热气的点 */
  readonly steam: Vec[] = []
  /** 占地：中心相对落点的偏移，半宽、半深。布置（propArrange.ts）、脚下的影子、点击区都按它 */
  foot: { cx: number; cz: number; hw: number; hd: number } = { cx: 0, cz: 0, hw: 0, hd: 0 }
  /** 靠墙摆的家具（柜子、床）：离哪面墙近就背靠哪面 */
  wall = false
  /** 沙发椅：屋里铺地毯时铺在它脚下 */
  lounge = false
  /** 用它的人站在哪（相对落点），lift 是垫高多少（躺到床上）；不给就站在正面跟前 */
  use?: { at: [number, number]; lift?: number }
  /** 最高处，名字挂在它上面 */
  tall = 0

  /** 占地以落点为中心时的简写 */
  footprint(hw: number, hd: number, cx = 0, cz = 0) {
    this.foot = { cx, cz, hw, hd }
  }

  /** 一块面板：从 o 起沿 du 铺 nu 格、沿 dv 铺 nv 格（du、dv 是整面的两条边），逐格上色；
   *  同一行里相邻同色的格子并成一条 */
  panel(
    m: Mesher,
    o: Vec,
    du: Vec,
    dv: Vec,
    n: Vec,
    nu: number,
    nv: number,
    paint: Paint,
    tone = 0
  ) {
    const at = (a: number, b: number): Vec => [
      o[0] + du[0] * a + dv[0] * b,
      o[1] + du[1] * a + dv[1] * b,
      o[2] + du[2] * a + dv[2] * b,
    ]
    this.tall = Math.max(this.tall, o[1], o[1] + du[1] + dv[1])
    if (typeof paint === 'string') {
      m.quad([at(0, 0), at(1, 0), at(1, 1), at(0, 1)], n, UV, 0, flat(paint, tone))
      return
    }
    nu = Math.max(1, nu)
    nv = Math.max(1, nv)
    for (let v = 0; v < nv; v++) {
      let start = 0
      let last = paint(0, v, nu, nv)
      for (let u = 1; u <= nu; u++) {
        const now = u < nu ? paint(u, v, nu, nv) : null
        if (u < nu && now === last) continue
        if (last)
          m.quad(
            [
              at(start / nu, v / nv),
              at(u / nu, v / nv),
              at(u / nu, (v + 1) / nv),
              at(start / nu, (v + 1) / nv),
            ],
            n,
            UV,
            0,
            flat(last, tone)
          )
        start = u
        last = now
      }
    }
  }

  /** 一块料：x0..x1 东西、z0..z1 南北、y0..y1 高。五个面各自上色，底面不画 */
  box(x0: number, x1: number, z0: number, z1: number, y0: number, y1: number, f: Faces | string) {
    const faces: Faces = typeof f === 'string' ? { all: f } : f
    const nx = Math.round((x1 - x0) / P),
      nz = Math.round((z1 - z0) / P),
      ny = Math.round((y1 - y0) / T)
    const pick = (p?: Paint | false) => (p === false ? undefined : (p ?? faces.all))
    const top = pick(faces.top),
      south = pick(faces.south),
      north = pick(faces.north),
      east = pick(faces.east),
      west = pick(faces.west)
    const w: Vec = [x1 - x0, 0, 0],
      d: Vec = [0, 0, z1 - z0],
      down: Vec = [0, y0 - y1, 0]
    if (top) this.panel(this.top, [x0, y1, z0], w, d, [0, 1, 0], nx, nz, top, TONE.top)
    if (south) this.panel(this.side, [x0, y1, z1], w, down, [0, 0, 1], nx, ny, south, TONE.south)
    if (north)
      this.panel(
        this.side,
        [x1, y1, z0],
        [x0 - x1, 0, 0],
        down,
        [0, 0, -1],
        nx,
        ny,
        north,
        TONE.north
      )
    if (east)
      this.panel(this.side, [x1, y1, z1], [0, 0, z0 - z1], down, [1, 0, 0], nz, ny, east, TONE.east)
    if (west) this.panel(this.side, [x0, y1, z0], d, down, [-1, 0, 0], nz, ny, west, TONE.west)
  }

  /** 八棱柱（桶、圆桌、灯罩、麻袋）：中心 (cx, cz)，底下半径 r、顶上半径 r1（不给就上下一样粗）；
   *  side(k, v) 给第 k 面第 v 行的颜色，top 给顶面的颜色（不给不封顶）；into 换一组几何装（发光的面） */
  prism(
    cx: number,
    cz: number,
    r: number,
    y0: number,
    y1: number,
    side: string | ((k: number, v: number, nv: number) => string),
    top?: string,
    r1 = r,
    into?: Mesher
  ) {
    const N = 8
    const nv = Math.max(1, Math.round((y1 - y0) / T))
    const ring = (rad: number, y: number, k: number): Vec => {
      const a = ((k + 0.5) / N) * Math.PI * 2
      return [cx + Math.cos(a) * rad, y, cz + Math.sin(a) * rad]
    }
    this.tall = Math.max(this.tall, y1)
    for (let k = 0; k < N; k++) {
      const mid = ((k + 1) / N) * Math.PI * 2
      const n: Vec = [Math.cos(mid), 0, Math.sin(mid)]
      const tone =
        n[2] > 0.5 ? TONE.south : n[2] > -0.5 ? (n[0] > 0 ? TONE.east : TONE.west) : TONE.north
      for (let v = 0; v < nv; v++) {
        const ya = y1 + ((y0 - y1) * v) / nv,
          yb = y1 + ((y0 - y1) * (v + 1)) / nv
        const ra = r1 + ((r - r1) * v) / nv,
          rb = r1 + ((r - r1) * (v + 1)) / nv
        const hex = typeof side === 'string' ? side : side(k, v, nv)
        ;(into ?? this.side).quad(
          [ring(ra, ya, k), ring(ra, ya, k + 1), ring(rb, yb, k + 1), ring(rb, yb, k)],
          n,
          UV,
          0,
          into ? WHITE : flat(hex, tone)
        )
      }
    }
    if (top) {
      const center: Vec = [cx, y1, cz]
      for (let k = 0; k < N; k += 2)
        (into ?? this.top).quad(
          [center, ring(r1, y1, k), ring(r1, y1, k + 1), ring(r1, y1, k + 2)],
          [0, 1, 0],
          UV,
          0,
          into ? WHITE : flat(top, TONE.top)
        )
    }
  }

  /** 桶的内壁：朝里的一圈面，从桶口往下看得见 */
  well(cx: number, cz: number, r: number, y0: number, y1: number, color: string) {
    const N = 8
    const ring = (y: number, k: number): Vec => {
      const a = ((k + 0.5) / N) * Math.PI * 2
      return [cx + Math.cos(a) * r, y, cz + Math.sin(a) * r]
    }
    for (let k = 0; k < N; k++) {
      const mid = ((k + 1) / N) * Math.PI * 2
      this.side.quad(
        [ring(y1, k), ring(y1, k + 1), ring(y0, k + 1), ring(y0, k)],
        [-Math.cos(mid), 0, -Math.sin(mid)],
        UV,
        0,
        flat(color, -0.18)
      )
    }
  }

  private lit(always: boolean, color: string) {
    const map = always ? this.always : this.night
    let m = map.get(color)
    if (!m) map.set(color, (m = new Mesher()))
    return m
  }

  /** 一块自己发光的料（屏幕、指示灯、柜里的灯条）；always 白天也亮 */
  glow(
    x0: number,
    x1: number,
    z0: number,
    z1: number,
    y0: number,
    y1: number,
    color: string,
    always = false
  ) {
    const m = this.lit(always, color)
    this.tall = Math.max(this.tall, y1)
    m.quad(
      [
        [x0, y1, z0],
        [x1, y1, z0],
        [x1, y1, z1],
        [x0, y1, z1],
      ],
      [0, 1, 0],
      UV,
      0,
      WHITE
    )
    m.quad(
      [
        [x0, y1, z1],
        [x1, y1, z1],
        [x1, y0, z1],
        [x0, y0, z1],
      ],
      [0, 0, 1],
      UV,
      0,
      WHITE
    )
    m.quad(
      [
        [x1, y1, z1],
        [x1, y1, z0],
        [x1, y0, z0],
        [x1, y0, z1],
      ],
      [1, 0, 0],
      UV,
      0,
      WHITE
    )
    m.quad(
      [
        [x0, y1, z0],
        [x0, y1, z1],
        [x0, y0, z1],
        [x0, y0, z0],
      ],
      [-1, 0, 0],
      UV,
      0,
      WHITE
    )
    m.quad(
      [
        [x1, y1, z0],
        [x0, y1, z0],
        [x0, y0, z0],
        [x1, y0, z0],
      ],
      [0, 0, -1],
      UV,
      0,
      WHITE
    )
  }

  /** 发光的八棱柱：灯罩入夜才亮；always 的白天也亮（炉火、发光的石头） */
  shade(
    cx: number,
    cz: number,
    r: number,
    y0: number,
    y1: number,
    color: string,
    r1 = r,
    always = false
  ) {
    this.prism(cx, cz, r, y0, y1, color, color, r1, this.lit(always, color))
  }

  lamp(at: Vec, color: string, reach: number, size: number, strength = 1) {
    this.lamps.push({ at, color, reach, size, strength })
  }
}
