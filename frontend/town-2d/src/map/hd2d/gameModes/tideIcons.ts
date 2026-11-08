import type { TideNewsKind } from 'town-shared/protocol'
import { iconImage, type PixelIcon } from './pixelIcons'

// 潮水圈界面的像素图标：动手、倒下、木箱、船，画法见 pixelIcons.ts。

const ICONS = {
  clash: {
    pal: { y: '#f2c14e', o: '#e5803d', r: '#d9473b' },
    rows: [
      '................',
      '.......y........',
      '...y...y....y...',
      '....y..y...y....',
      '.....yyoyyy.....',
      '.....yorroy.....',
      '..yyyorrrroyyy..',
      '....yorrrrroy...',
      '.....yorrroy....',
      '.....yyoroyy....',
      '....y..yoy..y...',
      '...y...y.y...y..',
      '.......y........',
      '................',
      '................',
      '................',
    ],
  },
  fell: {
    pal: { w: '#ece6da', g: '#b9b2a4', n: '#2a2228' },
    rows: [
      '................',
      '.....wwwwww.....',
      '....wwwwwwww....',
      '...wwwwwwwwww...',
      '...wwwwwwwwww...',
      '...wnnwwwwnnw...',
      '...wnnnwwnnnw...',
      '...wnnwwwwnnw...',
      '...wwwwnnwwww...',
      '....wwwnnwww....',
      '.....wwwwww.....',
      '.....wgwgwgw....',
      '.....wgwgwgw....',
      '......wwwww.....',
      '................',
      '................',
    ],
  },
  crate: {
    pal: { b: '#b4733a', d: '#7c4b23', l: '#d69a5c', n: '#e6e0d2', s: '#4f7d4a' },
    rows: [
      '................',
      '................',
      '..dddddddddddd..',
      '..dllllllllllld.',
      '..dbnbbbbbbbnbd.',
      '..dbbbbbbbbbbbd.',
      '..dddddddddddd..',
      '..dllllllllllld.',
      '..dbnbbbbbbbnbd.',
      '..dbbbbbbbbbbbd.',
      '..dddddddddddd..',
      '..dllllllllllld.',
      '..dbnbbbbbbbnbd.',
      '..dbbsbbbbsbbbd.',
      '..dddddddddddd..',
      '................',
    ],
  },
  boat: {
    pal: { w: '#f4ecd6', l: '#d8cba8', b: '#a8642f', d: '#77441d', m: '#5b4632', s: '#6fb3d6' },
    rows: [
      '.......m........',
      '.......mw.......',
      '.......mww......',
      '.......mwww.....',
      '.......mwwww....',
      '.......mwwwww...',
      '.......mwwwwl...',
      '.......mwwll....',
      '.......m........',
      '..dddddmddddd...',
      '..bbbbbbbbbbbbb.',
      '...bbbbbbbbbbb..',
      '....ddddddddd...',
      '..ss.ss.ss.ss.s.',
      '.s..s..s..s..s..',
      '................',
    ],
  },
} satisfies Record<TideNewsKind, PixelIcon>

/** 战报一类事的图标，按 scale 倍显示（18 × scale 像素见方） */
export function tideIcon(kind: TideNewsKind, scale = 2) {
  return iconImage(`tide:${kind}`, ICONS[kind], scale, 'tide-px')
}
