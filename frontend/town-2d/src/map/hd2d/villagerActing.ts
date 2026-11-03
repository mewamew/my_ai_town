import { hashString } from '../pixel/noise'
import type { Direction, HeadTurn, Stance, View } from './villagerSprite'
import type { Eyes, Frame } from './villagerRig'

// 村民此刻在演什么：呼吸、眨眼、看哪儿、走到哪一步、起步停步和转身，每帧合成一个 Frame 交给
// villagerRig.ts 画。节奏按编号错开，一群人站着不会一起动。要求减少动画、或者拉得太远一格不到
// 一个屏幕像素时，呼吸、眨眼、眼珠和头发都停，走路照常换步。

/** 呼吸一个来回的秒数：3～4 秒，每人不同 */
const BREATH_S = [3.1, 4]
/** 一个来回里头沉下去的那一段 */
const BREATH_DOWN = 0.42
/** 两次眨眼之间的秒数，偶尔连眨两下 */
const BLINK_GAP_S = [2.2, 6]
const DOUBLE_BLINK = 0.2
/** 眨一下：半闭 40 毫秒、闭上 90 毫秒、半闭 40 毫秒；连眨时中间睁开 80 毫秒 */
const BLINK = [40, 90, 40]
const BLINK_PAUSE = 80
/** 转身时头先转过去，身子晚这么久跟上（毫秒） */
const TURN_MS = 120
/** 起步时头往前探一格的时长、停下时头发多晃一下的时长 */
const LEAN_MS = 120
const SETTLE_MS = 260
/** 随便看看：眼珠停在一边的秒数 */
const GLANCE_S = [1.5, 4.5]

/** 八帧走路：着地、下沉、过渡、腾起，左右脚各一遍。身子按 0、+1、0、−1 起伏（往下为正）；
 *  头比身子晚一拍，垂下来的头发再晚一拍，只往下晚：头往上晚会和身子脱开一道缝。侧面手臂前后摆 */
const BOBS = [0, 1, 0, -1, 0, 1, 0, -1]
export function walk8(view: View, p: number) {
  const bob = BOBS[p % 8]
  const head = Math.max(bob, BOBS[(p + 7) % 8])
  const hair = Math.max(head, BOBS[(p + 6) % 8])
  const first = p % 8 < 4
  let stance: Stance
  if (view !== 'side') {
    // 正面背面：前半步左脚在前，后半步换右脚
    const a = first ? 8 : 11,
      b = first ? 11 : 8
    const legs: Stance['legs'][] = [
      [
        [a, 26, 2],
        [b, 26, 2],
      ],
      [
        [a, 27, 1],
        [b, 27, 1],
      ],
      [
        [a, 26, 2],
        [b, 25, 2],
      ],
      [
        [a, 25, 3],
        [b, 25, 1],
      ],
    ]
    stance = { legs: legs[p % 4], arm: 0 }
  } else {
    // 侧面：两腿前后分开着地，下沉时膝盖弯、脚掌放平，过渡时并拢，腾起时后脚只有脚尖点地
    const sides: Stance[] = [
      {
        legs: [
          [12, 26, 2],
          [8, 26, 2],
        ],
        arm: 0,
      },
      {
        legs: [
          [12, 27, 1],
          [9, 27, 1],
        ],
        toes: [
          [14, 27],
          [8, 27],
        ],
        arm: 0,
      },
      {
        legs: [
          [11, 26, 2],
          [9, 26, 1],
        ],
        arm: 0,
      },
      {
        legs: [
          [11, 25, 3],
          [8, 25, 2],
        ],
        toes: [[7, 26]],
        arm: 0,
      },
    ]
    stance = { ...sides[p % 4], arm: p % 4 === 2 ? 0 : first ? 1 : 2 }
  }
  return { stance, bodyDy: bob, headDy: head, bounce: hair - head }
}

const STAND: Record<View, Stance> = {
  down: {
    legs: [
      [8, 26, 2],
      [11, 26, 2],
    ],
    arm: 0,
  },
  up: {
    legs: [
      [8, 26, 2],
      [11, 26, 2],
    ],
    arm: 0,
  },
  side: {
    legs: [
      [10, 26, 2],
      [11, 26, 2],
    ],
    arm: 0,
  },
}

const VIEW: Record<Direction, [View, boolean]> = {
  down: ['down', false],
  up: ['up', false],
  right: ['side', false],
  left: ['side', true],
}
/** 掉头（左右、前后对调）时头先转到中间那个朝向 */
const MIDWAY: Partial<Record<`${Direction}${Direction}`, Direction>> = {
  leftright: 'down',
  rightleft: 'down',
  downup: 'right',
  updown: 'right',
}

/** 这一帧的外部条件：朝向、走没走、走了多远，能不能动小动作，风，看的方向（画面坐标，右、下为正） */
export interface Moment {
  now: number
  dir: Direction
  moving: boolean
  /** 走过的距离按步长折算的帧数：八帧走路按它换步 */
  stride: number
  /** 可以做呼吸、眨眼、眼珠、头发这些小动作 */
  lively: boolean
  /** 最软的头发此刻往画面右边摆几格（小数，负数往左） */
  wind: number
  /** 在看的方向；没有就随便看看 */
  look?: [number, number]
  /** 天上有东西可看（晴夜的星星、飘下来的雪）：随便看看时偶尔抬头，眼里多一格高光 */
  sky?: boolean
}

const between = (seed: number, [a, b]: number[]) => a + ((seed % 1000) / 1000) * (b - a)

