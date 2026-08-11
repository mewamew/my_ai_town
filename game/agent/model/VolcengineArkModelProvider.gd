class_name VolcengineArkModelProvider
extends "res://agent/model/OpenAICompatibleModelProvider.gd"


const GenericCompatibleProviderScript := preload(
	"res://agent/model/GenericOpenAICompatibleModelProvider.gd"
)
const DEFAULT_ENDPOINT := "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
const DEFAULT_MODEL := ""
const MODEL_DESCRIPTORS := []
const TOWN_MODEL_LABELS := {
	"doubao-seed-2-1-pro": "豆包 Seed 2.1 Pro",
	"doubao-seed-2-1-turbo": "豆包 Seed 2.1 Turbo",
	"doubao-seed-2-0-pro": "豆包 Seed 2.0 Pro",
	"doubao-seed-2-0-lite": "豆包 Seed 2.0 Lite",
	"doubao-seed-2-0-mini": "豆包 Seed 2.0 Mini",
	"doubao-seed-character": "豆包 Seed Character",
	"deepseek-v4-pro": "DeepSeek V4 Pro",
	"deepseek-v4-flash-ga": "DeepSeek V4 Flash",
	"glm-5-2": "GLM 5.2",
}
const TOWN_MULTIMODAL_MODEL_FAMILIES := [
	"doubao-seed-2-1-pro",
	"doubao-seed-2-1-turbo",
	"doubao-seed-character",
]

var _model_catalog_delegate: GenericOpenAICompatibleModelProvider


func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	super(request_host, transport, config)
	var catalog_config := config.duplicate(true)
	catalog_config["preset_provider_id"] = "volcengine-ark"
	catalog_config["preset_provider_label"] = "火山方舟"
	catalog_config["preset_default_endpoint"] = DEFAULT_ENDPOINT
	_model_catalog_delegate = GenericCompatibleProviderScript.new(
		request_host,
		transport,
		catalog_config,
	)


func _provider_id() -> String:
	return "volcengine-ark"


func _provider_label() -> String:
	return "火山方舟"


func _transport_label() -> String:
	return "方舟 OpenAI-compatible API"


func _default_endpoint() -> String:
	return DEFAULT_ENDPOINT


func _default_model() -> String:
	return DEFAULT_MODEL


func _provider_request_options() -> Dictionary:
	var model_id := String(_config.get("model", _default_model())).to_lower()
	if model_id.begins_with("doubao-"):
		return {"thinking": {"type": "disabled"}}
	return {}


func get_provider_descriptor() -> Dictionary:
	var descriptor := super.get_provider_descriptor()
	descriptor["custom_models"] = true
	descriptor["custom_group"] = false
	descriptor["model_catalog_supported"] = true
	descriptor["catalog_model_labels"] = TOWN_MODEL_LABELS.duplicate(true)
	descriptor["catalog_multimodal_families"] = (
		TOWN_MULTIMODAL_MODEL_FAMILIES.duplicate()
	)
	return descriptor


func model_catalog_endpoint() -> String:
	return _model_catalog_delegate.model_catalog_endpoint()


func request_model_catalog(on_complete: Callable) -> Dictionary:
	return _model_catalog_delegate.request_model_catalog(
		Callable(self, "_on_unfiltered_model_catalog").bind(on_complete),
	)


func _model_catalog_result(response: Dictionary) -> Dictionary:
	var result := _model_catalog_delegate._model_catalog_result(response)
	return _filter_town_model_catalog(result)


func _on_unfiltered_model_catalog(
	result_value: Variant,
	on_complete: Callable,
) -> void:
	var result: Dictionary
	if result_value is Dictionary:
		result = result_value as Dictionary
	else:
		result = _catalog_failure_result(
			"PROVIDER_MODEL_CATALOG_INVALID",
			false,
		)
	on_complete.call(_filter_town_model_catalog(result))


func _filter_town_model_catalog(result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		return result
	var models_value: Variant = result.get("models", [])
	if not models_value is Array:
		return _catalog_failure_result("PROVIDER_MODEL_CATALOG_INVALID", false)
	var latest_by_family := {}
	for value: Variant in models_value as Array:
		if typeof(value) != TYPE_STRING:
			continue
		var model_id := (value as String).strip_edges()
		if not _is_town_model(model_id):
			continue
		var family := _model_release_family(model_id)
		latest_by_family[family] = model_id
	var filtered: Array[String] = []
	for family_value: Variant in TOWN_MODEL_LABELS.keys():
		var family := String(family_value)
		if latest_by_family.has(family):
			filtered.append(String(latest_by_family.get(family, "")))
	if filtered.is_empty():
		return _catalog_failure_result("PROVIDER_MODEL_CATALOG_EMPTY", false)
	var filtered_result := result.duplicate(true)
	filtered_result["models"] = filtered
	return filtered_result


func _is_town_model(model_id: String) -> bool:
	if model_id.is_empty():
		return false
	return TOWN_MODEL_LABELS.has(_model_release_family(model_id.to_lower()))


func _model_release_family(model_id: String) -> String:
	var separator := model_id.rfind("-")
	if separator < 0:
		return model_id
	var suffix := model_id.substr(separator + 1)
	if suffix.is_valid_int() and suffix.length() in [6, 8]:
		return model_id.substr(0, separator)
	return model_id


func _catalog_failure_result(error_code: String, retryable: bool) -> Dictionary:
	return _model_catalog_delegate._catalog_failure(error_code, retryable)


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	var model_id := String(_config.get("model", DEFAULT_MODEL)).strip_edges()
	if model_id.is_empty():
		errors.append("缺少火山方舟模型或推理接入点 ID")
	return errors


func _api_key_environment_names() -> Array[String]:
	return ["ARK_API_KEY"]


func _billing_error_identifiers() -> Array[String]:
	return [
		"AccountOverdueError",
		"OperationDenied.ServiceOverdue",
		"ServiceOverdue",
	]


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少 ARK_API_KEY"
	if include_hint:
		message += "；可写入项目 .tmp/.env"
	return message
