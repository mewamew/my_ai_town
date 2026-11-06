// 选曲：此刻放哪一格的曲子。从上往下找——剧情 → 玩法 → 天气 → 时段，哪一层有事、这一格又有曲子
// 就放它；时段按世界分，同世界缺曲先借相邻时段（清晨借白天、夜晚借黄昏），再借小镇。
// 播放器按结果的紧要程度决定立刻换（变紧张、出了事）还是等这首放完（变平静）。
// 这里只有纯函数和类型，测试直接载入。
import type { NeedBand, NeedKind, RosterMember } from '../protocol'
import type { WeatherKind } from '../weather/types'
import type { MusicTrack } from './catalog'

/** 曲子按世界分：海岸小镇、荒岛（海岸乡镇走野外或环岛小径）、末日废土、冰封雪镇 */
export type MusicWorld = 'town' | 'island' | 'wasteland' | 'frozen'
export type TimeSlot = 'dawn' | 'day' | 'dusk' | 'night' | 'sleep'
type StoryCell =
  'story/finale' | 'story/murder' | 'story/mourning' | 'story/critical' | 'story/scarcity'
type WeatherCell =
  'weather/storm' | 'weather/snow' | 'weather/rain' | 'weather/clearing' | 'weather/overcast'
/** 玩法自己的格子，次序和判断在 gameModes/ 里 */
type ModeCell = 'tide/winner' | 'tide/final' | 'tide/rising' | 'tide/announced'
/** 一格曲子：在什么场合放 */
export type MusicCell =
  'ui/title' | StoryCell | ModeCell | WeatherCell | `${MusicWorld}/${TimeSlot}`
/** 出了事的那一下：刚有人去世、遇害，雨刚停。立刻换上，只放一首就回去 */
export type OnceCell = 'story/murder' | 'story/mourning' | 'weather/clearing'

export interface MusicChoice {
  cell: MusicCell
  tracks: readonly MusicTrack[]
  /** 越大越紧：剧情 > 玩法 > 天气 > 时段，同一层按上面的次序 */
  urgency: number
  once: boolean
}

export interface MusicSituation {
  clock: string
  weather?: WeatherKind
  world: MusicWorld
  /** 设定里的「剧情音乐」；关掉后剧情这一层整层不看 */
  storyMusic: boolean
  mood: RosterMood
  /** 还没放过的「只放一首」 */
  once: ReadonlySet<OnceCell>
  /** 开着的玩法：此刻要放的格子（null 交给天气和时段）、它由紧到松的全部格子，以及有人死时是否只响短提示 */
  mode?: { cell: MusicCell | null; order: readonly MusicCell[]; quietDeaths: boolean }
}

/** 名册里居民的处境；关掉的生理项不算 */
export interface RosterMood {
  /** 都去世了（至少有过一位居民） */
  finale: boolean
  /** 有人「健康危重」 */
  critical: boolean
  /** 活着的人里至少一半「很饿」或「很渴」 */
  scarcity: boolean
  living: number
  total: number
}

const ONCE: readonly MusicCell[] = ['story/murder', 'story/mourning', 'weather/clearing']
const BORROW: Partial<Record<TimeSlot, TimeSlot>> = { dawn: 'day', night: 'dusk' }
const RAINY: readonly (WeatherKind | undefined)[] = ['light_rain', 'rain', 'heavy_rain']
const STORY_LAYER = 300
const MODE_LAYER = 200
const WEATHER_LAYER = 100

/** 「第 3 天 06:05」里的钟点；认不出时按正午 */
export function hourOf(clock: string): number {
  const match = clock.match(/(?:^|\D)([01]?\d|2[0-3]):[0-5]\d(?:\D|$)/)
  return match ? Number(match[1]) : 12
}

/** 清晨 05–08、白天 08–17、黄昏 17–20、夜晚 20–23、深夜 23–05 */
export function slotAt(hour: number): TimeSlot {
  if (hour >= 23 || hour < 5) return 'sleep'
  if (hour < 8) return 'dawn'
  if (hour < 17) return 'day'
  return hour < 20 ? 'dusk' : 'night'
}

export function isRainy(weather?: WeatherKind): boolean {
  return weather === 'thunderstorm' || RAINY.includes(weather)
}

/** 地图风格包和小径 → 哪个世界的曲子 */
export function musicWorldOf(theme: string, settlement?: string): MusicWorld {
  if (theme === 'wasteland' || theme === 'frozen') return theme
  return settlement === 'wild' || settlement === 'ring' ? 'island' : 'town'
}

