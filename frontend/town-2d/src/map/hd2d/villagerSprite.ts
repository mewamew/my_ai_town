import type { AvatarLook } from 'town-shared/avatar/types'
import { decodeLookKey, type VillagerArt } from 'town-shared/portraits'
import type { VillagerLook } from 'town-shared/protocol'
import { hashString, mixHex } from '../pixel/noise'
import { AVATAR_COLORS, avatarLook, avatarLookKey } from './avatarLooks'
import { CLOTH_CREAM, CLOTH_WHITE } from '../palette'
import { PIXEL } from '../grid'
import { deepOf, refineVillager } from './villagerRefine'

// 像素村民：Q 版画法。
// 人物占 21×29 格：头 0～16 行，身子 17～25 行，腿 26～27 行是两个 2×2 的块（上一行裤子色，下一行鞋）。
// 一帧 25×34，人物放在 (2, 6)：头顶留 6 行给发髻、帽子和大葱头这种往上竖的头发，两边留给辫子。
// 朝向分下、右、上、左；场景里每人一块小画布，按此刻的姿势和表情现画（见 villagerRig.ts）。
// 描边 K 直接画在格子里，色块平涂。正面、背面只写左半边 11 列（第 10 列是中线）再镜像；
// 侧面按朝右整行写，朝左整张翻过来。

/** 人物在一帧里的位置：左边留 2 列给辫子，头顶留 6 行给发髻和帽子 */
export const OX = 2
export const OY = 6
export const FRAME_W = 25
export const FRAME_H = OY + 28
/** 一个人物像素约等于 2/3 个地图像素，人比门矮一点 */
export const VILLAGER_SCALE = 0.66
/** 站立的人从脚到头顶的高度（地图单位）：帧顶留给发髻和高发型的 OY 行不算 */
export const VILLAGER_HEIGHT = (FRAME_H - OY) * PIXEL * VILLAGER_SCALE
/** 头最宽，19 个人物像素，半宽（地图单位） */
export const VILLAGER_HALF = (19 / 2) * PIXEL * VILLAGER_SCALE
export const DIRECTIONS = ['down', 'right', 'up', 'left'] as const
export type Direction = (typeof DIRECTIONS)[number]

export type View = 'down' | 'up' | 'side'
type Rows = readonly string[]
type Patch = readonly (readonly [number, number, string])[]

const mirror = (half: Rows) => half.map((r) => r + [...r.slice(0, -1)].reverse().join(''))
const swap = (rows: Rows, at: number, ...next: string[]) => [
  ...rows.slice(0, at),
  ...next,
  ...rows.slice(at + next.length),
]
/** 小块字母格贴在 (x0, y0)，点是透明：发髻、辫子、呆毛这些加在头上的部件 */
const overlay = (x0: number, y0: number, rows: Rows): Patch =>
  rows.flatMap((row, j) =>
    [...row].flatMap((ch, i) => (ch === '.' ? [] : [[x0 + i, y0 + j, ch] as const]))
  )

// ---- 头：短发和齐耳短发是两套底稿，其余发型在它们上面改 ----

const SHORT_DOWN = mirror([
  '...........',
  '......KKKKK',
  '....KKhhhhh',
  '...KhhhhHHH',
  '..KhhhHHhhh',
  '..KhhHhhhhh',
  '.KhhhhLhhhL',
  '.Khhhhhhhhh',
  '.Khhhhhhhhh',
  '.Khhhhhhhhh',
  '.KhhhhKhKjs',
  '.KhhhhsKsss',
  '.KhhhhsKsss',
  '.KhhhKsesss',
  '..KhhKsssss',
  '...KKKjssss',
  '.....KKKKKK',
])
const SHORT_UP = mirror([
  '...........',
  '......KKKKK',
  '....KKhhhhh',
  '...KhhhhHHH',
  '..KhhhHHhhh',
  '..KhhHhhhhh',
  '.KhhhhLhhhL',
  '.Khhhhhhhhh',
  '.Khhhhhhhhh',
  '.Khhhhhhhhh',
  '.Khhhhhhhhh',
  '.Khhhhhhhhh',
  '.Khhhhhhhhh',
  '.Khhhhhhhhh',
  '..Khhhhhhhh',
  '...KKhhhhhh',
  '.....KKKsss',
])
/** 侧面和正面同一个圆头外形；只露一只眼，离脸的前边两格；下巴按正面的弧度回收 */
const SHORT_SIDE = [
  '.....................',
  '......KKKKKKKKK......',
  '....KKhhhhhhhhhKK....',
  '...KhhhhHHHHHhhhhK...',
  '..KhhhHHhhhhhhHhhhK..',
  '..KhhHhhhhhhhhhHhhK..',
  '.KhhhhhLhhhLhhhhhhhK.',
  '.KhhhhhhhhhhhhhhhhhK.',
  '.KhhhhhhhhhhhhhhhhhK.',
  '.KhhhhhhhhhhhhhhhhhK.',
  '.KhhhhhhhhhKKhKKKshK.',
  '.KhhhhhhhhhsssssKssK.',
  '.KhhhhhhhhhsssssKssK.',
  '.KhhhhhhhhhsssssessK.',
  '..KhhhhhhhhsssssssK..',
  '...KhhhhhhhsssssjK...',
  '.....KKKKKKKKKKKK....',
]
const BOB_DOWN = mirror([
  '......KKKKK',
  '....KKhhhhh',
  '...Khhhhhhh',
  '..KhhhhHHHH',
  '..KhhhHHhhh',
  '.KhhHHhhhhh',
  '.KhHhhLhhhL',
  '.Khhhhhhhhh',
  '.Khhhhhhhhh',
  '.Khhhhhhhhh',
  '.KhhhhKKKjs',
  '.KhhhhsKsss',
  '.KhhhhsKsss',
  '.Khhhhsesss',
  '.Khhhhsssss',
  '.Khhhhjssss',
  '.KhhhhKKKKK',
  '..KhhhK....',
  '...KKK.....',
])
const BOB_UP = mirror([
  '......KKKKK',
  '....KKhhhhh',
  '...Khhhhhhh',
  '..KhhhhHHHH',
  '..KhhhHHhhh',
  '.KhhHHhhhhh',
  '.KhHhhLhhhL',
  ...Array<string>(10).fill('.Khhhhhhhhh'),
  '..Khhhhhhhh',
  '...KKKKKKKK',
])
const BOB_SIDE = [
  '......KKKKKKKKK......',
  '....KKhhhhhhhhhKK....',
  '...KhhhhhhhhhhhhhK...',
  '..KhhhhHHHHHhhhhhhK..',
  '..KhhhHHhhhhhHHhhhK..',
  '.KhhHhhhhhhhhhhHhhhK.',
  '.KhHhhLhhhLhhhhhhhhK.',
  '.KhhhhhhhhhhhhhhhhhK.',
  '.KhhhhhhhhhhhhhhhhhK.',
  '.KhhhhhhhhhhhhhhhhhK.',
  '.KhhhhhhhhhKKKKKKshK.',
  '.KhhhhhhhhhsssssKssK.',
  '.KhhhhhhhhhsssssKssK.',
  '.KhhhhhhhhhsssssessK.',
  '.KhhhhhhhhhsssssssK..',
  '.KhhhhhhhhhsssssjK...',
  '.KhhhhhhhhhKKKKKK....',
  '..KhhhhhhhK..........',
  '...KKKKKKK...........',
]
/** 长发：齐耳短发的两边和后背一直垂到第 22 行 */
const LONG_DOWN = swap(
  BOB_DOWN,
  17,
  ...mirror([
    '.KhhhK.....',
    '.KhhhK.....',
    '.KhhhK.....',
    '.KhhhK.....',
    '..KhK......',
    '...K.......',
  ])
)
const LONG_UP = swap(
  BOB_UP,
  17,
  ...mirror([...Array<string>(5).fill('..Khhhhhhhh'), '...KKKKKKKK'])
)
const LONG_SIDE = swap(
  BOB_SIDE,
  17,
  ...Array<string>(5).fill('..KhhhhhhhK..........'),
  '...KKKKKKK...........'
)
/** 中分长发：额头露出一个三角 */
const PARTED_DOWN = swap(
  LONG_DOWN,
  7,
  '.KhhhhhhhhKhhhhhhhhK.',
  '.KhhhhhhhKsKhhhhhhhK.',
  '.KhhhhhhKsssKhhhhhhK.',
  '.KhhhhKKsssssKKhhhhK.'
)
const PARTED_SIDE = swap(LONG_SIDE, 10, '.KhhhhhhhhhhhhKKsssK.')
/** 刺头：头顶翘起几撮，刘海三个尖 */
const SPIKY_TOP = ['....K...K...K...K....', '....KK.KhK.KhK.KK....', '....KhKhhhKhhhKhK....']
const SPIKY_DOWN = swap(swap(SHORT_DOWN, 0, ...SPIKY_TOP), 10, '.KhhhhKhKshsKhKhhhhK.')
const SPIKY_UP = swap(SHORT_UP, 0, ...SPIKY_TOP)
const SPIKY_SIDE = swap(SHORT_SIDE, 0, ...SPIKY_TOP)
/** 短发中分：头发长度同短发，额头中间露出一个三角 */
const SPLIT_DOWN = swap(SHORT_DOWN, 7, ...PARTED_DOWN.slice(7, 11))
const SPLIT_SIDE = swap(SHORT_SIDE, 10, PARTED_SIDE[10])
/** 寸头：头发只薄薄一层，发际线在额头上面，露出耳朵 */
const CROP_DOWN = [
  '.....................',
  '.....................',
  '.......KKKKKKK.......',
  '.....KKhhhhhhhKK.....',
  '....KhhhHHHHHhhhK....',
  '...KhhhhhhhhhhhhhK...',
  '...KhhhLhhhLhhhLhK...',
  '..KhhhhhhhhhhhhhhhK..',
  '..KhhKKKKKKKKKKKhhK..',
  '..KhKsssssssssssKhK..',
  '..KhKsssssssssssKhK..',
  '..KssssKsssssKssssK..',
  '..KssssKsssssKssssK..',
  '..KssssesssssessssK..',
  '...KsssssssssssssK...',
  '....KsjsssssssjsK....',
  '.....KKKKKKKKKKK.....',
]
const CROP_UP = mirror([
  '...........',
  '...........',
  '.......KKKK',
  '.....KKhhhh',
  '....KhhhHHH',
  '...Khhhhhhh',
  '...KhhhLhhh',
  '..Khhhhhhhh',
  '..Khhhhhhhh',
  '..Khhhhhhhh',
  '..Khhhhhhhh',
  '..Kshhhhhhh',
  '..Kshhhhhhh',
  '..Kshhhhhhh',
  '...KKhhhhhh',
  '....KKhhhhh',
  '......KKsss',
])
const CROP_SIDE = [
  '.....................',
  '.....................',
  '.......KKKKKKK.......',
  '.....KKhhhhhhhKK.....',
  '....KhhhHHHHHhhhK....',
  '...KhhhhhhhhhhhhhK...',
  '...KhhhLhhhLhhhhhK...',
  '..KhhhhhhhhhhhhhhhK..',
  '..KhhhhhhhhhhKKKKKK..',
  '..KhhhhhhhhhhsssssK..',
  '..KhhhhhhhhhhsssssK..',
  '..KhhhhhhssssssKssK..',
  '..KhhhhhhssssssKssK..',
  '..KhhhhhhssssssessK..',
  '...KhhhhhssssssssK...',
  '....KhhhhsssssjsK....',
  '......KKKKKKKKKK.....',
]
/** 头发往后扎：额头全露，发际线是一道弧，两边在耳朵下面收住 */
const TIED_DOWN = [
  ...SHORT_DOWN.slice(0, 7),
  '.KhhhhhhKKKKKhhhhhhK.',
  '.KhhhhKKsssssKKhhhhK.',
  '.KhhhKsssssssssKhhhK.',
  '.KhhhssssssssssshhhK.',
  '.KhhhssKsssssKsshhhK.',
  '.KhhhssKsssssKsshhhK.',
  '.KhhhssesssssesshhhK.',
  '..KhhssssssssssshhK..',
  '...KKsjsssssssjsKK...',
  '.....KKKKKKKKKKK.....',
]
const TIED_SIDE = [
  ...SHORT_SIDE.slice(0, 7),
  '.KhhhhhhhhhhhhKKKKKK.',
  '.KhhhhhhhhhhhKsssssK.',
  '.KhhhhhhhhhhKssssssK.',
  '.KhhhhhhhhhssssssssK.',
  ...SHORT_SIDE.slice(11),
]

