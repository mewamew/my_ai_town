import { propGlyph } from 'town-shared/props/glyph'
import type { Atlas } from 'town-shared/mapDocument'
import type { At } from 'town-shared/protocol'
import { el } from 'town-shared/svg'
import { EdgeCurve } from './curve'
import { LEGACY_UNITS_PER_METRE, MARGIN, OUTDOOR_SPACE, PIXEL, roomPoint } from './grid'
import { placePropLabel, regionLabelAnchor, type Box } from './labels'
import { unlabeledRegions } from './styles/svgTown'
import { paintGround, type Ground } from './pixel/terrain'
import { addPropArtwork, bookCover, PROP_ART_MIN, PROP_ART_SIZE } from './propArt'
import { village, type MapTheme } from './themes'
import './pixel/pixel.css'

/** 画在图上的一件道具：地图坐标；有像素图时带着图和边长，立体场景把它立起来 */
export interface PlacedProp {
  id: string
  at: [number, number]
  art?: { url: string; size: number }
  /** 合成一摞的书有几本（见 bookPile） */
  count?: number
}

/** 地图外面的底色：外圈最远处的颜色，深海、盐碱地或冰面 */
function backdrop(theme: MapTheme) {
  return el('rect', {
    x: -1e5,
    y: -1e5,
    width: 2e5,
    height: 2e5,
    fill: theme.ground.outer[theme.ground.outer.length - 1],
    class: 'pixel-terrain',
  })
}

/** 平面像素地面：一张图垫在 SVG 最底层 */
function terrainImage(canvas: HTMLCanvasElement) {
  return el('image', {
    href: canvas.toDataURL(),
    x: -MARGIN,
    y: -MARGIN,
    width: canvas.width * PIXEL,
    height: canvas.height * PIXEL,
    class: 'pixel-terrain',
    'pointer-events': 'none',
  })
}

/** 房间坐标和地图坐标互换；室外和不认识的空间原样返回 */
function roomTransforms(atlas: Atlas) {
  const unfold = new Map(atlas.spaces.map((s) => [s.id, s.unfold]))
  const toWorld = (space: string, x: number, y: number): [number, number] => {
    const u = space === OUTDOOR_SPACE ? undefined : unfold.get(space)
    return u ? roomPoint(u, x, y) : [x, y]
  }
  /** toWorld 的逆变换：画面坐标回到房间自己的坐标 */
  const toLocal = (space: string, p: [number, number]): [number, number] => {
    const u = space === OUTDOOR_SPACE ? undefined : unfold.get(space)
    return u ? [(p[0] - u.offset_x) / u.scale, (p[1] - u.offset_y) / u.scale] : [p[0], p[1]]
  }
  return { toWorld, toLocal }
}

/** 人物在平面图上的位置：自由站位按旧地图的比例换算，落脚点取站位，路上按走过的比例插值 */
function positionOn(
  stationPos: Anchors,
  localeAnchor: Anchors,
  edgeCurves: Map<string, EdgeCurve>,
  toWorld: ToWorld
) {
  return (locale: string, at: At): [number, number] | undefined => {
    if (at.kind === 'offstage') return undefined
    if (at.kind === 'free')
      return toWorld(
        at.space,
        at.position[0] * LEGACY_UNITS_PER_METRE,
        at.position[1] * LEGACY_UNITS_PER_METRE
      )
    if (at.kind === 'station') return stationPos.get(at.station) ?? localeAnchor.get(locale)
    const curve = edgeCurves.get(locale)
    return curve ? curve.at(at.elapsed / (at.total || 1)) : localeAnchor.get(locale)
  }
}

