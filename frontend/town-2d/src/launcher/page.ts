import 'town-shared/style.css'
import './style.css'
import type { MapEntry } from 'town-shared/mapDocument'
import type { GameMap } from 'town-shared/gameMap'
import { $, query } from 'town-shared/dom'
import { errorText } from 'town-shared/format'
import { pauseWorld } from 'town-shared/pauseWorld'
import { loadDocument } from '../assets'
import { createMapRenderer } from '../mapRenderers'
import { gameUrl, listMaps, openMap } from './catalog'
import { initCreator } from './creator'
import { PREFABS, type Prefab } from 'town-shared/prefabs/index'
import { generatePrefab, isBuiltinTown, missingPrefabs, prefabTownId } from './prefabEntry'
import { api } from './api'
import { warmSelectedGame } from '../startupWarmup'
import { MUSIC_TRACKS } from 'town-shared/audio/catalog'
import { createMusicController } from 'town-shared/audio/music'
import {
  chooseMusic,
  musicWorldOf,
  rosterMood,
  titleChoice,
  type MusicWorld,
} from 'town-shared/audio/scene'
import { installPlatform, isCompact, isTouch, onBack, systemBars } from 'town-shared/platform'
import { installSelects } from 'town-shared/design/select'
import { installFavicon, logoUrl } from 'town-shared/brand/brand'
import { installHomeSettings } from './settings'
import { clockText, createSceneryBar } from './scenery'
import { themeOf, type MapTheme } from '../map/themes'
// 小镇选择页：一句话说清这是什么游戏、小镇列表（写着玩到第几天、住了几个人）、静态预览、进入或继续玩。
// 预览不启动世界。
installPlatform()
installSelects()
systemBars('night')
installFavicon()
query<HTMLImageElement>(document, '.launcher-mark').src = logoUrl
// 手机布局里预览在列表上面
const previewNote = document.querySelector<HTMLElement>('.launcher-preview-note')
const notePreview = () => {
  if (previewNote)
    previewNote.textContent = isCompact()
      ? '上面是选中小镇的预览，可以拖动和缩放。'
      : '选中的小镇显示在右边，可以拖动和缩放。'
}
notePreview()
window.addEventListener('resize', notePreview)

const enter = query<HTMLButtonElement>(document, '#enter-game')
const retry = query<HTMLButtonElement>(document, '#preview-retry')
const scenic = query<HTMLButtonElement>(document, '#preview-scenic')
const launcher = query<HTMLElement>(document, '.map-launcher')
const hideUi = query<HTMLButtonElement>(document, '#scenic-hide')
const showUi = query<HTMLButtonElement>(document, '#scenic-show')
const sceneryHost = $('scenery-bar')
let scenicScrollY = 0
/** 赏景过一次以后，换上来的预览都照景色条上的时刻和天气画（返回选镇也不跳回傍晚） */
let sceneryUsed = false
/** 展开现有的静态预览，底部景色条换时刻和天气。只换画面：不连接世界，不改存档的时钟或天气。 */
function setScenic(enabled: boolean) {
  if (enabled === launcher.classList.contains('is-scenic')) return
  if (enabled) scenicScrollY = window.scrollY
  else setBare(false)
  launcher.classList.toggle('is-scenic', enabled)
  scenic.setAttribute('aria-pressed', String(enabled))
  scenic.textContent = enabled ? '返回选镇' : '赏景'
  scenic.title = enabled ? '返回选择小镇（Esc）' : '展开地图，换时间和天气看小镇的景色'
  hideUi.hidden = !enabled
  sceneryHost.hidden = !enabled
  scenery.setActive(enabled)
  window.scrollTo(0, enabled ? 0 : scenicScrollY)
  scenic.focus({ preventScroll: true })
  if (enabled) {
    sceneryUsed = true
    const shown = shownPreview()
    if (shown) {
      scenery.setTheme(shown.theme.light)
      shown.map.setScenery?.(scenery.value.minutes, scenery.value.weather)
    }
    sceneryMusic(0)
  } else {
    clearTimeout(musicTimer)
    launcherMusic.setChoice(titleChoice(MUSIC_TRACKS), true)
  }
}
scenic.onclick = () => setScenic(!launcher.classList.contains('is-scenic'))
const scenery = createSceneryBar(sceneryHost, {
  change(value) {
    shownPreview()?.map.setScenery?.(value.minutes, value.weather)
    if (!scenery.playing) sceneryMusic()
  },
  playing(on) {
    if (!on) sceneryMusic()
  },
})
let musicTimer: ReturnType<typeof setTimeout> | undefined
/** 赏景时音乐跟着景色挑（夜里夜曲、下雨雨天的曲子）。拖动、点选停下一会儿再换，拖过几个时段不连着换曲；
 *  播放一天时不换，不然十几秒换一首 */
