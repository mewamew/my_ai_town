import * as THREE from 'three'
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js'
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js'
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js'
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js'
import type { Atlas } from 'town-shared/mapDocument'
import type { DecorPlan } from '../decor'
import { fromPx, MARGIN, OUTDOOR_SPACE, PIXEL, pxIndex, roomPoint } from '../grid'
import { WALL_CAP } from '../palette'
import { OPEN, paintGround, treeShape, type Ground } from '../pixel/terrain'
import type { Dock } from '../pixel/island'
import { fbm, rng } from '../pixel/noise'
import { Motes } from './motes'
import { Villagers, type VillagerPlacement } from './villagers'
import { VILLAGER_HALF } from './villagerSprite'
import { Weather3D } from './weather'
import { DOORS } from '../buildings'
import type { WeatherKind } from 'town-shared/weather/types'
import {
  DEFAULT_PITCH,
  PITCH_MAX,
  PITCH_MIN,
  WALL_TEXEL,
  houseOf,
  houseTop,
  tiltOf,
  type House,
  type Tilt,
} from './layout'
import {
  chimneyCanvas,
  glowCanvas,
  lampCanvas,
  awningCanvas,
  flagCanvas,
  gableCanvases,
  roofCanvas,
  treeCanvas,
  wallBase,
  wallCanvases,
} from './textures'
import { OVERHANG, chimneySpot, gableGeometry, roofHeight, roofParts } from './roofs'
import { gradeShader, SceneDepthPass, TILT_FOCUS, tiltShader } from './post'
import { landmarkSprites } from './landmarks'
import { coastTexture, outerMaterial, surfOnLand } from './sea'
import { Horizon } from './horizon'
import { ChimneySmoke } from './smoke'
import { interior, interiorTop, keepInside } from './interior'
import type { Partition } from './partition'
import { PROP_BASE, PropStandees, type PropPlacement } from './props'
import { colonnadeFront, lighthouseTower, vaultRoof } from './structures'
import { onStandee, stand, standee, texture } from './standee'
import type { MapTheme } from '../themes/types'
import { effectiveQuality, pixelRatioCap, type Quality } from 'town-shared/quality'

// 立体像素场景：垫在 SVG 下面，镜头跟着 SVG 的视口走。
// 世界坐标：x 同地图，z = 地图 y，y 向上为高度。镜头按俯角倾斜；树、路灯、村民这些立牌按俯角转向镜头。

