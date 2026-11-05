import { button, el } from '../dom'
import { newId } from '../ids'
import type { ModelOption } from '../models/session'
import type {
  ClientMsg,
  JoinOutcome,
  JoinPreview,
  ModelChoice,
  PhysiologySwitches,
  ServerMsg,
} from '../protocol'
import type { ShellPanel } from '../shell/panel'
import type { createWorldSettings } from '../worldSettings'
import type { Prefab } from '.'

// 开局设置：第一次进预制小镇（还没设世界观）时代替开局向导。玩家只改四项：人数、每位选手用的模型、
// 圈的位置（每局随机或固定种子）、吃喝睡开不开；世界观、玩法和其余设定由预制小镇写好。
// 点「开始这一局」依次保存世界观、生理开关，按号码请人入住（入住时带上各自的模型），最后打开玩法；
// 哪一步出错就停在那一步说明原因，再点一次从那一步接着做。做完世界还停着，玩家在顶栏点开始。
// 跳过就交回原来的首次对话框，像普通小镇一样自己设。

type Waiter = { match: (m: ServerMsg) => unknown; resolve: (v: unknown) => void }

const ALL_OFF: PhysiologySwitches = {
  fullness: false,
  energy: false,
  water: false,
  health: false,
  weather: false,
}

export function createPrefabSetup(d: {
  send: (msg: ClientMsg) => void
  worldSettings: ReturnType<typeof createWorldSettings>
  /** 能用的模型；没连模型时为空，选手先住下，连上模型后才行动 */
  modelOptions: () => ModelOption[]
  /** 做完时：请进来的居民编号（按号码） */
  onFinish: (joined: string[]) => void
}) {
  const root = el('div', '', 'guide prefab-setup')
  root.hidden = true
  root.setAttribute('role', 'dialog')
  root.setAttribute('aria-label', '开局设置')
  const card = el('section', '', 'guide-card')
  const top = el('div', '', 'guide-top')
  const title = el('b', '', 'prefab-title')
  const skip = button('跳过', () => close(), 'guide-skip')
  top.append(title, skip)
  const body = el('div', '', 'guide-body')
  const foot = el('div', '', 'guide-foot one')
  card.append(top, body, foot)
  root.append(card)
  document.body.append(root)

  let prefab: Prefab | null = null
  let players = 0
  /** 每个号码的模型；null 是没连模型、先住下 */
  let models: (ModelChoice | null)[] = []
  let fixedSeed = false
  let seed = 51
  let needs = true
  /** 村民库里的名字（模板编号 → 名字），读到之前显示编号 */
  const names = new Map<string, string>()
  // 做到哪一步了：出错后从这里接着做
  let running = false
  let status = ''
  let worldviewSaved = false
  let needsSaved = false
  let modeSaved = false
  const joined: (string | null)[] = []

  const waiters: Waiter[] = []
  function waitFor<T>(match: (m: ServerMsg) => T | undefined, ms = 15000) {
    return new Promise<T>((resolve, reject) => {
      const waiter: Waiter = { match, resolve: resolve as (v: unknown) => void }
      waiters.push(waiter)
      setTimeout(() => {
        const i = waiters.indexOf(waiter)
        if (i < 0) return
        waiters.splice(i, 1)
        reject(Error('小镇没有及时回应，请检查连接后再点一次'))
      }, ms)
    })
  }
  /** 世界设定的保存：成功时接着往下走，失败时带着原因停下 */
  const saved = (submit: (done: (ok: boolean, message: string) => void) => void) =>
    new Promise<void>((resolve, reject) =>
      submit((ok, message) => (ok ? resolve() : reject(Error(message))))
    )

  function slotModel(i: number) {
    const options = d.modelOptions()
    const chosen = models[i]
    return (
      options.find((o) => o.provider === chosen?.provider && o.model === chosen.model) ??
      options[0] ??
      null
    )
  }

  function render() {
    if (!prefab) return
    title.textContent = `${prefab.name} · 开局设置`
    skip.hidden = running
    const p = prefab
    const intro = el('p', p.description)
    const rows = el('div', '', 'prefab-rows')

    const count = el('div', '', 'prefab-count')
    const less = button('−', () => setPlayers(players - 1), 'prefab-step')
    const more = button('+', () => setPlayers(players + 1), 'prefab-step')
    less.disabled = running || players <= p.players.min
    more.disabled = running || players >= p.players.max
    less.setAttribute('aria-label', '少一个人')
    more.setAttribute('aria-label', '多一个人')
    count.append(
      less,
      el('b', String(players)),
      more,
      el('small', `${p.players.min}～${p.players.max} 人`)
    )
    rows.append(row('人数', count))

    const options = d.modelOptions()
    const roster = el('div', '', 'prefab-roster')
    for (let i = 0; i < players; i++) {
      const id = p.roster[i]
      const slot = el('label', '', 'prefab-slot')
      slot.append(el('span', `${i + 1} 号 · ${names.get(id) ?? id}`, 'prefab-who'))
      if (options.length) {
        const select = el('select')
        select.disabled = running || joined[i] !== undefined
        for (const o of options) {
          const option = el('option', `${o.name} · ${o.model}`)
          option.value = `${o.provider}\n${o.model}`
          select.append(option)
        }
        const current = slotModel(i)
        if (current) select.value = `${current.provider}\n${current.model}`
        select.onchange = () => {
          const [provider, model] = select.value.split('\n')
          models[i] = { provider, model }
        }
        slot.append(select)
      }
      roster.append(slot)
    }
    rows.append(row('选手', roster))
    if (!options.length)
      rows.append(row('', el('p', '还没连接模型：选手先住下，连上模型后才会行动。', 'guide-note')))

    const circles = el('div', '', 'prefab-radio')
    const random = radio('每局随机', !fixedSeed, () => {
      fixedSeed = false
      render()
    })
    const fixed = radio('固定种子', fixedSeed, () => {
      fixedSeed = true
      render()
    })
    const seedInput = el('input', '', 'prefab-seed')
    seedInput.type = 'number'
    seedInput.min = '1'
    seedInput.max = '4294967295'
    seedInput.value = String(seed)
    seedInput.disabled = running || !fixedSeed
    seedInput.setAttribute('aria-label', '种子')
    seedInput.onchange = () => {
      const n = Math.floor(Number(seedInput.value))
      if (Number.isFinite(n) && n >= 1 && n <= 4294967295) seed = n
      seedInput.value = String(seed)
    }
    circles.append(random, fixed, seedInput)
    rows.append(row('圈的位置', circles))

    const toggle = el('label', '', 'prefab-switch')
    const box = el('input')
    box.type = 'checkbox'
    box.setAttribute('role', 'switch')
    box.checked = needs
    box.disabled = running || needsSaved
    box.onchange = () => {
      needs = box.checked
      render()
    }
    toggle.append(box, el('span', needs ? '开：要吃要喝要睡，站在水里掉体力' : '关：只比谁会躲水'))
    rows.append(row('吃喝睡', toggle))

    const note = el(
      'p',
      '世界观、潮水的时间表和天气已经写好，不用改。用在线模型会产生费用。',
      'guide-note'
    )
    body.replaceChildren(el('h2', p.name), intro, rows, note)
    if (status) body.append(el('p', status, 'guide-note prefab-status'))

    const go = button(running ? '正在开局…' : '开始这一局', () => void start(), 'primary')
    go.disabled = running
    foot.replaceChildren(go)
  }

  function row(label: string, content: HTMLElement) {
    const line = el('div', '', 'prefab-row')
    line.append(el('span', label), content)
    return line
  }
  function radio(label: string, on: boolean, pick: () => void) {
    const b = button(label, pick, 'prefab-option' + (on ? ' on' : ''))
    b.setAttribute('aria-pressed', String(on))
    b.disabled = running
    return b
  }
  function setPlayers(n: number) {
    if (!prefab) return
    players = Math.min(prefab.players.max, Math.max(prefab.players.min, n))
    render()
  }

  async function join(templateId: string, model: ModelChoice | null): Promise<string> {
    d.send({ type: 'preview_resident_join', template_id: templateId })
    const preview: JoinPreview = await waitFor((m) =>
      m.type === 'join_preview' && m.preview.template_id === templateId ? m.preview : undefined
    )
    if (!preview.ok) throw Error(preview.problems.join('；') || '现在不能加入')
    const world = d.worldSettings.state()
    if (!world) throw Error('还没读到世界设定')
    const op_id = newId()
    d.send({
      type: 'join_resident',
      op_id,
      world_id: world.world_id,
      template_id: templateId,
      template_version: preview.template_version,
      name: preview.name,
      home: preview.home,
      ...(model ? { model } : {}),
    })
    const outcome: JoinOutcome = await waitFor((m) =>
      m.type === 'resident_joined' && m.outcome.op_id === op_id
        ? m.outcome
        : m.type === 'join_result' && m.op_id === op_id
          ? (m.outcome ?? undefined)
          : undefined
    )
    if (!outcome.ok || !outcome.resident_id) throw Error(outcome.message)
    return outcome.resident_id
  }

  async function start() {
    const p = prefab
    if (!p || running) return
    running = true
    status = ''
    render()
    const ws = d.worldSettings
    try {
      if (!worldviewSaved) {
        status = '正在写世界观…'
        render()
        await saved((done) => ws.saveWorldview(p.worldview, done))
        worldviewSaved = true
      }
      if (!needsSaved) {
        status = '正在设定吃喝睡…'
        render()
        const revision = ws.state()?.revision
        if (revision === undefined) throw Error('还没读到世界设定')
        await saved((done) => ws.savePhysiology(needs ? p.needs : ALL_OFF, revision, done))
        needsSaved = true
      }
      for (let i = 0; i < players; i++) {
        if (joined[i]) continue
        status = `正在请 ${i + 1} 号入住…`
        render()
        joined[i] = await join(p.roster[i], slotModel(i))
      }
      if (!modeSaved) {
        status = '正在打开玩法…'
        render()
        const choice = { ...p.gameMode, ...(fixedSeed ? { seed } : {}) }
        await saved((done) => ws.saveGameMode(choice, done))
        modeSaved = true
      }
      running = false
      root.hidden = true
      d.onFinish(joined.filter((id): id is string => !!id))
    } catch (error) {
      running = false
      status = `${status.replace(/…$/, '')}时出错：${error instanceof Error ? error.message : String(error)}。再点一次「开始这一局」从这一步接着做。`
      render()
    }
  }

  function close() {
    if (running) return
    root.hidden = true
    // 跳过：交回首次对话框，像普通小镇一样自己设
    d.worldSettings.setFirstRun(null)
  }

  const panel: ShellPanel = {
    handleMsg(m: ServerMsg) {
      if (m.type === 'resident_library') {
        for (const t of m.templates) names.set(t.template_id, t.name)
        if (!root.hidden) render()
      }
      for (const w of [...waiters]) {
        const value = w.match(m)
        if (value !== undefined) {
          waiters.splice(waiters.indexOf(w), 1)
          w.resolve(value)
        }
      }
    },
  }

  return {
    panel,
    /** 打开这个预制小镇的开局设置 */
    open(p: Prefab) {
      prefab = p
      players = p.players.default
      models = []
      root.hidden = false
      d.send({ type: 'get_resident_library', filter: { kind: 'builtin' } })
      render()
    },
    /** 模型配置变了（连上了新模型）：重画选择框 */
    refresh() {
      if (!root.hidden && !running) render()
    },
  }
}
