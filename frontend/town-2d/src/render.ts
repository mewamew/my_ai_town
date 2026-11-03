import { WeatherLayer } from './weather'
import type { ServerMsg } from 'town-shared/protocol'
import { heightAt, position as spatialPosition, type Spatial } from 'town-shared/spatial'
import { savedAppearance, defaultAppearance } from 'town-shared/props/appearances'
import type { Appearance, PropView } from 'town-shared/props/types'
import type { Atlas, Topology } from 'town-shared/mapDocument'
import type {
  AvatarPrompt,
  PlaceSpot,
  ResidentEntry,
  ScreenBox,
  WalkStep,
  WalkTarget,
} from 'town-shared/gameMap'
import type { AvatarState } from 'town-shared/avatar/types'
import { buildStaticMap, type PlacedProp } from './map/staticLayers'
import { groundOf, paintGround, type Ground } from './map/pixel/terrain'
import type { DecorPlan } from './map/decor'
import type { HdScene } from './map/hd2d/scene'
import type { LiveMotion, VillagerPlacement } from './map/hd2d/villagers'
import { cueOf } from './map/hd2d/villagerCues'
import { AvatarMotion } from './map/avatarMotion'
import { PropPositions } from './map/propPositions'
import { RoomCovers } from './map/rooms'
import { MapCamera, type CameraArea } from './map/camera'
import { DEFAULT_PITCH, PITCH_MAX } from './map/hd2d/layout'
import { standUpright, uprightRatio } from './map/upright'
import { ThoughtBubbles } from './map/bubbles'
import { ResidentLayer } from './map/residents'
import { PromptLayer } from './map/prompts'
import { propArtwork } from './map/propArt'

/** 开发版：地址里的 ?clock=18:30&weather=rain 只替换立体场景用的时间和天气，世界本身不变。
 *  画面改动前后按同一时刻、同一天气截图对比用；正式包里没有这段 */
const DEV_CLOCK = import.meta.env.DEV ? devClock(new URLSearchParams(location.search)) : null
function devClock(query: URLSearchParams) {
  const clock = /^(\d{1,2}):(\d{2})$/.exec(query.get('clock') ?? '')
  const minutes = clock ? Number(clock[1]) * 60 + Number(clock[2]) : undefined
  const weather = query.get('weather') ?? undefined
  return minutes === undefined && !weather ? null : { minutes, weather }
}
import type { PropPlacement } from './map/hd2d/props'
import { avatarLookOptions, VILLAGER_HALF, VILLAGER_HEIGHT } from './map/hd2d/villagerSprite'
import { PROP_HALF, WalkRoutes } from './map/route'
import { LEGACY_UNITS_PER_METRE, OUTDOOR_SPACE, roomRect } from './map/grid'
import { village, type MapTheme } from './map/themes'
import { el } from 'town-shared/svg'
import type { Quality } from 'town-shared/quality'
// 地图装配：静态图层、人物/气泡、镜头各自拥有状态；公共观察接口保持不变。

export interface TownMapOptions {
  atlas: Atlas
  topology: Topology
  container: HTMLElement
  appearanceFor?: (id: string, definition: string) => Appearance
  /** 有它才把运行期道具坐标交给小镇服务保存 */
  persistence?: { townId: string; mapHash: string }
  /** 有三维数据时人物位置按米换算，SVG 单位每米取自数据本身 */
  spatial?: Spatial
  /** 非致命问题（坐标保存失败）通知调用方显示 */
  notify?: (message: string) => void
  /** 地图风格，缺省是原作山水小镇 */
  theme?: MapTheme
  /** 调用方已经算好的地面（建镇预览先拿它画缩略图）；不给就在这里算 */
  ground?: Ground
}

