import * as THREE from 'three'
import { MARGIN, PIXEL } from '../grid'
import { hash, rng } from '../pixel/noise'
import type { Dock } from '../pixel/island'
import type { MapTheme } from '../themes/types'
import type { Tilt } from './layout'
import { REFLECTION_SKIP } from './reflection'
import { sprite } from './sprite'
import { standee, texture } from './standee'

// 环境里的小动静：白天鸟群从镇子一头飞到另一头、影子扫过屋顶，港口上空、灯塔顶上几只海鸥盘旋，花丛边有蝴蝶，
// 傍晚镇中心上空几只蝙蝠，近岸偶尔一条鱼跃出水面（落水处在踩踏图上起一圈涟漪），夜里烟囱口零星飘出火星。
// 纯装饰：按地图种子和时间确定性地动，不能点、不进协议，和世界里发生的事无关。减少动画时全部隐去。

/** 两帧扇翅的像素图（横排两帧） */
function flapper(rows: [string[], string[]], colors: Record<string, string>) {
  const h = rows[0].length,
    w = rows[0][0].length
  return sprite(w * 2, h, (p) =>
    rows.forEach((frame, f) =>
      frame.forEach((row, y) =>
        [...row].forEach((ch, x) => ch !== '.' && p.px(f * w + x, y, colors[ch]))
      )
    )
  )
}

const BIRD = flapper(
  [
    ['k.....k', '.k...k.', '..kkk..', '.......'],
    ['.......', '..kkk..', '.k.k.k.', 'k.....k'],
  ],
  { k: '#2c2a33' }
)
const GULL = flapper(
  [
    ['g.......g', '.ww...ww.', '...www...', '....w....'],
    ['.........', '.wwwwwww.', 'g..www..g', '.........'],
  ],
  { w: '#f4f2ec', g: '#8a8f99' }
)
const BAT = flapper(
  [
    ['b.....b', 'bb.b.bb', '.bbbbb.', '...b...'],
    ['.......', '..bbb..', 'bbbbbbb', 'b..b..b'],
  ],
  { b: '#2a2133' }
)
const FISH = sprite(6, 3, (p) => {
  p.rect(1, 1, 4, 1, '#b8c8d8')
  p.px(0, 0, '#8aa0b8')
  p.px(0, 2, '#8aa0b8')
  p.rect(2, 0, 2, 1, '#e8f0f8')
  p.px(5, 1, '#5a6a80')
})
function butterflyCanvas(color: string) {
  return flapper(
    [
      ['c.c', 'cbc', 'c.c'],
      ['...', '.b.', '...'],
    ].map((f) => f.map((r) => r.padEnd(3, '.'))) as [string[], string[]],
    { c: color, b: '#3a2a22' }
  )
}

interface Flyer {
  mesh: THREE.Mesh
  map: THREE.Texture
}

export interface FaunaWorld {
  /** 主岛（含海岸）的范围，世界坐标 */
  box: { x0: number; z0: number; x1: number; z1: number }
  docks: Dock[]
  /** 灯塔（地图坐标和灯室的高度），海鸥绕着塔顶飞 */
  towers: [number, number, number][]
  /** 花丛（地图坐标），蝴蝶围着它们飞 */
  flowers: [number, number][]
  /** 近岸的水（地图坐标），鱼在这里跳 */
  shallows: [number, number][]
  /** 烟囱口（世界坐标），夜里飘火星 */
  chimneys: [number, number, number][]
  center: [number, number]
}

export interface FaunaLight {
  day: number
  twilight: number
  night: number
  rain: number
  wind: number
}

export class Fauna {
  readonly group = new THREE.Group()
  private readonly birds: Flyer[] = []
  private readonly gulls: (Flyer & {
    dock: { x: number; y: number }
    phase: number
    radius: number
    height: number
  })[] = []
  private readonly butterflies: (Flyer & { at: [number, number]; phase: number })[] = []
  private readonly bats: (Flyer & { phase: number })[] = []
  private readonly fish: Flyer
  private readonly embers: THREE.Points
  private tilt: Tilt
  private light: FaunaLight = { day: 1, twilight: 0, night: 0, rain: 0, wind: 0.3 }
  /** 鱼落水时调用：在踩踏图上起一圈涟漪 */
  onSplash?: (x: number, y: number) => void
  private lastFish = -1

