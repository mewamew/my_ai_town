import { button, el } from 'town-shared/dom'
import { errorText } from 'town-shared/format'
import library from '../../../../data/mapgen/templates.json'
import { limits } from '../../../../scripts/mapgen/spec.mjs'
import { type CreatorContext } from './creatorContext'
import { createPlacePicker, type CreatorLimits } from './creatorPicker'
import { invalidate } from './creatorPreview'
import { stepStatus } from './creatorSteps'
import type { Options } from './creatorTypes'

// 地点模板和上限是页面自带的数据，和管理服务、手机上页面里的生成器读同一份
// （data/mapgen/templates.json、scripts/mapgen/spec.mjs），地点选择器不等管理服务，服务停了也照样能选。
// 要问管理服务的只有模型能不能用：每次打开建镇页都问，在首页设定里刚连好的模型这里马上能用。

/** 新建小镇时预先点好的地点 */
const defaultCounts: Record<string, number> = {
  home: 4,
  plaza: 1,
  library: 1,
  canteen: 1,
  park: 1,
  clinic: 1,
}

/** 页面自带的地点模板和上限；模型状态要问过管理服务才有 */
export function localOptions(): Options {
  return {
    templates: library.templates.map(({ kind, name, outdoor }) => ({ kind, name, outdoor })),
    limits: limits as CreatorLimits,
  }
}

/** 建地点选择器，点好新小镇默认的几处；建镇页创建时调用一次 */
export function mountPlacePicker(c: CreatorContext) {
  const { templates } = c.options
  c.el<HTMLTextAreaElement>('town-description').maxLength = c.options.limits.max_description
  c.picker = createPlacePicker(
    c.el('town-places'),
    c.el('town-selected'),
    c.el('town-counts'),
    [...templates].sort((a, b) => Number(a.kind === 'area') - Number(b.kind === 'area')),
    c.options.limits,
    () => invalidate(c),
    (text) => c.status(text)
  )
  c.picker.set(
    templates.flatMap((t) =>
      defaultCounts[t.kind] ? [{ kind: t.kind, size: 'medium', count: defaultCounts[t.kind] }] : []
    )
  )
  c.panel.querySelector<HTMLButtonElement>('[data-place-filter][aria-selected="true"]')?.click()
}

/**
 * 一句话规划用哪个模型；没连上时在原处放「连接模型」，连好当场能用，写好的描述不丢。
 * 没问到（多半是小镇服务停了）就写明原因、给「重试」。
 */
export function renderModel(c: CreatorContext) {
  const { model } = c.options
  const line = c.el('generation-model')
  if (c.modelProblem)
    line.replaceChildren(
      el('span', `没问到模型状态：${c.modelProblem}。`),
      button('重试', () => void refreshModel(c))
    )
  else if (!model) line.replaceChildren()
  else if (model.available)
    line.replaceChildren(
      el('span', `用 ${model.provider} · ${model.model} 理解你的描述，点生成时调用一次。`)
    )
  else
    line.replaceChildren(
      el('span', '还没连接模型：连上一个模型服务，就能用一句话建镇。'),
      ...(c.connectModel ? [button('连接模型', () => void connect(c))] : [])
    )
  for (const id of ['parse-town', 'refine-town', 'reparse-town'])
    c.el<HTMLButtonElement>(id).disabled = c.busy || !model?.available
  if (c.currentStep === 'basics' && !c.busy) c.status(stepStatus(c))
}

async function connect(c: CreatorContext) {
  if ((await c.connectModel?.()) === 'connected') await refreshModel(c)
}

/** 问管理服务模型能不能用 */
export async function refreshModel(c: CreatorContext) {
  try {
    c.options.model = (await c.request<Pick<Options, 'model'>>('/options')).model
    c.modelProblem = undefined
  } catch (error) {
    c.options.model = undefined
    c.modelProblem = errorText(error)
  }
  renderModel(c)
}