const BUN_TOP = overlay(7, -3, ['.KKKKK.', 'KhhHhhK', 'KhhhhhK', 'KxxxxxK'])
const BUN_SIDE = overlay(2, -1, ['.KKK.', 'KhHhK', 'Kxxx.', '.K...'])
const PONYTAIL_UP = overlay(8, 14, ['.xxx.', ...Array<string>(6).fill('KhhhK'), '.KhK.', '..K..'])
const PONYTAIL_SIDE = overlay(-1, 7, ['.K', 'Kx', ...Array<string>(9).fill('Kh'), '.K'])
const TWINTAIL_FRONT = [
  ...overlay(-2, 4, ['Kxx', ...Array<string>(13).fill('Khh'), '.KK']),
  ...overlay(20, 4, ['xxK', ...Array<string>(13).fill('hhK'), 'KK.']),
]
const TWINTAIL_SIDE = overlay(-2, 4, ['.xx', ...Array<string>(13).fill('Khh'), '.KK'])
const AHOGE: Record<View, Patch> = {
  down: overlay(11, 0, ['KK', 'hK']),
  up: overlay(8, 0, ['KK', 'Kh']),
  side: overlay(8, 0, ['KK', 'hK']),
}
/** 胡子连着鬓角，从下巴一直围到耳边 */
const BEARD: Partial<Record<View, Patch>> = {
  down: overlay(4, 14, ['hh.........hh', '.hhhhhhhhhhh.']),
  side: overlay(9, 14, ['hh.....', 'hhhhhhh']),
}
/** 络腮胡以外的几种胡子：长须（三绺垂到胸前）、虬髯（又粗又密、下沿带尖）、山羊胡（八字胡加一撮下巴胡） */
type BeardStyle = 'long' | 'bushy' | 'goatee'
const BEARDS: Record<BeardStyle, Partial<Record<View, Patch>>> = {
  long: {
    down: overlay(6, 14, [
      '..hh.hh..',
      '.hhhhhhh.',
      '.h.hhh.h.',
      'KhKhhhKhK',
      '.K.KhK.K.',
      '...KhK...',
      '....K....',
    ]),
    side: overlay(12, 14, ['....hh', '.hhhhh', '..hhh.', '.KhhhK', '..KhK.', '..KhK.', '...K..']),
  },
  bushy: {
    down: overlay(2, 13, [
      '.hh...........hh.',
      'hhhh..hhhhh..hhhh',
      'hhhhhhhhhhhhhhhhh',
      'hhhhhhhhhhhhhhhhh',
      'KhhhhhhhhhhhhhhhK',
      '.hKhhKhhhhKhhKhh.',
      '.K.KK.KhhK.KK.K..',
      '.......KK........',
    ]),
    side: overlay(9, 13, [
      '.......hh',
      'hh...hhhh',
      'hhhhhhhhh',
      'hhhhhhhhh',
      'KhhhhhhhK',
      '.hKhhKhh.',
      '.K.KK.KK.',
    ]),
  },
  goatee: {
    down: overlay(7, 14, ['.hh.hh.', '..hhh..', '..hhh..', '..KhK..', '...K...']),
    side: overlay(14, 14, ['..hh', '.hh.', '.hh.', '.Kh.', '..K.']),
  },
}
/** 草帽：盖住头顶 0～4 行，帽檐压在第 5～6 行 */
const HAT_FRONT = overlay(0, 0, [
  '......KKKKKKKKK......',
  '.....KzzzzzzzzzK.....',
  '....KzzzzzzzzzzzK....',
  '....KXXXXXXXXXXXK....',
  '.KKKKzzzzzzzzzzzKKKK.',
  'KzzzzzzzzzzzzzzzzzzzK',
  '.KKKKKKKKKKKKKKKKKKK.',
])
const HAT: Record<View, Patch> = {
  down: HAT_FRONT,
  up: HAT_FRONT,
  side: overlay(0, 0, [
    '.....KKKKKKKKK.......',
    '....KzzzzzzzzzK......',
    '...KzzzzzzzzzzzK.....',
    '...KXXXXXXXXXXXK.....',
    'KKKKzzzzzzzzzzzKKKKK.',
    'KzzzzzzzzzzzzzzzzzzzK',
    '.KKKKKKKKKKKKKKKKKKK.',
  ]),
}
const CLIP: Partial<Record<View, Patch>> = {
  down: overlay(3, 5, ['xx']),
  side: overlay(9, 5, ['xx']),
}

// ---- 奇特发型 ----

/** 把一套底稿里的颜色位换掉：光头、莫西干从寸头改 */
const recolor = (rows: Rows, map: Record<string, string>) =>
  rows.map((row) => [...row].map((ch) => map[ch] ?? ch).join(''))
/** 光头：寸头的头发换成皮肤，头顶的高光换成皮肤的反光，发际线去掉 */
const SCALP = { h: 's', L: 's', H: 'S' }
const BALD_DOWN = swap(recolor(CROP_DOWN, SCALP), 8, '..KsssssssssssssssK..')
const BALD_UP = recolor(CROP_UP, SCALP)
const BALD_SIDE = swap(recolor(CROP_SIDE, SCALP), 8, '..KsssssssssssssssK..')
/** 莫西干：两边剃成青皮（v），头顶中间留一道头发，竖起一排尖冠 */
const SHAVED = { h: 'v', L: 'v', H: 'v' }
const MOHAWK_DOWN = recolor(CROP_DOWN, SHAVED).map((row, y) =>
  y >= 2 && y <= 7 ? row.slice(0, 8) + 'hhhhh' + row.slice(13) : row
)
const MOHAWK_UP = recolor(CROP_UP, SHAVED).map((row, y) =>
  y >= 2 && y <= 15 ? row.slice(0, 8) + 'hhhhh' + row.slice(13) : row
)
const MOHAWK_SIDE = swap(recolor(CROP_SIDE, SHAVED), 2, '.......KKKKKKK.......')
const CREST_FRONT = overlay(7, -3, [
  '..K.K..',
  '.KhKhK.',
  '.KhHhK.',
  'KhhHhhK',
  'KhhHhhK',
  'KhhhhhK',
])
const CREST_SIDE = overlay(2, -3, [
  '..K....K....K.....',
  '.KhK..KhK..KhK....',
  '.KhhKKhHhKKhhhK...',
  'KhhhhhhHhhhhhhhKK.',
  'KhhHhhhhhhhhHhhhhK',
  '.KKhhhhhhhhhhhhhKK',
])
/**
 * 爆炸头：一团圆蓬蓬的卷发从头顶一直蓬到下巴，比头宽一圈，脸露在中间。整团（连同脸）当一张图
 * 贴在头的位置，头发底稿留空；戴帽子时只露出帽檐下的部分
 */
const AFRO_TOP = [
  '.....KKKKKKKKKKKKK.....',
  '...KKhhhHhhhhhHhhhKK...',
  '..KhhHhhhhhhhhhhhhHhK..',
  '.KhhhhhhhhHhhhHhhhhhhK.',
  '.KhHhhhhhhhhhhhhhhhHhK.',
  'KhhhhhhhhhhhhhhhhhhhhhK',
  'KhhhhhhhhhhhhhhhhhhhhhK',
  'KhHhhhhhhhhhhhhhhhhhHhK',
  ...Array<string>(5).fill('KhhhhhhhhhhhhhhhhhhhhhK'),
]
const AFRO_FRONT = overlay(-1, -3, [
  ...AFRO_TOP,
  'KhhhhhhKhKjsjKhKhhhhhhK',
  'KhhhhhhsKsssssKshhhhhhK',
  'KhhhhhhsKsssssKshhhhhhK',
  'KhhhhhKsesssssesKhhhhhK',
  '.KhhhhKsssssssssKhhhhK.',
  '..KhhhKjsssssssjKhhhK..',
  '...KKKKKKKKKKKKKKKKK...',
])
const AFRO_BACK = overlay(-1, -3, [
  ...AFRO_TOP,
  ...Array<string>(4).fill('KhhhhhhhhhhhhhhhhhhhhhK'),
  '.KhhhhhhhhhhhhhhhhhhhK.',
  '..KhhhhhhhhhhhhhhhhhK..',
  '...KKKKKKsssssKKKKKK...',
])
const AFRO_SIDE = overlay(-1, -3, [
  '...KKKKKKKKKKKK........',
  '.KKhhhHhhhhhHhhKK......',
  'KhhHhhhhhhhhhhhhhK.....',
  'KhhhhhhhhHhhhHhhhhK....',
  'KhHhhhhhhhhhhhhhhhhK...',
  'KhhhhhhhhhhhhhhhhhhhK..',
  'KhhhhhhhhhhhhhhhhhhhK..',
  'KhHhhhhhhhhhhhhhhHhhhK.',
  ...Array<string>(5).fill('KhhhhhhhhhhhhhhhhhhhhK.'),
  'KhhhhhhhhhhhKKhKKKshK..',
  'KhhhhhhhhhhhsssssKssK..',
  'KhhhhhhhhhhhsssssKssK..',
  'KhhhhhhhhhhhsssssessK..',
  '.KhhhhhhhhhhsssssssK...',
  '..KhhhhhhhhhsssssjK....',
  '...KKKKKKKKKKKKKKK.....',
])

// ---- 大葱头、M 刘海 ----

/**
 * 大葱头：一把叶子似的头发从头顶竖起来，中间一片最高（顶到帧顶），两边的往外倒，最外两片垂到耳边；
 * 额头露出来（寸头的脸，发际线带一点弧），鬓边各垂一缕到下巴。叶子整片当贴片画在头上，
 * 横跨 25 列（左右各出头 2 列），从第 -6 行到第 7 行
 */
const SCALLION_CROWN = overlay(-2, -6, [
  '............K............',
  '.......K...KhK...K.......',
  '......KhK..KhK..KhK......',
  '...K..KhK.KhHhK.KhK..K...',
  '..KhKKhHhKKhHhKKhHhKKhK..',
  '..KHhKhHhKKhHhKKhHhKHhK..',
  'K.KHhKhHhhKhHhKhHhhKHhK.K',
  'KhKhhKhhhKhhhhhKhhhKhhKhK',
  '.KhKhKhhhKhhhhhKhhhKhKhK.',
  '..KKhhhKhhhhhhhhhKhhhKK..',
  '..KhhhhhhhhhhhhhhhhhhhK..',
  '...KhhhhhhhhhhhhhhhhhK...',
  '...KhhhhhhhhhhhhhhhhhK...',
  '....KhhhhhhhhhhhhhhhK....',
])
/** 侧面的叶子往后倒，最前面一片探到额头上 */
const SCALLION_CROWN_SIDE = overlay(-2, -6, [
  '............K............',
  '.......K...KhK...........',
  '......KhK..KhK...K.......',
  '...K..KhK.KhHhK.KhK......',
  '..KhK.KHhKKhHhKKHhK......',
  '..KHhKKHhKKhHhKKHhK..K...',
  'K..KHhKhHhKhHhKhHhK.KhK..',
  'KhKKhhKKhhKhhhKhhhKKhhK..',
  '.KhKKhhKhhKhhhKhhhKhhK...',
  '..KhKhhhhhhhhhhhhhKhhK...',
  '...KhhhhhhhhhhhhhhhhhK...',
  '...KhhhhhhhhhhhhhhhhhK...',
  '....KhhhhhhhhhhhhhhhK....',
  '....KhhhhhhhhhhhhhhhK....',
])
const SCALLION_DOWN = swap(CROP_DOWN, 8, '..KhhhKKKKKKKKKhhhK..', '..KhhKsssssssssKhhK..')
/** 鬓边两缕：从发际线垂到下巴，盖在寸头露出的鬓角上 */
const SCALLION_STRANDS = [
  ...overlay(2, 9, ['Kh.', 'KhK', 'KhK', 'KhK', 'KhK', '.K.']),
  ...overlay(16, 9, ['.hK', 'KhK', 'KhK', 'KhK', 'KhK', '.K.']),
]
const SCALLION_STRAND_SIDE = overlay(12, 9, ['Kh', 'Kh', 'Kh', 'Kh', 'Kh', '.K'])
/** M 刘海：刘海从中间分开，下沿是锯齿的 M，鬓边一缕垂到眼角 */
const M_FRINGE = mirror(['.KhhhhhhhhK', '.KhhhhhhKhs', '.KhhhhhKsKs', '.KhhhhhKsss', '.KhhhhKKsss'])
const M_BANGS_DOWN = swap(BOB_DOWN, 8, ...M_FRINGE)
/** M 刘海长发：两边和后背垂到第 24 行（比长发长两行），耳边往外翘一个尖 */
const M_LONG_DOWN = swap(
  M_BANGS_DOWN,
  17,
  ...mirror([...Array<string>(6).fill('.KhhhK.....'), '..KhK......', '...K.......'])
)
const M_LONG_UP = swap(
  BOB_UP,
  17,
  ...mirror([...Array<string>(7).fill('..Khhhhhhhh'), '...KKKKKKKK'])
)
const M_LONG_SIDE = swap(
  BOB_SIDE,
  17,
  ...Array<string>(7).fill('..KhhhhhhhK..........'),
  '...KKKKKKK...........'
)
/** 耳边外翘：头发侧边在 11～12 行往外鼓一格，11 行尖出去；侧面只翘后脑勺那一边 */
const FLIP_LEFT = overlay(-1, 10, ['.K', 'Khh', '.Kh'])
const FLIPS = [...FLIP_LEFT, ...overlay(19, 10, ['.K', 'hhK', 'hK'])]

// ---- 头上戴的：草帽以外的帽子和头饰 ----
// covers 的帽子像草帽一样盖住头顶：头发只从第 5 行画起，头顶的发髻、呆毛不画

type Headwear =
  | 'cat_ears'
  | 'bunny_ears'
  | 'horns'
  | 'antennae'
  | 'halo'
  | 'crown'
  | 'top_hat'
  | 'wizard_hat'
  | 'chef_hat'
  | 'circlet'
  | 'pig_ears'
  | 'aureole'
  | 'scholar_cap'
  | 'topknot_crown'
  | 'feather_crown'
  | 'official_hat'

