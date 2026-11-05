// 地图左上角的头像条：一人一格，扫一眼就知道谁有状况；点头像镜头过去，打开角色卡。
// 圆点说好坏（绿正常、橙要留意、红危险、灰停了），右上角标说原因（饿渴累伤、停下、在聊），
// 只看名册里的枚举和数值，不拿中文做判断。顺序按入住登记固定，走动、出状况都不换位置。
// 鼠标悬停弹出近况卡；触屏没有悬停，点一下直接看角色卡。人多了收成只有头像的小格（触屏照样留名字）。
// 控制化身时整条藏起来（样式按 html.avatar-controlling）：那时点人是走过去，角色卡也不开。
// 地图顶部正中的提示（暂停、快进、等模型、提示卡）和头像条左右叠上时，往下让出头像条的高度。
// 末尾的「邀请」打开村民页（新建村民、从村民库挑选、名册）：电脑上请人入住只走这里，顶栏不再单放
// 一个村民按钮；空镇子时整条只剩它，用主色描出来（样式按 html[data-empty-town]）。
import { button, el } from '../dom'
import { chip } from '../design/ui'
import { agentStopped } from '../display'
import { playerText } from '../format'
import { gameIcon } from '../game/icons'
import type { GameMap, ResidentEntry } from '../gameMap'
import { agentStateLabels } from '../labels'
import { CLOSE_UP_WIDTH } from '../mapView'
import { isTouch } from '../platform'
import { byJoinOrder, onPopulation, residentPortraitUrl } from '../portraits'
import type { NeedStateView, RosterMember } from '../protocol'
import type { RosterFrame, ShellPanel } from '../shell/panel'
import { NEED_ICONS, NEED_ORDER, worstNeed } from './needs'
import './strip.css'

/** 超过这么多人收成只有头像的小格 */
const MANY = 8
/** 收起与否记在本机 */
const FOLD_KEY = 'town-resident-strip-folded'
/** 地图顶部正中的提示：和头像条左右叠上时往下让 */
const HINTS = '.pause-hint, .fast-hint, .model-wait, .town-notices, .avatar-toast, .place-hint'
const CONDITIONS = { injury: '受伤', illness: '患病', poison: '中毒' } as const

type Tone = 'ok' | 'busy' | 'danger' | 'off'
interface Status {
  tone: Tone
  /** 右上角标的图标名；没有就不挂 */
  badge: string | null
  /** 出了什么状况的一句短话：近况卡上的标签和读屏文字；没状况为空 */
  issue: string
}

/** 需求的短说法：后端那句话取逗号前一截（「很饿，需要进食」→「很饿」） */
const needShort = (n: NeedStateView) => (n.text || n.need).split(/[，,]/)[0]

/** 此刻好不好：去世 > 需要救助、需求告急 > 自己停下、等模型 > 被附身、在聊 */
function statusOf(m: RosterMember): Status {
  if (m.body?.life === 'dead') return { tone: 'off', badge: null, issue: '已去世' }
  const state = m.resident_agent?.state
  if (state === 'rescue') return { tone: 'danger', badge: 'heart', issue: agentStateLabels.rescue }
  const need = worstNeed(m.needs ?? [])
  if (need)
    return {
      // 健康掉到危险就算危险；别的需求到「严重」才算
      tone: need.kind === 'health' || need.band === 'collapse' ? 'danger' : 'busy',
      badge: NEED_ICONS[need.kind],
      issue: needShort(need),
    }
  if (state && (agentStopped(m) || state === 'no_model'))
    return {
      tone: 'off',
      badge: state === 'no_model' ? 'clock' : 'pause',
      issue: agentStateLabels[state],
    }
  if (state === 'manual') return { tone: 'ok', badge: 'person', issue: '' }
  return { tone: 'ok', badge: m.chat ? 'chat' : null, issue: '' }
}

interface StripDeps {
  map: GameMap
  /** 地图容器：头像条和近况卡都放在里面 */
  container: HTMLElement
  localeName: (id: string) => string
  /** 点头像：选中并打开角色卡 */
  open: (id: string) => void
  /** 点末尾的「邀请」：打开村民页 */
  invite: () => void
  /** 正在选中谁 */
  selected: () => string | null
  /** 控制化身中：点头像和数字键都不接 */
  avatarActive: () => boolean
}

