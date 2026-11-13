// 小镇里的模型配置：记着世界发来的 model_config，给连接模型的弹层当传输（经世界连接测试与保存）。
// 连上以后，镇上还没选模型的村民都设成刚连上的那个，不然点了开始他们也只会站着。
// 写世界观时的「还差一步」和点「开始」前的拦截都用它。
import type { Receipt, SaveCommand } from '../connection'
import { newId } from '../ids'
import type { ClientMsg, ModelChoice, ServerMsg } from '../protocol'
import { PRESETS, providerRow, quickModelNames } from '../providers'
import type { ShellPanel } from '../shell/panel'
import {
  connectModel,
  hasModel,
  usableProvider,
  type ConnectResult,
  type ModelConfig,
  type ModelTransport,
} from './connect'

/** 一个能用的模型：服务、模型名和给玩家看的服务名 */
export interface ModelOption extends ModelChoice {
  name: string
}

type Waiter = { match: (m: ServerMsg) => unknown; resolve: (v: unknown) => void }

export function createModelSession(deps: {
  send: (msg: ClientMsg) => void
  save: (command: SaveCommand, receipt: Receipt) => void
  /** 镇上居民的编号 */
  residents: () => string[]
}) {
  let config: ModelConfig | null = null
  /** 弹层里最近测试通过、存好的那个服务和模型 */
  let tested: ModelChoice | null = null
  let lastConnected: ModelChoice | null = null
  const watchers = new Set<() => void>()
  const waiters: Waiter[] = []
  function waitFor<T>(match: (m: ServerMsg) => T | undefined, ms: number) {
    return new Promise<T>((resolve, reject) => {
      const waiter: Waiter = { match, resolve: resolve as (v: unknown) => void }
      waiters.push(waiter)
      setTimeout(() => {
        const i = waiters.indexOf(waiter)
        if (i < 0) return
        waiters.splice(i, 1)
        reject(Error('小镇没有及时回应，请检查连接后重试'))
      }, ms)
    })
  }
  const saved = (command: SaveCommand) =>
    new Promise<void>((resolve, reject) =>
      deps.save(command, (ok, message) => (ok ? resolve() : reject(Error(message))))
    )
  function changed(next: ModelConfig) {
    config = next
    for (const watch of watchers) watch()
  }

  const transport: ModelTransport = {
    config: () => config,
    test(provider, model, key) {
      tested = { provider: provider.id, model }
      const request_id = newId()
      deps.send({
        type: 'test_model_connection',
        request_id,
        provider,
        model,
        ...(key ? { api_key: key } : {}),
      })
      return waitFor(
        (m) => (m.type === 'model_test_result' && m.request_id === request_id ? m : undefined),
        60000
      )
    },
    async save(command) {
      await saved({ type: 'set_model_config', ...command })
      lastConnected = tested
      // 世界随后会广播新的配置；先按刚存的改好，提示和拦截立刻跟着变
      const keyed = new Set(command.keys.map((k) => k.provider))
      changed({
        active: command.active,
        providers: command.providers.map((p) => ({
          ...p,
          model: p.model ?? '',
          key_mask: keyed.has(p.id)
            ? '已保存'
            : (config?.providers.find((c) => c.id === p.id)?.key_mask ?? ''),
        })),
      })
    },
  }

  const providerName = (id: string) =>
    config?.providers.find((p) => p.id === id)?.name || PRESETS.find((p) => p.id === id)?.name || id
  /** 当前模型排第一，聚合平台同时列出预置的快捷候选。 */
  function options(): ModelOption[] {
    if (!config) return []
    const list: ModelOption[] = []
    const active = config.active
    const usable = config.providers.filter(usableProvider)
    if (active && usable.some((p) => p.id === active.provider))
      list.push({ ...active, name: providerName(active.provider) })
    for (const p of usable) {
      const current = active?.provider === p.id ? active.model : undefined
      for (const model of quickModelNames(p.id, current, p.model)) {
        if (!list.some((o) => o.provider === p.id && o.model === model))
          list.push({ provider: p.id, model, name: providerName(p.id) })
      }
    }
    return list
  }

  /** 还没选模型的村民都用这个（默认是 `options` 的第一个）；单独选过的不动。所有人一起问、一起设 */
  async function bindUnbound(chosen?: ModelChoice) {
    const option = chosen ?? options()[0]
    const choice = option && { provider: option.provider, model: option.model }
    if (!choice) return
    await Promise.all(
      deps.residents().map(async (id) => {
        const reply = waitFor(
          (m) => (m.type === 'agent_config' && m.resident_id === id ? m : undefined),
          15000
        )
        deps.send({ type: 'get_agent_config', resident: id })
        if (!(await reply).model_binding)
          await saved({ type: 'set_resident_model', resident: id, model: choice })
      })
    )
  }

  const panel: ShellPanel = {
    // 只旁听：设定中心也要这些消息
    handleMsg(m) {
      if (m.type === 'model_config') changed({ active: m.active, providers: m.providers })
      for (const waiter of [...waiters]) {
        const value = waiter.match(m)
        if (value === undefined) continue
        waiters.splice(waiters.indexOf(waiter), 1)
        waiter.resolve(value)
      }
    },
  }

  return {
    panel,
    /** 有没有能用的模型；还没读到配置时为 null */
    connected: () => hasModel(config),
    options,
    providerName,
    /** 服务名 → 编号（暂停卡上写的是服务名） */
    providerId: (name: string) =>
      config?.providers.find((p) => p.name === name || p.id === name)?.id ??
      PRESETS.find((p) => p.name === name)?.id,
    bindUnbound,
    /** 连接弹层最近连上的那个；换服务后用它的村民改用它 */
    lastConnected: (): ModelOption | null =>
      lastConnected && { ...lastConnected, name: providerName(lastConnected.provider) },
    /** 设成小镇默认的模型：之后请进来的村民用它 */
    async makeActive(choice: ModelChoice) {
      if (!config) return
      const { active } = config
      if (active?.provider === choice.provider && active.model === choice.model) return
      await transport.save({
        active: { provider: choice.provider, model: choice.model },
        providers: config.providers.map(providerRow),
        keys: [],
      })
    },
    /** 给一位村民选模型 */
    bindResident: (id: string, choice: ModelChoice) =>
      saved({
        type: 'set_resident_model',
        resident: id,
        model: { provider: choice.provider, model: choice.model },
      }),
    subscribe(watch: () => void) {
      watchers.add(watch)
      return () => watchers.delete(watch)
    },
    /** 打开连接弹层；连上后在后台把还没选模型的村民都设成它，不耽误接着开始 */
    async connect(options: Parameters<typeof connectModel>[1]): Promise<ConnectResult> {
      const result = await connectModel(transport, options)
      if (result === 'connected')
        void bindUnbound().catch(() => {
          // 没设上的村民卡片上会写「还没选模型」，点进去还能选
        })
      return result
    },
  }
}
