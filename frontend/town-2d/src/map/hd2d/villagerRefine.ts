// 村民的精修：一帧叠好（发型、衣服、姿势、表情、道具、天气都画完）之后，再过一遍颜色。
// 原画的格子、比例、形状一格不动，只改三样：
//   1. 描边跟着颜色走。每格描边看一圈邻居，取最深那块的颜色再压深：头发的边是头发的深色，衣服的边是
//      衣服的深色，脸露在外面的边（侧脸、手）是深棕红。纯黑的边在有明暗的场景里像贴纸。
//   2. 暗面。头发、衣服右边和下边贴着边的格子压一档，光从左上来（和头顶那道高光一致）。脸不压：
//      脸只有五行高，压了显脏。
//   3. 刘海的影子。头发正下方那行皮肤压一档，头发像盖在脸上。
// 眼睛、嘴这些脸上的墨留深色，形状不变。立牌（villagerRig.ts）和头像、捏人预览（villagerSprite.ts 的
// drawFrame）共用这一个函数，两边的样子不会分叉。

const code = (ch: string) => ch.charCodeAt(0)

/** 颜色位 → 材质：0 透明和描边，1 头发，2 皮肤，3 眼睛，4 布和别的，5 金属。立牌的法线图也按它分材质 */
export const MATERIAL = new Uint8Array(128).fill(4)
MATERIAL[0] = 0
MATERIAL[code('K')] = 0
for (const c of 'hHLw') MATERIAL[code(c)] = 1
for (const c of 'sSJjvP') MATERIAL[code(c)] = 2
MATERIAL[code('e')] = 3
MATERIAL[code('%')] = 3
for (const c of 'YUM') MATERIAL[code(c)] = 5

/** 加工时的分类：-1 透明，0 描边，1 头发，2 皮肤，3 眼睛（不加工），4 别的（金属也算） */
const OUTLINE = 0,
  HAIR = 1,
  SKIN = 2,
  EYE = 3,
  CLOTH = 4
const KIND = new Int8Array(128)
for (let c = 0; c < 128; c++) KIND[c] = MATERIAL[c] === 5 ? CLOTH : MATERIAL[c]
KIND[0] = -1

type Rgb = readonly [number, number, number]
/** 描边：那块颜色乘上这层深色，再把亮度压到上限以内。上限三种材质一样：下巴那条线要是比头发的边浅，
 *  会被看成皮肤往下多长了一行，像脖子变长；白衬衫、灰头发的边太亮则像一圈光晕 */
const DEEP: Record<number, Rgb> = {
  [HAIR]: [0.4, 0.31, 0.38],
  [SKIN]: [0.33, 0.2, 0.22],
  [CLOTH]: [0.38, 0.32, 0.46],
}
const DEEP_MAX = 60
/** 暗面：一档。头发、布偏冷，皮肤偏红 */
const SHADE: Record<number, Rgb> = {
  [HAIR]: [0.77, 0.72, 0.84],
  [SKIN]: [0.94, 0.82, 0.78],
  [CLOTH]: [0.8, 0.77, 0.89],
}
/** 脸上的墨（眼睛、嘴）：比纯黑暖一点的深色 */
const INK = 0xff30222c

// 像素是小端 RGBA（0xAABBGGRR），和立牌贴图一致
const R = (c: number) => c & 0xff,
  G = (c: number) => (c >> 8) & 0xff,
  B = (c: number) => (c >> 16) & 0xff
const pack = (r: number, g: number, b: number) =>
  (0xff000000 | (Math.round(b) << 16) | (Math.round(g) << 8) | Math.round(r)) >>> 0
const lum = (c: number) => 0.299 * R(c) + 0.587 * G(c) + 0.114 * B(c)

/** 一块颜色的描边色。kind 省略时按布算：鞋就是裤子的描边色 */
export function deepOf(c: number, kind: number = CLOTH) {
  const t = DEEP[kind]
  let r = R(c) * t[0],
    g = G(c) * t[1],
    b = B(c) * t[2]
  const l = 0.299 * r + 0.587 * g + 0.114 * b
  if (l > DEEP_MAX) {
    const k = DEEP_MAX / l
    r *= k
    g *= k
    b *= k
  }
  return pack(r, g, b)
}
function shade(c: number, kind: number) {
  const t = SHADE[kind]
  return pack(R(c) * t[0], G(c) * t[1], B(c) * t[2])
}

const AROUND = [0, 1, 1, 0, -1, 0, 0, -1, 1, 1, -1, 1, 1, -1, -1, -1]

/** 就地加工一帧：px 是 w × h 的像素（自上而下，0 是透明），ch 是每格的颜色位，描边的颜色位是 K。
 *  scratch 是同样大的草稿（留一份加工前的颜色，邻格都从它借）；lone 是四周借不到颜色的描边用的颜色
 *  （抬起来只剩一行的脚、伞柄这种单格宽的线），给裤子的描边色，鞋的颜色才不随迈步变。
 *  要在画面方向上做（翻转、躺下之后），光才总是从左上来 */
export function refineVillager(
  px: Uint32Array,
  ch: Uint8Array,
  w: number,
  h: number,
  scratch: Uint32Array,
  lone: number
) {
  const n = w * h
  scratch.set(px.subarray(0, n))
  const kind = (x: number, y: number) =>
    x < 0 || y < 0 || x >= w || y >= h || !scratch[y * w + x] ? -1 : KIND[ch[y * w + x]]
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const i = y * w + x
      if (!scratch[i]) continue
      const k = KIND[ch[i]]
      if (k === EYE) continue
      if (k === OUTLINE) {
        // 眼睛上面那两格，和脸上别的墨（至少两面挨着皮肤、没挨着头发衣服和外面）：留深色
        let skin = 0,
          other = 0
        for (let j = 0; j < 8; j += 2) {
          const m = kind(x + AROUND[j], y + AROUND[j + 1])
          if (m === SKIN || m === EYE) skin++
          else if (m !== OUTLINE) other++
        }
        const below = kind(x, y + 1)
        if (
          below === EYE ||
          (below === OUTLINE && kind(x, y + 2) === EYE) ||
          (skin >= 2 && !other)
        ) {
          px[i] = INK
          continue
        }
        // 借颜色：先看四邻，没有再看斜角；挑最深的那块，描边归深色的一边，浅色那边的边才利落
        let from = 0,
          fromKind = CLOTH,
          best = 1e9
        for (let j = 0; j < 16 && !(j === 8 && from); j += 2) {
          const nx = x + AROUND[j],
            ny = y + AROUND[j + 1]
          const m = kind(nx, ny)
          if (m <= OUTLINE || m === EYE) continue
          const c = scratch[ny * w + nx]
          const l = lum(c)
          if (l < best) {
            best = l
            from = c
            fromKind = m
          }
        }
        px[i] = from ? deepOf(from, fromKind) : lone
        continue
      }
      if (k === SKIN) {
        // 刘海的影子：正上方是头发，或者隔着一格描边是头发
        const up = kind(x, y - 1)
        if (up === HAIR || (up === OUTLINE && kind(x, y - 2) === HAIR)) px[i] = shade(scratch[i], k)
        continue
      }
      // 头发、衣服、道具：右边或下边贴着描边、贴着外面的格子压一档
      if (kind(x + 1, y) <= OUTLINE || kind(x, y + 1) <= OUTLINE) px[i] = shade(scratch[i], k)
    }
}
