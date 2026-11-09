import * as THREE from 'three'
import { el } from 'town-shared/dom'
import { residentPortrait } from 'town-shared/portraits'
import type {
  GameModeView,
  TideCircle,
  TideFlare,
  TideNews,
  TidePlayer,
  TideView,
} from 'town-shared/protocol'
import { PIXEL } from '../../grid'
import type { MapTheme } from '../../themes/types'
import { SEA_DEPTH_HOOK } from '../sea'
import type { Badge } from '../villagerSigns'
import { VILLAGER_SCALE } from '../villagerSprite'
import type { GameModeLook } from '.'
import { FLARE_BADGE, tideIcon } from './tideIcons'
import './tide.css'

// 潮水圈：圈外的岛沉到水下。
// 地面：圈外的像素不画，露出底下的海。海面按「离新水边多远」重新算水深：圈外原来的地离水边越远越深，
// 原来的海取离新、旧两条岸较远的那个。于是新水边的浅水、透底、浪线、白沫和外海的起伏都按天然海岸那一套画，
// 旧海岸淹到深处就看不出来了；水边里侧一圈湿草。下一圈是一圈白色虚线，地面和海面都画。
// 树、灌木、地标、道具和草丛按脚下的水深往下沉：水线以下不画，贴着水线的一格泛白，水深过了它们的高度就整个没了；
// 投影跟着沉。村民也往下沉，但沉得再深也露出头。
// 全部按地面像素格取整，保持像素风。圆心和半径是行走地图上的米，乘每米的地图单位换成场景坐标。
// 外圈不是海的地图（干海床、冰原）上，圈外露出的是外圈本来的样子，水深不重算。
// 界面（上帝视角）：顶上一排选手头像和还剩几个人，倒下的变灰；右边一列战报（谁对谁动了手、谁倒下了、
// 木箱、信号弹、船），新的在上；分出结果时正中打出谁活着离开。选手、战报、输赢都由内核的潮水插件给。
// 有船票的局（船只认信号弹）：头像一排右边写着信号弹在谁身上，拿着的人头像一圈红边、头顶挂一枚小信号弹。

/** 海面上，圈外原来的地每离水边一个像素，水深算几个像素：小于 1 时新水边的浅水带比天然海岸宽一些 */
const SLOPE = 0.5
/** 立在地上的东西离水边几个像素以外开始下沉，之后每离远一个像素沉多少个像素 */
const SINK_FROM = 2
const SINK_RATE = 0.6
/** 村民最多沉到离脚底多高（人物像素）：一个人 28 像素高，水线压到下巴 */
const WADE_TEXELS = 11
/** 战报列几条 */
const NEWS_SHOWN = 5

/** 信号弹在哪，写在人数条右边：「秦烈」「铁皮匣里」「「椰林」的地上」 */
function flareWhere(flare: TideFlare, players: TidePlayer[]) {
  switch (flare.at) {
    case 'held':
      return players.find((p) => p.id === flare.id)?.name ?? '谁身上'
    case 'case':
      return '铁皮匣里'
    case 'left':
      return flare.place
    case 'gone':
      return '船边'
  }
}

/** 世界分钟写成「第 3 天 14:20」 */
function clock(at: number) {
  const day = Math.floor(at / 1440) + 1
  const m = Math.floor(at % 1440)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `第 ${day} 天 ${pad(Math.floor(m / 60))}:${pad(m % 60)}`
}

const P = PIXEL.toFixed(1)

interface TideUniforms {
  /** 此刻的水边：x、z 圆心，半径，w=1 表示开着 */
  uTideEdge: { value: THREE.Vector4 }
  /** 已公布、还没涨到的下一圈；w=1 时画虚线 */
  uTideNext: { value: THREE.Vector4 }
  uTideFoam: { value: THREE.Color }
}

const HEADER = /* glsl */ `
uniform vec4 uTideEdge;
uniform vec4 uTideNext;
uniform vec3 uTideFoam;
varying vec2 vTidePos;
`

