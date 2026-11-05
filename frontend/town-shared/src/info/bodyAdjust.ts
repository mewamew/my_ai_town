// 角色卡「状态」右边的「调整」：世界暂停时直接拨饱腹、精力、水分、健康，比如开局就让人饿着。
// 村民不知道这是玩家调的，只会觉得饿了累了（后端照常发跨线提醒，本人记录里不留痕）。
import type { NeedKind, NeedStateView, NeedsTuning } from '../protocol'
import { NEED_ORDER } from './needs'

export type BodyValues = Partial<Record<NeedKind, number>>

const NAMES: Record<NeedKind, string> = {
  fullness: '饱腹',
  energy: '精力',
  water: '水分',
  health: '健康',
}
/** 预览用的档位字：从好到坏，和后端的分档同一套分界 */
const WORDS: Record<NeedKind, [string, string, string, string]> = {
  fullness: ['不饿', '有些饿', '很饿', '严重饥饿'],
  energy: ['精神', '有些疲劳', '很疲劳', '严重疲劳'],
  water: ['不渴', '口渴', '很渴', '严重缺水'],
  health: ['良好', '受损', '危险', '危重'],
}
const PRESETS: { label: string; title: string; values: Record<NeedKind, number> }[] = [
  {
    label: '刚入住',
    title: '新村民入住时的数值',
    values: { fullness: 75, energy: 90, water: 85, health: 100 },
  },
  {
    label: '饿了一天',
    title: '很饿，有些疲劳和口渴',
    values: { fullness: 40, energy: 60, water: 60, health: 100 },
  },
  {
    label: '快撑不住',
    title: '很饿、很疲劳，健康已经受损',
    values: { fullness: 20, energy: 40, water: 45, health: 60 },
  },
]
/** 没读到村民设定时的分界（和后端默认需求参数一致） */
const DEFAULT_MARKS = { voiced: 60, ring: 35, collapse: 15 }

interface Deps {
  /** 发出调整，回执告诉成没成 */
  apply: (values: BodyValues, done: (ok: boolean, message: string) => void) => void
}

