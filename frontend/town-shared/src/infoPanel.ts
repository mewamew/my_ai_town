// 选中村民：地图上点人，脚下冒出一排动作钮（info/focus.ts）；点「资料」打开右栏的角色卡。
// 角色卡只读：像素小人和想法、住处、正在做的事、身体状态、口袋，原因和记录收在「更多细节」里。
// 跨级反馈：记录每项需求的上一个 band，变化时状态条一次性强调 + 追加本地事件。

import {
  type NeedsTuning,
  type PhysiologySwitches,
  type PopulationView,
  type ResidentRegistration,
  type RosterMember,
} from './protocol'
import { agentStopped } from './display'
import type { WaitLine } from './modelWait'
import type { GameMap, ResidentEntry } from './gameMap'
import type { RosterFrame } from './shell/panel'
import type { EventsHandle } from './events'
import { $, query } from './dom'
import { displayClock, playerText } from './format'
import { portraitKey } from './portraits'
import { agentStateLabels } from './labels'
import { lineLabel } from './game/icons'

interface InfoPanelDeps {
  map: GameMap
  events: EventsHandle
  localeName: (id: string) => string
  onPossess: (id: string) => void
  onEditResident: () => void
  onOpenDiary: () => void
  onOpenMemory: () => void
  onSelectResident: (id: string) => void
  /** 选中的村民换了人（右栏里的聊天记录页要退回角色卡） */
  onSelectionChange: () => void
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
}

import { installPanelWidth } from './info/width'
import { createBodyView } from './info/body'
import { createFocus } from './info/focus'
import { createInventoryView } from './info/inventory'
import { createNeedsView, needWord, worstNeed } from './info/needs'
import { createThoughtView } from './info/thought'
import { createPlanView } from './info/plan'
import { createAgentView } from './info/agent'
import { createStage } from './info/stage'
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
  lineLabel(talkBtn, 'chat', '说话')
  lineLabel(followBtn, 'eye', '跟随')
  lineLabel(possessBtn, 'person', '附身')
  lineLabel($('info-memory'), 'memory', '回忆')
  lineLabel($('info-diary'), 'clock', '经历')
  lineLabel($('info-chat'), 'chat', '聊过的')
  lineLabel($('info-edit'), 'pen', '设定')
  lineLabel($('info-collapse'), 'close', '收起')
  possessBtn.onclick = () => {
    if (selectedId) deps.onPossess(selectedId)
  }
  possessBtn.hidden = !deps.map.avatarSupported
  talkBtn.onclick = () => {
    if (selectedId) deps.onTalk(selectedId)
  }

  const residentSelect = query<HTMLSelectElement>(panel, '#resident-select')
  let residentChoices = ''
  /** 名册顺序，手机抽屉左右滑动按它换人 */
  let order: string[] = []
  residentSelect.onchange = () => select(residentSelect.value)

  let selectedId: string | null = null
  /** 已经替玩家选过第一位：之后点空地取消选中，下一份名册不再自动选回来 */
  let picked = false
  let physiology: PhysiologySwitches | undefined
  let following = false
  let registrations = new Map<string, ResidentRegistration>()
  /** 选中的人最近一份名册：地图上的动作钮按它决定能不能说话、附身 */
  let current: RosterMember | undefined
  const panelWidth = installPanelWidth(panel, resizer, obsMain)
  const inventory = createInventoryView($('info-inventory'), deps.onOpenItem)
  const body = createBodyView($('info-physiology'), query<HTMLElement>(panel, '.info-body-folds'))
  const needs = createNeedsView($('info-needs'), '', (text, warning) =>
    deps.events.pushLocal(text, warning)
  )
  const thought = createThoughtView($('info-thought'))
  const plan = createPlanView($('info-plan'))
  const agent = createAgentView($('info-agent'))
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
  })

  function setCollapsed(collapsed: boolean) {
    panel.hidden = collapsed
    resizer.hidden = collapsed
    panel.classList.toggle('collapsed', collapsed)
    syncFocus()
  }
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
    })
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
      current = undefined
    }
    selectedId = id
    residentSelect.value = id ?? ''
    if (id) deps.onSelectResident(id)
    deps.map.setSelected(id)
    focus.show(id)
    possessBtn.disabled = !id
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
  }

  function renderHome() {
    const r = selectedId ? registrations.get(selectedId) : undefined
    $('info-home').textContent = r
      ? `${r.home ? `住在${r.home_name}` : '还没有家'} · ${r.joined_clock ? `${displayClock(r.joined_clock)} 入村` : '原有居民'}`
      : ''
  }

  /** Agent 停下了或者在等模型：卡片顶上写明原因。按钮只放能马上处理、又只关乎村民的事；
   *  世界暂停时不放「继续行动」——开始运行是顶栏和地图提示的事，不在一个人的卡片上 */
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
    if (on && selectedId) {
      const pos = deps.map.getMemberPos(selectedId)
      if (pos) deps.map.panTo(pos[0], pos[1])
    }
    syncFocus()
  }
  followBtn.onclick = () => setFollowing(!following)
  $('info-edit').onclick = () => deps.onEditResident()
  $('info-diary').onclick = () => deps.onOpenDiary()
  $('info-memory').onclick = () => deps.onOpenMemory()
  $('info-collapse').onclick = collapse

  /** roster 驱动：信息刷新 + 跨级检测 + 跟随 */
  function render(entries: ResidentEntry[], minutes: number, speed: number) {
    const choices = entries.map((e) => ({ id: e.member.id, name: e.member.name }))
    order = choices.map((c) => c.id)
    const choiceKey = JSON.stringify(choices)
    if (residentChoices !== choiceKey) {
      residentChoices = choiceKey
      residentSelect.replaceChildren(...choices.map((choice) => new Option(choice.name, choice.id)))
      residentSelect.hidden = choices.length < 2
      residentSelect.value = selectedId ?? ''
    }
    if (!entries.length && !selectedId) {
      $('info-name').textContent = '还没有村民'
      $('info-place').textContent = '点顶栏的「邀请村民」请几位住进来'
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

    needs.setResidentName(m.name)
    $('info-edit').title = `编辑${m.name}的设定`
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
    plan.render(m.plan, m.body)
    syncFocus()
    // 跟随：每次 roster 更新，村民在视野外（带边距）才平移
    if (following) {
      const pos = deps.map.getMemberPos(m.id)
      if (pos) deps.map.panTo(pos[0], pos[1])
    }
  }

  return {
    select,
    /** 选中并打开角色卡 */
    open(id: string) {
      select(id)
      setCollapsed(false)
    },
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
    },
    /** 人口登记：住宅与入村时间来自这里，不从 roster 猜 */
    onPopulation(view: PopulationView) {
      registrations = new Map(view.residents.map((r) => [r.id, r]))
      renderHome()
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
    },
  }
}
