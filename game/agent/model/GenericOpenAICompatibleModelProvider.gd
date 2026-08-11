class_name GenericOpenAICompatibleModelProvider
extends "res://agent/model/OpenAICompatibleModelProvider.gd"


const DEFAULT_MODEL := "custom"
const MODEL_DESCRIPTORS := [
	{
		"id": DEFAULT_MODEL,
		"label": "自定义模型",
		"input_modalities": ["text"],
		"runtime_modalities_configurable": true,
	},
]


func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	var resolved_config := config.duplicate(true)
	var endpoint := String(resolved_config.get(
		"endpoint",
		resolved_config.get(
			"preset_default_endpoint",
			OS.get_environment("OPENAI_COMPATIBLE_ENDPOINT"),
		),
	)).strip_edges()
	if not endpoint.is_empty():
		resolved_config["endpoint"] = _normalize_request_endpoint(endpoint)
	super(request_host, transport, resolved_config)


func _provider_id() -> String:
	return String(_config.get("preset_provider_id", "openai-compatible"))


func _provider_label() -> String:
	return String(_config.get("preset_provider_label", "自定义模型"))


func _transport_label() -> String:
	return String(_config.get(
		"preset_transport_label",
		"自定义兼容接口",
	))


func _default_endpoint() -> String:
	var configured_default := String(
		_config.get("preset_default_endpoint", "")
	).strip_edges()
	if not configured_default.is_empty():
		return configured_default
	return OS.get_environment("OPENAI_COMPATIBLE_ENDPOINT").strip_edges()


func _default_model() -> String:
	return DEFAULT_MODEL


func get_provider_descriptor() -> Dictionary:
	var descriptor := super.get_provider_descriptor()
	descriptor["model_id"] = _api_model() if not _api_model().is_empty() else DEFAULT_MODEL
	descriptor["auth_required"] = _api_key_required()
	descriptor["default_endpoint"] = _default_endpoint()
	descriptor["custom_models"] = true
	descriptor["custom_group"] = true
	descriptor["model_catalog_supported"] = true
	return descriptor


func _request_endpoint() -> String:
	return _normalize_request_endpoint(String(
		_config.get("endpoint", _default_endpoint())
	).strip_edges())


func _normalize_request_endpoint(value: String) -> String:
	var endpoint := value.trim_suffix("/")
	if endpoint.is_empty():
		return ""
	if endpoint.ends_with("/chat/completions"):
		return endpoint
	var scheme_separator := endpoint.find("://")
	var path_start := endpoint.find("/", scheme_separator + 3)
	if path_start < 0:
		return "%s/v1/chat/completions" % endpoint
	return "%s/chat/completions" % endpoint


func model_catalog_endpoint() -> String:
	var configured := String(
		_config.get("endpoint", _default_endpoint())
	).strip_edges().trim_suffix("/")
	if configured.is_empty():
		return ""
	var endpoint := configured
	if not endpoint.ends_with("/models"):
		endpoint = _normalize_request_endpoint(configured).trim_suffix(
			"/chat/completions"
		).path_join("models")
	if _provider_id() == "302-ai":
		return "%s?llm=1&include_custom_models=1" % endpoint
	return endpoint


func request_model_catalog(on_complete: Callable) -> Dictionary:
	if not on_complete.is_valid():
		return _catalog_failure("PROVIDER_CALLBACK_INVALID", false)
	var endpoint := model_catalog_endpoint()
	if endpoint.is_empty():
		return _catalog_failure("PROVIDER_BASE_URL_INVALID", false)
	var api_key := _resolve_api_key()
	if _api_key_required() and api_key.is_empty():
		return _catalog_failure("PROVIDER_API_KEY_REQUIRED", false)
	var headers := PackedStringArray([
		"Accept: application/json",
	])
	if not api_key.is_empty():
		headers.append("Authorization: Bearer %s" % api_key)
	if _transport != null and _transport.has_method("request_model_catalog"):
		var transport_error: int = _transport.call(
			"request_model_catalog",
			endpoint,
			headers,
			func(response: Dictionary) -> void:
				on_complete.call(_model_catalog_result(response))
		)
		if transport_error != OK:
			return _catalog_failure("PROVIDER_MODEL_CATALOG_REQUEST_FAILED", true)
		return _catalog_started()
	if _request_host == null or not is_instance_valid(_request_host):
		return _catalog_failure("PROVIDER_REQUEST_HOST_REQUIRED", false)
	var http_request := HTTPRequest.new()
	http_request.timeout = float(_config.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS))
	var system_ca_pem := OS.get_system_ca_certificates()
	if not system_ca_pem.is_empty():
		var system_ca := X509Certificate.new()
		if system_ca.load_from_string(system_ca_pem) == OK:
			http_request.set_tls_options(TLSOptions.client(system_ca))
	_request_host.add_child(http_request)
	http_request.request_completed.connect(
		_on_model_catalog_request_completed.bind(
			http_request,
			on_complete,
		),
		CONNECT_ONE_SHOT,
	)
	var error := http_request.request(
		endpoint,
		headers,
		HTTPClient.METHOD_GET,
	)
	if error != OK:
		http_request.queue_free()
		return _catalog_failure("PROVIDER_MODEL_CATALOG_REQUEST_FAILED", true)
	return _catalog_started()


