import * as THREE from 'three'
import { PIXEL } from '../grid'
import { FOUNTAIN, type Fountain } from '../pixel/fountains'
import { crack, hash, mixHex, rng } from '../pixel/noise'
import { WALL_TEXEL } from './layout'
import { Mesher } from './pier'
import { pixelMaterial } from './pixelSampling'
import { texture } from './standee'

// 立体的喷泉（立在哪、多大见 pixel/fountains.ts），镜头怎么转都对：贴地一圈矮台阶，八角石池的池壁砌两层石块，
// 压一圈池沿（和长椅一样高，喷泉边的座位让人坐在上面）；池心石座托着下盘，下盘里一根细柱托着上盘，顶上一颗石珠。
// 风格包的 landmarks.fountain 选样子：
// - flowing：上盘沿八股水落进下盘，下盘沿十二股划着弧落进池子，石珠顶上冒水再落回上盘（粒子，见 FountainSpray）；
//   池面和盘里的水是逐帧贴图，落水的那一圈翻白，水纹往里外推，零星闪光。入夜池底的灯把水照亮。
// - frozen：水冻成冰、积着雪，池沿和盘沿压雪；盘沿挂一圈冰溜子，下盘有几股水冻成冰柱一直连到池面。
// - dry：池底干得龟裂，扔着碎石和一只轮胎；池沿塌了一段，上盘缺了口，石珠没了只剩一截断茬，石头脏旧。
// 水平一格一个地图像素，竖直一格一个墙面像素，和房子、道具的像素一样大。

export type FountainLook = 'flowing' | 'frozen' | 'dry'

const P = PIXEL
const T = WALL_TEXEL
const N = 8

interface Palette {
  stone: string[]
  joint: string
  cap: string
  capEdge: string
  plinth: string[]
  /** 池壁最底下一行零星的颜色：青苔、积雪、污渍 */
  foot: string
  shaft: string
}

const SNOW = '#f2f5f8'
const SNOW_SHADE = '#d6dee8'

const PALETTES: Record<FountainLook, Palette> = {
  flowing: {
    stone: ['#d9cdb2', '#cfc2a6', '#c4b697'],
    joint: '#9a8a6c',
    cap: '#ece4d0',
    capEdge: '#d4c9b0',
    plinth: ['#b9ad95', '#ada08a', '#a3967f'],
    foot: '#9a9a72',
    shaft: '#e4dac4',
  },
  frozen: {
    stone: ['#cdc8bf', '#c0bbb2', '#b3aea5'],
    joint: '#8e8a84',
    cap: SNOW,
    capEdge: SNOW_SHADE,
    plinth: ['#b2b4b6', '#a8aaae', '#9ea2a6'],
    foot: SNOW,
    shaft: '#dcd8d0',
  },
  dry: {
    stone: ['#b9b09c', '#aaa18d', '#9c937f'],
    joint: '#776f62',
    cap: '#cbc2ad',
    capEdge: '#a8a08c',
    plinth: ['#9a917e', '#8e8673', '#847c6a'],
    foot: '#6e604a',
    shaft: '#bdb4a0',
  },
}

const WATER = '#4f88a6'
const WATER_DEEP = '#3f7593'
const WATER_SKY = '#5d97b3'
const RIPPLE = '#7db4ca'
const GLINT = '#cfe6ee'
const FOAM = '#eef7fa'
const ICE = ['#bcd6e6', '#c8dfec', '#b2cfe2']
const ICE_CRACK = '#8fb2c8'
const ICICLE = '#d8ecf6'
const DUST = ['#9a8a6a', '#8f7f60', '#a49474']
const DUST_CRACK = '#5e5040'
const RUBBLE = ['#8a8272', '#9c9484', '#7a7264']

type Vec = [number, number, number]
const UV: [number, number][] = [
  [0, 0],
  [1, 0],
  [1, 1],
  [0, 1],
]

