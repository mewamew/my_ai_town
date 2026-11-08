import type { WerewolfRole } from 'town-shared/protocol'
import { iconImage, type PixelIcon } from './pixelIcons'

// 狼人杀界面的像素图标：画法见 pixelIcons.ts。

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
} satisfies Record<string, PixelIcon>

export type WerewolfIcon = keyof typeof ICONS | WerewolfRole

/** 按 scale 倍显示的像素图标（18 × scale 像素见方） */
export function pixelIcon(key: WerewolfIcon, scale = 2) {
  return iconImage(`ww:${key}`, ICONS[key] as PixelIcon, scale, 'ww-px')
}
