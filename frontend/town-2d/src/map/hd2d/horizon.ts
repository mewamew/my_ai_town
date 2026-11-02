import * as THREE from 'three'
import { PIXEL } from '../grid'
import { bayer, fbm, hash, rng } from '../pixel/noise'
import type { Tilt } from './layout'
import { texture } from './standee'
import { pixelMaterial } from './pixelSampling'
import { REFLECTION_SKIP } from './reflection'
import type { IsletPalette } from '../themes/types'

// 远景：正交镜头下东西不会因为远而变小，海面不会自己收成一条线，所以在北边（画面上方）
// 一段距离外立一块朝着镜头的天幕，天幕和海面相接处就是海平线。
// 天幕从下往上是海雾色到天色，下沿有两层远山剪影；靠近海平线的海面和远处的小岛逐渐融进海雾。
// 主岛四周另散几座远处的小岛，只画在立体场景里，不在地图上，走不过去；废土里它们是干海床上的台地。

/** 按朝向镜头的地面纵深往海雾色混；方位变化时雾和海平线一起转到远方。 */
const HAZE_HEADER = /* glsl */ `
uniform vec3 uHaze;
uniform float uHorizon;
uniform float uHazeLen;
uniform float uHazeBase;
varying float vHazeZ;
`
const HAZE_APPLY = /* glsl */ `
  float hazeT = clamp(1.0 - (vHazeZ - uHorizon) / uHazeLen, 0.0, 1.0);
  gl_FragColor.rgb = mix(gl_FragColor.rgb, uHaze, max(uHazeBase, hazeT * hazeT * 0.72));
`

export interface HazeUniforms {
  uHaze: { value: THREE.Color }
  uHorizon: { value: number }
  uHazeLen: { value: number }
  uHazeBase: { value: number }
  uHazeDirection: { value: THREE.Vector2 }
}

/** 给一个材质接上海雾；base 是不论远近都有的一层淡雾 */
export function addHaze(
  shader: THREE.WebGLProgramParametersWithUniforms,
  haze: HazeUniforms,
  base = 0
) {
  Object.assign(shader.uniforms, haze, { uHazeBase: { value: base } })
  shader.vertexShader =
    'varying float vHazeZ;\nuniform vec2 uHazeDirection;\n' +
    shader.vertexShader.replace(
      '#include <begin_vertex>',
      '#include <begin_vertex>\n  vHazeZ = dot((modelMatrix * vec4(transformed, 1.0)).xz, uHazeDirection);'
    )
  shader.fragmentShader =
    HAZE_HEADER +
    shader.fragmentShader.replace(
      '#include <dithering_fragment>',
      '#include <dithering_fragment>\n' + HAZE_APPLY
    )
}

