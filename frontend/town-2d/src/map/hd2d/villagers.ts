import * as THREE from 'three'
import { PIXEL } from '../grid'
import { hashString } from '../pixel/noise'
import { riseOf, type Tilt } from './layout'
import { pixelFilter, stand, standee } from './standee'
import { contactTexture } from './ao'
import { REFLECTION_SKIP } from './reflection'
import { VILLAGER_HALF, VILLAGER_HEIGHT, VILLAGER_SCALE, type Direction } from './villagerSprite'
import { RIG_H, RIG_W, VillagerRig, bayer, frameKey } from './villagerRig'
import { shadeVillager } from './villagerLight'
import { Acting, talkMs, type Mood, type Moment, type Wear } from './villagerActing'
import {
  SLOW_WALKERS,
  bodyOf,
  likes,
  moodOf,
  quirksOf,
  standingSigns,
  type Cue,
  type Quirk,
} from './villagerCues'
import { CYCLE, SIGN_RANK, type Badge, type Shown, type Sign } from './villagerSigns'
import { poseOf } from './villagerPose'

// 村民立牌：位置跟着名册走。名册每拍（100 毫秒）来一次，立牌比最新一份晚一到两拍，在相邻两份
// 之间匀速走过去：每份名册记作比上一份晚一拍，播放按真实时间走；每来一份按缓冲多少把播放稍微调快
// 或调慢，一份之内速度不变，名册早到晚到、主线程卡一下都不会让人忽快忽慢。
// 按这一段路的方向选朝向、按走过的距离换走路帧。每人一块小贴图，按此刻的姿势、呼吸、眨眼和
// 风现画（见 villagerRig.ts、villagerActing.ts），画面变了才重画、上传。
// 玩家正在操控的人不缓冲：位置由本地预测给出（见 ../avatarMotion.ts），每帧照着发出去的方向和步速走，
// 按下去马上就动，不比别人晚两拍，也不随名册早到晚到一顿一顿。

/** 走过多少地图单位换一帧（八帧走路，两步一个来回） */
const STRIDE = 1.6 * PIXEL
/** 一步多远：每一步在踩踏图上落一个脚印 */
const STEP = 4 * STRIDE
/** 相邻两份名册离得比这远就直接放过去（进出门、换地点），不走过场 */
const JUMP = 400
/** 服务端一拍（毫秒），名册按这个间隔来 */
const TICK_MS = 100
/** 刚来一份名册时立牌比它晚多久：两拍，下一份晚到一拍也还有路可走 */
const DELAY_MS = 200
/** 落后超过这么久（切到后台回来、断线重连）就直接跳到最新，不快放 */
const RESYNC_MS = 600
/** 追赶缓冲时最多快慢一成，看不出变速 */
const MAX_DRIFT = 0.1
/** 站着的人多久重新挑一次看谁（毫秒），各人错开 */
const LOOK_MS = 500
/** 这么近走过的人会被看一眼；玩家操控的人走得更远也看（地图单位） */
const LOOK_NEAR = 40 * PIXEL
const LOOK_AVATAR = 90 * PIXEL
/** 看人转身后至少这么久不再转（毫秒），不来回扭 */
const TURN_HOLD_MS = 1500

export interface VillagerPlacement {
  id: string
  /** 决定长相的编号：同一个头像模板永远长一个样 */
  look: string
  x: number
  y: number
  /** 为避开家具和墙而做的显示偏移，不进入名册位置与行走时间轴。 */
  offset?: [number, number]
  visible: boolean
  /** 玩家正在操控的人：不缓冲，按本地预测画（见 LiveMotion） */
  live?: boolean
  /** 站着时转身朝向这一点（被玩家邀请、正和玩家聊天的人朝向玩家，聊天的人朝向对方） */
  faceToward?: [number, number]
  /** 名册里和表演有关的那几项（见 villagerCues.ts） */
  cue?: Cue
}

/** 天气和时间落在人身上要用的：雨多大、在不在下雪、夜里亮灯的程度、冷不冷（呵白气、围围巾）、
 *  废土的正午（冒汗）、天好（散步哼歌），游戏分钟（按它算在外面待了多久） */
export interface Climate {
  rain: number
  snowing: boolean
  lit: number
  cold: boolean
  scarves: boolean
  hot: boolean
  fine: boolean
  minutes: number
}

/** 积雪、淋湿按在户外待的游戏分钟分档 */
const SNOW_MIN = [4, 15, 30]
const WET_MIN = [3, 12]
/** 一阵子的符号留多久（毫秒） */
const SIGN_MS = 2200
/** 站着没事做多久才演小动作、演多久、两段之间歇多久（毫秒） */
const QUIRK_AFTER_MS = 8000
const QUIRK_MS = [2600, 4200]
const QUIRK_REST_MS = [6000, 14000]
/** 复活的光柱：落下、停住、淡掉（毫秒），多高（地图单位） */
const BEAM_MS = [300, 1200, 1800]
const BEAM_H = VILLAGER_HEIGHT * 6

/** 玩家正在操控的人画在哪：本地预测（见 ../avatarMotion.ts），每帧问一次 */
export interface LiveMotion {
  /** 此刻的位置（地图单位）；还不知道时为空，先按名册画 */
  at(now: number): [number, number] | undefined
  /** 还在动（在走，或还在和服务端校正）：要每帧画 */
  active(): boolean
  /** 在走：走路帧要动 */
  walking(): boolean
}

/** 名册时间轴上的一个位置 */
interface Sample {
  t: number
  x: number
  y: number
}

