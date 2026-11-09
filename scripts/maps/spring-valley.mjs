// 内置地图「温泉谷」：冰雪风格。海冻成了冰原，岛上盖着雪；北边雪松林里一片空地，四口青绿的温泉池
// 一级级往下，终年冒着白汽，池边一圈压雪的黑石头，入夜池水透出青光；池后是温泉旅馆，东边一间冒烟的桑拿木屋。
// 一条挂灯的温泉街从南入口一路往北，两边是茶屋、杂货铺、食堂和雪灯市集，街顶是足汤广场（一口小汤池）。
// 木屋人家三三两两散在东西两坡；西湾里是冰封渔港，西南岬角立着灯塔，东南湾的海冰上是冰钓场，
// 东北是雪橇坡，西边雪松林里一条步道。海岸画成有湾有岬，交给引擎扭曲冲刷。
// 房子的门都开在南墙、前低后高；住家按街区刷两三种漆色。房子的内景、户外地点的道具和落脚点
// 按编号从默认地图搬（旅馆、桑拿、茶屋的内景在这里写），改了设计重新跑：
//   node scripts/maps/spring-valley.mjs        写 data/maps/spring-valley/map.json（封好摘要；--out 另写一处）
//   target/debug/town-map validate < data/maps/spring-valley/map.json
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { seal } from '../mapgen/document.mjs'
import {
  blob,
  ellipse,
  minus,
  own,
  poly,
  rect,
  room,
  roomOf,
  smooth,
  spring,
  townMap,
  union,
} from './townmap.mjs'

const FILE = new URL('../../data/maps/spring-valley/map.json', import.meta.url)
const SOURCE = new URL('../../data/maps/2d-town/map.json', import.meta.url)
// --source 换内景来源，--out 换输出（调设计时不动正式文件）
const arg = (name) => {
  const i = process.argv.indexOf(name)
  return i > 0 ? process.argv[i + 1] : undefined
}
const source = JSON.parse(fs.readFileSync(arg('--source') ?? SOURCE, 'utf8'))

// 刷漆木板墙的漆色（中、暗、亮）：法伦红、赭黄、奶白、海蓝、松绿、焦糖
const RED = ['#a3392b', '#922f23', '#b14638']
const OCHRE = ['#cf9a3e', '#c18c33', '#d8a74e']
const CREAM = ['#e6dcc6', '#ddd2ba', '#ede5d2']
const BLUE = ['#3f6488', '#355778', '#4b7298']
const PINE = ['#4e7458', '#43664c', '#5a8264']
const CARAMEL = ['#9a6238', '#8a552e', '#a86f44']
// 雪薄处露出来的瓦（亮、中、暗）
const SLATE = ['#4e5460', '#424852', '#343a42']
const BROWN = ['#5a4a44', '#4a3e3a', '#3a302c']
const MOSS = ['#44584a', '#3a4c40', '#2e3c32']

const W = 8200,
  H = 5800
const town = townMap({
  id: 'spring-valley',
  name: '温泉谷',
  description:
    '雪松林环抱的温泉小镇，海冻成了冰原。北边林中四口青绿的温泉池一级级往下，终年冒着白汽；' +
    '一条挂灯的温泉街从南入口通到足汤广场，木屋人家散在东西两坡，西湾有冰封的渔港，东南的海冰上有人冰钓。',
  width: W,
  height: H,
  source,
  roads: 'outdoor_road_01',
  script: 'scripts/maps/spring-valley.mjs',
  environment: { preset: 'frozen' },
})

