// 动态：只放小镇里发生的事——世界日志、村民想法、台词与本地状态变化。
// 模型请求记录（种类 model）在消耗页看，这里直接不收。
// 分类：想法、台词从名册里新出现的那一条记下；玩法里的发言（议事、狼人频道这类）是带「一段话」
// 标记（speech）的世界日志，和台词一起算「对话」；重要事件看事件自带的 alert（见 importantEvents.ts）。
// 收起时最近两条浮在地图左下（旧的一条淡一些）；有重要事件时只停它一条，普通事件挤不掉它，
// 直到来了新的重要事件或玩家展开、关掉。「全部动态」展开成一块浮板，可以按对话、想法、重要筛选。
// 列表按天分段，一天只写一次「第 N 天」；对话和想法名字单独一行、正文另起，世界里的事一行小字。

import { triggerLabel } from './display'
import { type ServerMsg } from './protocol'
import type { RosterFrame } from './shell/panel'
import { $, query } from './dom'
import { iconLabel } from './game/icons'
import { displayClock, playerText, shortClock } from './format'
import { detailsOf, importantEvent, importantLine, type ImportantEvent } from './importantEvents'

/** 一段话：谁说的、说了什么；玩法里的发言还有座号和场合 */
interface Said {
  who: string
  text: string
  seat?: number
  occasion?: string
}

interface TownEvent {
  id: number
  clock: string
  alert: boolean
  /** 一行的写法：收起时的两条用它 */
  text: string
  /** 想法行：text 是想法原文，who 是谁的想法，trigger 是触发标签 */
  thought?: { who: string; trigger: string }
  /** 对话行（台词、玩法里的发言）：text 是「名字：台词」或日志原文，列表按 say 分行排 */
  say?: Said
  /** 重要事件：text 已换成平实写法，原文在 important.detail */
  important?: ImportantEvent
}

export interface EventsHandle {
  /** 本地事件（保存结果、连接断开、需求跨级），时间戳用当前模拟时钟 */
  pushLocal(text: string, alert?: boolean): void
  /** 消化 ws 的 event 消息；返回是否已处理 */
  handleMsg(msg: ServerMsg): boolean
  /** 名册：更新当前模拟时钟，新台词记为对话行，新想法记为想法行 */
  roster(frame: RosterFrame): void
  /** 重要事件到达时通知（提示卡） */
  onImportant(fn: (clock: string, important: ImportantEvent) => void): void
  /** 最近 n 条（新在前），供村民信息栏「最近变化」使用 */
  recent(n: number): TownEvent[]
  /** roster 到达时更新当前模拟时钟 */
  setClock(clock: string): void
  /** 世界重置：此后 recent() 只看重置之后的条目（时间线本身保留，作历史） */
  markReset(): void
  /** 展开或收起完整事件列表 */
  expanded(): boolean
  expand(): void
  collapse(): void
}

type Filter = 'all' | 'speech' | 'thought' | 'important'

const MAX_EVENTS = 300
/** 服务端部分事件文本自带「[D1 07:17]」前缀，与左侧 ev-clock 重复，显示前剥掉 */
const withoutClock = (text: string) => text.replace(/^\[D\d+\s+\d{1,2}:\d{2}(?::\d{2})?\]\s*/, '')

