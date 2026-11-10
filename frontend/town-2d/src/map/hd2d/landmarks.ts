import type { Atlas } from 'town-shared/mapDocument'
import { PIXEL } from '../grid'
import { footprint, placer, type Dock } from '../pixel/island'
import { hash, mixHex } from '../pixel/noise'
import { boatModel } from './boats'
import type { FountainLook } from './fountain'
import type { Kit } from './propKit'
import { stall } from './stalls'
import { bench, deckChair, parasol, planter, reeds, rock, signpost, telescope } from './parkPieces'
import {
  BIG_TREE_HALOS,
  bigTree,
  blossomTree,
  cascade,
  cedar,
  deer,
  lilyPads,
  stoneLantern,
} from './groveArt'
import { sprite, stone } from './sprite'

// 户外地点的立体标志物：摩天轮、旋转亭、方尖碑、神庙遗迹这些地标（弧形阶台、喷泉是立体搭的，见 stand.ts、fountain.ts），
// 以及市场的摊位、港口栈桥边的船、花园的花拱门、公园的凉亭。都是竖在地上的像素立牌，
// 和树、路灯一样按俯角转向镜头；光从左上来，左边亮右边暗。一个贴图像素对应一个地图像素。

/** 立牌照亮脚下一圈地面（火盆、霓虹招牌）：颜色、照多远（地图单位）、亮度倍数，
 *  on 是天黑到什么程度亮起来（0～1，同路灯） */
export interface StandeeLight {
  color: string
  reach: number
  power?: number
  on?: number
}

/** 逐帧动画的立牌：canvas 是横排 frames 帧的图集，每秒 fps 帧循环播放 */
export interface Flipbook {
  canvas: HTMLCanvasElement
  /** 自发光图集（和 canvas 一样大）：白天微亮，夜里像打了灯 */
  glow?: HTMLCanvasElement
  frames: number
  fps: number
  light?: StandeeLight
  /** 花木：随风摆；高过 60 个贴图像素的大树，脚下的灯光越往上越暗（树顶留在月色里） */
  plant?: boolean
  /** 灯：自发光的部分天黑才亮（不给时白天也微亮） */
  lamp?: boolean
  /** 在这些点上加一团光晕：[横向偏移（贴图像素）, 离地多少贴图像素, 光晕大小（地图单位）] */
  halos?: [number, number, number][]
  /** 落花：花瓣从花冠里飘下来（见 petals.ts）。r 是花冠半径，low～high 是花冠离地多高（地图单位），count 片；
   *  afloat 是身边的水面上再浮多少片 */
  sheds?: { r: number; low: number; high: number; count: number; afloat?: number }
  /** 入夜身边聚多少只萤火虫，散在多大半径里（地图单位） */
  swarm?: { r: number; count: number }
}

export interface LandmarkSprite {
  /** 立牌底边中点（地图坐标） */
  x: number
  y: number
  canvas: HTMLCanvasElement
  /** 逐帧动画的立牌（见 Flipbook）：canvas 是图集，另带帧数、帧率和自发光图集 */
  frames?: number
  fps?: number
  glow?: HTMLCanvasElement
  light?: StandeeLight
  /** 以下几项同 Flipbook */
  plant?: boolean
  lamp?: boolean
  halos?: [number, number, number][]
  sheds?: Flipbook['sheds']
  swarm?: Flipbook['swarm']
  /** 蹲到这栋房子（或只看不进的楼）的墙顶上 */
  on?: string
}

/** 搭成立体的标志物（摊棚、船）：用道具的积木搭（propKit.ts），原点在落点的地面上，正面朝南。
 *  angle 是它的东（积木的 x 轴）在地图上转到哪个方向（弧度，地图 x 朝东、y 朝南）；
 *  float 是浮在水上随波起伏（船），roll 是绕积木的 x 轴歪多少（搁浅的船）。进场景见 landmarkModels.ts */
export interface LandmarkModel {
  build: (k: Kit) => void
  angle?: number
  float?: boolean
  roll?: number
}

/** 一件标志物：立牌、逐帧动画的立牌，或者搭成立体的 */
export type LandmarkArt = HTMLCanvasElement | Flipbook | LandmarkModel

