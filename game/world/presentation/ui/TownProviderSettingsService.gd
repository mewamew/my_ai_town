class_name TownProviderSettingsService
extends RefCounted


signal view_model_changed(scope: String, view_model: Dictionary)
signal operation_completed(scope: String, operation: Dictionary)

const SCOPE := "provider_settings"
const CONFIG_STORE := preload(
	"res://world/presentation/ui/TownProviderConfigStore.gd"
)
const CREDENTIAL_STORE := preload(
	"res://world/presentation/ui/TownProviderCredentialStore.gd"
)
const ENDPOINT_SECURITY := preload(
	"res://common/ProviderEndpointSecurity.gd"
)
const THREE_ZERO_TWO_PROVIDER := preload(
	"res://agent/model/ThreeZeroTwoAIModelProvider.gd"
)
const REQUIRED_PROVIDER_METHODS: Array[String] = [
	"configure",
	"get_health_snapshot",
	"list_available_models",
	"request_health_check",
	"request_model_catalog",
]
const HOST_ROUTING_REQUIRED := "PROVIDER_SETTINGS_HOST_ROUTING_REQUIRED"
const TEST_NO_NETWORK_ENV := "AI_TOWN_PROVIDER_TEST_NO_NETWORK"
const COMPATIBLE_PROFILE_TYPE := "openai-compatible-profile"
const COMPATIBLE_PROFILE_PREFIX := "openai-compatible-"
const PROVIDER_DISPLAY_NAMES := {
	"302-ai": "302.AI",
	"deepseek": "DeepSeek",
	"minimax": "MiniMax",
	"kimi": "Kimi",
	"lm-studio": "LM Studio（本地）",
	"ollama": "Ollama（本地）",
	"ollama-cloud": "Ollama Cloud",
	"openai-compatible": "其他兼容接口",
	"zhipu-glm": "智谱",
}
const MODEL_CAPABILITIES := {
	"deepseek-v4-flash": [
		"decision_json",
		"dialogue",
		"memory_summary",
	],
	"deepseek-v4-pro": [
		"decision_json",
		"dialogue",
		"memory_summary",
	],
	"glm-5.2": [
		"decision_json",
		"dialogue",
		"memory_summary",
	],
	"kimi-k2.6": [
		"decision_json",
		"dialogue",
		"memory_summary",
	],
	"kimi-k3": [
		"decision_json",
		"dialogue",
		"memory_summary",
	],
}

var _provider_service: Object
var _request_host: Node
var _store: TownProviderConfigStore = CONFIG_STORE.new()
var _credential_store: TownProviderCredentialStore = CREDENTIAL_STORE.new()
var _credential_keys: Dictionary = {}
var _stored_config: Dictionary = {
	"schemaVersion": 2,
	"selectedProviderId": "",
	"selectedModelByProvider": {},
	"providers": {},
}
var _view_model: Dictionary = {}
var _confirmed_data: Dictionary = {}
var _selected_provider_id := ""
var _revision := 0
var _request_sequence := 0
var _active_health_request_id := ""
var _active_model_catalog_request_id := ""
var _discovered_models_by_provider: Dictionary = {}
var _health_configuration_generation := 0
var _dirty_health_providers: Dictionary = {}


func configure_store(path: String) -> Dictionary:
	_discovered_models_by_provider.clear()
	var configured := _store.configure(path)
	if not bool(configured.get("ok", false)):
		return configured
	var credential_path := "%s.credentials.enc" % path.get_basename()
	var credential_configured := (
		_credential_store.configure(credential_path) as Dictionary
	)
	if not bool(credential_configured.get("ok", false)):
		return credential_configured
	return _load_stored_config()


func bind_provider_service(
	provider_service: Object,
	request_host: Node = null,
) -> Dictionary:
	if provider_service == null:
		_provider_service = null
		_confirmed_data.clear()
		_publish_disabled("PROVIDER_SETTINGS_SERVICE_NOT_BOUND")
		return _failure("PROVIDER_SETTINGS_SERVICE_NOT_BOUND", false)
	var missing_methods: Array[String] = []
	for method in REQUIRED_PROVIDER_METHODS:
		if not provider_service.has_method(method):
			missing_methods.append(method)
	if not missing_methods.is_empty():
		_provider_service = null
		_confirmed_data.clear()
		_publish_disabled("PROVIDER_SETTINGS_SERVICE_CONTRACT_INVALID")
		return _failure(
			"PROVIDER_SETTINGS_SERVICE_CONTRACT_INVALID",
			false,
			"Provider service 缺少公共方法：%s" % ", ".join(missing_methods),
		)
	_provider_service = provider_service
	_request_host = request_host
	var loaded := _load_stored_config()
	if not bool(loaded.get("ok", false)):
		_publish_result(_idle_operation(), loaded, "error")
		return loaded
	var configured := _apply_provider_configuration()
	if not bool(configured.get("ok", false)):
		_publish_result(_idle_operation(), configured, "error")
		return configured
	var refreshed := refresh()
	if not bool(refreshed.get("ok", false)):
		return refreshed
	var startup_check := _start_configured_health_check()
	if String(startup_check.get("status", "")) == "checking":
		return startup_check
	return refreshed


func runtime_configuration() -> Dictionary:
	var provider_id := String(_stored_config.get("selectedProviderId", "")).strip_edges()
	var selected_models := _stored_config.get("selectedModelByProvider", {}) as Dictionary
	var model_id := String(selected_models.get(provider_id, "")).strip_edges()
	var providers := _stored_config.get("providers", {}) as Dictionary
	var provider_config := providers.get(provider_id, {}) as Dictionary
	var provider_ready := false
	var provider_error_code := ""
	var provider_retryable := false
	var provider_auth_required := true
	for value: Variant in ((_view_model.get("data", {}) as Dictionary).get("providers", []) as Array):
		if not value is Dictionary:
			continue
		var provider := value as Dictionary
		if String(provider.get("providerId", "")) != provider_id:
			continue
		var connection := provider.get("connection", {}) as Dictionary
		provider_ready = (
			bool(provider.get("enabled", false))
			and String(connection.get("status", "")) == "available"
		)
		provider_error_code = String(connection.get("errorCode", ""))
		provider_retryable = bool(connection.get("retryable", false))
		provider_auth_required = bool(provider.get("authRequired", true))
		break
	var ready := provider_ready and not provider_id.is_empty() and not model_id.is_empty()
	var has_saved_key := _has_saved_key(provider_id)
	var error_code := ""
	if not ready:
		error_code = (
			"PROVIDER_SETTINGS_PROVIDER_REQUIRED"
			if provider_id.is_empty()
			else "PROVIDER_MODEL_SELECTION_REQUIRED"
			if model_id.is_empty()
			else "PROVIDER_DISABLED"
			if not bool(provider_config.get("enabled", true))
			else "PROVIDER_API_KEY_REQUIRED"
			if provider_auth_required and not has_saved_key
			else provider_error_code
			if not provider_error_code.is_empty()
			else "PROVIDER_HEALTH_UNAVAILABLE"
		)
	return {
		"ok": ready,
		"errorCode": error_code,
		"retryable": provider_retryable if not ready else false,
		"providerId": provider_id,
		"modelId": model_id,
		"providerConfigs": _provider_configs_for_runtime(),
		"hasSavedKey": has_saved_key,
		"authRequired": provider_auth_required,
	}


func load_saved_runtime_configuration() -> Dictionary:
	var loaded := _load_stored_config()
	if not bool(loaded.get("ok", false)):
		return loaded
	var selected_provider_id := String(
		_stored_config.get("selectedProviderId", ""),
	).strip_edges()
	var selected_models := (
		_stored_config.get("selectedModelByProvider", {}) as Dictionary
	)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"providerId": selected_provider_id,
		"modelId": String(selected_models.get(selected_provider_id, "")).strip_edges(),
		"providerConfigs": _provider_configs_for_runtime(),
	}


func refresh() -> Dictionary:
	if _provider_service == null:
		_publish_disabled("PROVIDER_SETTINGS_SERVICE_NOT_BOUND")
		return _failure("PROVIDER_SETTINGS_SERVICE_NOT_BOUND", false)
	var loaded := _load_public_snapshot()
	if not bool(loaded.get("ok", false)):
		_publish_result(
			_idle_operation(),
			loaded,
			"error",
		)
		return loaded
	_confirmed_data = (loaded.get("data", {}) as Dictionary).duplicate(true)
	_revision += 1
	_view_model = _base_view_model(
		"ready",
		_confirmed_data,
		_idle_operation(),
		{},
	)
	view_model_changed.emit(SCOPE, _view_model.duplicate(true))
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"revision": _revision,
	}


func get_view_model(scope: String = SCOPE) -> Dictionary:
	if scope != SCOPE:
		return {
			"scope": scope,
			"status": "error",
			"revision": 0,
			"data": {},
			"actions": {},
			"operation": _idle_operation(),
			"error": _error_payload(
				"UNKNOWN_UI_SCOPE",
				false,
				"Provider settings service 只提供 provider_settings scope。",
			),
		}
	if _view_model.is_empty():
		_publish_disabled("PROVIDER_SETTINGS_SERVICE_NOT_BOUND")
	return _view_model.duplicate(true)


func reveal_saved_api_key(provider_id_value: Variant) -> Dictionary:
	if (
		typeof(provider_id_value) != TYPE_STRING
		or not _canonical_id_is_valid(provider_id_value as String)
	):
		return _failure("PROVIDER_SETTINGS_PROVIDER_REQUIRED", false)
	var provider_id := provider_id_value as String
	if _provider_from_confirmed(provider_id).is_empty():
		return _failure("PROVIDER_SETTINGS_PROVIDER_UNKNOWN", false)
	var revealed := (
		_credential_store.api_key(provider_id) as Dictionary
	)
	if not bool(revealed.get("ok", false)):
		return _failure(
			String(revealed.get("errorCode", "PROVIDER_CREDENTIAL_READ_FAILED")),
			false,
		)
	var api_key_value: Variant = revealed.get("apiKey")
	if typeof(api_key_value) != TYPE_STRING:
		return _failure("PROVIDER_CREDENTIAL_READ_FAILED", false)
	var api_key := api_key_value as String
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"saved": not api_key.is_empty(),
		"apiKey": api_key,
	}


