// 内置地图「断楼城」：末日废土风格。海边的旧城塌了一半，北边一排断楼只剩空壳（前后错开，两栋塌成半截，
// 楼脚堆着碎水泥），楼下是裂开积沙的旧滨江大道。中央大道从旧城广场往南拐一道弯到南城门，路上堵着当年
// 没开走的车；广场东边是霓虹夜市，几块横的竖的霓虹招牌夜里把地面染上色。人住在铁皮棚里，三三两两扎堆，
// 小街都是弯的。海岸碎：东边塌进去一个大湾，湾里一小块碎石台地上还立着半截楼；西南一道旧堤断成两截。
// 海早就退干了，干海床上躺着大小两副鲸骨、骆驼骨架、牛头骨和鱼骨，秃鹫在鲸骨、废墟公园和高楼上空盘旋，
// 骨头边、楼顶上蹲着几只。
// 断楼是只看不进的楼（layout.ruins），骨头、火盆、霓虹、秃鹫是按坐标立的立牌（layout.standees、flocks）。
// 房子的门都开在南墙、前低后高；内景、户外地点的道具和落脚点按编号从默认地图搬（旅馆、茶水铺在这里改），
// 改了设计重新跑：
//   node scripts/maps/broken-towers.mjs        写 data/maps/broken-towers/map.json（封好摘要；--out 另写一处）
//   target/debug/town-map validate < data/maps/broken-towers/map.json
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { seal } from '../mapgen/document.mjs'
import { band, blob, own, poly, rect, room, roomOf, smooth, townMap, union } from './townmap.mjs'

const FILE = new URL('../../data/maps/broken-towers/map.json', import.meta.url)
const SOURCE = new URL('../../data/maps/2d-town/map.json', import.meta.url)
// --source 换内景来源，--out 换输出（调设计时不动正式文件）
const arg = (name) => {
  const i = process.argv.indexOf(name)
  return i > 0 ? process.argv[i + 1] : undefined
}
const source = JSON.parse(fs.readFileSync(arg('--source') ?? SOURCE, 'utf8'))

const WORLDVIEW =
  '大灾变过去十二年了。海早就退干，旧海床白茫茫一片，龟裂的泥里躺着鲸鱼的骨头，秃鹫整天在上头打转。' +
  '海边这座旧城塌了一半，北边那排高楼只剩空壳，有两栋已经塌成半截，没人敢上去住；活下来的人在楼下用铁皮、' +
  '集装箱和碎水泥搭棚子过日子。\n\n' +
  '镇上的人靠拾荒、修旧东西和以物换物过活：拾荒工坊把废车拆成零件，物资库管着全镇的水和罐头，' +
  '大锅饭一天开三顿，诊所里的药总是不够，旧书店里还留着几本没被拿去烧火的书。大事在幸存者议事厅里一起商量。' +
  '中央大道上还堵着当年没开走的车，南城门外就是干海床。\n\n' +
  '天一黑，霓虹夜市的灯一盏盏亮起来，大家围着油桶火盆换东西、喝一口茶水铺的热茶，像旧日子回来了一会儿。' +
  '日子苦，但邻里之间互相照应，谁也不想再失去谁。'

const W = 8000,
  H = 5600
const town = townMap({
  id: 'broken-towers',
  name: '断楼城',
  description:
    '海边的旧城塌了一半：北边一排断楼只剩空壳，楼下是铁皮棚、拐弯的中央大道和霓虹夜市；' +
    '海早就退干了，干海床上躺着鲸骨，秃鹫在上空打转。',
  width: W,
  height: H,
  source,
  roads: 'outdoor_road_01',
  script: 'scripts/maps/broken-towers.mjs',
  environment: { preset: 'wasteland' },
  worldview: WORLDVIEW,
  meals: [
    { name: '早饭', start: 360, end: 510, menu: '稀糊糊、压缩饼干和一碗热水' },
    { name: '午饭', start: 690, end: 810, menu: '罐头炖豆子和杂粮饼' },
    { name: '晚饭', start: 1050, end: 1200, menu: '大锅蘑菇汤和烤饼' },
  ],
})

