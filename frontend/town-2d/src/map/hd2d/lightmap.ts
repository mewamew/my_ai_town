import * as THREE from 'three'
import { MARGIN, PIXEL } from '../grid'
import type { House } from './layout'

// 地面光照图：一张和地面画布同尺寸的光（一格就是一个地图像素）。路灯、门灯、窗光、掀开屋顶后屋里的灯
// 都画在这张图上，地面、墙和立牌按它受光，所以多少盏灯都只是一次取样，不再受点光源数量的限制。
// 光被房子挡住：路灯的光沿光线在房子占地图上步进，碰到房子就停。地面按像素格取光，
// 亮度按台阶和有序抖动过渡，和像素海面同一种画法。光源只在入夜、开关屋顶时变，平时不重画。

export type LightKind = 'lamp' | 'window' | 'door' | 'room' | 'prop'
const KIND: Record<LightKind, number> = { lamp: 0, window: 1, door: 2, room: 3, prop: 4 }

export interface LightSource {
  kind: LightKind
  /** 地图坐标：灯杆脚、窗下的墙脚、门口、屋子中心 */
  x: number
  y: number
  /** 灯、门、道具：照亮半径；窗：光斑朝外伸多远；屋：半深（地图单位） */
  reach: number
  /** 窗：窗宽；屋：半宽（地图单位） */
  width?: number
  /** 窗光朝外的方向（单位向量，地图坐标） */
  dir?: [number, number]
  /** 线性颜色，已乘强度 */
  color: THREE.Color
  /** 夜里亮灯的程度超过它才亮（0～1），一盏盏错开 */
  on: number
  /** 窗、屋里的灯和屋里道具的灯属于哪栋房子：屋顶掀开时窗光换成屋里的光 */
  house?: string
}

/** 灯亮到全亮的过渡宽度（按「亮灯程度」算） */
const FADE = 0.08
/** 提着走的灯笼：最多几盏、照多远 */
const MAX_CARRIED = 24
const CARRIED_REACH = 22 * PIXEL

const VERTEX = /* glsl */ `
attribute vec4 iRect;
attribute vec4 iParams;
attribute vec4 iShape;
attribute vec3 iColor;
uniform vec2 uOrigin;
uniform vec2 uSize;
varying vec2 vMap;
varying vec4 vParams;
varying vec4 vShape;
varying vec3 vColor;
void main() {
  vMap = mix(iRect.xy, iRect.zw, position.xy);
  vParams = iParams;
  vShape = iShape;
  vColor = iColor;
  gl_Position = vec4((vMap - uOrigin) / uSize * 2.0 - 1.0, 0.0, 1.0);
}`

const FRAGMENT = /* glsl */ `
uniform sampler2D uOccupancy;
uniform vec2 uOrigin;
uniform vec2 uSize;
varying vec2 vMap;
varying vec4 vParams;
varying vec4 vShape;
varying vec3 vColor;
float occupied(vec2 p) { return texture2D(uOccupancy, (p - uOrigin) / uSize).r; }
void main() {
  float kind = vParams.x, reach = vParams.y, width = vParams.z, level = vParams.w;
  vec2 center = vShape.xy, dir = vShape.zw;
  float light = 0.0;
  if (kind < 0.5) {
    // 路灯：中间亮、往外按平方衰减；光线经过房子就被挡住
    float d = distance(vMap, center);
    light = pow(max(0.0, 1.0 - d / reach), 2.0);
    float open = 1.0;
    for (int k = 1; k < 16; k++) open *= 1.0 - occupied(mix(vMap, center, float(k) / 16.0));
    light *= open;
  } else if (kind < 1.5) {
    // 窗光：朝外投一块越往外越宽、越淡的梯形。窗开在半墙高，光落地要离墙几格，墙根自己不被照亮
    vec2 rel = vMap - center;
    float out_ = dot(rel, dir);
    float along = abs(dot(rel, vec2(-dir.y, dir.x)));
    float half_ = width * 0.5 + out_ * 0.45;
    light = smoothstep(${(1 * PIXEL).toFixed(1)}, ${(5 * PIXEL).toFixed(1)}, out_)
      * (1.0 - smoothstep(half_ - ${PIXEL.toFixed(1)}, half_ + ${PIXEL.toFixed(1)}, along))
      * pow(max(0.0, 1.0 - out_ / reach), 1.4) * (1.0 - occupied(vMap));
  } else if (kind < 2.5) {
    // 门灯：门口一小团，不穿进屋里
    float d = distance(vMap, center);
    light = pow(max(0.0, 1.0 - d / reach), 1.6) * (1.0 - occupied(vMap));
  } else if (kind < 3.5) {
    // 屋里的灯：掀开屋顶后整间屋子暖暖地亮，靠墙稍暗
    vec2 q = abs(vMap - center) / vec2(width, reach);
    light = 1.0 - smoothstep(0.35, 1.0, max(q.x, q.y));
  } else {
    // 屋里道具的灯（台灯、柜里的灯）：脚下一团暖光，不被自己这栋房子挡
    float d = distance(vMap, center);
    light = pow(max(0.0, 1.0 - d / reach), 1.7);
  }
  gl_FragColor = vec4(vColor * light * level, 1.0);
}`

