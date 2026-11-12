// 本机源码启动入口：只启动服务和选镇页，不打开世界、不改模型配置或存档。
import fs from 'node:fs/promises'
import path from 'node:path'
import net from 'node:net'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { setTimeout as delay } from 'node:timers/promises'
import { verifyClientBuild } from '../client-build-state.mjs'

const source = fileURLToPath(new URL('../../', import.meta.url))
const args = process.argv.slice(2)
const root = path.resolve(args[0] === '--root' && args[1] ? args[1] : source)
const local = path.join(source, '.local')
const logs = path.join(local, 'launcher')
const statusFile = path.join(logs, 'status.json')
const appUrl = 'http://127.0.0.1:5174/'
const modelUrl = 'http://127.0.0.1:11434/'
const samePath = (a, b) =>
  typeof a === 'string' && path.resolve(a).toLowerCase() === path.resolve(b).toLowerCase()

async function readJson(file) {
  return JSON.parse((await fs.readFile(file, 'utf8')).replace(/^\uFEFF/, ''))
}

async function exists(file) {
  try {
    await fs.access(file)
    return true
  } catch {
    return false
  }
}

async function findOllama(config) {
  if (config.ollamaExe) return path.resolve(root, config.ollamaExe)
  const candidates = [
    process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'Programs/Ollama/ollama.exe'),
    ...(process.env.PATH ?? '')
      .split(path.delimiter)
      .filter(Boolean)
      .map((directory) => path.join(directory.replace(/^"|"$/g, ''), 'ollama.exe')),
  ]
  for (const candidate of candidates) if (candidate && (await exists(candidate))) return candidate
  throw Error('找不到已安装的 Ollama。请先安装，或在 .local/windows-launcher.json 设置 ollamaExe。')
}

async function jsonAt(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(1500) })
    return response.ok ? await response.json() : null
  } catch {
    return null
  }
}

async function occupied(port) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: '127.0.0.1', port })
    const finish = (value) => {
      socket.destroy()
      resolve(value)
    }
    socket.setTimeout(1000, () => finish(true))
    socket.once('connect', () => finish(true))
    socket.once('error', () => finish(false))
  })
}

async function waitReady(url, child, name) {
  const deadline = Date.now() + 60000
  while (Date.now() < deadline) {
    const result = await jsonAt(url)
    if (result) return result
    if (child.exitCode !== null || child.signalCode !== null)
      throw Error(`${name}启动后退出，请查看 ${logs} 中对应的日志。`)
    await delay(350)
  }
  throw Error(`${name}启动超时，请查看 ${logs} 中对应的日志。`)
}

async function startServer(executable, arguments_, env, name) {
  const stdout = await fs.open(path.join(logs, `${name}.stdout.log`), 'a')
  const stderr = await fs.open(path.join(logs, `${name}.stderr.log`), 'a')
  try {
    // 独立进程与文件日志让启动窗口退出后服务继续运行，不遗留控制台窗口。
    const child = spawn(executable, arguments_, {
      cwd: root,
      env: { ...process.env, ...env },
      windowsHide: true,
      detached: true,
      stdio: ['ignore', stdout.fd, stderr.fd],
    })
    await new Promise((resolve, reject) => {
      child.once('spawn', resolve)
      child.once('error', reject)
    })
    await fs.writeFile(path.join(logs, `${name}.pid`), String(child.pid))
    child.unref()
    return child
  } finally {
    await Promise.all([stdout.close(), stderr.close()])
  }
}

async function checkManager(health, dataDir) {
  if (health.kind !== 'town-manager' || !samePath(health.source, root))
    throw Error('5174 端口正被另一个程序或项目使用。请关闭该服务后重试；启动器不会强制结束它。')
  let owner
  try {
    owner = await readJson(path.join(dataDir, 'manager.lock/owner.json'))
  } catch {}
  if (owner?.pid !== health.pid || !samePath(owner?.source, root))
    throw Error('已运行的小镇服务使用了不同的存档目录。请先保存并关闭原服务，再重新启动。')
}

async function ensureBuild() {
  try {
    await verifyClientBuild(root)
    return
  } catch {}
  console.log('正在构建最新客户端，首次启动可能需要稍等…')
  const corepack = path.join(
    path.dirname(process.execPath),
    'node_modules/corepack/dist/corepack.js'
  )
  if (!(await exists(corepack)))
    throw Error('客户端需要重新构建，但当前 Node.js 没有 Corepack。请先执行 corepack pnpm build。')
  const child = spawn(process.execPath, [corepack, 'pnpm', 'build'], {
    cwd: root,
    env: {
      ...process.env,
      PATH: `${path.dirname(process.execPath)}${path.delimiter}${process.env.PATH ?? ''}`,
      COREPACK_ENABLE_NETWORK: '0',
    },
    windowsHide: true,
    stdio: ['ignore', 'inherit', 'inherit'],
  })
  const code = await new Promise((resolve, reject) => {
    child.once('error', reject)
    child.once('exit', resolve)
  })
  if (code !== 0)
    throw Error('客户端构建失败，请查看 launcher.log；缺少依赖时先运行 corepack pnpm install。')
  await verifyClientBuild(root)
}

