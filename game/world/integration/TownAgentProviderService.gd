class_name TownAgentProviderService
extends RefCounted


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const CATALOG := preload("res://agent/model/ModelProviderCatalog.gd")
const ENDPOINT_SECURITY := preload(
	"res://common/ProviderEndpointSecurity.gd"
)
const CAPABILITY_MODES: Array[String] = ["development", "formal"]
const FAKE_PROVIDER_ID := "fake"
const MAX_SAFE_INTEGER := 9007199254740991
const HEALTH_PROBE_MAX_TOKENS := 256
const COMPATIBLE_PROFILE_TYPE := "openai-compatible-profile"
const PUBLIC_USAGE_FIELDS: Array[String] = [
	"prompt_tokens",
	"completion_tokens",
	"total_tokens",
]

var _catalog: RefCounted = CATALOG.new()
var _request_host: Node
var _capability_mode := "formal"
var _source := "runtime"
var _allow_fake := false
var _provider_configs: Dictionary = {}
var _providers_by_resident_id: Dictionary = {}
var _bindings_by_resident_id: Dictionary = {}
var _configured := false
var _configuration_generation := 0
var _health_request_sequence := 0
var _health_by_target: Dictionary = {}
var _pending_health_requests: Dictionary = {}
var _pending_model_catalog_providers: Array[RefCounted] = []


func configure(config_value: Variant, request_host_value: Variant = null) -> Dictionary:
	if not config_value is Dictionary:
		return _failure("PROVIDER_CONFIG_INVALID", false)
	if (
		request_host_value != null
		and (
			not request_host_value is Node
			or not is_instance_valid(request_host_value)
		)
	):
		return _failure("PROVIDER_REQUEST_HOST_INVALID", false)
	var config := config_value as Dictionary
	var request_host: Node = request_host_value as Node
	var mode_value: Variant = config.get("capabilityMode", "formal")
	if typeof(mode_value) != TYPE_STRING:
		return _failure("PROVIDER_CAPABILITY_MODE_INVALID", false)
	var mode := mode_value as String
	if not CAPABILITY_MODES.has(mode):
		return _failure("PROVIDER_CAPABILITY_MODE_INVALID", false)
	var configs_value: Variant = config.get("providerConfigs", {})
	if not configs_value is Dictionary:
		return _failure("PROVIDER_CONFIGS_INVALID", false)
	for config_key: Variant in (configs_value as Dictionary).keys():
		var provider_config_value: Variant = (
			configs_value as Dictionary
		).get(config_key)
		if (
			typeof(config_key) != TYPE_STRING
			or not _canonical_id_is_valid(config_key as String)
			or not provider_config_value is Dictionary
		):
			return _failure("PROVIDER_CONFIGS_INVALID", false)
		var provider_config := provider_config_value as Dictionary
		var consent_value: Variant = provider_config.get(
			"allow_insecure_http",
			false,
		)
		if typeof(consent_value) != TYPE_BOOL:
			return _failure("PROVIDER_CONFIGS_INVALID", false)
		var endpoint := String(provider_config.get("endpoint", "")).strip_edges()
		if (
			not endpoint.is_empty()
			and not ENDPOINT_SECURITY.scheme_is_supported(endpoint)
		):
			return _failure("PROVIDER_CONFIG_INVALID", false)
		if (
			ENDPOINT_SECURITY.requires_insecure_http_consent(endpoint)
			and not bool(consent_value)
		):
			return _failure(
				"PROVIDER_INSECURE_HTTP_CONSENT_REQUIRED",
				false,
			)
	var source_value: Variant = config.get("source", "runtime")
	if (
		typeof(source_value) != TYPE_STRING
		or not _canonical_id_is_valid(source_value as String)
	):
		return _failure("PROVIDER_SOURCE_INVALID", false)
	var allow_fake_value: Variant = config.get("allowFake", false)
	if typeof(allow_fake_value) != TYPE_BOOL:
		return _failure("PROVIDER_ALLOW_FAKE_INVALID", false)
	var source := source_value as String
	var allow_fake := (allow_fake_value as bool) and mode == "development"
	var provider_configs := (configs_value as Dictionary).duplicate(true)
	var catalog_result := _rebuild_catalog_for_configs(provider_configs)
	if not bool(catalog_result.get("ok", false)):
		return catalog_result
	if (
		_configured
		and _capability_mode == mode
		and _source == source
		and _allow_fake == allow_fake
		and _provider_configs == provider_configs
		and _request_host == request_host
	):
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"capabilityMode": _capability_mode,
			"source": _source,
			"formalReady": _capability_mode == "formal",
			"changed": false,
		}
	var clear_all_health := (
		not _configured
		or _capability_mode != mode
		or _source != source
		or _allow_fake != allow_fake
		or _request_host != request_host
	)
	var changed_provider_ids := _changed_provider_ids(
		_provider_configs,
		provider_configs,
	)
	_cancel_pending_health_checks()
	_capability_mode = mode
	_source = source
	_allow_fake = allow_fake
	_provider_configs = provider_configs
	_request_host = request_host
	_providers_by_resident_id.clear()
	_bindings_by_resident_id.clear()
	if clear_all_health:
		_health_by_target.clear()
	else:
		_invalidate_provider_health_entries(changed_provider_ids)
	_configuration_generation += 1
	_configured = true
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"capabilityMode": _capability_mode,
		"source": _source,
		"formalReady": _capability_mode == "formal",
		"changed": true,
	}


