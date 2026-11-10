import type { Atlas, IslandDesign } from 'town-shared/mapDocument'
import { buildingKind } from '../buildings'
import { MARGIN, PIXEL, roomRect, toPx } from '../grid'
import { fbm, hash } from './noise'

// 2D 小镇是四面环海的孤岛。海岸分三步算出来，全部按地面画布的像素算，一个像素 = PIXEL 个世界单位：
// 1. 初始轮廓：取镇上所有东西（区域、房屋、道路）的凸包，海岸在凸包外一段距离；
//    采样前先按大尺度噪声把坐标扭一扭，凸包的直边就变成大弯；
// 2. 冲刷：沿岸的陆地一轮轮被海浪啃掉。每个像素有一个「岩石硬度」（噪声），软的地方啃得快，
//    成了海湾；硬的地方留下来，成了岬角；伸进海里的地方三面受浪，啃得更快。
//    啃完再把孤立的尖角和一格的缺口抹平；
// 3. 啃断后留在海里的小块陆地和近岸随机撒的几处，画成礁石。
// 镇上的东西四周始终留一圈陆地。港口和海塔朝海的一侧把海岸收到旁边。
// 地图画好了海岸（Atlas.island）时，第 1 步的凸包换成画好的陆地，冲刷的参数也照它给的；
// 冲刷完再挖出岛内的河、湖、港湾（inland），边保持原样，不跟着海岸扭；其中标成温泉的另记一份（spring）。
// 港口的木码头朝南临水的一面往下画出木墙和桩（quay），再从岸线往水里伸出栈桥：
// 这里只定位置和尺寸，桥是立体场景搭的（hd2d/pier.ts），桥下仍是水。

/** 海岸的样子：coast 海岸离凸包的平均距离，bay 大弯的深浅，warp 扭曲的幅度（像素）；
 *  erosion 冲刷的轮数；rim 镇上东西四周至少留这么宽的陆地。地图画好了海岸时按它给的改 */
const SHAPE = { coast: 34, bay: 26, warp: 60, erosion: 80, rim: 6 }
type Shape = typeof SHAPE

/** 画好的海岸铺到地面像素上：land 是陆地底稿，water 是岛内的水，spring 是其中的温泉 */
export interface Design {
  land: Uint8Array
  water: Uint8Array
  spring: Uint8Array
  /** 镜池：平得像镜子的池塘，倒影格外清楚 */
  mirror: Uint8Array
  shape: Shape
}
/** 港口、海塔朝海一侧离海岸的距离（像素） */
const NEAR = { harbor: 1, lighthouse: 3 }
/** 算水深时最多数到这么多像素，再远都算深海 */
export const MAX_DEPTH = 40

/** 以 size 像素为特征尺度的噪声，大致落在 -1..1（fbm 自带 40 像素的尺度） */
const wave = (x: number, y: number, size: number, s: number) =>
  Math.max(-1, Math.min(1, (fbm((x * 40) / size, (y * 40) / size, s) - 0.5) * 3))

/** 一条栈桥：根部在岸线上，横平竖直地伸进水里，尽头一块平台往一边伸出去（L 形）。
 *  平台伸向「前面」：横向的桥是南边（朝镜头），竖向的桥是东边；桥身另一边整条留给船靠 */
export interface Dock {
  /** 根部、桥身中线上的一点（像素格的边界；场景里换成地图坐标） */
  x: number
  y: number
  /** 朝水里的方向（横竖之一） */
  dx: number
  dy: number
  /** 从根部往外的长度（含尽头平台） */
  length: number
  /** 桥身宽 */
  width: number
  /** 尽头平台沿栈桥方向的进深、横向的宽（从桥身后沿量起）；和桥身一样宽时就是没有平台 */
  head: [number, number]
}

/** 地图坐标的栈桥上，沿桥 u、横过桥 v（地面像素，可带小数）换成地图坐标 [x, y]。
 *  v 从桥身后沿量起，往前（横向桥朝南、竖向桥朝东）增大 */
export function placer(d: Dock) {
  const W = d.width / PIXEL
  return (u: number, v: number): [number, number] => {
    const a = u * PIXEL,
      b = (v - W / 2) * PIXEL
    return [d.x + d.dx * a + Math.abs(d.dy) * b, d.y + d.dy * a + Math.abs(d.dx) * b]
  }
}

