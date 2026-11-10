import { hash, mixHex } from '../pixel/noise'
import type { DecorKind } from './propArrange'
import { Kit, P, T } from './propKit'

// 各件道具的搭法：按道具定义编号登记，没登记的道具照旧用像素图立牌（props.ts）。
// 家具按村民的身子定大小：柜台 4.5 个墙面像素高，到村民的脖子；椅面 3 个墙面像素高。
// 加一件：写一个搭法，在 BUILDS 里登记定义编号；只在某些地方才这样画的（座位在室外是长椅、石沿）
// 在 buildOf 里判断。

/** 搭一件：往 Kit 里放料；seed 按道具实例编号来，同一件每次搭出来一样 */
export type Build = (k: Kit, seed: number) => void

const WOOD = { dark: '#6b4530', mid: '#96673f', light: '#c4925c', pale: '#dbb07a', line: '#4c2f22' }
const CREAM = '#f1e6cd'
const WHITE = '#f6f1e7'
const IRON = '#45444e'
const BRASS = '#e0ac48'
const GREEN = { dark: '#2c5546', mid: '#3f7a61', light: '#5a9a7c' }
const WARM = '#ffd58a'
const LAMP = '#ffbf73'

/** 柜体：一排柜门（顶上一道横框、门芯上一颗拉手、底下踢脚），上面压一块探出来的台面。返回台面的高度 */
function cabinet(
  k: Kit,
  w: number,
  d: number,
  c: { frame: string; core: string; slab: string; edge: string },
  doors: number
) {
  k.box(-w, w, -d, d, 0, 4 * T, {
    all: c.core,
    south: (u, v, nu, nv) => {
      if (v === nv - 1) return WOOD.line
      const span = Math.round(nu / doors)
      const i = u % span
      if (v === 0 || i === 0 || i === span - 1) return c.frame
      if (v === 1 && i === span - 2) return BRASS
      return c.core
    },
    top: false,
  })
  k.box(-w - 3, w + 3, -d - 1, d + 3, 4 * T, 4.5 * T, {
    all: c.edge,
    top: (u, v, nu, nv) => (v === nv - 1 ? c.edge : c.slab),
  })
  return 4.5 * T
}
const WALNUT = { frame: WOOD.dark, core: WOOD.mid, slab: WOOD.pale, edge: WOOD.light }

/** 台灯：黄铜底座和灯杆，灯罩入夜亮，照亮脚下一圈 */
function tableLamp(k: Kit, x: number, z: number, y: number, reach: number) {
  k.prism(x, z, 4.2, y, y + 0.3 * T, BRASS, BRASS)
  k.box(x - 1.5, x + 1.5, z - 1.5, z + 1.5, y + 0.3 * T, y + 1.4 * T, { all: BRASS })
  k.shade(x, z, 9.5, y + 1.4 * T, y + 3 * T, WARM, 6)
  k.lamp([x, y + 2.2 * T, z], LAMP, reach, 72)
}

/** 咖啡馆靠墙的内侧柜台：两摞杯子、两只豆罐、蛋糕架、一盆绿植 */
const backCounter: Build = (k) => {
  k.footprint(51, 16)
  k.wall = true
  const y = cabinet(k, 48, 15, WALNUT, 2)
  k.box(-42, -36, -9, -3, y, y + 1.6 * T, {
    all: WHITE,
    south: (u, v) => (v % 2 ? '#d8d0c0' : WHITE),
  })
  k.box(-33, -27, -6, 0, y, y + 1 * T, { all: WHITE })
  k.box(-21, -15, -9, -3, y, y + 2 * T, {
    all: '#7a4a2c',
    south: (u, v) => (v ? '#7a4a2c' : BRASS),
    top: BRASS,
  })
  k.box(-12, -6, -9, -3, y, y + 1.5 * T, { all: '#8fa25c', top: BRASS })
  k.prism(9, -3, 9.5, y, y + 0.3 * T, WHITE, WHITE)
  k.prism(9, -3, 6.8, y + 0.3 * T, y + 1.3 * T, '#eaa9b7', '#f8e2e6')
  k.box(7.5, 10.5, -4.5, -1.5, y + 1.3 * T, y + 1.6 * T, { all: '#c8323e' })
  k.box(30, 42, -9, 3, y, y + 1 * T, { all: '#bb6a44', top: '#8a4a30' })
  k.box(27, 45, -12, 6, y + 1 * T, y + 2.4 * T, {
    all: '#4f8f52',
    south: (u, v) => ((u + v) % 2 ? '#4f8f52' : '#6fae62'),
    top: (u, v) => ((u + v) % 2 ? '#6fae62' : '#8cc474'),
  })
}

