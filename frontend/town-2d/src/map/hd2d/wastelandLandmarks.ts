import { hash, mixHex, noise, rng } from '../pixel/noise'
import {
  carousel,
  dockGoods,
  ferrisWheel,
  gazebo,
  obelisk,
  roseArch,
  temple,
  type Flipbook,
  type LandmarkSet,
} from './landmarks'
import { sprite, wear } from './sprite'
import { stall } from './stalls'
import { boatModel } from './boats'
import { WALL_COLORS } from '../themes/walls'

// 末日废土的户外立牌。原作的地标都还在，只是锈了、褪色了、缺了几块；
// 喷泉干了（立体的，见 fountain.ts），市集是篷布摊和油桶火盆，港口有锈吊机和集装箱，栈桥边搁浅着锈船。
// 镇外的荒地上散落轮胎、油桶、废车；干海床上有沉船、船锚、浮标、鱼骨、牛头骨和倒毙的骆驼。
// 地图还能按坐标立（Atlas 的 standees）：火盆、霓虹招牌、褪色广告牌、一辆辆废车、废车场、
// 碎水泥堆、鲸骨，和蹲在骨头边、楼顶上的秃鹫。

const RUST = WALL_COLORS.rust
const rust = (x: number, y: number, seed: number) => RUST[Math.floor(hash(x, y, seed) * 3)]

/** 港口的锈吊机：格构塔身，顶上一根横臂，吊钩还垂着 */
function crane() {
  return sprite(64, 84, ({ px, rect, line }) => {
    const x0 = 10
    for (let y = 18; y < 80; y++) {
      px(x0, y, '#8a4a24')
      px(x0 + 10, y, '#6e3a1e')
      if (y % 8 === 0) line(x0, y, x0 + 10, y, '#7a4220')
      if (y % 8 === 4) line(x0, y - 4, x0 + 10, y + 4, '#7a4220')
    }
    // 司机室
    rect(x0 - 3, 10, 16, 9, '#a0784e')
    rect(x0 - 3, 10, 16, 1, '#c09a6a')
    rect(x0, 12, 6, 4, '#2a3236')
    px(x0 + 2, 13, '#8a9aa0')
    // 横臂和配重
    for (let x = x0 - 8; x < 62; x++) {
      px(x, 8, '#9a5a2e')
      px(x, 11, '#6e3a1e')
      if ((x - x0) % 6 === 0) line(x, 8, x + 3, 11, '#7a4220')
    }
    line(x0 + 5, 0, 60, 8, '#5a4a40')
    line(x0 + 5, 0, x0 - 8, 8, '#5a4a40')
    rect(x0 + 4, 0, 3, 8, '#8a4a24')
    rect(x0 - 10, 8, 6, 7, '#5e5a54')
    // 吊索和吊钩
    line(50, 12, 50, 44, '#3a3632')
    rect(48, 44, 5, 2, '#5e5a54')
    px(52, 46, '#5e5a54')
    px(51, 47, '#5e5a54')
    // 底座
    rect(x0 - 4, 80, 19, 4, '#7e7a72')
    rect(x0 - 4, 80, 19, 1, '#9a958c')
  })
}

/** 两层叠起来的集装箱，漆色各不相同，锈穿了几处 */
function containers(seed: number) {
  const paints = ['#8a3a2a', '#3e5e7a', '#4e6a4a', '#9a7a3a']
  return sprite(44, 26, ({ px }) => {
    const box = (x0: number, y0: number, w: number, h: number, k: number) => {
      const paint = paints[k % paints.length]
      for (let y = 0; y < h; y++)
        for (let x = 0; x < w; x++) {
          let c =
            x % 3 === 0
              ? mixHex(paint, '#000000', 0.3)
              : x % 3 === 1
                ? mixHex(paint, '#ffffff', 0.12)
                : paint
          if (y === 0) c = mixHex(paint, '#ffffff', 0.25)
          if (y === h - 1 || x === 0 || x === w - 1) c = mixHex(paint, '#000000', 0.45)
          if (noise((x0 + x) / 4, (y0 + y) / 3, seed + k) > 0.66) c = rust(x0 + x, y0 + y, seed)
          px(x0 + x, y0 + y, c)
        }
    }
    box(0, 13, 24, 13, seed)
    box(22, 13, 22, 13, seed + 1)
    box(6, 1, 24, 12, seed + 2)
  })
}

