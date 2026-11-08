// 手机布局的外框：底部六个入口、地图右上角的两个圆钮，以及把村民卡变成底部抽屉。最右边的「菜单」打开的
// 是电脑右上角同一块菜单，从底部弹出。宽屏时这些节点由样式隐藏。时钟牌、开始钮、世界观手机和电脑共用。
// 应用切到后台时让世界暂停，回来恢复原来的速度。
import { $, button, el } from '../dom'
import { countBadge } from '../design/ui'
import type { EventsHandle } from '../events'
import { gameIcon } from '../game/icons'
import { pixelIcon, type PixelName } from '../game/pixel'
import { isCompact, onBack, onLifecycle } from '../platform'
import type { SpeedBar } from '../shell/topbar'
import { bottomSheet, type Snap } from './sheet'
import './style.css'

interface ChromeDeps {
  speeds: SpeedBar
  /** 世界观已设好、连接正常：切回前台时才恢复速度 */
  worldReady: () => boolean
  events: EventsHandle
  infoPanel: {
    collapse(): void
    isCollapsed(): boolean
    cycle(step: 1 | -1): void
  }
  /** 村民卡里的聊天记录：开着时返回键先关它 */
  chatHistory: { back(): boolean }
  open: { residents(): void; props(): void; books(): void; usage(): void }
  /** 「书报」上的数字：没看过的新作品 */
  watchBooks: (update: (count: number) => void) => void
  /** 底部「菜单」打开的就是电脑右上角那块菜单（shell/menu.ts），从底部弹出 */
  menu: {
    toggle(): void
    close(): void
    isOpen(): boolean
    onChange(listener: () => void): () => void
  }
  avatar: { openEntry(): void; available(): boolean; active(): boolean }
}

