// 开局向导：第一次进新世界时代替「开始一个新世界」对话框，四步——玩法、连接模型、请居民、世界观。
// 手机和电脑共用，宽屏时居中显示。前三步只记下选择，最后点「开始」才依次保存世界观、请人入住
// （入住时就带上模型）、让世界跑起来，哪一步出错就停在那一步说明原因，再点「开始」从那一步接着做。
// 一句话建的小镇，请居民这一步先列建镇时写的「适合住在这里的人」：开始时用模型按那句话写好人设、
// 存进村民库再请进来。没连模型也能进去：村民先住下等模型，时间停着，化身照样能走。
// 随时可以跳过；跳过后回到原来的首次对话框。
import { button, el } from '../dom'
import { newId } from '../ids'
import { portraitFor, templateKey } from '../portraits'
import type {
  ClientMsg,
  JoinOutcome,
  JoinPreview,
  PopulationView,
  ProviderView,
  ResidentTemplate,
  ServerMsg,
  TemplateCard,
} from '../protocol'
import { keyHelp, keyPlaceholder, QUICK, usableProvider } from '../models/connect'
import {
  builtinReady,
  builtinStatus,
  builtinWaitingWifi,
  downloadBuiltin,
  downloadBuiltinNow,
  megabytes,
  onBuiltin,
  percent,
  progressText,
} from '../models/builtin'
import { isCompact } from '../platform'
import { BUILTIN, PRESETS, providerModel, type ProviderPreset } from '../providers'
import { peopleCount, PICKS, recommendReason, roomLeft } from '../residents/recommend'
import type { Receipt, SaveCommand } from '../connection'
import type { ShellPanel } from '../shell/panel'
import type { SpeedBar } from '../shell/topbar'
import { DEFAULT_WORLDVIEW, townEntryHint, type createWorldSettings } from '../worldSettings'
import { providerSaveCommand } from '../settings/providerCommands'

const DONE_KEY = 'town:guide-done'
/** 第二步列出的服务（和连接模型的弹层同一份）；其余的在设定的「模型服务」里 */
const SHOWN = QUICK.slice(0, 4)
const MAX_PICKS = 5
const LORES: [string, string][] = [
  ['宁静小镇', ''],
  ['海边渔港', '小镇靠海。清晨渔船出港，傍晚在码头卖鱼；大家习惯在市集碰面，交换消息。'],
  ['爱读书的小镇', '镇上的人都爱读书，图书馆是最热闹的地方。公告栏上常贴着读书会和换书的消息。'],
]

export function guideDone() {
  try {
    return localStorage.getItem(DONE_KEY) === '1'
  } catch {
    return false
  }
}
function markDone() {
  try {
    localStorage.setItem(DONE_KEY, '1')
  } catch {
    // 本地存储不可用时下次还会再出现，不影响使用
  }
}

interface GuideDeps {
  send: (msg: ClientMsg) => void
  save: (command: SaveCommand, receipt: Receipt) => void
  /** 一句话建镇时写的适合住进来的人，一人一句；逐步设置的小镇为空 */
  suggestions: string[]
  townName: string
  /** 一句话建镇时玩家那句话；逐步设置的小镇为空 */
  description: string
  worldSettings: ReturnType<typeof createWorldSettings>
  speeds: SpeedBar
  normalSpeed: number
  /** 向导结束（开始或跳过）：开始一次性提示；joined 是这次请进来的居民 */
  onFinish: (started: boolean, joined: string[]) => void
}

type Waiter = { match: (m: ServerMsg) => unknown; resolve: (v: unknown) => void; consume: boolean }

