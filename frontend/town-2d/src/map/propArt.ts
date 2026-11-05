import { el } from 'town-shared/svg'
import { registerPropArtwork } from 'town-shared/props/picture'
import './propArt.css'

// 道具像素图：文件名与定义 ID（去掉 core:）一致；功能版本共用素材，实例 ID 不参与匹配。
// 由原来的手绘图缩成 24 格像素图，没有手绘图的几种单独画。玩家照着内置道具改的变体
// （shipwreck:island-palms）编号后半段和内置道具同名时沿用同一张图。
const files = import.meta.glob<string>('../assets/props/pixel/*.png', {
  eager: true,
  query: '?url',
  import: 'default',
})
export const PROP_ART_SIZE = 72
/** 屋里的家具挨得近时缩小，最小到这么大 */
export const PROP_ART_MIN = 40

/** 四张书本封面（棕、绿、蓝、紫）：书没有单画的封面时用 */
const BOOK_COVERS = [1, 2, 3, 4].map((n) => files[`../assets/props/pixel/book-${n}.png`])

/** 按编号给一本书挑封面，同一本书每次都是同一张 */
export function bookCover(id: string) {
  let hash = 0
  for (const c of id) hash = (hash * 31 + c.charCodeAt(0)) >>> 0
  return BOOK_COVERS[hash % BOOK_COVERS.length]
}

export function propArtwork(reference: string): string | undefined {
  const id = reference.split('@')[0]
  const [namespace, name] = id.split(':')
  if (!name) return undefined
  const own = files[`../assets/props/pixel/${name}.png`]
  if (own) return own
  if (namespace !== 'core') return undefined
  // 内置的书 book-5、book-6……没有单画的封面：按编号轮流用四张，相邻几本颜色不同
  const n = Number(/^book-(\d+)$/.exec(name)?.[1])
  return n ? BOOK_COVERS[(n - 1) % BOOK_COVERS.length] : undefined
}

// 道具列表、设定中心的道具图也用同一套像素图
registerPropArtwork(propArtwork)

/** 保留原 glyph 作为加载中/失败时的回退；图片和透明点击框共用原实例的事件。size 是图片边长（地图单位） */
export function addPropArtwork(shape: SVGGElement, url: string, size = PROP_ART_SIZE) {
  const box = { x: -size / 2, y: -size / 2, width: size, height: size }
  const image = el('image', {
    ...box,
    class: 'prop-art-image',
    preserveAspectRatio: 'xMidYMid meet',
    'pointer-events': 'none',
  })
  image.addEventListener('load', () => shape.classList.add('prop-art-ready'), { once: true })
  image.addEventListener('error', () => shape.classList.remove('prop-art-ready'), { once: true })
  image.setAttribute('href', url)
  shape.append(image, el('rect', { ...box, class: 'prop-art-target', rx: 5 }))
}
