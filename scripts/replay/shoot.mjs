// 按镜头单把录像拍成视频：在无头 Chrome 里用游戏自己的画面重演录像（game.html?replay），一帧一帧往前走、
// 按镜头单摆机位、截图，交给 ffmpeg 拼成 mp4；同时出台词、心声两份字幕和一张样片图（抽几帧拼成一张，
// 用来检查有没有被挡、出画）。世界不开、模型不调，同一段拍多少遍都一样。
//
//   node scripts/replay/shoot.mjs <镜头单.json> [--draft] [--out 目录] [--base http://127.0.0.1:5174]
//
// --draft 出小样：1280×720、30 帧，几分钟就好；不加是成片：镜头单里的尺寸和帧率（缺省 3840×2160、60 帧）。
// --base 是正在跑的前端（pnpm dev 或 preview），缺省 5174。小镇目录按 AI_TOWN_HOME（或系统默认）找。
//
// 镜头单（距离单位是米，角度是度，时刻是录像里的小镇时钟或离这一卷开头的毫秒）：
// {
//   "town": "town-6e07…", "reel": "20261107T044056Z",       // reel 不写用最新的一卷
//   "size": [3840, 2160], "fps": 60,
//   "ui": { "names": true, "bubbles": true },                // 名字、头顶气泡留不留，缺省都留
//   "clips": [{
//     "name": "03_林晚等周屿_推拉", "from": "D2 05:42", "seconds": 15,
//     "camera": [
//       { "at": 0, "set": { "follow": "林晚", "width": 8, "yaw": 40, "pitch": 44 }, "focus": "林晚", "blur": "cinema" },
//       { "at": 4, "move": { "at": "center", "width": "all", "yaw": 0, "pitch": 36 }, "seconds": 3, "focus": null },
//       { "at": 7, "move": { "follow": "周屿", "width": 14 }, "seconds": 3, "focus": "周屿" }
//     ]
//   }]
// }
// 机位：follow 跟住谁（名字或编号）；at 对准哪（[x, y] 米、"center" 地图中间，或某人此刻站的地方）；
// width 画面横着看得见多少米（"all" 整张图）；yaw 转角，pitch 俯角（30–82）。move 用 seconds 秒慢起慢停地过去。
import { spawn, spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { launch, sleep } from './chrome.mjs'
import { loadMap, loadReel, scriptOf, segmentsFor, timeOfClock, townName } from './reels.mjs'

const args = process.argv.slice(2)
const option = (name, fallback) => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : fallback
}
const listFile = args.find(
  (a, i) => !a.startsWith('--') && !['--out', '--base'].includes(args[i - 1])
)
if (!listFile) {
  console.error(
    '用法：node scripts/replay/shoot.mjs <镜头单.json> [--draft] [--out 目录] [--base 地址]'
  )
  process.exit(2)
}
const draft = args.includes('--draft')
const list = JSON.parse(fs.readFileSync(listFile, 'utf8'))
const out = path.resolve(option('--out', path.dirname(path.resolve(listFile))))
const base = option('--base', 'http://127.0.0.1:5174').replace(/\/$/, '')
const [width, height] = draft ? [1280, 720] : (list.size ?? [3840, 2160])
const fps = draft ? 30 : (list.fps ?? 60)
/** 开拍前先空走这么久：人、气泡、镜头都就位了再截 */
const PREROLL_MS = 2000

if (spawnSync('ffmpeg', ['-version']).status !== 0)
  throw Error('要先装 ffmpeg（brew install ffmpeg）')
fs.mkdirSync(out, { recursive: true })
const reel = loadReel(list.town, list.reel)
const map = loadMap(list.town, reel.header.map_hash)
const metre = map.spatial?.svg_units_per_metre ?? 12
const canvas = map.layout.canvas
const { beats } = scriptOf(reel)

for (const clip of list.clips) {
  const started = Date.now()
  const from = typeof clip.from === 'number' ? clip.from : timeOfClock(reel, clip.from)
  const ms = clip.seconds * 1000
  const name = (clip.name ?? `clip_${from}`) + (draft ? '_小样' : '')
  console.log(
    `拍 ${name}：录像 ${(from / 1000).toFixed(1)} 秒起 ${clip.seconds} 秒，${width}×${height} ${fps} 帧`
  )
  const chrome = await launch()
  try {
    await shoot(chrome, clip, from, ms, name)
  } finally {
    await chrome.close()
  }
  writeSubtitles(name, from, ms)
  sheet(name, clip.seconds)
  console.log(
    `  好了：${path.join(out, name)}.mp4（用了 ${Math.round((Date.now() - started) / 1000)} 秒）`
  )
}

