// 打包 mac 版：构建前端与 Rust（世界进程、管理服务），编译 Swift 应用壳（macos/），组装 .app，
// 用钥匙串里的 Developer ID 证书签名，做成 DMG；给了公证档案就提交公证并把票据钉进 DMG。
// 用 scripts/builtin-model/build.mjs 编过内置模型的推理程序时一起打进包；模型文件不进包，用到时下载。
// 用法：node scripts/macos/build.mjs [--skip-web] [--skip-rust] [--no-sign] [--notary-profile <档案名>]
// 产物：target/macos/AI小镇.app 与 target/macos/ai-town-<版本>.dmg（只支持 Apple 芯片）。
// 有多张 Developer ID 证书时用 AI_TOWN_SIGN_IDENTITY 指定。公证：设好 AI_TOWN_APPLE_ID 与 AI_TOWN_APPLE_PASSWORD（App 专用密码）
// 即可，每次打包前脚本自己存进钥匙串档案 ai-town-notary（可用 --notary-profile 或 AI_TOWN_NOTARY_PROFILE 改名），Team ID 取自签名证书。
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { stageAppBundle } from '../app-bundle.mjs'
import { makeIcon } from './icon.mjs'

const root = fileURLToPath(new URL('../../', import.meta.url))
const out = path.join(root, 'target/macos')
const work = path.join(out, 'work')
const args = process.argv.slice(2)
const APP_NAME = 'AI小镇'
const BUNDLE_ID = 'com.aitown.app'
const MIN_MACOS = '13.0'
/** 包里的两个命令行程序：Rust 产物名 → 包里的名字（TownRuntime.swift 按这个名字找） */
const BINARIES = [
  ['host', 'town-host'],
  ['town-manager', 'town-manager'],
]
/** 内置模型的推理程序在包里的名字 */
const LLAMA_SERVER = 'llama-server'

function run(command, list, extra = {}) {
  console.log(`$ ${command} ${list.join(' ')}`)
  execFileSync(command, list, { stdio: 'inherit', cwd: root, ...extra })
}

function option(name) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}

/** 用证书的指纹签名，名字相同的证书不会认错 */
function signIdentity() {
  const named = process.env.AI_TOWN_SIGN_IDENTITY
  if (named) return { id: named, name: named }
  const listed = execFileSync('security', ['find-identity', '-v', '-p', 'codesigning'], {
    encoding: 'utf8',
  })
  const found = [...listed.matchAll(/\b([0-9A-F]{40}) "(Developer ID Application: [^"]+)"/g)]
  if (!found.length)
    throw Error('钥匙串里没有 Developer ID Application 证书；只在本机试用可以加 --no-sign')
  if (found.length > 1)
    throw Error('有多张 Developer ID Application 证书，请用 AI_TOWN_SIGN_IDENTITY 指定其中一张')
  return { id: found[0][1], name: found[0][2] }
}

function buildRust() {
  const env = { ...process.env, MACOSX_DEPLOYMENT_TARGET: MIN_MACOS }
  run('cargo', ['build', '--locked', '--release', '-p', 'host', '--bin', 'host'], { env })
  run('cargo', ['build', '--locked', '--release', '-p', 'manager', '--bin', 'town-manager'], {
    env,
  })
}

function infoPlist(file, version, build) {
  const json = path.join(work, 'Info.json')
  fs.writeFileSync(
    json,
    JSON.stringify({
      CFBundleDevelopmentRegion: 'zh_CN',
      CFBundleDisplayName: APP_NAME,
      CFBundleExecutable: 'AITown',
      CFBundleIconFile: 'AppIcon',
      CFBundleIdentifier: BUNDLE_ID,
      CFBundleInfoDictionaryVersion: '6.0',
      CFBundleName: APP_NAME,
      CFBundlePackageType: 'APPL',
      CFBundleShortVersionString: version,
      CFBundleVersion: String(build),
      LSApplicationCategoryType: 'public.app-category.simulation-games',
      LSMinimumSystemVersion: MIN_MACOS,
      NSHighResolutionCapable: true,
      NSPrincipalClass: 'NSApplication',
      // 页面和世界都在 127.0.0.1 上，走 http 与 ws
      NSAppTransportSecurity: { NSAllowsLocalNetworking: true },
    })
  )
  run('plutil', ['-convert', 'xml1', json, '-o', file])
}