interface Villager {
  id: string
  mesh: THREE.Mesh
  /** 脚下的像素暗斑 */
  contact: THREE.Mesh
  /** 这个人的贴图：像素就在 data 里，画完一帧标记上传 */
  map: THREE.DataTexture
  data: Uint8Array
  /** 法线和材质（见 villagerLight.ts），和颜色一起画、一起上传 */
  normalMap: THREE.DataTexture
  normals: Uint8Array
  rig: VillagerRig
  acting: Acting
  /** 上一帧的指纹：一样就不重画 */
  drawn: string
  look: string
  at: [number, number]
  /** 还没走完的几份名册位置，第一份在播放时刻之前（或就是最后一份） */
  path: Sample[]
  dir: Direction
  /** 最后一次行走的世界方向；转动镜头时静止的人也换到相应朝向帧。 */
  facing: [number, number]
  offset: [number, number]
  walked: number
  /** 走到这么远时落下一个脚印（踩踏图用），左右脚交替 */
  nextStep: number
  leftFoot: boolean
  moving: boolean
  /** 玩家正在操控的人：位置按 LiveMotion 画 */
  live?: boolean
  /** 站着时朝向的点 */
  faceToward?: [number, number]
  cue: Cue
  /** 在说的一句（开口的时刻）、在听的一句；一阵子的表情（刚聊完高兴、刚复活先惊后喜） */
  talk?: { at: number; text: string; liked: boolean }
  hear?: { at: number; ms: number; liked: boolean }
  react: { mood: Mood; until: number }[]
  /** 谁带伞、提灯笼、围围巾：按编号定，每次都是同一些人 */
  owns: { umbrella: boolean; lantern: boolean; scarf: boolean }
  /** 在户外淋雨、落雪的游戏分钟（进屋清零）：积雪和淋湿的档按它算 */
  rainMin: number
  snowMin: number
  /** 一阵子的符号（吓到、心、灯泡、怒）；过了就看一直在的状态 */
  sign?: Shown
  /** 刚复活的时刻和落下来的光柱 */
  revived?: number
  beam?: THREE.Mesh
  /** 伞面、符号高出头顶的地图单位：气泡按它躲开 */
  crown: number
  /** 上一帧在走：天好时刚出门散步，偶尔哼一句 */
  strolling: boolean
  /** 从什么时候起站着没事做；正在演的小动作；下一段最早什么时候 */
  idleSince: number
  quirk?: { kind: Quirk; at: number; until: number }
  nextQuirk: number
  /** 此刻在看的方向（画面坐标）和下次重挑的时刻；上次因为看人转身的时刻 */
  gazeAt?: [number, number]
  nextLook: number
  turnedAt: number
}

/** 脚下暗斑的大小（地图单位）：比人略宽，平放在地上 */
const CONTACT_W = VILLAGER_HALF * 2.4

export class Villagers {
  private readonly all = new Map<string, Villager>()
  /** 地图上一点要把人抬多高（走在桥上时是桥面的高度，见 pixel/bridges.ts），场景建好桥后填上 */
  lift: (x: number, y: number) => number = () => 0
  private readonly contactGeometry = new THREE.PlaneGeometry(CONTACT_W, CONTACT_W * 0.7).rotateX(
    -Math.PI / 2
  )
  private readonly contactMaterial = new THREE.MeshBasicMaterial({
    map: contactTexture(),
    color: '#000000',
    transparent: true,
    opacity: 0.42,
    depthWrite: false,
  })
  /** 同一个长相共用一份画法（缓存的笔画） */
  private readonly rigs = new Map<string, VillagerRig>()
  /** 一格贴图像素在屏幕上有几个设备像素：不到 1 个时小动作不做 */
  private texelPx = 2
  /** 要求减少动画 */
  private calm = false
  /** 风：立牌上最软的东西在 (x, z) 此刻往画面右边摆几格 */
  private sway: (x: number, z: number) => number = () => 0
  /** 天上有东西可看（晴夜的星星、飘下来的雪） */
  private sky = false
  /** 最新一份名册在时间轴上的时刻（毫秒），每来一份加一拍 */
  private latest = 0
  /** 播放到的时刻：立牌画的是这一刻的位置 */
  private play = -DELAY_MS
  /** 播放快慢：每来一份名册按缓冲调一次 */
  private rate = 1
  /** 上一次 step 的时刻 */
  private last = performance.now()
  /** 玩家正在操控的人的本地预测；没有在操控时为空 */
  private motion: LiveMotion | null = null
  setLiveMotion(motion: LiveMotion | null) {
    this.motion = motion
  }
  /** 玩法挂在头顶的常驻标记：村民编号 → 标记（大逃杀里拿着信号弹的人） */
  private badges: ReadonlyMap<string, Badge> = new Map()
  setBadges(badges: ReadonlyMap<string, Badge>) {
    this.badges = badges
  }

  /** prepare：每个新立牌的材质过一遍（接光照图） */
  constructor(
    private scene: THREE.Scene,
    private tilt: Tilt,
    private readonly prepare?: (material: THREE.Material) => void
  ) {
    scene.add(this.spot)
  }

  /** 俯角变了：所有人重新立好 */
  setTilt(tilt: Tilt) {
    this.tilt = tilt
    for (const v of this.all.values()) {
      this.moveTo(v, ...v.at)
      this.face(v)
    }
  }

