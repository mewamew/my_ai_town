// 把录像读成剧本：谁在几点说了什么、想了什么，世界日志里发生了什么，按先后列出来。
// 拍素材前用它找片段，镜头单里的 from 可以直接抄这里的小镇时钟或录像毫秒。
//
//   node scripts/replay/script.mjs <小镇> --reels                列出录下的几卷
//   node scripts/replay/script.mjs <小镇> [--reel 卷] [--who 林晚] [--grep 关键词]
//                                  [--from "D2 05:00"] [--to "D2 06:00"] [--only speech,thought,event]
//
// 小镇目录按 AI_TOWN_HOME（或系统默认的数据目录）找；--reel 不给时读最新的一卷。
import { clockMinutes, listReels, loadReel, scriptOf } from './reels.mjs'

const args = process.argv.slice(2)
const option = (name) => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}
const town = args[0]
if (!town || town.startsWith('--')) {
  console.error(
    '用法：node scripts/replay/script.mjs <小镇> [--reels] [--reel 卷] [--who 名字] [--grep 词] [--from 时钟] [--to 时钟]'
  )
  process.exit(2)
}

if (args.includes('--reels')) {
  for (const { id, header } of listReels(town)) {
    const start = new Date(header.started_at).toLocaleString('zh-CN', { hour12: false })
    const minutes = header.ended_at
      ? Math.round((header.ended_at - header.started_at) / 60000)
      : '录像中'
    console.log(`${id}  ${start}  ${header.from_clock} → ${header.to_clock}  ${minutes} 分钟`)
  }
  process.exit(0)
}

const reel = loadReel(town, option('--reel'))
const who = option('--who')
const grep = option('--grep')
const from = option('--from') ? clockMinutes(option('--from')) : -Infinity
const to = option('--to') ? clockMinutes(option('--to')) : Infinity
const only = new Set((option('--only') ?? 'speech,thought,event').split(','))
const LABEL = { speech: '说', thought: '心想', event: '·' }

console.log(`# ${reel.id}  ${reel.header.from_clock} → ${reel.header.to_clock}`)
for (const beat of scriptOf(reel).beats) {
  const minutes = clockMinutes(beat.clock)
  if (minutes < from || minutes > to || !only.has(beat.kind)) continue
  if (who && beat.who !== who) continue
  if (grep && !beat.text.includes(grep)) continue
  const t = (beat.t / 1000).toFixed(1).padStart(7)
  const line = beat.kind === 'event' ? beat.text : `${beat.who} ${LABEL[beat.kind]}：${beat.text}`
  console.log(`${t}s  ${beat.clock}  ${line}`)
}
