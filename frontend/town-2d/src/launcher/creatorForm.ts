import { DEFAULT_PRESET, STYLE_PRESETS } from '../map/themes/presets'
import { type CreatorContext } from './creatorContext'
import { creatorSelectionUsage } from './creatorPicker'
import { invalidate } from './creatorPreview'
import { placeSizes, type EditableSpec, type Spec } from './creatorTypes'

// 建镇参数和表单之间的转换：从表单拼参数、把参数写回表单，以及随地图模式联动的选项。

/** 指向的地点还在不在：玩家在「地点」里删掉了某种地点，模型给的名字和位置要求就不再带上 */
function refsIn(places: { kind: string; count: number }[]) {
  const totals = new Map<string, number>()
  for (const p of places) totals.set(p.kind, (totals.get(p.kind) ?? 0) + p.count)
  return (ref: string) => {
    const [kind, index] = ref.split(':')
    const total = totals.get(kind) ?? 0
    return index === undefined ? total > 0 : Number(index) >= 1 && Number(index) <= total
  }
}

export function spec(c: CreatorContext): Spec {
  const places = c.picker?.value() ?? []
  const exists = refsIn(places)
  const names = c.languageMode
    ? Object.fromEntries(Object.entries(c.parsedNames).filter(([ref]) => exists(ref)))
    : {}
  return {
    name: c.input('town-name').value,
    seed: Number(c.input('town-seed').value),
    schema_version: 2,
    appearance_set: 'pr10-village-v1',
    view_mode: '2d',
    environment: {
      preset: c.select('town-style').value,
      vegetation: c.select('town-vegetation').value,
    },
    resources: c.select('town-resources').value,
    terrain_source: 'auto',
    // 街道是默认值，不写进参数：旧参数和新参数生成同一张图
    ...(c.select('town-settlement').value !== 'town'
      ? { settlement: c.select('town-settlement').value as 'wild' | 'ring' }
      : {}),
    places,
    ...(Object.keys(names).length ? { names } : {}),
    constraints: c.languageMode
      ? c.parsedConstraints.filter((x) => exists(x.subject) && exists(x.relative_to))
      : [],
  }
}

/** 风格卡片跟随当前表单选择。 */
export function syncStyle(c: CreatorContext) {
  const style = c.select('town-style')
  c.panel
    .querySelectorAll<HTMLButtonElement>('[data-choice-for="town-style"] button[data-value]')
    .forEach((button) =>
      button.setAttribute('aria-pressed', String(button.dataset.value === style.value))
    )
}

/** 生活条件的后果：选中后写在卡片下面，难的那几种可能让村民倒下甚至死去 */
const RESOURCE_EFFECTS: Record<string, string> = {
  'normal-life': '每户都有床、干粮和水，村民能正常过日子。',
  'no-food': '镇上没有食物：村民会越来越饿，找不到吃的会倒下，最后可能死去。',
  'no-water': '镇上没有饮水：缺水比挨饿来得快，村民会渴得倒下，最后可能死去。',
  'no-rest': '镇上没有床和座椅：村民没法好好休息，精力耗尽后干不了活、会病倒。',
  'poisoned-food': '干粮都变质了：吃了会生病，病重可能倒下甚至死去。',
}
export function syncResourceEffect(c: CreatorContext) {
  c.el('town-resources-effect').textContent =
    RESOURCE_EFFECTS[c.select('town-resources').value] ?? ''
}

/** 检查参数里的地点种类和数量，超出上限就抛出说明 */
function checkPlaces(c: CreatorContext, s: EditableSpec) {
  const { templates, limits } = c.options
  // Old saved/model-generated specs may still contain size. The picker merges them by kind;
  // the next preview recalculates compatible internal groups automatically.
  const groups = new Map<string, number>()
  for (const p of s.places) {
    if (
      !p ||
      !templates.some((t) => t.kind === p.kind) ||
      (p.size !== undefined && !placeSizes.some(([size]) => size === p.size)) ||
      !Number.isInteger(p.count) ||
      p.count < 1 ||
      p.count > (limits.max_by_kind[p.kind] ?? limits.max_same_kind)
    )
      throw Error('请检查地点种类和数量')
    groups.set(p.kind, (groups.get(p.kind) ?? 0) + p.count)
  }
  for (const [kind, count] of groups) {
    const maximum = limits.max_by_kind[kind] ?? limits.max_same_kind
    if (count > maximum) throw Error(`${c.nameOf(kind)}最多 ${maximum} 处`)
  }
  const usage = creatorSelectionUsage([...groups].map(([kind, count]) => ({ kind, count })))
  if (usage.places > limits.max_places || usage.homes > limits.max_homes)
    throw Error(`地点最多 ${limits.max_places} 处，住宅最多 ${limits.max_homes} 处`)
}

/** 把一份参数写回表单（一句话规划、编辑完整要求）；参数不合法时抛出说明 */
export function fill(c: CreatorContext, s: EditableSpec) {
  if (s.view_mode !== undefined && s.view_mode !== '2d')
    throw Error('仅支持 HD-2D，独立 3D 版本已停用')
  checkPlaces(c, s)
  c.select('town-vegetation').value = s.environment?.vegetation ?? 'medium'
  const preset = s.environment?.preset ?? ''
  c.select('town-style').value = STYLE_PRESETS.some((p) => p.id === preset)
    ? preset
    : DEFAULT_PRESET.id
  syncStyle(c)
  // 玩家自己改过名字就留着，模型重新规划时不换掉
  const name = c.input('town-name')
  if (!name.dataset.edited) name.value = s.name
  c.input('town-seed').value = String(s.seed)
  c.select('town-resources').value = s.resources
  c.select('town-settlement').value = s.settlement ?? 'town'
  c.picker?.set(s.places)
  c.parsedConstraints = s.constraints
  c.parsedNames = s.names ?? {}
  c.panel.querySelectorAll<HTMLElement>('[data-choice-for]').forEach((group) => {
    const value = c.input(group.dataset.choiceFor!).value
    group
      .querySelectorAll<HTMLButtonElement>('button[data-value]')
      .forEach((button) =>
        button.setAttribute('aria-pressed', String(button.dataset.value === value))
      )
  })
  syncResourceEffect(c)
}
