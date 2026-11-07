import { button, el } from '../dom'

// 设定中心左侧目录：模型 / 游戏两组，只放跟着这台设备的东西。
// 村民的人设、长相、用哪个模型在角色卡页签里；世界观、规则、重置世界在「我的小镇」。

interface NavItem {
  id: string
  navLabel: string
}

interface NavSections {
  model: NavItem[]
  game: NavItem[]
}

export function createSettingsNav(
  root: HTMLElement,
  sections: NavSections,
  show: (id: string) => void
) {
  const buttons = new Map<string, HTMLButtonElement>()
  const badges = new Map<string, HTMLElement>()

  function item(p: NavItem) {
    const b = button('', () => show(p.id), 'nav-item')
    b.dataset.page = p.id
    const badge = el('span', '', 'nav-badge')
    b.append(el('span', p.navLabel, 'nav-label'), badge)
    buttons.set(p.id, b)
    badges.set(p.id, badge)
    return b
  }
  const group = (label: string) => el('div', label, 'nav-group section-caption')

  root.replaceChildren(
    group('模型'),
    ...sections.model.map(item),
    group('游戏'),
    ...sections.game.map(item)
  )

  return {
    mark(id: string) {
      for (const [pid, b] of buttons) b.classList.toggle('on', pid === id)
    },
    setDirty(ids: Set<string>) {
      for (const [pid, b] of buttons) b.classList.toggle('dirty', ids.has(pid))
    },
    setBadge(id: string, text: string, warn = false) {
      const badge = badges.get(id)
      if (!badge) return
      badge.textContent = text
      badge.classList.toggle('warn', warn)
    },
  }
}