/** 材质里取光照图的一段：地面按像素格取，按台阶和有序抖动量化 */
const SAMPLE = /* glsl */ `
uniform sampler2D uLightMap;
uniform vec2 uLightOrigin;
uniform vec2 uLightSize;
uniform float uLightGain;
uniform vec2 uRimDir;
uniform vec3 uRimSun;
uniform vec2 uRimRight;
float lightBayer2(vec2 a) { a = floor(a); return fract(dot(a, vec2(0.5, a.y * 0.75))); }
float lightBayer(vec2 a) { return lightBayer2(0.5 * a) * 0.25 + lightBayer2(a); }
vec3 lightAt(vec2 xz) {
  vec2 cell = floor(xz / ${PIXEL.toFixed(1)});
  vec3 l = texture2D(uLightMap, ((cell + 0.5) * ${PIXEL.toFixed(1)} - uLightOrigin) / uLightSize).rgb;
  float m = max(l.r, max(l.g, l.b));
  if (m <= 0.002) return vec3(0.0);
  float q = floor(m * 5.0 + lightBayer(cell)) / 5.0;
  return l * (q / m) * uLightGain;
}`

/** 立牌的轮廓光：贴图透明度在四邻的差给出这一格边缘朝外的方向（画面上的方向），
 *  和太阳在画面上的方向一致时亮（傍晚侧光、逆光）；灯按光照图在脚底左右的差找到在哪一边，人从灯下走过，
 *  朝灯那一侧的边亮。只亮最外一格，保持像素感 */
const RIM = /* glsl */ `
  #ifdef USE_MAP
  {
    vec2 rimTexel = 1.0 / vec2(textureSize(map, 0));
    float aL = texture2D(map, vMapUv - vec2(rimTexel.x, 0.0)).a, aR = texture2D(map, vMapUv + vec2(rimTexel.x, 0.0)).a;
    float aD = texture2D(map, vMapUv - vec2(0.0, rimTexel.y)).a, aU = texture2D(map, vMapUv + vec2(0.0, rimTexel.y)).a;
    vec2 outward = vec2(aL - aR, aD - aU);
    if (dot(outward, outward) > 0.09) {
      vec2 n = normalize(outward);
      vec3 rimLight = uRimSun * max(dot(n, uRimDir), 0.0);
      float side = dot(lightAt(vLightFoot + uRimRight * ${(6 * PIXEL).toFixed(1)}) - lightAt(vLightFoot - uRimRight * ${(6 * PIXEL).toFixed(1)}), vec3(0.3, 0.5, 0.2));
      rimLight += lightAt(vLightFoot) * 1.6 * max(dot(n, normalize(vec2(side, 0.35))), 0.0) * smoothstep(0.01, 0.12, abs(side) + 0.04);
      lamp += rimLight;
    }
  }
  #endif`

/** 受光的方式：地面逐像素格；墙按墙外一格取、越高越暗；立牌按脚底取、越高越暗 */
export type LightSurface = 'ground' | 'wall' | 'standee' | 'canopy'

export class LightMap {
  readonly target: THREE.WebGLRenderTarget
  private readonly scene = new THREE.Scene()
  private readonly camera = new THREE.Camera()
  private readonly material: THREE.ShaderMaterial
  private readonly geometry = new THREE.InstancedBufferGeometry()
  private readonly mesh: THREE.Mesh
  private readonly occupancy: THREE.DataTexture
  private readonly uniforms: {
    uLightMap: { value: THREE.Texture }
    uLightOrigin: { value: THREE.Vector2 }
    uLightSize: { value: THREE.Vector2 }
    uLightGain: { value: number }
    uRimDir: { value: THREE.Vector2 }
    uRimSun: { value: THREE.Color }
    uRimRight: { value: THREE.Vector2 }
  }
  private sources: LightSource[] = []
  private levels = new Float32Array(0)
  private lit = 0
  private open: ReadonlySet<string> = new Set()
  private dirty = true
  /** 提着走的灯笼：另一组实例，和固定的灯同一个着色器；一走动只重画它前后经过的那一块 */
  private readonly carriedGeometry = new THREE.InstancedBufferGeometry()
  private carried: [number, number][] = []
  /** 灯笼挪过后要重画的那一块（地图坐标的包围框）；固定的灯变了就整张重画 */
  private patch: [number, number, number, number] | null = null

