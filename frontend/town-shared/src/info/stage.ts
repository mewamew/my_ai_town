// 角色卡顶上的小人：用地图同一套像素画法画全身，由样式放大；在路上时原地迈步，平时站着。
// 画法是地图加载时登记的（portraits.ts），登记之前不画。
import { villagerArt } from '../portraits'

/** 迈一步的时间，和捏人预览一样快 */
const STEP_MS = 180

export function createStage(canvas: HTMLCanvasElement) {
  const still = matchMedia('(prefers-reduced-motion: reduce)')
  let key = ''
  let drawn = ''
  let walking = false
  let frame = 0
  let timer = 0

  function draw() {
    const art = villagerArt()
    canvas.hidden = !art || !key
    if (!art || !key) return
    const [w, h] = art.frame
    canvas.width = w
    canvas.height = h
    const ctx = canvas.getContext('2d')!
    ctx.clearRect(0, 0, w, h)
    art.drawFrame(ctx, art.lookOf(key), 'down', walking && !still.matches ? frame : 0, 0, 0)
    drawn = key
  }
  function tick() {
    timer = 0
    // 卡片收起（没有布局）时停下，下一份名册重新打开时再走
    if (!walking || still.matches || !canvas.offsetParent) return
    frame = (frame + 1) % 4
    draw()
    timer = window.setTimeout(tick, STEP_MS)
  }

  return {
    /** 出图编号和在不在路上；每份名册调一次，没变就不重画 */
    set(next: string, moving: boolean) {
      const restart = moving !== walking
      walking = moving
      key = next
      if (restart) frame = 0
      if (restart || drawn !== key) draw()
      if (walking && !timer) timer = window.setTimeout(tick, STEP_MS)
    },
    clear() {
      key = ''
      drawn = ''
      walking = false
      window.clearTimeout(timer)
      timer = 0
      draw()
    },
  }
}
