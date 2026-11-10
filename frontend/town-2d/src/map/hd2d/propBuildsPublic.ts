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
  crate,
  cutout,
  flowerBucket,
  shelf,
  table,
  tableLamp,
  woodChair,
  type Build,
  type Tier,
} from './propParts'

// 公共建筑屋里的家具：图书馆、公共食堂、诊所、镇公所、杂货铺、工作坊、码头仓库。
// 零件见 propParts.ts，登记在 propBuilds.ts。

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

// ---- 镇公所 ----

const sheets = (u: number, v: number) => (v === 0 ? WHITE : (u + v) % 3 ? WHITE : '#b9b3a6')

/** 议事桌：长桌四把椅子，桌上两沓文书、墨水台和一面小旗。议事的人坐在北边的椅子上 */
const meetingTable: Build = (k) => {
  k.footprint(51, 62)
  k.use = { at: [-24, -34] }
  for (const x of [-24, 24]) {
    woodChair(k, x, -45, -1)
    woodChair(k, x, 45, 1)
  }
  const y = table(k, -45, 45, -21, 21)
  k.box(-36, -18, -8, 6, y, y + 0.3 * T, { all: WHITE, top: sheets })
  k.box(6, 24, -2, 12, y, y + 0.3 * T, { all: WHITE, top: sheets })
  k.prism(-4, 2, 4.5, y, y + 0.6 * T, '#2e2c34', BRASS)
  k.box(34, 36, -4, -2, y, y + 3.2 * T, { all: BRASS })
  k.box(36, 48, -4, -3, y + 2.2 * T, y + 3.2 * T, { all: '#c2473d' })
}

/** 办事柜台：深色柜身，台面上一沓表格、笔筒、按铃和一块号码牌 */
const serviceCounter: Build = (k) => {
  k.footprint(45, 18)
  const y = cabinet(
    k,
    42,
    15,
    { frame: '#4a3a2c', core: '#6b523c', slab: '#d9ccb0', edge: '#c4b596' },
    2
  )
  k.box(-32, -14, -6, 8, y, y + 0.45 * T, { all: WHITE, top: sheets })
  k.prism(-2, -2, 3.8, y, y + 0.9 * T, '#3f6f8f', '#2e2c34')
  k.prism(10, 5, 3.6, y, y + 0.5 * T, BRASS, '#f3cf7a')
  k.box(22, 36, -2, 1, y, y + 1.7 * T, {
    all: '#2f5c4a',
    south: (u, v) => (v === 0 ? CREAM : '#2f5c4a'),
  })
}

/** 表格架：带脚的架子，三层各色表格 */
const formRack: Build = (k) => {
  k.footprint(27, 10)
  for (const x of [-24, 18]) k.box(x, x + 6, -6, 6, 0, 1.2 * T, { all: WOOD.dark, top: false })
  const forms =
    (tint: string): Tier =>
    (u) =>
      u % 3 === 2 ? null : u % 2 ? tint : WHITE
  shelf(k, 0, 24, 8, 1.2 * T, [forms('#e3ddd0'), forms('#a9cfe6'), forms('#f4dc8a')], {
    frame: WOOD.mid,
    board: WOOD.light,
    back: WOOD.dark,
  })
}

/** 档案柜：靠墙两只铁皮柜，一格格抽屉贴着标签，柜顶几只档案盒 */
const fileCabinet: Build = (k) => {
  k.footprint(32, 12)
  k.wall = true
  const metal = '#7d8c7a',
    dark = '#5c6a5a'
  k.box(-30, 30, -10, 10, 0, 7 * T, {
    all: metal,
    south: (u, v) =>
      u % 5 === 0 || u % 5 === 4 ? dark : v % 2 ? dark : u % 5 === 2 ? WHITE : metal,
    top: '#93a290',
  })
  k.box(-24, -10, -6, 6, 7 * T, 8.1 * T, {
    all: '#b98a5c',
    south: (u, v) => (v === 0 ? WHITE : '#b98a5c'),
  })
  k.box(-6, 8, -6, 6, 7 * T, 7.8 * T, {
    all: '#3f6f8f',
    south: (u, v) => (v === 0 ? WHITE : '#3f6f8f'),
  })
  k.box(12, 26, -6, 6, 7 * T, 8.4 * T, { all: '#8a6a4a' })
}

