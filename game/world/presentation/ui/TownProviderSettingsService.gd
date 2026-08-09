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
const REQUIRED_PROVIDER_METHODS: Array[String] = [
	"configure",
	"get_health_snapshot",
	"list_available_models",
	"request_health_check",
]
const HOST_ROUTING_REQUIRED := "PROVIDER_SETTINGS_HOST_ROUTING_REQUIRED"
const TEST_NO_NETWORK_ENV := "AI_TOWN_PROVIDER_TEST_NO_NETWORK"
const CUSTOM_MODEL_PROVIDER_ID := "openai-compatible"
const CUSTOM_MODEL_CATALOG_ID := "custom"
const PROVIDER_DISPLAY_NAMES := {
	"deepseek": "DeepSeek",
	"kimi": "Kimi",
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
var _store: RefCounted = CONFIG_STORE.new()
var _credential_store: RefCounted = CREDENTIAL_STORE.new()
var _credential_keys: Dictionary = {}
var _stored_config: Dictionary = {
	"schemaVersion": 1,
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
var _health_configuration_generation := 0
var _dirty_health_providers: Dictionary = {}


func configure_store(path: String) -> Dictionary:
	var configured := _store.call("configure", path) as Dictionary
	if not bool(configured.get("ok", false)):
		return configured
	var credential_path := "%s.credentials.enc" % path.get_basename()
	var credential_configured := (
		_credential_store.call("configure", credential_path) as Dictionary
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
			if not has_saved_key
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
		_credential_store.call("api_key", provider_id) as Dictionary
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
		"provider_settings.delete_key":
			result = _delete_key(payload)
		"provider_settings.save_base_url":
			result = _save_base_url(payload)
		"provider_settings.save_api_model":
			result = _save_api_model(payload)
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
		var selected_models := _stored_config.get("selectedModelByProvider", {}) as Dictionary
		var selected_model_id := String(
			selected_models.get(provider_id, "")
		).strip_edges()
		var projected_source := source.duplicate(true)
		if not enabled:
			projected_source["status"] = "disabled"
			projected_source["errorCode"] = "PROVIDER_DISABLED"
			projected_source["retryable"] = false
		elif not has_saved_key:
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
			"displayName": String(PROVIDER_DISPLAY_NAMES.get(
				provider_id,
				source.get("label", provider_id),
			)),
			"enabled": enabled,
			"external": bool(source.get("external", false)),
			"key": {
				"saved": has_saved_key,
				"maskedValue": _masked_key(
					String(_credential_keys.get(provider_id, ""))
				),
				"status": "saved" if has_saved_key else "missing",
				"errorCode": "" if has_saved_key else "PROVIDER_API_KEY_REQUIRED",
			},
			"baseUrl": String(stored_provider.get("endpoint", "")),
			"apiModel": String(stored_provider.get("apiModel", "")),
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
		_selected_provider_id = available_ids[0] if not available_ids.is_empty() else (
			String(providers[0].get("providerId", "")) if not providers.is_empty() else ""
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
		_credential_store.call("save_api_key", provider_id, api_key) as Dictionary
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
	providers[provider_id] = provider
	candidate["providers"] = providers
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
		_credential_store.call("delete_api_key", provider_id) as Dictionary
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
	if not endpoint.is_empty() and not endpoint.begins_with("https://"):
		return _failure("PROVIDER_BASE_URL_INVALID", false)
	if (
		provider_id == CUSTOM_MODEL_PROVIDER_ID
		and not _chat_completions_url_is_valid(endpoint)
	):
		return _failure("PROVIDER_CHAT_COMPLETIONS_URL_REQUIRED", false)
	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var provider := (providers.get(provider_id, {}) as Dictionary).duplicate(true)
	if endpoint.is_empty():
		provider.erase("endpoint")
	else:
		provider["endpoint"] = endpoint
	providers[provider_id] = provider
	candidate["providers"] = providers
	return _persist_candidate_reconfigure_and_reload(
		candidate,
		"Provider 地址已更新。",
		provider_id,
	)


func _save_api_model(payload: Dictionary) -> Dictionary:
	var provider_result := _required_canonical_id(payload, "providerId")
	if not bool(provider_result.get("ok", false)):
		return _failure("PROVIDER_SETTINGS_PROVIDER_REQUIRED", false)
	var provider_id := String(provider_result.get("value", ""))
	if (
		provider_id != CUSTOM_MODEL_PROVIDER_ID
		or _provider_from_confirmed(provider_id).is_empty()
	):
		return _failure("PROVIDER_SETTINGS_PROVIDER_UNKNOWN", false)
	var api_model_value: Variant = payload.get("apiModel")
	if typeof(api_model_value) != TYPE_STRING:
		return _failure("PROVIDER_API_MODEL_INVALID", false)
	var api_model := api_model_value as String
	if not _api_model_is_valid(api_model):
		return _failure("PROVIDER_API_MODEL_INVALID", false)
	var candidate := _stored_config.duplicate(true)
	var providers := candidate.get("providers", {}) as Dictionary
	var provider := (providers.get(provider_id, {}) as Dictionary).duplicate(true)
	provider["apiModel"] = api_model
	provider["enabled"] = true
	providers[provider_id] = provider
	candidate["providers"] = providers
	var selected_models := candidate.get("selectedModelByProvider", {}) as Dictionary
	selected_models[provider_id] = CUSTOM_MODEL_CATALOG_ID
	candidate["selectedModelByProvider"] = selected_models
	candidate["selectedProviderId"] = provider_id
	return _persist_candidate_reconfigure_and_reload(
		candidate,
		"自定义模型名称已更新。",
		provider_id,
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
	var endpoint := String(stored_provider.get("endpoint", "")).strip_edges()
	if (
		provider_id == CUSTOM_MODEL_PROVIDER_ID
		and not _chat_completions_url_is_valid(endpoint)
	):
		return _failure("PROVIDER_CHAT_COMPLETIONS_URL_REQUIRED", false)
	if not bool(stored_provider.get("enabled", true)):
		return _failure("PROVIDER_DISABLED", false)
	if not _has_saved_key(provider_id):
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
		if (
			provider_id.is_empty()
			or model_id.is_empty()
			or not bool(provider_config.get("enabled", true))
			or not _has_saved_key(provider_id)
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
	var loaded := _store.call("load_config") as Dictionary
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
		_credential_store.call("load_keys") as Dictionary
	)
	if not bool(loaded_credentials.get("ok", false)):
		return loaded_credentials
	_credential_keys = (
		loaded_credentials.get("keys", {}) as Dictionary
	).duplicate(true)
	var migration_result := _migrate_plaintext_credentials()
	if not bool(migration_result.get("ok", false)):
		return migration_result
	_selected_provider_id = String(_stored_config.get("selectedProviderId", ""))
	return {"ok": true, "errorCode": "", "retryable": false}


func _persist_candidate_and_reconfigure(candidate: Dictionary) -> Dictionary:
	var previous := _stored_config.duplicate(true)
	var persisted := _store.call("save_config", candidate) as Dictionary
	if not bool(persisted.get("ok", false)):
		return persisted
	_stored_config = candidate.duplicate(true)
	var configured := _apply_provider_configuration()
	if bool(configured.get("ok", false)):
		return configured
	var rollback := _store.call("save_config", previous) as Dictionary
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
		if not bool(source.get("enabled", true)):
			continue
		var config: Dictionary = {}
		var api_key := String(_credential_keys.get(provider_id, "")).strip_edges()
		if not api_key.is_empty():
			config["api_key"] = api_key
		var endpoint := String(source.get("endpoint", "")).strip_edges()
		if not endpoint.is_empty():
			config["endpoint"] = endpoint
		var api_model := String(source.get("apiModel", "")).strip_edges()
		if not api_model.is_empty():
			config["api_model"] = api_model
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
			_credential_store.call(
				"save_api_key",
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
				_store.call("save_config", _stored_config) as Dictionary
			)
			if not bool(scrubbed.get("ok", false)):
				return scrubbed
			return saved
	if changed:
		_stored_config["providers"] = providers
		return _store.call("save_config", _stored_config) as Dictionary
	return _success()


func _has_saved_key(provider_id: String) -> bool:
	return not String(_credential_keys.get(provider_id, "")).strip_edges().is_empty()


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


func _api_model_is_valid(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges() or value.length() > 256:
		return false
	for character: String in value:
		var codepoint := character.unicode_at(0)
		if codepoint <= 32 or codepoint == 127:
			return false
	return true


func _chat_completions_url_is_valid(value: String) -> bool:
	var normalized := value.strip_edges().trim_suffix("/")
	return (
		normalized.begins_with("https://")
		and normalized.ends_with("/chat/completions")
	)


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
	var actions_value := _actions(data)
	return AiTownUiViewModel.envelope(
		SCOPE, status, _revision, data, actions_value, operation, error
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
		"saveApiModel": _action("provider_settings.save_api_model", has_providers),
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


func _restore_credential(
	provider_id: String,
	had_previous_key: bool,
	previous_key: String,
) -> Dictionary:
	var restored: Dictionary
	if had_previous_key:
		restored = (
			_credential_store.call(
				"save_api_key",
				provider_id,
				previous_key,
			) as Dictionary
		)
		if bool(restored.get("ok", false)):
			_credential_keys[provider_id] = previous_key
	else:
		restored = (
			_credential_store.call("delete_api_key", provider_id) as Dictionary
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
		"playerMessage": message,
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
		"PROVIDER_DISABLED":
			return "当前 Provider 已停用。请先启用，再检查连接。"
		"PROVIDER_BASE_URL_INVALID":
			return "Base URL 必须使用 https:// 地址。请修正并重新保存。"
		"PROVIDER_API_MODEL_INVALID":
			return "请输入有效的模型名称。"
		"PROVIDER_CHAT_COMPLETIONS_URL_REQUIRED":
			return "Base URL 需要填写完整接口，例如：https://api.siliconflow.cn/v1/chat/completions"
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