interface Headgear {
  patch: Record<View, Patch>
  covers?: boolean
  /** 画在头后面、先于头发的部分：佛光 */
  back?: Patch
  /** 换掉发型规定的那两行头发（紧箍）：两行各用什么颜色位 */
  band?: readonly [string, string]
}
const same = (patch: Patch): Record<View, Patch> => ({ down: patch, up: patch, side: patch })
const TOP_HAT = overlay(0, -3, [
  '.....KKKKKKKKKKK.....',
  '.....KnNnnnnnnnK.....',
  '.....KnNnnnnnnnK.....',
  '.....KnNnnnnnnnK.....',
  '.....KnNnnnnnnnK.....',
  '.....KxxxxxxxxxK.....',
  '.....KnnnnnnnnnK.....',
  '..KKKKnnnnnnnnnKKKK..',
  'KKnnnnnnnnnnnnnnnnnKK',
  '.KKKKKKKKKKKKKKKKKKK.',
])
const WIZARD_HAT: Record<View, Patch> = {
  down: overlay(0, -3, [
    '.............KK......',
    '...........KKtK......',
    '.........KKtttK......',
    '........KtttttTK.....',
    '.......KttttttTTK....',
    '......KYYYYYYYYYYK...',
    '.....KttttttttTTTTK..',
    '.KKKKttttttttttTTTKKK',
    'KttttttttttttttttTTTK',
    '.KKKKKKKKKKKKKKKKKKK.',
  ]),
  up: overlay(0, -3, [
    '......KK.............',
    '......KtKK...........',
    '......KTttKK.........',
    '.....KTtttttK........',
    '....KTTttttttK.......',
    '...KYYYYYYYYYYK......',
    '..KTTTTttttttttK.....',
    'KKKTTTttttttttttKKKK.',
    'KTTTttttttttttttttttK',
    '.KKKKKKKKKKKKKKKKKKK.',
  ]),
  side: overlay(0, -3, [
    '.KK..................',
    '.KtKK................',
    '..KttKK..............',
    '...KtttKKK...........',
    '....KtttttTK.........',
    '...KYYYYYYYYK........',
    '..KtttttttttTK.......',
    'KKtttttttttttTKKKKK..',
    'KttttttttttttttttttTK',
    '.KKKKKKKKKKKKKKKKKKK.',
  ]),
}
const CHEF_HAT = overlay(0, -3, [
  '.....KKK.KKK.KKK.....',
  '....KWWWKWWWKWWWK....',
  '...KWWWWWWWWWWWWWK...',
  '...KWWWWWWWWWWWWWK...',
  '...KWWWWWWWWWWWWWK...',
  '...KgWWWWWWWWWWWgK...',
  '...KKKKKKKKKKKKKKK...',
  '..KWWWWWWWWWWWWWWWK..',
  '.KWWWWWWWWWWWWWWWWWK.',
  '.KKKKKKKKKKKKKKKKKKK.',
])
const CROWN = overlay(5, -3, [
  'K...K...K...K',
  'KK.KYK.KYK.KK',
  'KYKYYYKYYYKYK',
  'KYYYYxYYYYYYK',
  'KYUxUUUUUxUYK',
  'KKKKKKKKKKKKK',
])
const CROWN_SIDE = overlay(5, -3, [
  'K...K...K....',
  'KK.KYK.KYK...',
  'KYKYYYKYYYK..',
  'KYYYxYYYYYYK.',
  'KUUUUUUUxUUK.',
  'KKKKKKKKKKKK.',
])
const HALO = overlay(5, -3, ['..YYYYYYY..', 'YY.......YY', '..UUUUUUU..'])
const CAT_EARS: Record<View, Patch> = {
  down: [
    ...overlay(2, -2, ['K.....', 'KK....', 'KjK...', 'KjjK..', 'KhjhK.']),
    ...overlay(13, -2, ['.....K', '....KK', '...KjK', '..KjjK', '.KhjhK']),
  ],
  up: [
    ...overlay(2, -2, ['K.....', 'KK....', 'KhK...', 'KhhK..', 'KhhhK.']),
    ...overlay(13, -2, ['.....K', '....KK', '...KhK', '..KhhK', '.KhhhK']),
  ],
  side: overlay(4, -2, ['.....K...', '....KK..K', '...KjK.KK', '..KjjKKhK', '.KhjhKhhK']),
}
const BUNNY_EARS: Record<View, Patch> = {
  down: [
    ...overlay(5, -3, ['.KK.', 'KWWK', 'KjWK', 'KjWK', 'KjWK', '.KWK']),
    ...overlay(12, -3, ['.KK.', 'KWWK', 'KWjK', 'KWjK', 'KWjK', 'KWK.']),
  ],
  up: [
    ...overlay(5, -3, ['.KK.', 'KWWK', 'KWWK', 'KWWK', 'KWWK', '.KWK']),
    ...overlay(12, -3, ['.KK.', 'KWWK', 'KWWK', 'KWWK', 'KWWK', 'KWK.']),
  ],
  side: overlay(5, -3, ['.KK.KK.', 'KWWKWWK', 'KjWKjWK', 'KjWKjWK', '.KjWKWK', '..KWKK.']),
}
const HORNS: Record<View, Patch> = {
  down: [
    ...overlay(3, -1, ['K..', 'xK.', 'xxK', '.xK']),
    ...overlay(15, -1, ['..K', '.Kx', 'Kxx', 'Kx.']),
  ],
  up: [
    ...overlay(3, -1, ['K..', 'xK.', 'xxK', '.xK']),
    ...overlay(15, -1, ['..K', '.Kx', 'Kxx', 'Kx.']),
  ],
  side: overlay(10, -1, ['..K', '.Kx', 'Kxx', 'Kx.']),
}
const ANTENNAE: Record<View, Patch> = {
  down: [
    ...overlay(4, -3, ['KxK..', 'KxxK.', '.KK..', '...K.', '....K']),
    ...overlay(12, -3, ['..KxK', '.KxxK', '..KK.', '.K...', 'K....']),
  ],
  up: [
    ...overlay(4, -3, ['KxK..', 'KxxK.', '.KK..', '...K.', '....K']),
    ...overlay(12, -3, ['..KxK', '.KxxK', '..KK.', '.K...', 'K....']),
  ],
  side: overlay(9, -3, ['....KxK', '...KxxK', '....KK.', '...K...', '..K....']),
}
/** 猪耳朵：两只大耳朵从头两边耷拉下来，里面粉色 */
const PIG_EARS: Record<View, Patch> = {
  down: [
    ...overlay(-1, 4, ['..KK.', '.KssK', 'KsjsK', 'KsjsK', 'KsjK.', '.KK..']),
    ...overlay(17, 4, ['.KK..', 'KssK.', 'KsjsK', 'KsjsK', '.KjsK', '..KK.']),
  ],
  up: [
    ...overlay(-1, 4, ['..KK.', '.KssK', 'KsssK', 'KsssK', 'KssK.', '.KK..']),
    ...overlay(17, 4, ['.KK..', 'KssK.', 'KsssK', 'KsssK', '.KssK', '..KK.']),
  ],
  side: overlay(5, 4, ['.KK..', 'KssK.', 'KsjsK', 'KsjsK', 'KsjsK', '.KsK.', '..K..']),
}
/** 佛光：头后面一圈金色的光轮，头挡住中间 */
const AUREOLE: Patch = (() => {
  const out: [number, number, string][] = []
  for (let y = -3; y <= 15; y++)
    for (let x = -2; x <= 22; x++) {
      const d = Math.hypot(x - 10, (y - 7) * 1.08)
      if (d <= 12.6 && d > 11.4) out.push([x, y, 'Y'])
      else if (d <= 11.4 && d > 10.4) out.push([x, y, 'U'])
    }
  return out
})()
/** 纶巾（诸葛亮、关羽）：软软的方顶头巾，点缀色；背后垂两根带子 */
const CAP = [
  '......KKKKKKKKK......',
  '.....KEEEEKEEEEK.....',
  '....KExxxxKxxxxEK....',
  '...KExxxxxKxxxxxEK...',
  '..KExxxxxxKxxxxxxEK..',
  '..KxxxxxxxxxxxxxxxK..',
  '.KEEEEEEEEEEEEEEEEEK.',
  '.KKKKKKKKKKKKKKKKKKK.',
]
const SCHOLAR_CAP: Record<View, Patch> = {
  down: overlay(0, -1, CAP),
  up: [...overlay(0, -1, CAP), ...overlay(7, 7, Array(6).fill('KxK.KxK').concat(['.K...K.']))],
  side: [
    ...overlay(0, -1, [
      '.....KKKKKKKKK.......',
      '....KEEEEEEEEEK......',
      '...KExxxxxxxxxEK.....',
      '..KExxxxxxxxxxxEK....',
      '.KExxxxxxxxxxxxxEK...',
      '.KxxxxxxxxxxxxxxxxK..',
      'KEEEEEEEEEEEEEEEEEEK.',
      'KKKKKKKKKKKKKKKKKKKK.',
    ]),
    ...overlay(-1, 7, ['Kx', 'Kx', 'Kx', 'Kx', 'Kx', '.K']),
  ],
}
/** 束发金冠（周瑜、赵云）：头顶挽一个髻，套着金冠，横插一根簪子，冠上嵌点缀色的珠子 */
const TOPKNOT = ['..KKKKK..', '.KhhHhhK.', 'KKYYYYYKK', '.KYUxUYK.', '..KKKKK..']
const TOPKNOT_CROWN = same(overlay(6, -3, TOPKNOT))
/** 紫金冠插雉鸡翎（吕布）：金冠两边各插一根长翎子，往两边弯下来 */
const FEATHER_CROWN: Record<View, Patch> = {
  down: overlay(-2, -3, [
    '.FFUFFUF.KKKKK.FUFFUFF...',
    'FKKKKKKKKhhHhhKKKKKKKKF..',
    'U.......KYYYYYK.......U..',
    'F........KUxUK........F..',
    'F.........KKK.........F..',
    'U.....................U..',
    'F.....................F..',
    '.F...................F...',
  ]),
  up: overlay(-2, -3, [
    '.FFUFFUF.KKKKK.FUFFUFF...',
    'FKKKKKKKKhhHhhKKKKKKKKF..',
    'U.......KYYYYYK.......U..',
    'F........KYYYK........F..',
    'F.........KKK.........F..',
    'U.....................U..',
    'F.....................F..',
    '.F...................F...',
  ]),
  side: overlay(-2, -3, [
    '.FUFFUFFKKKKK....',
    'FKKKKKKKhhHhhK...',
    'U......KYYYYYK...',
    'F.......KUxUK....',
    'F........KKK.....',
    'U................',
    'F................',
    '.F...............',
  ]),
}
/** 官帽（曹操、文官）：黑色高冠，两边伸出一对帽翅 */
const OFFICIAL_HAT_FRONT = overlay(-2, -3, [
  '........KKKKKKKKK........',
  '.......KnNnnnnnnnK.......',
  'KKKK...KnNnnnnnnnK...KKKK',
  'KnnnKKKKnnnnnnnnnKKKKnnnK',
  'KKKKKnnnnnnnnnnnnnnnKKKKK',
  '....KnnnnnnnnnnnnnnnK....',
  '...KnnnnnnnnnnnnnnnnnK...',
  '...KnnnnnnnnnnnnnnnnnK...',
  '...KNNNNNNNNNNNNNNNNNK...',
  '...KKKKKKKKKKKKKKKKKKK...',
])
const OFFICIAL_HAT_SIDE = overlay(0, -3, [
  '.....KKKKKKKKK.......',
  '....KnNnnnnnnnK......',
  '....KnNnnnnnnnK......',
  '....KnnnnnnnnnK......',
  '..KKKnnnnnnnnnKKK....',
  '.KnnnnnnnnnnnnnnnK...',
  'KnnnnnnnnnnnnnnnnnK..',
  'KnnnnnnnnnnnnnnnnnnK.',
  'KnnnnnnnnnnnnnnnnnnK.',
  'KKKKKKKKKKKKKKKKKKKK.',
])
const HEADWEAR: Record<Headwear, Headgear> = {
  cat_ears: { patch: CAT_EARS },
  bunny_ears: { patch: BUNNY_EARS },
  horns: { patch: HORNS },
  antennae: { patch: ANTENNAE },
  halo: { patch: same(HALO) },
  crown: { patch: { down: CROWN, up: CROWN, side: CROWN_SIDE } },
  top_hat: { patch: same(TOP_HAT), covers: true },
  wizard_hat: { patch: WIZARD_HAT, covers: true },
  chef_hat: { patch: same(CHEF_HAT), covers: true },
  circlet: { patch: same([]), band: ['Y', 'U'] },
  pig_ears: { patch: PIG_EARS },
  aureole: { patch: same([]), back: AUREOLE },
  scholar_cap: { patch: SCHOLAR_CAP, covers: true },
  topknot_crown: { patch: TOPKNOT_CROWN },
  feather_crown: { patch: FEATHER_CROWN },
  official_hat: {
    patch: { down: OFFICIAL_HAT_FRONT, up: OFFICIAL_HAT_FRONT, side: OFFICIAL_HAT_SIDE },
    covers: true,
  },
}

// ---- 脸上戴的：按这一帧里眼睛那一格（e）摆，正面两只眼、侧面一只，背面不画 ----

type FaceGear =
  | 'glasses'
  | 'sunglasses'
  | 'eye_patch'
  | 'clown_nose'
  | 'monkey_face'
  | 'pig_snout'
  | 'forehead_dot'

