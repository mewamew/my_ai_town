import * as THREE from 'three'
import { PIXEL } from '../grid'
import { hash, mixHex } from '../pixel/noise'
import { FLOOR_RISE, STAGE_RISE, STAND_SPAN, STEP_RISE, type Stand } from '../pixel/stands'
import type { GroundPalette } from '../themes/types'
import { WALL_TEXEL } from './layout'
import { Mesher } from './pier'

// 立体的看台（几何见 pixel/stands.ts），镜头怎么转都看得见台阶的立面，影子落在下一级上：
// - 台阶：每级踏面铺砂岩石板、错缝，前沿一道亮的压边；立面是灰石。两条走道把台阶分成三片，
//   走道里每级多一个半高的小台阶，铺浅色石头。
// - 背后一道挡墙、两头的侧墙随台阶一级级收，灰石砌块一层层错缝。
// - 正中的圆形小舞台铺一圈圈石板，正中一块亮的圆心石，外沿一圈压边；舞台四周一圈石板地，
//   敞开的那一面多铺出去一级台阶那么深。
// 按「离舞台中心 d、偏离背后正中 a」搭，一段约一个地图像素宽，顶点色上色；光照、投影、积雪交给材质。

export interface BuiltStand {
  group: THREE.Group
  /** 朝上的面（踏面、舞台、石板地，接积雪和地面的灯光）、立着的面（立面、挡墙，接墙面的灯光） */
  top: THREE.MeshLambertMaterial
  sides: THREE.MeshLambertMaterial
}

type Vec = [number, number, number]

const UV: [number, number][] = [
  [0, 0],
  [1, 0],
  [1, 1],
  [0, 1],
]
const UP: Vec = [0, 1, 0]
/** 沿弧几段一块石板；走道多宽（地图单位） */
const BLOCK = 5
const AISLE = 3 * PIXEL
/** 挡墙、侧墙的砌块一层多高（世界单位） */
const COURSE = 1.25 * WALL_TEXEL

/** 一个面四个角同一种颜色（顶点色） */
function flat(hex: string): Vec[] {
  const c = new THREE.Color(hex)
  const v: Vec = [c.r, c.g, c.b]
  return [v, v, v, v]
}

