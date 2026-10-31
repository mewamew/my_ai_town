// 道具页两个视图、对象卡片和编辑器预览共用的部件：列表行、物品详情、动作说明、后端校验结果。
import type { ServerMsg } from '../protocol'
import { caption, meter, slot, status } from '../design/ui'
import { button, el } from './dom'
import { durationText, effectText, limitTexts, perHour, resultText } from './format'
import type { PropsView } from './pageState'
import { propPicture } from './picture'
import {
  isDefinitionPreview,
  type Action,
  type BodyNeed,
  type Definition,
  type PropView,
} from './types'

/** 列表里的一行（道具库用）：点了就选中并重画 */
export function listRow(view: PropsView, label: string, id: string, lines: HTMLElement[]) {
  const { state } = view
  const b = button(
    '',
    () => {
      state.selected = id
      view.render()
    },
    'prop-row'
  )
  b.classList.toggle('selected', state.selected === id)
  b.append(el('strong', label), ...lines)
  view.page.list.append(b)
}

const conditionLabel = { injury: '受伤', illness: '疾病', poison: '中毒' }

/** 定义里的效果写成一句话（「每小时恢复 9 点精力，算作有效休息」）；数值部分加粗 */
function effectSentence(a: Action, needLabel: (n: BodyNeed) => string) {
  const parts: (string | HTMLElement)[][] = []
  for (const e of a.during) {
    if (e.kind === 'restore_need')
      parts.push(['每小时恢复 ', el('b', `${perHour(e.per_minute)} 点${needLabel(e.need)}`)])
    else parts.push(['劳作会额外消耗精力和水分'])
  }
  for (const e of a.on_complete ?? []) {
    if (e.kind === 'restore')
      parts.push(['完成时恢复 ', el('b', `${e.amount} 点${needLabel(e.need)}`)])
    else if (e.kind === 'cure_condition') parts.push([`解除${conditionLabel[e.condition]}`])
    else if (e.kind === 'apply_condition')
      parts.push([el('b', `会造成${conditionLabel[e.condition]}`, 'bad'), `（程度 ${e.severity}）`])
    else if (e.kind === 'harm')
      parts.push([
        el('b', e.amount >= 100 ? '会杀死对方' : `对方健康减少 ${e.amount} 点`, 'bad'),
        `（留下${e.wound}）`,
      ])
    else if (e.kind === 'give_item') parts.push(['得到 ', el('b', `${e.item.name}×${e.count}`)])
    else if (e.kind === 'place_prop') parts.push(['在原地建成 ', el('b', e.prop.name)])
    else if (e.kind === 'chance')
      parts.push([
        el('b', `${e.percent}%`),
        e.effects.some((x) => x.kind === 'harm') ? ' 的可能得手' : ' 的可能有收获',
      ])
    else if (e.kind === 'schedule') parts.push(['过一阵会有动静'])
    else if (e.kind === 'depart') parts.push([el('b', '离开这里')])
    else parts.push(['可以让人复活'])
  }
  for (const r of a.requires ?? [])
    parts.push(['要带着 ', el('b', `${r.name}×${r.count}`), r.consume ? '（会用掉）' : ''])
  if (a.rest) parts.push(['算作有效休息'])
  if (a.consumes_item) parts.push(['用完就没了'])
  if (!parts.length) return null
  const p = el('p', '', 'pd-effects')
  parts.forEach((part, i) => {
    if (i) p.append('，')
    p.append(...part)
  })
  return p
}

/** 一个动作：第一行动作名和时长，下面一句效果，再往下是补给和限制 */
function actionRow(
  a: PropView['actions'][number],
  def: Action | undefined,
  needLabel: (n: BodyNeed) => string
) {
  const row = el('li', '', 'pd-action')
  const top = el('div', '', 'pd-action-top')
  top.append(
    el('strong', a.label),
    el('span', a.minutes === null ? '时长未定' : durationText(a.minutes), 'pd-dur')
  )
  row.append(top)
  const effects = def ? effectSentence(def, needLabel) : null
  if (effects) row.append(effects)
  else if (!def) for (const t of a.effects) row.append(el('p', effectText(t), 'pd-note'))
  const note = resultText(a.result)
  if (note) row.append(el('p', note, 'pd-note'))
  if ('supply' in a) {
    if (a.portion_name)
      row.append(el('p', `可领取：${a.portion_name}，与现场使用共用补给。`, 'pd-note'))
    if (a.supply) {
      const supply = el('div', '', 'pd-supply')
      const text =
        typeof a.remaining === 'number'
          ? `剩余 ${a.remaining} / ${a.supply.initial} 份`
          : `初始 ${a.supply.initial} 份`
      supply.append(el('span', `${text}，每次用掉 ${a.supply.cost} 份`))
      if (typeof a.remaining === 'number') supply.append(meter(a.remaining / a.supply.initial))
      row.append(supply)
    }
  }
  const limits = limitTexts(a.conditions)
  if (limits.length) row.append(el('p', '限制：' + limits.join('；'), 'pd-note'))
  return row
}