// ---- 地形 ----
// 底稿海岸：北岸一溜碎堤，东边塌进去一个大湾（湾里一块碎石台地），西边一个小湾，西南一道旧堤断成两截
// prettier-ignore
const coast = smooth([
  [620, 1180], [760, 900], [1060, 820], [1300, 940], [1520, 760], [1900, 700], [2250, 820], [2600, 720],
  [3000, 760], [3350, 640], [3800, 690], [4300, 620], [4700, 740], [5050, 660], [5450, 780], [5800, 700],
  [6200, 820], [6600, 760], [6950, 900], [7250, 1100], [7380, 1450], [7300, 1800], [7420, 2150],
  [7150, 2420], [6700, 2560], [6420, 2820], [6480, 3150], [6800, 3300], [7200, 3260], [7450, 3550],
  [7380, 3950], [7480, 4300], [7250, 4650], [6900, 4820], [6500, 4720], [6100, 4900], [5600, 4820],
  [5200, 4980], [4700, 4880], [4350, 5020], [3900, 5060], [3500, 4900], [3100, 5010], [2700, 4880],
  [2300, 4960], [1900, 4820], [1500, 4930], [1100, 4780], [800, 4560], [640, 4200], [520, 3800],
  [700, 3500], [980, 3300], [900, 3000], [600, 2850], [480, 2450], [560, 2050], [500, 1650], [620, 1180],
], 50)
const DIKE = [
  [2250, 4880],
  [2080, 5120],
]
const DIKE_TIP = [
  [1960, 5270],
  [1760, 5490],
]
const terrace = blob(7020, 2950, 300, 200, 6, 0.2)
town.island(union(poly(coast), band(DIKE, 170), band(DIKE_TIP, 170), terrace), union(), {
  coast: 1,
  bay: 14,
  warp: 32,
  erosion: 56,
  rim: 4,
})

// 两条大道的中线：旧滨江大道顺着楼脚弯，中央大道从广场南沿往南拐一道弯到城门
// prettier-ignore
const BOULEVARD = [[700, 1720], [1500, 1650], [2400, 1720], [3200, 1630], [4000, 1670], [4800, 1600], [5600, 1690], [6400, 1640], [7050, 1780]]
const AVENUE = [
  [3950, 2560],
  [3950, 3280],
  [4250, 3800],
  [4300, 4880],
]
const boulevardLine = smooth(BOULEVARD)
/** 旧滨江大道在 x 处的中线 y：小街从这里接上大道 */
function onBoulevard(x) {
  for (let i = 0; i + 1 < boulevardLine.length; i++) {
    const [ax, ay] = boulevardLine[i],
      [bx, by] = boulevardLine[i + 1]
    if (x >= ax && x <= bx) return [x, Math.round(ay + ((by - ay) * (x - ax)) / (bx - ax))]
  }
  throw Error(`旧滨江大道不经过 x=${x}`)
}
const avenueLine = smooth(AVENUE)
const avenueLength = avenueLine.reduce(
  (s, p, i) => (i ? s + Math.hypot(p[0] - avenueLine[i - 1][0], p[1] - avenueLine[i - 1][1]) : 0),
  0
)
/** 中央大道上的一点：从广场南沿走过全长的 t（0～1），再往西（side 负）或往东（正）偏 side 个单位 */
function onAvenue(t, side = 0) {
  let left = t * avenueLength
  for (let i = 0; i + 1 < avenueLine.length; i++) {
    const [ax, ay] = avenueLine[i],
      [bx, by] = avenueLine[i + 1]
    const len = Math.hypot(bx - ax, by - ay)
    if (left <= len || i + 2 === avenueLine.length) {
      const k = Math.min(1, left / len)
      // 朝东的法线：大道大体由北往南走，(dy, −dx) 指向东
      const [nx, ny] = [(by - ay) / len, -(bx - ax) / len]
      return [
        Math.round(ax + (bx - ax) * k + nx * side),
        Math.round(ay + (by - ay) * k + ny * side),
      ]
    }
    left -= len
  }
}

// ---- 区域（先登记的先占格子；没有名字的只管样子） ----
const PUBLIC = '公共地点',
  SHOP = '铺面'
