// 重要事件提示卡：村民去世、受伤、生病、中毒、健康危重、全镇暂停时，在地图上方居中弹出。
// 同一时刻同一类的事合成一张卡（「阿岚、阿树等 8 人去世了」）；同时最多显示 2 张（手机 1 张），
// 更多的排队，关掉一张补一张。卡片不自动消失，要玩家关掉。带数值的原文在事件栏和日志页的「详情」里。
// 全镇暂停按原因合成一张卡，列出受影响的人，按钮直接去修；暂停解除后卡片自己收起。

import './notices.css'
import { el, button } from './dom'
import { displayClock, playerText } from './format'
import type { HoldFix } from './holds'
import { detailsOf, type ImportantEvent } from './importantEvents'
import { isCompact } from './platform'
import { portraitFor, portraitKey } from './portraits'
import type { ResidentRegistration, WorldHold } from './protocol'

/** 手机布局一次只放一张，免得盖满地图 */
const maxShown = () => (isCompact() ? 1 : 2)

interface Notice {
  clock: string
  items: ImportantEvent[]
  box?: HTMLElement
}

export function createNotices(
  host: HTMLElement,
  onView: (residentId: string) => void,
  /** 暂停卡上的修复按钮；provider 是受影响村民用的服务名 */
  onFix: (fix: HoldFix, provider: string) => void
) {
  const stack = el('div', '', 'town-notices')
  stack.setAttribute('role', 'alert')
  // 与地图内按钮一样隔离指针事件，点卡片不会拖动地图
  for (const type of ['pointerdown', 'dblclick', 'wheel'])
    stack.addEventListener(type, (event) => event.stopPropagation())
  host.append(stack)
  const shown: Notice[] = []
  const queue: Notice[] = []
  let residents: ResidentRegistration[] = []

  /** 多人时标题写「阿岚、阿树等 8 人去世了」；标题去掉名字剩下的部分就是发生的事 */
  function titleOf(items: ImportantEvent[]): string {
    const first = items[0]
    if (items.length === 1) return first.title
    const names = items.map((e) => e.name)
    const what = first.title.slice(first.name.length)
    const who =
      items.length === 2 ? names.join('、') : `${names.slice(0, 2).join('、')}等 ${items.length} 人`
    return `${who}${what}`
  }

  /** 全镇暂停：标题、影响谁、接下来怎样，主按钮去修；各人的原文收进「详情」 */
  function renderHold(n: Notice): HTMLElement {
    const copy = n.items[0].hold!
    const box = el('div', '', `town-notice notice-hold tone-${copy.tone}`)
    box.append(el('span', '!', 'notice-portrait'))
    const body = el('div', '', 'notice-body')
    const names = [...new Set(n.items.map((e) => e.name))]
    body.append(
      el('strong', copy.title, 'notice-title'),
      el('div', `影响：${names.join('、')}`, 'notice-who'),
      el('div', copy.line, 'notice-line')
    )
    const details = n.items.map((e) => e.detail).filter((d): d is string => !!d)
    if (details.length) body.append(detailsOf([...new Set(details)].join('\n')))
    const actions = el('div', '', 'notice-actions')
    const provider = n.items[0].holdProvider ?? ''
    copy.actions.forEach((a, i) =>
      actions.append(button(a.label, () => onFix(a.fix, provider), i === 0 ? 'primary' : ''))
    )
    actions.append(button('关闭', () => close(n), 'ui-btn ghost'))
    body.append(actions)
    box.append(body)
    return box
  }

  function render(n: Notice): HTMLElement {
    const first = n.items[0]
    if (first.hold) return renderHold(n)
    const who = residents.find((r) => r.id === first.actor)
    const box = el('div', '', `town-notice notice-${first.kind}`)
    const url = who && first.kind !== 'hold' ? portraitFor(portraitKey(who)) : undefined
    if (url) {
      const img = el('img', '', 'notice-portrait')
      img.src = url
      img.alt = ''
      box.append(img)
    } else
      box.append(
        el('span', first.kind === 'hold' ? '!' : first.name.slice(0, 1), 'notice-portrait')
      )
    const body = el('div', '', 'notice-body')
    const reason = n.items.length === 1 ? first.reason : undefined
    body.append(
      el('strong', titleOf(n.items), 'notice-title'),
      el('div', displayClock(n.clock) + (reason ? ` · ${playerText(reason)}` : ''), 'notice-line')
    )
    const actions = el('div', '', 'notice-actions')
    if (who)
      actions.append(
        button('查看', () => {
          onView(who.id)
          close(n)
        })
      )
    actions.append(button('关闭', () => close(n)))
    box.append(body, actions)
    return box
  }

  function place(n: Notice) {
    const box = render(n)
    if (n.box) n.box.replaceWith(box)
    else stack.append(box)
    n.box = box
  }

  function close(n: Notice) {
    n.box?.remove()
    shown.splice(shown.indexOf(n), 1)
    const next = queue.shift()
    if (next) {
      shown.push(next)
      place(next)
    }
  }

  /** 标题去掉名字剩下的部分：遇害和去世、受伤和中毒说法不同，不合成一张 */
  const what = (e: ImportantEvent) => e.title.slice(e.name.length)

  return {
    show(clock: string, important: ImportantEvent) {
      // 暂停卡按原因合并，不论时间；同一个人再暂停一次不重复列名字
      const key = important.hold?.key
      const same = [...shown, ...queue].find((n) =>
        key
          ? n.items[0].hold?.key === key
          : n.clock === clock &&
            n.items[0].kind === important.kind &&
            what(n.items[0]) === what(important) &&
            !n.items[0].hold
      )
      if (same) {
        if (!key || !same.items.some((e) => e.actor === important.actor)) same.items.push(important)
        if (same.box) place(same)
        return
      }
      const n: Notice = { clock, items: [important] }
      if (shown.length < maxShown()) {
        shown.push(n)
        place(n)
      } else queue.push(n)
    },
    /** 居民登记：按编号找头像，「查看」按编号选中 */
    setResidents(list: ResidentRegistration[]) {
      residents = list
    },
    /** 每份名册：暂停解除了（玩家点了继续、换好了密钥）就收起暂停卡 */
    syncHolds(holds: WorldHold[]) {
      if (holds.length) return
      for (const n of [...queue]) if (n.items[0].hold) queue.splice(queue.indexOf(n), 1)
      for (const n of [...shown]) if (n.items[0].hold) close(n)
    },
  }
}
