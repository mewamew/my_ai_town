import type * as THREE from 'three'
import type {
  GameModeView,
  SwordholderLine,
  SwordholderRole,
  SwordholderSeat,
  SwordholderView,
} from 'town-shared/protocol'
import { el } from 'town-shared/dom'
import { residentPortrait } from 'town-shared/portraits'
import type { GameModeLook } from '.'
import { Droplet, type DropState } from './swordholderDrop'
import { ROLE_ICON, swordholderIcon, type SwordholderIcon } from './swordholderIcons'
import './swordholder.css'

// 执剑人之夜的画面：不改着色，地图上一层界面（上帝视角），天上一颗水滴（swordholderDrop.ts）。
// 顶上一条横幅：威慑纪元 62 年、此刻在做什么、轮到谁；水滴来袭时变成红色警报，带倒计时。
// 左边一列名单：头像、身份、谁握着开关、谁投了票。底下一张卡片放刚说的那段话和「心里」（交的时候写的打算）；
// 水滴来袭的十分钟里换成开关卡：执剑人、倒计时、按下还是不按。右边亮票后是票型和每个人投票时的心里。
// 结局定了右边一张结局卡（撞击那几秒过后才浮出来）。名册每来一拍整层重画，状态没变时场景不会叫它。

const ROLE: Record<SwordholderRole, string> = {
  holder: '现任执剑人',
  candidate: '候选人',
  envoy: '三体',
  voter: '选民',
}
/** 法官给执剑人的时间（分钟），同内核 swordholder.rs 的 ATTACK_MINUTES */
const ATTACK_MINUTES = 10
/** 结局卡在结局定下后几秒浮出来：等水滴撞上或掉头 */
const ENDING_DELAY = 3.2

