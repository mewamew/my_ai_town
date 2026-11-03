// 化身界面：底部居中的入口与操作条、居中的进入对话框、右侧面板、地图上的提示标签。
// 一个控制器对应一条连接；刷新只恢复租约，不重发动作或行走。
// 节点与事件绑定在 ui.ts，面板内容在 panels.ts，行走在 navigation.ts，命令回执在 commands.ts。
import { createAvatarCommands } from './commands'
import { createInvitations } from './invitations'
import { resumeLease } from './lease'
import { createAvatarNavigation } from './navigation'
import { createAvatarUI, escapeKey, guardPointer, type AvatarUI } from './ui'
import { createAvatarPanels, panelSignature, type AvatarPanelState } from './panels'
import { avatarTargets } from './targets'
import { bulletinSpots, createBulletinComposer, type BulletinBoard } from './bulletin'
import type { PropCatalog } from '../props/types'
import { createAvatarTouch } from './touch'
import { isTouch } from '../platform'
import type { AvatarActions, AvatarTab } from './ui-types'
import type { GameMap } from '../gameMap'
import type { ClientMsg, RosterMember, ServerMsg, WorldHold } from '../protocol'
import type { AvatarCommand, AvatarState, MiracleKind } from './types'
import { miracleOptions } from '../miracles'
import { playMiracle } from './miracleFx'
import type { GameAudio } from '../audio/controller'
import { $, el } from '../dom'
import type { HoldFix } from '../holds'
import { keycap, runningTalk } from './view'
import './style.css'

export interface AvatarDeps {
  send: (message: ClientMsg) => void
  map: GameMap
  openHistory: (id: string) => void
  localeName: (id: string) => string
  /** 地图上的已知地点：约时间时选见面的地方 */
  places: { id: string; name: string }[]
  /** 「继续世界」恢复到的运行速度 */
  resumeSpeed: number
  sounds?: Pick<GameAudio, 'updateMovement' | 'playDescend'>
  /** 游戏界面 */
  game: boolean
  /** 游戏界面打开化身面板时收起右栏的居民卡 */
  collapseInfo: () => void
  /** 面板里「查看消耗」「设定」等链接 */
  openUsage: () => void
  openSettings: () => void
  /** 全镇暂停时操作条上的修复按钮，和地图上的提示卡同一个动作 */
  fixHold: (fix: HoldFix, provider: string) => void
}

/** 脚步声跟着化身走动：控制中且在走时响，地面随位置变化 */
function movementSound(
  sounds: AvatarDeps['sounds'],
  getState: () => AvatarState | null,
  owned: () => boolean
) {
  const update = (active: boolean) => {
    const actor = getState()?.actor
    const at = actor?.locus.at
    sounds?.updateMovement({
      moving: active && owned(),
      locale: actor?.locus.locale ?? '',
      space: at?.kind === 'free' ? at.space : undefined,
      atKind: at?.kind,
    })
  }
  return { update }
}

const mapVisible = () => !document.getElementById('obs-view')?.hidden
/** 焦点在输入框里或开着对话框：按键是在打字 */
const typing = () => {
  const e = document.activeElement
  return (
    !!document.querySelector('dialog[open]') ||
    (e instanceof HTMLElement &&
      (e.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(e.tagName)))
  )
}
/** 刚进入化身时镜头拉近到的宽度（地图单位）：看得清自己和身边几步内的人 */
const CLOSE_UP_WIDTH = 1400
/** 镜头对准人头上方一点，名字和提示标签不贴着画面上沿 */
const CAMERA_RISE = 30
/** 一帧里人挪了这么远（地图单位）算瞬移（进门、出门），镜头直接切过去 */
const CAMERA_JUMP = 400

