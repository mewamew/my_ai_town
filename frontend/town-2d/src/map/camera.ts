import { isCompact } from 'town-shared/platform'
import { PIXEL } from './grid'

/** 一个地图像素占几个设备像素。按钮、双击和捏合停下后只停整数倍，像素边缘清楚；
 *  看全貌的整图档和再缩小一档按容器算，见 levels()。鼠标滚轮按固定比例连续缩放，不落档 */
const STEPS = [1, 2, 3, 4, 5, 6, 8, 10, 12, 16]
/** 鼠标滚轮一格放大的倍数 */
const WHEEL_RATIO = 1.1
/** 滚轮缩放追目标的快慢：每过这么久，离目标的差剩 1/e，约三倍时长到位 */
const WHEEL_EASE_MS = 70
/** 打开地图时的近景：一个地图像素约占 3 个屏幕像素，与立体像素演示页的镜头距离相同；
 *  手机竖屏只有桌面三分之一宽，同样的距离只看得见广场一角，退到一半 */
const closeUpPixels = () => (isCompact() ? 1.5 : 3)
/** 换档动画的时长：按钮、双击，以及手势停下后落到整档 */
const ZOOM_MS = 180
/** 滚轮停这么久算这次缩放结束，落到整档 */
const WHEEL_SETTLE_MS = 160
/** 「界面动画：减少」或系统要求少动画时，缩放直接到位 */
const reducedMotion = () =>
  document.body.classList.contains('reduce-ui-motion') ||
  matchMedia('(prefers-reduced-motion: reduce)').matches

/** WebKit（mac 版、Safari）的触控板捏合事件；scale 是相对捏合开始时的倍数 */
interface GestureEvent extends UIEvent {
  scale: number
  clientX: number
  clientY: number
}

export interface CameraArea {
  x: number
  y: number
  width: number
  height: number
}

export class MapCamera {
  private readonly abort = new AbortController()
  private controls!: HTMLElement
  private readonly resize: ResizeObserver
  dispose() {
    this.stopZoomAnimation()
    this.abort.abort()
    this.resize.disconnect()
    this.controls.remove()
  }
  /** 实际视口，由中心、倍数和容器尺寸算出并对齐像素格 */
  private vb: number[] = [0, 0, 0, 0]
  private vb0: number[] = [0, 0, 0, 1]
  private center: [number, number] = [0, 0]
  private scale = 1
  /** 立体场景里地面随俯角倾斜，纵深在屏幕上缩成这个比例；平面地图为 1 */
  private vScale = 1
  private yaw = 0
  private yawSin = 0
  private yawCos = 1

  /** 地面世界坐标与旋转后的 SVG 坐标分开；平移和缩放在 SVG 坐标里进行。 */
  readonly project = ([x, y]: [number, number]): [number, number] => [
    x * this.yawCos - y * this.yawSin,
    x * this.yawSin + y * this.yawCos,
  ]

  readonly unproject = ([x, y]: [number, number]): [number, number] => [
    x * this.yawCos + y * this.yawSin,
    -x * this.yawSin + y * this.yawCos,
  ]

  setYaw(degrees: number) {
    if (degrees === this.yaw) return
    this.stopZoomAnimation()
    const world = this.unproject(this.center)
    this.yaw = degrees
    this.yawSin = Math.sin((degrees * Math.PI) / 180)
    this.yawCos = Math.cos((degrees * Math.PI) / 180)
    this.center = this.project(world)
    if (this.fitted) this.scale = this.fitScale()
    this.applyViewBox()
  }
  /** 处在「整图」状态：容器尺寸变化时重新按整图取倍数 */
  private fitted = true
  private zoomInBtn!: HTMLButtonElement
  private zoomOutBtn!: HTMLButtonElement
  private zoomReadout!: HTMLButtonElement
  private zoomValue!: HTMLSpanElement

  constructor(
    private svg: SVGSVGElement,
    private container: HTMLElement,
    initialView: number[],
    private onZoom: (zoom: number) => void,
    private onVillagerClick: (id: string) => void,
    private onPropClick: (id: string) => void = () => {},
    private onPromptClick: (id: string) => void = () => {},
    /** 点了空地：地面世界坐标，以及点在屏幕上的位置（摆道具的浮窗贴着它出现） */
    private onGroundClick: (point: [number, number], client: [number, number]) => void = () => {},
    private onGroupClick: (key: string, client: [number, number]) => void = () => {},
    /** 双指同向上下拖：屏幕像素位移，交给立体场景调俯角 */
    private onTilt: (dy: number) => void = () => {}
  ) {
    this.installZoomControls(container)
    this.installPanZoom(container, initialView)
    this.resize = new ResizeObserver(() => {
      if (!container.clientWidth || !container.clientHeight) return
      this.scale = this.fitted ? this.fitScale() : this.levels()[this.indexOf(this.scale)]
      this.applyViewBox()
    })
    this.resize.observe(container)
  }

