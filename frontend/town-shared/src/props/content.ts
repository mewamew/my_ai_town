// 当前世界的书与公告：作品列表、正文、新写与修订，挂在「书与公告」页（books.ts）。
// 列表是默认样子；点开一篇或写新作品时列表让位，单独占一栏。正文只在明确请求详情后返回。
// 编辑表单在 contentForm.ts。
import type { ClientMsg, ServerMsg, ContentCommand } from '../protocol'
import {
  isContentDetail,
  type ContentDetail,
  type ContentText,
  type PropCatalog,
  type PropView,
} from './types'
import { announcer, el, button } from './dom'
import { newId } from '../ids'
import './style.css'
import './content.css'
import { propPicture } from './picture'
import { chip, slot } from '../design/ui'
import { gameIcon, iconLabel } from '../game/icons'
import { segmented } from '../settings/controls'
import { onBack } from '../platform'
import { ContentForm } from './contentForm'

/** 只看一处：地图上点一摞书是这个地点的书，点公告栏是这块栏上的公告 */
export interface ContentScope {
  kind: 'book' | 'bulletin'
  locale?: string
  board?: string
}

interface ContentHooks {
  /** 正文里的「在地图上定位」 */
  locate?: (id: string, locale: string) => void
  /** 列表里标「新」的作品 */
  isNew?: (id: string) => boolean
  /** 作品露在列表里或被点开：算看过 */
  seen?: (ids: string[]) => void
}

export function createContentManager(send: (m: ClientMsg) => void, hooks: ContentHooks = {}) {
  const panel = new ContentPanel(send, hooks)
  return {
    el: panel.root,
    /** 回到作品列表，看全部 */
    list: () => panel.list(null),
    /** 回到作品列表，只看一处 */
    scope: (scope: ContentScope) => panel.list(scope),
    /** 点开一篇 */
    show: (id: string) => panel.show(id),
    discard: () => panel.discard(),
    isDirty: () => panel.editing,
    disconnected: () => panel.disconnected(),
    handleMsg: (msg: ServerMsg) => panel.handleMsg(msg),
  }
}

/** 公告贴在哪：公告栏的名字里已经带着地点名时只写公告栏 */
function boardPlace(place: string, board: string | null | undefined) {
  if (!board) return place
  return board.includes(place) ? board : `${place} · ${board}`
}

/** 作者一行：作者名，村民写的、玩家写的各标一句，改过的写改过几次 */
function byline(t: ContentText) {
  const origin =
    t.origin.kind === 'resident' ? ' · 村民写的' : t.origin.kind === 'player' ? ' · 玩家写的' : ''
  return `${t.author}${origin}${t.version > 1 ? ` · 改过 ${t.version - 1} 次` : ''}`
}

class ContentPanel {
  readonly root = el('section', '', 'content-manager')
  private readonly status = el('p', '正在读取当前世界道具…', 'prop-status')
  /** 只看一处时写在列表上面，带一个「看全部作品」 */
  private readonly scopeLine = el('p', '', 'content-scope')
  private readonly items = el('div', '', 'content-list')
  private readonly detail = el('article', '', 'content-detail')
  private readonly empty = el(
    'p',
    '点一本查看或修改正文。玩家看正文不会让村民知道内容，村民要自己去读。',
    'content-empty'
  )
  private readonly announceTop = announcer(this.status)
  /** 点开一篇或写新作品时列表让位（content.css 的 focused）；这个钮退回列表 */
  private readonly back = button(
    '',
    () => {
      this.unfocus()
      this.render()
    },
    'content-back'
  )
  private offBack: (() => void) | null = null
  private readonly kind: ReturnType<typeof segmented>
  private readonly form: ContentForm
  private readonly send: (m: ClientMsg) => void
  private readonly hooks: ContentHooks
  /** 作品类型筛选：空为全部 */
  private filter = ''
  private scope: ContentScope | null = null
  private catalog: PropCatalog | null = null
  private selected: ContentDetail | null = null
  editing = false
  /** 等回执期间不再发新请求 */
  private busy = false
  private mode: 'book' | 'bulletin' | 'revise' = 'book'
  /** 新作品的编号：这次编辑重发保存时沿用，服务端不会建出第二本 */
  private createId = ''
  private activeRequest = ''
  private readonly pending = new Map<string, 'detail' | 'save'>()
  private connected = false