export class TownMap {
  readonly weatherSupported = true
  /** 平面图的天气层：只在立体场景起不来、退回平面像素地面时才有 */
  private weather?: WeatherLayer
  /** 最近一份名册，退回平面图时交给天气层 */
  private lastRoster?: Extract<ServerMsg, { type: 'roster' }>
  readonly avatarSupported = true
  readonly avatarLooks = avatarLookOptions
  walkDirection(direction: [number, number]): [number, number] {
    return this.camera.unproject(direction)
  }
  private avatarActive = false
  private zoom = 1
  setAvatarActive(active: boolean) {
    this.avatarActive = active
    // 控制化身时连点两下是在走路，不放大
    this.camera.doubleClickZoom = !active
    this.svg.classList.toggle('avatar-mode', active)
    this.applyMarkerScale()
    if (!active) {
      this.avatarPrompts = []
      this.prompts.clear()
      this.svg.classList.remove('walk-blocked')
    }
  }
  /** 化身在场或立体场景接手时，标记、文字与提示标签按缩放倍率反向缩放：整图时和观察模式一样大，
   *  放大后沿用人物尺寸比例，名字额外限制为不超过 16 屏幕像素，避免遮住近景。平面观察模式不缩放。 */
  private applyMarkerScale() {
    const scaled = this.avatarActive || !!this.hd
    this.svg.classList.toggle('scaled-labels', scaled)
    const screenScale = Math.abs(this.svg.getScreenCTM()?.a || 1)
    // 名字字号 54 个地图单位：化身模式按人物比例缩小，立体场景固定为 16 屏幕像素
    const fixed = 16 / (54 * screenScale)
    const scale = this.avatarActive
      ? Math.min(1, Math.max(0.25, 1 / this.zoom), fixed)
      : this.hd
        ? Math.min(1, fixed)
        : 1
    this.svg.style.setProperty('--marker-scale', String(scale))
    // 人的名字另算：化身模式放大到中间一档时会缩到 6、7 像素，手机上认不出是谁，最小留 12 像素
    const readable = 12 / (54 * screenScale)
    this.svg.style.setProperty('--name-scale', String(scaled ? Math.max(scale, readable) : scale))
    this.residents.setBodyHeight(this.hd ? VILLAGER_HEIGHT : undefined)
    this.residents.setMarkerScale(scale)
    this.prompts.setScale(4 * scale)
    this.markerScale = scale
    this.anchorProps()
    this.placeDestination()
  }
  /** 人物取名册位置，门取出入口编号对应的门口，道具取图形中心。 */
  setAvatarPrompts(prompts: AvatarPrompt[]) {
    this.avatarPrompts = prompts
    this.prompts.update(prompts, (p) => {
      const point =
        p.kind === 'person'
          ? this.residents.getMemberPos(p.target)
          : p.kind === 'portal'
            ? this.scene.doorAnchor.get(p.target)
            : this.propCenter(p.target)
      return point && this.camera.project(point)
    })
  }
  private avatarPrompts: AvatarPrompt[] = []
  private readonly groundLayer = el('g', { class: 'map-ground' })
  private readonly staticLabels = el('g', { class: 'map-labels' })
  private readonly labelAnchors = new WeakMap<Element, [number, number]>()
  readonly svg: SVGSVGElement
  onPropClick: ((id: string) => void) | null = null
  onVillagerClick: ((id: string) => void) | null = null
  onPromptClick: ((id: string) => void) | null = null
  onAvatarWalkTo: ((target: WalkTarget) => void) | null = null
  onPlaceClick: ((client: [number, number]) => void) | null = null
  onGroundClick: (() => void) | null = null
  private readonly destination = el('g', { class: 'avatar-destination' })
  private destinationAt: WalkTarget | null = null
  /** 摆道具：模式开关、描边的地点、点过的位置 */
  private placing = false
  private placeLocale: string | null = null
  private placeAt: WalkTarget | null = null
  private readonly placeOutline = el('path', { class: 'place-outline' })
  private readonly placeMarker = el('g', { class: 'place-marker' })
  /** 平面图上各区域占的格子，第一次摆道具时才建 */
  private cellsOfRegions?: Map<string, { size: number; cells: Set<string> }>
  private get regionCells() {
    return (this.cellsOfRegions ??= new Map(
      this.sourceAtlas.regions.map((r) => [
        r.id,
        { size: r.cell_size, cells: new Set(r.cells.map(([x, y]) => `${x},${y}`)) },
      ])
    ))
  }
  private markerScale = 1
  /** 道具立牌最近一次实际画的位置，名字和点击区跟着它 */
  private drawnProps: { id: string; x: number; y: number; base: number; size: number }[] = []
  /** 行走坐标的比例由后端随化身状态给出，不在前端复制一份 */
  private walkUnits?: number
  /** 本页正在操控的人：立体场景里他的立牌按本地预测画（见 map/avatarMotion.ts） */
  private liveId: string | null = null
  /** 本页正在操控的人的本地预测：附身的村民还在自己走过来时不预测，和别人一样按名册画 */
  private motion: AvatarMotion | null = null
  setAvatarState(state: AvatarState | null) {
    this.walkUnits = state?.units
    this.liveId = state?.controlled && state.actor?.present ? state.actor.id : null
    const predicted = this.liveId && !state?.awaiting_arrival ? this.liveId : null
    if (predicted !== this.motionId) {
      this.motionId = predicted
      this.motion = predicted
        ? new AvatarMotion((space, x, y) => this.walkGrid().clear(space, x, y))
        : null
      this.hd?.setLiveMotion(this.liveMotion())
      // 先把选路格子建好：第一次走路时才建会卡一下
      if (predicted) setTimeout(() => !this.disposed && this.walkGrid(), 0)
    }
    // 玩家邀请了还没回应的人、正和玩家聊着的人：站着时转身朝向玩家；还在想怎么回时头上冒「…」
    const me = this.liveId ?? ''
    const facing = new Map<string, string>()
    const awaited = new Set<string>()
    for (const i of (me && state?.interactions) || []) {
      if (i.kind.kind !== 'talk') continue
      if (i.status === 'offered' && i.initiator === me) {
        facing.set(i.partner, me)
        awaited.add(i.partner)
      }
      if (i.status === 'running')
        for (const id of [i.initiator, i.partner, ...(i.members ?? [])])
          if (id !== me) facing.set(id, me)
    }
    this.facing = facing
    for (const g of this.svg.querySelectorAll<SVGGElement>('[data-vid]'))
      g.classList.toggle('awaited', awaited.has(g.getAttribute('data-vid') ?? ''))
    this.syncFocus()
  }
  /** 转身朝向谁：村民编号 → 玩家操控的人 */
  private facing = new Map<string, string>()
  /** 村民编号 → 村民库模板编号：内置村民的喜好和小动作按它查 */
  private templates = new Map<string, string | undefined>()
  /** 指针指着的村民：立牌外面一圈白边 */
  private hoveredId: string | null = null
  /** 指到村民（他的头像、身形框、名字）时立牌描白边，离开时去掉 */
  private hoverVillagers() {
    const villager = (target: EventTarget | null) =>
      (target as Element | null)?.closest?.('[data-vid]')?.getAttribute('data-vid') ?? null
    this.svg.addEventListener('pointerover', (e) => {
      const id = villager(e.target)
      if (id === this.hoveredId) return
      this.hoveredId = id
      this.hd?.setPickedVillager(this.selectedId, id)
    })
    this.svg.addEventListener('pointerout', (e) => {
      if (!this.hoveredId || villager(e.relatedTarget) === this.hoveredId) return
      this.hoveredId = null
      this.hd?.setPickedVillager(this.selectedId, null)
    })
  }
  private motionId: string | null = null
  /** 给立体场景的本地预测：米制位置换成地图坐标 */
  private liveMotion(): LiveMotion | null {
    const motion = this.motion
    if (!motion) return null
    return {
      at: (now) => {
        const at = motion.current(now)
        return at && this.walkPoint(at)
      },
      active: () => motion.active(),
      walking: () => motion.walking(),
    }
  }
  /** 本页发出的行走方向和此刻的步速（米 / 秒）：立牌照着它预先走（见 map/avatarMotion.ts） */
  setAvatarMotion(direction: [number, number], metresPerSecond: number) {
    this.motion?.command(direction, metresPerSecond, performance.now())
  }
  avatarAt(): WalkTarget | undefined {
    return this.motion?.current(performance.now())
  }
  /** 立体场景每次画之前调（镜头跟随）：返回这一帧挪了镜头。没有立体场景时返回 false，调用方自己逐帧跑 */
  private frameHook: ((t: number) => boolean) | null = null
  setFrameHook(hook: ((t: number) => boolean) | null): boolean {
    this.frameHook = hook
    if (this.hd) this.hd.beforeDraw = hook ?? undefined
    return !!this.hd
  }
  /** 下一帧就画（不等节拍）：镜头要开始挪了之类 */
  requestFrame() {
    this.hd?.requestDraw()
  }
  private readonly scene: ReturnType<typeof buildStaticMap>
  private readonly sourceAtlas: Atlas
  private readonly spatial?: Spatial
  private readonly topology: Topology
  private readonly theme: MapTheme
  /** 这张地图的地面，只算一次；立体场景建好或平面图画好后就不再留着 */
  private ground?: Ground
  private readonly decor: DecorPlan
  private readonly camera: MapCamera
  private propDefinitions = new Map<string, string>()
  private readonly bubbles = new ThoughtBubbles()
  private readonly residents: ResidentLayer
  private readonly prompts = new PromptLayer()
  private entries: ResidentEntry[] = []
  private selectedId: string | null = null
  /** 道具位置与保存 */
  private readonly positions: PropPositions
  /** 图上画着的道具：地图坐标和立起来用的像素图 */
  private placed: PlacedProp[]
  /** 立体场景里哪些房子掀开屋顶 */
  private readonly rooms: RoomCovers
  /** 立体像素场景；WebGL 不可用或还没加载完时为空，地图退回平面像素图 */
  private hd?: HdScene
  private disposed = false
  /** 立体场景建好或退回平面图之前，SVG 上只有底色和放大的地名；建好前 svg 带 map-loading */
  readonly ready: Promise<void>
  private markReady: () => void = () => {}

