import * as THREE from 'three'
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js'
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js'
import { CopyShader } from 'three/addons/shaders/CopyShader.js'
import type { LookParams } from '../themes/types'

// 后期：真实表面深度控制前后景离焦，叠加原有上下边缘移轴模糊，再调色和暗角。
// 调色在色调映射之前的线性空间里做，对比度以中灰 0.18 为中心按幂次拉开，暗部不会变成负数。

/** 颜色和深度来自同一次场景绘制，保留树、村民的 alphaTest 和立牌自定义的深度。
 *  不用统一深度材质重画，否则透明边缘会变成矩形，人物也会和房屋遮挡不一致。
 *  独立目标在后续模糊期间保持只读，避免 composer 交换缓冲时覆盖深度或产生读写反馈。 */
export class SceneDepthPass extends RenderPass {
  captureDepth = true
  private readonly target = new THREE.WebGLRenderTarget(1, 1, {
    type: THREE.HalfFloatType,
    depthTexture: new THREE.DepthTexture(1, 1, THREE.UnsignedIntType),
  })
  private readonly copy = new ShaderPass(CopyShader)

  constructor(scene: THREE.Scene, camera: THREE.Camera) {
    super(scene, camera)
    this.copy.material.depthTest = false
    this.copy.material.depthWrite = false
    this.copy.material.blending = THREE.NoBlending
  }

  get depthTexture() {
    return this.target.depthTexture
  }

  override setSize(width: number, height: number) {
    this.target.setSize(width, height)
  }

  override render(
    renderer: THREE.WebGLRenderer,
    writeBuffer: THREE.WebGLRenderTarget,
    readBuffer: THREE.WebGLRenderTarget,
    deltaTime: number,
    maskActive: boolean
  ) {
    if (!this.captureDepth) {
      super.render(renderer, writeBuffer, readBuffer, deltaTime, maskActive)
      return
    }
    super.render(renderer, writeBuffer, this.target, deltaTime, maskActive)
    this.copy.render(renderer, readBuffer, this.target, deltaTime, maskActive)
  }

  override dispose() {
    this.copy.dispose()
    this.target.dispose()
  }
}

const vertexShader =
  'varying vec2 vUv;void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}'

/** 移轴的清晰带在画面里的高度（从下往上 0～1）：地图没被面板盖住时稍低于正中 */
export const TILT_FOCUS = 0.48

/** 横竖各跑一遍的景深模糊，amount/depthAmount 是每一采样步的设备像素。
 *  深度用正交相机的线性距离，清晰区跟着未被面板遮住的地面中心走。 */
export const tiltShader = {
  uniforms: {
    tDiffuse: { value: null },
    tDepth: { value: null },
    dir: { value: new THREE.Vector2(1, 0) },
    amount: { value: 2.6 },
    depthAmount: { value: 2.4 },
    cameraNear: { value: 0 },
    cameraFar: { value: 1 },
    focusDepth: { value: 0 },
    focusRange: { value: 1 },
    depthFalloff: { value: 1 },
    focus: { value: TILT_FOCUS },
    band: { value: 0.16 },
    res: { value: new THREE.Vector2(1, 1) },
  },
  vertexShader,
  fragmentShader: /* glsl */ `
uniform sampler2D tDiffuse;
uniform sampler2D tDepth;
uniform vec2 dir;
uniform float amount;
uniform float depthAmount;
uniform float cameraNear;
uniform float cameraFar;
uniform float focusDepth;
uniform float focusRange;
uniform float depthFalloff;
uniform float focus;
uniform float band;
uniform vec2 res;
varying vec2 vUv;
float surfaceDepth(vec2 uv) {
  return mix(cameraNear, cameraFar, texture2D(tDepth, uv).r);
}
void main() {
  float depth = surfaceDepth(vUv);
  float edgeBlur = smoothstep(band, band + 0.38, abs(vUv.y - focus)) * amount;
  float depthBlur = smoothstep(focusRange, focusRange + depthFalloff,
    abs(depth - focusDepth)) * depthAmount;
  float radius = max(edgeBlur, depthBlur);
  vec4 color = vec4(0.);
  float total = 0.;
  for (int i = -7; i <= 7; i++) {
    vec2 uv = clamp(vUv + dir * float(i) * radius / res, 0.5 / res, 1. - 0.5 / res);
    float weight = exp(-float(i * i) / 24.);
    // 远景颜色不穿过清晰人物、屋檐与树叶的轮廓；近景仍保留柔和离焦。
    float boundary = smoothstep(focusRange * 0.5, focusRange * 2.,
      abs(surfaceDepth(uv) - depth));
    weight *= mix(1., 0.08, boundary);
    color += texture2D(tDiffuse, uv) * weight;
    total += weight;
  }
  gl_FragColor = color / total;
}`,
}

/** 调色：饱和、整体偏色（tint）、只乘在暗部的偏色（shade，傍晚暗处偏青、亮处保持暖）、黑位、对比、暗角 */
export const gradeShader = {
  uniforms: {
    tDiffuse: { value: null },
    tint: { value: new THREE.Color(1, 1, 1) },
    shade: { value: new THREE.Color(1, 1, 1) },
    sat: { value: 1.18 },
    vignette: { value: 0.55 },
    lift: { value: new THREE.Color(0, 0, 0) },
    contrast: { value: 1 },
  },
  vertexShader,
  fragmentShader: /* glsl */ `
uniform sampler2D tDiffuse;
uniform vec3 tint;
uniform vec3 shade;
uniform float sat;
uniform float vignette;
uniform vec3 lift;
uniform float contrast;
varying vec2 vUv;
void main() {
  vec4 c = texture2D(tDiffuse, vUv);
  float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
  c.rgb = mix(vec3(l), c.rgb, sat) * tint;
  c.rgb *= mix(shade, vec3(1.0), smoothstep(0.02, 0.45, l));
  c.rgb += lift;
  c.rgb = 0.18 * pow(max(c.rgb, vec3(0.0)) / 0.18, vec3(contrast));
  vec2 q = vUv - 0.5;
  q.x *= 1.25;
  c.rgb *= mix(1.0, smoothstep(0.95, 0.25, length(q)), vignette);
  gl_FragColor = c;
}`,
}

