import type { WorldHold } from '../protocol'
import type { AvatarState } from './types'
import type { AvatarDeps } from './controller'

import { renderChat } from './chat'
import { renderBag } from './bag'
import { renderStatus } from './status'
import { actionButton, partnerNames, personName, runningTalk, runningWalk } from './view'
import { el } from '../dom'
import { gameIcon } from '../game/icons'
import { groupHolds } from '../holds'

import type { AvatarUI } from './ui'
import type { AvatarActions, AvatarTab } from './ui-types'
import { newId } from '../ids'
export interface AvatarPanelState {
  state: AvatarState | null
  online: boolean
  holds: WorldHold[]
  tab: AvatarTab | null
  invitationResults: Map<string, string>
  bagSelection: string | null
  /** 世界时刻（分钟），约时间用；不进面板签名，免得每拍重画 */
  minutes: number
}
/** 面板只在这些状态改变时重绘：坐标每拍都变，照坐标重绘会丢输入焦点和草稿 */
export function panelSignature(p: AvatarPanelState, controlling: boolean) {
  const { state, tab, bagSelection, holds, invitationResults } = p
  const a = state?.actor
  return JSON.stringify([
    tab,
    bagSelection,
    a?.revision,
    a?.inventory,
    a?.body,
    a?.needs,
    state?.recent,
    state?.goals,
    a?.activity,
    state?.speed,
    holds,
    [...invitationResults],
    state?.nearby,
    state?.props,
    state?.portals,
    state?.interactions,
    state?.nearby_chats,
    state?.feedback,
    state?.reading,
    state?.can_drop,
    controlling,
  ])
}
export function createAvatarPanels(ui: AvatarUI, deps: AvatarDeps, actions: AvatarActions) {
  const {
    map,
    localeName,
    places,
    send,
    resumeSpeed,
    openHistory,
    game,
    openUsage,
    openSettings,
    fixHold,
  } = deps
  const { execute, openTab, targets, stopMoving, render, selectBag, leave } = actions
  // 交谈中点开「告辞」后的几种说法；不在交谈里就收起
  let farewell = false
  const { me, meDot, meName, meSub, mid, bagCount, title, meta, body, profile, needsStrip } = ui
  // 状态每拍都会更新；保留内容没变的按钮，避免按下后、松开前被重建而丢失点击。
  function updateMid(next: HTMLElement[]) {
    for (let i = 0; i < next.length; i++) {
      const current = mid.children[i] as HTMLElement | undefined
      const incoming = next[i]
      if (!current) mid.append(incoming)
      else if (current.isEqualNode(incoming)) current.onclick = incoming.onclick
      else mid.replaceChild(incoming, current)
    }
    while (mid.children.length > next.length) mid.lastElementChild?.remove()
  }
  function renderHud(snapshot: AvatarPanelState) {
    const { state, online, holds } = snapshot
    const a = state?.actor
    if (!state || !a) return
    ui.paintDot(meDot, a.appearance.color)
    me.classList.toggle('is-possess', state?.mode === 'possession')
    meName.textContent = state?.mode === 'possession' ? `附身 · ${a.name}` : a.name
    // 原型附身模式：热栏上方四条需求数值条
    if (game && state?.mode === 'possession' && a.needs.length) {
      needsStrip.replaceChildren(
        ...a.needs.map((n) => {
          const item = el('span', `${n.need} ${Math.round(n.value)}`)
          item.className = 'avatar-need'
          if (n.value < 30) item.classList.add('low')
          return item
        })
      )
      needsStrip.hidden = false
    } else needsStrip.hidden = true
    const place = localeName(a.locus.locale)
    meSub.textContent = !online
      ? '连接已断开'
      : !state.speed
        ? `${place} · 世界已暂停`
        : `${place} · ${a.activity || '停留'}`
    if (state?.mode === 'possession') {
      const lowest = a.needs.reduce((low, n) => (n.value < low.value ? n : low), a.needs[0])
      meSub.textContent += ` · ${a.body?.limitation ?? ''}${lowest ? ` · ${lowest.need} ${lowest.value.toFixed(0)}` : ''}`
    }
    bagCount.textContent = String(a.inventory.used)
    const items: HTMLElement[] = []
    const talk = runningTalk(state)
    const walk = runningWalk(state)
    if (!talk || walk) farewell = false
    const interact = (command: Parameters<typeof execute>[0] & { kind: 'interact' }) =>
      void execute(command)
    const say = (operation: 'leave', message: string) =>
      talk &&
      interact({
        kind: 'interact',
        revision: a.revision,
        command: { operation, interaction_id: talk.id, message },
      })
    if (!state.speed && holds.length) {
      // 和地图上的提示卡同一个说法和修法；几种原因同时出现时先修第一种
      const [first] = groupHolds(holds)
      const fix = first.copy.actions[0]
      const go = actionButton(fix.label, undefined, () =>
        fixHold(fix.fix, first.holds[0].provider ?? '')
      )
      go.classList.add('main')
      items.push(el('span', `已暂停：${first.copy.short}`), go)
    } else if (!state.speed) {
      const resume = actionButton(
        state?.awaiting_arrival ? '等待到达 · 继续世界' : '继续世界',
        undefined,
        () => send({ type: 'set_speed', request_id: newId(), speed: resumeSpeed })
      )
      resume.classList.add('main')
      items.push(resume)
    } else if (state?.awaiting_arrival) {
      items.push(el('span', '等待村民到达，可随时交还 AI'))
    } else if (walk) {
      // 同行：带路时写谁跟着、到了和不用跟了；跟着走时写跟着谁、自动跟随和不跟了
      const names = walk.followers.map((id) => personName(state, walk.talk, id)).join('、')
      const leader = personName(state, walk.talk, walk.leader)
      const where = walk.locale ? ` · 去${localeName(walk.locale)}` : ''
      const chip = el('span', walk.leading ? `${names}跟着你${where}` : `跟着${leader}${where}`)
      chip.className = 'avatar-walk-chip'
      chip.onclick = () => openTab('chat')
      items.push(chip)
      if (walk.leading) {
        const done = actionButton('到了', undefined, () => say('leave', '到了。'))
        done.classList.add('main')
        items.push(
          done,
          actionButton('不用跟了', undefined, () => say('leave', '不用跟了。'))
        )
      } else {
        const on = actions.autoFollow() === walk.leader
        const toggle = actionButton(on ? '自动跟随：开' : '自动跟随：关', undefined, () =>
          actions.setAutoFollow(on ? null : walk.leader)
        )
        toggle.classList.toggle('on', on)
        items.push(
          toggle,
          actionButton('不跟了', undefined, () => say('leave', '我不跟了。'))
        )
      }
    } else if (talk) {
      const chatting = actionButton(`和${partnerNames(state, talk)}交谈中`, undefined, () =>
        openTab('chat')
      )
      chatting.classList.add('main')
      const toggle = actionButton(farewell ? '告辞 ▴' : '告辞 ▾', undefined, () => {
        farewell = !farewell
        render(true)
      })
      toggle.classList.toggle('on', farewell)
      items.push(chatting, toggle)
      if (farewell) {
        // 告辞的几种说法：对方听到的是这句话，而不是「走开了」；跟我来、你带路是提议一起走
        const others = (talk.members ?? []).filter((id) => id !== a.id)
        const propose = (leader: string, message: string) => {
          farewell = false
          interact({
            kind: 'interact',
            revision: a.revision,
            command: {
              operation: 'propose',
              interaction_id: talk.id,
              interaction: { kind: 'walk', leader },
              message,
            },
          })
        }
        const bye = (message: string) => {
          farewell = false
          say('leave', message)
        }
        items.push(actionButton('先走了，回头聊', undefined, () => bye('我先走了，回头聊。')))
        if (others.length === 1 && !talk.proposal)
          items.push(
            actionButton('跟我来', undefined, () => propose(a.id, '跟我来，我带你去。')),
            actionButton('你带路', undefined, () => propose(others[0], '你带路，我跟着你。'))
          )
        items.push(actionButton('改天再说', undefined, () => bye('改天再说吧。')))
      }
    } else if (a.busy) {
      const busy = el('span', `正在${a.activity}${a.remaining ? ` · ${a.remaining}` : ''}`)
      busy.className = 'avatar-busy'
      items.push(
        busy,
        actionButton('取消', undefined, () => void execute({ kind: 'stop' }))
      )
    } else {
      const main = targets().find((t) => t.prompt.key)
      if (main) {
        const b = actionButton(main.prompt.label, 'E', main.run)
        b.classList.add('main')
        items.push(b)
      } else {
        const tip = el('span', '点地图走过去，点人或东西互动')
        tip.className = 'avatar-hud-hint'
        items.push(tip)
      }
    }
    updateMid(items)
  }
  // 交谈记录贴着底部：停在最底下时，新的一句、弹出键盘把面板压矮，都保持最新一句看得见；
  // 往上翻看旧话时不打扰
  let pinned = true
  let shownTab: AvatarTab | null = null
  body.addEventListener('scroll', () => {
    pinned = body.scrollTop + body.clientHeight >= body.scrollHeight - 24
  })
  new ResizeObserver(() => {
    if (shownTab === 'chat' && pinned) body.scrollTop = body.scrollHeight
  }).observe(body)
  function renderPanel(snapshot: AvatarPanelState) {
    const { state, tab, holds, invitationResults, bagSelection } = snapshot
    const a = state?.actor
    if (!state || !a) return
    if (tab !== shownTab) pinned = true
    shownTab = tab
    const keep = body.scrollTop
    body.replaceChildren()
    if (tab === 'chat') {
      const talk = runningTalk(state)
      const walking = talk?.kind.kind === 'walk'
      title.textContent = talk
        ? `和${partnerNames(state, talk)}${walking ? '同行' : '交谈'}`
        : '交谈'
      meta.textContent = talk
        ? `${localeName(a.locus.locale)} · ${talk.members?.length ?? 2} 人`
        : '附近的人与邀请'
      renderChat(
        body,
        state,
        execute,
        () => {
          stopMoving()
          openHistory(a.id)
        },
        {
          holds,
          results: invitationResults,
          dismiss: (id) => {
            invitationResults.delete(id)
            render(true)
          },
          usage: openUsage,
          settings: openSettings,
          localeName,
          places,
          minutes: snapshot.minutes,
        }
      )
      body.scrollTop = pinned ? body.scrollHeight : keep
    } else if (tab === 'bag') {
      if (game) title.replaceChildren(gameIcon('bag'), document.createTextNode('背包'))
      else title.textContent = '背包'
      meta.textContent = `${a.inventory.used} / ${a.inventory.capacity}`
      renderBag(
        body,
        state,
        execute,
        {
          readOnly: false,
          selected: bagSelection,
          select: (id) => {
            selectBag(id)
            render(true)
          },
        },
        game,
        actions.bulletin()
      )
    } else if (tab === 'status') {
      title.textContent = `${a.name} 的状态`
      meta.textContent = localeName(a.locus.locale)
      renderStatus(body, state, profile, () => void leave())
    }
  }

  return { renderHud, renderPanel }
}
