import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
import { createRequire } from 'node:module'
import { MUSIC_TRACKS, STING_URLS } from '../src/audio/catalog.ts'
import * as scene from '../src/audio/scene.ts'

const require = createRequire(new URL('../package.json', import.meta.url))
const ts = require('typescript')

// 运行真正的播放器、淡化器与偏好存储，只替换浏览器媒体和时钟，不复制选曲或混音规则。
function playerHarness(storage = new Map()) {
  let now = 0
  let frameId = 0
  let defer = false
  const frames = new Map()
  const audios = []
  const document = new EventTarget()
  document.hidden = false
  class Audio extends EventTarget {
    volume = 1
    currentTime = 0
    duration = 120
    paused = true
    released = false
    constructor(src) {
      super()
      this.src = src
      audios.push(this)
    }
    play() {
      this.paused = false
      return defer
        ? new Promise((resolve, reject) => {
            this.resolve = resolve
            this.reject = reject
          })
        : Promise.resolve()
    }
    pause() {
      this.paused = true
    }
    removeAttribute(name) {
      if (name === 'src') this.src = ''
    }
    load() {
      this.released = true
    }
  }
  const modules = new Map([
    ['catalog', { MUSIC_TRACKS, STING_URLS }],
    ['scene', scene],
  ])
  const load = (name) => {
    if (modules.has(name)) return modules.get(name)
    const source = fs.readFileSync(new URL(`../src/audio/${name}.ts`, import.meta.url), 'utf8')
    const scope = {
      exports: {},
      Audio,
      document,
      DOMException,
      console,
      setTimeout,
      clearTimeout,
      performance: { now: () => now },
      requestAnimationFrame: (callback) => {
        frames.set(++frameId, callback)
        return frameId
      },
      cancelAnimationFrame: (id) => frames.delete(id),
      localStorage: {
        getItem: (key) => storage.get(key) ?? null,
        setItem: (key, value) => storage.set(key, String(value)),
        removeItem: (key) => storage.delete(key),
      },
      require: (dependency) => load(dependency.replace('./', '')),
    }
    vm.runInNewContext(
      ts.transpileModule(source, {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
      }).outputText,
      scope,
      { filename: `${name}.ts` }
    )
    modules.set(name, scope.exports)
    return scope.exports
  }
  const button = {
    querySelector: () => ({ textContent: '' }),
    setAttribute() {},
    contains: () => false,
  }
  const starts = []
  const player = load('music').createMusicController(button, {
    onStart: (cell) => starts.push(cell),
  })
  return {
    player,
    audios,
    starts,
    document,
    storage,
    defer(value) {
      defer = value
    },
    advance(ms) {
      now += ms
      const pending = [...frames.values()]
      frames.clear()
      pending.forEach((callback) => callback(now))
    },
    active: () => audios.filter((audio) => !audio.released && !audio.paused),
  }
}
const flush = () => new Promise((resolve) => setImmediate(resolve))
const choice = (cell) => ({
  cell,
  tracks: MUSIC_TRACKS.filter((track) => track.cells.includes(cell)),
  urgency: 1,
  once: false,
})

test('手选曲保留到恢复自动；切歌中音量覆盖全部声部，静音与关闭不会漏出提示音，音量随刷新保留', async () => {
  const h = playerHarness()
  const p = h.player
  const snapshots = []
  p.subscribe((state) => snapshots.push(state))
  try {
    assert.equal(p.state().volume, 0.32, '首次打开保持原音乐音量')
    p.setChoice(choice('town/day'))
    await flush()
    const manual = MUSIC_TRACKS.find((track) => track.cells.includes('frozen/day'))
    p.selectTrack(manual.id)
    await flush()
    assert.equal(p.state().track.id, manual.id)
    assert.equal(p.state().mode, 'manual')
    const autoStarts = h.starts.length
    p.setChoice(choice('story/critical'))
    await flush()
    assert.equal(p.state().track.id, manual.id)
    assert.equal(h.starts.length, autoStarts, '手选不能消费剧情的自动播放记录')
    p.setVolume(0.5)
    h.advance(1500)
    assert.ok(h.active().length >= 2, '交叉淡化中同时检查新旧声部')
    assert.ok(h.active().every((audio) => audio.volume <= 0.5))
    p.setVolume(0)
    h.advance(100)
    assert.ok(h.active().every((audio) => audio.volume === 0))
    p.setAutomatic()
    await flush()
    p.setVolume(0.4)
    p.playSting('death')
    await flush()
    assert.ok(h.active().some((audio) => audio.src === STING_URLS.death && audio.volume > 0))
    p.setVolume(0)
    h.advance(1500)
    assert.ok(
      h.active().every((audio) => audio.volume === 0),
      '零音量也约束提示音'
    )
    assert.equal(p.state().mode, 'auto')
    assert.ok(p.state().track.cells.includes('story/critical'))
    p.toggle()
    const count = h.audios.length
    h.advance(3000)
    p.playSting('death')
    p.selectTrack(manual.id)
    await flush()
    assert.equal(h.audios.length, count, '关闭音乐时选歌不能偷偷播放')
    assert.equal(h.active().length, 0)
    p.setVolume(0.27)
    p.toggle()
    await flush()
    assert.equal(p.state().track.id, manual.id)
    assert.ok(snapshots.some((state) => state.mode === 'manual' && state.volume === 0))
  } finally {
    p.dispose()
  }
  const restored = playerHarness(h.storage)
  try {
    assert.equal(restored.player.state().volume, 0.27)
  } finally {
    restored.player.dispose()
  }
})

