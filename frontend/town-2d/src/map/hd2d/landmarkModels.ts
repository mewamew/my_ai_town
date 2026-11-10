import * as THREE from 'three'
import { hash } from '../pixel/noise'
import type { LandmarkModel } from './landmarks'
import { T, type Kit } from './propKit'
import { kitMeshes } from './propModels'

// 搭成立体的户外标志物（摊棚、船，见 landmarks.ts 的 LandmarkModel）进场景：和道具一样是积木搭的，
// 全镇共用一对材质（朝上的面、立着的面），发光的面按颜色各一个。浮在水上的随波上下起伏、左右轻摇。

/** 浮着的上下起伏多高（世界单位）、左右摇多少（弧度） */
const BOB = 0.25 * T
const SWAY = 0.035

export class LandmarkModels {
  readonly group = new THREE.Group()
  readonly top = new THREE.MeshLambertMaterial({ vertexColors: true })
  readonly side = new THREE.MeshLambertMaterial({ vertexColors: true })
  private readonly lit = new Map<string, THREE.MeshLambertMaterial>()
  private readonly floating: { body: THREE.Group; roll: number; phase: number; rate: number }[] = []

  /** glowing：入夜才亮的材质交给场景，跟着别的灯一起亮 */
  constructor(private readonly glowing: (material: THREE.Material, on: number) => void) {}

  private litOf(color: string, always: boolean) {
    const key = `${color}${always}`
    let m = this.lit.get(key)
    if (!m) {
      m = new THREE.MeshLambertMaterial({
        color,
        emissive: color,
        emissiveIntensity: always ? 0.85 : 0,
      })
      this.lit.set(key, m)
      if (!always) this.glowing(m, 0.06)
    }
    return m
  }

  /** 把搭好的料放到 (x, y)（地图坐标），按 model 转向、歪斜；返回它的灯（世界坐标） */
  add(kit: Kit, model: LandmarkModel, x: number, y: number) {
    const turn = new THREE.Group(),
      body = new THREE.Group()
    turn.add(body)
    kitMeshes(kit, body, this.top, this.side, (color, always) => this.litOf(color, always))
    turn.position.set(x, 0, y)
    turn.rotation.y = -(model.angle ?? 0)
    const roll = model.roll ?? 0
    body.rotation.x = roll
    this.group.add(turn)
    if (model.float)
      this.floating.push({
        body,
        roll,
        phase: hash(Math.round(x), Math.round(y), 5) * Math.PI * 2,
        rate: 0.8 + hash(Math.round(y), Math.round(x), 6) * 0.4,
      })
    turn.updateMatrixWorld(true)
    return kit.lamps.map((l) => ({
      ...l,
      at: new THREE.Vector3(...l.at).applyMatrix4(body.matrixWorld),
    }))
  }

  /** 浮着的随波起伏；seconds 是场景时间 */
  step(seconds: number) {
    for (const f of this.floating) {
      const t = seconds * f.rate + f.phase
      f.body.position.y = Math.sin(t * 1.7) * BOB
      f.body.rotation.x = f.roll + Math.sin(t * 1.1 + 1) * SWAY
    }
  }
}