/** 下一圈的虚线：两个像素宽、每 6 个像素一段，按像素格取整 */
const DASHES = /* glsl */ `
  if (uTideNext.w > 0.5 && uTideNext.z > 0.0) {
    vec2 tideCell = floor(vTidePos / ${P});
    vec2 tideP = (tideCell + 0.5) * ${P};
    float dn = (length(tideP - uTideNext.xy) - uTideNext.z) / ${P};
    if (abs(dn) < 1.15) {
      float ang = atan(tideP.y - uTideNext.y, tideP.x - uTideNext.x);
      float seg = floor((ang + 3.14159265) * uTideNext.z / ${P} / 6.0);
      if (mod(seg, 2.0) < 1.0) diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0), 0.88);
    }
  }
`

/** 地面：圈外不画，圈里贴着水边的一圈湿一点 */
const FLOOD = /* glsl */ `
  if (uTideEdge.w > 0.5) {
    vec2 tideCell = floor(vTidePos / ${P});
    float away = (length((tideCell + 0.5) * ${P} - uTideEdge.xy) - uTideEdge.z) / ${P};
    if (away > 0.0) discard;
    if (away > -2.5) diffuseColor.rgb *= 0.74;
  }
`

/** 海面：圈外按离新水边的远近重算水深，接在海面着色器留给玩法的位置（sea.ts 的 SEA_DEPTH_HOOK） */
const SEA_DEPTH = /* glsl */ `
  if (uTideEdge.w > 0.5) {
    vec2 tideP = (cell + 0.5) * uPixel;
    float tideAway = (length(tideP - uTideEdge.xy) - uTideEdge.z) / uPixel;
    if (tideAway > 0.0) {
      // 离岸贴图的 a 通道标出原来的地
      vec2 tideSt = (tideP - uOrigin) / uSize;
      bool tideLand = tideSt.x >= 0.0 && tideSt.y >= 0.0 && tideSt.x <= 1.0 && tideSt.y <= 1.0
        && texture2D(uDepth, tideSt).a > 0.5;
      d = tideLand ? tideAway * ${SLOPE.toFixed(2)} : max(d, tideAway * ${SLOPE.toFixed(2)});
      open = true;
    }
  }
`

/** 地面或海面补上潮水着色 */
function shadeSurface(
  material: THREE.Material,
  uniforms: TideUniforms,
  surface: 'land' | 'sea',
  outerIsSea: boolean
) {
  const before = material.onBeforeCompile.bind(material)
  const beforeKey = material.customProgramCacheKey()
  material.onBeforeCompile = (shader, renderer) => {
    before(shader, renderer)
    Object.assign(shader.uniforms, uniforms)
    shader.vertexShader =
      'varying vec2 vTidePos;\n' +
      shader.vertexShader.replace(
        '#include <begin_vertex>',
        '#include <begin_vertex>\n  vTidePos = (modelMatrix * vec4(transformed, 1.0)).xz;'
      )
    let fragment = shader.fragmentShader
    // 只有海（sea.ts 的 COLOR）留了这个位置；干海床、冰原上不重算水深
    if (surface === 'sea' && outerIsSea) {
      if (fragment.includes(SEA_DEPTH_HOOK)) fragment = fragment.replace(SEA_DEPTH_HOOK, SEA_DEPTH)
      else
        console.error(
          '海面着色器里找不到留给玩法的位置（sea.ts 的 SEA_DEPTH_HOOK），潮水圈外不会画成海'
        )
    }
    shader.fragmentShader =
      HEADER +
      fragment.replace(
        '#include <alphamap_fragment>',
        `${surface === 'land' ? FLOOD : ''}${DASHES}
  #include <alphamap_fragment>`
      )
  }
  material.customProgramCacheKey = () => `${beforeKey}|tide-${surface}`
}

