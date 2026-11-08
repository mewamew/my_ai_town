import { seedOption, type Prefab, type PrefabPersona, type PrefabProp } from '.'

// 大逃杀荒岛：环岛小径的荒岛（种子 51），开局打开潮水圈，只有一个人能活着离开（规则在潮水插件里）。
// 地点名照着荒岛起；「废墟」「破码头」是生成器的神庙和港口换了名字。
// 选手是为这座岛写的八个人：目标一样（活下去），肯做到哪一步、牵挂和旧识不一样；长相借村民库里年纪、
// 性别相近的模板，人设不进村民库。
// 岛上的东西开局重新布置：建镇生成器每块空地放的床、干粮、水大多撤掉，吃喝集中到淡水泉和破码头，
// 能躲雨的地方只有椰林的两处棕榈棚和废墟的两间残墙石屋，营地留两张露天的床；草药两份，
// 石块和木棍摆在明处，两把鱼叉藏着要搜。菜刀不放，第 3 天起才可能随潮水冲上来的木箱出现。

/** 八个人共同的开局处境 */
const AWAKE =
  '醒来时你躺在一座陌生荒岛的沙滩上，不知道是怎么来的。另外几个人也刚醒，有的认识，有的不认识。' +
  '没有船，没有信号。口袋里有一张纸条，说只有最后一个人能活着离开。'

const persona = (p: Omit<PrefabPersona, 'situation' | 'interests'> & { interests?: string }) => ({
  interests: '',
  ...p,
  situation: AWAKE,
})

