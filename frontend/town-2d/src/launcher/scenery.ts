import { slotAt, type TimeSlot } from 'town-shared/audio/scene'
import { pixelIcon, setPixelIcon, type PixelName } from 'town-shared/game/pixel'
import { weatherLabels, type WeatherKind } from 'town-shared/weather/types'
import { skyTone } from '../map/hd2d/daylight'
import type { LightPalette } from '../map/themes/types'

// 赏景的景色条：拖天色轨道换时刻，点七种天气，播放时一分钟走完一天。只换选镇页预览的画面，
// 不连世界、不改存档（接到预览上见 page.ts 的 setScenic）。轨道的颜色是这座镇各个时刻的天色，
// 和立体场景同一套算法（hd2d/daylight.ts）。

export interface Scenery {
  /** 一天里的分钟（0～1440，播放时带小数） */
  minutes: number
  weather: WeatherKind
}

/** 进赏景时的景色：和预览原来的样子一样，傍晚 17 点、晴（hd2d/scene.ts 的 PREVIEW_HOUR） */
const START: Scenery = { minutes: 17 * 60, weather: 'clear' }
/** 播放时一秒走过的游戏分钟：一分钟走完一天 */
const PLAY_PER_SECOND = 1440 / 60
/** 方向键一下走 15 分钟，按住 Shift 一小时；都落在整刻、整点上 */
const STEP = 15
const ICONS: Record<WeatherKind, PixelName> = {
  clear: 'sun',
  overcast: 'cloud',
  light_rain: 'drizzle',
  rain: 'rain',
  heavy_rain: 'downpour',
  thunderstorm: 'storm',
  snow: 'snow',
}
/** 时段和选曲（audio/scene.ts 的 slotAt）一样分，赏景时换到哪一段就放哪一段的曲子 */
const SLOTS: Record<TimeSlot, string> = {
  dawn: '清晨',
  day: '白天',
  dusk: '黄昏',
  night: '夜晚',
  sleep: '深夜',
}

