// 地图页的各面板：建好后按顺序登记到外壳，外壳再按登记顺序分发消息、名册与连接事件。
// 登记顺序决定同一条消息先给谁：名册要在各面板读之前整理好。
import type { ResidentContext } from '../application'
import { createAvatar } from '../avatar/controller'
import type { GameAudio } from '../audio/controller'
import { initBooks } from '../books'
import { ChatBubbles } from '../chat/bubbles'
import { createChatHistory } from '../chat/history'
import { unclaimedReceipt, type Receipt, type SaveCommand } from '../connection'
import { initDiary } from '../diary'
import { $ } from '../dom'
import { installEmptyTown } from '../emptyTown'
import type { EventsHandle } from '../events'
import type { GameMap } from '../gameMap'
import { initInfoPanel } from '../infoPanel'
import { createResidentStrip } from '../info/strip'
import type { MapEntry, Topology } from '../mapDocument'
import { namesOf, type HoldFix } from '../holds'
import { createMapToast } from '../mapToast'
import { townWorldview } from '../townWorldview'
import { initMemory } from '../memory'
import { installModelWait } from '../modelWait'
import { autoUpdateBuiltin } from '../models/builtin'
import { createModelSession } from '../models/session'
import { createNotices } from '../notices'
import { createTownPanel } from '../town/panel'
import { installPauseHint, type PauseHint } from '../pauseHint'
import { initProps } from '../props/page'
import type { ClientMsg, JoinOutcome, ServerMsg, TemplateCard } from '../protocol'
import type { ModelOption } from '../models/session'
import { priceOf, type Price } from '../pricing'
import { initResidentsPage } from '../residents'
import { initSettingsCenter } from '../settingsCenter'
import { initUsage } from '../usage'
import { createWeatherPanel } from '../weather/panel'
import { createWorldSettings } from '../worldSettings'
import { rememberPopulation } from '../portraits'
import { createPanelRegistry, rosterFrame, type RosterMsg, type ShellPanel } from './panel'
import { createSettingsSession, type SettingsSession } from './settingsSession'
import { installBackToMaps, installSpeedBar, topbarPanel, type SpeedBar } from './topbar'

interface ShellInputs {
  normalSpeed: number
  /** 游戏界面；2D 地图用平铺界面 */
  game: boolean
  selectedMap: MapEntry
  map: GameMap
  events: EventsHandle
  localeName: (id: string) => string
  topology: Topology
  /** 重演录像：画面不连世界，这个页面没打开过小镇，离开时也不能去关（它可能正开在别的页面上跑） */
  replay: boolean
  send: (msg: ClientMsg) => void
  /** 发出保存命令，按请求编号收回执；断线时以失败结束 */
  save: (command: SaveCommand, receipt: Receipt) => void
  audio: GameAudio
}

