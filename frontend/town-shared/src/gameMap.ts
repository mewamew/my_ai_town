import type { AvatarLook, AvatarState } from './avatar/types'
import type { PlaceGrid, RosterMember, ServerMsg } from './protocol'
import type { PropCatalog, PropView } from './props/types'
import type { Insets } from './mapView'
import type { DepthBlur, Quality } from './quality'
import type { WeatherKind } from './weather/types'
export type ResidentEntry = { locale: string; member: RosterMember }
/** 居民在屏幕上的范围（CSS 像素）：脚底点的 x 与 y、头顶的 y、身体半宽 */
export interface ScreenBox {
  x: number
  feet: number
  top: number
  half: number
}
/** 化身在场时画在附近对象上方的提示标签；点击等于按对应的键。 */
export interface AvatarPrompt {
  id: string
  kind: 'person' | 'portal' | 'prop'
  /** 人物、门或道具的编号，渲染器据此定位 */
  target: string
  label: string
  /** 主动作的按键；同一时刻只有一个提示带它 */
  key?: string
  /** 现在做不了（对方正忙）：只显示，不响应点击 */
  muted?: boolean
  /** 同一对象的另一件事和它的键（开着化身神力时活人的「F 神力」）；画在主动作后面 */
  alt?: { key: string; label: string }
  /** 当前对象：Tab 换到的那个，没换过时是最近的；同一时刻只有一个。2D 地图只画它 */
  focused?: boolean
}
/** 点击移动的目标：米制坐标，和后端行走地图同一坐标系 */
export interface WalkTarget {
  space: string
  position: [number, number]
}
/** 摆道具时点到的地方：落在哪个地点，以及那一点的行走坐标（放置命令的 near） */
export interface PlaceSpot {
  locale: string
  /** 有格子时已经吸到离指针最近的能放的格子；这块地放满了时就是指针那一点 */
  near: WalkTarget
  /** 有格子时：指针那一点，以及它所在那一格放不下的原因（'.' 是能放，见 PlaceGrid.cells） */
  point?: WalkTarget
  code?: string
  /** 碰到或挡路的那件道具的编号 */
  by?: string
  /** 这块地一格都放不下了 */
  full?: boolean
}
/** 摆道具的绿框：东西会落在哪、占多大（米） */
export interface PlaceGhost {
  at: WalkTarget
  size: [number, number]
  /** 指针那一点：和落点不在一格时连一条虚线、画个叉 */
  from?: WalkTarget | null
  /** 从入口过来被挡：从入口连红虚线到指针，描红挡路的那件（道具编号；被自己挡住时为空串） */
  blockedBy?: string | null
  /** 放不下：画成红框 */
  bad?: boolean
}
/** 路线上的一个点；带 portal 时表示走到这里再开这扇门 */
export interface WalkStep {
  point: WalkTarget
  portal?: string
}
/** 拍素材时的一个机位：对准地面上哪一点（地图坐标）、画面横着看得见多宽（地图单位）、转角和俯角（度） */
export interface CameraShot {
  center: [number, number]
  width: number
  yaw: number
  pitch: number
}
/** 重演拍素材（town-2d 的 replay/director.ts）用的镜头：读写机位，看人画在哪，焦点对准谁 */
export interface DirectorCamera {
  shot(): CameraShot
  /** rise：对准的那一点放到画面中间以后再往上抬多少（视图单位） */
  setShot(shot: CameraShot, rise?: number): void
  /** 人此刻画在哪（地图坐标，画面平滑走动时比名册晚一点） */
  drawnAt(id: string): [number, number] | undefined
  /** 人身子中间离脚底多高（视图单位）：对准人时往上抬这么多，人整个在画面正中 */
  bodyRise(): number
  /** 景深的焦点对准谁（不画选中的光圈），他在屋里时屋顶掀开；null 交还给选中的人 */
  focus(id: string | null): void
  /** 镜头连续移动、不按地图像素吸附 */
  setSmooth(on: boolean): void
  /** 每画一帧之前调 hook（摆机位放在这里，和人物同一帧到位）；比化身、跟随的镜头优先，null 交还 */
  onFrame(hook: ((t: number) => boolean) | null): void
}
/** 共用外壳与地图之间的约定。面板用到的坐标是共用的 XZ 投影。 */
export interface GameMap {
  /** 地图会画天气：外壳才显示天气控件 */
  readonly weatherSupported?: boolean
  /** 选镇页赏景（不连世界的预览）：画面换成这个时刻（游戏分钟）和天气。只换画面，
   *  地面湿度、积雪几秒内跟上天气，不按游戏分钟累积 */
  setScenery?(minutes: number, weather: WeatherKind): void
  readonly avatarSupported?: boolean
  /** 化身可挑的几套外观；有就在进入对话框里挑外观，没有就挑颜色 */
  avatarLooks?(): AvatarLook[]
  setAvatarState?(state: AvatarState | null): void
  setAvatarActive?(active: boolean): void
  setAvatarPrompts?(prompts: AvatarPrompt[]): void
  onPromptClick?: ((id: string) => void) | null
  /** 点了地图空地：换算成米制目标点。只有后端负责移动的地图实现。 */
  onAvatarWalkTo?: ((target: WalkTarget) => void) | null
  /** 人、道具或门此刻的米制位置，用于走过去 */
  walkTargetOf?(kind: 'person' | 'prop', id: string): WalkTarget | undefined
  /** 绕开障碍的路线；走不到返回 null。没有实现时化身只会直线走。 */
  walkRoute?(from: WalkTarget, to: WalkTarget): WalkStep[] | null
  /** 两点之间的直线能不能走（同 walkRoute 的判断）；走路线时据此决定拐角能不能提前转 */
  walkSees?(from: WalkTarget, to: WalkTarget): boolean
  /** 键盘和摇杆的画面方向转成世界方向；点击路线已经是世界坐标，不经过这里。 */
  walkDirection?(direction: [number, number]): [number, number]
  /** 画出或清掉目的地标记 */
  setAvatarDestination?(target: WalkTarget | null): void
  /** 摆道具模式：开着时点空地交给 onPlaceClick（带屏幕坐标），不让化身走过去 */
  setPlacing?(placing: boolean): void
  onPlaceClick?: ((client: [number, number]) => void) | null
  /** 屏幕上一点落在哪个能放东西的地点；不在任何地点里返回 undefined */
  placeSpotAt?(client: [number, number]): PlaceSpot | undefined
  /** 描出指着或选中的地点；null 清掉 */
  setPlaceHighlight?(locale: string | null): void
  /** 在点过的位置画定位点；null 清掉 */
  setPlaceMarker?(target: WalkTarget | null): void
  /** 摆道具的格子（后端算的，每个能放东西的地点一份）：能放的地点挖亮、拉近后画出格子；null 清掉 */
  setPlaceGrids?(grids: PlaceGrid[] | null): void
  /** 画绿框；null 清掉 */
  setPlaceGhost?(ghost: PlaceGhost | null): void
  /** 镜头拉近到这个地点，格子看得清；at 是点的位置，地点太大装不下时对准它。avoid 是浮窗、提示条
   *  盖住的上边、右边、下边（CSS 像素），地点放进剩下那块。gentle 时这一点已经露在外面、格子也看得清就不动 */
  focusPlace?(
    locale: string,
    at?: WalkTarget,
    avoid?: { top?: number; right?: number; bottom?: number },
    gentle?: boolean
  ): void
  /** 格子此刻看不看得清（拉得够近） */
  placeDetail?(): boolean
  /** 拉近拉远让格子显示或藏起时通知 */
  onPlaceDetail?: ((detail: boolean) => void) | null
  /** 地图俯角（度）；只有 2D 立体场景有，其他地图不实现或返回 undefined */
  mapPitch?(): number | undefined
  /** 设俯角，立即重画并记到本机 */
  setMapPitch?(degrees: number): void
  /** 画质：像素比与后期效果，只影响本机画面 */
  setRenderQuality?(quality: Quality): void
  /** 失焦模糊：离焦点远的地方糊多少，只影响本机画面 */
  setDepthBlur?(level: DepthBlur): void
  /** 画面想告诉玩家的一句话（比如画质「自动」跑不动、降了一档），外壳放进事件栏 */
  onRenderNotice?: ((text: string) => void) | null
  /** 地图四边被面板盖住多少（CSS 像素）；跟随和「看这个人」会把目标放进露出来的那块 */
  setViewInsets?(insets: Insets): void
  /** 画面加载完（2D 的立体场景建好或退回平面图）；之前只有底色和地名 */
  ready?: Promise<void>
  /** 镇中心在哪（地图坐标）：最大的那片有名字的广场，没有广场时是全镇的正中间。选镇页的镜头对准它 */
  townHeart?(): [number, number]
  /** 拍一张全镇的小图当封面（JPEG 的 data URL）：机位临时摆成正面看全镇、不带失焦模糊，拍完摆回去，
   *  屏幕上看不出来。只有立体场景能拍，否则返回 undefined */
  cover?(width: number, height: number): string | undefined
  /** 此刻的画面（JPEG 的 data URL），宽不超过 maxWidth。进镇时拍下来，游戏页加载时垫在下面 */
  still?(maxWidth: number): string | undefined
  onVillagerClick: ((id: string) => void) | null
  /** 没在摆道具时点了空地（控制化身时 onAvatarWalkTo 同时收到走过去的目标） */
  onGroundClick?: (() => void) | null
  onPropClick: ((id: string) => void) | null
  setProps(props: PropView[], spatial?: PropCatalog['spatial']): void
  locateProp(id: string, locale: string): void
  /** 这件道具画在一摞书里（只有书合成一摞的地图有） */
  isBookPile?(id: string): boolean
  onReset(): void
  setSpeed(speed: number): void
  getScreenPos?(id: string): [number, number] | undefined
  /** 居民的屏幕范围；台词气泡据此摆在头顶并躲开旁人。没有实现时只按 getScreenPos 的一点估算 */
  getScreenBox?(id: string): ScreenBox | undefined
  getMemberPos(id: string): [number, number] | undefined
  /** 人此刻画在哪（地图坐标）；画面平滑走动时和名册位置差一点。没有实现时用 getMemberPos */
  getDrawnPos?(id: string): [number, number] | undefined
  /** 镜头跟着化身，每帧一次：dt 是离上一帧的毫秒数。window（默认）人走出画面中间的取景框才跟上，
   *  centre 把人慢慢挪回画面中间，snap 直接切过去（进门、出门）。返回这一帧挪了镜头 */
  followTo?(x: number, y: number, dt: number, how?: 'window' | 'centre' | 'snap'): boolean
  /** 地图每次画之前调 hook（镜头跟随放在这里，和人物、名字同一帧到位），hook 返回这一帧挪了镜头；
   *  地图不逐帧画时返回 false，调用方自己逐帧跑 */
  setFrameHook?(hook: ((t: number) => boolean) | null): boolean
  /** 下一帧就画，不等节拍 */
  requestFrame?(): void
  /** 「跟随中」：镜头每帧锁住这位村民，人始终在露出来那块的正中间，走动、拐弯、停下时平滑跟着；
   *  null 停止。玩家拖动地图时停止跟随并调 onStop。没有实现时外壳退回人快出画面才挪过去 */
  watch?(id: string | null, onStop?: () => void): void
  /** 本页发出的化身行走方向（世界方向）和此刻步速（米 / 秒）：地图照着它预先画自己的小人 */
  setAvatarMotion?(direction: [number, number], metresPerSecond: number): void
  /** 自己操控的人此刻画在哪（本地预测的米制位置，就是服务端马上要走到的地方）；不预测时为空 */
  avatarAt?(): WalkTarget | undefined
  /** 滚轮缩放的不动点（屏幕坐标）；null 或返回 undefined 时围着鼠标缩 */
  setZoomAnchor?(anchor: (() => [number, number] | undefined) | null): void
  panTo(x: number, y: number): void
  getViewBox(): number[]
  setViewBox(view: number[]): void
  setSelected(id: string | null): void
  /** 重演拍素材用的镜头；只有立体场景的地图有 */
  readonly director?: DirectorCamera
  update(entries: ResidentEntry[]): void
  dispose(): void
  handleMsg?(message: ServerMsg): void
  disconnect?(): void
}
