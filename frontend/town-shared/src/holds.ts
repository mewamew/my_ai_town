// 全镇暂停的说法与修法。同一个原因合成一张卡：标题说发生了什么，正文说接下来会怎样，
// 按钮直接去修；服务端的原文收进「详情」。提示卡、时钟牌下的提示和化身操作条共用。
import type { HoldCause, PauseKind, WorldHold } from './protocol'

/** 修复动作：换密钥、换服务、调额度、换模型、重试（清掉暂停接着跑） */
export type HoldFix = 'key' | 'provider' | 'limits' | 'model' | 'retry'

export interface HoldCopy {
  /** 同一原因的分组键：类别、原因、服务 */
  key: string
  /** danger：坏了要修；warn：玩家自己设的限制或慢了 */
  tone: 'danger' | 'warn'
  title: string
  line: string
  /** 时钟牌下的提示和化身操作条上的短说法 */
  short: string
  actions: { label: string; fix: HoldFix }[]
}

export function holdCopy(kind: PauseKind, cause: HoldCause = 'other', provider = ''): HoldCopy {
  const key = `${kind}:${kind === 'fault' ? cause : ''}:${provider}`
  const p = provider || '模型服务'
  const of = provider ? `${provider} 的` : '模型服务的'
  if (kind === 'budget')
    return {
      key,
      tone: 'warn',
      title: 'AI 用量到了你设的上限',
      line: '村民先停下，全镇暂停。调高上限后点「继续」接着跑。',
      short: '用量到上限',
      actions: [
        { label: '调整上限', fix: 'limits' },
        { label: '继续', fix: 'retry' },
      ],
    }
  if (kind === 'stale')
    return {
      key,
      tone: 'warn',
      title: '模型回复太慢，跟不上小镇',
      line: '村民的想法一再赶不上变化，全镇先暂停。可以直接继续，或者换个更快的模型。',
      short: '回复太慢',
      actions: [
        { label: '继续', fix: 'retry' },
        { label: '换模型', fix: 'model' },
      ],
    }
  const fault: Record<HoldCause, Omit<HoldCopy, 'key' | 'tone'>> = {
    auth: {
      title: `${of}密钥用不了了`,
      line: '服务商说这个密钥无效、过期或没有权限。村民先停下，换个密钥就能继续。',
      short: '密钥用不了',
      actions: [
        { label: '换个密钥', fix: 'key' },
        { label: '换一个服务', fix: 'provider' },
      ],
    },
    network: {
      title: `连不上 ${p}`,
      line: '可能是网络断了，或者服务暂时出了问题。检查网络后点「重试」。',
      short: '连不上服务',
      actions: [{ label: '重试', fix: 'retry' }],
    },
    balance: {
      title: `${of}账户余额不足`,
      line: '去服务商那里充值后点「重试」，村民就会接着行动；也可以换一个服务。',
      short: '余额不足',
      actions: [
        { label: '重试', fix: 'retry' },
        { label: '换一个服务', fix: 'provider' },
      ],
    },
    model: {
      title: `${p} 里没有这个模型`,
      line: '模型名可能写错了，或者服务下架了这个模型。到设定里换一个模型。',
      short: '模型名不对',
      actions: [{ label: '换模型', fix: 'model' }],
    },
    rejected: {
      title: `${p} 暂时拒绝了请求`,
      line: '可能是请求太频繁、超出了服务的限额，或者服务暂时出错。稍等一会儿再点「重试」。',
      short: '服务拒绝了请求',
      actions: [
        { label: '重试', fix: 'retry' },
        { label: '换一个服务', fix: 'provider' },
      ],
    },
    reply: {
      title: `${of}回复看不懂`,
      line: '模型接连回了格式不对的内容。可以重试，或者换一个更稳的模型。',
      short: '回复看不懂',
      actions: [
        { label: '重试', fix: 'retry' },
        { label: '换模型', fix: 'model' },
      ],
    },
    context: {
      title: '要记的内容超过了模型的上限',
      line: '删减以后还是太长。换一个能读更长内容的模型，再点「继续」。',
      short: '内容太长',
      actions: [
        { label: '换模型', fix: 'model' },
        { label: '继续', fix: 'retry' },
      ],
    },
    other: {
      title: '村民遇到问题停下了',
      line: '点「继续」让他们接着行动；反复出现的话，看看详情里写了什么。',
      short: '出了问题',
      actions: [{ label: '继续', fix: 'retry' }],
    },
  }
  return { key, tone: 'danger', ...fault[cause] }
}

/** 名册里的暂停按原因分组，每组列出受影响的人 */
export function groupHolds(holds: WorldHold[]) {
  const groups = new Map<string, { copy: HoldCopy; holds: WorldHold[] }>()
  for (const h of holds) {
    const copy = holdCopy(h.kind, h.cause, h.provider)
    const group = groups.get(copy.key) ?? { copy, holds: [] }
    group.holds.push(h)
    groups.set(copy.key, group)
  }
  return [...groups.values()]
}

/** 「阿岚、阿树」；人多时「阿岚、阿树等 5 人」 */
export function namesOf(names: string[]): string {
  return names.length <= 3
    ? names.join('、')
    : `${names.slice(0, 2).join('、')}等 ${names.length} 人`
}