// 旧城广场：正中一根断了尖的方尖碑，四角火盆；公告栏、报摊和卖艺的位置从默认图的中心广场搬来
town.region(
  'outdoor_plaza_01',
  '旧城广场',
  'plaza',
  poly([
    [3420, 1830],
    [4380, 1790],
    [4520, 2120],
    [4380, 2520],
    [3700, 2560],
    [3420, 2300],
  ]),
  {
    landmark: 'obelisk',
    place: {
      type: PUBLIC,
      summary:
        '断楼脚下的旧城广场，石板缺了不少，正中立着一根断了尖的方尖碑，四角烧着油桶火盆；' +
        '公告栏还有人在贴，镇上的人常在这里碰面、听人弹琴。',
      features: ['断了尖的方尖碑', '公告栏', '油桶火盆', '碎石板'],
      arrival: [3950, 2470],
      station: 'place_arrival_central_plaza',
      node: 'arrival_central_plaza',
      from: 'outdoor_plaza_01',
      rename: true,
      at: {
        中心广场公告栏张贴处__post_right: [3660, 2040],
        中心广场公告栏阅读处__read_left: [3590, 2040],
        中心广场报纸叫卖点__sell: [4270, 2050],
        中心广场报纸整理点__papers: [4340, 2050],
        中心广场排练点__rehearse: [3720, 2420],
        中心广场演奏点__perform: [4200, 2420],
        slot_bulletin_publish_01: [3660, 2040],
        slot_bulletin_read_01: [3590, 2040],
        slot_musician_perform_01: [4150, 2410],
        slot_musician_rehearse_01: [3770, 2410],
      },
    },
  }
)
// 霓虹夜市：篷布摊挤成一片，两头火盆；两个杂货摊、一张长凳
town.region(
  'outdoor_market_01',
  '霓虹夜市',
  'market',
  poly([
    [4580, 1880],
    [5600, 1840],
    [5700, 2300],
    [5300, 2600],
    [4620, 2500],
  ]),
  {
    place: {
      type: PUBLIC,
      summary:
        '旧城广场东边的夜市，篷布摊挤成一片，卖拆下来的零件、罐头和自酿的饮料；' +
        '天一黑几块霓虹招牌亮起来，粉的、青的、黄的光照在地上，大家围着火盆换东西。',
      features: ['篷布摊', '霓虹招牌', '油桶火盆', '杂货摊'],
      arrival: [5000, 2560],
      onRoad: 60,
      station: 'place_arrival_market',
      node: 'arrival_market',
      props: [
        {
          id: 'night_market_stall_west__count',
          definition: 'core:prop_c75138b13a@1',
          name: '夜市西头杂货摊',
          at: [4880, 2300],
        },
        {
          id: 'night_market_stall_east__tidy',
          definition: 'core:prop_27dee840cf@1',
          name: '夜市东头杂货摊',
          at: [5380, 2300],
        },
        {
          id: 'night_market_seat__rest',
          definition: 'core:seat@2',
          name: '夜市火盆边的长凳',
          at: [5120, 2460],
        },
      ],
      stations: [
        {
          id: 'slot_night_market_trade_01',
          name: '摆摊换东西',
          at: [5240, 2360],
          activity: 'activity_night_market_trade',
          pose: 'work',
          role: 'worker',
        },
        {
          id: 'slot_night_market_rest_01',
          name: '围着火盆歇脚',
          at: [5020, 2440],
          activity: 'activity_night_market_rest',
          pose: 'rest',
          role: 'visitor',
        },
      ],
    },
  }
)
// 南城门：中央大道南头，门外就是干海床
town.region('outdoor_south_gate_01', '南城门', 'gate', rect(4160, 4830, 300, 150), {
  place: {
    type: PUBLIC,
    summary: '中央大道南头的旧城门，两边烧着火盆，门外就是龟裂的干海床；新来的人从这里进镇。',
    features: ['城门', '油桶火盆'],
    arrival: [4300, 4880],
    onRoad: 60,
    station: 'place_arrival_south_entrance',
    node: 'arrival_south_entrance',
    from: 'outdoor_south_gate_01',
  },
})
// 中央大道：裂开积沙的沥青，当年堵死的车推到两边，中间让出一条走人的路
// 沥青带收在城门前，城门那块铺石板
town.region(
  'outdoor_avenue_01',
  '中央大道',
  'plaza',
  band([...AVENUE.slice(0, 3), [4295, 4760]], 300),
  {
    decor: 'asphalt',
    place: {
      type: PUBLIC,
      summary:
        '从旧城广场往南拐一道弯通到南城门的旧大道，沥青裂成一块块、积着沙；当年没开走的车被推到两边，' +
        '一辆挨一辆锈着，中间让出一条走人的路，拾荒的人常在车里翻找还能用的东西。',
      features: ['裂开的沥青路面', '堵死的废车', '油桶火盆'],
      arrival: onAvenue(0.2),
      onRoad: 60,
      station: 'place_arrival_central_avenue',
      node: 'arrival_central_avenue',
      stations: [
        {
          id: 'slot_avenue_scavenge_01',
          name: '在废车里翻找',
          at: onAvenue(0.3, 70),
          activity: 'activity_avenue_scavenge',
          pose: 'work',
          role: 'visitor',
        },
      ],
    },
  }
)
// 旧滨江大道：楼脚下一条沥青带，不是地点
town.region('asphalt_boulevard', '', 'plaza', band(BOULEVARD, 190), { decor: 'asphalt' })
// 废墟公园：枯树林、塌了半边顶的凉亭、干池子
town.region('outdoor_ruin_park_01', '废墟公园', 'park', blob(3330, 3400, 380, 230, 3, 0.18), {
  place: {
    type: PUBLIC,
    summary:
      '大锅饭南边一片枯树林，中间一座塌了半边顶的凉亭，旧池子早就干了，常有人来这里坐坐、发发呆。',
    features: ['枯树', '塌了顶的凉亭', '干池子', '长椅'],
    arrival: [3330, 3640],
    onRoad: 60,
    station: 'place_arrival_ruin_park',
    node: 'arrival_ruin_park',
    props: [
      {
        id: 'ruin_park_bench__rest',
        definition: 'core:seat@2',
        name: '废墟公园长椅',
        at: [3160, 3560],
      },
    ],
    stations: [
      {
        id: 'slot_ruin_park_rest_01',
        name: '坐着发呆',
        at: [3470, 3570],
        activity: 'activity_ruin_park_rest',
        pose: 'rest',
        role: 'visitor',
      },
    ],
  },
})
// 废车场：东南岸边，废车、轮胎、废铁堆，能翻出点东西
town.region('outdoor_scrapyard_01', '废车场', 'area', blob(6060, 4700, 340, 140, 5, 0.18), {
  landmark: 'scrapyard',
  place: {
    type: PUBLIC,
    summary: '东南岸边堆满废车、轮胎和废铁的空场，拾荒的人常来这里拆零件、翻找还能用的东西。',
    features: ['废车', '轮胎堆', '废铁堆'],
    arrival: [5930, 4590],
    onRoad: 60,
    station: 'place_arrival_scrapyard',
    node: 'arrival_scrapyard',
    props: [
      {
        id: 'scrapyard_heap__search',
        definition: 'core:island-rubble@1',
        name: '废车场废铁堆',
        at: [6260, 4760],
      },
    ],
    stations: [
      {
        id: 'slot_scrapyard_scavenge_01',
        name: '在废车堆里翻找',
        at: [6120, 4770],
        activity: 'activity_scrapyard_scavenge',
        pose: 'work',
        role: 'visitor',
      },
    ],
  },
})
// 断堤：西南的旧海堤断成两截，前半截孤零零地立在干海床上；坐在堤头能看见那副大鲸骨
town.region('outdoor_broken_dike_01', '断堤', 'plaza', band(DIKE, 110), {
  place: {
    type: PUBLIC,
    summary:
      '西南岸边的一道旧海堤，断成了两截，前半截孤零零地立在干海床上；坐在堤头能看见海床上那副大鲸骨，' +
      '秃鹫在骨头上空打转。',
    features: ['断成两截的海堤', '鲸骨', '秃鹫'],
    arrival: [2240, 4840],
    station: 'place_arrival_broken_dike',
    node: 'arrival_broken_dike',
    props: [
      {
        id: 'broken_dike_seat__rest',
        definition: 'core:seat@2',
        name: '断堤头的石墩',
        at: [2150, 5030],
      },
    ],
    stations: [
      {
        id: 'slot_broken_dike_watch_01',
        name: '坐在堤头看鲸骨',
        at: [2120, 5080],
        activity: 'activity_broken_dike_watch',
        pose: 'rest',
        role: 'visitor',
      },
    ],
  },
})
// 断开的前半截堤、塌楼脚下的碎石地：只管样子
town.region('dike_tip', '', 'plaza', band(DIKE_TIP, 110))
town.region('rubble_west', '', 'area', blob(2800, 1560, 420, 120, 7, 0.3), { decor: 'rubble' })
town.region('rubble_east', '', 'area', blob(6500, 1560, 380, 110, 8, 0.3), { decor: 'rubble' })
town.region('rubble_lane', '', 'area', blob(1960, 3060, 230, 140, 9, 0.3), { decor: 'rubble' })
// 小镇道路：镇子中间一大片，邮差的整理点在西边横街上
town.region('outdoor_road_01', '小镇道路', 'road', blob(3700, 3150, 2400, 1300, 2, 0.08), {
  place: {
    type: PUBLIC,
    summary: '连着铁皮棚、公共建筑和户外去处的土路和旧沥青大道，居民从这里往来全镇。',
    features: [],
    arrival: [1750, 2650],
    onRoad: 60,
    station: 'place_arrival_town_roads',
    node: 'arrival_town_roads',
    from: 'outdoor_road_01',
    at: {
      小镇道路投递袋整理点__mailbag: [1796, 2585],
      小镇道路邮件分拣点__sort: [1700, 2585],
      slot_postal_collect_outgoing_mail_01: [1750, 2585],
      slot_postal_prepare_mailbag_01: [1796, 2585],
      slot_postal_sort_mail_01: [1700, 2585],
    },
  },
})

