// 安装包里应用自带的数据是只读的（签了名的 mac 应用、手机安装目录），用户目录一开始是空的：
// 照打包脚本整理一份（stageAppBundle），设成只读，管理服务照样能列出内置小镇、建镇、开镇。
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { stageAppBundle } from '../app-bundle.mjs'
import { draftTown, startManager } from './support.mjs'
test('built app creates and runs a map with a read-only resource tree and no preconfigured map files', async () => {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'town-readonly-')),
    bundle = path.join(temp, 'application'),
    data = path.join(temp, 'user-data')
  let m
  async function permissions(dir, mode) {
    for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
      const p = path.join(dir, entry.name)
      if (entry.isDirectory()) await permissions(p, mode)
      else if (!entry.isSymbolicLink()) await fs.chmod(p, mode === 0o555 ? 0o444 : 0o644)
    }
    await fs.chmod(dir, mode)
  }
  try {
    stageAppBundle(bundle)
    const app = path.join(bundle, 'app')
    await permissions(bundle, 0o555)
    await assert.rejects(fs.writeFile(path.join(app, 'data/maps/another-map.json'), '{}'), (e) =>
      ['EACCES', 'EPERM'].includes(e.code)
    )
    m = await startManager(data, { app, web: path.join(bundle, 'web') })
    assert.match(await (await fetch(m.origin + '/')).text(), /AI小镇/)
    assert.equal((await fetch(m.origin + '/game.html')).status, 200)
    const { document, draft } = await draftTown(m, {
      name: '只读发布包验证',
      seed: 22,
      style_id: 'svg-town-v1',
      places: [
        { kind: 'home', count: 2, size: 'small' },
        { kind: 'park', count: 1, size: 'large' },
      ],
      constraints: [],
      resources: 'normal-life',
    })
    const saved = await m.api('/save', {
      draft_id: draft.id,
      expected_version: draft.version,
      request_id: 'readonly',
    })
    const opened = await m.api(`/${saved.id}/open`, {})
    assert(opened.worldId)
    assert.equal(opened.mapHash, document.content_hash)
    assert.equal(
      (await fs.readdir(path.join(app, 'data/maps'))).sort().join(','),
      '2d-town,broken-towers,spring-valley'
    )
    const actual = JSON.parse(await fs.readFile(path.join(data, 'towns', saved.id, 'map.json')))
    assert.deepEqual(actual, document)
    await m.api(`/${saved.id}/close`, {})
  } catch (error) {
    if (m) console.error(m.output())
    for (const id of await fs.readdir(path.join(data, 'towns')).catch(() => [])) {
      const log = await fs
        .readFile(path.join(data, 'towns', id, 'host.log'), 'utf8')
        .catch(() => '')
      if (log) console.error(log)
    }
    throw error
  } finally {
    await m?.stop()
    await permissions(bundle, 0o755).catch(() => {})
    await fs.rm(temp, { recursive: true, force: true })
  }
})