/** 立在地上的东西（立牌或成批的草丛）按脚下的水深往下沉；cap 是最多沉多深（世界单位） */
function sinkStanding(material: THREE.Material, uniforms: TideUniforms, cap: number) {
  const before = material.onBeforeCompile.bind(material)
  const beforeKey = material.customProgramCacheKey()
  const limit = Number.isFinite(cap) ? cap.toFixed(1) : '1e9'
  material.onBeforeCompile = (shader, renderer) => {
    before(shader, renderer)
    Object.assign(shader.uniforms, uniforms)
    shader.vertexShader =
      'uniform vec4 uTideEdge;\nvarying float vTideSink;\nvarying float vTideHeight;\nvarying float vTideFrac;\n' +
      shader.vertexShader.replace(
        '#include <begin_vertex>',
        `#include <begin_vertex>
  {
#ifdef USE_INSTANCING
    vec2 tideFoot = (modelMatrix * instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xz;
#else
    vec2 tideFoot = (modelMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xz;
#endif
    float tideAway = (length((floor(tideFoot / ${P}) + 0.5) * ${P} - uTideEdge.xy) - uTideEdge.z) / ${P};
    vTideSink = uTideEdge.w > 0.5
      ? min(max(tideAway - ${SINK_FROM.toFixed(1)}, 0.0) * ${(PIXEL * SINK_RATE).toFixed(2)}, ${limit})
      : 0.0;
    // 立牌和草丛的模型都是底边在 y=0、往上立；高度和贴图的 v 成正比，片元里两者一比就是整块的高
    vTideHeight = position.y;
    vTideFrac = uv.y;
  }`
      )
    shader.fragmentShader =
      'uniform vec3 uTideFoam;\nvarying float vTideSink;\nvarying float vTideHeight;\nvarying float vTideFrac;\n' +
      shader.fragmentShader.replace(
        '#include <alphamap_fragment>',
        `if (vTideSink > 0.0) {
    // 水线以下不画；只剩顶上两三个像素时整个不画，免得水面上漂着一片片碎顶
    float tideTop = vTideHeight / max(vTideFrac, 0.001);
    if (vTideHeight < vTideSink || vTideSink > tideTop - ${(2.5 * PIXEL).toFixed(1)}) discard;
    if (vTideHeight < vTideSink + ${P}) diffuseColor.rgb = mix(diffuseColor.rgb, uTideFoam, 0.35);
  }
  #include <alphamap_fragment>`
      )
  }
  material.customProgramCacheKey = () => `${beforeKey}|tide-sink-${limit}`
}

export class TideLook implements GameModeLook {
  private readonly uniforms: TideUniforms
  private readonly outerIsSea: boolean
  waterAnywhere = false
  private layer: HTMLElement | null = null
  private view: TideView | null = null
  /** 上次画界面时选手、战报和输赢的样子：水边每拍都在动，这些没变就不重画 */
  private drawn = ''

  constructor(theme: MapTheme) {
    this.outerIsSea = theme.outer === 'sea'
    this.uniforms = {
      uTideEdge: { value: new THREE.Vector4(0, 0, 0, 0) },
      uTideNext: { value: new THREE.Vector4(0, 0, 0, 0) },
      uTideFoam: { value: new THREE.Color(theme.ground.seaSurface?.foam ?? '#ffffff') },
    }
  }

  shadeGround(material: THREE.Material, surface: 'land' | 'sea') {
    shadeSurface(material, this.uniforms, surface, this.outerIsSea)
  }

  shadeStanding(material: THREE.Material, who: 'thing' | 'villager') {
    sinkStanding(
      material,
      this.uniforms,
      who === 'villager' ? WADE_TEXELS * PIXEL * VILLAGER_SCALE : Infinity
    )
  }

  mount(layer: HTMLElement) {
    this.layer = el('div', '', 'tide-hud')
    this.layer.hidden = true
    layer.append(this.layer)
    this.render()
  }

