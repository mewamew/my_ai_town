import type { ActiveModelChoice, ClientMsg, ProviderConfig, ProviderView } from '../protocol'
import type { SaveCommand } from '../connection'
import { providerRow } from '../providers'

/** 一个服务商的待保存内容：密钥为空表示保持已存密钥 */
export interface ProviderEdit {
  provider: ProviderConfig
  key: string
}

export function providerTestCommand(
  request_id: string,
  provider: ProviderConfig,
  model: string,
  key: string
): ClientMsg {
  return {
    type: 'test_model_connection',
    request_id,
    provider,
    model,
    ...(key ? { api_key: key } : {}),
  }
}

/** 服务端按整表保存：没改的服务商原样带上，active 指派不动。
 *  改了的服务没带模型名（只改地址、密钥的入口）时沿用记着的；带了空串才是清掉 */
export function providerSaveCommand(
  active: ActiveModelChoice | null,
  all: ProviderView[],
  edits: ProviderEdit[]
): SaveCommand {
  const edited = new Set(edits.map((e) => e.provider.id))
  const withModel = (p: ProviderConfig): ProviderConfig => {
    const model = p.model ?? all.find((v) => v.id === p.id)?.model
    return { id: p.id, name: p.name, base_url: p.base_url, ...(model ? { model } : {}) }
  }
  return {
    type: 'set_model_config',
    active,
    providers: [
      ...all.filter((p) => !edited.has(p.id)).map(providerRow),
      ...edits.map((e) => withModel(e.provider)),
    ],
    keys: edits.filter((e) => e.key).map((e) => ({ provider: e.provider.id, api_key: e.key })),
  }
}
