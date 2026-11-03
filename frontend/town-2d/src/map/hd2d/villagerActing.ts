import { hashString } from '../pixel/noise'
import { OX, OY, type Direction, type HeadTurn, type Stance, type View } from './villagerSprite'
import {
  LIE_X,
  LIE_Y,
  PAD_TOP,
  PAD_X,
  RIG_H,
  RIG_W,
  type Cells,
  type Eyes,
  type Frame,
  type Mouth,
  type Tint,
} from './villagerRig'
import { BEAT_MS, lantern, posed, scarf, umbrella, type PoseKind, type Posed } from './villagerPose'
import { SIGNS, signMotion, type Shown } from './villagerSigns'
import type { Quirk } from './villagerCues'

// 村民此刻在演什么：呼吸、眨眼、看哪儿、走到哪一步、起步停步和转身，做事的姿势，说话的口型和比划，
// 听人说话点头，脸上的表情，冒出来的热气、火星和「Z」，每帧合成一个 Frame 交给 villagerRig.ts 画。
// 节奏按编号错开，一群人站着不会一起动。要求减少动画、或者拉得太远一格不到一个屏幕像素时，呼吸、眨眼、
// 眼珠、头发、手上的动作和冒出来的东西都停，姿势和表情留静止的一帧，走路照常换步。

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
/** 说话：一个字张嘴一次，标点处停一下；一句最多演这么久（和气泡留的时间差不多） */
const SYLLABLE_MS = 135
const PAUSE_MS = 240
const TALK_MAX_MS = 6000
const PAUSES = /[，。！？、；：…,.!?;:～~\s]/
/** 听的人在别人说到一半时点一下头 */
const NOD_MS = 220
/** 犯困的人隔一阵打个哈欠 */
const YAWN_EVERY_MS = 7000
const YAWN_MS = 1400

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

/** 有据可查的心情：平常、高兴、惊讶、眼睛发亮、犯困、难受、低头 */
export type Mood = 'normal' | 'happy' | 'surprised' | 'bright' | 'sleepy' | 'pained' | 'down'

/** 这一帧的外部条件：朝向、走没走、走了多远，能不能动小动作，风，看的方向（画面坐标，右、下为正），
 *  站着时的姿势，心情，在说的话、在听的话 */
export interface Moment {
  now: number
  dir: Direction
  moving: boolean
  /** 走过的距离按步长折算的帧数：八帧走路按它换步 */
  stride: number
  /** 可以做呼吸、眨眼、眼珠、头发、手上的动作这些小动作 */
  lively: boolean
  /** 最软的头发此刻往画面右边摆几格（小数，负数往左） */
  wind: number
  /** 在看的方向；没有就随便看看 */
  look?: [number, number]
  /** 天上有东西可看（晴夜的星星、飘下来的雪）：随便看看时偶尔抬头，眼里多一格高光 */
  sky?: boolean
  /** 站着时在做的事：道具动作、身体状况的姿势 */
  pose?: PoseKind
  mood?: Mood
  /** 在说话：开口的时刻和这句台词；liked 是说的正是自己喜欢的话题 */
  talk?: { at: number; text: string; liked: boolean }
  /** 在听别人说：那句开口的时刻、要说多久；liked 是说到了这个人喜欢的话题 */
  hear?: { at: number; ms: number; liked: boolean }
  /** 身体：受伤、生病、中毒的轻重（0 没有，1～3），饿了，倒下了，死了 */
  body?: Body
  /** 天气落在这个人身上：打伞、没伞抱头、淋湿和积雪的档、围巾、冷得呵白气、提灯笼 */
  wear?: Wear
  /** 头顶的符号 */
  sign?: Shown
  /** 刚复活的时刻：先坐起来再站起来，身边往上飘羽毛 */
  revived?: number
  /** 站着没事做时的个性小动作和开始的时刻 */
  quirk?: { kind: Quirk; at: number }
  /** 拉近到一格贴图不少于 3 个屏幕像素：眨眼多一帧（眼睛的样子不变） */
  close?: boolean
  /** 悬停（白边）、选中（金边） */
  pick?: 'hover' | 'pick'
}

