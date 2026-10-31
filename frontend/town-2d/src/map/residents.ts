import { placeAbove, type LabelRect } from './labelLayout'
import type { At, ResidentRegistration, RosterMember, VerbKind } from 'town-shared/protocol'
import type { ResidentEntry } from 'town-shared/gameMap'
import { agentStopped, isWaiting } from 'town-shared/display'
import { residentOffsets } from './residentLayout'
import { ThoughtBubbles } from './bubbles'
import { el } from 'town-shared/svg'
import { portraitFor, portraitKey, registerPortraits } from 'town-shared/portraits'
import { VILLAGER_HALF, villagerArt, villagerPortrait } from './hd2d/villagerSprite'
import { avatarLookKey } from './hd2d/avatarLooks'
import { standUpright, uprightRatio } from './upright'
import { ResidentGroups, type GroupMember } from './residentGroups'

const conditionLabels = { injury: '受伤', illness: '患病', poison: '中毒' }
/** 动作词前的小图标，让脚下的字一眼看出是「在做的事」；状态（中毒等）不加。停留不显示 */
const VERB_ICONS: Record<VerbKind, string> = {
  goto: '\u279C',
  prop: '\u2692\uFE0E',
  interaction: '\u2726',
  inventory: '\u25C6',
  stay: '',
}

interface Villager {
  g: SVGGElement
  mark: SVGGElement
  portrait: SVGImageElement
  name: SVGTextElement
  verb: SVGTextElement
  wait: SVGTextElement
  labelLine: SVGLineElement
}

export class ResidentLayer {
  readonly layer = el('g')
  private villagers = new Map<string, Villager>()
  /** 居民编号 → 挑头像用的编号，来自最近一份居民登记 */
  private portraitKeys = new Map<string, string>()
  private positions = new Map<string, [number, number]>()
  /** 世界坐标先随相机方位投影，文字和标记再在 SVG 视图坐标里保持直立。 */
  private project: (point: [number, number]) => [number, number] = (point) => point
  /** 同一落脚点几个人分开画之前的位置，也就是真正站的地方 */
  private anchors = new Map<string, [number, number]>()
  /** 多人名单要用的名字、状态和地点，place 时记录 */
  private details = new Map<string, Omit<GroupMember, 'portrait'>>()
  private readonly groups: ResidentGroups
  private selectedId: string | null = null
  /** 标记与文字的缩放，1 = 观察模式大小；化身模式由渲染器按缩放倍率设置 */
  private markerScale = 1
  private lastEntries: ResidentEntry[] | null = null
  /** 纵向拉回比例：地面倾斜时名字、动作离脚底的距离按它放大，屏幕上保持不变 */
  private upright = 1
  /** 立体场景里小人从脚到头顶的高度（地图单位）；名字挂在头顶之上。平面图标没有，名字在头像上方 */
  private bodyHeight: number | undefined
  /**
   * @param metre SVG 单位每米。给了就按三维数据的米制偏移分开同站人物；
   *              没给（纯平面图集）就用固定像素偏移。
   * @param localeName 处所编号 → 中文名，写在多人标签上
   * @param onPick 在多人名单里点了某人
   */
  constructor(
    private position: (locale: string, at: At) => [number, number] | undefined,
    private bubbles: ThoughtBubbles,
    private metre: number | undefined,
    private localeName: (id: string) => string,
    onPick: (id: string) => void
  ) {
    registerPortraits({ url: villagerPortrait, art: villagerArt })
    this.layer.append(outlineFilters())
    this.groups = new ResidentGroups((id) => this.describe(id), onPick)
  }
  private describe(id: string): GroupMember | undefined {
    const detail = this.details.get(id)
    return detail && { ...detail, portrait: portraitFor(this.portraitKeys.get(id) ?? id) }
  }
  /** 点了多人标签 */
  openGroup(key: string, client: [number, number]) {
    this.groups.open(key, client)
  }
  dispose() {
    this.groups.dispose()
  }
  /** 村民当前世界坐标（update 时记录；不在场返回 undefined） */
  getMemberPos(id: string): [number, number] | undefined {
    return this.positions.get(id)
  }
  /** 村民真正站的地方：同一落脚点的几个人在画面上分开画（整图时分得很开，会画到屋外），
   *  走过去找人、判断人在哪间屋里都按这里，不按画出来的位置 */
  getMemberAnchor(id: string): [number, number] | undefined {
    return this.anchors.get(id)
  }

  /** 相机转向时重新布局；世界坐标保留给寻路、遮挡和立体场景。 */
  setProjection(project: (point: [number, number]) => [number, number]) {
    this.project = project
    this.relayout()
  }

