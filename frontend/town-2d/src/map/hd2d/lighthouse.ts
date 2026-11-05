import * as THREE from 'three'
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js'
import { PIXEL } from '../grid'
import { bayer, hash, hexRgb, mixHex, noise } from '../pixel/noise'
import { ICE, LAMP_GLOW, SNOW, SNOW_SHADE } from '../palette'
import type { MapTheme } from '../themes/types'
import { WALL_TEXEL, type House, type Tower } from './layout'
import { interiorTexels, lighthouseDecor, type Rect } from './interior'
import { pixelMaterial } from './pixelSampling'
import { texture } from './standee'
import type { InteriorPalette } from '../themes/interiors'

// 灯塔：整块占地是一座两层的石台，塔立在正中，不附带房子。尺寸见 layout.ts 的 towerOf。
// - 石台：底下一圈湿漉漉的粗石脚，上面一层方石砌的平台，台面铺石板、塔脚一圈放射状的小方石；
//   沿边一道刷白的矮栏墙，拐角立石柱；门那一面开三级台阶，台阶两边的柱头上各一盏灯。
// - 塔：方石砌的喇叭形塔脚，红白相间的塔身，小拱窗沿着里面的楼梯一路往上；塔门朝着台阶，
//   门上一个小山墙门廊，门两边两盆花。
// - 塔顶：一圈牛腿托着瞭望台和铁栏杆，十边形的玻璃灯室里一具透镜，红色圆顶、通风球、风向标。
// - 台上：信号旗杆、雾钟、朝海的铜望远镜、几只木桶和一盘缆绳，栏墙外挂一只救生圈。
// 夜里灯室最先亮，两束光绕着转；塔窗、台阶灯随后亮。圆的面（塔身、圆顶、木桶）光照分四档，像手画的明暗。
// 掀开屋顶时不变成普通房间，而是剖开的灯塔（见 cutaway）：屋里的人站在地面上，台子也落到地面。
// 风格：striped 红白条纹；snowy 冰雪（红塔身一道白带，台上积雪、檐下冰柱）；
// ruined 废土（灯室塌了、栏杆断了，瞭望台上架一盆火冒着烟，台上是锈桶和碎砖）。
// 原点在占地中心的地面上，x 向东、z 向南。竖直面上一个贴图像素高 WALL_TEXEL、宽 PIXEL，水平面上一格 PIXEL。

const P = PIXEL
const T = WALL_TEXEL
type Pt = readonly [number, number]
type Style = MapTheme['lighthouse']

interface Palette {
  /** 塔身从下往上的几道漆 */
  bands: readonly string[]
  /** 方石三档（亮、中、暗）、石缝 */
  stone: readonly [string, string, string]
  mortar: string
  /** 石脚的粗石三档、贴水那一排的海藻 */
  rock: readonly [string, string, string]
  weed: string
  /** 台面石板三档、板缝，压顶石 */
  paving: readonly [string, string, string]
  joint: string
  coping: string
  /** 栏墙刷的灰浆 */
  wash: string
  /** 铁件：暗、中、亮 */
  iron: readonly [string, string, string]
  door: string
  /** 台面、压顶、圆顶积着雪，瞭望台檐下挂冰柱 */
  snow: boolean
  /** 灯室塌了：见文件开头 */
  ruined: boolean
}

const PALETTES: Record<Style, Palette> = {
  striped: {
    bands: ['#ece6d8', '#bd463b', '#ece6d8', '#bd463b', '#ece6d8'],
    stone: ['#bfb6a5', '#b3aa99', '#a79e8d'],
    mortar: '#958c7c',
    rock: ['#7c8582', '#6a7370', '#59615f'],
    weed: '#4d6447',
    paving: ['#cec5b3', '#c4bba9', '#b9b09e'],
    joint: '#a39a88',
    coping: '#d6cebd',
    wash: '#ebe5d8',
    iron: ['#2c3533', '#45514e', '#6f7d79'],
    door: '#3e6863',
    snow: false,
    ruined: false,
  },
  snowy: {
    bands: ['#b0392f', '#b0392f', '#ece9e2', '#b0392f', '#b0392f'],
    stone: ['#adb1b6', '#9ea3a9', '#8f949b'],
    mortar: '#868b92',
    rock: ['#6d747c', '#5d646c', '#4e555c'],
    weed: '#55606a',
    paving: [SNOW, '#e6edf3', SNOW_SHADE],
    joint: '#c9d6e2',
    coping: SNOW,
    wash: '#e9e6df',
    iron: ['#262d30', '#3b4549', '#5f6b70'],
    door: '#2f4f6a',
    snow: true,
    ruined: false,
  },
  ruined: {
    bands: ['#bdb4a2', '#93604d', '#bdb4a2', '#93604d', '#bdb4a2'],
    stone: ['#aca497', '#9e9689', '#90887c'],
    mortar: '#76706a',
    rock: ['#7a7166', '#6a6258', '#5a534a'],
    weed: '#6e6046',
    paving: ['#b2aa9c', '#a59d90', '#988f83'],
    joint: '#7a746c',
    coping: '#bab3a5',
    wash: '#b0a99c',
    iron: ['#3a2a20', '#5e3c28', '#84573a'],
    door: '#5a4636',
    snow: false,
    ruined: true,
  },
}

/** 场景要接管的东西：材质接天气、光照图和夜里的亮灯，光晕和烟按组内坐标摆 */
export interface Lighthouse {
  group: THREE.Group
  /** 接天气（积雪、淋湿、随风摆）的材质 */
  weathered: { material: THREE.MeshLambertMaterial; snow: number; wet: number; sway?: boolean }[]
  /** 竖着的墙面：接光照图，门灯、路灯照得到 */
  walls: THREE.Material[]
  /** 夜里亮的：on 是亮灯门槛，不给就跟这栋房子的灯一起亮 */
  glowing: { material: THREE.Material; on?: number }[]
  /** 白天也亮着的火 */
  burning: THREE.MeshLambertMaterial[]
  /** 光晕：组内坐标、大小（世界单位）、亮灯门槛 */
  glows: { at: THREE.Vector3; size: number; on?: number }[]
  /** 转动的光束，和光束扫到正对镜头时闪光的位置（透镜中心） */
  beam?: THREE.Object3D
  lamp?: THREE.Vector3
  /** 冒烟的地方（组内坐标） */
  smoke: THREE.Vector3[]
  /** 地面：接光照图，掀开后屋里的灯照得到 */
  grounds: THREE.Material[]
  /** 掀开屋顶后的样子：剖开的灯塔（见 cutaway），和别的房子的室内一样由场景开合；glowing 是夜里亮的窗 */
  room: { group: THREE.Group; glowing: THREE.Material[] }
}

/** 台上的东西摆在哪一层：剖开前在台面上，剖开后台子落到地面 */
interface Stage {
  y: number
  add: (mesh: THREE.Mesh, shadow?: boolean) => THREE.Mesh
}

// ───────────── 像素图 ─────────────

const RGB = new Map<string, number[]>()
const rgb = (c: string) => RGB.get(c) ?? (RGB.set(c, hexRgb(c)), RGB.get(c)!)
const dark = (c: string, t: number) => mixHex(c, '#000000', t)
const light = (c: string, t: number) => mixHex(c, '#ffffff', t)

/** 逐像素画的小图；wrap 时横向首尾相接（绕塔一圈的贴图） */
class Pixmap {
  private readonly data: Uint8ClampedArray
  constructor(
    readonly w: number,
    readonly h: number,
    private readonly wrap = false
  ) {
    this.data = new Uint8ClampedArray(w * h * 4)
  }
  /** c 为 null 是透明 */
  set(i: number, j: number, c: string | null) {
    if (this.wrap) i = ((i % this.w) + this.w) % this.w
    if (i < 0 || j < 0 || i >= this.w || j >= this.h) return
    const o = (j * this.w + i) * 4
    if (!c) {
      this.data[o + 3] = 0
      return
    }
    const [r, g, b] = rgb(c)
    this.data[o] = r
    this.data[o + 1] = g
    this.data[o + 2] = b
    this.data[o + 3] = 255
  }
  fill(color: (i: number, j: number) => string | null) {
    for (let j = 0; j < this.h; j++) for (let i = 0; i < this.w; i++) this.set(i, j, color(i, j))
    return this
  }
  rect(i: number, j: number, w: number, h: number, c: string | null) {
    for (let y = j; y < j + h; y++) for (let x = i; x < i + w; x++) this.set(x, y, c)
  }
  /** 按字符画一块：key 里查颜色，空格不画 */
  stamp(i: number, j: number, rows: readonly string[], key: Record<string, string | null>) {
    rows.forEach((row, y) => {
      for (let x = 0; x < row.length; x++) if (row[x] !== ' ') this.set(i + x, j + y, key[row[x]])
    })
  }
  canvas() {
    const c = document.createElement('canvas')
    c.width = this.w
    c.height = this.h
    const ctx = c.getContext('2d')!
    const img = ctx.createImageData(this.w, this.h)
    img.data.set(this.data)
    ctx.putImageData(img, 0, 0)
    return c
  }
}

/** 可平铺的贴图：几何的贴图坐标按贴图像素算，一个单位一格 */
function tile(map: Pixmap) {
  const t = texture(map.canvas())
  t.wrapS = t.wrapT = THREE.RepeatWrapping
  t.repeat.set(1 / map.w, 1 / map.h)
  return t
}

/** 绕一圈的贴图铺在圆柱上：横向重复 around 次、纵向 up 次 */
function wrapped(map: Pixmap, around = 1, up = 1) {
  const t = texture(map.canvas())
  t.wrapS = t.wrapT = THREE.RepeatWrapping
  t.repeat.set(around, up)
  return t
}

/** 平铺的方石：两层，一层两格高，石块长短不一、上下错缝，每块上沿受光 */
function ashlar(p: Palette, salt: number) {
  const W = 48
  const cuts = [0, 1].map((course) => {
    const list: number[] = []
    for (let x = Math.floor(hash(course, salt, 3) * 5); x < W - 4;)
      (list.push(x), (x += 5 + Math.floor(hash(x, course, salt) * 5)))
    return list
  })
  return new Pixmap(W, 4).fill((i, j) => {
    const course = j >> 1,
      list = cuts[course]
    if (list.includes(i)) return p.mortar
    // 首尾相接：第一道缝左边那块和最后一块是同一块
    const start = [...list].reverse().find((c) => c <= i) ?? list[list.length - 1]
    const base = p.stone[Math.floor(hash(start, course, salt + 1) * 3)]
    if (p.ruined && noise(i / 3, j * 1.7, salt + 2) > 0.74) return dark(base, 0.25)
    return (j & 1) === 0 ? light(base, 0.08) : base
  })
}

/** 平铺的刷白栏墙：石缝淡淡的，零星几点脏 */
function washTile(p: Palette) {
  return new Pixmap(24, 4).fill((i, j) => {
    if ((i + (j >> 1) * 5) % 8 === 0 && !p.snow) return dark(p.wash, 0.06)
    if (p.ruined && noise(i / 3, j, 181) > 0.6) return dark(p.wash, 0.2)
    return hash(i, j, 182) < 0.07 ? dark(p.wash, 0.05) : p.wash
  })
}

