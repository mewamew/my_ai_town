import * as THREE from 'three'
import { PIXEL } from '../../grid'

// 执剑人之夜天上的水滴：一颗镜面似的像素水滴，从东北方的高空拖着一道光朝引力波天线飞来。
// 来袭的十分钟里按倒计时往前挪，停在天线前面一点；执剑人按下了，天线发出一圈圈引力波，水滴掉头飞走；
// 威慑失败，水滴撞上天线，一团白光，天线那里一直冒烟。都是面向镜头的像素小立牌（Sprite），不受灯光和雾影响。
// 刷新页面时已经有了结局：不再重放撞击或掉头，直接是冒烟或引力波。

/** 天线顶上大约多高、往北偏多少（地图单位）：方尖碑立牌 72 像素高，按俯角后仰 */
const TOP = { y: 330, z: -200 }
/** 水滴从天线的哪个方向、多远的高空飞来：镜头框住天线时，起点在画面右上角附近 */
const FROM = new THREE.Vector3(1000, 650, -300)
/** 来袭时最多飞到全程的这么多：剩下一截等结局 */
const REACH = 0.9
/** 十分钟里过去 p 时水滴在全程的哪儿：先快后慢，越逼越近 */
const reach = (p: number) => REACH * (1 - (1 - p) ** 3)
/** 警报一响，水滴几秒内先冲进来半程：执剑人多半一两分钟就做决定，那时它得已经在天线跟前 */
const ENTER = 0.55
const ENTER_SECONDS = 4
/** 水滴、光晕、闪光、引力波圈和烟的大小（地图单位）；拖尾几颗光点、相隔全程的多少 */
const DROP_W = 13 * PIXEL * 2
const HALO = DROP_W * 2
const TRAIL = 10
const TRAIL_GAP = 0.028
const FLASH = 1500
const RING = 1700
const PUFFS = 6

export type DropState =
  | { kind: 'none' }
  /** 来袭中：progress 是十分钟里过去的比例；fresh 时先冲进来，否则（打开页面时已经在来袭）直接在该在的地方 */
  | { kind: 'coming'; progress: number; fresh: boolean }
  /** 按下了：fresh 时水滴掉头飞走，否则只有引力波 */
  | { kind: 'broadcast'; fresh: boolean }
  /** 威慑失败：fresh 时撞上去、闪一下，之后一直冒烟 */
  | { kind: 'failed'; fresh: boolean }

/** 像素画到画布上：fn 返回每格的颜色，null 是透明 */
function pixels(w: number, h: number, fn: (x: number, y: number) => string | null) {
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const g = canvas.getContext('2d')
  if (g)
    for (let y = 0; y < h; y++)
      for (let x = 0; x < w; x++) {
        const c = fn(x, y)
        if (!c) continue
        g.fillStyle = c
        g.fillRect(x, y, 1, 1)
      }
  return canvas
}

function pixelTexture(canvas: HTMLCanvasElement) {
  const t = new THREE.CanvasTexture(canvas)
  t.magFilter = THREE.NearestFilter
  t.minFilter = THREE.NearestFilter
  t.generateMipmaps = false
  t.colorSpace = THREE.SRGBColorSpace
  return t
}

/** 柔光：中间亮、边上透明 */
function glowTexture(color: string) {
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = 64
  const g = canvas.getContext('2d')
  if (g) {
    const r = g.createRadialGradient(32, 32, 0, 32, 32, 32)
    r.addColorStop(0, color)
    r.addColorStop(1, 'rgba(255,255,255,0)')
    g.fillStyle = r
    g.fillRect(0, 0, 64, 64)
  }
  const t = new THREE.CanvasTexture(canvas)
  t.colorSpace = THREE.SRGBColorSpace
  return t
}

/** 水滴：尾尖朝上、圆头朝下的泪滴，左上来光，一小块高光，深色描边 */
function dropTexture() {
  const W = 13,
    H = 19,
    cx = 6.5,
    cy = 12.5,
    r = 6
  const inside = (x: number, y: number) => {
    const half =
      y < cy
        ? r * Math.pow(Math.max(0, y) / cy, 1.7)
        : Math.sqrt(Math.max(0, r * r - (y - cy) ** 2))
    return Math.abs(x - cx) <= half
  }
  return pixelTexture(
    pixels(W, H, (x, y) => {
      const px = x + 0.5,
        py = y + 0.5
      if (!inside(px, py)) return null
      const edge =
        !inside(px - 1, py) || !inside(px + 1, py) || !inside(px, py - 1) || !inside(px, py + 1)
      if (edge) return '#33415c'
      if (Math.hypot(px - (cx - 2.2), py - (cy - 2.6)) < 1.3) return '#ffffff'
      // 镜面：上半映着天，亮；下半映着地，暗一些
      const light = -((px - cx) * 0.6 + (py - cy) * 0.8) / r
      if (light > 0.45) return '#eef4fb'
      if (light > 0.05) return '#c9d7e8'
      if (light > -0.45) return '#93a9c6'
      return '#677e9f'
    })
  )
}

