// protocol.ts 是手写的前端类型。这里用 Rust 实际序列化出的样本逐条核对：
// crates/protocol/tests/wire.rs 的 samples_for_typescript 把每种消息的样本写到 target/tmp，
// 本测试把每条样本写成 `satisfies ServerMsg`（或 ClientMsg）的常量，交给 tsc 检查。
// 多出的字段、缺少的必填字段、错误的字符串取值、null 与缺省不一致都会报错。
import test from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..')
const target = path.resolve(root, process.env.CARGO_TARGET_DIR ?? 'target')
const samplesFile = path.join(target, 'tmp/protocol-wire-samples.json')

/** 相对路径写进 import 与 extends：tsc 要求以 ./ 或 ../ 开头 */
function relative(from, to) {
  const rel = path.relative(from, to).split(path.sep).join('/')
  return rel.startsWith('.') ? rel : `./${rel}`
}

test('Rust 发出的每种消息样本都符合 protocol.ts 的类型', () => {
  assert.ok(
    fs.existsSync(samplesFile),
    `缺少 ${samplesFile}：先运行 cargo test -p protocol --test wire 生成样本`
  )
  const { server, client } = JSON.parse(fs.readFileSync(samplesFile, 'utf8'))
  assert.ok(server.length > 0 && client.length > 0)
  const dir = path.join(target, 'tmp/protocol-wire-check')
  fs.mkdirSync(dir, { recursive: true })
  const protocol = relative(dir, path.join(root, 'frontend/town-shared/src/protocol.ts'))
  const lines = [`import type { ClientMsg, ServerMsg } from '${protocol}'`]
  server.forEach((sample, i) =>
    lines.push(`export const server${i} = ${JSON.stringify(sample)} satisfies ServerMsg`)
  )
  client.forEach((sample, i) =>
    lines.push(`export const client${i} = ${JSON.stringify(sample)} satisfies ClientMsg`)
  )
  fs.writeFileSync(path.join(dir, 'samples.ts'), lines.join('\n') + '\n')
  fs.writeFileSync(
    path.join(dir, 'tsconfig.json'),
    JSON.stringify({
      extends: relative(dir, path.join(root, 'frontend/tsconfig.base.json')),
      files: ['samples.ts'],
    })
  )
  // 直接交给 Node，避免 Windows 不能执行 .bin 中的 POSIX 包装脚本。
  const tsc = path.join(root, 'frontend/town-shared/node_modules/typescript/bin/tsc')
  const result = spawnSync(process.execPath, [tsc, '-p', dir], {
    encoding: 'utf8',
    windowsHide: true,
  })
  assert.ifError(result.error)
  assert.equal(result.status, 0, `${result.stdout}${result.stderr}`)
})
