// 明信片上的封面：一个小镇一张全景小图。随应用带的地图和剧本各带一张拍好的
// （assets/covers/<小镇编号>.jpg，重演页按整图机位拍的）；玩家自己建的小镇还没有封面时返回 undefined。
const bundled = import.meta.glob<string>('../assets/covers/*.jpg', {
  eager: true,
  query: '?url',
  import: 'default',
})
const BUNDLED = new Map(
  Object.entries(bundled).map(([path, url]) => [path.slice(path.lastIndexOf('/') + 1, -4), url])
)

/** 这个小镇的封面地址；没有时为 undefined */
export function coverOf(id: string): string | undefined {
  return BUNDLED.get(id)
}
