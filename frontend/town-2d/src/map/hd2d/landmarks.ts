import type { Atlas } from 'town-shared/mapDocument'
import { PIXEL } from '../grid'
import { footprint, placer, type Dock } from '../pixel/island'
import { hash, mixHex } from '../pixel/noise'
import { villageBoat, type BoatView, type Moor } from './boats'
import { fountain } from './fountain'
import { sprite, stone } from './sprite'

// 户外地点的立体标志物：摩天轮、旋转亭、方尖碑、喷泉、神庙遗迹、弧形阶台这些地标，
// 以及市场的摊位、港口栈桥边的船、花园的花拱门、公园的凉亭。都是竖在地上的像素立牌，
// 和树、路灯一样按俯角转向镜头；光从左上来，左边亮右边暗。一个贴图像素对应一个地图像素。

/** 逐帧动画的立牌：canvas 是横排 frames 帧的图集，每秒 fps 帧循环播放 */
export interface Flipbook {
  canvas: HTMLCanvasElement
  /** 自发光图集（和 canvas 一样大）：白天微亮，夜里像打了灯 */
  glow?: HTMLCanvasElement
  frames: number
  fps: number
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
}

/** 一种风格的户外立牌：各类地点放什么、栈桥边停什么船、桥上堆什么、野地和外圈散落什么 */
export interface LandmarkSet {
  /** 一种户外地点在自己的区域里放哪些立牌：[贴图或逐帧动画, 相对区域中心的偏移（地图像素）] */
  plans: Record<string, (seed: number) => [HTMLCanvasElement | Flipbook, number, number][]>
  /** 栈桥边的船：kind 0、1 是大船，2 是小舢板；view 是镜头看见侧面还是船尾，moor 是怎么系的。
   *  没有这种船时给 null */
  boat: (
    seed: number,
    view: BoatView,
    kind: number,
    moor: Moor
  ) => HTMLCanvasElement | Flipbook | null
  /** 栈桥上堆的杂物（木箱、木桶、缆绳、鱼篓） */
  dockGoods: (seed: number) => HTMLCanvasElement
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

export function court() {
  return sprite(92, 32, ({ px, rect }) => {
    // 半圆形的几级石阶，越往后越高；前面是一块表演用的平台
    const cx = 46
    for (let t = 3; t >= 0; t--) {
      const rx = 22 + t * 8,
        ry = 8 + t * 6,
        base = 30 - t * 2
      for (let y = base - ry; y <= base; y++) {
        const half = Math.round(rx * Math.sqrt(Math.max(0, 1 - ((base - y) / ry) ** 2)))
        for (let x = cx - half; x <= cx + half; x++) {
          const edge = y === base - ry || Math.abs(x - cx) >= half - 1
          px(x, y, edge ? '#8c8270' : t % 2 ? '#c8bca6' : '#b4a890')
        }
      }
    }
    for (let y = 26; y <= 31; y++) {
      const half = Math.round(20 * Math.sqrt(1 - ((y - 28.5) / 3.5) ** 2))
      rect(cx - half, y, 2 * half + 1, 1, y === 26 ? '#e8dec8' : '#d4c8b0')
    }
  })
}

const AWNINGS: [string, string][] = [
  ['#d0473c', '#f1ead8'],
  ['#3f7a9a', '#f1ead8'],
  ['#d8a840', '#f1ead8'],
  ['#5a9a5a', '#f1ead8'],
]
const GOODS = ['#e05a4a', '#f0c040', '#7ab050', '#e89040', '#b86ab0']

export function stall(k: number) {
  const [a, b] = AWNINGS[k % AWNINGS.length]
  return sprite(28, 26, ({ px, rect }) => {
    rect(1, 7, 2, 19, '#6a4a30')
    rect(25, 7, 2, 19, '#4e3624')
    for (let x = 0; x < 28; x++) for (let y = 1; y < 7; y++) px(x, y, (x >> 2) & 1 ? b : a)
    rect(0, 0, 28, 1, mixHex(a, '#2a2230', 0.3))
    for (let x = 0; x < 28; x++)
      if ((x >> 2) % 2 === 0 || x % 4 === 1) px(x, 7, (x >> 2) & 1 ? b : a)
    rect(0, 17, 28, 7, '#8a6a44')
    rect(0, 17, 28, 1, '#a88660')
    rect(0, 23, 28, 1, '#5e4630')
    for (let i = 0; i < 9; i++) {
      const c = GOODS[(i + k) % GOODS.length]
      rect(2 + i * 3, 15, 2, 2, c)
      px(2 + i * 3, 15, mixHex(c, '#ffffff', 0.4))
    }
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

/** broken 为 true 时顶棚塌了一块 */
export function gazebo(broken = false) {
  return sprite(42, 42, ({ px, rect }) => {
    for (let y = 2; y <= 14; y++) {
      const half = Math.round(((y - 1) / 13) * 20)
      for (let x = 21 - half; x <= 21 + half; x++) {
        if (broken && y > 5 && Math.hypot(x - 27, y - 10) < 5 + hash(x, y, 6) * 2) continue
        px(x, y, x > 21 + half * 0.4 ? '#3f6a5e' : x < 21 - half * 0.5 ? '#6a9a86' : '#4f7f6e')
      }
    }
    rect(20, 0, 2, 2, '#c8a040')
    rect(0, 15, 42, 2, '#e8e0d0')
    for (const x of [3, 14, 26, 37]) {
      rect(x, 17, 3, 18, '#f0ece2')
      rect(x + 2, 17, 1, 18, '#c8c2b4')
    }
    rect(3, 27, 37, 1, '#d8d0c0')
    for (let x = 4; x < 40; x += 3) rect(x, 28, 1, 5, '#d8d0c0')
    rect(1, 35, 40, 4, '#b8a888')
    rect(1, 35, 40, 1, '#d0c0a0')
    rect(1, 38, 40, 1, '#8a7a60')
  })
}

export const VILLAGE_LANDMARKS: LandmarkSet = {
  boat: villageBoat,
  dockGoods,
  plans: {
    ferris: () => [[ferrisWheel(), 0, -6]],
    carousel: () => [[carousel(), 0, -4]],
    obelisk: () => [[obelisk(), 0, -6]],
    fountain: () => [[fountain(), 0, -4]],
    temple: () => [[temple(), 0, -6]],
    court: () => [[court(), 0, -8]],
    market: (seed) => [
      [stall(seed), -30, -10],
      [stall(seed + 1), 0, -14],
      [stall(seed + 2), 30, -10],
    ],
    garden: () => [[roseArch(), 0, -8]],
    park: () => [[gazebo(), 0, -6]],
  },
}

/** 栈桥边的船：一条大船靠在桥身后面（横向的桥看侧面、船头朝桥头；竖向的桥看船尾），
 *  多半还有一条小舢板拴在桥前头靠根部的地方、一条船系在桥头外面港湾里的浮筒上。
 *  船底下要整片是水才放（water 按地图坐标问） */
function mooredBoats(
  dock: Dock,
  k: number,
  set: LandmarkSet,
  seed: number,
  water: (x: number, y: number) => boolean
): LandmarkSprite[] {
  const at = placer(dock)
  const { L, W } = footprint(dock)
  const side = dock.dx !== 0
  const view: BoatView = side ? 'side' : 'stern'
  // 船占的一片（沿桥 u0..u1、横过桥 v0..v1）隔两像素抽查一遍
  const clear = (u0: number, u1: number, v0: number, v1: number) => {
    for (let u = u0; u <= u1; u += 2)
      for (let v = v0; v <= v1; v += 2) if (!water(...at(u, v))) return false
    return true
  }
  const tied = (mirror: boolean): Moor => ({ mirror, tied: true })
  const out: LandmarkSprite[] = []
  const add = (u: number, v: number, art: HTMLCanvasElement | Flipbook | null) => {
    if (!art) return
    const [x, y] = at(u, v)
    out.push({ x, y, ...(art instanceof HTMLCanvasElement ? { canvas: art } : art) })
  }
  // 地形种子各张地图一样，按栈桥的位置再取一个：各个小镇的船不一样
  const own = Math.floor(hash(Math.round(dock.x), Math.round(dock.y), seed + k) * 1e6)
  const roll = (salt: number) => hash(own, salt, 17)
  const kind = Math.floor(roll(1) * 2)
  // 大船：侧面船长约 34、看船尾时宽约 14 像素
  const u = L - 13,
    v = side ? -4 : -9
  if (u > 17 && clear(u - 17, u + 17, v - (side ? 3 : 7), v + (side ? 3 : 7)))
    add(u, v, set.boat(own, view, kind, tied(dock.dx < 0)))
  const ru = 14,
    rv = W + (side ? 3 : 5)
  if (roll(2) < 0.75 && clear(ru - 10, ru + 10, rv - 2, rv + 4))
    add(ru, rv, set.boat(own + 7, view, 2, tied(dock.dx > 0)))
  // 港湾里的船：在桥头外面、桥身后方，和靠桥的大船错开
  const au = L + 14,
    av = side ? -24 : -26
  if (roll(3) < 0.8 && clear(au - 18, au + 18, av - 4, av + 4))
    add(au, av, set.boat(own + 13, view, 1 - kind, { mirror: dock.dx > 0, tied: false }))
  return out
}

/** 按区域摆出所有户外标志物；docks 是港口栈桥（地图坐标），船停在旁边，water 问地图上一点是不是水 */
export function landmarkSprites(
  atlas: Atlas,
  seed: number,
  docks: Dock[],
  set: LandmarkSet,
  water: (x: number, y: number) => boolean
): LandmarkSprite[] {
  const out: LandmarkSprite[] = docks.flatMap((d, k) => mooredBoats(d, k, set, seed, water))
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
    const plan = set.plans[r.kind]
    if (!plan) continue
    const cx = (box.x0 + box.x1) / 2,
      cy = (box.y0 + box.y1) / 2
    const arts = plan(seed + placed)
    placed += arts.length
    for (const [art, dx, dy] of arts) {
      // 落到水上的（港口的地标偏得远）往中心拉回陆上
      let k = 1
      while (k > 0 && water(cx + dx * PIXEL * k, cy + dy * PIXEL * k)) k -= 0.1
      out.push({
        x: cx + dx * PIXEL * Math.max(0, k),
        y: cy + dy * PIXEL * Math.max(0, k),
        ...(art instanceof HTMLCanvasElement ? { canvas: art } : art),
      })
    }
  }
  return out
}
