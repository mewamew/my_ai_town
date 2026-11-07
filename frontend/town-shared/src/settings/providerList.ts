import type { ActiveModelChoice, ProviderView, ServerMsg } from '../protocol'
import { BUILTIN, PRESETS, needsKey, type ProviderPreset } from '../providers'
import type { SettingsPage } from '../settingsCenter'
import { button, el, statusLine } from '../dom'
import { createProviderForm, type ProviderForm } from './provider'
import {
  builtinStatus,
  builtinView,
  onBuiltin,
  onBuiltinInstalled,
  refreshBuiltin,
} from '../models/builtin'
import { createBuiltinRows } from '../models/builtinRows'
import { providerSaveCommand, type ProviderEdit } from './providerCommands'
import type { PageDeps } from './page'

// 「模型服务」页：所有服务商一张表，每行服务名、状态、哪些村民在用、「填写 / 收起」。
// 点开一行在行下显示该服务商的编辑表单；保存时把各行的修改合成一条 set_model_config。
// 内置模型排在最前面，点开是下载和更新的几行（models/builtinRows.ts），不用填什么。

/** 表上直接列出的常用服务商数，其余收在「展开」后面 */
const COMMON = 7

type ProviderStatus = 'ok' | 'no' | 'local'

/** 已配置：填过密钥；本机服务（包括地址填在本机或局域网的）不用密钥 */
function providerStatus(preset: ProviderPreset, conf: ProviderView | undefined): ProviderStatus {
  if (!needsKey(preset, conf?.base_url)) return 'local'
  return conf?.key_mask ? 'ok' : 'no'
}

const STATUS_TEXT: Record<ProviderStatus, string> = {
  ok: '已配置',
  no: '未配置',
  local: '本机 · 不用密钥',
}

interface ProviderListDeps extends PageDeps {
  /** 用这个服务商的村民名字；还不知道时给空表 */
  usersOf(providerId: string): string[]
  /** 已配置数变了：目录上的「n / 13」跟着改 */
  onConfigured(count: number, total: number): void
}

