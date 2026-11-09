// 首页的「设定」：内置模型、模型服务、建镇用的模型、声音、显示——这些不属于哪个小镇，所有小镇共用；
// 世界观、村民、额度跟着小镇走，进小镇后在设定里改。模型服务经管理服务的 /api/towns/models 读写，
// 内置模型的下载与更新见 town-shared/models/builtin.ts。
// 还没有能用的模型时，标题下面一张「还差一步」的提示卡：应用带着内置模型就请玩家下载它（下载时卡片换成进度），
// 也可以连在线服务；点「以后再说」缩成一行小字，「设定」上留个小绿点。内置模型有新版本、又关了自动更新时，
// 「设定」上也亮小绿点。
import { effectsPreference } from 'town-shared/audio/effects'
import { storyMusicPreference } from 'town-shared/audio/controller'
import { button, el, query } from 'town-shared/dom'
import { errorText } from 'town-shared/format'
import { gameIcon } from 'town-shared/game/icons'
import {
  connectModel,
  hasModel,
  QUICK,
  usableProvider,
  type ModelConfig,
  type ModelTransport,
} from 'town-shared/models/connect'
import {
  autoUpdateBuiltin,
  builtinNeedsAttention,
  builtinReady,
  builtinStatus,
  builtinWaitingWifi,
  downloadBuiltin,
  downloadBuiltinNow,
  megabytes,
  onBuiltin,
  onBuiltinInstalled,
  pauseBuiltin,
  percent,
  progressText,
} from 'town-shared/models/builtin'
import { createBuiltinRows } from 'town-shared/models/builtinRows'
import { onBack } from 'town-shared/platform'
import { BUILTIN, PRESETS, quickModelNames } from 'town-shared/providers'
import type { ModelChoice } from 'town-shared/protocol'
import { settingRow } from 'town-shared/settings/controls'
import { createDisplayPage } from 'town-shared/settings/display'
import { createSoundPage } from 'town-shared/settings/sound'
import { api } from './api'
import './settings.css'

const LATER_KEY = 'town:model-prompt-later'

function later() {
  try {
    return localStorage.getItem(LATER_KEY) === '1'
  } catch {
    return false
  }
}

function remember() {
  try {
    localStorage.setItem(LATER_KEY, '1')
  } catch {
    // 存不了就只在这次打开里收起
  }
}

/** 首页经管理服务读写模型配置 */
function homeTransport(): ModelTransport & { load(): Promise<ModelConfig> } {
  let config: ModelConfig | null = null
  return {
    config: () => config,
    async load() {
      config = await api<ModelConfig>('/models')
      return config
    },
    test: (provider, model, key) =>
      api('/models/test', { provider, model, ...(key ? { api_key: key } : {}) }),
    async save(command) {
      config = await api<ModelConfig>('/models', command)
    },
  }
}

