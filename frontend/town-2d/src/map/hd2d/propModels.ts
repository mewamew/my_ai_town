import * as THREE from 'three'
import { hash, hashString } from '../pixel/noise'
import type { LightSource } from './lightmap'
import type { Tilt } from './layout'
import { turned, type Turn } from './propArrange'
import type { Build } from './propBuilds'
import { Kit } from './propKit'
import { ChimneySmoke } from './smoke'

// 立体道具进场景：把搭好的料（propKit.ts）变成网格，接上影子、光照图、夜里的灯和热气。
// 全镇的道具共用两对材质（朝上的面、立着的面，屋里屋外各一对），发光的面按颜色各一个。
// 摆在哪、朝哪由场景按房间算好（propArrange.ts）再交进来；这里只管搭和显隐。

export interface ModelPlacement {
  id: string
  build: Build
  /** 数量（一摞书有几本），搭法要用的才给 */
  amount?: number
  /** 模型原点（地图坐标）和转几个直角 */
  x: number
  y: number
  turn: Turn
  visible: boolean
  /** 在哪栋房子里：它的灯只在屋顶掀开时照亮屋里；室外的不给 */
  house?: string
}

/** 一种搭法量出来的尺寸，布置时用 */
export interface Measure {
  foot: Kit['foot']
  wall: boolean
  lounge: boolean
  tall: number
}

export interface ModelHooks {
  /** 入夜才亮的材质交给场景，跟着别的灯一起亮 */
  glowing(material: THREE.Material, on: number): void
  /** 在世界坐标 (x, y, z) 加一片光晕 */
  glow(x: number, y: number, z: number, size: number, on: number): THREE.Sprite
  /** 拆掉一片光晕 */
  unglow(sprite: THREE.Sprite): void
  /** 道具立在 (x, y) 要垫高多少（看台、亭子的台面） */
  lift(x: number, y: number): number
  /** 灯有增减：场景重排光照图的光源 */
  changed(): void
}

interface Built {
  placement: ModelPlacement
  group: THREE.Group
  /** 受光的网格：指着、选中时在它们上面叠一层亮色 */
  solid: THREE.Mesh[]
  lamps: {
    at: THREE.Vector3
    reach: number
    color: THREE.Color
    on: number
    sprite: THREE.Sprite
  }[]
  steam?: ChimneySmoke
  /** 用它的人站在哪、垫高多少 */
  use: { x: number; y: number; lift: number }
  tall: number
}

/** 热气用烟囱的烟缩小了画：一团烟缩到这么大 */
const STEAM_SCALE = 0.2
/** 人站在道具正面跟前，离占地边这么远 */
const STAND_GAP = 16

export class PropModels {
  readonly group = new THREE.Group()
  readonly top = new THREE.MeshLambertMaterial({ vertexColors: true })
  readonly side = new THREE.MeshLambertMaterial({ vertexColors: true })
  /** 室外的道具另用一对材质：场景给它们补积雪、淋湿和云影 */
  readonly topOut = new THREE.MeshLambertMaterial({ vertexColors: true })
  readonly sideOut = new THREE.MeshLambertMaterial({ vertexColors: true })
  private readonly contact = new THREE.MeshBasicMaterial({
    color: '#161019',
    transparent: true,
    opacity: 0.2,
    depthWrite: false,
  })
  private readonly night = new Map<string, THREE.MeshLambertMaterial>()
  private readonly always = new Map<string, THREE.MeshLambertMaterial>()
  private readonly tints = {
    picked: this.tint('#ffcf7a', 0.1),
    hovered: this.tint('#fff3d6', 0.05),
  }
  private readonly all = new Map<string, Built>()
  private readonly measures = new Map<Build, Measure>()
  private readonly halos: THREE.Mesh[] = []
  private picked: [string | null, string | null] = [null, null]
  private tilt?: Tilt

  constructor(private readonly hooks: ModelHooks) {}

  private tint(color: string, opacity: number) {
    return new THREE.MeshBasicMaterial({
      color,
      transparent: true,
      opacity,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -2,
      polygonOffsetUnits: -2,
    })
  }

