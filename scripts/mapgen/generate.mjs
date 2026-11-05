import { fitOriginalTopology } from './original-topology.mjs'
import { addSpatial } from './spatial.mjs'
import { budget, GenerationError, LAYOUT, PARAMETERS, minutesFor } from './budget.mjs'
import { validateSpec } from './spec.mjs'
import { expandPlan, placeDistricts } from './districts.mjs'
import { mainRoads, connectEntrance, addRoad } from './roads.mjs'
import { fitParcels } from './parcels.mjs'
import { contour, placeProps } from './layout.mjs'
import { measureConstraints } from './constraints.mjs'
import { buildGraph, distances } from './graph.mjs'
import { addStreetShortcuts } from './street-shortcuts.mjs'
import { ringLayout } from './ring.mjs'
import { connectOuterStreetEnds } from './outer-street-loops.mjs'
import { auditStreetVisualQuality } from './street-finish.mjs'
import { resourceReport, exportDocument } from './export.mjs'
import { dist } from './geometry.mjs'

export function generate(input, library, contours, definitions, options = {}) {
  let spec
  try {
    spec = validateSpec(input, library.templates)
  } catch (e) {
    throw new GenerationError('INVALID_SPEC', e.message, { stage: 'input' })
  }
  const timer = budget(options),
    plan = expandPlan(spec, library, definitions, timer)
  timer.check('input')
  const standalone = plan.places.length === 1
  if (standalone) {
    // 单地点：中心落在区域网格上，离原点留出固定边距。
    const p = plan.places[0],
      cell = PARAMETERS.cell_size
    p.x = Math.ceil(p.w / (2 * cell)) * cell + LAYOUT.standalone_margin
    p.y = Math.ceil(p.h / (2 * cell)) * cell + LAYOUT.standalone_margin
    // An isolated place has an internal arrival point, not an outside doorway.
    p.door = [p.x, p.y]
  } else if (spec.settlement === 'ring') {
    options.onStage?.('districts')
    ringLayout(plan)
  } else {
    options.onStage?.('districts')
    if (!fitOriginalTopology(plan, library, definitions)) {
      placeDistricts(plan)
      options.onStage?.('roads')
      mainRoads(plan)
      options.onStage?.('parcels')
      fitParcels(plan)
    }
  }
  const report = measureConstraints(spec, plan.places, plan.L)
  if (report.some((c) => c.required && !c.satisfied))
    throw new GenerationError('LAYOUT_UNRESOLVED', '在当前计算范围内未能同时满足必须的空间要求', {
      stage: 'constraints',
      constraints: report.filter((c) => c.required && !c.satisfied),
    })
  options.onStage?.('surfaces')
  for (const p of plan.places) {
    if (
      !standalone &&
      !plan.roads.some((r) => r.id === `access_${p.id}`) &&
      !connectEntrance(plan, p)
    )
      throw new GenerationError('ROUTE_UNRESOLVED', `${p.name}暂时没有可行的入口通道`, {
        stage: 'entrances',
        place_refs: [p.ref],
      })
    if (p.outdoor) p.surface = contour(plan, p, contours[p.contour ?? p.kind])
    placeProps(plan, p)
  }
  let graph = standalone
    ? {
        nodes: [
          {
            id: `arrival_${plan.places[0].id}`,
            locale: plan.places[0].id,
            x: plan.places[0].x,
            y: plan.places[0].y,
            kind: 'place_arrival',
            space: 'town_outdoor',
          },
        ],
        edges: [],
      }
    : buildGraph(plan)
  if (plan.preserveOriginalTopology && !standalone) {
    if (connectOuterStreetEnds(plan, graph, addRoad)) graph = buildGraph(plan)
  }
  // 普通布局补最多两条捷径修正过长的绕行；按建筑足迹放大的路网已经成环，
  // 落位后再补捷径会从院子里穿出新路。
  // 环岛只留那一圈小径，不从岛中间抄近路：绕到对面就得沿着海岸走
  if (!plan.preserveOriginalTopology && spec.settlement !== 'ring')
    graph = addStreetShortcuts(plan, graph)
  // 最终几何由 Rust 的 town-map validate 统一校验；这里只导出。
  const reachable = distances(graph, `arrival_${plan.places[0].id}`)
  const unreachablePlaces = plan.places.filter((p) => !reachable.has(`arrival_${p.id}`))
  if (unreachablePlaces.length)
    throw new GenerationError('ROUTE_UNRESOLVED', '道路连接在坐标导出后断开，请重新选择布局', {
      stage: 'final-connectivity',
      place_refs: unreachablePlaces.map((place) => place.ref),
      missing_arrivals: unreachablePlaces.map((place) => ({
        id: place.id,
        door: place.door,
        access: plan.roads.find((road) => road.id === `access_${place.id}`)?.polyline,
      })),
      graph: { nodes: graph.nodes.length, edges: graph.edges.length },
    })
  const resources = resourceReport(plan, graph)
  const travel = travelReport(plan, graph)
  const streetQuality = plan.preserveOriginalTopology
    ? auditStreetVisualQuality(graph)
    : { ok: true, issues: [] }
  const document = exportDocument(plan, graph, library, contours, definitions)
  if (spec.schema_version === 2) {
    options.onStage?.('spatial')
    addSpatial(document, plan, timer)
  }
  timer.check('export')
  // 说明原样显示在建镇预览旁边，写给玩家看：说后果，不说检查过程
  const warnings = []
  if (spec.resources !== 'normal-life')
    warnings.push(
      {
        'no-food': '按你的选择，镇上没有食物：村民会挨饿，可能倒下甚至死去。',
        'no-water': '按你的选择，镇上没有饮水：村民会口渴，缺水比挨饿来得快。',
        'no-rest': '按你的选择，镇上没有床和座椅：村民没法好好休息，累了会病倒。',
        'poisoned-food': '按你的选择，干粮都变质了：吃了会生病。',
      }[spec.resources]
    )
  if (!streetQuality.ok)
    warnings.push(
      `有 ${streetQuality.issues.length} 处道路挨得太近或忽宽忽窄，看着不顺眼可以换一张布局。`
    )
  if (standalone) warnings.push('这是一片单独的活动空间，没有道路和对外通道，村民直接出现在这里。')
  for (const r of resources.filter((r) => r.status === 'missing'))
    warnings.push(
      `${r.place}缺少可用的${{ fullness: '食物', water: '饮水', energy: '休息道具' }[r.need]}。`
    )
  return {
    document,
    report: {
      constraints: report,
      resources,
      travel,
      warnings,
      places: plan.places.map(({ ref, name, x, y, district }) => ({
        ref,
        name,
        x,
        y,
        district,
      })),
      layout: {
        reference_length: plan.L,
        districts: plan.districts.map(({ id, center, axis, density }) => ({
          id,
          center,
          axis,
          density,
        })),
        nodes: graph.nodes.length,
        edges: graph.edges.length,
        cycles: graph.edges.length - graph.nodes.length + 1,
        counts: { ...timer.counts },
        repairs: plan.repairs,
        street_quality: streetQuality,
      },
    },
  }
}

