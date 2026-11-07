import { seedOption, type Prefab } from '.'

// 大逃杀荒岛：环岛小径的荒岛（种子 51），开局打开潮水圈。
// 地点名照着荒岛起；「废墟」「破码头」是生成器的神庙和港口换了名字。

export const battleRoyale: Prefab = {
  id: 'battle-royale',
  name: '大逃杀荒岛',
  description: '一群人困在荒岛上，潮水每天涨一圈，最后只剩最高处的一小块地。',
  worldview:
    '这是一座无人荒岛。你们醒来时就在岛上，不知道是怎么来的，也没有船能离开。' +
    '岛上有淡水泉、椰林、礁石潮池和一处破码头，能找到吃的、喝的和用得上的东西。' +
    '潮水每天涨一圈：天亮 06:00 公布今天要涨到的圈，12:00 开始涨，18:00 涨到，圈外的地会被淹没。' +
    '圈一天比一天小，最后只剩岛上最高的地方。站在水里很快就会耗尽力气。',
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
  players: { default: 8, min: 4, max: 12 },
  needs: { fullness: true, energy: true, water: true, health: true, weather: true },
  needsDefault: true,
  needsHint: { on: '会饿会渴会困，站在水里会掉体力', off: '只比谁会躲水' },
  options: [seedOption('圈的位置', '每一局圈缩向哪里都不一样')],
}
