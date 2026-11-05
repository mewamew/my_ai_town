import { button, el, field, input, select } from './dom'
import type { Action, InstantEffect, BodyNeed } from './types'
const needs = [
  { id: 'fullness', label: '饱腹' },
  { id: 'energy', label: '精力' },
  { id: 'water', label: '水分' },
  { id: 'health', label: '健康' },
]
const conditions = [
  { id: 'injury', label: '受伤' },
  { id: 'illness', label: '疾病' },
  { id: 'poison', label: '中毒' },
]
const kinds = [
  { id: 'restore', label: '恢复数值' },
  { id: 'apply_condition', label: '施加身体状况' },
  { id: 'cure_condition', label: '解除身体状况' },
  { id: 'revive', label: '明确复活' },
]
export function bodyEffects(container: HTMLElement, action: Action) {
  let effects = structuredClone(action.on_complete ?? [])
  const root = el('fieldset')
  root.append(el('legend', '动作完成时的身体效果'))
  root.append(
    el(
      'p',
      '消耗品在完成时扣除和生效；中断不扣数量、不获得效果。有限补给不能同时配置每分钟恢复（可以算劳作），对他人施用不能配置每分钟效果。',
      'prop-muted'
    )
  )
  const list = el('div')
  root.append(list)
  let readers: (() => InstantEffect)[] = []
  const defaultEffect = (kind: string): InstantEffect =>
    kind === 'restore'
      ? { kind, need: 'health', amount: 25 }
      : kind === 'revive'
        ? { kind, values: [50, 50, 50, 40], clear_conditions: true }
        : kind === 'apply_condition'
          ? { kind, condition: 'poison', severity: 1 }
          : { kind: 'cure_condition', condition: 'poison' }
  function render() {
    list.replaceChildren()
    readers = []
    effects.forEach((effect, index) => {
      const row = el('div', undefined, 'prop-form-grid')
      const kind = select(kinds, effect.kind, 'instant-kind')
      row.append(field('效果', kind))
      kind.onchange = () => {
        effects = readers.map((r) => r())
        effects[index] = defaultEffect(kind.value)
        render()
      }
      let read: () => InstantEffect
      if (effect.kind === 'restore') {
        const need = select(needs, effect.need, 'instant-need')
        const amount = input(String(effect.amount), 'instant-amount', 'number')
        amount.min = '0.001'
        amount.max = '100'
        amount.step = 'any'
        row.append(field('属性', need), field('恢复点数', amount))
        read = () => ({
          kind: 'restore',
          need: need.value as BodyNeed,
          amount: Number(amount.value),
        })
      } else if (effect.kind === 'revive') {
        const values = effect.values.map((v, i) => {
          const inp = input(String(v), 'revive-' + needs[i].id, 'number')
          inp.min = '1'
          inp.max = '100'
          row.append(field('复活后' + needs[i].label, inp))
          return inp
        })
        const clear = input('', 'revive-clear', 'checkbox')
        clear.checked = effect.clear_conditions
        row.append(field('清除受伤、疾病和中毒', clear))
        read = () => {
          const [fullness, energy, water, health] = values.map((v) => Number(v.value))
          return {
            kind: 'revive',
            values: [fullness, energy, water, health],
            clear_conditions: clear.checked,
          }
        }
      } else if (effect.kind !== 'apply_condition' && effect.kind !== 'cure_condition') {
        // 产出物品、搭建、概率、定时事件和离开在道具数据里写，编辑器原样保留
        row.append(el('p', '这项效果在道具数据里编辑，这里原样保留', 'dim'))
        read = () => effect
      } else {
        const condition = select(conditions, effect.condition, 'instant-condition')
        row.append(field('身体状况', condition))
        const severity = input(
          String(effect.kind === 'apply_condition' ? effect.severity : 1),
          'instant-severity',
          'number'
        )
        severity.min = '1'
        severity.max = '3'
        severity.step = 'any'
        if (effect.kind === 'apply_condition') row.append(field('程度（叠加上限 3）', severity))
        read = () =>
          effect.kind === 'apply_condition'
            ? {
                kind: 'apply_condition',
                condition: condition.value as 'injury',
                severity: Number(severity.value),
              }
            : { kind: 'cure_condition', condition: condition.value as 'injury' }
      }
      readers.push(read)
      row.append(
        button('删除此效果', () => {
          effects = readers.map((r) => r())
          effects.splice(index, 1)
          render()
        })
      )
      list.append(row)
    })
  }
  render()
  root.append(
    button('增加完成时效果', () => {
      effects = readers.map((r) => r())
      if (effects.length < 8) effects.push(defaultEffect('restore'))
      render()
    })
  )
  const recipient = input('', 'recipient', 'checkbox')
  recipient.checked = !!action.recipient
  const rest = input('', 'rest', 'checkbox')
  rest.checked = !!action.rest
  const finite = input('', 'finite', 'checkbox')
  finite.checked = !!action.supply
  const initial = input(String(action.supply?.initial ?? 20), 'initial-supply', 'number')
  initial.min = '0'
  initial.max = '1000000'
  const cost = input(String(action.supply?.cost ?? 1), 'supply-cost', 'number')
  cost.min = '1'
  cost.max = '1000000'
  const grid = el('div', undefined, 'prop-form-grid')
  grid.append(
    field('可以对在场他人施用', recipient),
    field('属于有效休息', rest),
    field('有限补给', finite),
    field('初始份数', initial),
    field('每次消耗份数', cost)
  )
  root.append(grid)
  container.append(root)
  return () => ({
    on_complete: readers.map((r) => r()),
    recipient: recipient.checked,
    rest: rest.checked,
    supply: finite.checked
      ? { initial: Number(initial.value), cost: Number(cost.value) }
      : undefined,
  })
}