  /** 选中高亮（点击空白地图不清除选中，由调用方决定何时传 null） */
  setSelected(id: string | null) {
    const changed = id !== this.selectedId
    this.selectedId = id
    this.bubbles.setSelected(id)
    for (const [vid, v] of this.villagers) v.g.classList.toggle('vsel', vid === id)
    // 选中的人不参与合并：重新分组
    if (changed && this.lastEntries) this.update(this.lastEntries)
  }

  /** 缩放变了：名字的屏幕间距跟着变，重新分组。只在名字不随地图缩放（固定屏幕字号）时才会变 */
  relayout() {
    if (this.lastEntries) this.update(this.lastEntries)
  }

  /** 立体场景的立牌比名册晚一点、匀速走过去：这个人的名字、动作字和标记整组按落后的距离平移，
   *  跟着立牌走，不按名册一跳一跳 */
  follow(id: string, lag: [number, number] | undefined) {
    const v = this.villagers.get(id)
    if (!v) return
    const [dx, dy] = lag ?? [0, 0]
    if (Math.abs(dx) + Math.abs(dy) < 0.01) v.g.removeAttribute('transform')
    else v.g.setAttribute('transform', `translate(${dx.toFixed(2)},${dy.toFixed(2)})`)
  }

  /** 被屋顶盖住的人只留名字和状态，头像藏起来 */
  setCovered(covered: (p: [number, number]) => boolean) {
    for (const [id, v] of this.villagers) {
      const pos = this.positions.get(id)
      v.g.classList.toggle('vcovered', !!pos && covered(pos))
    }
  }

  /** 决定像素小人长相的键：与头像用同一个模板编号，同一模板长一个样 */
  lookOf(id: string) {
    return this.portraitKeys.get(id) ?? id
  }

  /** 居民登记变化：按模板编号换头像，和村民库卡片一致 */
  setPopulation(residents: ResidentRegistration[]) {
    this.portraitKeys = new Map(residents.map((r) => [r.id, portraitKey(r)]))
    for (const [id, v] of this.villagers) this.setPortrait(v.portrait, id)
  }
  private setPortrait(image: SVGImageElement, id: string) {
    const url = portraitFor(this.portraitKeys.get(id) ?? id)
    if (url) image.setAttribute('href', url)
    else image.removeAttribute('href')
  }

  setBodyHeight(height: number | undefined) {
    if (height === this.bodyHeight) return
    this.bodyHeight = height
    if (this.lastEntries) this.update(this.lastEntries)
  }

  /** 名字底边离脚底的距离（SVG 纵向单位）：小人头顶再留约 4 屏幕像素 */
  private nameRise() {
    const sy = this.markerScale * this.upright
    return this.bodyHeight === undefined ? 108 * sy : this.bodyHeight * this.upright + 14 * sy
  }

  /** 缩放变化时按上一份名册重画，暂停或断线时也能立刻生效 */
  setMarkerScale(scale: number) {
    if (scale === this.markerScale) return
    this.markerScale = scale
    if (this.lastEntries) this.update(this.lastEntries)
  }

  private create(member: RosterMember): Villager {
    const g = el('g', { 'data-vid': member.id })
    // 标记以头像底部落在世界坐标：外层 g 管位移，头像本身保持贴纸轮廓。
    const mark = el('g', { class: 'vmark' })
    mark.appendChild(el('circle', { class: 'vring', r: 58 }))
    const portrait = el('image', {
      class: 'vportrait',
      x: -44,
      y: -96,
      width: 88,
      height: 96,
      preserveAspectRatio: 'xMidYMid meet',
      'pointer-events': 'none',
    })
    this.setPortrait(portrait, member.id)
    mark.appendChild(portrait)
    const name = el('text', { class: 'vn' }, member.name)
    const verb = el('text', { class: 'vv' })
    const wait = el('text', { class: 'vwait', display: 'none' }, '…')
    const labelLine = el('line', {
      stroke: '#8f795a',
      'stroke-width': 2,
      'pointer-events': 'none',
      display: 'none',
    })
    g.append(labelLine, mark, name, verb, wait)
    if (this.selectedId === member.id) g.classList.add('vsel')
    this.layer.appendChild(g)
    const v = { g, mark, portrait, name, verb, wait, labelLine }
    this.villagers.set(member.id, v)
    return v
  }

  /** 同一落脚点的人物在屏幕上分开：只是标记偏移，不改变世界位置。 */
  private offsetOf(
    member: RosterMember,
    group: string[],
    spatialOffsets: Map<string, [number, number]> | undefined
  ): [number, number] {
    if (member.kind === 'avatar') return [0, 0]
    if (this.metre) {
      const offset = spatialOffsets?.get(member.id)
      return offset ? [offset[0] * this.metre, offset[1] * this.metre] : [0, 0]
    }
    if (group.length < 2) return [0, 0]
    const s = this.markerScale
    const index = group.indexOf(member.id)
    if (group.length === 2) return [(index === 0 ? -160 : 160) * s, 0]
    const angle = (index * 2 * Math.PI) / group.length
    return [Math.cos(angle) * 140 * s, Math.sin(angle) * 140 * s]
  }