/** 地图坐标的栈桥的平面形状（地面像素格）：长 L，桥身占 v ∈ [0, W)，尽头平台从 headU 起占 v ∈ [0, V) */
export function footprint(d: Dock) {
  const L = Math.round(d.length / PIXEL),
    V = Math.round(d.head[1] / PIXEL),
    W = Math.round(d.width / PIXEL),
    headU = L - Math.round(d.head[0] / PIXEL)
  const inside = (u: number, v: number) =>
    u >= 0 && u < L && v >= 0 && v < V && (u >= headU || v < W)
  return { L, V, W, headU, inside }
}

/** 栈桥桥身宽、尽头平台的进深和宽（像素） */
const PIER = { width: 8, headDepth: 7, headWidth: 20 }
/** 栈桥从天然的海边伸出去时：水边参差，桥头往岸上退几格、头几行容许压着沙滩（跳板就搭在沙滩上）；
 *  木码头离海边超过 reach 像素就不搭，免得桥离港口太远 */
const BEACH_PIER = { back: 2, slack: 4, reach: 48 }
/** 码头临水朝南的一面往下画几行：两行木墙，一行露出水面的桩；桩每隔 POST 像素一根 */
export const QUAY = { face: 3, post: 8 }

export interface Island {
  /** 海面像素（不含港口和公园里原有的水） */
  sea: Uint8Array
  /** 画好的海岸里挖出来的岛内水面（已并进 water）：河、湖、港湾不起浪，岸边不铺沙 */
  inland: Uint8Array
  /** 岛内水面里的温泉（inland 的一部分） */
  spring: Uint8Array
  /** 岛内水面里的镜池 */
  mirror: Uint8Array
  /** 栈桥（含尽头平台）在水面上的投影，桥下仍是水 */
  piers: Uint8Array
  /** 码头朝南临水那一面往下画的木墙：1、2 是两行墙板，3 是露出水面的桩；不算水 */
  quay: Uint8Array
  /** 礁石像素：画石头，不算水 */
  rocks: Uint8Array
  /** 每条栈桥（像素） */
  docks: Dock[]
  /** 陆地像素离海多远，海面像素离岸多远，都到 MAX_DEPTH 为止 */
  toSea: Uint8Array
}

/** 两遍倒角距离变换：每个像素到最近 source 像素的距离（像素，近似欧氏） */
export function distance(source: Uint8Array, w: number, h: number) {
  const d = new Float32Array(w * h)
  for (let i = 0; i < w * h; i++) d[i] = source[i] ? 0 : 1e9
  const D = Math.SQRT2
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const i = y * w + x
      if (x > 0) d[i] = Math.min(d[i], d[i - 1] + 1)
      if (y > 0) {
        d[i] = Math.min(d[i], d[i - w] + 1)
        if (x > 0) d[i] = Math.min(d[i], d[i - w - 1] + D)
        if (x < w - 1) d[i] = Math.min(d[i], d[i - w + 1] + D)
      }
    }
  for (let y = h - 1; y >= 0; y--)
    for (let x = w - 1; x >= 0; x--) {
      const i = y * w + x
      if (x < w - 1) d[i] = Math.min(d[i], d[i + 1] + 1)
      if (y < h - 1) {
        d[i] = Math.min(d[i], d[i + w] + 1)
        if (x < w - 1) d[i] = Math.min(d[i], d[i + w + 1] + D)
        if (x > 0) d[i] = Math.min(d[i], d[i + w - 1] + D)
      }
    }
  return d
}

