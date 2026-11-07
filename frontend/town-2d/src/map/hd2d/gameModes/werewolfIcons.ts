import type { WerewolfRole } from 'town-shared/protocol'

// 狼人杀界面的像素图标：16×16 平涂，照村民头像的画法（近黑描边，一种材质一两个颜色，不画光影），
// 外面自动描一圈边，成图 18×18，只按整数倍显示。

const OUTLINE = '#141014'

type Icon = { pal: Record<string, string>; rows: string[] }

const mirror = (half: string[]) => half.map((r) => r + [...r].reverse().join(''))
const disc = (fn: (x: number, y: number) => string) =>
  Array.from({ length: 16 }, (_, y) => Array.from({ length: 16 }, (_, x) => fn(x, y)).join(''))

const ICONS = {
  wolf: {
    pal: { G: '#8f949e', D: '#5d616b', l: '#e6dfcf', r: '#e5533d', n: '#141014' },
    rows: mirror([
      '........',
      '..G.....',
      '..GG....',
      '..GDG...',
      '..GDGGGG',
      '.GGGGGGG',
      '.GGGrrGG',
      '.GGGGGGG',
      '.GGGGGGl',
      '..GGGlll',
      '..GGllll',
      '...GGlln',
      '...GGlll',
      '....GGll',
      '.....GGG',
      '........',
    ]),
  },
  seer: {
    pal: { b: '#6f97dd', m: '#b39ae8', y: '#d9a441' },
    rows: [
      '................',
      '................',
      '......bbbb......',
      '....bbbbbbbb....',
      '...bbbbbbbbbb...',
      '...bbbmmbbbbb...',
      '..bbbbmbbmbbbb..',
      '..bbbbbmmmbbbb..',
      '..bbbbbbbbbbbb..',
      '...bbbbbbbbbb...',
      '...bbbbbbbbbb...',
      '.....bbbbbb.....',
      '....yyyyyyyy....',
      '...yyyyyyyyyy...',
      '...yyyyyyyyyy...',
      '................',
    ],
  },
  witch: {
    pal: { k: '#a77748', g: '#c9d3e3', p: '#9a5fd0', x: '#e3cdf7' },
    rows: [
      '................',
      '......kkkk......',
      '......kkkk......',
      '.......gg.......',
      '.......gg.......',
      '......gggg......',
      '....gggggggg....',
      '...gppppppppg...',
      '..gppppxpppppg..',
      '..gppppppppppg..',
      '..gpppxppppppg..',
      '..gppppppppppg..',
      '...gppppppppg...',
      '....gggggggg....',
      '................',
      '................',
    ],
  },
  hunter: {
    pal: { k: '#a77748', s: '#8b9099' },
    rows: [
      '................',
      '..............s.',
      '.............ss.',
      '............ss..',
      '...........ss...',
      '..........ss....',
      '.........ss.....',
      '........sss.....',
      '.......kkss.....',
      '......kkks......',
      '.....kkkk.s.....',
      '....kkkk........',
      '...kkkk.........',
      '..kkkk..........',
      '.kkk............',
      '................',
    ],
  },
  guard: {
    pal: { s: '#b8bcc4', m: '#4f7fc4', y: '#e2b24a' },
    rows: [
      '................',
      '..ssssssssssss..',
      '..smmmmmmmmmms..',
      '..smmmmyymmmms..',
      '..smmmyyyymmms..',
      '..smmmmyymmmms..',
      '..smmmmyymmmms..',
      '..smmmmmmmmmms..',
      '...smmmmmmmms...',
      '...smmmmmmmms...',
      '....smmmmmms....',
      '.....smmmms.....',
      '......smms......',
      '.......ss.......',
      '................',
      '................',
    ],
  },
  villager: {
    pal: { s: '#8b9099', k: '#a77748' },
    rows: [
      '................',
      '....s..ss..s....',
      '....s..ss..s....',
      '....s..ss..s....',
      '....s..ss..s....',
      '....ssssssss....',
      '.....ssssss.....',
      '.......kk.......',
      '.......kk.......',
      '.......kk.......',
      '.......kk.......',
      '.......kk.......',
      '.......kk.......',
      '.......kk.......',
      '.......kk.......',
      '................',
    ],
  },
  fire: {
    pal: { F: '#f08a24', f: '#ffd166', k: '#8a5a35' },
    rows: [
      '................',
      '.......FF.......',
      '......FFFF......',
      '.....FFFFF......',
      '.....FFfFFF.....',
      '....FFFffFF.....',
      '....FFffffFF....',
      '...FFFffffFFF...',
      '...FFffffffFF...',
      '...FFFffffFFF...',
      '....FFFFFFFF....',
      '..kkkkkkkkkkkk..',
      '.kkkk.kkkk.kkkk.',
      '..kkk..kk..kkk..',
      '................',
      '................',
    ],
  },
  ballot: {
    pal: { w: '#f1ead8', R: '#d4502a', k: '#a77748', n: '#141014' },
    rows: [
      '................',
      '......wwww......',
      '......wRRw......',
      '......wwRw......',
      '......wwww......',
      '..kkkknnnnkkkk..',
      '..kkkkkkkkkkkk..',
      '..kkkkkkkkkkkk..',
      '..kkkkkkkkkkkk..',
      '..kkkkkkkkkkkk..',
      '..kkkkkkkkkkkk..',
      '..kkkkkkkkkkkk..',
      '..kkkkkkkkkkkk..',
      '................',
      '................',
      '................',
    ],
  },
  moon: {
    pal: { m: '#f3e9c6' },
    rows: disc((x, y) => {
      const a = Math.hypot(x - 7.5, y - 7.5) <= 6.4
      const b = Math.hypot(x - 10.6, y - 5.4) <= 5.3
      return a && !b ? 'm' : '.'
    }),
  },
  sun: {
    pal: { y: '#ffd166', o: '#f0a03a' },
    rows: disc((x, y) => {
      const d = Math.hypot(x - 7.5, y - 7.5)
      if (d <= 4.4) return 'y'
      const ang = Math.atan2(y - 7.5, x - 7.5) / (Math.PI / 4)
      return d >= 5.6 && d <= 7.4 && Math.abs(ang - Math.round(ang)) < 0.13 ? 'o' : '.'
    }),
  },
} satisfies Record<string, Icon>