/** 搁浅的船：船身歪着坐在海床上，锈得发红，侧面破了个洞，桅杆斜着断了，底下积了一圈沙 */
function wreckBoat(seed: number) {
  const hull = ['#7a5236', '#6a4a36', '#5a5a52'][seed % 3]
  return sprite(40, 28, ({ px, rect, line }) => {
    line(15, 20, 26, 2, '#5a4030')
    line(16, 20, 27, 3, '#4a3428')
    for (let y = 16; y < 25; y++) {
      const inset = Math.round(((y - 16) / 9) * 5)
      const tilt = Math.round((y - 16) * 0.35)
      for (let x = inset; x < 38 - inset; x++) {
        const lift = Math.round((x / 38) * 3)
        let c =
          y === 16
            ? mixHex(hull, '#ffffff', 0.2)
            : x > 30 - inset
              ? mixHex(hull, '#000000', 0.3)
              : hull
        if (y === 19) c = '#b8b0a0'
        if (noise(x / 3, y / 2, seed) > 0.6) c = rust(x, y, seed)
        px(x + tilt - 2, y - lift, c)
      }
    }
    // 船侧的破洞
    rect(20, 18, 4, 3, '#1e1a16')
    px(24, 19, '#1e1a16')
    // 积沙
    for (let x = 2; x < 38; x++) {
      const h = 1 + Math.round(noise(x / 4, 0, seed) * 3)
      for (let k = 0; k < h; k++) px(x, 27 - k, k === h - 1 ? '#d8cdb0' : '#c9bb99')
    }
  })
}

/** 半埋在海床里的大船：一头只剩肋骨，一头还是完整的船壳 */
function shipwreck(seed: number) {
  return sprite(70, 32, ({ px, line }) => {
    for (let x = 0; x < 70; x++) {
      const top = 14 + Math.round(Math.abs(x - 40) / 8)
      if (x < 28) {
        // 肋骨
        if (x % 5 === 0)
          for (let y = top; y < 28; y++)
            px(x, y + Math.round(Math.sin((y - top) / 5) * 1.5), x % 10 ? '#6e5a48' : '#806a56')
        continue
      }
      for (let y = top; y < 28; y++) {
        let c = y === top ? '#8a7a66' : x > 60 ? '#4a3a2e' : y < top + 3 ? '#6a5a48' : '#5a4a3a'
        if (noise(x / 4, y / 3, seed) > 0.6) c = rust(x, y, seed)
        px(x, y, c)
      }
    }
    line(0, 27, 27, 25, '#6e5a48')
    // 船楼残骸
    for (let y = 6; y < 15; y++)
      for (let x = 46; x < 58; x++)
        px(x, y, y === 6 ? '#9a8a76' : (x + y) % 4 === 0 ? '#2a2420' : '#7a6a58')
    for (let x = 0; x < 70; x++) {
      const h = 2 + Math.round(noise(x / 5, 1, seed) * 3)
      for (let k = 0; k < h; k++) px(x, 31 - k, k === h - 1 ? '#d8cdb0' : '#c9bb99')
    }
  })
}

/** 一副大鱼骨：脊椎一条，两边弯弯的肋骨 */
function ribs() {
  return sprite(34, 14, ({ px, line }) => {
    line(1, 10, 32, 9, '#e0d8c4')
    for (let k = 0; k < 8; k++) {
      const x = 5 + k * 3.4
      const h = 7 - Math.abs(k - 3.5)
      for (let y = 0; y < h; y++)
        px(Math.round(x + Math.sin(y / 2) * 0.8), 9 - y, y === 0 ? '#c8c0aa' : '#ece4d0')
    }
    for (let y = 6; y < 12; y++)
      for (let x = 29; x < 34; x++) if (Math.hypot(x - 31, y - 9) < 3) px(x, y, '#d8d0bc')
    px(31, 8, '#3a3228')
  })
}

function anchor() {
  return sprite(12, 16, ({ px, rect, line }) => {
    rect(5, 2, 2, 11, '#5a4a40')
    rect(3, 3, 6, 1, '#5a4a40')
    for (let x = 1; x < 11; x++) px(x, 13 - Math.round(Math.abs(x - 5.5) * 0.6), '#6a584a')
    line(1, 10, 1, 13, '#6a584a')
    line(10, 10, 10, 13, '#6a584a')
    for (const [x, y] of [
      [5, 5],
      [6, 9],
      [4, 12],
    ])
      px(x, y, RUST[2])
    for (let x = 0; x < 12; x++) px(x, 15, '#c9bb99')
  })
}