/** 镇上东西的凸包画成一块多边形（单调链求凸包，按行扫描填充） */
function hullMask(content: Uint8Array, w: number, h: number) {
  const pts: [number, number][] = []
  for (let y = 0; y < h; y += 2)
    for (let x = 0; x < w; x += 2) if (content[y * w + x]) pts.push([x, y])
  pts.sort((p, q) => p[0] - q[0] || p[1] - q[1])
  const cross = (o: number[], a: number[], b: number[]) =>
    (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
  const half = (list: [number, number][]) => {
    const out: [number, number][] = []
    for (const p of list) {
      while (out.length >= 2 && cross(out[out.length - 2], out[out.length - 1], p) <= 0) out.pop()
      out.push(p)
    }
    out.pop()
    return out
  }
  const hull = [...half(pts), ...half([...pts].reverse())]
  const mask = new Uint8Array(w * h)
  if (hull.length < 3) return mask
  for (let y = 0; y < h; y++) {
    const xs: number[] = []
    for (let k = 0; k < hull.length; k++) {
      const [x0, y0] = hull[k],
        [x1, y1] = hull[(k + 1) % hull.length]
      if (y0 === y1 || y < Math.min(y0, y1) || y >= Math.max(y0, y1)) continue
      xs.push(x0 + ((y - y0) * (x1 - x0)) / (y1 - y0))
    }
    if (xs.length < 2) continue
    const lo = Math.max(0, Math.ceil(Math.min(...xs))),
      hi = Math.min(w - 1, Math.floor(Math.max(...xs)))
    for (let x = lo; x <= hi; x++) mask[y * w + x] = 1
  }
  return mask
}

/** 多边形按行扫描填进 mask（奇偶规则）；地图坐标，按像素中心判断 */
function fillPolygon(mask: Uint8Array, pts: [number, number][], w: number, h: number) {
  if (pts.length < 3) return
  for (let y = 0; y < h; y++) {
    const my = y * PIXEL - MARGIN + PIXEL / 2
    const xs: number[] = []
    for (let k = 0; k < pts.length; k++) {
      const [x0, y0] = pts[k],
        [x1, y1] = pts[(k + 1) % pts.length]
      if (y0 > my === y1 > my) continue
      xs.push(x0 + ((my - y0) * (x1 - x0)) / (y1 - y0))
    }
    xs.sort((a, b) => a - b)
    for (let k = 0; k + 1 < xs.length; k += 2) {
      const lo = Math.max(0, Math.ceil((xs[k] + MARGIN) / PIXEL - 0.5)),
        hi = Math.min(w - 1, Math.floor((xs[k + 1] + MARGIN) / PIXEL - 0.5))
      for (let x = lo; x <= hi; x++) mask[y * w + x] = 1
    }
  }
}

/** 带宽度的折线（河）填进 mask：离折线不到半宽的像素 */
function fillLine(mask: Uint8Array, pts: [number, number][], width: number, w: number, h: number) {
  const half = width / 2
  for (let k = 0; k + 1 < pts.length; k++) {
    const [ax, ay] = pts[k],
      [bx, by] = pts[k + 1]
    const dx = bx - ax,
      dy = by - ay,
      len2 = dx * dx + dy * dy
    const x0 = Math.max(0, toPx(Math.min(ax, bx) - half) - 1),
      x1 = Math.min(w - 1, toPx(Math.max(ax, bx) + half) + 1)
    const y0 = Math.max(0, toPx(Math.min(ay, by) - half) - 1),
      y1 = Math.min(h - 1, toPx(Math.max(ay, by) + half) + 1)
    for (let y = y0; y <= y1; y++)
      for (let x = x0; x <= x1; x++) {
        const px = x * PIXEL - MARGIN + PIXEL / 2,
          py = y * PIXEL - MARGIN + PIXEL / 2
        const t = len2 ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) : 0
        if (Math.hypot(px - ax - t * dx, py - ay - t * dy) <= half) mask[y * w + x] = 1
      }
  }
}

/** 画好的海岸铺到 w×h 的地面像素上；地图没画海岸时没有 */
export function designOf(design: IslandDesign | undefined, w: number, h: number) {
  if (!design?.land.length) return undefined
  const land = new Uint8Array(w * h),
    water = new Uint8Array(w * h),
    spring = new Uint8Array(w * h),
    mirror = new Uint8Array(w * h)
  for (const pts of design.land) fillPolygon(land, pts, w, h)
  for (const part of design.water) {
    const into =
      part.kind === 'spring' ? [water, spring] : part.kind === 'mirror' ? [water, mirror] : [water]
    for (const mask of into)
      if ('polygon' in part) fillPolygon(mask, part.polygon, w, h)
      else fillLine(mask, part.line, part.width, w, h)
  }
  const shape = { ...SHAPE }
  for (const key of Object.keys(shape) as (keyof Shape)[]) {
    const v = design[key]
    if (typeof v === 'number' && Number.isFinite(v)) shape[key] = v
  }
  return { land, water, spring, mirror, shape } satisfies Design
}

