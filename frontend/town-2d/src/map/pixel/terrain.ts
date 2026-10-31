import type { Atlas } from 'town-shared/mapDocument'
import { buildingKind } from '../buildings'
import { planDecor, type DecorPlan } from '../decor'
import { fromPx, MARGIN, OUTDOOR_SPACE, PIXEL, roomRect, toPx } from '../grid'
import { bayer, crack, fbm, hash, noise, pick } from './noise'
import { SNOW, SNOW_SHADE, WALL_CAP } from '../palette'
import { DEFAULT_EDGE_WIDTH } from '../route'
import { island, type Dock } from './island'
import type { GroundPalette, MapTheme } from '../themes/types'

// 地面按地面画布的像素算：地面、区域材质、水、海岸，再画上植被和房间。
// 画布一个像素 = PIXEL 个地图单位，镜头只按整数倍放大它。

/** 自带铺装的区域，路面不再盖一层土 */
const PAVED = new Set(['plaza', 'market', 'gate', 'harbor'])

const packed = new Map<string, number>()
function u(hex: string) {
  let v = packed.get(hex)
  if (v === undefined) {
    const n = parseInt(hex.slice(1), 16)
    v = ((255 << 24) | ((n & 255) << 16) | (((n >> 8) & 255) << 8) | (n >> 16)) >>> 0
    packed.set(hex, v)
  }
  return v
}
function mix(a: number, b: number, t: number) {
  const ch = (s: number) => {
    const x = (a >> s) & 255
    return Math.round(x + (((b >> s) & 255) - x) * t) << s
  }
  return ((255 << 24) | ch(16) | ch(8) | ch(0)) >>> 0
}
const SHADOW = u('#1d2a2a')

type Space = Atlas['spaces'][number]

/** 地面噪声的种子；固定下来，同一张地图每次打开长得一样 */
export const TERRAIN_SEED = 20260923

/**
 * 一张地图的地面，只算一次：立体场景、WebGL 不可用时的平面图和建镇缩略图都从它画。
 * base 是地面、区域材质、水面、海岸和浪花的像素，不含植被和房间（paintGround 再画上去）；
 * wet 标出外圈和水面像素（废土里外圈是干海床，也算在内），open 标出能种树的空地，
 * path 标出土路（2 是路中间的实土），立体场景在上面积水坑；depth 是水面离岸、陆地离水的像素数；
 * shore 标出海边的地物，立体场景按它画浪（见 shoreOf）；docks 是栈桥（地图坐标），船停在旁边
 */
export interface Ground {
  atlas: Atlas
  theme: MapTheme
  seed: number
  decor: DecorPlan
  width: number
  height: number
  base: Uint32Array
  wet: Uint8Array
  open: Uint8Array
  path: Uint8Array
  depth: Uint8Array
  shore: Uint8Array
  docks: Dock[]
}

export function groundOf(atlas: Atlas, theme: MapTheme, seed = TERRAIN_SEED): Ground {
  const decor = planDecor(atlas)
  const pw = Math.ceil((atlas.canvas.width + 2 * MARGIN) / PIXEL)
  const ph = Math.ceil((atlas.canvas.height + 2 * MARGIN) / PIXEL)
  const { region, wet } = rasterRegions(atlas, decor, pw, ph, seed)
  const kindAt = (i: number) => (region[i] < 0 ? '' : atlas.regions[region[i]].kind)
  const path = tracePaths(atlas, pw, ph, seed)
  const { content, built } = landMasks(atlas, region, wet, path, kindAt, pw, ph)
  const coast = coastOf(atlas, theme.ground, content, wet, pw, ph, seed)
  const layers: Layers = {
    pw,
    ph,
    seed,
    theme,
    kindAt,
    wet,
    path,
    built,
    ...coast,
    shoreWidth: shoreWidths(coast, wet, built, pw, ph, seed),
  }
  // 湾里的水浅：海面离岸的像素数按周围海的多少缩放，湾里的浅水带更宽，外海更快变深
  const { sea, depth, seaAround } = coast
  for (let y = 0; y < ph; y++)
    for (let x = 0; x < pw; x++) {
      const i = y * pw + x
      if (sea[i] && depth[i] < 30)
        depth[i] = Math.min(40, Math.round(depth[i] * (0.35 + seaAround(x, y) * 0.9)))
    }
  const base = new Uint32Array(pw * ph)
  paintBase(layers, base)
  paintShoreline(layers, base)
  // 栈桥换成地图坐标交给立体场景，船停在栈桥边上
  const docks = coast.docks.map((d) => ({
    ...d,
    x: fromPx(d.x),
    y: fromPx(d.y),
    length: d.length * PIXEL,
  }))
  const open = openGround(atlas, layers)
  const shore = shoreOf(layers)
  return {
    atlas,
    theme,
    seed,
    decor,
    width: pw,
    height: ph,
    base,
    wet,
    open,
    path,
    depth,
    shore,
    docks,
  }
}

