import type { Atlas, Topology } from 'town-shared/mapDocument'
import type { WalkStep, WalkTarget } from 'town-shared/gameMap'
// 化身点击移动的选路。后端没有「走到某点」的命令，也不给化身寻路，所以路线在这里算。
// 可走面按 crates/host/src/maps/walk.rs 的规则从同一份地图文件重建：dwell 区域的格子、
// dwell 房间的矩形、道路走廊、门口的短通道。前端只负责挑路线，每一段仍然发方向，
// 真正的贴墙、滑动和阻挡由后端判定，所以这里的几何差一点也不会走错，只是路线略有出入。

/** 与 crates/kernel/src/avatar/geometry.rs 一致 */
const AVATAR_RADIUS = 0.24
/** 默认地图的道具图标是功能标记，后端给它一个固定的小占地 */
export const PROP_HALF: [number, number] = [0.3, 0.3]
/** 门口两侧各留一段短通道，宽度同后端 */
const DOOR_WIDTH = 1.2
/** 地图文件没写道路宽度时后端取 18 个单位 */
export const DEFAULT_EDGE_WIDTH = 18
/** 没有区域格子时的退路：2 米一格 */
const DEFAULT_CELL_METRES = 2
/** 起点或终点落在不可走的地方时，最多往外找多远（米）去找能站的地方；
 *  按米算，格子大小不同的地图一样宽容 */
const SNAP_METRES = 5

export interface RouteObstacle {
  space: string
  position: [number, number]
  half: [number, number]
}
interface Portal {
  id: string
  from: WalkTarget
  to: WalkTarget
}

const cellKey = (space: string, x: number, y: number) => `${space}|${x}|${y}`

/** 三维地图的道路（和 town-shared/spatial.ts 的 Route 同形，这里只用到几项） */
interface SpatialRoad {
  id: string
  width: number
  points: [number, number, number][]
  owner?: string
}
interface RouteOptions {
  /** 三维地图的道路：后端按它们的点和宽度铺路 */
  routes?: SpatialRoad[]
  /** 室外这一点的地面能不能站人（不是海、不陡）；没有地形时不给 */
  ground?: (x: number, y: number) => boolean
}

type Contains = (x: number, y: number) => boolean
/** 人周围一圈 8 个点（相对中心，米），和后端 clear 一样从正东起每 45° 一个 */
const RING = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => [
  AVATAR_RADIUS * Math.cos((i * Math.PI) / 4),
  AVATAR_RADIUS * Math.sin((i * Math.PI) / 4),
])
/** 一对整数格号拼成一个数，当 Map/Set 的键（比拼字符串快）；坐标在 ±32768 格以内 */
const pair = (x: number, y: number) => (x + 32768) * 65536 + (y + 32768)

/** 可走面按 4 米一桶建索引：查一点时只看落在同一桶里的那几块 */
class ShapeIndex {
  private readonly buckets = new Map<string, Map<number, Contains[]>>()
  private readonly list: {
    space: string
    box: [number, number, number, number]
    contains: Contains
  }[] = []
  add(space: string, box: [number, number, number, number], contains: Contains) {
    this.list.push({ space, box, contains })
    let buckets = this.buckets.get(space)
    if (!buckets) this.buckets.set(space, (buckets = new Map()))
    for (let x = Math.floor(box[0] / 4); x <= Math.floor(box[2] / 4); x++)
      for (let y = Math.floor(box[1] / 4); y <= Math.floor(box[3] / 4); y++) {
        const bucket = buckets.get(pair(x, y))
        if (bucket) bucket.push(contains)
        else buckets.set(pair(x, y), [contains])
      }
  }
  covers(space: string, x: number, y: number) {
    const bucket = this.buckets.get(space)?.get(pair(Math.floor(x / 4), Math.floor(y / 4)))
    return !!bucket && bucket.some((c) => c(x, y))
  }
  all() {
    return this.list
  }
}

