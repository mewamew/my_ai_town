// 读录像：crates/host/src/recording.rs 写的那种。一卷是 header.json 加一段段 NNN.jsonl(.gz)，
// 每行 {t, m|k|d}：m 是原样的广播，k 是完整名册，d 是名册跟上一份不同的地方。这里把名册还原成
// 每一份完整的，按 t 的先后交出 {t, msg}。只用纯 JS，浏览器（重演画面）和 Node（拍摄工具）共用；
// 解压由调用方做（浏览器 DecompressionStream，Node zlib）。

/** 录像格式号，和 recording.rs 的 FORMAT 一致；2 在名册变化里把身体单独记（b）；3 的名册里每个人只带
 *  每拍要用的 Agent 状态，不再带整份角色卡细节。1、2 的录像照样读 */
export const FORMAT = 3
/** 读得了的格式号 */
export const FORMATS = [1, 2, 3]

/** 3 以前的录像：名册里每个人带着整份角色卡细节（目标、动作结果、互动、记忆），画面要的两个记号
 *  （最近改过的进行中目标、最近一次被婉拒的邀请）当时由页面从这些列表里现找。这里照当时的找法补成
 *  现在名册的写法，页面只认一种；原来的列表留着不动。3 的名册没有这些列表，原样返回 */
function withAgentMarks(member) {
  const agent = member.resident_agent
  if (!agent || !Array.isArray(agent.goals)) return member
  const goal = agent.goals
    .filter((g) => g.status === 'active')
    .reduce((a, g) => (!a || g.updated_at > a.updated_at ? g : a), undefined)
  const declined = (agent.interactions ?? []).find(
    (i) => i.status === 'declined' && i.participants[0] === member.name
  )
  return {
    ...member,
    resident_agent: {
      ...agent,
      ...(goal && { latest_goal: { id: goal.id, updated_at: goal.updated_at } }),
      ...(declined && { declined_invitation: declined.id }),
    },
  }
}

/** 一段的原文 → 一行行的对象；进程意外退出时最后一行可能没写完，丢掉它 */
export function parseSegment(text) {
  const lines = []
  for (const raw of text.split('\n')) {
    if (!raw) continue
    try {
      lines.push(JSON.parse(raw))
    } catch {
      break
    }
  }
  return lines
}

/** 还原名册：拿着上一份完整名册，接住下一行的完整名册或变化。已经交出去的名册不再改动 */
export function createRosterState() {
  /** 顶层字段（含 type），不含 locales */
  let top = null
  /** 编号 → 这个人 */
  let members = new Map()
  /** [[处所, [编号…]], …] */
  let order = []
  const build = () => ({
    ...top,
    locales: order.map(([locale, ids]) => ({ locale, members: ids.map((id) => members.get(id)) })),
  })
  return {
    /** 完整名册：从头来 */
    key(roster) {
      const { locales = [], ...rest } = roster
      top = rest
      members = new Map()
      order = locales.map(({ locale, members: list }) => {
        for (const member of list) members.set(member.id, withAgentMarks(member))
        return [locale, list.map((m) => m.id)]
      })
      return build()
    },
    /** 变化：s 变了的顶层字段，u 没了的顶层字段，m 按人变了的字段，x 按人没了的字段，o 先后，
     *  b 按人身体里变了的地方（s 变了的项、u 没了的项、h 经历末尾新添的） */
    delta(d) {
      if (!top) throw Error('录像缺少开头的完整名册')
      if (d.s || d.u) {
        top = { ...top, ...d.s }
        for (const key of d.u ?? []) delete top[key]
      }
      members = new Map(members)
      for (const [id, fields] of Object.entries(d.m ?? {})) {
        const member = { ...members.get(id), ...fields }
        members.set(id, fields.resident_agent ? withAgentMarks(member) : member)
      }
      for (const [id, keys] of Object.entries(d.x ?? {})) {
        const member = { ...members.get(id) }
        for (const key of keys) delete member[key]
        members.set(id, member)
      }
      for (const [id, b] of Object.entries(d.b ?? {})) {
        const member = members.get(id)
        const body = { ...member?.body, ...b.s }
        for (const key of b.u ?? []) delete body[key]
        if (b.h) body.history = [...(body.history ?? []), ...b.h]
        members.set(id, { ...member, body })
      }
      if (d.o) {
        order = d.o
        const present = new Set(order.flatMap(([, ids]) => ids))
        for (const id of members.keys()) if (!present.has(id)) members.delete(id)
      }
      return build()
    },
  }
}

/** 一行行 → {t, msg}；名册还原成完整的。state 跨段传下去（每段开头都有完整名册，单独一段也能读） */
export function* messages(lines, state = createRosterState()) {
  for (const line of lines) {
    if (line.m) yield { t: line.t, msg: line.m }
    else if (line.k) yield { t: line.t, msg: state.key(line.k) }
    else if (line.d) yield { t: line.t, msg: state.delta(line.d) }
  }
}

/** 段文件名 → 段号；不是段文件时为 null。同一段既有 .jsonl.gz 又有 .jsonl 时以压好的为准 */
export function segmentIndex(name) {
  const match = /^(\d{3,})\.jsonl(\.gz)?$/.exec(name)
  return match ? Number(match[1]) : null
}

/** 一卷里的段文件，按段号排好；同一段只留一个（压好的优先） */
export function segmentFiles(names) {
  const best = new Map()
  for (const name of names) {
    const index = segmentIndex(name)
    if (index === null) continue
    const packed = name.endsWith('.gz')
    if (!best.has(index) || packed) best.set(index, name)
  }
  return [...best.entries()].sort((a, b) => a[0] - b[0]).map(([, name]) => name)
}
