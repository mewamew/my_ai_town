import { hash, mixHex } from '../pixel/noise'
import type { Flipbook } from './landmarks'

// 小镇港口里的船：帆船、带驾驶舱的渔船靠在栈桥后面或在港湾里下锚，小舢板拴在桥前头。
// 桥是横向的，船顺着桥停，镜头看见侧面（船头朝右）；桥是竖向的，船也竖着停，镜头看见船尾。
// 都是逐帧动画：四帧里船身上下晃一像素，水线上的白沫和水纹跟着变；船尾灯和驾驶舱的窗夜里亮（glow）。
// 光从左上来：左边亮、右边暗，船底往下压暗；水线以下两行混进水色，像泡在水里。

export type BoatView = 'side' | 'stern'

/** 船身漆色和腰线色 */
const PAINTS: [string, string][] = [
  ['#2f6f7a', '#efe6cf'],
  ['#a8442e', '#efe6cf'],
  ['#2e4a6e', '#e8c45a'],
  ['#e6dfcc', '#2f6f7a'],
  ['#3e6e48', '#efe6cf'],
]
const SAILS = ['#f1ead8', '#e8d8b6', '#c4673f']
const BOTTOM = '#7e3328'
const RAIL = '#c89a62'
const RAIL_DARK = '#7a5a3a'
const SHADE = '#1d2a2a'
const WATER = '#24506a'
const FOAM = '#e6f4f2'
const RIPPLE = '#7fb4c8'
const ROPE = '#b89a6a'
const LAMP = '#ffd27a'
const FRAMES = 4
const FPS = 2
/** 每帧船身往下沉几像素 */
const BOB = [0, 0, 1, 1]

type Put = (x: number, y: number, c: string) => void

/** 夜里发光的一格：白天看是 day 色（玻璃、灯罩），夜里亮成 c */
type Lit = (x: number, y: number, c: string, day?: string) => void

/** 横排 FRAMES 帧的图集，每帧 w×h；draw 画一帧，o 是这一帧往下沉的像素，put 画底图、lit 画夜里发光的。
 *  mirror 时左右翻过来（船头朝左） */
function flipbook(
  w: number,
  h: number,
  draw: (put: Put, lit: Lit, o: number, f: number) => void,
  mirror = false
) {
  const make = () => {
    const c = document.createElement('canvas')
    c.width = w * FRAMES
    c.height = h
    return c
  }
  const canvas = make(),
    glow = make()
  const ctx = canvas.getContext('2d')!,
    gtx = glow.getContext('2d')!
  for (let f = 0; f < FRAMES; f++) {
    const at = (x: CanvasRenderingContext2D) => (px: number, py: number, c: string) => {
      px = Math.round(px)
      py = Math.round(py)
      if (px < 0 || py < 0 || px >= w || py >= h) return
      if (mirror) px = w - 1 - px
      x.fillStyle = c
      x.fillRect(f * w + px, py, 1, 1)
    }
    const put = at(ctx),
      light = at(gtx)
    draw(put, (x, y, c, day = c) => (put(x, y, day), light(x, y, c)), BOB[f], f)
  }
  return { canvas, glow, frames: FRAMES, fps: FPS } satisfies Flipbook
}

const line = (put: Put, x0: number, y0: number, x1: number, y1: number, c: string) => {
  const n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0), 1)
  for (let i = 0; i <= n; i++) put(x0 + ((x1 - x0) * i) / n, y0 + ((y1 - y0) * i) / n, c)
}

/** 下垂的缆绳 */
const rope = (put: Put, x0: number, y0: number, x1: number, y1: number) => {
  const n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0), 1)
  for (let i = 0; i <= n; i++) {
    const t = i / n
    put(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t + Math.sin(t * Math.PI) * 2, ROPE)
  }
}

/** 侧面的船身：船尾 stern 到船头 bow，sheer 是舷边（船身上沿）每一列的行，船底在 h-1 行。
 *  船头往下往回收，船尾略带斜；舷边一行亮木、一行暗木，往下第二行是腰线，再往下一行行木板缝，
 *  底下一行白水线，再往下是船底漆。返回每一行船身的左右端（画水线用） */