  /** 这种搭法占多大的地、靠不靠墙 */
  measure(build: Build, amount?: number): Measure {
    let m = amount === undefined ? this.measures.get(build) : undefined
    if (!m) {
      const kit = new Kit()
      build(kit, 0, amount)
      m = { foot: kit.foot, wall: kit.wall, lounge: kit.lounge, tall: kit.tall }
      if (amount === undefined) this.measures.set(build, m)
    }
    return m
  }

  private lit(color: string, always: boolean) {
    const map = always ? this.always : this.night
    let m = map.get(color)
    if (!m) {
      m = new THREE.MeshLambertMaterial({
        color,
        emissive: color,
        emissiveIntensity: always ? 0.85 : 0,
      })
      map.set(color, m)
      if (!always) this.hooks.glowing(m, 0.06)
    }
    return m
  }

  private build(p: ModelPlacement): Built {
    const seed = hashString(p.id)
    const kit = new Kit()
    p.build(kit, seed, p.amount)
    const group = new THREE.Group()
    const solid: THREE.Mesh[] = []
    const add = (geometry: THREE.BufferGeometry, material: THREE.Material, lit = true) => {
      if (!geometry.getAttribute('position').count) return
      const mesh = new THREE.Mesh(geometry, material)
      mesh.castShadow = mesh.receiveShadow = lit
      group.add(mesh)
      if (lit) solid.push(mesh)
    }
    add(kit.top.build(), p.house ? this.top : this.topOut)
    add(kit.side.build(), p.house ? this.side : this.sideOut)
    for (const [color, m] of kit.night) add(m.build(), this.lit(color, false), false)
    for (const [color, m] of kit.always) add(m.build(), this.lit(color, true), false)
    // 脚下压一圈影子，家具才像落在地板上
    const { cx, cz, hw, hd } = kit.foot
    if (hw > 0) {
      const blob = new THREE.Mesh(new THREE.PlaneGeometry((hw + 3) * 2, (hd + 3) * 2), this.contact)
      blob.rotation.x = -Math.PI / 2
      blob.position.set(cx, 0.7, cz + 1.5)
      blob.renderOrder = 1
      group.add(blob)
    }
    const up = this.hooks.lift(p.x, p.y)
    group.position.set(p.x, up, p.y)
    group.rotation.y = (p.turn * Math.PI) / 2
    group.updateMatrixWorld(true)
    const lamps = kit.lamps.map((l, i) => {
      const at = new THREE.Vector3(...l.at).applyMatrix4(group.matrixWorld)
      const on = 0.04 + hash(seed, i, 7) * 0.08
      return {
        at,
        reach: l.reach,
        color: new THREE.Color(l.color).multiplyScalar(1.25 * l.strength),
        on,
        sprite: this.hooks.glow(at.x, at.y, at.z, l.size, on),
      }
    })
    let steam: ChimneySmoke | undefined
    if (kit.steam.length) {
      steam = new ChimneySmoke()
      steam.group.scale.setScalar(STEAM_SCALE)
      for (const s of kit.steam) {
        const at = new THREE.Vector3(...s).applyMatrix4(group.matrixWorld)
        steam.add(at.x / STEAM_SCALE, at.y / STEAM_SCALE, at.z / STEAM_SCALE, seed)
      }
      if (this.tilt) steam.setTilt(this.tilt)
      this.group.add(steam.group)
    }
    this.group.add(group)
    const [ux, uy] = turned(...(kit.use?.at ?? [cx, cz + hd + STAND_GAP]), p.turn)
    return {
      placement: p,
      group,
      solid,
      lamps,
      steam,
      use: { x: p.x + ux, y: p.y + uy, lift: up + (kit.use?.lift ?? 0) },
      tall: kit.tall,
    }
  }

