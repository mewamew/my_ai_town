import type { Stance } from './villagerSprite'

// 做事的姿势：名册里在用道具时的动作词归成几类姿势，每类给出腿怎么放、身子低几格、两手和手里的
// 道具小图（按拍子换帧）。道具小图和村民同一套字母、同一种描边：K 描边，W 白，g 灰，R 红书皮，
// m、d 木头，u 饭菜，k 火苗，l 水，B 蓝，Y 金，M 铁，s 手。坐标是人物坐标（头 0～16 行，身子 17～25 行）。
// 都按正面画：在用道具的人站在道具跟前、面朝镜头。

export type PoseKind =
  | 'stand'
  | 'eat'
  | 'drink'
  | 'read'
  | 'write'
  | 'tend'
  | 'medic'
  | 'craft'
  | 'cook'
  | 'wash'
  | 'carry'
  | 'buy'
  | 'rest'
  | 'sleep'
  | 'play'
  | 'water'
  | 'post'
  | 'gaze'
  | 'knit'
  | 'busy'
  | 'belly'
  | 'cover'
  | 'sitGround'
  | 'lie'

/** 动作词里有这些字就归到这一类，从上往下先对上的算。道具定义里的 121 个动作有 117 个落在专门的姿势上
 *  （吃喝、整理照看、阅读、看病、做工、睡觉歇脚、书写、买卖、搬运，外加演奏、浇花、张贴、眺望），
 *  对不上的（议事、摸鱼、翻找、持刀）用通用的「手上忙」；玩家建的道具也按字归类 */
const VERBS: [PoseKind, RegExp][] = [
  ['sleep', /睡/],
  ['rest', /歇|避雨|晒太阳/],
  ['wash', /洗/],
  ['cook', /面团|烘烤|面包|做饭|冲咖啡|烹|炒/],
  ['carry', /搬|木料|木头|捡|采|堆/],
  ['craft', /组装|打磨|制作|修理|器物|零件|搭|收集器|点燃|篝火/],
  ['drink', /喝|饮/],
  ['eat', /吃|点心|干粮|罐头|椰子/],
  ['medic', /包扎|治疗|解毒|诊|接受检查|取药|复苏/],
  ['read', /读|阅|书籍|借还|档案|资料|字帖|公告栏/],
  ['write', /写|填表|文书|货单|记录|电脑/],
  ['buy', /购买|买|点单|办事/],
  ['play', /演奏|曲目|弹|唱|合成器|掌机/],
  ['water', /浇/],
  ['post', /张贴|叫卖/],
  ['gaze', /眺望|观察|登船/],
  ['tend', /整理|清点|看顾|照看|接待|检查|摊位|递|取|归还|分拣|成品|渔|园具|工具/],
]

/** 动作词 → 姿势类；对不上的用「手上忙」 */
export function poseOf(verb: string): PoseKind {
  for (const [kind, re] of VERBS) if (re.test(verb)) return kind
  return 'busy'
}

type Cells = readonly (readonly [number, number, string])[]
const cells = (x0: number, y0: number, rows: readonly string[]): Cells =>
  rows.flatMap((row, j) =>
    [...row].flatMap((ch, i) => (ch === '.' ? [] : [[x0 + i, y0 + j, ch] as const]))
  )

/** 一种姿势的一帧：腿、身子和头往下挪几格，侧面手臂；back 画在身子后面，front 画在最上面；
 *  eyes 是做这件事时的眼神（看书往下看，睡觉闭眼）；lie 是整个人躺下；fx 是冒出来的小东西 */
export interface Posed {
  stance: Stance
  bodyDy: number
  headDy: number
  back?: Cells
  front?: Cells
  eyes?: 'down' | 'closed' | 'half'
  mouth?: 'open' | 'o'
  lie?: boolean
  fx?: 'steam' | 'sparks' | 'zzz' | 'notes' | 'drops'
  /** 小东西从哪儿冒（人物坐标）：碗口、锤子落点、琴边、壶嘴 */
  fxAt?: readonly [number, number]
}

const STAND: Stance = {
  legs: [
    [8, 26, 2],
    [11, 26, 2],
  ],
  arm: null,
}
/** 盘腿坐在地上：身子低两格，两只脚往两边伸出来 */
const SIT_GROUND: Stance = {
  legs: [
    [5, 27, 1],
    [14, 27, 1],
  ],
  arm: null,
}

/** 两手在胸前：遮住身子两边原来垂着的手（站姿的手画在身子的第 20、21 行） */
const hands = (lx: number, rx: number, y: number): Cells => [
  [lx, y, 's'],
  [rx, y, 's'],
]

