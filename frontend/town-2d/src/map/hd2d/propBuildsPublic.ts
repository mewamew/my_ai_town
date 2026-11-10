import { hash } from '../pixel/noise'
import { T, type Kit } from './propKit'
import {
  BRASS,
  CREAM,
  IRON,
  WALNUT,
  WHITE,
  WOOD,
  cabinet,
  shelf,
  table,
  tableLamp,
  woodChair,
  type Build,
  type Tier,
} from './propParts'

// 公共建筑屋里的家具：图书馆、公共食堂、诊所。零件见 propParts.ts，登记在 propBuilds.ts。

const SPINES = ['#b9443a', '#3f6f8f', '#5a8a4a', '#d9a441', '#7a4a8a', '#c9805a', '#2f5c4a']
/** 一层书：一格一本，书脊颜色按位置定；gaps 是空着的比例 */
const books =
  (row: number, gaps = 0): Tier =>
  (u) =>
    hash(u, row, 5) < gaps ? null : SPINES[Math.floor(hash(u, row, 21) * SPINES.length)]

/** 桌上一摞书，从 y 往上摞 n 本 */
function bookStack(k: Kit, x: number, z: number, y: number, n: number) {
  for (let i = 0; i < n; i++)
    k.box(x + (i % 2), x + 14 - (i % 2), z, z + 10, y + i * 0.45 * T, y + (i + 1) * 0.45 * T, {
      all: SPINES[(i * 3 + 1) % SPINES.length],
      top: i === n - 1 ? SPINES[(i * 3 + 1) % SPINES.length] : false,
    })
}

/** 一本摊开的书 */
function openBook(k: Kit, x: number, z: number, y: number) {
  k.box(x - 9, x + 9, z - 6, z + 6, y, y + 0.3 * T, {
    all: WHITE,
    top: (u, v, nu) => (u === Math.floor(nu / 2) ? '#b9b3a6' : v % 2 ? '#e3ddd0' : WHITE),
    south: '#8f2f3a',
  })
}

// ---- 图书馆 ----

/** 借还书柜台：一摞待还的书、印台和印章、一块蓝头的牌子、一盏台灯 */
const loanDesk: Build = (k) => {
  k.footprint(51, 18)
  const y = cabinet(k, 48, 15, WALNUT, 2)
  bookStack(k, -42, -8, y, 3)
  k.box(-14, -2, -5, 5, y, y + 0.3 * T, { all: '#3d2e24', top: '#8f2f3a' })
  k.box(-10, -6, -2, 2, y + 0.3 * T, y + 1.1 * T, { all: WOOD.dark, top: WOOD.light })
  k.box(6, 22, 6, 9, y, y + 1.5 * T, { all: CREAM, south: (u, v) => (v === 0 ? '#3f6f8f' : CREAM) })
  tableLamp(k, 34, -4, y, 115)
}

/** 柜台内侧：靠墙一架矮书柜，放着还回来的书，柜顶一只地球仪和一摞书 */
const loanShelf: Build = (k) => {
  k.footprint(50, 12)
  k.wall = true
  const y = shelf(k, 0, 48, 10, 0, [books(1, 0.25), books(2)])
  k.prism(-28, 0, 3, y, y + 0.5 * T, BRASS)
  k.prism(
    -28,
    0,
    7,
    y + 0.5 * T,
    y + 1.9 * T,
    (side) => (side % 3 ? '#4f86b0' : '#6fa85e'),
    '#7fb2c9',
    5
  )
  bookStack(k, 12, -6, y, 4)
}

/** 阅读桌：桌上一本摊开的书、一摞书、一盏台灯，北边一把椅子。看书的人坐在桌子后面 */
const readingDesk: Build = (k) => {
  k.footprint(36, 35, 0, -16)
  k.use = { at: [0, -26] }
  woodChair(k, 0, -36, -1)
  const y = table(k, -30, 30, -15, 15)
  openBook(k, -4, 2, y)
  bookStack(k, -28, -10, y, 2)
  tableLamp(k, 22, -6, y, 120)
}