const tints = new Map<string, Vec[]>()
/** 四个顶点同色；tone > 0 往暖白提亮，< 0 往暗紫压（同道具积木） */
function tint(hex: string, tone: number): Vec[] {
  const key = hex + tone.toFixed(3)
  let c = tints.get(key)
  if (!c) {
    const mixed = tone >= 0 ? mixHex(hex, '#fff6e2', tone) : mixHex(hex, '#241c2c', -tone)
    const { r, g, b } = new THREE.Color(mixed)
    c = [
      [r, g, b],
      [r, g, b],
      [r, g, b],
      [r, g, b],
    ]
    tints.set(key, c)
  }
  return c
}

/** 立着的面按朝向分明暗：光从左上来，朝南的是本色，东面、北面背光 */
const toneOf = (nx: number, nz: number) => -0.11 + 0.11 * nz - 0.045 * nx

/** 正 sides 边形第 k 个角的方向（一条边正对南面）、第 k 条边的朝向 */
const corner = (k: number, sides = N) => ((k + 0.5) / sides) * Math.PI * 2
const faceAngle = (k: number, sides = N) => ((k + 1) / sides) * Math.PI * 2

/** 逐帧的水面贴图：size×size 一帧，横排 frames 帧。paint 按离中心多远 d、方位 a（像素、弧度）给一格的颜色 */
function sheet(
  size: number,
  frames: number,
  paint: (x: number, y: number, d: number, a: number, f: number) => string
) {
  const canvas = document.createElement('canvas')
  canvas.width = size * frames
  canvas.height = size
  const ctx = canvas.getContext('2d')!
  const c = (size - 1) / 2
  for (let f = 0; f < frames; f++)
    for (let y = 0; y < size; y++)
      for (let x = 0; x < size; x++) {
        const dx = x - c,
          dy = y - c
        const d = Math.hypot(dx, dy)
        if (d > size / 2 + 0.5) continue
        ctx.fillStyle = paint(x, y, d, Math.atan2(dy, dx), f)
        ctx.fillRect(f * size + x, y, 1, 1)
      }
  return canvas
}

/** 流动的水：底色靠池壁深一些、零星映着天色；落水的那一圈翻白闪动，水纹从那一圈往里、往外各推一道，零星闪光 */
function flowingWater(size: number, landing: number, inner: number, frames: number, seed: number) {
  const edge = size / 2
  return sheet(size, frames, (x, y, d, a, f) => {
    let color = d > edge - 1.6 ? WATER_DEEP : hash(x, y, seed) < 0.12 ? WATER_SKY : WATER
    const slot = Math.floor(((a + Math.PI) / (Math.PI * 2)) * 48)
    if (Math.abs(d - landing) < 0.75) {
      const k = hash(slot, f, seed + 3)
      color = k < 0.38 ? FOAM : k < 0.7 ? GLINT : RIPPLE
    } else if (Math.abs(d - landing) < 1.5 && hash(slot, f, seed + 4) < 0.35) color = RIPPLE
    for (const offset of [0, 0.5]) {
      const age = (f / frames + offset) % 1
      const out = landing + 1.2 + age * (edge - landing - 1.5)
      const back = landing - 1.2 - age * Math.max(0, landing - inner - 1.5)
      const on = (r: number) =>
        Math.abs(d - r) < 0.5 && hash(slot, Math.floor(age * 8), seed + 5) < 0.75 - age * 0.5
      if (on(out) || (back > inner + 0.5 && on(back))) color = age < 0.5 ? RIPPLE : WATER_SKY
    }
    if (hash(x * 7 + f, y * 3 - f, seed + 6) < 0.012) color = GLINT
    return color
  })
}

/** 冻住的水面：冰色深浅不一，几道裂纹从中间往外，靠池壁积一圈雪，冰里冻着几个气泡 */
function iceSheet(size: number, seed: number) {
  const edge = size / 2
  const rays = Array.from({ length: 5 }, (_, k) => (k / 5 + hash(k, 1, seed) * 0.15) * Math.PI * 2)
  return sheet(size, 1, (x, y, d, a) => {
    if (d > edge - 1.3 && hash(x, y, seed + 1) < 0.75)
      return hash(x, y, seed + 2) < 0.3 ? SNOW_SHADE : SNOW
    if (rays.some((r) => Math.abs(Math.sin(a - r)) * d < 0.55 && Math.cos(a - r) > 0) && d > 2)
      return ICE_CRACK
    if (hash(x, y, seed + 3) < 0.02) return '#eef6fa'
    return ICE[Math.floor(hash(x >> 1, y >> 1, seed + 4) * ICE.length)]
  })
}

