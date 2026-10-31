import * as THREE from 'three'
import {
  readWeatherPreferences,
  weatherPreferencesEvent,
  type WeatherKind,
  type WeatherPreferences,
} from 'town-shared/weather/types'
import { MARGIN, PIXEL } from '../grid'
import { noise, rng } from '../pixel/noise'
import { WEATHER_LEVELS, type WeatherLevels } from '../weatherLevels'
import { hashNoise } from './glsl'

// 立体场景里的天气：雨丝、落地水花、雪花、落叶是场景里的粒子；地面变湿、积水、积雪、云影和树随风摆
// 是给地面、屋顶、树的材质补的一段着色器。天气强度几秒内平滑过渡；湿度和积雪按游戏时间累积和消退。
// 尊重天气设置：关掉特效只留光照和湿度积雪，画质低只留雨雪，减少动画时不落雨雪不摇树，闪光开了才打闪电。

/** 天气切换时各项强度每秒追上的比例，约 4 秒完成 */
const BLEND = 0.8
/** 湿透和变干、积雪和融化各需要的游戏分钟 */
const WET_MINUTES = 20
const DRY_MINUTES = 150
const SNOW_MINUTES = 40
const MELT_MINUTES = 240
/** 插进着色器的数一律写成浮点 */
const f = (n: number) => n.toFixed(1)
/** 雨雪落下的高度（世界单位） */
const TOP = 60 * PIXEL
const COUNTS = {
  low: { rain: 700, snow: 500, splash: 0, leaves: 0 },
  medium: { rain: 1600, snow: 1000, splash: 250, leaves: 50 },
  high: { rain: 3000, snow: 1800, splash: 500, leaves: 90 },
}

const COMMON = /* glsl */ `
uniform float uTime;
uniform float uWind;
uniform vec2 uCenter;
uniform vec2 uSize;
uniform float uUnitPx;
uniform float uAmount;
attribute vec4 aSeed;
float rand(vec4 seed, float k) { return fract(sin(dot(seed.xy + k, vec2(12.9898, 78.233))) * 43758.5453); }
float wrapTo(float v, float c, float s) { return v + floor((c - v) / s + 0.5) * s; }
vec2 place(vec4 seed) {
  return vec2(wrapTo(seed.x * uSize.x, uCenter.x, uSize.x), wrapTo(seed.y * uSize.y, uCenter.y, uSize.y));
}`

const rainVertex = /* glsl */ `${COMMON}
attribute float aEnd;
uniform float uLength;
varying float vAlpha;
void main() {
  vec2 g = place(aSeed);
  float r1 = rand(aSeed, 1.0), r2 = rand(aSeed, 2.0), r3 = rand(aSeed, 3.0);
  // 每滴下落速度、长短、浓淡都不同；斜度在风向上下浮动，风在空间上一阵阵不一样
  float y = ${f(TOP)} * (1.0 - fract(uTime * mix(0.9, 1.5, r1) + aSeed.z));
  float gust = sin(g.x * 0.0015 + g.y * 0.001 + uTime * 0.8) * 0.12;
  float slant = uWind * (0.35 + gust) + (r2 - 0.5) * 0.18;
  float len = uLength * mix(0.55, 1.4, r3);
  vec3 p = vec3(g.x - slant * y, y, g.y) + vec3(slant, 1.0, (r1 - 0.5) * 0.2) * len * aEnd;
  vAlpha = step(aSeed.w, uAmount) * mix(0.2, 0.55, aEnd) * mix(0.5, 1.0, r2);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
}`
const rainFragment = /* glsl */ `
varying float vAlpha;
void main() { gl_FragColor = vec4(0.74, 0.82, 0.9, vAlpha); }`

const splashVertex = /* glsl */ `${COMMON}
varying float vAlpha;
varying float vLife;
void main() {
  vec2 g = place(aSeed);
  float life = fract(uTime * 2.2 + aSeed.z);
  vLife = life / 0.45;
  vAlpha = step(aSeed.w, uAmount) * step(life, 0.45);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(g.x, 0.8, g.y, 1.0);
  gl_PointSize = mix(1.5, 5.0, vLife) * ${f(PIXEL)} * uUnitPx;
}`
const splashFragment = /* glsl */ `
uniform float uSin;
varying float vAlpha;
varying float vLife;
void main() {
  // 地面随俯角压扁，水花圈画成同样压扁的椭圆
  vec2 c = gl_PointCoord - 0.5;
  float d = length(vec2(c.x, c.y / uSin)) * 2.0;
  float ring = smoothstep(1.0, 0.85, d) - smoothstep(0.75, 0.55, d);
  gl_FragColor = vec4(0.82, 0.88, 0.94, ring * vAlpha * (1.0 - vLife) * 0.45);
}`