  /** pw、ph 是地面画布的像素数；houses 的占地挡光 */
  constructor(pw: number, ph: number, houses: readonly House[]) {
    const origin = new THREE.Vector2(-MARGIN, -MARGIN)
    const size = new THREE.Vector2(pw * PIXEL, ph * PIXEL)
    this.target = new THREE.WebGLRenderTarget(pw, ph, {
      type: THREE.HalfFloatType,
      depthBuffer: false,
      magFilter: THREE.LinearFilter,
      minFilter: THREE.LinearFilter,
    })
    const occ = new Uint8Array(pw * ph)
    for (const h of houses) {
      const x0 = Math.max(0, Math.floor((h.x + MARGIN) / PIXEL)),
        x1 = Math.min(pw, Math.ceil((h.x + h.w + MARGIN) / PIXEL))
      const y0 = Math.max(0, Math.floor((h.y + MARGIN) / PIXEL)),
        y1 = Math.min(ph, Math.ceil((h.y + h.h + MARGIN) / PIXEL))
      for (let y = y0; y < y1; y++) occ.fill(255, y * pw + x0, y * pw + x1)
    }
    this.occupancy = new THREE.DataTexture(occ, pw, ph, THREE.RedFormat, THREE.UnsignedByteType)
    this.occupancy.magFilter = this.occupancy.minFilter = THREE.NearestFilter
    this.occupancy.needsUpdate = true
    this.material = new THREE.ShaderMaterial({
      vertexShader: VERTEX,
      fragmentShader: FRAGMENT,
      uniforms: {
        uOccupancy: { value: this.occupancy },
        uOrigin: { value: origin },
        uSize: { value: size },
      },
      blending: THREE.AdditiveBlending,
      depthTest: false,
      depthWrite: false,
      transparent: true,
    })
    this.geometry.setAttribute(
      'position',
      new THREE.BufferAttribute(new Float32Array([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0]), 3)
    )
    this.geometry.setIndex([0, 1, 2, 0, 2, 3])
    this.mesh = new THREE.Mesh(this.geometry, this.material)
    this.mesh.frustumCulled = false
    this.scene.add(this.mesh)
    const g = this.carriedGeometry
    g.setAttribute('position', this.geometry.getAttribute('position'))
    g.setIndex(this.geometry.getIndex())
    for (const [name, size] of [
      ['iRect', 4],
      ['iParams', 4],
      ['iShape', 4],
      ['iColor', 3],
    ] as const)
      g.setAttribute(
        name,
        new THREE.InstancedBufferAttribute(new Float32Array(MAX_CARRIED * size), size)
      )
    g.instanceCount = 0
    const carried = new THREE.Mesh(g, this.material)
    carried.frustumCulled = false
    this.scene.add(carried)
    this.uniforms = {
      uLightMap: { value: this.target.texture },
      uLightOrigin: { value: origin },
      uLightSize: { value: size },
      uLightGain: { value: 1 },
      uRimDir: { value: new THREE.Vector2(0, 1) },
      uRimSun: { value: new THREE.Color(0, 0, 0) },
      uRimRight: { value: new THREE.Vector2(1, 0) },
    }
  }

  /** 换一整批光源（建场景时一次） */
  setSources(sources: LightSource[]) {
    this.sources = sources
    const n = sources.length
    const rect = new Float32Array(n * 4),
      params = new Float32Array(n * 4),
      shape = new Float32Array(n * 4),
      color = new Float32Array(n * 3)
    sources.forEach((s, i) => {
      const r = s.reach,
        w = s.width ?? 0
      const [dx, dy] = s.dir ?? [0, 1]
      let box: [number, number, number, number]
      if (s.kind === 'window') {
        // 梯形光斑的外接框：沿墙方向窗宽加外扩，朝外 reach
        const side = w / 2 + r * 0.45 + PIXEL
        const ex = Math.abs(dy) * side + Math.max(0, dx) * r,
          wx = Math.abs(dy) * side + Math.max(0, -dx) * r
        const ey = Math.abs(dx) * side + Math.max(0, dy) * r,
          ny = Math.abs(dx) * side + Math.max(0, -dy) * r
        box = [s.x - wx, s.y - ny, s.x + ex, s.y + ey]
      } else if (s.kind === 'room') box = [s.x - w, s.y - r, s.x + w, s.y + r]
      else box = [s.x - r, s.y - r, s.x + r, s.y + r]
      rect.set(box, i * 4)
      params.set([KIND[s.kind], r, w, 0], i * 4)
      shape.set([s.x, s.y, dx, dy], i * 4)
      color.set([s.color.r, s.color.g, s.color.b], i * 3)
    })
    this.geometry.setAttribute('iRect', new THREE.InstancedBufferAttribute(rect, 4))
    this.geometry.setAttribute('iParams', new THREE.InstancedBufferAttribute(params, 4))
    this.geometry.setAttribute('iShape', new THREE.InstancedBufferAttribute(shape, 4))
    this.geometry.setAttribute('iColor', new THREE.InstancedBufferAttribute(color, 3))
    this.geometry.instanceCount = n
    this.levels = new Float32Array(n)
    this.refresh()
  }