/** 从画布边缘灌水，连不到外海的海面改回陆地，免得镇子中间冒出一小块海 */
function keepOpenSea(sea: Uint8Array, w: number, h: number) {
  const reached = new Uint8Array(w * h)
  const queue: number[] = []
  for (let x = 0; x < w; x++) for (const y of [0, h - 1]) if (sea[y * w + x]) queue.push(y * w + x)
  for (let y = 0; y < h; y++) for (const x of [0, w - 1]) if (sea[y * w + x]) queue.push(y * w + x)
  for (const i of queue) reached[i] = 1
  while (queue.length) {
    const i = queue.pop()!
    const x = i % w
    for (const j of [i - w, i + w, x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1])
      if (j >= 0 && j < w * h && sea[j] && !reached[j]) {
        reached[j] = 1
        queue.push(j)
      }
  }
  for (let i = 0; i < w * h; i++) if (sea[i] && !reached[i]) sea[i] = 0
}

interface Anchor {
  x: number
  y: number
  /** 朝镇外的单位方向 */
  dx: number
  dy: number
  /** 自身半宽（像素） */
  half: number
  near: number
}

/** 港口和海塔：朝镇外（离镇上东西的重心）的方向，海岸在它们朝海的一侧收近。
 *  港口的方向用 facing 给的横竖方向，和港口里的水、栈桥一致 */
function anchorsOf(
  atlas: Atlas,
  content: Uint8Array,
  facing: Map<string, [number, number]>,
  pw: number,
  ph: number
): Anchor[] {
  let cx = 0,
    cy = 0,
    n = 0
  for (let i = 0; i < pw * ph; i++)
    if (content[i]) {
      cx += i % pw
      cy += Math.floor(i / pw)
      n++
    }
  cx /= Math.max(1, n)
  cy /= Math.max(1, n)
  const anchors: Anchor[] = []
  const outward = (x: number, y: number, half: number, near: number, toward?: number[]) => {
    const len = Math.hypot(x - cx, y - cy) || 1
    const [dx, dy] = toward ?? [(x - cx) / len, (y - cy) / len]
    anchors.push({ x, y, dx, dy, half, near })
  }
  for (const r of atlas.regions) {
    if (r.kind !== 'harbor' || !r.cells.length) continue
    const ax = r.cells.reduce((s, [c]) => s + toPx((c + 0.5) * r.cell_size), 0) / r.cells.length
    const ay = r.cells.reduce((s, [, k]) => s + toPx((k + 0.5) * r.cell_size), 0) / r.cells.length
    const half = Math.sqrt(r.cells.length) * (r.cell_size / 6) * 0.5
    outward(ax, ay, half, NEAR.harbor, facing.get(r.id))
  }
  for (const s of atlas.spaces) {
    if (buildingKind(s) !== 'lighthouse') continue
    const r = roomRect(s)
    const x0 = toPx(r.x),
      x1 = toPx(r.x1)
    const y0 = toPx(r.y),
      y1 = toPx(r.y1)
    outward((x0 + x1) / 2, (y0 + y1) / 2, Math.max(x1 - x0, y1 - y0) / 2, NEAR.lighthouse)
  }
  return anchors
}

/** 1. 初始轮廓：凸包（画好了海岸时是画好的陆地）外一段距离是海，坐标先按大尺度噪声扭一扭；
 *  band 是之后会被冲刷的一带 */
