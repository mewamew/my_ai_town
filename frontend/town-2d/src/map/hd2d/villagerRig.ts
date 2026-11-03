import { mixHex } from '../pixel/noise'
import { SIGNS, type Sign } from './villagerSigns'
import {
  FRAME_H,
  FRAME_W,
  OX,
  OY,
  lookOf,
  palette,
  sketch,
  type HeadTurn,
  type Look,
  type Stance,
  type View,
} from './villagerSprite'

// 村民立牌的一帧：按此刻的姿势、表情和天气，把分层的笔画（villagerSprite.ts 的 sketch）叠进一块
// 带留白的小贴图。笔画按身子朝向、头的朝向和手臂缓存；每帧只挪组（呼吸时头沉一格、走路时身子起伏）、
// 摆头发，叠上手里的道具，改眼睛、嘴和腮红，再按定好的颜色填像素。所有变化都是整格的，保持像素感。

/** 一帧四周的留白：两边给伞、躺下和头边的符号，头顶给伞面和往上飘的小东西 */
export const PAD_X = 8
export const PAD_TOP = 12
/** 立牌贴图的尺寸（贴图像素） */
export const RIG_W = FRAME_W + 2 * PAD_X
export const RIG_H = FRAME_H + PAD_TOP
/** 躺下时整帧转 90°（头朝左）：帧的左上角落在贴图的这里，身子贴着贴图底边 */
export const LIE_X = Math.floor((RIG_W - FRAME_H) / 2)
export const LIE_Y = RIG_H - FRAME_W + OX

/** 眼睛：睁、半闭、闭（眨眼）；亮（眼里一格高光）、笑（弯成 ^）、疼（> <）、惊（睁大）、
 *  往下看、困（眼皮耷拉） */
export type Eyes =
  'open' | 'half' | 'closed' | 'bright' | 'happy' | 'pained' | 'wide' | 'down' | 'sleepy'
/** 嘴：平时不画；说话一张一合，笑、惊讶、撇嘴、打哈欠 */
export type Mouth = 'none' | 'dot' | 'open' | 'smile' | 'o' | 'frown' | 'yawn'
/** 一组格子 [x, y, 颜色位] */
export type Cells = readonly (readonly [number, number, string])[]
/** 身上的颜色：病了脸色发青、发烧脸红、中毒发紫，死了褪色，倒下了压暗 */
export type Tint = 'pale' | 'fever' | 'poison' | 'dead' | 'incap'

/** 一帧怎么画：view 和 flip 是身子的朝向（朝左时整张翻过来），turn 是头另外的朝向（转身时头先转）；
 *  bodyDy、headDy 是身子和头往下挪几格（头只比身子低、不比身子高，不然脖子露缝），headDx 是头往前探
 *  几格（画面方向）；sway 是最软的头发往画面右边摆几格（负数往左），bounce 是垂下来的头发往下甩几格
 *  （只往下，拉长一格）；gaze 是眼珠往画面哪边挪一格。
 *  props 是姿势带的道具（人物坐标，跟着身子挪）：back 先画、被身子挡住，front 最后画，key 用来比对；
 *  lie 是整个人躺下；sparks 是冒出来的小东西（贴图上的格子，画面坐标，左上为原点），最后画。
 *  tint 是身上的颜色，wet 是淋湿的档（衣服压深、头发多一道湿亮），snow 是头顶、帽檐、伞面积雪的档，
 *  bandage 是头上缠绷带；sign 是头顶的符号（画面坐标的左下角，alpha 按有序抖动淡出） */
export interface Frame {
  view: View
  flip: boolean
  turn?: HeadTurn
  stance: Stance
  bodyDy: number
  headDy: number
  headDx: number
  sway: number
  bounce: number
  eyes: Eyes
  gaze: -1 | 0 | 1
  mouth: Mouth
  blush: 0 | 1 | 2
  props?: { key: string; back?: Cells; front?: Cells }
  lie: boolean
  sparks?: Cells
  tint?: Tint
  wet: 0 | 1 | 2
  snow: 0 | 1 | 2 | 3
  bandage: boolean
  sign?: { name: Sign; x: number; y: number; alpha: number }
}