function dotTexture() {
  return pixelTexture(
    pixels(3, 3, (x, y) => (x === 1 && y === 1 ? '#ffffff' : x === 1 || y === 1 ? '#bfe2ff' : null))
  )
}

/** 引力波的一圈：放大到上千个单位时每格也就两三个地面像素，圈不至于太粗 */
function ringTexture() {
  return pixelTexture(
    pixels(128, 128, (x, y) => {
      const d = Math.hypot(x + 0.5 - 64, y + 0.5 - 64)
      return d > 61 && d <= 63 ? '#9fe0ff' : d > 60 && d <= 61 ? '#5fb8e8' : null
    })
  )
}

function puffTexture() {
  return pixelTexture(
    pixels(12, 12, (x, y) => {
      const d = Math.hypot(x + 0.5 - 6, y + 0.5 - 6)
      if (d > 5.6) return null
      return y > 7 ? '#4a4650' : d < 3 ? '#8a8690' : '#6a6670'
    })
  )
}

function sprite(map: THREE.Texture, additive = false, depthTest = true) {
  const s = new THREE.Sprite(
    new THREE.SpriteMaterial({
      map,
      transparent: true,
      depthWrite: false,
      depthTest,
      fog: false,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    })
  )
  s.visible = false
  return s
}

const ease = (t: number) => t * t * (3 - 2 * t)
const clamp01 = (t: number) => Math.min(1, Math.max(0, t))

export class Droplet {
  private readonly group = new THREE.Group()
  private readonly drop: THREE.Sprite
  private readonly halo: THREE.Sprite
  private readonly trail: THREE.Sprite[] = []
  private readonly flash: THREE.Sprite
  private readonly rings: THREE.Sprite[] = []
  private readonly puffs: THREE.Sprite[] = []
  /** 天线顶和水滴飞来的起点（场景坐标） */
  private readonly target = new THREE.Vector3()
  private readonly start = new THREE.Vector3()
  private aimed = false
  private state: DropState = { kind: 'none' }
  /** 此刻画在全程的哪儿：朝来袭的进度追过去，免得跳 */
  private shown = 0
  /** 警报响的时刻（秒）；打开页面时已经在来袭为 -1 */
  private alarm = -1
  /** 进入结局的时刻（秒）和那一刻水滴在全程的哪儿 */
  private since = -1
  private from = 0
  private last = 0
  private wasVisible = false
  /** 掉头飞走：尾尖朝天线，拖尾排在前面 */
  private away = false
  private readonly at = new THREE.Vector3()
  private readonly ahead = new THREE.Vector3()

  constructor(scene: THREE.Scene) {
    this.drop = sprite(dropTexture())
    this.drop.scale.set(DROP_W, (DROP_W * 19) / 13, 1)
    // 尾尖朝着来路：每帧按镜头把水滴转到飞行方向上（像素立牌在屏幕上转）
    this.drop.onBeforeRender = (_r, _s, camera) => this.orient(camera)
    this.halo = sprite(glowTexture('rgba(200,228,255,0.22)'), true)
    this.halo.scale.set(HALO, HALO, 1)
    const dot = dotTexture()
    for (let k = 0; k < TRAIL; k++) {
      const s = sprite(dot, true)
      const size = 30 * (1 - k / TRAIL) + 8
      s.scale.set(size, size, 1)
      ;(s.material as THREE.SpriteMaterial).opacity = 0.6 * (1 - k / TRAIL)
      this.trail.push(s)
    }
    // 都是半透明、不写深度：光晕最先画，拖尾其次，水滴压在最上面
    this.halo.renderOrder = 1
    for (const s of this.trail) s.renderOrder = 2
    this.drop.renderOrder = 3
    this.flash = sprite(glowTexture('rgba(255,255,255,1)'), true, false)
    const ring = ringTexture()
    for (let k = 0; k < 3; k++) this.rings.push(sprite(ring, true))
    const puff = puffTexture()
    for (let k = 0; k < PUFFS; k++) this.puffs.push(sprite(puff))
    this.group.add(this.halo, ...this.trail, this.drop, this.flash, ...this.rings, ...this.puffs)
    this.group.visible = false
    scene.add(this.group)
  }

  /** 天线在地图上的位置（场景坐标 x、z）；没有天线时什么也不画 */
  aim(spot: { x: number; z: number } | null) {
    this.aimed = !!spot
    if (!spot) return
    this.target.set(spot.x, TOP.y, spot.z + TOP.z)
    this.start.copy(this.target).add(FROM)
  }

  set(state: DropState) {
    const before = this.state
    this.state = state
    if (state.kind === 'coming' && before.kind !== 'coming') {
      // 刚响警报：从远处冲进来；打开页面时已经在来袭：直接在它该在的地方
      this.alarm = state.fresh ? this.last : -1
      this.shown = state.fresh ? 0 : reach(state.progress)
    }
    if ((state.kind === 'broadcast' || state.kind === 'failed') && before.kind !== state.kind) {
      this.since = state.fresh ? this.last : -1
      this.from = before.kind === 'coming' ? this.shown : REACH
    }
  }

