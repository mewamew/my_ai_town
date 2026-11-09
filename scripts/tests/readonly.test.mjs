import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { root } from './support.mjs'
test('built app creates and runs a map with a read-only resource tree and no preconfigured map files', async () => {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'town-readonly-')),
    bundle = path.join(temp, 'application'),
    data = path.join(temp, 'user-data')
  let child
  async function permissions(dir, mode) {
    for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
      const p = path.join(dir, entry.name)
      if (entry.isDirectory()) await permissions(p, mode)
      else if (!entry.isSymbolicLink()) await fs.chmod(p, mode === 0o555 ? 0o444 : 0o644)
    }
    await fs.chmod(dir, mode)
  }
  try {
    for (const file of [
      'scripts',
      'data/maps',
      'data/mapgen',
      'data/scene-assets',
      'data/props',
      'config/application.json',
      'config/needs_rules.json',
      'config/weather_rules.json',
      'config/resident-library',
      'frontend/town-2d/dist',
      // 生成器与前端共用的地形采样（scripts/mapgen/spatial.mjs 引用）。
      'frontend/town-shared/src/spatial.ts',
      // 地图风格名单（scripts/mapgen/spec.mjs 引用，校验建镇参数）。
      'frontend/town-2d/src/map/themes/presets.ts',
      // 建镇页的地点分组（scripts/mapgen/plan.mjs 引用，一句话规划的地点表）。
      'frontend/town-2d/src/launcher/placeGroups.ts',
    ]) {
      const p = path.join(bundle, file)
      await fs.mkdir(path.dirname(p), { recursive: true })
      await fs.cp(path.join(root, file), p, { recursive: true })
    }
    await fs.mkdir(path.join(bundle, 'target/debug'), { recursive: true })
    for (const bin of ['host', 'town-map'])
      await fs.symlink(path.join(root, 'target/debug', bin), path.join(bundle, 'target/debug', bin))
    await permissions(bundle, 0o555)
    await assert.rejects(fs.writeFile(path.join(bundle, 'data/maps/another-map.json'), '{}'), (e) =>
      ['EACCES', 'EPERM'].includes(e.code)
    )
    let output = ''
    child = spawn(process.execPath, [path.join(bundle, 'scripts/town-manager.mjs')], {
      cwd: bundle,
      env: {
        ...process.env,
        AI_TOWN_HOME: data,
        TOWN_MANAGER_PORT: '0',
        TOWN_MOCK_LLM: '1',
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    child.stdout.on('data', (b) => {
      output += b
    })
    child.stderr.on('data', (b) => {
      output += b
    })
    const deadline = Date.now() + 10000
    let match
    while (!(match = output.match(/http:\/\/127.0.0.1:(\d+)/))) {
      if (child.exitCode !== null || Date.now() > deadline) throw Error(output || '启动失败')
      await new Promise((r) => setTimeout(r, 50))
    }
    const base = 'http://127.0.0.1:' + match[1]
    assert.match(await (await fetch(base + '/')).text(), /AI小镇/)
    assert.equal((await fetch(base + '/game.html')).status, 200)
    const api = async (route, body) => {
      const r = await fetch(base + '/api/towns' + route, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-town-client': '1' },
        body: JSON.stringify(body),
      })
      const value = await r.json()
      assert.equal(r.status, 200, JSON.stringify(value))
      return value
    }
    const draft = await api('/preview', {
      spec: {
        name: '只读发布包验证',
        seed: 22,
        style_id: 'svg-town-v1',
        places: [
          { kind: 'home', count: 2, size: 'small' },
          { kind: 'park', count: 1, size: 'large' },
        ],
        constraints: [],
        resources: 'normal-life',
      },
    })
    const saved = await api('/save', {
      draft_id: draft.id,
      expected_version: draft.version,
      request_id: 'readonly',
    })
    const opened = await api(`/${saved.id}/open`, {})
    assert(opened.worldId)
    assert.equal(opened.mapHash, draft.version)
    assert.equal(
      (await fs.readdir(path.join(bundle, 'data/maps'))).sort().join(','),
      '2d-town,broken-towers,spring-valley'
    )
    const actual = JSON.parse(await fs.readFile(path.join(data, 'towns', saved.id, 'map.json')))
    assert.deepEqual(actual, draft.document)
    await api(`/${saved.id}/close`, {})
  } catch (error) {
    for (const id of await fs.readdir(path.join(data, 'towns')).catch(() => [])) {
      const log = await fs
        .readFile(path.join(data, 'towns', id, 'host.log'), 'utf8')
        .catch(() => '')
      if (log) console.error(log)
    }
    throw error
  } finally {
    if (child && child.exitCode === null) {
      const ended = new Promise((r) => child.once('exit', r))
      child.kill('SIGTERM')
      await ended
    }
    await permissions(bundle, 0o755)
    await fs.rm(temp, { recursive: true, force: true })
  }
})