/** 3D LUT 的边长 */
const LOOK_SIZE = 32

/** 风格包的胶片色调烘成一张 32³ 的 3D LUT：S 形对比、抬黑位、高光偏暖、暗部偏青、草绿偏移。
 *  在色调映射之后的显示空间里用（见 finishShader），以后换成美术调好的 LUT 只要换这张图 */
export function lookTexture(look: LookParams) {
  const n = LOOK_SIZE
  const data = new Uint8Array(n * n * n * 4)
  const smooth = (a: number, b: number, x: number) => {
    const t = Math.max(0, Math.min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
  }
  for (let bi = 0; bi < n; bi++)
    for (let gi = 0; gi < n; gi++)
      for (let ri = 0; ri < n; ri++) {
        let [r, g, b] = [ri / (n - 1), gi / (n - 1), bi / (n - 1)]
        // 草绿：色相落在绿区的颜色往黄绿或青绿挪一点、降一点饱和
        const [h, s, v] = rgbToHsv(r, g, b)
        const green = smooth(60, 95, h) * (1 - smooth(150, 185, h)) * smooth(0.08, 0.3, s)
        if (green > 0 && look.greens !== 0) {
          ;[r, g, b] = hsvToRgb(
            h - look.greens * 260 * green,
            s * (1 - Math.abs(look.greens) * 2.5 * green),
            v
          )
        }
        // S 形对比和抬起的黑位
        const curve = (x: number) => {
          const k = x + (x * x * (3 - 2 * x) - x) * look.contrast * 2
          return look.lift + k * (1 - look.lift)
        }
        r = curve(r)
        g = curve(g)
        b = curve(b)
        // 高光偏暖、暗部偏青
        const l = 0.2126 * r + 0.7152 * g + 0.0722 * b
        const hi = smooth(0.45, 1, l) * look.warm,
          lo = (1 - smooth(0, 0.45, l)) * look.teal
        r += hi * 0.55 - lo * 0.45
        g += hi * 0.12 + lo * 0.1
        b += -hi * 0.5 + lo * 0.35
        const o = (ri + gi * n + bi * n * n) * 4
        data[o] = Math.round(Math.max(0, Math.min(1, r)) * 255)
        data[o + 1] = Math.round(Math.max(0, Math.min(1, g)) * 255)
        data[o + 2] = Math.round(Math.max(0, Math.min(1, b)) * 255)
        data[o + 3] = 255
      }
  const t = new THREE.Data3DTexture(data, n, n, n)
  t.format = THREE.RGBAFormat
  t.type = THREE.UnsignedByteType
  t.magFilter = t.minFilter = THREE.LinearFilter
  t.wrapS = t.wrapT = t.wrapR = THREE.ClampToEdgeWrapping
  t.unpackAlignment = 1
  t.needsUpdate = true
  return t
}

function rgbToHsv(r: number, g: number, b: number): [number, number, number] {
  const max = Math.max(r, g, b),
    min = Math.min(r, g, b),
    d = max - min
  let h = 0
  if (d > 0) {
    if (max === r) h = 60 * (((g - b) / d) % 6)
    else if (max === g) h = 60 * ((b - r) / d + 2)
    else h = 60 * ((r - g) / d + 4)
  }
  return [(h + 360) % 360, max ? d / max : 0, max]
}

function hsvToRgb(h: number, s: number, v: number): [number, number, number] {
  h = ((h % 360) + 360) % 360
  s = Math.max(0, Math.min(1, s))
  const c = v * s,
    x = c * (1 - Math.abs(((h / 60) % 2) - 1)),
    m = v - c
  const [r, g, b] =
    h < 60
      ? [c, x, 0]
      : h < 120
        ? [x, c, 0]
        : h < 180
          ? [0, c, x]
          : h < 240
            ? [0, x, c]
            : h < 300
              ? [x, 0, c]
              : [c, 0, x]
  return [r + m, g + m, b + m]
}

/** 最后一遍，在色调映射和转 sRGB 之后：套风格包的胶片 LUT */
export const finishShader = {
  uniforms: {
    tDiffuse: { value: null },
    tLook: { value: null as THREE.Data3DTexture | null },
    lookAmount: { value: 1 },
  },
  vertexShader,
  fragmentShader: /* glsl */ `
uniform sampler2D tDiffuse;
uniform sampler3D tLook;
uniform float lookAmount;
varying vec2 vUv;
void main() {
  vec4 c = texture2D(tDiffuse, vUv);
  vec3 graded = texture(tLook, clamp(c.rgb, 0.0, 1.0) * ${((LOOK_SIZE - 1) / LOOK_SIZE).toFixed(6)} + ${(0.5 / LOOK_SIZE).toFixed(6)}).rgb;
  gl_FragColor = vec4(mix(c.rgb, graded, lookAmount), c.a);
}`,
}
