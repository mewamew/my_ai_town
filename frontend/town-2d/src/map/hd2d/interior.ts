import * as THREE from 'three'
import { PIXEL } from '../grid'
import { hash } from '../pixel/noise'
import type { BuildingKind } from '../buildings'
import { WALL_TEXEL, type House, type Tilt } from './layout'
import { texture } from './standee'
import { pixelMaterial } from './pixelSampling'
import { wallBase } from './textures'
import { planPartition, type Partition } from './partition'
import type { InteriorPalette } from '../themes/interiors'
import { LAMP_GLOW, WALL_CAP } from '../palette'

// 室内：屋子掀开后按剖面模型的样子立起三面墙。北墙和东西两墙大约半层楼高，朝南对着镜头的
// 那面只留一道矮墙，门在哪面墙就在那里留门洞。北墙内面按功能画护墙板、墙纸、窗和陈设；
// 大厅靠墙立柱子，住处和会客的地方中间铺地毯。地板还是地面图上画的那块。
// 屋里按家具分布砌一面隔墙分成两间（见 partition.ts），门洞两边立门框。
// 原点在房屋中心的地面上，和房子外壳同一个位置；墙厚两个像素，砌在占地里面。

const T = 2 * PIXEL
/** 矮墙高（贴图像素） */
const LOW = 4

/** 北墙和东西两墙的高度（贴图像素） */
export function interiorTexels(house: House) {
  return Math.max(14, Math.min(24, Math.round(house.wallTexels * 0.72)))
}

/** 掀开后墙顶在地图坐标里的 y，名字放在它上面；和 houseTop 同一个折算 */
export function interiorTop(house: House, tilt: Tilt) {
  return house.y - (interiorTexels(house) * WALL_TEXEL * tilt.cos) / tilt.sin
}

type Rect = (x: number, y: number, w: number, h: number, c: string) => void

/** 北墙内面：墙纸、护墙板、踢脚线、窗，再按功能加陈设。返回贴图和夜里发光的窗 */
function backWall(house: House, len: number, height: number) {
  const pal = house.interior
  const map = document.createElement('canvas'),
    glow = document.createElement('canvas')
  map.width = glow.width = len
  map.height = glow.height = height
  const x = map.getContext('2d')!,
    gx = glow.getContext('2d')!
  gx.fillStyle = '#000'
  gx.fillRect(0, 0, len, height)
  const rect: Rect = (i, j, w, h, c) => {
    x.fillStyle = c
    x.fillRect(i, j, w, h)
  }
  const seed = house.seed
  // 墙纸竖条纹、上沿一道线脚、下半截护墙板、踢脚线
  for (let i = 0; i < len; i++) rect(i, 0, 1, height, i % 4 < 2 ? pal.paper : pal.stripe)
  rect(0, 0, len, 1, pal.trim)
  const panelTop = height - Math.round(height * 0.34)
  rect(0, panelTop, len, height - panelTop, pal.panel)
  rect(0, panelTop, len, 1, pal.trim)
  for (let i = 3; i < len; i += 8) rect(i, panelTop + 2, 1, height - panelTop - 4, pal.trim)
  rect(0, height - 2, len, 2, pal.trim)

  // 窗：墙上等距开几扇，窗框、玻璃、窗台；夜里窗亮
  const windows: number[] = []
  const count = Math.max(1, Math.floor(len / 26))
  for (let k = 0; k < count; k++) windows.push(Math.round(((k + 0.5) * len) / count) - 4)
  const wy = 3,
    wh = Math.min(9, panelTop - 5)
  const drawWindow = (i: number) => {
    rect(i - 1, wy - 1, 10, wh + 2, pal.trim)
    rect(i, wy, 8, wh, '#9cc8e0')
    rect(i, wy, 8, 2, '#c8e4f0')
    rect(i + 3, wy, 2, wh, pal.trim)
    rect(i - 2, wy + wh + 1, 12, 1, pal.trim)
    gx.fillStyle = LAMP_GLOW
    gx.fillRect(i, wy, 8, wh)
  }
  const between = (k: number) =>
    k === 0 ? [2, windows[0] - 3] : [windows[k - 1] + 11, windows[k] - 3]
  const gaps = windows
    .map((_, k) => between(k))
    .concat([[windows[windows.length - 1] + 11, len - 2]])
  const decorate = DECOR[house.kind] ?? DECOR.home!
  // 陈设放在窗与窗之间的墙上
  gaps.forEach(([a, b], k) => {
    if (b - a >= 8) decorate(rect, a, b, panelTop, height, seed + k, pal)
  })
  // 剧院的幕布挡住中间的窗，先画窗再画幕布
  if (house.kind === 'theatre') {
    windows.forEach(drawWindow)
    stageCurtain(rect, len, height, panelTop)
    gx.fillStyle = '#000'
    gx.fillRect(Math.round(len * 0.2), 0, Math.round(len * 0.6), height)
  } else windows.forEach(drawWindow)
  return { map, glow }
}

