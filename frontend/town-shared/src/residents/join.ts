// 加入小镇：预览、命名、选住宅、提交。加入用操作编号去重，断线后按编号查询结果。
import { button, el } from '../dom'
import { displayClock } from '../format'
import { newId } from '../ids'
import type { JoinOutcome, JoinPreview } from '../protocol'
import { templateKey } from '../portraits'
import { field, input, marker, personaDetails } from './form'
import type { ResidentsContext, ViewHandle } from './state'

export function startJoin(ctx: ResidentsContext, id: string) {
  const { state, deps } = ctx
  state.view = { kind: 'join', id }
  state.editor = null
  state.preview = null
  state.detail = null
  deps.send({ type: 'get_resident_template', template_id: id })
  deps.send({ type: 'preview_resident_join', template_id: id })
  ctx.render()
}

/** 姓名、住宅、问题列表与提交按钮；改姓名或住宅就重新校验 */
function joinControls(ctx: ResidentsContext, id: string, p: JoinPreview) {
  const { state, deps } = ctx
  const name = input(p.name, '本次入村姓名', 20)
  const home = el('select')
  for (const h of p.free_homes)
    home.append(new Option(h.name, h.locale, false, h.locale === p.home))
  const hasHomes = (state.population?.homes.length ?? 0) > 0
  if (!p.free_homes.length)
    home.append(new Option(hasHomes ? '没有空置住宅' : '不分配住宅', '', true, true))
  const refresh = () => {
    state.preview = null
    deps.send({
      type: 'preview_resident_join',
      template_id: id,
      name: name.value,
      home: home.value || undefined,
    })
    ctx.render()
  }
  name.onchange = refresh
  home.onchange = refresh
  const problems = () => {
    const list = el('ul', '', 'drop')
    for (const problem of p.problems) list.append(el('li', problem))
    return list
  }
  const submit = (label: string) => {
    const confirm = button(
      label,
      () => {
        const population = state.population
        if (!p.ok || state.pending || !population) return
        const op_id = newId()
        state.pending = { op_id, template_id: id }
        const model = ctx.joinModel()
        deps.send({
          type: 'join_resident',
          op_id,
          world_id: population.world_id,
          template_id: id,
          template_version: p.template_version,
          name: name.value.trim() || p.name,
          home: home.value || undefined,
          ...(model ? { model: { provider: model.provider, model: model.model } } : {}),
        })
        ctx.render()
      },
      'primary'
    )
    confirm.disabled = !p.ok || !!state.pending
    const actions = el('div', '', 'row')
    actions.append(confirm)
    return actions
  }
  return { name, home, hasHomes, problems, submit }
}

function joinForm(ctx: ResidentsContext, id: string, p: JoinPreview) {
  const c = joinControls(ctx, id, p)
  const left = el('div')
  left.append(field('名字', c.name, '镇上不能有两个同名的人，重名就换一个'))
  if (c.hasHomes) left.append(field('住宅', c.home, '默认住第一间空房，可以改'))
  else left.append(el('p', '这里没有住宅，大家都在同一片地方活动。', 'dim'))
  const facts = el('div', '', 'rv-facts')
  const model = ctx.joinModel()
  facts.append(
    el('p', `出现位置：${p.entry_name || '加入时随机选择有效位置'}`),
    el('p', `当前世界时间：${displayClock(p.clock)}`),
    el(
      'p',
      model
        ? `用 ${model.name} · ${model.model} 思考，以后可以在角色卡的「模型」里单独换。`
        : '还没连模型：先住下，连上后才开始行动。',
      'dim'
    )
  )
  left.append(facts)
  if (p.problems.length) left.append(c.problems())
  left.append(c.submit(ctx.state.pending ? '提交中…' : '确认加入'))
  return left
}

export function renderJoin(ctx: ResidentsContext, id: string): ViewHandle {
  const { state } = ctx
  const box = el('div', '', 'rv-detail')
  box.append(button('← 返回', () => ctx.showTemplate(id)))
  const template = state.detail?.template
  const head = el('div', '', 'rv-head')
  // 加入前先看一眼这个人长什么样
  if (template)
    head.append(
      marker(
        templateKey({ template_id: template.template_id, appearance: template.fields.appearance }),
        template.fields.appearance.marker
      )
    )
  head.append(el('h2', `加入小镇${template ? ` · ${template.fields.name}` : ''}`))
  box.append(head)
  if (!state.preview) {
    box.append(el('p', '正在校验…', 'dim'))
    return { root: box }
  }
  const split = el('div', '', 'rv-split')
  const right = el('div', '', 'rv-sticky')
  right.append(personaDetails(state.detail?.persona ?? '读取中…').details)
  split.append(joinForm(ctx, id, state.preview), right)
  box.append(split)
  return { root: box }
}

/** 加入结果：成功就回到地图，告诉玩家谁搬进来了；失败留在预览并重新校验 */
export function finishJoin(ctx: ResidentsContext, outcome: JoinOutcome) {
  const { state, deps } = ctx
  if (state.pending?.op_id !== outcome.op_id) return
  state.pending = null
  if (outcome.ok) {
    state.notice = { text: outcome.message, residentId: outcome.resident_id }
    if (outcome.resident_id) {
      ctx.close()
      deps.onJoined([outcome], [], ctx.joinModel())
    } else {
      deps.send({ type: 'get_population' })
      ctx.setTab('roster')
    }
    return
  }
  state.notice = { text: `未加入：${outcome.message}`, warning: true }
  // 失败停留在预览，保留本次填写；重新校验一次拿到最新住宅列表
  if (state.view.kind === 'join')
    deps.send({
      type: 'preview_resident_join',
      template_id: state.view.id,
      name: state.preview?.name,
      home: state.preview?.home,
    })
  ctx.render()
}
