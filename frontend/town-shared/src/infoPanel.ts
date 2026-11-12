// 选中村民：地图上点人，脚下冒出一排动作钮（info/focus.ts）；点「资料」打开右栏的角色卡。
// 角色卡分页签（info/tabs.ts）：「近况」是像素小人和想法、住处、正在做的事、身体状态、口袋，原因和记录收在
// 「更多细节」里；「人设」「长相」「模型」就地改这位村民。
// 卡片上的东西都从每拍的名册来，只有「更多细节 → 目标与记忆」例外：那一截有好几 KB，名册里不带，
// 展开它时才告诉世界在看谁（watch_resident），世界单独发来、变了再发（resident_detail）。
// 跨级反馈：记录每项需求的上一个 band，变化时状态条一次性强调 + 追加本地事件。

import {
  type NeedsTuning,
  type PhysiologySwitches,
  type PopulationView,
  type ResidentRegistration,
  type RosterMember,
  type ServerMsg,
} from './protocol'
import { agentStopped } from './display'
import type { WaitLine } from './modelWait'
import type { GameMap, ResidentEntry } from './gameMap'
import type { RosterFrame } from './shell/panel'
import type { EventsHandle } from './events'
import { $, query } from './dom'
import { displayClock, playerText } from './format'
import { byJoinOrder, portraitKey } from './portraits'
import { agentStateLabels } from './labels'
import { lineLabel } from './game/icons'
import type { MiracleKind } from './avatar/types'
import { miracleOptions } from './miracles'

interface InfoPanelDeps {
  map: GameMap
  events: EventsHandle
  localeName: (id: string) => string
  onPossess: (id: string) => void
  /** 页签里改人设、长相、模型要用的：发消息、保存、跳到设定（info/tabs.ts） */
  editor: CardEditorDeps
  onOpenDiary: () => void
  onOpenMemory: () => void
  onSelectResident: (id: string) => void
  /** 告诉世界在看谁的「目标与记忆」，世界把那一位的细节发来、变了再发；null 是不看了 */
  onWatchDetail: (id: string | null) => void
  /** 重演录像：没有世界可问，「目标与记忆」那一截写明不显示 */
  replay: boolean
  /** 选中的村民换了人（右栏里的聊天记录页要退回角色卡） */
  onSelectionChange: () => void
  /** 选中谁定下来了（含取消选中）：头像条跟着高亮 */
  onSelected: () => void
  /** 化身控制中：右栏收起、不选中村民 */
  avatarActive: () => boolean
  /** 这个世界开放了化身控制 */
  avatarAvailable: () => boolean
  onOpenItem: (id: string) => void
  /** 清掉居民的暂停原因让他们接着行动：世界在运行时按原速度再选一次 */
  onResumeAgents: () => void
  /** 在等模型时卡片顶上写什么、按钮做什么（modelWait.ts） */
  waitLine: (m: RosterMember) => WaitLine | null
  /** 「说话」：进入化身、走过去搭话 */
  onTalk: (id: string) => void
  /** 化身神力的入口该不该出现：世界开着神力、能用化身、没在附身 */
  miracleReady: () => boolean
  /** 「复活」「治愈」「补满」：进入化身、走过去施展 */
  onMiracle: (id: string, kind: MiracleKind) => void
  /** 「调整」：世界暂停时直接改村民的身体数值 */
  onAdjustBody: (
    id: string,
    values: BodyValues,
    done: (ok: boolean, message: string) => void
  ) => void
}

import { installPanelWidth } from './info/width'
import { createBodyView } from './info/body'
import { createBodyAdjust, type BodyValues } from './info/bodyAdjust'
import { createFocus } from './info/focus'
import { createInventoryView } from './info/inventory'
import { createNeedsView, needWord, worstNeed } from './info/needs'
import { createThoughtView } from './info/thought'
import { createPlanView } from './info/plan'
import { createAgentView } from './info/agent'
import { createStage } from './info/stage'
import { createCardTabs, type CardEditorDeps, type CardTab } from './info/tabs'
import './info/card.css'

