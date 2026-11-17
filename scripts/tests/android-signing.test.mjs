import test from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const PASSWORD = 'TEST-ONLY-not-a-real-signing-password'
const SIGNING = new URL('../android/signing.mjs', import.meta.url).href

function fixture(t) {
  const android = fs.mkdtempSync(path.join(os.tmpdir(), 'town-android-signing-'))
  t.after(() => fs.rmSync(android, { recursive: true, force: true }))
  const runner = path.join(android, 'runner.mjs')
  const stub = path.join(android, 'fake-keytool.mjs')
  // 用 Node 假执行器代替 keytool；特意向两个输出流回显口令，覆盖成功和 execFileSync 失败。
  fs.writeFileSync(
    stub,
    `import fs from 'node:fs'
import path from 'node:path'
const args = process.argv.slice(2)
const value = (flag) => args[args.indexOf(flag) + 1]
const password = (flag) => args.includes(flag + ':env')
  ? process.env[value(flag + ':env')] : value(flag)
const storePassword = password('-storepass')
const keyPassword = password('-keypass')
const android = path.dirname(value('-keystore'))
fs.writeFileSync(path.join(android, 'received.json'), JSON.stringify({ storePassword, keyPassword }))
process.stdout.write('fake keytool stdout: ' + storePassword + '\\n')
process.stderr.write('fake keytool stderr: ' + keyPassword + '\\n')
if (fs.existsSync(path.join(android, 'fail'))) process.exit(7)
fs.writeFileSync(value('-keystore'), 'NOT A KEYSTORE: test fixture only')
`
  )
  fs.writeFileSync(
    runner,
    `import { execFileSync } from 'node:child_process'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { ensureReleaseKeystore } from ${JSON.stringify(SIGNING)}
const android = ${JSON.stringify(android)}
const mode = process.argv[2]
ensureReleaseKeystore({ android, java: android + '/fake-jdk', debug: mode === 'debug' }, {
  createPassword: () => {
    assert.equal(mode, 'release', 'debug and existing signatures must not generate passwords')
    return ${JSON.stringify(PASSWORD)}
  },
  execute: (command, args, options) => {
    fs.writeFileSync(android + '/invocation.json', JSON.stringify({ command, args }))
    return execFileSync(process.execPath, [${JSON.stringify(stub)}, ...args], options)
  },
})
assert.equal(process.env.AI_TOWN_KEYSTORE_PASSWORD, undefined, 'password must stay in child env')
`
  )
  const run = (mode) => spawnSync(process.execPath, [runner, mode], { encoding: 'utf8', env: {} })
  const read = (name) => fs.readFileSync(path.join(android, name), 'utf8')
  const exists = (name) => fs.existsSync(path.join(android, name))
  return { android, run, read, exists }
}

function assertNoPassword(result) {
  assert.equal(result.stdout.includes(PASSWORD), false, 'stdout must not expose the password')
  assert.equal(result.stderr.includes(PASSWORD), false, 'stderr/error must not expose the password')
}

test('debug skips signing; first release privately creates a reusable signing identity', (t) => {
  const { android, run, read, exists } = fixture(t)
  assert.equal(run('debug').status, 0)
  assert.equal(exists('release.jks'), false)
  assert.equal(exists('keystore.properties'), false)
  assert.equal(exists('invocation.json'), false)

  const first = run('release')
  assert.equal(first.status, 0)
  assert.deepEqual(JSON.parse(read('received.json')), {
    storePassword: PASSWORD,
    keyPassword: PASSWORD,
  })
  const properties = read('keystore.properties')
  assert.equal(
    properties,
    `storeFile=release.jks\nstorePassword=${PASSWORD}\nkeyAlias=aitown\nkeyPassword=${PASSWORD}\n`
  )
  assert.equal(fs.statSync(path.join(android, 'keystore.properties')).mode & 0o777, 0o600)
  assertNoPassword(first)
  const invocation = JSON.parse(read('invocation.json'))
  assert.equal(JSON.stringify(invocation).includes(PASSWORD), false, 'no password in argv')
  for (const flag of ['-storepass:env', '-keypass:env']) {
    assert.ok(invocation.args.includes(flag))
    assert.equal(invocation.args[invocation.args.indexOf(flag) + 1], 'AI_TOWN_KEYSTORE_PASSWORD')
  }

  const keystore = read('release.jks')
  fs.unlinkSync(path.join(android, 'invocation.json'))
  assert.equal(run('reuse').status, 0)
  assert.equal(exists('invocation.json'), false)
  assert.equal(read('keystore.properties'), properties)
  assert.equal(read('release.jks'), keystore)
})

test('keytool failure does not leak captured output or error details and does not commit credentials', (t) => {
  const { android, run, read, exists } = fixture(t)
  fs.writeFileSync(path.join(android, 'fail'), '')
  const failed = run('release')
  assert.notEqual(failed.status, 0)
  assert.deepEqual(JSON.parse(read('received.json')), {
    storePassword: PASSWORD,
    keyPassword: PASSWORD,
  })
  assert.equal(exists('keystore.properties'), false)
  assertNoPassword(failed)
  assert.match(failed.stderr, /keytool.*失败.*7/)

  fs.unlinkSync(path.join(android, 'fail'))
  const retried = run('release')
  assert.equal(retried.status, 0)
  assertNoPassword(retried)
  assert.equal(exists('keystore.properties'), true)
})
