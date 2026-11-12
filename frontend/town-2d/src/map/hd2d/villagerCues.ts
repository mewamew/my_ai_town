import type { AgentState, NeedBand, NeedKind, RosterMember } from 'town-shared/protocol'
import type { Body, Mood } from './villagerActing'
import type { Sign } from './villagerSigns'

// 名册里和表演有关的那几项：render.ts 从名册摘出来交给立牌，只换个演法——
// 动作词演成姿势，聊天演成面对面说话，需求和身体状况演成表情。表情只跟着有数据的状态走，
// 不从模型写的文字里猜情绪；没有数据就是平常脸。被婉拒的邀请和新定的目标，名册里各带一个记号
// （整份目标和互动是角色卡细节，不随名册来）。

/** 一个人此刻的线索 */
export interface Cue {
  /** 在用道具时的动作词（verb_kind 为 prop），以及坐下、躺下 */
  verb?: string
  /** 正在牵手、依偎、拥抱：动作词 */
  touch?: string
  /** 在聊天：这场聊天的编号，轮到不轮到这个人说 */
  chat?: string
  speaking?: boolean
  /** 刚说出口的一句：编号（换了就重新开口）和台词 */
  speech?: { key: string; text: string }
  /** 四项需求的档位 */
  needs?: Partial<Record<NeedKind, NeedBand>>
  /** 身体状况：种类和严重程度（1～3） */
  conditions?: { kind: 'injury' | 'illness' | 'poison'; severity: number }[]
  /** 倒下了（还活着，但不能自己决定或不能走动）；死了 */
  down?: boolean
  dead?: boolean
  /** 生命记录里刚发生的治愈、复活、神力（游戏分钟和种类） */
  revived?: { at: number; kind: 'cure' | 'revive' | 'miracle' }
  /** 村民的模型状态：反思、想不出要做什么 */
  state?: AgentState
  /** 村民库模板编号：内置村民的喜好和小动作按它查 */
  persona?: string
  /** 在屋里（淋不着雨、落不上雪，进屋抖掉积雪） */
  indoors?: boolean
  /** 最近一次自己发起、被对方婉拒的邀请；最近定下的目标（换了就冒符号） */
  declined?: string
  goal?: string
}

/** 换了姿势的停留：名册里是停留，按动作词摆坐、躺的姿势 */
const POSED_STAYS = new Set(['坐下', '躺下'])
/** 亲近的几种互动（名册里的动作词） */
const TOUCHES = new Set(['牵手', '依偎', '拥抱'])

/** 台词多旧以内还算刚说的（游戏分钟）：和聊天气泡一样；治愈、复活多久以内还演一下 */
const FRESH_SPEECH = 2
const FRESH_RECOVERY = 3

/** 从名册里摘线索；minutes 是名册的游戏时间 */
export function cueOf(
  member: RosterMember,
  minutes: number,
  persona?: string,
  indoors?: boolean
): Cue {
  const body = member.body
  const needs: Cue['needs'] = {}
  for (const n of member.needs ?? []) needs[n.kind] = n.band
  const recover = body?.history
    .filter((e) => e.kind === 'cure' || e.kind === 'revive' || e.kind === 'miracle')
    .at(-1)
  const recent = recover && minutes - recover.at <= FRESH_RECOVERY ? recover : undefined
  const speech = member.speech
  const agent = member.resident_agent
  const goal = agent?.latest_goal
  const alive = body?.life !== 'dead'
  return {
    // 道具动作和换了姿势的停留（坐下、躺下）按动作词摆姿势
    verb: member.verb_kind === 'prop' || POSED_STAYS.has(member.verb) ? member.verb : undefined,
    // 正在牵手、依偎、拥抱：头上冒爱心
    touch: member.verb_kind === 'interaction' && TOUCHES.has(member.verb) ? member.verb : undefined,
    chat: member.chat?.id,
    speaking: !!member.chat && member.chat.turn === member.id,
    speech:
      speech && (member.chat || minutes - speech.at <= FRESH_SPEECH)
        ? { key: `${speech.chat_id}:${speech.seq}`, text: speech.text }
        : undefined,
    needs,
    conditions: body?.conditions.map((c) => ({ kind: c.kind, severity: c.severity })),
    down: !!body && alive && (!body.can_decide || !body.can_move),
    dead: !alive,
    revived: recent && { at: recent.at, kind: recent.kind as 'cure' | 'revive' | 'miracle' },
    state: agent?.state,
    persona,
    indoors,
    declined: agent?.declined_invitation,
    goal: goal && `${goal.id}:${goal.updated_at}`,
  }
}

/** 身体状况演成什么：伤、病、毒按轻重，饿了，倒下了，死了 */
export function bodyOf(cue: Cue): Body {
  const level = (kind: 'injury' | 'illness' | 'poison') =>
    cue.conditions?.find((c) => c.kind === kind)?.severity ?? 0
  return {
    injury: level('injury'),
    illness: level('illness'),
    poison: level('poison'),
    hungry: low(cue.needs?.fullness),
    down: !!cue.down && !cue.dead,
    dead: !!cue.dead,
  }
}

