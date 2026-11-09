import { crack, hash, mixHex, noise, pick } from '../pixel/noise'
import { tree } from '../pixel/terrain'
import type { MapTheme } from '../themes/types'
import type { House } from './layout'
import { DOORS, type WindowKind } from '../buildings'
import { ICE, LAMP_GLOW, SNOW, SNOW_GREY, SNOW_SHADE } from '../palette'

// 立体场景用到的像素贴图，全部在画布上逐像素画出。

/** 墙面的中间一档颜色：拱顶两头、掀开屋顶后的外墙用它；集装箱按房子编号挑漆色，刷漆木板用房子的漆色 */
export function wallBase(house: House) {
  const { style, seed, walls } = house
  return style === 'container'
    ? walls.containers[seed % walls.containers.length][1]
    : style === 'painted'
      ? house.paint[1]
      : house.wallShades[1]
}
/** 墙面夜里的微光是窗户亮度的几分之一 */
const WALL_NIGHT_GLOW = 0.3
const FRAME = '#3b2a1f'
const GLASS = '#233140'
const GLASS_LIGHT = '#3b5068'
const LIT = '#ffc56a'

function canvas(w: number, h: number) {
  const c = document.createElement('canvas')
  c.width = Math.max(1, w)
  c.height = Math.max(1, h)
  return c
}

/** 墙面底色：各材质的砖缝、木纹、石块；颜色取房子所在风格的 walls */
function wallColor(house: House, i: number, j: number) {
  const { style, seed, walls: W } = house
  const base = house.wallShades
  switch (style) {
    case 'wood': {
      const row = Math.floor(j / 3)
      return j % 3 === 2
        ? W.woodGrain
        : base[Math.floor(hash(Math.floor((i + hash(row, 0, seed) * 20) / 14), row, seed) * 3)]
    }
    case 'plank': {
      // 竖向木板
      const col = Math.floor(i / 4)
      return i % 4 === 3 ? W.plankGap : base[Math.floor(hash(col, Math.floor(j / 9), seed) * 3)]
    }
    case 'stone':
    case 'brick': {
      const row = j >> 1,
        off = (row & 1) * (style === 'brick' ? 2 : 3),
        bw = style === 'brick' ? 4 : 6
      if (j % 2 === 1 || (i + off) % bw === 0)
        return style === 'brick' ? W.brickMortar : W.stoneMortar
      return base[Math.floor(hash(Math.floor((i + off) / bw), row, seed) * 3)]
    }
    case 'tin': {
      // 竖向波纹，一格亮一格暗；成片的锈，锈从钉眼往下流
      const r = noise(i / 6, j / 5, seed + 3)
      if (r > 0.62 || (hash(i, 0, seed) < 0.08 && j < hash(i, 1, seed) * 14))
        return W.rust[Math.floor(hash(i, j, seed + 4) * 3)]
      return base[[2, 0, 1][i % 3]]
    }
    case 'container': {
      const paint = W.containers[seed % W.containers.length]
      if (noise(i / 5, j / 4, seed + 5) > 0.66) return W.rust[Math.floor(hash(i, j, seed) * 2)]
      return i % 4 === 0 ? mixHex(paint[1], '#000000', 0.3) : i % 4 === 1 ? paint[2] : paint[0]
    }
    case 'concrete': {
      // 从墙顶往下的水渍，几块补过的灰浆，零星裂缝
      if (hash(i, 0, seed) < 0.1 && j < hash(i, 1, seed) * 18) return W.concreteStain
      if (crack(i, j, 7, seed) < 0.45 && noise(i / 9, j / 9, seed + 6) > 0.5) return W.concreteCrack
      if (hash(i >> 3, j >> 2, seed + 3) < 0.1) return pick(W.concretePatch, hash(i, j, seed), i, j)
      return pick(base, noise(i / 4, j / 4, seed), i, j, 0.8)
    }
    case 'scrap': {
      // 一块块拼起来的板：铁皮、锈板、刷了绿漆的板、木板，板缝发黑
      const row = Math.floor(j / 5),
        off = Math.floor(hash(row, 2, seed) * 7),
        col = Math.floor((i + off) / 7)
      if ((i + off) % 7 === 0 || j % 5 === 0) return W.scrapSeam
      const k = Math.floor(hash(col, row, seed) * 4)
      const mats = [base, W.rust, ...W.scrapBoards]
      return mats[k][(i + j * (k & 1)) % 3]
    }
    case 'painted': {
      // 竖木板，四格一条板缝，每块板漆色略有深浅
      const paint = house.paint
      if (i % 4 === 3) return mixHex(paint[1], '#000000', 0.3)
      return paint[Math.floor(hash(i >> 2, Math.floor(j / 11), seed) * 3)]
    }
    default:
      return pick(base, noise(i / 6, j / 6, seed), i, j, style === 'plaster' ? 1.2 : 0.6)
  }
}

type Ctx = CanvasRenderingContext2D

/** 墙根会做旧的墙面 */
const WEATHERED = new Set<House['style']>([
  'plaster',
  'wood',
  'stone',
  'brick',
  'clean',
  'pastel',
  'painted',
])