/** 咖啡机：矮柜上一台机器，红饰板和黄铜表，凹槽里两个冲煮头，接水盘上两只杯子；冒热气，指示灯常亮 */
const coffeeMachine: Build = (k) => {
  k.footprint(27, 16)
  k.wall = true
  // 人站在机器右前方，不把机器挡住
  k.use = { at: [30, 32] }
  const y = cabinet(k, 24, 15, WALNUT, 1)
  const top = y + 3 * T
  const red = '#c94a3f',
    chrome = '#cdd0d7'
  const rows = ['rrrrbr', 'kckkck', 'gwggwg']
  const tone: Record<string, string> = {
    r: red,
    b: BRASS,
    k: '#2e2c34',
    c: '#a3a7b1',
    g: '#74777f',
    w: WHITE,
  }
  k.box(-18, 18, -12, 6, y, top, {
    all: chrome,
    south: (u, v) => tone[rows[v]?.[u] ?? 'g'],
    east: (u, v) => (v === 0 ? red : chrome),
    west: (u, v) => (v === 0 ? red : chrome),
    top: '#dcdfe5',
  })
  for (const x of [-15, -6]) k.box(x, x + 6, -9, -3, top, top + 0.8 * T, { all: WHITE })
  k.box(6, 18, -12, -3, top, top + 1.7 * T, { all: '#6a4329', top: '#4b2f1e' })
  k.glow(12.6, 15.6, 5.6, 6.7, top - 0.75 * T, top - 0.25 * T, '#ffd25e', true)
  k.steam.push([-10, top + 1 * T, -3], [-1, top + 1 * T, -5])
  k.lamp([12, top - 0.5 * T, 10], '#ffb45e', 54, 30, 0.55)
}

/** 茶席：矮柜上一只茶盘，青瓷茶壶和三只茶杯，壶口冒热气 */
const teaTable: Build = (k) => {
  k.footprint(27, 16)
  k.wall = true
  k.use = { at: [30, 32] }
  const y = cabinet(k, 24, 15, WALNUT, 1)
  k.box(-21, 21, -10, 8, y, y + 0.25 * T, { all: '#5a3d2c', top: '#7a5238' })
  const tray = y + 0.25 * T
  const celadon = '#9fc9b4',
    glaze = '#c4e2d2'
  k.prism(-8, -2, 8.5, tray, tray + 1.3 * T, celadon, glaze, 7)
  k.prism(-8, -2, 3.2, tray + 1.3 * T, tray + 1.6 * T, '#7fae98', glaze)
  k.box(-1, 5, -3.5, -0.5, tray + 0.6 * T, tray + 1 * T, { all: celadon })
  for (const [x, z] of [
    [10, -5],
    [16, 2],
    [8, 3],
  ])
    k.prism(x, z, 3, tray, tray + 0.5 * T, WHITE, '#c79a52')
  k.steam.push([-8, tray + 2 * T, -2])
}

/** 点单柜台：绿漆柜身，正中一块画着咖啡杯的牌子；收银机的屏一直亮，菜单牌、小费罐、花瓶、按铃 */
const orderCounter: Build = (k) => {
  k.footprint(51, 18)
  const y = cabinet(
    k,
    48,
    15,
    { frame: GREEN.dark, core: GREEN.mid, slab: CREAM, edge: '#dfd2b4' },
    2
  )
  k.box(-12, 12, 15, 15.8, 1 * T, 3 * T, {
    all: CREAM,
    south: (u, v) => (v === 0 && (u === 1 || u === 2) ? '#8a5a3a' : CREAM),
    north: false,
    top: false,
  })
  k.box(21, 39, -9, 6, y, y + 1.4 * T, { all: '#5d4635', top: '#7d624a' })
  k.box(24, 36, -12, -6, y + 1.4 * T, y + 2.6 * T, { all: '#3d2e24', top: '#5d4635' })
  k.glow(26, 34, -6, -5.2, y + 1.6 * T, y + 2.4 * T, '#ffe2a0', true)
  k.box(-42, -30, 0, 3, y, y + 2 * T, {
    all: CREAM,
    south: (u, v) => (v === 0 ? '#d07f52' : '#cdbd9c'),
  })
  k.box(-24, -18, -3, 3, y, y + 1.1 * T, { all: '#bfe0dc', top: BRASS })
  k.box(-9, -3, -6, 0, y, y + 1 * T, { all: '#6fa9c7' })
  k.box(-12, 0, -9, 3, y + 1 * T, y + 2 * T, {
    all: '#e8687a',
    south: (u, v) => ((u + v) % 2 ? '#e8687a' : '#f2c64e'),
    top: (u, v) => ((u + v) % 2 ? '#f6a3b0' : '#f8dc7c'),
  })
  k.prism(9, 3, 3.6, y, y + 0.5 * T, BRASS, '#f3cf7a')
}

const PASTRY = ['#dba24f', '#e25a70', '#f8efdb', '#80492d', '#f4cb52']
/** 糕点柜：木底座上一只玻璃柜，两层糕点中间一道搁板；柜里一条暖灯入夜亮 */
const pastryCase: Build = (k) => {
  k.footprint(38, 17)
  const w = 36,
    d = 15
  k.box(-w, w, -d, d, 0, 2 * T, {
    all: WOOD.mid,
    south: (u, v, nu) =>
      v === 1 ? WOOD.line : u === 0 || u === nu - 1 || u % 3 === 2 ? WOOD.dark : WOOD.mid,
    top: false,
  })
  const glass = '#d5e8e4',
    frame = '#f6eedb',
    shelf = '#e9e0c9'
  const pane = (u: number, v: number, nu: number) =>
    u === 0 || u === nu - 1 ? frame : v === 1 ? shelf : glass
  k.box(-w, w, -d, d, 2 * T, 5 * T, {
    south: (u, v, nu) =>
      u === 0 || u === nu - 1
        ? frame
        : v === 1
          ? shelf
          : u % 2
            ? PASTRY[((u >> 1) + v) % PASTRY.length]
            : glass,
    north: glass,
    east: pane,
    west: pane,
    top: false,
  })
  k.box(-w - 2, w + 2, -d - 1, d + 2, 5 * T, 5.4 * T, { all: frame })
  k.glow(-w + 6, w - 6, d, d + 0.8, 4.65 * T, 5 * T, '#ffe9b8')
  k.lamp([0, 3.5 * T, d + 6], '#ffc878', 96, 54, 0.8)
}