// ---- 断楼：只看不进，前后错开，两栋塌成半截（矮）；湾里台地上还立着半截 ----
const GREY = [
  ['#9a968e', '#86827a', '#625e58'],
  ['#8e928e', '#7a7e7a', '#5a5e5a'],
  ['#a09486', '#8a7e70', '#665c50'],
]
// prettier-ignore
const TOWERS = [
  ['tower_1', [980, 1120, 540, 360], 72],
  ['tower_2', [1720, 1000, 600, 420], 120],
  ['tower_3', [2560, 1200, 500, 320], 30],
  ['tower_4', [3500, 980, 800, 480], 170],
  ['tower_5', [4560, 1100, 520, 360], 104],
  ['tower_6', [5320, 980, 640, 420], 150],
  ['tower_7', [6260, 1180, 500, 300], 38],
  ['tower_8', [6860, 2840, 300, 220], 56],
]
TOWERS.forEach(([id, box, height], k) => town.ruin(id, box, height, { roof: GREY[k % 3] }))

// ---- 房子：门开在南墙；铁皮棚三三两两扎堆，大小不一 ----
// 自己写的旅馆内景：前台、大堂茶桌和座位，三张客床
// prettier-ignore
const inn = room(1152, 704, [
  ['inn_front_desk__guest', 'core:prop_91ab2f9d1f@1', '霓虹旅馆前台', 300, 470],
  ['inn_front_desk__staff', 'core:prop_1f268c17ba@1', '霓虹旅馆前台内侧', 300, 400],
  ['inn_tea_table__tea', 'core:tea-table@1', '霓虹旅馆大堂茶桌', 800, 470],
  ['inn_lobby_seat__rest', 'core:seat@2', '霓虹旅馆大堂座位', 880, 540],
  ['inn_guest_bed_west__sleep', 'core:bed@2', '霓虹旅馆客床（西）', 150, 150],
  ['inn_guest_bed_middle__sleep', 'core:bed@2', '霓虹旅馆客床（中）', 880, 150],
  ['inn_guest_bed_east__sleep', 'core:bed@2', '霓虹旅馆客床（东）', 1010, 150],
  ['inn_water__drink', 'core:drinking_water@1', '霓虹旅馆水桶', 1060, 580],
], [
  ['slot_inn_receive_guests_01', '接待客人', 'activity_inn_receive_guests', 'service', 'worker', 300, 350],
  ['slot_inn_rest_lobby_01', '歇着', 'activity_inn_rest', 'rest', 'visitor', 700, 560],
])
town.building('indoor_neon_inn', '霓虹旅馆', 'inn', [5820, 1980, 600, 380], {
  room: own(inn, 'indoor_neon_inn'),
  place: {
    type: PUBLIC,
    summary:
      '霓虹夜市东头的旅馆，拼起来的铁皮和废料板盖的，门口竖着一块亮青光的招牌，有前台、大堂茶桌和几张客床，' +
      '过路的人可以在这里歇脚过夜。',
  },
})
// 茶水铺：内景照默认图的咖啡馆，咖啡机换成茶席，名字跟着改
const cafe = roomOf(source, 'indoor_flower_cafe')
const TEA_NAMES = [
  ['花房座位', '窗边座位'],
  ['糕点柜', '茶点柜'],
]
const teaName = (text) => TEA_NAMES.reduce((t, [a, b]) => t.replaceAll(a, b), text)
const teahouse = {
  ...cafe,
  props: cafe.props.map((p) => {
    const named = { ...p, name: teaName(p.name), mark: { ...p.mark, name: teaName(p.mark.name) } }
    if (p.definition !== 'core:coffee_machine@2') return named
    const id = 'tea_table_north__tea'
    return {
      id,
      definition: 'core:tea-table@1',
      name: '花房咖啡馆茶席',
      locale: p.locale,
      mark: { ...p.mark, id, name: '花房咖啡馆茶席' },
    }
  }),
  stations: cafe.stations.map((s) => (s.name === '冲咖啡' ? { ...s, name: '煮茶' } : s)),
}
town.building('indoor_flower_cafe', '茶水铺', 'cafe', [3420, 4040, 360, 250], {
  room: teahouse,
  place: {
    type: SHOP,
    summary:
      '废墟公园南边的茶水铺，烧着一壶壶热茶，摆着几样茶点，居民可以在这里喝茶、吃点心和聊天。',
  },
})
town.building('indoor_town_hall', '幸存者议事厅', 'townhall', [2700, 1980, 600, 400], {
  place: {
    type: PUBLIC,
    summary:
      '旧城广场西边、塌楼脚下的议事厅，补丁水泥砌的，大事都在这里一起商量，也办些镇上的杂事。',
  },
})
town.building('indoor_workshop', '拾荒工坊', 'workshop', [1160, 2980, 560, 380], {
  place: {
    type: SHOP,
    summary: '西街上的拾荒工坊，把捡回来的废车、废铁拆成零件，修旧东西、做新家什。',
  },
})
town.building('indoor_dining_hall', '大锅饭', 'canteen', [2680, 2760, 600, 360], {
  place: {
    type: PUBLIC,
    summary:
      '旧城广场西南边的大食堂，一口大锅一天开三顿，面向全镇供饭，居民可以在这里帮厨、吃饭和碰面。',
  },
})
town.building('indoor_clinic', '诊所', 'clinic', [4500, 3040, 460, 330], {
  place: {
    type: PUBLIC,
    summary:
      '中央大道东边的诊所，集装箱改的，门口一块亮绿光的十字招牌，为镇民看病和取药，药总是不够。',
  },
})
town.building('indoor_dock_warehouse', '物资库', 'warehouse', [5380, 3330, 680, 400], {
  place: {
    type: SHOP,
    summary: '东街上的物资库，几只集装箱连起来的大库房，管着全镇的水、罐头和换来的物资。',
  },
})
town.building('indoor_library', '旧书店', 'library', [2880, 4130, 460, 330], {
  place: {
    type: PUBLIC,
    summary: '南岸边的旧书店，书架上还留着几本没被拿去烧火的书，居民可以在这里看书、借书和写东西。',
  },
})
// 住家：铁皮棚，屋顶和墙按四种拼法轮着挑
const SHACK = [
  { roof: ['#a07a5a', '#8a6446', '#62452e'], wall: 'scrap' },
  { roof: ['#8a8a82', '#74746c', '#52524c'], wall: 'tin' },
  { roof: ['#4f6f86', '#3f5a70', '#2a3e50'], wall: 'concrete' },
  { roof: ['#b0703a', '#94602e', '#6a4420'], wall: 'tin' },
]
// prettier-ignore
const homes = [
  ['home_01', '楼脚一号', [1240, 1960, 400, 270], '西头断楼脚下'],
  ['home_02', '楼脚二号', [1700, 2080, 340, 240], '西头断楼脚下'],
  ['home_03', '楼脚三号', [1990, 2350, 380, 260], '西头断楼脚下、议事厅西边'],
  ['home_04', '东湾一号', [6520, 2000, 400, 260], '霓虹旅馆东边、塌湾跟前'],
  ['home_05', '西街一号', [1780, 3200, 360, 250], '西街碎石地南边'],
  ['home_06', '西街二号', [2060, 3820, 420, 280], '西街南头'],
  ['home_07', '大道东一号', [4640, 3620, 380, 260], '中央大道东边、诊所南边'],
  ['home_08', '大道东二号', [4520, 4240, 330, 230], '中央大道东边'],
  ['home_09', '东街一号', [5620, 3960, 440, 290], '东街上、物资库南边'],
  ['home_10', '南岸一号', [1300, 4150, 420, 280], '西南岸边'],
  ['home_11', '大道东三号', [4900, 4250, 360, 250], '中央大道东边'],
  ['home_12', '东街二号', [6260, 4020, 400, 270], '东街东头、废车场北边'],
]
homes.forEach(([id, name, box, where], k) =>
  town.building(id, name, 'home', box, {
    look: { roof: SHACK[k % 4].roof, roofing: 'tin', wall: SHACK[k % 4].wall },
    place: {
      type: '住家',
      summary: `${where}的一间铁皮棚屋，可分配给居民居住和休息。`,
      residential: true,
    },
  })
)