  /** 被面板盖住的边（容器里的 CSS 像素）：手机的底部抽屉、宽屏的右侧面板。取景时这部分算看不见 */
  private insets = { top: 0, right: 0, bottom: 0, left: 0 }
  /** 露出来的那块变了：原来在那块中间的地方跟着挪到新那块的中间。抽屉拉高时看着的地方升到抽屉上方，
   *  收起后回到画面中间，不会停在抽屉打开时被挪到的上半屏 */
  setInsets(insets: { top: number; right: number; bottom: number; left: number }) {
    const [l0, t0, r0, b0] = this.openArea()
    this.insets = insets
    const [l1, t1, r1, b1] = this.openArea()
    const [w, h] = this.viewSize()
    const dx = ((l0 + r0 - l1 - r1) / 2) * w,
      dy = ((t0 + b0 - t1 - b1) / 2) * h
    if (!dx && !dy) return
    this.center = [this.center[0] + dx, this.center[1] + dy]
    this.applyViewBox()
  }

  /** 露出来的那块在视口里占的比例：左、上、右、下 */
  private openArea(): [number, number, number, number] {
    const r = this.container.getBoundingClientRect()
    const w = r.width || 1,
      h = r.height || 1
    const l = Math.min(this.insets.left / w, 0.8),
      t = Math.min(this.insets.top / h, 0.8)
    return [
      l,
      t,
      Math.max(l + 0.2, 1 - this.insets.right / w),
      Math.max(t + 0.2, 1 - this.insets.bottom / h),
    ]
  }

  /** 跟随用：仅当目标不在露出来的那块里（带边距）时，把它挪到那块的中间 */
  panTo(x: number, y: number) {
    const [px, py] = this.project([x, y])
    const [vx, vy, vw, vh] = this.vb
    const [l, t, r, b] = this.openArea()
    const left = vx + vw * l,
      right = vx + vw * r,
      top = vy + vh * t,
      bottom = vy + vh * b
    const mx = (right - left) * 0.12,
      my = (bottom - top) * 0.12
    // 头顶上还挂着名字和提示标签：上边至少留 80 个屏幕像素，不然名字会钻到上面的面板底下
    const perPixel = vh / (this.container.getBoundingClientRect().height || 1)
    const above = Math.max(my, 80 * perPixel)
    if (px >= left + mx && px <= right - mx && py >= top + above && py <= bottom - my) return
    this.lookAt(x, y)
  }

  /** 把世界点放到露出来的那块的中间（没有面板时就是画面中心），倍数不变。
   *  那块很矮时（弹出键盘）往下放一点，头顶上至少留 80 像素给名字 */
  lookAt(x: number, y: number) {
    ;[x, y] = this.project([x, y])
    const [w, h] = this.viewSize()
    const [l, t, r, b] = this.openArea()
    const minAbove = 80 / (this.container.getBoundingClientRect().height || 1)
    const fy = Math.min(b - 0.02, Math.max((t + b) / 2, t + minAbove))
    this.center = [x + (0.5 - (l + r) / 2) * w, y + (0.5 - fy) * h]
    this.fitted = false
    this.applyViewBox()
  }

  getViewBox(): number[] {
    return [...this.vb]
  }

  /** 按给定视口的中心取中心，按宽度取最接近的倍数 */
  setViewBox(v: number[]) {
    this.center = [v[0] + v[2] / 2, v[1] + v[3] / 2]
    this.scale = this.levels()[this.clampIndex(this.indexOf((this.size()[0] * PIXEL) / v[2]))]
    this.fitted = false
    this.applyViewBox()
  }

  /** 把一块地图装进面板之间的可见区域；先设置俯角，再按压缩后的地面高度取景。
   *  预设只在玩家点击时生效，之后仍可正常拖动与缩放。 */
  frameArea(area: CameraArea) {
    if (area.width <= 0 || area.height <= 0) return
    this.stopZoomAnimation()
    const [width, height] = this.size()
    const [left, top, right, bottom] = this.openArea()
    const c = Math.abs(this.yawCos),
      s = Math.abs(this.yawSin)
    const target = Math.min(
      (width * (right - left) * PIXEL) / (area.width * c + area.height * s),
      (height * (bottom - top) * PIXEL) / ((area.width * s + area.height * c) * this.vScale)
    )
    if (!Number.isFinite(target) || target <= 0) return
    // 预设按构图精确取景；向下取整档可能把视野放大一倍。手动缩放仍走原来的像素档位。
    this.scale = target
    const [vw, vh] = this.viewSize()
    const [cx, cy] = this.project([area.x + area.width / 2, area.y + area.height / 2])
    this.center = [cx + (0.5 - (left + right) / 2) * vw, cy + (0.5 - (top + bottom) / 2) * vh]
    this.fitted = false
    this.applyViewBox()
  }

