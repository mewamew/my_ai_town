import 'town-shared/style.css'
import 'town-shared/shell/hud.css'
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
import { storedDepthBlur } from 'town-shared/quality'
import { installSelects } from 'town-shared/design/select'
import { installFavicon, logoUrl } from 'town-shared/brand/brand'
import { installHomeSettings } from './settings'
import { clockText, createSceneryBar, sceneryIcon, type Scenery } from './scenery'
import { themeOf, type MapTheme } from '../map/themes'
import { decoratePixels, pixelIcon } from 'town-shared/game/pixel'
import { COVER_SIZE, coverOf, dropCover as forgetCover, saveCover, signatureOf } from './covers'
import { portraitKey } from 'town-shared/portraits'
import { isWeatherKind } from 'town-shared/weather/types'
import { villagerPortrait } from '../map/hd2d/villagerSprite'
import { createStageCamera, stageCalm } from './camera'
import { saveHandoff } from '../enterHandoff'
// 小镇选择页：选中的小镇铺满窗口当背景，界面是游戏里那套白底零件——左下镇名、简介和「进入游戏」，
// 最下面一排明信片（一个小镇一张，写着玩到第几天、住了几个人）。预览不启动世界。
installPlatform()
installSelects()
// 顶上是风景，压着深色：系统栏用浅色的字
systemBars('night')
installFavicon()
decoratePixels(document)
query<HTMLImageElement>(document, '.launcher-mark').src = logoUrl

const enter = query<HTMLButtonElement>(document, '#enter-game')
const retry = query<HTMLButtonElement>(document, '#preview-retry')
const scenic = query<HTMLButtonElement>(document, '#preview-scenic')
const launcher = query<HTMLElement>(document, '.map-launcher')
const hideUi = query<HTMLButtonElement>(document, '#scenic-hide')
const showUi = query<HTMLButtonElement>(document, '#scenic-show')
const sceneryHost = $('scenery-bar')
/** 赏景过一次以后，没有自己样子的镇（玩家建的、还没玩过）换上来都照景色条上的时刻和天气画
 *  （返回选镇也不跳回傍晚）；别的镇照自己的样子画（见 Preview.own） */
