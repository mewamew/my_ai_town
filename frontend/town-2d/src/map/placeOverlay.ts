// 摆道具的地图叠层：能放东西的地点挖亮、别处压暗；拉近后地点里画出能放的格子，指着的地点再画出
// 居民走去各件东西的路和入口一圈；绿框是东西会落在哪。哪里能放由后端算（PlaceGrid），这里只画。
// 画在地图自己的 SVG 里（地图单位、转过方位角的坐标），镜头平移缩放不用重画，换方位角才重画。
import type { PlaceGrid } from 'town-shared/protocol'
import type { PlaceGhost } from 'town-shared/gameMap'
import { cells } from 'town-shared/props/placeGrid'
import { el } from 'town-shared/svg'

type Project = (p: [number, number]) => [number, number]
/** 米：x、地面上的 z、宽、深 */
export interface OverlayFloor {
  id: string
  bounds: { x: number; y: number; w: number; h: number }
}
/** 一件道具的占地（米），描红挡路的那件用 */
export interface OverlayProp {
  position: [number, number]
  footprint: [number, number]
}

/** 描挡路的那件时四边外扩一点（米），红框不贴着东西的边 */
const BLOCKER_PAD = 0.25

export class PlaceOverlay {
  readonly layer = el('g', { class: 'place-overlay' })
  private readonly mask = el('path', { class: 'place-mask', 'fill-rule': 'evenodd' })
  private readonly dim = el('path', { class: 'place-dim' })
  private readonly free = el('path', { class: 'place-cells' })
  private readonly frames = el('path', { class: 'place-frames' })
  private readonly full = el('path', { class: 'place-frames full' })
  private readonly walks = el('path', { class: 'place-walks' })
  private readonly door = el('path', { class: 'place-door' })
  private readonly blockLine = el('path', { class: 'place-block-line' })
  private readonly blocker = el('path', { class: 'place-blocker' })
  private readonly link = el('path', { class: 'place-link' })
  private readonly cross = el('path', { class: 'place-cross' })
  private readonly ghostHalo = el('path', { class: 'place-ghost-halo' })
  private readonly ghost = el('path', { class: 'place-ghost' })
  private floors: OverlayFloor[] = []
  private grids = new Map<string, PlaceGrid>()
  /** 每个地点能放的格子的路径，换格子、换方位角时重算；画的时候只拼镜头里看得见的那几块 */
  private cellPaths = new Map<string, string>()
  private visibleKey: string | null = null
  private hot: string | null = null
  private hotWalks: [number, number][][] = []
  private shown: PlaceGhost | null = null
  private blockerProp: OverlayProp | null = null
  private project: Project = (p) => p

  constructor(private readonly unit: number) {
    this.layer.append(
      this.mask,
      this.dim,
      this.free,
      this.frames,
      this.full,
      this.walks,
      this.door,
      this.blockLine,
      this.blocker,
      this.link,
      this.cross,
      this.ghostHalo,
      this.ghost
    )
    this.layer.style.display = 'none'
  }

  show(on: boolean) {
    this.layer.style.display = on ? '' : 'none'
  }

  /** 格子看得清时才画格子、路和入口；整图时只有遮罩 */
  setDetail(on: boolean) {
    this.layer.classList.toggle('detail', on)
  }

  /** 镜头里看得见的地点：只画这几块的格子（一座岛上的格子拼在一起有上万格，平移时拖慢画面） */
  setVisible(locales: string[]) {
    const key = [...locales].sort().join()
    if (key === this.visibleKey) return
    this.visibleKey = key
    this.free.setAttribute('d', locales.map((id) => this.cellPaths.get(id) ?? '').join(''))
  }

  /** 能放东西的地点（米）和后端给的格子；格子还没到时按地点范围先挖亮 */
  setPlaces(floors: OverlayFloor[], grids: Map<string, PlaceGrid>, project: Project) {
    this.floors = floors
    this.grids = grids
    this.project = project
    this.drawPlaces()
    this.drawHot()
    this.drawGhost()
  }

  /** 方位角变了：所有坐标重算 */
  reproject(project: Project) {
    this.project = project
    this.drawPlaces()
    this.drawHot()
    this.drawGhost()
  }

  /** 指着或选中的地点：画出它里面看不见的路（米的折线）和入口一圈 */
  setHot(locale: string | null, walks: [number, number][][]) {
    this.hot = locale
    this.hotWalks = walks
    this.drawHot()
  }

  /** 绿框；blocker 是挡路的那件的占地（从入口过来被挡时描红） */
  setGhost(ghost: PlaceGhost | null, blocker: OverlayProp | null) {
    this.shown = ghost
    this.blockerProp = blocker
    this.drawGhost()
  }

  private pt(x: number, z: number) {
    return this.project([x * this.unit, z * this.unit])
  }

  private poly(points: [number, number][]) {
    return 'M' + points.map(([x, z]) => this.pt(x, z).join(' ')).join('L') + 'Z'
  }

  private rect(x0: number, z0: number, x1: number, z1: number) {
    return this.poly([
      [x0, z0],
      [x1, z0],
      [x1, z1],
      [x0, z1],
    ])
  }