func get_health_snapshot() -> Dictionary:
	var providers: Array[Dictionary] = []
	for descriptor_value: Variant in _catalog.list_providers() as Array:
		var descriptor := descriptor_value as Dictionary
		var provider_id := String(descriptor.get("id", ""))
		if provider_id == FAKE_PROVIDER_ID and not _allow_fake:
			continue
		var health := _provider_health(provider_id)
		providers.append({
			"providerId": provider_id,
			"label": String(descriptor.get("label", provider_id)),
			"external": bool(descriptor.get("external", false)),
			"status": String(health.get("status", "unavailable")),
			"errorCode": String(health.get("errorCode", "")),
			"retryable": bool(health.get("retryable", false)),
			"checkedAtMsec": int(health.get("checkedAtMsec", 0)),
			"authRequired": bool(descriptor.get("auth_required", true)),
			"defaultBaseUrl": String(descriptor.get("default_endpoint", "")),
			"customModels": bool(descriptor.get("custom_models", false)),
			"customGroup": bool(descriptor.get("custom_group", false)),
			"modelCatalogSupported": bool(
				descriptor.get("model_catalog_supported", false)
			),
		})
	return {
		"ok": true,
		"status": "ready",
		"capabilityMode": _capability_mode,
		"source": _source,
		"formalReady": _capability_mode == "formal",
		"defaultProviderId": _catalog.default_provider_id(),
		"providers": providers,
	}


func get_default_provider_id() -> String:
	return _catalog.default_provider_id()


func list_available_models() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var known_model_keys: Dictionary = {}
	for model_value: Variant in _catalog.list_models() as Array:
		if not model_value is Dictionary:
			continue
		var model := model_value as Dictionary
		var provider_id := _public_string(model.get("provider_id"))
		var model_id := _public_string(model.get("id"))
		if provider_id.is_empty() or model_id.is_empty():
			continue
		if provider_id == FAKE_PROVIDER_ID:
			continue
		if _provider_uses_custom_models(provider_id) and model_id == "custom":
			continue
		var model_key := "%s/%s" % [provider_id, model_id]
		if known_model_keys.has(model_key):
			continue
		known_model_keys[model_key] = true
		result.append(_model_health_projection(model))
	for provider_id_value: Variant in _provider_configs.keys():
		var provider_id := String(provider_id_value)
		if not _provider_uses_custom_models(provider_id):
			continue
		for model_id: String in _configured_api_models(provider_id):
			var model_key := "%s/%s" % [provider_id, model_id]
			if known_model_keys.has(model_key):
				continue
			known_model_keys[model_key] = true
			result.append(_model_health_projection(
				_dynamic_model_descriptor(provider_id, model_id),
			))
	if _allow_fake:
		result.append({
			"id": "fake",
			"modelId": "fake",
			"label": "Fake（开发内测）",
			"provider_id": FAKE_PROVIDER_ID,
			"providerId": FAKE_PROVIDER_ID,
			"available": true,
			"errorCode": "",
			"retryable": false,
			"developmentOnly": true,
		})
	return result


func _model_health_projection(model: Dictionary) -> Dictionary:
	var provider_id := _public_string(model.get("provider_id"))
	var model_id := _public_string(model.get("id"))
	var health := _target_health(
		provider_id,
		model_id,
	)
	var projection := {
		"id": model_id,
		"modelId": model_id,
		"label": _public_string(model.get("label"), model_id),
		"provider_id": provider_id,
		"providerId": provider_id,
		"input_modalities": (
			(model.get("input_modalities", []) as Array).duplicate()
			if model.get("input_modalities", []) is Array
			else []
		),
		"inputModalities": (
			(model.get("input_modalities", []) as Array).duplicate()
			if model.get("input_modalities", []) is Array
			else []
		),
		"available": String(health.get("status", "")) == "available",
		"errorCode": String(health.get("errorCode", "")),
		"retryable": bool(health.get("retryable", false)),
		"healthStatus": String(health.get("status", "unavailable")),
		"custom": bool(model.get("custom", false)),
	}
	for boolean_key in ["deprecated", "default_for_provider"]:
		var boolean_value: Variant = model.get(boolean_key)
		if typeof(boolean_value) == TYPE_BOOL:
			projection[boolean_key] = boolean_value as bool
	return projection


func validate_resident_bindings(bindings_value: Variant) -> Dictionary:
	if not bindings_value is Array:
		return _failure("SESSION_LLM_BINDINGS_INVALID", false)
	var bindings := bindings_value as Array
	var seen_ids: Dictionary = {}
	var errors: Array[Dictionary] = []
	for index in range(bindings.size()):
		var value: Variant = bindings[index]
		if not value is Dictionary:
			errors.append(_detail(index, "SESSION_LLM_BINDING_INVALID"))
			continue
		var binding := value as Dictionary
		var resident_id_value: Variant = binding.get("residentId")
		var llm_value: Variant = binding.get("llmBinding")
		if (
			typeof(resident_id_value) != TYPE_STRING
			or not _canonical_id_is_valid(resident_id_value as String)
			or seen_ids.has(resident_id_value)
		):
			errors.append(_detail(index, "SESSION_RESIDENT_ID_INVALID"))
			continue
		var resident_id := resident_id_value as String
		seen_ids[resident_id] = true
		if not llm_value is Dictionary:
			errors.append(_detail(index, "SESSION_LLM_BINDING_INVALID"))
			continue
		var llm := llm_value as Dictionary
		var binding_result := _validate_model_binding(llm)
		if not bool(binding_result.get("ok", false)):
			errors.append(_detail(
				index,
				String(binding_result.get("errorCode", "LLM_MODEL_UNAVAILABLE")),
				{
					"residentId": resident_id,
					"providerId": String(llm.get("providerId", "")),
					"modelId": String(llm.get("modelId", "")),
				},
			))
	if not errors.is_empty():
		return _failure("SESSION_LLM_BINDINGS_INVALID", false, errors)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentCount": bindings.size(),
		"capabilityMode": _capability_mode,
		"formalReady": _capability_mode == "formal",
	}


