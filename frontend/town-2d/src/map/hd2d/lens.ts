import * as THREE from 'three'
import { FullScreenQuad, Pass } from 'three/addons/postprocessing/Pass.js'
import { TILT_FOCUS } from './post'

// 镜头：散景景深和双重滤波泛光。
// 景深按弥散圆（CoC）在半分辨率上做黄金角螺旋采样，亮点按亮度加权，虚化区里的灯、窗、海面闪光成一个个
// 光斑；后面的东西不晕到前面清楚的东西上。最后按弥散圆和全分辨率的清晰画面混合，焦点处保持原样清楚。
// 泛光是 13 点下采样（第一级做 Karis 平均，压掉单个亮像素的闪烁）加帐篷上采样，能量逐级累加，
// 叠回去时带一点暖色，像胶片高光边缘的晕。

const VERTEX =
  'varying vec2 vUv;void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}'

/** 移轴的清晰带、深度离焦的参数：和 post.ts 的 tiltShader 同名，场景按同一套算法更新 */
export function cocUniforms() {
  return {
    tDepth: { value: null as THREE.Texture | null },
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
  }
}
type CocUniforms = ReturnType<typeof cocUniforms>

/** 弥散圆半径（全分辨率设备像素）：画面上下边缘的移轴模糊和按深度的离焦取大的；
 *  移轴模糊的高斯每步 amount 像素、两边各 7 步，换成圆盘差不多是 5.5 倍 */
const COC = /* glsl */ `
uniform sampler2D tDepth;
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
float surfaceDepth(vec2 uv) { return mix(cameraNear, cameraFar, texture2D(tDepth, uv).r); }
float cocAt(vec2 uv) {
  float edge = smoothstep(band, band + 0.38, abs(uv.y - focus)) * amount;
  float depthBlur = smoothstep(focusRange, focusRange + depthFalloff,
    abs(surfaceDepth(uv) - focusDepth)) * depthAmount;
  return min(max(edge, depthBlur) * 5.5, 40.0);
}`

/** 半分辨率：颜色（线性过滤取到的就是 2×2 的平均）和弥散圆 */
const PREFILTER = /* glsl */ `
${COC}
uniform sampler2D tDiffuse;
varying vec2 vUv;
void main() {
  gl_FragColor = vec4(texture2D(tDiffuse, vUv).rgb, cocAt(vUv));
}`

const GATHER = /* glsl */ `
${COC}
uniform sampler2D tPre;
uniform vec2 halfRes;
uniform int taps;
varying vec2 vUv;
void main() {
  vec4 c0 = texture2D(tPre, vUv);
  float r0 = c0.a * 0.5;
  if (r0 < 0.5) {
    gl_FragColor = vec4(c0.rgb, 1.0);
    return;
  }
  float d0 = surfaceDepth(vUv);
  vec3 sum = c0.rgb;
  float total = 1.0;
  float n = float(taps);
  for (int i = 1; i < 64; i++) {
    if (i >= taps) break;
    float fi = float(i) + 0.5;
    float r = sqrt(fi / n) * r0;
    float a = fi * 2.39996323;
    vec2 uv = vUv + vec2(cos(a), sin(a)) * r / halfRes;
    vec4 s = texture2D(tPre, uv);
    // 样本自己糊开的半径够得着中心才算；样本在中心后面时，中心自己也要糊到这么大，
    // 远处的颜色不穿过清楚的人物、屋檐和树叶的轮廓
    float reach = smoothstep(r - 1.0, r + 1.0, s.a * 0.5 + 0.5);
    float behind = smoothstep(focusRange * 0.5, focusRange * 2.0, surfaceDepth(uv) - d0);
    float w = reach * mix(1.0, smoothstep(r - 1.0, r + 1.0, r0), behind);
    // 亮点权重大：灯、窗、闪光糊开成一个个光斑，而不是摊薄成一团
    float l = dot(s.rgb, vec3(0.2126, 0.7152, 0.0722));
    w *= 1.0 + 3.0 * smoothstep(0.8, 3.0, l);
    sum += s.rgb * w;
    total += w;
  }
  gl_FragColor = vec4(sum / total, 1.0);
}`

