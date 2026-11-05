import { rect, length, dist } from './geometry.mjs'
import { roadCells } from './layout.mjs'
import { GENERATOR_VERSION, PARAMETERS, GenerationError, minutesFor } from './budget.mjs'
import { hashDocument, seal } from './document.mjs'
import { distances } from './graph.mjs'

export function resourceReport(plan, graph) {
  const report = [],
    skip = { 'no-food': 'fullness', 'no-water': 'water', 'no-rest': 'energy' }[plan.spec.resources]
  const homes = plan.places.filter((p) => p.kind === 'home')
  for (const home of homes.length ? homes : plan.places) {
    const paths = distances(graph, `arrival_${home.id}`)
    for (const need of ['fullness', 'water', 'energy']) {
      if (need === skip) {
        report.push({
          home: home.ref,
          need,
          required: false,
          status: 'intentionally_absent',
        })
        continue
      }
      const sources = plan.places.filter((p) =>
        p.props.some((ref) =>
          plan.defs
            .get(ref)
            .actions.some(
              (a) =>
                !a.conditions?.length &&
                (!a.supply || a.supply.initial >= a.supply.cost) &&
                [...(a.during || []), ...(a.on_complete || [])].some(
                  (e) =>
                    e.need === need &&
                    ((e.kind === 'restore' && e.amount > 0) ||
                      (e.kind === 'restore_need' && e.per_minute > 0))
                )
            )
        )
      )
      const nearest = sources
        .map((p) => ({
          p,
          minutes: minutesFor(plan.spec, paths.get(`arrival_${p.id}`) ?? Infinity),
        }))
        .sort((a, b) => a.minutes - b.minutes || a.p.id.localeCompare(b.p.id))[0]
      if ((!nearest || nearest.minutes > 20) && homes.length)
        throw new GenerationError(
          'LAYOUT_UNRESOLVED',
          `${home.name}没有在初始步行预算内可用的${{ fullness: '食物', water: '饮水', energy: '休息道具' }[need]}`,
          {
            stage: 'resources',
            place_refs: [home.ref],
            expected: 20,
            measured: nearest ? Number(nearest.minutes.toFixed(3)) : null,
          }
        )
      report.push({
        home: homes.length ? home.ref : null,
        place: home.name,
        need,
        required: homes.length > 0,
        status: nearest && nearest.minutes <= 20 ? 'available' : 'missing',
        source: nearest?.p.ref ?? null,
        minutes: nearest ? Number(nearest.minutes.toFixed(4)) : null,
      })
    }
  }
  return report
}

/** 路和落脚点的名字：野外小径用于荒岛、野地，不带「小镇」「街道」 */
const ROAD_NAMES = {
  town: { roads: '小镇街道', street: '街道路段', access: '地点入口通道', arrival: '街道落脚点' },
  wild: { roads: '野外', street: '小径', access: '岔路', arrival: '野外落脚点' },
}
ROAD_NAMES.ring = ROAD_NAMES.wild

