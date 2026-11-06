import type { ResidentContext } from './application'
import type { ClientMsg, ModelChoice, ServerMsg } from './protocol'
import type { GameMap } from './gameMap'
// 设定中心外壳：左侧目录分小镇 / 村民 / 模型 / 游戏四组，最底下单独的「重置世界…」；
// 底部保存栏只在有未保存修改时出现。进入时暂停与返回后恢复速度由游戏页外壳负责；
// 这里管页面切换、村民组当前编辑的村民、脏状态与保存分发。

import type { PageDeps, ResidentPageDeps } from './settings/page'
import { createModelPage } from './settings/model'
import { createLookPage } from './settings/look'
import { createPersonaPage } from './settings/persona'
import { createResidentModelPage } from './settings/residentModel'
import { createProviderListPage } from './settings/providerList'
import { createSoundPage } from './settings/sound'
import { createDisplayPage } from './settings/display'
import { createLimitsPage } from './settings/limits'
import { createResetPage } from './settings/reset'
import { createPhysiologyPage } from './settings/physiology'
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
  group: 'town' | 'resident' | 'model' | 'game' | 'danger'
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
  worldSettings: import('./worldSettings').WorldSettingsController
  send: (obj: ClientMsg) => void
  onBack: () => void
  save: (command: SaveCommand, receipt: Receipt) => void
  /** 当前小镇名：重置世界要输入它确认 */
  townName: string
  /** 地图上选中的村民：进设定时村民组默认编辑他 */
  selectedResident: () => ResidentContext | null
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

/** 村民子页的编号是「基础编号:村民编号」，目录只认基础编号 */
const baseOf = (id: string) => id.split(':')[0]