  /** HD 场景加载后才提供街景与俯视入口；手机仍放在现有「俯角」弹层里。 */
  setViewPresets(presets: { label: string; title: string; apply: () => void }[]) {
    this.controls.querySelector('.map-view-presets')?.remove()
    const group = document.createElement('div')
    group.className = 'map-view-presets'
    group.setAttribute('role', 'group')
    group.setAttribute('aria-label', '取景方式')
    for (const preset of presets) {
      const button = document.createElement('button')
      button.type = 'button'
      button.textContent = preset.label
      button.title = preset.title
      button.addEventListener('click', preset.apply, { signal: this.abort.signal })
      group.append(button)
    }
    this.controls.querySelector('.map-pitch')?.after(group)
  }

  /** 150% 开始显示近景道具；回落保留 10% 余量，避免临界缩放来回闪换。 */
  private static DETAIL_ZOOM = 1.5
  private static DETAIL_EXIT_ZOOM = 1.35
  private detailVisible = false

  /** 纵深压缩比例变了：视口高度跟着变，SVG 按比例纵向压扁 */
  setVerticalScale(k: number) {
    if (k === this.vScale) return
    this.vScale = k
    this.svg.setAttribute('preserveAspectRatio', k === 1 ? 'xMidYMid meet' : 'none')
    if (this.fitted) this.scale = this.fitScale()
    this.applyViewBox()
  }

  /** 当前缩放倍率（1 = 整图 100%） */
  get zoom(): number {
    return this.vb0[2] / this.vb[2]
  }

  /** 近景：对准地图中心，倍数取最接近 closeUpPixels() 个屏幕像素的一档 */
  private closeUp() {
    this.scale =
      this.levels()[this.clampIndex(this.indexOf(closeUpPixels() * (window.devicePixelRatio || 1)))]
    this.center = this.project([this.vb0[0] + this.vb0[2] / 2, this.vb0[1] + this.vb0[3] / 2])
    this.fitted = false
    this.applyViewBox()
  }

  /** 回到整图：能装下整张图的最大倍数 */
  resetView() {
    this.scale = this.fitScale()
    this.center = this.project([this.vb0[0] + this.vb0[2] / 2, this.vb0[1] + this.vb0[3] / 2])
    this.fitted = true
    this.applyViewBox()
  }

  private size(): [number, number] {
    const r = this.container.getBoundingClientRect()
    const dpr = window.devicePixelRatio || 1
    return [r.width * dpr, r.height * dpr]
  }
  /** 整图刚好装进容器时的倍数 */
  private fitRatio() {
    const [w, h] = this.size()
    const c = Math.abs(this.yawCos),
      s = Math.abs(this.yawSin)
    return (
      Math.min(
        (w * PIXEL) / (this.vb0[2] * c + this.vb0[3] * s),
        (h * PIXEL) / ((this.vb0[2] * s + this.vb0[3] * c) * this.vScale)
      ) || 1
    )
  }
  /** 整图倍数不到 2 时一个地图像素还不到两个设备像素，不均匀看不出来，整图档直接取容器比例 */
  private levels() {
    const f = this.fitRatio()
    return f < 2 ? [f / 1.5, f, ...STEPS.filter((s) => s > f)] : STEPS
  }
  private fitScale() {
    const f = this.fitRatio()
    return f < 2 ? f : STEPS.filter((s) => s <= f).pop()!
  }
  /** 与倍数最接近的一档 */
  private indexOf(scale: number) {
    const levels = this.levels()
    let best = 0
    for (let i = 1; i < levels.length; i++)
      if (Math.abs(Math.log(levels[i] / scale)) < Math.abs(Math.log(levels[best] / scale))) best = i
    return best
  }
  /** 最多比整图再缩小一档 */
  private clampIndex(i: number) {
    const low = Math.max(0, this.indexOf(this.fitScale()) - 1)
    return Math.max(low, Math.min(this.levels().length - 1, i))
  }
  /** 从现在的倍数换 steps 档后的倍数；正在换档时从要去的那档接着算，连按、连滚不会少走 */
  private stepped(steps: number) {
    const from = this.zoomTarget ?? this.scale
    return this.levels()[this.clampIndex(this.indexOf(from) + steps)]
  }

