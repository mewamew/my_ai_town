// 游戏界面的图标：手绘图集里的格子，或者线条图形。
// decorateIcons 按模板里的标记给按钮加图标，模板见 game/shell.html。
const paintedAtlas = new URL('./materials/town-icons-painted-v1.png', import.meta.url).href
const paintedIcons: Record<string, number> = {
  people: 0,
  person: 0,
  town: 1,
  door: 2,
  bag: 3,
  chat: 4,
  heart: 5,
  camera: 6,
  settings: 7,
  book: 8,
  status: 8,
  map: 9,
  eye: 10,
  hand: 11,
  sun: 12,
  weather: 13,
  rain: 13,
  water: 14,
  food: 15,
}
const shapes: Record<string, string> = {
  moon: '<path d="M19.7 15.5A8.8 8.8 0 0 1 8.5 4.3 8.9 8.9 0 1 0 19.7 15.5Z"/><path d="m17 3 .5 1.5L19 5l-1.5.5L17 7l-.5-1.5L15 5l1.5-.5Z"/>',
  dawn: '<path d="M3 17h18M5 21h14M7 17a5 5 0 0 1 10 0M12 3v6m-3-3 3-3 3 3M3 10l2 2m14 0 2-2"/>',
  dusk: '<path d="M3 17h18M5 21h14M7 17a5 5 0 0 1 10 0M12 3v6m-3-3 3 3 3-3M3 10l2 2m14 0 2-2"/>',
  rain: '<path d="M5 14a4 4 0 0 1 0-8 5 5 0 0 1 10-1 4.5 4.5 0 1 1 3 9H5Z"/><path d="m7 17-1 3m6-3-1 4m6-4-1 3"/>',
  storm:
    '<path d="M5 14a4 4 0 0 1 0-8 5 5 0 0 1 10-1 4.5 4.5 0 0 1 3 9h-2"/><path d="m12 11-4 7h4l-1 5 6-8h-5l2-4"/>',
  snow: '<path d="M12 2v20M3.3 7l17.4 10M3.3 17 20.7 7M9 4l3 3 3-3M9 20l3-3 3 3M3.5 10l4.1-1.1-1.1-4.1M17.5 19.2l-1.1-4.1 4.1-1.1M6.5 19.2l1.1-4.1L3.5 14M20.5 10l-4.1-1.1 1.1-4.1"/>',
  sound: '<path d="M3 9h4l5-5v16l-5-5H3ZM16 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
  reset: '<path d="M4 9a8 8 0 1 1 0 7M4 3v6h6"/>',
  palette: '<circle cx="12" cy="12" r="8"/><path d="M12 4v16M4 12h16"/>',
  screen: '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M12 17v4m-5 0h10"/>',
  map: '<path d="m2 5 7-3 6 3 7-3v17l-7 3-6-3-7 3Zm7-3v17m6-14v17"/>',
  person: '<circle cx="12" cy="7" r="4"/><path d="M4 22v-4a8 8 0 0 1 16 0v4Z"/>',
  door: '<path d="M5 21V3h12v18M9 21V5l8-2M13 12h1M3 21h18"/>',
  heart: '<path d="M12 21 3 12C-2 5 7 0 12 7c5-7 14-2 9 5Z"/>',
  food: '<path d="M4 2v6a3 3 0 0 0 6 0V2M7 2v20M19 22V2c-5 3-5 10 0 10"/>',
  water: '<path d="M12 2S5 11 5 15a7 7 0 0 0 14 0c0-4-7-13-7-13Z"/>',
  energy: '<path d="m14 2-9 12h7l-2 8 10-13h-8Z"/>',
  book: '<path d="M12 5C8 2 4 3 2 4v16c4-2 7-1 10 1 3-2 6-3 10-1V4c-3-1-7-2-10 1Zm0 0v16"/>',
  memory: '<path d="m12 2 3 6 7 1-5 5 1 8-6-4-6 4 1-8-5-5 7-1Z"/>',
  chat: '<path d="M21 11a9 8 0 0 1-9 8H7l-5 3 1-7a8 8 0 0 1 0-8 10 9 0 0 1 18 4Z"/><path d="M7 11h.1m5 0h.1m5 0h.1"/>',
  hand: '<path d="M8 12V5a2 2 0 0 1 4 0v7-9a2 2 0 0 1 4 0v9-6a2 2 0 0 1 4 0v9c0 9-11 9-14 4l-4-6a2 2 0 0 1 3-2l3 3"/>',
  check: '<path d="m4 12 5 5L21 5"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/>',
  weather:
    '<path d="M7 16a4 4 0 1 1 1-7 5 5 0 0 1 10 1 3 3 0 0 1 0 6H7Zm2 3-1 2m5-2-1 2m5-2-1 2"/>',
  town: '<path d="M3 21V10l5-4 5 4v11M13 21V6l4-3 4 3v15M1 21h22M6 21v-6h4v6M16 9h2m-2 4h2m-2 4h2"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
  upload: '<path d="M12 16V3m-5 5 5-5 5 5M4 14v7h16v-7"/>',
  download: '<path d="M12 3v13m-5-5 5 5 5-5M4 14v7h16v-7"/>',
  restart: '<path d="M4 9a8 8 0 1 1 0 7M4 3v6h6"/>',
  'skip-back': '<path d="M5 5v14m14-13-10 6 10 6Z"/>',
  'skip-forward': '<path d="M19 5v14M5 6l10 6-10 6Z"/>',
  pause: '<path d="M8 5v14M16 5v14" stroke-width="3.5"/>',
  play: '<path d="m8 5 11 7-11 7Z"/>',
  fast: '<path d="m3 6 8 6-8 6Zm10 0 8 6-8 6Z"/>',
  slow: '<path d="M4 5v14m5-13 11 6-11 6Z"/>',
  chevron: '<path d="m8 10 4 4 4-4"/>',
  search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>',
  help: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.6 2.2c-.7.4-1.1 1-1.1 1.8v.5M12 17.5v.01"/>',
  back: '<path d="M20 12H4m6-6-6 6 6 6"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  spark: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5Z"/>',
  people:
    '<circle cx="9" cy="7" r="3"/><path d="M3 21v-5a6 6 0 0 1 12 0v5M17 4a3 3 0 0 1 0 6m2 3c3 1 3 4 3 8"/>',
  bag: '<path d="M5 8h14l2 13H3ZM9 8V5a3 3 0 0 1 6 0v3M8 14h8"/>',
  status:
    '<rect x="5" y="5" width="14" height="17" rx="2"/><path d="M9 5V2h6v3M9 11h6m-6 4h6m-6 4h4"/>',
  settings:
    '<path d="m9 3 1-2h4l1 2 2 1 2 0 2 3-1 2v3l1 2-2 3-2 0-2 1-1 3h-4l-1-3-2-1-2 0-2-3 1-2V9L3 7l2-3h2Z" transform="translate(0 1)"/><circle cx="12" cy="12" r="3"/>',
  chart: '<path d="M3 3v18h19M7 17v-5m5 5V8m5 9V4"/>',
  eye: '<path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12Z"/><circle cx="12" cy="12" r="3"/>',
  pin: '<path d="M12 22s7-6.2 7-12a7 7 0 0 0-14 0c0 5.8 7 12 7 12Z"/><circle cx="12" cy="10" r="2.6"/>',
  lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  pen: '<path d="m4 20 1-5L16 4l4 4L9 19Zm9-13 4 4"/>',
  more: '<circle cx="5" cy="12" r="1.3" fill="currentColor"/><circle cx="12" cy="12" r="1.3" fill="currentColor"/><circle cx="19" cy="12" r="1.3" fill="currentColor"/>',
  fit: '<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>',
  tilt: '<path d="M3 20h18M5 20 17 6"/><path d="M11 20a6 6 0 0 0-2-4.5"/>',
  cycle: '<path d="M4 12a8 8 0 0 1 14-5.3L20 9M20 12a8 8 0 0 1-14 5.3L4 15M20 4v5h-5M4 20v-5h5"/>',
  grid: '<rect x="3" y="3" width="7.5" height="7.5" rx="1.5"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="1.5"/><rect x="3" y="13.5" width="7.5" height="7.5" rx="1.5"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="1.5"/>',
}
export function iconLabel(element: HTMLElement, name: string, label: string, iconOnly = false) {
  const text = document.createElement('span')
  text.textContent = label
  if (iconOnly) text.className = 'game-sr-only'
  element.replaceChildren(gameIcon(name), text)
  element.classList.add('game-icon-control')
  element.setAttribute('aria-label', label)
  if (iconOnly) element.title = label
}
/** 线条图标加看得见的文字：角色卡等处的入口用，和手机底部入口是同一套线条图标 */
export function lineLabel(element: HTMLElement, name: string, label: string) {
  const text = document.createElement('span')
  text.textContent = label
  element.replaceChildren(gameIcon(name, true), text)
  element.classList.add('game-icon-control')
}
/** line：只用线条图形，不用手绘图集（手机底部入口要和其他线条图标一致） */
export function gameIcon(name: string, line = false) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
  svg.classList.add('game-icon')
  svg.setAttribute('viewBox', '0 0 24 24')
  svg.setAttribute('aria-hidden', 'true')
  svg.dataset.icon = name
  const cell = line ? undefined : paintedIcons[name]
  if (cell !== undefined) {
    svg.classList.add('game-icon-painted')
    const image = document.createElementNS('http://www.w3.org/2000/svg', 'image')
    image.setAttribute('href', paintedAtlas)
    // Generated atlas regions have measured gutters, not an assumed equal grid.
    const columns = [
      [0, 327],
      [332, 284],
      [625, 309],
      [945, 309],
    ]
    const rows = [
      [20, 335],
      [375, 260],
      [645, 280],
      [930, 300],
    ]
    const [x, width] = columns[cell % 4]
    const [y, height] = rows[Math.floor(cell / 4)]
    svg.setAttribute('viewBox', `${x} ${y} ${width} ${height}`)
    image.setAttribute('width', '1254')
    image.setAttribute('height', '1254')
    svg.append(image)
  } else svg.innerHTML = shapes[name] ?? shapes.status
  return svg
}

/**
 * 模板里的图标标记：data-with-icon 把按钮内容换成图标加文字（再带 data-icon-only 时文字只给读屏）；
 * data-icon-before 在文字前加图标；i[data-symbol] 换成顶栏的装饰图标。处理完去掉标记。
 */
export function decorateIcons(root: ParentNode) {
  for (const element of root.querySelectorAll<HTMLElement>('[data-with-icon]')) {
    const iconOnly = element.hasAttribute('data-icon-only')
    iconLabel(element, element.dataset.withIcon ?? '', (element.textContent ?? '').trim(), iconOnly)
    element.removeAttribute('data-with-icon')
    element.removeAttribute('data-icon-only')
  }
  for (const element of root.querySelectorAll<HTMLElement>('[data-icon-before]')) {
    element.prepend(gameIcon(element.dataset.iconBefore ?? ''))
    element.removeAttribute('data-icon-before')
  }
  for (const placeholder of root.querySelectorAll<HTMLElement>('i[data-symbol]')) {
    const symbol = gameIcon(placeholder.dataset.symbol ?? '')
    symbol.classList.add('hud-symbol')
    placeholder.replaceWith(symbol)
  }
}