export function createAvatar(deps: AvatarDeps) {
  const avatar = new AvatarController(deps)
  const { ui } = avatar
  return {
    /** 离开地图画面前交还控制；交还失败时返回 false，调用方留在原处 */
    release: () => avatar.release(),
    /** 隐藏地图前清掉移动输入 */
    stopMoving: () => avatar.stopMoving(),
    /** 打开进入小镇的对话框 */
    openEntry: () => avatar.openDialog(),
    /** 关掉进入小镇的对话框；原来开着就返回 true（返回键） */
    closeEntry: () => avatar.closeEntry(),
    onEntryChange: ui.entry.onAvailable,
    panelOpen: () => !ui.panel.hidden,
    /** 这个世界开放了化身控制 */
    available: () => !ui.root.hidden,
    /** 关掉侧面板；原来开着就返回 true */
    closePanel: () => avatar.closePanel(),
    /** 菜单等覆盖层打开或关闭时停止移动输入 */
    overlay: (open: boolean) => avatar.overlay(open),
    possess: (resident: string) => avatar.possess(resident),
    handleMsg: (message: ServerMsg) => avatar.handleMsg(message),
    connected: () => avatar.connected(),
    disconnected: () => avatar.disconnected(),
    /** 地图上点了村民或道具：控制中就走过去并互动，否则交给观察界面 */
    select: (kind: 'chat' | 'bag', id?: string) => avatar.select(kind, id),
    /** 右栏「和 X 说话」：进入化身（来过的直接回到上次的位置），走过去搭话 */
    talkTo: (resident: string) => avatar.talkTo(resident),
    /** 神力的入口（地图上的钮、角色卡、死亡卡）该不该出现 */
    miracleReady: () => avatar.miracleReady(),
    /** 对某人施展神力：进入化身、走过去，到了就施展 */
    miracle: (resident: string, kind: MiracleKind) => avatar.miracle(resident, kind),
    /** 几个人里离化身最近的一个（死亡卡上的「去复活」先去最近的） */
    nearest: (ids: string[]) => avatar.nearest(ids),
    onReset: () => avatar.reset(),
    active: () => avatar.owned(),
    dispose: () => avatar.dispose(),
  }
}

class AvatarController {
  readonly ui: AvatarUI
  private readonly deps: AvatarDeps
  private readonly map: GameMap
  private readonly listeners = new AbortController()
  private readonly invitations = createInvitations()
  private readonly lease: ReturnType<typeof resumeLease>
  private readonly footsteps: ReturnType<typeof movementSound>
  private readonly navigation: ReturnType<typeof createAvatarNavigation>
  private readonly commands: ReturnType<typeof createAvatarCommands>
  private readonly panels: ReturnType<typeof createAvatarPanels>
  /** 在公告栏跟前写公告的对话框 */
  private readonly bulletin: ReturnType<typeof createBulletinComposer>
  /** 最近一份道具目录：找化身所在处所的公告栏和张贴处 */
  private catalog: PropCatalog | null = null
  /** 触屏的摇杆和动作钮 */
  private readonly touch: ReturnType<typeof createAvatarTouch>
  private readonly timer: number
  /** 世界因故暂停的原因（额度用尽等），随名册更新 */
  private holds: WorldHold[] = []
  /** 名册里的世界时刻（分钟）：约时间时从它往后算 */
  private minutes = 0
  /** 进入控制前的 2D 镜头，交还后恢复 */
  private savedCamera: number[] | null = null
  private state: AvatarState | null = null
  private world = ''
  private online = false
  /** 化身命令的序号，换租约时从服务端给的值接着计 */
  private sequence = 0
  private tab: AvatarTab | null = null
  /** 面板上次重绘时的内容签名 */
  private signature = ''
  /** 镜头跟着化身；拖动地图后脱离，开始走、按 C 或点「回到化身」重新跟上 */
  private following = true
  /** 跟随镜头的逐帧循环（控制中才转）、上一帧人画在哪 */
  private cameraFrame = 0
  private cameraLast: { t: number; p: [number, number] } | null = null
  /** 下一帧开始把人挪回画面中间（按 C、点「回到化身」） */
  private recentre = false
  private bagSelection: string | null = null
  /** Tab 换到的当前对象（提示编号） */
  private focusedTarget: string | null = null
  /** 「和 X 说话」时还没进入化身：进去后走过去找的人 */
  private pendingTalk: string | null = null
  /** 「复活」「治愈」时还没进入化身：进去后走过去施展 */
  private pendingMiracle: { resident: string; kind: MiracleKind } | null = null
  /** 世界开着化身神力（世界设定）；化身状态里的 miracles 只在控制化身本人时为真 */
  private miraclesOn = false
  /** 名册上每个人的身体：神力选项单写会变成多少、做不了的原因 */
  private members = new Map<string, RosterMember>()
  /** 刚进入化身：镜头拉近到能看清人，拉一次 */
  private closeUp = false

