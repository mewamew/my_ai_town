// 默认地图「我的小镇」：河口双桥。一条河从西北的湖里流出来，横穿镇子，拐进南岸的小港湾、从窄口出海；
// 北岸是老城（镇公所、图书馆、诊所），南岸是广场、市集和人家，主街石拱桥、西边和下游两座木板桥连起两岸。
// 海岸是画好的天然海岸（北湾、东北带钩的岬角、西湾、南边到灯塔的月牙沙滩，外海三座小岛），交给引擎扭曲冲刷。
// 房子门都开在南墙、前低后高；屋顶按街区配色：北岸灰蓝石板瓦，南岸陶土红和蜂蜜黄。
// 房子的内景、户外地点的道具和落脚点按编号从现在的默认地图搬（第一次是从旧的默认地图搬过来的），改了设计重新跑：
//   node scripts/maps/default-town.mjs        写 data/maps/2d-town/map.json（封好摘要；--out 另写一处）
//   target/debug/town-map validate < data/maps/2d-town/map.json
import fs from 'node:fs'
import { seal } from '../mapgen/document.mjs'
import {
  arc,
  band,
  blob,
  circle,
  ellipse,
  minus,
  poly,
  rect,
  smooth,
  townMap,
  union,
} from './townmap.mjs'

const FILE = new URL('../../data/maps/2d-town/map.json', import.meta.url)
// --source 换内景来源，--out 换输出（调设计时不动正式文件）
const arg = (name) => {
  const i = process.argv.indexOf(name)
  return i > 0 ? process.argv[i + 1] : undefined
}
const source = JSON.parse(fs.readFileSync(arg('--source') ?? FILE, 'utf8'))

// 屋顶三色（亮、中、暗）：南岸暖色，北岸、东岸冷色
const TERRACOTTA = { roof: ['#bd6446', '#a3533a', '#7c3d2b'] }
const OCHRE = { roof: ['#c99550', '#ad7d40', '#80592c'], roofing: 'shingle' }
const SLATE = { roof: ['#647487', '#536173', '#3d4755'], roofing: 'slate' }
const MOSS = { roof: ['#667f56', '#566d49', '#405236'] }
const CHARCOAL = { roof: ['#555a63', '#474b53', '#34373d'], roofing: 'slate' }

const W = 8200,
  H = 5800
const town = townMap({
  id: '2d-town',
  name: '我的小镇',
  description: source.description,
  width: W,
  height: H,
  source,
  roads: 'outdoor_road_01',
})

// ---- 地形 ----
// 底稿海岸：西北湖岬、北湾、东北长岬、东岬（东林公园）、东南角、河口两岸、南边镇口小岬、西南海滨湾、西岬
// prettier-ignore
const coast = smooth(
  [
    [330, 1250], [420, 820], [760, 470], [1250, 300], [1750, 330], [2150, 470], [2550, 390],
    [3000, 260], [3600, 230], [4150, 300], [4480, 430], [4720, 700], [5000, 880], [5300, 860],
    [5560, 620], [5780, 380], [6150, 250], [6700, 230], [7250, 130], [7750, 40], [8150, 80],
    [8340, 300], [8250, 560], [8030, 600], [7860, 720], [7700, 980], [7650, 1250], [7900, 1650],
    [7850, 2050], [7650, 2350], [7800, 2700], [8080, 3050], [8150, 3550], [8000, 4050],
    [7850, 4450], [7900, 4850], [7700, 5200], [7300, 5420], [6850, 5420], [6500, 5300],
    [6300, 5450], [5950, 5480], [5650, 5560], [5330, 5420], [5050, 5120], [4700, 5000],
    [4350, 5100], [4120, 5400], [3800, 5660], [3450, 5560], [3150, 5420], [2750, 5380],
    [2350, 5520], [1900, 5560], [1450, 5520], [1050, 5380], [700, 5120], [520, 4800], [470, 4450],
    [330, 4100], [380, 3700], [520, 3350], [430, 3050], [520, 2800], [600, 2600], [470, 2400],
    [220, 2200], [130, 1950], [260, 1700], [380, 1500], [330, 1250],
  ],
  50
)
// 外海的小岛：西南海滨外一座、东北长岬外一座、西边一座小的（岛上种林子，不然会被当成礁石）
const ISLETS = [
  [1000, 5900, 260, 150, 3],
  [8050, 1050, 170, 120, 7],
  [-60, 2650, 160, 110, 11],
]
const islets = ISLETS.map(([x, y, rx, ry, seed]) => blob(x, y, rx, ry, seed, 0.22))
const lake = blob(1650, 1450, 560, 330, 5, 0.12)
const RIVER = 300
// prettier-ignore
const riverLine = [
  [2150, 1560], [2800, 1830], [3600, 2020], [4500, 2030], [5300, 2120], [5780, 2420],
  [6060, 2950], [6180, 3550], [6240, 4330],
]
const river = band(riverLine, RIVER)
// 港湾偏在河西岸、码头这一边（东岸不挖，不然从上往下看水面成十字），湾口窄
const basin = blob(5960, 4600, 430, 340, 9, 0.12)
// prettier-ignore
const neck = poly(
  smooth([
    [6010, 4880], [6250, 4880], [6280, 5250], [6330, 5800], [5950, 5800], [5990, 5250],
  ])
)
// 东林公园林间草地上的小池塘，凉亭立在北岸
const pond = blob(7130, 3790, 230, 130, 13, 0.12)
const water = union(lake, river, basin, neck, pond)
town.island(union(poly(coast), ...islets), water, {
  coast: 1,
  bay: 12,
  warp: 26,
  erosion: 46,
  rim: 4,
})
const dry = (shape) => minus(shape, water)

