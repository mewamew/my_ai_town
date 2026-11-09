import { hash, mixHex } from '../pixel/noise'
import { sprite } from './sprite'

// 公园和海边的小摆设：长椅、遮阳伞和躺椅、花箱、芦苇、石头、投币望远镜、路口的指路牌。
// 地图按坐标立（Atlas 的 standees），只给画面看，不是道具，村民不用它们。
// 一个贴图像素对应一个地图像素，光从左上来：左边亮、右边暗。

const SHADE = '#2a2230'
const LIGHT = '#fff6e6'
const IRON = '#3b3a42'
const IRON_LIT = '#5f5e69'

/** 公园长椅：正对镜头，两根靠背板条、一块座板，铁扶手和铁腿 */
export function bench(seed: number) {
  const woods = ['#b98858', '#a8774c', '#c49464']
  const wood = woods[Math.floor(hash(seed, 1, 3) * woods.length)]
  return sprite(18, 11, ({ px, rect }) => {
    const slat = (y: number) => {
      rect(2, y, 14, 1, mixHex(wood, LIGHT, 0.18))
      rect(2, y + 1, 14, 1, mixHex(wood, SHADE, 0.12))
      px(15, y, mixHex(wood, SHADE, 0.2))
    }
    slat(0)
    slat(3)
    // 座板：前沿一道亮边，底下压一道影子
    rect(1, 6, 16, 1, mixHex(wood, LIGHT, 0.3))
    rect(1, 7, 16, 1, mixHex(wood, SHADE, 0.3))
    for (const x of [1, 16]) {
      rect(x, 0, 1, 8, IRON)
      px(x, 0, IRON_LIT)
    }
    // 扶手卷出去一点，铁腿落地
    rect(0, 5, 2, 1, IRON)
    rect(16, 5, 2, 1, IRON)
    for (const x of [2, 15]) rect(x, 8, 1, 3, IRON)
    px(2, 8, IRON_LIT)
  })
}

const PARASOLS: [string, string][] = [
  ['#d8483c', '#f4efe2'],
  ['#3f86c0', '#f4efe2'],
  ['#e8b53c', '#f4efe2'],
  ['#4fa08a', '#f4efe2'],
]

/** 沙滩遮阳伞：六瓣相间的伞面，伞沿一圈荷叶边，细伞杆斜插在沙里 */
export function parasol(seed: number) {
  const [a, b] = PARASOLS[Math.floor(hash(seed, 2, 5) * PARASOLS.length)]
  return sprite(24, 24, ({ px, rect }) => {
    for (let y = 2; y <= 9; y++) {
      const half = Math.round(11 * Math.sqrt(Math.max(0, 1 - ((9.5 - y) / 8) ** 2)))
      for (let x = 12 - half; x <= 11 + half; x++) {
        const panel = Math.floor(((x - 1) / 22) * 6)
        let c = panel % 2 ? b : a
        if (x > 16) c = mixHex(c, SHADE, 0.22)
        else if (x < 6) c = mixHex(c, LIGHT, 0.15)
        if (y === 2 + Math.floor((Math.abs(x - 11.5) / 11) * 3)) c = mixHex(c, LIGHT, 0.2)
        px(x, y, c)
      }
    }
    // 荷叶边：伞沿下面隔一个像素垂一点
    for (let x = 1; x <= 22; x++)
      if (x % 2) px(x, 10, mixHex(Math.floor(((x - 1) / 22) * 6) % 2 ? b : a, SHADE, 0.15))
    rect(11, 0, 2, 2, b)
    // 伞杆
    for (let y = 10; y < 24; y++) {
      const x = 11 + Math.floor((y - 10) / 9)
      px(x, y, '#ece4d4')
      px(x + 1, y, '#a8a090')
    }
  })
}

/** 躺椅：侧面看，一块斜靠背、一段平的座面，布面是条纹 */
export function deckChair(seed: number) {
  const [a, b] = PARASOLS[Math.floor(hash(seed, 3, 5) * PARASOLS.length)]
  return sprite(14, 8, ({ px, rect, line }) => {
    // 木框：斜靠背连着座面，两条腿
    line(1, 0, 5, 5, '#8a6440')
    line(5, 5, 13, 5, '#8a6440')
    line(2, 7, 5, 5, '#6e4e32')
    line(12, 7, 11, 5, '#6e4e32')
    // 布面
    for (let k = 0; k < 4; k++) px(1 + k, 1 + k, k % 2 ? b : a)
    for (let x = 6; x <= 12; x++) px(x, 4, x % 2 ? b : a)
    rect(6, 5, 7, 1, mixHex(a, SHADE, 0.35))
  })
}

