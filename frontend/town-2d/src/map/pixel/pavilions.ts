import type { Atlas } from 'town-shared/mapDocument'
import { PIXEL } from '../grid'
import { WALL_TEXEL } from '../hd2d/layout'
import { DEFAULT_EDGE_WIDTH } from '../route'

// 立体的八角凉亭立在哪。地图里 kind 为 pavilion 的立牌都是；风格包要立体凉亭时（村庄），各个公园区域
// （没有 decor、没指定地标的 park）的正中也立一座，不再立凉亭的立牌；正中有路穿过时往路边让开，路不从亭子里过。
// 立体场景按这里的位置搭（hd2d/gazebo.ts）；亭子占的地方不种树、不长草（terrain.ts 的 groundOf），
// 人和道具进了亭子按台面的高度抬起来（pavilionLift）。这里只管几何。

export interface Pavilion {
  /** 亭子正中（地图坐标） */
  x: number
  y: number
  /** 敞开的一面朝哪（单位向量）；不给朝南，正对缺省镜头 */
  facing?: [number, number]
}

/** 柱子所在的半径、石台和檐口各往外多出多少（地图单位）；石台多高（世界单位） */
export const PAVILION = {
  r: 20 * PIXEL,
  plinth: 2 * PIXEL,
  eave: 4 * PIXEL,
  floor: 2.4 * WALL_TEXEL,
}
/** 占地半径：到檐口（地图单位） */
export const PAVILION_REACH = PAVILION.r + PAVILION.eave

/** parks 为 true 时公园区域的正中也立（风格包说的） */
export function pavilionsOf(atlas: Atlas, parks: boolean): Pavilion[] {
  const out: Pavilion[] = (atlas.standees ?? [])
    .filter((s) => s.kind === 'pavilion')
    .map((s) => ({ x: s.x, y: s.y, ...(s.facing ? { facing: s.facing } : {}) }))
  if (!parks) return out
  for (const r of atlas.regions) {
    const kind = r.landmark ?? (r.decor ? undefined : r.kind)
    if (kind !== 'park' || !r.cells.length) continue
    const cs = r.cell_size
    const xs = r.cells.map(([c]) => c * cs),
      ys = r.cells.map(([, rr]) => rr * cs)
    out.push(
      offRoads(atlas, {
        x: (Math.min(...xs) + Math.max(...xs) + cs) / 2,
        y: (Math.min(...ys) + Math.max(...ys) + cs) / 2,
      })
    )
  }
  return out
}

/** 路从石台上穿过时把亭子往路边推开，推几次（两条路夹着时来回让）；让不开就留在最后的位置 */
function offRoads(atlas: Atlas, p: Pavilion): Pavilion {
  const foot = PAVILION.r + PAVILION.plinth + PIXEL
  let { x, y } = p
  for (let turn = 0; turn < 4; turn++) {
    let worst: { gap: number; nx: number; ny: number } | undefined
    for (const e of atlas.edges) {
      const need = foot + (e.width ?? DEFAULT_EDGE_WIDTH) / 2
      for (let k = 0; k + 1 < e.polyline.length; k++) {
        const [ax, ay] = e.polyline[k],
          [bx, by] = e.polyline[k + 1]
        const dx = bx - ax,
          dy = by - ay
        const len2 = dx * dx + dy * dy
        const t = len2 ? Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / len2)) : 0
        const qx = ax + t * dx,
          qy = ay + t * dy
        const d = Math.hypot(x - qx, y - qy)
        if (d >= need || (worst && need - d <= worst.gap)) continue
        // 正压在路上时朝路的垂直方向让
        const len = Math.sqrt(len2) || 1
        worst =
          d > 1e-6
            ? { gap: need - d, nx: (x - qx) / d, ny: (y - qy) / d }
            : { gap: need, nx: -dy / len, ny: dx / len }
      }
    }
    if (!worst) break
    x += worst.nx * worst.gap
    y += worst.ny * worst.gap
  }
  return { x: Math.round(x), y: Math.round(y) }
}

/** 人和道具站在地图上一点要抬多高：在凉亭的石台上是台面的高度，不然是 0 */
export function pavilionLift(pavilions: readonly Pavilion[]) {
  const reach = PAVILION.r + PAVILION.plinth
  return (x: number, y: number) =>
    pavilions.some((p) => Math.hypot(x - p.x, y - p.y) < reach) ? PAVILION.floor : 0
}
