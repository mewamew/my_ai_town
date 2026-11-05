import type { MapDocument } from 'town-shared/mapDocument'
import type { MapTheme, ThemeId } from './types'
import { DEFAULT_PRESET, STYLE_PRESETS } from './presets'
import { village } from './village'
import { wasteland } from './wasteland'
import { frozen } from './frozen'

export type { MapTheme, ThemeId } from './types'
export { village }

const PACKS: Record<ThemeId, MapTheme> = { village, wasteland, frozen }

/** 建镇参数里的环境预设 → 风格包，名单见 presets.ts；没有预设（默认小镇、旧存档）按默认风格 */
const PRESETS = new Map<string, MapTheme>(STYLE_PRESETS.map((p) => [p.id, PACKS[p.theme]]))

export function themeOf(document: Pick<MapDocument, 'generation'>): MapTheme {
  const theme =
    PRESETS.get(document.generation?.spec?.environment?.preset ?? '') ?? PACKS[DEFAULT_PRESET.theme]
  // 野外小径、环岛小径（荒岛、野地）：路边不立路灯
  const settlement = document.generation?.spec?.settlement
  return settlement === 'wild' || settlement === 'ring' ? { ...theme, lamp: 'none' } : theme
}
