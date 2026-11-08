// 摆道具的格子（后端放置器算好的，见 protocol 的 PlaceGrid）：按位置找格、找最近的能放的格，
// 把不能放的原因说成一句话。规则都在后端，这里只按格子里记的结果查。
import type { PlaceGrid } from '../protocol'

export interface GridCell {
  index: number
  /** 格子中心（米：x 与地面上的 z） */
  at: [number, number]
  /** '.' 能放；其余见 PlaceGrid.cells */
  code: string
  /** 碰到或挡路的那件道具的编号 */
  by?: string
}

const DIGITS = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'

function cell(g: PlaceGrid, index: number): GridCell {
  const at: [number, number] = [
    g.origin[0] + (index % g.columns) * g.step,
    g.origin[1] + Math.floor(index / g.columns) * g.step,
  ]
  const k = DIGITS.indexOf(g.by[index] ?? '-')
  return { index, at, code: g.cells[index] ?? '.', by: k >= 0 ? g.props[k] : undefined }
}

/** 离这一点最近的格子；点在格子外时取边上那一格 */
export function cellNear(g: PlaceGrid, [x, z]: [number, number]): GridCell | undefined {
  if (!g.columns || !g.rows) return
  const clamp = (v: number, n: number) => Math.min(n - 1, Math.max(0, Math.round(v)))
  const col = clamp((x - g.origin[0]) / g.step, g.columns)
  const row = clamp((z - g.origin[1]) / g.step, g.rows)
  return cell(g, row * g.columns + col)
}

/** 离这一点最近的能放的格子（和放置器按 near 挑空位一样按直线距离）；一格都没有时没有 */
export function freeNear(g: PlaceGrid, [x, z]: [number, number]): GridCell | undefined {
  let best = -1,
    away = Infinity
  for (let i = 0; i < g.cells.length; i++) {
    if (g.cells[i] !== '.') continue
    const c = cell(g, i).at
    const d = Math.hypot(c[0] - x, c[1] - z)
    if (d < away) {
      away = d
      best = i
    }
  }
  return best >= 0 ? cell(g, best) : undefined
}

/** 每一格：画格子用 */
export function* cells(g: PlaceGrid): Generator<GridCell> {
  for (let i = 0; i < g.cells.length; i++) yield cell(g, i)
}

/** 指着的格子为什么放不下，说成一句话；thing 是碰到或挡路的那件东西的名字 */
export function blockedText(code: string, thing?: string) {
  switch (code) {
    case 'a':
      return '离入口太近，会堵门'
    case 'p':
      return thing ? `这里已经有${thing}` : '这里已经有东西'
    case 'r':
      return '小路上放不了'
    case 'b':
      return thing ? `从入口走过来会被${thing}挡住` : '从入口走过来会被挡住'
    case 's':
      return '从入口过来的坡太陡'
    case 'w':
      return '用的人站不到它跟前'
    default:
      return '这里放不了'
  }
}

/** 这块地还能放几件，说成半句话 */
export function roomText(g: PlaceGrid) {
  if (!g.cells.includes('.')) return '已经放满了'
  return g.room_capped ? `还能放 ${g.room} 件以上` : `还能放约 ${g.room} 件`
}
