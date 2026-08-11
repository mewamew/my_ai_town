class_name AgentModelProviderCatalog
extends RefCounted


const DeepSeekModelProviderScript := preload("res://agent/model/DeepSeekModelProvider.gd")
const VolcengineArkModelProviderScript := preload("res://agent/model/VolcengineArkModelProvider.gd")
const AlibabaBailianModelProviderScript := preload("res://agent/model/AlibabaBailianModelProvider.gd")
const KimiModelProviderScript := preload("res://agent/model/KimiModelProvider.gd")
const ZhipuGLMModelProviderScript := preload("res://agent/model/ZhipuGLMModelProvider.gd")
const XiaomiMiMoModelProviderScript := preload("res://agent/model/XiaomiMiMoModelProvider.gd")
const GenericOpenAICompatibleModelProviderScript := preload(
	"res://agent/model/GenericOpenAICompatibleModelProvider.gd"
)
const ThreeZeroTwoAIModelProviderScript := preload(
	"res://agent/model/ThreeZeroTwoAIModelProvider.gd"
)
const OllamaCloudModelProviderScript := preload(
	"res://agent/model/OllamaCloudModelProvider.gd"
)
const FakeModelProviderScript := preload("res://agent/model/FakeModelProvider.gd")
const SUPPORTED_INPUT_MODALITIES := ["text", "image"]

var _descriptors: Dictionary = {}
var _factories: Dictionary = {}
var _provider_ids: Array[String] = []
var _default_provider_id := ""
var _model_descriptors_by_provider: Dictionary = {}
var _model_ids_by_provider: Dictionary = {}
var _default_model_ids_by_provider: Dictionary = {}


func _init(include_defaults := true) -> void:
	if not include_defaults:
		return
	_register_provider_with_models(DeepSeekModelProviderScript, _create_deepseek, true)
	_register_provider_with_models(VolcengineArkModelProviderScript, _create_volcengine_ark)
	_register_provider_with_models(AlibabaBailianModelProviderScript, _create_alibaba_bailian)
	_register_provider_with_models(KimiModelProviderScript, _create_kimi)
	_register_provider_with_models(ZhipuGLMModelProviderScript, _create_zhipu_glm)
	_register_provider_with_models(XiaomiMiMoModelProviderScript, _create_xiaomi_mimo)
	_register_provider_with_models(
		GenericOpenAICompatibleModelProviderScript,
		_create_openai_compatible,
	)
	_register_openai_compatible_preset(
		"302-ai",
		"302.AI",
		"302.AI OpenAI-compatible API",
		"https://api.302.ai/v1",
		true,
		_create_302_ai,
		{
			"catalog_model_labels": ThreeZeroTwoAIModelProviderScript.TOWN_MODEL_LABELS,
		},
	)
	_register_openai_compatible_preset(
		"ollama",
		"Ollama（本地）",
		"Ollama OpenAI-compatible API",
		"http://127.0.0.1:11434/v1",
		false,
		_create_ollama,
	)
	_register_openai_compatible_preset(
		"ollama-cloud",
		"Ollama Cloud",
		"Ollama Cloud API",
		"https://ollama.com/api",
		true,
		_create_ollama_cloud,
		{"native_ollama_api": true},
	)
	_register_openai_compatible_preset(
		"lm-studio",
		"LM Studio（本地）",
		"LM Studio OpenAI-compatible API",
		"http://127.0.0.1:1234/v1",
		false,
		_create_lm_studio,
	)
	register_provider(FakeModelProviderScript.new().get_provider_descriptor(), _create_fake)
	register_model({
		"id": "fake",
		"label": "Fake",
		"provider_id": "fake",
		"default_for_provider": true,
		"input_modalities": ["text", "image"],
	})


