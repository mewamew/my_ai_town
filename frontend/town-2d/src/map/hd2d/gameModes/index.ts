import type * as THREE from 'three'
import type { GameModeView } from 'town-shared/protocol'
import type { MapTheme } from '../../themes/types'
import { TideLook } from './tide'

// 玩法的画面：场景在固定的几处把材质交给玩法（地面、海面、立在地上的东西、村民），
// 名册来了把玩法此刻的状态交给它。每个玩法的着色都先装好，没开它时它什么也不画。
// 加一个玩法：在这个目录写一个文件实现 GameModeLook，再登记到下面的 gameModeLooks。

/** 玩法接进画面的几处 */
export interface GameModeLook {
  /** 地面（陆地）和海面的材质 */
  shadeGround(material: THREE.Material, surface: 'land' | 'sea'): void
  /** 立在地上的东西（树、道具、地标、草丛）和村民的材质；投影用的深度材质也过一遍 */
  shadeStanding(material: THREE.Material, who: 'thing' | 'villager'): void
  /** 名册里玩法此刻的状态；没开玩法时是 null。metre 是每米的地图单位 */
  apply(view: GameModeView | null, metre: number): void
  /** 开着时到处都可能是水：倒影要一直画 */
  readonly waterAnywhere: boolean
}

/** 所有玩法的画面，场景建好时装上 */
export function gameModeLooks(theme: MapTheme): GameModeLook[] {
  return [new TideLook(theme)]
}
