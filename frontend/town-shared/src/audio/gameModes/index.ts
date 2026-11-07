import type { GameModeId, GameModeView } from '../../protocol'
import type { StingId } from '../catalog'
import type { MusicCell } from '../scene'
import { tideMusic } from './tide'
import { werewolfMusic } from './werewolf'

// 玩法的音乐：名册来一拍，把玩法此刻的状态交给它，它说该放哪一格、这一拍要不要响短提示。
// 选曲把它排在剧情之下、天气之上；它说 null 时交给天气和时段。
// 加一个玩法：在这个目录写一个文件实现 GameModeMusic，再登记到下面的 GAME_MODE_MUSIC。

export interface GameModeMusic<K extends GameModeId = GameModeId> {
  /** 这个玩法的全部格子，由紧到松：往前跳立刻换，往后退等这首放完 */
  readonly order: readonly MusicCell[]
  /** 开着时有人去世只响短提示，不换哀悼、疑云的曲子 */
  readonly quietDeaths: boolean
  /** 此刻该放的格子；people 是居民里活着的和一共的人数 */
  cell(
    view: Extract<GameModeView, { kind: K }>,
    people: { living: number; total: number }
  ): MusicCell | null
  /** 和上一拍比，这一拍要响的短提示 */
  sting(
    view: Extract<GameModeView, { kind: K }>,
    before: Extract<GameModeView, { kind: K }>
  ): StingId | null
}

export const GAME_MODE_MUSIC: { [K in GameModeId]: GameModeMusic<K> } = {
  tide: tideMusic,
  werewolf: werewolfMusic,
}