// ---- 地形 ----
// 底稿海岸：西北圆岬、北湾（雪松林背后）、东北长岬、东湾、东南湾（冰钓场）、南边镇口小湾、
// 西南灯塔岬、西湾（渔港）、西边小岬
// prettier-ignore
const coast = smooth(
  [
    [560, 1420], [520, 980], [800, 620], [1250, 450], [1800, 400], [2150, 520], [2380, 800],
    [2560, 880], [2760, 770], [2980, 520], [3500, 390], [4150, 420], [4700, 350], [5300, 420],
    [5900, 370], [6500, 440], [6950, 360], [7380, 230], [7820, 260], [8000, 470], [7880, 700],
    [7640, 820], [7600, 1150], [7820, 1500], [7930, 2000], [7840, 2500], [7600, 2800],
    [7300, 3000], [7240, 3250], [7380, 3450], [7700, 3600], [7930, 4000], [7880, 4500],
    [7800, 4950], [7560, 5180], [7300, 5060], [7050, 4900], [6750, 4850], [6450, 4930],
    [6200, 5150], [5800, 5330], [5300, 5420], [4880, 5360], [4600, 5470], [4280, 5470],
    [4050, 5400], [3800, 5240], [3450, 5200], [3150, 5330], [2850, 5400], [2300, 5450],
    [1800, 5420], [1420, 5340], [1180, 5520], [860, 5640], [560, 5560], [400, 5250],
    [520, 4900], [760, 4600], [700, 4250], [380, 4050], [300, 3900], [430, 3700], [420, 3350],
    [330, 3050], [240, 2850], [470, 2650], [640, 2450], [430, 2150], [400, 1780], [560, 1420],
  ],
  50
)
// 外海的小岛（岛上长林子，不然会被当成礁石）：北边一座、东边一座、西南一座小的
const ISLETS = [
  [1500, -60, 300, 150, 3],
  [8260, 3100, 170, 260, 7],
  [120, 5700, 220, 140, 11],
]
const islets = ISLETS.map(([x, y, rx, ry, seed]) => blob(x, y, rx, ry, seed, 0.22))
// 温泉：旅馆门前一口上池，往下左右两口，再往下一口，一级级往下；街顶的足汤广场一口小汤池
const POOLS = [
  ['upper', blob(4400, 1640, 280, 130, 41, 0.12)],
  ['west', blob(3720, 1930, 290, 160, 42, 0.14)],
  ['east', blob(4880, 1990, 300, 170, 43, 0.13)],
  ['lower', blob(4200, 2290, 270, 140, 44, 0.13)],
  ['footbath', blob(4560, 2890, 200, 100, 45, 0.1)],
]
const pools = union(...POOLS.map(([, shape]) => shape))
town.island(union(poly(coast), ...islets), spring(pools), {
  coast: 1,
  bay: 12,
  warp: 26,
  erosion: 46,
  rim: 4,
})
const dry = (shape) => minus(shape, pools)

// ---- 区域（先登记的先占格子；没有名字的只管样子） ----
const PUBLIC = '公共地点',
  SHOP = '铺面'