export function createBodyAdjust(container: HTMLElement, deps: Deps) {
  let tuning: NeedsTuning | null = null
  /** 健康的三条分界：危重、危险、受损 */
  let healthMarks = [10, 30, 70]
  let paused = true
  let busy = false
  const sliders = new Map<
    NeedKind,
    { row: HTMLElement; input: HTMLInputElement; value: HTMLElement; band: HTMLElement }
  >()

  container.className = 'body-adjust'
  container.hidden = true
  const presets = document.createElement('div')
  presets.className = 'body-adjust-presets'
  const presetButtons = PRESETS.map((p) => {
    const b = document.createElement('button')
    b.type = 'button'
    b.textContent = p.label
    b.title = p.title
    b.onclick = () => {
      for (const [kind, s] of sliders) s.input.value = String(p.values[kind])
      for (const other of presetButtons) other.setAttribute('aria-pressed', String(other === b))
      refresh()
    }
    presets.append(b)
    return b
  })
  const rows = document.createElement('div')
  rows.className = 'body-adjust-rows'
  for (const kind of NEED_ORDER) {
    const row = document.createElement('label')
    row.className = 'body-adjust-row'
    row.dataset.need = kind
    const name = document.createElement('span')
    name.textContent = NAMES[kind]
    const input = document.createElement('input')
    input.type = 'range'
    input.min = kind === 'health' ? '1' : '0'
    input.max = '100'
    input.step = '1'
    input.id = `body-adjust-${kind}`
    input.oninput = () => {
      for (const b of presetButtons) b.setAttribute('aria-pressed', 'false')
      refresh()
    }
    const value = document.createElement('span')
    value.className = 'body-adjust-value'
    const band = document.createElement('span')
    band.className = 'body-adjust-band'
    row.append(name, input, value, band)
    rows.append(row)
    sliders.set(kind, { row, input, value, band })
  }
  const forecast = document.createElement('p')
  forecast.className = 'body-adjust-forecast'
  const hint = document.createElement('p')
  hint.className = 'body-adjust-hint'
  hint.textContent =
    '村民不会知道这是你调的，只会觉得饿了、累了。想让这份饿有来由，可以在人设的开局处境里写一句。'
  const status = document.createElement('p')
  status.className = 'body-adjust-status'
  status.setAttribute('role', 'status')
  const actions = document.createElement('div')
  actions.className = 'body-adjust-actions'
  const cancel = document.createElement('button')
  cancel.type = 'button'
  cancel.className = 'link'
  cancel.textContent = '取消'
  cancel.onclick = () => close()
  const apply = document.createElement('button')
  apply.type = 'button'
  apply.className = 'body-adjust-apply'
  apply.textContent = '应用'
  apply.onclick = () => {
    const values: BodyValues = {}
    for (const [kind, s] of sliders) if (!s.row.hidden) values[kind] = Number(s.input.value)
    busy = true
    sync()
    status.textContent = '调整中…'
    deps.apply(values, (ok, message) => {
      busy = false
      status.textContent = ok ? '' : message
      if (ok) close()
      else sync()
    })
  }
  actions.append(cancel, apply)
  container.append(presets, rows, forecast, hint, status, actions)

  /** 档位：饱腹、精力、水分按村民自己的需求参数，健康按固定的三条线 */
  function band(kind: NeedKind, v: number): [string, string] {
    const words = WORDS[kind]
    if (kind === 'health') {
      const [critical, danger, good] = healthMarks
      if (v >= good) return [words[0], 'steady']
      if (v > danger) return [words[1], 'voiced']
      if (v > critical) return [words[2], 'ring']
      return [words[3], 'collapse']
    }
    const m = tuning ?? DEFAULT_MARKS
    if (v >= m.voiced) return [words[0], 'steady']
    if (v >= m.ring) return [words[1], 'voiced']
    if (v >= m.collapse) return [words[2], 'ring']
    return [words[3], 'collapse']
  }

  /** 不吃东西多久会到「很饿」「严重饥饿」：按饱腹的基础消耗估，干活会更快 */
  function hours(from: number, line: number) {
    const perHour = (tuning?.fullness_decay ?? 0.05) * 60
    return (from - line) / perHour
  }

  function refresh() {
    for (const [kind, s] of sliders) {
      const v = Number(s.input.value)
      s.value.textContent = String(v)
      const [word, cls] = band(kind, v)
      s.band.textContent = word
      s.band.dataset.band = cls
    }
    const full = sliders.get('fullness')
    if (!full || full.row.hidden) {
      forecast.textContent = ''
      return
    }
    const v = Number(full.input.value)
    const m = tuning ?? DEFAULT_MARKS
    const text = (line: number, word: string) => {
      if (v <= line) return `已经${word}`
      const h = hours(v, line)
      return `约 ${h < 1 ? '不到 1' : Math.round(h)} 小时后${word}`
    }
    forecast.textContent = `不吃东西的话：${text(m.ring, '很饿')}，${text(m.collapse, '严重饥饿')}。`
  }

  function sync() {
    apply.disabled = busy || !paused
    if (!paused && !busy) status.textContent = '世界在运行，先暂停再调'
    else if (paused && status.textContent === '世界在运行，先暂停再调') status.textContent = ''
  }

  function close() {
    container.hidden = true
    status.textContent = ''
    busy = false
  }

  return {
    /** 打开时按当前数值摆好滑条；关掉的生理项（名册里没有）不出现 */
    open(needs: NeedStateView[]) {
      for (const [kind, s] of sliders) {
        const n = needs.find((x) => x.kind === kind)
        s.row.hidden = !n
        if (n) s.input.value = String(Math.round(n.value))
      }
      for (const b of presetButtons) b.setAttribute('aria-pressed', 'false')
      status.textContent = ''
      container.hidden = false
      refresh()
      sync()
    },
    close,
    isOpen: () => !container.hidden,
    setPaused(value: boolean) {
      paused = value
      sync()
    },
    tune(value: NeedsTuning, marks: number[]) {
      tuning = value
      if (marks.length === 3) healthMarks = marks
      refresh()
    },
  }
}