async function shoot(chrome, clip, from, ms, name) {
  const { send, evaluate } = chrome
  await send('Page.enable')
  await send('Emulation.setDeviceMetricsOverride', {
    width,
    height,
    deviceScaleFactor: 1,
    mobile: false,
  })
  // 画质开到高，失焦模糊先按「轻」，镜头单里可以改
  await send('Page.addScriptToEvaluateOnNewDocument', {
    source: `try { localStorage.setItem('town-2d:hd-quality', 'high'); localStorage.setItem('town-2d:hd-blur', 'light') } catch {}`,
  })
  await send('Page.navigate', {
    url: `${base}/game.html?map=${encodeURIComponent(list.town)}&replay=1`,
  })
  await until(() => evaluate('!!window.__replay'), '页面没有进入重演模式（前端是不是旧的？）')
  const start = Math.max(0, from - PREROLL_MS)
  const input = {
    name: townName(list.town),
    map,
    segments: segmentsFor(reel, start, from + ms).map((s) => s.text),
    start,
  }
  await evaluate(`window.__replay.provide(${JSON.stringify(input)})`)
  await until(() => evaluate('!!window.director'), '画面没有建起来', 120000)
  const ui = { names: true, bubbles: true, ...list.ui }
  await evaluate(`director.ui(${JSON.stringify({ clean: true, ...ui })}); director.hold()`)
  const people = await evaluate('director.residents()')
  const idOf = (who) => {
    const found = people.find((p) => p.id === who || p.name === who)
    if (!found) throw Error(`录像里此刻没有「${who}」：${people.map((p) => p.name).join('、')}`)
    return found.id
  }
  /** 镜头单里的机位（米）→ 页面里的机位（地图单位） */
  const aimOf = async (aim) => {
    const next = {}
    if (aim.follow) next.follow = idOf(aim.follow)
    if (aim.at === 'center') next.at = [canvas.width / 2, canvas.height / 2]
    else if (Array.isArray(aim.at)) next.at = [aim.at[0] * metre, aim.at[1] * metre]
    else if (typeof aim.at === 'string') {
      next.at = await evaluate(`director.position(${JSON.stringify(idOf(aim.at))})`)
      if (!next.at) throw Error(`「${aim.at}」此刻不在画面里，对不准`)
    }
    if (aim.width === 'all')
      next.width = Math.max(canvas.width, canvas.height * (width / height)) * 1.06
    else if (aim.width !== undefined) next.width = aim.width * metre
    if (aim.yaw !== undefined) next.yaw = aim.yaw
    if (aim.pitch !== undefined) next.pitch = aim.pitch
    return next
  }
  const cues = [...(clip.camera ?? [])].sort((a, b) => (a.at ?? 0) - (b.at ?? 0))
  let cue = 0
  /** 到点的机位指令都做掉；clipMs 是这段视频里的毫秒 */
  const direct = async (clipMs) => {
    while (cue < cues.length && (cues[cue].at ?? 0) * 1000 <= clipMs) {
      const c = cues[cue++]
      if (c.set) await evaluate(`director.camera(${JSON.stringify(await aimOf(c.set))})`)
      if (c.move)
        await evaluate(
          `director.move(${JSON.stringify(await aimOf(c.move))}, ${c.seconds ?? 2}, ${JSON.stringify(c.curve ?? 'smooth')})`
        )
      if ('focus' in c)
        await evaluate(`director.focus(${JSON.stringify(c.focus ? idOf(c.focus) : null)})`)
      if (c.blur) await evaluate(`director.blur(${JSON.stringify(c.blur)})`)
    }
  }
  const frame = 1000 / fps
  await direct(0)
  for (let t = start; t < from; t += frame)
    await evaluate(`director.step(${Math.min(frame, from - t)})`)
  const ffmpeg = spawn(
    'ffmpeg',
    [
      ...[
        '-y',
        '-loglevel',
        'error',
        '-f',
        'image2pipe',
        '-framerate',
        String(fps),
        '-c:v',
        'mjpeg',
      ],
      ...['-i', '-', '-c:v', 'libx264', '-pix_fmt', 'yuv420p'],
      ...(draft ? ['-crf', '23', '-preset', 'veryfast'] : ['-crf', '14', '-preset', 'slow']),
      ...['-movflags', '+faststart', '-timecode', timecode(from), path.join(out, `${name}.mp4`)],
    ],
    { stdio: ['pipe', 'inherit', 'inherit'] }
  )
  const done = new Promise((resolve, reject) =>
    ffmpeg.on('exit', (code) => (code === 0 ? resolve() : reject(Error(`ffmpeg 退出码 ${code}`))))
  )
  const frames = Math.round((ms / 1000) * fps)
  for (let i = 0; i < frames; i++) {
    await direct(i * frame)
    if (i > 0) await evaluate(`director.step(${frame})`)
    const shot = await send('Page.captureScreenshot', { format: 'jpeg', quality: draft ? 85 : 95 })
    if (!ffmpeg.stdin.write(Buffer.from(shot.data, 'base64')))
      await new Promise((resolve) => ffmpeg.stdin.once('drain', resolve))
    if (i % fps === 0) process.stdout.write(`\r  ${Math.round((i / frames) * 100)}%`)
  }
  ffmpeg.stdin.end()
  await done
  process.stdout.write('\r')
}

