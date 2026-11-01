import type { AvatarPrompt } from '../gameMap'
import type { AvatarCommand } from './types'
import type { BulletinBoard, BulletinSpots } from './bulletin'
export type AvatarTab = 'chat' | 'bag' | 'status'
/** instant：不占世界里的时间（比如在公告栏写公告），世界暂停时也能做；
 *  approach：人还够不着，run 是先走过去再搭话 */
export type AvatarTarget = {
  prompt: AvatarPrompt
  run: () => void
  instant?: boolean
  approach?: boolean
}
/** 跟前能张贴公告的地方和打开写公告的对话框 */
export interface BulletinTargets {
  spots: BulletinSpots
  open: (board: BulletinBoard) => void
}

/** 界面按钮、菜单和面板里的操作，由控制器实现 */
export interface AvatarActions {
  openDialog: () => void
  closeDialog: () => void
  execute: (command: AvatarCommand) => Promise<boolean>
  toggleTab: (tab: AvatarTab) => void
  openTab: (tab: AvatarTab) => void
  closeTab: () => void
  leave: () => Promise<boolean>
  stopMoving: () => void
  showHistory: () => void
  speak: () => Promise<void>
  follow: () => void
  resetCamera: () => void
  targets: () => AvatarTarget[]
  /** 跟前能张贴公告的地方；附近没有公告栏时为 null */
  bulletin: () => BulletinTargets | null
  render: (force?: boolean) => void
  selectBag: (id: string | null) => void
}