func _register_provider_with_models(
	provider_script: Script,
	factory: Callable,
	make_default := false,
) -> void:
	var adapter: RefCounted = provider_script.new()
	var descriptor: Dictionary = adapter.call("get_provider_descriptor")
	var provider_id := String(descriptor.get("id", ""))
	register_provider(descriptor, factory, make_default)
	var default_model := String(provider_script.get("DEFAULT_MODEL"))
	for model_descriptor: Dictionary in provider_script.get("MODEL_DESCRIPTORS"):
		var registered_model := model_descriptor.duplicate(true)
		registered_model["provider_id"] = provider_id
		if registered_model.get("id") == default_model:
			registered_model["default_for_provider"] = true
		register_model(registered_model)


func _register_openai_compatible_preset(
	provider_id: String,
	label: String,
	transport_label: String,
	default_endpoint: String,
	auth_required: bool,
	factory: Callable,
	extra_descriptor: Dictionary = {},
) -> Dictionary:
	var descriptor := {
		"id": provider_id,
		"label": label,
		"transport_label": transport_label,
		"external": true,
		"auth_required": auth_required,
		"default_endpoint": default_endpoint,
		"custom_models": true,
		"custom_group": true,
		"model_catalog_supported": true,
	}
	for key: Variant in extra_descriptor:
		descriptor[key] = extra_descriptor[key]
	var provider_result := register_provider(descriptor, factory)
	if provider_result.get("ok") != true:
		return provider_result
	var model_result := register_model({
		"id": "custom",
		"label": "自定义模型",
		"provider_id": provider_id,
		"default_for_provider": true,
		"input_modalities": ["text"],
		"runtime_modalities_configurable": true,
	})
	if model_result.get("ok") != true:
		return model_result
	return {"ok": true, "descriptor": provider_result.get("descriptor", {})}


func register_openai_compatible_profile(
	provider_id: String,
	label: String,
	default_endpoint := "",
	auth_required := true,
) -> Dictionary:
	var normalized_id := provider_id.strip_edges()
	var normalized_label := label.strip_edges()
	if normalized_id.is_empty() or normalized_label.is_empty():
		return {"ok": false, "errors": ["兼容连接名称和 ID 不能为空"]}
	return _register_openai_compatible_preset(
		normalized_id,
		normalized_label,
		"%s OpenAI-compatible API" % normalized_label,
		default_endpoint.strip_edges(),
		auth_required,
		_create_dynamic_openai_compatible.bind(
			normalized_id,
			normalized_label,
			default_endpoint.strip_edges(),
			auth_required,
		),
	)


func register_provider(descriptor: Dictionary, factory: Callable, make_default := false) -> Dictionary:
	var provider_id := String(descriptor.get("id", "")).strip_edges()
	var label := String(descriptor.get("label", "")).strip_edges()
	var errors: Array[String] = []
	if provider_id.is_empty():
		errors.append("Provider descriptor.id 必须是非空文本")
	if label.is_empty():
		errors.append("Provider descriptor.label 必须是非空文本")
	if not factory.is_valid():
		errors.append("Provider factory 必须是有效回调")
	if _descriptors.has(provider_id):
		errors.append("Provider 已注册：%s" % provider_id)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var normalized := descriptor.duplicate(true)
	normalized["id"] = provider_id
	normalized["label"] = label
	normalized.erase("model_id")
	normalized["transport_label"] = String(normalized.get("transport_label", label)).strip_edges()
	normalized["external"] = bool(normalized.get("external", false))
	_descriptors[provider_id] = normalized
	_factories[provider_id] = factory
	_provider_ids.append(provider_id)
	_model_descriptors_by_provider[provider_id] = {}
	_model_ids_by_provider[provider_id] = []
	if make_default or _default_provider_id.is_empty():
		_default_provider_id = provider_id
	return {"ok": true, "descriptor": normalized.duplicate(true)}


func list_providers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for provider_id: String in _provider_ids:
		result.append((_descriptors[provider_id] as Dictionary).duplicate(true))
	return result


func default_provider_id() -> String:
	return _default_provider_id


