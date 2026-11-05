import type { WorldHold } from '../protocol'
import type { ChatEntry } from '../chat/types'
import type {
  AvatarCommand,
  AvatarInteraction,
  AvatarState,
  InteractionCommand,
  InteractionKind,
} from './types'
import { panelButton, pendingTalk, personName, runningTalk, runningWalk } from './view'
import { button, el } from '../dom'
import { clock } from '../format'
import { isTouch } from '../platform'
// 交谈面板：收到的邀请、进行中的对话或同行、交谈里的提议、附近的人。发言输入框由控制器持有。

type Execute = (c: AvatarCommand) => Promise<boolean>
type Actor = NonNullable<AvatarState['actor']>

interface Notices {
  holds: WorldHold[]
  results: ReadonlyMap<string, string>
  dismiss: (id: string) => void
  usage: () => void
  settings: () => void
  localeName: (id: string) => string
  /** 约时间可选的见面地点 */
  places: { id: string; name: string }[]
  /** 世界时刻（分钟） */
  minutes: number
}

/** 一次重绘里各部分共用的东西 */
interface ChatView {
  state: AvatarState
  actor: Actor
  /** 控制中且世界在走：可以回应和发言 */
  active: boolean
  /** 另外还不在忙：可以发起邀请、加入交谈 */
  idle: boolean
  execute: Execute
  interact: (command: InteractionCommand) => void
  nameOf: (id: string) => string
  localeName: (id: string) => string
  notices: Notices
  /** 在面板里加一段 */
  block: (className: string) => HTMLElement
}

/** 世界暂停时的说明；因额度或故障暂停时给出原因和去处 */
function pauseNotice(notice: HTMLElement, notices: Notices) {
  notice.setAttribute('role', 'status')
  notice.append(
    el('strong', notices.holds.length ? '世界因故暂停，暂时无法交谈' : '世界已暂停，继续后可发言')
  )
  for (const hold of notices.holds) notice.append(el('p', `${hold.resident}：${hold.reason}`))
  if (notices.holds.length)
    notice.append(
      button('查看消耗', notices.usage),
      button('前往设定（将离开化身）', notices.settings)
    )
}

/** 别人想和你亲近时卡片上的说法 */
const TOUCH_WISH = { hold_hands: '牵你的手', lean: '靠着你', hug: '抱抱你' } as const

/** 一张邀请卡：别人邀请我时回应，我邀请别人时等待或取消 */
function inviteCard(v: ChatView, i: AvatarInteraction) {
  const { interact, nameOf } = v
  const card = v.block('avatar-invite')
  const row = el('div')
  row.className = 'avatar-row'
  if (i.partner === v.actor.id) {
    const what =
      i.kind.kind === 'talk'
        ? '和你聊聊'
        : i.kind.kind === 'walk'
          ? walkWish(v, i.kind)
          : i.kind.kind === 'appointment'
            ? `约你${appointmentText(v, i.kind)}`
            : i.kind.kind === 'touch'
              ? TOUCH_WISH[i.kind.gesture]
              : '送你东西'
    card.append(el('p', `${nameOf(i.initiator)}想${what}${i.message ? `：${i.message}` : ''}`))
    const reply = (accept: boolean, message: string) =>
      interact({ operation: 'reply', interaction_id: i.id, accept, message })
    const yes = panelButton('好', () => reply(true, '好。'), !v.idle)
    yes.className = 'avatar-primary-small'
    const touch = i.kind.kind === 'touch'
    row.append(
      yes,
      touch
        ? panelButton('躲开', () => reply(false, '别这样。'), !v.active)
        : panelButton('这次先不了', () => reply(false, '这次先不了，谢谢。'), !v.active)
    )
  } else {
    const partner = nameOf(i.partner)
    card.append(el('p', i.response_error ? `${partner}回应失败` : `等待${partner}回应`))
    if (i.response_error) card.append(el('p', i.response_error))
    row.append(
      panelButton(
        '取消邀请',
        () => interact({ operation: 'cancel', interaction_id: i.id }),
        !v.active
      )
    )
  }
  card.append(row)
}

function turnText(state: AvatarState, talk: AvatarInteraction) {
  if (!state.speed) return '暂停期间不计发言等待时间'
  if (talk.can_speak) return '轮到你了 · 一分钟不说话会自动切到只听'
  if (talk.kind.kind === 'walk' && talk.can_request_turn) return '路上没人说话，想说什么直接说'
  return talk.can_request_turn ? '你在只听，想说话就点「我想说」' : '等对方说完'
}

