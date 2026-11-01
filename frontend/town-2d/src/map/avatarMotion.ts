import type { WalkTarget } from 'town-shared/gameMap'

// 玩家自己操控的人：本地预测。名册 0.1 秒才来一份，按它画会一走一顿；而方向和步速是本地发出去的，
// 服务端按输入到达的时刻、按真实经过的时间走（见 crates/host/src/avatar/tick.rs），
// 所以每帧照着同样的方向和步速往前走，画出来的就是服务端马上要走到的地方。
// 撞墙和沿墙滑照搬服务端（crates/kernel/src/avatar/geometry.rs 的 advance 和 slide），两边走出来的路一样。
// 名册来了只用来校正：服务端的位置晚到一点，应当落在本地刚走过的轨迹上，走动时只补偏离轨迹的那一点，
// 不按「估出来晚了多久」往回拉（估多了会把人越推越前）；落在很久以前的地方（被挡住）才往回补，
// 两边都停下以后补上全部的差。差都用一小段时间平滑地补。

/** 和服务端的差按这个快慢补上：每过这么久剩 1/e */
const CORRECT_MS = 150
/** 名册最多比本地晚这么久（毫秒）：服务端一拍要处理一阵、偶尔卡一下（实测卡过 0.3 秒）；
 *  落在比这还早的轨迹上，就是服务端真的落后了（被挡住），往回补 */
const MAX_LAG_MS = 500
/** 预测轨迹留多久（毫秒） */
const HISTORY_MS = MAX_LAG_MS + 200
/** 差得比这远（米）直接跳过去：进出门、被服务端拉回原处 */
const SNAP_METRES = 2.5
/** 一帧最多按这么长推进（毫秒）：切回页面、主线程卡住之后不一下子冲出去 */
const MAX_STEP_MS = 250
/** 推进时每一小步最多走多远（米）：和服务端一样 0.1 米一步，撞墙判断不跨过窄墙 */
const SUB_STEP_METRES = 0.1
/** 一直在发方向、名册里的位置却这么久（毫秒）没动：服务端被挡住了，本地也停下等校正 */
const STUCK_MS = 250

type Point = [number, number]

export class AvatarMotion {
  private space = ''
  private pos: Point = [0, 0]
  /** 本地发出的速度（米 / 毫秒） */
  private vel: Point = [0, 0]
  private last = 0
  private history: { t: number; p: Point }[] = []
  /** 还没补上的差（米） */
  private error: Point = [0, 0]
  private known = false
  /** 服务端最近一份位置，和它从什么时候起没再动 */
  private server: { p: Point; still: number } | null = null
  private stuck = false

  /** clear：人能不能站在这一点（米），和服务端的判断一样（见 route.ts 的 clear） */
  constructor(private clear: (space: string, x: number, y: number) => boolean) {}

  /** 本地发出的方向（世界方向，长度不到 1 时按比例慢走，和服务端一样）与此刻的步速（米 / 秒） */
  command(direction: Point, metresPerSecond: number, now: number) {
    this.advance(now)
    const n = Math.max(1, Math.hypot(direction[0], direction[1]))
    const v: Point = [
      (direction[0] / n) * (metresPerSecond / 1000),
      (direction[1] / n) * (metresPerSecond / 1000),
    ]
    if (v[0] !== this.vel[0] || v[1] !== this.vel[1]) {
      this.stuck = false
      if (this.server) this.server.still = now
    }
    this.vel = v
  }

  /** 名册里的位置（服务端的权威位置） */
  sample(at: WalkTarget, now: number) {
    this.advance(now)
    const p = at.position
    if (
      !this.known ||
      at.space !== this.space ||
      Math.hypot(p[0] - this.pos[0], p[1] - this.pos[1]) > SNAP_METRES
    ) {
      this.reset(at, now)
      return
    }
    // 服务端被挡住：一直在发方向，它却不动了
    const moved =
      !this.server || Math.hypot(p[0] - this.server.p[0], p[1] - this.server.p[1]) > 0.01
    const still = moved || !(this.vel[0] || this.vel[1]) ? now : this.server!.still
    this.server = { p: [...p], still }
    this.stuck = now - still > STUCK_MS
    // 本地最近走过的轨迹上离它最近的点：落在轨迹上（晚到）只补偏离的那一点；
    // 落在 MAX_LAG_MS 以前（被挡住、落后了）按那一刻的位置往回补；最近没走动（两边都停了）补全部
    const near = this.nearest(p, now)
    const ref = !near ? this.pos : now - near.t > MAX_LAG_MS ? this.trail(now - MAX_LAG_MS) : near.q
    this.error = [p[0] - ref[0], p[1] - ref[1]]
  }

  /** 此刻画在哪（米）；还不知道位置时为空 */
  current(now: number): WalkTarget | undefined {
    if (!this.known) return undefined
    this.advance(now)
    return { space: this.space, position: [...this.pos] }
  }

