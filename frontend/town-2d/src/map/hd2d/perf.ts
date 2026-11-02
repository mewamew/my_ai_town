import type * as THREE from 'three'

// GPU 计时：浏览器给 EXT_disjoint_timer_query_webgl2 时，按段记 GPU 时间。
// 两个用处：开发版地址带 ?hd-perf 时右上角浮层显示每个 pass 的耗时；画质选「自动」时量开头一段的平均帧耗时，
// 超过本档预算两成就降一档（只这一次打开有效，设定里仍是「自动」）。没有这个扩展的浏览器（Safari、
// mac 版的 WKWebView）不量，也不降档。WebGL2 同一时刻只能有一个计时查询，所以各段不嵌套、依次量。

interface TimerExt {
  TIME_ELAPSED_EXT: number
  GPU_DISJOINT_EXT: number
}

export class GpuTimer {
  private readonly gl: WebGL2RenderingContext
  private readonly ext: TimerExt | null
  private active: { query: WebGLQuery; label: string } | null = null
  private readonly waiting: { query: WebGLQuery; label: string; frame: number }[] = []
  private frame = 0
  /** 每段最近 60 帧的耗时（毫秒） */
  readonly samples = new Map<string, number[]>()
  /** 每帧各段加起来的耗时（毫秒），最近 120 帧 */
  readonly frames: number[] = []
  private frameSum = new Map<number, number>()
  /** 关着时不量（不建查询） */
  on = false

  constructor(renderer: THREE.WebGLRenderer) {
    this.gl = renderer.getContext() as WebGL2RenderingContext
    this.ext = this.gl.getExtension('EXT_disjoint_timer_query_webgl2') as TimerExt | null
  }

  get available() {
    return !!this.ext
  }

  /** 开始量一段；上一段没收尾或不支持时不量 */
  begin(label: string) {
    if (!this.ext || this.active || !this.on) return
    const query = this.gl.createQuery()
    if (!query) return
    this.gl.beginQuery(this.ext.TIME_ELAPSED_EXT, query)
    this.active = { query, label }
  }

  end() {
    if (!this.ext || !this.active) return
    this.gl.endQuery(this.ext.TIME_ELAPSED_EXT)
    this.waiting.push({ ...this.active, frame: this.frame })
    this.active = null
  }

  /** 量 fn 这一段 */
  time<T>(label: string, fn: () => T): T {
    this.begin(label)
    try {
      return fn()
    } finally {
      this.end()
    }
  }

  /** 每帧结束时调：收回已经出结果的查询 */
  endFrame() {
    const gl = this.gl
    if (!this.ext) return
    const disjoint = gl.getParameter(this.ext.GPU_DISJOINT_EXT)
    for (let i = 0; i < this.waiting.length;) {
      const w = this.waiting[i]
      if (!gl.getQueryParameter(w.query, gl.QUERY_RESULT_AVAILABLE)) {
        i++
        continue
      }
      if (!disjoint) {
        const ms = gl.getQueryParameter(w.query, gl.QUERY_RESULT) / 1e6
        const list = this.samples.get(w.label) ?? []
        list.push(ms)
        if (list.length > 60) list.shift()
        this.samples.set(w.label, list)
        this.frameSum.set(w.frame, (this.frameSum.get(w.frame) ?? 0) + ms)
      }
      gl.deleteQuery(w.query)
      this.waiting.splice(i, 1)
    }
    // 早于还在等结果的最早一帧的，各段都齐了，记成一帧的总耗时
    const oldest = this.waiting.length
      ? Math.min(...this.waiting.map((w) => w.frame))
      : this.frame + 1
    for (const [f, ms] of this.frameSum)
      if (f < oldest) {
        this.frames.push(ms)
        if (this.frames.length > 120) this.frames.shift()
        this.frameSum.delete(f)
      }
    this.frame++
  }

  /** 最近 n 帧的平均总耗时（毫秒）；不够 n 帧时为 undefined */
  average(n: number) {
    if (this.frames.length < n) return
    const recent = this.frames.slice(-n)
    return recent.reduce((a, b) => a + b, 0) / n
  }

  dispose() {
    for (const w of this.waiting) this.gl.deleteQuery(w.query)
    this.waiting.length = 0
  }
}

/** 开发版的耗时浮层：每段最近 60 帧的平均，每秒刷新一次 */
export class PerfOverlay {
  private readonly el = document.createElement('pre')
  private last = 0

  constructor(
    container: HTMLElement,
    private readonly timer: GpuTimer
  ) {
    Object.assign(this.el.style, {
      position: 'absolute',
      top: '8px',
      right: '8px',
      zIndex: '50',
      margin: '0',
      padding: '6px 8px',
      font: '11px/1.4 ui-monospace, Menlo, monospace',
      color: '#e8f0e0',
      background: 'rgba(10, 14, 24, 0.72)',
      borderRadius: '6px',
      pointerEvents: 'none',
      whiteSpace: 'pre',
    })
    container.append(this.el)
  }

  update(now: number) {
    if (now - this.last < 1000) return
    this.last = now
    if (!this.timer.available) {
      this.el.textContent = 'GPU 计时：这个浏览器不支持'
      return
    }
    const rows = [...this.timer.samples].map(([label, list]) => {
      const avg = list.reduce((a, b) => a + b, 0) / list.length
      return `${label.padEnd(10)} ${avg.toFixed(2).padStart(6)} ms`
    })
    const total = this.timer.average(Math.min(30, this.timer.frames.length))
    this.el.textContent = [
      ...rows,
      `${'合计'.padEnd(9)} ${total?.toFixed(2).padStart(6) ?? '   —'} ms`,
    ].join('\n')
  }

  dispose() {
    this.el.remove()
  }
}
