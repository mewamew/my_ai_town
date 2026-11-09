import type { Atlas } from 'town-shared/mapDocument'
import { PIXEL } from '../grid'
import { WALL_TEXEL } from '../hd2d/layout'

// 看台（弧形阶台）：几级石阶围成大半圈，朝 facing 一面敞开，正中一座圆形小舞台，舞台四周一圈石板地。
// 地图上的 court 区域（取格子外框的中心和较短一边的一半当外半径），和按坐标立的 court 立牌
// （size 是外半径）都画成它。立体场景搭成真的台阶（hd2d/stand.ts），平面图画在地面上；
// 人和道具站上去按那一级的高度抬起来（standLift）。这里只管几何，平面图和立体场景共用。

export interface Stand {
  /** 舞台中心（地图坐标） */
  x: number
  y: number
  /** 外半径：最高一级的外沿（地图单位） */
  r: number
  /** 敞开的一面朝哪（地图坐标里的单位向量）；台阶围在背后 */
  facing: [number, number]
  /** 舞台半径、第一级台阶的内沿、几级、每级多深（地图单位） */
  stage: number
  inner: number
  tiers: number
  depth: number
}

/** 台阶围住的半角（弧度）：比半圈多出两边各 10° */
export const STAND_SPAN = (100 * Math.PI) / 180
/** 每级台阶高、舞台高、石板地高出地面多少（世界单位） */
export const STEP_RISE = 2.5 * WALL_TEXEL
export const STAGE_RISE = 1.2 * WALL_TEXEL
export const FLOOR_RISE = 0.4
/** 每级台阶至少多深（地图单位）：坐得下一个人；最多几级 */
const MIN_DEPTH = 48
const MAX_TIERS = 5

/** 按外半径和朝向定出舞台、台阶的尺寸 */
export function standShape(x: number, y: number, r: number, facing?: [number, number]): Stand {
  const len = facing ? Math.hypot(facing[0], facing[1]) : 0
  const f: [number, number] = len > 0 ? [facing![0] / len, facing![1] / len] : [0, 1]
  const stage = Math.min(96, Math.max(36, Math.round(r * 0.28)))
  const inner = stage + 2 * PIXEL
  const tiers = Math.min(MAX_TIERS, Math.max(1, Math.floor((r - inner) / MIN_DEPTH)))
  return { x, y, r, facing: f, stage, inner, tiers, depth: (r - inner) / tiers }
}

/** 地图上所有的看台：court 区域（没有 decor，或指定了 court 地标的区域）和 court 立牌 */
export function standsOf(atlas: Atlas): Stand[] {
  const out: Stand[] = []
  for (const r of atlas.regions) {
    const kind = r.landmark ?? (r.decor ? undefined : r.kind)
    if (kind !== 'court' || !r.cells.length) continue
    const cs = r.cell_size
    const xs = r.cells.map(([c]) => c * cs),
      ys = r.cells.map(([, rr]) => rr * cs)
    const x0 = Math.min(...xs),
      x1 = Math.max(...xs) + cs,
      y0 = Math.min(...ys),
      y1 = Math.max(...ys) + cs
    const radius = Math.min(x1 - x0, y1 - y0) / 2
    if (radius < 4 * PIXEL) continue
    out.push(standShape((x0 + x1) / 2, (y0 + y1) / 2, radius, r.facing))
  }
  for (const s of atlas.standees ?? [])
    if (s.kind === 'court') out.push(standShape(s.x, s.y, s.size ?? 160, s.facing))
  return out
}

/** 一点相对看台的位置：离舞台中心多远（d），偏离背后正中多少角度（a，-π～π，朝 facing 转为正） */
export function standPolar(s: Stand, x: number, y: number) {
  const dx = x - s.x,
    dy = y - s.y
  const [bx, by] = [-s.facing[0], -s.facing[1]]
  // 背后方向转到 (dx, dy) 的角度
  const a = Math.atan2(bx * dy - by * dx, bx * dx + by * dy)
  return { d: Math.hypot(dx, dy), a }
}

/** 看台上一点的高度（世界单位）：舞台、石板地、第几级台阶；不在看台上是 null */
export function standHeight(s: Stand, x: number, y: number): number | null {
  const { d, a } = standPolar(s, x, y)
  if (d > s.r) return null
  if (d <= s.stage) return STAGE_RISE
  if (d < s.inner || Math.abs(a) > STAND_SPAN) return d < s.inner ? FLOOR_RISE : null
  const k = Math.min(s.tiers - 1, Math.floor((d - s.inner) / s.depth))
  return (k + 1) * STEP_RISE
}

/** 人和道具站在地图上一点要抬多高：在看台的台阶、舞台上按那里的高度，不然是 0 */
export function standLift(stands: readonly Stand[]) {
  return (x: number, y: number) => {
    for (const s of stands) {
      const h = standHeight(s, x, y)
      if (h !== null) return h
    }
    return 0
  }
}

/** 地图上一点离看台多近（地图单位；在看台里为负）：树、灯、草丛按它让开 */
export function standGap(stands: readonly Stand[], x: number, y: number) {
  let best = Infinity
  for (const s of stands) best = Math.min(best, Math.hypot(x - s.x, y - s.y) - s.r)
  return best
}