/** 天幕：下沿在海平线上，按像素格画出天色渐变和两层远山 */
const SKY_VERTEX = /* glsl */ `
varying vec2 vSky;
void main() {
  vSky = position.xy;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
`
const SKY_FRAGMENT = /* glsl */ `
uniform vec3 uHaze;
uniform vec3 uTop;
uniform vec3 uHill;
uniform float uPixel;
uniform float uSeed;
uniform float uTime;
uniform float uAurora;
uniform float uViewX;
uniform float uViewW;
uniform vec3 uSun;
uniform vec3 uSunColor;
uniform vec3 uMoon;
uniform float uStars;
uniform float uRainbow;
uniform vec3 uBolt;
varying vec2 vSky;
float h1(float x) { return fract(sin(x * 127.1 + uSeed) * 43758.5453); }
float n1(float x) { float i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h1(i), h1(i + 1.0), f); }
float ridge(float x, float scale, float height) {
  return (n1(x / scale) * 0.6 + n1(x / scale * 2.3 + 7.0) * 0.3 + n1(x / scale * 5.1 + 3.0) * 0.1) * height;
}
void main() {
  vec2 p = floor(vSky / uPixel) * uPixel;
  float up = p.y;
  // 天色：海平线附近是海雾色，往上变成天色，档与档之间按像素交错
  float t = clamp(up / 1500.0, 0.0, 1.0);
  float dither = fract(sin(dot(floor(vSky / uPixel), vec2(12.9898, 78.233))) * 43758.5453);
  vec3 c = mix(uHaze, uTop, clamp(floor((sqrt(t) + dither * 0.08) * 8.0) / 8.0, 0.0, 1.0));
  // 星星：按像素格零星几颗，各自明暗闪烁；流星每二十来秒划过一道
  if (uStars > 0.0 && up > 240.0) {
    vec2 cell = floor(vSky / uPixel);
    float h = fract(sin(dot(cell, vec2(41.3, 289.1)) + uSeed) * 43758.5453);
    if (h > 0.9968) {
      float twinkle = 0.55 + 0.45 * sin(uTime * (1.3 + h * 40.0) + h * 300.0);
      c = mix(c, vec3(0.85, 0.9, 1.0), uStars * twinkle * smoothstep(240.0, 520.0, up));
    }
    float k = floor(uTime / 23.0), ft = fract(uTime / 23.0);
    if (ft < 0.07) {
      vec2 start = vec2(uViewX + (h1(k) - 0.5) * uViewW * 0.8, 900.0 + h1(k + 1.0) * 500.0);
      vec2 dir = normalize(vec2(-0.85, -0.35));
      vec2 head = start + dir * (ft / 0.07) * 700.0;
      vec2 rel = p - head;
      float along = dot(rel, -dir), across = abs(dot(rel, vec2(-dir.y, dir.x)));
      if (along > 0.0 && along < 180.0 && across < uPixel)
        c = mix(c, vec3(1.0, 0.97, 0.9), uStars * (1.0 - along / 180.0));
    }
  }
  // 太阳和月亮：贴着海平线的大光盘带一圈晕，夜里一弯月牙
  if (uSun.z > 0.0) {
    float d = length(p - uSun.xy);
    c += uSunColor * uSun.z * (0.55 * exp(-d / 260.0) + 0.25 * exp(-d / 900.0));
    if (d < 46.0) c = mix(c, mix(uSunColor, vec3(1.0, 0.97, 0.9), 0.55), uSun.z);
  }
  if (uMoon.z > 0.0) {
    float d = length(p - uMoon.xy);
    c += vec3(0.55, 0.62, 0.8) * uMoon.z * 0.18 * exp(-d / 220.0);
    if (d < 30.0 && length(p - uMoon.xy - vec2(13.0, 7.0)) > 26.0) c = mix(c, vec3(0.93, 0.94, 1.0), uMoon.z);
  }
  // 横向拉长的像素云：越高的云越大，下沿压一道暗边
  for (int k = 0; k < 3; k++) {
    float fk = float(k);
    float base = 380.0 + fk * 520.0;
    float scale = 1.0 + fk * 0.8;
    float cloud = n1(p.x / (900.0 * scale) + fk * 17.0) * 0.7 + n1(p.x / (260.0 * scale) + fk * 5.0) * 0.3;
    float thick = (cloud - 0.55) * 360.0 * scale;
    float dy = up - base;
    if (thick > 0.0 && dy > -thick * 0.35 && dy < thick) {
      // 云跟着天色明暗：白天发白，夜里只比夜空亮一点
      vec3 white = mix(uTop, vec3(1.0), 0.55 * clamp(length(uTop) * 1.2, 0.12, 1.0));
      c = dy < -thick * 0.2 ? mix(white, uTop, 0.45) : white;
    }
  }
  // 极光：三条竖着垂下的光带，下沿亮绿、往上变淡偏紫，沿横向慢慢摆动、明暗起伏
  if (uAurora > 0.0) {
    for (int k = 0; k < 3; k++) {
      float fk = float(k);
      float base = 700.0 + fk * 260.0 + (n1(p.x / 1800.0 + fk * 9.0 + uTime * 0.02) - 0.5) * 600.0
        + sin(p.x / 900.0 + uTime * 0.15 + fk) * 120.0;
      float len = 260.0 + n1(p.x / 700.0 + fk * 3.0 + uTime * 0.05) * 420.0;
      float dy = up - base;
      if (dy > 0.0 && dy < len) {
        float f = 1.0 - dy / len;
        float flick = 0.55 + 0.45 * sin(p.x / 230.0 + uTime * 0.6 + fk * 2.0);
        c += mix(vec3(0.55, 0.35, 0.9), vec3(0.35, 1.0, 0.65), f) * f * f * flick * uAurora * 0.35;
      }
    }
  }
  // 雨停后的彩虹：七道按像素格的色带，淡淡地挂在天边
  if (uRainbow > 0.0 && up > 0.0) {
    float d = length(p - vec2(uViewX + uViewW * 0.12, -160.0)) - 1150.0;
    if (d > 0.0 && d < 14.0 * uPixel) {
      float b = floor(d / (2.0 * uPixel));
      vec3 bow = b < 1.0 ? vec3(0.55, 0.35, 0.8) : b < 2.0 ? vec3(0.35, 0.4, 0.95) : b < 3.0 ? vec3(0.35, 0.75, 0.95)
        : b < 4.0 ? vec3(0.4, 0.85, 0.45) : b < 5.0 ? vec3(0.95, 0.9, 0.35) : b < 6.0 ? vec3(0.98, 0.6, 0.3) : vec3(0.95, 0.35, 0.3);
      c = mix(c, bow, uRainbow * 0.32 * smoothstep(0.0, 300.0, up));
    }
  }
  // 雷暴：闪的那一下，天上劈下一道折线
  if (uBolt.y > 0.01 && up > 0.0 && up < 1500.0) {
    float xb = uBolt.x + (h1(floor(up / 36.0) + uBolt.z) - 0.5) * 44.0 + (h1(floor(up / 110.0) + uBolt.z * 3.0) - 0.5) * 120.0;
    float dx = abs(p.x - xb);
    c += vec3(0.55, 0.55, 0.85) * uBolt.y * 0.3 * exp(-dx / 90.0);
    if (dx < uPixel * 1.2) c = mix(c, vec3(1.4, 1.38, 1.6), uBolt.y);
  }
  // 远山两层：远的一层更淡、更高低起伏平缓，近的一层稍深；中间有大段空隙露出海平线
  float gapFar = smoothstep(0.3, 0.55, n1(p.x / 5200.0 + 11.0));
  float gapNear = smoothstep(0.45, 0.7, n1(p.x / 3400.0 + 29.0));
  float far = ridge(p.x, 1400.0, 320.0) * gapFar;
  float near = ridge(p.x + 900.0, 700.0, 190.0) * gapNear;
  if (up < far) c = mix(uHaze, uHill, 0.35);
  if (up < near) c = mix(uHaze, uHill, 0.6);
  // 贴着海平线一条亮一点的雾带
  if (up < uPixel * 2.0) c = mix(c, uHaze * 1.08, 0.7);
  gl_FragColor = vec4(c, 1.0);
}
`