function sceneryMusic(delay = 700) {
  clearTimeout(musicTimer)
  musicTimer = setTimeout(() => {
    const shown = shownPreview()
    if (!shown || !launcher.classList.contains('is-scenic') || scenery.playing) return
    const { minutes, weather } = scenery.value
    const choice = chooseMusic(
      {
        clock: clockText(minutes),
        weather,
        world: shown.world,
        storyMusic: false,
        mood: rosterMood([]),
        once: new Set(),
      },
      MUSIC_TRACKS
    )
    launcherMusic.setChoice(choice, true)
  }, delay)
}
let idleTimer: ReturnType<typeof setTimeout> | undefined
/** 收起界面：只剩风景。左上角的「显示界面」鼠标停一会儿就淡掉，动一下、点一下画面又浮出来 */
function setBare(bare: boolean) {
  if (bare === launcher.classList.contains('is-bare')) return
  launcher.classList.toggle('is-bare', bare)
  showUi.hidden = !bare
  clearTimeout(idleTimer)
  if (bare) {
    // 焦点不留在藏起来的按钮上
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
    wake()
  } else {
    showUi.classList.remove('is-idle')
    hideUi.focus({ preventScroll: true })
  }
}
function wake() {
  if (!launcher.classList.contains('is-bare')) return
  showUi.classList.remove('is-idle')
  clearTimeout(idleTimer)
  idleTimer = setTimeout(() => showUi.classList.add('is-idle'), 2500)
}
hideUi.onclick = () => setBare(true)
showUi.onclick = () => setBare(false)
const stage = query<HTMLElement>(document, '.launcher-stage')
stage.addEventListener('pointermove', wake)
stage.addEventListener('pointerdown', wake)
document.addEventListener('keydown', (event) => {
  if (!launcher.classList.contains('is-scenic')) return
  // Esc 先把收起的界面放出来，再按一次返回选镇
  if (event.key === 'Escape') {
    event.preventDefault()
    if (launcher.classList.contains('is-bare')) setBare(false)
    else setScenic(false)
    return
  }
  const target = event.target instanceof Element ? event.target : null
  if (
    event.key.toLowerCase() === 'h' &&
    !event.altKey &&
    !event.ctrlKey &&
    !event.metaKey &&
    !target?.closest('input, textarea, select, [contenteditable]')
  ) {
    event.preventDefault()
    setBare(!launcher.classList.contains('is-bare'))
    return
  }
  wake()
})
const launcherMusic = createMusicController(
  query<HTMLButtonElement>(document, '#launcher-music-toggle'),
  { first: 'title-overture' }
)
launcherMusic.setChoice(titleChoice(MUSIC_TRACKS))
window.addEventListener('pagehide', () => launcherMusic.dispose(), { once: true })
const homeSettings = installHomeSettings({ music: launcherMusic })
/** 刚建好的小镇：预览出来后先看整张图 */
let fitNext = ''
let selected: MapEntry | undefined,
  request = 0,
  maps: MapEntry[] = []

/** theme 给景色条画天色轨道，world 给赏景挑曲子 */
type Preview = { host: HTMLElement; map: GameMap; theme: MapTheme; world: MusicWorld }
// 桌面保留最近两张预览，避免来回切换时重新生成地面和 WebGL 场景；触屏设备只保留一张，控制显存。
const previews = new Map<string, Preview>()
let pendingPreview: Preview | undefined
const previewKey = (map: MapEntry) => (map.mapHash ? `${map.id}:${map.mapHash}` : '')
function dropPendingPreview() {
  const pending = pendingPreview
  pendingPreview = undefined
  if (!pending) return
  pending.map.dispose()
  pending.host.remove()
}
function dropPreview(key: string) {
  const preview = previews.get(key)
  if (!preview) return
  previews.delete(key)
  preview.map.dispose()
  preview.host.remove()
}
/** 正露在外面的那张预览 */
const shownPreview = () => [...previews.values()].find((preview) => !preview.host.hidden)
function showPreview(key: string) {
  for (const [id, preview] of previews) preview.host.hidden = id !== key
  const preview = previews.get(key)
  if (preview) {
    previews.delete(key)
    previews.set(key, preview)
  }
}
function finishPreview(map: MapEntry) {
  $('preview-state').hidden = true
  scenic.disabled = false
  if (sceneryUsed) shownPreview()?.map.setScenery?.(scenery.value.minutes, scenery.value.weather)
  if (fitNext === map.id) {
    fitNext = ''
    $('map-preview')
      .querySelector<HTMLButtonElement>('.map-preview-scene:not([hidden]) .zoom-readout')
      ?.click()
  }
}