  /** 按名册同步；fresh 表示这是新来的一份名册，位置记进时间轴，其余（换选中、开合屋顶）只改最后一份。
   *  有人进出、显隐、变色或瞬移时返回 true（走过去的由 step 报告） */
  sync(placements: VillagerPlacement[], fresh = false) {
    if (fresh) {
      this.latest += TICK_MS
      const buffered = this.latest - this.play
      if (buffered > RESYNC_MS) {
        this.play = this.latest - DELAY_MS
        this.rate = 1
      } else this.rate = 1 + Math.max(-MAX_DRIFT, Math.min(MAX_DRIFT, (buffered - DELAY_MS) / 1000))
    }
    const seen = new Set<string>()
    let changed = false
    for (const p of placements) {
      seen.add(p.id)
      let v = this.all.get(p.id)
      if (v && v.look !== p.look) {
        this.remove(p.id)
        v = undefined
      }
      if (!v) {
        v = this.create(p)
        changed = true
      }
      const offset = p.offset ?? [0, 0]
      if (offset[0] !== v.offset[0] || offset[1] !== v.offset[1]) {
        v.offset = [offset[0], offset[1]]
        this.moveTo(v, ...v.at)
        changed = true
      }
      if (v.mesh.visible !== p.visible) changed = true
      v.mesh.visible = v.contact.visible = p.visible
      if (v.faceToward?.[0] !== p.faceToward?.[0] || v.faceToward?.[1] !== p.faceToward?.[1])
        changed = true
      v.faceToward = p.faceToward
      this.cue(v, p.cue ?? {})
      if (p.live) {
        // 时间轴上只留名册的最新位置：名字、心声泡按它和立牌的差跟着立牌（见 lag）
        v.live = true
        v.path = [{ t: this.latest, x: p.x, y: p.y }]
        continue
      }
      // 不再操控（交还、退出）：从现在的位置接回名册的时间轴
      if (v.live) {
        v.live = undefined
        v.path = [{ t: this.latest, x: v.at[0], y: v.at[1] }]
      }
      const end = v.path[v.path.length - 1]
      if (end.x === p.x && end.y === p.y) continue
      if (!p.visible || Math.hypot(p.x - end.x, p.y - end.y) > JUMP) {
        // 看不见的人、进出门换地点的人直接放到新位置
        changed = true
        v.path = [{ t: this.latest, x: p.x, y: p.y }]
        this.moveTo(v, p.x, p.y)
      } else if (fresh) {
        // 站着不动时不记重复的点；刚起步时补上上一拍还站在原地，免得从很久以前的点一下滑过来
        if (end.t < this.latest - TICK_MS) v.path.push({ ...end, t: this.latest - TICK_MS })
        v.path.push({ t: this.latest, x: p.x, y: p.y })
      } else v.path[v.path.length - 1] = { ...end, x: p.x, y: p.y }
    }
    for (const id of [...this.all.keys()])
      if (!seen.has(id)) {
        this.remove(id)
        changed = true
      }
    // 同一场聊天里，有人开口：别的人在听，说到喜欢的话题眼睛发亮
    const chats = new Set([...this.all.values()].map((v) => v.cue.chat))
    for (const id of this.heard.keys()) if (!chats.has(id)) this.heard.delete(id)
    for (const v of this.all.values()) {
      if (!v.talk || !v.cue.chat || this.heard.get(v.cue.chat) === v.talk) continue
      this.heard.set(v.cue.chat, v.talk)
      for (const o of this.all.values())
        if (o !== v && o.cue.chat === v.cue.chat)
          o.hear = {
            at: v.talk.at,
            ms: talkMs(v.talk.text),
            liked: likes(o.cue.persona, v.talk.text),
          }
    }
    return changed
  }

  /** 每场聊天最近开口的那一句：一句只分给听的人一次 */
  private readonly heard = new Map<string, Villager['talk']>()

  /** 换上新的线索：新说出口的一句开始动嘴；聊完了高兴一阵、冒个心；被治好冒心，复活、神力先惊讶再高兴，
   *  天上落下光柱；邀请被拒冒怒，牵手、依偎、拥抱冒心，有了新目标冒灯泡；身边有人倒下，旁边的人吓一跳 */
  private cue(v: Villager, cue: Cue) {
    const before = v.cue
    v.cue = cue
    const now = performance.now()
    if (cue.speech && cue.speech.key !== before.speech?.key)
      v.talk = { at: now, text: cue.speech.text, liked: likes(cue.persona, cue.speech.text) }
    if (before.chat && !cue.chat) {
      v.react = [{ mood: 'happy', until: now + 2500 }]
      this.signal(v, 'heart', now)
    }
    if (cue.revived && cue.revived.at !== before.revived?.at) {
      if (cue.revived.kind === 'cure') {
        v.react = [{ mood: 'happy', until: now + 3000 }]
        this.signal(v, 'heart', now)
      } else {
        v.react = [
          { mood: 'surprised', until: now + 900 },
          { mood: 'happy', until: now + 3500 },
        ]
        this.signal(v, '!', now)
        v.revived = now
        this.beamDown(v, now)
      }
    }
    if (cue.declined && before.declined !== cue.declined) this.signal(v, 'anger', now)
    // 牵起手、靠上去、抱在一起的那一下：两人都高兴一阵、冒个心
    if (cue.touch && cue.touch !== before.touch) {
      v.react = [{ mood: 'happy', until: now + 2500 }]
      this.signal(v, 'heart', now)
    }
    if (cue.goal && before.goal && before.goal !== cue.goal) this.signal(v, 'bulb', now)
    const fell = (cue.down || cue.dead) && !before.down && !before.dead && before !== cue
    if (fell && v.mesh.visible)
      for (const o of this.all.values())
        if (
          o !== v &&
          !o.cue.dead &&
          Math.hypot(o.at[0] - v.at[0], o.at[1] - v.at[1]) < LOOK_NEAR
        ) {
          this.signal(o, '!', now)
          o.react = [{ mood: 'surprised', until: now + 1200 }]
        }
  }