/** 平铺的粗石脚：两格高，大块湿石头，贴水的一排长着海藻 */
function rockTile(p: Palette) {
  return new Pixmap(40, 2).fill((i, j) => {
    const block = Math.floor((i + hash(j, 0, 41) * 3) / 7)
    if ((i + Math.floor(hash(block, j, 42) * 2)) % 7 === 0) return p.rock[2]
    if (j === 1 && noise(i / 2.5, 0, 43) > 0.42) return p.weed
    const c = p.rock[Math.floor(hash(block, 1, 44) * 2)]
    return j === 0 ? light(c, 0.08) : c
  })
}

/** 平铺的压顶石、台阶面：浅色长条石，冰雪时盖着雪 */
function copingTile(p: Palette) {
  return new Pixmap(16, 8).fill((i, j) => {
    if (p.snow) return hash(i, j, 51) < 0.12 ? SNOW_SHADE : SNOW
    if (i % 8 === 0 || j % 4 === 0) return dark(p.coping, 0.1)
    return hash(i >> 3, j >> 2, 52) < 0.5 ? p.coping : dark(p.coping, 0.04)
  })
}

/** 台面上一格：石板错缝铺，塔脚一圈放射状的小方石；靠墙根（edge 格以内）、塔脚发暗，缝里、墙角长青苔；
 *  冰雪时一片雪，从台阶到塔门踩出一条道。ring0 是塔脚外沿离塔中心几格 */
function paving(
  p: Palette,
  i: number,
  j: number,
  x: number,
  z: number,
  edge: number,
  ring0: number,
  path: [Pt, Pt]
) {
  const r = Math.hypot(x, z) / P
  if (p.snow) {
    const trodden = segmentDistance([x, z], path) < 2.6 * P
    let c = trodden
      ? (i + j) % 3 === 0
        ? SNOW_SHADE
        : '#dbe4ec'
      : hash(i, j, 61) < 0.08
        ? '#e6edf3'
        : SNOW
    if (edge < 4 || r < ring0 + 1) c = mixHex(c, SNOW_SHADE, 0.6)
    return c
  }
  let c: string
  if (r >= ring0 - 1 && r < ring0 + 5) {
    // 放射状的小方石：一圈一圈，每圈按周长分格
    const ring = Math.floor((r - ring0 + 1) / 2.5)
    const rr = ring0 + ring * 2.5
    const n = Math.max(8, Math.round((2 * Math.PI * rr) / 3))
    const a = (Math.atan2(x, z) / (2 * Math.PI) + 0.5) * n + ring * 0.5
    const cell = Math.floor(a)
    const seam = a - cell < 0.3 || (r - ring0 + 1) % 2.5 < 0.6
    c = seam ? p.joint : p.paving[Math.floor(hash(cell, ring, 62) * 3)]
  } else {
    const row = Math.floor(j / 5),
      off = Math.floor(hash(row, 1, 63) * 7)
    const col = Math.floor((i + off) / 7)
    c = j % 5 === 0 || (i + off) % 7 === 0 ? p.joint : p.paving[Math.floor(hash(col, row, 64) * 3)]
    if (p.ruined && noise(i / 5, j / 5, 65) > 0.7) c = dark(c, 0.2)
  }
  // 青苔：石板缝里零星，靠墙根、墙角成片
  const moss = noise(i / 4, j / 4, 66) + (edge < 7 ? 0.25 : 0) - (edge < 3 ? 1 : 0)
  if (!p.ruined && moss > 0.82) c = moss > 0.95 ? '#6f8450' : mixHex(c, '#7f9258', 0.55)
  if (p.ruined && moss > 0.9) c = '#7a6a4a'
  // 墙根和塔脚的阴影
  if (edge < 4) c = dark(c, edge < 3 ? 0.3 : 0.14)
  if (r < ring0) c = dark(c, 0.2)
  return c
}

/** 台面一整张图：从台阶到塔门是 path */
function deckCanvas(p: Palette, X: number, Z: number, tower: Tower, path: [Pt, Pt]) {
  const W = Math.max(4, Math.round((2 * X) / P)),
    H = Math.max(4, Math.round((2 * Z) / P))
  return new Pixmap(W, H)
    .fill((i, j) =>
      paving(
        p,
        i,
        j,
        -X + ((i + 0.5) * 2 * X) / W,
        -Z + ((j + 0.5) * 2 * Z) / H,
        Math.min(i, j, W - 1 - i, H - 1 - j),
        tower.foot / P + 4,
        path
      )
    )
    .canvas()
}

/** 剖开后的地面，铺满整块占地：台面的石板一直铺到塔墙脚，台子边外那一圈是湿石脚；
 *  塔里是一圈圈的石板，正中嵌一个八角罗盘。inside 判断一点在不在台子里（含台阶口） */
function floorCanvas(
  p: Palette,
  w: number,
  h: number,
  X: number,
  Z: number,
  rIn: number,
  rOut: number,
  inside: (x: number, z: number) => boolean,
  path: [Pt, Pt]
) {
  const W = Math.max(4, Math.round(w / P)),
    H = Math.max(4, Math.round(h / P))
  const inset = Math.round((w / 2 - X) / P)
  const star = rIn / P - 1.5
  return new Pixmap(W, H)
    .fill((i, j) => {
      const x = -w / 2 + ((i + 0.5) * w) / W,
        z = -h / 2 + ((j + 0.5) * h) / H
      const r = Math.hypot(x, z)
      if (r >= rIn && r < rOut) return p.stone[2]
      if (r < rIn) {
        // 罗盘：四个长尖指东南西北、四个短尖指四角，每个尖一半亮一半暗；外面一圈圈石板
        const a = Math.atan2(x, z),
          d = r / P
        const quarter = Math.PI / 2
        const main = a - Math.round(a / quarter) * quarter
        const minor = a - quarter / 2 - Math.round((a - quarter / 2) / quarter) * quarter
        const reachMain = star * (1 - Math.abs(main) / (quarter / 2)) ** 1.6
        const reachMinor = star * 0.55 * (1 - Math.abs(minor) / (quarter / 2)) ** 1.6
        if (d < 1.2) return '#c9a04e'
        if (d < reachMain) return main > 0 ? '#e8dcc0' : '#4e5866'
        if (d < reachMinor) return '#b8913e'
        if (Math.abs(d - star - 0.6) < 0.6) return '#4e5866'
        const ring = Math.floor((rIn / P - d) / 2.5)
        const seam = (rIn / P - d) % 2.5 < 0.6
        return seam ? p.joint : p.paving[Math.floor(hash(ring, Math.floor(a * 3), 67) * 3)]
      }
      if (!inside(x, z)) {
        // 台子边外：剖开前是石脚顶，湿石头上长着海藻
        if (p.snow) return hash(i, j, 68) < 0.3 ? SNOW_SHADE : '#dfe7ee'
        return noise(i / 2.5, j / 2.5, 69) > 0.6 ? p.weed : p.rock[Math.floor(hash(i, j, 70) * 2)]
      }
      const edge = Math.min(i, j, W - 1 - i, H - 1 - j) - inset
      return paving(p, i, j, x, z, edge, rOut / P, path)
    })
    .canvas()
}

/** 台面夜里的灯光：台阶两盏灯、塔门口各照出一圈暖光，按台阶和有序抖动过渡 */
function deckGlow(X: number, Z: number, lights: readonly Pt[]) {
  const W = Math.max(4, Math.round((2 * X) / P)),
    H = Math.max(4, Math.round((2 * Z) / P))
  const reach = 16 * P
  return new Pixmap(W, H)
    .fill((i, j) => {
      const x = -X + ((i + 0.5) * 2 * X) / W,
        z = -Z + ((j + 0.5) * 2 * Z) / H
      let v = 0
      for (const [lx, lz] of lights) v += Math.max(0, 1 - Math.hypot(x - lx, z - lz) / reach) ** 2
      const q = Math.min(4, Math.floor(Math.min(1, v) * 4 + bayer(i, j))) / 4
      return mixHex('#000000', LAMP_GLOW, q * 0.6)
    })
    .canvas()
}

/** 塔身：几道漆，漆底下隐约看得出石块；窗是带石框的小拱窗，窗台下一道水渍；墙脚溅脏。
 *  windows 是窗的 [横向像素, 离塔身底几格]；colorAt 换掉按高度分匀的几道漆（剖开后的残墙用）；返回贴图和夜里亮的窗 */
function bodyPixmaps(
  p: Palette,
  W: number,
  H: number,
  windows: [number, number][],
  seed: number,
  colorAt?: (y: number) => string
) {
  const nb = p.bands.length
  const band = (y: number) => Math.min(nb - 1, Math.floor((y / H) * nb))
  const map = new Pixmap(W, H, true).fill((i, j) => {
    const y = H - 1 - j
    let c = colorAt ? colorAt(y) : p.bands[band(y)]
    const course = Math.floor(y / 3)
    if (y % 3 === 2 && hash(i >> 2, course, seed) < 0.55) c = dark(c, 0.05)
    else if ((i + (course & 1) * 4) % 8 === 0) c = dark(c, 0.035)
    // 墙脚溅上的泥
    if (y < 5 && noise(i / 3, y / 2, seed + 1) > 0.3 + y * 0.12) c = mixHex(c, '#4a4036', 0.2)
    if (p.ruined) {
      // 漆掉了几块露出石头，锈水从上往下流
      if (noise(i / 4, y / 5, seed + 2) > 0.7) c = mixHex(c, '#8a8478', 0.6)
      if (hash(i, 0, seed + 3) < 0.12 && j < hash(i, 1, seed + 3) * H * 0.7)
        c = mixHex(c, '#6e4a32', 0.55)
    } else if (hash(i, j, seed + 4) < 0.025) c = dark(c, 0.06)
    return c
  })
  const glow = new Pixmap(W, H, true).fill(() => '#000000')
  for (const [u, y] of windows) {
    const j = H - 1 - y
    const under = p.bands[band(y)]
    const trim = p.ruined
      ? '#8e877a'
      : under === p.bands[0]
        ? dark(under, 0.16)
        : light(under, 0.82)
    // 5 宽 7 高：拱顶、三格宽的玻璃、窗台
    map.stamp(u - 2, j - 4, [' sss ', 'sgGgs', 'sgggs', 'sgggs', 'sgggs', 'sgggs', 'kkkkk'], {
      s: trim,
      g: '#233140',
      G: '#5a7896',
      k: light(trim, 0.1),
    })
    if (!p.ruined || hash(u, y, seed) < 0.5)
      for (let k = 1; k < 4; k++) map.set(u, j + 2 + k, dark(under, 0.1 + 0.03 * (3 - k)))
    glow.stamp(u - 1, j - 3, ['ggg', 'ggg', 'ggg', 'ggg', 'ggg'], { g: LAMP_GLOW })
    if (p.ruined) map.stamp(u - 1, j - 3, ['g  ', ' g ', '  g'], { g: '#4a5866' })
  }
  return { map, glow }
}

/** 剖开后塔墙里面：刷白的墙、下半截护墙板和踢脚线；背面开两扇深窗，窗间挂陈设（画法同灯塔房间的北墙）。
 *  从塔里看不左右颠倒：列号按角度从大到小排。windows、decor 是列号；返回贴图和夜里亮的窗 */
