import { seedOption, type Prefab } from '.'

// 月影村狼人杀：雪地街道镇（种子 7），十二间木屋按座号起名，议事广场、老钟楼、老酒馆、狼嚎林。
// 开局打开狼人杀：按入住的号码排座次、发身份。吃喝睡默认关着，只比嘴上功夫。
// 开局设置多两行：身份（每局随机或固定种子）、白天长短（天亮到 16:30 敲钟）。

export const werewolf: Prefab = {
  id: 'werewolf',
  name: '月影村狼人杀',
  description: '雪山下的小村子混进了狼人。白天过日子、私下串联，傍晚上议事广场投票，夜里狼人出没。',
  worldview:
    '月影村是雪山脚下的一个小村子。十二间木屋按号码排开，村子中间是议事广场，广场边有老钟楼，' +
    '村里还有一家老酒馆，村外是狼嚎林。天很冷，到处是雪。\n' +
    '最近村里混进了狼人：白天他们和大家一样过日子，夜里出来害人。村里定了规矩来找出他们：' +
    '每天 16:30 老钟楼敲钟，所有活着的人去议事广场，17:00 按座次每人发言一次，然后一起投票，放逐票最多的人；' +
    '天黑以后各回各家，有身份的人夜里会被叫醒行动，天亮时公布昨晚倒下的人。\n' +
    '每个人的座号、身份、知道的事和此刻该做什么，都写在观察里的 werewolf 一栏；发言、投票和夜里的行动用 mode_action 交。' +
    '白天可以自由走动，私下找人聊、结盟、打听消息。',
  spec: {
    schema_version: 2,
    appearance_set: 'pr10-village-v1',
    view_mode: '2d',
    environment: { preset: 'frozen', vegetation: 'dense' },
    name: '月影村',
    seed: 7,
    places: [
      { kind: 'home', count: 12, size: 'small' },
      { kind: 'plaza', count: 1, size: 'large' },
      { kind: 'temple', count: 1, size: 'small' },
      { kind: 'canteen', count: 1, size: 'small' },
      { kind: 'area', count: 1, size: 'large' },
    ],
    names: {
      ...Object.fromEntries(
        Array.from({ length: 12 }, (_, i) => [`home:${i + 1}`, `${i + 1} 号木屋`])
      ),
      plaza: '议事广场',
      temple: '老钟楼',
      canteen: '老酒馆',
      'area:1': '狼嚎林',
    },
    constraints: [],
    resources: 'normal-life',
    terrain_source: 'auto',
  },
  gameMode: { kind: 'werewolf' },
  roster: [
    'builtin_ashu',
    'builtin_xiaohe',
    'builtin_finn',
    'builtin_luna',
    'builtin_stone',
    'builtin_mira',
    'builtin_noah',
    'builtin_tan',
    'builtin_alan',
    'builtin_iris',
    'builtin_june',
    'builtin_reed',
  ],
  players: { default: 9, min: 6, max: 12 },
  needs: { fullness: true, energy: true, water: true, health: true, weather: true },
  needsDefault: false,
  needsHint: { on: '会饿会渴会困，夜里要睡觉', off: '只比嘴上功夫' },
  options: [
    seedOption('身份', '谁拿什么身份每局都不一样'),
    {
      label: '白天',
      choices: [
        { value: '3', label: '3 小时', hint: '只够每人一两场私聊，最省' },
        { value: '6', label: '6 小时', hint: '够狼人串供、预言家找人交底' },
        { value: '9', label: '9 小时', hint: '最像过日子，也最花钱' },
      ],
      initial: '6',
      apply: (choice, value) => ({ ...choice, day_hours: Number(value) }),
    },
  ],
}
