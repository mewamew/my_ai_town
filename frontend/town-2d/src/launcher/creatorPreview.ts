import { errorText } from 'town-shared/format'
import { newId } from 'town-shared/ids'
import { createMapRenderer } from '../mapRenderers'
import type { CreatorContext } from './creatorContext'
import { fill, spec } from './creatorForm'
import { SERVICE_UNREACHABLE, TownApiError } from './api'
import { failureMessage, trackProgress } from './creatorProgress'
import { clearReport, renderReport } from './creatorReport'
import { renderStepRows, setCreatorStep, stepStatus, syncStepControls } from './creatorSteps'
import type { Draft, ParseResult } from './creatorTypes'

// 生成预览：参数或一句话描述 → 后端生成草稿 → 画预览。
// revision 的用法见 CreatorContext：每一段 await 回来都先核对它，变了就不再动页面。

export function abort(c: CreatorContext) {
  c.controller?.abort()
  c.controller = undefined
}

export function dropPreview(c: CreatorContext) {
  c.previewMap?.dispose()
  c.previewMap = undefined
}

/** 要求改了：作废进行中的生成和当前草稿，需要重新生成 */
export function invalidate(c: CreatorContext) {
  // 有预览或正在生成才是真的作废了东西；还没生成过时底部仍写这一步的说明
  const stale = !!c.draft || c.busy
  c.revision++
  abort(c)
  c.parsing = false
  c.draft = undefined
  c.el<HTMLButtonElement>('save-town').disabled = true
  if (c.busy) setBusy(c, false)
  c.status(stale ? '要求已修改，请重新生成预览。' : stepStatus(c))
  syncStepControls(c)
}

export function setBusy(c: CreatorContext, value: boolean) {
  c.busy = value
  const noModel = !c.options.model?.available
  c.el<HTMLButtonElement>('generate-town').disabled = value
  c.el<HTMLButtonElement>('parse-town').disabled = value || noModel
  c.el<HTMLButtonElement>('refine-town').disabled = value || noModel
  c.el<HTMLButtonElement>('reparse-town').disabled = value || noModel
  c.el<HTMLButtonElement>('reroll-town').disabled = value
  c.el('cancel-generation').hidden = !value
  c.el('generation-progress').hidden = !value
  // 第一次问到进度之前不写秒数：上限由生成器给，进度条先不定长
  if (value) {
    c.el<HTMLProgressElement>('generation-progress-bar').removeAttribute('value')
    c.el('generation-progress-detail').textContent = ''
  }
  syncStepControls(c)
}

/** 一句话怎么用：从头理解描述，或者在当前这一版上照「还想改什么」改 */
type How = 'layout' | 'parse' | 'refine'

/** 自然语言 → 结构化要求；写回表单，记下给玩家看的说明 */
async function parseDescription(
  c: CreatorContext,
  seed: number,
  configuredSeed: number,
  signal: AbortSignal,
  how: How
) {
  const change = c.el<HTMLTextAreaElement>('refine-text').value.trim()
  // 在当前这一版上改：把这一版的规划和那句话一起交给模型
  const revision =
    how === 'refine'
      ? {
          change,
          previous: {
            spec: spec(c),
            worldview_suggestion: c.worldview,
            residents: c.residents,
          },
        }
      : {}
  c.status(
    how === 'refine'
      ? '正在按你说的改…（本次最多一次模型请求）'
      : '正在理解你的小镇要求…（本次最多一次模型请求）'
  )
  const result = await c.request<ParseResult>(
    '/parse',
    {
      description: c.el<HTMLTextAreaElement>('town-description').value,
      seed,
      request_id: newId(),
      ...revision,
    },
    signal
  )
  fill(c, { ...result.spec, seed: configuredSeed, view_mode: spec(c).view_mode })
  c.parsing = false
  renderStepRows(c)
  c.worldview = result.worldview_suggestion?.trim() ?? ''
  c.mapping = result.mapping ?? []
  c.residents = result.residents ?? []
  c.notes = (result.notes ?? []).map((note) => playerNote(c, note)).filter(Boolean)
  if (how === 'refine') c.el<HTMLTextAreaElement>('refine-text').value = ''
}

/** 模型偶尔还会写出英文种类名和字段名：换成玩家认得的说法 */
const FIELD_WORDS: Record<string, string> = {
  constraints: '位置要求',
  constraint: '位置要求',
  resources: '生活条件',
  environment: '环境',
  preset: '地图风格',
  vegetation: '树丛',
  places: '地点',
  spec: '规划',
}
function playerNote(c: CreatorContext, note: string) {
  return note
    .replace(/\b[a-z][a-z_-]*\b/g, (word) =>
      c.options.templates.some((t) => t.kind === word)
        ? c.nameOf(word)
        : (FIELD_WORDS[word] ?? word)
    )
    .trim()
}

/** 草稿到手：画预览图、列警告与地点，允许保存 */
export async function showDraft<D extends Draft>(c: CreatorContext<D>, result: D, seed: number) {
  const showingRevision = c.revision
  dropPreview(c)
  c.draft = undefined
  c.saveId = newId()
  c.el('creator-preview').replaceChildren()
  c.previewMap = await createMapRenderer(result.document, c.el('creator-preview'))
  if (showingRevision !== c.revision) return
  // 预览是用来查整体路网的：从整图看起，不停在游戏开场的近景
  c.el('creator-preview').querySelector<HTMLButtonElement>('.zoom-readout')?.click()
  c.draft = result
  c.draftSeed = seed
  setCreatorStep(c, 'preview')
  // 名字不影响布局：这里改了，保存时一起交给管理服务
  c.input('draft-name').value = c.input('town-name').value.trim() || result.document.name
  renderReport(c, result)
  c.status(
    `已生成 ${result.document.name}，共 ${result.report.places.length} 处地点。可以缩放检查，保存的就是当前这一版。`
  )
  c.el<HTMLButtonElement>('save-town').disabled = false
}