func dispatch(intent: Variant, payload: Dictionary = {}) -> Dictionary:
	if typeof(intent) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _dispatch_rejection(
			"",
			"PROVIDER_SETTINGS_INTENT_NOT_AVAILABLE",
		)
	var intent_id := String(intent)
	var request_id := _next_request_id()
	var operation := _operation(request_id, intent_id, "loading")
	_publish_operation(operation, {})
	var result: Dictionary
	match intent_id:
		"provider_settings.select_provider":
			result = _select_provider(payload)
		"provider_settings.check_connection":
			result = _check_connection(payload, request_id)
		"provider_settings.save_key":
			result = _save_key(payload)
			if (
				bool(result.get("ok", false))
				and String(payload.get("providerId", "")) == "volcengine-ark"
			):
				_publish_operation(operation, {})
				result = _discover_models(payload, request_id)
		"provider_settings.delete_key":
			result = _delete_key(payload)
		"provider_settings.save_base_url":
			result = _save_base_url(payload)
		"provider_settings.save_connection":
			result = _save_connection(payload)
		"provider_settings.create_compatible_connection":
			result = _create_compatible_connection(payload)
		"provider_settings.rename_compatible_connection":
			result = _rename_compatible_connection(payload)
		"provider_settings.delete_compatible_connection":
			result = _delete_compatible_connection(payload)
		"provider_settings.save_api_model":
			result = _save_api_model(payload)
		"provider_settings.delete_api_model":
			result = _delete_api_model(payload)
		"provider_settings.discover_models":
			result = _discover_models(payload, request_id)
		"provider_settings.set_enabled":
			result = _set_enabled(payload)
		"provider_settings.select_model":
			result = _select_model(payload)
		"provider_settings.back":
			result = _failure(HOST_ROUTING_REQUIRED, false)
		_:
			result = _failure("PROVIDER_SETTINGS_INTENT_NOT_AVAILABLE", false)
	if String(result.get("status", "")) == "checking":
		return {
			"ok": true,
			"accepted": true,
			"pending": true,
			"requestId": request_id,
			"errorCode": "",
			"retryable": false,
		}
	var final_status := "success" if bool(result.get("ok", false)) else (
		"error" if bool(result.get("retryable", false)) else "rejected"
	)
	operation["status"] = final_status
	operation["completedAtMsec"] = Time.get_ticks_msec()
	operation["message"] = String(result.get("message", ""))
	_publish_result(operation, result, final_status)
	operation_completed.emit(SCOPE, operation.duplicate(true))
	return {
		"ok": bool(result.get("ok", false)),
		"accepted": true,
		"requestId": request_id,
		"errorCode": String(result.get("errorCode", "")),
		"retryable": bool(result.get("retryable", false)),
	}


func _load_public_snapshot() -> Dictionary:
	var health_value: Variant = _provider_service.call("get_health_snapshot")
	if not (health_value is Dictionary):
		return _failure("PROVIDER_HEALTH_SNAPSHOT_INVALID", false)
	var health := health_value as Dictionary
	if not bool(health.get("ok", false)):
		return _normalize_failure(health, "PROVIDER_HEALTH_QUERY_FAILED")
	var provider_values: Variant = health.get("providers")
	if not (provider_values is Array):
		return _failure("PROVIDER_HEALTH_SNAPSHOT_INVALID", false)
	var models_value: Variant = _provider_service.call("list_available_models")
	if not (models_value is Array):
		return _failure("PROVIDER_MODEL_CATALOG_INVALID", false)
	var models_by_provider: Dictionary = {}
	var known_models: Dictionary = {}
	for value in models_value as Array:
		if not (value is Dictionary):
			return _failure("PROVIDER_MODEL_CATALOG_INVALID", false)
		var model := value as Dictionary
		var provider_value: Variant = model.get(
			"providerId",
			model.get("provider_id"),
		)
		var model_value: Variant = model.get("modelId", model.get("id"))
		if (
			typeof(provider_value) != TYPE_STRING
			or typeof(model_value) != TYPE_STRING
		):
			return _failure("PROVIDER_MODEL_CATALOG_INVALID", false)
		var provider_id := provider_value as String
		var model_id := model_value as String
		if (
			not _canonical_id_is_valid(provider_id)
			or not _canonical_id_is_valid(model_id)
		):
			return _failure("PROVIDER_MODEL_CATALOG_INVALID", false)
		var model_key := "%s/%s" % [provider_id, model_id]
		if known_models.has(model_key):
			return _failure("PROVIDER_MODEL_CATALOG_INVALID", false)
		known_models[model_key] = true
		if not models_by_provider.has(provider_id):
			models_by_provider[provider_id] = []
		var capabilities: Array = []
		var capabilities_value: Variant = model.get("capabilities", [])
		if not capabilities_value is Array:
			return _failure("PROVIDER_MODEL_CATALOG_INVALID", false)
		for capability_value: Variant in capabilities_value as Array:
			if (
				typeof(capability_value) != TYPE_STRING
				or not _canonical_id_is_valid(capability_value as String)
			):
				return _failure("PROVIDER_MODEL_CATALOG_INVALID", false)
			capabilities.append(capability_value)
		if capabilities.is_empty() and MODEL_CAPABILITIES.has(model_id):
			capabilities = (
				MODEL_CAPABILITIES.get(model_id, []) as Array
			).duplicate()
		var selected_models := _stored_config.get("selectedModelByProvider", {}) as Dictionary
		var health_dirty := bool(
			_dirty_health_providers.get(provider_id, false)
		)
		(models_by_provider[provider_id] as Array).append({
			"modelId": model_id,
			"displayName": String(model.get("label", model_id)),
			"capabilities": capabilities,
			"available": bool(model.get("available", false)) and not health_dirty,
			"enabled": String(selected_models.get(provider_id, "")) == model_id,
			"errorCode": (
				"PROVIDER_HEALTH_CHECK_REQUIRED"
				if health_dirty
				else String(model.get("errorCode", ""))
			),
			"retryable": false if health_dirty else bool(model.get("retryable", false)),
			"healthStatus": (
				"unchecked"
				if health_dirty
				else String(model.get("healthStatus", "unavailable"))
			),
			"custom": bool(model.get("custom", false)),
		})
	var providers: Array[Dictionary] = []
	var available_count := 0
	var known_providers: Dictionary = {}
	for value in provider_values as Array:
		if not (value is Dictionary):
			return _failure("PROVIDER_HEALTH_SNAPSHOT_INVALID", false)
		var source := value as Dictionary
		var provider_value: Variant = source.get("providerId")
		if (
			typeof(provider_value) != TYPE_STRING
			or not _canonical_id_is_valid(provider_value as String)
		):
			return _failure("PROVIDER_HEALTH_SNAPSHOT_INVALID", false)
		var provider_id := provider_value as String
		if known_providers.has(provider_id):
			return _failure("PROVIDER_HEALTH_SNAPSHOT_INVALID", false)
		known_providers[provider_id] = true
		var stored_providers := _stored_config.get("providers", {}) as Dictionary
		var stored_provider := stored_providers.get(provider_id, {}) as Dictionary
		var enabled := bool(stored_provider.get("enabled", true))
		var has_saved_key := _has_saved_key(provider_id)
		var auth_required := bool(source.get("authRequired", true))
		var custom_models := bool(source.get("customModels", false))
		var custom_group := bool(source.get("customGroup", false))
		var model_catalog_supported := bool(
			source.get("modelCatalogSupported", false)
		)
		var api_models := _stored_api_models(stored_provider)
		var selected_models := _stored_config.get("selectedModelByProvider", {}) as Dictionary
		var selected_model_id := String(
			selected_models.get(provider_id, "")
		).strip_edges()
		var projected_source := source.duplicate(true)
		if not enabled:
			projected_source["status"] = "disabled"
			projected_source["errorCode"] = "PROVIDER_DISABLED"
			projected_source["retryable"] = false
		elif auth_required and not has_saved_key:
			projected_source["status"] = "not_configured"
			projected_source["errorCode"] = "PROVIDER_API_KEY_REQUIRED"
			projected_source["retryable"] = false
		elif selected_model_id.is_empty():
			projected_source["status"] = "not_configured"
			projected_source["errorCode"] = "PROVIDER_MODEL_SELECTION_REQUIRED"
			projected_source["retryable"] = false
		elif bool(_dirty_health_providers.get(provider_id, false)):
			projected_source["status"] = "unchecked"
			projected_source["errorCode"] = "PROVIDER_HEALTH_CHECK_REQUIRED"
			projected_source["retryable"] = false
		var status := String(projected_source.get("status", "unavailable"))
		if status == "available" and enabled:
			available_count += 1
		providers.append({
			"providerId": provider_id,
			"displayName": String(stored_provider.get(
				"displayName",
				PROVIDER_DISPLAY_NAMES.get(
					provider_id,
					source.get("label", provider_id),
				),
			)),
			"enabled": enabled,
			"external": bool(source.get("external", false)),
			"authRequired": auth_required,
			"customModels": custom_models,
			"customGroup": custom_group,
			"modelCatalogSupported": model_catalog_supported,
			"deletableConnection": _is_dynamic_compatible_profile(
				provider_id,
				stored_provider,
			),
			"key": {
				"saved": has_saved_key,
				"maskedValue": _masked_key(
					String(_credential_keys.get(provider_id, ""))
				),
				"status": (
					"saved" if has_saved_key else (
						"missing" if auth_required else "optional"
					)
				),
				"errorCode": (
					"PROVIDER_API_KEY_REQUIRED"
					if auth_required and not has_saved_key
					else ""
				),
			},
			"baseUrl": String(stored_provider.get("endpoint", "")),
			"insecureHttpApproved": (
				ENDPOINT_SECURITY.requires_insecure_http_consent(
					String(stored_provider.get("endpoint", ""))
				)
				and ENDPOINT_SECURITY.consent_matches(
					String(stored_provider.get("endpoint", "")),
					String(stored_provider.get(
						"insecureHttpConsentEndpoint",
						"",
					)),
				)
			),
			"defaultBaseUrl": String(source.get("defaultBaseUrl", "")),
			"apiModel": selected_model_id if custom_models else "",
			"apiModels": api_models,
			"models": (
				models_by_provider.get(provider_id, []) as Array
			).duplicate(true),
			"connection": _connection_projection(projected_source),
		})
	providers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("providerId", "")) < String(right.get("providerId", ""))
	)
	var available_ids: Array[String] = []
	for provider in providers:
		available_ids.append(String(provider.get("providerId", "")))
	var stored_selected := String(_stored_config.get("selectedProviderId", ""))
	if not stored_selected.is_empty():
		_selected_provider_id = stored_selected
	if not available_ids.has(_selected_provider_id):
		var default_provider_id := String(
			health.get("defaultProviderId", "")
		).strip_edges()
		_selected_provider_id = (
			default_provider_id
			if available_ids.has(default_provider_id)
			else available_ids[0]
			if not available_ids.is_empty()
			else ""
		)
	return {
		"ok": true,
		"data": {
			"capabilityMode": String(health.get("capabilityMode", "formal")),
			"source": String(health.get("source", "runtime")),
			"formalReady": bool(health.get("formalReady", false)) and available_count > 0,
			"pageTitle": "模型设置",
			"selectedProviderId": _selected_provider_id,
			"formalStatusLabel": _formal_status_label(
				providers,
				_selected_provider_id,
			),
			"providers": providers,
			"summary": {
				"availableProviderCount": available_count,
				"enabledModelCount": _selected_model_count(),
			},
		},
	}