// ---- 路：大道、横街，小街都是弯的 ----
// [编号, 折线, 宽, 选项]
// prettier-ignore
const ROADS = [
  ['boulevard', BOULEVARD, 70],
  ['avenue', AVENUE, 80],
  // 广场南沿的横街：西头 → 中央大道 → 夜市南 → 霓虹旅馆门前
  ['cross_north', [[900, 2700], [1500, 2620], [2000, 2700], [2420, 2640], [3420, 2620], [3950, 2610], [4560, 2700], [5100, 2760], [5760, 2660], [6300, 2700]], 60],
  // 广场两边的小街，从横街上到大道
  ['plaza_west', [onBoulevard(3395), [3395, 2200], [3420, 2620]], 50],
  ['plaza_east', [onBoulevard(4545), [4550, 2200], [4560, 2700]], 50],
  // 西边两条弯弯的小街，从大道一直下到南岸
  ['w_lane', [onBoulevard(1000), [1120, 2300], [960, 2900], [1080, 3480], [960, 4100], [1140, 4620]], 54],
  ['mw_lane', [onBoulevard(2470), [2420, 2420], [2580, 3100], [2560, 3700], [2700, 4620]], 54],
  // 下横街：西岸 → 废墟公园南 → 中央大道
  ['cross_south', [[900, 3640], [1500, 3560], [2000, 3620], [2560, 3580], [3300, 3760], [4130, 3640]], 60],
  // 诊所门前的小街：中央大道 → 东边小街
  ['clinic_lane', [[4130, 3470], [4600, 3500], [5000, 3480], [5235, 3470]], 50],
  // 东边：旅馆门前往南到岸边；东横街从中央大道到塌湾边
  ['e_lane', [[5760, 2660], [5260, 3200], [5180, 3820], [5420, 4320], [5300, 4700]], 54],
  ['e_cross', [[4250, 3900], [4700, 4020], [5180, 3990], [5800, 3880], [6300, 3780]], 60],
  // 沿岸的路：西南 → 中央大道 → 东南
  ['s_coast', [[1140, 4620], [1800, 4560], [2700, 4620], [3600, 4500], [4290, 4620]], 60],
  ['e_coast', [[4290, 4620], [5000, 4600], [5300, 4700], [6000, 4560], [6600, 4380]], 60],
  // 塌湾边的小路、东头小街上到大道
  ['bay_path', [[6300, 3780], [6560, 3420]], 54],
  ['ne_lane', [[6300, 2700], [6480, 2420], [6460, 2100], onBoulevard(6400)], 54],
]
for (const [id, pts, width, options] of ROADS) town.road(id, pts, width, options)