function sideHull(
  put: Put,
  o: number,
  h: number,
  stern: number,
  bow: number,
  sheer: (x: number) => number,
  [paint, stripe]: [string, string],
  rake = 7
) {
  const top = sheer(bow)
  const bowAt = (y: number) =>
    bow - Math.round(rake * Math.pow(Math.max(0, y - top) / (h - 1 - top), 1.6))
  const sternAt = (y: number) =>
    stern + Math.round((2 * Math.max(0, y - sheer(stern))) / (h - 1 - sheer(stern)))
  const boot = h - 6
  for (let y = 0; y < h; y++) {
    const x0 = sternAt(y),
      x1 = bowAt(y)
    for (let x = x0; x <= x1; x++) {
      const s = sheer(x)
      if (y < s) continue
      const r = y - s
      let c =
        r === 0
          ? mixHex(RAIL, '#fff4dc', 0.25)
          : r === 1
            ? RAIL_DARK
            : r === 3
              ? stripe
              : y > boot
                ? BOTTOM
                : y === boot
                  ? '#efe6cf'
                  : r > 4 && (y - boot) % 3 === 0
                    ? mixHex(paint, SHADE, 0.22)
                    : paint
      const t = (x - stern) / (bow - stern)
      if (t > 0.72) c = mixHex(c, SHADE, 0.16)
      else if (t < 0.18 && r > 1) c = mixHex(c, '#ffffff', 0.08)
      if (y > boot) c = mixHex(c, SHADE, (y - boot) * 0.06)
      if ((x === x0 || x === x1) && r > 0) c = mixHex(c, SHADE, 0.35)
      put(x, y + o, c)
    }
  }
}

/** 水线：船身最下面两行混进水色；船头船尾两头一点白沫，船边几道水纹，按帧换位置 */
function waterline(
  put: Put,
  h: number,
  x0: number,
  x1: number,
  f: number,
  under: (x: number, y: number) => string | null
) {
  for (let y = h - 2; y < h; y++)
    for (let x = x0; x <= x1; x++) {
      const c = under(x, y)
      if (c) put(x, y, mixHex(c, WATER, y === h - 1 ? 0.7 : 0.45))
    }
  const flick = f % 2
  put(x0 - 1 - flick, h - 1, FOAM)
  put(x1 + 1 + flick, h - 1, FOAM)
  put(x1 + 2, h - 2 + flick, FOAM)
  for (let k = 0; k < 3; k++) {
    const x = x0 + 4 + ((k * 11 + f * 3) % Math.max(1, x1 - x0 - 6))
    put(x, h - 1, RIPPLE)
    put(x + 1, h - 1, RIPPLE)
  }
}

/** 把已经画好的一帧读回来，给水线混色用 */
function reader(put: Put) {
  const seen = new Map<string, string>()
  const wrapped: Put = (x, y, c) => {
    seen.set(`${Math.round(x)},${Math.round(y)}`, c)
    put(x, y, c)
  }
  return { put: wrapped, at: (x: number, y: number) => seen.get(`${x},${y}`) ?? null }
}

/** 系船的方式：mirror 时船头朝左；tied 是靠在桥边，船头船尾两根缆绳垂到桥上，不然是下了锚，船头一根锚链 */
export interface Moor {
  mirror: boolean
  tied: boolean
}

/** 缆绳或锚链：靠桥的两头各一根缆绳斜垂到桥上；下锚的只有船头一根锚链笔直入水，旁边漂一只浮筒 */
function lines(
  put: Put,
  moor: Moor,
  w: number,
  h: number,
  bow: [number, number],
  stern: [number, number]
) {
  if (moor.tied) {
    rope(put, bow[0], bow[1], w - 2, h - 1)
    rope(put, stern[0], stern[1], 0, h - 1)
    return
  }
  line(put, bow[0], bow[1], bow[0] + 4, h - 1, '#5a5a62')
  put(bow[0] + 6, h - 2, '#d0402e')
  put(bow[0] + 7, h - 2, '#f4efe4')
  put(bow[0] + 6, h - 1, '#a83020')
  put(bow[0] + 7, h - 1, '#c8c0b0')
}

