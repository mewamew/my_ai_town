// 手绘的内置地图：按形状（矩形、椭圆、多边形、沿折线的带子）摆区域、房子和路，生成一份完整的地图文档
// （schema 1：拓扑 + 显示数据，和默认地图同一种）。走路按每米 12 个地图单位、每分钟 12 米，路段的分钟数是
// 长度 / 144。
// - 路网：几条路在交叉处、路头碰到别的路处自动断开连成路口；房门和户外地点的到达点各接一条小路到最近的路上。
// - 房子：内景（大小、门、家具、落脚点）从一份已有地图里按房间编号搬过来，按设计的占地缩放摆上去；
//   门开在内景门所在的那面墙外。
// - 户外地点：到达点、道具和落脚点同样按编号从那份地图搬过来，整体平移到新的到达点旁边；新地点在设计里写。
// - 海岸：陆地底稿和岛内的水写进 layout.island，由前端扭曲、冲刷、挖水（见 frontend 的 map/pixel/island.ts）；
//   岛内的水用 spring() 包起来的是温泉（青绿的热水、黑石池沿、冒白汽，夜里透光）。
// - 风格：environment 写地图风格（同建镇参数的 environment.preset，比如 frozen 冰封雪镇），不写是默认风格；
//   worldview 是随地图带的世界观，第一次进镇时开局向导默认用它。
// - 只看不进的楼（ruin）、按坐标立的立牌（standee）、盘旋的鸟群（flock）写进 layout 的 ruins、standees、flocks，
//   只给画面看，不进拓扑（见 town-shared 的 mapDocument.ts）。
// 生成后用 scripts/mapgen/document.mjs 的 seal 封摘要，再过 town-map validate。

export const CELL = 24
/** 地图单位 / 分钟：每米 12 个单位，每分钟走 12 米 */
const UNITS_PER_MINUTE = 144
/** 路头离别的路这么近就接上；路口离得比这还近就并成一个（地图单位） */
const JOIN = 70
const MERGE = 12
/** 小路的宽度；房门的小路先试着笔直出去这么远找路 */
const ACCESS_WIDTH = 36
const RAY = 900

// ---------- 形状 ----------
export const rect = (x, y, w, h) => ({ t: 'rect', x, y, w, h })
export const ellipse = (cx, cy, rx, ry) => ({ t: 'ellipse', cx, cy, rx, ry })
export const circle = (cx, cy, r) => ellipse(cx, cy, r, r)
export const poly = (pts) => ({ t: 'poly', pts })
export const band = (pts, width) => ({ t: 'band', pts: smooth(pts), width })
export const minus = (a, b) => ({ t: 'minus', a, b })
export const union = (...s) => ({ t: 'union', s })
/** 岛内的水里，这一片是温泉 */
export const spring = (shape) => ({ t: 'spring', s: shape })