// ---- 区域（先登记的先占格子；没有名字的只管样子） ----
// 喷泉在广场正中，先占；港口压着港湾西沿，朝东临水
town.region('outdoor_fountain_01', '喷泉', 'fountain', circle(3800, 2560, 115), {
  place: {
    type: '公共地点',
    summary: '中心广场正中的石砌喷泉，池边一圈石沿可以坐，居民常在这里歇脚、约人和看水。',
    features: ['喷泉水池', '石沿'],
    arrival: [3800, 2650],
    station: 'place_arrival_fountain',
    node: 'arrival_fountain',
    props: [
      {
        id: 'fountain_rim_seat__rest',
        definition: 'core:seat@2',
        name: '喷泉石沿座位',
        at: [3730, 2620],
      },
    ],
  },
})
town.region('outdoor_harbor_01', '渔港', 'harbor', rect(5400, 4200, 380, 560), {
  facing: [1, 0],
  place: {
    type: '公共地点',
    summary:
      '河口小港湾西岸的木码头，栈桥伸进湾里泊着渔船，码头上放着货箱和木桶，居民会在这里处理货物、渔具和渔获。',
    features: ['木码头', '栈桥', '泊船', '货箱', '木桶'],
    arrival: [5480, 4560],
    station: 'place_arrival_fishing_harbor',
    node: 'arrival_fishing_harbor',
    from: 'outdoor_harbor_01',
    at: {
      渔港渔具整理点__gear: [5440, 4400],
      渔港渔获清点处__catch: [5500, 4360],
      slot_fisher_catch_in_region_01: [5500, 4470],
      slot_fisher_count_catch_01: [5500, 4380],
      slot_fisher_organize_gear_01: [5440, 4420],
    },
  },
})
town.region('outdoor_plaza_01', '中心广场', 'plaza', dry(rect(3300, 2260, 1000, 600)), {
  place: {
    type: '公共地点',
    summary:
      '镇子正中、石桥南头的石板广场，中间立着喷泉，四周有公告栏、花坛和路灯，居民可以在这里碰面、驻足和集合。',
    features: ['喷泉', '公告栏', '花坛', '路灯'],
    arrival: [3800, 2790],
    onRoad: 40,
    station: 'place_arrival_central_plaza',
    node: 'arrival_central_plaza',
    from: 'outdoor_plaza_01',
    at: {
      中心广场公告栏张贴处__post_right: [3488, 2400],
      中心广场公告栏阅读处__read_left: [3420, 2400],
      中心广场报纸叫卖点__sell: [4120, 2420],
      中心广场报纸整理点__papers: [4192, 2420],
      中心广场排练点__rehearse: [3460, 2700],
      中心广场演奏点__perform: [4130, 2700],
      slot_bulletin_publish_01: [3488, 2400],
      slot_bulletin_read_01: [3420, 2400],
      slot_musician_perform_01: [4060, 2690],
      slot_musician_rehearse_01: [3520, 2690],
    },
  },
})
// 城里那一段河的两岸铺石砌河堤
town.region('quay', '', 'plaza', dry(band(riverLine.slice(1, 6), RIVER + 170)))
town.region('outdoor_market_01', '市集', 'market', dry(rect(4420, 2330, 540, 380)), {
  place: {
    type: '公共地点',
    summary:
      '中心广场东侧、挨着河堤的露天摊位，摆着货架、木桶和不同颜色的棚铺，居民会来这里逛摊、买东西和碰面。',
    features: ['露天摊位', '货架', '木桶'],
    arrival: [4690, 2390],
    station: 'place_arrival_market',
    node: 'arrival_market',
    from: 'outdoor_market_01',
  },
})
town.region('outdoor_south_gate_01', '南入口', 'gate', rect(3650, 5150, 300, 260), {
  place: {
    type: '公共地点',
    summary: '主街南头通向镇外的入口，往东是一弯沙滩连到灯塔，居民会在这里迎送和等待来客。',
    features: ['入口台阶', '路灯'],
    arrival: [3800, 5260],
    station: 'place_arrival_south_entrance',
    node: 'arrival_south_entrance',
    from: 'outdoor_south_gate_01',
  },
})
town.region('outdoor_garden_01', '社区花园', 'garden', ellipse(3200, 4250, 340, 220), {
  place: {
    type: '公共地点',
    summary: '主街西侧、南街人家旁边围着花树和长椅的公共花园，适合散步、赏花和休息。',
    features: ['花圃', '花树', '长椅', '路灯'],
    arrival: [3170, 4160],
    station: 'place_arrival_community_garden',
    node: 'arrival_community_garden',
    from: 'outdoor_garden_01',
    at: {
      slot_botanist_observe_plants_01: [3060, 4200],
      slot_farm_tidy_tools_01: [3340, 4120],
      slot_farm_water_beds_01: [3280, 4160],
      slot_garden_harvest_region_01: [3200, 4320],
    },
  },
})
// 公园：环湖公园（湖心凉亭）、海滨公园和街心绿地（草坪多、树稀，各有看台和旋转木马）、东林公园（林子）
town.region('outdoor_river_park_01', '河岸公园', 'park', dry(ellipse(1650, 1450, 860, 600)), {
  place: {
    type: '公共地点',
    summary: '镇子西北环湖的公园，河从湖里流出来；一圈步道绕着湖，湖心有座凉亭，图书馆就在旁边。',
    features: ['湖', '环湖步道', '湖心凉亭', '长椅'],
    arrival: [1650, 1949],
    onRoad: 40,
    station: 'place_arrival_riverbank_park',
    node: 'arrival_riverbank_park',
    from: 'outdoor_river_park_01',
    at: {
      河岸公园长椅__seat: [1560, 1880],
      slot_river_bench_rest_01: [1560, 1880],
      slot_musician_rehearse_river_01: [1760, 1880],
    },
  },
})
town.region('pocket_carousel', '', 'carousel', circle(1500, 3300, 110))
// 海滨公园：一大片草坪，北边两丛树框住；看台坐在南边伸进海里的岬角上、朝海敞开，
// 步道绕草坪一圈，南边那半圈贴着海走、从看台前面过
const STAND = { at: [1800, 5320], size: 300 }
// 贴着海的那半圈步道铺石板
// prettier-ignore
const SEA_FRONT = [[1040, 4800], [1180, 5080], [1420, 5330], [1800, 5520], [2160, 5370], [2330, 5080], [2350, 4800]]
town.region('seaside_promenade', '', 'plaza', band(SEA_FRONT.slice(1, -1), 110))
town.region('seaside_grove_west', '', 'park', blob(1130, 4560, 260, 170, 31, 0.2), {
  decor: 'woods',
})
town.region('seaside_grove_east', '', 'park', blob(2280, 4520, 240, 160, 32, 0.2), {
  decor: 'woods',
})
town.region(
  'outdoor_seaside_park_01',
  '海滨公园',
  'park',
  union(ellipse(1700, 4800, 820, 420), circle(...STAND.at, STAND.size)),
  {
    decor: 'lawn',
    label: [1640, 4700],
    place: {
      type: '公共地点',
      summary:
        '西南海边的一大片草坪，环形步道绕一圈、南边贴着海走；岬角上一座朝海的石砌看台，几级台阶围着小舞台，傍晚常有人坐着看海。',
      features: ['草坪', '环形步道', '朝海看台', '小舞台'],
      arrival: [1050, 4800],
      onRoad: 40,
      station: 'place_arrival_seaside_park',
      node: 'arrival_seaside_park',
      props: [
        {
          id: 'seaside_stand_seat__rest',
          definition: 'core:seat@2',
          name: '海滨公园看台座位',
          at: [1800, 5160],
        },
      ],
    },
  }
)
town.standee('court', STAND.at, { size: STAND.size })
// 只给画面看的小摆设：步道边朝海的长椅、两个入口的花箱、岬角上朝海的望远镜、两边小沙滩上的遮阳伞
// prettier-ignore
const SEASIDE_PIECES = {
  bench: [[1235, 5090], [1420, 5250], [2210, 5235], [2300, 5000], [1480, 4505], [1930, 4495]],
  planter: [[960, 4740], [1110, 4890], [2420, 4740], [2290, 4880]],
  telescope: [[1880, 5585]],
  parasol: [[1190, 5360], [2470, 5262], [2600, 5290]],
}
for (const [kind, spots] of Object.entries(SEASIDE_PIECES))
  for (const at of spots) town.standee(kind, at)