/** 在画布上填一个矩形 */
function rect(ctx: Ctx, i: number, j: number, w: number, h: number, col: string) {
  ctx.fillStyle = col
  ctx.fillRect(i, j, w, h)
}

/** 墙面：材质底色，灰泥墙的木框架、刷漆木板的包边，墙脚石基、檐下阴影和冰柱 */
function paintWall(x: Ctx, house: House, len: number, hgt: number, mid: number) {
  const { style, seed, look } = house
  for (let j = 0; j < hgt; j++)
    for (let i = 0; i < len; i++) rect(x, i, j, 1, 1, wallColor(house, i, j))
  if (style === 'plaster') {
    x.fillStyle = house.walls.timber
    x.fillRect(0, 0, len, 1)
    x.fillRect(0, mid, len, 1)
    for (let i = 0; i < len; i += 14) x.fillRect(i, 0, 1, hgt)
    x.fillRect(len - 1, 0, 1, hgt)
  }
  if (style === 'painted') {
    // 两头和檐下的白色包边板
    x.fillStyle = house.walls.trim
    x.fillRect(0, 0, 2, hgt)
    x.fillRect(len - 2, 0, 2, hgt)
    x.fillRect(0, 2, len, 1)
  }
  // 墙根溅上的泥和水渍，石基往上几排成片发暗；铁皮、水泥这些墙自己画了锈和水渍
  if (WEATHERED.has(style))
    for (let j = hgt - 7; j < hgt - 3; j++)
      for (let i = 0; i < len; i++)
        if (noise(i / 4, j / 2, seed + 40) > 0.45 + (hgt - 3 - j) * 0.08)
          rect(x, i, j, 1, 1, 'rgba(48,36,24,.16)')
  // 墙脚石基、屋檐下的阴影
  for (let j = hgt - 3; j < hgt; j++)
    for (let i = 0; i < len; i++)
      rect(x, i, j, 1, 1, (i + j) % 4 === 0 ? '#5f5a52' : j === hgt - 3 ? '#8a8478' : '#77716a')
  x.fillStyle = 'rgba(20,16,12,.35)'
  x.fillRect(0, 0, len, 2)
  // 屋檐下一排冰柱，长短不齐，尖上最亮
  if (look.icicles)
    for (let i = 1; i < len - 1; i += 2) {
      const n = Math.floor(hash(i, 3, seed) * 5)
      for (let k = 0; k < n; k++) rect(x, i, k, 1, 1, k === n - 1 ? '#f4fbff' : ICE)
    }
}

/** 南墙上的门，dx 是门左边；返回门（连两侧的柱子）占的横向范围，窗和招牌避开它 */
function paintDoor(x: Ctx, house: House, dx: number, top: number, hgt: number) {
  const { look } = house
  const [width] = DOORS[look.door]
  const tall = hgt - top
  const paint = house.doorPaint ?? '#6b4630'
  rect(x, dx - 1, top - 1, width + 2, tall + 1, FRAME)
  rect(x, dx - 2, top - 2, width + 4, 1, FRAME)
  rect(x, dx, top, width, tall, look.door === 'barn' ? '#7a5438' : paint)
  const mid = dx + Math.floor(width / 2)
  if (look.door === 'barn') {
    // 谷仓门：外框加 X 形斜撑
    for (let k = 0; k < tall; k++) {
      const a = Math.round((k / tall) * (width - 1))
      rect(x, dx + a, top + k, 1, 1, '#4e3424')
      rect(x, dx + width - 1 - a, top + k, 1, 1, '#4e3424')
    }
    rect(x, mid, top, 1, tall, '#4e3424')
  } else if (look.door !== 'single') {
    rect(x, mid, top, 1, tall, '#4e3424')
    rect(x, mid - 2, top + Math.floor(tall / 2), 1, 1, '#e0b060')
    rect(x, mid + 2, top + Math.floor(tall / 2), 1, 1, '#e0b060')
  } else {
    rect(x, dx + 3, top, 1, tall, mixHex(paint, '#000000', 0.2))
    rect(x, dx + 1, top + 2, 1, tall - 4, mixHex(paint, '#ffffff', 0.12))
    rect(x, dx + 5, top + Math.floor(tall / 2), 1, 1, '#e0b060')
  }
  if (look.door !== 'grand') return [dx - 3, dx + width + 3]
  // 门两侧的柱子和门前台阶
  for (const px of [dx - 4, dx + width + 2])
    for (let j = top - 3; j < hgt - 2; j++)
      rect(x, px, j, 2, 1, j === top - 3 ? '#e2ddd0' : '#cfc9bb')
  rect(x, dx - 5, hgt - 2, width + 10, 1, '#d8d2c4')
  rect(x, dx - 6, hgt - 1, width + 12, 1, '#b9b3a4')
  return [dx - 7, dx + width + 7]
}

/** 墙面与夜里发光的窗户；door 是门中心离墙左端的像素数。
 *  按房子的功能画不同的窗、门和招牌 */
