// 执剑人之夜的音乐：借现有的曲子。投票、平票指定放潮水圈决战那首紧的；水滴来袭的十分钟放「情况危急」那组；
// 结局定了放终章。白天、演说、交接交给天气和时段。敲钟、亮票各响一下短提示，水滴来袭那一刻响最刺耳的一下，
// 威慑失败再响一下去世的那段。这一局不死人，有人去世照常换哀悼曲。
import type { GameModeMusic } from '.'

export const swordholderMusic: GameModeMusic<'swordholder'> = {
  order: ['story/finale', 'story/critical', 'tide/final'],
  quietDeaths: false,
  cell(view) {
    if (view.ending) return 'story/finale'
    if (view.phase === 'attack') return 'story/critical'
    if (view.phase === 'vote' || view.phase === 'tiebreak') return 'tide/final'
    return null
  },
  sting(view, before) {
    if (view.phase === 'attack' && before.phase !== 'attack') return 'murder'
    if (view.ending && !before.ending) return view.ending === 'failed' ? 'death' : 'tide-rise'
    if (view.phase === 'gather' && before.phase !== 'gather') return 'tide-announce'
    return view.revealed && !before.revealed ? 'tide-rise' : null
  },
}
