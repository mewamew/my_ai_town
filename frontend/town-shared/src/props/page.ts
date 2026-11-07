// 道具页：整页覆盖地图页。当前地图实例、可复用定义库、创建/编辑、导入导出。
// 书和公告的正文在「书与公告」页（books.ts），这里点「阅读全文」「看上面的公告」就转过去。
// 状态在 pageState.ts，两个列表视图在 worldView.ts 与 libraryView.ts。
import type { ClientMsg, ServerMsg } from '../protocol'
import type { Appearance, BodyNeed, Definition, PropCatalog } from './types'
import { createEditor } from './editor'
import { savedAppearance, saveAppearance } from './appearances'
import { announcer, button, choice, el, input, select } from './dom'
import { $ } from '../dom'
import { newId } from '../ids'
import { errorText } from '../format'
import { observationPage } from '../observationPage'
import './style.css'
import { gameIcon, iconLabel } from '../game/icons'
import { showValidation, renderPropDetail } from './detail'
import { createPropCard } from './card'
import { readPackage, renderLibrary } from './libraryView'
import { createPropsPageState, type PropsDeps, type PropsView } from './pageState'
import { PURPOSES, renderWorld } from './worldView'
import { createPlacing } from './placing'

const worldHint = '点选一件物品，看它能做什么、现在能不能用。'

/** 道具页的骨架：页头按钮、筛选条、列表与详情两栏、编辑区、导入文件框 */
function propsSkeleton(
  game: boolean,
  actions: {
    back: () => void
    create: () => void
    filter: () => void
  }
) {
  const root = el('section', '', 'props-page')
  root.id = 'props-view'
  root.hidden = true
  // 面板可使用整页页头或独立窗口页头
  const toolbar = el('header', '', game ? 'props-toolbar' : 'page-topbar')
  const heading = el('h1', '道具')
  heading.id = 'props-title'
  const status = el('p', '正在读取道具库…', 'prop-status')
  status.setAttribute('aria-live', 'polite')
  const controls = el('div', '', 'props-controls')
  const search = input('', 'prop-search', 'search')
  search.placeholder = '搜索名称、动作、地点'
  const searchBox = el('label', '', 'ui-search')
  searchBox.append(gameIcon('search'), search)
  const mode = choice(
    '显示内容',
    [
      { value: 'world', label: '场景物品' },
      { value: 'library', label: '道具库（创作）' },
    ],
    'world',
    actions.filter
  )
  const location = select([{ id: '', label: '全部地点' }], '', 'prop-location')
  location.setAttribute('aria-label', '地点')
  const purpose = choice('用途', PURPOSES, '', actions.filter)
  // 地点和用途只筛场景里的物品，道具库里不出现
  const filters = el('div', '', 'props-filters')
  filters.append(location, purpose.el)
  const list = el('div', '', 'props-list'),
    detail = el('article', '', 'props-detail'),
    editor = el('div', '', 'props-editor')
  editor.hidden = true
  const layout = el('div', '', 'props-layout')
  layout.append(list, detail)
  const importFile = input('', 'prop-import', 'file')
  importFile.accept = '.json,application/json'
  importFile.hidden = true
  const backButton = button(game ? '← 返回' : '← 返回地图', actions.back)
  backButton.id = 'props-back'
  if (game) iconLabel(backButton, 'close', '关闭')
  // 创建和导入只在道具库里出现；游戏界面不显示：样式把 developer-tool 隐藏
  const tool = game ? 'developer-tool' : ''
  const create = button('创建道具', actions.create, tool)
  const importButton = button('导入道具包', () => importFile.click(), tool)
  const hintText = el('span', worldHint, 'dim')
  if (game) {
    const title = el('div')
    title.append(heading, hintText)
    toolbar.append(backButton, title, mode.el, create, importButton)
  } else {
    toolbar.append(backButton, heading, hintText, el('span', '', 'spacer'))
    toolbar.append(mode.el, create, importButton)
  }
  controls.append(searchBox, filters)
  const scroll = el('div', '', 'props-scroll')
  scroll.append(status, layout)
  root.append(toolbar, controls, scroll, editor, importFile)
  const fields = {
    hintText,
    create,
    importButton,
    search,
    mode,
    location,
    purpose,
    filters,
    list,
    detail,
    editor,
    importFile,
  }
  return { root, heading, status, controls, layout, scroll, ...fields }
}