/** 摆好位置的立体标志物（地图坐标） */
export interface PlacedModel {
  x: number
  y: number
  model: LandmarkModel
}

const isModel = (art: LandmarkArt): art is LandmarkModel => 'build' in art

/** 一种风格的户外立牌：各类地点放什么、栈桥边停什么船、桥上堆什么、野地和外圈散落什么 */
export interface LandmarkSet {
  /** 一种户外地点在自己的区域里放哪些立牌：[贴图或逐帧动画, 相对区域中心的偏移（地图像素）, 能不能立在水上]。
   *  按区域的 kind 挑，区域指定了 landmark 就按它挑。落到水上的一般拉回岸上，第四项为 true 的照立
   *  （冰钓小屋立在冻住的海上） */
  plans: Record<string, (seed: number) => [LandmarkArt, number, number, boolean?][]>
  /** 栈桥边的船（搭成立体的，见 boats.ts）：kind 0、1 是大船，2 是小舢板；没有这种船时给 null */
  boat: (seed: number, kind: number) => LandmarkModel | null
  /** 栈桥上堆的杂物（木箱、木桶、缆绳、鱼篓） */
  dockGoods: (seed: number) => HTMLCanvasElement
  /** 公园（没有 decor、没指定地标的 park 区域）正中的凉亭搭成立体的（见 pixel/pavilions.ts），
   *  这些区域不再立 plans.park 的立牌；地图按坐标立的 park 立牌照旧（旧地图里的） */
  pavilion?: boolean
  /** 喷泉区域的喷泉是立体的（见 fountain.ts），这里选样子：流水、冻住，还是干涸 */
  fountain: FountainLook
  /** 散落物：每个地图像素放一件的概率，野地（land）和外圈（outer）分开算；sprite 给出一件的贴图 */
  scatter?: {
    land: number
    outer: number
    sprite(where: 'land' | 'outer', seed: number): HTMLCanvasElement
  }
}

/** broken 为 true 时是废弃的：吊厢掉了一半，轮缘断一截，轮辐缺两根 */
export function ferrisWheel(broken = false) {
  return sprite(64, 78, ({ px, rect, line }) => {
    const cx = 32,
      cy = 30,
      r = 26
    // 支架：两条斜腿、一道横撑、底座
    for (const d of [-1, 1]) {
      line(cx, cy, cx + d * 15, 74, '#6c7280')
      line(cx + d, cy, cx + d * 16, 74, d < 0 ? '#9aa0ac' : '#555b68')
    }
    line(cx - 9, 56, cx + 9, 56, '#6c7280')
    rect(10, 74, 44, 4, '#8a7a66')
    rect(10, 74, 44, 1, '#a8987e')
    rect(10, 77, 44, 1, '#5e5142')
    // 轮辐和两圈轮缘
    for (let k = 0; k < 12; k++) {
      if (broken && (k === 3 || k === 8)) continue
      const a = (k / 12) * Math.PI * 2
      line(cx, cy, cx + Math.cos(a) * r, cy + Math.sin(a) * r, '#a3a9b4')
    }
    for (let k = 0; k < 360; k++) {
      if (broken && k > 60 && k < 88) continue
      const a = (k / 360) * Math.PI * 2
      const lit = Math.cos(a + 2.4) > 0
      px(cx + Math.cos(a) * r, cy + Math.sin(a) * r, lit ? '#e6e9ee' : '#8d939e')
      px(cx + Math.cos(a) * (r - 2), cy + Math.sin(a) * (r - 2), '#7a808c')
    }
    rect(cx - 3, cy - 3, 6, 6, '#5a606c')
    rect(cx - 2, cy - 2, 2, 2, '#9aa0ac')
    // 吊厢挂在轮缘外面，四种颜色轮流
    const cabins = ['#e05a4a', '#f0c040', '#4a9ad8', '#5ab870']
    for (let k = 0; k < 12; k++) {
      if (broken && hash(k, 5, 11) < 0.5) continue
      const a = (k / 12) * Math.PI * 2 + 0.26
      const x = Math.round(cx + Math.cos(a) * r),
        y = Math.round(cy + Math.sin(a) * r)
      const c = cabins[k % 4]
      px(x, y + 1, '#555b68')
      rect(x - 2, y + 2, 5, 4, c)
      rect(x - 2, y + 2, 5, 1, mixHex(c, '#ffffff', 0.35))
      rect(x - 1, y + 3, 3, 1, '#dff0f8')
      rect(x + 2, y + 3, 1, 3, mixHex(c, '#2a2230', 0.3))
    }
  })
}

