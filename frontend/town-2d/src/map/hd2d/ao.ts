import * as THREE from 'three'
import { MARGIN, PIXEL } from '../grid'
import type { House } from './layout'

// 接触阴影和环境光遮蔽：房子、树、灯、人「站」在地上的那一圈暗。
// 地面遮蔽在加载地图时烘一次：房子按高度场做水平角搜索（墙越高、离墙越近越暗），树根和灯杆脚下加一小圈，
// 结果按台阶和有序抖动量化，和光照图、像素海面同一种画法；运行时零开销，只影响天光（aoMap）
// 和一点点直射光。墙面按离地高度压一条墙脚暗带、檐下一条阴影带。村民脚下一块像素化的椭圆暗斑，跟着人走。

const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map((v) => (v + 0.5) / 16)

/** 地面上一个小圆遮蔽（树根、灯杆、地标脚下）：中心地图坐标、半径（地面像素）、最暗处的遮蔽量 */
export interface Contact {
  x: number
  y: number
  r: number
  strength: number
}

/** 烘地面遮蔽图：和地面画布同尺寸，白是不遮、越黑遮得越多 */
export function groundOcclusion(
  pw: number,
  ph: number,
  houses: readonly House[],
  contacts: Contact[]
) {
  const height = new Float32Array(pw * ph)
  const toPx = (v: number) => Math.floor((v + MARGIN) / PIXEL)
  for (const h of houses) {
    const top = h.wallH + h.ridge * 0.55
    for (let y = Math.max(0, toPx(h.y)); y < Math.min(ph, toPx(h.y + h.h)); y++)
      for (let x = Math.max(0, toPx(h.x)); x < Math.min(pw, toPx(h.x + h.w)); x++)
        height[y * pw + x] = Math.max(height[y * pw + x], top)
  }
  const ao = new Float32Array(pw * ph).fill(1)
  const done = new Uint8Array(pw * ph)
  const REACH = 14
  const DIRS = 12
  const dirs = Array.from({ length: DIRS }, (_, k) => [
    Math.cos((k / DIRS) * Math.PI * 2),
    Math.sin((k / DIRS) * Math.PI * 2),
  ])
  for (const h of houses) {
    const x0 = Math.max(1, toPx(h.x) - REACH),
      x1 = Math.min(pw - 1, toPx(h.x + h.w) + REACH)
    const y0 = Math.max(1, toPx(h.y) - REACH),
      y1 = Math.min(ph - 1, toPx(h.y + h.h) + REACH)
    for (let y = y0; y < y1; y++)
      for (let x = x0; x < x1; x++) {
        const i = y * pw + x
        if (done[i] || height[i] > 0) continue
        done[i] = 1
        // 每个方向上能看到的天空被房子挡掉多少（最大仰角的正弦），各方向平均
        let blocked = 0
        for (const [dx, dy] of dirs) {
          let best = 0
          for (let s = 1; s <= REACH; s++) {
            const sx = Math.round(x + dx * s),
              sy = Math.round(y + dy * s)
            if (sx < 0 || sy < 0 || sx >= pw || sy >= ph) break
            const hh = height[sy * pw + sx]
            if (hh <= 0) continue
            const d = s * PIXEL
            best = Math.max(best, hh / Math.hypot(hh, d))
          }
          blocked += best
        }
        ao[i] = Math.min(ao[i], 1 - (blocked / DIRS) * 0.85)
      }
  }
  for (const c of contacts) {
    const cx = (c.x + MARGIN) / PIXEL,
      cy = (c.y + MARGIN) / PIXEL
    for (let y = Math.floor(cy - c.r); y <= Math.ceil(cy + c.r); y++)
      for (let x = Math.floor(cx - c.r); x <= Math.ceil(cx + c.r); x++) {
        if (x < 0 || y < 0 || x >= pw || y >= ph) continue
        // 地面压扁：脚下的圈横向宽、纵向窄
        const d = Math.hypot((x + 0.5 - cx) / c.r, ((y + 0.5 - cy) / c.r) * 1.6)
        if (d >= 1) continue
        const i = y * pw + x
        ao[i] *= 1 - c.strength * (1 - d) * (1 - d)
      }
  }
  // 量化成六档，按有序抖动过渡；顺带换成画布，和地面贴图同一个朝向
  const canvas = document.createElement('canvas')
  canvas.width = pw
  canvas.height = ph
  const ctx = canvas.getContext('2d')!
  const img = ctx.createImageData(pw, ph)
  for (let y = 0; y < ph; y++)
    for (let x = 0; x < pw; x++) {
      const i = y * pw + x
      const q = Math.min(1, Math.floor(ao[i] * 6 + BAYER[(x & 3) + (y & 3) * 4]) / 6)
      const v = Math.round(q * 255)
      img.data[i * 4] = img.data[i * 4 + 1] = img.data[i * 4 + 2] = v
      img.data[i * 4 + 3] = 255
    }
  ctx.putImageData(img, 0, 0)
  const t = new THREE.CanvasTexture(canvas)
  t.magFilter = t.minFilter = THREE.NearestFilter
  t.generateMipmaps = false
  return t
}