/** 倒在海床上的浮标，漆掉了一半 */
function buoy(seed: number) {
  return sprite(12, 14, ({ px }) => {
    for (let y = 2; y < 12; y++)
      for (let x = 1; x < 11; x++) {
        if (Math.hypot(x - 5.5, (y - 7) * 1.1) > 5) continue
        let c = y < 7 ? '#a8463a' : '#c8c0b0'
        if (x > 7) c = mixHex(c, '#000000', 0.3)
        if (noise(x / 2, y / 2, seed) > 0.58) c = rust(x, y, seed)
        px(x, y, c)
      }
    for (let x = 0; x < 12; x++) px(x, 13, '#c9bb99')
  })
}

function tires(seed: number) {
  return sprite(12, 8, ({ px, rect }) => {
    const r = rng(seed)
    for (const [x, y] of [
      [0, 4],
      [5, 4],
      [2, 1],
    ].slice(0, 2 + Math.floor(r() * 2))) {
      rect(x + 1, y, 5, 4, '#1e1e1e')
      rect(x, y + 1, 7, 2, '#1e1e1e')
      rect(x + 2, y + 1, 3, 2, '#3a3a36')
      px(x + 1, y, '#3a3a36')
    }
  })
}

function drum(seed: number) {
  return sprite(6, 8, ({ px, rect }) => {
    for (let y = 1; y < 8; y++)
      for (let x = 0; x < 5; x++)
        px(
          x,
          y,
          y === 2 || y === 5 ? '#5a2a18' : x === 0 ? '#a55f2e' : x === 4 ? '#5a3020' : '#8a4a24'
        )
    rect(0, 0, 5, 1, hash(seed, 0, 1) < 0.5 ? '#3a3632' : '#8a4a24')
  })
}

function scrapHeap(seed: number) {
  const r = rng(seed)
  return sprite(20, 9, ({ px }) => {
    const mats = ['#5c6062', '#8a4a24', '#3a3632', '#4f6a5a', '#a3a7a5', '#6e3a1e', '#7a5a3a']
    for (let y = 0; y < 8; y++)
      for (let x = y + 1; x < 19 - y; x++)
        if (r() < 0.9) px(x, 8 - y, mats[Math.floor(r() * mats.length)])
  })
}

/** 趴窝的废车：没了轮子，车窗全碎，锈斑成片 */
function carWreck(seed: number) {
  const paint = ['#5a6a7a', '#8a7a4a', '#7a3a2a', '#6a6a62'][seed % 4]
  return sprite(22, 11, ({ px, rect }) => {
    for (let y = 5; y < 10; y++)
      for (let x = 0; x < 22; x++) {
        let c =
          y === 5 ? mixHex(paint, '#ffffff', 0.15) : y === 9 ? mixHex(paint, '#000000', 0.4) : paint
        if (noise(x / 3, y / 2, seed) > 0.56) c = rust(x, y, seed)
        px(x, y, c)
      }
    for (let y = 1; y < 5; y++)
      for (let x = 5 + (5 - y); x < 16 + Math.min(1, y - 1); x++)
        px(
          x,
          y,
          x === 10 || y === 1
            ? mixHex(paint, '#000000', 0.2)
            : (x + y) % 4 === 0
              ? '#8a9aa0'
              : '#2a3236'
        )
    rect(2, 10, 4, 1, '#1a1a1a')
    rect(16, 10, 4, 1, '#1a1a1a')
  })
}

/** 一张空画布 */
function blank(w: number, h: number) {
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  return canvas
}

/** 油桶火盆：锈红的油桶，两道箍，桶口窜着火苗（四帧轮着跳），夜里发光、照亮脚下一圈地 */
function fireBarrel(seed: number): Flipbook {
  const F = 4,
    w = 14,
    h = 24
  const canvas = blank(w * F, h),
    glow = blank(w * F, h)
  const c = canvas.getContext('2d')!,
    g = glow.getContext('2d')!
  const put = (ctx: CanvasRenderingContext2D, x: number, y: number, col: string) => {
    ctx.fillStyle = col
    ctx.fillRect(x, y, 1, 1)
  }
  for (let f = 0; f < F; f++) {
    const ox = f * w
    for (let y = 12; y < 24; y++)
      for (let x = 3; x < 11; x++) {
        let col = x === 3 ? '#b4683a' : x === 10 ? '#5a2e1c' : '#8a4a26'
        if (y === 15 || y === 20) col = '#5a2a18'
        if (hash(x, y, seed + 2) < 0.12) col = '#a0582e'
        put(c, ox + x, y, col)
      }
    for (let x = 3; x < 11; x++) put(c, ox + x, 12, '#3a2a20')
    // 火苗：每帧的形状和摆动不一样
    for (let y = 1; y < 13; y++)
      for (let x = 2; x < 12; x++) {
        const k = hash(x, y, seed * 7 + f * 13)
        const half = (13 - y) * 0.42 + 0.6 + (hash(y, f, seed + 5) - 0.5) * 1.6
        const dx = Math.abs(x + 0.5 - 7 - Math.sin((y + f * 2.3) * 0.9) * 0.9)
        if (dx > half || (y < 5 && k < 0.45)) continue
        const t = dx / Math.max(half, 0.1)
        const core = t < 0.35 && y > 6
        put(c, ox + x, y, core ? '#fff2b0' : t < 0.7 ? '#ffb040' : '#e8562a')
        put(g, ox + x, y, core ? '#fff6c8' : t < 0.7 ? '#ffb848' : '#ff6a30')
      }
    // 火光映着桶口，火星往上蹦
    for (let x = 4; x < 10; x++) put(g, ox + x, 12, '#ff9a40')
    for (let k = 0; k < 2; k++) {
      const x = 4 + Math.floor(hash(k, f, seed + 9) * 6),
        y = Math.floor(hash(k, f, seed + 11) * 3)
      put(c, ox + x, y, '#ffd070')
      put(g, ox + x, y, '#ffd070')
    }
  }
  return { canvas, glow, frames: F, fps: 7, light: { color: '#ff8a3a', reach: 300, power: 1.7 } }
}