  constructor(deps: AvatarDeps) {
    this.deps = deps
    this.map = deps.map
    const { signal } = this.listeners
    const mapEl = $('map')
    const actions = this.createActions()
    const ui = createAvatarUI(mapEl, signal, actions, deps.map.avatarLooks?.() ?? null, deps.game)
    this.ui = ui
    // 拖动地图即脱离跟随；开始走、按 C 或点「回到化身」重新跟上
    guardPointer(ui, mapEl, signal, () => {
      if (this.following && this.owned()) {
        this.following = false
        this.render()
      }
    })
    // 跟随时滚轮围着化身缩放，人不会被缩到画面一边
    deps.map.setZoomAnchor?.(() => {
      const id = this.state?.actor?.id
      return id && this.owned() && this.following ? this.map.getScreenPos?.(id) : undefined
    })
    window.addEventListener(
      'keydown',
      (e) => {
        if (e.code !== 'KeyC' || e.repeat || e.metaKey || e.ctrlKey || e.altKey) return
        if (!this.owned() || !mapVisible() || typing()) return
        e.preventDefault()
        this.resumeFollowing()
      },
      { signal }
    )
    this.lease = resumeLease(
      () => this.world,
      (command) => this.execute(command)
    )
    this.footsteps = movementSound(
      deps.sounds,
      () => this.state,
      () => this.owned()
    )
    this.navigation = this.createNavigation(signal)
    this.touch = createAvatarTouch(
      ui.root,
      {
        stick: (direction) => this.navigation.stick(direction),
        act: () => this.touchAct(),
        bag: () => this.toggleTab('bag'),
        cycle: () => void this.cycleTarget(1),
      },
      signal
    )
    deps.map.onPromptClick = (id) => this.promptClick(id)
    this.commands = createAvatarCommands({
      context: () => ({ online: this.online, world: this.world, state: this.state }),
      nextSequence: () => ++this.sequence,
      stopMoving: () => this.stopMoving(),
      showToast: ui.showToast,
      send: deps.send,
    })
    this.panels = createAvatarPanels(ui, deps, actions)
    this.bulletin = createBulletinComposer({
      send: deps.send,
      world: () => this.world,
      author: () => this.state?.actor?.name ?? '旅人',
      localeName: deps.localeName,
      showToast: ui.showToast,
    })
    escapeKey(
      ui,
      signal,
      () => this.closeTab(),
      () => this.closeDialog(),
      () => void this.leave()
    )
    this.timer = window.setInterval(() => this.pulse(), 5000)
  }

  /** 界面按钮、菜单和面板里的操作 */
  private createActions(): AvatarActions {
    return {
      openDialog: () => this.openDialog(),
      closeDialog: () => this.closeDialog(),
      execute: (command) => this.execute(command),
      toggleTab: (tab) => this.toggleTab(tab),
      openTab: (tab) => this.openTab(tab),
      closeTab: () => this.closeTab(),
      leave: () => this.leave(),
      stopMoving: () => this.stopMoving(),
      showHistory: () => {
        if (this.state?.actor) this.deps.openHistory(this.state.actor.id)
      },
      speak: () => this.speak(),
      follow: () => this.resumeFollowing(),
      resetCamera: () => this.resumeFollowing(),
      targets: () => this.targets(),
      bulletin: () => this.bulletinTargets(),
      render: (force) => this.render(force),
      selectBag: (id) => {
        this.bagSelection = id
      },
      miracleMenu: () => this.miracleMenu(),
      autoFollow: () => this.navigation.autoFollow(),
      setAutoFollow: (id) => {
        this.navigation.setAutoFollow(id)
        this.render()
      },
    }
  }

  private createNavigation(signal: AbortSignal) {
    return createAvatarNavigation({
      map: this.map,
      signal,
      getState: () => this.state,
      getWorld: () => this.world,
      getHolds: () => this.holds,
      owned: () => this.owned(),
      mapVisible,
      send: this.deps.send,
      execute: (command) => this.execute(command),
      targets: () => this.targets(),
      cycleTarget: (step) => this.cycleTarget(step),
      toggleBag: () => this.toggleTab('bag'),
      miracleMenu: () => this.miracleMenu(),
      showToast: this.ui.showToast,
      onDirection: (direction) => this.footsteps.update(direction[0] !== 0 || direction[1] !== 0),
      onWalk: () => this.resumeFollowing(false),
    })
  }

  /** 镜头重新跟上化身。按 C、点「回到化身」：把人慢慢挪回画面中间；
   *  拖开地图后一开始走（centre 为 false）：只是重新跟着，人走出取景框才挪，离得太远才挪回中间 */
  private resumeFollowing(centre = true) {
    if (!this.owned() || (this.following && !centre)) return
    this.following = true
    if (centre) this.recentre = true
    this.render()
    this.map.requestFrame?.()
  }