/** 每类姿势每一拍的样子；phase 是拍子（各类自己的节奏，见 BEAT_MS） */
export function posed(kind: PoseKind, phase: number): Posed {
  const a = phase % 2 === 1
  switch (kind) {
    case 'read':
      // 两手捧着一本摊开的书，隔一会儿翻一页
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 1,
        eyes: 'down',
        front: [
          ...cells(5, 19, [
            'KKKKKKKKKKK',
            a ? 'KWWWWgKKKK.' : 'KWWWWgWWWWK',
            'KWggWgWggWK',
            'KWWWWgWWWWK',
            'KRRRRRRRRRK',
          ]),
          ...hands(4, 16, 21),
        ],
      }
    case 'write':
      // 胸前一张纸，笔尖来回动
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 1,
        eyes: 'down',
        front: [
          ...cells(5, 20, ['KKKKKKKKK', 'KWWWWWWWK', 'KWggWgWWK', 'KWWWWWWWK', 'KKKKKKKKK']),
          ...cells(a ? 9 : 11, 18, ['.n', 'n.', 's.']),
          [4, 22, 's'],
        ],
      }
    case 'eat':
      // 一手端碗，一手拿筷子一口一口往嘴边送；碗里冒热气
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 0,
        mouth: a ? 'open' : undefined,
        fx: 'steam',
        fxAt: [10, 18],
        front: [
          ...cells(6, 19, ['KKKKKKKK', 'KuuuuuuK', '.KWWWWK.', '..KKKK..']),
          ...(a
            ? cells(12, 14, ['m.', 'm.', 'm.', 'm.', 'ms'])
            : cells(13, 16, ['m.', 'm.', 'm.', 'ms'])),
          [5, 20, 's'],
        ],
      }
    case 'drink':
      // 端着杯子，每隔一会儿举到嘴边喝一口
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 0,
        fx: a ? undefined : 'steam',
        fxAt: [13, 18],
        front: a
          ? [...cells(9, 14, ['KKK', 'KWK', 'sWs']), [6, 21, 's']]
          : [...cells(12, 19, ['KKK', 'KWK', 'KWK', '.s.']), [6, 21, 's']],
      }
    case 'carry':
      // 两手抱着一只木箱
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 0,
        front: [
          ...cells(4, 18, [
            'KKKKKKKKKKKKK',
            'KmmmmmmmmmmmK',
            'KdmmmmmmmmmdK',
            'KmmmmmmmmmmmK',
            'KKKKKKKKKKKKK',
          ]),
          ...hands(3, 17, 20),
        ],
      }
    case 'craft':
      // 右手抡锤子：举起、落下，落下时溅火星
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: a ? 1 : 0,
        eyes: 'down',
        fx: a ? 'sparks' : undefined,
        fxAt: [12, 21],
        front: a
          ? [...cells(11, 21, ['KKK...', 'KMKmms']), [6, 21, 's']]
          : [...cells(15, 12, ['KKK', 'KMK', 'KKK', '.m.', '.m.', '.m.', '.s.']), [6, 21, 's']],
      }
    case 'cook':
      // 揉面、翻锅：两手在胸前一推一拉，冒热气
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 1,
        eyes: 'down',
        fx: 'steam',
        fxAt: [10, 18],
        front: [
          ...cells(5, 19, ['KKKKKKKKKK', 'KuuuuuuuuK', '.KMMMMMMK.', '..KKKKKK..']),
          ...hands(a ? 4 : 5, a ? 14 : 15, 20),
        ],
      }
    case 'wash':
      // 两手在盆里搓，溅起水点
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 1,
        eyes: 'down',
        fx: 'drops',
        fxAt: [10, 19],
        front: [
          ...cells(5, 20, ['KKKKKKKKKKK', 'KlllllllllK', '.KBBBBBBBK.', '..KKKKKKK..']),
          ...hands(a ? 7 : 8, a ? 12 : 13, 20),
        ],
      }
    case 'tend':
      // 低头摆弄手里的小东西（花束、货品、渔网）
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 1,
        eyes: 'down',
        front: [
          ...cells(a ? 7 : 8, 19, ['.P.Y.', 'PxYxP', '.KgK.', '..g..']),
          ...hands(a ? 6 : 7, a ? 12 : 13, 21),
        ],
      }
    case 'medic':
      // 拿着白药箱、缠绷带
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 1,
        eyes: 'down',
        front: [
          ...cells(6, 20, ['KKKKKKKK', 'KWWrrWWK', 'KWrrrrWK', 'KWWrrWWK', 'KKKKKKKK']),
          ...hands(5, 14, 21),
          ...(a ? cells(15, 18, ['W', 'W']) : []),
        ],
      }
    case 'buy':
      // 递过去一枚铜钱，手里提着纸袋
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 0,
        front: [
          ...(a ? cells(15, 19, ['KK', 'KY', 's.']) : cells(14, 20, ['KK', 'KY', 's.'])),
          ...cells(3, 21, ['.KKK.', 'KmmmK', 'KdmdK', 'KmmmK', '.KKK.']),
          [5, 21, 's'],
        ],
      }
    case 'play':
      // 抱着琴拨弦，冒音符
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: a ? 1 : 0,
        fx: 'notes',
        fxAt: [16, 12],
        front: [
          ...cells(5, 19, [
            '...KKK...',
            '..KmmmK..',
            '.KmmKmmKK',
            'KmmKKKmmK',
            'KmmmKmmK.',
            '.KmmmmK..',
            '..KKKK...',
          ]),
          ...cells(14, 17, ['KK', 'Kd', 'd.']),
          ...hands(a ? 10 : 9, 15, 20),
        ],
      }
    case 'water':
      // 提着水壶浇水，水一滴滴落下
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 1,
        eyes: 'down',
        fx: 'drops',
        fxAt: [20, 24],
        front: [
          ...cells(13, 20, ['.KKKK...', 'KBBBBKKK', 'KBBBBK.l', '.KKKK..l', '......l.']),
          [12, 21, 's'],
        ],
      }
    case 'post':
      // 踮脚把一张纸往上按
      return {
        stance: {
          legs: [
            [8, 25, 2],
            [11, 25, 2],
          ],
          arm: null,
        },
        bodyDy: -1,
        headDy: -1,
        front: cells(18, 2, [
          'KKKKK',
          'KWWWK',
          'KWgWK',
          'KWWWK',
          'KKKKK',
          '.Ks..',
          '.Kt..',
          '.Kt..',
          '.Kt..',
          '.Kt..',
          '.Kt..',
          '.Kt..',
          '.Kt..',
          '.Kt..',
          '.Kt..',
        ]),
      }
    case 'gaze':
      // 手搭凉棚往远处看
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 0,
        eyes: 'half',
        front: cells(14, 8, [
          'KKKKKK.',
          'ssssssK',
          '.....tK',
          '.....tK',
          '.....tK',
          '.....tK',
          '.....tK',
          '.....tK',
          '.....tK',
          '.....tK',
        ]),
      }
    case 'knit':
      // 两根针一上一下，脚边一团毛线
      return {
        stance: SIT_GROUND,
        bodyDy: 2,
        headDy: 3,
        eyes: 'down',
        front: [
          ...cells(
            6,
            21,
            a
              ? ['g...g..', '.g.g...', '..x....', '.sxxs..']
              : ['..g...g', '...g.g.', '....x..', '..sxxs.']
          ),
          ...cells(15, 26, ['.KK.', 'KxxK', '.KK.']),
        ],
      }
    case 'busy':
      // 两手在胸前忙个不停
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 1,
        eyes: 'down',
        front: [...hands(a ? 6 : 7, a ? 13 : 14, a ? 21 : 20), [a ? 9 : 10, 21, 'g']],
      }
    case 'belly':
      // 饿了：两手捂着肚子
      return { stance: STAND, bodyDy: 0, headDy: 1, front: cells(7, 22, ['sKsKs']) }
    case 'cover':
      // 没带伞淋雨：两手抱头
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 1,
        front: [...cells(4, 1, ['.KKK.', 'KsssK']), ...cells(12, 1, ['.KKK.', 'KsssK'])],
      }
    case 'rest':
    case 'sitGround':
      return { stance: SIT_GROUND, bodyDy: 2, headDy: 2 + (a ? 1 : 0), eyes: 'half' }
    case 'sleep':
    case 'lie':
      return {
        stance: STAND,
        bodyDy: 0,
        headDy: 0,
        eyes: 'closed',
        lie: true,
        fx: kind === 'sleep' ? 'zzz' : undefined,
      }
    default:
      return { stance: STAND, bodyDy: 0, headDy: 0 }
  }
}

/** 每类姿势一拍多长（毫秒）：吃一口、翻一页、抡一锤 */
export const BEAT_MS: Partial<Record<PoseKind, number>> = {
  read: 3800,
  write: 260,
  eat: 700,
  drink: 2400,
  craft: 380,
  cook: 450,
  wash: 300,
  tend: 900,
  medic: 800,
  buy: 1200,
  play: 320,
  water: 600,
  knit: 330,
  busy: 420,
  rest: 2600,
}

/** 拿着东西站着的姿势：脚边、手边多画的东西不跟着走路，走起来就换回走路的样子 */
export function holdsWhileWalking(kind: PoseKind) {
  return kind === 'carry'
}