export function wallCanvases(house: House, len: number, door?: number) {
  const { wallTexels: hgt, look } = house
  const c = canvas(len, hgt),
    x = c.getContext('2d')!
  const e = canvas(len, hgt),
    ex = e.getContext('2d')!
  const mid = Math.round(hgt * 0.45)
  paintWall(x, house, len, hgt, mid)
  // 夜里墙面自带一点微光：发光图先铺一层压暗的墙面，窗户和灯再画成亮色
  ex.drawImage(c, 0, 0)
  ex.fillStyle = `rgba(0,0,0,${1 - WALL_NIGHT_GLOW})`
  ex.fillRect(0, 0, len, hgt)
  const [width, doorH] = DOORS[look.door]
  const top = hgt - Math.min(hgt - 5, doorH)
  let span: number[]
  if (door !== undefined) {
    const dx = Math.max(3, Math.min(len - width - 3, Math.round(door - width / 2)))
    span = paintDoor(x, house, dx, top, hgt)
    signs(x, ex, look, dx, width, top, len)
  } else {
    // 门开在看不见的一面：招牌和徽章仍画在朝镜头这面墙的中间，一眼认得出是什么房子
    const dx = Math.round(len / 2 - width / 2)
    signs(x, ex, look, dx, width, top, len)
    span = [dx - 3, dx + width + (look.sign && look.sign !== 'emblem' ? 13 : 3)]
  }
  const free = (a: number, b: number) => b < span[0] || a > span[1]
  windows(x, ex, house, len, hgt, mid, free)
  return { map: c, emissive: e }
}

/** 画一种窗用到的东西：墙面画布 x、夜里发光的画布 ex，
 *  glass 画一扇带框的玻璃窗（夜里亮），row 沿墙等距排一排、避开门 */
interface WindowPen {
  x: Ctx
  ex: Ctx
  house: House
  hgt: number
  mid: number
  glass(i: number, j: number, w: number, h: number): void
  row(width: number, gap: number, y: number, draw: (i: number, y: number) => void): void
}

/** 窗下：有花的风格放花箱（花色按房子和窗的位置错开），否则一道窗台 */
function sill(p: WindowPen, i: number, wy: number, w: number) {
  const { x, house } = p
  if (!house.look.flowers) return rect(x, i - 1, wy, w + 2, 1, '#d8cdb4')
  rect(x, i - 1, wy + 1, w + 2, 2, '#6b4a32')
  for (let k = 0; k < w + 2; k++)
    rect(
      x,
      i - 1 + k,
      wy,
      1,
      1,
      k % 2 ? '#4f7a45' : house.flowers[(k + i + house.seed) % house.flowers.length]
    )
}

/** 带百叶的窗，rows 是上下两排（旅舍、酒店）；flowers 时窗下有花箱 */
function shutterWindows(p: WindowPen, rows: boolean) {
  const { x, ex, house, hgt } = p
  const shutter = ['#4f6f5a', '#6a4a5a', '#4a5f78', '#7a5a3a'][house.seed % 4]
  const draw = (i: number, wy: number) => {
    p.glass(i, wy, 5, 6)
    rect(x, i + 2, wy, 1, 6, FRAME)
    rect(x, i, wy + 3, 5, 1, FRAME)
    rect(ex, i + 2, wy, 1, 6, '#000')
    rect(x, i - 3, wy, 2, 6, shutter)
    rect(x, i + 6, wy, 2, 6, shutter)
    sill(p, i, wy + 6, 5)
  }
  if (rows) {
    p.row(5, 13, Math.round(hgt * 0.18), draw)
    p.row(5, 13, Math.round(hgt * 0.52), draw)
  } else p.row(5, 15, p.mid - 6, draw)
}

/** 拱窗：去掉上面两个角，露出墙面 */
function archedWindows(p: WindowPen) {
  const { x, ex, house, hgt } = p
  p.row(5, 11, Math.round(hgt * 0.24), (i, wy) => {
    p.glass(i, wy, 5, 10)
    for (const [a, b] of [
      [-1, -1],
      [0, -1],
      [-1, 0],
      [4, -1],
      [5, -1],
      [5, 0],
    ])
      rect(x, i + a, wy + b, 1, 1, wallColor(house, i + a, wy + b))
    rect(ex, i, wy, 1, 1, '#000')
    rect(ex, i + 4, wy, 1, 1, '#000')
    rect(x, i + 2, wy, 1, 10, FRAME)
    rect(ex, i + 2, wy, 1, 10, '#000')
    rect(x, i - 1, wy + 11, 7, 1, '#d8d2c4')
  })
}

/** 橱窗（shop）和宽窗（wide）：一排竖棂 */
function wideWindows(p: WindowPen, shop: boolean) {
  const { x, ex, hgt } = p
  const w = shop ? 11 : 8
  p.row(w, w + 6, hgt - (shop ? 13 : 14), (i, wy) => {
    p.glass(i, wy, w, shop ? 9 : 6)
    for (let k = 3; k < w; k += 4) {
      rect(x, i + k, wy, 1, 9, FRAME)
      rect(ex, i + k, wy, 1, 9, '#000')
    }
    rect(x, i - 1, wy + (shop ? 10 : 7), w + 2, 1, '#d8cdb4')
  })
}

