class_name OllamaCloudModelProvider
extends "res://agent/model/GenericOpenAICompatibleModelProvider.gd"


const DEFAULT_CLOUD_BASE_URL := "https://ollama.com/api"


func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	var resolved_config := config.duplicate(true)
	var configured_endpoint := String(
		resolved_config.get("endpoint", DEFAULT_CLOUD_BASE_URL)
	).strip_edges()
	if configured_endpoint.is_empty():
		configured_endpoint = DEFAULT_CLOUD_BASE_URL
	super(request_host, transport, resolved_config)
	# GenericOpenAICompatibleModelProvider 会补 OpenAI 的 /chat/completions；
	# Ollama Cloud 官方直连接口使用原生 /api/chat，因此在初始化后改回原生端点。
	_config["endpoint"] = _native_chat_endpoint(configured_endpoint)


func get_provider_descriptor() -> Dictionary:
	var descriptor := super.get_provider_descriptor()
	descriptor["native_ollama_api"] = true
	return descriptor


func model_catalog_endpoint() -> String:
	return _native_api_root(String(_config.get("endpoint", DEFAULT_CLOUD_BASE_URL))).path_join(
		"tags"
	)


func _build_request_body(model_request: Dictionary) -> Dictionary:
	var max_tokens := int(model_request.get(
		"max_tokens",
		_config.get("max_tokens", DEFAULT_MAX_TOKENS),
	))
	var body := {
		"model": _api_model(),
		"messages": model_request.get("messages", []),
		"stream": false,
		"options": {"num_predict": max_tokens},
	}
	# 原生 Ollama API 使用 think 控制推理。GPT-OSS 不接受 false，最低为 low；
	# 其他支持关闭思考的模型则直接关闭，保证最终内容有足够输出预算。
	body["think"] = "low" if _api_model().to_lower().begins_with("gpt-oss:") else false
	return body


func _model_catalog_result(response: Dictionary) -> Dictionary:
	var result_code := int(response.get("result", HTTPRequest.RESULT_SUCCESS))
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return _catalog_failure("PROVIDER_CONNECTION_FAILED", true)
	var status_code := int(response.get("status_code", 0))
	if status_code in [401, 403]:
		return _catalog_failure("PROVIDER_AUTH_FAILED", false)
	if status_code < 200 or status_code >= 300:
		return _catalog_failure(
			"PROVIDER_MODEL_CATALOG_REQUEST_FAILED",
			status_code >= 500,
		)
	var body_value: Variant = response.get("body", PackedByteArray())
	var body_text := (
		(body_value as PackedByteArray).get_string_from_utf8()
		if body_value is PackedByteArray
		else String(body_value)
	)
	var parsed: Variant = JSON.parse_string(body_text)
	if not parsed is Dictionary:
		return _catalog_failure("PROVIDER_MODEL_CATALOG_INVALID", false)
	var entries: Variant = (parsed as Dictionary).get("models", [])
	if not entries is Array:
		return _catalog_failure("PROVIDER_MODEL_CATALOG_INVALID", false)
	var models: Array[String] = []
	for value: Variant in entries as Array:
		if not value is Dictionary:
			continue
		var entry := value as Dictionary
		var model_id := String(entry.get("model", entry.get("name", ""))).strip_edges()
		if not model_id.is_empty() and model_id not in models:
			models.append(model_id)
	if models.is_empty():
		return _catalog_failure("PROVIDER_MODEL_CATALOG_EMPTY", false)
	return {
		"ok": true,
		"accepted": true,
		"status": "ready",
		"models": models,
		"errorCode": "",
		"retryable": false,
	}


func _handle_transport_result(
	response: Dictionary,
	on_complete: Callable,
	started_at: int,
	recorded_request: Dictionary,
) -> void:
	var normalized_response := response.duplicate(true)
	var result_code := int(response.get("result", HTTPRequest.RESULT_REQUEST_FAILED))
	var status_code := int(response.get("status_code", 0))
	if result_code == HTTPRequest.RESULT_SUCCESS and status_code >= 200 and status_code < 300:
		var body_value: Variant = response.get("body", PackedByteArray())
		var body_text := (
			(body_value as PackedByteArray).get_string_from_utf8()
			if body_value is PackedByteArray
			else String(body_value)
		)
		var parsed: Variant = JSON.parse_string(body_text)
		if parsed is Dictionary and (parsed as Dictionary).get("message") is Dictionary:
			var native := parsed as Dictionary
			var openai_response := {
				"choices": [{
					"message": native.get("message", {}),
					"finish_reason": String(native.get("done_reason", "stop")),
				}],
				"usage": {
					"prompt_tokens": int(native.get("prompt_eval_count", 0)),
					"completion_tokens": int(native.get("eval_count", 0)),
				},
			}
			normalized_response["body"] = JSON.stringify(openai_response).to_utf8_buffer()
	super._handle_transport_result(
		normalized_response,
		on_complete,
		started_at,
		recorded_request,
	)


func _native_chat_endpoint(value: String) -> String:
	return _native_api_root(value).path_join("chat")


func _native_api_root(value: String) -> String:
	var endpoint := value.strip_edges().trim_suffix("/")
	for suffix: String in ["/chat/completions", "/chat", "/tags", "/models"]:
		if endpoint.ends_with(suffix):
			endpoint = endpoint.trim_suffix(suffix)
	if not endpoint.ends_with("/api"):
		endpoint = endpoint.path_join("api")
	return endpoint
