// 拍素材用的无头 Chrome：走真 GPU（mac 上是 Metal），软件渲染跑不动 HD-2D 的整套后期。
// 只用 Chrome 自带的调试协议（CDP），不装别的包。
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

/** Chrome 在哪：CHROME_PATH，或 agent-browser 下载的 Chrome for Testing，或装在应用程序里的 Chrome */
export function chromePath() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH
  const testing = path.join(os.homedir(), '.agent-browser/browsers')
  if (fs.existsSync(testing))
    for (const dir of fs.readdirSync(testing).sort().reverse()) {
      const bin = path.join(
        testing,
        dir,
        'Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'
      )
      if (fs.existsSync(bin)) return bin
    }
  const app = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  if (fs.existsSync(app)) return app
  throw Error('找不到 Chrome：装一个 Google Chrome，或用 CHROME_PATH 指定')
}

/** 起一个无头 Chrome，返回连上第一个页面的 CDP 客户端；close() 关掉浏览器并删掉临时目录 */
export async function launch() {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-town-shoot-'))
  const child = spawn(
    chromePath(),
    [
      '--headless=new',
      '--use-angle=metal',
      '--ignore-gpu-blocklist',
      '--remote-debugging-port=0',
      `--user-data-dir=${profile}`,
      '--no-first-run',
      '--no-default-browser-check',
      '--hide-scrollbars',
      '--mute-audio',
      'about:blank',
    ],
    { stdio: 'ignore' }
  )
  const portFile = path.join(profile, 'DevToolsActivePort')
  for (let i = 0; i < 100 && !fs.existsSync(portFile); i++) await sleep(100)
  const port = fs.readFileSync(portFile, 'utf8').split('\n')[0]
  let page
  for (let i = 0; i < 50 && !page; i++) {
    const list = await fetch(`http://127.0.0.1:${port}/json/list`).then((r) => r.json())
    page = list.find((t) => t.type === 'page')
    if (!page) await sleep(100)
  }
  const client = await connect(page.webSocketDebuggerUrl)
  return {
    ...client,
    async close() {
      client.socket.close()
      child.kill()
      await sleep(300)
      fs.rmSync(profile, { recursive: true, force: true })
    },
  }
}

/** CDP：send 发命令等回复，evaluate 在页面里求值（等 Promise），按 JSON 取回结果 */
async function connect(url) {
  const socket = new WebSocket(url)
  await new Promise((resolve, reject) => {
    socket.onopen = resolve
    socket.onerror = reject
  })
  let id = 0
  const pending = new Map()
  socket.onmessage = (event) => {
    const msg = JSON.parse(event.data)
    const waiter = msg.id && pending.get(msg.id)
    if (!waiter) return
    pending.delete(msg.id)
    if (msg.error) waiter.reject(Error(`${msg.error.message}`))
    else waiter.resolve(msg.result)
  }
  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const i = ++id
      pending.set(i, { resolve, reject })
      socket.send(JSON.stringify({ id: i, method, params }))
    })
  const evaluate = async (expression) => {
    const result = await send('Runtime.evaluate', {
      expression,
      awaitPromise: true,
      returnByValue: true,
    })
    if (result.exceptionDetails)
      throw Error(
        result.exceptionDetails.exception?.description ?? result.exceptionDetails.text ?? '页面出错'
      )
    return result.result.value
  }
  return { socket, send, evaluate }
}

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
