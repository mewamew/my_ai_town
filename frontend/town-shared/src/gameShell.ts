// 游戏页外壳：定界面类型、放界面部件、建连接和各面板，服务端消息按面板登记顺序分发。
// 地图页 ⇄ 设定中心视图切换（进入设定暂停模拟，返回恢复进入前速度）。
// 静态图集先画（ws 断了图也在），Roster 流驱动活物层与各面板；人物身份只来自服务器名册。
import './style.css'
import { createGameAudio } from './audio/controller'
import { createConnection } from './connection'
import { $, query } from './dom'
import { initEvents } from './events'
import type { GameMap } from './gameMap'
import type { MapEntry, Topology } from './mapDocument'
import { installLayout } from './shell/layout'
import { createPanels, type Panels } from './shell/panels'
import { createReconnectHint } from './shell/reconnect'
import { installHelpMenu } from './shell/help'
import { installMapButtons, showConnection } from './shell/topbar'
import { reopenTown } from './townApi'
import { installMobileChrome } from './mobile/chrome'
import { createGuide, guideDone } from './mobile/guide'
import { createTips } from './mobile/tips'
import { trackMapInsets } from './mapView'
import { onBack, systemBars } from './platform'
import { useTownCreation } from './townWorldview'

export function startGameShell(
  selectedMap: MapEntry,
  map: GameMap,
  topology: Topology,
  decorate: () => void,
  options: { normalSpeed?: number } = {}
) {
  // 界面类型只在这里定一次，作为参数交给各面板
  const game = false
  installLayout()
  $('app-title').textContent = selectedMap.name
  document.title = `${selectedMap.name} · AI小镇`
  const listeners = new AbortController()
  const events = initEvents(game)
  const audio = createGameAudio(
    query<HTMLButtonElement>(document, '#music-toggle'),
    query<HTMLButtonElement>(document, '#effects-toggle')
  )
  const localeName = (id: string) =>
    topology.locales.find((l) => l.id === id)?.name ??
    // 落脚点 ID（place_arrival_*）经处所的 arrival_station 反查中文名
    topology.places.find((p) => p.arrival_station === id)?.name ??
    id
  const reconnect = createReconnectHint($('map'))
  // 连接的回调只在 connect() 之后触发，那时面板都已建好
  const connection = createConnection(
    selectedMap.endpoint,
    {
      message: (message) => panels.registry.dispatch(message),
      connected(recovered) {
        showConnection(true)
        if (recovered) {
          reconnect.back()
          events.pushLocal('已重新连上小镇')
        }
        panels.registry.connected()
      },
      disconnected() {
        showConnection(false)
        reconnect.lost()
        events.pushLocal('小镇的连接断了，正在重新连接')
        panels.registry.disconnected()
      },
      reopening: () => reconnect.reopening(),
      // 另一个页面进了别的小镇：说清原因，玩家点「回到这个小镇」才重新打开（会挤掉那边）
      displaced: (message) =>
        reconnect.displaced(message, async () => {
          const entry = await reopenTown(selectedMap.id, false)
          if (entry.mapHash !== selectedMap.mapHash) throw new Error('地图已变化')
          selectedMap.endpoint = entry.endpoint
          selectedMap.lease = entry.lease
          connection.resume(entry.endpoint)
        }),
      local: (text, warning) => events.pushLocal(text, warning),
    },
    { townId: selectedMap.id, mapHash: selectedMap.mapHash },
    // 世界进程不在了：请管理服务从存档重新打开，换新地址接着连；之后离开时用新的打开凭证关
    async () => {
      const entry = await reopenTown(selectedMap.id)
      if (entry.mapHash !== selectedMap.mapHash) throw new Error('地图已变化')
      selectedMap.endpoint = entry.endpoint
      selectedMap.lease = entry.lease
      return entry.endpoint
    }
  )
  const normalSpeed = options.normalSpeed ?? 1
  // 一句话建的小镇：世界观建议给首次对话框和开局向导，适合住进来的人给向导
  useTownCreation(selectedMap.id, selectedMap.creation)
  const inputs = { normalSpeed, game, selectedMap, map, events, localeName, topology }
  const panels = createPanels({
    ...inputs,
    send: connection.send,
    save: connection.save,
    audio,
  })
  installMapButtons(
    panels.open,
    panels.books.watch,
    panels.props.placing?.watch ?? null,
    listeners.signal
  )
  const tips = createTips(map)
  panels.registry.add(tips.panel)
  wireMap(map, panels, tips.picked)
  systemBars('paper')
  // 开局向导：第一次进新世界时代替首次对话框，手机和电脑一样；手机在「更多」、电脑在顶栏「帮助」里重新打开
  const guide = createGuide({
    send: connection.send,
    save: connection.save,
    suggestions: selectedMap.creation?.residents ?? [],
    townName: selectedMap.name,
    description: selectedMap.creation?.description ?? '',
    worldSettings: panels.worldSettings,
    speeds: panels.speeds,
    normalSpeed,
    onFinish: (_started, joined) => {
      tips.start()
      lookAt(joined[0])
    },
  })
  /** 新居民从入口进镇：镜头挪过去。名册可能晚一帧才带上新人，等一会儿再找 */
  function lookAt(id: string | undefined, tries = 20) {
    if (!id) return
    const at = map.getMemberPos(id)
    if (at) map.panTo(at[0], at[1])
    else if (tries > 0) setTimeout(() => lookAt(id, tries - 1), 100)
  }
  panels.registry.first(guide.panel)
  // 回来的玩家（向导已走过）直接从手势提示开始；看过的提示不会再出
  if (guideDone()) tips.start()
  let guideOpened = false
  // 每个新世界（还没设世界观）都走向导：第一次从头讲起，以后从「请居民」开始
  panels.worldSettings.setFirstRun(() => {
    if (!guideOpened) {
      guideOpened = true
      // 在设定里重置了世界：先回到地图，向导走完正好看到新来的人
      if (panels.session.inSettings()) panels.session.exit()
      guide.open(guideDone() ? 2 : 0)
    }
    return true
  })
  const resetTips = () => {
    tips.reset()
    tips.start()
  }
  installHelpMenu({ openGuide: () => guide.open(), resetTips })
  const back = installBack(panels)
  const chrome = installMobileChrome({
    speeds: panels.speeds,
    worldReady: () => panels.worldSettings.online() && !!panels.worldSettings.state()?.ready,
    events,
    infoPanel: panels.infoPanel,
    chatHistory: panels.chatHistory,
    open: panels.open,
    watchBooks: panels.books.watch,
    openSettings: () => void panels.session.enter(),
    avatar: panels.avatar,
    audio,
    openGuide: () => guide.open(),
    resetTips,
  })
  back.front()
  // 面板盖住地图的边变了：告诉镜头；盖得更多时，正在看的村民若被盖住就挪到露出来的那块
  trackMapInsets(
    $('map'),
    (insets) => map.setViewInsets?.(insets),
    () => {
      const id = panels.infoPanel.isCollapsed() ? null : panels.infoPanel.selected()
      const at = id ? map.getMemberPos(id) : undefined
      if (at) map.panTo(at[0], at[1])
    },
    listeners.signal
  )
  // 向导开着时返回键只在向导里退一步
  const offGuideBack = onBack(() => guide.back())
  window.addEventListener(
    'prop-appearance-changed',
    () => {
      decorate()
      connection.send({ type: 'get_props' })
    },
    { signal: listeners.signal }
  )
  window.addEventListener(
    'pageshow',
    (event) => {
      if (event.persisted) location.reload()
    },
    { signal: listeners.signal }
  )
  connection.connect()
  return {
    dispose() {
      listeners.abort()
      chrome.dispose()
      back.dispose()
      offGuideBack()
      connection.disconnect()
      panels.registry.dispose()
    },
  }
}