/** 帧的指纹：和上一次一样就不重画 */
export function frameKey(f: Frame) {
  const legs = f.stance.legs.map((l) => l.join('.')).join('/')
  const toes = f.stance.toes?.map((t) => t.join('.')).join('/') ?? ''
  const sparks = f.sparks?.map((s) => s.join('')).join(',') ?? ''
  const sign = f.sign ? `${f.sign.name}${f.sign.x}.${f.sign.y}.${f.sign.alpha.toFixed(2)}` : ''
  return `${f.view}${+f.flip}${f.turn ? f.turn.view + +f.turn.mirror : ''}|${legs}|${toes}|${f.stance.arm}|${f.bodyDy}${f.headDy}${f.headDx}|${f.sway}${f.bounce}|${f.eyes}${f.gaze}${f.mouth}${f.blush}|${f.props?.key ?? ''}|${+f.lie}|${sparks}|${f.tint ?? ''}${f.wet}${f.snow}${+f.bandage}|${sign}`
}

/** 道具、天气、表情用到的颜色位（村民的调色板里没有的）：木头、饭菜、火苗、水、蓝、紫、雪 */
const EXTRA: Record<string, string> = {
  m: '#b98250',
  d: '#7a5230',
  u: '#f4d48a',
  k: '#e0582c',
  l: '#8ed0f4',
  B: '#3e78d8',
  V: '#9a6ad0',
  '~': '#f4f8ff',
  '-': '#c6d4e6',
}

/** 缓存的一组笔画：并排的数组，叠的时候不用一笔笔建对象 */
interface Built {
  n: number
  x: Int16Array
  y: Int16Array
  ch: Uint8Array
  group: Uint8Array
  flex: Float32Array
  color: Uint32Array
}

const code = (ch: string) => ch.charCodeAt(0)
/** 换色时分的几类格子：皮肤、衣服、头发高光、描边 */
const CLASS = new Uint8Array(128)
for (const c of 'sSJjv') CLASS[code(c)] = 1
for (const c of 'tTGqQoOpcaAbxEnN') CLASS[code(c)] = 2
CLASS[code('H')] = 3
CLASS[code('K')] = 4
const SHADE_TO: Record<Tint, [number, number, number]> = {
  pale: [0xc8, 0xd6, 0xc0],
  fever: [0xf4, 0xa0, 0x90],
  poison: [0xb8, 0x9a, 0xd8],
  dead: [0x8a, 0x8a, 0x96],
  incap: [0x9a, 0x92, 0xa0],
}
/** 按比例把小端 RGBA 像素往某个颜色混 */
function mixPx(c: number, [r, g, b]: [number, number, number], k: number) {
  const cr = c & 0xff,
    cg = (c >> 8) & 0xff,
    cb = (c >> 16) & 0xff
  return (
    (0xff000000 |
      (Math.round(cb + (b - cb) * k) << 16) |
      (Math.round(cg + (g - cg) * k) << 8) |
      Math.round(cr + (r - cr) * k)) >>>
    0
  )
}
/** 有序抖动的门槛：淡出时一格格消失，保持像素感 */
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
export const bayer = (x: number, y: number) => (BAYER[(y & 3) * 4 + (x & 3)] + 0.5) / 16
const K = code('K'),
  E = code('e'),
  W = code('W'),
  X = code('X'),
  J = code('J'),
  CHEEK = code('j'),
  SKIN = new Set([...'sSJjv'].map(code))

/** '#rrggbb' → 小端 RGBA 像素（不透明） */
function rgba(hex: string) {
  const n = parseInt(hex.slice(1), 16)
  return (0xff000000 | ((n & 0xff) << 16) | (n & 0xff00) | ((n >> 16) & 0xff)) >>> 0
}