function initialCoast(
  hull: Uint8Array,
  shape: Shape,
  locked: (i: number) => unknown,
  pw: number,
  ph: number,
  seed: number
) {
  const { coast: COAST, bay: BAY, warp: WARP, erosion: EROSION } = shape
  const outside = new Uint8Array(pw * ph)
  for (let i = 0; i < pw * ph; i++) outside[i] = hull[i] ? 0 : 1
  const toHull = distance(hull, pw, ph),
    inHull = distance(outside, pw, ph)
  const sea = new Uint8Array(pw * ph)
  const band: number[] = []
  for (let y = 0; y < ph; y++)
    for (let x = 0; x < pw; x++) {
      const i = y * pw + x
      if (locked(i)) continue
      const sx = Math.min(pw - 1, Math.max(0, Math.round(x + wave(x, y, 220, seed + 310) * WARP)))
      const sy = Math.min(ph - 1, Math.max(0, Math.round(y + wave(x, y, 220, seed + 311) * WARP)))
      const j = sy * pw + sx
      const signed = hull[j] ? -inHull[j] : toHull[j]
      const edge = signed - (COAST + wave(x, y, 140, seed + 300) * BAY)
      if (edge > 0) sea[i] = 1
      // 冲刷只会发生在初始海岸往里这一带
      if (edge > -EROSION - 6 && edge <= 2 && x > 2 && y > 2 && x < pw - 3 && y < ph - 3)
        band.push(i)
    }
  return { sea, band }
}

/** 2. 冲刷：只看当前的岸线像素，每轮啃掉一些，被啃处的邻居变成新的岸线；啃完抹平尖角和缺口 */
function erode(
  sea: Uint8Array,
  band: number[],
  rounds: number,
  pw: number,
  ph: number,
  seed: number
) {
  const inBand = new Uint8Array(pw * ph)
  const hard = new Float32Array(pw * ph)
  for (const i of band) {
    inBand[i] = 1
    const x = i % pw,
      y = (i - x) / pw
    // 硬度拉开两头：软岩成片啃成海湾，硬岩成片留下成岬角，小尺度再掺一点让岸线不平
    const h = wave(x, y, 70, seed + 320) * 0.8 + wave(x, y, 16, seed + 321) * 0.35
    hard[i] = Math.max(0, Math.min(1, 0.5 + h * 1.1))
  }
  const onShore = (i: number) =>
    inBand[i] && !sea[i] && (sea[i - 1] || sea[i + 1] || sea[i - pw] || sea[i + pw])
  let shoreline = band.filter(onShore)
  const listed = new Uint8Array(pw * ph)
  for (let round = 0; round < rounds; round++) {
    const bite: number[] = []
    const keep: number[] = []
    for (const i of shoreline) {
      if (!onShore(i)) continue
      let open = 0
      for (let dy = -2; dy <= 2; dy++)
        for (let dx = -2; dx <= 2; dx++) open += sea[i + dy * pw + dx]
      const soft = 1 - hard[i]
      const chance = soft * soft * soft * (0.2 + open / 20)
      if (hash(i, round, seed + 330) < chance) bite.push(i)
      else keep.push(i)
    }
    for (const i of bite) sea[i] = 1
    listed.fill(0)
    shoreline = []
    for (const i of [...keep, ...bite.flatMap((b) => [b - 1, b + 1, b - pw, b + pw])])
      if (!listed[i] && onShore(i)) {
        listed[i] = 1
        shoreline.push(i)
      }
  }
  // 抹平：三面临海的陆地尖角并进海里，三面是陆地的一格缺口填上
  for (let pass = 0; pass < 2; pass++)
    for (const i of band) {
      const n = sea[i - 1] + sea[i + 1] + sea[i - pw] + sea[i + pw]
      if (!sea[i] && n >= 3) sea[i] = 1
      else if (sea[i] && n <= 1) sea[i] = 0
    }
}

/** 港口、海塔朝海的一侧把海岸收近，越往两边收得越少，挖出来是一个圆弧的湾 */
function pullCoast(
  sea: Uint8Array,
  anchors: Anchor[],
  fromContent: Float32Array,
  locked: (i: number) => unknown,
  pw: number,
  ph: number
) {
  for (let y = 0; y < ph; y++)
    for (let x = 0; x < pw; x++) {
      const i = y * pw + x
      if (sea[i] || locked(i)) continue
      let near = Infinity
      for (const a of anchors) {
        const vx = x - a.x,
          vy = y - a.y
        const along = vx * a.dx + vy * a.dy,
          across = Math.abs(vx * a.dy - vy * a.dx)
        const side = Math.min(1, Math.max(0, (a.half * 1.6 + 30 - across) / 30))
        const ahead = Math.min(1, Math.max(0, (along + 4) / 12))
        const w = side * ahead
        if (w > 0) near = Math.min(near, a.near + (1 - w) * 36)
      }
      if (fromContent[i] > near) sea[i] = 1
    }
}

