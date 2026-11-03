import * as THREE from 'three'
import { PIXEL } from '../grid'
import { footprint, placer, type Dock } from '../pixel/island'
import { hash, mixHex } from '../pixel/noise'
import { LAMP_GLOW } from '../palette'
import type { GroundPalette } from '../themes/types'
import { WALL_TEXEL } from './layout'
import { pixelMaterial } from './pixelSampling'
import { texture } from './standee'

// 栈桥：架在水上的木桥。根部一段跳板从码头斜着搭上来，桥面高出水面，底下一排排木桩插进水里，
// 尽头一块平台往前伸出去（L 形，见 island.ts 的 Dock），几根桩冒出桥面当系缆桩。桥面板横铺，一块两像素宽；
// 是立体的：镜头怎么转都看得见侧面和桩，影子落在水上，倒影里也有。桥下的水由海面画暗（见 calmOf）。
// 位置和尺寸来自 island.ts 的 Dock（地图坐标），这里按「沿桥 u、横过桥 v」的像素格搭。

/** 桥面高出地面多少、桥面板连托梁多厚（世界单位）；根部跳板占几个像素 */
export const PIER_DECK = 1.7 * WALL_TEXEL
const THICK = WALL_TEXEL
const RAMP = 4
/** 跳板根部搭在码头上的高度 */
const ROOT = 0.6
/** 桩：水下插多深，系缆桩冒出桥面多高，桩每隔几像素一根 */
const SINK = -3
const BOLLARD = 0.8 * WALL_TEXEL
const POST_GAP = 8

/** 桥面顶在 u 处的高度：跳板一段从 ROOT 斜到 PIER_DECK */
const topAt = (u: number) => (u >= RAMP ? PIER_DECK : ROOT + ((PIER_DECK - ROOT) * u) / RAMP)

/** 一点点攒起来的几何：四边形按给的法线自动定绕向，分材质记成几组 */
class Mesher {
  private pos: number[] = []
  private nor: number[] = []
  private uv: number[] = []
  private col: number[] = []
  private index: number[][] = []

  quad(
    corners: [number, number, number][],
    normal: [number, number, number],
    uvs: [number, number][],
    group: number,
    colors?: [number, number, number][]
  ) {
    const base = this.pos.length / 3
    corners.forEach((c, k) => {
      this.pos.push(...c)
      this.nor.push(...normal)
      this.uv.push(...uvs[k])
      this.col.push(...(colors?.[k] ?? [1, 1, 1]))
    })
    const [a, b, , d] = corners
    const e1 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]],
      e2 = [d[0] - a[0], d[1] - a[1], d[2] - a[2]]
    const facing =
      (e1[1] * e2[2] - e1[2] * e2[1]) * normal[0] +
      (e1[2] * e2[0] - e1[0] * e2[2]) * normal[1] +
      (e1[0] * e2[1] - e1[1] * e2[0]) * normal[2]
    const list = (this.index[group] ??= [])
    if (facing >= 0) list.push(base, base + 1, base + 2, base, base + 2, base + 3)
    else list.push(base, base + 2, base + 1, base, base + 3, base + 2)
  }

  build() {
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3))
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nor, 3))
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2))
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3))
    const all: number[] = []
    this.index.forEach((list, group) => {
      if (!list?.length) return
      g.addGroup(all.length, list.length, group)
      all.push(...list)
    })
    g.setIndex(all)
    return g
  }
}

/** 桥面贴图：沿桥一像素一列。板子横铺两像素宽、一像素浅缝，每块板深浅不一，零星几个木节；
 *  跳板上每隔一块板钉一道防滑条。gaps 是缺板的比例（废土），缺的板挖空，露出底下的水 */