  private place(v: Villager, member: RosterMember, locale: string, worldX: number, worldY: number) {
    this.positions.set(member.id, [worldX, worldY])
    const [x, y] = this.project([worldX, worldY])
    v.name.textContent =
      member.kind === 'avatar' ? `${member.appearance?.marker ?? '我'} ${member.name}` : member.name
    v.g.classList.toggle('vavatar', member.kind === 'avatar')
    if (member.appearance) v.mark.style.setProperty('--avatar-color', member.appearance.color)
    // 化身按所选颜色对应的那套外观画小人和头像
    if (member.kind === 'avatar' && member.appearance) {
      const look = avatarLookKey(member.appearance.color)
      if (this.portraitKeys.get(member.id) !== look) {
        this.portraitKeys.set(member.id, look)
        this.setPortrait(v.portrait, member.id)
      }
    }
    const s = this.markerScale,
      sy = s * this.upright
    v.mark.setAttribute(
      'transform',
      `translate(${x},${y})${s === 1 && sy === 1 ? '' : ` scale(${s},${sy})`}`
    )
    v.name.setAttribute('x', String(x))
    v.name.setAttribute('y', String(y - this.nameRise()))
    v.verb.setAttribute('x', String(x))
    v.verb.setAttribute('y', String(y + 72 * sy))
    const dead = member.body?.life === 'dead'
    const incapacitated = !!member.body && !member.body.can_decide
    v.g.classList.toggle('vdead', dead)
    v.g.classList.toggle('vincapacitated', incapacitated && !dead)
    const conditions = member.body?.conditions.map((c) => conditionLabels[c.kind]).join(' / ')
    const special = dead
      ? member.body?.wound
        ? '遇害'
        : '已死亡'
      : incapacitated
        ? '需要救助'
        : conditions
    const status = special || member.verb
    // 停留不写在名字下面，只在多人名单里写
    v.verb.textContent = special
      ? special
      : member.verb_kind === 'stay'
        ? ''
        : `${VERB_ICONS[member.verb_kind]} ${member.verb}`
    this.details.set(member.id, {
      id: member.id,
      name: member.name,
      status,
      place: this.localeName(locale),
    })
    // 「…」：他在等模型（不占气泡槽，画在名字右侧）
    v.wait.setAttribute('x', String(x + 78 * s))
    v.wait.setAttribute('y', String(y - this.nameRise()))
    for (const text of [v.name, v.verb, v.wait]) standUpright(text, this.upright)
    // 名字旁边：等模型回复时是「…」，Agent 停下要人处理时是「‖」（⏸ 在安卓上会画成橙色表情图标），
    // 还没有能用的模型时写「等模型」
    const stopped = agentStopped(member)
    const noModel = member.resident_agent?.state === 'no_model'
    v.wait.classList.toggle('vnomodel', noModel)
    if (noModel || stopped || isWaiting(member)) {
      v.wait.textContent = noModel ? '等模型' : stopped ? '‖' : '…'
      v.wait.removeAttribute('display')
    } else v.wait.setAttribute('display', 'none')
    if (dead || incapacitated || member.chat) this.bubbles.dropBubble(member.id)
    else this.bubbles.syncThoughtBubble(member, x, y)
  }

