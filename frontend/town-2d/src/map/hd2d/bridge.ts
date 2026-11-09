import * as THREE from 'three'
import { PIXEL } from '../grid'
import { CROWN, deckHeight, spanOf, type Bridge } from '../pixel/bridges'
import { hash, mixHex } from '../pixel/noise'
import type { GroundPalette } from '../themes/types'
import { WALL_TEXEL } from './layout'
import { Mesher, sideCanvas } from './pier'
import { pixelMaterial } from './pixelSampling'
import { texture } from './standee'

// 路过河的桥（位置和样子见 pixel/bridges.ts），立体的，镜头怎么转都看得见侧面，影子落在水上，倒影里也有：
// - 石拱桥：整座拱成一道弧，桥面铺石板，两边一道石栏压着亮的压顶石；桥身两侧开几孔拱，拱洞里看得见
//   拱顶的暗面，底下是水。
// - 木板桥：两头跳板、中间平，桥面板横铺；桥边一道托梁，一排木桩插进水里，桩头冒出桥面当栏杆柱，
//   上面一道扶手。
// 按「沿桥 s、横过桥 v」搭（地图单位，v 以桥面中线为 0），每 PIXEL 一段。

/** 石栏多厚、高出桥面多少；桥身侧面从水下这么深开始 */
const PARAPET = { thick: PIXEL, high: 1.5 * WALL_TEXEL }
const BOTTOM = -3
/** 水面高度（海面平面在地面下 1 个单位） */
const WATER = -1
/** 拱和拱之间的桥墩宽、一孔拱最宽多少（像素） */
const PIER_W = 3
const ARCH_MAX = 18
/** 木板桥：托梁多厚、栏杆高出桥面多少、桩每隔几像素一根 */
const BEAM = 0.8 * WALL_TEXEL
const RAIL = 1.6 * WALL_TEXEL
const POST_GAP = 6

export interface BuiltBridge {
  group: THREE.Group
  /** 朝上的（桥面、压顶，接积雪和地面的灯光）、侧面（接墙面的灯光）、木头和石头的零件（顶点色） */
  top: THREE.MeshLambertMaterial
  sides: THREE.MeshLambertMaterial
  parts: THREE.MeshLambertMaterial
}

interface Arch {
  /** 拱的中点（沿桥）、半跨、拱高（从水面量） */
  c: number
  r: number
  q: number
}

/** 水面这一段分成几孔拱：中间的大，拱高按那里桥面的高度留出拱顶上的一层石头 */
function archesOf(b: Bridge): Arch[] {
  const [w0, w1] = b.water
  const span = (w1 - w0) / PIXEL
  const n = Math.max(1, Math.round((span + PIER_W) / (ARCH_MAX + PIER_W)))
  const each = (span - (n - 1) * PIER_W) / n
  const out: Arch[] = []
  for (let k = 0; k < n; k++) {
    const r = (each * PIXEL) / 2
    const c = w0 + (k * (each + PIER_W) + each / 2) * PIXEL
    // 拱顶上至少留一层石头；拱的两脚落在水面上，拱高最多是半圆
    const top = Math.min(deckHeight(b, c - r * 0.5), deckHeight(b, c + r * 0.5))
    const q = Math.max(0, Math.min(r, top - WATER - 1.1 * WALL_TEXEL))
    if (q > WALL_TEXEL) out.push({ c, r, q })
  }
  return out
}

/** 拱洞上沿在沿桥 s 处的高度；不在拱下时是 -Infinity */
function archTop(arches: Arch[], s: number) {
  for (const a of arches) {
    const k = (s - a.c) / a.r
    if (Math.abs(k) < 1) return WATER + a.q * Math.sqrt(1 - k * k)
  }
  return -Infinity
}

/** 石拱桥的侧面贴图：一列一个地面像素、一行一个墙面像素，从水下往上。错缝的石块，水线一带发绿，
 *  拱洞挖空、绕一圈拱石，正中一块拱心石；最上一行是压顶石 */
