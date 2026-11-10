import { hash, mixHex } from '../pixel/noise'
import { SNOW, SNOW_SHADE } from '../palette'
import type { LandmarkModel } from './landmarks'
import { crate, LAMP, WARM, WOOD } from './propParts'
import { Kit, P, T, type Vec } from './propKit'

// 市集的摊棚，搭成立体的（积木见 propKit.ts）。原点在柜台正面的中点，摊子往北伸：前面一排柜台摆着货，
// 后面是摊主站的地方，四根柱子撑着往前斜的棚布，棚檐垂一排花边，檐下吊一盏灯，入夜亮起来。
// - village：条纹棚布四种配色，木柜台上一筐筐果蔬，后面码着木箱。
// - frozen：同上，棚布和柜台压着雪，花边下挂一排冰溜子。
// - wasteland：歪柱子撑着打补丁的篷布，破边参差；三只木箱拼成台子，摆着罐头、瓶子和零件，灯是一只裸灯泡。

export type StallLook = 'village' | 'frozen' | 'wasteland'

const AWNINGS: [string, string][] = [
  ['#d0473c', '#f1ead8'],
  ['#3f7a9a', '#f1ead8'],
  ['#d8a840', '#f1ead8'],
  ['#5a9a5a', '#f1ead8'],
]
const PRODUCE = ['#e05a4a', '#f0c040', '#7ab050', '#e89040', '#b86ab0']
const TARPS = [
  ['#4f6f86', '#8a8472', '#b0703a'],
  ['#b0703a', '#6e6a5c', '#4f6f86'],
  ['#6e7a5a', '#8a8472', '#9a5a3a'],
]
const JUNK = ['#8a8e8e', '#5a7a4a', '#a55f2e', '#b8b0a0', '#6a6e7a']
const ICICLE = '#d8ecf6'

/** 半宽、柜台多深、摊子多深（地图单位）；棚布前后沿多高、柜台多高（世界单位） */
const W = 13 * P
const COUNTER = 5 * P
const DEPTH = 11 * P
const FRONT = 13 * T
const BACK = 15.5 * T
const DESK = 4.2 * T
/** 棚布往前、往两边多出来多少 */
const OVER = 2 * P
const SIDE = P

/** 一座摊棚；seed 挑配色和摆的货 */
export function stall(seed: number, look: StallLook): LandmarkModel {
  return { build: (k) => (look === 'wasteland' ? junkStall(k, seed) : fruitStall(k, seed, look)) }
}

/** 柱顶、吊绳缩在棚布底下这么多，不从棚布上冒出来 */
const TUCK = 0.15 * T

/** 棚布从摊子最里面（ZB）斜到檐口（OVER）：back、front 是两头的高度，返回南北向 z 处棚布的高度 */
const ZB = -DEPTH - P
const roofAt = (z: number, back: number, front: number) =>
  back + ((front - back) * (z - ZB)) / (OVER - ZB)

/** 往前斜的棚布：上面一层（朝上，接积雪和地面的灯光）、底下一层（朝下，压暗）；paint(u, v) 的 v 从后往前 */
function awning(
  k: Kit,
  x0: number,
  x1: number,
  back: number,
  front: number,
  paint: (u: number, v: number) => string | null
) {
  const zb = ZB,
    zf = OVER
  const nu = Math.round((x1 - x0) / P),
    nv = Math.round((zf - zb) / P)
  const run = zf - zb,
    rise = back - front
  const len = Math.hypot(run, rise)
  const up: Vec = [0, run / len, rise / len]
  k.panel(k.top, [x0, back, zb], [x1 - x0, 0, 0], [0, -rise, run], up, nu, nv, paint, 0.1)
  k.panel(
    k.side,
    [x1, back - 0.2, zb],
    [x0 - x1, 0, 0],
    [0, -rise, run],
    [0, -up[1], -up[2]],
    nu,
    nv,
    (u, v) => {
      const c = paint(nu - 1 - u, v)
      return c && mixHex(c, '#241c2c', 0.3)
    }
  )
}

