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
// 烟团是朝向镜头的像素小片，受场景光照，夜里跟着暗下去。冰雪里家家冒烟，烟团一多就是几百片：
// 所有烟团是一个实例化网格，一次画完，每团的位置、大小、浓淡每拍写进实例。

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
  origin: THREE.Vector3
  phase: number
}

export class ChimneySmoke {
  readonly group = new THREE.Group()
  private readonly puffs: Puff[] = []
  private readonly material: THREE.MeshLambertMaterial
  private mesh?: THREE.InstancedMesh
  private alpha?: THREE.InstancedBufferAttribute
  private readonly turn = new THREE.Quaternion()
  private readonly m = new THREE.Matrix4()
  private readonly at = new THREE.Vector3()
  private readonly size = new THREE.Vector3()
  private last = 0

  constructor() {
    this.material = pixelMaterial(
      new THREE.MeshLambertMaterial({
        map: texture(puffCanvas()),
        transparent: true,
        depthWrite: false,
      })
    )
    this.material.onBeforeCompile = (shader) => {
      shader.vertexShader =
        'attribute float aAlpha;\nvarying float vPuffAlpha;\n' +
        shader.vertexShader.replace(
          '#include <uv_vertex>',
          '#include <uv_vertex>\n  vPuffAlpha = aAlpha;'
        )
      shader.fragmentShader =
        'varying float vPuffAlpha;\n' +
        shader.fragmentShader.replace(
          '#include <map_fragment>',
          '#include <map_fragment>\n  diffuseColor.a *= vPuffAlpha;'
        )
    }
    this.material.customProgramCacheKey = () => 'chimney-smoke'
  }

  /** 烟囱口在世界坐标 (x, y, z)；seed 错开各根烟囱的节奏 */
  add(x: number, y: number, z: number, seed: number) {
    for (let k = 0; k < PUFFS; k++)
      this.puffs.push({ origin: new THREE.Vector3(x, y, z), phase: k / PUFFS + (seed % 97) / 97 })
    this.build()
  }

  /** 烟团数变了就重建实例化网格（房子都建好以后就不再变） */
  private build() {
    if (this.mesh) {
      this.group.remove(this.mesh)
      this.mesh.geometry.dispose()
    }
    const n = this.puffs.length
    const geometry = new THREE.PlaneGeometry(8 * PIXEL, 8 * PIXEL)
    this.alpha = new THREE.InstancedBufferAttribute(new Float32Array(n), 1)
    this.alpha.setUsage(THREE.DynamicDrawUsage)
    geometry.setAttribute('aAlpha', this.alpha)
    this.mesh = new THREE.InstancedMesh(geometry, this.material, n)
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage)
    this.mesh.frustumCulled = false
    this.mesh.renderOrder = 2
    this.group.add(this.mesh)
    this.step(this.last)
  }

  /** seconds 是场景时间；要求减少动画时只在建好时摆一次 */
  step(seconds: number) {
    this.last = seconds
    const { mesh, alpha } = this
    if (!mesh || !alpha) return
    const a = alpha.array as Float32Array
    this.puffs.forEach((p, i) => {
      const age = (seconds / LIFE + p.phase) % 1
      const sway = Math.sin(age * 6 + p.phase * 20) * 1.5
      const drift = DRIFT * (0.5 + 1.4 * gust(p.origin.x, p.origin.z, seconds))
      this.at.set(
        p.origin.x + (age * drift + sway) * PIXEL,
        p.origin.y + age * RISE * PIXEL,
        p.origin.z
      )
      this.size.setScalar(0.5 + age * 1.1)
      this.m.compose(this.at, this.turn, this.size)
      mesh.setMatrixAt(i, this.m)
      // 刚冒出来时很快变浓，之后慢慢散掉
      a[i] = 0.8 * Math.min(1, age * 8) * (1 - age) ** 1.3
    })
    mesh.instanceMatrix.needsUpdate = true
    alpha.needsUpdate = true
  }

  /** 烟团和立牌一样按俯角后仰，正对镜头 */
  setTilt(tilt: Tilt) {
    this.turn.setFromEuler(new THREE.Euler(-tilt.pitch, tilt.yaw, 0, 'YXZ'))
    this.step(this.last)
  }
}