/** 画出地面：trees 为 false 时不画树和灌木，由立体场景把它们立起来 */
export function paintGround(ground: Ground, trees: boolean): HTMLCanvasElement {
  const { width: pw, height: ph, atlas, theme, seed, decor } = ground
  const G = theme.ground
  const canvas = document.createElement('canvas')
  canvas.width = pw
  canvas.height = ph
  const ctx = canvas.getContext('2d')!
  const img = ctx.createImageData(pw, ph)
  const px = new Uint32Array(img.data.buffer)
  px.set(ground.base)
  const put = (x: number, y: number, c: number) => {
    x = Math.round(x)
    y = Math.round(y)
    if (x >= 0 && y >= 0 && x < pw && y < ph) px[y * pw + x] = c
  }
  const darken = (x: number, y: number, t: number) => {
    if (x >= 0 && y >= 0 && x < pw && y < ph) px[y * pw + x] = mix(px[y * pw + x], SHADOW, t)
  }
  const veg = [...decor.vegetation].sort((a, b) => a.y - b.y)
  for (const v of veg) {
    const x = toPx(v.x),
      y = toPx(v.y)
    if (v.kind === 'grass') {
      const c = u(G.grass[4])
      put(x - 1, y, c)
      put(x - 1, y - 1, c)
      put(x + 1, y, c)
      put(x, y - 1, u(G.tuft))
    } else if (v.kind === 'flowers') {
      const k = Math.floor(hash(x, y, seed) * 5)
      for (const [dx, dy, j] of [
        [-1, 0, 0],
        [1, -1, 1],
        [0, 1, 2],
        [2, 1, 0],
      ])
        put(x + dx, y + dy, u(G.flowers[(k + j) % 5]))
    } else if (trees) {
      const { r, variant, bush } = treeShape(v)
      tree(x, y, r, variant, bush, seed, theme.flora, put, darken)
    }
  }
  for (const s of atlas.spaces) if (s.id !== OUTDOOR_SPACE) room(s, theme, seed, put, darken)
  ctx.putImageData(img, 0, 0)
  return canvas
}

/** groundOf 的中间结果，给后面几步画地面、算空地用 */
interface Layers {
  pw: number
  ph: number
  seed: number
  theme: MapTheme
  kindAt: (i: number) => string
  wet: Uint8Array
  path: Uint8Array
  built: Uint8Array
  sea: Uint8Array
  piers: Uint8Array
  rocks: Uint8Array
  depth: Uint8Array
  /** 这一处沙滩有多宽（像素），-1 是不在岸边 */
  shoreWidth: Float32Array
}

/** 区域和水面先按格子铺到像素上，取色时再加噪声偏移采样，边界就不是方格锯齿 */
function rasterRegions(atlas: Atlas, decor: DecorPlan, pw: number, ph: number, seed: number) {
  const rawRegion = new Int16Array(pw * ph).fill(-1)
  const rawWater = new Uint8Array(pw * ph)
  const fillCells = (cells: [number, number][], cs: number, write: (i: number) => void) => {
    for (const [c, r] of cells) {
      const x0 = toPx(c * cs),
        y0 = toPx(r * cs),
        x1 = toPx((c + 1) * cs),
        y1 = toPx((r + 1) * cs)
      for (let y = Math.max(0, y0); y < Math.min(ph, y1); y++)
        for (let x = Math.max(0, x0); x < Math.min(pw, x1); x++) write(y * pw + x)
    }
  }
  atlas.regions.forEach((r, i) =>
    fillCells(fillHoles(r, atlas), r.cell_size, (p) => (rawRegion[p] = i))
  )
  for (const r of atlas.regions) {
    const cells = decor.water.get(r.id)
    if (cells) fillCells(cells, r.cell_size, (p) => (rawWater[p] = 1))
  }
  const region = new Int16Array(pw * ph)
  const wet = new Uint8Array(pw * ph)
  for (let y = 0; y < ph; y++)
    for (let x = 0; x < pw; x++) {
      const jx = Math.round((noise(x / 6, y / 6, seed + 50) - 0.5) * 6)
      const jy = Math.round((noise(x / 6, y / 6, seed + 51) - 0.5) * 6)
      const sx = Math.min(pw - 1, Math.max(0, x + jx)),
        sy = Math.min(ph - 1, Math.max(0, y + jy))
      region[y * pw + x] = rawRegion[sy * pw + sx]
      wet[y * pw + x] = rawWater[sy * pw + sx]
    }
  return { region, wet }
}

/** 四面环海：镇上的东西（区域、道路、房屋）之外一段距离就是海。
 *  content 标出镇上的东西；built 是沙滩不能盖的地方：道路、铺装和区域、房屋，街道区域里的空草地可以铺沙 */
function landMasks(
  atlas: Atlas,
  region: Int16Array,
  wet: Uint8Array,
  path: Uint8Array,
  kindAt: (i: number) => string,
  pw: number,
  ph: number
) {
  const content = new Uint8Array(pw * ph)
  const built = new Uint8Array(pw * ph)
  for (let i = 0; i < pw * ph; i++) {
    content[i] = !wet[i] && (region[i] >= 0 || path[i] > 0) ? 1 : 0
    built[i] = content[i] && (path[i] > 0 || kindAt(i) !== 'road') ? 1 : 0
  }
  for (const s of atlas.spaces) {
    if (s.id === OUTDOOR_SPACE) continue
    const r = roomRect(s)
    for (let y = toPx(r.y); y < toPx(r.y1); y++)
      for (let x = toPx(r.x); x < toPx(r.x1); x++)
        if (x >= 0 && y >= 0 && x < pw && y < ph) content[y * pw + x] = built[y * pw + x] = 1
  }
  return { content, built }
}