  /**
   * 手势停下时落到哪一档：几乎没动就回到开始那档；不然在缩放的方向上取离现在最近的一档，
   * 至少挪一档。张开一点点也会放大一档，不会被弹回去；张开很多就停在最接近的那档。
   */
  private settled(start: number, current: number) {
    const levels = this.levels()
    const from = levels[this.indexOf(start)]
    const change = Math.log(current / start)
    if (Math.abs(change) < 0.03) return from
    const allowed = levels.slice(this.clampIndex(0), this.clampIndex(Infinity) + 1)
    const ahead = allowed.filter((l) => (change > 0 ? l > from : l < from))
    if (!ahead.length) return from
    const gap = (l: number) => Math.abs(Math.log(l / current))
    return ahead.reduce((best, l) => (gap(l) < gap(best) ? l : best))
  }

  /** 进行中的缩放动画和它要去的倍数；拖动、捏合一开始就停掉它 */
  private zoomAnimation = 0
  private zoomTarget: number | undefined
  /** 滚轮缩放正在追的倍数、不动点（视图坐标 + 屏幕坐标）和上一帧的时间 */
  private wheel: { target: number; anchor: [number, number, number, number]; last: number } | null =
    null
  private stopZoomAnimation() {
    cancelAnimationFrame(this.zoomAnimation)
    this.zoomAnimation = 0
    this.zoomTarget = undefined
    this.wheel = null
  }

