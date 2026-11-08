// 外观只归客户端管理。道具包携带外观，服务端只接收功能定义。
import type { Appearance } from './types'
export const defaultAppearance: Appearance = { glyph: 'box', color: '#b79a70' }
const prefix = 'town-prop-appearance:'
const sessionAppearances = new Map<string, Appearance>()
export function validateAppearance(value: unknown): Appearance {
  if (!value || typeof value !== 'object') throw new Error('外观格式无效')
  const a = value as Appearance
  if (
    !['box', 'bed', 'book', 'plant', 'machine'].includes(a.glyph) ||
    !/^#[0-9a-f]{6}$/i.test(a.color)
  )
    throw new Error('外观图形或颜色无效')
  if (
    a.image &&
    (a.image.length > 1500000 ||
      !/^data:image\/(png|webp|jpeg);base64,[a-z0-9+/=]+$/i.test(a.image))
  )
    throw new Error('图片须为不超过 1 MB 的 PNG、JPEG 或 WebP')
  return {
    glyph: a.glyph,
    color: a.color,
    ...(a.image ? { image: a.image } : {}),
  }
}
export function savedAppearance(reference: string): Appearance | null {
  const cached = sessionAppearances.get(reference)
  if (cached) return cached
  try {
    const a = localStorage.getItem(prefix + reference)
    return a ? validateAppearance(JSON.parse(a)) : null
  } catch {
    return null
  }
}
/** 删掉道具以后清掉它的外观；镇上还用着的版本别清，地图画它还要用 */
export function forgetAppearance(reference: string) {
  sessionAppearances.delete(reference)
  try {
    localStorage.removeItem(prefix + reference)
  } catch {
    // 本机存储不能用时本来也没存下
  }
}
export function saveAppearance(reference: string, value: Appearance) {
  const appearance = validateAppearance(value)
  sessionAppearances.set(reference, appearance)
  try {
    localStorage.setItem(prefix + reference, JSON.stringify(appearance))
  } finally {
    window.dispatchEvent(new Event('prop-appearance-changed'))
  }
}