/** 随机抽一个种子，和上一次抽到的不重复 */
function randomSeed(c: CreatorContext) {
  let seed = crypto.getRandomValues(new Uint32Array(1))[0]
  if (seed === c.lastSeed) seed = (seed + 1) >>> 0
  c.lastSeed = seed
  return seed
}

/** 种子 -1 表示随机抽一个 */
function pickSeed(c: CreatorContext) {
  const configuredSeed = Number(c.input('town-seed').value)
  const seed = configuredSeed === -1 ? randomSeed(c) : configuredSeed
  c.lastSeed = seed
  return { seed, configuredSeed }
}

/** 随机种子时，布局差一点没排开（位置关系、入口通道）就换一张再试，最多这么多张 */
const LAYOUT_ATTEMPTS = 3
const RETRY_CODES = new Set(['LAYOUT_UNRESOLVED', 'ROUTE_UNRESOLVED'])

/** 窄屏上建镇页是一长条：生成完把状态行和预览带进视野，不然成功或失败都看不见 */
function revealResult(c: CreatorContext) {
  if (matchMedia('(max-width: 860px)').matches)
    c.el('creator-status').scrollIntoView({ block: 'start', behavior: 'smooth' })
}

export function placeholder(text: string) {
  const box = document.createElement('div')
  box.className = 'creator-placeholder'
  box.textContent = text
  return box
}

/** 还没生成时预览区的话，按建镇方式写 */
export function idlePlaceholder(c: CreatorContext) {
  return placeholder(
    c.languageMode
      ? '写下想要的小镇，几秒钟就能在这里看到它。'
      : '选好地点后生成，可以拖动、缩放查看小镇。'
  )
}

/** 开始一次生成：清掉上一版预览，显示占位和进度 */
function startGenerating(c: CreatorContext) {
  abort(c)
  c.controller = new AbortController()
  const current = ++c.revision
  c.draft = undefined
  dropPreview(c)
  c.el('creator-preview').replaceChildren(placeholder('正在生成这次的小镇…'))
  clearReport(c)
  c.el<HTMLButtonElement>('save-town').disabled = true
  setBusy(c, true)
  return { signal: c.controller.signal, current }
}

/**
 * 按表单生成一版草稿并显示。parse 先让模型理解描述；refine 在当前这一版上照玩家的话改，
 * 先用当前的布局种子，只改了名字时地图不变。
 */
export async function preview<D extends Draft>(c: CreatorContext<D>, how: How = 'layout') {
  const language = how !== 'layout'
  if (!c.el<HTMLFormElement>('creator-form').reportValidity()) return
  if (language && !c.el<HTMLTextAreaElement>('town-description').value.trim()) {
    c.status('先写一句话描述你想要的小镇，或者点一个例子。')
    c.el('town-description').focus()
    return
  }
  if (!language && !spec(c).places.length) {
    c.status('先点一个地点图标，再抽一张布局。')
    return
  }
  const { seed, configuredSeed } = pickSeed(c)
  const sameLayout = how === 'refine' ? c.draftSeed : undefined
  let parsed = !language
  c.parsing = language
  setCreatorStep(c, 'preview')
  const { signal, current } = startGenerating(c)
  try {
    if (language) {
      await parseDescription(c, seed, configuredSeed, signal, how)
      if (current !== c.revision) return
      parsed = true
    }
    c.status('正在安排活动空间、道具并检查地图…')
    const request = c.request
    let result: D | undefined
    let used = sameLayout ?? seed
    for (let attempt = 1; !result; attempt++) {
      const taskId = newId()
      const stopTracking = trackProgress(c, request, taskId, current, signal)
      try {
        result = await request<D>(
          '/preview',
          { spec: { ...spec(c), seed: used }, request_id: taskId },
          signal
        )
      } catch (error) {
        const retry =
          configuredSeed === -1 &&
          attempt < LAYOUT_ATTEMPTS &&
          !signal.aborted &&
          current === c.revision &&
          error instanceof TownApiError &&
          RETRY_CODES.has(error.code ?? '')
        if (!retry) throw error
        used = randomSeed(c)
        c.status(`这张布局没排开，换一张再试（第 ${attempt + 1} 张）…`)
      } finally {
        stopTracking()
      }
    }
    if (current !== c.revision) return
    await showDraft(c, result, used)
    revealResult(c)
  } catch (error) {
    if (current === c.revision) {
      c.parsing = false
      const message = signal.aborted
        ? '已取消生成。'
        : failureMessage(error, (kind) => c.nameOf(kind))
      // 回到能再生成的一步：模型没理解成功回到描述，布局没排开回到地点；
      // 预览步骤没有草稿，也就没有「换一张布局」
      setCreatorStep(c, parsed ? 'places' : 'basics')
      // 连不上服务时改要求没用，只说原因
      const offline = error instanceof TownApiError && error.code === SERVICE_UNREACHABLE
      c.status(
        signal.aborted
          ? message
          : `没有生成成功：${message}。${offline ? '' : '可以去掉这条要求或调整地点，再生成一次。'}`
      )
      c.el('creator-preview').replaceChildren(placeholder(message))
      revealResult(c)
    }
  } finally {
    if (current === c.revision) setBusy(c, false)
  }
}
