import { hash, mixHex, noise } from '../pixel/noise'
import { SNOW, SNOW_SHADE } from '../palette'
import type { LandmarkModel } from './landmarks'
import { WOOD } from './propParts'
import { Kit, P, T } from './propKit'

// 港口的船，搭成立体的（积木见 propKit.ts）。船头朝积木的东（x 轴），原点在水线上船身正中；
// 栈桥边怎么停见 landmarks.ts 的 mooredBoats：船身顺着栈桥，镜头怎么转都看得见侧面和船尾。
// 船身一像素一片横着排：船尾略收、船头收尖并往上翘；舷边一道亮木、一道暗木，往下是腰线、船身漆，
// 水线上一道白，水下是船底漆。
// - village：kind 0 帆船（主帆、前帆，桅顶一面小旗，靠桥那边挂护舷），1 渔船（船尾驾驶舱的窗夜里亮，
//   桅杆上帆卷着罩着帆罩，船头堆着渔网和浮子），2 小舢板（两道坐板，一支桨搭在里面）。都随水起伏。
// - frozen：冻在冰里不动，甲板和横桁压雪，船边一圈冰雪；小舢板大半埋在雪里。
// - wasteland：搁浅的锈船歪在海床上，侧面破了个洞，桅杆断了半截，船边积一圈沙。没有小舢板。

export type BoatLook = 'village' | 'frozen' | 'wasteland'

const PAINTS: [string, string][] = [
  ['#2f6f7a', '#efe6cf'],
  ['#a8442e', '#efe6cf'],
  ['#2e4a6e', '#e8c45a'],
  ['#e6dfcc', '#2f6f7a'],
  ['#3e6e48', '#efe6cf'],
]
const FROZEN_HULLS = ['#6a2a24', '#2e4a6a', '#3a4a3a']
const WRECK_HULLS = ['#7a5236', '#6a4a36', '#5a5a52']
const RUST = ['#8a4a24', '#a55f2e', '#6e3a1e']
const SAILS = ['#f1ead8', '#e8d8b6', '#c4673f']
const BOTTOM = '#7e3328'
const BOOT = '#efe6cf'
const RAIL = '#d4a874'
const RAIL_DARK = '#7a5a3a'
const DECK = ['#c4925c', '#b5844f']
const MAST = '#6b4a30'
const ICE = '#cfe2ee'
const SAND = ['#d8cdb0', '#c9bb99']
const LAMP = '#ffd27a'

interface Hull {
  /** 长、宽（地图单位）；舷边多高、吃水多深（世界单位） */
  len: number
  beam: number
  sheer: number
  draft: number
  paint: string
  stripe: string
  /** 甲板的颜色：一片一种（积雪、锈） */
  deck: (i: number, v: number, nv: number) => string
  /** 船身侧面每一格的颜色要改的话（锈斑、破洞、积雪的舷边），返回 undefined 照旧 */
  over?: (i: number, y: number, side: number) => string | undefined
}

/** 船身：沿船长一像素一片，返回第 i 片（从船尾数）的半宽和舷边高，给甲板上的东西定位 */
function hull(k: Kit, h: Hull) {
  const n = Math.round(h.len / P)
  const x0 = -h.len / 2
  const shape = (i: number) => {
    const t = (i + 0.5) / n
    const half =
      (h.beam / 2) * (t < 0.12 ? 0.82 + t * 1.5 : t > 0.62 ? Math.sqrt((1 - t) / 0.38) : 1)
    const top = h.sheer + (t > 0.7 ? ((t - 0.7) / 0.3) * 0.7 * T : 0)
    return { half: Math.max(P * 0.6, Math.round(half / P) * P), top }
  }
  for (let i = 0; i < n; i++) {
    const { half, top } = shape(i)
    const x = x0 + i * P
    const rows = Math.max(1, Math.round((top + h.draft) / T))
    const side = (s: number) => (u: number, v: number) => {
      const y = top - ((v + 0.5) * (top + h.draft)) / rows
      const custom = h.over?.(i, y, s)
      if (custom) return custom
      if (v === 0) return RAIL
      if (v === 1) return RAIL_DARK
      if (y < -0.25 * T) return BOTTOM
      if (y < 0.35 * T) return BOOT
      return v === 2 ? h.stripe : h.paint
    }
    k.box(x, x + P, -half, half, -h.draft, top, {
      south: side(1),
      north: side(-1),
      east: side(0),
      west: side(0),
      top: (u, v, nu, nv) => (v === 0 || v === nv - 1 ? RAIL : h.deck(i, v, nv)),
    })
  }
  return (t: number) => shape(Math.min(n - 1, Math.max(0, Math.floor(t * n))))
}

