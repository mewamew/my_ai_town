// 化身界面的节点与事件绑定；世界状态留在控制器里。
import type { AvatarLook } from './types'
import { gameIcon, iconLabel } from '../game/icons'
import { createAvatarEntry } from './entry'
import { lookChoice, type LookChoice } from './looks'
import { actionButton, field, keycap } from './view'
import { button, el } from '../dom'
import { isTouch } from '../platform'
import type { AvatarActions } from './ui-types'

/** 状态面板里常驻的形象表单：不随重绘重建，避免丢焦点 */
function profileForm(choice: LookChoice, initial: string, execute: AvatarActions['execute']) {
  const profile = el('form')
  profile.className = 'avatar-profile'
  const profileName = el('input')
  profileName.maxLength = 24
  profileName.required = true
  profileName.setAttribute('aria-label', '化身名字')
  const profilePicker = choice.picker(initial, () => {})
  const save = el('button', '保存形象')
  save.type = 'submit'
  profile.append(
    el('h4', '形象与名字'),
    field('名字', profileName),
    field(choice.caption, profilePicker.root),
    save
  )
  profile.onsubmit = (e) => {
    e.preventDefault()
    void execute(choice.command('profile', profileName.value, profilePicker.value))
  }
  return { profile, profileName, profilePicker }
}

/** 操作条上「⋯」展开的菜单 */
function moreMenu(h: AvatarActions, profile: HTMLElement) {
  const menu = el('div')
  menu.className = 'avatar-menu'
  menu.hidden = true
  menu.setAttribute('role', 'menu')
  const moreBtn = actionButton('⋯', undefined, () => {
    menu.hidden = !menu.hidden
  })
  moreBtn.classList.add('avatar-more')
  moreBtn.setAttribute('aria-label', '更多')
  moreBtn.setAttribute('aria-haspopup', 'menu')
  const menuItem = (text: string, action: () => void, className = '') => {
    const b = button(text, () => {
      menu.hidden = true
      action()
    })
    b.className = className
    b.setAttribute('role', 'menuitem')
    menu.append(b)
    return b
  }
  menuItem('交谈与邀请', () => h.openTab('chat'))
  menuItem('完整交谈记录', () => {
    h.stopMoving()
    h.showHistory()
  })
  const profileMenu = menuItem('形象与名字', () => {
    h.openTab('status')
    profile.scrollIntoView({ block: 'nearest' })
  })
  const leaveMenu = menuItem('退出化身', () => void h.leave(), 'avatar-danger')
  return { menu, moreBtn, profileMenu, leaveMenu }
}

/** 操作条：我是谁在哪 · 当前主动作 · 背包 · 状态 · 更多。
 *  badge 是游戏界面挂在 root 最前面的徽章和「离开小镇」槽钮。 */
