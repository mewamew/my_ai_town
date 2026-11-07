// 将 HD-2D 界面部件放进 gameShell.html 的骨架，不替换已建好的地图容器。
// 地图页没有顶栏：时钟牌、世界观、菜单都浮在地图上（plain.html 的 map 槽），#topbar 留空藏起来。
import plainParts from './plain.html?raw'
import { decorateIcons } from '../game/icons'
import { decoratePixels } from '../game/pixel'
import { $ } from '../dom'
import './hud.css'

export function installLayout() {
  const parts = document.createElement('template')
  parts.innerHTML = plainParts
  const slot = (name: string) => {
    const template = parts.content.querySelector<HTMLTemplateElement>(
      `template[data-slot="${name}"]`
    )
    if (!template) return null
    const fragment = document.importNode(template.content, true)
    decorateIcons(fragment)
    decoratePixels(fragment)
    return fragment
  }
  $('topbar').replaceChildren()
  $('info-panel').replaceChildren(slot('info-panel') ?? '')
  const mapButtons = slot('map')
  if (mapButtons) $('map').prepend(mapButtons)
  const dock = slot('obs-view')
  if (dock) $('obs-view').append(dock)
  const dialogs = slot('body')
  if (dialogs) document.body.append(dialogs)
}
