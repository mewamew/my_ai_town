import * as THREE from 'three'
import type { FrostlightView, GameModeAction, GameModeView } from 'town-shared/protocol'
import { button, el } from 'town-shared/dom'
import { requestGameModeControl } from 'town-shared/gameModeControls'
import type { GameModeLook } from '.'
import type { Badge } from '../villagerSigns'
import { FrostlightFurnace } from './frostlightFurnace'
import './frostlight.css'

const PHASE = { preparation: '储备期', cold: '寒潮逼近', storm: '暴风雪', over: '这一夜的结局' }
const WORK: Record<string, string> = {
  fuel: '采集燃料',
  food: '运送食材',
  materials: '回收材料',
  build: '加固保温',
  tend: '照顾居民',
}
const POLICY = [
  ['extended_shift', '延长轮班', '产出+50%，工时25→35分；希望−8，不满+15，之后每小时不满+2。'],
  ['soup', '热汤配给', '日常粮耗降低35%；希望−5，不满+12。'],
  ['mutual_aid', '互助公约', '立即分发3食物；希望+10、不满−8，之后每小时希望+2，照护效果增强。'],
] as const
const JOB_BADGE: Badge = {
  name: 'frostlight-work',
  rows: ['..KKK..', '.KYYYK.', 'KYYYYYK', 'KKKYKKK', '..KYK..', '..KYK..', '..KKK..'],
}
const CARE_BADGE: Badge = {
  name: 'frostlight-care',
  rows: ['.KK.KK.', 'KPPKPPK', 'KPPPPPK', '.KPPPK.', '..KPK..', '...K...'],
}
const timeLeft = (minutes: number) => {
  const n = Math.max(0, Math.ceil(minutes))
  return n >= 60 ? `${Math.floor(n / 60)}时 ${n % 60}分` : `${n}分`
}
const amount = (n: number) => (Number.isFinite(n) ? Math.max(0, n).toFixed(n < 10 ? 1 : 0) : '—')

/** 节点只建一次，广播只改文本与属性。鼠标按下、键盘焦点和展开状态不会被下一帧名册冲掉。 */
export class FrostlightLook implements GameModeLook {
  readonly waterAnywhere = false
  private view: FrostlightView | null = null
  private root: HTMLElement | null = null
  private furnace: FrostlightFurnace | null = null
  private landmark: ((id: string) => { x: number; z: number } | null) | null = null
  private fields = new Map<string, HTMLElement>()
  private actions: { node: HTMLButtonElement; command: GameModeAction }[] = []
  private bars = new Map<string, HTMLMeterElement>()
  private people = new Map<string, { root: HTMLElement; job: HTMLElement; score: HTMLElement }>()
  private pending = false
  private endingDismissed = false
  private lastEnding = ''
  private lastNews = ''
  private history: HTMLElement | null = null
  private roster: HTMLElement | null = null
  private ending: HTMLElement | null = null

  shadeGround(_material: THREE.Material, _surface: 'land' | 'sea') {}
  shadeStanding(_material: THREE.Material, _who: 'thing' | 'villager') {}

  private field(key: string, tag: 'span' | 'strong' | 'p' | 'h2' = 'span', cls = '') {
    const node = el(tag, '', cls)
    this.fields.set(key, node)
    return node
  }
  private text(key: string, value: string) {
    const node = this.fields.get(key)
    if (node && node.textContent !== value) node.textContent = value
  }
  private action(label: string, command: GameModeAction, cls = '') {
    const node = button(label, () => void this.submit(command), cls)
    this.actions.push({ node, command })
    return node
  }
  private gauge(key: string, label: string) {
    const root = el('div', '', `fl-gauge fl-${key}`)
    const heading = el('div')
    heading.append(el('span', label), this.field(key))
    const meter = el('meter')
    meter.min = 0
    meter.max = 100
    meter.setAttribute('aria-label', label)
    this.bars.set(key, meter)
    root.append(heading, meter)
    return root
  }