/** 写作桌：一沓稿纸、墨水瓶和羽毛笔、一盏台灯，北边一把椅子 */
const writingDesk: Build = (k) => {
  k.footprint(36, 35, 0, -16)
  k.use = { at: [0, -26] }
  woodChair(k, 0, -36, -1)
  const y = table(k, -30, 30, -15, 15)
  k.box(-12, 6, -6, 8, y, y + 0.35 * T, {
    all: WHITE,
    top: (u, v) => (v === 0 ? WHITE : (u + v) % 3 ? WHITE : '#b9b3a6'),
  })
  k.prism(-22, -4, 3.6, y, y + 0.7 * T, '#2e2c34', '#3f6f8f')
  k.box(-23, -21, -5, -3, y + 0.7 * T, y + 2 * T, { all: WHITE })
  tableLamp(k, 22, -6, y, 120)
}

/** 还书车：带轮子的小车，两层书 */
const bookCart: Build = (k) => {
  k.footprint(26, 12)
  for (const x of [-21, 15])
    for (const z of [-9, 5]) k.box(x, x + 6, z, z + 4, 0, 0.8 * T, { all: IRON, top: false })
  shelf(k, 0, 21, 10, 0.8 * T, [books(7, 0.15), books(8, 0.4)])
  k.box(21, 25, -2, 2, 3 * T, 5.4 * T, { all: IRON })
}

/** 高书架：靠墙四层书，顶上一摞书 */
const tallShelf: Build = (k) => {
  k.footprint(44, 12)
  k.wall = true
  const y = shelf(k, 0, 42, 10, 0, [books(3), books(4, 0.1), books(5), books(6, 0.2)])
  bookStack(k, -30, -6, y, 3)
}

/** 书：一张矮展台，书一本本立着、封面朝外，最多摆七本。amount 是这一摞有几本；单独一本就是一只小台子 */
const bookDisplay: Build = (k, seed, amount = 1) => {
  const n = Math.max(1, Math.min(7, Math.round(amount)))
  const w = n * 7 + 5
  k.footprint(w, 9)
  k.use = { at: [0, 26] }
  k.box(-w, w, -8, 8, 0, 2.2 * T, {
    all: WOOD.mid,
    south: (u, v, nu, nv) =>
      v === nv - 1 ? WOOD.line : u === 0 || u === nu - 1 ? WOOD.dark : WOOD.mid,
    top: WOOD.pale,
  })
  for (let i = 0; i < n; i++) {
    const x = -n * 7 + i * 14 + 1
    const cover = SPINES[Math.floor(hash(seed, i, 31) * SPINES.length)]
    k.box(x, x + 12, -4, 0, 2.2 * T, 4.4 * T, {
      all: cover,
      south: (u, v) => (v === 0 && u === 1 ? CREAM : cover),
      top: WHITE,
    })
  }
}

// ---- 公共食堂 ----

const BOWL = '#f6f1e7'
/** 一只碗：里面的汤或饭给个颜色 */
function bowl(k: Kit, x: number, z: number, y: number, food: string) {
  k.prism(x, z, 5.5, y, y + 0.55 * T, BOWL, food, 6.5)
}

/** 长餐桌：两边各一条长凳，桌上几只碗、一篮面包、一只水壶。吃饭的人坐在北边那条凳上 */
const diningTable: Build = (k) => {
  k.footprint(45, 36)
  k.use = { at: [0, -27], lift: 2 * T }
  for (const z of [-33, 24]) {
    for (const x of [-36, 30])
      k.box(x, x + 6, z + 1, z + 8, 0, 1.6 * T, { all: WOOD.dark, top: false })
    k.box(-39, 39, z, z + 9, 1.6 * T, 2 * T, { all: WOOD.mid, top: WOOD.light })
  }
  const y = table(k, -39, 39, -15, 15)
  bowl(k, -27, -6, y, '#e2b05a')
  bowl(k, -9, 6, y, '#c9704e')
  bowl(k, 27, 5, y, '#e9e0c9')
  k.box(3, 21, -11, -1, y, y + 0.6 * T, {
    all: '#b98a5c',
    top: (u) => (u % 2 ? '#e2b05a' : '#c9904a'),
  })
  k.prism(-36, 6, 4.5, y, y + 1.4 * T, '#6fa9c7', '#9fc9df', 3.5)
}

