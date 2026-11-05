// 村民页：整页替换地图页。名册、村民库浏览与编辑、加入预览与加入、按一句话描述生成人物。
// 不暂停世界；人物只由服务器创建，页面只呈现名册和登记表。各视图在 residents/ 下，状态在 residents/state.ts。
import { $, button, el, statusLine } from './dom'
import { displayClock } from './format'
import { gameIcon, iconLabel } from './game/icons'
import { newId } from './ids'
import { observationPage } from './observationPage'
import type { JoinOutcome, JoinPreview, ModelChoice, PopulationView, ServerMsg } from './protocol'
import { handleEditorMsg, renderEditor } from './residents/editor'
import { finishJoin, renderJoin, startJoin } from './residents/join'
import { renderLibrary, renderTemplate } from './residents/library'
import { renderRoster, rosterSignature } from './residents/roster'
import {
  createResidentsState,
  type ResidentsContext,
  type ResidentsDeps,
  type ResidentsTab,
  type ResidentsView,
  type ViewHandle,
} from './residents/state'
import type { RosterFrame } from './shell/panel'

export type { ResidentsDeps } from './residents/state'

function renderView(ctx: ResidentsContext, view: ResidentsView): ViewHandle {
  switch (view.kind) {
    case 'roster':
      return renderRoster(ctx)
    case 'library':
      return renderLibrary(ctx)
    case 'template':
      return renderTemplate(ctx, view.id)
    case 'join':
      return renderJoin(ctx, view.id)
    case 'editor':
      return renderEditor(ctx, view.template, view.copyFrom, view.from)
  }
}

/** 页首的结果提示：加入成功或失败，可以关掉 */
function noticeBar(ctx: ResidentsContext) {
  const { notice } = ctx.state
  if (!notice) return null
  const bar = el('div', '', `rv-notice${notice.warning ? ' drop' : ''}`)
  bar.setAttribute('role', 'status')
  if (ctx.game)
    bar.append(
      gameIcon(notice.warning ? 'status' : 'check'),
      el('span', notice.residentId ? '已入住小镇' : notice.text)
    )
  else bar.append(el('span', notice.text))
  if (notice.residentId) bar.append(ctx.locateButton(notice.residentId))
  bar.append(
    button('×', () => {
      ctx.state.notice = null
      ctx.render()
    })
  )
  return bar
}

type Waiter = { match: (m: ServerMsg) => unknown; resolve: (v: unknown) => void }