/** 3. 礁石：和镇子连不上的小块陆地（太碎的并进海里），加上近岸随机的几处；港口、海塔前面留出航道 */
function rocksOf(
  sea: Uint8Array,
  content: Uint8Array,
  band: number[],
  anchors: Anchor[],
  pw: number,
  ph: number,
  seed: number
) {
  const rocks = new Uint8Array(pw * ph)
  const mainland = new Uint8Array(pw * ph)
  const queue: number[] = []
  for (let i = 0; i < pw * ph; i++)
    if (content[i]) {
      mainland[i] = 1
      queue.push(i)
    }
  while (queue.length) {
    const i = queue.pop()!
    for (const j of [i - 1, i + 1, i - pw, i + pw])
      if (j >= 0 && j < pw * ph && !sea[j] && !mainland[j]) {
        mainland[j] = 1
        queue.push(j)
      }
  }
  const seen = new Uint8Array(pw * ph)
  for (const start of band) {
    if (sea[start] || mainland[start] || seen[start]) continue
    const part = [start]
    seen[start] = 1
    for (let k = 0; k < part.length; k++)
      for (const j of [part[k] - 1, part[k] + 1, part[k] - pw, part[k] + pw])
        if (!sea[j] && !mainland[j] && !seen[j]) {
          seen[j] = 1
          part.push(j)
        }
    for (const i of part) {
      if (part.length < 6) sea[i] = 1
      else rocks[i] = 1
    }
  }
  scatterRocks(sea, rocks, band, anchors, pw, ph, seed)
  for (let i = 0; i < pw * ph; i++) if (rocks[i]) sea[i] = 0
  return rocks
}

/** 近岸（离岸 3～12 像素）零星几块礁石，避开港口和海塔前面 */
function scatterRocks(
  sea: Uint8Array,
  rocks: Uint8Array,
  band: number[],
  anchors: Anchor[],
  pw: number,
  ph: number,
  seed: number
) {
  const shore = distance(
    Uint8Array.from(sea, (v) => 1 - v),
    pw,
    ph
  )
  const clear = (x: number, y: number) =>
    anchors.every((a) => Math.hypot(x - a.x, y - a.y) > a.half + 40)
  for (const i of band) {
    if (!sea[i] || shore[i] < 3 || shore[i] > 12 || hash(i, 1, seed + 340) > 0.0015) continue
    const x = i % pw,
      y = (i - x) / pw
    if (!clear(x, y)) continue
    const r = 1 + hash(i, 2, seed + 340) * 1.6
    for (let dy = -2; dy <= 2; dy++)
      for (let dx = -3; dx <= 3; dx++)
        if (Math.hypot(dx, dy * 1.3) <= r + hash(x + dx, y + dy, seed + 341) * 0.8)
          rocks[i + dy * pw + dx] = 1
  }
}

/** 栈桥：从港口中心顺着朝海的方向找到岸线（往回走出水、再往前走到水边），根部就在水边，
 *  往外伸 38～50 像素，尽头一块平台往前伸出去；港口很宽的分两条。整条桥（含平台）下面都得是水，
 *  半路碰到陆地或礁石就截短，太短不搭；平台放不下就不要平台。
 *  港口不临海时（水已改成木码头，见 dryHarbors），桥从前面的海边伸出去，桥头搭在沙滩上 */