/** 一张地图的可走格子图；道具变化时只重算被挡住的格子。 */
export class WalkRoutes {
  private readonly cell: number
  private readonly open = new Set<string>()
  /** 门口所在的格子 → 经过它的门，A* 据此跨空间 */
  private readonly doors = new Map<string, Portal[]>()
  /** 有门的房间 → 门外、门内各一点（点房子时走到这里） */
  private readonly entrances = new Map<string, { outside: WalkTarget; inside: WalkTarget }>()
  private blocked = new Set<string>()

  constructor(
    atlas: Atlas,
    topology: Topology,
    private readonly units: number,
    /** 有三维数据时房间坐标要加摊开偏移，与 walk.rs 的 room_point 一致 */
    private readonly roomOffset: boolean,
    options: RouteOptions = {}
  ) {
    const dwell = new Set(topology.locales.filter((l) => l.kind === 'dwell').map((l) => l.id))
    this.cell =
      Math.min(
        ...atlas.regions.filter((r) => dwell.has(r.id)).map((r) => r.cell_size / units),
        DEFAULT_CELL_METRES
      ) || DEFAULT_CELL_METRES
    for (const r of atlas.regions) {
      if (!dwell.has(r.id)) continue
      const size = r.cell_size / units
      const cells = new Set(r.cells.map(([x, y]) => `${x},${y}`))
      const xs = r.cells.map((c) => c[0]),
        ys = r.cells.map((c) => c[1])
      this.shapes.add(
        OUTDOOR,
        [
          Math.min(...xs) * size,
          Math.min(...ys) * size,
          (Math.max(...xs) + 1) * size,
          (Math.max(...ys) + 1) * size,
        ],
        (x, y) => cells.has(`${Math.floor(x / size)},${Math.floor(y / size)}`)
      )
    }
    for (const s of atlas.spaces) {
      if (!dwell.has(s.id)) continue
      const [x0, y0] = this.roomPoint(s, [s.bounds.x, s.bounds.y])
      const [x1, y1] = this.roomPoint(s, [
        s.bounds.x + s.bounds.width,
        s.bounds.y + s.bounds.height,
      ])
      this.shapes.add(s.id, [x0, y0, x1, y1], (x, y) => x >= x0 && x <= x1 && y >= y0 && y <= y1)
    }
    // 道路：有三维路线时用路线的点和宽度，屋里的通道（owner）属于房间、不算室外，和 walk.rs 一致
    const routes = new Map(options.routes?.map((r) => [r.id, r]))
    for (const e of atlas.edges) {
      const route = routes.get(e.id)
      if (route?.owner) continue
      this.addCorridor(
        OUTDOOR,
        route
          ? route.points.map((p) => [p[0], p[2]] as [number, number])
          : e.polyline.map((p) => this.metres(p)),
        route ? route.width : (e.width ?? DEFAULT_EDGE_WIDTH) / units
      )
    }
    for (const s of atlas.spaces) {
      // 图上画成门的装饰不能穿越：拓扑里必须有一条带「通行」的通道连着这个房间
      if (!s.door_outside || !s.door_inside_local || !dwell.has(s.id)) continue
      if (
        !(topology.passages ?? []).some(
          (p) => (p.a === s.id || p.b === s.id) && p.capabilities.includes('通行')
        )
      )
        continue
      const outside: WalkTarget = { space: OUTDOOR, position: this.metres(s.door_outside) }
      const inside: WalkTarget = { space: s.id, position: this.roomPoint(s, s.door_inside_local) }
      for (const spot of [outside, inside])
        this.addCorridor(spot.space, [spot.position, spot.position], DOOR_WIDTH)
      this.addPortal({ id: `${s.id}:enter`, from: outside, to: inside })
      this.addPortal({ id: `${s.id}:exit`, from: inside, to: outside })
      this.entrances.set(s.id, { outside, inside })
    }
    this.ground = options.ground
    this.fillStandable(options.ground)
  }