/** 小圆桌：铁脚、圆台面。返回台面的高度 */
function roundTable(k: Kit, cx: number, cz: number, r: number) {
  k.prism(cx, cz, r * 0.55, 0, 0.4 * T, IRON, '#55545f')
  k.prism(cx, cz, 4.5, 0.4 * T, 3.4 * T, IRON)
  k.prism(cx, cz, r, 3.4 * T, 3.8 * T, '#d9ccb0', CREAM)
  return 3.8 * T
}

/** 木椅：四条腿、座板和红坐垫、横档靠背；back 是靠背在北（-1，人朝南坐）还是在南（1，背对镜头） */
function woodChair(k: Kit, cx: number, cz: number, back: -1 | 1) {
  for (const x of [-15, 9])
    for (const z of [-15, 9])
      k.box(cx + x, cx + x + 6, cz + z, cz + z + 6, 0, 2.4 * T, { all: WOOD.dark, top: false })
  k.box(cx - 15, cx + 15, cz - 15, cz + 15, 2.4 * T, 3 * T, { all: WOOD.light })
  k.box(cx - 12, cx + 12, cz - 12, cz + 12, 3 * T, 3.4 * T, { all: '#bd554c', top: '#d6776a' })
  const z0 = back < 0 ? cz - 15 : cz + 9
  const rails = (u: number, v: number, nu: number) =>
    u === 0 || u === nu - 1 ? WOOD.light : v === 1 ? WOOD.mid : WOOD.pale
  k.box(cx - 15, cx + 15, z0, z0 + 6, 3 * T, 6 * T, { all: WOOD.mid, south: rails, north: rails })
}

/** 桌上的东西：一杯咖啡、一碟蛋糕、一枝花 */
function tableware(k: Kit, cx: number, cz: number, y: number) {
  k.prism(cx - 12, cz - 6, 6.5, y, y + 0.12 * T, WHITE, WHITE)
  k.box(cx - 15, cx - 9, cz - 9, cz - 3, y + 0.12 * T, y + 0.9 * T, { all: WHITE, top: '#6f4528' })
  k.prism(cx + 8, cz - 10, 6.5, y, y + 0.12 * T, WHITE, WHITE)
  k.box(cx + 5, cx + 11, cz - 13, cz - 7, y + 0.12 * T, y + 0.75 * T, {
    all: '#f4cb52',
    top: '#f8efdb',
  })
  k.box(cx + 3, cx + 9, cz + 6, cz + 12, y, y + 0.9 * T, { all: '#6fa9c7' })
  k.box(cx + 3, cx + 9, cz + 6, cz + 12, y + 0.9 * T, y + 1.6 * T, {
    all: '#e8687a',
    top: '#f6a3b0',
  })
}

/** 咖啡馆的木椅：椅子在落点，南边摆一张小圆桌；人站在椅子和桌子之间 */
const cafeChair: Build = (k) => {
  k.footprint(24, 46.5, 9, 31.5)
  k.use = { at: [0, 17] }
  woodChair(k, 0, 0, -1)
  tableware(k, 9, 54, roundTable(k, 9, 54, 24))
}

const SOFAS = [
  ['#629a5e', '#8aba7e', '#467a4e'],
  ['#d09a3e', '#ecc468', '#ac7a2c'],
  ['#c9704e', '#e59674', '#a4563a'],
]
/** 扶手椅：软垫、两只扶手、钉扣靠背、一只靠枕；旁边一张边几，上面一盏台灯。人坐在坐垫上 */
const armchair: Build = (k, seed) => {
  k.footprint(40.5, 24, 13.5, 0)
  k.lounge = true
  // 歇着的人坐在坐垫上
  k.use = { at: [0, 12], lift: 2.6 * T }
  const [main, light, shade] = SOFAS[Math.floor(hash(seed, 3, 11) * SOFAS.length)]
  k.box(-24, 24, -21, 21, 0, 0.6 * T, { all: WOOD.dark, top: false })
  k.box(-15, 15, -12, 24, 0.6 * T, 2.6 * T, { all: main, top: light })
  for (const x of [-27, 15])
    k.box(x, x + 12, -18, 24, 0.6 * T, 4 * T, {
      all: main,
      top: light,
      south: (u, v) => (v === 0 ? light : main),
    })
  k.box(-27, 27, -24, -12, 0.6 * T, 6.2 * T, {
    all: main,
    south: (u, v) => (v === 0 ? light : v < 4 && u % 2 === 1 && v % 2 === 1 ? shade : main),
    top: light,
  })
  k.box(-9, 9, -12, -6, 2.6 * T, 4.5 * T, {
    all: CREAM,
    south: (u, v) => (v === 1 ? '#e2c98f' : CREAM),
    top: '#fbf5e4',
  })
  const tx = 42,
    tz = -9
  k.prism(tx, tz, 3.5, 0, 3 * T, WOOD.dark)
  k.prism(tx, tz, 12, 3 * T, 3.4 * T, WOOD.light, WOOD.pale)
  tableLamp(k, tx, tz, 3.4 * T, 135)
}

