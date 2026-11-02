import * as THREE from 'three'

// 像素贴图的抗锯齿采样：贴图用线性过滤，采样点吸到最近的贴图像素中心，只在两个像素的交界处
// 留一个屏幕像素宽的过渡。整数倍放大时和最近邻一样锐利；缩放动画、转方位、非整数倍时
// 像素大小一致，不再一胖一瘦、边缘爬行。
// 改的是 three 的公共着色器片段，只对定义了 PIXEL_SAMPLING 的材质生效（pixelMaterial 打的标记），
// 其余材质（光晕贴片、粒子、后期）照旧。

const SAMPLER = /* glsl */ `
#ifdef PIXEL_SAMPLING
vec4 pixelTexture( sampler2D t, vec2 uv ) {
  vec2 size = vec2( textureSize( t, 0 ) );
  vec2 p = uv * size;
  vec2 seam = floor( p + 0.5 );
  p = seam + clamp( ( p - seam ) / max( fwidth( p ), vec2( 1e-5 ) ), -0.5, 0.5 );
  return texture2D( t, p / size );
}
#define PIXEL_TEXTURE pixelTexture
#else
#define PIXEL_TEXTURE texture2D
#endif
`

const chunks = THREE.ShaderChunk as unknown as Record<string, string>
function patch(name: string, from: string, to: string) {
  const before = chunks[name]
  if (before.includes(to)) return
  const after = before.replace(from, to)
  if (after === before) console.warn(`像素采样没能改写着色器片段 ${name}`)
  chunks[name] = after
}
if (!chunks.map_pars_fragment.includes('PIXEL_TEXTURE')) chunks.map_pars_fragment += SAMPLER
patch('map_fragment', 'texture2D( map, vMapUv )', 'PIXEL_TEXTURE( map, vMapUv )')
patch(
  'emissivemap_fragment',
  'texture2D( emissiveMap, vEmissiveMapUv )',
  'PIXEL_TEXTURE( emissiveMap, vEmissiveMapUv )'
)

/** 让材质的贴图走像素抗锯齿采样；贴图本身要是线性过滤（standee.ts 的 texture() 就是） */
export function pixelMaterial<T extends THREE.Material>(material: T): T {
  material.defines = { ...material.defines, PIXEL_SAMPLING: '' }
  material.needsUpdate = true
  return material
}
