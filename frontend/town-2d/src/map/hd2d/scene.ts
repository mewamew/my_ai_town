import * as THREE from 'three'
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js'
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js'
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js'
import type { Atlas } from 'town-shared/mapDocument'
import type { DecorPlan } from '../decor'
import { fromPx, MARGIN, OUTDOOR_SPACE, PIXEL, pxIndex, roomPoint, toPx } from '../grid'
import { WALL_CAP } from '../palette'
import { mownLawn, OPEN, paintGround, treeShape, type Ground } from '../pixel/terrain'
import type { Dock } from '../pixel/island'
import { pier, PIER_DECK, pierLampCanvas } from './pier'
import { bridge } from './bridge'
import { liftOf, onBridge, type Bridge } from '../pixel/bridges'
import { PAVILION_REACH, pavilionLift, type Pavilion } from '../pixel/pavilions'
import { FOUNTAIN, fountainLift, fountainsOf, rimSpot, type Fountain } from '../pixel/fountains'
import { standGap, standLift, standsOf, type Stand } from '../pixel/stands'
import { buildStand } from './stand'
import { fbm, hash, rng } from '../pixel/noise'
import { Motes } from './motes'
import { Villagers, type LiveMotion, type VillagerPlacement } from './villagers'
import type { Badge } from './villagerSigns'
import { villagerLight } from './villagerLight'
import { VILLAGER_HALF, VILLAGER_HEIGHT, VILLAGER_SCALE } from './villagerSprite'
import { Weather3D } from './weather'
import { gameModeLooks, type GameModeLook } from './gameModes'
import { daylight } from './daylight'
import { DOORS } from '../buildings'
import type { WeatherKind } from 'town-shared/weather/types'
import type { GameModeView } from 'town-shared/protocol'
import {
  DEFAULT_PITCH,
  PITCH_MAX,
  PITCH_MIN,
  WALL_TEXEL,
  houseOf,
  houseTop,
  riseOf,
  ruinOf,
  tiltOf,
  type House,
  type Tilt,
} from './layout'
import {
  chimneyCanvas,
  glowCanvas,
  lampCanvas,
  awningCanvas,
  gableCanvases,
  roofCanvas,
  treeCanvas,
  wallBase,
  wallCanvases,
} from './textures'
import { OVERHANG, chimneySpot, gableGeometry, roofHeight, roofParts } from './roofs'
import {
  finishShader,
  gradeShader,
  lookTexture,
  SceneDepthPass,
  TILT_FOCUS,
  tiltShader,
} from './post'
import { LightMap, type LightSource } from './lightmap'
import { BokehPass, GlowPass } from './lens'
import { Reflection, REFLECTION_SKIP, wetReflection } from './reflection'
import { groundAo, groundOcclusion, wallAo, type Contact } from './ao'
import { Grass, tuftsOf } from './grass'
import { Trail } from './trail'
import { Fauna, shallowsOf } from './fauna'
import { GpuTimer, PerfOverlay } from './perf'
import { qualityLabels, storedQuality } from 'town-shared/quality'
import { VolumetricPass } from './volumetric'
import { pixelMaterial } from './pixelSampling'
import { landmarkSprites, mapStandees, type PlacedModel } from './landmarks'
import { LandmarkModels } from './landmarkModels'
import { Kit } from './propKit'
import { PETAL, stoneLantern } from './groveArt'
import { buildGazebo } from './gazebo'
import { buildFountain, type FountainSpray } from './fountain'
import { Petals, type PetalSource } from './petals'
import { coastTexture, outerMaterial, surfOnLand } from './sea'
import { Horizon } from './horizon'
import { ChimneySmoke } from './smoke'
import { SpringSteam, springShore } from './steam'
import { interior, interiorTop, keepInside } from './interior'
import type { Partition } from './partition'
import { PROP_BASE, PropStandees, type PropPlacement } from './props'
import { arrange, furnish, type Decor, type Room } from './propArrange'
import { buildOf, decorBuild, type Build } from './propBuilds'
import { PropModels, type ModelPlacement } from './propModels'
import { colonnadeFront, vaultRoof } from './structures'
import { lighthouse } from './lighthouse'
import { dissolvable } from './dissolve'
import { onStandee, stand, standee, texture } from './standee'
import type { MapTheme } from '../themes/types'
import {
  effectiveQuality,
  pixelRatioCap,
  storedDepthBlur,
  type DepthBlur,
  type Quality,
} from 'town-shared/quality'

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
/** 玩家操控的人在走、镜头在动、有操作要马上画时的间隔：60Hz 屏上每帧都画，
 *  120Hz 屏上隔一帧画，最多每秒 60 帧；比 1000/60 少一点，免得刚好差一点点就跳过一帧 */
const MOTION_MS = 1000 / 60 - 2
/** 雾气浓度与镜头距离，按演示页换算：演示页一个单位是一个地图像素 */
const FOG_DENSITY = 0.00042 / PIXEL
const CAMERA_DISTANCE_PER_VIEW_HEIGHT = 2.17
/** 雾只在近景起作用：镜头距离最远取演示页默认的 600 个地图像素，拉远看全图时雾不再加浓 */
const MAX_CAMERA_DISTANCE = 600 * PIXEL
/** 移轴模糊按近景设计：视野高度超过这么多地图单位后按比例减弱，拉远时不把上下两片糊掉 */
const TILT_SHIFT_VIEW_HEIGHT = 2000
/** 路灯在地上照出的光圈半径、门灯和窗光往外投多远（地图单位） */
const LAMP_REACH = 64 * PIXEL
/** 地标立牌身前多少像素不种树（树冠会挡住它），约 200 个地图单位 */
const FRONT_CLEAR = 34
const DOOR_REACH = 16 * PIXEL
const WINDOW_REACH = 22 * PIXEL
/** 屋顶从盖严到全掀开（或反过来）按像素格溶解的时长（毫秒） */
const DISSOLVE_MS = 160
/** 失焦模糊三档（设定 · 显示）：清晰带上下各占画面高度的多少，按画面高度、按远近糊的强度（原来的倍数），
 *  焦点跟着选中的人走的高度范围（从下往上）。「电影感」是原来的样子：人站在画面边上时清晰带跟到边上，
 *  另一半全糊，最糊处半径约 18 个屏幕像素，看全镇时太重；默认「轻」。「关」的清晰带盖满画面，色差也没了 */
const DEPTH_BLUR: Record<
  DepthBlur,
  { band: number; tilt: number; depth: number; follow: readonly [number, number] }
> = {
  off: { band: 1, tilt: 0, depth: 0, follow: [0.18, 0.82] },
  light: { band: 0.32, tilt: 0.34, depth: 0.3, follow: [0.4, 0.6] },
  cinema: { band: 0.16, tilt: 1, depth: 1, follow: [0.18, 0.82] },
}

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

/** 后期：保留场景深度 → 体积光和雾 → 景深（中档两遍高斯移轴，高档以上散景）→ 泛光 → 调色 → 色调映射 → 胶片 LUT。
 *  体积光在景深之前，雾和光柱跟着虚化；泛光在景深之后，散景光斑也会发光 */
function createComposer(
  renderer: THREE.WebGLRenderer,
  scene: THREE.Scene,
  camera: THREE.OrthographicCamera
) {
  const composer = new EffectComposer(renderer)
  const sceneDepth = new SceneDepthPass(scene, camera)
  composer.addPass(sceneDepth)
  const volumetric = new VolumetricPass()
  volumetric.uniforms.tDepth.value = sceneDepth.depthTexture
  composer.addPass(volumetric)
  const tiltShift = [new ShaderPass(tiltShader), new ShaderPass(tiltShader)]
  tiltShift[1].uniforms.dir.value.set(0, 1)
  for (const p of tiltShift) {
    p.uniforms.tDepth.value = sceneDepth.depthTexture
    composer.addPass(p)
  }
  const bokeh = new BokehPass()
  bokeh.uniforms.tDepth.value = sceneDepth.depthTexture
  composer.addPass(bokeh)
  const bloom = new GlowPass()
  composer.addPass(bloom)
  const grade = new ShaderPass(gradeShader)
  composer.addPass(grade)
  composer.addPass(new OutputPass())
  // 色调映射之后再套风格包的胶片 LUT
  const finish = new ShaderPass(finishShader)
  composer.addPass(finish)
  return { composer, sceneDepth, volumetric, bokeh, bloom, tiltShift, grade, finish }
}

/** 窗在墙面贴图上占的列：自发光图里亮着的列连成一段就是一扇窗。返回 [起, 止) 列 */
function windowSpans(emissive: HTMLCanvasElement) {
  const { width: w, height: h } = emissive
  const data = emissive.getContext('2d')!.getImageData(0, 0, w, h).data
  const spans: [number, number][] = []
  let start = -1
  for (let x = 0; x <= w; x++) {
    let lit = false
    for (let y = 0; x < w && y < h && !lit; y++) {
      const o = (y * w + x) * 4
      lit = data[o] + data[o + 1] + data[o + 2] > 60 && data[o + 3] > 0
    }
    if (lit && start < 0) start = x
    if (!lit && start >= 0) {
      spans.push([start, x])
      start = -1
    }
  }
  return spans
}

/** 不画的面（房子贴地的底面） */
const HIDDEN = new THREE.MeshBasicMaterial({ visible: false })

/** 水的粗格子：16 个地面像素一格，格子里有水就记下；外圈是干海床时只算池塘 */
const WATER_CELL = 16
function waterGridOf(ground: Ground, outerWater: boolean) {
  const { width: pw, height: ph, wet, depth } = ground
  const gw = Math.ceil(pw / WATER_CELL),
    gh = Math.ceil(ph / WATER_CELL)
  const cells = new Uint8Array(gw * gh)
  for (let y = 0; y < ph; y++)
    for (let x = 0; x < pw; x++) {
      const i = y * pw + x
      // 干海床的「水」像素是旧海床，不反光；池塘离岸近、depth 小
      if (wet[i] && (outerWater || depth[i] < 6))
        cells[((y / WATER_CELL) | 0) * gw + ((x / WATER_CELL) | 0)] = 1
    }
  return { cells, gw, gh, outerWater }
}

/** 按地点编号找它的地标落在哪儿：和 landmarkSprites 一样取地点格子的外框中心（场景的 x、z 就是地图坐标） */
function landmarkSpot(atlas: Atlas) {
  const regions = new Map(atlas.regions.map((r) => [r.id, r]))
  return (locale: string) => {
    const r = regions.get(locale)
    if (!r?.cells.length) return null
    const xs = r.cells.map(([x]) => x * r.cell_size),
      ys = r.cells.map(([, y]) => y * r.cell_size)
    return {
      x: (Math.min(...xs) + Math.max(...xs) + r.cell_size) / 2,
      z: (Math.min(...ys) + Math.max(...ys) + r.cell_size) / 2,
    }
  }
}

/** 一栋房子的窗和灯在入夜后什么时候亮（亮灯程度的门槛），按房子编号错开 */
const houseLightsOn = (house: House) => 0.12 + hash(house.seed, 3, 11) * 0.62

/** 风格包要秃鹫、地图又没给鸟群时：从干海床上散落的骨头、沉船里挑三处（彼此隔开一段），上空各盘旋一群 */
function carrionFlocks(spots: [number, number][], seed: number) {
  const order = spots
    .map((p, i) => ({ p, k: hash(i, 7, seed) }))
    .sort((a, b) => a.k - b.k)
    .map(({ p }) => p)
  const picked: [number, number][] = []
  for (const p of order) {
    if (picked.length >= 3) break
    if (picked.every((q) => Math.hypot(q[0] - p[0], q[1] - p[1]) > 1500)) picked.push(p)
  }
  return picked.map(([x, y], k) => ({ x, y, height: (60 + k * 14) * PIXEL, count: 2 + (k % 2) }))
}

