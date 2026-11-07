import type * as THREE from 'three'
import type {
  GameModeView,
  WerewolfLine,
  WerewolfOut,
  WerewolfRole,
  WerewolfSeat,
  WerewolfView,
} from 'town-shared/protocol'
import { button, el } from 'town-shared/dom'
import type { GameModeLook } from '.'
import { pixelIcon, type WerewolfIcon } from './werewolfIcons'
import './werewolf.css'

// 狼人杀的画面：不改着色（白天黑夜本来就有），只在地图上画自己的一层界面，上帝视角：
// 顶上一条横幅说法官此刻在做什么；左边一列座位（号码、名字、身份、出局了没有、轮到谁）；
// 底下一张卡片放刚说的那段话（夜里是狼人频道）；右边一块板子：票型、夜里各身份的选择、天亮倒下的人、结算翻牌。
// 身份可以藏起来跟着猜（记在本机）。名册每来一拍整层重画，状态没变时场景不会叫它。

const ROLE: Record<WerewolfRole, string> = {
  wolf: '狼人',
  seer: '预言家',
  witch: '女巫',
  hunter: '猎人',
  guard: '守卫',
  villager: '平民',
}
const OUT: Record<WerewolfOut, string> = {
  killed: '被刀',
  poisoned: '被毒',
  exiled: '放逐',
  shot: '中枪',
  died: '倒下',
}
const HIDE_KEY = 'town-2d:werewolf-hide-roles'

function hiddenRoles() {
  try {
    return localStorage.getItem(HIDE_KEY) === '1'
  } catch {
    return false
  }
}

export class WerewolfLook implements GameModeLook {
  readonly waterAnywhere = false
  private layer: HTMLElement | null = null
  private view: WerewolfView | null = null
  private hide = hiddenRoles()

  shadeGround(_material: THREE.Material, _surface: 'land' | 'sea') {}
  shadeStanding(_material: THREE.Material, _who: 'thing' | 'villager') {}

  mount(layer: HTMLElement) {
    this.layer = el('div', '', 'ww-hud')
    this.layer.hidden = true
    layer.append(this.layer)
    this.render()
  }

  apply(view: GameModeView | null) {
    this.view = view?.kind === 'werewolf' ? view : null
    this.render()
  }

  private seat(n: number | undefined): WerewolfSeat | undefined {
    return n ? this.view?.seats[n - 1] : undefined
  }
  private label(n: number | undefined) {
    const s = this.seat(n)
    return s ? `${s.seat} 号 ${s.name}` : ''
  }
  private roleIcon(role: WerewolfRole) {
    return this.hide ? null : pixelIcon(role)
  }

  private render() {
    const root = this.layer
    if (!root) return
    const v = this.view
    root.hidden = !v
    root.replaceChildren()
    if (!v) return
    root.classList.toggle('ww-dark', v.phase === 'night' || v.phase === 'dusk')
    root.append(this.banner(v), this.seats(v))
    const stage = this.stage(v)
    if (stage) root.append(stage)
    const board = this.board(v)
    if (board) root.append(board)
  }

  /** 顶上的横幅：阶段、轮到谁、投了几票 */
  private banner(v: WerewolfView) {
    const icon: WerewolfIcon =
      v.phase === 'night' || v.phase === 'dusk'
        ? 'moon'
        : v.phase === 'vote'
          ? 'ballot'
          : v.phase === 'speech' || v.phase === 'gather'
            ? 'fire'
            : 'sun'
    const box = el('div', '', 'ww-banner')
    box.append(pixelIcon(icon, 2), el('b', v.notice))
    const living = v.seats.filter((s) => !s.out).length
    let sub = ''
    if (v.phase === 'speech' && v.turn) sub = `正在说：${this.label(v.turn)}`
    else if (v.phase === 'vote' && !v.revealed) sub = `已投 ${v.ballots?.length ?? 0}/${living}`
    else if (v.phase === 'last_words' && v.turn) sub = `${this.label(v.turn)} 留遗言`
    else if (v.phase === 'shot' && v.turn) sub = `猎人 ${this.label(v.turn)} 要开枪`
    else if (v.phase === 'night' && v.turn) sub = `狼人频道：${this.label(v.turn)}`
    else if (v.phase === 'waiting') sub = '天亮开局'
    else if (v.phase === 'over') sub = v.winner === 'good' ? '好人胜利' : '狼人胜利'
    if (sub) box.append(el('span', sub))
    return box
  }

  /** 左边的座位：号码、名字、身份、出局方式；轮到谁亮绿圈，投了票打勾 */
  private seats(v: WerewolfView) {
    const box = el('div', '', 'ww-seats')
    const voted = new Set((v.ballots ?? []).map((b) => b.voter))
    const voting = v.phase === 'vote' && !v.revealed
    for (const s of v.seats) {
      const row = el('div', '', 'ww-seat')
      if (s.out) row.classList.add('out')
      if (v.turn === s.seat) row.classList.add('turn')
      if (!this.hide && s.role === 'wolf') row.classList.add('wolf')
      row.append(el('i', String(s.seat)))
      const icon = this.roleIcon(s.role)
      if (icon) row.append(icon)
      row.append(el('b', s.name))
      if (s.out) row.append(el('small', OUT[s.out]))
      else if (voting && voted.has(s.seat)) row.append(el('small', '已投', 'ok'))
      box.append(row)
    }
    const toggle = button(this.hide ? '显示身份' : '藏起身份', () => {
      this.hide = !this.hide
      try {
        localStorage.setItem(HIDE_KEY, this.hide ? '1' : '0')
      } catch {
        // 本机存不了就只这一次有效
      }
      this.render()
    })
    toggle.className = 'ww-toggle'
    box.append(toggle)
    return box
  }

