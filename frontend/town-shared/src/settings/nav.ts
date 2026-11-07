import type { ResidentContext } from '../application'
import { button, el } from '../dom'
import { residentPortrait, residentPortraitUrl } from '../portraits'

// 设定中心左侧目录：村民 / 模型 / 游戏三组。
// 村民组顶部是换人框，下面几项指向当前选中村民的子页；目录项按页的基础编号（不带村民编号）登记。

interface NavItem {
  id: string
  navLabel: string
}

interface NavSections {
  model: NavItem[]
  game: NavItem[]
}

/** 头像优先使用像素头像，没有时用名字第一个字 */
function residentFace(r: ResidentContext, game: boolean): HTMLElement {
  const box = el('span', '', 'settings-face')
  const url = residentPortraitUrl(r.id)
  if (url) {
    const img = el('img')
    img.src = url
    img.alt = ''
    box.append(img)
    return box
  }
  if (game) {
    const frame = residentPortrait(r.id, r.name)
    if (!frame.querySelector('img')?.hidden) {
      box.append(frame)
      return box
    }
  }
  box.textContent = [...r.name][0] ?? ''
  box.classList.add('initial')
  return box
}

export function createSettingsNav(
  root: HTMLElement,
  sections: NavSections,
  handlers: { show(id: string): void; pickResident(id: string): void },
  /** 游戏界面用模型头像 */
  game: boolean
) {
  const buttons = new Map<string, HTMLButtonElement>()
  const badges = new Map<string, HTMLElement>()

  function item(p: NavItem, className = 'nav-item') {
    const id = p.id // 村民子页登记后会改名带上村民编号，目录只认登记时的基础编号
    const b = button('', () => handlers.show(id), className)
    b.dataset.page = id
    const badge = el('span', '', 'nav-badge')
    b.append(el('span', p.navLabel, 'nav-label'), badge)
    buttons.set(id, b)
    badges.set(id, badge)
    return b
  }
  const group = (label: string) => el('div', label, 'nav-group section-caption')

  // 村民组：换人框（details 自带展开收起）+ 空村提示 + 子页各项
  const picker = el('details', '', 'settings-resident-picker')
  const pickerHead = el('summary')
  const pickerMenu = el('div', '', 'settings-resident-menu')
  picker.append(pickerHead, pickerMenu)
  const empty = el('p', '还没有村民', 'settings-no-resident')
  const residentItems = el('div', '', 'settings-resident-items')

  root.replaceChildren(
    group('村民'),
    picker,
    empty,
    residentItems,
    group('模型'),
    ...sections.model.map((p) => item(p)),
    group('游戏'),
    ...sections.game.map((p) => item(p))
  )

  return {
    /** 第一次建村民子页时登记目录项（所有村民共用这几项） */
    setResidentItems(items: NavItem[]) {
      if (residentItems.childElementCount === 0) residentItems.append(...items.map((p) => item(p)))
    },
    setResidents(list: ResidentContext[], current: ResidentContext | null) {
      empty.hidden = list.length > 0
      picker.hidden = !current
      residentItems.hidden = !current
      picker.open = false
      if (!current) return
      pickerHead.replaceChildren(
        residentFace(current, game),
        el('span', current.name, 'settings-resident-name'),
        el('span', list.length > 1 ? '换人 ▾' : '', 'settings-resident-switch')
      )
      pickerMenu.replaceChildren(
        ...list.map((r) => {
          const b = button(
            '',
            () => {
              picker.open = false
              handlers.pickResident(r.id)
            },
            r.id === current.id ? 'on' : ''
          )
          b.append(residentFace(r, game), el('span', r.name))
          return b
        })
      )
    },
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
