import type { GameMap, WalkStep, WalkTarget } from '../gameMap'
import type { AvatarCommand, AvatarState } from './types'
import type { ClientMsg, WorldHold } from '../protocol'
import type { AvatarTarget } from './ui-types'
import { createWalkingInput } from './input'
import { createWalkTo } from './walkTo'
interface AvatarNavigationDeps {
  map: GameMap
  signal: AbortSignal
  getState: () => AvatarState | null
  getWorld: () => string
  getHolds: () => WorldHold[]
  owned: () => boolean
  mapVisible: () => boolean
  send: (msg: ClientMsg) => void
  execute: (cmd: AvatarCommand) => Promise<boolean>
  targets: () => AvatarTarget[]
  /** Tab 换当前对象；没有可换的返回 false */
  cycleTarget?: (step: 1 | -1) => boolean
  toggleBag: () => void
  /** F：对当前对象施展神力（开着化身神力时） */
  miracleMenu: () => void
  showToast: (message: string, sticky?: boolean) => void
  /** 化身方向变化（已按能否行走归零），供脚步声使用 */
  onDirection?: (direction: [number, number]) => void
  /** 玩家开始走（点地图、按方向键、推摇杆）：镜头重新跟上 */
  onWalk?: () => void
}

/** 判断走没走动、到点前减速按多长一段算（秒）：方向每 0.1 秒发一次，后端按真实经过的时间走
 *  （见 crates/host/src/avatar/tick.rs 的 advance_avatar），0.1 秒就是相邻两次方向之间走的路 */
const TICK_SECONDS = 0.1
/** 旧服务端不给步速时按村民的步速算：每模拟分钟 12 米 */
const RESIDENT_METRES_PER_MINUTE = 12
/** 追人时多久看一次他挪没挪开（毫秒） */
const CHASE_CHECK_MS = 300
/** 自动跟随：离带路的人超过这么远（米）就追上去，追到这么近停下 */
const FOLLOW_START = 2.4
const FOLLOW_STOP = 1.4

/** 自己跟着别人走的同行：编号和带路的人；不在同行里或自己带路时为空 */
function followedWalk(state: AvatarState | null): { id: string; leader: string } | undefined {
  const walk = state?.interactions?.find((i) => i.status === 'running' && i.kind.kind === 'walk')
  const kind = walk?.kind
  return walk && kind?.kind === 'walk' && kind.leader !== state?.actor?.id
    ? { id: walk.id, leader: kind.leader }
    : undefined
}

