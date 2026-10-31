import type { AvatarLook, AvatarState } from './avatar/types'
import type { RosterMember, ServerMsg } from './protocol'
import type { PropView } from './props/types'
import type { Insets } from './mapView'
import type { Quality } from './quality'
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
  near: WalkTarget
}
/** 路线上的一个点；带 portal 时表示走到这里再开这扇门 */
export interface WalkStep {
  point: WalkTarget
  portal?: string
}
/** 共用外壳与地图之间的约定。面板用到的坐标是共用的 XZ 投影。 */
export interface GameMap {
  /** 地图会画天气：外壳才显示天气控件 */
  readonly weatherSupported?: boolean
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
  /** 地图俯角（度）；只有 2D 立体场景有，其他地图不实现或返回 undefined */
  mapPitch?(): number | undefined
  /** 设俯角，立即重画并记到本机 */
  setMapPitch?(degrees: number): void
  /** 画质：像素比与后期效果，只影响本机画面 */
  setRenderQuality?(quality: Quality): void
  /** 地图四边被面板盖住多少（CSS 像素）；跟随和「看这个人」会把目标放进露出来的那块 */
  setViewInsets?(insets: Insets): void
  /** 画面加载完（2D 的立体场景建好或退回平面图）；之前只有底色和地名 */
  ready?: Promise<void>
  onVillagerClick: ((id: string) => void) | null
  /** 没在摆道具时点了空地（控制化身时 onAvatarWalkTo 同时收到走过去的目标） */
  onGroundClick?: (() => void) | null
  onPropClick: ((id: string) => void) | null
  setProps(props: PropView[]): void
  locateProp(id: string, locale: string): void
  /** 这件道具画在一摞书里（只有书合成一摞的地图有） */
  isBookPile?(id: string): boolean
  onReset(): void
  setSpeed(speed: number): void
  getScreenPos?(id: string): [number, number] | undefined
  /** 居民的屏幕范围；台词气泡据此摆在头顶并躲开旁人。没有实现时只按 getScreenPos 的一点估算 */
  getScreenBox?(id: string): ScreenBox | undefined
  getMemberPos(id: string): [number, number] | undefined
  panTo(x: number, y: number): void
  getViewBox(): number[]
  setViewBox(view: number[]): void
  setSelected(id: string | null): void
  update(entries: ResidentEntry[]): void
  dispose(): void
  handleMsg?(message: ServerMsg): void
  disconnect?(): void
}