  /** 全程上 p 处的位置 */
  private along(p: number, out: THREE.Vector3) {
    return out.copy(this.start).lerp(this.target, p)
  }

  /** 把水滴的尾尖转向来路：拿此刻的位置和往前一点的位置在屏幕上的走向算 */
  private orient(camera: THREE.Camera) {
    const a = this.at.copy(this.drop.position).project(camera)
    const b = this.ahead
      .copy(this.target)
      .sub(this.start)
      .normalize()
      .multiplyScalar(this.away ? -60 : 60)
    b.add(this.drop.position).project(camera)
    const dx = b.x - a.x,
      dy = b.y - a.y
    ;(this.drop.material as THREE.SpriteMaterial).rotation = Math.atan2(dx, -dy)
  }
  /** 推进一拍（t 秒）；画面有变化时返回 true */
  step(t: number): boolean {
    const dt = this.last ? Math.min(0.1, t - this.last) : 0
    this.last = t
    const s = this.state
    const visible = this.aimed && s.kind !== 'none'
    const changed = visible || this.wasVisible
    this.wasVisible = visible
    this.group.visible = visible
    if (!visible) return changed
    for (const o of [this.drop, this.halo, this.flash, ...this.trail, ...this.rings, ...this.puffs])
      o.visible = false
    this.away = false
    if (s.kind === 'coming') {
      const enter = this.alarm < 0 ? 0 : ENTER * ease(clamp01((t - this.alarm) / ENTER_SECONDS))
      const goal = Math.max(reach(s.progress), enter)
      this.shown += (goal - this.shown) * Math.min(1, dt * 2.5)
      this.showDrop(this.shown, 1, t)
    } else if (s.kind === 'broadcast') {
      const k = this.since < 0 ? 1 : clamp01((t - this.since) / 3.2)
      if (k < 1) {
        // 先顿一下，再掉头加速飞回高空，越飞越淡
        this.away = true
        this.showDrop(this.from * (1 - ease(k) * ease(k)), 1 - k, t)
      }
      this.showRings(t)
    } else if (this.since < 0) {
      this.showSmoke(t)
    } else {
      // 0.9 秒加速撞上去，白光 1.6 秒散开，之后一直冒烟
      const k = (t - this.since) / 0.9
      if (k < 1) this.showDrop(this.from + (1 - this.from) * k * k, 1, t)
      else {
        const f = (t - this.since - 0.9) / 1.6
        if (f < 1) this.showFlash(f)
        this.showSmoke(t)
      }
    }
    return true
  }

  private showDrop(p: number, opacity: number, t: number) {
    this.along(p, this.drop.position)
    ;(this.drop.material as THREE.SpriteMaterial).opacity = opacity
    this.drop.visible = true
    // 光晕轻轻呼吸
    this.halo.position.copy(this.drop.position)
    ;(this.halo.material as THREE.SpriteMaterial).opacity = opacity * (0.8 + 0.2 * Math.sin(t * 3))
    this.halo.visible = true
    // 身后一串光点：沿来路往回排，越远越小越淡
    this.trail.forEach((dot, k) => {
      const q = this.away ? p + (k + 1) * TRAIL_GAP : p - (k + 1) * TRAIL_GAP
      if (q < 0 || q > 1) return
      this.along(q, dot.position)
      dot.visible = opacity > 0.05
    })
  }

  private showFlash(k: number) {
    this.flash.position.copy(this.target)
    const size = 120 + FLASH * ease(clamp01(k * 1.6))
    this.flash.scale.set(size, size, 1)
    ;(this.flash.material as THREE.SpriteMaterial).opacity = 1 - clamp01(k)
    this.flash.visible = true
  }

  /** 引力波：从天线一圈圈往外扩，每 1.2 秒一圈 */
  private showRings(t: number) {
    this.rings.forEach((ring, k) => {
      const phase = (((t / 2.4 + k / 3) % 1) + 1) % 1
      ring.position.copy(this.target)
      const size = 80 + RING * phase
      ring.scale.set(size, size, 1)
      ;(ring.material as THREE.SpriteMaterial).opacity = 0.9 * (1 - phase)
      ring.visible = true
    })
  }

  /** 天线那里一直冒烟：几团烟从天线顶往上飘，飘高了淡掉再从底下冒出来 */
  private showSmoke(t: number) {
    this.puffs.forEach((puff, k) => {
      const phase = (((t / 4 + k / PUFFS) % 1) + 1) % 1
      puff.position.set(
        this.target.x + Math.sin(k * 2.1 + t * 0.6) * 40 + phase * 60,
        this.target.y - 120 + phase * 420,
        this.target.z - phase * 80
      )
      const size = 70 + phase * 160
      puff.scale.set(size, size, 1)
      ;(puff.material as THREE.SpriteMaterial).opacity = 0.85 * (1 - phase)
      puff.visible = true
    })
  }
}
