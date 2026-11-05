// HD-2D 建镇：自然语言解析、预览、保存与进度，草稿只存于内存。
import fs from 'node:fs/promises'
import path from 'node:path'
import { randomUUID } from 'node:crypto'
import { worker } from './workers.mjs'
import { HttpError } from './http.mjs'
import { safeId, townCreation } from './storage.mjs'
import { runGeneration } from '../mapgen/worker.mjs'
import { validateSpec, limits, resources, MAX_SEED } from '../mapgen/spec.mjs'
import { plannerKinds, tidyPlan } from '../mapgen/plan.mjs'
import { hashDocument, seal } from '../mapgen/document.mjs'
import { APPEARANCE_SET, GenerationError, PARAMETERS } from '../mapgen/budget.mjs'

// 同时进行的解析与预览最多两个。
const MAX_GENERATION_TASKS = 2
// 预览草稿只放内存：最多 24 条，每条两小时后过期，服务重启即清空。
const DRAFT_LIMIT = 24
const DRAFT_TTL_MS = 2 * 60 * 60 * 1000
// 生成结束后进度再保留 30 秒，供前端最后一次查询。
const TASK_RETENTION_MS = 30000
const MAX_REQUEST_ID = 120
const RUST_VALIDATE_TIMEOUT_MS = 10000
export class DraftStore {
  #entries = new Map()
  /** 同一份草稿按操作编号读取。 */
  put(keys, draft) {
    const entry = { draft, expiresAt: Date.now() + DRAFT_TTL_MS }
    for (const key of keys) {
      this.#entries.delete(key)
      this.#entries.set(key, entry)
    }
    while (this.#entries.size > DRAFT_LIMIT) this.#entries.delete(this.#entries.keys().next().value)
  }
  get(key) {
    const entry = this.#entries.get(key)
    if (entry && Date.now() > entry.expiresAt) this.#entries.delete(key)
    else return entry
  }
}

export class GenerationTasks {
  #tasks = new Map()
  /** 登记一次生成；操作编号缺省时自动分配，格式不对或重复都拒绝。 */
  begin(requestId) {
    if (typeof requestId !== 'string' || !/^[a-zA-Z0-9-]{1,120}$/.test(requestId))
      throw Error('生成操作编号无效')
    if (this.#tasks.has(requestId)) throw Error('生成操作编号重复')
    this.update(requestId, {})
    return requestId
  }
  update(id, update) {
    const current = this.#tasks.get(id) ?? {
      stage: 'pending',
      started_at: Date.now(),
      limit_ms: null,
    }
    this.#tasks.set(id, {
      ...current,
      ...(typeof update === 'string' ? { stage: update } : update),
    })
  }
  finish(id, update) {
    this.update(id, update)
    setTimeout(() => this.#tasks.delete(id), TASK_RETENTION_MS).unref()
  }
  /** 进度：阶段、已用时间和生成器的计算上限 */
  stage(id) {
    const task = this.#tasks.get(id)
    return {
      stage: task?.stage ?? 'pending',
      elapsed_ms: task ? Date.now() - task.started_at : 0,
      limit_ms: PARAMETERS.max_ms,
    }
  }
}

/**
 * 预览后改的名字：只换名字、重算摘要，布局不变，不用重新生成。手机上的管理服务
 * （crates/manager/src/creation.rs）按同样的规则改名，两边保存出的地图一致。
 */
export function renamed(document, name) {
  if (name === undefined || name === null) return document
  if (typeof name !== 'string' || !name.trim() || name.trim().length > 60)
    throw Error('名称须为 1–60 个字符')
  if (name.trim() === document.name) return document
  const copy = structuredClone(document)
  copy.name = name.trim()
  if (copy.generation?.spec) {
    copy.generation.spec.name = copy.name
    copy.generation.input_hash = hashDocument(copy.generation.spec)
  }
  return seal(copy)
}