  /** 夜里亮灯的程度（0 白天～1 全亮）；各光源按自己的门槛错开亮起 */
  setLit(lit: number) {
    if (Math.abs(lit - this.lit) < 0.004 && !(lit === 0 && this.lit !== 0)) return
    this.lit = lit
    this.refresh()
  }

  /** 掀开了屋顶的房子：屋里的灯亮，那栋房子的窗光不再往外投（墙已经拿掉了） */
  setOpenRooms(open: ReadonlySet<string>) {
    this.open = open
    this.refresh()
  }

  /** 光源 i 此刻的亮度（0～1），入夜时逐个亮起 */
  level(on: number) {
    return Math.max(0, Math.min(1, (this.lit - on) / FADE))
  }

  private refresh() {
    const params = this.geometry.getAttribute('iParams') as
      THREE.InstancedBufferAttribute | undefined
    if (!params) return
    let changed = false
    this.sources.forEach((s, i) => {
      const opened = s.house !== undefined && this.open.has(s.house)
      const visible =
        s.kind === 'room' || s.kind === 'prop' ? opened : s.kind === 'window' ? !opened : true
      const v = visible ? this.level(s.on) : 0
      if (Math.abs(v - this.levels[i]) > 0.001) {
        this.levels[i] = v
        params.setW(i, v)
        changed = true
      }
    })
    if (changed) {
      params.needsUpdate = true
      this.dirty = true
    }
  }

  /** 提着灯笼的人（地图坐标）：灯笼是一盏会走的小灯，光照图跟着重画。只重画灯笼这一帧和上一帧
   *  所在的那一块（剪裁到包围框），不整张重画；color 是灯的颜色（线性，已乘强度） */
  setCarried(points: readonly [number, number][], color: THREE.Color) {
    const n = Math.min(points.length, MAX_CARRIED)
    const same =
      n === this.carried.length &&
      this.carried.every(([x, y], i) => x === points[i][0] && y === points[i][1])
    if (same) return
    for (const p of this.carried) this.grow(p)
    this.carried = points.slice(0, n).map(([x, y]) => [x, y])
    for (const p of this.carried) this.grow(p)
    const g = this.carriedGeometry
    const rect = g.getAttribute('iRect') as THREE.InstancedBufferAttribute,
      params = g.getAttribute('iParams') as THREE.InstancedBufferAttribute,
      shape = g.getAttribute('iShape') as THREE.InstancedBufferAttribute,
      tint = g.getAttribute('iColor') as THREE.InstancedBufferAttribute
    const r = CARRIED_REACH
    this.carried.forEach(([x, y], i) => {
      rect.setXYZW(i, x - r, y - r, x + r, y + r)
      params.setXYZW(i, KIND.lamp, r, 0, 1)
      shape.setXYZW(i, x, y, 0, 1)
      tint.setXYZ(i, color.r, color.g, color.b)
    })
    for (const a of [rect, params, shape, tint]) a.needsUpdate = true
    g.instanceCount = n
  }

  private grow([x, y]: [number, number]) {
    const r = CARRIED_REACH + PIXEL
    const p = this.patch
    this.patch = p
      ? [Math.min(p[0], x - r), Math.min(p[1], y - r), Math.max(p[2], x + r), Math.max(p[3], y + r)]
      : [x - r, y - r, x + r, y + r]
  }