/**
 * 远处小岛的贴图，画法和主岛一致：硬边像素，外圈两档实色浅水、一圈白浪，沙滩，
 * 朝南（朝镜头）的岸边露出几格岩壁显出高度，岛上有草地、带明暗的树丛和岩石。
 * 配色没有浅水时不画水圈，透出下面的外圈（干海床）。
 */
function isletCanvas(size: number, seed: number, pal: IsletPalette) {
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = size
  const ctx = canvas.getContext('2d')!
  const img = ctx.createImageData(size, size)
  const put = (i: number, hex: string) => {
    const n = parseInt(hex.slice(1), 16)
    img.data.set([n >> 16, (n >> 8) & 255, n & 255, 255], i * 4)
  }
  const c = size / 2
  // 岛占中间一块，留出外圈给浅水；岩壁往南垂几格
  const cliff = Math.max(2, Math.round(size / 30))
  const land = new Uint8Array(size * size)
  for (let y = 0; y < size; y++)
    for (let x = 0; x < size; x++) {
      const d =
        Math.hypot(x - c, (y - c + cliff) * 1.3) / (c * 0.62) +
        (fbm(x * 2.2, y * 2.2, seed) - 0.5) * 0.8 +
        (fbm(x * 8, y * 8, seed + 1) - 0.5) * 0.2
      if (d < 1) land[y * size + x] = 1
    }
  // 离岛的像素数（到 9 为止），给浅水和白浪用
  const near = new Uint8Array(size * size).fill(99)
  for (let i = 0; i < size * size; i++) if (land[i]) near[i] = 0
  for (let pass = 0; pass < 9; pass++)
    for (let y = 1; y < size - 1; y++)
      for (let x = 1; x < size - 1; x++) {
        const i = y * size + x
        near[i] = Math.min(
          near[i],
          near[i - 1] + 1,
          near[i + 1] + 1,
          near[i - size] + 1,
          near[i + size] + 1
        )
      }
  const isLand = (x: number, y: number) =>
    x >= 0 && y >= 0 && x < size && y < size && land[y * size + x] === 1
  for (let y = 0; y < size; y++)
    for (let x = 0; x < size; x++) {
      const i = y * size + x
      // 岩壁：这一格是水，但往北几格内有陆地，陆地的南岸在它上面
      let face = 0
      for (let k = 1; k <= cliff && !face; k++) if (!land[i] && isLand(x, y - k)) face = k
      if (face) {
        put(i, face === 1 ? pal.cliff[0] : face === cliff ? pal.cliff[2] : pal.cliff[1])
        continue
      }
      if (!land[i]) {
        const n = near[i]
        if (!pal.shallows) continue
        const [shallow, deeper, foam] = pal.shallows
        if (n <= 1) put(i, foam)
        else if (n <= 3 || (n === 4 && bayer(x, y) < 0.5)) put(i, shallow)
        else if (n <= 7 || (n === 8 && bayer(x, y) < 0.5)) put(i, deeper)
        continue
      }
      const edge = !isLand(x - 1, y) || !isLand(x + 1, y) || !isLand(x, y - 1) || !isLand(x, y + 1)
      const shore = edge || !isLand(x - 2, y) || !isLand(x + 2, y) || !isLand(x, y - 2)
      if (shore) {
        put(i, hash(x, y, seed) < 0.5 ? pal.shore[0] : pal.shore[1])
        continue
      }
      const g = fbm(x * 3, y * 3, seed + 2)
      if (fbm(x * 5, y * 5, seed + 3) > 0.56) {
        // 树丛：左上亮、右下暗，底下一格影子
        const lit = !isLand(x - 1, y - 1) || fbm((x - 1) * 5, (y - 1) * 5, seed + 3) <= 0.56
        const dark = fbm(x * 5, (y + 1) * 5, seed + 3) <= 0.56
        const [light, shade, mid, low] = pal.scrub
        put(i, lit ? light : dark ? shade : g > 0.55 ? mid : low)
      } else if (fbm(x * 4, y * 4, seed + 4) > 0.68)
        put(i, hash(x, y, seed + 5) < 0.3 ? pal.rock[0] : pal.rock[1])
      else put(i, g > 0.5 ? pal.ground[0] : pal.ground[1])
    }
  ctx.putImageData(img, 0, 0)
  return canvas
}

