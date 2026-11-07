import type { WeatherKind } from '../weather/types'
import type { MusicCell } from './scene'

export interface MusicTrack {
  id: string
  /** 换曲时菜单里音乐开关上亮几秒的曲名 */
  title: string
  /** 在哪些场合放，见 scene.ts */
  cells: readonly MusicCell[]
  url: string
}

export const MUSIC_TRACKS: readonly MusicTrack[] = [
  {
    id: 'daylife-gathering',
    title: '晨集小镇',
    cells: ['town/day', 'ui/title'],
    url: new URL('../../assets/music/music_town_daylife_gathering.m4a', import.meta.url).href,
  },
  {
    id: 'daylife-market',
    title: '晨市像素日',
    cells: ['town/day'],
    url: new URL('../../assets/music/music_town_daylife_market.m4a', import.meta.url).href,
  },
  {
    id: 'daylife-corner-opening',
    title: '街角开门时',
    cells: ['town/day', 'town/dawn'],
    url: new URL('../../assets/music/music_town_daylife_corner_opening.m4a', import.meta.url).href,
  },
  {
    id: 'daylife-window-afternoon',
    title: '窗边午后小镇',
    cells: ['town/day'],
    url: new URL('../../assets/music/music_town_daylife_window_afternoon.m4a', import.meta.url)
      .href,
  },
  {
    id: 'evening-dusk-town',
    title: '暮色小镇',
    cells: ['town/dusk'],
    url: new URL('../../assets/music/music_town_evening_dusk_town.m4a', import.meta.url).href,
  },
  {
    id: 'evening-lane-breeze',
    title: '巷口晚风',
    cells: ['town/dusk'],
    url: new URL('../../assets/music/music_town_evening_lane_breeze.m4a', import.meta.url).href,
  },
  {
    id: 'evening-workshop-lights',
    title: '夜工坊灯火',
    cells: ['town/night'],
    url: new URL('../../assets/music/music_town_evening_workshop_lights.m4a', import.meta.url).href,
  },
  {
    id: 'rain-window-town-01',
    title: '窗边小镇',
    cells: ['weather/rain'],
    url: new URL('../../assets/music/music_town_rain_window_town_01.m4a', import.meta.url).href,
  },
  {
    id: 'rain-window-town-02',
    title: '窗边小镇（变体）',
    cells: ['weather/rain'],
    url: new URL('../../assets/music/music_town_rain_window_town_02.m4a', import.meta.url).href,
  },
  {
    id: 'after-rain-01',
    title: '雨后小镇',
    cells: ['weather/clearing'],
    url: new URL('../../assets/music/music_town_thunderstorm_after_rain_01.m4a', import.meta.url)
      .href,
  },
  {
    id: 'after-rain-02',
    title: '雨后小镇（变体）',
    cells: ['weather/clearing'],
    url: new URL('../../assets/music/music_town_thunderstorm_after_rain_02.m4a', import.meta.url)
      .href,
  },
  {
    id: 'sleep-belltower',
    title: '沉睡钟楼',
    cells: ['town/sleep'],
    url: new URL('../../assets/music/music_town_sleep_belltower_01.m4a', import.meta.url).href,
  },
  // 2026-11 用 Suno 生成的新曲（播放录音转码，见 licenses/ASSETS.txt）
  {
    id: 'title-overture',
    title: '小镇序曲',
    cells: ['ui/title'],
    url: new URL('../../assets/music/music_title_overture.m4a', import.meta.url).href,
  },
  {
    id: 'town-dawn-harbor-mist',
    title: '晨雾码头',
    cells: ['town/dawn'],
    url: new URL('../../assets/music/music_town_dawn_harbor_mist.m4a', import.meta.url).href,
  },
  {
    id: 'town-dawn-chimney',
    title: '炊烟起',
    cells: ['town/dawn'],
    url: new URL('../../assets/music/music_town_dawn_chimney_smoke.m4a', import.meta.url).href,
  },
  {
    id: 'town-day-stone-lane',
    title: '石板路散步',
    cells: ['town/day'],
    url: new URL('../../assets/music/music_town_daylife_stone_lane.m4a', import.meta.url).href,
  },
  {
    id: 'town-day-sea-breeze',
    title: '海风晾衣绳',
    cells: ['town/day'],
    url: new URL('../../assets/music/music_town_daylife_sea_breeze.m4a', import.meta.url).href,
  },
  {
    id: 'town-night-window-lamps',
    title: '窗灯一盏盏',
    cells: ['town/night'],
    url: new URL('../../assets/music/music_town_night_window_lamps.m4a', import.meta.url).href,
  },
  {
    id: 'town-night-lighthouse',
    title: '灯塔守夜',
    cells: ['town/night'],
    url: new URL('../../assets/music/music_town_night_lighthouse.m4a', import.meta.url).href,
  },
  {
    id: 'town-sleep-starlit',
    title: '星下熟睡',
    cells: ['town/sleep'],
    url: new URL('../../assets/music/music_town_sleep_starlit.m4a', import.meta.url).href,
  },
  {
    id: 'town-sleep-tide-dream',
    title: '潮声入梦',
    cells: ['town/sleep'],
    url: new URL('../../assets/music/music_town_sleep_tide_dream.m4a', import.meta.url).href,
  },
  {
    id: 'weather-snow-first',
    title: '初雪广场',
    cells: ['weather/snow'],
    url: new URL('../../assets/music/music_weather_snow_first.m4a', import.meta.url).href,
  },
  {
    id: 'weather-snow-silent',
    title: '雪落无声',
    cells: ['weather/snow'],
    url: new URL('../../assets/music/music_weather_snow_silent.m4a', import.meta.url).href,
  },
  {
    id: 'weather-storm-front',
    title: '风暴压境',
    cells: ['weather/storm'],
    url: new URL('../../assets/music/music_weather_storm_front.m4a', import.meta.url).href,
  },
  {
    id: 'weather-storm-indoors',
    title: '屋里听雷',
    cells: ['weather/storm'],
    url: new URL('../../assets/music/music_weather_storm_indoors.m4a', import.meta.url).href,
  },
  {
    id: 'weather-overcast',
    title: '阴天的邮差',
    cells: ['weather/overcast'],
    url: new URL('../../assets/music/music_weather_overcast_grey.m4a', import.meta.url).href,
  },
  {
    id: 'story-scarcity',
    title: '最后一罐',
    cells: ['story/scarcity'],
    url: new URL('../../assets/music/music_story_scarcity_last_can.m4a', import.meta.url).href,
  },
  {
    id: 'story-critical',
    title: '撑住',
    cells: ['story/critical'],
    url: new URL('../../assets/music/music_story_critical_hold_on.m4a', import.meta.url).href,
  },
  {
    id: 'story-mourning',
    title: '潮声里的名字',
    cells: ['story/mourning'],
    url: new URL('../../assets/music/music_story_mourning_names.m4a', import.meta.url).href,
  },
  {
    id: 'story-mourning-chair',
    title: '空着的椅子',
    cells: ['story/mourning'],
    url: new URL('../../assets/music/music_story_mourning_empty_chair.m4a', import.meta.url).href,
  },
  {
    id: 'story-murder',
    title: '谁在说谎',
    cells: ['story/murder'],
    url: new URL('../../assets/music/music_story_murder_who_lies.m4a', import.meta.url).href,
  },
  {
    id: 'story-finale',
    title: '小镇空了',
    cells: ['story/finale'],
    url: new URL('../../assets/music/music_story_finale_empty_town.m4a', import.meta.url).href,
  },
  {
    id: 'island-day-wreck',
    title: '沉船海滩',
    cells: ['island/day'],
    url: new URL('../../assets/music/music_island_day_wreck_beach.m4a', import.meta.url).href,
  },
  {
    id: 'island-day-palm',
    title: '椰林小径',
    cells: ['island/day'],
    url: new URL('../../assets/music/music_island_day_palm_trail.m4a', import.meta.url).href,
  },
  {
    id: 'island-dusk-campfire',
    title: '篝火与潮汐',
    cells: ['island/dusk'],
    url: new URL('../../assets/music/music_island_dusk_campfire.m4a', import.meta.url).href,
  },
  {
    id: 'island-sleep-reef',
    title: '礁石上的星空',
    cells: ['island/sleep'],
    url: new URL('../../assets/music/music_island_sleep_reef_stars.m4a', import.meta.url).href,
  },
  {
    id: 'tide-announced',
    title: '今天涨到哪',
    cells: ['tide/announced'],
    url: new URL('../../assets/music/music_tide_announced.m4a', import.meta.url).href,
  },
  {
    id: 'tide-rising-edge',
    title: '水边在逼近',
    cells: ['tide/rising'],
    url: new URL('../../assets/music/music_tide_rising_edge.m4a', import.meta.url).href,
  },
  {
    id: 'tide-rising-high',
    title: '往高处去',
    cells: ['tide/rising'],
    url: new URL('../../assets/music/music_tide_rising_high_ground.m4a', import.meta.url).href,
  },
  {
    id: 'tide-final',
    title: '最后的高地',
    cells: ['tide/final'],
    url: new URL('../../assets/music/music_tide_final_ring.m4a', import.meta.url).href,
  },
  {
    id: 'tide-winner',
    title: '潮退之后',
    cells: ['tide/winner'],
    url: new URL('../../assets/music/music_tide_winner.m4a', import.meta.url).href,
  },
  {
    id: 'wasteland-day-rust',
    title: '锈船之间',
    cells: ['wasteland/day'],
    url: new URL('../../assets/music/music_wasteland_day_rust_ships.m4a', import.meta.url).href,
  },
  {
    id: 'wasteland-day-tin',
    title: '铁皮屋集市',
    cells: ['wasteland/day'],
    url: new URL('../../assets/music/music_wasteland_day_tin_market.m4a', import.meta.url).href,
  },
  {
    id: 'wasteland-dusk-sunset',
    title: '干海床落日',
    cells: ['wasteland/dusk'],
    url: new URL('../../assets/music/music_wasteland_dusk_seabed_sunset.m4a', import.meta.url).href,
  },
  {
    id: 'wasteland-sleep-embers',
    title: '余烬收音机',
    cells: ['wasteland/sleep'],
    url: new URL('../../assets/music/music_wasteland_sleep_embers_radio.m4a', import.meta.url).href,
  },
  {
    id: 'frozen-day-harbor',
    title: '冰港晴日',
    cells: ['frozen/day'],
    url: new URL('../../assets/music/music_frozen_day_ice_harbor.m4a', import.meta.url).href,
  },
  {
    id: 'frozen-day-pines',
    title: '雪松林',
    cells: ['frozen/day'],
    url: new URL('../../assets/music/music_frozen_day_pine_forest.m4a', import.meta.url).href,
  },
  {
    id: 'frozen-dusk-aurora',
    title: '极光未至',
    cells: ['frozen/dusk'],
    url: new URL('../../assets/music/music_frozen_dusk_before_aurora.m4a', import.meta.url).href,
  },
  {
    id: 'frozen-sleep-lamp',
    title: '冰下的灯',
    cells: ['frozen/sleep'],
    url: new URL('../../assets/music/music_frozen_sleep_lamp_under_ice.m4a', import.meta.url).href,
  },
]

