/** 模拟时钟与错误文本的统一格式。 */
const MINUTES_PER_DAY = 1440

function dayAndTime(at: number): { day: number; time: string } {
  const minutes = Math.floor(at)
  const day = Math.floor(minutes / MINUTES_PER_DAY) + 1
  const hour = String(Math.floor((minutes % MINUTES_PER_DAY) / 60)).padStart(2, '0')
  const minute = String(minutes % 60).padStart(2, '0')
  return { day, time: `${hour}:${minute}` }
}

/** 「第 N 天 HH:MM」，用于聊天记录与记忆页。 */
export function clock(at: number): string {
  const { day, time } = dayAndTime(at)
  return `第 ${day} 天 ${time}`
}

/** 「11:47」；和 now 不在同一天时写「第 2 天 08:47」 */
export function clockNear(at: number, now: number): string {
  const { day, time } = dayAndTime(at)
  return day === dayAndTime(now).day ? time : `第 ${day} 天 ${time}`
}

/** 「DN HH:MM」，与服务端 roster 的 clock 字段同一种写法。 */
export function shortClock(at: number): string {
  const { day, time } = dayAndTime(at)
  return `D${day} ${time}`
}

/** 服务端文字里的「D3」「D3 07:00」改成界面统一的「第 3 天」写法。 */
export function displayClock(text: string): string {
  return text.replace(/(^|[^A-Za-z0-9_])D(\d+)(?![A-Za-z0-9_])/g, '$1第 $2 天')
}

/** 一天里的分钟数 → 「07:24」 */
const clockOfMinute = (minute: number) => {
  const m = ((Math.round(minute) % 1440) + 1440) % 1440
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`
}

/** 小数收短：十以上取整，一以上留一位，一以下留两位有效数字 */
const shortNumber = (value: number) => {
  const a = Math.abs(value)
  const text =
    a >= 10 ? String(Math.round(value)) : a >= 1 ? value.toFixed(1) : value.toPrecision(2)
  return text.includes('.') ? text.replace(/\.?0+$/, '') : text
}

/**
 * 服务端写的叙述（事件、回执、日志、记忆）显示给玩家前的收拾：日子改成「第 3 天」，
 * 去掉写给模型看的部分——工具提示、作品实例编号、互动编号、括号里的内部编号（模型写记忆时会照抄），
 * 「第 1 天 420–444 分钟」改成钟点，两位以上的小数收短。模型那边看到的原文不变。
 */
/** 需求恢复了：玩家看的说法 */
const RESTORED = {
  饱腹: '吃饱了些',
  水分: '解了渴',
  精力: '恢复了些精力',
  健康: '身体好了些',
}

export function playerText(text: string): string {
  return (
    displayClock(text)
      .replace(/[；;，,]?\s*可用 [a-z_]+ [^；;。\n]*/g, '')
      .replace(/[，,]\s*实例\s*[^\s，,；;。]+/g, '')
      .replace(/》版本 \d+，/g, '》，')
      .replace(/\s*\b[a-z]+\/[0-9a-f]{8,}\/\d+/g, '')
      .replace(/\s*[（(]\s*[a-z][a-z0-9]*(?:[_:@.-][a-z0-9_@.-]+)+\s*[)）]/g, '')
      .replace(/；已发生的移动和身体变化保留/g, '')
      .replace(
        /(第\s*\d+\s*天)\s*(\d+)\s*[–—~～-]\s*(\d+)\s*分钟/g,
        (_, day: string, from: string, to: string) =>
          `${day} ${clockOfMinute(Number(from))}–${clockOfMinute(Number(to))}`
      )
      // 每分钟零点几点看不出快慢，换成每小时
      .replace(
        /每分钟(恢复|损失|消耗|下降)\s*(\d+(?:\.\d+)?)\s*点/g,
        (_, verb: string, rate: string) => `每小时${verb}约 ${shortNumber(Number(rate) * 60)} 点`
      )
      // 物资的份数、需求恢复的点数是给模型的账：玩家看「解了渴」「吃饱了些」就够
      .replace(/[：:]\s*消耗\s*\d+\s*份[，,]\s*剩余\s*\d+\s*份/g, '')
      .replace(/[；;]?\s*来源剩余\s*\d+\s*份/g, '')
      .replace(
        /(饱腹|水分|精力|健康)恢复\s*\d+(?:\.\d+)?\s*点/g,
        (_, need: keyof typeof RESTORED) => RESTORED[need]
      )
      .replace(/\d+\.\d{2,}/g, (n) => shortNumber(Number(n)))
  )
}

/** 文件大小：1.2 GB、36.5 MB、80 KB（按 1024 进位，不到 1 KB 也写 1 KB） */
export function fileSize(n: number): string {
  if (n >= 1024 * 1024 * 1024) return `${(n / 1024 / 1024 / 1024).toFixed(1)} GB`
  if (n >= 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`
  return `${Math.max(1, Math.round(n / 1024))} KB`
}

/** 抛出的东西不一定是 Error；给用户看的文字只要 message。 */
export function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}