// ---- 立牌：按坐标立，不占区域格子 ----
// 中央大道上堵死的废车：当年没开走的车被推到两边，顺着大道一辆挨一辆，隔几辆缺一辆，中间让出一条走人的路
// 横街接上大道的路口：路口两边不摆车，让出路来
const crossings = ROADS.filter(([id]) => id !== 'avenue')
  .flatMap(([, pts]) => [pts[0], pts[pts.length - 1]])
  .filter(([x, y]) => avenueLine.some(([ax, ay]) => Math.hypot(ax - x, ay - y) < 120))
for (let k = 0; k < 24; k++) {
  const t = 0.03 + k * 0.04
  for (const side of [-1, 1]) {
    // 按位置定的伪随机：缺哪几辆、离中线多远
    const roll = Math.abs(Math.sin(k * 12.9898 + side * 78.233) * 43758.5453) % 1
    const at = onAvenue(t, side * (112 + Math.round(roll * 24)))
    if (roll < 0.22 || crossings.some(([x, y]) => Math.hypot(x - at[0], y - at[1]) < 230)) continue
    town.standee('wreck', at, { flip: roll > 0.6 })
  }
}
// 夜市里多摆几排摊；东南岸边的废车场由区域的地标摆
for (const at of [
  [4880, 2150],
  [5280, 2190],
  [4920, 2420],
])
  town.standee('stalls', at)