/** 职员的办公桌：靠墙，桌上打字机、文件筐、台灯；桌前一把椅子，办公的人坐在那儿 */
const clerkDesk: Build = (k) => {
  k.footprint(36, 34, 0, 17)
  k.wall = true
  k.use = { at: [0, 30] }
  woodChair(k, 0, 36, 1)
  const y = table(k, -30, 30, -15, 15)
  k.box(-12, 8, -8, 4, y, y + 0.9 * T, {
    all: '#3d3b45',
    top: (u, v) => (v === 0 ? '#2e2c34' : '#55545f'),
  })
  k.box(-8, 4, -9, -7, y + 0.9 * T, y + 1.9 * T, { all: WHITE })
  k.box(-28, -16, -6, 8, y, y + 0.5 * T, { all: WOOD.mid, top: sheets })
  tableLamp(k, 22, -6, y, 115)
}

// ---- 杂货铺 ----

const ice = (u: number, v: number) =>
  (u + v * 2) % 3 === 0 ? '#7fa6bd' : (u + v) % 2 ? '#e6f4f9' : '#cfe6ef'

/** 铺着条纹布的货摊：返回摊面的高度 */
function stallTable(k: Kit, w: number, a: string, b: string) {
  k.box(-w, w, -15, 15, 0, 3 * T, {
    all: a,
    south: (u, v) => (v === 0 ? b : u % 2 ? a : b),
    east: (u) => (u % 2 ? a : b),
    west: (u) => (u % 2 ? a : b),
    top: false,
  })
  k.box(-w - 2, w + 2, -16, 17, 3 * T, 3.4 * T, { all: WOOD.light, top: WOOD.pale })
  return 3.4 * T
}

/** 鱼货摊：蓝白条的摊子，一盘碎冰上码着鱼，旁边一台秤和一块价牌 */
const fishStall: Build = (k) => {
  k.footprint(41, 18)
  const y = stallTable(k, 39, '#3f86c0', CREAM)
  k.box(-33, 15, -11, 9, y, y + 0.6 * T, {
    all: '#aeb4bd',
    top: (u, v, nu, nv) =>
      u === 0 || v === 0 || u === nu - 1 || v === nv - 1 ? '#cdd0d7' : ice(u, v),
  })
  k.box(21, 35, -8, 4, y, y + 0.5 * T, { all: '#55565e' })
  k.prism(28, -2, 6, y + 0.5 * T, y + 0.7 * T, BRASS, '#f3cf7a')
  k.box(-12, 0, 11, 13, y, y + 1.2 * T, {
    all: CREAM,
    south: (u, v) => (v === 0 ? '#3f86c0' : CREAM),
  })
}

/** 屋里的花摊：后面一层木台上三盆花，前面两只花桶 */
const flowerStand: Build = (k, seed) => {
  k.footprint(38, 18)
  k.box(-36, 36, -16, -2, 0, 2.2 * T, {
    all: WOOD.mid,
    south: (u, v, nu, nv) => (v === nv - 1 ? WOOD.line : u % 4 === 3 ? WOOD.dark : WOOD.mid),
    top: WOOD.pale,
  })
  const blooms = [
    ['#e8687a', '#f6a3b0'],
    ['#f2c64e', '#f8dc7c'],
    ['#b07cd0', '#d6b0e6'],
    ['#ef8c4a', '#f6f1e7'],
  ]
  for (let i = 0; i < 3; i++) {
    const x = -24 + i * 24
    const [c, lit] = blooms[(i + (seed % 4)) % blooms.length]
    k.box(x - 6, x + 6, -15, -3, 2.2 * T, 3.1 * T, { all: '#bb6a44', top: '#8a4a30' })
    k.box(x - 9, x + 9, -18, 0, 3.1 * T, 4.4 * T, {
      all: '#4f8a4c',
      south: (u, v) => (v === 0 ? c : (u + v) % 2 ? '#4f8a4c' : '#6fa85e'),
      top: (u, v) => ((u + v) % 2 ? c : lit),
    })
  }
  flowerBucket(k, -20, 9, [blooms[seed % 4][0], '#f6f1e7', blooms[(seed + 1) % 4][0]])
  flowerBucket(k, 14, 9, [blooms[(seed + 2) % 4][0], blooms[(seed + 3) % 4][1], '#f6f1e7'])
}

