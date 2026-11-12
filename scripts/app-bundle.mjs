// 应用自带的数据与许可，不含密钥。安卓、mac 和 Windows 打包共用。
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../', import.meta.url))

/** 整理到 dest/web（页面）与 dest/app（数据），返回相对 dest 的文件列表（已排序） */
export function stageAppBundle(dest) {
  for (const file of ['LICENSE', 'NOTICE', 'licenses/DEPENDENCIES.txt', 'licenses/ASSETS.txt'])
    if (!fs.existsSync(path.join(root, file))) throw Error(`发布许可文件缺失：${file}`)
  const dist = path.join(root, 'frontend/town-2d/dist')
  if (!fs.existsSync(path.join(dist, 'game.html')))
    throw Error('前端还没有构建：去掉 --skip-web 再试')
  for (const dir of ['web', 'app'])
    fs.rmSync(path.join(dest, dir), { recursive: true, force: true })
  fs.cpSync(dist, path.join(dest, 'web'), {
    recursive: true,
    filter: (src) => path.basename(src) !== 'build-source.json',
  })
  for (const dir of ['data/maps', 'data/props', 'data/scene-assets', 'config/resident-library'])
    fs.cpSync(path.join(root, dir), path.join(dest, 'app', dir), { recursive: true })
  for (const file of [
    'config/needs_rules.json',
    'config/weather_rules.json',
    'config/providers.json',
  ])
    fs.cpSync(path.join(root, file), path.join(dest, 'app', file))
  // 仓库里的配置让 Agent 轨迹记完整题面（开发、复盘用）；安装包不记，玩家要时在设定 → 日志里打开。
  // 内置模型的推理程序在仓库里是 target/builtin-model（scripts/builtin-model/build.mjs 编的），
  // 安装包里在 app/builtin-model，管理服务没读到这一项时就指那里
  const application = JSON.parse(
    fs.readFileSync(path.join(root, 'config/application.json'), 'utf8')
  )
  delete application.trace_full_prompts
  delete application.builtin_model_path
  fs.writeFileSync(
    path.join(dest, 'app/config/application.json'),
    JSON.stringify(application, null, 2) + '\n'
  )
  fs.cpSync(path.join(root, 'licenses'), path.join(dest, 'app/licenses'), { recursive: true })
  for (const file of ['LICENSE', 'NOTICE'])
    fs.copyFileSync(path.join(root, file), path.join(dest, 'app/licenses', file))
  const files = []
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name)
      if (entry.isDirectory()) walk(full)
      else files.push(path.relative(dest, full).split(path.sep).join('/'))
    }
  }
  walk(path.join(dest, 'web'))
  walk(path.join(dest, 'app'))
  if (files.some((f) => f.endsWith('credentials.json'))) throw Error('数据包里不能有密钥文件')
  return files.sort()
}
