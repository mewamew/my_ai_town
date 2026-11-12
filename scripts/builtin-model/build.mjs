// 准备内置模型的推理程序：把固定版本的 llama.cpp 编成单个、不依赖其他库的 llama-server，放进 target/：
//   默认（Mac）：target/builtin-model/，用 Metal；pnpm dev、preview 的管理服务看到它，设定里就有「内置模型」。
//   --android：target/builtin-model-android/，arm64 CPU；scripts/android/build.mjs 看到它就打进 APK。
//   --windows：target/builtin-model-windows/llama-server.exe，用 mingw 交叉编译、x86_64 CPU；
//              scripts/windows/build.mjs 看到它就打进 zip。
// 模型文件不进安装包，游戏自己从发布处下载（crates/host/src/builtin_store.rs）。
// 想在电脑上先试一个还没发布的模型：加 --gguf <模型.gguf>，它会装进用户数据目录，当作今天的「本机测试版」，
// 发布处出了更新的版本才会被换掉。
// 用法：node scripts/builtin-model/build.mjs [--llama <llama.cpp 源码目录>] [--android | --windows] [--gguf <模型.gguf>]
// 没给 --llama 时把 llama.cpp 取到 target/llama.cpp（要联网）；给了就只读那份源码，编译目录在 target/ 下。
// 世界进程按 crates/host/src/builtin.rs 的写法启动它。
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { MIN_API, ndkDir, sdkDir } from '../android/toolchain.mjs'
import { dataRoot } from '../data-root.mjs'
import { MINGW, windowsDlls, windowsSystemDll } from '../windows/dlls.mjs'

const root = fileURLToPath(new URL('../../', import.meta.url))
const args = process.argv.slice(2)
const forAndroid = args.includes('--android')
const forWindows = args.includes('--windows')
const suffix = forAndroid ? '-android' : forWindows ? '-windows' : ''
const out = path.join(root, `target/builtin-model${suffix}`)
const build = path.join(root, `target/llama-build${suffix}`)
const SERVER = forWindows ? 'llama-server.exe' : 'llama-server'
/** 和训练仓库评测量化版时用的同一版 llama.cpp */
const LLAMA_REPO = 'https://github.com/ggml-org/llama.cpp.git'
const LLAMA_COMMIT = '78651c4'
const MIN_MACOS = '13.0'
/** 共同的编译选项：静态链接、不要联网下载模型用的 OpenSSL，只编服务 */
const COMMON = [
  '-DCMAKE_BUILD_TYPE=Release',
  '-DBUILD_SHARED_LIBS=OFF',
  '-DGGML_NATIVE=OFF',
  '-DLLAMA_OPENSSL=OFF',
  '-DLLAMA_BUILD_TESTS=OFF',
  '-DLLAMA_BUILD_EXAMPLES=OFF',
  '-DLLAMA_BUILD_APP=OFF',
  '-DLLAMA_BUILD_SERVER=ON',
]

function run(command, list, extra = {}) {
  console.log(`$ ${command} ${list.join(' ')}`)
  execFileSync(command, list, { stdio: 'inherit', cwd: root, ...extra })
}

function option(name) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}

function llamaSource() {
  const given = option('--llama')
  if (given) return path.resolve(given)
  const dir = path.join(root, 'target/llama.cpp')
  if (!fs.existsSync(path.join(dir, '.git')))
    run('git', ['clone', '--filter=blob:none', LLAMA_REPO, dir])
  run('git', ['-C', dir, 'checkout', '--quiet', LLAMA_COMMIT])
  return dir
}

/** Mac：Metal 着色器编进程序，一个文件就能跑，以后也能直接放进应用包 */
function macFlags() {
  return [
    `-DCMAKE_OSX_DEPLOYMENT_TARGET=${MIN_MACOS}`,
    '-DGGML_METAL=ON',
    '-DGGML_METAL_EMBED_LIBRARY=ON',
  ]
}

/** 手机只用 CPU；dotprod 和 fp16 是近几年 arm64 手机都有的指令 */
function androidFlags(ndk) {
  return [
    `-DCMAKE_TOOLCHAIN_FILE=${path.join(ndk, 'build/cmake/android.toolchain.cmake')}`,
    '-DANDROID_ABI=arm64-v8a',
    `-DANDROID_PLATFORM=android-${MIN_API}`,
    '-DGGML_OPENMP=OFF',
    '-DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16',
  ]
}

/**
 * Windows 没有显卡加速，只用 CPU。交叉编译时 ggml 默认连 AVX 都不开，这里开到 AVX2（2013 年以后的
 * CPU 都有）；C/C++ 运行库和线程库静态链接，一个 exe 就能跑。
 */
function windowsFlags() {
  return [
    '-DCMAKE_SYSTEM_NAME=Windows',
    '-DCMAKE_SYSTEM_PROCESSOR=x86_64',
    `-DCMAKE_C_COMPILER=${MINGW}-gcc`,
    `-DCMAKE_CXX_COMPILER=${MINGW}-g++`,
    `-DCMAKE_RC_COMPILER=${MINGW}-windres`,
    '-DCMAKE_EXE_LINKER_FLAGS=-static',
    '-DGGML_OPENMP=OFF',
    ...['SSE42', 'AVX', 'AVX2', 'FMA', 'F16C', 'BMI2'].map((ins) => `-DGGML_${ins}=ON`),
  ]
}