  /** 室外地面能不能站（不是海、不陡）；没有地形时为空 */
  private readonly ground?: Contains
  /** 挡路的道具和树，按 4 米一桶：每件放进它（加上人的半径）盖到的每个桶 */
  private obstacles = new Map<string, Map<number, RouteObstacle[]>>()

  /** 人能不能站在这一点（米），和后端 crates/kernel/src/avatar/geometry.rs 的 clear 一样：
   *  周围 AVATAR_RADIUS 一圈 8 个点都落在可走面上，室外中心那点的地面不是海、不陡，也不碰道具和树。
   *  预测自己走路时按它判断撞墙，和服务端走出来的路一致 */
  clear(space: string, x: number, y: number) {
    if (space === OUTDOOR && this.ground && !this.ground(x, y)) return false
    for (const [dx, dy] of RING) if (!this.shapes.covers(space, x + dx, y + dy)) return false
    const near = this.obstacles.get(space)?.get(pair(Math.floor(x / 4), Math.floor(y / 4)))
    return !near?.some(
      (o) =>
        Math.abs(x - o.position[0]) < o.half[0] + AVATAR_RADIUS &&
        Math.abs(y - o.position[1]) < o.half[1] + AVATAR_RADIUS
    )
  }

  /** 各空间里的可走面（区域格子、房间、道路、门口），按 4 米的桶索引，查一点落没落在可走面上 */
  private readonly shapes = new ShapeIndex()

  /** 道路、门口：每一段各算一块，外框只包住这一段 */
  private addCorridor(space: string, points: [number, number][], width: number) {
    const half = width / 2
    for (let i = 0; i < Math.max(1, points.length - 1); i++) {
      const a = points[i],
        b = points[i + 1] ?? points[i]
      this.shapes.add(
        space,
        [
          Math.min(a[0], b[0]) - half,
          Math.min(a[1], b[1]) - half,
          Math.max(a[0], b[0]) + half,
          Math.max(a[1], b[1]) + half,
        ],
        (x, y) => segmentDistance([x, y], a, b) <= half
      )
    }
  }

  /** 能站的格子：和后端一样（crates/kernel/src/avatar/geometry.rs 的 clear），人的中心周围
   *  AVATAR_RADIUS 一圈 8 个点都落在可走面上，室外还要地面不是海、不陡。格子比人粗得多的旧地图
   *  （一格 2 米）只看格子中心，不然窄路会断成一截一截。 */
  private fillStandable(ground?: Contains) {
    if (this.cell > 4 * AVATAR_RADIUS) {
      // 旧地图：格子中心落在哪块可走面上就算可走，逐块填
      for (const { space, box, contains } of this.shapes.all())
        this.eachCell(box, (x, y, cx, cy) => {
          if (contains(cx, cy)) this.open.add(cellKey(space, x, y))
        })
      return
    }
    // 几块可走面重叠时外框会扫到同一格，每格只判断一次
    const seen = new Map<string, Set<number>>()
    for (const { space, box } of this.shapes.all()) {
      let done = seen.get(space)
      if (!done) seen.set(space, (done = new Set()))
      const checked = done
      this.eachCell(box, (x, y, cx, cy) => {
        if (checked.has(pair(x, y))) return
        checked.add(pair(x, y))
        if (
          this.shapes.covers(space, cx, cy) &&
          (space !== OUTDOOR || !ground || ground(cx, cy)) &&
          RING.every(([dx, dy]) => this.shapes.covers(space, cx + dx, cy + dy))
        )
          this.open.add(cellKey(space, x, y))
      })
    }
  }

  /** 外框（米）盖到的每一格：格号和格子中心 */
  private eachCell(
    box: [number, number, number, number],
    visit: (x: number, y: number, cx: number, cy: number) => void
  ) {
    const [x0, y0] = this.cellOf(box[0], box[1])
    const [x1, y1] = this.cellOf(box[2], box[3])
    for (let x = x0; x <= x1; x++)
      for (let y = y0; y <= y1; y++) visit(x, y, (x + 0.5) * this.cell, (y + 0.5) * this.cell)
  }