func _formal_status_label(
	providers: Array[Dictionary],
	selected_provider_id: String,
) -> String:
	var selected := _provider_in_list(providers, selected_provider_id)
	if selected.is_empty():
		return "请选择服务商"
	var connection := selected.get("connection", {}) as Dictionary
	match String(connection.get("status", "unavailable")):
		"available":
			return "连接已通过"
		"checking":
			return "正在检查连接"
		"unchecked":
			return "请检查连接"
		"auth_failed":
			return "API Key 认证失败"
		"billing_failed":
			return "账户状态异常"
		"rate_limited":
			return "服务请求受限"
		"timeout":
			return "连接检查超时"
		"network_unavailable", "unavailable":
			return "连接暂不可用"
		"disabled":
			return "当前服务商已停用"
	var error_code := String(connection.get("errorCode", ""))
	if error_code == "PROVIDER_API_KEY_REQUIRED":
		return "请保存 API Key"
	if error_code == "PROVIDER_MODEL_SELECTION_REQUIRED":
		return "请选择居民模型"
	return "请完成模型设置"


func _provider_in_list(
	providers: Array[Dictionary],
	provider_id: String,
) -> Dictionary:
	for provider: Dictionary in providers:
		if String(provider.get("providerId", "")) == provider_id:
			return provider
	return {}


func _connection_projection(source: Dictionary) -> Dictionary:
	var status := String(source.get("status", "unavailable"))
	var error_code := String(source.get("errorCode", ""))
	var labels := {
		"available": "连接可用",
		"checking": "正在检查",
		"unchecked": "尚未检查",
		"not_configured": "配置待完成",
		"auth_failed": "认证失效",
		"billing_failed": "账户不可用",
		"rate_limited": "请求过于频繁",
		"timeout": "连接超时",
		"network_unavailable": "网络不可用",
		"disabled": "已停用",
		"unavailable": "当前不可用",
	}
	var label := String(labels.get(status, "当前不可用"))
	if error_code in ["PROVIDER_CONNECTION_FAILED", "PROVIDER_NETWORK_UNAVAILABLE"]:
		label = "网络不可用"
	return {
		"status": status,
		"label": label,
		"message": (
			"本次真实网络健康检查通过。"
			if status == "available"
			else _player_message_for_error_code(error_code)
		),
		"errorCode": error_code,
		"retryable": bool(source.get("retryable", false)),
	}


