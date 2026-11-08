// 道具：地图上的「道具」格进入，右边浮出道具浮窗（手机上从底部升起，只占半屏），分两层。
// 第一层「镇上有什么」：按地点列出镇上的东西，点一件镜头飞过去看它在哪，每个地点能「往这里放」。
// 第二层「放到某处」：点了地图上的地点（或「往这里放」）以后，列出能放的道具，头上「‹ 全镇」回第一层。
// 开着浮窗时地图压暗，只有能放东西的地点亮着；拉近后地点里画出能放的格子，指到哪里，绿框就吸到最近的
// 能放的格子，东西会落在绿框里。格子和原因都由后端算（get_placement_grid），这里只管怎么用。第二层里
// 指着一行时试放（preview_placement），绿框换成这件的大小；点一行就放下。浮窗不关，可以接着放、撤销
// 刚放的那件，顶上列出这个地点已有的东西，可以顺手移除。点地图上已有的道具弹出小菜单：在它旁边再放
// 东西，或者移除它。改道具、导出道具包在整页的「道具库」（浮窗底部进）。道具目录和命令回执都经道具页
// （page.ts），这里只管界面。
import type { ClientMsg, PlaceGrid, ServerMsg } from '../protocol'
import type { GameMap, PlaceGhost, PlaceSpot, WalkTarget } from '../gameMap'
import { gameIcon } from '../game/icons'
import { visibleMapRect } from '../mapView'
import { slot } from '../design/ui'
import { newId } from '../ids'
import { button, el } from './dom'
import { propPicture } from './picture'
import { definitionId, latestVersions } from './libraryView'
import { PURPOSES, usesOf } from './worldView'
import { blockedText, freeNear, roomText } from './placeGrid'
import type { Definition, PropCatalog, PropView } from './types'
import './placing.css'

export type PlacingMap = Pick<
  GameMap,
  | 'setPlacing'
  | 'placeSpotAt'
  | 'setPlaceHighlight'
  | 'setPlaceMarker'
  | 'walkTargetOf'
  | 'setPlaceGrids'
  | 'setPlaceGhost'
  | 'focusPlace'
  | 'placeDetail'
  | 'onPlaceDetail'
>

type Answer = Extract<ServerMsg, { type: 'placement_grid' | 'placement_preview' }>
/** 试放的结果：落点和占地（米），或者放不下的原因 */
type Preview = { at: [number, number]; size: [number, number] } | { cant: string }

export interface PlacingDeps {
  map: PlacingMap
  catalog(): PropCatalog | null
  localeName(id: string): string
  /** 要一份最新的道具目录 */
  refresh(): void
  /** 放置、移除：回执到了调 done；没连上时返回 false */
  command(
    kind: 'place_prop' | 'remove_prop',
    build: (world_id: string, request_id: string) => ClientMsg,
    done: (ok: boolean, message: string) => void
  ): boolean
  /** 问后端哪里能放（格子、试放）：回包经 answer 交回来；没连上时返回 null */
  ask(build: (world_id: string, request_id: string) => ClientMsg): string | null
  /** 整页的道具库：改道具、导出道具包 */
  openLibrary(): void
}

type Status =
  | { kind: 'idle' }
  | { kind: 'busy'; text: string }
  | { kind: 'placed'; id: string; name: string; locale: string }
  | { kind: 'note'; text: string }
  | { kind: 'error'; text: string }

/** 道具库里每件道具取最新一版；公告要先选公告栏，从「书与公告」贴，不在这里放 */
function choices(c: PropCatalog) {
  return latestVersions(c.definitions).filter((d) => d.readable?.kind !== 'bulletin')
}

/** 地点里摆在地图上的东西：撤下的、收进背包和容器的不算 */
function placedIn(c: PropCatalog, locale: string) {
  return c.instances.filter((p) => p.locale === locale && !p.withdrawn && p.on_map !== false)
}

function matches(d: Definition, query: string, purpose: string) {
  if (purpose) {
    const read = purpose === 'read' && (!!d.readable || d.bulletin_board)
    if (!read && !d.actions.some((a) => usesOf(a).includes(purpose))) return false
  }
  return `${d.name} ${d.description} ${d.actions.map((a) => a.label).join(' ')}`
    .toLowerCase()
    .includes(query)
}