/** 干了的池底：土色龟裂，零星碎石 */
function dustSheet(size: number, seed: number) {
  return sheet(size, 1, (x, y) => {
    if (crack(x, y, 4.5, seed + 9) < 0.55) return DUST_CRACK
    if (hash(x, y, seed + 10) < 0.06) return RUBBLE[Math.floor(hash(y, x, seed) * RUBBLE.length)]
    return DUST[Math.floor(hash(x >> 1, y >> 1, seed + 11) * DUST.length)]
  })
}

export interface BuiltFountain {
  group: THREE.Group
  /** 朝上的面（台阶、池沿、盘沿，接积雪和地面的灯光）、立着的面（池壁、柱子，接墙面的灯光） */
  top: THREE.MeshLambertMaterial
  sides: THREE.MeshLambertMaterial
  /** 池面和盘里的水（或冰、干池底）；flowing 的入夜按自身颜色发光 */
  water: THREE.MeshLambertMaterial[]
  /** 逐帧翻的贴图（flowing 才有） */
  flipbook?: { maps: THREE.Texture[]; frames: number; fps: number }
  /** 水花（flowing 才有） */
  spray?: FountainSpray
}

/** 搭一座喷泉 */
export function buildFountain(f: Fountain, look: FountainLook, seed: number): BuiltFountain {
  const { x, y } = f
  const s = f.scale
  const C = PALETTES[look]
  const top = new Mesher(),
    side = new Mesher()
  const random = rng(seed + 3)
  const at = (r: number, a: number, h: number): Vec => [x + Math.cos(a) * r, h, y + Math.sin(a) * r]
  const lerp3 = (p: Vec, q: Vec, t: number): Vec => [
    p[0] + (q[0] - p[0]) * t,
    p[1] + (q[1] - p[1]) * t,
    p[2] + (q[2] - p[2]) * t,
  ]

  /** 八角柱第 k 面：半径从 h1 处的 r1 到 h0 处的 r（斜着往外伸的是水盘的底），outward 为 false 时朝里；
   *  paint(k, u, v) 给第 u 列（沿边一像素一列）、第 v 行（从上往下一墙面像素一行）的颜色，null 空着 */
  type Paint = (k: number, u: number, v: number, nu: number, nv: number) => string | null
  const face = (
    k: number,
    r: number,
    h0: number,
    h1: number,
    paint: Paint,
    outward = true,
    r1 = r,
    extra = 0,
    cx = x,
    cz = y,
    sides = N
  ) => {
    const nv = Math.max(1, Math.round((h1 - h0) / T))
    const a0 = corner(k, sides),
      a1 = corner(k + 1, sides)
    const fa = faceAngle(k, sides)
    const n: Vec = outward ? [Math.cos(fa), 0, Math.sin(fa)] : [-Math.cos(fa), 0, -Math.sin(fa)]
    const tone = toneOf(n[0], n[2]) + extra
    const nu = Math.max(1, Math.round((2 * Math.max(r, r1) * Math.sin(Math.PI / sides)) / P))
    const pt = (rad: number, a: number, h: number): Vec => [
      cx + Math.cos(a) * rad,
      h,
      cz + Math.sin(a) * rad,
    ]
    for (let v = 0; v < nv; v++) {
      const ha = h1 - ((h1 - h0) * v) / nv,
        hb = h1 - ((h1 - h0) * (v + 1)) / nv
      const ra = r1 + ((r - r1) * v) / nv,
        rb = r1 + ((r - r1) * (v + 1)) / nv
      const A0 = pt(ra, a0, ha),
        A1 = pt(ra, a1, ha),
        B0 = pt(rb, a0, hb),
        B1 = pt(rb, a1, hb)
      let start = 0
      let last = paint(k, 0, v, nu, nv)
      for (let u = 1; u <= nu; u++) {
        const now = u < nu ? paint(k, u, v, nu, nv) : null
        if (u < nu && now === last) continue
        if (last) {
          const t0 = start / nu,
            t1 = u / nu
          const corners: Vec[] = outward
            ? [lerp3(A0, A1, t0), lerp3(A0, A1, t1), lerp3(B0, B1, t1), lerp3(B0, B1, t0)]
            : [lerp3(A1, A0, t0), lerp3(A1, A0, t1), lerp3(B1, B0, t1), lerp3(B1, B0, t0)]
          side.quad(corners, n, UV, 0, tint(last, tone))
        }
        start = u
        last = now
      }
    }
  }
  const band = (
    r: number,
    h0: number,
    h1: number,
    paint: Paint,
    outward = true,
    r1 = r,
    extra = 0,
    skip?: (k: number) => boolean
  ) => {
    for (let k = 0; k < N; k++) if (!skip?.(k)) face(k, r, h0, h1, paint, outward, r1, extra)
  }
  /** 一圈朝上的面：半径 r0（里）到 r1（外），高 h；沿边每 seg 像素一块 */
  const ring = (
    r0: number,
    r1: number,
    h: number,
    paint: (k: number, s: number) => string,
    seg = 3,
    skip?: (k: number) => boolean
  ) => {
    for (let k = 0; k < N; k++) {
      if (skip?.(k)) continue
      const a0 = corner(k),
        a1 = corner(k + 1)
      const ns = Math.max(1, Math.round((2 * r1 * Math.sin(Math.PI / N)) / P / seg))
      for (let i = 0; i < ns; i++) {
        const t0 = i / ns,
          t1 = (i + 1) / ns
        const O0 = lerp3(at(r1, a0, h), at(r1, a1, h), t0),
          O1 = lerp3(at(r1, a0, h), at(r1, a1, h), t1),
          I0 = lerp3(at(r0, a0, h), at(r0, a1, h), t0),
          I1 = lerp3(at(r0, a0, h), at(r0, a1, h), t1)
        top.quad([I0, I1, O1, O0], [0, 1, 0], UV, 0, tint(paint(k, i), 0.1))
      }
    }
  }
  /** 实心的柱子：sides 边形，中心 (cx, cz)，底下半径 r、顶上 r1；cap 给顶面的颜色 */
  const column = (
    cx: number,
    cz: number,
    r: number,
    h0: number,
    h1: number,
    paint: string | Paint,
    cap?: string,
    r1 = r,
    sides = N
  ) => {
    const p: Paint = typeof paint === 'string' ? () => paint : paint
    for (let k = 0; k < sides; k++) face(k, r, h0, h1, p, true, r1, 0, cx, cz, sides)
    if (!cap) return
    const c: Vec = [cx, h1, cz]
    const pt = (k: number): Vec => [
      cx + Math.cos(corner(k, sides)) * r1,
      h1,
      cz + Math.sin(corner(k, sides)) * r1,
    ]
    for (let k = 0; k < sides; k++)
      top.quad([c, c, pt(k + 1), pt(k)], [0, 1, 0], UV, 0, tint(cap, 0.1))
  }

  const stone: Paint = (k, u, v) => {
    // 砌块：一块四个像素长，隔行错开半块；块与块之间一道暗缝，块的深浅各不相同；废土的零星带着污渍
    const off = v % 2 ? 2 : 0
    const block = Math.floor((u + off) / 4)
    if ((u + off) % 4 === 0) return C.joint
    if (look === 'dry' && hash(k * 16 + block, v, seed + 12) < 0.18)
      return mixHex(C.foot, C.stone[1], 0.5)
    return C.stone[Math.floor(hash(k * 16 + block, v, seed + 1) * C.stone.length)]
  }

  const F = FOUNTAIN
  const R = { step: F.step * s, out: F.out * s, in: F.in * s }
  const capH = 0.5 * T
  const capOut = R.out + 0.6 * P
  // 废土塌掉的那一段池沿
  const broken = look === 'dry' ? Math.floor(hash(seed, 2, 7) * N) : -1
  const gone = (k: number) => k === broken

  // 贴地的台阶：冰雪积着雪
  band(R.step, 0, F.stepH, (k, u) => (u % 5 === 0 ? C.joint : C.plinth[(k + u) % 3]))
  ring(R.out, R.step, F.stepH, (k, i) => {
    if (look === 'frozen') return hash(k, i, seed + 2) < 0.75 ? SNOW : C.plinth[1]
    return C.plinth[Math.floor(hash(k, i, seed + 2) * 3)]
  })
  // 池壁外面两层砌块，最底下一行零星长青苔（积雪、污渍）；池沿压一圈石头，朝外多出半格
  const wallTop = F.rim - capH
  const wall: Paint = (k, u, v, nu, nv) =>
    v === nv - 1 && hash(k, u, seed + 7) < 0.22
      ? mixHex(C.foot, C.stone[2], 0.4)
      : stone(k, u, v, nu, nv)
  band(R.out, F.stepH, wallTop, wall, true, R.out, 0, gone)
  band(capOut, wallTop, F.rim, (k, u) => (u % 6 === 5 ? C.capEdge : C.cap), true, capOut, 0, gone)
  ring(R.in, capOut, F.rim, (k, i) => (i % 2 ? C.cap : mixHex(C.cap, C.capEdge, 0.5)), 3, gone)
  // 池壁里面：从池沿往下到水面（干池到池底）
  const floor = look === 'dry' ? F.water - 0.9 * T : F.water
  const inside: Paint = (k, u, v) => (v === 0 ? C.capEdge : stone(k, u, v + 1, 0, 0))
  band(R.in, floor, F.rim, inside, false, R.in, 0, gone)
  if (broken >= 0) {
    // 塌了的那一段：池沿没了，池壁矮一截，顶上露着断面，碎块落在台阶上
    const low = wallTop - 0.9 * T
    face(broken, R.out, F.stepH, low, wall)
    face(broken, R.in, floor, low, inside, false)
    ring(
      R.in,
      R.out,
      low,
      () => C.stone[2],
      2,
      (k) => k !== broken
    )
    for (let i = 0; i < 4; i++) {
      const a = corner(broken) + (0.2 + random() * 0.6) * (Math.PI / 4)
      const r = R.out + (1 + random() * 3) * P
      column(
        x + Math.cos(a) * r,
        y + Math.sin(a) * r,
        (0.6 + random() * 0.7) * P,
        F.stepH,
        F.stepH + (0.4 + random() * 0.6) * T,
        C.stone[i % 3],
        C.cap,
        undefined,
        4
      )
    }
  }

  // 池心：石座、石柱、下盘；高度跟着缩放
  const base = F.water + 3.2 * T * s
  column(
    x,
    y,
    3.8 * P * s,
    floor,
    base,
    (k, u, v, nu, nv) => (v === 0 ? C.cap : stone(k, u, v, nu, nv)),
    C.cap
  )
  column(x, y, 2.7 * P * s, base, base + 0.5 * T, C.capEdge, undefined, 2.2 * P * s)
  const shaft = base + 4.5 * T * s
  column(x, y, 2.2 * P * s, base + 0.5 * T, shaft, (k, u) => (u === 1 ? C.shaft : C.stone[1]))
  // 盘：底下往外斜着伸开，口沿一道边，盘里盛着水（冰、干的污渍）
  const bowl = (r: number, r0: number, h0: number, h1: number, lip: number, chipped = false) => {
    const nick = (k: number) => chipped && (k === 2 || k === 3)
    band(r, h0, h1, (k, u, v) => (v === 0 ? C.capEdge : C.stone[(u + v) % 3]), true, r0, -0.12)
    band(r, h1, h1 + lip, () => C.cap, true, r, 0, nick)
    ring(r - 0.8 * P * s, r, h1 + lip, () => (look === 'frozen' ? SNOW : C.cap), 4, nick)
    band(r - 0.8 * P * s, h1 + 0.2 * T, h1 + lip, () => C.capEdge, false, r - 0.8 * P * s, 0, nick)
  }
  const low = { r: 9.5 * P * s, h0: shaft - 0.4 * T * s, h1: shaft + 2 * T * s, lip: 0.6 * T }
  bowl(low.r, 2.2 * P * s, low.h0, low.h1, low.lip)
  const lowWater = low.h1 + 0.25 * T
  const upShaft = lowWater + 4.2 * T * s
  column(x, y, 1.6 * P * s, lowWater, upShaft, (k, u) => (u === 0 ? C.shaft : C.stone[0]))
  const up = { r: 5.6 * P * s, h0: upShaft - 0.4 * T * s, h1: upShaft + 1.4 * T * s, lip: 0.5 * T }
  bowl(up.r, 1.6 * P * s, up.h0, up.h1, up.lip, look === 'dry')
  const upWater = up.h1 + 0.2 * T
  // 石珠：干了的只剩一截断茬
  const stem = upWater + T * s
  column(
    x,
    y,
    1.1 * P * s,
    upWater,
    stem,
    C.stone[0],
    look === 'dry' ? C.capEdge : undefined,
    0.9 * P * s
  )
  let crown = stem
  if (look !== 'dry') {
    column(x, y, 1.5 * P * s, stem, stem + 0.8 * T * s, C.cap, undefined, 1.8 * P * s)
    column(x, y, 1.8 * P * s, stem + 0.8 * T * s, stem + 1.6 * T * s, C.cap, undefined, 1.2 * P * s)
    column(
      x,
      y,
      1.2 * P * s,
      stem + 1.6 * T * s,
      stem + 2.1 * T * s,
      C.capEdge,
      look === 'frozen' ? SNOW : C.cap,
      0.4 * P * s
    )
    crown = stem + 2.1 * T * s
  }

  // 冰溜子挂在盘沿；下盘几股水冻成冰柱，一直连到池面
  if (look === 'frozen') {
    const icicles = (r: number, lip: number, count: number, longest: number) => {
      for (let i = 0; i < count; i++) {
        const a = ((i + random() * 0.5) / count) * Math.PI * 2
        const len = (0.4 + random() * longest) * T
        const cx = x + Math.cos(a) * (r + 0.2 * P),
          cz = y + Math.sin(a) * (r + 0.2 * P)
        column(cx, cz, 0.45 * P, lip - len * 0.55, lip, ICICLE, undefined, 0.6 * P, 4)
        column(cx, cz, 0.2 * P, lip - len, lip - len * 0.55, ICICLE, undefined, 0.45 * P, 4)
      }
    }
    icicles(low.r, low.h1 + low.lip * 0.5, 14, 1.6)
    icicles(up.r, up.h1 + up.lip * 0.5, 9, 1.2)
    for (let i = 0; i < 4; i++) {
      const a = ((i + 0.3 + random() * 0.4) / 4) * Math.PI * 2
      const r = low.r + 0.9 * P * s
      const cx = x + Math.cos(a) * r,
        cz = y + Math.sin(a) * r
      column(cx, cz, 0.7 * P, F.water, F.water + 1.2 * T, ICICLE, undefined, 0.5 * P, 4)
      column(
        cx,
        cz,
        0.5 * P,
        F.water + 1.2 * T,
        low.h1 + low.lip * 0.5,
        ICICLE,
        undefined,
        0.6 * P,
        4
      )
    }
  }
  // 干池里的碎石和一只轮胎
  if (look === 'dry') {
    for (let i = 0; i < 5; i++) {
      const a = random() * Math.PI * 2
      const r = (4.5 + random() * 7.5) * P * s
      column(
        x + Math.cos(a) * r,
        y + Math.sin(a) * r,
        (0.5 + random() * 0.6) * P,
        floor,
        floor + (0.3 + random() * 0.5) * T,
        RUBBLE[i % 3],
        RUBBLE[(i + 1) % 3],
        undefined,
        4
      )
    }
    const a = random() * Math.PI * 2
    const r = 9 * P * s
    column(
      x + Math.cos(a) * r,
      y + Math.sin(a) * r,
      1.6 * P,
      floor,
      floor + 0.5 * T,
      '#1e1e1e',
      '#2e2e2c'
    )
    column(
      x + Math.cos(a) * r,
      y + Math.sin(a) * r,
      0.7 * P,
      floor + 0.5 * T,
      floor + 0.55 * T,
      '#3a3a36',
      DUST[0]
    )
  }

  // 水面（冰面、干池底）：池子、下盘、上盘各一张
  const flowing = look === 'flowing'
  const frames = flowing ? 12 : 1
  const lowReach = 3 * P * s,
    upReach = 1.6 * P * s
  const sheets = [
    { r: R.in, h: floor, landing: (low.r + 0.3 * P + lowReach) / P, inner: 3.8 * s },
    {
      r: low.r - 0.8 * P * s,
      h: lowWater,
      landing: (up.r + 0.3 * P + upReach) / P,
      inner: 1.6 * s,
    },
    { r: up.r - 0.7 * P * s, h: upWater, landing: 2.3 * s, inner: s },
  ]
  const group = new THREE.Group()
  const water: THREE.MeshLambertMaterial[] = []
  const maps: THREE.Texture[] = []
  sheets.forEach((w, i) => {
    const size = Math.max(4, Math.round((w.r * 2) / P))
    const own = seed + i * 11
    const canvas = flowing
      ? flowingWater(size, w.landing, w.inner, frames, own)
      : look === 'frozen'
        ? iceSheet(size, own)
        : dustSheet(size, own)
    const map = texture(canvas)
    map.repeat.x = 1 / frames
    // 流水入夜被池底的灯照亮：按自身颜色发光，场景按天黑程度给亮度
    const material = pixelMaterial(
      new THREE.MeshLambertMaterial(
        flowing
          ? { map, emissiveMap: map, emissive: new THREE.Color('#3f86ad'), emissiveIntensity: 0 }
          : { map }
      )
    )
    const disc = new THREE.Mesh(new THREE.CircleGeometry(w.r, N, Math.PI / N), material)
    disc.rotation.x = -Math.PI / 2
    disc.position.set(x, w.h, y)
    disc.receiveShadow = true
    group.add(disc)
    water.push(material)
    maps.push(map)
  })

  const topMaterial = new THREE.MeshLambertMaterial({ vertexColors: true })
  const sideMaterial = new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide })
  for (const [m, material] of [
    [top, topMaterial],
    [side, sideMaterial],
  ] as const) {
    const mesh = new THREE.Mesh(m.build(), material)
    mesh.castShadow = mesh.receiveShadow = true
    group.add(mesh)
  }

  if (!flowing) return { group, top: topMaterial, sides: sideMaterial, water }
  const spray = new FountainSpray(seed, [
    // 下盘沿十二股划着弧落进池子
    {
      x,
      y,
      r0: low.r + 0.3 * P,
      y0: low.h1 + low.lip * 0.6,
      reach: lowReach,
      up: 0.35 * T,
      drop: low.h1 + low.lip * 0.6 - F.water,
      streams: 12,
      drops: 24,
      seconds: 1.05,
    },
    // 上盘沿八股落进下盘
    {
      x,
      y,
      r0: up.r + 0.3 * P,
      y0: up.h1 + up.lip * 0.6,
      reach: upReach,
      up: 0.25 * T,
      drop: up.h1 + up.lip * 0.6 - lowWater,
      streams: 8,
      drops: 14,
      seconds: 0.75,
    },
    // 石珠顶上冒起来，落回上盘
    {
      x,
      y,
      r0: 0.1 * P,
      y0: crown,
      reach: 2.2 * P * s,
      up: 2.4 * T * s,
      drop: crown - upWater,
      streams: 6,
      drops: 14,
      seconds: 1.1,
    },
  ])
  return {
    group,
    top: topMaterial,
    sides: sideMaterial,
    water,
    flipbook: { maps, frames, fps: 8 },
    spray,
  }
}

