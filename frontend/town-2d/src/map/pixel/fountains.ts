import type { Atlas } from 'town-shared/mapDocument'
import { PIXEL } from '../grid'
import { WALL_TEXEL } from '../hd2d/layout'
import { DEFAULT_EDGE_WIDTH } from '../route'

// 立体的喷泉立在哪、多大（搭法见 hd2d/fountain.ts）。喷泉区域（区域指定了 fountain 地标的也算）的外框正中立一座，
// 地图按坐标立的 fountain 立牌也换成一座。地图上的到达点和路是先有的，喷泉照着它们定大小：台阶外沿离最近的
// 路点、路边留出半个人宽，放不下就整座按比例缩小（最多缩到 MIN_SCALE）。默认地图的喷泉到达点离中心只有 94，
// 就是这样缩到八成左右的。人站上台阶按台阶高抬起来（fountainLift），喷泉边的座位坐到池沿上（rimSpot）。
// 这里只管几何。

const P = PIXEL
const T = WALL_TEXEL

/** 满尺寸时各圈的半径（八角形的角到中心，地图单位）和池子的高度（世界单位）。
 *  池子的高度不跟着缩放：池沿和长椅的坐面一样高，人坐上去垫这么高 */
export const FOUNTAIN = {
  step: 18.5 * P,
  out: 17 * P,
  in: 14.5 * P,
  stepH: 0.6 * T,
  rim: 2.6 * T,
  water: 1.8 * T,
}
/** 八角形的边心距和角半径之比：一条边正对南面，离中心最近 */
export const APOTHEM = Math.cos(Math.PI / 8)
/** 台阶外沿离路点、路边至少留多远（地图单位） */
const MARGIN = 10
const MIN_SCALE = 0.7

export interface Fountain {
  /** 喷泉正中（地图坐标） */
  x: number
  y: number
  /** 整座的缩放，1 是满尺寸 */
  scale: number
}

export function fountainsOf(atlas: Atlas): Fountain[] {
  const spots: [number, number][] = (atlas.standees ?? [])
    .filter((s) => s.kind === 'fountain')
    .map((s) => [s.x, s.y])
  for (const r of atlas.regions) {
    const kind = r.landmark ?? (r.decor ? undefined : r.kind)
    if (kind !== 'fountain' || !r.cells.length) continue
    const cs = r.cell_size
    const xs = r.cells.map(([c]) => c * cs),
      ys = r.cells.map(([, rr]) => rr * cs)
    spots.push([
      (Math.min(...xs) + Math.max(...xs) + cs) / 2,
      (Math.min(...ys) + Math.max(...ys) + cs) / 2,
    ])
  }
  return spots.map(([x, y]) => ({ x, y, scale: fit(atlas, x, y) }))
}

/** 按离得最近的路点、路定缩放。连到喷泉跟前那几个路点（到达点）的小路只算路线本身，别的路连路面一起让开 */
function fit(atlas: Atlas, x: number, y: number) {
  const reach = FOUNTAIN.step * APOTHEM
  let room = Infinity
  const own = new Set<string>()
  for (const n of atlas.nodes) {
    const d = Math.hypot(n.x - x, n.y - y)
    if (d < reach + MARGIN) own.add(n.id)
    room = Math.min(room, d)
  }
  for (const e of atlas.edges) {
    const d = toPolyline(e.polyline, x, y)
    const mine = own.has(e.from_node) || own.has(e.to_node)
    room = Math.min(room, mine ? d : d - (e.width ?? DEFAULT_EDGE_WIDTH) / 2)
  }
  return Math.max(MIN_SCALE, Math.min(1, (room - MARGIN) / reach))
}

function toPolyline(line: [number, number][], x: number, y: number) {
  let best = Infinity
  for (let k = 0; k + 1 < line.length; k++) {
    const [ax, ay] = line[k],
      [bx, by] = line[k + 1]
    const dx = bx - ax,
      dy = by - ay
    const len2 = dx * dx + dy * dy
    const t = len2 ? Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / len2)) : 0
    best = Math.min(best, Math.hypot(x - ax - t * dx, y - ay - t * dy))
  }
  return line.length === 1 ? Math.hypot(x - line[0][0], y - line[0][1]) : best
}

/** 站上台阶的人按台阶高抬起来；池子里面（坐在池沿上的人）交给座位自己垫 */
export function fountainLift(fountains: readonly Fountain[]) {
  return (x: number, y: number) => {
    for (const f of fountains) {
      const d = Math.hypot(x - f.x, y - f.y)
      if (d < FOUNTAIN.out * APOTHEM * f.scale) return 0
      if (d < FOUNTAIN.step * f.scale) return FOUNTAIN.stepH
    }
    return 0
  }
}

/** 喷泉边的座位：(x, y) 离哪座喷泉的台阶够近，就换成朝着它那段池沿上的一点（地图坐标），
 *  离池壁外缘一个像素，八角形哪个方向都落在池沿上 */
export function rimSpot(fountains: readonly Fountain[], x: number, y: number) {
  const f = fountains.find((f) => Math.hypot(x - f.x, y - f.y) < FOUNTAIN.step * f.scale + 40)
  if (!f) return undefined
  const d = Math.hypot(x - f.x, y - f.y) || 1
  const r = (FOUNTAIN.out * APOTHEM - P) * f.scale
  return [f.x + ((x - f.x) / d) * r, f.y + ((y - f.y) / d) * r] as [number, number]
}