function stoneSide(b: Bridge, arches: Arch[], G: GroundPalette, seed: number) {
  const L = spanOf(b)
  const cols = Math.ceil(L / PIXEL)
  const rows = Math.ceil((CROWN.stone + PARAPET.high - BOTTOM) / WALL_TEXEL) + 1
  const canvas = document.createElement('canvas')
  canvas.width = cols
  canvas.height = rows
  const ctx = canvas.getContext('2d')!
  const stones = [G.gate[0], G.gate[1] ?? G.gate[0], G.gate[2] ?? G.gate[0]]
  for (let u = 0; u < cols; u++) {
    const s = (u + 0.5) * PIXEL
    const top = deckHeight(b, s) + PARAPET.high
    const arch = archTop(arches, s)
    for (let r = 0; r < rows; r++) {
      const y = BOTTOM + (r + 0.5) * WALL_TEXEL
      if (y > top + WALL_TEXEL * 0.5) continue
      if (y < arch) continue
      // 贴图的行从上往下数
      const row = rows - 1 - r
      let c: string
      if (y > top - WALL_TEXEL * 0.5) c = mixHex(G.plazaLight, '#ffffff', 0.15)
      else if (y < arch + WALL_TEXEL) {
        // 拱石：一圈亮暗相间，正中一块拱心石
        const center = arches.find((a) => Math.abs(s - a.c) < a.r)!
        const key = Math.abs(s - center.c) < PIXEL
        c = key ? mixHex(G.plazaLight, '#ffffff', 0.25) : u % 2 ? stones[0] : G.gateLine
      } else {
        // 错缝石块：一行一层，每层的缝错开半块
        const joint = (u + (r % 2) * 2) % 5 === 0
        const block = Math.floor((u + (r % 2) * 2) / 5)
        c = joint ? G.gateLine : stones[Math.floor(hash(block, r, seed) * stones.length)]
        if (y < 3) c = mixHex(c, '#3f5a3c', 0.45)
      }
      ctx.fillStyle = c
      ctx.fillRect(u, row, 1, 1)
    }
  }
  return { canvas, rows }
}

/** 石拱桥的桥面：石板错缝铺，一块深浅不一，中线一道略亮的车辙石 */
function stoneDeck(b: Bridge, G: GroundPalette, seed: number) {
  const cols = Math.ceil(spanOf(b) / PIXEL),
    rows = Math.max(2, Math.round(b.width / PIXEL))
  const canvas = document.createElement('canvas')
  canvas.width = cols
  canvas.height = rows
  const ctx = canvas.getContext('2d')!
  for (let u = 0; u < cols; u++)
    for (let v = 0; v < rows; v++) {
      const off = (v >> 1) % 2 ? 2 : 0
      const joint = (u + off) % 4 === 0 || v % 2 === 0
      const slab = Math.floor((u + off) / 4)
      let c = joint ? G.plazaLine : G.plaza[Math.floor(hash(slab, v >> 1, seed) * G.plaza.length)]
      if (!joint && Math.abs(v - rows / 2) < 1) c = mixHex(c, G.plazaLight, 0.25)
      ctx.fillStyle = c
      ctx.fillRect(u, v, 1, 1)
    }
  return canvas
}

/** 木板桥的桥面：板子横铺，一块两像素宽、一像素浅缝，深浅不一 */
function woodDeck(b: Bridge, G: GroundPalette, seed: number) {
  const cols = Math.ceil(spanOf(b) / PIXEL),
    rows = Math.max(2, Math.round(b.width / PIXEL))
  const canvas = document.createElement('canvas')
  canvas.width = cols
  canvas.height = rows
  const ctx = canvas.getContext('2d')!
  for (let u = 0; u < cols; u++) {
    const seam = u % 3 === 2
    const tone = G.plank[Math.floor(hash(Math.floor(u / 3), 1, seed) * G.plank.length)]
    for (let v = 0; v < rows; v++) {
      let c = seam ? mixHex(G.plankLine, tone, 0.5) : tone
      if (!seam && hash(u, v, seed + 4) < 0.04) c = mixHex(c, G.plankLine, 0.5)
      if (v === 0 || v === rows - 1) c = mixHex(c, '#1d2a2a', 0.25)
      ctx.fillStyle = c
      ctx.fillRect(u, v, 1, 1)
    }
  }
  return canvas
}