/** 按姿势演的小动作 */
const POSE_QUIRKS = new Set<Quirk>([
  'read',
  'drink',
  'knit',
  'write',
  'tend',
  'busy',
  'craft',
  'cook',
  'gaze',
  'medic',
])
/** 招手：右手举到头边一摇一摇 */
const WAVE = (a: boolean): Cells =>
  [
    [a ? 22 : 21, 9, 's'],
    [a ? 21 : 20, 10, 'K'],
    [21, 10, 's'],
    ...[11, 12, 13, 14, 15, 16].flatMap((y) => [[20, y, 'K'] as const, [21, y, 't'] as const]),
  ] as Cells

export interface Body {
  injury: number
  illness: number
  poison: number
  hungry: boolean
  down: boolean
  dead: boolean
}

export interface Wear {
  umbrella: boolean
  cover: boolean
  wet: 0 | 1 | 2
  snow: 0 | 1 | 2 | 3
  scarf: boolean
  breath: boolean
  lantern: boolean
}

/** 一句话要说多久（毫秒）：一个字一下，标点停一下，最多 TALK_MAX_MS */
export function talkMs(text: string) {
  let t = 0
  for (const ch of text) t += PAUSES.test(ch) ? PAUSE_MS : SYLLABLE_MS
  return Math.min(t, TALK_MAX_MS)
}

/** 说到第 k 毫秒时嘴的样子：每个字前半张开（每三个字有一个圆口），后半合上；标点处闭嘴。说完返回 null */
function mouthAt(text: string, k: number): Mouth | null {
  if (k >= TALK_MAX_MS) return null
  let t = 0,
    i = 0
  for (const ch of text) {
    const pause = PAUSES.test(ch)
    const len = pause ? PAUSE_MS : SYLLABLE_MS
    if (k < t + len) return pause || k - t > len * 0.55 ? 'none' : i % 3 === 2 ? 'o' : 'open'
    t += len
    i++
  }
  return null
}

/** 小东西的形状：Z、音符 */
const GLYPHS: Record<string, readonly string[]> = {
  z: ['WWW', '.W.', 'WWW'],
  note: ['.YY', '.Y.', 'YY.', 'YY.'],
}
const glyph = (name: string, x: number, y: number): Cells =>
  GLYPHS[name].flatMap((row, j) =>
    [...row].flatMap((c, i) => (c === '.' ? [] : [[x + i, y + j, c] as const]))
  )

type Fx = NonNullable<Posed['fx']> | 'cough' | 'bubbles' | 'breath' | 'feathers'
/** 小东西按多少毫秒一格地动 */
const PARTICLE_STEP_MS = 80
/** 各种小东西隔多久冒一次、一次飘多久（毫秒） */
const FX_TIMING: Record<Fx, [number, number]> = {
  steam: [420, 1200],
  sparks: [380, 300],
  drops: [420, 1200],
  zzz: [1600, 2400],
  notes: [1100, 1800],
  cough: [5200, 450],
  bubbles: [1400, 1300],
  breath: [2600, 1000],
  feathers: [240, 1600],
}

/** 冒出来的小东西在第 now 毫秒的位置：按时间算，不存状态。(ax, ay) 是冒出来的地方（贴图上的画面坐标），
 *  face 是脸朝画面哪边（咳嗽、呵气往那边出） */
