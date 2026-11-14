import * as THREE from 'three'
import type { FrostlightView } from 'town-shared/protocol'

/** 压实煤灰和融雪边界直接画在地面上；白天与雪幕下也能读出中央广场。 */
function hearthTexture() {
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = 256
  const ctx = canvas.getContext('2d')!
  const shade = ctx.createRadialGradient(128, 128, 36, 128, 128, 128)
  shade.addColorStop(0, '#343437')
  shade.addColorStop(0.48, '#4d4a45')
  shade.addColorStop(0.72, 'rgba(94, 78, 60, .94)')
  shade.addColorStop(0.88, 'rgba(116, 91, 64, .6)')
  shade.addColorStop(1, 'rgba(116, 91, 64, 0)')
  ctx.fillStyle = shade
  ctx.fillRect(0, 0, 256, 256)
  // 短石缝和炉灰保留像素颗粒；位置由索引确定，重进小镇不会闪变。
  for (let i = 0; i < 160; i++) {
    const angle = i * 2.39996
    const radius = 30 + ((i * 47) % 77)
    const x = Math.round(128 + Math.cos(angle) * radius)
    const y = Math.round(128 + Math.sin(angle) * radius)
    ctx.fillStyle = i % 3 ? 'rgba(21, 29, 35, .22)' : 'rgba(207, 164, 99, .2)'
    ctx.fillRect(x, y, 3 + (i % 3), 2)
  }
  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace
  texture.magFilter = THREE.NearestFilter
  return texture
}

/** 热源是场景里的实体几何；不改摄像机或全场材质，景深与边缘雾化照常作用于它。 */
export class FrostlightFurnace {
  private group = new THREE.Group()
  private flames = new THREE.Group()
  private glow = new THREE.MeshBasicMaterial({
    color: 0xff902e,
    transparent: true,
    opacity: 0.3,
    depthWrite: false,
    toneMapped: false,
    side: THREE.DoubleSide,
  })
  private fire = new THREE.MeshBasicMaterial({ color: 0xffb343, toneMapped: false })
  private ring: THREE.Mesh
  private halo: THREE.Mesh
  private lamp = new THREE.PointLight(0xffad5a, 15, 1100, 0.5)
  private steam: THREE.Mesh[] = []
  private view: FrostlightView | null = null