func check_entry_availability(
	bindings: Variant,
	on_complete_value: Variant = Callable(),
) -> Dictionary:
	if typeof(on_complete_value) != TYPE_CALLABLE:
		return _failure("PROVIDER_CALLBACK_INVALID", false)
	var on_complete := on_complete_value as Callable
	var validation := validate_resident_bindings(bindings)
	var result: Dictionary
	if bool(validation.get("ok", false)):
		result = {
			"ok": true,
			"accepted": true,
			"status": "available",
			"errorCode": "",
			"retryable": false,
			"capabilityMode": _capability_mode,
			"source": _source,
			"formalReady": _capability_mode == "formal",
		}
	else:
		result = validation.duplicate(true)
		result["accepted"] = false
		result["status"] = "unavailable"
	if on_complete.is_valid():
		on_complete.call(result.duplicate(true))
	return result


func request_model_catalog(
	provider_id_value: Variant,
	on_complete_value: Variant = Callable(),
) -> Dictionary:
	if typeof(on_complete_value) != TYPE_CALLABLE:
		return _failure("PROVIDER_CALLBACK_INVALID", false)
	var on_complete := on_complete_value as Callable
	if (
		typeof(provider_id_value) != TYPE_STRING
		or not _canonical_id_is_valid(provider_id_value as String)
	):
		return _failure("PROVIDER_SETTINGS_PROVIDER_REQUIRED", false)
	if not _configured:
		return _failure("PROVIDER_SERVICE_NOT_CONFIGURED", false)
	var provider_id := provider_id_value as String
	if not _provider_uses_custom_models(provider_id):
		return _failure("PROVIDER_MODEL_CATALOG_UNSUPPORTED", false)
	var creation := _catalog.create_provider(
		provider_id,
		_request_host,
		_provider_config(provider_id, ""),
	) as Dictionary
	if not bool(creation.get("ok", false)):
		return _failure("LLM_MODEL_PROVIDER_CREATION_FAILED", false)
	var provider: Object = creation.get("provider")
	if provider == null or not provider.has_method("request_model_catalog"):
		return _failure("PROVIDER_MODEL_CATALOG_UNSUPPORTED", false)
	var retained_provider := provider as RefCounted
	_pending_model_catalog_providers.append(retained_provider)
	var complete_and_release := func(result: Dictionary) -> void:
		_pending_model_catalog_providers.erase(retained_provider)
		on_complete.call(result)
	var started_value: Variant = provider.call(
		"request_model_catalog",
		complete_and_release,
	)
	if not started_value is Dictionary:
		_pending_model_catalog_providers.erase(retained_provider)
		return _failure("PROVIDER_MODEL_CATALOG_REQUEST_FAILED", true)
	var started := started_value as Dictionary
	if not bool(started.get("accepted", false)):
		_pending_model_catalog_providers.erase(retained_provider)
	return started


func request_health_check(
	targets_value: Variant,
	on_complete_value: Variant = Callable(),
) -> Dictionary:
	if typeof(on_complete_value) != TYPE_CALLABLE:
		return _failure("PROVIDER_CALLBACK_INVALID", false)
	var on_complete := on_complete_value as Callable
	if not _configured:
		var unconfigured := _failure("PROVIDER_SERVICE_NOT_CONFIGURED", false)
		unconfigured["accepted"] = false
		unconfigured["status"] = "unavailable"
		if on_complete.is_valid():
			on_complete.call(unconfigured.duplicate(true))
		return unconfigured
	if not targets_value is Array:
		var invalid_targets := _failure("PROVIDER_HEALTH_TARGETS_INVALID", false)
		invalid_targets["accepted"] = false
		invalid_targets["status"] = "unavailable"
		if on_complete.is_valid():
			on_complete.call(invalid_targets.duplicate(true))
		return invalid_targets
	var normalized := _normalize_health_targets(targets_value as Array)
	if normalized.get("ok") != true:
		var rejected := normalized.duplicate(true)
		rejected["accepted"] = false
		rejected["status"] = "unavailable"
		if on_complete.is_valid():
			on_complete.call(rejected.duplicate(true))
		return rejected
	_cancel_pending_health_checks()
	_health_request_sequence += 1
	var request_id := "provider-health-%06d" % _health_request_sequence
	var request := {
		"requestId": request_id,
		"configurationGeneration": _configuration_generation,
		"targets": normalized.get("targets", []).duplicate(true),
		"results": {},
		"onComplete": on_complete,
	}
	_pending_health_requests[request_id] = request
	var prepared: Array[Dictionary] = []
	for target_value: Variant in request.get("targets", []) as Array:
		var target := target_value as Dictionary
		var provider_id := String(target.get("providerId", ""))
		var model_id := String(target.get("modelId", ""))
		var target_key := _target_key(provider_id, model_id)
		_health_by_target[target_key] = {
			"providerId": provider_id,
			"modelId": model_id,
			"status": "checking",
			"errorCode": "",
			"retryable": false,
			"checkedAtMsec": 0,
			"requestId": request_id,
		}
		if provider_id == FAKE_PROVIDER_ID:
			prepared.append({"target": target, "provider": null})
			continue
		var creation := _catalog_create_model(
			provider_id,
			model_id,
			_request_host,
			_provider_config(provider_id, model_id),
		)
		if not bool(creation.get("ok", false)):
			prepared.append({
				"target": target,
				"failure": _health_failure(
					"unavailable",
					"LLM_MODEL_PROVIDER_CREATION_FAILED",
					false,
				),
			})
			continue
		var provider: Object = creation.get("provider")
		if provider == null or not provider.has_method("request_json"):
			prepared.append({
				"target": target,
				"failure": _health_failure(
					"unavailable",
					"PROVIDER_HEALTH_REQUEST_UNSUPPORTED",
					false,
				),
			})
			continue
		if not provider.has_method("validate_configuration"):
			prepared.append({
				"target": target,
				"failure": _health_failure(
					"unavailable",
					"LLM_PROVIDER_CONFIGURATION_INVALID",
					false,
				),
			})
			continue
		var validation_value: Variant = provider.validate_configuration()
		if not validation_value is Array:
			prepared.append({
				"target": target,
				"failure": _health_failure(
					"unavailable",
					"LLM_PROVIDER_CONFIGURATION_INVALID",
					false,
				),
			})
			continue
		var configuration_errors := validation_value as Array
		if not configuration_errors.is_empty():
			prepared.append({
				"target": target,
				"failure": _health_failure(
					"unavailable",
					"LLM_PROVIDER_CONFIGURATION_INVALID",
					false,
				),
			})
			continue
		prepared.append({"target": target, "provider": provider})

	for item in prepared:
		var target := item.get("target", {}) as Dictionary
		if item.has("failure"):
			_complete_health_target(
				request_id,
				target,
				item.get("failure", {}) as Dictionary,
			)
			continue
		var provider: Object = item.get("provider")
		if provider == null:
			_complete_health_target(
				request_id,
				target,
				_health_success(),
			)
			continue
		provider.request_json(_health_probe_request(), Callable(
			self,
			"_on_health_probe_completed",
		).bind(request_id, target.duplicate(true), provider))
	return {
		"ok": true,
		"accepted": true,
		"status": "checking",
		"errorCode": "",
		"retryable": false,
		"requestId": request_id,
		"targetCount": (normalized.get("targets", []) as Array).size(),
	}