/** 一圈水流：从半径 r0、高 y0 的一圈出发，往外 reach、先往上 up 再落下 drop（地图单位、世界单位）；
 *  streams 股，每股 drops 滴，落一趟 seconds 秒 */
interface Curtain {
  x: number
  y: number
  r0: number
  y0: number
  reach: number
  up: number
  drop: number
  streams: number
  drops: number
  seconds: number
}

const sprayVertex = /* glsl */ `
attribute float angle;
attribute vec4 path;
attribute vec4 motion;
uniform float time;
uniform float unitPx;
varying float vTint;
varying float vHide;
void main() {
  // path：起点半径、起点高度、往外多远、初速；motion：重力、相位、每秒几趟、颜色
  float t = fract(time * motion.z + motion.y);
  float r = path.x + path.z * t;
  float h = path.y + path.w * t - motion.x * t * t;
  vec3 p = position + vec3(cos(angle) * r, h, sin(angle) * r);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
  // 下半截断成一滴一滴：每一趟随机藏掉一些
  float lap = floor(time * motion.z + motion.y);
  float k = fract(sin(dot(vec2(motion.y * 91.7, lap), vec2(12.9898, 78.233))) * 43758.5453);
  vHide = step(0.62, t) * step(k, 0.18 + t * 0.25);
  // 一股水里每四滴一滴亮的，顺着水往下走；刚出口的一截最亮
  vTint = max(step(0.74, fract(motion.y * 4.0 + motion.w * 0.2)), 1.0 - step(0.12, t));
  gl_PointSize = max(1.0, ${PIXEL.toFixed(1)} * unitPx);
}`