  /** 冒一个一阵子的符号：比正在冒的要紧（或那个已经过了）才换 */
  private signal(v: Villager, sign: Sign, now: number) {
    if (v.sign && v.sign.until > now && SIGN_RANK[v.sign.sign] > SIGN_RANK[sign]) return
    v.sign = { sign, at: now, until: now + SIGN_MS }
  }

  /** 此刻头顶冒哪个符号：一阵子的优先；没有就看一直在的状态，按各自的节奏隔一阵冒一次 */
  private signNow(v: Villager, now: number): Shown | undefined {
    if (v.sign && v.sign.until > now) return v.sign
    v.sign = undefined
    const phase = hashString(v.id) % 10000
    let best: Shown | undefined
    for (const sign of standingSigns(v.cue, this.climate.hot)) {
      const [on, off] = CYCLE[sign] ?? [2000, 6000]
      const start = now - ((now + phase) % (on + off))
      if (now - start >= on) continue
      if (!best || SIGN_RANK[sign] > SIGN_RANK[best.sign])
        best = { sign, at: start, until: start + on }
    }
    return best
  }

  /** 闪电：在外面的人吓一跳 */
  startle() {
    const now = performance.now()
    for (const v of this.all.values())
      if (v.mesh.visible && !v.cue.indoors && !v.cue.dead) {
        this.signal(v, '!', now)
        v.react = [{ mood: 'surprised', until: now + 700 }]
      }
  }

  /** 复活：天上落下一道光柱，停一会儿淡掉 */
  private beamDown(v: Villager, now: number) {
    if (v.beam) return
    const material = new THREE.MeshBasicMaterial({
      map: this.beamTexture,
      color: '#fff1c8',
      transparent: true,
      opacity: 0,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    })
    const mesh = new THREE.Mesh(this.beamGeometry, material)
    mesh.layers.set(REFLECTION_SKIP)
    mesh.renderOrder = 2
    mesh.userData.at = now
    v.beam = mesh
    this.scene.add(mesh)
    this.placeBeam(v)
  }

  private placeBeam(v: Villager) {
    if (!v.beam) return
    stand(v.beam, v.at[0] + v.offset[0], v.at[1] + v.offset[1], this.tilt, PIXEL * 2)
  }

  /** 光柱：贴地往上，落下时从上往下长出来，停住后淡掉 */
  private stepBeam(v: Villager, now: number) {
    const beam = v.beam
    if (!beam) return
    const k = now - beam.userData.at
    const material = beam.material as THREE.MeshBasicMaterial
    if (k >= BEAM_MS[2]) {
      this.scene.remove(beam)
      material.dispose()
      v.beam = undefined
      return
    }
    const grow = Math.min(1, k / BEAM_MS[0])
    beam.scale.set(1, grow, 1)
    // 从上往下长：缩放以顶端为准
    this.placeBeam(v)
    beam.translateY(BEAM_H * (1 - grow))
    material.opacity =
      0.85 * (k < BEAM_MS[1] ? 1 : 1 - (k - BEAM_MS[1]) / (BEAM_MS[2] - BEAM_MS[1]))
  }

  private readonly beamGeometry = new THREE.PlaneGeometry(VILLAGER_HALF * 2.6, BEAM_H).translate(
    0,
    BEAM_H / 2,
    0
  )
  private readonly beamTexture = beamTexture()

  /** 此刻的心情：一阵子的表情优先，过了就按身体和需求 */
  private moodNow(v: Villager, now: number): Mood {
    while (v.react.length && v.react[0].until <= now) v.react.shift()
    return v.react[0]?.mood ?? moodOf(v.cue)
  }

  /** 操控中的人：画到本地预测的位置，按走过的距离换走路帧；还不知道预测位置时按名册 */
  private stepLive(v: Villager, now: number) {
    const end = v.path[v.path.length - 1]
    const [x, y] = this.motion?.at(now) ?? [end.x, end.y]
    const dx = x - v.at[0],
      dy = y - v.at[1]
    const d = Math.hypot(dx, dy)
    v.moving = !!this.motion?.walking()
    if (v.moving && d > 0.01) v.facing = [dx, dy]
    if (!v.moving) this.turnToward(v)
    this.face(v)
    if (d > 0.01) {
      if (v.moving) v.walked += d
      this.moveTo(v, x, y)
      this.footfall(v)
      return true
    }
    return false
  }

  /** 玩家操控的人还在动（在走，或在和服务端校正）：场景要每帧都画，不等节拍 */
  liveActive() {
    if (!this.motion?.active()) return false
    for (const v of this.all.values()) if (v.live) return true
    return false
  }

  /** 还有人没走到最新位置：定时器据此决定要不要再画一帧 */
  active() {
    for (const v of this.all.values()) {
      const end = v.path[v.path.length - 1]
      if (v.live) {
        if (this.motion?.active() || v.moving) return true
        continue
      }
      if (v.path.length > 1 || v.at[0] !== end.x || v.at[1] !== end.y) return true
    }
    return false
  }

