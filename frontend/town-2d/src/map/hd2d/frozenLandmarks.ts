import { hash, mixHex, noise } from '../pixel/noise'
import {
  carousel,
  court,
  dockGoods,
  ferrisWheel,
  gazebo,
  obelisk,
  roseArch,
  stall,
  temple,
  type Flipbook,
  type LandmarkSet,
} from './landmarks'
import { snowCap, sprite, stone } from './sprite'
import { ICE, SNOW, SNOW_GREY, SNOW_SHADE } from '../palette'

// 冰封雪镇的户外立牌。原作的地标照旧，只是压了一层雪；喷泉冻成一串冰挂，
// 港口有晾鱼架，栈桥边的船冻在冰里。镇外雪地上有雪人、雪橇和柴垛，冰原上有冰钓小屋和冰窟窿。

/** 冻住的喷泉：池里是冰，池沿压雪，中间的水柱冻成一串冰挂 */
function frozenFountain() {
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
    rect(3, 36, 52, 8, '#9aa2ac')
    rect(3, 36, 52, 1, SNOW)
    rect(3, 43, 52, 1, '#6a727c')
    for (let x = 3; x < 55; x += 7) rect(x, 37, 1, 6, '#8a929c')
    ellipse(29, 35, 26, 6, (_x, _y, t) => (t < 0.55 ? SNOW : SNOW_SHADE))
    ellipse(29, 35, 23, 4, (x, y) =>
      (x + y * 3) % 9 === 0 ? '#e4f2fa' : noise(x / 4, y / 2, 5) > 0.55 ? '#bcdae8' : '#a4cadc'
    )
    rect(26, 18, 6, 17, '#b4bcc4')
    rect(26, 18, 2, 17, '#d0d6dc')
    rect(30, 18, 2, 17, '#9aa2ac')
    ellipse(29, 18, 10, 2, (_x, _y, t) => stone(t, SNOW_GREY))
    rect(27, 6, 4, 11, '#e4e0d8')
    rect(26, 9, 6, 4, '#e4e0d8')
    rect(28, 3, 3, 3, '#e4e0d8')
    rect(27, 2, 5, 1, SNOW)
    // 从上层盆边垂下的冰挂，越往下越细
    for (const d of [-1, 1])
      for (let k = 0; k < 4; k++) {
        const x = 29 + d * (7 + k * 2),
          len = 12 - k * 2
        for (let y = 0; y < len; y++)
          px(x, 20 + y, y === len - 1 ? '#ffffff' : k % 2 ? ICE : '#e4f2fa')
      }
  })
}

/** 港口的晾鱼架：两根木桩一根横杆，下面挂一排鱼干，杆上压雪 */
function fishRack(seed: number) {
  return sprite(34, 22, ({ px, rect }) => {
    for (const x of [2, 30]) {
      rect(x, 3, 2, 19, '#5a4030')
      rect(x + 1, 3, 1, 19, '#44301f')
    }
    rect(0, 3, 34, 2, '#6a4c30')
    rect(0, 2, 34, 1, SNOW)
    for (let x = 5; x < 29; x += 3) {
      const len = 7 + Math.floor(hash(x, 1, seed) * 4)
      for (let y = 0; y < len; y++)
        px(x, 5 + y, y === 0 ? '#3a2a20' : y > len - 3 ? '#8a6a4a' : '#b89a6a')
      px(x + 1, 6, '#9a7a52')
    }
    rect(4, 19, 10, 3, '#8a6844')
    rect(4, 18, 10, 1, SNOW)
    rect(16, 20, 8, 2, '#7a5a3a')
    rect(16, 19, 8, 1, SNOW)
  })
}

/** 冻在冰里的船：船身一圈冰，甲板和桅杆的横桁上压雪 */
function frozenShip(seed: number) {
  const hull = ['#6a2a24', '#2e4a6a', '#3a4a3a'][seed % 3]
  return sprite(40, 32, ({ px, rect, line }) => {
    for (const mx of [13, 22]) {
      rect(mx, 2, 1, 20, '#3a2a20')
      rect(mx - 4, 7, 9, 1, '#3a2a20')
      rect(mx - 4, 6, 9, 1, SNOW)
    }
    line(13, 2, 34, 20, '#5a4a40')
    rect(22, 14, 10, 6, '#d8d0c0')
    rect(22, 13, 10, 1, SNOW)
    rect(24, 16, 2, 2, '#f0d890')
    for (let y = 20; y < 28; y++) {
      const inset = Math.round(((y - 20) / 8) * 5)
      for (let x = inset; x < 40 - inset; x++)
        px(
          x,
          y,
          y === 20
            ? SNOW
            : y === 21
              ? mixHex(hull, '#ffffff', 0.2)
              : x > 32 - inset
                ? mixHex(hull, '#000000', 0.35)
                : hull
        )
    }
    // 船身四周冻住的冰和雪堆
    for (let x = 0; x < 40; x++) {
      const h = 2 + Math.round(noise(x / 3, 0, seed) * 3)
      for (let k = 0; k < h; k++)
        px(x, 31 - k, k === h - 1 ? SNOW : k === 0 ? '#a4cadc' : '#dde8f0')
    }
  })
}

