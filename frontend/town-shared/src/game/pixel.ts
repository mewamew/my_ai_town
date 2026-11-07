// 地图上和菜单里的像素图标：照村民头像的画法——平涂、近黑描边、一种材质最多两个颜色，不画渐变和立体光影。
// 16×16 一格，只按整数倍显示（默认 2 倍，和头像一样每个像素 2 个点），浏览器按像素放大，不会糊。
// 图形用字符画写在这里：「.」是空，其余字母查 PALETTE；带描边的图形由 outline() 在外圈补一圈近黑。
// 模板里写 <i data-pixel="名字"></i>，decoratePixels 换成图片；脚本里用 pixelIcon()。

const PALETTE: Record<string, string> = {
  O: '#141014',
  w: '#f4f6f4',
  c: '#f4ece2',
  C: '#dccbb3',
  s: '#f2d9c6',
  k: '#2b201b',
  K: '#6b635f',
  m: '#c4bfbb',
  M: '#8a837f',
  b: '#d39a63',
  B: '#a9693f',
  D: '#7a4a2b',
  y: '#f6c94e',
  Y: '#d8962c',
  L: '#f7e7a6',
  g: '#6cc08f',
  G: '#2f6b55',
  r: '#e0664f',
  u: '#9cc8ea',
  U: '#4f7fb0',
  p: '#e4aab0',
}

type Cells = (string | null)[][]

function parse(rows: string[]): Cells {
  return rows.map((row) => [...row].map((ch) => (ch === '.' ? null : ch)))
}
/** 外描边：挨着色块（上下左右）的空格涂成近黑 */
function outline(cells: Cells): Cells {
  const at = (x: number, y: number) => cells[y]?.[x] ?? null
  return cells.map((row, y) =>
    row.map(
      (v, x) =>
        v ??
        ([
          [1, 0],
          [-1, 0],
          [0, 1],
          [0, -1],
        ].some(([dx, dy]) => at(x + dx, y + dy))
          ? 'O'
          : null)
    )
  )
}
/** 后面的层盖住前面的 */
function stack(...layers: Cells[]): Cells {
  return layers[0].map((row, y) =>
    row.map((_, x) => layers.reduce<string | null>((v, l) => l[y][x] ?? v, null))
  )
}
/** 圆形的图：对每个格子中心问一下该涂什么颜色 */
function radial(fn: (dx: number, dy: number) => string | null): Cells {
  return Array.from({ length: 16 }, (_, y) =>
    Array.from({ length: 16 }, (_, x) => fn(x + 0.5 - 8, y + 0.5 - 8))
  )
}
const drawn = (rows: string[]) => outline(parse(rows))

const cloudRows = (top: number, fill: string, shade: string) => {
  const shape = [
    '.......www......',
    '.....wwwwwww....',
    '....wwwwwwwww...',
    '..wwwwwwwwwwww..',
    '.wwwwwwwwwwwwww.',
    '.wwwwwwwwwwwwsw.',
    '..ssssssssssss..',
  ].map((r) => r.replaceAll('w', fill).replaceAll('s', shade))
  return Array.from({ length: 16 }, (_, y) => shape[y - top] ?? '................')
}

