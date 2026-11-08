// 潮水圈的音乐：公布新的一圈、开始涨各有一首，最后一圈是决战，涨完或只剩一个人是结局。
// 公布和开始涨的那一刻各响一下短提示。大逃杀里死人多，有人死只响短提示，不换哀悼曲。
import type { GameModeMusic } from '.'

export const tideMusic: GameModeMusic<'tide'> = {
  order: ['tide/winner', 'tide/final', 'tide/rising', 'tide/announced'],
  quietDeaths: true,
  cell(view, people) {
    if (view.phase === 'closed' || (people.total > 1 && people.living === 1)) return 'tide/winner'
    const moving = view.phase === 'announced' || view.phase === 'rising'
    if (moving && view.ring >= view.rings) return 'tide/final'
    if (view.phase === 'rising') return 'tide/rising'
    return view.phase === 'announced' ? 'tide/announced' : null
  },
  sting(view, before) {
    if (view.phase === before.phase) return null
    if (view.phase === 'announced') return 'tide-announce'
    return view.phase === 'rising' ? 'tide-rise' : null
  },
}
