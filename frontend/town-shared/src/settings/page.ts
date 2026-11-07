import type { ClientMsg } from '../protocol'
import type { Receipt, SaveCommand } from '../connection'
import { query } from '../dom'

export interface PageDeps {
  send: (obj: ClientMsg) => void
  /** 发出保存命令；回执按请求编号回来，断线时以失败结束 */
  save: (command: SaveCommand, receipt: Receipt) => void
  onDirty: () => void
  showPage: (id: string) => void
  /** 游戏界面 */
  game: boolean
  /** 离开设定中心去「消耗」页 */
  openUsage: () => void
}

/** 子页模板里的固定元素：找不到直接报错，不用非空断言遮住 */
export const $ = <T extends HTMLElement>(root: HTMLElement, sel: string) => query<T>(root, sel)

/** 配置中的显示名进入模板时仍按纯文本处理。 */
export function htmlText(text: string): string {
  const el = document.createElement('span')
  el.textContent = text
  return el.innerHTML
}
