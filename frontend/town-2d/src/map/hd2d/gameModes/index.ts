import type * as THREE from 'three'
import type { GameModeView } from 'town-shared/protocol'
import type { MapTheme } from '../../themes/types'
import type { Badge } from '../villagerSigns'
import { SwordholderLook } from './swordholder'
import { TideLook } from './tide'
import { WerewolfLook } from './werewolf'
import { FrostlightLook } from './frostlight'

// 玩法的画面：场景在固定的几处把材质交给玩法（地面、海面、立在地上的东西、村民），
// 名册来了把玩法此刻的状态交给它；要在地图上画自己界面的玩法，场景建好时给它一层；
// 要在场景里放自己东西的玩法（天上的水滴……），场景建好时给它场景，每拍让它推进自己的动画；
// 要给人做记号的玩法（拿着信号弹的人）给出头顶的标记。
// 每个玩法的着色和界面都先装好，没开它时它什么也不画。
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
  /** 玩法自己的界面（横幅、侧栏……）：盖在地图上的一层，不接点击，要接的元素自己打开 */
  mount?(layer: HTMLElement): void
  /** 玩法放在场景里的东西：场景建好时给它场景，和按地点编号找那个地点的地标落在哪儿（场景的 x、z，
   *  就是地图坐标；地图上没有这个地点时为 null） */
  addToScene?(
    scene: THREE.Scene,
    landmark: (locale: string) => { x: number; z: number } | null
  ): void
  /** 每拍推进放在场景里的东西（t 是秒）；返回 true 时这一拍要重画 */
  step?(t: number): boolean
  /** 给哪些村民头顶挂常驻的小标记（大逃杀里拿着信号弹的人）：村民编号 → 标记，画法见 villagerSigns.ts。
   *  每次 apply 之后读一遍 */
  badges?(): ReadonlyMap<string, Badge>
}

/** 所有玩法的画面，场景建好时装上 */
export function gameModeLooks(theme: MapTheme): GameModeLook[] {
  return [new TideLook(theme), new WerewolfLook(), new SwordholderLook(), new FrostlightLook()]
}
