import * as THREE from 'three'
import { PIXEL } from '../grid'
import { rng } from '../pixel/noise'

// 花瓣：从花树的花冠里飘下来，打着旋往下风方向落，落地前淡掉；池面上另有一些浮着的花瓣，慢慢打转。
// 每片一个地图像素大的方点，不透明；明暗由场景按天光给（入夜再加一份灯笼的暖光，不然是花冠上的一个个黑点）。
// 运动全在着色器里，主线程只更新时间。

export interface PetalSource {
  /** 树根（地图坐标）、花冠半径和花冠离地的高度范围（地图单位） */
  x: number
  y: number
  r: number
  low: number
  high: number
  count: number
}

const vertexShader = /* glsl */ `
attribute float phase;
attribute float kind;
attribute float tint;
uniform float time;
uniform float wind;
uniform vec2 windDir;
uniform float unitPx;
varying float vAlpha;
varying float vTint;
void main() {
  vec3 p = position;
  float afloat = step(0.5, kind);
  // 飘落：一生 9～14 秒，从花冠落到地面
  float rate = mix(0.07, 0.11, fract(phase * 7.3));
  float life = fract(time * rate + phase);
  float fall = life * life * 0.35 + life * 0.65;
  vec3 falling = vec3(
    sin(time * 1.1 + phase * 40.0) * ${(2.2 * PIXEL).toFixed(1)} * (0.4 + life)
      + windDir.x * (0.5 + wind * 2.0) * life * ${(26 * PIXEL).toFixed(1)},
    -position.y * fall,
    cos(time * 0.9 + phase * 31.0) * ${(1.6 * PIXEL).toFixed(1)}
      + windDir.y * (0.5 + wind * 2.0) * life * ${(26 * PIXEL).toFixed(1)});
  // 浮在水面：绕着一个小圈慢慢漂
  vec3 floating = vec3(
    sin(time * 0.11 + phase * 50.0) * ${(3 * PIXEL).toFixed(1)},
    0.0,
    cos(time * 0.09 + phase * 37.0) * ${(2 * PIXEL).toFixed(1)});
  p += mix(falling, floating, afloat);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
  float fade = smoothstep(0.0, 0.08, life) * (1.0 - smoothstep(0.9, 1.0, life));
  float near = smoothstep(0.1, 0.3, unitPx);
  vAlpha = mix(fade, 0.9, afloat) * near;
  vTint = tint;
  gl_PointSize = max(1.0, ${PIXEL.toFixed(1)} * unitPx);
}`

const fragmentShader = /* glsl */ `
uniform vec3 light;
uniform vec3 pale;
uniform vec3 deep;
varying float vAlpha;
varying float vTint;
void main() {
  if (vAlpha < 0.5) discard;
  gl_FragColor = vec4(mix(deep, pale, vTint) * light, 1.0);
}`

export class Petals {
  readonly points: THREE.Points
  private readonly material: THREE.ShaderMaterial

  /** afloat 是池面上浮着花瓣的位置（地图坐标）；pale、deep 是花瓣的浅色和深色 */
  constructor(
    sources: PetalSource[],
    afloat: [number, number][],
    pale: string,
    deep: string,
    seed: number
  ) {
    const random = rng(seed + 61)
    const falling = sources.reduce((n, s) => n + s.count, 0)
    const count = falling + afloat.length
    const pos = new Float32Array(count * 3),
      phase = new Float32Array(count),
      kind = new Float32Array(count),
      tint = new Float32Array(count)
    let i = 0
    for (const s of sources)
      for (let k = 0; k < s.count; k++, i++) {
        const a = random() * Math.PI * 2,
          d = Math.sqrt(random()) * s.r
        pos[i * 3] = s.x + Math.cos(a) * d
        pos[i * 3 + 1] = s.low + random() * (s.high - s.low)
        pos[i * 3 + 2] = s.y + Math.sin(a) * d * 0.5
        phase[i] = random()
        tint[i] = random()
      }
    for (const [x, y] of afloat) {
      pos[i * 3] = x
      pos[i * 3 + 1] = 0.6
      pos[i * 3 + 2] = y
      phase[i] = random()
      kind[i] = 1
      tint[i] = 0.3 + random() * 0.7
      i++
    }
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3))
    g.setAttribute('phase', new THREE.BufferAttribute(phase, 1))
    g.setAttribute('kind', new THREE.BufferAttribute(kind, 1))
    g.setAttribute('tint', new THREE.BufferAttribute(tint, 1))
    this.material = new THREE.ShaderMaterial({
      vertexShader,
      fragmentShader,
      uniforms: {
        time: { value: 0 },
        wind: { value: 0.3 },
        windDir: { value: new THREE.Vector2(1, 0) },
        unitPx: { value: 1 },
        light: { value: new THREE.Color(1, 1, 1) },
        pale: { value: new THREE.Color(pale) },
        deep: { value: new THREE.Color(deep) },
      },
      depthWrite: false,
    })
    this.points = new THREE.Points(g, this.material)
    this.points.frustumCulled = false
  }

  /** 此刻的环境光（线性色），夜里花瓣跟着暗下去 */
  setLight(light: THREE.Color) {
    ;(this.material.uniforms.light.value as THREE.Color).copy(light)
  }

  setWind(strength: number, dir: THREE.Vector2) {
    this.material.uniforms.wind.value = strength
    ;(this.material.uniforms.windDir.value as THREE.Vector2).copy(dir)
  }

  setScale(unitPx: number) {
    this.material.uniforms.unitPx.value = unitPx
  }

  step(now: number) {
    this.material.uniforms.time.value = now / 1000
  }
}
