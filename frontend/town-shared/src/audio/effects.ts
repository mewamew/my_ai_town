import type { WeatherKind } from '../weather/types'
import { EFFECT_ASSETS, rainAmbienceVolume, resolveFootstepSurface } from './catalog'
import { ambienceAt } from './scene'
import { readSwitch, saveSwitch } from './preference'

const ENABLED_KEY = 'ai-town:effects-enabled'
const STEP_INTERVAL_MS = 460

/** 首页没有音效可放：首页「设定」只改这个开关，进小镇后按它播放 */
export const effectsPreference = {
  enabled: () => readSwitch(ENABLED_KEY),
  toggle: () => saveSwitch(ENABLED_KEY, !readSwitch(ENABLED_KEY)),
}

export interface MovementSoundState {
  moving: boolean
  locale: string
  space?: string
  atKind?: string
}

export function createEffectsController(button: HTMLButtonElement) {
  let enabled = readSwitch(ENABLED_KEY)
  let unlocked = false
  let clock = '12:00'
  let weather: WeatherKind | undefined
  let movement: MovementSoundState = { moving: false, locale: '' }
  let ambientKind: 'rain' | 'sleep' | null = null
  let ambient: HTMLAudioElement | null = null
  let stepTimer: ReturnType<typeof setInterval> | undefined
  let thunderTimer: ReturnType<typeof setTimeout> | undefined
  let lastStep = -1
  const oneShots = new Set<HTMLAudioElement>()

  /** 菜单里的开关：图标和「音效」不动，只改后面写开关的那一格；没有那一格时整个按钮写字 */
  const state = button.querySelector<HTMLElement>('.toggle-state')
  const updateButton = () => {
    // 写明是音效、开着还是关着：只有符号时分不清音乐和音效，也看不出是状态还是按钮
    if (state) state.textContent = enabled ? '开' : '关'
    else button.textContent = enabled ? '♪ 音效：开' : '♪ 音效：关'
    button.setAttribute('aria-label', enabled ? '音效：开' : '音效：关')
    button.setAttribute('aria-pressed', String(enabled))
    button.title = enabled
      ? '环境音与化身音效已开启（点击关闭）'
      : '环境音与化身音效已关闭（点击开启）'
  }
  const release = (audio: HTMLAudioElement) => {
    oneShots.delete(audio)
    audio.removeAttribute('src')
    audio.load()
  }
  const playOne = (url: string, volume: number) => {
    if (!enabled || !unlocked || document.hidden) return
    const audio = new Audio(url)
    audio.volume = volume
    oneShots.add(audio)
    audio.addEventListener('ended', () => release(audio), { once: true })
    audio.addEventListener('error', () => release(audio), { once: true })
    void audio.play().catch(() => release(audio))
  }
  const stopAmbient = () => {
    ambient?.pause()
    ambient?.removeAttribute('src')
    ambient?.load()
    ambient = null
    ambientKind = null
  }
  const syncAmbient = () => {
    const nextKind = ambienceAt(clock, weather)
    if (!enabled || !unlocked || document.hidden || !nextKind) {
      stopAmbient()
      return
    }
    const volume = nextKind === 'rain' ? rainAmbienceVolume(weather) : 0.1
    if (ambient && ambientKind === nextKind) {
      ambient.volume = volume
      if (ambient.paused) void ambient.play().catch(() => {})
      return
    }
    stopAmbient()
    ambientKind = nextKind
    ambient = new Audio(EFFECT_ASSETS.ambience[nextKind])
    ambient.loop = true
    ambient.preload = 'auto'
    ambient.volume = volume
    void ambient.play().catch(() => {})
  }
  const clearThunder = () => {
    if (thunderTimer) clearTimeout(thunderTimer)
    thunderTimer = undefined
  }
  const scheduleThunder = () => {
    clearThunder()
    if (!enabled || !unlocked || document.hidden || weather !== 'thunderstorm') return
    thunderTimer = setTimeout(
      () => {
        playOne(EFFECT_ASSETS.thunder, 0.42)
        scheduleThunder()
      },
      8000 + Math.random() * 16000
    )
  }
  const step = () => {
    if (!movement.moving) return
    const surface = resolveFootstepSurface(
      movement.locale,
      movement.space,
      movement.atKind,
      weather
    )
    const variants = EFFECT_ASSETS.footsteps[surface]
    lastStep = (lastStep + 1 + Math.floor(Math.random() * (variants.length - 1))) % variants.length
    playOne(variants[lastStep], surface === 'indoor' ? 0.24 : 0.2)
  }
  const syncSteps = () => {
    if (stepTimer) clearInterval(stepTimer)
    stepTimer = undefined
    if (!enabled || !unlocked || document.hidden || !movement.moving) return
    step()
    stepTimer = setInterval(step, STEP_INTERVAL_MS)
  }
  const stopAll = () => {
    stopAmbient()
    clearThunder()
    if (stepTimer) clearInterval(stepTimer)
    stepTimer = undefined
    for (const audio of oneShots) {
      audio.pause()
      release(audio)
    }
  }
  const unlock = () => {
    unlocked = true
    syncAmbient()
    scheduleThunder()
    syncSteps()
  }
  const onFirstGesture = () => unlock()
  const onVisibility = () => {
    if (document.hidden) stopAll()
    else if (enabled && unlocked) unlock()
  }
  document.addEventListener('pointerdown', onFirstGesture, { capture: true, once: true })
  document.addEventListener('keydown', onFirstGesture, { capture: true, once: true })
  document.addEventListener('visibilitychange', onVisibility)
  const toggle = () => {
    unlocked = true
    enabled = !enabled
    saveSwitch(ENABLED_KEY, enabled)
    if (enabled) unlock()
    else stopAll()
    updateButton()
  }
  button.onclick = (event) => {
    event.stopPropagation()
    toggle()
  }
  updateButton()

  return {
    enabled: () => enabled,
    toggle,
    updateEnvironment(nextClock: string, nextWeather?: WeatherKind) {
      const changed = weather !== nextWeather
      clock = nextClock
      weather = nextWeather
      syncAmbient()
      if (changed) {
        scheduleThunder()
        syncSteps()
      }
    },
    updateMovement(next: MovementSoundState) {
      const changed =
        next.moving !== movement.moving ||
        next.locale !== movement.locale ||
        next.space !== movement.space ||
        next.atKind !== movement.atKind
      movement = next
      if (changed) syncSteps()
    },
    playDescend() {
      playOne(EFFECT_ASSETS.descend, 0.38)
    },
    dispose() {
      document.removeEventListener('pointerdown', onFirstGesture, true)
      document.removeEventListener('keydown', onFirstGesture, true)
      document.removeEventListener('visibilitychange', onVisibility)
      button.onclick = null
      stopAll()
    },
  }
}
