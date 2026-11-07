// 和小镇断开时地图上方的提示：正在重新连接 → 正在从存档重新打开 → 已重新连上（几秒后收起）。
// 时钟牌下的连接提示写同样的话；断开期间 <html data-offline>，「世界已暂停」那条先不出。
import { $, button, el } from '../dom'

/** 「已重新连上」留多久（毫秒） */
const BACK_SHOWN = 3000

export function createReconnectHint(map: HTMLElement) {
  const hint = document.createElement('div')
  hint.className = 'pause-hint reconnect-hint'
  hint.setAttribute('role', 'status')
  hint.hidden = true
  map.append(hint)
  let timer = 0
  let reopened = false
  function say(text: string, status: string) {
    window.clearTimeout(timer)
    hint.textContent = text
    hint.hidden = false
    $('conn-text').textContent = status
  }
  return {
    lost() {
      reopened = false
      document.documentElement.toggleAttribute('data-offline', true)
      say('小镇的连接断了，正在重新连接…', '正在重新连接…')
    },
    reopening() {
      reopened = true
      say('小镇的连接断了，正在从存档重新打开…', '正在重新打开小镇…')
    },
    back() {
      document.documentElement.toggleAttribute('data-offline', false)
      say(reopened ? '已重新连上小镇，世界从刚才的存档接着来' : '已重新连上小镇', '')
      timer = window.setTimeout(() => (hint.hidden = true), BACK_SHOWN)
    },
    /** 另一个页面进了别的小镇，这里先停了：说清原因，回不回来由玩家决定 */
    displaced(message: string, comeBack: () => Promise<void>) {
      window.clearTimeout(timer)
      hint.hidden = true
      $('conn-text').textContent = '已停下'
      const card = el('div', '', 'displaced-card')
      card.setAttribute('role', 'alertdialog')
      // 卡片上的按下不能漏给地图，否则会被当成拖动的起点，按钮点不动
      for (const type of ['pointerdown', 'dblclick', 'wheel'])
        card.addEventListener(type, (e) => e.stopPropagation())
      const status = el('p', '', 'dim')
      const back = button(
        '回到这个小镇',
        () => {
          back.disabled = true
          status.textContent = '正在打开…'
          comeBack().then(
            () => card.remove(),
            (error: Error) => {
              back.disabled = false
              status.textContent = error.message
            }
          )
        },
        'primary'
      )
      const home = button('选择小镇', () => location.assign('./'))
      const actions = el('div', '', 'displaced-actions')
      actions.append(back, home)
      card.append(
        el('b', '这个小镇先停了'),
        el('p', `${message}。回到这里会把那边的小镇存好关掉。`),
        actions,
        status
      )
      // 挂在页面最上层：开局向导开着时也看得到；模态对话框在最顶层，先收起来
      for (const dialog of document.querySelectorAll<HTMLDialogElement>('dialog[open]'))
        dialog.close()
      document.body.append(card)
    },
  }
}