/** 眼睛那一格 [x, y]（人物坐标）；侧面另给脸前沿那条描边的 x */
interface Eyes {
  at: (readonly [number, number])[]
  front: number
}
const ring = (ex: number, ey: number): Patch => [
  ...overlay(ex - 1, ey - 3, ['KKK']),
  ...overlay(ex - 2, ey - 2, ['K...K', 'K...K', 'K...K']),
  ...overlay(ex - 1, ey + 1, ['KKK']),
]
/** 猴脸：眼睛周围留一张桃心脸，其余的脸换成毛色（头发色）；at 读这一帧已画好的格子 */
function monkeyFace(view: View, eyes: Eyes, at: (x: number, y: number) => string | null): Patch {
  const [[lx, ey], second] = eyes.at
  const rx = second?.[0] ?? lx
  const bare = (x: number, y: number) => {
    const d = y - ey
    if (view === 'side') return d >= -3 && d <= 2 && x >= lx - (d === 2 ? 0 : 1)
    if (d === -3) return Math.abs(x - lx) <= 1 || Math.abs(x - rx) <= 1
    if (d >= -2 && d <= 0) return x >= lx - 1 && x <= rx + 1
    if (d === 1) return x >= lx && x <= rx
    if (d === 2) return x >= lx + 1 && x <= rx - 1
    return d === 3 && x >= lx + 2 && x <= rx - 2
  }
  const out: [number, number, string][] = []
  for (let y = ey - 4; y <= ey + 3; y++)
    for (let x = -OX; x < FRAME_W - OX; x++)
      if ('sjS'.includes(at(x, y) ?? '.') && !bare(x, y)) out.push([x, y, 'h'])
  // 两只圆圆的猴耳朵贴在头两边；侧面只看得到一只
  const ear = ['.KK.', 'KjsK', 'KjsK', '.KK.']
  if (view === 'side') return [...out, ...overlay(lx - 12, ey - 3, ear)]
  return [
    ...out,
    ...overlay(lx - 9, ey - 4, ear),
    ...overlay(rx + 6, ey - 4, ['.KK.', 'KsjK', 'KsjK', '.KK.']),
  ]
}
function faceGear(
  gear: FaceGear,
  view: View,
  eyes: Eyes,
  at: (x: number, y: number) => string | null
): Patch {
  const [first, second] = eyes.at
  if (!first || view === 'up') return []
  if (gear === 'monkey_face') return monkeyFace(view, eyes, at)
  if (view === 'side') {
    const [ex, ey] = first
    if (gear === 'pig_snout') return overlay(eyes.front - 1, ey, ['PPPK', 'PPKK', '.KK.'])
    if (gear === 'forehead_dot') return [[eyes.front - 2, ey - 4, 'r']]
    if (gear === 'glasses') return [...ring(ex, ey), ...overlay(ex - 6, ey - 2, ['KKKK'])]
    if (gear === 'sunglasses')
      return [
        ...overlay(ex - 1, ey - 2, ['WnK', 'nnK', 'nnK']),
        ...overlay(ex - 6, ey - 2, ['KKKKK']),
      ]
    if (gear === 'eye_patch')
      return [
        ...overlay(ex - 1, ey - 2, ['KKK', 'KKK', 'KKK']),
        ...overlay(ex - 7, ey - 6, ['KK....', '..KK..', '....KK']),
      ]
    return overlay(eyes.front, ey, ['rr', 'rr'])
  }
  const [lx, ey] = first
  const rx = second?.[0] ?? lx + 6
  if (gear === 'glasses')
    return [
      ...ring(lx, ey),
      ...ring(rx, ey),
      ...overlay(lx + 3, ey - 2, ['K'.repeat(Math.max(1, rx - lx - 5))]),
      [lx - 3, ey - 2, 'K'],
      [rx + 3, ey - 2, 'K'],
    ]
  if (gear === 'sunglasses')
    return [
      ...overlay(lx - 2, ey - 2, ['KWnnK', 'Knnnn', '.nnn.']),
      ...overlay(rx - 2, ey - 2, ['KWnnK', 'nnnnK', '.nnn.']),
      ...overlay(lx + 3, ey - 2, ['K'.repeat(Math.max(1, rx - lx - 5))]),
    ]
  if (gear === 'eye_patch')
    return [
      ...overlay(rx - 1, ey - 2, ['KKK', 'KKK', '.K.']),
      ...overlay(lx - 4, ey - 6, ['KK.......', '..KK.....', '....KK...', '......KK.']),
      ...overlay(rx + 2, ey - 2, ['KK']),
    ]
  const nx = Math.round((lx + rx) / 2)
  if (gear === 'pig_snout') return overlay(nx - 2, ey, ['.PPP.', 'PKPKP', '.PPP.'])
  if (gear === 'forehead_dot') return [[nx, ey - 4, 'r']]
  return overlay(nx - 1, ey, ['.r.', 'rWr', '.r.'])
}

type HairStyle =
  | 'short'
  | 'spiky'
  | 'split'
  | 'crop'
  | 'bob'
  | 'long'
  | 'parted'
  | 'bun'
  | 'ponytail'
  | 'twintail'
  | 'afro'
  | 'mohawk'
  | 'bald'
  | 'twin_buns'
  | 'curls'
  | 'scallion'
  | 'm_bangs'
  | 'm_long'

interface Hair {
  rows: Record<View, Rows>
  extra?: Partial<Record<View, Patch>>
  /** 画在头后面、先于头发的部件：爆炸头蓬起来的那团 */
  back?: Partial<Record<View, Patch>>
  /** 头巾压在哪两行：只把这两行里的头发换成头巾色 */
  band: readonly [number, number]
  /** 往上竖的发型：渐变发的发梢在上面 */
  up?: boolean
}
const TIED = { down: TIED_DOWN, up: SHORT_UP, side: TIED_SIDE }
/** 双髻（哪吒头）：头发往上扎成左右两个小发髻，下面系点缀色的发带 */
const TWIN_BUN = ['.KKK.', 'KhHhK', 'KhhhK', '.KxK.']
const TWIN_BUNS_FRONT = [...overlay(2, -2, TWIN_BUN), ...overlay(14, -2, TWIN_BUN)]
/** 螺发：寸头上满是一粒粒卷发（亮暗相间），头顶隆起肉髻 */
const curl = (rows: Rows) =>
  rows.map((row, y) =>
    [...row].map((ch, x) => (ch === 'h' && y >= 2 && (x + y) % 2 === 0 ? 'H' : ch)).join('')
  )
const USHNISHA = overlay(8, -1, ['.KKK.', 'KhHhK', 'KHhHK', 'hhhhh'])
const HAIR: Record<HairStyle, Hair> = {
  short: { rows: { down: SHORT_DOWN, up: SHORT_UP, side: SHORT_SIDE }, band: [7, 8] },
  spiky: { rows: { down: SPIKY_DOWN, up: SPIKY_UP, side: SPIKY_SIDE }, band: [7, 8], up: true },
  split: { rows: { down: SPLIT_DOWN, up: SHORT_UP, side: SPLIT_SIDE }, band: [5, 6] },
  crop: { rows: { down: CROP_DOWN, up: CROP_UP, side: CROP_SIDE }, band: [6, 7] },
  bob: { rows: { down: BOB_DOWN, up: BOB_UP, side: BOB_SIDE }, band: [7, 8] },
  long: { rows: { down: LONG_DOWN, up: LONG_UP, side: LONG_SIDE }, band: [7, 8] },
  parted: { rows: { down: PARTED_DOWN, up: LONG_UP, side: PARTED_SIDE }, band: [5, 6] },
  bun: { rows: TIED, extra: { down: BUN_TOP, up: BUN_TOP, side: BUN_SIDE }, band: [5, 6] },
  ponytail: { rows: TIED, extra: { up: PONYTAIL_UP, side: PONYTAIL_SIDE }, band: [5, 6] },
  twintail: {
    rows: { down: BOB_DOWN, up: BOB_UP, side: BOB_SIDE },
    extra: { down: TWINTAIL_FRONT, up: TWINTAIL_FRONT, side: TWINTAIL_SIDE },
    band: [7, 8],
  },
  afro: {
    rows: { down: [], up: [], side: [] },
    back: { down: AFRO_FRONT, up: AFRO_BACK, side: AFRO_SIDE },
    band: [2, 3],
  },
  mohawk: {
    rows: { down: MOHAWK_DOWN, up: MOHAWK_UP, side: MOHAWK_SIDE },
    extra: { down: CREST_FRONT, up: CREST_FRONT, side: CREST_SIDE },
    band: [7, 8],
    up: true,
  },
  bald: { rows: { down: BALD_DOWN, up: BALD_UP, side: BALD_SIDE }, band: [6, 7] },
  twin_buns: {
    rows: TIED,
    extra: { down: TWIN_BUNS_FRONT, up: TWIN_BUNS_FRONT, side: overlay(7, -2, TWIN_BUN) },
    band: [5, 6],
  },
  curls: {
    rows: { down: curl(CROP_DOWN), up: curl(CROP_UP), side: curl(CROP_SIDE) },
    extra: {
      down: USHNISHA,
      up: USHNISHA,
      side: overlay(7, -1, ['.KKK.', 'KhHhK', 'KHhHK', 'hhhhh']),
    },
    band: [6, 7],
  },
  scallion: {
    rows: { down: SCALLION_DOWN, up: CROP_UP, side: CROP_SIDE },
    extra: {
      down: [...SCALLION_CROWN, ...SCALLION_STRANDS],
      up: SCALLION_CROWN,
      side: [...SCALLION_CROWN_SIDE, ...SCALLION_STRAND_SIDE],
    },
    band: [6, 7],
    up: true,
  },
  m_bangs: { rows: { down: M_BANGS_DOWN, up: BOB_UP, side: BOB_SIDE }, band: [5, 6] },
  m_long: {
    rows: { down: M_LONG_DOWN, up: M_LONG_UP, side: M_LONG_SIDE },
    extra: { down: FLIPS, up: FLIPS, side: FLIP_LEFT },
    band: [5, 6],
  },
}

// ---- 身子：9 行，字母是衣服上的颜色位 ----
// t 上衣，T 上衣暗面，G 上衣亮面，c 领口或内衣，a 领巾或蝴蝶结，o 围裙，O 围裙暗面，p 围裙口袋，
// b 腰带，q 裤子或裙子，Q 裤裙暗面，R 书皮，y 书上的字，s 手，J 皮肤暗面，W 白，g 浅灰，Y 金

type Outfit =
  | 'apron'
  | 'book'
  | 'cardigan'
  | 'jacket'
  | 'dress'
  | 'coat'
  | 'suit'
  | 'overalls'
  | 'tee'
  | 'hoodie'
  | 'robe'
  | 'clown'
  | 'space'
  | 'armor'
  | 'skeleton'
  | 'tiger_skirt'
  | 'bellyband'
  | 'kasaya'
  | 'bikini'
  | 'swim_trunks'
  | 'general'

interface Body {
  rows: Record<View, Rows>
  /** 侧面手臂：站着、往前摆、往后摆，[x, 相对身子顶部的行, 颜色]；抱着东西时不画 */
  arm?: readonly [Patch, Patch, Patch]
}

/** 侧面摆动的手臂：袖子是 top 色，短袖（t）第二格露出手臂；hand 是手（宇航服、盔甲、骷髅是手套色） */
const swingArm = (x: number, top: string, hand = 's'): Body['arm'] => {
  const mid = top === 't' ? hand : top
  return [
    [
      [x, 2, top],
      [x, 3, mid],
      [x, 4, hand],
    ],
    [
      [x + 1, 2, top],
      [x + 1, 3, mid],
      [x + 2, 4, hand],
    ],
    [
      [x, 2, top],
      [x - 1, 3, mid],
      [x - 1, 4, hand],
    ],
  ]
}
/** 夹克、西装的背面 */
const BACK_JACKET = mirror([
  '.......Kttt',
  '......Ktttt',
  '.....KTtttt',
  '.....KTtttt',
  '.....KsTTTT',
  '......Kqqqq',
  '......Kqqqq',
  '......Kqqqq',
  '......KKKKK',
])
const SKIRT_DOWN = ['......Kqqqq', '.....KqqQqq', '....KqqQqqq', '....KKKKKKK']
const SKIRT_SIDE = [
  '.......KqqqqqqK......',
  '......KqqqqQqqqK.....',
  '.....KqqqqqQqqqqK....',
  '.....KKKKKKKKKKKK....',
]

