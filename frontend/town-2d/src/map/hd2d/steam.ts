import * as THREE from 'three'
import { fromPx, PIXEL } from '../grid'
import { hash, noise } from '../pixel/noise'
import type { Tilt } from './layout'
import { pixelMaterial } from './pixelSampling'
import { texture } from './standee'

// 温泉冒的白汽：水面上一缕缕薄雾，贴着水面冒出来，慢慢升高、顺风往东飘，越飘越宽、越淡，散了再从水面冒。
// 一缕是一片朝向镜头的像素薄片（横着长、边上破碎的一抹雾），画了几种样子轮着用。
// 所有白汽是一个实例化网格，一次画完：每缕的位置、大小、浓淡每拍在这里算好写进实例，手机上也只多一次绘制。
// 受场景光照（傍晚染成粉色、夜里暗下去），夜里被池水的青光从底下映亮（glow）；
// 深度按冒汽的那一点水面算，池子南边的树挡得住它，北边的房子挡不住。

/** 薄雾贴图：几种样子横排成一张图，每种 FW×FH 个贴图像素 */
const FRAMES = 4
const FW = 36
const FH = 10
/** 一缕从冒出到散掉几秒；飘完升高、往东偏多少（地图像素） */
const LIFE = 8
const RISE = 26
const DRIFT = 14
/** 每多少水面像素放一处冒汽的地方（离池边至少 EDGE 像素），一处轮流冒几缕 */
const AREA = 300
const EDGE = 4
const PER = 3

/** 一抹薄雾：几道横着的细雾丝，长短不一、上下错开，丝上有断口；丝和丝之间隔格子铺一层极淡的雾连起来。
 *  不画成圆鼓鼓的一团，免得定格时像一朵朵云 */
function wispAtlas(seed: number) {
  const c = document.createElement('canvas')
  c.width = FW * FRAMES
  c.height = FH
  const ctx = c.getContext('2d')!
  const img = ctx.createImageData(c.width, c.height)
  const put = (f: number, x: number, y: number, a: number, top: boolean) => {
    if (x < 0 || x >= FW || y < 0 || y >= FH) return
    const i = (y * c.width + f * FW + x) * 4
    if (img.data[i + 3] >= a) return
    img.data[i] = top ? 255 : 228
    img.data[i + 1] = top ? 255 : 238
    img.data[i + 2] = top ? 255 : 244
    img.data[i + 3] = a
  }
  for (let f = 0; f < FRAMES; f++) {
    const strands = 3 + (f % 2)
    let lo = FW,
      hi = 0
    for (let k = 0; k < strands; k++) {
      const y = Math.min(FH - 1, 1 + Math.floor(((k + hash(f, k, seed + 41)) / strands) * (FH - 2)))
      const len = Math.floor(FW * (0.45 + 0.4 * hash(f, k, seed + 42)))
      const x0 = Math.floor((FW - len) * hash(k, f, seed + 43))
      lo = Math.min(lo, x0)
      hi = Math.max(hi, x0 + len)
      for (let x = x0; x < x0 + len; x++) {
        const t = (x - x0) / len
        const end = Math.min(t, 1 - t) * 2
        const gap = noise(x / 3, k * 5 + f * 11, seed + 44)
        if (gap < 0.3) continue
        const strong = end > 0.35 && gap > 0.5
        put(f, x, y, strong ? 150 : 80, y < FH / 2)
        // 丝的上沿偶尔多一像素，看着是一缕缕卷起来的
        if (strong && noise(x / 2, k + f * 3, seed + 45) > 0.68) put(f, x, y - 1, 70, true)
      }
    }
    for (let y = 1; y < FH - 1; y++)
      for (let x = lo + 2; x < hi - 2; x++) if ((x + y) % 2 === 0) put(f, x, y, 34, y < FH / 2)
  }
  ctx.putImageData(img, 0, 0)
  return c
}

/** 也随阵风偏：和烟囱的烟同一个风向（往东），强弱按位置和时间一阵阵起伏 */
function gust(x: number, z: number, seconds: number) {
  return noise((x * 0.98 + z * 0.18) / (120 * PIXEL) - seconds * 0.35, 0.5, 7)
}

interface Wisp {
  x: number
  z: number
  phase: number
  frame: number
  /** 这一缕的大小倍数 */
  size: number
}

export class SpringSteam {
  readonly mesh: THREE.InstancedMesh
  /** 池水映上来的青光（线性色，场景按昼夜设） */
  readonly glow = { value: new THREE.Color(0, 0, 0) }
  private readonly wisps: Wisp[] = []
  private readonly alpha: THREE.InstancedBufferAttribute
  private readonly turn = new THREE.Quaternion()
  private readonly m = new THREE.Matrix4()
  private readonly at = new THREE.Vector3()
  private readonly size = new THREE.Vector3()
  private last = 0

