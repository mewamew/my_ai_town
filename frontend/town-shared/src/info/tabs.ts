// 角色卡的页签：近况（原来卡片上的内容）｜人设｜长相｜模型。人设、长相、用哪个模型跟着这一局的存档，
// 所以就在这位村民自己的卡片上改，不进右上角的设定；地图一直在，世界不暂停。
// 每位村民的三页第一次用到时才建，草稿按人留着：改到一半点了别人，回来还在，页签上有圆点。
// 改人设原文和捏长相时卡片拉到最宽，镜头把这个人挪进露出来的地图；手机上抽屉拉满屏（mobile/chrome.ts）。
import type { ResidentContext } from '../application'
import type { Receipt, SaveCommand } from '../connection'
import { button, el, query } from '../dom'
import type { ClientMsg, ServerMsg } from '../protocol'
import { createLookPage } from './look'
import { createPersonaPage } from './persona'
import { createResidentModelPage } from './residentModel'

export type CardTab = 'status' | 'persona' | 'look' | 'model'
type EditTab = Exclude<CardTab, 'status'>
const EDIT_TABS: EditTab[] = ['persona', 'look', 'model']
const CAPTIONS: Record<EditTab, string> = { persona: '人设', look: '长相', model: '用的模型' }
const isCardTab = (value: string | undefined): value is CardTab =>
  value === 'status' || EDIT_TABS.includes(value as EditTab)

/** 页签里的一页：每页自己保存，不走设定那条底部保存栏 */
export interface TabPage {
  el: HTMLElement
  /** 离开小镇前列出没存的修改时用 */
  title: string
  isDirty(): boolean
  save(): void
  discard(): void
  onShow?(): void
  handleMsg?(msg: ServerMsg): void
}

/** 页签里各页要用的：哪位村民、怎么发消息和保存、改了告诉谁 */
export interface CardPageDeps {
  resident: ResidentContext
  send: (msg: ClientMsg) => void
  /** 发出保存命令；回执按请求编号回来，断线时以失败结束 */
  save: (command: SaveCommand, receipt: Receipt) => void
  onDirty: () => void
  /** 跳到右上角设定的某一页（「去配置这个服务」） */
  showPage: (id: string) => void
}

export interface CardEditorDeps {
  send: (msg: ClientMsg) => void
  save: (command: SaveCommand, receipt: Receipt) => void
  /** 打开右上角的设定，停在某一页 */
  openSettings: (pageId: string) => void
  residentName: (id: string) => string | undefined
}