  constructor(send: (m: ClientMsg) => void, hooks: ContentHooks) {
    this.send = send
    this.hooks = hooks
    this.status.setAttribute('aria-live', 'polite')
    this.kind = segmented(
      '作品类型',
      [
        { value: '', label: '全部' },
        { value: 'book', label: '书' },
        { value: 'bulletin', label: '公告' },
      ],
      (value) => {
        this.filter = value
        this.kind.set(this.filter)
        this.render()
      }
    )
    this.kind.set(this.filter)
    this.form = new ContentForm({
      save: () => this.save(),
      discard: () => this.discard(),
      catalog: () => this.catalog,
    })
    // 作品列表随后端的 props 广播自动更新（道具变化和保存成功后都会推），不需要刷新按钮
    const toolbar = el('div', '', 'props-controls content-toolbar')
    toolbar.append(
      button('新写一本书', () => this.start('book')),
      button('张贴公告', () => this.start('bulletin')),
      el('span', '', 'content-toolbar-gap'),
      this.kind.el
    )
    iconLabel(this.back, 'back', '全部作品')
    this.scopeLine.hidden = true
    this.root.append(
      toolbar,
      this.scopeLine,
      this.status,
      this.items,
      this.empty,
      this.back,
      this.detail,
      this.form.form
    )
  }

  /** 页面顶上的状态行；编辑表单开着时同一句话也写到表单的按钮上面，不然点了保存像没反应 */
  private announce(text: string, bad = false) {
    this.announceTop(text, bad)
    if (this.editing && text) this.form.say(text, bad)
  }

  /** 只看这一篇（或这张表单）：滚回顶上；返回键先退回列表 */
  private focus() {
    this.root.classList.add('focused')
    this.root.parentElement?.scrollTo({ top: 0 })
    // 整页的返回键先登记，这里后登记的先问；页面被盖住或已离开时不拦
    this.offBack ??= onBack(() => {
      if (!this.root.classList.contains('focused') || !this.root.getClientRects().length)
        return false
      if (this.editing) this.announce('先保存或取消当前编辑。', true)
      else {
        this.unfocus()
        this.render()
      }
      return true
    })
  }

  /** 退回列表：刚才那篇不再算选中，列表里不留高亮 */
  private unfocus() {
    this.root.classList.remove('focused')
    this.offBack?.()
    this.offBack = null
    if (this.editing) return
    this.selected = null
    this.renderDetail()
  }

  /** 回到作品列表：scope 为空时看全部，否则只看那一处，类型筛选跟着换。正在写时不打断 */
  list(scope: ContentScope | null) {
    if (!this.editing) {
      this.scope = scope
      this.filter = scope?.kind ?? ''
      this.kind.set(this.filter)
      this.unfocus()
      this.clearNotice()
    }
    this.render()
  }

  /** 上一回操作留下的提示（「先保存或取消」、保存失败）不留到下一回；断线的提示留着 */
  private clearNotice() {
    if (this.connected) this.announce('')
  }

  /** 作品列表；编辑中或等回执时卡片不能点 */
  private render() {
    const { catalog, items, scope } = this
    if (!catalog) return
    items.replaceChildren()
    const all = catalog.instances.flatMap((p) =>
      p.readable ? [{ prop: p, text: p.readable }] : []
    )
    this.kind.relabel('', `全部 ${all.length}`)
    const books = all.filter(
      ({ prop, text }) =>
        (!this.filter || text.kind === this.filter) &&
        (!scope?.locale || prop.locale === scope.locale) &&
        (!scope?.board || prop.board === scope.board)
    )
    if (!books.length)
      items.append(
        el(
          'p',
          scope?.board ? '这块公告栏上还没有公告。' : '这里还没有符合条件的作品。',
          'prop-muted'
        )
      )
    for (const { prop, text } of books) {
      const place = catalog.locations.find((l) => l.id === prop.locale)?.name ?? prop.locale
      items.append(this.card(prop, text, place))
    }
    this.renderScope()
    this.empty.hidden = !!this.selected || this.editing
    if (!this.busy && !this.status.classList.contains('error'))
      this.announce(catalog.persistent ? '' : '本次运行未启用磁盘存档，作品不会保留。')
    // 列表露着的时候，上面的作品都算看过；正在点开一篇时列表马上要让位，不算
    const opening = [...this.pending.values()].includes('detail')
    if (!this.root.classList.contains('focused') && !opening)
      this.hooks.seen?.(books.map(({ prop }) => prop.id))
  }

