// 背景乐的音量：每首各自淡入淡出（换曲时交叉淡化），短提示响时整体压低一点。
// 每帧按「基准音量 × 这首的增益 × 压低系数」写一次 volume，都到位了就停。
// 页面藏起来时动画帧不走，由 settle 直接收尾。

interface Ramp {
  from: number
  to: number
  start: number
  ms: number
}

const valueAt = (ramp: Ramp, now: number) =>
  ramp.ms <= 0 || now >= ramp.start + ramp.ms
    ? ramp.to
    : ramp.from + ((ramp.to - ramp.from) * (now - ramp.start)) / ramp.ms
const still = (to: number): Ramp => ({ from: to, to, start: 0, ms: 0 })

export function createMixer(base: number, release: (audio: HTMLAudioElement) => void) {
  /** drop：淡到 0 后放掉这首 */
  const voices = new Map<HTMLAudioElement, Ramp & { drop: boolean }>()
  let duck = still(1)
  let frame = 0

  const apply = (now: number) => {
    const level = valueAt(duck, now)
    for (const [audio, ramp] of voices) {
      audio.volume = Math.min(1, Math.max(0, base * valueAt(ramp, now) * level))
      if (ramp.drop && now >= ramp.start + ramp.ms) {
        voices.delete(audio)
        release(audio)
      }
    }
  }
  const moving = (now: number) =>
    now < duck.start + duck.ms || [...voices.values()].some((r) => now < r.start + r.ms)
  const tick = (now: number) => {
    frame = 0
    apply(now)
    if (moving(now)) frame = requestAnimationFrame(tick)
  }
  const kick = () => {
    const now = performance.now()
    apply(now)
    if (!frame && moving(now)) frame = requestAnimationFrame(tick)
  }

  return {
    /** 新的一首，从 gain 起步 */
    add(audio: HTMLAudioElement, gain: number) {
      voices.set(audio, { ...still(gain), drop: false })
      kick()
    },
    fade(audio: HTMLAudioElement, to: number, ms: number, drop = false) {
      const ramp = voices.get(audio)
      if (!ramp) return
      const now = performance.now()
      voices.set(audio, { from: valueAt(ramp, now), to, start: now, ms, drop })
      kick()
    },
    duck(to: number, ms: number) {
      const now = performance.now()
      duck = { from: valueAt(duck, now), to, start: now, ms }
      kick()
    },
    /** 不再管这首的音量（已经放完或放掉了） */
    forget(audio: HTMLAudioElement) {
      voices.delete(audio)
    },
    /** 立刻收尾：淡出的放掉，其余停在目标音量，不再压低 */
    settle() {
      if (frame) cancelAnimationFrame(frame)
      frame = 0
      duck = still(1)
      for (const [audio, ramp] of voices) voices.set(audio, { ...still(ramp.to), drop: ramp.drop })
      apply(performance.now())
    },
    /** 全部放掉 */
    clear() {
      if (frame) cancelAnimationFrame(frame)
      frame = 0
      duck = still(1)
      for (const audio of voices.keys()) release(audio)
      voices.clear()
    },
  }
}