  owned() {
    return this.online && !!this.state?.controlled && !!this.state.actor?.present
  }

  stopMoving() {
    this.navigation.stopMoving()
  }

  /** 触屏主按钮：等于按 E；做不了时说明原因 */
  private touchAct() {
    if (!this.owned()) return
    const focused = this.targets().find((t) => t.prompt.focused)
    if (focused?.instant) return focused.run()
    if (!this.state?.speed) {
      this.ui.showToast(
        this.holds.length ? '世界因故暂停，请查看交谈面板中的原因' : '世界已暂停，请先继续运行'
      )
      return
    }
    const current = this.targets().find((t) => t.prompt.focused)
    if (!current) this.ui.showToast('附近没有可以互动的，走近人或东西再试')
    else if (current.prompt.key) this.navigation.primary()
    else this.ui.showToast(current.prompt.label)
  }

  /** 地图上点了提示标签：世界暂停时说明原因，否则执行这个对象的主动作 */
  private promptClick(id: string) {
    const target = this.owned() ? this.targets().find((t) => t.prompt.id === id) : undefined
    if (target?.instant) return target.run()
    if (this.owned() && !this.state?.speed) {
      if (id.startsWith('person:')) this.openTab('chat')
      else
        this.ui.showToast(
          this.holds.length ? '世界因故暂停，请查看交谈面板中的原因' : '世界已暂停，请先继续运行'
        )
      return
    }
    if (this.owned())
      this.targets()
        .find((t) => t.prompt.id === id)
        ?.run()
  }

  private targets() {
    const { state, map } = this
    return avatarTargets(
      state,
      (command) => this.execute(command),
      (tab) => this.openTab(tab),
      (id) => {
        this.bagSelection = id
      },
      {
        id: this.focusedTarget,
        where: map.walkTargetOf?.bind(map),
        // 还够不着的人：对准他，走过去，够得着就搭话
        approach: (id) => {
          this.focusedTarget = `person:${id}`
          this.navigation.reachFor('person', id)
        },
        cast: (id, kind) => void this.castAt(id, kind),
      },
      this.bulletinTargets()
    )
  }

  /** 化身所在处所里能贴公告的公告栏和张贴处；公告和公告栏在同一地点，就是化身现在所在的地点 */
  private bulletinTargets() {
    const locale = this.state?.actor?.locus.locale
    const spots = locale ? bulletinSpots(this.catalog, this.state?.props ?? [], locale) : null
    return (
      spots && { spots, open: (board: BulletinBoard) => this.owned() && this.bulletin.open(board) }
    )
  }

  /** Tab 在附近的对象间轮换当前对象，E 执行它 */
  private cycleTarget(step: 1 | -1): boolean {
    if (!this.owned() || !mapVisible()) return false
    const list = this.targets()
    if (!list.length) return false
    // 只有一个对象时 Tab 也留在地图上，不跳到页面上的按钮
    if (list.length < 2) return true
    const i = Math.max(
      0,
      list.findIndex((t) => t.prompt.focused)
    )
    this.focusedTarget = list[(i + step + list.length) % list.length].prompt.id
    this.render()
    return true
  }

  private execute(command: AvatarCommand) {
    return this.commands.execute(command)
  }

  private async leave() {
    this.stopMoving()
    if (!this.state?.controlled) return !this.state?.occupied
    const ok = await this.execute({ kind: 'leave' })
    if (ok) {
      this.lease.store()
      this.tab = null
    }
    return ok
  }

  async release() {
    return !this.state?.controlled || (await this.leave())
  }

  private async speak() {
    const { state, ui } = this
    const chat = runningTalk(state)
    const text = ui.draft.value.trim()
    const quietWalk = chat?.kind.kind === 'walk' && chat.can_request_turn
    if (!chat || !state?.actor || !text || !(chat.can_speak || quietWalk)) return
    if (!state.speed || !this.online) return
    if (
      await this.execute({
        kind: 'interact',
        revision: state.actor.revision,
        command: { operation: 'say', interaction_id: chat.id, message: text },
      })
    )
      ui.draft.value = ''
  }

  private openTab(next: AvatarTab) {
    this.stopMoving()
    if (this.deps.game) this.deps.collapseInfo()
    this.tab = next
    this.render(true)
  }

