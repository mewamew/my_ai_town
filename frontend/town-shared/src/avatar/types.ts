import type {
  Appearance,
  BodyView,
  GoalStatus,
  IntentDraft,
  InventoryView,
  Locus,
  NeedStateView,
  InteractionStatus,
} from '../protocol'
import type { ActionDescription, ContentText } from '../props/types'
import type { ChatEntry } from '../chat/types'

export type InventoryOperation =
  | { operation: 'pick_up' | 'drop'; items: string[] }
  | { operation: 'store' | 'retrieve'; items: string[]; container: string }
  | { operation: 'take'; source: string; action: string; quantity: number }
/** 玩家的一个动作（crates/protocol ActionDraft）：动作词、可选的道具、接受者、背包操作与写作内容 */
export interface PlayerAction {
  intent: IntentDraft
  prop_id?: string
  recipient?: string
  inventory?: InventoryOperation
  writing?: { title: string; text: string }
}
/** 双方互动的种类：交谈、赠予物品、招待用餐、同行（leader 带路，locale 是说好的目的地）、
 *  约定（at 是约好的世界分钟，locale 是见面的地方）、亲近（牵手、依偎、拥抱） */
export type InteractionKind =
  | { kind: 'talk' }
  | { kind: 'give'; items: string[] }
  | { kind: 'serve'; prop_id: string; verb: string }
  | { kind: 'walk'; leader: string; locale?: string }
  | { kind: 'appointment'; locale: string; at: number }
  | { kind: 'touch'; gesture: 'hold_hands' | 'lean' | 'hug' }
export type InteractionCommand =
  | { operation: 'offer'; partner_id: string; interaction: InteractionKind; message: string }
  | { operation: 'reply'; interaction_id: string; accept: boolean; message: string }
  | { operation: 'cancel' | 'listen'; interaction_id: string }
  | { operation: 'join' | 'leave' | 'decline'; interaction_id: string; message: string }
  | { operation: 'say'; interaction_id: string; message: string; to?: string }
  | {
      operation: 'propose'
      interaction_id: string
      interaction: InteractionKind
      message: string
      to?: string
    }
  | { operation: 'accept'; interaction_id: string; message: string; locale?: string }
/** 交谈里等人回答的提议（现在是一起走） */
export interface ChatProposal {
  by: string
  to: string
  interaction: InteractionKind
  at: number
}
/** 化身神力：复活死者、治好伤病、补满饱腹精力水分 */
export type MiracleKind = 'revive' | 'heal' | 'refill'
export type AvatarCommand =
  | { kind: 'view' | 'heartbeat' | 'leave' | 'stop' }
  | { kind: 'enter' | 'profile'; name: string; appearance: Appearance }
  | { kind: 'possess'; resident: string }
  | { kind: 'resume'; token: string }
  | { kind: 'portal'; id: string }
  | { kind: 'action'; revision: number; action: PlayerAction }
  | { kind: 'interact'; revision: number; command: InteractionCommand }
  | { kind: 'request_turn'; chat_id: string; revision: number }
  | { kind: 'miracle'; revision: number; recipient: string; miracle: MiracleKind }
/** 化身命令回执的结果类别（crates/protocol AvatarResultCode） */
export type AvatarResultCode =
  | 'ok'
  | 'rejected'
  | 'wrong_world'
  | 'save_failed'
  | 'not_ready'
  | 'control_lost'
  | 'conflict'
  | 'paused'
  | 'busy'
  | 'occupied'
  | 'world'
/** 把一组字段标成不出现：让联合类型的每个成员都能读这些字段，读到的是 undefined */
type Absent<T> = { [K in keyof T]?: undefined }
interface InteractionBase {
  id: string
  initiator: string
  partner: string
  locale: string
  kind: InteractionKind
  message: string
  reply: string | null
  reason: string | null
  status: InteractionStatus
  expires_at: number
  can_speak: boolean
  can_request_turn: boolean
  /** 受邀村民的模型回应格式出错时给邀请者看的说明 */
  response_error?: string
}
/** 聊天：本人听到的台词、成员与轮次，以及等人回答的提议 */
interface ChatFields {
  entries: ChatEntry[]
  members: string[]
  turn: string | null
  proposal?: ChatProposal
}
/** 赠予、招待用餐等双方互动的完整记录 */
interface PairFields {
  accepted: boolean | null
  changes: string[]
  created_at: number
  duration_minutes: number
  ended_at: number | null
  event_ids: Record<string, number[]>
  started_at: number | null
}
export type AvatarInteraction =
  | (InteractionBase & ChatFields & Absent<PairFields>)
  | (InteractionBase & PairFields & Absent<ChatFields>)