export type WerewolfIcon = keyof typeof ICONS | WerewolfRole

const painted = new Map<string, string>()

/** 一个图标画成 18×18 的图（描边一格），缓存成 data URL */
function paint(key: keyof typeof ICONS) {
  const cached = painted.get(key)
  if (cached) return cached
  const { rows, pal } = ICONS[key] as Icon
  const h = rows.length
  const w = rows[0].length
  const canvas = document.createElement('canvas')
  canvas.width = w + 2
  canvas.height = h + 2
  const g = canvas.getContext('2d')
  if (!g) return ''
  const on = (x: number, y: number) => x >= 0 && y >= 0 && x < w && y < h && rows[y][x] !== '.'
  g.fillStyle = OUTLINE
  for (let y = -1; y <= h; y++)
    for (let x = -1; x <= w; x++)
      if (!on(x, y) && (on(x + 1, y) || on(x - 1, y) || on(x, y + 1) || on(x, y - 1)))
        g.fillRect(x + 1, y + 1, 1, 1)
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const ch = rows[y][x]
      if (ch === '.') continue
      g.fillStyle = pal[ch] ?? '#f0f'
      g.fillRect(x + 1, y + 1, 1, 1)
    }
  const url = canvas.toDataURL()
  painted.set(key, url)
  return url
}

/** 按 scale 倍显示的像素图标（18 × scale 像素见方） */
export function pixelIcon(key: WerewolfIcon, scale = 2) {
  const img = document.createElement('img')
  img.src = paint(key)
  img.alt = ''
  img.className = 'ww-px'
  img.width = 18 * scale
  img.height = 18 * scale
  return img
}
