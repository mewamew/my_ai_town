import * as THREE from 'three'
import { FullScreenQuad, Pass } from 'three/addons/postprocessing/Pass.js'
import { MARGIN, PIXEL } from '../grid'

// 体积光与晨雾：低分辨率上从每个像素看到的地面（或屋顶、树）沿正交视线朝镜头步进，穿过贴地的一层雾。
// 每一步查一次太阳的阴影贴图：被房子、树挡住的地方不亮，光就从缝里一道道斜着穿过来；
// 再按地面光照图加上灯在雾里的光晕，灯下的雾是暖的。雾随风流动，清晨和雨后浓，贴着水面和地面更浓。
// 起点按 4×4 有序抖动错开，回到全分辨率时按深度做双边上采样，不糊到轮廓外面。
// 不做时域累积：场景静止时节拍循环不重画，累积帧攒不起来。

const VERTEX =
  'varying vec2 vUv;void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}'

const MARCH = /* glsl */ `
uniform sampler2D tDepth;
uniform sampler2DShadow tShadow;
uniform sampler2D tLight;
uniform bool hasShadow;
uniform mat4 shadowMatrix;
uniform mat4 cameraWorld;
uniform vec4 viewRect;
uniform float cameraNear;
uniform float cameraFar;
uniform vec3 sunDir;
uniform vec3 sunColor;
uniform vec3 skyColor;
uniform float density;
uniform float mist;
uniform float layer;
uniform float lampScatter;
uniform float sunGain;
uniform float skyGain;
uniform vec2 lightOrigin;
uniform vec2 lightSize;
uniform vec2 wind;
uniform float time;
uniform int steps;
varying vec2 vUv;
float vhash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(vhash(i), vhash(i + vec2(1.0, 0.0)), f.x), mix(vhash(i + vec2(0.0, 1.0)), vhash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float vbayer2(vec2 a) { a = floor(a); return fract(dot(a, vec2(0.5, a.y * 0.75))); }
float vbayer(vec2 a) { return vbayer2(0.5 * a) * 0.25 + vbayer2(a); }
// 雾的密度：贴地的一层按高度指数变淡，噪声随风流动；晨雾更低更浓
float fogAt(vec3 q) {
  vec2 p = q.xz / ${(90 * PIXEL).toFixed(1)} + wind * time;
  float n = vnoise(p) * 0.65 + vnoise(p * 2.7 + 13.0) * 0.35;
  float base = density * exp(-max(q.y, 0.0) / (layer * 0.45)) * (0.45 + 1.1 * n);
  float low = mist * exp(-max(q.y, 0.0) / (layer * 0.3)) * smoothstep(0.25, 0.7, n);
  return base + low;
}
float sunVisible(vec3 q) {
  if (!hasShadow) return 1.0;
  vec4 s = shadowMatrix * vec4(q, 1.0);
  if (s.x < 0.0 || s.y < 0.0 || s.x > 1.0 || s.y > 1.0 || s.z > 1.0) return 1.0;
  return texture(tShadow, vec3(s.xy, s.z - 0.0015));
}
void main() {
  float depth = texture2D(tDepth, vUv).r;
  vec3 view = vec3(mix(viewRect.x, viewRect.y, vUv.x), mix(viewRect.w, viewRect.z, vUv.y),
    -mix(cameraNear, cameraFar, depth));
  vec3 p = (cameraWorld * vec4(view, 1.0)).xyz;
  // 朝镜头的方向：正交镜头的视线处处平行
  vec3 back = normalize(cameraWorld[2].xyz);
  float top = layer * 1.6;
  if (p.y >= top || back.y <= 0.001) {
    gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }
  float len = min((top - max(p.y, -1.0)) / back.y, ${(400 * PIXEL).toFixed(1)});
  float n = float(steps);
  float dt = len / n;
  float jitter = vbayer(gl_FragCoord.xy);
  // 往镜头方向看去的光：顺着光走来的方向散射得多一些（逆光、侧光时光柱更明显）
  float cosTheta = dot(-sunDir, back);
  float g = 0.45;
  float hg = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cosTheta, 1.5) / 12.566;
  float phase = 0.045 + hg;
  vec3 light = vec3(0.0);
  float trans = 1.0;
  for (int i = 0; i < 32; i++) {
    if (i >= steps) break;
    vec3 q = p + back * (float(i) + jitter) * dt;
    float f = fogAt(q);
    if (f < 1e-6) continue;
    vec3 lamp = texture2D(tLight, (q.xz - lightOrigin) / lightSize).rgb
      * exp(-max(q.y, 0.0) / (layer * 0.6)) * lampScatter;
    vec3 inscatter = sunColor * sunVisible(q) * phase * sunGain + skyColor * skyGain + lamp;
    float step_ = f * dt;
    light += trans * inscatter * step_;
    trans *= exp(-step_ * 0.6);
  }
  gl_FragColor = vec4(light, trans);
}`

const COMPOSITE = /* glsl */ `
uniform sampler2D tDiffuse;
uniform sampler2D tFog;
uniform sampler2D tDepth;
uniform vec2 fogRes;
uniform float cameraNear;
uniform float cameraFar;
varying vec2 vUv;
float dist(vec2 uv) { return mix(cameraNear, cameraFar, texture2D(tDepth, uv).r); }
void main() {
  vec4 c = texture2D(tDiffuse, vUv);
  // 双边上采样：四个最近的低分辨率格子按深度相近程度加权，雾不跨过前后差得远的轮廓
  vec2 p = vUv * fogRes - 0.5;
  vec2 base = floor(p), f = p - base;
  float d0 = dist(vUv);
  vec4 sum = vec4(0.0);
  float total = 0.0;
  for (int j = 0; j < 2; j++)
    for (int i = 0; i < 2; i++) {
      vec2 cell = base + vec2(float(i), float(j));
      vec2 uv = (cell + 0.5) / fogRes;
      float w = (i == 0 ? 1.0 - f.x : f.x) * (j == 0 ? 1.0 - f.y : f.y);
      w *= 1.0 / (1.0 + abs(dist(uv) - d0) * 0.05);
      sum += texture2D(tFog, uv) * w;
      total += w;
    }
  vec4 fog = total > 0.0 ? sum / total : texture2D(tFog, vUv);
  gl_FragColor = vec4(c.rgb * fog.a + fog.rgb, c.a);
}`