  private closeTab() {
    this.tab = null
    this.ui.draft.blur()
    this.stopMoving()
    this.render()
  }

  private toggleTab(next: AvatarTab) {
    if (this.tab === next) this.closeTab()
    else this.openTab(next)
  }

  closePanel() {
    if (this.ui.panel.hidden) return false
    this.closeTab()
    return true
  }

  openDialog() {
    const { state } = this
    if (!this.online || state?.occupied) return
    this.ui.entry.open(state?.actor)
  }

  private closeDialog() {
    this.ui.entry.close()
    this.pendingTalk = null
    this.pendingMiracle = null
    this.render()
  }

  closeEntry() {
    if (!this.ui.entry.isOpen()) return false
    this.closeDialog()
    return true
  }

  overlay(_open: boolean) {}

  async possess(resident: string) {
    const { ui, state } = this
    if (!this.map.avatarSupported) {
      ui.showToast('当前地图尚未支持接管', true)
      return false
    }
    if (state && !state.supported) {
      ui.showToast('后端尚未开放这张地图的接管能力', true)
      return false
    }
    if (this.state?.controlled && !(await this.leave())) return false
    return this.execute({ kind: 'possess', resident })
  }

  select(kind: 'chat' | 'bag', id?: string) {
    if (!this.owned()) return false
    // 点了谁，E 就对准谁：走近后身边先出现的往往是道具
    if (id) this.focusedTarget = `${kind === 'chat' ? 'person' : 'prop'}:${id}`
    if (id && this.navigation.reachFor(kind === 'chat' ? 'person' : 'prop', id)) return true
    this.openTab(kind)
    return true
  }

  /** 右栏「和 X 说话」：控制中直接走过去；没进入化身时先进入（第一次先选样子），进去后走过去 */
  talkTo(resident: string) {
    if (this.owned()) return this.select('chat', resident)
    if (!this.enterFirst()) return false
    this.pendingTalk = resident
    this.pendingMiracle = null
    return true
  }

  /** 进入化身：来过的直接回到上次的位置，第一次先选样子。进不去（断线、被别的页面占着）返回 false */
  private enterFirst() {
    const { state } = this
    if (!this.online || state?.occupied || !this.map.avatarSupported || !state?.supported)
      return false
    const actor = state.actor
    if (actor)
      void this.execute({
        kind: 'enter',
        name: actor.name,
        appearance: { marker: '我', color: actor.appearance.color },
      })
    else this.openDialog()
    return true
  }

  /** 神力的入口（地图上的钮、角色卡、死亡卡）该不该出现：世界开着神力，这张地图能用化身，
   *  没被别的页面占着，也没在附身（附身就是那个村民，村民不会神力） */
  miracleReady() {
    const s = this.state
    return (
      this.online &&
      this.miraclesOn &&
      !!this.map.avatarSupported &&
      !!s?.supported &&
      !(s.occupied && !s.controlled) &&
      s.mode !== 'possession'
    )
  }

  /** 对某人施展神力：控制中直接走过去，到了就施展；没进入化身时先进入，进去后再走过去 */
  miracle(resident: string, kind: MiracleKind) {
    if (!this.miracleReady()) return false
    if (this.owned()) return this.castAt(resident, kind)
    if (!this.enterFirst()) return false
    this.pendingMiracle = { resident, kind }
    this.pendingTalk = null
    return true
  }

  /** 走过去（够得着就不走），到了施展；施展前按最新的状态取修订号 */
  private castAt(resident: string, kind: MiracleKind) {
    this.ui.miracles.hidden = true
    this.focusedTarget = `person:${resident}`
    if (this.navigation.reachFor('person', resident, () => void this.cast(resident, kind)))
      return true
    this.ui.showToast('看不到这个人在哪，先走近一点')
    return false
  }

  private async cast(resident: string, kind: MiracleKind) {
    const a = this.state?.actor
    if (!a) return
    const ok = await this.execute({
      kind: 'miracle',
      revision: a.revision,
      recipient: resident,
      miracle: kind,
    })
    // 结果那句话随回执的说明当提示显示（handleMsg）；这里只画那一下光
    if (ok) playMiracle(this.map, $('map'), resident)
  }