const BODIES: Record<Outfit, Body> = {
  apron: {
    rows: {
      down: mirror([
        '.......Ktaa',
        '......Kttoa',
        '.....Ktttoo',
        '.....Ksttop',
        '.....Ksbbbb',
        '......Kqooo',
        '......Kqooo',
        '......KqOOO',
        '......KKKKK',
      ]),
      up: mirror([
        '.......Kttt',
        '......Kottt',
        '.....Kttott',
        '.....Kstttt',
        '.....Ksbbbb',
        '......Kqqqq',
        '......Kqqqq',
        '......Kqqqq',
        '......KKKKK',
      ]),
      side: [
        '........KtttaK.......',
        '.......KttttaoK......',
        '.......KttttooK......',
        '.......KttttooK......',
        '.......KbbbbbbK......',
        '.......KqqqoooK......',
        '.......KqqqoooK......',
        '.......KqqqOOOK......',
        '.......KKKKKKKK......',
      ],
    },
    arm: swingArm(11, 't'),
  },
  book: {
    rows: {
      down: mirror([
        '.......Ktcc',
        '......KTttc',
        '.....KTtRRR',
        '.....KTsRyy',
        '.....KTtRRR',
        ...SKIRT_DOWN,
      ]),
      up: mirror([
        '.......Kttt',
        '......KTttt',
        '.....KTtttt',
        '.....KTtttt',
        '.....KTTTTT',
        ...SKIRT_DOWN,
      ]),
      side: [
        '........KttttcK......',
        '.......KttttTcK......',
        '.......KtttTsRRK.....',
        '.......KtttTsyRK.....',
        '.......KttttTRRK.....',
        ...SKIRT_SIDE,
      ],
    },
  },
  cardigan: {
    rows: {
      down: mirror([
        '.......Ktcc',
        '......KTttc',
        '.....KTttcc',
        '.....KTttcc',
        '.....KsTTTc',
        ...SKIRT_DOWN,
      ]),
      up: mirror([
        '.......Kttt',
        '......KTttt',
        '.....KTtttt',
        '.....KTtttt',
        '.....KsTTTT',
        ...SKIRT_DOWN,
      ]),
      side: [
        '........KttttcK......',
        '.......KttttTcK......',
        '.......KttttTcK......',
        '.......KttttTcK......',
        '.......KTTTTTTK......',
        ...SKIRT_SIDE,
      ],
    },
    arm: swingArm(11, 'T'),
  },
  jacket: {
    rows: {
      down: mirror([
        '.......Ktcc',
        '......Kttcc',
        '.....KTttcc',
        '.....KTttcc',
        '.....KsTTTc',
        '......Kqqqq',
        '......Kqqqq',
        '......KqqQq',
        '......KKKKK',
      ]),
      up: BACK_JACKET,
      side: [
        '........KttttcK......',
        '.......KtttttcK......',
        '.......KtttttcK......',
        '.......KtttttcK......',
        '.......KTTTTTTK......',
        '.......KqqqqqqK......',
        '.......KqqqqqqK......',
        '.......KqqqqQqK......',
        '.......KKKKKKKK......',
      ],
    },
    arm: swingArm(11, 'T'),
  },
  dress: {
    rows: {
      down: mirror([
        '.......Kcca',
        '......KTtta',
        '.....KTtttt',
        '.....Kstttt',
        '......KTTTT',
        '......Ktttt',
        '.....KttTtt',
        '....KtttTtt',
        '....KKKKKKK',
      ]),
      up: mirror([
        '.......Kttt',
        '......KTttt',
        '.....KTtttt',
        '.....KTtttt',
        '......KTTTT',
        '......Ktttt',
        '.....KttTtt',
        '....KtttTtt',
        '....KKKKKKK',
      ]),
      side: [
        '........KttcaK.......',
        '.......KtttttaK......',
        '.......KttttttK......',
        '.......KttttttK......',
        '.......KTTTTTTK......',
        '.......KttttttK......',
        '......KtttTtttK......',
        '.....KttttTttttK.....',
        '.....KKKKKKKKKKK.....',
      ],
    },
    arm: swingArm(11, 'T'),
  },
  coat: {
    rows: {
      down: mirror([
        '.......Ktcc',
        '......Kttcc',
        '.....KTttcc',
        '.....KTttcc',
        '.....KsTttc',
        '......Ktttc',
        '......Ktttc',
        '......KTTTc',
        '......KKKKK',
      ]),
      up: mirror([
        '.......Kttt',
        '......Ktttt',
        '.....KTtttt',
        '.....KTtttt',
        '.....KsTttt',
        '......Ktttt',
        '......Ktttt',
        '......KTTTT',
        '......KKKKK',
      ]),
      side: [
        '........KttttcK......',
        '.......KtttttcK......',
        '.......KtttttcK......',
        '.......KtttttcK......',
        '.......KtttttcK......',
        '.......KtttttcK......',
        '.......KtttttcK......',
        '.......KTTTTTTK......',
        '.......KKKKKKKK......',
      ],
    },
    arm: swingArm(11, 'T'),
  },
  /** 西装：白衬衫露一道 V 领，点缀色的领带 */
  suit: {
    rows: {
      down: mirror([
        '.......Ktca',
        '......KTtca',
        '.....KTttca',
        '.....KTttta',
        '.....KsTTTT',
        '......Kqqqq',
        '......Kqqqq',
        '......KqqQq',
        '......KKKKK',
      ]),
      up: BACK_JACKET,
      side: [
        '........KttttcK......',
        '.......KtttttaK......',
        '.......KtttttaK......',
        '.......KttttttK......',
        '.......KTTTTTTK......',
        '.......KqqqqqqK......',
        '.......KqqqqqqK......',
        '.......KqqqqQqK......',
        '.......KKKKKKKK......',
      ],
    },
    arm: swingArm(11, 'T'),
  },
  /** 背带裤：上衣是衬衫，下装色的背带和护胸，金色扣子 */
  overalls: {
    rows: {
      down: mirror([
        '.......Kqtt',
        '......Ktqtt',
        '.....KTtYqq',
        '.....KTtqQQ',
        '.....Ksqqqq',
        '......Kqqqq',
        '......Kqqqq',
        '......KqqQq',
        '......KKKKK',
      ]),
      up: mirror([
        '.......Kqtt',
        '......Ktqtt',
        '.....KTttqt',
        '.....KTtttq',
        '.....Ksqqqq',
        '......Kqqqq',
        '......Kqqqq',
        '......Kqqqq',
        '......KKKKK',
      ]),
      side: [
        '........KtqtttK......',
        '.......KttqtttK......',
        '.......KtttqYqK......',
        '.......KtttqqqK......',
        '.......KqqqqqqK......',
        '.......KqqqqqqK......',
        '.......KqqqqqqK......',
        '.......KqqqqQqK......',
        '.......KKKKKKKK......',
      ],
    },
    arm: swingArm(11, 't'),
  },
  /** 短袖短裤：露手臂和小腿 */
  tee: {
    rows: {
      down: mirror([
        '.......KtTT',
        '......Ktttt',
        '.....KTtttt',
        '.....Kstttt',
        '.....KsTTTT',
        '......Kqqqq',
        '......KqqQq',
        '.......KssK',
        '.......KssK',
      ]),
      up: mirror([
        '.......Kttt',
        '......Ktttt',
        '.....KTtttt',
        '.....Kstttt',
        '.....KsTTTT',
        '......Kqqqq',
        '......Kqqqq',
        '.......KssK',
        '.......KssK',
      ]),
      side: [
        '........KtttttK......',
        '.......KttttttK......',
        '.......KttttttK......',
        '.......KttttttK......',
        '.......KTTTTTTK......',
        '.......KqqqqqqK......',
        '.......KqqqqQqK......',
        '........KssssK.......',
        '........KssssK.......',
      ],
    },
    arm: swingArm(11, 't'),
  },
  /** 卫衣：胸前两根白抽绳、肚子上一个大口袋，背后垂着帽子 */
  hoodie: {
    rows: {
      down: mirror([
        '.......KTTT',
        '......Kttct',
        '.....KTttct',
        '.....KTtTTT',
        '.....KsTTTT',
        '......Kqqqq',
        '......Kqqqq',
        '......KqqQq',
        '......KKKKK',
      ]),
      up: mirror([
        '......KKTTT',
        '.....KTKTTT',
        '.....KTtKTT',
        '.....KTttKT',
        '.....KsTTTT',
        '......Kqqqq',
        '......Kqqqq',
        '......Kqqqq',
        '......KKKKK',
      ]),
      side: [
        '.....KKTtttTK........',
        '.....KTTKttttK.......',
        '......KKtttttK.......',
        '.......KtttTtK.......',
        '.......KTTTTTK.......',
        '.......KqqqqqqK......',
        '.......KqqqqqqK......',
        '.......KqqqqQqK......',
        '.......KKKKKKKK......',
      ],
    },
    arm: swingArm(11, 'T'),
  },
  /** 长袍：拖到脚面，宽袖子，腰上一道带子；巫师、道士、学者、天使都能穿 */
  robe: {
    rows: {
      down: mirror([
        '.......Ktcc',
        '......KTttc',
        '.....KTtttt',
        '....KTTtttt',
        '....KsKbbbb',
        '......Ktttt',
        '......KttTt',
        '.....KtttTt',
        '.....KKKKKK',
      ]),
      up: mirror([
        '.......Kttt',
        '......KTttt',
        '.....KTtttt',
        '....KTTtttt',
        '....KsKbbbb',
        '......Ktttt',
        '......Ktttt',
        '.....KttTtt',
        '.....KKKKKK',
      ]),
      side: [
        '........KttttcK......',
        '.......KtttttcK......',
        '.......KttttttK......',
        '.......KttttttK......',
        '.......KbbbbbbK......',
        '.......KttttttK......',
        '......KtttttTtK......',
        '......KttttttTtK.....',
        '......KKKKKKKKKK.....',
      ],
    },
    arm: swingArm(11, 'T'),
  },
  /** 小丑服：白色大花领，点缀色的绒球扣，左右两色、上下再对调 */
  clown: {
    rows: {
      down: [
        '.....KWWWWWWWWWK.....',
        '......KtttaqqqK......',
        '.....KTtttKqqqQK.....',
        '.....KTtttaqqqQK.....',
        '.....KsTTTKQQQsK.....',
        '......KqqqKtttK......',
        '......KqqqKtttK......',
        '.....KqqqQKtttTK.....',
        '.....KKKKKKKKKKK.....',
      ],
      up: [
        '.....KWWWWWWWWWK.....',
        '......KqqqqtttK......',
        '.....KQqqqqtttTK.....',
        '.....KQqqqqtttTK.....',
        '.....KsQQQQTTTsK.....',
        '......KttttqqqK......',
        '......KttttqqqK......',
        '.....KttttTqqqQK.....',
        '.....KKKKKKKKKKK.....',
      ],
      side: [
        '.......KWWWWWWWK.....',
        '.......KtttttaK......',
        '.......KttttttK......',
        '.......KtttttaK......',
        '.......KTTTTTTK......',
        '.......KqqqqqqK......',
        '.......KqqqqqqK......',
        '......KqqqqqqQK......',
        '......KKKKKKKKK......',
      ],
    },
    arm: swingArm(11, 'T'),
  },
  /** 宇航服：脖子上一圈头盔接环，胸前控制面板，背后生命维持背包；接环、腰带、手套都是浅灰 */
  space: {
    rows: {
      down: mirror([
        '.......Kggg',
        '......Ktttt',
        '.....KTtKKK',
        '.....KTtKaY',
        '.....KgTKKK',
        '......Kgggg',
        '......Kqqqq',
        '......KqqQq',
        '......KKKKK',
      ]),
      up: mirror([
        '.......Kggg',
        '......KtKKK',
        '.....KTtKgg',
        '.....KTtKgg',
        '.....KgTKKK',
        '......Kgggg',
        '......Kqqqq',
        '......Kqqqq',
        '......KKKKK',
      ]),
      side: [
        '.....KKKgggggK.......',
        '.....KggKttttK.......',
        '.....KggKtttKaK......',
        '.....KggKtttKYK......',
        '.....KKKTTTTTK.......',
        '.......KggggggK......',
        '.......KqqqqqqK......',
        '.......KqqqqQqK......',
        '.......KKKKKKKK......',
      ],
    },
    arm: swingArm(11, 'T', 'g'),
  },
  /** 盔甲：上衣色的金属，亮面是反光；护肩、胸甲中线、腰带、护手 */
  armor: {
    rows: {
      down: mirror([
        '.......KtGt',
        '....KKKtTtG',
        '....KGtKttG',
        '....KtTKTtG',
        '.....KtKbbb',
        '......KtTtT',
        '......Kqqqq',
        '......KqGqQ',
        '......KKKKK',
      ]),
      up: mirror([
        '.......Kttt',
        '....KKKtttt',
        '....KGtKttt',
        '....KtTKttt',
        '.....KtKbbb',
        '......KtTtT',
        '......Kqqqq',
        '......KqGqq',
        '......KKKKK',
      ]),
      side: [
        '........KtGttK.......',
        '......KKKtttGK.......',
        '.....KGttKttGK.......',
        '.....KtTTKttGK.......',
        '......KKKbbbbK.......',
        '.......KtTtTtK.......',
        '.......KqqqqqqK......',
        '.......KqGqqQqK......',
        '.......KKKKKKKK......',
      ],
    },
    arm: swingArm(11, 'T', 't'),
  },
  /** 骷髅服：上衣、下装色的连体衣上画白骨头 */
  skeleton: {
    rows: {
      down: [
        '.......KttWttK.......',
        '......KtWWWWWtK......',
        '.....KWtttWtttWK.....',
        '.....KWtWWWWWtWK.....',
        '.....KWttWWWttWK.....',
        '......KqWqqqWqK......',
        '......KqWqqqWqK......',
        '......KqWqQqWqK......',
        '......KKKKKKKKK......',
      ],
      up: [
        '.......KttWttK.......',
        '......KttWWWttK......',
        '.....KWttWWWttWK.....',
        '.....KWttWWWttWK.....',
        '.....KWtWWWWWtWK.....',
        '......KqWqqqWqK......',
        '......KqWqqqWqK......',
        '......KqWqqqWqK......',
        '......KKKKKKKKK......',
      ],
      side: [
        '........KtWttK.......',
        '.......KtWWWWtK......',
        '.......KtWtttWK......',
        '.......KtWWWWtK......',
        '.......KtWWWttK......',
        '.......KqqWqqqK......',
        '.......KqqWqqqK......',
        '.......KqqWqQqK......',
        '.......KKKKKKKK......',
      ],
    },
    arm: swingArm(11, 'W', 'W'),
  },
  /** 虎皮裙（孙悟空）：点缀色的围脖，背后是同色披风；腰带下一条虎皮短裙 */
  tiger_skirt: {
    rows: {
      down: mirror([
        '.......Kaaa',
        '......KTttt',
        '.....KTtttt',
        '.....KTtttt',
        '.....Ksbbbb',
        '.....KiIiiI',
        '....KiIiiIi',
        '......Kqqqq',
        '......KKKKK',
      ]),
      up: mirror([
        '.......Kaaa',
        '......Kaaaa',
        '.....KTaaaa',
        '.....KTaaaa',
        '.....Ksaaaa',
        '.....KiIiiI',
        '....KiIiiIi',
        '......Kqqqq',
        '......KKKKK',
      ]),
      side: [
        '........KaaaaaK......',
        '......KaKtttttK......',
        '......KaKtttttK......',
        '......KaKtttttK......',
        '......KaKbbbbbK......',
        '.......KiIiiIiK......',
        '......KiIiiIiiIK.....',
        '.......KqqqqqqK......',
        '.......KKKKKKKK......',
      ],
    },
    arm: swingArm(11, 'T'),
  },
  /** 肚兜（哪吒）：脖子上套着金色乾坤圈，胸前上衣色的菱形肚兜，两边飘着点缀色的混天绫 */
  bellyband: {
    rows: {
      down: mirror([
        '.......KYUY',
        '...a..Ksstt',
        '..a..Ksttt',
        '..a..Ksstt',
        '...a.Ksssst',
        '......Kqqqq',
        '......Kqqqq',
        '......KqqQq',
        '......KKKKK',
      ]),
      up: mirror([
        '.......KYUY',
        '...a..Kssss',
        '..a..Ksssst',
        '..a..Kssstt',
        '...a.Ksssss',
        '......Kqqqq',
        '......Kqqqq',
        '......Kqqqq',
        '......KKKKK',
      ]),
      side: [
        '........KYUYYK.......',
        '.....a.KsssstK.......',
        '....a..KssstttK......',
        '....a..KssstttK......',
        '.....a.KssssstK......',
        '.......KqqqqqqK......',
        '.......KqqqqqqK......',
        '.......KqqqqQqK......',
        '.......KKKKKKKK......',
      ],
    },
    arm: swingArm(11, 's'),
  },
  /** 袈裟（如来、唐僧）：斜披在一边肩上，另一边露出肩膀和手臂，金色的滚边，拖到脚面 */
  kasaya: {
    rows: {
      down: [
        '.......KssYttK.......',
        '......KsssYtttK......',
        '.....KsssYttttTK.....',
        '.....KssYtttttTK.....',
        '.....KsYttttttsK.....',
        '......KtttTtttK......',
        '.....KttttTttttK.....',
        '.....KYYYYYYYYYK.....',
        '.....KKKKKKKKKKK.....',
      ],
      up: [
        '.......KttYssK.......',
        '......KtttYsssK......',
        '.....KTttttYsssK.....',
        '.....KTtttttYssK.....',
        '.....KsttttttYsK.....',
        '......KtttTtttK......',
        '.....KttttTttttK.....',
        '.....KYYYYYYYYYK.....',
        '.....KKKKKKKKKKK.....',
      ],
      side: [
        '........KsssYK.......',
        '.......KsssYtK.......',
        '.......KssYttK.......',
        '.......KsYtttK.......',
        '.......KYttttK.......',
        '.......KttTtttK......',
        '......KtttTttttK.....',
        '......KYYYYYYYYK.....',
        '......KKKKKKKKKK.....',
      ],
    },
    arm: swingArm(11, 's'),
  },
  /** 比基尼：上下两件都是上衣色（画花纹也一起印上），露出手臂、腰和腿；手臂用皮肤暗面和身子分开 */
  bikini: {
    rows: {
      down: [
        '.......KststsK.......',
        '......KsttsttsK......',
        '.....KJsTtttTsJK.....',
        '.....KJsssssssJK.....',
        '.....KssssJssssK.....',
        '......KstttttsK......',
        '......KsstttssK......',
        '.......KssKssK.......',
        '.......KssKssK.......',
      ],
      up: [
        '.......KststsK.......',
        '......KsssssssK......',
        '.....KJtttttttJK.....',
        '.....KJsssssssJK.....',
        '.....KsssssssssK.....',
        '......KtttttttK......',
        '......KsstttssK......',
        '.......KssKssK.......',
        '.......KssKssK.......',
      ],
      side: [
        '........KssstsK......',
        '.......KsssstTK......',
        '.......KttttTTK......',
        '.......KssssssK......',
        '.......KssssssK......',
        '.......KttttttK......',
        '.......KsttttsK......',
        '........KssssK.......',
        '........KssssK.......',
      ],
    },
    arm: swingArm(11, 'J'),
  },
  /** 男式泳裤：光着上身，下装色的泳裤到大腿，腰上一根白抽绳 */
  swim_trunks: {
    rows: {
      down: [
        '.......KsssssK.......',
        '......KsssssssK......',
        '.....KJsJsssJsJK.....',
        '.....KJsssssssJK.....',
        '.....KssssJssssK.....',
        '......KqqqWqqqK......',
        '......KqqqqqqqK......',
        '......KqqQKQqqK......',
        '.......KssKssK.......',
      ],
      up: [
        '.......KsssssK.......',
        '......KsssssssK......',
        '.....KJsssssssJK.....',
        '.....KJsssJsssJK.....',
        '.....KsssssssssK.....',
        '......KqqqqqqqK......',
        '......KqqqqqqqK......',
        '......KqqQKQqqK......',
        '.......KssKssK.......',
      ],
      side: [
        '........KsssssK......',
        '.......KssssssK......',
        '.......KssssJsK......',
        '.......KssssssK......',
        '.......KssssssK......',
        '.......KqqqqWqK......',
        '.......KqqqqqqK......',
        '.......KqqqqQqK......',
        '........KssssK.......',
      ],
    },
    arm: swingArm(11, 'J'),
  },
  /** 将军甲（三国武将）：上衣色的铠甲，胸前一面金色护心镜，背后一领点缀色的披风垂到脚边 */
  general: {
    rows: {
      down: [
        '...K...KtGtGtK...K...',
        '..KaKKKtTtGtTtKKKaK..',
        '..KaKGtKtYYYtKtGKaK..',
        '..KaKtTKTYUYTKTtKaK..',
        '..Ka.KtKbbbbbKtK.aK..',
        '..Ka..KtTtTtTtK..aK..',
        '..Ka..KqqqqqqqK..aK..',
        '..Ka..KqGqQqGqK..aK..',
        '..KKK.KKKKKKKKK.KKK..',
      ],
      up: [
        '.......KaaaaaK.......',
        '....KKKaaaaaaaKKK....',
        '..KaaaaaaaaaaaaaaaK..',
        '..KaaaAaaaaaaaAaaaK..',
        '..KaaaAaaaaaaaAaaaK..',
        '..KaaaAaaaaaaaAaaaK..',
        '..KaaaAaaaaaaaAaaaK..',
        '..KaaaaaaaaaaaaaaaK..',
        '..KKKKKKKKKKKKKKKKK..',
      ],
      side: [
        '....Ka..KtGttK.......',
        '...KaaKKKtttGK.......',
        '...KaKGttKYYGK.......',
        '...KaKtTTKYUGK.......',
        '...KaaKKKbbbbK.......',
        '...KaaaKtTtTtK.......',
        '...KaaaKqqqqqqK......',
        '...KaaAKqGqqQqK......',
        '...KKKKKKKKKKKK......',
      ],
    },
    arm: swingArm(11, 'T', 't'),
  },
}