/** 棚檐垂下的花边：前后两面，bottom(u) 给第 u 列最下面一行画不画 */
function valance(
  k: Kit,
  x0: number,
  x1: number,
  y: number,
  color: (u: number) => string,
  bottom: (u: number) => boolean
) {
  const nu = Math.round((x1 - x0) / P)
  const h = 1.2 * T
  const paint = (flip: boolean) => (u: number, v: number) => {
    const i = flip ? nu - 1 - u : u
    return v === 1 && !bottom(i) ? null : color(i)
  }
  k.panel(k.side, [x0, y, OVER], [x1 - x0, 0, 0], [0, -h, 0], [0, 0, 1], nu, 2, paint(false))
  k.panel(
    k.side,
    [x1, y, OVER - 0.2],
    [x0 - x1, 0, 0],
    [0, -h, 0],
    [0, 0, -1],
    nu,
    2,
    paint(true),
    -0.2
  )
}

/** 四根柱子顶着棚布：前两根在柜台两头，后两根在摊子最里面；lean 是前柱往里歪多少（废土） */
function posts(k: Kit, color: string, back: number, front: number, lean = 0) {
  for (const sx of [-1, 1]) {
    const x = sx * (W - P / 2) + lean * sx
    k.box(x - P / 2, x + P / 2, -P, 0, 0, roofAt(0, back, front) - TUCK, color)
    const xb = sx * (W - P / 2)
    k.box(
      xb - P / 2,
      xb + P / 2,
      -DEPTH,
      -DEPTH + P,
      0,
      roofAt(-DEPTH + P, back, front) - TUCK,
      color
    )
  }
}

/** 村庄和冰雪：条纹棚布的果蔬摊 */
function fruitStall(k: Kit, seed: number, look: StallLook) {
  const snowy = look === 'frozen'
  const [a, b] = AWNINGS[seed % AWNINGS.length]
  const stripe = (u: number) => ((u >> 2) & 1 ? b : a)
  k.footprint(W + SIDE, (DEPTH + OVER + P) / 2, 0, (OVER - DEPTH - P) / 2)
  posts(k, WOOD.dark, BACK, FRONT)
  // 柜台：竖着的木板，上沿一道浅色压条，台面探出一点
  k.box(-W + P, W - P, -COUNTER, 0, 0, DESK - 0.4 * T, {
    all: WOOD.mid,
    south: (u, v, nu, nv) => (v === nv - 1 ? WOOD.line : u % 3 === 2 ? WOOD.dark : WOOD.mid),
    top: false,
  })
  k.box(-W + 0.5 * P, W - 0.5 * P, -COUNTER - 2, 2, DESK - 0.4 * T, DESK, {
    all: WOOD.light,
    top: (u, v) => (snowy && hash(u, v, seed + 4) < 0.45 ? SNOW : WOOD.pale),
  })
  // 一筐筐果蔬：筐沿木色，货堆着冒出筐口，上面一点高光
  for (let i = 0; i < 7; i++) {
    const x0 = -W + 1.5 * P + i * 3.5 * P
    const c = PRODUCE[(i + seed) % PRODUCE.length]
    const h = DESK + (0.7 + (i % 2) * 0.3) * T
    k.box(x0, x0 + 3 * P, -COUNTER + P, -P, DESK, h, {
      all: WOOD.dark,
      south: (u, v) => (v === 0 ? c : WOOD.mid),
      top: (u, v) =>
        snowy && hash(u, v + i, seed + 5) < 0.3
          ? SNOW
          : (u + v) % 3 === 0
            ? mixHex(c, '#ffffff', 0.35)
            : c,
    })
  }
  // 后面码着木箱
  crate(k, -W + 1.5 * P, -DEPTH + 1.5 * P, 5 * P, 3 * P, 0, 2 * T)
  crate(k, -W + 2 * P, -DEPTH + 1.5 * P, 4 * P, 3 * P, 2 * T, 1.6 * T)
  crate(k, W - 6.5 * P, -DEPTH + 1.5 * P, 5 * P, 3 * P, 0, 2 * T)
  // 棚布：竖条纹，前沿一行压深；冰雪的大半压着雪，前沿露出条纹
  const nv = Math.round((OVER + DEPTH + P) / P)
  awning(k, -W - SIDE, W + SIDE, BACK, FRONT, (u, v) => {
    if (snowy && v < nv - 2 && hash(u >> 1, v >> 1, seed + 6) < 0.85)
      return hash(u, v, seed + 7) < 0.2 ? SNOW_SHADE : SNOW
    const c = stripe(u)
    return v === nv - 1 ? mixHex(c, '#241c2c', 0.2) : c
  })
  valance(k, -W - SIDE, W + SIDE, FRONT, stripe, (u) => u % 4 === 1 || u % 4 === 2)
  // 冰溜子挂在花边底下
  if (snowy)
    for (let u = 1; u < (2 * (W + SIDE)) / P; u += 2) {
      if (hash(u, 3, seed) < 0.35) continue
      const x = -W - SIDE + u * P
      const len = (0.5 + hash(u, 4, seed) * 1.3) * T
      k.box(x, x + P * 0.7, OVER - P, OVER, FRONT - 1.2 * T - len, FRONT - 1.2 * T, ICICLE)
    }
  lantern(k, WARM, BACK, FRONT)
}