  /** 底下的卡片：今天最后说的那段话（黄昏时多半是遗言）；夜里换成狼人频道最后一句（上帝视角） */
  private stage(v: WerewolfView) {
    let line: WerewolfLine | undefined
    let channel = false
    if (v.phase === 'night') {
      line = v.night?.wolf_lines?.at(-1)
      channel = true
    } else if (['speech', 'vote', 'last_words', 'shot', 'dusk'].includes(v.phase)) {
      line = v.lines?.at(-1)
    }
    if (!line) return null
    const s = this.seat(line.seat)
    const card = el('div', '', channel ? 'ww-stage channel' : 'ww-stage')
    if (Array.from(line.text).length > 220) card.classList.add('long')
    const head = el('div', '', 'ww-stage-head')
    head.append(el('i', String(line.seat)))
    const icon = s && this.roleIcon(s.role)
    if (icon) head.append(icon)
    head.append(el('b', s?.name ?? ''))
    const tag = channel ? '狼人频道' : line.last ? '遗言' : line.away ? '没到场' : ''
    if (tag) head.append(el('small', tag))
    card.append(head, el('p', line.text))
    return card
  }

  /** 右边的板子：按阶段放票型、夜里的选择、天亮的死讯或结算翻牌 */
  private board(v: WerewolfView) {
    if (v.phase === 'over') return this.finale(v)
    if (v.phase === 'night' && v.night) return this.nightBoard(v)
    if (v.revealed && (v.ballots?.length ?? 0) > 0) return this.tally(v)
    if (v.phase === 'day' && v.day > 1) return this.dawnBoard(v)
    return null
  }

  private tally(v: WerewolfView) {
    const box = el('div', '', 'ww-board')
    box.append(el('h4', `第 ${v.day} 天 · 票型`))
    const groups = new Map<number, number[]>()
    const abstain: number[] = []
    for (const b of v.ballots ?? []) {
      if (b.target) groups.set(b.target, [...(groups.get(b.target) ?? []), b.voter])
      else abstain.push(b.voter)
    }
    const rows = [...groups].sort((a, b) => b[1].length - a[1].length)
    const most = rows[0]?.[1].length ?? 0
    for (const [target, voters] of rows) {
      const row = el('div', '', 'ww-tally')
      if (voters.length === most) row.classList.add('top')
      row.append(el('b', this.label(target)), el('span', `${voters.length} 票`))
      row.append(el('small', `← ${voters.join('、')} 号`))
      box.append(row)
    }
    if (abstain.length) box.append(el('p', `弃票：${abstain.join('、')} 号`, 'ww-note'))
    return box
  }

  private nightBoard(v: WerewolfView) {
    const n = v.night!
    const box = el('div', '', 'ww-board dark')
    box.append(el('h4', `第 ${n.night} 夜 · 上帝视角`))
    const row = (icon: WerewolfIcon, title: string, text: string) => {
      const r = el('div', '', 'ww-act')
      r.append(pixelIcon(icon), el('b', title), el('span', text))
      box.append(r)
    }
    row('wolf', '狼人', n.kill ? `刀 ${this.label(n.kill)}` : '还在商量')
    if (v.seats.some((s) => s.role === 'guard'))
      row('guard', '守卫', n.guard ? `守 ${this.label(n.guard)}` : '还没选')
    row(
      'seer',
      '预言家',
      n.check ? `验 ${this.label(n.check.seat)}：${n.check.wolf ? '狼人' : '好人'}` : '还没验'
    )
    row('witch', '女巫', n.save ? '用解药救人' : n.poison ? `毒 ${this.label(n.poison)}` : '没用药')
    return box
  }

  private dawnBoard(v: WerewolfView) {
    const box = el('div', '', 'ww-board')
    box.append(el('h4', `第 ${v.day} 天 · 天亮了`))
    const dawn = v.dawn ?? []
    if (!dawn.length) box.append(el('p', '昨晚是平安夜', 'ww-big'))
    else {
      box.append(el('p', '昨晚倒下的是', 'ww-note'))
      for (const n of dawn) {
        const s = this.seat(n)
        const r = el('div', '', 'ww-fallen')
        r.append(el('i', String(n)), el('b', s?.name ?? ''))
        box.append(r)
      }
      box.append(el('p', '不说死因，不翻牌', 'ww-note'))
    }
    return box
  }

  private finale(v: WerewolfView) {
    const box = el('div', '', 'ww-board finale')
    box.append(el('h4', v.winner === 'good' ? '好人胜利' : '狼人胜利'))
    for (const s of v.seats) {
      const r = el('div', '', 'ww-reveal')
      if (s.role === 'wolf') r.classList.add('wolf')
      if (s.out) r.classList.add('out')
      r.append(
        el('i', String(s.seat)),
        pixelIcon(s.role),
        el('b', s.name),
        el('span', ROLE[s.role])
      )
      const night = s.out === 'killed' || s.out === 'poisoned'
      const when = s.out_day ? `第 ${s.out_day} ${night ? '夜' : '天'}` : ''
      r.append(el('small', s.out ? `${when}${OUT[s.out]}` : '存活'))
      box.append(r)
    }
    return box
  }
}
