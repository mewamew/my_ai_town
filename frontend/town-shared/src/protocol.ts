import type { WeatherKind, WeatherMode, WeatherView } from './weather/types'
import type { AvatarCommand, AvatarResultCode, AvatarState } from './avatar/types'
import type { ChatPresence, Speech, ChatSummary, ChatEntry } from './chat/types'
import type {
  ActionDescription,
  ContentMeta,
  Definition,
  Instance,
  PropCatalog,
  PropResultPreview,
} from './props/types'
import type { WeatherCode } from './weather/types'
// crates/protocol 的前端镜像：命令与回包在此集中维护。
import type {
  NotebookQuery,
  NotebookDetailQuery,
  NotebookView,
  NotebookDetail,
} from './memory/protocol'
// ---- 线上类型（protocol crate 的镜像，手写保持极小） ----

export type At =
  | { kind: 'station'; station: string }
  | { kind: 'transit'; elapsed: number; total: number; toward: string }
  | { kind: 'offstage' }
  | { kind: 'free'; space: string; position: [number, number]; elevation?: number; yaw?: number }

export type NeedBand = 'steady' | 'mild' | 'urgent' | 'collapse'
/** 四项身体需求；判断用它，need 是显示用的名字 */
export type NeedKind = 'fullness' | 'energy' | 'water' | 'health'
export interface NeedStateView {
  kind: NeedKind
  need: string
  value: number
  band: NeedBand
  text: string
}

export interface PlanView {
  current: string
  upcoming: string[]
}

/// 一次规划的触发原因；标签按 kind 决定，纯文字来源直接显示 text
export interface TriggerInfo {
  kind: 'queue_low' | 'notice' | 'activity_failed' | 'text'
  at: number | null
  action: string | null
  text: string
}
/// 最近一次决定时的自述想法：text 全文、line 第一句（心声，供气泡）
export interface ThoughtView {
  sim_minutes: number
  trigger_info: TriggerInfo
  text: string
  line: string
  clock: string
}
interface ReceiptView {
  sim_minutes: number
  clock: string
  text: string
  /** 死亡这类生命记录的提示卡细节 */
  alert?: Alert
}
/** 身体状况的种类 */
type ConditionKind = 'injury' | 'illness' | 'poison'
/** 需要提示卡的事件：前端按种类写标题和说明，不解析正文 */
export type Alert =
  /** 健康耗尽死亡；shortages、conditions 是当时正在造成损害的来源，其他死因时为空；
   *  killed 是遇害时的凶手和伤口 */
  | { kind: 'death'; shortages: NeedKind[]; conditions: ConditionKind[]; killed?: Killing }
  | { kind: 'condition'; condition: ConditionKind }
  | { kind: 'critical' }
  | { kind: 'hold'; pause: PauseKind; reason: string; cause?: HoldCause; provider?: string }
/** 世界日志一行的种类：出发与到达、模型请求台账，其余是世界里发生的事 */
export type EventKind = 'world' | 'movement' | 'model'
/** 日志说的是谁：编号与当时的名字 */
export interface EventActor {
  id: string
  name: string
}
/** 遇害：谁下的手、留下什么伤 */
export interface Killing {
  by: EventActor
  wound: string
}

/// 日志里的一天：世界的执行记录、当天的想法、他次日写的「昨天」
export interface DiaryDay {
  label: string
  receipts: ReceiptView[]
  thoughts: ThoughtView[]
  summary?: string
  current: boolean
}

/** 背包投影：kernel inventory_view 的输出 */
export interface InventoryView {
  capacity: number
  used: number
  slots: InventorySlot[]
}
export interface InventorySlot {
  items: string[]
  name: string
  definition: string | null
  quantity: number
  actions: ActionDescription[]
  readable: ContentMeta | null
}
/** 处所与处所内的位置 */
export interface Locus {
  locale: string
  at: At
}

