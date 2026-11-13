import type { ActiveModelChoice, ProviderView, ServerMsg } from '../protocol'
import { statusLine } from '../dom'
import {
  BUILTIN,
  PRESETS,
  modelCandidates,
  needsKey,
  providerModel,
  providerRow,
} from '../providers'
import type { SettingsPage } from '../settingsCenter'
import { $, type PageDeps } from './page'

export function createModelPage(deps: PageDeps): SettingsPage {
  const el = document.createElement('section')
  el.className = 'spage'
  el.innerHTML = `
    <h2>默认模型</h2>
    <p class="hint">新请进来的村民默认用它，写人设、生成人物也用它。每位村民可以在自己角色卡的「模型」里换。</p>
    <div class="form-row">
      <label for="use-prov">模型服务</label>
      <select id="use-prov"></select>
    </div>
    <div class="form-row">
      <label for="use-model">模型名</label>
      <input id="use-model" list="use-model-list" spellcheck="false">
      <datalist id="use-model-list"></datalist>
    </div>
    <div class="form-status dim" id="use-prov-state"></div>
    <div class="row"><button type="button" id="use-goto">去配置此服务</button></div>
    <p class="hint" id="use-current"></p>
    <div class="page-status"></div>`
  const sel = $<HTMLSelectElement>(el, '#use-prov')
  const model = $<HTMLInputElement>(el, '#use-model')
  const datalist = $<HTMLDataListElement>(el, '#use-model-list')
  const provState = $<HTMLElement>(el, '#use-prov-state')
  const current = $<HTMLElement>(el, '#use-current')
  const status = $<HTMLElement>(el, '.page-status')

  let configured: ProviderView[] = []
  /** 应用带着内置模型：村民不指定默认模型也能用它 */
  let builtin = false
  let active: ActiveModelChoice | null = null
  let dirty = false

  const setStatus = statusLine(status)
  const presetOf = (id: string) => PRESETS.find((p) => p.id === id)
  const confOf = (id: string) => configured.find((p) => p.id === id)

  function renderProvState() {
    const id = sel.value
    const conf = configured.find((p) => p.id === id)
    const preset = presetOf(id)
    if (!id) {
      provState.textContent = ''
      return
    }
    provState.textContent = conf?.key_mask
      ? `该服务已配置密钥 ${conf.key_mask}`
      : preset && !needsKey(preset, conf?.base_url)
        ? '本地服务，无需密钥'
        : '该服务尚未配置密钥'
  }

  function fillModels() {
    datalist.replaceChildren(
      ...modelCandidates(sel.value, confOf(sel.value)).map((m) => new Option(m))
    )
  }

  function fill() {
    sel.replaceChildren(...configured.map((p) => new Option(p.name, p.id)))
    sel.disabled = configured.length === 0
    const chosen = active
    sel.value =
      chosen && configured.some((p) => p.id === chosen.provider)
        ? chosen.provider
        : (configured[0]?.id ?? '')
    model.value = active?.model ?? ''
    fillModels()
    renderProvState()
    renderCurrent()
  }

  function renderCurrent() {
    current.textContent = active
      ? `当前：${presetOf(active.provider)?.name ?? active.provider} / ${active.model}`
      : builtin
        ? '尚未指定模型；村民可以用内置模型，写人设、生成人物要用在线的模型服务。'
        : '尚未指定模型；未指定时调用会失败并等待。'
    if (configured.length === 0) {
      current.textContent += builtin
        ? '　还没有配置在线的模型服务，可以在左侧「模型服务」中填写。'
        : '　尚未配置任何模型服务，请先在左侧「模型服务」中配置。'
    }
  }

  function onInput() {
    dirty = sel.value !== (active?.provider ?? '') || model.value !== (active?.model ?? '')
    renderProvState()
    deps.onDirty()
  }
  sel.addEventListener('change', () => {
    // 换服务商时模型名跟着换：换回已保存的服务商用已存的名字，否则用「模型服务」里给它填的、
    // 再没有用预置的缺省（可再手改）；都没有的留空，不能沿用上一家的模型名
    model.value =
      sel.value === active?.provider ? active.model : providerModel(sel.value, confOf(sel.value))
    fillModels()
    onInput()
  })
  model.addEventListener('input', onInput)
  $<HTMLButtonElement>(el, '#use-goto').onclick = () => {
    if (sel.value) deps.showPage('prov-' + sel.value)
  }

  return {
    id: 'model',
    group: 'model',
    navLabel: '默认模型',
    title: '默认模型',
    el,
    isDirty: () => dirty,
    save() {
      if (!sel.value) {
        setStatus('尚未配置任何模型服务，请先到「模型服务」页配置', 'drop')
        return
      }
      if (!model.value.trim()) {
        setStatus('模型名不能为空', 'drop')
        return
      }
      // 这里是非村民工具模型，不参与村民路由。
      const choice: ActiveModelChoice = {
        provider: sel.value,
        model: model.value.trim(),
      }
      // providers 原样保留（连同各服务记着的模型名），只改 active；密钥不碰
      const providers = configured.map(providerRow)
      // 先写「保存中…」：没连上时回执立刻回来，结果不能被它盖掉
      setStatus('保存中…')
      deps.save(
        { type: 'set_model_config', active: choice, providers, keys: [] },
        (ok, message) => {
          if (ok) {
            active = choice
            dirty = false
            deps.onDirty()
            renderCurrent()
            setStatus('✓ 默认模型已保存；已经住着的村民还用各自的模型。', 'ok')
          } else setStatus('✗ ' + message, 'drop')
        }
      )
    },
    discard() {
      dirty = false
      fill()
      setStatus('已放弃修改，恢复为已保存的默认模型')
      deps.onDirty()
    },
    handleMsg(msg: ServerMsg) {
      if (msg.type !== 'model_config') return
      // 默认模型还要写人设、生成人物，内置模型只练过村民过日子
      configured = msg.providers.filter((p) => p.id !== BUILTIN)
      builtin = configured.length < msg.providers.length
      active = msg.active
      if (!dirty) fill()
      else renderCurrent()
    },
  }
}
