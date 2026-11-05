import type { BodyView, FactKind, PlanView, ResidentAgentView } from '../protocol'
import { clockNear, playerText } from '../format'

/** 等的那类事件来了会提前醒。动作和阅读结果等待时等不到（旧存档里可能还挂着），不写 */
const wakeOn: Partial<Record<FactKind, string>> = {
  presence: '有人来去就醒',
  speech: '有人说话就醒',
  interaction: '有邀约或回应就醒',
  observation: '有新动静就醒',
  notice: '有要紧事就醒',
}

/** 身体闲着时世界层只会说「等待新计划」；Agent 在等、在想或在整理记忆时，改说他实际在做什么 */
function mind(plan: PlanView, agent: ResidentAgentView | undefined, now: number) {
  if (!plan.idle || !agent) return null
  const { wait, state } = agent
  if (wait) {
    const at = clockNear(wait.until, now)
    const on = wait.event && wakeOn[wait.event]
    return {
      text: playerText(wait.reason),
      wake: on ? `${on} · 最迟 ${at} 再想` : `到 ${at} 再想`,
    }
  }
  if (state === 'thinking') return { text: '在想下一步' }
  if (state === 'reflecting') return { text: '在整理记忆' }
  return null
}

function line(className: string, text: string) {
  const div = document.createElement('div')
  div.className = className
  div.textContent = text
  return div
}

/** 角色卡「正在」一栏：此刻在做的事，下面是接下来的几件；只读，不伪装成可勾选的清单 */
export function createPlanView(box: HTMLElement) {
  let lastPlanKey: string | null = ''
  function renderPlan(plan?: PlanView, body?: BodyView, agent?: ResidentAgentView, now = 0) {
    const minded = plan && mind(plan, agent, now)
    const key = JSON.stringify([plan, body?.can_decide, minded])
    if (key === lastPlanKey) return
    lastPlanKey = key
    box.replaceChildren()
    box.className = ''

    if (!plan) {
      box.className = 'dim'
      box.textContent = '计划数据暂不可用'
      return
    }

    if (minded) {
      box.appendChild(line('plan-current', minded.text))
      if (minded.wake) box.appendChild(line('plan-wake', minded.wake))
    } else {
      box.appendChild(line('plan-current', playerText(plan.current)))
      box.appendChild(line('plan-next-head', plan.upcoming.length ? '接下来' : '接下来 · 还没想好'))
      if (plan.upcoming.length) {
        const list = document.createElement('ol')
        list.className = 'plan-list'
        for (const text of plan.upcoming) {
          const item = document.createElement('li')
          item.textContent = playerText(text)
          list.appendChild(item)
        }
        box.appendChild(list)
      }
    }

    if (body && !body.can_decide)
      box.appendChild(line('plan-note', '重新获得自主能力后，才会重新观察并安排活动。'))
  }

  return {
    render: renderPlan,
    reset() {
      lastPlanKey = null
    },
    clear() {
      lastPlanKey = ''
      box.className = 'dim'
      box.textContent = '计划数据暂不可用'
    },
  }
}
