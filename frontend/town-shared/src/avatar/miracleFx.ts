// 施展神力的那一下：一道光从上方落在对方身上，约一秒后散开。画在地图上方的一层，跟着对方
// 此刻在屏幕上的位置走；对方不在画面里就不画。系统设了减少动画时整个跳过，结果只看提示。
import type { GameMap } from '../gameMap'
import { el } from '../dom'

/** 光停留多久（毫秒），和 style.css 里的动画时长一致 */
const DURATION = 1100

export function playMiracle(map: GameMap, host: HTMLElement, id: string) {
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return
  if (!map.getScreenBox?.(id)) return
  const fx = el('div', '', 'miracle-fx')
  fx.setAttribute('aria-hidden', 'true')
  for (let i = 0; i < 5; i++) fx.append(el('i'))
  host.append(fx)
  const start = performance.now()
  const frame = (now: number) => {
    const box = map.getScreenBox?.(id)
    if (!box || now - start > DURATION || !fx.isConnected) {
      fx.remove()
      return
    }
    const area = host.getBoundingClientRect()
    fx.style.left = `${box.x - area.left}px`
    fx.style.top = `${box.feet - area.top}px`
    fx.style.setProperty('--fx-half', `${Math.max(16, box.half)}px`)
    requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
}
