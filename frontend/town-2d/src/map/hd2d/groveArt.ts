import { hash, mixHex, noise, rng } from '../pixel/noise'
import type { Flipbook } from './landmarks'
import { sprite } from './sprite'

// 花树林的立牌（默认地图的东林公园）：池心小岛上的大花树（挂着纸灯笼）、一团团花冠的小花树、深色的雪松、
// 石灯、水面的睡莲、叠水的石头、林边吃草的鹿。地图按坐标立，光从左上来。

/** 花冠的配色：从最暗的背光到最亮的受光六档 */
const BLOOM = ['#6b3252', '#96496e', '#c2668c', '#e28dab', '#f5b8ca', '#fee6ec'] as const
/** 夜里花冠被灯笼映亮的颜色 */
const BLOOM_LIT = '#ffb9a8'
/** 飘落的花瓣：浅色、深色（见 petals.ts） */
export const PETAL = { pale: BLOOM[5], deep: BLOOM[3] }

const BARK = ['#2e2224', '#463230', '#5f463a', '#7c5d48', '#9a7a5c']
const SHADE = '#2a2230'

interface Puff {
  x: number
  y: number
  r: number
  /** 这一团整体的明暗（-0.5 背光 ～ 0.5 受光） */
  tone: number
}

/** 一团团花冠：每团是一个带噪声边缘的圆，左上亮、右下暗，右下沿压一道最暗色把相邻的团分开。
 *  按从后到前（先上后下）画，后画的盖住先画的 */
function paintPuffs(put: (x: number, y: number, c: string) => void, puffs: Puff[], seed: number) {
  const T = BLOOM
  for (const [k, p] of puffs.entries()) {
    const r = p.r
    for (let dy = -r - 1; dy <= r + 1; dy++)
      for (let dx = -r - 1; dx <= r + 1; dx++) {
        const X = Math.round(p.x + dx),
          Y = Math.round(p.y + dy)
        const n = noise(X / 2.6, Y / 2.6, seed + k * 7)
        const d = Math.hypot(dx, dy * 1.18)
        const edge = r * (0.8 + 0.34 * n)
        if (d >= edge) continue
        // 团里零星透出背后的暗处，花冠不是实心的一块
        if (d < edge - 2.5 && hash(X >> 1, Y, seed + 3) < 0.02) {
          put(X, Y, T[0])
          continue
        }
        let light = ((-dx * 0.6 - dy * 1.0) / r) * 1.05 + (n - 0.5) * 0.7 + p.tone * 1.35
        // 花是一小撮一小撮的：按 2 像素的小块再抖一下明暗
        light += (hash(X >> 1, Y >> 1, seed + 11) - 0.5) * 0.42
        let i = Math.floor(((light + 1.25) / 2.5) * 6)
        i = Math.max(0, Math.min(5, i))
        // 右下沿的暗边
        if (d > edge - 1.3 && dx * 0.6 + dy > 0) i = Math.min(i, d > edge - 0.7 ? 0 : 1)
        // 左上沿的亮边
        else if (d > edge - 1.2 && dx + dy * 1.4 < -r * 0.5) i = Math.max(i, 4)
        put(X, Y, T[i])
      }
  }
}

/** 一段树枝：从 (x, y) 朝 angle 走 len 个像素，粗 w，越走越细；左半边亮 */
function bough(
  put: (x: number, y: number, c: string) => void,
  x: number,
  y: number,
  angle: number,
  len: number,
  w: number,
  bend: number
) {
  for (let s = 0; s < len; s++) {
    x += Math.cos(angle)
    y += Math.sin(angle)
    angle += bend / len
    const width = Math.max(1, Math.round(w * (1 - (s / len) * 0.65)))
    for (let k = 0; k < width; k++) {
      const t = width === 1 ? 0.4 : k / (width - 1)
      put(x + k - width / 2, y, BARK[t < 0.3 ? 3 : t < 0.7 ? 2 : 1])
    }
  }
  return [x, y] as const
}

/** 大花树按这个倍数画（1 时 132×116 个贴图像素） */
const K = 0.74
const BIG_W = Math.round(132 * K)
const BIG_H = Math.round(116 * K)