export function buildStaticMap(
  atlas: Atlas,
  artworkFor: (id: string) => string | undefined = () => undefined,
  theme: MapTheme = village
) {
  const surfaces = new Map<string, SVGElement>()
  const props = new Map<string, SVGElement>()
  const propLabels = new Map<string, SVGTextElement>()
  const localeAnchor = new Map<string, [number, number]>()
  // 「空间:enter」= 室外门口，「空间:exit」= 摊开房间里的门，与化身出入口编号一致
  const doorAnchor = new Map<string, [number, number]>()
  const stationPos = new Map<string, [number, number]>()
  const edgeCurves = new Map<string, EdgeCurve>()
  const W = atlas.canvas.width,
    H = atlas.canvas.height
  const { toWorld, toLocal } = roomTransforms(atlas)

  const svg = el('svg', { viewBox: `-200 -200 ${W + 400} ${H + 400}` })
  if (atlas.spaces.length + atlas.regions.filter((r) => r.kind !== 'road').length === 1)
    svg.classList.add('single-place')
  // 地面由立体场景画；SVG 只留底色、点击、感知和文字，立体场景起不来时才垫一张平面像素图
  const outer = backdrop(theme)
  svg.appendChild(outer)

  svg.appendChild(drawRegions(atlas, localeAnchor, surfaces))
  svg.appendChild(drawEdges(atlas, localeAnchor, edgeCurves, surfaces))
  const obstacles: Box[] = []
  const rooms = drawRooms(atlas, toWorld, localeAnchor, doorAnchor, obstacles, surfaces)
  svg.appendChild(rooms.group)
  const roomObstacles = [...obstacles]
  const drawn = drawProps(atlas.props, atlas.stations, toWorld, obstacles, artworkFor, new Map())
  const details = drawn.group
  const setProps = (d: ReturnType<typeof drawProps>) => {
    props.clear()
    propLabels.clear()
    for (const [id, shape] of d.shapes) props.set(id, shape)
    for (const [id, label] of d.labels) propLabels.set(id, label)
    return d.placed
  }
  const initialProps = setProps(drawn)
  svg.appendChild(details)
  for (const st of atlas.stations) stationPos.set(st.id, toWorld(st.space, st.x, st.y))

  return {
    svg,
    surfaces,
    localeAnchor,
    doorAnchor,
    toWorld,
    toLocal,
    /** 立体场景起不来时，把平面像素地面垫在最底层 */
    showTerrain(canvas: HTMLCanvasElement) {
      outer.after(terrainImage(canvas))
    },
    /** 画面上的点落在哪个摊开的房间里；都不在就是室外 */
    spaceAt(p: [number, number]): string {
      const hit = rooms.bounds.find(
        (r) => p[0] >= r.x && p[0] <= r.x + r.width && p[1] >= r.y && p[1] <= r.y + r.height
      )
      return hit?.id ?? OUTDOOR_SPACE
    },
    /** 道具编号 → 图形、名字标签 */
    props,
    propLabels,
    details,
    /** 打开时地图文件里的道具 */
    initialProps,
    /** 按新的道具位置重画道具和名字；图集本身不改。books：在地图上的书，编号 → 地点 */
    replaceProps(next: Atlas['props'], books: ReadonlyMap<string, string>) {
      const d = drawProps(next, atlas.stations, toWorld, [...roomObstacles], artworkFor, books)
      details.replaceChildren(...Array.from(d.group.childNodes))
      return setProps(d)
    },
    initialView: [-200, -200, W + 400, H + 400],
    position: positionOn(stationPos, localeAnchor, edgeCurves, toWorld),
  }
}

type Anchors = Map<string, [number, number]>
type ToWorld = (space: string, x: number, y: number) => [number, number]

function drawRegions(atlas: Atlas, localeAnchor: Anchors, surfaces: Map<string, SVGElement>) {
  // 1. 室外区域色块（按行程合并成单 path）
  const gRegions = el('g')
  for (const r of atlas.regions) {
    const cs = r.cell_size
    const rows = new Map<number, number[]>()
    for (const [c, row] of r.cells) {
      const cols = rows.get(row) ?? []
      cols.push(c)
      rows.set(row, cols)
    }
    const d: string[] = []
    for (const [row, cols] of [...rows.entries()].sort((a, b) => a[0] - b[0])) {
      cols.sort((a, b) => a - b)
      for (let i = 0; i < cols.length;) {
        let j = i
        while (j + 1 < cols.length && cols[j + 1] === cols[j] + 1) j++
        const x = cols[i] * cs,
          y = row * cs,
          w = (j - i + 1) * cs
        d.push(`M${x} ${y}h${w}v${cs}h-${w}z`)
        i = j + 1
      }
    }
    const shape = el('path', { fill: 'none', d: d.join('') })
    gRegions.appendChild(shape)
    surfaces.set(r.id, shape)
    const label = r.label_anchor ?? regionLabelAnchor(r.cells, cs)
    localeAnchor.set(r.id, label)
    // 没有名字的区域（林子、河堤、公园里的旋转木马）只管样子，不标名字
    if (!unlabeledRegions.has(r.kind) && r.name) {
      const title =
        atlas.spaces.length === 0 && atlas.regions.length === 1
          ? [atlas.canvas.width / 2, Math.min(...r.cells.map((c) => c[1])) * cs - 60]
          : label
      gRegions.appendChild(el('text', { class: 'rg', x: title[0], y: title[1] }, r.name))
    }
  }

  return gRegions
}

function drawEdges(
  atlas: Atlas,
  localeAnchor: Anchors,
  edgeCurves: Map<string, EdgeCurve>,
  surfaces: Map<string, SVGElement>
) {
  // 2. 路段：画面由像素图负责，这里只留折线给感知高亮和人物插值
  const gEdges = el('g', { fill: 'none', stroke: 'none' })
  for (const e of atlas.edges) {
    const shape = el('polyline', {
      points: e.polyline.map((p) => p.join(',')).join(' '),
    })
    gEdges.appendChild(shape)
    surfaces.set(e.id, shape)
    const curve = new EdgeCurve(e.polyline)
    edgeCurves.set(e.id, curve)
    localeAnchor.set(e.id, curve.at(0.5))
  }
  return gEdges
}