export class Horizon {
  readonly haze: HazeUniforms
  private readonly sky: THREE.ShaderMaterial
  private readonly backdrop: THREE.Mesh

  /** box 是主岛（含海岸）在世界坐标里的范围 */
  constructor(
    scene: THREE.Scene,
    private readonly box: { x0: number; z0: number; x1: number; z1: number },
    seed: number,
    private readonly islet: IsletPalette
  ) {
    const w = box.x1 - box.x0,
      h = box.z1 - box.z0
    // 海平线在主岛北边约一个岛深处；海雾从主岛北岸往北四分之一处开始，越往海平线越浓
    const horizon = box.z0 - Math.max(2400, h * 0.9)
    this.haze = {
      // 海雾、高处天色、远山色由 setColors 按风格包和时间设置
      uHaze: { value: new THREE.Color() },
      uHorizon: { value: horizon },
      uHazeLen: { value: (box.z0 - horizon) * 0.75 },
      uHazeBase: { value: 0 },
      uHazeDirection: { value: new THREE.Vector2(0, 1) },
    }
    this.sky = new THREE.ShaderMaterial({
      vertexShader: SKY_VERTEX,
      fragmentShader: SKY_FRAGMENT,
      uniforms: {
        uHaze: this.haze.uHaze,
        uTop: { value: new THREE.Color() },
        uHill: { value: new THREE.Color() },
        uPixel: { value: PIXEL },
        uSeed: { value: seed % 1000 },
        uTime: { value: 0 },
        uAurora: { value: 0 },
        uViewX: { value: 0 },
        uViewW: { value: 1000 },
        uSun: { value: new THREE.Vector3() },
        uSunColor: { value: new THREE.Color() },
        uMoon: { value: new THREE.Vector3() },
        uStars: { value: 0 },
        uRainbow: { value: 0 },
        uBolt: { value: new THREE.Vector3() },
      },
      fog: false,
    })
    const span = Math.max(w, h) * 40
    const geometry = new THREE.PlaneGeometry(span, 200000)
    geometry.translate(0, 100000, 0)
    this.backdrop = new THREE.Mesh(geometry, this.sky)
    this.backdrop.position.set((box.x0 + box.x1) / 2, 0, horizon)
    // 天幕不进倒影：水里没映着东西的地方由材质自己映天色
    this.backdrop.layers.set(REFLECTION_SKIP)
    scene.add(this.backdrop)
    this.addIslets(scene, box, horizon, seed)
  }