export function createCardTabs(
  panel: HTMLElement,
  deps: CardEditorDeps,
  hooks: {
    /** 卡片拉到最宽（不记成本机偏好），关掉回到原来的宽度 */
    setWide: (on: boolean) => void
    /** 卡片变宽后，镜头把选中的人挪进露出来的地图 */
    reveal: () => void
  }
) {
  const tabButtons = [
    ...query(panel, '#info-tabs').querySelectorAll<HTMLButtonElement>('[data-tab]'),
  ]
  const host = query(panel, '#info-tab-page')
  const label = el('span')
  const edit = button('编辑', () => startEditing(), 'card-adjust')
  const caption = el('h3', '', 'card-caption card-tab-caption')
  caption.append(label, edit)
  const body = el('div', '', 'card-tab-body')
  const note = el('span', '', 'card-tab-note')
  const discardButton = button('放弃', () => discard())
  const saveButton = button('保存', () => current()?.save(), 'primary')
  const footer = el('div', '', 'card-tab-bar')
  footer.append(note, discardButton, saveButton)
  host.append(caption, body, footer)

  const pages = new Map<string, Record<EditTab, TabPage>>()
  let tab: CardTab = 'status'
  let residentId: string | null = null
  /** 人设在改原文（卡片拉宽、左原文右预览）；没在改时只看预览。有草稿时总在改 */
  let editing = false
  /** 正挂在卡片上的那一页：换了页才调 onShow */
  let shown: TabPage | null = null

  function pagesOf(id: string) {
    const known = pages.get(id)
    if (known) return known
    const pageDeps: CardPageDeps = {
      resident: { id, name: deps.residentName(id) ?? id },
      send: deps.send,
      save: (command, receipt) =>
        deps.save(command, (ok, message) => {
          receipt(ok, message)
          if (!ok) return
          // 重读这位村民的设定：人设原文、用的模型跟着更新
          deps.send({ type: 'get_agent_config', resident: id })
          // 人设存好了，回到只看预览，从头看起
          if (command.type === 'set_persona' && id === residentId && editing) {
            editing = false
            panel.scrollTop = 0
          }
          render()
        }),
      // 页还在建（编辑器初始化时也可能报一次改动）时不重画，免得重画里又来建它
      onDirty: () => {
        if (pages.has(id)) render()
      },
      showPage: deps.openSettings,
    }
    const made = {
      persona: createPersonaPage(pageDeps),
      look: createLookPage(pageDeps),
      model: createResidentModelPage(pageDeps),
    }
    pages.set(id, made)
    return made
  }
  function current(): TabPage | null {
    return tab === 'status' || !residentId ? null : pagesOf(residentId)[tab]
  }
  const wide = () => tab === 'look' || (tab === 'persona' && editing)

  function render() {
    // 手机外框看这个属性把抽屉拉满屏；只在换页时改，打字时不惊动它
    if (panel.dataset.tab !== tab) panel.dataset.tab = tab
    const own = residentId ? pages.get(residentId) : undefined
    for (const b of tabButtons) {
      const t = b.dataset.tab
      b.setAttribute('aria-selected', String(t === tab))
      b.tabIndex = t === tab ? 0 : -1
      b.classList.toggle('dirty', t !== 'status' && !!own?.[t as EditTab]?.isDirty())
    }
    const page = current()
    // 人设有草稿就停在编辑里（先定下来，下面按它决定卡片宽不宽）
    if (page && tab === 'persona' && page.isDirty()) editing = true
    host.hidden = !page
    if (page !== shown) {
      // 不在卡片上的页拿下来：长相预览的动画随之停下，草稿留在页里
      body.replaceChildren(...(page ? [page.el] : []))
      shown = page
      page?.onShow?.()
    }
    hooks.setWide(!!page && wide())
    if (!page || tab === 'status') return
    const dirty = page.isDirty()
    const viewing = tab === 'persona' && !editing
    host.dataset.mode = viewing ? 'view' : 'edit'
    label.textContent = CAPTIONS[tab]
    edit.hidden = !viewing
    footer.hidden = viewing
    saveButton.disabled = !dirty
    // 改人设时没动过也能点：回到只看预览
    const back = tab === 'persona' && !dirty
    discardButton.textContent = back ? '返回预览' : '放弃'
    discardButton.disabled = !dirty && !back
    note.textContent = dirty ? '有没保存的修改' : ''
  }

  function startEditing() {
    editing = true
    render()
    requestAnimationFrame(hooks.reveal)
    shown?.el.querySelector<HTMLTextAreaElement>('textarea')?.focus()
  }
  function discard() {
    const page = current()
    if (!page) return
    if (page.isDirty()) page.discard()
    if (tab === 'persona') editing = false
    panel.scrollTop = 0
    render()
  }
  function show(next: CardTab) {
    if (next === tab) return
    const wasWide = wide()
    tab = next
    editing = false
    panel.scrollTop = 0
    render()
    if (wide() && !wasWide) requestAnimationFrame(hooks.reveal)
  }

  tabButtons.forEach((b, i) => {
    b.onclick = () => {
      if (isCardTab(b.dataset.tab)) show(b.dataset.tab)
    }
    // 页签之间用左右键换
    b.onkeydown = (event) => {
      const step = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0
      if (!step) return
      event.preventDefault()
      const next = tabButtons[(i + step + tabButtons.length) % tabButtons.length]
      next.focus()
      next.click()
    }
  })
  render()

  return {
    show,
    tab: () => tab,
    /** 选中的人换了：页签停在原处，换成这个人的那一页（他的草稿还在） */
    setResident(id: string | null) {
      if (id === residentId) return
      residentId = id
      editing = false
      render()
    },
    /** 卡片收起：这一页没草稿就回到近况，下次打开从近况看起 */
    collapsed() {
      if (tab !== 'status' && !current()?.isDirty()) show('status')
    },
    /** 名册里还在的人：离开小镇的人，他的几页一起删掉 */
    keep(ids: Set<string>) {
      for (const [id, set] of pages) {
        if (ids.has(id)) continue
        for (const page of Object.values(set)) {
          page.el.remove()
          if (page === shown) shown = null
        }
        pages.delete(id)
      }
      render()
    },
    /** 配置、名册等消息交给已经建好的各页 */
    handleMsg(msg: ServerMsg) {
      for (const set of pages.values()) for (const page of Object.values(set)) page.handleMsg?.(msg)
    },
    /** 还没保存的修改（「某某的人设」），离开小镇前问一句 */
    unsaved() {
      return [...pages.values()].flatMap((set) =>
        Object.values(set).flatMap((page) => (page.isDirty() ? [page.title] : []))
      )
    },
  }
}
export type CardTabs = ReturnType<typeof createCardTabs>