/** 一个人的画法：长相、调色板和缓存的笔画；每帧按 Frame 画进 data（RIG_W × RIG_H 的 RGBA，自下而上） */
export class VillagerRig {
  readonly look: Look
  private readonly pal: Record<string, string>
  /** 颜色位 → 像素颜色：道具和后改的格子（眼睛、嘴）按它上色 */
  private readonly lut = new Uint32Array(128)
  private readonly cache = new Map<string, Built>()
  // 叠出来的一帧：每格的颜色和颜色位（按身子的朝向，翻转在填像素时做）
  private readonly color = new Uint32Array(RIG_W * RIG_H)
  private readonly ch = new Uint8Array(RIG_W * RIG_H)
  private readonly turned = new Uint32Array(RIG_W * RIG_H)

  constructor(key: string) {
    this.look = lookOf(key)
    this.pal = palette(this.look)
    const accent = this.pal.x
    const colors = { ...EXTRA, ...this.pal, C: accent, f: mixHex(accent, '#2a2230', 0.3) }
    for (const [k, v] of Object.entries(colors)) this.lut[code(k)] = rgba(v)
  }

  private built(view: View, arm: Stance['arm'], turn?: HeadTurn): Built {
    const key = `${view}|${arm}|${turn ? turn.view + +turn.mirror : ''}`
    let b = this.cache.get(key)
    if (b) return b
    const strokes = sketch(this.look, this.pal, view, { legs: [], arm }, turn)
    const n = strokes.length
    b = {
      n,
      x: new Int16Array(n),
      y: new Int16Array(n),
      ch: new Uint8Array(n),
      group: new Uint8Array(n),
      flex: new Float32Array(n),
      color: new Uint32Array(n),
    }
    strokes.forEach((s, i) => {
      b!.x[i] = s.x
      b!.y[i] = s.y
      b!.ch[i] = code(s.ch)
      b!.group[i] = s.group
      b!.flex[i] = s.flex
      b!.color[i] = rgba(s.color)
    })
    // 朝向、手臂和转头的组合有限，一个人最多十几组
    if (this.cache.size > 24) this.cache.delete(this.cache.keys().next().value!)
    this.cache.set(key, b)
    return b
  }

  private put(x: number, y: number, c: number, col = this.lut[c]) {
    if (x < 0 || y < 0 || x >= RIG_W || y >= RIG_H) return
    const i = y * RIG_W + x
    this.ch[i] = c
    this.color[i] = col
  }

  private at(x: number, y: number) {
    return x < 0 || y < 0 || x >= RIG_W || y >= RIG_H ? 0 : this.ch[y * RIG_W + x]
  }