  /** 新落下的脚印（地图坐标）：取走后清空。左右脚往两边错开一点 */
  private readonly prints: [number, number][] = []
  takeFootprints() {
    return this.prints.splice(0)
  }

  /** 走过的距离够一步了：落一个脚印 */
  private footfall(v: Villager) {
    if (v.walked < v.nextStep || !v.mesh.visible) return
    v.nextStep = v.walked + STEP
    v.leftFoot = !v.leftFoot
    const [fx, fy] = v.facing
    const len = Math.hypot(fx, fy) || 1
    const side = (v.leftFoot ? -1 : 1) * 1.2 * PIXEL
    if (this.prints.length < 64)
      this.prints.push([
        v.at[0] + v.offset[0] - (fy / len) * side,
        v.at[1] + v.offset[1] + (fx / len) * side,
      ])
  }

  /** 立牌此刻站在哪（地图坐标，含避让家具和墙的偏移）；不在场或看不见时为 undefined */
  drawnAt(id: string): [number, number] | undefined {
    const v = this.all.get(id)
    return v?.mesh.visible ? [v.at[0] + v.offset[0], v.at[1] + v.offset[1]] : undefined
  }

  /** 立牌比名册里的位置落后多少（地图单位）：名字和心声泡按它跟着立牌平移 */
  lag(id: string): [number, number] | undefined {
    const v = this.all.get(id)
    if (!v) return
    const end = v.path[v.path.length - 1]
    // 站在桥上抬高了的，名字和心声泡也跟着往画面上方挪（离镜头远的方向）
    const up = PIXEL - riseOf(this.lift(v.at[0] + v.offset[0], v.at[1] + v.offset[1]), this.tilt)
    return [
      v.at[0] - end.x + v.offset[0] + up * this.tilt.yawSin,
      v.at[1] - end.y + v.offset[1] + up * this.tilt.yawCos,
    ]
  }

  /** 立牌此刻走多快（地图单位 / 毫秒，按播放快慢折成真实时间）：镜头锁住跟随时按它往前补一截。
   *  照时间轴上这一段算，不按每帧位移估，换位置偏移、进门出门那一下跳不会被当成飞快地走；
   *  站着、操控中的人为零 */
  velocity(id: string): [number, number] | undefined {
    const v = this.all.get(id)
    if (!v) return
    const [a, b] = v.path
    if (v.live || !b || b.t <= a.t || this.play < a.t || this.play >= b.t) return [0, 0]
    const k = this.rate / (b.t - a.t)
    return [(b.x - a.x) * k, (b.y - a.y) * k]
  }

  /** 每帧画之前调用（now 是这一帧的时刻）：摆到播放时刻的位置，更新朝向，画好每人这一帧；
   *  有人走动时返回 true */
  step(now: number) {
    const dt = Math.min(100, Math.max(0, now - this.last))
    this.last = now
    this.play = Math.min(this.latest, this.play + dt * this.rate)
    let changed = false
    for (const v of this.all.values()) {
      if (v.live) {
        if (this.stepLive(v, now)) changed = true
        this.frame(v, now)
        this.stepBeam(v, now)
        continue
      }
      while (v.path.length > 1 && v.path[1].t <= this.play) v.path.shift()
      const [a, b] = v.path
      const k = b ? Math.max(0, (this.play - a.t) / (b.t - a.t)) : 0
      const x = b ? a.x + (b.x - a.x) * k : a.x,
        y = b ? a.y + (b.y - a.y) * k : a.y
      const d = Math.hypot(x - v.at[0], y - v.at[1])
      // 朝向按这一段路的方向，不按每帧的小位移，斜着走时不来回换
      const sx = b ? b.x - a.x : 0,
        sy = b ? b.y - a.y : 0
      v.moving = Math.hypot(sx, sy) > 0.01
      if (v.moving) v.facing = [sx, sy]
      else {
        this.turnToward(v)
        this.lookAround(v, now)
      }
      this.face(v)
      if (d > 0) {
        v.walked += d
        this.moveTo(v, x, y)
        this.footfall(v)
        changed = true
      }
      this.frame(v, now)
      this.stepBeam(v, now)
    }
    this.stepSpot(now)
    return changed
  }

  /** 站着的人隔一会儿挑一个看的对象：朝着的人（和玩家说话、被玩家邀请），其次玩家操控的人，
   *  再次身边走过的人；都没有就随便看看。对象到了身侧（画面上偏过 45°）整个人转过去，
   *  在身后就只看不转，免得背对镜头；在用道具、在聊天的人只拿眼睛看 */
  private lookAround(v: Villager, now: number) {
    if (now < v.nextLook) return
    v.nextLook = now + LOOK_MS
    let target = v.faceToward
    if (!target) {
      let best = Infinity
      for (const o of this.all.values()) {
        if (o === v || !o.mesh.visible) continue
        const d = Math.hypot(o.at[0] - v.at[0], o.at[1] - v.at[1])
        const reach = o.live ? LOOK_AVATAR : o.moving ? LOOK_NEAR : 0
        const score = o.live ? d / 2 : d
        if (d < reach && score < best) {
          best = score
          target = o.at
        }
      }
    }
    if (!target) {
      v.gazeAt = undefined
      return
    }
    const dx = target[0] - v.at[0],
      dy = target[1] - v.at[1]
    if (Math.hypot(dx, dy) < 1) return
    const sx = dx * this.tilt.yawCos - dy * this.tilt.yawSin
    const sy = dx * this.tilt.yawSin + dy * this.tilt.yawCos
    v.gazeAt = [sx, sy]
    if (v.faceToward || v.cue.verb || v.cue.chat || now - v.turnedAt < TURN_HOLD_MS) return
    const want: Direction =
      Math.abs(sx) > Math.abs(sy) ? (sx > 0 ? 'right' : 'left') : sy > 0 ? 'down' : 'up'
    if (want === 'up' || want === v.dir) return
    v.facing = [dx, dy]
    v.turnedAt = now
  }