export function initResidentsPage(deps: ResidentsDeps) {
  const game = deps.game
  const state = createResidentsState()
  // 一次请几位时逐个等预览和加入结果；消息照常交给页面，这里只旁听
  const waiters: Waiter[] = []
  function waitFor<T>(match: (m: ServerMsg) => T | undefined, ms = 15000) {
    return new Promise<T>((resolve, reject) => {
      const waiter: Waiter = { match, resolve: resolve as (v: unknown) => void }
      waiters.push(waiter)
      setTimeout(() => {
        const i = waiters.indexOf(waiter)
        if (i < 0) return
        waiters.splice(i, 1)
        reject(Error('小镇没有及时回应，请检查连接后重试'))
      }, ms)
    })
  }
  function joinModel() {
    const options = deps.modelOptions()
    const chosen = state.joinModel
    return (
      options.find((o) => o.provider === chosen?.provider && o.model === chosen.model) ??
      options[0] ??
      null
    )
  }
  async function invite(ids: string[]) {
    if (state.inviting || !ids.length) return
    state.inviting = true
    render()
    const model = joinModel()
    const joined: JoinOutcome[] = []
    const failed: string[] = []
    /** 请成了的人从勾选里去掉，没请成的留着可以再试 */
    const done = new Set<string>()
    try {
      if (!state.population) {
        deps.send({ type: 'get_population' })
        await waitFor((m) => (m.type === 'population' ? m.population : undefined))
      }
      const population = state.population as PopulationView | null
      if (!population) throw Error('还没读到小镇的居民登记')
      for (const id of ids) {
        const name = state.cards.find((c) => c.template_id === id)?.name ?? id
        try {
          deps.send({ type: 'preview_resident_join', template_id: id })
          const preview: JoinPreview = await waitFor((m) =>
            m.type === 'join_preview' && m.preview.template_id === id ? m.preview : undefined
          )
          if (!preview.ok) throw Error(preview.problems.join('；') || '现在不能加入')
          const op_id = newId()
          deps.send({
            type: 'join_resident',
            op_id,
            world_id: population.world_id,
            template_id: id,
            template_version: preview.template_version,
            name: preview.name,
            home: preview.home,
            ...(model ? { model: { provider: model.provider, model: model.model } } : {}),
          })
          const outcome: JoinOutcome = await waitFor((m) =>
            m.type === 'resident_joined' && m.outcome.op_id === op_id
              ? m.outcome
              : m.type === 'join_result' && m.op_id === op_id
                ? (m.outcome ?? undefined)
                : undefined
          )
          if (!outcome.ok) throw Error(outcome.message)
          joined.push(outcome)
          done.add(id)
        } catch (error) {
          failed.push(`${name}：${error instanceof Error ? error.message : String(error)}`)
        }
      }
    } catch (error) {
      failed.push(error instanceof Error ? error.message : String(error))
    }
    state.inviting = false
    state.picks = state.picks.filter((id) => !done.has(id))
    render()
    deps.onJoined(joined, failed, model)
  }
  const page = $('residents-page')
  const tabs = Array.from(document.querySelectorAll<HTMLButtonElement>('.rv-tab'))
  const lifecycle = observationPage(
    $('residents-view'),
    $('obs-view'),
    () => deps.send({ type: 'get_population' }),
    null,
    game
  )
  /** 当前画出的视图与当时的提示；提示变了就整页重画 */
  let current: { handle: ViewHandle; notice: ResidentsContext['state']['notice'] } | null = null
  let headNew: HTMLButtonElement | null = null
  const ctx: ResidentsContext = {
    state,
    deps,
    game,
    render,
    setTab,
    newVillager(from) {
      state.view = { kind: 'editor', from }
      state.editor = null
      render()
    },
    showTemplate(id) {
      state.view = { kind: 'template', id }
      state.editor = null
      state.detail = null
      deps.send({ type: 'get_resident_template', template_id: id })
      render()
    },
    startJoin: (id) => startJoin(ctx, id),
    invite,
    joinModel,
    requestLibrary: () => deps.send({ type: 'get_resident_library', filter: state.filter }),
    close: () => {
      lifecycle.close()
    },
    locateButton: (id) =>
      button(game ? '查看居民' : '在地图上看', () => {
        lifecycle.close()
        if (game) deps.onLocate(id)
        else deps.onFollow(id)
      }),
    setStatus(target, text, bad = false) {
      statusLine(target)(text, bad ? 'drop' : '')
    },
  }

  function open(tab: ResidentsTab = 'roster') {
    if (game) {
      deps.onOverlayOpen()
      // 名册行要显示模板一句话：打开面板即拉村民库，不等切到村民库 tab
      ctx.requestLibrary()
    }
    lifecycle.open()
    setTab(tab)
  }
  function setTab(tab: ResidentsTab) {
    state.view = { kind: tab }
    state.editor = null
    for (const t of tabs) {
      t.classList.toggle('on', t.dataset.tab === tab)
      t.setAttribute('aria-selected', String(t.dataset.tab === tab))
    }
    if (tab === 'library') ctx.requestLibrary()
    render()
  }
  for (const t of tabs)
    t.onclick = () => {
      const tab = t.dataset.tab
      setTab(tab === 'library' ? tab : 'roster')
    }
  $('residents-back').onclick = ctx.close
  if (game) iconLabel($('residents-back'), 'close', '关闭')

  /** 原型村民库：标题栏放「＋ 新建人物」primary 按钮（仅库 tab 显示） */
  function syncHeaderNew() {
    if (!game) return
    if (!headNew) {
      headNew = button(
        '＋ 新建人物',
        () => {
          state.view = { kind: 'editor' }
          render()
        },
        'primary residents-head-new'
      )
      $('residents-tabs').after(headNew)
    }
    headNew.hidden = state.view.kind !== 'library'
  }
  function render() {
    syncHeaderNew()
    const handle = renderView(ctx, state.view)
    current = { handle, notice: state.notice }
    page.replaceChildren(handle.root)
    const bar = noticeBar(ctx)
    if (bar) page.prepend(bar)
  }
  /** 数据更新：视图能只重画列表就不整页重画，正在输入的搜索框保留 */
  function refresh(...kinds: ResidentsView['kind'][]) {
    if (!lifecycle.isOpen() || !kinds.includes(state.view.kind)) return
    if (current?.handle.update && current.notice === state.notice) current.handle.update()
    else render()
  }

  return {
    open,
    /** 直接打开新建村民；返回、取消回到村中居民 */
    create() {
      open('roster')
      ctx.newVillager('roster')
    },
    close: ctx.close,
    isOpen: lifecycle.isOpen,
    roster({ residents, msg }: RosterFrame) {
      state.roster = residents
      $('residents-clock').textContent = displayClock(msg.clock)
      if (!lifecycle.isOpen() || state.view.kind !== 'roster') return
      const signature = rosterSignature(ctx)
      if (signature === state.rosterSignature) return
      state.rosterSignature = signature
      refresh('roster')
    },
    /** 重连：重新拉名册，并按操作编号查询上次未收到结果的加入 */
    connected() {
      deps.send({ type: 'get_population' })
      if (state.pending && state.population)
        deps.send({
          type: 'get_resident_join_result',
          world_id: state.population.world_id,
          op_id: state.pending.op_id,
        })
    },
    onReset() {
      state.pending = null
      state.preview = null
      state.notice = null
      deps.send({ type: 'get_population' })
    },
    /** 一次请几位入住（空镇卡片的「请他们三位住进来」也走这里） */
    invite,
    requestLibrary: ctx.requestLibrary,
    /** 新村民用的模型；空镇卡片上换了也记在这里 */
    joinModel,
    setJoinModel(choice: ModelChoice) {
      state.joinModel = { provider: choice.provider, model: choice.model }
    },
    handleMsg(msg: ServerMsg) {
      for (const waiter of [...waiters]) {
        const value = waiter.match(msg)
        if (value === undefined) continue
        waiters.splice(waiters.indexOf(waiter), 1)
        waiter.resolve(value)
      }
      return handleResidentsMsg(ctx, msg, refresh)
    },
  }
}

