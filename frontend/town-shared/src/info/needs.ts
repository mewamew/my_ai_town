import type { NeedKind, NeedStateView, NeedsTuning, PhysiologySwitches } from '../protocol'

import { NEED_BANDS } from '../needsRules'
import { gameIcon } from '../game/icons'
const BAND_CLASS: Record<string, string> = Object.fromEntries(
  Object.entries(NEED_BANDS).map(([id, band]) => [id, band.class])
)
const BAND_LABEL: Record<string, string> = Object.fromEntries(
  Object.entries(NEED_BANDS).map(([id, band]) => [id, band.label])
)
const BAND_SEVERITY: Record<string, number> = Object.fromEntries(
  Object.entries(NEED_BANDS).map(([id, band]) => [id, band.severity])
)
/** 显示顺序固定；世界设定关掉的项后端不再发送，这里按需求种类补一行灰条。 */
const NEED_ORDER: NeedKind[] = ['fullness', 'energy', 'water', 'health']
/** 关掉的项没有后端数据，灰条上写的名字 */
const NEED_NAMES: Record<NeedKind, string> = {
  fullness: '饱腹',
  energy: '精力',
  water: '水分',
  health: '健康',
}
export const NEED_ICONS: Record<NeedKind, string> = {
  fullness: 'food',
  energy: 'energy',
  water: 'water',
  health: 'heart',
}
/** 一条分成几格：只看大概还剩多少，确切数字在悬停提示里 */
const PIPS = 10

/** 这一项的状态文字：后端给的优先，平稳时不写 */
export function needWord(n: NeedStateView) {
  if (n.band === 'steady') return ''
  return n.text || BAND_LABEL[n.band] || n.band
}

/** 最该担心的一项：很饿、很渴这一级及以上才算；都还好返回 undefined */
export function worstNeed(list: NeedStateView[]): NeedStateView | undefined {
  const severity = (n: NeedStateView) => BAND_SEVERITY[n.band] ?? 0
  return list.filter((n) => severity(n) >= 2).sort((a, b) => severity(b) - severity(a))[0]
}

interface NeedEls {
  root: HTMLElement
  /** 格子条：读屏按 meter 读 */
  track: HTMLElement
  pips: HTMLElement[]
  state: HTMLElement
  kind: NeedKind
  /** 分界线的说明，放进整行的悬停提示 */
  marks: string
}