  /** 几个人里离化身最近的一个；化身不在场或量不出位置时取第一个 */
  nearest(ids: string[]) {
    const me = this.state?.actor?.present ? this.map.getMemberPos(this.state.actor.id) : undefined
    const far = (id: string) => {
      const p = me && this.map.getMemberPos(id)
      return me && p ? Math.hypot(p[0] - me[0], p[1] - me[1]) : Infinity
    }
    return [...ids].sort((x, y) => far(x) - far(y))[0]
  }

  /** F 或操作条上的「神力」：对当前对象（人）打开选项单，写清会变成多少，做不了的灰着写原因 */
  private miracleMenu() {
    const { ui, state } = this
    if (!this.owned() || !state?.miracles) return
    if (!ui.miracles.hidden) {
      ui.miracles.hidden = true
      return
    }
    const current = this.targets().find((t) => t.prompt.focused)
    const id = current?.prompt.kind === 'person' ? current.prompt.target : null
    const m = id ? this.members.get(id) : undefined
    if (!id || !m) {
      ui.showToast('走近一个人，再施展神力')
      return
    }
    const head = el('p', `✦ 神力 · ${m.name}`, 'avatar-miracles-head')
    const rows = miracleOptions(m).map((o) => {
      const b = el('button')
      b.type = 'button'
      b.setAttribute('role', 'menuitem')
      b.disabled = !o.enabled
      b.append(el('b', o.label), el('small', o.note))
      b.onclick = () => void this.castAt(id, o.kind)
      return b
    })
    const foot = el('p', '够不着就先走过去；在场的人会看到', 'avatar-miracles-foot')
    ui.miracles.replaceChildren(head, ...rows, foot)
    ui.miracles.hidden = false
    rows.find((b) => !b.disabled)?.focus()
  }

  private panelState(): AvatarPanelState {
    return {
      state: this.state,
      online: this.online,
      holds: this.holds,
      tab: this.tab,
      invitationResults: this.invitations.results,
      bagSelection: this.bagSelection,
      minutes: this.minutes,
    }
  }

  /** 镜头跟着化身：控制中每帧跑一次 followFrame——地图逐帧画时由它在每次画之前调（人物、名字、镜头
   *  同一帧到位），不然自己逐帧跑。刚进入时先拉近一次，看得清自己和身边的人；本来就够近时不动。
   *  地图不会平滑跟随时，退回人快出画面才挪过去 */
  private followCamera(controlling: boolean) {
    const { map } = this
    const a = this.state?.actor
    if (!controlling || !a) {
      cancelAnimationFrame(this.cameraFrame)
      this.cameraFrame = 0
      this.cameraLast = null
      map.setFrameHook?.(null)
      return
    }
    const p = map.getMemberPos(a.id)
    if (p && this.closeUp) {
      this.closeUp = false
      const view = map.getViewBox()
      const width = Math.min(view[2], CLOSE_UP_WIDTH)
      const height = (width * view[3]) / view[2]
      map.setViewBox([p[0] - width / 2, p[1] - CAMERA_RISE - height / 2, width, height])
    }
    if (!map.followTo) {
      if (p && this.following) map.panTo(p[0], p[1] - CAMERA_RISE)
      return
    }
    if (map.setFrameHook?.(this.frameHook)) {
      cancelAnimationFrame(this.cameraFrame)
      this.cameraFrame = 0
      return
    }
    if (!this.cameraFrame) {
      const loop = (now: number) => {
        this.cameraFrame = requestAnimationFrame(loop)
        this.followFrame(now)
      }
      this.cameraFrame = requestAnimationFrame(loop)
    }
  }

  private readonly frameHook = (t: number) => this.followFrame(t)

  /** 一帧的跟随：人在画面中间的取景框里走动时镜头不动，顶出框才跟上（见 MapCamera.follow）；
   *  人一下子挪很远（进门、出门）就直接切过去。拖开地图后只记位置不动镜头。返回这一帧挪了镜头 */
  private followFrame(now: number): boolean {
    const { map, state } = this
    const a = state?.actor
    if (!a || !this.owned() || !mapVisible() || document.hidden) {
      this.cameraLast = null
      return false
    }
    const p = map.getDrawnPos?.(a.id) ?? map.getMemberPos(a.id)
    if (!p) return false
    const last = this.cameraLast
    this.cameraLast = { t: now, p }
    if (!this.following) return false
    const dt = last ? Math.min(100, Math.max(0, now - last.t)) : 0
    const jumped = !!last && Math.hypot(p[0] - last.p[0], p[1] - last.p[1]) > CAMERA_JUMP
    const how = jumped ? 'snap' : this.recentre ? 'centre' : 'window'
    this.recentre = false
    return map.followTo?.(p[0], p[1] - CAMERA_RISE, dt, how) ?? false
  }