  /** 房间的门外、门内各一点；没有能通行的门时为空 */
  entrance(space: string) {
    return this.entrances.get(space)
  }

  /** 实际要去的点：本身能站就是它；不然在 SNAP_METRES 内找最近的能站的格子，取格子里离原点最近的一点；
   *  附近都站不了返回 null */
  destination(at: WalkTarget): WalkTarget | null {
    const key = this.nearestOpen(at)
    if (!key) return null
    const { x, y } = this.parse(key)
    const [cx, cy] = this.cellOf(...at.position)
    if (x === cx && y === cy) return at
    const margin = Math.min(0.25, this.cell / 4)
    const clamp = (v: number, cell: number) =>
      Math.min((cell + 1) * this.cell - margin, Math.max(cell * this.cell + margin, v))
    return { space: at.space, position: [clamp(at.position[0], x), clamp(at.position[1], y)] }
  }

  /** 地上的道具会挡路；拿走或收起来的不算 */
  setObstacles(list: RouteObstacle[]) {
    const blocked = new Set<string>()
    const obstacles = new Map<string, Map<number, RouteObstacle[]>>()
    for (const o of list) {
      let buckets = obstacles.get(o.space)
      if (!buckets) obstacles.set(o.space, (buckets = new Map()))
      const rx = o.half[0] + AVATAR_RADIUS,
        ry = o.half[1] + AVATAR_RADIUS
      for (
        let x = Math.floor((o.position[0] - rx) / 4);
        x <= Math.floor((o.position[0] + rx) / 4);
        x++
      )
        for (
          let y = Math.floor((o.position[1] - ry) / 4);
          y <= Math.floor((o.position[1] + ry) / 4);
          y++
        ) {
          const bucket = buckets.get(pair(x, y))
          if (bucket) bucket.push(o)
          else buckets.set(pair(x, y), [o])
        }
    }
    this.obstacles = obstacles
    for (const o of list) {
      const reach = [o.half[0] + AVATAR_RADIUS, o.half[1] + AVATAR_RADIUS]
      const [x0, y0] = this.cellOf(o.position[0] - reach[0], o.position[1] - reach[1])
      const [x1, y1] = this.cellOf(o.position[0] + reach[0], o.position[1] + reach[1])
      for (let x = x0; x <= x1; x++)
        for (let y = y0; y <= y1; y++) {
          const c = this.centre(x, y)
          if (
            Math.abs(c[0] - o.position[0]) < reach[0] &&
            Math.abs(c[1] - o.position[1]) < reach[1]
          )
            blocked.add(cellKey(o.space, x, y))
        }
    }
    this.blocked = blocked
  }

  /** 从 from 走到 to 的路径点；走不到返回 null。带 portal 的一步表示走到门口再开门。
   *  to 站不了时终点换成附近能站的地方（见 destination），最后一个点就是实际要去的地方 */
  find(from: WalkTarget, to: WalkTarget): WalkStep[] | null {
    const end = this.destination(to)
    const start = this.nearestOpen(from),
      goal = end && cellKey(end.space, ...this.cellOf(...end.position))
    if (!start || !end || !goal) return null
    const came = new Map<string, { previous: string; portal?: Portal }>()
    const best = new Map<string, number>([[start, 0]])
    const queue = new Heap()
    queue.push(start, this.guess(start, goal))
    while (queue.size) {
      const here = queue.pop()!
      if (here === goal) return this.steps(came, here, end, from)
      const cost = best.get(here)!
      for (const [next, step, portal] of this.neighbours(here)) {
        const total = cost + step
        if ((best.get(next) ?? Infinity) <= total) continue
        best.set(next, total)
        came.set(next, { previous: here, portal })
        queue.push(next, total + this.guess(next, goal))
      }
    }
    return null
  }

  // ---- 内部 ----

