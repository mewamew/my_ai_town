// 世界观面板的规则里跟身体有关的两块：村民生理五个开关（改完点保存才生效）、化身神力（切换就保存）。
import type { PhysiologySwitches } from '../protocol'
import type { WorldSettingsController } from '../worldSettings'
import { el, button } from '../dom'
import './physiology.css'

type Key = keyof PhysiologySwitches

/** 四项的名字与开关后的含义；规则在内核，这里只描述结果。 */
const PHYSIOLOGY_ITEMS: { key: Key; name: string; on: string; off: string }[] = [
  {
    key: 'fullness',
    name: '饱腹',
    on: '饿了会想吃饭；持续饥饿会损害健康',
    off: '不会饿；吃饭仍可作为普通动作',
  },
  {
    key: 'energy',
    name: '精力',
    on: '累了会想休息；精力过低不能劳作',
    off: '不会累；睡觉仍可作为普通动作',
  },
  {
    key: 'water',
    name: '水分',
    on: '渴了会想喝水；持续缺水会损害健康',
    off: '不会渴；喝水仍可作为普通动作',
  },
  {
    key: 'health',
    name: '健康',
    on: '持续低值、受伤、疾病和中毒会损害健康；归零死亡',
    off: '不受损害、不会死亡；受伤、疾病、中毒不新增也不生效',
  },
  {
    key: 'weather',
    name: '天气影响身体',
    on: '露天淋雨雪额外消耗精力，淋久了会着凉生病；在室内或遮蔽处慢慢变干',
    off: '雨雪只影响画面和雷暴时的露天活动，不伤身体',
  },
]

const same = (a: PhysiologySwitches, b: PhysiologySwitches) =>
  PHYSIOLOGY_ITEMS.every(({ key }) => !!a[key] === !!b[key])

/** 「已关闭：饱腹、水分」这样的摘要 */
export function physiologySummary(s: PhysiologySwitches) {
  const off = PHYSIOLOGY_ITEMS.filter(({ key }) => !s[key]).map(({ name }) => name)
  if (!off.length) return '全部开启'
  if (off.length === PHYSIOLOGY_ITEMS.length) return '全部关闭'
  return `已关闭：${off.join('、')}`
}

/**
 * 世界级生理开关表单，自带保存和放弃。草稿只在本地，保存经世界设定控制器发给后端；
 * 显示值始终来自后端回读。
 */
