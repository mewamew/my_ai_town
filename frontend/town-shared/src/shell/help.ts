// 顶栏的「帮助」（电脑布局）：重看开局向导、重新显示新手提示、按键说明。手机上这几项在「更多」里。
import { $, button, el } from '../dom'
import { lineLabel } from '../game/icons'

const KEYS: [string, string][] = [
  ['空格', '开始 / 暂停'],
  ['1 – 9', '跳到头像条上对应的村民，打开角色卡'],
  ['拖动地图 · 滚轮', '移动镜头 · 缩放'],
  ['右键上下拖动，或右下角的滑杆', '调整俯角'],
  ['W A S D，或点地面', '化身走路'],
  ['E', '和身边提示的人或东西互动'],
  ['Tab', '换一个互动对象'],
  ['B', '打开背包'],
  ['F', '对身边的人施展神力（设定里打开化身神力后）'],
  ['Esc', '关掉打开的面板'],
]

export function installHelpMenu(actions: { openGuide: () => void; resetTips: () => void }) {
  const open = $('open-help')
  lineLabel(open, 'help', '帮助')
  const menu = el('div', '', 'help-menu')
  menu.hidden = true
  menu.setAttribute('role', 'menu')
  document.body.append(menu)

  function close() {
    menu.hidden = true
    open.setAttribute('aria-expanded', 'false')
  }
  function place() {
    const r = open.getBoundingClientRect()
    menu.style.top = `${r.bottom + 6}px`
    menu.style.right = `${Math.max(8, innerWidth - r.right)}px`
  }
  function item(label: string, run: () => void) {
    const b = button(label, () => {
      close()
      run()
    })
    b.setAttribute('role', 'menuitem')
    return b
  }
  function showMenu() {
    menu.className = 'help-menu'
    menu.replaceChildren(
      item('重新看开局向导', actions.openGuide),
      item('重新显示新手提示', actions.resetTips),
      button('按键说明', showKeys)
    )
    place()
    menu.hidden = false
    open.setAttribute('aria-expanded', 'true')
  }
  function showKeys() {
    menu.className = 'help-menu help-keys'
    const list = el('dl')
    for (const [key, what] of KEYS) list.append(el('dt', key), el('dd', what))
    menu.replaceChildren(el('b', '按键说明'), list, button('知道了', close))
    place()
  }
  open.setAttribute('aria-haspopup', 'menu')
  open.onclick = () => (menu.hidden ? showMenu() : close())
  // 点别处或按 Esc 收起
  document.addEventListener(
    'pointerdown',
    (e) => {
      if (menu.hidden || !(e.target instanceof Node)) return
      if (!menu.contains(e.target) && !open.contains(e.target)) close()
    },
    true
  )
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !menu.hidden) close()
  })
}