export function initSettingsCenter(deps: CenterDeps) {
  const pageBox = $('settings-page')
  const savebar = $('settings-savebar')
  const savebarHint = $('settings-savebar-hint')

  let residents: ResidentContext[] = []
  /** 村民组正在编辑的村民 */
  let current: ResidentContext | null = null
  /** 村民 → 使用的模型；还没读到的不在表里 */
  const bindings = new Map<string, ModelChoice | null>()
  /** 各村民的子页，首次需要时才建；离村后删掉 */
  const residentPages = new Map<string, SettingsPage[]>()
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

  const pages: SettingsPage[] = []
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
  pages.push(
    deps.worldSettings.page(refreshDirty),
    createPhysiologyPage(deps.worldSettings, refreshDirty),
    providers,
    createModelPage(pageDeps),
    createLimitsPage(pageDeps, deps.townPrice),
    createSoundPage(deps.game, deps.audio),
    createDisplayPage(deps.map, deps.game),
    createResetPage(pageDeps, deps.townName)
  )
  const inGroup = (group: SettingsPage['group']) => pages.filter((p) => p.group === group)
  nav = createSettingsNav(
    $('settings-nav'),
    {
      town: inGroup('town'),
      model: inGroup('model'),
      game: inGroup('game'),
      danger: inGroup('danger'),
    },
    { show: openPage, pickResident },
    deps.game
  )
  providers.render()

  let currentId = pages[0].id
  const pageOf = (id: string) => pages.find((p) => p.id === id)
  const visible = () => !$('settings-view').hidden

  function ensurePages(resident: ResidentContext) {
    if (residentPages.has(resident.id)) return
    const childDeps: ResidentPageDeps = {
      ...pageDeps,
      resident,
      // 保存成功后重读这位村民的设定：目录上的「未选」和模型服务表里的「在用」跟着更新
      save: (command, receipt) =>
        deps.save(command, (ok, message) => {
          receipt(ok, message)
          if (ok) deps.send({ type: 'get_agent_config', resident: resident.id })
        }),
    }
    const list = [
      createPersonaPage(childDeps),
      createLookPage(childDeps),
      createResidentModelPage(childDeps),
    ]
    nav?.setResidentItems(list)
    for (const page of list) page.id = `${page.id}:${resident.id}`
    residentPages.set(resident.id, list)
    pages.push(...list)
  }

  function syncResidentNav() {
    if (current) ensurePages(current) // 村民组的目录项随第一位村民的子页一起登记
    const list =
      current && !residents.some((r) => r.id === current?.id) ? [...residents, current] : residents
    nav?.setResidents(list, current)
    const binding = current ? bindings.get(current.id) : undefined
    nav?.setBadge('resident-model', binding === null ? '未选' : '', true)
  }

  /** 进设定时读一遍各村民的模型绑定，目录和模型服务表要用 */
  function requestBindings() {
    for (const r of residents)
      if (!bindings.has(r.id)) deps.send({ type: 'get_agent_config', resident: r.id })
  }

  function pickResident(id: string) {
    const r = residents.find((item) => item.id === id)
    if (!r) return
    current = r
    syncResidentNav()
    const page = pageOf(currentId)
    if (page?.group === 'resident') showPage(baseOf(currentId))
    else refreshDirty()
  }

  function showPage(id: string) {
    // 别的页上「去配置此服务」：跳到模型服务页并点开那一行
    if (id.startsWith('prov-')) {
      providers.expand(id.slice('prov-'.length))
      id = providers.id
    }
    let p = pageOf(id)
    if (!p && current) {
      ensurePages(current)
      p = pageOf(`${id}:${current.id}`)
    }
    if (!p) return
    if (p.group === 'resident') {
      const owner = [...residentPages].find(([, list]) => list.includes(p))?.[0]
      const r = residents.find((item) => item.id === owner)
      if (r && r.id !== current?.id) {
        current = r
        syncResidentNav()
      }
    }
    currentId = p.id
    // 子页 DOM 常驻，切换不销毁：未保存的编辑不会因换页被静默丢弃
    pageBox.replaceChildren(p.el)
    pageBox.scrollTop = 0
    nav?.mark(baseOf(p.id))
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
    // 目录上的圆点：村民子页只标当前村民的
    nav?.setDirty(
      new Set(
        dirty
          .filter((p) => p.group !== 'resident' || p.id.endsWith(`:${current?.id}`))
          .map((p) => baseOf(p.id))
      )
    )
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
    /** 从地图或村民页点「编辑」：村民组切到这位村民，打开他的使用模型页 */
    ensureResident(resident: ResidentContext) {
      current = resident
      syncResidentNav()
      return `resident-model:${resident.id}`
    },
    /** 人口登记变化：不在村里的村民，子页一并删掉；村民组换到还在的人 */
    setResidents(list: { id: string; name: string }[]) {
      residents = list.map((r) => ({ id: r.id, name: r.name }))
      const present = new Set(residents.map((r) => r.id))
      let removedCurrent = false
      for (const [id, group] of residentPages) {
        if (present.has(id)) continue
        residentPages.delete(id)
        bindings.delete(id)
        for (const page of group) {
          page.el.remove()
          const index = pages.indexOf(page)
          if (index >= 0) pages.splice(index, 1)
          if (page.id === currentId) removedCurrent = true
        }
      }
      if (current && !present.has(current.id)) current = null
      if (!current) {
        const selected = deps.selectedResident()
        current = residents.find((r) => r.id === selected?.id) ?? residents[0] ?? null
      }
      syncResidentNav()
      providers.render()
      if (visible()) requestBindings()
      if (removedCurrent) showPage(pages[0].id)
      else refreshDirty()
    },
    showPage,
    refreshDirty,
    enter(pageId?: string) {
      if (!pageId) {
        const selected = deps.selectedResident()
        const r = residents.find((item) => item.id === selected?.id)
        if (r) current = r
      }
      syncResidentNav()
      requestBindings()
      // 上次停在某位村民的子页时，换成当前村民的同一页
      showPage(pageId ?? baseOf(currentId))
      // 从别处直接打开某页（编辑村民、世界观）就停在那一页，从「设定」进来先看目录
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
        syncResidentNav()
        providers.render()
      }
      for (const p of pages) p.handleMsg?.(msg)
    },
  }
}