  mount(layer: HTMLElement) {
    const root = (this.root = el('section', '', 'fl-hud'))
    root.hidden = true
    root.setAttribute('aria-label', '霜灯镇生存状态')
    // 地图会捕获左键指针来平移；面板操作要留在面板里，否则抬起时 click 会落到地图上。
    for (const type of ['pointerdown', 'dblclick', 'wheel'] as const)
      root.addEventListener(type, (event) => event.stopPropagation())
    const top = el('header', '', 'fl-summary')
    const seal = el('div', '', 'fl-seal')
    seal.append(el('span', 'FROSTLIGHT'), el('b', '霜灯镇'))
    const phase = el('div', '', 'fl-phase')
    phase.append(this.field('phase', 'strong'), this.field('countdown'))
    const temperature = el('div', '', 'fl-temperature')
    temperature.append(this.field('temperature', 'strong'), el('span', '外界气温'))
    top.append(seal, phase, temperature)
    const stock = el('div', '', 'fl-stock')
    for (const [key, title, icon] of [
      ['fuel', '燃料', '♨'],
      ['food', '食物', '◒'],
      ['materials', '材料', '▧'],
    ]) {
      const item = el('div', '', 'fl-resource')
      item.append(
        el('span', icon, 'fl-resource-icon'),
        this.field(key, 'strong'),
        el('small', title)
      )
      stock.append(item)
    }
    const morale = el('div', '', 'fl-morale')
    morale.append(this.gauge('hope', '希望'), this.gauge('discontent', '不满'))
    const resources = el('div', '', 'fl-resources')
    const climate = this.field('climate', 'p', 'fl-climate')
    const warning = this.field('warning', 'p', 'fl-warning')
    warning.setAttribute('role', 'status')
    warning.setAttribute('aria-live', 'polite')
    resources.append(stock, morale, climate, warning)
    const panel = el('details', '', 'fl-panel')
    panel.open = !window.matchMedia('(max-width: 760px)').matches
    const summary = el('summary')
    summary.append(el('span', '热源与法令'), el('small', '管理霜灯镇'))
    const inner = el('div', '', 'fl-panel-body')
    const objective = el(
      'p',
      '守住炉火，熬过风暴。居民需走到工作点劳动，再把物资带回。',
      'fl-objective'
    )
    const heat = el('div', '', 'fl-heat')
    heat.append(el('h3', '中央热源'), this.field('heat-note', 'p'))
    const levels = el('div', '', 'fl-heat-levels')
    for (const [i, label] of ['关闭', '低温', '高温', '过载'].entries())
      levels.append(this.action(label, { action: 'heat', target: String(i) }))
    heat.append(
      levels,
      this.gauge('stress', '炉压'),
      this.field('insulation', 'p', 'fl-small'),
      el(
        'p',
        '六人每小时耗燃料：0 / 3 / 6 / 10，随人口同比变化。过载炉压+0.8/分，其他档−0.35/分；100%跳闸，90%以上不能开启过载。',
        'fl-small'
      ),
      el('p', '炉周暖圈表示热浪，抗寒以避难所温度为准。', 'fl-small')
    )
    const laws = el('div', '', 'fl-laws')
    laws.append(el('h3', '生存法令'), el('p', '法令本局不可撤销。请先衡量下面的代价。', 'fl-small'))
    for (const [id, title, description] of POLICY) {
      const law = this.action('', { action: 'law', target: id }, 'fl-law')
      law.append(el('b', title), el('small', description))
      laws.append(law)
    }
    const relief = this.action('启用最后一批应急物资', { action: 'relief' }, 'fl-relief')
    relief.title = '本局一次：燃料+12、食物+8、材料+6，希望+5。'
    const receipt = this.field('receipt', 'p', 'fl-receipt')
    receipt.setAttribute('role', 'status')
    receipt.setAttribute('aria-live', 'polite')
    inner.append(
      objective,
      heat,
      laws,
      relief,
      el('p', '本局一次：燃料+12、食物+8、材料+6，希望+5。', 'fl-small'),
      receipt
    )
    panel.append(summary, inner)
    const community = el('details', '', 'fl-community')
    community.append(el('summary', '居民与值守记录'))
    this.roster = el('div', '', 'fl-roster')
    this.history = el('ol', '', 'fl-news')
    community.append(this.roster, this.history)
    community.addEventListener('toggle', () => {
      if (community.open) panel.open = false
    })
    panel.addEventListener('toggle', () => {
      if (panel.open) community.open = false
    })
    this.ending = el('aside', '', 'fl-ending')
    this.ending.hidden = true
    this.ending.setAttribute('aria-label', '霜灯镇结局')
    const close = button(
      '收起',
      () => {
        this.endingDismissed = true
        this.render()
      },
      'fl-ending-close'
    )
    this.ending.append(
      el('span', '这一夜，我们留下的', 'fl-eyebrow'),
      close,
      this.field('ending-title', 'h2'),
      this.field('ending-text', 'p'),
      this.field('ending-score', 'p', 'fl-small')
    )
    const reopen = button(
      '查看结局',
      () => {
        this.endingDismissed = false
        this.render()
      },
      'fl-reopen'
    )
    this.fields.set('reopen', reopen)
    reopen.hidden = true
    const controls = [top, resources, panel, community, this.ending, reopen]
    for (const control of controls) control.setAttribute('data-map-control', '')
    root.append(...controls)
    layer.append(root)
    this.render()
  }

