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
// 摆头发、改眼睛，再按定好的颜色填像素。所有变化都是整格的，保持像素感。

/** 一帧四周的留白：两边给伞、躺下和头边的符号，头顶给伞面和往上飘的小东西 */
export const PAD_X = 8
export const PAD_TOP = 12
/** 立牌贴图的尺寸（贴图像素） */
export const RIG_W = FRAME_W + 2 * PAD_X
export const RIG_H = FRAME_H + PAD_TOP

/** 眼睛：睁、半闭、闭（眨眼），亮（抬头看天，眼里一格高光） */
export type Eyes = 'open' | 'half' | 'closed' | 'bright'

/** 一帧怎么画：view 和 flip 是身子的朝向（朝左时整张翻过来），turn 是头另外的朝向（转身时头先转）；
 *  bodyDy、headDy 是身子和头往下挪几格（头只比身子低、不比身子高，不然脖子露缝），headDx 是头往前探
 *  几格（画面方向）；sway 是最软的头发往画面右边摆几格（负数往左），bounce 是垂下来的头发往下甩几格
 *  （只往下，拉长一格）；gaze 是眼珠往画面哪边挪一格 */
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
}

/** 帧的指纹：和上一次一样就不重画 */
export function frameKey(f: Frame) {
  const legs = f.stance.legs.map((l) => l.join('.')).join('/')
  const toes = f.stance.toes?.map((t) => t.join('.')).join('/') ?? ''
  return `${f.view}${+f.flip}${f.turn ? f.turn.view + +f.turn.mirror : ''}|${legs}|${toes}|${f.stance.arm}|${f.bodyDy}${f.headDy}${f.headDx}|${f.sway}${f.bounce}|${f.eyes}${f.gaze}`
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
const K = code('K'),
  E = code('e'),
  W = code('W'),
  SKIN = new Set([...'sSJjv'].map(code))

/** '#rrggbb' → 小端 RGBA 像素（不透明） */
function rgba(hex: string) {
  const n = parseInt(hex.slice(1), 16)
  return (0xff000000 | ((n & 0xff) << 16) | (n & 0xff00) | ((n >> 16) & 0xff)) >>> 0
}

/** 一个人的画法：长相、调色板和缓存的笔画；每帧按 Frame 画进 data（RIG_W × RIG_H 的 RGBA，自下而上） */
export class VillagerRig {
  private readonly look: Look
  private readonly pal: Record<string, string>
  /** 颜色位 → 像素颜色：改眼睛这类后改的格子按它上色 */
  private readonly lut = new Uint32Array(128)
  private readonly cache = new Map<string, Built>()
  // 叠出来的一帧：每格的颜色和颜色位（按身子的朝向，翻转在填像素时做）
  private readonly color = new Uint32Array(RIG_W * RIG_H)
  private readonly ch = new Uint8Array(RIG_W * RIG_H)

  constructor(key: string) {
    this.look = lookOf(key)
    this.pal = palette(this.look)
    for (const [k, v] of Object.entries(this.pal)) this.lut[code(k)] = rgba(v)
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

  /** 画一帧到 data（RIG_W × RIG_H × 4，第一行是贴图最底下一行，直接交给 DataTexture） */
  draw(f: Frame, data: Uint8Array) {
    const color = this.color,
      ch = this.ch
    color.fill(0)
    ch.fill(0)
    const put = (x: number, y: number, c: number, col: number) => {
      if (x < 0 || y < 0 || x >= RIG_W || y >= RIG_H) return
      const i = y * RIG_W + x
      ch[i] = c
      color[i] = col
    }
    // 腿：两格宽的黑块，不跟身子挪
    const black = this.lut[K]
    for (const [x, top, n] of f.stance.legs)
      for (let y = top; y < top + n; y++) {
        put(x + OX + PAD_X, y + OY + PAD_TOP, K, black)
        put(x + OX + 1 + PAD_X, y + OY + PAD_TOP, K, black)
      }
    for (const [x, y] of f.stance.toes ?? []) put(x + OX + PAD_X, y + OY + PAD_TOP, K, black)
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
          put(x, y, b.ch[i], b.color[i])
          y += f.bounce
        }
      }
      put(x, y, b.ch[i], b.color[i])
    }
    this.face(f, f.gaze * dir)
    // 填像素：翻转、自下而上
    const out = new Uint32Array(data.buffer, data.byteOffset, RIG_W * RIG_H)
    for (let y = 0; y < RIG_H; y++) {
      const row = (RIG_H - 1 - y) * RIG_W,
        src = y * RIG_W
      if (f.flip) for (let x = 0; x < RIG_W; x++) out[row + x] = color[src + RIG_W - 1 - x]
      else out.set(color.subarray(src, src + RIG_W), row)
    }
  }

  /** 眼睛：每只眼是一竖条「描边、描边、瞳色」，e 在最下面。按状态重画，gaze 让眼珠往一边挪一格 */
  private face(f: Frame, gaze: number) {
    if (f.eyes === 'open' && !gaze) return
    const ch = this.ch,
      color = this.color
    const at = (x: number, y: number) =>
      x < 0 || y < 0 || x >= RIG_W || y >= RIG_H ? 0 : ch[y * RIG_W + x]
    const set = (x: number, y: number, c: number) => {
      if (x < 0 || y < 0 || x >= RIG_W || y >= RIG_H) return
      const i = y * RIG_W + x
      ch[i] = c
      color[i] = this.lut[c]
    }
    // 眼睛只在头那几行：人物的 8～18 行
    const eyes: [number, number][] = []
    for (let y = PAD_TOP + OY + 8; y < PAD_TOP + OY + 19; y++)
      for (let x = 0; x < RIG_W; x++) if (ch[y * RIG_W + x] === E) eyes.push([x, y])
    if (!eyes.length || eyes.length > 2) return
    const skin = code('s')
    // 侧面不挪眼珠：只有一只眼，贴着脸的前沿。两只眼一起挪，有一只挪不过去（挨着头发）就都不挪
    let shift = f.view === 'down' && f.turn?.view !== 'side' ? gaze : 0
    for (const [x, y] of eyes)
      if (!SKIN.has(at(x + shift, y)) || !SKIN.has(at(x + shift, y - 2))) shift = 0
    const mid = eyes.length === 2 ? (eyes[0][0] + eyes[1][0]) / 2 : -1
    for (const [x, y] of eyes) {
      // 往脸中间那一边：闭眼画成两格宽的一道
      const inward = mid < 0 ? -1 : x < mid ? 1 : -1
      const top = at(x, y - 2) === K ? y - 2 : y - 1
      for (let k = top; k <= y; k++) set(x, k, skin)
      const ex = x + shift
      switch (f.eyes) {
        case 'open':
        case 'bright':
          set(ex, y - 2, f.eyes === 'bright' ? W : K)
          set(ex, y - 1, K)
          set(ex, y, E)
          break
        case 'half':
          set(ex, y - 1, K)
          set(ex, y, E)
          break
        case 'closed':
          set(ex, y, K)
          if (SKIN.has(at(ex + inward, y))) set(ex + inward, y, K)
          break
      }
    }
  }
}
