import * as THREE from 'three'
import { fromPx, MARGIN, PIXEL } from '../grid'
import { OPEN } from '../pixel/terrain'
import { fbm, hash, rng } from '../pixel/noise'
import type { DecorPlan } from '../decor'
import type { MapTheme } from '../themes/types'
import type { Tilt } from './layout'
import { pixelMaterial } from './pixelSampling'
import { sprite } from './sprite'
import { texture } from './standee'
import { WIND } from './weather'

// 草丛和花：一簇簇像素小立牌。一阵风吹过时成片往下风方向倒、再立起来，人走过时往两边分开（踩踏图，见 trail.ts），
// 积雪厚了被埋住。一张图集画八种草、四种花；几千簇按地面格子分块，每块一个 InstancedMesh，看不见的块不画；
// 拉远到一簇草只剩一两个像素时整片隐去。中档一半密度，低档不画。
// 地图规划里的 grass、flowers 原来只画在地面贴图上，这里在同样的位置立起来，野地、公园、花园再按噪声撒一些。

const GRASS_VARIANTS = 8
const VARIANTS = GRASS_VARIANTS + 4
const TUFT_W = 7
const TUFT_H = 8
/** 一块的边长（地面像素） */
const CHUNK = 48
/** 最多多少簇 */
const LIMIT = 16000

interface Tuft {
  x: number
  y: number
  variant: number
  scale: number
}

/** 草和花的图集：每格 7×8，下面是深色的根，上面是亮的草尖；后四格顶上开花 */
function tuftAtlas(theme: MapTheme) {
  const g = theme.ground
  const dark = g.grass[0],
    mid = g.grass[Math.min(2, g.grass.length - 1)],
    light = g.tuft
  return sprite(TUFT_W * VARIANTS, TUFT_H, (p) => {
    for (let v = 0; v < VARIANTS; v++) {
      const ox = v * TUFT_W
      const blades = 3 + (v % 3)
      for (let b = 0; b < blades; b++) {
        const x = ox + 1 + Math.floor(hash(b, v, 5) * (TUFT_W - 2))
        const h = 3 + Math.floor(hash(b, v, 9) * (TUFT_H - 4))
        const lean = hash(b, v, 13) < 0.5 ? -1 : 1
        for (let k = 0; k < h; k++) {
          const xx = x + (k >= Math.ceil(h * 0.6) ? lean : 0)
          p.px(xx, TUFT_H - 1 - k, k === h - 1 ? light : k === 0 ? dark : mid)
        }
      }
      if (v >= GRASS_VARIANTS) {
        const c = g.flowers[v % g.flowers.length]
        const fx = ox + 2 + (v % 3)
        p.px(fx, 1, c)
        p.px(fx + 1, 1, c)
        p.px(fx, 2, c)
        p.px(fx + 1, 2, c)
        p.px(fx, 3, mid)
      }
    }
  })
}

/** 立起来的位置：规划里的草和花一簇散成几簇，野地、公园、花园再按噪声撒；
 *  mown 时草坪是修剪过的，几乎不长草丛 */
