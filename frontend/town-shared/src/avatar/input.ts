/** 采集移动方向并交给后端推进位置。E 触发主动作，hotkeys 是其他按键。
 *  cycle 是 Tab / Shift+Tab 换当前对象，返回 false 表示没有可换的，Tab 照常移动焦点。
 *  按住 Shift 是奔跑：方向键和点地图走过去都算，running() 给出现在是否按着。 */
export function createWalkingInput(
  enabled: () => boolean,
  emit: (direction: [number, number]) => void,
  primary: () => void,
  signal: AbortSignal,
  hotkeys: Record<string, () => void> = {},
  cycle?: (step: 1 | -1) => boolean
) {
  const keys = new Set<string>()
  let composing = false
  let shift = false
  const editing = () => {
    const e = document.activeElement
    return (
      !!document.querySelector('dialog[open]') ||
      (e instanceof HTMLElement &&
        (e.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(e.tagName)))
    )
  }
  const send = () =>
    emit([
      Number(keys.has('KeyD')) - Number(keys.has('KeyA')),
      Number(keys.has('KeyS')) - Number(keys.has('KeyW')),
    ])
  function stop() {
    keys.clear()
    shift = false
    emit([0, 0])
  }
  window.addEventListener(
    'keydown',
    (e) => {
      if (e.key === 'Shift') shift = !composing && !editing()
      if (composing || e.isComposing || editing() || e.metaKey || e.ctrlKey || e.altKey) return
      const hotkey = hotkeys[e.code]
      if (hotkey) {
        if (!e.repeat) {
          e.preventDefault()
          stop()
          hotkey()
        }
        return
      }
      // 换对象不影响走路，不停下
      if (e.code === 'Tab' && cycle?.(e.shiftKey ? -1 : 1)) {
        e.preventDefault()
        return
      }
      if (!enabled()) return
      if (e.code === 'KeyE' && !e.repeat) {
        e.preventDefault()
        stop()
        primary()
        return
      }
      if (!['KeyW', 'KeyA', 'KeyS', 'KeyD'].includes(e.code)) return
      e.preventDefault()
      // 失焦后保持按键，不会在恢复焦点时自动开始走动。
      if (!e.repeat) {
        keys.add(e.code)
        send()
      }
    },
    { signal }
  )
  window.addEventListener(
    'keyup',
    (e) => {
      if (e.key === 'Shift') shift = false
      if (keys.delete(e.code)) send()
    },
    { signal }
  )
  window.addEventListener('blur', stop, { signal })
  document.addEventListener('visibilitychange', stop, { signal })
  document.addEventListener(
    'focusin',
    () => {
      if (editing()) stop()
    },
    { signal }
  )
  document.addEventListener(
    'compositionstart',
    () => {
      composing = true
      stop()
    },
    { signal }
  )
  document.addEventListener(
    'compositionend',
    () => {
      composing = false
    },
    { signal }
  )
  const timer = window.setInterval(() => {
    if (!keys.size) return
    if (!enabled() || editing() || document.hidden) stop()
    else send()
  }, 100)
  signal.addEventListener('abort', () => {
    clearInterval(timer)
    keys.clear()
  })
  return { stop, running: () => shift }
}