/** 地面接上遮蔽图：天光按它（aoMap），直射光也压一点，接触的地方看得出来 */
export function groundAo(material: THREE.MeshPhongMaterial, map: THREE.Texture) {
  material.aoMap = map
  material.aoMapIntensity = 1
  const before = material.onBeforeCompile.bind(material)
  const beforeKey = material.customProgramCacheKey()
  material.onBeforeCompile = (shader, renderer) => {
    before(shader, renderer)
    shader.fragmentShader = shader.fragmentShader.replace(
      '#include <opaque_fragment>',
      `#ifdef USE_AOMAP
        outgoingLight *= mix(1.0, texture2D(aoMap, vAoMapUv).r, 0.4);
      #endif
      #include <opaque_fragment>`
    )
  }
  material.customProgramCacheKey = () => `${beforeKey}|groundAo`
}

/** 墙脚往上几格一条暗带，檐下一条阴影带；top 是墙顶高度（世界单位） */
export function wallAo(material: THREE.Material, top: number) {
  const before = material.onBeforeCompile.bind(material)
  const beforeKey = material.customProgramCacheKey()
  material.onBeforeCompile = (shader, renderer) => {
    before(shader, renderer)
    shader.uniforms.uWallTop = { value: top }
    shader.vertexShader =
      'varying float vAoHeight;\n' +
      shader.vertexShader.replace(
        '#include <project_vertex>',
        `#include <project_vertex>
        vAoHeight = (modelMatrix * vec4(transformed, 1.0)).y;`
      )
    shader.fragmentShader =
      'varying float vAoHeight;\nuniform float uWallTop;\n' +
      shader.fragmentShader.replace(
        '#include <opaque_fragment>',
        `{
          float base = smoothstep(0.0, ${(5 * PIXEL).toFixed(1)}, vAoHeight);
          float eave = smoothstep(uWallTop, uWallTop - ${(3 * PIXEL).toFixed(1)}, vAoHeight);
          outgoingLight *= mix(0.66, 1.0, floor(base * 4.0 + 0.5) / 4.0) * mix(0.82, 1.0, floor(eave * 3.0 + 0.5) / 3.0);
        }
        #include <opaque_fragment>`
      )
  }
  material.customProgramCacheKey = () => `${beforeKey}|wallAo:${top.toFixed(1)}`
}

/** 脚下暗斑的贴图：一个按有序抖动过渡的像素圆 */
export function contactTexture() {
  const n = 16
  const c = document.createElement('canvas')
  c.width = c.height = n
  const x = c.getContext('2d')!
  const img = x.createImageData(n, n)
  for (let j = 0; j < n; j++)
    for (let i = 0; i < n; i++) {
      const d = Math.hypot((i + 0.5) / n - 0.5, (j + 0.5) / n - 0.5) * 2
      const a = d < 1 ? (1 - d * d) * 0.95 : 0
      const q = Math.floor(a * 4 + BAYER[(i & 3) + (j & 3) * 4]) / 4
      img.data[(j * n + i) * 4 + 3] = Math.round(Math.min(1, q) * 255)
    }
  x.putImageData(img, 0, 0)
  const t = new THREE.CanvasTexture(c)
  t.magFilter = t.minFilter = THREE.NearestFilter
  t.generateMipmaps = false
  return t
}
