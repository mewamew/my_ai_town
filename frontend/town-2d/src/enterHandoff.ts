// 从选镇页进小镇时的交接：选镇页把最后一帧画面、连同已经飞到左上角的时钟牌、开始钮和头像（定了形的一份
// 拷贝）记在这次会话里；游戏页（gameEntry.ts）加载时把它们垫在最上面，场景建好再淡出，露出同一位置上
// 真的那几样。两页是两份文档，样式表也不同，所以拷贝把用到的样式都写在元素自己身上。

const KEY = 'town:enter'
/** 交接只在跳转那一下有效：隔了这么久（刷新、后退再进）就不用了 */
const FRESH_MS = 30_000
/** 定形时抄下来的样式 */
const STYLES = [
  'position',
  'left',
  'top',
  'width',
  'height',
  'box-sizing',
  'display',
  'flex',
  'flex-direction',
  'align-items',
  'justify-content',
  'justify-items',
  'align-content',
  'gap',
  'grid-template-columns',
  'margin',
  'padding',
  'border',
  'border-radius',
  'background-color',
  'box-shadow',
  'color',
  'font',
  'font-variant-numeric',
  'letter-spacing',
  'white-space',
  'overflow',
  'text-overflow',
  'opacity',
  'image-rendering',
]

export interface Handoff {
  /** 选镇页最后一帧（JPEG 的 data URL） */
  image: string
  /** 飞到位的几样东西，定了形的 HTML */
  ghost: string
}

/** 一份不靠样式表的拷贝：每个元素算出来的样式写在自己身上，类名和编号去掉 */
function freeze(source: HTMLElement): HTMLElement {
  const copy = source.cloneNode(true) as HTMLElement
  const from = [source, ...source.querySelectorAll<HTMLElement>('*')]
  const to = [copy, ...copy.querySelectorAll<HTMLElement>('*')]
  from.forEach((element, i) => {
    const style = getComputedStyle(element)
    const target = to[i]
    for (const name of ['class', 'id', 'hidden', 'title', 'aria-label', 'role', 'disabled'])
      target.removeAttribute(name)
    target.style.cssText = STYLES.map((name) => `${name}:${style.getPropertyValue(name)}`).join(';')
  })
  copy.setAttribute('aria-hidden', 'true')
  return copy
}

/** 选镇页：记下最后一帧和飞到位的那几样。存不下就不交接，游戏页照旧显示加载页 */
export function saveHandoff(mapId: string, image: string, pieces: HTMLElement[]) {
  try {
    const ghost = document.createElement('div')
    ghost.append(...pieces.map(freeze))
    sessionStorage.setItem(
      KEY,
      JSON.stringify({ map: mapId, at: Date.now(), image, ghost: ghost.innerHTML })
    )
  } catch {
    // 会话存储满了或不可用
  }
}

/** 游戏页：取走给这个小镇的交接（只用一次）；没有、不是这个镇的或过期了返回 undefined */
export function takeHandoff(mapId: string): Handoff | undefined {
  try {
    const saved = JSON.parse(sessionStorage.getItem(KEY) ?? 'null') as
      (Handoff & { map: string; at: number }) | null
    sessionStorage.removeItem(KEY)
    if (!saved || saved.map !== mapId || Date.now() - saved.at > FRESH_MS) return undefined
    return typeof saved.image === 'string' && typeof saved.ghost === 'string' ? saved : undefined
  } catch {
    return undefined
  }
}