  /** 站着的人转身朝向要看的人 */
  private turnToward(v: Villager) {
    if (!v.faceToward) return
    const dx = v.faceToward[0] - v.at[0],
      dy = v.faceToward[1] - v.at[1]
    if (Math.hypot(dx, dy) > 1) v.facing = [dx, dy]
  }

  /** 一格贴图像素在屏幕上占几个设备像素（随缩放变） */
  setTexelPx(px: number) {
    this.texelPx = px
  }

  /** 天上有没有值得抬头看的（晴夜的星星、下雪） */
  setSky(sky: boolean) {
    this.sky = sky
  }

  /** 每帧画之前：要不要减少动画、风在每处往哪边吹 */
  setAir(calm: boolean, sway: (x: number, z: number) => number) {
    this.calm = calm
    this.sway = sway
  }

  /** 镜头看得见的范围（地图坐标，已留出一圈余量）：范围外的人不重画贴图 */
  setView(x0: number, y0: number, x1: number, y1: number) {
    this.view = [x0, y0, x1, y1]
  }
  private view: [number, number, number, number] = [-Infinity, -Infinity, Infinity, Infinity]

  /** 按此刻的朝向、走路、姿势、表情、呼吸眨眼和风合成这一帧；和上一帧不一样才重画、上传。
   *  镜头外的人不画 */
  private frame(v: Villager, now: number) {
    if (!v.mesh.visible) return
    const [vx0, vy0, vx1, vy1] = this.view
    const [px, py] = [v.at[0] + v.offset[0], v.at[1] + v.offset[1]]
    if (px < vx0 || px > vx1 || py < vy0 || py > vy1) return
    // 天好时在外面刚迈开步，五个人里约有一个哼一句
    if (v.moving && !v.strolling && this.climate.fine && !v.cue.indoors && !v.cue.verb)
      if (hashString(`${v.id}${Math.floor(now / 20000)}`) % 5 === 0) this.signal(v, 'note', now)
    v.strolling = v.moving
    if (v.talk && now - v.talk.at > talkMs(v.talk.text)) v.talk = undefined
    if (v.hear && now - v.hear.at > v.hear.ms) v.hear = undefined
    const m: Moment = {
      now,
      dir: v.dir,
      moving: v.moving,
      stride: v.walked / STRIDE,
      lively: !this.calm && this.texelPx >= 1,
      wind: this.sway(v.mesh.position.x, v.mesh.position.z),
      look: v.gazeAt,
      sky: this.sky,
      pose: v.cue.verb ? poseOf(v.cue.verb) : undefined,
      mood: this.moodNow(v, now),
      talk: v.talk,
      hear: v.hear,
      body: bodyOf(v.cue),
      wear: this.wearOf(v),
      sign: this.signNow(v, now),
      badge: this.badges.get(v.id),
      revived: v.revived,
    }
    // 没伞淋雨的人小跑：脚步比走过的路快；走得慢的人步子慢
    if (m.wear?.cover) m.stride *= 1.4
    else if (v.cue.persona && SLOW_WALKERS.has(v.cue.persona)) m.stride *= 0.75
    m.quirk = this.quirkNow(v, now, m.lively)
    m.close = this.texelPx >= 3
    m.pick = v.id === this.picked ? 'pick' : v.id === this.hovered ? 'hover' : undefined
    const f = v.acting.frame(m)
    v.crown =
      (f.props?.key.includes('umbrella') ? 10 : f.sign || f.badge ? 3 : 0) * PIXEL * VILLAGER_SCALE
    const key = frameKey(f)
    if (key === v.drawn) return
    v.drawn = key
    v.rig.draw(f, v.data, v.normals)
    v.map.needsUpdate = true
    v.normalMap.needsUpdate = true
  }

  /** 站着没事做（没在走、没用道具、没聊天、没倒下）超过 8 秒，隔一阵演一段自己的小动作 */
  private quirkNow(v: Villager, now: number, lively: boolean) {
    const c = v.cue
    if (v.moving || c.verb || c.chat || c.dead || c.down || v.talk || !lively) {
      v.idleSince = now
      v.quirk = undefined
      return undefined
    }
    if (v.quirk && now < v.quirk.until) return v.quirk
    if (v.quirk) {
      v.quirk = undefined
      v.nextQuirk = now + between(QUIRK_REST_MS, hashString(`${v.id}${now | 0}`))
    }
    if (now - v.idleSince < QUIRK_AFTER_MS || now < v.nextQuirk) return undefined
    const pick = hashString(`${v.id}:${Math.floor(now / 1000)}`)
    const kinds = quirksOf(c.persona, v.rig.look.outfit, this.climate.lit > 0.5)
    v.quirk = {
      kind: kinds[pick % kinds.length],
      at: now,
      until: now + between(QUIRK_MS, pick >>> 8),
    }
    return v.quirk
  }

  /** 选中的人（金边，脚下一圈暖色光斑）、指着的人（白边） */
  setPicked(picked: string | null, hovered: string | null) {
    this.picked = picked
    this.hovered = hovered
  }
  private picked: string | null = null
  private hovered: string | null = null