/** torn 为 true 时顶篷破了洞 */
export function carousel(torn = false) {
  return sprite(50, 48, ({ px, rect, line }) => {
    // 尖顶：红白相间的扇面，顶上一面小旗
    line(25, 0, 25, 3, '#6a5040')
    rect(26, 0, 4, 2, '#e05a4a')
    for (let y = 4; y <= 18; y++) {
      const half = Math.round(((y - 3) / 15) * 23)
      for (let x = 25 - half; x <= 25 + half; x++) {
        const band = Math.floor(((x - 25) / (half + 1)) * 4 + 4)
        let c = band % 2 ? '#e8e0cc' : '#d0473c'
        if (x > 25 + half * 0.4) c = mixHex(c, '#2a2230', 0.2)
        if (x < 25 - half * 0.5) c = mixHex(c, '#fff6e6', 0.15)
        if (torn && y > 8 && Math.hypot(x - 33, y - 13) < 4 + hash(x, y, 4) * 2) continue
        px(x, y, c)
      }
    }
    // 檐口一圈金色花边
    for (let x = 2; x <= 48; x++) {
      px(x, 19, '#d8a840')
      if ((x - 2) % 4 < 3) px(x, 20, '#d8a840')
      if ((x - 2) % 4 === 1) px(x, 21, '#b8862c')
    }
    // 立柱和木马
    for (const x of [5, 15, 25, 35, 45]) rect(x, 21, 1, 18, '#e0b850')
    rect(23, 21, 5, 18, '#e8d8b0')
    rect(26, 21, 2, 18, '#c8b890')
    const horses = [
      [8, 27],
      [17, 31],
      [30, 28],
      [38, 31],
    ]
    for (const [x, y] of horses) {
      rect(x, y + 2, 6, 3, '#f4efe4')
      rect(x + 4, y, 3, 3, '#f4efe4')
      px(x + 6, y + 1, '#2a2230')
      rect(x, y + 5, 1, 2, '#d8d0c0')
      rect(x + 5, y + 5, 1, 2, '#d8d0c0')
      rect(x + 1, y + 1, 3, 1, '#c8453b')
    }
    // 底盘
    for (let y = 39; y <= 45; y++) {
      const half = Math.round(Math.sqrt(1 - ((y - 42) / 4.5) ** 2) * 24)
      for (let x = 25 - half; x <= 25 + half; x++)
        px(x, y, y < 41 ? '#c8a878' : y < 44 ? '#a68a64' : '#7a6448')
    }
  })
}

export function obelisk() {
  return sprite(20, 72, ({ px, rect }) => {
    rect(0, 66, 20, 6, '#9a9488')
    rect(0, 66, 20, 1, '#c8c2b4')
    rect(2, 60, 16, 6, '#aaa496')
    rect(2, 60, 16, 1, '#d6d0c2')
    // 碑身往上收窄，左边亮右边暗，中间一列刻字
    for (let y = 12; y < 60; y++) {
      const half = 3 + Math.round(((y - 12) / 48) * 2.5)
      for (let x = 10 - half; x < 10 + half; x++)
        px(x, y, stone((x - (10 - half)) / (2 * half), '#cfc8b8'))
    }
    for (let y = 18; y < 54; y += 3) rect(9, y, 2, 1, '#9a9282')
    // 塔尖镀金
    for (let y = 4; y < 12; y++) {
      const half = Math.round(((y - 3) / 8) * 3)
      for (let x = 10 - half; x < 10 + half; x++) px(x, y, x < 10 ? '#f0d070' : '#c8a040')
    }
  })
}

