import type { Atlas } from 'town-shared/mapDocument'
import { OUTDOOR_SPACE } from './grid'
import { hashString, rng } from './pixel/noise'
// 表现层装饰：植被散布与水面，从图集几何确定性派生（种子按区域 ID），
// 不进地图文件，新老地图与生成器产物自动生效。树会同时注册为寻路障碍（render.ts），
// 与 spatial.vegetation 在三维地图里的角色一致。

export interface DecorVeg {
  x: number
  y: number
  kind: 'tree0' | 'tree1' | 'tree2' | 'bush' | 'grass' | 'flowers'
  scale: number
  flip: boolean
}

export interface DecorPlan {
  vegetation: DecorVeg[]
  /** region.id → 水面格子（与 region.cells 同一栅格坐标系） */
  water: Map<string, [number, number][]>
  /** 港口 region.id → 朝海的方向（横竖之一的单位向量），岸线和栈桥都顺着它 */
  harbors: Map<string, [number, number]>
}

function pointToSeg(px: number, py: number, x1: number, y1: number, x2: number, y2: number) {
  const dx = x2 - x1
  const dy = y2 - y1
  const len2 = dx * dx + dy * dy
  let t = len2 ? ((px - x1) * dx + (py - y1) * dy) / len2 : 0
  t = Math.max(0, Math.min(1, t))
  return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))
}

/** 最大四连通块，避免零散小水洼 */
function largestBlob(cells: Set<string>): Set<string> {
  const seen = new Set<string>()
  let best = new Set<string>()
  for (const key of cells) {
    if (seen.has(key)) continue
    const blob = new Set<string>()
    const queue = [key]
    seen.add(key)
    while (queue.length) {
      const cur = queue.pop()!
      blob.add(cur)
      const [c, r] = cur.split(',').map(Number)
      for (const [dc, dr] of [
        [1, 0],
        [-1, 0],
        [0, 1],
        [0, -1],
      ] as const) {
        const nk = `${c + dc},${r + dr}`
        if (cells.has(nk) && !seen.has(nk)) {
          seen.add(nk)
          queue.push(nk)
        }
      }
    }
    if (blob.size > best.size) best = blob
  }
  return best
}

type Near = (x: number, y: number, dist: number) => boolean
interface Obstacles {
  nearRoad: Near
  nearPoi: Near
}
type Region = Atlas['regions'][number]
type Cell = [number, number]
const keyOf = (c: number, rr: number) => `${c},${rr}`
const cellsOf = (keys: Iterable<string>) => [...keys].map((k) => k.split(',').map(Number) as Cell)

/** 离道路、室外落脚点和道具多近：水面和植被都要避开它们 */
function obstaclesOf(atlas: Atlas): Obstacles {
  const stations = atlas.stations.filter((s) => s.space === OUTDOOR_SPACE)
  const props = atlas.props.filter((p) => p.space === OUTDOOR_SPACE)
  const roadSegs: number[] = []
  for (const e of atlas.edges) {
    const pl = e.polyline
    for (let i = 0; i + 1 < pl.length; i++)
      roadSegs.push(pl[i][0], pl[i][1], pl[i + 1][0], pl[i + 1][1])
  }
  const nearRoad = (x: number, y: number, dist: number) => {
    for (let i = 0; i < roadSegs.length; i += 4) {
      if (pointToSeg(x, y, roadSegs[i], roadSegs[i + 1], roadSegs[i + 2], roadSegs[i + 3]) < dist)
        return true
    }
    return false
  }
  const nearPoi = (x: number, y: number, dist: number) =>
    stations.some((s) => Math.hypot(s.x - x, s.y - y) < dist) ||
    props.some((p) => Math.hypot(p.x - x, p.y - y) < dist)
  return { nearRoad, nearPoi }
}

/** 港口朝哪边：从镇子中心指向港口中心，取横竖里更接近的那个方向（单位向量）。
 *  岸线、栈桥都顺着它，横平竖直 */
function harborFacing(r: Region, center: Cell): [number, number] {
  const cs = r.cell_size
  const hx = r.cells.reduce((s, [c]) => s + c + 0.5, 0) / r.cells.length,
    hy = r.cells.reduce((s, [, rr]) => s + rr + 0.5, 0) / r.cells.length
  const dx = hx * cs - center[0],
    dy = hy * cs - center[1]
  return Math.abs(dx) >= Math.abs(dy) ? [Math.sign(dx) || 1, 0] : [0, Math.sign(dy) || 1]
}

/** 港口朝海一侧为水，和陆上的木码头隔着一条笔直的岸线（垂直于 facing，按格对齐）。
 *  落脚点、道具和路附近的格子留作码头：那几行的岸线往海里伸，围住它们，码头连成一片不碎；
 *  伸出去不多时整条岸线一起往外挪，还是一条直线 */
function harborWater(r: Region, facing: [number, number], near: Obstacles) {
  const cs = r.cell_size
  const [fx, fy] = facing
  const along = ([c, rr]: Cell) => c * fx + rr * fy
  const row = ([c, rr]: Cell) => (fx ? rr : c)
  const values = r.cells.map(along)
  const lo = Math.min(...values),
    hi = Math.max(...values)
  const base = lo + Math.round((hi - lo) * 0.42)
  const keep = new Map<number, number>()
  for (const cell of r.cells) {
    const x = (cell[0] + 0.5) * cs,
      y = (cell[1] + 0.5) * cs
    if (!near.nearPoi(x, y, cs * 2.6) && !near.nearRoad(x, y, cs * 1.2)) continue
    const k = row(cell)
    keep.set(k, Math.max(keep.get(k) ?? base, along(cell) + 1))
  }
  const most = Math.max(base, ...keep.values())
  const quay = (k: number) => (most - base <= 4 ? most : (keep.get(k) ?? base))
  const cells = new Set<string>()
  for (const cell of r.cells) if (along(cell) > quay(row(cell))) cells.add(keyOf(...cell))
  const blob = largestBlob(cells)
  return blob.size ? cellsOf(blob) : undefined
}