/** 行走输入、点击目标的路线与到达后的互动。 */
export function createAvatarNavigation(deps: AvatarNavigationDeps) {
  const { map, signal, getState, getWorld, getHolds, owned, mapVisible, send, execute } = deps
  const { targets, cycleTarget, toggleBag, miracleMenu, showToast, onDirection, onWalk } = deps
  // 化身输入的序号：换租约时从头计
  let inputSequence = 0
  /** 按住 Shift 在跑；输入模块建好之前当作没按 */
  let running = () => false
  /** 此刻每秒走多少米：步速（奔跑再乘倍数）× 每秒的模拟分钟数 */
  const metresPerSecond = () => {
    const state = getState()
    const walk = state?.walk
    const perMinute =
      (walk?.metres_per_minute ?? RESIDENT_METRES_PER_MINUTE) *
      (walk && running() ? walk.sprint_factor : 1)
    return perMinute * (state?.speed ?? 0)
  }
  /** 相邻两次方向之间走多少米 */
  const stepMetres = () => metresPerSecond() * TICK_SECONDS
  const canWalk = () => {
    const state = getState()
    return (
      owned() &&
      mapVisible() &&
      !!map.avatarSupported &&
      !!state?.speed &&
      !state?.actor?.busy &&
      (state?.mode !== 'possession' || !!state?.actor?.body?.can_move)
    )
  }
  const emitDirection = (direction: [number, number]) => {
    const state = getState()
    if (!owned()) return
    if (!canWalk()) direction = [0, 0]
    onDirection?.(direction)
    // 还没拿到租约时不发；发出去的同时交给地图预先画（服务端按到达时刻换方向，两边走的路一样）
    map.setAvatarMotion?.(state?.epoch ? direction : [0, 0], metresPerSecond())
    if (!state?.epoch) return
    send({
      type: 'avatar_input',
      world_id: getWorld(),
      epoch: state.epoch,
      sequence: ++inputSequence,
      navigation_revision: state.navigation_revision ?? 1,
      direction,
      ...(running() && { run: true }),
    })
  }
  const emitManualDirection = (direction: [number, number]) => {
    if ((direction[0] || direction[1]) && canWalk()) onWalk?.()
    emitDirection(map.walkDirection?.(direction) ?? direction)
  }
  const primaryAction = () => {
    if (owned())
      targets()
        .find((t) => t.prompt.key)
        ?.run()
  }
  const bagAction = () => {
    if (owned() && mapVisible()) toggleBag()
  }
  /** 化身此刻的米制位置：地图在预测自己的小人时用它画的位置（服务端马上要走到的地方，比名册新），
   *  不然用服务端给的自由位置；站在落脚点时退回地图上的坐标 */
  const herePoint = (): WalkTarget | undefined => {
    const state = getState()
    const a = state?.actor
    if (!a) return undefined
    const predicted = map.avatarAt?.()
    if (predicted) return predicted
    const at = a.locus.at
    if (at.kind === 'free') return { space: at.space, position: at.position }
    return map.walkTargetOf?.('person', a.id)
  }
  // 走到目标后要做的那件事（提示编号）；只是走过去时为空
  let arriveAction: string | null = null
  /** 到了要做的不是对象的主动作（比如施展神力）：做这个；对方正忙也照做 */
  let arriveAct: (() => void) | null = null
  /** 正在走向的人：他走开（出门、进屋、换地方）时路线跟着改，不扑空到他原来站的地方 */
  let chasing: { id: string; at: WalkTarget; checked: number } | null = null
  /** 跟着村民走时的自动跟随：他走到哪就跟到哪。世界不带着玩家操控的人走（见 kernel 的
   *  interactions/walk.rs），答应跟着走就由这里跟上；自己走动（按方向、点地图、点人或东西）、
   *  在操作条上关掉或同行结束时停下 */
  let autoFollow: string | null = null
  /** 已经替玩家打开过自动跟随的那场同行：每场只自动开一次，玩家关掉或自己走开后不再打开 */
  let autoFollowWalk: string | null = null
  // 路线经过门时化身自己发开门命令，这一下不算用户改主意，不该清掉路线
  let autoPortal = false
  /** 选一条绕开障碍的路线；地图没有选路能力时退回直线 */
  function planRoute(to: WalkTarget): WalkStep[] | null {
    const here = herePoint()
    if (!here) return null
    if (!map.walkRoute) return [{ point: to }]
    return map.walkRoute(here, to)
  }
  const walk = createWalkTo({
    here: herePoint,
    step: stepMetres,
    canWalk,
    emit: emitDirection,
    portal: async (id) => {
      autoPortal = true
      try {
        return await execute({ kind: 'portal', id })
      } finally {
        autoPortal = false
      }
    },
    replan: planRoute,
    sees: (from, to) => map.walkSees?.(from, to) ?? true,
    end: (reason) => {
      map.setAvatarDestination?.(null)
      const object = arriveAction
      const act = arriveAct
      arriveAction = null
      arriveAct = null
      chasing = null
      if (reason === 'arrived' && object) runOnArrival(object, act)
      else if (reason === 'blocked')
        showToast(object ? '走不过去，先靠近一点再点' : '走不过去，换个位置试试')
    },
  })
  /** 够得着、可以做了：要做的是主动作时对方还得有空，另有要做的事（施展神力）时够得着就行 */
  const doable = (t: AvatarTarget, act: (() => void) | null) =>
    !t.approach && (!!act || !t.prompt.muted)
  /** 走到了：这时的状态就是后端按同一位置算出来的，能做就直接做 */
  function runOnArrival(id: string, act: (() => void) | null) {
    const target = targets().find((t) => t.prompt.id === id)
    if (target && doable(target, act)) (act ?? target.run)()
    else
      showToast(
        target?.approach
          ? '还说不上话，换个不隔着东西的位置再试'
          : target
            ? target.prompt.label
            : '走到了，但现在够不着'
      )
  }
  /** 要找的人或东西已经够得着：不必走到终点，停下就做 */
  function arriveEarly() {
    const ready = arriveAction ? targets().find((t) => t.prompt.id === arriveAction) : undefined
    if (ready && doable(ready, arriveAct)) walk.arrive()
  }
  const input = createWalkingInput(
    canWalk,
    (direction) => {
      // 按方向键就放弃点击的目标和自动跟随；松键和失焦发的零向量不算
      if (direction[0] || direction[1]) {
        autoFollow = null
        walk.clear()
      }
      emitManualDirection(direction)
    },
    primaryAction,
    signal,
    { KeyB: bagAction, KeyF: () => owned() && mapVisible() && miracleMenu() },
    cycleTarget
  )
  running = input.running
  // 触屏摇杆：按住时每 100 毫秒重发一次方向（后端的输入会过期），松手发零向量
  let stickDirection: [number, number] | null = null
  let stickTimer = 0
  function stick(direction: [number, number] | null) {
    if (!direction) {
      if (!stickDirection) return
      stickDirection = null
      clearInterval(stickTimer)
      emitDirection([0, 0])
      return
    }
    if (!stickDirection) {
      // 和按方向键一样：推摇杆就放弃点击的目标和自动跟随
      autoFollow = null
      walk.clear()
      stickTimer = window.setInterval(() => {
        if (stickDirection) emitManualDirection(stickDirection)
      }, 100)
    }
    stickDirection = direction
    emitManualDirection(direction)
  }
  signal.addEventListener('abort', () => clearInterval(stickTimer))
  /** 停下：方向键、摇杆和点击目标一起清掉。化身自己开门那一下除外，那是路线的一部分。 */
  function stopMoving() {
    input.stop()
    stick(null)
    if (!autoPortal) walk.clear()
  }
  /** 设一个新的点击目标；走不了就说明原因。act 是到了要做的事，不给就做对象的主动作 */
  function startWalk(
    target: WalkTarget,
    radius: number,
    object: string | null,
    act: (() => void) | null = null
  ): boolean {
    const state = getState(),
      holds = getHolds()
    if (!owned()) return false
    if (!state?.speed) {
      showToast(holds.length ? '世界因故暂停，请查看交谈面板中的原因' : '世界已暂停，请先继续运行')
      return false
    }
    if (state.actor?.busy) {
      showToast(`正在${state.actor.activity}，停下来才能走动`, true)
      return false
    }
    if (!canWalk()) {
      showToast('现在的身体状况走不动', true)
      return false
    }
    if (!herePoint()) {
      showToast('位置还没同步，请稍候再点', true)
      return false
    }
    const route = planRoute(target)
    if (!route?.length) {
      showToast('找不到能走过去的路')
      return false
    }
    arriveAction = object
    arriveAct = act
    // 自己选了要去的地方：不再自动跟着带路的人，不然下一拍就被拉回他身后
    autoFollow = null
    walk.set(route, radius)
    // 圈画在实际要去的地方：点到站不了的地方时，选路换成了附近能站的一点
    map.setAvatarDestination?.(route[route.length - 1].point)
    onWalk?.()
    // 当场发出第一份方向，不等下一拍的化身状态
    walk.tick()
    return true
  }
  /** 点地图上的人或道具：够得着就直接做，够不着就走过去，到了再做一次。act 是要做的事，
   *  不给就做对象的主动作（交谈、拾取……）。点自己或对象不在图上时交回观察界面。 */
  function reachFor(kind: 'person' | 'prop', id: string, act?: () => void): boolean {
    const state = getState()
    if (kind === 'person' && id === state?.actor?.id) return false
    const object = `${kind}:${id}`
    const ready = targets().find((t) => t.prompt.id === object)
    if (ready && doable(ready, act ?? null) && state?.speed && !state.actor?.busy) {
      ;(act ?? ready.run)()
      return true
    }
    const target = map.walkTargetOf?.(kind, id)
    if (!target) return false
    // 停在伸手可及的距离外（后端道具 1.6 米、交谈 3 米），不踩到对象身上
    if (startWalk(target, kind === 'person' ? 1.4 : 1.2, object, act) && kind === 'person')
      chasing = { id, at: target, checked: performance.now() }
    return true
  }
  /** 每收到一次化身状态：要找的人或东西已经够得着就停下来做；要找的人挪开一米以上
   *  （或进了别的屋子），按他现在的位置重新选路 */
  function followChased() {
    arriveEarly()
    keepFollowing()
    if (!chasing || (!arriveAction && chasing.id !== autoFollow)) return
    const now = performance.now()
    if (now - chasing.checked < CHASE_CHECK_MS) return
    chasing.checked = now
    const there = map.walkTargetOf?.('person', chasing.id)
    if (!there) return
    const moved =
      there.space !== chasing.at.space ||
      Math.hypot(
        there.position[0] - chasing.at.position[0],
        there.position[1] - chasing.at.position[1]
      ) > 1
    if (!moved) return
    const route = planRoute(there)
    if (!route?.length) return
    chasing.at = there
    walk.set(route, 1.4)
    map.setAvatarDestination?.(route[route.length - 1].point)
  }
  /** 自动跟随：同行还在、他还在带路就追上去，到了身后就停；同行结束就关掉。
   *  新的一场同行里自己是跟着走的人（答应了别人带路、跟上了路过的同行）时先替玩家打开 */
  function keepFollowing() {
    const followed = followedWalk(getState())
    if (followed && followed.id !== autoFollowWalk) {
      autoFollowWalk = followed.id
      autoFollow = followed.leader
    }
    if (!autoFollow) return
    if (followed?.leader !== autoFollow) {
      autoFollow = null
      return
    }
    if (chasing?.id === autoFollow || !canWalk()) return
    const there = map.walkTargetOf?.('person', autoFollow)
    const here = herePoint()
    if (!there || !here) return
    const gap =
      here.space === there.space
        ? Math.hypot(here.position[0] - there.position[0], here.position[1] - there.position[1])
        : Infinity
    if (gap <= FOLLOW_START) return
    const route = planRoute(there)
    if (!route?.length) return
    arriveAction = null
    arriveAct = null
    walk.set(route, FOLLOW_STOP)
    chasing = { id: autoFollow, at: there, checked: performance.now() }
    walk.tick()
  }
  map.onAvatarWalkTo = (target) => {
    if (owned() && startWalk(target, 0.5, null)) chasing = null
  }
  signal.addEventListener('abort', () => {
    map.onAvatarWalkTo = null
    map.setAvatarDestination?.(null)
  })
  return {
    canWalk,
    walk,
    followChased,
    stopMoving,
    reachFor,
    stick,
    /** 和按 E 一样：做当前对象的主动作 */
    primary: primaryAction,
    /** 换了租约：输入序号从头计 */
    restartSequence() {
      inputSequence = 0
    },
    autoFollow: () => autoFollow,
    setAutoFollow(id: string | null) {
      autoFollow = id
      if (!id && chasing) walk.clear()
      keepFollowing()
    },
  }
}