export function initProps(deps: PropsDeps) {
  const page = new PropsPage(deps)
  return {
    open: (id?: string) => page.open(id),
    /** 地图上点道具：弹出对象卡片 */
    card: (id: string) => page.openCard(id),
    closeCard: () => page.closeCard(),
    close: () => page.close(),
    isOpen: page.lifecycle.isOpen,
    connected: () => page.connected(),
    disconnected: () => page.disconnected(),
    onReset: () => page.onReset(),
    handleMsg: (msg: ServerMsg) => page.handleMsg(msg),
    dispose: () => page.dispose(),
    /** 摆道具；地图不支持时为 null */
    placing: page.placing,
  }
}

/** 地图上画出的道具：撤下的和收在背包、容器里的不画 */
const visibleOnMap = (c: PropCatalog) =>
  c.instances.filter((p) => !p.withdrawn && p.on_map !== false)

class PropsPage implements PropsView {
  readonly state = createPropsPageState()
  readonly deps: PropsDeps
  readonly game: boolean
  readonly page: ReturnType<typeof propsSkeleton>
  readonly lifecycle: ReturnType<typeof observationPage>
  private readonly listeners = new AbortController()
  private readonly card = createPropCard(() => this.closeCard())
  private cardId = ''
  private cardSignature = ''
  private cardPoll: number | null = null
  /** 地点下拉框上次按哪份地点表建的 */
  private locationSignature = ''
  private readonly announce: ReturnType<typeof announcer>
  readonly placing: ReturnType<typeof createPlacing> | null
  readonly localeName = (id: string) =>
    this.state.catalog?.locations.find((l) => l.id === id)?.name ?? id
  readonly personName = (id: string) => this.deps.personName?.(id)
  readonly needLabel = (need: BodyNeed) =>
    this.state.catalog?.capabilities.needs.find((n) => n.id === need)?.label ?? need

  constructor(deps: PropsDeps) {
    this.deps = deps
    this.game = deps.game
    this.page = propsSkeleton(deps.game, {
      back: () => this.close(),
      create: () => this.edit(null),
      filter: () => this.render(),
    })
    document.body.append(this.page.root)
    // 卡片放进地图容器：不盖信息栏，宽度不够时随地图一起缩
    $('map').append(this.card.root)
    this.lifecycle = observationPage(
      this.page.root,
      $('obs-view'),
      () => deps.send({ type: 'get_props' }),
      2000,
      deps.game
    )
    this.announce = announcer(this.page.status)
    this.placing = deps.map
      ? createPlacing({
          map: deps.map,
          catalog: () => this.state.catalog,
          localeName: this.localeName,
          refresh: () => deps.send({ type: 'get_props' }),
          command: (kind, build, done) => this.sendWorldCommand(kind, build, done),
          ask: (build) => this.ask(build),
          openLibrary: () => this.openLibrary(),
        })
      : null
    this.bindEvents()
  }

  private bindEvents() {
    const { page, state, deps } = this
    page.importFile.onchange = async () => {
      try {
        const f = page.importFile.files?.[0]
        if (f) {
          const { definition, appearance } = await readPackage(f)
          this.submit('save_prop', definition, appearance)
        }
      } catch (e) {
        this.announce(errorText(e), true)
      } finally {
        page.importFile.value = ''
      }
    }
    page.search.addEventListener('input', () => this.render())
    page.location.addEventListener('change', () => this.render())
    window.addEventListener(
      'prop-appearance-changed',
      () => {
        state.mapSignature = ''
        if (state.catalog) deps.onUpdate(visibleOnMap(state.catalog), state.catalog.spatial)
      },
      { signal: this.listeners.signal }
    )
  }