function particles(fx: Fx, at: number, ax: number, ay: number, seed: number, face = 0): Cells {
  // 按 80 毫秒一格走：像素小点一秒动十来下就够，贴图也少重画
  const now = at - (at % PARTICLE_STEP_MS)
  const out: (readonly [number, number, string])[] = []
  const [every, life] = FX_TIMING[fx]
  for (let n = Math.floor((now - life) / every) + 1; n * every <= now; n++) {
    const k = (now - n * every) / life
    if (k < 0 || k >= 1) continue
    const r = ((n * 2654435761 + seed) >>> 0) / 0x100000000
    switch (fx) {
      case 'steam': {
        // 热气：一缕往上飘，左右晃一格，越往上越稀
        const y = Math.round(ay - k * 7)
        const x = ax + Math.round(Math.sin(k * 6 + r * 6) * 1.2) + (r < 0.5 ? -1 : 1)
        if (k < 0.75 || (x + y) % 2) out.push([x, y, 'W'])
        break
      }
      case 'sparks':
        // 火星：锤子落下时往两边溅三颗
        for (let j = 0; j < 3; j++) {
          const dx = (j - 1) * 2 + (r < 0.5 ? 0 : 1)
          out.push([
            ax + Math.round(dx * k * 2),
            Math.round(ay - k * 3 + k * k * 4),
            j === 1 ? 'Y' : 'k',
          ])
        }
        break
      case 'drops':
        out.push([ax + Math.round((r - 0.5) * 4), Math.round(ay + k * 4), 'l'])
        break
      case 'zzz':
        out.push(...glyph('z', ax + Math.round(k * 5), Math.round(ay - k * 9)))
        break
      case 'notes':
        out.push(...glyph('note', ax + Math.round(k * 4 + r * 2), Math.round(ay - k * 8)))
        break
      case 'cough':
        // 咳嗽：嘴边喷出两小团白气
        out.push([ax + Math.round(face * (1 + k * 3)), Math.round(ay - k), 'W'])
        if (k > 0.3) out.push([ax + Math.round(face * (2 + k * 3)), Math.round(ay - 1 - k), 'W'])
        break
      case 'bubbles': {
        // 中毒：头顶冒紫色小泡
        const x = ax + Math.round((r - 0.5) * 8),
          y = Math.round(ay - k * 7)
        if (k < 0.7 || (x + y) % 2) out.push([x, y, 'V'])
        break
      }
      case 'breath': {
        // 冷：嘴边一口口白气，往前上方散开
        const x = ax + Math.round(face * (1 + k * 2)),
          y = Math.round(ay - k * 3)
        if (k < 0.6 || (x + y) % 2) out.push([x, y, '~'])
        if (k > 0.25 && k < 0.8) out.push([x + (face || 1), y - 1, '~'])
        break
      }
      case 'feathers': {
        // 复活：羽毛从脚边往上飘，左右摇
        const x = ax + Math.round((r - 0.5) * 18 + Math.sin(k * 7 + r * 9) * 1.5),
          y = Math.round(ay - k * 22)
        out.push([x, y, 'W'], [x + 1, y, 'W'])
        break
      }
    }
  }
  // 整格：落在半格上的点画不出来
  return out.map(([x, y, c]) => [Math.round(x), Math.round(y), c] as const)
}

const between = (seed: number, [a, b]: number[]) => a + ((seed % 1000) / 1000) * (b - a)

/** 一个人的表演节奏 */
export class Acting {
  private readonly breathMs: number
  private readonly breathPhase: number
  private readonly id: number
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
    this.seed = this.id = hashString(id)
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

