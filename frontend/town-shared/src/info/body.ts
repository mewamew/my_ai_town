import type { BodyView, PhysiologySwitches } from '../protocol'
import { clock, playerText } from '../format'
const labels: Record<string, string> = { injury: '受伤', illness: '疾病', poison: '中毒' }
/**
 * 生理状态：生命状态、伤病，以及「现在为什么变化」「身体与生命记录」两个折叠项。
 * foldHost 与 container 不同时（2D），身体正常就把前两行收进「身体与生命记录」，
 * 受伤、生病、死亡等异常才留在 container（需求条下面）醒目显示。
 */
export function createBodyView(container: HTMLElement, foldHost: HTMLElement = container) {
  const separate = foldHost !== container
  let previous = ''
  function render(body?: BodyView, switches?: PhysiologySwitches) {
    const key = JSON.stringify([body, switches])
    if (key === previous) return
    previous = key
    const wasOpen = Array.from(foldHost.querySelectorAll('details')).map((d) => d.open)
    container.replaceChildren()
    if (separate) foldHost.replaceChildren()
    if (!body) return
    const summary = document.createElement('p')
    summary.className =
      body.life === 'dead' ? 'body-danger' : !body.can_decide ? 'body-warning' : 'body-life'
    summary.textContent =
      body.life !== 'dead'
        ? `存活 · ${body.limitation}`
        : body.wound
          ? `遇害 · ${body.wound}`
          : body.limitation
    const conditions = document.createElement('div')
    conditions.className = 'body-conditions'
    if (switches && !switches.health)
      conditions.textContent = '健康机制已关闭，受伤、疾病、中毒不生效'
    else if (!body.conditions.length) conditions.textContent = '无受伤、疾病或中毒'
    for (const c of body.conditions) {
      const item = document.createElement('span')
      item.className = 'body-condition'
      item.textContent = `${labels[c.kind] ?? c.kind} · ${c.severity < 1.5 ? '轻' : c.severity < 2.5 ? '中' : '重'}`
      item.title = `发生于${clock(c.since)}；来源：${c.source}`
      conditions.append(item)
    }
    const normal = body.life !== 'dead' && body.can_decide && !body.conditions.length
    const reasons = document.createElement('details')
    reasons.open = wasOpen[0] ?? !body.can_decide
    const heading = document.createElement('summary')
    heading.textContent = '现在为什么变化'
    const list = document.createElement('ul')
    for (const cause of body.causes) {
      const li = document.createElement('li')
      li.textContent = playerText(cause)
      list.append(li)
    }
    if (body.life === 'dead') {
      const li = document.createElement('li')
      li.textContent = '死亡后停止生理消耗；需要明确复活手段。'
      list.append(li)
    } else if (switches && !body.causes.length) {
      const li = document.createElement('li')
      li.textContent = '数值不再变化：相关生理机制已在世界设定中关闭。'
      list.append(li)
    }
    reasons.append(heading, list)
    const history = document.createElement('details')
    history.open = wasOpen[1] ?? false
    const h = document.createElement('summary')
    h.textContent = `身体与生命记录（${body.history.length}）`
    history.append(h)
    if (separate && normal) {
      summary.textContent += ` · ${conditions.textContent}`
      history.append(summary)
    } else container.append(summary, conditions)
    const entries = document.createElement('ol')
    for (const event of body.history.slice(-30).reverse()) {
      const li = document.createElement('li')
      li.textContent = `${clock(event.at)} · ${playerText(event.text)}`
      entries.append(li)
    }
    history.append(entries)
    foldHost.append(reasons, history)
  }
  return {
    render,
    clear() {
      previous = ''
      container.replaceChildren()
      if (separate) foldHost.replaceChildren()
    },
  }
}