export class HdScene {
  readonly houses: House[]
  /** 只看不进的楼（地图的 ruins）：只有外壳，不是地点，不掀开 */
  private readonly ruins: House[]
  private readonly renderer: THREE.WebGLRenderer
  private readonly scene = new THREE.Scene()
  private readonly camera = new THREE.OrthographicCamera()
  private readonly composer: EffectComposer
  private readonly sceneDepth: SceneDepthPass
  private readonly bloom: GlowPass
  private readonly bokeh: BokehPass
  private readonly volumetric: VolumetricPass
  private readonly tiltShift: ShaderPass[]
  private readonly grade: ShaderPass
  private readonly finish: ShaderPass
  private readonly sun = new THREE.DirectionalLight('#fff4e0', 2.6)
  /** 天光：颜色和强度由 applyLight 按风格包和时间设置 */
  private readonly hemi = new THREE.HemisphereLight()
  private readonly houseGroups = new Map<string, THREE.Group>()
  /** 掀开后的室内墙，和房子外壳一一对应 */
  private readonly rooms = new Map<string, THREE.Group>()
  /** 每栋房子的开合（见 setOpenRooms）：amount 是外壳去掉的比例，open 是要掀开还是盖回，
   *  from、at 是这次开合起步时的比例和时刻，moving 是还没走完 */
  private readonly reveals = new Map<
    string,
    { amount: { value: number }; open: boolean; from: number; at: number; moving: boolean }
  >()
  /** 溶解的一格多大（画布像素）：画面上一个地图像素 */
  private readonly dissolveCell = { value: 1 }
  /** 有房子正在开合：每帧都画 */
  private roomsMoving = false
  /** 屋里的灯亮着的房子：溶解过半时换 */
  private litRooms = ''
  /** 屋顶刚盖严的房子：地图这时才把屋里的人和道具藏起来、房间名挪回屋顶上方 */
  onRoomsClosed: ((ids: string[]) => void) | null = null
  private readonly partitions = new Map<string, Partition | undefined>()
  private pitchDegrees = storedPitch()
  private yawDegrees = storedYaw()
  private tilt: Tilt = tiltOf(this.pitchDegrees, this.yawDegrees)
  /** 地面、水面和房子 */
  private readonly flat = new THREE.Group()
  /** 路过河的桥（见 pixel/bridges.ts）：人走上去抬高、不留脚印 */
  private bridges: Bridge[] = []
  /** 看台（见 pixel/stands.ts）：人和道具站上台阶按那一级抬高，树、灯、草丛让开 */
  private stands: Stand[] = []
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
  /** 夜里发光的窗、灯罩：亮灯程度超过 on 才亮，入夜时一栋栋、一盏盏错开 */
  private readonly glowing: { material: THREE.Material; on: number }[] = []
  /** 屋顶、山墙和墙顶：夜里按自身颜色发一点微光，房子不至于黑成一片 */
  private readonly moonlit: (THREE.MeshLambertMaterial | THREE.MeshPhongMaterial)[] = []
  /** 门口和灯头的光晕贴片，和各自的灯同时亮 */
  private readonly glows: { sprite: THREE.Sprite; on: number }[] = []
  /** 地面光照图：所有灯、门、窗和掀开的屋子把光洒在地上，地面、墙和立牌按它受光 */
  private readonly lightmap: LightMap
  private readonly lightSources: LightSource[] = []
  /** 水面倒影（见 reflection.ts）；视野里有没有水，没有且地不湿时不画倒影 */
  private readonly reflection = new Reflection()
  private waterVisible = true
  /** 粗格子（16 个地面像素一格）：这一格里有没有水；地面画布以外都是海 */
  private waterGrid: { cells: Uint8Array; gw: number; gh: number } | null = null
  /** 镜头看着的地面点（世界坐标），倒影镜头按它翻转 */
  private readonly viewTarget = new THREE.Vector3()
  /** 地面材质：烘好遮蔽图后接上 */
  private landMaterial: THREE.MeshPhongMaterial | null = null
  /** 树根、灯杆、地标脚下的接触阴影，最后和房子一起烘进地面遮蔽图 */
  private readonly contacts: Contact[] = []
  /** 外圈（干海床、冰原）上散落的东西摆在哪（地图坐标）：要秃鹫的风格在这上面挑几处盘旋 */
  private readonly carrion: [number, number][] = []
  /** 草丛和花（见 grass.ts）、踩踏图（见 trail.ts）、环境里的小动静（见 fauna.ts） */
  private readonly grass: Grass
  private readonly trail: Trail
  private readonly fauna: Fauna
  /** 冒烟的烟囱口（世界坐标）：夜里飘火星 */
  private readonly chimneyMouths: [number, number, number][] = []
  /** 灯塔：地图坐标和灯室的高度，海鸥绕着塔顶飞 */
  private readonly beacons: [number, number, number][] = []
  /** 地面哪些像素是水：脚印落在水里是涟漪 */
  private readonly groundWet: { wet: Uint8Array; width: number; height: number }
  /** GPU 计时（见 perf.ts）：开发版浮层、「自动」画质跑不动时降档 */
  private readonly gpu: GpuTimer
  private overlay: PerfOverlay | null = null
  /** 此刻用的画质档 */
  private quality: Quality = 'high'
  /** 失焦模糊的档（见 DEPTH_BLUR） */
  private depthBlur = storedDepthBlur()
  /** 「自动」画质从什么时候开始量、已经降过几档 */
  private measureFrom = 0
  private drops = 0
  /** 画面想告诉玩家的一句话（降了画质），交给外壳放进事件栏 */
  onNotice?: (text: string) => void
  /** 夜里亮灯的程度：日落前后从 0 升到 1，各盏灯按自己的门槛亮起 */
  private lit = 0
  /** 灯塔转动的光束；光束扫到正对镜头时灯室那一闪 */
  private readonly beams: THREE.Mesh[] = []
  private readonly flares: { beam: THREE.Object3D; sprite: THREE.Sprite }[] = []
  private readonly smoke = new ChimneySmoke()
  /** 温泉冒的白汽；没有温泉的地图没有 */
  private readonly steam?: SpringSteam
  /** 逐帧动画的地标（喷泉）：图集横排，按时间挪贴图的横向偏移 */
  private readonly flipbooks: { maps: THREE.Texture[]; frames: number; fps: number }[] = []
  /** 自己发一点光的地标（喷泉的水），亮度随昼夜变 */
  private readonly selfLit: THREE.MeshLambertMaterial[] = []
  private glowMap!: THREE.Texture
  private pavilions: readonly Pavilion[] = []
  private fountains: readonly Fountain[] = []
  /** 喷泉的水花（粒子）；喷泉边座位的搭法（按座位的位置记） */
  private readonly sprays: FountainSpray[] = []
  private readonly rimSeats = new Map<string, Build | undefined>()
  /** 搭成立体的户外标志物（摊棚、船）：第一件来了才建 */
  private landmarkModels?: LandmarkModels
  private petals?: Petals
  /** 落花的立牌、聚萤火虫的地方：立地标时记下，后面建花瓣和微粒用 */
  private readonly petalSources: (PetalSource & { afloat?: number })[] = []
  private readonly swarms: { x: number; y: number; r: number; count: number }[] = []
  /** 海面动画的时间（秒） */
  private readonly seaTime: { value: number }
  /** 海面闪光的多少：晴天白天多，夜里和阴天少 */
  private readonly seaSparkle: { value: number }
  /** 温泉透出来的光（见 sea.ts） */
  private readonly springGlow: { value: number }
  /** 海面的日光路径（见 sea.ts） */
  private readonly seaPath: ReturnType<typeof outerMaterial>['sunPath']
  /** 焦点跟着的人（选中的村民或玩家操控的人）；在交谈时清晰带收窄 */
  private focusSubject: string | null = null
  private focusTalking = false
  /** 正在用的焦点（从下往上 0～1），往跟着的人那里缓动；没跟人时为 null，按面板遮挡居中 */
  private focusNow: number | null = null
  private focusTalk = 0
  private focusAt = 0
  /** 焦点还在缓动：要每帧画 */
  private focusMoving = false
  private readonly horizon: Horizon
  private readonly observers: { disconnect(): void }[] = []
  private readonly reduceMotion = matchMedia('(prefers-reduced-motion: reduce)')
  private ticker = 0
  /** 有操作带来的变化（拖地图、换角度、开合屋顶）要在下一帧画，不等节拍 */
  private dirty = false
  /** 上一次画的时刻；镜头上一次画的时候还在动 */
  private lastDraw = 0
  private cameraMoving = false
  /** 立体镜头已经按这个 viewBox 设好 */
  private viewBox = ''
  /** 每次画之前、立牌摆好以后调用（玩家操控时的镜头跟随）：返回这一帧挪了镜头。
   *  挪镜头改的 viewBox 当场读进立体镜头，SVG 上的名字和立体画面同一帧到位 */
  beforeDraw?: (t: number) => boolean
  /** 画过第一帧：之后画布改尺寸要当场补画 */
  private drawn = false
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
  private readonly villagers = new Villagers(this.scene, this.tilt, (m) => {
    this.lightmap.shade(m, 'standee')
    for (const look of this.looks) look.shadeStanding(m, 'villager')
  })
  private readonly swayAt = (x: number, z: number) => this.weather.swayAt(x, z)
  /** 灯笼的光：和路灯同色，暗一些 */
  private get lanternColor() {
    return (this._lantern ??= new THREE.Color(this.theme.light.lamp).multiplyScalar(1.1))
  }
  private _lantern?: THREE.Color
  /** 上一拍在打闪：闪电亮起的那一下人才吓一跳 */
  private bolt = false
  /** 游戏分钟：人在外面淋雨、落雪多久按它算 */
  private minutes = 0
  private readonly props = new PropStandees(
    this.scene,
    this.tilt,
    () => this.request(),
    (m) => {
      this.lightmap.shade(m, 'standee')
      for (const look of this.looks) look.shadeStanding(m, 'thing')
    }
  )
  private lastTick = performance.now()
  /** 立体道具（propModels.ts）：第一份道具名单来了才建 */
  private models?: PropModels
  /** 立体道具的光晕：和别的光晕一样按俯角摆、入夜亮，道具拆掉时跟着拆 */
  private readonly modelGlows = new Set<{
    sprite: THREE.Sprite
    on: number
    at: [number, number, number]
  }>()
  /** 每间屋子里人会站的点（落脚点，地图坐标）：陈设让开它们和它们之间的直线 */
  private readonly roomStops = new Map<string, [number, number][]>()
  /** 掀开了的房子：屋里的陈设跟着显隐 */
  private openRooms: ReadonlySet<string> = new Set()
  /** 各间屋子算好的陈设，道具没动就不重算 */
  private readonly decor = new Map<string, { key: string; list: Decor[] }>()

  private readonly theme: MapTheme
  /** 玩法的画面（gameModes/）：地面、海面、立着的东西和村民的着色先装好，名册来了交给它们 */
  private readonly looks: GameModeLook[]
  /** 玩法自己的界面盖在地图上的那一层 */
  private readonly modeLayer = document.createElement('div')