/** 名册成员的种类；现在只有村民 */
type MemberKind = 'resident' | 'avatar'
/** 当前活动是否有进度语义：移动与定时活动 advancing，站立、旁听、空等 placeholder */
type ActivityKind = 'advancing' | 'placeholder'
/** 精确导航下的移动阶段 */
type MovementPhase = 'travel' | 'approach'
/** 动作属于哪一类；判断用它，verb 是显示用的动作词 */
export type VerbKind = 'goto' | 'stay' | 'prop' | 'interaction' | 'inventory'

/// 名册里的一位在场人物
export interface RosterMember {
  appearance?: Appearance
  chat?: ChatPresence
  speech?: Speech
  /** 背包投影 */
  inventory: InventoryView
  movement?: {
    route: string
    navigation_revision: number
    destination_station: string
    phase: MovementPhase
  }
  body?: BodyView
  id: string
  name: string
  kind: MemberKind
  at: At
  verb: string
  verb_kind: VerbKind
  activity: ActivityKind
  needs?: NeedStateView[]
  plan: PlanView
  thought?: ThoughtView
  resident_agent?: ResidentAgentView
}

interface ActionResultView {
  action_id: string
  group_id: string
  prop_id: string | null
  verb: string
  started_at: number | null
  ended_at: number
  status: 'succeeded' | 'failed' | 'interrupted' | 'cancelled'
  changes: string[]
  reason: string | null
  event_ids: number[]
  verb_kind: VerbKind
}
/** 会话停止的原因类别：额度用尽、故障、回复接连过时让全镇暂停；等模型不算出错，模型能用了自动接着走 */
export type PauseKind = 'fault' | 'budget' | 'stale' | 'no_model'
/** 故障暂停的原因类别，提示卡据此给修复按钮；非模型原因是 other */
export type HoldCause =
  'auth' | 'network' | 'balance' | 'model' | 'rejected' | 'reply' | 'context' | 'other'
/** 村民此刻的状态；文案见 labels.ts */
export type AgentState =
  | 'dead'
  | 'fault'
  | 'budget'
  | 'stale'
  | 'rescue'
  | 'chatting'
  | 'interacting'
  | 'reflecting'
  | 'thinking'
  | 'acting'
  | 'waiting'
  | 'undecided'
  | 'manual'
  | 'unconfigured'
  | 'no_model'
export type GoalStatus = 'active' | 'paused' | 'completed' | 'abandoned' | 'failed'
export type NoteStatus = 'candidate' | 'supported' | 'rejected'
export type MemoryKind = 'episode' | 'recognition' | 'experience'
export type MemoryStatus = 'active' | 'candidate' | 'superseded'
export type EvidenceSource = 'observed' | 'reported' | 'inferred'
export type InteractionStatus =
  'offered' | 'running' | 'succeeded' | 'declined' | 'cancelled' | 'expired' | 'interrupted'
export type RequestKind = 'life' | 'reflection' | 'chat'
export type RequestStatus =
  'in_flight' | 'adopted' | 'format_retry' | 'outdated' | 'failed' | 'dropped' | 'controlled'

/** 世界事件的种类；旧存档里的 job 读入时按 observation */
type FactKind = 'observation' | 'readable' | 'notice' | 'action' | 'speech' | 'interaction'
/** 村民经历过的一条世界事件 */
interface WorldFact {
  event_id: number
  at: number
  kind: FactKind
  text: string
  objects: string[]
  action_id: string | null
  /** 读到的内容身份；只有阅读事件有 */
  readable?: {
    id: string
    version: string
    previously_read: boolean
    previous_version: string | null
  }
}
export interface ResidentAgentView {
  state: AgentState
  reason: string
  daily_calls: number
  daily_limit: number
  daily_tokens: number
  daily_input_tokens: number
  daily_cache_hit_tokens: number
  /** 生活决策回复累计数与其中因世界变化过时、未执行的数 */
  replies: number
  stale_replies: number
  goals: {
    id: string
    title: string
    status: GoalStatus
    reason: string
    commitment: string
    next_steps: string[]
    updated_at: number
  }[]
  results: ActionResultView[]
  interactions: {
    id: string
    title: string
    status: InteractionStatus
    participants: string[]
    result: string
  }[]
  memories: {
    memory_id: number
    kind: MemoryKind
    source: EvidenceSource
    status: MemoryStatus
    confidence: number
    text: string
    at: number
    replaces: number[]
    events: WorldFact[]
  }[]
}

