import { query } from 'town-shared/dom'
import { creationRequest } from './localCreation'
import { localOptions } from './creatorOptions'
import type { createPlacePicker } from './creatorPicker'
import type { Constraint, CreatorStep, Draft, Mention, Options } from './creatorTypes'

/**
 * 建镇页的全部状态和取页面元素的方法；步骤、表单、生成、保存各模块都读写它。
 * 生成、取消和保存之间靠 revision 防止过时的结果覆盖新的：每次要求改变或开始生成
 * 都加一，异步回来时发现它变了就丢掉结果。
 */
export class CreatorContext<D extends Draft = Draft> {
  /** 地点模板、上限（页面自带）和模型能不能用（打开建镇页时问管理服务） */
  readonly options: Options = localOptions()
  /** 没问到模型状态的原因，多半是小镇服务停了；写在模型那一行，点重试再问 */
  modelProblem?: string
  picker?: ReturnType<typeof createPlacePicker>
  /** 一句话规划解析出的位置关系和地点名，只在一句话模式下带进参数 */
  parsedConstraints: Constraint[] = []
  parsedNames: Record<string, string> = {}
  /** 一句话规划给玩家看的：说到的地方对应哪里、做不到的事、适合住进来的人 */
  mapping: Mention[] = []
  notes: string[] = []
  residents: string[] = []
  /** 一句话规划时模型给的世界观建议；保存小镇时一起存下，第一次进镇默认用它 */
  worldview = ''
  /** 当前预览用的布局种子：「按这句改」先用它，只改名字时地图不变 */
  draftSeed?: number
  languageMode = false
  /** 正在等模型理解描述：左栏摘要先不写默认值 */
  parsing = false
  /** 首页设定里的连接模型弹层；没连模型时一句话规划在原处给这个按钮 */
  connectModel?: () => Promise<string>
  currentStep: CreatorStep = 'basics'
  /** 当前可以保存的草稿；要求改了或正在生成时为空 */
  draft?: D
  previewMap?: { dispose(): void }
  revision = 0
  /** 当前生成请求，取消时中止 */
  controller?: AbortController
  /** 这一版草稿的保存操作编号，重复点保存时服务端按它去重 */
  saveId = ''
  busy = false
  saving = false
  lastSeed?: number
  /** 保存期间整张表单禁用，之前就禁用的元素记下来，保存完不误开 */
  readonly disabledBeforeSave = new Set<Element>()

  constructor(readonly panel: HTMLElement) {}

  /** 电脑版直接请求管理服务；手机应用里生成换到网页里做，见 localCreation.ts */
  readonly request = creationRequest()

  el<T extends HTMLElement = HTMLElement>(id: string) {
    return query<T>(this.panel, '#' + id)
  }
  input(id: string) {
    return this.el<HTMLInputElement>(id)
  }
  select(id: string) {
    return this.el<HTMLSelectElement>(id)
  }
  status(text: string) {
    this.el('creator-status').textContent = text
  }
  nameOf(kind: string) {
    return this.options.templates.find((t) => t.kind === kind)?.name ?? kind
  }
}
