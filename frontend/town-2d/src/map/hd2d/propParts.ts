import { Kit, P, T, type Paint } from './propKit'

// 立体道具的通用零件和配色：柜体、桌椅、台灯、花桶、像素画片。各件道具的搭法（propBuilds.ts、
// propBuildsPublic.ts）拿它们拼。

/** 搭一件：往 Kit 里放料；seed 按道具实例编号来，同一件每次搭出来一样；amount 是数量（一摞书有几本） */
export type Build = (k: Kit, seed: number, amount?: number) => void

export const WOOD = {
  dark: '#6b4530',
  mid: '#96673f',
  light: '#c4925c',
  pale: '#dbb07a',
  line: '#4c2f22',
}
export const CREAM = '#f1e6cd'
export const WHITE = '#f6f1e7'
export const IRON = '#45444e'
export const BRASS = '#e0ac48'
export const GREEN = { dark: '#2c5546', mid: '#3f7a61', light: '#5a9a7c' }
export const WARM = '#ffd58a'
export const LAMP = '#ffbf73'

/** 柜体：一排柜门（顶上一道横框、门芯上一颗拉手、底下踢脚），上面压一块探出来的台面。返回台面的高度 */
export function cabinet(
  k: Kit,
  w: number,
  d: number,
  c: { frame: string; core: string; slab: string; edge: string },
  doors: number
) {
  k.box(-w, w, -d, d, 0, 4 * T, {
    all: c.core,
    south: (u, v, nu, nv) => {
      if (v === nv - 1) return WOOD.line
      const span = Math.round(nu / doors)
      const i = u % span
      if (v === 0 || i === 0 || i === span - 1) return c.frame
      if (v === 1 && i === span - 2) return BRASS
      return c.core
    },
    top: false,
  })
  k.box(-w - 3, w + 3, -d - 1, d + 3, 4 * T, 4.5 * T, {
    all: c.edge,
    top: (u, v, nu, nv) => (v === nv - 1 ? c.edge : c.slab),
  })
  return 4.5 * T
}
export const WALNUT = { frame: WOOD.dark, core: WOOD.mid, slab: WOOD.pale, edge: WOOD.light }

/** 台灯：黄铜底座和灯杆，灯罩入夜亮，照亮脚下一圈 */
export function tableLamp(k: Kit, x: number, z: number, y: number, reach: number) {
  k.prism(x, z, 4.2, y, y + 0.3 * T, BRASS, BRASS)
  k.box(x - 1.5, x + 1.5, z - 1.5, z + 1.5, y + 0.3 * T, y + 1.4 * T, { all: BRASS })
  k.shade(x, z, 9.5, y + 1.4 * T, y + 3 * T, WARM, 6)
  k.lamp([x, y + 2.2 * T, z], LAMP, reach, 72)
}

/** 小圆桌：铁脚、圆台面。返回台面的高度 */
export function roundTable(k: Kit, cx: number, cz: number, r: number) {
  k.prism(cx, cz, r * 0.55, 0, 0.4 * T, IRON, '#55545f')
  k.prism(cx, cz, 4.5, 0.4 * T, 3.4 * T, IRON)
  k.prism(cx, cz, r, 3.4 * T, 3.8 * T, '#d9ccb0', CREAM)
  return 3.8 * T
}

/** 木椅：四条腿、座板和红坐垫、横档靠背；back 是靠背在北（-1，人朝南坐）还是在南（1，背对镜头） */
export function woodChair(k: Kit, cx: number, cz: number, back: -1 | 1) {
  for (const x of [-15, 9])
    for (const z of [-15, 9])
      k.box(cx + x, cx + x + 6, cz + z, cz + z + 6, 0, 2.4 * T, { all: WOOD.dark, top: false })
  k.box(cx - 15, cx + 15, cz - 15, cz + 15, 2.4 * T, 3 * T, { all: WOOD.light })
  k.box(cx - 12, cx + 12, cz - 12, cz + 12, 3 * T, 3.4 * T, { all: '#bd554c', top: '#d6776a' })
  const z0 = back < 0 ? cz - 15 : cz + 9
  const rails = (u: number, v: number, nu: number) =>
    u === 0 || u === nu - 1 ? WOOD.light : v === 1 ? WOOD.mid : WOOD.pale
  k.box(cx - 15, cx + 15, z0, z0 + 6, 3 * T, 6 * T, { all: WOOD.mid, south: rails, north: rails })
}

/** 桌上的东西：一杯咖啡、一碟蛋糕、一枝花 */
export function tableware(k: Kit, cx: number, cz: number, y: number) {
  k.prism(cx - 12, cz - 6, 6.5, y, y + 0.12 * T, WHITE, WHITE)
  k.box(cx - 15, cx - 9, cz - 9, cz - 3, y + 0.12 * T, y + 0.9 * T, { all: WHITE, top: '#6f4528' })
  k.prism(cx + 8, cz - 10, 6.5, y, y + 0.12 * T, WHITE, WHITE)
  k.box(cx + 5, cx + 11, cz - 13, cz - 7, y + 0.12 * T, y + 0.75 * T, {
    all: '#f4cb52',
    top: '#f8efdb',
  })
  k.box(cx + 3, cx + 9, cz + 6, cz + 12, y, y + 0.9 * T, { all: '#6fa9c7' })
  k.box(cx + 3, cx + 9, cz + 6, cz + 12, y + 0.9 * T, y + 1.6 * T, {
    all: '#e8687a',
    top: '#f6a3b0',
  })
}