/** 结霜的窗：白窗框十字棂，窗角结霜，窗台上积一层雪 */
function frostWindows(p: WindowPen) {
  const { x, ex } = p
  p.row(5, 14, p.mid - 6, (i, wy) => {
    p.glass(i, wy, 5, 6)
    for (const [a, b, w, h] of [
      [-1, -1, 7, 1],
      [-1, 6, 7, 1],
      [-1, -1, 1, 8],
      [5, -1, 1, 8],
      [2, 0, 1, 6],
      [0, 3, 5, 1],
    ]) {
      rect(x, i + a, wy + b, w, h, '#ece8e0')
      rect(ex, i + a, wy + b, w, h, '#000')
    }
    for (const [a, b] of [
      [0, 0],
      [4, 0],
      [0, 5],
    ])
      rect(x, i + a, wy + b, 1, 1, '#d8ecf6')
    rect(x, i - 2, wy + 7, 9, 1, SNOW)
    rect(x, i - 2, wy + 8, 9, 1, SNOW_SHADE)
  })
}

/** 一部分窗钉死了木板，夜里不亮；其余是加了铁栏的脏玻璃 */
function boardedWindows(p: WindowPen) {
  const { x, ex } = p
  const { seed, walls } = p.house
  // 钉在窗上的木板和拼板墙的木板同色
  const boards = walls.scrapBoards[1]
  p.row(5, 13, p.mid - 6, (i, wy) => {
    if (hash(i, wy, seed + 3) < 0.45) {
      rect(x, i - 1, wy - 1, 7, 8, '#2a2622')
      for (let k = 0; k < 3; k++)
        rect(x, i - 1, wy + k * 2 + (k ? 1 : 0), 7, 2, boards[(k + seed) % boards.length])
      for (let k = 0; k < 7; k++) rect(x, i - 1 + k, wy + 5 - Math.round(k * 0.7), 1, 1, '#5e452c')
      return
    }
    p.glass(i, wy, 5, 6)
    for (const b of [1, 3]) {
      rect(x, i + b, wy, 1, 6, '#3a3632')
      rect(ex, i + b, wy, 1, 6, '#000')
    }
    rect(x, i, wy + 4, 5, 2, 'rgba(96,74,44,.55)')
    rect(x, i - 1, wy + 7, 7, 1, '#6a655c')
  })
}

/** 不带百叶的双扇窗：白窗框，中间一道竖棂、上面一道横棂 */
function casementWindows(p: WindowPen) {
  const { x, ex } = p
  p.row(7, 14, p.mid - 6, (i, wy) => {
    p.glass(i, wy, 7, 6)
    for (const [a, b, w, h] of [
      [-1, -1, 9, 1],
      [-1, -1, 1, 8],
      [7, -1, 1, 8],
      [3, 0, 1, 6],
      [0, 2, 7, 1],
    ]) {
      rect(x, i + a, wy + b, w, h, '#efe9dc')
      rect(ex, i + a, wy + b, w, h, '#000')
    }
    sill(p, i, wy + 7, 7)
  })
}

const WINDOWS: Record<WindowKind, (p: WindowPen) => void> = {
  shutter: (p) => shutterWindows(p, false),
  casement: casementWindows,
  rows: (p) => shutterWindows(p, true),
  plain: (p) =>
    p.row(5, 11, p.mid - 5, (i, wy) => {
      p.glass(i, wy, 5, 7)
      rect(p.x, i - 1, wy - 1, 7, 1, '#f6f4ee')
      rect(p.x, i - 1, wy + 7, 7, 1, '#f6f4ee')
      rect(p.x, i + 2, wy, 1, 7, '#f6f4ee')
      rect(p.ex, i + 2, wy, 1, 7, '#000')
    }),
  tall: (p) =>
    p.row(5, 13, Math.round(p.hgt * 0.22), (i, wy) => {
      p.glass(i, wy, 5, 10)
      rect(p.x, i, wy + 4, 5, 1, FRAME)
      rect(p.x, i - 2, wy + 11, 9, 1, '#d8d2c4')
      rect(p.x, i - 1, wy - 2, 7, 1, '#d8d2c4')
    }),
  arched: archedWindows,
  shop: (p) => wideWindows(p, true),
  wide: (p) => wideWindows(p, false),
  high: (p) => p.row(4, 12, 4, (i, wy) => p.glass(i, wy, 4, 3)),
  frost: frostWindows,
  boarded: boardedWindows,
}