/** 只能依赖系统自带的库，换台机器、装进应用包都能跑 */
function checkLinkage(server, ndk) {
  const system = forAndroid
    ? (lib) => ['libc.so', 'libm.so', 'libdl.so', 'liblog.so'].includes(lib)
    : forWindows
      ? windowsSystemDll
      : (lib) => lib.startsWith('/usr/lib/') || lib.startsWith('/System/')
  const libs = forAndroid
    ? [
        ...execFileSync(path.join(ndkBin(ndk), 'llvm-readelf'), ['-d', server], {
          encoding: 'utf8',
        }).matchAll(/Shared library: \[(.+?)\]/g),
      ].map((m) => m[1])
    : forWindows
      ? windowsDlls(server)
      : execFileSync('otool', ['-L', server], { encoding: 'utf8' })
          .split('\n')
          .slice(1)
          .map((line) => line.trim().split(' ')[0])
          .filter(Boolean)
  const foreign = libs.filter((lib) => !system(lib))
  if (foreign.length)
    throw Error(`llama-server 还依赖这些库，换台机器跑不了：${foreign.join('、')}`)
}

function ndkBin(ndk) {
  const host = process.platform === 'darwin' ? 'darwin-x86_64' : 'linux-x86_64'
  return path.join(ndk, 'toolchains/llvm/prebuilt', host, 'bin')
}

function buildServer(source) {
  const commit = execFileSync('git', ['-C', source, 'rev-parse', '--short=7', 'HEAD'], {
    encoding: 'utf8',
  }).trim()
  if (commit !== LLAMA_COMMIT)
    console.warn(`注意：llama.cpp 是 ${commit}，评测用的是 ${LLAMA_COMMIT}`)
  const ndk = forAndroid ? ndkDir(sdkDir()) : null
  const flags = forAndroid ? androidFlags(ndk) : forWindows ? windowsFlags() : macFlags()
  run('cmake', ['-S', source, '-B', build, ...COMMON, ...flags])
  run('cmake', ['--build', build, '--config', 'Release', '--target', 'llama-server', '-j'])
  const server = path.join(build, 'bin', SERVER)
  checkLinkage(server, ndk)
  fs.mkdirSync(out, { recursive: true })
  const dest = path.join(out, SERVER)
  if (forAndroid)
    run(path.join(ndkBin(ndk), 'llvm-strip'), ['--strip-unneeded', '-o', dest, server])
  else if (forWindows) run(`${MINGW}-strip`, ['--strip-unneeded', '-o', dest, server])
  else fs.copyFileSync(server, dest)
  fs.chmodSync(dest, 0o755)
}

/** 本机测试版装进用户数据目录，写法和下载装好的一样（installed.json 见 builtin_store.rs） */
function installLocal(gguf) {
  const store = path.join(dataRoot(), 'builtin-model')
  fs.mkdirSync(store, { recursive: true })
  const model = path.join(store, 'model.gguf')
  // APFS 上是写时复制，几百 MB 的模型瞬间就好
  fs.copyFileSync(path.resolve(gguf), model + '.tmp', fs.constants.COPYFILE_FICLONE)
  fs.renameSync(model + '.tmp', model)
  const hash = createHash('sha256').update(fs.readFileSync(model)).digest('hex')
  const date = new Date().toISOString().slice(0, 10)
  const installed = {
    date,
    size: fs.statSync(model).size,
    sha256: hash,
    notes: '本机测试版',
    installed_at: Date.now(),
  }
  fs.writeFileSync(path.join(store, 'installed.json'), JSON.stringify(installed, null, 2))
  for (const name of ['download.json', 'progress.json', 'model.gguf.part'])
    fs.rmSync(path.join(store, name), { force: true })
  console.log(
    `已装进 ${store}（${(installed.size / 1e6).toFixed(0)} MB，当作 ${date} 的本机测试版）`
  )
}

const gguf = option('--gguf')
if (process.platform !== 'darwin') throw Error('这个脚本在 Mac 上运行')
if (forAndroid && forWindows) throw Error('--android 和 --windows 一次只能选一个')
if (gguf && (forAndroid || forWindows || !fs.existsSync(gguf)))
  throw Error('--gguf 只给电脑版用，要指向一个存在的 .gguf 文件')
buildServer(llamaSource())
console.log(
  `推理程序已准备好：${out}（${(fs.statSync(path.join(out, SERVER)).size / 1e6).toFixed(0)} MB）`
)
if (gguf) installLocal(gguf)
console.log(
  forAndroid
    ? '下一步：node scripts/android/build.mjs 打包时会带上它'
    : forWindows
      ? '下一步：node scripts/windows/build.mjs 打包时会带上它'
      : '管理服务要重启才认得出新目录：重新运行 corepack pnpm preview'
)
