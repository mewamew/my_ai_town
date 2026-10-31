import * as THREE from 'three'
import { MARGIN, PIXEL } from '../grid'
import { MAX_DEPTH } from '../pixel/island'
import { hashNoise } from './glsl'
import { addHaze, type HazeUniforms } from './horizon'
import type { MapTheme } from '../themes/types'

// 海面：一整块平面垫在地面下面，地面贴图上水的像素是透明的，露出海。
// 颜色按离岸像素数分档（近岸浅青、远处深蓝），档与档之间按有序抖动交错；外海有大片深浅不一的色斑和几处浅滩。
// 浅水透底：看得见沙底的波纹，水面折下来的光斑在沙底上游动。
// 外海是大片慢慢推过来的明暗起伏，亮处偶尔一道细细的反光；风大时反光变多，有的翻成白浪尖。
// 近岸浪线顺着岸往里推，水浅了走得慢、挤得密，到碎浪区断成白沫，过后留下一片碎沫；
// 浪冲上沙滩又退下去，前沿一线白沫，退后留下慢慢晾干的湿痕；拍在岩石上溅起白沫（这一段画在地面上，见 surfOnLand）。
// 池塘和外海不连着，只有透底和闪光，不起浪。下雨时水面一圈圈雨点；晴天有闪光，偶尔一个十字星芒。
// 越往北越融进海雾，直到海平线。全部按地图像素格取整，时间按每秒 8 步走，保持像素风。
// 废土里同一块平面画成干海床：离旧海岸越远越平、越白；成片龟裂、盐壳、旧水位线，零星碎贝壳。
// 冰雪里画成冰原：近岸冻得厚、发白，越远越蓝；近岸一圈碎浮冰，成片积雪、风吹雪纹、断续的冰堆，冰面偶尔一点反光。

/** 一道浪从外海推到岸上要多久（秒）；近岸浪线的疏密 */
const SURF_PERIOD = 3.4
const SURF_SPACING = 0.85

/** 近岸的浪，海面和地面共用。prefix 是噪声函数的前缀 */
const surf = (prefix: string) => /* glsl */ `
// 离岸 d 像素处的浪相位，0 是浪头。浪速随水深开方变慢，所以近岸一道道挤得密；
// 沿岸各段到岸的先后由大尺度噪声错开，不会整条海岸一起拍
float surfPhase(vec2 cell, float d, float t) {
  return fract(sqrt(d + 1.0) * ${SURF_SPACING} - t / ${SURF_PERIOD.toFixed(1)} + ${prefix}Noise(cell / 52.0) * 1.6);
}
// 上一道浪打到岸上之后过了多久（一个周期算 1）
float surfAge(vec2 cell, float t) {
  return 1.0 - surfPhase(cell, 0.0, t);
}
`