function describe(map: MapEntry) {
  document
    .querySelectorAll<HTMLElement>('[data-map-id]')
    .forEach((el) => el.setAttribute('aria-pressed', String(el.dataset.mapId === map.id)))
  const detail = document.querySelector<HTMLElement>('.map-detail')
  if (detail) detail.hidden = false
  $('selected-map-name').textContent = map.name
  $('selected-map-description').textContent = map.description
  $('selection-status').textContent = `已选择 · ${map.name}`
  const played = !!map.progress
  $('pause-status').textContent = played
    ? '接着上次的进度玩。这里只是预览，进去后小镇才接着走。'
    : '这里只是预览，进去后小镇才开始。'
  enter.replaceChildren(played ? '继续玩 ' : '进入游戏 ', arrow())
  updateActions()
  enter.disabled = deleting || !map.available
}

async function select(map: MapEntry) {
  setScenic(false)
  scenic.disabled = true
  actions.open = false
  selected = map
  const current = ++request
  const url = new URL(location.href)
  url.searchParams.set('map', map.id)
  history.replaceState(null, '', url)
  describe(map)
  retry.hidden = true
  dropPendingPreview()
  const key = previewKey(map)
  showPreview(key)
  if (key && previews.has(key)) {
    finishPreview(map)
    warmSelectedGame(map)
    return
  }
  $('preview-state').hidden = false
  $('preview-state').textContent = '正在加载预览…'
  // 先把选中状态画出来再干重活；连点时只建最后一张预览
  await new Promise<void>((resolve) => requestAnimationFrame(() => setTimeout(resolve, 120)))
  if (current !== request) return
  warmSelectedGame(map)
  try {
    const mapDocument = await loadDocument(map.id, map.mapHash)
    if (current !== request) return
    const theme = themeOf(mapDocument)
    const world = musicWorldOf(theme.id, mapDocument.generation?.spec?.settlement)
    // 先让加载提示有机会显示，再在主线程计算地面和创建场景。
    await new Promise<void>((resolve) => setTimeout(resolve, 0))
    if (current !== request) return
    const limit = isTouch() ? 1 : 2
    while (previews.size >= limit) dropPreview(previews.keys().next().value!)
    const host = document.createElement('div')
    host.className = 'map-preview-scene'
    $('map-preview').append(host)
    let rendered: GameMap
    try {
      rendered = await createMapRenderer(mapDocument, host)
    } catch (error) {
      host.remove()
      throw error
    }
    if (current !== request) {
      rendered.dispose()
      host.remove()
      return
    }
    const pending = (pendingPreview = { host, map: rendered, theme, world })
    // 立体场景建好再拿掉「正在加载预览…」：之前只有底色和放大的地名
    await rendered.ready
    if (current !== request) {
      if (pendingPreview === pending) dropPendingPreview()
      return
    }
    pendingPreview = undefined
    // 没有摘要时不能判断内容是否变化，只在本次选中期间保留。
    const cacheKey = key || `${map.id}:request:${current}`
    previews.set(cacheKey, pending)
    finishPreview(map)
  } catch (error) {
    if (current === request) {
      $('preview-state').textContent = errorText(error)
      retry.hidden = false
    }
  }
}

function arrow() {
  const span = document.createElement('span')
  span.setAttribute('aria-hidden', 'true')
  span.textContent = '→'
  return span
}

/** 列表上的小字：玩到第几天、住了几个人；自带的小镇没玩过时写「自带的小镇」 */
function progressText(map: MapEntry) {
  if (!map.available) return '无法打开'
  const p = map.progress
  if (p && p.residents > 0) return `第 ${p.day} 天 · ${p.residents} 位村民`
  if (p) return `第 ${p.day} 天 · 还没有村民`
  return map.origin === 'builtin' ? '自带的小镇 · 还没开始' : '还没开始'
}