const snowVertex = /* glsl */ `${COMMON}
varying float vAlpha;
void main() {
  vec2 g = place(aSeed);
  float r1 = rand(aSeed, 1.0), r2 = rand(aSeed, 2.0);
  // 大片落得慢，小片落得快；两种频率叠起来左右飘，偶尔打个旋
  float size = mix(0.7, 2.4, r1 * r1);
  float fall = fract(uTime * mix(0.13, 0.08, r1) + aSeed.z);
  float y = ${f(TOP)} * (1.0 - fall);
  float sway = sin(uTime * mix(0.6, 1.3, r2) + aSeed.z * 40.0) * ${f(2 * PIXEL)}
    + sin(uTime * 2.7 + r1 * 30.0) * ${f(0.6 * PIXEL)} + uWind * (${f(TOP)} - y) * 0.25;
  float drift = cos(uTime * 0.7 + r2 * 20.0) * ${f(1.2 * PIXEL)};
  vAlpha = step(aSeed.w, uAmount) * smoothstep(0.0, 0.1, fall) * smoothstep(1.0, 0.9, fall) * mix(0.35, 0.7, r2);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(g.x + sway, y, g.y + drift, 1.0);
  gl_PointSize = max(1.5, size * ${f(PIXEL)} * uUnitPx);
}`
const snowFragment = /* glsl */ `
varying float vAlpha;
void main() {
  float d = length(gl_PointCoord - 0.5) * 2.0;
  if (d > 1.0) discard;
  // 中间实、边缘虚的圆片；颜色略带灰蓝，比纯白暗，免得被泛光放大成亮点
  gl_FragColor = vec4(0.84, 0.87, 0.92, vAlpha * smoothstep(1.0, 0.35, d));
}`

const leafVertex = /* glsl */ `${COMMON}
attribute vec3 aColor;
varying float vAlpha;
varying vec3 vColor;
void main() {
  // 顺风飘过：横向随时间平移，上下起伏，忽隐忽现像在翻转
  vec2 g = vec2(
    wrapTo(aSeed.x * uSize.x + uTime * uWind * ${f(25 * PIXEL)}, uCenter.x, uSize.x),
    wrapTo(aSeed.y * uSize.y, uCenter.y, uSize.y));
  float y = (4.0 + aSeed.z * 14.0) * ${f(PIXEL)} + sin(uTime * 1.3 + aSeed.z * 30.0) * ${f(3 * PIXEL)};
  vColor = aColor;
  // 拉远后落叶只剩一个像素，看起来像噪点，隐去
  vAlpha = step(aSeed.w, uAmount) * (0.55 + 0.45 * sin(uTime * 5.0 + aSeed.z * 50.0)) * smoothstep(0.12, 0.35, uUnitPx);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(g.x, y, g.y, 1.0);
  gl_PointSize = max(1.0, ${f(PIXEL)} * uUnitPx);
}`
const leafFragment = /* glsl */ `
varying float vAlpha;
varying vec3 vColor;
void main() { gl_FragColor = vec4(vColor, vAlpha); }`

/** 云影、积雪、湿润和摇摆：补进地面、屋顶、树的材质 */
const SHADE_VERTEX_HEAD = /* glsl */ `
uniform float uTime;
uniform float uWind;
uniform float uSway;
varying vec3 vWeatherPos;
varying float vWeatherUp;`
const SHADE_FRAGMENT_HEAD = /* glsl */ `
uniform float uWet;
uniform float uSnow;
uniform float uCloudShadow;
uniform vec2 uCloudOffset;
uniform float uSnowFactor;
uniform float uWetFactor;
uniform float uSway;
varying vec3 vWeatherPos;
varying float vWeatherUp;
${hashNoise('weather')}`

export interface SurfaceWeather {
  /** 积雪程度的倍数：朝上的面才积，树冠只积一半 */
  snow: number
  /** 变湿变深的倍数 */
  wet: number
  /** 随风摇摆（树） */
  sway?: boolean
}