function hudBar(h: AvatarActions, profile: HTMLElement, game: boolean) {
  const hud = el('div')
  hud.className = 'avatar-hud'
  const me = el('div'),
    meDot = el('i'),
    meText = el('div'),
    meName = el('b'),
    meSub = el('small')
  me.className = 'avatar-me'
  meDot.className = 'avatar-dot'
  meText.append(meName, meSub)
  me.append(meDot, meText)
  const mid = el('div')
  mid.className = 'avatar-mid'
  const icon = (name: string) => (game ? gameIcon(name) : null)
  const bagBtn = actionButton('背包', 'B', () => h.toggleTab('bag'), icon('bag'))
  // 触屏时背包钮在右下的动作区，操作条上不再放
  bagBtn.classList.add('avatar-bag-btn')
  const bagCount = el('small')
  bagBtn.append(bagCount)
  const statusBtn = actionButton('状态', undefined, () => h.toggleTab('status'), icon('status'))
  const releaseBtn = actionButton('交还 AI', undefined, () => void h.leave(), icon('eye'))
  releaseBtn.hidden = true
  const { menu, moreBtn, profileMenu, leaveMenu } = moreMenu(h, profile)
  const chatBtn = actionButton('交谈', 'E', () => h.toggleTab('chat'))
  const cameraBtn = actionButton('镜头回正', 'V', h.resetCamera)
  // 化身神力开着时才出现：点它（或按 F）对当前对象施展；触屏没有键盘，不画 F
  const miracleBtn = actionButton(
    '神力',
    isTouch() ? undefined : 'F',
    () => h.miracleMenu(),
    gameIcon('spark', true)
  )
  miracleBtn.classList.add('avatar-miracle')
  miracleBtn.hidden = true
  miracleBtn.title = '对身边的人复活、治愈、补满'
  // 神力的选项单：浮在操作条上方，选了就走过去施展
  const miracles = el('div')
  miracles.className = 'avatar-miracles'
  miracles.hidden = true
  miracles.setAttribute('role', 'menu')
  // 原型附身模式：热栏上方的四条需求数值条
  const needsStrip = el('div')
  needsStrip.className = 'avatar-needs'
  needsStrip.hidden = true
  const badge: HTMLElement[] = []
  if (game) {
    // 徽章挂到 root：hotbar 的 backdrop-filter 会把 fixed 定位拉进热栏里。
    // 徽章下方是「离开小镇」槽钮（与 Esc 同等）
    const leaveSlot = actionButton('离开小镇', 'Esc', () => void h.leave())
    leaveSlot.classList.add('avatar-leave')
    leaveSlot.title = '离开小镇（Esc）'
    badge.push(me, leaveSlot)
    hud.append(mid, miracleBtn, chatBtn, bagBtn, statusBtn, cameraBtn, releaseBtn, moreBtn)
  } else {
    chatBtn.hidden = true
    cameraBtn.hidden = true
    hud.append(me, mid, miracleBtn, bagBtn, statusBtn, releaseBtn, moreBtn)
  }
  hud.append(menu, miracles)
  return {
    hud,
    badge,
    me,
    meDot,
    meName,
    meSub,
    mid,
    bagCount,
    needsStrip,
    buttons: { chat: chatBtn, bag: bagBtn, status: statusBtn, camera: cameraBtn },
    miracleBtn,
    miracles,
    releaseBtn,
    moreBtn,
    menu,
    profileMenu,
    leaveMenu,
  }
}

/** 右侧面板：交谈 / 背包 / 状态；交谈时底部有输入框，Enter 发送 */
function sidePanel(signal: AbortSignal, { closeTab, speak }: AvatarActions, game: boolean) {
  const panel = el('aside')
  panel.className = 'avatar-panel'
  panel.hidden = true
  const head = el('div')
  head.className = 'avatar-panel-head'
  const title = el('b'),
    meta = el('small')
  const close = button('收起', () => closeTab())
  close.className = 'avatar-panel-close'
  if (game) iconLabel(close, 'back', '返回游戏 · Esc', true)
  else close.append(keycap('Esc'))
  head.append(title, meta, close)
  const body = el('div')
  body.className = 'avatar-panel-body'
  const composer = el('form'),
    draft = el('textarea')
  composer.className = 'avatar-composer'
  composer.hidden = true
  draft.placeholder = '输入想说的话，打字时不会移动'
  draft.maxLength = 600
  draft.rows = 2
  draft.setAttribute('aria-label', '交谈内容')
  const say = el('button', '发送')
  say.type = 'submit'
  say.className = 'avatar-send'
  say.append(keycap('⏎'))
  composer.append(draft, say)
  composer.onsubmit = (e) => {
    e.preventDefault()
    void speak()
  }
  draft.addEventListener(
    'keydown',
    (e) => {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
        e.preventDefault()
        void speak()
      }
    },
    { signal }
  )
  panel.append(head, body, composer)
  return { panel, title, meta, body, composer, draft, say }
}

/** 提示条：点一下或到时收起；sticky 的只在点击或下一条提示时收起 */
function toastBar() {
  const toast = el('div')
  toast.className = 'avatar-toast'
  toast.hidden = true
  toast.setAttribute('role', 'status')
  toast.onclick = () => hideToast()
  let toastTimer = 0
  function showToast(text: string, sticky = false, duration = 2600) {
    window.clearTimeout(toastTimer)
    toast.textContent = text
    toast.classList.toggle('sticky', sticky)
    toast.hidden = false
    if (!sticky) toastTimer = window.setTimeout(hideToast, duration)
  }
  function hideToast() {
    window.clearTimeout(toastTimer)
    toast.hidden = true
  }
  return { toast, showToast, hideToast }
}