  /** 画一帧到 data（RIG_W × RIG_H × 4，第一行是贴图最底下一行，直接交给 DataTexture） */
  draw(f: Frame, data: Uint8Array) {
    this.color.fill(0)
    this.ch.fill(0)
    const x0 = OX + PAD_X,
      y0 = OY + PAD_TOP
    // 腿：两格宽的黑块，不跟身子挪
    for (const [x, top, n] of f.stance.legs)
      for (let y = top; y < top + n; y++) {
        this.put(x + x0, y + y0, K)
        this.put(x + x0 + 1, y + y0, K)
      }
    for (const [x, y] of f.stance.toes ?? []) this.put(x + x0, y + y0, K)
    for (const [x, y, c] of f.props?.back ?? []) this.put(x + x0, y + y0 + f.bodyDy, code(c))
    // 身子和头：按组挪，软的头发再摆；画面方向的偏移在翻转的帧里反过来
    const b = this.built(f.view, f.stance.arm, f.turn)
    const dir = f.flip ? -1 : 1
    const sway = f.sway * dir,
      lean = f.headDx * dir
    for (let i = 0; i < b.n; i++) {
      const g = b.group[i]
      let x = b.x[i] + PAD_X,
        y = b.y[i] + PAD_TOP
      if (g === 1) y += f.bodyDy
      else if (g === 2) {
        x += lean
        y += f.headDy
      }
      const flex = b.flex[i]
      if (flex) {
        x += Math.round(sway * flex)
        // 往下甩时原处也留一笔：头发拉长一格，不和发根脱开
        if (flex > 0.3 && f.bounce > 0) {
          this.put(x, y, b.ch[i], b.color[i])
          y += f.bounce
        }
      }
      this.put(x, y, b.ch[i], b.color[i])
    }
    for (const [x, y, c] of f.props?.front ?? []) this.put(x + x0, y + y0 + f.bodyDy, code(c))
    this.face(f, f.gaze * dir)
    if (f.snow && !f.lie) this.snowOn(f.snow)
    if (f.tint || f.wet) this.recolor(f.tint, f.wet)
    // 填像素：躺下的先转过来，再翻转、自下而上
    let color = this.color
    if (f.lie) {
      color = this.turned
      color.fill(0)
      for (let fy = 0; fy < FRAME_H; fy++)
        for (let fx = 0; fx < FRAME_W; fx++) {
          const c = this.color[(fy + PAD_TOP) * RIG_W + fx + PAD_X]
          if (c) color[(LIE_Y + FRAME_W - 1 - fx) * RIG_W + LIE_X + fy] = c
        }
    }
    const out = new Uint32Array(data.buffer, data.byteOffset, RIG_W * RIG_H)
    for (let y = 0; y < RIG_H; y++) {
      const row = (RIG_H - 1 - y) * RIG_W,
        src = y * RIG_W
      if (f.flip) for (let x = 0; x < RIG_W; x++) out[row + x] = color[src + RIG_W - 1 - x]
      else out.set(color.subarray(src, src + RIG_W), row)
    }
    for (const [x, y, c] of f.sparks ?? [])
      if (x >= 0 && y >= 0 && x < RIG_W && y < RIG_H)
        out[(RIG_H - 1 - y) * RIG_W + x] = this.lut[code(c)]
    if (f.sign) {
      const { name, x: sx, y: sy, alpha } = f.sign
      const rows = SIGNS[name]
      rows.forEach((row, j) => {
        const y = sy - rows.length + 1 + j
        for (let i = 0; i < row.length; i++) {
          const x = sx + i
          if (row[i] === '.' || x < 0 || y < 0 || x >= RIG_W || y >= RIG_H) continue
          if (alpha < 1 && bayer(x, y) >= alpha) continue
          out[(RIG_H - 1 - y) * RIG_W + x] = this.lut[code(row[i])]
        }
      })
    }
  }

  /** 积雪：每一列最上面那格（头顶、帽子、伞面、肩膀）落白，厚了往下多盖一格、往上堆一格 */
  private snowOn(level: 1 | 2 | 3) {
    const white = code('~'),
      shade = code('-')
    for (let x = 0; x < RIG_W; x++) {
      let y = 0
      while (y < RIG_H && !this.ch[y * RIG_W + x]) y++
      if (y >= RIG_H) continue
      this.put(x, y, white)
      if (level >= 2 && this.at(x, y + 1) && this.at(x, y + 1) !== K) this.put(x, y + 1, shade)
      if (level >= 3 && (x + y) % 3) this.put(x, y - 1, white)
    }
  }