/** 同行的说法：「陈默带路，去陈默家」 */
function walkText(v: ChatView, kind: Extract<InteractionKind, { kind: 'walk' }>) {
  const who = kind.leader === v.actor.id ? '你带路' : `${v.nameOf(kind.leader)}带路`
  return kind.locale ? `${who}，去${v.localeName(kind.locale)}` : who
}
/** 收到的同行邀请或提议想做什么：「一起走（你带路）」 */
function walkWish(v: ChatView, kind: Extract<InteractionKind, { kind: 'walk' }>) {
  return `一起走（${walkText(v, kind)}）`
}
/** 约定的说法：「第 13 天 14:00 在小广场见」 */
function appointmentText(v: ChatView, kind: Extract<InteractionKind, { kind: 'appointment' }>) {
  return `${clock(kind.at)} 在${v.localeName(kind.locale)}见`
}
/** 提议的说法：一起走或约时间 */
function proposalText(v: ChatView, kind: InteractionKind) {
  if (kind.kind === 'walk') return walkWish(v, kind)
  if (kind.kind === 'appointment') return `约好${appointmentText(v, kind)}`
  return '一起做件事'
}

/** 已经约好的事：什么时候在哪儿见、和谁，可以取消 */
function appointments(v: ChatView) {
  const kept = (v.state.interactions ?? []).filter(
    (i) => i.status === 'running' && i.kind.kind === 'appointment'
  )
  if (!kept.length) return
  const list = v.block('avatar-appointments')
  list.append(el('h4', '约定'))
  for (const i of kept) {
    if (i.kind.kind !== 'appointment') continue
    const other = i.initiator === v.actor.id ? i.partner : i.initiator
    const row = el('div')
    row.className = 'avatar-person'
    row.append(
      el('span', `${appointmentText(v, i.kind)} · 和${v.nameOf(other)}`),
      panelButton(
        '取消约定',
        () => v.interact({ operation: 'cancel', interaction_id: i.id }),
        !v.active
      )
    )
    list.append(row)
  }
}

// 约时间的选择在重画之间保留：面板每有新话就重画，选到一半不该被清掉
let appointPlace = ''
let appointLater = '一小时后'

/** 约时间可选的时刻：一两个钟头以后、明早、明天中午；超出一天的不列（约定最多约到一天以内） */
function laterChoices(now: number) {
  const day = Math.floor(now / 1440) * 1440
  const round = (m: number) => Math.ceil(m / 10) * 10
  return [
    { label: '一小时后', at: round(now + 60) },
    { label: '两小时后', at: round(now + 120) },
    { label: '三小时后', at: round(now + 180) },
    { label: '明早八点', at: day + 1440 + 480 },
    { label: '明天中午', at: day + 1440 + 720 },
  ].filter((c) => c.at >= now + 10 && c.at + 30 <= now + 1440)
}

/** 两人交谈时约个以后见面的时间地点：在交谈里提议，对方答应才算约好 */
function appointRow(v: ChatView, talk: AvatarInteraction) {
  const others = (talk.members ?? []).filter((id) => id !== v.actor.id)
  const { places, minutes } = v.notices
  if (talk.kind.kind !== 'talk' || others.length !== 1 || talk.proposal || !places.length) return
  const choices = laterChoices(minutes)
  if (!choices.length) return
  if (!places.some((p) => p.id === appointPlace)) appointPlace = places[0].id
  const row = v.block('avatar-textacts avatar-appoint')
  const place = el('select')
  place.setAttribute('aria-label', '见面地点')
  for (const p of places) place.append(new Option(p.name, p.id, false, p.id === appointPlace))
  place.onchange = () => (appointPlace = place.value)
  const later = el('select')
  later.setAttribute('aria-label', '见面时间')
  for (const c of choices)
    later.append(
      new Option(`${c.label}（${clock(c.at).slice(-5)}）`, c.label, false, c.label === appointLater)
    )
  later.onchange = () => (appointLater = later.value)
  const propose = () => {
    const c = choices.find((c) => c.label === later.value) ?? choices[0]
    v.interact({
      operation: 'propose',
      interaction_id: talk.id,
      interaction: { kind: 'appointment', locale: place.value, at: c.at },
      message: `${c.label}在${v.localeName(place.value)}见，行吗？`,
    })
  }
  row.append(el('span', '约时间'), place, later, panelButton('约好', propose, !v.active))
}