function travelReport(plan, graph) {
  const paths = new Map(plan.places.map((p) => [p.id, distances(graph, `arrival_${p.id}`)]))
  const publicPlaces = plan.places
    .filter((p) => p.kind !== 'home')
    .map((p) => {
      const minutes = plan.places
        .filter((h) => h.kind === 'home')
        .map((h) => minutesFor(plan.spec, paths.get(h.id).get(`arrival_${p.id}`)))
        .sort((a, b) => a - b)
      if (!minutes.length) return { place: p.ref, median_minutes: null, max_minutes: null }
      const middle = Math.floor(minutes.length / 2)
      return {
        place: p.ref,
        median_minutes: Number(
          ((minutes[middle] + minutes[Math.max(0, Math.ceil(minutes.length / 2) - 1)]) / 2).toFixed(
            4
          )
        ),
        max_minutes: Number(minutes.at(-1).toFixed(4)),
      }
    })
  const neighbors = []
  for (const p of plan.places)
    for (const q of plan.places) {
      if (p.id >= q.id) continue
      const direct = dist(p.door, q.door)
      if (direct > plan.L * 2) continue
      const distance = paths.get(p.id).get(`arrival_${q.id}`)
      neighbors.push({
        from: p.ref,
        to: q.ref,
        direct_distance: Number(direct.toFixed(3)),
        road_distance: Number(distance.toFixed(3)),
        detour_ratio: Number((distance / Math.max(plan.L * 0.25, direct)).toFixed(3)),
      })
    }
  return { public_places: publicPlaces, neighbors }
}