  /** 身上换色：病、死、倒下按类改皮肤或整个人，淋湿了衣服压深、头发多一道湿亮；同一种颜色只算一次 */
  private readonly shaded = new Map<number, number>()
  private shadedFor = ''
  private recolor(tint: Tint | undefined, wet: number) {
    const key = `${tint ?? ''}${wet}`
    if (key !== this.shadedFor) {
      this.shaded.clear()
      this.shadedFor = key
    }
    const w = wet / 2
    for (let i = 0; i < RIG_W * RIG_H; i++) {
      const c = this.color[i]
      if (!c) continue
      const cls = CLASS[this.ch[i]]
      const memo = c + cls * 0x100000000
      let out = this.shaded.get(memo)
      if (out === undefined) {
        out = c
        if (w && cls === 2) out = mixPx(out, [0x1c, 0x24, 0x36], 0.22 * w)
        if (w && cls === 3) out = mixPx(out, [0xff, 0xff, 0xff], 0.25 * w)
        if (tint === 'dead' && cls !== 4) out = mixPx(out, SHADE_TO.dead, 0.55)
        else if (tint === 'incap' && cls !== 4) out = mixPx(out, SHADE_TO.incap, 0.18)
        else if (tint && tint !== 'dead' && tint !== 'incap' && cls === 1)
          out = mixPx(out, SHADE_TO[tint], tint === 'pale' ? 0.45 : tint === 'fever' ? 0.35 : 0.4)
        this.shaded.set(memo, out)
      }
      this.color[i] = out
    }
  }

  /** 改脸：眼睛按状态重画（每只眼是一竖条「描边、描边、瞳色」，e 在最下面），眼珠往一边挪一格，
   *  画嘴、腮红。都只改皮肤上的格子：墨镜盖住眼睛就不动眼睛，胡子、猪鼻子盖住嘴就不画嘴 */
  private face(f: Frame, gaze: number) {
    if (f.eyes === 'open' && !gaze && f.mouth === 'none' && !f.blush && !f.bandage) return
    const set = (x: number, y: number, c: number) => this.put(x, y, c)
    const skin = (x: number, y: number) => SKIN.has(this.at(x, y))
    // 眼睛只在头那几行：人物的 8～20 行（坐下、低头时头会往下挪）
    const eyes: [number, number][] = []
    for (let y = PAD_TOP + OY + 8; y < PAD_TOP + OY + 21; y++)
      for (let x = 0; x < RIG_W; x++) if (this.ch[y * RIG_W + x] === E) eyes.push([x, y])
    if (!eyes.length || eyes.length > 2) return
    const side = eyes.length === 1 || f.view === 'side' || f.turn?.view === 'side'
    // 侧面不挪眼珠：只有一只眼，贴着脸的前沿。两只眼一起挪，有一只挪不过去（挨着头发）就都不挪
    let shift = f.view === 'down' && !side ? gaze : 0
    for (const [x, y] of eyes) if (!skin(x + shift, y) || !skin(x + shift, y - 2)) shift = 0
    const mid = eyes.length === 2 ? (eyes[0][0] + eyes[1][0]) / 2 : -1
    const s = code('s')
    if (f.eyes !== 'open' || shift)
      for (const [x, y] of eyes) {
        // 往脸中间那一边：闭眼、睁大画成两格宽
        const inward = mid < 0 ? -1 : x < mid ? 1 : -1
        const top = this.at(x, y - 2) === K ? y - 2 : y - 1
        for (let k = top; k <= y; k++) set(x, k, s)
        const ex = x + shift
        switch (f.eyes) {
          case 'open':
          case 'bright':
            set(ex, y - 2, f.eyes === 'bright' ? W : K)
            set(ex, y - 1, K)
            set(ex, y, E)
            break
          case 'wide':
            set(ex, y - 2, W)
            set(ex, y - 1, E)
            set(ex, y, E)
            if (skin(ex + inward, y - 2)) {
              set(ex + inward, y - 2, K)
              set(ex + inward, y - 1, K)
              set(ex + inward, y, K)
            }
            break
          case 'half':
            set(ex, y - 1, K)
            set(ex, y, E)
            break
          case 'sleepy':
            set(ex, y - 1, J)
            set(ex, y, K)
            if (skin(ex + inward, y)) set(ex + inward, y, K)
            break
          case 'closed':
            set(ex, y, K)
            if (skin(ex + inward, y)) set(ex + inward, y, K)
            break
          case 'down':
            set(ex, y - 1, J)
            set(ex, y, K)
            break
          case 'happy':
            set(ex, y - 1, K)
            if (skin(ex - 1, y)) set(ex - 1, y, K)
            if (skin(ex + 1, y)) set(ex + 1, y, K)
            break
          case 'pained': {
            // 正面左眼「>」、右眼「<」；侧面朝前那只按「<」
            const o = mid < 0 ? 1 : x < mid ? -1 : 1
            set(ex + o, y - 2, K)
            set(ex, y - 1, K)
            set(ex + o, y, K)
            break
          }
        }
      }
    if (f.mouth !== 'none' && f.view !== 'up') this.mouth(f.mouth, eyes, side)
    if (f.blush) this.blush(f.blush, eyes[0][1])
    if (f.bandage) this.bandage(eyes, side)
  }

