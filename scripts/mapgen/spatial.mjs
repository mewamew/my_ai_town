// 版本 2 地图的三维部分：地形、建筑、家具、室内通道、植被，以及把结果写回二维拓扑。
import { stream, noise, hashDocument, seal } from './document.mjs'
import { contains, dist, length3, orient, overlaps, project, segmentRect } from './geometry.mjs'
import { GENERATOR_VERSION, GenerationError, manifest } from './budget.mjs'
import { publicSpaceLoop } from './public-space-loop.mjs'
// 地形双线性采样与前端共用 town-shared 的实现，生成与渲染算出的高度一致。
import { heightAt } from '../../frontend/town-shared/src/spatial.ts'

const M = manifest.parameters
const S = M.svg_units_per_metre,
  q = (n) => Math.round(n * 1e5) / 1e5
// 家具放置与室内寻路的手感参数，单位为米。
const FURNITURE = Object.freeze({
  wall_gap: 0.55, // 家具外沿到房间边界的最小距离
  grid: 0.4, // 候选位置步长
  clearance: 0.4, // 家具四周留给走动的空间
  door_gap: 1.65, // 家具到到达点的最小距离
  anchor_offset: 0.45, // 操作位置在家具正面之外的距离
  sample_step: 0.2, // 判断通道是否在活动空间内时的采样间距
  corner_gap: 0.02, // 绕行家具时拐点离障碍的距离
  route_step: 0.7, // 室外道路折线重采样间距
})
const VEGETATION = Object.freeze({
  density: { sparse: 0.45, medium: 1, dense: 1.7 },
  max_instances: 1600,
  area_per_plant: 35, // 每株植被平均占地（平方米）
  per_cluster: 12,
  cluster_radius: 18,
  min_height: 0.7, // 低于此高度视为岸边或水面，不长植物
  floor_margin: 2, // 离活动空间边界的距离
  road_margin: 1.5, // 离道路边缘的距离
  spacing: 1.5,
  rock_ratio: 0.13,
})

// 建筑与区域的米制包围盒。
const box = (x, y, w, h) => ({ x: x / S, y: y / S, w: w / S, h: h / S })
const roomBox = (r) => box(r.unfold.offset_x, r.unfold.offset_y, r.bounds.width, r.bounds.height)
const regionBox = (r) => box(r.bounds.x, r.bounds.y, r.bounds.width, r.bounds.height)
const corners = ({ x, y, w, h }) => [
  [x, y],
  [x + w, y],
  [x + w, y + h],
  [x, y + h],
]