/** 一个人的表演节奏 */
export class Acting {
  private readonly breathMs: number
  private readonly breathPhase: number
  private seed: number
  private nextBlink: number
  private blinkAt = -1
  private double = false
  private glance: { gaze: -1 | 0 | 1; up: boolean; until: number } = {
    gaze: 0,
    up: false,
    until: 0,
  }
  private dir: Direction | null = null
  private turn: { from: Direction; at: number } | null = null
  private moving = false
  private startAt = -1e9
  private stopAt = -1e9

  constructor(id: string) {
    this.seed = hashString(id)
    this.breathMs = between(this.seed, BREATH_S) * 1000
    this.breathPhase = (this.seed >>> 10) % this.breathMs
    this.nextBlink = performance.now() + between(this.seed >>> 4, BLINK_GAP_S) * 1000
  }

  private random() {
    this.seed = (Math.imul(this.seed, 1103515245) + 12345) >>> 0
    return (this.seed >>> 8) / 0x1000000
  }

  /** 朝向变了（转身）、起步、停下：记下时刻，之后几帧按它过渡 */
  private track(m: Moment) {
    if (this.dir && m.dir !== this.dir) this.turn = { from: this.dir, at: m.now }
    this.dir = m.dir
    if (m.moving && !this.moving) this.startAt = m.now
    if (!m.moving && this.moving) this.stopAt = m.now
    this.moving = m.moving
  }

  private blink(now: number): Eyes {
    if (this.blinkAt < 0 && now >= this.nextBlink) {
      this.blinkAt = now
      this.double = this.random() < DOUBLE_BLINK
    }
    if (this.blinkAt < 0) return 'open'
    const once = BLINK[0] + BLINK[1] + BLINK[2]
    let k = now - this.blinkAt
    if (this.double && k >= once) {
      if (k < once + BLINK_PAUSE) return 'open'
      k -= once + BLINK_PAUSE
    }
    if (k >= once) {
      this.blinkAt = -1
      this.nextBlink =
        now + (BLINK_GAP_S[0] + this.random() * (BLINK_GAP_S[1] - BLINK_GAP_S[0])) * 1000
      return 'open'
    }
    return k < BLINK[0] || k >= BLINK[0] + BLINK[1] ? 'half' : 'closed'
  }

  /** 眼珠往画面哪边挪：有看的东西就看它，没有就隔一阵随便看看 */
  private gaze(m: Moment): -1 | 0 | 1 {
    if (m.look) {
      const [sx, sy] = m.look
      // 正面朝着镜头：目标偏到一边（偏离正下方超过约 15°）就往那边看
      return Math.abs(sx) > Math.abs(sy) * 0.27 ? (sx > 0 ? 1 : -1) : 0
    }
    if (m.now >= this.glance.until) {
      const r = this.random()
      const up = !!m.sky && this.random() < 0.35
      this.glance = {
        gaze: up || r < 0.5 ? 0 : r < 0.75 ? -1 : 1,
        up,
        until: m.now + (GLANCE_S[0] + this.random() * (GLANCE_S[1] - GLANCE_S[0])) * 1000,
      }
    }
    return this.glance.gaze
  }

  frame(m: Moment): Frame {
    this.track(m)
    const [view, flip] = VIEW[m.dir]
    const forward = view === 'side' ? (flip ? -1 : 1) : 0
    let stance = STAND[view],
      bodyDy = 0,
      headDy = 0,
      headDx = 0,
      bounce = 0,
      trail = 0
    if (m.moving) {
      const w = walk8(view, Math.floor(m.stride) % 8)
      stance = w.stance
      bodyDy = w.bodyDy
      headDy = w.headDy
      bounce = w.bounce
      // 侧面走的时候头发往身后飘一格
      trail = -forward
      // 起步：头往前探一格（正面背面看不出前后，就低一下头）
      if (m.now - this.startAt < LEAN_MS) {
        if (forward) headDx = forward
        else headDy = Math.max(headDy, 1)
      }
    } else {
      // 停下：头发顺着惯性往前甩一下再回来
      const k = m.now - this.stopAt
      if (k < SETTLE_MS) {
        const swing = k < SETTLE_MS / 2 ? 1 : -1
        if (forward) trail = swing * forward
        else bounce = swing > 0 ? 1 : 0
      }
      if (m.lively && (m.now + this.breathPhase) % this.breathMs < this.breathMs * BREATH_DOWN)
        headDy = 1
    }
    // 转身：头先转，身子按原来的朝向再画一会儿
    let bodyView = view,
      bodyFlip = flip,
      turn: HeadTurn | undefined
    if (this.turn && m.now - this.turn.at < TURN_MS) {
      const [fromView, fromFlip] = VIEW[this.turn.from]
      const mid = MIDWAY[`${this.turn.from}${m.dir}`]
      const [headView, headFlip] = mid ? VIEW[mid] : [view, flip]
      bodyView = fromView
      bodyFlip = fromFlip
      stance = m.moving ? walk8(fromView, Math.floor(m.stride) % 8).stance : STAND[fromView]
      turn = { view: headView, mirror: headFlip !== fromFlip }
    } else this.turn = null
    const wind = m.lively ? m.wind : 0
    const sway = Math.max(-3, Math.min(3, Math.round(wind + trail)))
    const blink = m.lively ? this.blink(m.now) : 'open'
    return {
      view: bodyView,
      flip: bodyFlip,
      turn,
      stance,
      bodyDy,
      headDy,
      headDx,
      sway,
      bounce,
      gaze: m.lively && view === 'down' && !turn ? this.gaze(m) : 0,
      eyes: m.lively && blink === 'open' && !m.look && m.sky && this.glance.up ? 'bright' : blink,
    }
  }
}
