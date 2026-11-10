import { hash } from '../pixel/noise'
import type { DecorKind } from './propArrange'
import { Kit, T } from './propKit'

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
}

const DECOR: Record<DecorKind, Build> = {
  'table-set': tableSet,
  plant: tallPlant,
  rug,
}

/**
 * 这件道具的搭法；没有就返回 undefined，照旧立牌。reference 是定义编号（带不带版本都行），
 * indoor 是它在不在屋里：座位这个定义在室外是长椅、喷泉石沿、看台，景物里已经画了，只有屋里的才是扶手椅。
 */
export function buildOf(reference: string | undefined, indoor: boolean): Build | undefined {
  const id = reference?.split('@')[0]
  if (!id) return undefined
  if (id === 'core:seat') return indoor ? armchair : undefined
  return BUILDS[id]
}

export const decorBuild = (kind: DecorKind): Build => DECOR[kind]