type Decor = (
  rect: Rect,
  a: number,
  b: number,
  panelTop: number,
  height: number,
  seed: number,
  pal: InteriorPalette
) => void

const SPINES = ['#8e3f33', '#44566e', '#5b7352', '#c9a04e', '#6a5779', '#a86a3a', '#e8dcc0']
const bookshelf: Decor = (rect, a, b, panelTop, height, seed) => {
  rect(a, 2, b - a, height - 4, '#4e3624')
  for (let y = 4; y + 4 < height - 2; y += 5) {
    for (let i = a + 1; i < b - 1;) {
      const w = 1 + Math.floor(hash(i, y, seed) * 2),
        h = 3 + Math.floor(hash(i, y, seed + 1) * 2)
      rect(i, y + 4 - h, w, h, SPINES[Math.floor(hash(i, y, seed + 2) * SPINES.length)])
      i += w + (hash(i, y, seed + 3) < 0.15 ? 1 : 0)
    }
    rect(a, y + 4, b - a, 1, '#2e2016')
  }
}
const frame = (rect: Rect, i: number, j: number, w: number, h: number, seed: number) => {
  rect(i, j, w, h, '#6a4a2e')
  rect(i + 1, j + 1, w - 2, h - 2, hash(i, j, seed) < 0.5 ? '#9cc0d6' : '#e8d8a8')
  rect(i + 1, j + h - 3, w - 2, 2, '#6f9754')
  rect(i + 2, j + h - 5, 2, 2, '#4d7a45')
}
const DECOR: Partial<Record<BuildingKind, Decor>> = {
  home: (rect, a, b, panelTop, _h, seed) => {
    const c = Math.round((a + b) / 2)
    if (hash(a, b, seed) < 0.5) frame(rect, c - 4, 4, 8, 6, seed)
    else {
      // 挂钟
      rect(c - 2, 4, 5, 5, '#6a4a2e')
      rect(c - 1, 5, 3, 3, '#f1ead8')
      rect(c, 5, 1, 2, '#2b282c')
    }
    // 小搁板和两个罐子
    if (panelTop > 13) {
      rect(c - 4, panelTop - 3, 9, 1, '#6a4a2e')
      rect(c - 3, panelTop - 5, 2, 2, '#c8765a')
      rect(c + 1, panelTop - 6, 2, 3, '#5a8aa1')
    }
  },
  library: bookshelf,
  colonnade: bookshelf,
  townhall: (rect, a, b, panelTop) => {
    // 两面竖旗夹一枚徽章
    const c = Math.round((a + b) / 2)
    for (const i of [a + 1, b - 4]) {
      rect(i, 2, 3, panelTop - 3, '#8e3f33')
      rect(i, panelTop - 2, 1, 1, '#8e3f33')
      rect(i + 2, panelTop - 2, 1, 1, '#8e3f33')
      rect(i + 1, 5, 1, 3, '#c9a04e')
    }
    rect(c - 2, 4, 5, 5, '#c9a04e')
    rect(c - 1, 5, 3, 3, '#44566e')
  },
  clinic: (rect, a, b, panelTop) => {
    const c = Math.round((a + b) / 2)
    rect(c - 3, 4, 7, 7, '#f6f4ee')
    rect(c - 1, 5, 3, 5, '#c8453b')
    rect(c - 2, 6, 5, 3, '#c8453b')
    // 下半截是瓷砖，画出砖缝
    for (let i = a; i < b; i += 3) rect(i, panelTop + 1, 1, 6, '#b6d0cc')
  },
  canteen: (rect, a, b) => {
    // 菜单黑板
    const w = Math.min(14, b - a - 2),
      i = Math.round((a + b - w) / 2)
    rect(i, 3, w, 8, '#6a4a2e')
    rect(i + 1, 4, w - 2, 6, '#2f3a34')
    for (let j = 5; j < 10; j += 2) rect(i + 2, j, Math.max(2, w - 5 - (j % 3)), 1, '#d8d4c8')
  },
  cafe: (rect, a, b, panelTop) => {
    const c = Math.round((a + b) / 2)
    rect(c - 5, panelTop - 3, 11, 1, '#6a4a2e')
    for (let k = 0; k < 4; k++)
      rect(c - 4 + k * 3, panelTop - 5, 2, 2, k % 2 ? '#f6f4ee' : '#c88a8e')
    rect(c - 3, 4, 7, 5, '#2f3a34')
    rect(c - 2, 5, 5, 1, '#e8dcc0')
  },
  shop: (rect, a, b, panelTop) => {
    const goods = ['#e05a4a', '#f0c040', '#7ab050', '#e89040', '#5a8aa1']
    for (let y = 4; y < panelTop - 1; y += 4) {
      rect(a, y + 3, b - a, 1, '#6a4a2e')
      for (let i = a + 1; i < b - 1; i += 3) rect(i, y + 1, 2, 2, goods[(i + y) % goods.length])
    }
  },
  workshop: (rect, a, b, panelTop) => {
    // 工具挂板：锤子、锯、扳手
    rect(a, 3, b - a, panelTop - 4, '#c8a878')
    const c = Math.round((a + b) / 2)
    rect(c - 5, 5, 1, 5, '#6a4a2e')
    rect(c - 6, 4, 3, 2, '#8a8f96')
    rect(c - 1, 5, 5, 2, '#b8bcc4')
    rect(c + 3, 5, 1, 3, '#6a4a2e')
    rect(c + 5, 4, 1, 6, '#8a8f96')
    rect(c + 4, 4, 3, 1, '#8a8f96')
  },
  warehouse: (rect, a, b, _p, height) => {
    // 靠墙码着的木箱
    for (let i = a; i + 6 <= b; i += 7)
      for (let j = height - 8; j > height - 8 - 6 * (1 + (i % 3)) && j > 2; j -= 6) {
        rect(i, j, 6, 6, '#8a6a44')
        rect(i, j, 6, 1, '#a88660')
        rect(i + 2, j + 1, 1, 5, '#6a4a2e')
      }
  },
  inn: (rect, a, b, panelTop, h, seed, pal) => DECOR.home!(rect, a, b, panelTop, h, seed, pal),
  hotel: (rect, a, b, panelTop, _h, seed) => {
    const c = Math.round((a + b) / 2)
    frame(rect, c - 5, 3, 10, 7, seed)
    // 两盏壁灯
    for (const i of [a + 1, b - 2]) {
      rect(i, 5, 1, 3, '#c9a04e')
      rect(i, 4, 1, 1, LAMP_GLOW)
    }
    void panelTop
  },
  club: (rect, a, b, _p, _h, seed) => {
    const c = Math.round((a + b) / 2)
    rect(c - 5, 3, 10, 8, '#c9a04e')
    rect(c - 4, 4, 8, 6, hash(a, b, seed) < 0.5 ? '#8e3f33' : '#44566e')
    rect(c - 2, 6, 4, 2, '#e8d8a8')
  },
  lighthouse: (rect, a, b) => {
    // 船舵
    const c = Math.round((a + b) / 2)
    rect(c - 3, 4, 7, 7, '#6a4a2e')
    rect(c - 2, 5, 5, 5, '#dfe7ee')
    rect(c - 1, 6, 3, 3, '#6a4a2e')
    rect(c, 3, 1, 9, '#6a4a2e')
    rect(c - 4, 7, 9, 1, '#6a4a2e')
  },
}