export class Weather3D {
  private readonly shared = {
    uTime: { value: 0 },
    uWind: { value: 0.3 },
    uWet: { value: 0 },
    uSnow: { value: 0 },
    uCloudShadow: { value: 0 },
    uCloudOffset: { value: new THREE.Vector2() },
    /** 雨下得多大（0～1），海面画雨点用 */
    uRain: { value: 0 },
  }
  private readonly particles: THREE.ShaderMaterial[] = []
  private readonly rain: THREE.LineSegments
  private readonly splash: THREE.Points
  private readonly snow: THREE.Points
  private readonly leaves: THREE.Points
  private readonly puddles: THREE.Mesh
  private readonly wetMaterials: THREE.MeshPhongMaterial[] = []
  private prefs = readWeatherPreferences()
  private readonly reduceMotion = matchMedia('(prefers-reduced-motion: reduce)')
  private readonly abort = new AbortController()
  private kind: WeatherKind = 'clear'
  private readonly now: WeatherLevels = { ...WEATHER_LEVELS.clear }
  private started = false
  private minutes: number | null = null
  private wet = 0
  private snowCover = 0
  private nextFlash = 0
  private flashAt = -1
  /** 闪电的亮度，0..1，由场景加到日光上 */
  flash = 0

  constructor(
    scene: THREE.Scene,
    flat: THREE.Group,
    terrain: { width: number; height: number; path: Uint8Array; wet: Uint8Array },
    seed: number
  ) {
    const counts = COUNTS.high
    const random = rng(seed + 31)
    const seeds = (n: number, perDrop = 1) => {
      const a = new Float32Array(n * perDrop * 4)
      for (let i = 0; i < n; i++) {
        const s = [random(), random(), random(), random()]
        for (let k = 0; k < perDrop; k++) a.set(s, (i * perDrop + k) * 4)
      }
      return a
    }
    // 雨丝：每滴两个顶点，aEnd 0 是下端、1 是上端
    const rainGeometry = new THREE.BufferGeometry()
    rainGeometry.setAttribute(
      'position',
      new THREE.BufferAttribute(new Float32Array(counts.rain * 6), 3)
    )
    rainGeometry.setAttribute('aSeed', new THREE.BufferAttribute(seeds(counts.rain, 2), 4))
    rainGeometry.setAttribute(
      'aEnd',
      new THREE.BufferAttribute(
        Float32Array.from({ length: counts.rain * 2 }, (_, i) => i % 2),
        1
      )
    )
    this.rain = new THREE.LineSegments(
      rainGeometry,
      this.particle(rainVertex, rainFragment, { uLength: { value: 8 * PIXEL } })
    )
    this.splash = this.points(counts.splash, seeds(counts.splash), splashVertex, splashFragment, {
      uSin: { value: 0.77 },
    })
    this.snow = this.points(counts.snow, seeds(counts.snow), snowVertex, snowFragment)
    const leafColors = new Float32Array(counts.leaves * 3)
    const palette = [
      [0.84, 0.52, 0.26],
      [0.62, 0.7, 0.3],
      [0.9, 0.62, 0.66],
      [0.8, 0.7, 0.3],
    ]
    for (let i = 0; i < counts.leaves; i++) leafColors.set(palette[i % palette.length], i * 3)
    this.leaves = this.points(counts.leaves, seeds(counts.leaves), leafVertex, leafFragment)
    this.leaves.geometry.setAttribute('aColor', new THREE.BufferAttribute(leafColors, 3))
    for (const o of [this.rain, this.splash, this.snow, this.leaves]) {
      o.frustumCulled = false
      scene.add(o)
    }
    this.puddles = puddleMesh(terrain, seed)
    flat.add(this.puddles)

    window.addEventListener(
      weatherPreferencesEvent,
      (e) => {
        this.prefs = (e as CustomEvent<WeatherPreferences>).detail
      },
      { signal: this.abort.signal }
    )
  }

  private particle(
    vertexShader: string,
    fragmentShader: string,
    extra: Record<string, THREE.IUniform> = {}
  ) {
    const m = new THREE.ShaderMaterial({
      vertexShader,
      fragmentShader,
      uniforms: {
        uTime: this.shared.uTime,
        uWind: this.shared.uWind,
        uCenter: { value: new THREE.Vector2() },
        uSize: { value: new THREE.Vector2(1, 1) },
        uUnitPx: { value: 1 },
        uAmount: { value: 0 },
        ...extra,
      },
      transparent: true,
      depthWrite: false,
    })
    this.particles.push(m)
    return m
  }