  close() {
    this.lifecycle.close()
  }

  /** 地图上点了一件道具：弹出对象卡片，随服务端目录更新 */
  openCard(id: string) {
    this.state.selected = id
    this.cardId = id
    this.cardSignature = ''
    this.card.open()
    this.renderCard()
    this.deps.send({ type: 'get_props' })
    if (this.cardPoll === null)
      this.cardPoll = window.setInterval(() => this.deps.send({ type: 'get_props' }), 2000)
  }

  closeCard() {
    this.cardId = ''
    this.card.close()
    if (this.cardPoll !== null) window.clearInterval(this.cardPoll)
    this.cardPoll = null
  }

  private renderCard() {
    const { catalog, connected } = this.state
    const p = catalog?.instances.find((i) => i.id === this.cardId)
    const body = this.card.content
    if (!p) {
      const text = catalog ? '这件物品已不在小镇里。' : '正在读取…'
      if (this.cardSignature !== text) body.replaceChildren(el('p', text))
      this.cardSignature = text
      return
    }
    const definition = catalog?.definitions.find((d) => `${d.id}@${d.version}` === p.definition)
    const signature = JSON.stringify([p, definition?.description, connected])
    if (signature === this.cardSignature) return
    this.cardSignature = signature
    // 镇上其他东西在道具浮窗里看：镜头飞到这件，浮窗列出镇上有什么；地图不支持时开整页
    const all = button('镇上的道具', () => {
      this.closeCard()
      if (this.placing) this.placing.browse(p.id)
      else this.open(p.id)
    })
    const buttons = [all]
    if (p.readable) {
      all.className = 'ui-btn ghost'
      buttons.unshift(
        button(
          '阅读全文',
          () => {
            this.closeCard()
            this.deps.read(p.id)
          },
          'primary'
        )
      )
    } else all.className = 'primary'
    body.replaceChildren()
    renderPropDetail(body, p, {
      localeName: this.localeName,
      personName: this.personName,
      connected,
      definition,
      needLabel: this.needLabel,
      size: 'card',
      buttons,
    })
  }

  /** 打开道具页；给了实例编号就清掉筛选，在当前地图里选中它 */
  /** 整页的道具库：改道具、导出道具包、导入（道具浮窗底部进） */
  openLibrary() {
    this.page.mode.value = 'library'
    this.open()
  }

  open(id?: string) {
    const { page } = this
    this.closeCard()
    this.placing?.exit()
    if (id) {
      page.mode.value = 'world'
      page.search.value = ''
      page.location.value = ''
      page.purpose.value = ''
      this.state.selected = id
    }
    this.render()
    this.lifecycle.open()
    this.scrollToSelected()
  }

  /** 物品很多时把选中的一格带到视野中间。窄屏上选中物品的详情排在格子上面，
   *  滚到格子会把详情切掉一半，所以从头看起：详情在最上面，格子接在下面 */
  private scrollToSelected() {
    if (window.matchMedia('(max-width: 959px)').matches) {
      this.page.scroll.scrollTop = 0
      return
    }
    this.page.list.querySelector('.pw-tile.selected, .prop-row.selected')?.scrollIntoView({
      block: 'center',
    })
  }

  /** 打开编辑器：d 为空时新建，否则以它为底复制或编辑下一版本 */
  edit(d: Definition | null) {
    const { state, page } = this
    if (!state.catalog || !state.connected) {
      this.announce('连接后才能编辑道具', true)
      return
    }
    createEditor(
      page.editor,
      state.catalog,
      d,
      d ? savedAppearance(`${d.id}@${d.version}`) : null,
      (kind, definition, appearance) => this.submit(kind, definition, appearance),
      () => {
        page.editor.hidden = true
      }
    )
    page.editor.scrollIntoView({ block: 'start' })
  }

