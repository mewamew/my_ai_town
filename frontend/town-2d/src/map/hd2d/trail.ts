import * as THREE from 'three'
import { FullScreenQuad } from 'three/addons/postprocessing/Pass.js'
import { MARGIN, PIXEL } from '../grid'

// 踩踏图：一张地面空间的低分辨率图（两个地面像素一格），记下人走过的地方。
// R 是踩倒的草（几秒内慢慢立起来）、G 是雪地上的脚印（下雪时被新雪盖上，不下雪时留很久）、
// B 是浅水里的涟漪（边散开边淡，看上去是一圈圈往外走）。每画一帧前先按经过的时间衰减，再盖上新的脚印；
// 人每走一步按左右脚交替盖一个印。只在有人走动、或者图上还有没散完的印时更新。

const DECAY = /* glsl */ `
uniform sampler2D tPrev;
uniform vec2 texel;
uniform vec3 keep;
uniform float spread;
varying vec2 vUv;
void main() {
  vec4 c = texture2D(tPrev, vUv);
  // 涟漪往外散：取四邻的平均混进来
  float around = (texture2D(tPrev, vUv + vec2(texel.x, 0.0)).b + texture2D(tPrev, vUv - vec2(texel.x, 0.0)).b
    + texture2D(tPrev, vUv + vec2(0.0, texel.y)).b + texture2D(tPrev, vUv - vec2(0.0, texel.y)).b) * 0.25;
  c.b = mix(c.b, around, spread);
  gl_FragColor = vec4(c.rgb * keep, 1.0);
}`

const STAMP_VERTEX = /* glsl */ `
attribute vec3 stamp;
uniform vec2 origin;
uniform vec2 size;
uniform float pointPx;
varying vec3 vStamp;
void main() {
  vStamp = stamp;
  gl_Position = vec4((position.xz - origin) / size * 2.0 - 1.0, 0.0, 1.0);
  gl_PointSize = pointPx;
}`
const STAMP_FRAGMENT = /* glsl */ `
varying vec3 vStamp;
void main() {
  float d = length(gl_PointCoord - 0.5) * 2.0;
  if (d > 1.0) discard;
  gl_FragColor = vec4(vStamp * (1.0 - d * d), 1.0);
}`

const VERTEX =
  'varying vec2 vUv;void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}'

/** 一个脚印：地图坐标，在不在水里 */
export interface Footstep {
  x: number
  y: number
  water: boolean
}

const MAX_STAMPS = 128

export class Trail {
  private targets: [THREE.WebGLRenderTarget, THREE.WebGLRenderTarget]
  private readonly decay = new FullScreenQuad(
    new THREE.ShaderMaterial({
      vertexShader: VERTEX,
      fragmentShader: DECAY,
      uniforms: {
        tPrev: { value: null },
        texel: { value: new THREE.Vector2() },
        keep: { value: new THREE.Vector3(1, 1, 1) },
        spread: { value: 0 },
      },
      depthTest: false,
      depthWrite: false,
    })
  )
  private readonly stampScene = new THREE.Scene()
  private readonly stampCamera = new THREE.Camera()
  private readonly stampGeometry = new THREE.BufferGeometry()
  private readonly stampMaterial: THREE.ShaderMaterial
  private readonly pending: Footstep[] = []
  /** 最后一次盖印的时刻：之后五分钟内接着衰减（不下雪时的脚印最慢，五分钟后看不出来了） */
  private lastStamp = -Infinity
  private last = performance.now()
  /** 材质里取踩踏图用的 */
  readonly uniforms: {
    uTrail: { value: THREE.Texture }
    uTrailOrigin: { value: THREE.Vector2 }
    uTrailSize: { value: THREE.Vector2 }
  }
  enabled = true