/** 帆：竖在船的中线上（正反两面），fill(u, v) 说第 u 列（从船尾往船头）、第 v 行（从上往下）有没有帆布 */
function sail(
  k: Kit,
  x0: number,
  x1: number,
  y0: number,
  y1: number,
  color: string,
  fill: (u: number, v: number, nu: number, nv: number) => boolean
) {
  const nu = Math.max(1, Math.round((x1 - x0) / P)),
    nv = Math.max(1, Math.round((y1 - y0) / T))
  const paint = (flip: boolean) => (u: number, v: number) =>
    fill(flip ? nu - 1 - u : u, v, nu, nv)
      ? v % 3 === 2
        ? mixHex(color, '#7a6a50', 0.18)
        : color
      : null
  k.panel(k.side, [x0, y1, 0.5], [x1 - x0, 0, 0], [0, y0 - y1, 0], [0, 0, 1], nu, nv, paint(false))
  k.panel(
    k.side,
    [x1, y1, -0.5],
    [x0 - x1, 0, 0],
    [0, y0 - y1, 0],
    [0, 0, -1],
    nu,
    nv,
    paint(true),
    -0.2
  )
}

/** 一盏夜里亮的灯 */
function lamp(k: Kit, x: number, z: number, y: number) {
  k.shade(x, z, 0.7 * P, y, y + 0.7 * T, LAMP, 0.5 * P)
  k.lamp([x, y + 0.4 * T, z], LAMP, 90, 44, 0.7)
}

/** 小镇的船：kind 0 帆船、1 渔船、2 小舢板 */
function villageBoat(k: Kit, seed: number, kind: number) {
  const [paint, stripe] = PAINTS[seed % PAINTS.length]
  if (kind === 2) return rowboat(k, seed, false)
  const len = kind === 0 ? 32 * P : 30 * P,
    beam = kind === 0 ? 9 * P : 10 * P
  const sheer = 2.2 * T
  k.footprint(len / 2, beam / 2)
  const at = hull(k, {
    len,
    beam,
    sheer,
    draft: 1.6 * T,
    paint,
    stripe,
    deck: (i, v) => DECK[(i + (v >> 1)) % 2],
  })
  const deck = (t: number) => at(t).top
  if (kind === 0) {
    // 桅杆、帆桁、主帆和前帆，桅顶一面小旗
    const mx = 0.08 * len
    const top = sheer + 22 * T
    k.box(mx - P / 2, mx + P / 2, -P / 2, P / 2, deck(0.58), top, MAST)
    const boom = sheer + 3.4 * T
    k.box(-0.42 * len, mx, -0.4 * P, 0.4 * P, boom, boom + 0.5 * T, MAST)
    const main = SAILS[seed % 2]
    sail(
      k,
      -0.4 * len,
      mx - P / 2,
      boom + 0.5 * T,
      top - T,
      main,
      (u, v, nu, nv) => u >= nu - ((v + 1) * nu) / nv
    )
    sail(
      k,
      mx + P / 2,
      0.47 * len,
      sheer + 2 * T,
      top - 2 * T,
      SAILS[(seed + 1) % 3],
      (u, v, nu, nv) => u < ((v + 1) * nu) / nv
    )
    k.box(mx + P / 2, mx + 3.5 * P, -0.3, 0.3, top - 1.2 * T, top - 0.2 * T, '#d0473c')
    // 两舷各挂两只护舷
    for (const fx of [-0.2, 0.2])
      for (const z of [-beam / 2 - P, beam / 2])
        k.box(fx * len - P, fx * len + P, z, z + P, sheer - 1.6 * T, sheer - 0.4 * T, '#f1ead8')
    lamp(k, -0.46 * len, 0, deck(0))
  } else {
    // 船尾驾驶舱：白墙，四面开窗，夜里亮；顶上压一块深色顶板
    const x0 = -0.44 * len,
      x1 = -0.12 * len,
      half = beam / 2 - 1.5 * P
    const y0 = deck(0.2),
      y1 = y0 + 5.5 * T
    const window = (u: number, v: number, nu: number) =>
      v === 1 && u % 3 === 1 && u < nu - 1 ? '#3a4a5a' : '#ece6d8'
    k.box(x0, x1, -half, half, y0, y1, {
      all: '#ece6d8',
      south: window,
      north: window,
      east: window,
      west: '#ece6d8',
      top: false,
    })
    k.box(x0 - P, x1 + P, -half - P, half + P, y1, y1 + 0.6 * T, { all: '#3a4a5a', top: '#4c5c6c' })
    for (const z of [half + 0.3, -half - 0.3])
      for (let x = x0 + 1.5 * P; x < x1 - P; x += 3 * P)
        k.glow(x, x + P, z - 0.3, z + 0.3, y0 + 1.6 * T, y0 + 2.6 * T, '#ffd88a')
    // 救生圈挂在驾驶舱南墙上
    k.box(x0 + 0.5 * P, x0 + 2.5 * P, half, half + 0.6 * P, y0 + 1.2 * T, y0 + 3.2 * T, {
      all: '#f1ead8',
      south: (u, v) => ((u + v) % 2 ? '#d0473c' : '#f1ead8'),
    })
    // 桅杆在前，帆卷着罩着帆罩
    const mx = 0.18 * len
    const top = sheer + 15 * T
    k.box(mx - P / 2, mx + P / 2, -P / 2, P / 2, deck(0.68), top, MAST)
    k.box(mx - 7 * P, mx, -0.8 * P, 0.8 * P, sheer + 4 * T, sheer + 5 * T, {
      all: '#2f5f6a',
      top: '#3f7a86',
    })
    k.box(mx + P / 2, mx + 2.5 * P, -0.3, 0.3, top - T, top, '#e8c45a')
    // 船头堆着渔网和浮子
    const nx = 0.3 * len
    k.box(nx, nx + 6 * P, -2.5 * P, 2.5 * P, deck(0.85), deck(0.85) + 1.2 * T, {
      all: '#3f5f4a',
      top: (u, v) => ((u * 3 + v) % 5 === 0 ? '#e8823a' : (u + v) % 2 ? '#3f5f4a' : '#4f7458'),
    })
    lamp(k, x1 - P, 0, y1 + 0.6 * T)
  }
}

