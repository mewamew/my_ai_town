import fs from 'node:fs/promises'
import path from 'node:path'
import os from 'node:os'
import { randomUUID } from 'node:crypto'
import { checkIdentity } from '../mapgen/document.mjs'
export const readJson = async (p) => JSON.parse(await fs.readFile(p, 'utf8'))
const BUILTIN_MAP = 'data/maps/2d-town/map.json'
// 旧 3D 地图仍留在用户目录；列表隐藏，直接打开也拒绝，避免误当 HD-2D 运行。
export function supportsHd2d(document) {
  return (
    !document.renderer &&
    (!document.views?.default || document.views.default === '2d') &&
    (!document.views?.available || document.views.available.every((view) => view === '2d'))
  )
}
export function assertHd2d(document) {
  if (!supportsHd2d(document)) {
    const error = Error('此地图属于已停用的 3D 版本，存档保留，请使用 HD-2D 小镇')
    error.code = 'RETIRED_3D_MAP'
    throw error
  }
}
export async function atomicJson(file, value, mode = 0o600) {
  await fs.mkdir(path.dirname(file), { recursive: true })
  const tmp = file + '.' + randomUUID() + '.tmp'
  const fd = await fs.open(tmp, 'wx', mode)
  try {
    await fd.writeFile(JSON.stringify(value, null, 2) + '\n')
    await fd.sync()
  } finally {
    await fd.close()
  }
  try {
    await fs.rename(tmp, file)
  } catch (e) {
    await fs.rm(tmp, { force: true })
    throw e
  }
}
export function dataRoot() {
  return path.resolve(
    process.env.AI_TOWN_HOME ??
      (process.platform === 'darwin'
        ? path.join(os.homedir(), 'Library/Application Support/MyAiTown')
        : path.join(
            process.env.XDG_DATA_HOME ?? path.join(os.homedir(), '.local/share'),
            'my-ai-town'
          ))
  )
}
/**
 * 一句话建镇时的描述、世界观建议和推荐的居民，和小镇放在一起（creation.json）：换设备、换成 mac 版
 * 打开也还在。逐步设置的小镇没有这个文件。从预制小镇开的一局另记 prefab（预制小镇的编号，见
 * frontend/town-shared/src/prefabs），进镇时按它出开局设置。手机上的管理服务（crates/manager/src/storage.rs）规则相同。
 */
