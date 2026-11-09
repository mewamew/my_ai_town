// 头顶的漫画符号：整格的小图画在立牌贴图里，和人一起受光、一起虚化，没有半透明的糊边。
// 每人同一时间最多一个，挂在头的右上角（只高出头顶三格，名字在它上面）；冒出来时整格跳一下，
// 消失时按有序抖动一格格淡掉。只跟着名册里有数据的状态冒：被吓到「！」、想不出做什么「？」、
// 演奏和天好时散步「♪」、需求告急「汗」、邀请被拒「怒」、有了新目标「灯泡」、聊完和被治好「心」、
// 在反思「…」、饿了「咕」。等模型、额度用完这类系统状态仍只用名字旁的文字。

export type Sign = '!' | '?' | 'note' | 'sweat' | 'anger' | 'bulb' | 'heart' | 'dots' | 'growl'

/** 符号的样子：K 描边，r 红，B 蓝，Y 金，W 白，l 浅蓝，g 灰，P 粉，i 橙；最高 8 行 */
export const SIGNS: Record<Sign, readonly string[]> = {
  '!': ['.KKK.', 'KrrrK', 'KrrrK', '.KrK.', '.KrK.', '..K..', '.KrK.', '.KKK.'],
  '?': ['.KKKK.', 'KBBBBK', 'KBKKBK', '..KBBK', '..KBK.', '..KK..', '..KBK.', '..KK..'],
  note: ['...KKK', '..KYYK', '..KYK.', '..KYK.', '.KKYK.', 'KYYYK.', 'KYYK..', '.KK...'],
  sweat: ['..K..', '.KlK.', 'KlWlK', 'KlllK', '.KKK.'],
  anger: ['.KK.KK.', 'KrrKrrK', 'KrK.KrK', '.K...K.', 'KrK.KrK', 'KrrKrrK', '.KK.KK.'],
  bulb: ['.KKK.', 'KYYYK', 'KYWYK', 'KYYYK', '.KYK.', '.KgK.', '..K..'],
  heart: ['.KK.KK.', 'KPPKPPK', 'KPWPPPK', 'KPPPPPK', '.KPPPK.', '..KPK..', '...K...'],
  dots: ['.KKKKKKK.', 'KWWWWWWWK', 'KWKWKWKWK', 'KWWWWWWWK', '.KKKKKKK.', '.KK......', 'K........'],
  growl: ['.K...K.', 'KiK.KiK', 'i.KiK.i', '...K...'],
}

/** 玩法给某人头顶挂的常驻标记（大逃杀里拿着信号弹的人）：挂在头的左上角，和右上角冒的符号错开；
 *  躺着时挂在身子上方。rows 的写法同上面的符号，最高 8 行；name 用来比对要不要重画 */
export interface Badge {
  name: string
  rows: readonly string[]
}

/** 一个冒出来的符号：从 at 到 until（毫秒） */
export interface Shown {
  sign: Sign
  at: number
  until: number
}

/** 先后：同时有好几个时只冒最要紧的一个 */
export const SIGN_RANK: Record<Sign, number> = {
  '!': 9,
  anger: 8,
  heart: 7,
  bulb: 6,
  dots: 5,
  '?': 4,
  growl: 3,
  sweat: 2,
  note: 1,
}

/** 一直在的状态（反思、想不出、饿、需求告急）隔一阵冒一次：亮 on 毫秒、歇 off 毫秒，各人错开 */
export const CYCLE: Partial<Record<Sign, [number, number]>> = {
  dots: [3000, 2500],
  '?': [2800, 5200],
  growl: [1600, 8400],
  sweat: [2000, 7000],
}

/** 冒出来时跳一下、最后 400 毫秒淡掉：返回往下挪几格和还剩几成（减少动画时不跳不淡） */
export function signMotion(s: Shown, now: number, lively: boolean) {
  if (!lively) return { dy: 0, alpha: 1 }
  const k = now - s.at
  const dy = k < 80 ? -2 : k < 160 ? 1 : 0
  const left = s.until - now
  return { dy, alpha: left < 400 ? Math.max(0, left / 400) : 1 }
}