const COMPOSITE = /* glsl */ `
${COC}
uniform sampler2D tDiffuse;
uniform sampler2D tBokeh;
varying vec2 vUv;
void main() {
  vec4 sharp = texture2D(tDiffuse, vUv);
  vec3 blur = texture2D(tBokeh, vUv).rgb;
  gl_FragColor = vec4(mix(sharp.rgb, blur, smoothstep(0.6, 2.5, cocAt(vUv))), sharp.a);
}`

function halfFloatTarget() {
  return new THREE.WebGLRenderTarget(1, 1, {
    type: THREE.HalfFloatType,
    depthBuffer: false,
    magFilter: THREE.LinearFilter,
    minFilter: THREE.LinearFilter,
  })
}

/** 散景景深：替换高档以上的移轴模糊（中档仍用 post.ts 的两遍高斯） */
export class BokehPass extends Pass {
  readonly uniforms: CocUniforms = cocUniforms()
  /** 每个像素的采样数：高档 24，极致 48 */
  taps = 24
  private readonly pre = halfFloatTarget()
  private readonly gathered = halfFloatTarget()
  private readonly prefilter: FullScreenQuad
  private readonly gather: FullScreenQuad
  private readonly composite: FullScreenQuad
  private readonly halfRes = new THREE.Vector2(1, 1)

  constructor() {
    super()
    const material = (fragmentShader: string, extra: Record<string, THREE.IUniform> = {}) =>
      new THREE.ShaderMaterial({
        vertexShader: VERTEX,
        fragmentShader,
        uniforms: { ...this.uniforms, ...extra },
        depthTest: false,
        depthWrite: false,
      })
    this.prefilter = new FullScreenQuad(material(PREFILTER, { tDiffuse: { value: null } }))
    this.gather = new FullScreenQuad(
      material(GATHER, {
        tPre: { value: this.pre.texture },
        halfRes: { value: this.halfRes },
        taps: { value: this.taps },
      })
    )
    this.composite = new FullScreenQuad(
      material(COMPOSITE, {
        tDiffuse: { value: null },
        tBokeh: { value: this.gathered.texture },
      })
    )
  }

  override setSize(width: number, height: number) {
    const w = Math.max(1, Math.ceil(width / 2)),
      h = Math.max(1, Math.ceil(height / 2))
    this.pre.setSize(w, h)
    this.gathered.setSize(w, h)
    this.halfRes.set(w, h)
    this.uniforms.res.value.set(width, height)
  }

  override render(
    renderer: THREE.WebGLRenderer,
    writeBuffer: THREE.WebGLRenderTarget,
    readBuffer: THREE.WebGLRenderTarget
  ) {
    const pre = this.prefilter.material as THREE.ShaderMaterial
    pre.uniforms.tDiffuse.value = readBuffer.texture
    renderer.setRenderTarget(this.pre)
    this.prefilter.render(renderer)
    ;(this.gather.material as THREE.ShaderMaterial).uniforms.taps.value = this.taps
    renderer.setRenderTarget(this.gathered)
    this.gather.render(renderer)
    const out = this.composite.material as THREE.ShaderMaterial
    out.uniforms.tDiffuse.value = readBuffer.texture
    renderer.setRenderTarget(this.renderToScreen ? null : writeBuffer)
    this.composite.render(renderer)
  }

  override dispose() {
    this.pre.dispose()
    this.gathered.dispose()
    for (const q of [this.prefilter, this.gather, this.composite]) {
      q.material.dispose()
      q.dispose()
    }
  }
}

