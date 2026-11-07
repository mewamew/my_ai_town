// 书与公告的编辑表单：标题、作者、放置地点（书）或公告栏（公告）、正文与字数，提示行和保存、取消按钮。
import { button, el, field, input, select } from './dom'
import type { ContentDetail, PropCatalog } from './types'

const MAX_TEXT = 4000

export class ContentForm {
  readonly form = el('form', '', 'content-form')
  readonly saveButton: HTMLButtonElement
  readonly location = select([], '', 'content-locale')
  readonly board = select([], '', 'content-board')
  private readonly title = input('', 'content-title')
  private readonly author = input('', 'content-author')
  private readonly body = el('textarea')
  private readonly locationField = field('放置地点', this.location)
  private readonly boardField = field('贴在哪块公告栏', this.board)
  private readonly counter = el('small', `0 / ${MAX_TEXT} 字`, 'prop-muted')
  /** 保存的结果和填写问题写在按钮上面：页面顶上的状态行这时多半已经滚出屏幕 */
  private readonly notice = el('p', '', 'content-form-notice')
  private readonly catalog: () => PropCatalog | null

  constructor(actions: {
    save: () => void
    discard: () => void
    catalog: () => PropCatalog | null
  }) {
    const { form, title, author, body } = this
    this.catalog = actions.catalog
    title.maxLength = 80
    author.maxLength = 80
    body.name = 'content-text'
    body.maxLength = MAX_TEXT
    body.rows = 10
    form.append(
      field('标题（最多 80 字）', title),
      field('作者显示名（最多 80 字）', author),
      this.locationField,
      this.boardField,
      field('正文', body),
      this.counter,
      this.notice
    )
    this.saveButton = button('保存到当前世界', actions.save, 'prop-primary')
    const buttons = el('div', '', 'content-form-actions')
    buttons.append(this.saveButton, button('取消编辑', actions.discard))
    form.append(buttons)
    form.hidden = true
    form.onsubmit = (e) => {
      e.preventDefault()
      actions.save()
    }
    body.oninput = () => this.count()
    this.board.onchange = () => this.placeOnBoard()
  }

  count() {
    this.counter.textContent = `${[...this.body.value].length} / ${MAX_TEXT} 字`
  }

  focus() {
    this.title.focus()
  }

  /** 按钮上面的提示；有内容时滚到看得见的地方 */
  say(text: string, bad = false) {
    this.notice.textContent = text
    this.notice.classList.toggle('error', bad)
    if (text) this.notice.scrollIntoView({ block: 'nearest' })
  }

  /** 公告栏下拉框：列出所有没撤下的公告栏，带上所在地点，没有公告栏的地点根本不出现 */
  private boards(catalog: PropCatalog | null) {
    const { board } = this
    const previous = board.value
    const place = (id: string) => catalog?.locations.find((l) => l.id === id)?.name ?? id
    board.replaceChildren()
    for (const p of catalog?.instances ?? [])
      if (p.bulletin_board && !p.withdrawn)
        board.append(new Option(`${p.name}（${place(p.locale)}）`, p.id))
    if ([...board.options].some((o) => o.value === previous)) board.value = previous
  }

  /** 公告贴在所选公告栏所在的地点 */
  private placeOnBoard() {
    const p = this.catalog()?.instances.find((i) => i.id === this.board.value)
    if (p) this.location.value = p.locale
  }

  /** 开始编辑：新写时清空；修订公告时带入原文，公告栏不能改。
   *  书选放在哪个地点；公告只选公告栏，地点跟着公告栏走。preset 是新写时预先选好的地点或公告栏 */
  fill(
    catalog: PropCatalog,
    source: ContentDetail | null,
    book: boolean,
    preset?: { locale?: string; board?: string } | null
  ) {
    const { location, board } = this
    this.title.value = source?.content?.title ?? ''
    this.author.value = source?.content?.author ?? ''
    this.body.value = source?.content?.text ?? ''
    location.replaceChildren(...catalog.locations.map((l) => new Option(l.name, l.id)))
    location.disabled = !!source
    this.locationField.hidden = !book
    this.boardField.hidden = book
    this.boards(catalog)
    board.disabled = !!source
    if (source) {
      location.value = source.locale
      board.value = source.board ?? ''
    } else if (book) {
      if (preset?.locale) location.value = preset.locale
    } else {
      if ([...board.options].some((o) => o.value === preset?.board))
        board.value = preset?.board ?? ''
      this.placeOnBoard()
    }
    this.saveButton.textContent = book ? '保存这本书' : source ? '保存修订' : '张贴公告'
    this.say(
      !book && !board.options.length
        ? '这个世界还没有公告栏。先在「道具」里放一块公告栏，再来张贴。'
        : '',
      true
    )
  }

  /** 标题、作者与正文；有空项或正文超长时为 null */
  read() {
    const { title, author, body } = this
    if (
      !title.value.trim() ||
      !author.value.trim() ||
      !body.value.trim() ||
      [...body.value].length > MAX_TEXT
    )
      return null
    return { title: title.value.trim(), author: author.value.trim(), text: body.value.trim() }
  }
}