/** 帆船，侧面：一根桅杆，主帆和前帆都升着，桅顶一面小旗；船边挂两只护舷 */
function sloopSide(seed: number, moor: Moor) {
  const W = 44,
    H = 40
  const paint = PAINTS[Math.floor(hash(seed, 1, 41) * PAINTS.length)]
  const sail = SAILS[Math.floor(hash(seed, 2, 41) * SAILS.length)]
  const stern = 4,
    bow = 38
  const sheer = (x: number) => {
    const t = (x - 20) / 17
    return Math.round(29 - 2.5 * t * t - 2 * Math.max(0, t) ** 2)
  }
  return flipbook(
    W,
    H,
    (raw, lit, o, f) => {
      const { put, at } = reader(raw)
      const mast = 21,
        boomY = sheer(mast) - 4 + o
      // 主帆在桅杆后面（船尾一侧），三角形略带弧；前帆在桅杆和船头之间
      const head = 4 + o
      for (let y = head; y < boomY; y++) {
        const t = (y - head) / (boomY - head)
        const x0 = mast - 1 - Math.round(t * 11 + Math.sin(t * Math.PI) * 1.2)
        for (let x = x0; x < mast; x++) {
          let c = sail
          if (x > mast - 3) c = mixHex(c, '#ffffff', 0.12)
          if (x === x0) c = mixHex(c, SHADE, 0.25)
          else if ((y - head) % 4 === 3) c = mixHex(c, SHADE, 0.1)
          put(x, y, c)
        }
      }
      const jibTop = head + 3,
        jibFoot = sheer(mast + 2) - 2 + o
      for (let y = jibTop; y < jibFoot; y++) {
        const t = (y - jibTop) / (jibFoot - jibTop)
        const x1 = mast + 2 + Math.round(t * (bow - mast - 7))
        for (let x = mast + 2; x <= x1; x++)
          put(x, y, x === x1 ? mixHex(sail, SHADE, 0.3) : mixHex(sail, SHADE, 0.12))
      }
      // 帆桁、桅杆、桅顶小旗
      line(put, mast - 12, boomY, mast, boomY, '#6b4a30')
      for (let y = 1 + o; y < sheer(mast) + o; y++) {
        put(mast, y, '#8a6440')
        put(mast + 1, y, '#5a3e28')
      }
      const flap = f % 2
      for (let k = 0; k < 3; k++) put(mast + 2 + k, 1 + o + (k > 1 ? flap : 0), '#c83a2a')
      put(mast + 2, 2 + o, '#9a2a20')
      // 前支索、后支索
      line(put, mast + 1, 2 + o, bow, sheer(bow) + o, '#4a4a52')
      line(put, mast, 2 + o, stern + 1, sheer(stern + 1) + o, '#4a4a52')
      sideHull(put, o, H, stern, bow, sheer, paint, 5)
      // 护舷、船号、船尾灯
      for (const x of [14, 27]) {
        put(x, sheer(x) + o + 1, ROPE)
        put(x, sheer(x) + o + 2, '#f4efe4')
        put(x, sheer(x) + o + 3, '#d8d0c0')
      }
      for (let k = 0; k < 2; k++) put(bow - 8 + k * 2, sheer(bow - 8) + o + 5, '#f4efe4')
      put(stern + 2, sheer(stern) + o - 1, '#5a3e28')
      lit(stern + 2, sheer(stern) + o - 2, LAMP)
      lines(put, moor, W, H, [bow - 3, sheer(bow - 3) + o], [stern + 2, sheer(stern + 2) + o])
      waterline(raw, H, stern + 1, bow - 5, f, at)
    },
    moor.mirror
  )
}

