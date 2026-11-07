import type { ResidentEntry } from 'town-shared/gameMap'

type Point = [number, number]

/** 地点能站人的范围（米；y 是地面上的 z），同 Spatial.floors 的 bounds；props 是立着的道具（米） */
export type Room = { rect: { x: number; y: number; w: number; h: number }; props: Point[] }

/** 自由位置离站点这么近（米），就算站在同一个点上，一起分开画 */
const SAME_SPOT = 0.35
/** 分开画时离墙至少这么远（米），身子不挨着墙 */
const WALL_MARGIN = 0.45
/** 离道具中心至少这么远（米），不站进道具里 */
const PROP_CLEAR = 0.9
/** 道具在人前面（画面缺省朝北看，z 大的在前）这么近、横着又对得上时，人会被它挡住（米） */
const BEHIND = { depth: 2, half: 0.9 }
/** 排开的人彼此至少隔这么远（米）：小人约一米宽 */
const PERSON_GAP = 1.1
/** 排进屋里多深（米）、横着每人隔多远（米） */
const ROW_DEPTH = 1.6
const ROW_GAP = 1.3
/** 前后站的两个人，前面的要低下去这么多（米）才不挡住后面的脸 */
const DEPTH_GAP = 1.5
/** 找空位的网格（米）和范围 */
const GRID = 0.25
const SEARCH = 3

/**
 * 同一点上几个人在画面上分开（米），只影响人物和气泡落点，不改世界位置。
 * 站在同一站点的人一组；自由位置落在站点上的人（比如跟着别人进门、停在门口的）也算进去。
 * 有地面范围时往屋里排成一横排，只排在这块地面上、避开道具：房间的到达点就在门上，原先左右
 * 各挪 1.3 米，正好挪进墙里，画面上只剩名字（回声湾老屋）。没有地面范围时围成一圈。
 * at 给这个人真正站的地方（米），room 给地点能站人的范围和里面的道具。
 */
export function residentOffsets(
  entries: ResidentEntry[],
  at: (entry: ResidentEntry) => Point | undefined,
  room: (locale: string) => Room | undefined
): Map<string, Point> {
  const groups = new Map<string, { locale: string; spot: Point; ids: string[] }>()
  for (const entry of entries) {
    const { locale, member } = entry
    const spot = member.at.kind === 'station' ? at(entry) : undefined
    if (member.at.kind !== 'station' || !spot) continue
    const key = `${locale}/${member.at.station}`
    const group = groups.get(key) ?? { locale, spot, ids: [] }
    group.ids.push(member.id)
    groups.set(key, group)
  }
  for (const entry of entries) {
    const { locale, member } = entry
    if (member.at.kind !== 'free' || member.kind === 'avatar') continue
    const spot = at(entry)
    const group =
      spot &&
      [...groups.values()].find((g) => g.locale === locale && distance(g.spot, spot) <= SAME_SPOT)
    group?.ids.push(member.id)
  }
  const offsets = new Map<string, Point>()
  for (const { locale, spot, ids } of groups.values()) {
    if (ids.length < 2) continue
    ids.sort()
    const points = rowInside(spot, ids.length, room(locale)) ?? ring(spot, ids.length)
    ids.forEach((id, i) => offsets.set(id, [points[i][0] - spot[0], points[i][1] - spot[1]]))
  }
  return offsets
}

/** 在这块地面上排成横排（画面缺省朝北看，横着排谁也不挡谁）：门在南北墙上时贴着墙往里一点排开，
 *  在东西墙上时从门口往屋里排；每人挑离横排上那一点最近、在地面上、离道具够远、不被道具挡住、不挡别人的空位。
 *  落脚点不在这块地面上或就在正中间时返回 undefined */
function rowInside(spot: Point, count: number, room: Room | undefined): Point[] | undefined {
  if (!room) return undefined
  const { rect } = room
  const center: Point = [rect.x + rect.w / 2, rect.y + rect.h / 2]
  const near = (lo: number, v: number, size: number) =>
    v >= lo - WALL_MARGIN && v <= lo + size + WALL_MARGIN
  if (!near(rect.x, spot[0], rect.w) || !near(rect.y, spot[1], rect.h)) return undefined
  if (distance(center, spot) < 0.3) return undefined
  const lo: Point = [rect.x + WALL_MARGIN, rect.y + WALL_MARGIN]
  const hi: Point = [rect.x + rect.w - WALL_MARGIN, rect.y + rect.h - WALL_MARGIN]
  const clamp = (v: number, a: number, b: number) =>
    a > b ? (a + b) / 2 : Math.min(b, Math.max(a, v))
  const props = room.props.filter((p) => distance(p, spot) < SEARCH + 2)
  const free = (p: Point) =>
    p[0] >= lo[0] &&
    p[0] <= hi[0] &&
    p[1] >= lo[1] &&
    p[1] <= hi[1] &&
    props.every(
      (q) =>
        distance(p, q) >= PROP_CLEAR &&
        !(q[1] > p[1] && q[1] - p[1] < BEHIND.depth && Math.abs(q[0] - p[0]) < BEHIND.half)
    )
  // 两人横着够开，或者一前一后隔得够远
  const apart = (a: Point, b: Point) =>
    Math.abs(a[0] - b[0]) >= PERSON_GAP || Math.abs(a[1] - b[1]) >= DEPTH_GAP
  const [dx, dz] = [center[0] - spot[0], center[1] - spot[1]]
  const ideal = (i: number): Point =>
    Math.abs(dz) >= Math.abs(dx)
      ? [spot[0] + (i - (count - 1) / 2) * ROW_GAP, spot[1] + Math.sign(dz) * ROW_DEPTH]
      : [spot[0] + Math.sign(dx) * (ROW_DEPTH + i * ROW_GAP), spot[1]]
  const candidates: Point[] = []
  for (let x = -SEARCH; x <= SEARCH; x += GRID)
    for (let z = -SEARCH; z <= SEARCH; z += GRID) candidates.push([spot[0] + x, spot[1] + z])
  const chosen: Point[] = []
  for (let i = 0; i < count; i++) {
    const want = ideal(i)
    const best = [want, ...candidates]
      .filter((p) => free(p) && chosen.every((c) => apart(p, c)))
      .sort((a, b) => distance(a, want) - distance(b, want))[0]
    chosen.push(best ?? [clamp(want[0], lo[0], hi[0]), clamp(want[1], lo[1], hi[1])])
  }
  return chosen
}

/** 围着落脚点一圈 */
function ring(spot: Point, count: number): Point[] {
  const radius = Math.max(1.3, count * 0.38)
  return Array.from({ length: count }, (_, i) => {
    const angle = (i * 2 * Math.PI) / count
    return [spot[0] + Math.cos(angle) * radius, spot[1] + Math.sin(angle) * radius]
  })
}

function distance(a: Point, b: Point) {
  return Math.hypot(a[0] - b[0], a[1] - b[1])
}