export function initInfoPanel(deps: InfoPanelDeps) {
  const panel = $('info-panel')
  // 角色卡用深色那套颜色，像游戏里的状态窗；聊天记录页也在这一栏里，跟着一起
  panel.dataset.tier = 'night'
  const resizer = $('info-resizer')
  const obsMain = $('obs-main')
  const followBtn = $('info-follow')
  const talkBtn = query<HTMLButtonElement>(panel, '#info-talk')
  const possessBtn = query<HTMLButtonElement>(panel, '#info-possess')
  const reviveBtn = query<HTMLButtonElement>(panel, '#info-revive')
  // 「状态」标题右边的治愈、补满：看着数值直接点
  const miracleBox = $('info-miracles')
  const miracleBtns = [...miracleBox.querySelectorAll<HTMLButtonElement>('button')]
  // 「状态」标题最右边的「调整」：暂停时直接拨身体数值
  const adjustBtn = query<HTMLButtonElement>(panel, '#info-adjust')
  lineLabel(reviveBtn, 'spark', '复活')
  lineLabel(talkBtn, 'chat', '说话')
  lineLabel(followBtn, 'eye', '跟随')
  lineLabel(possessBtn, 'person', '附身')
  lineLabel($('info-memory'), 'memory', '回忆')
  lineLabel($('info-diary'), 'clock', '经历')
  lineLabel($('info-chat'), 'chat', '聊过的')
  lineLabel($('info-collapse'), 'close', '收起')
  possessBtn.onclick = () => {
    if (selectedId) deps.onPossess(selectedId)
  }
  possessBtn.hidden = !deps.map.avatarSupported
  talkBtn.onclick = () => {
    if (selectedId) deps.onTalk(selectedId)
  }

  /** 换人的顺序（按入住登记，和头像条一样），手机抽屉左右滑动按它换人 */
  let order: string[] = []

  let selectedId: string | null = null
  /** 已经替玩家选过第一位：之后点空地取消选中，下一份名册不再自动选回来 */
  let picked = false
  let physiology: PhysiologySwitches | undefined
  let following = false
  let registrations = new Map<string, ResidentRegistration>()
  /** 选中的人最近一份名册：地图上的动作钮按它决定能不能说话、附身 */
  let current: RosterMember | undefined
  const panelWidth = installPanelWidth(panel, resizer, obsMain)
  const tabs = createCardTabs(panel, deps.editor, {
    setWide: panelWidth.setWide,
    reveal() {
      const pos = selectedId ? deps.map.getMemberPos(selectedId) : undefined
      if (pos) deps.map.panTo(pos[0], pos[1])
    },
  })
  const inventory = createInventoryView($('info-inventory'), deps.onOpenItem)
  const body = createBodyView($('info-physiology'), query<HTMLElement>(panel, '.info-body-folds'))
  const needs = createNeedsView($('info-needs'), '', (text, warning) =>
    deps.events.pushLocal(text, warning)
  )
  const thought = createThoughtView($('info-thought'))
  const adjust = createBodyAdjust($('info-adjust-body'), {
    apply: (values, done) => {
      const id = selectedId
      if (!id) return done(false, '没有选中村民')
      // 成功时世界日志会广播「观察者调整了……」，这里不再另记一条
      deps.onAdjustBody(id, values, (ok, message) => {
        done(ok, message)
        syncAdjust()
      })
    },
  })
  const plan = createPlanView($('info-plan'))
  const agent = createAgentView($('info-agent'), deps.replay)
  const stage = createStage(query<HTMLCanvasElement>(panel, '.card-sprite'))
  const focus = createFocus(deps.map, $('map'), {
    talk: () => {
      if (selectedId) deps.onTalk(selectedId)
    },
    follow: () => setFollowing(!following),
    possess: () => {
      if (selectedId) deps.onPossess(selectedId)
    },
    card: () => (panel.hidden ? setCollapsed(false) : collapse()),
    miracle: (kind) => {
      if (selectedId) deps.onMiracle(selectedId, kind)
    },
  })
  reviveBtn.onclick = () => {
    if (selectedId) deps.onMiracle(selectedId, 'revive')
  }
  for (const b of miracleBtns)
    b.onclick = () => {
      if (selectedId) deps.onMiracle(selectedId, b.dataset.miracle as MiracleKind)
    }
  adjustBtn.onclick = () => {
    if (adjust.isOpen()) adjust.close()
    else if (current) adjust.open(current.needs ?? [])
    syncAdjust()
  }
  /** 世界的速度：「调整」只在暂停时能用 */
  let worldSpeed = 0
  /** 「调整」钮：活着的村民才有；世界在跑时灰着 */
  function syncAdjust() {
    const m = current
    const alive = !!m && m.kind === 'resident' && m.body?.life !== 'dead' && !!m.needs?.length
    adjustBtn.hidden = !alive
    if (!alive && adjust.isOpen()) adjust.close()
    adjustBtn.disabled = worldSpeed > 0 && !adjust.isOpen()
    adjustBtn.title =
      worldSpeed > 0 ? '先暂停世界，再调身体数值' : `直接调${m?.name ?? ''}的饱腹、精力、水分和健康`
    adjustBtn.setAttribute('aria-expanded', String(adjust.isOpen()))
    adjust.setPaused(worldSpeed === 0)
  }

  function setCollapsed(collapsed: boolean) {
    panel.hidden = collapsed
    resizer.hidden = collapsed
    panel.classList.toggle('collapsed', collapsed)
    if (collapsed) tabs.collapsed()
    syncFocus()
    syncWatch()
  }

  // 「更多细节」和里面的「目标与记忆」：两层都展开、卡片开着，才要选中那位的细节
  const folds = [
    query<HTMLDetailsElement>(panel, '.card-more'),
    query<HTMLDetailsElement>(panel, '#info-agent-fold'),
  ]
  /** 连着世界：没连着时不发，连上再说 */
  let online = false
  /** 已经告诉世界在看谁；断线后世界不记得，连上要再说一遍 */
  let watching: string | null = null
  function syncWatch() {
    const wanted = selectedId && !panel.hidden && folds.every((f) => f.open) ? selectedId : null
    if (!online || wanted === watching) return
    watching = wanted
    deps.onWatchDetail(wanted)
  }
  for (const fold of folds) fold.addEventListener('toggle', syncWatch)
  /** 收起角色卡，保留选中：地图上的动作钮还在 */
  function collapse() {
    setCollapsed(true)
  }

  /** 能不能和他说话：化身开放、对方能回应、没被人附身 */
  function canTalk(m: RosterMember) {
    return (
      !!deps.map.avatarSupported &&
      deps.avatarAvailable() &&
      m.kind === 'resident' &&
      !!m.body?.can_decide &&
      m.resident_agent?.state !== 'manual'
    )
  }
  function canPossess(m: RosterMember) {
    return (
      !!deps.map.avatarSupported &&
      deps.avatarAvailable() &&
      !!m.body?.can_decide &&
      !!m.body?.can_move
    )
  }

  /** 化身神力的选项：开着神力、能用化身时才有 */
  function miraclesFor(m: RosterMember | undefined) {
    return m?.kind === 'resident' && deps.miracleReady() ? miracleOptions(m) : null
  }

  /** 地图上的动作钮跟着名册和右栏开合更新 */
  function syncFocus() {
    const m = current
    const alert = m?.kind === 'resident' ? worstNeed(m.needs ?? []) : undefined
    focus.sync({
      canTalk: !!m && canTalk(m),
      canPossess: !!m && canPossess(m),
      following,
      cardOpen: !panel.hidden,
      alert: alert ? { kind: alert.kind, text: `${m?.name}${needWord(alert)}` } : null,
      miracles: miraclesFor(m),
    })
  }

  /** 角色卡上的神力：死者的「复活」大钮，活人「状态」右边的治愈、补满 */
  function renderMiracles(m: RosterMember) {
    const options = miraclesFor(m)
    const dead = m.body?.life === 'dead'
    reviveBtn.hidden = !options || !dead
    reviveBtn.title = `你的化身会走过去，让${m.name}活过来`
    miracleBox.hidden = !options || dead
    for (const b of miracleBtns) {
      const o = options?.find((x) => x.kind === b.dataset.miracle)
      b.disabled = !o?.enabled
      b.title = o ? `${o.note}；你的化身会走过去` : ''
    }
  }

  /** 选中谁：地图描出来、脚下冒动作钮；不自动打开角色卡，卡片开着时跟着换人 */
  function select(id: string | null) {
    if (selectedId !== id) {
      deps.onSelectionChange()
      needs.clear()
      body.clear()
      inventory.clear()
      plan.clear()
      thought.clear()
      agent.clear()
      stage.clear()
      adjust.close()
      current = undefined
    }
    selectedId = id
    tabs.setResident(id)
    if (id) deps.onSelectResident(id)
    deps.map.setSelected(id)
    focus.show(id)
    possessBtn.disabled = !id
    if (following) watchSelected()
    if (!id) {
      if (following) setFollowing(false)
      setCollapsed(true)
      $('info-name').textContent = '未选中村民'
      $('info-place').textContent = '点击地图上的村民查看信息'
      $('info-activity').textContent = ''
      $('info-transit').textContent = ''
      $('info-home').textContent = ''
    }
    syncFocus()
    syncWatch()
    deps.onSelected()
  }

  function renderHome() {
    const r = selectedId ? registrations.get(selectedId) : undefined
    $('info-home').textContent = r
      ? `${r.home ? `住在${r.home_name}` : '还没有家'} · ${r.joined_clock ? `${displayClock(r.joined_clock)} 入村` : '原有居民'}`
      : ''
  }

  /** Agent 停下了或者在等模型：卡片顶上写明原因。按钮只放能马上处理、又只关乎村民的事；
   *  世界暂停时不放「继续行动」——开始运行是开始钮和地图提示的事，不在一个人的卡片上 */
  function renderStop(m: RosterMember, speed: number) {
    const box = $('info-stop')
    const agent = m.resident_agent
    const wait = deps.waitLine(m)
    box.hidden = !agent || (!wait && !agentStopped(m))
    if (box.hidden || !agent) return
    const reason = agent.reason ? playerText(agent.reason) : agentStateLabels[agent.state]
    // 在等的东西没有可点的（比如内置模型正在下载）时不放按钮
    const action = wait
      ? wait.label
        ? { label: wait.label, run: wait.run }
        : null
      : agent.state === 'budget' || agent.state === 'unconfigured' || speed === 0
        ? null
        : { label: '继续行动', run: deps.onResumeAgents }
    query<HTMLElement>(box, 'span').textContent = wait ? wait.text : `${m.name}停下了：${reason}`
    const button = query<HTMLButtonElement>(box, 'button')
    button.hidden = !action
    if (action) {
      button.textContent = action.label
      button.onclick = action.run
    }
  }

  function setFollowing(on: boolean) {
    following = on
    followBtn.classList.toggle('on', following)
    followBtn.setAttribute('aria-pressed', String(following))
    lineLabel(followBtn, 'eye', following ? '跟随中' : '跟随')
    watchSelected()
    if (on && selectedId && !deps.map.watch) {
      const pos = deps.map.getMemberPos(selectedId)
      if (pos) deps.map.panTo(pos[0], pos[1])
    }
    syncFocus()
  }
  /** 地图能逐帧跟时，镜头锁住选中的人（换了人跟着换）；玩家拖开地图就不再跟随 */
  function watchSelected() {
    deps.map.watch?.(following ? selectedId : null, () => setFollowing(false))
  }
  followBtn.onclick = () => setFollowing(!following)
  $('info-diary').onclick = () => deps.onOpenDiary()
  $('info-memory').onclick = () => deps.onOpenMemory()
  $('info-collapse').onclick = collapse

  /** roster 驱动：信息刷新 + 跨级检测 + 跟随 */
  function render(entries: ResidentEntry[], minutes: number, speed: number) {
    order = byJoinOrder(
      entries.map((e) => e.member.id),
      (id) => id
    )
    if (!entries.length && !selectedId) {
      $('info-name').textContent = '还没有村民'
      $('info-place').textContent = '点地图左上角的「邀请」请几位住进来'
    }
    const me = selectedId ? entries.find((e) => e.member.id === selectedId) : undefined
    if (!me) return
    const m = me.member
    current = m
    possessBtn.hidden = !deps.map.avatarSupported
    possessBtn.disabled = !canPossess(m)
    possessBtn.title = possessBtn.disabled
      ? !deps.avatarAvailable()
        ? '当前世界尚未开放角色控制'
        : (m.body?.limitation ?? '村民状态尚未就绪')
      : '直接接管这名村民；AI 暂停决策'
    talkBtn.hidden = !canTalk(m)
    talkBtn.title = `你的化身会走过去，${m.name}会停下来等你`
    renderMiracles(m)
    worldSpeed = speed
    syncAdjust()

    needs.setResidentName(m.name)
    $('info-name').textContent = m.name
    const at = m.at
    $('info-place').textContent = deps.localeName(me.locale)
    $('info-activity').textContent = m.chat
      ? `正在交谈 · ${m.chat.participants.join('、')}`
      : m.verb
    renderStop(m, speed)
    // 只在路上时多写一行进度
    $('info-transit').textContent =
      at.kind === 'transit'
        ? `在路上，去${deps.localeName(at.toward)}（还要约 ${Math.max(1, Math.round(at.total - at.elapsed))} 分钟）`
        : ''
    $('info-transit').hidden = at.kind !== 'transit'
    renderHome()
    const r = registrations.get(m.id)
    stage.set(r ? portraitKey(r) : m.id, at.kind === 'transit')
    if (m.kind === 'resident') needs.render(m.needs ?? [])
    body.render(m.body, physiology)
    inventory.render(m.inventory)
    thought.render(m.thought, minutes)
    agent.render(m.resident_agent)
    plan.render(m.plan, m.body, m.resident_agent, minutes)
    syncFocus()
    // 地图不会逐帧跟时：每次 roster 更新，村民在视野外（带边距）才平移
    if (following && !deps.map.watch) {
      const pos = deps.map.getMemberPos(m.id)
      if (pos) deps.map.panTo(pos[0], pos[1])
    }
  }

  return {
    select,
    /** 选中并打开角色卡；给了页签就翻到那一页（村民页的「档案」开到人设） */
    open(id: string, tab?: CardTab) {
      select(id)
      setCollapsed(false)
      if (tab) tabs.show(tab)
    },
    /** 页签里还没保存的修改，离开小镇前问一句 */
    unsaved: () => tabs.unsaved(),
    dispose() {
      panelWidth.dispose()
      focus.show(null)
    },
    follow: setFollowing,
    setCollapsed,
    collapse,
    /** 打开选中村民的日记（快捷栏「日记」与 2 键） */
    openDiary: () => deps.onOpenDiary(),
    isCollapsed: () => panel.hidden,
    /** 按名册顺序换到上一位或下一位 */
    cycle(step: 1 | -1) {
      if (order.length < 2) return
      const i = Math.max(0, order.indexOf(selectedId ?? ''))
      select(order[(i + step + order.length) % order.length])
    },
    selected: () => selectedId,
    /** 世界重置：清掉本地缓存与选中，下一帧 roster 全量重画（跟随保留） */
    onReset() {
      inventory.clear()
      needs.reset()
      plan.reset()
      thought.reset()
      agent.reset()
      select(null)
      picked = false
    },
    /** 世界生理开关：下一帧名册按它补画关掉的项 */
    onPhysiology(value: PhysiologySwitches) {
      physiology = value
      needs.setSwitches(value)
    },
    /** agent_config 到达后补上分界线的说明 */
    onTuning(t: NeedsTuning, healthMarks: number[]) {
      needs.tune(t, healthMarks)
      adjust.tune(t, healthMarks)
    },
    /** 人口登记：住宅与入村时间来自这里，不从 roster 猜；离开小镇的人，页签里他的几页一起删掉 */
    onPopulation(view: PopulationView) {
      registrations = new Map(view.residents.map((r) => [r.id, r]))
      tabs.keep(new Set(registrations.keys()))
      renderHome()
    },
    /** 「目标与记忆」的细节自己收下（换人以后才到的上一位的不画）；人设原文、模型配置等交给页签里的
     *  各页，不认领，后面的面板照常收到 */
    handleMsg(msg: ServerMsg) {
      if (msg.type === 'resident_detail') {
        if (msg.resident_id === watching) agent.detail(msg.detail ?? null)
        return true
      }
      tabs.handleMsg(msg)
    },
    connected() {
      online = true
      syncWatch()
    },
    disconnected() {
      online = false
      watching = null
    },
    /** 名册：先定选中谁，再刷新信息、跨级检测与跟随 */
    roster({ residents, msg }: RosterFrame) {
      // 第一份名册选中第一位：镜头对准他，脚下的动作钮告诉玩家能做什么；角色卡等玩家点「资料」再开
      if (deps.avatarActive()) {
        setCollapsed(true)
        if (selectedId !== null) select(null)
      } else if (selectedId === null && residents.length && !picked) select(residents[0].member.id)
      else if (selectedId !== null && !residents.some((e) => e.member.id === selectedId))
        select(null)
      if (residents.length) picked = true
      render(residents, msg.sim_minutes, msg.speed)
      // 模型页认其他村民（「套用到其他还没选的村民」）要看名册
      tabs.handleMsg(msg)
    },
  }
}