export function temple() {
  return sprite(82, 56, ({ px, rect }) => {
    // 三级台基
    const steps: [number, number, number][] = [
      [0, 50, 82],
      [3, 45, 76],
      [6, 41, 70],
    ]
    for (const [x, y, w] of steps) {
      rect(x, y, w, 6, '#bdb4a2')
      rect(x, y, w, 1, '#ddd5c4')
      rect(x, y + 5, w, 1, '#8c8474')
    }
    // 七根柱子，两根断了
    for (let k = 0; k < 7; k++) {
      const x = 9 + k * 10
      const top = k === 2 ? 26 : k === 5 ? 31 : 13
      for (let y = top; y < 41; y++) {
        rect(x, y, 6, 1, '#d6cebc')
        px(x, y, '#ece6d8')
        px(x + 2, y, '#bcb4a2')
        px(x + 5, y, '#a49c8a')
      }
      if (top === 13) rect(x - 1, 11, 8, 2, '#c8c0ae')
      else for (let i = 0; i < 6; i += 2) px(x + i, top - 1, '#d6cebc')
    }
    // 左边还剩一段檐和半个山花
    rect(7, 7, 38, 4, '#c8c0ae')
    rect(7, 10, 38, 1, '#9c9482')
    for (let y = 0; y < 7; y++) {
      const half = Math.round((y / 7) * 19)
      for (let x = 26 - half; x <= Math.min(26 + half, 44); x++)
        px(x, y, x - 26 > half - 2 || y === 6 ? '#a8a08e' : '#d0c8b6')
    }
    // 散落的石块和青苔
    rect(62, 46, 7, 4, '#b0a896')
    rect(70, 44, 5, 6, '#a49c8a')
    rect(56, 47, 4, 3, '#c0b8a6')
    for (let k = 0; k < 30; k++)
      px(Math.floor(hash(k, 1, 7) * 80), 12 + Math.floor(hash(k, 2, 7) * 42), '#6f8a4e')
  })
}

/** 栈桥上的杂物：摞起来的两只木箱、木桶、一盘缆绳、一只鱼篓，按编号挑一种 */
export function dockGoods(seed: number) {
  const k = Math.floor(hash(seed, 1, 23) * 4)
  if (k === 0)
    return sprite(8, 9, ({ rect, px }) => {
      for (const [x, y, w, h] of [
        [0, 4, 7, 5],
        [2, 0, 6, 4],
      ]) {
        rect(x, y, w, h, '#a07a4e')
        rect(x, y, w, 1, '#c8a070')
        rect(x + w - 1, y, 1, h, '#6e5034')
        px(x + 1, y + h - 2, '#5a4030')
      }
    })
  if (k === 1)
    return sprite(5, 7, ({ rect }) => {
      rect(0, 1, 5, 5, '#8a5e3a')
      rect(1, 0, 3, 7, '#8a5e3a')
      rect(1, 0, 1, 7, '#a8784a')
      rect(4, 1, 1, 5, '#5e3e26')
      rect(0, 2, 5, 1, '#4a4a52')
      rect(0, 5, 5, 1, '#4a4a52')
    })
  if (k === 2)
    return sprite(7, 3, ({ rect, px }) => {
      rect(1, 0, 5, 3, '#b89a6a')
      rect(0, 1, 7, 1, '#b89a6a')
      rect(2, 1, 3, 1, '#7a6040')
      px(1, 0, '#d8c090')
      px(6, 2, '#8a7050')
    })
  return sprite(6, 5, ({ rect, px }) => {
    rect(0, 1, 6, 4, '#a88a50')
    rect(0, 1, 6, 1, '#c8a868')
    for (let x = 1; x < 6; x += 2) rect(x, 2, 1, 3, '#7a6038')
    px(2, 0, '#9ab0b8')
    px(3, 0, '#c8d8e0')
  })
}