function ground(document, seed, tuning) {
  const w = document.layout.canvas.width / S,
    h = document.layout.canvas.height / S
  const margin = Math.max(12, Math.min(w, h) * 0.3),
    width = w + margin * 2,
    depth = h + margin * 2,
    step = Math.max(width, depth) / 128,
    columns = Math.ceil(width / step) + 1,
    rows = Math.ceil(depth / step) + 1
  const field = noise(seed, 'terrain', 18),
    coast = noise(seed, 'coastline', 16)
  const cloud = [
    ...document.layout.spaces.flatMap((s) => corners(roomBox(s))),
    ...document.layout.regions
      .filter((r) => r.bounds)
      .flatMap(({ bounds: b }) => [
        [b.x / S, b.y / S],
        [(b.x + b.width) / S, b.y / S],
        [(b.x + b.width) / S, (b.y + b.height) / S],
        [b.x / S, (b.y + b.height) / S],
      ]),
    ...document.layout.edges.flatMap((e) => e.polyline.map((p) => p.map((v) => v / S))),
  ].sort((a, b) => a[0] - b[0] || a[1] - b[1])
  const half = (ps) => {
    const h = []
    for (const p of ps) {
      while (h.length >= 2 && orient(h.at(-2), h.at(-1), p) <= 0) h.pop()
      h.push(p)
    }
    return h.slice(0, -1)
  }
  const hull = [...half(cloud), ...half([...cloud].reverse())]
  const t = {
    origin: [-margin, -margin],
    step: q(step),
    columns,
    rows,
    heights: [],
    land: [],
    sea_level: 0,
  }
  // 建成区的凸包整体保留为陆地；海岸缓冲只作用在凸包之外。
  for (let z = 0; z < rows; z++)
    for (let x = 0; x < columns; x++) {
      const px = x * t.step - margin,
        pz = z * t.step - margin
      const interior = hull.every((a, i) => orient(a, hull[(i + 1) % hull.length], [px, pz]) >= 0),
        out = interior
          ? 0
          : Math.min(
              ...hull.map((a, i) => project([px, pz], a, hull[(i + 1) % hull.length]).distance)
            )
      const shore = margin * (0.55 + coast(px, pz) * 0.23),
        fall = Math.max(0, out - shore * 0.63)
      let y = 2.1 + field(px, pz) * 0.6 - fall * (tuning ? 0.42 : 0.72)
      if (tuning?.relief && y > 0.3) {
        // Broad planted shoulders; keep the complete road width and every floor
        // clear before changing terrain, so the renderer cannot hide a mismatch.
        let clearance = Infinity
        for (const room of document.layout.spaces) {
          const rx = room.unfold.offset_x / S,
            rz = room.unfold.offset_y / S
          clearance = Math.min(
            clearance,
            Math.hypot(
              Math.max(rx - px, 0, px - rx - room.bounds.width / S),
              Math.max(rz - pz, 0, pz - rz - room.bounds.height / S)
            )
          )
        }
        for (const region of document.layout.regions.filter((r) => r.kind !== 'road')) {
          const b = region.bounds
          clearance = Math.min(
            clearance,
            Math.hypot(
              Math.max(b.x / S - px, 0, px - (b.x + b.width) / S),
              Math.max(b.y / S - pz, 0, pz - (b.y + b.height) / S)
            )
          )
        }
        for (const edge of document.layout.edges)
          for (let j = 1; j < edge.polyline.length; j++) {
            clearance = Math.min(
              clearance,
              project(
                [px, pz],
                edge.polyline[j - 1].map((v) => v / S),
                edge.polyline[j].map((v) => v / S)
              ).distance -
                edge.width / S / 2
            )
          }
        const u = Math.max(0, Math.min(1, (clearance - 5) / 15))
        const bank = Math.max(0, Math.min(1, (y - 0.3) / 1.7))
        const wave = (Math.sin(px / 22 + seed * 0.03) + Math.cos(pz / 29 - seed * 0.02) + 2) / 4
        y += tuning.relief * u * u * (3 - 2 * u) * bank * bank * (3 - 2 * bank) * wave
      }
      t.heights.push(q(Math.max(-3, y)))
      t.land.push(y > 0.15 ? 1 : 0)
    }
  // 建筑和活动区域是平地：以中心高度为准，向四周 5 米内渐变。
  const areas = [
    ...document.layout.spaces.map(roomBox),
    ...document.layout.regions.filter((r) => r.kind !== 'road').map(regionBox),
  ]
  for (const r of areas) {
    r.level = q(heightAt(t, r.x + r.w / 2, r.y + r.h / 2))
    for (let z = 0; z < rows; z++)
      for (let x = 0; x < columns; x++) {
        const px = x * t.step - margin,
          pz = z * t.step - margin,
          d = Math.hypot(
            Math.max(r.x - px, 0, px - r.x - r.w),
            Math.max(r.y - pz, 0, pz - r.y - r.h)
          )
        if (d > 5) continue
        const blend = Math.max(0, 1 - d / 5),
          i = z * columns + x
        t.heights[i] = q(t.heights[i] * (1 - blend) + r.level * blend)
      }
  }
  return t
}