function mapOption(map: MapEntry) {
  const b = document.createElement('button')
  b.className = 'map-option'
  b.dataset.mapId = map.id
  b.setAttribute('aria-pressed', 'false')
  b.setAttribute('aria-label', `选择${map.name}`)
  const text = document.createElement('span'),
    name = document.createElement('strong'),
    status = document.createElement('span')
  name.textContent = map.name
  status.className = 'map-option-status'
  status.textContent = progressText(map)
  text.append(name, status)
  b.append(text)
  if (isBuiltinTown(map)) {
    b.classList.add('is-builtin')
    const badge = document.createElement('span')
    badge.className = 'map-option-badge'
    badge.textContent = '内置'
    name.append(badge)
  }
  b.onclick = () => {
    if (selected?.id === map.id && selected.mapHash === map.mapHash && retry.hidden) return
    void select(map)
  }
  return b
}

function prefabOption(prefab: Prefab) {
  const b = mapOption({
    id: prefabTownId(prefab),
    name: prefab.name,
    description: prefab.description,
    origin: 'builtin',
    available: true,
  } as MapEntry)
  b.querySelector('.map-option-status')!.textContent = '还没开始'
  b.onclick = () => void buildPrefab(prefab)
  return b
}

// 第一次选中预制小镇：生成岛、存成内置小镇，再像别的小镇一样选中预览；重新开始也走这里
let building = false
async function buildPrefab(prefab: Prefab) {
  if (building) return
  building = true
  const current = ++request
  selected = undefined
  dropPendingPreview()
  showPreview('')
  document
    .querySelectorAll<HTMLElement>('[data-map-id]')
    .forEach((el) =>
      el.setAttribute('aria-pressed', String(el.dataset.mapId === prefabTownId(prefab)))
    )
  const detail = document.querySelector<HTMLElement>('.map-detail')
  if (detail) detail.hidden = false
  $('selected-map-name').textContent = prefab.name
  $('selected-map-description').textContent = prefab.description
  $('pause-status').textContent = ''
  enter.disabled = true
  actions.hidden = true
  retry.hidden = true
  $('preview-state').hidden = false
  $('preview-state').textContent = '正在生成岛…'
  try {
    const id = await generatePrefab(prefab)
    building = false
    if (current !== request) return
    fitNext = id
    await refresh(id)
  } catch (error) {
    building = false
    if (current === request) $('preview-state').textContent = errorText(error)
  }
}

async function refresh(id?: string) {
  try {
    maps = await listMaps()
    // 还没生成的预制小镇也排在内置小镇里，选中时才生成
    const options = maps.map(mapOption)
    const after = maps.filter(isBuiltinTown).length
    options.splice(after, 0, ...missingPrefabs(maps).map(prefabOption))
    $('map-list').replaceChildren(...options)
    $('map-count').textContent = `${maps.length} 个`
    $('map-empty').hidden = maps.length > 0
    const wanted = id ?? new URLSearchParams(location.search).get('map')
    const initial = maps.find((m) => m.id === wanted)
    const prefab = PREFABS.find((p) => prefabTownId(p) === wanted)
    if (!initial && prefab) await buildPrefab(prefab)
    else if (initial ?? maps[0]) await select(initial ?? maps[0]!)
    return true
  } catch (error) {
    $('selection-status').textContent = '小镇列表加载失败'
    $('pause-status').textContent = errorText(error)
    $('pause-retry').hidden = false
    $('pause-retry').textContent = '重新连接'
    return false
  }
}
enter.onclick = async () => {
  if (!selected?.available || deleting) return
  const map = selected
  enter.disabled = true
  $('pause-status').textContent = '正在打开小镇…'
  try {
    const runtime = await openMap(map.id)
    await pauseWorld(runtime.endpoint)
    if (selected === map) location.assign(gameUrl(map))
  } catch (error) {
    $('pause-status').textContent = errorText(error)
    enter.disabled = false
  }
}
retry.onclick = () => {
  if (selected) void select(selected)
}
$('pause-retry').onclick = () => {
  void refresh()
}
const actions = query<HTMLDetailsElement>(document, '#town-actions')
const close = query<HTMLButtonElement>(document, '#close-town')
const remove = query<HTMLButtonElement>(document, '#delete-town')
const reset = query<HTMLButtonElement>(document, '#reset-town')
function updateActions() {
  close.hidden = !selected?.running
  remove.hidden = !selected?.deletable
  reset.hidden = !selected?.id.startsWith('prefab-')
  actions.hidden = close.hidden && remove.hidden && reset.hidden
  if (actions.hidden) actions.open = false
}
document.addEventListener('click', (event) => {
  if (event.target instanceof Node && !actions.contains(event.target)) actions.open = false
})
actions.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    actions.open = false
    actions.querySelector('summary')?.focus()
  }
})
close.title = '保存当前进度并关闭小镇，下次进入时继续'
close.onclick = async () => {
  const map = selected
  if (!map?.running || closing) return
  actions.open = false
  closing = true
  ++runningRequest
  close.disabled = true
  try {
    await api(`/${encodeURIComponent(map.id)}/close`, {})
    map.running = false
    if (selected?.id === map.id) {
      selected.running = false
      updateActions()
      $('pause-status').textContent = '进度已保存，小镇已关闭'
    }
  } catch (error) {
    $('pause-status').textContent = errorText(error)
  } finally {
    closing = false
    close.disabled = false
    void syncRunning()
  }
}
// 只更新运行状态，避免轮询重画预览或覆盖操作提示。
let closing = false,
  runningRequest = 0