  addToScene(scene: THREE.Scene, landmark: (id: string) => { x: number; z: number } | null) {
    this.furnace = new FrostlightFurnace(scene)
    this.landmark = landmark
    this.syncFurnace()
  }
  private syncFurnace() {
    const v = this.view
    this.furnace?.set(v, v ? (this.landmark?.(v.generator) ?? null) : null)
  }
  apply(view: GameModeView | null, _metre: number) {
    this.view = view?.kind === 'frostlight' ? view : null
    this.syncFurnace()
    this.render()
  }
  step(t: number) {
    return this.furnace?.step(t) ?? false
  }
  badges(): ReadonlyMap<string, Badge> {
    return new Map(
      (this.view?.people ?? [])
        .filter((p) => p.work && !p.gone)
        .map((p) => [p.id, p.work?.kind === 'tend' ? CARE_BADGE : JOB_BADGE])
    )
  }
  private async submit(command: GameModeAction) {
    if (!this.root || !this.view || this.pending || this.view.ending) return
    this.pending = true
    this.text('receipt', '正在等待小镇确认…')
    this.render()
    const receipt = await requestGameModeControl(this.root, command)
    this.pending = false
    this.text('receipt', receipt.ok ? `✓ ${receipt.message}` : receipt.message)
    this.render()
  }
  private render() {
    const v = this.view
    if (!this.root) return
    this.root.hidden = !v
    if (!v) return
    this.root.dataset.phase = v.phase
    this.text('phase', PHASE[v.phase])
    this.text(
      'countdown',
      v.ending
        ? '本局已结束'
        : `${v.phase === 'storm' ? '距黎明' : '距阶段结束'} ${timeLeft(v.until - v.now)}`
    )
    this.text('temperature', `${Math.round(v.temperature)}°C`)
    this.text(
      'climate',
      `${Number.isFinite(v.shelter_temperature) ? `避难所 ${Math.round(v.shelter_temperature)}°C` : '避难所温度待同步'} · 中央热源向避难所供热`
    )
    const risks = [
      v.cold_minutes > 0 ? `严寒 ${Math.ceil(v.cold_minutes)}/90分` : '',
      v.hunger_minutes > 0 ? `断粮 ${Math.ceil(v.hunger_minutes)}/120分` : '',
      v.unrest_minutes > 0 ? `民心危机 ${Math.ceil(v.unrest_minutes)}/30分` : '',
      v.stress >= 80 ? '炉压接近极限，请降低供热档位' : '',
    ].filter(Boolean)
    this.text(
      'warning',
      risks.length
        ? `⚠ ${risks.join(' · ')}${v.cold_minutes > 0 || v.hunger_minutes > 0 || v.unrest_minutes > 0 ? '。达到时限将失守，恢复供给后风险逐渐缓解。' : ''}`
        : ''
    )
    const warning = this.fields.get('warning')
    if (warning) warning.hidden = !risks.length || !!v.ending
    for (const key of ['fuel', 'food', 'materials'] as const) {
      this.text(key, amount(v[key]))
      this.fields.get(key)?.parentElement?.classList.toggle('low', v[key] < 5)
    }
    for (const key of ['hope', 'discontent', 'stress'] as const) {
      this.text(key, `${Math.round(v[key])}%`)
      const bar = this.bars.get(key)
      if (bar) bar.value = Math.max(0, Math.min(100, v[key]))
    }
    this.text(
      'heat-note',
      v.fuel <= 0
        ? '燃料已耗尽，热源正在失温。'
        : ([
            '炉火已关闭 · 储备燃料',
            '基础供热 · 节约燃料',
            '加强供热 · 消耗更多燃料',
            '过载供热 · 炉压持续上升',
          ][v.heat] ?? '热源运行中')
    )
    this.text('insulation', `保温加固 ${v.insulation} 级 · 距黎明 ${timeLeft(v.ends_at - v.now)}`)
    for (const { node, command } of this.actions) {
      const enacted =
        command.action === 'law' && !!v.policies[command.target as keyof typeof v.policies]
      const active = command.action === 'heat' && String(v.heat) === command.target
      node.disabled =
        (command.action === 'heat' && command.target === '3' && v.stress >= 90) ||
        (command.action === 'law' && command.target === 'mutual_aid' && v.food < 3) ||
        this.pending ||
        !!v.ending ||
        enacted ||
        (command.action === 'relief' && v.aid_used)
      node.classList.toggle('active', active || enacted)
      if (command.action === 'heat') node.setAttribute('aria-pressed', String(active))
      if (command.action === 'law') node.setAttribute('aria-pressed', String(enacted))
      if (command.action === 'relief')
        node.textContent = v.aid_used ? '应急物资已启用' : '启用最后一批应急物资'
    }
    const ids = new Set(v.people.map((p) => p.id))
    for (const [id, row] of this.people)
      if (!ids.has(id)) {
        row.root.remove()
        this.people.delete(id)
      }
    for (const person of v.people) {
      let row = this.people.get(person.id)
      if (!row) {
        const root = el('div', '', 'fl-person'),
          job = el('span'),
          score = el('small')
        root.append(el('b', person.name), job, score)
        row = { root, job, score }
        this.people.set(person.id, row)
        this.roster?.append(root)
      }
      row.root.classList.toggle('gone', person.gone)
      row.job.textContent = person.gone
        ? '已离开'
        : person.work
          ? (WORK[person.work.kind] ?? person.work.kind)
          : '自行安排'
      row.score.textContent = `贡献 ${person.contribution}`
      row.root.title = person.role
    }
    const news = JSON.stringify(v.news)
    if (news !== this.lastNews) {
      this.lastNews = news
      this.history?.replaceChildren(
        ...v.news
          .slice(-6)
          .reverse()
          .map((n) => el('li', n.text))
      )
    }
    const endingKey = v.ending ? `${v.ends_at}:${v.ending.kind}` : ''
    if (endingKey !== this.lastEnding) {
      this.lastEnding = endingKey
      this.endingDismissed = false
    }
    if (this.ending) this.ending.hidden = !v.ending || this.endingDismissed
    const reopen = this.fields.get('reopen')
    if (reopen) reopen.hidden = !v.ending || !this.endingDismissed
    if (v.ending) {
      this.text('ending-title', v.ending.title)
      this.text('ending-text', v.ending.text)
      this.text(
        'ending-score',
        `留下 ${v.ending.survivors} 位居民 · 总贡献 ${v.people.reduce((n, p) => n + p.contribution, 0)} · 希望 ${Math.round(v.hope)}%`
      )
    }
  }
}
