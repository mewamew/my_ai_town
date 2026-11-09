// 一天里的天光：太阳多高，此刻白天、夜、蓝调、金色时刻各占几成。
// 立体场景打光（scene.ts 的 applyLight）和选镇页赏景的天色轨道（launcher/scenery.ts）共用这一份，
// 轨道上画的颜色就是场景那一刻的天色。这里不引用 three，选镇页不必为了几个颜色提前载入它。

const smooth = (a: number, b: number, x: number) => {
  const t = Math.max(0, Math.min(1, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}

export interface Daylight {
  /** 太阳高度：正午 1，6 点和 18 点 0，半夜 -1 */
  e: number
  day: number
  night: number
  /** 蓝调：日落后到天黑前约四十分钟（e 从 0 降到 -0.25），日出前对称一段；环境光发蓝、灯已亮 */
  twilight: number
  /** 金色时刻，按晴天算；有云时调用方再乘 1 - 云量 */
  golden: number
}

/** hour 是 0～24 的钟点 */
export function daylight(hour: number): Daylight {
  const e = Math.sin(((hour - 6) / 12) * Math.PI)
  const day = smooth(-0.02, 0.25, e),
    night = 1 - smooth(-0.32, -0.12, e)
  const twilight = smooth(-0.3, -0.08, e) * (1 - smooth(-0.04, 0.1, e)) * (1 - night)
  const golden = Math.max(0, 1 - Math.abs(e - 0.1) / 0.25) * day
  return { e, day, night, twilight, golden }
}

const toLinear = (c: number) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)
const toSrgb = (c: number) => (c <= 0.0031308 ? c * 12.92 : 1.055 * c ** (1 / 2.4) - 0.055)
const linear = (hex: string) =>
  [1, 3, 5].map((i) => toLinear(parseInt(hex.slice(i, i + 2), 16) / 255))

/** 风格包的一组天色在这个钟点（晴天）混出来的颜色，返回 sRGB 的 0～255。
 *  和场景的 phase 同一个次序：夜 → 白天，再往蓝调、金色时刻靠，在线性空间里混（three 的颜色也是）；
 *  warm 是金色时刻往暖色靠多少（场景里天色 0.55、天顶 0.45） */
export function skyTone(
  palette: { day: string; night: string; blue: string; golden: string },
  hour: number,
  warm: number
): [number, number, number] {
  const { day, twilight, golden } = daylight(hour)
  const mix = (a: number[], b: number[], t: number) => a.map((v, i) => v + (b[i] - v) * t)
  const c = mix(
    mix(mix(linear(palette.night), linear(palette.day), day), linear(palette.blue), twilight),
    linear(palette.golden),
    golden * warm
  )
  return c.map((v) => Math.round(toSrgb(Math.max(0, Math.min(1, v))) * 255)) as [
    number,
    number,
    number,
  ]
}