  constructor(scene: THREE.Scene) {
    const hearth = new THREE.Mesh(
      new THREE.CircleGeometry(320, 96),
      new THREE.MeshBasicMaterial({
        map: hearthTexture(),
        transparent: true,
        depthWrite: false,
        toneMapped: false,
      })
    )
    hearth.rotation.x = -Math.PI / 2
    hearth.position.y = 1
    hearth.renderOrder = 1
    this.group.add(hearth)
    const steel = new THREE.MeshStandardMaterial({
      color: 0x34404a,
      roughness: 0.8,
      metalness: 0.35,
      flatShading: true,
    })
    const copper = new THREE.MeshStandardMaterial({
      color: 0x956741,
      roughness: 0.65,
      metalness: 0.4,
      flatShading: true,
    })
    const stone = new THREE.MeshStandardMaterial({
      color: 0x707e84,
      roughness: 1,
      flatShading: true,
    })
    const snow = new THREE.MeshStandardMaterial({
      color: 0xd6e2e9,
      roughness: 1,
      flatShading: true,
    })
    const cylinder = (
      top: number,
      bottom: number,
      height: number,
      y: number,
      material: THREE.Material,
      sides = 12
    ) => {
      const mesh = new THREE.Mesh(new THREE.CylinderGeometry(top, bottom, height, sides), material)
      mesh.position.y = y
      mesh.castShadow = true
      mesh.receiveShadow = true
      this.group.add(mesh)
      return mesh
    }
    cylinder(120, 136, 22, 11, stone)
    cylinder(101, 113, 9, 26, snow)
    cylinder(74, 87, 16, 36, copper)
    cylinder(53, 65, 142, 111, steel)
    cylinder(69, 70, 9, 64, copper)
    cylinder(57, 61, 10, 155, copper)
    cylinder(39, 60, 23, 191, steel)
    cylinder(30, 34, 62, 229, steel)
    cylinder(39, 39, 8, 261, copper)
    cylinder(42, 32, 6, 267, snow)
    // 六片护筋与检修踏台围出炉体；橙色炉门从任意旋转方向都能看见。
    for (let i = 0; i < 6; i++) {
      const angle = (i * Math.PI) / 3
      const rib = new THREE.Mesh(new THREE.BoxGeometry(12, 104, 16), copper)
      rib.position.set(Math.sin(angle) * 64, 98, Math.cos(angle) * 64)
      rib.rotation.y = angle
      this.group.add(rib)
      const door = new THREE.Mesh(new THREE.BoxGeometry(29, 58, 6), this.fire)
      door.position.set(Math.sin(angle + Math.PI / 6) * 65, 100, Math.cos(angle + Math.PI / 6) * 65)
      door.rotation.y = angle + Math.PI / 6
      this.group.add(door)
      const pipe = new THREE.Mesh(new THREE.CylinderGeometry(6, 6, 94, 6), steel)
      pipe.rotation.z = Math.PI / 2
      pipe.rotation.y = angle
      pipe.position.set(Math.cos(angle) * 100, 37, -Math.sin(angle) * 100)
      this.group.add(pipe)
      const brace = new THREE.Mesh(new THREE.BoxGeometry(12, 5, 174), copper)
      brace.position.set(Math.sin(angle) * 170, 4, Math.cos(angle) * 170)
      brace.rotation.y = angle
      this.group.add(brace)
    }
    for (let i = 0; i < 4; i++) {
      const flame = new THREE.Mesh(
        new THREE.ConeGeometry(16 - i * 2, 54 + i * 7, 5),
        new THREE.MeshBasicMaterial({
          color: i % 2 ? 0xffe2a0 : 0xff8d2f,
          toneMapped: false,
        })
      )
      flame.position.set(Math.sin(i * 2) * 14, 270 + i * 4, Math.cos(i * 2) * 14)
      this.flames.add(flame)
    }
    this.group.add(this.flames)
    this.halo = new THREE.Mesh(new THREE.CircleGeometry(245, 64), this.glow)
    this.halo.rotation.x = -Math.PI / 2
    this.halo.position.y = 3
    this.halo.renderOrder = 2
    this.group.add(this.halo)
    this.ring = new THREE.Mesh(
      new THREE.RingGeometry(274, 280, 96),
      new THREE.MeshBasicMaterial({
        color: 0xffbd68,
        transparent: true,
        opacity: 0.65,
        toneMapped: false,
        side: THREE.DoubleSide,
        depthWrite: false,
      })
    )
    this.ring.rotation.x = -Math.PI / 2
    this.ring.position.y = 4
    this.ring.renderOrder = 3
    this.group.add(this.ring)
    this.lamp.position.y = 145
    this.group.add(this.lamp)
    for (let i = 0; i < 9; i++) {
      const puff = new THREE.Mesh(
        new THREE.IcosahedronGeometry(14, 0),
        new THREE.MeshBasicMaterial({
          color: 0xb6c9d3,
          transparent: true,
          opacity: 0.2,
          depthWrite: false,
        })
      )
      this.steam.push(puff)
      this.group.add(puff)
    }
    this.group.visible = false
    scene.add(this.group)
  }
  set(view: FrostlightView | null, spot: { x: number; z: number } | null) {
    this.view = view
    this.group.visible = !!view && !!spot
    if (spot) this.group.position.set(spot.x, 0, spot.z)
    if (!view) return
    const lit = view.heat > 0 && view.fuel > 0 && view.ending?.kind !== 'frozen'
    this.flames.visible = lit
    this.lamp.intensity = lit ? 9 + view.heat * 4 : 0
    this.halo.visible = lit
    this.ring.visible = lit
    this.ring.scale.setScalar(0.82 + view.heat * 0.075)
    this.halo.scale.setScalar(0.85 + view.heat * 0.1)
    this.fire.color.setHex(!lit ? 0x322a29 : view.heat === 3 ? 0xff5937 : 0xffb343)
    this.glow.color.setHex(view.heat === 3 ? 0xff5b2e : 0xff902e)
    for (const puff of this.steam) puff.visible = lit
  }
  step(t: number) {
    if (!this.group.visible || !this.view || !this.flames.visible) return false
    const steady = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    const flicker = steady ? 1 : 1 + Math.sin(t * 9) * 0.06 + Math.cos(t * 13) * 0.04
    this.flames.scale.y = flicker
    this.glow.opacity = (0.2 + this.view.heat * 0.045) * flicker
    for (let i = 0; i < this.steam.length; i++) {
      const age = ((steady ? i * 0.55 : t * 0.28 + i * 0.55) % 5) / 5
      const puff = this.steam[i]
      puff.position.set(18 + age * 130, 280 + age * 180, age * 32 + Math.sin(i) * 12)
      puff.scale.setScalar(0.8 + age * 2.8)
      ;(puff.material as THREE.MeshBasicMaterial).opacity = (1 - age) * 0.2
    }
    return !steady
  }
}
