import type { ClientMsg, ServerMsg } from '../protocol'
import { el } from '../dom'
import { newId } from '../ids'

// 世界观面板最底下的重置世界：平时收着，展开后输入当前小镇名按钮才可点。
// 重置成功后外壳会收到 world_reset，面板随之关上，开局向导接手。
export function createResetSection(send: (msg: ClientMsg) => void, townName: string) {
  const root = el('details', '', 'town-section town-reset')
  const summary = el('summary', '重置世界…')
  const input = el('input', '', 'reset-input')
  input.type = 'text'
  input.autocomplete = 'off'
  input.spellcheck = false
  input.placeholder = townName
  input.setAttribute('aria-label', '输入小镇名确认')
  const btn = el('button', '重置世界', 'reset-btn')
  btn.type = 'button'
  btn.disabled = true
  const status = el('p', '', 'town-status')
  status.setAttribute('role', 'status')
  const confirmText = el('p', '', 'reset-zone-text')
  confirmText.append(el('b', '这一步不能撤销。'), el('br'), `输入小镇名「${townName}」后才能点。`)
  const zone = el('div', '', 'reset-zone')
  zone.append(confirmText, input, btn)
  root.append(
    summary,
    el(
      'p',
      '会清空：所有村民，以及他们的行动、目标、记忆、对话和用量。时间回到第 1 天 07:00，世界保持暂停。',
      'town-hint'
    ),
    el(
      'p',
      '会保留：模型服务和密钥 · 花费上限 · 地图 · 村民库里的人物（重置后可以再邀请回来）',
      'town-hint'
    ),
    zone,
    status
  )

  /** 已发出、还没有结果的重置请求编号 */
  let pending: string | null = null
  input.oninput = () => {
    btn.disabled = input.value.trim() !== townName
  }
  btn.onclick = () => {
    if (input.value.trim() !== townName) return
    input.value = ''
    btn.disabled = true
    status.textContent = '已发送重置'
    pending = newId()
    send({ type: 'reset_world', request_id: pending })
  }

  return {
    el: root,
    /** 面板开合时清掉输入，收起这一块 */
    clear() {
      input.value = ''
      btn.disabled = true
      if (pending === null) status.textContent = ''
      root.open = false
    },
    /** 世界重置了：这次请求有了结果 */
    reset() {
      pending = null
      status.textContent = ''
    },
    disconnected() {
      if (pending === null) return
      pending = null
      status.textContent = '连接断开，没有收到重置结果；重新连接后请查看世界是否已回到第一天'
    },
    /** 重置命令没能执行时回的是通用错误；认领了返回 true */
    handleMsg(msg: ServerMsg) {
      if (pending === null || msg.type !== 'error' || msg.request_id !== pending) return false
      pending = null
      status.textContent = `✗ ${msg.message}`
      return true
    },
  }
}