const SHAPES: Record<string, () => Cells> = {
  sun: () =>
    drawn([
      '................',
      '................',
      '.......yy.......',
      '...y........y...',
      '.....yyyyyy.....',
      '....yccyyyyy....',
      '....ycyyyyyy....',
      '.yy.yyyyyyyy.yy.',
      '.yy.yyyyyyyy.yy.',
      '....yyyyyyYy....',
      '....yyyyyYYy....',
      '.....yyyyyy.....',
      '...y........y...',
      '.......yy.......',
      '................',
      '................',
    ]),
  moon: () =>
    outline(
      radial((dx, dy) =>
        Math.hypot(dx, dy) <= 5.6 && Math.hypot(dx - 3, dy + 2.2) > 4.6 ? 'L' : null
      )
    ),
  cloud: () => outline(parse(cloudRows(4, 'w', 'm'))),
  rain: () =>
    stack(
      outline(parse(cloudRows(2, 'w', 'm'))),
      parse([
        ...Array<string>(10).fill('................'),
        '...U....U....U..',
        '..U....U....U...',
        '................',
        '.....U....U.....',
        '....U....U......',
        '................',
      ])
    ),
  storm: () =>
    stack(
      outline(parse(cloudRows(2, 'm', 'M'))),
      drawn([
        ...Array<string>(9).fill('................'),
        '.......yy.......',
        '......yy........',
        '.....yyyy.......',
        '.......yy.......',
        '......yy........',
        '................',
        '................',
      ])
    ),
  snow: () =>
    stack(
      outline(parse(cloudRows(2, 'w', 'm'))),
      parse([
        ...Array<string>(10).fill('................'),
        '...u.....u......',
        '.......u.....u..',
        '................',
        '.....u.....u....',
        '................',
        '................',
      ])
    ),
  scroll: () =>
    drawn([
      '................',
      '................',
      '..cccccccccccc..',
      '..CCCCCCCCCCCC..',
      '...cccccccccc...',
      '...cKKKKKKKKc...',
      '...cccccccccc...',
      '...cKKKKKKccc...',
      '...cccccccccc...',
      '...cKKKKKKKKc...',
      '...cccccccccc...',
      '...cKKKKccrrc...',
      '..cccccccccccc..',
      '..CCCCCCCCCCCC..',
      '................',
      '................',
    ]),
  chest: () =>
    drawn([
      '................',
      '................',
      '................',
      '................',
      '...bbbbbbbbbb...',
      '..BBBBBBBBBBBB..',
      '..BBBBBBBBBBBB..',
      '..DDDDDyyDDDDD..',
      '..BBBBByYBBBBB..',
      '..BBBBBBBBBBBB..',
      '..BBBBBBBBBBBB..',
      '..BBBBBBBBBBBB..',
      '..DDDDDDDDDDDD..',
      '................',
      '................',
      '................',
    ]),
  // 书页比封面往右下多出两格：一格让封面的描边压着，一格露出白边
  book: () =>
    stack(
      drawn([
        '................',
        '................',
        '................',
        '................',
        '.....wwwwwwwww..',
        '.....wwwwwwwww..',
        '.....wwwwwwwww..',
        '.....wwwwwwwww..',
        '.....wwwwwwwww..',
        '.....wwwwwwwww..',
        '.....wwwwwwwww..',
        '.....wwwwwwwww..',
        '.....wwwwwwwww..',
        '.....wwwwwwwww..',
        '.....wwwwwwwww..',
        '................',
      ]),
      drawn([
        '................',
        '................',
        '...GGGGGGGGG....',
        '...GgGGGGGGG....',
        '...GgGccccGG....',
        '...GgGccccGG....',
        '...GgGGGGGGG....',
        '...GgGGGGGGG....',
        '...GgGGGGGGG....',
        '...GgGGGGGGG....',
        '...GgGGGGGGG....',
        '...GgGGGGGGG....',
        '...GGGGGGGGG....',
        '................',
        '................',
        '................',
      ])
    ),
  hammer: () =>
    drawn([
      '................',
      '................',
      '...mmmmmmmmmm...',
      '...MMMMMMMMMM...',
      '...MMMMMMMMMM...',
      '.......bB.......',
      '.......bB.......',
      '.......bB.......',
      '.......bB.......',
      '.......bB.......',
      '.......bB.......',
      '.......DD.......',
      '.......DD.......',
      '................',
      '................',
      '................',
    ]),
  // 两个人：后面的先描边，前面的盖上去
  people: () =>
    stack(
      drawn([
        '................',
        '.........kkkk...',
        '........kkkkkk..',
        '.......kkkkkkkk.',
        '.......ssssssss.',
        '.......skssssks.',
        '.......ssssssss.',
        '........ssssss..',
        '.......UUwwUUU..',
        '......UUUUUUUUU.',
        '......UUUUUUUUU.',
        '......UUUUUUUUU.',
        '......UUUUUUUUU.',
        '................',
        '................',
        '................',
      ]),
      drawn([
        '................',
        '................',
        '................',
        '................',
        '..kkkk..........',
        '.kkkkkk.........',
        'kkkkkkkk........',
        'kssssssk........',
        'kskssksk........',
        'kssssssk........',
        'kksssskkk.......',
        'kpppppppk.......',
        'ppppppppp.......',
        'ppppppppp.......',
        '................',
        '................',
      ])
    ),
  gear: () =>
    outline(
      radial((dx, dy) => {
        const r = Math.hypot(dx, dy)
        const t = ((((Math.atan2(dy, dx) / (2 * Math.PI)) * 8 + 0.5) % 1) + 1) % 1
        if (r < 2.1 || !(r <= 4.7 || (Math.abs(t - 0.5) < 0.2 && r <= 6.7))) return null
        return dx + dy > 3.2 ? 'M' : 'm'
      })
    ),
  coin: () =>
    outline(
      radial((dx, dy) => {
        if (Math.hypot(dx, dy) > 6.1) return null
        if (Math.abs(dx) < 1.1 && Math.abs(dy) < 3.1) return 'Y'
        if ((dx === -2.5 && dy === -3.5) || (dx === -3.5 && (dy === -2.5 || dy === -1.5)))
          return 'w'
        return dx + dy > 5.5 ? 'Y' : 'y'
      })
    ),
  help: () =>
    stack(
      drawn([
        '................',
        '..wwwwwwwwwwww..',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '..wwwwwwwwwwww..',
        '...www..........',
        '...ww...........',
        '...w............',
        '................',
        '................',
      ]),
      parse([
        '................',
        '................',
        '................',
        '......OOOO......',
        '.....OO..OO.....',
        '.........OO.....',
        '........OO......',
        '.......OO.......',
        '................',
        '.......OO.......',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
      ])
    ),
  // 选择小镇：门加往外的箭头
  door: () =>
    stack(
      drawn([
        '................',
        '................',
        '....BBBB........',
        '...BBBBBB.......',
        '...BBDBBB.......',
        '...BBDBBB.......',
        '...BBDBBB.......',
        '...BBDBBB.......',
        '...BBDByB.......',
        '...BBDBBB.......',
        '...BBDBBB.......',
        '...BBDBBB.......',
        '...BBDBBB.......',
        '...BBDBBB.......',
        '................',
        '................',
      ]),
      drawn([
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
        '............g...',
        '..........ggggg.',
        '..........gggggg',
        '..........ggggg.',
        '............g...',
        '................',
        '................',
        '................',
        '................',
        '................',
      ])
    ),
  note: () =>
    parse([
      '................',
      '................',
      '........OOOO....',
      '........OOOOOO..',
      '........O...OO..',
      '........O....O..',
      '........O.......',
      '........O.......',
      '........O.......',
      '........O.......',
      '....OOOOO.......',
      '...OOOOOO.......',
      '...OOOOOO.......',
      '....OOOO........',
      '................',
      '................',
    ]),
  speaker: () =>
    parse([
      '................',
      '................',
      '.......O........',
      '......OO....O...',
      '.....OOO..O..O..',
      '..OOOOOO...O..O.',
      '..OOOOOO...O..O.',
      '..OOOOOO...O..O.',
      '..OOOOOO...O..O.',
      '..OOOOOO...O..O.',
      '.....OOO..O..O..',
      '......OO....O...',
      '.......O........',
      '................',
      '................',
      '................',
    ]),
  bars: () =>
    parse([
      '................',
      '................',
      '................',
      '...OOOOOOOOOO...',
      '...OOOOOOOOOO...',
      '................',
      '................',
      '...OOOOOOOOOO...',
      '...OOOOOOOOOO...',
      '................',
      '................',
      '...OOOOOOOOOO...',
      '...OOOOOOOOOO...',
      '................',
      '................',
      '................',
    ]),
  chat: () =>
    stack(
      drawn([
        '................',
        '................',
        '..wwwwwwwwwwww..',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '.wwwwwwwwwwwwww.',
        '..wwwwwwwwwwww..',
        '...www..........',
        '...ww...........',
        '...w............',
        '................',
        '................',
        '................',
      ]),
      parse([
        '................',
        '................',
        '................',
        '................',
        '................',
        '....OO.OO.OO....',
        '....OO.OO.OO....',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
      ])
    ),
  // 化身：一个人加一颗星
  avatar: () =>
    stack(
      drawn([
        '................',
        '................',
        '.....kkkkkk.....',
        '....kkkkkkkk....',
        '....kkkkkkkk....',
        '....ssssssss....',
        '....skssssks....',
        '....ssssssss....',
        '.....ssssss.....',
        '...GGGGwwGGGG...',
        '..GGGGGGGGGGGG..',
        '..GGGGGGGGGGGG..',
        '..GGGGGGGGGGGG..',
        '................',
        '................',
        '................',
      ]),
      drawn([
        '................',
        '.............y..',
        '............yyy.',
        '.............y..',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
      ])
    ),
  // 录像中：时钟牌右上角的红灯，左上一点亮
  rec: () =>
    outline(
      radial((dx, dy) =>
        Math.hypot(dx, dy) > 3.3 ? null : Math.hypot(dx + 1.2, dy + 1.2) < 1.3 ? 'p' : 'r'
      )
    ),
  // 开始、暂停：画在绿色按钮上，白色、不描边
  play: () =>
    parse([
      '................',
      '................',
      '................',
      '.....w..........',
      '.....www........',
      '.....wwwww......',
      '.....wwwwwww....',
      '.....wwwwwwww...',
      '.....wwwwwww....',
      '.....wwwww......',
      '.....www........',
      '.....w..........',
      '................',
      '................',
      '................',
      '................',
    ]),
  pause: () =>
    parse([
      '................',
      '................',
      '................',
      '....OOO..OOO....',
      '....OOO..OOO....',
      '....OOO..OOO....',
      '....OOO..OOO....',
      '....OOO..OOO....',
      '....OOO..OOO....',
      '....OOO..OOO....',
      '....OOO..OOO....',
      '....OOO..OOO....',
      '................',
      '................',
      '................',
      '................',
    ]),
}