/** 动作列表；旧格式地图道具的动作只有动作词与时长，时长可能缺失 */
export function actionList(
  parent: HTMLElement,
  actions: PropView['actions'],
  definition?: Definition,
  needLabel: (n: BodyNeed) => string = (n) => n
) {
  const list = el('ul', '', 'pd-actions')
  for (const a of actions)
    list.append(
      actionRow(
        a,
        definition?.actions.find((d) => d.id === a.id),
        needLabel
      )
    )
  parent.append(list)
}

/** 一件道具现在的状态：撤下、占用状态未知、谁在用、空闲 */
function propStatus(
  p: PropView,
  connected: boolean,
  personName?: (id: string) => string | undefined
) {
  if (p.withdrawn) return status('已撤下')
  if (!connected) return status('占用状态未知')
  // occupants 是村民编号，显示名字。公告可以几个人同时看，有人在看也不算占用
  const who = p.occupants.map((id) => personName?.(id) ?? '有人').join('、')
  if (p.occupants.length && p.readable?.kind === 'bulletin') return status(`${who}正在看`, 'ok')
  if (p.occupants.length) return status(`${who}正在使用`, 'busy')
  return status('空闲', 'ok')
}

export interface DetailContext {
  localeName: (id: string) => string
  /** 村民编号 → 名字；不知道时写「有人」 */
  personName?: (id: string) => string | undefined
  connected: boolean
  /** 道具定义：有它才能把效果写成一句话、给出一句话说明 */
  definition?: Definition
  needLabel: (n: BodyNeed) => string
  /** 卡片用中号物品图，整页右栏用大号 */
  size: 'card' | 'page'
  /** 按钮区：卡片和整页各放自己的按钮 */
  buttons: HTMLElement[]
}

/** 道具详情，对象卡片与整页右栏共用：名字、地点和状态在前，其次是能做什么，最后是按钮 */
export function renderPropDetail(parent: HTMLElement, p: PropView, ctx: DetailContext) {
  const { definition } = ctx
  const head = el('header', '', 'pd-head')
  const art = slot(
    propPicture(p.definition ?? p.id, p.readable ? 'book' : 'bag'),
    ctx.size === 'page' ? 'lg' : 'md'
  )
  const id = el('div', '', 'pd-id')
  const where =
    p.location?.kind === 'carried'
      ? `${p.location_name ?? p.location.actor}的随身物品`
      : p.location?.kind === 'stored'
        ? `存放在${p.location_name ?? p.location.container}`
        : ctx.localeName(p.locale)
  const meta = el('div', '', 'pd-meta')
  meta.append(el('span', where), propStatus(p, ctx.connected, ctx.personName))
  id.append(el('h2', p.name, 'ui-title pd-name'))
  if (p.readable)
    id.append(
      el('p', `${p.readable.author} ${p.readable.kind === 'book' ? '著' : '张贴'}`, 'pd-by')
    )
  id.append(meta)
  head.append(art, id)
  parent.append(head)
  const facts: string[] = []
  facts.push(p.portable ? `可以放进背包，每格最多 ${p.stack_limit} 件` : '固定在原地，不能带走')
  if (p.storage_slots) facts.push(`能存放 ${p.storage_slots} 格东西`)
  if (p.withdrawn) facts.push('公告已撤下，村民不能开始新的阅读；读过的人仍能回看当时的版本')
  // 书和公告的定义说明是给 Agent 的系统话，作者已经写在名字下面
  if (definition?.description && !p.readable)
    parent.append(el('p', definition.description, 'pd-desc'))
  parent.append(caption('可以做的事'))
  if (p.actions.length) actionList(parent, p.actions, definition, ctx.needLabel)
  else parent.append(el('p', '只是摆在这里的东西，没有使用动作。', 'pd-note'))
  parent.append(el('p', facts.join('。') + '。', 'pd-facts'))
  if (ctx.buttons.length) {
    const foot = el('div', '', 'pd-foot')
    foot.append(...ctx.buttons)
    parent.append(foot)
  }
}

/** 编辑器里「预览实际效果」的结果：后端校验后的携带说明与动作说明 */
export function showValidation(msg: Extract<ServerMsg, { type: 'prop_result' }>) {
  const preview = document.getElementById('prop-editor-preview')
  if (!preview) return
  preview.replaceChildren()
  if (!msg.ok || !isDefinitionPreview(msg.preview)) {
    preview.append(el('p', msg.message))
    return
  }
  const d = msg.preview.definition
  preview.append(
    el(
      'p',
      d.portable
        ? `校验通过 · 可放入背包，每格最多 ${d.stack_limit ?? 1} 件。`
        : '校验通过 · 固定道具。'
    )
  )
  if (d.storage_slots) preview.append(el('p', `容器容量 ${d.storage_slots} 格。`))
  if (msg.preview.actions?.length) actionList(preview, msg.preview.actions, d)
  else preview.append(el('p', '没有使用动作，可作为收藏物品。'))
}