export function installMobileChrome(d: ChromeDeps) {
  const listeners = new AbortController()
  const { signal } = listeners
  // 一次只开一个浮层；返回键先关它
  let popover: { el: HTMLElement; close(): void } | null = null
  const closePopover = () => {
    if (!popover) return false
    popover.close()
    popover = null
    syncDock()
    return true
  }

  // ---------- 底部六个入口 ----------
  const dock = el('nav', '', 'mobile-dock')
  dock.id = 'mobile-dock'
  dock.setAttribute('aria-label', '主要入口')
  // 底部入口的图标和电脑上的一样，是平涂像素画（地图右上角的两个圆钮仍用线条图标）
  const entry = (name: string, icon: PixelName, label: string, action: () => void) => {
    const b = button('', action)
    b.dataset.dock = name
    b.append(pixelIcon(icon), el('span', label))
    dock.append(b)
    return b
  }
  entry('residents', 'people', '居民', () => {
    closePopover()
    d.open.residents()
  })
  const eventsBtn = entry('events', 'chat', '动态', () => {
    closePopover()
    if (d.events.expanded()) d.events.collapse()
    else {
      d.infoPanel.collapse()
      d.events.expand()
    }
    syncDock()
  })
  const avatarBtn = entry('avatar', 'avatar', '化身', () => {
    closePopover()
    // 进入对话框在地图中间，先收起压在它上面的村民卡和事件列表
    d.infoPanel.collapse()
    d.events.collapse()
    syncDock()
    d.avatar.openEntry()
  })
  avatarBtn.classList.add('dock-avatar')
  entry('props', 'chest', '道具', () => {
    closePopover()
    d.open.props()
  })
  const booksBtn = entry('books', 'book', '书报', () => {
    closePopover()
    d.open.books()
  })
  d.watchBooks(countBadge(booksBtn, '书报'))
  const menuBtn = entry('menu', 'bars', '菜单', () => {
    closePopover()
    d.menu.toggle()
  })
  $('event-bar').after(dock)
  function syncDock() {
    eventsBtn.classList.toggle('on', d.events.expanded())
    menuBtn.classList.toggle('on', d.menu.isOpen())
    avatarBtn.disabled = !d.avatar.available()
  }
  const offMenu = d.menu.onChange(syncDock)

  // ---------- 地图右上角：回到整图、俯角 ----------
  const zoom = document.querySelector<HTMLElement>('.map-zoom')
  const fabs = el('div', '', 'map-fabs')
  fabs.id = 'map-fabs'
  const fit = button('', () => {
    closePopover()
    zoom?.querySelector<HTMLButtonElement>('.zoom-readout')?.click()
  })
  fit.append(gameIcon('fit', true))
  fit.setAttribute('aria-label', '回到整图')
  fit.title = '回到整图'
  const tilt = button('', () => {
    if (popover?.el === zoom) return void closePopover()
    closePopover()
    if (!zoom) return
    zoom.classList.add('show-pitch')
    popover = { el: zoom, close: () => zoom.classList.remove('show-pitch') }
  })
  tilt.append(gameIcon('tilt', true))
  tilt.setAttribute('aria-label', '俯角')
  tilt.title = '俯角：也可以两根手指同时上下拖动'
  fabs.append(fit, tilt)
  // 圆钮上的按下不能漏给地图，否则会被当成拖动的起点
  for (const type of ['pointerdown', 'dblclick'])
    fabs.addEventListener(type, (e) => e.stopPropagation(), { signal })
  $('map').append(fabs)
  // 俯角滑杆是立体场景加载后才放进缩放钮的；没有立体场景时不显示这个圆钮
  const syncTilt = () => (tilt.hidden = !zoom?.querySelector('.map-pitch'))
  syncTilt()
  if (zoom) new MutationObserver(syncTilt).observe(zoom, { childList: true })

  // ---------- 村民卡：底部抽屉 ----------
  const panel = $('info-panel')
  const head = $('info-head')
  const sheet = bottomSheet({
    panel,
    head,
    // 露头档露到名字和住处为止；底部按钮吸底盖在内容上，也要算进去，不然名字正好被它挡住
    peekHeight: () => {
      const who = document.getElementById('info-who')
      const actions = document.getElementById('info-actions')
      const top = panel.getBoundingClientRect().top
      const bottom = who?.getBoundingClientRect().bottom ?? top + 140
      const bar = actions?.offsetHeight ?? 0
      const most = Math.max(200, $('obs-main').clientHeight * 0.55)
      // 抽屉滚动过时，想法在内容里的位置要加回滚动距离
      return Math.max(132, Math.min(most, bottom - top + panel.scrollTop + 12 + bar))
    },
    maxHeight: () => $('obs-main').clientHeight - 8,
    onClose: () => d.infoPanel.collapse(),
    onSwipe: (step) => d.infoPanel.cycle(step),
  })
  let wasHidden = panel.hidden
  // 聊天记录是村民卡里的一整页，人设、长相、模型页签要地方编辑：打开时拉到全屏，
  // 退回近况时回到原来的档
  const wantsFull = () =>
    panel.classList.contains('chat-open') || (panel.dataset.tab ?? 'status') !== 'status'
  let beforeFull: Snap | null = null
  new MutationObserver(() => {
    const full = wantsFull()
    if (wasHidden && !panel.hidden) {
      // 电脑上贴边的动态是地图旁边的一整列，和角色卡并排，不收
      if (!$('obs-view').dataset.feedDock) d.events.collapse()
      syncDock()
      beforeFull = full ? 'peek' : null
      // 先按默认高度排出头部，下一帧再量露头档
      requestAnimationFrame(() => sheet.open(wantsFull() ? 'full' : 'peek'))
    } else if (full && !beforeFull) {
      beforeFull = sheet.snap()
      sheet.set('full')
    } else if (!full && beforeFull) {
      if (!panel.hidden) sheet.set(beforeFull)
      beforeFull = null
    }
    wasHidden = panel.hidden
  }).observe(panel, { attributes: true, attributeFilter: ['hidden', 'class', 'data-tab'] })
  // 住处、想法晚一步填上或换了长短：露头档跟着重新量，免得把一行字切成两半
  let remeasure = 0
  new MutationObserver(() => {
    if (remeasure || panel.hidden || sheet.snap() !== 'peek') return
    remeasure = requestAnimationFrame(() => {
      remeasure = 0
      if (!panel.classList.contains('dragging')) sheet.refresh()
    })
  }).observe(panel, { childList: true, characterData: true, subtree: true })
  window.addEventListener('resize', () => sheet.refresh(), { signal })

  // ---------- 返回键：先关这一层的浮层、事件列表与村民卡 ----------
  const unregister = onBack(() => {
    if (!isCompact()) return false
    if (closePopover()) return true
    if (d.menu.isOpen()) {
      d.menu.close()
      return true
    }
    if (d.events.expanded()) {
      d.events.collapse()
      syncDock()
      return true
    }
    if (d.chatHistory.back()) return true
    if (!d.infoPanel.isCollapsed()) {
      d.infoPanel.collapse()
      return true
    }
    return false
  })

  // ---------- 前后台：切走就暂停，回来恢复原来的速度 ----------
  let pausedAt = 0
  const offLifecycle = onLifecycle((state) => {
    if (state === 'pause') {
      const now = d.speeds.current()
      if (now > 0 && d.worldReady()) {
        pausedAt = now
        d.speeds.choose(0)
      }
    } else if (pausedAt) {
      d.speeds.choose(pausedAt)
      pausedAt = 0
    }
  })

  syncDock()
  const timer = window.setInterval(syncDock, 1000)
  return {
    syncDock,
    dispose() {
      listeners.abort()
      clearInterval(timer)
      unregister()
      offLifecycle()
      offMenu()
    },
  }
}