/** dead 为 true 时藤蔓枯了，没有花 */
export function roseArch(dead = false) {
  return sprite(30, 32, ({ px, rect }) => {
    for (const x of [2, 25]) {
      rect(x, 8, 3, 24, '#e8e0d0')
      rect(x + 2, 8, 1, 24, '#c0b8a8')
      for (let y = 10; y < 32; y += 4) rect(x, y, 3, 1, '#b8b0a0')
    }
    for (let k = 0; k <= 40; k++) {
      const a = Math.PI - (k / 40) * Math.PI
      const x = 15 + Math.cos(a) * 12,
        y = 10 - Math.sin(a) * 8
      px(x, y, '#e8e0d0')
      px(x, y + 1, '#c0b8a8')
    }
    for (let k = 0; k < 40; k++) {
      const a = Math.PI - hash(k, 1, 5) * Math.PI
      const r = 11 + hash(k, 2, 5) * 3
      const x = 15 + Math.cos(a) * r,
        y = 10 - Math.sin(a) * (r - 4)
      px(x, y, dead ? (k % 3 ? '#6a5a3a' : '#8a7448') : k % 3 ? '#4d7a45' : '#6b9a52')
      if (k % 2 && !dead) px(x + 1, y, k % 4 === 1 ? '#e05a6a' : '#f4a0b0')
    }
    for (let k = 0; k < 16; k++) {
      const x = k % 2 ? 1 + Math.floor(hash(k, 3, 5) * 5) : 24 + Math.floor(hash(k, 3, 5) * 5)
      px(x, 12 + Math.floor(hash(k, 4, 5) * 18), dead ? '#6a5a3a' : k % 3 ? '#4d7a45' : '#e05a6a')
    }
  })
}

/** 公园的八角凉亭：瓦顶分成几片斜面（左亮右暗）、一道道瓦缝，奶白的屋脊和檐口花边，檐下吊一盏灯；
 *  白柱子之间看得见亭子里的暗处和后排的柱子，前面一圈栏杆，正中留口、两级石阶下来，左边柱子爬着开花的藤。
 *  broken 为 true 时顶棚塌了一块，灯掉了 */
export function gazebo(broken = false) {
  return sprite(46, 46, ({ px, rect }) => {
    const apex = 22.5
    // 瓦顶：五道屋脊把顶分成四片，越往右越暗；每三行一道瓦缝
    const ridges = [1, 12, apex, 33, 44]
    const panels = ['#78ab90', '#5f9179', '#4d7c67', '#3b6555']
    for (let y = 4; y <= 16; y++) {
      const t = (y - 4) / 12
      const half = 1 + t * 21.5
      for (let x = Math.ceil(apex - half); x <= Math.floor(apex + half); x++) {
        if (broken && y > 6 && Math.hypot(x - 29, y - 11) < 4.5 + hash(x, y, 6) * 2) continue
        const at = ridges.map((r) => apex + (r - apex) * t)
        const ridge = at.some((r) => Math.abs(x - r) < 0.6)
        const panel = Math.min(3, Math.max(0, at.findIndex((r) => x < r) - 1))
        let c = panels[panel < 0 ? 3 : panel]
        if ((y - 4) % 3 === 2) c = mixHex(c, '#1d2a2a', 0.22)
        px(x, y, ridge ? mixHex('#e2dac6', '#1d2a2a', panel > 1 ? 0.18 : 0) : c)
      }
    }
    // 宝顶
    rect(22, 0, 2, 1, '#e8c860')
    rect(21, 1, 4, 2, '#c8a040')
    px(21, 1, '#f0d878')
    rect(22, 3, 2, 1, '#9a7a30')
    // 檐口：一道奶白的封檐板，底下隔一个像素垂一点花边
    rect(0, 17, 46, 1, '#f0ebde')
    rect(0, 18, 46, 1, '#cfc7b6')
    for (let x = 0; x < 46; x += 2) px(x, 19, '#e6dfcf')
    // 亭子里：暗处、后排的柱子和栏杆
    rect(4, 19, 38, 15, '#2f3b36')
    rect(4, 19, 38, 2, '#222b28')
    for (const x of [10, 22, 35]) rect(x, 21, 1, 13, '#5a645e')
    rect(4, 28, 38, 1, '#4a5450')
    // 檐下吊的灯
    if (!broken) {
      rect(23, 20, 1, 2, '#3a3440')
      rect(22, 22, 3, 3, '#ffd27a')
      px(22, 22, '#fff0b8')
      rect(22, 25, 3, 1, '#a8762c')
    }
    // 前排四根柱子：柱头宽一点，左亮右暗
    for (const x of [2, 14, 30, 42]) {
      rect(x - 1, 19, 4, 1, '#e8e2d4')
      rect(x, 20, 2, 15, '#f4f0e6')
      rect(x + 2, 20, 1, 15, '#c8c0b0')
      px(x, 20, '#ffffff')
    }
    // 前面的栏杆：两边两跨有，正中一跨留口
    for (const [x0, x1] of [
      [4, 13],
      [33, 41],
    ]) {
      rect(x0, 28, x1 - x0 + 1, 1, '#f0ebde')
      for (let x = x0 + 1; x < x1; x += 2) rect(x, 29, 1, 4, '#ddd6c6')
      rect(x0, 33, x1 - x0 + 1, 1, '#cfc7b6')
    }
    // 台基：石砌，上沿亮
    rect(0, 35, 46, 1, '#e2d8c0')
    rect(0, 36, 46, 4, '#bcae92')
    rect(38, 36, 8, 4, '#a39478')
    rect(0, 39, 46, 1, '#857760')
    for (let x = 3; x < 46; x += 6) px(x, 37, '#a39478')
    // 正中两级石阶
    rect(15, 40, 16, 1, '#d6ccb4')
    rect(15, 41, 16, 2, '#ab9d82')
    rect(13, 43, 20, 1, '#d6ccb4')
    rect(13, 44, 20, 2, '#9c8e74')
    // 左边柱子上爬的藤和花
    for (let k = 0; k < 34; k++) {
      const x = 1 + Math.floor(hash(k, 1, 9) * 5)
      const y = 19 + Math.floor(hash(k, 2, 9) * 17)
      const leaf = hash(k, 3, 9)
      if (broken && leaf > 0.7) continue
      px(
        x,
        y,
        leaf < 0.4 ? '#4d7a45' : leaf < 0.7 ? '#6b9a52' : leaf < 0.85 ? '#e8687a' : '#f4a0b0'
      )
    }
  })
}