// 在同一活动空间内从 a 走到 b：先试直线，再在障碍四角之间做 Dijkstra；不通返回 null。
function route(a, b, obstacles, valid) {
  const clear = (p, q) => {
    if (obstacles.some((r) => segmentRect(p, q, r))) return false
    const n = Math.ceil(dist(p, q) / FURNITURE.sample_step) || 1
    for (let i = 0; i <= n; i++)
      if (!valid([p[0] + ((q[0] - p[0]) * i) / n, p[1] + ((q[1] - p[1]) * i) / n])) return false
    return true
  }
  if (clear(a, b)) return [a, b]
  const g = FURNITURE.corner_gap
  const waypoints = obstacles
    .flatMap((r) => [
      [r.x - g, r.y - g],
      [r.x + r.w + g, r.y - g],
      [r.x + r.w + g, r.y + r.h + g],
      [r.x - g, r.y + r.h + g],
    ])
    .filter(valid)
  const points = [a, b, ...waypoints],
    ds = points.map(() => Infinity),
    previous = [],
    done = new Set()
  ds[0] = 0
  for (let guard = 0; guard < points.length; guard++) {
    let u = -1
    for (let i = 0; i < points.length; i++) if (!done.has(i) && (u < 0 || ds[i] < ds[u])) u = i
    if (u < 0 || !Number.isFinite(ds[u])) break
    if (u === 1) {
      const ps = []
      for (let k = 1; k !== undefined; k = previous[k]) ps.unshift(points[k])
      return ps
    }
    done.add(u)
    for (let v = 0; v < points.length; v++)
      if (
        !done.has(v) &&
        ds[u] + dist(points[u], points[v]) < ds[v] &&
        clear(points[u], points[v])
      ) {
        ds[v] = ds[u] + dist(points[u], points[v])
        previous[v] = u
      }
  }
  return null
}

function buildings(scene, outdoor = false) {
  const { layout, plan, seed, point, places, visualStations } = scene
  const rows = outdoor
    ? plan.places
        .filter((p) => p.outdoor && p.assetId)
        .map((p) => ({
          id: p.id,
          unfold: { offset_x: p.x - p.w / 2, offset_y: p.y - p.h / 2 },
          bounds: { width: p.w, height: p.h },
          door_outside: p.door,
        }))
    : layout.spaces
  return rows.map((r, i) => {
    const p = places.get(r.id),
      dx =
        (r.door_outside?.[0] ?? r.unfold.offset_x + r.bounds.width / 2) -
        r.unfold.offset_x -
        r.bounds.width / 2,
      dz =
        (r.door_outside?.[1] ?? r.unfold.offset_y + r.bounds.height) -
        r.unfold.offset_y -
        r.bounds.height / 2
    // 朝向由门相对中心的方向决定；东西向的房子宽深互换。
    const yaw = Number.isFinite(p.assetYaw)
        ? p.assetYaw
        : p.entranceSource
          ? { north: Math.PI, south: 0, east: Math.PI / 2, west: -Math.PI / 2 }[p.doorFace]
          : Math.abs(dx) > Math.abs(dz)
            ? dx > 0
              ? Math.PI / 2
              : -Math.PI / 2
            : dz < 0
              ? Math.PI
              : 0,
      swap = p.entranceSource ? Math.abs(Math.sin(yaw)) > 0.5 : Math.abs(dx) > Math.abs(dz),
      rng = stream(seed, 'building-form', r.id),
      facade = stream(seed, 'facade', String(p.district ?? 0))
    return {
      id: r.id,
      kind: p.kind,
      size: p.size,
      ...(p.assetId ? { assetId: p.assetId } : {}),
      ...(p.entranceSource ? { entranceSource: p.entranceSource } : {}),
      position: point([
        p.entranceSource ? p.x / S : (r.unfold.offset_x + r.bounds.width / 2) / S,
        p.entranceSource ? p.y / S : (r.unfold.offset_y + r.bounds.height / 2) / S,
      ]),
      yaw: q(yaw),
      width: (p.plotWidth ?? (swap ? p.h : p.w)) / S,
      depth: (p.plotDepth ?? (swap ? p.w : p.h)) / S,
      archetype: manifest.archetypes[(i + Math.floor(rng() * 3)) % 3],
      wall_variant: Math.floor(facade() * 3),
      roof_variant: Math.floor(stream(seed, 'roof', r.id)() * 3),
      height: M.wall_height,
      door: point(scene.world(visualStations.get(`at_${r.id}`))),
      closed: plan.places.length === 1,
    }
  })
}

function floors(scene) {
  const { topology, rooms, regions } = scene
  return topology.places.map((p) => {
    const r = rooms.get(p.locale)
    return {
      id: p.locale,
      bounds: r ? roomBox(r) : regionBox(regions.get(p.locale)),
      indoor: !!r,
    }
  })
}