func create_provider_for_resident(binding_value: Variant) -> Dictionary:
	if not binding_value is Dictionary:
		return _failure("SESSION_LLM_BINDING_INVALID", false)
	var binding := binding_value as Dictionary
	var resident_id_value: Variant = binding.get("residentId")
	if (
		typeof(resident_id_value) != TYPE_STRING
		or not _canonical_id_is_valid(resident_id_value as String)
	):
		return _failure("SESSION_RESIDENT_ID_INVALID", false)
	var resident_id := resident_id_value as String
	var llm_value: Variant = binding.get("llmBinding")
	if not llm_value is Dictionary:
		return _failure("SESSION_LLM_BINDING_INVALID", false)
	var llm := llm_value as Dictionary
	var validation := _validate_model_binding(llm)
	if not bool(validation.get("ok", false)):
		return validation
	var provider_id := String(llm.get("providerId", ""))
	var model_id := String(llm.get("modelId", ""))
	var canonical_binding := {
		"providerId": provider_id,
		"modelId": model_id,
	}
	if _providers_by_resident_id.has(resident_id):
		var cached_binding_value: Variant = _bindings_by_resident_id.get(resident_id)
		if cached_binding_value is Dictionary and cached_binding_value == canonical_binding:
			return {
				"ok": true,
				"provider": _providers_by_resident_id[resident_id],
				"providerId": provider_id,
				"modelId": model_id,
				"errorCode": "",
				"retryable": false,
			}
	var provider_config := _provider_config(provider_id, model_id)
	var creation: Dictionary
	if provider_id == FAKE_PROVIDER_ID:
		creation = _catalog.create_provider(provider_id,
			_request_host,
			provider_config,) as Dictionary
	else:
		creation = _catalog_create_model(
			provider_id,
			model_id,
			_request_host,
			provider_config,
		)
	if not bool(creation.get("ok", false)):
		return _failure("LLM_MODEL_PROVIDER_CREATION_FAILED", false, [{
			"residentId": resident_id,
			"providerId": provider_id,
			"modelId": model_id,
		}])
	var provider: Object = creation.get("provider")
	if provider == null or not provider.has_method("validate_configuration"):
		return _failure("LLM_MODEL_PROVIDER_CREATION_FAILED", false)
	var validation_value: Variant = provider.validate_configuration()
	if not validation_value is Array:
		return _failure("LLM_PROVIDER_CONFIGURATION_INVALID", false)
	var configuration_errors := validation_value as Array
	if not configuration_errors.is_empty():
		return _failure("LLM_PROVIDER_CONFIGURATION_INVALID", false, [{
			"residentId": resident_id,
			"providerId": provider_id,
			"modelId": model_id,
		}])
	_providers_by_resident_id[resident_id] = provider
	_bindings_by_resident_id[resident_id] = canonical_binding
	return {
		"ok": true,
		"provider": provider,
		"providerId": provider_id,
		"modelId": model_id,
		"errorCode": "",
		"retryable": false,
	}


func resident_ids_using_model(provider_id: String, model_id: String) -> Array[String]:
	var result: Array[String] = []
	for resident_id_value: Variant in _bindings_by_resident_id.keys():
		var binding_value: Variant = _bindings_by_resident_id.get(resident_id_value)
		if not binding_value is Dictionary:
			continue
		var binding := binding_value as Dictionary
		if (
			String(binding.get("providerId", "")) == provider_id
			and String(binding.get("modelId", "")) == model_id
		):
			result.append(String(resident_id_value))
	result.sort()
	return result


func get_latest_diagnostic(resident_id_value: Variant) -> Dictionary:
	if (
		typeof(resident_id_value) != TYPE_STRING
		or not _canonical_id_is_valid(resident_id_value as String)
	):
		return {}
	var resident_id := resident_id_value as String
	var provider: Object = _providers_by_resident_id.get(resident_id)
	if provider == null or not provider.has_method("get_diagnostics"):
		return {}
	var diagnostics_value: Variant = provider.get_diagnostics()
	if not diagnostics_value is Array:
		return {}
	var diagnostics := diagnostics_value as Array
	if diagnostics.is_empty() or not diagnostics.back() is Dictionary:
		return {}
	return _public_diagnostic(diagnostics.back() as Dictionary)