func register_model(descriptor: Dictionary, make_default := false) -> Dictionary:
	var model_id := String(descriptor.get("id", "")).strip_edges()
	var label := String(descriptor.get("label", "")).strip_edges()
	var provider_id := String(descriptor.get("provider_id", "")).strip_edges()
	var errors: Array[String] = []
	if model_id.is_empty():
		errors.append("Model descriptor.id 必须是非空文本")
	if label.is_empty():
		errors.append("Model descriptor.label 必须是非空文本")
	if provider_id.is_empty():
		errors.append("Model descriptor.provider_id 必须是非空文本")
	elif not _descriptors.has(provider_id):
		errors.append("Model 引用了未知 Provider：%s" % provider_id)
	var provider_models: Dictionary = _model_descriptors_by_provider.get(provider_id, {})
	if provider_models.has(model_id):
		errors.append("Model 已注册：%s" % model_id)
	var input_modalities: Variant = descriptor.get("input_modalities")
	var modality_validation := _validate_input_modalities(
		input_modalities,
		"Model descriptor.input_modalities",
	)
	errors.append_array(modality_validation.get("errors", []))
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var normalized := descriptor.duplicate(true)
	normalized["id"] = model_id
	normalized["label"] = label
	normalized["provider_id"] = provider_id
	normalized["input_modalities"] = modality_validation.get("input_modalities", [])
	provider_models[model_id] = normalized
	_model_descriptors_by_provider[provider_id] = provider_models
	var provider_model_ids: Array = _model_ids_by_provider.get(provider_id, [])
	provider_model_ids.append(model_id)
	_model_ids_by_provider[provider_id] = provider_model_ids
	if not _default_model_ids_by_provider.has(provider_id) or bool(normalized.get("default_for_provider", false)):
		_default_model_ids_by_provider[provider_id] = model_id
	if make_default:
		_default_provider_id = provider_id
		_default_model_ids_by_provider[provider_id] = model_id
	return {"ok": true, "descriptor": normalized.duplicate(true)}


func list_models(provider_id := "") -> Array[Dictionary]:
	var normalized_provider_id := String(provider_id).strip_edges()
	var result: Array[Dictionary] = []
	var provider_ids: Array[String] = []
	if normalized_provider_id.is_empty():
		provider_ids.assign(_provider_ids)
	else:
		provider_ids.append(normalized_provider_id)
	for current_provider_id: String in provider_ids:
		var provider_models: Dictionary = _model_descriptors_by_provider.get(current_provider_id, {})
		var model_ids: Array[String] = []
		model_ids.assign(_model_ids_by_provider.get(current_provider_id, []))
		for model_id: String in model_ids:
			result.append((provider_models[model_id] as Dictionary).duplicate(true))
	return result


func default_model_id(provider_id := "") -> String:
	var normalized_provider_id := String(provider_id).strip_edges()
	if normalized_provider_id.is_empty():
		normalized_provider_id = _default_provider_id
	return String(_default_model_ids_by_provider.get(normalized_provider_id, ""))


func model_descriptor(provider_id: String, model_id: String) -> Dictionary:
	var provider_models: Dictionary = _model_descriptors_by_provider.get(provider_id, {})
	if not provider_models.has(model_id):
		return {}
	return (provider_models[model_id] as Dictionary).duplicate(true)


func descriptor(provider_id: String) -> Dictionary:
	if not _descriptors.has(provider_id):
		return {}
	return (_descriptors[provider_id] as Dictionary).duplicate(true)


