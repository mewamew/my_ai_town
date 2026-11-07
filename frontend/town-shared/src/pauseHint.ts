// 地图上方居中的提示：世界暂停时提示怎样开始，自动快进时写明正在快进；空格键开始或暂停世界。
import { gameIcon } from './game/icons'
import { isTouch } from './platform'

/** 实际速度达到选定速度的这么多倍才提示快进：服务端约一秒半加速到这里，几秒的空档不闪提示 */
const FAST_SHOWN = 8

/** 空格给别的东西用的时候不接：输入框、对话框、聚焦的按钮和链接、地图上聚焦的道具。
 *  时钟牌旁的开始/暂停钮例外，点完它再按空格就是开始或暂停。 */
function spaceIsFree(target: EventTarget | null, map: HTMLElement) {
  if (document.querySelector('dialog[open]')) return false
  // 地图页没显示（设定中心、道具页等整页替换了它）
  if (!map.getClientRects().length) return false
  if (!(target instanceof HTMLElement || target instanceof SVGElement)) return true
  if (target === document.body || target.closest('#speeds')) return true
  if (target instanceof HTMLElement && target.isContentEditable) return false
  return !target.closest('input, textarea, select, button, a[href], [tabindex], [role="button"]')
}

export function installPauseHint(
  map: HTMLElement,
  /** 选一个速度，和点开始/暂停钮一样；返回 false 表示这次没有立刻生效（比如先要连模型） */
  choose: (speed: number) => boolean,
  /** 运行时的世界速度 */
  normalSpeed: number
) {
  const hint = document.createElement('div')
  hint.className = 'pause-hint'
  hint.hidden = true
  const key = document.createElement('kbd')
  key.textContent = '空格'
  // 触屏没有空格键
  if (isTouch()) hint.replaceChildren('世界已暂停，点左上角的 ▶ 开始')
  else hint.replaceChildren('世界已暂停，点左上角的 ▶ 或按 ', key, ' 开始')
  // 快进提示和暂停提示在同一个位置，但不挤开别的提示、不算遮挡地图：它常来常走，不能带着别的东西跳
  const fast = document.createElement('div')
  fast.className = 'fast-hint'
  fast.hidden = true
  fast.append(gameIcon('fast', true), '快进中 · 现在没人走动或说话')
  map.append(hint, fast)
  let speed: number | null = null
  window.addEventListener('keydown', (e) => {
    if (e.code !== 'Space' || e.repeat || e.ctrlKey || e.metaKey || e.altKey || e.shiftKey) return
    if (speed === null || e.isComposing || !spaceIsFree(e.target, map)) return
    e.preventDefault()
    const next = speed === 0 ? normalSpeed : 0
    if (choose(next)) update(next, next)
  })
  function update(next: number, pace: number) {
    speed = next
    hint.hidden = next !== 0
    fast.hidden = next === 0 || pace < next * FAST_SHOWN
  }
  return {
    /** 每份名册调用：选定速度与这一拍的实际速度 */
    update,
  }
}
export type PauseHint = ReturnType<typeof installPauseHint>