function deckCanvas(d: Dock, G: GroundPalette, gaps: number, seed: number) {
  const { L, V, headU, inside } = footprint(d)
  const canvas = document.createElement('canvas')
  canvas.width = L
  canvas.height = V
  const ctx = canvas.getContext('2d')!
  const img = ctx.createImageData(L, V)
  const put = (u: number, v: number, hex: string) => {
    const n = parseInt(hex.slice(1), 16),
      o = (v * L + u) * 4
    img.data.set([n >> 16, (n >> 8) & 255, n & 255, 255], o)
  }
  for (let u = 0; u < L; u++) {
    const board = Math.floor(u / 3)
    const seam = u % 3 === 2
    if (gaps && u > RAMP && u < headU - 1 && !seam && hash(board, 3, seed) < gaps) continue
    const tone = G.plank[Math.floor(hash(board, 1, seed) * G.plank.length)]
    // 每块板两头差一点长短，桥边不是一刀切齐
    const short = hash(board, 2, seed)
    for (let v = 0; v < V; v++) {
      if (!inside(u, v)) continue
      const end = !inside(u, v - 1) || !inside(u, v + 1)
      if (end && !seam && short < 0.15) continue
      let c = seam ? mixHex(G.plankLine, tone, 0.5) : tone
      if (!seam && u % 3 === 0) c = mixHex(c, '#fff4dc', 0.1)
      if (!seam && hash(u, v, seed + 4) < 0.03) c = mixHex(c, G.plankLine, 0.5)
      if (u < RAMP && u % 2 === 1) c = mixHex(G.plankLine, tone, 0.3)
      put(u, v, c)
    }
  }
  ctx.putImageData(img, 0, 0)
  return canvas
}

/** 托梁的侧面：一像素一列横着重复，上半亮下半暗，每隔 POST_GAP 一颗螺栓 */
function sideCanvas(G: GroundPalette) {
  const canvas = document.createElement('canvas')
  canvas.width = POST_GAP
  canvas.height = 2
  const ctx = canvas.getContext('2d')!
  for (let u = 0; u < POST_GAP; u++) {
    ctx.fillStyle =
      u === 3 ? mixHex(G.plankLine, '#000000', 0.3) : mixHex(G.plank[1], '#1d2a2a', 0.25)
    ctx.fillRect(u, 0, 1, 1)
    ctx.fillStyle = mixHex(G.plank[0], '#1d2a2a', 0.5)
    ctx.fillRect(u, 1, 1, 1)
  }
  return canvas
}

/** 桥头的灯：一根木桩挑出一盏马灯；glass 为 true 时只画发光的灯罩 */
export function pierLampCanvas(glass: boolean) {
  const canvas = document.createElement('canvas')
  canvas.width = 7
  canvas.height = 18
  const ctx = canvas.getContext('2d')!
  const rect = (x: number, y: number, w: number, h: number, c: string) => {
    ctx.fillStyle = c
    ctx.fillRect(x, y, w, h)
  }
  if (!glass) {
    rect(1, 2, 1, 16, '#8a6440')
    rect(2, 2, 1, 16, '#5a3e28')
    rect(1, 1, 5, 1, '#5a3e28')
    rect(1, 0, 2, 1, '#a07850')
    rect(5, 2, 1, 1, '#2b282c')
    rect(4, 3, 3, 1, '#2b282c')
    rect(4, 7, 3, 1, '#2b282c')
  }
  rect(4, 4, 3, 3, LAMP_GLOW)
  return canvas
}

const rgb = (hex: string): [number, number, number] => {
  const c = new THREE.Color(hex)
  return [c.r, c.g, c.b]
}

export interface Pier {
  group: THREE.Group
  /** 桥面（朝上，接积雪、地面的灯光）、托梁侧面和桩（接墙面的灯光，系缆桩顶也积雪） */
  top: THREE.MeshLambertMaterial
  sides: THREE.MeshLambertMaterial
  posts: THREE.MeshLambertMaterial
  /** 尽头平台外角上立灯的地方、桥上能放杂物的几处（地图坐标） */
  lamp: [number, number]
  spots: [number, number][]
}

