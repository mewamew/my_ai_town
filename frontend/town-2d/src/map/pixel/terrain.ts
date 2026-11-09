import type { Atlas } from 'town-shared/mapDocument'
import { buildingKind } from '../buildings'
import { planDecor, type DecorPlan } from '../decor'
import { fromPx, MARGIN, OUTDOOR_SPACE, PIXEL, roomRect, toPx } from '../grid'
import { bayer, crack, fbm, hash, noise, pick } from './noise'
import { SNOW, SNOW_SHADE, WALL_CAP } from '../palette'
import { bridgesOf, onBridge, spanOf, type Bridge } from './bridges'
import { DEFAULT_EDGE_WIDTH } from '../route'
import {
  designOf,
  distance,
  footprint,
  island,
  MAX_DEPTH,
  placer,
  QUAY,
  type Design,
  type Dock,
} from './island'
import type { GroundPalette, MapTheme } from '../themes/types'

// 地面按地面画布的像素算：地面、区域材质、水、海岸，再画上植被和房间。
// 画布一个像素 = PIXEL 个地图单位，镜头只按整数倍放大它。

/** 自带铺装的区域，路面不再盖一层土（沥青是区域的 decor，见 groundKind） */
const PAVED = new Set(['plaza', 'market', 'gate', 'harbor', 'asphalt'])
/** 区域的 decor 换掉地面画法的几种：旧沥青路面、碎石废墟地；都不长树 */
const DECOR_GROUNDS = new Set(['asphalt', 'rubble'])

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
 * shore 标出海边的地物，立体场景按它画浪（见 shoreOf）；calm 是码头一带水面的平静程度（0～255，见 calmOf）；
 * docks 是栈桥（地图坐标），立体场景按它搭桥，船停在旁边；bridges 是路过岛内水面的桥（见 bridges.ts）；
 * spring 标出温泉的水面，立体场景在上面冒白汽、夜里发光
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
  calm: Uint8Array
  docks: Dock[]
  bridges: Bridge[]
  spring: Uint8Array
}

export function groundOf(atlas: Atlas, theme: MapTheme, seed = TERRAIN_SEED): Ground {
  const decor = planDecor(atlas)
  const pw = Math.ceil((atlas.canvas.width + 2 * MARGIN) / PIXEL)
  const ph = Math.ceil((atlas.canvas.height + 2 * MARGIN) / PIXEL)
  const { region, wet } = rasterRegions(atlas, decor, pw, ph, seed)
  const kindAt = (i: number) => (region[i] < 0 ? '' : atlas.regions[region[i]].kind)
  const decorAt = (i: number) => (region[i] < 0 ? undefined : atlas.regions[region[i]].decor)
  const path = tracePaths(atlas, pw, ph, seed)
  const { content, built } = landMasks(atlas, region, wet, path, kindAt, pw, ph)
  const deck = new Uint8Array(pw * ph)
  for (let i = 0; i < pw * ph; i++) deck[i] = kindAt(i) === 'harbor' && !wet[i] ? 1 : 0
  const design = designOf(atlas.island, pw, ph)
  const coast = coastOf(atlas, decor.harbors, content, deck, wet, design, pw, ph, seed)
  const layers: Layers = {
    pw,
    ph,
    seed,
    theme,
    kindAt,
    decorAt,
    wet,
    path,
    built,
    deck,
    ...coast,
    ...springRim(coast.spring, wet, pw, ph),
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
  // 温泉四周不种树、不长草丛：池边留一片干净的雪地
  if (layers.clear.some(Boolean))
    decor.vegetation = decor.vegetation.filter((v) => !layers.clear[toPx(v.y) * pw + toPx(v.x)])
  const calm = calmOf(layers, theme.outer === 'sea')
  const base = new Uint32Array(pw * ph)
  paintBase(layers, base)
  paintShoreline(layers, base)
  // 栈桥换成地图坐标交给立体场景，船停在栈桥边上
  const docks = coast.docks.map((d) => ({
    ...d,
    x: fromPx(d.x),
    y: fromPx(d.y),
    length: d.length * PIXEL,
    width: d.width * PIXEL,
    head: [d.head[0] * PIXEL, d.head[1] * PIXEL] as [number, number],
  }))
  const open = openGround(atlas, layers)
  const shore = shoreOf(layers)
  const bridges = bridgesOf(atlas, coast.inland, pw, ph)
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
    calm,
    docks,
    bridges,
    spring: coast.spring,
  }
}

