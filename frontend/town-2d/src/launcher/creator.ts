import { query } from 'town-shared/dom'
import { onBack } from 'town-shared/platform'
import { creatorTemplate } from './creatorTemplate'
import './creator.css'
import { CreatorContext } from './creatorContext'
import { fill, spec, syncResourceEffect, syncStyle } from './creatorForm'
import { mountPlacePicker, refreshModel } from './creatorOptions'
import { mountChoiceCards } from './creatorPicker'
import { dropPreview, idlePlaceholder, invalidate, placeholder, preview } from './creatorPreview'
import { clearReport } from './creatorReport'
import { saveDraft } from './creatorSave'
import { setCreatorStep, syncStepControls, wireSteps } from './creatorSteps'
import type { Draft } from './creatorTypes'

// 创建小镇：一句话描述（默认）或逐项参数 → 后端生成草稿 → 预览 → 保存并进镇。
// 状态在 CreatorContext；步骤、表单、地点选项、生成预览、说明、保存各在一个 creator*.ts。

/** 一句话描述（大门）和自己一项项选两种方式：第一步换内容，作废进行中的生成 */
export function setMode(c: CreatorContext, mode: 'language' | 'parameters') {
  c.languageMode = mode === 'language'
  c.panel.dataset.mode = mode
  c.el('creator-language').hidden = !c.languageMode
  c.el('basics-title').textContent = c.languageMode ? '说说你想要的小镇' : '给小镇起个名字'
  c.el('basics-hint').textContent = c.languageMode
    ? '写一句话：这是个什么地方、大家怎么过日子。地点的名字、写给村民的背景、住进来的人都按它来。'
    : '接下来自己选环境和地点，最后看生成的布局。'
  invalidate(c)
  if (!c.draft && !c.busy) c.el('creator-preview').replaceChildren(idlePlaceholder(c))
  syncStepControls(c)
}

/** 表单里的输入、生成、取消、清空，两种方式的切换，例子，以及预览后的改名、改一句、换一种理解 */
function wireForm(c: CreatorContext) {
  const name = c.input('town-name')
  c.el('creator-form').addEventListener('input', (event) => {
    // 名字不影响布局：改名不作废预览，保存时把名字一起交给管理服务
    if (event.target === name) {
      c.input('draft-name').value = name.value
      return
    }
    invalidate(c)
  })
  c.input('draft-name').addEventListener('input', () => {
    name.value = c.input('draft-name').value
    name.dataset.edited = '1'
  })
  c.select('town-resources').addEventListener('input', () => syncResourceEffect(c))
  c.el('creator-form').onsubmit = (event) => {
    event.preventDefault()
    c.input('town-seed').value = '-1'
    void preview(c)
  }
  c.el('parse-town').onclick = () => void preview(c, 'parse')
  c.el('reparse-town').onclick = () => void preview(c, 'parse')
  const refine = c.el<HTMLTextAreaElement>('refine-text')
  c.el('refine-town').onclick = () => {
    if (!refine.value.trim()) {
      c.status('先写一句想改什么，比如「再加一座灯塔」。')
      refine.focus()
      return
    }
    void preview(c, 'refine')
  }
  c.el('reroll-town').onclick = () => {
    c.input('town-seed').value = '-1'
    void preview(c)
  }
  c.el('cancel-generation').onclick = () => {
    invalidate(c)
    dropPreview(c)
    c.el('creator-preview').replaceChildren(placeholder('已取消生成。'))
    setCreatorStep(c, c.languageMode ? 'basics' : 'places')
    c.status('已取消生成。')
  }
  c.el('single-area').onclick = () => {
    fill(c, { ...spec(c), places: [{ kind: 'area', count: 1, size: 'large' }], constraints: [] })
    invalidate(c)
  }
  c.el('clear-places').onclick = () => {
    c.picker?.set([])
    invalidate(c)
  }
  c.panel.querySelectorAll<HTMLButtonElement>('[data-mode]').forEach((b) => {
    b.onclick = () => setMode(c, b.dataset.mode === 'language' ? 'language' : 'parameters')
  })
  const description = c.el<HTMLTextAreaElement>('town-description')
  c.panel.querySelectorAll<HTMLButtonElement>('[data-example]').forEach((b) => {
    b.onclick = () => {
      description.value = b.dataset.example ?? ''
      description.dispatchEvent(new Event('input', { bubbles: true }))
      description.focus()
    }
  })
  c.panel.querySelectorAll<HTMLButtonElement>('[data-place-filter]').forEach((button) => {
    button.onclick = () => {
      const filter = button.dataset.placeFilter
      c.panel
        .querySelectorAll<HTMLButtonElement>('[data-place-filter]')
        .forEach((item) => item.setAttribute('aria-selected', String(item === button)))
      c.panel.querySelectorAll<HTMLElement>('[data-place-group]').forEach((item) => {
        item.hidden = item.dataset.placeGroup !== filter
      })
    }
  })
}