const HEADER = /* glsl */ `
uniform sampler2D uDepth;
uniform float uSeaTime;
uniform vec2 uOrigin;
uniform vec2 uSize;
uniform float uPixel;
uniform vec3 uBand[6];
uniform vec3 uSalt;
uniform vec3 uSeaBand[6];
uniform vec3 uFoam;
uniform vec3 uRipple;
uniform vec3 uGlint;
uniform vec3 uSand;
uniform float uSparkle;
uniform float uWind;
uniform float uRain;
varying vec2 vSeaPos;
${hashNoise('sea')}
${surf('sea')}
vec3 seaHex(vec3 c) { return pow(c / 255.0, vec3(2.2)); }
// 4×4 有序抖动（0～1）
float seaBayer2(vec2 a) { a = floor(a); return fract(dot(a, vec2(0.5, a.y * 0.75))); }
float seaBayer(vec2 a) { return seaBayer2(0.5 * a) * 0.25 + seaBayer2(a); }
// 时间换成哈希的种子：取模，开久了 sin 的参数不会大到失去精度
float seaTick(float rate) { return mod(floor(uSeaTime * rate), 241.0); }
// 泰森多边形：返回到最近两个格点的距离和最近那一格的编号（0～1），冰面的浮冰块用
vec3 seaCells(vec2 cell, float size) {
  vec2 g = floor(cell / size);
  float f1 = 1e9, f2 = 1e9, id = 0.0;
  for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
      vec2 o = g + vec2(float(i), float(j));
      vec2 p = (o + vec2(seaHash(o), seaHash(o + 17.0))) * size;
      float dist = length(cell - p);
      if (dist < f1) { f2 = f1; f1 = dist; id = seaHash(o + 5.0); } else if (dist < f2) f2 = dist;
    }
  return vec3(f1, f2, id);
}
// 焦散：格点绕着各自的位置慢慢转圈，两格距离差小的地方连成一张亮网
float seaCaustic(vec2 cell, float size, float t) {
  vec2 g = floor(cell / size);
  float f1 = 1e9, f2 = 1e9;
  for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
      vec2 o = g + vec2(float(i), float(j));
      float a = t * (0.6 + seaHash(o + 9.0) * 0.5) + seaHash(o) * 6.2832;
      vec2 p = (o + 0.5 + 0.34 * vec2(cos(a), sin(a * 1.3))) * size;
      float dist = length(cell - p);
      if (dist < f1) { f2 = f1; f1 = dist; } else if (dist < f2) f2 = dist;
    }
  return f2 - f1;
}
vec3 seaBandColor(float band) {
  return band < 1.0 ? seaHex(uSeaBand[0])
    : band < 2.0 ? seaHex(uSeaBand[1])
    : band < 3.0 ? seaHex(uSeaBand[2])
    : band < 4.0 ? seaHex(uSeaBand[3])
    : band < 5.0 ? seaHex(uSeaBand[4])
    : seaHex(uSeaBand[5]);
}
// 离岸贴图：r 是离岸（陆地是离水）的像素数，g 是岸边地物（1 外海的水，2 沙滩，3 岩石）；地图外都算外海深水
vec2 seaCoast(vec2 cell) {
  vec2 st = ((cell + 0.5) * uPixel - uOrigin) / uSize;
  if (st.x < 0.0 || st.y < 0.0 || st.x > 1.0 || st.y > 1.0) return vec2(${MAX_DEPTH.toFixed(1)}, 1.0);
  vec4 c = texture2D(uDepth, st);
  return vec2(c.r * 255.0, floor(c.g * 255.0 + 0.5));
}
`