town.region('outdoor_pocket_park_01', '街心绿地', 'park', rect(820, 3150, 1450, 330), {
  decor: 'lawn',
  place: {
    type: '公共地点',
    summary: '西街人家中间的一块草地，有一座旋转木马和长椅，住在附近的人出门就到。',
    features: ['草地', '旋转木马', '长椅'],
    arrival: [1137, 3397],
    onRoad: 40,
    station: 'place_arrival_pocket_park',
    node: 'arrival_pocket_park',
    props: [
      {
        id: 'pocket_park_bench__rest',
        definition: 'core:seat@2',
        name: '街心绿地长椅',
        at: [1700, 3250],
      },
    ],
  },
})
// 东林公园：过下游的小木桥进林子，环路绕着林子中间一片草地，草地上一口小池塘，凉亭立在北岸
town.region('outdoor_east_park_01', '东林公园', 'park', dry(blob(7110, 3800, 430, 350, 33, 0.12)), {
  decor: 'lawn',
  label: [6850, 3540],
  place: {
    type: '公共地点',
    summary:
      '过下游的小木桥就是东边的林子，林间一条环路，林子中间一片草地，草地上有口小池塘，凉亭立在池塘北岸。',
    features: ['树林', '林间环路', '林间草地', '池塘', '凉亭', '长椅'],
    arrival: [6780, 3700],
    onRoad: 40,
    station: 'place_arrival_east_park',
    node: 'arrival_east_park',
    props: [
      {
        id: 'east_park_bench__rest',
        definition: 'core:seat@2',
        name: '东林公园长椅',
        at: [6880, 3820],
      },
    ],
  },
})
town.region('woods_east_park', '', 'park', dry(ellipse(7080, 3700, 640, 840)), { decor: 'woods' })
town.standee('park', [7130, 3672])
// 池边的芦苇和石头、木桥头的指路牌、草地边的长椅
// prettier-ignore
const EAST_PARK_PIECES = {
  reeds: [[6905, 3820], [7355, 3760], [7020, 3930], [7250, 3925]],
  rock: [[6950, 3895], [7330, 3850], [6930, 3720]],
  signpost: [[6615, 3500]],
  bench: [[7345, 3640], [6900, 3690]],
}
for (const [kind, spots] of Object.entries(EAST_PARK_PIECES))
  for (const at of spots) town.standee(kind, at)