function inPoly(x, y, pts) {
  let inside = false
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i],
      [xj, yj] = pts[j]
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside
  }
  return inside
}
/** 点到线段的距离和垂足的参数 t（0..1） */
function toSegment(px, py, ax, ay, bx, by) {
  const dx = bx - ax,
    dy = by - ay
  const l2 = dx * dx + dy * dy
  const t = l2 ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) : 0
  return { d: Math.hypot(px - (ax + t * dx), py - (ay + t * dy)), t }
}
export function contains(s, x, y) {
  switch (s.t) {
    case 'rect':
      return x >= s.x && x < s.x + s.w && y >= s.y && y < s.y + s.h
    case 'ellipse':
      return ((x - s.cx) / s.rx) ** 2 + ((y - s.cy) / s.ry) ** 2 <= 1
    case 'poly':
      return inPoly(x, y, s.pts)
    case 'band':
      for (let i = 0; i + 1 < s.pts.length; i++)
        if (toSegment(x, y, ...s.pts[i], ...s.pts[i + 1]).d <= s.width / 2) return true
      return false
    case 'minus':
      return contains(s.a, x, y) && !contains(s.b, x, y)
    case 'union':
      return s.s.some((k) => contains(k, x, y))
    case 'spring':
      return contains(s.s, x, y)
  }
  throw Error('不认识的形状 ' + s.t)
}
function bbox(s) {
  switch (s.t) {
    case 'rect':
      return [s.x, s.y, s.x + s.w, s.y + s.h]
    case 'ellipse':
      return [s.cx - s.rx, s.cy - s.ry, s.cx + s.rx, s.cy + s.ry]
    case 'poly':
    case 'band': {
      const pad = s.t === 'band' ? s.width / 2 : 0
      const xs = s.pts.map((p) => p[0]),
        ys = s.pts.map((p) => p[1])
      return [
        Math.min(...xs) - pad,
        Math.min(...ys) - pad,
        Math.max(...xs) + pad,
        Math.max(...ys) + pad,
      ]
    }
    case 'minus':
      return bbox(s.a)
    case 'union': {
      const b = s.s.map(bbox)
      return [0, 1, 2, 3].map((k) => (k < 2 ? Math.min : Math.max)(...b.map((v) => v[k])))
    }
    case 'spring':
      return bbox(s.s)
  }
}
/** Catmull-Rom：给的点之间插出平滑曲线，大约每 step 一个点 */
export function smooth(pts, step = 40) {
  if (pts.length < 3) return pts
  const out = []
  for (let i = 0; i + 1 < pts.length; i++) {
    const p0 = pts[Math.max(0, i - 1)],
      p1 = pts[i],
      p2 = pts[i + 1],
      p3 = pts[Math.min(pts.length - 1, i + 2)]
    const n = Math.max(1, Math.ceil(Math.hypot(p2[0] - p1[0], p2[1] - p1[1]) / step))
    for (let k = 0; k < n; k++) {
      const t = k / n,
        t2 = t * t,
        t3 = t2 * t
      const f = (a, b, c, d) =>
        0.5 *
        (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
      out.push([f(p0[0], p1[0], p2[0], p3[0]), f(p0[1], p1[1], p2[1], p3[1])])
    }
  }
  out.push(pts[pts.length - 1])
  return out
}
/** 椭圆弧上的点：角度按度，0 在东、90 在南 */
export function arc(cx, cy, rx, ry, from, to, n = 24) {
  const pts = []
  for (let k = 0; k <= n; k++) {
    const a = ((from + ((to - from) * k) / n) * Math.PI) / 180
    pts.push([cx + Math.cos(a) * rx, cy + Math.sin(a) * ry])
  }
  return pts
}
/** 天然的一团（湖、小岛、林子）：半径按几组谐波起伏，再平滑；seed 定起伏的样子 */
export function blob(cx, cy, rx, ry, seed = 1, amp = 0.16, n = 40) {
  let s = seed * 9301 + 49297
  const rand = () => (s = (s * 9301 + 49297) % 233280) / 233280
  const waves = [2, 3, 5, 7].map((k) => ({
    k,
    a: ((rand() - 0.5) * 2 * amp) / Math.sqrt(k - 1),
    p: rand() * Math.PI * 2,
  }))
  const pts = []
  for (let i = 0; i < n; i++) {
    const t = (i / n) * Math.PI * 2
    const r = 1 + waves.reduce((acc, w) => acc + w.a * Math.cos(w.k * t + w.p), 0)
    pts.push([cx + Math.cos(t) * rx * r, cy + Math.sin(t) * ry * r])
  }
  pts.push(pts[0])
  return poly(smooth(pts, 30))
}

/** 形状占的格子（按格子中心判断），taken 里已有的跳过并记下新占的 */
function cellsOf(shape, taken) {
  const [x0, y0, x1, y1] = bbox(shape)
  const cells = []
  for (let r = Math.floor(y0 / CELL); r <= Math.ceil(y1 / CELL); r++)
    for (let c = Math.floor(x0 / CELL); c <= Math.ceil(x1 / CELL); c++) {
      const key = c + ',' + r
      if (taken.has(key)) continue
      if (contains(shape, (c + 0.5) * CELL, (r + 0.5) * CELL)) {
        cells.push([c, r])
        taken.add(key)
      }
    }
  return cells
}

/** 陆地底稿、岛内的水换成 layout.island 的写法：多边形照抄，带子写成带宽度的折线 */
function flatten(shape) {
  if (shape.t === 'union') return shape.s.flatMap(flatten)
  if (shape.t === 'spring') return flatten(shape.s).map((part) => ({ ...part, kind: 'spring' }))
  if (shape.t === 'poly') return [{ polygon: shape.pts.map(round) }]
  if (shape.t === 'band') return [{ line: shape.pts.map(round), width: shape.width }]
  if (shape.t === 'ellipse')
    return [{ polygon: arc(shape.cx, shape.cy, shape.rx, shape.ry, 0, 360, 48).map(round) }]
  if (shape.t === 'rect')
    return [
      {
        polygon: [
          [shape.x, shape.y],
          [shape.x + shape.w, shape.y],
          [shape.x + shape.w, shape.y + shape.h],
          [shape.x, shape.y + shape.h],
        ],
      },
    ]
  throw Error('海岸只认多边形、椭圆、矩形和带子：' + shape.t)
}
const round = ([x, y]) => [Math.round(x), Math.round(y)]
/** 带子（沿折线、宽 width）的外轮廓：两侧按相邻两段的平均法线往外推半宽，两头各补半圈 */
function bandOutline(line, width) {
  const half = width / 2
  const normal = (i) => {
    const [ax, ay] = line[Math.max(0, i - 1)],
      [bx, by] = line[Math.min(line.length - 1, i + 1)]
    const len = Math.hypot(bx - ax, by - ay) || 1
    return [-(by - ay) / len, (bx - ax) / len]
  }
  const side = (sign) =>
    line.map(([x, y], i) => [x + normal(i)[0] * half * sign, y + normal(i)[1] * half * sign])
  const cap = ([x, y], [nx, ny]) =>
    [1, 2, 3].map((k) => {
      const a = (k / 4) * Math.PI
      // 从 +法线转到 -法线，经过路头外侧
      const [tx, ty] = [ny, -nx]
      return [
        x + (nx * Math.cos(a) + tx * Math.sin(a)) * half,
        y + (ny * Math.cos(a) + ty * Math.sin(a)) * half,
      ]
    })
  const last = line.length - 1
  const [ex, ey] = normal(last),
    [sx, sy] = normal(0)
  return [
    ...side(1),
    ...cap(line[last], [ex, ey]),
    ...side(-1).reverse(),
    ...cap(line[0], [-sx, -sy]),
  ].map(round)
}
const length = (pts) =>
  pts.reduce((s, p, i) => (i ? s + Math.hypot(p[0] - pts[i - 1][0], p[1] - pts[i - 1][1]) : 0), 0)
const minutesOf = (pts) => Number((length(pts) / UNITS_PER_MINUTE).toFixed(4))

// ---------- 从已有地图里搬内景 ----------

/** 一间房的内景：大小、门、家具和落脚点（房间坐标），连同到达点、门内外节点和门的通道编号 */
export function roomOf(source, id) {
  const space = source.layout.spaces.find((s) => s.id === id)
  if (!space) throw Error(`内景来源里没有房间 ${id}`)
  const place = source.topology.places.find((p) => p.locale === id)
  const arrival = source.topology.stations.find((s) => s.id === place.arrival_station)
  const door = source.topology.passages.find(
    (p) => p.b === id && p.node_a !== p.node_b && p.capabilities.includes('通行')
  )
  return {
    bounds: space.bounds,
    door: space.door_inside_local,
    name: place.name,
    ids: {
      arrival: arrival.id,
      inside: arrival.node,
      outside: door.node_a,
      passage: door.id,
    },
    ...contentsOf(source, id),
  }
}

/** 自己写的内景：房间坐标里的大小、门（南墙正中往里一点）、家具 [编号, 定义, 名字, x, y] 和
 *  落脚点 [编号, 名字, 活动, 姿势, 角色, x, y] */
export function room(width, height, props, stations = []) {
  return {
    bounds: { x: 0, y: 0, width, height },
    door: [width / 2, height - 48],
    props: props.map(([id, definition, name, x, y]) => ({
      id,
      definition,
      name,
      mark: { id, x, y, name, appearance: { glyph: 'box', color: '#b79a70' } },
    })),
    stations: stations.map(([id, name, activity, pose, role, x, y]) => ({
      id,
      name,
      kind: 'slot',
      activity_id: activity,
      pose_family: pose,
      role,
      mark: { id, x, y },
    })),
  }
}
/** 自己写的内景里的道具和落脚点要带上所在的地点 */
export const own = (r, locale) => ({
  ...r,
  props: r.props.map((p) => ({ ...p, locale })),
  stations: r.stations.map((s) => ({ ...s, locale })),
})

/** 一处地点的道具和落脚点（不含到达点），原样带着编号、名字和标记 */
function contentsOf(source, locale) {
  const T = source.topology,
    L = source.layout
  const place = T.places.find((p) => p.locale === locale)
  const props = T.props
    .filter((p) => p.locale === locale)
    .map((p) => ({ ...p, mark: L.props.find((m) => m.id === p.id) }))
  const stations = T.stations
    .filter((s) => s.locale === locale && s.id !== place?.arrival_station)
    .map((s) => ({ ...s, mark: L.stations.find((m) => m.id === s.id) }))
  return { props, stations }
}

// ---------- 地图 ----------

/**
 * source 是搬内景和户外道具的那份地图文档。roads 是「小镇道路」这处地点的编号：路口和房门外都算在它里面。
 * script 是生成这张图的脚本（记在拓扑的 source 里）；environment 是地图风格、worldview 是随图带的世界观（见文件头）；
 * entry 是新来的人落在哪（{ locale, station }），meals 是三餐，不给都照 source
 */
export function townMap({
  id,
  name,
  description,
  width,
  height,
  source,
  roads,
  script = 'scripts/maps/default-town.mjs',
  environment,
  worldview,
  entry,
  meals,
}) {
  const regions = [],
    buildings = [],
    streets = [],
    places = [],
    outdoor = [],
    ruins = [],
    standees = [],
    flocks = []
  const taken = new Set()
  let island = null
  const api = {
    /** 只看不进的楼：占地矩形 [x, y, w, h]，墙高 height（贴图像素），look 同房子（屋顶色、屋面、墙面、屋顶形状） */
    ruin(rid, [x, y, w, h], height, look) {
      ruins.push({ id: rid, x, y, w, h, height, ...(look ? { look } : {}) })
      return api
    },
    /** 按坐标立的立牌：kind 是风格包 plans 里的名字；flip 左右翻，on 是蹲到哪栋房子或楼的墙顶上；
     *  court 是立体的看台：size 是外半径，facing 是敞开的一面朝哪（不给朝南） */
    standee(kind, [x, y], { flip, on, size, facing } = {}) {
      standees.push({
        kind,
        x: Math.round(x),
        y: Math.round(y),
        ...(flip ? { flip: true } : {}),
        ...(on ? { on } : {}),
        ...(size ? { size } : {}),
        ...(facing ? { facing } : {}),
      })
      return api
    },
    /** 在 (x, y) 上空、离地 height（地图单位）盘旋的 count 只鸟 */
    flock([x, y], height, count) {
      flocks.push({ x, y, height, count })
      return api
    },
    /** 陆地底稿和岛内的水，冲刷参数见前端的 IslandDesign */
    island(land, water, shape = {}) {
      island = {
        // 陆地只认多边形：带子（伸进海里的旧堤）换成它的外轮廓
        land: flatten(land).map((p) => p.polygon ?? bandOutline(p.line, p.width)),
        water: flatten(water),
        ...shape,
      }
      return api
    },
    /** 一块室外区域，先登记的先占格子。place 给了就是一处地点：type、summary、features 是地点的类型、简介、
     *  看得见的东西；arrival 是到达点（station、node 是它落脚点和节点的编号），onRoad 给了且离路不到这么远时
     *  到达点就落在路上；from 是来源地图里搬道具和落脚点的地点，at 按编号指定其中几件的位置，
     *  rename 为 true 时道具名字里原来的地名换成新地名；
     *  props 是新添的道具 { id, definition, name, at }，stations 是新添的落脚点 { id, name, at, activity, pose, role }；
     *  landmark 指定立什么地标（风格包 plans 里的名字），不给按 kind；label 是地名标在哪（地图坐标），
     *  不给标在离区域边最远的格子上 */
    region(rid, rname, kind, shape, { decor, facing, landmark, label, place } = {}) {
      const cells = cellsOf(shape, taken)
      if (!cells.length) throw Error(`区域 ${rid} 一格也没占到`)
      regions.push({
        id: rid,
        name: rname,
        cell_size: CELL,
        cells,
        kind,
        ...(label ? { label_anchor: round(label) } : {}),
        ...(decor ? { decor } : {}),
        ...(facing ? { facing } : {}),
        ...(landmark ? { landmark } : {}),
      })
      if (place) {
        places.push({ locale: rid, name: rname, ...place })
        outdoor.push({ locale: rid, ...place })
      }
      return api
    },
    /** 一条路：折线（默认平滑），宽 width；bridge 是跨水时的桥（stone、wood） */
    road(rid, pts, width = 60, { curve = true, bridge } = {}) {
      const line = (curve ? smooth(pts) : pts).map(round)
      streets.push({ id: rid, line, width, bridge })
      return api
    },
    /** 房子：占地矩形 [x, y, w, h]，内景按 room 编号（默认同 sid）从来源地图搬，或者直接给一份 room；
     *  内景按比例缩放到占地大小（保持长宽比，中心对齐）。look 是屋顶色、墙面；place 是地点的类型、简介 */
    building(sid, sname, kind, [x, y, w, h], { room = sid, look, place } = {}) {
      const r = typeof room === 'string' ? roomOf(source, room) : room
      // 搬过来的家具名字带着原来的地名（「北街一号住宅单人床」），换成新名字
      const rename =
        r.name && r.name !== sname ? (text) => text.replaceAll(r.name, sname) : undefined
      const b = r.bounds
      const scale = Number(Math.sqrt((w * h) / (b.width * b.height)).toFixed(4))
      const cx = x + w / 2,
        cy = y + h / 2
      const offset_x = Number((cx - scale * (b.x + b.width / 2)).toFixed(1)),
        offset_y = Number((cy - scale * (b.y + b.height / 2)).toFixed(1))
      const at = ([lx, ly]) => [offset_x + scale * lx, offset_y + scale * ly]
      // 门开在内景门最近的那面墙外 12 个单位
      const [dx, dy] = at(r.door)
      const x0 = offset_x + scale * b.x,
        y0 = offset_y + scale * b.y,
        x1 = x0 + scale * b.width,
        y1 = y0 + scale * b.height
      const walls = [
        [dy - y0, [dx, y0 - 12]],
        [y1 - dy, [dx, y1 + 12]],
        [dx - x0, [x0 - 12, dy]],
        [x1 - dx, [x1 + 12, dy]],
      ]
      const wall = walls.map((w, k) => [...w, k]).sort((p, q) => p[0] - q[0])[0]
      const outside = round(wall[1])
      const dir = [
        [0, -1],
        [0, 1],
        [-1, 0],
        [1, 0],
      ][wall[2]]
      const short = sid.replace(/^indoor_/, '')
      buildings.push({
        id: sid,
        name: sname,
        kind,
        bounds: b,
        unfold: { scale, offset_x, offset_y },
        door: r.door,
        outside,
        dir,
        box: [x0, y0, x1, y1],
        look,
        rename,
        ids: r.ids ?? {
          arrival: `place_arrival_${short}`,
          inside: `portal_${short}_inside`,
          outside: `portal_${short}_outside`,
          passage: `connection_${sid}`,
        },
        props: r.props,
        stations: r.stations,
      })
      if (place) places.push({ locale: sid, name: sname, building: true, ...place })
      return api
    },
    build() {
      return assemble({
        id,
        name,
        description,
        width,
        height,
        source,
        roads,
        script,
        environment,
        worldview,
        entry,
        meals,
        island,
        regions,
        buildings,
        streets,
        places,
        outdoor,
        ruins,
        standees,
        flocks,
      })
    },
  }
  return api
}

// ---------- 路网 ----------

/** 路上的一点：第 seg 段、段内 t；按 (seg + t) 排序 */
function pointOn(line, seg, t) {
  const [ax, ay] = line[seg],
    [bx, by] = line[Math.min(seg + 1, line.length - 1)]
  return [ax + (bx - ax) * t, ay + (by - ay) * t]
}
function nearestOn(line, [x, y]) {
  let best = { d: Infinity, seg: 0, t: 0 }
  for (let i = 0; i + 1 < line.length; i++) {
    const r = toSegment(x, y, ...line[i], ...line[i + 1])
    if (r.d < best.d) best = { d: r.d, seg: i, t: r.t }
  }
  return { ...best, at: pointOn(line, best.seg, best.t) }
}
/** 两条线段的交点参数；交在折线的拐点上也算（同一处会从相邻两段各找到一次，节点按位置合并） */
function crossing(a, b, c, d) {
  const r = [b[0] - a[0], b[1] - a[1]],
    s = [d[0] - c[0], d[1] - c[1]]
  const den = r[0] * s[1] - r[1] * s[0]
  if (Math.abs(den) < 1e-9) return null
  const t = ((c[0] - a[0]) * s[1] - (c[1] - a[1]) * s[0]) / den,
    u = ((c[0] - a[0]) * r[1] - (c[1] - a[1]) * r[0]) / den
  const eps = 1e-6
  if (t < -eps || t > 1 + eps || u < -eps || u > 1 + eps) return null
  return { t: Math.min(1, Math.max(0, t)), u: Math.min(1, Math.max(0, u)) }
}

/**
 * 路网连成图：路头碰到别的路（JOIN 以内）先挪到那条路上，路与路相交、路头落在别的路上处断开；
 * connectors 是要接到路网上的点（房门外、户外地点的到达点），各接一条小路到最近的路上，
 * 给了 onRoad 且离路不到这么远的直接落在路上。返回用到的节点和切好的路段。
 */
function network(streets, connectors) {
  for (const [k, s] of streets.entries())
    for (const idx of [0, s.line.length - 1]) {
      let best = null
      for (const [j, o] of streets.entries()) {
        if (j === k) continue
        const near = nearestOn(o.line, s.line[idx])
        if (near.d <= JOIN && (!best || near.d < best.d)) best = near
      }
      if (best) s.line[idx] = round(best.at)
    }
  const nodes = new Map() // key → { x, y, kind, id?, locale? }
  const node = ([x, y], extra) => {
    for (const [key, n] of nodes)
      if (Math.hypot(n.x - x, n.y - y) < MERGE) {
        if (extra && !n.id) Object.assign(n, extra)
        return key
      }
    const key = `k${nodes.size}`
    nodes.set(key, { x: Math.round(x), y: Math.round(y), kind: 'junction', ...extra })
    return key
  }
  // 每条路上的断点：pos 是沿路的位置（第几段 + 段内比例）
  const cuts = streets.map(() => [])
  const cutAt = (k, pos, key) => cuts[k].push({ pos, key })
  for (const [k, s] of streets.entries()) {
    const ends = [
      [0, s.line[0]],
      [s.line.length - 1, s.line[s.line.length - 1]],
    ]
    for (const [pos, at] of ends) {
      const key = node(at)
      cutAt(k, pos, key)
      for (const [j, o] of streets.entries()) {
        if (j === k) continue
        const near = nearestOn(o.line, at)
        if (near.d < 1.5) cutAt(j, near.seg + near.t, key)
      }
    }
  }
  for (let k = 0; k < streets.length; k++)
    for (let j = k + 1; j < streets.length; j++) {
      const A = streets[k].line,
        B = streets[j].line
      for (let a = 0; a + 1 < A.length; a++)
        for (let b = 0; b + 1 < B.length; b++) {
          const hit = crossing(A[a], A[a + 1], B[b], B[b + 1])
          if (!hit) continue
          const key = node(pointOn(A, a, hit.t))
          cutAt(k, a + hit.t, key)
          cutAt(j, b + hit.u, key)
        }
    }
  const access = []
  for (const c of connectors) {
    let best = null
    for (const [k, s] of streets.entries()) {
      const near = nearestOn(s.line, c.at)
      if (!best || near.d < best.near.d) best = { k, near }
    }
    if (!best) throw Error(`${c.id} 附近没有路`)
    // 房门：小路先试着从门口笔直出去，碰到的第一条路比最近的那条远得不多就接它
    if (c.dir) {
      const far = [c.at[0] + c.dir[0] * RAY, c.at[1] + c.dir[1] * RAY]
      let hit = null
      for (const [k, s] of streets.entries())
        for (let i = 0; i + 1 < s.line.length; i++) {
          const x = crossing(c.at, far, s.line[i], s.line[i + 1])
          if (x && (!hit || x.t < hit.along))
            hit = {
              k,
              along: x.t,
              near: { seg: i, t: x.u, d: x.t * RAY, at: pointOn(s.line, i, x.u) },
            }
        }
      if (hit && hit.near.d <= best.near.d * 1.6 + 40) best = hit
    }
    const extra = { id: c.id, kind: c.kind, locale: c.locale }
    if (c.onRoad && best.near.d <= c.onRoad) {
      cutAt(best.k, best.near.seg + best.near.t, node(best.near.at, extra))
      continue
    }
    const own = node(c.at, extra)
    const key = node(best.near.at)
    cutAt(best.k, best.near.seg + best.near.t, key)
    access.push({ road: c.id, from: own, to: key, width: ACCESS_WIDTH })
  }
  const edges = []
  for (const [k, s] of streets.entries()) {
    const list = cuts[k].sort((p, q) => p.pos - q.pos)
    for (let i = 0; i + 1 < list.length; i++) {
      const a = list[i],
        b = list[i + 1]
      if (a.key === b.key && b.pos - a.pos < 1e-6) continue
      const pa = nodes.get(a.key),
        pb = nodes.get(b.key)
      const line = [[pa.x, pa.y]]
      for (let v = Math.floor(a.pos) + 1; v < b.pos; v++) if (v > a.pos + 1e-6) line.push(s.line[v])
      line.push([pb.x, pb.y])
      const clean = line.filter(
        (p, n) => n === 0 || Math.hypot(p[0] - line[n - 1][0], p[1] - line[n - 1][1]) > 1
      )
      if (clean.length < 2) continue
      edges.push({ from: a.key, to: b.key, line: clean, width: s.width, bridge: s.bridge })
    }
  }
  for (const a of access) {
    const from = nodes.get(a.from),
      to = nodes.get(a.to)
    edges.push({
      from: a.from,
      to: a.to,
      line: [
        [from.x, from.y],
        [to.x, to.y],
      ],
      width: a.width,
    })
  }
  // 只留用到的节点；路口按位置（先北后南、先西后东）编号
  const used = new Set(edges.flatMap((e) => [e.from, e.to]))
  for (const key of [...nodes.keys()]) if (!used.has(key)) nodes.delete(key)
  const junctions = [...nodes.values()].filter((n) => !n.id).sort((p, q) => p.y - q.y || p.x - q.x)
  junctions.forEach((n, i) => (n.id = `junction_${String(i + 1).padStart(2, '0')}`))
  return { nodes, edges }
}

// ---------- 拼文档 ----------

function assemble(m) {
  const { source, roads } = m
  const OUTDOOR = 'town_outdoor'
  const placeName = new Map(m.places.map((p) => [p.locale, p.name]))
  const locales = []
  const passages = [],
    stations = [],
    props = []
  const layoutStations = [],
    layoutProps = [],
    layoutNodes = []
  const connectors = []

  // 房子：门外接到路上；内景的家具、落脚点照搬
  for (const b of m.buildings) {
    connectors.push({
      id: b.ids.outside,
      kind: 'portal_outside',
      locale: roads,
      at: b.outside,
      dir: b.dir,
    })
    layoutNodes.push({
      id: b.ids.inside,
      kind: 'portal_inside',
      space: b.id,
      x: b.door[0],
      y: b.door[1],
    })
    stations.push({
      id: b.ids.arrival,
      locale: b.id,
      name: `${b.name}·到达点`,
      kind: 'arrival',
      node: b.ids.inside,
    })
    layoutStations.push({ id: b.ids.arrival, space: b.id, x: b.door[0], y: b.door[1] })
    passages.push({
      id: b.ids.passage,
      a: roads,
      b: b.id,
      node_a: b.ids.outside,
      node_b: b.ids.inside,
      minutes: 1,
      capabilities: ['通行', '视', '听'],
    })
    const rename = (text) => (text === undefined || !b.rename ? text : b.rename(text))
    for (const s of b.stations) {
      const { mark, ...station } = s
      stations.push({ ...station, name: rename(station.name) })
      layoutStations.push({ id: s.id, space: b.id, x: mark.x, y: mark.y })
    }
    for (const p of b.props) {
      const { mark, ...prop } = p
      props.push(prop.name === undefined ? prop : { ...prop, name: rename(prop.name) })
      layoutProps.push({ ...mark, name: rename(mark.name), place_name: b.name, space: b.id })
    }
  }

  // 户外地点：到达点接到路上；道具、落脚点从来源地图搬过来平移，或者用设计里给的
  for (const o of m.outdoor) {
    connectors.push({
      id: o.node,
      kind: 'place_arrival',
      locale: o.locale,
      at: o.arrival,
      onRoad: o.onRoad,
    })
    stations.push({
      id: o.station,
      locale: o.locale,
      name: `${placeName.get(o.locale)}·到达点`,
      kind: 'arrival',
      node: o.node,
    })
    layoutStations.push({ id: o.station, space: OUTDOOR, x: o.arrival[0], y: o.arrival[1] })
    if (o.from) {
      const old = contentsOf(source, o.from)
      const oldPlace = source.topology.places.find((p) => p.locale === o.from)
      const oldArrival = source.layout.stations.find((s) => s.id === oldPlace.arrival_station)
      const shift = ([x, y], id) => {
        const fixed = o.at?.[id]
        if (fixed) return fixed
        return [
          Math.round(x - oldArrival.x + o.arrival[0]),
          Math.round(y - oldArrival.y + o.arrival[1]),
        ]
      }
      // rename：搬过来的道具名字带着原来的地名（「中心广场公告栏」），换成新地名
      const renamed = (named) =>
        o.rename && named.name !== undefined
          ? { ...named, name: named.name.replaceAll(oldPlace.name, placeName.get(o.locale)) }
          : named
      for (const p of old.props) {
        const { mark, ...prop } = p
        const [x, y] = shift([mark.x, mark.y], p.id)
        props.push(renamed({ ...prop, locale: o.locale }))
        layoutProps.push(
          renamed({ ...mark, x, y, place_name: placeName.get(o.locale), space: OUTDOOR })
        )
      }
      for (const s of old.stations) {
        const { mark, ...station } = s
        const [x, y] = shift([mark.x, mark.y], s.id)
        stations.push({ ...station, locale: o.locale })
        layoutStations.push({ id: s.id, space: OUTDOOR, x, y })
      }
    }
    for (const p of o.props ?? []) {
      props.push({ id: p.id, definition: p.definition, name: p.name, locale: o.locale })
      layoutProps.push({
        id: p.id,
        x: p.at[0],
        y: p.at[1],
        name: p.name,
        place_name: placeName.get(o.locale),
        space: OUTDOOR,
        appearance: p.appearance ?? { glyph: 'box', color: '#b79a70' },
      })
    }
    for (const s of o.stations ?? []) {
      stations.push({
        id: s.id,
        locale: o.locale,
        name: s.name,
        kind: 'slot',
        activity_id: s.activity,
        pose_family: s.pose,
        role: s.role,
      })
      layoutStations.push({ id: s.id, space: OUTDOOR, x: s.at[0], y: s.at[1] })
    }
  }

  // 路网；落在路上的到达点，标记跟着挪到节点上
  const { nodes, edges } = network(m.streets, connectors)
  for (const n of nodes.values()) {
    layoutNodes.push({ id: n.id, kind: n.kind, space: OUTDOOR, x: n.x, y: n.y })
    const o = m.outdoor.find((p) => p.node === n.id)
    const mark = o && layoutStations.find((s) => s.id === o.station)
    if (mark) Object.assign(mark, { x: n.x, y: n.y })
  }
  const localeOf = (n) => n.locale ?? roads
  const layoutEdges = []
  const seen = new Map()
  for (const e of edges) {
    const a = nodes.get(e.from),
      b = nodes.get(e.to)
    let eid = `edge_${a.id}__${b.id}`
    seen.set(eid, (seen.get(eid) ?? 0) + 1)
    if (seen.get(eid) > 1) eid += `_${seen.get(eid)}`
    const from = localeOf(a),
      to = localeOf(b)
    locales.push({
      id: eid,
      name: `路：${placeName.get(from)} ↔ ${placeName.get(to)}`,
      kind: 'transit',
      minutes: minutesOf(e.line),
      from_node: a.id,
      to_node: b.id,
    })
    layoutEdges.push({
      id: eid,
      from_node: a.id,
      to_node: b.id,
      from_locale: from,
      to_locale: to,
      polyline: e.line,
      width: e.width,
      ...(e.bridge ? { bridge: e.bridge } : {}),
    })
    for (const [side, n, locale] of [
      ['a', a, from],
      ['b', b, to],
    ])
      passages.push({
        id: `pass__${eid}__${side}`,
        a: eid,
        b: locale,
        node_a: n.id,
        node_b: n.id,
        minutes: 0,
        capabilities: ['通行', '视', '听'],
      })
  }

  // 处所：地点（驻留）在前，路段（穿过）在后
  const dwell = m.places.map((p) => ({ id: p.locale, name: p.name, kind: 'dwell' }))
  const topology = {
    schema_version: 1,
    source: m.script,
    notes: '路段分钟数 = 折线长度 / 144（每米 12 个地图单位、每分钟 12 米）；跨区域的路段不切开。',
    locales: [...dwell, ...locales],
    passages,
    stations,
    places: m.places.map((p) => ({
      name: p.name,
      locale: p.locale,
      arrival_station: p.station ?? m.buildings.find((b) => b.id === p.locale).ids.arrival,
      type: p.type,
      summary: p.summary,
      visible_features: p.features ?? [],
      ...(p.residential ? { residential: true } : {}),
    })),
    props,
    meals: m.meals ?? source.topology.meals,
    entry: m.entry ?? source.topology.entry,
  }
  const layout = {
    schema_version: 1,
    canvas: { width: m.width, height: m.height },
    ...(m.island ? { island: m.island } : {}),
    regions: m.regions,
    nodes: layoutNodes,
    edges: layoutEdges,
    spaces: m.buildings.map((b) => ({
      id: b.id,
      name: b.name,
      kind: b.kind,
      bounds: b.bounds,
      unfold: b.unfold,
      door_outside: b.outside,
      door_inside_local: b.door,
      ...(b.look ? { look: b.look } : {}),
    })),
    stations: layoutStations,
    props: layoutProps,
    ...(m.ruins.length ? { ruins: m.ruins } : {}),
    ...(m.standees.length ? { standees: m.standees } : {}),
    ...(m.flocks.length ? { flocks: m.flocks } : {}),
  }
  return {
    schema_version: 1,
    id: m.id,
    name: m.name,
    description: m.description,
    origin: 'builtin',
    style_id: 'svg-town-v1',
    style_version: 1,
    ...(m.environment ? { environment: m.environment } : {}),
    ...(m.worldview ? { worldview: m.worldview } : {}),
    topology,
    layout,
  }
}
