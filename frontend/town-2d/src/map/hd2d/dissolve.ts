import type * as THREE from 'three'

// 房子外壳按像素格溶解：掀开、盖回屋顶时外壳一格格去掉或长回来。格子按 4×4 有序抖动取舍，
// 和光照图、像素海面的过渡同一种画法；一格是画面上一个地图像素大，跟着缩放走。
// 去掉的格子连深度也不写，屋里的墙、人和道具从格子里露出来。

const DISSOLVE = /* glsl */ `
uniform float uDissolve;
uniform float uDissolveCell;
float dissolveBayer2(vec2 a) { a = floor(a); return fract(dot(a, vec2(0.5, a.y * 0.75))); }
float dissolveBayer(vec2 a) { return dissolveBayer2(0.5 * a) * 0.25 + dissolveBayer2(a); }
`

/** uDissolve：去掉的比例（0 完整～1 全去掉），一栋房子的材质共用一个；uDissolveCell：一格多少画布像素 */
export interface Dissolve {
  uDissolve: { value: number }
  uDissolveCell: { value: number }
}

/** 材质接上溶解；接在其他着色器改写之后 */
export function dissolvable(material: THREE.Material, uniforms: Dissolve) {
  const before = material.onBeforeCompile.bind(material)
  const beforeKey = material.customProgramCacheKey()
  material.onBeforeCompile = (shader, renderer) => {
    before(shader, renderer)
    Object.assign(shader.uniforms, uniforms)
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>\n${DISSOLVE}`)
      .replace(
        'void main() {',
        `void main() {
          if (uDissolve > 0.0 && dissolveBayer(gl_FragCoord.xy / uDissolveCell) < uDissolve) discard;`
      )
  }
  material.customProgramCacheKey = () => `${beforeKey}|dissolve`
}
