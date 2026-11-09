import type { Atlas } from 'town-shared/mapDocument'
import { PIXEL, toPx } from '../grid'
import { WALL_TEXEL } from '../hd2d/layout'
import { DEFAULT_EDGE_WIDTH } from '../route'

// 桥：路跨过岛内的水（画好的海岸里的河、湖、港湾，见 island.ts 的 inland）时，在跨水的那一段搭一座桥。
// 桥身取路下水、上岸两点的连线，两头各多伸几个像素搭在岸上；路段写了 bridge 就按它的样子，不写是木板桥。
// 石拱桥中间拱起、两侧石栏，桥身侧面开几个拱洞；木板桥平平地架在桩上、两侧木栏杆。
// 桥是立体场景搭的（hd2d/bridge.ts），桥下仍是水，看得见；人走在桥上按桥面高度抬起来（liftOf）。

export type BridgeStyle = 'stone' | 'wood'

export interface Bridge {
  /** 桥两头、桥面中线上的点（地图坐标）；沿桥从 a 量到 b */
  a: [number, number]
  b: [number, number]
  /** 桥面宽（地图单位，栏杆在桥面两边以内） */
  width: number
  style: BridgeStyle
  /** 从 a 量起，桥下的水从哪到哪（地图单位） */
  water: [number, number]
}

/** 两头搭在岸上多长（像素）；桥面比路宽出多少（地图单位） */
const LANDING: Record<BridgeStyle, number> = { stone: 6, wood: 3 }
const WIDER: Record<BridgeStyle, number> = { stone: 4 * PIXEL, wood: 2 * PIXEL }
/** 桥面最高处高出地面多少（世界单位）：石拱桥拱顶、木板桥桥面；木板桥两头的跳板占几个像素 */
export const CROWN: Record<BridgeStyle, number> = {
  stone: 4.6 * WALL_TEXEL,
  wood: 1.4 * WALL_TEXEL,
}
export const RAMP = 3
/** 跨水不到这么长（像素）的不搭桥：路擦过水边一两格不算过河 */
const SHORTEST = 2

/** 地图上画好的岛内水面上，各条路过水的地方 */
export function bridgesOf(atlas: Atlas, inland: Uint8Array, pw: number, ph: number): Bridge[] {
  const wet = ([x, y]: [number, number]) => {
    const px = toPx(x),
      py = toPx(y)
    return px >= 0 && py >= 0 && px < pw && py < ph && inland[py * pw + px] === 1
  }
  const out: Bridge[] = []
  for (const e of atlas.edges) {
    const style: BridgeStyle = e.bridge === 'stone' ? 'stone' : 'wood'
    // 沿折线每 3 个单位取一点
    const pts: [number, number][] = []
    for (let k = 0; k + 1 < e.polyline.length; k++) {
      const [ax, ay] = e.polyline[k],
        [bx, by] = e.polyline[k + 1]
      const n = Math.max(1, Math.ceil(Math.hypot(bx - ax, by - ay) / 3))
      for (let t = 0; t < n; t++) pts.push([ax + ((bx - ax) * t) / n, ay + ((by - ay) * t) / n])
    }
    pts.push(e.polyline[e.polyline.length - 1])
    for (let k = 0; k < pts.length;) {
      if (!wet(pts[k])) {
        k++
        continue
      }
      let j = k
      while (j < pts.length && wet(pts[j])) j++
      // 两头都在岸上、跨得够长才搭
      if (k > 0 && j < pts.length) {
        const [fx, fy] = pts[k - 1],
          [tx, ty] = pts[j]
        const span = Math.hypot(tx - fx, ty - fy)
        if (span >= SHORTEST * PIXEL) {
          const dx = (tx - fx) / span,
            dy = (ty - fy) / span
          const land = LANDING[style] * PIXEL
          out.push({
            a: [fx - dx * land, fy - dy * land],
            b: [tx + dx * land, ty + dy * land],
            width: (e.width ?? DEFAULT_EDGE_WIDTH) + WIDER[style],
            style,
            water: [land, land + span],
          })
        }
      }
      k = j
    }
  }
  return out
}

/** 桥长（地图单位） */
export const spanOf = (b: Bridge) => Math.hypot(b.b[0] - b.a[0], b.b[1] - b.a[1])

/** 桥面在沿桥 s 处（地图单位，从 a 量起）的高度：石拱桥整座拱成一道弧，木板桥两头跳板、中间平 */
export function deckHeight(b: Bridge, s: number) {
  const L = spanOf(b)
  if (s < 0 || s > L) return 0
  if (b.style === 'stone') {
    const k = (2 * s) / L - 1
    return CROWN.stone * (1 - k * k)
  }
  const ramp = RAMP * PIXEL
  const up = (d: number) => Math.min(1, d / ramp)
  return CROWN.wood * Math.min(up(s), up(L - s))
}

/** 地图上一点在哪座桥上、桥面多高：沿桥 s、横过桥 v（中线为 0），都是地图单位 */
export function onBridge(bridges: readonly Bridge[], x: number, y: number) {
  for (const b of bridges) {
    const L = spanOf(b)
    const dx = (b.b[0] - b.a[0]) / L,
      dy = (b.b[1] - b.a[1]) / L
    const s = (x - b.a[0]) * dx + (y - b.a[1]) * dy,
      v = -(x - b.a[0]) * dy + (y - b.a[1]) * dx
    if (s >= 0 && s <= L && Math.abs(v) <= b.width / 2) return { bridge: b, s, v }
  }
  return undefined
}

/** 人站在地图上一点要抬多高：在桥上是桥面的高度，不然是 0 */
export function liftOf(bridges: readonly Bridge[]) {
  return (x: number, y: number) => {
    const on = onBridge(bridges, x, y)
    return on ? deckHeight(on.bridge, on.s) : 0
  }
}