/**
 * 内置模型的推理程序：target/builtin-model/llama-server 编好了才带上。它是可执行文件，放进 Contents/MacOS
 * 和别的程序一起签名；自带数据的 app/builtin-model/ 里放一个指向它的软链接——管理服务把这个目录告诉世界进程，
 * 和电脑版、安卓版的目录一样。模型文件不进包，下载到和电脑版共用的数据目录。
 */
function stageBuiltinModel(bin, resources) {
  const source = path.join(root, 'target/builtin-model', LLAMA_SERVER)
  if (!fs.existsSync(source)) return false
  const server = path.join(bin, LLAMA_SERVER)
  fs.copyFileSync(source, server)
  fs.chmodSync(server, 0o755)
  run('strip', ['-x', server])
  const dir = path.join(resources, 'app/builtin-model')
  fs.mkdirSync(dir, { recursive: true })
  fs.symlinkSync(path.join('../../../MacOS', LLAMA_SERVER), path.join(dir, LLAMA_SERVER))
  return true
}

/** AI小镇.app：Contents/MacOS 放应用壳与命令行程序，Contents/Resources 放页面、数据和图标 */
function assemble(version, build) {
  const app = path.join(out, `${APP_NAME}.app`)
  fs.rmSync(app, { recursive: true, force: true })
  const contents = path.join(app, 'Contents')
  const bin = path.join(contents, 'MacOS')
  const resources = path.join(contents, 'Resources')
  fs.mkdirSync(bin, { recursive: true })
  fs.mkdirSync(resources, { recursive: true })
  fs.mkdirSync(work, { recursive: true })
  const swift = fs
    .readdirSync(path.join(root, 'macos'))
    .filter((f) => f.endsWith('.swift'))
    .map((f) => path.join(root, 'macos', f))
  run('xcrun', [
    'swiftc',
    '-O',
    '-target',
    `arm64-apple-macos${MIN_MACOS}`,
    ...swift,
    '-o',
    path.join(bin, 'AITown'),
  ])
  for (const [name, packed] of BINARIES) {
    const target = path.join(bin, packed)
    fs.copyFileSync(path.join(root, 'target/release', name), target)
    fs.chmodSync(target, 0o755)
    run('strip', ['-x', target])
  }
  const files = stageAppBundle(resources)
  const builtin = stageBuiltinModel(bin, resources)
  makeIcon(root, path.join(resources, 'AppIcon.icns'), work)
  infoPlist(path.join(contents, 'Info.plist'), version, build)
  fs.writeFileSync(path.join(contents, 'PkgInfo'), 'APPL????')
  return { app, files: files.length, builtin }
}

/** 由内到外签：先签命令行程序，再签整个应用。公证要求开启强化运行时、带时间戳 */
function sign(app, identity, builtin) {
  const base = identity
    ? ['--force', '--timestamp', '--options', 'runtime', '--sign', identity.id]
    : ['--force', '--sign', '-']
  const programs = BINARIES.map(([, packed]) => packed)
  if (builtin) programs.push(LLAMA_SERVER)
  for (const packed of programs)
    run('codesign', [
      ...base,
      '--identifier',
      `${BUNDLE_ID}.${packed}`,
      path.join(app, 'Contents/MacOS', packed),
    ])
  run('codesign', [...base, app])
  run('codesign', ['--verify', '--strict', '--deep', '--verbose=2', app])
}

/** 打开 DMG 看到应用和「应用程序」的快捷方式，拖过去就装好了 */
function makeDmg(app, version, identity) {
  const stage = path.join(work, 'dmg')
  fs.rmSync(stage, { recursive: true, force: true })
  fs.mkdirSync(stage, { recursive: true })
  run('ditto', [app, path.join(stage, path.basename(app))])
  fs.symlinkSync('/Applications', path.join(stage, 'Applications'))
  const dmg = path.join(out, `ai-town-${version}.dmg`)
  fs.rmSync(dmg, { force: true })
  run('hdiutil', [
    'create',
    '-volname',
    APP_NAME,
    '-srcfolder',
    stage,
    '-fs',
    'HFS+',
    '-format',
    'UDZO',
    '-imagekey',
    'zlib-level=9',
    dmg,
  ])
  if (identity) run('codesign', ['--force', '--timestamp', '--sign', identity.id, dmg])
  return dmg
}

/** 没指定档案名时，公证凭据存进这个钥匙串档案 */
const NOTARY_PROFILE = 'ai-town-notary'