func create_provider(provider_id: String, request_host: Node = null, config: Dictionary = {}) -> Dictionary:
	if not _factories.has(provider_id):
		return {"ok": false, "errors": ["未知模型 Provider：%s" % provider_id]}
	var resolved_config := config.duplicate(true)
	if resolved_config.has("model"):
		var configured_model_id := String(resolved_config.get("model", ""))
		var provider_models: Dictionary = _model_descriptors_by_provider.get(provider_id, {})
		var provider_descriptor := descriptor(provider_id)
		if (
			not provider_models.has(configured_model_id)
			and not bool(provider_descriptor.get("custom_models", false))
		):
			return {"ok": false, "errors": ["未知模型：%s" % configured_model_id]}
	if not resolved_config.has("model"):
		var provider_default_model := default_model_id(provider_id)
		if not provider_default_model.is_empty():
			resolved_config["model"] = provider_default_model
	var selected_model_id := String(resolved_config.get("model", ""))
	if not selected_model_id.is_empty():
		var selected_model := model_descriptor(provider_id, selected_model_id)
		var registered_modalities: Variant = selected_model.get("input_modalities", ["text"])
		if bool(selected_model.get("runtime_modalities_configurable", false)) \
				and resolved_config.has("input_modalities"):
			var custom_validation := _validate_input_modalities(
				resolved_config.get("input_modalities"),
				"Custom Model input_modalities",
			)
			if custom_validation.get("ok") != true:
				return {"ok": false, "errors": custom_validation.get("errors", [])}
			resolved_config["input_modalities"] = custom_validation.get("input_modalities", [])
		else:
			resolved_config["input_modalities"] = registered_modalities
	var provider: Object = (_factories[provider_id] as Callable).call(request_host, resolved_config)
	if provider == null:
		return {"ok": false, "errors": ["Provider 工厂未返回合法 adapter：%s" % provider_id]}
	var missing_methods: Array[String] = []
	for method_name: String in ["get_provider_descriptor", "validate_configuration", "request_decision", "get_debug_snapshot"]:
		if not provider.has_method(method_name):
			missing_methods.append(method_name)
	if not missing_methods.is_empty():
		return {"ok": false, "errors": ["Provider adapter 接口不完整：%s" % ", ".join(missing_methods)]}
	var instance_descriptor: Dictionary = provider.call("get_provider_descriptor")
	if String(instance_descriptor.get("id", "")) != provider_id:
		return {"ok": false, "errors": ["Provider adapter id 与注册 id 不一致：%s" % provider_id]}
	return {"ok": true, "provider": provider, "descriptor": descriptor(provider_id)}


func _validate_input_modalities(value: Variant, field_label: String) -> Dictionary:
	var errors: Array[String] = []
	var normalized: Array[String] = []
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		errors.append("%s 必须是非空数组" % field_label)
	else:
		for modality_value: Variant in value:
			if typeof(modality_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
				errors.append("Model 输入模态必须是字符串")
				continue
			var modality := String(modality_value).strip_edges()
			if modality not in SUPPORTED_INPUT_MODALITIES:
				errors.append("Model 输入模态不受支持：%s" % modality)
			elif modality in normalized:
				errors.append("Model 输入模态重复：%s" % modality)
			else:
				normalized.append(modality)
		if "text" not in normalized:
			errors.append("Agent Model 必须支持 text 输入")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"input_modalities": normalized,
	}


func create_model(
	provider_id: String,
	model_id: String,
	request_host: Node = null,
	config: Dictionary = {},
) -> Dictionary:
	var provider_models: Dictionary = _model_descriptors_by_provider.get(provider_id, {})
	if not provider_models.has(model_id):
		return {"ok": false, "errors": ["未知模型：%s" % model_id]}
	var selected_model := provider_models[model_id] as Dictionary
	var resolved_config := config.duplicate(true)
	resolved_config["model"] = model_id
	var creation := create_provider(provider_id, request_host, resolved_config)
	if creation.get("ok") != true:
		return creation
	creation["provider_descriptor"] = creation.get("provider").call("get_provider_descriptor")
	creation["model_descriptor"] = selected_model.duplicate(true)
	return creation


func _create_deepseek(request_host: Node, config: Dictionary) -> RefCounted:
	return DeepSeekModelProviderScript.new(request_host, null, config)


func _create_volcengine_ark(request_host: Node, config: Dictionary) -> RefCounted:
	return VolcengineArkModelProviderScript.new(request_host, null, config)


func _create_alibaba_bailian(request_host: Node, config: Dictionary) -> RefCounted:
	return AlibabaBailianModelProviderScript.new(request_host, null, config)


func _create_zhipu_glm(request_host: Node, config: Dictionary) -> RefCounted:
	return ZhipuGLMModelProviderScript.new(request_host, null, config)


func _create_xiaomi_mimo(request_host: Node, config: Dictionary) -> RefCounted:
	return XiaomiMiMoModelProviderScript.new(request_host, null, config)