/** 剧院：北墙正中的红幕和金色顶帘 */
function stageCurtain(rect: Rect, len: number, height: number, panelTop: number) {
  const a = Math.round(len * 0.2),
    b = Math.round(len * 0.8)
  for (let i = a; i < b; i++) rect(i, 1, 1, height - 3, (i - a) % 4 < 2 ? '#a8323a' : '#8a2830')
  rect(a, 1, b - a, 3, '#c9a04e')
  for (let i = a; i < b; i += 3) rect(i, 4, 2, 1, '#c9a04e')
  // 幕布中间拉开一道缝
  const c = Math.round((a + b) / 2)
  rect(c - 1, 5, 2, height - 7, '#3a1a1c')
  void panelTop
}

/** 地毯：边框、内圈和中间的花纹 */
function rugCanvas(w: number, h: number, color: string, seed: number) {
  const c = document.createElement('canvas')
  c.width = w
  c.height = h
  const x = c.getContext('2d')!
  const rect: Rect = (i, j, rw, rh, col) => {
    x.fillStyle = col
    x.fillRect(i, j, rw, rh)
  }
  rect(0, 0, w, h, '#e8d8a8')
  rect(1, 1, w - 2, h - 2, color)
  rect(3, 3, w - 6, h - 6, '#e8d8a8')
  rect(4, 4, w - 8, h - 8, color)
  for (let i = 6; i < w - 6; i += 4)
    for (let j = 6; j < h - 6; j += 4) if (hash(i, j, seed) < 0.5) rect(i, j, 2, 2, '#e8d8a8')
  return c
}
const PILLARED = new Set<BuildingKind>(['townhall', 'theatre', 'library', 'colonnade', 'hotel'])