  private render(force = false) {
    const { ui, map, state } = this
    ui.root.hidden = !map.avatarSupported || !state?.supported
    const a = state?.actor
    const controlling = this.owned()
    const possessing = state?.mode === 'possession'
    // 退出化身常驻在操作条上（原来藏在「⋯」里）；游戏界面另有「离开小镇」槽钮
    ui.releaseBtn.hidden = !controlling || (!possessing && this.deps.game)
    const releaseLabel = possessing ? '交还 AI' : '退出化身'
    if (ui.releaseBtn.textContent !== (isTouch() ? '' : 'Esc') + releaseLabel)
      ui.releaseBtn.replaceChildren(...(isTouch() ? [] : [keycap('Esc')]), el('span', releaseLabel))
    ui.profileMenu.hidden = possessing
    ui.leaveMenu.textContent = possessing ? '交还 AI' : '退出化身'
    const flag = document.getElementById('avatar-flag')
    if (flag) flag.textContent = possessing && a ? `正在附身 · ${a.name}` : '化身在场'
    const controlled = controlling
    map.setAvatarState?.(state ? { ...state, controlled } : null)
    map.setAvatarActive?.(controlling)
    // 手机布局据此收起底部入口和最新事件那一行
    document.documentElement.classList.toggle('avatar-controlling', controlling)
    const occupied = !!state?.occupied
    const online = this.online
    ui.entry.render({ supported: !ui.root.hidden, controlling, online, occupied, actor: a })
    ui.hud.hidden = !controlling
    if (this.deps.game) document.body.classList.toggle('player-mode', controlling)
    if (!controlling) ui.menu.hidden = true
    ui.miracleBtn.hidden = !controlling || !state?.miracles
    if (ui.miracleBtn.hidden) ui.miracles.hidden = true
    if (controlling) {
      this.panels.renderHud(this.panelState())
    }
    ui.panel.hidden = !controlling || this.tab === null
    ui.back.hidden = !controlling || this.following
    const talk = runningTalk(state)
    ui.composer.hidden = this.tab !== 'chat' || !talk || !controlling
    // 同行路上安静着时也能直接开口（世界从开口的人说起）
    const canSay = !!talk?.can_speak || (talk?.kind.kind === 'walk' && !!talk.can_request_turn)
    ui.say.disabled = !canSay || !state?.speed || this.commands.pendingMutation || !online
    ui.draft.readOnly = !state?.speed || !online
    const prompts = controlling ? this.targets().map((t) => t.prompt) : []
    map.setAvatarPrompts?.(prompts)
    this.touch.render(controlling, prompts)
    const next = panelSignature(this.panelState(), controlling)
    if (a && controlling && this.tab && (force || next !== this.signature)) {
      this.signature = next
      this.panels.renderPanel(this.panelState())
    }
    this.followCamera(controlling)
  }

  /** 收到新的化身状态：换人、换租约、拿到或交还控制时各有收尾，然后重画 */
  private receive(next: AvatarState) {
    const old = this.state
    this.state = next
    if (!this.navigation.canWalk()) this.footsteps.update(false)
    if (
      next.controlled &&
      next.actor?.present &&
      (!old?.controlled || !old.actor?.present || old.actor?.id !== next.actor.id)
    )
      this.deps.sounds?.playDescend()
    if (old?.actor?.id !== next.actor?.id) this.invitations.results.clear()
    if (old?.epoch !== next.epoch) {
      this.navigation.restartSequence()
      this.sequence = next.sequence ?? 0
      this.stopMoving()
    }
    if (next.resume_token) this.lease.store(next.resume_token)
    const { ui } = this
    if (next.actor && !ui.profile.contains(document.activeElement)) {
      ui.profileName.value = next.actor.name
      ui.profilePicker.set(next.actor.appearance.color)
    }
    if (next.controlled && !old?.controlled) this.takeControl()
    if (old?.controlled && !next.controlled) {
      if (this.savedCamera) this.map.setViewBox(this.savedCamera)
      this.savedCamera = null
      this.tab = null
    }
    // 邀请发出后立刻显示等待状态；回应、拒绝与过期也给出结果。
    const invited = this.invitations.update(next, this.tab)
    this.tab = invited.tab
    for (const result of invited.fresh) ui.showToast(result)
    this.render()
  }

