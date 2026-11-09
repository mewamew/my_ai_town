import type { Atlas } from 'town-shared/mapDocument'
import type { ServerMsg } from 'town-shared/protocol'
import { el } from 'town-shared/svg'
import { OUTDOOR_SPACE, roomRect } from './map/grid'
import { WEATHER_LEVELS } from './map/weatherLevels'
import {
  readWeatherPreferences,
  weatherPreferencesEvent,
  type WeatherKind,
  type WeatherPreferences,
  type WeatherView,
} from 'town-shared/weather/types'

/** 平面图上的天气和昼夜：只在立体场景起不来、退回平面像素地面时使用。
 *  天气只读服务器事实；图集仅用于遮住摊开的室内房间。 */
export class WeatherLayer {
  readonly layer = el('g', {
    'data-weather-layer': '',
    'pointer-events': 'none',
    'aria-hidden': 'true',
  })
  private defs = el('defs')
  private tint: SVGRectElement
  private precipitation: SVGGElement
  private rain = el('path', { fill: 'none', stroke: '#759cae', 'stroke-linecap': 'round' })
  private snow = el('path', { fill: 'none', stroke: '#fffef4', 'stroke-linecap': 'round' })
  private wet: SVGRectElement
  private light: SVGRectElement
  private prefs = readWeatherPreferences()
  private media = matchMedia('(prefers-reduced-motion: reduce)')
  private abort = new AbortController()
  private observer: MutationObserver
  private view?: WeatherView
  /** 选镇页赏景：没有世界，天气是玩家点的（见 setScenery） */
  private scenery?: WeatherKind
  private minutes = 0
  private speed = 0
  private frame = 0
  private lastTime = 0
  private elapsed = 0
  private disposed = false
  private synchronize = true
  private current = [0, 0, 0]
  private target = [0, 0, 0]
  constructor(
    private svg: SVGSVGElement,
    atlas: Atlas
  ) {
    const W = atlas.canvas.width,
      H = atlas.canvas.height
    const id = `weather-mask-${crypto.randomUUID()}`
    const mask = el('mask', {
      id,
      maskUnits: 'userSpaceOnUse',
      x: -200,
      y: -200,
      width: W + 400,
      height: H + 400,
    })
    mask.append(el('rect', { x: 0, y: 0, width: W, height: H, fill: 'white' }))
    for (const space of atlas.spaces) {
      if (space.id === OUTDOOR_SPACE) continue
      const r = roomRect(space)
      mask.append(
        el('rect', {
          x: r.x - 5,
          y: r.y - 5,
          width: r.w + 10,
          height: r.h + 10,
          fill: 'black',
          'data-indoor-mask': space.id,
        })
      )
    }
    this.defs.append(mask)
    const area = { x: -200, y: -200, width: W + 400, height: H + 400 }
    this.tint = el('rect', { ...area, fill: '#18273f', opacity: 0 })
    this.wet = el('rect', { ...area, fill: '#7090a3', opacity: 0 })
    this.light = el('rect', { ...area, fill: '#f4edc5', opacity: 0 })
    this.precipitation = el('g', { mask: `url(#${id})` })
    this.precipitation.append(this.wet, this.rain, this.snow, this.light)
    this.layer.append(this.defs, this.tint, this.precipitation)
    window.addEventListener(
      weatherPreferencesEvent,
      (e) => {
        this.prefs = (e as CustomEvent<WeatherPreferences>).detail
        this.refresh()
      },
      { signal: this.abort.signal }
    )
    this.media.addEventListener('change', () => this.refresh(), { signal: this.abort.signal })
    document.addEventListener('visibilitychange', () => this.refresh(), {
      signal: this.abort.signal,
    })
    // 相机移动时静态效果也要重画，但不因此开始持续动画。
    this.observer = new MutationObserver(() => this.request())
    this.observer.observe(svg, { attributes: true, attributeFilter: ['viewBox'] })
  }
  handleMsg(msg: ServerMsg) {
    if (msg.type !== 'roster') return
    const snap = this.synchronize || this.view?.world_id !== msg.environment?.world_id
    this.synchronize = false
    this.view = msg.environment
    this.minutes = msg.sim_minutes
    this.speed = msg.speed
    this.refresh(snap)
  }
  setSpeed(speed: number) {
    this.speed = speed
    this.refresh()
  }
  /** 赏景：画这个时刻和天气，雨雪照常落、几秒内过渡 */
  setScenery(minutes: number, kind: WeatherKind) {
    this.scenery = kind
    this.minutes = minutes
    this.refresh()
  }
  reset() {
    this.view = undefined
    this.speed = 0
    this.refresh()
  }
  disconnect() {
    this.synchronize = true
    this.speed = 0
    this.refresh()
  }
  private get animated() {
    return (
      (this.speed > 0 || !!this.scenery) &&
      !this.prefs.reduceMotion &&
      !this.media.matches &&
      !document.hidden
    )
  }
  private refresh(snap = false) {
    const kind = this.view?.kind ?? this.scenery
    const level = kind ? WEATHER_LEVELS[kind] : undefined
    const hour = (((this.minutes % 1440) + 1440) % 1440) / 60
    const night =
      hour < 5 || hour >= 21
        ? 0.2
        : hour < 7
          ? (0.2 * (7 - hour)) / 2
          : hour > 18
            ? (0.2 * (hour - 18)) / 3
            : 0
    // 云把夜色再压暗一点，最阴的雷暴加深 0.09
    const cloud = (level?.cloud ?? 0) * 0.1
    this.target =
      this.prefs.effects && kind
        ? [level?.rain ?? 0, level?.snow ?? 0, Math.min(0.27, night + cloud)]
        : [0, 0, 0]
    if (snap || !this.animated) {
      this.current = [...this.target]
      cancelAnimationFrame(this.frame)
      this.frame = 0
      this.lastTime = 0
    }
    this.request()
  }
  private request() {
    if (!this.disposed && !document.hidden && !this.frame)
      this.frame = requestAnimationFrame((now) => this.draw(now))
  }
  private draw(now: number) {
    this.frame = 0
    const dt = this.lastTime ? Math.min((now - this.lastTime) / 1000, 0.05) : 0
    this.lastTime = now
    if (this.animated) {
      this.elapsed += dt
      this.current = this.current.map((v, i) =>
        Math.abs(v - this.target[i]) < 0.002
          ? this.target[i]
          : v + (this.target[i] - v) * Math.min(1, dt * 3)
      )
    }
    this.tint.setAttribute('opacity', String(this.current[2]))
    this.wet.setAttribute('opacity', String(this.current[0] * 0.065))
    const [x, y, w, h] = this.svg.getAttribute('viewBox')!.split(/[ ,]+/).map(Number)
    const scale = w / Math.max(this.svg.clientWidth, 400)
    const total = this.prefs.quality === 'low' ? 70 : this.prefs.quality === 'high' ? 300 : 160
    const fraction = (v: number) => v - Math.floor(v)
    const path = (density: number, isSnow: boolean) => {
      const parts: string[] = []
      for (let i = 0; i < Math.round(total * density); i++) {
        const px = x + fraction(i * 0.61803398875 + this.elapsed * (isSnow ? 0.012 : -0.025)) * w
        const py = y + fraction(i * 0.41421356237 + this.elapsed * (isSnow ? 0.055 : 0.5)) * h
        parts.push(
          `M${px.toFixed(1)} ${py.toFixed(1)}l${isSnow ? '.01' : (-3 * scale).toFixed(1)} ${isSnow ? '0' : (11 * scale).toFixed(1)}`
        )
      }
      return parts.join('')
    }
    this.rain.setAttribute('d', path(this.current[0], false))
    this.rain.setAttribute('stroke-width', String(1.1 * scale))
    this.rain.setAttribute('opacity', '.72')
    this.snow.setAttribute('d', path(this.current[1], true))
    this.snow.setAttribute('stroke-width', String(3.3 * scale))
    // 默认无雷光；显式启用且允许动画时，每 13 秒一次缓慢、低亮度变化。
    const phase = this.elapsed % 13
    const glow =
      (this.view?.kind ?? this.scenery) === 'thunderstorm' &&
      this.prefs.flash &&
      this.prefs.effects &&
      this.animated &&
      phase < 1.4
        ? Math.sin((phase / 1.4) * Math.PI) * 0.075
        : 0
    this.light.setAttribute('opacity', String(glow))
    if (
      this.animated &&
      (this.current[0] || this.current[1] || this.current.some((v, i) => v !== this.target[i]))
    )
      this.request()
    else this.lastTime = 0
  }
  dispose() {
    this.disposed = true
    cancelAnimationFrame(this.frame)
    this.observer.disconnect()
    this.abort.abort()
    this.layer.remove()
  }
}