// ---- 手里拿的：兵器和羽扇 ----
// 正面、背面握在身边（右手；背面在另一边），杆子的上半截被大头挡住，兵器头露在头顶上方；
// 侧面竖着背在身后，只露出头顶上的兵器头和脚边的杆尾。羽扇拿在胸前，背面看不见。

type HeldItem = 'fan' | 'guandao' | 'snake_spear' | 'spear' | 'halberd' | 'golden_staff' | 'rake'

interface Held {
  /** 先于身子画：侧面背在身后 */
  back?: Partial<Record<View, Patch>>
  /** 身子之后、头之前：正面背面握在手边 */
  mid?: Partial<Record<View, Patch>>
  /** 最后画：兵器头、胸前的扇子 */
  front?: Partial<Record<View, Patch>>
}
/** 竖杆：从 top 画到脚底；c 是杆的颜色位 */
const pole = (x: number, top: number, c: string): Patch =>
  Array.from({ length: 28 - top }, (_, k) => [x, top + k, c] as const)
/** 镜像到背面：右手在画面另一边 */
const flip = (patch: Patch): Patch => patch.map(([x, y, ch]) => [20 - x, y, ch] as const)
/** 长兵器：杆子 c，兵器头 head（左上角放在 x0，从第 -3 行起） */
function polearm(c: string, x0: number, head: Rows): Held {
  const hand: Patch = [[5, 21, 's']]
  const down = [...pole(4, 2, c), ...hand]
  const top = overlay(x0, -3, head)
  return {
    back: { side: [...pole(8, 1, c), ...overlay(x0 + 4, -3, head)] },
    mid: { down, up: flip(down) },
    front: { down: top, up: flip(top) },
  }
}
const HELD: Record<HeldItem, Held> = {
  /** 羽扇（诸葛亮）：白羽毛扇面，金柄 */
  fan: {
    front: {
      down: overlay(2, 16, ['.KKK.', 'KWWWK', 'KWgWK', '.KWK.', '..Y..', '..Ys.']),
      side: overlay(13, 15, ['.KKK.', 'KWWWK', 'KWgWK', '.KWK.', '..Y..']),
    },
  },
  /** 青龙偃月刀（关羽）：杆上一口大弯刀，刀下系红缨 */
  guandao: polearm('D', 1, ['.KKK.', 'KMMMK', 'KMMK.', '.KMK.', '.rrD.', '..rD.']),
  /** 丈八蛇矛（张飞）：黑杆，弯弯曲曲的矛头 */
  snake_spear: polearm('n', 3, ['.K.', 'KM.', '.MK', 'KM.', 'rnr']),
  /** 长枪（赵云）：直直的枪头，红缨 */
  spear: polearm('D', 3, ['.K.', 'KMK', 'KMK', '.M.', 'rrr', '.r.']),
  /** 方天画戟（吕布）：枪尖两边各一片月牙 */
  halberd: polearm('r', 2, ['..K..', 'K.M.K', 'MKMKM', 'KMMMK', '..r..']),
  /** 金箍棒（孙悟空）：金色的棒子，两头红箍 */
  golden_staff: {
    back: { side: [...pole(8, -3, 'Y'), [8, -3, 'r'], [8, -2, 'r'], [8, 26, 'r'], [8, 27, 'r']] },
    mid: {
      down: [
        ...pole(4, -3, 'Y'),
        [4, -3, 'r'],
        [4, -2, 'r'],
        [4, 26, 'r'],
        [4, 27, 'r'],
        [5, 21, 's'],
      ],
      up: flip([
        ...pole(4, -3, 'Y'),
        [4, -3, 'r'],
        [4, -2, 'r'],
        [4, 26, 'r'],
        [4, 27, 'r'],
        [5, 21, 's'],
      ]),
    },
    front: {
      down: [
        [4, -3, 'r'],
        [4, -2, 'r'],
        [4, -1, 'Y'],
        [4, 0, 'Y'],
        [4, 1, 'Y'],
      ],
      up: flip([
        [4, -3, 'r'],
        [4, -2, 'r'],
        [4, -1, 'Y'],
        [4, 0, 'Y'],
        [4, 1, 'Y'],
      ]),
    },
  },
  /** 九齿钉耙（猪八戒）：杆顶一排耙齿 */
  rake: polearm('D', 1, ['KKKKKKK', 'MMMMMMM', 'M.M.M.M', '...D...']),
}

// ---- 每个人的长相 ----

export interface Look {
  hair: HairStyle
  outfit: Outfit
  /** 发色、瞳色、上衣、下装 */
  h: string
  /** 发梢颜色：有就从发根渐变到它 */
  tip?: string
  e: string
  t: string
  q: string
  /** 领口或内衣、领巾、围裙、腰带、发饰 */
  c?: string
  a?: string
  o?: string
  b?: string
  x?: string
  skin?: string
  /** 头巾颜色；有就把发型规定的两行头发换成头巾 */
  band?: string
  hat?: boolean
  ahoge?: boolean
  beard?: boolean
  clip?: boolean
  /** 草帽以外头上戴的；和草帽只能有一个 */
  headwear?: Headwear
  face?: FaceGear
  /** 络腮胡以外的胡子；和 beard 只能有一个 */
  beardStyle?: BeardStyle
  held?: HeldItem
  /** 捏人画的花纹：平铺在上衣（t）或下装（q）上 */
  pattern?: Pattern
}

/** 4×4 花纹：cells[行][列] 为真的格子换成花纹色，暗面跟着衣服一样压暗 */
interface Pattern {
  target: 't' | 'q'
  color: string
  cells: readonly (readonly boolean[])[]
}

const WHITE = CLOTH_WHITE
const CREAM = CLOTH_CREAM
const TAN = '#ecd4bc'