func _public_diagnostic(source: Dictionary) -> Dictionary:
	# Provider implementations may retain request/response bodies for their own
	# debug tools. The production World/Gateway boundary must never propagate
	# prompts, image data URLs, raw responses, parsed decisions, or credentials.
	var result: Dictionary = {}
	for key in [
		"provider",
		"model",
		"error_type",
		"finish_reason",
		"provider_error_code",
	]:
		var text := _public_string(source.get(key))
		if not text.is_empty():
			result[key] = text
	for key in ["status_code", "elapsed_ms"]:
		var number := _public_nonnegative_integer(source.get(key))
		if number >= 0:
			result[key] = number
	var request_value: Variant = source.get("request")
	if request_value is Dictionary:
		var request_url := _public_request_url(request_value as Dictionary)
		if not request_url.is_empty():
			result["request_url"] = request_url
	for key in [
		"content_present",
		"reasoning_present",
		"thinking_block_removed",
		"json_repaired",
	]:
		var flag_value: Variant = source.get(key)
		if typeof(flag_value) == TYPE_BOOL:
			result[key] = flag_value as bool
	for key in ["content_length", "reasoning_length", "parse_content_length"]:
		var length := _public_nonnegative_integer(source.get(key))
		if length >= 0:
			result[key] = length
	var retryable_value: Variant = source.get("retryable")
	if typeof(retryable_value) == TYPE_BOOL:
		result["retryable"] = retryable_value as bool
	var usage_value: Variant = source.get("usage")
	if usage_value is Dictionary:
		var usage: Dictionary = {}
		for key in PUBLIC_USAGE_FIELDS:
			var count := _public_nonnegative_integer((usage_value as Dictionary).get(key))
			if count >= 0:
				usage[key] = count
		if not usage.is_empty():
			result["usage"] = usage
	return result


func capability_snapshot() -> Dictionary:
	return {
		"capabilityMode": _capability_mode,
		"source": _source,
		"formalReady": _capability_mode == "formal",
		"allowFake": _allow_fake,
	}


func _validate_model_binding(llm: Dictionary) -> Dictionary:
	var mode_value: Variant = llm.get("mode")
	if typeof(mode_value) != TYPE_STRING or mode_value != "model":
		return _failure("SESSION_LLM_BINDING_MODE_INVALID", false)
	var provider_value: Variant = llm.get("providerId")
	var model_value: Variant = llm.get("modelId")
	if (
		typeof(provider_value) != TYPE_STRING
		or not _canonical_id_is_valid(provider_value as String)
	):
		return _failure("SESSION_LLM_PROVIDER_REQUIRED", false)
	if (
		typeof(model_value) != TYPE_STRING
		or not _canonical_id_is_valid(model_value as String)
	):
		return _failure("SESSION_LLM_MODEL_REQUIRED", false)
	var provider_id := provider_value as String
	var model_id := model_value as String
	if provider_id == FAKE_PROVIDER_ID:
		if not _allow_fake or _capability_mode != "development":
			return _failure("FAKE_PROVIDER_FORBIDDEN", false)
		return {"ok": true, "errorCode": "", "retryable": false}
	var descriptor := _catalog_model_descriptor(provider_id, model_id)
	if descriptor.is_empty():
		return _failure("LLM_MODEL_UNKNOWN", false)
	if String(descriptor.get("provider_id", "")) != provider_id:
		return _failure("LLM_MODEL_PROVIDER_MISMATCH", false)
	var health := _target_health(provider_id, model_id)
	if String(health.get("status", "")) != "available":
		return _failure(
			String(health.get("errorCode", "LLM_MODEL_UNAVAILABLE")),
			bool(health.get("retryable", false)),
		)
	return {"ok": true, "errorCode": "", "retryable": false}


func _provider_health(provider_id: String) -> Dictionary:
	var descriptor := _catalog.descriptor(provider_id) as Dictionary
	if descriptor.is_empty():
		return {"status": "unavailable", "errorCode": "LLM_PROVIDER_UNKNOWN", "retryable": false}
	if provider_id == FAKE_PROVIDER_ID:
		return (
			{"status": "available", "errorCode": "", "retryable": false}
			if _allow_fake
			else {"status": "disabled", "errorCode": "FAKE_PROVIDER_FORBIDDEN", "retryable": false}
		)
	if bool(descriptor.get("external", false)) and (
		_request_host == null
		or not is_instance_valid(_request_host)
	):
		return {"status": "unavailable", "errorCode": "PROVIDER_REQUEST_HOST_REQUIRED", "retryable": false}
	var checked: Array[Dictionary] = []
	for value: Variant in _health_by_target.values():
		if not value is Dictionary:
			continue
		var health := value as Dictionary
		if String(health.get("providerId", "")) == provider_id:
			checked.append(health)
	if not checked.is_empty():
		for health in checked:
			if String(health.get("status", "")) == "checking":
				return health.duplicate(true)
		for health in checked:
			if String(health.get("status", "")) != "available":
				return health.duplicate(true)
		var latest := checked[0]
		for health in checked:
			if int(health.get("checkedAtMsec", 0)) > int(latest.get("checkedAtMsec", 0)):
				latest = health
		return latest.duplicate(true)
	var creation := _catalog.create_provider(provider_id,
		_request_host,
		_provider_config(provider_id, ""),) as Dictionary
	if not bool(creation.get("ok", false)):
		return {"status": "unavailable", "errorCode": "LLM_MODEL_PROVIDER_CREATION_FAILED", "retryable": false}
	var provider: Object = creation.get("provider")
	if provider == null or not provider.has_method("validate_configuration"):
		return {"status": "unavailable", "errorCode": "LLM_MODEL_PROVIDER_CREATION_FAILED", "retryable": false}
	var validation_value: Variant = provider.validate_configuration()
	if not validation_value is Array:
		return {"status": "unavailable", "errorCode": "LLM_PROVIDER_CONFIGURATION_INVALID", "retryable": false}
	var configuration_errors := validation_value as Array
	if not configuration_errors.is_empty():
		return {"status": "unavailable", "errorCode": "LLM_PROVIDER_CONFIGURATION_INVALID", "retryable": false}
	return {
		"status": "unchecked",
		"errorCode": "PROVIDER_HEALTH_CHECK_REQUIRED",
		"retryable": false,
		"checkedAtMsec": 0,
	}


