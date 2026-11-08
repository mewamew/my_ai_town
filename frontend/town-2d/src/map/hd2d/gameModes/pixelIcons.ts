// 玩法界面的像素图标：16×16 平涂，照村民头像的画法（近黑描边，一种材质一两个颜色，不画光影），
// 外面自动描一圈边，成图 18×18，只按整数倍显示。各玩法自己画图标，这里只管画成图。

const OUTLINE = '#141014'

/** 一个图标：调色板和 16 行字符，'.' 是透明 */
export type PixelIcon = { pal: Record<string, string>; rows: string[] }

const painted = new Map<string, string>()

/** 一个图标画成 18×18 的图（描边一格），按 key 缓存成 data URL */
function paint(key: string, { rows, pal }: PixelIcon) {
  const cached = painted.get(key)
  if (cached) return cached
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
export function iconImage(key: string, icon: PixelIcon, scale: number, className: string) {
  const img = document.createElement('img')
  img.src = paint(key, icon)
  img.alt = ''
  img.className = className
  img.width = 18 * scale
  img.height = 18 * scale
  return img
}