  /** 光源有变化时重画光照图：固定的灯变了整张重画，只有灯笼走动时只重画它经过的那一块；返回画了没有 */
  render(renderer: THREE.WebGLRenderer) {
    if (!this.dirty && !this.patch) return false
    const target = this.target
    if (!this.dirty && this.patch) {
      // 地图坐标 → 光照图的像素（原点在左下，和光照图的行同向）
      const o = this.uniforms.uLightOrigin.value
      const x0 = Math.max(0, Math.floor((this.patch[0] - o.x) / PIXEL)),
        y0 = Math.max(0, Math.floor((this.patch[1] - o.y) / PIXEL))
      const x1 = Math.min(target.width, Math.ceil((this.patch[2] - o.x) / PIXEL)),
        y1 = Math.min(target.height, Math.ceil((this.patch[3] - o.y) / PIXEL))
      target.scissor.set(x0, y0, Math.max(0, x1 - x0), Math.max(0, y1 - y0))
      target.scissorTest = true
    }
    this.dirty = false
    this.patch = null
    const before = renderer.getRenderTarget()
    const clear = renderer.getClearColor(new THREE.Color()),
      alpha = renderer.getClearAlpha()
    renderer.setRenderTarget(target)
    renderer.setClearColor(0x000000, 0)
    renderer.clear(true, false, false)
    if (this.levels.some((v) => v > 0) || this.carried.length)
      renderer.render(this.scene, this.camera)
    target.scissorTest = false
    renderer.setRenderTarget(before)
    renderer.setClearColor(clear, alpha)
    return true
  }

  /** 给材质接上光照图：outgoingLight 加上「颜色 × 灯光」，在云影之后，灯光不被云挡 */
  shade(material: THREE.Material, surface: LightSurface) {
    const uniforms = this.uniforms
    const before = material.onBeforeCompile.bind(material)
    const beforeKey = material.customProgramCacheKey()
    material.onBeforeCompile = (shader, renderer) => {
      before(shader, renderer)
      Object.assign(shader.uniforms, uniforms)
      const foot =
        surface === 'standee' || surface === 'canopy'
          ? `#ifdef USE_INSTANCING
              vLightFoot = (modelMatrix * instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xz;
            #else
              vLightFoot = modelMatrix[3].xz;
            #endif
            vLightHeight = position.y;`
          : `vec4 lightWorld = modelMatrix * vec4(transformed, 1.0);
            vLightFoot = lightWorld.xz;
            vLightHeight = lightWorld.y;
            vLightNormal = normalize(mat3(modelMatrix) * objectNormal);`
      shader.vertexShader =
        'varying vec2 vLightFoot;\nvarying float vLightHeight;\nvarying vec3 vLightNormal;\n' +
        shader.vertexShader.replace(
          '#include <project_vertex>',
          `#include <project_vertex>
          ${foot}`
        )
      const take =
        surface === 'ground'
          ? 'vec3 lamp = lightAt(vLightFoot);'
          : surface === 'wall'
            ? `vec3 lampN = normalize(vLightNormal);
              vec3 lamp = lightAt(vLightFoot + lampN.xz * ${(1.5 * PIXEL).toFixed(1)})
                * exp(-max(vLightHeight, 0.0) / ${(36 * PIXEL).toFixed(1)}) * (1.0 - max(lampN.y, 0.0));`
            : surface === 'canopy'
              ? `vec3 lamp = lightAt(vLightFoot) * (0.08 + 0.92 * (1.0 - smoothstep(${(16 * PIXEL).toFixed(1)}, ${(58 * PIXEL).toFixed(1)}, vLightHeight)));
              ${RIM}`
              : `vec3 lamp = lightAt(vLightFoot) * mix(1.0, 0.45, clamp(vLightHeight / ${(60 * PIXEL).toFixed(1)}, 0.0, 1.0));
              ${RIM}`
      shader.fragmentShader =
        'varying vec2 vLightFoot;\nvarying float vLightHeight;\nvarying vec3 vLightNormal;\n' +
        SAMPLE +
        '\n' +
        shader.fragmentShader.replace(
          '#include <opaque_fragment>',
          `{
            ${take}
            outgoingLight += diffuseColor.rgb * lamp;
          }
          #include <opaque_fragment>`
        )
    }
    material.customProgramCacheKey = () => `${beforeKey}|lightmap:${surface}`
    return material
  }

  /** 太阳在画面上的方向（右、上）和轮廓光的颜色强度；镜头右手方向在地图上的朝向（找灯在哪边用） */
  setRim(dir: THREE.Vector2, color: THREE.Color, right: THREE.Vector2) {
    this.uniforms.uRimDir.value.copy(dir)
    this.uniforms.uRimSun.value.copy(color)
    this.uniforms.uRimRight.value.copy(right)
  }

  /** 光照图贴图：体积光按它给灯上方的雾加光晕 */
  get texture() {
    return this.target.texture
  }

  dispose() {
    this.carriedGeometry.dispose()
    this.target.dispose()
    this.occupancy.dispose()
    this.material.dispose()
    this.geometry.dispose()
  }
}