export function createPlacing(deps: PlacingDeps) {
  const mapEl = document.getElementById('map')!
  const listeners = new AbortController()
  const { signal } = listeners
  let active = false
  let spot: (PlaceSpot & { client: [number, number] }) | null = null
  let query = ''
  let purpose = ''
  let status: Status = { kind: 'idle' }
  /** 这次摆道具放过的道具（定义编号），最近的在前 */
  let recent: string[] = []
  let lastPointer: [number, number] = [0, 0]
  const watchers: ((active: boolean) => void)[] = []
  /** 后端给的格子，按地点；还没到或地图没有三维数据时为空，退回只描地点 */
  let grids = new Map<string, PlaceGrid>()
  let gridAsked: string | null = null
  /** 地图上摆着的东西变了才重新要格子 */
  let placedKey = ''
  /** 试放：问出去的请求对应哪一行、哪一格；结果按「道具版本|格子」记着，同一格不再问 */
  const previewAsked = new Map<string, string>()
  const previews = new Map<string, Preview>()
  let previewing: string | null = null
  /** 指针正停在浮窗里哪一行（鼠标）；格子换了以后按新位置重新试放它 */
  let hoveredRow: Definition | null = null
  const touch = () => document.documentElement.dataset.input === 'touch'

  const hintText = el('span', '道具：点地图上的地点往那里放，点一件看它在哪')
  const hint = el('div', '', 'place-hint')
  hint.setAttribute('role', 'status')
  hint.append(
    hintText,
    button('完成', () => setActive(false))
  )
  /** 顶上那句提示：整图时说亮着的地点能放，拉近后说格子 */
  function renderHint() {
    const detail = !!deps.map.placeDetail?.()
    hintText.textContent = !grids.size
      ? '道具：点地图上的地点往那里放，点一件看它在哪'
      : detail
        ? touch()
          ? '道具：点一个亮格子，再选要放的东西'
          : '道具：亮格子能放，指到哪里，绿框就落在哪里'
        : touch()
          ? '道具：亮着的地方能放，点一块拉近'
          : '道具：亮着的地方能放，点一块拉近看格子'
  }
  if (deps.map.onPlaceDetail !== undefined) deps.map.onPlaceDetail = () => renderHint()
  const follow = el('div', '', 'place-follow')
  const picker = el('section', '', 'place-picker')
  picker.setAttribute('role', 'dialog')
  picker.setAttribute('aria-label', '道具')
  const menu = el('div', '', 'place-menu')
  menu.setAttribute('role', 'menu')
  for (const node of [hint, follow, picker, menu]) {
    node.hidden = true
    // 和地图上的按钮一样隔开：在浮窗里点、滚不能被地图当成点地面、拖动或缩放
    for (const type of ['pointerdown', 'dblclick', 'wheel'])
      node.addEventListener(type, (event) => event.stopPropagation(), { signal })
  }
  mapEl.append(hint, follow, picker, menu)

  // 浮窗里的固定部件：搜索框重画时不能丢焦点，只换列表、已有物品和底栏
  const title = el('b')
  const titleSmall = el('small', '放到')
  const back = button('‹ 全镇', () => leaveSpot(), 'place-back')
  back.setAttribute('aria-label', '回到镇上有什么')
  const here = el('div', '', 'place-here')
  const search = el('input')
  search.type = 'search'
  search.placeholder = '搜索道具或能做的事，比如「喝水」'
  search.autocomplete = 'off'
  search.setAttribute('aria-label', '搜索道具')
  search.addEventListener('input', () => {
    query = search.value.trim().toLowerCase()
    renderList()
  })
  const segments = el('div', '', 'place-seg')
  segments.setAttribute('role', 'group')
  segments.setAttribute('aria-label', '用途')
  const segButtons = PURPOSES.map((p) => {
    const b = button(p.label, () => {
      purpose = p.value
      for (const [i, s] of segButtons.entries())
        s.setAttribute('aria-pressed', String(PURPOSES[i].value === purpose))
      renderList()
    })
    b.setAttribute('aria-pressed', String(p.value === purpose))
    return b
  })
  segments.append(...segButtons)
  const list = el('div', '', 'place-list')
  const foot = el('div', '', 'place-foot')
  foot.setAttribute('aria-live', 'polite')
  {
    const head = el('header', '', 'place-head')
    const where = el('span', '', 'place-where')
    where.append(titleSmall, title)
    const close = button('', () => setActive(false), 'place-close')
    close.setAttribute('aria-label', '关上道具')
    close.append(gameIcon('close', true))
    head.append(back, where, close)
    const box = el('label', '', 'place-search')
    box.append(gameIcon('search', true), search)
    picker.append(head, here, box, segments, list, foot)
  }

  function setActive(on: boolean) {
    if (on === active) return
    active = on
    deps.map.setPlacing?.(on)
    mapEl.classList.toggle('placing', on)
    hint.hidden = !on
    if (on) {
      recent = []
      placedKey = placedSignature()
      deps.refresh()
      askGrid()
      showTown()
    } else {
      leaveSpot()
      picker.hidden = true
      clearTimeout(locateTimer)
      closeMenu()
      follow.hidden = true
      grids = new Map()
      gridAsked = null
      placedKey = ''
      previews.clear()
      previewAsked.clear()
    }
    renderHint()
    for (const watch of watchers) watch(on)
  }

  /** 要一份各地点能放的格子：进摆道具时、地图上摆着的东西变了以后 */
  function askGrid() {
    gridAsked = deps.ask((world_id, request_id) => ({
      type: 'get_placement_grid',
      request_id,
      world_id,
    }))
  }

  /** 后端的回包：格子换上，试放的结果记下来 */
  function answer(msg: Answer) {
    if (msg.type === 'placement_grid') {
      if (msg.request_id !== gridAsked || !active) return
      gridAsked = null
      grids = new Map(msg.grids.map((g) => [g.locale, g]))
      previews.clear()
      deps.map.setPlaceGrids?.(msg.grids)
      renderHint()
      // 刚放下的那件占了格子：绿框挪到离点的位置最近的、还能放的格子；第一层的「往这里放」跟着格子变
      if (spot) resnap()
      else if (active) renderTownList(true)
      return
    }
    const key = previewAsked.get(msg.request_id)
    if (!key) return
    previewAsked.delete(msg.request_id)
    const result: Preview =
      msg.ok && msg.spot
        ? { at: [msg.spot.position[0], msg.spot.position[2]], size: msg.spot.footprint }
        : { cant: msg.ok ? '' : msg.message }
    previews.set(key, result)
    if (previewing === key) showPreview(key)
  }

  function openPicker(at: PlaceSpot, client: [number, number]) {
    closeMenu()
    follow.hidden = true
    spot = { ...at, client }
    status = at.full ? { kind: 'note', text: '这里已经放满了，移走点东西再放' } : { kind: 'idle' }
    deps.map.setPlaceHighlight?.(at.locale)
    titleSmall.textContent = '放到'
    title.textContent = deps.localeName(at.locale)
    back.hidden = false
    search.placeholder = '搜索道具或能做的事，比如「喝水」'
    picker.hidden = false
    mapEl.classList.add('place-picking')
    render()
    showSpotGhost()
    // 镜头拉近到这块地，并让开浮窗：格子看得清，要放的位置不被浮窗盖住
    if (grids.has(at.locale)) deps.map.focusPlace?.(at.locale, at.near, pickerCover(), true)
    deps.refresh()
    if (document.documentElement.dataset.layout !== 'compact') search.focus({ preventScroll: true })
  }

  /** 离开第二层：清掉点好的位置，开着道具时回到第一层「镇上有什么」 */
  function leaveSpot() {
    if (!spot) return
    spot = null
    previewing = null
    hoveredRow = null
    mapEl.classList.remove('place-picking')
    deps.map.setPlaceHighlight?.(null)
    deps.map.setPlaceMarker?.(null)
    deps.map.setPlaceGhost?.(null)
    if (active) showTown()
  }

  /** 第一层「镇上有什么」 */
  function showTown() {
    titleSmall.textContent = '道具'
    back.hidden = true
    search.placeholder = '搜镇上的东西或能做的事，比如「喝水」'
    picker.hidden = false
    render()
  }

  let locateTimer = 0
  /** 第一层里点一件：镜头飞到它所在的地点，脉冲圈标出它；带在身上、收在容器里的没有位置 */
  function locate(p: PropView) {
    const at = p.on_map !== false && !p.location ? deps.map.walkTargetOf?.('prop', p.id) : undefined
    if (!at) {
      flashInPanel(
        `${p.name}${p.location?.kind === 'carried' ? '在村民身上' : '收在容器里'}，地图上看不到`
      )
      return
    }
    deps.map.focusPlace?.(p.locale, at, pickerCover())
    deps.map.setPlaceHighlight?.(p.locale)
    deps.map.setPlaceMarker?.(at)
    clearTimeout(locateTimer)
    locateTimer = window.setTimeout(() => {
      if (spot) return
      deps.map.setPlaceMarker?.(null)
      deps.map.setPlaceHighlight?.(null)
    }, 2600)
  }

  /** 第一层里「往这里放」：选这个地点里离中间最近的能放的格子，进第二层 */
  function placeInto(locale: string) {
    const g = grids.get(locale)
    if (!g) return
    const middle: [number, number] = [
      g.origin[0] + ((g.columns - 1) * g.step) / 2,
      g.origin[1] + ((g.rows - 1) * g.step) / 2,
    ]
    const free = freeNear(g, middle)
    const near: WalkTarget = { space: '', position: free?.at ?? middle }
    openPicker({ locale, near, full: !free }, lastPointer)
  }

  /** 第一层底栏的一句话，几秒后换回说明 */
  let footTimer = 0
  function flashInPanel(text: string) {
    foot.querySelector('span')?.replaceChildren(text)
    clearTimeout(footTimer)
    footTimer = window.setTimeout(() => {
      if (!spot) renderTownFoot()
    }, 2600)
  }

  /** 浮窗盖住地图的右边（宽屏）；手机上是底部的抽屉，加上顶上的提示条（它下面才露出地图） */
  function pickerCover() {
    const m = mapEl.getBoundingClientRect(),
      p = picker.getBoundingClientRect()
    if (document.documentElement.dataset.layout !== 'compact')
      return { right: Math.max(0, m.right - p.left) }
    const h = hint.hidden ? null : hint.getBoundingClientRect()
    return {
      top: h ? Math.max(0, h.bottom - m.top + 8) : 0,
      bottom: Math.max(0, m.bottom - p.top),
    }
  }

  /** 点好的位置：有格子时画绿框（没有专门大小的东西那么大），没有格子时画定位点 */
  function showSpotGhost() {
    previewing = null
    if (!spot) return
    const g = grids.get(spot.locale)
    if (!g || spot.full) {
      deps.map.setPlaceGhost?.(null)
      deps.map.setPlaceMarker?.(spot.near)
      return
    }
    deps.map.setPlaceMarker?.(null)
    deps.map.setPlaceGhost?.({ at: spot.near, size: g.size })
  }

  /** 格子换了（刚放下一件）：点好的位置挪到离原来点的地方最近的、还能放的格子 */
  function resnap() {
    if (!spot) return
    const g = grids.get(spot.locale)
    const free = g && freeNear(g, (spot.point ?? spot.near).position)
    spot = free
      ? { ...spot, near: { space: spot.near.space, position: free.at }, full: false }
      : { ...spot, full: !!g }
    showSpotGhost()
    if (hoveredRow) previewRow(hoveredRow)
  }

  /** 指着浮窗里的一行：试放这件，绿框换成它的大小和落点 */
  function previewRow(d: Definition) {
    if (!spot || !grids.has(spot.locale) || spot.full) return
    const reference = `${d.id}@${d.version}`
    const key = `${reference}|${spot.near.position.join()}`
    previewing = key
    if (previews.has(key)) return showPreview(key)
    if ([...previewAsked.values()].includes(key)) return
    const { locale, near } = spot
    const id = deps.ask((world_id, request_id) => ({
      type: 'preview_placement',
      request_id,
      world_id,
      instance: { id: `user:${newId()}`, definition: reference, locale },
      near,
    }))
    if (id) previewAsked.set(id, key)
  }

  function showPreview(key: string) {
    const result = previews.get(key)
    if (!spot || !result) return
    const reference = key.split('|')[0]
    for (const row of list.querySelectorAll<HTMLElement>('.place-row'))
      row.classList.toggle('cant', row.dataset.ref === reference && 'cant' in result)
    if ('cant' in result) {
      const g = grids.get(spot.locale)
      deps.map.setPlaceGhost?.({ at: spot.near, size: g?.size ?? [0.65, 0.65], bad: true })
      const row = [...list.querySelectorAll<HTMLElement>('.place-row')].find(
        (r) => r.dataset.ref === reference
      )
      if (row) row.title = `这里放不下：${result.cant}`
      return
    }
    const at: WalkTarget = { space: spot.near.space, position: result.at }
    deps.map.setPlaceGhost?.({ at, size: result.size })
  }

  /** 宽屏靠右边放（右上角菜单下面、缩放钮左边），不跟着点的位置跳，镜头会把要放的地方挪到左边露出来。
   *  手机上是底部抽屉，只占半屏，交给样式 */
  function position() {
    if (picker.hidden) return
    if (document.documentElement.dataset.layout === 'compact') {
      picker.style.left = picker.style.top = picker.style.maxHeight = ''
      return
    }
    const m = mapEl.getBoundingClientRect()
    const area = visibleMapRect(mapEl)
    const top = area.top + 86
    picker.style.maxHeight = `${Math.max(240, area.bottom - top - 14)}px`
    const left = Math.max(area.left + 12, area.right - 72 - picker.offsetWidth)
    picker.style.left = `${left - m.left}px`
    picker.style.top = `${top - m.top}px`
  }

  function render() {
    picker.classList.toggle('town', !spot)
    renderHere()
    renderFoot()
    renderList()
  }

  /** 镜头里这件东西归哪一组：摆在地图上的按地点，带在身上、收在容器里的另成一组 */
  function groupOf(p: PropView) {
    if (p.location?.kind === 'carried') return '~carried'
    if (p.location?.kind === 'stored') return '~stored'
    return p.locale
  }

  function townMatches(c: PropCatalog, p: PropView) {
    if (purpose) {
      const read = purpose === 'read' && (!!p.readable || p.bulletin_board)
      const d = c.definitions.find((x) => `${x.id}@${x.version}` === p.definition)
      if (!read && !(d?.actions ?? []).some((a) => usesOf(a).includes(purpose))) return false
    }
    return `${p.name} ${deps.localeName(p.locale)} ${p.actions.map((a) => a.label).join(' ')}`
      .toLowerCase()
      .includes(query)
  }

  /** 第一层：按地点列出镇上的东西，同名的合成一行；能放东西的地点头上有「往这里放」 */
  function renderTownList(keepScroll = false) {
    const c = deps.catalog()
    const scroll = keepScroll ? list.scrollTop : 0
    list.replaceChildren()
    if (!c) {
      title.textContent = '镇上'
      list.append(el('p', '正在读取镇上的东西…', 'place-empty'))
      return
    }
    const all = c.instances.filter((p) => !p.withdrawn)
    title.textContent = `镇上 ${all.length} 件`
    const groups = new Map<string, PropView[]>()
    for (const p of all.filter((p) => townMatches(c, p))) {
      const key = groupOf(p)
      groups.set(key, [...(groups.get(key) ?? []), p])
    }
    const label = (key: string) =>
      key === '~carried' ? '在村民身上' : key === '~stored' ? '收在容器里' : deps.localeName(key)
    const order = [...groups.keys()].sort(
      (a, b) =>
        Number(a.startsWith('~')) - Number(b.startsWith('~')) ||
        label(a).localeCompare(label(b), 'zh-CN')
    )
    for (const key of order) {
      const items = groups.get(key)!
      const cap = el('p', '', 'place-group place-town-group')
      cap.append(el('b', label(key)), el('small', String(items.length)))
      const g = grids.get(key)
      if (g?.cells.includes('.'))
        cap.append(button('＋ 往这里放', () => placeInto(key), 'place-add'))
      list.append(cap)
      const same = new Map<string, PropView[]>()
      for (const p of items) same.set(p.name, [...(same.get(p.name) ?? []), p])
      for (const twins of same.values()) list.append(townRow(twins))
    }
    if (!groups.size)
      list.append(
        el(
          'p',
          all.length
            ? '没有符合的东西，换个词或分类试试。'
            : '镇上还没有东西，点地图上亮着的地方放一件。',
          'place-empty'
        )
      )
    list.scrollTop = scroll
    position()
  }

  /** 第一层的一行：同名的几件合成一行，点了看第一件在哪 */
  function townRow(twins: PropView[]) {
    const p = twins[0]
    const item = button('', () => locate(p), 'place-row')
    const name = el('span', '', 'place-name')
    name.append(el('span', p.name))
    if (twins.length > 1) name.append(el('span', `×${twins.length}`, 'place-times'))
    const text = el('span', '', 'place-text')
    const uses = p.actions.map((a) => a.label).join('、')
    text.append(name, el('span', uses || '摆设', 'place-desc'))
    item.title = p.name
    const onMap = p.on_map !== false && !p.location
    item.append(
      slot(propPicture(p.definition ?? p.id, p.readable ? 'book' : 'bag'), 'sm'),
      text,
      el('span', onMap ? '在哪' : '', 'place-act locate')
    )
    return item
  }

  /** 第一层的底栏：一句说明，右边是整页的道具库 */
  function renderTownFoot() {
    foot.classList.remove('error')
    foot.replaceChildren(
      el('span', '点一件，镜头飞过去看它；点地图上亮着的地方，往那里放新的。'),
      button('道具库', () => deps.openLibrary(), 'place-library')
    )
  }

  function renderHere() {
    const c = deps.catalog()
    here.hidden = !spot
    if (!spot || !c) {
      here.replaceChildren()
      return
    }
    const items = placedIn(c, spot.locale)
    const count = new Map<string, number>()
    for (const p of items)
      count.set(definitionId(p.definition), (count.get(definitionId(p.definition)) ?? 0) + 1)
    here.replaceChildren(
      el('span', items.length ? `这里已有 ${items.length} 件` : '这里还没有东西', 'place-cap')
    )
    for (const p of items) {
      const dup = (count.get(definitionId(p.definition)) ?? 0) > 1
      const chip = el('span', '', dup ? 'place-chip dup' : 'place-chip')
      chip.title = dup ? '这里有好几件一样的' : p.name
      const remove = button('', () => removeProp(p))
      remove.setAttribute('aria-label', `移除 ${p.name}`)
      remove.append(gameIcon('close', true))
      chip.append(el('span', p.name), remove)
      here.append(chip)
    }
  }

  /** 换了搜索词或分类从头看起；目录更新（放下、移除之后）留在原来滚到的地方 */
  function renderList(keepScroll = false) {
    if (!spot) return renderTownList(keepScroll)
    const c = deps.catalog()
    const scroll = keepScroll ? list.scrollTop : 0
    list.replaceChildren()
    if (!c) {
      list.append(el('p', '正在读取道具库…', 'place-empty'))
      return
    }
    const have = new Map<string, number>()
    for (const p of placedIn(c, spot.locale))
      have.set(definitionId(p.definition), (have.get(definitionId(p.definition)) ?? 0) + 1)
    const all = choices(c)
    const found = all.filter((d) => matches(d, query, purpose))
    const groups: [string, Definition[]][] = []
    if (query) groups.push([`找到 ${found.length} 件`, found])
    else if (purpose) groups.push([PURPOSES.find((p) => p.value === purpose)!.label, found])
    else {
      // 书很多，排在最后，不把能用的东西挤到下面去
      const book = (d: Definition) => d.readable?.kind === 'book'
      groups.push(
        ['刚放过', recent.flatMap((id) => all.filter((d) => d.id === id))],
        ['道具', found.filter((d) => !book(d))],
        ['书', found.filter(book)]
      )
    }
    for (const [label, items] of groups) {
      if (!items.length) continue
      list.append(el('p', label, 'place-group'))
      for (const d of items) list.append(row(d, have.get(d.id) ?? 0))
    }
    if (!found.length) list.append(el('p', '没有符合的道具，换个词或分类试试。', 'place-empty'))
    list.scrollTop = scroll
    // 列表变长变短后浮窗的高度跟着变，重新摆一下，别伸到左下角的按钮上
    position()
  }

  function row(d: Definition, count: number) {
    const reference = `${d.id}@${d.version}`
    const item = button('', () => place(d), 'place-row')
    item.dataset.ref = reference
    // 指着一行：地图上的绿框换成这件的大小和落点
    item.addEventListener('pointerenter', (event) => {
      if (event.pointerType !== 'mouse') return
      hoveredRow = d
      previewRow(d)
    })
    const name = el('span', '', 'place-name')
    name.append(el('span', d.name))
    if (count) name.append(el('span', `已有 ${count}`, 'place-have'))
    const text = el('span', '', 'place-text')
    const uses = d.actions.map((a) => a.label).join('、')
    text.append(name, el('span', uses || d.description || '摆设', 'place-desc'))
    item.title = d.description || d.name
    // 这一格试放过、放不下：标出来
    const tried = spot && previews.get(`${reference}|${spot.near.position.join()}`)
    if (tried && 'cant' in tried) {
      item.classList.add('cant')
      item.title = `这里放不下：${tried.cant}`
    }
    item.append(
      slot(propPicture(reference, d.readable ? 'book' : 'bag'), 'sm'),
      text,
      el('span', count ? '再放一件' : '放下', count ? 'place-act again' : 'place-act')
    )
    return item
  }

  function renderFoot() {
    if (!spot) return renderTownFoot()
    foot.replaceChildren()
    foot.classList.toggle('error', status.kind === 'error')
    if (status.kind === 'placed') {
      const ok = el('span', '', 'place-ok')
      ok.append(gameIcon('check', true))
      const text = el('span', `已放到${deps.localeName(status.locale)}：`)
      text.append(el('strong', status.name))
      foot.append(ok, text, button('撤销', undo))
    } else if (status.kind === 'idle') {
      foot.append(el('span', '点一行就放下，浮窗不会关，可以接着放。'))
    } else foot.append(el('span', status.text))
  }

  function setStatus(next: Status) {
    status = next
    renderFoot()
    // 浮窗关着（从菜单里移除，或者回执到时已经关了）：结果写在指针旁边
    if (spot || next.kind === 'idle') return
    flash(
      next.kind === 'placed' ? `已放到${deps.localeName(next.locale)}：${next.name}` : next.text,
      lastPointer
    )
  }

  function place(d: Definition) {
    if (!spot) return
    const { locale, near } = spot
    const id = `user:${newId()}`
    const sent = deps.command(
      'place_prop',
      (world_id, request_id) => ({
        type: 'place_prop',
        request_id,
        world_id,
        instance: { id, definition: `${d.id}@${d.version}`, locale },
        near,
      }),
      (ok, message) => {
        if (!ok) return setStatus({ kind: 'error', text: `没放成：${message}` })
        recent = [d.id, ...recent.filter((r) => r !== d.id)].slice(0, 3)
        setStatus({ kind: 'placed', id, name: d.name, locale })
        renderList(true)
        askGrid()
      }
    )
    setStatus(
      sent
        ? { kind: 'busy', text: `正在放「${d.name}」…` }
        : { kind: 'error', text: '小镇的连接断了，连上后再放' }
    )
  }

  function undo() {
    if (status.kind !== 'placed') return
    const { id, name } = status
    remove(id, name, `已撤销「${name}」`)
  }

  function removeProp(p: PropView) {
    // 有人正在用：移除会打断他，先问一声
    if (p.occupants.length && !window.confirm(`有人正在用「${p.name}」，移除会打断他。确定移除？`))
      return
    remove(p.id, p.name, `已移除「${p.name}」`)
  }

  function remove(id: string, name: string, done: string) {
    const sent = deps.command(
      'remove_prop',
      (world_id, request_id) => ({ type: 'remove_prop', request_id, world_id, id }),
      (ok, message) => {
        setStatus(
          ok ? { kind: 'note', text: done } : { kind: 'error', text: `没移除成：${message}` }
        )
        if (ok) askGrid()
      }
    )
    setStatus(
      sent
        ? { kind: 'busy', text: `正在移除「${name}」…` }
        : { kind: 'error', text: '小镇的连接断了，连上后再试' }
    )
  }

  /** 摆道具时点了地图上已有的道具：在点的位置弹出小菜单 */
  function openMenu(p: PropView) {
    closeMenu()
    follow.hidden = true
    const near = deps.map.walkTargetOf?.('prop', p.id)
    menu.replaceChildren(
      el('p', p.name, 'place-menu-title'),
      el('p', deps.localeName(p.locale), 'place-menu-sub')
    )
    if (near)
      menu.append(
        button('在这里再放东西', () => {
          closeMenu()
          openPicker({ locale: p.locale, near }, lastPointer)
        })
      )
    menu.append(
      button(
        '移除这个道具',
        () => {
          closeMenu()
          if (spot?.locale !== p.locale) leaveSpot()
          removeProp(p)
        },
        'danger'
      ),
      button('取消', closeMenu)
    )
    menu.hidden = false
    const m = mapEl.getBoundingClientRect()
    const [x, y] = lastPointer
    const left = Math.min(x - m.left + 8, m.width - menu.offsetWidth - 12)
    const top = Math.min(y - m.top + 8, m.height - menu.offsetHeight - 12)
    menu.style.left = `${Math.max(12, left)}px`
    menu.style.top = `${Math.max(12, top)}px`
  }

  function closeMenu() {
    menu.hidden = true
  }

  let flashTimer = 0
  /** 指针旁边的一句短提示，两秒后收起 */
  function flash(text: string, [x, y]: [number, number]) {
    if (!text) return
    const m = mapEl.getBoundingClientRect()
    follow.textContent = text
    follow.classList.add('flash')
    follow.style.left = `${x - m.left}px`
    follow.style.top = `${y - m.top}px`
    follow.hidden = false
    clearTimeout(flashTimer)
    flashTimer = window.setTimeout(() => {
      follow.hidden = true
      follow.classList.remove('flash')
    }, 2000)
  }

  // 指针在地图画面上移动：描出指着的地点，旁边写「放到 X」；浮窗开着时不跟
  let frame = 0
  let pointer: PointerEvent | null = null
  const onMap = (target: EventTarget | null) =>
    target instanceof Element && !!target.closest('#map > svg') && !target.closest('[data-prop-id]')
  const propAt = (target: EventTarget | null) =>
    target instanceof Element
      ? target.closest('#map > svg [data-prop-id]')?.getAttribute('data-prop-id')
      : undefined
  mapEl.addEventListener(
    'pointermove',
    (event) => {
      if (!active || spot || !menu.hidden || event.pointerType === 'touch') return
      pointer = event
      frame ||= requestAnimationFrame(() => {
        frame = 0
        const e = pointer
        if (!e || !active || spot || !menu.hidden || follow.classList.contains('flash')) return
        const at = onMap(e.target) ? deps.map.placeSpotAt?.([e.clientX, e.clientY]) : undefined
        deps.map.setPlaceHighlight?.(at?.locale ?? null)
        const prop = deps.catalog()?.instances.find((p) => p.id === propAt(e.target))
        if (!onMap(e.target) && !prop) {
          follow.hidden = true
          deps.map.setPlaceGhost?.(null)
          return
        }
        const { text, ghost } = prop
          ? { text: `${prop.name}：点它可以移除，或在旁边再放`, ghost: null }
          : at
            ? hover(at)
            : { text: '这里放不了东西', ghost: null }
        deps.map.setPlaceGhost?.(ghost)
        const m = mapEl.getBoundingClientRect()
        follow.textContent = text
        follow.style.left = `${e.clientX - m.left}px`
        follow.style.top = `${e.clientY - m.top}px`
        follow.hidden = false
      })
    },
    { signal }
  )
  mapEl.addEventListener(
    'pointerleave',
    () => {
      follow.hidden = true
      if (active && !spot) {
        deps.map.setPlaceHighlight?.(null)
        deps.map.setPlaceGhost?.(null)
      }
    },
    { signal }
  )
  // 指针离开道具列表：绿框回到点好的位置、按没有专门大小的东西画
  list.addEventListener(
    'pointerleave',
    () => {
      hoveredRow = null
      if (previewing) showSpotGhost()
    },
    { signal }
  )

  /** 指着地图上一点：说一句会怎样，拉得够近时画绿框（指着放不了的地方，绿框吸到最近的能放的格子） */
  function hover(at: PlaceSpot): { text: string; ghost: PlaceGhost | null } {
    const name = deps.localeName(at.locale)
    const g = grids.get(at.locale)
    if (!g) return { text: `放到 ${name}`, ghost: null }
    if (at.full) return { text: `${name}已经放满了`, ghost: null }
    if (!deps.map.placeDetail?.()) return { text: `放到 ${name} · ${roomText(g)}`, ghost: null }
    if (at.code === '.' || !at.code)
      return { text: `放到 ${name}`, ghost: { at: at.near, size: g.size } }
    const thing = at.by && deps.catalog()?.instances.find((p) => p.id === at.by)?.name
    return {
      text: `${blockedText(at.code, thing || undefined)}，会放到绿框`,
      ghost: {
        at: at.near,
        size: g.size,
        from: at.point,
        blockedBy: at.code === 'b' ? (at.by ?? '') : null,
      },
    }
  }

  /** 地图上摆着的东西：变了才重新要格子 */
  function placedSignature() {
    return (deps.catalog()?.instances ?? [])
      .filter((p) => !p.withdrawn && p.on_map !== false)
      .map((p) => `${p.id}@${p.locale}`)
      .sort()
      .join()
  }
  mapEl.addEventListener('pointerdown', (event) => (lastPointer = [event.clientX, event.clientY]), {
    signal,
    capture: true,
  })
  document.addEventListener(
    'pointerdown',
    (event) => {
      if (!menu.hidden && !menu.contains(event.target as Node)) closeMenu()
    },
    { signal, capture: true }
  )
  document.addEventListener(
    'keydown',
    (event) => {
      if (!active || event.key !== 'Escape') return
      if (!menu.hidden) closeMenu()
      else if (spot) leaveSpot()
      else setActive(false)
      event.preventDefault()
      event.stopPropagation()
    },
    { signal, capture: true }
  )
  window.addEventListener('resize', () => position(), { signal })

  return {
    active: () => active,
    toggle: () => setActive(!active),
    exit: () => setActive(false),
    /** 打开道具浮窗的第一层，有 id 时镜头飞到这件东西（道具卡片上「在镇上看」） */
    browse(id?: string) {
      setActive(true)
      leaveSpot()
      const p = id ? deps.catalog()?.instances.find((i) => i.id === id) : undefined
      if (p) locate(p)
    },
    /** 按钮跟着开关道具浮窗 */
    watch(update: (active: boolean) => void) {
      watchers.push(update)
      update(active)
    },
    /** 摆道具时点了空地 */
    clickAt(client: [number, number]) {
      if (!active) return
      const at = deps.map.placeSpotAt?.(client)
      if (at) openPicker(at, client)
      else {
        closeMenu()
        flash('这里不在能放东西的地点里', client)
      }
    },
    /** 摆道具时点了已有的道具：弹出菜单；不在摆道具时返回 false，照常打开卡片 */
    propClick(id: string) {
      if (!active) return false
      const p = deps.catalog()?.instances.find((i) => i.id === id)
      if (p) openMenu(p)
      return true
    },
    /** 道具目录更新：已有物品和列表跟着变；地图上摆着的东西变了就重新要格子 */
    refreshed() {
      if (active) {
        const key = placedSignature()
        if (key !== placedKey) {
          placedKey = key
          askGrid()
        }
      }
      if (!active) return
      renderHere()
      renderList(true)
    },
    /** 后端回的格子和试放结果（道具页转过来） */
    answer,
    disconnected() {
      if (status.kind === 'busy') setStatus({ kind: 'error', text: '小镇的连接断了，没收到结果' })
    },
    reset() {
      setActive(false)
    },
    dispose() {
      setActive(false)
      if (deps.map.onPlaceDetail !== undefined) deps.map.onPlaceDetail = null
      listeners.abort()
      for (const node of [hint, follow, picker, menu]) node.remove()
    },
  }
}