  /** 按名单同步：新来的搭起来，挪了地方、换了搭法的重搭，不在名单里的拆掉 */
  sync(placements: ModelPlacement[]) {
    const seen = new Set<string>()
    let changed = false
    for (const p of placements) {
      seen.add(p.id)
      let b = this.all.get(p.id)
      const was = b?.placement
      if (
        was &&
        (was.build !== p.build ||
          was.x !== p.x ||
          was.y !== p.y ||
          was.turn !== p.turn ||
          was.amount !== p.amount ||
          was.house !== p.house)
      ) {
        this.remove(p.id)
        b = undefined
      }
      if (!b) {
        b = this.build(p)
        this.all.set(p.id, b)
        changed = true
      }
      b.placement = p
      b.group.visible = p.visible
      if (b.steam) b.steam.group.visible = p.visible
      for (const l of b.lamps) l.sprite.visible = p.visible
    }
    for (const id of [...this.all.keys()])
      if (!seen.has(id)) {
        this.remove(id)
        changed = true
      }
    if (changed) {
      this.hooks.changed()
      this.applyPicked()
    }
  }

  has(id: string) {
    return this.all.has(id)
  }

  /** 用这件道具的人站在哪（地图坐标）、垫高多少 */
  useOf(id: string) {
    return this.all.get(id)?.use
  }

  /** 这一点上的人要垫高多少：躺在床上的人 */
  liftAt(x: number, y: number) {
    for (const b of this.all.values())
      if (b.use.lift && Math.abs(b.use.x - x) < 6 && Math.abs(b.use.y - y) < 6) return b.use.lift
    return 0
  }

  /** 道具自己的灯：屋里的只在屋顶掀开时照亮地板和墙，室外的和路灯一样 */
  lights(): LightSource[] {
    const out: LightSource[] = []
    for (const b of this.all.values())
      for (const l of b.lamps)
        out.push({
          kind: b.placement.house ? 'prop' : 'lamp',
          x: l.at.x,
          y: l.at.z,
          reach: l.reach,
          color: l.color,
          on: l.on,
          house: b.placement.house,
        })
    return out
  }

  /** 选中的道具（暖色）、指着的道具（白）：在它身上叠一层亮色 */
  setPicked(picked: string | null, hovered: string | null) {
    if (this.picked[0] === picked && this.picked[1] === hovered) return
    this.picked = [picked, hovered]
    this.applyPicked()
  }

  private applyPicked() {
    for (const m of this.halos) m.removeFromParent()
    this.halos.length = 0
    const [picked, hovered] = this.picked
    const wear = (id: string | null, material: THREE.Material) => {
      const b = id ? this.all.get(id) : undefined
      if (!b) return
      for (const mesh of b.solid) {
        const halo = new THREE.Mesh(mesh.geometry, material)
        halo.renderOrder = 3
        b.group.add(halo)
        this.halos.push(halo)
      }
    }
    wear(picked, this.tints.picked)
    if (hovered !== picked) wear(hovered, this.tints.hovered)
  }

  setTilt(tilt: Tilt) {
    this.tilt = tilt
    for (const b of this.all.values()) b.steam?.setTilt(tilt)
  }

  /** 热气往上飘；seconds 是场景时间 */
  step(seconds: number) {
    for (const b of this.all.values()) if (b.steam && b.group.visible) b.steam.step(seconds * 1.6)
  }

  private remove(id: string) {
    const b = this.all.get(id)
    if (!b) return
    this.group.remove(b.group)
    const halos = new Set<THREE.Object3D>(this.halos)
    b.group.traverse((o) => {
      if (o instanceof THREE.Mesh && !halos.has(o)) o.geometry.dispose()
    })
    if (b.steam) {
      this.group.remove(b.steam.group)
      b.steam.dispose()
    }
    for (const l of b.lamps) this.hooks.unglow(l.sprite)
    this.all.delete(id)
  }

  dispose() {
    for (const id of [...this.all.keys()]) this.remove(id)
    for (const m of [
      this.top,
      this.side,
      this.topOut,
      this.sideOut,
      this.contact,
      this.tints.picked,
      this.tints.hovered,
      ...this.night.values(),
      ...this.always.values(),
    ])
      m.dispose()
  }
}
