// 屋里家具的布置走完整路径：拿默认地图的花房咖啡馆，照场景的做法砌隔墙、摆道具、再摆陈设。
// 直接载入源码（布置和隔墙两个文件都不引入别的模块，Node 去掉类型即可运行）。
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { arrange, furnish } from '../../town-2d/src/map/hd2d/propArrange.ts'
import { planPartition } from '../../town-2d/src/map/hd2d/partition.ts'

const map = JSON.parse(
  fs.readFileSync(new URL('../../../data/maps/2d-town/map.json', import.meta.url), 'utf8')
)
const space = map.layout.spaces.find((s) => s.kind === 'cafe')
const point = (p) => [
  space.unfold.offset_x + space.unfold.scale * p.x,
  space.unfold.offset_y + space.unfold.scale * p.y,
]
const [x, y] = point(space.bounds)
const w = space.unfold.scale * space.bounds.width,
  h = space.unfold.scale * space.bounds.height
const stations = map.layout.stations.filter((p) => p.space === space.id).map(point)
const marks = map.layout.props.filter((p) => p.space === space.id)
const partition = planPartition(
  w,
  h,
  12,
  [...stations, ...marks.map(point)].map(([px, py]) => [px - x - w / 2, py - y - h / 2]),
  [space.door_outside[0] - x - w / 2, space.door_outside[1] - y - h / 2]
)
const room = {
  x0: x + 12,
  y0: y + 12,
  x1: x + w - 12,
  y1: y + h - 12,
  walls: (partition?.segments ?? []).map(([from, to]) =>
    partition.alongX
      ? {
          horizontal: true,
          at: y + h / 2 + partition.at,
          from: x + w / 2 + from,
          to: x + w / 2 + to,
        }
      : {
          horizontal: false,
          at: x + w / 2 + partition.at,
          from: y + h / 2 + from,
          to: y + h / 2 + to,
        }
  ),
}
// 占地照 propBuilds.ts 里这几件的搭法：咖啡机和内侧柜台靠墙，其余落地
const FEET = {
  'core:coffee_machine': { cx: 0, cz: 0, hw: 27, hd: 16, wall: true },
  'core:prop_1f268c17ba': { cx: 0, cz: 0, hw: 51, hd: 16, wall: true },
  'core:prop_91ab2f9d1f': { cx: 0, cz: 0, hw: 51, hd: 18 },
  'core:prop_d8ed6d0f46': { cx: 0, cz: 0, hw: 38, hd: 17 },
  'core:prop_fb48cd2aaf': { cx: 9, cz: 31.5, hw: 24, hd: 46.5 },
  'core:seat': { cx: 13.5, cz: 0, hw: 40.5, hd: 24 },
}
const definition = new Map(map.topology.props.map((p) => [p.id, p.definition.split('@')[0]]))
const pieces = marks.map((p) => {
  const { wall = false, ...foot } = FEET[definition.get(p.id)]
  const [px, py] = point(p)
  return { id: p.id, x: px, y: py, foot, wall }
})
const overlap = (a, b) =>
  a.x0 < b.x1 - 0.01 && b.x0 < a.x1 - 0.01 && a.y0 < b.y1 - 0.01 && b.y0 < a.y1 - 0.01
const inside = (b) =>
  b.x0 >= room.x0 - 0.01 &&
  b.y0 >= room.y0 - 0.01 &&
  b.x1 <= room.x1 + 0.01 &&
  b.y1 <= room.y1 + 0.01

test('cafe furniture backs onto the wall, lines up, and never overlaps or leaves the room', () => {
  const spots = arrange(room, pieces)
  const boxes = pieces.map((p) => spots.get(p.id).box)
  for (const b of boxes) assert.ok(inside(b), `在墙内 ${JSON.stringify(b)}`)
  for (let i = 0; i < boxes.length; i++)
    for (let j = i + 1; j < boxes.length; j++)
      assert.ok(!overlap(boxes[i], boxes[j]), `${pieces[i].id} 和 ${pieces[j].id} 不重叠`)
  // 咖啡机和内侧柜台在地图上只隔 51，比两件的宽度窄：贴上北墙、沿墙排开，正好挨着
  const [machine, counter] = ['core:coffee_machine', 'core:prop_1f268c17ba'].map(
    (d) => spots.get(pieces.find((p) => definition.get(p.id) === d).id).box
  )
  assert.equal(machine.y0, room.y0)
  assert.equal(counter.y0, room.y0)
  assert.ok(Math.abs(machine.x1 - counter.x0) < 0.01, '两件挨着')
  // 室外的道具原地朝南
  const outdoor = arrange(undefined, [pieces[0]]).get(pieces[0].id)
  assert.deepEqual([outdoor.x, outdoor.y, outdoor.turn], [pieces[0].x, pieces[0].y, 0])
})

test('decor stays off props, standing spots and the straight lines villagers walk', () => {
  const spots = arrange(room, pieces)
  const taken = pieces.map((p) => spots.get(p.id).box)
  const lounge = pieces
    .filter((p) => definition.get(p.id) === 'core:seat')
    .map((p) => spots.get(p.id).box)
  const decor = furnish(room, 'cafe', taken, stations, lounge)
  assert.ok(
    decor.some((d) => d.kind === 'table-set'),
    '至少摆下一套桌椅'
  )
  assert.equal(decor.filter((d) => d.kind === 'rug').length, 1)
  const half = { 'table-set': [26, 62], plant: [16, 16] }
  for (const d of decor.filter((d) => d.kind !== 'rug')) {
    const [hx, hy] = half[d.kind]
    const b = { x0: d.x - hx, y0: d.y - hy, x1: d.x + hx, y1: d.y + hy }
    assert.ok(inside(b), `${d.kind} 在墙内`)
    assert.ok(!taken.some((t) => overlap(t, b)), `${d.kind} 不压道具`)
    assert.ok(
      !stations.some(([sx, sy]) => sx > b.x0 && sx < b.x1 && sy > b.y0 && sy < b.y1),
      `${d.kind} 不占落脚点`
    )
    // 落脚点两两连线上每隔 4 个单位取一点，都不落在陈设里
    for (let i = 0; i < stations.length; i++)
      for (let j = i + 1; j < stations.length; j++) {
        const [ax, ay] = stations[i],
          [bx, by] = stations[j]
        const steps = Math.ceil(Math.hypot(bx - ax, by - ay) / 4)
        for (let k = 0; k <= steps; k++) {
          const px = ax + ((bx - ax) * k) / steps,
            py = ay + ((by - ay) * k) / steps
          assert.ok(!(px > b.x0 && px < b.x1 && py > b.y0 && py < b.y1), `${d.kind} 不挡走道`)
        }
      }
  }
  // 没登记陈设的屋子不摆
  assert.deepEqual(furnish(room, 'home', taken, stations, lounge), [])
})
