// 等模型：村民还没有能用的模型时不算出错，也不暂停全镇。时钟牌下写「等你连接模型」，世界在跑时
// 地图上方一条平静的提示，按钮直接打开连接弹层；连上了但有人没选模型时「都用 X」一键选好。
// 用内置模型的村民在等它下载：提示条写下载进度，没开始下就给「下载」，出错了给「重试」。
// 谁都还不能思考时服务端让时间停着，化身照样能走。点「开始」时没连模型或有人没选模型，就地问一句。
import { button, el } from './dom'
import { namesOf } from './holds'
import {
  builtinReady,
  builtinStatus,
  builtinWaitingWifi,
  downloadBuiltin,
  downloadBuiltinNow,
  megabytes,
  onBuiltin,
  bytesText,
  percent,
  refreshBuiltinSoon,
} from './models/builtin'
import { BUILTIN } from './providers'
import type { ModelOption, createModelSession } from './models/session'
import type { ModelChoice, PopulationView, RosterMember } from './protocol'
import type { ShellPanel } from './shell/panel'

type Models = ReturnType<typeof createModelSession>
/** 提示条上写什么、按钮做什么；meter 是下载进度（0–1） */
type Plan = {
  head: string
  body: string
  flag: string
  label: string
  run: () => void
  meter?: number
}

/** 右栏第一行：谁在等、为什么、一个能马上处理的按钮 */
export interface WaitLine {
  text: string
  label: string
  run: () => void
}