  private drawPlaces() {
    const open = this.floors.filter((f) => this.grids.get(f.id)?.cells.includes('.') ?? true)
    const shut = this.floors.filter((f) => !open.includes(f))
    const box = ({ bounds: b }: OverlayFloor) => this.rect(b.x, b.y, b.x + b.w, b.y + b.h)
    // 遮罩：一大块减去还能放的地点。外框取所有地点外面很远的一圈，转了方位角也盖得住画面
    let x0 = Infinity,
      z0 = Infinity,
      x1 = -Infinity,
      z1 = -Infinity
    for (const { bounds: b } of this.floors) {
      x0 = Math.min(x0, b.x)
      z0 = Math.min(z0, b.y)
      x1 = Math.max(x1, b.x + b.w)
      z1 = Math.max(z1, b.y + b.h)
    }
    const far = Number.isFinite(x0) ? Math.max(x1 - x0, z1 - z0, 50) * 20 : 0
    this.mask.setAttribute(
      'd',
      far ? this.rect(x0 - far, z0 - far, x1 + far, z1 + far) + open.map(box).join('') : ''
    )
    this.frames.setAttribute('d', open.map(box).join(''))
    this.full.setAttribute('d', shut.map(box).join(''))
    // 地点里放不下的格子压暗一点，能放的格子画亮
    this.dim.setAttribute('d', [...this.grids.values()].map((g) => this.gridBox(g)).join(''))
    this.cellPaths.clear()
    for (const g of this.grids.values()) {
      const h = g.step / 2
      let d = ''
      for (const c of cells(g))
        if (c.code === '.') d += this.rect(c.at[0] - h, c.at[1] - h, c.at[0] + h, c.at[1] + h)
      this.cellPaths.set(g.locale, d)
    }
    // 下一次 setVisible 重新拼
    this.visibleKey = null
  }

  /** 格子覆盖的那一块（米）：格点外扩半格 */
  private gridBox(g: PlaceGrid) {
    const h = g.step / 2
    return this.rect(
      g.origin[0] - h,
      g.origin[1] - h,
      g.origin[0] + (g.columns - 1) * g.step + h,
      g.origin[1] + (g.rows - 1) * g.step + h
    )
  }

  private drawHot() {
    const g = this.hot ? this.grids.get(this.hot) : undefined
    this.walks.setAttribute(
      'd',
      this.hotWalks
        .filter((line) => line.length > 1)
        .map((line) => 'M' + line.map(([x, z]) => this.pt(x, z).join(' ')).join('L'))
        .join('')
    )
    if (!g) {
      this.door.setAttribute('d', '')
      return
    }
    const [ex, ez] = g.entrance,
      r = g.entrance_clearance
    const ring: [number, number][] = []
    for (let i = 0; i < 48; i++) {
      const k = (i / 48) * Math.PI * 2
      ring.push([ex + Math.cos(k) * r, ez + Math.sin(k) * r])
    }
    this.door.setAttribute('d', this.poly(ring))
  }

  private drawGhost() {
    const ghost = this.shown
    const clear = [this.ghost, this.ghostHalo, this.link, this.cross, this.blockLine, this.blocker]
    if (!ghost) {
      for (const node of clear) node.setAttribute('d', '')
      return
    }
    const [x, z] = ghost.at.position,
      [w, d] = ghost.size
    const box = this.rect(x - w / 2, z - d / 2, x + w / 2, z + d / 2)
    this.ghost.setAttribute('d', box)
    this.ghostHalo.setAttribute('d', box)
    this.ghost.classList.toggle('bad', !!ghost.bad)
    const from = ghost.from?.position
    if (from) {
      const r = 0.22
      this.link.setAttribute('d', `M${this.pt(...from).join(' ')}L${this.pt(x, z).join(' ')}`)
      this.cross.setAttribute(
        'd',
        `M${this.pt(from[0] - r, from[1] - r).join(' ')}L${this.pt(from[0] + r, from[1] + r).join(' ')}` +
          `M${this.pt(from[0] + r, from[1] - r).join(' ')}L${this.pt(from[0] - r, from[1] + r).join(' ')}`
      )
    } else {
      this.link.setAttribute('d', '')
      this.cross.setAttribute('d', '')
    }
    // 从入口过来被挡：红虚线从入口连到指针，描红挡路的那件
    const g = this.hot ? this.grids.get(this.hot) : undefined
    if (ghost.blockedBy != null && from && g) {
      this.blockLine.setAttribute(
        'd',
        `M${this.pt(...g.entrance).join(' ')}L${this.pt(...from).join(' ')}`
      )
      const p = this.blockerProp
      this.blocker.setAttribute(
        'd',
        p
          ? this.rect(
              p.position[0] - p.footprint[0] / 2 - BLOCKER_PAD,
              p.position[1] - p.footprint[1] / 2 - BLOCKER_PAD,
              p.position[0] + p.footprint[0] / 2 + BLOCKER_PAD,
              p.position[1] + p.footprint[1] / 2 + BLOCKER_PAD
            )
          : ''
      )
    } else {
      this.blockLine.setAttribute('d', '')
      this.blocker.setAttribute('d', '')
    }
  }
}