  constructor(pw: number, ph: number) {
    const w = Math.ceil(pw / 2),
      h = Math.ceil(ph / 2)
    const make = () =>
      new THREE.WebGLRenderTarget(w, h, {
        type: THREE.HalfFloatType,
        depthBuffer: false,
        magFilter: THREE.LinearFilter,
        minFilter: THREE.LinearFilter,
      })
    this.targets = [make(), make()]
    const origin = new THREE.Vector2(-MARGIN, -MARGIN),
      size = new THREE.Vector2(pw * PIXEL, ph * PIXEL)
    ;(this.decay.material as THREE.ShaderMaterial).uniforms.texel.value.set(1 / w, 1 / h)
    this.stampGeometry.setAttribute(
      'position',
      new THREE.BufferAttribute(new Float32Array(MAX_STAMPS * 3), 3)
    )
    this.stampGeometry.setAttribute(
      'stamp',
      new THREE.BufferAttribute(new Float32Array(MAX_STAMPS * 3), 3)
    )
    this.stampMaterial = new THREE.ShaderMaterial({
      vertexShader: STAMP_VERTEX,
      fragmentShader: STAMP_FRAGMENT,
      uniforms: {
        origin: { value: origin },
        size: { value: size },
        pointPx: { value: 3 },
      },
      blending: THREE.AdditiveBlending,
      depthTest: false,
      depthWrite: false,
      transparent: true,
    })
    const points = new THREE.Points(this.stampGeometry, this.stampMaterial)
    points.frustumCulled = false
    this.stampScene.add(points)
    this.uniforms = {
      uTrail: { value: this.targets[0].texture },
      uTrailOrigin: { value: origin },
      uTrailSize: { value: size },
    }
  }

  /** 记下这一帧新踩的脚印，下一次 update 时盖上 */
  add(steps: Footstep[]) {
    if (!this.enabled) return
    for (const s of steps) if (this.pending.length < MAX_STAMPS) this.pending.push(s)
  }

  /** 衰减、盖新印；snowing 时脚印很快被盖上，raining 时涟漪多一些。返回图有没有变 */
  update(renderer: THREE.WebGLRenderer, snowing: boolean) {
    const now = performance.now()
    const dt = Math.min(1, (now - this.last) / 1000)
    this.last = now
    if (!this.enabled || (now - this.lastStamp > 300000 && !this.pending.length)) return false
    if (this.pending.length) this.lastStamp = now
    const [read, write] = this.targets
    const d = (this.decay.material as THREE.ShaderMaterial).uniforms
    d.tPrev.value = read.texture
    // 草几秒内立起来；脚印不下雪时留几分钟，下雪时半分钟内被盖上；涟漪一两秒散完
    d.keep.value.set(Math.exp(-dt / 2.5), Math.exp(-dt / (snowing ? 25 : 240)), Math.exp(-dt / 0.9))
    d.spread.value = Math.min(1, dt * 6)
    const before = renderer.getRenderTarget()
    renderer.setRenderTarget(write)
    this.decay.render(renderer)
    if (this.pending.length) {
      const pos = this.stampGeometry.getAttribute('position') as THREE.BufferAttribute
      const stamp = this.stampGeometry.getAttribute('stamp') as THREE.BufferAttribute
      this.pending.forEach((s, i) => {
        pos.setXYZ(i, s.x, 0, s.y)
        stamp.setXYZ(i, s.water ? 0 : 1, s.water ? 0 : 1, s.water ? 1 : 0)
      })
      pos.needsUpdate = stamp.needsUpdate = true
      this.stampGeometry.setDrawRange(0, this.pending.length)
      this.pending.length = 0
      renderer.autoClear = false
      renderer.render(this.stampScene, this.stampCamera)
      renderer.autoClear = true
    }
    renderer.setRenderTarget(before)
    this.targets = [write, read]
    this.uniforms.uTrail.value = write.texture
    return true
  }

  dispose() {
    for (const t of this.targets) t.dispose()
    this.decay.material.dispose()
    this.decay.dispose()
    this.stampGeometry.dispose()
    this.stampMaterial.dispose()
  }
}