func _target_health(provider_id: String, model_id: String) -> Dictionary:
	if provider_id == FAKE_PROVIDER_ID:
		return _provider_health(provider_id)
	var key := _target_key(provider_id, model_id)
	if _health_by_target.has(key):
		return (_health_by_target[key] as Dictionary).duplicate(true)
	var descriptor := _catalog_model_descriptor(provider_id, model_id)
	if descriptor.is_empty():
		return _health_failure("unavailable", "LLM_MODEL_UNKNOWN", false)
	if String(descriptor.get("provider_id", "")) != provider_id:
		return _health_failure("unavailable", "LLM_MODEL_PROVIDER_MISMATCH", false)
	var provider_health := _provider_health(provider_id)
	if String(provider_health.get("status", "")) != "unchecked":
		return provider_health
	return {
		"providerId": provider_id,
		"modelId": model_id,
		"status": "unchecked",
		"errorCode": "PROVIDER_HEALTH_CHECK_REQUIRED",
		"retryable": false,
		"checkedAtMsec": 0,
	}


func _normalize_health_targets(values: Array) -> Dictionary:
	var targets: Array[Dictionary] = []
	var keys: Array[String] = []
	for index in range(values.size()):
		var value: Variant = values[index]
		if not value is Dictionary:
			return _failure("PROVIDER_HEALTH_TARGETS_INVALID", false, [
				_detail(index, "SESSION_LLM_BINDING_INVALID"),
			])
		var source := value as Dictionary
		var llm := (
			source.get("llmBinding", {}) as Dictionary
			if source.get("llmBinding") is Dictionary
			else source
		)
		var mode_value: Variant = llm.get("mode", "model")
		if typeof(mode_value) != TYPE_STRING or mode_value != "model":
			return _failure("PROVIDER_HEALTH_TARGETS_INVALID", false, [
				_detail(index, "SESSION_LLM_BINDING_MODE_INVALID"),
			])
		var provider_value: Variant = llm.get("providerId")
		var model_value: Variant = llm.get("modelId")
		if (
			typeof(provider_value) != TYPE_STRING
			or typeof(model_value) != TYPE_STRING
			or not _canonical_id_is_valid(provider_value as String)
			or not _canonical_id_is_valid(model_value as String)
		):
			return _failure("PROVIDER_HEALTH_TARGETS_INVALID", false, [
				_detail(index, "PROVIDER_HEALTH_TARGET_INVALID"),
			])
		var provider_id := provider_value as String
		var model_id := model_value as String
		if provider_id == FAKE_PROVIDER_ID:
			if not _allow_fake or _capability_mode != "development":
				return _failure("FAKE_PROVIDER_FORBIDDEN", false)
		else:
			var descriptor := _catalog_model_descriptor(provider_id, model_id)
			if descriptor.is_empty():
				return _failure("LLM_MODEL_UNKNOWN", false)
			if String(descriptor.get("provider_id", "")) != provider_id:
				return _failure("LLM_MODEL_PROVIDER_MISMATCH", false)
		var key := _target_key(provider_id, model_id)
		if keys.has(key):
			continue
		keys.append(key)
		targets.append({"providerId": provider_id, "modelId": model_id})
	if targets.is_empty():
		return _failure("PROVIDER_HEALTH_TARGETS_REQUIRED", false)
	return {"ok": true, "errorCode": "", "retryable": false, "targets": targets}


func _health_probe_request() -> Dictionary:
	return {
		"messages": [
			{
				"role": "system",
				"content": "Return only a json object. Do not include markdown.",
			},
			{
				"role": "user",
				"content": "Return exactly {\"ok\":true}.",
			},
		],
		"max_tokens": HEALTH_PROBE_MAX_TOKENS,
	}


func _on_health_probe_completed(
	result: Variant,
	request_id: String,
	target: Dictionary,
	provider: Object,
) -> void:
	if not _pending_health_requests.has(request_id):
		return
	var health := _health_success()
	if not result is Dictionary or (result as Dictionary).get("ok") != true:
		health = _health_from_provider_diagnostic(provider)
	_complete_health_target(request_id, target, health)


func _complete_health_target(
	request_id: String,
	target: Dictionary,
	health: Dictionary,
) -> void:
	if not _pending_health_requests.has(request_id):
		return
	var request := _pending_health_requests[request_id] as Dictionary
	if int(request.get("configurationGeneration", -1)) != _configuration_generation:
		return
	var provider_id := String(target.get("providerId", ""))
	var model_id := String(target.get("modelId", ""))
	var key := _target_key(provider_id, model_id)
	var current := _health_by_target.get(key, {}) as Dictionary
	if String(current.get("requestId", "")) != request_id:
		return
	var results := request.get("results", {}) as Dictionary
	if results.has(key):
		return
	var projection := health.duplicate(true)
	projection["providerId"] = provider_id
	projection["modelId"] = model_id
	projection["checkedAtMsec"] = Time.get_ticks_msec()
	projection["requestId"] = request_id
	_health_by_target[key] = projection
	results[key] = projection.duplicate(true)
	request["results"] = results
	_pending_health_requests[request_id] = request
	if results.size() < (request.get("targets", []) as Array).size():
		return
	_finish_health_request(request_id)


