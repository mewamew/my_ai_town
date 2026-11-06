// 选曲走完整路径：名册里居民的处境、玩法给的格子 → 逐层找曲 → 播放器立刻换还是等放完。
// 也核对曲库登记的文件都在、目录里没有没登记的曲子。直接载入源码（只有类型导入，Node 去掉类型即可运行）。
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { MUSIC_TRACKS, STING_URLS } from '../src/audio/catalog.ts'
import { chooseMusic, rosterMood, switchNow } from '../src/audio/scene.ts'
import { tideMusic } from '../src/audio/gameModes/tide.ts'

const resident = (life, needs = {}) => ({
  body: { life },
  needs: Object.entries(needs).map(([kind, band]) => ({ kind, band })),
})

test('选曲从剧情、玩法、天气到时段逐层找，缺曲借相邻时段和小镇；变紧张立刻换，变平静等放完', () => {
  const listed = [...MUSIC_TRACKS.map((t) => t.url), ...Object.values(STING_URLS)]
  const dir = fileURLToPath(new URL('../assets/music/', import.meta.url))
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.m4a'))
  assert.deepEqual(new Set(listed.map((url) => path.basename(fileURLToPath(url)))), new Set(files))

  const calm = rosterMood([resident('alive'), resident('alive')])
  const base = { clock: '第 2 天 06:30', weather: 'clear', world: 'town', storyMusic: true }
  const at = (patch) =>
    chooseMusic({ ...base, mood: calm, once: new Set(), ...patch }, MUSIC_TRACKS)

  const dawn = at({})
  assert.equal(dawn.cell, 'town/dawn')
  assert.ok(dawn.tracks.some((t) => t.title === '晨雾码头'))
  // 本世界缺这一时段先借相邻时段：荒岛的夜晚放荒岛黄昏，废土的清晨放废土白天
  assert.equal(at({ world: 'island', clock: '21:10' }).cell, 'island/dusk')
  assert.equal(at({ world: 'wasteland' }).cell, 'wasteland/day')
  // 雪镇里下雪是常态
  assert.equal(at({ world: 'frozen', clock: '14:00', weather: 'snow' }).cell, 'frozen/day')
  assert.equal(at({ clock: '14:00', weather: 'snow' }).cell, 'weather/snow')

  // 剧情压过天气；关掉剧情音乐就只看天气和时段；缺吃少喝在深夜让给深夜曲
  const critical = rosterMood([resident('alive', { health: 'collapse' }), resident('dead')])
  const stormNight = { clock: '02:00', weather: 'thunderstorm', mood: critical }
  assert.equal(at(stormNight).cell, 'story/critical')
  assert.equal(at({ ...stormNight, storyMusic: false }).cell, 'weather/storm')
  const hungry = rosterMood([resident('alive', { fullness: 'urgent' }), resident('alive')])
  assert.equal(at({ clock: '10:00', mood: hungry }).cell, 'story/scarcity')
  assert.equal(at({ clock: '01:00', mood: hungry }).cell, 'town/sleep')

  // 潮水圈排在剧情之下、天气之上；开着时有人去世只响短提示；最后一圈是决战，只剩一人是结局
  const tide = (view, mood = calm, extra = {}) =>
    at({
      world: 'island',
      clock: '13:00',
      weather: 'rain',
      mood,
      ...extra,
      mode: { cell: tideMusic.cell(view, mood), order: tideMusic.order, quietDeaths: true },
    })
  const rising = { phase: 'rising', ring: 2, rings: 4 }
  assert.equal(tide(rising, calm, { once: new Set(['story/mourning']) }).cell, 'tide/rising')
  assert.equal(tide({ ...rising, ring: 4 }).cell, 'tide/final')
  const alone = rosterMood([resident('alive'), resident('dead'), resident('dead')])
  assert.equal(tide(rising, alone).cell, 'tide/winner')
  assert.equal(tide({ ...rising, phase: 'holding' }).cell, 'weather/rain')

  // 出了事、变紧张立刻换；变平静等这首放完；时段变了，快放完的那首放完
  const day = at({ clock: '16:59' })
  const storm = at({ clock: '16:59', weather: 'thunderstorm' })
  const mourning = at({
    clock: '16:59',
    weather: 'thunderstorm',
    once: new Set(['story/mourning']),
  })
  assert.equal(switchNow(storm, day, 120), true)
  assert.equal(switchNow(day, storm, 120), false)
  assert.equal(switchNow(mourning, storm, 120), true)
  assert.equal(switchNow(at({ clock: '17:00' }), day, 120), true)
  assert.equal(switchNow(at({ clock: '17:00' }), day, 10), false)
})