// 足汤广场：温泉街北头，正中一口小汤池，池边一圈长凳；公告栏、报摊和卖艺的位置从默认图的中心广场搬来
town.region(
  'outdoor_footbath_01',
  '足汤广场',
  'plaza',
  dry(
    poly(
      smooth([
        [4020, 2700],
        [4560, 2660],
        [4980, 2730],
        [5010, 3080],
        [4480, 3130],
        [3990, 3070],
      ])
    )
  ),
  {
    place: {
      type: PUBLIC,
      summary:
        '温泉街北头的石板广场，正中一口冒着热气的小汤池，池边一圈长凳，坐下就能泡脚；' +
        '四周有公告栏和路灯，镇上的人常在这里碰面、歇脚。',
      features: ['足汤池', '池边长凳', '公告栏', '路灯'],
      arrival: [4470, 3150],
      onRoad: 40,
      station: 'place_arrival_footbath_plaza',
      node: 'arrival_footbath_plaza',
      from: 'outdoor_plaza_01',
      at: {
        中心广场公告栏张贴处__post_right: [4120, 2790],
        中心广场公告栏阅读处__read_left: [4060, 2790],
        中心广场报纸叫卖点__sell: [4880, 2800],
        中心广场报纸整理点__papers: [4940, 2800],
        中心广场排练点__rehearse: [4100, 3040],
        中心广场演奏点__perform: [4900, 3040],
        slot_bulletin_publish_01: [4120, 2790],
        slot_bulletin_read_01: [4060, 2790],
        slot_musician_perform_01: [4860, 3030],
        slot_musician_rehearse_01: [4130, 3030],
      },
      props: [
        {
          id: 'footbath_seat_west__rest',
          definition: 'core:seat@2',
          name: '足汤池西边长凳',
          at: [4320, 2900],
        },
        {
          id: 'footbath_seat_east__rest',
          definition: 'core:seat@2',
          name: '足汤池东边长凳',
          at: [4800, 2900],
        },
        {
          id: 'footbath_seat_south__rest',
          definition: 'core:seat@2',
          name: '足汤池南边长凳',
          at: [4600, 3040],
        },
      ],
      stations: [
        {
          id: 'slot_footbath_rest_01',
          name: '坐在池边',
          at: [4400, 2990],
          activity: 'activity_footbath_rest',
          pose: 'rest',
          role: 'visitor',
        },
        {
          id: 'slot_footbath_rest_02',
          name: '坐在池边',
          at: [4730, 2990],
          activity: 'activity_footbath_rest',
          pose: 'rest',
          role: 'visitor',
        },
        {
          id: 'slot_footbath_rest_03',
          name: '坐在池边',
          at: [4500, 3040],
          activity: 'activity_footbath_rest',
          pose: 'rest',
          role: 'visitor',
        },
      ],
    },
  }
)
// 露天温泉：林中空地，池子之间留出步道；池边几处落脚点，两张长椅
town.region(
  'outdoor_hot_springs_01',
  '露天温泉',
  'park',
  dry(
    poly(
      smooth([
        [3180, 1640],
        [3600, 1460],
        [4100, 1430],
        [4600, 1440],
        [5200, 1600],
        [5400, 1900],
        [5220, 2240],
        [4700, 2470],
        [4200, 2580],
        [3700, 2400],
        [3220, 2160],
      ])
    )
  ),
  {
    decor: 'lawn',
    place: {
      type: PUBLIC,
      summary:
        '镇子北边雪松林里的一片空地，四口青绿的温泉池一级级往下，池边一圈压雪的黑石头，终年冒着白汽，' +
        '入夜池水透出青光；池子之间有步道，池边有长椅。',
      features: ['温泉池', '黑石池沿', '白汽', '池边长椅', '步道'],
      arrival: [4300, 2600],
      onRoad: 40,
      station: 'place_arrival_hot_springs',
      node: 'arrival_hot_springs',
      props: [
        {
          id: 'spring_bench_west__rest',
          definition: 'core:seat@2',
          name: '温泉池边长椅（西）',
          at: [3520, 2200],
        },
        {
          id: 'spring_bench_east__rest',
          definition: 'core:seat@2',
          name: '温泉池边长椅（东）',
          at: [5080, 2290],
        },
      ],
      stations: [
        {
          id: 'slot_spring_rest_01',
          name: '在池边歇脚',
          at: [4250, 2490],
          activity: 'activity_spring_rest',
          pose: 'rest',
          role: 'visitor',
        },
        {
          id: 'slot_spring_rest_02',
          name: '在池边歇脚',
          at: [3740, 2150],
          activity: 'activity_spring_rest',
          pose: 'rest',
          role: 'visitor',
        },
        {
          id: 'slot_spring_rest_03',
          name: '在池边歇脚',
          at: [4880, 2230],
          activity: 'activity_spring_rest',
          pose: 'rest',
          role: 'visitor',
        },
        {
          id: 'slot_spring_rest_04',
          name: '在池边歇脚',
          at: [4420, 1830],
          activity: 'activity_spring_rest',
          pose: 'rest',
          role: 'visitor',
        },
      ],
    },
  }
)
town.region('outdoor_market_01', '雪灯市集', 'market', rect(4700, 3930, 520, 320), {
  place: {
    type: PUBLIC,
    summary: '温泉街东侧的露天摊位，棚子上压着雪，摊前一排雪灯，居民会来这里逛摊、买东西和碰面。',
    features: ['露天摊位', '雪灯', '货架', '木桶'],
    arrival: [4960, 3950],
    station: 'place_arrival_market',
    node: 'arrival_market',
    from: 'outdoor_market_01',
  },
})
town.region('outdoor_south_gate_01', '南入口', 'gate', rect(4280, 5160, 320, 240), {
  place: {
    type: PUBLIC,
    summary: '温泉街南头通向镇外的入口，往外就是冻住的海，居民会在这里迎送和等待来客。',
    features: ['入口台阶', '路灯'],
    arrival: [4440, 5260],
    station: 'place_arrival_south_entrance',
    node: 'arrival_south_entrance',
    from: 'outdoor_south_gate_01',
  },
})
// 渔港压着西湾的岸，朝西临着冰面
town.region('outdoor_harbor_01', '冰封渔港', 'harbor', rect(470, 3260, 420, 520), {
  facing: [-1, 0],
  place: {
    type: PUBLIC,
    summary:
      '西湾里的木码头，栈桥伸到冰面上，渔船冻在冰里；码头上晾着鱼干、堆着货箱，居民会在这里处理渔具和渔获。',
    features: ['木码头', '栈桥', '冻住的渔船', '晾鱼架', '货箱'],
    arrival: [820, 3480],
    station: 'place_arrival_fishing_harbor',
    node: 'arrival_fishing_harbor',
    from: 'outdoor_harbor_01',
    at: {
      渔港渔具整理点__gear: [780, 3360],
      渔港渔获清点处__catch: [800, 3600],
      slot_fisher_catch_in_region_01: [760, 3660],
      slot_fisher_count_catch_01: [800, 3560],
      slot_fisher_organize_gear_01: [780, 3400],
    },
  },
})
// 冰钓场：东南湾的岸边，冰上一片冰钓小屋和冰窟窿（地标立在冰上）
town.region('outdoor_ice_fishing_01', '冰钓场', 'area', ellipse(6800, 4700, 300, 120), {
  landmark: 'icefishing',
  place: {
    type: PUBLIC,
    summary:
      '东南湾冻得最厚的一片海冰，冰上几间冰钓小屋和冰窟窿，岸边放着小凳，常有人坐着冰钓、看人钓鱼。',
    features: ['冰钓小屋', '冰窟窿', '小凳'],
    arrival: [6800, 4640],
    station: 'place_arrival_ice_fishing',
    node: 'arrival_ice_fishing',
    props: [
      {
        id: 'ice_fishing_stool__rest',
        definition: 'core:seat@2',
        name: '冰钓场小凳',
        at: [6700, 4740],
      },
    ],
    stations: [
      {
        id: 'slot_ice_fishing_01',
        name: '冰钓',
        at: [6880, 4760],
        activity: 'activity_fisher_catch_in_region',
        pose: 'work',
        role: 'worker',
      },
      {
        id: 'slot_ice_fishing_watch_01',
        name: '看人冰钓',
        at: [6620, 4700],
        activity: 'activity_ice_fishing_watch',
        pose: 'rest',
        role: 'visitor',
      },
    ],
  },
})
// 雪橇坡：东北林子前的一片坡地，雪橇、雪人
town.region('outdoor_sled_slope_01', '雪橇坡', 'park', blob(7050, 2350, 420, 400, 51, 0.12), {
  decor: 'clearing',
  landmark: 'sledding',
  place: {
    type: PUBLIC,
    summary: '东北林子前的一片缓坡，雪积得厚，坡上停着雪橇、堆着雪人，常有人在这里滑雪橇、打雪仗。',
    features: ['雪坡', '雪橇', '雪人', '长椅'],
    arrival: [6760, 2560],
    station: 'place_arrival_sled_slope',
    node: 'arrival_sled_slope',
    props: [
      {
        id: 'sled_slope_bench__rest',
        definition: 'core:seat@2',
        name: '雪橇坡长椅',
        at: [6880, 2540],
      },
    ],
    stations: [
      {
        id: 'slot_sled_watch_01',
        name: '看人滑雪橇',
        at: [7020, 2500],
        activity: 'activity_sled_watch',
        pose: 'rest',
        role: 'visitor',
      },
    ],
  },
})
// 雪松林步道：西边林子里一圈步道，林间一座凉亭、一张长椅（从默认图的东林公园搬）
town.region('outdoor_forest_trail_01', '雪松林步道', 'park', blob(1480, 2200, 540, 580, 52, 0.12), {
  decor: 'woods',
  landmark: 'park',
  place: {
    type: PUBLIC,
    summary: '镇子西边一片雪松林，林间一圈步道，林子中间有座压雪的凉亭，走一圈正好醒醒神。',
    features: ['雪松林', '林间步道', '凉亭', '长椅'],
    arrival: [1990, 2300],
    onRoad: 40,
    station: 'place_arrival_forest_trail',
    node: 'arrival_forest_trail',
    from: 'outdoor_east_park_01',
    at: { east_park_bench__rest: [1560, 2380] },
  },
})
// 林子：北边温泉背后的一整条林带（分几团）、东北、东边、东南、西南灯塔背后；外海小岛上也长树
// prettier-ignore
const woods = [
  ['woods_north_1', blob(1550, 1000, 650, 330, 61, 0.2)],
  ['woods_north_2', blob(3150, 1000, 420, 360, 62, 0.2)],
  ['woods_north_3', blob(5350, 850, 600, 290, 63, 0.2)],
  ['woods_north_4', blob(6450, 1050, 600, 360, 64, 0.2)],
  ['woods_cape', blob(7550, 520, 360, 200, 65, 0.22)],
  ['woods_springs_east', blob(5700, 2400, 230, 280, 67, 0.2)],
  ['woods_east', blob(7600, 3950, 240, 330, 68, 0.2)],
  ['woods_southeast', blob(5850, 5150, 380, 180, 69, 0.18)],
  ['woods_southwest', blob(1700, 5100, 480, 200, 70, 0.18)],
  ['woods_west', blob(780, 4250, 200, 180, 71, 0.2)],
]
for (const [id, shape] of woods) town.region(id, '', 'park', dry(shape), { decor: 'woods' })
ISLETS.forEach(([x, y, rx, ry, seed], k) =>
  town.region(`woods_islet_${k + 1}`, '', 'park', blob(x, y, rx * 0.65, ry * 0.6, seed, 0.15), {
    decor: 'woods',
  })
)
// prettier-ignore
const townArea = poly(smooth([
  [800, 2700], [1300, 1650], [2300, 1450], [2900, 1350], [3200, 1280], [4900, 1250], [5700, 1350],
  [6600, 1550], [7400, 1700], [7500, 2900], [7250, 3350], [7400, 4300], [7000, 4550], [6200, 4700],
  [5600, 4900], [5000, 5150], [4100, 5150], [3000, 5050], [2200, 4850], [1300, 4750], [900, 4400],
  [950, 3900], [700, 3300],
]))
town.region('outdoor_road_01', '小镇道路', 'road', dry(townArea), {
  place: {
    type: PUBLIC,
    summary:
      '连接住宅、公共建筑和户外地点的扫过雪的街道，温泉街从南入口一直通到足汤广场，居民从这里往来全镇。',
    features: [],
    arrival: [3000, 3240],
    onRoad: 40,
    station: 'place_arrival_town_roads',
    node: 'arrival_town_roads',
    from: 'outdoor_road_01',
    at: {
      小镇道路投递袋整理点__mailbag: [3046, 3310],
      小镇道路邮件分拣点__sort: [2950, 3310],
      slot_postal_collect_outgoing_mail_01: [3000, 3310],
      slot_postal_prepare_mailbag_01: [3046, 3310],
      slot_postal_sort_mail_01: [2950, 3310],
    },
  },
})