  private blink(now: number, close = false): Eyes {
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
    // 拉近时多一帧：半闭之后先耷拉一下再闭上
    if (close && k >= BLINK[0] / 2 && k < BLINK[0]) return 'sleepy'
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
    const body = m.body,
      wear = m.wear
    let [view, flip] = VIEW[m.dir]
    // 身体状况的姿势：死了倒在地上，倒下了坐在地上，刚复活先坐起来；饿了站着捂肚子，没伞淋雨抱头
    const rising = m.revived !== undefined && m.now - m.revived < 450
    // 小动作：站着没事做时才演
    const quirk = !m.moving && !body?.dead && !body?.down && m.lively ? m.quirk : undefined
    const qk = quirk ? m.now - quirk.at : 0
    // 提着灯笼、打着伞的人手里没空：不演要用手的那些
    const handsBusy = wear?.lantern || wear?.umbrella
    const quirkPose: PoseKind | undefined = quirk
      ? POSE_QUIRKS.has(quirk.kind) && !handsBusy
        ? (quirk.kind as PoseKind)
        : quirk.kind === 'pickup' && qk < 900
          ? 'sitGround'
          : undefined
      : undefined
    let pose: PoseKind | undefined = body?.dead
      ? 'lie'
      : body?.down || rising
        ? 'sitGround'
        : !m.moving
          ? (m.pose ??
            (wear?.cover ? 'cover' : body?.hungry && !m.talk && !m.hear ? 'belly' : quirkPose))
          : undefined
    const still = body?.dead
    const lively = m.lively && !still
    // 做事的姿势按正面画：在用道具的人站在道具跟前、面朝镜头（说着话的照旧面朝对方）
    if (pose && !m.talk && !m.hear) [view, flip] = ['down', false]
    const forward = view === 'side' ? (flip ? -1 : 1) : 0
    let stance = STAND[view],
      bodyDy = 0,
      headDy = 0,
      headDx = 0,
      bounce = 0,
      trail = 0
    let posedNow: Posed | undefined
    if (m.moving && !pose) {
      const phase = Math.floor(m.stride) % 8
      const w = walk8(view, phase)
      stance = w.stance
      bodyDy = w.bodyDy
      headDy = w.headDy
      bounce = w.bounce
      // 受伤一瘸一拐：伤腿那半步身子多沉一格
      if (body?.injury && phase >= 4) {
        bodyDy += 1
        headDy += 1
      }
      // 侧面走的时候头发往身后飘一格
      trail = -forward
      // 起步：头往前探一格（正面背面看不出前后，就低一下头）
      if (m.now - this.startAt < LEAN_MS) {
        if (forward) headDx = forward
        else headDy = Math.max(headDy, bodyDy + 1)
      }
    } else {
      // 停下：头发顺着惯性往前甩一下再回来
      const k = m.now - this.stopAt
      if (k < SETTLE_MS) {
        const swing = k < SETTLE_MS / 2 ? 1 : -1
        if (forward) trail = swing * forward
        else bounce = swing > 0 ? 1 : 0
      }
      if (pose) {
        // 手上的动作按各自的拍子换；减少动画时停在第一拍
        const beat = BEAT_MS[pose]
        const phase = beat && lively ? Math.floor((m.now + (this.id % 997)) / beat) : 0
        posedNow = posed(pose, phase)
        stance = posedNow.stance
        bodyDy = posedNow.bodyDy
        headDy = posedNow.headDy
      }
      if (lively && (m.now + this.breathPhase) % this.breathMs < this.breathMs * BREATH_DOWN)
        headDy = Math.max(headDy, bodyDy + 1)
    }
    // 小动作：跟着拍子点头、蹦一下
    if (quirk?.kind === 'beat' && Math.floor(qk / 320) % 2) headDy = Math.max(headDy, bodyDy + 1)
    if (quirk?.kind === 'hop' && qk % 450 < 140) {
      stance = { ...stance, legs: stance.legs.map(([x, top, n]) => [x, top - 2, n] as const) }
      bodyDy -= 2
      headDy -= 2
    }
    // 生病：隔一阵咳一下，头一低
    const coughing =
      !!body?.illness &&
      lively &&
      (m.now + (this.id % 5200)) % FX_TIMING.cough[0] < FX_TIMING.cough[1]
    if (coughing) headDy = Math.max(headDy, bodyDy + 1)
    // 转身：头先转，身子按原来的朝向再画一会儿
    let bodyView = view,
      bodyFlip = flip,
      turn: HeadTurn | undefined
    if (!posedNow && this.turn && m.now - this.turn.at < TURN_MS) {
      const [fromView, fromFlip] = VIEW[this.turn.from]
      const mid = MIDWAY[`${this.turn.from}${m.dir}`]
      const [headView, headFlip] = mid ? VIEW[mid] : [view, flip]
      bodyView = fromView
      bodyFlip = fromFlip
      stance = m.moving ? walk8(fromView, Math.floor(m.stride) % 8).stance : STAND[fromView]
      turn = { view: headView, mirror: headFlip !== fromFlip }
    } else if (!this.turn || m.now - this.turn.at >= TURN_MS) this.turn = null
    // 说话：嘴按字一张一合，说到一半抬手比划；听的人在对方说到一半时点一下头
    let mouth: Mouth = posedNow?.mouth ?? 'none'
    const front: Cells[] = []
    const names: string[] = []
    if (posedNow?.front || posedNow?.back) {
      front.push(posedNow.front ?? [])
      names.push(`${pose}${posedNow.front?.[0]?.join('') ?? ''}${posedNow.front?.length ?? 0}`)
    }
    if (m.talk && !still) {
      const k = m.now - m.talk.at
      const open = mouthAt(m.talk.text, k)
      if (open !== null) {
        mouth = lively ? open : 'dot'
        const len = talkMs(m.talk.text)
        if (lively && len > 1500 && k > len * 0.35 && k < len * 0.65 && !posedNow) {
          if (bodyView === 'side') stance = { ...stance, arm: 1 }
          else if (!wear?.umbrella) {
            front.push(GESTURE)
            names.push('gesture')
          }
        }
      }
    }
    if (m.hear && lively && !m.moving) {
      const k = m.now - m.hear.at - m.hear.ms * 0.5
      if (k >= 0 && k < NOD_MS) headDy = Math.max(headDy, bodyDy + 1)
    }
    // 穿戴：围巾、灯笼、伞（做事、倒下、死了的人不打伞不提灯）
    const wearView = bodyView
    const free = !posedNow || pose === 'cover'
    if (wear?.scarf && !posedNow?.lie) {
      front.push(scarf(wearView))
      names.push('scarf')
    }
    if (wear?.lantern && free && pose !== 'cover') {
      front.push(lantern(wearView))
      names.push('lantern')
    }
    if (wear?.umbrella && free && pose !== 'cover') {
      front.push(umbrella(wearView))
      names.push('umbrella')
      stance = { ...stance, arm: null }
    }
    if (wear?.cover && m.moving) {
      // 没伞的人淋着雨小跑：两手抱头
      front.push(posed('cover', 0).front ?? [])
      names.push('cover')
      stance = { ...stance, arm: null }
    }
    if (quirk?.kind === 'wave' && bodyView === 'down' && !handsBusy) {
      front.push(WAVE(Math.floor(qk / 250) % 2 === 1))
      names.push(`wave${Math.floor(qk / 250) % 2}`)
    }
    const props: Frame['props'] =
      names.length || posedNow?.back
        ? { key: names.join(','), back: posedNow?.back, front: front.flat() }
        : undefined
    // 低头：心情低落时头也低下一格（眼睛跟着头往下挪一格，见 villagerRig.ts）
    if ((m.mood ?? 'normal') === 'down' && !m.moving) headDy = Math.max(headDy, bodyDy + 1)
    const quirkMood: Mood | undefined =
      quirk?.kind === 'smile' || quirk?.kind === 'wave'
        ? 'happy'
        : quirk?.kind === 'yawn'
          ? 'sleepy'
          : quirk?.kind === 'stargaze'
            ? 'bright'
            : undefined
    const face = this.face(
      quirkMood && (m.mood ?? 'normal') === 'normal' ? { ...m, mood: quirkMood } : m,
      posedNow,
      mouth,
      lively,
      still
    )
    const wind = lively ? m.wind : 0
    const sway = Math.max(-3, Math.min(3, Math.round(wind + trail)))
    const sparks: (readonly [number, number, string])[] = []
    const headTop = PAD_TOP + OY + headDy
    // 嘴在画面上的位置：正面在脸中间，侧面在脸的前沿（呵气、咳嗽从这里出）
    const facing = bodyView === 'side' ? (bodyFlip ? -1 : 1) : 0
    const mouthX = facing ? Math.round(RIG_W / 2 + facing * 9) : Math.round(RIG_W / 2 - 0.5)
    const mouthY = headTop + 15
    if (lively) {
      if (posedNow?.fx) {
        // 躺着的人从头顶冒「Z」；别的从姿势给的地方冒
        const [fx, fy] = posedNow.fxAt ?? [10, 18]
        const [ax, ay] = posedNow.lie
          ? [LIE_X + 14, LIE_Y + 1]
          : [fx + PAD_X + OX, fy + PAD_TOP + OY + bodyDy]
        sparks.push(...particles(posedNow.fx, m.now, ax, ay, this.id))
      }
      if (quirk?.kind === 'beat')
        sparks.push(...particles('notes', qk, PAD_X + OX + 16, headTop + 6, this.id))
      if (body?.illness && bodyView !== 'up' && !posedNow?.lie)
        sparks.push(
          ...particles('cough', m.now + (this.id % 5200), mouthX, mouthY, this.id, facing || 1)
        )
      if (body?.poison && !posedNow?.lie)
        sparks.push(...particles('bubbles', m.now, RIG_W >> 1, headTop - 1, this.id))
      if (wear?.breath && bodyView !== 'up' && !posedNow?.lie)
        sparks.push(
          ...particles('breath', m.now + (this.id % 2600), mouthX, mouthY, this.id, facing || 1)
        )
      if (m.revived !== undefined && m.now - m.revived < 1600)
        sparks.push(...particles('feathers', m.now - m.revived, RIG_W >> 1, RIG_H - 2, this.id))
    }
    // 头顶的符号挂在头的右上角：只高出头顶两格，名字在它上面
    let sign: Frame['sign']
    if (m.sign && !still && !posedNow?.lie) {
      const { dy, alpha } = signMotion(m.sign, m.now, m.lively)
      const width = SIGNS[m.sign.sign][0].length
      sign = { name: m.sign.sign, x: Math.min(RIG_W - width, 27), y: headTop + 5 + dy, alpha }
    }
    const tint: Tint | undefined = body?.dead
      ? 'dead'
      : body?.down
        ? 'incap'
        : body?.poison
          ? 'poison'
          : body?.illness
            ? body.illness >= 3
              ? 'fever'
              : 'pale'
            : undefined
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
      gaze:
        lively && view === 'down' && !turn && !posedNow?.eyes
          ? quirk?.kind === 'scan'
            ? Math.floor(qk / 520) % 2
              ? 1
              : -1
            : this.gaze(m)
          : 0,
      eyes: face.eyes,
      mouth: face.mouth,
      blush: face.blush,
      props,
      lie: !!posedNow?.lie,
      sparks: sparks.length ? sparks : undefined,
      tint,
      wet: wear?.wet ?? 0,
      snow: wear?.snow ?? 0,
      bandage: !!body?.injury && !body.dead,
      sign,
      outline: m.pick,
    }
  }

  /** 脸：心情给眼神、嘴和腮红，没有心情时按手上的事（看书往下看），在说话时嘴按口型；
   *  睁着的眼睛照常眨，抬头看天时眼里一格高光 */
  private face(
    m: Moment,
    posedNow: Posed | undefined,
    talking: Mouth,
    lively: boolean,
    still?: boolean
  ) {
    let eyes: Eyes = 'open',
      mouth: Mouth = 'none',
      blush: 0 | 1 | 2 = 0
    // 死了闭着眼，不眨不动
    if (still) return { eyes: 'closed' as Eyes, mouth, blush }
    switch (m.mood ?? 'normal') {
      case 'happy':
        eyes = 'happy'
        mouth = 'smile'
        blush = 1
        break
      case 'surprised':
        eyes = 'wide'
        mouth = 'o'
        break
      case 'bright':
        eyes = 'bright'
        blush = 1
        break
      case 'sleepy': {
        eyes = 'sleepy'
        // 隔一阵打个哈欠：闭眼张大嘴
        const k = (m.now + (this.id % YAWN_EVERY_MS)) % YAWN_EVERY_MS
        if (lively && k < YAWN_MS) {
          eyes = 'closed'
          mouth = 'yawn'
        }
        break
      }
      case 'pained':
        eyes = 'pained'
        mouth = 'frown'
        break
      case 'down':
        eyes = 'down'
        break
      default:
        if (posedNow?.eyes) eyes = posedNow.eyes
        // 说到、听到喜欢的话题：眼睛发亮
        if (m.hear?.liked || m.talk?.liked) {
          eyes = 'bright'
          blush = 1
        }
    }
    if (talking !== 'none' || m.talk) mouth = talking
    if (lively && (eyes === 'open' || eyes === 'bright' || eyes === 'wide')) {
      const blink = this.blink(m.now, m.close)
      if (blink !== 'open') eyes = blink
      else if (eyes === 'open' && !m.look && m.sky && this.glance.up && !posedNow) eyes = 'bright'
    }
    return { eyes, mouth, blush }
  }
}

/** 说到一半抬手比划：正面右手抬到胸前 */
const GESTURE: Cells = [
  [15, 16, 's'],
  [15, 17, 'K'],
  [16, 17, 's'],
  [15, 18, 'K'],
  [16, 18, 't'],
]
