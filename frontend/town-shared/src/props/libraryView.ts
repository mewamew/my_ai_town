// 道具页「可复用道具库」视图：一件道具一行，右栏是定义详情与放入当前地图的表单；道具包的导出与读取也在这里。
import { newId } from '../ids'
import { defaultAppearance, savedAppearance, validateAppearance } from './appearances'
import { actionList, listRow } from './detail'
import { caption, slot } from '../design/ui'
import { propPicture } from './picture'
import { button, el, field, input, select } from './dom'
import type { PropsView } from './pageState'
import type { Definition, PropCatalog } from './types'

/** 「编号@版本」里的编号 */
export const definitionId = (reference: string | null | undefined) =>
  (reference ?? '').split('@')[0]

/** 每件道具只留最新一版：「修改」每存一次多一个版本，旧版本留给镇上已经摆着的那几件，玩家不用看见 */
export function latestVersions(definitions: Definition[]) {
  const latest = new Map<string, Definition>()
  for (const d of definitions) {
    const old = latest.get(d.id)
    if (!old || d.version > old.version) latest.set(d.id, d)
  }
  return [...latest.values()]
}

/** 镇上用着这件道具（哪一版都算）的东西：摆着的、背包里的、容器里的；撤下的公告不算 */
function townCopies(c: PropCatalog, id: string) {
  return c.instances.filter((p) => !p.withdrawn && definitionId(p.definition) === id)
}

export function renderLibrary(view: PropsView, c: PropCatalog, q: string) {
  const { state, page } = view
  const items = latestVersions(c.definitions).filter((d) =>
    `${d.name} ${d.id} ${d.actions.map((a) => a.label).join(' ')}`.toLowerCase().includes(q)
  )
  page.list.append(el('p', `${items.length} 件道具`, 'prop-count'))
  // 不写版本号：同一件道具改过几次对玩家没有意义，自带的和自己做的分开就够了；镇上有几件写在后面，删之前就看得到
  for (const d of items) {
    const copies = townCopies(c, d.id).length
    const origin = d.id.startsWith('core:') ? '自带的' : '自己做的'
    listRow(view, d.name, `${d.id}@${d.version}`, [
      el('small', copies ? `${origin} · 镇上有 ${copies} 件` : origin),
    ])
  }
  // 选中的是旧版本（别的页面刚改过它）时跟到同一件的最新版
  const d = items.find((d) => d.id === definitionId(state.selected)) ?? items[0]
  if (!d) {
    page.detail.append(el('p', '道具库里没有匹配内容。'))
    return
  }
  state.selected = `${d.id}@${d.version}`
  renderDefinition(view, c, d)
}

function renderDefinition(view: PropsView, c: PropCatalog, d: Definition) {
  const { detail } = view.page
  const reference = `${d.id}@${d.version}`
  const head = el('header', '', 'pd-head')
  const id = el('div', '', 'pd-id')
  const meta = el('div', '', 'pd-meta')
  meta.append(
    el('span', d.id.startsWith('core:') ? '自带的' : '自己做的'),
    el('span', d.portable ? '可以放进背包' : '固定在原地')
  )
  if (d.storage_slots) meta.append(el('span', `能存放 ${d.storage_slots} 格`))
  const copies = townCopies(c, d.id).length
  if (copies) meta.append(el('span', `镇上有 ${copies} 件`))
  id.append(el('h2', d.name, 'ui-title pd-name'), meta)
  head.append(slot(propPicture(reference, d.readable ? 'book' : 'bag'), 'md'), id)
  detail.append(head, el('p', d.description || '暂无说明', 'pd-desc'))
  const buttons = el('div', '', 'pd-foot')
  buttons.append(
    button(d.id.startsWith('core:') ? '复制并修改' : '修改', () => view.edit(d)),
    button('导出道具包', () => exportPackage(d))
  )
  const actions = el('section', '', 'pd-section')
  actions.append(caption('可以做的事'))
  actionList(actions, c.definition_actions[reference] ?? [], d, view.needLabel)
  const place = el('section', '', 'pd-section')
  place.append(caption('放进小镇'), placementForm(view, c, d))
  detail.append(actions, place, buttons)
}

/** 把定义放进当前地图：地点、实例名，公告还要挑同地点的公告栏。 */
function placementForm(view: PropsView, c: PropCatalog, d: Definition) {
  const box = el('div')
  const reference = `${d.id}@${d.version}`
  const place = select(
    c.locations.map((l) => ({ id: l.id, label: l.name })),
    c.locations[0]?.id ?? '',
    'place-locale'
  )
  const instanceName = input(d.name, 'instance-name')
  box.append(field('放到哪里', place), field('在镇上叫什么', instanceName))
  const board = select(
    c.instances
      .filter((p) => p.bulletin_board && !p.withdrawn)
      .map((p) => ({ id: p.id, label: `${p.name} · ${view.localeName(p.locale)}` })),
    '',
    'place-board'
  )
  const isBulletin = d.readable?.kind === 'bulletin'
  if (isBulletin) box.append(field('关联公告栏（须同一地点）', board))
  box.append(
    button(
      '放入当前地图',
      () =>
        view.sendWorldCommand('place_prop', (world_id, request_id) => ({
          type: 'place_prop',
          request_id,
          world_id,
          instance: {
            id: `user:${newId()}`,
            definition: reference,
            locale: place.value,
            name: instanceName.value.trim(),
            board: isBulletin ? board.value : undefined,
          },
        })),
      'prop-primary'
    ),
    el(
      'p',
      '放出去的是新的一件，和原来那件互不影响；没摆好位置时会先标在这个地点上。',
      'prop-muted'
    )
  )
  return box
}

/** 道具包：功能定义加本机保存的外观 */
function exportPackage(d: Definition) {
  const appearance = savedAppearance(`${d.id}@${d.version}`) ?? defaultAppearance
  const blob = new Blob(
    [JSON.stringify({ schema_version: 1, definition: structuredClone(d), appearance }, null, 2)],
    { type: 'application/json' }
  )
  const url = URL.createObjectURL(blob)
  const a = el('a')
  a.href = url
  a.download = d.id.replace(':', '-') + '-v' + d.version + '.json'
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

/** 读道具包；内置定义改成玩家自己的新编号与第 1 版，格式不对时抛出原因 */
export async function readPackage(f: File) {
  if (f.size > 2000000) throw new Error('道具包不能超过 2 MB')
  const pack = JSON.parse(await f.text())
  if (pack.schema_version !== 1 || !pack.definition) throw new Error('不支持的道具包格式')
  const appearance = pack.appearance ? validateAppearance(pack.appearance) : defaultAppearance
  const definition = pack.definition as Definition
  if (definition.id?.startsWith('core:')) {
    definition.id = `player:import_${newId().slice(0, 8)}`
    definition.version = 1
    if (definition.readable) {
      definition.readable.origin = { kind: 'player' }
      definition.readable.work_id = definition.id
      definition.readable.version = 1
    }
  }
  return { definition, appearance }
}
