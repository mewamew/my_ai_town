import fs from 'node:fs/promises'
import path from 'node:path'
import { createHash } from 'node:crypto'

export async function clientSourceHash(root) {
  const hash = createHash('sha256')
  async function visit(relative) {
    const full = path.join(root, relative)
    let stat
    try {
      stat = await fs.stat(full)
    } catch (error) {
      if (error.code === 'ENOENT') {
        hash.update(relative + ':missing')
        return
      }
      throw error
    }
    if (stat.isDirectory()) {
      for (const name of (await fs.readdir(full)).sort())
        if (!['node_modules', 'dist', '.local'].includes(name))
          await visit(path.join(relative, name))
    } else if (/\.(?:[cm]?js|tsx?|css|html|json)$/.test(relative)) {
      hash.update(relative.split(path.sep).join('/'))
      hash.update(await fs.readFile(full))
    }
  }
  // 手绘预制地图会作为 JSON 分块进入客户端；地图改变也必须重建，避免启动器放行旧布局。
  for (const relative of ['frontend/town-2d', 'frontend/town-shared', 'data/maps'])
    await visit(relative)
  return hash.digest('hex')
}

export async function writeClientBuildState(root, directory) {
  await fs.writeFile(
    path.join(directory, 'build-source.json'),
    JSON.stringify({
      version: 1,
      sourceHash: await clientSourceHash(root),
    }) + '\n'
  )
}

export async function verifyClientBuild(root) {
  const directory = path.join(root, 'frontend/town-2d/dist')
  let state
  try {
    state = JSON.parse(await fs.readFile(path.join(directory, 'build-source.json'), 'utf8'))
    await fs.access(path.join(directory, 'index.html'))
    await fs.access(path.join(directory, 'game.html'))
  } catch {
    throw Error(
      '正式客户端未构建或缺少游戏入口，请在当前工作区执行 corepack pnpm build 后重新启动。'
    )
  }
  if (state.version !== 1 || state.sourceHash !== (await clientSourceHash(root)))
    throw Error('正式客户端构建已过期，请在当前工作区执行 corepack pnpm build，避免运行旧版界面。')
}
