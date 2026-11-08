import { query } from 'town-shared/dom'
import type { CreatorContext } from './creatorContext'
import { creatorSteps, type CreatorStep } from './creatorTypes'

// 建镇页的四个步骤：基础、环境、地点、预览。当前步骤展开，做完的步骤收成一行摘要。
// 一句话描述时第一步就是描述框，底部主按钮「生成小镇」；预览这一步左栏写说明，能改一句再生成。

export function syncStepControls(c: CreatorContext) {
  const index = creatorSteps.indexOf(c.currentStep)
  const describing = c.languageMode && c.currentStep === 'basics'
  const previewing = c.currentStep === 'preview'
  const previous = c.el<HTMLButtonElement>('creator-prev-step')
  const next = c.el<HTMLButtonElement>('creator-next-step')
  previous.hidden = index === 0
  previous.disabled = c.busy
  next.hidden = describing || c.currentStep === 'places' || previewing
  next.disabled = c.busy
  next.textContent = c.currentStep === 'basics' ? '下一步：环境' : '下一步：地点'
  c.el('parse-town').hidden = !describing
  c.el('generate-town').hidden = c.currentStep !== 'places'
  c.el('reroll-town').hidden = !previewing || !c.draft
  c.el('save-town').hidden = !previewing
  c.el('save-only').hidden = !previewing || !c.draft
  c.el<HTMLButtonElement>('save-only').disabled = c.busy || c.saving
  // 说明、改名、改一句只跟着当前这一版预览
  c.el('creator-result').hidden = !previewing || !c.draft
  c.el('creator-refine').hidden = !c.languageMode
  c.el('preview-hint').textContent = c.languageMode
    ? '满意就进镇。想改哪里，在下面说一句；只想换个排法，点「换一张布局」。可以拖动、缩放地图看看。'
    : '满意就进镇；不满意点「换一张布局」，设置不变，只重新排地形和布局。可以拖动、缩放地图看看。'
}

function stepSummary(c: CreatorContext, step: CreatorStep) {
  // 模型还没回话：表单里还是默认值，不当成规划结果写出来
  if (c.parsing) return '正在理解…'
  const chosen = (id: string) => c.select(id).selectedOptions[0]?.text ?? ''
  if (step === 'basics') return c.input('town-name').value
  if (step === 'environment')
    return `${chosen('town-style')} · 树丛${chosen('town-vegetation')} · ${chosen('town-resources')}${c.select('town-settlement').value === 'town' ? '' : ` · ${chosen('town-settlement')}`}`
  const count = (c.picker?.selection() ?? []).reduce((n, p) => n + p.count, 0)
  return step === 'places' ? `${count} 处地点` : ''
}

const stepHints: Record<CreatorStep, string> = {
  basics: '起个名字，下一步选环境。',
  environment: '选择地形、树丛和生活条件。',
  places: '选择小镇里的建筑与公共空间。',
  preview: '检查预览里的布局，满意就进镇。',
}

/** 底部状态里这一步的说明；到了预览这一步还没有草稿时，提示回去生成 */
export function stepStatus(c: CreatorContext) {
  if (c.currentStep === 'preview' && !c.draft)
    return c.languageMode
      ? '还没有可保存的预览，回到第一步点「生成小镇」。'
      : '还没有可保存的预览，请返回地点步骤生成。'
  // 一句话描述不填名字（由模型起名），第一步只要写描述
  if (c.currentStep === 'basics' && c.languageMode) {
    if (c.modelProblem) return '还没问到模型状态，点上面的「重试」再问一次。'
    return c.options.model && !c.options.model.available
      ? '先连接一个模型，再点「生成小镇」。'
      : '写一句话或点一个例子，再点「生成小镇」，几秒钟就好。'
  }
  return stepHints[c.currentStep]
}

/** 步骤行：当前步骤只显示展开的内容，做完的收成一行摘要 */
export function renderStepRows(c: CreatorContext) {
  const index = creatorSteps.indexOf(c.currentStep)
  c.panel.querySelectorAll<HTMLButtonElement>('[data-creator-step]').forEach((button) => {
    const own = button.dataset.creatorStep as CreatorStep
    const done = creatorSteps.indexOf(own) < index
    button.hidden = own === c.currentStep
    button.classList.toggle('is-done', done)
    query(button, 'small').textContent = done ? stepSummary(c, own) : (button.dataset.hint ?? '')
  })
}

export function setCreatorStep(c: CreatorContext, step: CreatorStep) {
  c.currentStep = step
  c.panel.dataset.creatorStep = step
  c.panel.querySelectorAll<HTMLElement>('[data-creator-panel]').forEach((section) => {
    section.hidden = section.dataset.creatorPanel !== step
  })
  renderStepRows(c)
  c.status(stepStatus(c))
  syncStepControls(c)
  // 换了一步从顶上看起：手机上整页滚动，停在上一步滚到的位置会看不到这一步的标题
  c.panel.scrollTop = 0
  c.panel.querySelector('.creator-main')?.scrollTo(0, 0)
}

/** 上一步、下一步和步骤标题的点击 */
export function wireSteps(c: CreatorContext) {
  c.panel.querySelectorAll<HTMLButtonElement>('[data-creator-step]').forEach((button) => {
    button.onclick = () => setCreatorStep(c, button.dataset.creatorStep as CreatorStep)
  })
  c.el('creator-prev-step').onclick = () => {
    const index = creatorSteps.indexOf(c.currentStep)
    if (index > 0) setCreatorStep(c, creatorSteps[index - 1])
  }
  c.el('creator-next-step').onclick = () => {
    if (c.currentStep === 'basics' && !c.input('town-name').reportValidity()) return
    const index = creatorSteps.indexOf(c.currentStep)
    if (index < creatorSteps.indexOf('places')) setCreatorStep(c, creatorSteps[index + 1])
  }
}
