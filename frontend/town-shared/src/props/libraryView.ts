// 道具页「可复用道具库」视图：一件道具一行，右栏是定义详情与放入当前地图的表单；道具包的导出与读取也在这里。
import { newId } from '../ids'
import {
  defaultAppearance,
  forgetAppearance,
  savedAppearance,
  validateAppearance,
} from './appearances'
import { actionList, listRow } from './detail'
import { caption, slot } from '../design/ui'
import { propPicture } from './picture'
import { button, el, field, input, select } from './dom'
import type { PropsView } from './pageState'
import type { Definition, PropCatalog, PropView } from './types'

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
  const at = Math.max(
    0,
    items.findIndex((d) => d.id === definitionId(state.selected))
  )
  const d = items[at]
  if (!d) {
    page.detail.append(el('p', '道具库里没有匹配内容。'))
    return
  }
  state.selected = `${d.id}@${d.version}`
  // 删掉这件以后选中下一件；删的是最后一件就选上一件
  const after = items[at + 1] ?? items[at - 1]
  renderDefinition(view, c, d, after ? `${after.id}@${after.version}` : '')
}

function renderDefinition(view: PropsView, c: PropCatalog, d: Definition, next: string) {
  const { detail } = view.page
  const reference = `${d.id}@${d.version}`
  const own = !d.id.startsWith('core:')
  const head = el('header', '', 'pd-head')
  const id = el('div', '', 'pd-id')
  const meta = el('div', '', 'pd-meta')
  meta.append(
    el('span', own ? '自己做的' : '自带的'),
    el('span', d.portable ? '可以放进背包' : '固定在原地')
  )
  if (d.storage_slots) meta.append(el('span', `能存放 ${d.storage_slots} 格`))
  const copies = townCopies(c, d.id).length
  if (copies) meta.append(el('span', `镇上有 ${copies} 件`))
  id.append(el('h2', d.name, 'ui-title pd-name'), meta)
  head.append(slot(propPicture(reference, d.readable ? 'book' : 'bag'), 'md'), id)
  detail.append(head, el('p', d.description || '暂无说明', 'pd-desc'))
  const actions = el('section', '', 'pd-section')
  actions.append(caption('可以做的事'))
  actionList(actions, c.definition_actions[reference] ?? [], d, view.needLabel)
  const place = el('section', '', 'pd-section')
  place.append(caption('放进小镇'), placementForm(view, c, d))
  // 换了一件看，上一件没确认的删除就作罢
  if (view.state.confirmDelete !== d.id) view.state.confirmDelete = ''
  const foot = own && view.state.confirmDelete ? deleteConfirm(view, c, d, next) : buttons(view, d)
  detail.append(actions, place, foot)
}

/** 详情底下的按钮条：自己做的最右边是红字「删除」，和改、导出隔开免得手滑；自带的在那儿说一句删不了 */
function buttons(view: PropsView, d: Definition) {
  const own = !d.id.startsWith('core:')
  const foot = el('div', '', 'pd-foot')
  foot.append(
    button(own ? '修改' : '复制并修改', () => view.edit(d)),
    button('导出道具包', () => exportPackage(d))
  )
  if (!own) {
    foot.append(el('span', '自带的删不了', 'pd-foot-note'))
    return foot
  }
  const remove = button(
    '删除',
    () => {
      view.state.confirmDelete = d.id
      view.render()
      // 焦点放在「取消」上：键盘一按回车不会误删，焦点留在详情里，目录刷新也不重画这块
      view.page.detail.querySelector<HTMLElement>('.pd-confirm button')?.focus({
        preventScroll: true,
      })
    },
    'ui-btn danger pd-delete'
  )
  foot.append(remove)
  return foot
}

/** 镇上已经摆着的那几件在哪，确认时和删完以后各说一句；镇上没有就都不说。
 *  一处只写地方名，几处的写各有几件，地方太多只写前三处 */
function keptCopies(view: PropsView, copies: PropView[]) {
  if (!copies.length) return { before: '', after: '' }
  const count = new Map<string, number>()
  for (const p of copies) {
    const where =
      p.location?.kind === 'carried'
        ? `${p.location_name ?? '村民'}的背包`
        : p.location?.kind === 'stored'
          ? `${p.location_name ?? '容器'}里`
          : view.localeName(p.locale)
    count.set(where, (count.get(where) ?? 0) + 1)
  }
  const parts = [...count].map(([where, n]) =>
    count.size > 1 && n > 1 ? `${where} ${n} 件` : where
  )
  const text =
    parts.length > 3 ? `${parts.slice(0, 3).join('、')}等 ${parts.length} 处` : parts.join('、')
  const n = copies.length
  return {
    before: `镇上已经摆着的 ${n} 件（${text}）还在，不受影响。`,
    after: `镇上已经摆着的${n === 1 ? '那' : ''} ${n} 件还在${count.size > 1 ? '：' : ''}${text}。`,
  }
}

/** 点了「删除」：按钮条原地换成一块确认，照设定里「删除内置模型？」，不弹系统对话框。
 *  删的是道具库里这件的所有版本；镇上已经摆着的各自存着整份定义，不受影响，这里写清楚在哪 */
function deleteConfirm(view: PropsView, c: PropCatalog, d: Definition, next: string) {
  const kept = keptCopies(view, townCopies(c, d.id))
  const box = el('div', '', 'pd-confirm')
  box.append(
    el('strong', `删除「${d.name}」？`),
    el('p', '道具库里不再有它，以后也不能再往镇上放。')
  )
  if (kept.before) box.append(el('p', kept.before))
  const cancel = button('取消', () => {
    view.state.confirmDelete = ''
    view.render()
  })
  const yes = button(
    '删除',
    () => {
      const sent = view.sendWorldCommand(
        'delete_prop',
        (_, request_id) => ({ type: 'delete_prop', request_id, id: d.id }),
        (ok, message) => {
          view.state.confirmDelete = ''
          if (ok) {
            view.state.selected = next
            forgetUnusedAppearances(view.state.catalog ?? c, d.id)
            view.report(`${message}。${kept.after}`)
          }
          view.render()
        }
      )
      if (!sent) return
      cancel.disabled = yes.disabled = true
      yes.textContent = '正在删除…'
    },
    'pd-confirm-delete'
  )
  const row = el('div', '', 'pd-confirm-actions')
  row.append(cancel, yes)
  box.append(row)
  return box
}

/** 删掉的道具各版本的外观：镇上还有东西用着的那一版留着（地图画它要用），其余的清掉 */
function forgetUnusedAppearances(c: PropCatalog, id: string) {
  const used = new Set(c.instances.map((p) => p.definition))
  for (const d of c.definitions)
    if (d.id === id && !used.has(`${d.id}@${d.version}`)) forgetAppearance(`${d.id}@${d.version}`)
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
