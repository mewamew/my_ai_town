import type { ResidentContext } from './application'
import type { ClientMsg, ModelChoice, ServerMsg } from './protocol'
import type { GameMap } from './gameMap'
// 设定中心外壳：只放跟着这台设备的东西，左侧目录分模型 / 游戏两组。这一局的世界观、规则和重置世界在
// 世界观面板（town/panel.ts，地图左上角「世界观」打开），村民的人设、长相、用哪个模型在他的角色卡页签里（info/tabs.ts）。
// 底部保存栏只在有未保存修改时出现。进入时暂停与返回后恢复速度由游戏页外壳负责；
// 这里管页面切换、脏状态与保存分发。

import type { PageDeps } from './settings/page'
import { createModelPage } from './settings/model'
import { createProviderListPage } from './settings/providerList'
import { createSoundPage } from './settings/sound'
import { createDisplayPage } from './settings/display'
import { createLimitsPage } from './settings/limits'
import { createSettingsNav } from './settings/nav'
import { $ } from './dom'
import { isCompact } from './platform'
import { iconLabel } from './game/icons'
import type { GameAudio } from './audio/controller'
import type { RosterFrame } from './shell/panel'

/** 保存回执：连接按请求编号把 agent_saved / config_saved / error 交给发起方 */
export type { Receipt } from './connection'
import type { Receipt, SaveCommand } from './connection'

export interface SettingsPage {
  id: string
  group: 'model' | 'game'
  navLabel: string
  /** 页名；保存栏列出未保存的页时也用它 */
  title: string
  el: HTMLElement
  isDirty(): boolean
  /** 改了什么，写在保存栏上；不提供时只写页名 */
  dirtySummary?(): string
  /** 发送保存消息（回执按请求编号回来；断线时以失败结束） */
  save(): void
  /** 放弃修改：重填已保存值 */
  discard(): void
  onShow?(): void
  onDisconnected?(): void
  handleMsg?(msg: ServerMsg): void
}

interface CenterDeps {
  send: (obj: ClientMsg) => void
  onBack: () => void
  save: (command: SaveCommand, receipt: Receipt) => void
  /** 显示页的地图俯角要调用地图；没有俯角的地图不显示那一项 */
  map?: GameMap
  /** 游戏界面 */
  game: boolean
  /** 离开设定中心去「消耗」页；有未保存修改时先问 */
  openUsage: () => void
  /** 声音开关 */
  audio: Pick<GameAudio, 'music' | 'story' | 'effects'>
  /** 小镇默认模型的价格（花费上限按它换算）；价格没收录时为 null */
  townPrice: () => import('./pricing').Price | null
}