/** 一直在的状态隔一阵冒的符号：在反思「…」、想不出要做什么「？」、饿了「咕」、亲近时「心」、需求告急「汗」 */
export function standingSigns(cue: Cue, hot: boolean): Sign[] {
  if (cue.dead) return []
  const out: Sign[] = []
  if (cue.state === 'reflecting') out.push('dots')
  if (cue.state === 'undecided') out.push('?')
  if (low(cue.needs?.fullness)) out.push('growl')
  if (cue.touch) out.push('heart')
  const urgent = Object.values(cue.needs ?? {}).some((b) => b === 'urgent')
  if (urgent || (hot && !cue.indoors)) out.push('sweat')
  return out
}

const low = (band?: NeedBand) => band === 'urgent' || band === 'collapse'

/** 一直挂在脸上的心情：疼（健康很低、病得重）、困（精力很低）、低头（身上有轻的病痛、饿渴到撑不住） */
export function moodOf(cue: Cue): Mood {
  const conditions = cue.conditions ?? []
  if (low(cue.needs?.health) || conditions.some((c) => c.severity >= 2)) return 'pained'
  if (low(cue.needs?.energy)) return 'sleepy'
  if (conditions.length || cue.needs?.fullness === 'collapse' || cue.needs?.water === 'collapse')
    return 'down'
  return 'normal'
}

/** 内置村民喜欢的话题（按村民库里的兴趣、性格写）：聊天时说到、听到就眼睛发亮。
 *  捏出来的村民前端拿不到兴趣，不演 */
const LIKES: Record<string, RegExp> = {
  builtin_alan: /做饭|吃|菜|饭|食堂|市集|请客/,
  builtin_ashu: /公告|新鲜|见闻|消息|新来/,
  builtin_finn: /咖啡|豆子|拉花/,
  builtin_hazel: /书|诗|小说|推荐/,
  builtin_iris: /陶|釉|窑|器皿|泥/,
  builtin_june: /面包|麦|面团|配方|老面|烤/,
  builtin_laozhou: /木|工序|材料|做完/,
  builtin_linxi: /河|散步|风景|走走/,
  builtin_luna: /星|天文|夜空|月亮|望远镜/,
  builtin_mira: /花/,
  builtin_noah: /车|发动机|引擎|扳手/,
  builtin_po: /船|渡口|从前|以前|掌故/,
  builtin_poppy: /苗|温室|植物|堆肥|种子/,
  builtin_reed: /曲|歌|琴|调子|小调|演出|音乐|哼/,
  builtin_sana: /药|病|方子|看诊/,
  builtin_stone: /羊|石|水漂|连环画/,
  builtin_tan: /船|摆渡|水色|对岸/,
  builtin_theo: /木|刨|手艺|出师/,
  builtin_tilla: /石头|星|邮票|望远镜/,
  builtin_xiaohe: /花|植物|苗/,
  builtin_xiaoning: /档案|记录|书/,
  builtin_zhou: /船|龙骨|手艺|修/,
}

/** 这句话说到了这个人喜欢的话题 */
export function likes(persona: string | undefined, text: string) {
  return !!persona && !!LIKES[persona]?.test(text)
}

/** 站着没事做时的个性小动作：按姿势演的（看书、喝咖啡、织毛线……），或者跟着拍子点头、蹦一下、
 *  左看右看、蹲下捡东西、招手、笑、打哈欠、抬头看星星 */
export type Quirk =
  | 'read'
  | 'drink'
  | 'knit'
  | 'write'
  | 'tend'
  | 'busy'
  | 'craft'
  | 'cook'
  | 'gaze'
  | 'medic'
  | 'beat'
  | 'hop'
  | 'scan'
  | 'pickup'
  | 'wave'
  | 'smile'
  | 'yawn'
  | 'stargaze'

/** 内置村民的小动作（按村民库里的职业和性格写）：阿岚见人招呼，里德跟着拍子点头，阿婆针线不停，
 *  露娜白天打哈欠、夜里抬头看星星，苔拉左看右看、蹲下捡石头，石头蹦蹦跳跳……；周伯走得慢 */
const QUIRKS: Record<string, readonly Quirk[]> = {
  builtin_alan: ['wave', 'smile'],
  builtin_ashu: ['scan', 'read'],
  builtin_finn: ['drink'],
  builtin_hazel: ['read'],
  builtin_iris: ['busy'],
  builtin_june: ['cook'],
  builtin_laozhou: ['craft'],
  builtin_linxi: ['gaze', 'scan'],
  builtin_luna: ['yawn'],
  builtin_mira: ['smile', 'tend'],
  builtin_noah: ['busy'],
  builtin_po: ['knit'],
  builtin_poppy: ['tend'],
  builtin_reed: ['beat'],
  builtin_sana: ['medic'],
  builtin_stone: ['hop', 'scan'],
  builtin_tan: ['gaze'],
  builtin_theo: ['craft', 'busy'],
  builtin_tilla: ['scan', 'pickup'],
  builtin_xiaohe: ['tend'],
  builtin_xiaoning: ['write'],
  builtin_zhou: ['gaze'],
}

/** 走路比别人慢的人 */
export const SLOW_WALKERS = new Set(['builtin_zhou'])

/** 这个人的小动作：内置村民查表，露娜夜里换成看星星；捏出来的按外形挑（穿着书的看书，系围裙的手上忙，
 *  别的左看右看） */
export function quirksOf(
  persona: string | undefined,
  outfit: string,
  night: boolean
): readonly Quirk[] {
  if (persona === 'builtin_luna' && night) return ['stargaze']
  const known = persona && QUIRKS[persona]
  if (known) return known
  return outfit === 'book' ? ['read', 'scan'] : outfit === 'apron' ? ['busy', 'scan'] : ['scan']
}