func _finish_health_request(request_id: String) -> void:
	if not _pending_health_requests.has(request_id):
		return
	var request := _pending_health_requests[request_id] as Dictionary
	_pending_health_requests.erase(request_id)
	var target_results: Array[Dictionary] = []
	var all_available := true
	var first_error_code := ""
	var retryable := false
	for target_value: Variant in request.get("targets", []) as Array:
		var target := target_value as Dictionary
		var key := _target_key(
			String(target.get("providerId", "")),
			String(target.get("modelId", "")),
		)
		var health := (
			(request.get("results", {}) as Dictionary).get(key, {}) as Dictionary
		).duplicate(true)
		health.erase("requestId")
		target_results.append(health)
		if String(health.get("status", "")) != "available":
			all_available = false
			if first_error_code.is_empty():
				first_error_code = String(
					health.get("errorCode", "PROVIDER_HEALTH_UNAVAILABLE"),
				)
			retryable = retryable or bool(health.get("retryable", false))
	var result := {
		"ok": all_available,
		"accepted": true,
		"status": "available" if all_available else "unavailable",
		"errorCode": "" if all_available else first_error_code,
		"retryable": retryable,
		"requestId": request_id,
		"targets": target_results,
	}
	var on_complete := request.get("onComplete") as Callable
	if on_complete.is_valid():
		on_complete.call(result.duplicate(true))


func _cancel_pending_health_checks() -> void:
	if _pending_health_requests.is_empty():
		return
	var pending := _pending_health_requests.duplicate()
	_pending_health_requests.clear()
	for request_value: Variant in pending.values():
		var request := request_value as Dictionary
		var request_id := String(request.get("requestId", ""))
		for target_value: Variant in request.get("targets", []) as Array:
			if not target_value is Dictionary:
				continue
			var target := target_value as Dictionary
			var key := _target_key(
				String(target.get("providerId", "")),
				String(target.get("modelId", "")),
			)
			var current_value: Variant = _health_by_target.get(key)
			if (
				current_value is Dictionary
				and String((current_value as Dictionary).get("requestId", "")) == request_id
			):
				_health_by_target.erase(key)
		var on_complete := request.get("onComplete") as Callable
		if on_complete.is_valid():
			on_complete.call({
				"ok": false,
				"accepted": true,
				"status": "stale",
				"errorCode": "PROVIDER_HEALTH_CHECK_STALE",
				"retryable": false,
				"requestId": request_id,
				"targets": [],
			})


func _health_from_provider_diagnostic(provider: Object) -> Dictionary:
	var diagnostic := {}
	if provider != null and provider.has_method("get_diagnostics"):
		var diagnostics_value: Variant = provider.get_diagnostics()
		if diagnostics_value is Array:
			var diagnostics := diagnostics_value as Array
			if not diagnostics.is_empty() and diagnostics.back() is Dictionary:
				diagnostic = diagnostics.back() as Dictionary
	var error_type := _public_string(diagnostic.get("error_type"))
	var retryable_value: Variant = diagnostic.get("retryable")
	var retryable := (
		retryable_value as bool
		if typeof(retryable_value) == TYPE_BOOL
		else false
	)
	match error_type:
		"authentication":
			return _health_failure("auth_failed", "PROVIDER_AUTH_FAILED", false)
		"billing":
			return _health_failure("billing_failed", "PROVIDER_BILLING_FAILED", false)
		"rate_limit":
			return _health_failure("rate_limited", "PROVIDER_RATE_LIMITED", true)
		"timeout":
			return _health_failure("timeout", "PROVIDER_TIMEOUT", true)
		"network", "server":
			return _health_failure("unavailable", "PROVIDER_CONNECTION_FAILED", true)
		"configuration":
			return _health_failure("unavailable", "LLM_PROVIDER_CONFIGURATION_INVALID", false)
		_:
			return _health_failure(
				"unavailable",
				"PROVIDER_HEALTH_REQUEST_FAILED",
				retryable,
			)


func _health_success() -> Dictionary:
	return {"status": "available", "errorCode": "", "retryable": false}


func _health_failure(status: String, error_code: String, retryable: bool) -> Dictionary:
	return {"status": status, "errorCode": error_code, "retryable": retryable}


func _target_key(provider_id: String, model_id: String) -> String:
	return "%s|%s" % [provider_id, model_id]


func _provider_config(provider_id: String, model_id: String) -> Dictionary:
	var config: Dictionary = {}
	var provider_value: Variant = _provider_configs.get(provider_id, {})
	if provider_value is Dictionary:
		config = (provider_value as Dictionary).duplicate(true)
	var model_value: Variant = _provider_configs.get(model_id, {})
	if model_value is Dictionary:
		config.merge((model_value as Dictionary).duplicate(true), true)
	return config


func _catalog_model_descriptor(
	provider_id: String,
	model_id: String,
) -> Dictionary:
	if (
		_provider_uses_custom_models(provider_id)
		and model_id in _configured_api_models(provider_id)
	):
		return _dynamic_model_descriptor(provider_id, model_id)
	var value: Variant
	if _method_argument_count(_catalog, "model_descriptor") >= 2:
		value = _catalog.model_descriptor(provider_id, model_id)
	else:
		value = _catalog.model_descriptor(model_id)
	return value as Dictionary if value is Dictionary else {}


func _catalog_create_model(
	provider_id: String,
	model_id: String,
	request_host: Node,
	config: Dictionary,
) -> Dictionary:
	if (
		_provider_uses_custom_models(provider_id)
		and model_id in _configured_api_models(provider_id)
	):
		var resolved_config := config.duplicate(true)
		resolved_config["api_model"] = model_id
		resolved_config["model"] = model_id
		resolved_config.erase("api_models")
		var creation := _catalog.create_provider(
			provider_id,
			request_host,
			resolved_config,
		) as Dictionary
		if bool(creation.get("ok", false)):
			var provider_descriptor := (
				creation.get("descriptor", {}) as Dictionary
			).duplicate(true)
			provider_descriptor["model_id"] = model_id
			creation["provider_descriptor"] = provider_descriptor
			creation["model_descriptor"] = _dynamic_model_descriptor(
				provider_id,
				model_id,
			)
		return creation
	var value: Variant
	if _method_argument_count(_catalog, "create_model") >= 4:
		value = _catalog.create_model(provider_id,
			model_id,
			request_host,
			config,)
	else:
		value = _catalog.create_model(model_id, request_host, config)
	return value as Dictionary if value is Dictionary else {}


