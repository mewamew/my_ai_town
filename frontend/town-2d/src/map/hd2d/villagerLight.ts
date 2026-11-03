import * as THREE from 'three'
import { MATERIAL_STEP } from './villagerRig'

// 村民立牌的受光：villagerRig.ts 按字母格算出每格的材质和像素法线（「枕头」形，8 个方向 × 2 档倾斜），
// 和颜色一起上传。这里改立牌的着色器：太阳光按法线分三档明暗（皮肤、金属各有各的档），头发多一圈高光、
// 金属多一个闪点，逆光时皮肤边上透一点暖色；夜里给人一个最暗下限（约原色的四成，偏一点蓝），离灯最远的人
// 也看得清轮廓，傍晚站在房子阴影里的人脸也不发灰。原画自带的明暗不动，只在太阳那份光上乘一档；
// 选中、悬停的描边不受光。画质低、中档不接（见 Villagers.setDetail）

/** 所有村民共用：太阳在画面上的方向（右、上、朝镜头），太阳有多亮（0 夜里～1 白天），夜里保底的程度 */
export const villagerLight = {
  uSunScreen: { value: new THREE.Vector3(0, 0.6, 0.8) },
  uSunUp: { value: 1 },
  uFloor: { value: 0.36 },
  uFloorTint: { value: new THREE.Color(0, 0, 0) },
  /** 按法线分档、高光闪点：高档以上才开（0 关 1 开）；保底和描边哪一档都有 */
  uShape: { value: 1 },
}

const MATERIALS = /* glsl */ `
uniform sampler2D uNormals;
uniform vec3 uSunScreen;
uniform float uSunUp;
uniform float uFloor;
uniform vec3 uFloorTint;
uniform float uShape;
// 法线图里这一格：法线（画面右、上、朝镜头）、材质编号、是不是最外一圈
vec4 villagerTexel() {
  vec2 size = vec2(textureSize(uNormals, 0));
  return texture2D(uNormals, (floor(vMapUv * size) + 0.5) / size);
}
float villagerMaterial(vec4 t) { return floor(t.b * 255.0 / ${MATERIAL_STEP.toFixed(1)} + 0.5); }
vec3 villagerNormal(vec4 t) {
  vec2 n = t.rg * 2.0 - 1.0;
  return vec3(n, sqrt(max(0.0, 1.0 - dot(n, n))));
}`

/** 太阳那份光按法线分档：亮、中、暗三档；头发高光、金属闪点。法线图只取一次，后面保底也用 */
const BANDS = /* glsl */ `
vec4 vt = villagerTexel();
float vm = villagerMaterial(vt);
{
  vec3 vn = villagerNormal(vt);
  vec3 L = normalize(uSunScreen);
  float d = dot(vn, L);
  float band = d > 0.72 ? 1.14 : d > 0.3 ? 1.0 : 0.84;
  if (vm > 1.5 && vm < 2.5) band = d > 0.5 ? 1.08 : d > -0.1 ? 1.0 : 0.92;
  if (vm > 4.5 && vm < 5.5) band = d > 0.72 ? 1.3 : d > 0.3 ? 1.0 : 0.74;
  if (vm < 0.5 || vm > 5.5) band = 1.0;
  vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
  float nh = dot(vn, H);
  // 头发的高光圈、金属的闪点：都跟着太阳那份光走，影子里就没了
  float shine = (vm > 0.5 && vm < 1.5 && nh > 0.93) ? 0.45 : (vm > 4.5 && vm < 5.5 && nh > 0.96) ? 1.4 : 0.0;
  reflectedLight.directDiffuse *= mix(1.0, band, uShape) + shine * uSunUp * uShape;
  // 逆光时皮肤边上透一点暖色
  if (vm > 1.5 && vm < 2.5 && vt.a < 0.75 && L.z < 0.0)
    reflectedLight.directDiffuse += diffuseColor.rgb * vec3(0.32, 0.14, 0.06) * (-L.z) * uSunUp * uShape;
}`

/** 夜里保底：最暗不低于原色的这么多，偏一点蓝；描边发光，不受光 */
const FLOOR = /* glsl */ `
{
  if (vm > 6.5) outgoingLight = diffuseColor.rgb;
  else if (vm > 0.5) outgoingLight = max(outgoingLight, diffuseColor.rgb * (uFloor + (vm > 1.5 && vm < 2.5 ? 0.06 : 0.0)) + uFloorTint);
}`

/** 给一个村民立牌的材质接上它自己的法线图；要在材质第一次画之前接 */
export function shadeVillager(material: THREE.Material, normals: THREE.Texture) {
  const before = material.onBeforeCompile.bind(material)
  const beforeKey = material.customProgramCacheKey()
  material.onBeforeCompile = (shader, renderer) => {
    before(shader, renderer)
    Object.assign(shader.uniforms, villagerLight, { uNormals: { value: normals } })
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <map_pars_fragment>', `#include <map_pars_fragment>\n${MATERIALS}`)
      .replace('#include <lights_fragment_end>', `#include <lights_fragment_end>\n${BANDS}`)
      .replace('#include <opaque_fragment>', `${FLOOR}\n#include <opaque_fragment>`)
  }
  material.customProgramCacheKey = () => `${beforeKey}|villager-light`
  return material
}