test('快速切歌与页面隐藏会废弃旧播放请求；浏览器阻止自动播放后可由用户恢复', async () => {
  const h = playerHarness()
  const p = h.player
  h.defer(true)
  try {
    p.setChoice(choice('town/day'))
    const first = h.audios.at(-1)
    first.reject(new DOMException('gesture required', 'NotAllowedError'))
    await flush()
    assert.equal(p.state().blocked, true)
    // 新播放器按钮先经过 document 的 pointerdown 捕获，再执行自己的 click。
    // 全局解锁若抢先清掉 blocked，后面的 toggle 会误把音乐关掉。
    const pointer = new Event('pointerdown')
    const control = {
      closest: (selector) => (selector === '[data-music-control]' ? control : null),
    }
    Object.defineProperty(pointer, 'target', { value: control })
    h.document.dispatchEvent(pointer)
    p.toggle()
    assert.equal(p.enabled(), true)
    const retry = h.audios.at(-1)
    retry.resolve()
    await flush()
    assert.equal(p.state().blocked, false)
    p.next()
    const stale = h.audios.at(-1)
    p.next()
    const latest = h.audios.at(-1)
    latest.resolve()
    await flush()
    const selected = p.state().track.id
    stale.resolve()
    await flush()
    assert.equal(p.state().track.id, selected)
    assert.equal(stale.released, true)
    p.next()
    const hidden = h.audios.at(-1)
    const beforeHide = p.state().track.id
    const startsBeforeHide = h.starts.length
    h.document.hidden = true
    h.document.dispatchEvent(new Event('visibilitychange'))
    hidden.resolve()
    await flush()
    assert.equal(hidden.released, true)
    assert.equal(p.state().track.id, beforeHide, '隐藏后晚到的请求不能成为当前曲目')
    assert.equal(h.starts.length, startsBeforeHide)
  } finally {
    p.dispose()
  }
  assert.equal(h.active().length, 0)
})

test('页面恢复的迟到回执不覆盖切歌、隐藏或关闭后的播放状态', async () => {
  const h = playerHarness()
  const p = h.player
  const visibility = (hidden) => {
    h.document.hidden = hidden
    h.document.dispatchEvent(new Event('visibilitychange'))
  }
  const denied = () => new DOMException('gesture required', 'NotAllowedError')
  try {
    p.setChoice(choice('town/day'))
    await flush()
    h.defer(true)
    const first = h.audios.at(-1)
    visibility(true)
    visibility(false)
    p.next()
    const second = h.audios.at(-1)
    first.reject(denied())
    await flush()
    second.resolve()
    await flush()
    assert.equal(p.state().track.url, second.src)
    assert.equal(p.state().blocked, false)
    assert.equal(p.state().error, null)
    p.toggle()
    assert.equal(p.enabled(), false, '当前曲已播放时开关应关闭，而不是重试')
    assert.equal(h.active().length, 0)

    p.toggle()
    const third = h.audios.at(-1)
    third.resolve()
    await flush()
    visibility(true)
    visibility(false)
    p.next()
    h.audios.at(-1).reject(denied())
    await flush()
    third.resolve()
    await flush()
    assert.equal(p.state().blocked, true, '旧恢复成功不能清掉新切歌的真实拒绝')
    p.toggle()
    const retry = h.audios.at(-1)
    retry.resolve()
    await flush()
    assert.equal(p.state().error, null)

    visibility(true)
    visibility(false)
    visibility(true)
    retry.reject(denied())
    await flush()
    assert.equal(p.state().blocked, false)
    assert.equal(p.state().error, null)
    assert.equal(h.active().length, 0)
    visibility(false)
    p.toggle()
    retry.reject(denied())
    await flush()
    assert.equal(p.enabled(), false)
    assert.equal(p.state().error, null)
    assert.equal(h.active().length, 0)
  } finally {
    p.dispose()
  }
})