const PRODUCE = [
  ['#c8323e', '#e25a50'],
  ['#ef8c4a', '#f6b060'],
  ['#5a8a4a', '#8cc474'],
  ['#e8b53c', '#f6d776'],
]
/** 杂货摊：红白条的摊子，三箱果蔬，几只罐子，摊边靠一袋粮 */
const groceryStall: Build = (k, seed) => {
  k.footprint(41, 18)
  const y = stallTable(k, 39, '#c2473d', CREAM)
  for (let i = 0; i < 3; i++) {
    const [c, lit] = PRODUCE[(i + (seed % 4)) % PRODUCE.length]
    crate(k, -36 + i * 21, -11, 18, 18, y, 0.9 * T, (u, v, nu, nv) =>
      u === 0 || v === 0 || u === nu - 1 || v === nv - 1 ? WOOD.light : (u + v) % 2 ? c : lit
    )
  }
  k.box(27, 33, -9, -3, y, y + 1.4 * T, { all: '#bfe0dc', top: BRASS })
  k.box(29, 35, 0, 6, y, y + 1.1 * T, { all: '#e2b05a', top: BRASS })
  k.prism(-46, 8, 9, 0, 2.2 * T, (side, v) => (v ? '#b18d57' : '#d6b47a'), '#e3cc9c', 7)
}

// ---- 工作坊 ----

const STEEL = '#aeb4bd'
/** 装配用的锯架台：两只木马架一块长板，板上一只做了一半的凳子和一把手锯 */
const sawhorse: Build = (k) => {
  k.footprint(39, 12)
  for (const x of [-30, 24]) {
    for (const z of [-10, 6]) k.box(x, x + 6, z, z + 4, 0, 3 * T, { all: WOOD.dark, top: false })
    k.box(x - 1, x + 7, -10, 10, 2.6 * T, 3 * T, { all: WOOD.mid })
  }
  k.box(-36, 36, -9, 9, 3 * T, 3.4 * T, {
    all: WOOD.light,
    top: (u, v) => (v === 1 ? WOOD.pale : '#e6c99a'),
  })
  const y = 3.4 * T
  for (const [x, z] of [
    [-27, -6],
    [-15, -6],
    [-27, 3],
  ])
    k.box(x, x + 3, z, z + 3, y, y + 1.4 * T, { all: WOOD.mid })
  k.box(-28, -11, -7, 7, y + 1.4 * T, y + 1.75 * T, { all: WOOD.pale })
  k.box(6, 30, -2, 3, y, y + 0.15 * T, { all: STEEL, top: '#cdd0d7' })
  k.box(30, 36, -3, 4, y, y + 0.35 * T, { all: WOOD.dark })
}

/** 打磨机：靠墙的铁座上一台蓝色电机，一只砂轮，迸着几点火星（一直亮） */
const grinder: Build = (k) => {
  k.footprint(15, 12)
  k.wall = true
  k.box(-10, 10, -10, 10, 0, 3 * T, {
    all: '#55545f',
    south: (u, v) => (v === 0 ? '#6b6a74' : '#45444e'),
    top: false,
  })
  k.box(-13, 13, -9, 7, 3 * T, 4.6 * T, {
    all: '#3f6f8f',
    top: '#5a8fb0',
    south: (u, v) => (v === 0 ? '#5a8fb0' : '#3f6f8f'),
  })
  cutout(k, 0, 9, 3.2 * T, ['.gg.', 'gdgg', 'ggdg', '.gg.'], { g: '#9a9ea8', d: '#6d7078' })
  k.glow(11, 13, 10, 11, 4 * T, 4.2 * T, '#ffcf5e', true)
  k.glow(14, 15.5, 11, 12, 3.6 * T, 3.75 * T, '#ffb347', true)
  k.lamp([12, 4 * T, 14], '#ffb45e', 44, 26, 0.5)
}

const GOODS = ['#c2473d', '#3f86c0', '#e8b53c', '#b98a5c', '#f6f1e7', '#5a8a4a']
const goods =
  (row: number): Tier =>
  (u) =>
    hash(u, row, 13) < 0.3 ? null : GOODS[Math.floor(hash(u, row, 17) * GOODS.length)]

/** 成品架：靠墙三层，摆着做好的各色器物 */
const goodsShelf: Build = (k) => {
  k.footprint(32, 12)
  k.wall = true
  shelf(k, 0, 30, 10, 0, [goods(1), goods(2), goods(3)])
}

