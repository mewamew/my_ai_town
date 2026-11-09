// 服务商预置目录：参照老项目 ModelProviderCatalog（内容权威 ~/dev/my_ai_town）。
// 全部走 OpenAI 兼容传输——base_url 不含 /chat/completions 后缀（host 拼接）。
// 模型清单 = 老目录预置 + 常用官方名；页面上模型可自由输入，清单只是候选。

export interface ProviderPreset {
  id: string
  name: string
  baseUrl: string
  needsKey: boolean
  models: string[]
  defaultModel: string
}

export const PRESETS: ProviderPreset[] = [
  {
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    needsKey: true,
    models: ['deepseek-chat', 'deepseek-reasoner', 'deepseek-v4-flash', 'deepseek-v4-pro'],
    defaultModel: 'deepseek-chat',
  },
  {
    id: 'kimi',
    name: 'Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    needsKey: true,
    models: ['kimi-k3', 'kimi-k2.7-code-highspeed', 'kimi-k2.6', 'kimi-k2.5'],
    defaultModel: 'kimi-k3',
  },
  {
    id: 'zhipu-glm',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    needsKey: true,
    models: ['glm-5.2', 'glm-5.1', 'glm-5', 'glm-4.7', 'glm-5v-turbo'],
    defaultModel: 'glm-5.2',
  },
  {
    id: 'minimax',
    name: 'MiniMax',
    baseUrl: 'https://api.minimaxi.com/v1',
    needsKey: true,
    models: [
      'MiniMax-M3',
      'MiniMax-M2.7',
      'MiniMax-M2.7-highspeed',
      'MiniMax-M2.5',
      'MiniMax-M2.5-highspeed',
      'MiniMax-M2.1',
      'MiniMax-M2.1-highspeed',
      'MiniMax-M2',
    ],
    defaultModel: 'MiniMax-M2.7',
  },
  {
    id: 'volcengine-ark',
    name: '火山方舟',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    needsKey: true,
    models: [],
    defaultModel: '',
  },
  {
    id: 'alibaba-bailian',
    name: '阿里百炼',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    needsKey: true,
    models: [
      'qwen3.7-plus',
      'qwen3.7-max',
      'qwen3.6-plus',
      'qwen3.6-flash',
      'qwen3.6-max-preview',
      'qwen3.5-plus',
      'qwen3.5-flash',
    ],
    defaultModel: 'qwen3.7-plus',
  },
  {
    id: 'xiaomi-mimo',
    name: '小米 MiMo',
    baseUrl: 'https://api.xiaomimimo.com/v1',
    needsKey: true,
    models: ['mimo-v2.6-pro', 'mimo-v2.6-pro-ultraspeed', 'mimo-v2.6-flash'],
    defaultModel: 'mimo-v2.6-pro',
  },
  {
    id: '302-ai',
    name: '302.AI',
    baseUrl: 'https://api.302.ai/v1',
    needsKey: true,
    models: [],
    defaultModel: '',
  },
  {
    // 老项目走 Ollama 原生 API；本项目统一 OpenAI 兼容端点
    id: 'ollama',
    name: 'Ollama（本地）',
    baseUrl: 'http://127.0.0.1:11434/v1',
    needsKey: false,
    models: [],
    defaultModel: '',
  },
  {
    id: 'ollama-cloud',
    name: 'Ollama Cloud',
    baseUrl: 'https://ollama.com/v1',
    needsKey: true,
    models: [],
    defaultModel: '',
  },
  {
    id: 'lm-studio',
    name: 'LM Studio（本地）',
    baseUrl: 'http://127.0.0.1:1234/v1',
    needsKey: false,
    models: [],
    defaultModel: '',
  },
  {
    id: 'custom',
    name: '自定义（OpenAI 兼容）',
    baseUrl: '',
    needsKey: true,
    models: [],
    defaultModel: '',
  },
  {
    // 随游戏带的小模型，世界进程在本机跑；应用带着它时服务端才把它列进配置
    id: 'builtin',
    name: '内置模型',
    baseUrl: '',
    needsKey: false,
    models: ['小镇村民'],
    defaultModel: '小镇村民',
  },
]

/** 内置模型：不用地址和密钥，只给村民过日子用，不写人设、不建镇 */
export const BUILTIN = 'builtin'

/** 本机或局域网地址上的服务（Ollama、LM Studio 这类）不用密钥；和服务端的判断一致 */
export function localEndpoint(url: string): boolean {
  let host = ''
  try {
    host = new URL(url).hostname.replace(/^\[|\]$/g, '').toLowerCase()
  } catch {
    return false
  }
  return (
    host === 'localhost' ||
    host.endsWith('.localhost') ||
    host.endsWith('.local') ||
    host === '::1' ||
    /^(127\.|10\.|192\.168\.|169\.254\.|0\.0\.0\.0$)/.test(host) ||
    /^172\.(1[6-9]|2\d|3[01])\./.test(host)
  )
}

/** 要不要填密钥：预置里不用的不要，地址填在本机或局域网的（比如自定义地址接本机模型）也不要 */
export function needsKey(preset: ProviderPreset | undefined, baseUrl = ''): boolean {
  return !!preset?.needsKey && !localEndpoint(baseUrl)
}