/** 隔墙高（贴图像素）：东西向的隔墙挡在镜头和北半间之间，砌矮一些 */
const PARTITION = { alongX: 7, alongZ: 14 }

/** 隔墙朝南一面：上半截墙纸、下半截护墙板 */
function partitionCanvas(len: number, height: number, pal: InteriorPalette) {
  const c = document.createElement('canvas')
  c.width = len
  c.height = height
  const x = c.getContext('2d')!
  for (let i = 0; i < len; i++) {
    x.fillStyle = i % 4 < 2 ? pal.paper : pal.stripe
    x.fillRect(i, 0, 1, height)
  }
  const panelTop = Math.round(height * 0.45)
  x.fillStyle = pal.panel
  x.fillRect(0, panelTop, len, height - panelTop)
  x.fillStyle = pal.trim
  x.fillRect(0, 0, len, 1)
  x.fillRect(0, panelTop, len, 1)
  x.fillRect(0, height - 1, len, 1)
  return c
}

/** 室内墙用到的材质：外面、里面、墙顶，北墙内面带贴图 */
interface WallMaterials {
  outer: THREE.Material
  inner: THREE.Material
  cap: THREE.Material
  face: THREE.Material
}

/** 一段墙：along 是沿墙的起止，at 是墙的中线位置；materials 按 BoxGeometry 的六个面 */
function segment(
  group: THREE.Group,
  horizontal: boolean,
  a: number,
  b: number,
  at: number,
  bottom: number,
  top: number,
  materials: THREE.Material[]
) {
  if (b - a < 1 || top - bottom < 1) return
  const g = horizontal
    ? new THREE.BoxGeometry(b - a, top - bottom, T)
    : new THREE.BoxGeometry(T, top - bottom, b - a)
  const mesh = new THREE.Mesh(g, materials)
  mesh.position.set(
    horizontal ? (a + b) / 2 : at,
    (bottom + top) / 2,
    horizontal ? at : (a + b) / 2
  )
  mesh.castShadow = mesh.receiveShadow = true
  group.add(mesh)
}