function piersOf(
  sea: Uint8Array,
  water: Uint8Array,
  deck: Uint8Array,
  rocks: Uint8Array,
  anchors: Anchor[],
  pw: number,
  ph: number,
  seed: number
) {
  const piers = new Uint8Array(pw * ph)
  const docks: Dock[] = []
  const inside = (x: number, y: number) => x > 1 && y > 1 && x < pw - 2 && y < ph - 2
  const wet = (x: number, y: number) =>
    inside(x, y) &&
    (sea[y * pw + x] || water[y * pw + x]) &&
    !rocks[y * pw + x] &&
    !piers[y * pw + x]
  for (const a of anchors) {
    if (a.near !== NEAR.harbor) continue
    const sx = a.dx,
      sy = a.dy
    // 一般一条；港口很宽时两条，中间放得下前一条的平台和后一条后面靠的船
    const offsets = a.half > 50 ? [-a.half * 0.55, a.half * 0.55] : [0]
    offsets.forEach((off, k) => {
      let x = Math.round(a.x + (sx ? 0 : off)),
        y = Math.round(a.y + (sx ? off : 0))
      for (let n = 0; n < 200 && wet(x, y); n++) ((x -= sx), (y -= sy))
      // 往前走到水边；离开木码头后在陆上走了多远（港口和海之间隔着路时，桥从路那边的海边伸出去）
      let ashore = 0
      for (let n = 0; n < 200 && inside(x, y) && !wet(x, y); n++) {
        ashore = deck[y * pw + x] ? 0 : ashore + 1
        x += sx
        y += sy
      }
      if (!wet(x, y) || ashore > BEACH_PIER.reach) return
      // 横过桥面的一排像素（从桥身中线往后 back、往前 front）都是水
      const half = PIER.width / 2
      const across = (s: number, back: number, front: number) => {
        for (let t = -back; t < front; t++)
          if (!wet(x + sx * s + (sx ? 0 : t), y + sy * s + (sx ? t : 0))) return false
        return true
      }
      // 码头的岸线是直的，第一排就全是水；天然的海边参差，桥头退到沙滩上
      let ramp = 0
      while (ramp <= BEACH_PIER.slack && !across(ramp, half, half)) ramp++
      if (ramp > BEACH_PIER.slack) return
      if (ramp) {
        x -= sx * BEACH_PIER.back
        y -= sy * BEACH_PIER.back
        ramp += BEACH_PIER.back
      }
      const want = 38 + Math.floor(hash(k, Math.round(a.x * 7 + a.y), seed + 7) * 13)
      let length = ramp
      while (length < want && across(length, half, half)) length++
      if (length - ramp < 16) return
      let head = PIER.headWidth
      for (let s = length - PIER.headDepth; s < length; s++)
        if (!across(s, half, head - half)) head = PIER.width
      for (let s = 0; s < length; s++) {
        const front = (s >= length - PIER.headDepth ? head : PIER.width) - half
        for (let t = -half; t < front; t++) {
          const i = (y + sy * s + (sx ? t : 0)) * pw + x + sx * s + (sx ? 0 : t)
          if (sea[i] || water[i]) piers[i] = 1
        }
      }
      // 根部记在像素格的边界上：朝正方向时是根部像素的左（上）沿，朝负方向时是右（下）沿
      docks.push({
        x: x + (sx < 0 ? 1 : 0),
        y: y + (sy < 0 ? 1 : 0),
        dx: sx,
        dy: sy,
        length,
        width: PIER.width,
        head: [PIER.headDepth, head],
      })
    })
  }
  return { piers, docks }
}

/** 码头朝南临水的一面：木码头正下方的水往下画 QUAY.face 行（栈桥底下不画），
 *  前两行是墙板，第三行只在桩的位置有东西，其余仍是水 */
function quayOf(
  sea: Uint8Array,
  water: Uint8Array,
  deck: Uint8Array,
  piers: Uint8Array,
  pw: number,
  ph: number
) {
  const quay = new Uint8Array(pw * ph)
  for (let y = 1; y < ph - QUAY.face; y++)
    for (let x = 0; x < pw; x++) {
      if (!deck[(y - 1) * pw + x]) continue
      for (let k = 1; k <= QUAY.face; k++) {
        const i = (y + k - 1) * pw + x
        if (!(sea[i] || water[i]) || piers[i]) break
        const post = x % QUAY.post < 2
        if (k < QUAY.face || post) quay[i] = k
      }
    }
  for (let i = 0; i < pw * ph; i++)
    if (quay[i]) {
      sea[i] = 0
      water[i] = 0
    }
  return quay
}

/** 港口里的水连不到海（港口和海之间隔着路、房子），就成了镇子中间的一个水洼：
 *  改铺木码头，栈桥照旧顺着朝海的方向从前面的海边伸出去。公园的池塘不挨木码头，不受影响 */