/** 内置村民，按模板编号；颜色从模板的标记色调亮 */
// prettier-ignore
const BUILTIN: Record<string, Look> = {
  builtin_ashu: { hair: 'short', ahoge: true, h: '#9a5e34', e: '#c07a30', outfit: 'apron', t: WHITE, a: '#e44a4e', o: '#58b078', b: '#c8a06a', q: '#7a6450' },
  builtin_xiaoning: { hair: 'bob', clip: true, x: '#e44a4e', h: '#3e3a4c', e: '#4c77da', outfit: 'book', t: '#52b8aa', c: WHITE, q: '#3c4a7a' },
  builtin_alan: { hair: 'bun', band: '#d8503e', x: '#e8c070', h: '#5a3626', e: '#9a5a2a', outfit: 'apron', t: WHITE, a: '#e8c070', o: '#d8883a', b: '#8a5a3a', q: '#5a4a40' },
  builtin_finn: { hair: 'split', h: '#d8b070', e: '#4c9a6a', outfit: 'apron', t: CREAM, a: '#6a4430', o: '#8a6a48', b: '#5a4030', q: '#3e3a40' },
  builtin_hazel: { hair: 'long', h: '#7a4a2e', e: '#6a8a4a', outfit: 'book', t: '#7e8c66', c: CREAM, q: '#5a4a3a' },
  builtin_iris: { hair: 'ponytail', x: '#9a80c0', h: '#4a3a5a', e: '#8a70b0', outfit: 'apron', t: '#e8e4ec', a: '#7a5a9a', o: '#aaa2b6', b: '#6a5a7a', q: '#5a5060' },
  builtin_june: { hair: 'bun', x: '#f0e0b0', h: '#c89060', e: '#8a5a2a', outfit: 'apron', t: WHITE, a: '#e0b040', o: '#7aa09a', b: '#5a7a74', q: '#6a5a4a' },
  builtin_laozhou: { hair: 'crop', band: '#e8e4d8', beard: true, skin: TAN, h: '#3a3430', e: '#5a4a3a', outfit: 'jacket', t: '#86826e', c: CREAM, q: '#4a4a40' },
  builtin_linxi: { hair: 'crop', skin: TAN, h: '#2e2a2a', e: '#4a6a8a', outfit: 'jacket', t: '#566a80', c: '#f0e8c8', q: '#3a4048' },
  builtin_luna: { hair: 'long', h: '#2a2e4a', e: '#e0c050', outfit: 'dress', t: '#4a5a88', c: WHITE, a: '#e0c050', q: '#3a3a44' },
  builtin_mira: { hair: 'short', clip: true, x: '#f0d060', h: '#d8804e', e: '#4a9a6a', outfit: 'dress', t: '#c88a8e', c: WHITE, a: '#f0d060', q: '#3a3a44' },
  builtin_noah: { hair: 'crop', beard: true, skin: TAN, h: '#4a3a30', e: '#5a4a3a', outfit: 'jacket', t: '#b07a5a', c: '#d8d0c0', q: '#4a4a50' },
  builtin_po: { hair: 'bun', x: '#8a6a4a', h: '#c0bab0', e: '#5a4a3a', outfit: 'coat', t: '#4a5a78', c: CREAM, q: '#3a3a44' },
  builtin_poppy: { hair: 'ponytail', band: '#5a9a4a', x: '#5a9a4a', h: '#d8a040', e: '#4a8a4a', outfit: 'apron', t: '#f4f0e0', a: '#5a9a4a', o: '#c8a868', b: '#8a6a3a', q: '#5a6a48' },
  builtin_reed: { hair: 'bob', h: '#2a2626', e: '#6a5a8a', outfit: 'jacket', t: '#7a8a7c', c: '#2e2e36', q: '#3a3a40' },
  builtin_sana: { hair: 'parted', h: '#3a2a24', e: '#4a6a9a', outfit: 'coat', t: '#f0ede4', c: '#6a90b0', q: '#4a5060' },
  builtin_stone: { hair: 'spiky', skin: TAN, h: '#3a2a1e', e: '#6a4a2a', outfit: 'jacket', t: '#c0b060', c: '#f0e8d0', q: '#6a5a40' },
  builtin_tan: { hair: 'short', hat: true, skin: TAN, h: '#2a2420', e: '#4a4a5a', outfit: 'jacket', t: '#56687a', c: '#e8e0c8', q: '#3a3a44' },
  builtin_theo: { hair: 'split', h: '#b88a5a', e: '#4a7a9a', outfit: 'apron', t: '#9aaebc', a: '#56687a', o: '#7a6450', b: '#4a3a2a', q: '#4a4a50' },
  builtin_tilla: { hair: 'twintail', x: '#e44a4e', h: '#6a4a3a', e: '#6a8ab0', outfit: 'dress', t: '#8a9bb0', c: WHITE, a: '#e44a4e', q: '#3a3a44' },
  builtin_xiaohe: { hair: 'parted', h: '#4a3a2a', e: '#8a6a2a', outfit: 'apron', t: '#f4f0e0', a: '#7ab070', o: '#c8b048', b: '#8a7a3a', q: '#6a5a40' },
  builtin_zhou: { hair: 'crop', beard: true, skin: TAN, h: '#c8c2b8', e: '#5a4a3a', outfit: 'jacket', t: '#56645a', c: CREAM, q: '#4a4a44' },
}

const HAIR_COLORS = [
  '#3e3a4c',
  '#2a2626',
  '#5a3626',
  '#9a5e34',
  '#c89060',
  '#d8a040',
  '#7a4a2e',
  '#c0bab0',
]
const EYE_COLORS = ['#4c77da', '#c07a30', '#4c9a6a', '#8a70b0', '#6a4a2a']
const CLOTH = [
  '#58b078',
  '#52b8aa',
  '#d8883a',
  '#c88a8e',
  '#4a5a88',
  '#86826e',
  '#b07a5a',
  '#7a8a7c',
  '#e8c070',
]
const BOTTOMS = ['#3c4a7a', '#5a4a3a', '#4a4a50', '#6a5a40', '#3a3a44']
/** 自定义村民不知道性别和年龄，只从男女都合适的发型和衣服里挑 */
const CUSTOM_HAIR: HairStyle[] = ['short', 'spiky', 'split', 'crop', 'bob', 'parted', 'ponytail']
const CUSTOM_OUTFIT: Outfit[] = ['apron', 'jacket', 'coat']

/** 捏人的长相（协议里的写法）→ 画法用的长相。没写的细节色交给 palette 的默认值；围裙缺省米白 */
function spriteLook(v: VillagerLook): Look {
  return {
    hair: v.hair,
    outfit: v.outfit,
    h: v.hair_color,
    tip: v.hair_tip,
    e: v.eye_color,
    skin: v.skin,
    t: v.top,
    q: v.bottom,
    a: v.accent,
    c: v.collar,
    o: v.apron ?? (v.outfit === 'apron' ? CREAM : undefined),
    b: v.belt,
    x: v.ornament,
    band: v.headband,
    hat: v.hat,
    ahoge: v.ahoge,
    clip: v.clip,
    beard: v.beard,
    headwear: v.headwear,
    face: v.face,
    beardStyle: v.beard_style,
    held: v.held,
    pattern: v.pattern && {
      target: v.pattern.on === 'bottom' ? 'q' : 't',
      color: v.pattern.color,
      cells: v.pattern.rows.map((row) => [...row].map((ch) => ch === '#')),
    },
  }
}

/** 画法用的长相 → 协议里的写法：捏人界面从预制村民或随机长相起步时用，画出来和原来一样 */
function villagerLook(l: Look): VillagerLook {
  const pattern = l.pattern
  return {
    hair: l.hair,
    outfit: l.outfit,
    hair_color: l.h,
    ...(l.tip ? { hair_tip: l.tip } : {}),
    eye_color: l.e,
    skin: l.skin ?? DEFAULT_SKIN,
    top: l.t,
    bottom: l.q,
    accent: l.a ?? l.x ?? DEFAULT_ACCENT,
    ...(l.c ? { collar: l.c } : {}),
    ...(l.o ? { apron: l.o } : {}),
    ...(l.b ? { belt: l.b } : {}),
    ...(l.x ? { ornament: l.x } : {}),
    ...(l.band ? { headband: l.band } : {}),
    ...(l.hat ? { hat: true } : {}),
    ...(l.ahoge ? { ahoge: true } : {}),
    ...(l.clip ? { clip: true } : {}),
    ...(l.beard ? { beard: true } : {}),
    ...(l.headwear ? { headwear: l.headwear } : {}),
    ...(l.face ? { face: l.face } : {}),
    ...(l.beardStyle ? { beard_style: l.beardStyle } : {}),
    ...(l.held ? { held: l.held } : {}),
    ...(pattern
      ? {
          pattern: {
            on: pattern.target === 'q' ? ('bottom' as const) : ('top' as const),
            color: pattern.color,
            rows: pattern.cells.map((row) => row.map((on) => (on ? '#' : '.')).join('')),
          },
        }
      : {}),
  }
}

export function lookOf(key: string): Look {
  const custom = decodeLookKey(key)
  if (custom) return spriteLook(custom)
  const known = BUILTIN[key] ?? avatarLook(key)
  if (known) return known
  let h = hashString(key)
  const pick = <T>(items: readonly T[]) => {
    const item = items[h % items.length]
    h = Math.floor(h / items.length) + 7919
    return item
  }
  return {
    hair: pick(CUSTOM_HAIR),
    h: pick(HAIR_COLORS),
    e: pick(EYE_COLORS),
    outfit: pick(CUSTOM_OUTFIT),
    t: pick(CLOTH),
    q: pick(BOTTOMS),
    c: CREAM,
    a: '#e44a4e',
    o: pick(CLOTH),
    b: '#8a6a44',
    x: '#e44a4e',
  }
}

const SHADE = '#2a2230'
const DEFAULT_SKIN = '#f6ece0'
const DEFAULT_ACCENT = '#e44a4e'
/** 暗面压暗的比例：上衣、下装 */
const TOP_SHADE = 0.2
const BOTTOM_SHADE = 0.25
export function palette(look: Look): Record<string, string> {
  const o = look.o ?? look.t
  return {
    K: '#141014',
    s: look.skin ?? DEFAULT_SKIN,
    j: '#f0b0a6',
    e: look.e,
    h: look.h,
    H: mixHex(look.h, '#ffffff', 0.3),
    L: mixHex(look.h, '#ffffff', 0.55),
    x: look.x ?? look.a ?? DEFAULT_ACCENT,
    t: look.t,
    T: mixHex(look.t, SHADE, TOP_SHADE),
    c: look.c ?? WHITE,
    a: look.a ?? look.t,
    o,
    O: mixHex(o, SHADE, 0.22),
    p: mixHex(o, '#ffffff', 0.35),
    b: look.b ?? mixHex(look.q, '#ffffff', 0.3),
    q: look.q,
    Q: mixHex(look.q, SHADE, BOTTOM_SHADE),
    R: '#e44a4e',
    y: '#fff0d0',
    w: look.band ?? WHITE,
    z: '#e6c77c',
    Z: '#c8a45a',
    X: '#c0503a',
    S: mixHex(look.skin ?? DEFAULT_SKIN, '#ffffff', 0.5),
    v: mixHex(look.skin ?? DEFAULT_SKIN, '#4a4440', 0.3),
    G: mixHex(look.t, '#ffffff', 0.4),
    W: WHITE,
    g: '#a8aeb6',
    Y: '#e8b83c',
    U: '#b8862a',
    n: '#2a2a34',
    N: '#4e4e5c',
    r: '#e03a3a',
    i: '#e8963a',
    I: '#4a2c1a',
    P: '#e48c8a',
    J: mixHex(look.skin ?? DEFAULT_SKIN, SHADE, 0.16),
    A: mixHex(look.a ?? look.t, SHADE, 0.25),
    E: mixHex(look.x ?? look.a ?? DEFAULT_ACCENT, '#ffffff', 0.35),
    D: '#8a5a32',
    M: '#c8d0d8',
    F: '#c8783a',
  }
}

// ---- 分层合成 ----
// 一帧由一笔笔格子叠成，分腿、身子、头三组，每一笔记下属于哪一层、哪一组，颜色按调色板、渐变发和花纹
// 当场定好。动画按组挪（呼吸时头沉一格，走路时身子起伏、头晚一拍，转身时头先转），垂下来的头发和辫子
// 按离发根远近有一个软度，随风和走路摆（见 villagerRig.ts）。头像和捏人界面也走这里，叠好之后和立牌一样
// 过一遍精修（villagerRefine.ts）。

/** 一笔属于哪一层，按画的先后排 */
export type Layer =
  | 'legs'
  | 'heldBack'
  | 'body'
  | 'arm'
  | 'heldMid'
  | 'hairBack'
  | 'gearBack'
  | 'head'
  | 'hairExtra'
  | 'ahoge'
  | 'beard'
  | 'clip'
  | 'face'
  | 'hat'
  | 'heldFront'

/** 一笔：帧坐标 (x, y)、颜色位 ch 和定好的颜色。group 0 是腿，1 是身子（连手里拿的），
 *  2 是头（连头发、帽子、脸上戴的）；flex 是随风摆的软度，0 不动、1 最软 */
export interface Stroke {
  x: number
  y: number
  ch: string
  color: string
  layer: Layer
  group: 0 | 1 | 2
  flex: number
}

/** 腿和手臂怎么摆。腿是 2 格宽的一块 [x, 顶行, 行数]（人物坐标），上面是裤子的颜色、最下面一行是鞋；
 *  toes 是另加的单格（侧面迈步时后脚的脚尖）；
 *  arm 是侧面的手臂：0 垂下、1 往前、2 往后，null 不画（两手在胸前拿着东西） */
export interface Stance {
  legs: readonly (readonly [number, number, number])[]
  toes?: readonly (readonly [number, number])[]
  arm: 0 | 1 | 2 | null
}

/** 原来的四帧走路：0 站、1 迈一只脚、2 站、3 迈另一只脚。迈步时身子和头上移一格（bob 为 -1），
 *  着地的腿长一格、抬起的腿短一格。头像和捏人界面用 */
function walk4(view: View, f: number): Stance & { bob: number } {
  const step = f % 2 === 1
  const bob = step ? -1 : 0
  if (view !== 'side') {
    const legs = [
      [f === 3 ? 11 : 8, step ? 25 : 26, step ? 3 : 2],
      [f === 3 ? 8 : 11, step ? 25 : 26, 2],
    ] as const
    return { legs, arm: 0, bob }
  }
  if (!step)
    return {
      legs: [
        [10, 26, 2],
        [11, 26, 2],
      ],
      arm: 0,
      bob,
    }
  return {
    legs: [
      [12, 25, 3],
      [9, 25, 2],
    ],
    toes: [[8, 26]],
    arm: f === 1 ? 1 : 2,
    bob,
  }
}

/** 头的朝向：转身时头先转过去，和身子不同；mirror 表示头和身子一个朝左一个朝右（朝左的帧最后整张翻过来） */
export interface HeadTurn {
  view: View
  mirror: boolean
}