/** 霓虹灯管的三种颜色：亮的光、白天不亮时的灯管、图案的芯 */
const NEON: Record<string, [string, string, string]> = {
  pink: ['#ff5fb4', '#e9c9d9', '#ff8ac8'],
  cyan: ['#45f2ff', '#c7e9ee', '#9af8ff'],
  yellow: ['#ffe14a', '#ece2b8', '#fff09a'],
  green: ['#5cff86', '#cbe9d0', '#a8ffc0'],
  red: ['#ff4a3a', '#ecc2ba', '#ff9a8a'],
}
/** 灯管图案：每个 10×10，# 是灯管 */
// prettier-ignore
const NEON_ICONS: Record<string, string[]> = {
  glass: ['##########', '.########.', '..######..', '...####...', '....##....', '....##....', '....##....', '....##....', '...####...', '.########.'],
  bowl: ['.#..#..#..', '..#..#..#.', '.#..#..#..', '..........', '##########', '#........#', '.#......#.', '..#....#..', '...####...', '..######..'],
  heart: ['..........', '.##....##.', '#..#..#..#', '#...##...#', '#........#', '.#......#.', '..#....#..', '...#..#...', '....##....', '..........'],
  star: ['....##....', '....##....', '...#..#...', '####..####', '.#......#.', '..#....#..', '..#.##.#..', '.#.#..#.#.', '.##....##.', '..........'],
  cross: ['...####...', '...#..#...', '...#..#...', '####..####', '#........#', '#........#', '####..####', '...#..#...', '...#..#...', '...####...'],
  bed: ['..........', '#.........', '#.##......', '#.##.#####', '#....#...#', '##########', '#........#', '#........#', '..........', '..........'],
  arrow: ['....#.....', '.....#....', '......#...', '##########', '......#...', '.....#....', '....#.....', '..........', '..........', '..........'],
  cup: ['..#..#....', '...#..#...', '..#..#....', '#######...', '#.....###.', '#.....#.#.', '#.....###.', '.#...#....', '..###.....', '#######...'],
}

/** 霓虹招牌：铁杆撑着一块黑底板，四边一圈灯管，中间几个灯管图案（横牌并排、竖牌上下摞）。
 *  白天灯管是灰白的，夜里发出颜色、把脚下一圈地染上色；坏了几截灯管不亮 */