/** 小镇当前使用的服务商与模型 */
export interface ActiveModelChoice {
  provider: string
  model: string
}
export interface ModelChoice {
  provider: string
  model: string
}
export interface NeedsTuning {
  fullness_decay: number
  energy_decay: number
  labor_rate: number
  voiced: number
  ring: number
  ring_reset: number
  collapse: number
}
export interface ProviderView {
  id: string
  name: string
  base_url: string
  key_mask: string
}
/** 外观：地图上的区分标记和像素小人的长相，旧存档可带形象编号 */
export interface Appearance {
  marker: string
  color: string
  /** 旧形象编号，仅用于兼容读写；HD-2D 不读取模型资源 */
  profile?: string
  /** 捏出来的像素小人；没有时按模板编号挑长相（预制村民固定，自定义的按编号随机） */
  look?: VillagerLook
}
export type HairStyle =
  | 'short'
  | 'spiky'
  | 'split'
  | 'crop'
  | 'bob'
  | 'long'
  | 'parted'
  | 'bun'
  | 'ponytail'
  | 'twintail'
  | 'afro'
  | 'mohawk'
  | 'bald'
  | 'twin_buns'
  | 'curls'
  /** 大葱头：一把叶子似的头发往上竖 */
  | 'scallion'
  /** M 刘海：齐耳短发，刘海下沿是锯齿的 M */
  | 'm_bangs'
  /** M 刘海长发：垂到腰，耳边往外翘 */
  | 'm_long'
export type Outfit =
  | 'jacket'
  | 'coat'
  | 'cardigan'
  | 'dress'
  | 'apron'
  | 'book'
  | 'suit'
  | 'overalls'
  | 'tee'
  | 'hoodie'
  | 'robe'
  | 'clown'
  | 'space'
  | 'armor'
  | 'skeleton'
  | 'tiger_skirt'
  | 'bellyband'
  | 'kasaya'
  | 'bikini'
  | 'swim_trunks'
  | 'general'
/** 草帽以外头上戴的：耳朵、角、触角、光环、王冠、几种帽子，以及紧箍、猪耳朵、佛光 */
export type Headwear =
  | 'cat_ears'
  | 'bunny_ears'
  | 'horns'
  | 'antennae'
  | 'halo'
  | 'crown'
  | 'top_hat'
  | 'wizard_hat'
  | 'chef_hat'
  | 'circlet'
  | 'pig_ears'
  | 'aureole'
  | 'scholar_cap'
  | 'topknot_crown'
  | 'feather_crown'
  | 'official_hat'
/** 脸上戴的 */
export type FaceGear =
  | 'glasses'
  | 'sunglasses'
  | 'eye_patch'
  | 'clown_nose'
  | 'monkey_face'
  | 'pig_snout'
  | 'forehead_dot'
/** 络腮胡以外的胡子：长须、虬髯、山羊胡 */
export type BeardStyle = 'long' | 'bushy' | 'goatee'
/** 手里拿的：羽扇和几样兵器 */
export type HeldItem =
  'fan' | 'guandao' | 'snake_spear' | 'spear' | 'halberd' | 'golden_staff' | 'rake'