/** game：游戏界面的展开、收起钮画图标 */
export function initEvents(game: boolean): EventsHandle {
  const latestBar = $('event-latest')
  const latestText = $('event-latest-text')
  const latestLine = latestText.closest<HTMLElement>('.event-line') ?? latestText
  const prevText = $('event-prev')
  const dismiss = $('event-latest-dismiss')
  const full = $('event-full')
  const list = $('event-list')
  const autoscroll = query<HTMLInputElement>(document, '#event-autoscroll')

  let clock = '--:--'
  let filter: Filter = 'all'
  let autoPaused = false // 用户上翻后暂停自动滚动，回到底部自动恢复
  let nextId = 1
  let resetAt = 0 // 最近一次重置时的事件 id 水位
  let pinned: TownEvent | null = null // 收起时停住的重要事件
  let notify: (clock: string, important: ImportantEvent) => void = () => {}
  const spoken = new Map<string, string>() // 村民 id → 最近记下的台词编号
  const thoughts = new Map<string, string>() // 村民 id → 最近记下的想法
  const store: TownEvent[] = []

  /** 列表里上一行的天数：换了天先插一条「第 N 天」，行里只写时刻 */
  let lastDay = ''
  function append(e: TownEvent) {
    const [day, time] = e.clock.split(' ')
    if (time && day !== lastDay) {
      lastDay = day
      const head = document.createElement('div')
      head.className = 'ev-day'
      head.textContent = displayClock(day)
      list.appendChild(head)
    }
    list.appendChild(rowOf(e, time || displayClock(e.clock)))
  }

  const el = (tag: string, text: string, className = '') => {
    const node = document.createElement(tag)
    node.textContent = text
    if (className) node.className = className
    return node
  }

  /** 对话、想法：名字一行（座号、场合或想法的来由、时刻），正文另起一段 */
  function paragraph(className: string, head: Node[], body: string) {
    const div = el('div', '', className)
    const heading = el('div', '', 'ev-head')
    heading.append(...head)
    div.append(heading, el('p', body))
    return div
  }

  function rowOf(e: TownEvent, time: string): HTMLElement {
    const clock = el('span', time, 'ev-clock')
    if (e.thought)
      return paragraph(
        'ev-think',
        [el('b', e.thought.who), el('em', e.thought.trigger), clock],
        `「${playerText(e.text)}」`
      )
    if (e.say) {
      const { who, seat, occasion, text } = e.say
      const head = [el('b', who)]
      if (seat) head.unshift(el('i', String(seat)))
      if (occasion) head.push(el('em', occasion))
      return paragraph('ev-say', [...head, clock], playerText(text))
    }
    const div = el('div', '', 'ev-line')
    if (e.alert) div.classList.add('alert')
    if (e.important) div.classList.add('important')
    div.append(clock, playerText(e.text))
    if (e.important?.detail) div.append(detailsOf(e.important.detail))
    return div
  }

  /** 列表最多留 MAX_EVENTS 行：先删最早一天里最早的一行，这一天删空了再删它的天头 */
  function trim() {
    while (list.childElementCount > MAX_EVENTS) {
      const first = list.firstElementChild!
      const next = first.nextElementSibling
      const keepDay =
        first.classList.contains('ev-day') && next && !next.classList.contains('ev-day')
      const oldest = keepDay ? next : first
      oldest.remove()
    }
  }

  function matches(e: TownEvent) {
    if (filter === 'all') return true
    if (filter === 'thought') return !!e.thought
    if (filter === 'speech') return !!e.say
    return !!e.important
  }

  const lineOf = (e: TownEvent) =>
    e.thought ? `${e.thought.who}：「${playerText(e.text)}」` : playerText(e.text)
  /** 收起时的两条：有停住的重要事件就只显示它，否则显示最新两条 */
  function showLatest() {
    const e = pinned ?? store.at(-1)
    // 还没有动态时这一行藏起来，只留「全部动态」
    latestLine.hidden = !e
    latestText.textContent = !e ? '暂无事件' : lineOf(e)
    const prev = pinned ? undefined : store.at(-2)
    prevText.hidden = !prev
    prevText.textContent = prev ? lineOf(prev) : ''
    prevText.className = prev?.alert ? 'alert' : ''
    latestText.className = pinned
      ? 'alert important'
      : e?.alert
        ? 'alert'
        : e?.thought
          ? 'thought'
          : ''
    dismiss.hidden = !pinned
  }

  function unpin() {
    pinned = null
    showLatest()
  }

  function rerender() {
    list.replaceChildren()
    lastDay = ''
    for (const e of store) if (matches(e)) append(e)
    showLatest()
    maybeScroll(true)
  }

  function maybeScroll(force = false) {
    if (full.hidden) return
    if (force || (autoscroll.checked && !autoPaused)) {
      autoPaused = false
      list.scrollTop = list.scrollHeight
    }
  }

  function add(e: Omit<TownEvent, 'id' | 'clock'> & { clock?: string }) {
    const event: TownEvent = { ...e, id: nextId++, clock: e.clock ?? clock }
    store.push(event)
    while (store.length > MAX_EVENTS) store.shift()
    if (event.important) {
      pinned = full.hidden ? event : null
      notify(event.clock, event.important)
    }
    showLatest()
    if (!full.hidden && matches(event)) {
      append(event)
      trim()
    }
    maybeScroll()
  }

  function push(text: string, alert: boolean, at?: string, say?: Said) {
    add({ clock: at, alert, text: withoutClock(text), say })
  }

  function expand() {
    pinned = null
    full.hidden = false
    latestBar.hidden = true
    rerender()
  }
  function collapse() {
    full.hidden = true
    latestBar.hidden = false
    showLatest()
  }
  if (game) {
    iconLabel($('event-expand'), 'status', '查看事件', true)
    // 收起钮：原型为「收起 ×」文字钮，不用箭头图标
    iconLabel($('event-collapse'), 'close', '收起')
  }
  $('event-expand').addEventListener('click', expand)
  $('event-collapse').addEventListener('click', collapse)
  dismiss.addEventListener('click', unpin)
  for (const b of document.querySelectorAll<HTMLButtonElement>('.event-filter')) {
    b.addEventListener('click', () => {
      const f = b.dataset.f
      filter = f === 'speech' || f === 'thought' || f === 'important' ? f : 'all'
      document.querySelectorAll('.event-filter').forEach((x) => x.classList.toggle('on', x === b))
      rerender()
    })
  }
  autoscroll.addEventListener('change', () => {
    autoPaused = false
    maybeScroll()
  })
  list.addEventListener('scroll', () => {
    autoPaused = list.scrollTop + list.clientHeight < list.scrollHeight - 8
  })

  return {
    expanded: () => !full.hidden,
    expand,
    collapse,
    pushLocal: (text, alert = false) => push(text, alert),
    recent: (n) =>
      store
        .filter((e) => e.id > resetAt)
        .slice(-n)
        .reverse(),
    setClock: (c) => {
      clock = c
    },
    onImportant: (fn) => {
      notify = fn
    },
    roster({ msg, residents }) {
      clock = msg.clock
      const minutes = msg.sim_minutes
      // 与气泡同一条件：刚说的或还在交谈中的，才算新台词；首次连上时的旧台词不补记
      for (const { member: m } of residents) {
        const s = m.speech
        if (!s) continue
        const key = `${s.chat_id}:${s.seq}`
        if (spoken.get(m.id) === key) continue
        spoken.set(m.id, key)
        if (minutes - s.at <= 2 || m.chat)
          add({
            clock: shortClock(s.at),
            alert: false,
            text: `${m.name}：${s.text}`,
            say: { who: m.name, text: s.text },
          })
      }
      // 想法同气泡：只记有心声的那种（只在查看或记目标的轮次不冒泡，也不记），同样不补记旧的
      for (const { member: m } of residents) {
        const t = m.thought
        if (!t?.line) continue
        const key = `${t.sim_minutes}|${t.text}`
        if (thoughts.get(m.id) === key) continue
        thoughts.set(m.id, key)
        if (minutes - t.sim_minutes <= 2)
          add({
            clock: shortClock(t.sim_minutes),
            alert: false,
            text: t.text,
            thought: { who: m.name, trigger: triggerLabel(t.trigger_info) },
          })
      }
    },
    markReset: () => {
      resetAt = nextId - 1
      spoken.clear()
      thoughts.clear()
      unpin()
    },
    handleMsg(msg) {
      if (msg.type === 'event') {
        if (msg.kind === 'model') return true
        const important =
          msg.alert && msg.actor
            ? importantEvent(msg.alert, msg.actor, withoutClock(msg.text))
            : null
        if (important)
          add({ clock: msg.clock, alert: true, text: importantLine(important), important })
        else {
          // 玩法里的一段话：发言人、座号、场合都在标记里，正文照旧写在一行里给收起时看
          const said = msg.speech && msg.actor ? { ...msg.speech, who: msg.actor.name } : undefined
          push(msg.text, false, msg.clock, said)
        }
        return true
      }
      return false
    },
  }
}