export function createPanels(input: ShellInputs) {
  const { map, events, localeName, send, selectedMap, game } = input
  const session = createSettingsSession(map, send, game, () => avatar.release())
  const chatHistory = createChatHistory(send, localeName, game, () => infoPanel.setCollapsed(false))
  // HD-2D 的台词使用独立聊天气泡
  const chatBubbles = game
    ? null
    : new ChatBubbles(map, $('map'), (actor, chat) => chatHistory.open(actor, chat))
  const worldSettings = createWorldSettings(
    send,
    selectedMap.name,
    session.forgetSpeed,
    game,
    townWorldview(selectedMap.id)
  )
  /** 名册里的居民（不含化身），每拍名册重建 */
  const observed = new Map<string, ResidentContext>()
  // 模型配置：首次对话框里的「还差一步」和点「开始」前的拦截都看它
  const models = createModelSession({
    send,
    save: input.save,
    residents: () => [...observed.keys()],
  })
  worldSettings.setModels(models)
  const modelWait = installModelWait($('map'), {
    models,
    mock: () => !!worldSettings.state()?.mock,
  })
  // 内置模型的状态：等模型的提示条和开局向导都要看；被打断的下载接着下，开着自动更新就看有没有新版本
  void autoUpdateBuiltin()
  const selectedResident = (): ResidentContext | null =>
    observed.get(infoPanel.selected() ?? '') ?? null
  const withSelected = (action: (r: ResidentContext) => void) => () => {
    const r = selectedResident()
    if (r) action(r)
  }
  // 地图左上角的头像条：点头像和在地图上点人一样，先关掉道具卡，再选中并打开角色卡
  const strip = createResidentStrip({
    map,
    container: $('map'),
    dock: $('hud-left'),
    localeName,
    open: (id) => {
      props.closeCard()
      infoPanel.open(id)
    },
    invite: () => void open.residents(),
    selected: () => infoPanel.selected(),
    avatarActive: () => avatar.active(),
  })
  const infoPanel = initInfoPanel({
    map,
    events,
    localeName,
    onPossess: (id) => void avatar.possess(id),
    // 页签里改人设、长相、模型：保存走连接的回执；「去配置这个服务」打开右上角的设定
    editor: {
      send,
      save: input.save,
      openSettings: (pageId) => void session.enter(pageId),
      residentName: (id) => observed.get(id)?.name,
    },
    onOpenDiary: () => {
      // 没选中居民时用名册第一位：日记页左栏自带村民切换，不应弹名册
      const r = selectedResident() ?? [...observed.values()][0]
      if (r && !session.inSettings()) pages.diary.open(r)
    },
    onOpenMemory: withSelected((r) => {
      if (!session.inSettings()) pages.memory.open(r)
    }),
    onSelectResident: (id) => send({ type: 'get_agent_config', resident: id }),
    onWatchDetail: (id) =>
      send(id ? { type: 'watch_resident', resident: id } : { type: 'watch_resident' }),
    replay: input.replay,
    onSelectionChange: () => chatHistory.residentChanged(),
    onSelected: () => strip.select(),
    avatarActive: () => avatar.active(),
    avatarAvailable: () => avatar.available(),
    onOpenItem: (id) => props.open(id),
    // 点一次开始就会清掉所有居民的暂停原因；世界在运行时按原速度再选一次
    onResumeAgents: () => resumeAgents(),
    waitLine: (m) => modelWait.line(m),
    onTalk: (id) => void avatar.talkTo(id),
    miracleReady: () => avatar.miracleReady(),
    onMiracle: (id, kind) => void avatar.miracle(id, kind),
    onAdjustBody: (id, values, done) => {
      const world_id = worldSettings.state()?.world_id
      if (!world_id) return done(false, '还没读到世界设定')
      input.save({ type: 'set_resident_body', world_id, resident_id: id, values }, done)
    },
  })
  const resumeAgents = () => pages.speeds.choose(pages.speeds.current() || input.normalSpeed)
  /** 「在地图上定位」：先停止跟随，不然下一份名册就把镜头拉回跟着的人 */
  const locateProp = (id: string, locale: string) => {
    infoPanel.follow(false)
    map.locateProp(id, locale)
  }
  const books = initBooks({
    send,
    town: selectedMap.id,
    game,
    locate: locateProp,
  })
  const props = initProps({
    send,
    game,
    read: (id) => {
      props.close()
      books.read(id)
    },
    openBoard: (id) => {
      props.close()
      books.board(id)
    },
    onLocate: locateProp,
    onUpdate: (list, spatial) => map.setProps(list, spatial),
    map: map.placeSpotAt ? map : undefined,
    personName: (id) => observed.get(id)?.name,
  })
  const center = initSettingsCenter({
    send,
    onBack: () => session.exit(),
    save: input.save,
    map,
    game,
    openUsage: () => {
      session.exit()
      if (!session.inSettings()) open.usage()
    },
    audio: input.audio,
    townPrice: () => priceOf(models.options()[0]),
  })
  session.bind(center)
  // 世界观面板：这一局的世界观、规则和重置，从地图左上角的「世界观」打开（菜单里也有），地图留在背后
  const town = createTownPanel({
    world: worldSettings,
    send,
    townName: selectedMap.name,
    onOpen: () => avatar.stopMoving(),
  })
  worldSettings.setOpenTown(town.open)
  const toast = createMapToast($('map'))
  /** 请人入住结束：回到地图，一句话说谁搬进来了、用哪个模型；镜头挪过去 */
  function joined(list: JoinOutcome[], failed: string[], model: ModelOption | null) {
    for (const reason of failed) events.pushLocal(`没请成：${reason}`, true)
    if (!list.length) return
    if (pages.residents.isOpen()) pages.residents.close()
    const names = list.map((j) => j.name ?? '').filter(Boolean)
    const how = model ? `用 ${model.name} 思考` : '连上模型后开始行动'
    const start = pages.speeds.current() ? '' : ' · 点左上角的 ▶ 让小镇动起来'
    toast.show(`${namesOf(names)}搬进来了 · ${how}${start}`)
    lookAt(list[0].resident_id)
  }
  /** 新居民从入口进镇：名册可能晚一帧才带上新人，等一会儿再找 */
  function lookAt(id: string | undefined, tries = 20) {
    if (!id) return
    const at = map.getMemberPos(id)
    if (at) map.panTo(at[0], at[1])
    else if (tries > 0) setTimeout(() => lookAt(id, tries - 1), 100)
  }
  const pages = createPages(input, {
    session,
    infoPanel,
    observed,
    overlay: (on) => avatar.overlay(on),
    modelOptions: () => models.options(),
    connectModel: () => modelWait.connect(),
    joined,
    library: (cards) => emptyTown.setLibrary(cards),
    // 消耗页算钱：村民按自己用的模型，不给编号时按小镇默认的模型
    price: (id) => priceOf(id ? modelWait.modelOf(id) : models.options()[0]),
  })
  // 点「开始」前：还没连模型先请玩家连上，连上了但有人没选模型就地问一句（modelWait.ts）
  pages.speeds.setGate((go) => modelWait.gate(go))
  const avatar = createAvatar({
    send,
    map,
    openHistory: (id) => chatHistory.open(id),
    localeName,
    places: input.topology.places.map((p) => ({ id: p.locale, name: p.name })),
    resumeSpeed: input.normalSpeed,
    sounds: input.audio,
    game,
    collapseInfo: () => {
      if (!infoPanel.isCollapsed()) infoPanel.collapse()
    },
    openUsage: () => open.usage(),
    openSettings: () => void session.enter(),
    fixHold: (fix, provider) => fixHold(fix, provider),
  })
  const open = createOpeners({ avatar, pages, props, books, session })
  // 菜单里的「消耗」「设定」（shell/plain.html）
  $('open-usage').onclick = open.usage
  $('open-settings').onclick = () => session.enter()
  const emptyTown = installEmptyTown($('map'), {
    ready: () => !!worldSettings.state()?.ready,
    create: open.newVillager,
    library: open.library,
    requestLibrary: pages.residents.requestLibrary,
    invite: pages.residents.invite,
    modelOptions: () => models.options(),
    joinModel: pages.residents.joinModel,
    chooseModel: pages.residents.setJoinModel,
    connectModel: () => modelWait.connect(),
  })
  worldSettings.subscribe(emptyTown.sync)
  models.subscribe(emptyTown.refresh)
  // 离开小镇前：角色卡页签里还有没存的草稿先问一句，再交还化身控制
  if (!input.replay)
    installBackToMaps(selectedMap, events, async () => {
      const unsaved = infoPanel.unsaved()
      if (
        unsaved.length &&
        !confirm(
          `还有没保存的修改：${unsaved.join('、')}。\n「确定」放弃修改并离开；「取消」留下来保存。`
        )
      )
        return false
      return avatar.release()
    })
  // 信息栏按世界生理开关补画关掉的项
  worldSettings.subscribe(() => {
    const switches = worldSettings.state()?.physiology
    if (switches) infoPanel.onPhysiology(switches)
  })
  /** 全镇暂停卡上的修复按钮：换密钥、换服务直接打开连接弹层，连上就接着跑；额度和模型去设定 */
  async function fixHold(fix: HoldFix, provider: string) {
    const id = provider ? models.providerId(provider) : undefined
    if (fix === 'retry') return resumeAgents()
    if (fix === 'limits') return void session.enter('limits')
    if (fix === 'model') return void session.enter('providers')
    const result = await models.connect(
      fix === 'key'
        ? {
            title: `换个${provider ? ` ${provider} 的` : ''}密钥`,
            text: '旧的密钥用不了了。贴一个新的，测试通过后村民接着行动。',
            dismiss: '取消',
            confirm: '测试并继续',
            provider: id,
          }
        : {
            title: '换一个模型服务',
            text: '选一个服务、填上密钥，测试通过后用它的村民都改用新的服务接着行动。',
            dismiss: '取消',
            confirm: '测试并继续',
          }
    )
    if (result !== 'connected') return
    const next = models.lastConnected()
    if (fix === 'provider' && next && next.provider !== id) {
      // 新服务设成默认，用旧服务的村民都改用它；没改成的村民卡片上会写明，点进去还能选
      await models.makeActive(next).catch(() => {})
      if (id) await modelWait.moveResidents(id, next).catch(() => {})
    }
    resumeAgents()
  }
  // 重要事件提示卡：「查看」选中该村民并让镜头跟随；暂停卡的按钮直接去修；
  // 开着化身神力时死亡卡上的「去复活」：化身走到最近的一位身边复活他
  const notices = createNotices(
    $('map'),
    (id) => {
      infoPanel.select(id)
      infoPanel.follow(true)
    },
    (fix, provider) => void fixHold(fix, provider),
    {
      ready: () => avatar.miracleReady(),
      go: (ids) => {
        const id = avatar.nearest(ids)
        if (id) avatar.miracle(id, 'revive')
      },
    }
  )
  events.onImportant((clock, important) => notices.show(clock, important))
  const parts = {
    session,
    chatHistory,
    chatBubbles,
    worldSettings,
    town,
    observed,
    infoPanel,
    strip,
  }
  const shell = {
    ...parts,
    ...{ books, props, center, notices, avatar, open, emptyTown, models, modelWait },
    ...pages,
  }
  return { ...shell, ...register(input, shell) }
}
export type Panels = ReturnType<typeof createPanels>

