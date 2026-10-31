import type { PlanView, BodyView } from '../protocol'
import { playerText } from '../format'

/** 角色卡「正在」一栏：此刻在做的事，下面是接下来的几件；只读，不伪装成可勾选的清单 */
export function createPlanView(box: HTMLElement) {
  let lastPlanKey: string | null = ''
  function renderPlan(plan?: PlanView, body?: BodyView) {
    const key = JSON.stringify([plan, body?.can_decide])
    if (key === lastPlanKey) return
    lastPlanKey = key
    box.replaceChildren()
    box.className = ''

    if (!plan) {
      box.className = 'dim'
      box.textContent = '计划数据暂不可用'
      return
    }

    const current = document.createElement('div')
    current.className = 'plan-current'
    current.textContent = playerText(plan.current)
    box.appendChild(current)

    const next = document.createElement('div')
    next.className = 'plan-next-head'
    next.textContent = plan.upcoming.length ? '接下来' : '接下来 · 还没想好'
    box.appendChild(next)
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

    if (body && !body.can_decide) {
      const note = document.createElement('div')
      note.className = 'plan-note'
      note.textContent = '重新获得自主能力后，才会重新观察并安排活动。'
      box.appendChild(note)
    }
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