  private submit(
    kind: 'validate_prop' | 'save_prop',
    definition: Definition,
    appearance: Appearance
  ) {
    if (!this.state.connected) {
      this.announce('连接已断开，请重新连接后保存', true)
      return
    }
    const request_id = newId()
    this.state.pending.set(request_id, { kind, definition, appearance })
    this.deps.send({ type: kind, request_id, definition })
    this.announce(kind === 'save_prop' ? '正在保存固定版本…' : '正在校验效果…')
  }

  sendWorldCommand(
    kind: string,
    command: (world_id: string, request_id: string) => ClientMsg,
    done?: (ok: boolean, message: string) => void
  ) {
    const { catalog, connected, pending } = this.state
    if (!catalog) return false
    if (!connected) {
      this.announce('连接已断开，无法操作', true)
      return false
    }
    const request_id = newId()
    pending.set(request_id, { kind, done })
    this.deps.send(command(catalog.world_id, request_id))
    return true
  }

  /** 只读的问题（摆道具的格子、试放）：不进待回执表、不在道具页报结果，回包直接交给摆道具。
   *  记着问的是什么：还没换新的小镇进程不认识这两条命令，回的是错误，按「没有格子」「放不下」交回去 */
  private readonly asked = new Map<string, ClientMsg['type']>()
  private ask(build: (world_id: string, request_id: string) => ClientMsg) {
    const { catalog, connected } = this.state
    if (!catalog || !connected) return null
    const request_id = newId()
    const msg = build(catalog.world_id, request_id)
    this.asked.set(request_id, msg.type)
    this.deps.send(msg)
    return request_id
  }

  /** 摆道具问的问题回来了；出错时换成它自己的回包，不进事件栏 */
  private answered(msg: ServerMsg) {
    if (msg.type === 'placement_grid' || msg.type === 'placement_preview') {
      this.asked.delete(msg.request_id)
      this.placing?.answer(msg)
      return true
    }
    if (msg.type !== 'error' || msg.request_id === undefined) return false
    const kind = this.asked.get(msg.request_id)
    if (!kind) return false
    this.asked.delete(msg.request_id)
    const { request_id } = msg
    if (kind === 'get_placement_grid')
      this.placing?.answer({ type: 'placement_grid', request_id, grids: [] })
    else
      this.placing?.answer({
        type: 'placement_preview',
        request_id,
        ok: false,
        message: msg.message,
        spot: null,
      })
    return true
  }

  render() {
    const { page, state } = this
    const scroll = page.scroll.scrollTop
    page.list.replaceChildren()
    page.detail.replaceChildren()
    const library = page.mode.value === 'library'
    page.create.hidden = !library
    page.importButton.hidden = !library
    page.filters.hidden = library
    page.list.classList.toggle('as-grid', !library)
    page.hintText.textContent = library ? '复用道具定义，创建自己的道具。' : worldHint
    if (!state.catalog) {
      page.list.append(el('p', '还没收到服务端的道具数据。'))
      return
    }
    const q = page.search.value.trim().toLowerCase()
    if (page.mode.value === 'world') renderWorld(this, state.catalog, q)
    else renderLibrary(this, state.catalog, q)
    page.scroll.scrollTop = scroll
  }

  handleMsg(msg: ServerMsg) {
    if (this.answered(msg)) return true
    if (msg.type === 'props') this.onCatalog(msg.catalog)
    else if (msg.type === 'prop_result') this.onResult(msg)
    // 命令没能执行（格式错误、命令过多）：按失败结束这次操作
    else if (
      msg.type === 'error' &&
      msg.request_id !== undefined &&
      this.state.pending.has(msg.request_id)
    )
      this.onResult({
        type: 'prop_result',
        request_id: msg.request_id,
        ok: false,
        message: msg.message,
        preview: null,
      })
    else return false
    return true
  }

