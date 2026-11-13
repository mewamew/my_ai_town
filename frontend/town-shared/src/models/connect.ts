// 连接模型的弹层：选一个模型服务、填密钥，测试连通后保存。首页的「设定」和提示卡、小镇里写世界观时
// 和点「开始」时都用它；首页经管理服务的 /api/towns/models，小镇里经世界连接，由 transport 决定。
// 手机上从底部升起，电脑上居中。它是模态对话框，从别的对话框里打开也盖在最上面。
// 有默认模型的服务可以直接连；要手填模型名、地址的服务进小镇后在「设定 · 模型服务」里配。
import type { ActiveModelChoice, ProviderConfig, ProviderView } from '../protocol'
import {
  PRESETS,
  localEndpoint,
  providerModel,
  providerRow,
  type ProviderPreset,
} from '../providers'
import { hourRange, priceOf } from '../pricing'
import { button, el } from '../dom'
import { errorText } from '../format'
import { isTouch, onBack } from '../platform'
import './connect.css'

/** 填个密钥就能用的服务（有默认模型），前四个先列出来，其余点「更多」 */
export const QUICK = [
  'deepseek',
  'kimi',
  'zhipu-glm',
  'minimax',
  'alibaba-bailian',
  'xiaomi-mimo',
  'volcengine-ark',
]
const FIRST = 4
/** 申请密钥的地方：只给到平台首页，路径变了也打得开 */
export const SIGN_UP: Record<string, string> = {
  deepseek: 'https://platform.deepseek.com',
  kimi: 'https://platform.moonshot.cn',
  'zhipu-glm': 'https://open.bigmodel.cn',
  minimax: 'https://platform.minimaxi.com',
  'alibaba-bailian': 'https://bailian.console.aliyun.com',
  'xiaomi-mimo': 'https://platform.xiaomimimo.com',
  'volcengine-ark': 'https://console.volcengine.com/ark',
}

export interface ModelConfig {
  active: ActiveModelChoice | null
  providers: ProviderView[]
}

export interface ModelTransport {
  config(): ModelConfig | null
  test(
    provider: ProviderConfig,
    model: string,
    key: string
  ): Promise<{ ok: boolean; message: string; latency_ms: number }>
  save(command: {
    active: ActiveModelChoice | null
    providers: ProviderConfig[]
    keys: { provider: string; api_key: string }[]
  }): Promise<void>
}

/** 这个服务现在能用：填过密钥，或者是不用密钥的本机服务 */
export function usableProvider(p: ProviderView): boolean {
  return (
    !!p.key_mask ||
    PRESETS.find((x) => x.id === p.id)?.needsKey === false ||
    (!!p.base_url && localEndpoint(p.base_url))
  )
}

/** 有没有能用的模型。还没读到配置时为 null */
export function hasModel(config: ModelConfig | null): boolean | null {
  if (!config) return null
  return config.providers.some(usableProvider)
}

/** 密钥框的占位：sk- 开头的写 sk-…，其余照服务名说 */
export function keyPlaceholder(preset: ProviderPreset) {
  return ['deepseek', 'kimi', 'alibaba-bailian'].includes(preset.id)
    ? 'sk-…'
    : `粘贴 ${preset.name} 的密钥`
}

/** 「还没有密钥？」：按所选的服务写怎么申请、钱从哪里扣、大概花多少。连接弹层和开局向导共用 */
export function keyHelp(preset: ProviderPreset): HTMLElement[] {
  const steps = el('ol')
  const price = priceOf({ provider: preset.id, model: preset.defaultModel })
  steps.append(
    el('li', `打开 ${preset.name} 开放平台，注册并登录`),
    el('li', '在控制台新建一个 API Key，复制回来贴在上面'),
    el(
      'li',
      price
        ? `费用按用量从你在 ${preset.name} 的账户里扣：3 位村民玩一小时大约 ${hourRange(price)}（按公布的价格估算）`
        : `费用按用量从你在 ${preset.name} 的账户里扣，价格看它的官网`
    )
  )
  const link = el('a', `打开 ${(SIGN_UP[preset.id] ?? '').replace(/^https?:\/\//, '')}`)
  link.href = SIGN_UP[preset.id] ?? '#'
  link.target = '_blank'
  link.rel = 'noopener'
  return [el('b', `还没有 ${preset.name} 的密钥？`), steps, link]
}

/** connected：连上并存好；skipped：点了左边的按钮（「先不连接」这类）；cancelled：关掉了 */
export type ConnectResult = 'connected' | 'skipped' | 'cancelled'

