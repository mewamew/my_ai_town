import fs from 'node:fs/promises'
import path from 'node:path'
import { createHash } from 'node:crypto'

const BUILD_STATE_VERSION = 2
// 只遍历客户端的源码/素材和明确的构建依赖，不扫整个仓库（尤其是存档与 config/credentials.json）。
// 生成器经 worker、localCreation 和 creatorOptions 打包；budget 还会引入空间清单。
const INPUTS = [
  'frontend/town-2d',
  'frontend/town-shared',
  'frontend/tsconfig.base.json',
  'scripts/mapgen',
  'scripts/replay/reel.mjs',
  'data/maps',
  'data/mapgen',
  'data/props/core/definitions.json',
  'data/scene-assets/pr10-village-v1/manifest.json',
  'config/needs_rules.json',
  'package.json',
  'pnpm-lock.yaml',
  'pnpm-workspace.yaml',
  'scripts/client-build-state.mjs',
]
const IGNORED = new Set([
  'node_modules',
  'dist',
  'dist-ssr',
  '.local',
  '.vite',
  '.vite-temp',
  '.cache',
  '.tmp',
  '.DS_Store',
])

export async function clientSourceHash(root) {
  const hash = createHash('sha256')
  async function visit(relative) {
    const full = path.join(root, relative)
    const key = relative.split(path.sep).join('/')
    let stat
    try {
      stat = await fs.stat(full)
    } catch (error) {
      if (error.code === 'ENOENT') {
        hash.update(`missing\0${key}\0`)
        return
      }
      throw error
    }
    if (stat.isDirectory()) {
      for (const name of (await fs.readdir(full)).sort())
        if (
          !IGNORED.has(name) &&
          !/^\.env(?:\.|$)/.test(name) &&
          !/(?:\.local|\.tmp|\.sw[op]|\.log|\.tsbuildinfo|~)$/.test(name)
        )
          await visit(path.join(relative, name))
    } else if (stat.isFile()) {
      // Vite 的 URL/glob 会打包图片、音频等二进制文件，不能只摘要 JS/JSON 等文本扩展名。
      const bytes = await fs.readFile(full)
      hash.update(`file\0${key}\0${bytes.length}\0`)
      hash.update(bytes)
    }
  }
  for (const relative of INPUTS) await visit(relative)
  return hash.digest('hex')
}

export async function writeClientBuildState(root, directory) {
  await fs.writeFile(
    path.join(directory, 'build-source.json'),
    JSON.stringify({
      version: BUILD_STATE_VERSION,
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
  if (state.version !== BUILD_STATE_VERSION || state.sourceHash !== (await clientSourceHash(root)))
    throw Error('正式客户端构建已过期，请在当前工作区执行 corepack pnpm build，避免运行旧版界面。')
}