/** 冰钓小屋：木板小屋，屋顶积雪，铁皮烟囱，门口一个冰窟窿 */
function iceHut(seed: number) {
  const wall = ['#a8462e', '#3e5a78', '#b8893a', '#4a6a4e'][seed % 4]
  return sprite(24, 18, ({ px, rect }) => {
    for (let y = 7; y < 16; y++)
      for (let x = 1; x < 14; x++)
        px(
          x,
          y,
          x % 3 === 2 ? mixHex(wall, '#000000', 0.3) : x > 11 ? mixHex(wall, '#000000', 0.2) : wall
        )
    rect(0, 4, 15, 3, SNOW)
    rect(0, 6, 15, 1, SNOW_SHADE)
    rect(5, 10, 4, 6, '#2a2420')
    rect(2, 9, 2, 2, '#f0d890')
    rect(11, 0, 2, 5, '#5a5e66')
    for (let y = 14; y < 18; y++)
      for (let x = 15; x < 23; x++) {
        const d = Math.hypot((x - 19) / 3, (y - 16) / 1.3)
        if (d < 1) px(x, y, '#1c3444')
        else if (d < 1.4) px(x, y, SNOW)
      }
    rect(0, 16, 15, 2, SNOW)
  })
}

/** 冰窟窿边插一面小旗，旁边一个木桶 */
function fishingHole(seed: number) {
  return sprite(14, 12, ({ px, rect }) => {
    for (let y = 7; y < 12; y++)
      for (let x = 0; x < 10; x++) {
        const d = Math.hypot((x - 5) / 4, (y - 9.5) / 1.8)
        if (d < 0.75) px(x, y, '#1c3444')
        else if (d < 1.05) px(x, y, SNOW)
      }
    rect(9, 1, 1, 9, '#5a4030')
    rect(10, 1, 3, 2, hash(seed, 1, 3) < 0.5 ? '#c83a2a' : '#e8b030')
    rect(11, 8, 3, 3, '#7a5a3a')
    rect(11, 7, 3, 1, SNOW)
  })
}

/** 冻住的小划艇，一半埋在雪里 */
function rowboat(seed: number) {
  return sprite(20, 8, ({ px }) => {
    for (let y = 2; y < 6; y++) {
      const inset = y - 2
      for (let x = inset; x < 20 - inset; x++)
        px(x, y, y === 2 ? '#8a6844' : noise(x / 2, y, seed) > 0.6 ? SNOW : '#6a4c30')
    }
    for (let x = 0; x < 20; x++) px(x, 6 + (x % 3 === 0 ? 0 : 1), SNOW)
    for (let x = 2; x < 18; x += 5) px(x, 1, SNOW)
  })
}

function snowman(seed: number) {
  return sprite(10, 14, ({ px, rect }) => {
    const ball = (cx: number, cy: number, r: number) => {
      for (let j = -r; j <= r; j++)
        for (let i = -r; i <= r; i++)
          if (i * i + j * j <= r * r + 1) px(cx + i, cy + j, i + j > 1 ? SNOW_SHADE : SNOW)
    }
    ball(5, 10, 3)
    ball(5, 5, 2)
    px(4, 4, '#1e1e24')
    px(6, 4, '#1e1e24')
    px(7, 5, '#e07a2a')
    rect(3, 7, 5, 1, ['#c83a2a', '#2e5a9a', '#e8b030'][seed % 3])
    rect(2, 2, 6, 1, '#2a2a30')
    rect(3, 0, 4, 2, '#2a2a30')
  })
}

function sled() {
  return sprite(12, 6, ({ rect, px }) => {
    rect(1, 1, 8, 2, '#a8462e')
    rect(1, 0, 8, 1, SNOW)
    rect(0, 4, 10, 1, '#3a3a40')
    px(10, 3, '#3a3a40')
    px(2, 3, '#3a3a40')
    px(7, 3, '#3a3a40')
  })
}

/** 柴垛：一排圆木截面，顶上压雪 */
function woodstack() {
  return sprite(14, 10, ({ px, rect }) => {
    for (let y = 2; y < 10; y++)
      for (let x = 0; x < 14; x++) {
        const cx = x % 3,
          cy = (y - 2) % 3
        px(x, y, cx === 1 && cy === 1 ? '#c8a070' : cx === 2 || cy === 2 ? '#4a3018' : '#8a6040')
      }
    rect(0, 0, 14, 2, SNOW)
    rect(8, 1, 6, 1, SNOW_SHADE)
  })
}