// 林子：北岸背后三团、东北长岬、东边、东南角、河口东岸；小岛上也长树
const woods = [
  ['woods_north_1', blob(3150, 700, 650, 260, 21, 0.2)],
  ['woods_north_2', blob(4150, 720, 420, 230, 22, 0.2)],
  ['woods_north_3', blob(6400, 900, 820, 330, 23, 0.2)],
  ['woods_cape', blob(7600, 560, 480, 260, 24, 0.22)],
  ['woods_southeast', blob(7150, 4950, 560, 360, 25, 0.18)],
  ['woods_mouth', blob(6560, 5250, 260, 230, 27, 0.15)],
  ['woods_east', blob(7300, 2250, 330, 380, 26, 0.2)],
]
for (const [id, shape] of woods) town.region(id, '', 'park', dry(shape), { decor: 'woods' })
ISLETS.forEach(([x, y, rx, ry, seed], k) =>
  town.region(`woods_islet_${k + 1}`, '', 'park', blob(x, y, rx * 0.65, ry * 0.6, seed, 0.15), {
    decor: 'woods',
  })
)
// 河边柳树、主街行道树
town.region(
  'willows_north',
  '',
  'park',
  dry(
    band(
      [
        [4300, 1530],
        [5200, 1600],
      ],
      90
    )
  ),
  { decor: 'allee' }
)
town.region(
  'willows_south',
  '',
  'park',
  dry(
    band(
      [
        [2650, 2420],
        [3150, 2420],
      ],
      90
    )
  ),
  { decor: 'allee' }
)
town.region('allee_west', '', 'park', rect(3600, 3000, 90, 680), { decor: 'allee' })
town.region('allee_east', '', 'park', rect(3910, 3000, 90, 680), { decor: 'allee' })
// prettier-ignore
const townArea = poly(smooth([
  [700, 2200], [1500, 2150], [2500, 1700], [2600, 1000], [3300, 1050], [4200, 1020], [4700, 1000],
  [5700, 1150], [6300, 1300], [7050, 1650], [7150, 2050], [6900, 2850], [6400, 3300], [6350, 4100],
  [5500, 4950], [5000, 4870], [4400, 4880], [4000, 5050], [3200, 4950], [2600, 4450], [1700, 4250],
  [900, 4350], [650, 3600], [700, 2750],
]))
town.region('outdoor_road_01', '小镇道路', 'road', dry(townArea), {
  place: {
    type: '公共地点',
    summary:
      '连接住宅、公共建筑和户外活动区域的街道与桥面，主街过石拱桥通到镇公所，居民从这里往来全镇。',
    features: [],
    arrival: [2450, 2901],
    onRoad: 40,
    station: 'place_arrival_town_roads',
    node: 'arrival_town_roads',
    from: 'outdoor_road_01',
    at: {
      小镇道路投递袋整理点__mailbag: [2496, 2836],
      小镇道路邮件分拣点__sort: [2400, 2836],
      slot_postal_collect_outgoing_mail_01: [2450, 2836],
      slot_postal_prepare_mailbag_01: [2496, 2836],
      slot_postal_sort_mail_01: [2400, 2836],
    },
  },
})

