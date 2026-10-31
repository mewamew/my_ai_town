// 居民头顶气泡的位置规则：
// - 名册里台词或想法变了才冒泡；第一次见到的人只记下，分不清是新的还是旧的。
//   台词按「交谈编号#第几句」、想法按「模拟分钟|全文」判断是否新的；台词只在交谈进行中算。
// - 寿命按阅读时间：1.5 秒加每字 0.1 秒，夹在 3–6 真实秒；模拟速度 ×0 时冻结。
// - 全图最多两个，超出先撤最早冒出的、非选中的。
// - 选中的人一直挂着最近的想法：不扣寿命，没有气泡时把最近一句补上，直到换成别人。
// 这里只管什么时候冒、留多久、撤谁，画法由地图自己定。
import type { RosterMember } from './protocol'

const MAX_BUBBLES = 2

/** 气泡寿命（毫秒），按气泡里显示出来的字数算 */
function bubbleLifetime(shown: string) {
  return Math.min(6000, Math.max(3000, 1500 + 100 * Array.from(shown).length))
}

interface BubbleOptions {
  /** 允许交谈台词冒泡；HD-2D 的台词由聊天气泡显示 */
  speech: boolean
  /** 气泡里实际显示的文字，寿命按它的字数算；默认整句 */
  shown?: (line: string) => string
  /** 冒出一个新气泡 */
  onSpawn?: (id: string, line: string) => void
  /** 一个气泡到时或被挤掉 */
  onDrop?: (id: string) => void
}

export class BubbleTracker {
  /** 按冒出先后排列：最早的在前 */
  private live = new Map<string, { line: string; remainingMs: number }>()
  private seen = new Map<string, { speech: string; thought: string }>()
  private speed = 1
  private lastTick = performance.now()
  /** 选中的居民的气泡不会被挤掉 */
  selected: string | null = null

  constructor(private options: BubbleOptions) {}

  setSpeed(speed: number) {
    this.speed = speed
  }

  /** 名册里的一位成员：和上次比，台词或想法变了就冒泡 */
  observe(member: RosterMember) {
    const speech = this.options.speech && member.chat ? member.speech : undefined
    const thought = member.thought
    const keys = {
      speech: speech ? `${speech.chat_id}#${speech.seq}` : '',
      thought: thought ? `${thought.sim_minutes}|${thought.text}` : '',
    }
    const previous = this.seen.get(member.id)
    this.seen.set(member.id, keys)
    const fresh = (key: 'speech' | 'thought') => !!previous && keys[key] !== previous[key]
    const held = member.id === this.selected && !this.live.has(member.id)
    if (speech && fresh('speech')) this.spawn(member.id, speech.line || speech.text)
    else if (thought?.line && (fresh('thought') || held)) this.spawn(member.id, thought.line)
  }

  sync(members: Iterable<RosterMember>) {
    for (const member of members) this.observe(member)
  }

  /** 每帧调用：按真实时间扣寿命，暂停时不扣 */
  tick() {
    const now = performance.now()
    const dt = now - this.lastTick
    this.lastTick = now
    if (this.speed <= 0) return
    for (const [id, bubble] of [...this.live]) {
      if (id === this.selected) continue
      bubble.remainingMs -= dt
      if (bubble.remainingMs <= 0) this.drop(id)
    }
  }

  /** 这位居民此刻气泡里的一句；没有气泡时为空 */
  text(id: string) {
    return this.live.get(id)?.line ?? ''
  }

  drop(id: string) {
    if (!this.live.delete(id)) return
    this.options.onDrop?.(id)
  }

  /** 世界重置：撤掉气泡，清空「见过的」记录，之后第一次见到的想法不冒泡 */
  reset() {
    for (const id of [...this.live.keys()]) this.drop(id)
    this.seen.clear()
  }

  private spawn(id: string, line: string) {
    this.drop(id)
    const shown = this.options.shown?.(line) ?? line
    this.live.set(id, { line, remainingMs: bubbleLifetime(shown) })
    this.options.onSpawn?.(id, line)
    while (this.live.size > MAX_BUBBLES) {
      const victim = [...this.live.keys()].find((key) => key !== this.selected)
      if (!victim) break
      this.drop(victim)
    }
  }
}
