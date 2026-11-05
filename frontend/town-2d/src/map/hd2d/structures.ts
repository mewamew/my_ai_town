import * as THREE from 'three'
import { PIXEL } from '../grid'
import { WALL_TEXEL, type House } from './layout'

// 特殊建筑的立体部件：剧院的拱顶、柱廊图书馆门前的石柱（海塔整栋另搭，见 lighthouse.ts）。
// 都以房屋中心的地面为原点，x 沿屋脊方向（拱顶）或东西方向（石柱）。

/** 半圆拱顶：沿 x 轴，宽 rd、长 rl，高出墙顶 rise；两头的半圆面用墙面材质 */
export function vaultRoof(
  rl: number,
  rd: number,
  wallH: number,
  rise: number,
  material: THREE.Material,
  endMaterial: THREE.Material
) {
  const radius = rd / 2
  const shell = new THREE.CylinderGeometry(radius, radius, rl, 20, 1, true, 0, Math.PI)
  shell.rotateZ(Math.PI / 2)
  const end = new THREE.CircleGeometry(radius, 20, 0, Math.PI)
  const group = new THREE.Group()
  group.add(new THREE.Mesh(shell, material))
  for (const side of [-1, 1]) {
    const cap = new THREE.Mesh(end, endMaterial)
    cap.rotation.y = (side * Math.PI) / 2
    cap.position.x = (side * rl) / 2
    group.add(cap)
  }
  group.scale.y = rise / radius
  group.position.y = wallH
  group.traverse((o) => {
    o.castShadow = o.receiveShadow = true
  })
  return group
}

/** 南墙前一排石柱，顶上一道横梁 */
export function colonnadeFront(house: House) {
  const group = new THREE.Group()
  const material = new THREE.MeshLambertMaterial({ color: '#e4ddcc' })
  const height = house.wallH * 0.85
  const z = house.h / 2 + 5 * PIXEL
  const count = Math.max(3, Math.floor(house.w / (16 * PIXEL)))
  const span = house.w - 8 * PIXEL
  for (let k = 0; k < count; k++) {
    const column = new THREE.Mesh(
      new THREE.CylinderGeometry(1.8 * PIXEL, 2 * PIXEL, height, 8),
      material
    )
    column.position.set(-span / 2 + (span * k) / (count - 1), height / 2, z)
    group.add(column)
  }
  const beam = new THREE.Mesh(
    new THREE.BoxGeometry(house.w - 2 * PIXEL, 3 * WALL_TEXEL, 8 * PIXEL),
    material
  )
  beam.position.set(0, height + 1.5 * WALL_TEXEL, z - 2 * PIXEL)
  group.add(beam)
  group.traverse((o) => {
    o.castShadow = o.receiveShadow = true
  })
  return group
}
