// HD-2D 像素头像按长相编号出图：捏过长相的用长相本身当编号，没捏过的用模板编号；
// 只知道居民编号时通过登记表找。画法在 town-2d（villagerSprite.ts），启动时登记进来。
import type { PopulationView, ResidentRegistration, VillagerLook } from './protocol'

export type Facing = 'down' | 'right' | 'up' | 'left'

/** 捏人界面要的画法 */
export interface VillagerArt {
  /** 一帧的宽高（像素） */
  frame: readonly [number, number]
  /** 按长相把一帧画到 (x, y)：朝向，第几帧（0～3，1、3 是迈步） */
  drawFrame(
    ctx: CanvasRenderingContext2D,
    look: VillagerLook,
    facing: Facing,
    frame: number,
    x: number,
    y: number
  ): void
  /** 编号对应的长相：捏过的照原样，预制村民是固定长相，其余按编号随机 */
  lookOf(key: string): VillagerLook
}

interface PortraitSource {
  url(key: string): string | undefined
  art?: VillagerArt
}
let source: PortraitSource | undefined
export function registerPortraits(next: PortraitSource) {
  source = next
}

/** 捏人界面用的画法；地图还没登记时为 undefined */
export function villagerArt(): VillagerArt | undefined {
  return source?.art
}

const LOOK_PREFIX = 'look:'
/** 长相编号里的字段顺序：同一套长相不管字段先后，编号都一样，头像只出一次图 */
const LOOK_KEYS: (keyof VillagerLook)[] = [
  'hair',
  'outfit',
  'hair_color',
  'hair_tip',
  'eye_color',
  'skin',
  'top',
  'bottom',
  'accent',
  'collar',
  'apron',
  'belt',
  'ornament',
  'headband',
  'hat',
  'ahoge',
  'clip',
  'beard',
  'headwear',
  'face',
  'beard_style',
  'held',
  'pattern',
]

/** 捏过的长相当出图编号用 */
export function lookKey(look: VillagerLook): string {
  const tidy: Record<string, unknown> = {}
  for (const key of LOOK_KEYS) {
    const value = look[key]
    if (value !== undefined && value !== false) tidy[key] = value
  }
  return LOOK_PREFIX + JSON.stringify(tidy)
}

/** 长相编号读回长相；不是长相编号或写坏了返回 undefined */
export function decodeLookKey(key: string): VillagerLook | undefined {
  if (!key.startsWith(LOOK_PREFIX)) return undefined
  try {
    const look = JSON.parse(key.slice(LOOK_PREFIX.length)) as VillagerLook
    return typeof look.hair === 'string' && typeof look.outfit === 'string' ? look : undefined
  } catch {
    return undefined
  }
}

/** 出图用的编号：捏过长相用长相，否则模板编号；没有模板的旧居民用居民编号 */
export function portraitKey(resident: {
  id: string
  template_id?: string
  appearance?: { look?: VillagerLook }
}) {
  const look = resident.appearance?.look
  return look ? lookKey(look) : (resident.template_id ?? resident.id)
}

/** 村民库里一份模板的出图编号 */
export function templateKey(template: {
  template_id: string
  appearance?: { look?: VillagerLook }
}) {
  return portraitKey({ id: template.template_id, appearance: template.appearance })
}

export function portraitFor(key: string): string | undefined {
  return source?.url(key)
}

/** 当前人口：村民页每收到一份就整份替换。只知道居民编号的页面（记忆页、设定的长相页）靠它找头像和登记 */
let population: PopulationView | null = null
let residentKeys = new Map<string, string>()
const populationListeners = new Set<() => void>()

export function rememberPopulation(next: PopulationView) {
  population = next
  residentKeys = new Map(next.residents.map((r) => [r.id, portraitKey(r)]))
  for (const listener of populationListeners) listener()
}

/** 人口变了就通知；返回取消订阅 */
export function onPopulation(listener: () => void) {
  populationListeners.add(listener)
  return () => populationListeners.delete(listener)
}

export function currentPopulation(): PopulationView | null {
  return population
}

export function registrationOf(id: string): ResidentRegistration | undefined {
  return population?.residents.find((r) => r.id === id)
}

/** 按入住登记的先后排；人口还没到或没登记的照原顺序排在后面。名册按地点分组，人一走动顺序就变，
 *  头像条和角色卡换人要一个固定的顺序 */
export function byJoinOrder<T>(items: T[], id: (item: T) => string): T[] {
  const rank = new Map(population?.residents.map((r, i) => [r.id, i]))
  return items
    .map((item, i) => ({ item, key: rank.get(id(item)) ?? rank.size + i }))
    .sort((a, b) => a.key - b.key)
    .map(({ item }) => item)
}

/** 居民编号 → 出图编号 */
export function residentPortraitKey(id: string): string {
  return residentKeys.get(id) ?? id
}

export function residentPortraitUrl(id: string): string | undefined {
  return portraitFor(residentPortraitKey(id))
}

/** 有头像时显示像素图；尚未登记时显示名字首字。 */
export function residentPortrait(id: string, name: string) {
  const frame = document.createElement('span')
  frame.className = 'resident-portrait'
  const src = residentPortraitUrl(id)
  if (src) {
    const img = document.createElement('img')
    img.src = src
    img.alt = `${name}的像素头像`
    frame.append(img)
  } else frame.textContent = name.slice(0, 1)
  return frame
}

export function portraitOf(id: string, name: string, imageClass: string): HTMLElement | null {
  const url = residentPortraitUrl(id)
  if (!url) return null
  const img = document.createElement('img')
  img.className = imageClass
  img.src = url
  img.alt = `${name}的像素头像`
  return img
}
