import * as THREE from 'three'
import { PIXEL } from '../grid'

const PIXEL_UNITS = PIXEL.toFixed(1)

// 水面倒影：以地平面（y = 0，海面在它下面一点，差得可以忽略）为镜面，把镜头翻到地下，
// 只画房子、立牌这些立着的东西（地面、海、积水、粒子、天幕在 REFLECTION_SKIP 层，不画），
// 画进一张低分辨率的图；没映着东西的地方透明，由材质自己淡淡映一点高处的天色。
// 按真实几何，36° 的俯角下只有紧挨水边又够高的东西映得进水里，倒影几乎看不见；这里有意把倒影镜头
// 压低到实际俯角的 TILT 倍，岸边的房子、灯、树和船能完整地映在水里（HD-2D 常用的夸张倒影）。
// 海、池塘、积水和湿地按投影矩阵取这张图，偏移按地图像素取整，保持像素感。
// 视野里没有水、地也不湿时不画。阴影贴图沿用主画面上一帧的，不为倒影再画一遍。

/** 倒影镜头的俯角是实际俯角的多少倍（最低 12°） */
const TILT = 0.5

/** 不进倒影的东西（地面、海、积水、天气粒子）放在这一层；主镜头两层都看 */
export const REFLECTION_SKIP = 1

export class Reflection {
  readonly camera = new THREE.OrthographicCamera()
  readonly target = new THREE.WebGLRenderTarget(1, 1, {
    type: THREE.HalfFloatType,
    magFilter: THREE.LinearFilter,
    minFilter: THREE.LinearFilter,
  })
  /** 材质里取倒影用的：倒影贴图、世界坐标到倒影贴图的投影、倒影的强弱 */
  readonly uniforms = {
    uReflection: { value: this.target.texture as THREE.Texture },
    uReflMatrix: { value: new THREE.Matrix4() },
    uReflAmount: { value: 0 },
    /** 倒影里没东西的地方映出的天色（高处的天，线性色） */
    uReflSky: { value: new THREE.Color() },
    /** 灯和窗的倒影拉成光带的方向和步长（世界单位，背离镜头） */
    uReflStreak: { value: new THREE.Vector2(0, -36) },
  }
  /** 倒影图相对主画面的比例：高档三分之一，极致二分之一（再小窗户的倒影就被平均掉了） */
  scale = 0.34
  enabled = false
  /** 倒影的强弱：越接近街景越亮，俯视时淡（场景按俯角设） */
  strength = 0.28
  private size = [1, 1]

  constructor() {
    this.camera.layers.set(0)
  }

  setSize(width: number, height: number) {
    this.size = [width, height]
    this.target.setSize(
      Math.max(1, Math.round(width * this.scale)),
      Math.max(1, Math.round(height * this.scale))
    )
  }

  setScale(scale: number) {
    if (scale === this.scale) return
    this.scale = scale
    this.setSize(this.size[0], this.size[1])
  }

  /** 画倒影：main 是主镜头（看着地面上的 target）；visible 为 false（视野里没水、地不湿）时不画 */
  render(
    renderer: THREE.WebGLRenderer,
    scene: THREE.Scene,
    main: THREE.OrthographicCamera,
    target: THREE.Vector3,
    visible: boolean
  ) {
    const amount = this.uniforms.uReflAmount
    if (!this.enabled || !visible) {
      amount.value = 0
      return
    }
    amount.value = this.strength
    const cam = this.camera
    Object.assign(cam, {
      left: main.left,
      right: main.right,
      top: main.top,
      bottom: main.bottom,
      near: main.near,
      far: main.far,
    })
    // 镜头看向 target 的方向：水平朝向不变，俯角压低后翻到水面下
    const back = main.position.clone().sub(target)
    const distance = back.length()
    const flat = Math.hypot(back.x, back.z) || 1
    const pitch = Math.max((12 * Math.PI) / 180, Math.atan2(back.y, flat) * TILT)
    const hx = back.x / flat,
      hz = back.z / flat
    cam.position.set(
      target.x + hx * Math.cos(pitch) * distance,
      -Math.sin(pitch) * distance,
      target.z + hz * Math.cos(pitch) * distance
    )
    cam.up.set(-hx * Math.sin(pitch), -Math.cos(pitch), -hz * Math.sin(pitch))
    cam.lookAt(target.x, 0, target.z)
    cam.updateProjectionMatrix()
    cam.updateMatrixWorld()
    this.uniforms.uReflMatrix.value
      .set(0.5, 0, 0, 0.5, 0, 0.5, 0, 0.5, 0, 0, 0.5, 0.5, 0, 0, 0, 1)
      .multiply(cam.projectionMatrix)
      .multiply(cam.matrixWorldInverse)
    const before = renderer.getRenderTarget()
    const shadows = renderer.shadowMap.autoUpdate
    const clear = renderer.getClearColor(new THREE.Color()),
      alpha = renderer.getClearAlpha()
    renderer.shadowMap.autoUpdate = false
    renderer.setRenderTarget(this.target)
    // 透明度 0 清空：倒影图的 alpha 就是「这里映着东西」，没东西的地方由材质自己映天色
    renderer.setClearColor(0x000000, 0)
    renderer.clear()
    renderer.render(scene, cam)
    renderer.setRenderTarget(before)
    renderer.setClearColor(clear, alpha)
    renderer.shadowMap.autoUpdate = shadows
  }