export function initSettingsCenter(deps: CenterDeps) {
  const pageBox = $('settings-page')
  const savebar = $('settings-savebar')
  const savebarHint = $('settings-savebar-hint')

  let residents: ResidentContext[] = []
  /** 村民 → 使用的模型（模型服务表上写谁在用）；还没读到的不在表里 */
  const bindings = new Map<string, ModelChoice | null>()
  let nav: ReturnType<typeof createSettingsNav> | null = null

  // 手机布局里目录与子页分两层：点目录进子页，「返回」先回目录；宽屏两栏并排，这个标记不起作用
  const view = $('settings-view')
  function setPane(pane: 'nav' | 'page') {
    view.dataset.pane = pane
    if (!deps.game)
      $('settings-back').textContent = isCompact() && pane === 'page' ? '← 设定' : '← 返回地图'
  }
  function openPage(id: string) {
    showPage(id)
    setPane('page')
  }

  const pageDeps: PageDeps = {
    send: deps.send,
    save: deps.save,
    onDirty: refreshDirty,
    showPage: openPage,
    game: deps.game,
    openUsage: deps.openUsage,
  }
  const providers = createProviderListPage({
    ...pageDeps,
    usersOf: (providerId) =>
      residents.filter((r) => bindings.get(r.id)?.provider === providerId).map((r) => r.name),
    onConfigured: (count, total) => nav?.setBadge('providers', `${count} / ${total}`),
  })
  const pages: SettingsPage[] = [
    providers,
    createModelPage(pageDeps),
    createLimitsPage(pageDeps, deps.townPrice),
    createSoundPage(deps.game, deps.audio),
    createDisplayPage(deps.map, deps.game),
  ]
  const inGroup = (group: SettingsPage['group']) => pages.filter((p) => p.group === group)
  nav = createSettingsNav(
    $('settings-nav'),
    { model: inGroup('model'), game: inGroup('game') },
    openPage
  )
  providers.render()

  let currentId = pages[0].id
  const pageOf = (id: string) => pages.find((p) => p.id === id)
  const visible = () => !$('settings-view').hidden

  /** 进设定时读一遍各村民的模型绑定，模型服务表上要写谁在用 */
  function requestBindings() {
    for (const r of residents)
      if (!bindings.has(r.id)) deps.send({ type: 'get_agent_config', resident: r.id })
  }

  function showPage(id: string) {
    // 别的页上「去配置此服务」：跳到模型服务页并点开那一行
    if (id.startsWith('prov-')) {
      providers.expand(id.slice('prov-'.length))
      id = providers.id
    }
    const p = pageOf(id)
    if (!p) return
    currentId = p.id
    // 子页 DOM 常驻，切换不销毁：未保存的编辑不会因换页被静默丢弃
    pageBox.replaceChildren(p.el)
    pageBox.scrollTop = 0
    nav?.mark(p.id)
    p.onShow?.()
    refreshDirty()
  }

  const dirtyPages = () => pages.filter((p) => p.isDirty())

  function refreshDirty() {
    const dirty = dirtyPages()
    savebar.hidden = dirty.length === 0
    const what = dirty
      .map((p) => p.dirtySummary?.() || p.title)
      .filter(Boolean)
      .join('；')
    savebarHint.textContent = what ? `有未保存的修改：${what}` : '有未保存的修改'
    nav?.setDirty(new Set(dirty.map((p) => p.id)))
  }

  $('settings-back').onclick = () => {
    if (isCompact() && view.dataset.pane === 'page') setPane('nav')
    else deps.onBack()
  }
  if (deps.game) iconLabel($('settings-back'), 'close', '关闭')
  $('settings-save').onclick = () => {
    for (const p of dirtyPages()) p.save()
  }
  $('settings-discard').onclick = () => {
    for (const p of dirtyPages()) p.discard()
    refreshDirty()
  }

  showPage(currentId)

  return {
    /** 人口登记变化：模型服务表上「谁在用」只算还在村里的人 */
    setResidents(list: { id: string; name: string }[]) {
      residents = list.map((r) => ({ id: r.id, name: r.name }))
      const present = new Set(residents.map((r) => r.id))
      for (const id of bindings.keys()) if (!present.has(id)) bindings.delete(id)
      providers.render()
      if (visible()) requestBindings()
    },
    showPage,
    refreshDirty,
    enter(pageId?: string) {
      requestBindings()
      showPage(pageId ?? currentId)
      // 从别处直接打开某页（花费上限、模型服务）就停在那一页，从「设定」进来先看目录
      setPane(pageId ? 'page' : 'nav')
    },
    isDirty: () => dirtyPages().length > 0,
    discardAll() {
      for (const p of dirtyPages()) p.discard()
      refreshDirty()
    },
    disconnected() {
      for (const p of pages) p.onDisconnected?.()
    },
    /** 名册也广播给各子页（调参页显示当前值） */
    roster({ msg }: RosterFrame) {
      for (const p of pages) p.handleMsg?.(msg)
    },
    /** 配置类消息广播给所有子页（保存回执由连接按请求编号直接交给发起的子页） */
    handleMsg(msg: ServerMsg) {
      if (msg.type === 'agent_config') {
        bindings.set(msg.resident_id, msg.model_binding ?? null)
        providers.render()
      }
      for (const p of pages) p.handleMsg?.(msg)
    },
  }
}