/** 夜里亮灯的凉亭：檐下那盏灯是自发光的，照亮亭子里和脚下一圈 */
export function gazeboLit(): Flipbook {
  const canvas = gazebo()
  const glow = sprite(canvas.width, canvas.height, ({ rect, px }) => {
    rect(22, 22, 3, 3, '#ffd27a')
    px(22, 22, '#fff0b8')
  })
  return { canvas, glow, frames: 1, fps: 1, light: { color: '#ffc477', reach: 180, power: 1.1 } }
}

export const VILLAGE_LANDMARKS: LandmarkSet = {
  boat: (seed, kind) => boatModel('village', seed, kind),
  dockGoods,
  pavilion: true,
  fountain: 'flowing',
  plans: {
    ferris: () => [[ferrisWheel(), 0, -6]],
    carousel: () => [[carousel(), 0, -4]],
    obelisk: () => [[obelisk(), 0, -6]],
    temple: () => [[temple(), 0, -6]],
    market: (seed) => [
      [stall(seed, 'village'), -30, -10],
      [stall(seed + 1, 'village'), 0, -14],
      [stall(seed + 2, 'village'), 30, -10],
    ],
    garden: () => [[roseArch(), 0, -8]],
    park: () => [[gazeboLit(), 0, -6]],
    // 公园和海边的小摆设（见 parkPieces.ts），地图按坐标立
    bench: (seed) => [[bench(seed), 0, 0]],
    parasol: (seed) => [
      [parasol(seed), 0, 0],
      [deckChair(seed), 14, 3],
    ],
    planter: (seed) => [[planter(seed), 0, 0]],
    reeds: (seed) => [[reeds(seed), 0, 0]],
    rock: (seed) => [[rock(seed), 0, 0]],
    telescope: () => [[telescope(), 0, 0]],
    signpost: (seed) => [[signpost(seed), 0, 0]],
    // 花树林（见 groveArt.ts），地图按坐标立：大花树落花、入夜聚萤火虫，灯笼和石灯天黑才亮
    bigtree: () => [
      [
        {
          ...bigTree(),
          plant: true,
          lamp: true,
          halos: BIG_TREE_HALOS.map(([dx, up]) => [dx, up, 54]),
          sheds: { r: 290, low: 150, high: 430, count: 300, afloat: 110 },
          swarm: { r: 520, count: 170 },
        },
        0,
        0,
      ],
    ],
    blossom: (seed) => [
      [
        {
          canvas: blossomTree(seed),
          frames: 1,
          fps: 1,
          plant: true,
          sheds: { r: 90, low: 60, high: 170, count: 14 },
        },
        0,
        0,
      ],
    ],
    cedar: (seed) => [[{ canvas: cedar(seed), frames: 1, fps: 1, plant: true }, 0, 0]],
    lantern: (seed) => [[{ ...stoneLantern(seed), lamp: true, halos: [[0, 8, 60]] }, 0, 0]],
    lily: (seed) => [[lilyPads(seed), 0, 0]],
    cascade: () => [[cascade(), 0, 0]],
    deer: (seed) => [[deer(seed), 0, 0]],
  },
}