export class VolumetricPass extends Pass {
  /** 步进的步数：高档 12，极致 20 */
  steps = 12
  /** 低分辨率的比例：高档四分之一，极致二分之一 */
  scale = 0.25
  readonly uniforms = {
    tDepth: { value: null as THREE.Texture | null },
    tShadow: { value: null as THREE.Texture | null },
    tLight: { value: null as THREE.Texture | null },
    hasShadow: { value: false },
    shadowMatrix: { value: new THREE.Matrix4() },
    cameraWorld: { value: new THREE.Matrix4() },
    viewRect: { value: new THREE.Vector4() },
    cameraNear: { value: 0 },
    cameraFar: { value: 1 },
    sunDir: { value: new THREE.Vector3(0, 1, 0) },
    sunColor: { value: new THREE.Color() },
    skyColor: { value: new THREE.Color() },
    density: { value: 0 },
    mist: { value: 0 },
    layer: { value: 30 * PIXEL },
    lampScatter: { value: 0.03 },
    /** 太阳散射的倍数：光柱要看得出来，比物理值强 */
    sunGain: { value: 3 },
    /** 天光照亮雾的多少：晨雾主要是被天光照白的 */
    skyGain: { value: 0.22 },
    lightOrigin: { value: new THREE.Vector2(-MARGIN, -MARGIN) },
    lightSize: { value: new THREE.Vector2(1, 1) },
    wind: { value: new THREE.Vector2(0.02, 0.008) },
    time: { value: 0 },
    steps: { value: 12 },
  }
  private readonly fog = new THREE.WebGLRenderTarget(1, 1, {
    type: THREE.HalfFloatType,
    depthBuffer: false,
    magFilter: THREE.NearestFilter,
    minFilter: THREE.NearestFilter,
  })
  private readonly march = new FullScreenQuad(
    new THREE.ShaderMaterial({
      vertexShader: VERTEX,
      fragmentShader: MARCH,
      uniforms: this.uniforms,
      depthTest: false,
      depthWrite: false,
    })
  )
  private readonly composite = new FullScreenQuad(
    new THREE.ShaderMaterial({
      vertexShader: VERTEX,
      fragmentShader: COMPOSITE,
      uniforms: {
        tDiffuse: { value: null },
        tFog: { value: this.fog.texture },
        tDepth: this.uniforms.tDepth,
        fogRes: { value: new THREE.Vector2(1, 1) },
        cameraNear: this.uniforms.cameraNear,
        cameraFar: this.uniforms.cameraFar,
      },
      depthTest: false,
      depthWrite: false,
    })
  )
  private size = [1, 1]

  override setSize(width: number, height: number) {
    this.size = [width, height]
    this.resizeFog()
  }

  private resizeFog() {
    const w = Math.max(1, Math.round(this.size[0] * this.scale)),
      h = Math.max(1, Math.round(this.size[1] * this.scale))
    this.fog.setSize(w, h)
    ;(this.composite.material as THREE.ShaderMaterial).uniforms.fogRes.value.set(w, h)
  }

  /** 换画质档：低分辨率比例和步数 */
  setDetail(scale: number, steps: number) {
    this.steps = steps
    if (scale !== this.scale) {
      this.scale = scale
      this.resizeFog()
    }
  }

  private sun: THREE.DirectionalLight | null = null

  /** 镜头变了：直接引用镜头的世界矩阵（画场景时更新），视野和远近面按值存 */
  setView(camera: THREE.OrthographicCamera) {
    const u = this.uniforms
    u.cameraWorld.value = camera.matrixWorld
    u.viewRect.value.set(camera.left, camera.right, camera.top, camera.bottom)
    u.cameraNear.value = camera.near
    u.cameraFar.value = camera.far
  }

  /** 太阳挪了：方向按值存；阴影矩阵引用太阳阴影自己的那份（画阴影时更新） */
  setSun(sun: THREE.DirectionalLight) {
    this.sun = sun
    this.uniforms.shadowMatrix.value = sun.shadow.matrix
    this.uniforms.sunDir.value.copy(sun.position).sub(sun.target.position).normalize()
  }

  override render(
    renderer: THREE.WebGLRenderer,
    writeBuffer: THREE.WebGLRenderTarget,
    readBuffer: THREE.WebGLRenderTarget
  ) {
    // 阴影贴图第一次画阴影时才建
    const map = this.sun?.shadow.map?.depthTexture ?? null
    this.uniforms.tShadow.value = map
    this.uniforms.hasShadow.value = !!map
    this.uniforms.steps.value = this.steps
    renderer.setRenderTarget(this.fog)
    this.march.render(renderer)
    const out = this.composite.material as THREE.ShaderMaterial
    out.uniforms.tDiffuse.value = readBuffer.texture
    renderer.setRenderTarget(this.renderToScreen ? null : writeBuffer)
    this.composite.render(renderer)
  }

  override dispose() {
    this.fog.dispose()
    for (const q of [this.march, this.composite]) {
      q.material.dispose()
      q.dispose()
    }
  }
}
