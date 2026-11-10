import type { CameraShot, DirectorCamera, GameMap } from 'town-shared/gameMap'
import { isTouch } from 'town-shared/platform'

// 选镇页的镜头：新换上来的小镇从远处推近到位，之后闲着慢慢左右漂；玩家一碰地图就停，松手几秒后从
// 当时的位置接着漂；进镇时再推近一截，停在游戏开场的近景那么近。触屏设备和要求减少动画时都不动。
// 只横着漂：倍数是整档时，横着挪是整幅画面一起走一个屏幕像素，看着是平滑的；竖着挪，斜着的地面
// 纹理会一行行地爬。

/** 推近：从比到位时宽这么多倍的地方开始，用这么久 */
const PUSH_FROM = 1.6
const PUSH_MS = 2200
/** 慢漂：一个来回这么久，往两边各漂画面宽的这个比例 */
const DRIFT_MS = 40_000
const DRIFT_SPAN = 0.025
/** 玩家松手后这么久接着漂 */
const RESUME_MS = 8000
/** 进镇：推近到选镇页宽度的这个比例（选镇页比游戏开场的近景退了一档，见 page.ts），用这么久 */
const ENTER_TO = 1 / 1.5
const ENTER_MS = 1100

const easeOut = (u: number) => 1 - (1 - u) ** 3
const easeInOut = (u: number) => (u < 0.5 ? 4 * u * u * u : 1 - (-2 * u + 2) ** 3 / 2)

/** 不该动：触屏设备（手机、平板省电），或玩家、系统要求减少动画 */
export const stageCalm = () =>
  isTouch() ||
  document.body.classList.contains('reduce-ui-motion') ||
  matchMedia('(prefers-reduced-motion: reduce)').matches

export function createStageCamera(stage: HTMLElement) {
  let camera: DirectorCamera | undefined
  /** 到位时的机位；漂是围着它左右挪 */
  let base: CameraShot | undefined
  let push:
    | {
        from: number
        to: number
        ms: number
        ease: (u: number) => number
        done?: () => void
      }
    | undefined
  /** 这一段（推近或慢漂）已经走了多久。按帧攒，一帧最多算 50 毫秒：刚建好场景那几帧常常卡一下，
   *  照墙上的钟算，推近没露面就过去一半了；切到后台再回来也不会跳 */
  let elapsed = 0
  let last: number | undefined
  let running = false
  let held = false
  let timer: ReturnType<typeof setTimeout> | undefined

  /** 每画一帧之前：按推近或慢漂摆机位 */
  const frame = (t: number) => {
    if (!camera || !base) return false
    elapsed += last === undefined ? 0 : Math.min(50, Math.max(0, t - last))
    last = t
    const pushing = !!push
    let width = base.width,
      shift = 0
    if (push) {
      const u = Math.min(1, elapsed / push.ms)
      width *= push.from + (push.to - push.from) * push.ease(u)
      if (u >= 1) {
        const done = push.done
        base = { ...base, width }
        push = undefined
        elapsed = 0
        done?.()
      }
    } else shift = Math.sin((elapsed / DRIFT_MS) * Math.PI * 2) * base.width * DRIFT_SPAN
    // 画面的横向在地图上朝哪：转过角度的地图要跟着转
    const yaw = (base.yaw * Math.PI) / 180
    camera.setShot({
      ...base,
      width,
      center: [base.center[0] + shift * Math.cos(yaw), base.center[1] - shift * Math.sin(yaw)],
    })
    // 推近时每帧都画；慢漂跟着场景自己的节拍（水波、烟每秒约 30 拍）挪，不为它多画
    return pushing
  }
  function run() {
    if (!camera || running) return
    running = true
    elapsed = 0
    last = undefined
    camera.setSmooth(true)
    camera.onFrame(frame)
  }
  function halt() {
    clearTimeout(timer)
    if (!camera || !running) return
    running = false
    camera.onFrame(null)
    camera.setSmooth(false)
  }
  /** 从镜头此刻的位置重新开始漂 */
  function drift() {
    halt()
    if (!camera || stageCalm()) return
    base = camera.shot()
    push = undefined
    run()
  }
  /** 玩家动了地图：马上停，松手几秒后接着漂 */
  function touched() {
    if (!camera) return
    // 进镇那一下推近不让打断
    if (push?.done) return
    halt()
    timer = setTimeout(() => !held && drift(), RESUME_MS)
  }
  stage.addEventListener('pointerdown', () => {
    held = true
    touched()
  })
  for (const type of ['pointerup', 'pointercancel'] as const)
    window.addEventListener(type, () => {
      if (!held) return
      held = false
      touched()
    })
  stage.addEventListener('wheel', touched, { passive: true })
  // 窗口变了大小：镜头自己会落回整档，等它落稳再漂
  window.addEventListener('resize', touched)

  return {
    /** 换上这张地图。fresh 是刚建好第一次露面：从远处推近；不然从它现在的位置接着漂 */
    show(map: GameMap, fresh: boolean) {
      halt()
      camera = map.director
      if (!camera || stageCalm()) return
      base = camera.shot()
      push = fresh ? { from: PUSH_FROM, to: 1, ms: PUSH_MS, ease: easeOut } : undefined
      run()
    },
    /** 地图要撤掉了：是正在动的那张就先停下 */
    drop(map: GameMap) {
      if (map.director !== camera) return
      halt()
      camera = base = undefined
    },
    /** 别处要挪镜头（界面盖住的边变了）：停下让它挪，挪完从新位置接着漂 */
    around(move: () => void) {
      // 进镇那一下推近不打断
      if (push?.done) return move()
      const pushing = push
      halt()
      // 还在推近：先直接到位，再让它挪
      if (pushing && camera && base) camera.setShot(base)
      move()
      drift()
    },
    /** 进镇：再推近一截，推完兑现。不动画时马上兑现 */
    enter(): Promise<void> {
      halt()
      if (!camera || stageCalm()) return Promise.resolve()
      base = camera.shot()
      return new Promise((resolve) => {
        push = { from: 1, to: ENTER_TO, ms: ENTER_MS, ease: easeInOut, done: resolve }
        run()
      })
    },
    /** 进镇没成：退回推近之前的位置接着漂 */
    back() {
      halt()
      if (!camera || !base || stageCalm()) return
      camera.setShot({ ...base, width: push ? base.width : base.width / ENTER_TO })
      drift()
    },
  }
}