/** 窗：按功能挑样式，沿墙等距排开，避开门 */
function windows(
  x: Ctx,
  ex: Ctx,
  house: House,
  len: number,
  hgt: number,
  mid: number,
  free: (a: number, b: number) => boolean
) {
  WINDOWS[house.windows]({
    x,
    ex,
    house,
    hgt,
    mid,
    glass(i, j, w, h) {
      // 砖墙、石墙的窗上压一道浅色石窗楣
      if ((house.style === 'brick' || house.style === 'stone') && house.windows !== 'arched')
        rect(x, i - 2, j - 2, w + 4, 1, '#d2c9b5')
      rect(x, i - 1, j - 1, w + 2, h + 2, FRAME)
      rect(x, i, j, w, h, GLASS)
      rect(x, i, j, Math.min(2, w), Math.min(2, h), GLASS_LIGHT)
      rect(ex, i, j, w, h, LIT)
    },
    row(width, gap, y, draw) {
      for (let i = 5; i + width + 4 < len; i += gap) if (free(i - 2, i + width + 2)) draw(i, y)
    },
  })
}

/** 招牌的位置：(sx, sy) 是门右上方（放不下就在左边），dx、width、top 是门 */
interface SignPlace {
  x: Ctx
  ex: Ctx
  sx: number
  sy: number
  dx: number
  width: number
  top: number
}

const SIGNS: Record<NonNullable<House['look']['sign']>, (s: SignPlace) => void> = {
  cross: ({ x, ex, sx, sy }) => {
    rect(x, sx, sy, 9, 9, '#f6f4ee')
    rect(x, sx, sy, 9, 1, '#c9c3b4')
    rect(x, sx + 3, sy + 1, 3, 7, '#c8453b')
    rect(x, sx + 1, sy + 3, 7, 3, '#c8453b')
    rect(ex, sx + 3, sy + 1, 3, 7, '#9a2a24')
    rect(ex, sx + 1, sy + 3, 7, 3, '#9a2a24')
  },
  book: ({ x, sx, sy }) => {
    rect(x, sx, sy, 9, 7, '#5a3f2c')
    rect(x, sx + 1, sy + 1, 3, 5, '#f1ead8')
    rect(x, sx + 5, sy + 1, 3, 5, '#f1ead8')
    rect(x, sx + 4, sy + 1, 1, 5, '#8e3f33')
    rect(x, sx + 2, sy + 3, 1, 1, '#9a9080')
    rect(x, sx + 6, sy + 3, 1, 1, '#9a9080')
  },
  hammer: ({ x, sx, sy }) => {
    rect(x, sx, sy, 9, 7, '#5a3f2c')
    rect(x, sx + 4, sy + 2, 1, 4, '#c9a46e')
    rect(x, sx + 2, sy + 1, 5, 2, '#9aa0a8')
  },
  // 从墙上伸出的铁架挂一块木牌
  inn: ({ x, sx, sy }) => {
    rect(x, sx, sy - 1, 8, 1, '#2b282c')
    rect(x, sx + 1, sy, 1, 1, '#2b282c')
    rect(x, sx + 6, sy, 1, 1, '#2b282c')
    rect(x, sx, sy + 1, 8, 6, '#7a5438')
    rect(x, sx + 1, sy + 2, 6, 4, '#c9a04e')
    rect(x, sx + 3, sy + 3, 2, 2, '#7a5438')
  },
  // 剧院：一白一金两张面具
  mask: ({ x, sx, sy }) => {
    rect(x, sx, sy, 11, 8, '#5a2a2e')
    rect(x, sx + 1, sy + 1, 4, 5, '#f4efe4')
    rect(x, sx + 6, sy + 2, 4, 5, '#e0b850')
    rect(x, sx + 2, sy + 2, 1, 1, '#2b282c')
    rect(x, sx + 7, sy + 3, 1, 1, '#2b282c')
    rect(x, sx + 2, sy + 4, 2, 1, '#c8453b')
    rect(x, sx + 7, sy + 5, 2, 1, '#8a5a20')
  },
  // 门上方的圆形徽章
  emblem: ({ x, dx, width, top }) => {
    const cx = dx + Math.floor(width / 2) - 3
    const cy = Math.max(2, top - 9)
    rect(x, cx + 1, cy, 5, 7, '#c9a04e')
    rect(x, cx, cy + 1, 7, 5, '#c9a04e')
    rect(x, cx + 2, cy + 1, 3, 5, '#44566e')
    rect(x, cx + 1, cy + 2, 5, 3, '#44566e')
    rect(x, cx + 3, cy + 3, 1, 1, '#e8d9a8')
  },
}

/** 门边的招牌和灯 */
function signs(
  x: Ctx,
  ex: Ctx,
  look: House['look'],
  dx: number,
  width: number,
  top: number,
  len: number
) {
  // 招牌放在门右上方，放不下就放左边
  const right = dx + width + 3
  const sx = right + 9 < len ? right : Math.max(1, dx - 12)
  const sy = Math.max(3, top - 3)
  if (look.sign) SIGNS[look.sign]({ x, ex, sx, sy, dx, width, top })
  if (look.lanterns)
    for (const lx of [dx - 3, dx + width + 2]) {
      rect(x, lx, top + 1, 2, 1, '#2b282c')
      rect(x, lx, top + 2, 2, 3, LAMP_GLOW)
      rect(ex, lx, top + 2, 2, 3, LAMP_GLOW)
    }
}