export interface AvatarProp {
  id: string
  name: string
  /** 公告栏：站在跟前可以直接张贴公告 */
  bulletin_board: boolean
  portable: boolean
  carried: boolean
  storage_slots: number
  actions: ActionDescription[]
  contents: { id: string; name: string; definition: string | null }[]
}
/** 控制目标本人 */
export interface AvatarActor {
  id: string
  name: string
  appearance: Appearance
  present: boolean
  revision: number
  locus: Locus
  body: BodyView | null
  needs: NeedStateView[]
  activity: string
  remaining: string
  busy: boolean
  inventory: InventoryView
}
/** 有控制目标时的完整视图 */
interface PresentView {
  actor: AvatarActor
  awaiting_arrival: boolean
  can_drop: boolean
  /** 最近三个动作的变化与失败原因 */
  feedback: string[]
  interactions: AvatarInteraction[]
  /** 化身神力开着，控制的又是化身本人：能对够得着的人施展 */
  miracles: boolean
  mode: 'avatar' | 'possession'
  navigation_revision: number
  /** 够得着的人；聊不了时 busy 写着原因 */
  nearby: {
    id: string
    name: string
    available: boolean
    can_talk: boolean
    activity: string
    busy?: string
    /** 已经死了 */
    dead?: true
  }[]
  /** 附近还说不上话的人：离得远（米），或已经够近、只是隔着东西 */
  approach?: { id: string; name: string; distance: number; blocked: boolean }[]
  /** 附近进行中的交谈；带 leader 的是路过的同行，加入就是跟着走 */
  nearby_chats: { id: string; locale: string; members: string[]; leader?: string }[]
  portals: { id: string; label: string }[]
  props: AvatarProp[]
  reading: ContentText | null
  supported: boolean
  units: number
}
type PresentOnly = Omit<PresentView, 'actor' | 'supported' | 'units'>
/**
 * 本连接能看到的化身视图：有控制目标、支持化身但还没有目标、地图不支持化身，
 * 以及目标正被另一个页面控制（只说明地图支持化身）。
 */
type AvatarSight =
  | PresentView
  | (Absent<PresentOnly> & { actor: null; supported: boolean; units: number })
  | (Absent<PresentOnly> & { actor?: undefined; supported: boolean; units?: undefined })
  | (Absent<PresentOnly> & { actor: null; supported: boolean; units?: undefined })
/** 本连接持有控制租约时才有：控制代次、断线恢复凭据、已处理到的操作序号 */
type Lease =
  | { epoch: string; resume_token: string; sequence: number }
  | Absent<{
      epoch: string
      resume_token: string
      sequence: number
    }>
/** 发给一个连接的化身状态：内核的化身视图，加上 host 的世界编号、速度、控制与位置上报回执 */
export type AvatarState = AvatarSight &
  Lease & {
    world_id: string
    /** 化身走路的速度：模拟分钟 / 现实秒（每分钟走 12 米），0 为暂停 */
    speed: number
    /** 本连接持有控制且在线 */
    controlled: boolean
    /** 化身或附身目标已被某个连接控制 */
    occupied: boolean
    /** 附身时本人最近的日志，新的在前 */
    recent?: { at: number; text: string }[]
    /** 附身时本人的目标 */
    goals?: { status: GoalStatus; text: string }[]
    /** 三维地图由前端上报位置；二维地图没有这个键 */
    client_positions?: true
    /** 玩家操控的人的步速：每模拟分钟多少米、按住奔跑（Shift）时再乘的倍数；没有行走地图时没有这个键 */
    walk?: { metres_per_minute: number; sprint_factor: number }
    /** 三维地图且本连接持有租约时：最近处理的位置上报序号与被拒原因 */
    position_error?: string | null
    position_sequence?: number
  }
/** 化身可挑的一套外观：颜色写进 Appearance.color，头像是这套外观的正面像 */
export interface AvatarLook {
  color: string
  portrait: string
}