function plasterPixmaps(
  p: Palette,
  pal: InteriorPalette,
  W: number,
  H: number,
  windows: number[],
  decor: number[],
  seed: number
) {
  const panelTop = H - Math.round(H * 0.34)
  // 塔里窄、光进不来，护墙板比房间里的浅一档，不然看着像个黑洞
  const panel = mixHex(pal.panel, pal.paper, 0.45)
  const map = new Pixmap(W, H, true).fill((i, j) => {
    if (j === 0) return pal.trim
    if (j >= H - 2) return pal.trim
    if (j >= panelTop) return j === panelTop || (i % 8 === 3 && j < H - 3) ? pal.trim : panel
    let c = i % 4 < 2 ? pal.paper : pal.stripe
    if (p.ruined && noise(i / 3, j / 3, seed + 9) > 0.66) c = mixHex(c, '#8a7a62', 0.4)
    return c
  })
  const glow = new Pixmap(W, H, true).fill(() => '#000000')
  const wy = 3,
    wh = Math.min(8, panelTop - 5)
  for (const u of windows) {
    // 深窗：窗洞两边是墙的厚度，暗一档
    map.rect(u - 3, wy - 1, 7, wh + 2, pal.trim)
    map.rect(u - 2, wy, 5, wh, dark(pal.paper, 0.25))
    map.rect(u - 1, wy, 3, wh, '#9cc8e0')
    map.rect(u - 1, wy, 3, 1, '#c8e4f0')
    map.rect(u - 3, wy + wh + 1, 7, 1, light(pal.paper, 0.2))
    glow.rect(u - 1, wy, 3, wh, LAMP_GLOW)
  }
  const rect: Rect = (i, j, w, h, c) => map.rect(i, j, w, h, c)
  decor.forEach((u, k) => lighthouseDecor(rect, u - 7, u + 7, panelTop, H, seed + k, pal))
  return { map, glow }
}

/** 托瞭望台的牛腿：一圈石托，托与托之间是深影，最上一道是台底的阴影 */
function corbelPixmap(p: Palette, W: number) {
  return new Pixmap(W, 3, true).fill((i, j) => {
    if (j === 0) return p.iron[0]
    const k = i % 4
    const gone = p.ruined && hash(Math.floor(i / 4), 0, 71) < 0.3
    if (k > 1 || gone || (j === 2 && k === 1)) return '#2b2a2c'
    const c = p.snow ? '#d8dde2' : p.coping
    return j === 1 ? light(c, 0.12) : dark(c, 0.1)
  })
}

/** 栏杆：上下两道扶手，三格一根立杆，十二格一根粗柱；ruined 时断了几段、少了几根 */
function railPixmap(p: Palette, W: number) {
  return new Pixmap(W, 4, true).fill((i, j) => {
    if (p.ruined && (hash(Math.floor(i / 7), 0, 81) < 0.32 || hash(i, j, 82) < 0.12)) return null
    if (i % 12 === 0 || i % 12 === 1) return p.iron[0]
    if (j === 0) return p.iron[2]
    if (j === 2) return p.iron[1]
    return i % 3 === 0 ? p.iron[1] : null
  })
}

/** 灯室底座：一道亮边，漆面上开一圈通风孔，最下一道暗 */
function pedestalPixmap(p: Palette, W: number, paint: readonly string[]) {
  const map = new Pixmap(W, 4, true).fill((_, j) =>
    j === 0 ? p.iron[2] : j === 3 ? paint[2] : paint[1]
  )
  const holes = 6
  for (let k = 0; k < holes; k++)
    map.stamp(Math.round(((k + 0.5) * W) / holes) - 1, 1, ['bd', 'dd'], {
      b: '#c9a04e',
      d: '#1d2224',
    })
  return map
}

/** 灯室的铁框：每面一根竖框，上下框和一道横档；框以外透明 */
function framePixmap(p: Palette, faces: number, fw: number, H: number) {
  return new Pixmap(faces * fw, H, true).fill((i, j) => {
    if (i % fw === 0) return j === 0 ? p.iron[2] : p.iron[1]
    if (j === 0 || j === H - 1) return p.iron[1]
    return j === Math.floor(H / 2) ? p.iron[0] : null
  })
}

/** 玻璃：淡青，隔几面靠左一道竖的反光 */
function glassPixmap(faces: number, fw: number, H: number) {
  return new Pixmap(faces * fw, H, true).fill((i, j) => {
    const face = Math.floor(i / fw)
    if (i % fw === 1 && j > 1 && j < H - 2 && face % 3 === 0) return '#f4fbfd'
    return '#b9dce6'
  })
}

/** 透镜：上下黄铜箍，中间一圈圈棱镜，正中两道最亮；返回贴图和亮度图 */
function lensPixmaps() {
  const ROWS = ['b', 'l', 'c', 'c', 'l', 'b']
  const MAP: Record<string, string> = { b: '#9a7634', l: '#d9b45e', c: '#f3dc98' }
  const GLOW: Record<string, string> = { b: '#000000', l: '#9a9a9a', c: '#ffffff' }
  const at = (table: Record<string, string>) => (i: number, j: number) => {
    const c = table[ROWS[j]]
    return i % 4 === 0 && ROWS[j] !== 'b' ? dark(c, 0.25) : c
  }
  return {
    map: new Pixmap(16, ROWS.length, true).fill(at(MAP)),
    glow: new Pixmap(16, ROWS.length, true).fill(at(GLOW)),
  }
}

/** 圆顶：十道筋，冰雪时顶上盖着雪 */
function domePixmap(p: Palette, W: number, paint: readonly string[]) {
  const rib = Math.max(3, Math.round(W / 10))
  return new Pixmap(W, 5, true).fill((i, j) => {
    if (p.snow && j < 2 + (hash(i, 0, 101) < 0.4 ? 1 : 0)) return j === 2 ? SNOW_SHADE : SNOW
    if (i % rib === 0) return paint[2]
    return j === 4 ? paint[2] : paint[1]
  })
}

/** 门廊正面：方石墙面上一扇拱门，石砌的门券和拱心石，门上两道铁合页、一个黄铜把手 */
function portalPixmap(p: Palette) {
  const map = new Pixmap(13, 14).fill((i, j) => {
    const row = j >> 1
    const c = p.stone[Math.floor(hash((i + (row & 1) * 3) >> 2, row, 111) * 3)]
    return (i + (row & 1) * 3) % 4 === 0 || j % 2 === 1 ? dark(c, 0.05) : light(c, 0.05)
  })
  const S = p.snow ? '#e4e8ec' : p.coping
  // prettier-ignore
  map.stamp(1, 1, [
    '    kkk    ',
    '   sssss   ',
    '  ss   ss  ',
    ' ss     ss ',
    ' s       s ',
    ' s       s ',
    ' s       s ',
    ' s       s ',
    ' s       s ',
    ' s       s ',
    ' s       s ',
    ' s       s ',
    'sssssssssss',
  ], { k: light(S, 0.25), s: S })
  const D = p.door
  // prettier-ignore
  map.stamp(3, 3, [
    '  ddd  ',
    ' ddDdd ',
    'ddddddd',
    'hhhdddd',
    'ddddddd',
    'dddDddd',
    'ddddddb',
    'ddddddd',
    'hhhdddd',
    'ddddddd',
  ], { d: D, D: dark(D, 0.25), h: p.iron[0], b: '#e0b060' })
  for (let j = 5; j < 13; j++) map.set(6, j, dark(D, 0.2))
  return map
}

/** 门廊山墙上的瓦：屋顶的三色；冰雪时盖着雪 */
function tilePixmap(paint: readonly string[], snow: boolean) {
  return new Pixmap(8, 4).fill((i, j) => {
    if (snow) return j < 3 ? SNOW : SNOW_SHADE
    if (j === 3) return paint[2]
    return (i + (j & 1) * 2) % 4 === 0 ? paint[2] : j === 0 ? paint[0] : paint[1]
  })
}

/** 木桶：竖的板条，两道铁箍 */
function barrelPixmap(p: Palette, H: number) {
  const wood = p.ruined ? ['#6e4a32', '#7e5a3a', '#5e3c28'] : ['#8a6644', '#9a7450', '#7a583a']
  return new Pixmap(12, H, true).fill((i, j) => {
    if (j === 1 || j === H - 2) return p.iron[1]
    if (p.ruined && noise(i / 2, j / 2, 121) > 0.6) return '#8a4a24'
    return i % 2 === 0 ? wood[2] : wood[Math.floor(hash(i, 0, 122) * 2)]
  })
}

/** 花盆里的花：叶子上点着几朵花 */
function bloomPixmap(flowers: readonly string[], seed: number) {
  return new Pixmap(8, 6, true).fill((i, j) => {
    if (hash(i, j, seed) < 0.22) return flowers[Math.floor(hash(i, j, seed + 1) * flowers.length)]
    return j < 2 ? '#7fa65a' : hash(i, j, seed + 2) < 0.5 ? '#5d8a46' : '#4c7439'
  })
}

/** 信号旗：几面不同图案的方旗 */
const FLAGS: ((i: number, j: number) => string)[] = [
  (i) => (i < 2 ? '#f4f1ea' : '#3a5f9a'),
  (i, j) => (i + j < 4 ? '#c8453b' : '#e8c24a'),
  (i, j) => (i < 2 !== j < 2 ? '#c8453b' : '#f4f1ea'),
  (_, j) => (j === 1 || j === 2 ? '#f4f1ea' : '#3a5f9a'),
  (i) => (i === 1 || i === 2 ? '#c8453b' : '#e8c24a'),
  () => '#e8c24a',
]

// ───────────── 几何 ─────────────

/** 攒成一个 BufferGeometry：每个面给三个点和贴图坐标，法线按点的顺序算（逆时针朝外） */
class Builder {
  private readonly pos: number[] = []
  private readonly uv: number[] = []
  tri(a: number[], b: number[], c: number[], ua: Pt, ub: Pt, uc: Pt) {
    this.pos.push(...a, ...b, ...c)
    this.uv.push(...ua, ...ub, ...uc)
  }
  quad(a: number[], b: number[], c: number[], d: number[], ua: Pt, ub: Pt, uc: Pt, ud: Pt) {
    this.tri(a, b, c, ua, ub, uc)
    this.tri(a, c, d, ua, uc, ud)
  }
  geometry() {
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3))
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2))
    g.computeVertexNormals()
    return g
  }
}

/** 竖着围一圈的墙：轮廓按地图上逆时针排（z 朝下看），每条边朝外；u 沿周长按格、v 按高度的格 */
function walls(b: Builder, outline: readonly Pt[], y0: number, y1: number) {
  let s = 0
  for (let k = 0; k < outline.length; k++) {
    const [ax, az] = outline[k],
      [bx, bz] = outline[(k + 1) % outline.length]
    const len = Math.hypot(bx - ax, bz - az)
    const u0 = s / P,
      u1 = (s + len) / P
    b.quad(
      [ax, y0, az],
      [bx, y0, bz],
      [bx, y1, bz],
      [ax, y1, az],
      [u0, y0 / T],
      [u1, y0 / T],
      [u1, y1 / T],
      [u0, y1 / T]
    )
    s += len
  }
}

/** 顶面：多边形三角剖分，朝上；贴图坐标由 uv 给（默认按地图像素平铺） */
function cap(
  b: Builder,
  outline: readonly Pt[],
  y: number,
  uv: (x: number, z: number) => Pt = (x, z) => [x / P, -z / P]
) {
  const tris = THREE.ShapeUtils.triangulateShape(
    outline.map(([x, z]) => new THREE.Vector2(x, z)),
    []
  )
  for (const [i, j, k] of tris) {
    const [a, c, d] = [outline[i], outline[j], outline[k]]
    // 朝上：(c-a)×(d-a) 的 y 分量为正
    const up = (c[1] - a[1]) * (d[0] - a[0]) - (c[0] - a[0]) * (d[1] - a[1]) > 0
    const [p1, p2] = up ? [c, d] : [d, c]
    b.tri([a[0], y, a[1]], [p1[0], y, p1[1]], [p2[0], y, p2[1]], uv(...a), uv(...p1), uv(...p2))
  }
}

