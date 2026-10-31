// 重要事件的平实写法：死亡、受伤、生病、中毒、健康危重、全镇暂停。
// 服务端在事件与日记记录上给出结构化的 alert（种类、死因、暂停类别），这里只按它写标题和说明；
// 带数值的原文放在 detail 里给「详情」展开。事件栏、提示卡和日志页共用。
import { playerText } from './format'
import { holdCopy, type HoldCopy } from './holds'
import type { Alert, EventActor, NeedKind } from './protocol'

type ImportantKind = Alert['kind']

export interface ImportantEvent {
  kind: ImportantKind
  /** 相关村民的编号；全镇暂停时是触发暂停的村民 */
  actor: string
  /** 相关村民的名字 */
  name: string
  /** 提示卡标题，如「林溪去世了」「林溪遇害了」 */
  title: string
  /** 一句话说明，如「健康耗尽，去世了。饥饿和缺水持续太久」 */
  summary: string
  /** 提示卡上标题下面那行的原因（标题已说明发生了什么，不再重复）；没有就只写时间 */
  reason?: string
  /** 带数值的服务端原文；与 summary 相同时不给 */
  detail?: string
  /** 全镇暂停的说法与修法；同一原因的卡合成一张 */
  hold?: HoldCopy
  /** 全镇暂停时这位村民用的模型服务名，修复按钮据此打开对应的服务 */
  holdProvider?: string
}

type ConditionKind = Extract<Alert, { kind: 'condition' }>['condition']
const CONDITION_WORD: Record<ConditionKind, string> = {
  injury: '受伤',
  illness: '生病',
  poison: '中毒',
}
const SHORTAGE_WORD: Record<NeedKind, string> = {
  fullness: '饥饿',
  water: '缺水',
  energy: '过劳',
  health: '健康损失',
}

/** 「饥饿、过劳和缺水」 */
function joinAnd(items: string[]): string {
  return items.length < 2 ? (items[0] ?? '') : `${items.slice(0, -1).join('、')}和${items.at(-1)}`
}

/** 死因 →「中毒，饥饿和缺水持续太久」；随时间推进之外的死因没有来源，返回空串 */
function plainCause(alert: Extract<Alert, { kind: 'death' }>): string {
  const parts: string[] = []
  if (alert.conditions.length)
    parts.push([...new Set(alert.conditions.map((c) => CONDITION_WORD[c]))].join('、'))
  if (alert.shortages.length)
    parts.push(`${joinAnd([...new Set(alert.shortages.map((n) => SHORTAGE_WORD[n]))])}持续太久`)
  return parts.join('，')
}

/** 死亡记录 → 平实的一句与原文；遇害的写伤口，凶手留在原文（详情）里 */
export function describeDeath(alert: Extract<Alert, { kind: 'death' }>, text: string) {
  if (alert.killed) {
    const { wound } = alert.killed
    return { summary: `遇害身亡，${wound}`, reason: wound, detail: text }
  }
  const cause = plainCause(alert)
  return {
    summary: cause ? `健康耗尽，去世了。${cause}` : '健康耗尽，去世了',
    reason: cause ? `健康耗尽，${cause}` : '健康耗尽',
    detail: text,
  }
}

/** 带 alert 的世界日志一行 → 重要事件；text 是去掉时间前缀的原文 */
export function importantEvent(alert: Alert, actor: EventActor, text: string): ImportantEvent {
  const { id, name } = actor
  switch (alert.kind) {
    case 'hold': {
      // 标题说发生了什么、正文说接下来怎样；服务端原文带数字和错误码，进详情
      const hold = holdCopy(alert.pause, alert.cause, alert.provider)
      return {
        kind: 'hold',
        actor: id,
        name,
        title: hold.title,
        summary: hold.line,
        reason: hold.line,
        detail: `${name}：${playerText(alert.reason)}`,
        hold,
        holdProvider: alert.provider,
      }
    }
    case 'death':
      return {
        kind: 'death',
        actor: id,
        name,
        title: alert.killed ? `${name}遇害了` : `${name}去世了`,
        ...describeDeath(alert, text),
      }
    case 'condition': {
      const word = CONDITION_WORD[alert.condition]
      return {
        kind: 'condition',
        actor: id,
        name,
        title: `${name}${word}了`,
        summary: `${word}了`,
        detail: text,
      }
    }
    case 'critical': {
      const summary = '健康危重，无法自主活动或决策，需要他人救助'
      return {
        kind: 'critical',
        actor: id,
        name,
        title: `${name}健康危重`,
        summary,
        reason: summary,
      }
    }
  }
}

/** 事件栏里的一行字：名字 + 平实说明；全镇暂停本身就是完整句子 */
export function importantLine(e: ImportantEvent): string {
  return e.kind === 'hold' ? `全镇已暂停：${e.title}。${e.summary}` : `${e.name} ${e.summary}`
}

/** 可展开的「详情」：收着带数值的原文 */
export function detailsOf(detail: string): HTMLDetailsElement {
  const box = document.createElement('details')
  box.className = 'important-detail'
  const head = document.createElement('summary')
  head.textContent = '详情'
  const body = document.createElement('div')
  body.textContent = detail
  box.append(head, body)
  return box
}