/** 公园内部自动选址挖一个池塘，避开道路与落脚点；120 次都找不到就不挖 */
function parkPond(r: Region, random: () => number, near: Obstacles) {
  const cs = r.cell_size
  const set = new Set(r.cells.map(([c, rr]) => keyOf(c, rr)))
  const interior = (c: number, rr: number) =>
    [-1, 0, 1].every((dc) => [-1, 0, 1].every((dr) => set.has(keyOf(c + dc, rr + dr))))
  for (let attempt = 0; attempt < 120; attempt++) {
    const [cc, cr] = r.cells[Math.floor(random() * r.cells.length)]
    const rad = 3.2 + random() * 1.6
    const pond = new Set<string>()
    let ok = interior(cc, cr)
    if (ok) {
      for (const [c, rr] of r.cells) {
        if (Math.hypot(c - cc, rr - cr) > rad) continue
        if (!interior(c, rr)) {
          ok = false
          break
        }
        const cx = c * cs + cs / 2
        const cy = rr * cs + cs / 2
        if (near.nearPoi(cx, cy, 80) || near.nearRoad(cx, cy, 44)) {
          ok = false
          break
        }
        pond.add(keyOf(c, rr))
      }
    }
    if (ok && pond.size > 16) return cellsOf(pond)
  }
  return undefined
}

/** 水面：镇子四面环海；港口的水放在朝镇外、也就是朝海的那一侧，公园里挖池塘 */
function planWater(atlas: Atlas, near: Obstacles) {
  let tx = 0,
    ty = 0,
    tn = 0
  for (const r of atlas.regions)
    for (const [c, rr] of r.cells) {
      tx += (c + 0.5) * r.cell_size
      ty += (rr + 0.5) * r.cell_size
      tn++
    }
  const center: Cell = [tx / Math.max(1, tn), ty / Math.max(1, tn)]
  const water = new Map<string, Cell[]>()
  const harbors = new Map<string, [number, number]>()
  for (const r of atlas.regions) {
    if (!r.cells.length) continue
    let cells: Cell[] | undefined
    if (r.kind === 'harbor') {
      const facing = harborFacing(r, center)
      harbors.set(r.id, facing)
      cells = harborWater(r, facing, near)
    } else if (r.kind === 'park') cells = parkPond(r, rng(hashString(r.id) ^ 0x51ab3c), near)
    if (cells) water.set(r.id, cells)
  }
  return { water, harbors }
}

/** 一个公园或花园里的植被：里面撒树、灌木和草，边上是花丛（花园）或灌木（公园） */
function regionVegetation(r: Region, water: Map<string, Cell[]>, { nearRoad, nearPoi }: Obstacles) {
  const vegetation: DecorVeg[] = []
  const random = rng(hashString(r.id) ^ 0x9e3779b9)
  const cs = r.cell_size
  const set = new Set(r.cells.map(([c, rr]) => keyOf(c, rr)))
  const waterCells = new Set((water.get(r.id) ?? []).map(([c, rr]) => keyOf(c, rr)))
  const isPark = r.kind === 'park'
  const treeP = isPark ? 0.13 : 0.07
  for (const [c, rr] of r.cells) {
    if (waterCells.has(keyOf(c, rr))) continue
    const cx = c * cs + cs / 2 + (random() - 0.5) * cs * 0.7
    const cy = rr * cs + cs / 2 + (random() - 0.5) * cs * 0.7
    const roll = random()
    const inner = [-1, 0, 1].every((dc) =>
      [-1, 0, 1].every(
        (dr) => set.has(keyOf(c + dc, rr + dr)) && !waterCells.has(keyOf(c + dc, rr + dr))
      )
    )
    const plant = (kind: DecorVeg['kind'], scale: number, spread: number) =>
      vegetation.push({
        x: cx,
        y: cy,
        kind,
        scale: scale + random() * spread,
        flip: random() < 0.5,
      })
    if (inner) {
      if (roll < treeP) {
        if (nearPoi(cx, cy, 85) || nearRoad(cx, cy, 55)) continue
        plant(`tree${Math.floor(random() * 3)}` as DecorVeg['kind'], 0.85, 0.6)
      } else if (roll < treeP + 0.1) {
        if (nearPoi(cx, cy, 45)) continue
        plant('bush', 0.8, 0.5)
      } else if (roll < treeP + 0.32) plant('grass', 0.9, 0.5)
    } else {
      // 边缘：花丛（花园）/ 灌木（公园）
      const p = isPark ? 0.12 : 0.16
      if (roll < p) {
        if (nearPoi(cx, cy, 40) || nearRoad(cx, cy, 30)) continue
        plant(isPark ? 'bush' : 'flowers', 0.75, 0.45)
      } else if (roll < p + 0.2) plant('grass', 0.9, 0.4)
    }
  }
  return vegetation
}

export function planDecor(atlas: Atlas): DecorPlan {
  const near = obstaclesOf(atlas)
  const { water, harbors } = planWater(atlas, near)
  const vegetation = atlas.regions
    .filter((r) => r.kind === 'park' || r.kind === 'garden')
    .flatMap((r) => regionVegetation(r, water, near))
  vegetation.sort((a, b) => a.y - b.y)
  return { vegetation, water, harbors }
}
