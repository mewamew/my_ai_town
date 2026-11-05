// 空镇子：世界观设好了、镇上还没有村民时，在地图正中请玩家先请人入住，有人入住就收起。
// 卡片写明推荐谁、为什么（人选固定，见 residents/recommend.ts），一下请进来；想换人就「自己挑」。
// 底下一行写明用哪个模型思考。同一个判断写在 <html data-empty-town> 上，样式据此让「开始」不用主色、
// 暂停提示不出，把醒目给头像条上的「邀请」和手机底部的「居民」——空镇子点开始，时间走了也没人动。
import { button, el } from './dom'
import type { ModelOption } from './models/session'
import { portraitFor, templateKey } from './portraits'
import type { PopulationView, TemplateCard } from './protocol'
import { modelLine } from './residents/modelLine'
import { peopleCount, PICKS, recommended, recommendReason, roomLeft } from './residents/recommend'

export function installEmptyTown(
  map: HTMLElement,
  deps: {
    /** 世界观已经设好（首次对话框和开局向导关着） */
    ready: () => boolean
    create: () => void
    library: () => void
    /** 要村民库列表（回来时调 setLibrary） */
    requestLibrary: () => void
    invite: (ids: string[]) => Promise<void>
    modelOptions: () => ModelOption[]
    joinModel: () => ModelOption | null
    chooseModel: (option: ModelOption) => void
    connectModel: () => void
  }
) {
  /** 还没读到人口时是 null：读到之前不当成空镇子，免得进地图时闪一下 */
  let residents: number | null = null
  /** 还空着几处住宅：一处住一个人，推荐的人数不超过它 */
  let room = Infinity
  let cards: TemplateCard[] | null = null
  let inviting = false
  let requested = false
  const card = el('div', '', 'empty-town')
  card.hidden = true
  // 卡片上的按下不能漏给地图，否则会被当成拖动的起点
  for (const type of ['pointerdown', 'dblclick', 'wheel'])
    card.addEventListener(type, (e) => e.stopPropagation())
  map.append(card)

  function render() {
    const picks = cards ? recommended(cards, Math.min(PICKS.length, room)) : []
    const actions = el('div', '', 'empty-town-actions')
    const body: HTMLElement[] = [
      el('h2', '小镇里还没有村民'),
      el('p', '请几位村民搬进来，他们会按自己的性格过日子。'),
    ]
    if (picks.length) {
      const faces = el('div', '', 'empty-faces')
      for (const c of picks) {
        const url = portraitFor(templateKey(c))
        const face = el(url ? 'img' : 'span', url ? '' : c.name.slice(0, 1), 'empty-face')
        if (face instanceof HTMLImageElement && url) {
          face.src = url
          face.alt = ''
        }
        faces.append(face)
      }
      const words = el('div', '', 'empty-rec-words')
      words.append(
        el('b', `推荐先请：${picks.map((c) => c.name).join('、')}`),
        el('span', `${recommendReason(picks)}人选和人数都能改。`)
      )
      const rec = el('div', '', 'empty-rec')
      rec.append(faces, words)
      body.push(rec)
      const go = button(
        inviting ? '正在请…' : `请他们${peopleCount(picks.length)}住进来`,
        () => {
          inviting = true
          render()
          void deps.invite(picks.map((c) => c.template_id)).finally(() => {
            inviting = false
            render()
          })
        },
        'primary'
      )
      go.disabled = inviting
      actions.append(
        go,
        button('自己挑', () => deps.library())
      )
      body.push(
        actions,
        modelLine({
          options: deps.modelOptions(),
          current: deps.joinModel(),
          choose: (o) => {
            deps.chooseModel(o)
            render()
          },
          connect: deps.connectModel,
        })
      )
    } else {
      // 村民库还没读到，或者库里的人都住进来了：照旧新建或去库里挑
      actions.append(
        button('＋ 新建村民', () => deps.create(), 'primary'),
        button('从村民库挑选', () => deps.library())
      )
      body.push(actions)
    }
    card.replaceChildren(...body)
  }

  function sync() {
    const empty = residents === 0
    document.documentElement.toggleAttribute('data-empty-town', empty)
    const show = empty && deps.ready()
    if (show && !requested) {
      requested = true
      deps.requestLibrary()
    }
    if (show) render()
    card.hidden = !show
  }
  return {
    sync,
    setPopulation(population: PopulationView) {
      // 镇子重新变空（重置了世界）：库里各人的入住状态变了，再要一次
      if (population.residents.length === 0 && residents !== 0) {
        cards = null
        requested = false
      }
      residents = population.residents.length
      room = roomLeft(population)
      sync()
    },
    /** 村民库列表：挑推荐人选 */
    setLibrary(list: TemplateCard[]) {
      cards = list
      if (!card.hidden) render()
    },
    /** 模型配置变了：底下那一行跟着变 */
    refresh() {
      if (!card.hidden) render()
    },
  }
}
