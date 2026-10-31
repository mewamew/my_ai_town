// 一次性提示：第一次遇到时各出现一次，一次只出一条，不挡操作；点「知道了」或者做了提示里说的事
// 就不再出现。看过的记在本机。手机和电脑说法不同：手机讲手势、指底部的「动态」，电脑讲鼠标键盘、
// 指顶栏的「帮助」和事件栏的「展开」。
import { isWaiting } from '../display'
import { button, el } from '../dom'
import type { GameMap } from '../gameMap'
import { visibleMapRect } from '../mapView'
import { isCompact } from '../platform'
import type { RosterFrame, ShellPanel } from '../shell/panel'

const KEY = 'town:tips'
/** 两条提示之间至少隔这么久（毫秒）：刚进地图时几件事同时发生，不要一条接一条地弹 */
const GAP = 20_000
type TipId = 'gesture' | 'waiting' | 'tap' | 'events'
const TEXT: Record<TipId, string> = {
  gesture: '单指拖动地图，两指缩放，两指一起上下拖动调俯角。按住物品可以看名字。',
  waiting: '名字旁边出现三个小点，是居民在等模型回复，通常几秒后就会行动。',
  tap: '点一个人，看看此刻在想什么；脚下的按钮能说话、跟随，点「资料」看详情。',
  events: '错过的对话和想法，都在下面的「动态」里。',
}
const DESK_TEXT: Partial<Record<TipId, string>> = {
  gesture: '拖动地图看各处，滚轮缩放，空格暂停或继续。想再看一遍向导，点这里的「帮助」。',
  events: '错过的对话和想法，都在下面的事件栏里，点「展开」看全部。',
}

function load(): Set<TipId> {
  try {
    return new Set(JSON.parse(localStorage.getItem(KEY) ?? '[]'))
  } catch {
    return new Set()
  }
}

