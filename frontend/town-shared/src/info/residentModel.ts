import type { ModelChoice, ProviderView, ServerMsg } from '../protocol'
import { statusLine } from '../dom'
import { BUILTIN, PRESETS, needsKey } from '../providers'
import { displayClock } from '../format'
import { $, htmlText } from '../settings/page'
import { residentModelProblem } from './residentModelValidation'
import { saveInTurn, trackOtherResidents } from './residentModelOthers'
import type { CardPageDeps, TabPage } from './tabs'

const sameChoice = (a: ModelChoice, b: ModelChoice | null) =>
  a?.provider === b?.provider && a?.model === b?.model

// 角色卡 → 模型：每位村民单独绑定模型，没有默认值；没绑定时下拉框停在「请选择」，不预选任何服务。
// 服务和密钥本身在右上角的「设定 → 模型服务」里配。
export function createResidentModelPage(deps: CardPageDeps): TabPage {
  const el = document.createElement('section')
  el.className = 'spage'
  const name = htmlText(deps.resident.name)
  const suffix = deps.resident.id.replace(/[^a-zA-Z0-9_-]/g, '-')
  const providerId = `resident-model-provider-${suffix}`
  const modelId = `resident-model-name-${suffix}`
  const listId = `resident-model-list-${suffix}`
  el.innerHTML = `
    <h2>${name}用的模型</h2>
    <p class="hint">${name}每次做决定、整理记忆都会调用这个模型。</p>
    <div class="form-row">
      <label for="${providerId}">模型服务</label>
      <select id="${providerId}"></select>
    </div>
    <div class="form-row">
      <label for="${modelId}">模型名</label>
      <input id="${modelId}" list="${listId}" spellcheck="false">
      <datalist id="${listId}"></datalist>
    </div>
    <div class="form-status dim rm-provider-state"></div>
    <div class="row"><button type="button" class="rm-goto">去配置这个服务</button></div>
    <div class="form-status rm-current"></div>
    <div class="row"><button type="button" class="rm-apply-others" hidden></button></div>
    <div class="page-status"></div>`

  const provider = $<HTMLSelectElement>(el, `#${providerId}`)
  const model = $<HTMLInputElement>(el, `#${modelId}`)
  const models = $<HTMLDataListElement>(el, `#${listId}`)
  const providerState = $<HTMLElement>(el, '.rm-provider-state')
  const goto = $<HTMLButtonElement>(el, '.rm-goto')
  const current = $<HTMLElement>(el, '.rm-current')
  const applyOthers = $<HTMLButtonElement>(el, '.rm-apply-others')
  const status = $<HTMLElement>(el, '.page-status')
  const others = trackOtherResidents(deps.resident.id, deps.send)

  let configured: ProviderView[] = []
  let saved: ModelChoice | null = null
  let dirty = false
  let applying = false

  const presetOf = (id: string) => PRESETS.find((preset) => preset.id === id)
  const labelOf = (choice: ModelChoice) =>
    `${presetOf(choice.provider)?.name ?? choice.provider} / ${choice.model}`
  const edited = (): ModelChoice => ({ provider: provider.value, model: model.value.trim() })

  const showStatus = statusLine(status)
  /** 提示里带的游戏时刻按界面格式显示 */
  function setStatus(text: string, cls = '') {
    showStatus(displayClock(text), cls)
  }

  function fillModels() {
    models.replaceChildren(...(presetOf(provider.value)?.models ?? []).map((id) => new Option(id)))
  }

  /** 没选服务时模型名不能填，占位写「先选服务」 */
  function renderProviderState() {
    const chosen = !!provider.value
    model.disabled = !chosen
    model.placeholder = chosen ? '' : '先选服务'
    // 内置模型没有要配置的
    goto.hidden = !chosen || provider.value === BUILTIN
    const conf = configured.find((item) => item.id === provider.value)
    const preset = presetOf(provider.value)
    providerState.textContent = !chosen
      ? configured.length
        ? ''
        : '还没有配置任何模型服务，先到右上角「设定 → 模型服务」配置。'
      : provider.value === BUILTIN
        ? '随游戏自带，在这台设备上运行，不用密钥也不花钱'
        : conf?.key_mask
          ? `这个服务已配置密钥 ${conf.key_mask}`
          : preset && !needsKey(preset, conf?.base_url)
            ? '本地服务，不需要密钥'
            : '这个服务还没有配置密钥'
  }

  function renderCurrent() {
    current.textContent = saved
      ? `当前使用：${labelOf(saved)}`
      : `还没选模型。${deps.resident.name}在选好之前不会行动。`
    current.className = 'form-status rm-current ' + (saved ? 'ok' : 'drop')
  }

  function renderApplyOthers() {
    const count = others.unbound().length
    applyOthers.hidden = count === 0
    applyOthers.textContent = `保存，并套用到其他 ${count} 位还没选的村民`
    applyOthers.disabled = applying
  }

  function fill() {
    const bound = saved && configured.some((item) => item.id === saved?.provider)
    // 「请选择」只是提示：藏起来不进列表，框里显示成浅色
    const prompt = new Option('请选择', '')
    prompt.hidden = prompt.disabled = true
    provider.replaceChildren(
      ...(bound ? [] : [prompt]),
      ...configured.map((item) => new Option(item.name, item.id))
    )
    provider.value = bound && saved ? saved.provider : ''
    model.value = provider.value ? (saved?.model ?? '') : ''
    provider.disabled = configured.length === 0
    fillModels()
    renderProviderState()
    renderCurrent()
  }

  function onInput() {
    dirty = !sameChoice(edited(), saved)
    renderProviderState()
    deps.onDirty()
  }

  provider.addEventListener('change', () => {
    const preset = presetOf(provider.value)
    model.value = preset?.defaultModel ?? ''
    fillModels()
    onInput()
  })
  model.addEventListener('input', onInput)
  goto.onclick = () => {
    if (provider.value) deps.showPage('prov-' + provider.value)
  }

  /** 表单里的选择过校验才返回；没过就把原因写到页面状态行 */
  function checkedChoice(): ModelChoice | null {
    const choice = edited()
    const problem = residentModelProblem(
      choice,
      configured,
      needsKey(
        presetOf(choice.provider),
        configured.find((item) => item.id === choice.provider)?.base_url
      )
    )
    if (problem) setStatus(problem, 'drop')
    return problem ? null : choice
  }

  function markSaved(choice: ModelChoice) {
    saved = choice
    dirty = false
    deps.onDirty()
    fill()
  }

  applyOthers.onclick = () => {
    const choice = checkedChoice()
    if (!choice || applying) return
    const targets = [{ id: deps.resident.id, name: deps.resident.name }, ...others.unbound()]
    applying = true
    renderApplyOthers()
    setStatus('保存中…')
    saveInTurn(
      targets,
      choice,
      deps.save,
      (id, ok) => {
        if (ok && id === deps.resident.id) markSaved(choice)
      },
      (count, failed) => {
        applying = false
        renderApplyOthers()
        const failures = failed.map((f) => `${f.name}（${f.message}）`).join('、')
        setStatus(
          `已给 ${count} 位村民设好。${failures ? `没设好：${failures}` : ''}`,
          failed.length ? 'drop' : 'ok'
        )
      }
    )
  }

  return {
    title: `${deps.resident.name}用的模型`,
    el,
    isDirty: () => dirty,
    save() {
      const choice = checkedChoice()
      if (!choice) return
      // 先写「保存中…」：没连上时回执立刻回来，结果不能被它盖掉
      setStatus('保存中…')
      deps.save(
        { type: 'set_resident_model', resident: deps.resident.id, model: choice },
        (ok, message) => {
          if (ok) {
            markSaved(choice)
            setStatus(`✓ ${deps.resident.name}的模型已保存，下一次请求生效。`, 'ok')
          } else setStatus('✗ ' + message, 'drop')
        }
      )
    },
    discard() {
      dirty = false
      fill()
      setStatus('已放弃修改，恢复为已保存的模型选择')
      deps.onDirty()
    },
    onShow() {
      setStatus('')
      deps.send({ type: 'get_agent_config', resident: deps.resident.id })
      deps.send({ type: 'get_model_config' })
      others.refresh()
    },
    handleMsg(msg: ServerMsg) {
      if (others.handleMsg(msg)) {
        if (msg.type === 'roster' && el.isConnected) others.refresh(true)
        renderApplyOthers()
      }
      if (msg.type === 'agent_config') {
        if (msg.resident_id !== deps.resident.id) return
        saved = msg.model_binding ?? null
      } else if (msg.type === 'model_config') {
        configured = msg.providers
      } else return
      if (!dirty) fill()
      else renderCurrent()
    },
  }
}