export function connectModel(
  t: ModelTransport,
  o: { title: string; text: string; dismiss: string; confirm: string; provider?: string }
): Promise<ConnectResult> {
  return new Promise((resolve) => {
    const presets = QUICK.map((id) => PRESETS.find((p) => p.id === id)).filter(
      (p): p is ProviderPreset => !!p
    )
    let preset = presets.find((p) => p.id === o.provider) ?? presets[0]
    let more = presets.indexOf(preset) >= FIRST
    let state: 'idle' | 'testing' | 'error' = 'idle'
    let message = ''
    let result: ConnectResult = 'cancelled'

    const dialog = el('dialog', '', 'model-connect')
    dialog.setAttribute('aria-label', o.title)
    const body = el('div', '', 'mc-body')
    const grid = el('div', '', 'mc-providers')
    const key = el('input', '', 'mc-key')
    key.type = 'text'
    key.autocomplete = 'off'
    key.spellcheck = false
    key.setAttribute('autocapitalize', 'off')
    const keyName = el('span')
    const field = el('label', '', 'mc-field')
    field.append(keyName, key)
    const status = el('p', '', 'mc-status')
    status.setAttribute('role', 'status')
    const help = el('div', '', 'mc-help')
    const dismiss = button(o.dismiss, () => finish('skipped'))
    const confirm = button(o.confirm, () => void connect(), 'primary')
    const foot = el('div', '', 'mc-foot')
    foot.append(dismiss, confirm)
    const heading = el('h2', o.title)
    heading.tabIndex = -1
    // 打开时的焦点：电脑上直接落在密钥框；触屏上落在标题，键盘一弹起来就盖住半个弹层
    if (isTouch()) heading.autofocus = true
    else key.autofocus = true
    body.append(
      el('div', '', 'mc-grip'),
      heading,
      el('p', o.text, 'mc-text'),
      grid,
      field,
      status,
      help,
      foot
    )
    dialog.append(body)

    const configured = () => t.config()?.providers.find((p) => p.id === preset.id)
    function render() {
      const shown = more ? presets : presets.slice(0, FIRST)
      grid.replaceChildren(
        ...shown.map((p) => {
          const b = button(
            '',
            () => {
              preset = p
              state = 'idle'
              key.value = ''
              render()
            },
            'mc-provider' + (p === preset ? ' on' : '')
          )
          const name = el('b', p.name)
          if (p.id === 'deepseek') name.append(el('span', '推荐', 'ui-chip ok'))
          const saved = t.config()?.providers.find((c) => c.id === p.id)?.key_mask
          b.append(name, el('small', saved ? '已连接' : p.defaultModel))
          b.setAttribute('aria-pressed', String(p === preset))
          return b
        })
      )
      if (!more) {
        const rest = presets.slice(FIRST).map((p) => p.name)
        grid.append(
          button(
            `更多服务：${rest.join('、')} ▾`,
            () => {
              more = true
              render()
            },
            'mc-more'
          )
        )
      }
      const saved = configured()?.key_mask
      keyName.textContent = `${preset.name} 的密钥`
      key.placeholder = saved ? `已保存 ${saved}，留空就用它` : keyPlaceholder(preset)
      help.replaceChildren(...keyHelp(preset))
      status.replaceChildren(
        state === 'testing'
          ? el('span', '正在连接…', 'ui-status busy')
          : state === 'error'
            ? el('span', message, 'ui-status danger')
            : ''
      )
      confirm.disabled = dismiss.disabled = state === 'testing'
      confirm.textContent = state === 'testing' ? '正在连接…' : o.confirm
    }

    // 先测通再存：服务、密钥一起写进配置；还没有建镇用的模型时顺便用它
    async function connect() {
      const config = t.config()
      const existing = configured()
      const typed = key.value.trim()
      if (!typed && !existing?.key_mask) {
        state = 'error'
        message = '先填上密钥'
        render()
        key.focus()
        return
      }
      const provider: ProviderConfig = {
        id: preset.id,
        name: existing?.name ?? preset.name,
        base_url: existing?.base_url || preset.baseUrl,
        ...(existing?.model ? { model: existing.model } : {}),
      }
      const model = providerModel(preset.id, existing, config?.active)
      state = 'testing'
      render()
      try {
        const tested = await t.test(provider, model, typed)
        if (!tested.ok) throw Error(tested.message || '连接失败')
        const all = (config?.providers ?? []).map((p) =>
          p.id === provider.id ? provider : providerRow(p)
        )
        await t.save({
          active: config?.active ?? { provider: provider.id, model },
          providers: existing ? all : [...all, provider],
          keys: typed ? [{ provider: provider.id, api_key: typed }] : [],
        })
        finish('connected')
      } catch (error) {
        state = 'error'
        message = errorText(error)
        render()
      }
    }

    let offBack = () => {}
    function finish(next: ConnectResult) {
      if (state === 'testing' && next !== 'connected') return
      result = next
      dialog.close()
    }
    dialog.addEventListener('close', () => {
      offBack()
      dialog.remove()
      resolve(result)
    })
    // 正在连接时不让 Esc 关掉，免得存到一半
    dialog.addEventListener('cancel', (event) => {
      if (state === 'testing') event.preventDefault()
    })
    // 点到弹层外面（遮罩）就关上
    dialog.addEventListener('click', (event) => {
      if (event.target === dialog) finish('cancelled')
    })
    render()
    document.body.append(dialog)
    dialog.showModal()
    offBack = onBack(() => {
      if (!dialog.open) return false
      finish('cancelled')
      return true
    })
  })
}