func _select_provider(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	if not bool(provider_result.get("ok", false)):
		return _failure("PROVIDER_SETTINGS_PROVIDER_UNKNOWN", false)
	var provider_id := String(provider_result.get("value", ""))
	if provider_id.is_empty() or _provider_from_confirmed(provider_id).is_empty():
		return _failure("PROVIDER_SETTINGS_PROVIDER_UNKNOWN", false)
	var candidate := _stored_config.duplicate(true)
	candidate["selectedProviderId"] = provider_id
	var persisted := _persist_candidate_and_reconfigure(candidate)
	if not bool(persisted.get("ok", false)):
		return persisted
	_selected_provider_id = provider_id
	_confirmed_data["selectedProviderId"] = provider_id
	_revision += 1
	return _success()


func _save_key(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	var api_key_value: Variant = payload.get("apiKey")
	if (
		not bool(provider_result.get("ok", false))
		or typeof(api_key_value) != TYPE_STRING
	):
		return _failure("PROVIDER_API_KEY_REQUIRED", false)
	var provider_id := String(provider_result.get("value", ""))
	var api_key := api_key_value as String
	if api_key.is_empty() or api_key != api_key.strip_edges():
		return _failure("PROVIDER_API_KEY_REQUIRED", false)
	if _provider_from_confirmed(provider_id).is_empty():
		return _failure("PROVIDER_SETTINGS_PROVIDER_UNKNOWN", false)
	var previous_key := String(_credential_keys.get(provider_id, ""))
	var had_previous_key := _credential_keys.has(provider_id)
	var credential_result := (
		_credential_store.save_api_key(provider_id, api_key) as Dictionary
	)
	if not bool(credential_result.get("ok", false)):
		return credential_result
	_credential_keys[provider_id] = api_key
	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var provider := (providers.get(provider_id, {}) as Dictionary).duplicate(true)
	provider.erase("api_key")
	provider["apiKeyRef"] = String(
		credential_result.get(
			"apiKeyRef",
			"secure_store.llm.%s.api_key" % provider_id,
		)
	)
	provider["enabled"] = true
	if provider_id == "volcengine-ark":
		provider["apiModels"] = []
	providers[provider_id] = provider
	candidate["providers"] = providers
	if provider_id == "volcengine-ark":
		var selected_models := (
			candidate.get("selectedModelByProvider", {}) as Dictionary
		)
		selected_models.erase(provider_id)
		candidate["selectedModelByProvider"] = selected_models
	candidate["selectedProviderId"] = provider_id
	var persisted := _persist_candidate_reconfigure_and_reload(
		candidate,
		"API Key 已保存在本机游戏数据目录。",
		provider_id,
	)
	if bool(persisted.get("ok", false)):
		return persisted
	var restored := _restore_credential(
		provider_id,
		had_previous_key,
		previous_key,
	)
	if not bool(restored.get("ok", false)):
		return restored
	_apply_provider_configuration()
	return persisted


func _delete_key(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	if not bool(provider_result.get("ok", false)):
		return _failure("PROVIDER_SETTINGS_PROVIDER_REQUIRED", false)
	var provider_id := String(provider_result.get("value", ""))
	if _provider_from_confirmed(provider_id).is_empty():
		return _failure("PROVIDER_SETTINGS_PROVIDER_UNKNOWN", false)
	var previous_key := String(_credential_keys.get(provider_id, ""))
	var had_previous_key := _credential_keys.has(provider_id)
	var credential_result := (
		_credential_store.delete_api_key(provider_id) as Dictionary
	)
	if not bool(credential_result.get("ok", false)):
		return credential_result
	_credential_keys.erase(provider_id)
	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var provider := (providers.get(provider_id, {}) as Dictionary).duplicate(true)
	provider.erase("api_key")
	provider.erase("apiKeyRef")
	providers[provider_id] = provider
	candidate["providers"] = providers
	var persisted := _persist_candidate_reconfigure_and_reload(
		candidate,
		"本机 API Key 已删除。",
		provider_id,
	)
	if bool(persisted.get("ok", false)):
		return persisted
	var restored := _restore_credential(
		provider_id,
		had_previous_key,
		previous_key,
	)
	if not bool(restored.get("ok", false)):
		return restored
	_apply_provider_configuration()
	return persisted


func _save_base_url(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	if not bool(provider_result.get("ok", false)):
		return _failure("PROVIDER_SETTINGS_PROVIDER_REQUIRED", false)
	var provider_id := String(provider_result.get("value", ""))
	if _provider_from_confirmed(provider_id).is_empty():
		return _failure("PROVIDER_SETTINGS_PROVIDER_UNKNOWN", false)
	var endpoint_value: Variant = payload.get("baseUrl")
	if typeof(endpoint_value) != TYPE_STRING:
		return _failure("PROVIDER_BASE_URL_INVALID", false)
	var endpoint := endpoint_value as String
	if endpoint != endpoint.strip_edges():
		return _failure("PROVIDER_BASE_URL_INVALID", false)
	if not endpoint.is_empty() and not _base_url_scheme_is_allowed(endpoint):
		return _failure("PROVIDER_BASE_URL_INVALID", false)
	var consent := _insecure_http_consent(payload, endpoint)
	if not bool(consent.get("ok", false)):
		return consent
	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var provider := (providers.get(provider_id, {}) as Dictionary).duplicate(true)
	if endpoint.is_empty():
		provider.erase("endpoint")
	else:
		provider["endpoint"] = endpoint
	_store_insecure_http_consent(
		provider,
		endpoint,
		bool(consent.get("approved", false)),
	)
	providers[provider_id] = provider
	candidate["providers"] = providers
	return _persist_candidate_reconfigure_and_reload(
		candidate,
		"Provider 地址已更新。",
		provider_id,
	)


func _create_compatible_connection(payload: Dictionary) -> Dictionary:
	var display_name_value: Variant = payload.get("displayName", "")
	if typeof(display_name_value) != TYPE_STRING:
		return _failure("PROVIDER_CONNECTION_NAME_INVALID", false)
	var requested_display_name := String(display_name_value).strip_edges()
	if not _compatible_display_name_is_valid(requested_display_name, true):
		return _failure("PROVIDER_CONNECTION_NAME_INVALID", false)
	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var index := 2
	var provider_id := "%s%d" % [COMPATIBLE_PROFILE_PREFIX, index]
	while providers.has(provider_id):
		index += 1
		provider_id = "%s%d" % [COMPATIBLE_PROFILE_PREFIX, index]
	providers[provider_id] = {
		"enabled": true,
		"connectionType": COMPATIBLE_PROFILE_TYPE,
		"displayName": (
			requested_display_name
			if not requested_display_name.is_empty()
			else "兼容接口 %d" % index
		),
		"authRequired": true,
		"apiModels": [],
	}
	candidate["providers"] = providers
	candidate["selectedProviderId"] = provider_id
	var persisted := _persist_candidate_reconfigure_and_reload(
		candidate,
		"新的兼容连接已建立，请填写地址和 API Key。",
		provider_id,
	)
	if bool(persisted.get("ok", false)):
		_selected_provider_id = provider_id
	return persisted


func _rename_compatible_connection(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	var display_name_value: Variant = payload.get("displayName", "")
	if (
		not bool(provider_result.get("ok", false))
		or typeof(display_name_value) != TYPE_STRING
	):
		return _failure("PROVIDER_CONNECTION_NAME_INVALID", false)
	var provider_id := String(provider_result.get("value", ""))
	var requested_display_name := String(display_name_value).strip_edges()
	if not _compatible_display_name_is_valid(requested_display_name, true):
		return _failure("PROVIDER_CONNECTION_NAME_INVALID", false)
	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var provider := (providers.get(provider_id, {}) as Dictionary).duplicate(true)
	if not _is_dynamic_compatible_profile(provider_id, provider):
		return _failure("PROVIDER_CONNECTION_RENAME_FORBIDDEN", false)
	if requested_display_name.is_empty():
		var endpoint := String(provider.get("endpoint", ""))
		requested_display_name = (
			_compatible_display_name(endpoint)
			if not endpoint.is_empty()
			else "兼容接口"
		)
	provider["displayName"] = requested_display_name
	providers[provider_id] = provider
	candidate["providers"] = providers
	return _persist_candidate_reconfigure_and_reload(
		candidate,
		"连接名称已更新。",
		provider_id,
	)


func _delete_compatible_connection(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	if not bool(provider_result.get("ok", false)):
		return _failure("PROVIDER_SETTINGS_PROVIDER_REQUIRED", false)
	var provider_id := String(provider_result.get("value", ""))
	var providers := _stored_config.get("providers", {}) as Dictionary
	var stored_provider := providers.get(provider_id, {}) as Dictionary
	if not _is_dynamic_compatible_profile(provider_id, stored_provider):
		return _failure("PROVIDER_CONNECTION_DELETE_FORBIDDEN", false)
	for api_model: String in _stored_api_models(stored_provider):
		if not _provider_service.has_method("resident_ids_using_model"):
			continue
		var resident_ids_value: Variant = _provider_service.resident_ids_using_model(
			provider_id,
			api_model,
		)
		if resident_ids_value is Array and not (resident_ids_value as Array).is_empty():
			return _failure(
				"PROVIDER_CONNECTION_IN_USE",
				false,
				"这个连接仍有居民正在使用，请先重新分配居民模型。",
				resident_ids_value,
			)
	var previous_key := String(_credential_keys.get(provider_id, ""))
	var had_previous_key := _credential_keys.has(provider_id)
	var credential_result := (
		_credential_store.delete_api_key(provider_id) as Dictionary
	)
	if not bool(credential_result.get("ok", false)):
		return credential_result
	_credential_keys.erase(provider_id)
	var candidate := _stored_config.duplicate(true)
	var candidate_providers := candidate.get("providers", {}) as Dictionary
	candidate_providers.erase(provider_id)
	candidate["providers"] = candidate_providers
	var selected_models := (
		candidate.get("selectedModelByProvider", {}) as Dictionary
	)
	selected_models.erase(provider_id)
	candidate["selectedModelByProvider"] = selected_models
	if String(candidate.get("selectedProviderId", "")) == provider_id:
		candidate["selectedProviderId"] = _remaining_custom_provider_id(
			candidate_providers,
			provider_id,
		)
	var persisted := _persist_candidate_reconfigure_and_reload(
		candidate,
		"兼容连接已删除。",
		provider_id,
	)
	if bool(persisted.get("ok", false)):
		_discovered_models_by_provider.erase(provider_id)
		return persisted
	var restored := _restore_credential(
		provider_id,
		had_previous_key,
		previous_key,
	)
	if not bool(restored.get("ok", false)):
		return restored
	_apply_provider_configuration()
	return persisted


func _remaining_custom_provider_id(
	providers: Dictionary,
	deleted_provider_id: String,
) -> String:
	for preferred_id: String in [
		"ollama",
		"ollama-cloud",
		"lm-studio",
		"302-ai",
	]:
		if preferred_id != deleted_provider_id and providers.has(preferred_id):
			return preferred_id
	var provider_ids: Array[String] = []
	for provider_id_value: Variant in providers.keys():
		var provider_id := String(provider_id_value)
		if provider_id == deleted_provider_id:
			continue
		var provider := providers.get(provider_id, {}) as Dictionary
		if _is_dynamic_compatible_profile(provider_id, provider):
			provider_ids.append(provider_id)
	provider_ids.sort()
	if not provider_ids.is_empty():
		return provider_ids[0]
	# 内置 Ollama 配置即使尚未写进存档，也始终存在于自定义模型分组。
	return "ollama"


func _save_connection(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	if not bool(provider_result.get("ok", false)):
		return _failure("PROVIDER_SETTINGS_PROVIDER_REQUIRED", false)
	var provider_id := String(provider_result.get("value", ""))
	var confirmed_provider := _provider_from_confirmed(provider_id)
	if confirmed_provider.is_empty():
		return _failure("PROVIDER_SETTINGS_PROVIDER_UNKNOWN", false)
	var endpoint_value: Variant = payload.get("baseUrl", "")
	var api_key_value: Variant = payload.get("apiKey", "")
	if typeof(endpoint_value) != TYPE_STRING or typeof(api_key_value) != TYPE_STRING:
		return _failure("PROVIDER_BASE_URL_INVALID", false)
	var endpoint := endpoint_value as String
	var api_key := api_key_value as String
	if endpoint != endpoint.strip_edges():
		return _failure("PROVIDER_BASE_URL_INVALID", false)
	if not endpoint.is_empty() and not _base_url_scheme_is_allowed(endpoint):
		return _failure("PROVIDER_BASE_URL_INVALID", false)
	var consent := _insecure_http_consent(payload, endpoint)
	if not bool(consent.get("ok", false)):
		return consent
	if api_key != api_key.strip_edges():
		return _failure("PROVIDER_API_KEY_REQUIRED", false)
	if (
		_provider_auth_required(confirmed_provider)
		and api_key.is_empty()
		and not _has_saved_key(provider_id)
	):
		return _failure("PROVIDER_API_KEY_REQUIRED", false)

	var previous_key := String(_credential_keys.get(provider_id, ""))
	var had_previous_key := _credential_keys.has(provider_id)
	var api_key_ref := ""
	if not api_key.is_empty():
		var credential_result := (
			_credential_store.save_api_key(provider_id, api_key) as Dictionary
		)
		if not bool(credential_result.get("ok", false)):
			return credential_result
		_credential_keys[provider_id] = api_key
		api_key_ref = String(credential_result.get(
			"apiKeyRef",
			"secure_store.llm.%s.api_key" % provider_id,
		))

	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var provider := (providers.get(provider_id, {}) as Dictionary).duplicate(true)
	if endpoint.is_empty():
		provider.erase("endpoint")
	else:
		provider["endpoint"] = endpoint
	_store_insecure_http_consent(
		provider,
		endpoint,
		bool(consent.get("approved", false)),
	)
	if (
		_is_dynamic_compatible_profile(provider_id, provider)
		and not endpoint.is_empty()
		and _compatible_display_name_is_automatic(
			String(provider.get("displayName", ""))
		)
	):
		provider["displayName"] = _compatible_display_name(endpoint)
	provider.erase("api_key")
	if not api_key_ref.is_empty():
		provider["apiKeyRef"] = api_key_ref
	provider["enabled"] = true
	providers[provider_id] = provider
	candidate["providers"] = providers
	candidate["selectedProviderId"] = provider_id
	var persisted := _persist_candidate_reconfigure_and_reload(
		candidate,
		"连接设置已保存。",
		provider_id,
	)
	if bool(persisted.get("ok", false)):
		return persisted
	if not api_key.is_empty():
		var restored := _restore_credential(
			provider_id,
			had_previous_key,
			previous_key,
		)
		if not bool(restored.get("ok", false)):
			return restored
	_apply_provider_configuration()
	return persisted


func _save_api_model(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	var api_model_value: Variant = payload.get("apiModel")
	if (
		not bool(provider_result.get("ok", false))
		or typeof(api_model_value) != TYPE_STRING
	):
		return _failure("PROVIDER_API_MODEL_REQUIRED", false)
	var provider_id := String(provider_result.get("value", ""))
	var confirmed_provider := _provider_from_confirmed(provider_id)
	if confirmed_provider.is_empty() or not bool(
		confirmed_provider.get("customModels", false)
	):
		return _failure("PROVIDER_SETTINGS_PROVIDER_UNKNOWN", false)
	var api_model := (api_model_value as String).strip_edges()
	if api_model.is_empty() or api_model != api_model_value:
		return _failure("PROVIDER_API_MODEL_REQUIRED", false)
	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var provider := (providers.get(provider_id, {}) as Dictionary).duplicate(true)
	var api_models := _stored_api_models(provider)
	if api_model not in api_models:
		api_models.append(api_model)
	provider["apiModels"] = api_models
	provider["enabled"] = true
	providers[provider_id] = provider
	candidate["providers"] = providers
	var selected_models := (
		candidate.get("selectedModelByProvider", {}) as Dictionary
	)
	selected_models[provider_id] = api_model
	candidate["selectedModelByProvider"] = selected_models
	candidate["selectedProviderId"] = provider_id
	var persisted := _persist_candidate_reconfigure_and_reload(
		candidate,
		"模型已添加并设为居民默认模型。",
		provider_id,
	)
	return persisted


func _delete_api_model(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	var api_model_value: Variant = payload.get("apiModel")
	if (
		not bool(provider_result.get("ok", false))
		or typeof(api_model_value) != TYPE_STRING
	):
		return _failure("PROVIDER_API_MODEL_REQUIRED", false)
	var provider_id := String(provider_result.get("value", ""))
	var api_model := (api_model_value as String).strip_edges()
	var confirmed_provider := _provider_from_confirmed(provider_id)
	if (
		api_model.is_empty()
		or confirmed_provider.is_empty()
		or not bool(confirmed_provider.get("customModels", false))
	):
		return _failure("PROVIDER_API_MODEL_UNKNOWN", false)
	if _provider_service.has_method("resident_ids_using_model"):
		var resident_ids_value: Variant = _provider_service.resident_ids_using_model(
			provider_id,
			api_model,
		)
		if resident_ids_value is Array and not (resident_ids_value as Array).is_empty():
			return _failure(
				"PROVIDER_API_MODEL_IN_USE",
				false,
				"请先为正在使用这个模型的居民重新分配模型。",
				resident_ids_value,
			)
	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var provider := (providers.get(provider_id, {}) as Dictionary).duplicate(true)
	var api_models := _stored_api_models(provider)
	if api_model not in api_models:
		return _failure("PROVIDER_API_MODEL_UNKNOWN", false)
	api_models.erase(api_model)
	provider["apiModels"] = api_models
	providers[provider_id] = provider
	candidate["providers"] = providers
	var selected_models := (
		candidate.get("selectedModelByProvider", {}) as Dictionary
	)
	if String(selected_models.get(provider_id, "")) == api_model:
		if api_models.is_empty():
			selected_models.erase(provider_id)
		else:
			selected_models[provider_id] = api_models[0]
	candidate["selectedModelByProvider"] = selected_models
	return _persist_candidate_reconfigure_and_reload(
		candidate,
		"自定义模型已删除。",
		provider_id,
	)


func _discover_models(payload: Dictionary, request_id: String) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	if not bool(provider_result.get("ok", false)):
		return _failure("PROVIDER_SETTINGS_PROVIDER_REQUIRED", false)
	var provider_id := String(provider_result.get("value", ""))
	var provider := _provider_from_confirmed(provider_id)
	if provider.is_empty() or not bool(provider.get("customModels", false)):
		return _failure("PROVIDER_MODEL_CATALOG_UNSUPPORTED", false)
	if not bool(provider.get("modelCatalogSupported", false)):
		return _failure(
			"PROVIDER_MODEL_CATALOG_UNSUPPORTED",
			false,
			"当前服务需要手动填写模型或推理接入点 ID。",
		)
	if not bool(provider.get("enabled", true)):
		return _failure("PROVIDER_DISABLED", false)
	if _provider_auth_required(provider) and not _has_saved_key(provider_id):
		return _failure("PROVIDER_API_KEY_REQUIRED", false)
	_active_model_catalog_request_id = request_id
	var started_value: Variant = _provider_service.call(
		"request_model_catalog",
		provider_id,
		Callable(self, "_on_model_catalog_completed").bind(
			request_id,
			provider_id,
		),
	)
	if not started_value is Dictionary:
		_active_model_catalog_request_id = ""
		return _failure("PROVIDER_MODEL_CATALOG_REQUEST_FAILED", true)
	var started := started_value as Dictionary
	if not bool(started.get("accepted", false)):
		_active_model_catalog_request_id = ""
		return _normalize_failure(
			started,
			"PROVIDER_MODEL_CATALOG_REQUEST_FAILED",
		)
	return {
		"ok": true,
		"accepted": true,
		"status": "checking",
		"errorCode": "",
		"retryable": false,
	}


func _on_model_catalog_completed(
	result_value: Variant,
	request_id: String,
	provider_id: String,
) -> void:
	if request_id != _active_model_catalog_request_id:
		return
	_active_model_catalog_request_id = ""
	var result := (
		result_value as Dictionary
		if result_value is Dictionary
		else _failure("PROVIDER_MODEL_CATALOG_INVALID", false)
	)
	var final_result: Dictionary
	if not bool(result.get("ok", false)):
		final_result = _normalize_failure(
			result,
			"PROVIDER_MODEL_CATALOG_REQUEST_FAILED",
		)
	else:
		final_result = _store_discovered_models(
			provider_id,
			result.get("models", []),
		)
	var operation := _operation(
		request_id,
		"provider_settings.discover_models",
		"success" if bool(final_result.get("ok", false)) else "error",
	)
	operation["completedAtMsec"] = Time.get_ticks_msec()
	operation["message"] = String(final_result.get("message", ""))
	_publish_result(
		operation,
		final_result,
		"success" if bool(final_result.get("ok", false)) else "error",
	)
	operation_completed.emit(SCOPE, operation.duplicate(true))


func _store_discovered_models(
	provider_id: String,
	models_value: Variant,
) -> Dictionary:
	if not models_value is Array:
		return _failure("PROVIDER_MODEL_CATALOG_INVALID", false)
	var discovered: Array[String] = []
	for value: Variant in models_value as Array:
		if typeof(value) != TYPE_STRING:
			continue
		var model_id := (value as String).strip_edges()
		if (
			not model_id.is_empty()
			and _is_discoverable_chat_model(model_id)
			and model_id not in discovered
		):
			discovered.append(model_id)
	if discovered.is_empty():
		return _failure("PROVIDER_MODEL_CATALOG_EMPTY", false)
	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var provider := (
		providers.get(provider_id, {}) as Dictionary
	).duplicate(true)
	# 刷新列表时不能静默移除仍由居民使用的旧模型。
	for stored_model: String in _stored_api_models(provider):
		if stored_model in discovered:
			continue
		if _resident_ids_using_model(provider_id, stored_model).is_empty():
			continue
		discovered.append(stored_model)
	var selected_models := (
		candidate.get("selectedModelByProvider", {}) as Dictionary
	)
	var selected_model := String(
		selected_models.get(provider_id, "")
	).strip_edges()
	if selected_model in discovered:
		discovered.erase(selected_model)
		discovered.push_front(selected_model)
	else:
		selected_models[provider_id] = discovered[0]
	provider["apiModels"] = discovered.duplicate()
	provider["enabled"] = true
	providers[provider_id] = provider
	candidate["providers"] = providers
	candidate["selectedModelByProvider"] = selected_models
	candidate["selectedProviderId"] = provider_id
	var message := (
		"已从火山方舟读取 %d 个可用模型。" % discovered.size()
		if provider_id == "volcengine-ark"
		else "已自动读取并加入 %d 个可用模型。" % discovered.size()
	)
	var persisted := _persist_candidate_reconfigure_and_reload(
		candidate,
		message,
		provider_id,
	)
	if bool(persisted.get("ok", false)):
		_discovered_models_by_provider.erase(provider_id)
		persisted["models"] = discovered.duplicate()
	return persisted


func _is_discoverable_chat_model(model_id: String) -> bool:
	var normalized := model_id.to_lower()
	for marker: String in [
		"embedding",
		"rerank",
		"moderation",
		"seedream",
		"seedance",
		"text-to-image",
		"image-generation",
		"image-edit",
		"text-to-video",
		"video-generation",
		"speech",
		"transcri",
		"whisper",
		"-tts",
		"tts-",
		"music-generation",
		"hyper3d",
		"seed3d",
		"hitem3d",
	]:
		if marker in normalized:
			return false
	return true


func _resident_ids_using_model(provider_id: String, model_id: String) -> Array:
	if not _provider_service.has_method("resident_ids_using_model"):
		return []
	var resident_ids_value: Variant = _provider_service.resident_ids_using_model(
		provider_id,
		model_id,
	)
	return (
		(resident_ids_value as Array).duplicate()
		if resident_ids_value is Array
		else []
	)


func _set_enabled(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	if not bool(provider_result.get("ok", false)):
		return _failure("PROVIDER_SETTINGS_PROVIDER_REQUIRED", false)
	var provider_id := String(provider_result.get("value", ""))
	if _provider_from_confirmed(provider_id).is_empty():
		return _failure("PROVIDER_SETTINGS_PROVIDER_UNKNOWN", false)
	var enabled_value: Variant = payload.get("enabled")
	if typeof(enabled_value) != TYPE_BOOL:
		return _failure("PROVIDER_SETTINGS_PAYLOAD_INVALID", false)
	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var provider := (providers.get(provider_id, {}) as Dictionary).duplicate(true)
	provider["enabled"] = enabled_value as bool
	providers[provider_id] = provider
	candidate["providers"] = providers
	return _persist_candidate_reconfigure_and_reload(
		candidate,
		"Provider 状态已更新。",
		provider_id,
	)


func _select_model(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	var model_result := _required_canonical_id(payload, "modelId")
	var enabled_value: Variant = payload.get("enabled")
	if (
		not bool(provider_result.get("ok", false))
		or not bool(model_result.get("ok", false))
		or typeof(enabled_value) != TYPE_BOOL
	):
		return _failure("PROVIDER_MODEL_SELECTION_REQUIRED", false)
	var provider_id := String(provider_result.get("value", ""))
	var model_id := String(model_result.get("value", ""))
	var provider := _provider_from_confirmed(provider_id)
	if provider.is_empty() or not _provider_has_model(provider, model_id):
		return _failure("LLM_MODEL_UNKNOWN", false)
	var candidate := _stored_config.duplicate(true)
	var selected_models := candidate.get("selectedModelByProvider", {}) as Dictionary
	if enabled_value as bool:
		selected_models[provider_id] = model_id
		candidate["selectedProviderId"] = provider_id
	else:
		selected_models.erase(provider_id)
	candidate["selectedModelByProvider"] = selected_models
	return _persist_candidate_reconfigure_and_reload(
		candidate,
		"居民默认模型已更新。",
		provider_id,
	)


func _check_connection(payload: Dictionary, request_id: String) -> Dictionary:
	var provider_id := _selected_provider_id
	if payload.has("providerId"):
		var provider_result := _required_canonical_id(payload, "providerId")
		if not bool(provider_result.get("ok", false)):
			return _failure("PROVIDER_SETTINGS_PROVIDER_REQUIRED", false)
		provider_id = String(provider_result.get("value", ""))
	if provider_id.is_empty():
		return _failure("PROVIDER_SETTINGS_PROVIDER_REQUIRED", false)
	var provider := _provider_from_confirmed(provider_id)
	if provider.is_empty():
		return _failure("PROVIDER_SETTINGS_PROVIDER_UNKNOWN", false)
	var selected_models := _stored_config.get("selectedModelByProvider", {}) as Dictionary
	var model_id := String(selected_models.get(provider_id, "")).strip_edges()
	if model_id.is_empty():
		return _failure("PROVIDER_MODEL_SELECTION_REQUIRED", false)
	var stored_providers := _stored_config.get("providers", {}) as Dictionary
	var stored_provider := stored_providers.get(provider_id, {}) as Dictionary
	if not bool(stored_provider.get("enabled", true)):
		return _failure("PROVIDER_DISABLED", false)
	if _provider_auth_required(provider) and not _has_saved_key(provider_id):
		return _failure("PROVIDER_API_KEY_REQUIRED", false)
	return _start_health_request(
		[{"providerId": provider_id, "modelId": model_id}],
		request_id,
		"provider_settings.check_connection",
	)


func _start_configured_health_check() -> Dictionary:
	if (
		OS.is_debug_build()
		and OS.get_environment(TEST_NO_NETWORK_ENV) == "1"
	):
		return {
			"ok": true,
			"accepted": false,
			"status": "test_network_disabled",
			"errorCode": "",
			"retryable": false,
		}
	var targets: Array[Dictionary] = []
	var selected_models := _stored_config.get("selectedModelByProvider", {}) as Dictionary
	var providers := _stored_config.get("providers", {}) as Dictionary
	for provider_id_value: Variant in selected_models:
		var provider_id := String(provider_id_value).strip_edges()
		var model_id := String(selected_models.get(provider_id, "")).strip_edges()
		var provider_config := providers.get(provider_id, {}) as Dictionary
		var confirmed_provider := _provider_from_confirmed(provider_id)
		if (
			provider_id.is_empty()
			or model_id.is_empty()
			or not bool(provider_config.get("enabled", true))
			or (
				_provider_auth_required(confirmed_provider)
				and not _has_saved_key(provider_id)
			)
		):
			continue
		targets.append({"providerId": provider_id, "modelId": model_id})
	if targets.is_empty():
		return {
			"ok": true,
			"accepted": false,
			"status": "not_required",
			"errorCode": "",
			"retryable": false,
		}
	var request_id := _next_request_id()
	var operation := _operation(
		request_id,
		"provider_settings.startup_health_check",
		"loading",
	)
	_publish_operation(operation, {})
	return _start_health_request(
		targets,
		request_id,
		"provider_settings.startup_health_check",
	)


func _start_health_request(
	targets: Array,
	request_id: String,
	intent: String,
) -> Dictionary:
	_active_health_request_id = request_id
	var health_generation := _health_configuration_generation
	var started_value: Variant = _provider_service.call(
		"request_health_check",
		targets.duplicate(true),
		Callable(self, "_on_health_request_completed").bind(
			request_id,
			intent,
			health_generation,
			targets.duplicate(true),
		),
	)
	if not started_value is Dictionary:
		_active_health_request_id = ""
		return _failure("PROVIDER_HEALTH_QUERY_FAILED", false)
	var started := started_value as Dictionary
	if not bool(started.get("accepted", false)):
		_active_health_request_id = ""
		return _normalize_failure(started, "PROVIDER_HEALTH_QUERY_FAILED")
	return {
		"ok": true,
		"accepted": true,
		"status": "checking",
		"errorCode": "",
		"retryable": false,
		"requestId": request_id,
	}


func _on_health_request_completed(
	result: Dictionary,
	request_id: String,
	intent: String,
	health_generation: int,
	requested_targets: Array,
) -> void:
	if (
		request_id != _active_health_request_id
		or health_generation != _health_configuration_generation
	):
		return
	_active_health_request_id = ""
	if String(result.get("status", "")) == "stale":
		return
	_mark_health_targets_current(requested_targets)
	var loaded := _load_public_snapshot()
	if bool(loaded.get("ok", false)):
		_confirmed_data = (loaded.get("data", {}) as Dictionary).duplicate(true)
	_revision += 1
	var completed := result.duplicate(true)
	if not bool(loaded.get("ok", false)):
		completed = loaded
	var final_status := (
		"success"
		if bool(completed.get("ok", false))
		else ("error" if bool(completed.get("retryable", false)) else "rejected")
	)
	var operation := _operation(request_id, intent, final_status)
	operation["completedAtMsec"] = Time.get_ticks_msec()
	operation["message"] = (
		"本次真实网络健康检查通过。"
		if bool(completed.get("ok", false))
		else "本次真实网络健康检查未通过。"
	)
	_publish_result(operation, completed, final_status)
	operation_completed.emit(SCOPE, operation.duplicate(true))


func _load_stored_config() -> Dictionary:
	var loaded := _store.load_config()
	if not bool(loaded.get("ok", false)):
		return loaded
	_stored_config = (loaded.get("config", {}) as Dictionary).duplicate(true)
	if not _stored_config.has("selectedProviderId"):
		_stored_config["selectedProviderId"] = ""
	if not _stored_config.get("selectedModelByProvider", {}) is Dictionary:
		_stored_config["selectedModelByProvider"] = {}
	if not _stored_config.get("providers", {}) is Dictionary:
		_stored_config["providers"] = {}
	var loaded_credentials := (
		_credential_store.load_keys() as Dictionary
	)
	if not bool(loaded_credentials.get("ok", false)):
		return loaded_credentials
	_credential_keys = (
		loaded_credentials.get("keys", {}) as Dictionary
	).duplicate(true)
	var migration_result := _migrate_plaintext_credentials()
	if not bool(migration_result.get("ok", false)):
		return migration_result
	var catalog_migration := _sanitize_legacy_302_catalog()
	if not bool(catalog_migration.get("ok", false)):
		return catalog_migration
	_selected_provider_id = String(_stored_config.get("selectedProviderId", ""))
	return {"ok": true, "errorCode": "", "retryable": false}


func _sanitize_legacy_302_catalog() -> Dictionary:
	var providers := _stored_config.get("providers", {}) as Dictionary
	if not providers.has("302-ai"):
		return _success()
	var provider := (providers.get("302-ai", {}) as Dictionary).duplicate(true)
	var stored_models := _stored_api_models(provider)
	# 旧版本曾把 302.AI 的全品类目录（数百项）原样写入存档。
	# 小规模列表可能是玩家手动维护的，不在这里擅自改动。
	if stored_models.size() <= 50:
		return _success()
	var filtered := THREE_ZERO_TWO_PROVIDER.filter_town_models(stored_models)
	if filtered.is_empty():
		return _success()
	provider["apiModels"] = filtered.duplicate()
	providers["302-ai"] = provider
	_stored_config["providers"] = providers
	var selected_models := (
		_stored_config.get("selectedModelByProvider", {}) as Dictionary
	)
	var selected := String(selected_models.get("302-ai", ""))
	if selected not in filtered:
		selected_models["302-ai"] = filtered[0]
	_stored_config["selectedModelByProvider"] = selected_models
	return _store.save_config(_stored_config)


func _persist_candidate_and_reconfigure(candidate: Dictionary) -> Dictionary:
	var previous := _stored_config.duplicate(true)
	var persisted := _store.save_config(candidate)
	if not bool(persisted.get("ok", false)):
		return persisted
	_stored_config = candidate.duplicate(true)
	var configured := _apply_provider_configuration()
	if bool(configured.get("ok", false)):
		return configured
	var rollback := _store.save_config(previous)
	_stored_config = previous
	var runtime_rollback := _apply_provider_configuration()
	if (
		not bool(rollback.get("ok", false))
		or not bool(runtime_rollback.get("ok", false))
	):
		return _failure("PROVIDER_SETTINGS_ROLLBACK_FAILED", true)
	return configured


func _persist_candidate_reconfigure_and_reload(
	candidate: Dictionary,
	message: String,
	dirty_provider_id := "",
) -> Dictionary:
	var persisted := _persist_candidate_and_reconfigure(candidate)
	if not bool(persisted.get("ok", false)):
		return persisted
	if not dirty_provider_id.is_empty():
		_discovered_models_by_provider.erase(dirty_provider_id)
		_invalidate_provider_health(dirty_provider_id)
	var loaded := _load_public_snapshot()
	if not bool(loaded.get("ok", false)):
		return loaded
	_confirmed_data = (loaded.get("data", {}) as Dictionary).duplicate(true)
	_selected_provider_id = String(_confirmed_data.get("selectedProviderId", ""))
	_revision += 1
	return _success(message)


func _apply_provider_configuration() -> Dictionary:
	if _provider_service == null:
		return _failure("PROVIDER_SETTINGS_SERVICE_NOT_BOUND", false)
	var configured_value: Variant = _provider_service.call("configure", {
		"capabilityMode": "formal",
		"source": "runtime",
		"allowFake": false,
		"providerConfigs": _provider_configs_for_runtime(),
	}, (
		_request_host
		if _request_host != null and is_instance_valid(_request_host)
		else (Engine.get_main_loop().root if Engine.get_main_loop() is SceneTree else null)
	))
	if not configured_value is Dictionary:
		return _failure("PROVIDER_RECONFIGURE_FAILED", false)
	var configured := configured_value as Dictionary
	if not bool(configured.get("ok", false)):
		return _normalize_failure(configured, "PROVIDER_RECONFIGURE_FAILED")
	return configured


func _provider_configs_for_runtime() -> Dictionary:
	var result: Dictionary = {}
	for provider_id_value: Variant in (_stored_config.get("providers", {}) as Dictionary):
		var provider_id := String(provider_id_value)
		var source := (
			(_stored_config.get("providers", {}) as Dictionary).get(provider_id, {})
			as Dictionary
		)
		var dynamic_profile := (
			String(source.get("connectionType", ""))
			== COMPATIBLE_PROFILE_TYPE
		)
		if not bool(source.get("enabled", true)) and not dynamic_profile:
			continue
		var config: Dictionary = {}
		if dynamic_profile:
			config["connection_type"] = COMPATIBLE_PROFILE_TYPE
			config["display_name"] = String(
				source.get("displayName", "兼容接口")
			)
			config["api_key_required"] = bool(
				source.get("authRequired", true)
			)
			config["disabled"] = not bool(source.get("enabled", true))
		var api_key := String(_credential_keys.get(provider_id, "")).strip_edges()
		if not api_key.is_empty():
			config["api_key"] = api_key
		var endpoint := String(source.get("endpoint", "")).strip_edges()
		if not endpoint.is_empty():
			if not ENDPOINT_SECURITY.consent_matches(
				endpoint,
				String(source.get("insecureHttpConsentEndpoint", "")),
			):
				continue
			config["endpoint"] = endpoint
			if ENDPOINT_SECURITY.requires_insecure_http_consent(endpoint):
				config["allow_insecure_http"] = true
		var api_models := _stored_api_models(source)
		if not api_models.is_empty():
			config["api_models"] = api_models
		var selected_models := (
			_stored_config.get("selectedModelByProvider", {}) as Dictionary
		)
		var selected_model := String(
			selected_models.get(provider_id, "")
		).strip_edges()
		if selected_model in api_models:
			config["api_model"] = selected_model
		result[provider_id] = config
	return result


func _migrate_plaintext_credentials() -> Dictionary:
	var providers := _stored_config.get("providers", {}) as Dictionary
	var changed := false
	for provider_id_value: Variant in providers.keys():
		var provider_id := String(provider_id_value).strip_edges()
		var provider := (providers.get(provider_id, {}) as Dictionary).duplicate(true)
		var plaintext_key := String(provider.get("api_key", "")).strip_edges()
		if plaintext_key.is_empty():
			continue
		var saved := (
			_credential_store.save_api_key(
				provider_id,
				plaintext_key,
			) as Dictionary
		)
		provider.erase("api_key")
		changed = true
		if bool(saved.get("ok", false)):
			_credential_keys[provider_id] = plaintext_key
			provider["apiKeyRef"] = String(
				saved.get(
					"apiKeyRef",
					"secure_store.llm.%s.api_key" % provider_id,
				)
			)
		else:
			_credential_keys.erase(provider_id)
			provider.erase("apiKeyRef")
		providers[provider_id] = provider
		_stored_config["providers"] = providers
		if not bool(saved.get("ok", false)):
			var scrubbed := (
				_store.save_config(_stored_config)
			)
			if not bool(scrubbed.get("ok", false)):
				return scrubbed
			return saved
	if changed:
		_stored_config["providers"] = providers
		return _store.save_config(_stored_config)
	return _success()


func _has_saved_key(provider_id: String) -> bool:
	return not String(_credential_keys.get(provider_id, "")).strip_edges().is_empty()


func _provider_auth_required(provider: Dictionary) -> bool:
	return bool(provider.get("authRequired", true))


func _stored_api_models(provider: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var models_value: Variant = provider.get("apiModels", [])
	if not models_value is Array:
		return result
	for value: Variant in models_value as Array:
		if typeof(value) != TYPE_STRING:
			continue
		var model_id := (value as String).strip_edges()
		if not model_id.is_empty() and model_id not in result:
			result.append(model_id)
	return result


func _base_url_scheme_is_allowed(endpoint: String) -> bool:
	return ENDPOINT_SECURITY.scheme_is_supported(endpoint)


func _insecure_http_consent(
	payload: Dictionary,
	endpoint: String,
) -> Dictionary:
	var approval_value: Variant = payload.get("allowInsecureHttp", false)
	if typeof(approval_value) != TYPE_BOOL:
		return _failure("PROVIDER_INSECURE_HTTP_CONSENT_INVALID", false)
	var requires_consent := (
		ENDPOINT_SECURITY.requires_insecure_http_consent(endpoint)
	)
	if requires_consent and not bool(approval_value):
		return _failure("PROVIDER_INSECURE_HTTP_CONSENT_REQUIRED", false)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"approved": requires_consent and bool(approval_value),
	}


func _store_insecure_http_consent(
	provider: Dictionary,
	endpoint: String,
	approved: bool,
) -> void:
	if approved:
		provider["insecureHttpConsentEndpoint"] = endpoint
		return
	provider.erase("insecureHttpConsentEndpoint")


func _masked_key(api_key: String) -> String:
	if api_key.is_empty():
		return ""
	return "••••••••••••••••"


func _selected_model_count() -> int:
	var count := 0
	for model_id: Variant in (_stored_config.get("selectedModelByProvider", {}) as Dictionary).values():
		if not String(model_id).is_empty():
			count += 1
	return count


func _provider_from_confirmed(provider_id: String) -> Dictionary:
	for value in _confirmed_data.get("providers", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("providerId", "")) == provider_id:
			return value as Dictionary
	return {}


func _provider_has_model(provider: Dictionary, model_id: String) -> bool:
	for value: Variant in provider.get("models", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get("modelId", "")) == model_id
		):
			return true
	return false


func _invalidate_provider_health(provider_id: String) -> void:
	_health_configuration_generation += 1
	_active_health_request_id = ""
	_dirty_health_providers[provider_id] = true


func _mark_health_targets_current(targets: Array) -> void:
	for value: Variant in targets:
		if not value is Dictionary:
			continue
		var provider_id := String(
			(value as Dictionary).get("providerId", "")
		).strip_edges()
		if not provider_id.is_empty():
			_dirty_health_providers.erase(provider_id)


func _publish_disabled(error_code: String) -> void:
	_revision += 1
	var error := _error_payload(error_code, false, "正式 Provider 设置只读服务尚未绑定。")
	_view_model = _base_view_model(
		"disabled",
		_empty_data(),
		_operation("", "", "disabled"),
		error,
	)
	view_model_changed.emit(SCOPE, _view_model.duplicate(true))


func _publish_operation(operation: Dictionary, error: Dictionary) -> void:
	_view_model = _base_view_model(
		"loading" if String(operation.get("status", "")) == "loading" else "ready",
		_confirmed_data,
		operation,
		error,
	)
	view_model_changed.emit(SCOPE, _view_model.duplicate(true))


func _publish_result(operation: Dictionary, result: Dictionary, status: String) -> void:
	var error: Dictionary = {}
	if not bool(result.get("ok", false)):
		var error_code := String(
			result.get("errorCode", "PROVIDER_SETTINGS_OPERATION_FAILED")
		)
		var message := String(result.get("message", "")).strip_edges()
		if message.is_empty():
			message = _player_message_for_error_code(error_code)
		error = _error_payload(
			error_code,
			bool(result.get("retryable", false)),
			message,
			result.get("errors", []),
		)
	_view_model = _base_view_model(
		"ready" if status == "success" else status,
		_confirmed_data,
		operation,
		error,
	)
	view_model_changed.emit(SCOPE, _view_model.duplicate(true))


func _base_view_model(
	status: String,
	data: Dictionary,
	operation: Dictionary,
	error: Dictionary,
) -> Dictionary:
	var rendered_data := data.duplicate(true)
	var providers := rendered_data.get("providers", []) as Array
	for index: int in range(providers.size()):
		if not providers[index] is Dictionary:
			continue
		var provider := (providers[index] as Dictionary).duplicate(true)
		var provider_id := String(provider.get("providerId", ""))
		provider["discoveredModels"] = (
			_discovered_models_by_provider.get(provider_id, []) as Array
		).duplicate()
		providers[index] = provider
	rendered_data["providers"] = providers
	var actions_value := _actions(rendered_data)
	return AiTownUiViewModel.envelope(
		SCOPE,
		status,
		_revision,
		rendered_data,
		actions_value,
		operation,
		error,
	)


func _actions(data: Dictionary) -> Dictionary:
	var has_providers := not (data.get("providers", []) as Array).is_empty()
	return {
		"back": _action("provider_settings.back", false, HOST_ROUTING_REQUIRED),
		"selectProvider": _action("provider_settings.select_provider", has_providers),
		"setProviderEnabled": _action("provider_settings.set_enabled", has_providers),
		"saveKey": _action("provider_settings.save_key", has_providers),
		"deleteKey": _action("provider_settings.delete_key", has_providers),
		"saveBaseUrl": _action("provider_settings.save_base_url", has_providers),
		"saveConnection": _action("provider_settings.save_connection", has_providers),
		"createCompatibleConnection": _action(
			"provider_settings.create_compatible_connection",
			has_providers,
		),
		"renameCompatibleConnection": _action(
			"provider_settings.rename_compatible_connection",
			has_providers,
		),
		"deleteCompatibleConnection": _action(
			"provider_settings.delete_compatible_connection",
			has_providers,
		),
		"saveApiModel": _action("provider_settings.save_api_model", has_providers),
		"deleteApiModel": _action("provider_settings.delete_api_model", has_providers),
		"discoverModels": _action("provider_settings.discover_models", has_providers),
		"selectModel": _action("provider_settings.select_model", has_providers),
		"checkConnection": _action("provider_settings.check_connection", has_providers, "PROVIDER_SETTINGS_PROVIDER_REQUIRED"),
	}


func _empty_data() -> Dictionary:
	return {
		"capabilityMode": "formal",
		"source": "runtime",
		"formalReady": false,
		"pageTitle": "模型设置",
		"selectedProviderId": "",
		"formalStatusLabel": "正式 Provider 查询未接入",
		"providers": [],
		"summary": {
			"availableProviderCount": 0,
			"enabledModelCount": 0,
		},
	}


func _action(intent: String, enabled: bool, disabled_reason := "") -> Dictionary:
	return AiTownUiViewModel.make_action(intent, enabled, disabled_reason)


func _idle_operation() -> Dictionary:
	return _operation("", "", "idle")


func _operation(request_id: String, intent: String, status: String) -> Dictionary:
	return {
		"requestId": request_id,
		"intent": intent,
		"status": status,
		"submittedAtMsec": Time.get_ticks_msec() if status == "loading" else 0,
		"completedAtMsec": 0,
		"message": "",
	}


func _next_request_id() -> String:
	_request_sequence += 1
	return AiTownUiViewModel.request_id("provider-settings", _request_sequence)


func _success(message := "") -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"message": message,
	}


func _failure(error_code: String, retryable: bool, message := "", errors: Variant = []) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"message": message,
		"errors": (errors as Array).duplicate(true) if errors is Array else [],
	}


func _dispatch_rejection(intent_id: String, error_code: String) -> Dictionary:
	var request_id := _next_request_id()
	var operation := _operation(request_id, intent_id, "rejected")
	operation["completedAtMsec"] = Time.get_ticks_msec()
	var result := _failure(error_code, false)
	_publish_result(operation, result, "rejected")
	operation_completed.emit(SCOPE, operation.duplicate(true))
	return {
		"ok": false,
		"accepted": true,
		"requestId": request_id,
		"errorCode": error_code,
		"retryable": false,
	}


func _required_canonical_id(payload: Dictionary, key: String) -> Dictionary:
	var value: Variant = payload.get(key)
	if (
		typeof(value) != TYPE_STRING
		or not _canonical_id_is_valid(value as String)
	):
		return {"ok": false}
	return {"ok": true, "value": value}


func _canonical_id_is_valid(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges()


func _is_dynamic_compatible_profile(
	provider_id: String,
	provider: Dictionary,
) -> bool:
	return (
		provider_id.begins_with(COMPATIBLE_PROFILE_PREFIX)
		and String(provider.get("connectionType", ""))
		== COMPATIBLE_PROFILE_TYPE
	)


func _compatible_display_name(endpoint: String) -> String:
	var remainder := endpoint.strip_edges()
	if remainder.begins_with("https://"):
		remainder = remainder.trim_prefix("https://")
	elif remainder.begins_with("http://"):
		remainder = remainder.trim_prefix("http://")
	var authority := remainder.split("/", false)[0]
	var host := authority
	if authority.begins_with("["):
		var bracket := authority.find("]")
		if bracket >= 0:
			host = authority.left(bracket + 1)
	elif authority.contains(":"):
		host = authority.get_slice(":", 0)
	if host.is_empty():
		return "兼容接口"
	var label := "兼容 · %s" % host
	return label.left(48)


func _compatible_display_name_is_valid(
	display_name: String,
	allow_empty: bool = false,
) -> bool:
	if display_name.is_empty():
		return allow_empty
	if display_name != display_name.strip_edges() or display_name.length() > 48:
		return false
	for character: String in display_name:
		var codepoint := character.unicode_at(0)
		if codepoint < 32 or codepoint == 127:
			return false
	return true


func _compatible_display_name_is_automatic(display_name: String) -> bool:
	return (
		display_name.is_empty()
		or display_name == "兼容接口"
		or display_name == "新建兼容连接"
		or display_name.begins_with("兼容接口 ")
		or display_name.begins_with("兼容 · ")
	)


func _restore_credential(
	provider_id: String,
	had_previous_key: bool,
	previous_key: String,
) -> Dictionary:
	var restored: Dictionary
	if had_previous_key:
		restored = (
			_credential_store.save_api_key(
				provider_id,
				previous_key,
			) as Dictionary
		)
		if bool(restored.get("ok", false)):
			_credential_keys[provider_id] = previous_key
	else:
		restored = (
				_credential_store.delete_api_key(provider_id) as Dictionary
		)
		if bool(restored.get("ok", false)):
			_credential_keys.erase(provider_id)
	if not bool(restored.get("ok", false)):
		return _failure("PROVIDER_SETTINGS_ROLLBACK_FAILED", true)
	return _success()


func _normalize_failure(result: Dictionary, fallback_code: String) -> Dictionary:
	var error_code := String(result.get("errorCode", fallback_code))
	var message := String(result.get("message", "")).strip_edges()
	if message.is_empty():
		message = _player_message_for_error_code(error_code)
	return _failure(
		error_code,
		bool(result.get("retryable", false)),
		message,
		result.get("errors", []),
	)


func _error_payload(
	code: String,
	retryable: bool,
	message: String,
	details: Variant = [],
) -> Dictionary:
	return {
		"kind": _error_kind_for_code(code, retryable),
		"code": code,
		"retryable": retryable,
		"message": message,
		"details": (details as Array).duplicate(true) if details is Array else [],
	}


func _error_kind_for_code(code: String, retryable: bool) -> String:
	match code:
		"PROVIDER_AUTH_FAILED":
			return "authentication"
		"PROVIDER_BILLING_FAILED":
			return "billing"
		"PROVIDER_RATE_LIMITED":
			return "rate_limit"
		"PROVIDER_TIMEOUT":
			return "timeout"
		"PROVIDER_CONNECTION_FAILED", "PROVIDER_NETWORK_UNAVAILABLE":
			return "network"
	return "transport" if retryable else "unavailable"


func _player_message_for_error_code(code: String) -> String:
	match code:
		"":
			return "尚未完成连接检查。"
		"PROVIDER_API_KEY_REQUIRED", "LLM_PROVIDER_CONFIGURATION_INVALID":
			return "请先在上方输入并保存 API Key，然后重试。"
		"PROVIDER_MODEL_SELECTION_REQUIRED":
			return "请先启用一个模型，然后再检查连接。"
		"PROVIDER_API_MODEL_REQUIRED":
			return "请先填写并保存接口实际使用的模型 ID。"
		"PROVIDER_API_MODEL_UNKNOWN":
			return "没有找到要删除的自定义模型。"
		"PROVIDER_API_MODEL_IN_USE":
			return "这个模型仍在被居民使用，请先重新分配居民模型。"
		"PROVIDER_MODEL_CATALOG_EMPTY":
			return "服务没有返回可用模型，请手动填写模型 ID。"
		"PROVIDER_MODEL_CATALOG_INVALID", "PROVIDER_MODEL_CATALOG_REQUEST_FAILED":
			return "暂时无法读取模型列表，请检查地址后重试，或手动填写模型 ID。"
		"PROVIDER_MODEL_CATALOG_UNSUPPORTED":
			return "当前服务需要手动填写模型或推理接入点 ID。"
		"PROVIDER_CONNECTION_IN_USE":
			return "这个连接仍在被居民使用，请先重新分配居民模型。"
		"PROVIDER_CONNECTION_DELETE_FORBIDDEN":
			return "内置连接不能删除。"
		"PROVIDER_DISABLED":
			return "当前 Provider 已停用。请先启用，再检查连接。"
		"PROVIDER_BASE_URL_INVALID":
			return "Base URL 必须以 http:// 或 https:// 开头。"
		"PROVIDER_INSECURE_HTTP_CONSENT_REQUIRED":
			return "这个 HTTP 地址尚未获得未加密传输授权，请返回设置后重新确认。"
		"PROVIDER_INSECURE_HTTP_CONSENT_INVALID":
			return "未加密传输授权无效，请返回设置后重新确认。"
		"PROVIDER_AUTH_FAILED":
			return "API Key 未通过认证。请重新输入并保存 Key，然后重试。"
		"PROVIDER_BILLING_FAILED":
			return "Provider 账户当前不可用。请检查账户额度或计费状态后重试。"
		"PROVIDER_RATE_LIMITED":
			return "Provider 请求过于频繁。请稍后再试。"
		"PROVIDER_TIMEOUT":
			return "连接 Provider 超时。请检查网络和 Base URL，然后重试。"
		"PROVIDER_CONNECTION_FAILED", "PROVIDER_NETWORK_UNAVAILABLE":
			return "无法连接 Provider。请检查网络和 Base URL，然后重试。"
		"PROVIDER_REQUEST_HOST_REQUIRED":
			return "当前运行环境无法发起连接检查。请重新启动游戏后重试。"
		"PROVIDER_HEALTH_CHECK_REQUIRED":
			return "配置已更新，请重新检查连接。"
		"LLM_MODEL_UNKNOWN":
			return "所选模型已不可用。请重新选择模型。"
	return "Provider 设置操作未完成。请检查当前配置后重试。"
