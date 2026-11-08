import type { SwordholderRole } from 'town-shared/protocol'
import { iconImage, type PixelIcon } from './pixelIcons'

// 执剑人之夜界面的像素图标：画法见 pixelIcons.ts。身份各一个（剑、讲台、三个太阳、票箱），
// 另有敲钟、水滴、引力波天线和开关。

/** 三个太阳：上一个、左下右下各一个，各自一种颜色 */
function suns(): PixelIcon {
  const discs: [number, number, string][] = [
    [7.5, 4, 'y'],
    [3.5, 11.5, 'o'],
    [11.5, 11.5, 'r'],
  ]
  const rows = Array.from({ length: 16 }, (_, y) =>
    Array.from({ length: 16 }, (_, x) => {
      for (const [cx, cy, c] of discs) {
        const d = Math.hypot(x - cx, y - cy)
        if (d <= 1.2) return c.toUpperCase()
        if (d <= 3.3) return c
      }
      return '.'
    }).join('')
  )
  return {
    pal: { y: '#f2c14e', Y: '#fbe7a4', o: '#e8823a', O: '#f6c08e', r: '#d84a3a', R: '#f19a8c' },
    rows,
  }
}

const ICONS = {
  sword: {
    pal: { w: '#f4f6fa', s: '#aab3c4', g: '#d9a441', G: '#b07d2a', h: '#6b4a32' },
    rows: [
      '.......w........',
      '.......ws.......',
      '.......ws.......',
      '.......ws.......',
      '.......ws.......',
      '.......ws.......',
      '.......ws.......',
      '.......ws.......',
      '.......ws.......',
      '....gggggggg....',
      '....GGGGGGGG....',
      '.......hh.......',
      '.......hh.......',
      '.......hh.......',
      '......gggg......',
      '................',
    ],
  },
  podium: {
    pal: { k: '#3a3f4a', w: '#c98a4a', W: '#9a6232', b: '#4a78c8' },
    rows: [
      '................',
      '.........kk.....',
      '.........kk.....',
      '..........k.....',
      '..........k.....',
      '..wwwwwwwwwwww..',
      '..WWWWWWWWWWWW..',
      '...wwwwwwwwww...',
      '...wwwbbbbwww...',
      '...wwwbbbbwww...',
      '...wwwwwwwwww...',
      '...wwwwwwwwww...',
      '...wwwwwwwwww...',
      '...WWWWWWWWWW...',
      '..WWWWWWWWWWWW..',
      '................',
    ],
  },
  ballot: {
    pal: { p: '#f4f1ea', l: '#9aa3b5', b: '#4a78c8', B: '#33589a', w: '#ffffff' },
    rows: [
      '................',
      '......pppp......',
      '......pllp......',
      '......pppp......',
      '......pllp......',
      '..bbbbppppbbbb..',
      '..bBBBBBBBBBBb..',
      '..bbbbbbbbbbbb..',
      '..bbbbwwwwbbbb..',
      '..bbbbwwwwbbbb..',
      '..bbbbbbbbbbbb..',
      '..bbbbbbbbbbbb..',
      '..BBBBBBBBBBBB..',
      '................',
      '................',
      '................',
    ],
  },
  bell: {
    pal: { y: '#e0b54a', Y: '#f6dc8a', d: '#a8802a', k: '#5a4a3a' },
    rows: [
      '................',
      '.......kk.......',
      '......yyyy......',
      '.....yyyyyy.....',
      '.....yYyyyy.....',
      '....yYyyyyyy....',
      '....yYyyyyyy....',
      '....yyyyyyyy....',
      '...yyyyyyyyyy...',
      '...yyyyyyyyyy...',
      '..yyyyyyyyyyyy..',
      '..dddddddddddd..',
      '.......kk.......',
      '................',
      '................',
      '................',
    ],
  },
  drop: {
    pal: { w: '#ffffff', S: '#dce6f2', s: '#a9bcd4', D: '#6f86a6' },
    rows: [
      '.......ss.......',
      '.......ss.......',
      '......sSSs......',
      '......sSSs......',
      '.....sSSSSs.....',
      '.....sSwSSs.....',
      '....sSwwSSSs....',
      '....sSwSSSSs....',
      '...sSSSSSSSSs...',
      '...sSSSSSSSSs...',
      '...sSSSSSSSDs...',
      '...sSSSSSSDDs...',
      '....sSSSSDDs....',
      '.....sDDDDs.....',
      '......ssss......',
      '................',
    ],
  },
  antenna: {
    pal: { s: '#d8dce4', S: '#a8aebb', r: '#e5533d', d: '#8a8f9a' },
    rows: [
      '.......rr.......',
      '.......ss.......',
      '.......sS.......',
      '......ssSS......',
      '......ssSS......',
      '......ssSS......',
      '......ssSS......',
      '......ssSS......',
      '.....sssSSS.....',
      '.....sssSSS.....',
      '.....sssSSS.....',
      '.....sssSSS.....',
      '....ssssSSSS....',
      '...dddddddddd...',
      '...dddddddddd...',
      '................',
    ],
  },
  switch: {
    pal: { r: '#e5533d', R: '#f6a08f', d: '#a8301f', k: '#4a4f5a', K: '#6a707c' },
    rows: [
      '................',
      '................',
      '................',
      '.....rrrrrr.....',
      '....rRRrrrrr....',
      '...rRRrrrrrrr...',
      '...rRrrrrrrrr...',
      '...rrrrrrrrrr...',
      '...drrrrrrrrd...',
      '..kkddddddddkk..',
      '..kkkkkkkkkkkk..',
      '..kKKKKKKKKKKk..',
      '..kkkkkkkkkkkk..',
      '................',
      '................',
      '................',
    ],
  },
  suns: suns(),
} satisfies Record<string, PixelIcon>

export type SwordholderIcon = keyof typeof ICONS

/** 身份的图标 */
export const ROLE_ICON: Record<SwordholderRole, SwordholderIcon> = {
  holder: 'sword',
  candidate: 'podium',
  envoy: 'suns',
  voter: 'ballot',
}

/** 按 scale 倍显示的像素图标（18 × scale 像素见方） */
export function swordholderIcon(name: SwordholderIcon, scale = 1) {
  return iconImage(`swordholder:${name}`, ICONS[name], scale, 'sh-px')
}
