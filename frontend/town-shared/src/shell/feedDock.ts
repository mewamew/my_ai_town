// 动态的三种摆法：浮板（默认，展开时浮在地图左下）、贴左、贴右。贴边时展开的动态成从顶到底的一整列，
// 放在地图旁边、不盖在地图上：#obs-main 让出这一列的宽度（shell/hud.css），地图变窄，地图里的浮层
// （座位、发言卡、化身面板、玩法的板子）跟着挪，和角色卡那一栏同一个做法。收起时整列收掉，左下回到两行小字；
// 再点「全部动态」回到上次的贴边。摆法、宽度和贴边时开没开都记在本机，刷新后还是上次的样子。
// 1024 宽起才贴边（Windows、mac、网页一样）；地图至少留 480 宽，角色卡也开着、排不下最窄的一列时先变回浮板，
// 宽了再贴回去。手机的底部抽屉、平板的浮板和录像拍摄页都不贴边。
import { $ } from '../dom'
import { installColumnWidth, MIN_MAP_WIDTH } from '../info/width'

type Side = 'left' | 'right'

const SIDE_KEY = 'town-feed-dock'
const OPEN_KEY = 'town-feed-dock-open'
const MIN_WIDTH = 300

function load(key: string) {
  try {
    return localStorage.getItem(key)
  } catch {
    return null // 私密窗口等场景拿不到就当没选过
  }
}
function save(key: string, value: string | null) {
  try {
    if (value === null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  } catch {
    /* 同上 */
  }
}

export interface FeedDock {
  /** 动态展开或收起了：贴边的话整列跟着出来或收掉 */
  opened(open: boolean): void
  /** 上次是贴着边开着走的：载入时直接展开 */
  reopen(): boolean
}

/** dockable：录像拍摄页传 false，贴边钮和拖边都拿掉 */
export function installFeedDock(dockable: boolean): FeedDock {
  const view = $('obs-view')
  const resizer = $('event-resizer')
  const group = document.querySelector<HTMLElement>('.event-dock')
  if (!dockable) {
    group?.remove()
    resizer.remove()
    return { opened() {}, reopen: () => false }
  }
  const buttons: Record<Side, HTMLElement> = {
    left: $('event-dock-left'),
    right: $('event-dock-right'),
  }
  const saved = load(SIDE_KEY)
  let side: Side | null = saved === 'left' || saved === 'right' ? saved : null
  let open = false
  const desktop = window.matchMedia('(min-width: 1024px)')
  /** 地图让得出的宽度：电脑上角色卡和它的拖边也排在地图旁边，先扣掉。
   *  按窗口量不按 #obs-view：载入时地图页还藏着，上次贴着边走的要一出来就是整列 */
  const room = () =>
    document.documentElement.clientWidth -
    ['info-panel', 'info-resizer'].reduce(
      (sum, id) => sum + (document.getElementById(id)?.getBoundingClientRect().width ?? 0),
      0
    ) -
    MIN_MAP_WIDTH
  const width = installColumnWidth({
    host: view,
    cssVar: '--feed-dock-width',
    resizer,
    storageKey: 'town-feed-width',
    defaultWidth: 400,
    min: MIN_WIDTH,
    max: 640,
    room,
    edge: () => (side === 'right' ? 'left' : 'right'),
    label: '动态栏',
  })

  const fits = () => desktop.matches && room() >= MIN_WIDTH
  function fit() {
    const docked = open && side && fits() ? side : null
    if (docked) width.render()
    if (docked) view.dataset.feedDock = docked
    else delete view.dataset.feedDock
    for (const s of ['left', 'right'] as const) {
      const on = side === s
      buttons[s].setAttribute('aria-pressed', String(on))
      buttons[s].title = !on
        ? `贴在窗口${s === 'left' ? '左' : '右'}边成一整列，地图让开`
        : open && !docked
          ? '窗口排不下，先浮在地图上；宽了会自己贴回去。再点一下改回浮板'
          : '再点一下浮回地图上'
    }
  }
  for (const s of ['left', 'right'] as const)
    buttons[s].addEventListener('click', () => {
      side = side === s ? null : s
      save(SIDE_KEY, side)
      fit()
    })

  // 窗口变了、角色卡开关或拖宽了：重新看排不排得下。就在这一帧里改，不留一帧浮板；
  // 贴边只改地图那一块的宽，量的这两样不跟着变，不会自己追自己
  const observer = new ResizeObserver(fit)
  observer.observe(view)
  const info = document.getElementById('info-panel')
  if (info) observer.observe(info)
  fit()

  return {
    opened(next) {
      open = next
      save(OPEN_KEY, next ? '1' : null)
      fit()
    },
    reopen: () => !!side && load(OPEN_KEY) === '1' && fits(),
  }
}