/** 栈桥边的船（见 boats.ts）：一条大船靠在桥身后面，船身顺着桥、船头朝桥头；多半还有一条小舢板拴在桥前头
 *  靠根部的地方，船头朝岸；一条船下了锚停在桥头外面的港湾里，船头大致朝岸。船底下要整片是水才放（water 按地图坐标问） */
function mooredBoats(
  dock: Dock,
  k: number,
  set: LandmarkSet,
  seed: number,
  water: (x: number, y: number) => boolean
): PlacedModel[] {
  const at = placer(dock)
  const { L, W } = footprint(dock)
  // 船占的一片（沿桥 u0..u1、横过桥 v0..v1）隔两像素抽查一遍
  const clear = (u0: number, u1: number, v0: number, v1: number) => {
    for (let u = u0; u <= u1; u += 2)
      for (let v = v0; v <= v1; v += 2) if (!water(...at(u, v))) return false
    return true
  }
  const out: PlacedModel[] = []
  const along = Math.atan2(dock.dy, dock.dx)
  const add = (u: number, v: number, model: LandmarkModel | null, angle: number) => {
    if (!model) return
    const [x, y] = at(u, v)
    out.push({ x, y, model: { ...model, angle } })
  }
  // 地形种子各张地图一样，按栈桥的位置再取一个：各个小镇的船不一样
  const own = Math.floor(hash(Math.round(dock.x), Math.round(dock.y), seed + k) * 1e6)
  const roll = (salt: number) => hash(own, salt, 17)
  const kind = Math.floor(roll(1) * 2)
  // 大船长 32、宽 10 像素以内，船边离桥一个半像素
  const u = L - 13,
    v = -6.5
  if (u > 17 && clear(u - 17, u + 17, v - 5.5, v + 5.5)) add(u, v, set.boat(own, kind), along)
  const ru = 14,
    rv = W + 3.5
  if (roll(2) < 0.75 && clear(ru - 8, ru + 8, rv - 3, rv + 3))
    add(ru, rv, set.boat(own + 7, 2), along + Math.PI)
  const au = L + 14,
    av = -24
  if (roll(3) < 0.8 && clear(au - 18, au + 18, av - 6, av + 6))
    add(au, av, set.boat(own + 13, 1 - kind), along + Math.PI + (roll(4) - 0.5) * 0.7)
  return out
}

/** 左右翻过来的立牌：逐帧动画每一帧各自翻，帧的顺序不变 */
function mirrored(art: HTMLCanvasElement | Flipbook): HTMLCanvasElement | Flipbook {
  const flip = (c: HTMLCanvasElement, frames: number) => {
    const out = document.createElement('canvas')
    out.width = c.width
    out.height = c.height
    const ctx = out.getContext('2d')!
    const fw = c.width / frames
    for (let f = 0; f < frames; f++) {
      ctx.save()
      ctx.translate((f + 1) * fw, 0)
      ctx.scale(-1, 1)
      ctx.drawImage(c, f * fw, 0, fw, c.height, 0, 0, fw, c.height)
      ctx.restore()
    }
    return out
  }
  if (art instanceof HTMLCanvasElement) return flip(art, 1)
  return {
    ...art,
    canvas: flip(art.canvas, art.frames),
    glow: art.glow && flip(art.glow, art.frames),
  }
}