/** 画出地面。flat 是平面图：树、灌木和栈桥都画在地面上；不然由立体场景把它们立起来、搭起来 */
export function paintGround(ground: Ground, flat: boolean): HTMLCanvasElement {
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
    } else if (flat) {
      const { r, variant, bush } = treeShape(v)
      tree(x, y, r, variant, bush, seed, theme.flora, put, darken)
    }
  }
  for (const s of atlas.spaces) if (s.id !== OUTDOOR_SPACE) room(s, theme, seed, put, darken)
  for (const r of atlas.ruins ?? []) ruinTop(r, put, darken)
  if (flat) {
    for (const d of ground.docks) flatPier(d, G, put)
    for (const b of ground.bridges) flatBridge(b, G, pw, ph, put)
  }
  ctx.putImageData(img, 0, 0)
  return canvas
}

/** 平面图上的桥：石拱桥铺石板、两边一道石栏，木板桥横铺木板、两边压一道深色；南边水上压一行影子 */
function flatBridge(
  b: Bridge,
  G: GroundPalette,
  pw: number,
  ph: number,
  put: (x: number, y: number, c: number) => void
) {
  const L = spanOf(b),
    half = b.width / 2
  const x0 = toPx(Math.min(b.a[0], b.b[0]) - half) - 1,
    x1 = toPx(Math.max(b.a[0], b.b[0]) + half) + 1
  const y0 = toPx(Math.min(b.a[1], b.b[1]) - half) - 1,
    y1 = toPx(Math.max(b.a[1], b.b[1]) + half) + 1
  for (let y = Math.max(0, y0); y <= Math.min(ph - 1, y1); y++)
    for (let x = Math.max(0, x0); x <= Math.min(pw - 1, x1); x++) {
      const on = onBridge([b], fromPx(x) + PIXEL / 2, fromPx(y) + PIXEL / 2)
      if (!on) continue
      const edge = half - Math.abs(on.v) < PIXEL * 1.2
      const col = Math.floor(on.s / PIXEL)
      if (b.style === 'stone') {
        const slab = G.plaza[Math.floor(hash(col >> 2, Math.floor(on.v / 12), 3) * G.plaza.length)]
        const c = u(edge ? G.gateLine : slab)
        put(x, y, edge ? mix(c, SHADOW, 0.2) : c)
      } else {
        const board = u(G.plank[Math.floor(hash(Math.floor(col / 2), 1, 5) * G.plank.length)])
        put(
          x,
          y,
          edge ? mix(board, SHADOW, 0.45) : col % 2 ? mix(u(G.plankLine), board, 0.5) : board
        )
      }
      if (
        on.s > L * 0.02 &&
        on.s < L * 0.98 &&
        !onBridge([b], fromPx(x) + PIXEL / 2, fromPx(y + 1) + PIXEL / 2)
      )
        put(x, y + 1, mix(u(G.outer[1]), SHADOW, 0.45))
    }
}