function neonSign(icons: string[], color: string, seed: number, across = false): Flipbook {
  const [hot, cold, core] = NEON[color]
  const Z = 2
  const w = across ? 22 * icons.length + 8 : 28,
    h = across ? 30 : 22 * icons.length + 8,
    pole = across ? 24 : 30
  const glow = blank(w, h + pole)
  const gx = glow.getContext('2d')!
  const lit = (x: number, y: number, c: string, n = 1) => {
    gx.fillStyle = c
    gx.fillRect(x, y, n, n)
  }
  const canvas = sprite(w, h + pole, ({ px, rect }) => {
    // 横牌两根杆，竖牌一根
    for (const x0 of across ? [5, w - 8] : [13]) {
      rect(x0, h, 3, pole, '#4a4a50')
      rect(x0, h, 1, pole, '#6a6a72')
    }
    for (let y = 0; y < h; y++)
      for (let x = 0; x < w; x++) {
        let c = x < 2 ? '#3a3a46' : x > w - 3 ? '#1c1c24' : '#26262f'
        if (noise(x / 4, y / 4, seed + 3) > 0.74) c = '#4a3428'
        px(x, y, c)
      }
    const tube = (x: number, y: number) => {
      const dead = hash(x >> 2, y >> 2, seed + 17) < 0.08
      px(x, y, dead ? '#5a5a62' : cold)
      if (!dead) lit(x, y, hot)
    }
    for (let x = 2; x < w - 2; x++) {
      tube(x, 2)
      tube(x, h - 3)
    }
    for (let y = 2; y < h - 2; y++) {
      tube(2, y)
      tube(w - 3, y)
    }
    icons.forEach((name, k) => {
      const rows = NEON_ICONS[name]
      const ox = across ? 4 + k * 22 : 4,
        oy = across ? 5 : 6 + k * 22
      for (let y = 0; y < 10; y++)
        for (let x = 0; x < 10; x++)
          if (rows[y][x] === '#') {
            rect(ox + x * Z, oy + y * Z, Z, Z, cold)
            lit(ox + x * Z, oy + y * Z, core, Z)
          }
    })
  })
  return {
    canvas,
    glow,
    frames: 1,
    fps: 1,
    light: { color: hot, reach: 320, power: 1.6, on: 0.15 },
  }
}

/** 褪色的广告牌：画着蓝海、太阳和沙滩（海早就退了），一行大字掉了一个，几块板子掉了露出骨架；
 *  顶上两盏灯一盏还亮 */
function billboard(seed: number): Flipbook {
  const w = 100,
    bh = 46,
    legs = 56,
    H = bh + legs
  const glow = blank(w, H)
  const gx = glow.getContext('2d')!
  const canvas = sprite(w, H, ({ px, rect, line }) => {
    for (const x0 of [22, 74]) {
      rect(x0, bh, 4, legs, '#5a5a58')
      rect(x0, bh, 1, legs, '#7a7a76')
      for (let y = bh + 6; y < H - 4; y += 12) line(x0 + 4, y, x0 + 12, y + 10, '#4a4a48')
    }
    for (let y = 2; y < bh - 4; y++)
      for (let x = 2; x < w - 2; x++) {
        let c
        if (y < 20) c = mixHex('#7ab4d0', '#e8e0c8', y / 30)
        else if (y < 30) c = (x + y) % 7 === 0 ? '#a8d0e0' : '#3f86b0'
        else c = '#e2cc96'
        if (Math.hypot(x - 72, y - 14) < 7) c = '#f4c060'
        c = mixHex(c, '#d8cbb0', 0.35 + 0.25 * noise(x / 8, y / 6, seed))
        if (noise(x / 4, y / 4, seed + 5) > 0.76) c = mixHex(c, '#6a4a30', 0.5)
        px(x, y, c)
      }
    for (let k = 0; k < 5; k++) {
      if (k === 3) continue
      rect(10 + k * 9, 33, 7, 6, '#b8442e')
      rect(11 + k * 9, 34, 5, 4, '#e8d8b8')
    }
    for (const [x0, y0, ww, hh] of [
      [60, 24, 12, 16],
      [84, 4, 10, 12],
    ]) {
      rect(x0, y0, ww, hh, '#2a2622')
      line(x0, y0, x0 + ww - 1, y0 + hh - 1, '#5a5a58')
    }
    rect(0, 0, w, 2, '#4a4a48')
    rect(0, bh - 4, w, 4, '#3a3a38')
    rect(0, 0, 2, bh, '#4a4a48')
    rect(w - 2, 0, 2, bh, '#2a2a28')
    for (const lx of [26, 70]) rect(lx, bh - 6, 6, 3, '#6a6a66')
    gx.fillStyle = '#fff0c0'
    gx.fillRect(26, bh - 5, 6, 2)
  })
  return { canvas, glow, frames: 1, fps: 1, light: { color: '#ffe0a0', reach: 240, power: 0.8 } }
}

/** 骨头的三档颜色：向光的亮面、中间、背光 */
const bone = (t: number) => (t < 0.3 ? '#efe7d4' : t < 0.7 ? '#d8cdb2' : '#a89a7c')