/** 渔船，侧面：船尾一间驾驶舱（窗夜里亮），桅杆在前，帆卷起来罩着帆罩；船头堆着渔网和浮子，舷边挂救生圈 */
function trawlerSide(seed: number, moor: Moor) {
  const W = 44,
    H = 36
  const paint = PAINTS[Math.floor(hash(seed, 3, 41) * PAINTS.length)]
  const stern = 4,
    bow = 38
  const sheer = (x: number) => {
    const t = (x - 19) / 17
    return Math.round(25 - 2 * t * t - 2.5 * Math.max(0, t) ** 2)
  }
  return flipbook(
    W,
    H,
    (raw, lit, o, f) => {
      const { put, at } = reader(raw)
      // 桅杆、卷起的帆、桅顶灯
      const mast = 25
      for (let y = 3 + o; y < sheer(mast) + o; y++) {
        put(mast, y, '#8a6440')
        put(mast + 1, y, '#5a3e28')
      }
      lit(mast, 2 + o, LAMP)
      const boomY = sheer(mast) - 7 + o
      line(put, 17, boomY + 1, mast, boomY + 1, '#6b4a30')
      for (let x = 18; x < mast; x++) {
        put(x, boomY, '#3e6a8a')
        put(x, boomY - 1, x % 3 === 0 ? '#2e4e6a' : '#4e7c9c')
      }
      line(put, mast + 1, 4 + o, bow, sheer(bow) + o, '#4a4a52')
      // 驾驶舱
      const c0 = 7,
        c1 = 16,
        roof = sheer(11) - 9 + o
      for (let y = roof + 2; y < sheer(11) + o; y++)
        for (let x = c0; x <= c1; x++) {
          let c = x > c1 - 2 ? '#c8bfa8' : '#ece4d0'
          if (y === roof + 2) c = mixHex(c, SHADE, 0.15)
          put(x, y, c)
        }
      for (let x = c0 - 1; x <= c1 + 1; x++) {
        put(x, roof, '#8a5a3a')
        put(x, roof + 1, '#6a4430')
      }
      // 一排三扇小窗：白天是玻璃（一点天光），夜里亮
      for (let x = c0 + 1; x < c1 - 1; x += 3)
        for (let y = roof + 3; y < roof + 5; y++)
          for (let dx = 0; dx < 2; dx++)
            lit(
              x + dx,
              y,
              y === roof + 3 ? '#f2d48a' : '#e8b860',
              dx || y > roof + 3 ? '#34485a' : '#7a96a8'
            )
      sideHull(put, o, H, stern, bow, sheer, paint, 5)
      // 救生圈挂在舷边
      for (const [dx, dy] of [
        [0, 1],
        [1, 0],
        [2, 1],
        [1, 2],
      ])
        put(21 + dx, sheer(21) + o + 1 + dy, dx === 1 ? '#f4efe4' : '#d0402e')
      // 船头的渔网堆和浮子
      for (let x = 28; x < 35; x++) {
        const hgt = 1 + Math.round(Math.sin(((x - 28) / 7) * Math.PI) * 2)
        for (let k = 1; k <= hgt; k++)
          put(x, sheer(x) + o - k, (x + k) % 3 === 0 ? '#2e4a3c' : '#4a6a52')
      }
      for (const x of [29, 33]) put(x, sheer(x) + o - 2, '#e8823a')
      for (let k = 0; k < 2; k++) put(bow - 9 + k * 2, sheer(bow - 9) + o + 5, '#f4efe4')
      lines(put, moor, W, H, [bow - 3, sheer(bow - 3) + o], [stern + 2, sheer(stern + 2) + o])
      waterline(raw, H, stern + 1, bow - 5, f, at)
    },
    moor.mirror
  )
}

/** 小舢板，侧面：木色船身，一支桨斜搭在船舷上，船头一根缆绳拴在桥上 */
function rowboatSide(seed: number, mirror: boolean) {
  const W = 26,
    H = 12
  const wood = hash(seed, 4, 41) < 0.5 ? '#9a6e48' : '#7a8a6a'
  const sheer = (x: number) => {
    const t = (x - 12) / 10
    return Math.round(6 - 1.5 * t * t)
  }
  return flipbook(
    W,
    H,
    (raw, _lit, o, f) => {
      const { put, at } = reader(raw)
      line(put, 5, 3 + o, 20, 6 + o, '#c8a070')
      put(20, 6 + o, '#a88050')
      put(21, 7 + o, '#a88050')
      sideHull(put, o, H, 3, 22, sheer, [wood, mixHex(wood, '#ffffff', 0.3)], 3)
      rope(put, 21, sheer(21) + o, W - 1, H - 1)
      waterline(raw, H, 4, 19, f, at)
    },
    mirror
  )
}

/** 船尾看过去的船身：上宽下窄的 U 形，舷边、腰线、船名牌、白水线、船底漆，正中一道舵 */
function sternHull(
  put: Put,
  o: number,
  h: number,
  cx: number,
  top: number,
  half: number,
  [paint, stripe]: [string, string]
) {
  const boot = h - 6
  for (let y = top; y < h; y++) {
    const t = (y - top) / (h - 1 - top)
    const hw = Math.round(half - half * 0.45 * Math.pow(t, 1.5))
    for (let x = cx - hw; x < cx + hw; x++) {
      const r = y - top
      let c =
        r === 0
          ? mixHex(RAIL, '#fff4dc', 0.25)
          : r === 1
            ? RAIL_DARK
            : r === 3
              ? stripe
              : y > boot
                ? BOTTOM
                : y === boot
                  ? '#efe6cf'
                  : paint
      if (x >= cx + hw - 2) c = mixHex(c, SHADE, 0.22)
      else if (x <= cx - hw + 1) c = mixHex(c, '#ffffff', 0.1)
      if (y > boot) c = mixHex(c, SHADE, (y - boot) * 0.06)
      put(x, y + o, c)
    }
  }
  // 船名牌和舵（小船没有名牌）
  if (half > 5)
    for (let x = cx - 2; x < cx + 2; x++) put(x, top + 5 + o, x % 2 ? '#f4efe4' : '#d8cfb8')
  for (let y = top + (half > 5 ? 7 : 3); y < h; y++) put(cx, y + o, '#5a3e28')
}