/** 环境声：下雨、雷暴时放雨声，深夜放白噪声 */
export function ambienceAt(clock: string, weather?: WeatherKind): 'rain' | 'sleep' | null {
  if (isRainy(weather)) return 'rain'
  return slotAt(hourOf(clock)) === 'sleep' ? 'sleep' : null
}

export function rosterMood(residents: readonly Pick<RosterMember, 'body' | 'needs'>[]): RosterMood {
  const living = residents.filter((member) => member.body?.life !== 'dead')
  const band = (member: Pick<RosterMember, 'needs'>, kind: NeedKind): NeedBand | undefined =>
    member.needs?.find((need) => need.kind === kind)?.band
  const low = (value?: NeedBand) => value === 'urgent' || value === 'collapse'
  const short = living.filter(
    (member) => low(band(member, 'fullness')) || low(band(member, 'water'))
  ).length
  return {
    finale: residents.length > 0 && living.length === 0,
    critical: living.some((member) => band(member, 'health') === 'collapse'),
    scarcity: living.length > 0 && short * 2 >= living.length,
    living: living.length,
    total: residents.length,
  }
}

/** 首页：「小镇序曲」和「晨集小镇」轮流 */
export function titleChoice(library: readonly MusicTrack[]): MusicChoice {
  return { cell: 'ui/title', tracks: tracksIn(library, 'ui/title'), urgency: 0, once: false }
}

export function chooseMusic(s: MusicSituation, library: readonly MusicTrack[]): MusicChoice {
  const slot = slotAt(hourOf(s.clock))
  /** 一层里由紧到松的候选：false 是此刻没这回事；第一个有曲子的就是这一层的结果 */
  const layer = (base: number, order: readonly (MusicCell | false)[]): MusicChoice | null => {
    for (const [index, cell] of order.entries()) {
      if (!cell) continue
      const tracks = tracksIn(library, cell)
      if (tracks.length)
        return { cell, tracks, urgency: base + order.length - index, once: ONCE.includes(cell) }
    }
    return null
  }
  const quietDeaths = s.mode?.quietDeaths ?? false
  const story =
    s.storyMusic &&
    layer(STORY_LAYER, [
      s.mood.finale && 'story/finale',
      !quietDeaths && s.once.has('story/murder') && 'story/murder',
      !quietDeaths && s.once.has('story/mourning') && 'story/mourning',
      s.mood.critical && 'story/critical',
      // 深夜照旧放深夜曲
      s.mood.scarcity && slot !== 'sleep' && 'story/scarcity',
    ])
  if (story) return story
  const mode = s.mode
  if (mode?.cell) {
    const tracks = tracksIn(library, mode.cell)
    if (tracks.length)
      return {
        cell: mode.cell,
        tracks,
        urgency: MODE_LAYER + mode.order.length - mode.order.indexOf(mode.cell),
        once: false,
      }
  }
  const w = s.weather
  const weather = layer(WEATHER_LAYER, [
    w === 'thunderstorm' && 'weather/storm',
    // 雪镇里下雪是常态，照旧放雪镇的曲
    w === 'snow' && s.world !== 'frozen' && 'weather/snow',
    RAINY.includes(w) && 'weather/rain',
    s.once.has('weather/clearing') && 'weather/clearing',
    // 深夜不分阴晴
    w === 'overcast' && slot !== 'sleep' && 'weather/overcast',
  ])
  if (weather) return weather
  const borrow = BORROW[slot]
  const time = layer(0, [
    `${s.world}/${slot}`,
    !!borrow && `${s.world}/${borrow}`,
    `town/${slot}`,
    !!borrow && `town/${borrow}`,
  ])
  return time
    ? { ...time, urgency: 0 }
    : { cell: 'town/day', tracks: tracksIn(library, 'town/day'), urgency: 0, once: false }
}

/**
 * 正在放 current 这一格、离放完还剩 left 秒时选曲变成了 next：
 * 出了事、变紧张立刻换；变平静等这首放完；只是时段变了，快放完的放完，不然淡过去。
 */
export function switchNow(
  next: Pick<MusicChoice, 'cell' | 'urgency' | 'once'>,
  current: Pick<MusicChoice, 'cell' | 'urgency'>,
  left: number
): boolean {
  if (next.cell === current.cell) return false
  if (next.once) return true
  if (next.urgency !== current.urgency) return next.urgency > current.urgency
  return left > 20
}

function tracksIn(library: readonly MusicTrack[], cell: MusicCell): readonly MusicTrack[] {
  return library.filter((track) => track.cells.includes(cell))
}