/** 地图按坐标立的立牌（Atlas 的 standees）：照风格包 plans 里的名字画，不占区域格子，
 *  落在水上（干海床、冰面）也照立。种子按立牌的位置取，挪动一件不影响别的 */
export function mapStandees(
  atlas: Atlas,
  seed: number,
  set: LandmarkSet
): (LandmarkSprite | PlacedModel)[] {
  const out: (LandmarkSprite | PlacedModel)[] = []
  for (const s of atlas.standees ?? []) {
    const plan = s.kind === 'court' ? undefined : set.plans[s.kind]
    if (!plan) continue
    const own = Math.floor(hash(Math.round(s.x), Math.round(s.y), seed + 41) * 1e6)
    for (const [art, dx, dy] of plan(own)) {
      const x = s.x + (s.flip ? -dx : dx) * PIXEL,
        y = s.y + dy * PIXEL
      // 立体的不翻：转过去看就是另一面
      if (isModel(art)) {
        out.push({ x, y, model: art })
        continue
      }
      const drawn = s.flip ? mirrored(art) : art
      out.push({
        x,
        y,
        ...(drawn instanceof HTMLCanvasElement ? { canvas: drawn } : drawn),
        ...(s.on ? { on: s.on } : {}),
      })
    }
  }
  return out
}

/** 按区域摆出所有户外标志物；docks 是港口栈桥（地图坐标），船停在旁边，water 问地图上一点是不是水 */
export function landmarkSprites(
  atlas: Atlas,
  seed: number,
  docks: Dock[],
  set: LandmarkSet,
  water: (x: number, y: number) => boolean
): (LandmarkSprite | PlacedModel)[] {
  const out: (LandmarkSprite | PlacedModel)[] = docks.flatMap((d, k) =>
    mooredBoats(d, k, set, seed, water)
  )
  // 各地点立牌的种子按摆了几件往后数；船的条数不定，按原先每条栈桥一条船起算，地标的样子不跟着变
  let placed = docks.length
  for (const r of atlas.regions) {
    // 港口朝海的一半是水，地标摆在陆上的木码头上
    const cs = r.cell_size
    const cells =
      r.kind === 'harbor'
        ? r.cells.filter(([c, rr]) => !water((c + 0.5) * cs, (rr + 0.5) * cs))
        : r.cells
    if (!cells.length) continue
    const xs = cells.map(([x]) => x * cs),
      ys = cells.map(([, y]) => y * cs)
    const box = {
      x0: Math.min(...xs),
      y0: Math.min(...ys),
      x1: Math.max(...xs) + r.cell_size,
      y1: Math.max(...ys) + r.cell_size,
    }
    // 林子、行道树、草坪这些只管样子的区域不摆这类地点自带的凉亭、花拱门；指定了地标的照它摆。
    // 看台（court）是立体搭的，见 stand.ts
    const kind = r.landmark ?? (r.decor ? undefined : r.kind)
    // 立体凉亭由场景另搭（见 pixel/pavilions.ts）
    if (kind === 'park' && set.pavilion) continue
    // 立体喷泉由场景另搭（见 pixel/fountains.ts）
    if (kind === 'fountain') continue
    const plan = kind && kind !== 'court' ? set.plans[kind] : undefined
    if (!plan) continue
    const cx = (box.x0 + box.x1) / 2,
      cy = (box.y0 + box.y1) / 2
    const arts = plan(seed + placed)
    placed += arts.length
    for (const [art, dx, dy, afloat] of arts) {
      // 落到水上的（港口的地标偏得远）往中心拉回陆上
      let k = 1
      while (!afloat && k > 0 && water(cx + dx * PIXEL * k, cy + dy * PIXEL * k)) k -= 0.1
      const x = cx + dx * PIXEL * Math.max(0, k),
        y = cy + dy * PIXEL * Math.max(0, k)
      out.push(
        isModel(art)
          ? { x, y, model: art }
          : { x, y, ...(art instanceof HTMLCanvasElement ? { canvas: art } : art) }
      )
    }
  }
  return out
}
