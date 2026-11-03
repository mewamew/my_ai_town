import { OUTDOOR_SPACE } from './grid'
import type { House } from './hd2d/layout'
import type { HdScene } from './hd2d/scene'
import { standUpright } from './upright'

type Point = [number, number]

/**
 * 立体场景里房子的开合：选中的人或化身所在的房间、放大后镜头中心所在的房间、旁观时指着或点着的房子
 * （见 RoomPeek）掀开屋顶；其余房子盖着屋顶，里面的道具藏起来，人只留名字。房间名盖着屋顶时放在屋顶上方，
 * 掀开后回到房间上沿。屋顶按像素格溶解着开合（见 HdScene.setOpenRooms），盖严之前屋里的人和道具还看得见。
 */
export class RoomCovers {
  /** 该掀开的房间 */
  private open = new Set<string>()
  /** 屋顶没盖严的房间：该掀开的，加上正在盖回去的 */
  private readonly shown = new Set<string>()
  /** 上次交给立体场景的开合，null 表示要重新交 */
  private key: string | null = null
  private readonly labels = new Map<string, { label: Element; house: House }>()

  constructor(private readonly spaceAt: (p: Point) => string) {}

  /** 立体场景起来后记下每栋房子的名字标签 */
  attach(svg: SVGSVGElement, houses: House[]) {
    for (const house of houses) {
      const label = svg.querySelector(`[data-room="${CSS.escape(house.id)}"]`)
      if (label) this.labels.set(house.id, { label, house })
    }
    this.key = null
  }

  /** 俯角或道具变了：下次 update 时重新交给立体场景 */
  reset() {
    this.key = null
  }

  /** focus 里的点所在的房间和 houses 里的房子掀开；和上次交给立体场景的不同时返回 true */
  update(focus: (Point | undefined)[], houses: (string | null)[]) {
    const open = new Set<string>()
    for (const p of focus) {
      const space = p && this.spaceAt(p)
      if (space && space !== OUTDOOR_SPACE) open.add(space)
    }
    for (const id of houses) if (id) open.add(id)
    this.open = open
    for (const id of open) this.shown.add(id)
    const key = `${[...open].sort().join('|')}/${[...this.shown].sort().join('|')}`
    if (key === this.key) return false
    this.key = key
    return true
  }

  /** 立体场景说这些房间的屋顶盖严了；屋里因此要藏起来时返回 true，再 update 一次 */
  closed(ids: string[]) {
    let changed = false
    for (const id of ids) if (!this.open.has(id) && this.shown.delete(id)) changed = true
    return changed
  }

  /** 这一点被屋顶盖着：在房间里，而且这间的屋顶盖严了 */
  readonly covered = (p: Point) => {
    const space = this.spaceAt(p)
    return space !== OUTDOOR_SPACE && !this.shown.has(space)
  }

  /** 开合交给立体场景，房间名跟着屋顶或墙顶的高度走 */
  apply(hd: HdScene, project: (point: Point) => Point) {
    hd.setOpenRooms(this.open)
    for (const [id, { label, house }] of this.labels) {
      const opened = this.shown.has(id)
      const corners = [
        [house.x, house.y],
        [house.x + house.w, house.y],
        [house.x, house.y + house.h],
        [house.x + house.w, house.y + house.h],
      ] as Point[]
      const view = corners.map(project)
      const [x] = project([house.x + house.w / 2, house.y + house.h / 2])
      const rise = opened
        ? house.y - hd.roomTop(house)
        : house.y + (house.alongX ? house.h / 2 : 0) - hd.roofTop(house)
      let top = Math.min(...view.map((p) => p[1])) - rise
      if (!opened) {
        const ridge: Point[] = house.alongX
          ? [
              [house.x, house.y + house.h / 2],
              [house.x + house.w, house.y + house.h / 2],
            ]
          : [
              [house.x + house.w / 2, house.y],
              [house.x + house.w / 2, house.y + house.h],
            ]
        const wallRise = (rise * house.wallH) / (house.wallH + house.ridge)
        top = Math.min(
          ...view.map((p) => p[1] - wallRise),
          ...ridge.map((p) => project(p)[1] - rise)
        )
      }
      label.setAttribute('x', String(x))
      label.setAttribute('y', String(top - 18))
      standUpright(label, 1 / hd.verticalScale)
    }
  }
}

/** 指针在一栋房子上停多久才掀开它、离开多久才盖回（毫秒） */
const PEEK_DWELL_MS = 250
const PEEK_LEAVE_MS = 300

/**
 * 旁观时指着、点着的房子。桌面上指着是临时看一眼，点一下是让它一直开着；手机没有悬停，只靠点。
 * - 指针在一栋房子上停够 PEEK_DWELL_MS 才掀开，同一时间只掀一栋：扫过一片房子不会一路闪
 * - 离开 PEEK_LEAVE_MS 后盖回，中途回来接着开着：在两栋之间挪一下不会让两栋都闪
 * - 画面在动（拖动、缩放、转角度）时不计时，画面停下来、指针还在这栋上才算停够
 * - 点房子钉住，点空地盖回
 * 指着、钉住的房子判断指针在不在上面时一直按盖着屋顶的轮廓（见 TownMap.houseAt）
 */
export class RoomPeek {
  /** 指着掀开的房子 */
  peeked: string | null = null
  /** 点过钉住的房子 */
  pinned: string | null = null
  /** 指针此刻在哪栋房子上 */
  private under: string | null = null
  private dwell = 0
  private leave = 0

  constructor(private readonly changed: () => void) {}

  /** 指针此刻在哪栋房子上（不在房子上为 null）；moving 是画面还在动，没掀开的重新计时 */
  point(house: string | null, moving = false) {
    const entered = house !== this.under
    this.under = house
    if (house === this.peeked) this.stopLeave()
    else if (this.peeked && !this.leave)
      this.leave = window.setTimeout(() => {
        this.leave = 0
        this.peeked = null
        this.changed()
      }, PEEK_LEAVE_MS)
    if (!entered && !moving) return
    this.stopDwell()
    if (house && house !== this.peeked)
      this.dwell = window.setTimeout(() => {
        this.dwell = 0
        this.stopLeave()
        this.peeked = house
        this.changed()
      }, PEEK_DWELL_MS)
  }

  /** 点了一下：点在房子上钉住它，指针也就在它上面；点在空地上（null），钉住的和指着的都盖回 */
  pin(house: string | null) {
    this.stop()
    const differs = house !== this.peeked || house !== this.pinned
    this.under = this.peeked = this.pinned = house
    if (differs) this.changed()
  }

  /** 停掉计时，不再回调（地图销毁） */
  stop() {
    this.stopDwell()
    this.stopLeave()
  }

  private stopDwell() {
    window.clearTimeout(this.dwell)
    this.dwell = 0
  }

  private stopLeave() {
    window.clearTimeout(this.leave)
    this.leave = 0
  }
}
