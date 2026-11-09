import * as THREE from 'three'
import { fromPx, PIXEL } from '../grid'
import { OPEN } from '../pixel/terrain'
import { rng } from '../pixel/noise'
import type { MapTheme } from '../themes/types'

// 空气里的微粒：白天在阳光里慢慢上飘的浮尘（傍晚最明显，下雨时没有），夜里公园和花园的萤火虫。
// 废土的浮尘更浓、偏土黄，被风吹着横着走，没有萤火虫。冰雪里是日夜都在往下飘的小雪。
// 每颗有自己的生命周期，淡入、飘一段、淡出；运动在着色器里算，主线程只更新时间。

const DUST = 500
const FIREFLIES = 140
/** 浮尘和萤火虫的大小（世界单位）；镜头拉远到一个世界单位不足这么多设备像素时逐渐隐去 */
const DUST_SIZE = 1.6 * PIXEL
const FIREFLY_SIZE = 2.6 * PIXEL
const HIDE_BELOW = 0.12
const SHOW_ABOVE = 0.35

const vertexShader = /* glsl */ `
attribute float phase;
attribute float kind;
attribute float size;
uniform float time;
uniform float day;
uniform float golden;
uniform float cloud;
uniform float unitPx;
uniform vec3 dustColor;
uniform float dustStrength;
uniform float nightStrength;
uniform float drift;
uniform float lift;
varying float vAlpha;
varying vec3 vColor;
varying float vKind;
void main() {
  vec3 p = position;
  float firefly = step(0.5, kind);
  // 一生约 15～20 秒，两头淡入淡出
  float life = fract(time * mix(0.05, 0.07, firefly) + phase);
  float fade = sin(life * 3.14159);
  // 浮尘：往上飘，随风横向漂一点
  vec3 dust = vec3(
    sin(time * 0.13 + phase * 6.28) * ${3 * PIXEL}.0 + life * drift,
    life * lift,
    cos(time * 0.11 + phase * 9.0) * ${3 * PIXEL}.0);
  // 萤火虫：在原地附近绕着游走
  vec3 wander = vec3(
    sin(time * 0.7 + phase * 20.0) * ${5 * PIXEL}.0 + sin(time * 1.9 + phase * 7.0) * ${PIXEL}.0,
    sin(time * 0.9 + phase * 13.0) * ${2 * PIXEL}.0,
    cos(time * 0.6 + phase * 17.0) * ${5 * PIXEL}.0);
  p += mix(dust, wander, firefly);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
  float near = smoothstep(${HIDE_BELOW}, ${SHOW_ABOVE}, unitPx);
  float blink = pow(0.5 + 0.5 * sin(time * 2.3 + phase * 40.0), 3.0);
  float dustAlpha = fade * (day * (dustStrength + golden) + (1.0 - day) * nightStrength) * (1.0 - cloud) * 0.9;
  float fireflyAlpha = fade * (1.0 - day) * (0.25 + 0.75 * blink);
  vAlpha = mix(dustAlpha, fireflyAlpha, firefly) * near;
  vColor = mix(mix(dustColor, vec3(1.0, 0.78, 0.5), golden), vec3(0.75, 1.0, 0.35), firefly);
  vKind = firefly;
  gl_PointSize = max(1.5, size * unitPx);
}`

const fragmentShader = /* glsl */ `
varying float vAlpha;
varying vec3 vColor;
varying float vKind;
void main() {
  float d = length(gl_PointCoord - 0.5) * 2.0;
  if (d > 1.0) discard;
  // 浮尘是柔和的圆点；萤火虫是亮核加一圈淡光晕
  float dust = smoothstep(1.0, 0.0, d);
  float firefly = smoothstep(0.35, 0.0, d) + smoothstep(1.0, 0.2, d) * 0.35;
  gl_FragColor = vec4(vColor * vAlpha * mix(dust, firefly, vKind), 1.0);
}`

export class Motes {
  readonly points: THREE.Points
  private readonly material: THREE.ShaderMaterial

  constructor(
    terrain: { width: number; height: number; open: Uint8Array },
    seed: number,
    motes: MapTheme['motes']
  ) {
    const { width: pw, height: ph, open } = terrain
    const random = rng(seed + 5)
    const land: number[] = [],
      green: number[] = []
    for (let i = 0; i < pw * ph; i += 17) {
      if (open[i]) land.push(i)
      if (
        motes.fireflies &&
        (open[i] === OPEN.park || open[i] === OPEN.lawn || open[i] === OPEN.garden)
      )
        green.push(i)
    }
    const count = DUST + (green.length ? FIREFLIES : 0)
    const pos = new Float32Array(count * 3),
      phase = new Float32Array(count),
      kind = new Float32Array(count),
      size = new Float32Array(count)
    for (let i = 0; i < count; i++) {
      const firefly = i >= DUST
      const pool = firefly ? green : land
      const p = pool.length
        ? pool[Math.floor(random() * pool.length)]
        : Math.floor(random() * pw * ph)
      pos[i * 3] = fromPx(p % pw)
      // 往下落的微粒从高处起步，落完一生刚好到地面附近
      pos[i * 3 + 1] =
        (firefly ? 2 + random() * 8 : 2 + Math.max(0, -motes.lift) + random() * 16) * PIXEL
      pos[i * 3 + 2] = fromPx(Math.floor(p / pw))
      phase[i] = random()
      kind[i] = firefly ? 1 : 0
      size[i] = (firefly ? FIREFLY_SIZE : DUST_SIZE) * (0.6 + random() * 0.8)
    }
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3))
    g.setAttribute('phase', new THREE.BufferAttribute(phase, 1))
    g.setAttribute('kind', new THREE.BufferAttribute(kind, 1))
    g.setAttribute('size', new THREE.BufferAttribute(size, 1))
    this.material = new THREE.ShaderMaterial({
      vertexShader,
      fragmentShader,
      uniforms: {
        time: { value: 0 },
        day: { value: 1 },
        golden: { value: 0 },
        cloud: { value: 0 },
        unitPx: { value: 1 },
        dustColor: { value: new THREE.Vector3(...motes.dust) },
        dustStrength: { value: motes.strength },
        nightStrength: { value: motes.night },
        drift: { value: motes.drift * PIXEL },
        lift: { value: motes.lift * PIXEL },
      },
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    })
    this.points = new THREE.Points(g, this.material)
    // 飘动范围超出原始包围盒，不做视锥裁剪
    this.points.frustumCulled = false
  }

  /** day 为 1 是白天、0 是夜里；golden 是傍晚暖光的程度；cloud 为 0 晴到 1 雷雨 */
  setLight(day: number, golden: number, cloud: number) {
    const u = this.material.uniforms
    u.day.value = day
    u.golden.value = golden
    u.cloud.value = cloud
  }

  /** 一个世界单位占几个设备像素，粒子大小按它换算，太小时隐去 */
  setScale(unitPx: number) {
    this.material.uniforms.unitPx.value = unitPx
  }

  step(now: number) {
    this.material.uniforms.time.value = now / 1000
  }
}