/** 主木工台：厚实的台子，台钳、刨子、一把锤子，台面上散着刨花，背后一块挂工具的板 */
const workbench: Build = (k) => {
  k.footprint(42, 19)
  for (const x of [-39, 30]) k.box(x, x + 9, -15, 15, 0, 3 * T, { all: WOOD.dark, top: false })
  k.box(-36, 36, -12, 12, 0.8 * T, 1.2 * T, { all: WOOD.mid })
  k.box(-42, 42, -17, 17, 3 * T, 3.8 * T, {
    all: WOOD.light,
    top: (u, v) => (hash(u, v, 3) < 0.18 ? '#f1dcb0' : u % 4 === 3 ? WOOD.light : WOOD.pale),
  })
  const y = 3.8 * T
  k.box(-42, -30, 9, 19, y - 1 * T, y + 0.5 * T, { all: '#55565e', top: '#74777f' })
  k.box(-12, 6, -4, 4, y, y + 0.6 * T, { all: WOOD.mid, top: WOOD.dark })
  k.box(14, 32, 2, 5, y, y + 0.3 * T, { all: WOOD.dark })
  k.box(28, 36, -1, 8, y, y + 0.5 * T, { all: '#55565e' })
  // 挂工具的板
  k.box(-39, 39, -19, -17, y, y + 3 * T, {
    all: '#8a6a4a',
    south: (u, v, nu) =>
      u === 0 || u === nu - 1
        ? WOOD.dark
        : (u * 3 + v) % 5 === 0
          ? STEEL
          : (u + v * 2) % 7 === 0
            ? WOOD.dark
            : '#8a6a4a',
  })
}

/** 木料架：靠墙的架子上码着木板（看得见一头头的截面），旁边靠着几根长料 */
const lumberRack: Build = (k) => {
  k.footprint(36, 12, 4, 0)
  k.wall = true
  const ends =
    (row: number): Tier =>
    (u) =>
      [WOOD.pale, WOOD.light, '#e6c99a', WOOD.mid][(u + row) % 4]
  shelf(k, -6, 24, 10, 0, [ends(0), ends(1), ends(2)], {
    frame: '#45444e',
    board: '#6b6a74',
    back: '#2e2c34',
  })
  for (const [x, h, c] of [
    [22, 9, WOOD.light],
    [28, 10, WOOD.pale],
    [34, 8.4, WOOD.mid],
  ] as [number, number, string][])
    k.box(x, x + 5, -9, -5, 0, h * T, { all: c })
}

/** 修理交接台：柜台上等着修的东西——一盏歪了罩的台灯、一只座钟、一只红工具箱 */
const repairDesk: Build = (k) => {
  k.footprint(36, 18)
  const y = cabinet(k, 33, 15, WALNUT, 2)
  k.prism(-22, -2, 4, y, y + 0.3 * T, BRASS, BRASS)
  k.box(-23, -21, -3, -1, y + 0.3 * T, y + 1.2 * T, { all: BRASS })
  k.prism(-19, -2, 7, y + 1.2 * T, y + 2.2 * T, '#d9ccb0', '#efe4cc', 4.5)
  k.box(-6, 6, -6, 0, y, y + 1.6 * T, {
    all: WOOD.dark,
    south: (u, v) => (v === 0 ? CREAM : WOOD.dark),
    top: WOOD.mid,
  })
  k.box(14, 30, -7, 3, y, y + 1 * T, { all: '#c2473d', top: '#d9534a' })
  k.box(19, 25, -3, -1, y + 1 * T, y + 1.4 * T, { all: '#3d3b45' })
}

// ---- 码头仓库 ----

/** 手推车：两只大轮子的平板车，上面摞着三只木箱，北头一副铁把手 */
const handCart: Build = (k) => {
  k.footprint(30, 18)
  for (const x of [-30, 24]) k.box(x, x + 6, -6, 8, 0, 1.6 * T, { all: '#3d3b45', top: '#55545f' })
  k.box(-24, 24, -15, 15, 1 * T, 1.4 * T, {
    all: WOOD.mid,
    top: (u) => (u % 3 === 2 ? WOOD.dark : WOOD.light),
  })
  crate(k, -21, -12, 24, 24, 1.4 * T, 2 * T)
  crate(k, 4, -9, 17, 18, 1.4 * T, 1.5 * T)
  crate(k, -17, -9, 16, 16, 3.4 * T, 1.3 * T)
  for (const x of [-24, 21]) k.box(x, x + 3, -18, -15, 1.4 * T, 5.4 * T, { all: IRON })
  k.box(-24, 24, -18, -15, 5.1 * T, 5.4 * T, { all: IRON })
}