  private onCatalog(next: PropCatalog) {
    const { state, page } = this
    if (state.catalog && state.catalog.world_id !== next.world_id) {
      state.pending.clear()
      page.editor.hidden = true
      state.selected = ''
    }
    state.catalog = next
    if (this.cardId) this.renderCard()
    this.placing?.refreshed()
    // 道具页每 2 秒刷新一次目录；地点没变就不重建下拉框，不然开着的下拉列表会一闪一闪
    const placesKey = JSON.stringify(next.locations)
    if (placesKey !== this.locationSignature) {
      this.locationSignature = placesKey
      const previous = page.location.value
      page.location.replaceChildren(new Option('全部地点', ''))
      // 公共地点和住宅分两组：住宅一多，公共地点也不会被挤到列表底下
      const groups = [
        { label: '公共地点', places: next.locations.filter((l) => !l.residential) },
        { label: '住宅', places: next.locations.filter((l) => l.residential) },
      ]
      for (const { label, places } of groups) {
        if (!places.length) continue
        const group = el('optgroup')
        group.label = label
        group.append(...places.map((l) => new Option(l.name, l.id)))
        page.location.append(group)
      }
      page.location.value = previous
    }
    this.updateMap(next)
    const signature = JSON.stringify(next)
    if (
      this.lifecycle.isOpen() &&
      signature !== state.renderSignature &&
      !page.detail.contains(document.activeElement)
    ) {
      this.render()
      state.renderSignature = signature
    }
    // 数量在列表顶部写了，这里只在有话要说时出声
    if (!page.status.classList.contains('error'))
      this.announce(next.persistent ? '' : '当前运行不保存到磁盘')
  }

  /** 道具的地点、定义、名字或位置变了才重画地图上的道具 */
  private updateMap(next: PropCatalog) {
    const structure = JSON.stringify([
      next.spatial?.revision,
      next.instances.map((p) => [
        p.id,
        p.locale,
        p.definition,
        p.name,
        p.withdrawn,
        p.location,
        p.position,
      ]),
    ])
    if (structure === this.state.mapSignature) return
    this.state.mapSignature = structure
    this.deps.onUpdate(visibleOnMap(next), next.spatial)
  }

  private onResult(msg: Extract<ServerMsg, { type: 'prop_result' }>) {
    const { state, page } = this
    const op = state.pending.get(msg.request_id)
    if (!op) return
    state.pending.delete(msg.request_id)
    this.announce(msg.message, !msg.ok)
    op.done?.(msg.ok, msg.message)
    if (op.kind === 'validate_prop') showValidation(msg)
    if (msg.ok && op.kind === 'save_prop' && op.definition && op.appearance) {
      state.renderSignature = ''
      try {
        saveAppearance(`${op.definition.id}@${op.definition.version}`, op.appearance)
      } catch {
        this.announce('功能已保存，但浏览器未能保存外观。请导出并保留道具包。', true)
      }
      page.editor.hidden = true
      page.mode.value = 'library'
      state.selected = `${op.definition.id}@${op.definition.version}`
      page.search.value = ''
    }
  }

  connected() {
    this.state.connected = true
    this.announce('')
    this.deps.send({ type: 'get_props' })
  }

  disconnected() {
    const { state } = this
    state.connected = false
    const unconfirmed = state.pending.size > 0
    state.pending.clear()
    this.asked.clear()
    this.placing?.disconnected()
    this.announce(
      unconfirmed
        ? '小镇的连接断了，刚才的操作没收到结果；连上后请再看一眼道具列表。'
        : '小镇的连接断了，正在重新连接；下面是断开前的样子。',
      unconfirmed
    )
    this.render()
    if (this.cardId) this.renderCard()
  }

  onReset() {
    const { state } = this
    this.cardSignature = ''
    state.catalog = null
    state.selected = ''
    state.mapSignature = ''
    state.renderSignature = ''
    state.pending.clear()
    this.asked.clear()
    this.page.editor.hidden = true
    this.placing?.reset()
    this.deps.send({ type: 'get_props' })
    this.render()
  }

  dispose() {
    this.listeners.abort()
    this.placing?.dispose()
    this.lifecycle.close()
    this.closeCard()
    this.card.root.remove()
    this.page.root.remove()
  }
}