/** 平面图上的栈桥：桥面板横铺，南边（朝镜头）压两行深色的桥侧和一排桩，看着是架在水上的 */
function flatPier(d: Dock, G: GroundPalette, put: (x: number, y: number, c: number) => void) {
  const at = placer(d)
  const { L, V, inside } = footprint(d)
  const cell = (a: number, b: number) =>
    at(a + 0.5, b + 0.5).map((p) => Math.floor((p + MARGIN) / PIXEL))
  const deck = new Set<string>()
  for (let a = 0; a < L; a++)
    for (let b = 0; b < V; b++) if (inside(a, b)) deck.add(cell(a, b).join(','))
  for (let a = 0; a < L; a++)
    for (let b = 0; b < V; b++) {
      if (!inside(a, b)) continue
      const [x, y] = cell(a, b)
      const board = u(G.plank[Math.floor(hash(Math.floor(a / 3), 1, d.x) * G.plank.length)])
      put(x, y, a % 3 === 2 ? mix(u(G.plankLine), board, 0.5) : board)
      if (deck.has(`${x},${y + 1}`)) continue
      put(x, y + 1, mix(u(G.plank[0]), SHADOW, 0.5))
      if (x % 4 === 0) put(x, y + 2, mix(u(G.plank[0]), SHADOW, 0.65))
    }
}