/** 小舢板：木色船身，两道坐板，一支桨搭在里面；snowy 时大半埋在雪里 */
function rowboat(k: Kit, seed: number, snowy: boolean) {
  const len = 14 * P,
    beam = 5 * P
  k.footprint(len / 2, beam / 2)
  const sheer = snowy ? 0.6 * T : 1.3 * T
  hull(k, {
    len,
    beam,
    sheer,
    draft: snowy ? 1.4 * T : 0.9 * T,
    paint: WOOD.mid,
    stripe: WOOD.light,
    deck: (i, v) => (snowy && hash(i, v, seed) < 0.7 ? SNOW : (i + v) % 3 ? WOOD.mid : WOOD.dark),
    over: snowy
      ? (i, y) => (y > 0 && hash(i, Math.round(y), seed) < 0.4 ? SNOW : undefined)
      : undefined,
  })
  if (snowy) {
    snowBank(k, len, beam, seed, 0.6 * T)
    return
  }
  for (const x of [-0.18 * len, 0.18 * len])
    k.box(x - P / 2, x + P / 2, -beam / 2 + P, beam / 2 - P, sheer, sheer + 0.3 * T, WOOD.light)
  k.box(-0.38 * len, 0.3 * len, 0.5 * P, 1.1 * P, sheer + 0.3 * T, sheer + 0.6 * T, WOOD.pale)
}

/** 船边一圈冰雪（冻住的船）：高低不平的雪块 */
function snowBank(k: Kit, len: number, beam: number, seed: number, high: number) {
  const n = Math.round(len / P / 2)
  for (let i = 0; i < n; i++) {
    const x = -len / 2 + i * 2 * P
    for (const side of [-1, 1]) {
      const h = (0.3 + hash(i, side, seed + 3) * 0.7) * high
      const z0 = side * (beam / 2)
      const z1 = z0 + side * (1 + hash(i, side, seed + 4) * 1.5) * P
      k.box(x - P, x + P, Math.min(z0, z1), Math.max(z0, z1), -0.2 * T, h, {
        all: hash(i, side, seed + 5) < 0.3 ? ICE : SNOW_SHADE,
        top: SNOW,
      })
    }
  }
}