/** 13 点下采样；first 时先做软阈值，再按组做 Karis 平均 */
const DOWN = /* glsl */ `
uniform sampler2D tSrc;
uniform vec2 texel;
uniform float threshold;
uniform float knee;
uniform bool first;
varying vec2 vUv;
vec3 tap(vec2 o) { return texture2D(tSrc, vUv + o * texel).rgb; }
vec3 bright(vec3 c) {
  float b = max(c.r, max(c.g, c.b));
  float soft = clamp(b - threshold + knee, 0.0, 2.0 * knee);
  soft = soft * soft / (4.0 * knee + 1e-4);
  return c * max(soft, b - threshold) / max(b, 1e-4);
}
float karis(vec3 c) { return 1.0 / (1.0 + dot(c, vec3(0.2126, 0.7152, 0.0722))); }
void main() {
  vec3 a = tap(vec2(-2.0, 2.0)), b = tap(vec2(0.0, 2.0)), c = tap(vec2(2.0, 2.0));
  vec3 d = tap(vec2(-2.0, 0.0)), e = tap(vec2(0.0)), f = tap(vec2(2.0, 0.0));
  vec3 g = tap(vec2(-2.0, -2.0)), h = tap(vec2(0.0, -2.0)), i = tap(vec2(2.0, -2.0));
  vec3 j = tap(vec2(-1.0, 1.0)), k = tap(vec2(1.0, 1.0)), l = tap(vec2(-1.0, -1.0)), m = tap(vec2(1.0, -1.0));
  vec3 g0 = (j + k + l + m) * 0.25, g1 = (a + b + d + e) * 0.25, g2 = (b + c + e + f) * 0.25;
  vec3 g3 = (d + e + g + h) * 0.25, g4 = (e + f + h + i) * 0.25;
  if (first) {
    g0 = bright(g0); g1 = bright(g1); g2 = bright(g2); g3 = bright(g3); g4 = bright(g4);
    float w0 = karis(g0) * 0.5, w1 = karis(g1) * 0.125, w2 = karis(g2) * 0.125;
    float w3 = karis(g3) * 0.125, w4 = karis(g4) * 0.125;
    gl_FragColor = vec4((g0 * w0 + g1 * w1 + g2 * w2 + g3 * w3 + g4 * w4) / (w0 + w1 + w2 + w3 + w4), 1.0);
  } else gl_FragColor = vec4(g0 * 0.5 + (g1 + g2 + g3 + g4) * 0.125, 1.0);
}`

/** 帐篷上采样：低一级放大后加到这一级上 */
const UP = /* glsl */ `
uniform sampler2D tLow;
uniform sampler2D tHigh;
uniform vec2 texel;
varying vec2 vUv;
void main() {
  vec2 d = texel;
  vec3 t = texture2D(tLow, vUv + vec2(-d.x, d.y)).rgb + texture2D(tLow, vUv + vec2(d.x, d.y)).rgb
    + texture2D(tLow, vUv + vec2(-d.x, -d.y)).rgb + texture2D(tLow, vUv + vec2(d.x, -d.y)).rgb
    + 2.0 * (texture2D(tLow, vUv + vec2(0.0, d.y)).rgb + texture2D(tLow, vUv + vec2(0.0, -d.y)).rgb
      + texture2D(tLow, vUv + vec2(d.x, 0.0)).rgb + texture2D(tLow, vUv + vec2(-d.x, 0.0)).rgb)
    + 4.0 * texture2D(tLow, vUv).rgb;
  gl_FragColor = vec4(texture2D(tHigh, vUv).rgb + t / 16.0, 1.0);
}`

const MIX = /* glsl */ `
uniform sampler2D tDiffuse;
uniform sampler2D tBloom;
uniform float strength;
uniform vec3 tint;
uniform float levels;
varying vec2 vUv;
void main() {
  vec4 c = texture2D(tDiffuse, vUv);
  gl_FragColor = vec4(c.rgb + texture2D(tBloom, vUv).rgb / levels * strength * tint, c.a);
}`