  /** 选中的人脚下的光斑：一张贴地的小图，不受夜色压暗，慢慢明暗起伏 */
  private stepSpot(now: number) {
    const v = this.picked ? this.all.get(this.picked) : undefined
    const spot = this.spot
    spot.visible = !!v?.mesh.visible
    if (!v || !spot.visible) return
    spot.position.set(v.at[0] + v.offset[0], 0.5, v.at[1] + v.offset[1])
    const material = spot.material as THREE.MeshBasicMaterial
    material.opacity = this.calm ? 0.75 : 0.62 + 0.18 * Math.sin(now / 420)
  }
  private readonly spot = selectionSpot()

  /** 天气落在这个人身上：下雨在外面的打伞（没伞的抱头），淋湿和积雪按在外面待的时间分档，
   *  冷天多数人围围巾、在外面呵白气，夜里一部分人提灯笼 */
  private wearOf(v: Villager): Wear {
    const c = this.climate
    const out = !v.cue.indoors && !v.cue.dead && !v.cue.down
    const raining = out && c.rain > 0.15
    const level = (n: number, steps: number[]) => steps.filter((s) => n >= s).length
    return {
      umbrella: raining && v.owns.umbrella,
      cover: raining && !v.owns.umbrella && !v.cue.verb,
      wet: level(v.rainMin, WET_MIN) as Wear['wet'],
      snow: level(v.snowMin, SNOW_MIN) as Wear['snow'],
      scarf: c.scarves && v.owns.scarf,
      breath: c.cold && out,
      lantern: out && c.lit > 0.5 && v.owns.lantern,
    }
  }

  /** 天气和时间变了：按过去的游戏分钟给每人累积淋雨、积雪（进屋就抖掉、慢慢干） */
  setClimate(c: Climate) {
    const dt = Math.max(0, Math.min(30, c.minutes - this.climate.minutes))
    this.climate = c
    if (!dt) return
    for (const v of this.all.values()) {
      const out = !v.cue.indoors
      if (out && c.rain > 0.15) v.rainMin += dt * (v.owns.umbrella ? 0.25 : 1)
      else v.rainMin = Math.max(0, v.rainMin - dt / 3)
      if (!out) v.snowMin = 0
      else if (c.snowing) v.snowMin += dt
      else v.snowMin = Math.max(0, v.snowMin - dt / 10)
    }
  }
  private climate: Climate = {
    rain: 0,
    snowing: false,
    lit: 0,
    cold: false,
    scarves: false,
    hot: false,
    fine: false,
    minutes: 0,
  }

  /** 提着灯笼的人在哪（地图坐标）：光照图把它们当作会走的灯 */
  lanterns() {
    const out: [number, number][] = []
    for (const v of this.all.values())
      if (v.mesh.visible && v.drawn.includes('lantern'))
        out.push([v.at[0] + v.offset[0], v.at[1] + v.offset[1]])
    return out
  }

  /** 打着伞的人：伞面中心（世界 x、z）、半径、离地高，雨滴落到伞面就没了。伞面在贴图第 8～14 行，
   *  立牌按俯角往后仰，所以按立牌自己的朝向从脚往上量 */
  umbrellas() {
    const out: [number, number, number, number][] = []
    const texel = PIXEL * VILLAGER_SCALE
    for (const v of this.all.values()) {
      if (!v.mesh.visible || !v.drawn.includes('umbrella')) continue
      const top = this.canopy.set(0, (RIG_H - 11) * texel, 0)
      v.mesh.localToWorld(top)
      out.push([top.x, top.z, 14 * texel, top.y])
    }
    return out
  }
  private readonly canopy = new THREE.Vector3()

  /** 头顶多出来的高度（伞面、符号，地图单位）：气泡按它躲开 */
  crown(id: string) {
    return this.all.get(id)?.crown ?? 0
  }

  /** 还有一阵子的东西要演完（光柱、刚冒的符号）：减少动画时也要接着画 */
  pending() {
    const now = performance.now()
    for (const v of this.all.values())
      if (v.beam || (v.sign && v.sign.until > now) || v.react.length) return true
    return false
  }

  private create(p: VillagerPlacement): Villager {
    let rig = this.rigs.get(p.look)
    if (!rig) {
      rig = new VillagerRig(p.look)
      this.rigs.set(p.look, rig)
    }
    // 每人一块小贴图，像素直接写进 data
    const data = new Uint8Array(RIG_W * RIG_H * 4)
    const map = pixelFilter(new THREE.DataTexture(data, RIG_W, RIG_H)) as THREE.DataTexture
    map.colorSpace = THREE.SRGBColorSpace
    const mesh = standee(map, { scale: VILLAGER_SCALE, frame: [RIG_W, RIG_H] })
    this.prepare?.(mesh.material as THREE.Material)
    const normals = new Uint8Array(RIG_W * RIG_H * 4)
    const normalMap = new THREE.DataTexture(normals, RIG_W, RIG_H)
    normalMap.magFilter = normalMap.minFilter = THREE.NearestFilter
    shadeVillager(mesh.material as THREE.Material, normalMap)
    this.scene.add(mesh)
    const contact = new THREE.Mesh(this.contactGeometry, this.contactMaterial)
    contact.layers.set(REFLECTION_SKIP)
    contact.renderOrder = 1
    this.scene.add(contact)
    const v: Villager = {
      id: p.id,
      mesh,
      contact,
      map,
      data,
      normalMap,
      normals,
      rig,
      acting: new Acting(p.id),
      drawn: '',
      cue: p.cue ?? {},
      react: [],
      owns: owns(p.id),
      rainMin: 0,
      snowMin: 0,
      crown: 0,
      strolling: false,
      idleSince: performance.now(),
      nextQuirk: 0,
      look: p.look,
      at: [p.x, p.y],
      path: [{ t: this.latest, x: p.x, y: p.y }],
      dir: 'down',
      facing: [0, 1],
      offset: p.offset ?? [0, 0],
      walked: 0,
      nextStep: STEP,
      leftFoot: false,
      moving: false,
      nextLook: 0,
      turnedAt: -TURN_HOLD_MS,
    }
    this.moveTo(v, p.x, p.y)
    this.face(v)
    this.frame(v, performance.now())
    this.all.set(p.id, v)
    return v
  }