/** 「16:40」 */
export function clockText(minutes: number) {
  const m = ((Math.floor(minutes) % 1440) + 1440) % 1440
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`
}
/** 和游戏里的时钟牌一样：19 点到次日 5 点画月亮 */
const moonAt = (minutes: number) => minutes >= 19 * 60 || minutes < 5 * 60
/** 这个时刻、这种天气的图标（晴天夜里是月亮） */
export const sceneryIcon = (minutes: number, weather: WeatherKind): PixelName =>
  weather === 'clear' && moonAt(minutes) ? 'moon' : ICONS[weather]

export function createSceneryBar(
  host: HTMLElement,
  events: {
    /** 时刻或天气变了：拖动、点选，以及播放的每一帧 */
    change(scenery: Readonly<Scenery>): void
    /** 开始或停下播放 */
    playing(on: boolean): void
  }
) {
  const value: Scenery = { ...START }
  let playing = false
  let active = false

  const play = document.createElement('button')
  play.type = 'button'
  play.className = 'scenery-play'
  const playIcon = pixelIcon('play')
  play.append(playIcon)

  const track = document.createElement('div')
  track.className = 'scenery-track'
  track.tabIndex = 0
  track.setAttribute('role', 'slider')
  track.setAttribute('aria-label', '时刻')
  track.setAttribute('aria-valuemin', '0')
  track.setAttribute('aria-valuemax', '1439')
  track.title = '拖动或点一下换时刻（← → 一刻钟，Shift 一小时）'
  const band = document.createElement('canvas')
  band.className = 'scenery-band'
  band.width = 480
  band.height = 12
  const thumb = pixelIcon('sun')
  thumb.classList.add('scenery-thumb')
  track.append(band, thumb)
  for (const hour of [0, 6, 12, 18, 24]) {
    const tick = document.createElement('span')
    tick.className = 'scenery-tick'
    tick.textContent = String(hour)
    tick.style.left = `${(hour / 24) * 100}%`
    track.append(tick)
  }

  const readout = document.createElement('div')
  readout.className = 'scenery-readout'
  const time = document.createElement('b'),
    note = document.createElement('small')
  readout.append(time, note)

  const weather = document.createElement('div')
  weather.className = 'scenery-weather'
  weather.setAttribute('role', 'group')
  weather.setAttribute('aria-label', '天气')
  const kinds = Object.keys(weatherLabels) as WeatherKind[]
  const buttons = kinds.map((kind) => {
    const button = document.createElement('button')
    button.type = 'button'
    button.dataset.kind = kind
    button.title = weatherLabels[kind]
    button.setAttribute('aria-label', weatherLabels[kind])
    button.append(pixelIcon(ICONS[kind]))
    button.onclick = () => {
      if (value.weather === kind) return
      value.weather = kind
      render()
      events.change(value)
    }
    weather.append(button)
    return button
  })
  const separator = document.createElement('span')
  separator.className = 'scenery-separator'
  host.replaceChildren(play, track, readout, separator, weather)

  function render() {
    const minutes = value.minutes
    thumb.style.left = `${(minutes / 1440) * 100}%`
    const moon = moonAt(minutes)
    setPixelIcon(thumb, moon ? 'moon' : 'sun')
    const clock = clockText(minutes),
      slot = SLOTS[slotAt(minutes / 60)]
    time.textContent = clock
    note.textContent = `${slot} · ${weatherLabels[value.weather]}`
    track.setAttribute('aria-valuenow', String(Math.floor(minutes)))
    track.setAttribute('aria-valuetext', `${clock} ${slot}`)
    for (const button of buttons) {
      const kind = button.dataset.kind as WeatherKind
      button.setAttribute('aria-pressed', String(kind === value.weather))
      if (kind === 'clear') setPixelIcon(button.querySelector('img')!, moon ? 'moon' : 'sun')
    }
  }
  function renderPlay() {
    setPixelIcon(playIcon, playing ? 'pause' : 'play')
    play.classList.toggle('is-playing', playing)
    play.setAttribute('aria-label', playing ? '暂停' : '播放一天')
    play.title = playing ? '暂停（空格）' : '播放：一分钟走完一天（空格）'
  }
  function setMinutes(minutes: number) {
    value.minutes = ((minutes % 1440) + 1440) % 1440
    render()
    events.change(value)
  }

  let frame = 0,
    last = 0
  function tick(t: number) {
    frame = requestAnimationFrame(tick)
    // 切到后台再回来不追那段时间
    const dt = last ? Math.min(0.1, (t - last) / 1000) : 0
    last = t
    setMinutes(value.minutes + dt * PLAY_PER_SECOND)
  }
  function start() {
    if (playing) return
    playing = true
    last = 0
    frame = requestAnimationFrame(tick)
    renderPlay()
    events.playing(true)
  }
  function stop() {
    if (!playing) return
    playing = false
    cancelAnimationFrame(frame)
    renderPlay()
    events.playing(false)
  }
  play.onclick = () => (playing ? stop() : start())

  // 拖轨道：按下就跳到那一刻，拖着走；停掉播放
  const pointerMinutes = (event: PointerEvent) => {
    const r = band.getBoundingClientRect()
    const f = Math.min(1, Math.max(0, (event.clientX - r.left) / r.width))
    return Math.min(1439, Math.round(f * 1440))
  }
  track.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return
    event.preventDefault()
    track.setPointerCapture(event.pointerId)
    stop()
    setMinutes(pointerMinutes(event))
  })
  track.addEventListener('pointermove', (event) => {
    if (track.hasPointerCapture(event.pointerId)) setMinutes(pointerMinutes(event))
  })

  // 键盘：赏景时 ← → 换时刻，空格总是播放、暂停（和游戏里的空格一样）。进赏景时焦点在「返回选镇」上，
  // 空格要是照常去按它，一按就退出了；按钮用回车按
  let spaceTaken = false
  document.addEventListener('keydown', (event) => {
    if (!active || event.altKey || event.ctrlKey || event.metaKey) return
    const target = event.target instanceof Element ? event.target : null
    if (target?.closest('input, textarea, select, [contenteditable]')) return
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      event.preventDefault()
      stop()
      const step = (event.shiftKey ? 60 : STEP) * (event.key === 'ArrowLeft' ? -1 : 1)
      const unit = Math.abs(step)
      const from =
        step > 0 ? Math.floor(value.minutes / unit) * unit : Math.ceil(value.minutes / unit) * unit
      setMinutes(from + step)
    } else if (event.key === ' ') {
      event.preventDefault()
      spaceTaken = true
      if (event.repeat) return
      if (playing) stop()
      else start()
    }
  })
  // 按钮在空格松开时才算按下：按下时已经切过播放，松开时不再去按焦点所在的按钮
  document.addEventListener('keyup', (event) => {
    if (event.key === ' ' && spaceTaken) {
      spaceTaken = false
      event.preventDefault()
    }
  })

  render()
  renderPlay()
  return {
    get value(): Readonly<Scenery> {
      return value
    },
    get playing() {
      return playing
    },
    /** 景色条摆到这个时刻和天气，不通知（预览已经是这副样子：进赏景时接着存档停下的那一刻） */
    setValue(next: Readonly<Scenery>) {
      value.minutes = ((next.minutes % 1440) + 1440) % 1440
      value.weather = next.weather
      render()
    },
    /** 轨道换成这座镇的天色 */
    setTheme(light: LightPalette) {
      const g = band.getContext('2d')
      if (!g) return
      for (let x = 0; x < band.width; x++) {
        const hour = (x / (band.width - 1)) * 24
        const top = skyTone(light.top, hour, 0.45),
          sky = skyTone(light.sky, hour, 0.55)
        const gradient = g.createLinearGradient(0, 0, 0, band.height)
        gradient.addColorStop(0, `rgb(${top.join(' ')})`)
        gradient.addColorStop(1, `rgb(${sky.join(' ')})`)
        g.fillStyle = gradient
        g.fillRect(x, 0, 1, band.height)
      }
    },
    /** 进出赏景：出去时停掉播放，按键不再管 */
    setActive(on: boolean) {
      active = on
      if (!on) stop()
    },
  }
}