export function createCreation({
  source,
  root,
  config,
  storage,
  library,
  contours,
  definitions,
  serial,
}) {
  const drafts = new DraftStore(),
    tasks = new GenerationTasks()
  let running = 0
  async function admit(fn) {
    if (running >= MAX_GENERATION_TASKS)
      throw new HttpError(409, `已有 ${MAX_GENERATION_TASKS} 个生成任务，请稍后再试`)
    running++
    try {
      return await fn()
    } finally {
      running--
    }
  }
  const validate = (document, signal, timeout) =>
    worker(source, config, 'validate', document, { signal, ...(timeout ? { timeout } : {}) })

  async function modelStatus() {
    try {
      return await worker(source, config, 'options', {}, { timeout: 5000 })
    } catch (e) {
      return { available: false, error: e.message }
    }
  }
  async function options() {
    return {
      templates: library.templates.map(({ kind, name, outdoor }) => ({ kind, name, outdoor })),
      limits,
      resources,
      styles: [{ id: APPEARANCE_SET, name: '海岸乡镇' }],
      model: await modelStatus(),
      uncompleted_drafts: '草稿保留两小时；重新打开创建页时需重新预览，已保存小镇不受影响',
    }
  }

  // 自然语言 → 结构化要求。每次调用记一行到数据目录的 map-generation-calls.jsonl。
  const parse = (body, signal) =>
    admit(async () => {
      if (!Number.isInteger(body.seed) || body.seed < 0 || body.seed > MAX_SEED)
        throw Error('随机种子无效')
      const started = Date.now()
      let result,
        accepted = false
      try {
        // 模型只能用建镇页卡片上有的地点，地点表由生成器这边给
        const request = { ...body, templates: plannerKinds(library.templates) }
        result = tidyPlan(
          await worker(source, config, 'parse', request, { signal }),
          library.templates,
          body.seed
        )
        accepted = true
      } finally {
        await fs.appendFile(
          path.join(root, 'map-generation-calls.jsonl'),
          JSON.stringify({
            at: new Date().toISOString(),
            request_id: body.request_id,
            elapsed_ms: Date.now() - started,
            ok: accepted,
            attempts: 1,
            calls: result?.calls ?? null,
          }) + '\n'
        )
      }
      return result
    })

  async function preview2d(body, signal) {
    const taskId = tasks.begin(body.request_id ?? randomUUID()),
      stage = (s) => tasks.update(taskId, { stage: s })
    stage('districts')
    let result
    try {
      try {
        validateSpec(body.spec, library.templates)
      } catch (e) {
        throw new GenerationError('INVALID_SPEC', e.message, { stage: 'input' })
      }
      result = await runGeneration(body.spec, library, contours, definitions, {
        signal,
        onStage: stage,
      })
      // 最终几何由 Rust 校验，错误信息原样返回。
      stage('runtime_validation')
      await validate(result.document, signal, RUST_VALIDATE_TIMEOUT_MS)
      tasks.finish(taskId, { stage: 'complete' })
    } catch (e) {
      tasks.finish(taskId, { stage: 'failed' })
      throw e
    }
    if (signal.aborted) throw Error('生成已取消')
    const draft = {
      id: 'draft-' + randomUUID(),
      version: result.document.content_hash,
      expires_at: Date.now() + DRAFT_TTL_MS,
      ...result,
    }
    drafts.put([draft.id], draft)
    return draft
  }

  const preview = (body, signal) => admit(() => preview2d(body, signal))

  async function save(body) {
    const draftId = safeId(body.draft_id)
    if (typeof body.request_id !== 'string' || body.request_id.length > MAX_REQUEST_ID)
      throw Error('保存操作编号无效')
    const entry = drafts.get(draftId)
    if (!entry) throw Error('预览草稿不存在或已过期，请重新生成')
    const { draft } = entry
    if (draft.version !== body.expected_version) throw Error('预览版本已变化，请重新预览')
    const document = renamed(draft.document, body.name)
    const creation = townCreation(body.creation)
    // 预制小镇存成固定编号 prefab-<编号>，列表里当内置小镇
    const townId =
      body.town_id == null ? draftId.replace('draft-', 'town-') : prefabTownId(body.town_id)
    return serial('town-' + townId, async () => {
      await storage.create(
        townId,
        document,
        { request_id: body.request_id, draft_id: draftId, map_hash: document.content_hash },
        creation
      )
      return { id: townId, mapHash: document.content_hash }
    })
  }

  const routes = [
    ['GET', /^\/api\/towns\/options$/, options],
    ['POST', /^\/api\/towns\/parse$/, ({ body, signal }) => parse(body, signal)],
    ['POST', /^\/api\/towns\/preview$/, ({ body, signal }) => preview(body, signal)],
    ['POST', /^\/api\/towns\/save$/, ({ body }) => save(body)],
    [
      'GET',
      /^\/api\/towns\/generation\/([a-zA-Z0-9-]{1,120})$/,
      ({ params: [id] }) => tasks.stage(id),
    ],
  ]
  return { routes }
}

function prefabTownId(id) {
  if (typeof id !== 'string' || !/^prefab-[a-z0-9][a-z0-9-]{0,60}$/.test(id))
    throw Error('预制小镇编号无效')
  return id
}
