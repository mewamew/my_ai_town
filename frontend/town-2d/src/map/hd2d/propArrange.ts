// 屋里家具的布置：只算位置，不碰画面（测试见 frontend/town-shared/tests/prop-arrange.test.mjs）。
// 地图里一件道具只有一个落点，没有朝向，也不知道家具有多大。这里按房间把它们摆好：
// - 靠墙的家具（柜子、床）离北、西、东哪面墙近就背靠哪面，贴上去；南墙对着镜头，不靠。
// - 谁也不伸出墙外、不压隔墙、互相不叠：靠同一面墙的沿墙挪开拼成一排，别的往空处让。
// - 陈设（只给画面看的桌椅、绿植、地毯）摆在没人走的地方：让开道具、人站的点，以及这些点两两之间的
//   直线（村民在屋里就是在落脚点之间直线走的）。
// 坐标都是地图坐标：x 朝东、y 朝南。这个文件不引入别的模块，测试直接载入源码。

export interface Box {
  x0: number
  y0: number
  x1: number
  y1: number
}

export interface Room extends Box {
  /** 隔墙的几段：horizontal 是东西向的墙（在 y = at，从 from 到 to），否则是南北向的（在 x = at） */
  walls: { horizontal: boolean; at: number; from: number; to: number }[]
}

export interface Piece {
  id: string
  /** 道具落点 */
  x: number
  y: number
  /** 朝南摆时的占地：中心相对落点的偏移、半宽、半深 */
  foot: { cx: number; cz: number; hw: number; hd: number }
  /** 靠墙摆的家具 */
  wall: boolean
}

/** 转几个直角：0 朝南、1 朝东、2 朝北、3 朝西 */
export type Turn = 0 | 1 | 2 | 3

export interface Spot {
  /** 模型的原点摆在哪 */
  x: number
  y: number
  turn: Turn
  /** 摆好以后占的地 */
  box: Box
}

/** 隔墙厚度的一半 */
const THICK = 6
/** 靠墙的家具背后离墙不超过这么远就贴上去 */
const SNAP = 72
/** 北墙比东西墙多让这么远 */
const NORTH_BIAS = 48

/** 模型里的一点 (lx, lz) 转 turn 个直角以后的偏移 */
export function turned(lx: number, lz: number, turn: Turn): [number, number] {
  return turn === 0 ? [lx, lz] : turn === 1 ? [lz, -lx] : turn === 2 ? [-lx, -lz] : [-lz, lx]
}

interface Placing {
  piece: Piece
  cx: number
  cy: number
  hx: number
  hy: number
  turn: Turn
  /** 背靠哪面墙：贴北墙的只沿东西挪，贴东西墙的只沿南北挪 */
  anchor: 'n' | 'w' | 'e' | null
}

const overlap = (a: Box, b: Box) => a.x0 < b.x1 && b.x0 < a.x1 && a.y0 < b.y1 && b.y0 < a.y1
const grow = (b: Box, by: number): Box => ({
  x0: b.x0 - by,
  y0: b.y0 - by,
  x1: b.x1 + by,
  y1: b.y1 + by,
})
const boxOf = (s: Placing): Box => ({
  x0: s.cx - s.hx,
  y0: s.cy - s.hy,
  x1: s.cx + s.hx,
  y1: s.cy + s.hy,
})
const wallBox = (w: Room['walls'][number]): Box =>
  w.horizontal
    ? { x0: w.from, x1: w.to, y0: w.at - THICK, y1: w.at + THICK }
    : { y0: w.from, y1: w.to, x0: w.at - THICK, x1: w.at + THICK }