export function exportDocument(plan, graph, library, contours, definitions) {
  const standalone = plan.places.length === 1
  const names = ROAD_NAMES[plan.spec.settlement ?? 'town']
  const topology = {
    schema_version: 1,
    locales: standalone ? [] : [{ id: 'roads', name: names.roads, kind: 'dwell' }],
    passages: [],
    stations: [],
    places: [],
    props: [],
    meals: [],
  }
  const layout = {
    canvas: { width: plan.width, height: plan.height },
    regions: [],
    nodes: graph.nodes.map(({ locale, ...n }) => n),
    edges: graph.edges.map(({ owner, ...e }) => e),
    spaces: [],
    stations: [],
    props: [],
  }
  for (const e of graph.edges) {
    topology.locales.push({
      id: e.id,
      name: e.road_class === 'access' ? names.access : names.street,
      kind: 'transit',
      from_node: e.from_node,
      to_node: e.to_node,
      minutes: Number(minutesFor(plan.spec, length(e.polyline)).toFixed(4)),
    })
    for (const [node, locale, side] of [
      [e.from_node, e.from_locale, 'a'],
      [e.to_node, e.to_locale, 'b'],
    ])
      topology.passages.push({
        id: `${e.id}_${side}`,
        a: e.id,
        b: locale,
        node_a: node,
        node_b: node,
        minutes: 0,
        capabilities: ['通行', '视', '听'],
      })
  }
  const station = (id, locale, name, node, x, y, space, kind = 'arrival') => {
    topology.stations.push({ id, locale, name, kind, node })
    layout.stations.push({ id, space, x, y })
  }
  const homes = plan.places.filter((p) => p.kind === 'home')
  const entry = standalone
    ? graph.nodes[0]
    : graph.nodes
        .filter((n) => n.locale === 'roads')
        .sort(
          (a, b) =>
            homes.reduce(
              (s, p) => s + dist([a.x, a.y], [p.x, p.y]) - dist([b.x, b.y], [p.x, p.y]),
              0
            ) || a.id.localeCompare(b.id)
        )[0]
  if (!standalone)
    station('road_arrival', 'roads', names.arrival, entry.id, entry.x, entry.y, 'town_outdoor')
  // 新来的人落在哪：小镇落在街道上；单地点和野外落在第一个地点里（荒岛上醒来就在海滩，不在小径上）
  topology.entry =
    standalone || ['wild', 'ring'].includes(plan.spec.settlement)
      ? { locale: plan.places[0].id, station: `at_${plan.places[0].id}` }
      : { locale: 'roads', station: 'road_arrival' }
  for (const p of plan.places) {
    const node = `arrival_${p.id}`,
      r = p.interiorRect ?? rect(p)
    topology.locales.push({ id: p.id, name: p.name, kind: 'dwell' })
    topology.places.push({
      name: p.name,
      locale: p.id,
      arrival_station: `at_${p.id}`,
      type: p.kind === 'home' ? '住宅' : p.name,
      residential: p.kind === 'home',
      summary: `${p.name}，可使用这里的道具。`,
      visible_features: [],
    })
    station(`at_${p.id}`, p.id, p.name + '到达点', node, ...p.door, 'town_outdoor')
    if (p.outdoor) layout.regions.push(p.surface)
    else
      layout.spaces.push({
        id: p.id,
        name: p.name,
        kind: p.kind,
        bounds: { x: 0, y: 0, width: r.w, height: r.h },
        unfold: { scale: 1, offset_x: r.x, offset_y: r.y },
        ...(standalone
          ? {}
          : {
              door_outside: p.door,
              door_inside_local: [p.door[0] - r.x, p.door[1] - r.y],
            }),
      })
    p.props.forEach((reference, i) => {
      const d = plan.defs.get(reference),
        id = `${p.id}_prop_${i + 1}`,
        prop = { id, definition: reference, name: d.name, locale: p.id }
      if (reference.startsWith('core:bulletin-'))
        prop.board = `${p.id}_prop_${p.props.findIndex((r) => r.startsWith('core:bulletin_board@')) + 1}`
      topology.props.push(prop)
      const [x, y] = p.propPositions[i],
        space = p.outdoor ? 'town_outdoor' : p.id
      layout.props.push({ id, name: d.name, place_name: p.name, space, x, y })
      station(`use_${id}`, p.id, d.name + '使用点', node, x, y, space, 'slot')
    })
  }
  if (!standalone)
    layout.regions.unshift({
      id: 'roads',
      name: names.roads,
      kind: 'road',
      ...roadCells(
        graph.edges,
        plan.places.filter((p) => !p.outdoor).map((p) => rect(p))
      ),
    })
  if (layout.regions.reduce((n, r) => n + r.cells.length, 0) > plan.budget.caps.max_cells)
    throw new GenerationError('GENERATION_BUDGET_EXCEEDED', '地图区域单元达到上限', {
      stage: 'export',
    })
  crop(layout, plan)
  const refs = new Set(plan.places.flatMap((p) => p.props))
  const assets_hash = hashDocument({
    library,
    contours,
    definitions: definitions.filter((d) => refs.has(`${d.id}@${d.version}`)),
    parameters: PARAMETERS,
  })
  return seal({
    schema_version: 1,
    id: `generated-${hashDocument({ spec: plan.spec, generator_version: GENERATOR_VERSION, assets_hash }).slice(0, 16)}`,
    name: plan.spec.name,
    description: `${plan.places.length} 处地点 · ${homes.length} 处住宅`,
    origin: 'generated',
    generation: {
      spec: plan.spec,
      generator_version: GENERATOR_VERSION,
      template_version: library.version,
      input_hash: hashDocument(plan.spec),
      assets_hash,
      parameters_version: PARAMETERS.version,
    },
    style_id: 'svg-town-v1',
    style_version: 1,
    topology,
    layout,
  })
}

function crop(layout, plan) {
  const cell = PARAMETERS.cell_size
  const bounds = plan.places.map((p) => rect(p, 100))
  for (const n of layout.nodes) bounds.push({ x: n.x - 80, y: n.y - 80, w: 160, h: 160 })
  for (const r of layout.regions)
    for (const [x, y] of r.cells) bounds.push({ x: x * cell, y: y * cell, w: cell, h: cell })
  let minX = Infinity,
    minY = Infinity,
    maxX = -Infinity,
    maxY = -Infinity
  for (const r of bounds) {
    minX = Math.min(minX, r.x)
    minY = Math.min(minY, r.y)
    maxX = Math.max(maxX, r.x + r.w)
    maxY = Math.max(maxY, r.y + r.h)
  }
  // 平移量对齐到区域网格，区域单元坐标才能整数平移。
  const dx = Math.floor((minX - plan.L * 0.3) / cell) * cell,
    dy = Math.floor((minY - plan.L * 0.3) / cell) * cell
  layout.canvas = {
    width: Math.ceil((maxX - dx + plan.L * 0.3) / cell) * cell,
    height: Math.ceil((maxY - dy + plan.L * 0.3) / cell) * cell,
  }
  // Copy points before translating: room doors and shared edge vertices may alias internally.
  for (const collection of [layout.nodes, layout.stations, layout.props])
    for (const p of collection)
      if (p.space === 'town_outdoor') {
        p.x -= dx
        p.y -= dy
      }
  for (const e of layout.edges) e.polyline = e.polyline.map(([x, y]) => [x - dx, y - dy])
  for (const s of layout.spaces) {
    s.unfold.offset_x -= dx
    s.unfold.offset_y -= dy
    if (s.door_outside) s.door_outside = [s.door_outside[0] - dx, s.door_outside[1] - dy]
  }
  for (const r of layout.regions) {
    r.cells = r.cells.map(([x, y]) => [x - dx / cell, y - dy / cell])
    if (r.label_anchor) r.label_anchor = [r.label_anchor[0] - dx, r.label_anchor[1] - dy]
    if (r.bounds) {
      r.bounds.x -= dx
      r.bounds.y -= dy
    }
  }
  for (const p of plan.places) {
    p.x -= dx
    p.y -= dy
  }
  for (const d of plan.districts) d.center = [d.center[0] - dx, d.center[1] - dy]
}
