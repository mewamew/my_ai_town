class_name OllamaModelProvider
extends "res://agent/model/OpenAICompatibleModelProvider.gd"


const DEFAULT_ENDPOINT := "http://localhost:11434/v1/chat/completions"
const QWEN_V3_5__0_8B_MODEL := "qwen3.5:0.8b"
const QWEN_V3_5__2B_MODEL := "qwen3.5:2b"
const QWEN_V3_5__4B_MODEL := "qwen3.5:4b"
const QWEN_V3_5__9B_MODEL := "qwen3.5:9b"
const DEFAULT_MODEL := QWEN_V3_5__2B_MODEL
const MODEL_DESCRIPTORS := [
	{"id": QWEN_V3_5__0_8B_MODEL, "label": "Qwen 2.5 - 0.8b (Ollama)", "input_modalities": ["text"]},
	{"id": QWEN_V3_5__2B_MODEL, "label": "Qwen 2.5 - 2b (Ollama)", "input_modalities": ["text"]},
	{"id": QWEN_V3_5__4B_MODEL, "label": "Qwen 2.5 - 4b (Ollama)", "input_modalities": ["text"]},
	{"id": QWEN_V3_5__9B_MODEL, "label": "Qwen 2.5 - 9b (Ollama)", "input_modalities": ["text"]},
]

func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	super(request_host, transport, config)


func _provider_id() -> String:
	return "ollama"


func _provider_label() -> String:
	return "Ollama"


func _transport_label() -> String:
	return "Ollama API"


func _default_endpoint() -> String:
	return DEFAULT_ENDPOINT


func _default_model() -> String:
	return DEFAULT_MODEL


func _provider_request_options() -> Dictionary:
	return {
		"thinking": {"type": "disabled"},
		"response_format": {"type": "json_object"},
	}


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	var model_id := String(_config.get("model", DEFAULT_MODEL))
	var support_models := [QWEN_V3_5__0_8B_MODEL, QWEN_V3_5__2B_MODEL, QWEN_V3_5__4B_MODEL, QWEN_V3_5__9B_MODEL]
	if model_id not in support_models:
		errors.append("Ollama Provider 不支持模型：%s" % model_id)
	return errors


func _api_key_environment_names() -> Array[String]:
	return ["OLLAMA_API_KEY"]


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少 OLLAMA_API_KEY"
	if include_hint:
		message += "；可写入项目 .tmp/.env"
	return message
