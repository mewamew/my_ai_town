import { DEFAULT_PRESET, STYLE_PRESETS } from '../map/themes/presets'

/** 地图风格：隐藏的下拉框和卡片，都按风格名单生成 */
const styleOptions = STYLE_PRESETS.map((p) => `<option value="${p.id}">${p.name}</option>`).join('')
const styleCards = STYLE_PRESETS.map(
  (p) =>
    `<button type="button" data-value="${p.id}" aria-pressed="${p.id === DEFAULT_PRESET.id}"><span class="style-scene" style="--style-swatch: ${p.swatch}" aria-hidden="true">${p.icon}</span><strong>${p.name}</strong><small>${p.description}</small></button>`
).join('')

/** 第一步的例子：点一下填进描述框。写的是地方和过日子的方式，不是方位和数量 */
const EXAMPLES: [string, string][] = [
  ['海边渔村', '海边的小渔村，大家靠打鱼为生，傍晚在码头卖鱼，村口有一家小酒馆。'],
  ['冰雪小镇', '冰天雪地里的小镇，大家凿冰捕鱼、进林子打猎，镇上有温泉和一家酒馆。'],
  ['废土避难所', '末日废土上的避难所，几户人家挤在铁皮屋里，没有干净的水。'],
  ['三国边城', '三国时期的边城，有县衙、酒肆和铁匠铺，城里有个热闹的集市。'],
  ['四人宿舍', '大学宿舍楼，住着四个室友，楼下有食堂和自习室。'],
]
const examples = EXAMPLES.map(
  ([label, text]) => `<button type="button" data-example="${text}">${label}</button>`
).join('')