/** 屋面：画布底边是屋檐，顶边是屋脊；按房子的屋面材质画 */
export function roofCanvas(len: number, slope: number, house: House) {
  if (house.roofing === 'tin') return tinRoofCanvas(len, slope, house)
  if (house.roofing === 'snow') return snowRoofCanvas(len, slope, house)
  const c = canvas(len, slope),
    x = c.getContext('2d')!
  const paint =
    house.roofing === 'slate' ? slateColor : house.roofing === 'shingle' ? shingleColor : tileColor
  for (let j = 0; j < slope; j++)
    for (let i = 0; i < len; i++) {
      const up = slope - 1 - j
      let col = paint(house, i, up, slope)
      // 青苔：檐口几排成片长，越往上越少；零星几点散在整片屋面上
      if (noise(i / 6, j / 3, house.seed + 21) > 0.66 + (up / slope) * 0.6)
        col = mixHex(col, MOSS[Math.floor(hash(i, j, house.seed + 22) * 2)], 0.55)
      else if (hash(i, j, house.seed + 9) < 0.02) col = mixHex(col, MOSS[0], 0.5)
      x.fillStyle = col
      x.fillRect(i, j, 1, 1)
    }
  ridgeCap(x, len, house.roof)
  x.fillStyle = mixHex(house.roof[2], '#000000', 0.3)
  x.fillRect(0, slope - 1, len, 1)
  return c
}

const MOSS = ['#6f7a4a', '#5d6a3e']

/** 每片瓦在主色和亮色之间挑一种，少数几片偏深或偏浅；up 是从屋檐往上数的行，slope 是总行数 */
function tileColor(house: House, i: number, up: number) {
  const pal = house.roof
  const row = Math.floor(up / 3),
    off = (row & 1) * 2,
    tile = Math.floor((i + off) / 4)
  if (up % 3 === 2) return pal[2]
  let col = pal[Math.floor(hash(tile, row, house.seed) * 2)]
  const t = hash(tile, row, house.seed + 17)
  if (t < 0.12) col = mixHex(col, '#000000', 0.12)
  else if (t > 0.9) col = mixHex(col, '#ffffff', 0.1)
  return (i + off) % 4 === 0 ? mixHex(col, pal[2], 0.5) : col
}

/** 石板瓦：两排一层、六格一片，片间缝深；零星几片新换的发亮，几片长了灰白的地衣 */
function slateColor(house: House, i: number, up: number) {
  const pal = house.roof
  const row = up >> 1,
    off = (row & 1) * 3,
    tile = Math.floor((i + off) / 6)
  if (up % 2 === 1) return mixHex(pal[1], pal[2], 0.6)
  if ((i + off) % 6 === 0) return pal[2]
  const t = hash(tile, row, house.seed + 23)
  if (t < 0.06) return mixHex(pal[0], '#ffffff', 0.12)
  if (t > 0.95) return mixHex(pal[1], '#b8b49a', 0.4)
  return mixHex(pal[0], pal[1], hash(tile, row, house.seed + 24) * 0.8)
}

/** 木瓦：两排一层，宽窄不一的木片，色差大；越靠屋脊晒得越灰 */
function shingleColor(house: House, i: number, up: number, slope: number) {
  const pal = house.roof
  const row = up >> 1,
    off = Math.floor(hash(row, 3, house.seed) * 3),
    tile = Math.floor((i + off) / 3)
  if (up % 2 === 1) return pal[2]
  if ((i + off) % 3 === 0 && hash(tile, row, house.seed + 25) < 0.7)
    return mixHex(pal[1], pal[2], 0.7)
  const col = pal[Math.floor(hash(tile, row, house.seed + 26) * 2)]
  const t = hash(tile, row, house.seed + 27)
  return mixHex(t < 0.2 ? mixHex(col, '#000000', 0.12) : col, '#9a948a', 0.05 + 0.2 * (up / slope))
}

/** 屋脊压一道脊瓦：最上一排隔几格一个亮点，下面一排阴影 */
function ridgeCap(x: Ctx, len: number, pal: readonly string[]) {
  x.fillStyle = pal[2]
  x.fillRect(0, 0, len, 2)
  x.fillStyle = mixHex(pal[2], '#ffffff', 0.22)
  for (let i = 0; i < len; i += 3) x.fillRect(i, 0, 2, 1)
  x.fillStyle = mixHex(pal[2], '#000000', 0.25)
  x.fillRect(0, 2, len, 1)
}

/** 山墙面：墙面材质铺满，灰泥墙底边压一道木梁，斜边下一道屋檐阴影；
 *  peak 是顶上三角部分占的行数（其余是矩形墙），opening 是老虎窗的小窗、山墙上的圆窗或不开窗。
 *  和墙面一样另有一张夜里发光的图 */