/**
 * 安卓返回键，后登记的先问：先关对话框、化身的面板和整页（front），再由手机外框关浮层、事件列表和村民卡，
 * 都没有可关的才交还化身，最后回到地图选择（这一组最先登记，最后问）。
 */
function installBack(panels: Panels) {
  const last = onBack(() => {
    if (panels.avatar.active()) {
      void panels.avatar.release()
      return true
    }
    document.getElementById('back-to-maps')?.click()
    return true
  })
  let first = () => {}
  return {
    /** 在手机外框之后调用，让这一组排在最前面 */
    front() {
      first = onBack(() => {
        const dialog = [...document.querySelectorAll<HTMLDialogElement>('dialog[open]')].at(-1)
        if (dialog) {
          // 第一次进入要填的世界观不能跳过，按返回键不关
          if (dialog.id !== 'world-setup') dialog.close()
          return true
        }
        if (panels.avatar.closeEntry() || panels.avatar.closePanel()) return true
        const page = [...document.querySelectorAll<HTMLElement>('.page-view, #props-view')].find(
          (view) => !view.hidden && view.getClientRects().length
        )
        if (page) {
          page.querySelector<HTMLButtonElement>("button[id$='-back']")?.click()
          return true
        }
        if (document.querySelector('.prop-card:not([hidden])')) {
          panels.props.closeCard()
          return true
        }
        return false
      })
    },
    dispose() {
      last()
      first()
    },
  }
}

/** 地图上点了村民、空地或道具：控制化身时走过去互动，否则选中村民或打开道具页 */
function wireMap(map: GameMap, panels: Panels, picked: () => void) {
  $('info-chat').onclick = () => {
    const id = panels.infoPanel.selected()
    if (id) panels.chatHistory.open(id)
  }
  // 点人选中，脚下冒出动作钮；再点一次已选中的人直接打开角色卡
  map.onVillagerClick = (id) => {
    panels.props.closeCard()
    if (panels.avatar.select('chat', id)) return
    picked()
    if (panels.infoPanel.selected() === id) panels.infoPanel.open(id)
    else panels.infoPanel.select(id)
  }
  // 点空地取消选中，角色卡一起收起；控制化身时点空地是走过去，不管选中
  map.onGroundClick = () => {
    if (!panels.avatar.active()) panels.infoPanel.select(null)
  }
  // 摆道具时点空地打开道具浮窗，点道具弹出移除和再放的菜单
  map.onPlaceClick = (client) => panels.props.placing?.clickAt(client)
  // 书和公告直接打开「书与公告」：一摞书看这个地点的书，公告栏看栏上的公告，单本直接读
  map.onPropClick = (id) => {
    if (panels.props.placing?.propClick(id)) return
    if (panels.avatar.select('bag', id)) return
    panels.props.closeCard()
    if (map.isBookPile?.(id)) panels.books.place(id)
    else if (panels.books.isBoard(id)) panels.books.board(id)
    else if (panels.books.isReadable(id)) panels.books.read(id)
    else panels.props.card(id)
  }
}