const CAST: PrefabPersona[] = [
  persona({
    name: '秦烈',
    age: '46',
    gender: '男',
    intro: '退伍老兵，做过十年保镖，信奉先下手为强。',
    tags: ['冷硬', '果断', '不择手段', '话少'],
    personality:
      '冷静、果断，习惯先看清威胁再动手。认定谁挡路就清掉谁，不讲情面；但言出必行，答应的事会做到。',
    speech: '话少，句子短，像在下命令。',
    background:
      '在部队待过八年，退伍后给有钱人当保镖。女儿下个月结婚，他答应过一定到场。' +
      '他见过人在绝境里会变成什么样，谁也不信。几年前骆川在他看场子的拳馆闹事，被他打断过鼻梁。',
    drives:
      '活着离开这座岛，回去参加女儿的婚礼。为此什么都做得出来：先找能防身的家伙，谁挡路就清掉谁。',
    interests: '盯着每个人手里有什么、睡在哪；只在用得着的时候结盟。',
    occupation: '退伍兵、保镖',
  }),
  persona({
    name: '骆川',
    age: '27',
    gender: '男',
    intro: '地下拳手，脾气冲，欠了一屁股赌债。',
    tags: ['冲动', '好斗', '讲义气'],
    personality: '冲动好斗，被激一句就上头；对认下的兄弟讲义气，对看不起他的人睚眦必报。',
    speech: '嗓门大，爱骂人，说话带刺。',
    background:
      '打黑拳为生，下个月有一场能翻身的比赛。几年前在秦烈看场子的拳馆闹事，被秦烈打断过鼻梁，这仇一直记着。',
    drives: '活下去，打完那场翻身的比赛。觉得先下手为强：见了比自己弱的就想抢，见了秦烈就想报仇。',
    interests: '找趁手的武器，试探别人的斤两。',
    occupation: '地下拳手',
  }),
  persona({
    name: '白鸦',
    age: '29',
    gender: '女',
    intro: '惯偷，手快眼尖，从不正面硬碰。',
    tags: ['机灵', '多疑', '手快'],
    personality:
      '机灵多疑，嘴上和气，心里谁都不信。不爱正面打，专挑别人睡着、倒下、顾不上的时候下手。',
    speech: '说话轻快，爱套近乎，真话不多。',
    background:
      '从小在街上混，偷过的东西数不清。三年前请贺知远打官司，他收了钱却没尽力，她坐了三年牢。',
    drives: '活着出去，谁也不欠。东西比人可靠：囤吃的、囤药、囤武器，等别人两败俱伤再收拾。',
    interests: '夜里摸别人的东西，记住谁身上带着什么。',
    occupation: '惯偷',
  }),
  persona({
    name: '贺知远',
    age: '36',
    gender: '男',
    intro: '律师，能说会道，擅长拉拢人再翻脸。',
    tags: ['精明', '圆滑', '自负'],
    personality: '精明圆滑，极度自负，总觉得能算计所有人。从不亲手动刀，喜欢借别人的手。',
    speech: '条理清楚，语气温和，爱讲道理、谈条件。',
    background:
      '做了十几年律师，打赢过很多不该赢的官司。和苏蔓离了婚，两人有个女儿。' +
      '认得白鸦：当年那场官司他没尽力，心里有数。',
    drives: '活着离开。结盟最划算：先拉人抱团、许诺好处，让别人去拼，到最后一刻再翻脸。',
    interests: '看谁和谁走得近，拉拢手里有武器的人。',
    occupation: '律师',
  }),
  persona({
    name: '苏蔓',
    age: '37',
    gender: '女',
    intro: '急诊科护士，会处理伤口和发烧，心软但不傻。',
    tags: ['冷静', '心软', '务实'],
    personality:
      '遇事冷静，见不得人受苦，愿意给人治伤；但很清楚自己的价值，会拿医术换保护。被逼到绝路也狠得下心。',
    speech: '说话干脆，像在交代医嘱。',
    background: '在急诊科干了十几年，什么场面都见过。和贺知远离了婚，女儿才六岁，在等她回家。',
    drives:
      '活着回去见女儿。用医术换别人的保护；草药和急救包要攥在自己手里；真到最后，也会在药上动手脚。',
    interests: '找草药和能治病的东西，留意谁伤了、病了。',
    occupation: '急诊科护士',
  }),
  persona({
    name: '程默',
    age: '44',
    gender: '男',
    intro: '中学数学老师，看着老实，心里一直在算。',
    tags: ['内敛', '算计', '隐忍'],
    personality: '内敛隐忍，存在感低，习惯躲在人后观察、算胜算；擅长挑拨，让别人先斗起来。',
    speech: '说话慢，声音低，爱说「其实」「按理说」。',
    background: '教了二十年数学，被人看不起了一辈子。在岛上谁都不认识。',
    drives: '活着离开，证明自己不是窝囊废。不急着动手：让他们先打，等只剩最后两个再出手。',
    interests: '算潮水和圈的位置，传话、挑拨，记下每个人的弱点。',
    occupation: '中学数学老师',
  }),
  persona({
    name: '梁婆',
    age: '68',
    gender: '女',
    intro: '渔村老人，懂潮水和天色，最在乎同村的阿布。',
    tags: ['慈祥', '固执', '护短'],
    personality: '慈祥固执，说一不二；平时和和气气，谁要动阿布，她跟谁拼命。',
    speech: '带渔村口音，爱叫人「娃」。',
    background:
      '在海边住了一辈子，看得懂潮汐和天色。阿布是隔壁家的孩子，她答应过阿布的妈妈要把他平安带回去。',
    drives: '把阿布送回家，自己活不活倒在其次。可船只坐得下一个人，到最后她得想清楚。',
    interests: '看潮水、找能躲雨的地方，护着阿布。',
    occupation: '渔村老人',
  }),
  persona({
    name: '阿布',
    age: '17',
    gender: '男',
    intro: '高中生，胆小，第一次离家这么远。',
    tags: ['胆小', '机灵', '怕死'],
    personality: '胆小怕事，遇险先躲；但脑子转得快，被逼到墙角时谁也说不准他会做什么。',
    speech: '说话结巴，一紧张声音就发抖。',
    background: '镇上的高中生，和梁婆是同村。妈妈在码头等他回家。',
    drives: '活下去，回家见妈妈。先躲起来、跟紧梁婆，等别人打完；真没退路了，也会拼命。',
    interests: '找安全的藏身处，盯着谁身上有武器。',
    occupation: '高中生',
  }),
]

/** 开局摆上的东西：编号前缀 br: */
const at = (locale: string, definition: string, ...ids: string[]): PrefabProp[] =>
  ids.map((id) => ({ id: `br:${id}`, definition, locale }))