export function installHomeSettings(deps: { music: { enabled(): boolean; toggle(): void } }) {
  const transport = homeTransport()
  const entry = button('', () => open(), 'launcher-settings')
  entry.append(gameIcon('settings', true), el('span', '设定'))
  query(document, '.launcher-brand').append(entry)
  const connect = (provider?: string) =>
    connectModel(transport, {
      title: '连接模型服务',
      text: '选一个服务，填上你在那里申请的密钥，测试连通后就保存。',
      dismiss: '取消',
      confirm: '测试并保存',
      provider,
    }).then((result) => {
      if (result === 'connected') refresh()
      return result
    })

  // ---------- 提示卡与收起后的一行字 ----------
  const prompt = el('div', '', 'model-prompt')
  const badge = el('span', '', 'mp-badge')
  badge.append(gameIcon('spark', true))
  const promptTitle = el('b')
  const promptText = el('span', '', 'mp-text')
  const promptMeter = el('div', '', 'ui-meter mp-meter')
  const promptFill = el('span')
  promptMeter.append(promptFill)
  const promptSub = el('span', '', 'mp-sub')
  const actions = el('div', '', 'mp-actions')
  prompt.append(badge, promptTitle, promptText, promptMeter, promptSub, actions)
  const laterButton = button(
    '以后再说',
    () => {
      remember()
      render()
    },
    'mp-later'
  )
  const line = button(
    '',
    () => (builtinStatus()?.supported ? open() : void connect()),
    'model-line'
  )
  const lineText = el('span')
  const go = el('b')
  line.append(el('i'), lineText, go)
  /** 内置模型刚下好：提示卡收起，留一句话 */
  const ready = el('div', '', 'model-line ok')
  ready.append(el('i'), el('span', '内置模型下好了，进小镇请村民吧'))
  prompt.hidden = line.hidden = ready.hidden = true
  query(document, '.launcher-heading').after(prompt, line, ready)
  let readyTimer = 0
  onBuiltinInstalled((first) => {
    if (!first) return
    ready.hidden = false
    clearTimeout(readyTimer)
    readyTimer = window.setTimeout(() => (ready.hidden = true), 8000)
  })

  // ---------- 设定页 ----------
  const dialog = el('dialog', '', 'home-settings')
  dialog.setAttribute('aria-labelledby', 'home-settings-title')
  const head = el('header', '', 'hs-head')
  const back = button('', () => dialog.close(), 'hs-back')
  back.append(gameIcon('back', true))
  back.setAttribute('aria-label', '返回')
  const title = el('h1', '设定')
  title.id = 'home-settings-title'
  head.append(back, title)
  // 内置模型：应用带着推理程序才有这一节
  const builtin = el('section', '', 'spage')
  builtin.hidden = true
  builtin.append(
    el('h2', '内置模型'),
    el(
      'p',
      '游戏自带的小模型，在这台设备上运行，不用密钥也不花钱。只给村民过日子用，一句话建镇要用在线服务。',
      'hint'
    ),
    createBuiltinRows().el
  )
  const models = el('section', '', 'spage')
  const modelRows = el('div', '', 'set-rows')
  const status = el('p', '', 'page-status')
  status.setAttribute('role', 'status')
  models.append(
    el('h2', '模型服务'),
    el('p', '村民靠它思考。密钥只保存在这台设备上，所有小镇共用。', 'hint'),
    modelRows,
    el('p', 'Ollama、自定义地址等服务，进入小镇后在「设定 · 模型服务」里配置。', 'hs-note'),
    status
  )
  const toolRows = el('div', '', 'set-rows')
  const tool = el('section', '', 'spage')
  tool.append(el('h2', '建镇用的模型'), toolRows)
  const sound = createSoundPage(false, {
    music: deps.music,
    story: storyMusicPreference,
    effects: effectsPreference,
  })
  const display = createDisplayPage(undefined, false)
  const body = el('div', '', 'hs-body')
  body.append(
    builtin,
    models,
    tool,
    sound.el,
    display.el,
    el('p', '世界观、村民、调用额度跟着小镇走，进入小镇后点「设定」修改。', 'hs-note')
  )
  dialog.append(head, body)
  document.body.append(dialog)
  let offBack = () => {}
  dialog.addEventListener('close', () => offBack())

  function open() {
    sound.onShow?.()
    display.onShow?.()
    renderSettings()
    dialog.showModal()
    body.scrollTop = 0
    offBack = onBack(() => {
      if (!dialog.open) return false
      dialog.close()
      return true
    })
  }

  function renderSettings() {
    const config = transport.config()
    const presets = QUICK.map((id) => PRESETS.find((p) => p.id === id)!)
    modelRows.replaceChildren(
      ...presets.map((p) => {
        const conf = config?.providers.find((c) => c.id === p.id)
        const row = settingRow(
          p.name,
          conf?.key_mask ? `已连接 · 密钥 ${conf.key_mask}` : p.defaultModel,
          button(conf?.key_mask ? '更换密钥' : '连接', () => void connect(p.id))
        )
        if (p.id === 'deepseek') row.querySelector('.set-row-label')?.append(chip('推荐'))
        if (conf?.key_mask) row.classList.add('connected')
        return row
      })
    )
    // 建镇用的模型：连上的服务里选一个；一个都没有时，连上第一个会自动用它
    // 内置模型只给村民过日子用，不会建镇
    const usable = (config?.providers ?? []).filter(
      (p) => p.id !== BUILTIN && hasModel({ active: null, providers: [p] })
    )
    if (!usable.length) {
      toolRows.replaceChildren(
        settingRow('一句话建镇时理解你的描述', '连上一个模型服务后自动用它', el('span'))
      )
      return
    }
    const choose = el('select')
    choose.setAttribute('aria-label', '建镇用的模型')
    const choices: ModelChoice[] = []
    for (const p of usable) {
      const current = config?.active?.provider === p.id ? config.active.model : undefined
      for (const model of quickModelNames(p.id, current)) {
        const selected = config?.active?.provider === p.id && config.active.model === model
        choose.append(new Option(`${p.name} · ${model}`, String(choices.length), false, selected))
        choices.push({ provider: p.id, model })
      }
    }
    choose.onchange = () => {
      const choice = choices[Number(choose.value)]
      if (choice) void saveTool(choice)
    }
    toolRows.replaceChildren(settingRow('一句话建镇时理解你的描述', '只在建镇时调用一次', choose))
  }

  async function saveTool(choice: ModelChoice) {
    const config = transport.config()
    if (!config) return
    status.textContent = '保存中…'
    try {
      await transport.save({
        active: choice,
        providers: config.providers.map(({ id, name, base_url }) => ({ id, name, base_url })),
        keys: [],
      })
      status.textContent = '已保存'
    } catch (error) {
      status.textContent = errorText(error)
    }
    renderSettings()
  }

  /** 提示卡里写什么。应用带着内置模型时请玩家下载它，下载时换成进度；idle 表示还没开始，可以收起 */
  function promptCopy(): {
    title: string
    text: string
    actions: HTMLElement[]
    meter?: number
    sub?: string
    idle: boolean
  } {
    const action = (label: string, run: () => void) => button(label, run, 'mp-go')
    const s = builtinStatus()
    if (!s?.supported)
      return {
        title: '还差一步：连接一个模型',
        text: '连上以后，村民会自己思考、过日子。大约 1 分钟，密钥只保存在这台设备上。',
        actions: [action('连接模型', () => void connect()), laterButton],
        idle: true,
      }
    const d = s.download
    const size = megabytes(d?.size ?? s.latest?.size ?? 0)
    const retry = [action('重试', () => void downloadBuiltin())]
    if (builtinWaitingWifi())
      return {
        title: '等连上 Wi-Fi 再下载内置模型',
        text: `${size}。连上 Wi-Fi 就自动开始。`,
        actions: [action('用流量下载', () => void downloadBuiltinNow())],
        idle: false,
      }
    if (d) {
      const meter = d.size ? d.done / d.size : 0
      switch (d.state) {
        case 'running':
          return {
            title: '正在下载内置模型',
            text: progressText(d),
            meter,
            sub: '可以先进小镇请村民，下完他们就开始行动。',
            actions: [action('暂停', () => void pauseBuiltin())],
            idle: false,
          }
        case 'verifying':
          return {
            title: '内置模型下好了',
            text: '正在检查文件…',
            meter: 1,
            actions: [],
            idle: false,
          }
        case 'paused':
          return {
            title: '内置模型下载暂停了',
            text: `下了 ${percent(d)}%（${Math.round(d.done / 1e6)} / ${size}）`,
            meter,
            actions: [action('继续', () => void downloadBuiltin())],
            idle: false,
          }
        case 'error-net':
          return {
            title: '内置模型没下完',
            text: `连不上下载服务器。已下的 ${percent(d)}% 会留着，连上网后自动接着下。`,
            actions: retry,
            idle: false,
          }
        case 'error-space':
          return {
            title: '空间不够，内置模型没开始下',
            text: `还需要 ${megabytes(d.need)}，这台设备只剩 ${megabytes(d.free)}。清出空间后点重试。`,
            actions: retry,
            idle: false,
          }
        case 'error-file':
          return {
            title: '内置模型没下好',
            text: '下载的文件对不上，已经删掉了。',
            actions: retry,
            idle: false,
          }
      }
    }
    return {
      title: '还差一步：准备一个模型',
      text: `游戏自带一个小模型，免费，在这台设备上运行，下载${s.latest ? ` ${size} ` : ''}就能用；也可以连接在线的大模型。`,
      actions: [
        action('下载内置模型', () => void downloadBuiltin()),
        button('连接在线模型', () => void connect(), 'mp-link'),
        laterButton,
      ],
      idle: true,
    }
  }

  /** 提示卡、一行字和「设定」上的小绿点 */
  function render() {
    const config = transport.config()
    const s = builtinStatus()
    builtin.hidden = !s?.supported
    // 连上了在线服务，或者内置模型已经下好，就不用再提示
    const online = !!config?.providers.some((p) => p.id !== BUILTIN && usableProvider(p))
    const missing = s?.supported
      ? !!config && !online && !builtinReady()
      : hasModel(config) === false
    const copy = promptCopy()
    // 下载中、出错时不收起：那是正在发生的事
    const folded = copy.idle && later()
    prompt.hidden = !missing || folded
    line.hidden = !missing || !folded
    if (!prompt.hidden) {
      promptTitle.textContent = copy.title
      promptText.textContent = copy.text
      promptMeter.hidden = copy.meter === undefined
      promptFill.style.setProperty('--v', String(copy.meter ?? 0))
      promptSub.textContent = copy.sub ?? ''
      promptSub.hidden = !copy.sub
      actions.replaceChildren(...copy.actions)
      actions.hidden = !copy.actions.length
    }
    lineText.textContent = s?.supported ? '第一次玩？先准备一个模型' : '第一次玩？先连接一个模型'
    go.replaceChildren(s?.supported ? '准备' : '连接', gameIcon('chevron', true))
    entry.classList.toggle('has-dot', (missing && folded) || builtinNeedsAttention())
    if (dialog.open) renderSettings()
  }

  function refresh() {
    transport.load().then(render, () => {
      // 读不到（旧的管理服务没有这个接口）就不提示，不挡着进小镇
    })
  }
  refresh()
  onBuiltin(render)
  // 打开游戏时：接着下被打断的下载，开着自动更新就看有没有新版本
  void autoUpdateBuiltin()

  /** 建镇页没连模型时直接弄这个连接弹层，连好后首页的提示也跟着收起 */
  return { connect }
}

function chip(text: string) {
  return el('span', text, 'ui-chip ok')
}
