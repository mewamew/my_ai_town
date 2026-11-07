// 角色卡 → 人设：平时在卡片里只看预览，点「编辑」卡片拉宽，左原文右预览（info/tabs.ts）。
import type { ServerMsg } from '../protocol'
import { statusLine } from '../dom'
import { $, htmlText } from '../settings/page'
import { renderMarkdown } from '../settings/markdown'
import type { CardPageDeps, TabPage } from './tabs'

export function createPersonaPage(deps: CardPageDeps): TabPage {
  const el = document.createElement('section')
  el.className = 'spage'
  const name = htmlText(deps.resident.name)
  // 左侧编辑人设原文，右侧显示 Markdown 预览
  el.innerHTML = `
    <h2>${name} · 人设</h2>
    <p class="hint">写给${name}自己看的设定：性格、说话方式、来小镇之前的经历，可以用 # 写小标题。保存后，${name}下一次想事情时就会用上。</p>
    <div class="persona-tabs">
      <button type="button" data-t="edit" class="on">原文</button>
      <button type="button" data-t="preview">预览</button>
    </div>
    <div class="persona-wrap">
      <div class="persona-split">
        <textarea id="persona-text" spellcheck="false" rows="16"></textarea>
        <div class="persona-preview"></div>
      </div>
    </div>
    <div class="page-status"></div>`
  const ta = $<HTMLTextAreaElement>(el, '#persona-text')
  const preview = $<HTMLElement>(el, '.persona-preview')
  const wrap = $<HTMLElement>(el, '.persona-wrap')
  const status = $<HTMLElement>(el, '.page-status')

  let saved = ''
  let dirty = false

  const setStatus = statusLine(status)

  ta.addEventListener('input', () => {
    dirty = ta.value !== saved
    preview.innerHTML = renderMarkdown(ta.value)
    deps.onDirty()
  })
  // 窄屏页签：原文 / 预览切换（宽屏两栏同显，页签由 CSS 隐藏）
  for (const b of el.querySelectorAll<HTMLButtonElement>('.persona-tabs button')) {
    b.onclick = () => {
      wrap.classList.toggle('show-preview', b.dataset.t === 'preview')
      el.querySelectorAll('.persona-tabs button').forEach((x) => x.classList.toggle('on', x === b))
    }
  }

  function fill(text: string) {
    ta.value = text
    preview.innerHTML = renderMarkdown(text)
  }

  return {
    title: `${deps.resident.name}的人设`,
    el,
    isDirty: () => dirty,
    save() {
      // 回执对应的是发出去的这份原文；等回执时又改的内容仍算未保存
      const text = ta.value
      // 先写「保存中…」：没连上时回执立刻回来，结果不能被它盖掉
      setStatus('保存中…')
      deps.save({ type: 'set_persona', resident: deps.resident.id, text }, (ok, message) => {
        if (ok) {
          saved = text
          dirty = ta.value !== saved
          deps.onDirty()
          setStatus(`✓ ${deps.resident.name}的人设已保存，下一次想事情时就会用上。`, 'ok')
        } else setStatus('✗ ' + message, 'drop')
      })
    },
    discard() {
      dirty = false
      fill(saved)
      setStatus('已放弃修改，恢复为已保存的人设')
      deps.onDirty()
    },
    onShow() {
      deps.send({ type: 'get_agent_config', resident: deps.resident.id })
    },
    handleMsg(msg: ServerMsg) {
      if (msg.type !== 'agent_config' || msg.resident_id !== deps.resident.id) return
      saved = msg.persona
      // 正在编辑时不覆盖（保存后的回读内容一致，覆盖也无感）
      if (!dirty && document.activeElement !== ta) fill(saved)
    },
  }
}
