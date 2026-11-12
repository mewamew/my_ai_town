// pnpm dev / pnpm preview：起 Rust 管理服务（crates/manager 的 town-manager，安装包里也是它），dev 再起 Vite
// （页面热更新；/api/towns、/data/props 由 vite.config.ts 代理到管理服务），preview 由管理服务直接发构建好的
// 页面（frontend/town-2d/dist）。先 cargo build -p host -p manager。
// 环境变量：AI_TOWN_HOME 数据目录（缺省见 data-root.mjs）；TOWN_MANAGER_PORT 管理服务端口（dev，缺省 8788）；
// TOWN_HOST_BINARY 换一个世界进程（跑长局用 target/release/host）；TOWN_MANAGER_BINARY 换一个管理服务
// （在没编 Rust 的 worktree 里用主仓库编好的）；TOWN_MOCK_LLM=1 世界用固定回复模型。
import { spawn } from 'node:child_process'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'
import { fileURLToPath } from 'node:url'
import { verifyClientBuild } from './client-build-state.mjs'
import { dataRoot } from './data-root.mjs'

const START_TIMEOUT_MS = 20000
const root = fileURLToPath(new URL('../', import.meta.url)),
  mode = process.argv[2] ?? 'dev'
if (!['dev', 'preview'].includes(mode)) throw Error('Expected dev or preview')
// dev：页面在 Vite 的端口，管理服务在 TOWN_MANAGER_PORT；preview：页面和接口都在 --port（缺省 5174）
let port = Number(process.env.TOWN_MANAGER_PORT ?? 8788)
if (mode === 'preview') {
  const args = process.argv.slice(3),
    i = args.indexOf('--port')
  port = i >= 0 ? Number(args[i + 1]) : 5174
}
if (!Number.isInteger(port) || port < 1 || port > 65535) throw Error('应用端口无效')
if (mode === 'preview') await verifyClientBuild(root)
console.log(`[town-client] ${mode} · ${root}`)

const binary = (name) =>
  path.join(root, 'target/debug', name + (process.platform === 'win32' ? '.exe' : ''))
const managerBinary = process.env.TOWN_MANAGER_BINARY ?? binary('town-manager')
const ready = path.join(os.tmpdir(), `town-manager-ready-${process.pid}.json`)
await fs.rm(ready, { force: true })
const manager = spawn(
  managerBinary,
  [
    ...['--root', dataRoot(), '--app', root, '--web', path.join(root, 'frontend/town-2d/dist')],
    ...['--host-bin', process.env.TOWN_HOST_BINARY ?? binary('host')],
    ...['--port', String(port), '--ready-file', ready],
    // 管道一直握在本进程手里：本进程无论怎样退出，管理服务都让各世界保存后退出，不留孤儿进程
    '--stop-on-stdin-close',
    ...(process.env.TOWN_MOCK_LLM === '1' ? ['--mock-llm'] : []),
  ],
  { cwd: root, windowsHide: true, stdio: ['pipe', 'inherit', 'inherit'] }
)
manager.stdin.on('error', () => {})
let managerCode = null
const managerExit = new Promise((resolve) => {
  manager.once('error', (e) => {
    console.error(
      e.code === 'ENOENT'
        ? `[town-client] 找不到 ${managerBinary}，请先 cargo build -p host -p manager`
        : `[town-client] 管理服务没能启动：${e.message}`
    )
    resolve(1)
  })
  manager.once('exit', (code) => resolve(code ?? 1))
}).then((code) => (managerCode = code))

// 等管理服务写就绪文件。它在要的端口被占用时会往后挪，而 Vite 的代理、启动器和页面地址都认这个端口，
// 所以挪了也当启动失败（和以前一样报端口被占用）
const deadline = Date.now() + START_TIMEOUT_MS
let listening
while (managerCode === null && Date.now() < deadline) {
  try {
    listening = JSON.parse(await fs.readFile(ready, 'utf8')).port
    break
  } catch (e) {
    if (e.code !== 'ENOENT') throw e
  }
  await delay(50)
}
await fs.rm(ready, { force: true })
if (listening !== port) {
  // 没起来时原因管理服务自己已经打出来了（比如这个数据目录已有管理服务）
  if (listening) console.error(`[town-client] 端口 ${port} 已被占用，请关闭占用它的程序后重试`)
  else if (managerCode === null) console.error('[town-client] 管理服务启动超时')
  manager.stdin.end()
  await managerExit
  process.exit(1)
}

let client
if (mode === 'dev')
  client = spawn(
    process.execPath,
    [path.join(root, 'frontend/town-2d/node_modules/vite/bin/vite.js'), ...process.argv.slice(3)],
    { cwd: path.join(root, 'frontend/town-2d'), windowsHide: true, stdio: 'inherit' }
  )
let stopping = false
async function stop(code = 0) {
  if (stopping) return
  stopping = true
  client?.kill('SIGTERM')
  // 关上管道，管理服务让各世界保存后退出（终端里按 Ctrl+C 时它自己也收到了信号）
  manager.stdin.end()
  await managerExit
  process.exitCode = code || managerCode
}
client?.once('error', (e) => {
  console.error(e.message)
  void stop(1)
})
client?.once('exit', (code) => {
  void stop(code ?? 0)
})
void managerExit.then((code) => {
  if (stopping) return
  console.error(`[town-client] 管理服务退出了（退出码 ${code}）`)
  void stop(code || 1)
})
// 第一次 Ctrl+C 等各世界保存后退出；第二次本进程直接退出，管理服务在后台照样存完
let asked = false
for (const signal of ['SIGINT', 'SIGTERM'])
  process.on(signal, () => {
    if (asked) process.exit(130)
    asked = true
    void stop()
  })
