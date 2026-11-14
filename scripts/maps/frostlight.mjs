// 霜灯镇：专为六人供热生存玩法设计的环形雪地地图。三条同心环路由六条放射路连接，
// 宿舍在第一、二环之间；工作院落留在室外，动作组能沿同一行走空间往返并交付。
// 内景只借当前发布地图的家具定义，地形、道路、地点和房屋排布在这里独立设计。
// node scripts/maps/frostlight.mjs [--out <file>]；生成后用 town-map validate 校验。
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { seal } from '../mapgen/document.mjs'
import { arc, band, blob, circle, minus, room, own, townMap, union } from './townmap.mjs'

const source = JSON.parse(
  fs.readFileSync(new URL('../../data/maps/2d-town/map.json', import.meta.url), 'utf8')
)
const C = 2100
const polar = (r, degrees) => {
  const a = (degrees * Math.PI) / 180
  return [Math.round(C + r * Math.cos(a)), Math.round(C + r * Math.sin(a))]
}
const town = townMap({
  id: 'frostlight',
  name: '霜灯镇',
  description:
    '冰原中的环形避难镇。中央霜灯炉把暖光投向六间宿舍，三道环路和六条放射路连接煤场、粮站、工坊与诊疗院。暴风雪将至，六个人需要把物资运回炉前，让黎明还能有人点灯。',
  width: C * 2,
  height: C * 2,
  source,
  roads: 'frostlight_roads',
  script: 'scripts/maps/frostlight.mjs',
  environment: { preset: 'frozen', vegetation: 'sparse' },
  worldview:
    '霜灯镇是一座环形雪镇，中央热源连接六间宿舍与外圈工作院落。每次出门劳动，都要把取得的物资实际带回。',
  entry: { locale: 'gen:town-square', station: 'frostlight_arrival_generator' },
})
town.island(blob(C, C, 1960, 1960, 71, 0.045), union(), {
  coast: 1,
  bay: 4,
  warp: 9,
  erosion: 12,
  rim: 4,
})

// 地标中心留空交给玩法的立体热源；到达点在炉南侧，行人不穿炉心。
town.region('gen:town-square', '霜灯炉广场', 'plaza', circle(C, C, 325), {
  decor: 'asphalt',
  snow_cover: 0.12,
  label: [C, C + 290],
  place: {
    type: '公共热源',
    summary:
      '环形小镇正中的霜灯炉，燃料与材料在炉南交接，保温修筑在这里完成。先完成往返劳动，公共库存才会增加。',
    features: ['中央霜灯炉', '燃料交接台', '保温施工区'],
    arrival: [C, C + 270],
    station: 'frostlight_arrival_generator',
    node: 'frostlight_node_generator',
  },
})

const sites = [
  [
    'gen:forest',
    '西环煤场',
    'fuel',
    [650, C],
    'forest',
    '积雪下的煤垛与木料堆。工作取得燃料后沿环路运回霜灯炉。',
  ],
  [
    'gen:market',
    '东环粮站',
    'food',
    [3550, C],
    'market',
    '冻粮棚旁的配给院。整理食材并把食物运回公共库，才能供全镇用餐。',
  ],
  [
    'gen:workshop',
    '北环工坊院',
    'materials',
    [C, 1000],
    'plaza',
    '工坊门前的修筑院，回收铁件、木板和毡布，保温工程需要这些材料。',
  ],
  [
    'gen:clinic',
    '南环诊疗院',
    'shelter',
    [C, 3200],
    'plaza',
    '风雪中的互助诊疗院，居民可以完成照护工作，稳住大家的信心。',
  ],
]
for (const [id, name, station, [x, y], kind, summary] of sites) {
  town.region(id, name, kind, circle(x, y, 185), {
    decor: 'asphalt',
    snow_cover: 0.32,
    label: [x, y + 165],
    place: {
      type: '公共工作地点',
      summary,
      features: [name, '物资装卸空地'],
      arrival: [x, y],
      station: `frostlight_arrival_${station}`,
      node: `frostlight_node_${station}`,
    },
  })
}

// 清扫后的环路露出深色压实地面，积雪仍留在路缘；不靠改天气让道路显形。
const roadShapes = [470, 1060, 1600].map((r) => band(arc(C, C, r, r, 0, 360, 72), 84))
for (let a = 0; a < 360; a += 60) roadShapes.push(band([polar(320, a), polar(1600, a)], 78))
roadShapes.push(
  band(
    [
      [C, C + 1600],
      [C, C + 1840],
    ],
    90
  )
)
const roadSurface = union(...roadShapes)
const inner = circle(C, C, 510)
const warmPaths = union(
  roadSurface,
  band(
    [
      [C, C + 270],
      [C, C + 470],
    ],
    64
  )
)
// 只拆分原暖环中的装饰格：这两块都没有 place，合起来仍是原来的暖环，
// 已登记地点的 cells、全部行走节点/道路/落脚点保持不变。
town.region('frostlight_warm_paths', '', 'plaza', minus(inner, minus(inner, warmPaths)), {
  decor: 'asphalt',
  snow_cover: 0.18,
})
town.region('frostlight_inner', '', 'plaza', inner, { decor: 'clearing' })
town.region('frostlight_roads', '环镇道路', 'road', roadSurface, {
  decor: 'asphalt',
  snow_cover: 0.22,
  place: {
    type: '公共道路',
    summary: '三道同心环路和六条放射状通道连接全镇，工作物资由这些道路运回中央霜灯炉。',
    arrival: [C + 1060, C],
    onRoad: 40,
    station: 'frostlight_arrival_roads',
    node: 'frostlight_node_roads',
  },
})
town.region('frostlight_snow', '', 'grass', circle(C, C, 1740), { decor: 'clearing' })
town.region('frostlight_forest', '', 'forest', minus(circle(C, C, 1900), circle(C, C, 1730)), {
  decor: 'woods',
})

