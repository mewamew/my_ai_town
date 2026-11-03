import type { AvatarState } from './types'
import type { AvatarTab } from './ui-types'
import { runningTalk } from './view'

/** 交谈邀请的变化：新开始的交谈、新收到的邀请会打开交谈面板；
 *  自己发出的交谈邀请被拒绝或过期时记一条结果。 */
export function createInvitations() {
  const results = new Map<string, string>()
  let runningIds = new Set<string>(),
    offeredIds = new Set<string>()
  return {
    /** 面板里显示的邀请结果，按邀请编号 */
    results,
    /** 收到新状态：返回之后该开的面板和新出现的结果 */
    update(next: AvatarState, tab: AvatarTab | null) {
      const fresh: string[] = []
      const talk = runningTalk(next)
      if (next.controlled && talk && !runningIds.has(talk.id)) tab = 'chat'
      const interactions = next.interactions ?? []
      runningIds = new Set(interactions.filter((i) => i.status === 'running').map((i) => i.id))
      const offered = interactions.filter((i) => i.status === 'offered')
      if (next.controlled && tab === null && offered.some((i) => !offeredIds.has(i.id)))
        tab = 'chat'
      for (const i of interactions) {
        const social = i.kind.kind === 'talk' || i.kind.kind === 'walk'
        if (!offeredIds.has(i.id) || i.initiator !== next.actor?.id || !social) continue
        if (i.status !== 'declined' && i.status !== 'expired') continue
        const partner = next.nearby?.find((n) => n.id === i.partner)?.name ?? '对方'
        const label = i.kind.kind === 'walk' ? '同行' : '交谈'
        const result =
          i.status === 'declined'
            ? `${partner}没有接受邀请：${i.reply || '这次暂时不方便'}`
            : `${partner}未回应，${label}邀请已过期`
        results.set(i.id, result)
        fresh.push(result)
      }
      offeredIds = new Set(offered.map((i) => i.id))
      return { tab, fresh }
    },
  }
}