/** 创建小镇面板的静态骨架；所有动态内容由 creator.ts 用 DOM 写入。 */
export const creatorTemplate = `
<div class="creator-stage" aria-label="小镇预览">
  <div id="creator-preview" class="creator-preview"></div>
</div>

<section class="creator-panel">
  <header class="creator-heading">
    <button type="button" id="creator-back" class="creator-back">← 返回选择小镇</button>
    <div class="creator-title-block">
      <h1>建造你的小镇</h1>
      <p>写一句话就能建一个小镇，也可以自己一项项选。</p>
    </div>
    <div id="creator-heading-actions" class="creator-heading-actions"></div>
  </header>

  <main class="creator-main">
    <div id="creator-before-form" class="creator-before-form"></div>
    <form id="creator-form" class="creator-form">
      <fieldset id="creator-layout-stage" class="layout-stage">
        <legend class="creator-visually-hidden">小镇规划</legend>

        <button type="button" class="creator-step" data-creator-step="basics" data-hint="描述或名称"><span>1</span><strong>基础</strong><small>描述或名称</small></button>
        <section class="creator-step-panel" data-creator-panel="basics">
          <div class="creator-panel-heading">
            <div><span>1</span><h2 id="basics-title">说说你想要的小镇</h2></div>
            <p id="basics-hint">写一句话：这是个什么地方、大家怎么过日子。地点的名字、写给村民的背景、住进来的人都按它来。</p>
          </div>
          <section id="creator-language" class="creator-language">
            <textarea id="town-description" maxlength="2000" rows="4" aria-label="描述你想要的小镇" placeholder="例如：海边的小渔村，大家靠打鱼为生，傍晚在码头卖鱼，村口有一家小酒馆。"></textarea>
            <div class="creator-examples" role="group" aria-label="例子">${examples}</div>
            <div id="generation-model" class="creator-model-line"></div>
            <button type="button" class="creator-link" data-mode="parameters">自己一项项选环境和地点 →</button>
          </section>
          <div class="creator-basic-grid">
            <label class="creator-name-field">小镇名称
              <input id="town-name" maxlength="60" required value="新小镇">
            </label>
            <button type="button" class="creator-link" data-mode="language">改用一句话描述 →</button>
          </div>
          <input id="town-seed" type="hidden" value="-1">
        </section>

        <button type="button" class="creator-step" data-creator-step="environment" data-hint="地貌与生活条件"><span>2</span><strong>环境</strong><small>地貌与生活条件</small></button>
        <section class="creator-step-panel" data-creator-panel="environment" hidden>
          <div class="creator-panel-heading">
            <div><span>2</span><h2>选择小镇环境</h2></div>
            <p>选择小镇的画面风格、树丛密度和生活条件。</p>
          </div>
          <div id="creator-environment-extension"></div>
          <section class="creator-setting-block" aria-label="地图类型">
            <h3>地图风格</h3>
            <select id="town-style" hidden>${styleOptions}</select>
            <div class="creator-style-cards" data-choice-for="town-style">${styleCards}</div>
          </section>
          <div class="creator-environment-grid">
            <section class="creator-setting-block" aria-label="树丛">
              <h3>树丛密度</h3>
              <select id="town-vegetation" hidden><option value="sparse">稀疏</option><option value="medium" selected>适中</option><option value="dense">茂密</option></select>
              <div class="creator-choice-cards" data-choice-for="town-vegetation">
                <button type="button" data-value="sparse" aria-pressed="false"><span aria-hidden="true">♧</span>稀疏</button>
                <button type="button" data-value="medium" aria-pressed="true"><span aria-hidden="true">♧♧</span>适中</button>
                <button type="button" data-value="dense" aria-pressed="false"><span aria-hidden="true">♧♧♧</span>茂密</button>
              </div>
            </section>
            <section class="creator-setting-block" aria-label="生活资源">
              <h3>生活条件</h3>
              <select id="town-resources" hidden><option value="normal-life">正常生活</option><option value="no-food">没有食物</option><option value="no-water">没有饮水</option><option value="no-rest">没有休息道具</option><option value="poisoned-food">变质干粮</option></select>
              <div class="creator-choice-cards resources" data-choice-for="town-resources">
                <button type="button" data-value="normal-life" aria-pressed="true" title="每户有床、干粮和水"><span aria-hidden="true">⌂</span>正常生活</button>
                <button type="button" data-value="no-food" aria-pressed="false" title="村民会饿"><span aria-hidden="true">∅</span>没有食物<small class="creator-hard">难度高</small></button>
                <button type="button" data-value="no-water" aria-pressed="false" title="村民会渴"><span aria-hidden="true">♧</span>没有饮水<small class="creator-hard">难度高</small></button>
                <button type="button" data-value="no-rest" aria-pressed="false" title="没有床"><span aria-hidden="true">⊘</span>没有休息道具<small class="creator-hard">难度高</small></button>
                <button type="button" data-value="poisoned-food" aria-pressed="false" title="吃了会病"><span aria-hidden="true">⚠</span>变质干粮<small class="creator-hard">难度高</small></button>
              </div>
              <p id="town-resources-effect" class="creator-hint creator-effect" role="status"></p>
            </section>
            <section class="creator-setting-block" aria-label="地点之间">
              <h3>地点之间</h3>
              <select id="town-settlement" hidden><option value="town" selected>街道相连</option><option value="wild">野外小径</option><option value="ring">环岛小径</option></select>
              <div class="creator-choice-cards" data-choice-for="town-settlement">
                <button type="button" data-value="town" aria-pressed="true" title="小镇：地点之间是街道"><span aria-hidden="true">⌂</span>街道相连</button>
                <button type="button" data-value="wild" aria-pressed="false" title="荒岛、野地：地点之间是踩出来的小路"><span aria-hidden="true">⋯</span>野外小径</button>
                <button type="button" data-value="ring" aria-pressed="false" title="大的荒岛：户外地点沿海岸排一圈，一条小路绕岛，岛中间是林地"><span aria-hidden="true">◯</span>环岛小径</button>
              </div>
              <p class="creator-hint">按选的地点生成道路、建筑和周边环境；港口与海塔会安排在岸边。荒岛、野地选「野外小径」，路上不会出现「小镇」「街道」的字样；「环岛小径」把户外地点沿海岸排成一圈，地点越多岛越大，只能选户外地点。</p>
            </section>
          </div>
        </section>

        <button type="button" class="creator-step" data-creator-step="places" data-hint="建筑与公共空间"><span>3</span><strong>地点</strong><small>建筑与公共空间</small></button>
        <section class="creator-step-panel" data-creator-panel="places" hidden>
          <div class="creator-panel-heading">
            <div><span>3</span><h2>安排地点和建筑</h2></div>
            <p>地点数量会影响镇子范围。独特地标每种只能建一处。</p>
          </div>
          <div id="creator-planning" class="creator-planning"></div>
          <div id="town-counts" class="creator-capacity" role="status" aria-live="polite"></div>
          <div class="creator-place-filters" role="tablist" aria-label="地点分类">
            <button type="button" data-place-filter="everyday" aria-selected="true">住宅与公共建筑</button>
            <button type="button" data-place-filter="landmarks" aria-selected="false">地标与游乐设施</button>
            <button type="button" data-place-filter="outdoor" aria-selected="false">户外空间</button>
          </div>
          <div id="town-places" class="creator-place-grid"></div>
          <div class="creator-selected-heading"><span>已选地点 · 点减号去掉一处</span><button type="button" id="clear-places">清空</button></div>
          <div id="town-selected" class="creator-selected"></div>
          <div class="creator-single-area"><button type="button" id="single-area">只保留一处活动区域</button><p id="single-area-hint" class="creator-hint">整个小镇就是一片空地（比如一座公园），没有房子和道路，村民直接出现在那里。</p></div>
        </section>

        <button type="button" class="creator-step" data-creator-step="preview" data-hint="检查并保存小镇"><span>4</span><strong>预览</strong><small>检查并保存小镇</small></button>
        <section class="creator-step-panel creator-review-panel" data-creator-panel="preview" hidden>
          <div class="creator-panel-heading">
            <div><span>4</span><h2>看看这座小镇</h2></div>
            <p id="preview-hint"></p>
          </div>
        </section>
      </fieldset>
    </form>
    <section id="creator-result" class="creator-result" aria-label="这座小镇" hidden>
      <label class="creator-draft-name">小镇名字
        <input id="draft-name" maxlength="60" autocomplete="off">
      </label>
      <div id="creator-plan" class="creator-plan"></div>
      <div id="creator-refine" class="creator-refine">
        <label for="refine-text">还想改什么？</label>
        <textarea id="refine-text" rows="2" maxlength="300" placeholder="比如：酒馆挪到码头边，再加一座灯塔"></textarea>
        <div class="creator-refine-actions">
          <button type="button" id="refine-town">按这句改</button>
          <button type="button" id="reparse-town" class="creator-link">换一种理解</button>
        </div>
      </div>
    </section>
  </main>

  <footer class="creator-footer">
    <div class="creator-status-block">
      <p id="creator-status" role="status">从基础设定开始。</p>
      <div id="generation-progress" class="generation-progress" hidden>
        <progress id="generation-progress-bar"></progress>
        <small id="generation-progress-detail">等待开始…</small>
      </div>
    </div>
    <div class="creator-footer-actions">
      <button type="button" id="creator-prev-step">上一步</button>
      <button type="button" id="creator-next-step" class="creator-primary">下一步</button>
      <button type="button" id="parse-town" class="creator-primary" hidden>生成小镇</button>
      <button type="submit" form="creator-form" id="generate-town" class="creator-primary" hidden>生成小镇预览</button>
      <button type="button" id="reroll-town" hidden>换一张布局</button>
      <button type="button" id="cancel-generation" hidden>取消生成</button>
      <button type="button" id="save-only" hidden>只保存</button>
      <button type="button" id="save-town" class="creator-primary" disabled hidden>保存并进镇</button>
    </div>
  </footer>
</section>`