/** 孤岛的海岸（见 island.ts），再把外圈和栈桥并进 wet；seaAround 是一处周围 21×21 里海的比例 */
function coastOf(
  atlas: Atlas,
  G: GroundPalette,
  content: Uint8Array,
  wet: Uint8Array,
  pw: number,
  ph: number,
  seed: number
) {
  const { sea, piers, rocks, docks, toSea: depth } = island(atlas, content, wet, pw, ph, seed)
  // 废土的栈桥年久失修：沿栈桥隔几段缺一整排板，露出下面的海床
  if (G.pierGaps)
    docks.forEach((d, k) => {
      for (let s = 4; s < d.length; s++) {
        if (hash(s, k, seed + 8) >= G.pierGaps) continue
        for (let t = -1; t <= 2; t++) {
          const i = (d.y + d.dy * s + (d.dx ? t : 0)) * pw + d.x + d.dx * s + (d.dy ? t : 0)
          piers[i] = 0
          sea[i] = 1
        }
      }
    })
  for (let i = 0; i < pw * ph; i++) {
    if (sea[i]) wet[i] = 1
    if (piers[i]) wet[i] = 0
  }
  const R = 10
  const seaSum = new Int32Array((pw + 1) * (ph + 1))
  for (let y = 0; y < ph; y++) {
    let row = 0
    for (let x = 0; x < pw; x++) {
      row += sea[y * pw + x]
      seaSum[(y + 1) * (pw + 1) + x + 1] = seaSum[y * (pw + 1) + x + 1] + row
    }
  }
  const seaAround = (x: number, y: number) => {
    const x0 = Math.max(0, x - R),
      y0 = Math.max(0, y - R),
      x1 = Math.min(pw, x + R + 1),
      y1 = Math.min(ph, y + R + 1)
    const W = pw + 1
    return (
      (seaSum[y1 * W + x1] - seaSum[y0 * W + x1] - seaSum[y1 * W + x0] + seaSum[y0 * W + x0]) /
      ((x1 - x0) * (y1 - y0))
    )
  }
  return { sea, piers, rocks, docks, depth, seaAround }
}

/** 沙滩宽窄看地形：数一数周围 21×21 里有多少海，海少说明是凹进去的湾，浪小、沙子堆得宽；
 *  海多说明是凸出去的岬角，浪大、只剩岩石。只看外海，公园池塘和港口的水边不铺沙。
 *  先在紧贴外海的岸线上算，再按周围 53×53 里岸线的平均值铺到内陆，沙滩和过渡带的宽度沿岸平滑变化；
 *  小于 2 就是岩石岸 */
function shoreWidths(
  coast: ReturnType<typeof coastOf>,
  wet: Uint8Array,
  built: Uint8Array,
  pw: number,
  ph: number,
  seed: number
) {
  const { sea, piers, rocks, depth, seaAround } = coast
  const coastW = new Float32Array((pw + 1) * (ph + 1)),
    coastN = new Int32Array((pw + 1) * (ph + 1))
  for (let y = 0; y < ph; y++) {
    let rw = 0,
      rn = 0
    for (let x = 0; x < pw; x++) {
      const i = y * pw + x
      const coast =
        !wet[i] &&
        !rocks[i] &&
        !piers[i] &&
        (sea[i - 1] || sea[i + 1] || sea[i - pw] || sea[i + pw])
      if (coast) {
        const width =
          (0.52 - seaAround(x, y)) * 70 + 6 + (fbm(x * 1.4, y * 1.4, seed + 351) - 0.5) * 8
        rw += Math.max(0, Math.min(18, width))
        rn++
      }
      const k = (y + 1) * (pw + 1) + x + 1
      coastW[k] = coastW[k - pw - 1] + rw
      coastN[k] = coastN[k - pw - 1] + rn
    }
  }
  const S = 26
  const shoreWidth = new Float32Array(pw * ph).fill(-1)
  for (let y = 0; y < ph; y++)
    for (let x = 0; x < pw; x++) {
      const i = y * pw + x
      if (wet[i] || built[i] || piers[i] || rocks[i] || depth[i] > 24) continue
      const x0 = Math.max(0, x - S),
        y0 = Math.max(0, y - S),
        x1 = Math.min(pw, x + S + 1),
        y1 = Math.min(ph, y + S + 1)
      const W = pw + 1,
        box = (a: Float32Array | Int32Array) =>
          a[y1 * W + x1] - a[y0 * W + x1] - a[y1 * W + x0] + a[y0 * W + x0]
      const n = box(coastN)
      if (n) shoreWidth[i] = box(coastW) / n
    }
  return shoreWidth
}

/** 岸边：0 不是，1 岩石岸，2 湿沙，3 干沙，4 草地和沙子交错的过渡带 */
function shoreKind(L: Layers, i: number) {
  const width = L.shoreWidth[i]
  if (width < 0) return 0
  const d = L.depth[i]
  if (width < 2) return d <= 2 ? 1 : 0
  if (d <= 1) return 2
  if (d <= width) return 3
  return d <= width + 5 ? 4 : 0
}
function beach(L: Layers, i: number) {
  const k = shoreKind(L, i)
  return k > 0 && k < 4
}