/** 一副鲸骨：侧面，尾巴在左、头骨在右，肋骨一根根拱起来落到地上，有几根断了，下半截埋在沙里 */
function whaleSkeleton(seed: number) {
  const G = 61
  return sprite(200, 66, ({ px, rect, line }) => {
    const spineY = (x: number) =>
      x < 40
        ? 50 - (x - 6) * (20 / 34)
        : x < 150
          ? 30 - Math.sin(((x - 40) / 110) * Math.PI) * 6
          : 30 + (x - 150) * 0.3
    // 远侧的肋骨先画，暗一些
    for (let rx = 56; rx <= 142; rx += 6) {
      if (hash(rx, 3, seed) < 0.12) continue
      const y0 = Math.round(spineY(rx)) + 2
      const len = G - y0
      for (let k = 0; k <= len - 2; k++) {
        const t = k / len
        px(
          rx - 3 + Math.round(Math.sin(t * Math.PI) * 4) - Math.round(t * 2),
          y0 + k + 1,
          '#9a8e76'
        )
      }
    }
    // 脊椎一节一节，中段背上有棘突
    for (let x = 6; x < 158; x++) {
      if (x % 5 === 4) continue
      const y = Math.round(spineY(x))
      const size = x < 40 ? 1 + Math.round((x - 6) / 17) : 3
      for (let k = 0; k < size; k++) px(x, y + k, bone(k / size))
      if (x % 5 === 1 && x > 40 && x < 150) {
        px(x, y - 1, '#e6dec8')
        px(x, y - 2, '#d0c6aa')
      }
    }
    // 近侧的肋骨
    for (let rx = 58; rx <= 140; rx += 6) {
      const broken = hash(rx, 5, seed) < 0.18
      const y0 = Math.round(spineY(rx)) + 3
      const len = G - y0
      for (let k = 0; k <= (broken ? len * 0.55 : len); k++) {
        const t = k / len
        const x = rx + Math.round(Math.sin(t * Math.PI) * 5) - Math.round(t * 2)
        px(x, y0 + k, bone(0.15 + t * 0.55))
        px(x + 1, y0 + k, '#8e826a')
      }
    }
    // 头骨：圆顶加一截长长的上颌，下颌躺在地上
    for (let y = 17; y < 37; y++)
      for (let x = 154; x < 172; x++)
        if (Math.hypot(x - 163, y - 27) < 8.5) px(x, y, bone(((x - 154) / 18) * 0.7))
    for (let x = 166; x < 198; x++) {
      const y = Math.round(25 + (x - 166) * 0.42)
      const th = Math.max(1, 4 - Math.floor((x - 166) / 10))
      for (let k = 0; k < th; k++) px(x, y + k, bone(k / th))
    }
    for (let x = 156; x < 198; x++) {
      const y = Math.round(53 - Math.sin(((x - 156) / 42) * Math.PI) * 6)
      px(x, y, '#e6dec8')
      px(x, y + 1, '#c4b89e')
      px(x, y + 2, '#a89c84')
    }
    rect(159, 24, 3, 3, '#4e4436')
    // 鳍骨、掉在沙里的几节尾椎
    for (let k = 0; k < 4; k++) line(118 + k * 2, 49, 110 + k * 3, 58, '#cfc4aa')
    for (let k = 0; k < 4; k++) rect(2 + k * 4, 52 + (k % 2), 2, 2, '#d6ccb4')
    // 下半截埋在沙里
    for (let x = 30; x < 196; x++) {
      const h = Math.max(
        0,
        Math.round(noise(x / 7, 0, seed + 3) * 9 + noise(x / 2, 1, seed) * 2 - 4)
      )
      for (let k = 0; k < h; k++) px(x, G + 3 - k, k === h - 1 ? '#ddd6c6' : '#cfc7b4')
    }
  })
}

/** 牛头骨：两只长角，两个黑眼窝 */
function cattleSkull(seed: number) {
  return sprite(22, 12, ({ px, rect, line }) => {
    line(1, 1, 7, 5, '#e8dec6')
    line(1, 2, 7, 6, '#c8bca0')
    line(20, 1, 14, 5, '#d6ccb4')
    line(20, 2, 14, 6, '#b4a88e')
    rect(8, 4, 6, 6, '#ece4d0')
    rect(13, 4, 1, 6, '#c4b89e')
    rect(9, 10, 4, 1, '#dcd2ba')
    px(9, 6, '#3e3428')
    px(12, 6, '#3e3428')
    px(10, 9, '#6a5e4c')
    px(11, 9, '#6a5e4c')
    for (let x = 4; x < 18; x++) if (hash(x, 1, seed) < 0.7) px(x, 11, '#d2cab6')
  })
}