// ---- 房子：门开在南墙（灯塔开在北面，朝着港边小路） ----
const PUBLIC = '公共地点',
  SHOP = '铺面'
// 北岸老城：公所正对石桥，西边图书馆挨着环湖公园，东边诊所
town.building('indoor_town_hall', '镇公所', 'townhall', [3480, 960, 640, 420], {
  place: {
    type: PUBLIC,
    summary: '北岸正对石拱桥的镇公所，处理镇务和公共事务，居民可以在这里任职、办事和议事。',
  },
})
town.building('indoor_library', '图书馆', 'library', [2560, 1010, 560, 380], {
  place: {
    type: PUBLIC,
    summary:
      '北岸西头、挨着河岸公园的图书馆，收藏和借阅书籍，居民可以在这里工作、阅读、写作和查资料。',
  },
})
town.building('indoor_clinic', '诊所', 'clinic', [4600, 1060, 500, 360], {
  place: { type: PUBLIC, summary: '北岸东边的诊所，为镇民看病和取药，医护居民可以在这里工作。' },
})
// 南岸：广场西边咖啡馆，东边市集、杂货铺；食堂在主街；工作坊和码头仓库顺着下游
town.building('indoor_flower_cafe', '花房咖啡馆', 'cafe', [2760, 2470, 440, 320], {
  place: {
    type: SHOP,
    summary: '中心广场西边、临河的咖啡馆，带玻璃花房，居民可以在这里工作、喝东西、休息和聊天。',
  },
})
town.building('indoor_dining_hall', '公共食堂', 'canteen', [4100, 3180, 520, 340], {
  place: {
    type: PUBLIC,
    summary: '主街东侧、广场南边的公共食堂，面向全镇供餐，居民可以在这里工作、吃饭和碰面。',
  },
})
town.building('indoor_market_shop', '杂货铺', 'shop', [5040, 2560, 440, 300], {
  place: {
    type: SHOP,
    summary:
      '市集东边的杂货铺，铺里摆着鱼货、鲜花和日用杂货的摊子，居民可以在这里经营、采购和碰面。',
  },
})
town.building('indoor_workshop', '工作坊', 'workshop', [5180, 3080, 440, 330], {
  place: {
    type: SHOP,
    summary: '南岸下游河边的工坊，制作和修理器物，居民可以在这里经营铺面和从事手工工作。',
  },
})
town.building('indoor_dock_warehouse', '码头仓库', 'warehouse', [4860, 4260, 480, 360], {
  place: { type: SHOP, summary: '渔港旁存放货物和渔具的仓库，居民可以在这里管理货物和处理渔获。' },
})
// 灯塔守在港湾口西边：内景是新的，塔里一张瞭望座位
town.building('indoor_lighthouse', '灯塔', 'lighthouse', [5600, 5090, 320, 320], {
  room: {
    bounds: { x: 0, y: 0, width: 640, height: 640 },
    door: [320, 48],
    props: [
      {
        id: 'lighthouse_lookout_seat__rest',
        definition: 'core:seat@2',
        name: '灯塔瞭望座位',
        locale: 'indoor_lighthouse',
        mark: {
          id: 'lighthouse_lookout_seat__rest',
          x: 420,
          y: 360,
          name: '灯塔瞭望座位',
          appearance: { glyph: 'box', color: '#b79a70' },
        },
      },
    ],
    stations: [],
  },
  place: {
    type: PUBLIC,
    summary: '港湾口西边的灯塔，石台上立着红白相间的塔，夜里塔顶的灯照着出海口，塔里能坐着看海。',
  },
})
// 住宅：北岸、东岸灰蓝石板瓦和苔绿，南岸陶土红和蜂蜜黄；名字按位置起
const homes = [
  ['home_01', '北岸一号', [5380, 1150, 450, 300], SLATE, 'brick', '北岸诊所东边'],
  ['home_02', '北岸二号', [6060, 1420, 440, 290], CHARCOAL, 'plaster', '北岸东头临河'],
  ['home_03', '林边一号', [6700, 1720, 440, 290], SLATE, 'brick', '东边林子跟前'],
  ['home_04', '林边二号', [6650, 2420, 440, 290], MOSS, 'wood', '东边林子南头、河湾东岸'],
  ['home_05', '林间小屋', [7000, 4560, 420, 280], MOSS, 'wood', '东林公园南边林子里'],
  ['home_06', '湖畔一号', [1080, 2280, 440, 290], OCHRE, 'wood', '河岸公园南边湖畔'],
  ['home_07', '湖畔二号', [1700, 2350, 450, 300], TERRACOTTA, 'plaster', '河岸公园南边湖畔'],
  ['home_08', '西街一号', [900, 3500, 440, 290], OCHRE, 'plaster', '西街北头、街心绿地南边'],
  ['home_09', '西街二号', [1560, 3500, 450, 300], TERRACOTTA, 'brick', '西街中段、街心绿地南边'],
  ['home_10', '西街三号', [2250, 3500, 440, 290], OCHRE, 'wood', '西街东头、街心绿地南边'],
  ['home_11', '河街一号', [2950, 3250, 440, 290], TERRACOTTA, 'plaster', '主街西侧、咖啡馆南边'],
  ['home_12', '南街一号', [2350, 4250, 440, 290], TERRACOTTA, 'plaster', '社区花园西边'],
  ['home_13', '南街二号', [4350, 3750, 440, 290], OCHRE, 'plaster', '主街东侧、公共食堂南边'],
  ['home_14', '南街三号', [4250, 4300, 440, 290], TERRACOTTA, 'wood', '主街东侧、码头仓库西边'],
  ['home_15', '港边一号', [5150, 3700, 440, 290], OCHRE, 'wood', '下游西岸、渔港北边'],
]
for (const [id, name, box, roof, wall, where] of homes)
  town.building(id, name, 'home', box, {
    look: { ...roof, wall },
    place: {
      type: '住家',
      summary: `${where}的一套独立住宅，可分配给居民居住和休息。`,
      residential: true,
    },
  })