const BLANKETS = [
  ['#c05a50', '#e39a86'],
  ['#5385b8', '#9cbfde'],
  ['#629a5e', '#a6c996'],
  ['#d09a3e', '#f0d8a0'],
]
/** 单人床：横着摆，床头在西（村民睡觉是头朝西躺的），长边靠墙；床头外一只床头柜和小灯。人躺在被子上 */
const bed: Build = (k, seed) => {
  k.footprint(72, 27, -12, 0)
  k.wall = true
  k.use = { at: [2, 25], lift: 2.4 * T }
  const [main, stripe] = BLANKETS[Math.floor(hash(seed, 5, 13) * BLANKETS.length)]
  k.box(-54, 54, -27, 27, 0, 1.8 * T, { all: WOOD.mid, top: false })
  k.box(-51, -15, -24, 24, 1.8 * T, 2.7 * T, { all: WHITE })
  k.box(-48, -30, -15, 15, 2.7 * T, 3.5 * T, { all: CREAM, top: '#fdf8ea' })
  // 被子：靠枕头的一头翻出一道白边，被面隔几格一道条纹
  const quilt = (u: number) =>
    u === 0 ? WHITE : u === 1 ? '#e6dfce' : (u - 2) % 4 === 3 ? stripe : main
  k.box(-15, 54, -27, 27, 1.8 * T, 3.1 * T, {
    all: main,
    top: (u) => quilt(u),
    south: (u, v, nu, nv) => (v === nv - 1 ? stripe : quilt(u)),
  })
  const board = (u: number, v: number) => (v === 0 ? WOOD.pale : u % 2 ? WOOD.mid : WOOD.light)
  k.box(-60, -54, -27, 27, 0, 6 * T, {
    all: WOOD.mid,
    south: WOOD.dark,
    east: board,
    top: WOOD.pale,
  })
  for (const z of [-27, 21])
    k.box(-60, -54, z, z + 6, 6 * T, 6.7 * T, { all: WOOD.dark, top: WOOD.light })
  k.box(54, 60, -27, 27, 0, 3.2 * T, { all: WOOD.mid, south: WOOD.dark, top: WOOD.pale })
  k.box(-84, -63, -27, -3, 0, 3 * T, {
    all: WOOD.mid,
    south: (u, v, nu, nv) =>
      v === nv - 1
        ? WOOD.line
        : v === 0 || u === 0 || u === nu - 1
          ? WOOD.dark
          : u === 2 && v === 1
            ? BRASS
            : WOOD.mid,
    top: WOOD.pale,
  })
  tableLamp(k, -73, -15, 3 * T, 150)
}

/** 干粮袋：鼓肚子、扎口的麻袋，旁边靠着一小袋和两块干粮 */
const rationSack: Build = (k) => {
  k.footprint(26.5, 18, 3.5, 0)
  const tones = ['#d6b47a', '#c5a168', '#b18d57']
  k.prism(-6, 0, 17, 0, 3 * T, (side, v) => tones[v] ?? tones[2], undefined, 14)
  k.prism(-6, 0, 14, 3 * T, 3.5 * T, tones[0], '#e3cc9c', 8)
  k.prism(-6, 0, 6.6, 3.5 * T, 3.8 * T, '#7c5432')
  k.prism(-6, 0, 6, 3.8 * T, 4.5 * T, tones[0], '#ead6aa', 8.5)
  k.box(12, 30, 3, 18, 0, 1.5 * T, { all: '#c9a76e', top: '#dfc48e' })
  k.box(15, 21, 6, 12, 1.5 * T, 1.95 * T, { all: '#e9c57e', top: '#f4dca0' })
  k.box(21, 27, 9, 15, 1.5 * T, 1.8 * T, { all: '#d9ad62', top: '#ecca88' })
}

