import * as THREE from 'three'
import { PIXEL } from '../grid'
import type { Tilt } from './layout'
import { texture } from './standee'
import { pixelMaterial } from './pixelSampling'
import { noise } from '../pixel/noise'

/** 烟也随阵风偏：和树、草同一个风向（往东），强弱按位置和时间一阵阵起伏 */
function gust(x: number, z: number, seconds: number) {
  return noise((x * 0.98 + z * 0.18) / (120 * PIXEL) - seconds * 0.35, 0.5, 7)
}

// 烟囱冒的烟：每根烟囱一串烟团，从烟囱口往上飘、顺风往东偏，越飘越大越淡，飘完从烟囱口重新冒出来。
// 烟团是朝向镜头的像素小片，受场景光照，夜里跟着暗下去。

/** 每根烟囱几团烟、一团从冒出到散掉几秒 */
const PUFFS = 6
const LIFE = 5
/** 一团烟飘完升高、往东偏多少（地图像素） */
const RISE = 26
const DRIFT = 10

/** 一团烟：两档灰白，右下压一点阴影 */
function puffCanvas() {
  const c = document.createElement('canvas')
  c.width = c.height = 8
  const x = c.getContext('2d')!
  const rows = ['..xxxx..', '.xxxxxx.', 'xxxxxxxx', 'xxxxxxxs', 'xxxxxxss', '.xxxxss.', '..ssss..']
  rows.forEach((row, j) =>
    [...row].forEach((ch, i) => {
      if (ch === '.') return
      x.fillStyle = ch === 's' ? '#c4c2bc' : '#ecebe6'
      x.fillRect(i, j + 1, 1, 1)
    })
  )
  return c
}

interface Puff {
  mesh: THREE.Mesh
  material: THREE.MeshLambertMaterial
  origin: THREE.Vector3
  phase: number
}

export class ChimneySmoke {
  readonly group = new THREE.Group()
  private readonly puffs: Puff[] = []
  private readonly geometry = new THREE.PlaneGeometry(8 * PIXEL, 8 * PIXEL)
  private readonly map = texture(puffCanvas())

  /** 烟囱口在世界坐标 (x, y, z)；seed 错开各根烟囱的节奏 */
  add(x: number, y: number, z: number, seed: number) {
    for (let k = 0; k < PUFFS; k++) {
      const material = pixelMaterial(
        new THREE.MeshLambertMaterial({
          map: this.map,
          transparent: true,
          depthWrite: false,
        })
      )
      const mesh = new THREE.Mesh(this.geometry, material)
      mesh.renderOrder = 2
      this.group.add(mesh)
      this.puffs.push({
        mesh,
        material,
        origin: new THREE.Vector3(x, y, z),
        phase: k / PUFFS + (seed % 97) / 97,
      })
    }
    this.step(0)
  }

  /** seconds 是场景时间；要求减少动画时只在建好时摆一次 */
  step(seconds: number) {
    for (const p of this.puffs) {
      const age = (seconds / LIFE + p.phase) % 1
      const sway = Math.sin(age * 6 + p.phase * 20) * 1.5
      const drift = DRIFT * (0.5 + 1.4 * gust(p.origin.x, p.origin.z, seconds))
      p.mesh.position.set(
        p.origin.x + (age * drift + sway) * PIXEL,
        p.origin.y + age * RISE * PIXEL,
        p.origin.z
      )
      p.mesh.scale.setScalar(0.5 + age * 1.1)
      // 刚冒出来时很快变浓，之后慢慢散掉
      p.material.opacity = 0.8 * Math.min(1, age * 8) * (1 - age) ** 1.3
    }
  }

  /** 烟团和立牌一样按俯角后仰，正对镜头 */
  setTilt(tilt: Tilt) {
    for (const p of this.puffs) p.mesh.rotation.set(-tilt.pitch, tilt.yaw, 0, 'YXZ')
  }
}
