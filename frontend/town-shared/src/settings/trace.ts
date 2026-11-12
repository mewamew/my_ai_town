import type { AgentTraceState, ServerMsg } from '../protocol'
import type { SettingsPage } from '../settingsCenter'
import { el, statusLine } from '../dom'
import { fileSize } from '../format'
import type { PageDeps } from './page'
import { settingRow, switchControl } from './controls'
import './trace.css'

// 日志：村民和模型之间每一次往来的轨迹（crates/host/src/agent_trace.rs）。「记下完整题面」跟着这台设备，
// 存在用户目录 config/ 的 preferences.json 里，所有小镇都按它记；切换就保存、马上生效，不进保存栏。
// 日志按小镇放在小镇目录的 logs/ 里，下面写的是这个小镇的用量，进这一页时读一次。

const mb = (bytes: number) => `${Math.round(bytes / 1024 / 1024)} MB`

export function createTracePage(deps: PageDeps): SettingsPage {
  const root = el('section', '', 'spage trace-page')
  root.append(
    el('h2', '日志'),
    el(
      'p',
      '村民每次想事情、模型怎么回、动作做成没有，都按先后记在日志里，复盘和查问题时用。',
      'hint'
    )
  )
  let state: AgentTraceState | null = null
  let saving = false
  const status = el('p', '', 'page-status')
  status.setAttribute('role', 'status')
  const setStatus = statusLine(status)
  const full = switchControl('记下完整题面', (on) => {
    saving = true
    render()
    setStatus('保存中…')
    deps.save({ type: 'set_agent_trace', full_prompts: on }, (ok, message) => {
      saving = false
      // 回执先到，随后广播的 agent_trace 再带上用量；失败时开关退回原样
      if (ok && state) state = { ...state, full_prompts: on }
      setStatus((ok ? '✓ ' : '✗ ') + message, ok ? 'ok' : 'drop')
      render()
    })
  })
  const rows = el('div', '', 'set-rows')
  rows.append(
    settingRow(
      '记下完整题面',
      '每次发给模型的整份题面和工具表都记下来，能看到村民当时看到的全部内容；日志会大六七倍。关着时只记每轮新给的那段',
      full.el
    )
  )
  const usage = el('p', '', 'hint')
  const dir = el('code', '', 'trace-dir')
  root.append(
    rows,
    status,
    el('h3', '这个小镇的日志', 'section-caption'),
    usage,
    dir,
    el(
      'p',
      '开关跟着这台设备，所有小镇都按它记。3 个村民玩一小时，开着大约 50 MB，关着大约 8 MB。',
      'hint'
    )
  )

  function render() {
    full.set(!!state?.full_prompts)
    full.el.disabled = !state || saving
    if (!state) {
      usage.textContent = '正在读取…'
      dir.hidden = true
      return
    }
    const now = state.files
      ? `现在 ${state.files} 份，共 ${fileSize(state.bytes)}`
      : '还没有记下什么'
    usage.textContent = `${now}。每份写到 ${mb(state.file_bytes)} 换下一份，每个小镇最多留 ${mb(state.keep_bytes)}，超了先删最早的。`
    dir.textContent = state.dir
    dir.hidden = false
  }
  render()

  return {
    id: 'trace',
    group: 'game',
    navLabel: '日志',
    title: '日志',
    el: root,
    isDirty: () => false,
    save: () => {},
    discard: () => {},
    onShow() {
      deps.send({ type: 'get_agent_trace' })
    },
    onDisconnected() {
      saving = false
      render()
    },
    handleMsg(msg: ServerMsg) {
      if (msg.type !== 'agent_trace') return
      state = msg.state
      render()
    },
  }
}