/** 饮用水桶：一圈木板条、两道铁箍，桶口看得见水面，搭一把水瓢 */
const waterBarrel: Build = (k) => {
  k.footprint(22, 20, 2, 0)
  k.prism(0, 0, 18, 0, 4 * T, (side) => (side % 2 ? '#99693f' : '#855a35'))
  k.prism(0, 0, 18.8, 0.7 * T, 1 * T, IRON)
  k.prism(0, 0, 18.8, 3 * T, 3.3 * T, IRON)
  k.well(0, 0, 15, 3.85 * T, 4 * T, '#855a35')
  // 桶口一圈木沿
  for (let i = 0; i < 8; i++) {
    const a = ((i + 0.5) / 8) * Math.PI * 2,
      b = ((i + 1.5) / 8) * Math.PI * 2
    k.panel(
      k.top,
      [Math.cos(a) * 15, 4 * T, Math.sin(a) * 15],
      [Math.cos(b) * 15 - Math.cos(a) * 15, 0, Math.sin(b) * 15 - Math.sin(a) * 15],
      [Math.cos(a) * 3, 0, Math.sin(a) * 3],
      [0, 1, 0],
      1,
      1,
      '#b98a5c',
      0.1
    )
  }
  k.prism(0, 0, 15, 3.8 * T, 3.85 * T, '#4f9fd0', '#62b2e0')
  k.box(-7, -1, -7, -4, 3.85 * T, 3.87 * T, { top: '#c8e8f8' })
  k.box(5, 11, -3, 3, 4 * T, 4.5 * T, { all: '#cdd0d7' })
  k.box(11, 24, -1.5, 1.5, 4.3 * T, 4.5 * T, { all: WOOD.light })
}

/** 一片像素画（吉他这种靠轮廓认的东西）：rows 从上到下，一个字一格，'.' 空着；格子是正方的，正反两面都画。
 *  (x, z) 是底边中点，y 是底边的高度 */
function cutout(
  k: Kit,
  x: number,
  z: number,
  y: number,
  rows: string[],
  palette: Record<string, string>
) {
  const nu = rows[0].length,
    nv = rows.length
  const w = nu * P,
    h = nv * P
  const paint = (flip: boolean) => (u: number, v: number) => {
    const ch = rows[v][flip ? nu - 1 - u : u]
    return ch === '.' ? null : palette[ch]
  }
  k.panel(k.side, [x - w / 2, y + h, z + 1], [w, 0, 0], [0, -h, 0], [0, 0, 1], nu, nv, paint(false))
  k.panel(
    k.side,
    [x + w / 2, y + h, z - 1],
    [-w, 0, 0],
    [0, -h, 0],
    [0, 0, -1],
    nu,
    nv,
    paint(true),
    -0.2
  )
}

/** 公园长椅：铁架子，木板条的座面和两道靠背；人坐在座板上。室外的座位都是它 */
const bench: Build = (k, seed) => {
  k.footprint(30, 12)
  k.use = { at: [0, 5], lift: 2.5 * T }
  const wood = ['#b98858', '#a8774c', '#c49464'][Math.floor(hash(seed, 1, 3) * 3)]
  const pale = mixHex(wood, '#fff6e6', 0.25),
    dark = mixHex(wood, '#2a2230', 0.25)
  for (const x of [-30, 24]) {
    k.box(x, x + 6, 6, 9, 0, 3.4 * T, { all: IRON })
    k.box(x, x + 6, -12, -9, 0, 5.4 * T, { all: IRON })
    k.box(x, x + 6, -12, 10, 3.4 * T, 3.8 * T, { all: IRON, top: '#5f5e69' })
  }
  k.box(-27, 27, -9, 9, 2.1 * T, 2.5 * T, {
    all: wood,
    top: (u, v) => (v === 1 ? dark : pale),
    south: pale,
  })
  for (const y of [3 * T, 4.4 * T])
    k.box(-27, 27, -12, -9, y, y + 0.8 * T, { all: wood, top: pale })
}

const PAPERS: Record<string, string> = {
  f: WOOD.light,
  c: '#c9a36a',
  w: '#f6f1e7',
  y: '#f4dc8a',
  p: '#f2b6c0',
  b: '#a9cfe6',
  g: '#bfe0b0',
}
/** 公告栏：一长块软木板钉满了纸，顶上一道小屋檐，檐下三盏灯，两头各一只花箱。
 *  板子往落点的西边伸（东边紧挨着张贴处），比人高，看公告的人站在跟前也露得出上半截 */
const noticeBoard: Build = (k) => {
  k.footprint(69, 15, -30, 0)
  k.use = { at: [-30, 34] }
  for (const x of [-96, -33, 30]) k.box(x, x + 6, -3, 3, 0, 12.2 * T, { all: WOOD.dark })
  k.box(-90, 30, -2, 2, 6 * T, 6.5 * T, { all: WOOD.dark })
  const rows = [
    'ffffffffffffffffffff',
    'fwwcyycppcwwwcbbcggf',
    'fwwcyycwwcwwwcbbcwwf',
    'fcccggcwwccyycccccwf',
    'ffffffffffffffffffff',
  ]
  k.box(-90, 30, -2, 2, 6.5 * T, 11.5 * T, {
    all: WOOD.mid,
    south: (u, v) => PAPERS[rows[v]?.[u] ?? 'f'],
    north: WOOD.dark,
  })
  // 图钉
  for (const x of [-78, -60, -42, -21, 0, 18])
    k.box(x - 1.5, x + 1.5, 2, 3, 10.4 * T - 3, 10.4 * T, { all: '#c8323e' })
  // 小屋檐：一层瓦，压一道脊
  k.box(-102, 42, -13, 14, 11.6 * T, 12.1 * T, {
    all: '#7a4a3c',
    top: (u) => (u % 2 ? '#8a5646' : '#7a4a3c'),
    south: (u) => (u % 2 ? '#8a5646' : '#6a3e32'),
  })
  k.box(-102, 42, -5, 5, 12.1 * T, 12.7 * T, { all: '#9a6450', top: '#b07a62' })
  for (const x of [-72, -30, 12]) k.glow(x - 3, x + 3, 9, 11, 11.15 * T, 11.55 * T, WARM)
  k.lamp([-30, 9 * T, 20], LAMP, 150, 76, 0.9)
  // 花箱
  for (const x of [-99, 15]) {
    k.box(x, x + 24, 3, 15, 0, 1.2 * T, { all: '#bcb3a2', top: '#6b5a48', south: '#cfc6b5' })
    k.box(x + 2, x + 22, 5, 13, 1.2 * T, 2 * T, {
      all: '#5a8a4a',
      south: (u) => ['#e8687a', '#5a8a4a', '#f2c64e', '#77a65a'][u % 4],
      top: (u, v) => ['#f08c9a', '#77a65a', '#f6d776', '#5a8a4a'][(u + v) % 4],
    })
  }
}