/** 短提示：出事的那一刻压在背景乐上响 3～4 秒 */
export type StingId = 'death' | 'murder' | 'tide-announce' | 'tide-rise'
export const STING_URLS: Record<StingId, string> = {
  death: new URL('../../assets/music/sting_death.m4a', import.meta.url).href,
  murder: new URL('../../assets/music/sting_murder.m4a', import.meta.url).href,
  'tide-announce': new URL('../../assets/music/sting_tide_announce.m4a', import.meta.url).href,
  'tide-rise': new URL('../../assets/music/sting_tide_rise.m4a', import.meta.url).href,
}

export const EFFECT_ASSETS = {
  ambience: {
    rain: new URL('../../assets/effects/ambience/amb_town_rain_loop.ogg', import.meta.url).href,
    sleep: new URL(
      '../../assets/effects/ambience/amb_sleep_soft_white_noise_loop.m4a',
      import.meta.url
    ).href,
  },
  thunder: new URL('../../assets/effects/sfx/weather/sfx_thunder_generated.ogg', import.meta.url)
    .href,
  descend: new URL('../../assets/effects/sfx/avatar/sfx_avatar_descend.ogg', import.meta.url).href,
  footsteps: {
    outdoor: [
      new URL('../../assets/effects/sfx/footsteps/sfx_footstep_outdoor_01.ogg', import.meta.url)
        .href,
      new URL('../../assets/effects/sfx/footsteps/sfx_footstep_outdoor_02.ogg', import.meta.url)
        .href,
      new URL('../../assets/effects/sfx/footsteps/sfx_footstep_outdoor_03.ogg', import.meta.url)
        .href,
    ],
    indoor: [
      new URL('../../assets/effects/sfx/footsteps/sfx_footstep_indoor_01.ogg', import.meta.url)
        .href,
      new URL('../../assets/effects/sfx/footsteps/sfx_footstep_indoor_02.ogg', import.meta.url)
        .href,
      new URL('../../assets/effects/sfx/footsteps/sfx_footstep_indoor_03.ogg', import.meta.url)
        .href,
    ],
    wet: [
      new URL('../../assets/effects/sfx/footsteps/sfx_footstep_wet_01.ogg', import.meta.url).href,
      new URL('../../assets/effects/sfx/footsteps/sfx_footstep_wet_02.ogg', import.meta.url).href,
      new URL('../../assets/effects/sfx/footsteps/sfx_footstep_wet_03.ogg', import.meta.url).href,
    ],
  },
} as const

type FootstepSurface = keyof typeof EFFECT_ASSETS.footsteps

export function rainAmbienceVolume(weather?: WeatherKind): number {
  if (weather === 'thunderstorm') return 0.3
  if (weather === 'heavy_rain') return 0.25
  if (weather === 'rain') return 0.2
  return 0.14
}

export function resolveFootstepSurface(
  locale: string,
  space: string | undefined,
  atKind: string | undefined,
  weather?: WeatherKind
): FootstepSurface {
  const indoors =
    (!!space && space !== 'town_outdoor') ||
    atKind === 'station' ||
    /(?:^|_)(?:indoor|interior|home|house)(?:_|$)/i.test(locale)
  if (indoors) return 'indoor'
  return weather === 'light_rain' ||
    weather === 'rain' ||
    weather === 'heavy_rain' ||
    weather === 'thunderstorm'
    ? 'wet'
    : 'outdoor'
}