/** 大花树的花团：一个大伞盖，中间高、两边垂下来，前面（下沿）几团压在最上面 */
function bigPuffs(seed: number): Puff[] {
  const random = rng(seed)
  const cx = BIG_W / 2,
    top = 12 * K
  const puffs: Puff[] = []
  // 伞盖按行铺：越往下越宽，到最宽处再收一点
  const rows = [
    { y: 8, half: 20, n: 3, r: 11 },
    { y: 17, half: 36, n: 5, r: 12 },
    { y: 27, half: 49, n: 7, r: 12.5 },
    { y: 37, half: 56, n: 8, r: 12 },
    { y: 47, half: 57, n: 8, r: 11 },
    { y: 56, half: 52, n: 7, r: 9.5 },
  ]
  for (const [j, row] of rows.entries())
    for (let k = 0; k < row.n; k++) {
      const t = row.n === 1 ? 0 : (k / (row.n - 1)) * 2 - 1
      const x = cx + (t * row.half + (random() - 0.5) * 7) * K
      // 两边的团往下垂
      const y = top + (row.y + Math.abs(t) ** 2 * 9 + (random() - 0.5) * 5) * K
      // 最下面一行中间空出来，露出树干和枝杈
      if (j === rows.length - 1 && Math.abs(t) < 0.3) continue
      if (j === rows.length - 2 && Math.abs(t) < 0.15) continue
      puffs.push({
        x,
        y,
        r: row.r * (0.85 + random() * 0.35) * K + 0.8,
        tone: -t * 0.22 - (j / rows.length) * 0.5 + 0.28,
      })
    }
  // 垂到最低的几团（两边的枝梢）
  for (const [x, y, r] of [
    [10, 78, 7],
    [20, 84, 6],
    [122, 80, 7],
    [112, 86, 6],
    [34, 80, 6.5],
    [98, 81, 6.5],
  ] as const)
    puffs.push({ x: x * K, y: (y - 4) * K, r: r * K + 0.6, tone: x * K < cx ? 0.0 : -0.35 })
  return puffs.sort((a, b) => a.y - b.y)
}

/** 灯笼挂在哪：[x, 绳顶 y, 灯笼顶 y]，都在花冠下沿 */
const LANTERNS: [number, number, number][] = (
  [
    [17, 82, 90],
    [29, 80, 94],
    [41, 74, 88],
    [53, 70, 85],
    [79, 70, 86],
    [91, 74, 90],
    [103, 80, 95],
    [116, 82, 91],
    [66, 64, 78],
  ] as const
).map(([x, y0, y1]) => [Math.round(x * K), Math.round(y0 * K), Math.round(y1 * K)])

/** 池心小岛上的大花树：粗树干从盘开的树根里拔起来，分成三股大枝撑开一个大伞盖，花一团团压着；
 *  花冠下沿挂一圈纸灯笼。夜里灯笼亮起来，把花冠的下半映成暖色，照亮树下一圈 */
