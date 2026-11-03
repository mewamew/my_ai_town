import type { InteractionStatus } from '../protocol'

export interface Speech {
  chat_id: string
  seq: number
  at: number
  text: string
  /** 台词第一句（地图气泡用） */
  line: string
}
export interface ChatPresence {
  id: string
  participants: string[]
  turn: string | null
}
/** 聊天记录的一条：说了话，加入、离开、结束这类过程记录，或提议、答应、没答应 */
type ChatEntryKind = 'speech' | 'joined' | 'left' | 'ended' | 'proposed' | 'accepted' | 'declined'
export interface ChatEntry {
  seq: number
  at: number
  actor: string
  name: string
  kind: ChatEntryKind
  text: string
  audience: string[]
}
export interface ChatSummary {
  id: string
  locale: string
  participants: string[]
  status: InteractionStatus
  created_at: number
  ended_at: number | null
  entries: number
}