/** 张贴处：一张小桌，上面浆糊桶和刷子、几卷海报、一沓传单 */
const pasteTable: Build = (k) => {
  k.footprint(21, 14)
  k.use = { at: [0, 30] }
  for (const x of [-18, 12])
    for (const z of [-12, 6]) k.box(x, x + 6, z, z + 6, 0, 2.8 * T, { all: WOOD.dark, top: false })
  k.box(-21, 21, -14, 14, 2.8 * T, 3.3 * T, {
    all: WOOD.light,
    top: (u) => (u % 3 === 2 ? WOOD.mid : WOOD.pale),
  })
  const y = 3.3 * T
  k.prism(-11, -4, 6.5, y, y + 1.2 * T, '#aeb4bd', '#f3ead2')
  k.box(-14, -8, -6, 9, y + 1.2 * T, y + 1.45 * T, { all: WOOD.mid })
  k.box(2, 18, -11, -6, y, y + 0.55 * T, { all: WHITE, east: '#e25a70', west: '#e25a70' })
  k.box(4, 20, -5, 0, y, y + 0.55 * T, { all: '#a9cfe6', east: '#3f86c0', west: '#3f86c0' })
  k.box(3, 19, -8, -3, y + 0.55 * T, y + 1.1 * T, {
    all: '#f4dc8a',
    east: '#d9a441',
    west: '#d9a441',
  })
  k.box(-3, 9, 4, 12, y, y + 0.3 * T, {
    all: CREAM,
    top: (u, v) => (v === 0 ? '#d07f52' : WHITE),
  })
}

const MAGS = ['#d9534a', '#3f86c0', '#e8b53c', '#4fa08a', '#b07cd0']
const NEWS = { paper: '#ece7d9', edge: '#cfc8b6', ink: '#5a554d', twine: '#9a6a3a' }
const newsLayers = (u: number, v: number) => (v % 2 ? NEWS.edge : NEWS.paper)
/** 报刊亭：青绿的柜身，台面上三摞报纸，背后一架杂志，红白条的雨棚，檐下一条灯。卖报的人站在亭子西边 */
const newsstand: Build = (k) => {
  k.footprint(36, 18)
  k.use = { at: [-54, 12] }
  const teal = { frame: '#245a56', core: '#2f7f78' }
  k.box(-30, 30, -15, 12, 0, 4 * T, {
    all: teal.core,
    south: (u, v, nu, nv) =>
      v === nv - 1 ? '#1c4744' : v === 0 || u % 5 === 0 || u % 5 === 4 ? teal.frame : teal.core,
    top: false,
  })
  k.box(-33, 33, -16, 15, 4 * T, 4.5 * T, { all: WOOD.light, top: WOOD.pale })
  const y = 4.5 * T
  const stack = (x: number, h: number) =>
    k.box(x, x + 12, 0, 12, y, y + h, {
      all: NEWS.paper,
      south: newsLayers,
      east: newsLayers,
      west: newsLayers,
      top: (u, v) => (v === 0 ? NEWS.ink : NEWS.paper),
    })
  stack(-27, 1.2 * T)
  stack(-12, 0.8 * T)
  stack(6, 1.6 * T)
  k.prism(25, 6, 3.6, y, y + 0.6 * T, BRASS, '#f3cf7a')
  // 背板上的杂志架：三排封面，排与排之间一道搁板
  k.box(-30, 30, -15, -11, y, 10.5 * T, {
    all: teal.frame,
    south: (u, v, nu) =>
      u === 0 || u === nu - 1 || v % 2 ? teal.frame : MAGS[(((u - 1) >> 1) + v) % MAGS.length],
  })
  for (const x of [-30, 27]) k.box(x, x + 3, 9, 12, y, 10.5 * T, { all: teal.frame })
  // 雨棚和垂下来的一道边
  const stripe = (u: number) => (u % 2 ? '#d9534a' : CREAM)
  k.box(-36, 36, -18, 14, 10.5 * T, 11 * T, { all: '#c2473d', top: stripe, south: stripe })
  k.box(-36, 36, 13, 14, 9.7 * T, 10.5 * T, {
    south: (u) => (u % 2 ? '#c2473d' : '#e6dac0'),
    north: false,
    top: false,
    east: '#c2473d',
    west: '#c2473d',
  })
  // 招牌：红底一行白字
  k.box(-21, 21, -6, -2, 11 * T, 13 * T, {
    all: '#b9443a',
    south: (u, v, nu) => (v === 0 && u > 0 && u < nu - 1 && u !== 3 ? CREAM : '#b9443a'),
    top: '#d9534a',
  })
  k.glow(-24, 24, 9.5, 10.5, 10.1 * T, 10.4 * T, WARM)
  k.lamp([0, 7 * T, 22], LAMP, 140, 70, 0.9)
}

