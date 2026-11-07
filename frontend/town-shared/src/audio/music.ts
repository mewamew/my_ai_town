import { STING_URLS, type MusicTrack, type StingId } from './catalog'
import { createMixer } from './fade'
import { readSwitch, saveSwitch } from './preference'
import { switchNow, type MusicCell, type MusicChoice } from './scene'

// 背景乐播放器：选曲（scene.ts）给出此刻该放的一格，这里决定什么时候换、怎么换。
// 出了事、变紧张立刻换，新旧两首交叉淡化 3 秒；变平静等这首放完再从新的一格挑。
// 同一格里随机挑，不和上一首重复。短提示压在背景乐上响，响的时候背景乐压低。
// 换上新的一首时，音乐按钮上亮 4 秒曲名。

// 音乐默认开：换过键名，旧版存下的「关」不再沿用，之后的选择照常记住
const ENABLED_KEY = 'ai-town:music-on'
const VOLUME = 0.32
const STING_VOLUME = 0.36
const CROSSFADE_MS = 3000
/** 短提示响时背景乐压到几成 */
const DUCK_TO = 0.35
const TITLE_MS = 4000
/** 同一时刻接连出事（几个人一起去世）只响一下 */
const STING_GAP_MS = 2500

interface Playing {
  audio: HTMLAudioElement
  track: MusicTrack
  choice: MusicChoice
}

export function createMusicController(
  button: HTMLButtonElement,
  options: {
    /** 第一首放这一首（在这一格里的话） */
    first?: string
    /** 换上了某一格的曲子：「只放一首」的格子据此记为放过 */
    onStart?: (cell: MusicCell) => void
  } = {}
) {
  let enabled = readSwitch(ENABLED_KEY)
  // 浏览器在页面上有过点击或按键之前不许出声：开着却被拦下时记着，下一次操作再放
  let blocked = false
  let choice: MusicChoice | null = null
  let current: Playing | null = null
  /** 正在载入、还没响的那一格 */
  let starting: MusicCell | null = null
  let lastTrackId = ''
  let first = options.first
  let request = 0
  let titleShown = ''
  let titleTimer: ReturnType<typeof setTimeout> | undefined
  const stings = new Set<HTMLAudioElement>()
  let lastSting = -Infinity

  /** 菜单里的开关：图标和「音乐」不动，只改后面写开关的那一格；没有那一格时整个按钮写字 */
  const state = button.querySelector<HTMLElement>('.toggle-state')
  const updateButton = () => {
    // 写明是音乐、开着还是关着：只有符号时分不清音乐和音效，也看不出是状态还是按钮
    if (state) state.textContent = enabled ? titleShown || '开' : '关'
    else button.textContent = enabled ? `♫ ${titleShown || '音乐：开'}` : '♫ 音乐：关'
    button.setAttribute('aria-label', enabled ? '音乐：开' : '音乐：关')
    button.setAttribute('aria-pressed', String(enabled))
    button.title = enabled
      ? current
        ? `背景音乐正在播放：${current.track.title}（点击关闭）`
        : '背景音乐已开启（下次操作后播放）'
      : '背景音乐已关闭（点击开启）'
  }
  const showTitle = (track: MusicTrack) => {
    clearTimeout(titleTimer)
    titleShown = track.title
    updateButton()
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
  const mixer = createMixer(VOLUME, clearAudio)
  const pick = (tracks: readonly MusicTrack[]) => {
    const wanted = tracks.find((track) => track.id === first)
    first = undefined
    if (wanted) return wanted
    const others = tracks.filter((track) => track.id !== lastTrackId)
    const pool = others.length ? others : tracks
    return pool[Math.floor(Math.random() * pool.length)]
  }

  /** 从此刻的一格里挑一首放；crossfade 时和正在放的那首交叉淡化，否则直接开始 */
  const start = async (crossfade: boolean) => {
    const target = choice
    if (!enabled || document.hidden || !target?.tracks.length) return
    const id = ++request
    const track = pick(target.tracks)
    starting = target.cell
    blocked = false
    const audio = new Audio(track.url)
    audio.preload = 'auto'
    mixer.add(audio, crossfade ? 0 : 1)
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
        if (current?.audio !== audio) return
        mixer.forget(audio)
        current = null
        updateButton()
      },
      { once: true }
    )
    try {
      await audio.play()
      if (id !== request || !enabled || document.hidden) {
        mixer.forget(audio)
        clearAudio(audio)
        return
      }
      const previous = current
      current = { audio, track, choice: target }
      starting = null
      lastTrackId = track.id
      if (previous) mixer.fade(previous.audio, 0, CROSSFADE_MS, true)
      if (crossfade) mixer.fade(audio, 1, previous ? CROSSFADE_MS : 0)
      showTitle(track)
      options.onStart?.(target.cell)
    } catch (error) {
      mixer.forget(audio)
      clearAudio(audio)
      if (id !== request) return
      starting = null
      blocked = error instanceof DOMException && error.name === 'NotAllowedError'
      updateButton()
    }
  }

  /** 选曲换了一格：立刻换、等这首放完，还是不用动 */
  const setChoice = (next: MusicChoice) => {
    choice = next
    if (!enabled || blocked || document.hidden) return
    if (starting) {
      if (starting === next.cell) return
      // 正在载入的那一格已经不对了：作废，按正在放的那首重新判断
      request += 1
      starting = null
    }
    if (!current) {
      void start(false)
      return
    }
    const left = current.audio.duration - current.audio.currentTime
    if (switchNow(next, current.choice, Number.isFinite(left) ? left : Infinity)) void start(true)
  }

  const stopStings = () => {
    for (const audio of stings) clearAudio(audio)
    stings.clear()
  }
  const playSting = (id: StingId) => {
    const now = performance.now()
    if (!enabled || blocked || document.hidden || now - lastSting < STING_GAP_MS) return
    lastSting = now
    const audio = new Audio(STING_URLS[id])
    audio.volume = STING_VOLUME
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
    request += 1
    starting = null
    mixer.clear()
    stopStings()
    current = null
    clearTimeout(titleTimer)
    titleShown = ''
    updateButton()
  }
  const onVisibility = () => {
    if (document.hidden) {
      mixer.settle()
      stopStings()
      current?.audio.pause()
    } else if (enabled) {
      if (current) void current.audio.play().catch(() => updateButton())
      else void start(false)
    }
  }
  // 点音乐开关本身交给开关处理：不然按下时先放出来，松开时又被开关关掉
  const onGesture = (event: Event) => {
    if (blocked && !button.contains(event.target as Node)) void start(false)
  }
  document.addEventListener('pointerdown', onGesture, true)
  document.addEventListener('keydown', onGesture, true)
  document.addEventListener('visibilitychange', onVisibility)
  const toggle = () => {
    // 显示开着、却被浏览器拦着没响：这一下是要听，放出来而不是关掉
    if (enabled && blocked) {
      void start(false)
      return
    }
    enabled = !enabled
    saveSwitch(ENABLED_KEY, enabled)
    if (enabled) void start(false)
    else stop()
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
    setChoice,
    playSting,
    /** 正在放（或正在换上）的那一格 */
    playingCell: (): MusicCell | null => starting ?? current?.choice.cell ?? null,
    dispose() {
      document.removeEventListener('pointerdown', onGesture, true)
      document.removeEventListener('keydown', onGesture, true)
      document.removeEventListener('visibilitychange', onVisibility)
      button.onclick = null
      stop()
    },
  }
}
