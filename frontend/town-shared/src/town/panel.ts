// 世界观面板：这一局的设定，跟着存档走——世界观、规则（初来乍到、村民生理、化身神力）、重置世界。
// 地图左上角的「世界观」点开（电脑、手机一样），菜单里也有一格。地图留在背后，打开不暂停世界，
// 保存世界观和生理开关时服务端照旧会暂停。跟着这台设备走的模型、声音、显示在菜单的「设定」里。
import { $, button, el } from '../dom'
import { gameIcon } from '../game/icons'
import type { ClientMsg, ServerMsg } from '../protocol'
import type { ShellPanel } from '../shell/panel'
import type { WorldSettingsController } from '../worldSettings'
import { createMiraclesSwitch, createPhysiologySwitches, physiologySummary } from './physiology'
import { createRecordingSection } from './recording'
import { createResetSection } from './reset'
import './panel.css'

export function createTownPanel(deps: {
  world: WorldSettingsController
  send: (msg: ClientMsg) => void
  townName: string
  /** 打开前停下化身：按着的方向键松开（开着对话框时化身本来就不收按键） */
  onOpen: () => void
}) {
  const trigger = $('town-button')
  const dialog = el('dialog', '', 'town-panel')
  dialog.setAttribute('aria-labelledby', 'town-panel-title')
  const title = el('h2', deps.townName)
  title.id = 'town-panel-title'
  const titles = el('div', '', 'town-panel-titles')
  titles.append(title, el('small', '这一局的设定 · 跟着存档走'))
  const close = button('', () => tryClose(), 'town-panel-close')
  close.append(gameIcon('close', true))
  close.setAttribute('aria-label', '关闭')
  const head = el('header', '', 'town-panel-head')
  head.append(titles, close)

  const worldview = deps.world.worldviewSection()
  // 规则：初来乍到、生理、神力一屏看完；生理五项平时收成一行摘要
  const physiology = createPhysiologySwitches(deps.world, { idPrefix: 'town-physiology' })
  const physiologyState = el('span', '', 'town-physiology-state')
  const physiologyHead = el('summary')
  physiologyHead.append(el('b', '村民生理'), physiologyState)
  const physiologyBox = el('details', '', 'town-physiology')
  physiologyBox.append(physiologyHead, physiology.el)
  const rules = el('section', '', 'town-section town-rules')
  rules.append(
    el('h3', '规则'),
    deps.world.strangersSwitch(),
    physiologyBox,
    createMiraclesSwitch(deps.world)
  )
  const recording = createRecordingSection(deps.world)
  const reset = createResetSection(deps.send, deps.townName)
  const body = el('div', '', 'town-panel-body')
  body.append(worldview.el, rules, recording.el, reset.el)
  // 对话框本身没有内边距，内容占满它：点到对话框本身就是点在遮罩上
  const inner = el('div', '', 'town-panel-inner')
  inner.append(head, body)
  dialog.append(inner)
  document.body.append(dialog)

  deps.world.subscribe(() => {
    const switches = deps.world.state()?.physiology
    physiologyState.textContent = switches ? physiologySummary(switches) : ''
  })

  const dirty = () => worldview.isDirty() || physiology.isDirty()

  /** 挂在「世界观」按钮下面、和时钟牌左边对齐；手机上由样式贴底 */
  function place() {
    const r = trigger.getBoundingClientRect()
    if (!r.width) return
    const left = document.getElementById('hud-left')?.getBoundingClientRect().left ?? r.left
    dialog.style.setProperty('--town-left', `${Math.max(8, Math.round(left))}px`)
    dialog.style.setProperty('--town-top', `${Math.round(r.bottom + 6)}px`)
  }
  function open() {
    if (dialog.open) return
    deps.onOpen()
    reset.clear()
    place()
    dialog.showModal()
    trigger.setAttribute('aria-expanded', 'true')
  }
  function discardAll() {
    worldview.discard()
    physiology.discard()
  }
  /** 有没存的修改时先问，确定才丢掉草稿关上 */
  function tryClose() {
    if (
      dirty() &&
      !confirm('世界观或规则里有没保存的修改。\n「确定」放弃修改并关上；「取消」继续编辑。')
    )
      return
    discardAll()
    dialog.close()
  }
  dialog.addEventListener('close', () => {
    trigger.setAttribute('aria-expanded', 'false')
    reset.clear()
  })
  // Esc 和点关闭一样，有草稿先问
  dialog.addEventListener('cancel', (event) => {
    event.preventDefault()
    tryClose()
  })
  // 在遮罩上按下、松开才关；从输入框里拖选文字拖出了面板不算
  let downOnBackdrop = false
  dialog.addEventListener('pointerdown', (event) => {
    downOnBackdrop = event.target === dialog
  })
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog && downOnBackdrop) tryClose()
  })

  trigger.onclick = open

  const panel: ShellPanel = {
    handleMsg: (msg: ServerMsg) => reset.handleMsg(msg),
    disconnected: () => reset.disconnected(),
    // 世界重置：草稿作废、面板关上，开局向导接手
    onReset() {
      reset.reset()
      discardAll()
      if (dialog.open) dialog.close()
    },
    dispose() {
      dialog.remove()
    },
  }
  return { open, isOpen: () => dialog.open, panel }
}
