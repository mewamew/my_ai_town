import type { At } from './protocol'
import type { PropCatalog } from './props/types'
type Vec3 = [number, number, number]
export interface SpatialProp {
  id: string
  locale: string
  model: string
  position: Vec3
  anchor: Vec3
  yaw: number
  footprint: [number, number]
}
export interface Building {
  id: string
  kind: string
  size: string
  position: Vec3
  yaw: number
  width: number
  depth: number
  height: number
  archetype: string
  wall_variant: number
  roof_variant: number
  door: Vec3
  closed: boolean
}
export interface Route {
  id: string
  from: string
  to: string
  width: number
  road_class?: 'main' | 'street' | 'access' | 'path' | 'interior'
  points: Vec3[]
  length: number
  minutes: number
  indoor: boolean
  owner?: string
}
export interface Terrain {
  origin: [number, number]
  step: number
  columns: number
  rows: number
  heights: number[]
  land: number[]
  sea_level: number
}
export interface Spatial {
  version: number
  units: string
  svg_units_per_metre: number
  /** 各地点能放东西的范围（米；y 是地面上的 z）。后端放置器在这块里找空位 */
  floors?: { id: string; indoor: boolean; bounds: { x: number; y: number; w: number; h: number } }[]
  navigation_revision: number
  terrain: Terrain
  buildings: Building[]
  props: SpatialProp[]
  stations: { id: string; locale: string; position: Vec3 }[]
  nodes: { id: string; position: Vec3 }[]
  routes: Route[]
  vegetation: {
    id: string
    model: string
    position: Vec3
    yaw: number
    height: number
    collider_radius: number
  }[]
  center: [number, number]
}

/** Roads rendered as the shared town street surface, excluding door spurs and place-owned paths. */
export function publicRoadRoutes(spatial: Pick<Spatial, 'routes'>) {
  return spatial.routes.filter(
    (route) => !route.indoor && !route.owner && route.road_class !== 'access'
  )
}
export interface AssetManifest {
  id: string
  files: Record<string, { bytes: number; sha256: string }>
  props: Record<string, { model: string; footprint: [number, number]; anchor: Vec3 }>
}
export function along(points: Vec3[], fraction: number): Vec3 {
  const ds = points.slice(1).map((p, i) => Math.hypot(...p.map((v, k) => v - points[i][k])))
  let left = ds.reduce((s, n) => s + n, 0) * Math.max(0, Math.min(1, fraction))
  for (let i = 0; i < ds.length; i++) {
    if (left <= ds[i]) {
      const f = left / (ds[i] || 1)
      const [a, b] = [points[i], points[i + 1]]
      return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f]
    }
    left -= ds[i]
  }
  return points[points.length - 1]
}
export function position(
  s: Spatial,
  locale: string,
  at: At,
  runtime?: PropCatalog['spatial']
): Vec3 | undefined {
  if (at.kind === 'free')
    return [at.position[0], at.elevation ?? heightAt(s.terrain, ...at.position), at.position[1]]
  if (at.kind === 'offstage') return
  // 操作点使用地图协议的 use_ 前缀。耗尽或拿走的道具仍保留历史站位和通路，
  // 人可能还停在这里，不能随道具可见性一起过滤。
  if (at.kind === 'station')
    return (
      runtime?.overrides.find(({ prop }) => `use_${prop.id}` === at.station)?.prop.anchor ??
      s.stations.find((st) => st.id === at.station)?.position
    )
  const route =
    runtime?.overrides.find(({ route }) => route.id === locale)?.route ??
    s.routes.find((r) => r.id === locale)
  return route ? along(route.points, at.elapsed / (at.total || 1)) : undefined
}
export function heightAt(t: Terrain, x: number, z: number) {
  const u = (x - t.origin[0]) / t.step,
    v = (z - t.origin[1]) / t.step,
    ix = Math.max(0, Math.min(t.columns - 2, Math.floor(u))),
    iz = Math.max(0, Math.min(t.rows - 2, Math.floor(v))),
    a = Math.max(0, Math.min(1, u - ix)),
    b = Math.max(0, Math.min(1, v - iz))
  return (
    (t.heights[iz * t.columns + ix] * (1 - a) + t.heights[iz * t.columns + ix + 1] * a) * (1 - b) +
    (t.heights[(iz + 1) * t.columns + ix] * (1 - a) +
      t.heights[(iz + 1) * t.columns + ix + 1] * a) *
      b
  )
}
