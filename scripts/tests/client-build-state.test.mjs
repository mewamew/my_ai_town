import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import {
  clientSourceHash,
  verifyClientBuild,
  writeClientBuildState,
} from '../client-build-state.mjs'

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'creator-build-state-'))
  t.after(() => fs.rm(root, { recursive: true, force: true }))
  const put = async (relative, content) => {
    const file = path.join(root, relative)
    await fs.mkdir(path.dirname(file), { recursive: true })
    await fs.writeFile(file, content)
  }
  await put('frontend/town-2d/src/main.ts', 'export const version = 1')
  await put('frontend/town-shared/src/shared.ts', 'export const shared = 1')
  await put('scripts/mapgen/generate.mjs', 'export const generate = () => ({})')
  await put('frontend/town-2d/dist/index.html', '<main></main>')
  await put('frontend/town-2d/dist/game.html', '<main></main>')
  const rebuild = () => writeClientBuildState(root, path.join(root, 'frontend/town-2d/dist'))
  return { root, put, rebuild }
}

test('formal preview rejects missing, old-format and stale builds until rebuilt', async (t) => {
  const { root, put, rebuild } = await fixture(t)
  await assert.rejects(verifyClientBuild(root), /未构建/)
  await rebuild()
  await verifyClientBuild(root)
  await fs.rm(path.join(root, 'frontend/town-2d/dist/game.html'))
  await assert.rejects(verifyClientBuild(root), /缺少游戏入口/)
  await put('frontend/town-2d/dist/game.html', '<main></main>')
  await put(
    'frontend/town-2d/dist/build-source.json',
    JSON.stringify({ version: 1, sourceHash: await clientSourceHash(root) })
  )
  await assert.rejects(verifyClientBuild(root), /构建已过期/)
  await rebuild()
  await verifyClientBuild(root)
  await put('frontend/town-2d/src/main.ts', 'export const version = 2')
  await assert.rejects(verifyClientBuild(root), /构建已过期/)
  await rebuild()
  await verifyClientBuild(root)
})

// 每类都走生产用的写摘要、启动检查，再重建的路径；改动互相隔离，不能靠另一份输入代为失效。
for (const [kind, inputs] of Object.entries({
  'shared generator and replay code': ['scripts/mapgen/graph.mjs', 'scripts/replay/reel.mjs'],
  'bundled gameplay data': [
    'data/mapgen/templates.json',
    'data/props/core/definitions.json',
    'data/scene-assets/pr10-village-v1/manifest.json',
    'config/needs_rules.json',
    'data/maps/frostlight/map.json',
  ],
  'binary and text assets': [
    'frontend/town-2d/src/assets/covers/default-town.jpg',
    'frontend/town-shared/assets/music/music_title_overture.m4a',
    'frontend/town-shared/src/game/icon.svg',
  ],
  'dependency and build configuration': [
    'package.json',
    'pnpm-lock.yaml',
    'pnpm-workspace.yaml',
    'frontend/tsconfig.base.json',
    'frontend/town-2d/vite.config.ts',
    'scripts/client-build-state.mjs',
  ],
})) {
  test(`formal preview invalidates changes to ${kind}`, async (t) => {
    const { root, put, rebuild } = await fixture(t)
    for (const input of inputs) await put(input, 'before')
    await rebuild()
    await verifyClientBuild(root)
    for (const input of inputs) {
      await put(input, 'after')
      await assert.rejects(verifyClientBuild(root), /构建已过期/, input)
      await rebuild()
      await verifyClientBuild(root)
    }
    // 素材与 glob 输入的增删也要失效，不能只比较已知文件的修改时间。
    if (kind === 'binary and text assets') {
      const added = 'frontend/town-2d/src/assets/covers/new-town.jpg'
      await put(added, Buffer.from([0, 255, 1]))
      await assert.rejects(verifyClientBuild(root), /构建已过期/)
      await rebuild()
      await verifyClientBuild(root)
      await fs.rm(path.join(root, added))
      await assert.rejects(verifyClientBuild(root), /构建已过期/)
      await rebuild()
      await verifyClientBuild(root)
    }
  })
}

test('build outputs, caches and private runtime files do not invalidate the client', async (t) => {
  const { root, put, rebuild } = await fixture(t)
  await rebuild()
  const hash = await clientSourceHash(root)
  for (const relative of [
    'frontend/town-2d/dist/assets/game.js',
    'frontend/town-2d/node_modules/vite/index.js',
    'frontend/town-2d/.vite/deps.json',
    'frontend/town-2d/.vite-temp/vite.config.ts.timestamp.mjs',
    'frontend/town-shared/.cache/module.js',
    'frontend/town-2d/.local/preview.js',
    'scripts/mapgen/.tmp/debug.json',
    'frontend/town-2d/src/main.ts.tmp',
    'frontend/town-2d/.DS_Store',
    'frontend/town-2d/.env.local',
    '.local/run-data/towns/test/world.json',
    'config/credentials.json',
    'logs/manager.log',
  ])
    await put(relative, 'not a build input')
  assert.equal(await clientSourceHash(root), hash)
  await verifyClientBuild(root)
})
