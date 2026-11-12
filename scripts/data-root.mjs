import os from 'node:os'
import path from 'node:path'

/**
 * 电脑上的数据目录：AI_TOWN_HOME，没设时 mac 是 ~/Library/Application Support/MyAiTown（mac 版应用也用它，
 * 两边看到同一批小镇和村民库），其他系统按 XDG 放。pnpm dev / preview 把它交给管理服务，录像和内置模型的
 * 脚本也按它找小镇。
 */
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