/** 俯角存在浏览器里，选择地图、建镇预览和游戏共用 */
const PITCH_KEY = 'town-2d:hd-pitch'
const YAW_KEY = 'town-2d:hd-yaw'
/** 右键上下拖动时每个屏幕像素改变的俯角（度） */
const PITCH_PER_PIXEL = 0.2
const YAW_PER_PIXEL = 0.3
const normalizeYaw = (degrees: number) => ((degrees % 360) + 360) % 360
const smooth = (a: number, b: number, x: number) => {
  const t = Math.max(0, Math.min(1, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}
const lerp = (a: number, b: number, t: number) => a + (b - a) * t
/** 屋顶夜里的微光强度（自身颜色的倍数） */
const ROOF_NIGHT_GLOW = 0.3
/** 没有世界时钟时（选择地图、建镇预览）按傍晚打光 */
const PREVIEW_HOUR = 17
/** 环境动画的节拍（毫秒）：约每秒 30 拍；比 1000/30 少一点，60Hz 屏上正好隔一帧一拍 */
const BEAT_MS = 30
/** 雾气浓度与镜头距离，按演示页换算：演示页一个单位是一个地图像素 */
const FOG_DENSITY = 0.00042 / PIXEL
const CAMERA_DISTANCE_PER_VIEW_HEIGHT = 2.17
/** 雾只在近景起作用：镜头距离最远取演示页默认的 600 个地图像素，拉远看全图时雾不再加浓 */
const MAX_CAMERA_DISTANCE = 600 * PIXEL
/** 移轴模糊按近景设计：视野高度超过这么多地图单位后按比例减弱，拉远时不把上下两片糊掉 */
const TILT_SHIFT_VIEW_HEIGHT = 2000
/** 路灯里带真实点光源的数量，其余只有光晕 */
const LIT_LAMPS = 12
/** 路灯点光源的照亮半径：90 个地图像素 */
const LAMP_REACH = 90 * PIXEL

function storedPitch() {
  try {
    const v = Number(localStorage.getItem(PITCH_KEY))
    return Number.isFinite(v) && v >= PITCH_MIN && v <= PITCH_MAX ? v : DEFAULT_PITCH
  } catch {
    return DEFAULT_PITCH
  }
}

function storedYaw() {
  try {
    const value = Number(localStorage.getItem(YAW_KEY))
    return Number.isFinite(value) ? normalizeYaw(value) : 0
  } catch {
    return 0
  }
}

/** WebGL 渲染器：像素风不抗锯齿，开阴影和色调映射；画布垫在 SVG 下面 */
function createRenderer(container: HTMLElement, svg: SVGSVGElement) {
  const renderer = new THREE.WebGLRenderer({ antialias: false })
  const canvas = renderer.domElement
  canvas.className = 'hd2d-canvas'
  renderer.setPixelRatio(Math.min(devicePixelRatio, pixelRatioCap(effectiveQuality())))
  renderer.shadowMap.enabled = true
  renderer.shadowMap.type = THREE.PCFShadowMap
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  container.insertBefore(canvas, svg)
  return renderer
}

/** 后期：保留场景深度，泛光，横竖两遍景深与边缘模糊，调色，最后输出 */
function createComposer(
  renderer: THREE.WebGLRenderer,
  scene: THREE.Scene,
  camera: THREE.OrthographicCamera
) {
  const composer = new EffectComposer(renderer)
  const sceneDepth = new SceneDepthPass(scene, camera)
  composer.addPass(sceneDepth)
  const bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.5, 0.5, 0.85)
  composer.addPass(bloom)
  const tiltShift = [new ShaderPass(tiltShader), new ShaderPass(tiltShader)]
  tiltShift[1].uniforms.dir.value.set(0, 1)
  for (const p of tiltShift) {
    p.uniforms.tDepth.value = sceneDepth.depthTexture
    composer.addPass(p)
  }
  const grade = new ShaderPass(gradeShader)
  composer.addPass(grade)
  composer.addPass(new OutputPass())
  return { composer, sceneDepth, bloom, tiltShift, grade }
}

export class HdScene {
  readonly houses: House[]
  private readonly renderer: THREE.WebGLRenderer
  private readonly scene = new THREE.Scene()
  private readonly camera = new THREE.OrthographicCamera()
  private readonly composer: EffectComposer
  private readonly sceneDepth: SceneDepthPass
  private readonly bloom: UnrealBloomPass
  private readonly tiltShift: ShaderPass[]
  private readonly grade: ShaderPass
  private readonly sun = new THREE.DirectionalLight('#fff4e0', 2.6)
  /** 天光：颜色和强度由 applyLight 按风格包和时间设置 */
  private readonly hemi = new THREE.HemisphereLight()
  private readonly houseGroups = new Map<string, THREE.Group>()
  /** 掀开后的室内墙，和房子外壳一一对应 */
  private readonly rooms = new Map<string, THREE.Group>()
  private readonly partitions = new Map<string, Partition | undefined>()
  private pitchDegrees = storedPitch()
  private yawDegrees = storedYaw()
  private tilt: Tilt = tiltOf(this.pitchDegrees, this.yawDegrees)
  /** 地面、水面和房子 */
  private readonly flat = new THREE.Group()
  /** 立牌和挂在立牌上的光：俯角变了按这些函数重新摆 */
  private readonly upright: ((tilt: Tilt) => void)[] = []
  private readonly center: [number, number]
  /** 当前视野高度（地图单位），决定雾和移轴模糊的强弱 */
  private viewHeight = TILT_SHIFT_VIEW_HEIGHT
  /** 地图上下被面板盖住的高度（CSS 像素）：移轴的清晰带对准露出来的那块 */
  private focusInsets: readonly [number, number] = [0, 0]
  private readonly abort = new AbortController()
  private pitchControl?: HTMLElement
  /** 俯角变化后通知地图，屋顶上的房间名要跟着挪 */
  onTilt: (() => void) | null = null
  private readonly glowing: THREE.Material[] = []
  /** 屋顶、山墙和墙顶：夜里按自身颜色发一点微光，房子不至于黑成一片 */
  private readonly moonlit: (THREE.MeshLambertMaterial | THREE.MeshPhongMaterial)[] = []
  private readonly glows: THREE.Sprite[] = []
  private readonly lampLights: THREE.PointLight[] = []
  /** 灯塔转动的光束（冰雪风格） */
  private readonly beams: THREE.Mesh[] = []
  private readonly smoke = new ChimneySmoke()
  /** 逐帧动画的地标（喷泉）：图集横排，按时间挪贴图的横向偏移 */
  private readonly flipbooks: { maps: THREE.Texture[]; frames: number; fps: number }[] = []
  /** 自己发一点光的地标（喷泉的水），亮度随昼夜变 */
  private readonly selfLit: THREE.MeshLambertMaterial[] = []
  /** 海面动画的时间（秒） */
  private readonly seaTime: { value: number }
  /** 海面闪光的多少：晴天白天多，夜里和阴天少 */
  private readonly seaSparkle: { value: number }
  private readonly horizon: Horizon
  private readonly observers: { disconnect(): void }[] = []
  private readonly reduceMotion = matchMedia('(prefers-reduced-motion: reduce)')
  private frame = 0
  private ticker = 0
  /** 天光、立牌显隐这类环境变化等下一个节拍再画，不在两拍之间插一帧 */
  private ambient = false
  private hour = PREVIEW_HOUR
  /** 上次 setClock 的时间和天气 */
  private clock = ''
  private readonly weather: Weather3D
  /** 白天的程度，天气粒子按它显隐 */
  private day = 1
  /** 场景的雾，颜色由 applyLight 跟着天色改 */
  private readonly fog: THREE.FogExp2
  private readonly motes: Motes
  private readonly villagers = new Villagers(this.scene, this.tilt)
  private readonly props = new PropStandees(this.scene, this.tilt, () => this.request())
  private lastTick = performance.now()

  private readonly theme: MapTheme

  /** ground 是这张地图算好的地面（pixel/terrain.ts 的 groundOf），场景只读它 */
  constructor(
    atlas: Atlas,
    ground: Ground,
    private container: HTMLElement,
    private svg: SVGSVGElement
  ) {
    const { seed, decor, theme } = ground
    this.theme = theme
    this.renderer = createRenderer(container, svg)
    this.scene.add(this.flat)
    this.center = [atlas.canvas.width / 2, atlas.canvas.height / 2]

    this.fog = new THREE.FogExp2(theme.light.sky.day, FOG_DENSITY * theme.light.fog)
    this.weather = new Weather3D(this.scene, this.flat, ground, seed)
    this.horizon = new Horizon(
      this.scene,
      { x0: fromPx(0), z0: fromPx(0), x1: fromPx(ground.width), z1: fromPx(ground.height) },
      seed,
      theme.islet
    )
    this.upright.push((t) => this.horizon.setTilt(t))
    this.scene.add(this.smoke.group)
    this.upright.push((t) => this.smoke.setTilt(t))
    const sea = this.addGround(ground)
    this.seaTime = sea.time
    this.seaSparkle = sea.sparkle
    this.houses = atlas.spaces.filter((s) => s.id !== OUTDOOR_SPACE).map((s) => houseOf(s, theme))
    const glowMap = new THREE.CanvasTexture(glowCanvas())
    glowMap.colorSpace = THREE.SRGBColorSpace
    this.addHouses(atlas, glowMap)
    // 地标立牌和散落物先占地，剩下的空地再撒树、放微粒
    const open = this.placeStandees(atlas, ground, seed)
    const clear = { width: ground.width, height: ground.height, open }
    this.addTrees(decor, clear, seed)
    this.addLamps(atlas, ground.wet, ground.width, glowMap)
    this.motes = new Motes(clear, seed, theme.motes)
    this.scene.add(this.motes.points)
    this.scene.fog = this.fog
    this.setupSun(atlas)
    const post = createComposer(this.renderer, this.scene, this.camera)
    this.composer = post.composer
    this.sceneDepth = post.sceneDepth
    this.bloom = post.bloom
    this.tiltShift = post.tiltShift
    this.grade = post.grade
    const views = new MutationObserver(() => this.readView())
    views.observe(svg, { attributes: true, attributeFilter: ['viewBox'] })
    const sizes = new ResizeObserver(() => this.resize())
    sizes.observe(container)
    this.observers.push(views, sizes)
    this.ticker = requestAnimationFrame(this.loop)
    this.setQuality(effectiveQuality())
    this.installPitchControls()
    this.applyTilt()
    this.resize()
    this.applyLight()
  }

  /** 每栋房子的外壳和室内，门口一团暖光；屋里的落脚点和家具换到世界坐标，隔墙按它们的分布砌 */
  private addHouses(atlas: Atlas, glowMap: THREE.Texture) {
    for (const s of atlas.spaces) {
      if (s.id === OUTDOOR_SPACE) continue
      const points = [...atlas.stations, ...atlas.props]
        .filter((p) => p.space === s.id)
        .map((p) => roomPoint(s.unfold, p.x, p.y))
      this.addHouse(
        this.houses.find((h) => h.id === s.id)!,
        s.door_outside,
        points
      )
      if (s.door_outside) this.addGlow(glowMap, s.door_outside[0], s.door_outside[1], 14, 70)
    }
  }

  /** 太阳：阴影贴图盖住整个镇子，对准镇子中心 */
  private setupSun(atlas: Atlas) {
    this.sun.castShadow = true
    this.sun.shadow.mapSize.set(4096, 4096)
    const reach = Math.hypot(atlas.canvas.width, atlas.canvas.height) / 2 + 600
    Object.assign(this.sun.shadow.camera, {
      left: -reach,
      right: reach,
      top: reach,
      bottom: -reach,
      near: 10,
      far: 30000,
    })
    this.sun.shadow.bias = -0.0004
    this.sun.shadow.normalBias = 3
    this.sun.target.position.set(this.center[0], 0, this.center[1])
    this.scene.add(this.hemi, this.sun, this.sun.target)
  }

  /** 节拍：跟着屏幕刷新走，每秒约 30 拍（60Hz 屏隔一帧一拍）。环境变化只在拍上画，帧距均匀，走路才匀 */
  private loop = (t: number) => {
    this.ticker = requestAnimationFrame(this.loop)
    if (t - this.lastTick >= BEAT_MS) this.tick(t)
  }

  /** 村民走动、水面波纹、空气微粒和天气按节拍推进，画面有变化才重画。
   *  页面隐藏或地图没显示出来时停下；要求减少动画时海、微粒和树都不动，只有村民走动和天气变化时重画 */
  private tick(t: number) {
    const dt = Math.min(0.1, (t - this.lastTick) / 1000)
    this.lastTick = t
    if (document.hidden || !this.container.clientWidth) return
    let changed = this.villagers.active()
    const weather = this.weather.step(dt, t / 1000, this.day)
    if (weather.light) this.applyLight(false)
    changed ||= weather.changed || this.ambient
    this.ambient = false
    if (!this.reduceMotion.matches) {
      this.seaTime.value = t / 1000
      this.motes.step(t)
      this.horizon.step(t / 1000)
      for (const b of this.beams) b.rotation.y -= dt * 0.9
      this.smoke.step(t / 1000)
      for (const b of this.flipbooks)
        for (const m of b.maps) m.offset.x = (Math.floor((t / 1000) * b.fps) % b.frames) / b.frames
      changed = true
    }
    if (changed) this.draw(t)
  }

  /** 画一帧：立牌先摆到这一帧那一刻的位置，名字跟上，再画 */
  private draw(t: number) {
    if (this.villagers.step(t)) this.onVillagersMoved?.()
    this.composer.render()
  }

  /** 会被雨打湿的面：高光随湿度变，另外补上积雪和云影 */
  private wettable(material: THREE.MeshPhongMaterial) {
    material.specular.setScalar(0)
    material.shininess = 60
    this.weather.shade(material, { snow: 1, wet: 1 })
    return material
  }

  /** 当前俯角（度） */
  get pitch() {
    return this.pitchDegrees
  }

  get yaw() {
    return this.yawDegrees
  }

  /** 地面纵深在屏幕上的压缩比例，SVG 视口按它纵向压扁 */
  get verticalScale() {
    return this.tilt.sin
  }

  /** 房屋最高点在地图坐标里的 y，随俯角变化；房间名放在它上面 */
  roofTop(house: House) {
    return houseTop(house, this.tilt)
  }

  /** 掀开后室内墙顶的 y */
  roomTop(house: House) {
    return interiorTop(house, this.tilt)
  }

  setPitch(degrees: number) {
    this.setAngles(degrees, this.yawDegrees)
  }

  setYaw(degrees: number) {
    this.setAngles(this.pitchDegrees, degrees)
  }

  private setAngles(pitch: number, yaw: number) {
    if (!Number.isFinite(pitch) || !Number.isFinite(yaw)) return
    const next = Math.round(Math.min(PITCH_MAX, Math.max(PITCH_MIN, pitch)))
    const nextYaw = normalizeYaw(yaw)
    if (next === this.pitchDegrees && nextYaw === this.yawDegrees) return
    this.pitchDegrees = next
    this.yawDegrees = nextYaw
    this.tilt = tiltOf(next, nextYaw)
    try {
      localStorage.setItem(PITCH_KEY, String(next))
      localStorage.setItem(YAW_KEY, String(nextYaw))
    } catch {
      // 存不下就只在这次页面里生效
    }
    this.applyTilt()
    this.onTilt?.()
  }

  private applyTilt() {
    const t = this.tilt
    for (const place of this.upright) place(t)
    this.villagers.setTilt(t)
    this.props.setTilt(t)
    this.applyLight()
    this.updateTiltShift()
    const control = this.pitchControl
    if (control) {
      const degrees = this.pitchDegrees
      control.style.setProperty(
        '--pitch-t',
        String((degrees - PITCH_MIN) / (PITCH_MAX - PITCH_MIN))
      )
      control.setAttribute('aria-valuenow', String(degrees))
      control.setAttribute('aria-valuetext', `${degrees}°`)
      control.querySelector('output')!.textContent = `${degrees}°`
    }
    this.readView()
  }

  /** 画质：低档直接画场景，不拷贝深度颜色目标，也关闭泛光和景深模糊 */
  setQuality(quality: Quality) {
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, pixelRatioCap(quality)))
    this.composer.setPixelRatio(this.renderer.getPixelRatio())
    this.bloom.enabled = quality !== 'low'
    this.sceneDepth.captureDepth = quality !== 'low'
    for (const p of this.tiltShift) p.enabled = quality !== 'low'
    this.resize()
    this.request()
  }

  private updateTiltShift() {
    const pr = this.renderer.getPixelRatio()
    const near = Math.min(1, TILT_SHIFT_VIEW_HEIGHT / this.viewHeight)
    // 低角度保留前、中、后景层次；转向俯视时逐渐收小离焦，方便读地图与选中人物。
    const overhead = smooth(52, PITCH_MAX, this.pitchDegrees)
    const amount = lerp(3.2, 0.35, overhead) * pr * near
    // 清晰带跟着露出来的那块地图走：手机上村民卡盖住下半屏时，上半屏选中的人不糊
    const h = this.container.clientHeight
    const [top, bottom] = this.focusInsets
    const centre = top + Math.max(0, h - top - bottom) / 2
    const focus = h ? TILT_FOCUS + (h / 2 - centre) / h : TILT_FOCUS
    const depthSpan = (this.viewHeight * this.tilt.cos) / this.tilt.sin
    const distance = Math.min(
      this.viewHeight * CAMERA_DISTANCE_PER_VIEW_HEIGHT,
      MAX_CAMERA_DISTANCE
    )
    for (const p of this.tiltShift) {
      p.uniforms.amount.value = amount
      p.uniforms.focus.value = focus
      p.uniforms.depthAmount.value = 2.4 * (1 - overhead) * pr * near
      p.uniforms.cameraNear.value = this.camera.near
      p.uniforms.cameraFar.value = this.camera.far
      p.uniforms.focusDepth.value = distance + (focus - 0.5) * depthSpan
      p.uniforms.focusRange.value = Math.max(24 * PIXEL, depthSpan * 0.19)
      p.uniforms.depthFalloff.value = Math.max(48 * PIXEL, depthSpan * 0.3)
    }
  }

  /** 地图上下被面板盖住多少（CSS 像素） */
  setFocusInsets(top: number, bottom: number) {
    if (top === this.focusInsets[0] && bottom === this.focusInsets[1]) return
    this.focusInsets = [top, bottom]
    this.updateTiltShift()
    this.request()
  }

  /** 俯角：缩放按钮上方一根竖向滑杆，另外在地图上按住右键上下拖动也能调。
   *  滑杆自己画、自己处理拖动：原生竖向滑杆要较新的浏览器内核，旧 WebView 里会画成横着的一小截；
   *  而且原生滑杆只有中间一条能按，手机上手指稍偏一点就拖成了平移地图。这里整块都能按住上下拖 */
  private installPitchControls() {
    const signal = this.abort.signal
    const zoom = this.container.querySelector('.map-zoom')
    const box = document.createElement('div')
    box.className = 'map-pitch'
    box.title =
      '俯角：往上俯瞰全镇，往下看街景；右键拖动可左右旋转、上下调俯角；双击恢复观景角度与方向'
    box.tabIndex = 0
    box.setAttribute('role', 'slider')
    box.setAttribute('aria-label', '俯角')
    box.setAttribute('aria-orientation', 'vertical')
    box.setAttribute('aria-valuemin', String(PITCH_MIN))
    box.setAttribute('aria-valuemax', String(PITCH_MAX))
    const part = (className: string, tag = 'span') => {
      const node = document.createElement(tag)
      node.className = className
      return node
    }
    const track = part('map-pitch-track')
    track.append(part('map-pitch-fill'), part('map-pitch-thumb'))
    const caption = part('map-pitch-caption')
    caption.textContent = '俯角'
    box.append(track, caption, document.createElement('output'))
    // 按在滑轨的高度范围里：先跳到按的位置；按在字上：不跳。之后都按上下移动的距离换算
    const range = PITCH_MAX - PITCH_MIN
    let drag: { id: number; y: number; pitch: number } | null = null
    box.addEventListener(
      'pointerdown',
      (ev) => {
        // 滑杆上的按下不能漏给地图，否则会被当成拖动平移
        ev.stopPropagation()
        if (ev.button > 0) return
        const r = track.getBoundingClientRect()
        if (r.height && ev.clientY >= r.top && ev.clientY <= r.bottom)
          this.setPitch(PITCH_MIN + ((r.bottom - ev.clientY) / r.height) * range)
        drag = { id: ev.pointerId, y: ev.clientY, pitch: this.pitchDegrees }
        box.setPointerCapture(ev.pointerId)
      },
      { signal }
    )
    box.addEventListener(
      'pointermove',
      (ev) => {
        if (ev.pointerId !== drag?.id) return
        const height = track.getBoundingClientRect().height || 1
        this.setPitch(drag.pitch + ((drag.y - ev.clientY) / height) * range)
      },
      { signal }
    )
    for (const type of ['pointerup', 'pointercancel'] as const)
      box.addEventListener(type, (ev) => ev.pointerId === drag?.id && (drag = null), { signal })
    box.addEventListener(
      'dblclick',
      (ev) => {
        ev.stopPropagation()
        this.setAngles(DEFAULT_PITCH, 0)
      },
      { signal }
    )
    // 键盘：上下左右一度，翻页五度，Home/End 到两头；用掉的键不再交给化身行走
    const steps: Record<string, number> = {
      ArrowUp: 1,
      ArrowRight: 1,
      ArrowDown: -1,
      ArrowLeft: -1,
      PageUp: 5,
      PageDown: -5,
    }
    box.addEventListener(
      'keydown',
      (ev) => {
        const next =
          ev.key === 'Home'
            ? PITCH_MIN
            : ev.key === 'End'
              ? PITCH_MAX
              : ev.key in steps
                ? this.pitchDegrees + steps[ev.key]
                : undefined
        if (next === undefined) return
        ev.preventDefault()
        ev.stopPropagation()
        this.setPitch(next)
      },
      { signal }
    )
    if (zoom) zoom.prepend(box)
    else this.container.append(box)
    this.pitchControl = box

    let dragFrom: { id: number; x: number; y: number; pitch: number; yaw: number } | null = null
    const stop = (ev?: PointerEvent) => {
      if (!dragFrom || (ev && ev.pointerId !== dragFrom.id)) return
      const id = dragFrom.id
      dragFrom = null
      this.container.classList.remove('orbit')
      if (this.container.hasPointerCapture(id)) this.container.releasePointerCapture(id)
    }
    this.container.addEventListener(
      'pointerdown',
      (ev) => {
        if (ev.button !== 2 || ev.buttons & 1 || dragFrom) return
        if (
          (ev.target as Element | null)?.closest(
            '.map-zoom, button, input, select, textarea, [role="dialog"]'
          )
        )
          return
        ev.preventDefault()
        dragFrom = {
          id: ev.pointerId,
          x: ev.clientX,
          y: ev.clientY,
          pitch: this.pitchDegrees,
          yaw: this.yawDegrees,
        }
        this.container.classList.add('orbit')
        try {
          this.container.setPointerCapture(ev.pointerId)
        } catch {
          stop()
        }
      },
      { signal }
    )
    this.container.addEventListener(
      'pointermove',
      (ev) => {
        if (!dragFrom || ev.pointerId !== dragFrom.id) return
        if (!(ev.buttons & 2) || ev.buttons & 1) {
          stop(ev)
          return
        }
        ev.preventDefault()
        this.setAngles(
          dragFrom.pitch + (ev.clientY - dragFrom.y) * PITCH_PER_PIXEL,
          dragFrom.yaw + (ev.clientX - dragFrom.x) * YAW_PER_PIXEL
        )
      },
      { signal }
    )
    this.container.addEventListener('pointerup', stop, { signal })
    this.container.addEventListener('pointercancel', stop, { signal })
    this.container.addEventListener('lostpointercapture', stop, { signal })
    window.addEventListener('blur', () => stop(), { signal })
    this.container.addEventListener(
      'contextmenu',
      (ev) => {
        if (
          !(ev.target as Element | null)?.closest(
            '.map-zoom, button, input, select, textarea, [role="dialog"]'
          )
        )
          ev.preventDefault()
      },
      { signal }
    )
  }

  /** 地面贴图挖掉水的像素，下面垫一整块海（废土是干海床），一直铺到地图外很远；
   *  外圈是海时浪还会冲上沙滩。返回海面动画的时间和闪光的多少 */
  private addGround(terrain: Ground) {
    const { width: pw, height: ph, wet } = terrain
    const w = pw * PIXEL,
      h = ph * PIXEL
    // 树和灌木由场景立起来，地面图上不画
    const land = paintGround(terrain, false)
    const ctx = land.getContext('2d')!
    const img = ctx.getImageData(0, 0, pw, ph)
    for (let i = 0; i < pw * ph; i++) if (wet[i]) img.data[i * 4 + 3] = 0
    ctx.putImageData(img, 0, 0)
    const landMaterial = this.wettable(
      new THREE.MeshPhongMaterial({ map: texture(land), alphaTest: 0.5 })
    )
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(w, h), landMaterial)
    ground.rotation.x = -Math.PI / 2
    ground.position.set(-MARGIN + w / 2, 0, -MARGIN + h / 2)
    ground.receiveShadow = true
    const coast = coastTexture(terrain.depth, terrain.shore, pw, ph)
    const { material, time, sparkle } = outerMaterial(coast, this.horizon.haze, this.theme)
    // 海面也有云影，风和雨从天气里来
    this.weather.shade(material, { snow: 0, wet: 0 })
    if (this.theme.outer === 'sea') surfOnLand(landMaterial, coast, time, this.theme)
    const sea = new THREE.Mesh(new THREE.PlaneGeometry(w * 6, h * 6), material)
    sea.rotation.x = -Math.PI / 2
    sea.position.set(ground.position.x, -1, ground.position.z)
    sea.receiveShadow = true
    this.flat.add(ground, sea)
    return { time, sparkle }
  }

  private addHouse(house: House, door?: [number, number], points: [number, number][] = []) {
    const { x, y, w, h } = house
    const group = new THREE.Group()
    group.position.set(x + w / 2, 0, y + h / 2)
    // 只有朝南的墙面向镜头；门在南墙上时画出来
    const onSouth = door && Math.abs(door[1] - (y + h)) <= Math.min(Math.abs(door[1] - y), 40)
    const top = this.addBody(group, house, onSouth ? (door![0] - x) / PIXEL : undefined)
    this.addRoof(group, house, top)
    this.addFeatures(group, house, onSouth ? door![0] - (x + w / 2) : undefined)
    this.addChimney(group, house)
    this.flat.add(group)
    this.houseGroups.set(house.id, group)
    const room = interior(house, door, points)
    this.flat.add(room.group)
    this.rooms.set(house.id, room.group)
    this.partitions.set(house.id, room.partition)
    this.glowing.push(room.glowing)
  }

  /** 房子的墙：朝镜头的墙面贴画好的墙（夜里窗户发光），墙顶压深色；door 是门离墙左端的像素数。
   *  返回墙顶的材质，夜里和屋顶一起微亮 */
  private addBody(group: THREE.Group, house: House, door?: number) {
    const { w, h, wallH } = house
    const wall = wallCanvases(house, Math.max(4, Math.round(w / PIXEL)), door)
    const front = new THREE.MeshLambertMaterial({
      map: texture(wall.map),
      emissiveMap: texture(wall.emissive),
      emissive: new THREE.Color('#ffffff'),
      emissiveIntensity: 0,
    })
    this.glowing.push(front)
    this.weather.shade(front, { snow: 0, wet: 0.5 })
    const top = new THREE.MeshLambertMaterial({ color: WALL_CAP, emissive: WALL_CAP })
    this.weather.shade(top, { snow: 1, wet: 0.5 })
    const body = new THREE.Mesh(new THREE.BoxGeometry(w, wallH, h), [
      front,
      front,
      top,
      top,
      front,
      front,
    ])
    body.position.y = wallH / 2
    body.castShadow = body.receiveShadow = true
    group.add(body)
    return top
  }

  /** 屋顶：斜面、两头山墙、南坡上的十字脊或老虎窗（形状见 roofs.ts），剧院是拱顶 */
  private addRoof(group: THREE.Group, house: House, top: THREE.MeshLambertMaterial) {
    const { w, h, wallH, ridge, alongX } = house
    const parts = roofParts(house)
    const roofMap = texture(
      roofCanvas(
        Math.max(2, Math.round(parts.length / PIXEL)),
        Math.max(2, Math.round(parts.slope / PIXEL)),
        house
      )
    )
    const roofMaterial = this.wettable(
      new THREE.MeshPhongMaterial({
        map: roofMap,
        emissiveMap: roofMap,
        emissive: '#ffffff',
        side: THREE.DoubleSide,
      })
    )
    this.moonlit.push(top, roofMaterial)
    if (house.look.vault) {
      // 拱顶沿南北方向，半圆的一头正对镜头
      const ends = new THREE.MeshLambertMaterial({
        color: wallBase(house),
        emissive: wallBase(house),
        side: THREE.DoubleSide,
      })
      this.weather.shade(ends, { snow: 0, wet: 0.5 })
      this.moonlit.push(ends)
      const vault = vaultRoof(h, w + 2 * OVERHANG, wallH, ridge, roofMaterial, ends)
      vault.rotation.y = Math.PI / 2
      group.add(vault)
      return
    }
    const roof = new THREE.Mesh(parts.slopes, roofMaterial)
    roof.castShadow = roof.receiveShadow = true
    group.add(roof)
    // 山墙面和墙一样贴墙面材质，窗夜里亮；屋脊南北向时南头的山墙正对镜头，开一扇圆窗
    const face = (geometry: THREE.BufferGeometry, art: ReturnType<typeof gableCanvases>) => {
      const material = new THREE.MeshLambertMaterial({
        map: texture(art.map),
        emissiveMap: texture(art.emissive),
        emissive: new THREE.Color('#ffffff'),
        emissiveIntensity: 0,
        side: THREE.DoubleSide,
      })
      this.glowing.push(material)
      this.weather.shade(material, { snow: 0, wet: 0.5 })
      const mesh = new THREE.Mesh(geometry, material)
      mesh.castShadow = mesh.receiveShadow = true
      group.add(mesh)
    }
    if (parts.ends) {
      const texels = Math.max(2, Math.round(ridge / WALL_TEXEL))
      const across = Math.max(2, Math.round((alongX ? h : w) / PIXEL))
      face(parts.ends, gableCanvases(house, across, texels, texels, alongX ? 'none' : 'round'))
    }
    for (const g of parts.gables) {
      const texels = Math.max(2, Math.round((g.y1 - g.y0) / WALL_TEXEL))
      const peak = Math.round(g.peak / WALL_TEXEL)
      const art = gableCanvases(
        house,
        Math.max(2, Math.round((g.x1 - g.x0) / PIXEL)),
        texels,
        peak,
        g.dormer ? 'dormer' : 'round'
      )
      face(gableGeometry(g), art)
    }
  }

  /** 烟囱：风格说总有、有时有（按房子编号）还是没有。从南坡上立起来、高出屋脊，
   *  浅色石砌、顶上压一圈深色烟囱帽，在深色屋面上一眼看得见 */
  private addChimney(group: THREE.Group, house: House) {
    const { look, wallH, ridge } = house
    if (!(look.chimney === 'always' || (look.chimney === 'sometimes' && house.seed % 5 < 3))) return
    const [x, z] = chimneySpot(house)
    const base = roofHeight(house, x, z) - 3 * WALL_TEXEL
    const top = Math.max(base + 11 * WALL_TEXEL, wallH + ridge + 4 * WALL_TEXEL)
    const height = top - base
    const side = new THREE.MeshLambertMaterial({
      map: texture(chimneyCanvas(house, Math.round(height / WALL_TEXEL))),
    })
    const mouth = new THREE.MeshLambertMaterial({ color: '#2e2a26' })
    const chimney = new THREE.Mesh(new THREE.BoxGeometry(6 * PIXEL, height, 6 * PIXEL), [
      side,
      side,
      mouth,
      mouth,
      side,
      side,
    ])
    chimney.position.set(x, base + height / 2, z)
    const cap = new THREE.Mesh(
      new THREE.BoxGeometry(8 * PIXEL, 2 * WALL_TEXEL, 8 * PIXEL),
      new THREE.MeshLambertMaterial({ color: '#4a433d' })
    )
    cap.position.set(x, top - WALL_TEXEL, z)
    chimney.castShadow = cap.castShadow = chimney.receiveShadow = true
    group.add(chimney, cap)
    if (look.smoke)
      this.smoke.add(group.position.x + x, top + WALL_TEXEL, group.position.z + z, house.seed)
  }

  /** 功能类型的立体特征：门口的条纹雨棚、公所屋脊上的旗 */
  private addFeatures(group: THREE.Group, house: House, doorX?: number) {
    const { w, h, wallH, ridge, look } = house
    if (look.awning && doorX !== undefined) {
      const [doorW, doorH] = DOORS[look.door]
      const width = look.awning.whole ? w - 4 * PIXEL : (doorW + 10) * PIXEL
      const cx = look.awning.whole
        ? 0
        : Math.max(-w / 2 + width / 2, Math.min(w / 2 - width / 2, doorX))
      const depth = 6 * PIXEL,
        tilt = 0.5
      const map = texture(awningCanvas(Math.max(4, Math.round(width / PIXEL)), look.awning.colors))
      const material = new THREE.MeshLambertMaterial({
        map,
        side: THREE.DoubleSide,
        alphaTest: 0.5,
      })
      this.weather.shade(material, { snow: 1, wet: 0.5 })
      const awning = new THREE.Mesh(new THREE.PlaneGeometry(width, depth), material)
      // 贴在南墙门上方，外沿往下斜
      const topY = Math.min(wallH - 2 * WALL_TEXEL, (doorH + 3) * WALL_TEXEL)
      awning.rotation.x = -Math.PI / 2 + tilt
      awning.position.set(
        cx,
        topY - (Math.sin(tilt) * depth) / 2,
        h / 2 + (Math.cos(tilt) * depth) / 2
      )
      awning.castShadow = awning.receiveShadow = true
      group.add(awning)
    }
    if (look.columns) group.add(colonnadeFront(house))
    if (look.tower) {
      // 灯塔立在离镇中心远的那一头，也就是朝海的一头
      const tower = lighthouseTower(
        house,
        Math.sign(house.x + house.w / 2 - this.center[0]) || 1,
        this.theme.lighthouse
      )
      group.add(tower.group)
      this.glowing.push(tower.lamp)
      if (tower.beam) this.beams.push(tower.beam)
    }
    if (look.flag) {
      const poleH = 16 * WALL_TEXEL
      const pole = new THREE.Mesh(
        new THREE.BoxGeometry(PIXEL, poleH, PIXEL),
        new THREE.MeshLambertMaterial({ color: '#3a3634' })
      )
      pole.position.set(0, wallH + ridge + poleH / 2, 0)
      pole.castShadow = true
      const map = texture(flagCanvas(this.theme.flag))
      const cloth = new THREE.MeshLambertMaterial({ map, side: THREE.DoubleSide })
      this.weather.shade(cloth, { snow: 0, wet: 0.3, sway: true })
      const flag = new THREE.Mesh(new THREE.PlaneGeometry(10 * PIXEL, 6 * WALL_TEXEL), cloth)
      flag.geometry.translate(5 * PIXEL, 0, 0)
      flag.position.set(PIXEL / 2, wallH + ridge + poleH - 3 * WALL_TEXEL, 0)
      flag.castShadow = true
      group.add(pole, flag)
    }
  }

  /** 立起户外地标和散落物；返回去掉它们占地之后的空地（terrain.open 的副本） */
  private placeStandees(
    atlas: Atlas,
    terrain: {
      width: number
      height: number
      open: Uint8Array
      wet: Uint8Array
      depth: Uint8Array
      docks: Dock[]
    },
    seed: number
  ) {
    const open = terrain.open.slice()
    this.addLandmarks(atlas, terrain.docks, open, terrain.width, seed)
    this.addScatter(terrain, open, seed)
    return open
  }

  /** 户外地点的标志物立牌；立牌占的地方从空地里去掉 */
  private addLandmarks(atlas: Atlas, docks: Dock[], open: Uint8Array, pw: number, seed: number) {
    for (const s of landmarkSprites(atlas, seed, docks, this.theme.landmarks)) {
      // 逐帧动画的立牌按一帧的宽度算
      const frames = s.frames ?? 1,
        width = s.canvas.width / frames
      // 占地和房子重叠的不放（默认小镇的市集中间就有一栋房子）
      const half = (width / 2) * PIXEL,
        deep = s.canvas.height * 0.4 * PIXEL
      if (
        this.houses.some(
          (h) => s.x + half > h.x && s.x - half < h.x + h.w && s.y > h.y && s.y - deep < h.y + h.h
        )
      )
        continue
      const map = texture(s.canvas),
        glow = s.glow && texture(s.glow)
      const mesh = standee(map, { frame: [width, s.canvas.height], emissive: glow })
      const material = mesh.material as THREE.MeshLambertMaterial
      if (glow) this.selfLit.push(material)
      if (frames > 1) {
        const maps = glow ? [map, glow] : [map]
        for (const m of maps) m.repeat.x = 1 / frames
        this.flipbooks.push({ maps, frames, fps: s.fps ?? 1 })
      }
      this.weather.shade(material, { snow: 1, wet: 0.4 })
      const sx = Math.round(s.x / PIXEL) * PIXEL,
        sy = Math.round(s.y / PIXEL) * PIXEL
      this.upright.push((t) => stand(mesh, sx, sy, t))
      this.scene.add(mesh)
      const clear = Math.ceil(width / 2) + 3
      for (let dy = -Math.ceil(s.canvas.height * 0.6); dy <= 4; dy++)
        for (let dx = -clear; dx <= clear; dx++) {
          const i = pxIndex(sx + dx * PIXEL, sy + dy * PIXEL, pw)
          if (i >= 0 && i < open.length) open[i] = OPEN.none
        }
    }
  }

  /** 散落物：野地上的轮胎、雪人，外圈（干海床、冰原）上的沉船、冰钓小屋。放在空地上，占的地方从空地里去掉 */
  private addScatter(
    terrain: { width: number; height: number; wet: Uint8Array; depth: Uint8Array },
    open: Uint8Array,
    seed: number
  ) {
    const scatter = this.theme.landmarks.scatter
    if (!scatter) return
    const { width: pw, height: ph, wet, depth } = terrain
    const random = rng(seed + 31)
    const STEP = 12
    for (let gy = 0; gy < ph; gy += STEP)
      for (let gx = 0; gx < pw; gx += STEP) {
        const x = gx + Math.floor(random() * STEP),
          y = gy + Math.floor(random() * STEP)
        const chance = random()
        if (x >= pw || y >= ph) continue
        const i = y * pw + x
        const where =
          open[i] === OPEN.wild
            ? 'land'
            : this.theme.outer !== 'sea' && wet[i] && depth[i] > 5 && depth[i] < 30
              ? 'outer'
              : null
        if (!where || chance > scatter[where]) continue
        const canvas = scatter.sprite(where, (x * 7919 + y * 104729) >>> 0)
        const half = Math.ceil(canvas.width / 2)
        const fits = (dx: number) => {
          const j = i + dx
          return where === 'land' ? open[j] === OPEN.wild : wet[j] === 1
        }
        let clear = x - half > 0 && x + half < pw
        for (let dx = -half; clear && dx <= half; dx++) clear = fits(dx)
        if (!clear) continue
        const mesh = standee(texture(canvas))
        this.weather.shade(mesh.material as THREE.MeshLambertMaterial, { snow: 1, wet: 0.4 })
        const sx = fromPx(x),
          sy = fromPx(y)
        this.upright.push((t) => stand(mesh, sx, sy, t))
        this.scene.add(mesh)
        for (let dy = -Math.ceil(canvas.height * 0.6); dy <= 3; dy++)
          for (let dx = -half - 2; dx <= half + 2; dx++) {
            const j = (y + dy) * pw + x + dx
            if (j >= 0 && j < open.length) open[j] = OPEN.none
          }
      }
  }

  private addGlow(map: THREE.Texture, x: number, y: number, texelsUp: number, size: number) {
    const sprite = new THREE.Sprite(
      new THREE.SpriteMaterial({
        map,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        transparent: true,
        opacity: 0,
      })
    )
    // 沿立牌的方向抬高，屏幕上正好高出 texelsUp 个像素
    this.upright.push((t) => onStandee(sprite, x, y, texelsUp, t, 40))
    sprite.scale.set(size, size, 1)
    this.scene.add(sprite)
    this.glows.push(sprite)
    return sprite
  }

  /** 地图规划的树，加上按演示页规则撒在空地上的树：公园最密，镇外草地按噪声成片 */
  private addTrees(
    decor: DecorPlan,
    terrain: { width: number; height: number; open: Uint8Array },
    seed: number
  ) {
    const cache = new Map<string, THREE.Texture>()
    const add = (
      x: number,
      y: number,
      r: number,
      variant: number,
      bush: boolean,
      scale: number
    ) => {
      const key = `${r}|${variant}|${bush}`
      if (!cache.has(key))
        cache.set(key, texture(treeCanvas(r, variant, bush, seed, this.theme.flora)))
      const mesh = standee(cache.get(key)!, { scale })
      // 树冠顶上积雪，随风摆
      this.weather.shade(mesh.material as THREE.MeshLambertMaterial, {
        snow: 1,
        wet: 0.3,
        sway: true,
      })
      const sx = Math.round(x / PIXEL) * PIXEL,
        sy = Math.round(y / PIXEL) * PIXEL
      this.upright.push((t) => stand(mesh, sx, sy, t))
      this.scene.add(mesh)
    }
    for (const v of decor.vegetation) {
      if (v.kind === 'grass' || v.kind === 'flowers') continue
      const { r, variant, bush } = treeShape(v)
      add(v.x, v.y, r, variant, bush, 1)
    }
    const { width: pw, height: ph, open } = terrain
    const random = rng(seed + 12)
    const placed: [number, number, number][] = []
    const free = (x: number, y: number, r: number) => {
      for (let dy = -r - 2; dy <= r + 2; dy += 2)
        for (let dx = -r - 2; dx <= r + 2; dx += 2) {
          const X = Math.round(x + dx),
            Y = Math.round(y + dy)
          if (X < 2 || Y < 2 || X >= pw - 2 || Y >= ph - 2 || !open[Y * pw + X]) return false
        }
      return true
    }
    const density: Record<number, (x: number, y: number) => number> = {
      [OPEN.park]: () => 0.5,
      [OPEN.garden]: () => 0.05,
      [OPEN.town]: () => 0.02,
      [OPEN.wild]: (x, y) => 0.26 * Math.max(0, fbm(x * 0.6, y * 0.6, seed + 90) * 2.6 - 1.05),
    }
    for (let gy = 0; gy < ph; gy += 7)
      for (let gx = 0; gx < pw; gx += 7) {
        const x = gx + Math.floor(random() * 6),
          y = gy + Math.floor(random() * 6)
        if (x >= pw || y >= ph) continue
        const d = (density[open[y * pw + x]]?.(x, y) ?? 0) * this.theme.flora.density
        if (random() > d) continue
        const bush = random() < 0.25,
          r = bush ? 3 + Math.floor(random() * 2) : 5 + Math.floor(random() * 5)
        if (!free(x, y, bush ? 2 : 3)) continue
        if (placed.some(([px, py, pr]) => Math.hypot(px - x, py - y) < (pr + r) * 0.8)) continue
        placed.push([x, y, r])
        add(fromPx(x), fromPx(y), r, Math.floor(random() * 3), bush, 1.3)
      }
  }

  /** 沿室外路段每隔一段立一盏路灯，离地图中心近的几盏带点光源 */
  private addLamps(atlas: Atlas, wet: Uint8Array, pw: number, glowMap: THREE.Texture) {
    const rooms = this.houses
    const inRoom = (x: number, y: number, pad: number) =>
      rooms.some(
        (r) => x > r.x - pad && x < r.x + r.w + pad && y > r.y - pad && y < r.y + r.h + pad
      )
    const spots: [number, number][] = []
    const gap = 80 * PIXEL
    for (const e of atlas.edges) {
      if (e.polyline.some(([x, y]) => inRoom(x, y, -12))) continue
      let run = gap / 2
      for (let k = 0; k + 1 < e.polyline.length; k++) {
        const [a, b] = [e.polyline[k], e.polyline[k + 1]]
        const len = Math.hypot(b[0] - a[0], b[1] - a[1])
        for (let s = 0; s < len; s += 12) {
          run += 12
          if (run < gap) continue
          const t = s / len
          const px = a[0] + (b[0] - a[0]) * t - ((b[1] - a[1]) / len) * 48
          const py = a[1] + (b[1] - a[1]) * t + ((b[0] - a[0]) / len) * 48
          const i = pxIndex(px, py, pw)
          if (
            inRoom(px, py, 40) ||
            wet[i] ||
            spots.some((p) => Math.hypot(p[0] - px, p[1] - py) < gap * 0.85)
          )
            continue
          spots.push([px, py])
          run = 0
        }
      }
    }
    const cx = atlas.canvas.width / 2,
      cy = atlas.canvas.height / 2
    spots.sort((p, q) => Math.hypot(p[0] - cx, p[1] - cy) - Math.hypot(q[0] - cx, q[1] - cy))
    const post = texture(lampCanvas(false, this.theme.lamp)),
      glass = texture(lampCanvas(true, this.theme.lamp))
    spots.forEach(([x, y], i) => {
      const mesh = standee(post, { emissive: glass })
      const sx = Math.round(x / PIXEL) * PIXEL,
        sy = Math.round(y / PIXEL) * PIXEL
      this.upright.push((t) => stand(mesh, sx, sy, t))
      this.scene.add(mesh)
      this.glowing.push(mesh.material as THREE.Material)
      this.addGlow(glowMap, sx, sy, 24, 120)
      if (i >= LIT_LAMPS) return
      const light = new THREE.PointLight(this.theme.light.lamp, 0, LAMP_REACH, 1)
      this.upright.push((t) => onStandee(light, sx, sy, 24, t, 60))
      this.scene.add(light)
      this.lampLights.push(light)
    })
  }

  /** 世界时间与天气 */
  setClock(minutes: number, weather?: string) {
    // 名册每次都带时钟；世界暂停时时间和天气都没变，不必重算光照、重画
    const clock = `${minutes}|${weather}`
    if (clock === this.clock) return
    this.clock = clock
    this.hour = (((minutes % 1440) + 1440) % 1440) / 60
    this.weather.setKind(weather as WeatherKind | undefined)
    this.weather.setClock(minutes)
    // 名册每拍都会改时钟：等节拍再画，不打乱走路的帧距
    this.applyLight(false)
  }

  /** 屋里的立牌收到墙内侧，见 keepInside */
  private inside(x: number, y: number, half: number) {
    for (const house of this.houses)
      [x, y] = keepInside(
        house,
        this.partitions.get(house.id),
        x,
        y,
        half * Math.abs(this.tilt.yawCos),
        half * Math.abs(this.tilt.yawSin)
      )
    return [x, y] as [number, number]
  }

  /** 最近一次的道具立牌，村民用道具时站到它前面 */
  private propPlacements: PropPlacement[] = []

  /** 立牌每帧挪过之后、以及新名册改了目标之后调用：SVG 里的名字和心声泡按 villagerLag 跟上立牌 */
  onVillagersMoved?: () => void

  /** 村民位置；fresh 表示这是新来的一份名册。两份之间由场景自己匀速走过去（见 villagers.ts） */
  setVillagers(placements: VillagerPlacement[], fresh = false) {
    const changed = this.villagers.sync(
      placements.map((p) => {
        // 落脚点就在道具上时，人站到道具底边前面一点，不站进家具里
        const at = this.propPlacements.find(
          (q) => q.visible && Math.hypot(q.x - p.x, q.y - p.y) < 8
        )
        const toward = at ? at.size * PROP_BASE + 4 : 0
        const [x, y] = this.inside(
          p.x + toward * this.tilt.yawSin,
          p.y + toward * this.tilt.yawCos,
          VILLAGER_HALF
        )
        return { ...p, offset: [x - p.x, y - p.y] as [number, number] }
      }),
      fresh
    )
    // 名字已经按名册摆到了新位置，立牌还在后面：马上按落后的距离挪回立牌头上
    this.onVillagersMoved?.()
    // 有人进出、显隐的等下一个节拍画；只是换了目标点的，走过去时再画
    if (changed) this.ambient = true
  }

  /** 立牌比名册里的位置落后多少（地图单位）；不在场的人为 undefined */
  villagerLag(id: string) {
    return this.villagers.lag(id)
  }

  /** 道具立牌：屋里的跟着屋子掀开才显示。返回每个立牌实际画的位置：x 是收进墙内侧后的，
   *  base 是底边中点的 y；SVG 层的点击区和名字据此跟着立牌走 */
  setProps(placements: PropPlacement[]) {
    this.propPlacements = placements
    const drawn = placements.map((p) => {
      const [x, y] = this.inside(p.x, p.y, p.size / 2)
      return { ...p, x, y }
    })
    this.props.sync(drawn)
    this.request()
    return drawn.map((p) => ({
      id: p.id,
      x: p.x,
      y: p.y,
      base: p.y + p.size * PROP_BASE,
      size: p.size,
    }))
  }

  /** 这些房间去掉整栋房子，立起室内的墙，露出地面上画的地板 */
  setOpenRooms(open: ReadonlySet<string>) {
    for (const [id, group] of this.houseGroups) group.visible = !open.has(id)
    for (const [id, group] of this.rooms) group.visible = open.has(id)
    this.request()
  }

  /** 光照公式与演示页相同；cloud 压低日照和饱和度。now 为 false 时等下一个节拍再画（名册、天气这类环境变化） */
  private applyLight(now = true) {
    const e = Math.sin(((this.hour - 6) / 12) * Math.PI)
    const elev = (e * Math.PI) / 3,
      az = ((this.hour - 12) / 12) * Math.PI
    const day = smooth(-0.06, 0.22, e),
      night = 1 - smooth(-0.12, 0.1, e)
    const { cloud, overcast, flash } = this.weather
    this.day = day
    const golden = Math.max(0, 1 - Math.abs(e - 0.12) / 0.3) * day * (1 - cloud)
    // 太阳在南边（镜头这一侧）偏高处：朝镜头的南墙受光，影子往北落在房子后面；
    // 中午最偏南，早晚偏东西、斜照南墙
    const dir =
      e > -0.06
        ? new THREE.Vector3(
            -Math.sin(az) * Math.cos(elev),
            Math.max(Math.sin(elev), 0.33),
            0.3 + 0.2 * Math.cos(az)
          )
        : new THREE.Vector3(-0.35, 0.8, 0.55)
    this.sun.position.copy(this.sun.target.position).addScaledVector(dir.normalize(), 12000)
    const L = this.theme.light
    const color = (hex: string) => new THREE.Color(hex)
    const sunColor = color(L.sun.low).lerp(color(L.sun.day), smooth(0.05, 0.6, e))
    // 闪电那一下是冷白色的强光
    this.sun.color
      .copy(new THREE.Color('#8fa6d9').lerp(sunColor, day))
      .lerp(new THREE.Color('#dce6ff'), flash)
    // 夜里的月光和天光比演示页亮一些，游戏里要能看清人和房子
    this.sun.intensity = (lerp(0.9, 2.7, day) + golden * 1.1) * (1 - cloud * 0.7) + flash * 6
    // 阴天光线是漫射的：影子变淡
    this.sun.shadow.intensity = 1 - 0.7 * overcast
    this.hemi.color.copy(color(L.hemiSky.night).lerp(color(L.hemiSky.day), day))
    this.hemi.groundColor.copy(color(L.hemiGround.night).lerp(color(L.hemiGround.day), day))
    this.hemi.intensity = lerp(1.35, 1.05, day) + golden * 0.35 + cloud * 0.3 * day + flash * 2.5
    const sky = color(L.sky.night)
      .lerp(color(L.sky.day), day)
      .lerp(color(L.sky.golden), golden * 0.55)
    this.fog.color.copy(sky)
    this.renderer.setClearColor(sky)
    // 远景：高处的天色比海雾深、偏蓝，傍晚带一点暖色，阴天往海雾色靠；远山是压暗的海雾色
    const top = color(L.top.night)
      .lerp(color(L.top.day), day)
      .lerp(color(L.top.golden), golden * 0.45)
      .lerp(sky, overcast * 0.7)
    const hill = sky
      .clone()
      .multiplyScalar(0.72)
      .lerp(color(L.hill), 0.35 * day)
    this.horizon.setColors(sky, top, hill)
    // 夜里灯只是点缀：窗户和路灯微亮，看清人和房子靠天光和对比度
    for (const m of this.glowing) (m as THREE.MeshLambertMaterial).emissiveIntensity = night * 0.9
    for (const m of this.moonlit) m.emissiveIntensity = night * ROOF_NIGHT_GLOW
    for (const m of this.selfLit) m.emissiveIntensity = lerp(0.3, 0.55, night)
    this.seaSparkle.value = lerp(0.3, 1, day) * (1 - cloud * 0.9)
    for (const g of this.glows) g.material.opacity = night * 0.3
    for (const l of this.lampLights) l.intensity = night * 220
    for (const b of this.beams) (b.material as THREE.MeshBasicMaterial).opacity = night * 0.45
    this.horizon.setAurora(night * L.aurora)
    this.bloom.strength = lerp(0.35, 0.5, night)
    this.bloom.threshold = lerp(0.9, 0.82, night)
    this.grade.uniforms.contrast.value = lerp(1, 1.15, night)
    const tint = this.grade.uniforms.tint.value as THREE.Color
    tint
      .setRGB(...L.tint.day)
      .lerp(new THREE.Color(...L.tint.golden), golden)
      .lerp(new THREE.Color(...L.tint.night), night)
      .lerp(new THREE.Color(0.94, 0.98, 1.06), overcast * 0.6 * day)
    ;(this.grade.uniforms.lift.value as THREE.Color).setRGB(
      0.004 * night,
      0.008 * night,
      0.02 * night
    )
    this.grade.uniforms.sat.value = L.saturation - cloud * 0.25
    this.renderer.toneMappingExposure = lerp(1.3, 1.12, day)
    this.motes.setLight(day, golden, cloud)
    if (now) this.request()
    else this.ambient = true
  }

  private readView() {
    const vb = this.svg.getAttribute('viewBox')?.split(/[ ,]+/).map(Number)
    if (!vb || vb.length !== 4 || vb.some((v) => !Number.isFinite(v))) return
    const [x, y, w, h] = vb
    const cam = this.camera
    const { sin, cos, yawSin, yawCos } = this.tilt
    // 视口高 h 是地图纵深；镜头倾斜后它在画面上只占 h·sin
    const screenH = h * sin
    Object.assign(cam, {
      left: -w / 2,
      right: w / 2,
      top: screenH / 2,
      bottom: -screenH / 2,
    })
    const vx = x + w / 2,
      vy = y + h / 2
    const target = new THREE.Vector3(yawCos * vx + yawSin * vy, 0, -yawSin * vx + yawCos * vy)
    this.viewHeight = screenH
    const unitPx = this.renderer.domElement.width / w
    this.motes.setScale(unitPx)
    this.weather.setView(target.x, target.z, w, h, screenH, unitPx, sin, cos, yawSin, yawCos)
    // 正交镜头的距离不改变画面，只决定雾气：按演示页，视野越大离得越远、雾越浓
    const distance = Math.min(screenH * CAMERA_DISTANCE_PER_VIEW_HEIGHT, MAX_CAMERA_DISTANCE)
    cam.near = -40000
    cam.far = distance + 40000
    cam.up.set(-yawSin * sin, cos, -yawCos * sin)
    cam.position
      .copy(target)
      .add(new THREE.Vector3(yawSin * cos, sin, yawCos * cos).multiplyScalar(distance))
    cam.lookAt(target)
    cam.updateProjectionMatrix()
    this.updateTiltShift()
    this.request()
  }

  private resize() {
    const { clientWidth: w, clientHeight: h } = this.container
    if (!w || !h) return
    this.renderer.setSize(w, h)
    this.composer.setSize(w, h)
    const pr = this.renderer.getPixelRatio()
    for (const p of this.tiltShift) p.uniforms.res.value.set(w * pr, h * pr)
    this.updateTiltShift()
    this.readView()
  }

  /** 操作带来的变化（拖地图、换角度、开合屋顶）马上画，不等节拍 */
  private request() {
    if (!this.frame)
      this.frame = requestAnimationFrame((t) => {
        this.frame = 0
        this.draw(t)
      })
  }

  dispose() {
    cancelAnimationFrame(this.frame)
    cancelAnimationFrame(this.ticker)
    this.abort.abort()
    this.weather.dispose()
    this.props.dispose()
    this.pitchControl?.remove()
    this.villagers.dispose()
    for (const o of this.observers) o.disconnect()
    this.scene.traverse((o) => {
      // 灯连同阴影贴图（太阳的是 4096×4096）一起释放
      if (o instanceof THREE.Light) o.dispose()
      const mesh = o as THREE.Mesh
      mesh.geometry?.dispose()
      const mats = Array.isArray(mesh.material)
        ? mesh.material
        : mesh.material
          ? [mesh.material]
          : []
      for (const m of mats) {
        for (const v of Object.values(m)) if (v instanceof THREE.Texture) v.dispose()
        m.dispose()
      }
    })
    // composer.dispose 只释放它自己的两张渲染目标，泛光等各个 pass 的渲染目标和材质要逐个释放
    for (const pass of this.composer.passes) pass.dispose()
    this.composer.dispose()
    this.renderer.dispose()
    // 立即交还 WebGL 上下文，不等垃圾回收；否则选图页多点几张图就会超过浏览器的上下文上限
    this.renderer.forceContextLoss()
    this.renderer.domElement.remove()
  }
}
