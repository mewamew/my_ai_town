import type { ThoughtView } from '../protocol'

export function createThoughtView(box: HTMLElement) {
  let lastThoughtKey: string | null = ''
  let thoughtAgeEl: HTMLElement | null = null
  // ---- 想法泡：角色卡小人旁边，只放想法原文和「N 分钟前」；没有想法就不显示。
  // 新想法到达强调一次，年龄按模拟时钟 ----
  function ageText(thoughtMinutes: number, nowMinutes: number): string {
    const a = Math.floor(thoughtMinutes),
      b = Math.floor(nowMinutes)
    if (!Number.isFinite(a) || !Number.isFinite(b)) return ''
    const d = Math.max(0, b - a)
    if (d < 1) return '刚刚'
    if (d < 60) return `${Math.floor(d)} 分钟前`
    return `${(d / 60).toFixed(d < 600 ? 1 : 0)} 小时前`
  }

  function renderThought(t: ThoughtView | undefined, nowMinutes: number) {
    const key = t ? `${t.clock}|${t.text}` : ''
    if (key === lastThoughtKey) {
      if (t && thoughtAgeEl) thoughtAgeEl.textContent = ageText(t.sim_minutes, nowMinutes)
      return
    }
    const firstRender = lastThoughtKey === '' || lastThoughtKey === null
    lastThoughtKey = key
    box.replaceChildren()
    thoughtAgeEl = null
    box.hidden = !t
    if (!t) return
    box.className = 'thought-box'

    const text = document.createElement('div')
    text.className = 'thought-text'
    text.textContent = `「${t.text}」`
    const foot = document.createElement('div')
    foot.className = 'thought-foot'
    foot.textContent = ageText(t.sim_minutes, nowMinutes)
    thoughtAgeEl = foot
    box.append(text, foot)
    if (!firstRender) {
      box.classList.add('flash')
      box.addEventListener('animationend', () => box.classList.remove('flash'), { once: true })
    }
  }

  return {
    render: renderThought,
    reset() {
      lastThoughtKey = null
      thoughtAgeEl = null
    },
    clear() {
      box.replaceChildren()
      box.hidden = true
      lastThoughtKey = ''
      thoughtAgeEl = null
    },
  }
}