  /** ground 是这张地图算好的地面（pixel/terrain.ts 的 groundOf），场景只读它 */
  constructor(
    atlas: Atlas,
    ground: Ground,
    private container: HTMLElement,
    private svg: SVGSVGElement,
    /** 屋里摆不摆陈设（只给画面看的桌椅、绿植、地毯）：随应用发的内置地图才摆 */
    private readonly furnished = false
  ) {
    const { seed, decor, theme } = ground
    this.theme = theme
    this.looks = gameModeLooks(theme)
    this.renderer = createRenderer(container, svg)
    this.modeLayer.className = 'mode-layer'
    this.modeLayer.style.cssText = 'position:absolute;inset:0;pointer-events:none;overflow:hidden'
    container.append(this.modeLayer)
    for (const look of this.looks) look.mount?.(this.modeLayer)
    this.scene.add(this.flat)
    this.center = [atlas.canvas.width / 2, atlas.canvas.height / 2]

    this.fog = new THREE.FogExp2(theme.light.sky.day, FOG_DENSITY * theme.light.fog)
    this.weather = new Weather3D(this.scene, this.flat, ground, seed)
    this.weather.reflectPuddles(this.reflection.uniforms)
    this.trail = new Trail(ground.width, ground.height)
    this.weather.useTrail(this.trail.uniforms)
    this.groundWet = { wet: ground.wet, width: ground.width, height: ground.height }
    // 主镜头也看「不进倒影」的那一层（地面、海、积水、粒子）
    this.camera.layers.enable(REFLECTION_SKIP)
    this.horizon = new Horizon(
      this.scene,
      { x0: fromPx(0), z0: fromPx(0), x1: fromPx(ground.width), z1: fromPx(ground.height) },
      seed,
      theme.islet
    )
    this.upright.push((t) => this.horizon.setTilt(t))
    this.scene.add(this.smoke.group)
    this.upright.push((t) => this.smoke.setTilt(t))
    this.houses = atlas.spaces.filter((s) => s.id !== OUTDOOR_SPACE).map((s) => houseOf(s, theme))
    this.ruins = (atlas.ruins ?? []).map((r) => ruinOf(r, theme))
    this.pavilions = ground.pavilions
    this.fountains = fountainsOf(atlas)
    // 光照图先建好：后面建的地面、墙和立牌的材质都要接上它
    this.lightmap = new LightMap(ground.width, ground.height, [...this.houses, ...this.ruins])
    const sea = this.addGround(ground)
    if (ground.spring.some(Boolean)) {
      const quality = effectiveQuality()
      const density = quality === 'low' ? 0.35 : quality === 'mid' ? 0.6 : 1
      this.steam = new SpringSteam(ground.spring, ground.width, ground.height, seed, density)
      this.lightmap.shade(this.steam.mesh.material as THREE.Material, 'standee')
      this.steam.mesh.layers.set(REFLECTION_SKIP)
      this.scene.add(this.steam.mesh)
      this.upright.push((t) => this.steam!.setTilt(t))
      // 池水的青光照到池边的雪上
      const teal = new THREE.Color('#2fb8c0').convertSRGBToLinear().multiplyScalar(0.55)
      for (const [x, y] of springShore(ground.spring, ground.width, ground.height))
        this.lightSources.push({ kind: 'lamp', x, y, reach: 26 * PIXEL, color: teal, on: 0.02 })
    }
    this.seaTime = sea.time
    this.seaSparkle = sea.sparkle
    this.springGlow = sea.springGlow
    this.seaPath = sea.sunPath
    const glowMap = new THREE.CanvasTexture(glowCanvas())
    glowMap.colorSpace = THREE.SRGBColorSpace
    this.glowMap = glowMap
    this.addHouses(atlas, glowMap)
    this.addRuins()
    this.addPiers(ground, glowMap, seed)
    this.addBridges(ground, seed)
    this.addStands(atlas, seed)
    // 地标立牌和散落物先占地，剩下的空地再撒树、放微粒
    const open = this.placeStandees(atlas, ground, seed)
    for (const look of this.looks) look.addToScene?.(this.scene, landmarkSpot(atlas))
    const clear = { width: ground.width, height: ground.height, open }
    this.addTrees(decor, clear, seed)
    this.addLamps(atlas, ground.wet, ground.width, glowMap)
    this.lightmap.setSources(this.lightSources)
    // 房子、树根、灯杆、地标脚下的遮蔽烘进地面；粗格子记下哪里有水，没水时不画倒影
    if (this.landMaterial)
      groundAo(
        this.landMaterial,
        groundOcclusion(ground.width, ground.height, [...this.houses, ...this.ruins], this.contacts)
      )
    this.waterGrid = waterGridOf(ground, theme.outer !== 'seabed')
    // 草丛：冰雪里大多埋在雪下，废土里稀疏一些
    const grassDensity = theme.outer === 'ice' ? 0.35 : theme.outer === 'seabed' ? 0.6 : 1
    this.grass = new Grass(
      tuftsOf(decor, clear, seed, grassDensity, mownLawn(theme)),
      theme,
      this.tilt
    )
    Object.assign(this.grass.uniforms, this.weather.windUniforms, this.trail.uniforms)
    this.lightmap.shade(this.grass.surface, 'standee')
    for (const look of this.looks) look.shadeStanding(this.grass.surface, 'thing')
    this.grass.group.traverse((o) => o.layers.set(REFLECTION_SKIP))
    this.scene.add(this.grass.group)
    this.upright.push((t) => this.grass.setTilt(t))
    this.fauna = new Fauna(
      {
        box: { x0: fromPx(0), z0: fromPx(0), x1: fromPx(ground.width), z1: fromPx(ground.height) },
        docks: ground.docks,
        flowers: decor.vegetation.filter((v) => v.kind === 'flowers').map((v) => [v.x, v.y]),
        shallows: theme.outer === 'sea' ? shallowsOf(ground) : [],
        chimneys: this.chimneyMouths,
        towers: this.beacons,
        center: this.center,
        flocks: atlas.flocks ?? (theme.vultures ? carrionFlocks(this.carrion, seed) : []),
      },
      theme,
      seed,
      this.tilt
    )
    // 鱼落水的地方起一圈涟漪
    this.fauna.onSplash = (x, y) => this.trail.add([{ x, y, water: true }])
    this.scene.add(this.fauna.group)
    this.upright.push((t) => this.fauna.setTilt(t))
    // 花树四周萤火虫成群（立牌自己说聚多少，见 addLandmarks）
    this.motes = new Motes(clear, seed, theme.motes, this.swarms)
    this.motes.points.layers.set(REFLECTION_SKIP)
    this.scene.add(this.motes.points)
    // 落花：花瓣从花冠里飘下来；身边有水的，水面上浮几片（往镜头这边多找一些，那边看得见）
    if (this.petalSources.length) {
      const afloat: [number, number][] = []
      const random = rng(seed + 63)
      for (const s of this.petalSources) {
        const reach = s.r * 1.55
        let found = 0
        for (let k = 0; k < (s.afloat ?? 0) * 24 && found < s.afloat!; k++) {
          const x = s.x + (random() - 0.5) * 2 * reach,
            y = s.y + 60 + (random() - 0.3) * reach * 1.16
          if (ground.wet[pxIndex(x, y, ground.width)] !== 1) continue
          afloat.push([x, y])
          found++
        }
      }
      this.petals = new Petals(this.petalSources, afloat, PETAL.pale, PETAL.deep, seed)
      this.petals.points.layers.set(REFLECTION_SKIP)
      this.scene.add(this.petals.points)
    }
    this.scene.fog = this.fog
    this.setupSun(atlas)
    const post = createComposer(this.renderer, this.scene, this.camera)
    this.composer = post.composer
    this.sceneDepth = post.sceneDepth
    // 画场景之前先画倒影：这时镜头已经按这一帧挪好
    this.sceneDepth.prepare = (renderer) => {
      this.gpu.time('踩踏图', () => {
        this.trail.add(this.footprints())
        this.trail.update(renderer, this.weather.snowFalling)
      })
      // 第一帧主画面还没画过阴影贴图：这时画倒影（倒影里不更新阴影），带阴影的材质采样到的是空贴图，
      // 整批绘制被丢掉，Chrome 报几百条“纹理格式和采样器类型对不上”，报满上限后后面真的 WebGL 错误也不报了。
      // 这一帧先不画倒影，下一帧照常
      this.gpu.time('倒影', () =>
        this.reflection.render(
          renderer,
          this.scene,
          this.camera,
          this.viewTarget,
          !!this.sun.shadow.map && (this.waterVisible || this.weather.wetLevel > 0.05)
        )
      )
    }
    this.sceneDepth.onResize = (w, h) => this.reflection.setSize(w, h)
    this.bloom = post.bloom
    this.bokeh = post.bokeh
    this.volumetric = post.volumetric
    this.volumetric.uniforms.tLight.value = this.lightmap.texture
    this.volumetric.uniforms.lightSize.value.set(ground.width * PIXEL, ground.height * PIXEL)
    this.tiltShift = post.tiltShift
    this.grade = post.grade
    this.finish = post.finish
    this.finish.uniforms.tLook.value = lookTexture(theme.light.look)
    this.gpu = new GpuTimer(this.renderer)
    this.timePasses(import.meta.env.DEV && new URLSearchParams(location.search).has('hd-perf'))
    this.measureFrom = performance.now()
    const views = new MutationObserver(() => this.syncView())
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
      const house = this.houses.find((h) => h.id === s.id)!
      this.roomStops.set(
        s.id,
        atlas.stations.filter((p) => p.space === s.id).map((p) => roomPoint(s.unfold, p.x, p.y))
      )
      const on = houseLightsOn(house)
      this.addHouse(house, s.door_outside, points, on, glowMap)
      const lamp = new THREE.Color(this.theme.light.lamp)
      if (s.door_outside) {
        const [dx, dy] = s.door_outside
        this.addGlow(glowMap, dx, dy, 14, 70, on)
        this.lightSources.push({
          kind: 'door',
          x: dx,
          y: dy,
          reach: DOOR_REACH,
          color: lamp.clone().multiplyScalar(0.9),
          on,
        })
      }
      // 掀开屋顶后屋里的灯：整间屋子暖暖地亮
      this.lightSources.push({
        kind: 'room',
        x: house.x + house.w / 2,
        y: house.y + house.h / 2,
        width: house.w / 2,
        reach: house.h / 2,
        color: lamp.clone().multiplyScalar(0.55),
        on,
        house: house.id,
      })
    }
  }

  /** 只看不进的楼：墙和屋顶照房子搭（一层一排窗，夜里零星几扇亮），没有门、室内，
   *  亮着的窗高高在楼上，不往楼脚的地面投光斑；不掀开 */
  private addRuins() {
    for (const house of this.ruins) {
      const group = new THREE.Group()
      group.position.set(house.x + house.w / 2, 0, house.y + house.h / 2)
      const on = houseLightsOn(house)
      const top = this.addBody(group, house, undefined, on, false)
      this.addRoof(group, house, top, on)
      this.flat.add(group)
    }
  }

  /** 墙上每扇窗往外投一块光：四面墙贴的是同一张墙面图（见 addBody），窗按比例落在各面墙上 */
  private addWindowLights(house: House, emissive: HTMLCanvasElement, on: number) {
    const { x, y, w, h } = house
    const color = new THREE.Color(this.theme.light.lamp).multiplyScalar(0.8)
    const len = emissive.width
    for (const [a, b] of windowSpans(emissive)) {
      const f = (a + b) / 2 / len,
        part = (b - a) / len
      // BoxGeometry 各面贴图的横向：南面从西到东，北面从东到西，东面从南到北，西面从北到南
      const sides: [number, number, number, [number, number]][] = [
        [x + f * w, y + h, part * w, [0, 1]],
        [x + (1 - f) * w, y, part * w, [0, -1]],
        [x + w, y + (1 - f) * h, part * h, [1, 0]],
        [x, y + f * h, part * h, [-1, 0]],
      ]
      for (const [sx, sy, width, dir] of sides)
        this.lightSources.push({
          kind: 'window',
          x: sx,
          y: sy,
          width: Math.max(width, 2 * PIXEL),
          reach: WINDOW_REACH,
          dir,
          color,
          on,
          house: house.id,
        })
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

  /** 节拍：跟着屏幕刷新走。玩家操控的人在走、镜头在动、有操作要马上画时每帧都画（最多每秒 60 帧），
   *  不然每秒约 30 拍（60Hz 屏隔一帧一拍），环境变化只在拍上画。帧距均匀，走路才匀；一帧最多画一遍 */
  private loop = (t: number) => {
    this.ticker = requestAnimationFrame(this.loop)
    const fast =
      this.dirty ||
      this.cameraMoving ||
      this.focusMoving ||
      this.roomsMoving ||
      this.villagers.liveActive()
    if (fast ? t - this.lastDraw >= MOTION_MS : t - this.lastTick >= BEAT_MS) this.tick(t, fast)
  }

  /** 村民走动、水面波纹、空气微粒和天气按节拍推进，画面有变化（或 fast）才重画。
   *  页面隐藏或地图没显示出来时停下；要求减少动画时海、微粒和树都不动，只有村民走动和天气变化时重画 */
  private tick(t: number, fast = false) {
    const dt = Math.min(0.1, (t - this.lastTick) / 1000)
    this.lastTick = t
    if (document.hidden || !this.container.clientWidth) return
    if (this.roomsMoving) this.stepRooms(t)
    let changed = fast || this.villagers.active() || this.villagers.pending()
    const weather = this.weather.step(dt, t / 1000, this.day)
    // 闪电：在外面的人吓一跳
    const bolt = this.weather.flash > 0.5
    if (bolt && !this.bolt) this.villagers.startle()
    this.bolt = bolt
    if (weather.light) this.applyLight(false)
    for (const look of this.looks) if (look.step?.(t / 1000)) changed = true
    changed ||= weather.changed || this.ambient
    this.ambient = false
    if (!this.reduceMotion.matches) {
      this.seaTime.value = t / 1000
      this.volumetric.uniforms.time.value = t / 1000
      this.fauna.step(t / 1000)
      this.motes.step(t)
      this.petals?.step(t)
      for (const s of this.sprays) s.step(t)
      this.landmarkModels?.step(t / 1000)
      this.horizon.step(t / 1000)
      for (const b of this.beams) b.rotation.y -= dt * 0.9
      this.flare()
      this.smoke.step(t / 1000)
      this.models?.step(t / 1000)
      this.steam?.step(t / 1000)
      for (const b of this.flipbooks)
        for (const m of b.maps) m.offset.x = (Math.floor((t / 1000) * b.fps) % b.frames) / b.frames
      changed = true
    }
    if (changed) this.draw(t)
  }

  /** 画一帧：立牌先摆到这一帧那一刻的位置，名字跟上；镜头按立牌挪好、读进立体镜头，再画 */
  private draw(t: number) {
    this.lastDraw = t
    // 人的头发跟着风场摆，要求减少动画时呼吸、眨眼这些小动作也停
    this.villagers.setAir(this.weather.calm, this.swayAt)
    if (this.villagers.step(t)) this.onVillagersMoved?.()
    // 提着的灯笼是会走的灯：人走到哪，光照图上那一块跟着重画；打着伞的人头顶不落雨
    this.lightmap.setCarried(this.villagers.lanterns(), this.lanternColor)
    if (this.weather.rainLevel > 0) this.weather.setUmbrellas(this.villagers.umbrellas())
    this.lightmap.render(this.renderer)
    this.cameraMoving = this.beforeDraw?.(t) ?? false
    this.stepFocus(t)
    this.finish.uniforms.seed.value = (t * 0.37) % 100
    this.syncView()
    this.dirty = false
    this.composer.render()
    this.drawn = true
  }

  /** 当场画一帧，把画布正中间（和小图同样长宽比的那块）缩成 width×height 的小图。这一帧不画失焦模糊，
   *  也不叫镜头的钩子（调用方已经摆好机位）；restore 把机位摆回去，接着补画一帧——两帧在同一拍里画完，
   *  屏幕上只看得到后一帧 */
  capture(width: number, height: number, restore: () => void): HTMLCanvasElement {
    const hook = this.beforeDraw
    const bokeh = this.bokeh.enabled
    const tilt = this.tiltShift.map((p) => p.enabled)
    this.beforeDraw = undefined
    this.bokeh.enabled = false
    for (const p of this.tiltShift) p.enabled = false
    this.draw(performance.now())
    const image = this.copy(width, height)
    this.bokeh.enabled = bokeh
    this.tiltShift.forEach((p, i) => (p.enabled = tilt[i]))
    this.beforeDraw = hook
    restore()
    this.draw(performance.now())
    return image
  }

  /** 此刻的画面，原样拍下来（宽不超过 maxWidth） */
  grab(maxWidth: number): HTMLCanvasElement {
    this.draw(performance.now())
    const source = this.renderer.domElement
    const width = Math.max(1, Math.min(maxWidth, source.width))
    return this.copy(width, Math.max(1, Math.round((source.height * width) / source.width)))
  }

  /** 画布正中间、和小图同样长宽比的那块，缩成 width×height。画布不留上一帧，要紧跟在 draw 后面拷 */
  private copy(width: number, height: number): HTMLCanvasElement {
    const source = this.renderer.domElement
    const image = document.createElement('canvas')
    image.width = width
    image.height = height
    const k = Math.max(width / source.width, height / source.height)
    const w = width / k,
      h = height / k
    image
      .getContext('2d')
      ?.drawImage(
        source,
        (source.width - w) / 2,
        (source.height - h) / 2,
        w,
        h,
        0,
        0,
        width,
        height
      )
    return image
  }

  /** 玩家操控的人的本地预测（见 villagers.ts 的 LiveMotion）；没在操控时为空 */
  setLiveMotion(motion: LiveMotion | null) {
    this.villagers.setLiveMotion(motion)
    this.request()
  }

  /** 下一帧画（不等节拍）：镜头要开始挪了之类 */
  requestDraw() {
    this.request()
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

  /** 离地 height 高的一点在屏幕上高出它脚下多少，折成地图纵深 */
  rise(height: number) {
    return riseOf(height, this.tilt)
  }

  setPitch(degrees: number) {
    this.setAngles(degrees, this.yawDegrees)
  }

  setYaw(degrees: number) {
    this.setAngles(this.pitchDegrees, degrees)
  }

  /** 俯角和转角一起设；exact 时俯角不取整、也不记到本机（重演拍素材时逐帧连续地转） */
  setAngles(pitch: number, yaw: number, exact = false) {
    if (!Number.isFinite(pitch) || !Number.isFinite(yaw)) return
    const clamped = Math.min(PITCH_MAX, Math.max(PITCH_MIN, pitch))
    const next = exact ? clamped : Math.round(clamped)
    const nextYaw = normalizeYaw(yaw)
    if (next === this.pitchDegrees && nextYaw === this.yawDegrees) return
    this.pitchDegrees = next
    this.yawDegrees = nextYaw
    this.tilt = tiltOf(next, nextYaw)
    if (!exact)
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

  /** 画质：低档直接画场景，不拷贝深度颜色目标，关掉泛光、景深、色差和颗粒；中档是两遍高斯的移轴模糊；
   *  高档以上换成散景景深、打开体积光和雾 */
  setQuality(quality: Quality) {
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, pixelRatioCap(quality)))
    this.composer.setPixelRatio(this.renderer.getPixelRatio())
    const low = quality === 'low',
      mid = quality === 'mid'
    this.bloom.enabled = !low
    this.sceneDepth.captureDepth = !low
    // 倒影镜头和多重采样只在高档以上；中档海面只反射天色和日光路径。
    // 2 倍像素比的屏幕本身就够细，再开 4× 多重采样看不出差别、渲染目标却要多占几百兆，只在 1.5 倍以下开
    this.reflection.enabled = !low && !mid
    this.sceneDepth.setSamples(!low && !mid && this.renderer.getPixelRatio() < 1.6 ? 4 : 0)
    // 极致档：体积光和倒影更细、散景采样加倍
    const ultra = quality === 'ultra'
    this.bokeh.taps = ultra ? 48 : 24
    this.volumetric.setDetail(ultra ? 0.5 : 0.25, ultra ? 20 : 12)
    this.reflection.setScale(ultra ? 0.5 : 0.34)
    // 草丛中档一半；踩踏和小动物低档不要
    this.grass.setDensity(low ? 0 : mid ? 0.5 : 1)
    this.trail.enabled = !low
    // 村民按像素法线分明暗、头发高光、金属闪点：高档以上
    villagerLight.uShape.value = low || mid ? 0 : 1
    this.quality = quality
    this.enableBlurPasses()
    this.volumetric.enabled = !low && !mid
    this.finish.uniforms.grain.value = low ? 0 : mid ? 0.025 : 0.035
    this.finish.uniforms.aberration.value = low || mid ? 0 : 0.012
    this.resize()
    this.applyLight()
  }

  /** 失焦模糊换档（设定 · 显示） */
  setDepthBlur(level: DepthBlur) {
    if (level === this.depthBlur) return
    this.depthBlur = level
    this.enableBlurPasses()
    this.updateTiltShift()
    this.request()
  }

  /** 景深按画质画：中档两遍高斯移轴，高档以上散景；失焦模糊「关」时两种都不画 */
  private enableBlurPasses() {
    const on = this.depthBlur !== 'off'
    for (const p of this.tiltShift) p.enabled = on && this.quality === 'mid'
    this.bokeh.enabled = on && this.quality !== 'mid' && this.quality !== 'low'
  }

  /** 焦点跟着谁：选中的村民或玩家操控的人（null 回到画面中间）；talking 时清晰带收窄，像对话时的特写 */
  setFocusSubject(id: string | null, talking = false) {
    if (id === this.focusSubject && talking === this.focusTalking) return
    this.focusSubject = id
    this.focusTalking = talking
    this.request()
  }

  /** 跟着的人的身子在画面上的高度（从下往上 0～1），只在这一档跟人的范围里跟；不在画面里时为 undefined */
  private subjectFocus() {
    const at = this.focusSubject && this.villagers.drawnAt(this.focusSubject)
    if (!at) return
    const p = new THREE.Vector3(at[0], 0, at[1]).project(this.camera)
    const half = VILLAGER_HEIGHT / (this.camera.top - this.camera.bottom)
    const y = (p.y + half) * 0.5 + 0.5
    const [low, high] = DEPTH_BLUR[this.depthBlur].follow
    return y > 0.02 && y < 0.98 && Math.abs(p.x) < 1 ? Math.max(low, Math.min(high, y)) : undefined
  }

  /** 每帧画之前：焦点往跟着的人那里缓动，约 400 毫秒到位；交谈时清晰带慢慢收窄 */
  private stepFocus(t: number) {
    const dt = Math.min(0.1, Math.max(0, (t - this.focusAt) / 1000))
    this.focusAt = t
    const target = this.subjectFocus()
    const k = 1 - Math.exp(-dt / 0.12)
    const talk = this.focusTalking && target !== undefined ? 1 : 0
    let moving = Math.abs(talk - this.focusTalk) > 0.01
    this.focusTalk += (talk - this.focusTalk) * k
    if (target !== undefined) {
      const from = this.focusNow ?? this.defaultFocus()
      this.focusNow = from + (target - from) * k
      moving ||= Math.abs(target - this.focusNow) > 0.002
    } else if (this.focusNow !== null) {
      const home = this.defaultFocus()
      this.focusNow += (home - this.focusNow) * k
      if (Math.abs(home - this.focusNow) < 0.002) this.focusNow = null
      else moving = true
    }
    if (moving || this.focusMoving) this.updateTiltShift()
    this.focusMoving = moving
  }

  /** 没跟人时的焦点：画面中间稍低，跟着没被面板盖住的那块地图走 */
  private defaultFocus() {
    const h = this.container.clientHeight
    const [top, bottom] = this.focusInsets
    const centre = top + Math.max(0, h - top - bottom) / 2
    return h ? TILT_FOCUS + (h / 2 - centre) / h : TILT_FOCUS
  }

  private updateTiltShift() {
    const pr = this.renderer.getPixelRatio()
    const near = Math.min(1, TILT_SHIFT_VIEW_HEIGHT / this.viewHeight)
    // 低角度保留前、中、后景层次；转向俯视时逐渐收小离焦，方便读地图与选中人物。
    const overhead = smooth(52, PITCH_MAX, this.pitchDegrees)
    const level = DEPTH_BLUR[this.depthBlur]
    const amount = lerp(3.2, 0.35, overhead) * pr * near * level.tilt
    // 清晰带跟着选中的人；没选人时跟着露出来的那块地图走：手机上村民卡盖住下半屏时，上半屏选中的人不糊。
    // 交谈时收窄一截，像对话时的特写
    const focus = this.focusNow ?? this.defaultFocus()
    const band = level.band - 0.06 * this.focusTalk
    const depthSpan = (this.viewHeight * this.tilt.cos) / this.tilt.sin
    const distance = Math.min(
      this.viewHeight * CAMERA_DISTANCE_PER_VIEW_HEIGHT,
      MAX_CAMERA_DISTANCE
    )
    for (const u of [...this.tiltShift.map((p) => p.uniforms), this.bokeh.uniforms]) {
      u.amount.value = amount
      u.focus.value = focus
      u.band.value = band
      u.depthAmount.value = 2.4 * (1 - overhead) * pr * near * level.depth
      u.cameraNear.value = this.camera.near
      u.cameraFar.value = this.camera.far
      u.focusDepth.value = distance + (focus - 0.5) * depthSpan
      u.focusRange.value = Math.max(24 * PIXEL, depthSpan * (0.19 - 0.06 * this.focusTalk))
      u.depthFalloff.value = Math.max(48 * PIXEL, depthSpan * 0.3)
    }
    this.finish.uniforms.focus.value = focus
    this.finish.uniforms.band.value = band
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
      pixelMaterial(new THREE.MeshPhongMaterial({ map: texture(land), alphaTest: 0.5 }))
    )
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(w, h), landMaterial)
    ground.rotation.x = -Math.PI / 2
    ground.position.set(-MARGIN + w / 2, 0, -MARGIN + h / 2)
    ground.receiveShadow = true
    const coast = coastTexture(terrain.depth, terrain.shore, terrain.calm, pw, ph, wet)
    const { material, time, sparkle, sunPath, springGlow } = outerMaterial(
      coast,
      this.horizon.haze,
      this.theme,
      this.reflection.uniforms,
      this.trail.uniforms
    )
    // 海面也有云影，风和雨从天气里来
    this.weather.shade(material, { snow: 0, wet: 0 })
    if (this.theme.outer === 'sea') surfOnLand(landMaterial, coast, time, this.theme)
    this.lightmap.shade(landMaterial, 'ground')
    wetReflection(landMaterial, this.reflection.uniforms, 'ground')
    for (const look of this.looks) {
      look.shadeGround(landMaterial, 'land')
      look.shadeGround(material, 'sea')
    }
    this.landMaterial = landMaterial
    const sea = new THREE.Mesh(new THREE.PlaneGeometry(w * 6, h * 6), material)
    sea.rotation.x = -Math.PI / 2
    sea.position.set(ground.position.x, -1, ground.position.z)
    sea.receiveShadow = true
    ground.layers.set(REFLECTION_SKIP)
    sea.layers.set(REFLECTION_SKIP)
    this.flat.add(ground, sea)
    return { time, sparkle, sunPath, springGlow }
  }

  /** on：这栋房子的窗和灯在亮灯程度超过它时亮 */
  private addHouse(
    house: House,
    door: [number, number] | undefined,
    points: [number, number][],
    on: number,
    glowMap: THREE.Texture
  ) {
    const { x, y, w, h } = house
    const group = new THREE.Group()
    group.position.set(x + w / 2, 0, y + h / 2)
    // 灯塔掀开后是剖开的灯塔，别的房子是矮墙围起来的房间（见 interior.ts）
    let room: { group: THREE.Group; glowing: THREE.Material[]; partition?: Partition }
    if (house.tower) room = this.addLighthouse(group, house, door, on, glowMap)
    else {
      const inside = interior(house, door, points)
      room = { ...inside, glowing: [inside.glowing] }
      // 只有朝南的墙面向镜头；门在南墙上时画出来
      const onSouth = door && Math.abs(door[1] - (y + h)) <= Math.min(Math.abs(door[1] - y), 40)
      const top = this.addBody(group, house, onSouth ? (door![0] - x) / PIXEL : undefined, on)
      this.addRoof(group, house, top, on)
      this.addFeatures(group, house, onSouth ? door![0] - (x + w / 2) : undefined)
      this.addChimney(group, house)
    }
    this.flat.add(group)
    this.houseGroups.set(house.id, group)
    // 外壳的材质都是这栋自己的（看不见的底面除外），共用一个溶解程度
    const amount = { value: 0 }
    const materials = new Set<THREE.Material>()
    group.traverse((o) => {
      if (o instanceof THREE.Mesh)
        for (const m of [o.material].flat() as THREE.Material[]) if (m !== HIDDEN) materials.add(m)
    })
    for (const m of materials)
      dissolvable(m, { uDissolve: amount, uDissolveCell: this.dissolveCell })
    this.reveals.set(house.id, { amount, open: false, from: 0, at: 0, moving: false })
    this.flat.add(room.group)
    this.rooms.set(house.id, room.group)
    this.partitions.set(house.id, room.partition)
    for (const material of room.glowing) this.glowing.push({ material, on })
  }

  /** 房子的墙：朝镜头的墙面贴画好的墙（夜里窗户发光），墙顶压深色；door 是门离墙左端的像素数，
   *  lights 为 false 时亮着的窗不往地上投光斑。返回墙顶的材质，夜里和屋顶一起微亮 */
  private addBody(
    group: THREE.Group,
    house: House,
    door: number | undefined,
    on: number,
    lights = true
  ) {
    const { w, h, wallH } = house
    const wall = wallCanvases(house, Math.max(4, Math.round(w / PIXEL)), door)
    const front = pixelMaterial(
      new THREE.MeshLambertMaterial({
        map: texture(wall.map),
        emissiveMap: texture(wall.emissive),
        emissive: new THREE.Color('#ffffff'),
        emissiveIntensity: 0,
      })
    )
    this.glowing.push({ material: front, on })
    if (lights) this.addWindowLights(house, wall.emissive, on)
    this.weather.shade(front, { snow: 0, wet: 0.5 })
    this.lightmap.shade(front, 'wall')
    wallAo(front, wallH)
    const top = new THREE.MeshLambertMaterial({ color: WALL_CAP, emissive: WALL_CAP })
    this.weather.shade(top, { snow: 1, wet: 0.5 })
    // 底面贴着地面，主画面里看不到；倒影镜头从水面下往上看时它会挡住墙，不画
    const body = new THREE.Mesh(new THREE.BoxGeometry(w, wallH, h), [
      front,
      front,
      top,
      HIDDEN,
      front,
      front,
    ])
    body.position.y = wallH / 2
    body.castShadow = body.receiveShadow = true
    group.add(body)
    return top
  }

  /** 屋顶：斜面、两头山墙、南坡上的十字脊或老虎窗（形状见 roofs.ts），剧院是拱顶 */
  private addRoof(group: THREE.Group, house: House, top: THREE.MeshLambertMaterial, on: number) {
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
      pixelMaterial(
        new THREE.MeshPhongMaterial({
          map: roofMap,
          emissiveMap: roofMap,
          emissive: '#ffffff',
          side: THREE.DoubleSide,
        })
      )
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
      const material = pixelMaterial(
        new THREE.MeshLambertMaterial({
          map: texture(art.map),
          emissiveMap: texture(art.emissive),
          emissive: new THREE.Color('#ffffff'),
          emissiveIntensity: 0,
          side: THREE.DoubleSide,
        })
      )
      this.glowing.push({ material, on })
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
    const side = pixelMaterial(
      new THREE.MeshLambertMaterial({
        map: texture(chimneyCanvas(house, Math.round(height / WALL_TEXEL))),
      })
    )
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
    if (look.smoke) {
      this.smoke.add(group.position.x + x, top + WALL_TEXEL, group.position.z + z, house.seed)
      this.chimneyMouths.push([group.position.x + x, top + WALL_TEXEL, group.position.z + z])
    }
  }

  /** 功能类型的立体特征：门口的条纹雨棚、柱廊门前的一排石柱 */
  private addFeatures(group: THREE.Group, house: House, doorX?: number) {
    const { w, h, wallH, look } = house
    if (look.awning && doorX !== undefined) {
      const [doorW, doorH] = DOORS[look.door]
      const width = look.awning.whole ? w - 4 * PIXEL : (doorW + 10) * PIXEL
      const cx = look.awning.whole
        ? 0
        : Math.max(-w / 2 + width / 2, Math.min(w / 2 - width / 2, doorX))
      const depth = 6 * PIXEL,
        tilt = 0.5
      const map = texture(awningCanvas(Math.max(4, Math.round(width / PIXEL)), look.awning.colors))
      const material = pixelMaterial(
        new THREE.MeshLambertMaterial({
          map,
          side: THREE.DoubleSide,
          alphaTest: 0.5,
        })
      )
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
  }

  /** 灯塔整块占地是石台，塔立在正中（见 lighthouse.ts）。材质接上天气和光照图；灯室天一暗就最先亮，
   *  塔窗、台阶灯跟这栋房子的灯一起亮。光晕往镜头那边挪一点，不被灯罩自己挡住；火盆的烟和火星从盆口冒。
   *  返回掀开屋顶后的样子：剖开的灯塔 */
  private addLighthouse(
    group: THREE.Group,
    house: House,
    door: [number, number] | undefined,
    on: number,
    glowMap: THREE.Texture
  ) {
    const [cx, cz] = [group.position.x, group.position.z]
    const built = lighthouse(house, door && [door[0] - cx, door[1] - cz], this.theme.lighthouse)
    group.add(built.group)
    for (const { material, snow, wet, sway } of built.weathered)
      this.weather.shade(material, { snow, wet, sway })
    for (const m of built.walls) this.lightmap.shade(m, 'wall')
    for (const m of built.grounds) this.lightmap.shade(m, 'ground')
    for (const g of built.glowing) this.glowing.push({ material: g.material, on: g.on ?? on })
    this.selfLit.push(...built.burning)
    const glow = (at: THREE.Vector3, size: number) => {
      const sprite = new THREE.Sprite(
        new THREE.SpriteMaterial({
          map: glowMap,
          blending: THREE.AdditiveBlending,
          depthWrite: false,
          transparent: true,
          opacity: 0,
        })
      )
      sprite.scale.set(size, size, 1)
      const near = 6 * PIXEL
      this.upright.push((t) =>
        sprite.position.set(
          at.x + near * t.yawSin * t.cos,
          at.y + near * t.sin,
          at.z + near * t.yawCos * t.cos
        )
      )
      group.add(sprite)
      return sprite
    }
    for (const g of built.glows) this.glows.push({ sprite: glow(g.at, g.size), on: g.on ?? on })
    if (built.lamp) this.beacons.push([cx, cz, built.lamp.y])
    if (built.beam) {
      this.beams.push(built.beam as THREE.Mesh)
      if (built.lamp) this.flares.push({ beam: built.beam, sprite: glow(built.lamp, 100 * PIXEL) })
    }
    for (const s of built.smoke) {
      this.smoke.add(cx + s.x, s.y, cz + s.z, house.seed)
      this.chimneyMouths.push([cx + s.x, s.y, cz + s.z])
    }
    built.room.group.position.copy(group.position)
    return built.room
  }

  /** 光束扫到正对镜头时灯室一闪：两束光里离镜头水平方向最近的那束越正越亮，只在天黑后 */
  private flare() {
    const { yawSin, yawCos } = this.tilt
    for (const { beam, sprite } of this.flares) {
      const a = beam.rotation.y
      const facing = Math.abs(Math.cos(a) * yawSin - Math.sin(a) * yawCos)
      sprite.material.opacity = this.lit * 0.5 * facing ** 24
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
      shore: Uint8Array
      docks: Dock[]
    },
    seed: number
  ) {
    const open = terrain.open.slice()
    this.clearStands(open, terrain.width, terrain.height)
    this.addGazebos(atlas, open, terrain.width, seed)
    this.addFountains(open, terrain.width, seed)
    this.addLandmarks(atlas, terrain.docks, open, terrain.width, seed)
    this.addScatter(terrain, open, seed)
    return open
  }

  /** 立体的凉亭（位置见 pixel/pavilions.ts，搭法见 gazebo.ts）：接上天气和灯光，檐角的灯笼和亭里的吊灯
   *  入夜亮起来、照亮台面；占地和身前一片不撒树 */
  private addGazebos(atlas: Atlas, open: Uint8Array, pw: number, seed: number) {
    const color = new THREE.Color('#ffb768').multiplyScalar(1.3)
    for (const s of this.pavilions) {
      const own = Math.floor(hash(Math.round(s.x), Math.round(s.y), seed + 53) * 1e6)
      const built = buildGazebo(s.x, s.y, own, s.facing)
      this.weather.shade(built.top, { snow: 1, wet: 0.5 })
      this.weather.shade(built.sides, { snow: 0, wet: 0.5 })
      this.weather.shade(built.rail, { snow: 0, wet: 0.3 })
      this.weather.shade(built.roof, { snow: 1, wet: 0.5 })
      this.lightmap.shade(built.top, 'ground')
      this.lightmap.shade(built.sides, 'wall')
      this.lightmap.shade(built.rail, 'wall')
      this.moonlit.push(built.roof)
      this.flat.add(built.group)
      const on = 0.1
      this.glowing.push({ material: built.lamps, on })
      for (const [lx, ly, lz] of built.lampSpots) this.addGlow(this.glowMap, lx, lz, 0, 58, on, ly)
      this.lightSources.push({ kind: 'lamp', x: s.x, y: s.y, reach: 230, color, on })
      this.contacts.push({ x: s.x, y: s.y, r: (PAVILION_REACH / PIXEL) * 0.85, strength: 0.4 })
      const reach = Math.ceil(PAVILION_REACH / PIXEL) + 2
      for (let dy = -reach; dy <= reach + FRONT_CLEAR; dy++)
        for (let dx = -reach; dx <= reach; dx++) {
          const i = pxIndex(s.x + dx * PIXEL, s.y + dy * PIXEL, pw)
          if (i < 0 || i >= open.length) continue
          if (Math.hypot(dx, dy) <= reach) open[i] = OPEN.none
          else if (dy > 0 && open[i] !== OPEN.none) open[i] = OPEN.verge
        }
    }
  }

  /** 立体的喷泉（位置、大小见 pixel/fountains.ts，搭法见 fountain.ts），样子按风格包：接上天气和灯光；
   *  流水的池面逐帧翻、水花是粒子，入夜池灯把水照亮、四周地面映一圈青光；占地不种树、不长草 */
  private addFountains(open: Uint8Array, pw: number, seed: number) {
    const look = this.theme.landmarks.fountain
    for (const f of this.fountains) {
      const own = Math.floor(hash(Math.round(f.x), Math.round(f.y), seed + 59) * 1e6)
      const built = buildFountain(f, look, own)
      this.weather.shade(built.top, { snow: 1, wet: 0.5 })
      this.weather.shade(built.sides, { snow: 0, wet: 0.5 })
      this.lightmap.shade(built.top, 'ground')
      this.lightmap.shade(built.sides, 'wall')
      for (const m of built.water) {
        // 冰面、干池底和地面一样积雪淋湿，流水不积
        if (!built.spray) this.weather.shade(m, { snow: 1, wet: 0.4 })
        this.lightmap.shade(m, 'ground')
      }
      this.flat.add(built.group)
      if (built.flipbook) this.flipbooks.push(built.flipbook)
      if (built.spray) {
        for (const m of built.water) this.glowing.push({ material: m, on: 0.12 })
        built.spray.points.layers.set(REFLECTION_SKIP)
        this.scene.add(built.spray.points)
        this.sprays.push(built.spray)
        const color = new THREE.Color('#6fc4f0').convertSRGBToLinear().multiplyScalar(0.45)
        this.lightSources.push({
          kind: 'lamp',
          x: f.x,
          y: f.y,
          reach: 170 * f.scale,
          color,
          on: 0.12,
        })
      }
      const reach = (FOUNTAIN.step * f.scale) / PIXEL
      this.contacts.push({ x: f.x, y: f.y, r: reach * 0.95, strength: 0.35 })
      const clear = Math.ceil(reach) + 2
      for (let dy = -clear; dy <= clear; dy++)
        for (let dx = -clear; dx <= clear; dx++) {
          const i = pxIndex(f.x + dx * PIXEL, f.y + dy * PIXEL, pw)
          if (i >= 0 && i < open.length && Math.hypot(dx, dy) <= clear) open[i] = OPEN.none
        }
    }
  }

  /** 看台上和看台跟前不种树、不长草：台阶连同前面一片（镜头在南边，前面的树会挡住台阶） */
  private clearStands(open: Uint8Array, pw: number, ph: number) {
    const MARGIN_PX = 3,
      FRONT = 120
    for (const s of this.stands) {
      const x0 = Math.max(0, toPx(s.x - s.r - FRONT)),
        x1 = Math.min(pw - 1, toPx(s.x + s.r + FRONT))
      const y0 = Math.max(0, toPx(s.y - s.r - FRONT)),
        y1 = Math.min(ph - 1, toPx(s.y + s.r + FRONT))
      for (let py = y0; py <= y1; py++)
        for (let px = x0; px <= x1; px++) {
          const x = fromPx(px) + PIXEL / 2,
            y = fromPx(py) + PIXEL / 2
          const near = standGap([s], x, y) < MARGIN_PX * PIXEL
          // 镜头那一侧（朝南）再空出一片，树冠不压到台阶上
          const front = Math.abs(x - s.x) < s.r && y > s.y && y - s.y < s.r + FRONT
          if (near || front) open[py * pw + px] = OPEN.none
        }
    }
  }

  /** 户外地点的标志物立牌和地图按坐标立的立牌；立牌占的地方从空地里去掉。
   *  带灯光的立牌（火盆、霓虹）照亮脚下一圈地面，蹲在楼顶的抬到那栋楼的墙顶 */
  private addLandmarks(atlas: Atlas, docks: Dock[], open: Uint8Array, pw: number, seed: number) {
    const { wet, width, height } = this.groundWet
    const water = (x: number, y: number) => {
      const px = toPx(x),
        py = toPx(y)
      return px >= 0 && py >= 0 && px < width && py < height && wet[py * width + px] === 1
    }
    const set = this.theme.landmarks
    const buildings = [...this.houses, ...this.ruins]
    for (const s of [
      ...landmarkSprites(atlas, seed, docks, set, water),
      ...mapStandees(atlas, seed, set),
    ]) {
      if ('model' in s) {
        this.addLandmarkModel(s, buildings, open, pw)
        continue
      }
      // 逐帧动画的立牌按一帧的宽度算
      const frames = s.frames ?? 1,
        width = s.canvas.width / frames
      const perch = s.on ? buildings.find((h) => h.id === s.on) : undefined
      if (s.on && !perch) continue
      // 占地和房子重叠的不放（默认小镇的市集中间就有一栋房子）；蹲在楼顶的不算
      const half = (width / 2) * PIXEL,
        deep = s.canvas.height * 0.4 * PIXEL
      if (
        !perch &&
        buildings.some(
          (h) => s.x + half > h.x && s.x - half < h.x + h.w && s.y > h.y && s.y - deep < h.y + h.h
        )
      )
        continue
      const map = texture(s.canvas),
        glow = s.glow && texture(s.glow)
      const mesh = standee(map, { frame: [width, s.canvas.height], emissive: glow })
      const material = mesh.material as THREE.MeshLambertMaterial
      if (glow) {
        if (s.lamp) this.glowing.push({ material, on: s.light?.on ?? 0.1 })
        else this.selfLit.push(material)
      }
      if (frames > 1) {
        const maps = glow ? [map, glow] : [map]
        for (const m of maps) m.repeat.x = 1 / frames
        this.flipbooks.push({ maps, frames, fps: s.fps ?? 1 })
      }
      this.weather.shade(material, { snow: 1, wet: 0.4, ...(s.plant ? { sway: true } : {}) })
      this.lightmap.shade(material, s.plant && s.canvas.height > 60 ? 'canopy' : 'standee')
      if (s.plant && mesh.customDepthMaterial) this.weather.swayShadow(mesh.customDepthMaterial)
      this.standing(mesh)
      const sx = Math.round(s.x / PIXEL) * PIXEL,
        sy = Math.round(s.y / PIXEL) * PIXEL
      for (const [dx, up, size] of s.halos ?? [])
        this.addGlow(this.glowMap, sx + dx * PIXEL, sy, up, size, s.light?.on ?? 0.1)
      if (s.sheds) this.petalSources.push({ x: sx, y: sy, ...s.sheds })
      // 萤火虫聚在立牌身前一点：镜头那一侧
      if (s.swarm) this.swarms.push({ x: sx, y: sy + 120, ...s.swarm })
      if (perch) {
        const lift = perch.wallH
        this.upright.push((t) => {
          stand(mesh, sx, sy, t)
          mesh.position.y += lift
        })
        this.scene.add(mesh)
        continue
      }
      this.upright.push((t) => stand(mesh, sx, sy, t))
      this.scene.add(mesh)
      this.contacts.push({ x: sx, y: sy, r: Math.max(3, width * 0.4), strength: 0.3 })
      if (s.light)
        this.lightSources.push({
          kind: 'lamp',
          x: sx,
          y: sy,
          reach: s.light.reach,
          color: new THREE.Color(s.light.color).multiplyScalar(s.light.power ?? 1.5),
          on: s.light.on ?? 0.2,
        })
      const clear = Math.ceil(width / 2) + 3
      for (let dy = -Math.ceil(s.canvas.height * 0.6); dy <= 4; dy++)
        for (let dx = -clear; dx <= clear; dx++) {
          const i = pxIndex(sx + dx * PIXEL, sy + dy * PIXEL, pw)
          if (i >= 0 && i < open.length) open[i] = OPEN.none
        }
      // 身前（镜头那一侧）一片只长草不种树，树冠挡不住它；矮的小摆设空得少一些
      const front = Math.min(FRONT_CLEAR, Math.ceil(s.canvas.height * 1.2))
      for (let dy = 5; dy <= front; dy++)
        for (let dx = -clear; dx <= clear; dx++) {
          const i = pxIndex(sx + dx * PIXEL, sy + dy * PIXEL, pw)
          if (i >= 0 && i < open.length && open[i] !== OPEN.none) open[i] = OPEN.verge
        }
    }
  }

  /** 搭成立体的标志物（摊棚、船，见 landmarkModels.ts）：和房子重叠的不放；灯入夜亮、照亮四周。
   *  落在地上的脚下压一片影子，占地不种树不长草，身前一片只长草 */
  private addLandmarkModel(
    s: PlacedModel,
    buildings: { x: number; y: number; w: number; h: number }[],
    open: Uint8Array,
    pw: number
  ) {
    const kit = new Kit()
    s.model.build(kit)
    // 占地按朝向转到地图上：积木的 x 轴朝 (c, sn)，z 轴朝 (-sn, c)
    const { cx, cz, hw, hd } = kit.foot
    const a = s.model.angle ?? 0
    const c = Math.cos(a),
      sn = Math.sin(a)
    const at = (u: number, v: number): [number, number] => [
      s.x + u * c - v * sn,
      s.y + u * sn + v * c,
    ]
    const corners = [
      at(cx - hw, cz - hd),
      at(cx + hw, cz - hd),
      at(cx + hw, cz + hd),
      at(cx - hw, cz + hd),
    ]
    const x0 = Math.min(...corners.map(([x]) => x)),
      x1 = Math.max(...corners.map(([x]) => x)),
      y0 = Math.min(...corners.map(([, y]) => y)),
      y1 = Math.max(...corners.map(([, y]) => y))
    if (
      !s.model.float &&
      buildings.some((h) => x1 > h.x && x0 < h.x + h.w && y1 > h.y && y0 < h.y + h.h)
    )
      return
    for (const l of this.landmarkModelsOf().add(kit, s.model, s.x, s.y)) {
      const on = 0.1
      this.addGlow(this.glowMap, l.at.x, l.at.z, 0, l.size, on, l.at.y)
      this.lightSources.push({
        kind: 'lamp',
        x: l.at.x,
        y: l.at.z,
        reach: l.reach,
        color: new THREE.Color(l.color).multiplyScalar(1.25 * l.strength),
        on,
      })
    }
    if (s.model.float) return
    // 影子沿长边排几团
    const long = Math.max(hw, hd),
      short = Math.max(1, Math.min(hw, hd))
    const n = Math.max(1, Math.round(long / short))
    for (let i = 0; i < n; i++) {
      const t = n === 1 ? 0 : (i / (n - 1)) * 2 - 1
      const [x, y] = hw >= hd ? at(cx + t * (hw - hd), cz) : at(cx, cz + t * (hd - hw))
      this.contacts.push({ x, y, r: (short / PIXEL) * 1.1, strength: 0.3 })
    }
    const px0 = Math.floor(x0 / PIXEL) - 1,
      px1 = Math.ceil(x1 / PIXEL) + 1,
      py0 = Math.floor(y0 / PIXEL) - 1,
      py1 = Math.ceil(y1 / PIXEL) + 1
    for (let py = py0; py <= py1 + 10; py++)
      for (let px = Math.max(0, px0); px <= Math.min(pw - 1, px1); px++) {
        const i = py * pw + px
        if (i < 0 || i >= open.length) continue
        if (py <= py1) open[i] = OPEN.none
        else if (open[i] !== OPEN.none) open[i] = OPEN.verge
      }
  }

  /** 立体标志物的管理器：材质接上天气、光照图和玩法的着色 */
  private landmarkModelsOf() {
    if (this.landmarkModels) return this.landmarkModels
    const models = (this.landmarkModels = new LandmarkModels((material, on) =>
      this.glowing.push({ material, on })
    ))
    this.weather.shade(models.top, { snow: 1, wet: 0.5 })
    this.weather.shade(models.side, { snow: 0, wet: 0.5 })
    this.lightmap.shade(models.top, 'ground')
    this.lightmap.shade(models.side, 'wall')
    for (const look of this.looks) {
      look.shadeStanding(models.top, 'thing')
      look.shadeStanding(models.side, 'thing')
    }
    this.flat.add(models.group)
    return models
  }

  /** 散落物：野地上的轮胎、雪人，外圈（干海床、冰原）上的沉船、冰钓小屋。放在空地上，占的地方从空地里去掉 */
  private addScatter(
    terrain: {
      width: number
      height: number
      wet: Uint8Array
      depth: Uint8Array
      shore: Uint8Array
    },
    open: Uint8Array,
    seed: number
  ) {
    const scatter = this.theme.landmarks.scatter
    if (!scatter) return
    const { width: pw, height: ph, wet, depth, shore } = terrain
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
            : this.theme.outer !== 'sea' && shore[i] === 1 && depth[i] > 5 && depth[i] < 30
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
        this.lightmap.shade(mesh.material as THREE.Material, 'standee')
        this.standing(mesh)
        const sx = fromPx(x),
          sy = fromPx(y)
        this.upright.push((t) => stand(mesh, sx, sy, t))
        this.scene.add(mesh)
        if (where === 'outer') this.carrion.push([sx, sy])
        for (let dy = -Math.ceil(canvas.height * 0.6); dy <= 3; dy++)
          for (let dx = -half - 2; dx <= half + 2; dx++) {
            const j = (y + dy) * pw + x + dx
            if (j >= 0 && j < open.length) open[j] = OPEN.none
          }
      }
  }

  /** 光晕贴片；on 是它跟着亮起的那盏灯（那栋房子）的门槛 */
  private addGlow(
    map: THREE.Texture,
    x: number,
    y: number,
    texelsUp: number,
    size: number,
    on: number,
    lift = 0
  ) {
    const sprite = new THREE.Sprite(
      new THREE.SpriteMaterial({
        map,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        transparent: true,
        opacity: 0,
      })
    )
    // 沿立牌的方向抬高，屏幕上正好高出 texelsUp 个像素；lift 是立牌底下垫高的世界单位（栈桥上的灯）
    this.upright.push((t) => {
      onStandee(sprite, x, y, texelsUp, t, 40)
      sprite.position.y += lift
    })
    sprite.scale.set(size, size, 1)
    this.scene.add(sprite)
    this.glows.push({ sprite, on })
    return sprite
  }

  /** 地图规划的树，加上按演示页规则撒在空地上的树：公园最密，镇外草地按噪声成片；
   *  修剪过的草坪上不撒（树由地图规划种在北沿，见 decor.ts） */
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
      // 树冠顶上积雪，随风摆；树影跟着摆
      this.weather.shade(mesh.material as THREE.MeshLambertMaterial, {
        snow: 1,
        wet: 0.3,
        sway: true,
      })
      this.lightmap.shade(mesh.material as THREE.Material, 'standee')
      if (mesh.customDepthMaterial) this.weather.swayShadow(mesh.customDepthMaterial)
      this.standing(mesh)
      const sx = Math.round(x / PIXEL) * PIXEL,
        sy = Math.round(y / PIXEL) * PIXEL
      this.upright.push((t) => stand(mesh, sx, sy, t))
      this.scene.add(mesh)
    }
    for (const v of decor.vegetation) {
      if (v.kind === 'grass' || v.kind === 'flowers') continue
      const { r, variant, bush } = treeShape(v)
      add(v.x, v.y, r, variant, bush, 1)
      this.contacts.push({ x: v.x, y: v.y, r: r * 0.85, strength: bush ? 0.28 : 0.38 })
    }
    const { width: pw, height: ph, open } = terrain
    const mown = mownLawn(this.theme)
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
      [OPEN.lawn]: () => (mown ? 0 : 0.07),
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
        this.contacts.push({ x: fromPx(x), y: fromPx(y), r: r * 1.1, strength: bush ? 0.28 : 0.38 })
      }
  }

  /** 路过河的桥（见 bridge.ts）：桥身接上天气和灯光；人走上桥按桥面抬高 */
  private addBridges(ground: Ground, seed: number) {
    if (!ground.bridges.length) return
    this.bridges = ground.bridges
    this.villagers.lift = liftOf(ground.bridges)
    ground.bridges.forEach((b, k) => {
      const own = Math.floor(hash(Math.round(b.a[0]), Math.round(b.a[1]), seed + k) * 1e6)
      const built = bridge(b, this.theme.ground, own)
      this.weather.shade(built.top, { snow: 1, wet: 0.5 })
      this.weather.shade(built.sides, { snow: 0, wet: 0.5 })
      this.weather.shade(built.parts, { snow: 1, wet: 0.5 })
      this.lightmap.shade(built.top, 'ground')
      this.lightmap.shade(built.sides, 'wall')
      this.lightmap.shade(built.parts, 'wall')
      this.flat.add(built.group)
    })
  }

  /** 看台（见 stand.ts）：台阶接上天气和灯光；人和道具站上台阶、舞台按那里的高度抬起来，桥上照旧 */
  private addStands(atlas: Atlas, seed: number) {
    this.stands = standsOf(atlas)
    if (!this.stands.length && !this.pavilions.length && !this.fountains.length) return
    const worn = this.theme.ground.cracks !== undefined
    this.stands.forEach((s, k) => {
      const own = Math.floor(hash(Math.round(s.x), Math.round(s.y), seed + k) * 1e6)
      const built = buildStand(s, this.theme.ground, own, worn)
      this.weather.shade(built.top, { snow: 1, wet: 0.5 })
      this.weather.shade(built.sides, { snow: 0, wet: 0.5 })
      this.lightmap.shade(built.top, 'ground')
      this.lightmap.shade(built.sides, 'wall')
      this.flat.add(built.group)
    })
    const onBridges = liftOf(this.bridges),
      onStands = standLift(this.stands)
    const inPavilion = pavilionLift(this.pavilions),
      onFountains = fountainLift(this.fountains)
    const lift = (x: number, y: number) =>
      onBridges(x, y) || onStands(x, y) || inPavilion(x, y) || onFountains(x, y)
    // 躺在床上的人按床面垫高
    this.villagers.lift = (x, y) => lift(x, y) || (this.models?.liftAt(x, y) ?? 0)
    this.props.lift = lift
  }

  /** 港口的栈桥（见 pier.ts）：桥身接上天气和灯光；尽头平台立一盏灯，入夜和路灯一起亮 */
  private addPiers(ground: Ground, glowMap: THREE.Texture, seed: number) {
    const G = this.theme.ground
    // 废土沿用横担吊灯泡的破路灯，其余是木桩挑一盏马灯
    const scrap = this.theme.lamp === 'scrap'
    const post = texture(scrap ? lampCanvas(false, 'scrap') : pierLampCanvas(false)),
      glass = texture(scrap ? lampCanvas(true, 'scrap') : pierLampCanvas(true))
    const color = new THREE.Color(this.theme.light.lamp).multiplyScalar(1.5)
    ground.docks.forEach((dock, k) => {
      // 地形种子各张地图一样，按栈桥的位置再取一个
      const own = Math.floor(hash(Math.round(dock.x), Math.round(dock.y), seed + k) * 1e6)
      const built = pier(dock, G, G.pierGaps, own)
      this.weather.shade(built.top, { snow: 1, wet: 0.5 })
      this.weather.shade(built.sides, { snow: 0, wet: 0.5 })
      this.weather.shade(built.posts, { snow: 1, wet: 0.5 })
      this.lightmap.shade(built.top, 'ground')
      this.lightmap.shade(built.sides, 'wall')
      this.lightmap.shade(built.posts, 'wall')
      this.flat.add(built.group)
      const [x, y] = built.lamp
      const lamp = standee(post, { emissive: glass })
      this.lightmap.shade(lamp.material as THREE.Material, 'standee')
      this.upright.push((t) => {
        stand(lamp, x, y, t)
        lamp.position.y += PIER_DECK
      })
      this.scene.add(lamp)
      const on = 0.3 + hash(own, 3, 17) * 0.1
      this.glowing.push({ material: lamp.material as THREE.Material, on })
      this.addGlow(glowMap, x, y, scrap ? 24 : 13, 90, on, PIER_DECK)
      this.lightSources.push({ kind: 'lamp', x, y, reach: LAMP_REACH, color, on })
      // 桥上的杂物
      built.spots.forEach(([gx, gy], j) => {
        if (hash(own, j, 19) < 0.25) return
        const goods = standee(texture(this.theme.landmarks.dockGoods(own + j)))
        this.weather.shade(goods.material as THREE.MeshLambertMaterial, { snow: 1, wet: 0.4 })
        this.lightmap.shade(goods.material as THREE.Material, 'standee')
        const sx = Math.round(gx / PIXEL) * PIXEL,
          sy = Math.round(gy / PIXEL) * PIXEL
        this.upright.push((t) => {
          stand(goods, sx, sy, t)
          goods.position.y += PIER_DECK
        })
        this.scene.add(goods)
      })
    })
  }

  /** 沿室外路段每隔一段立一盏路灯，灯光画进光照图。入夜时从镇中心往外一盏盏亮起 */
  private addLamps(atlas: Atlas, wet: Uint8Array, pw: number, glowMap: THREE.Texture) {
    if (this.theme.lamp === 'none') return
    const rooms = [...this.houses, ...this.ruins]
    const inRoom = (x: number, y: number, pad: number) =>
      rooms.some(
        (r) => x > r.x - pad && x < r.x + r.w + pad && y > r.y - pad && y < r.y + r.h + pad
      )
    /** 第三项：这段路立的是矮石灯 */
    const spots: [number, number, boolean][] = []
    const gap = (this.theme.lampGap ?? 80) * PIXEL
    for (const e of atlas.edges) {
      if (e.lamp === 'none' || e.polyline.some(([x, y]) => inRoom(x, y, -12))) continue
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
            onBridge(this.bridges, px, py) ||
            standGap(this.stands, px, py) < 30 ||
            spots.some((p) => Math.hypot(p[0] - px, p[1] - py) < gap * 0.85)
          )
            continue
          spots.push([px, py, e.lamp === 'lantern'])
          run = 0
        }
      }
    }
    const cx = atlas.canvas.width / 2,
      cy = atlas.canvas.height / 2
    const far = Math.max(1, ...spots.map(([x, y]) => Math.hypot(x - cx, y - cy)))
    const post = texture(lampCanvas(false, this.theme.lamp)),
      glass = texture(lampCanvas(true, this.theme.lamp))
    const color = new THREE.Color(this.theme.light.lamp).multiplyScalar(1.5)
    // 地图说立矮石灯的路段（公园里的步道）：石灯矮、光圈小，都在天刚擦黑时亮
    const lanternArt = spots.some((s) => s[2]) ? stoneLantern(1) : undefined
    const lanternMap = lanternArt && texture(lanternArt.canvas),
      lanternGlow = lanternArt?.glow && texture(lanternArt.glow)
    const lanternColor = new THREE.Color('#ffb768').multiplyScalar(1.2)
    spots.forEach(([x, y, lantern]) => {
      if (lantern && lanternMap) {
        const mesh = standee(lanternMap, { emissive: lanternGlow })
        this.lightmap.shade(mesh.material as THREE.Material, 'standee')
        const sx = Math.round(x / PIXEL) * PIXEL,
          sy = Math.round(y / PIXEL) * PIXEL
        const on = 0.08 + hash(sx, sy, 17) * 0.1
        this.upright.push((t) => stand(mesh, sx, sy, t))
        this.scene.add(mesh)
        this.glowing.push({ material: mesh.material as THREE.Material, on })
        this.addGlow(glowMap, sx, sy, 8, 60, on)
        this.lightSources.push({ kind: 'lamp', x: sx, y: sy, reach: 150, color: lanternColor, on })
        this.contacts.push({ x: sx, y: sy, r: 3, strength: 0.3 })
        return
      }
      const mesh = standee(post, { emissive: glass })
      this.lightmap.shade(mesh.material as THREE.Material, 'standee')
      const sx = Math.round(x / PIXEL) * PIXEL,
        sy = Math.round(y / PIXEL) * PIXEL
      // 离镇中心越远亮得越晚，再按位置错开一点，不整圈同时亮
      const on = 0.04 + (Math.hypot(x - cx, y - cy) / far) * 0.6 + hash(sx, sy, 17) * 0.14
      this.upright.push((t) => stand(mesh, sx, sy, t))
      this.scene.add(mesh)
      this.glowing.push({ material: mesh.material as THREE.Material, on })
      this.addGlow(glowMap, sx, sy, 24, 120, on)
      this.lightSources.push({ kind: 'lamp', x: sx, y: sy, reach: LAMP_REACH, color, on })
      this.contacts.push({ x: sx, y: sy, r: 2.5, strength: 0.3 })
    })
  }

  /** 立在岛上的东西接上玩法的着色（潮水圈里按水深往下沉），投影跟着 */
  private standing(mesh: THREE.Mesh) {
    for (const look of this.looks) {
      look.shadeStanding(mesh.material as THREE.Material, 'thing')
      if (mesh.customDepthMaterial) look.shadeStanding(mesh.customDepthMaterial, 'thing')
    }
  }

  /** 名册里开着的玩法此刻的状态（没开时 null）；metre 是每米的地图单位。状态没变时不重画 */
  setGameMode(view: GameModeView | null, metre: number) {
    const key = view ? `${metre}|${JSON.stringify(view)}` : ''
    if (key === this.gameModeKey) return
    this.gameModeKey = key
    for (const look of this.looks) look.apply(view, metre)
    const badges = new Map<string, Badge>()
    for (const look of this.looks) look.badges?.().forEach((badge, id) => badges.set(id, badge))
    this.villagers.setBadges(badges)
    this.ambient = true
  }
  private gameModeKey = ''

  /** 世界时间与天气 */
  setClock(minutes: number, weather?: string) {
    // 名册每次都带时钟；世界暂停时时间和天气都没变，不必重算光照、重画
    const clock = `${minutes}|${weather}`
    if (clock === this.clock) return
    this.clock = clock
    this.minutes = minutes
    this.hour = (((minutes % 1440) + 1440) % 1440) / 60
    this.weather.setKind(weather as WeatherKind | undefined)
    this.weather.setClock(minutes)
    // 名册每拍都会改时钟：等节拍再画，不打乱走路的帧距
    this.applyLight(false)
  }

  /** 赏景（选镇页的预览，没有世界）：玩家拖到的时刻和点的天气。从此地面湿度、积雪不按游戏分钟累积，
   *  换了天气几秒内跟上（见 Weather3D.followScenery） */
  setScenery(minutes: number, weather: WeatherKind) {
    this.weather.followScenery()
    this.setClock(minutes, weather)
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
          (q) =>
            q.visible && (q.url || this.models?.has(q.id)) && Math.hypot(q.x - p.x, q.y - p.y) < 8
        )
        // 立体道具各有各的操作位（柜台跟前、椅子和桌子之间、床上），不随镜头转
        const use = at && this.models?.useOf(at.id)
        if (use) return { ...p, offset: [use.x - p.x, use.y - p.y] as [number, number] }
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
  /** 立牌此刻的速度（地图单位 / 毫秒），见 Villagers.velocity */
  villagerVelocity(id: string) {
    return this.villagers.velocity(id)
  }

  /** 选中的人（金边、脚下光斑）、指着的人（白边） */
  setPickedVillager(picked: string | null, hovered: string | null) {
    this.villagers.setPicked(picked, hovered)
    this.request()
  }

  /** 头顶撑着的伞、冒着的符号高出头顶多少（地图单位）：气泡躲开 */
  villagerCrown(id: string) {
    return this.villagers.crown(id)
  }

  /** 立体道具的管理器：材质接上光照图和玩法的着色，光晕、垫高交给场景 */
  private modelsOf() {
    if (this.models) return this.models
    const models = (this.models = new PropModels({
      glowing: (material, on) => {
        this.glowing.push({ material, on })
      },
      glow: (x, y, z, size, on) => {
        const sprite = new THREE.Sprite(
          new THREE.SpriteMaterial({
            map: this.glowMap,
            blending: THREE.AdditiveBlending,
            depthWrite: false,
            transparent: true,
            opacity: this.lightmap.level(on) * 0.3,
          })
        )
        sprite.scale.set(size, size, 1)
        onStandee(sprite, x, z, 0, this.tilt, 40)
        sprite.position.y += y
        this.scene.add(sprite)
        this.modelGlows.add({ sprite, on, at: [x, y, z] })
        return sprite
      },
      unglow: (sprite) => {
        for (const g of this.modelGlows) if (g.sprite === sprite) this.modelGlows.delete(g)
        sprite.removeFromParent()
        sprite.material.dispose()
      },
      lift: (x, y) => this.props.lift(x, y),
      changed: () => {
        this.lightmap.setSources([...this.lightSources, ...models.lights()])
        this.applyLight(false)
      },
    }))
    this.weather.shade(models.topOut, { snow: 1, wet: 0.5 })
    this.weather.shade(models.sideOut, { snow: 0, wet: 0.5 })
    for (const [top, side] of [
      [models.top, models.side],
      [models.topOut, models.sideOut],
    ]) {
      this.lightmap.shade(top, 'ground')
      this.lightmap.shade(side, 'wall')
      for (const look of this.looks) {
        look.shadeStanding(top, 'thing')
        look.shadeStanding(side, 'thing')
      }
    }
    this.flat.add(models.group)
    models.setTilt(this.tilt)
    this.upright.push((t) => {
      models.setTilt(t)
      for (const g of this.modelGlows) {
        onStandee(g.sprite, g.at[0], g.at[2], 0, t, 40)
        g.sprite.position.y += g.at[1]
      }
    })
    return models
  }

  /** 屋子外墙内侧的范围和隔墙，家具按它布置（propArrange.ts）；外墙厚两个像素 */
  private roomOf(house: House): Room {
    const wall = 2 * PIXEL
    const cx = house.x + house.w / 2,
      cy = house.y + house.h / 2
    const p = this.partitions.get(house.id)
    return {
      x0: house.x + wall,
      y0: house.y + wall,
      x1: house.x + house.w - wall,
      y1: house.y + house.h - wall,
      walls: (p?.segments ?? []).map(([from, to]) =>
        p!.alongX
          ? { horizontal: true, at: cy + p!.at, from: cx + from, to: cx + to }
          : { horizontal: false, at: cx + p!.at, from: cy + from, to: cy + to }
      ),
    }
  }

  /** 喷泉边上的座位：不搭长椅，人坐到朝着它的那段池沿上，和长椅一样高。
   *  一个座位的搭法只建一次：搭法换了道具就会重搭 */
  private rimSeat(x: number, y: number): Build | undefined {
    const key = `${x},${y}`
    if (!this.rimSeats.has(key)) {
      const spot = rimSpot(this.fountains, x, y)
      this.rimSeats.set(
        key,
        spot &&
          ((k) => {
            k.use = { at: [spot[0] - x, spot[1] - y], lift: FOUNTAIN.rim }
          })
      )
    }
    return this.rimSeats.get(key)
  }

  /** 道具：登记了搭法的搭成立体的，按屋子布置（贴墙、拼排）；其余的照旧立牌。屋里的跟着屋子掀开才显示。
   *  返回每件实际画的位置：x 是中心，base 是底边（立体的是正面的边）的 y，size 是立起来多高；
   *  SVG 层的点击区和名字据此跟着走。model 是立体的，width 是它点击区的宽 */
  setProps(placements: PropPlacement[]) {
    this.propPlacements = placements
    const models = this.modelsOf()
    // 按屋子分组：灯塔里是剖开的塔，不摆立体家具
    const groups = new Map<House | undefined, { p: PropPlacement; build: Build }[]>()
    for (const p of placements) {
      const house = this.houses.find(
        (h) => p.x >= h.x && p.x <= h.x + h.w && p.y >= h.y && p.y <= h.y + h.h
      )
      const seat = !house && p.definition?.split('@')[0] === 'core:seat'
      const build =
        (seat && this.rimSeat(p.x, p.y)) ||
        (house?.tower ? undefined : buildOf(p.definition, !!house))
      if (!build) continue
      let group = groups.get(house)
      if (!group) groups.set(house, (group = []))
      group.push({ p, build })
    }
    const list: ModelPlacement[] = []
    const drawnModels = new Map<
      string,
      { x: number; y: number; base: number; size: number; width: number }
    >()
    for (const [house, group] of groups) {
      const room = house && this.roomOf(house)
      const pieces = group.map(({ p, build }) => {
        const { foot, wall } = models.measure(build, p.amount)
        return { id: p.id, x: p.x, y: p.y, foot, wall }
      })
      const spots = arrange(room, pieces)
      for (const { p, build } of group) {
        const spot = spots.get(p.id)!
        list.push({
          id: p.id,
          build,
          x: spot.x,
          y: spot.y,
          turn: spot.turn,
          visible: p.visible,
          house: house?.id,
          amount: p.amount,
        })
        drawnModels.set(p.id, {
          x: (spot.box.x0 + spot.box.x1) / 2,
          y: (spot.box.y0 + spot.box.y1) / 2,
          base: spot.box.y1,
          size: Math.max(40, models.measure(build, p.amount).tall),
          width: Math.max(40, spot.box.x1 - spot.box.x0),
        })
      }
      if (!house || !room || !this.furnished) continue
      // 陈设：让开摆好的道具和人走的地方；道具没动就用上次算的
      const boxes = group.map(({ p }) => spots.get(p.id)!.box)
      const key = boxes.map((b) => `${b.x0},${b.y0},${b.x1},${b.y1}`).join(';')
      let decor = this.decor.get(house.id)
      if (decor?.key !== key) {
        const lounge = group
          .filter(({ build }) => models.measure(build).lounge)
          .map(({ p }) => spots.get(p.id)!.box)
        decor = {
          key,
          list: furnish(room, house.kind, boxes, this.roomStops.get(house.id) ?? [], lounge),
        }
        this.decor.set(house.id, decor)
      }
      decor.list.forEach((d, i) =>
        list.push({
          id: `decor:${house.id}:${i}`,
          build: decorBuild(d.kind),
          x: d.x,
          y: d.y,
          turn: 0,
          visible: this.openRooms.has(house.id),
          house: house.id,
        })
      )
    }
    models.sync(list)
    const standees = placements
      .filter((p) => p.url && !drawnModels.has(p.id))
      .map((p) => {
        const [x, y] = this.inside(p.x, p.y, p.size / 2)
        return { ...p, x, y }
      })
    this.props.sync(standees)
    this.request()
    return [
      ...standees.map((p) => ({
        id: p.id,
        x: p.x,
        y: p.y,
        base: p.y + p.size * PROP_BASE,
        size: p.size,
        model: false,
        width: p.size,
      })),
      ...[...drawnModels].map(([id, d]) => ({ id, ...d, model: true })),
    ]
  }

  /** 选中的道具、指着的道具：立体的在身上叠一层亮色（立牌的选中框在 SVG 层） */
  setPickedProp(picked: string | null, hovered: string | null) {
    this.models?.setPicked(picked, hovered)
    this.request()
  }

  /** 这些房间去掉整栋房子，立起室内的墙，露出地面上画的地板；其余的盖回去。
   *  开合时外壳按像素格溶解（DISSOLVE_MS，要求减少动画时直接换），中途反悔从当时的样子往回走 */
  setOpenRooms(open: ReadonlySet<string>) {
    this.openRooms = open
    const now = performance.now()
    for (const [id, r] of this.reveals) {
      if (open.has(id) === r.open) continue
      r.open = open.has(id)
      r.from = r.amount.value
      r.at = now
      r.moving = this.roomsMoving = true
    }
    this.request()
  }

  /** 开合中的房子走到这一帧：室内的墙从开始掀到屋顶盖严一直立着，外壳全去掉了才藏起来，
   *  屋里的灯和窗光在溶解过半时换。走完盖回的告诉地图（刚要掀又盖回、还没动过的也算） */
  private stepRooms(t: number) {
    const span = this.reduceMotion.matches ? 0 : DISSOLVE_MS
    const closed: string[] = []
    let moving = false
    for (const [id, r] of this.reveals) {
      if (!r.moving) continue
      const step = span ? Math.max(0, t - r.at) / span : 1
      const v = r.open ? Math.min(1, r.from + step) : Math.max(0, r.from - step)
      r.amount.value = v
      this.houseGroups.get(id)!.visible = v < 1
      this.rooms.get(id)!.visible = v > 0 || r.open
      if (v === (r.open ? 1 : 0)) {
        r.moving = false
        if (!r.open) closed.push(id)
      } else moving = true
    }
    this.roomsMoving = moving
    const lit = [...this.reveals].filter(([, r]) => r.amount.value >= 0.5).map(([id]) => id)
    const key = lit.join('|')
    if (key !== this.litRooms) {
      this.litRooms = key
      this.lightmap.setOpenRooms(new Set(lit))
    }
    if (closed.length) this.onRoomsClosed?.(closed)
  }

  /** 按太阳高度分四段：白天、金色时刻、蓝调时刻（日落后天没黑透、环境光发蓝、灯已亮）、夜，
   *  颜色在风格包的四组之间插值；cloud 压低日照和饱和度。now 为 false 时等下一个节拍再画（名册、天气这类环境变化） */
  private applyLight(now = true) {
    const { e, day, night, twilight, golden: clearGolden } = daylight(this.hour)
    const elev = (e * Math.PI) / 3,
      az = ((this.hour - 12) / 12) * Math.PI
    const { cloud, overcast, flash } = this.weather
    this.day = day
    const golden = clearGolden * (1 - cloud)
    // 亮灯：日落前一刻钟开始，到蓝调过半全亮；天亮前按同样的顺序熄
    this.lit = 1 - smooth(-0.16, 0.06, e)
    this.lightmap.setLit(this.lit)
    // 太阳在南边（镜头这一侧）偏高处：朝镜头的南墙受光，影子往北落在房子后面；
    // 中午最偏南，早晚偏东西、斜照南墙；傍晚太阳压得低，影子拉得长
    const dir =
      e > -0.06
        ? new THREE.Vector3(
            -Math.sin(az) * Math.cos(elev),
            Math.max(Math.sin(elev), 0.2),
            0.3 + 0.2 * Math.cos(az)
          )
        : new THREE.Vector3(-0.35, 0.8, 0.55)
    this.sun.position.copy(this.sun.target.position).addScaledVector(dir.normalize(), 12000)
    const L = this.theme.light
    const color = (hex: string) => new THREE.Color(hex)
    /** 一组颜色按此刻的时段混出来：夜 → 白天，再往蓝调、金色时刻靠 */
    const phase = (
      p: { day: string; night: string; blue: string; golden?: string },
      warm = 0.55
    ) => {
      const c = color(p.night).lerp(color(p.day), day).lerp(color(p.blue), twilight)
      return p.golden ? c.lerp(color(p.golden), golden * warm) : c
    }
    const sunColor = color(L.sun.low).lerp(color(L.sun.day), smooth(0.05, 0.6, e))
    // 闪电那一下是冷白色的强光
    this.sun.color
      .copy(new THREE.Color('#8fa6d9').lerp(sunColor, day))
      .lerp(new THREE.Color('#dce6ff'), flash)
    // 夜里的月光和天光比演示页亮一些，游戏里要能看清人和房子；蓝调时环境光为主、月光弱
    this.sun.intensity =
      (lerp(0.9, 2.7, day) + golden * 1.1 - twilight * 0.3) * (1 - cloud * 0.7) + flash * 6
    // 阴天光线是漫射的：影子变淡；蓝调时天光从四面来，影子也淡
    this.sun.shadow.intensity = (1 - 0.7 * overcast) * (1 - 0.55 * twilight)
    this.hemi.color.copy(phase(L.hemiSky))
    this.hemi.groundColor.copy(phase(L.hemiGround))
    this.hemi.intensity =
      lerp(1.35, 1.05, day) + golden * 0.35 + cloud * 0.3 * day + twilight * 0.4 + flash * 2.5
    const sky = phase(L.sky)
    this.fog.color.copy(sky)
    this.renderer.setClearColor(sky)
    // 远景：高处的天色比海雾深、偏蓝，傍晚带一点暖色，阴天往海雾色靠；远山是压暗的海雾色
    const top = phase(L.top, 0.45).lerp(sky, overcast * 0.7)
    const hill = sky
      .clone()
      .multiplyScalar(0.72)
      .lerp(color(L.hill), 0.35 * day)
    this.horizon.setColors(sky, top, hill)
    this.reflection.uniforms.uReflSky.value.copy(top)
    // 窗、灯罩和光晕按各自的门槛错开亮；屋顶夜里按自身颜色微亮，看清房子靠天光和对比度
    for (const g of this.glowing)
      (g.material as THREE.MeshLambertMaterial).emissiveIntensity = this.lightmap.level(g.on) * 0.9
    for (const g of this.glows) g.sprite.material.opacity = this.lightmap.level(g.on) * 0.3
    for (const g of this.modelGlows) g.sprite.material.opacity = this.lightmap.level(g.on) * 0.3
    for (const m of this.moonlit) m.emissiveIntensity = night * ROOF_NIGHT_GLOW
    for (const m of this.selfLit) m.emissiveIntensity = lerp(0.3, 0.55, Math.max(night, twilight))
    this.seaSparkle.value = lerp(0.3, 1, day) * (1 - cloud * 0.9)
    // 温泉白天只是微微透亮，天越黑越显出青光；白汽被池水从底下映成青色
    this.springGlow.value = lerp(0.12, 1, Math.max(night, twilight * 0.8))
    this.steam?.glow.value
      .set('#2a9aa6')
      .convertSRGBToLinear()
      .multiplyScalar(0.35 * Math.max(night, twilight * 0.6))
    for (const b of this.beams) (b.material as THREE.MeshBasicMaterial).opacity = this.lit * 0.45
    this.flare()
    this.horizon.setAurora(night * L.aurora)
    const dusk = Math.max(night, twilight * 0.8)
    this.bloom.strength = lerp(0.35, 0.5, dusk)
    this.bloom.threshold = lerp(0.9, 0.82, dusk)
    // 地上积雪时阴影压蓝、对比稍强，雪地不再一片灰白
    const snow = this.weather.snowLevel * day
    this.grade.uniforms.contrast.value = lerp(1, 1.15, night) + twilight * 0.05 + snow * 0.08
    const mixRgb = (p: Record<'day' | 'golden' | 'blue' | 'night', [number, number, number]>) =>
      new THREE.Color(...p.day)
        .lerp(new THREE.Color(...p.golden), golden)
        .lerp(new THREE.Color(...p.blue), twilight)
        .lerp(new THREE.Color(...p.night), night)
    ;(this.grade.uniforms.tint.value as THREE.Color)
      .copy(mixRgb(L.tint))
      .lerp(new THREE.Color(0.94, 0.98, 1.06), overcast * 0.6 * day)
    // 暗部偏色只改色相不改亮度：按亮度归一，清晨、傍晚不因为偏色而变暗
    const shade = (this.grade.uniforms.shade.value as THREE.Color)
      .copy(mixRgb(L.shade))
      .lerp(new THREE.Color(0.82, 0.9, 1.16), snow * 0.7)
    shade.multiplyScalar(1 / (0.2126 * shade.r + 0.7152 * shade.g + 0.0722 * shade.b))
    ;(this.grade.uniforms.lift.value as THREE.Color).setRGB(
      0.004 * night + 0.004 * twilight,
      0.008 * night + 0.006 * twilight,
      0.02 * night + 0.016 * twilight
    )
    this.grade.uniforms.sat.value = L.saturation - cloud * 0.25 - twilight * 0.05 + snow * 0.06
    this.renderer.toneMappingExposure = lerp(1.3, 1.12, day) + twilight * 0.12
    // 立牌轮廓光：太阳在画面上的方向（镜头的右、上分量），侧光、逆光时亮，傍晚最明显
    const { sin: ps, cos: pc, yawSin: ys, yawCos: yc } = this.tilt
    const sx = dir.dot(new THREE.Vector3(yc, 0, -ys)),
      sy = dir.dot(new THREE.Vector3(-ys * ps, pc, -yc * ps)),
      sz = dir.dot(new THREE.Vector3(ys * pc, ps, yc * pc))
    const rim =
      (golden * 0.9 * Math.min(1, Math.abs(sx) * 1.2) + Math.max(0, -sz) * 0.6 * day) *
      (1 - cloud * 0.8)
    // 村民的像素法线按太阳在画面上的方向分明暗；夜里给人一个最暗下限，偏一点蓝
    villagerLight.uSunScreen.value.set(sx, sy, sz)
    villagerLight.uSunUp.value = day
    villagerLight.uFloorTint.value.setRGB(0.012, 0.018, 0.04).multiplyScalar(night)
    this.lightmap.setRim(
      new THREE.Vector2(sx, sy).normalize(),
      this.sun.color.clone().multiplyScalar(this.sun.intensity * rim * 0.6),
      new THREE.Vector2(yc, -ys)
    )
    // 倒影越接近街景越亮，俯视时淡
    this.reflection.strength = lerp(0.3, 0.12, smooth(40, PITCH_MAX, this.pitchDegrees))
    this.applySky(e, day, night, twilight, golden, dir)
    this.motes.setLight(day, golden, cloud)
    // 花瓣：白天按天光和日光，入夜被树上的灯笼映成暖色
    this.petals?.setLight(
      this.hemi.color
        .clone()
        .multiplyScalar(this.hemi.intensity * 0.42)
        .add(this.sun.color.clone().multiplyScalar(this.sun.intensity * 0.2 * day))
        .add(new THREE.Color(1, 0.62, 0.4).multiplyScalar(0.5 * this.lit))
    )
    // 喷泉的水花：白天按天光和日光，入夜被池灯映成青白
    if (this.sprays.length) {
      const light = this.hemi.color
        .clone()
        .multiplyScalar(this.hemi.intensity * 0.45)
        .add(this.sun.color.clone().multiplyScalar(this.sun.intensity * 0.24 * day))
      const glow = new THREE.Color(0.22, 0.48, 0.62).multiplyScalar(this.lit * 0.8)
      for (const s of this.sprays) s.setLight(light, glow)
    }
    if (now) this.request()
    else this.ambient = true
  }

  /** 视野里有没有水：视野四角在地面上的外接框碰到有水的格子，或者伸出了地面画布（外面都是海） */
  private waterInView(target: THREE.Vector3, w: number, h: number) {
    const grid = this.waterGrid
    // 开着玩法时（潮水圈）圈外到处都可能是水
    if (!grid || this.looks.some((look) => look.waterAnywhere)) return true
    const { yawSin, yawCos } = this.tilt
    const ex = (Math.abs(yawCos) * w + Math.abs(yawSin) * h) / 2,
      ez = (Math.abs(yawSin) * w + Math.abs(yawCos) * h) / 2
    const cell = WATER_CELL * PIXEL
    const x0 = Math.floor((target.x - ex + MARGIN) / cell),
      x1 = Math.floor((target.x + ex + MARGIN) / cell)
    const z0 = Math.floor((target.z - ez + MARGIN) / cell),
      z1 = Math.floor((target.z + ez + MARGIN) / cell)
    if (x0 < 0 || z0 < 0 || x1 >= grid.gw || z1 >= grid.gh) return this.theme.outer !== 'seabed'
    for (let z = z0; z <= z1; z++)
      for (let x = x0; x <= x1; x++) if (grid.cells[z * grid.gw + x]) return true
    return false
  }

  /** 新踩下的脚印；落在水里的是涟漪 */
  private footprints() {
    const { wet, width, height } = this.groundWet
    // 桥上走过不在地面和桥下的水里留印子
    const prints = this.villagers.takeFootprints().filter(([x, y]) => !onBridge(this.bridges, x, y))
    return prints.map(([x, y]) => {
      const px = toPx(x),
        py = toPx(y)
      const water = px >= 0 && py >= 0 && px < width && py < height && wet[py * width + px] === 1
      return { x, y, water }
    })
  }

  /** GPU 计时：开发版地址带 ?hd-perf 时按 pass 量、右上角显示；不然只在「自动」画质的测量期整帧量一次 */
  private timePasses(perPass: boolean) {
    const gpu = this.gpu
    if (!gpu.available) return
    if (perPass) {
      gpu.on = true
      this.overlay = new PerfOverlay(this.container, gpu)
      const names = new Map<object, string>([
        [this.volumetric, '体积光'],
        [this.bokeh, '散景'],
        [this.bloom, '泛光'],
        [this.grade, '调色'],
        [this.finish, 'LUT 颗粒'],
      ])
      for (const p of this.tiltShift) names.set(p, '移轴')
      for (const pass of this.composer.passes) {
        if (pass === this.sceneDepth) continue
        const label = names.get(pass) ?? '色调映射'
        const render = pass.render.bind(pass) as (...args: unknown[]) => void
        pass.render = ((...args: unknown[]) =>
          gpu.time(label, () => render(...args))) as typeof pass.render
      }
      // 场景：倒影和踩踏图先各量各的，再量场景本身（计时查询不能嵌套）
      const scene = this.sceneDepth
      const render = scene.render.bind(scene) as (...args: unknown[]) => void
      scene.render = ((...args: unknown[]) => {
        const prepare = scene.prepare
        prepare?.(args[0] as THREE.WebGLRenderer)
        scene.prepare = undefined
        try {
          gpu.time('场景', () => render(...args))
        } finally {
          scene.prepare = prepare
        }
      }) as typeof scene.render
    }
    const render = this.composer.render.bind(this.composer)
    this.composer.render = (deltaTime?: number) => {
      const measuring = !perPass && this.measuring()
      if (!perPass) gpu.on = measuring
      if (measuring) gpu.begin('整帧')
      render(deltaTime)
      if (measuring) gpu.end()
      gpu.endFrame()
      this.overlay?.update(performance.now())
      this.checkBudget()
    }
  }

  /** 画质选「自动」时，开头半分钟量帧耗时（最多降两档） */
  private measuring() {
    return (
      storedQuality() === 'auto' && this.drops < 2 && performance.now() - this.measureFrom < 30000
    )
  }

  /** 「自动」画质跑不动：最近 45 帧的平均 GPU 耗时超过本档预算两成就降一档，在事件栏说一声 */
  private checkBudget() {
    if (!this.measuring()) return
    const avg = this.gpu.average(45)
    if (avg === undefined) return
    // 高档以上按 60 帧算，中档按节拍的 30 帧算
    const budget = { ultra: 16.7, high: 16.7, mid: 33, low: Infinity }[this.quality]
    if (avg <= budget * 1.2) return
    const next: Quality | null =
      this.quality === 'ultra'
        ? 'high'
        : this.quality === 'high'
          ? 'mid'
          : this.quality === 'mid'
            ? 'low'
            : null
    if (!next) return
    this.drops++
    this.gpu.frames.length = 0
    this.measureFrom = performance.now()
    this.setQuality(next)
    this.onNotice?.(
      `画面有点吃力（每帧约 ${avg.toFixed(0)} 毫秒），这次先把画质降到「${qualityLabels[next]}」；设定 · 显示里可以改`
    )
  }

  /** 天上和空气里的东西跟着时段走：日月星辰、彩虹、闪电、海面的日光路径，体积光的雾和光柱 */
  private applySky(
    e: number,
    day: number,
    night: number,
    twilight: number,
    golden: number,
    sunDir: THREE.Vector3
  ) {
    const { cloud, overcast } = this.weather
    const rain = this.weather.rainLevel,
      wet = this.weather.wetLevel
    const clear = 1 - cloud
    // 太阳在视野里偏左还是偏右：太阳方向在镜头右手方向上的分量
    const right = new THREE.Vector2(this.tilt.yawCos, -this.tilt.yawSin)
    const flat = new THREE.Vector2(sunDir.x, sunDir.z)
    const side = flat.lengthSq() > 1e-6 ? flat.normalize().dot(right) : 0
    const sun = smooth(-0.06, 0.01, e) * (1 - smooth(0.22, 0.4, e)) * clear
    const sunColor = this.sun.color.clone().lerp(new THREE.Color('#ffd9a0'), 0.4)
    this.horizon.setSky({
      side,
      elevation: e,
      sun,
      sunColor,
      moon: night * clear,
      stars: night * clear * (1 - rain),
      // 雨停了地还湿、天放晴：天边挂一道彩虹，地干了就淡出
      rainbow:
        Math.min(1, Math.max(0, (wet - 0.25) * 2.5)) *
        day *
        (1 - Math.min(1, rain * 4)) *
        (1 - overcast * 0.7),
      bolt: this.weather.flash,
      boltSeed: this.weather.flashSeed,
    })
    const path = this.seaPath
    path.uSunPath.value = sun * (0.4 + 0.6 * golden)
    path.uPathTo.value.set(...this.horizon.sunOnHorizon())
    path.uSunGlint.value.copy(sunColor).lerp(new THREE.Color('#ffe3a0'), 0.55).multiplyScalar(1.3)
    // 体积光：清晨和雨后有贴地的晨雾，傍晚空气里有暖色的光柱，夜里灯在雾里有光晕
    const hour = this.hour
    const dawn = smooth(4.3, 5.6, hour) * (1 - smooth(7.6, 9.2, hour))
    const v = this.volumetric.uniforms
    v.density.value =
      (0.00022 +
        golden * 0.0005 +
        twilight * 0.0004 +
        night * 0.00035 +
        wet * 0.0006 +
        rain * 0.0008) *
      this.theme.light.fog
    v.mist.value = (dawn * 0.004 + wet * 0.0015) * (1 - rain * 0.5)
    v.sunColor.value
      .copy(this.sun.color)
      .multiplyScalar(this.sun.intensity * (0.25 + 0.75 * day) * (0.5 + golden))
    v.skyColor.value.copy(this.hemi.color).multiplyScalar(this.hemi.intensity)
    v.lampScatter.value = 0.025 + wet * 0.04 + rain * 0.03
    this.volumetric.setSun(this.sun)
    // 小动物和草：白天、黄昏、夜里各有各的；积雪厚了草被埋住
    this.fauna.setLight({ day, twilight, night, rain, wind: this.weather.windUniforms.uWind.value })
    // 晴夜有星星、下雪时有雪花：站着的人偶尔抬头看
    this.villagers.setSky(night * clear * (1 - rain) > 0.5 || this.weather.snowFalling)
    // 天气落在人身上：伞、淋湿、积雪、围巾、呵白气、灯笼、废土正午冒汗、天好时散步哼歌
    const icy = this.theme.outer === 'ice'
    const snowy = this.weather.snowFalling || this.weather.snowLevel > 0.3
    this.villagers.setClimate({
      rain,
      snowing: this.weather.snowFalling,
      lit: this.lit,
      cold: icy || snowy || (hour >= 4.5 && hour < 8.5 && (wet > 0.3 || overcast > 0.5)),
      scarves: icy || snowy,
      hot: this.theme.outer === 'seabed' && hour >= 11 && hour < 15 && clear > 0.6,
      fine: day > 0.6 && cloud < 0.3 && rain < 0.05,
      minutes: this.minutes,
    })
    this.fauna.setEnabled(!this.reduceMotion.matches && this.quality !== 'low')
    this.grass.uniforms.uSnow.value = this.weather.snowLevel
    // 有体积光时灯在雾里的光晕由它画，加色贴片淡一些
    const sprites = this.volumetric.enabled ? 0.55 : 1
    for (const g of this.glows) g.sprite.material.opacity *= sprites
  }

  /** SVG 的视口变了才重设立体镜头：镜头跟随在画之前已经设过的，观察回调来时不再设、不再多画一帧 */
  private syncView() {
    if ((this.svg.getAttribute('viewBox') ?? '') !== this.viewBox) this.readView()
  }

  private readView() {
    this.viewBox = this.svg.getAttribute('viewBox') ?? ''
    const vb = this.viewBox.split(/[ ,]+/).map(Number)
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
    this.dissolveCell.value = Math.max(1, unitPx * PIXEL)
    this.motes.setScale(unitPx)
    this.petals?.setScale(unitPx)
    for (const s of this.sprays) s.setScale(unitPx)
    this.weather.setView(target.x, target.z, w, h, screenH, unitPx, sin, cos, yawSin, yawCos)
    this.horizon.setView(target.x, target.z, w)
    // 日光路径从画面下沿（朝镜头那一侧的地面）出发
    this.seaPath.uPathFrom.value.set(target.x + (yawSin * h) / 2, target.z + (yawCos * h) / 2)
    this.seaPath.uPathFade.value = h
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
    this.volumetric.setView(cam)
    this.viewTarget.copy(target)
    this.grass.setScale(unitPx)
    this.fauna.setScale(unitPx)
    this.villagers.setTexelPx(unitPx * PIXEL * VILLAGER_SCALE)
    // 看得见的地面范围（转过方位角时取外接框），外面留一圈：镜头外的人不重画贴图。
    // 村民位置是地图坐标，中心要用转回地图的 target；vx、vy 是转过方位角的视口坐标，转过角度后差得很远
    const reach = (Math.abs(yawCos) + Math.abs(yawSin)) * Math.max(w, h) * 0.5 + VILLAGER_HEIGHT * 2
    this.villagers.setView(target.x - reach, target.z - reach, target.x + reach, target.z + reach)
    this.reflection.uniforms.uReflStreak.value.set(-yawSin, -yawCos).multiplyScalar(6 * PIXEL)
    this.waterVisible = this.waterInView(target, w, h)
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
    // 改尺寸（右栏开合、窗口缩放、换画质）会清空画布：当场补画，不等下一帧。
    // 尺寸监听在浏览器绘制前回调，等下一帧再画，中间这一帧画布就是空的：
    // Safari 和 mac 版露出底下的浅色页面，像白屏闪一下，Chrome 是黑一下
    if (this.drawn) this.draw(performance.now())
  }

  /** 操作带来的变化（拖地图、换角度、开合屋顶）下一帧就画，不等节拍 */
  private request() {
    this.dirty = true
  }

  dispose() {
    cancelAnimationFrame(this.ticker)
    this.abort.abort()
    this.weather.dispose()
    this.props.dispose()
    this.models?.dispose()
    this.pitchControl?.remove()
    this.modeLayer.remove()
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
    this.lightmap.dispose()
    this.reflection.dispose()
    this.grass.dispose()
    this.trail.dispose()
    this.fauna.dispose()
    this.gpu.dispose()
    this.overlay?.dispose()
    ;(this.finish.uniforms.tLook.value as THREE.Texture | null)?.dispose()
    // composer.dispose 只释放它自己的两张渲染目标，泛光等各个 pass 的渲染目标和材质要逐个释放
    for (const pass of this.composer.passes) pass.dispose()
    this.composer.dispose()
    this.renderer.dispose()
    // 立即交还 WebGL 上下文，不等垃圾回收；否则选图页多点几张图就会超过浏览器的上下文上限
    this.renderer.forceContextLoss()
    this.renderer.domElement.remove()
  }
}
