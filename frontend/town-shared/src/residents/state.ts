// 村民页的状态：服务器给的名册、登记表与村民库，当前视图，以及各视图跨渲染保留的输入。
import type { EventsHandle } from '../events'
import type { ResidentEntry } from '../gameMap'
import type { ModelOption } from '../models/session'
import type {
  ClientMsg,
  JoinOutcome,
  JoinPreview,
  LibraryFilter,
  ModelChoice,
  PopulationView,
  ResidentTemplate,
  TemplateCard,
  TemplateFields,
} from '../protocol'

export interface ResidentsDeps {
  send: (obj: ClientMsg) => void
  events: EventsHandle
  localeName: (id: string) => string
  onLocate: (id: string) => void
  onFollow: (id: string) => void
  /** 「档案」：回到地图，打开他的角色卡翻到人设 */
  onOpenProfile: (resident: { id: string; name: string }) => void
  /** 能用的模型，第一个是新村民默认用的；一个都没有时先住下，连上模型再行动 */
  modelOptions: () => ModelOption[]
  /** 打开连接模型的弹层 */
  connectModel: () => void
  /** 请人入住结束：回到地图告诉玩家谁搬进来了；failed 是没请成的原因 */
  onJoined: (joined: JoinOutcome[], failed: string[], model: ModelOption | null) => void
  /** 村民库列表回来了（空镇卡片用它挑推荐人选） */
  onLibrary: (cards: TemplateCard[]) => void
  /** 游戏界面 */
  game: boolean
  /** 这个小镇的去处，村民表单的兴趣栏列出来点选 */
  placeNames: () => string[]
  /** 打开村民页时收起居民卡 */
  onOverlayOpen: () => void
}

export type ResidentsTab = 'roster' | 'library'
export type ResidentsView =
  | { kind: ResidentsTab }
  | { kind: 'template'; id: string }
  | { kind: 'join'; id: string }
  /** from：从哪一页打开，返回、取消回到那里；从村中居民新建时主按钮是「保存并加入小镇」 */
  | { kind: 'editor'; template?: ResidentTemplate; copyFrom?: TemplateFields; from?: ResidentsTab }

/** 编辑器跨渲染保留：生成请求、预览回写、保存后是否直接加入 */
interface EditorState {
  /** 给 AI 看的人设原文（折叠）；set 换成最新的预览 */
  persona: { details: HTMLElement; set(text: string): void }
  status: HTMLElement
  aiStatus: HTMLElement
  gen: HTMLButtonElement
  fill: (f: TemplateFields) => void
  generating: string | null
  /** 正在等回执的保存请求编号 */
  saving: string | null
  joinAfterSave: boolean
}

interface ResidentsState {
  population: PopulationView | null
  roster: ResidentEntry[]
  cards: TemplateCard[]
  customRoot: string
  view: ResidentsView
  filter: Required<LibraryFilter>
  detail: { template?: ResidentTemplate; persona: string; error?: string } | null
  preview: JoinPreview | null
  pending: { op_id: string; template_id: string } | null
  notice: { text: string; residentId?: string; warning?: boolean } | null
  /** 村民库里勾选的人（模板编号），底部托盘一次请进来 */
  picks: string[]
  /** 托盘上换过的模型；没换时用 modelOptions 的第一个 */
  joinModel: ModelChoice | null
  /** 正在请人入住 */
  inviting: boolean
  /** 名册视图上一次画出的内容；roster 每拍都来，内容没变就不重画 */
  rosterSignature: string
  residentQuery: string
  editor: EditorState | null
}

export function createResidentsState(): ResidentsState {
  return {
    population: null,
    roster: [],
    cards: [],
    customRoot: '',
    view: { kind: 'roster' },
    filter: { query: '', kind: 'all', include_archived: false },
    detail: null,
    preview: null,
    pending: null,
    notice: null,
    picks: [],
    joinModel: null,
    inviting: false,
    rosterSignature: '',
    residentQuery: '',
    editor: null,
  }
}

/** 一个视图画出的内容；update 只重画列表等会变的部分，搜索框之类的输入框保留 */
export interface ViewHandle {
  root: HTMLElement
  update?(): void
}

/** 各视图共用的页面操作 */
export interface ResidentsContext {
  state: ResidentsState
  deps: ResidentsDeps
  game: boolean
  render(): void
  setTab(tab: ResidentsTab): void
  /** 打开新建村民；from 是返回时回到的那一页 */
  newVillager(from: ResidentsTab): void
  showTemplate(id: string): void
  startJoin(id: string): void
  /** 一次请几位入住：逐个预览、按预览给的住宅入住，带上所选模型 */
  invite(templateIds: string[]): Promise<void>
  /** 托盘和加入表单用的模型 */
  joinModel(): ModelOption | null
  requestLibrary(): void
  close(): void
  /** 回到地图并选中这位居民；2D 同时跟随 */
  locateButton(id: string): HTMLButtonElement
  setStatus(target: HTMLElement, text: string, bad?: boolean): void
}