function props(scene) {
  const { layout, propDefs, point, world } = scene
  return layout.props.map((m) => {
    const d = propDefs.get(m.id),
      model = manifest.props[d.definition.split('@')[0]] ?? {
        model: 'generic',
        footprint: [0.65, 0.65],
        anchor: [0, 0, 0.8],
      },
      p = point(world(m))
    return {
      id: m.id,
      locale: d.locale,
      model: model.model,
      position: p,
      yaw: 0,
      footprint: model.footprint,
      anchor: point([p[0] + model.anchor[0], p[2] + model.anchor[2]]),
    }
  })
}

// 家具按占地和操作位置在活动空间内重新摆放；二维图上的原坐标只作为偏好，不保证无碰撞。
function placeFurniture(scene, floors, propsByFloor) {
  const { rooms, marks, point, world, visualStations } = scene
  const F = FURNITURE
  for (const f of floors) {
    const used = [],
      a = world(visualStations.get(`at_${f.id}`))
    for (const p of propsByFloor.get(f.id)) {
      const [w, d] = p.footprint,
        preferred = [p.position[0], p.position[2]],
        candidates = []
      for (
        let z = f.bounds.y + d / 2 + F.wall_gap;
        z < f.bounds.y + f.bounds.h - d / 2 - 1;
        z += F.grid
      )
        for (
          let x = f.bounds.x + w / 2 + F.wall_gap;
          x < f.bounds.x + f.bounds.w - w / 2 - F.wall_gap;
          x += F.grid
        ) {
          const r = {
            x: x - w / 2 - F.clearance,
            y: z - d / 2 - F.clearance,
            w: w + F.clearance * 2,
            h: d + F.clearance * 2,
          }
          if (
            dist([x, z], a) < F.door_gap ||
            used.some((v) => overlaps(r, v.r, 0)) ||
            used.some((v) => contains(r, v.anchor, 0.0001))
          )
            continue
          const anchor = [x, z + d / 2 + F.anchor_offset]
          if (used.some((v) => contains(v.r, anchor, 0.0001))) continue
          candidates.push({ x, z, r, anchor, score: dist([x, z], preferred) })
        }
      candidates.sort((a, b) => a.score - b.score || a.z - b.z || a.x - b.x)
      const best = candidates[0]
      if (!best)
        throw new GenerationError(
          'INSUFFICIENT_SPACE',
          `${f.id} 无法容纳 ${p.id} 的占地和操作位置`,
          {
            stage: 'spatial',
            place_refs: [scene.places.get(f.id)?.ref ?? f.id],
          }
        )
      p.position = point([best.x, best.z])
      p.anchor = point(best.anchor)
      used.push(best)
      const mark = marks.get(p.id),
        room = rooms.get(mark.space)
      mark.x = q(best.x * S - (room?.unfold.offset_x ?? 0))
      mark.y = q(best.z * S - (room?.unfold.offset_y ?? 0))
    }
  }
}

// 室外道路：二维折线按固定间距重采样后贴到地形上。
function outdoorRoutes(scene) {
  const { layout, point } = scene
  return layout.edges.map((e) => ({
    id: e.id,
    from: e.from_node,
    to: e.to_node,
    from_locale: e.from_locale,
    to_locale: e.to_locale,
    width: e.width / S,
    road_class: e.road_class,
    points: e.polyline.flatMap((b, i) => {
      if (!i) return [point(b.map((v) => v / S))]
      const a = e.polyline[i - 1],
        n = Math.ceil(dist(a, b) / S / FURNITURE.route_step)
      return Array.from({ length: n }, (_, j) =>
        point(a.map((v, k) => (v + ((b[k] - v) * (j + 1)) / n) / S))
      )
    }),
    indoor: false,
  }))
}

// 家具占地加上角色半径，与 Rust 校验使用的障碍框一致。
const furnitureObstacles = (members) =>
  members.map((p) => ({
    x: p.position[0] - p.footprint[0] / 2 - M.actor_radius,
    y: p.position[2] - p.footprint[1] / 2 - M.actor_radius,
    w: p.footprint[0] + M.actor_radius * 2,
    h: p.footprint[1] + M.actor_radius * 2,
  }))

