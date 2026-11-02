import { placeAbove, type LabelRect } from './labelLayout'
import type { AvatarPrompt } from 'town-shared/gameMap'
import { el } from 'town-shared/svg'
import { uprightRatio } from './upright'
import { isTouch } from 'town-shared/platform'
// 化身模式的地图提示标签：只画当前对象一个，画在它上方，随地图一起缩放平移；
// 附近不止一个对象时在后面写「Tab 换人 1 / 7」。点击由 camera 按 data-prompt 命中。

const PAD = 7,
  HEIGHT = 22,
  KEY_WIDTH = 16,
  GAP = 5,
  LIFT = 54

type PositionOf = (p: AvatarPrompt) => [number, number] | undefined

export class PromptLayer {
  readonly layer = el('g', { class: 'avatar-prompts' })
  /** 标签尺寸按 1 = 放大 12 倍时的大小设计；渲染器按缩放倍率传入，整图时放大到可读 */
  private scale = 1
  private last: { prompts: AvatarPrompt[]; positionOf: PositionOf } | null = null
  clear() {
    this.last = null
    this.layer.replaceChildren()
  }
  setScale(scale: number) {
    if (scale === this.scale) return
    this.scale = scale
    if (this.last) this.update(this.last.prompts, this.last.positionOf)
  }
  update(prompts: AvatarPrompt[], positionOf: PositionOf) {
    this.layer.replaceChildren()
    this.last = { prompts, positionOf }
    const index = Math.max(
      0,
      prompts.findIndex((p) => p.focused)
    )
    const p = prompts[index]
    const pos = p && positionOf(p)
    if (!pos) return
    const screen = this.layer.getScreenCTM()
    const k = screen?.a ? 1 / Math.abs(screen.a) : this.scale
    // 纵向单位：地面倾斜时视口被压扁，标签按比例拉回
    const ky = k * uprightRatio(this.layer)
    const occupied: LabelRect[] = [
      ...(this.layer.ownerSVGElement?.querySelectorAll<SVGGraphicsElement>('.vn, .vv') ?? []),
    ]
      .filter(
        (e) =>
          e.getClientRects().length &&
          e.closest('[display="none"]') === null &&
          e.closest('.vgrouped') === null
      )
      .map((e) => e.getBBox())
    // 多人标签自带 translate/scale，getBBox 不含它自己的变换，要换算回地图坐标
    for (const group of this.layer.ownerSVGElement?.querySelectorAll<SVGGElement>('.vgroup') ??
      []) {
      const m = group.transform.baseVal.consolidate()?.matrix
      const b = group.getBBox()
      if (m)
        occupied.push({
          x: m.e + b.x * m.a,
          y: m.f + b.y * m.d,
          width: b.width * m.a,
          height: b.height * m.d,
        })
    }
    const g = el('g', {
      'data-prompt': p.id,
      class: `aprompt${p.key ? ' aprompt-main' : ''}${p.muted ? ' aprompt-muted' : ''}`,
    })
    const box = el('rect', { class: 'aprompt-box', rx: 6, height: HEIGHT })
    g.appendChild(box)
    this.layer.appendChild(g)
    let x = PAD
    // 触屏没有键盘：不画按键，换对象用右下的「换目标」钮
    const keys = !isTouch()
    if (p.key && keys) x += keycap(g, x, p.key, KEY_WIDTH) + GAP
    x += text(g, x, p.label, 'aprompt-text')
    // 另一件事（F 神力）只给键盘画：触屏在操作条上点「神力」
    if (p.alt && keys) {
      x += GAP * 2
      x += keycap(g, x, p.alt.key, KEY_WIDTH) + GAP
      x += text(g, x, p.alt.label, 'aprompt-text')
    }
    if (prompts.length > 1) {
      const word = prompts.every((q) => q.kind === 'person') ? '换人' : '切换'
      x += GAP * 2
      if (keys) x += keycap(g, x, 'Tab', 26) + GAP
      x += text(g, x, `${word} ${index + 1} / ${prompts.length}`, 'aprompt-more')
    }
    const width = x + PAD
    box.setAttribute('width', String(width))
    const left = pos[0] - (width * k) / 2
    const w = width * k,
      h = HEIGHT * ky
    const boxRect = placeAbove(
      { x: left, y: pos[1] - LIFT * ky, width: w, height: h },
      occupied,
      5 * ky
    )
    const y = boxRect.y
    g.setAttribute('transform', `translate(${left},${y}) scale(${k},${ky})`)
    const line = el('line', {
      x1: pos[0],
      y1: pos[1] - 20 * ky,
      x2: pos[0],
      y2: y + h,
      stroke: '#78867a',
      'stroke-width': k,
      'pointer-events': 'none',
    })
    this.layer.insertBefore(line, g)
  }
}

/** 画一个按键框，返回宽度 */
function keycap(g: SVGGElement, x: number, key: string, width: number) {
  g.append(
    el('rect', { class: 'aprompt-key', x, y: (HEIGHT - 14) / 2, width, height: 14, rx: 3 }),
    el('text', { class: 'aprompt-keytext', x: x + width / 2, y: HEIGHT / 2 }, key)
  )
  return width
}

/** 画一段文字，返回宽度（要先挂进文档才量得出） */
function text(g: SVGGElement, x: number, content: string, className: string) {
  const t = el('text', { class: className, x, y: HEIGHT / 2 }, content) as SVGTextElement
  g.appendChild(t)
  return t.getComputedTextLength()
}