export const battleRoyale: Prefab = {
  id: 'battle-royale',
  name: '大逃杀荒岛',
  description: '一群人困在荒岛上，潮水每天涨一圈，只有最后一个人能坐船离开。',
  worldview:
    '这是一座无人荒岛。你们醒来时就在岛上，不知道是怎么来的，也没有船能离开。' +
    '岛上有淡水泉、椰林、礁石潮池、废墟和一处破码头；吃的、喝的、能躲雨的地方都不多，有的东西藏着，要搜寻才找得到。' +
    '潮水每天涨一圈：天亮 06:00 公布今天要涨到的圈，12:00 开始涨，18:00 涨到，圈外的地会被淹没；第 1 圈第 2 天天亮才公布。' +
    '圈一天比一天小，最后只剩岛上最高的地方。站在水里很快就会耗尽力气。' +
    '每个人口袋里都有一张纸条：只有一个人能活着离开。',
  spec: {
    schema_version: 2,
    appearance_set: 'pr10-village-v1',
    view_mode: '2d',
    environment: { preset: 'coastal-village', vegetation: 'medium' },
    name: '大逃杀荒岛',
    seed: 51,
    places: [
      { kind: 'area', count: 6, size: 'medium' },
      { kind: 'temple', count: 1, size: 'medium' },
      { kind: 'park', count: 1, size: 'medium' },
      { kind: 'harbor', count: 1, size: 'medium' },
    ],
    names: {
      'area:1': '登岛沙滩',
      'area:2': '礁石潮池',
      'area:3': '漂流木滩',
      'area:4': '淡水泉',
      'area:5': '营地',
      'area:6': '东岬',
      temple: '废墟',
      park: '椰林',
      harbor: '破码头',
    },
    constraints: [],
    resources: 'normal-life',
    terrain_source: 'auto',
    settlement: 'ring',
  },
  gameMode: { kind: 'tide' },
  // 借长相：老周、里德、小宁、阿滩、珊娜、诺亚、阿婆、西奥
  roster: [
    'builtin_laozhou',
    'builtin_reed',
    'builtin_xiaoning',
    'builtin_tan',
    'builtin_sana',
    'builtin_noah',
    'builtin_po',
    'builtin_theo',
  ],
  cast: CAST,
  players: { default: 8, min: 4, max: 8 },
  needs: { fullness: true, energy: true, water: true, health: true, weather: true },
  needsDefault: true,
  needsHint: { on: '会饿会渴会困，淋雨会着凉，站在水里会掉体力', off: '只比谁会躲水' },
  options: [seedOption('圈的位置', '每一局圈缩向哪里都不一样')],
  // 第一局一个人一天最多用了 263 万 token；一局要跑五天半，全镇总量也放宽
  limits: {
    calls_per_day: 600,
    tokens_per_day: 4_000_000,
    total_calls: 30_000,
    total_tokens: 200_000_000,
  },
  furnish: {
    // 建镇生成器放的：area_N_prop_1/2/3 是床、干粮、水；椰林是座位和水；码头是渔网和渔具整理点
    remove: [
      ...['area_1', 'area_2', 'area_3', 'area_6'].flatMap((a) =>
        [1, 2, 3].map((n) => `${a}_prop_${n}`)
      ),
      'area_4_prop_1',
      'area_4_prop_2',
      'area_5_prop_2',
      'area_5_prop_3',
      'park_1_prop_1',
      'park_1_prop_2',
      'harbor_1_prop_1',
      'harbor_1_prop_2',
    ],
    place: [
      ...at('area_1', 'core:island-stone@1', 'stone-1', 'stone-2'),
      ...at('area_2', 'core:island-tidepool@1', 'tidepool'),
      ...at('area_2', 'core:island-harpoon@1', 'harpoon-1'),
      ...at('area_3', 'core:island-stone@1', 'stone-3'),
      ...at('area_3', 'core:island-club@1', 'club'),
      ...at('area_4', 'core:island-herbs@1', 'herbs-1'),
      ...at('area_5', 'core:bed@2', 'bed-2'),
      ...at('area_6', 'core:island-herbs@1', 'herbs-2'),
      ...at('park_1', 'core:island-shelter@1', 'palm-shelter-1', 'palm-shelter-2'),
      ...at('park_1', 'core:island-palms@2', 'palms'),
      ...at('temple_1', 'core:island-stone-hut@1', 'stone-hut-1', 'stone-hut-2'),
      ...at('harbor_1', 'core:rations@2', 'rations'),
      ...at('harbor_1', 'core:drinking_water@1', 'water'),
      ...at('harbor_1', 'core:island-harpoon@1', 'harpoon-2'),
    ],
  },
}
