import type { Scenery } from './scenery'

// 明信片上的封面：一个小镇一张全景小图。预览建好后当场拍一张（GameMap.cover），存在这台设备上，
// 下次打开选镇页就是上次看到的样子；还没拍过的，随应用带的地图和剧本各有一张拍好的
// （assets/covers/<小镇编号>.jpg，重演页按整图机位拍的），玩家自己建的小镇返回 undefined。
const bundled = import.meta.glob<string>('../assets/covers/*.jpg', {
  eager: true,
  query: '?url',
  import: 'default',
})
const BUNDLED = new Map(
  Object.entries(bundled).map(([path, url]) => [path.slice(path.lastIndexOf('/') + 1, -4), url])
)
/** 随应用带的封面拍的是哪一刻：各镇最好看的时候。还没玩过时预览也照它画（断楼城是霓虹亮起的夜里，
 *  温泉谷是下着雪的傍晚），实拍的封面和它是一个样子；玩过以后照存档停下的那一刻 */
const SIGNATURE: Record<string, Scenery> = {
  'default-town': { minutes: 17 * 60, weather: 'clear' },
  'spring-valley': { minutes: 17 * 60 + 30, weather: 'snow' },
  'broken-towers': { minutes: 21 * 60, weather: 'clear' },
  'prefab-battle-royale': { minutes: 10 * 60 + 30, weather: 'clear' },
  'prefab-swordholder': { minutes: 21 * 60, weather: 'clear' },
  'prefab-werewolf': { minutes: 22 * 60, weather: 'clear' },
}
/** 这个小镇最好看的时刻和天气；玩家自己建的小镇没有 */
export const signatureOf = (id: string): Scenery | undefined => SIGNATURE[id]
/** 封面的宽高（像素）：明信片上显示成一半大，高分屏也清楚 */
export const COVER_SIZE = [384, 226] as const
const PREFIX = 'town:cover:'
/** 本机最多留这么多张拍的封面，再多就丢掉最早拍的 */
const KEEP = 24

interface Saved {
  at: number
  url: string
}

function read(id: string): Saved | undefined {
  try {
    const saved = JSON.parse(localStorage.getItem(PREFIX + id) ?? 'null') as Saved | null
    return saved && typeof saved.url === 'string' ? saved : undefined
  } catch {
    return undefined
  }
}

/** 这个小镇的封面地址；没有时为 undefined */
export function coverOf(id: string): string | undefined {
  return read(id)?.url ?? BUNDLED.get(id)
}

/** 记下刚拍的封面。存不下（本机存储满了、不可用）就算了，下次打开再拍 */
export function saveCover(id: string, url: string) {
  try {
    localStorage.setItem(PREFIX + id, JSON.stringify({ at: Date.now(), url } satisfies Saved))
    const kept: [string, number][] = []
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i)
      if (key?.startsWith(PREFIX)) kept.push([key, read(key.slice(PREFIX.length))?.at ?? 0])
    }
    kept.sort((a, b) => b[1] - a[1])
    for (const [key] of kept.slice(KEEP)) localStorage.removeItem(key)
  } catch {
    // 只在这次打开里用得上
  }
}

/** 小镇删掉、重新开始后不留它的封面 */
export function dropCover(id: string) {
  try {
    localStorage.removeItem(PREFIX + id)
  } catch {
    // 留着也只是一张旧图
  }
}