/** 聊天记录里的过程条目怎么说 */
function eventText(e: ChatEntry) {
  switch (e.kind) {
    case 'joined':
      return `${e.name}加入了`
    case 'left':
      return `${e.name}离开了：${e.text}`
    case 'proposed':
      return `${e.name}提议${e.text}`
    case 'accepted':
      return `${e.name}答应了`
    case 'declined':
      return `${e.name}${e.text}`
    default:
      return e.text || '交谈结束'
  }
}

/** 交谈里等人回答的提议：问我的给「好」「算了」，我提的可以撤回 */
function proposalCard(v: ChatView, talk: AvatarInteraction) {
  const p = talk.proposal
  if (!p) return
  const { interact, active } = v
  const card = v.block('avatar-invite avatar-proposal')
  const row = el('div')
  row.className = 'avatar-row'
  const walk = p.interaction.kind === 'walk' ? p.interaction : null
  if (p.to === v.actor.id) {
    card.append(el('p', `${v.nameOf(p.by)}想${proposalText(v, p.interaction)}`))
    const lead = walk?.leader === v.actor.id
    card.append(
      el(
        'p',
        !walk
          ? '答应后双方照常活动，到点前会提醒'
          : lead
            ? '答应后交谈结束，他跟在你身后'
            : '答应后自动跟着他走'
      )
    )
    const yes = panelButton(
      !walk ? '好，到时见' : lead ? '好，跟我来' : '好，走吧',
      () => interact({ operation: 'accept', interaction_id: talk.id, message: '好。' }),
      !active
    )
    yes.className = 'avatar-primary-small'
    row.append(
      yes,
      panelButton(
        '算了',
        () =>
          interact({ operation: 'decline', interaction_id: talk.id, message: '算了，改天吧。' }),
        !active
      )
    )
  } else {
    card.append(el('p', `等${v.nameOf(p.to)}回答：${proposalText(v, p.interaction)}`))
    row.append(
      panelButton(
        '撤回',
        () => interact({ operation: 'decline', interaction_id: talk.id, message: '' }),
        !active
      )
    )
  }
  card.append(row)
}

/** 两人交谈时的「一起走」：跟我来（我带路）、你带路（他带路）。都在交谈里提议，对方答应才走 */
function togetherRow(v: ChatView, talk: AvatarInteraction) {
  const others = (talk.members ?? []).filter((id) => id !== v.actor.id)
  if (talk.kind.kind !== 'talk' || others.length !== 1 || talk.proposal) return
  const [partner] = others
  const propose = (leader: string, message: string) =>
    v.interact({
      operation: 'propose',
      interaction_id: talk.id,
      interaction: { kind: 'walk', leader },
      message,
    })
  const row = v.block('avatar-textacts avatar-together')
  row.append(
    el('span', '一起走'),
    panelButton('跟我来', () => propose(v.actor.id, '跟我来，我带你去。'), !v.active),
    panelButton('你带路', () => propose(partner, '你带路，我跟着你。'), !v.active)
  )
}

/** 进行中的交谈或同行：对白、轮到谁发言，以及只听、我想说、离开；同行另有到了、不跟了 */
function talkLog(v: ChatView, talk: AvatarInteraction) {
  const { actor: a, active, interact } = v
  const walk = runningWalk(v.state)
  if (walk) {
    const note = v.block('avatar-walk-note')
    note.append(
      el(
        'p',
        walk.leading
          ? `${walk.followers.map(v.nameOf).join('、')}跟着你${walk.locale ? ` · 去${v.localeName(walk.locale)}` : ''}`
          : `跟着${v.nameOf(walk.leader)}走${walk.locale ? ` · 去${v.localeName(walk.locale)}` : ''}`
      ),
      el(
        'p',
        walk.leading
          ? '你走到哪他们跟到哪，在一个地方停下一会儿就算到了；带着人时走得慢一些'
          : '自动跟着他走，到了地方同行自动结束；自己走动就不再自动跟，操作条上可以再打开'
      )
    )
  }
  const log = v.block('avatar-chatlog')
  for (const e of talk.entries ?? []) {
    if (e.kind === 'speech') {
      const b = el('div')
      b.className = e.actor === a.id ? 'avatar-bubble me' : 'avatar-bubble'
      b.append(el('small', e.actor === a.id ? '你' : e.name), document.createTextNode(e.text))
      log.append(b)
      continue
    }
    const ev = el('p', eventText(e))
    ev.className = 'avatar-chat-event'
    log.append(ev)
  }
  const turn = el('p', turnText(v.state, talk))
  turn.className = active && talk.can_speak ? 'avatar-turn on' : 'avatar-turn'
  log.append(turn)
  proposalCard(v, talk)
  togetherRow(v, talk)
  appointRow(v, talk)
  const acts = v.block('avatar-textacts')
  acts.append(
    panelButton(
      '只听',
      () => interact({ operation: 'listen', interaction_id: talk.id }),
      !active || !talk.can_speak
    ),
    panelButton(
      '我想说',
      () => void v.execute({ kind: 'request_turn', chat_id: talk.id, revision: a.revision }),
      !active || !talk.can_request_turn
    )
  )
  const leave = (message: string) =>
    interact({ operation: 'leave', interaction_id: talk.id, message })
  if (!walk) acts.append(panelButton('离开交谈', () => leave('我先走了，回头聊。'), !active))
  else if (walk.leading)
    acts.append(
      panelButton('到了', () => leave('到了。'), !active),
      panelButton('不用跟了', () => leave('不用跟了，你先忙吧。'), !active)
    )
  else acts.append(panelButton('不跟了', () => leave('我不跟了。'), !active))
}