func _provider_uses_custom_models(provider_id: String) -> bool:
	var descriptor := _catalog.descriptor(provider_id) as Dictionary
	return bool(descriptor.get("custom_models", false))


func _configured_api_models(provider_id: String) -> Array[String]:
	var result: Array[String] = []
	var config_value: Variant = _provider_configs.get(provider_id, {})
	if not config_value is Dictionary:
		return result
	var models_value: Variant = (config_value as Dictionary).get("api_models", [])
	if not models_value is Array:
		return result
	for model_value: Variant in models_value as Array:
		if typeof(model_value) != TYPE_STRING:
			continue
		var model_id := (model_value as String).strip_edges()
		if not model_id.is_empty() and model_id not in result:
			result.append(model_id)
	return result


func _dynamic_model_descriptor(provider_id: String, model_id: String) -> Dictionary:
	var provider_descriptor := _catalog.descriptor(provider_id) as Dictionary
	var model_family := _model_release_family(model_id)
	var model_labels := (
		provider_descriptor.get("catalog_model_labels", {}) as Dictionary
	)
	var multimodal_families := (
		provider_descriptor.get("catalog_multimodal_families", []) as Array
	)
	return {
		"id": model_id,
		"label": String(model_labels.get(
			model_family,
			model_labels.get(model_family.to_lower(), model_id),
		)),
		"provider_id": provider_id,
		"input_modalities": (
			["text", "image"]
			if model_family in multimodal_families
			else ["text"]
		),
		"runtime_modalities_configurable": true,
		"custom": true,
	}


func _model_release_family(model_id: String) -> String:
	var separator := model_id.rfind("-")
	if separator < 0:
		return model_id
	var suffix := model_id.substr(separator + 1)
	if suffix.is_valid_int() and suffix.length() in [6, 8]:
		return model_id.substr(0, separator)
	return model_id


func _rebuild_catalog_for_configs(provider_configs: Dictionary) -> Dictionary:
	# 测试可注入自己的 catalog；只重建正式目录实例。
	if _catalog == null or _catalog.get_script() != CATALOG:
		return {"ok": true, "errorCode": "", "retryable": false}
	var rebuilt := CATALOG.new()
	for provider_id_value: Variant in provider_configs.keys():
		var provider_id := String(provider_id_value).strip_edges()
		var config_value: Variant = provider_configs.get(provider_id_value)
		if not config_value is Dictionary:
			continue
		var config := config_value as Dictionary
		if String(config.get("connection_type", "")) != COMPATIBLE_PROFILE_TYPE:
			continue
		var display_name := String(
			config.get("display_name", "兼容接口")
		).strip_edges()
		var registered := rebuilt.register_openai_compatible_profile(
			provider_id,
			display_name,
			String(config.get("endpoint", "")).strip_edges(),
			bool(config.get("api_key_required", true)),
		) as Dictionary
		if not bool(registered.get("ok", false)):
			return _failure(
				"PROVIDER_DYNAMIC_CONNECTION_INVALID",
				false,
				registered.get("errors", []) as Array,
			)
	_catalog = rebuilt
	return {"ok": true, "errorCode": "", "retryable": false}


func _changed_provider_ids(previous: Dictionary, current: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for provider_id_value: Variant in previous.keys():
		var provider_id := String(provider_id_value)
		if not current.has(provider_id) or previous.get(provider_id) != current.get(provider_id):
			result.append(provider_id)
	for provider_id_value: Variant in current.keys():
		var provider_id := String(provider_id_value)
		if not previous.has(provider_id) and provider_id not in result:
			result.append(provider_id)
	return result


func _invalidate_provider_health_entries(provider_ids: Array[String]) -> void:
	if provider_ids.is_empty():
		return
	for key_value: Variant in _health_by_target.keys():
		var health_value: Variant = _health_by_target.get(key_value)
		if (
			health_value is Dictionary
			and String((health_value as Dictionary).get("providerId", "")) in provider_ids
		):
			_health_by_target.erase(key_value)


func _method_argument_count(target: Object, method_name: String) -> int:
	for method_value: Variant in target.get_method_list():
		if not method_value is Dictionary:
			continue
		var method := method_value as Dictionary
		if String(method.get("name", "")) != method_name:
			continue
		var args_value: Variant = method.get("args", [])
		return (args_value as Array).size() if args_value is Array else 0
	return 0


func _canonical_id_is_valid(value: String) -> bool:
	return not value.is_empty() and value == value.strip_edges()


func _public_string(value: Variant, fallback := "") -> String:
	return value as String if typeof(value) == TYPE_STRING else fallback


func _public_request_url(request: Dictionary) -> String:
	var url := _public_string(request.get("url"))
	if url.is_empty():
		return ""
	var query_start := url.find("?")
	if query_start >= 0:
		return "%s?<已隐藏参数>" % url.left(query_start)
	return url


func _public_nonnegative_integer(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		var integer := value as int
		return integer if integer >= 0 and integer <= MAX_SAFE_INTEGER else -1
	if typeof(value) != TYPE_FLOAT:
		return -1
	var number := float(value)
	if (
		not is_finite(number)
		or number < 0.0
		or number > float(MAX_SAFE_INTEGER)
		or number != floorf(number)
	):
		return -1
	return int(number)


func _detail(index: int, code: String, meta: Dictionary = {}) -> Dictionary:
	return {
		"path": "residentBindings[%d]" % index,
		"code": code,
		"meta": meta.duplicate(true),
	}


func _failure(error_code: String, retryable: bool, errors: Array = []) -> Dictionary:
	return RESULT_SHAPES.failure_with(error_code, retryable, errors)