const COLOR = /* glsl */ `
  vec2 cell = floor(vSeaPos / uPixel);
  vec2 coast = seaCoast(cell);
  float d = coast.x;
  bool open = coast.y == 1.0;
  float t = floor(uSeaTime * 8.0) / 8.0;
  float dither = seaBayer(cell);
  // 水深分档，外海叠上大片色斑和几处浅滩
  float deep = clamp((d - 8.0) / 16.0, 0.0, 1.0);
  float blotch = seaNoise(cell / 140.0) * 0.7 + seaNoise(cell / 50.0 + 7.0) * 0.3;
  float shoal = smoothstep(0.93, 0.98, seaNoise(cell / 70.0 + 31.0) * 0.8 + seaNoise(cell / 18.0 + 5.0) * 0.2);
  float band = log2(d + 0.5) + dither * 0.8 - 0.2 + deep * ((blotch - 0.5) * 1.1 - shoal * 2.0);
  vec3 c = seaBandColor(clamp(band, 0.0, 5.0));
  vec3 foam = seaHex(uFoam), ripple = seaHex(uRipple), glint = seaHex(uGlint);
  bool crest = false;

  // 浅水透底：沙底顺着岸的波纹，水面折下来的光斑在沙底上游动；越浅越清楚
  float clear = smoothstep(10.0, 1.0, d);
  if (clear > 0.0) {
    if (fract(d * 0.55 + seaNoise(cell / 6.0) * 1.4) < 0.2) c = mix(c, seaHex(uSand), 0.22 * clear);
    float net = min(seaCaustic(cell, 9.0, t), seaCaustic(cell + 4.0, 13.0, t * 0.8 + 3.0) + 0.35);
    if (net < 0.9) c = mix(c, mix(seaHex(uSeaBand[0]), foam, 0.55), 0.5 * clear);
  }

  // 外海：不画一条条浪纹，只有大片的明暗起伏，慢慢朝镜头这边（南）推，按抖动分成三档
  float far = smoothstep(7.0, 16.0, d);
  if (far > 0.0) {
    vec2 drift = vec2(0.6, 1.4) * t;
    float swell = sin((cell.y + seaNoise(cell / vec2(60.0, 120.0)) * 14.0) / 26.0 * 6.2832 - t * 0.5);
    float drifted = seaNoise((cell - drift) / 90.0) * 0.6 + seaNoise((cell - drift * 1.6) / 37.0) * 0.4;
    float light = (swell * 0.2 + (drifted - 0.5) * 2.0) * far;
    if (light > 0.2 + dither * 0.5) c *= 1.13;
    else if (light < -0.2 - dither * 0.5) c *= 0.9;
    // 反光：亮的那几片里偶尔一道一像素细的亮线，原地慢慢亮起又暗下去；风大时多，有的翻成白浪尖
    vec2 blk = floor(cell / vec2(12.0, 6.0));
    float cycle = uSeaTime * 0.22 + seaHash(blk + 2.0);
    float shown = seaHash(blk + mod(floor(cycle), 241.0));
    float chance = (0.05 + 0.15 * uWind) * (0.5 + max(light, 0.0));
    vec2 at = blk * vec2(12.0, 6.0) + floor(vec2(seaHash(blk + 4.0) * 4.0, 1.0 + seaHash(blk + 6.0) * 4.0));
    float len = floor((3.0 + seaHash(blk + 8.0) * 5.0) * sin(fract(cycle) * 3.1416) + 0.5);
    if (shown > 1.0 - chance && cell.y == at.y && cell.x >= at.x && cell.x < at.x + len) {
      crest = true;
      c = seaHash(blk + 11.0) < (uWind - 0.55) * 1.5 ? foam : mix(c, ripple, 0.55);
    }
  }

  if (open && d > 2.5 && d < 18.0) {
    // 近岸浪线：外面是一道亮线，越近岸越白，到碎浪区断成一串白沫；贴岸那两格交给下面的白沫
    float phase = surfPhase(cell, d, t);
    float cyc = 2.0 * sqrt(d + 1.0) / ${SURF_SPACING};
    float near = smoothstep(18.0, 9.0, d);
    float line = 1.0 / cyc;
    float breaking = smoothstep(7.0, 3.0, d);
    if (phase < line) {
      bool lace = seaHash(floor(cell / 2.0) + seaTick(2.0) * 7.0) > 0.3;
      c = mix(c, breaking > 0.5 && lace ? foam : mix(ripple, foam, breaking * 0.8), near * 0.85);
      crest = true;
    } else if (d < 7.0 && phase < line + 3.0 / cyc) {
      // 浪头过后留下的碎沫，越往后越稀
      float after = (phase - line) * cyc / 3.0;
      if (seaNoise(cell / 2.3 + vec2(t * 0.4, 0.0)) > 0.64 + after * 0.3) c = mix(c, foam, 0.5 * breaking);
    } else if (phase > 1.0 - 1.0 / cyc && d > 3.0) c *= 0.9;
  }
  if (open && d < 2.5) {
    // 贴岸的白沫跟着浪：浪刚打上来时成片，退下去只剩零星
    float age = surfAge(cell, t);
    float keep = d < 1.5 ? (age < 0.25 ? 0.15 : 0.62) : (age < 0.1 ? 0.6 : 1.0);
    if (seaHash(cell + seaTick(3.0) * 13.0) > keep) c = mix(c, foam, d < 1.5 ? 1.0 : 0.6);
  }
  // 池塘边一圈淡淡的水线
  if (!open && d < 1.5 && seaHash(cell + seaTick(2.0)) > 0.5) c = mix(c, foam, 0.5);

  // 雨点：每 10×10 格最多一处，落下先是一个点，再散成上下左右四瓣，淡淡的
  if (uRain > 0.01) {
    c *= 1.0 - 0.12 * uRain;
    vec2 g = floor(cell / 10.0);
    float rt = uSeaTime * 1.8 + seaHash(g + 0.37);
    float k = mod(floor(rt), 241.0), age = fract(rt);
    vec2 drop = g * 10.0 + 3.0 + floor(vec2(seaHash(g + k), seaHash(g + k + 3.1)) * 4.0);
    vec2 off = abs(cell - drop);
    bool hit = age < 0.4 ? off.x + off.y == 0.0 : off.x + off.y == 1.0;
    if (seaHash(g + k * 1.7) < uRain * 0.25 && hit) c = mix(c, ripple, age < 0.4 ? 0.5 : 0.35);
  }

  // 闪光：零星亮点，浪脊上多一些；更少的大亮点带十字星芒
  float sparkle = uSparkle * (1.0 - uRain);
  if (seaHash(cell + vec2(seaTick(3.0) * 17.0, 3.0)) > 1.0 - sparkle * (crest ? 0.03 : 0.002)) c = glint;
  if (sparkle > 0.0 && d > 3.0) {
    float s = seaTick(2.0) * 31.0;
    float star = 1.0 - 0.0005 * sparkle;
    if (seaHash(cell + vec2(s, 7.0)) > star) c = glint * 1.15;
    else if (seaHash(cell + vec2(s + 1.0, 7.0)) > star || seaHash(cell + vec2(s - 1.0, 7.0)) > star
      || seaHash(cell + vec2(s, 8.0)) > star || seaHash(cell + vec2(s, 6.0)) > star) c = mix(c, glint, 0.6);
  }
  diffuseColor.rgb = c;
`