  private points(
    n: number,
    seed: Float32Array,
    vertex: string,
    fragment: string,
    extra: Record<string, THREE.IUniform> = {}
  ) {
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(n * 3), 3))
    g.setAttribute('aSeed', new THREE.BufferAttribute(seed, 4))
    return new THREE.Points(g, this.particle(vertex, fragment, extra))
  }

  /** 世界天气；刚打开时直接到位，之后几秒内过渡 */
  setKind(kind: WeatherKind | undefined) {
    this.kind = kind && kind in WEATHER_LEVELS ? kind : 'clear'
    if (!this.started) Object.assign(this.now, WEATHER_LEVELS[this.kind])
    this.started = true
  }

  /** 按游戏时间累积湿度和积雪；第一次拿到时钟时按当前天气直接给定 */
  setClock(minutes: number) {
    const t = WEATHER_LEVELS[this.kind]
    if (this.minutes === null) {
      this.wet = t.rain > 0 ? 1 : 0
      this.snowCover = t.snow > 0 ? 1 : 0
    } else {
      const d = Math.max(0, Math.min(60, minutes - this.minutes))
      this.wet =
        t.rain > 0
          ? Math.min(1, this.wet + (d * t.rain) / (WET_MINUTES * 0.6))
          : Math.max(0, this.wet - d / DRY_MINUTES)
      // 下雨也会把积雪冲掉
      this.snowCover =
        t.snow > 0
          ? Math.min(1, this.snowCover + d / SNOW_MINUTES)
          : Math.max(0, this.snowCover - d / (t.rain > 0 ? MELT_MINUTES / 3 : MELT_MINUTES))
    }
    this.minutes = minutes
  }

  /** 视野变了：雨雪只下在视野附近；unitPx 是一个世界单位占几个设备像素 */
  setView(
    cx: number,
    cz: number,
    w: number,
    h: number,
    screenH: number,
    unitPx: number,
    sin: number,
    cos: number,
    yawSin = 0,
    yawCos = 1
  ) {
    // 高处落下的雨在画面上往上偏，纵深往镜头一侧多留一段，画面底部也有雨
    const depth = h * 1.3 + (TOP * cos) / sin
    const toward = (TOP * cos) / sin / 2
    for (const m of this.particles) {
      m.uniforms.uCenter.value.set(cx + toward * yawSin, cz + toward * yawCos)
      // 粒子仍锚定世界，范围覆盖旋转后视锥的地面包围盒，四个方向都不会露出没有雨雪的边。
      m.uniforms.uSize.value.set(
        Math.abs(yawCos) * w * 1.3 + Math.abs(yawSin) * depth,
        Math.abs(yawSin) * w * 1.3 + Math.abs(yawCos) * depth
      )
      m.uniforms.uUnitPx.value = unitPx
    }
    // 雨丝长度随视野放大，拉远时仍看得出是雨
    ;(this.rain.material as THREE.ShaderMaterial).uniforms.uLength.value = Math.max(
      8 * PIXEL,
      screenH * 0.03
    )
    ;(this.splash.material as THREE.ShaderMaterial).uniforms.uSin.value = sin
  }

  /** 给材质补天气着色：积雪、湿润、云影，树再加随风摇摆 */
  shade(
    material: THREE.MeshLambertMaterial | THREE.MeshPhongMaterial | THREE.MeshStandardMaterial,
    surface: SurfaceWeather
  ) {
    if (material instanceof THREE.MeshPhongMaterial && surface.wet > 0.5)
      this.wetMaterials.push(material)
    const shared = this.shared
    // 立牌自己的着色器改动（按底边算遮挡）先做，再叠天气。缓存键也要带上原来的，
    // 否则天气参数相同、原改动不同的两种材质会共用一个着色器程序
    const before = material.onBeforeCompile.bind(material)
    const beforeKey = material.customProgramCacheKey()
    material.onBeforeCompile = (shader, renderer) => {
      before(shader, renderer)
      Object.assign(shader.uniforms, shared, {
        uSnowFactor: { value: surface.snow },
        uWetFactor: { value: surface.wet },
        uSway: { value: surface.sway ? 1 : 0 },
      })
      shader.vertexShader = (SHADE_VERTEX_HEAD + '\n' + shader.vertexShader)
        .replace(
          '#include <begin_vertex>',
          `#include <begin_vertex>
          // 树冠顶端随风摆，根部不动
          transformed.x += uSway * sin(uTime * 1.4 + modelMatrix[3].x * 0.013 + modelMatrix[3].z * 0.007)
            * (0.4 + uWind) * position.y * 0.03;`
        )
        .replace(
          '#include <project_vertex>',
          `#include <project_vertex>
          vWeatherPos = (modelMatrix * vec4(transformed, 1.0)).xyz;
          vWeatherUp = normalize(mat3(modelMatrix) * objectNormal).y;`
        )
      shader.fragmentShader = (SHADE_FRAGMENT_HEAD + '\n' + shader.fragmentShader)
        .replace(
          '#include <map_fragment>',
          `#include <map_fragment>
          // 湿了颜色变深；积雪按像素格一格格盖上去，只盖朝上的面
          diffuseColor.rgb *= 1.0 - 0.45 * uWet * uWetFactor;
          vec2 snowP = floor(vWeatherPos.xz / ${f(PIXEL)});
          float snowCell = weatherHash(snowP);
          // 大块噪声决定哪里先积：先成片，边缘按像素格参差，最后铺满
          float drift = weatherNoise(snowP / 16.0) * 0.6 + weatherNoise(snowP / 5.0) * 0.4;
          float snowLevel = drift * 0.75 + snowCell * 0.25;
          float snowUp = smoothstep(0.25, 0.6, vWeatherUp);
          #ifdef USE_MAP
            // 树是竖着的立牌：只积在树冠顶部
            snowUp = mix(snowUp, smoothstep(0.55, 0.75, vMapUv.y), uSway);
          #endif
          float snowed = step(snowLevel, uSnow * 1.05 - 0.05) * snowUp * uSnowFactor;
          float under = dot(diffuseColor.rgb, vec3(0.3, 0.59, 0.11));
          // 雪的深浅跟着底下的明暗和积雪厚薄走，薄处透出一点底色
          float depth = smoothstep(0.0, 0.25, uSnow * 1.05 - 0.05 - snowLevel);
          vec3 snowTone = vec3(0.86, 0.89, 0.94) * (0.82 + 0.3 * under + 0.06 * (snowCell - 0.5));
          snowTone = mix(mix(diffuseColor.rgb, snowTone, 0.6), snowTone, depth);
          diffuseColor.rgb = mix(diffuseColor.rgb, snowTone, snowed);`
        )
        .replace(
          '#include <opaque_fragment>',
          `// 云影：大片噪声随风移动，压暗受光
          vec2 cloudP = (vWeatherPos.xz + uCloudOffset) / ${f(240 * PIXEL)};
          float cloud = weatherNoise(cloudP) * 0.6 + weatherNoise(cloudP * 2.3) * 0.3 + weatherNoise(cloudP * 5.1) * 0.1;
          outgoingLight *= 1.0 - uCloudShadow * smoothstep(0.5, 0.64, cloud);
          #include <opaque_fragment>`
        )
    }
    material.customProgramCacheKey = () =>
      `${beforeKey}|weather:${surface.snow}:${surface.wet}:${surface.sway ? 1 : 0}`
  }

  get cloud() {
    return this.now.cloud
  }
  get overcast() {
    return this.now.overcast
  }

  /** 每帧：过渡强度、推进时间、更新粒子与湿度。light：光照要重算；changed：画面上有东西变了 */
  step(dt: number, time: number, day: number) {
    const target = WEATHER_LEVELS[this.kind]
    const k = Math.min(1, dt * BLEND)
    let lightChanged = false
    for (const key of Object.keys(target) as (keyof WeatherLevels)[]) {
      const before = this.now[key]
      this.now[key] += (target[key] - before) * k
      if (Math.abs(target[key] - this.now[key]) < 0.002) this.now[key] = target[key]
      if ((key === 'cloud' || key === 'overcast') && this.now[key] !== before) lightChanged = true
    }
    const effects = this.prefs.effects
    const moving = !this.prefs.reduceMotion && !this.reduceMotion.matches
    const counts = COUNTS[this.prefs.quality]
    const max = COUNTS.high
    const s = this.shared
    s.uTime.value = moving ? time : 0
    // 阵风：风力在基准上下缓慢起伏；减少动画时不起伏，树停在基准风力下
    s.uWind.value = this.now.wind * (moving ? 1 + 0.25 * Math.sin(time * 0.3) : 1)
    s.uWet.value = this.wet
    s.uSnow.value = this.snowCover
    s.uRain.value = effects && moving ? this.now.rain : 0
    s.uCloudShadow.value =
      effects && this.prefs.quality !== 'low' ? this.now.shadows * day * 0.35 : 0
    if (moving) s.uCloudOffset.value.x += dt * PIXEL * 4 * (0.4 + this.now.wind)
    const show = (o: THREE.Object3D, amount: number, cap: number, total: number) => {
      const m = (o as THREE.Points).material as THREE.ShaderMaterial
      m.uniforms.uAmount.value = amount * (cap / total)
      o.visible = effects && moving && amount > 0.01 && cap > 0
    }
    show(this.rain, this.now.rain, counts.rain, max.rain)
    show(this.splash, this.now.rain, counts.splash, max.splash)
    show(this.snow, this.now.snow, counts.snow, max.snow)
    show(this.leaves, this.now.leaves * day, counts.leaves, max.leaves)
    // 湿了反光：路灯、窗户和太阳在地面和屋顶上留下高光；低洼处积水
    // 反光只留窄窄的亮斑：太大太亮会在整片地面上铺一层白，看起来反而发灰
    for (const m of this.wetMaterials) m.specular.setScalar(0.12 * this.wet)
    const puddle = this.puddles.material as THREE.MeshPhongMaterial
    puddle.opacity = (0.55 * Math.max(0, this.wet - 0.3)) / 0.7
    this.puddles.visible = puddle.opacity > 0.01
    const light = this.stepFlash(time, moving) || lightChanged
    const state = this.state()
    const changed = state !== this.lastState
    this.lastState = state
    return { light, changed }
  }

  /** 着色器和粒子用到的量，逐帧比较它判断画面有没有变 */
  private lastState = ''
  private state() {
    const s = this.shared
    const parts: (number | boolean)[] = [
      s.uTime.value,
      s.uWind.value,
      s.uCloudShadow.value,
      s.uCloudOffset.value.x,
      s.uWet.value,
      s.uSnow.value,
      this.puddles.visible,
    ]
    for (const o of [this.rain, this.splash, this.snow, this.leaves])
      parts.push(
        o.visible,
        ((o as THREE.Points).material as THREE.ShaderMaterial).uniforms.uAmount.value
      )
    return parts.join()
  }

  /** 雷暴：闪光开关打开时，每隔 6～15 秒一次短促的双闪 */
  private stepFlash(time: number, moving: boolean) {
    const before = this.flash
    const allowed = this.now.storm > 0.5 && this.prefs.flash && this.prefs.effects && moving
    if (!allowed) this.flash = 0
    else {
      if (time >= this.nextFlash) {
        this.flashAt = time
        this.nextFlash = time + 6 + Math.random() * 9
      }
      const t = time - this.flashAt
      this.flash =
        t < 0.12 ? 1 : t < 0.22 ? 0.2 : t < 0.32 ? 0.7 : Math.max(0, 0.7 - (t - 0.32) * 2.5)
    }
    return this.flash !== before
  }

  dispose() {
    this.abort.abort()
  }
}

