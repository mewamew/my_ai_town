// 录像：世界观面板「规则」下面一节——开关、录下的几卷和删除；录着的时候时钟牌右上角亮一盏红灯。
// 录像由世界进程写进小镇目录（crates/host/src/recording.rs）：录的是名册和事件，事后照着它把画面
// 重演一遍、换角度拍成视频（scripts/replay）。开关跟着存档走，切换就保存，世界不暂停。
import { button, el } from '../dom'
import { displayClock, fileSize } from '../format'
import { pixelIcon } from '../game/pixel'
import type { ReelView } from '../protocol'
import type { WorldSettingsController } from '../worldSettings'
import './recording.css'

/** 列表里直接列出的卷数；更早的收进「更早的 N 卷」 */
const SHOWN = 4
/** 点了「删除」以后这么久里再点一次才删 */
const CONFIRM_MS = 4000

export function createRecordingSection(world: WorldSettingsController) {
  const root = el('section', '', 'town-section town-recording')
  const total = el('span', '', 'rec-total')
  const title = el('h3', '录像')
  title.append(total)
  const box = el('section', '', 'physiology-switches town-rule')
  const row = el('label', '', 'physiology-row')
  const input = el('input')
  input.type = 'checkbox'
  input.id = 'town-recording'
  input.setAttribute('role', 'switch')
  row.htmlFor = input.id
  const description = el('small')
  const text = el('span', '', 'physiology-text')
  text.append(el('b', '录下这个小镇'), description)
  row.append(input, text)
  box.append(
    row,
    el(
      'p',
      '切换就保存，世界不会暂停。每小时大约几兆；关着的时候发生的事，事后拍不了。',
      'physiology-note'
    )
  )
  const list = el('ol', '', 'rec-list')
  const older = el('details', '', 'rec-older')
  const olderHead = el('summary')
  const olderList = el('ol', '', 'rec-list')
  older.append(olderHead, olderList)
  const status = el('p', '', 'town-status')
  status.setAttribute('role', 'status')
  root.append(title, box, list, older, status)

  /** 点过一次「删除」、等着再点一次的那一卷 */
  let armed: { id: string; timer: ReturnType<typeof setTimeout> } | null = null
  const disarm = () => {
    if (armed) clearTimeout(armed.timer)
    armed = null
  }

  function reelRow(reel: ReelView, live: boolean) {
    const item = el('li')
    const span = `${displayClock(reel.from_clock) || '还没开始'} → ${live ? '现在' : displayClock(reel.to_clock) || '—'}`
    const what = el('span')
    what.append(el('b', when(reel, live)), el('small', span))
    const size = el(
      'span',
      live ? '● 录像中' : fileSize(reel.bytes),
      live ? 'rec-size live' : 'rec-size'
    )
    const del = button(armed?.id === reel.id ? '确定删除？' : '删除', () => {
      if (armed?.id !== reel.id) {
        disarm()
        armed = { id: reel.id, timer: setTimeout(() => (disarm(), render()), CONFIRM_MS) }
        render()
        return
      }
      disarm()
      status.textContent = '正在删除…'
      world.deleteRecording(reel.id, (ok, message) => {
        status.textContent = ok ? `✓ ${message}` : message
        render()
      })
      render()
    })
    del.className = armed?.id === reel.id ? 'rec-del armed' : 'rec-del'
    del.disabled = live || !world.online() || world.saving()
    if (live) del.title = '正在录的这一卷删不了，先关掉录像'
    item.append(what, size, del)
    return item
  }

  function render() {
    const state = world.state()
    const recordings = world.recordings()
    const live = recordings?.live
    input.checked = !!state?.recording
    input.disabled = !state || !state.persistent || !world.online() || world.saving()
    row.classList.toggle('off', !input.checked)
    description.textContent = !state?.persistent
      ? '这个世界不存档，录不了像'
      : !input.checked
        ? '关着：现在发生的事不录'
        : live
          ? '正在录：录下来的剧情可以事后重演，换角度拍成视频'
          : '开着：世界运行时就录'
    const reels = recordings?.reels ?? []
    const sum = reels.reduce((n, r) => n + r.bytes, 0)
    total.textContent = reels.length ? `${reels.length} 卷 · 共 ${fileSize(sum)}` : ''
    list.replaceChildren(...reels.slice(0, SHOWN).map((r) => reelRow(r, r.id === live)))
    const rest = reels.slice(SHOWN)
    older.hidden = rest.length === 0
    olderHead.textContent = `更早的 ${rest.length} 卷`
    olderList.replaceChildren(...rest.map((r) => reelRow(r, r.id === live)))
    light.hidden = !live
    const current = live ? reels.find((r) => r.id === live) : undefined
    if (current) {
      const minutes = Math.max(0, Math.round((Date.now() - current.started_at) / 60000))
      light.title = `正在录像 · 第 ${reels.length - reels.indexOf(current)} 卷 · 已录 ${minutes} 分钟`
    }
  }

  input.addEventListener('change', () => {
    status.textContent = '正在保存…'
    world.saveRecording(input.checked, (ok, message) => {
      status.textContent = ok ? `✓ ${message}` : message
      render()
    })
    render()
  })

  // 时钟牌右上角的红灯：录着的时候亮，悬停看是第几卷、录了多久
  const light = pixelIcon('rec', 1)
  light.classList.add('hud-rec')
  light.alt = '正在录像'
  light.hidden = true
  light.addEventListener('pointerenter', render)
  document.getElementById('hud-clock')?.append(light)

  world.subscribe(render)
  render()
  return { el: root }
}

/** 这一卷是什么时候录的：「今天 10:31 起」「11月5日 15:40–16:32」 */
function when(reel: ReelView, live: boolean) {
  const start = new Date(reel.started_at)
  const day = dayLabel(start)
  const hm = (d: Date) => `${pad(d.getHours())}:${pad(d.getMinutes())}`
  if (live || !reel.ended_at) return `${day} ${hm(start)} 起`
  const end = new Date(reel.ended_at)
  return dayLabel(end) === day
    ? `${day} ${hm(start)}–${hm(end)}`
    : `${day} ${hm(start)} – ${dayLabel(end)} ${hm(end)}`
}

function dayLabel(d: Date) {
  const today = new Date()
  const days = Math.round(
    (new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime() -
      new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()) /
      86_400_000
  )
  if (days === 0) return '今天'
  if (days === 1) return '昨天'
  return `${d.getMonth() + 1}月${d.getDate()}日`
}

const pad = (n: number) => String(n).padStart(2, '0')
