// 测试共用：仓库根目录、生成素材、Rust 校验入口、管理服务。不依赖 cwd。
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import fs from 'node:fs/promises'
import path from 'node:path'
import { spawn, spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { generate } from '../mapgen/generate.mjs'
export const root = fileURLToPath(new URL('../../', import.meta.url))
export const read = (relative) => JSON.parse(readFileSync(path.join(root, relative), 'utf8'))
export const library = read('data/mapgen/templates.json')
export const contours = read('data/mapgen/contours.json')
export const definitions = read('data/props/core/definitions.json')
export const gen = (spec, options) => generate(spec, library, contours, definitions, options)
const binary = (name) =>
  path.join(root, 'target/debug', name + (process.platform === 'win32' ? '.exe' : ''))
// 用 Rust 的 town-map validate 校验一份地图，返回子进程结果。
export function townMap(document) {
  return spawnSync(binary('town-map'), ['validate'], {
    input: JSON.stringify(document),
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    timeout: 60000,
  })
}
export function gate(document) {
  const r = townMap(document)
  assert.ifError(r.error)
  assert.equal(r.status, 0, r.stdout + r.stderr)
}
export function rejected(document) {
  const r = townMap(document)
  assert.notEqual(r.status, 0, r.stdout)
  return r.stdout
}

/**
 * 起一个管理服务（crates/manager 的 town-manager，pnpm dev 和安装包里都是它）：数据目录 home，应用数据缺省
 * 是仓库本身（和 pnpm dev 一样），世界用固定回复模型。密钥先放一份空的，不把仓库里的密钥抄进临时目录。
 * api(路径, 请求体) 调 /api/towns 下的接口，没给请求体是 GET；stop() 让它保存各世界后退出，返回退出码。
 */
export async function startManager(
  home,
  { app = root, web = path.join(root, 'frontend/town-2d/dist'), maxRunning = 1 } = {}
) {
  await fs.mkdir(path.join(home, 'config'), { recursive: true })
  await fs
    .writeFile(path.join(home, 'config/credentials.json'), '{}', { flag: 'wx' })
    .catch((e) => {
      if (e.code !== 'EEXIST') throw e
    })
  const ready = path.join(home, 'manager-ready.json')
  await fs.rm(ready, { force: true })
  const child = spawn(
    binary('town-manager'),
    [
      ...['--root', home, '--app', app, '--web', web, '--host-bin', binary('host')],
      ...['--port', '0', '--ready-file', ready, '--max-running', String(maxRunning)],
      '--mock-llm',
      '--stop-on-stdin-close',
    ],
    { stdio: ['pipe', 'pipe', 'pipe'] }
  )
  let output = ''
  for (const stream of [child.stdout, child.stderr]) stream.on('data', (b) => (output += b))
  const exited = new Promise((resolve) => child.once('close', resolve))
  const deadline = Date.now() + 20000
  let port
  while (!port) {
    try {
      port = JSON.parse(await fs.readFile(ready, 'utf8')).port
    } catch (e) {
      if (e.code !== 'ENOENT') throw e
      if (child.exitCode !== null || Date.now() > deadline)
        throw Error(output || '管理服务没有就绪')
      await new Promise((r) => setTimeout(r, 30))
    }
  }
  const origin = `http://127.0.0.1:${port}`
  async function api(route, body) {
    const r = await fetch(`${origin}/api/towns${route}`, {
      method: body === undefined ? 'GET' : 'POST',
      headers:
        body === undefined ? {} : { 'content-type': 'application/json', 'x-town-client': '1' },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
    const data = await r.json()
    if (!r.ok) throw Error(data.error)
    return data
  }
  return {
    origin,
    api,
    output: () => output,
    stop() {
      child.stdin.end()
      return exited
    },
  }
}

/** 和建镇页一样：地图在这边生成，交 /drafts 由管理服务校验成草稿 */
export async function draftTown(manager, spec) {
  const { document } = gen(spec)
  const draft = await manager.api('/drafts', { request_id: 'draft', document })
  return { document, draft }
}

/** 生成一座小镇并保存，返回保存回执（id、mapHash） */
export async function createTown(manager, spec) {
  const { draft } = await draftTown(manager, spec)
  return manager.api('/save', {
    draft_id: draft.id,
    expected_version: draft.version,
    request_id: 'save-' + draft.id,
  })
}

/** 连上世界、可选地发一条命令，等到第一条符合条件的消息就断开 */
export function worldQuery(endpoint, command, predicate, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(endpoint)
    let done = false
    const finish = (error, value) => {
      if (done) return
      done = true
      clearTimeout(timer)
      ws.close()
      error ? reject(error) : resolve(value)
    }
    const timer = setTimeout(() => finish(Error('世界服务没有及时回应')), timeout)
    ws.onopen = () => {
      if (command) ws.send(JSON.stringify(command))
    }
    ws.onerror = () => finish(Error('无法连接世界服务'))
    ws.onmessage = (e) => {
      try {
        const m = JSON.parse(e.data)
        if (predicate(m)) finish(null, m)
      } catch {
        finish(Error('世界返回无效数据'))
      }
    }
    ws.onclose = () => {
      if (!done) finish(Error('世界连接已断开'))
    }
  })
}