  private addPortal(portal: Portal) {
    const [x, y] = this.cellOf(...portal.from.position)
    const key = cellKey(portal.from.space, x, y)
    this.doors.set(key, [...(this.doors.get(key) ?? []), portal])
  }
  private metres(p: [number, number]): [number, number] {
    return [p[0] / this.units, p[1] / this.units]
  }
  private roomPoint(space: Atlas['spaces'][number], p: [number, number]): [number, number] {
    return this.roomOffset
      ? this.metres([p[0] + space.unfold.offset_x, p[1] + space.unfold.offset_y])
      : this.metres(p)
  }
  private cellOf(x: number, y: number): [number, number] {
    return [Math.floor(x / this.cell), Math.floor(y / this.cell)]
  }
  private centre(x: number, y: number): [number, number] {
    return [(x + 0.5) * this.cell, (y + 0.5) * this.cell]
  }
  private parse(key: string): { space: string; x: number; y: number } {
    const i = key.indexOf('|'),
      j = key.lastIndexOf('|')
    return { space: key.slice(0, i), x: Number(key.slice(i + 1, j)), y: Number(key.slice(j + 1)) }
  }
  private point(key: string): [number, number] {
    const { x, y } = this.parse(key)
    return this.centre(x, y)
  }
  private walkable(key: string) {
    return this.open.has(key) && !this.blocked.has(key)
  }
  /** 点所在的格子能站就是它，不然在 SNAP_METRES 内找格子中心离这点最近的能站的格子 */
  private nearestOpen(at: WalkTarget): string | null {
    const [cx, cy] = this.cellOf(...at.position)
    let best: string | null = null,
      bestDistance = Infinity
    for (let ring = 0; ring <= Math.ceil(SNAP_METRES / this.cell); ring++) {
      // 这一圈的格子中心离这点至少还有 ring - 1 格：已经找到更近的就不用再往外
      if ((ring - 1) * this.cell > bestDistance) break
      for (let x = cx - ring; x <= cx + ring; x++)
        for (let y = cy - ring; y <= cy + ring; y++) {
          if (Math.max(Math.abs(x - cx), Math.abs(y - cy)) !== ring) continue
          const key = cellKey(at.space, x, y)
          if (!this.walkable(key)) continue
          if (ring === 0) return key
          const c = this.centre(x, y)
          const d = Math.hypot(c[0] - at.position[0], c[1] - at.position[1])
          if (d <= SNAP_METRES && d < bestDistance) {
            best = key
            bestDistance = d
          }
        }
    }
    return best
  }
  /** 四邻接不会切到格子的角；门是额外的一条跨空间的边 */
  private neighbours(key: string): [string, number, Portal?][] {
    const { space, x, y } = this.parse(key)
    const out: [string, number, Portal?][] = []
    for (const [dx, dy] of [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ]) {
      const next = cellKey(space, x + dx, y + dy)
      if (this.walkable(next)) out.push([next, this.cell])
    }
    for (const portal of this.doors.get(key) ?? []) {
      const [tx, ty] = this.cellOf(...portal.to.position)
      const next = cellKey(portal.to.space, tx, ty)
      if (this.walkable(next)) out.push([next, this.cell, portal])
    }
    return out
  }
  private guess(from: string, to: string) {
    const a = this.parse(from),
      b = this.parse(to)
    // 跨空间时曼哈顿距离没有意义，给 0 退化成 Dijkstra，仍然找得到最短路
    if (a.space !== b.space) return 0
    return (Math.abs(a.x - b.x) + Math.abs(a.y - b.y)) * this.cell
  }
  /** 回溯成路径点，再把同一空间内看得通的连续点并掉。起点站在能走的格子上时从它本身出发，
   *  不先绕回格子中心 */
  private steps(
    came: Map<string, { previous: string; portal?: Portal }>,
    goal: string,
    to: WalkTarget,
    from: WalkTarget
  ): WalkStep[] {
    const chain: { key: string; portal?: Portal }[] = [{ key: goal }]
    for (let key = goal; came.has(key);) {
      const from = came.get(key)!
      chain[chain.length - 1].portal = from.portal
      chain.push({ key: from.previous })
      key = from.previous
    }
    chain.reverse()
    const raw: WalkStep[] = []
    for (let i = 0; i < chain.length; i++) {
      const { key, portal } = chain[i]
      const space = this.parse(key).space
      // 穿门要站到门口那一点上，后端要求离门 1.6 米内才开得了门
      if (portal) raw.push({ point: portal.from, portal: portal.id })
      else raw.push({ point: { space, position: this.point(key) } })
    }
    const [fx, fy] = this.cellOf(...from.position)
    if (!raw[0].portal && chain[0].key === cellKey(from.space, fx, fy)) raw[0] = { point: from }
    raw.push({ point: to })
    return this.smooth(raw)
  }
  /** 连续两点之间直线可走时去掉中间的点，走出来才不是锯齿 */
  private smooth(steps: WalkStep[]): WalkStep[] {
    const out: WalkStep[] = []
    for (let i = 0; i < steps.length;) {
      out.push(steps[i])
      if (steps[i].portal) {
        i++
        continue
      }
      let next = i + 1
      for (let j = i + 2; j < steps.length; j++) {
        if (steps[j - 1].portal || steps[j].portal) break
        if (steps[j].point.space !== steps[i].point.space) break
        if (!this.clearLine(steps[i].point, steps[j].point)) break
        next = j
      }
      i = next
    }
    return out.filter((s, i) => i === 0 || s.portal || !same(s.point, out[i - 1].point))
  }
  private clearLine(a: WalkTarget, b: WalkTarget) {
    const distance = Math.hypot(b.position[0] - a.position[0], b.position[1] - a.position[1])
    const steps = Math.ceil(distance / (this.cell / 2))
    for (let i = 0; i <= steps; i++) {
      const t = i / steps
      const [x, y] = this.cellOf(
        a.position[0] + (b.position[0] - a.position[0]) * t,
        a.position[1] + (b.position[1] - a.position[1]) * t
      )
      if (!this.walkable(cellKey(a.space, x, y))) return false
    }
    return true
  }
}