/** 渔网堆：堆成一座小丘的渔网，上面压着三只浮漂，旁边一盘缆绳 */
const netPile: Build = (k) => {
  k.footprint(32, 24)
  const net = (side: number, v: number) => ((side + v) % 2 ? '#c9c3a8' : '#a9a48a')
  k.prism(0, 0, 26, 0, 1.4 * T, net, '#b9b398', 19)
  k.prism(-3, -2, 17, 1.4 * T, 2.5 * T, net, '#d6d0b6', 9)
  for (const [x, z, c] of [
    [10, 12, '#ef6a3a'],
    [-14, 10, '#f6f1e7'],
    [2, -4, '#ef6a3a'],
  ] as [number, number, string][])
    k.prism(
      x,
      z,
      5,
      x === 2 ? 2.5 * T : 1.4 * T,
      (x === 2 ? 2.5 : 1.4) * T + 0.8 * T,
      c,
      '#f6f1e7',
      3.5
    )
  k.prism(26, 14, 8, 0, 0.5 * T, '#c9a66b', '#b08c56')
  k.prism(26, 14, 4.5, 0.5 * T, 0.9 * T, '#c9a66b', '#d8bb85')
}

/** 入库木箱：两只并排、上面再摞一只，箱板上刷着记号 */
const crateStack: Build = (k) => {
  k.footprint(30, 15)
  const lid = (u: number, v: number, nu: number, nv: number) =>
    u === 0 || v === 0 || u === nu - 1 || v === nv - 1
      ? WOOD.dark
      : u === v
        ? WOOD.dark
        : WOOD.light
  crate(k, -28, -13, 27, 26, 0, 2.2 * T, lid)
  crate(k, 1, -11, 26, 24, 0, 2 * T, lid)
  crate(k, -16, -10, 24, 21, 2.2 * T, 1.8 * T, lid)
}

/** 货单桌：一张高脚小桌，夹着货单的写字板、一枚印章、一盏台灯 */
const tallyDesk: Build = (k) => {
  k.footprint(22, 14)
  const y = table(k, -18, 18, -12, 12, 3.8 * T)
  k.box(-12, 4, -7, 7, y, y + 0.3 * T, {
    all: '#8a6a4a',
    top: (u, v) => (v === 0 ? '#3d3b45' : (u + v) % 3 ? WHITE : '#b9b3a6'),
  })
  k.box(8, 12, 2, 6, y, y + 0.8 * T, { all: WOOD.dark, top: '#8f2f3a' })
  tableLamp(k, 12, -6, y, 105)
}

const STOCK = ['#b98a5c', '#d6b47a', '#855a35', '#7d8c7a', '#c9805a']
/** 仓库的货架：靠墙的铁架三层，箱子、麻袋、木桶 */
const storageRack: Build = (k) => {
  k.footprint(44, 13)
  k.wall = true
  const stock =
    (row: number): Tier =>
    (u) =>
      hash(u >> 1, row, 23) < 0.2 ? null : STOCK[Math.floor(hash(u >> 1, row, 29) * STOCK.length)]
  shelf(k, 0, 42, 11, 0, [stock(1), stock(2), stock(3)], {
    frame: '#45444e',
    board: '#6b6a74',
    back: '#2e2c34',
  })
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
  'core:prop_c2a3f71093': meetingTable,
  'core:prop_9637021f77': serviceCounter,
  'core:prop_8027663c65': formRack,
  'core:prop_87ac10e608': fileCabinet,
  'core:prop_4412190019': clerkDesk,
  'core:prop_13b51fbe0f': fishStall,
  'core:prop_3b8425f629': flowerStand,
  'core:prop_ace65ef490': flowerStand,
  'core:prop_27dee840cf': groceryStall,
  'core:prop_c75138b13a': groceryStall,
  'core:prop_c332b3d588': sawhorse,
  'core:prop_85488fb21a': grinder,
  'core:prop_3aa5440c88': goodsShelf,
  'core:workbench': workbench,
  'core:prop_35e8c138dd': lumberRack,
  'core:prop_a5084de387': repairDesk,
  'core:prop_6d11edf922': handCart,
  'core:prop_8848b79337': netPile,
  'core:prop_614f630b11': crateStack,
  'core:prop_c1c10c842b': tallyDesk,
  'core:prop_055fa1337d': storageRack,
}