const rgb = (hex: string): [number, number, number] => {
  const c = new THREE.Color(hex)
  return [c.r, c.g, c.b]
}

/** 搭一座桥。G 是风格包的地面配色：石拱桥用城门石色和广场石板，木板桥用码头的木色 */
export function bridge(b: Bridge, G: GroundPalette, seed: number): BuiltBridge {
  const L = spanOf(b)
  const dx = (b.b[0] - b.a[0]) / L,
    dz = (b.b[1] - b.a[1]) / L
  // 横过桥的方向（v 增大的方向）
  const nx = -dz,
    nz = dx
  const at = (s: number, v: number, y: number): [number, number, number] => [
    b.a[0] + dx * s + nx * v,
    y,
    b.a[1] + dz * s + nz * v,
  ]
  const steps = Math.ceil(L / PIXEL)
  const sAt = (k: number) => Math.min(L, k * PIXEL)
  const h = (s: number) => deckHeight(b, s)
  const half = b.width / 2
  const stone = b.style === 'stone'
  const group = new THREE.Group()
  const deck = new Mesher(),
    side = new Mesher(),
    parts = new Mesher()

  // 桥面：一段段跟着桥面的高度起伏；石拱桥的石栏占掉两边
  const inner = stone ? half - PARAPET.thick : half
  for (let k = 0; k < steps; k++) {
    const s0 = sAt(k),
      s1 = sAt(k + 1)
    deck.quad(
      [at(s0, -inner, h(s0)), at(s1, -inner, h(s1)), at(s1, inner, h(s1)), at(s0, inner, h(s0))],
      [0, 1, 0],
      [
        [s0 / L, 0],
        [s1 / L, 0],
        [s1 / L, 1],
        [s0 / L, 1],
      ],
      0
    )
  }

  let sideMap: THREE.Texture
  if (stone) {
    const arches = archesOf(b)
    const { canvas, rows } = stoneSide(b, arches, G, seed)
    sideMap = texture(canvas)
    const height = rows * WALL_TEXEL
    // 两侧的桥身连石栏外面：一列一段，上沿跟着石栏顶
    for (const sign of [-1, 1])
      for (let k = 0; k < steps; k++) {
        const s0 = sAt(k),
          s1 = sAt(k + 1)
        const t0 = h(s0) + PARAPET.high,
          t1 = h(s1) + PARAPET.high
        side.quad(
          [
            at(s0, sign * half, BOTTOM),
            at(s1, sign * half, BOTTOM),
            at(s1, sign * half, t1),
            at(s0, sign * half, t0),
          ],
          [nx * sign, 0, nz * sign],
          [
            [s0 / (steps * PIXEL), 0],
            [s1 / (steps * PIXEL), 0],
            [s1 / (steps * PIXEL), (t1 - BOTTOM) / height],
            [s0 / (steps * PIXEL), (t0 - BOTTOM) / height],
          ],
          0
        )
      }
    // 石栏里面一侧和压顶：顶点色
    const wall = rgb(G.gate[1] ?? G.gate[0]),
      cap = rgb(mixHex(G.plazaLight, '#ffffff', 0.15)),
      vault = rgb(mixHex(G.gateLine, '#1d2a2a', 0.45))
    for (const sign of [-1, 1])
      for (let k = 0; k < steps; k++) {
        const s0 = sAt(k),
          s1 = sAt(k + 1)
        const v = sign * inner
        parts.quad(
          [
            at(s0, v, h(s0)),
            at(s1, v, h(s1)),
            at(s1, v, h(s1) + PARAPET.high),
            at(s0, v, h(s0) + PARAPET.high),
          ],
          [-nx * sign, 0, -nz * sign],
          [
            [0, 0],
            [1, 0],
            [1, 1],
            [0, 1],
          ],
          0,
          [wall, wall, wall, wall]
        )
        parts.quad(
          [
            at(s0, v, h(s0) + PARAPET.high),
            at(s1, v, h(s1) + PARAPET.high),
            at(s1, sign * half, h(s1) + PARAPET.high),
            at(s0, sign * half, h(s0) + PARAPET.high),
          ],
          [0, 1, 0],
          [
            [0, 0],
            [1, 0],
            [1, 1],
            [0, 1],
          ],
          0,
          [cap, cap, cap, cap]
        )
      }
    // 石栏两头的端面
    for (const s of [0, L])
      for (const sign of [-1, 1])
        parts.quad(
          [
            at(s, sign * inner, h(s)),
            at(s, sign * half, h(s)),
            at(s, sign * half, h(s) + PARAPET.high),
            at(s, sign * inner, h(s) + PARAPET.high),
          ],
          [s ? dx : -dx, 0, s ? dz : -dz],
          [
            [0, 0],
            [1, 0],
            [1, 1],
            [0, 1],
          ],
          0,
          [wall, wall, cap, cap]
        )
    // 拱洞顶上的拱腹：横过整座桥的一道暗弧
    for (const a of arches) {
      const n = Math.max(4, Math.ceil((2 * a.r) / PIXEL))
      for (let k = 0; k < n; k++) {
        const s0 = a.c - a.r + (2 * a.r * k) / n,
          s1 = a.c - a.r + (2 * a.r * (k + 1)) / n
        const y0 = archTop([a], s0 + 1e-3),
          y1 = archTop([a], s1 - 1e-3)
        parts.quad(
          [at(s0, -half, y0), at(s1, -half, y1), at(s1, half, y1), at(s0, half, y0)],
          [0, -1, 0],
          [
            [0, 0],
            [1, 0],
            [1, 1],
            [0, 1],
          ],
          0,
          [vault, vault, vault, vault]
        )
      }
    }
  } else {
    sideMap = texture(sideCanvas(G))
    sideMap.wrapS = THREE.RepeatWrapping
    // 托梁：桥面两边往下一道
    for (const sign of [-1, 1])
      for (let k = 0; k < steps; k++) {
        const s0 = sAt(k),
          s1 = sAt(k + 1)
        side.quad(
          [
            at(s0, sign * half, h(s0) - BEAM),
            at(s1, sign * half, h(s1) - BEAM),
            at(s1, sign * half, h(s1)),
            at(s0, sign * half, h(s0)),
          ],
          [nx * sign, 0, nz * sign],
          [
            [k, 0],
            [k + 1, 0],
            [k + 1, 1],
            [k, 1],
          ],
          0
        )
      }
    // 桩：一像素见方，水里的从水下插上来，冒出桥面当栏杆柱；扶手一道连着柱头
    const wood = rgb(mixHex(G.plank[0], '#1d2a2a', 0.45)),
      wet = rgb(mixHex(G.plank[0], '#2f4a3c', 0.6)),
      rail = rgb(mixHex(G.plank[2] ?? G.plank[0], '#fff4dc', 0.1))
    const box = (s: number, v: number, y0: number, y1: number, bottom = wood, topColor = wood) => {
      const c = [
        [s, v],
        [s + PIXEL, v],
        [s + PIXEL, v + PIXEL],
        [s, v + PIXEL],
      ].map(([a, w]) => at(a, w, 0))
      for (let k = 0; k < 4; k++) {
        const p = c[k],
          q = c[(k + 1) % 4]
        const ex = q[0] - p[0],
          ez = q[2] - p[2]
        const len = Math.hypot(ex, ez) || 1
        const mx = (p[0] + q[0]) / 2 - (c[0][0] + c[2][0]) / 2,
          mz = (p[2] + q[2]) / 2 - (c[0][2] + c[2][2]) / 2
        const out = ez * mx - ex * mz >= 0 ? 1 : -1
        parts.quad(
          [
            [p[0], y0, p[2]],
            [q[0], y0, q[2]],
            [q[0], y1, q[2]],
            [p[0], y1, p[2]],
          ],
          [(out * ez) / len, 0, (-out * ex) / len],
          [
            [0, 0],
            [1, 0],
            [1, 1],
            [0, 1],
          ],
          0,
          [bottom, bottom, topColor, topColor]
        )
      }
      parts.quad(
        c.map(([x, , z]) => [x, y1, z] as [number, number, number]),
        [0, 1, 0],
        [
          [0, 0],
          [1, 0],
          [1, 1],
          [0, 1],
        ],
        0,
        [rail, rail, rail, rail]
      )
    }
    const [w0, w1] = b.water
    for (let s = PIXEL; s < L - PIXEL; s += POST_GAP * PIXEL)
      for (const v of [-half, half - PIXEL]) {
        const inWater = s > w0 - PIXEL && s < w1
        box(s, v, inWater ? BOTTOM : 0, h(s + PIXEL / 2) + RAIL, inWater ? wet : wood)
      }
    // 扶手：两边各一道，跟着桥面起伏
    for (const v of [-half, half - PIXEL])
      for (let k = 1; k + 1 < steps; k++) {
        const s0 = sAt(k),
          s1 = sAt(k + 1)
        const y0 = h(s0) + RAIL,
          y1 = h(s1) + RAIL
        parts.quad(
          [at(s0, v, y0), at(s1, v, y1), at(s1, v + PIXEL, y1), at(s0, v + PIXEL, y0)],
          [0, 1, 0],
          [
            [0, 0],
            [1, 0],
            [1, 1],
            [0, 1],
          ],
          0,
          [rail, rail, rail, rail]
        )
        for (const w of [v, v + PIXEL])
          parts.quad(
            [at(s0, w, y0 - 3), at(s1, w, y1 - 3), at(s1, w, y1), at(s0, w, y0)],
            [w === v ? -nx : nx, 0, w === v ? -nz : nz],
            [
              [0, 0],
              [1, 0],
              [1, 1],
              [0, 1],
            ],
            0,
            [wood, wood, rail, rail]
          )
      }
  }

  const deckMap = texture(stone ? stoneDeck(b, G, seed) : woodDeck(b, G, seed))
  const top = pixelMaterial(new THREE.MeshLambertMaterial({ map: deckMap }))
  const deckMesh = new THREE.Mesh(deck.build(), top)
  deckMesh.castShadow = deckMesh.receiveShadow = true
  group.add(deckMesh)

  const sides = pixelMaterial(
    new THREE.MeshLambertMaterial({
      map: sideMap,
      alphaTest: 0.5,
      side: stone ? THREE.DoubleSide : THREE.FrontSide,
    })
  )
  const sideMesh = new THREE.Mesh(side.build(), sides)
  sideMesh.castShadow = sideMesh.receiveShadow = true
  // 投影也按贴图挖空：拱洞底下透光
  sideMesh.customDepthMaterial = pixelMaterial(
    new THREE.MeshDepthMaterial({
      depthPacking: THREE.RGBADepthPacking,
      map: sideMap,
      alphaTest: 0.5,
    })
  )
  sides.addEventListener('dispose', () => sideMesh.customDepthMaterial?.dispose())
  group.add(sideMesh)

  const partsMaterial = new THREE.MeshLambertMaterial({
    vertexColors: true,
    side: THREE.DoubleSide,
  })
  const partsMesh = new THREE.Mesh(parts.build(), partsMaterial)
  partsMesh.castShadow = partsMesh.receiveShadow = true
  group.add(partsMesh)
  return { group, top, sides, parts: partsMaterial }
}