// 公园与花园的环形步道。环线或入口段穿过家具时，这处空间不生成环线，
// 家具通道仍从到达点出发。
function publicSpaceRoutes(scene, floors, propsByFloor, routes, navNodes) {
  const loops = new Map()
  for (const floor of floors) {
    if (floor.indoor || !['park', 'garden'].includes(scene.regions.get(floor.id)?.kind)) continue
    const arrival = scene.world(scene.visualStations.get(`at_${floor.id}`)),
      loop = publicSpaceLoop(floor.bounds, arrival),
      obstacles = furnitureObstacles(propsByFloor.get(floor.id)),
      entryPoint = loop.points[loop.anchors[loop.entryIndex]],
      blocked = (a, b) => obstacles.some((r) => segmentRect(a, b, r))
    if (
      blocked(arrival, entryPoint) ||
      loop.points.some((point, i) => blocked(point, loop.points[(i + 1) % loop.points.length]))
    )
      continue
    const anchors = loop.anchors.map((index, number) => ({
      id:
        dist(loop.points[index], arrival) < 0.05
          ? `arrival_${floor.id}`
          : `node_${floor.id}_path_${number}`,
      position: scene.point(loop.points[index]),
    }))
    navNodes.push(...anchors.filter((node) => !node.id.startsWith('arrival_')))
    loops.set(floor.id, anchors)
    for (let i = 0; i < anchors.length; i++) {
      const start = loop.anchors[i],
        end = loop.anchors[(i + 1) % anchors.length],
        flat =
          start < end
            ? loop.points.slice(start, end + 1)
            : [...loop.points.slice(start), ...loop.points.slice(0, end + 1)]
      routes.push({
        id: `walk_${floor.id}_loop_${i}`,
        from: anchors[i].id,
        to: anchors[(i + 1) % anchors.length].id,
        from_locale: floor.id,
        to_locale: floor.id,
        width: 1.2,
        points: flat.map(scene.point),
        indoor: false,
        owner: floor.id,
      })
    }
    const entry = anchors[loop.entryIndex]
    if (entry.id !== `arrival_${floor.id}`)
      routes.push({
        id: `walk_${floor.id}_entry`,
        from: `arrival_${floor.id}`,
        to: entry.id,
        from_locale: floor.id,
        to_locale: floor.id,
        width: 1.2,
        points: [scene.point(arrival), entry.position],
        indoor: false,
        owner: floor.id,
      })
  }
  return loops
}

// 从到达点（或最近的环线节点）到每件家具操作位置的通道；同时把操作位置写回二维使用点。
function interiorRoutes(scene, floors, propsByFloor, routes, navNodes, timer, publicLoops) {
  const { rooms, point, world, visualStations, stations } = scene
  for (const f of floors) {
    timer.check('interiors')
    const arrival = world(visualStations.get(`at_${f.id}`)),
      members = propsByFloor.get(f.id),
      loop = publicLoops.get(f.id)
    const obstacles = furnitureObstacles(members)
    // 整个活动空间的包围盒都可通行，包括二维图案上没有着色的空隙；边界之外没有通道。
    const valid = (p) => contains(f.bounds, p, 0.0001)
    for (const p of members) {
      const b = [p.anchor[0], p.anchor[2]]
      const candidates = loop
        ?.slice()
        .sort(
          (left, right) =>
            dist([left.position[0], left.position[2]], b) -
            dist([right.position[0], right.position[2]], b)
        ) ?? [null]
      let nearest = null,
        path = null
      for (const candidate of candidates) {
        const a = candidate ? [candidate.position[0], candidate.position[2]] : arrival
        path = route(a, b, obstacles, valid)
        if (path) {
          nearest = candidate
          break
        }
      }
      if (!path)
        throw new GenerationError('ROUTE_UNRESOLVED', `${p.id} 的操作位置没有避开家具的通道`, {
          stage: 'spatial',
          place_refs: [scene.places.get(f.id)?.ref ?? f.id],
          from: a,
          to: b,
          bounds: f.bounds,
        })
      const node = `node_${p.id}`
      routes.push({
        id: `walk_${p.id}`,
        from: nearest?.id ?? `arrival_${f.id}`,
        to: node,
        from_locale: f.id,
        to_locale: f.id,
        width: 0.7,
        points: path.map(point),
        indoor: f.indoor,
        owner: f.id,
      })
      navNodes.push({ id: node, position: p.anchor })
      stations.get(`use_${p.id}`).node = node
      const st = visualStations.get(`use_${p.id}`),
        r = rooms.get(st.space)
      st.x = q(b[0] * S - (r?.unfold.offset_x ?? 0))
      st.y = q(b[1] * S - (r?.unfold.offset_y ?? 0))
    }
  }
}

