// 狼人杀的音乐：第一期先借现有的曲子。投票到放逐（遗言、开枪）放潮水圈决战那首紧的，一局结束放终章；
// 白天、议事和夜里交给天气和时段（夜里本来就是夜曲）。敲钟和亮票各响一下短提示。
// 局里有人倒下是玩法的一部分，只响短提示，不换哀悼、疑云的曲子。
import type { GameModeMusic } from '.'

export const werewolfMusic: GameModeMusic<'werewolf'> = {
  order: ['story/finale', 'tide/final'],
  quietDeaths: true,
  cell(view) {
    if (view.phase === 'over') return 'story/finale'
    if (view.phase === 'vote' || view.phase === 'last_words' || view.phase === 'shot')
      return 'tide/final'
    return null
  },
  sting(view, before) {
    if (view.phase === 'gather' && before.phase !== 'gather') return 'tide-announce'
    return view.revealed && !before.revealed ? 'tide-rise' : null
  },
}