async function syncRunning() {
  if (document.hidden || closing || deleting) return
  const current = ++runningRequest
  try {
    const latest = await listMaps()
    if (current !== runningRequest || closing || deleting) return
    for (const map of maps)
      map.running = latest.find((town) => town.id === map.id)?.running ?? false
    updateActions()
  } catch {
    if (current === runningRequest) {
      close.hidden = true
      actions.hidden = remove.hidden && reset.hidden
      if (actions.hidden) actions.open = false
    }
  }
}
window.addEventListener('pageshow', () => {
  void syncRunning()
})
window.addEventListener('focus', () => {
  void syncRunning()
})
document.addEventListener('visibilitychange', () => {
  void syncRunning()
})
window.setInterval(() => {
  void syncRunning()
}, 5000)
let deleting = false
remove.onclick = async () => {
  const map = selected
  if (!map?.deletable || deleting) return
  actions.open = false
  if (
    !window.confirm(
      `删除“${map.name}”？\n\n该小镇的地图、居民、记忆和全部游戏进度将永久删除，无法恢复。正在运行的服务也会关闭。`
    )
  )
    return
  deleting = true
  remove.disabled = true
  enter.disabled = true
  close.disabled = true
  $('pause-status').textContent = '正在关闭服务并删除地图…'
  try {
    await api(`/${encodeURIComponent(map.id)}/delete`, {})
    for (const key of previews.keys()) if (key.startsWith(`${map.id}:`)) dropPreview(key)
    if (selected?.id === map.id) {
      selected = undefined
      ++request
      dropPendingPreview()
      remove.hidden = true
      document.querySelector<HTMLElement>('.map-detail')!.hidden = true
    }
    if (await refresh(selected?.id)) $('pause-status').textContent = `已删除“${map.name}”。`
  } catch (error) {
    $('pause-status').textContent = errorText(error)
  } finally {
    deleting = false
    remove.disabled = false
    close.disabled = false
    enter.disabled = !selected?.available
  }
}
// 预制小镇重新开始：清掉这一局（地图、居民、进度）、重新生成岛，进镇后重新出开局设置
reset.onclick = async () => {
  const map = selected
  const prefab = PREFABS.find((p) => map && prefabTownId(p) === map.id)
  if (!map || !prefab || deleting) return
  actions.open = false
  if (!window.confirm(`重新开始“${map.name}”？\n\n这一局的村民、记忆和进度都会清掉，从头开始。`))
    return
  deleting = true
  enter.disabled = true
  $('pause-status').textContent = '正在清掉这一局…'
  try {
    await api(`/${encodeURIComponent(map.id)}/reset`, {})
    for (const key of previews.keys()) if (key.startsWith(`${map.id}:`)) dropPreview(key)
    deleting = false
    await buildPrefab(prefab)
  } catch (error) {
    $('pause-status').textContent = errorText(error)
    enter.disabled = !selected?.available
  } finally {
    deleting = false
  }
}
// 建镇：电脑版由管理服务生成，手机应用在页面里生成（见 localCreation.ts）
initCreator(
  (id, problem) => {
    // 刚建好的小镇先看整张图，不停在开场的近景；保存后没能进镇时在这里说原因
    fitNext = id
    void refresh(id).then(() => {
      if (problem) $('pause-status').textContent = problem
    })
  },
  () => maps.map((m) => m.name),
  () => homeSettings.connect(),
  // 保存并进镇：和「进入游戏」一样先打开、停住世界，再进游戏页
  async (id) => {
    const runtime = await openMap(id)
    await pauseWorld(runtime.endpoint)
    location.assign(gameUrl(runtime))
  }
)
// 安卓返回键：先收起「更多操作」，其余交给应用壳（再按一次退出）
onBack(() => {
  if (launcher.classList.contains('is-bare')) {
    setBare(false)
    return true
  }
  if (launcher.classList.contains('is-scenic')) {
    setScenic(false)
    return true
  }
  if (!actions.open) return false
  actions.open = false
  return true
})
void refresh()