/** 按画的先后叠成一张字母格（帧坐标），只看头那几层：找眼睛、认头发 */
function layOut(strokes: readonly Stroke[]) {
  const g: (string | null)[][] = Array.from({ length: FRAME_H }, () => Array(FRAME_W).fill(null))
  for (const s of strokes)
    if (s.x >= 0 && s.y >= 0 && s.x < FRAME_W && s.y < FRAME_H) g[s.y][s.x] = s.ch
  return g
}

/** 垂下来的头发有多软：0 不动，1 最软。辫子、马尾按离发根的远近，长发、齐耳短发只算下巴以下那截
 *  （脸两边的头发一摆就和脸脱开）；发髻、爆炸头、竖起来的冠不动。坐标是人物坐标 */
function flexOf(layer: Layer, ch: string, y: number, look: Look) {
  // 呆毛只有两格高，摆多了就飞了：最多一格
  if (layer === 'ahoge') return 0.34
  if (!'hHLKxw'.includes(ch) || STIFF.has(look.hair)) return 0
  const k = (v: number) => Math.max(0, Math.min(1, v))
  if (layer === 'hairExtra') return k((y - 6) / 12)
  if (layer === 'hairBack') return k((y - 10) / 12)
  if (layer === 'head' && y >= 17) return Math.min(1, 0.45 + (y - 17) / 8)
  return 0
}
const STIFF = new Set<HairStyle>(['afro', 'bun', 'twin_buns', 'curls', 'mohawk', 'spiky'])

/** 一帧的笔画：先腿，再身子、头，最后手里拿的兵器头和扇子。view 是身子的朝向，turn 是头另外的朝向 */
export function sketch(
  look: Look,
  pal: Record<string, string>,
  view: View,
  stance: Stance,
  turn?: HeadTurn
): Stroke[] {
  const out: Stroke[] = []
  const put = (x: number, y: number, ch: string, layer: Layer, group: Stroke['group']) => {
    if (ch !== '.') out.push({ x: x + OX, y: y + OY, ch, color: '', layer, group, flex: 0 })
  }
  const stamp = (rows: Rows, y0: number, layer: Layer, group: Stroke['group']) =>
    rows.forEach((row, j) => [...row].forEach((ch, i) => put(i, y0 + j, ch, layer, group)))
  const apply = (patch: Patch | undefined, layer: Layer, group: Stroke['group'], dy = 0) => {
    for (const [x, y, ch] of patch ?? []) put(x, y + dy, ch, layer, group)
  }
  // 腿：上面是裤子的颜色，最下面一行是鞋（和立牌一样，见 villagerRig.ts）
  for (const [x, top, n] of stance.legs)
    for (let y = top; y < top + n; y++) {
      const ch = y === top + n - 1 ? 'K' : 'q'
      put(x, y, ch, 'legs', 0)
      put(x + 1, y, ch, 'legs', 0)
    }
  for (const [x, y] of stance.toes ?? []) put(x, y, 'K', 'legs', 0)
  const held = look.held ? HELD[look.held] : undefined
  apply(held?.back?.[view], 'heldBack', 1)
  const body = BODIES[look.outfit]
  stamp(body.rows[view], 17, 'body', 1)
  if (view === 'side' && body.arm && stance.arm !== null) apply(body.arm[stance.arm], 'arm', 1, 17)
  apply(held?.mid?.[view], 'heldMid', 1)
  // 头按自己的朝向画（转身时头先转）
  const hv = turn?.view ?? view
  const from = out.length
  const hair = HAIR[look.hair]
  const gear = look.headwear ? HEADWEAR[look.headwear] : undefined
  // 戴帽子时头顶 0～4 行被帽子盖住：头发只从第 5 行画起，发髻、呆毛不画，垂到帽檐下的辫子照画
  const covered = !!look.hat || !!gear?.covers
  const below = (patch?: Patch) => (covered ? patch?.filter(([, y]) => y >= 5) : patch)
  apply(below(hair.back?.[hv]), 'hairBack', 2)
  if (gear?.back) apply(gear.back, 'gearBack', 2)
  stamp(covered ? hair.rows[hv].slice(5) : hair.rows[hv], covered ? 5 : 0, 'head', 2)
  apply(below(hair.extra?.[hv]), 'hairExtra', 2)
  if (look.ahoge && !covered) apply(AHOGE[hv], 'ahoge', 2)
  // 渐变只染头发：这时候画上的 h/H/L 才是头发，后面的胡子、猴脸毛色不算
  const mask = layOut(out.slice(from)).map((row) => row.map((ch) => !!ch && 'hHL'.includes(ch)))
  const recolor = (row: number, chars: string, to: string) => {
    for (let i = from; i < out.length; i++)
      if (out[i].y === row + OY && chars.includes(out[i].ch)) out[i].ch = to
  }
  if (look.band) for (const row of hair.band) recolor(row, 'hHL', 'w')
  if (look.beard) apply(BEARD[hv], 'beard', 2)
  if (look.beardStyle) apply(BEARDS[look.beardStyle][hv], 'beard', 2)
  if (look.clip) apply(CLIP[hv], 'clip', 2)
  if (gear?.band) hair.band.forEach((row, i) => recolor(row, 'hHLsSv', gear.band![i]))
  if (look.face) {
    const g = layOut(out.slice(from))
    const at = (x: number, y: number) => g[y + OY]?.[x + OX] ?? null
    apply(faceGear(look.face, hv, eyesOf(g), at), 'face', 2)
  }
  if (look.hat) apply(HAT[hv], 'hat', 2)
  else if (gear) apply(gear.patch[hv], 'hat', 2)
  // 记下哪些笔是头发（渐变按它染）、垂下来的头发有多软，再把头翻到身子的朝向
  const hairy = new Set<Stroke>()
  for (let i = from; i < out.length; i++) {
    const s = out[i]
    if (mask[s.y]?.[s.x] && 'hHL'.includes(s.ch)) hairy.add(s)
    s.flex = flexOf(s.layer, s.ch, s.y - OY, look)
    if (turn?.mirror) s.x = FRAME_W - 1 - s.x
  }
  apply(held?.front?.[view], 'heldFront', 1)
  paintStrokes(look, pal, out, hairy)
  return out
}

/** 给每一笔定颜色：花纹、渐变发、调色板依次看 */
function paintStrokes(
  look: Look,
  pal: Record<string, string>,
  strokes: Stroke[],
  hairy: Set<Stroke>
) {
  const tipped = tipColors(look, strokes, hairy)
  const pattern = look.pattern
  const shade =
    pattern && mixHex(pattern.color, SHADE, pattern.target === 't' ? TOP_SHADE : BOTTOM_SHADE)
  for (const s of strokes)
    s.color =
      // 腿不上花纹：立牌的腿是另画的纯色，两边要一样
      (pattern && shade && s.layer !== 'legs' && patternAt(pattern, shade, s.ch, s.x, s.y)) ||
      (hairy.has(s) ? tipped?.(s.y, s.ch) : undefined) ||
      (pal[s.ch] ?? '#ff00ff')
}

/** 渐变发从发根往发梢分几档 */
const TIP_STEPS = 3
/** 发根这一段不变色（按头发的高度算） */
const TIP_FROM = 0.3
/** 渐变发每一笔的颜色：从发根到发梢分档混进发梢色，高光跟着变；往上竖的发型发梢在上面。
 *  发根发梢的范围按最后叠出来、最上面一笔还是头发的格子算。没有发梢色时返回 undefined */
function tipColors(look: Look, strokes: readonly Stroke[], hairy: Set<Stroke>) {
  const tip = look.tip
  if (!tip) return undefined
  const shown = new Map<number, Stroke>()
  for (const s of strokes)
    if (s.x >= 0 && s.y >= 0 && s.x < FRAME_W && s.y < FRAME_H) shown.set(s.y * FRAME_W + s.x, s)
  let top = FRAME_H,
    bottom = -1
  for (const s of shown.values()) {
    if (!hairy.has(s)) continue
    top = Math.min(top, s.y)
    bottom = Math.max(bottom, s.y)
  }
  if (bottom <= top) return undefined
  const up = HAIR[look.hair].up
  const shades = Array.from({ length: TIP_STEPS + 1 }, (_, k) => {
    const h = mixHex(look.h, tip, k / TIP_STEPS)
    return { h, H: mixHex(h, '#ffffff', 0.3), L: mixHex(h, '#ffffff', 0.55) } as Record<
      string,
      string
    >
  })
  // 被盖住的笔（摆头发时会露出来）可能在范围外，按最近的一头算
  return (y: number, ch: string) => {
    const t = Math.min(1, (up ? bottom - y : y - top) / (bottom - top))
    return shades[Math.round(Math.max(0, (t - TIP_FROM) / (1 - TIP_FROM)) * TIP_STEPS)][ch]
  }
}

/** 这一帧里眼睛那一格（人物坐标，已含迈步的起伏）；侧面再从眼睛往前找到脸前沿的描边 */
function eyesOf(g: (string | null)[][]): Eyes {
  const at: [number, number][] = []
  for (let y = 0; y < FRAME_H; y++)
    for (let x = 0; x < FRAME_W; x++) if (g[y][x] === 'e') at.push([x - OX, y - OY])
  const [ex, ey] = at[0] ?? [0, 0]
  let front = ex + 1
  while (front + OX < FRAME_W - 1 && g[ey + OY]?.[front + OX] !== 'K') front++
  return { at, front }
}

/** 花纹落在这一格的颜色；不是花纹格返回 undefined。坐标按身子算（迈步时身子上移一格，花纹跟着走） */
function patternAt(p: Pattern, shade: string, ch: string, x: number, y: number) {
  if (ch !== p.target && ch !== p.target.toUpperCase()) return undefined
  if (!p.cells[((y % 4) + 4) % 4]?.[((x % 4) + 4) % 4]) return undefined
  return ch === p.target ? p.color : shade
}

/** 头像和捏人界面画的一帧：站姿和原来的四帧走路，flip 是朝左时整张翻过来 */
/** '#rrggbb' ↔ 小端 RGBA 像素（精修按像素算） */
function pixelOf(hex: string) {
  const n = parseInt(hex.slice(1), 16)
  return (0xff000000 | ((n & 0xff) << 16) | (n & 0xff00) | ((n >> 16) & 0xff)) >>> 0
}
function hexOf(px: number) {
  const n = ((px & 0xff) << 16) | (px & 0xff00) | ((px >> 16) & 0xff)
  return '#' + n.toString(16).padStart(6, '0')
}
const FRAME_PX = new Uint32Array(FRAME_W * FRAME_H),
  FRAME_CH = new Uint8Array(FRAME_W * FRAME_H),
  FRAME_SCRATCH = new Uint32Array(FRAME_W * FRAME_H)

/** 画一帧：叠好笔画、朝左的翻过来，再过一遍精修（和镇上的立牌同一个函数），最后一格格填上 */
function drawFrame(
  ctx: CanvasRenderingContext2D,
  ox: number,
  oy: number,
  look: Look,
  pal: Record<string, string>,
  view: View,
  f: number,
  flip: boolean
) {
  const stance = walk4(view, f)
  FRAME_PX.fill(0)
  FRAME_CH.fill(0)
  for (const s of sketch(look, pal, view, stance)) {
    const y = s.group ? s.y + stance.bob : s.y
    if (s.x < 0 || y < 0 || s.x >= FRAME_W || y >= FRAME_H) continue
    const i = y * FRAME_W + (flip ? FRAME_W - 1 - s.x : s.x)
    FRAME_PX[i] = pixelOf(s.color)
    FRAME_CH[i] = s.ch.charCodeAt(0)
  }
  refineVillager(FRAME_PX, FRAME_CH, FRAME_W, FRAME_H, FRAME_SCRATCH, deepOf(pixelOf(pal.q)))
  for (let y = 0; y < FRAME_H; y++)
    for (let x = 0; x < FRAME_W; x++) {
      const px = FRAME_PX[y * FRAME_W + x]
      if (!px) continue
      ctx.fillStyle = hexOf(px)
      ctx.fillRect(ox + x, oy + y, 1, 1)
    }
}

/** 头像：正面站姿的头和肩，23×23 格放大 4 倍；从头顶上方 3 行裁起（大葱头的叶尖裁掉一截） */
const CROP = { x: 1, y: OY - 3, size: 23 }
const ZOOM = 4
const portraits = new Map<string, string>()
export function villagerPortrait(key: string): string {
  let url = portraits.get(key)
  if (url) return url
  const look = lookOf(key)
  const frame = document.createElement('canvas')
  frame.width = FRAME_W
  frame.height = FRAME_H
  drawFrame(frame.getContext('2d')!, 0, 0, look, palette(look), 'down', 0, false)
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = CROP.size * ZOOM
  const ctx = canvas.getContext('2d')!
  ctx.imageSmoothingEnabled = false
  ctx.drawImage(frame, CROP.x, CROP.y, CROP.size, CROP.size, 0, 0, canvas.width, canvas.height)
  url = canvas.toDataURL()
  portraits.set(key, url)
  return url
}

/** 捏人界面用的画法：按长相画任意朝向的一帧，读出编号对应的长相 */
export const villagerArt: VillagerArt = {
  frame: [FRAME_W, FRAME_H],
  drawFrame(ctx, look, dir, frame, x, y) {
    const l = spriteLook(look)
    const view: View = dir === 'down' || dir === 'up' ? dir : 'side'
    drawFrame(ctx, x, y, l, palette(l), view, frame, dir === 'left')
  },
  lookOf: (key) => villagerLook(lookOf(key)),
}

/** 化身可挑的外观：颜色和正面头像 */
export function avatarLookOptions(): AvatarLook[] {
  return AVATAR_COLORS.map((color) => ({ color, portrait: villagerPortrait(avatarLookKey(color)) }))
}
