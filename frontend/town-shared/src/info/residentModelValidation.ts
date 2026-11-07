interface ModelChoiceLike {
  provider: string
  model: string
}

interface ProviderLike {
  id: string
  key_mask: string
}

export function residentModelProblem(
  choice: ModelChoiceLike,
  configured: ProviderLike[],
  needsKey: boolean
) {
  if (!choice.provider) return '尚未配置任何模型服务，请先到「模型服务」页配置'
  if (!choice.model.trim()) return '模型名不能为空'
  const conf = configured.find((item) => item.id === choice.provider)
  if (needsKey && !conf?.key_mask) return '这个模型服务还没有密钥，请先完成服务配置'
  return null
}