/** 双重滤波泛光：strength、threshold 和原来的 UnrealBloomPass 同名，场景按时段调 */
export class GlowPass extends Pass {
  strength = 0.4
  threshold = 0.85
  /** 软阈值的过渡宽度：太宽时白天大片受光的地面也泛光，整幅发灰 */
  knee = 0.15
  /** 叠回去时的颜色：偏暖一点就是胶片高光边缘的晕 */
  readonly tint = new THREE.Color(1, 0.92, 0.84)
  private readonly levels = 6
  private readonly down: THREE.WebGLRenderTarget[] = []
  private readonly up: THREE.WebGLRenderTarget[] = []
  private readonly downQuad = new FullScreenQuad(
    new THREE.ShaderMaterial({
      vertexShader: VERTEX,
      fragmentShader: DOWN,
      uniforms: {
        tSrc: { value: null },
        texel: { value: new THREE.Vector2() },
        threshold: { value: 0.85 },
        knee: { value: 0.45 },
        first: { value: false },
      },
      depthTest: false,
      depthWrite: false,
    })
  )
  private readonly upQuad = new FullScreenQuad(
    new THREE.ShaderMaterial({
      vertexShader: VERTEX,
      fragmentShader: UP,
      uniforms: {
        tLow: { value: null },
        tHigh: { value: null },
        texel: { value: new THREE.Vector2() },
      },
      depthTest: false,
      depthWrite: false,
    })
  )
  private readonly mixQuad = new FullScreenQuad(
    new THREE.ShaderMaterial({
      vertexShader: VERTEX,
      fragmentShader: MIX,
      uniforms: {
        tDiffuse: { value: null },
        tBloom: { value: null },
        strength: { value: 0.4 },
        tint: { value: this.tint },
        levels: { value: 6 },
      },
      depthTest: false,
      depthWrite: false,
    })
  )

  constructor() {
    super()
    for (let i = 0; i < this.levels; i++) {
      this.down.push(halfFloatTarget())
      this.up.push(halfFloatTarget())
    }
  }

  override setSize(width: number, height: number) {
    let w = width,
      h = height
    for (let i = 0; i < this.levels; i++) {
      w = Math.max(1, Math.ceil(w / 2))
      h = Math.max(1, Math.ceil(h / 2))
      this.down[i].setSize(w, h)
      this.up[i].setSize(w, h)
    }
  }

  override render(
    renderer: THREE.WebGLRenderer,
    writeBuffer: THREE.WebGLRenderTarget,
    readBuffer: THREE.WebGLRenderTarget
  ) {
    const d = (this.downQuad.material as THREE.ShaderMaterial).uniforms
    d.threshold.value = this.threshold
    d.knee.value = this.knee
    let source = readBuffer
    for (let i = 0; i < this.levels; i++) {
      d.tSrc.value = source.texture
      d.texel.value.set(1 / source.width, 1 / source.height)
      d.first.value = i === 0
      renderer.setRenderTarget(this.down[i])
      this.downQuad.render(renderer)
      source = this.down[i]
    }
    const u = (this.upQuad.material as THREE.ShaderMaterial).uniforms
    let low = this.down[this.levels - 1]
    for (let i = this.levels - 2; i >= 0; i--) {
      u.tLow.value = low.texture
      u.tHigh.value = this.down[i].texture
      u.texel.value.set(1 / low.width, 1 / low.height)
      renderer.setRenderTarget(this.up[i])
      this.upQuad.render(renderer)
      low = this.up[i]
    }
    const m = (this.mixQuad.material as THREE.ShaderMaterial).uniforms
    m.tDiffuse.value = readBuffer.texture
    m.tBloom.value = low.texture
    m.strength.value = this.strength
    m.levels.value = this.levels
    renderer.setRenderTarget(this.renderToScreen ? null : writeBuffer)
    this.mixQuad.render(renderer)
  }

  override dispose() {
    for (const t of [...this.down, ...this.up]) t.dispose()
    for (const q of [this.downQuad, this.upQuad, this.mixQuad]) {
      q.material.dispose()
      q.dispose()
    }
  }
}