/** 一根长条（栏墙、台阶）：沿 a→b、往里厚 depth，从 y0 到 y1，带顶面 */
function bar(sides: Builder, top: Builder, a: Pt, b: Pt, depth: number, y0: number, y1: number) {
  const dx = b[0] - a[0],
    dz = b[1] - a[1],
    len = Math.hypot(dx, dz) || 1
  const nx = (dz / len) * depth,
    nz = (-dx / len) * depth
  const box: Pt[] = [a, b, [b[0] + nx, b[1] + nz], [a[0] + nx, a[1] + nz]]
  walls(sides, box, y0, y1)
  cap(top, box, y1)
}

/** 方柱的轮廓：中心 c、半边长 half */
const square = ([x, z]: Pt, half: number): Pt[] => [
  [x - half, z + half],
  [x + half, z + half],
  [x + half, z - half],
  [x - half, z - half],
]

/** 两点之间的一根圆杆（三脚架的腿、望远镜筒）：a 端半径 ra、b 端半径 rb */
function rod(a: THREE.Vector3, b: THREE.Vector3, ra: number, rb = ra) {
  const dir = b.clone().sub(a)
  const g = new THREE.CylinderGeometry(rb, ra, dir.length(), 6)
  g.translate(0, dir.length() / 2, 0)
  g.applyQuaternion(
    new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.normalize())
  )
  return g.translate(a.x, a.y, a.z)
}

/** 点到线段的距离 */
function segmentDistance([x, z]: Pt, [[ax, az], [bx, bz]]: [Pt, Pt]) {
  const dx = bx - ax,
    dz = bz - az
  const t = Math.max(0, Math.min(1, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz || 1)))
  return Math.hypot(x - ax - t * dx, z - az - t * dz)
}

/** 剖开的一圈塔墙：外半径 rOut、里半径 rIn，高度按角度给（height 返回世界单位）；门洞 gap = [中心角, 半宽角] 不砌。
 *  外面的 u 绕一圈 0→1，里面反过来（从塔里看不左右颠倒），v 按 top 归一；墙顶和高低错开的截面是一块，不贴图 */
function ringWall(
  rIn: number,
  rOut: number,
  height: (a: number) => number,
  top: number,
  gap: readonly [number, number],
  n = 64
) {
  const outer = new Builder(),
    inner = new Builder(),
    cut = new Builder()
  const at = (r: number, a: number, y: number) => [Math.sin(a) * r, y, Math.cos(a) * r]
  const angle = (k: number) => (k / n) * 2 * Math.PI
  const hs = Array.from({ length: n }, (_, k) => {
    const mid = (angle(k) + angle(k + 1)) / 2
    const off = Math.atan2(Math.sin(mid - gap[0]), Math.cos(mid - gap[0]))
    return Math.abs(off) < gap[1] ? 0 : height(mid)
  })
  const none: Pt = [0, 0]
  for (let k = 0; k < n; k++) {
    const a0 = angle(k),
      a1 = angle(k + 1),
      y = hs[k]
    if (y > 0) {
      const u0 = k / n,
        u1 = (k + 1) / n
      outer.quad(
        at(rOut, a0, 0),
        at(rOut, a1, 0),
        at(rOut, a1, y),
        at(rOut, a0, y),
        [u0, 0],
        [u1, 0],
        [u1, y / top],
        [u0, y / top]
      )
      inner.quad(
        at(rIn, a1, 0),
        at(rIn, a0, 0),
        at(rIn, a0, y),
        at(rIn, a1, y),
        [1 - u1, 0],
        [1 - u0, 0],
        [1 - u0, y / top],
        [1 - u1, y / top]
      )
      cut.quad(
        at(rOut, a0, y),
        at(rOut, a1, y),
        at(rIn, a1, y),
        at(rIn, a0, y),
        none,
        none,
        none,
        none
      )
    }
    // 和下一段高低不一样的地方（含门洞两边）露出截面
    const next = hs[(k + 1) % n]
    if (next !== y) {
      const lo = Math.min(y, next),
        hi = Math.max(y, next)
      cut.quad(
        at(rOut, a1, lo),
        at(rIn, a1, lo),
        at(rIn, a1, hi),
        at(rOut, a1, hi),
        none,
        none,
        none,
        none
      )
    }
  }
  return { outer: outer.geometry(), inner: inner.geometry(), cut: cut.geometry() }
}

/** 台阶口：门那一面的边上往台子里切进去；a、b 是口子两角（在边上），inward 往里、along 沿边 */
interface Notch {
  a: Pt
  b: Pt
  inward: Pt
  along: Pt
  depth: number
}

/** 平台的轮廓：占地往里收 inset、四角切角 chamfer；门那面的边上切一道台阶口 */
function deckOutline(
  w: number,
  h: number,
  inset: number,
  chamfer: number,
  door: Pt,
  stair: { width: number; depth: number }
) {
  const X = w / 2 - inset,
    Z = h / 2 - inset,
    c = chamfer
  // 四条边按逆时针：南边往东、东边往北、北边往西、西边往南
  const edges: { side: string; start: Pt; along: Pt; len: number; inward: Pt }[] = [
    { side: 's', start: [-X + c, Z], along: [1, 0], len: 2 * (X - c), inward: [0, -1] },
    { side: 'e', start: [X, Z - c], along: [0, -1], len: 2 * (Z - c), inward: [-1, 0] },
    { side: 'n', start: [X - c, -Z], along: [-1, 0], len: 2 * (X - c), inward: [0, 1] },
    { side: 'w', start: [-X, -Z + c], along: [0, 1], len: 2 * (Z - c), inward: [1, 0] },
  ]
  // 门在哪面：离哪条占地边最近
  const [dx, dz] = door
  const gaps: Record<string, number> = {
    s: Math.abs(dz - h / 2),
    n: Math.abs(dz + h / 2),
    e: Math.abs(dx - w / 2),
    w: Math.abs(dx + w / 2),
  }
  const side = Object.keys(gaps).reduce((m, k) => (gaps[k] < gaps[m] ? k : m))
  const pts: Pt[] = []
  let notch: Notch | undefined
  for (const e of edges) {
    const on = (s: number, d = 0): Pt => [
      e.start[0] + e.along[0] * s + e.inward[0] * d,
      e.start[1] + e.along[1] * s + e.inward[1] * d,
    ]
    pts.push(e.start)
    if (e.side === side) {
      const half = stair.width / 2
      const at = Math.max(
        half + 2 * P,
        Math.min(
          e.len - half - 2 * P,
          (dx - e.start[0]) * e.along[0] + (dz - e.start[1]) * e.along[1]
        )
      )
      notch = {
        a: on(at - half),
        b: on(at + half),
        inward: e.inward,
        along: e.along,
        depth: stair.depth,
      }
      pts.push(on(at - half), on(at - half, stair.depth), on(at + half, stair.depth), on(at + half))
    }
    pts.push(on(e.len))
  }
  // 切角为 0 时相邻两边的端点重合
  const outline = pts.filter((q, k) => {
    const r = pts[(k + 1) % pts.length]
    return Math.hypot(q[0] - r[0], q[1] - r[1]) > 0.01
  })
  return { outline, notch: notch!, X, Z }
}

/** 兰伯特光照分四档：圆的面（塔身、圆顶、木桶）明暗一档一档的，像手画的像素 */
const BANDED_LIGHT = THREE.ShaderChunk.lights_lambert_pars_fragment.replace(
  'float dotNL = saturate( dot( geometryNormal, directLight.direction ) );',
  'float dotNL = floor( saturate( dot( geometryNormal, directLight.direction ) ) * 4.0 + 0.6 ) / 4.0;'
)
if (BANDED_LIGHT === THREE.ShaderChunk.lights_lambert_pars_fragment)
  console.warn('灯塔的分档光照没能改写着色器片段')
function banded<M extends THREE.MeshLambertMaterial>(m: M) {
  const before = m.onBeforeCompile.bind(m)
  const key = m.customProgramCacheKey()
  m.onBeforeCompile = (shader, renderer) => {
    before(shader, renderer)
    shader.fragmentShader = shader.fragmentShader.replace(
      '#include <lights_lambert_pars_fragment>',
      BANDED_LIGHT
    )
  }
  m.customProgramCacheKey = () => `${key}|banded`
  return m
}

/** 像素贴图的兰伯特材质 */
function lambert(params: THREE.MeshLambertMaterialParameters) {
  return pixelMaterial(new THREE.MeshLambertMaterial(params))
}

/** 镂空的面（栏杆、铁框、旗、风向标）投影也按镂空投 */
function cutout(mesh: THREE.Mesh, map: THREE.Texture) {
  mesh.customDepthMaterial = pixelMaterial(
    new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, map, alphaTest: 0.5 })
  )
  return mesh
}

/** 两束光：从透镜往外，中间亮、两边和远处渐暗，叠加混合；场景按夜色调亮、绕着转 */
function beams(radius: number) {
  const length = 120 * P,
    half = 9 * P
  const BRIGHT = [1, 0.93, 0.72]
  // 每束三段（灯边、中段、尽头），每段左、中、右三列；正中亮，两边只有一点
  const rows = [
    { d: radius, w: radius * 0.8, k: 1 },
    { d: length * 0.35, w: half * 0.35 + radius, k: 0.38 },
    { d: length, w: half, k: 0 },
  ]
  const pos: number[] = [],
    col: number[] = []
  for (const s of [1, -1])
    for (let k = 0; k < 2; k++)
      for (const [l, r] of [
        [-1, 0],
        [0, 1],
      ]) {
        const corners = [
          [rows[k], l],
          [rows[k], r],
          [rows[k + 1], r],
          [rows[k + 1], l],
        ] as const
        for (const q of [0, 1, 2, 0, 2, 3]) {
          const [row, side] = corners[q]
          pos.push(s * row.d, 0, s * side * row.w)
          col.push(...BRIGHT.map((c) => c * row.k * (side === 0 ? 1 : 0.15)))
        }
      }
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
  mesh.renderOrder = 3
  return mesh
}

// ───────────── 搭起来 ─────────────

