import test from 'node:test'
import assert from 'node:assert/strict'
import { seal, checkIdentity } from '../mapgen/document.mjs'
import { distances } from '../mapgen/graph.mjs'
import { APPEARANCE_SET } from '../mapgen/budget.mjs'
import { tidyPlan } from '../mapgen/plan.mjs'
import { gen, gate, read, rejected, library, definitions } from './support.mjs'

const spec = {
  name: '生成回归',
  seed: 3817,
  style_id: 'svg-town-v1',
  places: [
    { kind: 'home', count: 3, size: 'small' },
    { kind: 'home', count: 2, size: 'large' },
    { kind: 'plaza', count: 1, size: 'large' },
    { kind: 'library', count: 1, size: 'medium' },
    { kind: 'canteen', count: 1, size: 'medium' },
  ],
  constraints: [],
  resources: 'normal-life',
}
const { style_id, ...rest } = spec
const spatial = {
  ...rest,
  schema_version: 2,
  appearance_set: APPEARANCE_SET,
  environment: { preset: 'coastal-village', vegetation: 'medium' },
}

// 代表性布局、规模上限与资源规则共走生成器和 Rust 校验，不展开种子、模板和尺寸矩阵。
test('default and generated maps are valid, connected, deterministic and obey constraints', () => {
  const builtin = read('data/maps/2d-town/map.json')
  checkIdentity(builtin)
  gate(builtin)
  const generated = gen({
    ...spec,
    seed: 51,
    constraints: [
      {
        kind: 'direction',
        subject: 'library',
        relative_to: 'plaza',
        value: 'north',
        required: true,
      },
    ],
  })
  const map = generated.document
  gate(map)
  assert.equal(distances(map.layout, map.layout.nodes[0].id).size, map.layout.nodes.length)
  assert.equal(map.topology.places.length, 8)
  assert.equal(map.layout.props.length, map.topology.props.length)
  assert.equal(generated.report.constraints[0].satisfied, true)
  const at = (kind) => generated.report.places.find((p) => p.ref === kind + ':1')
  assert(at('library').y < at('plaza').y)
  // 一句话规划起的地点名：单独起的优先，同一种共用的名字多处时编号；村民认得的拓扑地名就是它
  const named = gen({ ...spec, names: { library: '老书馆', home: '渔家', 'home:2': '灯塔下的屋' } })
  gate(named.document)
  const topologyNames = named.document.topology.places.map((p) => p.name)
  for (const name of ['老书馆', '灯塔下的屋', '渔家 1', '渔家 3', '广场'])
    assert(topologyNames.includes(name), name)
  assert.equal(new Set(topologyNames).size, topologyNames.length)
  // 野外小径：路和落脚点的名字里没有「小镇」「街道」，村民走在路上看到的就是这些名字
  const wild = gen({ ...spatial, settlement: 'wild' }).document
  gate(wild)
  const roadNames = [
    ...wild.topology.locales,
    ...wild.topology.stations,
    ...wild.layout.regions,
  ].map((x) => x.name)
  assert(roadNames.includes('野外') && roadNames.includes('小径'), roadNames.join('、'))
  assert(!roadNames.some((n) => /小镇|街道/.test(n)), roadNames.join('、'))
  // 野外图上新来的人落在第一个地点里（荒岛上醒来就在海滩），小镇落在街道上
  assert.equal(wild.topology.entry.locale, wild.topology.places[0].locale)
  assert.equal(gen(spatial).document.topology.entry.locale, 'roads')
  // 环岛：户外地点沿海岸排一圈（绕岛心的角度依次递增），一圈小径首尾相连，名字照野外的叫法；
  // 只排户外地点，至少三处
  const ring = gen({
    ...spatial,
    settlement: 'ring',
    places: [{ kind: 'area', count: 8, size: 'large' }],
  }).document
  gate(ring)
  assert.equal(ring.topology.entry.locale, 'area_1')
  assert(!ring.topology.locales.some((l) => /小镇|街道/.test(l.name)))
  const ringPlaces = ring.topology.places.map((p) =>
    ring.spatial.stations.find((s) => s.id === p.arrival_station)
  )
  const hub = [0, 2].map(
    (k) => ringPlaces.reduce((s, p) => s + p.position[k], 0) / ringPlaces.length
  )
  const turns = ringPlaces.map((p) => Math.atan2(p.position[2] - hub[1], p.position[0] - hub[0]))
  const steps = turns.map(
    (t, i) => (turns[(i + 1) % turns.length] - t + 4 * Math.PI) % (2 * Math.PI)
  )
  assert(Math.abs(steps.reduce((s, x) => s + x, 0) - 2 * Math.PI) < 1e-6, '地点绕岛一圈')
  // 主小径（不算各地点的入口岔路）上每个节点都正好接两段：一个没有断头的环
  const degree = new Map()
  for (const e of ring.layout.edges.filter((e) => e.road_class === 'street'))
    for (const n of [e.from_node, e.to_node]) degree.set(n, (degree.get(n) ?? 0) + 1)
  assert(
    degree.size >= 8 && [...degree.values()].every((d) => d === 2),
    JSON.stringify([...degree])
  )
  for (const bad of [
    { places: [{ kind: 'area', count: 2, size: 'large' }] },
    {
      places: [
        { kind: 'area', count: 3, size: 'large' },
        { kind: 'home', count: 1, size: 'small' },
      ],
    },
  ])
    assert.throws(() => gen({ ...spatial, settlement: 'ring', ...bad }), /环岛小径/)
  // 户外活动区域里有几个带名字的落脚点，各有一条走过去的通道
  const areas = gen({
    ...spatial,
    settlement: 'wild',
    places: [{ kind: 'area', count: 2, size: 'large' }],
  }).document
  gate(areas)
  for (const locale of ['area_1', 'area_2']) {
    const here = areas.topology.stations.filter(
      (s) => s.locale === locale && s.id.startsWith('spot_')
    )
    assert(here.length >= 2, `${locale} 的落脚点：${here.map((s) => s.name)}`)
    assert.equal(new Set(here.map((s) => s.name)).size, here.length)
    for (const s of here)
      assert(
        areas.spatial.routes.some((r) => r.to === s.node),
        `${s.id} 没有走过去的通道`
      )
  }
  assert.deepEqual(gen(spec), gen(spec))
  assert.deepEqual(
    gen(spec).document.layout,
    gen({ ...spec, name: '改名', places: [...spec.places].reverse() }).document.layout
  )
  const maximum = gen({
    ...spatial,
    places: [
      { kind: 'home', count: 20, size: 'large' },
      { kind: 'library', count: 8, size: 'large' },
      { kind: 'clinic', count: 8, size: 'large' },
    ],
  }).document
  gate(maximum)
  assert.equal(maximum.topology.places.length, 36)
  assert.equal(maximum.spatial.buildings.filter((b) => b.kind === 'home').length, 20)
  for (const [resources, need] of [
    ['no-food', 'fullness'],
    ['no-water', 'water'],
    ['no-rest', 'energy'],
  ]) {
    const map = gen({ ...spec, resources }).document
    gate(map)
    for (const prop of map.topology.props) {
      const definition = definitions.find((d) => d.id + '@' + d.version === prop.definition)
      assert(
        definition.actions.every((a) =>
          [...(a.on_complete ?? []), ...(a.during ?? [])].every((e) => e.need !== need)
        )
      )
    }
  }
})

