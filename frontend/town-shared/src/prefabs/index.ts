import type { GameModeChoice, PhysiologySwitches } from '../protocol'
import { battleRoyale } from './battleRoyale'

// 预制小镇：选它就是玩某个玩法，开局前只改几项设置，不用自己建岛、写世界观、一个个请人。
// 建镇参数是固定的，同一版建镇生成器出来的岛都一样；每开一局都走建镇流程存成一个新小镇，
// 建镇说明（creation.json）里记着 prefab，第一次进镇时出开局设置（setup.ts）代替开局向导。
// 加一个预制小镇：写一个文件，登记到 PREFABS；它的玩法要先在内核和画面的 game_mode 里有。

export interface Prefab {
  /** 建镇说明里记的编号：小写字母、数字和连字符 */
  id: string
  /** 选择小镇页上的名字，也是每一局小镇名的前缀 */
  name: string
  /** 一句话简介 */
  description: string
  /** 开局时写进的世界观 */
  worldview: string
  /** 建镇参数，交给建镇流程生成地图 */
  spec: Record<string, unknown>
  /** 开局时打开的玩法；种子由开局设置决定 */
  gameMode: GameModeChoice
  /** 选手：村民库里的模板，按号码排，人数从头取 */
  roster: string[]
  players: { default: number; min: number; max: number }
  /** 「吃喝睡」打开时的生理开关；关掉时全关 */
  needs: PhysiologySwitches
}

export const PREFABS: Prefab[] = [battleRoyale]

export function prefabOf(id: string | null | undefined): Prefab | null {
  return PREFABS.find((p) => p.id === id) ?? null
}
