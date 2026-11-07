// 重演拍素材的时钟：接管 performance.now、requestAnimationFrame 和 setTimeout / setInterval。
// 平时照常走（页面加载、读地图都按真实时间）；拍摄脚本叫 hold() 以后只有 advance(ms) 才往前走，
// 一次走多少，画面里的人、海浪、气泡就动多少——截一帧再慢，视频里每帧之间也是同样的时间。

interface Timer {
  due: number
  run: () => void
  every?: number
}

export interface VirtualClock {
  /** 从此时间只按 advance 走 */
  hold(): void
  readonly holding: boolean
  /** 往前走 ms 毫秒：到点的定时器按先后执行，再画一帧（执行排着队的 requestAnimationFrame） */
  advance(ms: number): void
}

export function installClock(): VirtualClock {
  const native = {
    now: performance.now.bind(performance),
    raf: window.requestAnimationFrame.bind(window),
    caf: window.cancelAnimationFrame.bind(window),
    setTimeout: window.setTimeout.bind(window),
    clearTimeout: window.clearTimeout.bind(window),
    setInterval: window.setInterval.bind(window),
    clearInterval: window.clearInterval.bind(window),
  }
  let holding = false
  let now = 0
  /** 自己发的编号从这里起，和浏览器发的分开 */
  let nextId = 1 << 30
  const timers = new Map<number, Timer>()
  let frames = new Map<number, FrameRequestCallback>()
  const call = (handler: TimerHandler, args: unknown[]) => () => {
    if (typeof handler === 'function') handler(...args)
  }

  performance.now = () => (holding ? now : native.now())
  window.requestAnimationFrame = (callback) => {
    if (!holding) return native.raf(callback)
    const id = nextId++
    frames.set(id, callback)
    return id
  }
  window.cancelAnimationFrame = (id) => {
    if (!frames.delete(id)) native.caf(id)
  }
  window.setTimeout = ((handler: TimerHandler, delay = 0, ...args: unknown[]) => {
    if (!holding) return native.setTimeout(handler, delay, ...args)
    const id = nextId++
    timers.set(id, { due: now + Math.max(0, delay), run: call(handler, args) })
    return id
  }) as typeof window.setTimeout
  window.clearTimeout = ((id?: number) => {
    if (id !== undefined && !timers.delete(id)) native.clearTimeout(id)
  }) as typeof window.clearTimeout
  window.setInterval = ((handler: TimerHandler, delay = 0, ...args: unknown[]) => {
    if (!holding) return native.setInterval(handler, delay, ...args)
    const id = nextId++
    const every = Math.max(1, delay)
    timers.set(id, { due: now + every, run: call(handler, args), every })
    return id
  }) as typeof window.setInterval
  window.clearInterval = ((id?: number) => {
    if (id !== undefined && !timers.delete(id)) native.clearInterval(id)
  }) as typeof window.clearInterval

  return {
    hold() {
      if (holding) return
      now = native.now()
      holding = true
    },
    get holding() {
      return holding
    },
    advance(ms: number) {
      const target = now + Math.max(0, ms)
      for (;;) {
        let id = -1
        let next: Timer | undefined
        for (const [key, timer] of timers)
          if (timer.due <= target && (!next || timer.due < next.due)) {
            id = key
            next = timer
          }
        if (!next) break
        now = Math.max(now, next.due)
        if (next.every) next.due += next.every
        else timers.delete(id)
        try {
          next.run()
        } catch (error) {
          console.error(error)
        }
      }
      now = target
      const due = frames
      frames = new Map()
      for (const callback of due.values())
        try {
          callback(now)
        } catch (error) {
          console.error(error)
        }
    },
  }
}