/** 礁石和岩石岸：灰色石头，上沿提亮、下沿压暗 */
function stone(L: Layers, i: number, x: number, y: number) {
  const { rocks, wet, piers, pw } = L
  const solid = (j: number) => rocks[j] || (!wet[j] && !piers[j])
  if (!solid(i - pw)) return u('#b3ac9b')
  if (!solid(i + pw)) return u('#57524a')
  return u(hash(x, y, L.seed + 14) < 0.3 ? '#7d776b' : '#8e887a')
}

function shoreColor(L: Layers, i: number, x: number, y: number, kind: number) {
  const G = L.theme.ground
  if (kind === 1) return stone(L, i, x, y)
  if (kind === 2) return u(bayer(x, y) < 0.5 ? G.wetSand : G.wetSandDither)
  // 干沙从湿沙往里越来越浅，零星几颗深色小石子
  const t = (L.depth[i] - 1) / Math.max(1, L.shoreWidth[i] - 1)
  if (hash(x, y, L.seed + 15) < 0.02) return u(G.sandPebble)
  return u(pick(G.sand, 1 - t, x, y, 1.4))
}

/** 水按离岸远近分档，档与档之间按有序抖动交错，像素风的渐变 */
function seaColor(G: GroundPalette, d: number, x: number, y: number) {
  const t = Math.min(G.outer.length - 1, Math.max(0, Math.log2(d + 0.5) + bayer(x, y) * 0.8 - 0.2))
  return u(G.outer[Math.floor(t)])
}

/** 逐像素铺地面：外圈和水面、栈桥、礁石、沙滩，其余按区域材质 */
function paintBase(L: Layers, px: Uint32Array) {
  const { pw, ph, seed, theme, wet, depth, piers, rocks, path, shoreWidth } = L
  const G = theme.ground
  for (let y = 0; y < ph; y++)
    for (let x = 0; x < pw; x++) {
      const i = y * pw + x
      if (wet[i]) {
        px[i] = seaColor(G, depth[i], x, y)
        // 干海床的龟裂、冰原的裂缝
        if (theme.outer !== 'sea' && crack(x, y, 11, seed + 70) < 0.7)
          px[i] = mix(px[i], SHADOW, 0.3)
        continue
      }
      if (piers[i]) {
        const edge = !piers[i - 1] || !piers[i + 1] || !piers[i - pw] || !piers[i + pw]
        px[i] = edge
          ? u((x + y) % 5 ? '#6b5038' : '#3e2f24')
          : u(G.plank[Math.floor(hash(x >> 2, y >> 2, seed + 6) * 3)])
        continue
      }
      if (rocks[i]) {
        px[i] = stone(L, i, x, y)
        continue
      }
      const shore = shoreKind(L, i)
      if (shore && shore < 4) {
        px[i] = shoreColor(L, i, x, y, shore)
        continue
      }
      const kind = L.kindAt(i)
      const trodden = !PAVED.has(kind) && (path[i] === 2 || (path[i] === 1 && bayer(x, y) < 0.5))
      px[i] = groundColor(trodden ? 'path' : kind, x, y, seed, G, (c) => {
        if (y > 0) px[i - pw] = c
      })
      // 过渡带：越靠沙滩沙子越多，按有序抖动和草地交错，偶尔一丛海草
      if (shore === 4 && !trodden) {
        const t = (shoreWidth[i] + 5 - depth[i]) / 6
        if (bayer(x, y) < t) px[i] = u(pick(G.sand, 0.9, x, y, 1))
        else if (hash(x, y, seed + 16) < 0.05) px[i] = u(G.shoreWeed)
      }
    }
}

/** 岸线：水边一圈浪花（废土里是旧海岸的土坎），岸上一圈湿痕，码头边是深色木桩 */
function paintShoreline(L: Layers, px: Uint32Array) {
  const { pw, ph, wet, piers, rocks } = L
  const G = L.theme.ground
  for (let y = 1; y < ph - 1; y++)
    for (let x = 1; x < pw - 1; x++) {
      const i = y * pw + x
      const n = wet[i - 1] + wet[i + 1] + wet[i - pw] + wet[i + pw]
      if (wet[i]) {
        if (n < 4) px[i] = u(G.outerEdge)
      } else if (n > 0 && !piers[i] && !rocks[i] && !beach(L, i))
        px[i] = L.kindAt(i) === 'harbor' ? u('#3e2f24') : mix(px[i], SHADOW, 0.35)
    }
}

/** 海边的地物：1 是和外海连着的水（港口的水也算，池塘不算），2 是外海边的沙滩，3 是外海边的岩石岸和礁石。
 *  立体场景只在外海上起浪，浪冲上沙滩、拍在岩石上 */
function shoreOf(L: Layers) {
  const { pw, ph, wet, rocks } = L
  const out = new Uint8Array(pw * ph)
  // 从地图四边的水往里灌，灌得到的就是外海
  const stack: number[] = []
  const push = (i: number) => {
    if (!wet[i] || out[i]) return
    out[i] = 1
    stack.push(i)
  }
  for (let x = 0; x < pw; x++) (push(x), push((ph - 1) * pw + x))
  for (let y = 0; y < ph; y++) (push(y * pw), push(y * pw + pw - 1))
  while (stack.length) {
    const i = stack.pop()!
    const x = i % pw
    if (x > 0) push(i - 1)
    if (x < pw - 1) push(i + 1)
    if (i >= pw) push(i - pw)
    if (i < pw * (ph - 1)) push(i + pw)
  }
  for (let i = 0; i < pw * ph; i++) {
    if (wet[i]) continue
    const kind = shoreKind(L, i)
    if (rocks[i] || kind === 1) out[i] = 3
    else if (kind === 2 || kind === 3) out[i] = 2
  }
  return out
}

