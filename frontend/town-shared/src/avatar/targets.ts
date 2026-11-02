import type { AvatarCommand, AvatarProp, AvatarState, MiracleKind, PlayerAction } from './types'
import type { WalkTarget } from '../gameMap'

import { pendingTalk, runningTalk } from './view'

import type { AvatarTab, AvatarTarget, BulletinTargets } from './ui-types'
import { postsHere } from './bulletin'

type Actor = NonNullable<AvatarState['actor']>

/** 当前对象：Tab 换到的提示编号；where 给出人和道具的米制位置，用来把近的排在前面；
 *  approach 是走到够不着的人身边再搭话；cast 是对够得着的人施展神力 */
interface TargetFocus {
  id: string | null
  where?: (kind: 'person' | 'prop', id: string) => WalkTarget | undefined
  approach?: (id: string) => void
  cast?: (id: string, kind: MiracleKind) => void
}

/** Derive interaction prompts from the latest authoritative avatar state. */
export function avatarTargets(
  state: AvatarState | null,
  execute: (command: AvatarCommand) => Promise<boolean>,
  openTab: (tab: AvatarTab) => void,
  selectBag: (id: string) => void,
  focus: TargetFocus = { id: null },
  /** 跟前能张贴公告的地方，以及打开写公告的对话框 */
  bulletin?: BulletinTargets | null
): AvatarTarget[] {
  /** 一件附近道具的主动作：可拾取就拾取，否则第一个用法，再否则取回里面的东西 */
  function propMain(p: AvatarProp, a: Actor): { label: string; run: () => void } | null {
    const act = (draft: PlayerAction) =>
      void execute({ kind: 'action', revision: a.revision, action: draft })
    if (p.portable)
      return {
        label: `拾取${p.name}`,
        run: () =>
          act({ intent: { verb: '拾取' }, inventory: { operation: 'pick_up', items: [p.id] } }),
      }
    // 张贴处，或者没有张贴处的公告栏：走到跟前就是来贴公告的。公告栏的「查看公告栏」留在背包的附近物品里
    if (bulletin && postsHere(bulletin.spots, p)) {
      const { board } = bulletin.spots
      return { label: `${p.name} · 张贴公告`, run: () => bulletin.open(board) }
    }
    const v = p.actions[0]
    // 只能对别人用的（复活、伤人），化身也没有身体可用的：打开背包选对象
    const choose = !!v?.recipient && (!!v.others_only || state?.mode !== 'possession')
    if (v && choose)
      return {
        label: `${p.name} · ${v.label}`,
        run: () => {
          selectBag(`prop:${p.id}`)
          openTab('bag')
        },
      }
    if (v)
      return {
        label: `${p.name} · ${v.label}`,
        run: () => act({ intent: { verb: v.id }, prop_id: p.id }),
      }
    const item = p.contents?.[0]
    if (item)
      return {
        label: `取回${item.name}`,
        run: () =>
          act({
            intent: { verb: '取回' },
            inventory: { operation: 'retrieve', container: p.id, items: [item.id] },
          }),
      }
    return null
  }
  /** 离化身多远（米）；量不出来（不在同一空间、地图不给位置）时为无穷大 */
  function distance(a: Actor, kind: 'person' | 'prop', id: string): number {
    const here =
      a.locus.at.kind === 'free'
        ? { space: a.locus.at.space, position: a.locus.at.position }
        : focus.where?.('person', a.id)
    const there = focus.where?.(kind, id)
    if (!here || !there || here.space !== there.space) return Infinity
    return Math.hypot(here.position[0] - there.position[0], here.position[1] - there.position[1])
  }
  /** 从近到远排；排序稳定，量不出距离的保持原来的先后 */
  function nearestFirst<T extends { id: string }>(
    a: Actor,
    items: T[],
    kind: 'person' | 'prop'
  ): T[] {
    if (!focus.where) return items
    const d = new Map(items.map((item) => [item.id, distance(a, kind, item.id)]))
    return [...items].sort((x, y) => (d.get(x.id) ?? Infinity) - (d.get(y.id) ?? Infinity))
  }
  /** 附近可交互的对象：人、门、道具，人和道具各自从近到远排。
   *  当前对象是 Tab 换到的那个，没换过或它已不在附近时取第一个能做的；现在能做才带 E */
  function targets(): AvatarTarget[] {
    const a = state?.actor
    if (!a || !state) return []
    const talk = runningTalk(state)
    const talking = new Set(talk?.members ?? (talk ? [talk.initiator, talk.partner] : []))
    const list: AvatarTarget[] = []
    const cast = state.miracles ? focus.cast : undefined
    for (const n of nearestFirst(a, state.nearby ?? [], 'person')) {
      if (talking.has(n.id)) continue
      // 开着化身神力时，倒在跟前的死者的主动作是复活
      if (n.dead && cast) {
        list.push({
          prompt: { id: `person:${n.id}`, kind: 'person', target: n.id, label: `复活${n.name}` },
          run: () => cast(n.id, 'revive'),
        })
        continue
      }
      const invitation = pendingTalk(state, n.id)
      const available = (n.can_talk ?? n.available) && !invitation
      // 在和别人聊、够得着那一圈人：可以加入（没在聊天时）
      const joinable = !available && !invitation && !talk
      const chat = joinable
        ? state.nearby_chats?.find((c) => c.members.includes(n.id) && !c.members.includes(a.id))
        : undefined
      list.push({
        prompt: {
          id: `person:${n.id}`,
          kind: 'person',
          target: n.id,
          label: invitation
            ? invitation.initiator === a.id
              ? `等待${n.name}回应`
              : `${n.name}邀请你交谈`
            : available
              ? `和${n.name}交谈`
              : chat
                ? `加入${n.name}的交谈`
                : `${n.name} · ${n.busy ?? '暂时无法交谈'}`,
          muted: !available && !chat,
          // 开着化身神力时，活着的人另有 F：治愈、补满
          ...(cast && !n.dead && { alt: { key: 'F', label: '神力' } }),
        },
        run: () => {
          if (invitation) openTab('chat')
          else if (available)
            void execute({
              kind: 'interact',
              revision: a.revision,
              command: {
                operation: 'offer',
                partner_id: n.id,
                interaction: { kind: 'talk' },
                message: '你好，方便聊一会儿吗？',
              },
            })
          else if (chat)
            void execute({
              kind: 'interact',
              revision: a.revision,
              command: { operation: 'join', interaction_id: chat.id, message: '我也来聊聊。' },
            })
        },
      })
    }
    for (const p of state.portals ?? [])
      list.push({
        prompt: { id: `portal:${p.id}`, kind: 'portal', target: p.id, label: p.label },
        run: () => void execute({ kind: 'portal', id: p.id }),
      })
    for (const p of nearestFirst(a, state.props ?? [], 'prop')) {
      if (p.carried) continue
      const main = propMain(p, a)
      list.push({
        instant: !!bulletin && postsHere(bulletin.spots, p),
        prompt: { id: `prop:${p.id}`, kind: 'prop', target: p.id, label: main?.label ?? p.name },
        run:
          main?.run ??
          (() => {
            selectBag(`prop:${p.id}`)
            openTab('bag')
          }),
      })
    }
    // 附近还够不着的人排在最后：按 E 或点标签就走过去，到了自动搭话
    for (const n of state.approach ?? []) {
      if (talking.has(n.id) || !focus.approach) continue
      const approach = focus.approach
      list.push({
        approach: true,
        prompt: {
          id: `person:${n.id}`,
          kind: 'person',
          target: n.id,
          label: n.blocked ? `隔着东西，绕过去和${n.name}说话` : `走过去和${n.name}说话`,
        },
        run: () => approach(n.id),
      })
    }
    const current =
      list.find((t) => t.prompt.id === focus.id) ?? list.find((t) => !t.prompt.muted) ?? list[0]
    if (current) current.prompt.focused = true
    // 只有现在真能按 E 时才标出来：世界在走、化身没在忙；写公告这类不占时间的随时能做
    if (current && !current.prompt.muted && ((state.speed && !a.busy) || current.instant))
      current.prompt.key = 'E'
    return list
  }

  return targets()
}