  /** 只看一处时：「只看「图书馆」的书 · 看全部作品」 */
  private renderScope() {
    const { scope, catalog, scopeLine } = this
    scopeLine.hidden = !scope
    if (!scope || !catalog) return
    let what: string
    if (scope.board) {
      const board = catalog.instances.find((p) => p.id === scope.board)
      const place = catalog.locations.find((l) => l.id === board?.locale)?.name ?? ''
      what = `「${boardPlace(place, board?.name) || '这块公告栏'}」上的公告`
    } else {
      const place = catalog.locations.find((l) => l.id === scope.locale)?.name ?? '这里'
      what = `「${place}」的${scope.kind === 'bulletin' ? '公告' : '书'}`
    }
    scopeLine.replaceChildren(
      el('span', `只看${what}`),
      button('看全部作品', () => this.list(null), 'ui-btn ghost')
    )
  }

  private card(prop: PropView, text: NonNullable<PropView['readable']>, place: string) {
    const card = button('', () => this.show(prop.id), 'content-card')
    card.classList.toggle('selected', this.selected?.id === prop.id)
    const body = el('span', '', 'content-card-text')
    const tags = el('span', '', 'content-card-tags')
    tags.append(chip(text.kind === 'book' ? '书' : '公告'))
    if (this.hooks.isNew?.(prop.id)) tags.append(chip('新', 'ok'))
    body.append(
      tags,
      el('b', text.title),
      el('small', `${text.author} · 放在${place}${prop.withdrawn ? ' · 已撤下' : ''}`)
    )
    card.append(
      slot(propPicture(prop.definition ?? prop.id, text.kind === 'book' ? 'book' : 'status'), 'sm'),
      body
    )
    card.disabled = this.editing || this.busy
    return card
  }

  private request(command: ContentCommand, kind: 'detail' | 'save') {
    const { catalog } = this
    if (!catalog || this.busy) return
    if (!this.connected) {
      this.announce('连接尚未恢复，编辑内容已保留。请稍后重试。', true)
      return
    }
    const request_id = newId()
    this.pending.set(request_id, kind)
    this.activeRequest = request_id
    this.busy = true
    this.form.saveButton.disabled = true
    this.send({ type: 'content', request_id, world_id: catalog.world_id, command })
    this.announce(kind === 'detail' ? '正在读取正文…' : '正在保存…')
  }

  /** 回执到了或连接断了：可以再发请求 */
  private idle() {
    this.busy = false
    this.form.saveButton.disabled = false
  }

  show(id: string) {
    if (this.editing) {
      this.announce('先保存或取消当前编辑。', true)
      return
    }
    this.request({ operation: 'detail', id }, 'detail')
  }

  /** 选中作品的正文与出处；公告还没撤下时可以修订或撤下 */
  private renderDetail() {
    const { detail, catalog } = this
    detail.replaceChildren()
    const d = this.selected
    this.empty.hidden = !!d || this.editing
    if (!d) return
    const t = d.content
    const place = catalog?.locations.find((l) => l.id === d.locale)?.name ?? d.locale
    // 作品还没有任何版本时没有正文可显示
    if (!t) {
      detail.append(el('p', `这件作品还没有正文 · 位置：${place}`, 'prop-muted'))
      return
    }
    const head = el('header', '', 'cd-head')
    const meta = el('div', '', 'cd-meta')
    const where = el('p', '', 'ui-kicker')
    where.append(
      gameIcon('pin'),
      `${boardPlace(place, d.board && catalog?.instances.find((p) => p.id === d.board)?.name)}${d.withdrawn ? ' · 已撤下' : ''}`
    )
    meta.append(
      chip(t.kind === 'book' ? '书' : '公告'),
      el('h3', t.title, 'ui-title'),
      el('p', byline(t), 'cd-by'),
      where
    )
    head.append(
      slot(
        propPicture(
          catalog?.instances.find((p) => p.id === d.id)?.definition ?? d.id,
          t.kind === 'book' ? 'book' : 'status'
        ),
        'md'
      ),
      meta
    )
    detail.append(head, el('p', t.text, 'content-body'))
    const foot = el('div', '', 'cd-foot')
    const locate = this.hooks.locate
    if (locate) foot.append(button('在地图上定位', () => locate(d.board ?? d.id, d.locale)))
    if (t.kind === 'bulletin' && !d.withdrawn)
      foot.append(
        button('修订公告', () => this.start('revise')),
        button('撤下公告', () =>
          this.request({ operation: 'withdraw', id: d.id, expected_version: t.version }, 'save')
        )
      )
    if (foot.childElementCount) detail.append(foot)
  }

