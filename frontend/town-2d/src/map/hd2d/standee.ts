import * as THREE from 'three'
import { PIXEL } from '../grid'
import type { Tilt } from './layout'
import { pixelMaterial } from './pixelSampling'

// 像素贴图与立牌：树、路灯、村民、道具都是竖在地上的像素图。

/** 像素贴图：线性过滤，配 pixelMaterial 的抗锯齿采样用（见 pixelSampling.ts），
 *  用它的材质都要过一遍 pixelMaterial，不然会糊 */
export function texture(canvas: HTMLCanvasElement) {
  const t = new THREE.CanvasTexture(canvas)
  pixelFilter(t)
  t.colorSpace = THREE.SRGBColorSpace
  return t
}

/** 外面加载的像素图（道具）也按像素贴图过滤 */
export function pixelFilter(t: THREE.Texture) {
  t.magFilter = THREE.LinearFilter
  t.minFilter = THREE.LinearFilter
  t.generateMipmaps = false
  return t
}

/** 立牌：朝向镜头的竖板，底边中点落在 (x, y)；scale 为 1 时投影后一个贴图像素正好一个地图像素。
 *  frame 是图集里一帧的像素尺寸，不给就取整张图 */
export function standee(
  map: THREE.Texture,
  {
    emissive,
    scale = 1,
    frame,
  }: { emissive?: THREE.Texture; scale?: number; frame?: [number, number] } = {}
) {
  const img = map.image as HTMLCanvasElement
  const [fw, fh] = frame ?? [img.width, img.height]
  const w = fw * PIXEL * scale,
    h = fh * PIXEL * scale
  const g = new THREE.PlaneGeometry(w, h)
  g.translate(0, h / 2, 0)
  const m = pixelMaterial(
    new THREE.MeshLambertMaterial({ map, alphaTest: 0.5, side: THREE.DoubleSide })
  )
  // 立牌按俯角后仰，上半截会伸到身后：整张牌的深度都按底边算，身前的墙挡得住它，身后的墙挡不住
  m.onBeforeCompile = (shader) => {
    shader.vertexShader = shader.vertexShader.replace(
      '#include <project_vertex>',
      `#include <project_vertex>
  {
    vec4 baseClip = projectionMatrix * viewMatrix * modelMatrix * vec4(transformed.x, 0.0, transformed.z, 1.0);
    gl_Position.z = baseClip.z / baseClip.w * gl_Position.w;
  }`
    )
  }
  if (emissive) {
    m.emissiveMap = emissive
    m.emissive = new THREE.Color('#ffffff')
    m.emissiveIntensity = 0
  }
  const mesh = new THREE.Mesh(g, m)
  mesh.castShadow = true
  mesh.receiveShadow = true
  const depth = pixelMaterial(
    new THREE.MeshDepthMaterial({
      depthPacking: THREE.RGBADepthPacking,
      map,
      alphaTest: 0.5,
    })
  )
  mesh.customDepthMaterial = depth
  // 投影用的深度材质只挂在 customDepthMaterial 上，遍历场景时找不到，跟着主材质一起释放
  m.addEventListener('dispose', () => depth.dispose())
  return mesh
}

/** 立牌立在地图点 (x, y) 上，按俯角转向镜头；toward 是朝镜头方向挪的世界单位 */
export function stand(mesh: THREE.Object3D, x: number, y: number, tilt: Tilt, toward = 0) {
  mesh.position.set(x + toward * tilt.yawSin, 0, y + toward * tilt.yawCos)
  mesh.rotation.set(-tilt.pitch, tilt.yaw, 0, 'YXZ')
}

/** 立牌平面上、离地 texelsUp 个贴图像素的一点（灯罩、门灯），toward 同上 */
export function onStandee(
  object: THREE.Object3D,
  x: number,
  y: number,
  texelsUp: number,
  tilt: Tilt,
  toward = 0
) {
  const up = texelsUp * PIXEL
  const depth = toward - up * tilt.sin
  object.position.set(x + depth * tilt.yawSin, up * tilt.cos, y + depth * tilt.yawCos)
}
