import type { ClientMsg, ModelChoice, ServerMsg } from '../protocol'
import type { Receipt, SaveCommand } from '../connection'

// 角色卡「模型」页的「套用到其他村民」：从名册认出其他在世村民，逐个读取他们的 agent_config
// 看用的是哪个模型，套用时逐个发 set_resident_model。

interface Other {
  name: string
  /** undefined 表示还没读到这位村民的 agent_config；null 是还没选模型 */
  binding?: ModelChoice | null
}

const same = (a: ModelChoice | null, b: ModelChoice | null) =>
  a?.provider === b?.provider && a?.model === b?.model

export function trackOtherResidents(selfId: string, send: (msg: ClientMsg) => void) {
  const others = new Map<string, Other>()
  return {
    /** 名册或 agent_config 改变了其他村民的情况时返回 true */
    handleMsg(msg: ServerMsg): boolean {
      if (msg.type === 'roster') {
        const alive = new Map<string, string>()
        for (const member of msg.locales.flatMap((locale) => locale.members))
          if (member.kind === 'resident' && member.id !== selfId && member.body?.life !== 'dead')
            alive.set(member.id, member.name)
        let changed = alive.size !== others.size
        for (const id of others.keys()) if (!alive.has(id)) others.delete(id)
        for (const [id, name] of alive) {
          const known = others.get(id)
          if (!known) {
            others.set(id, { name })
            changed = true
          } else known.name = name
        }
        return changed
      }
      if (msg.type === 'agent_config' && others.has(msg.resident_id)) {
        const other = others.get(msg.resident_id)
        const binding = msg.model_binding ?? null
        if (!other || (other.binding !== undefined && same(other.binding, binding))) return false
        other.binding = binding
        return true
      }
      return false
    },
    /** 读取其他村民的绑定情况：页面显示时全部重读，名册新来的人只读没读过的 */
    refresh(onlyUnknown = false) {
      for (const [id, other] of others)
        if (!onlyUnknown || other.binding === undefined)
          send({ type: 'get_agent_config', resident: id })
    },
    /** 用的模型和 choice 不一样的其他村民，还没选的也算；unbound 标出还没选的 */
    differ(choice: ModelChoice) {
      return [...others].flatMap(([id, other]) =>
        other.binding === undefined || same(other.binding, choice)
          ? []
          : [{ id, name: other.name, unbound: other.binding === null }]
      )
    },
  }
}

/** 逐个保存：等上一位的回执回来再发下一位，结果按名字汇总 */
export function saveInTurn(
  targets: { id: string; name: string }[],
  choice: ModelChoice,
  save: (command: SaveCommand, receipt: Receipt) => void,
  each: (id: string, ok: boolean) => void,
  done: (saved: number, failed: { name: string; message: string }[]) => void
) {
  let saved = 0
  const failed: { name: string; message: string }[] = []
  const next = (index: number) => {
    const target = targets[index]
    if (!target) {
      done(saved, failed)
      return
    }
    save({ type: 'set_resident_model', resident: target.id, model: choice }, (ok, message) => {
      if (ok) saved += 1
      else failed.push({ name: target.name, message })
      each(target.id, ok)
      next(index + 1)
    })
  }
  next(0)
}