/** 一间屋里的道具各摆在哪；room 不给（室外）就原地朝南 */
export function arrange(room: Room | undefined, pieces: Piece[]): Map<string, Spot> {
  const placing = pieces.map((piece): Placing => {
    const { cx, cz, hw, hd } = piece.foot
    const s: Placing = {
      piece,
      cx: piece.x + cx,
      cy: piece.y + cz,
      hx: hw,
      hy: hd,
      turn: 0,
      anchor: null,
    }
    if (!room || !piece.wall) return s
    // 背靠各面墙时，背后还空着多远。北墙优先：靠北墙正面对着镜头，靠东西墙只看得见侧面，
    // 所以北墙哪怕远出 NORTH_BIAS 也选它
    const north = piece.y + cz - hd - room.y0
    const west = piece.x + cz - hd - room.x0
    const east = room.x1 - (piece.x - cz + hd)
    const nearest = Math.min(north - NORTH_BIAS, west, east)
    if (nearest > SNAP) return s
    if (nearest === north - NORTH_BIAS) {
      s.anchor = 'n'
      s.cy = room.y0 + hd
    } else {
      s.anchor = nearest === west ? 'w' : 'e'
      s.turn = s.anchor === 'w' ? 1 : 3
      s.cy = piece.y + turned(cx, cz, s.turn)[1]
      s.hx = hd
      s.hy = hw
      s.cx = s.anchor === 'w' ? room.x0 + hd : room.x1 - hd
    }
    return s
  })
  if (room) {
    const clamp = (s: Placing) => {
      s.cx =
        room.x1 - room.x0 < 2 * s.hx
          ? (room.x0 + room.x1) / 2
          : Math.min(room.x1 - s.hx, Math.max(room.x0 + s.hx, s.cx))
      s.cy =
        room.y1 - room.y0 < 2 * s.hy
          ? (room.y0 + room.y1) / 2
          : Math.min(room.y1 - s.hy, Math.max(room.y0 + s.hy, s.cy))
    }
    const alongX = (s: Placing) => s.anchor !== 'w' && s.anchor !== 'e'
    const alongY = (s: Placing) => s.anchor !== 'n'
    for (const s of placing) clamp(s)
    for (let pass = 0; pass < 24; pass++) {
      let moved = false
      for (let i = 0; i < placing.length; i++)
        for (let j = i + 1; j < placing.length; j++) {
          const a = placing[i],
            b = placing[j]
          const ox = a.hx + b.hx - Math.abs(a.cx - b.cx),
            oy = a.hy + b.hy - Math.abs(a.cy - b.cy)
          if (ox <= 0.01 || oy <= 0.01) continue
          let x: boolean
          if (a.anchor && a.anchor === b.anchor) x = a.anchor === 'n'
          else {
            const xOk = alongX(a) || alongX(b),
              yOk = alongY(a) || alongY(b)
            if (!xOk && !yOk) continue
            x = !yOk || (xOk && ox <= oy)
          }
          const ma = x ? alongX(a) : alongY(a),
            mb = x ? alongX(b) : alongY(b)
          if (!ma && !mb) continue
          const share = ma && mb ? 0.5 : ma ? 1 : 0
          const over = x ? ox : oy
          const dir = (x ? Math.sign(a.cx - b.cx) : Math.sign(a.cy - b.cy)) || (i < j ? -1 : 1)
          if (x) {
            a.cx += dir * over * share
            b.cx -= dir * over * (1 - share)
          } else {
            a.cy += dir * over * share
            b.cy -= dir * over * (1 - share)
          }
          clamp(a)
          clamp(b)
          moved = true
        }
      // 压着隔墙的往落点所在的那一边让
      for (const s of placing)
        for (const w of room.walls) {
          if (!overlap(boxOf(s), wallBox(w))) continue
          if (w.horizontal) {
            if (!alongY(s)) continue
            s.cy =
              (s.piece.y === w.at ? s.cy : s.piece.y) < w.at
                ? w.at - THICK - s.hy
                : w.at + THICK + s.hy
          } else {
            if (!alongX(s)) continue
            s.cx =
              (s.piece.x === w.at ? s.cx : s.piece.x) < w.at
                ? w.at - THICK - s.hx
                : w.at + THICK + s.hx
          }
          clamp(s)
          moved = true
        }
      if (!moved) break
    }
  }
  return new Map(
    placing.map((s) => {
      const [ox, oy] = turned(s.piece.foot.cx, s.piece.foot.cz, s.turn)
      return [s.piece.id, { x: s.cx - ox, y: s.cy - oy, turn: s.turn, box: boxOf(s) }]
    })
  )
}

/** 线段 p–q 有没有穿过这块地 */
function crosses(p: [number, number], q: [number, number], b: Box) {
  let t0 = 0,
    t1 = 1
  for (const [from, delta, lo, hi] of [
    [p[0], q[0] - p[0], b.x0, b.x1],
    [p[1], q[1] - p[1], b.y0, b.y1],
  ]) {
    if (Math.abs(delta) < 1e-9) {
      if (from < lo || from > hi) return false
      continue
    }
    const a = (lo - from) / delta,
      c = (hi - from) / delta
    t0 = Math.max(t0, Math.min(a, c))
    t1 = Math.min(t1, Math.max(a, c))
    if (t0 > t1) return false
  }
  return true
}