function dryHarbors(sea: Uint8Array, water: Uint8Array, deck: Uint8Array, pw: number, ph: number) {
  const seen = new Uint8Array(pw * ph)
  for (let start = 0; start < pw * ph; start++) {
    if (!water[start] || seen[start]) continue
    const blob = [start]
    seen[start] = 1
    let harbor = false,
      open = false
    for (let n = 0; n < blob.length; n++) {
      const i = blob[n],
        x = i % pw
      for (const j of [i - pw, i + pw, x > 0 ? i - 1 : -1, x < pw - 1 ? i + 1 : -1]) {
        if (j < 0 || j >= pw * ph) continue
        if (deck[j]) harbor = true
        if (sea[j]) open = true
        if (water[j] && !seen[j]) {
          seen[j] = 1
          blob.push(j)
        }
      }
    }
    if (harbor && !open)
      for (const i of blob) {
        water[i] = 0
        deck[i] = 1
      }
  }
}

/** 陆地离海、海面离岸的像素数，给沙滩和水深用；栈桥架在水上，不算岸 */
function toSeaDistance(sea: Uint8Array, water: Uint8Array, pw: number, ph: number) {
  const allWater = new Uint8Array(pw * ph)
  const land = new Uint8Array(pw * ph)
  for (let i = 0; i < pw * ph; i++) {
    allWater[i] = sea[i] || water[i] ? 1 : 0
    land[i] = allWater[i] ? 0 : 1
  }
  const toWater = distance(allWater, pw, ph),
    toLand = distance(land, pw, ph)
  const toSea = new Uint8Array(pw * ph)
  for (let i = 0; i < pw * ph; i++)
    toSea[i] = Math.min(MAX_DEPTH, Math.round(allWater[i] ? toLand[i] : toWater[i]))
  return toSea
}

/**
 * content 标出镇上的东西（不含原有水面），water 标出港口和公园里原有的水（码头的木墙会从里面划掉，
 * 画好的海岸里的岛内水面会并进来），deck 标出港口的木码头，facing 是各港口朝海的方向（见 decor.ts），
 * design 是地图画好的海岸（见 designOf）。
 */
export function island(
  atlas: Atlas,
  land: {
    content: Uint8Array
    water: Uint8Array
    deck: Uint8Array
    facing: Map<string, [number, number]>
    design?: Design
  },
  pw: number,
  ph: number,
  seed: number
): Island {
  const { content, water, deck, facing, design } = land
  const shape = design?.shape ?? SHAPE
  const anchors = anchorsOf(atlas, content, facing, pw, ph)
  const fromContent = distance(content, pw, ph)
  const locked = (i: number) => content[i] || water[i] || fromContent[i] <= shape.rim
  const hull = design?.land ?? hullMask(content, pw, ph)
  const { sea, band } = initialCoast(hull, shape, locked, pw, ph, seed)
  erode(sea, band, shape.erosion, pw, ph, seed)
  // 画好的海岸里港口本来就摆在水边，不再往它朝海的一侧挖海（会从区域之间的缝里挖出一道水汊）；海塔照旧
  const pulls = design ? anchors.filter((a) => a.near !== NEAR.harbor) : anchors
  pullCoast(sea, pulls, fromContent, locked, pw, ph)
  keepOpenSea(sea, pw, ph)
  // 岛内的水在海岸定下来以后才挖：边不跟着扭，也不会被当成镇子中间的一小块海填掉
  const inland = new Uint8Array(pw * ph)
  if (design)
    for (let i = 0; i < pw * ph; i++)
      if (design.water[i] && !sea[i]) {
        inland[i] = 1
        water[i] = 1
      }
  dryHarbors(sea, water, deck, pw, ph)
  const rocks = rocksOf(sea, content, band, anchors, pw, ph, seed)
  const { piers, docks } = piersOf(sea, water, deck, rocks, anchors, pw, ph, seed)
  const quay = quayOf(sea, water, deck, piers, pw, ph)
  for (let i = 0; i < pw * ph; i++) if (!water[i]) inland[i] = 0
  const spring = new Uint8Array(pw * ph)
  if (design) for (let i = 0; i < pw * ph; i++) spring[i] = inland[i] && design.spring[i] ? 1 : 0
  const mirror = new Uint8Array(pw * ph)
  if (design) for (let i = 0; i < pw * ph; i++) mirror[i] = inland[i] && design.mirror[i] ? 1 : 0
  return {
    sea,
    inland,
    spring,
    mirror,
    piers,
    quay,
    rocks,
    docks,
    toSea: toSeaDistance(sea, water, pw, ph),
  }
}