let sceneryUsed = false
/** 展开现有的静态预览，底部景色条换时刻和天气。只换画面：不连接世界，不改存档的时钟或天气。 */
function setScenic(enabled: boolean) {
  if (enabled === launcher.classList.contains('is-scenic')) return
  if (!enabled) setBare(false)
  launcher.classList.toggle('is-scenic', enabled)
  scenic.setAttribute('aria-pressed', String(enabled))
  query(scenic, 'span').textContent = enabled ? '返回选镇' : '赏景'
  scenic.title = enabled ? '返回选择小镇（Esc）' : '收起选镇的界面，换时间和天气看小镇的景色'
  hideUi.hidden = !enabled
  sceneryHost.hidden = !enabled
  scenery.setActive(enabled)
  syncInsets()
  scenic.focus({ preventScroll: true })
  if (enabled) {
    sceneryUsed = true
    const shown = shownPreview()
    if (shown) {
      // 从这座镇自己的那一刻接着调，画面不跳
      if (shown.own) scenery.setValue(shown.own)
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
scenic.title = '收起选镇的界面，换时间和天气看小镇的景色'
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
  syncInsets()
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
const bottom = query<HTMLElement>(document, '.launcher-bottom')
const strip = query<HTMLElement>(document, '.launcher-strip')
/** 界面盖住了地图的下边多少（CSS 像素）。电脑上只算最下面那排明信片（镇名一组只占左下一角），
 *  手机上镇名、明信片、按钮整块都算；赏景时只有景色条，收起界面后什么都不盖 */
function coveredBottom() {
  const box = stage.getBoundingClientRect()
  const top = launcher.classList.contains('is-bare')
    ? box.bottom
    : launcher.classList.contains('is-scenic')
      ? sceneryHost.getBoundingClientRect().top
      : (isCompact() ? bottom : strip).getBoundingClientRect().top
  return Math.max(0, Math.round(box.bottom - top))
}
/** 推近、慢漂、进镇时再推近（见 camera.ts） */
const stageCamera = createStageCamera(stage)
/** 镜头把小镇的中心和景深的焦点放进没被界面盖住的那块 */
function setCovered(preview: Preview, covered: number) {
  preview.covered = covered
  preview.map.setViewInsets?.({ top: 0, right: 0, bottom: covered, left: 0 })
}
/** 界面盖住的边变了（窗口大小、进出赏景、收起界面）：正露着的预览跟着挪；没变就不打断镜头 */
function syncInsets() {
  const shown = shownPreview()
  const covered = coveredBottom()
  if (shown && covered !== shown.covered) stageCamera.around(() => setCovered(shown, covered))
}
/** 新建好的预览：镜头对准镇中心（最大的广场），放在露出来那块的正中间；倍数不动 */
function aimAtHeart(preview: Preview) {
  const camera = preview.map.director,
    heart = preview.map.townHeart?.()
  const height = stage.getBoundingClientRect().height
  if (!camera || !heart || !height) return
  // 露出来那块的中间比画面中间高半个遮挡：镜头中心落在镇中心往下这么多（视图单位）
  const lower = (coveredBottom() / 2 / height) * preview.map.getViewBox()[3]
  camera.setShot({ ...camera.shot(), center: heart }, -lower)
}
window.addEventListener('resize', syncInsets)
// 明信片放不下时横着滚：鼠标滚轮上下滚也算
strip.addEventListener(
  'wheel',
  (event) => {
    if (strip.scrollWidth <= strip.clientWidth || Math.abs(event.deltaX) > Math.abs(event.deltaY))
      return
    event.preventDefault()
    strip.scrollLeft += event.deltaY
  },
  { passive: false }
)
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

/** theme 给景色条画天色轨道，world 给赏景挑曲子。own 是这座镇自己的时刻和天气：玩过的是存档停下的
 *  那一刻，没玩过的内置小镇是它最好看的时候（covers.ts 的 signatureOf），都没有就为空 */
type Preview = {
  host: HTMLElement
  map: GameMap
  theme: MapTheme
  world: MusicWorld
  own?: Scenery
  /** 上次按界面盖住下边多少摆的镜头（见 setCovered） */
  covered?: number
}
/** 存档停在一天里的几点、什么天气；没玩过（或管理服务是旧的，没带这两项）时为 undefined */
function savedScenery(map: MapEntry): Scenery | undefined {
  const p = map.progress
  return p?.minutes !== undefined && isWeatherKind(p.weather)
    ? { minutes: ((p.minutes % 1440) + 1440) % 1440, weather: p.weather }
    : undefined
}
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
  stageCamera.drop(preview.map)
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
const cover = $('preview-cover')
let coverTimer: ReturnType<typeof setTimeout> | undefined
/** 场景还在建：先垫这个小镇的明信片（放大、虚掉），不露黑底；没有明信片就不垫 */
function showCover(id: string) {
  clearTimeout(coverTimer)
  const url = coverOf(id)
  cover.hidden = !url
  cover.classList.remove('is-leaving')
  if (url) cover.style.backgroundImage = `url("${url}")`
}
function dropCover() {
  if (cover.hidden) return
  cover.classList.add('is-leaving')
  clearTimeout(coverTimer)
  coverTimer = setTimeout(() => (cover.hidden = true), 650)
}
/** 预览露出来了。fresh 是刚建好第一次露面：镜头对准镇中心、从远处推近，过一会儿拍封面；
 *  换回留着的那张时从它原来的位置接着漂 */
function finishPreview(map: MapEntry, fresh = false) {
  $('preview-state').hidden = true
  scenic.disabled = false
  dropCover()
  const shown = shownPreview()
  if (!shown) return
  setCovered(shown, coveredBottom())
  // 有自己样子的镇照自己的画；没有的照景色条（赏景调过才有，不然是场景自带的傍晚晴天）
  const view = shown.own ?? (sceneryUsed ? scenery.value : undefined)
  if (view) shown.map.setScenery?.(view.minutes, view.weather)
  // 刚建好的小镇先看整张图，不推近
  const whole = fitNext === map.id
  if (whole) {
    fitNext = ''
    query<HTMLButtonElement>(shown.host, '.zoom-readout').click()
  } else if (fresh) aimAtHeart(shown)
  stageCamera.show(shown.map, fresh && !whole)
  if (fresh) shootCover(map, shown)
}

/** 预览露出来两三秒（天气落到地面了）再拍一张全镇当封面，存在本机，明信片换成它。
 *  赏景调过时刻天气的画面不拍：封面是小镇自己的样子 */
function shootCover(map: MapEntry, preview: Preview) {
  window.setTimeout(() => {
    const alive = [...previews.values()].includes(preview)
    if (!alive || preview.host.hidden || document.hidden) return
    if (launcher.classList.contains('is-scenic') || (sceneryUsed && !preview.own)) return
    const url = preview.map.cover?.(...COVER_SIZE)
    if (!url) return
    saveCover(map.id, url)
    const picture = document.querySelector<HTMLElement>(
      `[data-map-id="${CSS.escape(map.id)}"] .map-cover`
    )
    picture?.replaceChildren(coverImage(url))
  }, 2600)
}
function coverImage(url: string) {
  const image = document.createElement('img')
  image.alt = ''
  image.draggable = false
  image.src = url
  return image
}

/** 和游戏里时钟牌上的叫法一样（内核 calendar.rs 的时段表） */
function periodOf(minutes: number) {
  return minutes < 360
    ? '凌晨'
    : minutes < 660
      ? '上午'
      : minutes < 810
        ? '晌午'
        : minutes < 1050
          ? '下午'
          : minutes < 1200
            ? '傍晚'
            : '夜里'
}
/** 时钟牌：存档停在几点、什么天气、第几天；没玩过的镇不出 */
function showClock(map: MapEntry) {
  const plate = $('town-clock')
  const saved = savedScenery(map)
  plate.hidden = !saved
  if (!saved || !map.progress) return
  query(plate, '.clock-weather').replaceChildren(
    pixelIcon(sceneryIcon(saved.minutes, saved.weather))
  )
  $('town-clock-time').textContent = clockText(saved.minutes)
  $('town-clock-period').textContent = periodOf(saved.minutes)
  $('town-clock-day').textContent = `第 ${map.progress.day} 天`
  $('town-clock-name').textContent = ` · ${map.name}`
  plate.title = '上次停在这一刻，进去后接着走'
}
/** 住着谁：像素头像和名字，按入住先后；放不下的写「+几」 */
function showResidents(map: MapEntry) {
  const host = $('town-residents')
  const cast = map.progress?.cast ?? []
  const shown = cast.slice(0, isCompact() ? 5 : 8)
  host.hidden = !shown.length
  const people = shown.map((person) => {
    const figure = document.createElement('figure'),
      slot = document.createElement('span'),
      image = document.createElement('img'),
      name = document.createElement('figcaption')
    slot.className = 'resident-slot'
    image.alt = ''
    image.draggable = false
    image.src = villagerPortrait(
      portraitKey({
        id: person.name,
        template_id: person.template_id ?? undefined,
        appearance: { look: person.look ?? undefined },
      })
    )
    slot.append(image)
    name.textContent = person.name
    figure.append(slot, name)
    return figure
  })
  const rest = (map.progress?.residents ?? 0) - shown.length
  if (rest > 0) {
    const more = document.createElement('span')
    more.className = 'resident-more'
    more.textContent = `+${rest}`
    people.push(more)
  }
  host.replaceChildren(...people)
}

/** 哪张明信片是选中的；它不在画面里时滚进来 */
function markSelected(id: string) {
  for (const card of document.querySelectorAll<HTMLElement>('[data-map-id]')) {
    const on = card.dataset.mapId === id
    card.setAttribute('aria-pressed', String(on))
    if (on) card.scrollIntoView({ block: 'nearest', inline: 'nearest' })
  }
}

function describe(map: MapEntry) {
  markSelected(map.id)
  const detail = document.querySelector<HTMLElement>('.map-detail')
  if (detail) detail.hidden = false
  $('selected-map-name').textContent = map.name
  $('selected-map-description').textContent = map.description
  // 简介只露两行，全文放在悬停提示里
  $('selected-map-description').title = map.description
  $('selection-status').textContent = `已选择 · ${map.name}`
  const played = !!map.progress
  $('pause-status').textContent = played
    ? '接着上次的进度玩。这里只是预览，进去后小镇才接着走。'
    : '这里只是预览，进去后小镇才开始。'
  enterLabel.textContent = played ? '继续玩' : '进入游戏'
  showClock(map)
  showResidents(map)
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
    clearTimeout(coverTimer)
    cover.hidden = true
    finishPreview(map)
    warmSelectedGame(map)
    return
  }
  showCover(map.id)
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
    // 近处虚掉，镇名和明信片压在虚掉的地方；玩家在设定里关了失焦模糊就照关
    if (storedDepthBlur() !== 'off') rendered.setDepthBlur?.('cinema')
    // 比游戏里开场的近景退一档：标题画面多看见半条街
    const [x, y, w, h] = rendered.getViewBox()
    rendered.setViewBox([x - w / 4, y - h / 4, w * 1.5, h * 1.5])
    if (current !== request) {
      rendered.dispose()
      host.remove()
      return
    }
    const own = savedScenery(map) ?? signatureOf(map.id)
    const pending: Preview = { host, map: rendered, theme, world, own }
    pendingPreview = pending
    // 场景一建好就是那一刻的天色，不先闪一下傍晚
    if (own) rendered.setScenery?.(own.minutes, own.weather)
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
    finishPreview(map, true)
  } catch (error) {
    if (current === request) {
      $('preview-state').textContent = errorText(error)
      retry.hidden = false
    }
  }
}

const enterLabel = query<HTMLElement>(enter, 'span')

/** 明信片上的小字：玩到第几天、住了几个人 */
function progressText(map: MapEntry) {
  if (!map.available) return '无法打开'
  const p = map.progress
  if (p && p.residents > 0) return `第 ${p.day} 天 · ${p.residents} 位村民`
  if (p) return `第 ${p.day} 天 · 还没有村民`
  return '还没开始'
}

/** 一张明信片：白边相框里是小镇的全景，下面名字和进度。还没有封面的先放一枚小图标 */
function mapOption(map: MapEntry) {
  const b = document.createElement('button')
  b.className = 'map-option'
  b.dataset.mapId = map.id
  b.setAttribute('aria-pressed', 'false')
  b.setAttribute('aria-label', `选择${map.name}`)
  const picture = document.createElement('span'),
    name = document.createElement('strong'),
    status = document.createElement('span')
  picture.className = 'map-cover'
  const url = coverOf(map.id)
  picture.append(url ? coverImage(url) : pixelIcon('door'))
  name.textContent = map.name
  status.className = 'map-option-status'
  status.textContent = progressText(map)
  b.append(picture, name, status)
  b.onclick = () => {
    if (selected?.id === map.id && selected.mapHash === map.mapHash && retry.hidden) return
    void select(map)
  }
  return b
}

function mapGroup(name: string, cards: HTMLElement[]) {
  const group = document.createElement('div'),
    label = document.createElement('span'),
    row = document.createElement('div')
  group.className = 'map-group'
  label.className = 'map-group-name'
  label.textContent = name
  row.className = 'map-group-cards'
  row.append(...cards)
  group.append(label, row)
  return group
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
  markSelected(prefabTownId(prefab))
  const detail = document.querySelector<HTMLElement>('.map-detail')
  if (detail) detail.hidden = false
  $('selected-map-name').textContent = prefab.name
  $('selected-map-description').textContent = prefab.description
  $('selected-map-description').title = prefab.description
  $('pause-status').textContent = ''
  enterLabel.textContent = '进入游戏'
  $('town-clock').hidden = true
  $('town-residents').hidden = true
  enter.disabled = true
  actions.hidden = true
  retry.hidden = true
  showCover(prefabTownId(prefab))
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
    // 三组：随应用带的地图、选了就玩某个玩法的剧本（还没生成的也排在这里，选中时才生成）、玩家自己建的
    const groups: [string, HTMLElement[]][] = [
      ['内置地图', maps.filter((m) => m.origin === 'builtin').map(mapOption)],
      [
        '剧本',
        [
          ...maps.filter((m) => m.id.startsWith('prefab-')).map(mapOption),
          ...missingPrefabs(maps).map(prefabOption),
        ],
      ],
      ['我建的', maps.filter((m) => !isBuiltinTown(m)).map(mapOption)],
    ]
    $('map-list').replaceChildren(
      ...groups.filter(([, cards]) => cards.length).map(([name, cards]) => mapGroup(name, cards))
    )
    $('map-empty').hidden = maps.length > 0
    syncInsets()
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
/** 进镇的转场：别的零件散开，镜头推近；电脑上时钟牌、「进入游戏」和头像原样飞到它们在游戏里的位置
 *  （左上那一列，见 shell/hud.css 的 .hud-left：时钟牌在 14,14，右边隔 8 是开始钮，下面隔 10 是头像条）。
 *  手机、触屏和要求减少动画时不飞，只散开。返回动画做完的时刻、飞到位的那几样，和进不去时摆回原样的办法 */
function leaveForGame() {
  launcher.classList.add('is-entering')
  const steps: (() => void)[] = [() => launcher.classList.remove('is-entering')]
  const flown: HTMLElement[] = []
  if (!stageCalm() && !isCompact()) {
    const plate = $('town-clock'),
      residents = $('town-residents')
    const plans: [HTMLElement, number, number, number?][] = []
    if (!plate.hidden) plans.push([plate, 14, 14])
    // 没玩过的镇没有时钟牌，游戏里会有：开始钮落在它右边大概的位置
    plans.push([enter, plate.hidden ? 187 : 14 + plate.offsetWidth + 8, 14, 58])
    if (!residents.hidden) plans.push([residents, 14, 82])
    // 先都量好再动：谁先离开原位都会挤动别人。原位留一个同样大的空当，旁边的东西不跳
    const boxes = plans.map(([el]) => el.getBoundingClientRect())
    plans.forEach(([el, left, top, width], i) => {
      const box = boxes[i]
      const gap = document.createElement('div')
      gap.style.cssText = `flex:none;width:${box.width}px;height:${box.height}px;margin:${getComputedStyle(el).margin}`
      el.before(gap)
      const before = el.style.cssText
      el.classList.add('is-flying')
      Object.assign(el.style, {
        position: 'fixed',
        left: `${box.left}px`,
        top: `${box.top}px`,
        width: `${box.width}px`,
        margin: '0',
      })
      void el.offsetWidth
      el.style.left = `${left}px`
      el.style.top = `${top}px`
      if (width) el.style.width = `${width}px`
      flown.push(el)
      steps.push(() => {
        el.classList.remove('is-flying')
        el.style.cssText = before
        gap.remove()
      })
    })
  }
  return {
    done: Promise.all([
      stageCamera.enter(),
      new Promise((resolve) => setTimeout(resolve, flown.length ? 760 : 0)),
    ]),
    flown,
    undo() {
      stageCamera.back()
      for (const step of steps.reverse()) step()
    },
  }
}
/** 正在进镇的那场转场；没在进镇时为空 */
let leaving: ReturnType<typeof leaveForGame> | undefined
/** 没进成，或者从游戏页按后退回到这一页（浏览器把这页原样留着）：界面摆回原样 */
function cancelLeaving() {
  leaving?.undo()
  leaving = undefined
  enter.disabled = deleting || !selected?.available
}
window.addEventListener('pageshow', (event) => {
  if (event.persisted) cancelLeaving()
})
enter.onclick = async () => {
  if (!selected?.available || deleting || leaving) return
  const map = selected
  enter.disabled = true
  setScenic(false)
  $('pause-status').textContent = '正在打开小镇…'
  const going = (leaving = leaveForGame())
  // 小镇开得慢时（世界进程冷启动）：零件都散开了，画面中间说一声
  const slow = setTimeout(() => {
    $('preview-state').textContent = '正在进入小镇…'
    $('preview-state').hidden = false
  }, 1500)
  try {
    const [runtime] = await Promise.all([openMap(map.id), going.done])
    await pauseWorld(runtime.endpoint)
    // 最后一帧和飞到位的那几样交给游戏页，垫着等场景建好（enterHandoff.ts）
    const image = shownPreview()?.map.still?.(2400)
    if (image) saveHandoff(map.id, image, going.flown)
    location.assign(gameUrl(map))
  } catch (error) {
    cancelLeaving()
    $('pause-status').textContent = errorText(error)
  } finally {
    clearTimeout(slow)
    $('preview-state').hidden = true
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
    forgetCover(map.id)
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
    forgetCover(map.id)
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
// 建镇：地图在页面里生成，管理服务校验成品后保存（见 localCreation.ts）
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
// ← → 换到旁边那张明信片（赏景时这两个键归景色条换时刻；建镇页、设定页开着时不管）
document.addEventListener('keydown', (event) => {
  if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return
  if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return
  if (launcher.hidden || launcher.classList.contains('is-scenic') || building || deleting) return
  if (leaving) return
  const target = event.target instanceof Element ? event.target : null
  if (target?.closest('input, textarea, select, [contenteditable], dialog')) return
  if (document.querySelector('dialog[open]')) return
  const cards = [...document.querySelectorAll<HTMLElement>('[data-map-id]')]
  const at = cards.findIndex((card) => card.getAttribute('aria-pressed') === 'true')
  const next = cards[at + (event.key === 'ArrowLeft' ? -1 : 1)]
  if (at < 0 || !next) return
  event.preventDefault()
  next.focus({ preventScroll: true })
  next.click()
})
// 第一次来（一个镇都没玩过）：一句话说清这是什么游戏，和游戏里的新手提示同一张小卡，点「知道了」不再出现
const INTRO_KEY = 'town:launcher-intro'
function showIntro() {
  const seen = (() => {
    try {
      return localStorage.getItem(INTRO_KEY) === '1'
    } catch {
      return false
    }
  })()
  if (seen || maps.some((m) => m.progress) || document.querySelector('.launcher-intro')) return
  const card = document.createElement('div'),
    text = document.createElement('p'),
    row = document.createElement('div'),
    note = document.createElement('small'),
    ok = document.createElement('button')
  card.className = 'launcher-intro'
  card.setAttribute('role', 'status')
  text.textContent =
    '这里的村民是 AI：自己起床、做饭、串门、聊天，还记得发生过的事。挑一张明信片进去，在旁边看，或者和大家说说话。'
  note.textContent = '新手提示 · 只出现一次'
  ok.type = 'button'
  ok.textContent = '知道了'
  ok.onclick = () => {
    card.remove()
    try {
      localStorage.setItem(INTRO_KEY, '1')
    } catch {
      // 存不了就只在这次打开里收起
    }
  }
  row.append(note, ok)
  card.append(text, row)
  query(document, '.launcher-notes').append(card)
}
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
void refresh().then((ok) => ok && showIntro())