  constructor(options: TownMapOptions) {
    const { atlas, topology, container } = options
    this.sourceAtlas = atlas
    this.spatial = options.spatial
    this.topology = topology
    this.propDefinitions = new Map(topology.props.map((p) => [p.id, p.definition ?? '']))
    this.theme = options.theme ?? village
    this.ground = options.ground ?? groundOf(atlas, this.theme)
    this.decor = this.ground.decor
    const scene = (this.scene = buildStaticMap(
      atlas,
      (id) => propArtwork(this.propDefinitions.get(id) ?? ''),
      this.theme
    ))
    this.svg = scene.svg
    // 地面几何随方位角旋转；文字、人物和道具命中区在投影后单独摆放，始终朝向屏幕。
    for (const label of this.svg.querySelectorAll('.rg, .rm')) {
      this.labelAnchors.set(label, [
        Number(label.getAttribute('x')),
        Number(label.getAttribute('y')),
      ])
      this.staticLabels.append(label)
    }
    this.groundLayer.append(...this.svg.childNodes)
    this.svg.append(this.groundLayer, this.staticLabels, scene.details)
    this.rememberPropLabels()
    this.placed = scene.initialProps
    this.rooms = new RoomCovers(scene.spaceAt)
    this.positions = new PropPositions(
      atlas,
      (locale, at) => scene.position(locale, at),
      options.appearanceFor ??
        ((_, definition) => savedAppearance(definition) ?? defaultAppearance),
      options.spatial,
      options.persistence,
      options.notify ?? ((message) => console.error(message)),
      (marks, props) => this.applyProps(marks, props)
    )
    const localeNames = new Map(topology.locales.map((l) => [l.id, l.name]))
    this.residents = new ResidentLayer(
      this.positionOf.bind(this),
      this.bubbles,
      this.metre,
      (id) => localeNames.get(id) ?? id,
      (id) => this.onVillagerClick?.(id)
    )
    this.destination.append(
      el('circle', { class: 'avatar-destination-halo', r: 44 }),
      el('circle', { class: 'avatar-destination-ring', r: 44 }),
      el('circle', { class: 'avatar-destination-dot', r: 14 })
    )
    this.destination.style.display = 'none'
    this.placeMarker.append(
      el('circle', { class: 'place-marker-pulse', r: 30 }),
      el('circle', { class: 'place-marker-ring', r: 30 }),
      el('circle', { class: 'place-marker-dot', r: 12 })
    )
    this.placeMarker.style.display = 'none'
    this.svg.append(
      this.placeOutline,
      this.residents.layer,
      this.destination,
      this.placeMarker,
      this.bubbles.layer,
      this.prompts.layer
    )
    this.nameHoveredProps()
    this.hoverVillagers()
    container.appendChild(this.svg)
    this.svg.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return
      const prop = event.target instanceof Element ? event.target.closest('[data-prop-id]') : null
      const id = prop?.getAttribute('data-prop-id')
      if (id) {
        event.preventDefault()
        this.onPropClick?.(id)
      }
    })
    this.camera = new MapCamera(
      this.svg,
      container,
      scene.initialView,
      (zoom) => {
        // 平移也会走到这里；只有倍率变了才重新分组
        const zoomed = zoom !== this.zoom
        this.zoom = zoom
        this.bubbles.setZoom(zoom)
        this.applyMarkerScale()
        if (zoomed) this.residents.relayout()
        this.refreshRooms()
      },
      (id) => this.onVillagerClick?.(id),
      (id) => this.onPropClick?.(id),
      (id) => this.onPromptClick?.(id),
      (point, client) => {
        if (this.placing) return this.onPlaceClick?.(client)
        if (this.onAvatarWalkTo) this.onAvatarWalkTo(this.walkTargetAt(point))
        this.onGroundClick?.()
      },
      (key, client) => this.residents.openGroup(key, client),
      // 双指上下拖调俯角：和右键拖动同样每像素 0.2 度
      (dy) => {
        if (this.hd) this.hd.setPitch(this.hd.pitch + dy * 0.2)
      }
    )
    // 控制化身时指针下附近都走不到就换成禁止的指针；每帧最多算一次
    let hover: { client: [number, number]; target: EventTarget | null } | null = null
    this.svg.addEventListener('pointermove', (e) => {
      if (!this.avatarActive || e.pointerType !== 'mouse') return
      if (!hover)
        requestAnimationFrame(() => {
          if (hover && !this.disposed) this.hoverWalk(hover.client, hover.target)
          hover = null
        })
      hover = { client: [e.clientX, e.clientY], target: e.target }
    })
    this.svg.classList.add('map-loading')
    this.ready = new Promise((resolve) => (this.markReady = resolve))
    this.startHd(atlas)
  }

  private loaded() {
    this.svg.classList.remove('map-loading')
    this.markReady()
  }

  /** 立体场景按需加载；加载或建场景失败（比如没有 WebGL）就退回平面像素地面 */
  private startHd(atlas: Atlas) {
    void import('./map/hd2d/scene')
      .then(({ HdScene }) => {
        const container = this.svg.parentElement
        if (this.disposed || !container || !this.ground) return
        this.hd = new HdScene(atlas, this.ground, container, this.svg)
        this.ground = undefined
        this.svg.classList.add('hd2d')
        this.applyMarkerScale()
        if (this.clock) this.hd.setClock(...this.clock)
        this.rooms.attach(this.svg, this.hd.houses)
        this.hd.onTilt = () => this.applyTilt()
        this.hd.onVillagersMoved = () => this.followVillagers()
        this.hd.beforeDraw = this.frameHook ?? undefined
        this.hd.setLiveMotion(this.liveMotion())
        this.hd.onNotice = (text) => this.onRenderNotice?.(text)
        this.hd.setPickedVillager(this.selectedId, this.hoveredId)
        this.syncFocus()
        this.applyTilt()
        if (this.viewInsets) this.hd.setFocusInsets(this.viewInsets.top, this.viewInsets.bottom)
        this.camera.setViewPresets([
          { label: '街景', title: '低角度看广场与街巷', apply: () => this.showCameraPreset(false) },
          { label: '俯视', title: '从上方看全镇布局', apply: () => this.showCameraPreset(true) },
        ])
      })
      .catch((error) => {
        console.warn('立体像素场景未能启动，使用平面地图', error)
        this.showFlat(atlas)
      })
      .finally(() => this.loaded())
  }

  /** 取景只读图集：围绕本镇真正的广场组织街景，俯视容纳道路和所有建筑，不依赖默认地图坐标。 */
  private showCameraPreset(overhead: boolean) {
    const hd = this.hd
    if (!hd) return
    hd.setYaw(0)
    hd.setPitch(overhead ? PITCH_MAX : DEFAULT_PITCH)
    const atlas = this.sourceAtlas
    let x0 = Infinity,
      y0 = Infinity,
      x1 = -Infinity,
      y1 = -Infinity
    const include = (x: number, y: number) => {
      x0 = Math.min(x0, x)
      y0 = Math.min(y0, y)
      x1 = Math.max(x1, x)
      y1 = Math.max(y1, y)
    }
    for (const region of atlas.regions)
      for (const [x, y] of region.cells) {
        include(x * region.cell_size, y * region.cell_size)
        include((x + 1) * region.cell_size, (y + 1) * region.cell_size)
      }
    for (const space of atlas.spaces) {
      if (space.id === OUTDOOR_SPACE) continue
      const box = roomRect(space)
      include(box.x, box.y)
      include(box.x1, box.y1)
    }
    for (const edge of atlas.edges) for (const point of edge.polyline) include(...point)
    if (!Number.isFinite(x0)) {
      x0 = y0 = 0
      x1 = atlas.canvas.width
      y1 = atlas.canvas.height
    }
    const width = Math.max(1, x1 - x0),
      height = Math.max(1, y1 - y0)
    let area: CameraArea
    if (overhead) {
      // 屋脊仍高于地面，四边留空让最外侧的屋顶、树冠与水岸能完整入镜。
      area = {
        x: x0 - width * 0.08,
        y: y0 - height * 0.12,
        width: width * 1.16,
        height: height * 1.2,
      }
    } else {
      const plazas = atlas.regions.filter(
        (region) => region.kind === 'plaza' && region.cells.length
      )
      const plaza = plazas.sort(
        (a, b) => b.cells.length * b.cell_size ** 2 - a.cells.length * a.cell_size ** 2
      )[0]
      const center = plaza
        ? plaza.cells.reduce(
            (point, [x, y]) => [
              point[0] + ((x + 0.5) * plaza.cell_size) / plaza.cells.length,
              point[1] + ((y + 0.5) * plaza.cell_size) / plaza.cells.length,
            ],
            [0, 0]
          )
        : [x0 + width / 2, y0 + height / 2]
      // 广场位于清晰中景偏下处，镜头向北多留一些空间给屋顶、树林与远雾。
      const viewWidth = width * 0.58,
        viewHeight = height * 0.64
      area = {
        x: center[0] - viewWidth / 2,
        y: center[1] - viewHeight * 0.58,
        width: viewWidth,
        height: viewHeight,
      }
    }
    this.camera.frameArea(area)
  }
  /** 平面像素地面（带树）垫在 SVG 最底层，天气和昼夜也改由 SVG 天气层画 */
  private showFlat(atlas: Atlas) {
    if (this.disposed || !this.ground) return
    this.scene.showTerrain(paintGround(this.ground, true))
    this.ground = undefined
    this.weather = new WeatherLayer(this.svg, atlas)
    this.svg.insertBefore(this.weather.layer, this.residents.layer)
    if (this.lastRoster) this.weather.handleMsg(this.lastRoster)
  }
  /** 地面随俯角倾斜：地图视口纵向压扁，立着的文字按比例拉回，房间名跟着屋顶高度走 */
  private applyTilt() {
    if (!this.hd) return
    this.groundLayer.setAttribute('transform', `rotate(${this.hd.yaw})`)
    this.camera.setYaw(this.hd.yaw)
    this.camera.setVerticalScale(this.hd.verticalScale)
    this.residents.setProjection(this.camera.project)
    this.placeDestination()
    this.rooms.reset()
    this.refreshRooms()
    this.standLabels()
    this.setAvatarPrompts(this.avatarPrompts)
    this.followVillagers()
  }
  /** 地名、房间名和道具名按俯角拉回；跟着立牌走的道具名和房间名挪动时各自再拉一次 */
  private standLabels() {
    const k = this.hd ? 1 / this.hd.verticalScale : 1
    for (const label of this.svg.querySelectorAll('.rg, .pl')) {
      const anchor = this.labelAnchors.get(label)
      if (anchor) {
        const [x, y] = this.camera.project(anchor)
        label.setAttribute('x', String(x))
        label.setAttribute('y', String(y))
      }
      standUpright(label, k)
    }
    this.anchorProps()
  }
  private rememberPropLabels() {
    for (const label of this.scene.propLabels.values())
      this.labelAnchors.set(label, [
        Number(label.getAttribute('x')),
        Number(label.getAttribute('y')),
      ])
  }
  private clock?: [number, string | undefined]

  /** 立体场景跟上房子的开合（见 RoomCovers）、村民和道具立牌；fresh 表示刚来了一份名册 */
  private refreshRooms(fresh = false) {
    const hd = this.hd
    if (!hd) return
    const avatar = this.entries.find((e) => e.member.kind === 'avatar')
    const [x, y, w, h] = this.zoom >= 1.5 ? (this.camera?.getViewBox() ?? []) : []
    const changed = this.rooms.update([
      this.selectedId ? this.residents.getMemberAnchor(this.selectedId) : undefined,
      avatar && this.residents.getMemberAnchor(avatar.member.id),
      w ? this.camera.unproject([x + w / 2, y + h / 2]) : undefined,
    ])
    const covered = this.rooms.covered
    this.residents.setCovered(covered)
    hd.setVillagers(this.villagerPlacements(covered), fresh)
    if (!changed) return
    this.rooms.apply(hd, this.camera.project)
    this.drawnProps = hd.setProps(this.coverProps(covered))
    this.anchorProps()
  }

  /** 立体场景里道具名字不常驻：指到（或键盘聚焦）某个道具时才出现，选中的道具一直有 */
  private nameHoveredProps() {
    const toggle = (target: EventTarget | null, on: boolean) => {
      const id = (target as Element | null)
        ?.closest?.('[data-prop-id]')
        ?.getAttribute('data-prop-id')
      if (!id) return
      const selected = this.scene.props.get(id)?.classList.contains('selected-prop')
      this.scene.propLabels.get(id)?.classList.toggle('named', on || !!selected)
    }
    for (const type of ['pointerover', 'focusin'])
      this.svg.addEventListener(type, (e) => toggle(e.target, true))
    for (const type of ['pointerout', 'focusout'])
      this.svg.addEventListener(type, (e) => toggle(e.target, false))
  }

  /** 道具的点击区和名字跟着立牌走：点击区在立牌中心，名字挂在立牌头顶再高一点 */
  private anchorProps() {
    const up = this.hd ? 1 / this.hd.verticalScale : 1
    for (const p of this.placed) {
      const [x, y] = this.camera?.project(p.at) ?? p.at
      this.scene.props.get(p.id)?.setAttribute('transform', `translate(${x} ${y})`)
    }
    for (const p of this.drawnProps) {
      // 点击区中心对准立牌中心：立牌底边在 base，向上立起 size（屏幕上按俯角拉回）
      const [x, y] = this.camera.project([p.x, p.y])
      const base = y + p.base - p.y
      const centre = base - (p.size * up) / 2
      this.scene.props
        .get(p.id)
        ?.setAttribute('transform', `translate(${x} ${centre}) scale(1 ${up})`)
      const label = this.scene.propLabels.get(p.id)
      if (!label) continue
      label.setAttribute('x', String(x))
      label.setAttribute('y', String(base - p.size * up - 18 * this.markerScale * up))
      standUpright(label, up)
    }
  }

  /** 站着时朝向谁：被玩家邀请、正和玩家聊的人朝向玩家；聊天的人朝向正在说话的人，自己在说就朝向对方 */
  private faceToward(member: ResidentEntry['member']): [number, number] | undefined {
    const other =
      this.facing.get(member.id) ??
      (member.chat &&
        (member.chat.turn && member.chat.turn !== member.id
          ? member.chat.turn
          : member.chat.participants.find((p) => p !== member.id)))
    return other ? this.residents.getMemberPos(other) : undefined
  }

  private villagerPlacements(covered: (p: [number, number]) => boolean): VillagerPlacement[] {
    return this.entries.flatMap(({ member }) => {
      const p = this.residents.getMemberPos(member.id)
      return p
        ? [
            {
              id: member.id,
              look: this.residents.lookOf(member.id),
              x: p[0],
              y: p[1],
              visible: !covered(p),
              live: member.id === this.motionId,
              faceToward: this.faceToward(member),
              cue: cueOf(
                member,
                this.lastRoster?.sim_minutes ?? 0,
                this.templates.get(member.id),
                this.scene.spaceAt(p) !== OUTDOOR_SPACE
              ),
            },
          ]
        : []
    })
  }

  /** 盖着屋顶的房子里的道具连名字藏起来；有像素图的道具在立体场景里立起来，SVG 里的图只留作点击区 */
  private coverProps(covered: (p: [number, number]) => boolean): PropPlacement[] {
    const standees: PropPlacement[] = []
    for (const { id, at, art } of this.placed) {
      const hidden = covered(at)
      this.scene.props.get(id)?.classList.toggle('roofed', hidden)
      this.scene.propLabels.get(id)?.classList.toggle('roofed', hidden)
      if (art)
        standees.push({ id, url: art.url, x: at[0], y: at[1], size: art.size, visible: !hidden })
    }
    return standees
  }

  /** SVG 单位每米；没有三维数据时人物位置直接来自平面图集，不需要换算 */
  private get metre(): number | undefined {
    return this.spatial?.svg_units_per_metre
  }

  private positionOf(locale: string, at: ResidentEntry['member']['at']) {
    if (!this.spatial) return this.scene.position(locale, at)
    const p = spatialPosition(this.spatial, locale, at)
    const metre = this.spatial.svg_units_per_metre
    return p ? ([p[0] * metre, p[2] * metre] as [number, number]) : undefined
  }

  private get walkUnit(): number {
    return this.walkUnits ?? this.metre ?? LEGACY_UNITS_PER_METRE
  }
  /** 画面坐标 → 米制行走坐标。有三维数据时全图一个比例，否则按房间的摊开变换反算。 */
  private walkTarget(point: [number, number]): WalkTarget {
    const space = this.scene.spaceAt(point)
    const [x, y] = this.spatial ? point : this.scene.toLocal(space, point)
    return { space, position: [x / this.walkUnit, y / this.walkUnit] }
  }
  /** walkTarget 的反向：米制行走坐标 → 画面坐标 */
  private walkPoint(target: WalkTarget): [number, number] {
    const [x, y] = [target.position[0] * this.walkUnit, target.position[1] * this.walkUnit]
    return this.spatial ? [x, y] : this.scene.toWorld(target.space, x, y)
  }
  /** 选路用的格子图：第一次要走路时才建，之后跟着地图上的道具更新障碍 */
  private routes?: WalkRoutes
  private routeMarks: { id: string; at: [number, number] }[] = []
  private walkGrid(): WalkRoutes {
    if (!this.routes) {
      const t = this.spatial?.terrain
      // 和后端 WalkMap::terrain_clear 一样：在地形范围里、高出海面、往东往南 0.2 米的落差都不大
      const ground =
        t &&
        ((x: number, y: number) => {
          const [ox, oy] = t.origin
          if (
            x < ox ||
            y < oy ||
            x > ox + t.step * (t.columns - 1) ||
            y > oy + t.step * (t.rows - 1)
          )
            return false
          const h = heightAt(t, x, y)
          return (
            h > t.sea_level + 0.05 &&
            Math.abs(heightAt(t, x + 0.2, y) - h) <= 0.16 &&
            Math.abs(heightAt(t, x, y + 0.2) - h) <= 0.16
          )
        })
      this.routes = new WalkRoutes(this.sourceAtlas, this.topology, this.walkUnit, !!this.spatial, {
        routes: this.spatial?.routes.map((r) => ({ ...r, points: r.points })),
        ground: ground || undefined,
      })
      this.applyRouteObstacles()
    }
    return this.routes
  }
  walkRoute(from: WalkTarget, to: WalkTarget): WalkStep[] | null {
    return this.walkGrid().find(from, to)
  }
  walkSees(from: WalkTarget, to: WalkTarget): boolean {
    return this.walkGrid().sees(from, to)
  }

  /** 控制化身时点了地图：点在盖着屋顶的房子（屋顶、墙）上就走进它的门，不然走到点的地面；
   *  这一点站不了时由选路换成附近能站的地方 */
  private walkTargetAt(point: [number, number]): WalkTarget {
    if (!this.avatarActive) return this.walkTarget(point)
    const house = this.houseAt(this.camera.project(point))
    const door = house ? this.walkGrid().entrance(house) : undefined
    return door?.inside ?? this.walkTarget(point)
  }

  /** 立体场景里一点（视图坐标）落在哪栋房子的墙和屋顶上：房子立起来后遮住了它后面的地面，
   *  点在那里是点房子，不是点房子后面的地。点在掀开屋顶的房间地面上不算。重叠时取离镜头近的 */
  private houseAt([vx, vy]: [number, number]): string | undefined {
    const hd = this.hd
    if (!hd) return
    let best: { id: string; front: number } | undefined
    for (const house of hd.houses) {
      const centre: [number, number] = [house.x + house.w / 2, house.y + house.h / 2]
      const open = !this.rooms.covered(centre)
      const foot = (
        [
          [house.x, house.y],
          [house.x + house.w, house.y],
          [house.x + house.w, house.y + house.h],
          [house.x, house.y + house.h],
        ] as [number, number][]
      ).map(this.camera.project)
      // 立起来的高度：盖着屋顶时到屋脊，掀开后只有墙（和 RoomCovers 摆房间名的算法一样）
      const rise = open
        ? house.y - hd.roomTop(house)
        : house.y + (house.alongX ? house.h / 2 : 0) - hd.roofTop(house)
      const outline = hull([...foot, ...foot.map(([x, y]) => [x, y - rise] as [number, number])])
      if (!inside(outline, [vx, vy])) continue
      // 掀开的房间：点在地面上就是走到屋里那一点
      if (open && inside(foot, [vx, vy])) continue
      const front = Math.max(...foot.map((p) => p[1]))
      if (!best || front > best.front) best = { id: house.id, front }
    }
    return best?.id
  }

  /** 指针下面能不能走过去：控制化身时，附近都走不到的地方显示禁止的指针 */
  private hoverWalk(client: [number, number], target: EventTarget | null) {
    const blocked =
      this.avatarActive &&
      !this.placing &&
      !(
        target instanceof Element &&
        target.closest('[data-vid],[data-prop-id],[data-prompt],[data-group]')
      ) &&
      (() => {
        const point = this.camera.groundAt(...client)
        const house = this.houseAt(this.camera.project(point))
        return (
          !(house && this.walkGrid().entrance(house)) &&
          !this.walkGrid().destination(this.walkTarget(point))
        )
      })()
    this.svg.classList.toggle('walk-blocked', blocked)
  }
  /** 挡路的是立在图上的道具（见 applyProps 里的 routeMarks）。
   *  有三维数据时道具按自己的占地算，树木也一并算上，与 maps/walk.rs 一致。 */
  private applyRouteObstacles() {
    const footprints = new Map(this.spatial?.props.map((p) => [p.id, p.footprint]))
    const obstacles = this.routeMarks.map((mark) => {
      const size = footprints.get(mark.id)
      return {
        ...this.walkTarget(mark.at),
        half: size ? ([size[0] / 2, size[1] / 2] as [number, number]) : PROP_HALF,
      }
    })
    for (const v of this.spatial?.vegetation ?? [])
      if (v.collider_radius > 0)
        obstacles.push({
          space: OUTDOOR_SPACE,
          position: [v.position[0], v.position[2]],
          half: [v.collider_radius, v.collider_radius],
        })
    // 二维地图的装饰树（town-shared/decor）同样挡路，与 spatial.vegetation 一致
    if (!this.spatial) {
      const unit = this.walkUnit
      for (const v of this.decor.vegetation) {
        if (!v.kind.startsWith('tree')) continue
        obstacles.push({
          space: OUTDOOR_SPACE,
          position: [v.x / unit, v.y / unit],
          half: [0.5, 0.5],
        })
      }
    }
    this.routes?.setObstacles(obstacles)
  }
  walkTargetOf(kind: 'person' | 'prop', id: string) {
    // 道具按摆放的位置（和后端判断够不够得着、选路避让用的是同一个点），不按画出来的图形中心：
    // 公告栏、摊位这类高的道具图形中心在摆放点北边好几米，走到那里还是够不着
    const point =
      kind === 'person'
        ? this.residents.getMemberAnchor(id)
        : (this.placed.find((p) => p.id === id)?.at ?? this.propCenter(id))
    return point ? this.walkTarget(point) : undefined
  }
  setAvatarDestination(target: WalkTarget | null) {
    this.destinationAt = target
    this.placeDestination()
  }
  /** 目的地标记跟着人物标记一起反向缩放，放大后不会盖住半张图 */
  private placeDestination() {
    this.pin(this.destination, this.destinationAt)
    this.pin(this.placeMarker, this.placeAt)
    this.placeOutline.setAttribute(
      'd',
      (this.placeLocale ? this.outlineOf(this.placeLocale) : [])
        .map((line) => 'M' + line.map((p) => this.camera.project(p).join(' ')).join('L'))
        .join('')
    )
  }
  private pin(marker: SVGGElement, at: WalkTarget | null) {
    marker.style.display = at ? '' : 'none'
    if (!at) return
    const [x, y] = this.camera.project(this.walkPoint(at))
    const s = this.markerScale,
      sy = s * uprightRatio(this.svg)
    marker.setAttribute(
      'transform',
      `translate(${x} ${y})${s === 1 && sy === 1 ? '' : ` scale(${s} ${sy})`}`
    )
  }

  /** 摆道具模式：开着时点空地交给 onPlaceClick，不让化身走过去；关掉时清掉描边和定位点 */
  setPlacing(placing: boolean) {
    this.placing = placing
    this.svg.classList.toggle('placing', placing)
    if (!placing) this.placeLocale = this.placeAt = null
    this.placeDestination()
  }
  setPlaceHighlight(locale: string | null) {
    this.placeLocale = locale
    this.placeDestination()
  }
  setPlaceMarker(target: WalkTarget | null) {
    this.placeAt = target
    this.placeDestination()
  }
  placeSpotAt(client: [number, number]): PlaceSpot | undefined {
    const point = this.camera.groundAt(...client)
    const locale = this.localeAt(point)
    return locale ? { locale, near: this.walkTarget(point) } : undefined
  }
  /** 能放东西的地点：有三维数据时按各地点的可放置范围（和后端放置器用的同一块），
   *  否则按房间和图上的区域格子；只认居民能待的地点，路段和通道不算 */
  private localeAt(point: [number, number]): string | undefined {
    const dwell = (id: string | undefined) =>
      id && this.topology.locales.some((l) => l.id === id && l.kind === 'dwell') ? id : undefined
    if (this.spatial) {
      const unit = this.spatial.svg_units_per_metre
      const [x, z] = [point[0] / unit, point[1] / unit]
      const floors = (this.spatial.floors ?? []).filter(
        ({ bounds: b }) => x >= b.x && x <= b.x + b.w && z >= b.y && z <= b.y + b.h
      )
      // 范围套着范围时取小的那个：屋子在院子里，点屋里就是放进屋里
      floors.sort((a, b) => a.bounds.w * a.bounds.h - b.bounds.w * b.bounds.h)
      return dwell(floors[0]?.id)
    }
    const space = this.scene.spaceAt(point)
    if (space !== OUTDOOR_SPACE) return dwell(space)
    for (const [id, { size, cells }] of this.regionCells)
      if (cells.has(`${Math.floor(point[0] / size)},${Math.floor(point[1] / size)}`))
        return dwell(id)
    return undefined
  }
  /** 地点的边（地图坐标的折线）：可放置范围和房间是矩形，区域是格子外沿的一段段边 */
  private outlineOf(locale: string): [number, number][][] {
    const rect = (x0: number, y0: number, x1: number, y1: number): [number, number][] => [
      [x0, y0],
      [x1, y0],
      [x1, y1],
      [x0, y1],
      [x0, y0],
    ]
    if (this.spatial) {
      const unit = this.spatial.svg_units_per_metre
      const b = this.spatial.floors?.find((f) => f.id === locale)?.bounds
      return b ? [rect(b.x * unit, b.y * unit, (b.x + b.w) * unit, (b.y + b.h) * unit)] : []
    }
    const room = this.sourceAtlas.spaces.find((s) => s.id === locale)
    if (room) {
      const box = roomRect(room)
      return [rect(box.x, box.y, box.x1, box.y1)]
    }
    const region = this.regionCells.get(locale)
    if (!region) return []
    const { size, cells } = region
    const edges: [number, number][][] = []
    for (const key of cells) {
      const [cx, cy] = key.split(',').map(Number)
      const [x0, y0, x1, y1] = [cx * size, cy * size, (cx + 1) * size, (cy + 1) * size]
      if (!cells.has(`${cx},${cy - 1}`))
        edges.push([
          [x0, y0],
          [x1, y0],
        ])
      if (!cells.has(`${cx + 1},${cy}`))
        edges.push([
          [x1, y0],
          [x1, y1],
        ])
      if (!cells.has(`${cx},${cy + 1}`))
        edges.push([
          [x1, y1],
          [x0, y1],
        ])
      if (!cells.has(`${cx - 1},${cy}`))
        edges.push([
          [x0, y1],
          [x0, y0],
        ])
    }
    return edges
  }

  handleMsg(msg: ServerMsg) {
    this.weather?.handleMsg(msg)
    if (msg.type === 'roster') {
      this.lastRoster = msg
      this.clock = [
        DEV_CLOCK?.minutes ?? msg.sim_minutes,
        DEV_CLOCK?.weather ?? msg.environment?.kind,
      ]
      this.hd?.setClock(...this.clock)
    }
    if (msg.type === 'population') {
      this.templates = new Map(msg.population.residents.map((r) => [r.id, r.template_id]))
      this.residents.setPopulation(msg.population.residents)
      this.refreshRooms()
    }
  }
  disconnect() {
    this.weather?.disconnect()
  }
  dispose() {
    this.disposed = true
    this.markReady()
    this.hd?.dispose()
    this.weather?.dispose()
    this.positions.dispose()
    this.camera.dispose()
    this.residents.dispose()
    this.svg.remove()
  }

  /** 道具位置算好（PropPositions）：重画道具，交给立体场景、寻路和感知 */
  private applyProps(marks: Atlas['props'], props: PropView[]) {
    this.propDefinitions = new Map(props.map((p) => [p.id, p.definition ?? '']))
    // 地图上的书：挨着的几本合成一摞画
    const books = new Map(
      props.filter((p) => p.readable?.kind === 'book').map((p) => [p.id, p.locale])
    )
    this.placed = this.scene.replaceProps(marks, books)
    this.rememberPropLabels()
    this.rooms.reset()
    this.refreshRooms()
    this.standLabels()
    // 和后端 avatar_obstacles 一样只算立着的道具：有物品位置的（放在地上、拿在手里、收在容器里）不挡路。
    // 放在屋里地上的物品画在房间的落脚点上，那一点常常就在门口，算成障碍会把门堵死、整间屋都选不出路
    const loose = new Set(props.filter((p) => p.location).map((p) => p.id))
    this.routeMarks = this.placed
      .filter(({ id }) => !loose.has(id))
      .map(({ id, at }) => ({ id, at }))
    this.applyRouteObstacles()
  }

  setProps(props: PropView[]) {
    this.positions.update(props)
  }
  /** 这件道具画在一摞书里：点它打开「书与公告」里这个地点的书，不弹单本的卡片 */
  isBookPile(id: string) {
    return !!this.scene.props.get(id)?.classList.contains('book-pile')
  }
  /** 道具图形的中心；没有图形时返回 undefined */
  private propCenter(id: string): [number, number] | undefined {
    const shape = this.scene.props.get(id)
    const graphic = shape instanceof SVGGraphicsElement ? shape : undefined
    const box = graphic?.getBBox()
    const matrix = graphic?.transform.baseVal.consolidate()?.matrix
    return box && matrix
      ? this.camera.unproject([
          matrix.e + box.x + box.width / 2,
          matrix.f + (box.y + box.height / 2) * matrix.d,
        ])
      : undefined
  }
  locateProp(id: string, locale: string) {
    const shape = this.scene.props.get(id)
    const pos = this.propCenter(id) ?? this.scene.localeAnchor.get(locale)
    if (pos) {
      const projected = this.camera.project(pos)
      const view = this.camera.getViewBox()
      const width = Math.min(view[2], 1500),
        height = (width * view[3]) / view[2]
      this.camera.setViewBox([projected[0] - width / 2, projected[1] - height / 2, width, height])
    }
    this.svg
      .querySelectorAll('.selected-prop')
      .forEach((el) => el.classList.remove('selected-prop'))
    this.svg.querySelectorAll('.pl.named').forEach((el) => el.classList.remove('named'))
    shape?.classList.add('selected-prop')
    this.scene.propLabels.get(id)?.classList.add('named')
  }
  onReset() {
    this.lastRoster = undefined
    this.weather?.reset()
    this.bubbles.onReset()
    this.entries = []
  }
  setSpeed(speed: number) {
    this.bubbles.setSpeed(speed)
    this.weather?.setSpeed(speed)
  }
  /** 村民在屏幕上的位置：按画出来的立牌算（比名册晚一点），聊天气泡等跟着人走的东西不超前 */
  getScreenPos(id: string): [number, number] | undefined {
    const p = this.getMemberPos(id),
      matrix = this.svg.getScreenCTM()
    if (!p || !matrix) return
    const [dx, dy] = this.hd?.villagerLag(id) ?? [0, 0]
    const [x, y] = this.camera.project([p[0] + dx, p[1] + dy])
    const point = new DOMPoint(x, y).matrixTransform(matrix)
    return [point.x, point.y]
  }
  /** 村民在屏幕上的范围：立牌高度按横向缩放折算；平面地图退回头像标记的尺寸 */
  getScreenBox(id: string): ScreenBox | undefined {
    const p = this.getScreenPos(id),
      a = Math.abs(this.svg.getScreenCTM()?.a || 1)
    if (!p) return
    // 立体场景里头顶撑着伞、冒着符号时，气泡躲开那一截
    const height = this.hd ? VILLAGER_HEIGHT + this.hd.villagerCrown(id) : 108 * this.markerScale
    const half = this.hd ? VILLAGER_HALF : 58 * this.markerScale
    return { x: p[0], feet: p[1], top: p[1] - height * a, half: half * a }
  }
  getMemberPos(id: string) {
    return this.residents.getMemberPos(id)
  }
  /** 立牌此刻画在哪（地图坐标）：立体场景里立牌和名册差一点，平面图上就是名册位置 */
  getDrawnPos(id: string): [number, number] | undefined {
    const p = this.residents.getMemberPos(id)
    const lag = this.hd?.villagerLag(id)
    return p && lag ? [p[0] + lag[0], p[1] + lag[1]] : p
  }
  /** 镜头跟着化身（见 MapCamera.follow）：返回这一帧挪了镜头 */
  followTo(x: number, y: number, dt: number, how?: 'window' | 'centre' | 'snap') {
    return this.camera.follow(x, y, dt, how)
  }
  /** 滚轮缩放的不动点：给了就围着它缩（化身跟随时围着化身），没有就围着鼠标 */
  setZoomAnchor(anchor: (() => [number, number] | undefined) | null) {
    this.camera.zoomAnchor = anchor
  }
  /** 地图被面板盖住的四边；立体场景晚一步建好时补上 */
  private viewInsets: { top: number; right: number; bottom: number; left: number } | undefined
  setViewInsets(insets: { top: number; right: number; bottom: number; left: number }) {
    this.camera.setInsets(insets)
    this.viewInsets = insets
    this.hd?.setFocusInsets(insets.top, insets.bottom)
  }
  panTo(x: number, y: number) {
    this.camera.panTo(x, y)
  }
  getViewBox() {
    const [x, y, w, h] = this.camera.getViewBox()
    const [cx, cy] = this.camera.unproject([x + w / 2, y + h / 2])
    return [cx - w / 2, cy - h / 2, w, h]
  }
  setViewBox(view: number[]) {
    // 公共地图接口仍用世界中心，化身模式和设置面板保存/恢复镜头不需要知道方位角。
    const [x, y, w, h] = view
    const [cx, cy] = this.camera.project([x + w / 2, y + h / 2])
    this.camera.setViewBox([cx - w / 2, cy - h / 2, w, h])
  }
  /** 立体场景的俯角；平面地图没有 */
  /** 画面想告诉玩家的一句话（画质自动降档），外壳放进事件栏 */
  onRenderNotice: ((text: string) => void) | null = null
  /** 地图画质（设定 · 显示） */
  setRenderQuality(quality: Quality) {
    this.hd?.setQuality(quality)
  }
  mapPitch() {
    return this.hd?.pitch
  }
  setMapPitch(degrees: number) {
    this.hd?.setPitch(degrees)
  }
  /** 进游戏后第一份名册里选中的人：镜头对准他，不停在空广场 */
  private rosters = 0
  setSelected(id: string | null) {
    this.selectedId = id
    this.residents.setSelected(id)
    this.hd?.setPickedVillager(id, this.hoveredId)
    const pos = id && this.rosters === 1 ? this.residents.getMemberPos(id) : undefined
    if (pos) {
      this.camera.lookAt(pos[0], pos[1])
      this.rosters++
    }
    this.refreshRooms()
    this.syncFocus()
  }
  /** 立体场景的焦点跟着选中的人，没选人时跟着玩家操控的人；他在交谈时清晰带收窄，像特写 */
  private syncFocus() {
    const id = this.selectedId ?? this.liveId
    const member = id ? this.entries.find((e) => e.member.id === id)?.member : undefined
    this.hd?.setFocusSubject(member ? member.id : null, !!member?.chat)
  }
  update(entries: ResidentEntry[]) {
    if (this.rosters < 2) this.rosters++
    this.entries = entries
    this.residents.update(entries)
    this.syncFocus()
    // 名册里自己的位置是服务端的权威位置：交给本地预测校正
    const me = this.motionId && entries.find((e) => e.member.id === this.motionId)?.member.at
    if (this.motion && me && me.kind === 'free')
      this.motion.sample({ space: me.space, position: me.position }, performance.now())
    this.refreshRooms(true)
  }

  /** 立牌比名册晚一点、匀速走：名字和心声泡按名册摆好后，平移回立牌头上，跟着它一起走 */
  private followVillagers() {
    const hd = this.hd
    if (!hd) return
    for (const { member } of this.entries) {
      const worldLag = hd.villagerLag(member.id)
      const lag = worldLag && this.camera.project(worldLag)
      this.residents.follow(member.id, lag)
      this.bubbles.follow(member.id, lag)
    }
  }
}

/** 凸包（单调链）：点不多，算房子立起来以后在画面上占的轮廓 */
function hull(points: [number, number][]): [number, number][] {
  const sorted = [...points].sort((a, b) => a[0] - b[0] || a[1] - b[1])
  const cross = (o: [number, number], a: [number, number], b: [number, number]) =>
    (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
  const half = (list: [number, number][]) => {
    const out: [number, number][] = []
    for (const p of list) {
      while (out.length >= 2 && cross(out[out.length - 2], out[out.length - 1], p) <= 0) out.pop()
      out.push(p)
    }
    return out.slice(0, -1)
  }
  return [...half(sorted), ...half([...sorted].reverse())]
}

/** 点在凸多边形里（边上也算） */
function inside(polygon: [number, number][], [x, y]: [number, number]): boolean {
  let sign = 0
  for (let i = 0; i < polygon.length; i++) {
    const [ax, ay] = polygon[i],
      [bx, by] = polygon[(i + 1) % polygon.length]
    const side = Math.sign((bx - ax) * (y - ay) - (by - ay) * (x - ax))
    if (!side) continue
    if (!sign) sign = side
    else if (side !== sign) return false
  }
  return true
}
