import * as THREE from 'three'
import { PIXEL } from '../grid'
import { hash, mixHex } from '../pixel/noise'
import { PAVILION } from '../pixel/pavilions'
import { WALL_TEXEL } from './layout'
import { Mesher } from './pier'
import { pixelMaterial } from './pixelSampling'
import { texture } from './standee'

// 立体的八角凉亭，和房子一样是搭起来的，镜头怎么转都对，影子落在地上、倒影映在水里：
// - 八角石台，敞开的一面两级石阶；台面铺一圈圈石板。
// - 八根白柱子立在八个角上，柱头柱脚各宽一圈；柱子之间一道横梁，梁下垂一排花边。
// - 除了敞开的那一跨，每跨一道栏杆（贴图镂空，看得见亭子里和对面）。
// - 八面瓦顶收到正中，每面一道道瓦缝，面与面之间压奶白的屋脊；檐口一圈封檐板；顶上一颗宝顶。
// - 朝镜头的几个檐角各挂一盏纸灯笼，亭子正中吊一盏灯：入夜亮起来，照亮台面和柱子。
// 尺寸按地图单位（水平）和墙面贴图像素（竖直，WALL_TEXEL）给。

export interface BuiltGazebo {
  group: THREE.Group
  /** 朝上的面（台面、踏面，接积雪和地面的灯光）、立着的面（石台、柱子、梁，接墙面的灯光） */
  top: THREE.MeshLambertMaterial
  sides: THREE.MeshLambertMaterial
  /** 栏杆和花边（镂空贴图）、瓦顶 */
  rail: THREE.MeshLambertMaterial
  roof: THREE.MeshLambertMaterial
  /** 灯笼和吊灯：自发光，天黑才亮 */
  lamps: THREE.MeshLambertMaterial
  /** 每盏灯的位置（世界坐标），场景在这里加光晕 */
  lampSpots: [number, number, number][]
}

type Vec = [number, number, number]
const T = WALL_TEXEL
const SIDES = 8
/** 柱子所在的半径、石台和檐口各往外多出多少（地图单位），和占地、抬人用的是同一份 */
const R = PAVILION.r
const PLINTH_OUT = PAVILION.plinth
const EAVE_OUT = PAVILION.eave
/** 石台、柱子、横梁、屋顶各多高 */
const PLINTH = PAVILION.floor
const COLUMN = 15 * T
const BEAM = 1.6 * T
const ROOF = 12.5 * T
const RAIL = 4.6 * T

const CREAM = '#f4f0e6'
const CREAM_SHADE = '#cfc7b6'
const STONE = ['#d6ccb4', '#cbbfa4', '#bcae92']
const STONE_LINE = '#9c8e74'
const TILE = ['#6f9f86', '#5f9179', '#55856f']
const TILE_JOINT = '#35554a'
const RIDGE = '#e6dfcc'

const UV: [number, number][] = [
  [0, 0],
  [1, 0],
  [1, 1],
  [0, 1],
]
const UP: Vec = [0, 1, 0]

function flat(hex: string): Vec[] {
  const c = new THREE.Color(hex)
  const v: Vec = [c.r, c.g, c.b]
  return [v, v, v, v]
}

function canvasOf(
  w: number,
  h: number,
  draw: (px: (x: number, y: number, c: string) => void) => void
) {
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')!
  draw((x, y, c) => {
    ctx.fillStyle = c
    ctx.fillRect(x, y, 1, 1)
  })
  return canvas
}

/** 栏杆和花边的图集：左半是一跨栏杆（上下两道横杆、中间隔一个像素一根立柱），右半是梁下的花边 */
function railCanvas(bay: number) {
  const h = 5
  return canvasOf(bay * 2, h, (px) => {
    for (let x = 0; x < bay; x++) {
      px(x, 0, CREAM)
      if (x % 2 === 1) for (let y = 1; y < 4; y++) px(x, y, '#ddd6c6')
      px(x, 4, CREAM_SHADE)
      // 花边：一排小齿
      px(bay + x, 0, '#e6dfcf')
      if (x % 2 === 0) px(bay + x, 1, '#d9d1c0')
    }
  })
}

