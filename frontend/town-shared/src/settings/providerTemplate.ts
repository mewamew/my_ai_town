import type { ProviderPreset } from '../providers'
export function providerTemplate(preset: ProviderPreset) {
  return `
    <label class="prov-field">服务地址
      <input id="p-url-${preset.id}" class="p-url" spellcheck="false">
    </label>
    <label class="prov-field">API 密钥
      <input id="p-key-${preset.id}" class="p-key" type="password" spellcheck="false" autocomplete="off">
    </label>
    <label class="prov-field">模型名
      <input id="p-model-${preset.id}" class="p-model" list="p-models-${preset.id}" spellcheck="false">
      <datalist id="p-models-${preset.id}"></datalist>
    </label>
    <button type="button" class="p-test">测试连接</button>
    <p class="hint p-model-hint">保存后，给村民或默认模型选这个服务时，会自动填上这里的模型名。</p>
    <div class="form-status p-test-status"></div>`
}