export function installModelWait(
  map: HTMLElement,
  deps: {
    models: Models
    /** 测试模式：村民用固定回复，不需要模型 */
    mock: () => boolean
  }
) {
  const { models } = deps
  const banner = el('div', '', 'model-wait')
  banner.hidden = true
  banner.setAttribute('role', 'status')
  const title = el('b')
  const text = el('span')
  const words = el('div', '', 'model-wait-words')
  const meter = el('div', '', 'ui-meter model-wait-meter')
  const fill = el('span')
  meter.append(fill)
  words.append(title, text, meter)
  const action = button('', () => act?.(), 'primary')
  banner.append(el('i', '', 'model-wait-dot'), words, action)
  // 提示条上的按下不能漏给地图，否则会被当成拖动的起点
  for (const type of ['pointerdown', 'dblclick', 'wheel'])
    banner.addEventListener(type, (e) => e.stopPropagation())
  map.append(banner)
  const flag = button('', () => act?.(), 'model-flag')
  flag.id = 'model-flag'
  flag.hidden = true
  document.getElementById('hold-flag')?.after(flag)

  let population: PopulationView | null = null
  let waiting: RosterMember[] = []
  let running = false
  let act: (() => void) | null = null

  const modelOf = (id: string) => population?.residents.find((r) => r.id === id)?.model
  function connect(provider?: string) {
    void models.connect({
      title: '连接一个模型',
      text: '居民靠大模型思考。连上以后，他们马上开始行动。',
      dismiss: '先不连接',
      confirm: '测试并保存',
      provider,
    })
  }
  /** 用内置模型的村民在等它下载：写进度，没开始下就给「下载」，出错了给「重试」；没有可点的时候 label 为空 */
  function builtinPlan(names: string[]): Plan {
    const s = builtinStatus()
    const d = s?.download
    const who = namesOf(names)
    const retry = () => void downloadBuiltin()
    // 村民还在等，页面却记着已经下好：多半是别处删了模型，再问一次
    if (builtinReady()) {
      refreshBuiltinSoon()
      return {
        head: '内置模型准备好了',
        body: `${who}马上开始行动。`,
        flag: '内置模型准备好了',
        label: '',
        run: () => {},
      }
    }
    if (builtinWaitingWifi())
      return {
        head: '内置模型等连上 Wi-Fi 再下载',
        body: `${who}用的是内置模型，下完就开始行动。`,
        flag: '等内置模型下载',
        label: '用流量下载',
        run: () => void downloadBuiltinNow(),
      }
    switch (d?.state) {
      case 'running':
        return {
          head: `内置模型下载中 ${percent(d)}%`,
          body: `${bytesText(d)}。下完${who}就开始行动。`,
          flag: `内置模型下载中 ${percent(d)}%`,
          label: '',
          run: () => {},
          meter: d.size ? d.done / d.size : 0,
        }
      case 'verifying':
        return {
          head: '内置模型下好了',
          body: '正在检查文件…',
          flag: '内置模型检查文件',
          label: '',
          run: () => {},
          meter: 1,
        }
      case 'paused':
        return {
          head: '内置模型下载暂停了',
          body: `下了 ${percent(d)}%，${who}在等它。`,
          flag: '内置模型下载暂停了',
          label: '继续',
          run: retry,
          meter: d.size ? d.done / d.size : 0,
        }
      case 'error-net':
        return {
          head: '内置模型没下完：网断了',
          body: '连上网后自动接着下。',
          flag: '内置模型没下完',
          label: '重试',
          run: retry,
        }
      case 'error-space':
        return {
          head: '空间不够，内置模型没法下载',
          body: `还需要 ${megabytes(d.need)}，这台设备只剩 ${megabytes(d.free)}。`,
          flag: '空间不够',
          label: '重试',
          run: retry,
        }
      case 'error-file':
        return {
          head: '内置模型没下好',
          body: '下载的文件对不上，已经删掉了。',
          flag: '内置模型没下好',
          label: '重试',
          run: retry,
        }
    }
    const size = s?.latest ? ` ${megabytes(s.latest.size)} ` : ''
    return {
      head: '内置模型还没下载',
      body: `${who}用的是内置模型，下载${size}后就开始行动。`,
      flag: '等内置模型下载',
      label: '下载',
      run: retry,
    }
  }

  /** 现在该怎么办：没连模型就连；连上了但有人没选就一键选好；选了的服务还没连上就去连它 */
  function plan(): Plan {
    const names = waiting.map((m) => m.name)
    const option = models.options()[0]
    if (!option)
      return {
        head: '村民还不会思考',
        body: '连上模型后他们就会开始行动，时间也从那时开始走。现在可以先用化身四处逛逛。',
        flag: '等你连接模型',
        label: '连接模型',
        run: () => connect(),
      }
    const unbound = waiting.filter((m) => !modelOf(m.id))
    if (unbound.length)
      return {
        head: `${namesOf(unbound.map((m) => m.name))}还没选模型`,
        body: '选好后就会开始行动。',
        flag: `${unbound.length} 位村民还没选模型`,
        label: `都用 ${option.name}`,
        run: () => void models.bindUnbound(option),
      }
    const provider = modelOf(waiting[0].id)?.provider
    if (provider === BUILTIN && builtinStatus()?.supported)
      return builtinPlan(
        waiting.filter((m) => modelOf(m.id)?.provider === BUILTIN).map((m) => m.name)
      )
    const name = provider ? models.providerName(provider) : '模型服务'
    return {
      head: `${name} 还没连上`,
      body: `${namesOf(names)}用的是 ${name}，填好密钥后就会开始行动。`,
      flag: `等 ${name} 连上`,
      label: '连接模型',
      run: () => connect(provider),
    }
  }
  function render() {
    if (!waiting.length || deps.mock()) {
      banner.hidden = flag.hidden = true
      act = null
      return
    }
    const p = plan()
    act = p.run
    title.textContent = p.head
    text.textContent = p.body
    action.textContent = p.label
    action.hidden = !p.label
    meter.hidden = p.meter === undefined
    fill.style.setProperty('--v', String(p.meter ?? 0))
    flag.textContent = p.flag
    flag.title = `${p.head}：${p.body}`
    flag.hidden = false
    // 世界停着时地图上方是「点开始」的提示，点开始时再问
    banner.hidden = !running
  }
  models.subscribe(render)
  onBuiltin(render)

  // 点「开始」前的询问：这一局里选过「先开始」就不再问
  let startWithout = false
  let startUnbound = false
  let ask: HTMLElement | null = null
  function closeAsk() {
    ask?.remove()
    ask = null
  }
  function askUnbound(go: () => void, option: ModelOption, unbound: string[]) {
    closeAsk()
    const box = el('div', '', 'start-ask')
    box.setAttribute('role', 'dialog')
    const names = namesOf(unbound)
    const all = unbound.length === (population?.residents.length ?? 0)
    const other = population?.residents.map((r) => r.model).find((m): m is ModelChoice => !!m)
    const used = other ?? option
    const actions = el('div', '', 'start-ask-actions')
    actions.append(
      button(
        `都用 ${models.providerName(used.provider)} 并开始`,
        () => {
          closeAsk()
          void models.bindUnbound(used).finally(go)
        },
        'primary'
      ),
      button('先开始', () => {
        closeAsk()
        startUnbound = true
        go()
      })
    )
    box.append(
      el('b', all ? '村民都还没选模型' : `${names}还没有选模型`),
      el(
        'span',
        all
          ? '选好模型他们才会开始行动。'
          : `其他人用的是 ${models.providerName(used.provider)} · ${used.model}。不选的话，开始后${names}会原地等着。`
      ),
      actions
    )
    const anchor = document.getElementById('speeds')?.getBoundingClientRect()
    if (anchor) {
      box.style.left = `${Math.max(12, Math.min(innerWidth - 332, anchor.left - 12))}px`
      box.style.top = `${anchor.bottom + 8}px`
    }
    document.body.append(box)
    ask = box
    // 点别处或按 Esc 收起
    setTimeout(() => {
      const away = (e: Event) => {
        if (ask && e.target instanceof Node && ask.contains(e.target)) return
        if (e instanceof KeyboardEvent && e.key !== 'Escape') return
        closeAsk()
        document.removeEventListener('pointerdown', away, true)
        document.removeEventListener('keydown', away, true)
      }
      document.addEventListener('pointerdown', away, true)
      document.addEventListener('keydown', away, true)
    })
  }

  const panel: ShellPanel = {
    roster({ msg, residents }) {
      running = msg.speed > 0
      waiting = residents.map((r) => r.member).filter((m) => m.resident_agent?.state === 'no_model')
      render()
    },
    onReset: closeAsk,
    dispose: closeAsk,
  }

  return {
    panel,
    setPopulation(view: PopulationView) {
      population = view
      render()
    },
    /** 打开连接弹层；provider 是先选中的服务 */
    connect,
    /** 这位村民用的模型；没选时为 undefined */
    modelOf,
    /** 换服务：原来用 from 的村民都改用 to */
    async moveResidents(from: string, to: ModelChoice) {
      const ids = population?.residents.filter((r) => r.model?.provider === from) ?? []
      await Promise.all(ids.map((r) => models.bindResident(r.id, to)))
    },
    /** 右栏第一行；不在等模型时为 null */
    line(m: RosterMember): WaitLine | null {
      if (m.resident_agent?.state !== 'no_model' || deps.mock()) return null
      const option = models.options()[0]
      const model = modelOf(m.id)
      if (!option)
        return {
          text: `${m.name}在等你连接模型，连上后就会开始行动。`,
          label: '连接模型',
          run: () => connect(),
        }
      if (!model)
        return {
          text: `${m.name}还没选模型，选好后就会开始行动。`,
          label: `用 ${option.name}`,
          run: () => void models.bindResident(m.id, option),
        }
      if (model.provider === BUILTIN && builtinStatus()?.supported) {
        const p = builtinPlan([m.name])
        return { text: `${p.head}。${p.body}`, label: p.label, run: p.run }
      }
      const name = models.providerName(model.provider)
      return {
        text: `${m.name}用的 ${name} 还没连上，填好密钥后就会开始行动。`,
        label: '连接模型',
        run: () => connect(model.provider),
      }
    },
    /** 点「开始」前：接手了返回 true，由这里决定之后要不要开始 */
    gate(go: () => void): boolean {
      if (deps.mock()) return false
      if (models.connected() === false) {
        if (startWithout) return false
        void models
          .connect({
            title: '开始前先连接一个模型',
            text: '居民靠大模型思考。不连接也能先进去，用化身逛逛；村民会原地等着，时间也先停着。',
            dismiss: '先不连接',
            confirm: '测试并开始',
          })
          .then((result) => {
            if (result === 'skipped') startWithout = true
            if (result !== 'cancelled') go()
          })
        return true
      }
      const option = models.options()[0]
      const unbound = population?.residents.filter((r) => !r.model).map((r) => r.name) ?? []
      if (!option || !unbound.length || startUnbound) return false
      askUnbound(go, option, unbound)
      return true
    },
  }
}
export type ModelWait = ReturnType<typeof installModelWait>
