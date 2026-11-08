import type { MapDocument } from 'town-shared/mapDocument'
import type { CreatorLimits } from './creatorPicker'

// 建镇页的数据类型：建镇参数、后端返回的草稿与选项。

export type Kind = { kind: string; name: string; outdoor: boolean }
export const placeSizes = [
  ['small', '小'],
  ['medium', '中'],
  ['large', '大'],
] as const
type PlaceSize = (typeof placeSizes)[number][0]
type SpecPlace = { kind: string; count: number; size: PlaceSize }
type EditableSpecPlace = Omit<SpecPlace, 'size'> & { size?: PlaceSize }
export type Spec = {
  name: string
  seed: number
  schema_version: 2
  view_mode?: '2d'
  appearance_set: string
  environment: { preset: string; vegetation: string }
  places: SpecPlace[]
  /** 地点名：键是 kind 或 kind:序号，一句话规划时由模型按描述起 */
  names?: Record<string, string>
  constraints: Constraint[]
  resources: string
  terrain_source?: string
  /** 地点之间怎么连：不写是小镇街道；wild 是野外小径（荒岛、野地）；ring 是环岛小径（户外地点沿海岸一圈） */
  settlement?: 'town' | 'wild' | 'ring'
}
export type EditableSpec = Omit<Spec, 'places'> & { places: EditableSpecPlace[] }
export type Constraint = {
  kind: string
  subject: string
  relative_to: string
  value?: string
  required: boolean
}
export type ReportConstraint = Constraint & {
  satisfied: boolean
  expected?: number
  measured?: number
}
export type Draft = {
  id: string
  version: string
  document: MapDocument
  report: {
    warnings: string[]
    constraints: ReportConstraint[]
    places: { ref: string; name: string }[]
  }
}
export type Options = {
  templates: Kind[]
  limits: CreatorLimits
  /** 管理服务 /options 回答的；还没问到时为空 */
  model?: { available: boolean; provider?: string; model?: string; error?: string }
}
/** 玩家说到的一处地方对应地图上的哪些地点；refs 为空表示地图上没有 */
export type Mention = { said: string; refs: string[] }
export type ParseResult = {
  spec: Spec
  mapping: Mention[]
  notes: string[]
  /** 适合住在这里的人，一人一句；进镇时开局向导按这几句写人设、请进来 */
  residents: string[]
  worldview_suggestion: string
  model: string
  calls: number
}
export type CreatorStep = 'basics' | 'environment' | 'places' | 'preview'
export const creatorSteps: CreatorStep[] = ['basics', 'environment', 'places', 'preview']