/** 一片像素画（吉他这种靠轮廓认的东西）：rows 从上到下，一个字一格，'.' 空着；格子是正方的，正反两面都画。
 *  (x, z) 是底边中点，y 是底边的高度 */
export function cutout(
  k: Kit,
  x: number,
  z: number,
  y: number,
  rows: string[],
  palette: Record<string, string>
) {
  const nu = rows[0].length,
    nv = rows.length
  const w = nu * P,
    h = nv * P
  const paint = (flip: boolean) => (u: number, v: number) => {
    const ch = rows[v][flip ? nu - 1 - u : u]
    return ch === '.' ? null : palette[ch]
  }
  k.panel(k.side, [x - w / 2, y + h, z + 1], [w, 0, 0], [0, -h, 0], [0, 0, 1], nu, nv, paint(false))
  k.panel(
    k.side,
    [x + w / 2, y + h, z - 1],
    [-w, 0, 0],
    [0, -h, 0],
    [0, 0, -1],
    nu,
    nv,
    paint(true),
    -0.2
  )
}

export const LEAF = ['#4f8a4c', '#6fa85e']
/** 一只铁皮桶插满花：桶口一圈叶子，上面一丛花，花色给两三种 */
export function flowerBucket(k: Kit, x: number, z: number, colors: string[]) {
  k.prism(x, z, 7.5, 0, 1.8 * T, (side, v) => (v ? '#8c959f' : '#a7b0ba'), '#4f8a4c', 9)
  const bloom = (u: number, v: number) =>
    (u + v) % 3 === 2 ? LEAF[(u + v) % 2] : colors[(u * 2 + v) % colors.length]
  k.box(x - 9, x + 9, z - 9, z + 9, 1.8 * T, 3 * T, {
    all: LEAF[0],
    south: (u, v) => (v === 0 ? colors[u % colors.length] : LEAF[u % 2]),
    east: (u, v) => (v === 0 ? colors[u % colors.length] : LEAF[u % 2]),
    west: (u, v) => (v === 0 ? colors[u % colors.length] : LEAF[u % 2]),
    top: bloom,
  })
}

/** 桌子：四条腿、一块探出一点的桌面；返回桌面的高度 */
export function table(
  k: Kit,
  x0: number,
  x1: number,
  z0: number,
  z1: number,
  h = 3.3 * T,
  top = WOOD.pale
) {
  for (const x of [x0, x1 - 6])
    for (const z of [z0, z1 - 6])
      k.box(x, x + 6, z, z + 6, 0, h - 0.5 * T, { all: WOOD.dark, top: false })
  k.box(x0 - 3, x1 + 3, z0 - 2, z1 + 2, h - 0.5 * T, h, {
    all: WOOD.light,
    top: (u) => (u % 3 === 2 ? WOOD.light : top),
  })
  return h
}

/** 架子上一层摆什么：第 u 格的颜色，null 是空着（露出背板） */
export type Tier = (u: number) => string | null

/**
 * 架子：两块侧板夹几层搁板，东西画在正面。tiers 从上到下，每层高两个墙面像素（一行东西、一行搁板）。
 * 中心在 (cx, 0)，半宽 w、半深 d，从 y0 起。返回架顶的高度
 */
export function shelf(
  k: Kit,
  cx: number,
  w: number,
  d: number,
  y0: number,
  tiers: Tier[],
  c = { frame: WOOD.dark, board: WOOD.mid, back: WOOD.line }
) {
  const top = y0 + tiers.length * 2 * T
  k.box(cx - w, cx + w, -d, d, y0, top, {
    all: c.frame,
    south: (u, v, nu) =>
      u === 0 || u === nu - 1 ? c.frame : v % 2 ? c.board : (tiers[v >> 1](u) ?? c.back),
    top: false,
  })
  k.box(cx - w - 2, cx + w + 2, -d - 1, d + 2, top, top + 0.4 * T, {
    all: c.board,
    top: WOOD.light,
  })
  return top + 0.4 * T
}

/** 木条箱：四面木条，顶上另给画法（敞口看得见里面的货，封着的画箱盖） */
export function crate(
  k: Kit,
  x: number,
  z: number,
  w: number,
  d: number,
  y: number,
  h: number,
  top: Paint = (u) => (u % 3 === 2 ? WOOD.mid : WOOD.light)
) {
  const slats = (u: number, v: number) => (v % 2 ? WOOD.dark : WOOD.mid)
  k.box(x, x + w, z, z + d, y, y + h, {
    all: WOOD.mid,
    south: slats,
    east: slats,
    west: slats,
    top,
  })
}