/** 冻在冰里的船：两根桅杆、横桁压雪，船尾一间舱房窗里亮着，甲板积雪，船边一圈冰雪 */
function frozenBoat(k: Kit, seed: number, kind: number) {
  if (kind === 2) return rowboat(k, seed, true)
  const paint = FROZEN_HULLS[seed % FROZEN_HULLS.length]
  const len = 32 * P,
    beam = 10 * P,
    sheer = 2 * T
  k.footprint(len / 2 + 2 * P, beam / 2 + 2 * P)
  const at = hull(k, {
    len,
    beam,
    sheer,
    draft: 1.6 * T,
    paint,
    stripe: mixHex(paint, '#ffffff', 0.2),
    deck: (i, v) => (hash(i, v, seed + 1) < 0.8 ? SNOW : DECK[i % 2]),
    over: (i, y, side) =>
      side !== 0 && y > sheer - 0.6 * T && hash(i, 1, seed) < 0.5 ? SNOW : undefined,
  })
  for (const [mx, high] of [
    [-0.12 * len, 17 * T],
    [0.2 * len, 19 * T],
  ]) {
    k.box(mx - P / 2, mx + P / 2, -P / 2, P / 2, at(0.5).top, sheer + high, '#3a2a20')
    const yard = sheer + high - 5 * T
    k.box(mx - P / 2, mx + P / 2, -4.5 * P, 4.5 * P, yard, yard + 0.5 * T, {
      all: '#3a2a20',
      top: SNOW,
    })
  }
  const x0 = -0.44 * len,
    x1 = -0.2 * len
  const y0 = at(0.15).top
  k.box(x0, x1, -3 * P, 3 * P, y0, y0 + 4 * T, { all: '#d8d0c0', top: false })
  k.box(x0 - P, x1 + P, -4 * P, 4 * P, y0 + 4 * T, y0 + 4.6 * T, { all: '#a8a094', top: SNOW })
  k.glow(x0 + 2 * P, x0 + 3.5 * P, 3 * P, 3 * P + 0.6, y0 + 1.5 * T, y0 + 2.6 * T, '#f0d890')
  k.lamp([x0 + 2.7 * P, y0 + 2 * T, 3 * P + 2], '#ffd27a', 80, 40, 0.6)
  snowBank(k, len, beam, seed, 1.1 * T)
}

/** 搁浅的锈船：船身歪着，锈斑一片片，侧面破个洞；桅杆断了半截，断下来的横在甲板上；船边积沙 */
function wreck(k: Kit, seed: number) {
  const paint = WRECK_HULLS[seed % WRECK_HULLS.length]
  const len = 30 * P,
    beam = 9 * P,
    sheer = 2 * T
  k.footprint(len / 2 + 2 * P, beam / 2 + 2 * P)
  const hole = 10 + Math.floor(hash(seed, 1, 3) * 8)
  const at = hull(k, {
    len,
    beam,
    sheer,
    draft: 1.2 * T,
    paint,
    stripe: '#b8b0a0',
    deck: (i, v) =>
      noise(i / 3, v / 2, seed) > 0.55 ? RUST[(i + v) % 3] : (i + v) % 3 ? '#6a5a48' : '#5a4a3a',
    over: (i, y, side) => {
      if (side === 1 && i >= hole && i < hole + 3 && y > 0 && y < 1.4 * T) return '#1e1a16'
      if (side !== 0 && noise(i / 3, y / 8, seed + 2) > 0.58) return RUST[(i + Math.round(y)) % 3]
      return undefined
    },
  })
  const mx = 0.1 * len
  k.box(mx - P / 2, mx + P / 2, -P / 2, P / 2, at(0.6).top, sheer + 6 * T, '#4a3428')
  k.box(-0.45 * len, mx - P, 0.8 * P, 1.6 * P, at(0.3).top, at(0.3).top + 0.6 * T, '#5a4030')
  // 船边积的沙
  for (let i = 0; i < len / P / 2; i++) {
    const x = -len / 2 + i * 2 * P
    for (const side of [-1, 1]) {
      const h = (0.4 + hash(i, side, seed + 6) * 0.8) * T
      const z0 = side * (beam / 2 - 0.5 * P)
      const z1 = z0 + side * (1.5 + hash(i, side, seed + 7) * 2) * P
      k.box(x - P, x + P, Math.min(z0, z1), Math.max(z0, z1), -0.4 * T, h - 0.4 * T, {
        all: SAND[1],
        top: SAND[0],
      })
    }
  }
}

/** 一种风格的船；kind 0、1 是大船，2 是小舢板。废土没有小舢板（返回 null） */
export function boatModel(look: BoatLook, seed: number, kind: number): LandmarkModel | null {
  if (look === 'wasteland')
    return kind === 2 ? null : { build: (k) => wreck(k, seed), roll: 0.16 * (seed % 2 ? 1 : -1) }
  if (look === 'frozen') return { build: (k) => frozenBoat(k, seed, kind) }
  return { build: (k) => villageBoat(k, seed, kind), float: true }
}
