import { hash, mixHex, noise, rng } from '../pixel/noise'
import {
  carousel,
  court,
  dockGoods,
  ferrisWheel,
  gazebo,
  obelisk,
  roseArch,
  temple,
  type LandmarkSet,
} from './landmarks'
import { sprite, stone, wear } from './sprite'
import { WALL_COLORS } from '../themes/walls'

// 末日废土的户外立牌。原作的地标都还在，只是锈了、褪色了、缺了几块；
// 喷泉干了，市集是篷布摊，港口有锈吊机和集装箱，栈桥边搁浅着锈船。
// 镇外的荒地上散落轮胎、油桶、废车；干海床上有沉船、船锚、浮标和一副大鱼骨。

const RUST = WALL_COLORS.rust
const rust = (x: number, y: number, seed: number) => RUST[Math.floor(hash(x, y, seed) * 3)]

/** 干掉的喷泉：池底龟裂发黑，积了一层沙，中间的雕像断了头 */
function dryFountain() {
  return sprite(58, 46, ({ px, rect }) => {
    const ellipse = (
      cx: number,
      cy: number,
      rx: number,
      ry: number,
      c: (x: number, y: number, t: number) => string
    ) => {
      for (let y = -ry; y <= ry; y++) {
        const half = Math.round(rx * Math.sqrt(1 - (y / ry) ** 2))
        for (let x = -half; x <= half; x++)
          px(cx + x, cy + y, c(cx + x, cy + y, (x + half) / (2 * half + 1)))
      }
    }
    rect(3, 36, 52, 8, '#948c7c')
    rect(3, 36, 52, 1, '#aea694')
    rect(3, 43, 52, 1, '#6a6254')
    for (let x = 3; x < 55; x += 7) rect(x, 37, 1, 6, '#7e7668')
    // 池沿缺了一块
    rect(40, 36, 6, 3, '#6a6254')
    ellipse(29, 35, 26, 6, (_x, _y, t) => stone(t, '#aaa290'))
    ellipse(29, 35, 23, 4, (x, y) =>
      noise(x / 3, y / 2, 9) > 0.55 ? '#b9a47e' : hash(x, y, 3) < 0.2 ? '#4a4238' : '#5e564a'
    )
    rect(26, 20, 6, 15, '#b0a896')
    rect(26, 20, 2, 15, '#c8c0ae')
    rect(30, 20, 2, 15, '#8a8272')
    ellipse(29, 20, 10, 2, (_x, _y, t) => stone(t, '#aaa290'))
    // 雕像只剩下半身，断口参差
    rect(27, 10, 4, 9, '#c8c2b6')
    rect(30, 10, 1, 9, '#9a948a')
    for (const [x, y] of [
      [27, 9],
      [29, 8],
      [30, 9],
    ])
      px(x, y, '#c8c2b6')
    // 池子里的一只轮胎和碎石
    rect(14, 32, 5, 3, '#1e1e1e')
    px(16, 33, '#3a3a36')
    for (let k = 0; k < 8; k++)
      px(34 + Math.floor(hash(k, 1, 4) * 14), 33 + Math.floor(hash(k, 2, 4) * 4), '#8a8272')
  })
}

/** 篷布摊：歪柱子，打补丁的篷布，下面是木箱搭的台子，摆着罐头、瓶子和零件 */
function junkStall(k: number) {
  const tarps = [
    ['#4f6f86', '#8a8472', '#b0703a'],
    ['#b0703a', '#6e6a5c', '#4f6f86'],
    ['#6e7a5a', '#8a8472', '#9a5a3a'],
  ][k % 3]
  return sprite(28, 26, ({ px, rect, line }) => {
    line(2, 8, 1, 25, '#5a4430')
    line(3, 8, 2, 25, '#6e5840')
    line(25, 7, 26, 25, '#4e3a28')
    for (let x = 0; x < 28; x++)
      for (let y = 1; y < 8; y++) {
        const patch = tarps[Math.floor(hash(x >> 3, y >> 2, k + 7) * 3)]
        let c = y === 1 ? mixHex(patch, '#1e1a16', 0.3) : patch
        if ((x + y * 2) % 11 === 0) c = mixHex(c, '#1e1a16', 0.25)
        px(x, y + Math.round(x / 14), c)
      }
    // 篷布下沿垂下来的破边
    for (let x = 0; x < 28; x += 3) if (hash(x, 9, k) < 0.6) px(x, 9 + Math.round(x / 14), tarps[0])
    // 木箱台子
    for (const [x, w] of [
      [1, 9],
      [10, 9],
      [19, 8],
    ]) {
      rect(x, 17, w, 7, '#8a6844')
      rect(x, 17, w, 1, '#a88660')
      rect(x, 20, w, 1, '#6a4c30')
      rect(x + w - 1, 17, 1, 7, '#5e4630')
    }
    const goods = ['#8a8e8e', '#5a7a4a', '#a55f2e', '#b8b0a0', '#6a6e7a']
    for (let i = 0; i < 8; i++) {
      const c = goods[(i + k) % goods.length]
      rect(2 + i * 3, 14 + (i % 2), 2, 3 - (i % 2), c)
      px(2 + i * 3, 14 + (i % 2), mixHex(c, '#ffffff', 0.3))
    }
  })
}

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

export const WASTELAND_LANDMARKS: LandmarkSet = {
  boat: (seed, _view, kind) => (kind === 2 ? null : wreckBoat(seed)),
  dockGoods: (seed) => wear(dockGoods(seed), seed),
  plans: {
    ferris: (seed) => [[wear(ferrisWheel(true), seed), 0, -6]],
    carousel: (seed) => [[wear(carousel(true), seed), 0, -4]],
    obelisk: (seed) => [[wear(obelisk(), seed), 0, -6]],
    fountain: () => [[dryFountain(), 0, -4]],
    temple: (seed) => [[wear(temple(), seed), 0, -6]],
    court: (seed) => [[wear(court(), seed), 0, -8]],
    market: (seed) => [
      [junkStall(seed), -30, -10],
      [junkStall(seed + 1), 0, -14],
      [junkStall(seed + 2), 30, -10],
    ],
    garden: (seed) => [[wear(roseArch(true), seed), 0, -8]],
    park: (seed) => [[wear(gazebo(true), seed), 0, -6]],
    harbor: (seed) => [
      [crane(), 6, -10],
      [containers(seed), -40, -6],
    ],
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
      return k < 0.14
        ? shipwreck(seed)
        : k < 0.36
          ? wreckBoat(seed)
          : k < 0.55
            ? ribs()
            : k < 0.7
              ? anchor()
              : k < 0.85
                ? buoy(seed)
                : scrapHeap(seed)
    },
  },
}
