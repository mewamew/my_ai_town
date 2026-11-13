import { providerTemplate } from './providerTemplate'
import { providerTestCommand, type ProviderEdit } from './providerCommands'
// 一个服务商的编辑表单：服务地址 / 密钥 / 模型名 / 测试连接。
// 表单挂在「模型服务」页的表格行下面，保存由那一页把各表单的修改合成一条命令发出。
// 模型名跟着服务存下来：别处选这个服务时自动填上它，自定义、本机服务就不用每次再输一遍。
// 纪律：密钥只往服务端送，回读永远只有掩码；输入框留空 = 保持已存密钥。

import type { ActiveModelChoice, ProviderView, ServerMsg } from '../protocol'
import { modelCandidates, needsKey, providerModel, type ProviderPreset } from '../providers'
import { newId } from '../ids'
import { $, type PageDeps } from './page'

export interface ProviderForm {
  preset: ProviderPreset
  el: HTMLElement
  isDirty(): boolean
  /** 改了哪些字段，保存栏上列出 */
  changes(): string[]
  /** 要保存的内容；填得不对时返回原因 */
  draft(): ProviderEdit | string
  /** 保存成功：已存值换成刚保存的，密钥框清空 */
  saved(): void
  /** 连接断开：还没有结果的连接测试以失败结束 */
  disconnected(): void
  discard(): void
  handleMsg(msg: ServerMsg): void
}

export function createProviderForm(preset: ProviderPreset, deps: PageDeps): ProviderForm {
  const el = document.createElement('div')
  el.className = 'prov-form'
  el.innerHTML = providerTemplate(preset)
  const url = $<HTMLInputElement>(el, '.p-url')
  const key = $<HTMLInputElement>(el, '.p-key')
  const model = $<HTMLInputElement>(el, '.p-model')
  const datalist = $<HTMLDataListElement>(el, '.p-model + datalist')
  const testStatus = $<HTMLElement>(el, '.p-test-status')

  let conf: ProviderView | undefined // 服务端已存的该服务商配置
  let active: ActiveModelChoice | null = null // 工具模型用的服务商与模型，没存过模型名时给它一个默认值
  let dirty = false

  const savedUrl = () => conf?.base_url || preset.baseUrl
  /** 框里先显示什么：存过的模型名；没存过时默认模型用着这个服务就填它，再不然填预置的缺省 */
  const savedModel = () => providerModel(preset.id, conf, active)

  /** 密钥框的占位跟着地址走：地址改成本机的，就不用密钥 */
  function keyHint() {
    key.placeholder = conf?.key_mask
      ? '已保存，留空不改'
      : needsKey(preset, url.value.trim())
        ? '填 API 密钥'
        : '本机服务，不用密钥'
  }

  function fillKey() {
    key.value = ''
    keyHint()
  }

  function fillForm() {
    url.value = savedUrl()
    model.value = savedModel()
    fillKey()
    datalist.replaceChildren(...modelCandidates(preset.id, conf).map((m) => new Option(m)))
  }

  function markDirty() {
    dirty = url.value !== savedUrl() || key.value !== '' || model.value.trim() !== savedModel()
    deps.onDirty()
  }
  for (const inp of [url, key, model]) inp.addEventListener('input', markDirty)
  url.addEventListener('input', keyHint)

  const providerMsg = () => ({
    id: preset.id,
    name: preset.name,
    base_url: url.value.trim(),
    model: model.value.trim(),
  })

  /** 正在等结果的连接测试的请求编号 */
  let testing: string | null = null
  const showTest = (ok: boolean, text: string) => {
    testing = null
    testStatus.textContent = text
    testStatus.className = 'form-status p-test-status ' + (ok ? 'ok' : 'drop')
  }
  $<HTMLButtonElement>(el, '.p-test').onclick = () => {
    testStatus.textContent = '测试中…'
    testStatus.className = 'form-status p-test-status'
    testing = newId()
    deps.send(providerTestCommand(testing, providerMsg(), model.value.trim(), key.value.trim()))
  }

  fillForm()

  return {
    preset,
    el,
    isDirty: () => dirty,
    changes() {
      const out: string[] = []
      if (url.value !== savedUrl()) out.push('服务地址')
      if (key.value !== '') out.push('API 密钥')
      if (model.value.trim() !== savedModel()) out.push('模型名')
      return out
    },
    draft() {
      const provider = providerMsg()
      if (!provider.base_url) return `${preset.name}的服务地址不能为空`
      return { provider, key: key.value.trim() }
    },
    saved() {
      const provider = providerMsg()
      conf = {
        ...provider,
        key_mask: key.value.trim() ? '已保存' : (conf?.key_mask ?? ''),
      }
      dirty = false
      fillKey()
    },
    discard() {
      dirty = false
      fillForm()
    },
    handleMsg(msg: ServerMsg) {
      if (msg.type === 'model_config') {
        conf = msg.providers.find((p) => p.id === preset.id)
        active = msg.active
        if (!dirty) fillForm()
        return
      }
      if (msg.type === 'model_test_result' && msg.request_id === testing)
        showTest(
          msg.ok,
          msg.ok
            ? `✓ 连接正常 · ${(msg.latency_ms / 1000).toFixed(1)} 秒：${msg.message}`
            : `✗ ${msg.message}`
        )
      else if (msg.type === 'error' && testing !== null && msg.request_id === testing)
        showTest(false, `✗ ${msg.message}`)
    },
    disconnected() {
      if (testing !== null) showTest(false, '✗ 连接断开，没有收到测试结果')
    },
  }
}