/** 石砌花箱：箱子上沿一道亮边，里面一丛高低不一的花 */
export function planter(seed: number) {
  const flowers = ['#e8687a', '#f2c64e', '#f4efe2', '#b07cd0', '#ef8c4a']
  return sprite(18, 11, ({ px, rect }) => {
    for (let k = 0; k < 70; k++) {
      const x = 1 + Math.floor(hash(k, 1, seed) * 16)
      const top = 1 + Math.round(Math.abs(x - 8.5) / 3)
      const y = top + Math.floor(hash(k, 2, seed) * (6 - top))
      const leaf = hash(k, 3, seed)
      px(
        x,
        y,
        leaf < 0.5 ? (x > 12 ? '#3f6a3a' : '#5a8a4a') : leaf < 0.62 ? '#77a65a' : flowers[k % 5]
      )
    }
    rect(0, 5, 18, 1, '#e8e0cf')
    rect(0, 6, 18, 4, '#bcb3a2')
    rect(14, 6, 4, 4, '#a29a8a')
    rect(0, 6, 2, 4, '#cfc6b5')
    rect(0, 10, 18, 1, '#857d6f')
  })
}

/** 池边一丛芦苇和香蒲：细长的叶子往两边歪，几根顶着褐色的蒲棒 */
export function reeds(seed: number) {
  return sprite(12, 16, ({ px, line, rect }) => {
    for (let k = 0; k < 9; k++) {
      const x = 1 + Math.floor(hash(k, 1, seed) * 10)
      const top = 1 + Math.floor(hash(k, 2, seed) * 8)
      const lean = Math.round((hash(k, 3, seed) - 0.5) * 4)
      line(x, 15, x + lean, top, k % 3 ? '#6f8f4a' : '#93ad5f')
      if (k % 3 === 0) {
        rect(x + lean, top, 1, 3, '#7a4e2e')
        px(x + lean, top, '#9a6a42')
      }
    }
  })
}

/** 一块圆石头：左上亮、右下暗，顶上一片青苔 */
export function rock(seed: number) {
  const w = 9 + Math.floor(hash(seed, 1, 7) * 5)
  return sprite(w, 7, ({ px }) => {
    for (let y = 0; y < 7; y++)
      for (let x = 0; x < w; x++) {
        const dx = (x + 0.5 - w / 2) / (w / 2),
          dy = (y + 0.5 - 7) / 7
        if (dx * dx + dy * dy > 1) continue
        let c = dx < -0.3 && dy < -0.5 ? '#b8b2a4' : dx > 0.35 || dy > -0.2 ? '#7a7468' : '#9a9486'
        if (dy < -0.6 && hash(x, y, seed) < 0.6)
          c = hash(x, y, seed + 1) < 0.5 ? '#6f8a4e' : '#88a35c'
        px(x, y, c)
      }
  })
}

/** 投币望远镜：海边步道上朝海的那种，铁柱子顶着一个双筒的头 */
export function telescope() {
  return sprite(10, 17, ({ px, rect }) => {
    rect(4, 7, 2, 9, '#4f6272')
    px(4, 7, '#7d93a4')
    rect(2, 16, 6, 1, '#34424e')
    // 双筒的头：上沿亮，右边暗，前面两个镜筒口
    rect(1, 2, 8, 5, '#6f8698')
    rect(1, 2, 8, 1, '#a6bccb')
    rect(7, 3, 2, 4, '#4c5e6d')
    rect(2, 4, 2, 2, '#22303a')
    rect(5, 4, 2, 2, '#22303a')
    px(2, 4, '#7fb4d8')
    px(5, 4, '#7fb4d8')
    rect(3, 1, 4, 1, '#4c5e6d')
  })
}

/** 路口的木指路牌：一根立柱，上面钉两块箭头木牌（一块朝左一块朝右），柱脚一丛草 */
export function signpost(seed: number) {
  return sprite(16, 20, ({ px, rect }) => {
    rect(7, 2, 2, 18, '#7a5434')
    px(7, 2, '#9e7449')
    rect(8, 2, 1, 18, '#563a24')
    const board = (y: number, left: boolean, tone: string) => {
      const x0 = left ? 1 : 6
      rect(x0, y, 9, 3, tone)
      rect(x0, y, 9, 1, mixHex(tone, LIGHT, 0.25))
      rect(x0, y + 2, 9, 1, mixHex(tone, SHADE, 0.25))
      // 箭头尖
      px(left ? 0 : 15, y + 1, tone)
      for (let x = x0 + 2; x < x0 + 7; x += 2) px(x, y + 1, '#5a3e26')
    }
    board(3, true, '#c9a472')
    board(8, false, '#b8925f')
    for (let k = 0; k < 10; k++)
      px(
        4 + Math.floor(hash(k, 1, seed) * 8),
        17 + Math.floor(hash(k, 2, seed) * 3),
        k % 3 ? '#5a8a4a' : '#77a65a'
      )
  })
}