  /** 天幕始终正对镜头：绕下沿按俯角转 */
  setTilt(tilt: Tilt) {
    const { box } = this
    const cx = (box.x0 + box.x1) / 2,
      cz = (box.z0 + box.z1) / 2
    const depth =
      Math.abs(tilt.yawSin) * (box.x1 - box.x0) + Math.abs(tilt.yawCos) * (box.z1 - box.z0)
    const beyond = Math.max(2400, depth * 0.9)
    const distance = depth / 2 + beyond
    this.backdrop.position.set(cx - tilt.yawSin * distance, 0, cz - tilt.yawCos * distance)
    this.backdrop.rotation.set(-tilt.pitch, tilt.yaw, 0, 'YXZ')
    this.haze.uHazeDirection.value.set(tilt.yawSin, tilt.yawCos)
    this.haze.uHorizon.value = cx * tilt.yawSin + cz * tilt.yawCos - distance
    this.haze.uHazeLen.value = beyond * 0.75
  }

  /** 镜头看着的地方（世界坐标）和视野宽（世界单位）：天幕上的日月、彩虹、流星摆在看得见的地方 */
  setView(x: number, z: number, width: number) {
    const b = this.backdrop.position,
      yaw = this.backdrop.rotation.y
    this.sky.uniforms.uViewX.value = (x - b.x) * Math.cos(yaw) - (z - b.z) * Math.sin(yaw)
    this.sky.uniforms.uViewW.value = width
  }

