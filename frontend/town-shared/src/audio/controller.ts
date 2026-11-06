import type { GameModeView, RosterMember, ServerMsg } from '../protocol'
import type { WeatherKind } from '../weather/types'
import { MUSIC_TRACKS } from './catalog'
import { createEffectsController, type MovementSoundState } from './effects'
import { GAME_MODE_MUSIC, type GameModeMusic } from './gameModes'
import { createMusicController } from './music'
import { readSwitch, saveSwitch } from './preference'
import { chooseMusic, isRainy, rosterMood, type MusicWorld, type OnceCell } from './scene'

export type GameAudio = ReturnType<typeof createGameAudio>
type RosterMsg = Extract<ServerMsg, { type: 'roster' }>

const STORY_KEY = 'ai-town:story-music'
/** 「只放一首」被更紧要的曲子盖住时，过这么久就作废，事后不补放 */
const ONCE_TTL_MS = 3 * 60_000
/** 雨停后这么多游戏分钟内进镇，也算「雨刚停」 */
const CLEARING_MINUTES = 30

/** 首页没有剧情可放：首页「设定」只改这个开关，进小镇后按它挑曲 */
export const storyMusicPreference = {
  enabled: () => readSwitch(STORY_KEY),
  toggle: () => saveSwitch(STORY_KEY, !readSwitch(STORY_KEY)),
}

/**
 * 游戏里的声音：名册每一拍把时钟、天气、玩法和居民的处境交给选曲，
 * 世界日志里的去世、遇害响短提示并放一首哀悼或疑云。
 * world 是地图风格定下的曲子世界，进镇时定一次。
 */
export function createGameAudio(
  musicButton: HTMLButtonElement,
  effectsButton: HTMLButtonElement,
  world: MusicWorld = 'town'
) {
  /** 还没放的「只放一首」→ 作废的时刻 */
  const once = new Map<OnceCell, number>()
  const music = createMusicController(musicButton, {
    onStart: (cell) => {
      if (once.delete(cell as OnceCell)) resolve()
    },
  })
  const effects = createEffectsController(effectsButton)
  let story = readSwitch(STORY_KEY)
  let clock = '12:00'
  let weather: WeatherKind | undefined
  let transition = -1
  let mood = rosterMood([])
  let mode: GameModeView | undefined

  const resolve = () => {
    const now = performance.now()
    for (const [cell, until] of once) if (until <= now) once.delete(cell)
    const modeMusic = mode && (GAME_MODE_MUSIC[mode.kind] as GameModeMusic)
    music.setChoice(
      chooseMusic(
        {
          clock,
          weather,
          world,
          storyMusic: story,
          mood,
          once: new Set(once.keys()),
          mode: mode &&
            modeMusic && {
              cell: modeMusic.cell(mode, mood),
              order: modeMusic.order,
              quietDeaths: modeMusic.quietDeaths,
            },
        },
        MUSIC_TRACKS
      )
    )
  }
  /** 记下一件「只放一首」的事；正在放这一格就算放过了 */
  const remember = (cell: OnceCell) => {
    if (music.playingCell() !== cell) once.set(cell, performance.now() + ONCE_TTL_MS)
  }

  return {
    /** 顶栏与设定中心「声音与按键」页共用的开关 */
    music: { enabled: music.enabled, toggle: music.toggle },
    effects: { enabled: effects.enabled, toggle: effects.toggle },
    story: {
      enabled: () => story,
      toggle() {
        story = !story
        saveSwitch(STORY_KEY, story)
        resolve()
      },
    },
    /** 名册每一拍；名册可以只带时钟，没有新的天气字段时保留上次的天气 */
    roster(msg: RosterMsg, residents: readonly RosterMember[]) {
      clock = msg.clock
      const environment = msg.environment
      if (environment) {
        weather = environment.kind
        const last = environment.last_transition
        if (last && last.id !== transition) {
          transition = last.id
          const cleared = last.to === 'clear' || last.to === 'overcast'
          if (isRainy(last.from) && cleared && msg.sim_minutes - last.at <= CLEARING_MINUTES)
            remember('weather/clearing')
        }
      }
      const view = msg.game_mode
      if (view && mode?.kind === view.kind) {
        const sting = (GAME_MODE_MUSIC[view.kind] as GameModeMusic).sting(view, mode)
        if (sting) music.playSting(sting)
      }
      mode = view
      mood = rosterMood(residents)
      effects.updateEnvironment(clock, weather)
      resolve()
    },
    /** 世界日志里有人去世：剧情音乐开着时响短提示，再放一首哀悼（遇害放疑云） */
    death(killed: boolean) {
      if (!story) return
      music.playSting(killed ? 'murder' : 'death')
      remember(killed ? 'story/murder' : 'story/mourning')
      resolve()
    },
    updateMovement(state: MovementSoundState) {
      effects.updateMovement(state)
    },
    playDescend() {
      effects.playDescend()
    },
    dispose() {
      music.dispose()
      effects.dispose()
    },
  }
}