export type PixelName = keyof typeof SHAPES
const urls = new Map<string, string>()

/** 图标的 data URI：横向相同颜色并成一个矩形，量很小 */
export function pixelIconUrl(name: string): string {
  const known = urls.get(name)
  if (known) return known
  const cells = (SHAPES[name] ?? SHAPES.help)()
  let rects = ''
  cells.forEach((row, y) => {
    for (let x = 0; x < row.length;) {
      const v = row[x]
      let end = x
      while (v && row[end + 1] === v) end++
      if (v)
        rects += `<rect x="${x}" y="${y}" width="${end - x + 1}" height="1" fill="${PALETTE[v]}"/>`
      x = end + 1
    }
  })
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16" shape-rendering="crispEdges">${rects}</svg>`
  const url = `data:image/svg+xml,${encodeURIComponent(svg)}`
  urls.set(name, url)
  return url
}

/** 一枚像素图标：scale 只给整数，2 倍是 32 像素 */
export function pixelIcon(name: PixelName, scale = 2) {
  const img = document.createElement('img')
  img.className = 'pixel-icon'
  img.src = pixelIconUrl(name)
  img.width = 16 * scale
  img.height = 16 * scale
  img.alt = ''
  img.draggable = false
  img.dataset.pixel = name
  return img
}

/** 换一枚图标（天气、开始/暂停跟着状态变）：同一个 img 只改地址 */
export function setPixelIcon(img: HTMLImageElement, name: PixelName) {
  if (img.dataset.pixel === name) return
  img.dataset.pixel = name
  img.src = pixelIconUrl(name)
}

/** 模板里的 <i data-pixel="名字" data-scale="1"></i> 换成图标 */
export function decoratePixels(root: ParentNode) {
  for (const mark of root.querySelectorAll<HTMLElement>('i[data-pixel]')) {
    const name = mark.dataset.pixel as PixelName
    mark.replaceWith(pixelIcon(name, Number(mark.dataset.scale ?? 2)))
  }
}