/** 倒在地上的骆驼骨架：脊椎、一圈肋骨、四条腿摊开、长脖子和头骨，半埋在沙里 */
function camelSkeleton(seed: number) {
  return sprite(54, 24, ({ px, rect, line }) => {
    for (let x = 6; x < 40; x++) {
      const y = 12 + Math.round(Math.sin(x / 9) * 1.5)
      if (x % 3) px(x, y, '#e6dec8')
      px(x, y + 1, '#c4b89e')
    }
    for (let rx = 14; rx < 34; rx += 3)
      for (let k = 0; k < 8; k++)
        px(rx + Math.round(Math.sin((k / 8) * Math.PI) * 2), 14 + k, k < 2 ? '#ece4d0' : '#d6ccb4')
    line(10, 14, 4, 22, '#d6ccb4')
    line(12, 14, 8, 22, '#c4b89e')
    line(36, 14, 42, 22, '#d6ccb4')
    line(38, 14, 47, 21, '#c4b89e')
    line(40, 12, 46, 6, '#e6dec8')
    line(41, 13, 47, 7, '#c4b89e')
    rect(45, 3, 7, 4, '#ece4d0')
    px(46, 4, '#3e3428')
    rect(50, 5, 3, 2, '#dcd2ba')
    for (let x = 0; x < 54; x++) {
      const h = 1 + Math.round(noise(x / 6, 1, seed) * 2)
      for (let k = 0; k < h; k++) px(x, 23 - k, '#d2cab6')
    }
  })
}

/** 蹲着的秃鹫：侧身朝右，驼着背，翅膀收在身侧，一圈白领，细长的秃脖子和粉灰的头。
 *  两帧轮着慢慢换：抬头张望、低头啄 */
// prettier-ignore
const PERCHED: string[][] = [
  [
    '..........hh....', '.........hhhb...', '.........hh.....', '........hh......',
    '.......ww.......', '....ddwwwd......', '...dkkkkkkd.....', '..dkkkkkkkkd....',
    '..lkkkkkkkkk....', '..lkkkkkkkkk....', '..lkkdkkkkkk....', '...kkkdkkkk.....',
    '...kkkkdkkk.....', '....kkkkkk......', '....kkkkk.......', '...kkk.f.f......',
    '..kk...f.f......', '......ff.ff.....',
  ],
  [
    '................', '................', '..........h.....', '.........hhh....',
    '.......wwhhhb...', '....ddwwwd......', '...dkkkkkkd.....', '..dkkkkkkkkd....',
    '..lkkkkkkkkk....', '..lkkkkkkkkk....', '..lkkdkkkkkk....', '...kkkdkkkk.....',
    '...kkkkdkkk.....', '....kkkkkk......', '....kkkkk.......', '...kkk.f.f......',
    '..kk...f.f......', '......ff.ff.....',
  ],
]
const PERCHED_COLORS: Record<string, string> = {
  k: '#2a2220',
  d: '#4a3e36',
  l: '#6a5a50',
  w: '#ece2d2',
  h: '#cf9f90',
  b: '#d8c070',
  f: '#8a7a6a',
}
function perchedVulture(seed: number): Flipbook {
  const w = 16,
    F = PERCHED.length
  const canvas = sprite(w * F, PERCHED[0].length, ({ px }) =>
    PERCHED.forEach((rows, f) =>
      rows.forEach((row, y) =>
        [...row].forEach((ch, x) => ch !== '.' && px(f * w + x, y, PERCHED_COLORS[ch]))
      )
    )
  )
  return { canvas, frames: F, fps: 0.4 + (seed % 3) * 0.1 }
}

/** 一堆碎水泥块，几根锈钢筋戳出来：塌楼脚下 */
function rubbleHeap(seed: number) {
  const r = rng(seed + 5)
  return sprite(46, 20, ({ px, line }) => {
    for (let i = 0; i < 10; i++) {
      const w = 6 + Math.floor(r() * 10),
        h = 3 + Math.floor(r() * 5)
      const x = Math.floor(r() * (46 - w)),
        y = 19 - h - Math.floor(r() * 6)
      const base = ['#9a968e', '#86827a', '#a8a298', '#7a766e'][Math.floor(r() * 4)]
      for (let yy = 0; yy < h; yy++)
        for (let xx = 0; xx < w; xx++) {
          let c =
            yy === 0
              ? mixHex(base, '#ffffff', 0.18)
              : xx === w - 1
                ? mixHex(base, '#000000', 0.3)
                : base
          if (hash(x + xx, y + yy, seed) < 0.08) c = '#5e5a54'
          px(x + xx, y + yy, c)
        }
      if (r() < 0.6) {
        const rx = x + Math.floor(r() * w)
        line(rx, y, rx + Math.floor((r() - 0.5) * 6), y - 3 - Math.floor(r() * 5), '#7a4a2a')
      }
    }
    for (let x = 2; x < 44; x++) if (hash(x, 1, seed) < 0.5) px(x, 19, '#8a8278')
  })
}