/** worn 为 true 时是废弃的：石板缺角、裂缝，积着土（废土） */
export function buildStand(s: Stand, G: GroundPalette, seed: number, worn = false): BuiltStand {
  const top = new Mesher(),
    side = new Mesher()
  const [bx, by] = [-s.facing[0], -s.facing[1]]
  // 背后正中转过 a 的方向（和 standPolar 的角度一致）
  const dir = (a: number): [number, number] => [
    bx * Math.cos(a) - by * Math.sin(a),
    bx * Math.sin(a) + by * Math.cos(a),
  ]
  const at = (d: number, a: number, h: number): Vec => {
    const [ux, uy] = dir(a)
    return [s.x + ux * d, h, s.y + uy * d]
  }
  /** 沿半径朝外（sign 为 -1 时朝圆心）的水平方向 */
  const out = (a: number, sign = 1): Vec => {
    const [ux, uy] = dir(a)
    return [ux * sign, 0, uy * sign]
  }
  /** 平铺的一块：d0～d1、角度 p～q、高 h */
  const lay = (d0: number, d1: number, p: number, q: number, h: number, c: string) =>
    top.quad([at(d0, p, h), at(d0, q, h), at(d1, q, h), at(d1, p, h)], UP, UV, 0, flat(c))
  /** 立着的一块弧面：半径 d、角度 p～q、从 h0 到 h1 */
  const rise = (d: number, p: number, q: number, h0: number, h1: number, n: Vec, c: string) =>
    side.quad([at(d, p, h0), at(d, q, h0), at(d, q, h1), at(d, p, h1)], n, UV, 0, flat(c))

  // 积土、裂缝（废土）
  const age = (c: string, i: number, j: number) => {
    if (!worn) return c
    const k = hash(i, j, seed + 31)
    return k < 0.12 ? mixHex(c, G.dirt[0], 0.55) : k < 0.2 ? G.plazaLine : c
  }
  const slab = (i: number, j: number) =>
    age(G.plaza[Math.floor(hash(i, j, seed) * G.plaza.length)], i, j)
  const block = (i: number, j: number) =>
    age(G.gate[Math.floor(hash(i, j, seed + 7) * G.gate.length)], i, j)
  /** 砌块墙上一格：每 BLOCK + 1 段一道竖缝，隔层错开 */
  const masonry = (i: number, row: number, salt: number) => {
    const j = i + (row % 2) * 3
    return j % (BLOCK + 1) === 0
      ? G.gateLine
      : riser(block(Math.floor(j / (BLOCK + 1)), row + salt))
  }
  const lip = mixHex(G.plazaLight, '#ffffff', 0.1)
  const aisleStone = mixHex(G.plaza[0], G.plazaLight, 0.45)
  function riser(c: string) {
    return mixHex(c, '#3a3440', 0.1)
  }

  /** 一整圈（或一段弧）平铺：d0～d1、角度 a0～a1、高 h，按段上色 */
  const ring = (
    d0: number,
    d1: number,
    a0: number,
    a1: number,
    h: number,
    color: (i: number, n: number) => string
  ) => {
    const n = Math.max(6, Math.ceil(((a1 - a0) * d1) / PIXEL))
    const da = (a1 - a0) / n
    for (let i = 0; i < n; i++) lay(d0, d1, a0 + i * da, a0 + (i + 1) * da, h, color(i, n))
  }
  /** 一整圈（或一段弧）朝外的砌块墙：半径 d、角度 a0～a1、从地面到 h，一层 course 高 */
  const wall = (d: number, a0: number, a1: number, h: number, salt: number, course = h) => {
    const n = Math.max(6, Math.ceil(((a1 - a0) * d) / PIXEL))
    const da = (a1 - a0) / n
    const rows = Math.max(1, Math.round(h / course))
    for (let row = 0; row < rows; row++)
      for (let i = 0; i < n; i++) {
        const p = a0 + i * da
        const [y0, y1] = [(h * row) / rows, (h * (row + 1)) / rows]
        rise(d, p, p + da, y0, y1, out(p + da / 2), masonry(i, row, salt))
      }
  }

  // 走道：把台阶分成三片的两条，角度按每级的中线算
  const aisles = [-STAND_SPAN / 3, STAND_SPAN / 3]
  const inAisle = (a: number, d: number) =>
    s.tiers > 1 && aisles.some((c) => Math.abs(a - c) * d < AISLE / 2)

  // 台阶：踏面（前沿压边 + 石板）、立面；走道里每级多一个半高的小台阶
  for (let k = 0; k < s.tiers; k++) {
    const d0 = s.inner + k * s.depth,
      d1 = d0 + s.depth,
      half = d0 + s.depth / 2
    const h0 = k * STEP_RISE,
      h1 = (k + 1) * STEP_RISE,
      hm = (h0 + h1) / 2
    const n = Math.max(8, Math.ceil((2 * STAND_SPAN * d1) / PIXEL))
    const da = (2 * STAND_SPAN) / n
    const stagger = (k * 2) % BLOCK
    for (let i = 0; i < n; i++) {
      const p = -STAND_SPAN + i * da,
        q = p + da
      const front = out((p + q) / 2, -1)
      if (inAisle((p + q) / 2, half)) {
        lay(d0, half, p, q, hm, lip)
        lay(half, d1, p, q, h1, aisleStone)
        rise(d0, p, q, h0, hm, front, riser(aisleStone))
        rise(half, p, q, hm, h1, front, riser(aisleStone))
        continue
      }
      const j = i + stagger
      const joint = j % BLOCK === 0
      lay(d0, d0 + PIXEL, p, q, h1, joint ? G.plazaLine : lip)
      lay(d0 + PIXEL, d1, p, q, h1, joint ? G.plazaLine : slab(Math.floor(j / BLOCK), k))
      rise(d0, p, q, h0, h1, front, joint ? G.gateLine : riser(block(Math.floor(j / BLOCK), k)))
    }
  }

  // 背后的挡墙
  wall(s.r, -STAND_SPAN, STAND_SPAN, s.tiers * STEP_RISE, 20, COURSE)
  // 两头的侧墙：跟着台阶一级级收
  for (const sign of [-1, 1]) {
    const a = sign * STAND_SPAN
    const [tx, ty] = dir(a + (sign * Math.PI) / 2)
    const normal: Vec = [tx, 0, ty]
    const steps = Math.max(1, Math.ceil(s.depth / PIXEL))
    for (let k = 0; k < s.tiers; k++) {
      const d0 = s.inner + k * s.depth,
        h1 = (k + 1) * STEP_RISE
      const rows = Math.max(1, Math.round(h1 / COURSE))
      for (let row = 0; row < rows; row++)
        for (let i = 0; i < steps; i++) {
          const [e0, e1] = [d0 + (s.depth * i) / steps, d0 + (s.depth * (i + 1)) / steps]
          const [y0, y1] = [(h1 * row) / rows, (h1 * (row + 1)) / rows]
          side.quad(
            [at(e0, a, y0), at(e1, a, y0), at(e1, a, y1), at(e0, a, y1)],
            normal,
            UV,
            0,
            flat(masonry(i + k * steps, row, 40))
          )
        }
    }
  }

  // 舞台：一圈圈石板，正中一块亮的圆心石，外沿一圈压边；侧面灰石
  const rings = Math.max(2, Math.round(s.stage / (2 * PIXEL)))
  const center = mixHex(G.plazaLight, '#ffffff', 0.2)
  for (let j = 0; j < rings; j++)
    ring((s.stage * j) / rings, (s.stage * (j + 1)) / rings, -Math.PI, Math.PI, STAGE_RISE, (i) =>
      j === 0
        ? center
        : j === rings - 1
          ? lip
          : i % 6 === 0
            ? G.plazaLine
            : (G.plaza[(j % 2) * 2] ?? G.plaza[0])
    )
  wall(s.stage, -Math.PI, Math.PI, STAGE_RISE, 60)
  // 舞台四周的石板地：一整圈压到第一级底下，敞开的一面多铺出去一级台阶那么深
  ring(s.stage, s.inner + PIXEL, -Math.PI, Math.PI, FLOOR_RISE, (i) =>
    i % BLOCK === 0 ? G.plazaLine : slab(Math.floor(i / BLOCK), 70)
  )
  const apron = s.inner + Math.min(s.depth, s.r - s.inner)
  ring(s.inner + PIXEL, apron, STAND_SPAN, 2 * Math.PI - STAND_SPAN, FLOOR_RISE, (i, n) =>
    i % BLOCK === 0 || i === n - 1 ? G.plazaLine : slab(Math.floor(i / BLOCK), 80)
  )

  const group = new THREE.Group()
  const topMaterial = new THREE.MeshLambertMaterial({ vertexColors: true })
  const sideMaterial = new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide })
  for (const [mesher, material] of [
    [top, topMaterial],
    [side, sideMaterial],
  ] as const) {
    const mesh = new THREE.Mesh(mesher.build(), material)
    mesh.castShadow = mesh.receiveShadow = true
    group.add(mesh)
  }
  return { group, top: topMaterial, sides: sideMaterial }
}