// ---- 房子：门开在南墙（灯塔开在北面，朝着岸上的小路） ----
// 温泉旅馆：前台、大堂茶席和座位，三张客床
// prettier-ignore
const inn = room(1152, 704, [
  ['inn_front_desk__guest', 'core:prop_91ab2f9d1f@1', '温泉旅馆前台', 300, 470],
  ['inn_front_desk__staff', 'core:prop_1f268c17ba@1', '温泉旅馆前台内侧', 300, 400],
  ['inn_tea_table__tea', 'core:tea-table@1', '温泉旅馆大堂茶席', 800, 470],
  ['inn_lobby_seat__rest', 'core:seat@2', '温泉旅馆大堂座位', 880, 540],
  ['inn_guest_bed_west__sleep', 'core:bed@2', '温泉旅馆客床（西）', 150, 150],
  ['inn_guest_bed_middle__sleep', 'core:bed@2', '温泉旅馆客床（中）', 880, 150],
  ['inn_guest_bed_east__sleep', 'core:bed@2', '温泉旅馆客床（东）', 1010, 150],
  ['inn_water__drink', 'core:drinking_water@1', '温泉旅馆茶水桶', 1060, 580],
], [
  ['slot_inn_receive_guests_01', '接待客人', 'activity_inn_receive_guests', 'service', 'worker', 300, 350],
  ['slot_inn_rest_lobby_01', '歇着', 'activity_inn_rest', 'rest', 'visitor', 700, 560],
])
town.building('indoor_hot_spring_inn', '温泉旅馆', 'inn', [3940, 900, 720, 440], {
  room: own(inn, 'indoor_hot_spring_inn'),
  look: { wall: 'wood', roof: BROWN },
  place: {
    type: PUBLIC,
    summary:
      '露天温泉北边、正对着池子的温泉旅馆，木头盖的两层大屋，有前台、大堂茶席和几张客床，来客可以在这里歇脚过夜。',
  },
})
// 桑拿木屋：三面长凳、一桶凉水，屋里烧着石头
// prettier-ignore
const sauna = room(960, 640, [
  ['sauna_bench_west__rest', 'core:seat@2', '桑拿木屋长凳（西）', 200, 230],
  ['sauna_bench_north__rest', 'core:seat@2', '桑拿木屋长凳（北）', 480, 150],
  ['sauna_bench_east__rest', 'core:seat@2', '桑拿木屋长凳（东）', 760, 230],
  ['sauna_water__drink', 'core:drinking_water@1', '桑拿木屋凉水桶', 820, 480],
], [
  ['slot_sauna_sweat_01', '蒸桑拿', 'activity_sauna_sweat', 'rest', 'visitor', 360, 300],
  ['slot_sauna_sweat_02', '蒸桑拿', 'activity_sauna_sweat', 'rest', 'visitor', 600, 300],
  ['slot_sauna_tend_stove_01', '添柴烧石', 'activity_sauna_tend_stove', 'work', 'worker', 150, 470],
])
town.building('indoor_sauna', '桑拿木屋', 'home', [5450, 1420, 420, 290], {
  room: own(sauna, 'indoor_sauna'),
  look: { wall: 'wood', roof: BROWN },
  place: {
    type: PUBLIC,
    summary:
      '露天温泉东边林子跟前的一间桑拿木屋，屋里烧着石头、三面长凳，烟囱一直冒着烟，蒸透了出来正好下池子。',
  },
})
// 雪见茶屋：内景照默认图的咖啡馆，咖啡机换成茶席，名字跟着改
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
town.building('indoor_flower_cafe', '雪见茶屋', 'cafe', [3750, 3420, 470, 320], {
  room: teahouse,
  look: { paint: CREAM, roof: MOSS },
  place: {
    type: SHOP,
    summary: '温泉街西侧的茶屋，窗边能看见街上的灯和雪，居民可以在这里煮茶、喝茶、吃点心和聊天。',
  },
})
town.building('indoor_market_shop', '杂货铺', 'shop', [4760, 3420, 440, 300], {
  look: { paint: RED, roof: SLATE },
  place: {
    type: SHOP,
    summary:
      '温泉街东侧、足汤广场南边的杂货铺，卖鱼货、柴火、毛线和日用杂货，居民可以在这里经营、采购和碰面。',
  },
})
town.building('indoor_dining_hall', '公共食堂', 'canteen', [3700, 4440, 540, 350], {
  place: {
    type: PUBLIC,
    summary: '温泉街西侧的公共食堂，炉火一直生着，面向全镇供餐，居民可以在这里工作、吃饭和碰面。',
  },
})
town.building('indoor_clinic', '诊所', 'clinic', [5160, 4480, 480, 340], {
  place: {
    type: PUBLIC,
    summary: '温泉街东侧、雪灯市集南边的诊所，为镇民看病和取药，医护居民可以在这里工作。',
  },
})
town.building('indoor_town_hall', '镇公所', 'townhall', [2950, 2700, 620, 410], {
  place: {
    type: PUBLIC,
    summary: '足汤广场西边坡上的镇公所，处理镇务和公共事务，居民可以在这里任职、办事和议事。',
  },
})
town.building('indoor_library', '图书馆', 'library', [5560, 2700, 540, 370], {
  look: { paint: BLUE },
  place: {
    type: PUBLIC,
    summary: '足汤广场东边坡上的图书馆，收藏和借阅书籍，居民可以在这里工作、阅读、写作和查资料。',
  },
})
town.building('indoor_dock_warehouse', '码头仓库', 'warehouse', [1180, 3620, 400, 300], {
  place: {
    type: SHOP,
    summary: '冰封渔港旁存放货物和渔具的仓库，居民可以在这里管理货物和处理渔获。',
  },
})
// 灯塔守在西南岬角：内景照默认图（塔里一张瞭望座位）
town.building('indoor_lighthouse', '灯塔', 'lighthouse', [700, 5170, 320, 320], {
  place: {
    type: PUBLIC,
    summary: '西南岬角上的灯塔，石台上立着红白相间的塔，夜里塔顶的灯扫过冰原，塔里能坐着看冰面。',
  },
})
// 住宅：三三两两散在东西两坡，大小不一；漆色按街区：西坡红和奶白，渔港一带赭黄和海蓝，
// 西南焦糖和红，东坡海蓝、奶白和松绿，东南赭黄和红；夹几户不刷漆的原木屋
// prettier-ignore
const homes = [
  ['home_01', '林边一号', [2100, 1640, 430, 290], 'painted', RED, BROWN, '雪松林步道东边、林子跟前'],
  ['home_02', '林边二号', [2680, 1560, 440, 290], 'wood', null, MOSS, '林边小路东头、露天温泉西边的林子前'],
  ['home_03', '西坡一号', [2120, 2290, 420, 280], 'painted', CREAM, SLATE, '西坡上、雪松林步道旁边'],
  ['home_04', '西坡二号', [2080, 2840, 450, 300], 'painted', RED, SLATE, '西坡下、镇公所西边'],
  ['home_05', '渔港一号', [1320, 2870, 440, 290], 'painted', OCHRE, BROWN, '渔港北边的坡上'],
  ['home_06', '渔港二号', [1700, 3660, 420, 280], 'painted', BLUE, SLATE, '码头仓库东边'],
  ['home_07', '渔港三号', [1560, 4420, 460, 300], 'wood', null, BROWN, '渔港南边、灯塔路旁'],
  ['home_08', '西街一号', [2600, 3860, 440, 290], 'painted', CARAMEL, MOSS, '温泉街西边的小街上'],
  ['home_09', '西街二号', [2380, 4470, 450, 300], 'painted', RED, SLATE, '西街南头'],
  ['home_10', '西街三号', [3020, 4560, 420, 280], 'painted', CARAMEL, BROWN, '公共食堂西边'],
  ['home_11', '东坡一号', [6150, 1640, 440, 290], 'painted', BLUE, SLATE, '东坡上、雪橇坡西边'],
  ['home_12', '东坡二号', [6420, 2780, 460, 300], 'painted', CREAM, MOSS, '图书馆东边的坡上'],
  ['home_13', '东坡三号', [5820, 3440, 430, 290], 'painted', PINE, SLATE, '杂货铺东边、东坡下'],
  ['home_14', '东湾一号', [6060, 4300, 440, 290], 'painted', OCHRE, BROWN, '东坡南头、冰钓场北边'],
  ['home_15', '东湾二号', [6900, 3820, 420, 280], 'wood', null, BROWN, '东湾边、冰钓场东北'],
]
for (const [id, name, box, wall, paint, roof, where] of homes)
  town.building(id, name, 'home', box, {
    look: { wall, roof, ...(paint ? { paint } : {}) },
    place: {
      type: '住家',
      summary: `${where}的一套独立住宅，可分配给居民居住和休息。`,
      residential: true,
    },
  })

