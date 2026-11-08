/** 电脑上贴着地图的一栏（右边的角色卡、贴边的动态）怎么拖宽：拖靠地图那条边，双击还原，方向键微调，
 *  宽度记成本机偏好。最宽能到多少由调用方按「地图至少留 MIN_MAP_WIDTH」算，这里只管交互和记忆。 */
export const MIN_MAP_WIDTH = 480

export interface ColumnWidthOptions {
  /** 宽度写成这个元素上的 CSS 变量 */
  host: HTMLElement
  cssVar: string
  resizer: HTMLElement
  storageKey: string
  defaultWidth: number
  min: number
  max: number
  /** 此刻地图让得出的宽度，不算 min、max */
  room: () => number
  /** 拖的那条边在这一栏的哪一侧：贴右的栏拖左边，贴左的栏拖右边 */
  edge: () => 'left' | 'right'
  /** 读屏念的名字，如「村民信息栏」 */
  label: string
}

export function installColumnWidth(options: ColumnWidthOptions) {
  const { host, cssVar, resizer, storageKey, defaultWidth, min, max } = options
  const listeners = new AbortController()
  const { signal } = listeners
  const isDesktop = () => window.matchMedia('(min-width: 1024px)').matches

  let preferred = defaultWidth
  try {
    const saved = Number(localStorage.getItem(storageKey))
    if (Number.isFinite(saved) && saved > 0) preferred = saved
  } catch {
    /* 私密窗口等场景拿不到就使用默认值 */
  }

  const limit = () => Math.min(max, Math.max(min, options.room()))

  function render(width: number) {
    const most = limit()
    const value = Math.round(Math.min(Math.max(width, min), most))
    host.style.setProperty(cssVar, `${value}px`)
    resizer.setAttribute('aria-valuemin', String(min))
    resizer.setAttribute('aria-valuemax', String(Math.round(most)))
    resizer.setAttribute('aria-valuenow', String(value))
    resizer.setAttribute('aria-valuetext', `${options.label}宽 ${value} 像素`)
    rendered = value
    return value
  }

  function remember(width: number) {
    preferred = render(width)
    try {
      localStorage.setItem(storageKey, String(preferred))
    } catch {
      /* 同上 */
    }
  }

  let rendered = defaultWidth
  render(preferred)
  /** 往外拖（离开地图）为正 */
  const outward = (dx: number) => (options.edge() === 'left' ? -dx : dx)
  let dragging = false
  let dragStartX = 0
  let dragStartWidth = rendered

  resizer.addEventListener(
    'mousedown',
    (e: MouseEvent) => {
      if (!isDesktop() || e.button !== 0) return
      e.preventDefault()
      dragging = true
      dragStartX = e.clientX
      dragStartWidth = rendered
      resizer.classList.add('drag')
      document.body.classList.add('resizing-column')
    },
    { signal }
  )
  window.addEventListener(
    'mousemove',
    (e: MouseEvent) => {
      if (dragging) render(dragStartWidth + outward(e.clientX - dragStartX))
    },
    { signal }
  )
  const finish = () => {
    if (!dragging) return
    dragging = false
    resizer.classList.remove('drag')
    document.body.classList.remove('resizing-column')
    remember(rendered)
  }
  window.addEventListener('mouseup', finish, { signal })
  window.addEventListener('blur', finish, { signal })
  resizer.addEventListener('dblclick', () => remember(defaultWidth), { signal })
  resizer.addEventListener(
    'keydown',
    (e: KeyboardEvent) => {
      if (!isDesktop()) return
      const step = e.shiftKey ? 48 : 16
      let next: number | null = null
      if (e.key === 'ArrowLeft') next = rendered + outward(-step)
      if (e.key === 'ArrowRight') next = rendered + outward(step)
      if (e.key === 'Home') next = min
      if (e.key === 'End') next = limit()
      if (next === null) return
      e.preventDefault()
      remember(next)
    },
    { signal }
  )
  return {
    /** 按此刻让得出的宽度重画；给了 width 就画它（不记成偏好），否则画本机偏好 */
    render: (width = preferred) => render(width),
    preferred: () => preferred,
    dispose: () => listeners.abort(),
  }
}

/** 角色卡的宽度：在右边，拖左边；地图让得出的宽度按 #obs-main 算（贴边的动态已经让出去了）。
 *  载入时地图页还藏着、量出来是 0，先按窗口算，不然一进来总是最窄 */
export function installPanelWidth(panel: HTMLElement, resizer: HTMLElement, obsMain: HTMLElement) {
  const isDesktop = () => window.matchMedia('(min-width: 1024px)').matches
  const room = () => (obsMain.clientWidth || document.documentElement.clientWidth) - MIN_MAP_WIDTH
  const width = installColumnWidth({
    host: panel,
    cssVar: '--info-panel-width',
    resizer,
    storageKey: 'town-info-panel-width',
    defaultWidth: 330,
    min: 280,
    max: 680,
    room,
    edge: () => 'left',
    label: '村民信息栏',
  })
  /** 改人设原文、捏长相时临时拉到最宽：不记成本机偏好，关掉回到原来的宽度 */
  let wide = false
  const refresh = () => {
    if (isDesktop()) width.render(wide ? room() : width.preferred())
  }
  window.addEventListener('resize', refresh)
  return {
    dispose() {
      window.removeEventListener('resize', refresh)
      width.dispose()
    },
    setWide(on: boolean) {
      if (wide === on) return
      wide = on
      // 平板上卡片是盖在地图上的一栏，宽度由样式按这个标记放宽
      panel.toggleAttribute('data-wide', on)
      refresh()
    },
  }
}
