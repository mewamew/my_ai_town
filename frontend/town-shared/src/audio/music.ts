import { MUSIC_TRACKS, STING_URLS, type MusicTrack, type StingId } from './catalog'
import { createMixer } from './fade'
import { readPreference, readSwitch, savePreference, saveSwitch } from './preference'
import { switchNow, type MusicCell, type MusicChoice } from './scene'

const ENABLED_KEY = 'ai-town:music-on'
const VOLUME_KEY = 'ai-town:music-volume'
const MANUAL_KEY = 'ai-town:music-track'
const DEFAULT_VOLUME = 0.32
const STING_RATIO = 0.36 / DEFAULT_VOLUME
const CROSSFADE_MS = 3000
const DUCK_TO = 0.35
const TITLE_MS = 4000
const STING_GAP_MS = 2500

export interface MusicState {
  enabled: boolean
  blocked: boolean
  loading: boolean
  mode: 'auto' | 'manual'
  /** 已成功开始播放的曲目，关闭音乐后为 null。 */
  track: MusicTrack | null
  /** 正在载入或手选待播的目标；关闭音乐、载入失败时仍保留选择。 */
  selectedTrack: MusicTrack | null
  volume: number
  error: string | null
}

export interface MusicControls {
  enabled(): boolean
  toggle(): void
  state(): MusicState
  subscribe(listener: (state: MusicState) => void): () => void
  readonly tracks: readonly MusicTrack[]
  selectTrack(id: string): void
  next(): void
  previous(): void
  setAutomatic(): void
  setVolume(value: number): void
}

interface Playing {
  audio: HTMLAudioElement
  track: MusicTrack
  /** 手选没有自动场景，不能据此消费只播放一次的剧情。 */
  choice: MusicChoice | null
}

