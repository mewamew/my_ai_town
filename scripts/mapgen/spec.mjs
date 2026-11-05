import { APPEARANCE_SET } from './budget.mjs'
import { STYLE_PRESETS } from '../../frontend/town-2d/src/map/themes/presets.ts'
// 2D 小镇只限地点总数、住宅数和每组（种类加尺寸）数量，不计用地、不限地标。
export const limits = {
  min_places: 1,
  max_places: 36,
  max_homes: 20,
  max_same_kind: 20,
  max_by_kind: {},
  max_constraints: 12,
  max_names: 40,
  max_name_chars: 16,
  max_description: 2000,
  capacity_mode: 'count',
}
export const maxPlacesForKind = (kind, activeLimits = limits) =>
  activeLimits.max_by_kind[kind] ?? activeLimits.max_same_kind
export const resources = ['normal-life', 'no-food', 'no-water', 'no-rest', 'poisoned-food']
// 地点之间怎么连：town 是小镇街道（默认，旧参数不带这一项）；wild 是野外小径，荒岛、野地用，
// 路和落脚点的名字里不出现「小镇」「街道」，村民走在路上看到的也是这些名字；ring 是环岛：
// 野外小径围成一圈，户外地点沿海岸排开、岛中间留空（ring.mjs），只排户外地点。
export const settlements = ['town', 'wild', 'ring']
export const MAX_SEED = 4294967295
const environmentPresets = STYLE_PRESETS.map((preset) => preset.id)
const sizes = ['small', 'medium', 'large']
export function validateSpec(value, templates) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('请填写地图要求')
  const allowed = [
    'schema_version',
    'appearance_set',
    'view_mode',
    'environment',
    'name',
    'seed',
    'style_id',
    'places',
    'names',
    'constraints',
    'resources',
    'terrain_source',
    'settlement',
  ]
  if (Object.keys(value).some((k) => !allowed.includes(k))) throw Error('地图要求包含不支持的字段')
  const spec = structuredClone(value)
  const activeLimits = limits
  if (typeof spec.name !== 'string' || !spec.name.trim() || spec.name.length > 60)
    throw Error('名称须为 1–60 个字符')
  spec.name = spec.name.trim()
  if (!Number.isInteger(spec.seed) || spec.seed < 0 || spec.seed > MAX_SEED)
    throw Error(`种子须为 0–${MAX_SEED} 的整数`)
  if (spec.view_mode !== undefined && (spec.schema_version !== 2 || spec.view_mode !== '2d'))
    throw Error('仅支持 HD-2D，独立 3D 版本已停用')
  if (spec.schema_version === 2) {
    if (
      spec.appearance_set !== APPEARANCE_SET ||
      !environmentPresets.includes(spec.environment?.preset) ||
      !['sparse', 'medium', 'dense'].includes(spec.environment.vegetation) ||
      Object.keys(spec.environment).some((k) => !['preset', 'vegetation'].includes(k))
    )
      throw Error('环境或资源集不受支持')
    if (spec.style_id !== undefined) throw Error('显示方式不属于生成参数')
    // 保留旧 HD-2D 参数中的 auto；独立 3D 地形签名已停用。
    if (spec.terrain_source !== undefined && spec.terrain_source !== 'auto')
      throw Error('HD-2D 不支持独立 3D 地形签名')
  } else if (spec.schema_version !== undefined || spec.style_id !== 'svg-town-v1')
    throw Error('不支持的生成版本')
  if (!resources.includes(spec.resources)) throw Error('不支持的资源组合')
  if (spec.settlement !== undefined && !settlements.includes(spec.settlement))
    throw Error('地点之间的连法只能是街道、野外小径或环岛小径')
  if (!Array.isArray(spec.places) || spec.places.length > templates.length * sizes.length)
    throw Error('地点列表无效')
  const seen = new Set()
  const countsByKind = new Map()
  let count = 0,
    homes = 0
  for (const p of spec.places) {
    if (
      !p ||
      typeof p !== 'object' ||
      Array.isArray(p) ||
      Object.keys(p).some((k) => !['kind', 'count', 'size'].includes(k)) ||
      !templates.some((t) => t.kind === p.kind)
    )
      throw Error('地点种类无效')
    if (
      !Number.isInteger(p.count) ||
      p.count < 1 ||
      p.count > maxPlacesForKind(p.kind, activeLimits) ||
      !sizes.includes(p.size)
    )
      throw Error('地点数量或尺寸无效')
    const group = `${p.kind}/${p.size}`
    if (seen.has(group)) throw Error('同种地点的同一尺寸只能填写一组数量')
    seen.add(group)
    countsByKind.set(p.kind, (countsByKind.get(p.kind) ?? 0) + p.count)
    count += p.count
    if (p.kind === 'home') homes += p.count
  }
  if (
    count < activeLimits.min_places ||
    count > activeLimits.max_places ||
    homes > activeLimits.max_homes
  )
    throw Error(
      `需要 ${activeLimits.min_places}–${activeLimits.max_places} 处活动地点，住宅可为 0，最多 ${activeLimits.max_homes} 处`
    )
  if (spec.settlement === 'ring') {
    if (count < 3) throw Error('环岛小径至少要三处地点')
    if (spec.places.some((p) => !templates.find((t) => t.kind === p.kind)?.outdoor))
      throw Error('环岛小径只排户外地点（活动区域、广场、公园这类）')
  }
  spec.constraints ??= []
  if (!Array.isArray(spec.constraints) || spec.constraints.length > limits.max_constraints)
    throw Error('空间要求最多 12 项')
  const targetExists = (ref) =>
    typeof ref === 'string' &&
    [...countsByKind].some(
      ([kind, total]) =>
        ref === kind || Array.from({ length: total }, (_, i) => `${kind}:${i + 1}`).includes(ref)
    )
  // 地点名：键是 kind 或 kind:序号（和位置要求同一种写法），地图上显示、村民认得的就是这些名字
  if (spec.names !== undefined) {
    if (!spec.names || typeof spec.names !== 'object' || Array.isArray(spec.names))
      throw Error('地点名字无效')
    const entries = Object.entries(spec.names)
    if (entries.length > limits.max_names) throw Error(`地点名字最多 ${limits.max_names} 个`)
    const seenNames = new Set()
    for (const [ref, name] of entries) {
      const text = typeof name === 'string' ? name.trim() : ''
      if (
        !targetExists(ref) ||
        !text ||
        [...text].length > limits.max_name_chars ||
        /[\u0000-\u001f]/.test(text) ||
        seenNames.has(text)
      )
        throw Error('地点名字无效或重复')
      seenNames.add(text)
      spec.names[ref] = text
    }
  }
  for (const c of spec.constraints) {
    if (
      !c ||
      Object.keys(c).some(
        (k) => !['kind', 'subject', 'relative_to', 'value', 'required'].includes(k)
      ) ||
      !['direction', 'near'].includes(c.kind) ||
      !targetExists(c.subject) ||
      !targetExists(c.relative_to) ||
      c.subject === c.relative_to ||
      typeof c.required !== 'boolean'
    )
      throw Error('空间要求格式或目标无效')
    if (c.kind === 'direction' && !['north', 'south', 'east', 'west'].includes(c.value))
      throw Error('方位仅支持东、西、南、北')
    if (c.kind === 'near' && c.value !== undefined) throw Error('邻近要求无需方位值')
  }
  spec.places.sort(
    (a, b) =>
      templates.findIndex((t) => t.kind === a.kind) -
        templates.findIndex((t) => t.kind === b.kind) ||
      sizes.indexOf(a.size) - sizes.indexOf(b.size)
  )
  return spec
}