  /** 绷带：额头上缠两行白布（只换头发那几格），正面脸颊上再贴一块；不画伤口 */
  private bandage(eyes: [number, number][], side: boolean) {
    const row = eyes[0][1] - 5
    const white = code('W'),
      gray = code('g')
    for (const y of [row, row + 1])
      for (let x = 0; x < RIG_W; x++) {
        const c = this.at(x, y)
        if (c && 'hHLw'.includes(String.fromCharCode(c))) this.put(x, y, (x + y) % 3 ? white : gray)
      }
    if (side || eyes.length < 2) return
    const [ex, ey] = eyes[0]
    for (const dx of [-1, 0])
      if (SKIN.has(this.at(ex + dx, ey + 1))) this.put(ex + dx, ey + 1, white)
  }

  /** 嘴：正面在两眼中间、眼睛下面两行；侧面贴着脸的前沿 */
  private mouth(kind: Mouth, eyes: [number, number][], side: boolean) {
    const set = (x: number, y: number, c: number) => {
      if (SKIN.has(this.at(x, y))) this.put(x, y, c)
    }
    const [ex, ey] = eyes[0]
    const y = ey + 2
    if (!side && eyes.length === 2) {
      const x = Math.round((eyes[0][0] + eyes[1][0]) / 2)
      // 嘴那一格不是皮肤（胡子、鼻子、面具盖着）就不画
      if (!SKIN.has(this.at(x, y))) return
      switch (kind) {
        case 'dot':
          set(x, y, K)
          break
        case 'open':
          set(x, y, X)
          set(x - 1, y, K)
          set(x + 1, y, K)
          break
        case 'o':
        case 'yawn':
          set(x, y, X)
          set(x, y - 1, K)
          if (kind === 'yawn') {
            set(x - 1, y, K)
            set(x + 1, y, K)
          }
          break
        case 'smile':
          set(x - 1, y - 1, K)
          set(x, y, K)
          set(x + 1, y - 1, K)
          break
        case 'frown':
          set(x - 1, y, K)
          set(x, y - 1, K)
          set(x + 1, y, K)
          break
      }
      return
    }
    // 侧面：从眼睛往前找到脸的前沿
    let fx = ex + 1
    while (fx < RIG_W - 1 && SKIN.has(this.at(fx + 1, y))) fx++
    if (!SKIN.has(this.at(fx, y))) return
    if (kind === 'open' || kind === 'o' || kind === 'yawn') {
      this.put(fx, y, X)
      if (this.at(fx + 1, y) === K) this.put(fx + 1, y, X)
      if (kind === 'yawn') set(fx, y - 1, X)
    } else set(fx, y, K)
  }

  /** 腮红：脸颊上的粉格加深，红透了再往外补一格 */
  private blush(level: 1 | 2, ey: number) {
    const pink = code('P'),
      red = code('r')
    for (let y = ey - 2; y <= ey + 3; y++)
      for (let x = 0; x < RIG_W; x++) {
        if (this.at(x, y) !== CHEEK) continue
        this.put(x, y, level === 2 ? red : pink)
        if (level === 2)
          for (const dx of [-1, 1]) if (SKIN.has(this.at(x + dx, y))) this.put(x + dx, y, pink)
      }
  }
}