/** 捏人：发型、衣服、颜色（#rrggbb）、配饰和衣服上 4×4 的花纹；领口、围裙、腰带、发饰缺省用默认色或点缀色 */
export interface VillagerLook {
  hair: HairStyle
  outfit: Outfit
  hair_color: string
  /** 发梢颜色：有这一项头发从发根渐变到它 */
  hair_tip?: string
  eye_color: string
  skin: string
  top: string
  bottom: string
  accent: string
  collar?: string
  apron?: string
  belt?: string
  ornament?: string
  /** 头巾颜色；有这一项就戴头巾 */
  headband?: string
  /** 草帽；和 headwear 只能有一个 */
  hat?: boolean
  ahoge?: boolean
  clip?: boolean
  beard?: boolean
  headwear?: Headwear
  face?: FaceGear
  /** 络腮胡以外的胡子；和 beard 只能有一样 */
  beard_style?: BeardStyle
  held?: HeldItem
  pattern?: LookPattern
}
/** 衣服上的花纹：4 行 × 4 个字符，# 是花纹色，. 露出衣服原色；平铺在上衣或下装上 */
export interface LookPattern {
  on: 'top' | 'bottom'
  color: string
  rows: string[]
}
/** 村民模板的可编辑字段：都是文字倾向，不产生资源、职位或权限 */
export interface TemplateFields {
  name: string
  age: string
  gender: string
  intro: string
  tags: string[]
  personality: string
  speech: string
  background: string
  /** 开局处境：来到这里时真实身处的情况，按已经发生的事写给模型；旧模板没有 */
  situation?: string
  drives: string
  interests: string
  occupation: string
  appearance: Appearance
}
export interface ResidentTemplate {
  template_id: string
  version: number
  builtin: boolean
  archived: boolean
  fields: TemplateFields
}
export interface TemplateCard {
  template_id: string
  version: number
  builtin: boolean
  archived: boolean
  name: string
  intro: string
  tags: string[]
  appearance: Appearance
  status: TemplateStatus
  resident_id?: string
}
/** 模板在当前世界里的状态：可加入 / 已在村中 / 已归档 */
export type TemplateStatus = 'available' | 'joined' | 'archived'
export type LibraryKind = 'all' | 'builtin' | 'custom'
export interface LibraryFilter {
  query?: string
  kind?: LibraryKind
  include_archived?: boolean
}
/** 当前世界里一位居民的登记（不含人设全文）；joined_at 缺省表示原有居民 */
export interface ResidentRegistration {
  id: string
  name: string
  home: string | null
  home_name: string
  joined_at?: number
  joined_clock?: string
  template_id?: string
  template_version?: number
  appearance: Appearance
  /** 这位村民用的模型；还没选时不写 */
  model?: ModelChoice
}
interface HomeView {
  locale: string
  name: string
  occupant?: string
}
export interface PopulationView {
  world_id: string
  revision: number
  residents: ResidentRegistration[]
  homes: HomeView[]
  entry_name?: string
}
export interface JoinPreview {
  ok: boolean
  problems: string[]
  template_id: string
  template_version: number
  name: string
  home?: string
  home_name?: string
  entry_name: string
  clock: string
  persona_chars: number
  free_homes: HomeView[]
}
export interface JoinOutcome {
  op_id: string
  ok: boolean
  message: string
  resident_id?: string
  name?: string
  home?: string
  joined_at?: number
  revision: number
}
/** 额度用尽、故障或回复接连过时导致的全镇暂停原因；修改额度或检查服务后点开始继续 */
export interface WorldHold {
  resident_id: string
  resident: string
  kind: PauseKind
  reason: string
  cause: HoldCause
  /** 这位村民用的模型服务（显示名）；没有绑定时不写 */
  provider?: string
}
/** 一项额度的取值范围（闭区间）；max 为 null 表示没有上限 */
export interface LimitRange {
  min: number
  max: number | null
}
/** 各项额度的取值范围，由后端的校验规则给出；两项之间的约束由后端校验后回报 */
export type AgentLimitRanges = Record<keyof AgentLimits, LimitRange>
/** 运行中可改的调用额度；并发与上下文窗口不在其中 */
export interface AgentLimits {
  calls_per_wake: number
  calls_per_day: number
  tokens_per_day: number
  total_calls: number
  total_tokens: number
  stale_replies_before_pause: number
  model_failures_before_pause: number
}
export interface ResidentUsage {
  id: string
  name: string
  daily_calls: number
  daily_tokens: number
  daily_input_tokens: number
  daily_cache_hit_tokens: number
  replies: number
  stale_replies: number
  in_flight: boolean
  paused?: string
}
/** 消耗页汇总：今天按各人当日账合计，累计按运行时总账；含在途预留 */
export interface UsageSummary {
  today_calls: number
  today_tokens: number
  today_input_tokens: number
  today_cache_hit_tokens: number
  lifetime_calls: number
  lifetime_tokens: number
  lifetime_input_tokens: number
  lifetime_cache_hit_tokens: number
  calls_per_day: number
  tokens_per_day: number
  total_calls: number
  total_tokens: number
  in_flight: number
}
/** 一次模型请求的台账行；只有村民的生活决策与记忆整理 */
export interface RequestView {
  id: number
  resident_id: string
  resident: string
  kind: RequestKind
  clock: string
  sim_minutes: number
  sent_at: number
  reserved_tokens: number
  estimated_tokens: number
  status: RequestStatus
  detail: string
  latency_ms?: number
  input_tokens?: number
  output_tokens?: number
  cache_hit_tokens?: number
}
export interface AgentUsage {
  lifetime_calls: number
  lifetime_tokens: number
  residents: ResidentUsage[]
}
/** 世界级生理开关：关掉的一项数值冻结，不限制活动，不进入村民观察。 */
export interface PhysiologySwitches {
  fullness: boolean
  energy: boolean
  water: boolean
  health: boolean
  /** 天气影响身体：露天淋雨雪额外消耗精力，淋久了生病；旧存档没有，按关闭 */
  weather?: boolean
}
export interface WorldSettingsState {
  world_id: string
  revision: number
  worldview: string
  ready: boolean
  mock: boolean
  provider: string
  model: string
  persistent: boolean
  max_chars: number
  physiology: PhysiologySwitches
}

