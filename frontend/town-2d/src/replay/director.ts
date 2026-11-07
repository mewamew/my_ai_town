// 重演拍素材的遥控，挂在 window.director：跳到录像的哪一刻、一帧一帧往前走、镜头怎么摆、界面藏不藏。
// 只给拍摄脚本（scripts/replay/shoot.mjs）用，页面上没有按钮。时刻是离这一卷开头的毫秒；
// 镜头按地面点（地图坐标）、画面宽度（地图单位）、转角和俯角（度）摆，分辨率不同取景也一样。
import type { CameraShot, GameMap } from 'town-shared/gameMap'
import type { DepthBlur } from 'town-shared/quality'
import type { VirtualClock } from './clock'
import type { ReplaySource } from './source'
import './replay.css'

/** 一个机位：跟住谁（村民编号）或对准哪一点，加上宽度、转角、俯角；没给的沿用此刻的 */
export interface Aim {
  follow?: string
  at?: [number, number]
  width?: number
  yaw?: number
  pitch?: number
}

/** 镜头此刻的样子；rise 是对准的那一点往上抬多少（对准人时是半个身子） */
interface Pose extends CameraShot {
  rise: number
}

const CURVES = {
  /** 慢起慢停 */
  smooth: (u: number) => (u < 0.5 ? 4 * u * u * u : 1 - (-2 * u + 2) ** 3 / 2),
  linear: (u: number) => u,
}
type Curve = keyof typeof CURVES

const lerp = (a: number, b: number, e: number) => a + (b - a) * e
/** 转角走近的那一边 */
const turn = (a: number, b: number, e: number) => a + (((b - a + 540) % 360) - 180) * e

/** 新的机位盖在旧的上面：跟人和对准一点二选一 */
function merge(base: Aim, aim: Aim): Aim {
  const next = { ...base, ...aim }
  if (aim.follow) delete next.at
  if (aim.at) delete next.follow
  return next
}

export function createDirector(map: GameMap, source: ReplaySource, clock: VirtualClock) {
  const camera = map.director
  if (!camera) throw Error('这张地图没有立体场景，拍不了')
  /** 录像放到哪（毫秒） */
  let reel = 0
  /** 镜头停着时的机位 */
  let steady: Aim = {}
  let pose: Pose | null = null
  let move: { from: Pose; to: Aim; start: number; ms: number; curve: Curve } | null = null

  const current = (): Pose => pose ?? { ...camera.shot(), rise: 0 }
  /** 机位落到此刻：跟着的人画在哪就对准哪 */
  const resolve = (aim: Aim, base: Pose): Pose => {
    const at = aim.follow ? camera.drawnAt(aim.follow) : aim.at
    return {
      center: at ?? base.center,
      rise: aim.follow && at ? camera.bodyRise() : aim.at ? 0 : base.rise,
      width: aim.width ?? base.width,
      yaw: aim.yaw ?? base.yaw,
      pitch: aim.pitch ?? base.pitch,
    }
  }
  /** 每画一帧之前：按机位（或正在推拉的那一段）摆好镜头 */
  const frame = () => {
    const base = current()
    let next = resolve(steady, base)
    if (move) {
      const u = Math.min(1, (reel - move.start) / move.ms)
      const e = CURVES[move.curve](u)
      const to = resolve(move.to, move.from)
      next = {
        center: [
          lerp(move.from.center[0], to.center[0], e),
          lerp(move.from.center[1], to.center[1], e),
        ],
        rise: lerp(move.from.rise, to.rise, e),
        width: Math.exp(lerp(Math.log(move.from.width), Math.log(to.width), e)),
        yaw: turn(move.from.yaw, to.yaw, e),
        pitch: lerp(move.from.pitch, to.pitch, e),
      }
      if (u >= 1) {
        steady = merge(steady, move.to)
        move = null
      }
    }
    pose = next
    camera.setShot(next, next.rise)
    return true
  }
  camera.onFrame(frame)

  const director = {
    /** 画面建好（立体场景起来了） */
    ready: map.ready ?? Promise.resolve(),
    /** 录像里第一行和最后一行的时刻 */
    span: () => source.span(),
    /** 录像放到哪 */
    time: () => reel,
    /** 此刻的小镇时钟（如 "D2 05:42"） */
    clock: () => {
      const roster = source.roster()
      return roster && roster.type === 'roster' ? roster.clock : ''
    },
    /** 此刻名册里的人 */
    residents: () => {
      const roster = source.roster()
      if (!roster || roster.type !== 'roster') return []
      return roster.locales.flatMap((l) => l.members.map((m) => ({ id: m.id, name: m.name })))
    },
    /** 跳到录像的 t 毫秒；之后先空走一两秒，人和气泡就位了再拍 */
    seek(t: number) {
      reel = t
      move = null
      source.seek(t)
      map.requestFrame?.()
    },
    /** 从此时间只按 step 走，镜头连续移动 */
    hold() {
      clock.hold()
      camera.setSmooth(true)
    },
    /** 往前走 ms 毫秒：交出这段时间里录下的消息，再画一帧 */
    step(ms: number) {
      if (!clock.holding) director.hold()
      reel += ms
      source.pump(reel)
      map.requestFrame?.()
      clock.advance(ms)
    },
    /** 马上摆到这个机位 */
    camera(aim: Aim) {
      move = null
      steady = merge(steady, aim)
      pose = resolve(steady, current())
      camera.setShot(pose, pose.rise)
      map.requestFrame?.()
    },
    /** 用 seconds 秒（录像时间）推拉摇移到这个机位 */
    move(aim: Aim, seconds: number, curve: Curve = 'smooth') {
      move = { from: current(), to: aim, start: reel, ms: Math.max(1, seconds * 1000), curve }
      map.requestFrame?.()
    },
    /** 景深对准谁；null 不对准 */
    focus(id: string | null) {
      camera.focus(id)
    },
    blur(level: DepthBlur) {
      map.setDepthBlur?.(level)
    },
    /** 界面：clean 藏掉按钮和面板；names、bubbles 管名字和头顶的气泡留不留 */
    ui(options: { clean?: boolean; names?: boolean; bubbles?: boolean }) {
      const body = document.body.classList
      if (options.clean !== undefined) body.toggle('replay-clean', options.clean)
      // 页面拿到第一份名册会选中第一个人（脚下一圈光）；干净画面不要
      if (options.clean) map.setSelected(null)
      if (options.names !== undefined) body.toggle('replay-no-names', !options.names)
      if (options.bubbles !== undefined) body.toggle('replay-no-bubbles', !options.bubbles)
    },
    /** 人此刻站在哪（地图坐标）；不在地图上时为 null */
    position: (id: string) => camera.drawnAt(id) ?? null,
    /** 人在屏幕上的范围（CSS 像素），自查有没有出画用；不在画面里时为 null */
    where: (id: string) => map.getScreenBox?.(id) ?? null,
    /** 镜头此刻的机位 */
    shot: (): CameraShot => {
      const { center, width, yaw, pitch } = current()
      return { center, width, yaw, pitch }
    },
  }
  return director
}

export type Director = ReturnType<typeof createDirector>