export type DecorKind = 'table-set' | 'plant' | 'rug'
export interface Decor {
  kind: DecorKind
  x: number
  y: number
}

/** 各种屋子摆什么陈设：几套桌椅、几盆绿植、铺不铺地毯。没写的屋子不摆 */
const PLANS: Record<string, { tables: number; plants: number; rug: boolean }> = {
  cafe: { tables: 3, plants: 2, rug: true },
}
/** 陈设的半宽、半深：一套桌椅是一张小圆桌、南北各一把椅子 */
const HALF: Record<DecorKind, [number, number]> = {
  'table-set': [26, 62],
  plant: [16, 16],
  rug: [60, 42],
}
/** 人站着要占的地方（村民的头宽 76） */
const STAND = 40

/**
 * 一间屋子的陈设摆在哪。taken 是已经摆好的道具占的地，stops 是人会站的点（落脚点、屋门里侧），
 * lounge 是沙发椅的位置（地毯铺在它脚下）。摆不下就少摆，都摆不下返回空。
 */
export function furnish(
  room: Room,
  kind: string,
  taken: Box[],
  stops: [number, number][],
  lounge: Box[] = []
): Decor[] {
  const plan = PLANS[kind]
  if (!plan) return []
  const used = [...taken]
  const walls = room.walls.map(wallBox)
  const lanes: [[number, number], [number, number]][] = []
  for (let i = 0; i < stops.length; i++)
    for (let j = i + 1; j < stops.length; j++) lanes.push([stops[i], stops[j]])
  const free = (b: Box, gap: number, lane: number) =>
    b.x0 >= room.x0 &&
    b.y0 >= room.y0 &&
    b.x1 <= room.x1 &&
    b.y1 <= room.y1 &&
    !used.some((t) => overlap(grow(t, gap), b)) &&
    !walls.some((w) => overlap(grow(w, 4), b)) &&
    !stops.some(([x, y]) => overlap(grow(b, STAND), { x0: x, y0: y, x1: x, y1: y })) &&
    !lanes.some(([p, q]) => crosses(p, q, grow(b, lane)))
  const at = (kind: DecorKind, x: number, y: number): Box => {
    const [hx, hy] = HALF[kind]
    return { x0: x - hx, y0: y - hy, x1: x + hx, y1: y + hy }
  }
  const out: Decor[] = []
  // 地毯铺在沙发椅脚下，压着隔墙就换一把
  if (plan.rug)
    for (const seat of lounge) {
      const [hx, hy] = HALF.rug
      const x = Math.min(room.x1 - hx - 2, Math.max(room.x0 + hx + 2, (seat.x0 + seat.x1) / 2))
      const y = Math.min(room.y1 - hy - 2, Math.max(room.y0 + hy + 2, (seat.y0 + seat.y1) / 2 + 8))
      const b = at('rug', x, y)
      if (b.x0 < room.x0 || b.y0 < room.y0 || walls.some((w) => overlap(grow(w, 2), b))) continue
      out.push({ kind: 'rug', x, y })
      break
    }
  // 桌椅从北墙根摆起（椅背靠墙），由东往西找空位
  const [tx, ty] = HALF['table-set']
  for (let y = room.y0 + ty; y <= room.y1 - ty && plan.tables > 0; y += 6)
    for (let x = room.x1 - tx; x >= room.x0 + tx; x -= 6) {
      const b = at('table-set', x, y)
      if (!free(b, 12, 12)) continue
      out.push({ kind: 'table-set', x, y })
      used.push(b)
      if (out.filter((d) => d.kind === 'table-set').length >= plan.tables) {
        y = Infinity
        break
      }
    }
  // 绿植放墙角
  const [px, py] = HALF.plant
  const corners: [number, number][] = [
    [room.x1 - px - 2, room.y0 + py + 2],
    [room.x0 + px + 2, room.y0 + py + 2],
    [room.x1 - px - 2, room.y1 - py - 2],
    [room.x0 + px + 2, room.y1 - py - 2],
  ]
  let plants = 0
  for (const [x, y] of corners) {
    if (plants >= plan.plants) break
    const b = at('plant', x, y)
    // 正北不远有家具时不摆：绿植高，从南边看会把它挡住
    const hides = used.some((t) => t.x0 < b.x1 && b.x0 < t.x1 && t.y1 <= b.y0 && b.y0 - t.y1 < 60)
    if (hides || !free(b, 6, 2)) continue
    out.push({ kind: 'plant', x, y })
    used.push(b)
    plants++
  }
  return out
}