/** 入口按钮与链接打开整页：控制化身时先交还控制，交还失败就留在地图上 */
function createOpeners(parts: {
  avatar: { release(): Promise<boolean>; stopMoving(): void }
  pages: ReturnType<typeof createPages>
  props: { open(): void; placing: { toggle(): void } | null }
  books: { open(): void }
  session: { inSettings(): boolean }
}) {
  const { avatar, pages, props, books, session } = parts
  const guarded = (go: () => void) => async () => {
    if (await avatar.release()) go()
  }
  return {
    residents: guarded(() => pages.residents.open()),
    newVillager: guarded(() => pages.residents.create()),
    library: guarded(() => pages.residents.open('library')),
    // 「道具」开关道具浮窗；地图不支持摆道具时打开整页
    props: guarded(() => (props.placing ? props.placing.toggle() : props.open())),
    books: guarded(() => books.open()),
    usage: () => {
      // 只读消耗页保留控制租约和聊天；隐藏地图前清掉移动输入
      avatar.stopMoving()
      if (!session.inSettings()) pages.usage.open()
    },
  }
}

/** 整页替换地图页的几个页面，以及时钟牌旁的开始/暂停钮 */
function createPages(
  input: ShellInputs,
  panels: {
    session: ReturnType<typeof createSettingsSession>
    infoPanel: ReturnType<typeof initInfoPanel>
    observed: Map<string, ResidentContext>
    /** 菜单等覆盖层打开时停止化身移动 */
    overlay: (open: boolean) => void
    modelOptions: () => ModelOption[]
    connectModel: () => void
    joined: (list: JoinOutcome[], failed: string[], model: ModelOption | null) => void
    library: (cards: TemplateCard[]) => void
    price: (residentId?: string) => Price | null
  }
) {
  const { map, events, localeName, send, game } = input
  const { session, infoPanel, observed } = panels
  const diary = initDiary({
    send,
    game,
    onBack: () => diary.close(),
    residents: () => [...observed.values()],
  })
  const memory = initMemory({ send, game, onBack: () => memory.close() })
  const usage = initUsage({ send, game, onBack: () => usage.close(), price: panels.price })
  const locateResident = (id: string) => {
    infoPanel.select(id)
    const pos = map.getMemberPos(id)
    if (pos) map.panTo(pos[0], pos[1])
  }
  const residents = initResidentsPage({
    send,
    game,
    events,
    localeName,
    onLocate: locateResident,
    onFollow: (id) => {
      locateResident(id)
      infoPanel.follow(true)
    },
    // 名册上的「档案」：回到地图，打开他的角色卡，翻到人设
    onOpenProfile: (r) => {
      locateResident(r.id)
      infoPanel.open(r.id, 'persona')
    },
    // 住宅不算去处；默认图把道路和入口也登记成了处所，同样不列
    placeNames: () =>
      input.topology.places
        .filter((p) => !p.residential && !/(道路|入口)$/.test(p.name))
        .map((p) => p.name),
    modelOptions: panels.modelOptions,
    connectModel: panels.connectModel,
    onJoined: panels.joined,
    onLibrary: panels.library,
    onOverlayOpen: () => {
      infoPanel.collapse()
      panels.overlay(true)
    },
  })
  const speeds = installSpeedBar(send, session.setSpeed, input.normalSpeed)
  // HD-2D 暂停和自动快进时显示提示，空格开始运行
  const pauseHint = game
    ? null
    : installPauseHint(
        $('map'),
        (speed) => (speed > 0 ? speeds.start() : (speeds.choose(speed), true)),
        input.normalSpeed
      )
  return { diary, memory, usage, residents, speeds, pauseHint }
}