const DISHES = ['#f6f1e7', '#a9cfe6', '#f6f1e7', '#e9e0c9']
/** 餐具架：靠墙三层，码着盘子和碗 */
const dishRack: Build = (k) => {
  k.footprint(26, 12)
  k.wall = true
  const dishes =
    (row: number): Tier =>
    (u) =>
      (u + row) % 3 === 2 ? null : DISHES[(u + row) % DISHES.length]
  shelf(k, 0, 24, 10, 0, [dishes(0), dishes(1), dishes(2)], {
    frame: WOOD.mid,
    board: WOOD.light,
    back: WOOD.dark,
  })
}

/** 面团操作台：撒了面粉的台面上两团面、一根擀面杖、一袋面粉 */
const doughTable: Build = (k) => {
  k.footprint(30, 17)
  const y = table(k, -27, 27, -15, 15, 3.6 * T, '#efe6d2')
  k.prism(-12, 0, 7, y, y + 0.7 * T, '#f3e6c4', '#fbf2d8', 5)
  k.prism(4, -6, 5.5, y, y + 0.6 * T, '#f3e6c4', '#fbf2d8', 4)
  k.box(-3, 17, 6, 9, y, y + 0.35 * T, { all: WOOD.light })
  k.box(16, 26, -10, 0, y, y + 1.6 * T, {
    all: '#e6dcc6',
    top: '#f6f1e7',
    south: (u, v) => (v === 0 ? '#c9805a' : '#e6dcc6'),
  })
}

/** 备餐柜：靠墙的矮柜，上面一口汤锅冒着热气、一盘面包 */
const pantry: Build = (k) => {
  k.footprint(27, 16)
  k.wall = true
  const y = cabinet(k, 24, 15, WALNUT, 1)
  k.prism(-8, -3, 9, y, y + 1.3 * T, '#55565e', '#d9a04e')
  k.box(-21, -17, -4, -2, y + 0.9 * T, y + 1.2 * T, { all: '#55565e' })
  k.box(6, 22, -8, 4, y, y + 0.3 * T, {
    all: WOOD.dark,
    top: (u) => (u % 2 ? '#d9a04e' : '#c98a3e'),
  })
  k.steam.push([-8, y + 1.8 * T, -3])
}

/** 递餐口：靠墙的台子，两只托盘上各一碗一碟，一只按铃 */
const servingHatch: Build = (k) => {
  k.footprint(27, 16)
  k.wall = true
  const y = cabinet(
    k,
    24,
    15,
    { frame: '#8a6a4a', core: '#b08a62', slab: CREAM, edge: '#dfd2b4' },
    1
  )
  for (const x of [-21, 3]) {
    k.box(x, x + 18, -8, 6, y, y + 0.25 * T, { all: WOOD.mid, top: WOOD.light })
    bowl(k, x + 6, -2, y + 0.25 * T, '#e2b05a')
    k.prism(x + 14, 2, 3.5, y + 0.25 * T, y + 0.4 * T, BOWL, '#6fae62')
  }
  k.prism(0, 9, 3, y, y + 0.5 * T, BRASS, '#f3cf7a')
}

/** 水槽：靠墙的白柜子，石台面里一池水，龙头，旁边一摞洗好的盘子 */
const sink: Build = (k) => {
  k.footprint(27, 16)
  k.wall = true
  const y = cabinet(
    k,
    24,
    15,
    { frame: '#bdb6a6', core: '#d9d3c6', slab: '#c9c4ba', edge: '#aaa59b' },
    2
  )
  k.box(-18, 6, -9, 9, y - 2, y + 0.1 * T, {
    top: (u, v, nu, nv) =>
      u === 0 || v === 0 || u === nu - 1 || v === nv - 1 ? '#8f8a80' : '#62b2e0',
  })
  k.box(-8, -4, -13, -10, y, y + 1.6 * T, { all: '#aeb4bd' })
  k.box(-8, -4, -13, -4, y + 1.6 * T, y + 1.9 * T, { all: '#aeb4bd', top: '#cdd0d7' })
  for (let i = 0; i < 3; i++)
    k.prism(16, -2, 6.5, y + i * 0.3 * T, y + (i + 1) * 0.3 * T, i % 2 ? '#a9cfe6' : BOWL, BOWL)
}

