import type {
  ClientMsg,
  GameModeChoice,
  PhysiologySwitches,
  ServerMsg,
  WorldSettingsState,
} from './protocol'
import type { SettingsPage } from './settingsCenter'
import { $, button, el, query } from './dom'
import { newId } from './ids'
import { gameIcon, iconLabel } from './game/icons'
import type { createModelSession } from './models/session'
import { isTouch } from './platform'

export const DEFAULT_WORLDVIEW = '这是一个宁静的小镇。居民相互认识，各自安排日常生活。'

/** 一个世界设定控制器，同时服务首次进入和设定中心，后端是唯一状态来源。 */
export function createWorldSettings(
  send: (msg: ClientMsg) => void,
  mapName: string,
  onChanged: () => void,
  /** 游戏界面 */
  game: boolean,
  /** 一句话建镇时的世界观建议（townWorldview.ts）；有的话代替默认的世界观 */
  suggested = ''
) {
  const fallback = suggested || DEFAULT_WORLDVIEW
  let state: WorldSettingsState | undefined
  let online = false
  let pending: { id: string; done: (ok: boolean, message: string) => void } | undefined
  const listeners = new Set<() => void>()
  /** 新世界还没设世界观时先问它：返回 true 表示由它接手（开局向导），不弹首次对话框 */
  let firstRun: (() => boolean) | null = null
  const flag = document.createElement('button')
  flag.id = 'world-mode'
  flag.className = 'world-mode'
  flag.textContent = '读取世界设定…'
  $('world-facts').after(flag)
  const dialog = document.createElement('dialog')
  dialog.className = 'world-setup'
  dialog.id = 'world-setup'
  dialog.innerHTML = `<form><p class="eyebrow">开始一个新世界</p><h1></h1><p>写给村民看的背景，他们会照着生活。可以先用默认的，以后在设定里改。</p>
    <label for="first-worldview">世界观</label><textarea id="first-worldview" rows="7" maxlength="6000"></textarea>
    <p class="hint">世界观决定村民怎么想、怎么说，变不出小镇里没有的东西。</p>
    <p class="world-save-status" role="status">正在读取世界设定…</p><div class="world-setup-actions"><a href="./">返回选择小镇</a><button type="submit" class="primary">保存世界观</button></div></form>`
  query(dialog, 'h1').textContent = mapName
  query(dialog, 'h1').tabIndex = -1
  // 还没连上模型时的「还差一步」：可以先写世界观，连上之后村民才会开始思考
  const modelHint = el('div', '', 'model-prompt world-model')
  modelHint.hidden = true
  query(dialog, 'h1').after(modelHint)
  let models: ReturnType<typeof createModelSession> | null = null
  const syncModelHint = () => {
    modelHint.hidden = models?.connected() !== false || !!state?.mock
  }
  const first = query<HTMLTextAreaElement>(dialog, 'textarea')
  first.value = fallback
  const firstButton = query<HTMLButtonElement>(dialog, 'button')
  const firstStatus = query(dialog, '[role=status]')
  dialog.addEventListener('cancel', (e) => e.preventDefault())
  document.body.append(dialog)
  function notify() {
    const ready = online && state?.ready
    flag.textContent = !online
      ? '正在重新连接…'
      : !state
        ? '读取世界设定…'
        : !state.ready
          ? '待设置世界观'
          : state.mock
            ? '测试模式'
            : 'AI 自主生活'
    if (game) iconLabel(flag, 'spark', flag.textContent ?? '世界设定', true)
    // 2D 顶栏只在不寻常的状态下显示这个标签；正常的 AI 自主生活不占顶栏位置。
    // 断开时也不显示：顶栏的连接状态和地图上的提示已经写了正在重新连接
    const normal = online && !!state?.ready && !state.mock
    flag.hidden = !game && (normal || !online)
    flag.title = state?.mock
      ? '固定回复 · 测试模式：村民用固定回复，不调用模型。村民模型在各自设定页单独配置；点击查看世界设定'
      : state?.ready
        ? '村民模型在各自设定页单独配置；点击查看世界设定'
        : '设置世界观后才能推进时间'
    document
      .querySelectorAll<HTMLButtonElement>('#speeds button')
      .forEach((b) => (b.disabled = !ready))
    firstButton.disabled = !online || !state || !!pending
    if (online && state && !state.ready && !dialog.open && !firstRun?.()) {
      // 对话框打开时会自动聚焦第一个输入框：触屏上那会立刻弹出键盘、盖住「保存世界观」，改成先聚焦标题
      query(dialog, 'h1').toggleAttribute('autofocus', isTouch())
      dialog.showModal()
    }
    if (state?.ready && dialog.open) dialog.close()
    syncModelHint()
    for (const listener of listeners) listener()
  }
  type Done = (ok: boolean, message: string) => void
  /** 世界观、生理开关与化身神力共用一个回执通道：同一时间只允许一个保存请求。 */
  function submit(
    build: (current: WorldSettingsState, requestId: string) => ClientMsg,
    done: Done
  ) {
    if (!online || !state) {
      done(false, '未连接，未保存')
      return
    }
    if (pending) {
      done(false, '正在保存，请等待回执')
      return
    }
    const id = newId()
    pending = { id, done }
    notify()
    send(build(state, id))
  }
  /** 陌生环境开关：放在世界观页底，切换就保存，不走底部保存条；显示值始终来自后端回读 */
  function strangersSwitch() {
    const root = el('section', '', 'physiology-switches miracles-switch')
    const row = el('label', '', 'physiology-row')
    const input = el('input')
    input.type = 'checkbox'
    input.id = 'settings-strangers'
    input.setAttribute('role', 'switch')
    row.htmlFor = input.id
    const description = el('small')
    const text = el('span', '', 'physiology-text')
    text.append(el('b', '村民初来乍到'), description)
    row.append(input, text)
    const status = el('p', '', 'physiology-status')
    status.setAttribute('role', 'status')
    root.append(
      el('h3', '对这里熟不熟'),
      row,
      el(
        'p',
        '适合荒岛、野地这类新地方。切换就保存，跟着这个小镇的存档；改了世界会暂停，村民重新观察。',
        'physiology-note'
      ),
      status
    )
    function render() {
      input.checked = !!state?.strangers
      input.disabled = !state || !online || !!pending
      row.classList.toggle('off', !input.checked)
      description.textContent = input.checked
        ? '只知道眼下所在的地方和家，别处要顺着路走过去才知道。'
        : '知道每个地方在哪、能做什么。'
    }
    input.addEventListener('change', () => {
      status.textContent = '正在保存…'
      submit(
        (current, id) => ({
          type: 'set_strangers',
          request_id: id,
          world_id: current.world_id,
          enabled: input.checked,
        }),
        (ok, message) => {
          status.textContent = ok ? `✓ ${message}` : message
          render()
        }
      )
      render()
    })
    listeners.add(render)
    render()
    return root
  }
  function save(text: string, revision: number, done: Done) {
    if (!text.trim()) {
      done(false, '请填写世界观')
      return
    }
    submit(
      (current, id) => ({
        type: 'set_worldview',
        request_id: id,
        world_id: current.world_id,
        expected_revision: revision,
        text,
      }),
      done
    )
  }
  query<HTMLFormElement>(dialog, 'form').onsubmit = (event) => {
    event.preventDefault()
    if (!state) return
    firstStatus.textContent = '正在保存…'
    save(first.value, state.revision, (ok, message) => {
      firstStatus.textContent = message
      if (ok) first.value = fallback
    })
  }
  return {
    state: () => state,
    online: () => online,
    /** 开局向导保存世界观；回执同首次对话框 */
    saveWorldview(text: string, done: Done) {
      if (!state) done(false, '还没读到世界设定')
      else save(text, state.revision, done)
    },
    setFirstRun(handler: (() => boolean) | null) {
      firstRun = handler
      notify()
    },
    /** 接上小镇的模型配置：没连上模型时，首次对话框里提示一句并能当场连上 */
    setModels(session: ReturnType<typeof createModelSession>) {
      models = session
      const badge = el('span', '', 'mp-badge')
      badge.append(gameIcon('spark', true))
      const actions = el('div', '', 'mp-actions')
      actions.append(
        button(
          '连接模型',
          () =>
            void session.connect({
              title: '连接一个模型',
              text: '居民靠大模型思考。选一个模型服务，填上你在那里申请的密钥。密钥只保存在这台设备上。',
              dismiss: '取消',
              confirm: '测试并保存',
            }),
          'mp-go'
        )
      )
      modelHint.replaceChildren(
        badge,
        el('b', '还差一步：连接一个模型'),
        el('span', '可以先写世界观；连上模型后，村民才会开始思考。', 'mp-text'),
        actions
      )
      session.subscribe(syncModelHint)
      syncModelHint()
    },
    defaultWorldview: fallback,
    /** 一句话建镇时的世界观建议；没有时为空串 */
    suggestedWorldview: suggested,
    saving: () => !!pending,
    /** 设定、连接或保存状态变化时回调；返回取消函数 */
    subscribe(listener: () => void) {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
    savePhysiology(switches: PhysiologySwitches, revision: number, done: Done) {
      submit(
        (current, id) => ({
          type: 'set_physiology',
          request_id: id,
          world_id: current.world_id,
          expected_revision: revision,
          switches,
        }),
        done
      )
    },
    /** 打开玩法（预制小镇开局时用）；回执同其他设定 */
    saveGameMode(choice: GameModeChoice, done: Done) {
      submit(
        (current, id) => ({
          type: 'set_game_mode',
          request_id: id,
          world_id: current.world_id,
          game_mode: choice,
        }),
        done
      )
    },
    /** 打开或关掉化身神力：切换就保存，不带修订号，世界不暂停 */
    saveMiracles(enabled: boolean, done: Done) {
      submit(
        (current, id) => ({
          type: 'set_miracles',
          request_id: id,
          world_id: current.world_id,
          enabled,
        }),
        done
      )
    },
    setOpenSettings(open: () => void) {
      flag.onclick = open
    },
    connected() {
      online = true
      send({ type: 'get_world_settings' })
      notify()
    },
    disconnected() {
      online = false
      if (pending) {
        pending.done(false, '连接断开，保存结果尚未确认；重新连接后读取当前设定')
        pending = undefined
      }
      firstStatus.textContent = '连接断开，请等待重新连接。'
      notify()
    },
    handleMsg(msg: ServerMsg) {
      if (msg.type === 'world_reset') {
        state = undefined
        first.value = fallback
        send({ type: 'get_world_settings' })
        notify()
      }
      if (msg.type === 'world_settings') {
        if (
          state &&
          (state.world_id !== msg.state.world_id || state.revision !== msg.state.revision)
        )
          onChanged()
        state = msg.state
        if (!state.ready) firstStatus.textContent = '世界已暂停。保存后，点顶栏的开始运行。'
        notify()
        return true
      }
      if (msg.type === 'world_settings_saved') {
        if (msg.request_id === pending?.id) {
          const done = pending.done
          pending = undefined
          done(msg.ok, msg.message)
          notify()
        }
        return true
      }
      // 保存命令没能执行（格式错误、命令过多）时回的是通用错误
      if (msg.type === 'error' && pending && msg.request_id === pending.id) {
        const done = pending.done
        pending = undefined
        done(false, msg.message)
        notify()
        return true
      }
      return false
    },
    page(onDirty: () => void): SettingsPage {
      const el = document.createElement('section')
      el.className = 'world-settings-page'
      el.innerHTML = `<h2>世界观</h2><p>设定只属于当前运行世界；修改会暂停世界、取消旧安排，并更新所有村民的 AI 上下文。</p>
        <label for="edit-worldview">世界观</label><textarea id="edit-worldview" rows="12" maxlength="6000"></textarea>
        <p class="hint">已有经历与记忆保留。世界观描述不会生成道具，也不会改写饥饿、疾病等生理机制。</p>
        <p class="world-save-status" role="status"></p>`
      const text = query<HTMLTextAreaElement>(el, 'textarea'),
        status = query(el, '[role=status]')
      el.append(strangersSwitch())
      let base = '',
        revision = -1,
        world = ''
      const dirty = () => text.value !== base
      function read() {
        base = state?.worldview ?? ''
        text.value = base
        revision = state?.revision ?? -1
        world = state?.world_id ?? ''
        status.textContent = ''
        onDirty()
      }
      text.oninput = onDirty
      listeners.add(() => {
        if (!state) return
        if (world !== state.world_id || (!dirty() && revision !== state.revision)) read()
        else if (revision !== state.revision && !pending)
          status.textContent = '设定已在其他页面更新；你的草稿保留。点「放弃」读取新内容。'
        text.disabled = !online || !!pending
      })
      return {
        id: 'worldview',
        group: 'town',
        navLabel: '世界观',
        title: '世界观',
        el,
        isDirty: dirty,
        discard: read,
        onShow: () => {
          if (!dirty()) read()
          if (online) send({ type: 'get_world_settings' })
        },
        save() {
          status.textContent = '正在保存…'
          save(text.value, revision, (ok, message) => {
            if (ok) read()
            status.textContent = message
            onDirty()
          })
        },
      }
    },
  }
}
export type WorldSettingsController = ReturnType<typeof createWorldSettings>