/** 登记到外壳的各面板 */
interface RegisteredParts {
  observed: Map<string, ResidentContext>
  session: SettingsSession
  speeds: SpeedBar
  pauseHint: PauseHint | null
  avatar: ReturnType<typeof createAvatar>
  chatHistory: ReturnType<typeof createChatHistory>
  chatBubbles: ChatBubbles | null
  worldSettings: ReturnType<typeof createWorldSettings>
  town: ReturnType<typeof createTownPanel>
  diary: ReturnType<typeof initDiary>
  memory: ReturnType<typeof initMemory>
  infoPanel: ReturnType<typeof initInfoPanel>
  strip: ReturnType<typeof createResidentStrip>
  residents: ReturnType<typeof initResidentsPage>
  usage: ReturnType<typeof initUsage>
  books: ReturnType<typeof initBooks>
  models: ReturnType<typeof createModelSession>
  props: ReturnType<typeof initProps>
  center: ReturnType<typeof initSettingsCenter>
  notices: ReturnType<typeof createNotices>
  emptyTown: ReturnType<typeof installEmptyTown>
  modelWait: ReturnType<typeof installModelWait>
}

/** 按顺序登记各面板；名册与世界重置由这里整理后再逐个通知 */
function register(input: ShellInputs, p: RegisteredParts) {
  const { map, events, send, selectedMap } = input
  const registry = createPanelRegistry()
  const roster = (msg: RosterMsg) => registry.roster(rosterFrame(msg))
  const reset = (msg: Extract<ServerMsg, { type: 'world_reset' }>) => {
    events.markReset()
    events.setClock(msg.clock) // 本地这条也用新世界的时钟，别沿用旧世界的
    events.pushLocal(
      selectedMap.id.startsWith('physiology-')
        ? `本场景已恢复初始条件，回到 ${msg.clock}，已暂停`
        : `已重置为空村，回到 ${msg.clock}，已暂停；请村民搬进来后再点开始`
    )
    registry.reset()
  }
  const observedPanel: ShellPanel = {
    roster({ residents }) {
      p.observed.clear()
      for (const { member } of residents)
        p.observed.set(member.id, { id: member.id, name: member.name })
    },
  }
  const mapPanel: ShellPanel = {
    handleMsg: (message) => void map.handleMsg?.(message),
    roster({ msg, entries }) {
      map.setSpeed(msg.speed)
      map.update(entries)
    },
    onReset: () => map.onReset(),
    disconnected: () => map.disconnect?.(),
  }
  const hubs = {
    roster: {
      handleMsg: (m: ServerMsg) => m.type === 'roster' && (roster(m), true),
    },
    reset: {
      handleMsg: (m: ServerMsg) => m.type === 'world_reset' && (reset(m), true),
    },
    population: {
      handleMsg(m: ServerMsg) {
        if (m.type !== 'population') return
        // 先记下出图编号：设定目录、通知卡、信息栏的头像都按它找
        rememberPopulation(m.population)
        p.infoPanel.onPopulation(m.population)
        p.notices.setResidents(m.population.residents)
        p.center.setResidents(m.population.residents)
        p.emptyTown.setPopulation(m.population)
        p.modelWait.setPopulation(m.population)
      },
    },
    // agent_config / model_config / model_test_result：选中村民的分界线交给信息栏，其余广播给设定中心各子页
    tuning: {
      handleMsg(m: ServerMsg) {
        const selected = p.observed.get(p.infoPanel.selected() ?? '')
        if (m.type === 'agent_config' && m.resident_id === selected?.id)
          p.infoPanel.onTuning(m.tuning, m.health_marks)
      },
    },
  }
  registry.add(
    observedPanel,
    topbarPanel(p.speeds, p.pauseHint, () => p.avatar.active()),
    p.modelWait.panel,
    {
      roster: ({ msg, residents }) => {
        p.notices.syncHolds(msg.holds ?? [])
        const life = new Map(residents.map(({ member }) => [member.id, member.body?.life]))
        p.notices.syncLife((id) => life.get(id) === 'alive')
      },
    },
    p.session.panel,
    {
      roster: ({ msg, residents }) =>
        input.audio.roster(
          msg,
          residents.map(({ member }) => member)
        ),
      // 不拦消息：事件栏、提示卡照常收到
      handleMsg(m) {
        if (m.type === 'event' && m.alert?.kind === 'death') input.audio.death(!!m.alert.killed)
      },
      dispose: input.audio.dispose,
    },
    createWeatherPanel(send, map, input.game),
    p.avatar,
    { connected: () => send({ type: 'get_model_config' }) },
    p.chatHistory,
    mapPanel,
    p.worldSettings,
    p.town.panel,
    hubs.roster,
    p.chatBubbles,
    events,
    p.diary,
    p.memory,
    hubs.reset,
    hubs.population,
    p.infoPanel,
    // 排在信息栏后面：第一份名册替玩家选中的人，头像条同一拍就高亮
    p.strip,
    p.residents,
    p.usage,
    // 书与公告只旁听道具目录，要排在道具页前面：道具页收到目录就认领了
    p.books.panel,
    p.props,
    hubs.tuning,
    // 模型配置只旁听，排在设定中心前面
    p.models.panel,
    p.center,
    // 没有页面认领的错误与回执最后写进事件栏
    { handleMsg: (m) => unclaimedReceipt(m, events.pushLocal) }
  )
  return { registry }
}