export function createGuide(d: GuideDeps) {
  const root = el('div', '', 'guide')
  root.hidden = true
  root.setAttribute('role', 'dialog')
  root.setAttribute('aria-label', '开局向导')
  const card = el('section', '', 'guide-card')
  const top = el('div', '', 'guide-top')
  const dots = el('div', '', 'guide-dots')
  const skip = button('跳过', () => finish(false), 'guide-skip')
  top.append(dots, skip)
  const body = el('div', '', 'guide-body')
  const foot = el('div', '', 'guide-foot')
  card.append(top, body, foot)
  root.append(card)
  document.body.append(root)

  // 服务端状态与请求回复
  let providers: ProviderView[] = []
  let templates: TemplateCard[] = []
  let population: PopulationView | null = null
  const waiters: Waiter[] = []
  function waitFor<T>(match: (m: ServerMsg) => T | undefined, consume = false, ms = 15000) {
    return new Promise<T>((resolve, reject) => {
      const waiter: Waiter = { match, resolve: resolve as (v: unknown) => void, consume }
      waiters.push(waiter)
      setTimeout(() => {
        const i = waiters.indexOf(waiter)
        if (i < 0) return
        waiters.splice(i, 1)
        reject(Error('服务没有及时回应，请检查连接后重试'))
      }, ms)
    })
  }
  const saved = (command: SaveCommand) =>
    new Promise<string>((resolve, reject) =>
      d.save(command, (ok, message) => (ok ? resolve(message) : reject(Error(message))))
    )

  /** 手机和电脑说法不同的地方：菜单在手机底部、电脑右上角 */
  const phone = () => isCompact()
  const usageAt = () => (phone() ? '底部「菜单 · 消耗」' : '右上角「菜单 · 消耗」')
  // 向导里的选择
  let step = 0
  let preset: ProviderPreset = PRESETS[0]
  let key = ''
  /** idle：还没测；ok：连通了（或已有密钥、测试模式） */
  let test: { state: 'idle' | 'testing' | 'ok' | 'error'; message: string } = {
    state: 'idle',
    message: '',
  }
  let skipModel = false
  /** 从「请居民」开始（玩家之前走过向导）：不经过选模型，用已经存了密钥的那个 */
  let fromSaved = false
  let reuse: { provider: string; model: string; name: string } | null = null
  let activeChoice: { provider: string; model: string } | null = null
  let picks: string[] = []
  /** 选中的「按小镇写的人」：suggestions 里的序号 */
  let wishes: number[] = []
  /** 这次开局已经做完的步骤：出错后再点「开始」时跳过，不重复请人 */
  const done = new Set<string>()
  /** 已经写好、存进村民库的人：请进来那一步出错时，再点「开始」不重写一遍 */
  const written = new Map<number, ResidentTemplate>()
  /** 默认人选只填一次；之后全部取消也不再自动补回 */
  let picked = false
  let lore = ''
  let running = false
  /** 第二步已经连好模型时只显示连好的那个；点「换一个」才展开服务和密钥 */
  let changing = false

  const mock = () => !!d.worldSettings.state()?.mock
  const savedKey = (id: string) => providers.find((p) => p.id === id)?.key_mask ?? ''
  const providerName = (id: string) =>
    providers.find((p) => p.id === id)?.name || PRESETS.find((p) => p.id === id)?.name || id
  /** 已经连好的模型：设定里选的优先，其次第一个能用的服务；测试模式和一个都没连时为 null */
  function connectedChoice() {
    if (mock()) return null
    const usable = providers.filter(usableProvider)
    const active = activeChoice
    if (active && usable.some((p) => p.id === active.provider))
      return { ...active, name: providerName(active.provider) }
    for (const p of usable) {
      const model = providerModel(p.id, p)
      if (model) return { provider: p.id, model, name: providerName(p.id) }
    }
    return null
  }

  /** 内置模型现在走到哪一步：变了才整页重画，进度只改那一行字和进度条 */
  const builtinPhase = () =>
    builtinReady()
      ? 'ready'
      : builtinWaitingWifi()
        ? 'wifi'
        : (builtinStatus()?.download?.state ?? 'none')
  let shownPhase = ''
  const conn = {
    small: el('small'),
    meter: el('div', '', 'ui-meter guide-meter'),
    fill: el('span'),
  }
  conn.meter.append(conn.fill)
  onBuiltin(() => {
    if (root.hidden || step !== 1) return
    if (builtinPhase() !== shownPhase) return render()
    const d = builtinStatus()?.download
    if (d?.state === 'running') conn.small.textContent = progressText(d)
    conn.fill.style.setProperty('--v', String(d?.size ? d.done / d.size : 0))
  })

  function render() {
    dots.replaceChildren(
      ...[0, 1, 2, 3].map((i) => el('i', '', i <= step ? 'on' : '')),
      el('span', `${step + 1} / 4`)
    )
    skip.hidden = running
    body.replaceChildren(...[welcome, model, residents, world][step]())
    body.scrollTop = 0
    renderFoot()
  }
  function renderFoot() {
    foot.className = 'guide-foot' + (step === 0 ? ' one' : '')
    const back = button('上一步', () => {
      step--
      render()
    })
    back.disabled = running
    if (step === 0) {
      foot.replaceChildren(primary('开始准备 · 大约一分钟', () => go(1)))
    } else if (step === 1) {
      const connected = !changing ? connectedChoice() : null
      const ready = !!connected || skipModel || mock() || test.state === 'ok'
      // 用内置模型、还没开始下：先下载，下载时就可以接着往下走
      if (connected?.provider === BUILTIN && builtinPhase() === 'none') {
        const size = builtinStatus()?.latest?.size
        foot.replaceChildren(
          back,
          primary(size ? `下载（${megabytes(size)}）` : '下载', () => void downloadBuiltin())
        )
        return
      }
      foot.replaceChildren(
        back,
        primary(
          ready ? '下一步' : test.state === 'testing' ? '正在连接…' : '测试并继续',
          () => {
            if (!ready) return void runTest(true)
            // 用已经连好的那个：之后请的人都用它
            if (connected) {
              reuse = connected
              skipModel = false
            }
            go(2)
          },
          test.state === 'testing'
        )
      )
    } else if (step === 2) {
      // 已经有人住着（重新看向导时）可以不再请人
      const hasResidents = !!population?.residents.length
      const count = picks.length + wishes.length
      foot.replaceChildren(
        back,
        primary(
          count || !hasResidents ? `请 ${count} 位住进来` : '不再请人，下一步',
          () => go(3),
          count === 0 && !hasResidents
        )
      )
    } else {
      const useDefault = button('用默认的', () => {
        lore = d.worldSettings.defaultWorldview
        void start()
      })
      useDefault.disabled = running
      foot.replaceChildren(
        useDefault,
        primary(
          running ? '正在准备…' : skipModel ? '进入小镇' : '开始',
          () => void start(),
          running
        )
      )
    }
  }
  function primary(text: string, action: () => void, disabled = false) {
    const b = button(text, action, 'primary')
    b.disabled = disabled
    return b
  }
  function go(next: number) {
    step = next
    render()
  }

  // 第一步：玩法；一句话建的小镇先把玩家那句话写在上面
  function welcome() {
    return [
      el('h2', `欢迎来到${d.townName}`),
      ...(d.description ? [el('blockquote', d.description, 'guide-quote')] : []),
      el(
        'p',
        '这里的居民由 AI 自己过日子：起床、做饭、串门、聊天，还会记住发生过的事。你可以在一旁看，点一个人看看此刻在想什么，也可以进去和大家说话。'
      ),
    ]
  }

  function changeButton() {
    return button('换一个', () => {
      changing = true
      render()
    })
  }

  /** 第二步用内置模型：还没下载时请玩家下载（主按钮），下载时显示进度，不用等它下完 */
  function builtinStep(name: string): HTMLElement[] {
    shownPhase = builtinPhase()
    const s = builtinStatus()
    const d = s?.download
    const size = megabytes(d?.size ?? s?.latest?.size ?? 0)
    const intro = '居民靠模型思考。游戏自带一个小模型，在这台设备上运行，不用密钥也不花钱'
    const wait = el('p', '不用等它下完，接着请村民就行；下完他们就开始行动。', 'guide-note')
    let text = `${intro}。`
    let dot = ''
    let small = ''
    let action = changeButton()
    let meter = false
    let note: HTMLElement | null = wait
    const retry = button('重试', () => void downloadBuiltin())
    switch (shownPhase) {
      case 'ready':
        text = `${intro}；想换成在线的大模型，点「换一个」。`
        small = '已下载 · 在这台设备上运行'
        note = null
        break
      case 'none':
        text = `${intro}。第一次用要下载${s?.latest ? ` ${size}` : ''}，以后不联网也能用；想换成在线的大模型，点「换一个」。`
        dot = 'off'
        small = s?.latest ? `还没下载 · ${size}` : '还没下载'
        note = null
        break
      case 'wifi':
        dot = 'off'
        small = '等连上 Wi-Fi 就开始下载'
        action = button('用流量下载', () => void downloadBuiltinNow())
        break
      case 'running':
        dot = 'busy'
        small = d ? progressText(d) : ''
        meter = true
        break
      case 'verifying':
        dot = 'busy'
        small = '下载好了，正在检查文件…'
        meter = true
        break
      case 'paused':
        dot = 'off'
        small = d ? `已暂停 · 下了 ${percent(d)}%` : '已暂停'
        meter = true
        action = button('继续', () => void downloadBuiltin())
        break
      case 'error-net':
        dot = 'danger'
        small = d
          ? `没下完：网断了。已下的 ${percent(d)}% 留着，连上后自动接着下`
          : '没下完：网断了'
        action = retry
        note = null
        break
      case 'error-space':
        dot = 'danger'
        small = d ? `空间不够：还需要 ${megabytes(d.need)}，只剩 ${megabytes(d.free)}` : '空间不够'
        action = retry
        note = null
        break
      case 'error-file':
        dot = 'danger'
        small = '下载的文件对不上，已经删掉了'
        action = retry
        note = null
        break
    }
    conn.small.textContent = small
    conn.small.className = dot === 'danger' ? 'danger' : ''
    conn.fill.style.setProperty('--v', String(d?.size ? d.done / d.size : 0))
    const box = el('div', '', 'guide-conn')
    const words = el('div')
    words.append(el('b', name), conn.small, ...(meter ? [conn.meter] : []))
    box.append(el('i', '', `guide-conn-dot${dot ? ' ' + dot : ''}`), words, action)
    return [el('h2', '用内置模型就行'), el('p', text), box, ...(note ? [note] : [])]
  }

  // 第二步：连接模型
  function model(): HTMLElement[] {
    if (mock())
      return [
        el('h2', '连接一个模型'),
        el('p', '这个小镇在测试模式：居民用固定回复，不调用模型，这一步可以直接跳过。'),
      ]
    const ready = connectedChoice()
    if (ready && !changing) {
      if (ready.provider === BUILTIN) return builtinStep(`${ready.name} · ${ready.model}`)
      const box = el('div', '', 'guide-conn')
      const words = el('div')
      words.append(
        el('b', `${ready.name} · ${ready.model}`),
        el('small', '已连接 · 密钥只保存在这台设备上')
      )
      box.append(el('i', '', 'guide-conn-dot'), words, changeButton())
      return [
        el('h2', '模型已经连好了'),
        el('p', '居民靠大模型思考。这台设备已经连上下面这个服务，直接用就行。'),
        box,
        el('p', `花了多少随时在${usageAt()}里看。`, 'guide-note'),
      ]
    }
    const grid = el('div', '', 'guide-providers')
    for (const p of PRESETS.filter((x) => SHOWN.includes(x.id))) {
      const b = button('', () => {
        // 回到这一步自己选了服务：不再沿用之前存的那个
        fromSaved = false
        reuse = null
        skipModel = false
        preset = p
        key = ''
        test = savedKey(p.id) ? { state: 'ok', message: '' } : { state: 'idle', message: '' }
        render()
      })
      b.className = 'guide-provider' + (p.id === preset.id ? ' on' : '')
      const name = el('b', p.name)
      if (p.id === 'deepseek') name.append(el('span', '推荐', 'ui-chip ok'))
      b.append(name, el('small', p.defaultModel))
      grid.append(b)
    }
    const input = el('input')
    input.type = 'text'
    input.className = 'guide-key'
    input.autocomplete = 'off'
    input.spellcheck = false
    input.setAttribute('autocapitalize', 'off')
    input.placeholder = savedKey(preset.id)
      ? `已保存 ${savedKey(preset.id)}，留空就用它`
      : keyPlaceholder(preset)
    input.value = key
    input.oninput = () => {
      key = input.value.trim()
      test =
        savedKey(preset.id) && !key ? { state: 'ok', message: '' } : { state: 'idle', message: '' }
      status.replaceChildren(testStatus())
      renderFoot()
    }
    const label = el('label', '', 'guide-field')
    label.append(el('span', `${preset.name} 的密钥`), input)
    const status = el('div', '', 'guide-test')
    status.append(testStatus())
    const alt = el('div', '', 'guide-alt')
    alt.append(
      ...keyHelp(preset),
      el('span', `花了多少随时在${usageAt()}里看。`),
      button(
        '先不连接，看看小镇',
        () => {
          skipModel = true
          go(2)
        },
        'guide-link'
      )
    )
    return [
      el('h2', '连接一个模型'),
      el('p', '居民靠大模型思考。选一个模型服务，填上你在那里申请的密钥。密钥只保存在这台设备上。'),
      grid,
      label,
      status,
      alt,
    ]
  }
  function testStatus() {
    if (test.state === 'testing') return el('span', '正在连接…', 'ui-status busy')
    if (test.state === 'ok')
      return el(
        'span',
        test.message || (savedKey(preset.id) && !key ? '使用已保存的密钥' : '已连通'),
        'ui-status ok'
      )
    if (test.state === 'error') return el('span', test.message, 'ui-status bad')
    return el('span', '')
  }
  async function runTest(advance: boolean) {
    fromSaved = false
    reuse = null
    if (!key) {
      test = { state: 'error', message: '先填上密钥' }
      render()
      return
    }
    test = { state: 'testing', message: '' }
    render()
    const request_id = newId()
    const config = { id: preset.id, name: preset.name, base_url: preset.baseUrl }
    d.send({
      type: 'test_model_connection',
      request_id,
      provider: config,
      model: preset.defaultModel,
      api_key: key,
    })
    try {
      const result = await waitFor(
        (m) => (m.type === 'model_test_result' && m.request_id === request_id ? m : undefined),
        true,
        40000
      )
      if (!result.ok) throw Error(result.message || '连接失败')
      // 连通了就存下来：服务商、密钥，并设为小镇的工具模型
      await saved(
        providerSaveCommand({ provider: preset.id, model: preset.defaultModel }, providers, [
          { provider: config, key },
        ])
      )
      test = { state: 'ok', message: `已连通 · ${result.latency_ms} 毫秒` }
      if (advance && step === 1) step = 2
    } catch (error) {
      test = { state: 'error', message: error instanceof Error ? error.message : String(error) }
    }
    if (root.hidden) return
    render()
  }

  // 第三步：请居民
  function residents(): HTMLElement[] {
    const free = templates.filter((t) => t.status === 'available' && !t.archived)
    // 一处住宅住一个人：空房比默认人数少时只请得下这么多
    const room = roomLeft(population)
    const limit = Math.min(MAX_PICKS, room)
    // 按小镇写的人要用模型写人设：没连模型时先不能选
    const canWrite = !skipModel
    if (!picked && !population?.residents.length && (d.suggestions.length || free.length)) {
      picked = true
      // 建镇时按描述写了几位（描述里说了几个人就有几位）就默认请几位
      if (canWrite && d.suggestions.length) wishes = d.suggestions.map((_, i) => i).slice(0, limit)
      else {
        picks = PICKS.filter((id) => free.some((t) => t.template_id === id))
        for (const t of free)
          if (picks.length < 3 && !picks.includes(t.template_id)) picks.push(t.template_id)
      }
    }
    if (!canWrite) wishes = []
    while (wishes.length + picks.length > limit) {
      if (picks.length) picks.pop()
      else wishes.pop()
    }
    const full = () => wishes.length + picks.length >= limit
    const wishGrid = el('div', '', 'guide-wishes')
    d.suggestions.forEach((line, i) => {
      const b = button('', () => {
        const at = wishes.indexOf(i)
        if (at >= 0) wishes.splice(at, 1)
        else if (!full()) wishes.push(i)
        render()
      })
      b.className = 'guide-wish' + (wishes.includes(i) ? ' on' : '')
      b.disabled = !canWrite
      b.append(el('span', line))
      wishGrid.append(b)
    })
    const grid = el('div', '', 'guide-residents')
    for (const t of free) {
      const b = button('', () => {
        const i = picks.indexOf(t.template_id)
        if (i >= 0) picks.splice(i, 1)
        else if (!full()) picks.push(t.template_id)
        render()
      })
      b.className = 'guide-resident' + (picks.includes(t.template_id) ? ' on' : '')
      const url = portraitFor(templateKey(t))
      if (url) {
        const img = el('img')
        img.src = url
        img.alt = ''
        b.append(img)
      }
      b.append(el('b', t.name), el('small', t.tags.slice(0, 2).join(' · ')))
      grid.append(b)
    }
    const using = skipModel
      ? '还没有连接模型：他们会先住下，连接后才开始行动。'
      : mock()
        ? '测试模式：他们用固定回复行动。'
        : reuse
          ? `都用 ${reuse.name} · ${reuse.model}，以后可以给每个人单独换。`
          : `都用 ${preset.name} · ${preset.defaultModel}，以后可以给每个人单独换。`
    // 还是默认的那几位时说明为什么推荐他们
    const chosen = picks.map((id) => free.find((t) => t.template_id === id))
    const defaults =
      picks.length === PICKS.length &&
      picks.every((id) => PICKS.includes(id)) &&
      chosen.every(Boolean)
    const why =
      room === 0
        ? '住宅都住满了：一处住宅住一个人，这次不能再请人。'
        : room < MAX_PICKS
          ? `这个小镇有 ${room} 处空住宅，一处住一个人，最多请${peopleCount(room)}。每多一位就多一份模型调用。`
          : wishes.length
            ? '先请建镇时为这个小镇写的几位：点「开始」后用模型把他们的人设写好再请进来，每位多一次调用。'
            : defaults
              ? `默认请了${chosen.map((t) => t!.name).join('、')}：${recommendReason(chosen as TemplateCard[])}每多一位就多一份模型调用。`
              : `每多一位就多一份模型调用，最多 ${MAX_PICKS} 位。`
    // 为什么是这几位、用哪个模型写在名单上面：库里人多，写在下面要翻到底才看得到
    const wishPart = d.suggestions.length
      ? [
          el('h3', '按小镇写的人', 'guide-sub'),
          ...(canWrite
            ? []
            : [el('p', '连上模型后，才能按建镇时的描述写出这几位。', 'guide-note')]),
          wishGrid,
          el('h3', '村民库里的人', 'guide-sub'),
        ]
      : []
    return [
      el('h2', '请几位居民住进来'),
      el('p', why),
      el('p', using, 'guide-note guide-using'),
      ...wishPart,
      free.length ? grid : el('p', '正在读取村民库…', 'dim'),
      el(
        'p',
        `以后可以随时点${phone() ? '「居民」' : '地图左上角的「邀请」'}新建自己的村民，或从村民库再请几位。`,
        'guide-note'
      ),
    ]
  }

  // 第四步：世界观，然后开始
  const progress = el('ol', '', 'guide-progress')
  function world(): HTMLElement[] {
    if (!lore) lore = d.worldSettings.state()?.worldview || d.worldSettings.defaultWorldview
    const text = el('textarea')
    text.rows = 5
    text.maxLength = 6000
    text.value = lore
    text.setAttribute('aria-label', '世界观')
    text.oninput = () => (lore = text.value)
    const chips = el('div', '', 'guide-chips')
    // 一句话建的小镇：建镇时的描述排第一个
    const suggested = d.worldSettings.suggestedWorldview
    const lores: [string, string][] = suggested
      ? [
          ['建镇时的描述', suggested],
          ...LORES.map(([l, v]): [string, string] => [l, v || DEFAULT_WORLDVIEW]),
        ]
      : LORES
    for (const [label, value] of lores) {
      const full = value || d.worldSettings.defaultWorldview
      const b = button(label, () => {
        lore = full
        text.value = full
        render()
      })
      b.className = 'guide-chip' + (lore === full ? ' on' : '')
      chips.append(b)
    }
    return [
      el('h2', '这是个什么样的小镇？'),
      el('p', `写给居民看的背景，他们会照着生活。可以先用默认的，以后${townEntryHint()}改。`),
      chips,
      text,
      ...(skipModel
        ? [
            el(
              'p',
              '还没连接模型：村民先住下，时间也先停着，可以先用化身逛逛。连上模型后他们就会开始行动。',
              'guide-note'
            ),
          ]
        : []),
      progress,
    ]
  }

  async function start() {
    if (running) return
    running = true
    render()
    type Step = { key: string; label: string; run: (item: HTMLElement) => Promise<unknown> }
    const steps: Step[] = []
    const state = d.worldSettings.state()
    const text = lore.trim() || d.worldSettings.defaultWorldview
    if (!state?.ready || state.worldview !== text)
      steps.push({
        key: 'worldview',
        label: '保存世界观',
        run: () =>
          new Promise((resolve, reject) =>
            d.worldSettings.saveWorldview(text, (ok, message) =>
              ok ? resolve(message) : reject(Error(message))
            )
          ),
      })
    const choice = residentModel()
    // 开始前已经住着的人（上次没连模型就请进来的）：这次连上了，一并用上
    const existing = population?.residents.map((r) => r.id) ?? []
    const joined: string[] = []
    const thinking = choice ? `，用 ${providerName(choice.provider)} 思考` : ''
    for (const i of wishes) {
      const line = d.suggestions[i]
      steps.push({
        key: `wish:${i}`,
        label: `按「${line}」写一位新居民`,
        run: async (item) => {
          const t = written.get(i) ?? (await writeResident(line))
          written.set(i, t)
          item.firstChild!.textContent = `请${t.fields.name}住进来${thinking}`
          joined.push(await join(t.template_id, choice))
        },
      })
    }
    for (const id of picks) {
      const t = templates.find((x) => x.template_id === id)
      if (!t) continue
      steps.push({
        key: `pick:${id}`,
        label: `请${t.name}住进来${thinking}`,
        run: async () => joined.push(await join(t.template_id, choice)),
      })
    }
    if (choice && existing.length)
      steps.push({
        key: 'existing-model',
        label: '已住的居民也用这个模型',
        run: async () => {
          for (const id of existing) {
            d.send({ type: 'get_agent_config', resident: id })
            const config = await waitFor((m) =>
              m.type === 'agent_config' && m.resident_id === id ? m : undefined
            )
            // 单独选过模型的不动
            if (!config.model_binding)
              await saved({ type: 'set_resident_model', resident: id, model: choice })
          }
        },
      })
    // 没连模型也让世界跑起来：村民先等模型、时间停着，化身照样能走
    steps.push({
      key: 'run',
      label: '让世界跑起来',
      run: async () => {
        if (!d.speeds.current()) d.speeds.choose(d.normalSpeed)
      },
    })
    progress.replaceChildren(...steps.map((s) => el('li', s.label)))
    for (const [i, s] of steps.entries()) {
      const item = progress.children[i] as HTMLElement
      if (done.has(s.key)) {
        item.className = 'done'
        continue
      }
      item.className = 'doing'
      try {
        await s.run(item)
        done.add(s.key)
        item.className = 'done'
      } catch (error) {
        item.className = 'failed'
        item.append(el('small', error instanceof Error ? error.message : String(error)))
        running = false
        renderFoot()
        skip.hidden = false
        return
      }
    }
    running = false
    finish(true, joined)
  }

  /** 给新居民用的模型：刚连通的服务；测试模式下用已有的第一个服务 */
  function residentModel(): { provider: string; model: string } | null {
    if (skipModel) return null
    if (mock()) {
      const p = providers[0]
      const known = p && PRESETS.find((x) => x.id === p.id)
      return p ? { provider: p.id, model: known?.defaultModel ?? 'deepseek-chat' } : null
    }
    if (reuse) return { provider: reuse.provider, model: reuse.model }
    if (test.state !== 'ok') return null
    return { provider: preset.id, model: preset.defaultModel }
  }

  /** 没经过选模型时挑一个能用的，和第二步的判断一样：设定里的默认模型优先，其次第一个能用的服务
   *  （存了密钥的在前，内置模型排最后）；都没有就先不连接 */
  function pickSaved() {
    if (!fromSaved) return
    reuse = connectedChoice()
    skipModel = !reuse && !mock()
  }

  /** 按一句话用模型写出一位居民并存进村民库（所有小镇共用），返回存好的模板 */
  async function writeResident(line: string): Promise<ResidentTemplate> {
    const request_id = newId()
    d.send({ type: 'generate_resident_template', request_id, brief: line })
    const written = await waitFor(
      (m) => (m.type === 'template_generated' && m.request_id === request_id ? m : undefined),
      true,
      120000
    )
    if (!written.ok || !written.fields) throw Error(written.message || '没能写出这位居民')
    const save_id = newId()
    d.send({ type: 'save_resident_template', request_id: save_id, fields: written.fields })
    const kept = await waitFor((m) =>
      m.type === 'template_saved' && m.request_id === save_id ? m : undefined
    )
    if (!kept.ok || !kept.template) throw Error(kept.message || '没能存进村民库')
    return kept.template
  }

  async function join(
    template_id: string,
    model: { provider: string; model: string } | null
  ): Promise<string> {
    if (!population) {
      d.send({ type: 'get_population' })
      await waitFor((m) => (m.type === 'population' ? m : undefined))
    }
    d.send({ type: 'preview_resident_join', template_id })
    const preview: JoinPreview = await waitFor(
      (m) =>
        m.type === 'join_preview' && m.preview.template_id === template_id ? m.preview : undefined,
      true
    )
    if (!preview.ok) throw Error(preview.problems.join('；') || '现在不能加入')
    const op_id = newId()
    d.send({
      type: 'join_resident',
      op_id,
      world_id: population!.world_id,
      template_id,
      template_version: preview.template_version,
      name: preview.name,
      home: preview.home,
      ...(model ? { model } : {}),
    })
    const outcome: JoinOutcome = await waitFor((m) =>
      m.type === 'resident_joined' && m.outcome.op_id === op_id
        ? m.outcome
        : m.type === 'join_result' && m.op_id === op_id
          ? m.outcome
          : undefined
    )
    if (!outcome.ok || !outcome.resident_id) throw Error(outcome.message)
    return outcome.resident_id
  }

  function finish(started: boolean, joined: string[] = []) {
    markDone()
    root.hidden = true
    // 跳过时世界观还没设：交回首次对话框
    d.worldSettings.setFirstRun(null)
    d.onFinish(started, joined)
  }

  /** fromStep：走过一遍向导的玩家建新小镇时，从「请居民」开始，玩法和模型不再重复 */
  function open(fromStep = 0) {
    step = fromStep
    fromSaved = fromStep >= 2
    reuse = null
    running = false
    test = savedKey(preset.id) ? { state: 'ok', message: '' } : { state: 'idle', message: '' }
    skipModel = false
    changing = false
    picks = []
    wishes = []
    done.clear()
    written.clear()
    picked = false
    lore = ''
    progress.replaceChildren()
    root.hidden = false
    d.send({ type: 'get_model_config' })
    d.send({ type: 'get_population' })
    d.send({ type: 'get_resident_library', filter: { kind: 'builtin' } })
    render()
  }

  const panel: ShellPanel = {
    handleMsg(m: ServerMsg) {
      if (m.type === 'model_config') {
        providers = m.providers
        activeChoice = m.active
        pickSaved()
        if (!root.hidden && step === 2) render()
      }
      if (m.type === 'population') {
        population = m.population
        if (!root.hidden && step === 2) render()
      }
      if (m.type === 'resident_library') {
        templates = m.templates
        if (!root.hidden && step === 2) render()
      }
      for (const w of [...waiters]) {
        const value = w.match(m)
        if (value === undefined) continue
        waiters.splice(waiters.indexOf(w), 1)
        w.resolve(value)
        if (w.consume) return true
      }
      return false
    },
  }

  return {
    panel,
    open,
    isOpen: () => !root.hidden,
    /** 返回键：在向导里就退一步，第一步时跳过 */
    back() {
      if (root.hidden) return false
      if (running) return true
      if (step > 0) go(step - 1)
      else finish(false)
      return true
    },
  }
}