// ---- 路 ----
// 露天温泉一圈步道：绕着四口池子，北头接旅馆门口，南头下到足汤广场；画成不太圆的一圈
const RING = [4300, 1960]
const ringPts = Array.from({ length: 19 }, (_, k) => {
  const a = (k / 18) * Math.PI * 2 - Math.PI / 2
  const wob = k % 18 === 0 ? 1 : 1 + 0.05 * Math.sin(k * 2.3) + 0.03 * Math.cos(k * 4.1)
  return [RING[0] + Math.cos(a) * 1060 * wob, RING[1] + Math.sin(a) * 600 * wob]
})
// [编号, 折线, 宽, 选项]：curve 为 false 的不平滑
// prettier-ignore
const ROADS = [
  // 温泉街：足汤广场南沿 → 南入口，中间拐两道缓弯
  ['onsen_street', [[4470, 3150], [4430, 3650], [4530, 4200], [4500, 4700], [4430, 5160]], 92],
  ['spring_loop', ringPts, 46],
  // 步道南头下到足汤广场，绕过汤池西边
  ['spring_steps', [ringPts[9], [4230, 2760], [4200, 3060], [4300, 3160]], 50],
  ['footbath_walk', [[4300, 3160], [4470, 3150]], 60, { curve: false }],
  // 桑拿木屋门前的小路接上步道东边
  ['sauna_path', [[5660, 1720], [5480, 1800], ringPts[4]], 46],
  // 上横街：渔港 → 西坡 → 镇公所前 → 足汤广场南沿 → 图书馆前 → 东坡，起伏着走
  ['upper_west', [[1000, 3330], [1500, 3270], [2100, 3300], [2750, 3230], [3300, 3230], [3900, 3200], [4300, 3160]], 64],
  ['upper_east', [[4470, 3150], [5000, 3200], [5600, 3170], [6200, 3270], [6800, 3240], [7050, 3180]], 64],
  // 林边小路：雪松林步道 → 两户林边人家门前 → 温泉步道西头
  ['west_lane', [[2000, 2060], [2400, 2010], [2900, 1990], ringPts[13]], 52],
  // 西坡路：林边小路 → 西坡人家之间 → 上横街；半坡一条小路接雪松林步道
  ['west_slope', [[2620, 2000], [2700, 2400], [2720, 2800], [2750, 3230]], 54],
  ['west_mid', [[1960, 2680], [2350, 2700], [2710, 2650]], 46],
  // 温泉街两边的小街：西边茶屋门前，东边杂货铺门前，往东接东坡人家和东湾
  ['tea_lane', [[4440, 3700], [4000, 3830], [3650, 3850]], 50],
  ['middle_east', [[4440, 3700], [5000, 3830], [5600, 3860], [6250, 3800], [6900, 4180], [7230, 4230]], 54],
  // 西街：上横街 → 西街人家 → 下横街
  ['west_street', [[2400, 3290], [2380, 3700], [2450, 4000], [2350, 4250]], 54],
  // 下横街：渔港南 → 西街 → 温泉街
  ['lower_west', [[1100, 4150], [1700, 4110], [2350, 4250], [2950, 4280], [3500, 4210], [4000, 4230], [4520, 4230]], 58],
  // 南街：灯塔路 → 西南人家、食堂门前 → 温泉街 → 诊所门前 → 冰钓场
  ['south_lane', [[1200, 4700], [1900, 4900], [2500, 4920], [3100, 4960], [3700, 4930], [4000, 4950], [4480, 4950]], 54],
  ['lower_east', [[4480, 4950], [5100, 4990], [5750, 4930], [6250, 4740], [6620, 4660], [6800, 4640]], 58],
  // 东坡：温泉步道东头 → 东坡人家门前 → 雪橇坡；东坡路往下接上横街
  ['east_lane', [ringPts[5], [5900, 2070], [6400, 2060], [6760, 2560]], 52],
  ['east_slope', [[6400, 2060], [6250, 2600], [6200, 3270]], 54],
  // 渔港路、灯塔路
  ['harbor_road', [[1000, 3330], [880, 3420], [820, 3480]], 56],
  ['harbor_south', [[1000, 3330], [1080, 3700], [1100, 4150]], 54],
  ['lighthouse_road', [[1100, 4150], [1200, 4700], [1050, 5000], [860, 5110]], 50],
  // 雪松林步道：林间一圈，东头接林边小路和半坡小路
  ['forest_loop', [[1990, 2300], [1960, 2680], [1450, 2780], [1040, 2560], [960, 2100], [1200, 1700], [1650, 1620], [2000, 2060], [1990, 2300]], 46],
]
for (const [id, pts, width, options] of ROADS) town.road(id, pts, width, options)

const doc = seal(town.build())
// 按层缩进，坐标对（格子、折线上的点）各占一行，和默认地图一样的写法，改了好比对
const text = JSON.stringify(doc, null, 2).replace(/\[\s+(-?[\d.]+),\s+(-?[\d.]+)\s+\]/g, '[$1, $2]')
const out = arg('--out') ?? fileURLToPath(FILE)
fs.mkdirSync(path.dirname(out), { recursive: true })
fs.writeFileSync(out, text + '\n')
console.log(
  `${doc.layout.spaces.length} 栋房子、${doc.topology.places.length} 处地点、${doc.layout.edges.length} 段路、` +
    `${doc.topology.props.length} 件道具`
)