export function bigTree(seed = 7): Flipbook {
  const puffs = bigPuffs(seed)
  const cx = Math.floor(BIG_W / 2)
  const base = BIG_H - 1
  const forkY = Math.round(64 * K)
  const canvas = sprite(BIG_W, BIG_H, ({ px, rect }) => {
    const put = (x: number, y: number, c: string) => px(Math.round(x), Math.round(y), c)
    // 伞盖底下的暗处：先铺一层最暗的花影，枝杈画在它上面
    for (let y = Math.round(44 * K); y < Math.round(82 * K); y++)
      for (let x = Math.round(10 * K); x < BIG_W - Math.round(10 * K); x++) {
        const t = (x - cx) / (56 * K)
        const lower = (70 + Math.abs(t) ** 2 * 10) * K
        if (Math.abs(t) < 1 && y < lower && hash(x, y, seed + 5) < 0.86)
          put(x, y, hash(x >> 1, y >> 1, seed + 6) < 0.3 ? BLOOM[1] : BLOOM[0])
      }
    // 树根：往两边盘开
    for (let k = 0; k < 4; k++) {
      const dir = k < 2 ? -1 : 1
      const reach = Math.round((9 + (k % 2) * 5) * K)
      for (let s = 0; s < reach; s++) {
        const x = cx + dir * (Math.round(4 * K) + s),
          y = base - Math.max(0, 3 - Math.floor(s / 2)) + (k % 2)
        rect(Math.round(x), Math.round(y), 1, base - Math.round(y) + 1, BARK[dir < 0 ? 3 : 1])
      }
    }
    // 树干：下粗上细，一道道竖着的树皮纹，左亮右暗
    for (let y = base; y > forkY - 2; y--) {
      const t = (base - y) / (base - forkY)
      const half = (8.5 - t * 3.2) * K + (y > base - 4 ? (4 - (base - y)) * 0.8 : 0)
      const lean = Math.sin(t * 2.2) * 1.2
      for (let x = Math.ceil(cx + lean - half); x <= Math.floor(cx + lean + half); x++) {
        const u = (x - (cx + lean)) / half
        let i = u < -0.55 ? 3 : u < 0.1 ? 2 : u < 0.6 ? 1 : 0
        if (hash(x, y >> 2, seed + 21) < 0.28) i = Math.max(0, i - 1)
        if (u < -0.3 && hash(x, y >> 1, seed + 22) < 0.18) i = 4
        put(x, y, BARK[i])
      }
    }
    // 树洞
    rect(cx + 1, base - Math.round(18 * K), 2, 4, BARK[0])
    // 三股大枝，各自再分一次叉
    const arms: [number, number, number, number][] = [
      [-2.25, 30, 7, 0.5],
      [-1.62, 26, 7, -0.15],
      [-0.9, 30, 7, -0.5],
      [-2.75, 34, 5, 0.75],
      [-0.4, 34, 5, -0.75],
    ]
    for (const [angle, len, w, bend] of arms) {
      const [ex, ey] = bough(put, cx, forkY, angle, len * K, w * K, bend)
      bough(put, ex, ey, angle + bend - 0.5, len * K * 0.45, 2, 0.3)
      bough(put, ex, ey, angle + bend + 0.5, len * K * 0.45, 2, -0.3)
    }
    paintPuffs(put, puffs, seed)
    // 灯笼：一根细绳吊着，红纸的灯身、暖黄的灯芯，底下一撮穗子
    for (const [x, y0, y1] of LANTERNS) {
      for (let y = y0; y < y1; y++) px(x, y, '#3a2c2c')
      rect(x - 1, y1, 3, 4, '#d8563c')
      rect(x - 1, y1 + 1, 3, 2, '#ffcf7a')
      px(x, y1 + 1, '#fff2c0')
      px(x - 1, y1, '#8a2c24')
      px(x + 1, y1, '#8a2c24')
      px(x, y1 + 4, '#e8b040')
    }
  })
  // 夜里发光的部分：灯笼本身，和被灯映亮的花冠下半（越靠近灯笼越亮，按抖动稀疏开）
  const glow = sprite(BIG_W, BIG_H, ({ px, rect }) => {
    const ctx = canvas.getContext('2d')!
    const img = ctx.getImageData(0, 0, BIG_W, BIG_H).data
    for (let y = Math.round(36 * K); y < BIG_H; y++)
      for (let x = 0; x < BIG_W; x++) {
        if (!img[(y * BIG_W + x) * 4 + 3]) continue
        let near = 0
        for (const [lx, , ly] of LANTERNS) {
          const d = Math.hypot(x - lx, (y - ly - 2) * 1.2)
          near = Math.max(near, 1 - d / (30 * K))
        }
        if (near <= 0) continue
        // 只映亮花，树干树枝少映一点
        const r = img[(y * BIG_W + x) * 4],
          b = img[(y * BIG_W + x) * 4 + 2]
        const petal = r > 110 || b > 110
        const level = near * (petal ? 1 : 0.45)
        if (level > 0.1 + hash(x, y, seed + 31) * 0.5)
          px(x, y, mixHex('#000000', BLOOM_LIT, Math.min(1, level * 0.95)))
      }
    for (const [x, , y1] of LANTERNS) {
      rect(x - 1, y1, 3, 4, '#ff9a5c')
      rect(x - 1, y1 + 1, 3, 2, '#ffe2a0')
      px(x, y1 + 1, '#ffffff')
    }
  })
  return {
    canvas,
    glow,
    frames: 1,
    fps: 1,
    light: { color: '#ffb277', reach: 330, power: 1.25, on: 0.12 },
  }
}