/** 帆船，船尾：桅杆在正中，两根侧支索斜拉到两舷；帆卷在帆桁上，从后面看是桅杆下部一小团 */
function sloopStern(seed: number) {
  const W = 20,
    H = 40
  const paint = PAINTS[Math.floor(hash(seed, 1, 41) * PAINTS.length)]
  const sail = SAILS[Math.floor(hash(seed, 2, 41) * SAILS.length)]
  const cx = 10,
    top = 29,
    half = 7
  return flipbook(W, H, (raw, lit, o, f) => {
    const { put, at } = reader(raw)
    line(put, cx, 2 + o, cx - half + 1, top + o, '#4a4a52')
    line(put, cx, 2 + o, cx + half - 2, top + o, '#4a4a52')
    for (let y = 1 + o; y < top + o; y++) {
      put(cx, y, '#8a6440')
      put(cx + 1, y, '#5a3e28')
    }
    for (let x = cx - 1; x < cx + 3; x++) {
      put(x, top - 6 + o, x < cx + 1 ? sail : mixHex(sail, SHADE, 0.2))
      put(x, top - 5 + o, mixHex(sail, SHADE, x < cx + 1 ? 0.1 : 0.3))
    }
    put(cx, top - 4 + o, '#6b4a30')
    for (let k = 0; k < 3; k++) put(cx + 1 + k, 1 + o + (k > 1 ? f % 2 : 0), '#c83a2a')
    sternHull(put, o, H, cx, top, half, paint)
    lit(cx, top - 2 + o, LAMP)
    put(cx, top - 1 + o, '#5a3e28')
    waterline(raw, H, cx - half + 2, cx + half - 3, f, at)
  })
}

/** 渔船，船尾：驾驶舱的后墙，一扇门、一扇夜里亮的小窗，桅顶灯 */
function trawlerStern(seed: number) {
  const W = 20,
    H = 36
  const paint = PAINTS[Math.floor(hash(seed, 3, 41) * PAINTS.length)]
  const cx = 10,
    top = 25,
    half = 7
  return flipbook(W, H, (raw, lit, o, f) => {
    const { put, at } = reader(raw)
    for (let y = 3 + o; y < top - 8 + o; y++) put(cx, y, '#6b4a30')
    lit(cx, 2 + o, LAMP)
    for (let y = top - 8 + o; y < top + o; y++)
      for (let x = cx - 5; x < cx + 5; x++) put(x, y, x > cx + 2 ? '#c8bfa8' : '#ece4d0')
    for (let x = cx - 6; x < cx + 6; x++) {
      put(x, top - 10 + o, '#8a5a3a')
      put(x, top - 9 + o, '#6a4430')
    }
    for (let y = top - 7; y < top; y++) {
      put(cx - 3, y + o, '#6a4430')
      put(cx - 2, y + o, y === top - 4 ? '#c8a050' : '#8a5a3a')
    }
    for (let y = top - 7; y < top - 5; y++)
      for (let x = cx + 1; x < cx + 3; x++)
        lit(x, y + o, '#e8b860', x === cx + 1 && y === top - 7 ? '#7a96a8' : '#34485a')
    sternHull(put, o, H, cx, top, half, paint)
    waterline(raw, H, cx - half + 2, cx + half - 3, f, at)
  })
}

/** 小舢板，船尾 */
function rowboatStern(seed: number) {
  const W = 12,
    H = 11
  const wood = hash(seed, 4, 41) < 0.5 ? '#9a6e48' : '#7a8a6a'
  return flipbook(W, H, (raw, _lit, o, f) => {
    const { put, at } = reader(raw)
    sternHull(put, o, H, 6, 5, 4, [wood, mixHex(wood, '#ffffff', 0.3)])
    waterline(raw, H, 3, 8, f, at)
  })
}

/** 小镇的船：kind 0 帆船、1 渔船、2 小舢板 */
export function villageBoat(seed: number, view: BoatView, kind: number, moor: Moor) {
  if (kind === 2) return view === 'side' ? rowboatSide(seed, moor.mirror) : rowboatStern(seed)
  if (kind === 1) return view === 'side' ? trawlerSide(seed, moor) : trawlerStern(seed)
  return view === 'side' ? sloopSide(seed, moor) : sloopStern(seed)
}