/** 积水坑：路中间的实土上按噪声挑出一块块低洼处，雨后显出来 */
function puddleMesh(
  terrain: { width: number; height: number; path: Uint8Array; wet: Uint8Array },
  seed: number
) {
  const { width: pw, height: ph, path, wet } = terrain
  const mask = document.createElement('canvas')
  mask.width = pw
  mask.height = ph
  const ctx = mask.getContext('2d')!,
    img = ctx.createImageData(pw, ph),
    px = new Uint32Array(img.data.buffer)
  for (let y = 0; y < ph; y++)
    for (let x = 0; x < pw; x++) {
      const i = y * pw + x
      const low = path[i] === 2 && !wet[i] && noise(x / 5, y / 5, seed + 140) > 0.8
      px[i] = low ? 0xffffffff : 0xff000000
    }
  ctx.putImageData(img, 0, 0)
  const alpha = new THREE.CanvasTexture(mask)
  alpha.magFilter = alpha.minFilter = THREE.NearestFilter
  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(pw * PIXEL, ph * PIXEL),
    new THREE.MeshPhongMaterial({
      // 水坑倒映天光：浅灰蓝，靠高光显出水面
      color: '#9aabb8',
      specular: '#ffffff',
      shininess: 120,
      alphaMap: alpha,
      transparent: true,
      opacity: 0,
      depthWrite: false,
    })
  )
  mesh.rotation.x = -Math.PI / 2
  mesh.position.set(-MARGIN + (pw * PIXEL) / 2, 0.6, -MARGIN + (ph * PIXEL) / 2)
  mesh.receiveShadow = true
  return mesh
}