/** 能种东西的空地，立体场景按它撒树、放微粒 */
function openGround(atlas: Atlas, L: Layers) {
  const { pw, ph, wet, path, piers, rocks } = L
  const open = new Uint8Array(pw * ph)
  for (let i = 0; i < pw * ph; i++) {
    const kind = L.kindAt(i)
    if (wet[i] || path[i] || piers[i] || rocks[i] || beach(L, i) || PAVED.has(kind)) continue
    open[i] = OPEN_KINDS[kind] ?? OPEN.town
  }
  for (const s of atlas.spaces) {
    if (s.id === OUTDOOR_SPACE) continue
    const r = roomRect(s)
    const x0 = toPx(r.x) - 6,
      y0 = toPx(r.y) - 6
    const x1 = toPx(r.x1) + 6,
      y1 = toPx(r.y1) + 6
    for (let y = Math.max(0, y0); y < Math.min(ph, y1); y++)
      for (let x = Math.max(0, x0); x < Math.min(pw, x1); x++) open[y * pw + x] = OPEN.none
  }
  return open
}

/** 空地分类：none 不能种东西（水、路、铺装、房屋四周），其余按所在区域 */
export const OPEN = { none: 0, wild: 1, park: 2, garden: 3, town: 4 } as const
const OPEN_KINDS: Record<string, number> = { '': OPEN.wild, park: OPEN.park, garden: OPEN.garden }

/** 沿路段折线画出土路：中间 2 是实土，两边 1 是和草地交错的边 */
function tracePaths(atlas: Atlas, pw: number, ph: number, seed: number): Uint8Array {
  const path = new Uint8Array(pw * ph)
  for (const e of atlas.edges) {
    const half = Math.max(2.4, (e.width ?? DEFAULT_EDGE_WIDTH) / PIXEL / 2 + 1)
    const pts = e.polyline.map(([x, y]) => [toPx(x), toPx(y)])
    for (let k = 0; k + 1 < pts.length; k++) {
      const [ax, ay] = pts[k],
        [bx, by] = pts[k + 1]
      const n = Math.max(1, Math.ceil(Math.hypot(bx - ax, by - ay)))
      for (let t = 0; t <= n; t++) {
        const cx = ax + ((bx - ax) * t) / n,
          cy = ay + ((by - ay) * t) / n
        const r = half + (noise(cx / 8, cy / 8, seed + 30) - 0.5) * 1.6
        for (let dy = -5; dy <= 5; dy++)
          for (let dx = -5; dx <= 5; dx++) {
            const X = Math.round(cx) + dx,
              Y = Math.round(cy) + dy
            if (X < 0 || Y < 0 || X >= pw || Y >= ph) continue
            const d = Math.hypot(X - cx, Y - cy)
            const v = d <= r ? 2 : d <= r + 1.5 ? 1 : 0
            if (v > path[Y * pw + X]) path[Y * pw + X] = v
          }
      }
    }
  }
  return path
}

/** 被同一块硬地区域四面围住的空格子并进去，广场中间不留草洞 */
function fillHoles(r: Atlas['regions'][number], atlas: Atlas): [number, number][] {
  if (!['plaza', 'market', 'gate', 'harbor'].includes(r.kind)) return r.cells
  const own = new Set(r.cells.map(([c, y]) => `${c},${y}`))
  const taken = new Set<string>()
  for (const other of atlas.regions)
    if (other.cell_size === r.cell_size) for (const [c, y] of other.cells) taken.add(`${c},${y}`)
  const xs = r.cells.map((c) => c[0]),
    ys = r.cells.map((c) => c[1])
  const extra: [number, number][] = []
  for (let y = Math.min(...ys); y <= Math.max(...ys); y++)
    for (let c = Math.min(...xs); c <= Math.max(...xs); c++) {
      if (taken.has(`${c},${y}`)) continue
      const enclosed = [
        [1, 0],
        [-1, 0],
        [0, 1],
        [0, -1],
      ].every(([dx, dy]) => {
        for (let d = 1; d <= 8; d++) {
          const key = `${c + dx * d},${y + dy * d}`
          if (own.has(key)) return true
          if (taken.has(key)) return false
        }
        return false
      })
      if (enclosed) extra.push([c, y])
    }
  return extra.length ? [...r.cells, ...extra] : r.cells
}

/** 取一个地面像素的颜色要用的东西：g 是这里的大尺度噪声，cracked 判断这里有没有成片龟裂 */
interface Spot {
  x: number
  y: number
  seed: number
  G: GroundPalette
  g: number
  cracked: (size: number) => boolean
}

