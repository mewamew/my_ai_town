// 顶栏：开始/暂停钮、回到地图选择、连接状态、全镇暂停标记，以及地图里的道具入口。
import { $, button, el } from '../dom'
import { countBadge } from '../design/ui'
import type { EventsHandle } from '../events'
import { displayClock } from '../format'
import { gameIcon, iconLabel } from '../game/icons'
import { groupHolds, namesOf } from '../holds'
import type { MapEntry } from '../mapDocument'
import { closeTown } from '../townApi'
import type { ClientMsg } from '../protocol'
import type { PauseHint } from '../pauseHint'
import type { RosterMsg, ShellPanel } from './panel'
import { newId } from '../ids'

/** 点了开始或暂停以后，最多等这么久（毫秒）让名册跟上；还没跟上就以名册为准（命令被拦下、没生效） */
const CONFIRM_MS = 3000

/** 顶栏的开始/暂停钮。世界只有暂停和运行两档，运行时村民在画面上像散步（正常速度由服务端按地图比例定）；
 *  大家都在做一件还要好一阵的事、没人走动或说话时服务端自动快进（名册的 pace 比 speed 大），
 *  快进的提示挂在地图上（pauseHint.ts）。
 *  点了先在本地记住新速度：紧接着进设定时，记下的是新速度而不是上一拍名册里的。
 *  服务端要到处理完命令的那一拍才换速度，正在算的这一拍发出的名册还是旧速度：
 *  名册跟上之前不照它改回去，不然点一下会「暂停 → 开始 → 暂停」跳一下。 */