/** 大花树上灯笼的位置（相对立牌底边中点：横向偏移、离地多少个贴图像素），场景在这些点上加光晕 */
export const BIG_TREE_HALOS: [number, number][] = LANTERNS.map(([x, , y1]) => [
  x - BIG_W / 2,
  BIG_H - (y1 + 2),
])

/** 小花树：分叉的深色树干托着五六团花，比镇上的圆冠树宽、矮，树干看得见 */
export function blossomTree(seed: number) {
  const random = rng(seed + 3)
  const big = 0.72 + random() * 0.3
  const W = Math.round(40 * big),
    H = Math.round(40 * big)
  const cx = W / 2
  return sprite(W, H, ({ px }) => {
    const put = (x: number, y: number, c: string) => px(Math.round(x), Math.round(y), c)
    const base = H - 1
    const lean = (random() - 0.5) * 0.5
    // 树干到一半分叉
    const [fx, fy] = bough(put, cx, base, -Math.PI / 2 + lean, H * 0.36, 3.4, lean * 0.6)
    px(Math.round(cx - 2), base, BARK[2])
    px(Math.round(cx + 2), base, BARK[1])
    for (const a of [-0.85, -0.2, 0.55]) {
      bough(put, fx, fy, -Math.PI / 2 + a, H * 0.26, 2, a * 0.5)
    }
    const puffs: Puff[] = []
    const n = 6 + Math.floor(random() * 3)
    for (let k = 0; k < n; k++) {
      const t = (k / (n - 1)) * 2 - 1
      const row = k % 2
      puffs.push({
        x: cx + t * W * 0.33 + (random() - 0.5) * 3,
        y: H * (0.3 + row * 0.16) + Math.abs(t) ** 2 * H * 0.12 + (random() - 0.5) * 3,
        r: W * (0.17 + random() * 0.06),
        tone: -t * 0.25 - row * 0.3 + 0.2,
      })
    }
    puffs.push({ x: cx + (random() - 0.5) * 4, y: H * 0.2, r: W * 0.2, tone: 0.3 })
    paintPuffs(
      put,
      puffs.sort((a, b) => a.y - b.y),
      seed
    )
  })
}

const CEDAR = ['#132a28', '#1b3a34', '#265040', '#34684c', '#4a825a', '#679a66']

/** 雪松：又高又瘦的深色尖塔，一层层枝往下垂、层与层之间露出暗处；立在花树背后把粉色衬出来 */
export function cedar(seed: number) {
  const random = rng(seed + 9)
  const H = 44 + Math.floor(random() * 16),
    half = 7 + Math.floor(random() * 3)
  const W = half * 2 + 3
  const cx = Math.floor(W / 2)
  return sprite(W, H, ({ px, rect }) => {
    rect(cx - 1, H - 5, 2, 5, BARK[1])
    px(cx - 1, H - 5, BARK[3])
    const tiers = Math.round(H / 6.5)
    for (let t = 0; t < tiers; t++) {
      const y0 = 1 + Math.round((t / tiers) * (H - 7))
      const y1 = 1 + Math.round(((t + 1) / tiers) * (H - 7)) + 2
      const w1 = Math.max(1.2, ((t + 1.2) / tiers) * half)
      for (let y = y0; y <= y1; y++) {
        const k = (y - y0) / (y1 - y0)
        const w = Math.round(w1 * (0.35 + 0.65 * k) + (hash(y, t, seed) - 0.5) * 1.4)
        for (let x = -w; x <= w; x++) {
          const u = x / (w + 0.5)
          let i = Math.floor(
            (0.62 - u * 0.5 - k * 0.3 + (hash(cx + x, y, seed + 1) - 0.5) * 0.5) * 6
          )
          if (k > 0.82) i = Math.min(i, 1)
          if (k < 0.2 && u < 0.2) i = Math.max(i, 4)
          px(cx + x, y, CEDAR[Math.max(0, Math.min(5, i))])
        }
      }
    }
    px(cx, 0, CEDAR[4])
  })
}