/** 灶台：靠墙的砖灶，炉膛里烧着火（一直亮），铁板上一口锅一只水壶冒着热气，一根烟管通上去 */
const stove: Build = (k) => {
  k.footprint(27, 16)
  k.wall = true
  const brick = (u: number, v: number) =>
    (u + (v % 2) * 2) % 4 === 0 ? '#8a4a3a' : v % 2 ? '#a85a44' : '#b9664e'
  k.box(-24, 24, -15, 15, 0, 4 * T, {
    all: '#a85a44',
    south: (u, v, nu, nv) => (v >= 2 && u >= 3 && u <= 4 && v < nv ? '#2a1c18' : brick(u, v)),
    east: brick,
    west: brick,
    top: false,
  })
  k.glow(-5, 5, 15, 15.8, 0.3 * T, 1.6 * T, '#ff9a3c', true)
  k.box(-26, 26, -16, 17, 4 * T, 4.4 * T, { all: '#3d3b45', top: '#55545f' })
  const y = 4.4 * T
  k.prism(-10, -2, 9, y, y + 1.4 * T, '#55565e', '#c9704e')
  k.prism(12, 2, 6, y, y + 1.1 * T, '#8f939c', '#aeb4bd', 4.5)
  k.box(15, 21, 1, 3, y + 0.5 * T, y + 0.8 * T, { all: '#8f939c' })
  k.box(-3, 3, -15, -11, y, 9 * T, { all: '#3d3b45' })
  k.steam.push([-10, y + 1.9 * T, -2], [12, y + 1.6 * T, 2])
  k.lamp([0, 1 * T, 22], '#ff9a4a', 90, 50, 0.8)
}

// ---- 诊所 ----

const MINT = '#7fb5ae'
/** 问诊桌（医生那一侧）：桌上病历夹、听诊器、一盏台灯，北边一把椅子。接诊的人坐在桌子后面 */
const doctorDesk: Build = (k) => {
  k.footprint(36, 35, 0, -16)
  k.use = { at: [0, -26] }
  woodChair(k, 0, -36, -1)
  const y = table(k, -30, 30, -15, 15, 3.3 * T, '#e9e4d6')
  k.box(-14, 2, -6, 8, y, y + 0.3 * T, {
    all: '#8a6a4a',
    top: (u, v) => (v === 0 ? '#aeb4bd' : WHITE),
  })
  k.box(-26, -18, 0, 3, y, y + 0.25 * T, { all: '#2e2c34' })
  k.prism(-22, 8, 3, y, y + 0.25 * T, '#aeb4bd', '#cdd0d7')
  tableLamp(k, 22, -6, y, 115)
}

/** 问诊桌（看诊那一侧）：一只圆凳，看诊的人坐在上面 */
const patientStool: Build = (k) => {
  k.footprint(12, 12)
  k.use = { at: [0, 2], lift: 2.6 * T }
  k.prism(0, 0, 8, 0, 0.3 * T, IRON, '#55545f')
  k.prism(0, 0, 2.5, 0.3 * T, 2.2 * T, IRON)
  k.prism(0, 0, 10, 2.2 * T, 2.6 * T, MINT, '#a6d3cc')
}

/** 检查床：铁架白床，头在西，枕头和叠好的薄毯；东头一道三折的布帘。接受检查的人躺在床上 */
const examBed: Build = (k) => {
  k.footprint(69, 27, 6, 0)
  k.wall = true
  k.use = { at: [2, 25], lift: 2.4 * T }
  for (const x of [-57, 51])
    for (const z of [-24, 18]) k.box(x, x + 6, z, z + 6, 0, 1.8 * T, { all: '#aeb4bd', top: false })
  k.box(-57, 57, -24, 24, 1.8 * T, 2.6 * T, {
    all: WHITE,
    south: (u, v) => (v ? '#aeb4bd' : WHITE),
  })
  k.box(-51, -33, -15, 15, 2.6 * T, 3.3 * T, { all: CREAM, top: '#fdf8ea' })
  k.box(27, 54, -21, 21, 2.6 * T, 3 * T, { all: MINT, top: (u) => (u % 2 ? '#a6d3cc' : MINT) })
  k.box(-60, -57, -24, 24, 0, 4.4 * T, { all: '#aeb4bd' })
  // 布帘：三折
  for (const [x, z] of [
    [63, -24],
    [66, -8],
    [63, 8],
  ])
    k.box(x, x + 3, z, z + 16, 0.4 * T, 7 * T, {
      all: MINT,
      east: (u, v) => (v === 0 ? WHITE : MINT),
      west: (u, v) => (v === 0 ? WHITE : MINT),
    })
}

