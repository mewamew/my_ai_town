import { GenerationError } from './budget.mjs'
import { stream } from './document.mjs'
import { overlaps, rect } from './geometry.mjs'
import { addRoad } from './roads.mjs'

// 环岛（settlement: ring）：户外地点按各自大小均匀排在一个略扁的圈上，里侧一圈小径首尾相连
// 把它们串起来，岛中间留空（前端和地形按地点与路的外包络画岛，中间就是一片林地）。
// 地点之间留出的空地决定岛有多大；落位后接入口、建路网、导出都走原流程。

/** 相邻两处地点之间留的空地（svg 单位，60 = 1 米）：15 米 */
const GAP = 900
/** 小径离地点朝岛心那一边多远：5 米，入口通道短而清楚 */
const ROAD_GAP = 300
/** 圈外留给海岸的边距 */
const MARGIN = 900
/** 环岛上的地点比小镇里的大一圈：海岸一圈地方宽，地点里也要放得下营地、柴堆和几样冲上岸的东西 */
const SCALE = 1.6

/** 地点在 angle 方向上的半宽：沿这个方向从中心走到地块边缘有多远 */
const reach = (p, angle) =>
  (Math.abs(Math.cos(angle)) * p.w) / 2 + (Math.abs(Math.sin(angle)) * p.h) / 2

export function ringLayout(plan) {
  const { places, spec } = plan
  const rng = stream(spec.seed, 'ring', 'layout')
  for (const p of places) {
    p.w = 2 * Math.round((p.w * SCALE) / 2)
    p.h = 2 * Math.round((p.h * SCALE) / 2)
  }
  const span = places.reduce((s, p) => s + Math.max(p.w, p.h) + GAP, 0)
  // 周长按圆估算，再按长短轴比拉成椭圆；椭圆周长和同面积的圆相差不到一成，留出的空地照样够
  const aspect = 1 + rng() * 0.35,
    radius = span / (2 * Math.PI),
    a = radius * Math.sqrt(aspect),
    b = radius / Math.sqrt(aspect)
  const extent = Math.max(...places.map((p) => Math.max(p.w, p.h)))
  plan.width = plan.initialWidth = Math.ceil(2 * (a + extent + MARGIN))
  plan.height = plan.initialHeight = Math.ceil(2 * (b + extent + MARGIN))
  plan.area = plan.width * plan.height
  const center = [plan.width / 2, plan.height / 2]
  plan.districts = [
    {
      id: 'district_1',
      center,
      radius: Math.min(a, b),
      axis: 0,
      aspect,
      density: plan.phi,
      targetArea: plan.area,
      usedArea: 0,
      branches: 0,
      hub: center,
    },
  ]
  // 每处地点占一段弧，弧长按地点大小分；第一处（新来的人落脚的地方）从随机的角度起
  let along = rng()
  const corners = places.map((p) => {
    const share = (Math.max(p.w, p.h) + GAP) / span,
      angle = 2 * Math.PI * (along + share / 2),
      wobble = 1 + (rng() - 0.5) * 0.1
    along += share
    p.x = Math.round(center[0] + Math.cos(angle) * a * wobble)
    p.y = Math.round(center[1] + Math.sin(angle) * b * wobble)
    p.intended = [p.x, p.y]
    p.district = 'district_1'
    p.anchor = true
    p.placed = true
    // 小径上对着这处地点的点：从地点中心朝岛心退到地块边缘外 ROAD_GAP
    const inward = Math.atan2(center[1] - p.y, center[0] - p.x),
      back = reach(p, inward) + ROAD_GAP
    return [Math.round(p.x + Math.cos(inward) * back), Math.round(p.y + Math.sin(inward) * back)]
  })
  for (let i = 0; i < places.length; i++)
    for (let j = 0; j < i; j++)
      if (overlaps(rect(places[i], 60), rect(places[j], 60)))
        throw new GenerationError('LAYOUT_UNRESOLVED', '环岛上的地点挤在一起，请换一张布局', {
          stage: 'districts',
          place_refs: [places[i].ref, places[j].ref],
        })
  for (let i = 0; i < corners.length; i++) {
    const next = corners[(i + 1) % corners.length]
    if (!addRoad(plan, corners[i], next, { id: `ring_${i + 1}`, class: 'street' }))
      throw new GenerationError('ROUTE_UNRESOLVED', '环岛小径没能连成一圈，请换一张布局', {
        stage: 'roads',
        place_refs: [places[i].ref, places[(i + 1) % places.length].ref],
      })
  }
}
