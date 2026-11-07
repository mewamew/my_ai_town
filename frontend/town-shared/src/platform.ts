// 运行环境：安卓应用壳（userAgent 带 AITownAndroid）、mac 应用壳（AITownMac）、Windows 应用壳
// （注入 window.townWindow）或普通浏览器。界面不按平台分叉：
// 窄屏（≤719px）换手机布局，触屏换手势与按钮；只有返回键、前后台和系统栏颜色是应用壳才有的事。
// 判断结果写在 <html> 的 data-layout / data-input / data-shell 上，样式与脚本看同一份。

const COMPACT = '(max-width: 719px)'
const TOUCH = '(pointer: coarse)'

interface AndroidBridge {
  systemBars?(tier: 'night' | 'paper'): void
  exit?(): void
}

const bridge = (): AndroidBridge | undefined =>
  (window as unknown as { TownAndroid?: AndroidBridge }).TownAndroid

/** 在安卓应用里运行 */
export const android = /\bAITownAndroid\//.test(navigator.userAgent)

interface WindowBridge {
  postMessage(message: { fullscreen?: boolean }): Promise<boolean>
}

/** mac 应用壳管窗口的那一头（macos/TownWindow.swift 的 WindowBridge）；浏览器和安卓里没有 */
const macWindow = (): WindowBridge | undefined =>
  (window as unknown as { webkit?: { messageHandlers?: { townWindow?: WindowBridge } } }).webkit
    ?.messageHandlers?.townWindow

/** Windows 应用壳注入的同样一头（windows/src/window.rs 的 BRIDGE） */
const windowsWindow = (): WindowBridge | undefined =>
  (window as unknown as { townWindow?: WindowBridge }).townWindow

/** 在 Windows 应用里运行 */
export const windows = !!windowsWindow()

const shellWindow = () => macWindow() ?? windowsWindow()

/** 窗口全屏由应用壳管（mac、Windows 版）：和绿色按钮、⌃⌘F 或 F11 一样，换页面不退出 */
export const windowFullscreenAvailable = () => !!shellWindow()

/** 应用壳的窗口全屏：on 不给时只问现在是不是全屏，回复是切换后的状态；没有应用壳时为 null */
export async function windowFullscreen(on?: boolean): Promise<boolean | null> {
  try {
    return (await shellWindow()?.postMessage(on === undefined ? {} : { fullscreen: on })) ?? null
  } catch {
    return null
  }
}

/** 应用壳的窗口进出全屏时回调（包括用户自己按绿色按钮、⌃⌘F、F11） */
export function onWindowFullscreen(listener: (on: boolean) => void) {
  window.addEventListener('town:fullscreen', (event) =>
    listener((event as CustomEvent<boolean>).detail)
  )
}

const compactQuery = matchMedia(COMPACT)
const touchQuery = matchMedia(TOUCH)

/** 手机布局：底部入口、抽屉，时钟牌一列小一号 */
export const isCompact = () => compactQuery.matches
/** 主要靠手指操作 */
export const isTouch = () => touchQuery.matches

/** 系统状态栏与导航栏跟着页面换底色：选图页深色，游戏页浅色。浏览器里什么也不做。 */
export function systemBars(tier: 'night' | 'paper') {
  try {
    bridge()?.systemBars?.(tier)
  } catch {
    // 应用壳没有这个能力时忽略
  }
}

function mark() {
  const root = document.documentElement
  root.dataset.layout = isCompact() ? 'compact' : 'wide'
  root.dataset.input = isTouch() ? 'touch' : 'mouse'
  if (android) root.dataset.shell = 'android'
  else if (macWindow()) root.dataset.shell = 'mac'
  else if (windows) root.dataset.shell = 'windows'
}

/** 触屏上点进输入框、键盘弹起来时在 <html> 上标 typing：贴底的入口栏先让开。
 *  键盘收起（返回手势）时输入框可能还聚焦着，所以同时看窗口是不是被键盘压矮了。 */
function trackTyping() {
  const root = document.documentElement
  let tallest = innerHeight
  let width = innerWidth
  const editing = (node: Element | null) =>
    node instanceof HTMLTextAreaElement ||
    (node instanceof HTMLElement && node.isContentEditable) ||
    (node instanceof HTMLInputElement &&
      !['checkbox', 'radio', 'button', 'submit', 'range', 'color', 'file'].includes(node.type))
  const update = () => {
    if (innerWidth !== width) {
      width = innerWidth
      tallest = innerHeight
    }
    tallest = Math.max(tallest, innerHeight)
    const squeezed = innerHeight < tallest * 0.8
    root.classList.toggle('typing', isTouch() && squeezed && editing(document.activeElement))
  }
  addEventListener('resize', update)
  document.addEventListener('focusin', update)
  document.addEventListener('focusout', () => setTimeout(update))
}

/** 每页启动时调用一次：写好布局与输入方式，窗口变化时跟着更新。 */
export function installPlatform() {
  mark()
  compactQuery.addEventListener('change', mark)
  touchQuery.addEventListener('change', mark)
  trackTyping()
}

// ---------- 返回键 ----------
// 应用壳按返回键时调用 window.townBack()：按登记顺序（后登记的先问）问各层能不能关一层，
// 有人处理就返回 true；都不处理返回 false，由应用壳提示再按一次退出。

type BackHandler = () => boolean
const backHandlers: BackHandler[] = []

/** 登记一层「返回」：能关就关并返回 true。返回取消登记的函数。 */
export function onBack(handler: BackHandler) {
  backHandlers.push(handler)
  return () => {
    const i = backHandlers.indexOf(handler)
    if (i >= 0) backHandlers.splice(i, 1)
  }
}

export function goBack(): boolean {
  for (let i = backHandlers.length - 1; i >= 0; i--) if (backHandlers[i]()) return true
  return false
}

// ---------- 前后台 ----------
// 应用切到后台时调用 window.townLifecycle('pause')，回到前台时调用 'resume'。

type Lifecycle = (state: 'pause' | 'resume') => void
const lifecycleHandlers = new Set<Lifecycle>()

export function onLifecycle(handler: Lifecycle) {
  lifecycleHandlers.add(handler)
  return () => lifecycleHandlers.delete(handler)
}

Object.assign(window, {
  townBack: goBack,
  townLifecycle(state: 'pause' | 'resume') {
    for (const handler of lifecycleHandlers) handler(state)
  },
})