async function main() {
  if (!samePath(root, source)) throw Error('启动器必须放在此项目根目录，不能指向另一个项目。')
  await fs.mkdir(logs, { recursive: true })
  await fs.writeFile(
    statusFile,
    JSON.stringify({ ready: false, started: new Date().toISOString() })
  )
  console.log('正在检查本地运行环境…')
  const major = Number(process.versions.node.split('.')[0])
  const minor = Number(process.versions.node.split('.')[1])
  if (major < 22 || (major === 22 && minor < 18)) throw Error('需要 Node.js 22.18 或更高版本。')
  let config = {}
  try {
    config = await readJson(path.join(local, 'windows-launcher.json'))
  } catch (error) {
    if (error.code !== 'ENOENT')
      throw Error('本机启动配置 .local/windows-launcher.json 不是有效 JSON。')
  }
  const dataDir = path.resolve(root, config.dataDir ?? '.local/run-data')
  const model = config.model ?? 'qwen3.5:2b'
  // 不覆盖系统 Ollama 的模型目录；便携安装可显式指定，已有 OLLAMA_MODELS 也继续生效。
  const modelDir = config.modelDir ? path.resolve(root, config.modelDir) : undefined
  const host = path.join(root, 'target/debug/host.exe')
  const manager = path.join(root, 'target/debug/town-manager.exe')
  if (!(await exists(host)) || !(await exists(manager)))
    throw Error('缺少 host.exe 或 town-manager.exe。请先按 docs/README.md 构建 Rust 内核。')

  let health = await jsonAt(appUrl + 'api/towns/health')
  if (health) await checkManager(health, dataDir)
  else if (await occupied(5174)) throw Error('5174 端口已被占用，但不是可识别的小镇服务。')
  await ensureBuild()

  console.log(`正在检查本地模型 ${model}…`)
  let tags = await jsonAt(modelUrl + 'api/tags')
  let ollama
  if (!tags) {
    if (await occupied(11434)) throw Error('11434 端口已被占用，但不是可识别的 Ollama 服务。')
    const ollamaExe = await findOllama(config)
    if (!(await exists(ollamaExe)) || (modelDir && !(await exists(modelDir))))
      throw Error('找不到 Ollama 或模型目录，请检查 .local/windows-launcher.json 中的路径。')
    console.log('正在启动本地 Ollama…')
    ollama = await startServer(
      ollamaExe,
      ['serve'],
      {
        ...(modelDir ? { OLLAMA_MODELS: modelDir } : {}),
        OLLAMA_HOST: '127.0.0.1:11434',
        OLLAMA_CONTEXT_LENGTH: '32768',
        OLLAMA_NUM_PARALLEL: '1',
        OLLAMA_KEEP_ALIVE: '30m',
        OLLAMA_NO_CLOUD: '1',
        OLLAMA_NOPRUNE: '1',
      },
      'ollama'
    )
    tags = await waitReady(modelUrl + 'api/tags', ollama, 'Ollama')
  } else console.log('本地模型服务已运行，直接复用。')
  if (!Array.isArray(tags.models) || !tags.models.some((entry) => entry.name === model))
    throw Error(`本地服务没有 ${model}。请检查模型目录；启动器不会下载或替换模型。`)

  // 编译或等待模型期间，原有管理服务可能已经退出；再确认一次后决定复用或启动。
  health = await jsonAt(appUrl + 'api/towns/health')
  if (health) await checkManager(health, dataDir)
  else if (await occupied(5174)) throw Error('5174 端口已被占用，但不是可识别的小镇服务。')
  if (!health) {
    console.log('正在启动小镇服务…')
    const server = await startServer(
      process.execPath,
      ['scripts/start-client.mjs', 'preview'],
      { AI_TOWN_HOME: dataDir, TOWN_HOST_BINARY: host },
      'manager'
    )
    health = await waitReady(appUrl + 'api/towns/health', server, '小镇服务')
    await checkManager(health, dataDir)
  } else console.log('小镇服务已运行，直接复用现有存档。')
  const page = await fetch(appUrl, { signal: AbortSignal.timeout(5000) })
  if (!page.ok || !(await page.text()).includes('选择小镇')) throw Error('小镇页面未能正常加载。')
  await fs.writeFile(
    statusFile,
    JSON.stringify(
      {
        ready: true,
        url: appUrl,
        source: root,
        dataDir,
        model,
        managerPid: health.pid,
        checked: new Date().toISOString(),
      },
      null,
      2
    ) + '\n'
  )
  console.log('服务已就绪，正在打开小镇。')
  console.log(`READY ${appUrl}`)
}

main().catch(async (error) => {
  const message = error.message ?? String(error)
  console.error(message)
  await fs.mkdir(logs, { recursive: true }).catch(() => {})
  await fs.writeFile(statusFile, JSON.stringify({ ready: false, error: message })).catch(() => {})
  process.exitCode = 1
})