const SLATE = ['#555d66', '#414953', '#303a43']
const BRASS = ['#ad7848', '#956039', '#c38e59']
const BLUE = ['#506d7c', '#405c6b', '#698694']
const RED = ['#98584d', '#81483f', '#ad6c5d']

// 使用朝南的紧凑独立宿舍，避免侧墙大幅遮挡中央炉；屋门附近始终留出人行空地。
const homeNames = ['守炉人的家', '运输员的家', '厨师的家', '粮站员的家', '修筑师的家', '医护员的家']
for (let i = 0; i < 6; i++) {
  const [x, y] = polar(760, i * 60 + 30)
  const id = `home_0${i + 1}`
  town.building(id, homeNames[i], 'home', [x - 150, y - 105, 300, 210], {
    look: { wall: 'painted', paint: [BRASS, BLUE, RED][i % 3], roof: SLATE },
    place: {
      type: '住家',
      residential: true,
      summary: `第一、二环之间的第 ${i + 1} 间保温宿舍。朝向环路的门口有装卸和歇脚的空地。`,
    },
  })
}

town.building('indoor_dining_hall', '暖环公共厨房', 'canteen', [2920, 2820, 350, 245], {
  look: { wall: 'painted', paint: BRASS, roof: SLATE },
  place: {
    type: '公共地点',
    summary: '内圈东南的公共厨房，窗里透着暖光。全镇的粮食由霜灯镇公共库存统一配给。',
  },
})
town.building('indoor_clinic', '南环诊疗所', 'clinic', [2310, 3320, 320, 220], {
  look: { wall: 'painted', paint: RED, roof: SLATE },
  place: { type: '公共地点', summary: '紧挨南环诊疗院的保温诊所。医护人员在门外的院落接应居民。' },
})
town.building('indoor_dock_warehouse', '北环修筑工坊', 'warehouse', [1930, 615, 340, 245], {
  look: { wall: 'painted', paint: BLUE, roof: SLATE },
  place: { type: '公共地点', summary: '北环工坊院背后的修筑工坊，堆放保温毡和维修工具。' },
})
town.building('indoor_market_shop', '冻粮库', 'shop', [3240, 1710, 300, 210], {
  look: { wall: 'wood', roof: SLATE },
  place: { type: '公共地点', summary: '东环粮站背后的冻粮库，食材在门外清点装车。' },
})

// 额外的小煤棚用全新道具编号，避免从来源房间复制出重复编号。
town.building('frostlight_coal_shed', '西环煤棚', 'warehouse', [660, 1710, 300, 210], {
  room: own(
    room(480, 360, [
      ['frostlight_coal_box', 'core:storage-box@1', '煤棚工具箱', 100, 120],
      ['frostlight_coal_bench', 'core:seat@2', '煤棚长凳', 350, 140],
    ]),
    'frostlight_coal_shed'
  ),
  look: { wall: 'wood', roof: SLATE },
  place: { type: '公共地点', summary: '西环煤场背后的避风木棚，供搬运人员暂歇。' },
})

for (const [i, r] of [470, 1060, 1600].entries())
  town.road(`frostlight_ring_${i + 1}`, arc(C, C, r, r, 0, 360, 72), i === 1 ? 76 : 64, {
    curve: false,
    lamp: i === 0 ? 'lantern' : 'none',
  })
for (let a = 0; a < 360; a += 60)
  town.road(`frostlight_spoke_${a}`, [polar(320, a), polar(1600, a)], 68, {
    curve: false,
    lamp: 'lantern',
  })
// 炉南侧的交接点接第一环，不穿过中央模型；南入口只到外环，不横穿宿舍。
town.road(
  'frostlight_furnace_access',
  [
    [C, C + 270],
    [C, C + 470],
  ],
  64,
  { curve: false }
)
town.road(
  'frostlight_south_entry',
  [
    [C, C + 1600],
    [C, C + 1840],
  ],
  80,
  { curve: false }
)

const doc = seal(town.build())
const outIndex = process.argv.indexOf('--out')
const out =
  outIndex >= 0
    ? process.argv[outIndex + 1]
    : fileURLToPath(new URL('../../data/maps/frostlight/map.json', import.meta.url))
if (!out) throw Error('--out 需要一个输出文件')
fs.mkdirSync(path.dirname(out), { recursive: true })
fs.writeFileSync(
  out,
  JSON.stringify(doc, null, 2).replace(/\[\s+(-?[\d.]+),\s+(-?[\d.]+)\s+\]/g, '[$1, $2]') + '\n'
)
console.log(
  `${doc.name}：${doc.layout.spaces.length} 栋房屋，${doc.topology.places.length} 个地点，${doc.layout.edges.length} 段路`
)