  /** 新写一本书、张贴公告，或修订选中的公告 */
  private start(next: 'book' | 'bulletin' | 'revise') {
    const { catalog } = this
    if (!catalog || this.busy) return
    if (this.editing) {
      this.announce('先保存或取消当前编辑。', true)
      return
    }
    const source = next === 'revise' ? this.selected : null
    if (next === 'revise' && !source) return
    this.mode = next
    this.createId = `user:${newId()}`
    this.editing = true
    this.form.form.hidden = false
    this.detail.hidden = true
    // 写的时候只能保存或取消，「全部作品」先收起来，免得表单被藏到列表后面
    this.back.hidden = true
    // 从一摞书或一块公告栏进来的：新书放在那个地点，新公告贴在那块栏上
    this.form.fill(catalog, source, next === 'book', this.scope)
    this.render()
    this.focus()
    this.form.count()
    this.form.focus()
  }

  /** 收起表单，回到作品详情 */
  private closeForm() {
    this.editing = false
    this.form.form.hidden = true
    this.detail.hidden = false
    this.back.hidden = false
  }

  discard() {
    if (this.busy) return
    this.closeForm()
    this.clearNotice()
    // 从列表写新作品时取消：回到列表；修订时取消：回到那篇的正文
    if (!this.selected) this.unfocus()
    this.render()
  }

  save() {
    const { catalog, form } = this
    if (!this.editing || this.busy || !catalog) return
    const fields = form.read()
    if (!fields) {
      this.announce('请填写标题、作者和正文；正文最多 4000 字。', true)
      return
    }
    if (this.mode === 'revise') {
      const selected = this.selected
      if (!selected?.content) return
      const expected_version = selected.content.version
      this.request({ operation: 'revise', id: selected.id, expected_version, ...fields }, 'save')
      return
    }
    if (this.mode === 'bulletin' && !form.board.value) {
      this.announce('先选一块公告栏；这个世界还没有公告栏的话，先在「道具」里放一块。', true)
      return
    }
    this.request(
      {
        operation: 'create',
        id: this.createId,
        locale: form.location.value,
        board: this.mode === 'bulletin' ? form.board.value : undefined,
        ...fields,
      },
      'save'
    )
  }

  /** 换了世界：丢掉等回执的请求和编辑中的内容 */
  private resetForWorld() {
    this.pending.clear()
    this.idle()
    this.closeForm()
    this.selected = null
    this.scope = null
    this.activeRequest = ''
    this.unfocus()
    this.renderDetail()
  }

  disconnected() {
    this.connected = false
    this.pending.clear()
    this.activeRequest = ''
    this.idle()
    this.announce('连接已断开，编辑内容已保留。恢复后可重试；已保存的新增作品不会重复创建。', true)
    this.render()
  }

  handleMsg(msg: ServerMsg) {
    if (msg.type === 'props') this.onCatalog(msg.catalog)
    // 命令没能执行（格式错误、命令过多）时回的是通用错误，同样结束这次请求
    else if (msg.type === 'error' && msg.request_id === this.activeRequest) {
      this.pending.delete(this.activeRequest)
      this.idle()
      this.announce(msg.message, true)
    } else if (
      msg.type === 'prop_result' &&
      this.pending.has(msg.request_id) &&
      msg.request_id === this.activeRequest
    )
      this.onResult(msg)
  }

  private onCatalog(next: PropCatalog) {
    if (!this.connected && this.catalog) this.announce('连接已恢复，编辑内容已保留。')
    this.connected = true
    if (this.catalog && this.catalog.world_id !== next.world_id) this.resetForWorld()
    this.catalog = next
    this.render()
  }

  private onResult(msg: Extract<ServerMsg, { type: 'prop_result' }>) {
    const kind = this.pending.get(msg.request_id)
    this.pending.delete(msg.request_id)
    this.idle()
    if (!msg.ok) {
      this.announce(msg.message, true)
      return
    }
    if (isContentDetail(msg.preview)) {
      this.selected = msg.preview
      this.hooks.seen?.([msg.preview.id])
    }
    if (kind === 'save') this.closeForm()
    this.renderDetail()
    if (kind === 'detail') this.focus()
    this.announce(kind === 'save' ? '已保存到当前世界。' : '正文已载入。')
    this.send({ type: 'get_props' })
  }
}