/** 广场和城门的石板：错缝铺，每块深浅不一，上沿提亮；废土里缺了一些露出土，剩下的有裂缝 */
function slabColor({ x, y, seed, G, g, cracked }: Spot, plaza: boolean) {
  const pal = plaza ? G.plaza : G.gate
  const row = Math.floor(y / 5),
    off = (row & 1) * 4,
    lx = (x + off) % 8,
    ly = y % 5
  const slab = Math.floor((x + off) / 8)
  if (G.cracks && hash(slab, row, seed + 62) < 0.12) return u(pick(G.dirt, g, x, y, 1.3))
  if (lx === 0 || ly === 0) return u(plaza ? G.plazaLine : G.gateLine)
  if (cracked(6)) return u(G.plazaLine)
  let c = u(pal[Math.floor(hash(slab, row, seed + 4) * pal.length)])
  if (ly === 1) c = mix(c, u(G.plazaLight), 0.25)
  if (g < 0.36 && bayer(x, y) < 0.4) c = mix(c, u(G.plazaStain), 0.18)
  return c
}

/** 港口的木板：一排排错开的长板，偶尔一块发暗 */
function harborColor({ x, y, seed, G }: Spot) {
  const by = Math.floor(y / 3),
    off = Math.floor(hash(by, 0, seed + 5) * 30)
  if (y % 3 === 2 || (x + off) % 26 === 0) return u(G.plankLine)
  const c = u(G.plank[Math.floor(hash(Math.floor((x + off) / 26), by, seed + 6) * 3)])
  return hash(x, y, seed + 7) < 0.07 ? mix(c, u(G.plankLine), 0.4) : c
}

/** 花园：一垄垄的花，垄间是草 */
function gardenColor({ x, y, seed, G, g }: Spot) {
  const bx = Math.floor(x / 24),
    ly = (y + bx * 3) % 9,
    lx = x % 24
  if (ly >= 3 && ly <= 5 && lx >= 2 && lx < 20) {
    const fl = G.flowers[Math.floor(hash(bx, Math.floor((y + bx * 3) / 9), seed + 8) * 5)]
    if (ly === 4) return x & 1 ? u(fl) : u(G.gardenLeaf[0])
    return (x + ly) & 1 ? u(G.gardenSoil) : u(G.gardenLeaf[1])
  }
  return u(pick(G.grass, g * 1.1 - 0.02, x, y, 1.2))
}

/** 野地和公园的草：零星的草丛尖和小花，废土里成片龟裂 */
function grassColor(s: Spot, park: boolean, paintAbove: (c: number) => void) {
  const { x, y, seed, G, g } = s
  const pal = park ? G.park : G.grass
  const h = hash(x, y, seed + 10)
  if (h < 0.012) {
    paintAbove(u(G.tuft))
    return u(pal[4])
  }
  if (h < 0.0135) return u(G.flowers[Math.floor(hash(x, y, seed + 11) * 5)])
  if (s.cracked(10)) return u(G.cracks!)
  return u(pick(pal, g * 1.15 - 0.05, x, y, 1.2))
}

function groundColor(
  kind: string,
  x: number,
  y: number,
  seed: number,
  G: GroundPalette,
  paintAbove: (c: number) => void
): number {
  const g = fbm(x, y, seed)
  // 废土的空地上成片的龟裂：只在一部分地方出现，不是满地网格
  const cracked = (size: number) =>
    G.cracks !== undefined &&
    crack(x, y, size, seed + 60) < 0.5 &&
    noise(x / 30, y / 30, seed + 61) > 0.55
  const spot: Spot = { x, y, seed, G, g, cracked }
  switch (kind) {
    case 'path': {
      if (hash(x, y, seed + 3) < 0.018) {
        paintAbove(u(G.pebble[0]))
        return u(G.pebble[1])
      }
      return u(pick(G.dirt, g * 1.25 - 0.12, x, y, 1.3))
    }
    case 'road':
    case 'area': {
      // 镇上的空地：踩薄了的草，零星露土
      if (cracked(9)) return u(G.cracks!)
      const c = u(pick(G.grass, g * 0.9 + 0.12, x, y, 1.2))
      return noise(x / 5, y / 5, seed + 12) < 0.3 && bayer(x, y) < 0.6
        ? mix(c, u(G.dirt[1]), 0.6)
        : c
    }
    case 'plaza':
    case 'gate':
      return slabColor(spot, kind === 'plaza')
    case 'market': {
      const [a, b, dot, stain] = G.market
      let c = u(((x >> 2) + (y >> 2)) & 1 ? a : b)
      if (x % 4 === 0 && y % 4 === 0) c = u(dot)
      return g < 0.4 && bayer(x, y) < 0.3 ? mix(c, u(stain), 0.2) : c
    }
    case 'harbor':
      return harborColor(spot)
    case 'garden':
      return gardenColor(spot)
    default:
      return grassColor(spot, kind === 'park', paintAbove)
  }
}

type Put = (x: number, y: number, c: number) => void
type Darken = (x: number, y: number, t: number) => void

/** 树冠半径（像素）与配色，平面图和立体场景共用 */
export function treeShape(v: DecorPlan['vegetation'][number]) {
  const bush = v.kind === 'bush'
  return {
    bush,
    r: bush ? 2 + Math.round(v.scale) : Math.round(3 + (v.scale - 0.8) * 5),
    variant: bush ? 1 : Number(v.kind.slice(4)) || 0,
  }
}