/** 石灯：石墩、石柱、镂空的灯室和一顶小石帽，帽上一点青苔；夜里灯室透出暖光，照亮脚下一小圈 */
export function stoneLantern(seed: number): Flipbook {
  const draw = (lit: boolean) =>
    sprite(9, 15, ({ px, rect }) => {
      if (lit) {
        rect(3, 5, 3, 3, '#ffd890')
        px(4, 6, '#ffffff')
        return
      }
      // 帽
      px(4, 0, '#8d887c')
      rect(3, 1, 3, 1, '#a9a396')
      rect(1, 2, 7, 1, '#bdb7a8')
      rect(0, 3, 9, 1, '#9c968a')
      px(8, 3, '#6f6a60')
      if (hash(seed, 1, 5) < 0.7) {
        px(2, 2, '#6f8a4e')
        px(3, 1, '#88a35c')
      }
      // 灯室
      rect(2, 4, 5, 5, '#8d887c')
      rect(2, 4, 1, 5, '#b3ad9f')
      rect(6, 4, 1, 5, '#6f6a60')
      rect(3, 5, 3, 3, '#ffc66e')
      px(4, 6, '#fff0c0')
      // 柱和墩
      rect(1, 9, 7, 1, '#a9a396')
      rect(3, 10, 3, 3, '#9c968a')
      px(3, 10, '#bdb7a8')
      px(5, 12, '#6f6a60')
      rect(1, 13, 7, 2, '#8d887c')
      rect(1, 13, 7, 1, '#b3ad9f')
      px(7, 14, '#6f6a60')
    })
  return {
    canvas: draw(false),
    glow: draw(true),
    frames: 1,
    fps: 1,
    light: { color: '#ffb768', reach: 130, power: 1.15, on: 0.1 },
  }
}

/** 一片睡莲：几张圆叶贴着水面（缺一个小口），一两朵花 */
export function lilyPads(seed: number) {
  const random = rng(seed + 17)
  return sprite(22, 9, ({ px, rect }) => {
    const pads = 3 + Math.floor(random() * 3)
    for (let k = 0; k < pads; k++) {
      const x = 1 + Math.floor(random() * 16),
        y = 2 + Math.floor(random() * 5)
      const w = 4 + Math.floor(random() * 2)
      rect(x, y, w, 2, '#4f8a54')
      rect(x + 1, y - 1, w - 2, 1, '#6aa863')
      rect(x + 1, y + 2, w - 2, 1, '#356b47')
      px(x + w - 2, y, '#2c5a5c')
      px(x + 1, y, '#8cc276')
      if (k < 2) {
        px(x + 2, y - 1, BLOOM[4])
        px(x + 3, y - 1, BLOOM[3])
        px(x + 2, y - 2, BLOOM[5])
        px(x + 2, y, '#f6d860')
      }
    }
  })
}

/** 叠水：一堆长了青苔的大石头，泉水从石缝里出来，分三叠落进脚下的小溪。四帧：水帘上的白纹往下走，
 *  每一叠落水处溅一点白沫 */