/** 一面瓦：底边是檐口、往上收到尖；每三行一道瓦缝，瓦片深浅不一，两条斜边压屋脊 */
function roofCanvas(eave: number, slope: number, seed: number) {
  return canvasOf(eave, slope, (px) => {
    for (let y = 0; y < slope; y++) {
      // 贴图第 0 行在最上面（屋顶尖），最后一行是檐口
      const fromEave = slope - 1 - y
      const inset = (fromEave / slope) * (eave / 2)
      for (let x = 0; x < eave; x++) {
        if (x < inset - 1 || x > eave - inset) continue
        const ridge = x < inset + 0.6 || x > eave - 1 - inset - 0.6
        let c = TILE[Math.floor(hash(x >> 1, fromEave / 3, seed) * TILE.length)]
        if (fromEave % 3 === 2) c = mixHex(c, TILE_JOINT, 0.55)
        else if (fromEave % 3 === 0) c = mixHex(c, '#ffffff', 0.08)
        px(x, y, ridge ? RIDGE : c)
      }
    }
    // 檐口一行压深，瓦头
    for (let x = 0; x < eave; x++) px(x, slope - 1, mixHex(TILE[2], TILE_JOINT, 0.4))
  })
}

/** 在 (x, y) 搭一座凉亭；facing 是敞开的一面朝哪（单位向量，不给朝南，正对缺省镜头） */
export function buildGazebo(
  x: number,
  y: number,
  seed: number,
  facing: [number, number] = [0, 1]
): BuiltGazebo {
  const top = new Mesher(),
    side = new Mesher(),
    rail = new Mesher(),
    roof = new Mesher(),
    lamp = new Mesher()
  // 第 k 个角的方向：敞开的一跨正对 facing，在第 0、1 两个角之间
  const front = Math.atan2(facing[1], facing[0])
  const step = (Math.PI * 2) / SIDES
  const angle = (k: number) => front - step / 2 + k * step
  const at = (r: number, a: number, h: number): Vec => [x + Math.cos(a) * r, h, y + Math.sin(a) * r]
  const out = (a: number): Vec => [Math.cos(a), 0, Math.sin(a)]
  const mid = (k: number) => angle(k) + step / 2
  /** 多边形半径 r 的那条边上、沿边 t（0～1）的一点 */
  const edge = (r: number, k: number, t: number, h: number): Vec => {
    const a = at(r, angle(k), h),
      b = at(r, angle(k + 1), h)
    return [a[0] + (b[0] - a[0]) * t, h, a[2] + (b[2] - a[2]) * t]
  }

  // ---- 石台：八面立面，台面一圈圈石板 ----
  const pr = R + PLINTH_OUT
  for (let k = 0; k < SIDES; k++) {
    const n = Math.max(2, Math.round((2 * pr * Math.sin(step / 2)) / PIXEL))
    for (let i = 0; i < n; i++) {
      const a = edge(pr, k, i / n, 0),
        b = edge(pr, k, (i + 1) / n, 0)
      const joint = (i + k * 3) % 6 === 0
      // 立面分两层：上面一道亮的压边
      side.quad(
        [a, b, [b[0], PLINTH - 0.5 * T, b[2]], [a[0], PLINTH - 0.5 * T, a[2]]],
        out(mid(k)),
        UV,
        0,
        flat(joint ? STONE_LINE : STONE[2])
      )
      side.quad(
        [
          [a[0], PLINTH - 0.5 * T, a[2]],
          [b[0], PLINTH - 0.5 * T, b[2]],
          [b[0], PLINTH, b[2]],
          [a[0], PLINTH, a[2]],
        ],
        out(mid(k)),
        UV,
        0,
        flat('#e2d8c0')
      )
    }
    // 台面：从中心到边分四圈，隔圈换色，外圈压边
    const rings = 4
    for (let j = 0; j < rings; j++) {
      const r0 = (pr * j) / rings,
        r1 = (pr * (j + 1)) / rings
      const c = j === rings - 1 ? '#e2d8c0' : j === 0 ? '#ded3ba' : STONE[j % 2]
      top.quad(
        [
          at(r0, angle(k), PLINTH),
          at(r0, angle(k + 1), PLINTH),
          at(r1, angle(k + 1), PLINTH),
          at(r1, angle(k), PLINTH),
        ],
        UP,
        UV,
        0,
        flat(c)
      )
    }
  }

  // ---- 敞开一跨前面的两级石阶 ----
  {
    const f: Vec = out(front)
    const sx: Vec = [-f[2], 0, f[0]]
    const half = pr * Math.sin(step / 2) * 0.82
    const near = pr * Math.cos(step / 2)
    const tread = 2 * PIXEL
    for (let s = 0; s < 2; s++) {
      const h = PLINTH * (1 - (s + 1) / 3)
      const d0 = near + s * tread,
        d1 = d0 + tread
      const w = half + s * PIXEL
      const p = (d: number, u: number, hh: number): Vec => [
        x + f[0] * d + sx[0] * u,
        hh,
        y + f[2] * d + sx[2] * u,
      ]
      top.quad([p(d0, -w, h), p(d0, w, h), p(d1, w, h), p(d1, -w, h)], UP, UV, 0, flat(STONE[0]))
      side.quad([p(d1, -w, 0), p(d1, w, 0), p(d1, w, h), p(d1, -w, h)], f, UV, 0, flat(STONE[2]))
      side.quad(
        [p(d0, -w, 0), p(d1, -w, 0), p(d1, -w, h), p(d0, -w, h)],
        [-sx[0], 0, -sx[2]],
        UV,
        0,
        flat(STONE[2])
      )
      side.quad([p(d0, w, 0), p(d1, w, 0), p(d1, w, h), p(d0, w, h)], sx, UV, 0, flat(STONE_LINE))
    }
  }

  // ---- 柱子：方柱，柱脚柱头宽一圈 ----
  const box = (
    c: Vec,
    half: number,
    h0: number,
    h1: number,
    light: string,
    dark: string,
    cap = false
  ) => {
    const [cx, , cz] = c
    const corners: [number, number][] = [
      [-half, half],
      [half, half],
      [half, -half],
      [-half, -half],
    ]
    const normals: Vec[] = [
      [0, 0, 1],
      [1, 0, 0],
      [0, 0, -1],
      [-1, 0, 0],
    ]
    for (let i = 0; i < 4; i++) {
      const [ax, az] = corners[i],
        [bx, bz] = corners[(i + 1) % 4]
      side.quad(
        [
          [cx + ax, h0, cz + az],
          [cx + bx, h0, cz + bz],
          [cx + bx, h1, cz + bz],
          [cx + ax, h1, cz + az],
        ],
        normals[i],
        UV,
        0,
        // 朝东、朝北的面压暗一档：光从左上来
        flat(i === 1 || i === 2 ? dark : light)
      )
    }
    if (cap)
      side.quad(
        [
          [cx - half, h1, cz + half],
          [cx + half, h1, cz + half],
          [cx + half, h1, cz - half],
          [cx - half, h1, cz - half],
        ],
        UP,
        UV,
        0,
        flat(light)
      )
  }
  const eaveH = PLINTH + COLUMN + BEAM
  for (let k = 0; k < SIDES; k++) {
    const c = at(R, angle(k), 0)
    box(c, 1.5 * PIXEL, PLINTH, PLINTH + T, '#e8e2d4', CREAM_SHADE, true)
    box(c, PIXEL, PLINTH + T, PLINTH + COLUMN - T, CREAM, CREAM_SHADE)
    box(c, 1.5 * PIXEL, PLINTH + COLUMN - T, PLINTH + COLUMN, '#ffffff', CREAM_SHADE)
  }

  // ---- 横梁、梁下的花边、栏杆 ----
  const bay = Math.max(4, Math.round((2 * R * Math.sin(step / 2)) / PIXEL))
  for (let k = 0; k < SIDES; k++) {
    const n = out(mid(k))
    const a = (h: number) => at(R, angle(k), h),
      b = (h: number) => at(R, angle(k + 1), h)
    side.quad(
      [a(PLINTH + COLUMN), b(PLINTH + COLUMN), b(eaveH), a(eaveH)],
      n,
      UV,
      0,
      flat('#ebe5d6')
    )
    // 花边：图集右半
    rail.quad(
      [
        a(PLINTH + COLUMN - 2 * T),
        b(PLINTH + COLUMN - 2 * T),
        b(PLINTH + COLUMN),
        a(PLINTH + COLUMN),
      ],
      n,
      [
        [0.5, 0.6],
        [1, 0.6],
        [1, 1],
        [0.5, 1],
      ],
      0
    )
    // 栏杆：敞开的那一跨（第 0 跨）不装
    if (k === 0) continue
    rail.quad(
      [a(PLINTH), b(PLINTH), b(PLINTH + RAIL), a(PLINTH + RAIL)],
      n,
      [
        [0, 0],
        [0.5, 0],
        [0.5, 1],
        [0, 1],
      ],
      0
    )
  }

  // ---- 瓦顶：八面收到正中；檐口一圈封檐板 ----
  const re = R + EAVE_OUT
  const apex: Vec = [x, eaveH + ROOF, y]
  const eaveLen = Math.max(6, Math.round((2 * re * Math.sin(step / 2)) / PIXEL))
  const slope = Math.max(6, Math.round(Math.hypot(re * Math.cos(step / 2), ROOF) / PIXEL))
  for (let k = 0; k < SIDES; k++) {
    const a = at(re, angle(k), eaveH),
      b = at(re, angle(k + 1), eaveH)
    // 面的法线：朝外、朝上
    const o = out(mid(k))
    const run = re * Math.cos(step / 2)
    const len = Math.hypot(run, ROOF)
    const normal: Vec = [(o[0] * ROOF) / len, run / len, (o[2] * ROOF) / len]
    roof.quad(
      [a, b, apex, apex],
      normal,
      [
        [0, 0],
        [1, 0],
        [0.5, 1],
        [0.5, 1],
      ],
      0
    )
    // 封檐板：檐口往下一道奶白的边
    side.quad(
      [[a[0], eaveH - 0.9 * T, a[2]], [b[0], eaveH - 0.9 * T, b[2]], b, a],
      o,
      UV,
      0,
      flat('#f0ebde')
    )
    // 檐底：从檐口收回到梁，朝下，看得见的是暗面
    side.quad(
      [
        [a[0], eaveH - 0.9 * T, a[2]],
        [b[0], eaveH - 0.9 * T, b[2]],
        at(R, angle(k + 1), eaveH - 0.2 * T),
        at(R, angle(k), eaveH - 0.2 * T),
      ],
      [0, -1, 0],
      UV,
      0,
      flat('#8f8878')
    )
  }
  // 宝顶：一截细颈托着一颗金珠
  box(apex, 0.5 * PIXEL, apex[1] - 0.5 * T, apex[1] + 1.2 * T, '#b8923a', '#8a6a26')
  box([x, 0, y], PIXEL, apex[1] + 1.2 * T, apex[1] + 3.4 * T, '#f0d878', '#c8a040', true)

  // ---- 灯：朝敞开那面的四个檐角各挂一盏纸灯笼，亭子正中吊一盏 ----
  const lampSpots: Vec[] = []
  const cube = (c: Vec, half: number, h0: number, h1: number, hex: string) => {
    const col = flat(hex)
    const [cx, , cz] = c
    const pts: [number, number][] = [
      [-half, half],
      [half, half],
      [half, -half],
      [-half, -half],
    ]
    const ns: Vec[] = [
      [0, 0, 1],
      [1, 0, 0],
      [0, 0, -1],
      [-1, 0, 0],
    ]
    for (let i = 0; i < 4; i++) {
      const [ax, az] = pts[i],
        [bx, bz] = pts[(i + 1) % 4]
      lamp.quad(
        [
          [cx + ax, h0, cz + az],
          [cx + bx, h0, cz + bz],
          [cx + bx, h1, cz + bz],
          [cx + ax, h1, cz + az],
        ],
        ns[i],
        UV,
        0,
        col
      )
    }
    lamp.quad(
      [
        [cx - half, h0, cz + half],
        [cx + half, h0, cz + half],
        [cx + half, h0, cz - half],
        [cx - half, h0, cz - half],
      ],
      [0, -1, 0],
      UV,
      0,
      col
    )
  }
  for (const k of [SIDES - 1, 0, 1, 2]) {
    const c = at(re - PIXEL, angle(k), 0)
    const h1 = eaveH - 1.8 * T,
      h0 = h1 - 2.4 * T
    // 纸灯笼：上下红纸封口（不发光的那一组），中间是亮的灯身
    box(c, 0.9 * PIXEL, h1, h1 + 0.6 * T, '#c8483a', '#8a2c24', true)
    box(c, 0.9 * PIXEL, h0 - 0.6 * T, h0, '#c8483a', '#8a2c24')
    // 吊绳
    side.quad(
      [
        [c[0] - 0.5, h1, c[2]],
        [c[0] + 0.5, h1, c[2]],
        [c[0] + 0.5, eaveH - 0.9 * T, c[2]],
        [c[0] - 0.5, eaveH - 0.9 * T, c[2]],
      ],
      [0, 0, 1],
      UV,
      0,
      flat('#3a2c2c')
    )
    cube(c, 0.9 * PIXEL, h0, h1, '#ffcf7a')
    lampSpots.push([c[0], (h0 + h1) / 2, c[2]])
  }
  // 敞开那一跨左边的柱子上爬着开花的藤：贴着柱面的一片片小叶子和花
  {
    const c = at(R, angle(0), 0)
    const leaf = ['#4d7a45', '#6b9a52', '#5a8a4a']
    const bloom = ['#e8687a', '#f4a0b0']
    for (let i = 0; i < 46; i++) {
      const u = (hash(i, 1, seed) - 0.5) * 3.4 * PIXEL
      const h = PLINTH + hash(i, 2, seed) * (COLUMN - T)
      const roll = hash(i, 3, seed)
      const hex = roll < 0.72 ? leaf[i % 3] : bloom[i % 2]
      const s = PIXEL * 0.5
      // 朝南的一面和朝西的一面各贴一些
      if (i % 3)
        side.quad(
          [
            [c[0] + u - s, h, c[2] + PIXEL + 0.6],
            [c[0] + u + s, h, c[2] + PIXEL + 0.6],
            [c[0] + u + s, h + T, c[2] + PIXEL + 0.6],
            [c[0] + u - s, h + T, c[2] + PIXEL + 0.6],
          ],
          [0, 0, 1],
          UV,
          0,
          flat(hex)
        )
      else
        side.quad(
          [
            [c[0] - PIXEL - 0.6, h, c[2] + u - s],
            [c[0] - PIXEL - 0.6, h, c[2] + u + s],
            [c[0] - PIXEL - 0.6, h + T, c[2] + u + s],
            [c[0] - PIXEL - 0.6, h + T, c[2] + u - s],
          ],
          [-1, 0, 0],
          UV,
          0,
          flat(hex)
        )
    }
  }
  {
    const h1 = PLINTH + COLUMN - 2.5 * T,
      h0 = h1 - 3 * T
    cube([x, 0, y], PIXEL, h0, h1, '#ffd28a')
    lampSpots.push([x, (h0 + h1) / 2, y])
  }

  const group = new THREE.Group()
  const topMaterial = new THREE.MeshLambertMaterial({ vertexColors: true })
  const sideMaterial = new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide })
  const railMap = texture(railCanvas(bay))
  const railMaterial = pixelMaterial(
    new THREE.MeshLambertMaterial({ map: railMap, alphaTest: 0.5, side: THREE.DoubleSide })
  )
  const roofMap = texture(roofCanvas(eaveLen, slope, seed))
  // 和房子的屋顶一样，夜里按自身颜色微亮（场景按昼夜设 emissiveIntensity）
  const roofMaterial = pixelMaterial(
    new THREE.MeshLambertMaterial({
      map: roofMap,
      emissiveMap: roofMap,
      emissive: new THREE.Color(0.5, 0.5, 0.5),
      emissiveIntensity: 0,
      alphaTest: 0.5,
      side: THREE.DoubleSide,
    })
  )
  const lampMaterial = new THREE.MeshLambertMaterial({
    vertexColors: true,
    emissive: new THREE.Color('#ffb060'),
    emissiveIntensity: 0,
  })
  const add = (mesher: Mesher, material: THREE.Material, depth?: THREE.Texture) => {
    const mesh = new THREE.Mesh(mesher.build(), material)
    mesh.castShadow = mesh.receiveShadow = true
    if (depth)
      mesh.customDepthMaterial = pixelMaterial(
        new THREE.MeshDepthMaterial({
          depthPacking: THREE.RGBADepthPacking,
          map: depth,
          alphaTest: 0.5,
        })
      )
    group.add(mesh)
  }
  add(top, topMaterial)
  add(side, sideMaterial)
  add(rail, railMaterial, railMap)
  add(roof, roofMaterial)
  add(lamp, lampMaterial)
  return {
    group,
    top: topMaterial,
    sides: sideMaterial,
    rail: railMaterial,
    roof: roofMaterial,
    lamps: lampMaterial,
    lampSpots,
  }
}