/** 报纸整理点：垫板上几捆扎好的报纸，地上还有一捆，旁边靠着一只帆布挎包 */
const paperBundles: Build = (k) => {
  k.footprint(33, 18)
  k.use = { at: [0, 34] }
  k.box(-24, 24, -15, 12, 0, 0.6 * T, {
    all: WOOD.mid,
    top: (u) => (u % 3 === 2 ? WOOD.dark : WOOD.light),
  })
  const bundle = (x: number, z: number, y: number, h: number) =>
    k.box(x, x + 18, z, z + 18, y, y + h, {
      all: NEWS.paper,
      south: newsLayers,
      east: newsLayers,
      west: newsLayers,
      top: (u, v) => (u === 1 || v === 1 ? NEWS.twine : v === 0 ? NEWS.ink : NEWS.paper),
    })
  bundle(-21, -12, 0.6 * T, 2 * T)
  bundle(0, -12, 0.6 * T, 1.3 * T)
  bundle(1, -11, 1.9 * T, 0.9 * T)
  bundle(12, 0, 0, 1.2 * T)
  k.box(-33, -24, -6, 9, 0, 2.2 * T, {
    all: '#7d8c56',
    south: (u, v) => (v === 0 ? '#96a66a' : '#7d8c56'),
    top: '#96a66a',
  })
}

/** 排练点：谱架上摊着两页谱，旁边一只高脚凳，地上一只琴盒。练曲子的人站在谱架后面 */
const musicStand: Build = (k) => {
  k.footprint(36, 14, 0, 4)
  k.use = { at: [0, -18] }
  k.prism(0, 0, 9, 0, 0.25 * T, IRON, '#55545f')
  k.box(-1.5, 1.5, -1.5, 1.5, 0.25 * T, 5 * T, { all: IRON })
  k.box(-18, 18, -2, 2, 5 * T, 7 * T, {
    all: WOOD.dark,
    south: (u, v, nu) =>
      u === 0 || u === nu - 1 ? WOOD.dark : v === 0 ? WHITE : u % 2 ? '#d9d3c6' : WHITE,
  })
  k.box(-18, 18, 2, 4, 5 * T, 5.3 * T, { all: WOOD.dark, top: WOOD.mid })
  k.prism(27, 4, 2.5, 0, 2.4 * T, WOOD.dark)
  k.prism(27, 4, 9, 2.4 * T, 2.8 * T, WOOD.light, WOOD.pale)
  k.box(-36, -12, 6, 16, 0, 0.9 * T, {
    all: '#5a2f2a',
    top: (u, v, nu) => (u === 0 || u === nu - 1 ? '#5a2f2a' : '#7a3f38'),
    south: (u, v, nu) => (u === 1 || u === nu - 2 ? BRASS : '#5a2f2a'),
  })
}

/** 演奏点：一方矮木台，台上高脚凳、靠着的吉他、小音箱，台前敞开的琴盒里有几枚硬币；
 *  两根高杆子拉一串小灯，入夜亮。演奏的人站在台上 */
const buskStage: Build = (k) => {
  k.footprint(54, 58, 0, 10)
  k.use = { at: [-9, 8], lift: 0.8 * T }
  const y = 0.8 * T
  k.prism(0, 0, 48, 0, y, (side) => (side % 2 ? WOOD.mid : WOOD.dark), WOOD.light)
  k.box(-30, 24, -12, 24, y, y + 0.9, {
    top: (u, v, nu, nv) => {
      const edge = Math.min(u, v, nu - 1 - u, nv - 1 - v)
      return edge === 0 ? '#8f4a4a' : edge === 1 ? CREAM : (u + v) % 2 ? '#a85a50' : '#c9805a'
    },
    south: '#8f4a4a',
    east: '#8f4a4a',
    west: '#8f4a4a',
    north: false,
  })
  k.prism(-12, -15, 2.5, y, y + 2.6 * T, IRON)
  k.prism(-12, -15, 8, y + 2.6 * T, y + 3 * T, '#5a2f2a', '#8f2f3a')
  // 吉他靠在小架子上
  k.prism(27, -10, 6, y, y + 0.2 * T, IRON, '#55545f')
  cutout(
    k,
    27,
    -10,
    y + 0.2 * T,
    [
      '.kkk.',
      '..n..',
      '..n..',
      '..n..',
      '..n..',
      '..n..',
      '.hww.',
      'hwwww',
      '.wow.',
      'wwwww',
      'wwbww',
      '.www.',
    ],
    { k: '#2a1c14', n: '#5a3a26', h: '#f0b860', w: '#d08a3c', o: '#3a2418', b: '#5a3a26' }
  )
  // 小音箱
  k.box(-39, -27, -24, -12, y, y + 1.8 * T, {
    all: '#2e2c34',
    south: (u, v) => (v === 0 ? '#55545f' : '#3d3b45'),
    top: '#45444e',
  })
  // 台前敞开的琴盒，里面几枚硬币
  k.box(-18, 18, 50, 68, 0, 0.6 * T, {
    all: '#3d2a24',
    top: (u, v, nu, nv) =>
      u === 0 || v === 0 || u === nu - 1 || v === nv - 1 ? '#3d2a24' : u % 2 ? BRASS : '#8f2f3a',
  })
  // 两根杆子拉一串小灯，比人高
  for (const x of [-54, 51]) k.box(x, x + 3, -40, -37, 0, 15 * T, { all: IRON })
  const tints = [WARM, '#ffb0a0', WARM, '#bfe6c8', WARM, '#ffb0a0', WARM]
  tints.forEach((tint, i) => {
    const x = -39 + i * 13
    const h = (13.5 + ((i - 3) * (i - 3)) / 10) * T
    k.box(x - 7, x + 7, -39, -38, h, h + 1, { all: IRON })
    k.glow(x - 2.5, x + 2.5, -41, -36, h - 0.5 * T, h, tint)
  })
  k.lamp([0, 6 * T, -8], LAMP, 170, 80, 0.9)
}

