import type { SettingsPage } from '../settingsCenter'
import type { GameMap } from '../gameMap'
import { el } from '../dom'
import { segmented, settingRow, switchControl } from './controls'
import './display.css'
import {
  android,
  isTouch,
  onWindowFullscreen,
  windowFullscreen,
  windowFullscreenAvailable,
  windows,
} from '../platform'
import {
  effectiveQuality,
  qualityLabels,
  qualityNotes,
  saveQuality,
  storedQuality,
  type QualityChoice,
} from '../quality'

// 显示：全屏 / 界面动画 / 文字大小 / 地图俯角，全部存本机 localStorage、即时生效，不走后端。
// 与原「游戏设置」对话框（gamePreferences）同一份存储键；入口已合并进设定中心。
const KEY = 'town-player-preferences'

let textSize = '标准',
  motion = '系统'
try {
  const saved = JSON.parse(localStorage.getItem(KEY) ?? '{}')
  if (['标准', '较大'].includes(saved.textSize)) textSize = saved.textSize
  if (['系统', '减少'].includes(saved.motion)) motion = saved.motion
} catch {
  /* 存储不可用时用默认值 */
}

/** 把本机偏好应用到 DOM（启动时调用一次恢复原设置；2D 忽略皮肤值） */
function applyPlayerPreferences() {
  document.body.dataset.uiText = textSize
  document.body.classList.toggle('reduce-ui-motion', motion === '减少')
}

function persist() {
  applyPlayerPreferences()
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) ?? '{}')
    localStorage.setItem(KEY, JSON.stringify({ ...saved, textSize, motion }))
  } catch {
    /* 存储不可用时仅本次生效 */
  }
}

export function createDisplayPage(map: GameMap | undefined, game: boolean): SettingsPage {
  // 设定中心初始化即建页：顺便恢复原「游戏设置」对话框实例化时的启动副作用
  applyPlayerPreferences()
  const root = el('section', '', 'spage')
  root.append(el('h2', '显示'))
  const rows = el('div', '', 'set-rows')
  const status = el('p', '', 'page-status')
  status.setAttribute('role', 'status')

  // mac、Windows 版切的是应用壳的窗口全屏，换页面不退出、不盖住开着的设定；浏览器里用网页全屏
  const native = windowFullscreenAvailable()
  const fullscreen = switchControl('全屏', async (on) => {
    if (native) {
      fullscreen.set((await windowFullscreen(on)) ?? false)
      return
    }
    try {
      if (on) await document.documentElement.requestFullscreen()
      else if (document.fullscreenElement) await document.exitFullscreen()
    } catch {
      status.textContent = '当前窗口不支持全屏，可使用应用的放大按钮。'
    }
    syncFullscreen()
  })
  const syncFullscreen = () => {
    if (native) void windowFullscreen().then((on) => fullscreen.set(!!on))
    else fullscreen.set(!!document.fullscreenElement)
  }
  fullscreen.el.disabled = !native && !document.fullscreenEnabled
  if (native) onWindowFullscreen((on) => fullscreen.set(on))
  else document.addEventListener('fullscreenchange', syncFullscreen)
  const fullscreenNote = native
    ? windows
      ? '也可以按 F11'
      : '也可以按 ⌃⌘F'
    : fullscreen.el.disabled
      ? '当前内嵌窗口不支持网页全屏'
      : ''
  // 手机应用本来就是全屏的，没有这一项
  if (!android) rows.append(settingRow('全屏', fullscreenNote, fullscreen.el))

  const motionChoice = segmented(
    '界面动画',
    [
      { value: '系统', label: '跟随系统' },
      { value: '减少', label: '减少' },
    ],
    (value) => {
      motion = value
      persist()
      motionChoice.set(motion)
    }
  )
  motionChoice.set(motion)
  rows.append(settingRow('界面动画', '「减少」会关掉面板滑入、提示卡弹出这类动画', motionChoice.el))

  const textChoice = segmented(
    '文字大小',
    ['标准', '较大'].map((value) => ({ value, label: value })),
    (value) => {
      textSize = value
      persist()
      textChoice.set(textSize)
    }
  )
  textChoice.set(textSize)
  rows.append(settingRow('文字大小', '角色卡、事件栏和各页面的字号', textChoice.el))

  // 地图俯角只有 2D 立体场景有；地图没实现这两个方法时整行不显示
  const PITCHES = [30, 50, 70]
  const pitchChoice = segmented(
    '地图俯角',
    PITCHES.map((degrees) => ({ value: String(degrees), label: `${degrees}°` })),
    (value) => {
      map?.setMapPitch?.(Number(value))
      syncPitch()
    }
  )
  const pitchRow = settingRow(
    '地图俯角',
    isTouch() ? '也可以两根手指同时上下拖动' : '也可以在地图上按住右键拖动',
    pitchChoice.el
  )
  const syncPitch = () => {
    const current = map?.mapPitch?.()
    pitchRow.hidden = current === undefined
    pitchChoice.set(String(current))
  }
  rows.append(pitchRow)

  // 画质：只在有立体场景的地图上有意义；即时生效
  const qualityChoice = segmented(
    '画质',
    (['auto', 'high', 'mid', 'low'] as const).map((value) => ({
      value,
      label: qualityLabels[value],
    })),
    (value) => {
      const choice = value as QualityChoice
      saveQuality(choice)
      map?.setRenderQuality?.(effectiveQuality(choice))
      syncQuality()
    }
  )
  const qualityRow = settingRow('画质', qualityNotes.auto, qualityChoice.el)
  const qualityNote = qualityRow.querySelector('.set-row-desc')
  const syncQuality = () => {
    const choice = storedQuality()
    qualityChoice.set(choice)
    if (qualityNote) qualityNote.textContent = qualityNotes[choice]
  }
  qualityRow.hidden = !map?.setRenderQuality
  rows.append(qualityRow)
  syncQuality()

  root.append(rows, status)
  const onShow = () => {
    syncFullscreen()
    syncPitch()
  }

  return {
    id: 'display',
    group: 'game',
    navLabel: '显示',
    title: '显示',
    el: root,
    isDirty: () => false,
    save: () => {},
    discard: () => {},
    onShow,
  }
}