const sprayFragment = /* glsl */ `
uniform vec3 light;
uniform vec3 glow;
varying float vTint;
varying float vHide;
void main() {
  if (vHide > 0.5) discard;
  vec3 c = mix(vec3(0.40, 0.62, 0.74), vec3(0.80, 0.91, 0.95), vTint);
  gl_FragColor = vec4(c * light + glow, 1.0);
}`

/** 喷泉的水花：一颗颗地图像素大的方点，沿抛物线落下；运动全在着色器里，主线程只更新时间 */
export class FountainSpray {
  readonly points: THREE.Points
  private readonly material: THREE.ShaderMaterial

  constructor(seed: number, curtains: Curtain[]) {
    const random = rng(seed + 71)
    const count = curtains.reduce((n, c) => n + c.streams * c.drops, 0)
    const pos = new Float32Array(count * 3),
      angle = new Float32Array(count),
      path = new Float32Array(count * 4),
      motion = new Float32Array(count * 4)
    let i = 0
    for (const c of curtains) {
      // 先往上 up 再落到 y0 - drop：初速 v、重力 g 满足 v - g = -drop、v²/4g = up
      const v = c.up > 0 ? 2 * c.up + 2 * Math.sqrt(c.up * c.up + c.up * c.drop) : 0
      const g = v + c.drop
      for (let k = 0; k < c.streams; k++) {
        const a = ((k + random() * 0.6) / c.streams) * Math.PI * 2
        const reach = c.reach * (0.8 + random() * 0.4)
        const rate = (1 / c.seconds) * (0.9 + random() * 0.2)
        const lean = 0.9 + random() * 0.2
        for (let d = 0; d < c.drops; d++, i++) {
          pos.set([c.x, 0, c.y], i * 3)
          angle[i] = a
          path.set([c.r0, c.y0, reach, v * lean], i * 4)
          motion.set([g * lean, (d + random() * 0.5) / c.drops, rate, random()], i * 4)
        }
      }
    }
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute('position', new THREE.BufferAttribute(pos, 3))
    geometry.setAttribute('angle', new THREE.BufferAttribute(angle, 1))
    geometry.setAttribute('path', new THREE.BufferAttribute(path, 4))
    geometry.setAttribute('motion', new THREE.BufferAttribute(motion, 4))
    this.material = new THREE.ShaderMaterial({
      vertexShader: sprayVertex,
      fragmentShader: sprayFragment,
      uniforms: {
        time: { value: 0 },
        unitPx: { value: 1 },
        light: { value: new THREE.Color(1, 1, 1) },
        glow: { value: new THREE.Color(0, 0, 0) },
      },
      depthWrite: false,
    })
    this.points = new THREE.Points(geometry, this.material)
    this.points.frustumCulled = false
  }

  /** 天光（线性色）和入夜池灯映上来的光 */
  setLight(light: THREE.Color, glow: THREE.Color) {
    ;(this.material.uniforms.light.value as THREE.Color).copy(light)
    ;(this.material.uniforms.glow.value as THREE.Color).copy(glow)
  }

  setScale(unitPx: number) {
    this.material.uniforms.unitPx.value = unitPx
  }

  step(now: number) {
    this.material.uniforms.time.value = now / 1000
  }
}