  /** spring 是地面像素上的温泉（见 terrain.ts 的 Ground.spring）；density 按画质减少缕数 */
  constructor(spring: Uint8Array, pw: number, ph: number, seed: number, density = 1) {
    const step = Math.round(Math.sqrt(AREA / density))
    const inside = (x: number, y: number) =>
      x >= EDGE &&
      y >= EDGE &&
      x < pw - EDGE &&
      y < ph - EDGE &&
      [
        [0, 0],
        [EDGE, 0],
        [-EDGE, 0],
        [0, EDGE],
        [0, -EDGE],
      ].every(([dx, dy]) => spring[(y + dy) * pw + x + dx])
    for (let gy = 0; gy < ph; gy += step)
      for (let gx = 0; gx < pw; gx += step) {
        const x = gx + Math.floor(hash(gx, gy, seed + 51) * step),
          y = gy + Math.floor(hash(gx, gy, seed + 52) * step)
        if (!inside(x, y)) continue
        for (let k = 0; k < PER; k++)
          this.wisps.push({
            x: fromPx(x) + PIXEL / 2,
            z: fromPx(y) + PIXEL / 2,
            phase: k / PER + hash(x, y, seed + 53) / PER,
            frame: Math.floor(hash(x + k, y, seed + 54) * FRAMES),
            size: 0.8 + hash(x, y + k, seed + 55) * 0.5,
          })
      }
    const geometry = new THREE.PlaneGeometry(FW * PIXEL, FH * PIXEL)
    geometry.translate(0, (FH * PIXEL) / 2, 0)
    const n = this.wisps.length
    this.alpha = new THREE.InstancedBufferAttribute(new Float32Array(n), 1)
    this.alpha.setUsage(THREE.DynamicDrawUsage)
    geometry.setAttribute('aAlpha', this.alpha)
    geometry.setAttribute(
      'aFrame',
      new THREE.InstancedBufferAttribute(
        Float32Array.from(this.wisps, (w) => w.frame),
        1
      )
    )
    geometry.setAttribute(
      'aFoot',
      new THREE.InstancedBufferAttribute(
        Float32Array.from(this.wisps.flatMap((w) => [w.x, 0, w.z])),
        3
      )
    )
    const material = pixelMaterial(
      new THREE.MeshLambertMaterial({
        map: texture(wispAtlas(seed)),
        transparent: true,
        depthWrite: false,
        side: THREE.DoubleSide,
      })
    )
    const glow = this.glow
    material.onBeforeCompile = (shader) => {
      shader.uniforms.uSteamGlow = glow
      shader.vertexShader =
        'attribute float aAlpha;\nattribute float aFrame;\nattribute vec3 aFoot;\nvarying float vSteamAlpha;\n' +
        shader.vertexShader
          .replace(
            '#include <uv_vertex>',
            `#include <uv_vertex>
  vMapUv.x = (vMapUv.x + aFrame) / ${FRAMES.toFixed(1)};
  vSteamAlpha = aAlpha;`
          )
          .replace(
            '#include <project_vertex>',
            `#include <project_vertex>
  {
    vec4 footClip = projectionMatrix * viewMatrix * vec4(aFoot, 1.0);
    gl_Position.z = footClip.z / footClip.w * gl_Position.w;
  }`
          )
      shader.fragmentShader =
        'uniform vec3 uSteamGlow;\nvarying float vSteamAlpha;\n' +
        shader.fragmentShader
          .replace(
            '#include <map_fragment>',
            '#include <map_fragment>\n  diffuseColor.a *= vSteamAlpha;'
          )
          .replace(
            '#include <emissivemap_fragment>',
            '#include <emissivemap_fragment>\n  totalEmissiveRadiance += uSteamGlow;'
          )
    }
    material.customProgramCacheKey = () => 'spring-steam'
    this.mesh = new THREE.InstancedMesh(geometry, material, n)
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage)
    this.mesh.frustumCulled = false
    this.mesh.renderOrder = 2
    this.step(0)
  }

  get count() {
    return this.wisps.length
  }

  /** seconds 是场景时间；要求减少动画时只在建好时摆一次 */
  step(seconds: number) {
    this.last = seconds
    const alpha = this.alpha.array as Float32Array
    this.wisps.forEach((w, i) => {
      const age = (seconds / LIFE + w.phase) % 1
      const drift = DRIFT * (0.5 + 1.4 * gust(w.x, w.z, seconds))
      const sway = Math.sin(age * 5 + w.phase * 17) * 1.2
      this.at.set(w.x + (age * drift + sway) * PIXEL, age * RISE * PIXEL, w.z)
      // 刚冒出来时又窄又贴着水面，越飘越宽、越扁
      const s = w.size * (0.6 + age * 0.7)
      this.size.set(s * (0.7 + age * 1.1), s * (1 - age * 0.3), 1)
      this.m.compose(this.at, this.turn, this.size)
      this.mesh.setMatrixAt(i, this.m)
      alpha[i] = 0.9 * Math.min(1, age * 5) * (1 - age) ** 1.4
    })
    this.mesh.instanceMatrix.needsUpdate = true
    this.alpha.needsUpdate = true
  }

  /** 和立牌一样按俯角后仰，正对镜头 */
  setTilt(tilt: Tilt) {
    this.turn.setFromEuler(new THREE.Euler(-tilt.pitch, tilt.yaw, 0, 'YXZ'))
    this.step(this.last)
  }
}

/** 池水的青光照到岸上：沿着温泉的岸每隔 GAP 像素一处（地图坐标），夜里在光照图上点一圈青色的光 */
export function springShore(spring: Uint8Array, pw: number, ph: number) {
  const GAP = 14
  const spots: [number, number][] = []
  for (let y = 1; y < ph - 1; y += 2)
    for (let x = 1; x < pw - 1; x += 2) {
      const i = y * pw + x
      if (!spring[i] || (spring[i - 1] && spring[i + 1] && spring[i - pw] && spring[i + pw]))
        continue
      const px = fromPx(x) + PIXEL / 2,
        py = fromPx(y) + PIXEL / 2
      if (spots.every(([sx, sy]) => Math.hypot(sx - px, sy - py) > GAP * PIXEL))
        spots.push([px, py])
    }
  return spots
}
