// 菜单里的「帮助」：重看开局向导、重新显示新手提示，电脑上还有按键说明。点了换掉菜单里的格子，「← 菜单」回去。
import { button, el } from '../dom'
import { isCompact } from '../platform'

const KEYS: [string, string][] = [
  ['空格', '开始 / 暂停'],
  ['Esc', '关掉打开的面板；什么都没开时打开菜单'],
  ['1 – 9', '跳到头像条上对应的村民，打开角色卡'],
  ['拖动地图 · 滚轮', '移动镜头 · 缩放'],
  ['右键上下拖动，或右下角的滑杆', '调整俯角'],
  ['W A S D，或点地面', '化身走路'],
  ['E', '和身边提示的人或东西互动'],
  ['Tab', '换一个互动对象'],
  ['B', '打开背包'],
  ['F', '对身边的人施展神力（先点左上角的「世界观」，在规则里打开化身神力）'],
]

export function createMenuHelp(
  box: HTMLElement,
  actions: { openGuide: () => void; resetTips: () => void },
  nav: {
    /** 回到菜单的格子 */
    back: () => void
    /** 关掉菜单（点了向导、提示之后） */
    close: () => void
  }
) {
  const backTo = (label: string, run: () => void) => {
    const b = button(label, run, 'menu-back')
    return b
  }
  const item = (label: string, run: () => void) =>
    button(label, () => {
      nav.close()
      run()
    })
  function list() {
    box.replaceChildren(
      backTo('← 菜单', nav.back),
      item('重新看开局向导', actions.openGuide),
      item('重新显示新手提示', actions.resetTips),
      // 手机没有键盘，不列按键
      ...(isCompact() ? [] : [button('按键说明', keys)])
    )
    box.querySelector<HTMLButtonElement>('button:nth-child(2)')?.focus()
  }
  function keys() {
    const dl = el('dl')
    for (const [key, what] of KEYS) dl.append(el('dt', key), el('dd', what))
    box.replaceChildren(backTo('← 帮助', list), dl)
    box.querySelector<HTMLButtonElement>('button')?.focus()
  }
  return { show: list }
}