  /** 刚拿到控制：放开输入框的焦点，记下原来的镜头，提示操作方法 */
  private takeControl() {
    // 对话框里的输入框还握着焦点会被当成「正在输入」，方向键就发不出去
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
    this.savedCamera = this.map.getViewBox()
    this.following = true
    this.closeUp = true
    this.tab = null
    this.bagSelection = null
    // 从右栏「和 X 说话」「复活」进来的：进去后直接走过去
    const talk = this.pendingTalk
    const miracle = this.pendingMiracle
    this.pendingTalk = null
    this.pendingMiracle = null
    if (talk) window.setTimeout(() => this.select('chat', talk), 200)
    if (miracle) window.setTimeout(() => this.castAt(miracle.resident, miracle.kind), 200)
    // 触屏上提示条在顶上压着地图，写短一点、早点收：摇杆和右下的按钮自己就看得出用法
    this.ui.showToast(
      isTouch()
        ? '摇杆或点地图走路，靠近人和东西点右下的按钮'
        : '点地图走过去，点人或东西走过去并互动；WASD 也能走，E 互动，B 打开背包',
      false,
      isTouch() ? 4000 : 6000
    )
  }

  reset() {
    this.stopMoving()
    this.footsteps.update(false)
    this.lease.store()
    this.state = null
    this.holds = []
    this.invitations.results.clear()
    this.world = ''
    this.lease.allowRetry()
    this.tab = null
    this.ui.entry.close()
    this.ui.hideToast()
    this.render()
  }

  /** 每 5 秒：重画一次；控制中发心跳，否则拉一次化身状态 */
  private pulse() {
    this.render()
    if (this.owned()) void this.execute({ kind: 'heartbeat' })
    else if (this.online && this.world) void this.execute({ kind: 'view' })
  }

  handleMsg(message: ServerMsg) {
    if (message.type === 'roster') {
      this.minutes = message.sim_minutes
      this.holds = message.holds ?? []
      this.members = new Map(message.locales.flatMap((l) => l.members).map((m) => [m.id, m]))
      this.render()
    }
    if (message.type === 'world_settings') {
      this.miraclesOn = message.state.miracles
      this.enterWorld(message.state.world_id)
    }
    // 化身命令没能执行（格式错误、命令过多）时回的是通用错误：结束等待并提示
    if (message.type === 'error' && message.request_id !== undefined) {
      const p = this.commands.settle(message.request_id, false)
      if (p) this.ui.showToast(message.message, true)
      return !!p
    }
    if (message.type === 'props') this.catalog = message.catalog
    if (this.bulletin.handleMsg(message)) return true
    if (message.type !== 'avatar_state' && message.type !== 'avatar_result') return false
    if (message.state.world_id !== this.world) return true
    this.receive(message.state)
    // 每拍一条化身状态：位置是新的，点击移动就在这里重算方向
    if (message.type === 'avatar_state') {
      this.navigation.followChased()
      this.navigation.walk.tick()
    }
    if (message.type === 'avatar_result') {
      const p = this.commands.settle(message.request_id, message.ok)
      if (message.message && !(p?.silent && !message.ok))
        this.ui.showToast(message.message, !message.ok)
    }
    return true
  }

  /** 收到世界设定：换了世界先清掉旧状态；然后拉一次化身状态，没在控制就试着恢复上次的控制 */
  private enterWorld(worldId: string) {
    if (this.world !== worldId) {
      this.reset()
      this.world = worldId
    }
    void this.execute({ kind: 'view' }).then(() =>
      this.lease.attempt(!!this.state?.controlled, !!this.map.avatarSupported)
    )
  }

  connected() {
    this.online = true
    this.lease.allowRetry()
    this.render()
  }

  disconnected() {
    this.stopMoving()
    this.footsteps.update(false)
    this.online = false
    this.commands.clear()
    this.render()
  }

  dispose() {
    this.stopMoving()
    this.footsteps.update(false)
    this.listeners.abort()
    clearInterval(this.timer)
    cancelAnimationFrame(this.cameraFrame)
    this.map.setFrameHook?.(null)
    this.map.setZoomAnchor?.(null)
    this.ui.root.remove()
    this.bulletin.dispose()
    document.documentElement.classList.remove('avatar-controlling')
    if (this.deps.game) document.body.classList.remove('player-mode')
    this.map.onPromptClick = null
    this.map.setAvatarPrompts?.([])
    this.commands.clear()
  }
}
