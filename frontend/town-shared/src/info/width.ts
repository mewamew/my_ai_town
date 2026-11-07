/** 信息栏宽度的交互和本机偏好，不读取人物或计划。 */
export function installPanelWidth(panel: HTMLElement, resizer: HTMLElement, obsMain: HTMLElement) {
  // ---- 桌面端宽度调整：拖动左边缘，记住本机偏好 ----
  const DEFAULT_WIDTH = 330
  const MIN_WIDTH = 280
  const MAX_WIDTH = 680
  const MIN_MAP_WIDTH = 480
  const WIDTH_KEY = 'town-info-panel-width'
  const listeners = new AbortController()
  const { signal } = listeners
  const isDesktop = () => window.matchMedia('(min-width: 1024px)').matches

  let preferredWidth = DEFAULT_WIDTH
  try {
    const saved = Number(localStorage.getItem(WIDTH_KEY))
    if (Number.isFinite(saved) && saved > 0) preferredWidth = saved
  } catch {
    /* 私密窗口等场景拿不到就使用默认值 */
  }

  function widthLimit() {
    return Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, obsMain.clientWidth - MIN_MAP_WIDTH))
  }

  function renderWidth(width: number) {
    const max = widthLimit()
    const value = Math.round(Math.min(Math.max(width, MIN_WIDTH), max))
    panel.style.setProperty('--info-panel-width', `${value}px`)
    resizer.setAttribute('aria-valuemin', String(MIN_WIDTH))
    resizer.setAttribute('aria-valuemax', String(Math.round(max)))
    resizer.setAttribute('aria-valuenow', String(value))
    resizer.setAttribute('aria-valuetext', `村民信息栏宽 ${value} 像素`)
    return value
  }

  function rememberWidth(width: number) {
    preferredWidth = renderWidth(width)
    try {
      localStorage.setItem(WIDTH_KEY, String(preferredWidth))
    } catch {
      /* 同上 */
    }
  }

  let renderedWidth = renderWidth(preferredWidth)
  /** 改人设原文、捏长相时临时拉到最宽：不记成本机偏好，关掉回到原来的宽度 */
  let wide = false
  const wanted = () => (wide ? widthLimit() : preferredWidth)
  let dragging = false
  let dragStartX = 0
  let dragStartWidth = renderedWidth

  resizer.addEventListener(
    'mousedown',
    (e: MouseEvent) => {
      if (!isDesktop() || e.button !== 0) return
      e.preventDefault()
      dragging = true
      dragStartX = e.clientX
      dragStartWidth = panel.getBoundingClientRect().width
      resizer.classList.add('drag')
      document.body.classList.add('resizing-info')
    },
    { signal }
  )
  window.addEventListener(
    'mousemove',
    (e: MouseEvent) => {
      if (!dragging) return
      renderedWidth = renderWidth(dragStartWidth + dragStartX - e.clientX)
    },
    { signal }
  )
  const finishResize = () => {
    if (!dragging) return
    dragging = false
    resizer.classList.remove('drag')
    document.body.classList.remove('resizing-info')
    rememberWidth(renderedWidth)
  }
  window.addEventListener('mouseup', finishResize, { signal })
  window.addEventListener('blur', finishResize, { signal })
  resizer.addEventListener(
    'dblclick',
    () => {
      renderedWidth = DEFAULT_WIDTH
      rememberWidth(renderedWidth)
    },
    { signal }
  )
  resizer.addEventListener(
    'keydown',
    (e: KeyboardEvent) => {
      if (!isDesktop()) return
      const step = e.shiftKey ? 48 : 16
      let next: number | null = null
      if (e.key === 'ArrowLeft') next = renderedWidth + step
      if (e.key === 'ArrowRight') next = renderedWidth - step
      if (e.key === 'Home') next = MIN_WIDTH
      if (e.key === 'End') next = widthLimit()
      if (next === null) return
      e.preventDefault()
      renderedWidth = renderWidth(next)
      rememberWidth(renderedWidth)
    },
    { signal }
  )
  window.addEventListener(
    'resize',
    () => {
      if (isDesktop()) renderedWidth = renderWidth(wanted())
    },
    { signal }
  )
  return {
    dispose: () => listeners.abort(),
    setWide(on: boolean) {
      if (wide === on) return
      wide = on
      // 平板上卡片是盖在地图上的一栏，宽度由样式按这个标记放宽
      panel.toggleAttribute('data-wide', on)
      if (isDesktop()) renderedWidth = renderWidth(wanted())
    },
  }
}