  /**
   * 缓动到倍数 target（按对数插值，放大缩小一样匀）。给了 anchor 就保持那个世界点在那个屏幕点下不动，
   * 给了 center 就同时把画面中心移过去。
   */
  private animateZoom(
    target: number,
    to: { anchor: [number, number, number, number] } | { center: [number, number] }
  ) {
    this.stopZoomAnimation()
    this.zoomTarget = target
    const from = this.scale,
      center0 = [...this.center] as [number, number]
    const frame = (t: number) => {
      const scale = from * (target / from) ** t
      if ('anchor' in to) {
        this.scaleAround(scale, ...to.anchor)
        return
      }
      this.scale = scale
      this.fitted = false
      this.center = [
        center0[0] + (to.center[0] - center0[0]) * t,
        center0[1] + (to.center[1] - center0[1]) * t,
      ]
      this.applyViewBox()
    }
    if (reducedMotion()) {
      frame(1)
      this.zoomTarget = undefined
      return
    }
    const start = performance.now()
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / ZOOM_MS)
      frame(1 - (1 - t) ** 3)
      this.zoomAnimation = t < 1 ? requestAnimationFrame(tick) : 0
      if (t >= 1) this.zoomTarget = undefined
    }
    this.zoomAnimation = requestAnimationFrame(tick)
  }

  /** 换 steps 档，保持屏幕点 (cx, cy) 下的地方不动（按钮以画面中心为准） */
  private zoomAt(steps: number, cx: number, cy: number) {
    const [wx, wy] = this.clientToView(cx, cy)
    this.animateZoom(this.stepped(steps), { anchor: [wx, wy, cx, cy] })
  }

  /**
   * 鼠标滚轮转了 notches 格（正数放大），保持屏幕点 (cx, cy) 下的地方不动。每格的倍数一样，目标连乘；
   * 画面每帧按指数追向目标，连着滚只是把目标往前推，动画不重新起步，停在哪就是哪。
   */
  private wheelZoom(notches: number, cx: number, cy: number) {
    const levels = this.levels()
    const base = this.wheel?.target ?? this.zoomTarget ?? this.scale
    const target = Math.max(
      levels[this.clampIndex(0)],
      Math.min(levels.at(-1)!, base * WHEEL_RATIO ** notches)
    )
    const anchor: [number, number, number, number] = [...this.clientToView(cx, cy), cx, cy]
    if (reducedMotion()) {
      this.stopZoomAnimation()
      this.scaleAround(target, ...anchor)
      return
    }
    this.zoomTarget = target
    if (this.wheel) {
      this.wheel.target = target
      this.wheel.anchor = anchor
      return
    }
    cancelAnimationFrame(this.zoomAnimation)
    this.wheel = { target, anchor, last: performance.now() }
    const tick = (now: number) => {
      const w = this.wheel
      if (!w) return
      const gap = Math.log(w.target / this.scale)
      const done = Math.abs(gap) < 0.002
      const k = 1 - Math.exp(-Math.max(0, now - w.last) / WHEEL_EASE_MS)
      w.last = now
      this.scaleAround(done ? w.target : this.scale * Math.exp(gap * k), ...w.anchor)
      if (done) this.stopZoomAnimation()
      else this.zoomAnimation = requestAnimationFrame(tick)
    }
    this.zoomAnimation = requestAnimationFrame(tick)
  }

  /** 换 steps 档，并把世界点 (wx, wy) 移到画面中心（双击） */
  private zoomCenter(steps: number, wx: number, wy: number) {
    this.animateZoom(this.stepped(steps), { center: [wx, wy] })
  }

  private viewSize(): [number, number] {
    const [w, h] = this.size()
    if (!w || !h) return [this.vb0[2], this.vb0[3]]
    const unit = PIXEL / this.scale
    return [w * unit, (h * unit) / this.vScale]
  }

  /** 屏幕上一点下面的地面世界坐标 */
  groundAt(cx: number, cy: number): [number, number] {
    return this.unproject(this.clientToView(cx, cy))
  }

  /** 屏幕坐标 → 旋转后的视图坐标。走 SVG 自己的 CTM，preserveAspectRatio 留白也算得准 */
  private clientToView(cx: number, cy: number): [number, number] {
    const matrix = this.svg.getScreenCTM()
    if (!matrix) return [cx, cy]
    const p = new DOMPoint(cx, cy).matrixTransform(matrix.inverse())
    return [p.x, p.y]
  }

  /** 视口宽高与容器的设备像素成整数比，左上角对齐到一个设备像素，地图像素就落在设备像素格上 */
  private applyViewBox() {
    const [w, h] = this.viewSize()
    const unit = PIXEL / this.scale
    const snap = (v: number, u: number) => (this.scale >= 1 ? Math.round(v / u) * u : v)
    this.vb = [
      snap(this.center[0] - w / 2, unit),
      snap(this.center[1] - h / 2, unit / this.vScale),
      w,
      h,
    ]
    this.svg.setAttribute('viewBox', this.vb.join(' '))
    const z = this.zoom
    this.detailVisible =
      z >= (this.detailVisible ? MapCamera.DETAIL_EXIT_ZOOM : MapCamera.DETAIL_ZOOM)
    this.svg.classList.toggle('zoom-detail', this.detailVisible)
    this.onZoom(z)
    this.zoomValue.textContent = `${Math.round(z * 100)}%`
    this.zoomReadout.classList.toggle('on', !this.fitted)
    const i = this.indexOf(this.scale)
    this.zoomInBtn.disabled = i >= this.clampIndex(Infinity)
    this.zoomOutBtn.disabled = i <= this.clampIndex(0)
  }

  /** 右下角缩放钮：+ / 「整图」（点了回到整图）/ − 。按钮缩放以画面中心为不动点。
   *  百分比只给读屏和悬停提示，不显示在按钮上：玩家用不着这个数 */
  private installZoomControls(mapEl: HTMLElement) {
    const box = document.createElement('div')
    this.controls = box
    box.className = 'map-zoom'
    box.setAttribute('role', 'group')
    box.setAttribute('aria-label', '地图缩放')
    const button = (text: string, title: string, onClick: () => void) => {
      const b = document.createElement('button')
      b.type = 'button'
      b.textContent = text
      b.title = title
      b.onclick = onClick
      box.appendChild(b)
      return b
    }
    /** 画面中心的屏幕坐标 */
    const center = (): [number, number] => {
      const r = this.container.getBoundingClientRect()
      return [r.left + r.width / 2, r.top + r.height / 2]
    }
    this.zoomInBtn = button('+', '放大', () => this.zoomAt(1, ...center()))
    this.zoomInBtn.setAttribute('aria-label', '放大')
    this.zoomReadout = button('', '回到整图', () => this.resetView())
    this.zoomReadout.className = 'zoom-readout'
    const caption = document.createElement('small')
    caption.textContent = '整图'
    this.zoomValue = document.createElement('span')
    this.zoomValue.className = 'zoom-value'
    this.zoomValue.textContent = '100%'
    this.zoomReadout.append(caption, this.zoomValue)
    this.zoomOutBtn = button('−', '缩小', () => this.zoomAt(-1, ...center()))
    this.zoomOutBtn.setAttribute('aria-label', '缩小')
    // 按钮上的按下 / 双击不能漏给地图：否则会被当成拖拽起点（指针被地图捕获，click 就丢了）或双击放大
    for (const type of ['pointerdown', 'dblclick'] as const) {
      box.addEventListener(type, (ev) => ev.stopPropagation())
    }
    mapEl.appendChild(box)
  }

  private installPanZoom(mapEl: HTMLElement, vb0: number[]) {
    this.vb = [...vb0]
    this.vb0 = [...vb0]
    this.installWheelZoom(mapEl)
    this.installDrag(mapEl)
    this.closeUp()
  }

  /**
   * 滚轮和触控板，都以指针处为不动点：鼠标滚轮（见 wheelNotches）每格放大同样倍数，平滑追过去，不落档；
   * 触控板捏合和双指滑动（数值小、一串连着来）跟着手连续缩放，停下来再缓动到一档整倍数（像素边缘清楚）。
   * 原来攒够一格滚动才跳一档，触控板捏合时张开半天没反应、然后突然大一截。
   * 双击：以点击处为画面中心放大两档。
   */
  private installWheelZoom(mapEl: HTMLElement) {
    const signal = this.abort.signal
    /** 这次缩放开始时的倍数和最近的指针位置；停下来时按它决定落到哪一档 */
    let gesture: { start: number; x: number; y: number } | null = null
    let settle = 0
    /** WebKit 的捏合事件正在进行：同一次捏合不再按滚轮算第二遍 */
    let pinching = false
    let pinch0 = 1
    const begin = (x: number, y: number) => {
      this.stopZoomAnimation()
      gesture ??= { start: this.scale, x, y }
      gesture.x = x
      gesture.y = y
    }
    const zoomTo = (scale: number, x: number, y: number) => {
      const [wx, wy] = this.clientToView(x, y)
      this.scaleAround(scale, wx, wy, x, y)
    }
    const finish = () => {
      window.clearTimeout(settle)
      const g = gesture
      gesture = null
      if (!g) return
      const [wx, wy] = this.clientToView(g.x, g.y)
      this.animateZoom(this.settled(g.start, this.scale), { anchor: [wx, wy, g.x, g.y] })
    }
    mapEl.addEventListener(
      'wheel',
      (ev) => {
        ev.preventDefault()
        if (pinching) return
        const notches = wheelNotches(ev)
        if (notches !== undefined && !gesture) {
          if (notches) this.wheelZoom(notches, ev.clientX, ev.clientY)
          return
        }
        begin(ev.clientX, ev.clientY)
        // 行、页换成像素；捏合（ctrlKey）每次的数值小，给得灵敏些；一次最多变 1.6 倍，猛滑也不跳太远
        const pixels =
          ev.deltaY * (ev.deltaMode === 1 ? 16 : ev.deltaMode === 2 ? this.size()[1] || 800 : 1)
        const amount = Math.max(-0.5, Math.min(0.5, pixels * (ev.ctrlKey ? 0.01 : 0.002)))
        zoomTo(this.scale * Math.exp(-amount), ev.clientX, ev.clientY)
        window.clearTimeout(settle)
        settle = window.setTimeout(finish, WHEEL_SETTLE_MS)
      },
      { passive: false, signal }
    )
    // mac 版（WKWebView）和 Safari 的触控板捏合
    mapEl.addEventListener(
      'gesturestart',
      (ev) => {
        ev.preventDefault()
        const e = ev as GestureEvent
        pinching = true
        begin(e.clientX, e.clientY)
        pinch0 = this.scale
      },
      { signal }
    )
    mapEl.addEventListener(
      'gesturechange',
      (ev) => {
        ev.preventDefault()
        const e = ev as GestureEvent
        if (!pinching || !e.scale) return
        begin(e.clientX, e.clientY)
        zoomTo(pinch0 * e.scale, e.clientX, e.clientY)
      },
      { signal }
    )
    mapEl.addEventListener(
      'gestureend',
      (ev) => {
        ev.preventDefault()
        pinching = false
        finish()
      },
      { signal }
    )
    mapEl.addEventListener(
      'dblclick',
      (ev) => {
        // 手指双击由手势那边处理，浏览器补发的 dblclick 不再放大一次
        if (performance.now() - this.lastTouch < 800) return
        const [wx, wy] = this.clientToView(ev.clientX, ev.clientY)
        this.zoomCenter(2, wx, wy)
      },
      { signal }
    )
  }

  /** 最近一次手指按下的时间：用来分辨 dblclick 是不是手指双击补发的 */
  private lastTouch = -Infinity

  /** 连续缩放到 scale（设备像素/地图像素），保持客户端坐标 (cx, cy) 下的世界点 (wx, wy) 不动 */
  private scaleAround(scale: number, wx: number, wy: number, cx: number, cy: number) {
    const levels = this.levels()
    this.scale = Math.max(levels[this.clampIndex(0)], Math.min(levels.at(-1)!, scale))
    this.fitted = false
    const r = this.container.getBoundingClientRect()
    const fx = r.width ? (cx - r.left) / r.width : 0.5,
      fy = r.height ? (cy - r.top) / r.height : 0.5
    const [nw, nh] = this.viewSize()
    this.center = [wx - (fx - 0.5) * nw, wy - (fy - 0.5) * nh]
    this.applyViewBox()
  }

  /**
   * 单指（或鼠标左键）拖动平移；单击选人 / 选道具 / 点空地：抬起时位移不超过容差才算点击
   * （鼠标 5px，手指 10px）。手指另有：双指捏合连续缩放、松手时落到最近一档；双指同向上下拖调俯角；
   * 双击放大两档。
   */
  private installDrag(mapEl: HTMLElement) {
    const signal = this.abort.signal
    const pointers = new Map<number, { x: number; y: number; touch: boolean }>()
    let drag: [number, number] | null = null
    let down: {
      pos: [number, number]
      /** 点击容差：鼠标 5px，手指 10px */
      slop: number
      /** 平移的起步距离：鼠标一动就平移（与原来一样），手指过了容差才算拖 */
      dead: number
      moved: boolean
      vid: string | null
      prop: string | null
      prompt: string | null
      group: string | null
    } | null = null
    /** 双指手势：起点距离、中点与那时中点下的世界点；mode 由最初的移动决定。
     *  start 是两指刚放下时的倍数（松手时按它决定落到哪一档），mid 是最近的中点 */
    let pair: {
      d0: number
      y0: number
      scale0: number
      start: number
      world: [number, number]
      mid: [number, number]
      mode: 'pinch' | 'tilt' | null
    } | null = null
    let lastTap: { t: number; x: number; y: number } | null = null
    const twoPoints = () => [...pointers.values()].slice(0, 2)
    const startPair = () => {
      const [a, b] = twoPoints()
      const mx = (a.x + b.x) / 2,
        my = (a.y + b.y) / 2
      pair = {
        d0: Math.hypot(a.x - b.x, a.y - b.y) || 1,
        y0: my,
        scale0: this.scale,
        start: this.scale,
        world: this.clientToView(mx, my),
        mid: [mx, my],
        mode: null,
      }
    }
    const endPair = () => {
      if (pair?.mode === 'pinch') {
        // 松手缓动到一档整倍数，最后的中点不动（这时已经少了一根手指，中点用记下的）
        const [mx, my] = pair.mid
        const [wx, wy] = this.clientToView(mx, my)
        this.animateZoom(this.settled(pair.start, this.scale), { anchor: [wx, wy, mx, my] })
      }
      pair = null
    }
    mapEl.addEventListener(
      'pointerdown',
      (ev) => {
        // 只有左键拖动平移；右键留给立体场景调俯角
        if (ev.button !== 0) return
        this.stopZoomAnimation()
        const touch = ev.pointerType === 'touch'
        if (touch) this.lastTouch = performance.now()
        pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY, touch })
        try {
          mapEl.setPointerCapture(ev.pointerId)
        } catch {
          // 指针已经抬起（极快的点按）时捕获会失败，照常处理
        }
        if (pointers.size === 2) {
          // 第二根手指：不再算点击，改成双指手势
          down = null
          drag = null
          startPair()
          return
        }
        if (pointers.size > 2) return
        drag = [ev.clientX, ev.clientY]
        down = {
          pos: [ev.clientX, ev.clientY],
          slop: touch ? 10 : 5,
          dead: touch ? 10 : 0,
          moved: false,
          vid: hitAttribute(ev.target, 'data-vid'),
          prop: hitAttribute(ev.target, 'data-prop-id'),
          prompt: hitAttribute(ev.target, 'data-prompt'),
          group: hitAttribute(ev.target, 'data-group'),
        }
        mapEl.classList.add('drag')
      },
      { signal }
    )
    mapEl.addEventListener(
      'pointermove',
      (ev) => {
        const p = pointers.get(ev.pointerId)
        if (!p) return
        p.x = ev.clientX
        p.y = ev.clientY
        if (pair && pointers.size >= 2) {
          const [a, b] = twoPoints()
          const d = Math.hypot(a.x - b.x, a.y - b.y)
          const mx = (a.x + b.x) / 2,
            my = (a.y + b.y) / 2
          if (!pair.mode) {
            if (Math.abs(d - pair.d0) > 16) {
              // 认出是捏合后从这里重新起算，不会一下补上开头那 16 像素，画面跳一下
              pair.mode = 'pinch'
              pair.d0 = d
              pair.scale0 = this.scale
              pair.world = this.clientToView(mx, my)
            } else if (Math.abs(my - pair.y0) > 14) pair.mode = 'tilt'
            else return
          }
          pair.mid = [mx, my]
          if (pair.mode === 'pinch') {
            this.scaleAround(pair.scale0 * (d / pair.d0), pair.world[0], pair.world[1], mx, my)
          } else {
            // 往下拖更接近正俯视，与右键拖动一致
            this.onTilt(my - pair.y0)
            pair.y0 = my
          }
          return
        }
        if (!drag) return
        if (down && !down.moved) {
          const dist = Math.hypot(ev.clientX - down.pos[0], ev.clientY - down.pos[1])
          if (dist <= down.dead) return
          if (dist > down.slop) down.moved = true
        }
        const m = this.svg.getScreenCTM() // a / d 即屏幕像素 ↔ 世界单位的比例
        if (!m) return
        this.center[0] -= (ev.clientX - drag[0]) / m.a
        this.center[1] -= (ev.clientY - drag[1]) / m.d
        this.fitted = false
        drag = [ev.clientX, ev.clientY]
        this.applyViewBox()
      },
      { signal }
    )
    const release = (ev: PointerEvent) => {
      const p = pointers.get(ev.pointerId)
      if (!p) return
      pointers.delete(ev.pointerId)
      if (pair) {
        if (pointers.size < 2) {
          endPair()
          // 剩下的那根手指接着平移，不算点击
          const [rest] = pointers.values()
          drag = rest ? [rest.x, rest.y] : null
          down = null
        }
        if (!pointers.size) mapEl.classList.remove('drag')
        return
      }
      if (pointers.size) return
      drag = null
      mapEl.classList.remove('drag')
      const d = down
      down = null
      if (ev.type !== 'pointerup' || !d) return
      const click = !d.moved && Math.hypot(ev.clientX - d.pos[0], ev.clientY - d.pos[1]) <= d.slop
      if (!click) return
      // 手指双击空地：以那里为中心放大两档
      const now = performance.now()
      const target = d.prompt || d.group || d.vid || d.prop
      if (p.touch && !target) {
        if (
          lastTap &&
          now - lastTap.t < 320 &&
          Math.hypot(ev.clientX - lastTap.x, ev.clientY - lastTap.y) < 30
        ) {
          lastTap = null
          const [wx, wy] = this.clientToView(ev.clientX, ev.clientY)
          this.zoomCenter(2, wx, wy)
          return
        }
        lastTap = { t: now, x: ev.clientX, y: ev.clientY }
      }
      if (d.prompt) this.onPromptClick(d.prompt)
      else if (d.group) this.onGroupClick(d.group, [ev.clientX, ev.clientY])
      else if (d.vid) this.onVillagerClick(d.vid)
      else if (d.prop) this.onPropClick(d.prop)
      else this.onGroundClick(this.groundAt(ev.clientX, ev.clientY), [ev.clientX, ev.clientY])
    }
    mapEl.addEventListener('pointerup', release, { signal })
    mapEl.addEventListener('pointercancel', release, { signal })
  }
}

