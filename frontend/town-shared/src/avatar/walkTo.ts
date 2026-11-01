import type { WalkStep, WalkTarget } from '../gameMap'
// 点击移动：后端只接受方向（avatar_input），没有「走到某点」的命令。
// 路线由地图选好（见 town-2d 的 route.ts），这里逐段走：设好路线和每收到一次化身状态时按最新位置
// 重算方向，到了一个路径点换下一个，遇到门先站到门口再开门。撞墙由后端沿墙滑动；
// 一段路连续几拍走不动就重新选一次路线，还是不行才算走不过去。

/** 连续这么多拍几乎没动就算这一段走不动 */
const STUCK_TICKS = 6
/** 位移小于一拍步长的这个比例算没动 */
const STILL_RATIO = 0.1
/** 中途路径点不必踩准 */
const WAYPOINT_RADIUS = 1
/** 门口要站得够近：后端要求离门 1.6 米内才开得了门 */
const PORTAL_RADIUS = 0.6
/** 同一次点击最多重新选路的次数 */
const REPLAN_LIMIT = 2

type WalkEnd = 'arrived' | 'blocked' | 'cancelled'
interface WalkDeps {
  /** 化身此刻的米制位置 */
  here: () => WalkTarget | undefined
  /** 后端一拍走多少米（按现在的步速，奔跑时更多）；暂停时为 0 */
  step: () => number
  /** 现在还能不能走：暂停、正忙、不能动时为假 */
  canWalk: () => boolean
  emit: (direction: [number, number]) => void
  /** 走到门口了：开门。失败就重新选路 */
  portal: (id: string) => Promise<boolean>
  /** 被挡住时重新选路；null 表示确实走不过去 */
  replan: (to: WalkTarget) => WalkStep[] | null
  end: (reason: WalkEnd) => void
}

export function createWalkTo(deps: WalkDeps) {
  let route: WalkStep[] = []
  let index = 0
  let radius = 0
  let replans = 0
  let opening = false
  let last: [number, number] | null = null
  let still = 0
  const goal = () => route[route.length - 1]?.point
  function rest() {
    last = null
    still = 0
  }
  function finish(reason: WalkEnd) {
    if (!route.length) return
    route = []
    index = 0
    opening = false
    rest()
    if (reason !== 'cancelled') deps.emit([0, 0])
    deps.end(reason)
  }
  /** 这一段走不动：换一条路线再试，换不出来才放弃 */
  function retry() {
    const target = goal()
    const next = replans < REPLAN_LIMIT && target ? deps.replan(target) : null
    if (!next?.length) return finish('blocked')
    replans++
    route = next
    index = 0
    rest()
  }
  return {
    /** steps 是完整路线，最后一个点是真正的目标；radius 是停在目标多远处 */
    set(steps: WalkStep[], stop: number) {
      route = steps
      index = 0
      radius = stop
      replans = 0
      opening = false
      rest()
    },
    clear() {
      if (route.length) finish('cancelled')
    },
    /** 还没走到终点但已经够得着要找的人或东西：就当走到了 */
    arrive() {
      if (route.length && !opening) finish('arrived')
    },
    /** 设好路线后马上调一次，之后每收到一次化身状态调一次：位置是新的，方向也要重发，
     *  后端 350 毫秒不刷新就归零。已经到了的路径点一并跳过，同一次就朝下一个点出发 */
    tick() {
      if (!route.length || opening) return
      if (!deps.canWalk()) return finish('cancelled')
      const here = deps.here()
      if (!here) return finish('blocked')
      let dx = 0,
        dy = 0,
        distance = 0
      for (;;) {
        const step = route[index]
        if (here.space !== step.point.space) return retry()
        dx = step.point.position[0] - here.position[0]
        dy = step.point.position[1] - here.position[1]
        distance = Math.hypot(dx, dy)
        const reach = step.portal
          ? PORTAL_RADIUS
          : index === route.length - 1
            ? radius
            : WAYPOINT_RADIUS
        if (distance > reach) break
        if (step.portal) {
          opening = true
          deps.emit([0, 0])
          void deps.portal(step.portal).then((ok) => {
            if (!opening) return
            opening = false
            rest()
            if (!ok) retry()
            else if (++index >= route.length) finish('arrived')
          })
          return
        }
        rest()
        if (++index >= route.length) return finish('arrived')
      }
      const step0 = Math.max(deps.step(), 0.01)
      if (last) {
        const moved = Math.hypot(here.position[0] - last[0], here.position[1] - last[1])
        still = moved < step0 * STILL_RATIO ? still + 1 : 0
        if (still >= STUCK_TICKS) return retry()
      }
      last = [...here.position]
      // 剩下不足两拍时按比例缩短向量减速：后端取 n = hypot(方向).max(1)，短向量就是慢速，不会被放大回满速。
      const scale = Math.min(1, distance / (2 * step0))
      deps.emit([(dx / distance) * scale, (dy / distance) * scale])
    },
  }
}