// 户外活动区域里几个有名字的落脚点：靠海的叫「水边」，其余按在区域里的方向叫「东头」「北边」「西南角」。
// 从离到达点远的格点里挑，彼此隔开、避开家具，每个从到达点有一条走过去的通道；村民停留时可以指定站到哪儿。
const SPOT_LIMIT = 3
const SPOT_GAP = 3
const SPOT_CLEAR = 1.2
const SPOT_SHORE = 10
const SPOT_DIRECTIONS = ['东头', '东北角', '北边', '西北角', '西头', '西南角', '南边', '东南角']
function spotName(terrain, p, center, used) {
  const landAt = ([x, z]) => {
    const ix = Math.round((x - terrain.origin[0]) / terrain.step),
      iz = Math.round((z - terrain.origin[1]) / terrain.step)
    if (ix < 0 || iz < 0 || ix >= terrain.columns || iz >= terrain.rows) return 0
    return terrain.land[iz * terrain.columns + ix]
  }
  const nearSea = [0, 1, 2, 3, 4, 5, 6, 7].some((k) => {
    const a = (k * Math.PI) / 4
    return [0.25, 0.5, 0.75, 1].some(
      (f) => !landAt([p[0] + Math.cos(a) * SPOT_SHORE * f, p[1] + Math.sin(a) * SPOT_SHORE * f])
    )
  })
  if (nearSea && !used.has('水边')) return '水边'
  // 地图上北是 z 减小的方向
  const angle = (Math.atan2(center[1] - p[1], p[0] - center[0]) * 180) / Math.PI
  const name = SPOT_DIRECTIONS[Math.round((((angle % 360) + 360) % 360) / 45) % 8]
  return used.has(name) ? null : name
}
function spots(scene, floors, propsByFloor, routes, navNodes) {
  for (const f of floors) {
    if (f.indoor || scene.regions.get(f.id)?.kind !== 'area') continue
    const arrival = scene.world(scene.visualStations.get(`at_${f.id}`)),
      obstacles = furnitureObstacles(propsByFloor.get(f.id)),
      valid = (p) => contains(f.bounds, p, 0.0001),
      { x, y, w, h } = f.bounds,
      center = [x + w / 2, y + h / 2],
      clear = (p) =>
        !obstacles.some(
          (r) =>
            p[0] > r.x - SPOT_CLEAR &&
            p[0] < r.x + r.w + SPOT_CLEAR &&
            p[1] > r.y - SPOT_CLEAR &&
            p[1] < r.y + r.h + SPOT_CLEAR
        )
    const candidates = []
    for (let i = 1; i <= 5; i++)
      for (let j = 1; j <= 5; j++) {
        const p = [q(x + (w * i) / 6), q(y + (h * j) / 6)]
        if (clear(p)) candidates.push(p)
      }
    candidates.sort((a, b) => dist(b, arrival) - dist(a, arrival) || a[0] - b[0] || a[1] - b[1])
    const chosen = [],
      used = new Set()
    for (const p of candidates) {
      if (chosen.length >= SPOT_LIMIT) break
      if (dist(p, arrival) < SPOT_GAP || chosen.some((c) => dist(c.p, p) < SPOT_GAP)) continue
      const name = spotName(scene.terrain, p, center, used)
      const path = name && route(arrival, p, obstacles, valid)
      if (!path) continue
      used.add(name)
      chosen.push({ p, name, path })
    }
    chosen.forEach(({ p, name, path }, k) => {
      const id = `spot_${f.id}_${k + 1}`,
        node = `node_${id}`
      routes.push({
        id: `walk_${id}`,
        from: `arrival_${f.id}`,
        to: node,
        from_locale: f.id,
        to_locale: f.id,
        width: 0.7,
        points: path.map(scene.point),
        indoor: false,
        owner: f.id,
      })
      navNodes.push({ id: node, position: scene.point(p) })
      const station = { id, locale: f.id, name, kind: 'slot', node },
        mark = { id, space: 'town_outdoor', x: q(p[0] * S), y: q(p[1] * S) }
      scene.topology.stations.push(station)
      scene.layout.stations.push(mark)
      scene.stations.set(id, station)
      scene.visualStations.set(id, mark)
    })
  }
}