/** 树冠：圆形加噪声边缘，按左上光源分五档明暗，底部压一圈最暗色；废土里乔木是枯树，冰雪里是压雪的松树、灌木是雪堆 */
export function tree(
  x: number,
  y: number,
  r: number,
  variant: number,
  bush: boolean,
  seed: number,
  flora: MapTheme['flora'],
  put: Put,
  darken: Darken
) {
  if (flora.tree === 'dead' && !bush) return deadTree(x, y, r, seed, put, darken)
  if (flora.tree === 'pine' && !bush)
    return pineTree(x, y, r, flora.canopy[variant % flora.canopy.length], seed, put, darken)
  const pal = flora.tree === 'pine' ? SNOW_MOUND : flora.canopy[variant % flora.canopy.length]
  const cy = bush ? y - r : y - r - 2
  for (let dy = -2; dy <= 2; dy++)
    for (let dx = -r - 1; dx <= r + 2; dx++)
      if ((dx / (r + 1.5)) ** 2 + (dy / 2.3) ** 2 < 1 && bayer(x + dx, y + dy) < 0.8)
        darken(x + dx + 1, y + dy, 0.42)
  if (!bush) {
    for (let k = 1; k <= 4; k++) {
      put(x - 1, y - k, u('#5e4432'))
      put(x, y - k, u(k > 2 ? '#74563f' : '#5e4432'))
    }
  }
  // 枯灌丛稀疏：边缘多挖掉一些，看得见地面
  const sparse = flora.tree === 'dead' ? 0.3 : 0
  for (let dy = -r - 1; dy <= r + 1; dy++)
    for (let dx = -r - 1; dx <= r + 1; dx++) {
      const X = x + dx,
        Y = cy + dy,
        n = noise(X / 3, Y / 3, seed + 7 + variant),
        d = Math.hypot(dx, dy),
        edge = r * (0.84 + 0.3 * n - sparse)
      if (d >= edge || (sparse && hash(X, Y, seed + 20) < 0.25)) continue
      const light = (-dx * 0.55 - dy * 0.85) / r + (n - 0.5) * 0.7
      let c = pick(pal, (light + 1) / 2, X, Y, 1.1)
      if (d > edge - 1.1 && dx + dy > 0) c = pal[0]
      put(X, Y, u(c))
    }
}

/** 雪堆：灌木被雪整个盖住，只剩一团白里透蓝的包 */
const SNOW_MOUND = ['#8c9cb2', '#aebccc', '#cad6e2', '#e2eaf1', '#f6f9fb']

/** 松树：一层层往下变宽的尖塔，左亮右暗；每层上沿压一道雪，朝光的一边白、背光的一边发蓝 */
function pineTree(
  x: number,
  y: number,
  r: number,
  pal: readonly string[],
  seed: number,
  put: Put,
  darken: Darken
) {
  const hgt = 2 * r + 4,
    layer = Math.max(3, Math.round(hgt / 4)),
    top = y - hgt - 1
  for (let dy = -1; dy <= 1; dy++)
    for (let dx = -r; dx <= r + 2; dx++)
      if (bayer(x + dx, y + dy) < 0.8) darken(x + dx + 1, y + dy, 0.35)
  put(x - 1, y, u('#4a3020'))
  put(x, y, u('#3a2418'))
  put(x - 1, y - 1, u('#4a3020'))
  put(x, y - 1, u('#3a2418'))
  for (let j = 0; j < hgt; j++) {
    const k = j % layer,
      w = Math.round(((j + 2) / hgt) * (r + 1) * (0.55 + 0.45 * (k / layer)))
    for (let i = -w; i <= w; i++) {
      const X = x + i,
        Y = top + j
      let t = 0.6 - (i / (w + 1)) * 0.45 + (hash(X, Y, seed + 30) - 0.5) * 0.3
      if (k === layer - 1) t -= 0.2
      let c = u(pick(pal, t, X, Y, 1))
      if (k === 0 || (k === 1 && hash(X, Y, seed + 31) < 0.5)) c = u(i <= 0 ? SNOW : SNOW_SHADE)
      put(X, Y, c)
    }
  }
}

/** 枯树：灰褐的树干往上分三四次叉，枝头越分越细；r 和活树的树冠半径同一尺度 */
function deadTree(x: number, y: number, r: number, seed: number, put: Put, darken: Darken) {
  for (let dx = -2; dx <= 4; dx++) if (bayer(x + dx, y) < 0.7) darken(x + dx, y, 0.35)
  for (let dx = 0; dx <= 3; dx++) darken(x + dx, y + 1, 0.2)
  const bark = [u('#3e3228'), u('#56463a'), u('#6f5e4e')]
  let k = 0
  const random = () => hash(x * 31 + k, y * 17 + k++, seed + 90)
  const branch = (bx: number, by: number, angle: number, length: number, width: number) => {
    for (let s = 0; s < length; s++) {
      bx += Math.cos(angle)
      by += Math.sin(angle)
      put(bx, by, bark[width > 1 ? 1 : 2])
      if (width > 1) put(bx + 1, by, bark[0])
      angle += (random() - 0.5) * 0.3
    }
    if (length < 3) return
    const forks = 1 + Math.floor(random() * 2.2)
    for (let f = 0; f < forks; f++)
      branch(bx, by, angle + (random() - 0.5) * 1.8, length * 0.6, width - 1)
  }
  branch(x, y, -Math.PI / 2, r * 0.9 + 3, 2)
}

