import type { RosterMember } from '../protocol'
import { el, button } from '../props/dom'
import { propPicture } from '../props/picture'
import './inventory.css'

/** 最多画几格：背包很大时空格子不铺满整张卡 */
const MAX_SLOTS = 24

/** 角色卡的口袋：一格一种东西，画道具的像素图，同类多件在角上写数量；点一格看用途 */
export function createInventoryView(root: HTMLElement, open: (id: string) => void) {
  const count = el('span', '', 'card-count')
  const caption = el('h3', '口袋', 'card-caption')
  caption.append(count)
  const grid = el('div', '', 'bag-grid')
  root.append(caption, grid)
  let previous = ''
  return {
    clear() {
      previous = ''
      count.textContent = ''
      grid.replaceChildren()
    },
    render(value: RosterMember['inventory']) {
      const key = JSON.stringify(value)
      if (key === previous) return
      previous = key
      count.textContent = value ? `${value.used} / ${value.capacity}` : '等待数据'
      grid.replaceChildren()
      if (!value) return
      for (const slot of value.slots) {
        const cell = button('', () => open(slot.items[0]), 'bag-slot')
        cell.append(propPicture(slot.definition ?? '', 'bag'))
        if (slot.quantity > 1) cell.append(el('small', String(slot.quantity)))
        const uses = slot.actions.map((a) => a.label).join('、') || '可携带、赠予或放下'
        cell.title = `${slot.name} ×${slot.quantity} · ${uses}`
        cell.setAttribute('aria-label', `${slot.name}，${slot.quantity} 件，查看用途`)
        grid.append(cell)
      }
      for (let i = value.slots.length; i < Math.min(value.capacity, MAX_SLOTS); i++) {
        const empty = el('span', '', 'bag-slot empty')
        empty.setAttribute('aria-hidden', 'true')
        grid.append(empty)
      }
    },
  }
}
