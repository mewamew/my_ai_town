import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'

/** 首次发布打包时生成签名；debug 不创建，已有签名沿用。 */
export function ensureReleaseKeystore(
  { android, java, debug = false },
  { execute = execFileSync, createPassword = () => randomBytes(18).toString('base64url') } = {}
) {
  if (debug) return
  const properties = path.join(android, 'keystore.properties')
  if (fs.existsSync(properties)) return
  const password = createPassword()
  const command = path.join(java, 'bin/keytool')
  const args = [
    '-genkeypair',
    '-keystore',
    path.join(android, 'release.jks'),
    '-alias',
    'aitown',
    '-keyalg',
    'RSA',
    '-keysize',
    '2048',
    '-validity',
    '10000',
    '-storepass:env',
    'AI_TOWN_KEYSTORE_PASSWORD',
    '-keypass:env',
    'AI_TOWN_KEYSTORE_PASSWORD',
    '-dname',
    'CN=AI Town, O=AI Town',
  ]
  console.log('首次发布打包：生成 Android 签名')
  try {
    // JDK 17 的 :env 参数只把变量名放进 argv，口令不进入命令日志或进程参数。
    // 显式捕获两个输出流；execFileSync 的错误也可能包含它们，不能直接重抛或附作 cause。
    execute(command, args, {
      stdio: ['ignore', 'pipe', 'pipe'],
      cwd: path.dirname(android),
      env: { ...process.env, AI_TOWN_KEYSTORE_PASSWORD: password },
    })
  } catch (error) {
    const status = Number.isInteger(error?.status) ? `（退出码 ${error.status}）` : ''
    throw Error(`keytool 生成 Android 发布签名失败${status}，请检查 JDK 和 Android 目录权限`)
  }
  // 唯一持久化口令的位置；不把子进程环境写回 process.env 或交给后续构建命令。
  fs.writeFileSync(
    properties,
    `storeFile=release.jks\nstorePassword=${password}\nkeyAlias=aitown\nkeyPassword=${password}\n`,
    { mode: 0o600 }
  )
}
