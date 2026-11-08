// 道具页「场景物品」视图：按地点分组的物品格子，可按地点、用途和搜索词筛选；右栏是选中物品的详情。
import { slot } from '../design/ui'
import { gameIcon } from '../game/icons'
import { renderPropDetail } from './detail'
import { button, el } from './dom'
import type { PropsView } from './pageState'
import { propPicture } from './picture'
import type { Action, BodyNeed, Definition, PropCatalog, PropView } from './types'

/** 用途筛选：按村民拿它做什么分。分类名和下面 usesOf 的判断要一起改 */
export const PURPOSES = [
  { value: '', label: '全部' },
  { value: 'eat', label: '吃喝' },
  { value: 'rest', label: '休息' },
  { value: 'heal', label: '看病' },
  { value: 'work', label: '干活' },
  { value: 'read', label: '阅读' },
]

function locationText(p: PropView, localeName: (id: string) => string) {
  if (p.location?.kind === 'carried') return '随身物品'
  if (p.location?.kind === 'stored') return '容器内物品'
  return localeName(p.locale)
}

/** 镇上一件东西的定义，说明、按用途筛和「复制并修改」都靠它：先查道具库，库里删掉了或本来就没有的
 *  （摘下来的椰子）再查目录里镇上自带的那份 */
export function definitionOf(c: PropCatalog | null, p: PropView) {
  const same = (d: Definition) => `${d.id}@${d.version}` === p.definition
  return c?.definitions.find(same) ?? c?.town_definitions?.find(same)
}

/** 一个动作的用处，看效果和完成方式，玩家自己做的道具也能自动归类：恢复饱腹或水分算吃喝，
 *  恢复精力或睡觉算休息，回健康、治病、复活算看病，耗体力的劳作算干活，读书、写书、查资料算阅读 */
export function usesOf(a: Action) {
  const done = a.on_complete ?? []
  const gains = new Set<BodyNeed>([
    ...a.during.flatMap((e) => (e.kind === 'restore_need' ? [e.need] : [])),
    ...done.flatMap((e) => (e.kind === 'restore' ? [e.need] : [])),
  ])
  const uses: string[] = []
  if (gains.has('fullness') || gains.has('water') || a.completion === 'meal') uses.push('eat')
  if (gains.has('energy') || a.completion === 'sleep' || a.rest) uses.push('rest')
  if (gains.has('health') || done.some((e) => e.kind === 'cure_condition' || e.kind === 'revive'))
    uses.push('heal')
  if (a.during.some((e) => e.kind === 'labor')) uses.push('work')
  if (['read_book', 'read_bulletin', 'write_book', 'research'].includes(a.completion))
    uses.push('read')
  return uses
}

/** 书、张贴出来的公告这类能读的东西，还有公告栏本身（没贴公告时也在），都归「阅读」 */
function matchesPurpose(view: PropsView, p: PropView) {
  const purpose = view.page.purpose.value
  if (!purpose) return true
  if (purpose === 'read' && (p.readable || p.bulletin_board)) return true
  return (definitionOf(view.state.catalog, p)?.actions ?? []).some((a) =>
    usesOf(a).includes(purpose)
  )
}

/** 格子右上角的状态点：空闲绿、使用中琥珀脉动、其余灰。公告有人在看也还能看，算空闲 */
function stateOf(view: PropsView, p: PropView) {
  if (p.withdrawn) return { key: 'off', text: '已撤下' }
  if (!view.state.connected) return { key: 'off', text: '占用状态未知' }
  if (p.occupants.length && p.readable?.kind === 'bulletin')
    return { key: 'free', text: '有人在看' }
  return p.occupants.length ? { key: 'busy', text: '使用中' } : { key: 'free', text: '空闲' }
}

