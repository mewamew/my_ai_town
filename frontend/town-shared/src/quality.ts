// 地图画质：只影响本机画面，存在浏览器里。「自动」在触屏设备上用「中」，省电、不容易发热。
import { isTouch } from './platform'

export type QualityChoice = 'auto' | 'ultra' | 'high' | 'mid' | 'low'
export type Quality = Exclude<QualityChoice, 'auto'>

const KEY = 'town-2d:hd-quality'
const CHOICES: QualityChoice[] = ['auto', 'ultra', 'high', 'mid', 'low']

export const qualityLabels: Record<QualityChoice, string> = {
  auto: '自动',
  ultra: '极致',
  high: '高',
  mid: '中',
  low: '低',
}
export const qualityNotes: Record<QualityChoice, string> = {
  auto: '按设备选：手机、平板用「中」，电脑用「高」；跑不动时自动降一档',
  ultra: '给 Apple 芯片和独立显卡的电脑：体积光、倒影更细，散景采样加倍，草丛最密',
  high: '最高 2 倍分辨率：散景景深、体积光和晨雾、水面倒影、多重采样都开',
  mid: '最高 1.5 倍分辨率：两遍高斯的移轴模糊，海面只反射天色，草丛一半',
  low: '1 倍分辨率：只留地面灯光、时段光色和像素采样，最省电',
}

export function storedQuality(): QualityChoice {
  try {
    const value = localStorage.getItem(KEY) as QualityChoice | null
    return value && CHOICES.includes(value) ? value : 'auto'
  } catch {
    return 'auto'
  }
}

export function saveQuality(choice: QualityChoice) {
  try {
    localStorage.setItem(KEY, choice)
  } catch {
    // 存储不可用时只本次生效
  }
}

/** 实际用的档位 */
export function effectiveQuality(choice = storedQuality()): Quality {
  return choice === 'auto' ? (isTouch() ? 'mid' : 'high') : choice
}

/** 这一档的像素比上限 */
export function pixelRatioCap(quality: Quality) {
  return quality === 'ultra' || quality === 'high' ? 2 : quality === 'mid' ? 1.5 : 1
}

/** 失焦模糊：画面上离焦点（选中的人）远的地方糊多少。默认「轻」，「电影感」是原来的强度 */
export type DepthBlur = 'off' | 'light' | 'cinema'

const BLUR_KEY = 'town-2d:hd-blur'
const BLURS: DepthBlur[] = ['off', 'light', 'cinema']

export const depthBlurLabels: Record<DepthBlur, string> = {
  off: '关',
  light: '轻',
  cinema: '电影感',
}
export const depthBlurNotes: Record<DepthBlur, string> = {
  off: '整个画面都清楚',
  light: '离焦点远的地方稍微柔一点；焦点跟着选中的人',
  cinema: '像拍微缩模型：焦点上下和远处都糊，人站在画面边上时另一半全糊',
}

export function storedDepthBlur(): DepthBlur {
  try {
    const value = localStorage.getItem(BLUR_KEY) as DepthBlur | null
    return value && BLURS.includes(value) ? value : 'light'
  } catch {
    return 'light'
  }
}

export function saveDepthBlur(level: DepthBlur) {
  try {
    localStorage.setItem(BLUR_KEY, level)
  } catch {
    // 存储不可用时只本次生效
  }
}
