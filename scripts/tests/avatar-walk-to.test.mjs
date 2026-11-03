import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
import { createRequire } from 'node:module'

const require = createRequire(new URL('../../frontend/town-2d/package.json', import.meta.url))
const ts = require('typescript')

function load(relative, name) {
  const source = fs.readFileSync(new URL(relative, import.meta.url), 'utf8')
  const scope = { exports: {} }
  vm.runInNewContext(
    ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText,
    scope
  )
  return scope.exports[name]
}

test('实际地图上能绕开碎掉的可走面，并穿门进屋', () => {
  const WalkRoutes = load('../../frontend/town-2d/src/map/route.ts', 'WalkRoutes')
  const map = JSON.parse(
    fs.readFileSync(new URL('../../data/maps/2d-town/map.json', import.meta.url), 'utf8')
  )
  const started = Date.now()
  const routes = new WalkRoutes(map.layout, map.topology, 12, false)
  const garden = { space: 'town_outdoor', position: [3396 / 12, 2772 / 12] }
  const plaza = { space: 'town_outdoor', position: [3250 / 12, 2050 / 12] }
  const harbor = { space: 'town_outdoor', position: [5766 / 12, 3114 / 12] }
  const cafe = { space: 'indoor_flower_cafe', position: [432 / 12, 912 / 12] }

  const toPlaza = routes.find(garden, plaza)
  assert.ok(toPlaza && toPlaza.length > 2, '社区花园到中心广场要拐弯，不是一条直线')
  assert.deepEqual(toPlaza.at(-1).point, plaza, '路线最后一个点就是目标')
  assert.ok(
    toPlaza.every((s) => s.point.space === 'town_outdoor'),
    '同为室外，不该穿门'
  )

  assert.ok(routes.find(garden, harbor), '跨半个镇也要找得到路')

  const toCafe = routes.find(garden, cafe)
  assert.ok(toCafe, '室外到室内要找得到路')
  // find 的结果建在测试沙箱里，跨域比较数组会失败，逐项断言
  const door = toCafe.filter((s) => s.portal)
  assert.equal(door.length, 1, '正好穿一次门')
  assert.equal(door[0].portal, 'indoor_flower_cafe:enter')
  assert.equal(door[0].point.space, 'town_outdoor', '开门时人还在门外')
  assert.equal(toCafe.at(-1).point.space, 'indoor_flower_cafe')
  assert.ok(Date.now() - started < 3000, '建图加三次查询要够快')
})

test('拐角那边走不通时先走到拐角再转弯，看得通才抄近路', () => {
  const createWalkTo = load('../../frontend/town-shared/src/avatar/walkTo.ts', 'createWalkTo')
  const at = (x, y) => ({ space: 'town_outdoor', position: [x, y] })
  const start = at(0, 0)
  let here = start
  const sent = []
  const walk = createWalkTo({
    here: () => here,
    step: () => 0.2,
    canWalk: () => true,
    emit: (direction) => sent.push(direction),
    portal: async () => true,
    replan: () => null,
    end: () => {},
    // 从起点直奔终点要穿过一块走不过去的地方，别处的直线都走得通
    sees: (from) => from !== start,
  })
  // 拐角离起点 0.6 米：1 米内的拐角一律提前转的话，人朝终点直走，撞上那块地方原地不动
  walk.set([{ point: at(0, 0.6) }, { point: at(4, 0.6) }], 0.5)
  walk.tick()
  let [dx, dy] = sent.at(-1)
  assert.ok(dy > 0 && Math.abs(dx) < 1e-9, '看不通终点：先朝拐角走')
  here = at(0.1, 0.2)
  walk.tick()
  ;[dx] = sent.at(-1)
  assert.ok(dx > 0, '看得通终点：拐角还没到也直奔终点')
})