/** 村民页收到的服务端消息；返回是否已处理 */
function handleResidentsMsg(
  ctx: ResidentsContext,
  msg: ServerMsg,
  refresh: (...kinds: ResidentsView['kind'][]) => void
): boolean {
  const { state, deps } = ctx
  switch (msg.type) {
    case 'population': {
      state.population = msg.population
      refresh('roster', 'library')
      return true
    }
    case 'resident_library':
      state.cards = msg.templates
      state.customRoot = msg.custom_root
      refresh('library', 'roster')
      deps.onLibrary(msg.templates)
      return true
    case 'resident_template':
      if (
        (state.view.kind === 'template' || state.view.kind === 'join') &&
        msg.template?.template_id !== state.view.id &&
        !msg.error
      )
        return true
      state.detail = { template: msg.template, persona: msg.persona, error: msg.error }
      refresh('template', 'join')
      return true
    case 'join_preview':
      if (state.view.kind === 'join' && msg.preview.template_id === state.view.id) {
        state.preview = msg.preview
        ctx.render()
      }
      return true
    case 'resident_joined':
      finishJoin(ctx, msg.outcome)
      ctx.requestLibrary()
      return true
    case 'error':
      // 加入命令失败：结束等待并写明原因。
      if (msg.request_id !== undefined && state.pending?.op_id === msg.request_id) {
        state.pending = null
        state.notice = { text: `未加入：${msg.message}`, warning: true }
        ctx.render()
        return true
      }
      return handleEditorMsg(ctx, msg)
    case 'join_result':
      if (msg.outcome) finishJoin(ctx, msg.outcome)
      else if (state.pending?.op_id === msg.op_id) {
        // 服务器从未提交这次操作：可以放心重新点选，不会产生第二个人
        state.pending = null
        state.notice = { text: '上次加入没有提交到服务器，请重新确认', warning: true }
        ctx.render()
      }
      return true
    default:
      return handleEditorMsg(ctx, msg)
  }
}
