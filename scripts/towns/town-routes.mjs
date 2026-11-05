// 小镇列表、地图、开关世界、删除与道具摆放。同一个小镇的写操作按小镇串行。
import { HttpError } from './http.mjs'
import { safeId } from './storage.mjs'
import { positions } from './positions.mjs'

export function createTownRoutes({ source, storage, hosts, serial }) {
  const inTown = (id, fn) => serial('town-' + safeId(id), fn)
  /** 被挤掉的小镇 → 挤掉它的小镇：另一个页面进了别的小镇时，这个页面断线后不自动抢回来 */
  const displaced = new Map()
  /** 正在被页面打开的小镇（关掉旧的、启动新的这段时间里它既不在运行也不在启动，也算占着） */
  const claiming = new Set()
  return [
    [
      'GET',
      /^\/api\/towns\/health$/,
      () => ({ kind: 'town-manager', version: 1, pid: process.pid, source }),
    ],
    [
      'GET',
      /^\/api\/towns$/,
      async () => ({
        towns: (await storage.list()).map((town) => ({
          ...town,
          running: hosts.isRunning(town.id),
        })),
      }),
    ],
    [
      'GET',
      /^\/api\/towns\/([a-z0-9-]+)\/map$/,
      async ({ params: [id], url }) => {
        const document = await storage.map(safeId(id))
        if (url.searchParams.has('hash') && url.searchParams.get('hash') !== document.content_hash)
          throw Error('地图已变化，请返回小镇列表重新打开')
        return document
      },
    ],
    [
      'POST',
      /^\/api\/towns\/([a-z0-9-]+)\/open$/,
      async ({ params: [id], body }) => {
        // 页面断线后自动重开（automatic）：这个小镇是被另一个页面进的小镇挤掉的、那个还开着，
        // 就不抢回来，告诉页面原因，由玩家自己决定回不回来；不然两个页面会来回互相挤
        const by = displaced.get(id)
        if (body?.automatic && by && (hosts.isRunning(by) || claiming.has(by))) {
          const { name } = await storage.labels(by, await storage.map(by))
          throw new HttpError(409, `另一个页面打开了「${name}」，同一时间只能运行一个小镇`)
        }
        claiming.add(id)
        try {
          // 要进的小镇没在运行、同时运行的已经跑满：先保存并关掉最久没人进过的，腾出位置
          while (!hosts.isRunning(id) && hosts.full()) {
            const oldest = hosts.leastRecent(id)
            if (!oldest) break
            displaced.set(oldest, id)
            await inTown(oldest, () => hosts.close(oldest))
          }
          displaced.delete(id)
          return await inTown(id, () => hosts.open(id))
        } finally {
          claiming.delete(id)
        }
      },
    ],
    [
      'POST',
      /^\/api\/towns\/([a-z0-9-]+)\/close$/,
      async ({ params: [id], body }) => {
        // 带着打开凭证来关：之后又有页面打开过这个小镇（比如刷新），旧页面晚到的关闭不算数
        const closed = await inTown(id, async () => {
          if (body?.lease && hosts.isRunning(id) && !hosts.holds(id, body.lease)) return false
          await hosts.close(id)
          return true
        })
        return { ok: true, closed }
      },
    ],
    [
      'POST',
      /^\/api\/towns\/([a-z0-9-]+)\/delete$/,
      ({ params: [id] }) =>
        inTown(id, async () => {
          if (!storage.canDelete(id)) throw new HttpError(403, '内置地图不能删除')
          await hosts.close(id)
          await storage.remove(id)
          return { ok: true }
        }),
    ],
    [
      'POST',
      /^\/api\/towns\/([a-z0-9-]+)\/reset$/,
      ({ params: [id] }) =>
        inTown(id, async () => {
          if (!id.startsWith('prefab-')) throw new HttpError(403, '只有预制小镇能重新开始')
          await hosts.close(id)
          await storage.remove(id, true)
          return { ok: true }
        }),
    ],
    [
      'POST',
      /^\/api\/towns\/([a-z0-9-]+)\/positions$/,
      ({ params: [id], body }) =>
        inTown(id, async () => {
          const document = await storage.map(id)
          if (document.content_hash !== body.map_hash) throw Error('地图版本不匹配')
          return { positions: await positions(storage, id, document, body.instances) }
        }),
    ],
  ]
}