function drawRooms(
  atlas: Atlas,
  toWorld: ToWorld,
  localeAnchor: Anchors,
  doorAnchor: Anchors,
  obstacles: Box[],
  surfaces: Map<string, SVGElement>
) {
  // 3. 室内房间（摊开）的名字与门口坐标
  const gRooms = el('g')
  const bounds: { id: string; x: number; y: number; width: number; height: number }[] = []
  for (const s of atlas.spaces) {
    const [x0, y0] = toWorld(s.id, s.bounds.x, s.bounds.y)
    const w = s.unfold.scale * s.bounds.width,
      h = s.unfold.scale * s.bounds.height
    // 房间画面在像素图里；这里的矩形只供感知高亮复制
    const shape = el('rect', { x: x0, y: y0, width: w, height: h, fill: 'none' })
    gRooms.appendChild(shape)
    bounds.push({ id: s.id, x: x0, y: y0, width: w, height: h })
    surfaces.set(s.id, shape)
    gRooms.appendChild(
      el('text', { class: 'rm', x: x0 + w / 2, y: y0 - 18, 'data-room': s.id }, s.name)
    )
    const nw = s.name.length * 62
    obstacles.push({
      x0: x0 + w / 2 - nw / 2,
      y0: y0 - 76,
      x1: x0 + w / 2 + nw / 2,
      y1: y0 - 2,
    })
    if (s.door_outside) doorAnchor.set(`${s.id}:enter`, s.door_outside)
    if (s.door_inside_local)
      doorAnchor.set(`${s.id}:exit`, toWorld(s.id, s.door_inside_local[0], s.door_inside_local[1]))
    localeAnchor.set(s.id, [x0 + w / 2, y0 + h / 2])
  }

  return { group: gRooms, bounds }
}

/** 同一个地点里的书，相距这么近以内就连成一摞（地图单位）；一摞里最多叠几本、每本封面多大 */
const PILE_LINK = 140
const PILE_SHOWN = 3
const PILE_COVER = 48

/** 把同一个地点里一本挨一本的书分成一摞摞，只有一本的不算；位置取这几本的中间 */
function bookPiles(
  marks: Atlas['props'],
  at: [number, number][],
  books: ReadonlyMap<string, string>
) {
  const byLocale = new Map<string, number[]>()
  marks.forEach((p, i) => {
    const locale = books.get(p.id)
    if (locale !== undefined) byLocale.set(locale, [...(byLocale.get(locale) ?? []), i])
  })
  const piles: { members: number[]; at: [number, number] }[] = []
  for (const left of byLocale.values()) {
    while (left.length) {
      const members = [left.shift()!]
      for (let k = 0; k < members.length; k++)
        for (let j = left.length - 1; j >= 0; j--) {
          const [a, b] = [at[members[k]], at[left[j]]]
          if (Math.hypot(a[0] - b[0], a[1] - b[1]) <= PILE_LINK) members.push(...left.splice(j, 1))
        }
      if (members.length < 2) continue
      const mid = (axis: 0 | 1) => members.reduce((s, i) => s + at[i][axis], 0) / members.length
      piles.push({ members, at: [mid(0), mid(1)] })
    }
  }
  return piles
}

/** 一摞书：最多三本封面错开叠着，右上角写本数。编号用第一本的，点开由外壳换成「书与公告」里这个地点的书 */
function bookPile(ids: string[], at: [number, number], cover: (id: string) => string) {
  const g = el('g', {
    class: 'pp book-pile',
    'data-prop-id': ids[0],
    transform: `translate(${at[0]} ${at[1]})`,
    role: 'button',
    tabindex: 0,
    'aria-label': `查看这里的 ${ids.length} 本书`,
  })
  g.appendChild(
    el('rect', { class: 'book-pile-target', x: -34, y: -42, width: 76, height: 80, rx: 6 })
  )
  const offsets: [number, number][] = [
    [-5, 10],
    [6, -2],
    [-2, -14],
  ]
  ids.slice(0, PILE_SHOWN).forEach((id, k) => {
    const [dx, dy] = offsets[k]
    const size = PILE_COVER
    g.appendChild(
      el('image', {
        class: 'book-pile-cover',
        href: cover(id),
        x: dx - size / 2,
        y: dy - size / 2,
        width: size,
        height: size,
      })
    )
  })
  const count = el('g', { class: 'book-pile-count' })
  count.append(
    el('circle', { cx: 30, cy: -34, r: 15 }),
    el('text', { x: 30, y: -28 }, `${ids.length}`)
  )
  g.appendChild(count)
  return g
}