/** 陈设：一张小圆桌，南北各一把椅子 */
const tableSet: Build = (k) => {
  k.footprint(24, 60)
  woodChair(k, 0, -45, -1)
  tableware(k, 0, 0, roundTable(k, 0, 0, 24))
  woodChair(k, 0, 45, 1)
}

/** 陈设：落地的大盆栽 */
const tallPlant: Build = (k) => {
  k.footprint(15, 15)
  k.prism(0, 0, 11, 0, 2 * T, '#bb6a44', '#6b4530', 13)
  k.box(-1.5, 1.5, -1.5, 1.5, 2 * T, 5 * T, { all: '#6b4530' })
  const leaf = (u: number, v: number) => ((u + v) % 2 ? '#3f7f49' : '#5fa55a')
  const lit = (u: number, v: number) => ((u + v) % 2 ? '#6db463' : '#8fcf7a')
  k.box(-15, 15, -12, 12, 4 * T, 6.5 * T, {
    all: '#3f7f49',
    south: leaf,
    east: leaf,
    west: leaf,
    top: lit,
  })
  k.box(-9, 9, -9, 9, 6.5 * T, 8 * T, {
    all: '#3f7f49',
    south: leaf,
    east: leaf,
    west: leaf,
    top: lit,
  })
  k.box(-21, -15, -6, 6, 4.5 * T, 5.5 * T, { all: '#5fa55a', top: '#8fcf7a' })
  k.box(15, 21, -6, 6, 5 * T, 6 * T, { all: '#3f7f49', top: '#6db463' })
}

/** 陈设：一块地毯，四周一圈花边；贴着地，不占地方 */
const rug: Build = (k) => {
  k.box(-60, 60, -42, 42, 0.5, 1.2, {
    top: (u, v, nu, nv) => {
      const edge = Math.min(u, v, nu - 1 - u, nv - 1 - v)
      if (edge === 0 || edge === 2) return CREAM
      if (edge === 1) return '#8f4a4a'
      return (u + v) % 4 === 0 ? '#c9805a' : '#a85a50'
    },
    south: '#8f4a4a',
    east: '#8f4a4a',
    west: '#8f4a4a',
    north: false,
  })
  k.tall = 0
}

const BUILDS: Record<string, Build> = {
  'core:bed': bed,
  'core:rations': rationSack,
  'core:drinking_water': waterBarrel,
  'core:coffee_machine': coffeeMachine,
  'core:tea-table': teaTable,
  'core:prop_1f268c17ba': backCounter,
  'core:prop_91ab2f9d1f': orderCounter,
  'core:prop_d8ed6d0f46': pastryCase,
  'core:prop_fb48cd2aaf': cafeChair,
  'core:bulletin_board': noticeBoard,
  'core:prop_f813ca3705': pasteTable,
  'core:prop_6d08f5c84a': newsstand,
  'core:prop_89517accaa': paperBundles,
  'core:prop_cc9e724d25': musicStand,
  'core:prop_a2ab77765f': buskStage,
}

const DECOR: Record<DecorKind, Build> = {
  'table-set': tableSet,
  plant: tallPlant,
  rug,
}

/**
 * 这件道具的搭法；没有就返回 undefined，照旧立牌。reference 是定义编号（带不带版本都行），
 * indoor 是它在不在屋里：座位这个定义屋里的是扶手椅，室外的（喷泉边、公园、看台、亭子里）是长椅。
 */
export function buildOf(reference: string | undefined, indoor: boolean): Build | undefined {
  const id = reference?.split('@')[0]
  if (!id) return undefined
  if (id === 'core:seat') return indoor ? armchair : bench
  return BUILDS[id]
}

export const decorBuild = (kind: DecorKind): Build => DECOR[kind]