/** 檐下正中吊一盏灯，入夜亮 */
function lantern(k: Kit, color: string, back: number, front: number) {
  const y = front - 1.9 * T
  k.box(-1, 1, -3, -1, y + 0.8 * T, roofAt(-1, back, front) - TUCK, '#3a3440')
  k.shade(0, -2, 0.9 * P, y, y + 0.8 * T, color, 0.6 * P)
  k.lamp([0, y + 0.4 * T, -2], LAMP, 120, 56, 0.8)
}

/** 废土：歪柱子、补丁篷布、木箱台子上的零碎 */
function junkStall(k: Kit, seed: number) {
  const tarps = TARPS[seed % TARPS.length]
  k.footprint(W + SIDE, (DEPTH + OVER + P) / 2, 0, (OVER - DEPTH - P) / 2)
  posts(k, '#5a4430', BACK - 0.8 * T, FRONT - 0.5 * T, -2)
  // 三只木箱拼成台子
  const boxes: [number, number][] = [
    [-W + P, 8 * P],
    [-W + 9.5 * P, 8 * P],
    [-W + 18 * P, 7 * P],
  ]
  boxes.forEach(([x0, w], i) => {
    const h = (3.4 + (i % 2) * 0.5) * T
    crate(k, x0, -COUNTER, w, COUNTER, 0, h, (u, v) => (u % 3 === 2 ? WOOD.dark : WOOD.mid))
    // 罐头、瓶子、零件：高高低低一排
    for (let j = 0; j < 3; j++) {
      const c = JUNK[(i * 3 + j + seed) % JUNK.length]
      const cx = x0 + (1.5 + j * 2.4) * P
      const tall = hash(i, j, seed + 8) < 0.4
      k.box(cx, cx + (tall ? 1 : 1.6) * P, -3 * P, -1.6 * P, h, h + (tall ? 1.5 : 0.8) * T, {
        all: c,
        top: mixHex(c, '#ffffff', 0.3),
      })
    }
  })
  // 补丁篷布：一块块颜色不同，接缝压深，零星破洞；往前斜，前沿垂下来的破边参差
  const nv = Math.round((OVER + DEPTH + P) / P)
  const patch = (u: number, v: number) => tarps[Math.floor(hash(u >> 3, v >> 2, seed + 7) * 3)]
  awning(k, -W - SIDE, W + SIDE, BACK - 0.8 * T, FRONT - 0.5 * T, (u, v) => {
    if (v > 1 && v < nv - 2 && hash(u, v, seed + 9) < 0.03) return null
    const c = patch(u, v)
    return (u + v * 2) % 11 === 0 || u % 8 === 0 ? mixHex(c, '#1e1a16', 0.25) : c
  })
  valance(
    k,
    -W - SIDE,
    W + SIDE,
    FRONT - 0.5 * T,
    (u) => patch(u, nv - 1),
    (u) => hash(u, 9, seed) < 0.55
  )
  // 一张铁皮斜靠在东边的柱子上
  k.panel(
    k.side,
    [W + 0.6 * P, 3.2 * T, -DEPTH + 2 * P],
    [0, 0, 6 * P],
    [0.8 * P, -3.2 * T, 0],
    [0.987, 0.159, 0],
    6,
    4,
    (u) => (u % 2 ? '#7a7a76' : '#9a9a94'),
    -0.1
  )
  lantern(k, '#ffcf7a', BACK - 0.8 * T, FRONT - 0.5 * T)
}