/** 雪灯：雪堆成的小灯笼，正面掏一个小窗，里面点着蜡烛；夜里窗口透出暖光（自发光图） */
function snowLantern(seed: number): Flipbook {
  const W = 10,
    H = 13
  const body = (
    px: (x: number, y: number, c: string) => void,
    rect: (x: number, y: number, w: number, h: number, c: string) => void
  ) => {
    // 顶上一个小雪球，下面一个圆鼓鼓的灯身，底座压着雪
    for (let y = 0; y < 3; y++)
      for (let x = 3; x < 7; x++)
        if (!((y === 0 || y === 2) && (x === 3 || x === 6))) px(x, y, x > 4 ? SNOW_SHADE : SNOW)
    for (let y = 3; y < 11; y++) {
      const half = y < 5 ? 4 : y < 9 ? 5 : 4
      for (let x = 5 - half; x < 5 + half; x++) px(x, y, x >= 6 ? SNOW_SHADE : SNOW)
    }
    rect(0, 11, W, 2, SNOW)
    rect(1, 12, W - 2, 1, SNOW_SHADE)
  }
  const flame = hash(seed, 2, 31) < 0.5 ? '#ffcf6a' : '#ffb85a'
  const canvas = sprite(W, H, ({ px, rect }) => {
    body(px, rect)
    // 掏出来的小窗：深色的洞，里面一点烛光
    rect(3, 5, 4, 4, '#5a4a40')
    rect(4, 6, 2, 3, flame)
  })
  const glow = sprite(W, H, ({ rect }) => {
    rect(3, 5, 4, 4, '#a0602a')
    rect(4, 6, 2, 3, '#ffd88a')
  })
  return { canvas, glow, frames: 1, fps: 1 }
}

/** 露出雪面的一块大石头 */
function snowRock(seed: number) {
  return sprite(12, 8, ({ px }) => {
    for (let y = 0; y < 8; y++)
      for (let x = 0; x < 12; x++) {
        const d = Math.hypot((x - 6) / 6, (y - 6) / 5) + (noise(x / 2, y / 2, seed) - 0.5) * 0.3
        if (d > 1) continue
        px(x, y, y < 3 ? (x < 6 ? SNOW : SNOW_SHADE) : x < 5 ? '#767c86' : '#4c525c')
      }
  })
}

export const FROZEN_LANDMARKS: LandmarkSet = {
  boat: (seed, _view, kind) => (kind === 2 ? rowboat(seed) : frozenShip(seed)),
  dockGoods: (seed) => snowCap(dockGoods(seed), seed),
  plans: {
    ferris: (seed) => [[snowCap(ferrisWheel(), seed), 0, -6]],
    carousel: (seed) => [[snowCap(carousel(), seed), 0, -4]],
    obelisk: (seed) => [[snowCap(obelisk(), seed), 0, -6]],
    fountain: () => [[frozenFountain(), 0, -4]],
    temple: (seed) => [[snowCap(temple(), seed), 0, -6]],
    court: (seed) => [[snowCap(court(), seed), 0, -8]],
    // 市集：三个压雪的棚子，摊前一排雪灯
    market: (seed) => [
      [snowCap(stall(seed), seed), -30, -10],
      [snowCap(stall(seed + 1), seed + 1), 0, -14],
      [snowCap(stall(seed + 2), seed + 2), 30, -10],
      [snowLantern(seed), -38, 8],
      [snowLantern(seed + 1), -13, 6],
      [snowLantern(seed + 2), 13, 6],
      [snowLantern(seed + 3), 38, 8],
    ],
    garden: (seed) => [[snowCap(roseArch(true), seed), 0, -8]],
    park: (seed) => [[snowCap(gazebo(), seed), 0, -6]],
    harbor: (seed) => [
      [fishRack(seed), -24, -8],
      [snowCap(stall(seed + 3), seed), 22, -6],
    ],
    // 冰钓场（手绘地图的区域指定）：岸边柴垛和雪橇，往外的海冰上几间冰钓小屋、几个冰窟窿
    icefishing: (seed) => [
      [woodstack(), -34, -6],
      [sled(), 14, 6],
      [iceHut(seed), -40, 34, true],
      [iceHut(seed + 1), 30, 46, true],
      [fishingHole(seed), -6, 42, true],
      [fishingHole(seed + 2), 58, 66, true],
      [fishingHole(seed + 3), -54, 70, true],
    ],
    // 雪橇坡：停着几架雪橇，堆着两个雪人
    sledding: (seed) => [
      [sled(), -24, 2],
      [sled(), 22, 12],
      [snowman(seed), -4, -14],
      [snowman(seed + 1), 38, -20],
      [sled(), -46, -22],
    ],
  },
  scatter: {
    land: 0.05,
    outer: 0.025,
    sprite(where, seed) {
      const k = hash(seed, 3, 29)
      if (where === 'land')
        return k < 0.25 ? snowman(seed) : k < 0.45 ? sled() : k < 0.7 ? woodstack() : snowRock(seed)
      return k < 0.35
        ? iceHut(seed)
        : k < 0.7
          ? fishingHole(seed)
          : k < 0.85
            ? rowboat(seed)
            : snowRock(seed)
    },
  },
}
