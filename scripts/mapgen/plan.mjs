// 一句话规划：交给模型的地点表，以及把模型的回复整理成合规的建镇参数。
// 建镇页（localCreation.ts）在网页里用，不依赖 Node 专有接口。
import { OFFERED_KINDS } from '../../frontend/town-2d/src/launcher/placeGroups.ts'
import { APPEARANCE_SET } from './budget.mjs'
import { limits, maxPlacesForKind, resources, validateSpec } from './spec.mjs'
import { STYLE_PRESETS } from '../../frontend/town-2d/src/map/themes/presets.ts'

/** 建镇页卡片上有的地点种类，按卡片顺序：种类、默认叫法、户外与否。下架的地标不在里面 */
export function plannerKinds(templates) {
  return OFFERED_KINDS.flatMap((kind) => {
    const t = templates.find((x) => x.kind === kind)
    return t ? [{ kind, name: t.name, outdoor: Boolean(t.outdoor) }] : []
  })
}

/** 生活条件照做了时，模型偶尔还把它写进「做不到的」：认得出是在说这件事的说明不要 */
const CONDITION_WORDS = {
  'no-food': /吃|食|粮/,
  'no-water': /水/,
  'no-rest': /床|休息|睡/,
  'poisoned-food': /变质|毒|坏/,
}

const text = (value, max) => {
  const s = typeof value === 'string' ? value.trim() : ''
  return s && [...s].length <= max && !/[\u0000-\u001f]/.test(s) ? s : ''
}
const strings = (list, max, count) =>
  (Array.isArray(list) ? list : [])
    .map((x) => text(x, max))
    .filter(Boolean)
    .slice(0, count)

/**
 * 模型的回复整理成能生成的参数和给玩家看的说明：只留建镇页有的地点、同种合并、数量夹在上限内，
 * 尺寸先填 medium（页面会按种类重排）；名字、位置要求和对照只留指得到地图上地点的；
 * 风格、生活条件不认识就用默认的。整理完再过一遍 validateSpec。
 */
export function tidyPlan(raw, templates, seed) {
  const source = raw?.spec && typeof raw.spec === 'object' ? raw.spec : {}
  const offered = plannerKinds(templates).map((k) => k.kind)
  const wanted = new Map()
  for (const p of Array.isArray(source.places) ? source.places : []) {
    const count = Math.floor(Number(p?.count))
    if (offered.includes(p?.kind) && count >= 1)
      wanted.set(p.kind, (wanted.get(p.kind) ?? 0) + count)
  }
  const counts = new Map()
  let total = 0
  for (const kind of offered) {
    const room = Math.min(
      maxPlacesForKind(kind),
      kind === 'home' ? limits.max_homes : Infinity,
      limits.max_places - total
    )
    const count = Math.min(wanted.get(kind) ?? 0, room)
    if (count < 1) continue
    counts.set(kind, count)
    total += count
  }
  const refOk = (ref) => {
    if (typeof ref !== 'string') return false
    const [kind, index, extra] = ref.split(':')
    const count = counts.get(kind) ?? 0
    if (!count || extra !== undefined) return false
    return index === undefined || (/^\d+$/.test(index) && +index >= 1 && +index <= count)
  }
  const names = {}
  const taken = new Set()
  for (const [ref, value] of Object.entries(source.names ?? {})) {
    const name = text(value, limits.max_name_chars)
    if (!refOk(ref) || !name || taken.has(name) || taken.size >= limits.max_names) continue
    names[ref] = name
    taken.add(name)
  }
  const constraints = (Array.isArray(source.constraints) ? source.constraints : [])
    .filter(
      (c) =>
        c &&
        refOk(c.subject) &&
        refOk(c.relative_to) &&
        c.subject !== c.relative_to &&
        ((c.kind === 'direction' && ['north', 'south', 'east', 'west'].includes(c.value)) ||
          c.kind === 'near')
    )
    .slice(0, limits.max_constraints)
    .map((c) => ({
      kind: c.kind,
      subject: c.subject,
      relative_to: c.relative_to,
      ...(c.kind === 'direction' ? { value: c.value } : {}),
      required: c.required === true,
    }))
  const environment = source.environment ?? {}
  const spec = validateSpec(
    {
      name: text(source.name, 60) || '新小镇',
      seed,
      schema_version: 2,
      appearance_set: APPEARANCE_SET,
      environment: {
        preset: STYLE_PRESETS.some((p) => p.id === environment.preset)
          ? environment.preset
          : STYLE_PRESETS[0].id,
        vegetation: ['sparse', 'medium', 'dense'].includes(environment.vegetation)
          ? environment.vegetation
          : 'medium',
      },
      places: [...counts].map(([kind, count]) => ({ kind, count, size: 'medium' })),
      ...(Object.keys(names).length ? { names } : {}),
      constraints,
      resources: resources.includes(source.resources) ? source.resources : 'normal-life',
    },
    templates
  )
  const mapping = (Array.isArray(raw?.mapping) ? raw.mapping : [])
    .map((m) => ({
      said: text(m?.said, 20),
      refs: (Array.isArray(m?.refs) ? m.refs : []).filter(refOk),
    }))
    // 对着三种以上地点的多半是在说整个小镇，不是点名的某处
    .filter((m) => m.said && new Set(m.refs.map((ref) => ref.split(':')[0])).size < 3)
    .slice(0, 12)
  const applied = CONDITION_WORDS[spec.resources]
  return {
    ...raw,
    spec,
    mapping,
    notes: strings(raw?.notes, 120, 8).filter((note) => !applied?.test(note)),
    worldview_suggestion: text(raw?.worldview_suggestion, 6000),
    residents: strings(raw?.residents, 60, 5),
  }
}