export type ServerMsg =
  | { type: 'avatar_state'; state: AvatarState }
  | {
      type: 'avatar_result'
      request_id: string
      ok: boolean
      code: AvatarResultCode
      message: string
      state: AvatarState
    }
  /** 连接后的第一条：客户端据此核对进的是哪个小镇、哪版地图；不是管理进程启动的小镇没有 town_id */
  | { type: 'world_identity'; town_id: string | null; map_hash: string }
  | {
      type: 'chat_history'
      resident: string
      request_id: string
      chat_id: string | null
      offset: number
      total: number
      chats: ChatSummary[]
      entries: ChatEntry[]
    }
  | {
      type: 'weather_saved'
      request_id: string
      world_id: string
      ok: boolean
      code: WeatherCode | null
      message: string
      environment: WeatherView | null
    }
  | { type: 'world_settings'; state: WorldSettingsState }
  | { type: 'world_settings_saved'; request_id: string; ok: boolean; message: string }
  | { type: 'props'; catalog: PropCatalog }
  | {
      type: 'prop_result'
      request_id: string
      ok: boolean
      message: string
      preview: PropResultPreview
    }
  | {
      type: 'roster'
      environment?: WeatherView
      sim_minutes: number
      clock: string
      /** 选定的速度：正常速度的倍数，1 是正常速度（村民在画面上像散步），0 为暂停 */
      speed: number
      /** 这一拍实际的推进速度，同样以正常速度为 1：大家都在做一件还要好一阵的事时自动快进，比 speed 快 */
      pace: number
      period: string
      holds?: WorldHold[]
      locales: { locale: string; members: RosterMember[] }[]
    }
  /** 世界日志一行：text 给人读，kind、actor、alert 给前端判断 */
  | {
      type: 'event'
      sim_minutes: number
      clock: string
      text: string
      kind: EventKind
      actor?: EventActor
      alert?: Alert
    }
  | {
      type: 'model_config'
      active: ActiveModelChoice | null
      providers: ProviderView[]
      /** 内置模型的新版是小镇开着时下好的，推理服务还在用旧的；restart_builtin_model 换上 */
      builtin_stale: boolean
    }
  | { type: 'config_saved'; request_id: string; ok: boolean; message: string }
  | {
      type: 'model_test_result'
      request_id: string
      provider: string
      ok: boolean
      message: string
      latency_ms: number
    }
  | {
      type: 'agent_config'
      resident_id: string
      resident: string
      persona: string
      tuning: NeedsTuning
      /** 健康条上的三条分界：危重、危险、受损 */
      health_marks: [number, number, number]
      model_binding?: ModelChoice
    }
  | { type: 'agent_saved'; request_id: string; ok: boolean; message: string }
  /**
   * 通用错误：命令无法执行、格式错误、读取失败或保存失败。request_id 是引起错误的命令自带的编号
   * （加入小镇是操作编号）；周期存盘失败这类不是由命令引起的错误没有。
   */
  | { type: 'error'; request_id?: string; message: string }
  | { type: 'world_reset'; clock: string }
  | { type: 'diary'; resident: string; days: DiaryDay[] }
  | {
      type: 'notebook'
      resident: string
      request_id: string
      notebook: NotebookView | null
      error: string | null
    }
  | {
      type: 'notebook_detail'
      resident: string
      request_id: string
      detail: NotebookDetail | null
      error: string | null
    }
  | { type: 'agent_limits'; limits: AgentLimits; ranges: AgentLimitRanges; usage: AgentUsage }
  | { type: 'population'; population: PopulationView }
  | {
      type: 'resident_appearance_saved'
      request_id: string
      resident_id: string
      ok: boolean
      message: string
      population: PopulationView
    }
  | { type: 'usage'; summary: UsageSummary; residents: ResidentUsage[]; requests: RequestView[] }
  | { type: 'resident_library'; templates: TemplateCard[]; custom_root: string }
  | { type: 'resident_template'; template?: ResidentTemplate; persona: string; error?: string }
  | {
      type: 'template_saved'
      request_id: string
      ok: boolean
      message: string
      template?: ResidentTemplate
    }
  | { type: 'template_persona'; persona: string; error?: string }
  | {
      type: 'template_generated'
      request_id: string
      ok: boolean
      message: string
      fields?: TemplateFields
    }
  | { type: 'join_preview'; preview: JoinPreview }
  | { type: 'resident_joined'; outcome: JoinOutcome }
  | { type: 'join_result'; op_id: string; outcome?: JoinOutcome }

