import type { AvatarInteraction, AvatarState } from './types'
import { button, el } from '../dom'
// 化身界面的小部件：面板按钮、按键提示、标记预览、色板，以及查交谈的几个函数。三个面板与控制器共用。

const SVG = 'http://www.w3.org/2000/svg'
/** 预设颜色；第一个是默认色 */
export const PRESET_COLORS = ['#387963', '#b4691e', '#5f6f95', '#a33d2b', '#8b6d3a', '#6b4d8a']

/** 面板里的操作按钮：做不了的操作照样列出，disabled 时按不下去 */
export function panelButton(text: string, action: () => void, disabled: boolean) {
  const b = button(text, action)
  b.disabled = disabled
  return b
}
export function keycap(key: string) {
  return el('kbd', key)
}
/** 操作条与面板里带按键提示的按钮；icon 画在最前面（游戏界面的热栏按钮用） */
export function actionButton(
  label: string,
  key: string | undefined,
  action: () => void,
  icon: SVGSVGElement | null = null
) {
  const b = el('button')
  b.type = 'button'
  b.className = 'avatar-act'
  if (icon) b.append(icon)
  if (key) b.append(keycap(key))
  b.append(el('span', label))
  b.onclick = action
  return b
}
/** 带说明文字的字段；色板用 div 包，避免 label 把点击转给第一个按钮 */
export function field(caption: string, control: HTMLElement) {
  const f = el(control instanceof HTMLInputElement ? 'label' : 'div')
  f.className = 'avatar-field'
  f.append(el('span', caption), control)
  return f
}
/** 地图上化身标记的样子：圆环加三角，颜色随选择变化 */
export function markerSvg(color: string, size = 44): SVGSVGElement {
  const svg = document.createElementNS(SVG, 'svg')
  svg.setAttribute('viewBox', '-30 -30 60 60')
  svg.setAttribute('width', String(size))
  svg.setAttribute('height', String(size))
  svg.setAttribute('aria-hidden', 'true')
  const ring = document.createElementNS(SVG, 'circle')
  ring.setAttribute('r', '26')
  ring.setAttribute('fill', 'none')
  ring.setAttribute('stroke', color)
  ring.setAttribute('stroke-width', '3')
  const tri = document.createElementNS(SVG, 'path')
  tri.setAttribute('d', 'M0,-17 L15,11 L-15,11 Z')
  tri.setAttribute('fill', color)
  svg.append(ring, tri)
  return svg
}
/** 预设色加自定义取色器；value 始终是当前颜色 */
export function colorPicker(initial: string, onChange: (color: string) => void) {
  const root = el('div')
  root.className = 'avatar-swatches'
  const custom = el('input')
  custom.type = 'color'
  custom.value = initial
  custom.setAttribute('aria-label', '自定义颜色')
  let value = initial
  const swatches: HTMLButtonElement[] = []
  const mark = () => {
    for (const s of swatches) s.classList.toggle('on', s.dataset.color === value)
    custom.classList.toggle('on', !swatches.some((s) => s.dataset.color === value))
  }
  const set = (color: string, notify: boolean) => {
    value = color
    custom.value = color
    mark()
    if (notify) onChange(color)
  }
  for (const color of PRESET_COLORS) {
    const s = el('button')
    s.type = 'button'
    s.dataset.color = color
    s.style.setProperty('--swatch', color)
    s.setAttribute('aria-label', `颜色 ${color}`)
    s.onclick = () => set(color, true)
    swatches.push(s)
    root.append(s)
  }
  custom.oninput = () => set(custom.value, true)
  root.append(custom)
  mark()
  return {
    root,
    get value() {
      return value
    },
    set(color: string) {
      set(color, false)
    },
  }
}
/** 正在进行的交谈或同行（同一时刻最多一场；同行是路上也能说话的交谈） */
export function runningTalk(state: AvatarState | null): AvatarInteraction | undefined {
  return state?.interactions?.find(
    (i) => i.status === 'running' && (i.kind.kind === 'talk' || i.kind.kind === 'walk')
  )
}
/** 正在进行的同行：谁带路、去哪、谁跟着；不在同行里为空 */
export function runningWalk(state: AvatarState | null) {
  const talk = runningTalk(state)
  const kind = talk?.kind
  if (!talk || kind?.kind !== 'walk') return undefined
  const me = state?.actor?.id
  const followers = (talk.members ?? []).filter((id) => id !== kind.leader)
  return {
    talk,
    leader: kind.leader,
    locale: kind.locale,
    leading: kind.leader === me,
    followers,
  }
}
/** 同一对人尚未回应的交谈或同行邀请，双方都不重复发起。 */
export function pendingTalk(state: AvatarState, other: string): AvatarInteraction | undefined {
  const me = state.actor?.id
  return state.interactions?.find(
    (i) =>
      (i.kind.kind === 'talk' || i.kind.kind === 'walk') &&
      i.status === 'offered' &&
      ((i.initiator === me && i.partner === other) || (i.partner === me && i.initiator === other))
  )
}
/** 交谈里对方的名字；多人时用顿号连接 */
export function partnerNames(state: AvatarState, talk: AvatarInteraction) {
  const me = state.actor?.id
  const ids = (talk.members ?? [talk.initiator, talk.partner]).filter((id) => id !== me)
  return ids.map((id) => personName(state, talk, id)).join('、') || '对方'
}
/** 一个人的名字：附近的人或交谈记录里有就用，否则叫「对方」；是自己时为「你」 */
export function personName(state: AvatarState, talk: AvatarInteraction | undefined, id: string) {
  if (id === state.actor?.id) return '你'
  return (
    state.nearby?.find((n) => n.id === id)?.name ??
    talk?.entries?.find((e) => e.actor === id)?.name ??
    state.interactions?.flatMap((i) => i.entries ?? []).find((e) => e.actor === id)?.name ??
    '对方'
  )
}