export function createProviderListPage(deps: ProviderListDeps) {
  const page = document.createElement('section')
  page.className = 'spage provider-list-page'
  page.append(
    el('h2', '模型服务'),
    el(
      'p',
      '填好服务地址和密钥的服务，才能在「默认模型」和角色卡的「模型」里选。保存后所有村民都能用。',
      'hint'
    )
  )
  const table = el('div', '', 'prov-table')
  const status = el('div', '', 'page-status')
  status.setAttribute('role', 'status')
  page.append(table, status)

  let providers: ProviderView[] = []
  let active: ActiveModelChoice | null = null
  let showAll = false
  const open = new Set<string>()

  const rows = PRESETS.filter((preset) => preset.id !== BUILTIN).map((preset) => {
    const form = createProviderForm(preset, deps)
    const row = el('div', '', 'prov-row')
    const name = el('b', preset.name, 'prov-name')
    const state = el('span', '', 'prov-state')
    const users = el('span', '', 'prov-users')
    const toggle = button(
      '填写',
      () => {
        if (!open.delete(preset.id)) open.add(preset.id)
        render()
      },
      'prov-toggle'
    )
    row.append(name, state, users, toggle)
    return { preset, form, row, state, users, toggle }
  })
  const more = el('div', '', 'prov-row prov-more')
  const moreText = el('span', '', 'prov-more-text')
  const moreBtn = button(
    '展开',
    () => {
      showAll = true
      render()
    },
    'prov-toggle'
  )
  more.append(moreText, moreBtn)

  // 内置模型不用填，应用带着它时单独一行排在最前面；点开是下载和更新
  const builtinUsers = el('span', '', 'prov-users')
  const builtinState = el('span', '', 'prov-state')
  const builtinRow = el('div', '', 'prov-row')
  const builtinToggle = button(
    '详情',
    () => {
      builtinOpen = !builtinOpen
      render()
    },
    'prov-toggle'
  )
  builtinRow.append(el('b', '内置模型', 'prov-name'), builtinState, builtinUsers, builtinToggle)
  /** 推理服务还在用小镇开着时换下来的旧模型，见 builtin_stale */
  let stale = false
  let restarting = false
  const builtinRows = createBuiltinRows({
    users: () => deps.usersOf(BUILTIN),
    swap: () =>
      stale
        ? {
            restarting,
            restart: () => {
              restarting = true
              builtinRows.render()
              deps.save({ type: 'restart_builtin_model' }, (ok, message) => {
                restarting = false
                if (ok) stale = false
                else setStatus('✗ ' + message, 'drop')
                render()
              })
            },
          }
        : null,
  })
  const builtinPanel = el('div', '', 'prov-form builtin-panel')
  builtinPanel.append(builtinRows.el)
  /** null：还没决定；第一次读到状态时，有要处理的事（没下载、在下载、有新版本）就展开 */
  let builtinOpen: boolean | null = null
  // 小镇开着时下好了新版：问一下推理服务是不是还在用旧的
  onBuiltinInstalled(() => deps.send({ type: 'get_model_config' }))
  onBuiltin(() => {
    if (page.isConnected) render()
  })

  const confOf = (id: string) => providers.find((p) => p.id === id)

  function usersText(id: string) {
    const names = deps.usersOf(id)
    if (names.length === 0) return ''
    if (names.length <= 2) return `${names.join('、')}在用`
    return `${names.slice(0, 2).join('、')}等 ${names.length} 人在用`
  }

  function render() {
    const nodes: HTMLElement[] = []
    const view = builtinView(stale ? { restart: () => {}, restarting } : undefined)
    if (confOf(BUILTIN) && view) {
      const s = builtinStatus()
      builtinOpen ??= !s?.installed || !!s.download || s.update || stale
      builtinUsers.textContent = usersText(BUILTIN)
      builtinState.textContent = view.chip.text
      builtinState.className = `prov-state ${view.chip.tone || 'no'}`
      builtinToggle.textContent = builtinOpen ? '收起' : '详情'
      builtinRow.classList.toggle('open', builtinOpen)
      nodes.push(builtinRow)
      if (builtinOpen) {
        builtinRows.render()
        nodes.push(builtinPanel)
      }
    }
    // 排在后面的服务商只要有一个已存配置、正在改或被点开，就整表展开
    const extraInUse = rows
      .slice(COMMON)
      .some((r) => confOf(r.preset.id) || r.form.isDirty() || open.has(r.preset.id))
    const all = showAll || extraInUse
    for (const [index, r] of rows.entries()) {
      if (!all && index >= COMMON) continue
      const s = providerStatus(r.preset, confOf(r.preset.id))
      r.state.textContent = STATUS_TEXT[s]
      r.state.className = `prov-state ${s}`
      r.users.textContent = usersText(r.preset.id)
      const expanded = open.has(r.preset.id)
      r.toggle.textContent = expanded ? '收起' : s === 'ok' ? '修改' : '填写'
      r.row.classList.toggle('open', expanded)
      nodes.push(r.row)
      if (expanded) nodes.push(r.form.el)
    }
    if (!all) {
      const rest = rows.slice(COMMON).map((r) => r.preset.name)
      moreText.textContent = `还有 ${rest.length} 个：${rest.join('、')}`
      nodes.push(more)
    }
    table.replaceChildren(...nodes)
    const count = rows.filter((r) => providerStatus(r.preset, confOf(r.preset.id)) === 'ok').length
    deps.onConfigured(count, rows.length)
  }

  const setStatus = statusLine(status)

  const dirtyRows = () => rows.filter((r) => r.form.isDirty())

  const result: SettingsPage & { expand(providerId: string): void; render(): void } = {
    id: 'providers',
    group: 'model',
    navLabel: '模型服务',
    title: '模型服务',
    el: page,
    isDirty: () => dirtyRows().length > 0,
    dirtySummary: () =>
      dirtyRows()
        .map((r) => `${r.preset.name}的${r.form.changes().join('、')}`)
        .join('；'),
    save() {
      const edits: ProviderEdit[] = []
      for (const r of dirtyRows()) {
        const draft = r.form.draft()
        if (typeof draft === 'string') {
          open.add(r.preset.id)
          render()
          setStatus('✗ ' + draft, 'drop')
          return
        }
        edits.push(draft)
      }
      if (edits.length === 0) return
      const saving = dirtyRows()
      // 先写「保存中…」：没连上时回执立刻回来，结果不能被它盖掉
      setStatus('保存中…')
      deps.save(providerSaveCommand(active, providers, edits), (ok, message) => {
        if (ok) {
          for (const r of saving) r.form.saved()
          deps.onDirty()
          setStatus('✓ 已保存', 'ok')
        } else setStatus('✗ ' + message, 'drop')
      })
    },
    discard() {
      for (const r of dirtyRows()) r.form.discard()
      setStatus('')
      render()
      deps.onDirty()
    },
    onShow() {
      setStatus('')
      render()
      void refreshBuiltin()
    },
    onDisconnected() {
      for (const r of rows) r.form.disconnected()
    },
    handleMsg(msg: ServerMsg) {
      for (const r of rows) r.form.handleMsg(msg)
      if (msg.type === 'model_config') {
        providers = msg.providers
        active = msg.active
        stale = msg.builtin_stale
        render()
      }
    },
    /** 从别的页跳过来：点开这个服务商的那一行 */
    expand(providerId: string) {
      if (rows.some((r) => r.preset.id === providerId)) open.add(providerId)
      render()
    },
    render,
  }
  render()
  return result
}
