// 地图真正露出来的范围：减掉贴边盖住地图的面板——手机的底部抽屉、宽屏的右侧面板、
// 触屏化身的顶部操作条和底部操作区。台词气泡、新手提示和镜头取景都按它算，
// 东西才不会落在面板底下，或者浮到面板上面。

export interface ViewRect {
  left: number
  top: number
  right: number
  bottom: number
}

/** 贴着地图边、成片盖住地图的面板 */
export const PANELS =
  '#info-panel, #event-bar, #event-full, .avatar-panel, .avatar-hud, .avatar-touch'
/** 地图上的小按钮和提示：不切掉范围，只让气泡尽量躲开 */
const CONTROLS =
  '.map-zoom, .map-fabs > *, .map-props-button, .pause-hint, .town-notices > *, .avatar-toast, .avatar-return, .focus-verbs, .focus-emote'
/** 离地图边多近算贴边（宽屏的右侧面板留着 12px 边距） */
const EDGE = 32

function shown(node: HTMLElement) {
  return !node.hidden && node.getClientRects().length > 0
}

export function visibleMapRect(map: HTMLElement): ViewRect {
  const m = map.getBoundingClientRect()
  const r = { left: m.left, top: m.top, right: m.right, bottom: m.bottom }
  for (const node of document.querySelectorAll<HTMLElement>(PANELS)) {
    if (!shown(node)) continue
    const p = node.getBoundingClientRect()
    if (p.right <= m.left || p.left >= m.right || p.bottom <= m.top || p.top >= m.bottom) continue
    const wide = p.width >= m.width * 0.6,
      tall = p.height >= m.height * 0.6
    // 几乎盖满：地图上没有露出来的地方
    if (p.width >= m.width * 0.85 && p.height >= m.height * 0.85) return { ...r, bottom: r.top }
    if (wide && m.bottom - p.bottom < EDGE) r.bottom = Math.min(r.bottom, p.top)
    else if (wide && p.top - m.top < EDGE * 3) r.top = Math.max(r.top, p.bottom)
    else if (tall && m.right - p.right < EDGE) r.right = Math.min(r.right, p.left)
    else if (tall && p.left - m.left < EDGE) r.left = Math.max(r.left, p.right)
  }
  return r
}

/** 地图里看得见的小按钮和提示的范围；新手提示挂在 body 上，一并算进来 */
export function mapControlRects(map: HTMLElement): DOMRect[] {
  return [
    ...map.querySelectorAll<HTMLElement>(CONTROLS),
    ...document.querySelectorAll<HTMLElement>('body > .coach'),
  ]
    .filter(shown)
    .map((node) => node.getBoundingClientRect())
}

export interface Insets {
  top: number
  right: number
  bottom: number
  left: number
}

/** 盖住地图的面板变了（抽屉打开或拖高、右侧面板出现、进出化身），把盖住的边告诉镜头；
 *  盖住的范围变大时回调，调用方据此把正在看的人挪到露出来的那块 */
export function trackMapInsets(
  map: HTMLElement,
  apply: (insets: Insets) => void,
  grew: () => void,
  signal: AbortSignal
) {
  let frame = 0
  let last: Insets = { top: 0, right: 0, bottom: 0, left: 0 }
  const measure = () => {
    frame = 0
    const m = map.getBoundingClientRect()
    if (!m.width || !m.height) return
    const v = visibleMapRect(map)
    const next = {
      top: Math.round(Math.max(0, v.top - m.top)),
      right: Math.round(Math.max(0, m.right - v.right)),
      bottom: Math.round(Math.max(0, m.bottom - Math.max(v.bottom, v.top))),
      left: Math.round(Math.max(0, v.left - m.left)),
    }
    const area = (i: Insets) => i.top + i.right + i.bottom + i.left
    if ((Object.keys(next) as (keyof Insets)[]).every((k) => next[k] === last[k])) return
    const bigger = area(next) > area(last) + 24
    last = next
    apply(next)
    if (bigger) grew()
  }
  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(measure)
  }
  // 只看面板自己和 html/body 上的状态类变化，地图里人物每帧的改动不理
  const watched = (node: Node) =>
    node === document.documentElement ||
    node === document.body ||
    (node instanceof Element && !!node.closest(`${PANELS}, .avatar-ui`))
  const observer = new MutationObserver((records) => {
    if (records.some((r) => watched(r.target))) schedule()
  })
  observer.observe(document.documentElement, {
    subtree: true,
    attributes: true,
    attributeFilter: ['hidden', 'class', 'style'],
  })
  const resize = new ResizeObserver(schedule)
  resize.observe(map)
  window.addEventListener('resize', schedule, { signal })
  signal.addEventListener('abort', () => {
    observer.disconnect()
    resize.disconnect()
    cancelAnimationFrame(frame)
  })
  schedule()
}