// 路线长度和分钟数以三维折线为准；室外道路更新拓扑与二维折线，室内通道新增处所、通道、边和节点。
function writeBackTopology(scene, routes, navNodes) {
  const { layout, topology, locales, edges } = scene
  const nodesById = new Map(navNodes.map((n) => [n.id, n])),
    writtenNodes = new Set(layout.nodes.map((node) => node.id))
  const flat = (points) => points.map((p) => [q(p[0] * S), q(p[2] * S)])
  for (const r of routes) {
    r.length = q(length3(r.points))
    r.minutes = q(r.length / M.metres_per_minute)
    const l = locales.get(r.id)
    if (l) {
      l.minutes = r.minutes
      edges.get(r.id).polyline = flat(r.points)
      continue
    }
    topology.locales.push({
      id: r.id,
      name: '前往道具的通道',
      kind: 'transit',
      minutes: r.minutes,
      from_node: r.from,
      to_node: r.to,
    })
    for (const [node, locale, side] of [
      [r.from, r.from_locale, 'a'],
      [r.to, r.to_locale, 'b'],
    ])
      topology.passages.push({
        id: r.id + '_' + side,
        a: r.id,
        b: locale,
        node_a: node,
        node_b: node,
        minutes: 0,
        capabilities: ['通行', '视', '听'],
      })
    layout.edges.push({
      id: r.id,
      from_node: r.from,
      to_node: r.to,
      from_locale: r.from_locale,
      to_locale: r.to_locale,
      polyline: flat(r.points),
      width: r.width * S,
      road_class: 'interior',
      owner: r.owner,
    })
    const n = nodesById.get(r.to)
    if (!writtenNodes.has(n.id)) {
      layout.nodes.push({
        id: n.id,
        x: q(n.position[0] * S),
        y: q(n.position[2] * S),
        kind: 'operation',
        space: 'town_outdoor',
      })
      writtenNodes.add(n.id)
    }
  }
}

function vegetation(scene, floors, routes, timer) {
  const { layout, plan, seed, terrain } = scene,
    V = VEGETATION
  const result = [],
    vr = stream(seed, 'vegetation-cluster'),
    density = V.density[plan.spec.environment.vegetation]
  const target = Math.min(
    V.max_instances,
    Math.ceil(((layout.canvas.width * layout.canvas.height) / S / S / V.area_per_plant) * density)
  )
  const clusters = Array.from({ length: Math.max(4, Math.ceil(target / V.per_cluster)) }, () => [
    vr() * terrain.step * (terrain.columns - 1) + terrain.origin[0],
    vr() * terrain.step * (terrain.rows - 1) + terrain.origin[1],
  ])
  const keepOut = floors.map((f) => ({
    x: f.bounds.x - V.floor_margin,
    y: f.bounds.y - V.floor_margin,
    w: f.bounds.w + V.floor_margin * 2,
    h: f.bounds.h + V.floor_margin * 2,
  }))
  const nearRoad = (x, z) =>
    routes.some((r) =>
      r.points
        .slice(1)
        .some(
          (b, j) =>
            project([x, z], [r.points[j][0], r.points[j][2]], [b[0], b[2]]).distance <
            r.width / 2 + V.road_margin
        )
    )
  for (let i = 0; i < target * 12 && result.length < target; i++) {
    if (!(i % 128)) timer.check('vegetation')
    const rng = stream(seed, 'vegetation-instance', String(i)),
      c = clusters[i % clusters.length],
      x = c[0] + (rng() - 0.5) * V.cluster_radius,
      z = c[1] + (rng() - 0.5) * V.cluster_radius,
      y = heightAt(terrain, x, z)
    if (y < V.min_height || keepOut.some((r) => contains(r, [x, z], 0.0001))) continue
    if (nearRoad(x, z)) continue
    if (result.some((p) => dist([p.position[0], p.position[2]], [x, z]) < V.spacing)) continue
    result.push({
      id: `plant_${i}`,
      model: rng() < V.rock_ratio ? 'rock' : 'tree',
      position: [q(x), q(y), q(z)],
      yaw: q(rng() * Math.PI * 2),
      height: q(2.9 + rng() * 3.7),
      collider_radius: 0.4,
    })
  }
  return result
}

