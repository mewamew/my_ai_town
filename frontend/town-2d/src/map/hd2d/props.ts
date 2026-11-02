import * as THREE from 'three'
import { PIXEL } from '../grid'
import type { Tilt } from './layout'
import { pixelFilter, stand, standee } from './standee'

// 道具立牌：道具像素图立在地上，和树、村民一样按俯角转向镜头、和墙互相遮挡。
// SVG 层只留道具的点击区和名字。道具可以被拿走、放回、新增，每次按渲染层给的名单同步。

/** 道具像素图的边长（像素，24 格加一圈描边） */
const ART = 26
/** 平面图上道具图以落点为中心；立起来后底边往南挪一点，看上去占的还是那块地 */
export const PROP_BASE = 0.3

export interface PropPlacement {
  id: string
  url: string
  /** 道具图中心（地图坐标） */
  x: number
  y: number
  /** 道具图边长（地图单位） */
  size: number
  visible: boolean
}

interface Standing {
  mesh: THREE.Mesh
  placement: PropPlacement
}

export class PropStandees {
  private readonly all = new Map<string, Standing>()
  private readonly textures = new Map<string, THREE.Texture>()
  private readonly loader = new THREE.TextureLoader()

  /** prepare：每个新立牌的材质过一遍（接光照图） */
  constructor(
    private readonly scene: THREE.Scene,
    private tilt: Tilt,
    private readonly onLoad: () => void,
    private readonly prepare?: (material: THREE.Material) => void
  ) {}

  private texture(url: string) {
    let t = this.textures.get(url)
    if (!t) {
      t = pixelFilter(this.loader.load(url, () => this.onLoad()))
      t.colorSpace = THREE.SRGBColorSpace
      this.textures.set(url, t)
    }
    return t
  }

  sync(placements: PropPlacement[]) {
    const seen = new Set<string>()
    for (const p of placements) {
      seen.add(p.id)
      let s = this.all.get(p.id)
      if (s && (s.placement.url !== p.url || s.placement.size !== p.size)) {
        this.remove(p.id)
        s = undefined
      }
      if (!s) {
        const mesh = standee(this.texture(p.url), {
          scale: p.size / (ART * PIXEL),
          frame: [ART, ART],
        })
        this.prepare?.(mesh.material as THREE.Material)
        this.scene.add(mesh)
        s = { mesh, placement: p }
        this.all.set(p.id, s)
      }
      s.placement = p
      s.mesh.visible = p.visible
      this.place(s)
    }
    for (const id of [...this.all.keys()]) if (!seen.has(id)) this.remove(id)
  }

  setTilt(tilt: Tilt) {
    this.tilt = tilt
    for (const s of this.all.values()) this.place(s)
  }

  private place({ mesh, placement: p }: Standing) {
    stand(mesh, p.x, p.y, this.tilt, p.size * PROP_BASE)
  }

  private remove(id: string) {
    const s = this.all.get(id)
    if (!s) return
    this.scene.remove(s.mesh)
    s.mesh.geometry.dispose()
    ;(s.mesh.material as THREE.Material).dispose()
    this.all.delete(id)
  }

  dispose() {
    for (const id of [...this.all.keys()]) this.remove(id)
    for (const t of this.textures.values()) t.dispose()
  }
}