/** 没在交谈时：附近的人（可邀请）和附近正在进行、可以加入的交谈 */
function nearbyPeople(v: ChatView) {
  const { state, idle, interact } = v
  const people = v.block('avatar-people')
  people.append(el('h4', '附近的人'))
  const list = state.nearby ?? []
  if (!list.length) {
    const p = el(
      'p',
      isTouch()
        ? '走到村民身边，地图上会出现「和某某交谈」的标签；点右下角的「交谈」或点标签发出邀请。'
        : '走到村民身边，地图上会出现「和某某交谈」的标签；按 E 或点标签发出邀请。'
    )
    p.className = 'dim'
    people.append(p)
  }
  for (const n of list) {
    const invitation = pendingTalk(state, n.id)
    const available = n.can_talk ?? n.available
    const row = el('div')
    row.className = 'avatar-person'
    const offer = () =>
      interact({
        operation: 'offer',
        partner_id: n.id,
        interaction: { kind: 'talk' },
        message: '你好，方便聊一会儿吗？',
      })
    row.append(
      el('span', n.activity ? `${n.name} · ${n.activity}` : n.name),
      panelButton(
        invitation ? '等待回应' : available ? '邀请交谈' : '暂时无法交谈',
        offer,
        !idle || !available || !!invitation
      )
    )
    people.append(row)
  }
  for (const c of state.nearby_chats ?? [])
    if (!c.members.includes(v.actor.id))
      people.append(
        c.leader
          ? panelButton(
              `跟上${v.nameOf(c.leader)}的同行（${c.members.length} 人）`,
              () => interact({ operation: 'join', interaction_id: c.id, message: '我也跟着去。' }),
              !idle
            )
          : panelButton(
              `加入附近的交谈（${c.members.length} 人）`,
              () =>
                interact({ operation: 'join', interaction_id: c.id, message: '我也想一起聊聊。' }),
              !idle
            )
      )
}

export function renderChat(
  root: HTMLElement,
  state: AvatarState,
  execute: Execute,
  openHistory: () => void,
  notices: Notices
) {
  const a = state.actor
  if (!a) return
  const active = state.controlled && state.speed > 0
  const view: ChatView = {
    state,
    actor: a,
    active,
    idle: active && !a.busy,
    execute,
    interact: (command) => void execute({ kind: 'interact', revision: a.revision, command }),
    nameOf: (id) => personName(state, undefined, id),
    localeName: notices.localeName,
    notices,
    block: (className) => {
      const s = el('section')
      s.className = className
      root.append(s)
      return s
    },
  }
  if (!state.speed) pauseNotice(view.block('avatar-pause-notice'), notices)
  for (const [id, text] of notices.results)
    view.block('avatar-invite-result').append(
      el('p', text),
      button('关闭这条结果', () => notices.dismiss(id))
    )
  for (const i of state.interactions ?? []) if (i.status === 'offered') inviteCard(view, i)
  appointments(view)
  const talk = runningTalk(state)
  if (talk) talkLog(view, talk)
  else nearbyPeople(view)
  view.block('avatar-textacts').append(button('完整交谈记录', openHistory))
}