/** 新小镇的默认名字：不和已有的重名（默认小镇就叫「我的小镇」） */
function freshName(taken: string[]) {
  for (let n = 1; ; n++) {
    const name = n === 1 ? '新小镇' : `新小镇 ${n}`
    if (!taken.includes(name)) return name
  }
}

export function initCreator<D extends Draft = Draft>(
  onSaved: (id: string, problem?: string) => void,
  /** 已有小镇的名字 */
  takenNames: () => string[] = () => [],
  /** 首页设定里的连接模型弹层，返回 'connected' 表示连上了 */
  connectModel?: () => Promise<string>,
  /** 保存后直接进这个小镇；出错时抛出，建镇页留着说明原因 */
  enterTown?: (id: string) => Promise<void>
) {
  const open = document.createElement('button')
  open.className = 'create-town-button'
  open.textContent = '＋ 创建小镇'
  query(document, '[data-create-town-slot]').append(open)
  const panel = document.createElement('section')
  panel.className = 'town-creator'
  panel.hidden = true
  panel.setAttribute('aria-label', '创建小镇')
  panel.innerHTML = creatorTemplate
  document.body.append(panel)
  const launcher = query(document, '.map-launcher')
  const c = new CreatorContext<D>(panel)
  c.connectModel = connectModel
  const name = c.input('town-name')
  name.addEventListener('input', () => (name.dataset.edited = '1'))
  // 每次打开都从一句话描述开始：上一次的预览、说明、描述和状态都不留
  const show = () => {
    launcher.hidden = true
    panel.hidden = false
    invalidate(c)
    dropPreview(c)
    clearReport(c)
    c.el<HTMLTextAreaElement>('town-description').value = ''
    c.el<HTMLTextAreaElement>('refine-text').value = ''
    c.worldview = ''
    c.mapping = []
    c.notes = []
    c.residents = []
    delete name.dataset.edited
    name.value = freshName(takenNames())
    setMode(c, 'language')
    setCreatorStep(c, 'basics')
    void refreshModel(c)
  }
  open.onclick = show
  const leave = () => {
    dropPreview(c)
    panel.hidden = true
    launcher.hidden = false
  }
  c.el('creator-back').onclick = () => {
    if (c.saving) return
    invalidate(c)
    leave()
  }
  // 安卓返回键：先退回上一步，第一步时回到地图选择；保存中不动
  onBack(() => {
    if (panel.hidden) return false
    const previous = c.el<HTMLButtonElement>('creator-prev-step')
    if (c.saving) return true
    if (!previous.hidden && !previous.disabled) previous.click()
    else c.el('creator-back').click()
    return true
  })
  wireForm(c)
  mountPlacePicker(c)
  wireSteps(c)
  c.el('save-town').onclick = () => saveDraft(c, leave, onSaved, enterTown)
  c.el('save-only').onclick = () => saveDraft(c, leave, onSaved)
  const invalidatePreview = () => {
    invalidate(c)
    dropPreview(c)
  }
  mountChoiceCards(panel)
  syncStyle(c)
  syncResourceEffect(c)
  setMode(c, 'language')
  setCreatorStep(c, 'basics')
  return { open: show, invalidatePreview }
}