export function townCreation(value) {
  if (value === undefined || value === null) return null
  const invalid = () => Error('建镇说明无效')
  if (typeof value !== 'object' || Array.isArray(value)) throw invalid()
  const text = (v, max) => {
    if (v === undefined || v === null) return ''
    if (typeof v !== 'string' || v.trim().length > max) throw invalid()
    return v.trim()
  }
  const residents = value.residents ?? []
  if (!Array.isArray(residents) || residents.length > 5) throw invalid()
  const prefab = value.prefab ?? null
  if (prefab !== null && (typeof prefab !== 'string' || !/^[a-z0-9][a-z0-9-]{0,39}$/.test(prefab)))
    throw invalid()
  return {
    description: text(value.description, 2000),
    worldview: text(value.worldview, 6000),
    residents: residents.map((r) => {
      const line = text(r, 300)
      if (!line) throw invalid()
      return line
    }),
    ...(prefab ? { prefab } : {}),
  }
}
export function safeId(id) {
  if (typeof id !== 'string' || !/^[a-z0-9][a-z0-9-]{0,90}$/.test(id)) throw Error('小镇编号无效')
  return id
}
export class Storage {
  constructor(root, source) {
    this.root = root
    this.source = source
  }
  town(id) {
    return path.join(this.root, 'towns', safeId(id))
  }
  async init() {
    await fs.mkdir(path.join(this.root, 'towns'), { recursive: true })
    const file = path.join(this.town('default-town'), 'map.json')
    try {
      await fs.access(file)
    } catch {
      const doc = await readJson(path.join(this.source, BUILTIN_MAP))
      checkIdentity(doc)
      await this.create('default-town', doc, { origin: 'builtin' })
    }
  }
  // 目录已存在时：同一张地图视为同一次保存的重试；地图不同或无法读取都报错。
  async existing(id, document) {
    let old
    try {
      old = await this.map(id)
    } catch (e) {
      if (e.code === 'ENOENT') return false
      throw Error(`小镇 ${id} 已存在，但地图数据无法读取：${e.message}`)
    }
    if (old.content_hash !== document.content_hash) throw Error('同一个保存操作对应不同的地图')
    return true
  }
  async create(id, document, receipt, creation = null) {
    assertHd2d(document)
    const dir = this.town(id)
    if (await this.existing(id, document)) return
    const tmp = path.join(this.root, 'towns', '.saving-' + randomUUID())
    await fs.mkdir(tmp)
    try {
      await atomicJson(path.join(tmp, 'map.json'), document)
      await atomicJson(path.join(tmp, 'receipt.json'), receipt)
      if (creation) await atomicJson(path.join(tmp, 'creation.json'), creation)
      await fs.rename(tmp, dir)
    } catch (e) {
      await fs.rm(tmp, { recursive: true, force: true })
      // 两个并发保存同时落盘：先到者已建好目录。
      if ((e.code === 'ENOTEMPTY' || e.code === 'EEXIST') && (await this.existing(id, document)))
        return
      throw e
    }
  }
  canDelete(id) {
    safeId(id)
    return id !== 'default-town'
  }
  async remove(id) {
    if (!this.canDelete(id)) throw Error('内置地图不能删除')
    // 不跟随小镇目录的符号链接，避免删除目录外的数据。
    await this.map(id)
    const dir = this.town(id)
    const stat = await fs.lstat(dir)
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw Error('小镇目录无效')
    await fs.rm(dir, { recursive: true })
  }
  async map(id) {
    const document = await readJson(path.join(this.town(id), 'map.json'))
    checkIdentity(document)
    assertHd2d(document)
    return document
  }
  /** 一句话建镇时记下的说明；没有或读不出时为 null */
  async creation(id) {
    try {
      return townCreation(await readJson(path.join(this.town(id), 'creation.json')))
    } catch {
      return null
    }
  }
  // 内置小镇的名称和简介跟随应用发布的版本。小镇目录里的地图副本不改：它的摘要是存档的身份。
  // 一句话建的小镇，简介写玩家当时那句话。
  async labels(id, document) {
    if (id === 'default-town') {
      const { name, description } = await readJson(path.join(this.source, BUILTIN_MAP))
      return { name, description, creation: null }
    }
    const creation = await this.creation(id)
    return {
      name: document.name,
      description: creation?.description || document.description,
      creation,
    }
  }
  // 小镇列表上的进度：玩到第几天、住了几个人。读存档 world.json，还没开始过的小镇是 null。
  // 手机上的管理服务（crates/manager）按同样的规则算，两边的 /api/towns 保持一致。
  async progress(id) {
    try {
      const save = await readJson(path.join(this.root, 'towns', id, 'world.json'))
      const minutes = save?.world?.minutes
      if (typeof minutes !== 'number') return null
      return {
        day: Math.floor(minutes / 1440) + 1,
        residents: Object.keys(save.population?.residents ?? {}).length,
      }
    } catch {
      return null
    }
  }
  async list() {
    const result = []
    for (const e of await fs.readdir(path.join(this.root, 'towns'), {
      withFileTypes: true,
    })) {
      if (!e.isDirectory() || e.name.startsWith('.')) continue
      try {
        const d = await this.map(e.name)
        const { name, description, creation } = await this.labels(e.name, d)
        result.push({
          id: e.name,
          deletable: this.canDelete(e.name),
          name,
          description,
          creation,
          version: String(d.schema_version),
          views: ['2d'],
          clientKind: 'town-2d',
          available: true,
          mapHash: d.content_hash,
          origin: d.origin,
          progress: await this.progress(e.name),
        })
      } catch (e2) {
        if (e2.code === 'RETIRED_3D_MAP') continue
        result.push({
          id: e.name,
          deletable: this.canDelete(e.name),
          name: e.name,
          description: '地图数据无法读取：' + e2.message,
          available: false,
          clientKind: 'town-2d',
        })
      }
    }
    return result.sort(
      (a, b) =>
        Number(b.id === 'default-town') - Number(a.id === 'default-town') ||
        a.name.localeCompare(b.name, 'zh-CN')
    )
  }
}
export async function setupConfig(root, source) {
  const app = await readJson(path.join(source, 'config/application.json'))
  for (const field of ['providers_path', 'credentials_path']) {
    const dest = path.join(root, 'config', path.basename(app[field]))
    try {
      await fs.access(dest)
    } catch {
      let value = {}
      try {
        value = await readJson(path.join(source, app[field]))
      } catch {}
      await atomicJson(dest, value)
    }
    app[field] = dest
  }
  // 自定义村民模板所有小镇共用一份，放在用户目录下；旧版存在各小镇目录里的由 host 开镇时收进来
  app.custom_library_path = path.join(root, 'resident-library')
  app.prop_catalog_path = path.join(
    source,
    app.prop_catalog_path ?? 'data/props/core/definitions.json'
  )
  app.legacy_prop_catalog_path = path.join(
    source,
    app.legacy_prop_catalog_path ?? 'data/props/compatibility/retired-core-20260925.json'
  )
  app.scene_assets_path = path.join(source, app.scene_assets_path ?? 'data/scene-assets')
  app.compatibility_path = path.join(
    source,
    app.compatibility_path ?? 'data/props/compatibility/physiology-v1.json'
  )
  app.resident_library_path = path.join(
    source,
    app.resident_library_path ?? 'config/resident-library'
  )
  app.topology_path = path.join(source, app.topology_path)
  app.needs_rules_path = path.join(source, app.needs_rules_path ?? 'config/needs_rules.json')
  app.weather_rules_path = path.join(source, app.weather_rules_path ?? 'config/weather_rules.json')
  // 内置模型的推理程序由 scripts/builtin-model/build.mjs 编在工作区里，没编时设定里不出现；
  // 模型文件下载到用户目录，和 mac 版共用一份
  app.builtin_model_path = path.join(source, app.builtin_model_path ?? 'target/builtin-model')
  app.builtin_model_store = path.join(root, 'builtin-model')
  const dest = path.join(root, 'config/application.json')
  await atomicJson(dest, app)
  return dest
}