// 议事厅背后、塌楼前面一块褪色的海景房广告牌
town.standee('billboard', [3230, 1900])
// 霓虹招牌：夜市四角和旅馆、食堂、诊所门前，有横有竖
// prettier-ignore
const NEON = [
  ['neon-star', [4680, 1900]], ['neon-bar', [5560, 1890]], ['neon-food', [5200, 2660]],
  ['neon-tea', [4660, 2600]], ['neon-inn', [6000, 2618]], ['neon-food', [3220, 3330]],
  ['neon-clinic', [4440, 3600]],
]
for (const [kind, at] of NEON) town.standee(kind, at)
// 油桶火盆：广场四角、大道边、城门两边、断堤口、东西两头
// prettier-ignore
const FIRES = [
  [3480, 1920], [4400, 1890], [3500, 2470], [4360, 2510], onAvenue(0.17, -215), onAvenue(0.56, -215),
  [4130, 4900], [4480, 4900], [2330, 4830], [1500, 2450], [6200, 3080],
]
for (const at of FIRES) town.standee('fire', at)
// 塌楼脚下、街角的碎水泥堆
// prettier-ignore
const RUBBLE = [
  [2350, 1530], [3260, 1540], [6100, 1560], [6880, 1600], [2120, 2860], [5640, 2990],
  [2440, 4500], [6700, 3560], [1500, 1560],
]
for (const at of RUBBLE) town.standee('rubble', at)
// 镇外的骨头：南边干海床上一副大鲸骨，东北一副小的（朝左），两具骆驼骨架，牛头骨、鱼骨
const WHALE = [2980, 5420]
town.standee('whale', WHALE)
town.standee('whale', [6900, 560], { flip: true })
const CAMEL = [7560, 2760]
town.standee('camel', CAMEL)
town.standee('camel', [820, 5000], { flip: true })
// prettier-ignore
for (const at of [[4760, 5150], [4980, 5260], [880, 2420], [1020, 4700], [7300, 4550], [2380, 5640]])
  town.standee('skull', at)
