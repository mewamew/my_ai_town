class_name OllamaCloudModelProvider
extends "res://agent/model/OpenAICompatibleModelProvider.gd"


const DEFAULT_ENDPOINT := "http://localhost:11434/v1/chat/completions"
const GPT_OSS__20B_CLOUD_MODEL := "gpt-oss:20b-cloud"
const GPT_OSS__120B_CLOUD_MODEL := "gpt-oss:120b-cloud"
const GEMMA_V4__CLOUD_MODEL := "gemma4:cloud"
const GEMMA_V4__31B_CLOUD_MODEL := "gemma4:31b-cloud"
const DEFAULT_MODEL := GPT_OSS__20B_CLOUD_MODEL
const MODEL_DESCRIPTORS := [
	{"id": GPT_OSS__20B_CLOUD_MODEL, "label": "GPT-OSS - 20b (Ollama-Cloud)", "input_modalities": ["text"]},
	{"id": GPT_OSS__120B_CLOUD_MODEL, "label": "GPT-OSS - 120b (Ollama-Cloud)", "input_modalities": ["text"]},
	{"id": GEMMA_V4__CLOUD_MODEL, "label": "Gemma 4 - (Ollama-Cloud)", "input_modalities": ["text"]},
	{"id": GEMMA_V4__31B_CLOUD_MODEL, "label": "Gemma 4 - 31b (Ollama-Cloud)", "input_modalities": ["text"]},
]

func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	super(request_host, transport, config)


func _provider_id() -> String:
	return "ollama-cloud"


func _provider_label() -> String:
	return "Ollama-Cloud"


func _transport_label() -> String:
	return "Ollama-Cloud API"


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
	var support_models := [GPT_OSS__20B_CLOUD_MODEL, GPT_OSS__120B_CLOUD_MODEL, GEMMA_V4__CLOUD_MODEL, GEMMA_V4__31B_CLOUD_MODEL]
	if model_id not in support_models:
		errors.append("Ollama-Cloud Provider 不支持模型：%s" % model_id)
	return errors


func _api_key_environment_names() -> Array[String]:
	return ["OLLAMA_CLOUD_API_KEY"]


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少 OLLAMA_CLOUD_API_KEY"
	if include_hint:
		message += "；可写入项目 .tmp/.env"
	return message