function floorColor(type: string, lx: number, ly: number, seed: number): string {
  switch (type) {
    case 'wood':
    case 'darkwood': {
      const pal =
        type === 'wood' ? ['#b98e62', '#b08658', '#c29a6c'] : ['#8e6644', '#9a7050', '#85603f']
      const by = Math.floor(ly / 3),
        off = Math.floor(hash(by, 1, seed) * 20)
      if (ly % 3 === 2 || (lx + off) % 18 === 0) return type === 'wood' ? '#7f5f40' : '#5f4430'
      return pal[Math.floor(hash(Math.floor((lx + off) / 18), by, seed + 1) * 3)]
    }
    case 'tile':
      if (lx % 5 === 0 || ly % 5 === 0) return '#c3c1b6'
      return (((lx / 5) | 0) + ((ly / 5) | 0)) & 1 ? '#e6e4dc' : '#dcdad0'
    case 'checker':
      return ((lx >> 2) + (ly >> 2)) & 1 ? '#e0d3b8' : '#a98f6c'
    case 'rough': {
      if (lx % 4 === 3) return '#7b6c56'
      const c = ['#9c8b72', '#a69580', '#938268'][
        Math.floor(hash(lx >> 2, Math.floor(ly / 20), seed + 2) * 3)
      ]
      return hash(lx, ly, seed + 3) < 0.06 ? '#7d705c' : c
    }
    case 'stone': {
      const row = Math.floor(ly / 5),
        off = (row & 1) * 3
      if ((lx + off) % 7 === 0 || ly % 5 === 0) return '#9c9585'
      return ['#bfb8a8', '#c9c2b1', '#b5ae9e'][
        Math.floor(hash(Math.floor((lx + off) / 7), row, seed + 4) * 3)
      ]
    }
    default:
      if (lx % 5 === 0 || ly % 5 === 0) return '#a8735a'
      return (((lx / 5) | 0) + ((ly / 5) | 0)) & 1 ? '#c98f6a' : '#bf8561'
  }
}

/** 房间：投影、地板、墙（顶边露出立面）、朝最近墙边开门 */
function room(s: Space, theme: MapTheme, seed: number, put: Put, darken: Darken) {
  const r = roomRect(s)
  const x = toPx(r.x),
    y = toPx(r.y)
  const w = toPx(r.x1) - x,
    h = toPx(r.y1) - y
  const type = theme.interiors.floors[buildingKind(s)]
  for (let yy = y + 2; yy < y + h + 4; yy++)
    for (let xx = x + 2; xx < x + w + 4; xx++)
      if ((xx >= x + w || yy >= y + h) && bayer(xx, yy) < 0.85) darken(xx, yy, 0.4)
  for (let yy = y; yy < y + h; yy++)
    for (let xx = x; xx < x + w; xx++) put(xx, yy, u(floorColor(type, xx - x, yy - y, seed)))
  const cap = u(WALL_CAP),
    top = u('#5a4d45')
  for (let xx = x - 2; xx < x + w + 2; xx++) {
    put(xx, y - 2, cap)
    put(xx, y - 1, top)
    for (let k = 0; k < 4; k++)
      put(
        xx,
        y + k,
        u(((xx + (k >> 1) * 3) % 6 === 0 && k % 2 === 1) || k === 3 ? '#6f5e50' : '#8b7867')
      )
    put(xx, y + h, top)
    put(xx, y + h + 1, cap)
  }
  for (let yy = y - 2; yy < y + h + 2; yy++) {
    put(x - 2, yy, cap)
    put(x - 1, yy, top)
    put(x + w, yy, top)
    put(x + w + 1, yy, cap)
  }
  for (let xx = x; xx < x + w; xx++) darken(xx, y + 4, 0.28)
  for (let yy = y + 4; yy < y + h; yy++) darken(x, yy, 0.2)
  if (!s.door_outside) return
  const dx = toPx(s.door_outside[0]),
    dy = toPx(s.door_outside[1])
  const dist = [Math.abs(dy - y), Math.abs(dy - (y + h)), Math.abs(dx - x), Math.abs(dx - (x + w))]
  const side = dist.indexOf(Math.min(...dist))
  const sill = u('#7a5a3e'),
    mat = u('#8f5a4a')
  const rect = (x0: number, y0: number, rw: number, rh: number, c: number) => {
    for (let yy = y0; yy < y0 + rh; yy++) for (let xx = x0; xx < x0 + rw; xx++) put(xx, yy, c)
  }
  if (side < 2) {
    const cx = Math.max(x + 2, Math.min(x + w - 8, dx - 3))
    if (side === 1) {
      rect(cx, y + h, 6, 2, sill)
      rect(cx, y + h + 2, 6, 2, mat)
    } else {
      rect(cx, y - 2, 6, 6, sill)
      rect(cx, y - 4, 6, 2, mat)
    }
  } else {
    const cy = Math.max(y + 5, Math.min(y + h - 8, dy - 3))
    rect(side === 2 ? x - 2 : x + w, cy, 2, 6, sill)
    rect(side === 2 ? x - 4 : x + w + 2, cy, 2, 6, mat)
  }
}