  dispose() {
    this.target.dispose()
  }
}

/** 取倒影的一段着色器：world 是这一点的世界坐标，wobble 是按地图像素取整的波纹偏移（世界单位） */
export const REFLECTION_SAMPLE = /* glsl */ `
uniform sampler2D uReflection;
uniform mat4 uReflMatrix;
uniform float uReflAmount;
uniform vec3 uReflSky;
uniform vec2 uReflStreak;
// 倒影里这一点映着的东西（a 是有没有东西）
vec4 reflectionAt(vec3 world, vec2 wobble) {
  vec4 r = uReflMatrix * vec4(world.x + wobble.x, 0.0, world.z + wobble.y, 1.0);
  return texture2D(uReflection, r.xy / r.w);
}`

/** 湿地和积水接上倒影：积水几乎就是一面镜子；湿了的地面按颜色有多灰决定反光多少
 *  （石板路、土路映出灯和窗，草地饱和、反光少）。地面的湿度取天气着色里的 uWet，要在 weather.shade 之后接 */
export function wetReflection(
  material: THREE.Material,
  uniforms: Reflection['uniforms'],
  surface: 'ground' | 'puddle'
) {
  const before = material.onBeforeCompile.bind(material)
  const beforeKey = material.customProgramCacheKey()
  material.onBeforeCompile = (shader, renderer) => {
    before(shader, renderer)
    Object.assign(shader.uniforms, uniforms)
    shader.vertexShader =
      'varying vec3 vReflWorld;\n' +
      shader.vertexShader.replace(
        '#include <project_vertex>',
        `#include <project_vertex>
        vReflWorld = (modelMatrix * vec4(transformed, 1.0)).xyz;`
      )
    const apply =
      surface === 'puddle'
        ? `if (uReflAmount > 0.0) {
            vec4 r = reflectionAt(vReflWorld, vec2(0.0));
            outgoingLight = mix(outgoingLight, mix(uReflSky, r.rgb, r.a), 0.7);
          }`
        : `if (uReflAmount > 0.0 && uWet > 0.01) {
            vec3 dc = diffuseColor.rgb;
            float hi = max(dc.r, max(dc.g, dc.b)), lo = min(dc.r, min(dc.g, dc.b));
            float grey = 1.0 - (hi - lo) / max(hi, 1e-3);
            float row = floor(vReflWorld.z / ${PIXEL_UNITS});
            float wob = floor((fract(sin(row * 12.9898) * 43758.5453) - 0.5) * 2.0 + 0.5) * ${PIXEL_UNITS};
            vec4 r = reflectionAt(vReflWorld, vec2(wob, 0.0));
            outgoingLight += r.rgb * r.a * uWet * smoothstep(0.45, 0.85, grey) * 0.3;
          }`
    shader.fragmentShader =
      'varying vec3 vReflWorld;\n' +
      REFLECTION_SAMPLE +
      '\n' +
      shader.fragmentShader.replace(
        '#include <opaque_fragment>',
        `${apply}
        #include <opaque_fragment>`
      )
  }
  material.customProgramCacheKey = () => `${beforeKey}|wetReflection:${surface}`
}