/**
 * 鼠标滚轮这一下往上滚了几格（往下为负）；触控板和捏合返回 undefined。按行、按页滚，或一次数值够大，算滚轮。
 * mac 上的 Chrome 给滚轮加速，慢慢滚一格 deltaY 只有 4，和触控板一样小；被当成触控板时一格只缩不到 1%，
 * 停下后又弹回原档。它的旧属性 wheelDeltaY 在滚轮上总是按格数给 120 的整数倍（触控板是 deltaY 的 -3 倍，
 * 能凑成 120 倍时 deltaY 已过 40），凭这个认出来，也按它数格：滚得快时一下有两三格。
 */
function wheelNotches(ev: WheelEvent): number | undefined {
  if (ev.ctrlKey) return undefined
  const legacy = (ev as WheelEvent & { wheelDeltaY?: number }).wheelDeltaY ?? 0
  const counted = legacy !== 0 && legacy % 120 === 0
  if (!counted && ev.deltaMode === 0 && Math.abs(ev.deltaY) < 40) return undefined
  return -Math.sign(ev.deltaY) * (counted ? Math.min(3, Math.abs(legacy) / 120) : 1)
}

/** 事件目标向上找带某属性的祖先，返回属性值 */
function hitAttribute(target: EventTarget | null, attribute: string): string | null {
  if (!(target instanceof Element)) return null
  return target.closest(`[${attribute}]`)?.getAttribute(attribute) ?? null
}