export function tuftsOf(
  decor: DecorPlan,
  ground: { width: number; height: number; open: Uint8Array },
  seed: number,
  density: number,
  mown = false
) {
  const random = rng(seed + 77)
  const tufts: Tuft[] = []
  for (const v of decor.vegetation) {
    if (v.kind !== 'grass' && v.kind !== 'flowers') continue
    const n = v.kind === 'flowers' ? 5 : 4
    for (let k = 0; k < n; k++)
      tufts.push({
        x: v.x + (random() - 0.5) * 5 * PIXEL,
        y: v.y + (random() - 0.5) * 3 * PIXEL,
        variant:
          v.kind === 'flowers' && k < 3
            ? GRASS_VARIANTS + Math.floor(random() * 4)
            : Math.floor(random() * GRASS_VARIANTS),
        scale: (0.8 + random() * 0.4) * v.scale,
      })
  }
  const { width: pw, height: ph, open } = ground
  const chance: Record<number, (x: number, y: number) => number> = {
    [OPEN.park]: () => 0.1,
    [OPEN.lawn]: () => (mown ? 0.006 : 0.06),
    [OPEN.verge]: () => 0.02,
    [OPEN.garden]: () => 0.12,
    [OPEN.town]: () => 0.015,
    [OPEN.wild]: (x, y) => 0.12 * Math.max(0, fbm(x * 0.9, y * 0.9, seed + 140) * 2.4 - 0.85),
  }
  for (let y = 2; y < ph - 2; y += 3)
    for (let x = 2; x < pw - 2; x += 3) {
      const p = (chance[open[y * pw + x]]?.(x, y) ?? 0) * density
      if (random() > p) continue
      tufts.push({
        x: fromPx(x) + random() * 3 * PIXEL,
        y: fromPx(y) + random() * 3 * PIXEL,
        variant:
          random() < 0.06
            ? GRASS_VARIANTS + Math.floor(random() * 4)
            : Math.floor(random() * GRASS_VARIANTS),
        scale: 0.75 + random() * 0.5,
      })
    }
  // 太多时均匀抽掉一些
  if (tufts.length > LIMIT) {
    const step = tufts.length / LIMIT
    return Array.from({ length: LIMIT }, (_, i) => tufts[Math.floor(i * step)])
  }
  return tufts
}

const VERTEX_HEAD = /* glsl */ `
attribute float aVariant;
attribute float aPhase;
uniform float uTime;
uniform float uWind;
uniform float uSnow;
uniform sampler2D uTrail;
uniform vec2 uTrailOrigin;
uniform vec2 uTrailSize;
${WIND}`

export class Grass {
  readonly group = new THREE.Group()
  private readonly material: THREE.MeshLambertMaterial
  private readonly meshes: { mesh: THREE.InstancedMesh; tufts: Tuft[] }[] = []
  private density = 1
  /** 天气和踩踏的 uniform：和天气共用时间、风；踩踏图由 trail.ts 给 */
  readonly uniforms = {
    uTime: { value: 0 },
    uWind: { value: 0.3 },
    uWindDir: { value: new THREE.Vector2(1, 0) },
    uWindSide: { value: 1 },
    uSnow: { value: 0 },
    uTrail: { value: null as THREE.Texture | null },
    uTrailOrigin: { value: new THREE.Vector2(-MARGIN, -MARGIN) },
    uTrailSize: { value: new THREE.Vector2(1, 1) },
  }