  /** 天上的东西。side：太阳在视野里偏左（-1）还是偏右（1）；elevation：太阳高度（-1～1）；
   *  sun、moon、stars、rainbow 是各自的显隐（0～1）；bolt 是闪电亮度，boltSeed 区分每一下 */
  setSky(o: {
    side: number
    elevation: number
    sun: number
    sunColor: THREE.Color
    moon: number
    stars: number
    rainbow: number
    bolt: number
    boltSeed: number
  }) {
    const u = this.sky.uniforms
    const view = u.uViewX.value as number,
      width = u.uViewW.value as number
    ;(u.uSun.value as THREE.Vector3).set(
      view + o.side * width * 0.38,
      (o.elevation + 0.03) * 1600,
      o.sun
    )
    ;(u.uSunColor.value as THREE.Color).copy(o.sunColor)
    ;(u.uMoon.value as THREE.Vector3).set(view + width * 0.3, 980, o.moon)
    u.uStars.value = o.stars
    u.uRainbow.value = o.rainbow
    const r = Math.abs(Math.sin(o.boltSeed * 12.9898) * 43758.5453) % 1
    ;(u.uBolt.value as THREE.Vector3).set(view + (r - 0.5) * width * 0.7, o.bolt, o.boltSeed % 97)
  }

  /** 太阳在天幕上那一点落到海平线上的世界坐标（x, z）：海面的日光路径朝着它 */
  sunOnHorizon(): [number, number] {
    const b = this.backdrop.position,
      yaw = this.backdrop.rotation.y
    const u = (this.sky.uniforms.uSun.value as THREE.Vector3).x
    return [b.x + u * Math.cos(yaw), b.z - u * Math.sin(yaw)]
  }

  /** 极光强度（0 是没有）；场景按夜色和风格设 */
  setAurora(strength: number) {
    this.sky.uniforms.uAurora.value = strength
  }

  /** 天幕上会动的东西（极光）按秒推进 */
  step(seconds: number) {
    this.sky.uniforms.uTime.value = seconds
  }

  /** haze 是海雾色（和场景的雾同色），top 是高处的天色，hill 是远山色 */
  setColors(haze: THREE.Color, top: THREE.Color, hill: THREE.Color) {
    this.haze.uHaze.value.copy(haze)
    ;(this.sky.uniforms.uTop.value as THREE.Color).copy(top)
    ;(this.sky.uniforms.uHill.value as THREE.Color).copy(hill)
  }

  /** 主岛周围几座小岛：北边往海平线方向放得多，东西两侧各一两座；和主岛、彼此之间都不挨着 */
  private addIslets(
    scene: THREE.Scene,
    box: { x0: number; z0: number; x1: number; z1: number },
    horizon: number,
    seed: number
  ) {
    const random = rng(seed + 400)
    const cx = (box.x0 + box.x1) / 2,
      w = box.x1 - box.x0
    const placed: [number, number, number][] = []
    for (let tries = 0; tries < 200 && placed.length < 6; tries++) {
      const size = Math.round(70 + random() * 150) * PIXEL
      const x = cx + (random() - 0.5) * (w + 6000)
      const z = horizon + size + random() * (box.z1 + 1200 - horizon - size)
      const pad = size * 0.6 + 700
      const touchesMain =
        x > box.x0 - pad && x < box.x1 + pad && z > box.z0 - pad && z < box.z1 + pad
      if (
        touchesMain ||
        placed.some(([px, pz, ps]) => Math.hypot(px - x, pz - z) < (ps + size) * 0.8)
      )
        continue
      placed.push([x, z, size])
    }
    placed.forEach(([x, z, full], k) => {
      // 正交镜头下远处的东西不会变小：越靠近海平线的岛画得越小，看得出远近
      const far = Math.min(1, Math.max(0, (box.z0 - z) / (box.z0 - horizon)))
      const size = Math.round((full * (1 - 0.5 * far)) / PIXEL) * PIXEL
      const map = texture(isletCanvas(Math.round(size / PIXEL), seed + 500 + k * 17, this.islet))
      const material = pixelMaterial(new THREE.MeshLambertMaterial({ map, alphaTest: 0.5 }))
      material.onBeforeCompile = (shader) => addHaze(shader, this.haze)
      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(size, size), material)
      mesh.rotation.x = -Math.PI / 2
      mesh.position.set(x, 0.5, z)
      // 平铺在海上的小岛不进倒影
      mesh.layers.set(REFLECTION_SKIP)
      mesh.receiveShadow = true
      scene.add(mesh)
    })
  }
}