export function createPhysiologySwitches(
  world: WorldSettingsController,
  options: { idPrefix: string }
) {
  const root = el('section', '', 'physiology-switches')
  const hint = el(
    'p',
    '关掉的项目：数值停在当前值，不限制活动，不发提醒，也不出现在村民的观察里。吃饭、喝水、睡觉仍可作为普通动作。',
    'physiology-hint'
  )
  const list = el('div', '', 'physiology-list')
  const rows: {
    item: (typeof PHYSIOLOGY_ITEMS)[number]
    input: HTMLInputElement
    description: HTMLElement
  }[] = []
  for (const item of PHYSIOLOGY_ITEMS) {
    const id = `${options.idPrefix}-${item.key}`
    const row = el('label', '', 'physiology-row')
    row.htmlFor = id
    const input = el('input')
    input.type = 'checkbox'
    input.id = id
    input.setAttribute('role', 'switch')
    const text = el('span', '', 'physiology-text')
    const description = el('small')
    text.append(el('b', item.name), description)
    row.append(input, text)
    list.append(row)
    rows.push({ item, input, description })
    input.addEventListener('change', () => {
      draft[item.key] = input.checked
      changed()
    })
  }
  const bulk = el('div', '', 'physiology-buttons')
  const setAll = (value: boolean) => {
    for (const { key } of PHYSIOLOGY_ITEMS) draft[key] = value
    changed()
  }
  const allOn = button('全部打开', () => setAll(true))
  const allOff = button('全部关闭', () => setAll(false))
  const saveButton = button('保存并应用', () => save(), 'primary')
  const discardButton = button('放弃修改', () => discard())
  bulk.append(allOn, allOff, el('span', '', 'physiology-gap'), discardButton, saveButton)
  const note = el(
    'p',
    '对全镇村民生效，随当前世界保存。保存后世界暂停，村民取消旧安排、重新观察。',
    'physiology-note'
  )
  const status = el('p', '', 'physiology-status')
  status.setAttribute('role', 'status')
  root.append(hint, list, bulk, note, status)

  let draft: PhysiologySwitches = {
    fullness: true,
    energy: true,
    water: true,
    health: true,
    weather: false,
  }
  /** 读进来时后端的开关：修订号变了但开关没变（世界观、神力也共用修订号），草稿照旧能存 */
  let base: PhysiologySwitches = { ...draft }
  let revision = -1
  let worldId = ''

  const saved = () => world.state()?.physiology
  const isDirty = () => {
    const current = saved()
    return !!current && !same(draft, current)
  }

  function render() {
    const current = saved()
    const locked = !current || !world.online() || world.saving()
    for (const { item, input, description } of rows) {
      input.checked = !!draft[item.key]
      input.disabled = locked
      input.closest('.physiology-row')?.classList.toggle('off', !draft[item.key])
      description.textContent = draft[item.key] ? item.on : item.off
    }
    allOn.disabled = allOff.disabled = locked
    const dirty = isDirty()
    saveButton.disabled = locked || !dirty
    discardButton.disabled = locked || !dirty
  }
  function read() {
    const state = world.state()
    if (state) draft = { weather: false, ...state.physiology }
    base = { ...draft }
    revision = state?.revision ?? -1
    worldId = state?.world_id ?? ''
    render()
  }
  function changed() {
    status.textContent = isDirty() ? '修改尚未保存' : ''
    render()
  }
  function save() {
    if (!isDirty()) {
      status.textContent = '没有需要保存的修改'
      return
    }
    status.textContent = '正在保存…'
    world.savePhysiology({ ...draft }, revision, (ok, message) => {
      if (ok) read()
      status.textContent = ok ? `${message}。当前${physiologySummary(draft)}。` : message
    })
    render()
  }
  function discard() {
    read()
    status.textContent = ''
  }

  world.subscribe(() => {
    const state = world.state()
    if (!state) {
      render()
      return
    }
    if (worldId !== state.world_id || (!isDirty() && revision !== state.revision)) read()
    else {
      if (revision !== state.revision && same(state.physiology, base)) revision = state.revision
      else if (revision !== state.revision && !world.saving())
        status.textContent = '生理开关在别处改过了；你的修改还在，点「放弃修改」读取最新的。'
      render()
    }
  })
  read()

  return { el: root, isDirty, discard }
}

/** 化身神力的两种说法：开着时能做什么，关着时怎样 */
const MIRACLES_ON =
  '化身走到人跟前，可以复活、治愈、补满；在场的村民会看到是谁做的。附身村民时不能用。'
const MIRACLES_OFF = '化身和村民一样，只能用道具救人。'

/**
 * 化身神力开关：切换就保存，世界不暂停；显示值始终来自后端回读。
 * 和生理开关挨着放，是因为它也直接改村民的身体。
 */
export function createMiraclesSwitch(world: WorldSettingsController) {
  const root = el('section', '', 'physiology-switches town-rule')
  const row = el('label', '', 'physiology-row')
  const input = el('input')
  input.type = 'checkbox'
  input.id = 'town-miracles'
  input.setAttribute('role', 'switch')
  row.htmlFor = input.id
  const description = el('small')
  const text = el('span', '', 'physiology-text')
  text.append(el('b', '化身神力'), description)
  row.append(input, text)
  const status = el('p', '', 'physiology-status')
  status.setAttribute('role', 'status')
  root.append(
    row,
    el(
      'p',
      '切换就保存，世界不会暂停。想让村民事先知道世上有神，写进「世界观」。',
      'physiology-note'
    ),
    status
  )
  function render() {
    const state = world.state()
    input.checked = !!state?.miracles
    input.disabled = !state || !world.online() || world.saving()
    row.classList.toggle('off', !input.checked)
    description.textContent = input.checked ? MIRACLES_ON : MIRACLES_OFF
  }
  input.addEventListener('change', () => {
    status.textContent = '正在保存…'
    world.saveMiracles(input.checked, (ok, message) => {
      status.textContent = ok ? `✓ ${message}` : message
      render()
    })
    render()
  })
  world.subscribe(render)
  render()
  return root
}
