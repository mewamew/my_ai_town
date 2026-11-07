// 角色卡 → 长相：捏这位居民在小镇里的像素小人。只改这一位，村民库里的模板不变；
// 切到这一页时卡片拉到最宽，保存后地图上马上换上。
import { el, statusLine } from '../dom'
import {
  currentPopulation,
  lookKey,
  onPopulation,
  registrationOf,
  residentPortraitKey,
} from '../portraits'
import type { VillagerLook } from '../protocol'
import { createLookEditor, lookFor } from '../residents/look'
import type { CardPageDeps, TabPage } from './tabs'

export function createLookPage(deps: CardPageDeps): TabPage {
  const { resident } = deps
  const page = el('section', '', 'spage')
  const status = el('div', '', 'page-status')
  const setStatus = statusLine(status)
  /** 登记里现在的长相：捏过的照原样，没捏过的是按模板编号出的那一套 */
  const registered = () => lookFor(residentPortraitKey(resident.id))
  let saved: VillagerLook = registered()
  const editor = createLookEditor(saved, () => deps.onDirty())
  const isDirty = () => lookKey(editor.value()) !== lookKey(saved)
  page.append(
    el('h2', `${resident.name} · 长相`),
    el(
      'p',
      `挑发型、衣服、颜色和配饰，再在小格子里点出衣服上的花纹。只改${resident.name}，村民库里的模板不变；保存后小镇里马上换上。`,
      'hint'
    ),
    editor.root,
    status
  )
  // 人口刚到或别的页面改了长相：这里没在改就跟着换
  onPopulation(() => {
    if (isDirty()) return
    saved = registered()
    editor.set(saved)
  })

  return {
    title: `${resident.name}的长相`,
    el: page,
    isDirty,
    save() {
      const population = currentPopulation()
      const registration = registrationOf(resident.id)
      if (!population || !registration) {
        setStatus('✗ 还没读到居民名单，稍后再保存', 'drop')
        return
      }
      const look = editor.value()
      setStatus('保存中…')
      deps.save(
        {
          type: 'set_resident_appearance',
          world_id: population.world_id,
          expected_revision: population.revision,
          resident_id: resident.id,
          appearance: { ...registration.appearance, look },
        },
        (ok, message) => {
          if (ok) {
            saved = look
            setStatus(`✓ ${message}`, 'ok')
          } else setStatus(`✗ ${message}`, 'drop')
          deps.onDirty()
        }
      )
    },
    discard() {
      editor.set(saved)
      setStatus('已放弃修改，恢复为保存过的长相')
      deps.onDirty()
    },
    onShow: () => editor.wake(),
  }
}
