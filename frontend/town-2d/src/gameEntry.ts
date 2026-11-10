import 'town-shared/style.css'
import shell from 'town-shared/gameShell.html?raw'
import { $ } from 'town-shared/dom'
import { errorText } from 'town-shared/format'
import { openMap } from './launcher/catalog'
import { installPlatform } from 'town-shared/platform'
import { installSelects } from 'town-shared/design/select'
import { installFavicon } from 'town-shared/brand/brand'
import { takeHandoff } from './enterHandoff'
installPlatform()
installSelects()
installFavicon()
document.body.innerHTML = shell

const query = new URLSearchParams(location.search)
const id = query.get('map')
/** 从选镇页点「进入游戏」过来：选镇页的最后一帧垫在加载页上，飞到左上角的那几样也在，
 *  场景建好再淡出（见 enterHandoff.ts）。直接打开、刷新时没有，照旧是白底的加载页 */
const handoff = id && !query.has('replay') ? takeHandoff(id) : undefined
const loading = $('game-loading')
const ghost = document.createElement('div')
if (handoff) {
  loading.classList.add('has-backdrop')
  loading.style.backgroundImage = `url("${handoff.image}")`
  ghost.innerHTML = handoff.ghost
  loading.append(ghost)
} else document.documentElement.classList.remove('entering')
/** 垫着的画面撤掉（出错时马上撤，换回白底的加载页说明原因） */
function dropBackdrop() {
  loading.classList.remove('has-backdrop', 'is-leaving')
  loading.style.backgroundImage = ''
  ghost.remove()
  document.documentElement.classList.remove('entering')
}
if (!id) location.replace(new URL('./', location.href))
else {
  try {
    if (query.has('replay')) {
      // 重演录像拍素材：不开世界，等拍摄脚本递进来地图和录像（scripts/replay/shoot.mjs）
      $('game-loading-message').textContent = '正在等录像'
      const { startReplay } = await import('./replay/boot')
      await startReplay(id)
    } else {
      $('game-loading-message').textContent = '正在连接世界并准备画面'
      const [entry, { startGame }] = await Promise.all([openMap(id), import('./main')])
      $('game-loading-message').textContent = '正在读取地图与场景缓存'
      const map = await startGame(entry)
      if (handoff) {
        // 地图在垫着的画面底下建：等立体场景画出来（最多等 8 秒）再淡出，不露出半成品
        $('obs-view').hidden = false
        await Promise.race([map.ready, new Promise((resolve) => setTimeout(resolve, 8000))])
        loading.classList.add('is-leaving')
        setTimeout(() => {
          loading.hidden = true
          dropBackdrop()
        }, 650)
      }
    }
    if (!handoff) loading.hidden = true
    $('obs-view').hidden = false
  } catch (error) {
    dropBackdrop()
    $('game-loading-title').textContent = '小镇加载失败'
    $('game-loading-message').textContent =
      error instanceof Error ? errorText(error) : '请重新加载，或返回小镇列表。'
    const retry = $('game-retry')
    retry.hidden = false
    retry.onclick = () => location.reload()
  }
}