// prettier-ignore
for (const at of [[1250, 5300], [5700, 5200], [6700, 620], [600, 3150], [3800, 5700]])
  town.standee('fishbones', at)
// 蹲着的秃鹫：鲸骨边三只、骆驼骨架边一只，最高那栋楼顶上两只、东边高楼顶上一只
town.standee('vulture', [WHALE[0] + 520, WHALE[1] + 20], { flip: true })
town.standee('vulture', [WHALE[0] - 260, WHALE[1] + 30])
town.standee('vulture', [WHALE[0] + 760, WHALE[1] + 60], { flip: true })
town.standee('vulture', [CAMEL[0] + 140, CAMEL[1] + 30])
town.standee('vulture', [3700, 1460], { on: 'tower_4' })
town.standee('vulture', [4150, 1460], { on: 'tower_4', flip: true })
town.standee('vulture', [5600, 1400], { on: 'tower_6' })
// 盘旋的秃鹫：大鲸骨、废墟公园、最高那栋楼前、东北的小鲸骨上空
town.flock([WHALE[0], WHALE[1] - 120], 420, 4)
town.flock([3330, 3420], 570, 3)
town.flock([3900, 1500], 1100, 3)
town.flock([6900, 500], 480, 2)

const doc = seal(town.build())
// 按层缩进，坐标对（格子、折线上的点）各占一行，和默认地图一样的写法，改了好比对
const text = JSON.stringify(doc, null, 2).replace(/\[\s+(-?[\d.]+),\s+(-?[\d.]+)\s+\]/g, '[$1, $2]')
const out = arg('--out') ?? fileURLToPath(FILE)
fs.mkdirSync(path.dirname(out), { recursive: true })
fs.writeFileSync(out, text + '\n')
console.log(
  `${doc.layout.spaces.length} 栋房子、${doc.layout.ruins.length} 栋断楼、${doc.topology.places.length} 处地点、` +
    `${doc.layout.edges.length} 段路、${doc.topology.props.length} 件道具、${doc.layout.standees.length} 块立牌`
)