/** 搭一座灯塔。door 是门外那一点相对占地中心的位置（不给就当门在南边） */
export function lighthouse(house: House, door: Pt | undefined, style: Style): Lighthouse {
  const tower = house.tower!
  const p = PALETTES[style]
  const { w, h, seed } = house
  const paint = house.roof
  const group = new THREE.Group()
  const out: Lighthouse = {
    group,
    weathered: [],
    walls: [],
    glowing: [],
    burning: [],
    glows: [],
    smoke: [],
    grounds: [],
    room: { group: new THREE.Group(), glowing: [] },
  }
  const add = (mesh: THREE.Mesh, shadow = true) => {
    mesh.castShadow = mesh.receiveShadow = shadow
    group.add(mesh)
    return mesh
  }
  const weather = <M extends THREE.MeshLambertMaterial>(
    m: M,
    snow = 1,
    wet = 0.5,
    wall = false
  ) => {
    out.weathered.push({ material: m, snow, wet })
    if (wall) out.walls.push(m)
    return m
  }
  const around = (r: number) => (2 * Math.PI * r) / P

  // ── 石台 ──
  const stair = { width: 14 * P, depth: 9 * P }
  const chamfer = Math.round(Math.min(w, h) / P / 9) * P
  const { outline, notch, X, Z } = deckOutline(w, h, 3 * P, chamfer, door ?? [0, h / 2], stair)
  const stoneSides = tile(ashlar(p, seed % 97))
  const stone = weather(lambert({ map: stoneSides }), 1, 0.6, true)
  const coping = weather(lambert({ map: tile(copingTile(p)) }), 1, 0.5)
  const foot: Pt[] = [
    [-w / 2, h / 2],
    [w / 2, h / 2],
    [w / 2, -h / 2],
    [-w / 2, -h / 2],
  ]
  const ledgeSides = new Builder(),
    ledgeTop = new Builder()
  walls(ledgeSides, foot, 0, tower.ledge)
  cap(ledgeTop, foot, tower.ledge)
  add(
    new THREE.Mesh(
      ledgeSides.geometry(),
      weather(lambert({ map: tile(rockTile(p)) }), 1, 0.8, true)
    )
  )
  add(
    new THREE.Mesh(
      ledgeTop.geometry(),
      weather(lambert({ color: p.snow ? '#dfe7ee' : p.rock[0] }), 1, 0.8)
    )
  )
  // 塔门朝着台阶口；台面上从台阶顶到门口是一条道，摆东西都让开它
  const mouth: Pt = [(notch.a[0] + notch.b[0]) / 2, (notch.a[1] + notch.b[1]) / 2]
  const toward = Math.atan2(mouth[0], mouth[1])
  const porchFront = tower.foot + 7 * P
  const doorAt: Pt = [Math.sin(toward) * porchFront, Math.cos(toward) * porchFront]
  const stairTop: Pt = [
    mouth[0] + notch.inward[0] * notch.depth,
    mouth[1] + notch.inward[1] * notch.depth,
  ]
  const path: [Pt, Pt] = [stairTop, doorAt]
  const deckSides = new Builder(),
    deckTop = new Builder()
  walls(deckSides, outline, tower.ledge, tower.deck)
  cap(deckTop, outline, tower.deck, (x, z) => [(x + X) / (2 * X), 1 - (z + Z) / (2 * Z)])
  add(new THREE.Mesh(deckSides.geometry(), stone))
  // 台阶两盏灯（在口子两角的柱头上）和塔门口夜里照亮的地方
  const lampAt = (q: Pt): Pt => {
    const len = Math.hypot(q[0], q[1]) || 1
    return [q[0] - (q[0] / len) * 1.2 * P, q[1] - (q[1] / len) * 1.2 * P]
  }
  const pools: Pt[] = p.ruined
    ? []
    : [lampAt(notch.a), lampAt(notch.b), [doorAt[0] * 1.15, doorAt[1] * 1.15]]
  const deckMat = weather(
    lambert({
      map: texture(deckCanvas(p, X, Z, tower, path)),
      emissiveMap: texture(deckGlow(X, Z, pools)),
      emissive: new THREE.Color('#ffffff'),
      emissiveIntensity: 0,
    }),
    1,
    0.7
  )
  out.glowing.push({ material: deckMat })
  add(new THREE.Mesh(deckTop.geometry(), deckMat))

  // 台阶：三级，从石脚顶上到台面；每级从口子往里铺到底
  const stepSides = new Builder(),
    stepTops = new Builder()
  for (let k = 0; k < 3; k++) {
    const d0 = (notch.depth * k) / 3
    const top = tower.ledge + ((tower.deck - tower.ledge) * (k + 1)) / 3
    const shift = (q: Pt): Pt => [q[0] + notch.inward[0] * d0, q[1] + notch.inward[1] * d0]
    bar(stepSides, stepTops, shift(notch.a), shift(notch.b), notch.depth - d0, tower.ledge, top)
  }
  add(new THREE.Mesh(stepSides.geometry(), stone))
  add(new THREE.Mesh(stepTops.geometry(), coping))

  // 栏墙和石柱：沿平台边，台阶口不砌；口子两角立高柱挂灯，其余拐角立矮柱
  const wallSides = new Builder(),
    wallTops = new Builder(),
    postSides = new Builder(),
    postTops = new Builder()
  const inNotch = (q: Pt) => {
    const s = (q[0] - notch.a[0]) * notch.along[0] + (q[1] - notch.a[1]) * notch.along[1]
    const d = (q[0] - notch.a[0]) * notch.inward[0] + (q[1] - notch.a[1]) * notch.inward[1]
    return s > -0.01 && s < stair.width + 0.01 && d > -0.01 && d < notch.depth + 0.01
  }
  const atMouth = (q: Pt) =>
    [notch.a, notch.b].some((n) => Math.hypot(q[0] - n[0], q[1] - n[1]) < 0.01)
  outline.forEach((a, k) => {
    const b = outline[(k + 1) % outline.length]
    if (atMouth(a) || !inNotch(a)) post(a, atMouth(a), k)
    if (inNotch(a) && inNotch(b)) return
    const broken = p.ruined ? hash(k, 0, seed % 89) : 1
    if (broken < 0.15) return
    const top = broken < 0.4 ? tower.deck + (0.6 + broken * 4) * T : tower.parapet
    bar(wallSides, wallTops, a, b, 2 * P, tower.deck - T, top)
  })
  add(
    new THREE.Mesh(wallSides.geometry(), weather(lambert({ map: tile(washTile(p)) }), 1, 0.5, true))
  )
  add(new THREE.Mesh(wallTops.geometry(), coping))
  add(new THREE.Mesh(postSides.geometry(), stone))
  add(new THREE.Mesh(postTops.geometry(), coping))

  /** 拐角的石柱：往台子里挪一点，顶上压一块帽石；台阶口两根高一些，柱头上挂灯 */
  function post(at: Pt, tall: boolean, k: number) {
    if (p.ruined && !tall && hash(k, 1, 131) < 0.4) return
    const c = lampAt(at)
    const y1 = tall ? tower.deck + 4.5 * T : tower.parapet + 0.8 * T
    walls(postSides, square(c, 1.6 * P), tower.deck - T, y1)
    cap(postTops, square(c, 1.6 * P), y1)
    walls(postSides, square(c, 2.1 * P), y1, y1 + 0.7 * T)
    cap(postTops, square(c, 2.1 * P), y1 + 0.7 * T)
    if (tall && !p.ruined) stairLamp(c, y1 + 0.7 * T)
  }

  /** 台阶柱头上的灯：一个玻璃方灯笼、铁帽 */
  function stairLamp([x, z]: Pt, y: number) {
    const glass = lambert({
      color: '#f6e6b8',
      emissive: new THREE.Color(LAMP_GLOW),
      emissiveIntensity: 0,
    })
    out.glowing.push({ material: glass })
    const box = add(new THREE.Mesh(new THREE.BoxGeometry(2 * P, 2.4 * T, 2 * P), glass))
    box.position.set(x, y + 1.2 * T, z)
    const hat = add(
      new THREE.Mesh(new THREE.ConeGeometry(1.5 * P, 0.8 * T, 4), lambert({ color: p.iron[1] }))
    )
    hat.rotation.y = Math.PI / 4
    hat.position.set(x, y + 2.8 * T, z)
    out.glows.push({ at: new THREE.Vector3(x, y + 1.2 * T, z), size: 20 * P })
  }

  // ── 塔脚：方石砌的喇叭口，顶上一道线脚 ──
  const skirtR = tower.foot + 4 * P,
    skirtH = tower.base - T - tower.deck
  const skirtMap = stoneSides.clone()
  skirtMap.repeat.set(around(skirtR) / 48, skirtH / T / 4)
  const skirt = add(
    new THREE.Mesh(
      new THREE.CylinderGeometry(tower.foot + P, skirtR, skirtH, 48, 1, true),
      weather(banded(lambert({ map: skirtMap })), 1, 0.6, true)
    )
  )
  skirt.position.y = tower.deck + skirtH / 2
  const molding = add(
    new THREE.Mesh(
      new THREE.CylinderGeometry(tower.foot + 1.5 * P, tower.foot + 1.5 * P, T, 48),
      weather(banded(lambert({ color: p.snow ? SNOW : p.coping })), 1, 0.5, true)
    )
  )
  molding.position.y = tower.base - T / 2

  // ── 塔身：红白相间，窗沿楼梯往上；朝镜头这面错落四扇，背面两扇，门廊挡着的往旁边让 ──
  const bodyH = tower.neck - tower.base
  const BW = Math.round(around(tower.foot)),
    BH = Math.round(bodyH / T)
  const nb = p.bands.length
  const col = (angle: number) => Math.round(((angle / (2 * Math.PI)) % 1) * BW + BW) % BW
  const clear = (angle: number, band: number) => {
    const off = Math.atan2(Math.sin(angle - toward), Math.cos(angle - toward))
    return band === 1 && Math.abs(off) < 0.7 ? toward + Math.sign(off || 1) * 0.9 : angle
  }
  const windows = (
    [
      [-0.42, 1],
      [0.46, 2],
      [-0.36, 3],
      [0.3, 4],
      [Math.PI - 0.4, 2],
      [Math.PI + 0.35, 4],
    ] as const
  )
    .filter(([, band]) => band < nb)
    .map(
      ([angle, band]) =>
        [col(clear(angle, band)), Math.round(((band + 0.5) * BH) / nb)] as [number, number]
    )
  const body = bodyPixmaps(p, BW, BH, windows, seed % 997)
  const bodyMat = weather(
    banded(
      lambert({
        map: texture(body.map.canvas()),
        emissiveMap: texture(body.glow.canvas()),
        emissive: new THREE.Color('#ffffff'),
        emissiveIntensity: 0,
      })
    ),
    0,
    0.5,
    true
  )
  out.glowing.push({ material: bodyMat })
  const bodyMesh = add(
    new THREE.Mesh(new THREE.CylinderGeometry(tower.top, tower.foot, bodyH, 48, 1, true), bodyMat)
  )
  bodyMesh.position.y = tower.base + bodyH / 2

  // ── 门廊：伸出塔身的一截方石墙，开拱门，顶上一个小山墙；门两边两盆花 ──
  porch()
  function porch() {
    const pw = 13 * P,
      ph = 14 * T,
      depth = 10 * P
    const r = porchFront - depth / 2
    const g = new THREE.Group()
    g.position.set(Math.sin(toward) * r, tower.deck, Math.cos(toward) * r)
    g.rotation.y = toward
    const sideMap = stoneSides.clone()
    sideMap.repeat.set(depth / P / 48, ph / T / 4)
    const side = weather(lambert({ map: sideMap }), 0, 0.5, true)
    const front = weather(lambert({ map: texture(portalPixmap(p).canvas()) }), 0, 0.5, true)
    const box = new THREE.Mesh(new THREE.BoxGeometry(pw, ph, depth), [
      side,
      side,
      coping,
      coping,
      front,
      side,
    ])
    box.position.y = ph / 2
    // 小山墙：前后两片三角用压顶石，两面坡铺瓦
    const rw = pw + 2 * P,
      rh = 4 * T,
      rd = depth + 1.5 * P
    const slopes = new Builder(),
      ends = new Builder()
    const L = Math.hypot(rw / 2, rh) / P
    for (const s of [-1, 1]) {
      const e0 = [(s * rw) / 2, ph, rd / 2],
        e1 = [(s * rw) / 2, ph, -rd / 2],
        r0 = [0, ph + rh, rd / 2],
        r1 = [0, ph + rh, -rd / 2]
      // 两面坡都朝外朝上：西坡 e0→r0→r1→e1，东坡反过来
      if (s < 0) slopes.quad(e0, r0, r1, e1, [0, 0], [0, L], [rd / P, L], [rd / P, 0])
      else slopes.quad(e0, e1, r1, r0, [0, 0], [rd / P, 0], [rd / P, L], [0, L])
    }
    for (const s of [1, -1]) {
      const z = (s * rd) / 2
      ends.tri(
        [(-s * rw) / 2, ph, z],
        [(s * rw) / 2, ph, z],
        [0, ph + rh, z],
        [0, 0],
        [rw / P, 0],
        [rw / P / 2, rh / T]
      )
    }
    const roof = new THREE.Mesh(
      slopes.geometry(),
      weather(lambert({ map: tile(tilePixmap(paint, p.snow)), side: THREE.DoubleSide }), 1, 0.6)
    )
    const gable = new THREE.Mesh(ends.geometry(), coping)
    for (const m of [box, roof, gable]) {
      m.castShadow = m.receiveShadow = true
      g.add(m)
    }
    if (p.snow) icicles(g, rw, ph, rd / 2)
    if (!p.snow && !p.ruined)
      for (const s of [-1, 1]) {
        const pot = new THREE.Mesh(
          new THREE.CylinderGeometry(1.7 * P, 1.2 * P, 2 * T, 10),
          banded(lambert({ color: '#b5643e' }))
        )
        pot.position.set(s * (pw / 2 + 2.6 * P), T, depth / 2 - 1.5 * P)
        const bloom = new THREE.Mesh(
          new THREE.SphereGeometry(2.2 * P, 10, 6),
          weather(banded(lambert({ map: wrapped(bloomPixmap(house.flowers, seed + s)) })), 1, 0.4)
        )
        bloom.scale.y = 0.85
        bloom.position.set(s * (pw / 2 + 2.6 * P), 2 * T + 1.2 * P, depth / 2 - 1.5 * P)
        for (const m of [pot, bloom]) {
          m.castShadow = m.receiveShadow = true
          g.add(m)
        }
      }
    group.add(g)
  }

  // ── 牛腿和瞭望台 ──
  const corbelR = tower.top + 3 * P
  const corbels = add(
    new THREE.Mesh(
      new THREE.CylinderGeometry(corbelR, tower.top, 3 * T, 48, 1, true),
      weather(
        banded(lambert({ map: wrapped(corbelPixmap(p, Math.round(around(corbelR)))) })),
        0,
        0.5
      )
    )
  )
  corbels.position.y = tower.neck + 1.5 * T
  // 废土：瞭望台塌了一角，栏杆跟着断
  const missing = p.ruined ? 0.45 * Math.PI : 0
  const gap0 = Math.PI * 0.85 + missing
  const slabSide = new Pixmap(8, 2, true).fill((_, j) => (j === 0 ? p.iron[2] : p.iron[1]))
  const slab = add(
    new THREE.Mesh(
      new THREE.CylinderGeometry(
        tower.rim,
        tower.rim,
        1.5 * T,
        48,
        1,
        false,
        gap0,
        2 * Math.PI - missing
      ),
      [
        weather(lambert({ map: wrapped(slabSide, around(tower.rim) / 8) }), 0, 0.5),
        weather(lambert({ color: p.snow ? SNOW : p.iron[1] }), 1, 0.6),
        lambert({ color: p.iron[0] }),
      ]
    )
  )
  slab.position.y = tower.gallery - 0.75 * T
  const railR = tower.rim - 0.5 * P
  const railMap = wrapped(railPixmap(p, Math.round(around(railR))))
  const rail = cutout(
    add(
      new THREE.Mesh(
        new THREE.CylinderGeometry(railR, railR, 4 * T, 64, 1, true, gap0, 2 * Math.PI - missing),
        weather(lambert({ map: railMap, alphaTest: 0.5, side: THREE.DoubleSide }), 0, 0.4)
      )
    ),
    railMap
  )
  rail.position.y = tower.gallery + 2 * T
  if (p.snow) {
    // 瞭望台檐下一圈冰柱
    const cones: THREE.BufferGeometry[] = []
    const n = Math.round(around(tower.rim) / 2.5)
    for (let k = 0; k < n; k++) {
      const len = (1 + hash(k, 0, 141) * 2.5) * T
      const cone = new THREE.ConeGeometry(0.7 * P, len, 4)
      cone.rotateX(Math.PI)
      const a = (k / n) * 2 * Math.PI,
        r = tower.rim - 0.6 * P
      cone.translate(Math.sin(a) * r, tower.gallery - 1.5 * T - len / 2, Math.cos(a) * r)
      cones.push(cone)
    }
    add(
      new THREE.Mesh(
        mergeGeometries(cones),
        lambert({ color: ICE, emissive: ICE, emissiveIntensity: 0.15 })
      )
    )
  }

  // ── 灯室 ──
  const pedestal = (height: number) => {
    const mesh = add(
      new THREE.Mesh(new THREE.CylinderGeometry(tower.lantern, tower.lantern, height, 20), [
        weather(
          banded(
            lambert({ map: wrapped(pedestalPixmap(p, Math.round(around(tower.lantern)), paint)) })
          ),
          0,
          0.5
        ),
        weather(lambert({ color: p.iron[1] }), 1, 0.5),
        lambert({ color: p.iron[0] }),
      ])
    )
    mesh.position.y = tower.gallery + height / 2
  }
  if (p.ruined) ruinedTop()
  else {
    pedestal(tower.glass[0] - tower.gallery)
    lantern()
  }

  function lantern() {
    const [g0, g1] = tower.glass
    const gh = g1 - g0,
      rows = Math.round(gh / T)
    const faces = 10,
      fw = Math.max(5, Math.round(around(tower.lantern) / faces))
    // 十边形，正对南边的是一面玻璃
    const prism = new THREE.CylinderGeometry(
      tower.lantern,
      tower.lantern,
      gh,
      faces,
      1,
      true,
      -Math.PI / faces
    )
    prism.translate(0, g0 + gh / 2, 0)
    // 透镜：立在灯室正中一个小铜座上
    const lr = tower.lantern * 0.45,
      lensH = 6 * T
    const lens = lensPixmaps()
    const lensMat = lambert({
      map: wrapped(lens.map, 2),
      emissiveMap: wrapped(lens.glow, 2),
      emissive: new THREE.Color('#fff0c8').multiplyScalar(2.4),
      emissiveIntensity: 0,
    })
    out.glowing.push({ material: lensMat, on: 0.02 })
    const brass = lambert({ color: '#b8913e' })
    const lensMesh = add(
      new THREE.Mesh(new THREE.CylinderGeometry(lr, lr, lensH, 16), [lensMat, brass, brass])
    )
    lensMesh.position.y = g0 + 1.2 * T + lensH / 2
    const stand = add(
      new THREE.Mesh(new THREE.CylinderGeometry(lr * 0.5, lr * 0.7, 1.2 * T, 10), brass)
    )
    stand.position.y = g0 + 0.6 * T
    // 铁框：镂空，投影也镂空
    const frameMap = wrapped(framePixmap(p, faces, fw, rows))
    cutout(
      add(
        new THREE.Mesh(prism, lambert({ map: frameMap, alphaTest: 0.5, side: THREE.DoubleSide }))
      ),
      frameMap
    )
    // 灯室里：隔着玻璃看见对面的内壁（只画背面，暗的）和正中的透镜；夜里内壁也映着暖光
    const room = lambert({
      color: '#26323a',
      side: THREE.BackSide,
      emissive: new THREE.Color('#ff9e48').multiplyScalar(0.55),
      emissiveIntensity: 0,
    })
    out.glowing.push({ material: room, on: 0.02 })
    add(new THREE.Mesh(prism.clone().scale(0.95, 1, 0.95), room), false)
    // 玻璃：朝外一层半透明，夜里透出暖光
    const glass = lambert({
      map: wrapped(glassPixmap(faces, fw, rows)),
      transparent: true,
      opacity: 0.32,
      depthWrite: false,
      emissive: new THREE.Color('#ffb85a').multiplyScalar(0.75),
      emissiveIntensity: 0,
    })
    out.glowing.push({ material: glass, on: 0.02 })
    add(new THREE.Mesh(prism.clone().scale(0.985, 1, 0.985), glass), false).renderOrder = 2
    // 檐、圆顶、通风球、避雷针和风向标
    const eave = add(
      new THREE.Mesh(
        new THREE.CylinderGeometry(tower.lantern + 1.5 * P, tower.lantern + 1.5 * P, T, 20),
        lambert({ color: p.iron[1] })
      )
    )
    eave.position.y = g1 + T / 2
    const domeR = tower.lantern + P,
      domeH = tower.dome - g1 - T
    const domeGeo = new THREE.SphereGeometry(domeR, 24, 8, 0, 2 * Math.PI, 0, Math.PI / 2)
    domeGeo.scale(1, domeH / domeR, 1)
    const dome = add(
      new THREE.Mesh(
        domeGeo,
        weather(
          banded(lambert({ map: wrapped(domePixmap(p, Math.round(around(domeR)), paint)) })),
          1,
          0.6
        )
      )
    )
    dome.position.y = g1 + T
    const iron = banded(lambert({ color: p.iron[1] }))
    const neck = add(new THREE.Mesh(new THREE.CylinderGeometry(0.9 * P, 1.4 * P, 1.2 * T, 8), iron))
    neck.position.y = tower.dome + 0.3 * T
    const ball = add(new THREE.Mesh(new THREE.SphereGeometry(2 * P, 12, 8), iron))
    ball.position.y = tower.dome + 0.9 * T + 2 * P
    const gold = lambert({ color: '#d4a84a' })
    const rodH = tower.height - tower.dome - 2 * T
    const rod = add(new THREE.Mesh(new THREE.CylinderGeometry(0.3 * P, 0.45 * P, rodH, 6), gold))
    rod.position.y = tower.height - rodH / 2
    // 风向标：一支箭，箭头朝西、箭尾两片羽
    const vane = new Pixmap(10, 3)
    vane.stamp(0, 0, [' g      gg', 'gggggggggg', ' g      gg'], { g: '#d4a84a' })
    const vaneMap = texture(vane.canvas())
    const arrow = cutout(
      add(
        new THREE.Mesh(
          new THREE.PlaneGeometry(10 * P, 3 * T),
          lambert({ map: vaneMap, alphaTest: 0.5, side: THREE.DoubleSide })
        )
      ),
      vaneMap
    )
    arrow.position.y = tower.height - 1.6 * T
    // 光束和灯室的光晕
    const beam = beams(lr)
    beam.position.y = lensMesh.position.y
    group.add(beam)
    out.beam = beam
    out.lamp = new THREE.Vector3(0, lensMesh.position.y, 0)
    out.glows.push({ at: new THREE.Vector3(0, lensMesh.position.y, 0), size: 56 * P, on: 0.02 })
  }

  /** 废土：灯室没了，底座只剩一圈断墙和几根扭了的铁框，瞭望台上一盆火，白天也烧着、冒着烟 */
  function ruinedTop() {
    pedestal(2 * T)
    const chunks: THREE.BufferGeometry[] = []
    for (let k = 0; k < 9; k++) {
      const a = (k / 9) * 2 * Math.PI + hash(k, 1, 151) * 0.3
      const hgt = (1 + hash(k, 2, 151) * 4) * T
      const box = new THREE.BoxGeometry(tower.lantern * 0.55, hgt, 1.6 * P)
      box.rotateY(a)
      box.translate(
        Math.sin(a) * tower.lantern * 0.85,
        tower.gallery + 2 * T + hgt / 2,
        Math.cos(a) * tower.lantern * 0.85
      )
      chunks.push(box)
    }
    add(
      new THREE.Mesh(
        mergeGeometries(chunks),
        weather(lambert({ map: tile(ashlar(p, 7)) }), 1, 0.5, true)
      )
    )
    const bars: THREE.BufferGeometry[] = []
    for (let k = 0; k < 4; k++) {
      const a = (k / 4) * 2 * Math.PI + 0.4
      const len = (4 + hash(k, 3, 152) * 5) * T
      const stub = new THREE.BoxGeometry(0.7 * P, len, 0.7 * P)
      stub.translate(0, len / 2, 0)
      stub.rotateX((hash(k, 4, 152) - 0.5) * 0.9)
      stub.rotateZ((hash(k, 5, 152) - 0.5) * 0.9)
      stub.translate(
        Math.sin(a) * tower.lantern,
        tower.gallery + 2 * T,
        Math.cos(a) * tower.lantern
      )
      bars.push(stub)
    }
    add(new THREE.Mesh(mergeGeometries(bars), lambert({ color: p.iron[1] })))
    // 火盆：铁盆，里面几簇火苗
    const bowl = add(
      new THREE.Mesh(
        new THREE.CylinderGeometry(3 * P, 2 * P, 2 * T, 10),
        banded(lambert({ color: '#3a2a20' }))
      )
    )
    bowl.position.y = tower.gallery + 3 * T
    const fire = lambert({
      color: '#ff9a3a',
      emissive: new THREE.Color('#ff7a2a'),
      emissiveIntensity: 0.3,
    })
    out.burning.push(fire)
    const flames: THREE.BufferGeometry[] = []
    for (let k = 0; k < 5; k++) {
      const a = (k / 5) * 2 * Math.PI
      const fh = (2 + hash(k, 6, 153) * 2) * T
      const flame = new THREE.ConeGeometry(1.2 * P, fh, 5)
      flame.translate(Math.sin(a) * 1.3 * P, tower.gallery + 4 * T + fh / 2, Math.cos(a) * 1.3 * P)
      flames.push(flame)
    }
    const core = new THREE.ConeGeometry(1.7 * P, 5 * T, 6)
    core.translate(0, tower.gallery + 6.5 * T, 0)
    flames.push(core)
    add(new THREE.Mesh(mergeGeometries(flames), fire), false)
    out.glows.push({ at: new THREE.Vector3(0, tower.gallery + 6 * T, 0), size: 44 * P, on: 0.02 })
    out.smoke.push(new THREE.Vector3(0, tower.gallery + 9 * T, 0))
  }

  /** 门廊山墙两侧檐下一排冰柱 */
  function icicles(g: THREE.Group, width: number, y: number, z: number) {
    const cones: THREE.BufferGeometry[] = []
    for (let i = -width / 2 + P; i < width / 2; i += 1.6 * P) {
      const len = (0.8 + hash(Math.round(i), 7, 161) * 2) * T
      const cone = new THREE.ConeGeometry(0.6 * P, len, 4)
      cone.rotateX(Math.PI)
      cone.translate(i, y - len / 2, z)
      cones.push(cone)
    }
    g.add(new THREE.Mesh(mergeGeometries(cones), lambert({ color: ICE })))
  }

  // ── 台上的东西：信号旗杆、雾钟、木桶，避开塔、台阶到塔门的道和彼此 ──
  const placed: { at: Pt; r: number }[] = []
  const free = ([x, z]: Pt, r: number) => {
    if (Math.abs(x) > X - 4 * P - r || Math.abs(z) > Z - 4 * P - r) return false
    if (Math.abs(x) + Math.abs(z) > X + Z - chamfer - 4 * P - r * 1.5) return false
    if (Math.hypot(x, z) < tower.reach + r + 2 * P) return false
    if (segmentDistance([x, z], path) < 4 * P + r) return false
    if (segmentDistance([x, z], [mouth, stairTop]) < stair.width / 2 + r + P) return false
    return placed.every((q) => Math.hypot(x - q.at[0], z - q.at[1]) > q.r + r + 2 * P)
  }
  const spot = (r: number, score: (x: number, z: number) => number) => {
    let best: Pt | undefined,
      value = -Infinity
    for (let x = -X; x <= X; x += P)
      for (let z = -Z; z <= Z; z += P) {
        if (!free([x, z], r)) continue
        const v = score(x, z)
        if (v > value) ((value = v), (best = [x, z]))
      }
    if (best) placed.push({ at: best, r })
    return best
  }
  const far = (x: number, z: number) => segmentDistance([x, z], path) / P
  const sea: Pt = [-Math.sin(toward), -Math.cos(toward)]
  const mast = p.ruined
    ? undefined
    : spot(3 * P, (x, z) => Math.abs(x) - Math.abs(z) * 0.8 + far(x, z) * 0.3)
  const bell = p.ruined
    ? undefined
    : spot(
        5 * P,
        (x, z) =>
          -Math.abs(z) * 0.6 +
          Math.abs(x) * 0.4 +
          (mast && Math.sign(x) !== Math.sign(mast[0]) ? 30 : 0)
      )
  // 望远镜放在朝海的那边（塔门的反方向），靠近栏墙
  const scope = p.ruined
    ? undefined
    : spot(
        2.5 * P,
        (x, z) => (x * sea[0] + z * sea[1]) / P - (Math.abs(x * sea[1] - z * sea[0]) / P) * 0.15
      )
  const barrels = spot(5 * P, (x, z) => z * 0.8 + Math.abs(x) * 0.2 + far(x, z) * 0.2)
  const pile = p.ruined ? spot(6 * P, (x, z) => -z * 0.3 + far(x, z) * 0.3) : undefined
  /** 台上的东西摆到一层上：旗杆太高，只在剖开前立着 */
  const furnish = (stage: Stage, ring: number) => {
    if (bell) fogBell(bell, stage)
    if (scope) telescope(scope, Math.atan2(sea[0], sea[1]), stage)
    if (barrels) cargo(barrels, stage)
    if (pile) rubble(pile, stage)
    if (!p.ruined) lifeRing(stage, ring)
  }
  if (mast) signalMast(mast)
  furnish({ y: tower.deck, add }, tower.deck + 0.2 * T)

  /** 信号旗杆：白漆木杆、一道横桁，两头各垂一串信号旗，杆顶一面长三角旗 */
  function signalMast([x, z]: Pt) {
    const poleH = 26 * T
    const white = weather(lambert({ color: '#e8e2d4' }), 1, 0.4)
    const pole = add(new THREE.Mesh(new THREE.BoxGeometry(1.2 * P, poleH, 1.2 * P), white))
    pole.position.set(x, tower.deck + poleH / 2, z)
    const base = add(new THREE.Mesh(new THREE.BoxGeometry(3.6 * P, T, 3.6 * P), coping))
    base.position.set(x, tower.deck + T / 2, z)
    const yardY = tower.deck + poleH - 5 * T
    const yard = add(new THREE.Mesh(new THREE.BoxGeometry(14 * P, 0.7 * T, 0.7 * P), white))
    yard.position.set(x, yardY, z)
    const knob = add(
      new THREE.Mesh(new THREE.SphereGeometry(1 * P, 8, 6), lambert({ color: '#d4a84a' }))
    )
    knob.position.set(x, tower.deck + poleH + 0.5 * T, z)
    const line = lambert({ color: '#4a4036' })
    let k = 0
    for (const s of [-1, 1]) {
      const lx = x + s * 6.5 * P
      const drop = 13 * T
      const rope = add(new THREE.Mesh(new THREE.BoxGeometry(0.25 * P, drop, 0.25 * P), line), false)
      rope.position.set(lx, yardY - drop / 2, z)
      for (let f = 0; f < 3; f++, k++)
        flag(lx, yardY - (2 + f * 3.8) * T, z + 0.2 * P, FLAGS[(seed + k) % FLAGS.length])
    }
    // 杆顶的长三角旗
    const pennant = new Pixmap(10, 3).fill((i, j) =>
      Math.abs(j - 1) * 10 <= 10 - i ? (i < 3 ? '#f4f1ea' : '#c8453b') : null
    )
    const pm = texture(pennant.canvas())
    const cloth = lambert({ map: pm, alphaTest: 0.5, side: THREE.DoubleSide })
    out.weathered.push({ material: cloth, snow: 0, wet: 0.3, sway: true })
    const geo = new THREE.PlaneGeometry(10 * P, 3 * T)
    geo.translate(5 * P, 0, 0)
    const pen = cutout(add(new THREE.Mesh(geo, cloth)), pm)
    pen.position.set(x + 0.6 * P, tower.deck + poleH - 1.5 * T, z)
  }

  function flag(x: number, y: number, z: number, pattern: (i: number, j: number) => string) {
    const cloth = lambert({
      map: texture(new Pixmap(4, 4).fill(pattern).canvas()),
      side: THREE.DoubleSide,
    })
    out.weathered.push({ material: cloth, snow: 0, wet: 0.3, sway: true })
    const mesh = add(new THREE.Mesh(new THREE.PlaneGeometry(3.2 * P, 3.2 * T), cloth))
    mesh.position.set(x, y, z)
  }

  /** 雾钟：两根木柱一道横梁、一个小坡顶，挂一口铜钟，钟下垂一根绳 */
  function fogBell([x, z]: Pt, { y, add }: Stage) {
    const wood = weather(lambert({ color: '#6b4b34' }), 1, 0.6)
    const postH = 9 * T
    for (const s of [-1, 1]) {
      const post = add(new THREE.Mesh(new THREE.BoxGeometry(1.2 * P, postH, 1.2 * P), wood))
      post.position.set(x + s * 3.4 * P, y + postH / 2, z)
    }
    const beam = add(new THREE.Mesh(new THREE.BoxGeometry(8.6 * P, T, 1.6 * P), wood))
    beam.position.set(x, y + postH + 0.5 * T, z)
    const shingle = weather(lambert({ color: p.snow ? SNOW : paint[1] }), 1, 0.6)
    for (const s of [-1, 1]) {
      const plank = add(new THREE.Mesh(new THREE.BoxGeometry(10.5 * P, 0.5 * T, 3 * P), shingle))
      plank.position.set(x, y + postH + 1.9 * T, z + s * 1.2 * P)
      plank.rotation.x = s * 0.5
    }
    const profile = [
      [0, 0],
      [2.4, 0],
      [2.2, 0.4],
      [1.8, 1.1],
      [1.5, 2.4],
      [1.1, 3],
      [0, 3.2],
    ].map(([r, h]) => new THREE.Vector2(r * P, h * T))
    const bell = add(
      new THREE.Mesh(
        new THREE.LatheGeometry(profile, 12),
        banded(lambert({ color: '#b08a3a', side: THREE.DoubleSide }))
      )
    )
    bell.position.set(x, y + postH - 3.2 * T, z)
    const rope = add(
      new THREE.Mesh(
        new THREE.BoxGeometry(0.3 * P, 2.6 * T, 0.3 * P),
        lambert({ color: '#c8b48a' })
      ),
      false
    )
    rope.position.set(x, y + postH - 4.4 * T, z)
  }

  /** 铜望远镜：木三脚架上一支铜筒，朝着海微微抬头 */
  function telescope([x, z]: Pt, facing: number, { y, add }: Stage) {
    const top = new THREE.Vector3(x, y + 4.2 * T, z)
    const legs = [0, 1, 2].map((k) => {
      const a = facing + Math.PI / 3 + (k * 2 * Math.PI) / 3
      return rod(
        new THREE.Vector3(x + Math.sin(a) * 2 * P, y, z + Math.cos(a) * 2 * P),
        top,
        0.3 * P
      )
    })
    add(new THREE.Mesh(mergeGeometries(legs), weather(lambert({ color: '#6b4b34' }), 1, 0.5)))
    const ahead = new THREE.Vector3(Math.sin(facing), 0.22, Math.cos(facing)).normalize()
    add(
      new THREE.Mesh(
        rod(
          top
            .clone()
            .addScaledVector(ahead, -2.6 * P)
            .setY(top.y + 0.4 * T),
          top
            .clone()
            .addScaledVector(ahead, 3.8 * P)
            .setY(top.y + 0.4 * T + 0.22 * 6.4 * P),
          0.55 * P,
          0.85 * P
        ),
        banded(lambert({ color: '#c9a04e' }))
      )
    )
  }

  /** 几只木桶，完好的灯塔再加一只木箱、一盘缆绳 */
  function cargo([x, z]: Pt, { y, add }: Stage) {
    const barrelH = 4 * T
    const staves = weather(
      banded(lambert({ map: wrapped(barrelPixmap(p, Math.round(barrelH / T))) })),
      1,
      0.5
    )
    const lid = weather(
      lambert({ color: p.snow ? SNOW : p.ruined ? '#5e3c28' : '#7a583a' }),
      1,
      0.5
    )
    ;[
      [-2.2, -1],
      [2.4, -1.6],
      [0.2, 2.2],
    ].forEach(([dx, dz], k) => {
      const tall = barrelH * (k === 2 ? 0.8 : 1)
      const b = add(
        new THREE.Mesh(new THREE.CylinderGeometry(2 * P, 2 * P, tall, 12), [staves, lid, lid])
      )
      b.position.set(x + dx * P, y + tall / 2, z + dz * P)
      b.rotation.y = k
    })
    if (p.ruined) return
    const crate = add(
      new THREE.Mesh(
        new THREE.BoxGeometry(4 * P, 3 * T, 4 * P),
        weather(
          lambert({
            map: tile(
              new Pixmap(4, 4).fill((i, j) => (i === 0 || j === 0 ? '#6b4b34' : '#9a7a52'))
            ),
          }),
          1,
          0.5
        )
      )
    )
    crate.position.set(x + 4.8 * P, y + 1.5 * T, z + 1.8 * P)
    crate.rotation.y = 0.3
    const coil = add(
      new THREE.Mesh(
        new THREE.TorusGeometry(1.7 * P, 0.65 * P, 6, 14),
        weather(lambert({ color: '#c8b48a' }), 1, 0.4)
      )
    )
    coil.rotation.x = Math.PI / 2
    coil.position.set(x - 4.6 * P, y + 0.6 * P, z + 2.6 * P)
  }

  /** 碎砖和锈铁皮堆 */
  function rubble([x, z]: Pt, { y, add }: Stage) {
    const bits: THREE.BufferGeometry[] = []
    for (let k = 0; k < 8; k++) {
      const s = (1.2 + hash(k, 8, 171) * 2) * P
      const box = new THREE.BoxGeometry(s * 1.4, s * 0.7, s)
      box.rotateY(hash(k, 9, 171) * Math.PI)
      box.rotateZ((hash(k, 10, 171) - 0.5) * 0.6)
      box.translate(
        x + (hash(k, 11, 171) - 0.5) * 7 * P,
        y + s * 0.3,
        z + (hash(k, 12, 171) - 0.5) * 5 * P
      )
      bits.push(box)
    }
    add(
      new THREE.Mesh(mergeGeometries(bits), weather(lambert({ map: tile(ashlar(p, 13)) }), 1, 0.5))
    )
  }

  /** 救生圈：挂在朝南那面栏墙外，避开台阶口，红白四段；height 是圈心的高度 */
  function lifeRing({ add }: Stage, height: number) {
    const south = notch.inward[1] === -1
    const x = (south && mouth[0] < 0 ? 1 : -1) * X * 0.42
    const ring = add(
      new THREE.Mesh(
        new THREE.TorusGeometry(2.1 * P, 0.7 * P, 6, 16),
        weather(
          banded(
            lambert({
              map: wrapped(new Pixmap(8, 1, true).fill((i) => (i % 4 < 2 ? '#d0453a' : '#f2eee6'))),
            })
          ),
          0,
          0.4
        )
      )
    )
    ring.position.set(x, height, Z + 0.9 * P)
  }

  // ── 掀开屋顶后：剖开的灯塔 ──
  out.room = cutaway()

  /** 剖开的灯塔：屋里的人站在地面上，所以台子落到地面，只沿台子边留一圈矮石边、台阶口留缺口；
   *  塔从中间剖开，留一圈塔墙，朝南（镜头）那面矮、背面高，按石层一阶一阶截断，看得见墙厚；
   *  外面还是红白漆，里面刷白、开两扇深窗、挂着海图船舵；沿墙一圈螺旋石阶，地上嵌一个罗盘；
   *  塔墙在门那个方向开门洞。台上矮的东西（雾钟、木桶、望远镜、救生圈）照原样摆着，旗杆不立 */
  function cutaway() {
    const g = new THREE.Group()
    g.visible = false
    const glowing: THREE.Material[] = []
    const put = (mesh: THREE.Mesh, shadow = true) => {
      mesh.castShadow = mesh.receiveShadow = shadow
      g.add(mesh)
      return mesh
    }
    const back = interiorTexels(house) * T,
      low = 4 * T
    const rOut = tower.foot,
      rIn = tower.foot - 3 * P
    // 地面
    const inPolygon = (x: number, z: number) => {
      let inside = false
      for (let k = 0, m = outline.length - 1; k < outline.length; m = k++) {
        const [ax, az] = outline[k],
          [bx, bz] = outline[m]
        if (az > z !== bz > z && x < ((bx - ax) * (z - az)) / (bz - az) + ax) inside = !inside
      }
      return inside || inNotch([x, z])
    }
    const floor = lambert({
      map: texture(floorCanvas(p, w, h, X, Z, rIn, rOut, inPolygon, path)),
    })
    out.grounds.push(floor)
    const plane = new THREE.Mesh(new THREE.PlaneGeometry(w, h), floor)
    plane.rotation.x = -Math.PI / 2
    plane.position.y = 0.6
    put(plane, false).receiveShadow = true
    // 台子边：外面方石、顶上压顶石，台阶口不砌
    const rimSides = new Builder(),
      rimTops = new Builder()
    outline.forEach((a, k) => {
      const b = outline[(k + 1) % outline.length]
      if (!(inNotch(a) && inNotch(b))) bar(rimSides, rimTops, a, b, 2 * P, 0, 3 * T)
    })
    const rimStone = lambert({ map: tile(ashlar(p, seed % 97)) })
    out.walls.push(rimStone)
    put(new THREE.Mesh(rimSides.geometry(), rimStone))
    put(new THREE.Mesh(rimTops.geometry(), lambert({ map: tile(copingTile(p)) })))
    // 塔墙：前低后高，高度一层石（两格）一阶
    const height = (a: number) =>
      Math.max(low, Math.floor((low + ((back - low) * (1 - Math.cos(a))) / 2) / (2 * T)) * 2 * T)
    const gap = [toward, (6.5 * P) / rOut] as const
    const ring = ringWall(rIn, rOut, height, back, gap)
    const rows = Math.round(back / T)
    // 外面：最下两格石基，往上红白一道四格交替（比真塔身的条纹密，剖开的矮墙上也认得出是灯塔）
    const stub = (y: number) =>
      y < 2 ? p.stone[1] : p.bands[1 + (Math.floor((y - 2) / 4) % (p.bands.length - 1))]
    const outerMap = bodyPixmaps(p, Math.round(around(rOut)), rows, [], seed % 997, stub).map
    const outerMat = banded(lambert({ map: texture(outerMap.canvas()) }))
    out.walls.push(outerMat)
    put(new THREE.Mesh(ring.outer, outerMat))
    // 螺旋石阶贴着墙往上（让开门洞），背面留给一扇深窗和一样陈设
    const IW = Math.round(around(rIn))
    const col = (a: number) => Math.round((1 - ((((a / (2 * Math.PI)) % 1) + 1) % 1)) * IW) % IW
    const apart = (a: number, b: number) => Math.abs(Math.atan2(Math.sin(a - b), Math.cos(a - b)))
    const clearOfDoor = (a: number) => apart(a, toward) > gap[1] + 0.2
    const steps = 6,
      turn = 0.3,
      rise = 1.8 * T
    // 从侧面起步、一级级往背面爬（东边逆时针、西边顺时针），越高的一级越靠背面的高墙；背面正中空着开窗
    let stairs: number[] = []
    let best = -Infinity
    for (let k = 0; k < 72; k++)
      for (const dir of [1, -1]) {
        const a0 = (k / 72) * 2 * Math.PI
        const arc = Array.from({ length: steps }, (_, i) => a0 + dir * i * turn)
        if (!arc.every((a) => clearOfDoor(a) && apart(a, Math.PI) > 0.6)) continue
        const score = arc.reduce((sum, a, i) => sum + (i + 1) * (1 - Math.cos(a)), 0)
        if (score > best) ((best = score), (stairs = arc))
      }
    // 窗和陈设：从背面正中往两边一点点找，离门洞、石阶和彼此都够远（half 是它在墙上占的半个角度）
    const hung: [number, number][] = []
    const place = (half: number) => {
      for (let i = 0; i <= 16; i++) {
        const a = Math.PI + (i % 2 ? -1 : 1) * Math.ceil(i / 2) * 0.12
        if (apart(a, toward) < gap[1] + half) continue
        if (stairs.some((b) => apart(a, b) < half + turn / 2)) continue
        if (hung.some(([b, h]) => apart(a, b) < half + h)) continue
        hung.push([a, half])
        return [col(a)]
      }
      return []
    }
    const windows = place(0.34)
    const decor = place(0.63)
    const plaster = plasterPixmaps(p, house.interior, IW, rows, windows, decor, seed)
    const innerMat = lambert({
      map: texture(plaster.map.canvas()),
      emissiveMap: texture(plaster.glow.canvas()),
      emissive: new THREE.Color('#ffffff'),
      emissiveIntensity: 0,
    })
    glowing.push(innerMat)
    out.walls.push(innerMat)
    put(new THREE.Mesh(ring.inner, innerMat))
    put(
      new THREE.Mesh(
        ring.cut,
        lambert({ color: p.snow ? '#e6ecf1' : dark(p.stone[1], 0.08), side: THREE.DoubleSide })
      )
    )
    // 石阶：比墙矮的才画（剖掉的不画）
    const treads: THREE.BufferGeometry[] = []
    const depth = 4.5 * P
    stairs.forEach((a, k) => {
      const top = (k + 1) * rise
      if (top > height(a) - 0.5 * T) return
      const tread = new THREE.BoxGeometry(rIn * turn * 1.08, rise, depth)
      tread.translate(0, top - rise / 2, rIn - depth / 2)
      tread.rotateY(a)
      treads.push(tread)
    })
    if (treads.length)
      put(
        new THREE.Mesh(
          mergeGeometries(treads),
          lambert({ color: p.snow ? '#d9dde2' : light(p.stone[0], 0.06) })
        )
      )
    furnish({ y: 0, add: put }, 1.8 * T)
    return { group: g, glowing }
  }

  return out
}