export function createNeedsView(
  container: HTMLElement,
  residentName: string,
  onChange: (text: string, warning: boolean) => void
) {
  let tuning: NeedsTuning | null = null
  /** 健康的分界不随人调整，随村民设定一起由后端给出 */
  let healthMarks: number[] = []
  let switches: PhysiologySwitches | null = null
  const lastText = new Map<NeedKind, string>()
  const lastBand = new Map<NeedKind, string>()
  const needEls = new Map<NeedKind, NeedEls>()
  // ---- 一行一项：图标、名字、格子条，不平稳时末尾写状态 ----
  function buildNeed(n: NeedStateView): NeedEls {
    const root = document.createElement('div')
    root.className = 'need'
    root.dataset.need = n.kind
    const icon = document.createElement('span')
    icon.className = 'need-icon'
    icon.append(gameIcon(NEED_ICONS[n.kind], true))
    const label = document.createElement('span')
    label.className = 'need-label'
    label.textContent = n.need
    const track = document.createElement('div')
    track.className = 'need-track'
    const pips: HTMLElement[] = []
    for (let i = 0; i < PIPS; i++) {
      const pip = document.createElement('span')
      pip.className = 'need-pip'
      track.appendChild(pip)
      pips.push(pip)
    }
    const state = document.createElement('span')
    state.className = 'need-state'
    root.append(icon, label, track, state)
    container.appendChild(root)
    root.addEventListener('animationend', () => root.classList.remove('flash'))
    const els: NeedEls = { kind: n.kind, root, track, pips, state, marks: '' }
    describeMarks(els)
    return els
  }

  function describeMarks(els: NeedEls) {
    if (!tuning) return
    // 三个分界：撑不住(collapse) / 重新考虑(ring) / 出现不适(voiced)
    const marks =
      els.kind === 'health' ? healthMarks : [tuning.collapse, tuning.ring, tuning.voiced]
    els.marks = `分界线：${marks.join(' / ')}`
  }

  function row(n: NeedStateView) {
    let els = needEls.get(n.kind)
    if (!els) {
      els = buildNeed(n)
      needEls.set(n.kind, els)
      for (const kind of NEED_ORDER) {
        const root = needEls.get(kind)?.root
        if (root) container.appendChild(root)
      }
    }
    return els
  }

  /** 世界设定关掉的项：没有数值，也不参与跨级提示 */
  function renderOff(kind: NeedKind) {
    const name = NEED_NAMES[kind]
    const els = row({ kind, need: name, value: 0, band: 'steady', text: '' })
    els.root.className = 'need need-off'
    for (const pip of els.pips) pip.classList.remove('on')
    els.state.textContent = '已关闭'
    els.root.title = `${name}已在世界设定中关闭，数值保留，不参与生活与决策`
    els.track.removeAttribute('aria-valuenow')
    lastBand.delete(kind)
    lastText.delete(kind)
  }

  /** 一次名册更新：开着的项按后端数值画，关掉的项画灰条 */
  function renderAll(list: NeedStateView[]) {
    for (const n of list) renderNeed(n)
    if (!switches) return
    const sent = new Set(list.map((n) => n.kind))
    for (const kind of NEED_ORDER) if (!switches[kind] && !sent.has(kind)) renderOff(kind)
  }

  function renderNeed(n: NeedStateView) {
    const els = row(n)
    const cls = BAND_CLASS[n.band] ?? 'steady'
    const value = Math.round(Math.min(Math.max(n.value, 0), 100))
    els.root.className = `need band-${cls}`
    // 还剩一点就留一格，免得看着像已经空了
    const on = value > 0 ? Math.max(1, Math.round((value / 100) * PIPS)) : 0
    els.pips.forEach((pip, i) => pip.classList.toggle('on', i < on))
    const word = needWord(n)
    els.state.textContent = word
    els.root.title = `${n.need} · ${value} · ${n.text || BAND_LABEL[n.band] || n.band}${els.marks ? '\n' + els.marks : ''}`
    els.track.setAttribute('role', 'meter')
    els.track.setAttribute('aria-label', word ? `${n.need}，${word}` : n.need)
    els.track.setAttribute('aria-valuemin', '0')
    els.track.setAttribute('aria-valuemax', '100')
    els.track.setAttribute('aria-valuenow', String(value))

    // 跨级检测：首次出现只记录，不强调
    const prev = lastBand.get(n.kind)
    if (prev !== undefined && prev !== n.band) {
      els.root.classList.remove('flash')
      void els.root.offsetWidth // 重启动画
      els.root.classList.add('flash')
      const worse = (BAND_SEVERITY[n.band] ?? 0) > (BAND_SEVERITY[prev] ?? 0)
      onChange(
        `${residentName}${n.need} ${value}：${lastText.get(n.kind) ?? prev} → ${n.text || BAND_LABEL[n.band] || n.band}`,
        worse
      )
    }
    lastBand.set(n.kind, n.band)
    lastText.set(n.kind, n.text || n.band)
  }

  return {
    setResidentName(name: string) {
      residentName = name
    },
    render: renderAll,
    setSwitches(value: PhysiologySwitches) {
      switches = value
    },
    tune(value: NeedsTuning, health: number[]) {
      tuning = value
      healthMarks = health
      for (const els of needEls.values()) describeMarks(els)
    },
    reset() {
      lastBand.clear()
      lastText.clear()
    },
    clear() {
      container.replaceChildren()
      needEls.clear()
      lastBand.clear()
      lastText.clear()
      tuning = null
    },
  }
}