func _on_model_catalog_request_completed(
	result: int,
	response_code: int,
	response_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest,
	on_complete: Callable,
) -> void:
	http_request.queue_free()
	on_complete.call(_model_catalog_result({
		"result": result,
		"status_code": response_code,
		"headers": response_headers,
		"body": body,
	}))


func _model_catalog_result(response: Dictionary) -> Dictionary:
	var result_code := int(response.get("result", HTTPRequest.RESULT_SUCCESS))
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return _catalog_failure("PROVIDER_CONNECTION_FAILED", true)
	var status_code := int(response.get("status_code", 0))
	if status_code in [401, 403]:
		return _catalog_failure("PROVIDER_AUTH_FAILED", false)
	if status_code < 200 or status_code >= 300:
		return _catalog_failure("PROVIDER_MODEL_CATALOG_REQUEST_FAILED", status_code >= 500)
	var body_value: Variant = response.get("body", PackedByteArray())
	var body_text := (
		(body_value as PackedByteArray).get_string_from_utf8()
		if body_value is PackedByteArray
		else String(body_value)
	)
	var parsed: Variant = JSON.parse_string(body_text)
	if not parsed is Dictionary:
		return _catalog_failure("PROVIDER_MODEL_CATALOG_INVALID", false)
	var entries_value: Variant = (parsed as Dictionary).get(
		"data",
		(parsed as Dictionary).get("models", []),
	)
	if not entries_value is Array:
		return _catalog_failure("PROVIDER_MODEL_CATALOG_INVALID", false)
	var models: Array[String] = []
	for value: Variant in entries_value as Array:
		var model_id := ""
		if typeof(value) == TYPE_STRING:
			model_id = (value as String).strip_edges()
		elif value is Dictionary:
			model_id = String((value as Dictionary).get("id", "")).strip_edges()
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


func _catalog_started() -> Dictionary:
	return {
		"ok": true,
		"accepted": true,
		"status": "checking",
		"errorCode": "",
		"retryable": false,
	}


func _catalog_failure(error_code: String, retryable: bool) -> Dictionary:
	return {
		"ok": false,
		"accepted": false,
		"status": "unavailable",
		"errorCode": error_code,
		"retryable": retryable,
	}


func _build_request_body(model_request: Dictionary) -> Dictionary:
	var body := super._build_request_body(model_request)
	body["model"] = _api_model()
	body.erase("max_tokens")
	# Ollama 与 LM Studio 的 OpenAI-compatible 端点支持 reasoning_effort=none。
	# 居民决策需要把输出预算留给最终 JSON，避免思考模型只返回推理过程。
	if _provider_id() in ["ollama", "lm-studio"]:
		body["reasoning_effort"] = "none"
	return body


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	if String(_config.get("endpoint", _default_endpoint())).strip_edges().is_empty():
		errors.append("缺少 OpenAI-compatible endpoint")
	if _api_model().is_empty():
		errors.append("缺少 OpenAI-compatible api_model")
	return errors


func _api_model() -> String:
	return String(
		_config.get("api_model", OS.get_environment("OPENAI_COMPATIBLE_MODEL"))
	).strip_edges()


func _api_key_environment_names() -> Array[String]:
	var configured_name := String(_config.get("preset_api_key_environment", ""))
	if not configured_name.is_empty():
		return [configured_name]
	return ["OPENAI_COMPATIBLE_API_KEY"]


func _api_key_required() -> bool:
	return bool(_config.get("preset_api_key_required", true))


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少 OPENAI_COMPATIBLE_API_KEY"
	if include_hint:
		message += "；可写入项目 .tmp/.env"
	return message