// 场景不断更新自动候选；手选只覆盖播放，不改剧情开关。所有来源共用同一混音器和请求代次。
export function createMusicController(
  button: HTMLButtonElement,
  options: {
    first?: string
    onStart?: (cell: MusicCell) => void
  } = {}
) {
  let enabled = readSwitch(ENABLED_KEY)
  const savedVolume = readPreference(VOLUME_KEY)
  const parsedVolume = savedVolume?.trim() ? Number(savedVolume) : NaN
  let volume = Number.isFinite(parsedVolume)
    ? Math.min(1, Math.max(0, parsedVolume))
    : DEFAULT_VOLUME
  const savedTrack = readPreference(MANUAL_KEY)
  let manual = MUSIC_TRACKS.find((track) => track.id === savedTrack) ?? null
  let blocked = false
  let error: string | null = null
  let choice: MusicChoice | null = null
  let current: Playing | null = null
  let pending: Playing | null = null
  let lastTrackId = ''
  let first = options.first
  let request = 0
  let disposed = false
  let titleShown = ''
  let titleTimer: ReturnType<typeof setTimeout> | undefined
  const listeners = new Set<(state: MusicState) => void>()
  const stings = new Set<HTMLAudioElement>()
  let lastSting = -Infinity
  const toggleState = button.querySelector<HTMLElement>('.toggle-state')
  const state = (): MusicState => ({
    enabled,
    blocked,
    loading: pending !== null,
    mode: manual ? 'manual' : 'auto',
    track: current?.track ?? null,
    selectedTrack: pending?.track ?? manual ?? current?.track ?? null,
    volume,
    error,
  })
  const updateButton = () => {
    if (toggleState) toggleState.textContent = enabled ? titleShown || '开' : '关'
    else button.textContent = enabled ? `♫ ${titleShown || '音乐：开'}` : '♫ 音乐：关'
    button.setAttribute('aria-label', enabled ? '音乐：开' : '音乐：关')
    button.setAttribute('aria-pressed', String(enabled))
    button.title = enabled
      ? current
        ? `背景音乐正在播放：${current.track.title}（点击关闭）`
        : '背景音乐已开启（下次操作后播放）'
      : '背景音乐已关闭（点击开启）'
  }
  const publish = () => {
    updateButton()
    const snapshot = state()
    for (const listener of listeners) listener(snapshot)
  }
  const showTitle = (track: MusicTrack) => {
    clearTimeout(titleTimer)
    titleShown = track.title
    publish()
    titleTimer = setTimeout(() => {
      titleShown = ''
      updateButton()
    }, TITLE_MS)
  }
  const clearAudio = (audio: HTMLAudioElement) => {
    audio.pause()
    audio.removeAttribute('src')
    audio.load()
  }
  const mixer = createMixer(volume, clearAudio)
  const pick = (tracks: readonly MusicTrack[]) => {
    const wanted = tracks.find((track) => track.id === first)
    first = undefined
    if (wanted) return wanted
    const others = tracks.filter((track) => track.id !== lastTrackId)
    const pool = others.length ? others : tracks
    return pool[Math.floor(Math.random() * pool.length)]
  }
  const cancelPending = () => {
    request += 1
    if (!pending) return
    mixer.forget(pending.audio)
    clearAudio(pending.audio)
    pending = null
  }
  const recordError = (reason: unknown) => {
    blocked = reason instanceof DOMException && reason.name === 'NotAllowedError'
    error = blocked
      ? '浏览器尚未允许播放，请点击音乐开关。'
      : '这首音乐暂时无法播放，请重试或换一首。'
  }

  const start = async (crossfade: boolean) => {
    const target = manual ? null : choice
    if (disposed || !enabled || document.hidden || (!manual && !target?.tracks.length)) return
    cancelPending()
    const id = request
    const track = manual ?? pick(target!.tracks)
    const audio = new Audio(track.url)
    const playing: Playing = { audio, track, choice: target }
    pending = playing
    blocked = false
    error = null
    audio.preload = 'auto'
    mixer.add(audio, crossfade ? 0 : 1)
    publish()
    audio.addEventListener(
      'ended',
      () => {
        if (current?.audio !== audio) return
        mixer.forget(audio)
        clearAudio(audio)
        current = null
        void start(false)
      },
      { once: true }
    )
    audio.addEventListener(
      'error',
      () => {
        if (pending?.audio === audio) cancelPending()
        else if (current?.audio === audio) {
          mixer.forget(audio)
          clearAudio(audio)
          current = null
        } else return
        recordError(null)
        publish()
      },
      { once: true }
    )
    try {
      await audio.play()
      if (disposed || id !== request || !enabled || document.hidden) {
        mixer.forget(audio)
        clearAudio(audio)
        return
      }
      const previous = current
      current = playing
      pending = null
      lastTrackId = track.id
      if (previous) mixer.fade(previous.audio, 0, CROSSFADE_MS, true)
      if (crossfade) mixer.fade(audio, 1, previous ? CROSSFADE_MS : 0)
      showTitle(track)
      if (target) options.onStart?.(target.cell)
    } catch (reason) {
      mixer.forget(audio)
      clearAudio(audio)
      if (disposed || id !== request) return
      pending = null
      recordError(reason)
      publish()
    }
  }

  const setChoice = (next: MusicChoice, now = false) => {
    choice = next
    if (disposed || !enabled || blocked || document.hidden) return
    if (manual) {
      if (!current && !pending) void start(false)
      return
    }
    if (pending) {
      if (pending.choice?.cell === next.cell) return
      cancelPending()
    }
    if (!current) {
      void start(false)
      return
    }
    const left = current.audio.duration - current.audio.currentTime
    if (
      !current.choice ||
      (now
        ? next.cell !== current.choice.cell
        : switchNow(next, current.choice, Number.isFinite(left) ? left : Infinity))
    )
      void start(true)
  }

  const stopStings = () => {
    for (const audio of stings) clearAudio(audio)
    stings.clear()
  }
  const stingVolume = () => Math.min(1, volume * STING_RATIO)
  const playSting = (id: StingId) => {
    const now = performance.now()
    // 手选是玩家要求持续听这一首；剧情提示不盖过它，事件仍由游戏自己的界面提示。
    if (
      disposed ||
      manual ||
      !enabled ||
      blocked ||
      document.hidden ||
      volume === 0 ||
      now - lastSting < STING_GAP_MS
    )
      return
    lastSting = now
    const audio = new Audio(STING_URLS[id])
    audio.volume = stingVolume()
    stings.add(audio)
    mixer.duck(DUCK_TO, 250)
    const done = () => {
      if (!stings.delete(audio)) return
      clearAudio(audio)
      if (!stings.size) mixer.duck(1, 1200)
    }
    audio.addEventListener('ended', done, { once: true })
    audio.addEventListener('error', done, { once: true })
    void audio.play().catch(done)
  }
  const stop = () => {
    cancelPending()
    mixer.clear()
    stopStings()
    current = null
    blocked = false
    error = null
    clearTimeout(titleTimer)
    titleShown = ''
    publish()
  }
  const onVisibility = () => {
    if (document.hidden) {
      cancelPending()
      mixer.settle()
      stopStings()
      current?.audio.pause()
      publish()
    } else if (enabled) {
      if (!current || (manual && current.track.id !== manual.id)) void start(false)
      else {
        const playing = current
        void playing.audio
          .play()
          .then(() => {
            if (disposed || current !== playing) return
            blocked = false
            error = null
            publish()
          })
          .catch((reason: unknown) => {
            if (disposed || current !== playing) return
            recordError(reason)
            publish()
          })
        if (!manual && choice) setChoice(choice)
      }
    }
  }
  const onGesture = (event: Event) => {
    const target = event.target as Element | null
    // 显式播放按钮的 click 自己负责恢复；捕获阶段抢先 play 会让随后的 toggle 反而关闭。
    if (blocked && !button.contains(target) && !target?.closest?.('[data-music-control]'))
      void start(Boolean(current))
  }
  const toggle = () => {
    if (disposed) return
    if (enabled && blocked) {
      void start(Boolean(current))
      return
    }
    enabled = !enabled
    saveSwitch(ENABLED_KEY, enabled)
    if (enabled) void start(false)
    else stop()
    publish()
  }
  const selectTrack = (id: string) => {
    if (disposed) return
    const track = MUSIC_TRACKS.find((entry) => entry.id === id)
    if (!track) return
    manual = track
    savePreference(MANUAL_KEY, id)
    cancelPending()
    stopStings()
    mixer.duck(1, 250)
    error = null
    if (enabled && !document.hidden) void start(Boolean(current))
    else publish()
  }
  const adjacent = (direction: number) => {
    const track = manual ?? pending?.track ?? current?.track
    const index = track ? MUSIC_TRACKS.findIndex((entry) => entry.id === track.id) : -1
    const next =
      index < 0
        ? direction > 0
          ? 0
          : MUSIC_TRACKS.length - 1
        : (index + direction + MUSIC_TRACKS.length) % MUSIC_TRACKS.length
    if (MUSIC_TRACKS[next]) selectTrack(MUSIC_TRACKS[next].id)
  }
  const setAutomatic = () => {
    if (disposed) return
    manual = null
    savePreference(MANUAL_KEY, null)
    cancelPending()
    error = null
    if (enabled && !document.hidden && choice?.tracks.length) void start(Boolean(current))
    else publish()
  }
  const setVolume = (value: number) => {
    if (disposed || !Number.isFinite(value)) return
    volume = Math.min(1, Math.max(0, value))
    savePreference(VOLUME_KEY, String(volume))
    mixer.setBaseVolume(volume)
    for (const audio of stings) audio.volume = stingVolume()
    publish()
  }
  document.addEventListener('pointerdown', onGesture, true)
  document.addEventListener('keydown', onGesture, true)
  document.addEventListener('visibilitychange', onVisibility)
  button.onclick = (event) => {
    event.stopPropagation()
    toggle()
  }
  updateButton()

  return {
    enabled: () => enabled,
    toggle,
    state,
    subscribe(listener: (state: MusicState) => void) {
      if (disposed) return () => {}
      listeners.add(listener)
      listener(state())
      return () => {
        listeners.delete(listener)
      }
    },
    tracks: MUSIC_TRACKS,
    selectTrack,
    next: () => adjacent(1),
    previous: () => adjacent(-1),
    setAutomatic,
    setVolume,
    setChoice,
    playSting,
    playingCell: (): MusicCell | null =>
      manual ? null : (pending?.choice?.cell ?? current?.choice?.cell ?? null),
    dispose() {
      if (disposed) return
      disposed = true
      document.removeEventListener('pointerdown', onGesture, true)
      document.removeEventListener('keydown', onGesture, true)
      document.removeEventListener('visibilitychange', onVisibility)
      button.onclick = null
      stop()
      listeners.clear()
    },
  } satisfies MusicControls & {
    setChoice(next: MusicChoice, now?: boolean): void
    playSting(id: StingId): void
    playingCell(): MusicCell | null
    dispose(): void
  }
}