/**
 * 公证用的钥匙串档案。设了 AI_TOWN_APPLE_ID 与 AI_TOWN_APPLE_PASSWORD（App 专用密码）就每次先存进钥匙串，
 * notarytool 会先向 Apple 验证，不通过就停下；Team ID 取自签名证书名。没设就用已存好的档案，没有则不公证。
 * 密码只出现在这条命令的参数里：失败时不把命令行带进报错，免得密码进日志。
 */
function notaryProfile(identity) {
  const named = option('--notary-profile') ?? process.env.AI_TOWN_NOTARY_PROFILE
  const appleId = process.env.AI_TOWN_APPLE_ID
  const password = process.env.AI_TOWN_APPLE_PASSWORD
  if (!appleId || !password) return named ?? null
  const profile = named ?? NOTARY_PROFILE
  const team = identity.name.match(/\(([A-Z0-9]{10})\)$/)?.[1]
  if (!team) throw Error(`签名证书名里找不到 Team ID：${identity.name}`)
  try {
    execFileSync(
      'xcrun',
      [
        'notarytool',
        'store-credentials',
        profile,
        '--apple-id',
        appleId,
        '--team-id',
        team,
        '--password',
        password,
      ],
      { cwd: root, stdio: ['ignore', 'ignore', 'inherit'] }
    )
  } catch {
    throw Error(
      '存公证凭据失败：请检查 AI_TOWN_APPLE_ID 与 AI_TOWN_APPLE_PASSWORD（要用 App 专用密码，不是 Apple ID 登录密码）'
    )
  }
  console.log(`公证凭据已存入钥匙串档案 ${profile}（Team ID ${team}）`)
  return profile
}

/** 公证整个 DMG（连同里面的应用），通过后把票据钉进 DMG，离线也能验证 */
function notarize(dmg, profile) {
  console.log('正在提交公证，通常要几分钟…')
  const result = JSON.parse(
    execFileSync(
      'xcrun',
      [
        'notarytool',
        'submit',
        dmg,
        '--keychain-profile',
        profile,
        '--wait',
        '--output-format',
        'json',
      ],
      { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] }
    )
  )
  if (result.status !== 'Accepted') {
    run('xcrun', ['notarytool', 'log', result.id, '--keychain-profile', profile])
    throw Error(`公证没有通过（${result.status}），原因见上面的日志`)
  }
  run('xcrun', ['stapler', 'staple', dmg])
  run('xcrun', ['stapler', 'validate', dmg])
  run('spctl', ['--assess', '--type', 'open', '--context', 'context:primary-signature', '-v', dmg])
}

function main() {
  if (process.platform !== 'darwin') throw Error('mac 版只能在 macOS 上打包')
  const version = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version
  // 版本号按分钟递增，与安卓的 versionCode 同一个算法
  const build = Math.floor(Date.now() / 60000) - 29_000_000
  // 先确认证书和公证凭据，免得构建完才发现签不了、公证不了
  const identity = args.includes('--no-sign') ? null : signIdentity()
  if (!identity && (option('--notary-profile') ?? process.env.AI_TOWN_NOTARY_PROFILE))
    throw Error('公证需要 Developer ID 签名，不能和 --no-sign 一起用')
  const profile = identity ? notaryProfile(identity) : null
  if (identity) console.log(`签名证书：${identity.name}`)
  if (!args.includes('--skip-web')) run('corepack', ['pnpm', 'build'])
  if (!args.includes('--skip-rust')) buildRust()
  const { app, files, builtin } = assemble(version, build)
  console.log(
    builtin ? '已带上内置模型的推理程序' : '没有编内置模型的推理程序，这个包不能用内置模型'
  )
  sign(app, identity, builtin)
  const dmg = makeDmg(app, version, identity)
  if (profile) notarize(dmg, profile)
  const mb = (fs.statSync(dmg).size / 1048576).toFixed(1)
  console.log(`\n应用：${path.relative(root, app)}（数据包 ${files} 个文件）`)
  console.log(`DMG：${path.relative(root, dmg)}（${mb} MB，版本 ${version} / ${build}）`)
  if (!identity) console.log('没有签名：只能在这台 Mac 上打开')
  else if (!profile)
    console.log(
      '已签名，没有公证：别的 Mac 第一次打开会被系统拦下。设好 AI_TOWN_APPLE_ID 与 AI_TOWN_APPLE_PASSWORD 后再打一次'
    )
}

main()