/** 几分钟写成「06:48」 */
function countdown(minutes: number) {
  const s = Math.max(0, Math.round(minutes * 60))
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${pad(Math.floor(s / 60))}:${pad(s % 60)}`
}

export class SwordholderLook implements GameModeLook {
  readonly waterAnywhere = false
  private layer: HTMLElement | null = null
  private view: SwordholderView | null = null
  private drop: Droplet | null = null
  private landmark: ((locale: string) => { x: number; z: number } | null) | null = null
  /** 看到结局的那一刻（毫秒）；一打开就已经有结局时为 0，结局卡不再等 */
  private endingSeen = -1

  shadeGround(_material: THREE.Material, _surface: 'land' | 'sea') {}
  shadeStanding(_material: THREE.Material, _who: 'thing' | 'villager') {}

  mount(layer: HTMLElement) {
    this.layer = el('div', '', 'sh-hud')
    this.layer.hidden = true
    layer.append(this.layer)
    this.render()
  }

  addToScene(scene: THREE.Scene, landmark: (locale: string) => { x: number; z: number } | null) {
    this.drop = new Droplet(scene)
    this.landmark = landmark
  }

  step(t: number) {
    return this.drop?.step(t) ?? false
  }

  apply(view: GameModeView | null) {
    const before = this.view
    this.view = view?.kind === 'swordholder' ? view : null
    const v = this.view
    if (!v?.ending) this.endingSeen = -1
    else if (this.endingSeen < 0) this.endingSeen = before ? performance.now() : 0
    this.aim(v, before)
    this.render()
  }

  /** 天上的水滴：来袭时按倒计时往前挪，结局定了撞上或掉头；刚看到结局才重放那一下 */
  private aim(v: SwordholderView | null, before: SwordholderView | null) {
    const drop = this.drop
    if (!drop) return
    drop.aim(v?.antenna ? (this.landmark?.(v.antenna) ?? null) : null)
    let state: DropState = { kind: 'none' }
    if (v?.ending) {
      const fresh = !!before && !before.ending
      state = { kind: v.ending === 'broadcast' ? 'broadcast' : 'failed', fresh }
    } else if (v?.phase === 'attack') {
      const left = v.left ?? ATTACK_MINUTES
      const progress = Math.min(1, Math.max(0, 1 - left / ATTACK_MINUTES))
      state = { kind: 'coming', progress, fresh: !!before && before.phase !== 'attack' }
    }
    drop.set(state)
  }

  private seat(n: number | undefined): SwordholderSeat | undefined {
    return n ? this.view?.seats[n - 1] : undefined
  }
  private name(n: number | undefined) {
    return this.seat(n)?.name ?? ''
  }
  /** 身份：交接完成后握着开关的人写「执剑人」，原来的执剑人写「前任执剑人」 */
  private roleOf(v: SwordholderView, s: SwordholderSeat) {
    const handed = v.swordholder !== 1
    if (handed && s.seat === v.swordholder) return '执剑人'
    if (handed && s.role === 'holder') return '前任执剑人'
    return ROLE[s.role]
  }

  private render() {
    const root = this.layer
    if (!root) return
    const v = this.view
    root.hidden = !v
    root.replaceChildren()
    if (!v) return
    root.append(this.banner(v), this.seats(v))
    const card = v.phase === 'attack' ? this.switchCard(v) : this.stage(v)
    if (card) root.append(card)
    const board = this.board(v)
    if (board) root.append(board)
    if (v.ending) root.append(this.ending(v))
  }

  /** 顶上的横幅：年代、阶段、轮到谁；水滴来袭时是红色警报和倒计时 */
  private banner(v: SwordholderView) {
    const alarm = v.phase === 'attack'
    const icon: SwordholderIcon =
      v.phase === 'attack'
        ? 'drop'
        : v.ending
          ? 'antenna'
          : v.phase === 'vote' || v.phase === 'tiebreak'
            ? 'ballot'
            : v.phase === 'speech'
              ? 'podium'
              : v.phase === 'gather'
                ? 'bell'
                : 'sword'
    const box = el('div', '', alarm ? 'sh-banner alarm' : 'sh-banner')
    box.append(swordholderIcon(icon, 2), el('b', `威慑纪元 62 年 · ${v.notice}`))
    const voters = v.seats.filter((s) => s.role === 'voter' && !s.gone).length
    let sub = ''
    if (alarm) sub = `天线被毁前 ${countdown(v.left ?? 0)}`
    else if (v.phase === 'speech' && v.turn) sub = `正在说：${this.name(v.turn)}`
    else if (v.phase === 'vote') sub = `已投 ${v.ballots?.length ?? 0}/${voters}`
    else if (v.phase === 'tiebreak' && v.turn) sub = `${this.name(v.turn)} 在指定`
    else if (v.phase === 'interval')
      sub = v.elected ? `新执剑人：${this.name(v.elected)}` : '没有新执剑人'
    else if (v.phase === 'handover')
      sub = v.turn ? `${this.name(v.turn)} 在交接` : `${this.name(v.swordholder)} 握着开关`
    else if (v.ending) sub = v.ending === 'broadcast' ? '引力波广播发出' : '威慑失败'
    else if (v.phase === 'waiting') sub = '天亮开局'
    else sub = '今天选出新的执剑人'
    box.append(el('span', sub))
    return box
  }

  /** 左边的名单：头像、名字、身份；轮到谁亮绿圈，握着开关的人带剑，投了票打勾 */
  private seats(v: SwordholderView) {
    const box = el('div', '', 'sh-seats')
    const voted = new Set((v.ballots ?? []).map((b) => b.voter))
    const voting = v.phase === 'vote' && !v.revealed
    for (const s of v.seats) {
      const row = el('div', '', 'sh-seat')
      if (s.gone) row.classList.add('gone')
      if (v.turn === s.seat) row.classList.add('turn')
      if (s.seat === v.swordholder) row.classList.add('holding')
      const face = residentPortrait(s.id, s.name)
      face.classList.add('sh-face')
      row.append(face, el('b', s.name), el('small', this.roleOf(v, s), `sh-role ${s.role}`))
      if (s.gone) row.append(el('i', '不在了', 'sh-state'))
      else if (s.seat === v.swordholder) row.append(swordholderIcon('sword'))
      else if (voting && voted.has(s.seat)) row.append(el('i', '已投', 'sh-state ok'))
      else if (v.elected === s.seat) row.append(el('i', '当选', 'sh-state ok'))
      box.append(row)
    }
    return box
  }

  /** 底下的卡片：最后说的那段话和心里；轮到的人还在想时最后一行写「X 正在想…」 */
  private stage(v: SwordholderView) {
    const line: SwordholderLine | undefined = v.lines?.at(-1)
    const speaking = ['speech', 'tiebreak', 'handover', 'aftermath'].includes(v.phase)
    const next = speaking && v.turn && v.turn !== line?.seat ? v.turn : undefined
    if (!line && !next) return null
    if (v.phase === 'waiting' || v.phase === 'day' || v.phase === 'gather') return null
    const card = el('div', '', 'sh-stage')
    if (line) {
      const s = this.seat(line.seat)
      if (Array.from(line.text).length > 220) card.classList.add('long')
      const head = el('div', '', 'sh-stage-head')
      if (s) {
        const face = residentPortrait(s.id, s.name)
        face.classList.add('sh-face')
        head.append(face, el('b', s.name), el('small', this.roleOf(v, s), `sh-role ${s.role}`))
      }
      head.append(el('em', line.away ? `${line.occasion} · 没到场` : line.occasion))
      card.append(head, el('p', line.text))
      if (line.reason) card.append(this.mind(line.reason))
    }
    if (next) {
      const row = el('div', '', line ? 'sh-next' : 'sh-next alone')
      const what = v.phase === 'tiebreak' ? '在想指定谁…' : '正在想…'
      row.append(el('span', '●●●', 'sh-dots'), `${this.name(next)} ${what}`)
      card.append(row)
    }
    return card
  }

  private mind(reason: string) {
    const mind = el('div', '', 'sh-mind')
    mind.append(el('b', '心里'), el('span', reason))
    return mind
  }

  /** 水滴来袭的十分钟：执剑人、倒计时、按下还是不按 */
  private switchCard(v: SwordholderView) {
    const s = this.seat(v.swordholder)
    const card = el('div', '', 'sh-stage sh-switch')
    const head = el('div', '', 'sh-stage-head')
    if (s) {
      const face = residentPortrait(s.id, s.name)
      face.classList.add('sh-face')
      head.append(face, el('b', s.name), el('small', '执剑人', 'sh-role holder'))
    }
    head.append(el('em', countdown(v.left ?? 0), 'sh-clock'))
    card.append(head)
    const row = el('div', '', 'sh-next alone')
    row.append(el('span', '●●●', 'sh-dots'), `${s?.name ?? ''} 正在想…`)
    card.append(row)
    const options = el('div', '', 'sh-options')
    const press = el('span', '', 'press')
    press.append(swordholderIcon('switch'), '按下 · 广播三体坐标')
    options.append(press, el('span', '不按', 'hold'))
    card.append(options)
    return card
  }

  /** 右边的板子：亮票后是票型和每张票的心里，交接前后多一行谁当选、怎么当选的 */
  private board(v: SwordholderView) {
    if (!v.revealed || v.phase === 'attack' || v.ending) return null
    const box = el('div', '', 'sh-board')
    box.append(el('h4', '票型'))
    const groups = new Map<number, number[]>()
    for (const s of v.seats) if (s.role === 'candidate') groups.set(s.seat, [])
    const abstain: number[] = []
    for (const b of v.ballots ?? []) {
      if (b.target && groups.has(b.target)) groups.get(b.target)!.push(b.voter)
      else abstain.push(b.voter)
    }
    const rows = [...groups].sort((a, b) => b[1].length - a[1].length)
    for (const [target, voters] of rows) {
      const row = el('div', '', 'sh-tally')
      if (v.elected === target) row.classList.add('top')
      row.append(el('b', this.name(target)), el('span', `${voters.length} 票`))
      if (voters.length) row.append(el('small', `← ${voters.map((n) => this.name(n)).join('、')}`))
      box.append(row)
    }
    if (abstain.length)
      box.append(el('p', `弃票：${abstain.map((n) => this.name(n)).join('、')}`, 'sh-note'))
    if (v.elected)
      box.append(
        el(
          'p',
          `${this.name(v.elected)} 当选${v.appointed ? '（平票，现任执剑人指定）' : ''}`,
          'sh-note strong'
        )
      )
    const reasons = (v.ballots ?? []).filter((b) => b.reason)
    if (reasons.length) {
      const list = el('div', '', 'sh-reasons')
      for (const b of reasons) {
        const r = el('div', '', 'sh-reason')
        r.append(el('b', this.name(b.voter)), el('span', b.reason!))
        list.append(r)
      }
      box.append(list)
    }
    return box
  }

  /** 右边的结局卡：按下了还是威慑失败，执剑人当时说的话和心里 */
  private ending(v: SwordholderView) {
    const failed = v.ending === 'failed'
    const box = el('div', '', failed ? 'sh-ending failed' : 'sh-ending')
    if (this.endingSeen > 0) {
      const wait = ENDING_DELAY - (performance.now() - this.endingSeen) / 1000
      if (wait > 0) box.style.animationDelay = `${wait.toFixed(2)}s`
      else box.style.animation = 'none'
    } else box.style.animation = 'none'
    box.append(
      swordholderIcon(failed ? 'drop' : 'antenna', 4),
      el('b', failed ? '威慑失败' : '引力波广播发出')
    )
    const who = this.name(v.swordholder)
    const d = v.decision
    box.append(
      el(
        'small',
        failed
          ? d
            ? `${who} 没有按下开关。水滴摧毁了引力波天线，人类将迁往澳大利亚。`
            : `${who} 到最后也没有按下开关。水滴摧毁了引力波天线，人类将迁往澳大利亚。`
          : `${who} 按下了开关。三体世界的坐标传遍宇宙，水滴转向离去。`
      )
    )
    if (d?.text) box.append(el('p', `「${d.text}」`, 'sh-quote'))
    if (d?.reason) box.append(this.mind(d.reason))
    return box
  }
}
