// 手机布局的外框：底部六个入口、「更多」抽屉、地图右上角的两个圆钮，以及把村民卡变成底部抽屉。
// 宽屏时这些节点由样式隐藏，桌面界面不变。开始/暂停钮手机和电脑共用（shell/topbar.ts）。
// 应用切到后台时让世界暂停，回来恢复原来的速度。
import { $, button, el } from '../dom'
import { countBadge } from '../design/ui'
import type { EventsHandle } from '../events'
import { gameIcon } from '../game/icons'
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
  open: { residents(): void; props(): void; books(): void; usage(): void; placing(): void }
  /** 「书报」上的数字：没看过的新作品 */
  watchBooks: (update: (count: number) => void) => void
  openSettings: () => void
  avatar: { openEntry(): void; available(): boolean; active(): boolean }
  audio: {
    music: { enabled(): boolean; toggle(): void }
    effects: { enabled(): boolean; toggle(): void }
  }
  /** 重新看开局向导 */
  openGuide?: () => void
  /** 新手提示从头再出一遍 */
  resetTips?: () => void
}

export function installMobileChrome(d: ChromeDeps) {
  const obsView = $('obs-view')
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
  const entry = (name: string, icon: string, label: string, action: () => void) => {
    const b = button('', action)
    b.dataset.dock = name
    b.append(gameIcon(icon, true), el('span', label))
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
  const avatarBtn = entry('avatar', 'person', '化身', () => {
    closePopover()
    // 进入对话框在地图中间，先收起压在它上面的村民卡和事件列表
    d.infoPanel.collapse()
    d.events.collapse()
    syncDock()
    d.avatar.openEntry()
  })
  avatarBtn.classList.add('dock-avatar')
  entry('props', 'hand', '物品', () => {
    closePopover()
    d.open.props()
  })
  const booksBtn = entry('books', 'book', '书报', () => {
    closePopover()
    d.open.books()
  })
  d.watchBooks(countBadge(booksBtn, '书报'))
  const moreBtn = entry('more', 'more', '更多', () =>
    popover?.el === more ? closePopover() : openMore()
  )
  $('event-bar').after(dock)
  function syncDock() {
    eventsBtn.classList.toggle('on', d.events.expanded())
    moreBtn.classList.toggle('on', popover?.el === more)
    avatarBtn.disabled = !d.avatar.available()
  }

  // ---------- 「更多」抽屉 ----------
  const more = el('div', '', 'm-pop m-more')
  more.id = 'mobile-more'
  more.hidden = true
  const shade = el('div', '', 'm-shade')
  shade.hidden = true
  shade.onclick = () => closePopover()
  obsView.append(shade, more)
  const click = (id: string) => () => {
    closePopover()
    document.getElementById(id)?.click()
  }
  function openMore() {
    closePopover()
    const tile = (icon: string, label: string, action: () => void, state?: string) => {
      const b = button('', action)
      b.className = 'm-tile'
      b.append(gameIcon(icon, true), el('span', label))
      if (state) b.append(el('small', state))
      return b
    }
    const toggle = (which: 'music' | 'effects') => () => {
      d.audio[which].toggle()
      openMore()
    }
    const tiles = el('div', '', 'm-tiles')
    tiles.append(
      tile('settings', '设定', () => {
        closePopover()
        d.openSettings()
      }),
      tile('chart', '消耗', () => {
        closePopover()
        d.open.usage()
      }),
      tile('plus', '摆道具', () => {
        closePopover()
        d.open.placing()
      }),
      tile('sound', '音乐', toggle('music'), d.audio.music.enabled() ? '开' : '关'),
      tile('sound', '音效', toggle('effects'), d.audio.effects.enabled() ? '开' : '关'),
      tile('map', '选择小镇', click('back-to-maps'))
    )
    more.replaceChildren(el('div', '', 'm-grip'), el('h2', '更多'), tiles)
    for (const [label, action] of [
      ['重新看开局向导', d.openGuide],
      ['重新显示新手提示', d.resetTips],
    ] as const) {
      if (!action) continue
      const row = button(label, () => {
        closePopover()
        action()
      })
      row.className = 'm-row'
      more.append(row)
    }
    more.hidden = false
    shade.hidden = false
    popover = {
      el: more,
      close: () => {
        more.hidden = true
        shade.hidden = true
      },
    }
    syncDock()
  }

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
  // 聊天记录是村民卡里的一整页，头部和把手都让给它：打开时拉到全屏，退回村民信息时回到原来的档
  let beforeChat: Snap | null = null
  new MutationObserver(() => {
    const chat = panel.classList.contains('chat-open')
    if (wasHidden && !panel.hidden) {
      d.events.collapse()
      syncDock()
      beforeChat = chat ? 'peek' : null
      // 先按默认高度排出头部，下一帧再量露头档
      requestAnimationFrame(() => sheet.open(chat ? 'full' : 'peek'))
    } else if (chat && !beforeChat) {
      beforeChat = sheet.snap()
      sheet.set('full')
    } else if (!chat && beforeChat) {
      if (!panel.hidden) sheet.set(beforeChat)
      beforeChat = null
    }
    wasHidden = panel.hidden
  }).observe(panel, { attributes: true, attributeFilter: ['hidden', 'class'] })
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
    },
  }
}