  /** 还在动：在走，或者还有没补完的差 */
  active() {
    return (
      ((this.vel[0] !== 0 || this.vel[1] !== 0) && !this.stuck) ||
      Math.hypot(this.error[0], this.error[1]) > 0.003
    )
  }

  /** 在走（走路帧要动）：发着方向、没被挡住 */
  walking() {
    return (this.vel[0] !== 0 || this.vel[1] !== 0) && !this.stuck
  }

  private reset(at: WalkTarget, now: number) {
    this.known = true
    this.space = at.space
    this.pos = [...at.position]
    this.history = [{ t: now, p: [...this.pos] }]
    this.error = [0, 0]
    this.server = { p: [...at.position], still: now }
    this.stuck = false
  }

  /** 推进到 now：按本地发出的速度走（撞墙沿墙滑或停下），再补上一部分和服务端的差 */
  private advance(now: number) {
    const dt = Math.min(MAX_STEP_MS, now - this.last)
    if (dt <= 0) return
    this.last = now
    if (!this.known) return
    if ((this.vel[0] || this.vel[1]) && !this.stuck) {
      const dx = this.vel[0] * dt,
        dy = this.vel[1] * dt
      const steps = Math.max(1, Math.ceil(Math.hypot(dx, dy) / SUB_STEP_METRES))
      for (let i = 0; i < steps; i++) this.step(dx / steps, dy / steps)
    }
    const k = 1 - Math.exp(-dt / CORRECT_MS)
    const cx = this.error[0] * k,
      cy = this.error[1] * k
    this.error = [this.error[0] - cx, this.error[1] - cy]
    this.pos = [this.pos[0] + cx, this.pos[1] + cy]
    // 补上的差连同记下的轨迹一起挪：下一份名册比的是挪过以后的轨迹，同一段差不会补两遍
    for (const h of this.history) h.p = [h.p[0] + cx, h.p[1] + cy]
    this.history.push({ t: now, p: [...this.pos] })
    while (this.history.length > 2 && this.history[1].t < now - HISTORY_MS) this.history.shift()
  }

  /** 走一小步：站得住就走；站不住依次偏 ±15°、±30°…±75°（步子按偏角缩短）沿墙滑，
   *  正对着墙时原地不动。和服务端的 advance、slide 一样 */
  private step(dx: number, dy: number) {
    const [x, y] = this.pos
    if (this.clear(this.space, x + dx, y + dy)) {
      this.pos = [x + dx, y + dy]
      return
    }
    for (let k = 1; k <= 5; k++) {
      const angle = (k * Math.PI) / 12,
        scale = Math.cos(angle)
      for (const sign of [1, -1]) {
        const s = Math.sin(sign * angle),
          c = Math.cos(sign * angle)
        const next: Point = [x + (dx * c - dy * s) * scale, y + (dx * s + dy * c) * scale]
        if (this.clear(this.space, ...next)) {
          this.pos = next
          return
        }
      }
    }
  }

  /** 最近走过的轨迹（含现在的位置）上离 p 最近的点和那一刻；最近没怎么走动时为空 */
  private nearest(p: Point, now: number): { t: number; q: Point } | undefined {
    const recent = this.history.filter((h) => h.t >= now - MAX_LAG_MS - 100)
    let length = 0
    for (let i = 1; i < recent.length; i++)
      length += Math.hypot(recent[i].p[0] - recent[i - 1].p[0], recent[i].p[1] - recent[i - 1].p[1])
    if (length < 0.01) return undefined
    let best = Infinity,
      found: { t: number; q: Point } | undefined
    for (let i = 1; i < recent.length; i++) {
      const a = recent[i - 1],
        b = recent[i]
      const ex = b.p[0] - a.p[0],
        ey = b.p[1] - a.p[1]
      const len = ex * ex + ey * ey
      const u = len
        ? Math.max(0, Math.min(1, ((p[0] - a.p[0]) * ex + (p[1] - a.p[1]) * ey) / len))
        : 0
      const q: Point = [a.p[0] + ex * u, a.p[1] + ey * u]
      const d = Math.hypot(q[0] - p[0], q[1] - p[1])
      // 离得一样近（站过的地方）取更晚的那一刻
      if (d <= best + 1e-6) {
        best = d
        found = { t: a.t + (b.t - a.t) * u, q }
      }
    }
    return found
  }

  /** 轨迹上 t 时刻在哪（早于记录的取最早的，晚于的取现在） */
  private trail(t: number): Point {
    const h = this.history
    if (!h.length || t >= h[h.length - 1].t) return [...this.pos]
    if (t <= h[0].t) return [...h[0].p]
    let i = h.length - 1
    while (i > 0 && h[i - 1].t > t) i--
    const a = h[i - 1],
      b = h[i]
    const u = (t - a.t) / (b.t - a.t || 1)
    return [a.p[0] + (b.p[0] - a.p[0]) * u, a.p[1] + (b.p[1] - a.p[1]) * u]
  }
}