/** 同 grid.ts 的 OUTDOOR_SPACE。scripts/tests/avatar-walk-to.test.mjs 把本文件单独编译后加载，
 *  本文件不能有运行时 import，所以这里另写一份 */
const OUTDOOR = 'town_outdoor'

function same(a: WalkTarget, b: WalkTarget) {
  return a.space === b.space && a.position[0] === b.position[0] && a.position[1] === b.position[1]
}

function segmentDistance(p: [number, number], a: [number, number], b: [number, number]) {
  const dx = b[0] - a[0],
    dy = b[1] - a[1]
  const length = dx * dx + dy * dy
  const t = length
    ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length))
    : 0
  return Math.hypot(p[0] - (a[0] + dx * t), p[1] - (a[1] + dy * t))
}

/** A* 的开放集合；地图一格 2 米，整张图约一万五千格，一次查询几毫秒 */
class Heap {
  private items: { key: string; rank: number }[] = []
  get size() {
    return this.items.length
  }
  push(key: string, rank: number) {
    this.items.push({ key, rank })
    for (let i = this.items.length - 1; i > 0;) {
      const parent = (i - 1) >> 1
      if (this.items[parent].rank <= this.items[i].rank) break
      ;[this.items[parent], this.items[i]] = [this.items[i], this.items[parent]]
      i = parent
    }
  }
  pop() {
    const top = this.items[0]
    const last = this.items.pop()!
    if (this.items.length) {
      this.items[0] = last
      for (let i = 0; ;) {
        const left = i * 2 + 1,
          right = left + 1
        let small = i
        if (left < this.items.length && this.items[left].rank < this.items[small].rank) small = left
        if (right < this.items.length && this.items[right].rank < this.items[small].rank)
          small = right
        if (small === i) break
        ;[this.items[small], this.items[i]] = [this.items[i], this.items[small]]
        i = small
      }
    }
    return top?.key
  }
}