export function gableCanvases(
  house: House,
  len: number,
  hgt: number,
  peak: number,
  opening: 'none' | 'round' | 'dormer'
) {
  const c = canvas(len, hgt),
    x = c.getContext('2d')!
  const e = canvas(len, hgt),
    ex = e.getContext('2d')!
  for (let j = 0; j < hgt; j++)
    for (let i = 0; i < len; i++) rect(x, i, j, 1, 1, wallColor(house, i, j))
  const mid = len / 2
  if (house.style === 'plaster') {
    x.fillStyle = house.walls.timber
    x.fillRect(0, hgt - 1, len, 1)
  }
  // 斜边内侧两个像素压暗：屋檐投下的影子
  x.fillStyle = 'rgba(20,16,12,.35)'
  for (let j = 0; j < Math.min(peak, hgt); j++) {
    const half = (mid * (j + 0.5)) / peak
    x.fillRect(Math.floor(mid - half), j, 2, 1)
    x.fillRect(Math.ceil(mid + half) - 2, j, 2, 1)
  }
  ex.drawImage(c, 0, 0)
  ex.fillStyle = `rgba(0,0,0,${1 - WALL_NIGHT_GLOW})`
  ex.fillRect(0, 0, len, hgt)
  const pane = (i: number, j: number, w: number, h: number) => {
    rect(x, i - 1, j - 1, w + 2, h + 2, FRAME)
    rect(x, i, j, w, h, GLASS)
    rect(x, i, j, 1, 1, GLASS_LIGHT)
    rect(ex, i, j, w, h, LIT)
  }
  if (opening === 'round' && peak >= 7 && len >= 7) {
    const i = Math.round(mid) - 1,
      j = Math.round(peak * 0.5)
    pane(i, j, 3, 3)
    for (const [a, b] of [
      [-1, -1],
      [3, -1],
      [-1, 3],
      [3, 3],
    ])
      rect(x, i + a, j + b, 1, 1, wallColor(house, i + a, j + b))
  }
  if (opening === 'dormer') {
    const w = Math.max(3, len - 4),
      i = Math.round(mid - w / 2)
    pane(i, peak + 1, w, Math.max(2, hgt - peak - 4))
    rect(x, Math.round(mid), peak + 1, 1, Math.max(2, hgt - peak - 4), FRAME)
    rect(ex, Math.round(mid), peak + 1, 1, Math.max(2, hgt - peak - 4), '#000')
  }
  return { map: c, emissive: e }
}

/** 波纹铁皮屋面：波纹顺着坡往下，一张张铁皮有接缝；成片生锈，有几张换过的新铁皮，偶尔一个破洞 */
function tinRoofCanvas(len: number, slope: number, house: House) {
  const [hi, mid, lo] = house.roof
  const c = canvas(len, slope),
    x = c.getContext('2d')!
  for (let j = 0; j < slope; j++)
    for (let i = 0; i < len; i++) {
      const sheet = Math.floor(i / 12),
        band = Math.floor((j + sheet * 3) / 9)
      const fresh = hash(sheet, band, house.seed + 11) < 0.07
      const ribs = fresh ? ['#b0b4ae', '#9a9e98', '#7e827c'] : [hi, mid, mixHex(mid, lo, 0.5)]
      let col = ribs[i % 3]
      if ((j + sheet * 3) % 9 === 0 || i % 12 === 0) col = lo
      else if (!fresh && noise(i / 3, j / 3, house.seed + 12) > 0.72)
        col = house.walls.rust[Math.floor(hash(i, j, house.seed) * 3)]
      if (hash(i, j, house.seed + 13) < 0.003) col = '#2a2420'
      x.fillStyle = col
      x.fillRect(i, j, 1, 1)
    }
  x.fillStyle = lo
  x.fillRect(0, 0, len, 2)
  for (let i = 1; i < len; i += 4) {
    x.fillStyle = hi
    x.fillRect(i, 0, 1, 1)
  }
  x.fillStyle = mixHex(lo, '#000000', 0.35)
  x.fillRect(0, slope - 1, len, 1)
  return c
}

/** 积雪的屋面：整片是厚雪，起伏处发蓝；雪薄的地方零星露出瓦，屋檐是一道翻出来的雪沿，下面压着深色檐板 */
function snowRoofCanvas(len: number, slope: number, house: House) {
  const c = canvas(len, slope),
    x = c.getContext('2d')!
  const tones = ['#c2d0de', '#d4dee8', '#e4ebf2', SNOW]
  for (let j = 0; j < slope; j++)
    for (let i = 0; i < len; i++) {
      const up = slope - 1 - j
      let col = pick(tones, 0.6 + (noise(i / 4, j / 3, house.seed) - 0.5) * 0.5, i, j)
      if (up > 3 && hash(i, j, house.seed + 5) < 0.004) col = mixHex(house.roof[0], tones[0], 0.5)
      x.fillStyle = col
      x.fillRect(i, j, 1, 1)
    }
  x.fillStyle = '#b4c2d2'
  x.fillRect(0, 0, len, 1)
  // 屋檐：雪沿往外翻，雪沿下露一条深色檐板
  x.fillStyle = '#f8fbfd'
  x.fillRect(0, slope - 3, len, 2)
  x.fillStyle = '#3e4250'
  x.fillRect(0, slope - 1, len, 1)
  for (let i = 0; i < len; i += 3) {
    x.fillStyle = SNOW_GREY
    x.fillRect(i, slope - 1, 1, 1)
  }
  return c
}