export function addSpatial(document, plan, timer) {
  const { layout, topology } = document,
    seed = plan.spec.seed,
    terrain = ground(document, seed, plan.budget.caps.lab),
    rooms = new Map(layout.spaces.map((r) => [r.id, r]))
  // 二维标记（可能带房间偏移）换算成米制平面坐标；point 再补上地形高度。
  const world = (m) => {
    const r = rooms.get(m.space)
    return [(m.x + (r?.unfold.offset_x ?? 0)) / S, (m.y + (r?.unfold.offset_y ?? 0)) / S]
  }
  const point = ([x, z]) => [q(x), q(heightAt(terrain, x, z)), q(z)]
  const scene = {
    layout,
    topology,
    plan,
    seed,
    terrain,
    world,
    point,
    rooms,
    places: new Map(plan.places.map((p) => [p.id, p])),
    regions: new Map(layout.regions.map((r) => [r.id, r])),
    marks: new Map(layout.props.map((m) => [m.id, m])),
    propDefs: new Map(topology.props.map((p) => [p.id, p])),
    visualStations: new Map(layout.stations.map((s) => [s.id, s])),
    stations: new Map(topology.stations.map((s) => [s.id, s])),
    locales: new Map(topology.locales.map((l) => [l.id, l])),
    edges: new Map(layout.edges.map((e) => [e.id, e])),
  }
  const built = buildings(scene),
    spaces = floors(scene),
    furniture = props(scene),
    propsByFloor = new Map(spaces.map((f) => [f.id, furniture.filter((p) => p.locale === f.id)]))
  placeFurniture(scene, spaces, propsByFloor)
  const routes = outdoorRoutes(scene),
    navNodes = layout.nodes.map((n) => ({ id: n.id, position: point(world(n)) }))
  const publicLoops = publicSpaceRoutes(scene, spaces, propsByFloor, routes, navNodes)
  interiorRoutes(scene, spaces, propsByFloor, routes, navNodes, timer, publicLoops)
  spots(scene, spaces, propsByFloor, routes, navNodes)
  writeBackTopology(scene, routes, navNodes)
  const stations = layout.stations.map((s) => ({
    id: s.id,
    locale: scene.stations.get(s.id).locale,
    position: point(world(s)),
  }))
  const plants = vegetation(scene, spaces, routes, timer)
  document.schema_version = 2
  document.generation.assets_hash = hashDocument(manifest)
  document.generation.assets_version = manifest.version
  document.generation.generator_version = GENERATOR_VERSION
  document.spatial = {
    version: 1,
    units: 'metres',
    svg_units_per_metre: S,
    navigation_revision: 1,
    terrain,
    buildings: built,
    landmarks: buildings(scene, true),
    floors: spaces,
    props: furniture,
    stations,
    nodes: navNodes,
    routes,
    vegetation: plants,
    center: [layout.canvas.width / S / 2, layout.canvas.height / S / 2],
  }
  document.assets = {
    id: manifest.id,
    version: manifest.version,
    manifest_hash: hashDocument(manifest),
    files: manifest.files,
  }
  document.views = {
    available: ['2d'],
    default: '2d',
    appearance_set: manifest.id,
  }
  document.topology.precise_navigation = true
  if (plan.budget.caps.lab)
    document.generation.experimental_recipe = { version: 1, ...plan.budget.caps.lab }
  document.id = `generated-${hashDocument({ spec: plan.spec, assets: document.assets, generator_version: GENERATOR_VERSION, ...(plan.budget.caps.lab ? { lab: document.generation.experimental_recipe } : {}) }).slice(0, 16)}`
  return seal(document)
}
