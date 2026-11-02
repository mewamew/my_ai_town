import * as THREE from 'three'
import { PIXEL } from '../grid'
import type { Tilt } from './layout'
import { stand, standee, texture } from './standee'
import {
  DIRECTIONS,
  FRAME_H,
  FRAME_W,
  VILLAGER_SCALE,
  villagerAtlas,
  type Direction,
} from './villagerSprite'

// 村民立牌：位置跟着名册走。名册每拍（100 毫秒）来一次，立牌比最新一份晚一到两拍，在相邻两份
// 之间匀速走过去：每份名册记作比上一份晚一拍，播放按真实时间走；每来一份按缓冲多少把播放稍微调快
// 或调慢，一份之内速度不变，名册早到晚到、主线程卡一下都不会让人忽快忽慢。
// 按这一段路的方向选朝向、按走过的距离换走路帧。
// 玩家正在操控的人不缓冲：位置由本地预测给出（见 ../avatarMotion.ts），每帧照着发出去的方向和步速走，
// 按下去马上就动，不比别人晚两拍，也不随名册早到晚到一顿一顿。

/** 走过多少地图单位换一帧 */
const STRIDE = 3.2 * PIXEL
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

export interface VillagerPlacement {
  id: string
  /** 决定长相的编号：同一个头像模板永远长一个样 */
  look: string
  x: number
  y: number
  /** 为避开家具和墙而做的显示偏移，不进入名册位置与行走时间轴。 */
  offset?: [number, number]
  visible: boolean
  /** 死亡的人变灰，失去行动能力的人压暗 */
  condition: 'normal' | 'incapacitated' | 'dead'
  /** 玩家正在操控的人：不缓冲，按本地预测画（见 LiveMotion） */
  live?: boolean
  /** 站着时转身朝向这一点（被玩家邀请、正和玩家聊天的人朝向玩家） */
  faceToward?: [number, number]
}

const TINT = { normal: '#ffffff', incapacitated: '#a8a0a0', dead: '#6f6f78' }

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
  mesh: THREE.Mesh
  map: THREE.Texture
  look: string
  at: [number, number]
  /** 还没走完的几份名册位置，第一份在播放时刻之前（或就是最后一份） */
  path: Sample[]
  dir: Direction
  /** 最后一次行走的世界方向；转动镜头时静止的人也换到相应朝向帧。 */
  facing: [number, number]
  offset: [number, number]
  walked: number
  moving: boolean
  /** 玩家正在操控的人：位置按 LiveMotion 画 */
  live?: boolean
  /** 站着时朝向的点 */
  faceToward?: [number, number]
}

export class Villagers {
  private readonly all = new Map<string, Villager>()
  private readonly atlases = new Map<string, THREE.Texture>()
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

  /** prepare：每个新立牌的材质过一遍（接光照图） */
  constructor(
    private scene: THREE.Scene,
    private tilt: Tilt,
    private readonly prepare?: (material: THREE.Material) => void
  ) {}

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
      v.mesh.visible = p.visible
      const color = (v.mesh.material as THREE.MeshLambertMaterial).color
      const tint = color.getHex()
      color.set(TINT[p.condition])
      if (color.getHex() !== tint) changed = true
      if (v.faceToward?.[0] !== p.faceToward?.[0] || v.faceToward?.[1] !== p.faceToward?.[1])
        changed = true
      v.faceToward = p.faceToward
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
    return changed
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
    let changed = this.face(v)
    if (d > 0.01) {
      if (v.moving) v.walked += d
      this.moveTo(v, x, y)
      changed = true
    }
    return changed
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
    return [
      v.at[0] - end.x + v.offset[0] + PIXEL * this.tilt.yawSin,
      v.at[1] - end.y + v.offset[1] + PIXEL * this.tilt.yawCos,
    ]
  }

  /** 每帧画之前调用（now 是这一帧的时刻）：摆到播放时刻的位置，更新朝向与走路帧；
   *  有人走动或换了帧时返回 true */
  step(now: number) {
    const dt = Math.min(100, Math.max(0, now - this.last))
    this.last = now
    this.play = Math.min(this.latest, this.play + dt * this.rate)
    let changed = false
    for (const v of this.all.values()) {
      if (v.live) {
        if (this.stepLive(v, now)) changed = true
        if (this.frame(v)) changed = true
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
      else this.turnToward(v)
      const directionChanged = this.face(v)
      if (directionChanged) changed = true
      if (d > 0) {
        v.walked += d
        this.moveTo(v, x, y)
        changed = true
      }
      if (this.frame(v)) changed = true
    }
    return changed
  }

  /** 站着的人转身朝向要看的人 */
  private turnToward(v: Villager) {
    if (!v.faceToward) return
    const dx = v.faceToward[0] - v.at[0],
      dy = v.faceToward[1] - v.at[1]
    if (Math.hypot(dx, dy) > 1) v.facing = [dx, dy]
  }

  /** 按朝向和走过的距离选走路帧；换了帧返回 true */
  private frame(v: Villager) {
    const frame = v.moving ? Math.floor(v.walked / STRIDE) % 4 : 0
    const fx = frame / 4,
      fy = 1 - (DIRECTIONS.indexOf(v.dir) + 1) / 4
    if (v.map.offset.x === fx && v.map.offset.y === fy) return false
    v.map.offset.set(fx, fy)
    return true
  }

  private create(p: VillagerPlacement): Villager {
    let atlas = this.atlases.get(p.look)
    if (!atlas) {
      atlas = texture(villagerAtlas(p.look))
      this.atlases.set(p.look, atlas)
    }
    // 每人一份贴图对象，共用同一张图集，只是偏移不同
    const map = atlas.clone()
    map.repeat.set(1 / 4, 1 / 4)
    const mesh = standee(map, { scale: VILLAGER_SCALE, frame: [FRAME_W, FRAME_H] })
    this.prepare?.(mesh.material as THREE.Material)
    this.scene.add(mesh)
    const v: Villager = {
      mesh,
      map,
      look: p.look,
      at: [p.x, p.y],
      path: [{ t: this.latest, x: p.x, y: p.y }],
      dir: 'down',
      facing: [0, 1],
      offset: p.offset ?? [0, 0],
      walked: 0,
      moving: false,
    }
    this.moveTo(v, p.x, p.y)
    this.face(v)
    this.all.set(p.id, v)
    return v
  }

  private moveTo(v: Villager, x: number, y: number) {
    v.at = [x, y]
    // 往镜头方向挪一个像素，站在同一处的道具前面
    stand(v.mesh, x + v.offset[0], y + v.offset[1], this.tilt, PIXEL)
  }

  private face(v: Villager) {
    const [x, y] = v.facing
    const sx = x * this.tilt.yawCos - y * this.tilt.yawSin
    const sy = x * this.tilt.yawSin + y * this.tilt.yawCos
    const dir = Math.abs(sx) > Math.abs(sy) ? (sx > 0 ? 'right' : 'left') : sy > 0 ? 'down' : 'up'
    const changed = dir !== v.dir
    v.dir = dir
    v.map.offset.y = 1 - (DIRECTIONS.indexOf(dir) + 1) / 4
    return changed
  }

  private remove(id: string) {
    const v = this.all.get(id)
    if (!v) return
    this.scene.remove(v.mesh)
    v.mesh.geometry.dispose()
    ;(v.mesh.material as THREE.Material).dispose()
    v.map.dispose()
    this.all.delete(id)
  }

  dispose() {
    for (const id of [...this.all.keys()]) this.remove(id)
    for (const a of this.atlases.values()) a.dispose()
  }
}