  constructor(tufts: Tuft[], theme: MapTheme, tilt: Tilt) {
    const map = texture(tuftAtlas(theme))
    this.material = pixelMaterial(
      new THREE.MeshLambertMaterial({ map, alphaTest: 0.5, side: THREE.DoubleSide })
    )
    const uniforms = this.uniforms
    this.material.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, uniforms)
      shader.vertexShader = (VERTEX_HEAD + '\n' + shader.vertexShader)
        .replace(
          '#include <uv_vertex>',
          `#include <uv_vertex>
          vMapUv.x = (vMapUv.x + aVariant) / ${VARIANTS.toFixed(1)};`
        )
        .replace(
          '#include <begin_vertex>',
          `#include <begin_vertex>
          {
            vec2 foot = (modelMatrix * instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xz;
            float tip = position.y / ${(TUFT_H * PIXEL).toFixed(1)};
            // 踩过的地方压扁、往两边分开，过一会儿慢慢立起来
            float trodden = texture2D(uTrail, (foot - uTrailOrigin) / uTrailSize).r;
            transformed.y *= (1.0 - 0.65 * clamp(trodden, 0.0, 1.0)) * (1.0 - smoothstep(0.35, 0.9, uSnow));
            transformed.x += (0.4 * sin(uTime * 2.1 + aPhase * 6.283) + windGust(foot) * 1.6 * uWindSide)
              * (0.35 + uWind) * tip * ${(1.6 * PIXEL).toFixed(1)}
              + trodden * tip * ${(2.0 * PIXEL).toFixed(1)} * (aPhase < 0.5 ? -1.0 : 1.0);
          }`
        )
        .replace(
          '#include <project_vertex>',
          `#include <project_vertex>
          {
            // 和立牌一样：整簇的深度按根部算，身前的墙挡得住它
            vec4 baseClip = projectionMatrix * viewMatrix * modelMatrix * instanceMatrix
              * vec4(transformed.x, 0.0, transformed.z, 1.0);
            gl_Position.z = baseClip.z / baseClip.w * gl_Position.w;
          }`
        )
    }
    this.material.customProgramCacheKey = () => 'grass-tufts'
    const quad = new THREE.PlaneGeometry(TUFT_W * PIXEL, TUFT_H * PIXEL).translate(
      0,
      (TUFT_H * PIXEL) / 2,
      0
    )
    // 按地面格子分块；块里的顺序打乱，中档按比例只画前一半
    const chunks = new Map<number, Tuft[]>()
    for (const t of tufts) {
      const key =
        Math.floor((t.y + MARGIN) / PIXEL / CHUNK) * 4096 +
        Math.floor((t.x + MARGIN) / PIXEL / CHUNK)
      let list = chunks.get(key)
      if (!list) chunks.set(key, (list = []))
      list.push(t)
    }
    for (const list of chunks.values()) {
      const random = rng(list.length * 31 + Math.round(list[0].x))
      for (let i = list.length - 1; i > 0; i--) {
        const j = Math.floor(random() * (i + 1))
        ;[list[i], list[j]] = [list[j], list[i]]
      }
      const geometry = quad.clone()
      geometry.setAttribute(
        'aVariant',
        new THREE.InstancedBufferAttribute(
          Float32Array.from(list, (t) => t.variant),
          1
        )
      )
      geometry.setAttribute(
        'aPhase',
        new THREE.InstancedBufferAttribute(
          Float32Array.from(list, (t) => hash(Math.round(t.x), Math.round(t.y), 3)),
          1
        )
      )
      const mesh = new THREE.InstancedMesh(geometry, this.material, list.length)
      mesh.receiveShadow = true
      this.meshes.push({ mesh, tufts: list })
      this.group.add(mesh)
    }
    quad.dispose()
    this.setTilt(tilt)
  }

  /** 和立牌一样朝镜头立起来 */
  setTilt(tilt: Tilt) {
    const m = new THREE.Matrix4(),
      q = new THREE.Quaternion().setFromEuler(new THREE.Euler(-tilt.pitch, tilt.yaw, 0, 'YXZ'))
    const p = new THREE.Vector3(),
      s = new THREE.Vector3()
    for (const { mesh, tufts } of this.meshes) {
      tufts.forEach((t, i) => {
        p.set(Math.round(t.x / PIXEL) * PIXEL, 0, Math.round(t.y / PIXEL) * PIXEL)
        s.setScalar(t.scale)
        mesh.setMatrixAt(i, m.compose(p, q, s))
      })
      mesh.instanceMatrix.needsUpdate = true
      mesh.computeBoundingSphere()
    }
  }

  /** 画多少（0～1）：中档一半 */
  setDensity(density: number) {
    this.density = density
    for (const { mesh, tufts } of this.meshes) mesh.count = Math.round(tufts.length * density)
    this.group.visible = density > 0
  }

  /** 一个世界单位占几个设备像素：太小时草只剩一两个像素，整片隐去 */
  setScale(unitPx: number) {
    this.group.visible = this.density > 0 && unitPx > 0.32
  }

  /** 材质：接光照图（灯下的草亮）用 */
  get surface() {
    return this.material
  }

  dispose() {
    for (const { mesh } of this.meshes) mesh.geometry.dispose()
    this.material.map?.dispose()
    this.material.dispose()
  }
}
