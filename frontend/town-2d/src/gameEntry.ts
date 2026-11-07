import 'town-shared/style.css'
import shell from 'town-shared/gameShell.html?raw'
import { $ } from 'town-shared/dom'
import { errorText } from 'town-shared/format'
import { openMap } from './launcher/catalog'
import { installPlatform } from 'town-shared/platform'
import { installSelects } from 'town-shared/design/select'
import { installFavicon } from 'town-shared/brand/brand'
installPlatform()
installSelects()
installFavicon()
document.body.innerHTML = shell

const query = new URLSearchParams(location.search)
const id = query.get('map')
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
      await startGame(entry)
    }
    $('game-loading').hidden = true
    $('obs-view').hidden = false
  } catch (error) {
    $('game-loading-title').textContent = '小镇加载失败'
    $('game-loading-message').textContent =
      error instanceof Error ? errorText(error) : '请重新加载，或返回小镇列表。'
    const retry = $('game-retry')
    retry.hidden = false
    retry.onclick = () => location.reload()
  }
}