/** 四面墙：北墙和东西墙半层楼高，朝南的只留矮墙；门在哪面墙就在哪里留门洞 */
function outerWalls(
  group: THREE.Group,
  house: House,
  door: [number, number] | undefined,
  H: number,
  { outer, inner, cap, face }: WallMaterials
) {
  const { w, h, x, y } = house
  // 门在哪面墙：离哪条边最近
  let side = -1
  let doorAt = 0
  if (door) {
    const d = [door[1] - y, y + h - door[1], door[0] - x, x + w - door[0]].map(Math.abs)
    side = d.indexOf(Math.min(...d))
    doorAt = side < 2 ? door[0] - (x + w / 2) : door[1] - (y + h / 2)
  }
  const doorW = 12 * PIXEL,
    doorH = 13 * WALL_TEXEL
  /** 一面墙，门在这面墙上就留门洞：矮墙整段断开，高墙在门上方留一截门楣 */
  const wall = (
    wallSide: number,
    horizontal: boolean,
    at: number,
    extent: number,
    height: number,
    materials: THREE.Material[]
  ) => {
    const a = -extent / 2,
      b = extent / 2
    if (side !== wallSide) return segment(group, horizontal, a, b, at, 0, height, materials)
    const g0 = Math.max(a + T, doorAt - doorW / 2),
      g1 = Math.min(b - T, doorAt + doorW / 2)
    segment(group, horizontal, a, g0, at, 0, height, materials)
    segment(group, horizontal, g1, b, at, 0, height, materials)
    if (height > doorH) segment(group, horizontal, g0, g1, at, doorH, height, materials)
  }
  // BoxGeometry 的面：+x、-x、+y、-y、+z、-z
  wall(0, true, -h / 2 + T / 2, w, H, [outer, outer, cap, cap, face, outer])
  wall(1, true, h / 2 - T / 2, w, LOW * WALL_TEXEL, [outer, outer, cap, cap, outer, inner])
  wall(2, false, -w / 2 + T / 2, h - 2 * T, H, [inner, outer, cap, cap, outer, outer])
  wall(3, false, w / 2 - T / 2, h - 2 * T, H, [outer, inner, cap, cap, outer, outer])
}

/** 大厅靠墙立柱子：北边两角，屋子深的在东西两墙中间再各一根 */
function pillars(group: THREE.Group, house: House, H: number) {
  const { w, h } = house
  const pillar = new THREE.MeshLambertMaterial({
    color: house.kind === 'theatre' ? '#c9a04e' : '#e4ddcc',
  })
  const r = 1.6 * PIXEL
  const spots: [number, number][] = [
    [-w / 2 + T + r, -h / 2 + T + r],
    [w / 2 - T - r, -h / 2 + T + r],
  ]
  if (h > 60 * PIXEL) spots.push([-w / 2 + T + r, 0], [w / 2 - T - r, 0])
  for (const [px, pz] of spots) {
    const mesh = new THREE.Mesh(new THREE.CylinderGeometry(r, r * 1.1, H, 10), pillar)
    mesh.position.set(px, H / 2, pz)
    mesh.castShadow = mesh.receiveShadow = true
    group.add(mesh)
  }
}

/** 隔墙：沿墙方向按段砌，两头和门洞两边立门框 */
function partitionWalls(group: THREE.Group, house: House, plan: Partition, m: WallMaterials) {
  const texels = plan.alongX ? PARTITION.alongX : PARTITION.alongZ
  const tall = texels * WALL_TEXEL
  const post = new THREE.MeshLambertMaterial({ color: house.interior.trim })
  for (const [a, b] of plan.segments) {
    const along = Math.max(2, Math.round((b - a) / PIXEL))
    const skin = pixelMaterial(
      new THREE.MeshLambertMaterial({
        map: texture(partitionCanvas(along, texels, house.interior)),
      })
    )
    const faces = plan.alongX
      ? [m.inner, m.inner, m.cap, m.cap, skin, m.inner]
      : [skin, skin, m.cap, m.cap, m.inner, m.inner]
    segment(group, plan.alongX, a, b, plan.at, 0, tall, faces)
  }
  for (const end of plan.opening) {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(T * 1.2, tall + WALL_TEXEL, T * 1.2), post)
    mesh.position.set(
      plan.alongX ? end : plan.at,
      (tall + WALL_TEXEL) / 2,
      plan.alongX ? plan.at : end
    )
    mesh.castShadow = mesh.receiveShadow = true
    group.add(mesh)
  }
}