interface Tile {
  root: HTMLButtonElement
  face: HTMLElement
  pic: HTMLElement
  badge: HTMLElement
  name: HTMLElement
  /** 上次画的内容和头像；没变就不动 DOM */
  drawn: string
  portrait: string | null
}

export function createResidentStrip(deps: StripDeps) {
  const { container } = deps
  const listeners = new AbortController()
  const { signal } = listeners
  const root = el('div', '', 'resident-strip')
  root.setAttribute('role', 'toolbar')
  root.setAttribute('aria-label', '村民')
  root.hidden = true
  // 和头像同一种格子，虚线框里一个加号：看得出是空位，不是一位村民
  const add = button('', () => deps.invite(), 'strip-tile strip-add')
  const addFace = el('span', '', 'strip-face')
  addFace.append(gameIcon('plus', true))
  add.append(addFace, el('span', '邀请', 'strip-name'))
  add.title = '邀请村民：新建，或从村民库挑选'
  add.setAttribute('aria-label', '邀请村民')
  const fold = button('', () => setFolded(true), 'strip-fold')
  fold.append(gameIcon('chevron', true))
  fold.title = '收起头像条'
  fold.setAttribute('aria-label', '收起头像条')
  const count = el('span')
  const alerts = el('span', '', 'strip-alerts')
  const unfold = button('', () => setFolded(false), 'strip-unfold')
  unfold.append(gameIcon('people', true), count, alerts)
  root.append(add, fold, unfold)
  const peek = el('div', '', 'strip-peek')
  peek.id = 'strip-peek'
  peek.setAttribute('role', 'tooltip')
  peek.hidden = true
  container.append(root, peek)
  // 按下不能漏给地图：不然会被当成拖动地图的起点，双击会放大
  for (const type of ['pointerdown', 'dblclick'])
    root.addEventListener(type, (e) => e.stopPropagation(), { signal })
  // 用鼠标点头像不抢焦点：接着按空格还是开始/暂停世界，不会又点一次头像；键盘 Tab 过来照样能按
  root.addEventListener('mousedown', (e) => e.preventDefault(), { signal })

  const tiles = new Map<string, Tile>()
  /** 最近一份名册里的人 */
  let entries = new Map<string, ResidentEntry>()
  /** 头像的顺序：按入住登记 */
  let order: string[] = []
  /** 上次写到收起钮上的人数和要留意的人数 */
  let counted = ''
  /** 收到过名册：之前整条不出，免得先只露一个「邀请」、人到了再把它挤到后面 */
  let rostered = false
  let folded = false
  try {
    folded = localStorage.getItem(FOLD_KEY) === '1'
  } catch {
    /* 私密窗口等拿不到本机存储时默认展开 */
  }
  root.classList.toggle('folded', folded)

  function setFolded(next: boolean) {
    const keyboard = root.contains(document.activeElement)
    folded = next
    root.classList.toggle('folded', next)
    hidePeek()
    try {
      if (next) localStorage.setItem(FOLD_KEY, '1')
      else localStorage.removeItem(FOLD_KEY)
    } catch {
      /* 记不住就只管这一次 */
    }
    // 用键盘按的：刚按的钮藏起来了，焦点交给换出来的那个钮，接着按
    if (keyboard) (next ? unfold : fold).focus({ preventScroll: true })
    scheduleLayout()
  }

  function createTile(id: string): Tile {
    const tile: Tile = {
      root: button('', () => activate(id), 'strip-tile'),
      face: el('span', '', 'strip-face'),
      pic: el('span', '', 'strip-pic'),
      badge: el('span', '', 'strip-badge'),
      name: el('span', '', 'strip-name'),
      drawn: '',
      portrait: null,
    }
    tile.root.dataset.id = id
    tile.face.append(tile.pic, el('span', '', 'strip-dot'), tile.badge)
    tile.root.append(tile.face, tile.name)
    tile.root.addEventListener('pointerenter', (e) => {
      if (e.pointerType === 'mouse') showPeek(id)
    })
    tile.root.addEventListener('pointerleave', () => hidePeek(id))
    tile.root.addEventListener('focus', () => {
      if (tile.root.matches(':focus-visible')) showPeek(id)
    })
    tile.root.addEventListener('blur', () => hidePeek(id))
    return tile
  }

  function paint(tile: Tile, m: RosterMember) {
    // 登记到了用像素头像；还没到先写名字的第一个字
    const portrait = residentPortraitUrl(m.id)
    const pic = portrait ?? m.name.slice(0, 1)
    if (pic !== tile.portrait) {
      tile.portrait = pic
      if (portrait) {
        const img = el('img')
        img.src = portrait
        img.alt = ''
        tile.pic.replaceChildren(img)
      } else tile.pic.replaceChildren(el('span', pic, 'strip-initial'))
    }
    const status = statusOf(m)
    const state = m.resident_agent ? agentStateLabels[m.resident_agent.state] : ''
    const drawn = JSON.stringify([m.name, status, state])
    if (drawn === tile.drawn) return
    tile.drawn = drawn
    tile.root.dataset.tone = status.tone
    tile.root.classList.toggle('dead', m.body?.life === 'dead')
    const word = status.issue || state
    tile.root.setAttribute('aria-label', word ? `${m.name}，${word}` : m.name)
    tile.name.textContent = m.name
    tile.badge.hidden = !status.badge
    tile.badge.replaceChildren(...(status.badge ? [gameIcon(status.badge, true)] : []))
  }

  /** 名册或人口变了：增删头像、按登记顺序排、重画有变化的格子 */
  function render() {
    for (const [id, tile] of tiles)
      if (!entries.has(id)) {
        tile.root.remove()
        tiles.delete(id)
      }
    let attention = 0
    for (const id of order) {
      let tile = tiles.get(id)
      if (!tile) {
        tile = createTile(id)
        tiles.set(id, tile)
      }
      paint(tile, entries.get(id)!.member)
      if (tile.root.dataset.tone === 'busy' || tile.root.dataset.tone === 'danger') attention++
    }
    const shown = [...root.querySelectorAll<HTMLElement>(':scope > .strip-tile[data-id]')]
    if (shown.map((node) => node.dataset.id).join('\n') !== order.join('\n'))
      for (const id of order) root.insertBefore(tiles.get(id)!.root, add)
    const summary = `${rostered}/${order.length}/${attention}`
    if (summary !== counted) {
      counted = summary
      root.hidden = !rostered
      // 空镇子没什么可收的：收起钮不出，收起过也照样露出「邀请」
      fold.hidden = !order.length
      root.classList.toggle('folded', folded && order.length > 0)
      root.classList.toggle('many', order.length > MANY)
      count.textContent = `村民 ${order.length}`
      alerts.hidden = !attention
      alerts.textContent = String(attention)
      unfold.setAttribute(
        'aria-label',
        `展开头像条：村民 ${order.length} 人${attention ? `，${attention} 人要留意` : ''}`
      )
    }
    mark()
    if (peekId) renderPeek()
    scheduleLayout()
  }

  /** 选中的人高亮：地图上点人、角色卡换人、提示卡「查看」都会改 */
  function mark() {
    const id = deps.selected()
    for (const [tid, tile] of tiles) {
      const pressed = String(tid === id)
      if (tile.root.getAttribute('aria-pressed') !== pressed)
        tile.root.setAttribute('aria-pressed', pressed)
    }
  }

  // ---------- 点头像：选中、打开角色卡，镜头过去 ----------
  function activate(id: string) {
    if (deps.avatarActive()) return
    hidePeek()
    deps.open(id)
    lookAt(id)
  }

  /** 镜头对准这个人：看整图时先拉近，再挪到露出来的那块中间；本来就看得见就不动。
   *  已经选中的人再点一次也走这里，拖开地图后点一下就找回来 */
  function lookAt(id: string) {
    const { map } = deps
    const pos = map.getMemberPos(id)
    if (!pos) return
    const view = map.getViewBox()
    if (view[2] > CLOSE_UP_WIDTH) {
      const width = CLOSE_UP_WIDTH
      const height = (width * view[3]) / view[2]
      map.setViewBox([pos[0] - width / 2, pos[1] - height / 2, width, height])
    }
    map.panTo(pos[0], pos[1])
  }

  // 数字键 1–9 跳到对应的头像（和悬停时卡片角上写的数字一样）
  window.addEventListener(
    'keydown',
    (e) => {
      if (e.repeat || e.ctrlKey || e.metaKey || e.altKey || e.isComposing) return
      if (e.key.length !== 1 || !'123456789'.includes(e.key)) return
      const id = order[Number(e.key) - 1]
      if (!id || !keysFree(e.target)) return
      e.preventDefault()
      activate(id)
    },
    { signal }
  )
  /** 数字键给别的东西用的时候不接：打字、开着对话框或开局向导、地图页没显示、控制化身中 */
  function keysFree(target: EventTarget | null) {
    if (deps.avatarActive() || root.hidden || !container.getClientRects().length) return false
    if (document.querySelector('dialog[open], .guide:not([hidden])')) return false
    return !(
      target instanceof HTMLElement &&
      (target.isContentEditable || target.closest('input, textarea, select'))
    )
  }

  // ---------- 悬停的近况卡 ----------
  let peekId: string | null = null
  function showPeek(id: string) {
    if (peekId && peekId !== id) hidePeek()
    peekId = id
    tiles.get(id)?.root.setAttribute('aria-describedby', peek.id)
    renderPeek()
  }
  function hidePeek(id = peekId) {
    if (!id || id !== peekId) return
    tiles.get(id)?.root.removeAttribute('aria-describedby')
    peekId = null
    peek.hidden = true
  }

  /** 在哪、在做什么：路上写去哪还要多久，在聊写和谁 */
  function whereOf({ locale, member: m }: ResidentEntry) {
    const place = deps.localeName(locale)
    if (m.body?.life === 'dead') return place
    const at = m.at
    if (at.kind === 'transit')
      return `在路上，去${deps.localeName(at.toward)}（还要约 ${Math.max(1, Math.round(at.total - at.elapsed))} 分钟）`
    const others = m.chat?.participants.filter((name) => name !== m.name) ?? []
    const doing = m.chat ? (others.length ? `和${others.join('、')}交谈` : '在交谈') : m.verb
    return doing ? `${place} · ${doing}` : place
  }

  /** 四项身体状态的小条：数值和颜色同角色卡，世界设定关掉的项不画 */
  function needBars(list: NeedStateView[]) {
    const byKind = new Map(list.map((n) => [n.kind, n]))
    const rows = NEED_ORDER.flatMap((kind) => {
      const n = byKind.get(kind)
      if (!n) return []
      const row = el('div', '', 'peek-need')
      row.dataset.need = kind
      row.dataset.band = n.band
      const bar = el('span', '', 'peek-bar')
      bar.style.setProperty('--v', String(Math.min(Math.max(n.value, 0), 100) / 100))
      bar.append(el('span'))
      row.append(gameIcon(NEED_ICONS[kind], true), el('span', n.need), bar)
      return [row]
    })
    if (!rows.length) return []
    const box = el('div', '', 'peek-needs')
    box.append(...rows)
    return [box]
  }

  function renderPeek() {
    const entry = peekId ? entries.get(peekId) : undefined
    const tile = peekId ? tiles.get(peekId) : undefined
    if (!entry || !tile || root.hidden || folded) return hidePeek()
    const m = entry.member
    const status = statusOf(m)
    const dead = m.body?.life === 'dead'
    const head = el('div', '', 'peek-head')
    head.append(el('b', m.name))
    if (status.issue) {
      const tag = chip(
        status.issue,
        status.tone === 'danger' ? 'danger' : status.tone === 'busy' ? 'busy' : undefined
      )
      // 和角标同一套线条图标
      if (status.badge) tag.prepend(gameIcon(status.badge, true))
      head.append(tag)
    }
    const agent = m.resident_agent
    const state = agent && !dead ? agentStateLabels[agent.state] : ''
    // 需要救助、故障暂停这类，标签已经写了，右边不再重复
    if (state && state !== status.issue) head.append(el('span', state, 'peek-state'))
    const lines = [head, el('div', whereOf(entry), 'peek-where')]
    if (agent?.reason && agentStopped(m))
      lines.push(el('div', `停下了：${playerText(agent.reason)}`, 'peek-note'))
    const ill = [...new Set((m.body?.conditions ?? []).map((c) => CONDITIONS[c.kind]))]
    if (ill.length && !dead) lines.push(el('div', ill.join(' · '), 'peek-note'))
    if (m.thought?.line && !dead) lines.push(el('div', `「${m.thought.line}」`, 'peek-thought'))
    if (!dead) lines.push(...needBars(m.needs ?? []))
    const tip = el('div', '单击：镜头过去，打开资料', 'peek-tip')
    const index = order.indexOf(m.id)
    if (index >= 0 && index < 9 && !isTouch()) tip.append(el('kbd', String(index + 1)))
    lines.push(tip)
    peek.replaceChildren(...lines)
    peek.hidden = false
    // 挂在头像正下方，左右不出地图；小尖角对着头像中间
    const area = container.getBoundingClientRect()
    const box = tile.root.getBoundingClientRect()
    const face = tile.face.getBoundingClientRect()
    const left = Math.max(8, Math.min(box.left - area.left - 10, area.width - peek.offsetWidth - 8))
    peek.style.left = `${left}px`
    peek.style.top = `${box.bottom - area.top + 12}px`
    peek.style.setProperty('--caret', `${face.left + face.width / 2 - area.left - left}px`)
  }

  // ---------- 让位：顶部正中的提示、手机上横着滑的渐隐 ----------
  let layoutFrame = 0
  function scheduleLayout() {
    if (!layoutFrame) layoutFrame = requestAnimationFrame(layout)
  }
  /** 提示条的显隐和内容变了也要重新量：看过的提示各盯一次 */
  const watched = new WeakSet<Element>()
  const watcher = new MutationObserver(scheduleLayout)
  function layout() {
    layoutFrame = 0
    const strip = root.getBoundingClientRect()
    let clear = 0
    for (const hint of container.querySelectorAll<HTMLElement>(HINTS)) {
      if (!watched.has(hint)) {
        watched.add(hint)
        watcher.observe(hint, {
          attributes: true,
          attributeFilter: ['hidden', 'class'],
          childList: true,
        })
      }
      const r = hint.getBoundingClientRect()
      if (!strip.width || !r.width || !r.height) continue
      // 只看左右：提示让下去以后上下就不叠了，按上下判断会来回跳
      if (r.left < strip.right + 8 && r.right > strip.left - 8) clear = Math.ceil(strip.height) + 8
    }
    const value = clear ? `${clear}px` : ''
    if (container.style.getPropertyValue('--strip-clear') !== value) {
      if (value) container.style.setProperty('--strip-clear', value)
      else container.style.removeProperty('--strip-clear')
    }
    // 手机上横着滑：右边还有没露出来的头像时才淡出右沿
    root.classList.toggle(
      'more',
      root.scrollLeft + root.clientWidth < root.scrollWidth - 1 && !folded
    )
  }
  root.addEventListener('scroll', scheduleLayout, { passive: true, signal })
  const resize = new ResizeObserver(scheduleLayout)
  resize.observe(root)
  resize.observe(container)
  // 人口（入住登记、头像编号）到了：按登记重新排，头像换成像素图
  const offPopulation = onPopulation(() => {
    order = byJoinOrder([...entries.keys()], (id) => id)
    render()
  })

  return {
    roster({ residents }: RosterFrame) {
      rostered = true
      entries = new Map(residents.map((e) => [e.member.id, e]))
      order = byJoinOrder([...entries.keys()], (id) => id)
      render()
    },
    onReset() {
      entries = new Map()
      order = []
      hidePeek()
      render()
    },
    /** 选中的人变了：头像条跟着高亮 */
    select: mark,
    dispose() {
      listeners.abort()
      watcher.disconnect()
      resize.disconnect()
      offPopulation()
      cancelAnimationFrame(layoutFrame)
      container.style.removeProperty('--strip-clear')
      root.remove()
      peek.remove()
    },
  } satisfies ShellPanel & { select(): void }
}