export function createAvatarUI(
  mapEl: HTMLElement,
  signal: AbortSignal,
  actions: AvatarActions,
  /** 地图给出的像素小人外观；有就挑外观，没有就挑颜色 */
  looks: AvatarLook[] | null,
  /** 游戏界面 */
  game: boolean
) {
  const root = el('div')
  root.className = 'avatar-ui'
  root.hidden = true
  const choice = lookChoice(looks)
  const entry = createAvatarEntry(choice, actions)
  const profile = profileForm(choice, entry.picker.value, actions.execute)
  const { badge, ...hud } = hudBar(actions, profile.profile, game)
  const side = sidePanel(signal, actions, game)
  const { toast, showToast, hideToast } = toastBar()
  // 拖动地图脱离跟随后，用它（或按 C）重新跟上化身；一开始走也会自动跟上
  const back = button('', () => actions.follow())
  back.append(...(isTouch() ? [] : [keycap('C')]), el('span', '回到化身'))
  back.className = 'avatar-return'
  root.append(...badge, hud.needsStrip, hud.hud, side.panel, toast, back, entry.backdrop)
  mapEl.append(root)
  // 「进入化身」放进底部正中那一排格子，在道具和书报中间；外壳没有那一排时留在化身界面里
  const books = mapEl.querySelector('.map-hotbar #open-books')
  if (books) books.before(entry.pill)
  else root.append(entry.pill)
  return {
    root,
    entry,
    ...hud,
    ...side,
    ...profile,
    back,
    showToast,
    hideToast,
    paintDot: choice.paintDot,
  }
}
export type AvatarUI = ReturnType<typeof createAvatarUI>

/** 化身界面的指针事件：不漏给地图；单指或左键拖动地图超过 6 像素算脱离跟随（右键转视角、
 *  双指缩放和调俯角都不算，镜头照样跟着人）；点操作条外面收起菜单 */
export function guardPointer(
  ui: AvatarUI,
  mapEl: HTMLElement,
  signal: AbortSignal,
  onDragAway: () => void
) {
  // 界面上的按下、双击、滚轮不能漏给地图，否则会被当成拖拽或缩放
  for (const event of ['pointerdown', 'dblclick', 'wheel'])
    ui.root.addEventListener(event, (e) => e.stopPropagation(), { signal })
  let dragStart: [number, number] | null = null
  const down = new Set<number>()
  mapEl.addEventListener(
    'pointerdown',
    (e) => {
      down.add(e.pointerId)
      const onUi = e.target instanceof Node && ui.root.contains(e.target)
      dragStart = onUi || e.button !== 0 || down.size > 1 ? null : [e.clientX, e.clientY]
    },
    { signal }
  )
  for (const type of ['pointerup', 'pointercancel'])
    mapEl.addEventListener(type, (e) => down.delete((e as PointerEvent).pointerId), { signal })
  mapEl.addEventListener(
    'pointermove',
    (e) => {
      if (!dragStart || !(e.buttons & 1) || down.size > 1) return
      if (Math.hypot(e.clientX - dragStart[0], e.clientY - dragStart[1]) <= 6) return
      dragStart = null
      onDragAway()
    },
    { signal }
  )
  document.addEventListener(
    'click',
    (e) => {
      const onHud = e.target instanceof Node && ui.hud.contains(e.target)
      if (!ui.menu.hidden && !onHud) ui.menu.hidden = true
      if (!ui.miracles.hidden && !onHud) ui.miracles.hidden = true
    },
    { signal }
  )
}

/** Esc 依次收起菜单、侧面板、进入对话框，都没开着时退出化身；页面上有打开的 dialog
 *  或焦点在输入框里时不处理 */
export function escapeKey(
  ui: AvatarUI,
  signal: AbortSignal,
  closeTab: () => void,
  closeDialog: () => void,
  leave: (() => void) | null
) {
  window.addEventListener(
    'keydown',
    (event) => {
      if (event.key !== 'Escape' || document.querySelector('dialog[open]')) return
      const typing = document.activeElement?.matches('input, textarea, select')
      if (!ui.menu.hidden) ui.menu.hidden = true
      else if (!ui.miracles.hidden) ui.miracles.hidden = true
      else if (!ui.panel.hidden) closeTab()
      else if (ui.entry.isOpen()) closeDialog()
      else if (leave && !typing && !ui.hud.hidden) leave()
      else return
      event.preventDefault()
    },
    { signal }
  )
}