export function renderWorld(view: PropsView, c: PropCatalog, q: string) {
  const { state, page, localeName } = view
  const items = c.instances
    .filter(
      (p) =>
        (!page.location.value || p.locale === page.location.value) &&
        matchesPurpose(view, p) &&
        `${p.name} ${localeName(p.locale)} ${p.actions.map((a) => a.label).join(' ')}`
          .toLowerCase()
          .includes(q)
    )
    .sort(
      (a, b) =>
        locationText(a, localeName).localeCompare(locationText(b, localeName), 'zh-CN') ||
        a.name.localeCompare(b.name, 'zh-CN')
    )
  const chosen = items.find((p) => p.id === state.selected) ?? items[0]
  if (chosen) state.selected = chosen.id
  if (!items.length) {
    // 一件都没筛出来：只留这句提示，不再挂「0 件」
    const empty = el('div', '', 'ui-empty')
    empty.append(gameIcon('search'), el('p', '没有符合条件的物品，换个词或放宽筛选试试。'))
    page.list.append(empty)
    return
  }
  // 「9 / 121」像收集进度，写成人话：没筛选时只说总数，筛选了说找到几件
  const filtered = !!q || !!page.location.value || !!page.purpose.value
  const total = c.instances.length
  page.list.append(
    el(
      'p',
      filtered ? `找到 ${items.length} 件，共 ${total} 件` : `共 ${total} 件物品`,
      'prop-count'
    )
  )
  const tiles = new Map<string, HTMLElement>()
  const choose = (p: PropView) => {
    state.selected = p.id
    for (const [id, tile] of tiles) {
      tile.classList.toggle('selected', id === p.id)
      tile.setAttribute('aria-pressed', String(id === p.id))
    }
    page.detail.replaceChildren()
    renderWorldDetail(view, p)
    // 窄屏上详情排在格子上方，点了格子要让它回到视野里
    if (window.matchMedia('(max-width: 959px)').matches)
      page.detail.scrollIntoView({ block: 'nearest' })
  }
  let group = ''
  let grid: HTMLElement | null = null
  for (const p of items) {
    const where = locationText(p, localeName)
    if (where !== group || !grid) {
      group = where
      const section = el('section', '', 'pw-group')
      const head = el('h3', '', 'pw-group-head')
      head.append(
        el('span', where),
        el('small', String(items.filter((i) => locationText(i, localeName) === where).length))
      )
      grid = el('div', '', 'pw-grid')
      section.append(head, grid)
      page.list.append(section)
    }
    const status = stateOf(view, p)
    const tile = button('', () => choose(p), 'ui-tile pw-tile')
    tile.dataset.state = status.key
    tile.setAttribute('aria-label', `${p.name}，${status.text}`)
    tile.classList.toggle('selected', p.id === state.selected)
    tile.setAttribute('aria-pressed', String(p.id === state.selected))
    tile.append(
      slot(propPicture(p.definition ?? p.id, p.readable ? 'book' : 'bag'), 'sm'),
      el('b', p.name),
      el('small', p.actions.map((a) => a.label).join('、') || '摆设'),
      el('i', '', 'pw-state')
    )
    tiles.set(p.id, tile)
    grid.append(tile)
  }
  if (chosen) renderWorldDetail(view, chosen)
}

function renderWorldDetail(view: PropsView, p: PropView) {
  renderPropDetail(view.page.detail, p, {
    localeName: view.localeName,
    personName: view.personName,
    connected: view.state.connected,
    definition: definitionOf(view.state.catalog, p),
    needLabel: view.needLabel,
    size: 'page',
    buttons: worldActions(view, p),
  })
}

/** 详情的按钮：读得了的先给「阅读全文」，公告栏先给「看上面的公告」，其余先给「在地图上定位」；
 *  复制修改与移除是创作操作，收在「更多」里 */
function worldActions(view: PropsView, p: PropView) {
  const { deps } = view
  const d = definitionOf(view.state.catalog, p)
  const buttons: HTMLElement[] = []
  const locate =
    p.on_map !== false
      ? button(
          '在地图上定位',
          () => {
            view.close()
            deps.onLocate(p.board ?? p.id, p.locale)
          },
          'ui-btn'
        )
      : null
  const read = p.readable
    ? button('阅读全文', () => deps.read(p.id), 'primary')
    : p.bulletin_board
      ? button('看上面的公告', () => deps.openBoard(p.id), 'primary')
      : null
  if (read) {
    buttons.push(read)
    if (locate) buttons.push(locate)
  } else if (locate) {
    locate.className = 'primary'
    buttons.push(locate)
  }
  const more = el('details', '', 'prop-more')
  more.append(el('summary', '更多'))
  const menu = el('div', '', 'prop-more-menu')
  if (d) menu.append(button('复制并修改', () => view.edit(d), 'ui-btn'))
  menu.append(
    button(
      '移除这个道具',
      () => {
        if (!window.confirm(`确定从小镇移除「${p.name}」？`)) return
        view.sendWorldCommand('remove_prop', (world_id, request_id) => ({
          type: 'remove_prop',
          request_id,
          world_id,
          id: p.id,
        }))
      },
      'ui-btn danger'
    )
  )
  more.append(menu)
  buttons.push(more)
  return buttons
}
