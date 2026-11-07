// 动态：只放小镇里发生的事——世界日志、村民想法、台词与本地状态变化。
// 模型请求记录（种类 model）在消耗页看，这里直接不收。
// 分类：想法、台词从名册里新出现的那一条记下；重要事件看事件自带的 alert（见 importantEvents.ts）。
// 收起时最近两条浮在地图左下（旧的一条淡一些）；有重要事件时只停它一条，普通事件挤不掉它，
// 直到来了新的重要事件或玩家展开、关掉。「全部动态」展开成一块浮板，可以按对话、想法、重要筛选。

import { triggerLabel } from './display'
import { type ServerMsg } from './protocol'
import type { RosterFrame } from './shell/panel'
import { $, query } from './dom'
import { iconLabel } from './game/icons'
import { displayClock, playerText, shortClock } from './format'
import { isCompact } from './platform'
import { detailsOf, importantEvent, importantLine, type ImportantEvent } from './importantEvents'

interface TownEvent {
  id: number
  clock: string
  alert: boolean
  text: string
  /** 想法行：text 是想法原文，who 是谁的想法，trigger 是触发标签 */
  thought?: { who: string; trigger: string }
  /** 台词行：text 是「名字：台词」 */
  speech?: boolean
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

  /** 上一行的天数：手机上同一天里只在第一行写「第 N 天」，其余只写时刻，省出一截宽度 */
  let lastDay = ''
  function clockText(at: string) {
    const [day, time] = at.split(' ')
    const repeat = day === lastDay && !!time
    lastDay = day
    return repeat && isCompact() ? time : displayClock(at)
  }

  function rowOf(e: TownEvent): HTMLElement {
    const div = document.createElement('div')
    if (e.alert) div.className = 'alert'
    const t = document.createElement('span')
    t.className = 'ev-clock'
    t.textContent = clockText(e.clock)
    if (e.thought) {
      div.className = 'thought'
      const q = document.createElement('span')
      q.className = 'ev-thought'
      q.textContent = `${e.thought.who}：「${playerText(e.text)}」`
      const tag = document.createElement('span')
      tag.className = 'ev-trigger'
      tag.textContent = e.thought.trigger
      div.append(t, q, tag)
      return div
    }
    if (e.speech) div.className = 'speech'
    div.append(t, document.createTextNode(playerText(e.text)))
    if (e.important) {
      div.className = 'alert important'
      if (e.important.detail) div.append(detailsOf(e.important.detail))
    }
    return div
  }

  function matches(e: TownEvent) {
    if (filter === 'all') return true
    if (filter === 'thought') return !!e.thought
    if (filter === 'speech') return !!e.speech
    return !!e.important
  }

  const lineOf = (e: TownEvent) =>
    e.thought ? `${e.thought.who}：「${playerText(e.text)}」` : playerText(e.text)
  /** 收起时的两条：有停住的重要事件就只显示它，否则显示最新两条 */
  function showLatest() {
    const e = pinned ?? store.at(-1)
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
    for (const e of store) if (matches(e)) list.appendChild(rowOf(e))
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
      list.appendChild(rowOf(event))
      while (list.childElementCount > MAX_EVENTS) list.firstElementChild?.remove()
    }
    maybeScroll()
  }

  function push(text: string, alert: boolean, at?: string) {
    add({ clock: at, alert, text: withoutClock(text) })
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
          add({ clock: shortClock(s.at), alert: false, text: `${m.name}：${s.text}`, speech: true })
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
        else push(msg.text, false, msg.clock)
        return true
      }
      return false
    },
  }
}
