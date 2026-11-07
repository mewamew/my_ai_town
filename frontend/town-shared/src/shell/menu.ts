// 右上角「菜单」：一级入口以外的都在这里——世界观（左上角也有）、居民、设定、消耗、帮助、选择小镇，加音乐、音效开关。
// 格子写在 shell/plain.html 里；设定、消耗、选择小镇、声音的点击由各自的模块接（id 没变），这里只管开合和其余几格。
// 电脑挂在菜单钮下面，手机从底部弹出（手机的菜单钮在底部入口里，见 mobile/chrome.ts）。打开不暂停世界。
// Esc：面板、对话框、道具浮窗、化身先用掉它；什么都没开时打开菜单，开着时关上。
import { $ } from '../dom'
import { isCompact } from '../platform'
import { createMenuHelp } from './help'

export interface GameMenuDeps {
  openTown: () => void
  openResidents: () => void
  help: { openGuide: () => void; resetTips: () => void }
  /** 打开前停下化身：按着的方向键松开 */
  onOpen: () => void
}

/** 按下 Esc 那一刻有没有别的东西开着：开着的话 Esc 是关它的，不来开菜单 */
function somethingOpen() {
  const active = document.activeElement
  return (
    !!document.querySelector(
      'dialog[open], .start-ask, .prop-card:not([hidden]), .page-view:not([hidden]), #props-view:not([hidden])'
    ) ||
    $('obs-view').hidden ||
    document.documentElement.classList.contains('avatar-controlling') ||
    !!active?.matches('input, textarea, select, [contenteditable="true"]') ||
    $('open-props').getAttribute('aria-pressed') === 'true'
  )
}

export function createGameMenu(deps: GameMenuDeps) {
  const menu = $('game-menu')
  const shade = $('game-menu-shade')
  const trigger = $('open-menu')
  const grid = $('game-menu-grid')
  const helpBox = $('game-menu-help')
  const listeners = new Set<() => void>()
  const notify = () => listeners.forEach((listener) => listener())

  const help = createMenuHelp(helpBox, deps.help, { back: showGrid, close })
  function showGrid() {
    helpBox.hidden = true
    grid.hidden = false
    grid.querySelector<HTMLButtonElement>('#open-help')?.focus({ preventScroll: true })
  }
  /** 挂在菜单钮下面、右边对齐；手机上由样式贴底 */
  function place() {
    if (isCompact()) return
    const r = trigger.getBoundingClientRect()
    if (!r.width) return
    menu.style.setProperty('--menu-top', `${Math.round(r.bottom + 8)}px`)
    menu.style.setProperty('--menu-right', `${Math.max(8, Math.round(innerWidth - r.right))}px`)
  }
  function open() {
    if (!menu.hidden) return
    deps.onOpen()
    helpBox.hidden = true
    grid.hidden = false
    place()
    menu.hidden = false
    shade.hidden = false
    trigger.setAttribute('aria-expanded', 'true')
    notify()
  }
  function close() {
    if (menu.hidden) return
    const inside = menu.contains(document.activeElement)
    menu.hidden = true
    shade.hidden = true
    trigger.setAttribute('aria-expanded', 'false')
    if (inside && trigger.offsetParent) trigger.focus({ preventScroll: true })
    notify()
  }
  const toggle = () => (menu.hidden ? open() : close())

  trigger.onclick = toggle
  shade.onclick = close
  // 点了格子先关菜单，再做那一格的事；「帮助」在菜单里换一页，不关
  grid.addEventListener('click', (event) => {
    const item = event.target instanceof Element ? event.target.closest('button') : null
    if (item && item.id !== 'open-help') close()
  })
  $('menu-town').onclick = deps.openTown
  $('menu-residents').onclick = deps.openResidents
  $('open-help').onclick = () => {
    grid.hidden = true
    helpBox.hidden = false
    help.show()
  }
  window.addEventListener('resize', place)

  // 先在捕获阶段记下按下那一刻的样子，等这次按键处理完再决定：别处用掉了 Esc（preventDefault）就不管
  window.addEventListener(
    'keydown',
    (event) => {
      if (event.key !== 'Escape' || event.repeat || event.isComposing) return
      if (!menu.hidden) {
        // 菜单开着时这次 Esc 只关菜单：不再往下传，免得化身那边接着把控制交还
        event.preventDefault()
        event.stopPropagation()
        if (!helpBox.hidden) showGrid()
        else close()
        return
      }
      if (somethingOpen()) return
      setTimeout(() => {
        if (!event.defaultPrevented && menu.hidden) open()
      })
    },
    true
  )
  return {
    open,
    close,
    toggle,
    isOpen: () => !menu.hidden,
    /** 开合变了：手机底部入口的「菜单」跟着亮 */
    onChange(listener: () => void) {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
  }
}
export type GameMenu = ReturnType<typeof createGameMenu>