test('invalid inputs and tampered maps are rejected', () => {
  for (const bad of [
    { ...spec, seed: -1 },
    { ...spec, places: [] },
    { ...spec, places: [{ kind: 'home', count: 21, size: 'large' }] },
    { ...spec, names: { cafe: '没有这处地点' } },
    { ...spec, names: { library: '重名', plaza: '重名' } },
  ])
    assert.throws(() => gen(bad))
  assert.throws(() => gen({ ...spatial, view_mode: '3d' }), /3D 版本已停用/)
  const map = gen(spec).document
  assert.throws(() => checkIdentity({ ...map, name: 'tampered' }))
  const broken = structuredClone(map)
  broken.layout.props.pop()
  rejected(seal(broken))
  const brokenSpatial = gen(spatial).document
  brokenSpatial.spatial.routes[0].minutes += 1
  rejected(seal(brokenSpatial))
  assert.throws(() => gen(spec, { max_ms: 0 }), { code: 'GENERATION_TIMEOUT' })
  assert.throws(() => gen(spec, { total_route_states: 0 }), { code: 'GENERATION_BUDGET_EXCEEDED' })
})

// 模型的回复常有下架的地点、对不上的名字和位置要求、不认识的风格：整理后只剩能生成的参数
test('a sloppy model plan is tidied into a valid spec that only uses places the creator offers', () => {
  const plan = tidyPlan(
    {
      spec: {
        name: '  海边小镇 ',
        places: [
          { kind: 'home', count: 3, size: 'small' },
          { kind: 'home', count: 2, size: 'large' },
          { kind: 'temple', count: 1 },
          { kind: 'cafe', count: 1 },
        ],
        names: {
          cafe: '村口酒馆',
          temple: '神庙',
          'home:9': '第九户',
          home: '渔家',
          library: '书馆',
        },
        constraints: [
          { kind: 'near', subject: 'cafe', relative_to: 'temple', required: true },
          {
            kind: 'direction',
            subject: 'cafe',
            relative_to: 'home',
            value: 'north',
            required: true,
          },
        ],
        environment: { preset: 'mars', vegetation: 'lush' },
        resources: 'party',
      },
      mapping: [
        { said: '小酒馆', refs: ['cafe', 'temple'] },
        { said: '神庙', refs: ['temple'] },
      ],
      residents: ['在村口酒馆当老板娘的寡妇', ''],
    },
    library.templates,
    7
  )
  assert.equal(plan.spec.name, '海边小镇')
  assert.deepEqual(plan.spec.places, [
    { kind: 'home', count: 5, size: 'medium' },
    { kind: 'cafe', count: 1, size: 'medium' },
  ])
  assert.deepEqual(plan.spec.names, { cafe: '村口酒馆', home: '渔家' })
  assert.deepEqual(
    plan.spec.constraints.map((c) => c.relative_to),
    ['home']
  )
  assert.deepEqual(plan.spec.environment, { preset: 'coastal-village', vegetation: 'medium' })
  assert.equal(plan.spec.resources, 'normal-life')
  assert.deepEqual(plan.mapping, [
    { said: '小酒馆', refs: ['cafe'] },
    { said: '神庙', refs: [] },
  ])
  assert.deepEqual(plan.residents, ['在村口酒馆当老板娘的寡妇'])
  gate(gen(plan.spec).document)
})
