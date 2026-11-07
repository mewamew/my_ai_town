import type { GameMap } from '../gameMap'
import type { ClientMsg, ServerMsg } from '../protocol'
import {
  isWeatherKind,
  weatherLabels,
  weatherQuality,
  readWeatherPreferences,
  saveWeatherPreferences,
  type WeatherView,
} from './types'
import { $, query } from '../dom'
import './panel.css'
import { pixelIcon, setPixelIcon, type PixelName } from '../game/pixel'

/** 时钟牌上的天气图：晴天夜里画月亮 */
function weatherIcon(kind: string, night: boolean): PixelName {
  if (kind === 'clear') return night ? 'moon' : 'sun'
  if (kind === 'overcast') return 'cloud'
  if (kind === 'thunderstorm') return 'storm'
  if (kind === 'snow') return 'snow'
  return 'rain'
}
/** 「D2 21:30」是不是夜里（19 点到次日 5 点） */
function isNight(clock: string) {
  const hour = Number(/\s(\d{1,2}):\d{2}$/.exec(clock)?.[1] ?? 12)
  return hour >= 19 || hour < 5
}

/** 控件只提交草案；显示的天气始终来自服务器回执或名册。 */
export function createWeatherPanel(
  send: (msg: ClientMsg) => void,
  map: GameMap,
  /** 游戏界面（3D 外壳，已不用）：和 2D 一样画像素天气图 */
  _game: boolean
) {
  // 时钟牌最前面的天气图，点开换天气
  const trigger = document.createElement('button')
  trigger.type = 'button'
  trigger.className = 'weather-trigger'
  trigger.hidden = true
  trigger.setAttribute('aria-haspopup', 'dialog')
  const icon = pixelIcon('sun')
  trigger.append(icon)
  $('hud-clock').prepend(trigger)
  const dialog = document.createElement('dialog')
  dialog.className = 'weather-dialog'
  dialog.setAttribute('aria-labelledby', 'weather-title')
  dialog.innerHTML = `<header><div><small>小镇环境</small><h2 id="weather-title">天气</h2></div><button type="button" data-close aria-label="关闭天气面板">关闭</button></header>
    <p data-current></p><p class="weather-hint" data-hint></p>
    <fieldset data-controls><legend>设置世界天气</legend><label>固定为 <select data-kind aria-label="固定天气类型"></select></label>
    <div class="weather-actions"><button type="button" data-fixed>应用固定天气</button><button type="button" data-natural>恢复自然变化</button></div>
    <p class="weather-hint">自然模式每隔 45–90 个游戏分钟检查一次。暂停时停止推进；手动设置立即生效。</p></fieldset>
    <p data-status role="status" aria-live="polite"></p>
    <fieldset><legend>本机画面</legend><label><input type="checkbox" data-effects> 显示天气与昼夜效果</label>
    <label>粒子数量 <select data-quality aria-label="粒子数量"><option value="low">低</option><option value="medium">中</option><option value="high">高</option></select></label>
    <label><input type="checkbox" data-motion> 减少动态效果</label><label><input type="checkbox" data-flash> 显示轻微雷光</label>
    <p class="weather-hint">关闭效果只改变画面，居民仍能感知天气。系统的“减少动态效果”设置也会生效。</p></fieldset>`
  document.body.append(dialog)
  const get = <T extends Element>(name: string) => query<T>(dialog, `[data-${name}]`)
  const kind = get<HTMLSelectElement>('kind')
  for (const [value, label] of Object.entries(weatherLabels)) kind.add(new Option(label, value))
  let view: WeatherView | undefined
  let night = false
  let worldId: string | undefined
  let online = false
  let ready = false
  let pending: Extract<ClientMsg, { type: 'set_weather' }> | undefined
  let timer: ReturnType<typeof setTimeout> | undefined
  const status = get<HTMLElement>('status')
  const prefs = readWeatherPreferences()
  get<HTMLInputElement>('effects').checked = prefs.effects
  get<HTMLSelectElement>('quality').value = prefs.quality
  get<HTMLInputElement>('motion').checked = prefs.reduceMotion
  get<HTMLInputElement>('flash').checked = prefs.flash
  const savePrefs = () =>
    saveWeatherPreferences({
      effects: get<HTMLInputElement>('effects').checked,
      quality: weatherQuality(get<HTMLSelectElement>('quality').value),
      reduceMotion: get<HTMLInputElement>('motion').checked,
      flash: get<HTMLInputElement>('flash').checked,
    })
  for (const name of ['effects', 'quality', 'motion', 'flash'])
    get<HTMLElement>(name).onchange = savePrefs
  function render() {
    trigger.hidden = !map.weatherSupported || !view
    if (trigger.hidden && dialog.open) dialog.close()
    if (view) {
      setPixelIcon(icon, weatherIcon(view.kind, night))
      const label = `${weatherLabels[view.kind]}${view.mode === 'fixed' ? ' · 固定' : ''}`
      trigger.setAttribute('aria-label', `天气：${label}`)
      trigger.title = `${label}：点开可以换成固定的天气，或者恢复自然变化`
      get<HTMLElement>('current').textContent =
        `当前：${weatherLabels[view.kind]} · ${view.mode === 'natural' ? '自然变化' : '固定天气'}`
      get<HTMLElement>('hint').textContent =
        view.kind === 'thunderstorm'
          ? '雷暴期间停止露天久留和聊天。移动、进屋、吃喝与救助仍然允许。'
          : '普通雨雪不会强制中断活动。居民可以继续，也可以选择室内地点。'
    }
    get<HTMLFieldSetElement>('controls').disabled = !online || !ready || !view || !!pending
  }
  function accept(next?: WeatherView | null) {
    if (!next || next.world_id !== worldId) return
    if (view?.world_id === next.world_id && view.revision > next.revision) return
    view = next
    render()
  }
  function waitForReceipt() {
    clearTimeout(timer)
    timer = setTimeout(() => {
      if (!pending) return
      status.replaceChildren(document.createTextNode('尚未收到保存回执。'))
      const retry = document.createElement('button')
      retry.textContent = '重试同一请求'
      retry.onclick = () => {
        if (online && pending) {
          send(pending)
          status.textContent = '正在确认保存结果…'
          waitForReceipt()
        }
      }
      status.append(retry)
    }, 6000)
  }
  function submit(mode: 'fixed' | 'natural') {
    if (!online || !ready || !view || pending) return
    pending = {
      type: 'set_weather',
      world_id: view.world_id,
      request_id: crypto.randomUUID(),
      expected_revision: view.revision,
      mode,
      ...(mode === 'fixed' && isWeatherKind(kind.value) ? { kind: kind.value } : {}),
    }
    status.textContent = '正在保存…'
    render()
    send(pending)
    waitForReceipt()
  }
  trigger.onclick = () => {
    if (view) kind.value = view.kind
    dialog.showModal()
  }
  get<HTMLButtonElement>('close').onclick = () => dialog.close()
  get<HTMLButtonElement>('fixed').onclick = () => submit('fixed')
  get<HTMLButtonElement>('natural').onclick = () => submit('natural')
  return {
    handleMsg(msg: ServerMsg) {
      if (msg.type === 'world_settings') {
        if (worldId !== msg.state.world_id) {
          view = undefined
          pending = undefined
          clearTimeout(timer)
          status.textContent = ''
        }
        worldId = msg.state.world_id
        ready = msg.state.ready
        render()
      }
      if (msg.type === 'roster') {
        const wasNight = night
        night = isNight(msg.clock)
        if (night !== wasNight && view) render()
        accept(msg.environment)
        return false
      }
      // 命令没能执行（格式错误、命令过多）：结束等待，写明原因
      if (msg.type === 'error' && pending && msg.request_id === pending.request_id) {
        pending = undefined
        clearTimeout(timer)
        status.textContent = msg.message
        render()
        return true
      }
      if (msg.type !== 'weather_saved') return false
      if (msg.world_id !== worldId || msg.request_id !== pending?.request_id) return true
      pending = undefined
      clearTimeout(timer)
      accept(msg.environment)
      status.textContent = msg.message
      render()
      return true
    },
    connected() {
      online = true
      ready = false
      render()
      if (pending) waitForReceipt()
    },
    disconnected() {
      online = false
      ready = false
      render()
      if (pending) status.textContent = '连接中断，重连后可重试同一请求。'
    },
    onReset() {
      view = undefined
      pending = undefined
      ready = false
      clearTimeout(timer)
      status.textContent = ''
      render()
    },
    dispose() {
      clearTimeout(timer)
      trigger.remove()
      dialog.remove()
    },
  }
}