export function createTips(map: GameMap) {
  const seen = load()
  const queue: { id: TipId; target?: string }[] = []
  let current: { id: TipId; target?: string } | null = null
  let frame = 0
  /** 上一条提示收起的时间；第一条（手势）不用等 */
  let lastDone = -GAP
  let waitTimer = 0

  const box = el('div', '', 'coach')
  box.hidden = true
  box.setAttribute('role', 'status')
  const text = el('p')
  const row = el('div', '', 'coach-row')
  row.append(
    el('small', '新手提示 · 只出现一次'),
    button('知道了', () => current && done(current.id))
  )
  const arrow = el('i', '', 'coach-arrow')
  box.append(text, row, arrow)
  document.body.append(box)

  const save = () => {
    try {
      localStorage.setItem(KEY, JSON.stringify([...seen]))
    } catch {
      // 本地存储不可用时下次还会再出现
    }
  }
  function want(id: TipId, target?: string) {
    if (seen.has(id) || current?.id === id || queue.some((q) => q.id === id)) return
    queue.push({ id, target })
    next()
  }
  function next() {
    if (current || !queue.length) return
    const wait = lastDone + GAP - performance.now()
    if (wait > 0) {
      clearTimeout(waitTimer)
      waitTimer = window.setTimeout(next, wait)
      return
    }
    current = queue.shift()!
    text.textContent = (!isCompact() && DESK_TEXT[current.id]) || TEXT[current.id]
    loop()
  }
  function done(id: TipId) {
    if (!seen.has(id)) {
      seen.add(id)
      save()
    }
    const i = queue.findIndex((q) => q.id === id)
    if (i >= 0) queue.splice(i, 1)
    if (current?.id !== id) return
    current = null
    box.hidden = true
    cancelAnimationFrame(frame)
    lastDone = performance.now()
    next()
  }

  /** 页面盖住地图、向导或对话框开着时先不出；指着人的提示在人被抽屉挡住时也先藏起来 */
  function covered() {
    return (
      !!document.querySelector(
        'dialog[open], .guide:not([hidden]), .m-pop:not([hidden]), .help-menu:not([hidden]), #event-full:not([hidden])'
      ) ||
      [...document.querySelectorAll<HTMLElement>('.page-view, #props-view')].some(
        (v) => !v.hidden && v.getClientRects().length
      ) ||
      document.documentElement.classList.contains('avatar-controlling')
    )
  }
  /** 地图露出来的那块；电脑上右栏是地图旁边的一栏，栏下面的人看不见 */
  function visibleRect() {
    const map = document.getElementById('map')
    return map ? visibleMapRect(map) : { left: 0, top: 0, right: innerWidth, bottom: innerHeight }
  }
  const visibleBottom = () => visibleRect().bottom
  function place() {
    if (!current) return
    if (covered()) {
      box.hidden = true
      return
    }
    let x: number,
      y: number,
      below = false,
      free = false,
      /** 指着顶栏上的入口：放在它下面 */
      under = false
    const desk = !isCompact()
    const top = (document.getElementById('topbar')?.getBoundingClientRect().bottom ?? 0) + 8
    const help = desk ? document.getElementById('open-help') : null
    if (current.id === 'gesture' && help?.offsetParent) {
      const r = help.getBoundingClientRect()
      under = true
      x = r.left + r.width / 2
      y = r.bottom
    } else if (current.id === 'gesture') {
      free = true
      x = innerWidth / 2
      const ticker = document.getElementById('event-bar')
      y =
        (ticker && ticker.offsetParent ? ticker.getBoundingClientRect().top : visibleBottom()) - 12
    } else if (current.id === 'events') {
      const dock = desk
        ? document.getElementById('event-expand')
        : document.querySelector<HTMLElement>('.mobile-dock [data-dock="events"]')
      const r = dock?.getBoundingClientRect()
      // 手机上村民卡开着时指向底部入口会盖住卡片，等卡片收起再说
      if (!r || !dock?.offsetParent || (!desk && !document.getElementById('info-panel')?.hidden)) {
        box.hidden = true
        return
      }
      x = r.left + r.width / 2
      y = r.top + 4
    } else {
      const head = current.target ? map.getScreenBox?.(current.target) : undefined
      const view = visibleRect()
      if (
        !head ||
        head.top < top ||
        head.feet > view.bottom ||
        head.x < view.left + 12 ||
        head.x > view.right - 12
      ) {
        box.hidden = true
        return
      }
      x = head.x
      y = head.top - 6
    }
    box.hidden = false
    box.classList.toggle('free', free)
    const w = box.offsetWidth,
      h = box.offsetHeight
    const left = Math.max(12, Math.min(innerWidth - w - 12, x - w / 2))
    let boxTop = under ? y + 10 : y - h - 10
    if (under) below = true
    else if (!free && boxTop < top) {
      boxTop = y + 46
      below = true
    }
    box.classList.toggle('below', below)
    box.style.left = `${left}px`
    box.style.top = `${boxTop}px`
    box.style.setProperty('--ax', `${Math.max(18, Math.min(w - 18, x - left))}px`)
  }
  function loop() {
    place()
    if (current) frame = requestAnimationFrame(loop)
  }

  // 做了提示里的事：拖过地图、展开过事件列表；点选村民由外壳告诉这里（picked）
  let dragFrom: [number, number] | null = null
  document.getElementById('map')?.addEventListener('pointerdown', (e) => {
    dragFrom = [e.clientX, e.clientY]
  })
  document.getElementById('map')?.addEventListener('pointermove', (e) => {
    if (
      dragFrom &&
      e.buttons &&
      Math.hypot(e.clientX - dragFrom[0], e.clientY - dragFrom[1]) > 40
    ) {
      dragFrom = null
      if (current?.id === 'gesture') done('gesture')
    }
  })
  const watch = (id: string, tip: TipId) => {
    const node = document.getElementById(id)
    if (node)
      new MutationObserver(() => !node.hidden && done(tip)).observe(node, {
        attributes: true,
        attributeFilter: ['hidden'],
      })
  }
  watch('event-full', 'events')

  const panel: ShellPanel = {
    roster({ residents }: RosterFrame) {
      const waiting = residents.find((r) => isWaiting(r.member))
      if (waiting) want('waiting', waiting.member.id)
      const thinking = residents.find((r) => r.member.thought)
      if (thinking) want('tap', thinking.member.id)
      if (residents.some((r) => r.member.speech)) want('events')
    },
  }

  return {
    panel,
    /** 进了地图：先讲手势 */
    start: () => want('gesture'),
    /** 玩家在地图上点了一个人：「点一个人」那条算做过了。开局替玩家选中的第一位不算 */
    picked: () => done('tap'),
    /** 「更多」或「帮助」里重新显示 */
    reset() {
      seen.clear()
      save()
    },
  }
}