const BOTTLES = ['#b9763a', '#4f86b0', '#5a8a4a', '#f6f1e7', '#c2473d']
/** 药柜：靠墙的白柜子，三层药瓶，顶上一个绿十字（入夜亮） */
const medicineCabinet: Build = (k) => {
  k.footprint(32, 12)
  k.wall = true
  const bottles =
    (row: number): Tier =>
    (u) =>
      (u + row) % 4 === 3 ? null : BOTTLES[(u * 2 + row) % BOTTLES.length]
  const y = shelf(k, 0, 30, 10, 0, [bottles(0), bottles(1), bottles(2), bottles(3)], {
    frame: '#e9e4d6',
    board: '#d2ccbd',
    back: '#b9c9c6',
  })
  k.glow(-3, 3, 4, 6, y, y + 1.5 * T, '#7fe0a8')
  k.glow(-8, 8, 4, 6, y + 0.5 * T, y + 1 * T, '#7fe0a8')
  k.lamp([0, 5 * T, 16], '#bff0d0', 70, 44, 0.5)
}

/** 救助药箱：小凳上一只白药箱，箱顶一个红十字，旁边一卷绷带 */
const firstAidKit: Build = (k) => {
  k.footprint(18, 12)
  const y = table(k, -15, 15, -9, 9, 2.4 * T, '#e9e4d6')
  k.box(-13, 5, -9, 9, y, y + 1.5 * T, {
    all: WHITE,
    south: (u, v) => (u === 1 && v === 0 ? '#c8323e' : v === 1 ? '#e3ddd0' : WHITE),
    top: (u, v) => (u === 1 || v === 1 ? '#c8323e' : WHITE),
  })
  k.prism(12, 2, 3, y, y + 0.6 * T, WHITE, '#e3ddd0')
}

/** 复苏石：石座上一块自己发光的青色石头，一直亮着 */
const revivalStone: Build = (k) => {
  k.footprint(14, 14)
  k.prism(0, 0, 12, 0, 0.5 * T, '#8f8a80', '#aaa59b')
  k.prism(0, 0, 9, 0.5 * T, 2 * T, '#aaa59b', '#c9c4ba', 7)
  k.shade(0, 0, 6.5, 2 * T, 3.2 * T, '#7fe8d8', 5, true)
  k.shade(0, 0, 5, 3.2 * T, 4.4 * T, '#b6f6ec', 1.5, true)
  k.lamp([0, 3 * T, 6], '#7fe8d8', 85, 60, 0.9)
}

/** 书的定义编号是 core:book-N，都用展台 */
export const bookBuild: Build = bookDisplay

export const PUBLIC_BUILDS: Record<string, Build> = {
  'core:prop_f3121b95b9': loanDesk,
  'core:prop_bbab22b9f4': loanShelf,
  'core:reading_desk': readingDesk,
  'core:prop_9041ded504': writingDesk,
  'core:prop_637a7dfbd1': bookCart,
  'core:prop_25a762372b': tallShelf,
  'core:dining_table': diningTable,
  'core:prop_4e2a97debc': dishRack,
  'core:prop_eb63f82215': doughTable,
  'core:prop_7055da94bc': pantry,
  'core:prop_2bdc99e6dc': servingHatch,
  'core:prop_10f9da8595': sink,
  'core:prop_c6e9a5d85f': stove,
  'core:prop_e5a0bf5f71': doctorDesk,
  'core:prop_f02ef5aaa6': patientStool,
  'core:prop_cb23035458': examBed,
  'core:medicine_cabinet': medicineCabinet,
  'core:medical_kit': firstAidKit,
  'core:revival_stone': revivalStone,
}