/** 台词和心声各出一份 SRT（时刻按这段视频算），名字写在前面；字幕不烧进画面，进 PR 的字幕轨 */
function writeSubtitles(name, from, ms) {
  for (const [kind, label, suffix] of [
    ['speech', '', '台词'],
    ['thought', '（心想）', '心声'],
  ]) {
    const lines = beats.filter((b) => b.kind === kind && b.t >= from - 4000 && b.t < from + ms)
    // 台词到下一句（谁说的都算）就换；心声只被同一个人的下一个想法换掉
    const entries = lines.map((b, i) => {
      const begin = Math.max(0, b.t - from)
      const next = lines.slice(i + 1).find((n) => kind === 'speech' || n.id === b.id)
      const end = Math.min(
        ms,
        begin + 4500,
        next ? Math.max(begin + 1500, next.t - from) : Infinity
      )
      return { begin, end, text: `${b.who}${label}：${b.text}` }
    })
    const srt = entries
      .filter((e) => e.end > e.begin)
      .map((e, i) => `${i + 1}\n${srtTime(e.begin)} --> ${srtTime(e.end)}\n${e.text}\n`)
      .join('\n')
    fs.writeFileSync(path.join(out, `${name}.${suffix}.srt`), srt)
  }
}

/** 样片图：整段均匀抽 8 帧拼成 4×2 一张，给自查和过目用 */
function sheet(name, seconds) {
  const video = path.join(out, `${name}.mp4`)
  spawnSync('ffmpeg', [
    ...['-y', '-loglevel', 'error', '-i', video],
    ...['-vf', `fps=8/${seconds},scale=640:-2,tile=4x2:padding=6:color=white`],
    ...['-frames:v', '1', '-q:v', '3', path.join(out, `${name}.样片.jpg`)],
  ])
}

function srtTime(ms) {
  const h = Math.floor(ms / 3600000)
  const m = Math.floor(ms / 60000) % 60
  const s = Math.floor(ms / 1000) % 60
  const pad = (n, w = 2) => String(n).padStart(w, '0')
  return `${pad(h)}:${pad(m)}:${pad(s)},${pad(Math.floor(ms % 1000), 3)}`
}

/** 素材的时间码按录像里的时刻写，同一段拍的几个机位在 PR 里按时间码就能对齐 */
function timecode(ms) {
  const total = Math.floor(ms / 1000)
  const pad = (n) => String(n).padStart(2, '0')
  const frames = Math.floor(((ms % 1000) / 1000) * fps)
  return `${pad(Math.floor(total / 3600))}:${pad(Math.floor(total / 60) % 60)}:${pad(total % 60)}:${pad(frames)}`
}

async function until(check, failure, timeout = 30000) {
  const deadline = Date.now() + timeout
  while (Date.now() < deadline) {
    if (await check().catch(() => false)) return
    await sleep(200)
  }
  throw Error(failure)
}