  private moveTo(v: Villager, x: number, y: number) {
    v.at = [x, y]
    // 往镜头方向挪一个像素，站在同一处的道具前面；在桥上就站到桥面上
    const up = this.lift(x + v.offset[0], y + v.offset[1])
    stand(v.mesh, x + v.offset[0], y + v.offset[1], this.tilt, PIXEL)
    v.mesh.position.y += up
    v.contact.position.set(x + v.offset[0], 0.35 + up, y + v.offset[1])
  }

  private face(v: Villager) {
    const [x, y] = v.facing
    const sx = x * this.tilt.yawCos - y * this.tilt.yawSin
    const sy = x * this.tilt.yawSin + y * this.tilt.yawCos
    v.dir = Math.abs(sx) > Math.abs(sy) ? (sx > 0 ? 'right' : 'left') : sy > 0 ? 'down' : 'up'
  }

  private remove(id: string) {
    const v = this.all.get(id)
    if (!v) return
    this.scene.remove(v.mesh, v.contact)
    if (v.beam) {
      this.scene.remove(v.beam)
      ;(v.beam.material as THREE.Material).dispose()
    }
    v.mesh.geometry.dispose()
    ;(v.mesh.material as THREE.Material).dispose()
    v.map.dispose()
    v.normalMap.dispose()
    this.all.delete(id)
  }

  dispose() {
    for (const id of [...this.all.keys()]) this.remove(id)
    this.scene.remove(this.spot)
    this.spot.geometry.dispose()
    ;(this.spot.material as THREE.MeshBasicMaterial).map?.dispose()
    ;(this.spot.material as THREE.Material).dispose()
    this.beamGeometry.dispose()
    this.beamTexture.dispose()
    this.contactGeometry.dispose()
    this.contactMaterial.map?.dispose()
    this.contactMaterial.dispose()
  }
}

/** 谁带伞（一半人）、提灯笼（三成）、围围巾（七成）：按编号定 */
function owns(id: string) {
  const h = hashString(id)
  return { umbrella: (h & 1) === 0, lantern: (h >>> 1) % 10 < 3, scarf: (h >>> 5) % 10 < 7 }
}

/** 光柱的样子：中间亮、两边和顶上淡，贴地那头最亮 */
function beamTexture() {
  const w = 16,
    h = 64
  const c = document.createElement('canvas')
  c.width = w
  c.height = h
  const ctx = c.getContext('2d')!
  const img = ctx.createImageData(w, h)
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const across = 1 - Math.abs((x + 0.5) / w - 0.5) * 2
      const up = 1 - y / h
      const a = Math.pow(across, 1.6) * (0.35 + 0.65 * Math.pow(1 - up, 0.6))
      const i = (y * w + x) * 4
      img.data[i] = img.data[i + 1] = img.data[i + 2] = 255
      img.data[i + 3] = Math.round(a * 255)
    }
  ctx.putImageData(img, 0, 0)
  const t = new THREE.CanvasTexture(c)
  t.colorSpace = THREE.SRGBColorSpace
  return t
}

/** 在 [a, b) 里按一个整数取一个数 */
function between([a, b]: number[], n: number) {
  return a + ((n % 1000) / 1000) * (b - a)
}

/** 选中的光斑：贴地的椭圆光圈，按有序抖动由里往外淡，像素感 */
function selectionSpot() {
  const w = 40,
    h = 24
  const c = document.createElement('canvas')
  c.width = w
  c.height = h
  const ctx = c.getContext('2d')!
  const img = ctx.createImageData(w, h)
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const d = Math.hypot((x + 0.5 - w / 2) / (w / 2), (y + 0.5 - h / 2) / (h / 2))
      // 一圈亮边，里面淡淡一层
      const a = d > 1 ? 0 : d > 0.78 ? 1 : 0.35 * (1 - d)
      const keep = a >= 1 || bayer(x, y) < a
      const i = (y * w + x) * 4
      img.data[i] = 255
      img.data[i + 1] = 214
      img.data[i + 2] = 120
      img.data[i + 3] = keep ? 255 : 0
    }
  ctx.putImageData(img, 0, 0)
  const map = new THREE.CanvasTexture(c)
  map.magFilter = map.minFilter = THREE.NearestFilter
  map.colorSpace = THREE.SRGBColorSpace
  const size = VILLAGER_HALF * 3.2
  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(size, size * (h / w)).rotateX(-Math.PI / 2),
    new THREE.MeshBasicMaterial({ map, transparent: true, opacity: 0.7, depthWrite: false })
  )
  mesh.renderOrder = 1
  mesh.layers.set(REFLECTION_SKIP)
  mesh.visible = false
  return mesh
}