/** 意图的结束谓词；线上取值就是中文 */
type UntilPredicate = '天亮' | '天黑'
export interface IntentDraft {
  verb: string
  locale?: string
  target?: string
  duration_minutes?: number
  until?: UntilPredicate
}

export interface ProviderConfig {
  id: string
  name: string
  base_url: string
}
export type ClientMsg =
  | {
      type: 'avatar'
      world_id: string
      request_id: string
      epoch: string
      sequence: number
      command: AvatarCommand
    }
  | {
      type: 'avatar_input'
      world_id: string
      epoch: string
      sequence: number
      navigation_revision: number
      direction: [number, number]
      pose?: {
        actor: string
        locale: string
        space: string
        position: [number, number, number]
        yaw: number
      }
    }
  | {
      type: 'get_chat_history'
      resident: string
      request_id: string
      chat_id?: string
      offset?: number
    }
  | { type: 'content'; request_id: string; world_id: string; command: ContentCommand }
  | {
      type: 'set_weather'
      world_id: string
      request_id: string
      expected_revision: number
      mode: WeatherMode
      kind?: WeatherKind
    }
  | { type: 'get_world_settings' }
  | {
      type: 'set_worldview'
      request_id: string
      world_id: string
      expected_revision: number
      text: string
    }
  | {
      type: 'set_physiology'
      request_id: string
      world_id: string
      expected_revision: number
      switches: PhysiologySwitches
    }
  | { type: 'get_props' }
  | {
      type: 'validate_prop' | 'save_prop'
      request_id: string
      definition: Definition
    }
  | { type: 'remove_prop'; request_id: string; world_id: string; id: string }
  | {
      type: 'place_prop'
      request_id: string
      world_id: string
      instance: Instance
      /** 在地图上点的位置（行走坐标，米）：道具落在它附近的空位 */
      near?: { space: string; position: [number, number] }
    }
  | { type: 'set_speed'; request_id: string; speed: number }
  | { type: 'get_model_config' | 'get_agent_limits' | 'get_population' | 'get_usage' }
  | { type: 'reset_world'; request_id: string }
  | { type: 'get_resident_library'; filter: LibraryFilter }
  | {
      type: 'set_resident_appearance'
      request_id: string
      world_id: string
      expected_revision: number
      resident_id: string
      appearance: Appearance
    }
  | { type: 'get_resident_template'; template_id: string }
  | {
      type: 'save_resident_template'
      request_id: string
      template_id?: string
      expected_version?: number
      fields: TemplateFields
    }
  | {
      type: 'archive_resident_template'
      request_id: string
      template_id: string
      expected_version: number
      archived: boolean
    }
  | { type: 'preview_template_persona'; fields: TemplateFields }
  | { type: 'generate_resident_template'; request_id: string; brief: string }
  | { type: 'preview_resident_join'; template_id: string; name?: string; home?: string }
  | {
      type: 'join_resident'
      op_id: string
      world_id: string
      template_id: string
      template_version: number
      name: string
      home?: string
      /** 入住时就定下用哪个模型思考；不带时先住下，选好模型再行动 */
      model?: ModelChoice
    }
  | { type: 'get_resident_join_result'; world_id: string; op_id: string }
  | { type: 'get_agent_config' | 'get_diary'; resident?: string }
  | { type: 'get_notebook'; resident: string; request_id: string; query: NotebookQuery }
  | {
      type: 'get_notebook_detail'
      resident: string
      request_id: string
      query: NotebookDetailQuery
    }
  | {
      type: 'set_model_config'
      request_id: string
      active: ActiveModelChoice | null
      providers: ProviderConfig[]
      keys?: { provider: string; api_key: string }[]
    }
  | { type: 'set_resident_model'; request_id: string; resident: string; model: ModelChoice }
  | { type: 'restart_builtin_model'; request_id: string }
  | {
      type: 'test_model_connection'
      request_id: string
      provider: ProviderConfig
      model: string
      api_key?: string
    }
  | { type: 'set_persona'; request_id: string; resident: string; text: string }
  | { type: 'set_agent_limits'; request_id: string; limits: AgentLimits }

type Life = 'alive' | 'dead'
/** 生命历史里一条记录的来源 */
type BodyEventKind =
  'pressure' | 'prop' | 'death' | 'ability' | 'experiment' | 'condition' | 'cure' | 'revive'
export interface BodyView {
  revision: number
  life: Life
  conditions: {
    kind: 'injury' | 'illness' | 'poison'
    severity: number
    since: number
    source: string
  }[]
  can_decide: boolean
  can_move: boolean
  can_labor: boolean
  limitation: string
  causes: string[]
  exposure: number[]
  history: { at: number; kind: BodyEventKind; source: string; text: string }[]
  /** 遇害者身上的伤口；活人和其他死因没有 */
  wound?: string
}
export type ContentCommand =
  | { operation: 'detail'; id: string }
  | {
      operation: 'create'
      id: string
      locale: string
      title: string
      author: string
      text: string
      board?: string
    }
  | {
      operation: 'revise'
      id: string
      expected_version: number
      title: string
      author: string
      text: string
    }
  | { operation: 'withdraw'; id: string; expected_version: number }