  constructor(
    private readonly world: FaunaWorld,
    theme: MapTheme,
    seed: number,
    tilt: Tilt
  ) {
    this.tilt = tilt
    const random = rng(seed + 991)
    const make = (canvas: HTMLCanvasElement, frames: number, scale = 1) => {
      const map = texture(canvas)
      map.repeat.x = 1 / frames
      const mesh = standee(map, { frame: [canvas.width / frames, canvas.height], scale })
      mesh.layers.set(REFLECTION_SKIP)
      this.group.add(mesh)
      return { mesh, map }
    }
    for (let i = 0; i < 7; i++) this.birds.push(make(BIRD, 2))
    if (theme.outer === 'sea')
      world.docks.slice(0, 2).forEach((dock, d) => {
        for (let i = 0; i < 3; i++)
          this.gulls.push({
            ...make(GULL, 2),
            dock,
            phase: random() * Math.PI * 2,
            radius: (28 + random() * 26) * PIXEL,
            height: (34 + random() * 18 + d * 4) * PIXEL,
          })
      })
    if (theme.outer === 'sea')
      for (const [x, y, height] of world.towers.slice(0, 2))
        for (let i = 0; i < 3; i++)
          this.gulls.push({
            ...make(GULL, 2),
            dock: { x, y },
            phase: random() * Math.PI * 2,
            radius: (22 + random() * 16) * PIXEL,
            height: height + (random() * 12 - 2) * PIXEL,
          })
    const colors = theme.ground.flowers
    const flowers = world.flowers.slice()
    for (let i = 0; i < Math.min(10, flowers.length); i++) {
      const at = flowers[Math.floor(random() * flowers.length)]
      this.butterflies.push({
        ...make(butterflyCanvas(colors[i % colors.length]), 2),
        at,
        phase: random() * 10,
      })
    }
    for (let i = 0; i < 5; i++) this.bats.push({ ...make(BAT, 2), phase: random() * 10 })
    this.fish = make(FISH, 1)
    this.fish.mesh.visible = false
    // 火星：每根烟囱几颗，在着色器里按时间往上飘、一闪一闪
    const n = world.chimneys.length * 4
    const pos = new Float32Array(n * 3),
      phase = new Float32Array(n)
    world.chimneys.forEach(([x, y, z], c) =>
      [0, 1, 2, 3].forEach((k) => {
        const i = c * 4 + k
        pos.set([x, y, z], i * 3)
        phase[i] = hash(c, k, 7)
      })
    )
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3))
    g.setAttribute('phase', new THREE.BufferAttribute(phase, 1))
    this.embers = new THREE.Points(
      g,
      new THREE.ShaderMaterial({
        uniforms: { time: { value: 0 }, amount: { value: 0 }, unitPx: { value: 1 } },
        vertexShader: /* glsl */ `
attribute float phase;
uniform float time;
uniform float unitPx;
varying float vAlpha;
void main() {
  float life = fract(time * 0.22 + phase);
  vec3 p = position + vec3(sin(time * 1.3 + phase * 30.0) * ${(3 * PIXEL).toFixed(1)} + life * ${(8 * PIXEL).toFixed(1)},
    life * ${(30 * PIXEL).toFixed(1)}, 0.0);
  vAlpha = (1.0 - life) * (0.5 + 0.5 * sin(time * 9.0 + phase * 50.0));
  gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
  gl_PointSize = max(1.5, ${PIXEL.toFixed(1)} * unitPx);
}`,
        fragmentShader: /* glsl */ `
uniform float amount;
varying float vAlpha;
void main() { gl_FragColor = vec4(vec3(1.0, 0.55, 0.2) * vAlpha * amount * 1.8, 1.0); }`,
        blending: THREE.AdditiveBlending,
        transparent: true,
        depthWrite: false,
      })
    )
    this.embers.frustumCulled = false
    this.embers.layers.set(REFLECTION_SKIP)
    this.group.add(this.embers)
    this.setTilt(tilt)
  }

  setTilt(tilt: Tilt) {
    this.tilt = tilt
    for (const f of this.flyers()) f.mesh.rotation.set(-tilt.pitch, tilt.yaw, 0, 'YXZ')
  }

  setLight(light: FaunaLight) {
    this.light = light
  }

  setScale(unitPx: number) {
    ;(this.embers.material as THREE.ShaderMaterial).uniforms.unitPx.value = unitPx
  }

  private flyers(): Flyer[] {
    return [...this.birds, ...this.gulls, ...this.butterflies, ...this.bats, this.fish]
  }

  /** 摆到 seconds 这一刻；减少动画时整组隐去 */
  step(seconds: number) {
    const { day, twilight, night, rain, wind } = this.light
    const { box, center } = this.world
    const flap = (f: Flyer, rate: number, offset: number) =>
      (f.map.offset.x = (Math.floor(seconds * rate + offset) % 2) / 2)
    const place = (f: Flyer, x: number, z: number, height: number) =>
      f.mesh.position.set(x, height, z)
    // 鸟群：每 70 秒一群，用 18 秒从一边飞到另一边，按 V 字排开
    const cycle = Math.floor(seconds / 70),
      t = (seconds % 70) / 18
    const birdsOut = t < 1 && day > 0.35 && rain < 0.3
    const heading = hash(cycle, 1, 3) * Math.PI * 2
    const dx = Math.cos(heading),
      dz = Math.sin(heading)
    const cx = (box.x0 + box.x1) / 2,
      cz = (box.z0 + box.z1) / 2
    const span = Math.hypot(box.x1 - box.x0, box.z1 - box.z0) * 0.6
    const lateral = (hash(cycle, 2, 3) - 0.5) * span * 0.6
    this.birds.forEach((b, i) => {
      b.mesh.visible = birdsOut
      if (!birdsOut) return
      const rank = Math.ceil(i / 2) * (i % 2 ? 1 : -1)
      const back = Math.abs(rank) * 9 * PIXEL
      const along = (t - 0.5) * 2 * span - back
      place(
        b,
        cx + dx * along - dz * (lateral + rank * 8 * PIXEL),
        cz + dz * along + dx * (lateral + rank * 8 * PIXEL),
        (78 + Math.sin(seconds * 0.7 + i) * 3) * PIXEL
      )
      flap(b, 6, i * 0.37)
    })
    // 海鸥：港口上空、灯塔顶上慢慢盘旋，偶尔扇几下
    for (const g of this.gulls) {
      g.mesh.visible = day > 0.3 && rain < 0.5
      const a = seconds * 0.25 + g.phase
      place(
        g,
        g.dock.x + Math.cos(a) * g.radius,
        g.dock.y + Math.sin(a) * g.radius * 0.6,
        g.height + Math.sin(a * 2) * 4 * PIXEL
      )
      g.map.offset.x = Math.sin(seconds * 9 + g.phase * 5) > 0.6 ? 0.5 : 0
    }
    // 蝴蝶：晴天围着自己的花丛打转
    for (const b of this.butterflies) {
      b.mesh.visible = day > 0.5 && rain < 0.1 && wind < 0.9
      const s = seconds * 0.9 + b.phase
      place(
        b,
        b.at[0] + Math.sin(s * 1.3) * 5 * PIXEL + Math.sin(s * 3.1) * PIXEL,
        b.at[1] + Math.cos(s * 0.9) * 3 * PIXEL,
        (5 + Math.sin(s * 2.3) * 2.5 + 2) * PIXEL
      )
      flap(b, 9, b.phase)
    }
    // 蝙蝠：傍晚到入夜，在镇中心上空乱飞
    for (const b of this.bats) {
      b.mesh.visible = (twilight > 0.3 || (night > 0.2 && night < 0.9)) && rain < 0.3
      const s = seconds * 0.8 + b.phase
      place(
        b,
        center[0] + Math.sin(s * 1.7) * 90 * PIXEL + Math.sin(s * 4.3) * 12 * PIXEL,
        center[1] + Math.cos(s * 1.1) * 60 * PIXEL,
        (26 + Math.sin(s * 3.7) * 6) * PIXEL
      )
      flap(b, 11, b.phase)
    }
    // 鱼：每 9 秒左右，近岸某处跳出水面划一道弧，落水处起一圈涟漪
    const shallows = this.world.shallows
    const fishCycle = Math.floor(seconds / 9),
      ft = (seconds % 9) / 0.9
    const fishOut = shallows.length > 0 && ft < 1 && (day > 0.2 || twilight > 0.2) && rain < 0.5
    this.fish.mesh.visible = fishOut
    if (fishOut) {
      const [x, y] = shallows[Math.floor(hash(fishCycle, 4, 9) * shallows.length)]
      const dir = hash(fishCycle, 5, 9) < 0.5 ? -1 : 1
      place(this.fish, x + dir * (ft - 0.5) * 10 * PIXEL, y, Math.sin(ft * Math.PI) * 7 * PIXEL)
      this.fish.mesh.rotation.z = -dir * (ft - 0.5) * 1.6
      if (ft > 0.9 && this.lastFish !== fishCycle) {
        this.lastFish = fishCycle
        this.onSplash?.(x + dir * 5 * PIXEL, y)
      }
    }
    // 火星：夜里烟囱口
    const embers = this.embers.material as THREE.ShaderMaterial
    embers.uniforms.time.value = seconds
    embers.uniforms.amount.value = night * (1 - rain)
    this.embers.visible = night > 0.05
  }

  /** 减少动画：整组隐去 */
  setEnabled(enabled: boolean) {
    this.group.visible = enabled
  }

  dispose() {
    for (const f of this.flyers()) {
      f.mesh.geometry.dispose()
      ;(f.mesh.material as THREE.Material).dispose()
      f.map.dispose()
    }
    this.embers.geometry.dispose()
    ;(this.embers.material as THREE.Material).dispose()
  }
}

/** 近岸浅水（地图坐标）：鱼跳的地方，离岸 4～10 个像素的海 */
export function shallowsOf(ground: {
  width: number
  height: number
  wet: Uint8Array
  depth: Uint8Array
}) {
  const { width: pw, height: ph, wet, depth } = ground
  const out: [number, number][] = []
  for (let y = 0; y < ph; y += 7)
    for (let x = 0; x < pw; x += 7) {
      const i = y * pw + x
      if (wet[i] && depth[i] >= 4 && depth[i] <= 10)
        out.push([x * PIXEL - MARGIN, y * PIXEL - MARGIN])
    }
  return out
}
