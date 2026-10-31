import type { SpatialProp } from '../spatial'
import type { Locus } from '../protocol'
type Vec3 = [number, number, number]
export type BodyNeed = 'energy' | 'fullness' | 'water' | 'health'
type ConditionKind = 'injury' | 'illness' | 'poison'
export type InstantEffect =
  | { kind: 'restore'; need: BodyNeed; amount: number }
  | { kind: 'apply_condition'; condition: ConditionKind; severity: number }
  | { kind: 'cure_condition'; condition: ConditionKind }
  | { kind: 'revive'; values: [number, number, number, number]; clear_conditions: boolean }
  /** 伤人：立即扣对方健康，扣到 0 就是遇害；wound 是留在身上的伤 */
  | { kind: 'harm'; amount: number; wound: string }
  | { kind: 'give_item'; item: Definition; count: number }
  | { kind: 'place_prop'; prop: Definition }
  | { kind: 'chance'; percent: number; effects: InstantEffect[]; miss?: string }
  | {
      kind: 'schedule'
      key: string
      after_minutes: number
      text: string
      place?: { locale?: string; prop: Definition; lasts_minutes?: number; leave_text?: string }
    }
  | { kind: 'depart'; text: string }
/** 动作的物品前提：开始和完成时随身要带够；consume 的完成时用掉 */
export interface Requirement {
  item: string
  name: string
  count: number
  consume?: boolean
}
export type Effect =
  | { kind: 'restore_need'; need: BodyNeed; per_minute: number; pause_decay: boolean }
  | { kind: 'labor' }
/** 动作完成时怎么结算 */
export type Completion =
  'activity' | 'sleep' | 'meal' | 'read_book' | 'read_bulletin' | 'write_book' | 'research'
/** 开始动作前要满足的条件：供餐时段、在自己家 */
export type ActionCondition = 'meal_window' | 'own_home'
/** 道具定义里的动作（kernel props::Action）；取默认值的字段不输出 */
export interface Action {
  consumes_item?: boolean
  portion_name?: string
  id: string
  label: string
  duration_minutes: number
  requires?: Requirement[]
  during: Effect[]
  completion: Completion
  conditions: ActionCondition[]
  on_complete?: InstantEffect[]
  supply?: { initial: number; cost: number; restock?: { amount: number; max: number } }
  recipient?: boolean
  rest?: boolean
}
/** 道具定义（kernel props::Definition）；取默认值的字段不输出 */
export interface Definition {
  portable?: boolean
  stack_limit?: number
  storage_slots?: number
  id: string
  version: number
  name: string
  description: string
  actions: Action[]
  readable?: ContentText
  bulletin_board: boolean
  /** 遮蔽处：在上面做事按室内算 */
  shelter?: boolean
}
export interface Instance {
  id: string
  definition: string
  locale: string
  name?: string
  board?: string
}
/** 动作说明（crates/protocol PropActionView）；remaining 只有道具列表给出 */
export interface ActionDescription {
  consumes_item: boolean
  portion_name: string | null
  recipient: boolean
  remaining?: number | null
  supply: { initial: number; cost: number } | null
  id: string
  label: string
  minutes: number
  effects: string[]
  conditions: string[]
  result: string
}
/** 旧格式地图道具的动作：只有动作词与时长，没有效果定义 */
interface LegacyVerb {
  id: string
  label: string
  minutes: number | null
  effects: string[]
  conditions: string[]
  result: string
}
/** 可携带道具的位置：在谁身上、存在哪个容器里，或放在哪个落脚点 */
export type ItemLocation =
  | { kind: 'carried'; actor: string }
  | { kind: 'stored'; container: string }
  | { kind: 'ground'; locale: string; station: string }
/** 设定中心道具页的一件道具（crates/protocol PropView） */
export interface PropView {
  id: string
  definition: string | null
  locale: string
  board: string | null
  portable: boolean
  stack_limit: number
  storage_slots: number
  location_name: string | null
  on_map: boolean
  position: Vec3 | null
  walk_position: Locus | null
  location: ItemLocation | null
  name: string
  occupants: string[]
  actions: (ActionDescription | LegacyVerb)[]
  custom: boolean
  readable: ContentMeta | null
  bulletin_board: boolean
  withdrawn: boolean
}
/** 道具编辑器里的一个选项；id 是对应枚举的线上取值 */
export interface Option<T extends string = string> {
  id: T
  label: string
}
/** 运行期放置道具的通路（crates/protocol Route） */
interface RuntimeRoute {
  id: string
  from: string
  to: string
  from_locale: string
  to_locale: string
  width: number
  points: Vec3[]
  length: number
  minutes: number
  indoor: boolean
  owner: string | null
}
/** 运行期放置道具的三维覆盖（host spatial_overrides）；没有三维数据的地图为 null */
interface SpatialOverrides {
  revision: number
  removed: string[]
  overrides: { prop: SpatialProp; route: RuntimeRoute }[]
}
export interface PropCatalog {
  spatial: SpatialOverrides | null
  definition_actions: Record<string, ActionDescription[]>
  schema_version: number
  world_id: string
  persistent: boolean
  definitions: Definition[]
  instances: PropView[]
  locations: {
    id: string
    name: string
    /** 能分给村民当住宅的地点 */
    residential: boolean
  }[]
  capabilities: {
    duration: {
      min: number
      max: number
    }
    rate: {
      min: number
      max: number
    }
    max_actions: number
    needs: Option<BodyNeed>[]
    conditions: Option<ActionCondition>[]
    completions: Option<Completion>[]
    completion_effects: Option<InstantEffect['kind']>[]
    effects: Option<Effect['kind']>[]
    schema_version: number
    supports_recipients: boolean
    supports_supply: boolean
  }
}
export interface Appearance {
  glyph: 'box' | 'bed' | 'book' | 'plant' | 'machine'
  color: string
  image?: string
}

/** 作品来源：内置、玩家写的，或者哪位居民写的 */
type ContentOrigin = { kind: 'builtin' } | { kind: 'player' } | { kind: 'resident'; actor: string }
/** 一个作品版本的正文与署名（道具定义里的 readable、化身在读的内容） */
export interface ContentText {
  work_id: string
  version: number
  kind: 'book' | 'bulletin'
  title: string
  author: string
  text: string
  origin: ContentOrigin
}
/** 作品元数据（kernel Text::metadata）：不带正文 */
export interface ContentMeta extends Omit<ContentText, 'text'> {
  fingerprint: string
}
/** content 命令的回包：一件作品实例的当前版本与位置；撤下的作品没有当前版本 */
export interface ContentDetail {
  id: string
  locale: string
  board: string | null
  withdrawn: boolean
  content: ContentText | null
  versions: ContentMeta[]
}
/** validate_prop / save_prop 的回包 */
interface DefinitionPreview {
  definition: Definition
  actions?: ActionDescription[]
}
/**
 * prop_result.preview 按 host 实际发送定型：校验/保存定义给 DefinitionPreview，
 * content 命令给 ContentDetail，放置/移除给空对象，失败给 null。
 */
export type PropResultPreview =
  DefinitionPreview | ContentDetail | { definition?: undefined; content?: undefined } | null
export function isDefinitionPreview(p: PropResultPreview): p is DefinitionPreview {
  return !!p && 'definition' in p && p.definition !== undefined
}
export function isContentDetail(p: PropResultPreview): p is ContentDetail {
  return !!p && 'content' in p && p.content !== undefined
}
