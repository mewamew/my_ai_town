import type { ResidentAgentView, ResidentDetailView } from '../protocol'
import { el as text } from '../dom'
import { clock, playerText } from '../format'
import {
  agentStateLabels,
  goalStatusLabels,
  interactionStatusLabels,
  memoryKindLabels,
  memorySourceLabels,
  memoryStatusLabels,
} from '../labels'

type Goal = ResidentDetailView['goals'][number]
type Result = ResidentDetailView['results'][number]
type Interaction = ResidentDetailView['interactions'][number]
type Memory = ResidentDetailView['memories'][number]

const resultStatusLabels = {
  succeeded: '完成',
  failed: '失败',
  interrupted: '中断',
  cancelled: '取消',
}

/** 状态和原因；调用次数、token 这些在「消耗」页里 */
function header(view: ResidentAgentView): HTMLElement[] {
  return [
    text('strong', agentStateLabels[view.state]),
    text('p', playerText(view.reason), 'dim'),
    text('p', 'AI 用了多少、花了多少，在「消耗」里看', 'agent-meter'),
  ]
}

/** 小标题 + 空提示 + 每项一行 */
function section<T>(title: string, items: T[], empty: string, row: (item: T) => HTMLElement) {
  const nodes: HTMLElement[] = [text('h4', title)]
  if (!items.length) nodes.push(text('p', empty, 'dim'))
  for (const item of items) nodes.push(row(item))
  return nodes
}

function goalRow(goal: Goal) {
  const row = text('article', '', 'agent-goal')
  row.dataset.goalId = goal.id
  row.append(text('strong', `${goal.title} · ${goalStatusLabels[goal.status]}`))
  const ongoing = goal.status === 'active' || goal.status === 'paused'
  if (goal.commitment)
    row.append(text('p', `${ongoing ? '记着的事' : '当时的约定'}：${playerText(goal.commitment)}`))
  if (goal.reason) row.append(text('p', playerText(goal.reason), 'dim'))
  if (ongoing && goal.next_steps.length)
    row.append(text('p', `接下来：${playerText(goal.next_steps.join('；'))}`))
  return row
}

function resultRow(result: Result) {
  const row = text('article', '', 'agent-result')
  row.append(
    text('strong', `${result.verb} · ${resultStatusLabels[result.status]}`),
    text(
      'p',
      `${clock(result.ended_at)} · ${playerText(result.changes.join('；')) || '没有新的世界变化'}`,
      'dim'
    )
  )
  if (result.reason) row.append(text('p', playerText(result.reason)))
  return row
}

function interactionRow(interaction: Interaction) {
  const row = text('article', '', 'agent-result')
  row.dataset.interactionId = interaction.id
  row.append(
    text('strong', `${interaction.title} · ${interactionStatusLabels[interaction.status]}`),
    text('p', interaction.participants.join('、')),
    text('p', playerText(interaction.result), 'dim')
  )
  return row
}

/** 记忆一行；来源放在 details 里，opened 是上一次渲染时已展开的记忆 id */
function memoryRow(memory: Memory, opened: Set<string | undefined>) {
  const row = text('article', '', 'agent-memory')
  row.append(
    // 经历最常见，不写；记得好好的也不写，只写来源和改过看法的
    text(
      'p',
      [
        memory.kind === 'episode' ? '' : memoryKindLabels[memory.kind],
        memorySourceLabels[memory.source],
        memory.status === 'active' ? '' : memoryStatusLabels[memory.status],
      ]
        .filter(Boolean)
        .join(' · '),
      'agent-memory-meta'
    ),
    text('p', playerText(memory.text))
  )
  const details = document.createElement('details')
  details.dataset.memoryId = String(memory.memory_id)
  details.open = opened.has(details.dataset.memoryId)
  details.append(text('summary', `查看来源 · ${clock(memory.at)}`))
  if (memory.replaces.length)
    details.append(text('p', `修正了之前的 ${memory.replaces.length} 条记忆`))
  for (const event of memory.events)
    details.append(text('p', `${clock(event.at)}\n${playerText(event.text)}`, 'agent-source'))
  row.append(details)
  return row
}

/**
 * 只读投影，分两截：状态和原因跟着名册每拍来（render）；目标、动作结果、互动和记着的事是世界单独发来的
 * 细节（detail），变了才来一份，更新时保留已展开的来源。recorded：重演录像，没有世界可问，细节不显示。
 */
export function createAgentView(box: HTMLElement, recorded = false) {
  box.classList.add('resident-agent')
  const head = text('div')
  const lists = text('div')
  /** 上次画的状态和原因；空串是还没画过这个人 */
  let drawn = ''
  function clear() {
    drawn = ''
    lists.replaceChildren()
    box.replaceChildren(text('p', '该村民没有 Agent 会话', 'dim'))
  }
  function render(view?: ResidentAgentView) {
    if (!view) {
      if (drawn) clear()
      return
    }
    const key = `${view.state}\n${view.reason}`
    if (key === drawn) return
    if (!drawn) {
      box.replaceChildren(head, lists)
      // 重演时只有名册：说清这一截为什么空着
      if (recorded) lists.replaceChildren(text('p', '重演录像时不显示目标与记忆', 'dim'))
    }
    drawn = key
    head.replaceChildren(...header(view))
  }
  /** 选中这位的细节到了；null 是世界说他没有（没有 Agent 会话） */
  function detail(view: ResidentDetailView | null) {
    if (!view) return lists.replaceChildren()
    const opened = new Set(
      Array.from(lists.querySelectorAll<HTMLDetailsElement>('details[open]')).map(
        (d) => d.dataset.memoryId
      )
    )
    const fragment = document.createDocumentFragment()
    fragment.append(
      ...section('持续目标', view.goals, '还没有记录目标', goalRow),
      ...section('最近动作结果', view.results, '还没有动作结果', resultRow)
    )
    if (view.interactions.length)
      fragment.append(text('h4', '互动与聊天'), ...view.interactions.map(interactionRow))
    fragment.append(
      ...section('记着的事', view.memories, '还没有记下什么', (memory) => memoryRow(memory, opened))
    )
    lists.replaceChildren(fragment)
  }
  clear()
  return { render, detail, clear, reset: clear }
}