export function installSpeedBar(
  send: (msg: ClientMsg) => void,
  onChoose: (speed: number) => void,
  /** 运行时的世界速度 */
  normalSpeed: number
) {
  const toggle = button('', () => (marked ? choose(0) : start()), 'speed-toggle')
  $('speeds').replaceChildren(toggle)
  function render(running: boolean) {
    toggle.replaceChildren(
      gameIcon(running ? 'pause' : 'play', true),
      el('span', running ? '暂停' : '开始')
    )
    toggle.setAttribute('aria-label', running ? '暂停' : '开始')
    toggle.title = running ? '暂停世界' : '开始运行；没人走动或说话时会自动快进'
    toggle.classList.toggle('go', !running)
  }
  // 名册来之前先画成暂停、不能点；世界设好并连上后由 worldSettings.ts 放开
  render(false)
  toggle.disabled = true
  function choose(speed: number) {
    onChoose(speed)
    pending = { speed, until: performance.now() + CONFIRM_MS }
    mark(speed)
    send({ type: 'set_speed', request_id: newId(), speed })
  }
  /** 点了、名册还没跟上的速度 */
  let pending: { speed: number; until: number } | null = null
  /** 每份名册调用：返回此刻该显示的速度。点了还没生效时名册里的旧速度先不算 */
  function sync(speed: number) {
    if (pending && speed !== pending.speed && performance.now() < pending.until)
      return pending.speed
    pending = null
    mark(speed)
    return speed
  }
  /** 「开始」前的拦截（还没连模型时先请玩家连上）：接手了返回 true，由它决定之后要不要开始 */
  let gate: ((start: () => void) => boolean) | null = null
  /** 玩家点「开始」或按空格：先问拦截。返回是否已经开始 */
  function start() {
    const go = () => choose(normalSpeed)
    if (gate?.(go)) return false
    go()
    return true
  }
  let marked: number | null = null
  /** 手机切到后台时的暂停与恢复跟着这里变 */
  const listeners = new Set<(speed: number) => void>()
  function mark(speed: number) {
    if (marked === speed) return
    marked = speed
    render(speed > 0)
    for (const listener of listeners) listener(speed)
  }
  function setAvatarMode(active: boolean) {
    $('avatar-flag').hidden = !active
  }
  return {
    sync,
    choose,
    start,
    setGate(next: (start: () => void) => boolean) {
      gate = next
    },
    setAvatarMode,
    paused: () => marked === 0,
    /** 当前世界速度；还没收到名册时为 0 */
    current: () => marked ?? 0,
    onChange(listener: (speed: number) => void) {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
  }
}
export type SpeedBar = ReturnType<typeof installSpeedBar>

/**
 * 「← 地图选择」：先交还化身控制，再保存并关闭小镇，然后离开。同时只运行一个小镇，退出就关；
 * 直接关掉网页也发一下关闭（刷新页面时新页面会重新打开它），从浏览器的后退缓存回来就重新载入。
 */
export function installBackToMaps(
  selectedMap: MapEntry,
  events: EventsHandle,
  release: () => Promise<boolean>
) {
  const back = $('back-to-maps')
  if (!(back instanceof HTMLButtonElement)) return
  let closed = false
  back.onclick = async () => {
    if (!(await release())) return
    back.disabled = true
    back.textContent = '保存中…'
    try {
      await closeTown(selectedMap.id, selectedMap.lease)
      closed = true
      location.assign(`./?map=${encodeURIComponent(selectedMap.id)}`)
    } catch (error) {
      back.disabled = false
      back.textContent = '← 选择小镇'
      events.pushLocal(`没能保存并关闭小镇：${(error as Error).message}`, true)
    }
  }
  window.addEventListener('pagehide', () => {
    if (!closed) void closeTown(selectedMap.id, selectedMap.lease, true).catch(() => {})
  })
  window.addEventListener('pageshow', (event) => {
    if (event.persisted) location.reload()
  })
}

export function showConnection(online: boolean) {
  $('conn-text').hidden = online
  $('conn-text').textContent = online ? '' : '正在重新连接…'
  // 悬停只说连没连上，不显示连接地址
  $('conn').title = online ? '已连上小镇' : '小镇的连接断了，正在重新连接'
  $('conn').className = online ? 'ok' : ''
}

function showHolds(msg: RosterMsg) {
  // 全镇暂停：同一原因只写一次（「已暂停：密钥用不了」），影响谁放在悬停提示；修法在地图上的提示卡里
  const groups = groupHolds(msg.holds ?? [])
  const flag = $('hold-flag')
  flag.hidden = groups.length === 0
  flag.textContent = groups.length ? `已暂停：${groups.map((g) => g.copy.short).join('；')}` : ''
  flag.title = groups
    .map((g) => `${g.copy.title}（${namesOf(g.holds.map((h) => h.resident))}）`)
    .join('\n')
  flag.classList.toggle('warn', groups.length > 0 && groups.every((g) => g.copy.tone === 'warn'))
}

/** 顶栏上跟着名册变的部分：时钟、时段、全镇暂停原因、开始/暂停钮、地图上的暂停与快进提示和化身在场标记 */
export function topbarPanel(
  speeds: SpeedBar,
  pauseHint: PauseHint | null,
  avatarActive: () => boolean
): ShellPanel {
  return {
    roster({ msg }) {
      $('clock').textContent = displayClock(msg.clock)
      $('world-facts').textContent = msg.period ?? ''
      showHolds(msg)
      const speed = speeds.sync(msg.speed)
      // 还在等名册跟上时这一拍的实际速度也是旧的，不按它提示快进
      pauseHint?.update(speed, speed === msg.speed ? msg.pace : speed)
      speeds.setAvatarMode(avatarActive())
    },
  }
}

/** 地图内按钮沿用缩放控件的事件隔离，避免拖拽捕获指针后丢失点击。 */
export function installMapButtons(
  open: { props(): void; books(): void; placing(): void },
  /** 书与公告上的数字：没看过的新作品 */
  watchBooks: (update: (count: number) => void) => void,
  /** 摆道具的按下状态；地图不支持摆道具时为 null，按钮藏起来 */
  watchPlacing: ((update: (active: boolean) => void) => void) | null,
  signal: AbortSignal
) {
  const propsButton = $('open-props')
  iconLabel(propsButton, 'bag', '场景物品')
  propsButton.onclick = open.props
  const booksButton = $('open-books')
  iconLabel(booksButton, 'book', '书与公告')
  booksButton.onclick = open.books
  watchBooks(countBadge(booksButton, '书与公告'))
  const placingButton = $('open-placing')
  placingButton.onclick = open.placing
  placingButton.hidden = !watchPlacing
  watchPlacing?.((active) => {
    iconLabel(placingButton, 'plus', active ? '摆道具中' : '摆道具')
    placingButton.setAttribute('aria-pressed', String(active))
  })
  for (const entry of [propsButton, booksButton, placingButton])
    for (const type of ['pointerdown', 'dblclick'])
      entry.addEventListener(type, (event) => event.stopPropagation(), { signal })
}