/** 搭一条栈桥。G 是风格包的地面配色（桥板沿用码头的木色），gaps 是废土缺板的比例 */
export function pier(d: Dock, G: GroundPalette, gaps: number, seed: number): Pier {
  const at = placer(d)
  const { L, V, W, headU, inside } = footprint(d)
  const group = new THREE.Group()

  // 桥面：跳板一块斜面，其余一块平面（平台以外的地方贴图是透明的）
  const deck = new Mesher()
  const top = (u0: number, u1: number, va: number, vb: number) => {
    const corners = [
      [u0, va],
      [u1, va],
      [u1, vb],
      [u0, vb],
    ].map(([u, v]) => {
      const [x, z] = at(u, v)
      return [x, topAt(u), z] as [number, number, number]
    })
    const uvs = [
      [u0, va],
      [u1, va],
      [u1, vb],
      [u0, vb],
    ].map(([u, v]) => [u / L, 1 - v / V] as [number, number])
    deck.quad(corners, [0, 1, 0], uvs, 0)
  }
  top(0, RAMP, 0, W)
  top(RAMP, L, 0, V)
  const deckMap = texture(deckCanvas(d, G, gaps, seed))
  const topMaterial = pixelMaterial(new THREE.MeshLambertMaterial({ map: deckMap, alphaTest: 0.5 }))
  const deckMesh = new THREE.Mesh(deck.build(), topMaterial)
  deckMesh.castShadow = deckMesh.receiveShadow = true
  // 投影也按贴图挖空：缺板的地方漏光
  deckMesh.customDepthMaterial = pixelMaterial(
    new THREE.MeshDepthMaterial({
      depthPacking: THREE.RGBADepthPacking,
      map: deckMap,
      alphaTest: 0.5,
    })
  )
  topMaterial.addEventListener('dispose', () => deckMesh.customDepthMaterial?.dispose())
  group.add(deckMesh)

  // 侧面：桥面形状的每段外沿往下一道托梁，跳板那段跟着斜；再加桩和系缆桩
  const frame = new Mesher()
  const side = (u0: number, v0s: number, u1: number, v1s: number, normal: [number, number]) => {
    const [xa, za] = at(u0, v0s),
      [xb, zb] = at(u1, v1s)
    const ya = topAt(u0),
      yb = topAt(u1)
    const run = Math.abs(u1 - u0) + Math.abs(v1s - v0s)
    const n: [number, number, number] = [normal[0], 0, normal[1]]
    frame.quad(
      [
        [xa, ya - THICK, za],
        [xb, yb - THICK, zb],
        [xb, yb, zb],
        [xa, ya, za],
      ],
      n,
      [
        [0, 0],
        [run, 0],
        [run, 1],
        [0, 1],
      ],
      0
    )
  }
  // 沿桥方向 (u) 和横过桥方向 (v) 在世界里的朝向，用来给侧面定法线
  const [ox, oz] = at(0, 0)
  const [ux, uz] = at(1, 0)
  const [vx, vz] = at(0, 1)
  const U: [number, number] = [(ux - ox) / PIXEL, (uz - oz) / PIXEL],
    Vd: [number, number] = [(vx - ox) / PIXEL, (vz - oz) / PIXEL]
  const neg = (p: [number, number]): [number, number] => [-p[0], -p[1]]
  // 横过桥的两条长边：按 u 一段段走，跳板转折处断开（侧面上沿跟着斜）
  for (let v = 0; v <= V; v++)
    for (const below of [true, false]) {
      let start = -1
      for (let u = 0; u <= L; u++) {
        const edge =
          u < L && (below ? inside(u, v - 1) && !inside(u, v) : inside(u, v) && !inside(u, v - 1))
        if (edge && start < 0) start = u
        if ((!edge || u === RAMP) && start >= 0 && u > start) {
          side(start, v, u, v, below ? Vd : neg(Vd))
          start = edge ? u : -1
        }
      }
    }
  // 沿桥的两条短边（根部、平台两侧和尽头）
  for (let u = 0; u <= L; u++)
    for (const after of [true, false]) {
      let start = -1
      for (let v = 0; v <= V; v++) {
        const edge =
          v < V && (after ? inside(u - 1, v) && !inside(u, v) : inside(u, v) && !inside(u - 1, v))
        if (edge && start < 0) start = v
        if (!edge && start >= 0) {
          side(u, start, u, v, after ? U : neg(U))
          start = -1
        }
      }
    }

  // 桩：一像素见方，从水下插到桥面底下；平台四角和桥身与平台相接处的桩冒出桥面
  const wood = rgb(mixHex(G.plank[0], '#1d2a2a', 0.45)),
    wet = rgb(mixHex(G.plank[0], '#2f4a3c', 0.6)),
    grain = rgb(mixHex(G.plank[2], '#fff4dc', 0.2))
  const post = (u: number, v: number, tall: boolean) => {
    const yTop = tall ? PIER_DECK + BOLLARD : topAt(u) - THICK
    const corners = [
      [u, v],
      [u + 1, v],
      [u + 1, v + 1],
      [u, v + 1],
    ].map(([a, b]) => at(a, b))
    for (let k = 0; k < 4; k++) {
      const [xa, za] = corners[k],
        [xb, zb] = corners[(k + 1) % 4]
      const nx = zb - za,
        nz = -(xb - xa)
      const len = Math.hypot(nx, nz) || 1
      // 法线朝外：桩中心指向这条边中点
      const [cx, cz] = at(u + 0.5, v + 0.5)
      const out = nx * ((xa + xb) / 2 - cx) + nz * ((za + zb) / 2 - cz) >= 0 ? 1 : -1
      frame.quad(
        [
          [xa, SINK, za],
          [xb, SINK, zb],
          [xb, yTop, zb],
          [xa, yTop, za],
        ],
        [(out * nx) / len, 0, (out * nz) / len],
        [
          [0, 0],
          [1, 0],
          [1, 1],
          [0, 1],
        ],
        1,
        [wet, wet, wood, wood]
      )
    }
    if (tall)
      frame.quad(
        corners.map(([x, z]) => [x, yTop, z] as [number, number, number]),
        [0, 1, 0],
        [
          [0, 0],
          [1, 0],
          [1, 1],
          [0, 1],
        ],
        1,
        [grain, grain, grain, grain]
      )
  }
  // 系缆桩：桥身后沿两根（船系在这里），平台的三个外角（第四个角立灯）
  const tall = new Set<string>()
  const bollards: [number, number][] = [
    [Math.max(RAMP + 2, L - 30), 0],
    [L - 12, 0],
    [L - 1, 0],
    ...(V > W ? ([[headU, V - 1]] as [number, number][]) : []),
  ]
  for (const [u, v] of bollards) {
    tall.add(`${u},${v}`)
    post(u, v, true)
  }
  for (let u = RAMP + 1; u < L; u += POST_GAP / 2)
    for (let v = 0; v < V; v++) {
      if (!inside(u, v) || tall.has(`${u},${v}`)) continue
      if (!inside(u, v - 1) || !inside(u, v + 1)) post(u, v, false)
    }

  const sideMap = texture(sideCanvas(G))
  sideMap.wrapS = THREE.RepeatWrapping
  const sides = pixelMaterial(new THREE.MeshLambertMaterial({ map: sideMap }))
  const posts = new THREE.MeshLambertMaterial({ vertexColors: true })
  const frameMesh = new THREE.Mesh(frame.build(), [sides, posts])
  frameMesh.castShadow = frameMesh.receiveShadow = true
  group.add(frameMesh)

  // 灯立在尽头平台前面的外角（横向桥在南边、竖向桥在东边，朝镜头这边不被桥挡）；
  // 杂物一件放在桥身前沿靠根部，一件放在平台上
  const lamp = at(L - 1.5, V - 1.5)
  const spots: [number, number][] = [at(RAMP + 3 + Math.floor(hash(1, 5, seed) * 6), W - 1.6)]
  if (V > W) spots.push(at(headU + 2, V - 2))
  return { group, top: topMaterial, sides, posts, lamp, spots }
}
