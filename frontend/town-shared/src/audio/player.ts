import { button, el } from '../dom'
import { pixelIcon } from '../game/pixel'
import { isCompact, onBack } from '../platform'
import type { MusicControls, MusicState } from './music'
import './player.css'

/** 播放器与设置页共用同一音量控件；范围值按百分数显示，控制器保持 0–1。 */
export function musicVolumeControl(music: MusicControls) {
  const root = el('div', '', 'music-volume')
  root.setAttribute('data-music-control', '')
  const range = el('input')
  range.type = 'range'
  range.min = '0'
  range.max = '100'
  range.step = '1'
  range.setAttribute('aria-label', '音乐音量')
  const value = el('output')
  root.append(range, value)
  range.addEventListener('input', () => music.setVolume(Number(range.value) / 100))
  const sync = (volume: number) => {
    const n = String(Math.round(volume * 100))
    range.value = n
    value.textContent = `${n}%`
    range.setAttribute('aria-valuetext', `${n}%`)
  }
  sync(music.state().volume)
  return { el: root, sync }
}

/** 只订阅同一播放器，不拥有音频。弹卡不暂停世界，关闭时也不改变播放。 */
export function createMusicPlayer(
  music: MusicControls,
  options: {
    host: HTMLElement
    compactHost?: HTMLElement
    placement: 'game' | 'home'
    onOpen?: () => void
  }
) {
  const abort = new AbortController()
  const { signal } = abort
  const trigger = button('', () => (panel.hidden ? open() : close()), 'music-entry')
  trigger.dataset.placement = options.placement
  trigger.setAttribute('data-music-control', '')
  trigger.setAttribute('data-map-control', '')
  trigger.setAttribute('aria-haspopup', 'dialog')
  trigger.setAttribute('aria-expanded', 'false')
  const entryText = el('span', '', 'music-entry-title')
  const compactText = el('span', '音乐', 'music-entry-short')
  trigger.append(pixelIcon('note'), entryText, compactText)
  const panel = el('section', '', 'music-player')
  panel.id = `music-player-${options.placement}`
  panel.hidden = true
  panel.setAttribute('role', 'dialog')
  panel.setAttribute('data-music-control', '')
  panel.setAttribute('aria-label', '音乐播放器')
  panel.setAttribute('data-map-control', '')
  trigger.setAttribute('aria-controls', panel.id)
  const header = el('header')
  const heading = el('h2', '小镇电台')
  heading.tabIndex = -1
  const dismiss = button('关闭', () => close(), 'music-player-close')
  dismiss.setAttribute('aria-label', '关闭音乐播放器')
  header.append(heading, dismiss)
  const title = el('strong', '', 'music-player-title')
  const status = el('p', '', 'music-player-status')
  status.setAttribute('role', 'status')
  status.setAttribute('aria-live', 'polite')
  const transport = el('div', '', 'music-transport')
  const previous = button('上一首', music.previous)
  const toggle = button('播放音乐', music.toggle, 'music-play-toggle')
  const next = button('下一首', music.next)
  transport.append(previous, toggle, next)
  const selectLabel = el('label', '', 'music-track-label')
  selectLabel.append(el('span', '选择曲目'))
  const select = el('select')
  select.setAttribute('aria-label', '音乐曲目')
  const placeholder = new Option('选择一首音乐…', '')
  placeholder.disabled = true
  select.add(placeholder)
  for (const track of music.tracks) select.add(new Option(track.title, track.id))
  select.addEventListener('change', () => music.selectTrack(select.value), { signal })
  selectLabel.append(select)
  const automatic = button('恢复自动选曲', music.setAutomatic, 'music-automatic')
  const mode = el('p', '', 'music-mode-note')
  const volume = musicVolumeControl(music)
  const volumeRow = el('div', '', 'music-volume-row')
  volumeRow.append(el('span', '音乐音量'), volume.el)
  panel.append(header, title, status, transport, selectLabel, automatic, mode, volumeRow)
  document.body.append(panel)

  let releaseBack = () => {}
  function place() {
    const host = isCompact() && options.compactHost ? options.compactHost : options.host
    if (trigger.parentElement !== host) host.append(trigger)
    if (panel.hidden || isCompact()) return
    const r = trigger.getBoundingClientRect()
    panel.style.setProperty('--music-top', `${Math.round(r.bottom + 8)}px`)
    panel.style.setProperty('--music-right', `${Math.max(12, innerWidth - r.right)}px`)
  }
  function close(restoreFocus = true) {
    if (panel.hidden) return
    panel.hidden = true
    trigger.setAttribute('aria-expanded', 'false')
    releaseBack()
    releaseBack = () => {}
    if (restoreFocus) trigger.focus({ preventScroll: true })
  }
  function open() {
    options.onOpen?.()
    panel.hidden = false
    trigger.setAttribute('aria-expanded', 'true')
    place()
    heading.focus({ preventScroll: true })
    releaseBack = onBack(() => {
      close()
      return true
    })
  }
  // 地图捕获指针来平移；音乐入口、滑杆与按键不能漏给地图。
  for (const node of [trigger, panel])
    for (const type of ['pointerdown', 'dblclick', 'wheel'] as const)
      node.addEventListener(type, (event) => event.stopPropagation(), { signal })
  panel.addEventListener(
    'keydown',
    (event) => {
      if (event.key === 'Escape' && !event.defaultPrevented) {
        event.preventDefault()
        close()
      }
      // Tab 留给音乐控件，字母键不触发化身移动；统一下拉框在捕获阶段接管选择键。
      event.stopPropagation()
    },
    { signal }
  )
  document.addEventListener(
    'pointerdown',
    (event) => {
      const target = event.target
      if (
        !panel.hidden &&
        target instanceof Element &&
        !panel.contains(target) &&
        !trigger.contains(target) &&
        !target.closest('.ui-select-layer')
      )
        close(false)
    },
    { capture: true, signal }
  )
  document.addEventListener(
    'keydown',
    (event) => {
      if (event.key !== 'Escape' || event.defaultPrevented || panel.hidden) return
      event.preventDefault()
      event.stopPropagation()
      close()
    },
    { signal }
  )
  window.addEventListener('resize', place, { signal })
  const render = (state: MusicState) => {
    const currentTitle = state.track?.title ?? '等待音乐播放'
    const note = !state.enabled
      ? '音乐已关闭'
      : state.blocked
        ? '点击播放，开始收听'
        : state.loading
          ? '正在载入音乐…'
          : state.error || (state.track ? '正在播放' : '等待音乐播放')
    entryText.textContent = state.enabled && state.track ? currentTitle : note
    trigger.title = `${note}${state.track ? `：${currentTitle}` : ''} · 打开音乐播放器`
    trigger.setAttribute('aria-label', trigger.title)
    trigger.classList.toggle('music-off', !state.enabled)
    title.textContent = currentTitle
    status.textContent = note
    status.classList.toggle('music-error', !!state.error)
    toggle.textContent = state.blocked || !state.enabled ? '播放音乐' : '关闭音乐'
    toggle.setAttribute('aria-pressed', String(state.enabled && !state.blocked))
    previous.disabled = next.disabled = music.tracks.length < 2
    automatic.disabled = state.mode === 'auto'
    automatic.textContent = state.mode === 'auto' ? '正在自动选曲' : '恢复自动选曲'
    mode.textContent =
      state.mode === 'auto'
        ? '自动：音乐随小镇、天气与剧情变化。'
        : '手选：这首曲目循环播放，直到改选或恢复自动。'
    if (document.activeElement !== select)
      select.value = state.selectedTrack?.id ?? state.track?.id ?? ''
    volume.sync(state.volume)
  }
  const unsubscribe = music.subscribe(render)
  render(music.state())
  place()
  return {
    close,
    dispose() {
      releaseBack()
      unsubscribe()
      abort.abort()
      trigger.remove()
      panel.remove()
    },
  }
}