const SEABED = /* glsl */ `
  vec2 cell = floor(vSeaPos / uPixel);
  float d = seaCoast(cell).x;
  float deep = clamp((d - 8.0) / 16.0, 0.0, 1.0);
  float blotch = seaNoise(cell / 140.0) * 0.7 + seaNoise(cell / 50.0 + 7.0) * 0.3;
  float band = log2(d + 0.5) + seaHash(cell) * 0.8 - 0.2 + deep * (blotch - 0.5) * 1.4;
  band = clamp(band, 0.0, 5.0);
  vec3 c = band < 1.0 ? uBand[0] : band < 2.0 ? uBand[1] : band < 3.0 ? uBand[2]
    : band < 4.0 ? uBand[3] : band < 5.0 ? uBand[4] : uBand[5];
  // 龟裂：泰森多边形，越远格子越大
  float size = 7.0 + deep * 6.0;
  vec2 g = floor(cell / size);
  float f1 = 1e9, f2 = 1e9;
  for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
      vec2 o = g + vec2(float(i), float(j));
      vec2 p = (o + vec2(seaHash(o), seaHash(o + 17.0))) * size;
      float dist = length(cell - p);
      if (dist < f1) { f2 = f1; f1 = dist; } else if (dist < f2) f2 = dist;
    }
  bool cracked = f2 - f1 < 0.9 && seaNoise(cell / 40.0 + 3.0) > 0.35;
  // 盐壳：远处成片发白
  float salt = seaNoise(cell / 35.0 + 13.0) * 0.7 + seaNoise(cell / 9.0 + 5.0) * 0.3;
  if (deep > 0.3 && salt > 0.64) c = mix(c, uSalt, 0.3 + 0.15 * step(0.72, salt));
  // 旧水位线：离岸每隔 6 格一道浅痕，断断续续
  if (d < 22.0 && mod(floor(d), 6.0) == 0.0 && seaHash(floor(cell / 3.0)) > 0.35) c = mix(c, uSalt, 0.3);
  if (cracked) c *= 0.7;
  if (seaHash(cell + 11.0) > 0.994) c = uSalt * 1.08;
  diffuseColor.rgb = c;
`

const ICE = /* glsl */ `
  vec2 cell = floor(vSeaPos / uPixel);
  float d = seaCoast(cell).x;
  float deep = clamp((d - 4.0) / 20.0, 0.0, 1.0);
  float band = log2(d + 0.5) + seaHash(cell) * 0.8 - 0.2 + (seaNoise(cell / 60.0) - 0.5) * 1.2 * deep;
  band = clamp(band, 0.0, 5.0);
  vec3 c = band < 1.0 ? uBand[0] : band < 2.0 ? uBand[1] : band < 3.0 ? uBand[2]
    : band < 4.0 ? uBand[3] : band < 5.0 ? uBand[4] : uBand[5];
  // 积雪：大片横向拉长的白，边缘柔和，不碎成小块
  float snow = seaNoise(cell / vec2(110.0, 60.0) + 3.0) * 0.85 + seaNoise(cell / 34.0 + 9.0) * 0.15;
  if (snow > 0.64) c = mix(c, uSalt, snow > 0.68 ? 0.7 : 0.35);
  // 风吹雪纹：顺着东西向的细长淡痕，只在没有积雪的冰面上
  if (snow <= 0.64 && seaNoise(vec2(cell.x / 45.0, cell.y / 1.8) + 50.0) > 0.78) c = mix(c, uSalt, 0.22);
  // 近岸碎浮冰：离岸越近冰块越小，块与块之间露出深色水缝，往外合成整片冰
  if (d > 1.5 && d < 30.0) {
    float near = 1.0 - (d - 1.5) / 28.5;
    // 格子大小固定：随距离变的话相邻像素的格子对不上，边就断了
    vec3 floe = seaCells(cell, 7.0);
    c *= 0.96 + floe.z * 0.08;
    if (floe.y - floe.x < 0.9 && seaHash(floor(cell / 3.0) + 31.0) < near * 1.2) c = mix(c, uBand[5] * 0.78, 0.55);
  }
  // 冰堆：沿一条大尺度等值线挤起来的碎冰块，断断续续，每两格一块，亮面和背光面分开
  float ridge = abs(seaNoise(cell / 120.0 + 21.0) - 0.5);
  if (ridge < 0.012 && seaNoise(cell / 18.0 + 40.0) > 0.55) {
    float block = seaHash(floor(cell / 2.0) + 60.0);
    c = block > 0.55 ? mix(c, uSalt, 0.85) : block > 0.2 ? c * 0.82 : c;
  }
  if (d < 1.5) c = uSalt;
  // 冰面反光：稀疏的亮点，隔一会儿换一处
  if (seaHash(cell + vec2(seaTick(3.0) * 7.0, 1.0)) > 0.9985) c = vec3(1.0);
  diffuseColor.rgb = c;
`