/** 地毯铺在哪里：有隔墙时铺在大的那一间中间，没有就铺在屋子中间偏南 */
function rugBoxOf(house: House, plan: Partition | undefined) {
  const { w, h } = house
  if (!plan) return { x: 0, z: h * 0.08, w: w * 0.42, h: h * 0.34 }
  const extent = plan.alongX ? h : w
  const lo = plan.firstLarger ? -extent / 2 : plan.at,
    hi = plan.firstLarger ? plan.at : extent / 2
  return plan.alongX
    ? { x: 0, z: (lo + hi) / 2, w: w * 0.42, h: (hi - lo) * 0.5 }
    : { x: (lo + hi) / 2, z: h * 0.08, w: (hi - lo) * 0.5, h: h * 0.34 }
}

function addRug(group: THREE.Group, house: House, rug: string, plan: Partition | undefined) {
  const box = rugBoxOf(house, plan)
  const rw = Math.max(12, Math.round(box.w / PIXEL)),
    rh = Math.max(8, Math.round(box.h / PIXEL))
  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(rw * PIXEL, rh * PIXEL),
    pixelMaterial(
      new THREE.MeshLambertMaterial({ map: texture(rugCanvas(rw, rh, rug, house.seed)) })
    )
  )
  mesh.rotation.x = -Math.PI / 2
  mesh.position.set(box.x, 0.4, box.z)
  mesh.receiveShadow = true
  group.add(mesh)
}

/** 一栋屋子的室内结构；points 是屋里的落脚点和家具（世界坐标），glowing 是夜里发光的窗 */
export function interior(house: House, door?: [number, number], points: [number, number][] = []) {
  const { w, h, x, y } = house
  const group = new THREE.Group()
  group.position.set(x + w / 2, 0, y + h / 2)
  group.visible = false
  const texels = interiorTexels(house)
  const H = texels * WALL_TEXEL
  const art = backWall(house, Math.max(8, Math.round(w / PIXEL)), texels)
  const materials: WallMaterials = {
    outer: new THREE.MeshLambertMaterial({ color: wallBase(house) }),
    inner: new THREE.MeshLambertMaterial({ color: house.interior.paper }),
    cap: new THREE.MeshLambertMaterial({ color: WALL_CAP }),
    face: pixelMaterial(
      new THREE.MeshLambertMaterial({
        map: texture(art.map),
        emissiveMap: texture(art.glow),
        emissive: '#ffffff',
        emissiveIntensity: 0,
      })
    ),
  }
  outerWalls(group, house, door, H, materials)
  if (PILLARED.has(house.kind)) pillars(group, house, H)
  const cx = x + w / 2,
    cz = y + h / 2
  const plan = planPartition(
    w,
    h,
    T,
    points.map(([px, pz]) => [px - cx, pz - cz]),
    door && [door[0] - cx, door[1] - cz]
  )
  if (plan) partitionWalls(group, house, plan, materials)
  if (house.rug) addRug(group, house, house.rug, plan)
  return { group, glowing: materials.face, partition: plan }
}

/**
 * 立牌底边随镜头旋转后在地面的两个半宽分别为 halfX/halfY；外墙和隔墙按这个范围让开。
 * 只挪画出来的位置，落脚点不变；不在这间屋里原样返回。
 */
export function keepInside(
  house: House,
  partition: Partition | undefined,
  x: number,
  y: number,
  halfX: number,
  halfY: number
): [number, number] {
  if (x < house.x || x > house.x + house.w || y < house.y || y > house.y + house.h) return [x, y]
  const clamp = (at: number, start: number, span: number, half: number) => {
    const lo = start + T + half,
      hi = start + span - T - half
    return lo > hi ? start + span / 2 : Math.min(hi, Math.max(lo, at))
  }
  x = clamp(x, house.x, house.w, halfX)
  y = clamp(y, house.y, house.h, halfY)
  if (partition) {
    const alongX = partition.alongX
    const wall = (alongX ? house.y + house.h / 2 : house.x + house.w / 2) + partition.at
    const along = alongX ? x - (house.x + house.w / 2) : y - (house.y + house.h / 2)
    const at = alongX ? y : x
    const clear = (alongX ? halfY : halfX) + T / 2
    if (
      Math.abs(at - wall) < clear &&
      partition.segments.some(([a, b]) => along > a && along < b)
    ) {
      const next = at < wall ? wall - clear : wall + clear
      if (alongX) y = next
      else x = next
    }
  }
  return [x, y]
}