  apply(view: GameModeView | null, metre: number) {
    const tide = view?.kind === 'tide' ? view : null
    const set = (target: THREE.Vector4, c: TideCircle | null | undefined) =>
      c
        ? target.set(c.center[0] * metre, c.center[1] * metre, c.radius * metre, 1)
        : target.set(0, 0, 0, 0)
    set(this.uniforms.uTideEdge.value, tide?.edge)
    set(this.uniforms.uTideNext.value, tide?.next)
    this.waterAnywhere = tide !== null
    this.view = tide
    this.render()
  }

  private render() {
    const root = this.layer
    if (!root) return
    const v = this.view
    const players = v?.players ?? []
    const key = v
      ? JSON.stringify([players, v.news ?? [], v.winner ?? '', v.phase === 'over', v.flare ?? ''])
      : ''
    if (key === this.drawn) return
    this.drawn = key
    root.hidden = !v || players.length === 0
    root.replaceChildren()
    if (!v || !players.length) return
    root.append(this.lineup(v, players))
    const news = v.news ?? []
    if (news.length) root.append(this.feed(news))
    if (v.phase === 'over') root.append(this.ending(v, players))
  }

  /** 顶上：还剩几个人，一排头像，倒下的变灰，上了船的亮金边；有船票的局右边写着信号弹在谁身上，
   *  拿着的人一圈红边 */
  private lineup(v: TideView, players: TidePlayer[]) {
    const box = el('div', '', 'tide-lineup')
    const left = players.filter((p) => !p.fell && p.id !== v.winner).length
    box.append(el('b', v.phase === 'over' ? '结束' : `剩 ${left} 人`))
    const faces = el('div', '', 'tide-faces')
    const flare = v.phase === 'over' ? undefined : v.flare
    for (const p of players) {
      const face = residentPortrait(p.id, p.name)
      face.classList.add('tide-face')
      if (p.fell) face.classList.add('out')
      if (p.id === v.winner) face.classList.add('won')
      if (flare?.at === 'held' && flare.id === p.id) face.classList.add('flare')
      face.title = p.fell ? `${p.name}：${p.fell}` : p.name
      faces.append(face)
    }
    box.append(faces)
    if (flare && flare.at !== 'gone') {
      const where = flareWhere(flare, players)
      const chip = el('span', '', 'tide-flare')
      chip.title = `信号弹在${where}`
      chip.append(tideIcon('flare', 1), el('span', where))
      box.append(chip)
    }
    return box
  }

  /** 拿着信号弹的人头顶挂一枚小信号弹；倒下了也挂着，等人来搜 */
  badges() {
    const out = new Map<string, Badge>()
    const flare = this.view?.flare
    if (flare?.at === 'held' && this.view?.phase !== 'over') out.set(flare.id, FLARE_BADGE)
    return out
  }

  /** 右边：最近几条战报，新的在上 */
  private feed(news: TideNews[]) {
    const box = el('div', '', 'tide-feed')
    for (const n of news.slice(-NEWS_SHOWN).reverse()) {
      const card = el('div', '', `tide-news ${n.kind}`)
      const text = el('div', '', 'tide-news-text')
      text.append(el('span', n.text), el('small', clock(n.at)))
      card.append(tideIcon(n.kind), text)
      box.append(card)
    }
    return box
  }

  /** 正中：谁活着离开了；没人等到船时也说一声 */
  private ending(v: TideView, players: TidePlayer[]) {
    const box = el('div', '', 'tide-ending')
    const winner = players.find((p) => p.id === v.winner)
    const last = [...(v.news ?? [])].reverse().find((n) => n.kind === (winner ? 'boat' : 'fell'))
    box.append(
      tideIcon(winner ? 'boat' : 'fell', 4),
      el('b', winner ? `${winner.name} 活着离开了荒岛` : '没有人等到船')
    )
    if (last) box.append(el('small', last.text))
    return box
  }
}
