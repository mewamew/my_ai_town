// 化身神力的三种（复活、治愈、补满）对某个人现在能不能用、会变成什么样。规则在内核
// （crates/kernel/src/miracle.rs），这里按名册上的身体照着写出来，给按钮写说明、把做不了的灰掉；
// 名册慢一拍时以内核的回执为准。化身的「F 神力」菜单、地图上选中村民的「神力」钮和角色卡共用。
import type { MiracleKind } from './avatar/types'
import type { NeedKind, RosterMember } from './protocol'

export interface MiracleOption {
  kind: MiracleKind
  label: string
  /** 会变成什么样，或者做不了的原因 */
  note: string
  enabled: boolean
}

const CONDITION_WORD = { injury: '受伤', illness: '疾病', poison: '中毒' } as const
/** 补满的三项；健康归治愈管 */
const REFILLED: NeedKind[] = ['fullness', 'energy', 'water']

/** 这个人现在受得了哪几种神力；死者只能复活。世界关掉的需求名册不发，也就不补 */
export function miracleOptions(m: Pick<RosterMember, 'body' | 'needs'>): MiracleOption[] {
  const dead = m.body?.life === 'dead'
  const needs = m.needs ?? []
  const health = needs.find((n) => n.kind === 'health')
  const conditions = [...new Set((m.body?.conditions ?? []).map((c) => CONDITION_WORD[c.kind]))]
  const low = needs.filter((n) => REFILLED.includes(n.kind) && n.value < 100)
  const healable = !!health && (conditions.length > 0 || health.value < 100)
  const healNote = !health
    ? '这个世界关掉了健康'
    : !healable
      ? '身体无恙'
      : `${conditions.length ? `解除${conditions.join('、')}，` : ''}健康 ${Math.round(health.value)} → 100`
  return [
    {
      kind: 'revive',
      label: '复活',
      note: dead ? '四项回满，伤病清除' : '还活着',
      enabled: dead,
    },
    {
      kind: 'heal',
      label: '治愈',
      note: dead ? '先复活' : healNote,
      enabled: !dead && healable,
    },
    {
      kind: 'refill',
      label: '补满',
      note: dead
        ? '先复活'
        : low.length
          ? `${low.map((n) => `${n.need} ${Math.round(n.value)}`).join('、')} → 100`
          : '都是满的',
      enabled: !dead && low.length > 0,
    },
  ]
}