/** 离岸距离和岸边地物（见 Ground.shore）合成一张两通道贴图，海面和沙滩上的浪共用 */
export function coastTexture(depth: Uint8Array, shore: Uint8Array, pw: number, ph: number) {
  const data = new Uint8Array(pw * ph * 2)
  for (let i = 0; i < pw * ph; i++) {
    data[i * 2] = depth[i]
    data[i * 2 + 1] = shore[i]
  }
  const map = new THREE.DataTexture(data, pw, ph, THREE.RGFormat, THREE.UnsignedByteType)
  map.magFilter = map.minFilter = THREE.NearestFilter
  map.needsUpdate = true
  return map
}

/** 外圈的材质：会动的海，或者干海床、冰原。coast 是 coastTexture 的贴图，画布左上角在世界坐标
 *  (-MARGIN, -MARGIN)；haze 是远景的海雾。time 是秒，sparkle 是闪光的多少（0～1，随昼夜和云量） */
export function outerMaterial(coast: THREE.DataTexture, haze: HazeUniforms, theme: MapTheme) {
  const { width: pw, height: ph } = coast.image
  const time = { value: 0 }
  const sparkle = { value: 1 }
  const surface = theme.ground.seaSurface
  if (theme.outer === 'sea' && !surface) throw Error('外圈是海的风格包要给 ground.seaSurface')
  // 海的颜色按 0～255 交给着色器，在着色器里换算成线性值
  const raw = (hex: string) => {
    const n = parseInt(hex.slice(1), 16)
    return new THREE.Vector3(n >> 16, (n >> 8) & 255, n & 255)
  }
  const material = new THREE.MeshStandardMaterial({
    roughness: theme.outer === 'seabed' ? 1 : theme.outer === 'ice' ? 0.35 : 0.5,
    metalness: 0,
  })
  // 离岸贴图只放在着色器的 uniform 里，材质释放时一起释放
  material.addEventListener('dispose', () => coast.dispose())
  material.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, {
      uDepth: { value: coast },
      uSeaTime: time,
      uOrigin: { value: new THREE.Vector2(-MARGIN, -MARGIN) },
      uSize: { value: new THREE.Vector2(pw * PIXEL, ph * PIXEL) },
      uPixel: { value: PIXEL },
      uBand: { value: theme.ground.outer.map((c) => new THREE.Color(c)) },
      uSalt: { value: new THREE.Color(theme.ground.outerSpot ?? theme.ground.outer[5]) },
      uSeaBand: { value: theme.ground.outer.map(raw) },
      uFoam: { value: raw(surface?.foam ?? '#000000') },
      uRipple: { value: raw(surface?.ripple ?? '#000000') },
      uGlint: { value: raw(surface?.glint ?? '#000000') },
      uSand: { value: raw(theme.ground.sand[0]) },
      uSparkle: sparkle,
    })
    shader.vertexShader =
      'varying vec2 vSeaPos;\n' +
      shader.vertexShader.replace(
        '#include <begin_vertex>',
        '#include <begin_vertex>\n  vSeaPos = (modelMatrix * vec4(transformed, 1.0)).xz;'
      )
    const body = theme.outer === 'seabed' ? SEABED : theme.outer === 'ice' ? ICE : COLOR
    shader.fragmentShader = HEADER + shader.fragmentShader.replace('#include <map_fragment>', body)
    addHaze(shader, haze)
  }
  return { material, time, sparkle }
}