export function cascade(): Flipbook {
  const W = 46,
    H = 34,
    FRAMES = 4
  const rockAt = (x: number, y: number) => {
    // 石堆的轮廓：几块大石头叠起来
    const blobs: [number, number, number, number][] = [
      [12, 22, 12, 11],
      [33, 23, 12, 10],
      [22, 13, 13, 11],
      [9, 29, 9, 5],
      [38, 29, 8, 5],
      [23, 26, 12, 8],
    ]
    let best = -1,
      shade = 0
    for (const [k, [bx, by, rx, ry]] of blobs.entries()) {
      const dx = (x - bx) / rx,
        dy = (y - by) / ry
      const d = dx * dx + dy * dy
      if (d < 1 + (noise(x / 2, y / 2, k + 3) - 0.5) * 0.3) {
        best = k
        shade = -dx * 0.55 - dy * 0.75
      }
    }
    return best < 0 ? null : shade
  }
  // 水走的路：三叠，每叠一段竖着的水帘，中间是石头上的一小汪
  const falls: [number, number, number, number][] = [
    [21, 8, 14, 3],
    [19, 15, 22, 4],
    [20, 23, 33, 6],
  ]
  const canvas = sprite(W * FRAMES, H, ({ px }) => {
    for (let f = 0; f < FRAMES; f++) {
      for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
          const s = rockAt(x, y)
          if (s === null) continue
          const n = noise(x / 3, y / 3, 41)
          let c = s > 0.45 ? '#b9b4a8' : s > 0.05 ? '#96918a' : s > -0.4 ? '#757068' : '#55514e'
          if (n > 0.66) c = mixHex(c, SHADE, 0.18)
          // 朝上的面长青苔
          if (s > 0.25 && noise(x / 2.2, y / 2.2, 43) > 0.52)
            c = hash(x, y, 44) < 0.5 ? '#5f8a4a' : '#7ba65a'
          px(f * W + x, y, c)
        }
      for (const [x0, y0, y1, w] of falls) {
        for (let y = y0; y <= y1; y++)
          for (let x = x0; x < x0 + w; x++) {
            const streak = (y + f * 2 + x * 3) % 8
            const c = streak < 2 ? '#f4fbff' : streak < 5 ? '#a8dcec' : '#6fbcd8'
            px(f * W + x, y, c)
          }
        // 落水处的白沫，隔帧换位置
        for (let k = 0; k < w + 2; k++)
          if (hash(k, f, y1) < 0.6)
            px(f * W + x0 - 1 + k, y1 + (hash(k, f, 7) < 0.5 ? 0 : 1), '#ffffff')
        // 每叠顶上的一汪水
        for (let x = x0 - 1; x < x0 + w + 1; x++) px(f * W + x, y0 - 1, '#8fd0e4')
      }
    }
  })
  return { canvas, frames: FRAMES, fps: 7 }
}

/** 林边的鹿：两帧，抬头张望、低头吃草；有的是带斑点的小鹿，有的是长角的公鹿 */
export function deer(seed: number): Flipbook {
  const W = 17,
    H = 15
  const fawn = hash(seed, 3, 1) < 0.45
  const up = [
    '............a..a.',
    '............a.a..',
    '...........ebbe..',
    '...........bbkbn.',
    '...........bbbb..',
    '..........bbb....',
    '.wBBBBBBBBbbb....',
    'wbbbbbbbbbbbb....',
    '.bbbbbbbbbbbb....',
    '.bbcccccccbb.....',
    '.dd.d....d.d.....',
    '.d..d....d.d.....',
    '..d.d....d.d.....',
    '..d.d....d.d.....',
    '..d.d....d.d.....',
  ]
  const down = [
    '.................',
    '.................',
    '.................',
    '.................',
    '.................',
    '.................',
    '.wBBBBBBBBbb.....',
    'wbbbbbbbbbbbb....',
    '.bbbbbbbbbbbbb...',
    '.bbcccccccbbbb...',
    '.dd.d....d.dbbe..',
    '.d..d....d.d.bbb.',
    '..d.d....d.d.bkbn',
    '..d.d....d.d..bb.',
    '..d.d....d.d.....',
  ]
  const body = fawn ? '#c58d58' : '#a8713f'
  const colors: Record<string, string> = {
    b: body,
    B: mixHex(body, '#fff6e6', 0.3),
    c: '#e8d6b4',
    d: mixHex(body, SHADE, 0.4),
    w: '#f6eedc',
    k: '#231816',
    n: '#3a2a22',
    e: mixHex(body, SHADE, 0.25),
    a: '#dccba4',
  }
  const canvas = sprite(W * 2, H, ({ px }) => {
    for (const [f, rows] of [up, down].entries())
      rows.forEach((row, y) =>
        [...row].forEach((ch, x) => {
          if (ch === '.' || (ch === 'a' && fawn)) return
          px(f * W + x, y, colors[ch])
        })
      )
    // 小鹿背上的白斑
    if (fawn)
      for (const f of [0, 1])
        for (const [x, y] of [
          [3, 7],
          [6, 8],
          [8, 7],
          [10, 8],
        ])
          px(f * W + x, y, '#f3e2c4')
  })
  return { canvas, frames: 2, fps: 0.3 }
}
