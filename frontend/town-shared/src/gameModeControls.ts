import type { GameModeAction } from './protocol'
import type { Receipt } from './connection'

const EVENT = 'town-game-mode-control'
interface Request {
  command: GameModeAction
  done: Receipt
}

/** 画面不拥有连接。操作沿地图节点交给游戏外壳，回执仍走世界命令的 request_id。 */
export function requestGameModeControl(node: HTMLElement, command: GameModeAction) {
  return new Promise<{ ok: boolean; message: string }>((resolve) => {
    const event = new CustomEvent<Request>(EVENT, {
      bubbles: true,
      cancelable: true,
      detail: { command, done: (ok, message) => resolve({ ok, message }) },
    })
    node.dispatchEvent(event)
    if (!event.defaultPrevented) resolve({ ok: false, message: '当前画面不能操作小镇。' })
  })
}

export function bindGameModeControls(
  node: HTMLElement,
  send: (command: GameModeAction, done: Receipt) => void,
  signal: AbortSignal,
  readonly: boolean
) {
  node.addEventListener(
    EVENT,
    (event) => {
      const request = event as CustomEvent<Request>
      request.preventDefault()
      if (readonly) request.detail.done(false, '录像只供观看，不能改变原小镇。')
      else send(request.detail.command, request.detail.done)
    },
    { signal }
  )
}