/** 废车场：一大片废车、轮胎、废铁堆和油桶 */
function scrapyard(seed: number): [HTMLCanvasElement, number, number][] {
  const r = rng(seed + 9)
  const out: [HTMLCanvasElement, number, number][] = []
  for (let i = 0; i < 14; i++) {
    const k = r()
    const art =
      k < 0.55
        ? carWreck(seed + i)
        : k < 0.7
          ? tires(seed + i)
          : k < 0.85
            ? scrapHeap(seed + i)
            : drum(seed + i)
    out.push([art, Math.round((r() - 0.5) * 300), Math.round((r() - 0.5) * 80)])
  }
  return out
}

export const WASTELAND_LANDMARKS: LandmarkSet = {
  boat: (seed, kind) => boatModel('wasteland', seed, kind),
  dockGoods: (seed) => wear(dockGoods(seed), seed),
  fountain: 'dry',
  plans: {
    ferris: (seed) => [[wear(ferrisWheel(true), seed), 0, -6]],
    carousel: (seed) => [[wear(carousel(true), seed), 0, -4]],
    obelisk: (seed) => [[wear(obelisk(), seed), 0, -6]],
    temple: (seed) => [[wear(temple(), seed), 0, -6]],
    // 市集两头各一只油桶火盆，夜里照亮摊子
    market: (seed) => [
      [stall(seed, 'wasteland'), -30, -10],
      [stall(seed + 1, 'wasteland'), 0, -14],
      [stall(seed + 2, 'wasteland'), 30, -10],
      [fireBarrel(seed + 3), -50, -4],
      [fireBarrel(seed + 4), 50, -4],
    ],
    garden: (seed) => [[wear(roseArch(true), seed), 0, -8]],
    park: (seed) => [[wear(gazebo(true), seed), 0, -6]],
    harbor: (seed) => [
      [crane(), 6, -10],
      [containers(seed), -40, -6],
    ],
    // 下面这些给地图按坐标立（Atlas 的 standees），区域也能用 landmark 指定
    fire: (seed) => [[fireBarrel(seed), 0, 0]],
    wreck: (seed) => [[carWreck(seed), 0, 0]],
    stalls: (seed) => [
      [stall(seed, 'wasteland'), -34, -4],
      [stall(seed + 1, 'wasteland'), 0, -6],
      [stall(seed + 2, 'wasteland'), 34, -4],
    ],
    scrapyard,
    billboard: (seed) => [[billboard(seed), 0, 0]],
    'neon-bar': (seed) => [[neonSign(['glass', 'heart'], 'pink', seed), 0, 0]],
    'neon-food': (seed) => [[neonSign(['bowl', 'arrow'], 'yellow', seed, true), 0, 0]],
    'neon-inn': (seed) => [[neonSign(['bed', 'star', 'star'], 'cyan', seed), 0, 0]],
    'neon-clinic': (seed) => [[neonSign(['cross'], 'green', seed), 0, 0]],
    'neon-tea': (seed) => [[neonSign(['cup', 'heart'], 'cyan', seed, true), 0, 0]],
    'neon-star': (seed) => [[neonSign(['star'], 'red', seed), 0, 0]],
    rubble: (seed) => [[rubbleHeap(seed), 0, 0]],
    whale: (seed) => [[whaleSkeleton(seed), 0, 0]],
    camel: (seed) => [[camelSkeleton(seed), 0, 0]],
    skull: (seed) => [[cattleSkull(seed), 0, 0]],
    fishbones: () => [[ribs(), 0, 0]],
    vulture: (seed) => [[perchedVulture(seed), 0, 0]],
  },
  scatter: {
    land: 0.05,
    outer: 0.03,
    sprite(where, seed) {
      const k = hash(seed, 3, 17)
      if (where === 'land')
        return k < 0.3
          ? tires(seed)
          : k < 0.55
            ? drum(seed)
            : k < 0.78
              ? scrapHeap(seed)
              : carWreck(seed)
      // 干海床：沉船、鱼骨、牛头骨、倒毙的骆驼、船锚、浮标、废铁
      return k < 0.12
        ? shipwreck(seed)
        : k < 0.3
          ? wreckBoat(seed)
          : k < 0.43
            ? ribs()
            : k < 0.53
              ? cattleSkull(seed)
              : k < 0.6
                ? camelSkeleton(seed)
                : k < 0.73
                  ? anchor()
                  : k < 0.87
                    ? buoy(seed)
                    : scrapHeap(seed)
    },
  },
}
