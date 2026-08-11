class_name ThreeZeroTwoAIModelProvider
extends "res://agent/model/GenericOpenAICompatibleModelProvider.gd"


# 302.AI 的模型目录同时包含图片、视频、嵌入、代码专用、Responses 专用和
# 大量历史版本。小镇只展示已经接入 chat/completions、适合居民持续对话的
# 主流通用模型；列表仍以玩家密钥实际返回的模型为准，不凭空添加。
const TOWN_MODEL_LABELS := {
	"gpt-5.5": "GPT-5.5",
	"claude-sonnet-5": "Claude Sonnet 5",
	"claude-opus-5": "Claude Opus 5",
	"gemini-3.6-flash": "Gemini 3.6 Flash",
	"deepseek-v4-pro": "DeepSeek V4 Pro",
	"deepseek-v4-flash": "DeepSeek V4 Flash",
	"qwen3.8-max": "Qwen 3.8 Max",
	"glm-5.2": "GLM 5.2",
	"kimi-k3": "Kimi K3",
	"minimax-m3": "MiniMax M3",
	"grok-4.5": "Grok 4.5",
	"step-3.7-flash": "Step 3.7 Flash",
	"doubao-seed-2-1-pro": "豆包 Seed 2.1 Pro",
	"doubao-seed-2-1-turbo": "豆包 Seed 2.1 Turbo",
}
const TOWN_MODEL_ORDER := [
	"gpt-5.5",
	"claude-sonnet-5",
	"claude-opus-5",
	"gemini-3.6-flash",
	"deepseek-v4-pro",
	"deepseek-v4-flash",
	"qwen3.8-max",
	"glm-5.2",
	"kimi-k3",
	"minimax-m3",
	"grok-4.5",
	"step-3.7-flash",
	"doubao-seed-2-1-pro",
	"doubao-seed-2-1-turbo",
]


func get_provider_descriptor() -> Dictionary:
	var descriptor := super.get_provider_descriptor()
	descriptor["catalog_model_labels"] = TOWN_MODEL_LABELS.duplicate(true)
	return descriptor


func _model_catalog_result(response: Dictionary) -> Dictionary:
	return _filter_town_model_catalog(super._model_catalog_result(response))


func _filter_town_model_catalog(result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		return result
	var values: Variant = result.get("models", [])
	if not values is Array:
		return _catalog_failure("PROVIDER_MODEL_CATALOG_INVALID", false)
	var filtered := filter_town_models(values as Array)
	if filtered.is_empty():
		return _catalog_failure("PROVIDER_MODEL_CATALOG_EMPTY", false)
	var filtered_result := result.duplicate(true)
	filtered_result["models"] = filtered
	return filtered_result


static func filter_town_models(values: Array) -> Array[String]:
	var latest_by_family := {}
	for value: Variant in values as Array:
		if typeof(value) != TYPE_STRING:
			continue
		var model_id := (value as String).strip_edges()
		var family := _model_release_family(model_id.to_lower())
		if TOWN_MODEL_LABELS.has(family):
			var current := String(latest_by_family.get(family, ""))
			if current.is_empty() or current.naturalnocasecmp_to(model_id) < 0:
				latest_by_family[family] = model_id
	var filtered: Array[String] = []
	for family: String in TOWN_MODEL_ORDER:
		if latest_by_family.has(family):
			filtered.append(String(latest_by_family.get(family, "")))
	return filtered


static func _model_release_family(model_id: String) -> String:
	var separator := model_id.rfind("-")
	if separator < 0:
		return model_id
	var suffix := model_id.substr(separator + 1)
	if suffix.is_valid_int() and suffix.length() in [6, 8]:
		return model_id.substr(0, separator)
	return model_id
