import * as THREE from 'three'
import { pixelMaterial } from './pixelSampling'
import { PIXEL } from '../grid'
import { WALL_TEXEL, type House } from './layout'
import { texture } from './standee'
import { hash, noise } from '../pixel/noise'
import type { MapTheme } from '../themes/types'
import { LAMP_GLOW } from '../palette'

// 特殊建筑的立体部件：剧院的拱顶、海塔的灯塔、柱廊图书馆门前的石柱。
// 都以房屋中心的地面为原点，x 沿屋脊方向（拱顶）或东西方向（灯塔、石柱）。

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

/** 灯塔的红白横条：一格一个贴图像素；ruined 时漆褪了，锈水从上往下流，墙皮掉了几块 */
function stripes(height: number, ruined: boolean) {
  const canvas = document.createElement('canvas')
  canvas.width = 16
  canvas.height = height
  const x = canvas.getContext('2d')!
  const [red, white, redShade, whiteShade] = ruined
    ? ['#9a5a48', '#bfb6a2', '#7a4436', '#9a927e']
    : ['#c8453b', '#f1ece0', '#9a3028', '#cfc8b8']
  for (let j = 0; j < height; j++)
    for (let i = 0; i < 16; i++) {
      const band = Math.floor(j / 8) % 2
      let c = i >= 10 ? (band ? redShade : whiteShade) : band ? red : white
      if (ruined) {
        if (hash(i, 0, 5) < 0.2 && j < hash(i, 1, 5) * height * 0.6) c = '#6e4a32'
        if (noise(i / 3, j / 4, 7) > 0.7) c = '#7e7a72'
      }
      x.fillStyle = c
      x.fillRect(i, j, 1, 1)
    }
  return texture(canvas)
}

/** 灯塔立在房子的一头（side 为 1 是东头，-1 是西头）：条纹塔身、玻璃灯室、红色尖顶。lamp 是夜里发光的灯室材质。
 *  ruined 时灯室和尖顶都没了，塔顶是断口，上面架一盆火，夜里发橙光；
 *  beacon 时灯室上多两束对着的光，beam 交给场景转动和按夜色调亮 */
export function lighthouseTower(
  house: House,
  side: number,
  style: MapTheme['lighthouse']
): { group: THREE.Group; lamp: THREE.MeshLambertMaterial; beam?: THREE.Mesh } {
  const ruined = style === 'ruined'
  const radius = Math.min(house.w, house.h) * 0.2
  const towerH = house.wallH * 3.2
  const group = new THREE.Group()
  const body = new THREE.Mesh(
    new THREE.CylinderGeometry(radius * 0.8, radius, towerH, 16),
    pixelMaterial(
      new THREE.MeshLambertMaterial({ map: stripes(Math.round(towerH / WALL_TEXEL), ruined) })
    )
  )
  body.position.y = towerH / 2
  group.position.set(side * (house.w / 2 - radius * 1.2), 0, 0)
  if (ruined) {
    // 断口：一圈高低不齐的残墙
    const broken = new THREE.MeshLambertMaterial({ color: '#8a7e6c' })
    for (let k = 0; k < 7; k++) {
      const a = (k / 7) * Math.PI * 2
      const h = (1 + hash(k, 2, 9) * 4) * WALL_TEXEL
      const chunk = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.5, h, radius * 0.3), broken)
      chunk.position.set(Math.cos(a) * radius * 0.7, towerH + h / 2, Math.sin(a) * radius * 0.7)
      chunk.rotation.y = -a
      group.add(chunk)
    }
    const fire = new THREE.MeshLambertMaterial({
      color: '#3a2a20',
      emissive: '#ff7a2a',
      emissiveIntensity: 0,
    })
    const brazier = new THREE.Mesh(
      new THREE.CylinderGeometry(radius * 0.45, radius * 0.3, 3 * WALL_TEXEL, 8),
      fire
    )
    brazier.position.y = towerH + 1.5 * WALL_TEXEL
    group.add(body, brazier)
    group.traverse((o) => {
      o.castShadow = o.receiveShadow = true
    })
    return { group, lamp: fire }
  }
  const gallery = new THREE.Mesh(
    new THREE.CylinderGeometry(radius * 1.05, radius * 1.05, 2 * WALL_TEXEL, 16),
    new THREE.MeshLambertMaterial({ color: '#3a3634' })
  )
  gallery.position.y = towerH
  const lamp = new THREE.MeshLambertMaterial({
    color: '#fff0c0',
    emissive: LAMP_GLOW,
    emissiveIntensity: 0,
  })
  const lanternH = 8 * WALL_TEXEL
  const lantern = new THREE.Mesh(
    new THREE.CylinderGeometry(radius * 0.6, radius * 0.6, lanternH, 12),
    lamp
  )
  lantern.position.y = towerH + lanternH / 2
  const cap = new THREE.Mesh(
    new THREE.ConeGeometry(radius * 0.75, 6 * WALL_TEXEL, 12),
    new THREE.MeshLambertMaterial({ color: '#a4413c' })
  )
  cap.position.y = towerH + lanternH + 3 * WALL_TEXEL
  group.add(body, gallery, lantern, cap)
  group.traverse((o) => {
    o.castShadow = o.receiveShadow = true
  })
  if (style !== 'beacon') return { group, lamp }
  const beam = beams()
  beam.position.y = towerH + lanternH / 2
  group.add(beam)
  return { group, lamp, beam }
}

/** 灯塔的两束光：水平的两个长三角，灯室处最亮、往外渐暗，叠加混合 */
function beams() {
  const length = 90 * PIXEL,
    half = 7 * PIXEL
  // prettier-ignore
  const pos = [0, 0, 0, length, 0, -half, length, 0, half, 0, 0, 0, -length, 0, half, -length, 0, -half]
  // prettier-ignore
  const col = [1, 0.93, 0.7, 0, 0, 0, 0, 0, 0, 1, 0.93, 0.7, 0, 0, 0, 0, 0, 0]
  const g = new THREE.BufferGeometry()
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3))
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3))
  const mesh = new THREE.Mesh(
    g,
    new THREE.MeshBasicMaterial({
      vertexColors: true,
      blending: THREE.AdditiveBlending,
      transparent: true,
      opacity: 0,
      depthWrite: false,
      side: THREE.DoubleSide,
      fog: false,
    })
  )
  mesh.renderOrder = 1
  return mesh
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