/** 浪冲上沙滩：沙滩上的地面材质补一段着色。浪打到岸上那一刻和海面的浪线对得上（共用 surfPhase）：
 *  一层薄水冲上来，前沿一线白沫、沫里零星气泡，退下去留下湿痕慢慢晾干；拍在岩石上那一下溅起白沫 */
export function surfOnLand(
  material: THREE.MeshPhongMaterial,
  coast: THREE.DataTexture,
  time: { value: number },
  theme: MapTheme
) {
  const { width: pw, height: ph } = coast.image
  const before = material.onBeforeCompile.bind(material)
  const beforeKey = material.customProgramCacheKey()
  material.onBeforeCompile = (shader, renderer) => {
    before(shader, renderer)
    Object.assign(shader.uniforms, {
      uCoast: { value: coast },
      uSeaTime: time,
      uCoastOrigin: { value: new THREE.Vector2(-MARGIN, -MARGIN) },
      uCoastSize: { value: new THREE.Vector2(pw * PIXEL, ph * PIXEL) },
      uShallow: { value: new THREE.Color(theme.ground.outer[1]) },
      uSurfFoam: { value: new THREE.Color(theme.ground.seaSurface?.foam ?? '#ffffff') },
    })
    shader.vertexShader =
      'varying vec2 vSurfPos;\n' +
      shader.vertexShader.replace(
        '#include <begin_vertex>',
        '#include <begin_vertex>\n  vSurfPos = (modelMatrix * vec4(transformed, 1.0)).xz;'
      )
    shader.fragmentShader =
      `uniform sampler2D uCoast;
uniform float uSeaTime;
uniform vec2 uCoastOrigin;
uniform vec2 uCoastSize;
uniform vec3 uShallow;
uniform vec3 uSurfFoam;
uniform float uWind;
varying vec2 vSurfPos;
${hashNoise('surf')}
${surf('surf')}
` +
      shader.fragmentShader.replace(
        '#include <map_fragment>',
        `#include <map_fragment>
  {
    vec2 cell = floor(vSurfPos / ${PIXEL.toFixed(1)});
    vec4 coast = texture2D(uCoast, ((cell + 0.5) * ${PIXEL.toFixed(1)} - uCoastOrigin) / uCoastSize);
    float kind = floor(coast.g * 255.0 + 0.5), ld = coast.r * 255.0;
    float t = floor(uSeaTime * 8.0) / 8.0;
    float age = surfAge(cell, t);
    if (kind == 2.0 && ld < 6.5) {
      // 一道浪：冲上来（白沫打头）→ 在最高处停一下（白沫散开）→ 退下去（只剩青色的水边往回收），
      // 身后留下深色的湿沙慢慢晾干。冲多远看这一段沙滩，风大冲得远
      float reach = (2.0 + 3.0 * surfNoise(cell / 23.0 + 4.0)) * (0.8 + 0.4 * uWind);
      float now = age < 0.2 ? reach * sin(age / 0.2 * 1.5708)
        : age < 0.35 ? reach
        : reach * pow(max(0.0, 1.0 - (age - 0.35) / 0.5), 1.3);
      bool rushing = age < 0.35;
      if (ld <= now + 0.5) {
        // 薄薄一层水：浅水的青色，靠前沿那一格和湿沙按格子交错，像透出底下的沙
        float inFilm = now - ld;
        float fizz = surfHash(cell + mod(floor(uSeaTime * 4.0), 241.0) * 3.0);
        bool front = rushing && inFilm < 0.8 && (age < 0.2 || fizz > 0.5);
        bool bubble = rushing && inFilm < 2.0 && fizz > 0.86;
        bool thin = inFilm < 1.0 && mod(cell.x + cell.y, 2.0) < 1.0;
        diffuseColor.rgb = front || bubble ? uSurfFoam : thin ? diffuseColor.rgb * 0.7 : uShallow;
      } else if (!rushing && ld <= reach + 0.5) {
        diffuseColor.rgb *= 1.0 - 0.34 * clamp(1.0 - (age - 0.35) / 0.65, 0.0, 1.0);
      }
    } else if (kind == 3.0 && ld < 1.5 && age < 0.2) {
      if (surfHash(cell + mod(floor(uSeaTime * 8.0), 241.0) * 5.0) > 0.5 + age * 2.5) diffuseColor.rgb = uSurfFoam;
    }
  }`
      )
  }
  material.customProgramCacheKey = () => `${beforeKey}|surf`
}