function drawProps(
  marks: Atlas['props'],
  stations: Atlas['stations'],
  toWorld: ToWorld,
  obstacles: Box[],
  artworkFor: (id: string) => string | undefined,
  books: ReadonlyMap<string, string>
) {
  // 4. 道具 + 落脚点。标签碰撞回避：候选槽位（近处优先，下上交替）里
  // 挑第一个不压别人的；全占了就退到最远的下方槽。位置静态，构建时排一次。
  const gProps = el('g')
  const shapes = new Map<string, SVGElement>()
  const labels = new Map<string, SVGTextElement>()
  const placed: PlacedProp[] = []
  const propPos = marks.map((p) => toWorld(p.space, p.x, p.y))
  // 挨着的书合成一摞画：一排一样的书既占地方又看不清
  const piles = bookPiles(marks, propPos, books)
  const piled = new Set(piles.flatMap((pile) => pile.members))
  const cover = (id: string) => artworkFor(id) ?? bookCover(id)
  // 屋里的坐标按 unfold 缩小过，家具之间比道具图还近：按离最近的另一件的距离缩小，免得叠在一起；
  // 合成一摞的书按那一摞的位置算
  const spots = [
    ...marks.flatMap((p, i) => (piled.has(i) ? [] : [{ i, space: p.space, at: propPos[i] }])),
    ...piles.map((pile) => ({ i: -1, space: marks[pile.members[0]].space, at: pile.at })),
  ]
  const artSize = marks.map((p, i) => {
    let near = Infinity
    for (const s of spots)
      if (s.i !== i && s.space === p.space)
        near = Math.min(near, Math.hypot(s.at[0] - propPos[i][0], s.at[1] - propPos[i][1]))
    return Math.max(PROP_ART_MIN, Math.min(PROP_ART_SIZE, near * 0.92))
  })
  marks.forEach((p, i) => {
    if (piled.has(i)) return
    const [x, y] = propPos[i]
    const shape = propGlyph(p.id, x, y, p.appearance)
    // 用户明确设置的图片优先；尚无内置素材的自定义道具继续使用原外观；单独一本书挑一张书本封面
    const artwork = p.appearance?.image
      ? undefined
      : books.has(p.id)
        ? cover(p.id)
        : artworkFor(p.id)
    if (artwork) addPropArtwork(shape, artwork, artSize[i])
    shape.setAttribute('aria-label', unnamed(p) ? '查看道具' : `查看${p.name}`)
    gProps.appendChild(shape)
    shapes.set(p.id, shape)
    placed.push({
      id: p.id,
      at: [x, y],
      art: artwork ? { url: artwork, size: artSize[i] } : undefined,
    })
    const radius = artwork ? artSize[i] / 2 : 24
    obstacles.push({ x0: x - radius, y0: y - radius, x1: x + radius, y1: y + radius })
  })
  for (const pile of piles) {
    const ids = pile.members.map((i) => marks[i].id)
    const shape = bookPile(ids, pile.at, cover)
    gProps.appendChild(shape)
    for (const id of ids) shapes.set(id, shape)
    placed.push({ id: ids[0], at: pile.at, count: ids.length })
    const [x, y] = pile.at
    obstacles.push({ x0: x - 34, y0: y - 50, x1: x + 46, y1: y + 38 })
  }
  for (const st of stations) {
    const [x, y] = toWorld(st.space, st.x, st.y)
    obstacles.push({ x0: x - 22, y0: y - 22, x1: x + 22, y1: y + 22 })
  }
  marks.forEach((p, i) => {
    if (piled.has(i) || unnamed(p)) return
    const [x, y] = propPos[i]
    const label = p.name.replace(p.place_name, '') || p.name
    const best = placePropLabel(x, y, label, obstacles)
    const text = el('text', { class: 'pl', x: best[0], y: best[1], 'data-prop-label': p.id }, label)
    gProps.appendChild(text)
    labels.set(p.id, text)
  })
  // 一摞书只标一个名字：几本书。名字只在指到或选中时出现，直接挂在这摞书上方，不避让到别处
  for (const pile of piles) {
    const ids = pile.members.map((i) => marks[i].id)
    const [x, y] = pile.at
    const text = el(
      'text',
      { class: 'pl', x, y: y - 60, 'data-prop-label': ids[0] },
      `${ids.length} 本书`
    )
    gProps.appendChild(text)
    for (const id of ids) labels.set(id, text)
  }
  return { group: gProps, shapes, labels, placed }
}

/** 地图包里个别道具没写名字，名字就是编号（medical_supply、initial:book-5）：先不标，服务器的道具名到了再标 */
const unnamed = (p: { id: string; name: string }) => p.name === p.id