/** 烟囱四面：石块错缝砌，颜色取风格包的石墙；高是贴图像素，最上几排熏黑 */
export function chimneyCanvas(house: House, hgt: number) {
  const { stone } = house.walls.shades
  const c = canvas(6, hgt),
    x = c.getContext('2d')!
  for (let j = 0; j < hgt; j++)
    for (let i = 0; i < 6; i++) {
      const row = j >> 1,
        off = (row & 1) * 3
      let col =
        j % 2 === 1 || (i + off) % 6 === 0
          ? house.walls.stoneMortar
          : stone[Math.floor(hash((i + off) >> 2, row, house.seed + 31) * 3)]
      if (j < 3) col = mixHex(col, '#2e2a26', 0.55 - j * 0.15)
      x.fillStyle = col
      x.fillRect(i, j, 1, 1)
    }
  return c
}

/** 雨棚：条纹沿墙排开，前沿一排扇形垂边 */
export function awningCanvas(len: number, colors: readonly [string, string]) {
  const c = canvas(len, 6),
    x = c.getContext('2d')!
  for (let i = 0; i < len; i++) {
    const col = colors[Math.floor(i / 3) % 2]
    x.fillStyle = col
    x.fillRect(i, 0, 1, 5)
    x.fillStyle = mixHex(col, '#000000', 0.25)
    x.fillRect(i, 0, 1, 1)
    if (i % 3 !== 2) {
      x.fillStyle = col
      x.fillRect(i, 5, 1, 1)
    }
  }
  return c
}

/** 旗子：两色横条；torn 时外沿撕成锯齿，中间一个破洞 */
export function flagCanvas(flag: MapTheme['flag']) {
  const c = canvas(10, 6),
    x = c.getContext('2d')!
  x.fillStyle = flag.colors[0]
  x.fillRect(0, 0, 10, 6)
  x.fillStyle = flag.colors[1]
  x.fillRect(0, 2, 10, 2)
  if (flag.torn) {
    for (let j = 0; j < 6; j++) x.clearRect(10 - [1, 3, 2, 4, 1, 3][j], j, 4, 1)
    x.clearRect(4, 3, 1, 2)
  }
  return c
}

/** 立起来的树：与平面图同一套树冠画法，底边中点是树根 */
export function treeCanvas(
  r: number,
  variant: number,
  bush: boolean,
  seed: number,
  flora: MapTheme['flora']
) {
  const w = 2 * r + 5,
    h = bush ? 2 * r + 4 : 2 * r + 8
  const c = canvas(w, h),
    ctx = c.getContext('2d')!
  const img = ctx.createImageData(w, h)
  const px = new Uint32Array(img.data.buffer)
  const put = (x: number, y: number, v: number) => {
    x = Math.round(x)
    y = Math.round(y)
    if (x >= 0 && y >= 0 && x < w && y < h) px[y * w + x] = v
  }
  tree(Math.floor(w / 2), h - 1, r, variant, bush, seed, flora, put, () => {})
  ctx.putImageData(img, 0, 0)
  return c
}

/** 路灯：灯杆与灯罩；glass 为 true 时只画发光的玻璃。废土的是木杆横担上吊一只灯泡，杆脚压几块石头 */
export function lampCanvas(glass: boolean, kind: MapTheme['lamp'] = 'street') {
  const c = canvas(7, 28),
    x = c.getContext('2d')!
  if (kind === 'scrap') {
    if (!glass) {
      x.fillStyle = '#5a4430'
      x.fillRect(4, 3, 1, 23)
      x.fillStyle = '#6e5840'
      x.fillRect(5, 3, 1, 23)
      x.fillRect(0, 3, 7, 1)
      x.fillStyle = '#2b282c'
      x.fillRect(1, 4, 1, 3)
      x.fillStyle = '#7a756c'
      x.fillRect(2, 26, 5, 2)
      x.fillRect(3, 25, 3, 1)
    }
    x.fillStyle = '#ffb060'
    x.fillRect(0, 7, 3, 2)
    x.fillRect(1, 9, 1, 1)
    return c
  }
  if (!glass) {
    x.fillStyle = '#2b282c'
    x.fillRect(3, 7, 1, 20)
    x.fillRect(1, 26, 5, 2)
    x.fillRect(1, 1, 5, 1)
    x.fillRect(0, 6, 7, 1)
    x.fillRect(1, 1, 1, 6)
    x.fillRect(5, 1, 1, 6)
  }
  x.fillStyle = LAMP_GLOW
  x.fillRect(2, 2, 3, 4)
  return c
}

export function glowCanvas() {
  const c = canvas(64, 64),
    x = c.getContext('2d')!
  const g = x.createRadialGradient(32, 32, 0, 32, 32, 32)
  g.addColorStop(0, 'rgba(255,220,150,1)')
  g.addColorStop(0.25, 'rgba(255,190,110,.55)')
  g.addColorStop(1, 'rgba(255,170,90,0)')
  x.fillStyle = g
  x.fillRect(0, 0, 64, 64)
  return c
}