func _create_kimi(request_host: Node, config: Dictionary) -> RefCounted:
	return KimiModelProviderScript.new(request_host, null, config)


func _create_openai_compatible(request_host: Node, config: Dictionary) -> RefCounted:
	return GenericOpenAICompatibleModelProviderScript.new(request_host, null, config)


func _create_dynamic_openai_compatible(
	request_host: Node,
	config: Dictionary,
	provider_id: String,
	provider_label: String,
	default_endpoint: String,
	auth_required: bool,
) -> RefCounted:
	return GenericOpenAICompatibleModelProviderScript.new(
		request_host,
		null,
		_compatible_preset_config(config, {
			"provider_id": provider_id,
			"provider_label": provider_label,
			"transport_label": "%s OpenAI-compatible API" % provider_label,
			"default_endpoint": default_endpoint,
			"api_key_required": auth_required,
			"api_key_environment": "",
			"timeout_seconds": 60.0,
		}),
	)


func _create_302_ai(request_host: Node, config: Dictionary) -> RefCounted:
	return ThreeZeroTwoAIModelProviderScript.new(
		request_host,
		null,
		_compatible_preset_config(config, {
			"provider_id": "302-ai",
			"provider_label": "302.AI",
			"transport_label": "302.AI OpenAI-compatible API",
			"default_endpoint": "https://api.302.ai/v1",
			"api_key_required": true,
			"api_key_environment": "AI_302_API_KEY",
			"timeout_seconds": 60.0,
		}),
	)


func _create_ollama(request_host: Node, config: Dictionary) -> RefCounted:
	return GenericOpenAICompatibleModelProviderScript.new(
		request_host,
		null,
		_compatible_preset_config(config, {
			"provider_id": "ollama",
			"provider_label": "Ollama（本地）",
			"transport_label": "Ollama OpenAI-compatible API",
			"default_endpoint": "http://127.0.0.1:11434/v1",
			"api_key_required": false,
			"api_key_environment": "OLLAMA_API_KEY",
			"timeout_seconds": 300.0,
		}),
	)


func _create_ollama_cloud(request_host: Node, config: Dictionary) -> RefCounted:
	return OllamaCloudModelProviderScript.new(
		request_host,
		null,
		_compatible_preset_config(config, {
			"provider_id": "ollama-cloud",
			"provider_label": "Ollama Cloud",
			"transport_label": "Ollama Cloud API",
			"default_endpoint": "https://ollama.com/api",
			"api_key_required": true,
			"api_key_environment": "OLLAMA_API_KEY",
			"timeout_seconds": 120.0,
		}),
	)


func _create_lm_studio(request_host: Node, config: Dictionary) -> RefCounted:
	return GenericOpenAICompatibleModelProviderScript.new(
		request_host,
		null,
		_compatible_preset_config(config, {
			"provider_id": "lm-studio",
			"provider_label": "LM Studio（本地）",
			"transport_label": "LM Studio OpenAI-compatible API",
			"default_endpoint": "http://127.0.0.1:1234/v1",
			"api_key_required": false,
			"api_key_environment": "LM_STUDIO_API_KEY",
			"timeout_seconds": 300.0,
		}),
	)


func _compatible_preset_config(
	config: Dictionary,
	preset: Dictionary,
) -> Dictionary:
	var result := config.duplicate(true)
	result["preset_provider_id"] = String(preset.get("provider_id", ""))
	result["preset_provider_label"] = String(preset.get("provider_label", ""))
	result["preset_transport_label"] = String(preset.get("transport_label", ""))
	result["preset_default_endpoint"] = String(preset.get("default_endpoint", ""))
	if not result.has("endpoint"):
		result["endpoint"] = result["preset_default_endpoint"]
	result["preset_api_key_required"] = bool(preset.get("api_key_required", true))
	result["preset_api_key_environment"] = String(
		preset.get("api_key_environment", "")
	)
	if not result.has("timeout_seconds"):
		result["timeout_seconds"] = float(preset.get("timeout_seconds", 30.0))
	return result


func _create_fake(_request_host: Node, config: Dictionary) -> RefCounted:
	return FakeModelProviderScript.new(config)