  /** Roster → 圆点位置。Transit 只有 {elapsed,total,toward}，位置由本地弧长插值得出。 */
  update(entries: ResidentEntry[]) {
    this.lastEntries = entries
    this.upright = uprightRatio(this.layer)
    const seen = new Set<string>()
    const spatialOffsets = this.metre ? residentOffsets(entries) : undefined
    const atStation = new Map<string, string[]>()
    for (const { locale, member } of entries) {
      if (member.at.kind !== 'station') continue
      const key = `${locale}/${member.at.station}`
      const group = atStation.get(key) ?? []
      group.push(member.id)
      atStation.set(key, group)
    }
    for (const group of atStation.values()) group.sort()
    for (const { locale, member } of entries) {
      seen.add(member.id)
      const v = this.villagers.get(member.id) ?? this.create(member)
      const at = member.at
      if (at.kind === 'offstage') {
        v.g.setAttribute('display', 'none')
        this.positions.delete(member.id)
        this.anchors.delete(member.id)
        this.bubbles.dropBubble(member.id)
        continue
      }
      v.g.removeAttribute('display')
      const pos = this.position(locale, at)
      if (!pos) continue
      const group = at.kind === 'station' ? (atStation.get(`${locale}/${at.station}`) ?? []) : []
      const [dx, dy] = this.offsetOf(member, group, spatialOffsets)
      this.anchors.set(member.id, pos)
      this.place(v, member, locale, pos[0] + dx, pos[1] + dy)
    }
    for (const [id, v] of this.villagers) {
      if (!seen.has(id)) {
        v.g.setAttribute('display', 'none')
        this.bubbles.dropBubble(id)
      }
    }
    const { grouped, occupied } = this.regroup(entries, seen)
    // 名字避让只移动文字，不改变角色的真实位置和交互距离。
    const labels: LabelRect[] = [...occupied]
    const bodies = new Map<string, LabelRect>()
    for (const [id, v] of this.villagers) {
      const worldPos = this.positions.get(id)
      if (!seen.has(id) || !worldPos || v.g.getAttribute('display') === 'none') continue
      const pos = this.project(worldPos)
      const verb = grouped.has(id) ? null : v.verb.getBBox()
      if (verb?.width && verb.height) labels.push(verb)
      const s = this.markerScale
      const sy = s * this.upright
      // 别人的名字要躲开这个人的身体：立体场景里是小人的立牌，平面里是头像标记
      const height = (this.bodyHeight ?? 0) * this.upright
      const body: LabelRect =
        this.bodyHeight === undefined
          ? { x: pos[0] - 48 * s, y: pos[1] - 104 * sy, width: 96 * s, height: 112 * sy }
          : {
              x: pos[0] - VILLAGER_HALF,
              y: pos[1] - height,
              width: VILLAGER_HALF * 2,
              height: height + 8 * sy,
            }
      bodies.set(id, body)
      labels.push(body)
    }
    const screen = this.layer.getScreenCTM()
    const gap = 4 / Math.abs(screen?.a || 1)
    for (const [id, v] of [...this.villagers].sort(([a], [b]) => a.localeCompare(b))) {
      if (!seen.has(id) || v.g.getAttribute('display') === 'none') continue
      if (grouped.has(id)) {
        v.labelLine.setAttribute('display', 'none')
        continue
      }
      const originalY = Number(v.name.getAttribute('y'))
      const initial = v.name.getBBox()
      if (!initial.width || !initial.height) continue
      const box = placeAbove(
        initial,
        labels.filter((r) => r !== bodies.get(id)),
        gap
      )
      v.name.setAttribute('y', String(originalY + box.y - initial.y))
      // 名字旁边的「…」「等模型」跟着名字让开，不留在原处挨着别人的名字
      v.wait.setAttribute('y', v.name.getAttribute('y')!)
      for (const text of [v.name, v.wait]) standUpright(text, this.upright)
      const shifted = Number(v.name.getAttribute('y')) !== originalY
      v.labelLine.setAttribute('display', shifted ? 'inline' : 'none')
      if (shifted) {
        const x = v.name.getAttribute('x')!
        v.labelLine.setAttribute('x1', x)
        v.labelLine.setAttribute('x2', x)
        v.labelLine.setAttribute('y1', String(originalY + 10 * this.markerScale * this.upright))
        v.labelLine.setAttribute('y2', String(box.y + box.height))
      }
      labels.push(box)
    }
    this.bubbles.tickBubbles()
  }

  /** 名字挨得太近的人合成一个多人标签。选中的人、在交谈的人、化身不参与，总是单独显示 */
  private regroup(entries: ResidentEntry[], seen: Set<string>) {
    const alone = new Set(
      entries.filter(({ member: m }) => m.kind === 'avatar' || m.chat).map(({ member: m }) => m.id)
    )
    if (this.selectedId) alone.add(this.selectedId)
    const boxes = []
    for (const [id, v] of this.villagers) {
      if (!seen.has(id) || alone.has(id) || !this.positions.has(id)) continue
      if (v.g.getAttribute('display') === 'none') continue
      const b = v.name.getBBox()
      if (b.width && b.height) boxes.push({ id, x: b.x, y: b.y, width: b.width, height: b.height })
    }
    // 组标签画在所有村民上面；新村民会插在它后面，所以每次检查
    if (this.layer.lastChild !== this.groups.layer) this.layer.append(this.groups.layer)
    const result = this.groups.update(boxes, this.upright)
    for (const [id, v] of this.villagers) v.g.classList.toggle('vgrouped', result.grouped.has(id))
    return result
  }
}

/** 头像沿透明底的轮廓向外描白边，在地图底色上好找；被感知时白边外再加一圈感知色 */
function outlineFilters() {
  const defs = el('defs')
  defs.innerHTML = `
    <filter id="vportrait-outline" x="-30%" y="-30%" width="160%" height="160%">
      <feMorphology in="SourceAlpha" operator="dilate" radius="11" result="grown"/>
      <feFlood flood-color="#fffdf8"/>
      <feComposite in2="grown" operator="in"/>
      <feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#423022" flood-opacity="0.35"/>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    </filter>`
  return defs
}
