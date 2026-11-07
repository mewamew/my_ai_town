// 村中居民名册：每行一位，带「在地图上看」和「档案」（角色卡里改人设、长相、模型）。页首最显眼的是「新建村民」，鼓励玩家自己创造，
// 从村民库挑预制人物排在它后面。
import { button, el } from '../dom'
import { displayClock, playerText } from '../format'
import { agentStateLabels } from '../labels'
import { portraitKey } from '../portraits'
import type { PopulationView } from '../protocol'
import { marker } from './form'
import type { ResidentsContext, ViewHandle } from './state'

type Registration = PopulationView['residents'][number]

function rosterSummary(p: PopulationView | null) {
  if (!p) return '正在读取住宅'
  const entry = p.entry_name ? `新来的人从${p.entry_name}进镇` : '新来的人会出现在公共地点'
  const free = p.homes.filter((h) => !h.occupant).length
  const homes = p.homes.length
    ? free
      ? `还有 ${free} 间空房`
      : '住宅都住满了'
    : '这里没有住宅，大家都在同一片地方活动'
  return `${entry} · ${homes}`
}

/** 名册画出的内容；每拍名册都来，内容没变就不重画 */
export function rosterSignature(ctx: ResidentsContext) {
  const { population, roster, cards, notice } = ctx.state
  return JSON.stringify([
    rosterSummary(population),
    (population?.residents ?? []).map((r) => {
      const m = roster.find((e) => e.member.id === r.id)
      return [
        r.id,
        r.name,
        r.home_name,
        r.joined_clock,
        portraitKey(r),
        cards.find((c) => c.template_id === r.template_id)?.intro,
        m?.locale,
        m?.member.verb,
        m?.member.activity,
        m?.member.resident_agent?.state,
        m?.member.resident_agent?.reason,
      ]
    }),
    notice,
  ])
}

function plainRow(ctx: ResidentsContext, r: Registration) {
  const { deps } = ctx
  const entry = ctx.state.roster.find((e) => e.member.id === r.id)
  const m = entry?.member
  const row = el('article', '', 'rv-row')
  row.dataset.residentId = r.id
  const who = el('div')
  who.append(
    el('strong', r.name),
    el('br'),
    el(
      'span',
      m?.resident_agent
        ? `${agentStateLabels[m.resident_agent.state]} · ${playerText(m.resident_agent.reason)}`
        : '',
      'dim'
    )
  )
  const where = el('div')
  where.append(
    el('div', `${entry ? deps.localeName(entry.locale) : '未在名册'}${m ? ` · ${m.verb}` : ''}`),
    el(
      'div',
      `住宅：${r.home_name} · ${r.joined_clock ? `${displayClock(r.joined_clock)} 入村` : '原有居民'}`,
      'dim'
    )
  )
  const actions = el('div', '', 'row')
  actions.append(
    ctx.locateButton(r.id),
    button('档案', () => {
      ctx.close()
      deps.onOpenProfile({ id: r.id, name: r.name })
    })
  )
  row.append(marker(portraitKey(r), r.appearance.marker), who, where, actions)
  return row
}

/** 新建村民（主按钮）和从村民库挑选 */
function inviteButtons(ctx: ResidentsContext) {
  return [
    button('＋ 新建村民', () => ctx.newVillager('roster'), 'primary'),
    button('从村民库挑选', () => ctx.setTab('library')),
  ]
}

function plainRoster(ctx: ResidentsContext): ViewHandle {
  const box = el('div')
  const residents = ctx.state.population?.residents ?? []
  const bar = el('div', '', 'rv-toolbar')
  bar.append(el('span', rosterSummary(ctx.state.population), 'dim'))
  box.append(bar)
  if (!residents.length) {
    // 空村：按钮放进大卡片里，页首只留住宅与出生位置
    const empty = el('div', '', 'rv-empty rv-create')
    const actions = el('div', '', 'row')
    actions.append(...inviteButtons(ctx))
    empty.append(
      el('h3', '还没有村民，来创造第一位吧'),
      el(
        'p',
        '写一句话，模型就替你写好人设、挑好长相；也可以自己捏长相、写性格，小丑、外星人、孙悟空都捏得出来。保存后直接请进小镇。',
        'dim'
      ),
      actions,
      el('p', '小镇没有默认村民，重置世界会清空所有人。', 'dim')
    )
    box.append(empty)
    return { root: box }
  }
  bar.prepend(...inviteButtons(ctx))
  const rows = el('div', '', 'rv-rows')
  for (const r of residents) rows.append(plainRow(ctx, r))
  box.append(rows)
  return { root: box }
}

export function renderRoster(ctx: ResidentsContext): ViewHandle {
  ctx.state.rosterSignature = rosterSignature(ctx)
  return plainRoster(ctx)
}