/** groundOf 的中间结果，给后面几步画地面、算空地用 */
interface Layers {
  pw: number
  ph: number
  seed: number
  theme: MapTheme
  kindAt: (i: number) => string
  /** 所在区域的装饰（林子、行道树、草坪，见 Atlas 的 regions.decor） */
  decorAt: (i: number) => string | undefined
  wet: Uint8Array
  path: Uint8Array
  built: Uint8Array
  sea: Uint8Array
  /** 画好的海岸里的岛内水面（河、湖、港湾）：和池塘一样不起浪 */
  inland: Uint8Array
  /** 其中的温泉，和温泉池边一圈压雪的黑石头（离水 1～RIM 像素），池子四周不种树的一圈（见 springRim） */
  spring: Uint8Array
  rim: Uint8Array
  clear: Uint8Array
  piers: Uint8Array
  /** 港口的木码头、码头朝南那一面的木墙（见 island.ts 的 Island.quay） */
  deck: Uint8Array
  quay: Uint8Array
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
  // 港口是搭出来的木码头：它和它的水按格子铺，边是直的，不加噪声偏移
  const harbor = (k: number) => k >= 0 && atlas.regions[k].kind === 'harbor'
  const region = new Int16Array(pw * ph)
  const wet = new Uint8Array(pw * ph)
  for (let y = 0; y < ph; y++)
    for (let x = 0; x < pw; x++) {
      const jx = Math.round((noise(x / 6, y / 6, seed + 50) - 0.5) * 6)
      const jy = Math.round((noise(x / 6, y / 6, seed + 51) - 0.5) * 6)
      const sx = Math.min(pw - 1, Math.max(0, x + jx)),
        sy = Math.min(ph - 1, Math.max(0, y + jy))
      const i = y * pw + x
      const j = harbor(rawRegion[i]) || harbor(rawRegion[sy * pw + sx]) ? i : sy * pw + sx
      region[i] = rawRegion[j]
      wet[i] = rawWater[j]
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
  for (const r of footprints(atlas))
    for (let y = toPx(r.y); y < toPx(r.y1); y++)
      for (let x = toPx(r.x); x < toPx(r.x1); x++)
        if (x >= 0 && y >= 0 && x < pw && y < ph) content[y * pw + x] = built[y * pw + x] = 1
  return { content, built }
}

/** 孤岛的海岸（见 island.ts），再把外圈并进 wet、码头的木墙从 wet 里划掉；seaAround 是一处周围 21×21 里海的比例 */
function coastOf(
  atlas: Atlas,
  facing: Map<string, [number, number]>,
  content: Uint8Array,
  deck: Uint8Array,
  wet: Uint8Array,
  design: Design | undefined,
  pw: number,
  ph: number,
  seed: number
) {
  const {
    sea,
    inland,
    spring,
    piers,
    quay,
    rocks,
    docks,
    toSea: depth,
  } = island(atlas, { content, water: wet, deck, facing, design }, pw, ph, seed)
  for (let i = 0; i < pw * ph; i++) if (sea[i]) wet[i] = 1
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
  return { sea, inland, spring, piers, quay, rocks, docks, depth, seaAround }
}

/** 温泉池沿有几圈像素宽（两层石头） */
const RIM = 6

/** 温泉四周不种树：池边 CLEAR 像素内，池子南边（镜头这一侧）再多留 CLEAR_SOUTH 像素，
 *  不然树立起来挡住池子 */
const CLEAR = 9
const CLEAR_SOUTH = 26

/** 温泉池边的陆地：离温泉水 1～RIM 像素的记下离水几像素，铺黑石头（见 springStone）；
 *  clear 标出池子四周不种树的一圈（见 CLEAR） */
function springRim(spring: Uint8Array, wet: Uint8Array, pw: number, ph: number) {
  const rim = new Uint8Array(pw * ph),
    clear = new Uint8Array(pw * ph)
  if (!spring.some(Boolean)) return { rim, clear }
  const to = distance(spring, pw, ph)
  for (let i = 0; i < pw * ph; i++) {
    if (!wet[i] && to[i] <= RIM + 0.4) rim[i] = Math.max(1, Math.round(to[i]))
    if (to[i] <= CLEAR) clear[i] = 1
  }
  // 往南：每一列从上往下数离上一个温泉像素多远，再左右放宽几格
  const south = new Uint8Array(pw * ph)
  for (let x = 0; x < pw; x++) {
    let last = -1e9
    for (let y = 0; y < ph; y++) {
      const i = y * pw + x
      if (spring[i]) last = y
      if (y - last <= CLEAR_SOUTH) south[i] = 1
    }
  }
  for (let y = 0; y < ph; y++)
    for (let x = 4; x < pw - 4; x++)
      for (let dx = -4; dx <= 4; dx++)
        if (south[y * pw + x + dx]) {
          clear[y * pw + x] = 1
          break
        }
  return { rim, clear }
}

/** 温泉池沿：一圈压雪的黑石头。石头 4×3 像素一块，一行行错开半块：顶上一行压着雪，
 *  中间一行左亮右暗，底下一行压暗；块之间露出雪。贴水的一圈被热气熏着不积雪、缝是黑的，
 *  最外一圈石头稀稀落落，空处是雪 */
function springStone(L: Layers, i: number, x: number, y: number) {
  const r = L.rim[i]
  const row = Math.floor(y / 3)
  const sx = x + (row % 2) * 2
  const col = Math.floor(sx / 4),
    lx = sx % 4,
    ly = y % 3
  const id = hash(col, row, L.seed + 71)
  if (r >= RIM - 1 && id < 0.5) return u(r >= RIM ? SNOW : SNOW_SHADE)
  if (lx === 3) return u(r <= 2 ? '#1d2127' : ly === 0 ? SNOW : SNOW_SHADE)
  const dark = id < 0.4
  if (ly === 0)
    return r > 2 && hash(col, row, L.seed + 72) < 0.6 ? u(SNOW) : u(dark ? '#4c535d' : '#5d6570')
  if (ly === 1) return u(lx === 0 ? (dark ? '#464c56' : '#5b636f') : dark ? '#353a42' : '#454c56')
  return u(dark ? '#23272d' : '#2e3339')
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
  const { sea, quay, rocks, depth, seaAround } = coast
  const coastW = new Float32Array((pw + 1) * (ph + 1)),
    coastN = new Int32Array((pw + 1) * (ph + 1))
  for (let y = 0; y < ph; y++) {
    let rw = 0,
      rn = 0
    for (let x = 0; x < pw; x++) {
      const i = y * pw + x
      const coast =
        !wet[i] && !rocks[i] && !quay[i] && (sea[i - 1] || sea[i + 1] || sea[i - pw] || sea[i + pw])
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
      if (wet[i] || built[i] || quay[i] || rocks[i] || depth[i] > 24) continue
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
  const { rocks, wet, pw } = L
  const solid = (j: number) => rocks[j] || !wet[j]
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

/** 逐像素铺地面：外圈和水面、码头的木墙、礁石、沙滩，其余按区域材质；木码头再收边（见 deckEdge） */
function paintBase(L: Layers, px: Uint32Array) {
  const { pw, ph, seed, theme, wet, depth, quay, rocks, path, shoreWidth } = L
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
      if (quay[i]) {
        px[i] = quayColor(G, quay[i], x)
        continue
      }
      if (rocks[i]) {
        px[i] = stone(L, i, x, y)
        continue
      }
      if (L.rim[i]) {
        px[i] = springStone(L, i, x, y)
        continue
      }
      const shore = shoreKind(L, i)
      if (shore && shore < 4) {
        px[i] = shoreColor(L, i, x, y, shore)
        continue
      }
      const kind = groundKind(L, i)
      const trodden = !PAVED.has(kind) && (path[i] === 2 || (path[i] === 1 && bayer(x, y) < 0.5))
      px[i] = groundColor(trodden ? 'path' : kind, x, y, seed, G, (c) => {
        if (y > 0) px[i - pw] = c
      })
      if (L.deck[i]) px[i] = deckEdge(L, i, x, y, px[i])
      // 过渡带：越靠沙滩沙子越多，按有序抖动和草地交错，偶尔一丛海草
      if (shore === 4 && !trodden) {
        const t = (shoreWidth[i] + 5 - depth[i]) / 6
        if (bayer(x, y) < t) px[i] = u(pick(G.sand, 0.9, x, y, 1))
        else if (hash(x, y, seed + 16) < 0.05) px[i] = u(G.shoreWeed)
      }
    }
}

/** 一个像素按什么画地面：区域的 decor 是沥青、碎石的照它画，不然按区域的种类 */
function groundKind(L: Layers, i: number) {
  const decor = L.decorAt(i)
  return decor && DECOR_GROUNDS.has(decor) ? decor : L.kindAt(i)
}

/** 码头朝南临水那一面（row 是 Island.quay 的 1～3）：两行横着的墙板，越往下越暗；
 *  桩每隔 QUAY.post 像素一根，两像素宽，左亮右暗，伸进水里那一截长了青苔 */
function quayColor(G: GroundPalette, row: number, x: number) {
  const wood = u(G.plank[0])
  if (x % QUAY.post < 2) {
    const post = mix(wood, SHADOW, x % QUAY.post ? 0.55 : 0.3)
    return row === QUAY.face ? mix(post, u('#2f4a3c'), 0.35) : post
  }
  return mix(wood, SHADOW, row === 1 ? 0.42 : 0.62)
}

/** 木码头收边：临水的一圈是压顶木（外沿一行亮、里面一行暗缝），隔 QUAY.post 像素露出一个桩头，
 *  和朝南那面墙上的桩对齐；挨着陆地的一圈压一道深色边框 */
function deckEdge(L: Layers, i: number, x: number, y: number, c: number) {
  const { pw, wet, deck, quay } = L
  const G = L.theme.ground
  const water = (j: number) => wet[j] || quay[j]
  const solid = (j: number) => deck[j] && !water(j)
  // 临水的一边（西、东、北、南）：先看紧挨着的一格（外沿那行），再看隔着一格码头的（里面那行）
  const steps = [-1, 1, -pw, pw]
  let outer = true
  let side = steps.findIndex((d) => water(i + d))
  if (side < 0) {
    outer = false
    side = steps.findIndex((d) => water(i + 2 * d) && solid(i + d))
  }
  if (side >= 0) {
    const vertical = side < 2
    const along = (vertical ? y : x) % QUAY.post
    if (along < 2) {
      // 桩头：2×2 的圆木截面，左上亮、右下暗
      const across = outer === (side % 2 === 0) ? 0 : 1
      const [col, row] = vertical ? [across, along] : [along, across]
      const tone = col + row
      return tone === 0
        ? mix(u(G.plank[2]), u('#fff4dc'), 0.3)
        : mix(u(G.plank[0]), SHADOW, tone === 1 ? 0.3 : 0.55)
    }
    return outer ? mix(u(G.plank[2]), u('#fff4dc'), 0.18) : mix(u(G.plankLine), SHADOW, 0.2)
  }
  const ground = (j: number) => !wet[j] && !quay[j] && !deck[j]
  if (steps.some((d) => ground(i + d))) return mix(u(G.plankLine), SHADOW, 0.25)
  return c
}

/** 岸线：水边一圈浪花（废土里是旧海岸的土坎），岸上一圈湿痕；木码头自己收边（见 deckEdge） */
function paintShoreline(L: Layers, px: Uint32Array) {
  const { pw, ph, wet, deck, quay, rocks } = L
  const G = L.theme.ground
  for (let y = 1; y < ph - 1; y++)
    for (let x = 1; x < pw - 1; x++) {
      const i = y * pw + x
      const n = wet[i - 1] + wet[i + 1] + wet[i - pw] + wet[i + pw]
      if (wet[i]) {
        if (n < 4) px[i] = u(G.outerEdge)
      } else if (n > 0 && !deck[i] && !quay[i] && !rocks[i] && !L.rim[i] && !beach(L, i))
        px[i] = mix(px[i], SHADOW, 0.35)
    }
}

/** 码头一带的水不起浪：离木码头、码头的木墙和栈桥 12 像素内全静，再往外 16 像素淡掉（0～254）；
 *  紧贴着它们的一圈记 255，海面在那里画木头底下的暗影和拍桩的水纹。
 *  外圈是海时码头边的水还要加深：靠着的是码头不是沙滩的地方按深一些的档画，不透出沙底 */
function calmOf(L: Layers, deepen: boolean) {
  const { pw, ph, wet, deck, quay, piers, depth } = L
  const built = new Uint8Array(pw * ph),
    shore = new Uint8Array(pw * ph)
  for (let i = 0; i < pw * ph; i++) {
    built[i] = deck[i] || quay[i] || piers[i] ? 1 : 0
    shore[i] = !wet[i] && !built[i] ? 1 : 0
  }
  const toBuilt = distance(built, pw, ph),
    toShore = distance(shore, pw, ph)
  const calm = new Uint8Array(pw * ph)
  for (let i = 0; i < pw * ph; i++) {
    if (!wet[i]) continue
    const k = Math.min(1, Math.max(0, (28 - toBuilt[i]) / 16))
    calm[i] = toBuilt[i] <= 1 ? 255 : Math.round(k * 254)
    if (deepen && k > 0 && toBuilt[i] <= toShore[i] + 2)
      depth[i] = Math.min(MAX_DEPTH, depth[i] + Math.round(7 * k))
  }
  return calm
}

/** 海边的地物：1 是和外海连着的水（港口的水也算，池塘和岛内的河湖不算），2 是外海边的沙滩，
 *  3 是外海边的岩石岸和礁石，4 是温泉的水。立体场景只在外海上起浪，浪冲上沙滩、拍在岩石上；
 *  温泉另画（见 sea.ts） */
function shoreOf(L: Layers) {
  const { pw, ph, wet, rocks, inland, spring } = L
  const out = new Uint8Array(pw * ph)
  // 从地图四边的水往里灌，灌得到的就是外海；岛内的水和外海连着也不灌进去
  const stack: number[] = []
  const push = (i: number) => {
    if (!wet[i] || inland[i] || out[i]) return
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
    if (wet[i]) {
      if (spring[i]) out[i] = 4
      continue
    }
    const kind = shoreKind(L, i)
    if (rocks[i] || kind === 1) out[i] = 3
    else if (kind === 2 || kind === 3) out[i] = 2
  }
  return out
}

/** 能种东西的空地，立体场景按它撒树、放微粒 */
function openGround(atlas: Atlas, L: Layers) {
  const { pw, ph, wet, path, quay, rocks } = L
  const open = new Uint8Array(pw * ph)
  for (let i = 0; i < pw * ph; i++) {
    const kind = L.kindAt(i)
    if (wet[i] || path[i] || quay[i] || rocks[i] || L.clear[i] || beach(L, i) || PAVED.has(kind))
      continue
    const decor = L.decorAt(i)
    open[i] =
      (decor === 'clearing' || (decor && DECOR_GROUNDS.has(decor))
        ? OPEN.none
        : decor === 'lawn'
          ? OPEN.lawn
          : OPEN_KINDS[kind]) ?? OPEN.town
  }
  for (const r of footprints(atlas)) {
    const x0 = toPx(r.x) - 6,
      y0 = toPx(r.y) - 6
    const x1 = toPx(r.x1) + 6,
      y1 = toPx(r.y1) + 6
    for (let y = Math.max(0, y0); y < Math.min(ph, y1); y++)
      for (let x = Math.max(0, x0); x < Math.min(pw, x1); x++) open[y * pw + x] = OPEN.none
  }
  return open
}

/** 房子和只看不进的楼（Atlas 的 ruins）的占地，地图坐标 */
function footprints(atlas: Atlas) {
  return [
    ...atlas.spaces.filter((s) => s.id !== OUTDOOR_SPACE).map((s) => roomRect(s)),
    ...(atlas.ruins ?? []).map((r) => ({ x: r.x, y: r.y, x1: r.x + r.w, y1: r.y + r.h })),
  ]
}

/** 空地分类：none 不能种东西（水、路、铺装、房屋四周），其余按所在区域；lawn 是草坪公园，树和草都稀 */
export const OPEN = { none: 0, wild: 1, park: 2, garden: 3, town: 4, lawn: 5 } as const
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

/** 旧沥青路面：深灰底，成片龟裂成黑缝，风刮来的沙在上面积成一摊摊 */
function asphaltColor({ x, y, seed, cracked }: Spot) {
  if (cracked(7)) return u('#2a2826')
  const n = noise(x / 5, y / 5, seed + 4)
  if (noise(x / 16, y / 16, seed + 9) > 0.66) return u(n > 0.5 ? '#9a8668' : '#8a785c')
  return u(n > 0.66 ? '#57534e' : n > 0.33 ? '#4c4844' : '#43403c')
}

/** 碎石废墟地：野地上撒满碎水泥块，大块的亮、碎屑发暗 */
function rubbleColor(s: Spot, paintAbove: (c: number) => void) {
  const { x, y, seed } = s
  if (hash(x, y, seed + 41) < 0.1) return u('#8a8478')
  if (hash(x >> 1, y >> 1, seed + 43) < 0.06) return u('#6e6a62')
  return grassColor(s, false, paintAbove)
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
    case 'asphalt':
      return asphaltColor(spot)
    case 'rubble':
      return rubbleColor(spot, paintAbove)
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

/** 只看不进的楼（Atlas 的 ruins）在平面图上：一块灰水泥楼顶，四边一圈深色女儿墙，东边、南边压一道影子 */
function ruinTop(r: NonNullable<Atlas['ruins']>[number], put: Put, darken: Darken) {
  const x = toPx(r.x),
    y = toPx(r.y)
  const w = toPx(r.x + r.w) - x,
    h = toPx(r.y + r.h) - y
  for (let yy = y + 3; yy < y + h + 6; yy++)
    for (let xx = x + 3; xx < x + w + 6; xx++)
      if ((xx >= x + w || yy >= y + h) && bayer(xx, yy) < 0.85) darken(xx, yy, 0.45)
  for (let yy = y; yy < y + h; yy++)
    for (let xx = x; xx < x + w; xx++) {
      const edge = xx === x || yy === y || xx === x + w - 1 || yy === y + h - 1
      put(xx, yy, u(edge ? '#5e5a54' : hash(xx >> 2, yy >> 2, 7) < 0.15 ? '#77736b' : '#8a867e'))
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