// ---- 路 ----
// [编号, 折线, 宽, 选项]：curve 为 false 的不平滑，bridge 是跨水时的桥
// prettier-ignore
const ROADS = [
  // 主街：南入口 → 中心广场（绕喷泉一圈）→ 石拱桥 → 镇公所
  ['main_south', [[3800, 5150], [3800, 2730]], 96, { curve: false }],
  ['plaza_ring', arc(3800, 2560, 170, 170, 90, 450, 32), 60, { curve: false }],
  ['main_north', [[3800, 2390], [3800, 1420]], 96, { curve: false, bridge: 'stone' }],
  // 广场北沿临河一条步道，接两岸的沿河街
  ['quay_walk', [[3290, 2260], [4310, 2260]], 68, { curve: false }],
  // 北岸沿河街，背后一条小巷串起东头的人家
  ['north_bank', [[2300, 1360], [3000, 1560], [3800, 1660], [4600, 1690], [5300, 1770], [5800, 1980], [6350, 2350], [6700, 2850]], 68],
  ['north_lane', [[5100, 1745], [5350, 1560], [5700, 1540], [6050, 1790], [6400, 1820], [6620, 2080], [7100, 2090]], 52],
  // 南岸沿河街：西段从木板桥南头到广场，东段从广场顺着下游西岸一直到港湾
  ['south_bank_west', [[2450, 1990], [2700, 2180], [3000, 2250], [3290, 2260]], 68],
  ['south_bank_east', [[4310, 2260], [5000, 2300], [5520, 2460], [5800, 2950], [5900, 3550], [5880, 4150]], 68],
  // 木板桥（西，也是环湖步道过河的地方）、下游小木桥（通东林）
  ['wood_bridge', [[2450, 1400], [2450, 1990]], 56, { curve: false, bridge: 'wood' }],
  ['foot_bridge', [[5900, 3550], [6560, 3550]], 50, { curve: false, bridge: 'wood' }],
  // 南岸的横街：北横街接市集街，食堂街，南横街；西街；南街从海滨公园一直到灯塔
  ['cross_north', [[650, 2900], [1500, 2860], [2400, 2900], [3800, 2900]], 64],
  ['market_street', [[3800, 2900], [4300, 2940], [5000, 2940], [5795, 2950]], 60],
  ['canteen_street', [[3800, 3610], [4600, 3610], [5300, 3600], [5900, 3550]], 56],
  ['cross_south', [[650, 3880], [1500, 3870], [2500, 3860], [3800, 3880], [4300, 4110], [4900, 4130], [5880, 4140]], 64],
  ['west_street', [[650, 2900], [650, 3880], [800, 4500]], 56],
  ['south_street', [[2350, 4800], [2900, 4700], [3400, 4720], [3800, 4760], [4600, 4760], [5250, 4800], [5560, 4980], [5700, 5060]], 60],
  // 环湖步道（让开出水口，过河走木板桥）、海滨公园步道、东林环线、街心绿地的小路
  ['lake_loop', arc(1650, 1450, 760, 500, 50, 350, 34), 50, { curve: false }],
  ['lake_north', [[2300, 1360], [2450, 1400]], 50, { curve: false }],
  ['lake_south', [[2138, 1833], [2300, 1950], [2450, 1990]], 50],
  // 海滨公园：北半圈沿着草坪北沿，南半圈贴着海、从看台前面过
  ['sea_north', [[1040, 4800], [1180, 4560], [1500, 4440], [1900, 4430], [2230, 4560], [2350, 4800]], 50],
  ['sea_front', SEA_FRONT, 56],
  ['sea_in', [[800, 4500], [1040, 4800]], 50, { curve: false }],
  // 东林环线绕着林间草地；北边接河湾东岸，南边下到林间小屋
  ['east_loop', arc(7110, 3720, 580, 570, 0, 360, 44), 50, { curve: false }],
  ['east_north', [[6700, 2850], [6950, 3000], [7110, 3150]], 56],
  ['east_south', [[7110, 4290], [6960, 4470], [6880, 4700], [6950, 4900], [7200, 4910]], 50],
  ['pocket_path', [[650, 3300], [900, 3320], [1300, 3440], [1700, 3440], [2200, 3300]], 46],
]
for (const [id, pts, width, options] of ROADS) town.road(id, pts, width, options)

const doc = seal(town.build())
// 按层缩进，坐标对（格子、折线上的点）各占一行，和原来的文件差不多大，改了好比对
const text = JSON.stringify(doc, null, 2).replace(/\[\s+(-?[\d.]+),\s+(-?[\d.]+)\s+\]/g, '[$1, $2]')
fs.writeFileSync(arg('--out') ?? FILE, text + '\n')
console.log(
  `${doc.layout.spaces.length} 栋房子、${doc.topology.places.length} 处地点、${doc.layout.edges.length} 段路、` +
    `${doc.topology.props.length} 件道具`
)
