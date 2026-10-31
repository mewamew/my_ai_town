import type { SettingsPage } from '../settingsCenter'
import { el } from '../dom'
import { isTouch } from '../platform'
import { settingRow, switchControl } from './controls'

// 声音与按键：音乐/音效开关直接驱动顶栏按钮（状态走同一份 localStorage），
// HD-2D 按键说明是静态内容，不需要保存；触屏上换成手势和屏幕按钮的说明。

type Keys = [keys: string, action: string][]

const KEYS_2D: [string, Keys][] = [
  [
    '看小镇时',
    [
      ['<kbd>空格</kbd>', '暂停 / 继续'],
      ['左键拖动 · 滚轮', '移动地图 · 缩放'],
      ['右键拖动', '调整俯角'],
      ['点村民 · 再点一次', '脚下出现说话、跟随等按钮 · 打开角色卡'],
      ['点空地', '取消选中'],
    ],
  ],
  [
    '操控化身时',
    [
      ['点地面 · <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd>', '走路'],
      ['<kbd>E</kbd> · <kbd>Tab</kbd>', '和提示的对象互动 · 换一个对象'],
      ['<kbd>B</kbd> · <kbd>Esc</kbd>', '背包 · 收起面板'],
    ],
  ],
]

/** 触屏上的操作说明：没有键盘和鼠标右键 */
const TOUCH_2D: [string, Keys][] = [
  [
    '看小镇时',
    [
      ['点顶栏的 ▶', '开始 / 暂停'],
      ['单指拖动 · 两指缩放', '移动地图 · 缩放'],
      ['两指一起上下拖', '调整俯角'],
      ['点村民 · 点「资料」', '脚下出现说话、跟随等按钮 · 打开角色卡；左右滑卡片换人'],
      ['点空地', '取消选中'],
    ],
  ],
  [
    '操控化身时',
    [
      ['左下摇杆 · 点地面', '走路'],
      ['右下主按钮 · 换目标', '和提示的对象互动 · 换一个对象'],
      ['背包 · 返回键', '背包 · 收起面板'],
    ],
  ],
]

/** 一个声音开关：顶栏按钮与这一页改的是同一个状态 */
interface SoundSwitch {
  enabled(): boolean
  toggle(): void
}

export function createSoundPage(
  game: boolean,
  audio: { music: SoundSwitch; effects: SoundSwitch }
): SettingsPage {
  const page = el('section', '', 'spage')
  page.append(el('h2', '声音与按键'))
  const rows = el('div', '', 'set-rows')
  const toggles = (
    [
      [audio.music, '音乐', '白天、傍晚、雨夜各有曲目，随游戏内时间切换'],
      [audio.effects, '音效', '脚步声、下雨与环境氛围声'],
    ] as const
  ).map(([sound, label, description]) => {
    const control = switchControl(label, () => {
      sound.toggle()
      sync()
    })
    rows.append(settingRow(label, description, control.el))
    return { control, on: sound.enabled }
  })
  page.append(rows)
  const keys = isTouch() ? TOUCH_2D : KEYS_2D
  for (const [caption, list] of keys) {
    page.append(el('h3', caption, 'section-caption'))
    const grid = el('div', '', 'set-keys')
    grid.innerHTML = list.map(([k, action]) => `<span>${k}</span><span>${action}</span>`).join('')
    page.append(grid)
  }
  const sync = () => {
    for (const toggle of toggles) toggle.control.set(toggle.on())
  }
  return {
    id: 'sound',
    group: 'game',
    navLabel: '声音与按键',
    title: '声音与按键',
    el: page,
    isDirty: () => false,
    save: () => {},
    discard: () => {},
    onShow: sync,
  }
}
