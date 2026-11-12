import type { ClientMsg, ServerMsg } from './protocol'
import { newId } from './ids'
import { TownDisplaced } from './townApi'

/** 保存结果：成功与否和说明 */
export type Receipt = (ok: boolean, message: string) => void
/** 联合类型逐个去掉字段 */
type DistributiveOmit<T, K extends PropertyKey> = T extends unknown ? Omit<T, K> : never
/** 回执是 agent_saved、config_saved 或 resident_appearance_saved 的命令（调身体也回 agent_saved）；请求编号由连接填写 */
export type SaveCommand = DistributiveOmit<
  Extract<
    ClientMsg,
    {
      type:
        | 'set_persona'
        | 'set_resident_model'
        | 'set_model_config'
        | 'restart_builtin_model'
        | 'set_agent_limits'
        | 'set_agent_trace'
        | 'set_resident_appearance'
        | 'set_resident_body'
    }
  >,
  'request_id'
>
export interface ConnectionEvents {
  message(msg: ServerMsg): void
  connected(recovered: boolean): void
  /** 连着的时候断了；之后重连不上不再重复通知 */
  disconnected(): void
  /** 连不上，正在请管理服务重新打开小镇 */
  reopening?(): void
  /** 这个小镇被另一个页面进的小镇挤掉了：不再自动重连，等玩家决定（resume 接着连） */
  displaced?(message: string): void
  local(text: string, warning?: boolean): void
}

/** 外壳要的连接：WebSocket 那个（createConnection），重演录像时换成录像（town-2d 的 replay/source.ts） */
export interface GameConnection {
  connect(): void
  send(command: ClientMsg): void
  save(command: SaveCommand, receipt: Receipt): void
  resume(next: string): void
  disconnect(): void
}

/** 断线时还没有回执的保存：服务器可能已经处理，也可能没有收到 */
const UNCONFIRMED = '小镇的连接断了，没收到保存结果；连上后请确认是否已保存'
/** 连续连不上这么多次，就当世界进程已经不在了 */
const REOPEN_AFTER = 2

/**
 * WebSocket 与保存回执。save 发出的命令带新的请求编号，同编号的 agent_saved、config_saved、
 * resident_appearance_saved 或 error 到达时交给登记的回调，不再往下分发；断线时未收到回执的保存全部以失败结束。
 * 断线后每 2 秒重连；给了 reopen 时，连续连不上就请它重新打开小镇（比如手机切到后台时世界进程被系统清掉），
 * 换它给的新地址接着连。
 */
export function createConnection(
  url: string,
  events: ConnectionEvents,
  identity?: { townId: string; mapHash: string },
  reopen?: () => Promise<string>
) {
  let endpoint = url
  let ws: WebSocket | null = null
  let hadClose = false
  let online = false
  let failures = 0
  let stopped = false
  /** 被另一个页面挤掉后停着，等玩家点「回到这个小镇」 */
  let paused = false
  let verified = !identity
  let reconnectTimer: ReturnType<typeof setTimeout> | undefined
  const pending = new Map<string, Receipt>()
  const isOpen = () => verified && ws !== null && ws.readyState === WebSocket.OPEN
  const send = (command: ClientMsg) => {
    if (ws && isOpen()) ws.send(JSON.stringify(command))
    else events.local('未连接，无法下发', true)
  }
  const save = (command: SaveCommand, receipt: Receipt) => {
    if (!ws || !isOpen()) {
      receipt(false, '未连接，未发送')
      return
    }
    const request_id = newId()
    pending.set(request_id, receipt)
    ws.send(JSON.stringify({ ...command, request_id }))
  }
  /** 本连接登记过的回执：交给回调并返回 true */
  const settle = (message: ServerMsg) => {
    if (
      message.type !== 'agent_saved' &&
      message.type !== 'config_saved' &&
      message.type !== 'resident_appearance_saved' &&
      message.type !== 'error'
    )
      return false
    const receipt = message.request_id === undefined ? undefined : pending.get(message.request_id)
    if (!receipt || message.request_id === undefined) return false
    pending.delete(message.request_id)
    receipt(message.type !== 'error' && message.ok, message.message)
    return true
  }
  const failPending = () => {
    const receipts = [...pending.values()]
    pending.clear()
    for (const receipt of receipts) receipt(false, UNCONFIRMED)
  }

  /** 连上并核对过身份 */
  function joined() {
    online = true
    failures = 0
    events.connected(hadClose)
    hadClose = false
  }
  function retry() {
    if (stopped || paused) return
    failures++
    if (!reopen || failures % REOPEN_AFTER !== 0) {
      reconnectTimer = setTimeout(connect, 2000)
      return
    }
    events.reopening?.()
    reopen()
      .then((next) => (endpoint = next))
      .then(
        () => (reconnectTimer = setTimeout(connect, 1000)),
        (error) => {
          if (error instanceof TownDisplaced) {
            paused = true
            events.displaced?.(error.message)
            return
          }
          // 管理服务也没回应：过一会儿接着试
          reconnectTimer = setTimeout(connect, 1000)
        }
      )
  }

  function connect() {
    if (stopped) return
    ws = new WebSocket(endpoint)
    verified = !identity
    ws.onopen = () => {
      if (verified) joined()
    }
    ws.onclose = () => {
      failPending()
      if (online) events.disconnected()
      online = false
      hadClose = true
      retry()
    }
    ws.onmessage = (event) => {
      let message: ServerMsg
      try {
        message = JSON.parse(event.data)
      } catch {
        events.local('收到无法解析的服务端消息，已忽略', true)
        return
      }
      if (identity && !verified) {
        if (
          message.type !== 'world_identity' ||
          message.town_id !== identity.townId ||
          message.map_hash !== identity.mapHash
        ) {
          stopped = true
          ws?.close()
          events.local('地图与世界身份不一致，请返回小镇列表重新进入', true)
          return
        }
        verified = true
        joined()
        return
      }
      if (message.type === 'world_identity' || settle(message)) return
      events.message(message)
    }
  }

  return {
    connect,
    send,
    save,
    /** 被挤掉后玩家选了回来：用新的地址接着连 */
    resume(next: string) {
      paused = false
      failures = 0
      endpoint = next
      clearTimeout(reconnectTimer)
      connect()
    },
    disconnect() {
      stopped = true
      clearTimeout(reconnectTimer)
      failPending()
      if (ws) {
        ws.onopen = null
        ws.onmessage = null
        ws.onclose = null
        ws.close()
      }
    },
  }
}

/** 没有页面认领的回执与错误写进事件栏；放在外壳面板登记表的最后 */
export function unclaimedReceipt(message: ServerMsg, local: ConnectionEvents['local']) {
  if (message.type === 'error') local(`✗ ${message.message}`, true)
  else if (message.type === 'agent_saved' || message.type === 'config_saved')
    local(`${message.ok ? '✓' : '✗'} ${message.message}`, !message.ok)
  else return false
  return true
}
