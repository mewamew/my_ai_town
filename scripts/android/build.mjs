// 打包安卓 APK：构建前端、交叉编译世界进程与管理服务、整理应用自带的数据，再交给 Gradle。
// 用法：node scripts/android/build.mjs [--skip-web] [--skip-rust] [--debug]
// 产物：target/android/ai-town-<版本>.apk。签名密钥第一次打包时生成在 android/（不入库，丢了就不能覆盖安装）。
// 用 scripts/builtin-model/build.mjs --android 编过内置模型的推理程序时一起打进包；模型文件不进包，用到时下载。
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { stageAppBundle } from '../app-bundle.mjs'
import { MIN_API, ndkDir, sdkDir } from './toolchain.mjs'
import { ensureReleaseKeystore } from './signing.mjs'

const root = fileURLToPath(new URL('../../', import.meta.url))
const android = path.join(root, 'android')
const options = new Set(process.argv.slice(2))
const TARGET = 'aarch64-linux-android'
const PORT_NOTE =
  '（页面由应用内的本机服务提供，端口见 android/app/src/main/java/com/aitown/app/TownRuntime.java）'

function run(command, args, extra = {}) {
  console.log(`$ ${command} ${args.join(' ')}`)
  execFileSync(command, args, { stdio: 'inherit', cwd: root, ...extra })
}

function javaHome() {
  const studio = '/Applications/Android Studio.app/Contents/jbr/Contents/Home'
  if (process.env.JAVA_HOME) return process.env.JAVA_HOME
  if (fs.existsSync(studio)) return studio
  throw Error('需要 JDK 17 或更新版本：请设置 JAVA_HOME')
}

function buildRust(ndk) {
  const host = process.platform === 'darwin' ? 'darwin-x86_64' : 'linux-x86_64'
  const bin = path.join(ndk, 'toolchains/llvm/prebuilt', host, 'bin')
  const clang = path.join(bin, `${TARGET}${MIN_API}-clang`)
  const env = {
    ...process.env,
    CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER: clang,
    CC_aarch64_linux_android: clang,
    AR_aarch64_linux_android: path.join(bin, 'llvm-ar'),
  }
  const target = ['--release', '--target', TARGET]
  run('cargo', ['build', '--locked', ...target, '-p', 'host', '--bin', 'host'], { env })
  run('cargo', ['build', '--locked', ...target, '-p', 'manager', '--bin', 'town-manager'], { env })
  // 以 lib*.so 的名字放进 jniLibs：安装时解压到可执行的 nativeLibraryDir
  const libs = path.join(android, 'app/src/main/jniLibs/arm64-v8a')
  fs.rmSync(libs, { recursive: true, force: true })
  fs.mkdirSync(libs, { recursive: true })
  for (const [name, lib] of [
    ['host', 'libtownhost.so'],
    ['town-manager', 'libtownmanager.so'],
  ])
    run(path.join(bin, 'llvm-strip'), [
      '--strip-unneeded',
      '-o',
      path.join(libs, lib),
      path.join(root, 'target', TARGET, 'release', name),
    ])
}

/**
 * 内置模型的推理程序：target/builtin-model-android/llama-server 编好了才带上，以 lib*.so 放进 jniLibs
 * （安装后可执行）。模型文件不进包，游戏用到时下载；起停和题面都由世界进程管，和电脑版一样。
 */
function stageBuiltinModel() {
  const server = path.join(root, 'target/builtin-model-android/llama-server')
  const lib = path.join(android, 'app/src/main/jniLibs/arm64-v8a/libllamaserver.so')
  // 早先的包把模型放在 assets/model/ 里
  fs.rmSync(path.join(android, 'app/src/main/assets/model'), { recursive: true, force: true })
  fs.rmSync(lib, { force: true })
  if (!fs.existsSync(server)) return false
  fs.copyFileSync(server, lib)
  return true
}

/** 应用自带的数据解到私有目录时按 files.txt 逐个取出 */
function stageBundle() {
  const bundle = path.join(android, 'app/src/main/assets/bundle')
  const files = stageAppBundle(bundle)
  fs.writeFileSync(path.join(bundle, 'files.txt'), files.join('\n') + '\n')
  return files.length
}

function main() {
  const sdk = sdkDir()
  const java = javaHome()
  const version = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version
  if (!options.has('--skip-web')) run('corepack', ['pnpm', 'build'])
  if (!options.has('--skip-rust')) buildRust(ndkDir(sdk))
  const count = stageBundle()
  console.log(`数据包：${count} 个文件 ${PORT_NOTE}`)
  console.log(
    stageBuiltinModel()
      ? '已带上内置模型的推理程序'
      : '没有编内置模型的推理程序，这个包不能用内置模型'
  )
  fs.writeFileSync(path.join(android, 'local.properties'), `sdk.dir=${sdk}\n`)
  const debug = options.has('--debug')
  ensureReleaseKeystore({ android, java, debug })
  // 版本号按分钟递增，新包可以直接覆盖安装旧包
  const versionCode = Math.floor(Date.now() / 60000) - 29_000_000
  run(
    path.join(android, 'gradlew'),
    [
      debug ? 'assembleDebug' : 'assembleRelease',
      `-PtownVersionCode=${versionCode}`,
      `-PtownVersionName=${version}`,
    ],
    { cwd: android, env: { ...process.env, JAVA_HOME: java, ANDROID_HOME: sdk } }
  )
  const kind = debug ? 'debug' : 'release'
  const apk = path.join(android, `app/build/outputs/apk/${kind}/app-${kind}.apk`)
  const out = path.join(root, 'target/android', `ai-town-${version}${debug ? '-debug' : ''}.apk`)
  fs.mkdirSync(path.dirname(out), { recursive: true })
  fs.copyFileSync(apk, out)
  const mb = (fs.statSync(out).size / 1048576).toFixed(1)
  console.log(`\nAPK：${path.relative(root, out)}（${mb} MB，版本 ${version} / ${versionCode}）`)
}

main()
