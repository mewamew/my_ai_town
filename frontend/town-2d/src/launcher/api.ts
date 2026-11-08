export class TownApiError extends Error {
  constructor(
    message: string,
    public code?: string,
    public details?: Record<string, unknown>
  ) {
    super(message)
  }
}
/** 请求没送到小镇服务：页面还开着，背后的服务已经停了或正在重启 */
export const SERVICE_UNREACHABLE = 'SERVICE_UNREACHABLE'

/** 连不上时怎么办：应用里的服务跟着应用走，浏览器里的服务要玩家自己重新启动 */
function unreachableMessage() {
  return document.documentElement.dataset.shell
    ? '连不上小镇服务，它可能已经停了，关掉应用重新打开后再试'
    : `连不上小镇服务（${location.host}），它可能已经停了，重新启动小镇服务后再试`
}

export async function api<T>(path: string, body?: unknown, signal?: AbortSignal): Promise<T> {
  let response: Response
  try {
    response = await fetch('/api/towns' + path, {
      method: body === undefined ? 'GET' : 'POST',
      headers:
        body === undefined ? {} : { 'Content-Type': 'application/json', 'X-Town-Client': '1' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal: signal ?? AbortSignal.timeout(120000),
    })
  } catch (error) {
    // 取消和超时原样抛出；连不上时浏览器只给一句「Failed to fetch」，换成能照着做的话
    if (!(error instanceof TypeError)) throw error
    throw new TownApiError(unreachableMessage(), SERVICE_UNREACHABLE)
  }
  const isJson = response.headers.get('content-type')?.includes('application/json') ?? false
  const data: Partial<{ error: string; code: string; details: Record<string, unknown> }> | null =
    isJson ? await response.json() : null
  if (!response.ok)
    throw new TownApiError(
      data?.error ??
        `小镇服务返回 ${response.status}${response.statusText ? ' ' + response.statusText : ''}`,
      data?.code,
      data?.details
    )
  if (!isJson) throw new TownApiError('小镇服务返回了非 JSON 内容')
  return data as T
}
