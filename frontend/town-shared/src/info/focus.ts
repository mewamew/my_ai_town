// 地图上选中的村民：脚下一排动作钮（说话、跟随、附身、资料），需求告急时头边冒一个表情。
// 开着化身神力时，死者脚下多一个「复活」，活人多一个「神力」，点开是治愈、补满的选项单。
// 想法用地图自己的心声泡（选中的人一直挂着，见 bubbles.ts），这里不再画一份。
// 每帧按地图给的屏幕范围摆；人走出露出来的地图、被面板盖住或不在场时整组藏起来。
import { button, el } from '../dom'
import { gameIcon } from '../game/icons'
import type { GameMap } from '../gameMap'
import { visibleMapRect } from '../mapView'
import type { NeedKind } from '../protocol'
import type { MiracleKind } from '../avatar/types'
import type { MiracleOption } from '../miracles'
import './focus.css'

export interface FocusActions {
  talk(): void
  follow(): void
  possess(): void
  card(): void
  /** 化身神力：进入化身、走过去施展 */
  miracle(kind: MiracleKind): void
}

/** 一位村民此刻能做的事和要冒的表情；按名册每拍更新 */
export interface FocusState {
  canTalk: boolean
  canPossess: boolean
  following: boolean
  cardOpen: boolean
  /** 告急的需求：头边冒这一项的表情；没有就不冒 */
  alert: { kind: NeedKind; text: string } | null
  /** 化身神力的选项；没开神力或用不了化身时为 null，钮都不出现 */
  miracles: MiracleOption[] | null
}

const ALERT_ICONS: Record<NeedKind, string> = {
  fullness: 'food',
  energy: 'energy',
  water: 'water',
  health: 'heart',
}
/** 动作钮离脚底的距离：让开名字下面那行动作字 */
const BELOW_FEET = 30

export function createFocus(map: GameMap, container: HTMLElement, actions: FocusActions) {
  const root = el('div', '', 'resident-focus')
  root.id = 'resident-focus'
  root.hidden = true
  const emote = el('span', '', 'focus-emote')
  emote.setAttribute('role', 'img')
  const verbs = el('div', '', 'focus-verbs')
  const verb = (icon: string, label: string, run: () => void) => {
    const b = button('', run, 'focus-verb')
    const dot = el('span', '', 'focus-dot')
    dot.append(gameIcon(icon, true))
    b.append(dot, el('span', label, 'focus-label'))
    verbs.append(b)
    return b
  }
  const revive = verb('spark', '复活', () => actions.miracle('revive'))
  revive.classList.add('main')
  const talk = verb('chat', '说话', actions.talk)
  talk.classList.add('main')
  const follow = verb('eye', '跟随', actions.follow)
  const possess = verb('person', '附身', actions.possess)
  const card = verb('book', '资料', actions.card)
  // 活人的神力：点开选项单，选了就进入化身、走过去施展
  const powers = verb('spark', '神力', () => {
    sheet.hidden = !sheet.hidden
    powers.setAttribute('aria-expanded', String(!sheet.hidden))
  })
  powers.setAttribute('aria-haspopup', 'menu')
  const sheet = el('div', '', 'focus-miracles')
  sheet.setAttribute('role', 'menu')
  sheet.hidden = true
  verbs.append(sheet)
  root.append(emote, verbs)
  function closeSheet() {
    sheet.hidden = true
    powers.setAttribute('aria-expanded', 'false')
  }
  /** 选项单的内容：每种神力一行，写会变成多少；做不了的灰着写原因 */
  function fillSheet(options: MiracleOption[]) {
    const key = JSON.stringify(options)
    if (sheet.dataset.key === key) return
    sheet.dataset.key = key
    sheet.replaceChildren(
      el('p', '✦ 神力', 'focus-miracles-head'),
      ...options
        .filter((o) => o.kind !== 'revive')
        .map((o) => {
          const b = button('', () => {
            closeSheet()
            actions.miracle(o.kind)
          })
          b.setAttribute('role', 'menuitem')
          b.disabled = !o.enabled
          b.append(el('b', o.label), el('small', o.note))
          return b
        }),
      el('p', '化身会走过去；在场的人会看到', 'focus-miracles-foot')
    )
  }
  // 按下不能漏给地图：不然松手时地图当成点了空地，把选中取消了
  for (const type of ['pointerdown', 'dblclick'])
    root.addEventListener(type, (e) => e.stopPropagation())
  container.append(root)

  let selected: string | null = null
  let frame = 0

  function place() {
    frame = 0
    if (!selected) return
    const box = map.getScreenBox?.(selected)
    const area = container.getBoundingClientRect()
    const view = visibleMapRect(container)
    const shown =
      !!box &&
      box.x > view.left + 8 &&
      box.x < view.right - 8 &&
      box.feet > view.top &&
      box.feet < view.bottom - 8
    root.hidden = !shown
    if (box && shown) {
      root.style.setProperty('--focus-x', `${box.x - area.left}px`)
      root.style.setProperty('--focus-feet', `${box.feet - area.top + BELOW_FEET}px`)
      root.style.setProperty('--focus-head', `${box.top - area.top}px`)
      root.style.setProperty('--focus-half', `${box.half}px`)
      // 脚下那排钮落到露出来的地图下面时翻到头顶上方
      const room = view.bottom - area.top - (box.feet - area.top + BELOW_FEET)
      root.classList.toggle('flip', room < verbs.offsetHeight + 8)
    }
    frame = requestAnimationFrame(place)
  }

  return {
    /** 选中谁；null 收起 */
    show(id: string | null) {
      if (id !== selected) closeSheet()
      selected = id
      if (!id) {
        root.hidden = true
        cancelAnimationFrame(frame)
        frame = 0
        return
      }
      if (!frame) frame = requestAnimationFrame(place)
    },
    sync(state: FocusState) {
      const dead = !!state.miracles?.find((o) => o.kind === 'revive')?.enabled
      revive.hidden = !state.miracles || !dead
      powers.hidden = !state.miracles || dead
      if (powers.hidden) closeSheet()
      if (state.miracles) fillSheet(state.miracles)
      talk.hidden = !state.canTalk
      possess.hidden = !state.canPossess
      follow.setAttribute('aria-pressed', String(state.following))
      follow.querySelector('.focus-label')!.textContent = state.following ? '跟随中' : '跟随'
      card.setAttribute('aria-expanded', String(state.cardOpen))
      emote.hidden = !state.alert
      if (state.alert) {
        emote.replaceChildren(gameIcon(ALERT_ICONS[state.alert.kind], true))
        emote.setAttribute('aria-label', state.alert.text)
        emote.title = state.alert.text
      }
      card.classList.toggle('alert', !!state.alert)
    },
  }
}
