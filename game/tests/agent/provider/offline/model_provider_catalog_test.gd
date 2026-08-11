extends "res://tests/agent/support/AgentTestCase.gd"


const CatalogScript := preload("res://agent/model/ModelProviderCatalog.gd")
const ProviderServiceScript := preload(
	"res://world/integration/TownAgentProviderService.gd"
)
const ConfigStoreScript := preload(
	"res://world/presentation/ui/TownProviderConfigStore.gd"
)
const SettingsServiceScript := preload(
	"res://world/presentation/ui/TownProviderSettingsService.gd"
)
const ProviderSettingsScreenScript := preload(
	"res://ui/provider_settings/ProviderSettingsScreen.gd"
)
const ResidentAssignmentServiceScript := preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentService.gd"
)
const CONFIG_TEST_ROOT := "user://tests/provider_compatibility_config"



func _initialize() -> void:
	var catalog: RefCounted = CatalogScript.new()
	var provider_ids: Array[String] = []
	for descriptor: Dictionary in catalog.call("list_providers"):
		provider_ids.append(String(descriptor.get("id", "")))
	_expect_equal(
		provider_ids,
		[
			"deepseek",
			"volcengine-ark",
			"aliyun-bailian",
			"kimi",
			"zhipu-glm",
			"xiaomi-mimo",
			"openai-compatible",
			"302-ai",
			"ollama",
			"ollama-cloud",
			"lm-studio",
			"fake",
		],
		"catalog exposes the provider adapters in stable order",
	)

	_expect_equal(_model_ids(catalog, "deepseek"), ["deepseek-v4-flash", "deepseek-v4-pro"], "DeepSeek exposes V4 models")
	_expect_equal(
		_model_ids(catalog, "volcengine-ark"),
		[],
		"Ark no longer ships a stale preset model list",
	)
	_expect_equal(
		_model_ids(catalog, "aliyun-bailian"),
		[
			"qwen3.5-plus",
			"qwen3.5-flash",
			"qwen3.5-397b-a17b",
			"qwen3.5-122b-a10b",
			"qwen3.5-35b-a3b",
			"qwen3.5-27b",
			"qwen3.6-max-preview",
			"qwen3.6-plus",
			"qwen3.6-flash",
			"qwen3.7-max",
			"qwen3.7-plus",
		],
		"Bailian exposes the documented Qwen 3.5 through 3.7 catalog",
	)
	_expect_equal(
		_model_ids(catalog, "kimi"),
		["kimi-k2.5", "kimi-k2.6", "kimi-k2.7-code-highspeed", "kimi-k3"],
		"Kimi keeps only the faster K2.7 variant alongside K2.5, K2.6, and K3",
	)
	_expect_equal(
		_model_ids(catalog, "zhipu-glm"),
		["glm-4.7", "glm-5", "glm-5.1", "glm-5.2", "glm-5v-turbo"],
		"GLM exposes 4.7 through current",
	)
	_expect_equal(
		_model_ids(catalog, "xiaomi-mimo"),
		["mimo-v2.5-pro", "mimo-v2.5"],
		"Xiaomi exposes the current MiMo V2.5 chat models",
	)
	_expect_equal(_model_ids(catalog, "openai-compatible"), ["custom"], "generic OpenAI compatibility has one custom model entry")
	_expect_equal(_model_ids(catalog, "302-ai"), ["custom"], "302.AI accepts player model ids")
	_expect_equal(_model_ids(catalog, "ollama"), ["custom"], "Ollama accepts local model ids")
	_expect_equal(
		_model_ids(catalog, "ollama-cloud"),
		["custom"],
		"Ollama Cloud accepts models returned for the player's cloud key",
	)
	_expect_equal(_model_ids(catalog, "lm-studio"), ["custom"], "LM Studio accepts local model ids")
	_expect_equal(_model_ids(catalog, "fake"), ["fake"], "Fake is represented by the same two-level catalog")
	_expect_equal(
		catalog.call("descriptor", "302-ai").get("default_endpoint"),
		"https://api.302.ai/v1",
		"302.AI ships with its recommended API base URL",
	)
	_expect_equal(
		catalog.call("descriptor", "ollama").get("auth_required"),
		false,
		"Ollama does not require a placeholder API key",
	)
	_expect_equal(
		catalog.call("descriptor", "ollama-cloud").get("default_endpoint"),
		"https://ollama.com/api",
		"Ollama Cloud uses the official direct API base URL",
	)
	_expect_equal(
		catalog.call("descriptor", "ollama-cloud").get("auth_required"),
		true,
		"direct Ollama Cloud access requires its API key",
	)
	_expect_equal(
		catalog.call("descriptor", "lm-studio").get("auth_required"),
		false,
		"LM Studio does not require a placeholder API key",
	)
	_expect_equal(catalog.call("default_model_id"), "deepseek-v4-flash", "DeepSeek remains the global default")
	_expect_equal(
		catalog.call("default_model_id", "volcengine-ark"),
		"",
		"Ark waits for the saved API key to return the account model list",
	)
	_expect_equal(
		catalog.call("descriptor", "volcengine-ark").get(
			"model_catalog_supported"
		),
		true,
		"Ark advertises API-key model discovery",
	)
	_expect_equal(catalog.call("default_model_id", "aliyun-bailian"), "qwen3.7-plus", "Bailian defaults to Qwen 3.7 Plus")
	_expect_equal(catalog.call("default_model_id", "kimi"), "kimi-k3", "Kimi defaults to K3")
	_expect_equal(catalog.call("default_model_id", "zhipu-glm"), "glm-5.2", "GLM defaults to 5.2")
	_expect_equal(catalog.call("default_model_id", "xiaomi-mimo"), "mimo-v2.5-pro", "Xiaomi defaults to MiMo V2.5 Pro")
	_expect_equal(
		catalog.call("model_descriptor", "deepseek", "deepseek-v4-flash").get("input_modalities"),
		["text"],
		"DeepSeek declares text input explicitly",
	)
	_expect_equal(
		catalog.call("model_descriptor", "aliyun-bailian", "qwen3.7-plus").get("input_modalities"),
		["text", "image"],
		"Qwen 3.7 Plus declares visual input explicitly",
	)
	_expect_equal(
		catalog.call("model_descriptor", "aliyun-bailian", "qwen3.7-max").get("input_modalities"),
		["text"],
		"unverified Qwen visual input fails closed",
	)
	_expect_equal(
		catalog.call("model_descriptor", "zhipu-glm", "glm-5v-turbo").get("input_modalities"),
		["text", "image"],
		"GLM-5V declares visual input explicitly",
	)
	_expect_equal(
		catalog.call("model_descriptor", "xiaomi-mimo", "mimo-v2.5-pro").get("input_modalities"),
		["text"],
		"MiMo V2.5 Pro declares text input",
	)
	_expect_equal(
		catalog.call("model_descriptor", "xiaomi-mimo", "mimo-v2.5").get("input_modalities"),
		["text", "image"],
		"MiMo V2.5 declares visual input",
	)
	_expect_equal(
		catalog.call("model_descriptor", "fake", "fake").get("input_modalities"),
		["text", "image"],
		"Fake supports offline visual-flow testing",
	)

	var k3_creation := catalog.call(
		"create_model",
		"kimi",
		"kimi-k3",
		null,
		{"api_key": "test-key"},
	) as Dictionary
	_expect_equal(k3_creation.get("ok"), true, "catalog creates K3 through the model seam")
	if k3_creation.get("ok") == true:
		_expect_equal(k3_creation.get("model_descriptor", {}).get("provider_id"), "kimi", "created K3 retains its route")
		_expect_equal(k3_creation.get("provider").call("get_provider_descriptor").get("model_id"), "kimi-k3", "K3 model id reaches the shared adapter")
		_expect_equal(
			k3_creation.get("provider").call("get_provider_descriptor").get("input_modalities"),
			["text", "image"],
			"selected model input modalities reach the adapter",
		)
	var fake_creation := catalog.call("create_model", "fake", "fake", null, {}) as Dictionary
	_expect_equal(fake_creation.get("ok"), true, "catalog creates Fake through the model seam")
	if fake_creation.get("ok") == true:
		_expect_equal(
			fake_creation.get("provider").call("get_provider_descriptor").get("input_modalities"),
			["text", "image"],
			"Fake receives the registered input modalities",
		)
	var visual_custom := catalog.call(
		"create_model",
		"openai-compatible",
		"custom",
		null,
		{"input_modalities": ["text", "image"]},
	) as Dictionary
	_expect_equal(visual_custom.get("ok"), true, "custom model accepts an explicit visual-input declaration")
	if visual_custom.get("ok") == true:
		_expect_equal(
			visual_custom.get("provider").call("get_provider_descriptor").get("input_modalities"),
			["text", "image"],
			"custom visual-input declaration reaches the adapter",
		)
	var suggestive_custom_name := catalog.call(
		"create_model",
		"openai-compatible",
		"custom",
		null,
		{"api_model": "vendor-vision-image-model"},
	) as Dictionary
	_expect_equal(suggestive_custom_name.get("ok"), true, "custom model accepts arbitrary wire model names")
	if suggestive_custom_name.get("ok") == true:
		_expect_equal(
			suggestive_custom_name.get("provider").call("get_provider_descriptor").get("input_modalities"),
			["text"],
			"custom remains text-only unless the user explicitly declares image input",
		)
	var invalid_custom_modalities := catalog.call(
		"create_model",
		"openai-compatible",
		"custom",
		null,
		{"input_modalities": ["image"]},
	) as Dictionary
	_expect_equal(
		invalid_custom_modalities.get("ok"),
		false,
		"custom model declarations must retain Agent text input",
	)
	var null_custom_modality := catalog.call(
		"create_model",
		"openai-compatible",
		"custom",
		null,
		{"input_modalities": [null]},
	) as Dictionary
	_expect_equal(
		null_custom_modality.get("ok"),
		false,
		"custom model rejects null input modality elements",
	)
	var numeric_custom_modality := catalog.call(
		"create_model",
		"openai-compatible",
		"custom",
		null,
		{"input_modalities": [1]},
	) as Dictionary
	_expect_equal(
		numeric_custom_modality.get("ok"),
		false,
		"custom model rejects numeric input modality elements",
	)
	var dictionary_custom_modality := catalog.call(
		"create_model",
		"openai-compatible",
		"custom",
		null,
		{"input_modalities": [{}]},
	) as Dictionary
	_expect_equal(
		dictionary_custom_modality.get("ok"),
		false,
		"custom model rejects dictionary input modality elements",
	)
	var protected_builtin := catalog.call(
		"create_model",
		"deepseek",
		"deepseek-v4-flash",
		null,
		{"input_modalities": ["text", "image"]},
	) as Dictionary
	_expect_equal(protected_builtin.get("ok"), true, "built-in model creation ignores capability expansion")
	if protected_builtin.get("ok") == true:
		_expect_equal(
			protected_builtin.get("provider").call("get_provider_descriptor").get("input_modalities"),
			["text"],
			"built-in model capabilities remain authoritative",
		)

	var legacy_kimi := catalog.call("create_provider", "kimi", null, {"api_key": "test-key"}) as Dictionary
	_expect_equal(legacy_kimi.get("ok"), true, "legacy provider creation remains available")
	if legacy_kimi.get("ok") == true:
		_expect_equal(legacy_kimi.get("provider").call("get_provider_descriptor").get("model_id"), "kimi-k3", "legacy Kimi creation resolves to K3")

	var mismatch := catalog.call("create_provider", "deepseek", null, {
		"api_key": "test-key",
		"model": "kimi-k3",
	}) as Dictionary
	_expect_equal(mismatch.get("ok"), false, "registered models cannot be sent to the wrong provider")
	_expect(_errors_contain(mismatch.get("errors", []), "未知模型"), "provider/model mismatch returns a useful error")
	var unsupported_kimi := catalog.call("create_provider", "kimi", null, {
		"api_key": "test-key",
		"model": "kimi-unknown",
	}) as Dictionary
	_expect_equal(unsupported_kimi.get("ok"), false, "unknown Kimi models cannot bypass the catalog")
	_expect(_errors_contain(unsupported_kimi.get("errors", []), "未知模型"), "unknown model returns a useful error")

	var unknown := catalog.call("create_model", "kimi", "missing-model", null, {}) as Dictionary
	_expect_equal(unknown.get("ok"), false, "unknown models are rejected")
	var shared_deepseek := catalog.call("register_model", {
		"id": "shared-model-id",
		"label": "DeepSeek Shared",
		"provider_id": "deepseek",
		"input_modalities": ["text"],
	}) as Dictionary
	var shared_kimi := catalog.call("register_model", {
		"id": "shared-model-id",
		"label": "Kimi Shared",
		"provider_id": "kimi",
		"input_modalities": ["text"],
	}) as Dictionary
	_expect_equal(shared_deepseek.get("ok"), true, "model ids are unique inside a Provider")
	_expect_equal(shared_kimi.get("ok"), true, "different Providers may reuse the same model id")
	_expect_equal(
		catalog.call("model_descriptor", "kimi", "shared-model-id").get("label"),
		"Kimi Shared",
		"provider/model identity resolves the correct descriptor",
	)
	var normalized_modalities := catalog.call("register_model", {
		"id": "normalized-modalities",
		"label": "Normalized Modalities",
		"provider_id": "deepseek",
		"input_modalities": [" text ", " image "],
	}) as Dictionary
	_expect_equal(normalized_modalities.get("ok"), true, "valid input modalities are normalized")
	_expect_equal(
		catalog.call("model_descriptor", "deepseek", "normalized-modalities").get("input_modalities"),
		["text", "image"],
		"catalog stores canonical input modality values",
	)
	var string_name_modalities := catalog.call("register_model", {
		"id": "string-name-modalities",
		"label": "StringName Modalities",
		"provider_id": "deepseek",
		"input_modalities": [&"text", &"image"],
	}) as Dictionary
	_expect_equal(string_name_modalities.get("ok"), true, "StringName input modalities are accepted")
	_expect_equal(
		catalog.call("model_descriptor", "deepseek", "string-name-modalities").get("input_modalities"),
		["text", "image"],
		"StringName input modalities are stored as canonical strings",
	)
	var missing_modalities := catalog.call("register_model", {
		"id": "missing-modalities",
		"label": "Missing Modalities",
		"provider_id": "deepseek",
	}) as Dictionary
	_expect_equal(missing_modalities.get("ok"), false, "model registration requires declared input modalities")
	var image_only := catalog.call("register_model", {
		"id": "image-only",
		"label": "Image Only",
		"provider_id": "deepseek",
		"input_modalities": ["image"],
	}) as Dictionary
	_expect_equal(image_only.get("ok"), false, "Agent models must support text input")
	var unknown_modality := catalog.call("register_model", {
		"id": "unknown-modality",
		"label": "Unknown Modality",
		"provider_id": "deepseek",
		"input_modalities": ["text", "audio"],
	}) as Dictionary
	_expect_equal(unknown_modality.get("ok"), false, "unknown input modalities are rejected")
	_test_compatible_runtime_models()
	_test_volcengine_custom_endpoint_model()
	_test_multiple_compatible_connections()
	_test_provider_health_isolation()
	_test_local_endpoint_and_model_persistence()
	_test_settings_service_custom_model_flow()
	_test_custom_model_ui_grouping()
	_finish_suite("MODEL_PROVIDER_CATALOG_PASS", [CONFIG_TEST_ROOT])


func _model_ids(catalog: RefCounted, provider_id: String) -> Array[String]:
	var result: Array[String] = []
	for descriptor: Dictionary in catalog.call("list_models", provider_id):
		result.append(String(descriptor.get("id", "")))
	return result


func _test_compatible_runtime_models() -> void:
	var service: RefCounted = ProviderServiceScript.new()
	var configured := service.call("configure", {
		"capabilityMode": "formal",
		"source": "runtime",
		"allowFake": false,
		"providerConfigs": {
			"302-ai": {
				"api_key": "temporary-302-key",
				"api_models": ["vendor/model-a", "vendor/model-b"],
				"api_model": "vendor/model-a",
			},
		},
	}) as Dictionary
	_expect_equal(configured.get("ok"), true, "302 runtime configuration is accepted")
	var compatible_ids: Array[String] = []
	for model: Dictionary in service.call("list_available_models"):
		if String(model.get("providerId", "")) == "302-ai":
			compatible_ids.append(String(model.get("modelId", "")))
	_expect_equal(
		compatible_ids,
		["vendor/model-a", "vendor/model-b"],
		"runtime exposes real compatible model ids instead of one custom alias",
	)
	service.set("_health_by_target", {
		"302-ai|vendor/model-a": {
			"providerId": "302-ai",
			"modelId": "vendor/model-a",
			"status": "available",
			"errorCode": "",
			"retryable": false,
		},
		"302-ai|vendor/model-b": {
			"providerId": "302-ai",
			"modelId": "vendor/model-b",
			"status": "available",
			"errorCode": "",
			"retryable": false,
		},
	})
	for index in range(2):
		var model_id := "vendor/model-a" if index == 0 else "vendor/model-b"
		var created := service.call("create_provider_for_resident", {
			"residentId": "resident-%d" % index,
			"llmBinding": {
				"mode": "model",
				"providerId": "302-ai",
				"modelId": model_id,
			},
		}) as Dictionary
		_expect_equal(created.get("ok"), true, "each resident can use a different 302 model")
		if bool(created.get("ok", false)):
			_expect_equal(
				created.get("provider").call("get_provider_descriptor").get("model_id"),
				model_id,
				"the resident's real wire model reaches the provider",
			)


func _test_volcengine_custom_endpoint_model() -> void:
	var service: RefCounted = ProviderServiceScript.new()
	var configured := service.call("configure", {
		"capabilityMode": "formal",
		"source": "runtime",
		"allowFake": false,
		"providerConfigs": {
			"volcengine-ark": {
				"api_key": "temporary-ark-key",
				"api_models": ["ep-player-custom-model"],
				"api_model": "ep-player-custom-model",
			},
		},
	}) as Dictionary
	_expect_equal(
		configured.get("ok"),
		true,
		"Ark accepts a player-entered inference endpoint id",
	)
	var custom_model := {}
	for model: Dictionary in service.call("list_available_models"):
		if (
			String(model.get("providerId", "")) == "volcengine-ark"
			and String(model.get("modelId", "")) == "ep-player-custom-model"
		):
			custom_model = model
			break
	_expect_equal(
		custom_model.get("custom"),
		true,
		"Ark projects the player-entered endpoint as a removable custom card",
	)
	service.set("_health_by_target", {
		"volcengine-ark|ep-player-custom-model": {
			"providerId": "volcengine-ark",
			"modelId": "ep-player-custom-model",
			"status": "available",
			"errorCode": "",
			"retryable": false,
		},
	})
	var created := service.call("create_provider_for_resident", {
		"residentId": "ark-custom-resident",
		"llmBinding": {
			"mode": "model",
			"providerId": "volcengine-ark",
			"modelId": "ep-player-custom-model",
		},
	}) as Dictionary
	_expect_equal(
		created.get("ok"),
		true,
		"an Ark custom endpoint can be assigned to a resident",
	)
	if bool(created.get("ok", false)):
		_expect_equal(
			created.get("provider").call("get_provider_descriptor").get("model_id"),
			"ep-player-custom-model",
			"the Ark custom endpoint id reaches the actual request provider",
		)
	var duplicate_service: RefCounted = ProviderServiceScript.new()
	var duplicate_configured := duplicate_service.call("configure", {
		"capabilityMode": "formal",
		"source": "runtime",
		"allowFake": false,
		"providerConfigs": {
			"volcengine-ark": {
				"api_key": "temporary-ark-key",
				"api_models": ["doubao-seed-2-0-lite-260428"],
				"api_model": "doubao-seed-2-0-lite-260428",
			},
		},
	}) as Dictionary
	_expect_equal(
		duplicate_configured.get("ok"),
		true,
		"Ark accepts an inference endpoint id matching a built-in model id",
	)
	var duplicate_model_count := 0
	for model: Dictionary in duplicate_service.call("list_available_models"):
		if (
			String(model.get("providerId", "")) == "volcengine-ark"
			and String(model.get("modelId", "")) == "doubao-seed-2-0-lite-260428"
		):
			duplicate_model_count += 1
	_expect_equal(
		duplicate_model_count,
		1,
		"Ark does not expose duplicate cards when a custom endpoint matches a built-in id",
	)


func _test_multiple_compatible_connections() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CONFIG_TEST_ROOT),
	)
	var request_host := Node.new()
	var provider_service: RefCounted = ProviderServiceScript.new()
	var settings: RefCounted = SettingsServiceScript.new()
	var configured := settings.call(
		"configure_store",
		"%s/multiple-compatible-settings.json" % CONFIG_TEST_ROOT,
	) as Dictionary
	_expect_equal(
		configured.get("ok"),
		true,
		"multiple compatible connection store is configured",
	)
	var bound := settings.call(
		"bind_provider_service",
		provider_service,
		request_host,
	) as Dictionary
	_expect_equal(bound.get("ok"), true, "multiple compatible connection runtime binds")
	var created_first := settings.call(
		"dispatch",
		"provider_settings.create_compatible_connection",
		{"displayName": "公司中转站"},
	) as Dictionary
	_expect_equal(created_first.get("ok"), true, "the first extra relay connection can be created")
	var first_id := String(
		(settings.call("get_view_model") as Dictionary).get("data", {}).get(
			"selectedProviderId",
			"",
		)
	)
	var saved_first := settings.call(
		"dispatch",
		"provider_settings.save_connection",
		{
			"providerId": first_id,
			"baseUrl": "https://relay-one.example/v1",
			"apiKey": "temporary-relay-one-key",
		},
	) as Dictionary
	_expect_equal(saved_first.get("ok"), true, "the first relay keeps its own address and key")
	var first_model := settings.call(
		"dispatch",
		"provider_settings.save_api_model",
		{"providerId": first_id, "apiModel": "shared/model"},
	) as Dictionary
	_expect_equal(first_model.get("ok"), true, "the first relay saves its own model card")
	var created_second := settings.call(
		"dispatch",
		"provider_settings.create_compatible_connection",
		{},
	) as Dictionary
	_expect_equal(created_second.get("ok"), true, "a second extra relay connection can be created")
	var second_id := String(
		(settings.call("get_view_model") as Dictionary).get("data", {}).get(
			"selectedProviderId",
			"",
		)
	)
	_expect(
		not first_id.is_empty() and not second_id.is_empty() and first_id != second_id,
		"each relay connection receives a stable independent identity",
	)
	var saved_second := settings.call(
		"dispatch",
		"provider_settings.save_connection",
		{
			"providerId": second_id,
			"baseUrl": "https://relay-two.example/v1",
			"apiKey": "temporary-relay-two-key",
		},
	) as Dictionary
	_expect_equal(saved_second.get("ok"), true, "the second relay keeps a different address and key")
	var second_model := settings.call(
		"dispatch",
		"provider_settings.save_api_model",
		{"providerId": second_id, "apiModel": "shared/model"},
	) as Dictionary
	_expect_equal(second_model.get("ok"), true, "different relays may expose the same wire model id")
	var projected_first := _provider_from_view_model(
		settings.call("get_view_model") as Dictionary,
		first_id,
	)
	var projected_second := _provider_from_view_model(
		settings.call("get_view_model") as Dictionary,
		second_id,
	)
	_expect_equal(
		projected_first.get("displayName"),
		"公司中转站",
		"a player-defined relay name survives connection saving",
	)
	_expect_equal(
		projected_second.get("displayName"),
		"兼容 · relay-two.example",
		"an unnamed relay receives a readable host-based name",
	)
	var renamed_second := settings.call(
		"dispatch",
		"provider_settings.rename_compatible_connection",
		{"providerId": second_id, "displayName": "备用中转站"},
	) as Dictionary
	_expect_equal(
		renamed_second.get("ok"),
		true,
		"a dynamic compatible connection can be renamed",
	)
	projected_second = _provider_from_view_model(
		settings.call("get_view_model") as Dictionary,
		second_id,
	)
	_expect_equal(
		projected_second.get("displayName"),
		"备用中转站",
		"the renamed connection is projected to the selector",
	)
	_expect_equal(projected_first.get("customGroup"), true, "the first relay stays inside Custom Models")
	_expect_equal(projected_second.get("customGroup"), true, "the second relay stays inside Custom Models")
	provider_service.set("_bindings_by_resident_id", {
		"resident-relay": {
			"mode": "model",
			"providerId": second_id,
			"modelId": "shared/model",
		},
	})
	var blocked_delete := settings.call(
		"dispatch",
		"provider_settings.delete_compatible_connection",
		{"providerId": second_id},
	) as Dictionary
	_expect_equal(
		blocked_delete.get("errorCode"),
		"PROVIDER_CONNECTION_IN_USE",
		"a relay connection assigned to a resident cannot be deleted",
	)
	provider_service.set("_bindings_by_resident_id", {})
	var deleted := settings.call(
		"dispatch",
		"provider_settings.delete_compatible_connection",
		{"providerId": second_id},
	) as Dictionary
	_expect_equal(deleted.get("ok"), true, "an unused relay connection can be deleted")
	_expect_equal(
		(settings.call("get_view_model") as Dictionary).get("data", {}).get(
			"selectedProviderId",
			"",
		),
		first_id,
		"deleting the selected relay stays inside Custom Models and selects the remaining relay",
	)
	_expect_equal(
		_provider_from_view_model(settings.call("get_view_model"), second_id).is_empty(),
		true,
		"deleting one relay preserves the others and removes only its card",
	)
	request_host.free()


func _test_provider_health_isolation() -> void:
	var service: RefCounted = ProviderServiceScript.new()
	var request_host := Node.new()
	service.call("configure", {
		"capabilityMode": "formal",
		"source": "runtime",
		"allowFake": false,
		"providerConfigs": {
			"deepseek": {"api_key": "deepseek-key"},
			"kimi": {"api_key": "kimi-key"},
		},
	}, request_host)
	service.set("_health_by_target", {
		"deepseek|deepseek-v4-flash": {
			"providerId": "deepseek",
			"modelId": "deepseek-v4-flash",
			"status": "available",
			"errorCode": "",
			"retryable": false,
		},
		"kimi|kimi-k3": {
			"providerId": "kimi",
			"modelId": "kimi-k3",
			"status": "available",
			"errorCode": "",
			"retryable": false,
		},
	})
	service.call("configure", {
		"capabilityMode": "formal",
		"source": "runtime",
		"allowFake": false,
		"providerConfigs": {
			"deepseek": {"api_key": "changed-deepseek-key"},
			"kimi": {"api_key": "kimi-key"},
		},
	}, request_host)
	_expect_equal(
		(service.get("_health_by_target") as Dictionary).keys(),
		["kimi|kimi-k3"],
		"reconfiguration retains only unchanged provider health entries",
	)
	var health_by_provider: Dictionary = {}
	for provider: Dictionary in service.call("get_health_snapshot").get("providers", []):
		health_by_provider[String(provider.get("providerId", ""))] = String(
			provider.get("status", ""),
		)
	_expect_equal(
		health_by_provider.get("kimi"),
		"available",
		"changing DeepSeek preserves Kimi availability",
	)
	_expect(
		health_by_provider.get("deepseek") != "available",
		"changing DeepSeek invalidates only DeepSeek health",
	)
	request_host.free()


func _test_local_endpoint_and_model_persistence() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CONFIG_TEST_ROOT),
	)
	var store: RefCounted = ConfigStoreScript.new()
	var configured := store.call(
		"configure",
		"%s/settings.json" % CONFIG_TEST_ROOT,
	) as Dictionary
	_expect_equal(configured.get("ok"), true, "provider config test store is configured")
	var local_config := {
		"schemaVersion": 1,
		"selectedProviderId": "ollama",
		"selectedModelByProvider": {"ollama": "qwen3:8b"},
		"providers": {
			"ollama": {
				"enabled": true,
				"endpoint": "http://localhost:11434/v1",
				"apiModels": ["qwen3:8b", "gemma3:4b"],
			},
		},
	}
	var saved := store.call("save_config", local_config) as Dictionary
	_expect_equal(saved.get("ok"), true, "loopback HTTP endpoint and local model ids are persisted")
	var loaded := store.call("load_config") as Dictionary
	_expect_equal(
		loaded.get("config", {}).get("providers", {}).get("ollama", {}).get("apiModels", []),
		["qwen3:8b", "gemma3:4b"],
		"local model ids survive a config reload",
	)
	var unsafe_config := local_config.duplicate(true)
	unsafe_config["providers"]["ollama"]["endpoint"] = "http://example.com/v1"
	var rejected := store.call("save_config", unsafe_config) as Dictionary
	_expect_equal(
		rejected.get("ok"),
		false,
		"unencrypted remote compatible endpoints remain forbidden",
	)
	var legacy_path := "%s/legacy-settings.json" % CONFIG_TEST_ROOT
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schemaVersion": 1,
		"selectedProviderId": "openai-compatible",
		"selectedModelByProvider": {"openai-compatible": "custom"},
		"providers": {
			"openai-compatible": {
				"enabled": true,
				"endpoint": "https://compatible.example/v1",
				"apiModel": "vendor/legacy-model",
			},
		},
	}))
	legacy_file = null
	var legacy_store: RefCounted = ConfigStoreScript.new()
	legacy_store.call("configure", legacy_path)
	var migrated := legacy_store.call("load_config") as Dictionary
	_expect_equal(migrated.get("ok"), true, "legacy custom model config migrates")
	var migrated_config := migrated.get("config", {}) as Dictionary
	_expect_equal(
		migrated_config.get("providers", {}).get("openai-compatible", {}).get("apiModels", []),
		["vendor/legacy-model"],
		"legacy API model becomes a saved custom model card",
	)
	_expect_equal(
		migrated_config.get("selectedModelByProvider", {}).get("openai-compatible"),
		"vendor/legacy-model",
		"legacy custom selection points at the migrated real model id",
	)


func _test_settings_service_custom_model_flow() -> void:
	var request_host := Node.new()
	var provider_service: RefCounted = ProviderServiceScript.new()
	var settings: RefCounted = SettingsServiceScript.new()
	var configured := settings.call(
		"configure_store",
		"%s/settings-service.json" % CONFIG_TEST_ROOT,
	) as Dictionary
	_expect_equal(configured.get("ok"), true, "settings service test store is configured")
	var bound := settings.call(
		"bind_provider_service",
		provider_service,
		request_host,
	) as Dictionary
	_expect_equal(bound.get("ok"), true, "settings service binds the real provider runtime")
	var discovered_ark := settings.call(
		"_store_discovered_models",
		"volcengine-ark",
		[
			"doubao-seed-2-1-pro-260628",
			"deepseek-v4-pro-260425",
			"glm-5-2-260617",
		],
	) as Dictionary
	_expect_equal(
		discovered_ark.get("ok"),
		true,
		"Ark discovery stores the models returned for the saved API key",
	)
	settings.call("refresh")
	var ark_provider := _provider_from_view_model(
		settings.call("get_view_model") as Dictionary,
		"volcengine-ark",
	)
	var ark_model_ids: Array[String] = []
	var ark_model_labels: Array[String] = []
	for model: Dictionary in ark_provider.get("models", []):
		ark_model_ids.append(String(model.get("modelId", "")))
		ark_model_labels.append(String(model.get("displayName", "")))
	_expect_equal(
		ark_model_ids,
		[
			"doubao-seed-2-1-pro-260628",
			"deepseek-v4-pro-260425",
			"glm-5-2-260617",
		],
		"Ark model cards come only from the discovered account catalog",
	)
	_expect_equal(
		ark_model_labels,
		["豆包 Seed 2.1 Pro", "DeepSeek V4 Pro", "GLM 5.2"],
		"Ark model cards use player-facing names instead of raw API ids",
	)
	var saved_local_connection := settings.call(
		"dispatch",
		"provider_settings.save_connection",
		{
			"providerId": "ollama",
			"baseUrl": "http://localhost:11434/v1",
			"apiKey": "",
		},
	) as Dictionary
	_expect_equal(
		saved_local_connection.get("ok"),
		true,
		"local custom connection saves without an API key",
	)
	var saved_remote_connection := settings.call(
		"dispatch",
		"provider_settings.save_connection",
		{
			"providerId": "openai-compatible",
			"baseUrl": "https://compatible.example/v1",
			"apiKey": "temporary-test-key",
		},
	) as Dictionary
	_expect_equal(
		saved_remote_connection.get("ok"),
		true,
		"remote custom connection saves its address and key together",
	)
	var saved_remote_provider := _provider_from_view_model(
		settings.call("get_view_model") as Dictionary,
		"openai-compatible",
	)
	_expect_equal(
		saved_remote_provider.get("baseUrl"),
		"https://compatible.example/v1",
		"combined connection save projects the normalized address",
	)
	_expect_equal(
		(saved_remote_provider.get("key", {}) as Dictionary).get("saved"),
		true,
		"combined connection save reports only masked credential state",
	)
	var saved_model := settings.call("dispatch", "provider_settings.save_api_model", {
		"providerId": "302-ai",
		"apiModel": "vendor/model-a",
	}) as Dictionary
	_expect_equal(saved_model.get("ok"), true, "302 model id can be saved from settings")
	var model_ids: Array[String] = []
	var view_model := settings.call("get_view_model") as Dictionary
	var provider := _provider_from_view_model(view_model, "302-ai")
	for model: Dictionary in provider.get("models", []):
		model_ids.append(String(model.get("modelId", "")))
	_expect_equal(model_ids, ["vendor/model-a"], "saved 302 model is projected back to the player")
	var saved_local_model := settings.call(
		"dispatch",
		"provider_settings.save_api_model",
		{"providerId": "ollama", "apiModel": "qwen3:8b"},
	) as Dictionary
	_expect_equal(saved_local_model.get("ok"), true, "Ollama model can be saved without an API key")
	var discovered := settings.call(
		"_store_discovered_models",
		"ollama",
		[
			"qwen3:8b",
			"gemma3:4b",
			"qwen3:8b",
			"nomic-embedding-text",
		],
	) as Dictionary
	_expect_equal(discovered.get("ok"), true, "discovered local chat models are saved automatically")
	settings.call("refresh")
	view_model = settings.call("get_view_model") as Dictionary
	provider = _provider_from_view_model(view_model, "ollama")
	model_ids.clear()
	for model: Dictionary in provider.get("models", []):
		model_ids.append(String(model.get("modelId", "")))
	_expect_equal(
		model_ids,
		["qwen3:8b", "gemma3:4b"],
		"discovery saves unique chat models and filters embedding models",
	)
	_expect_equal(
		provider.get("discoveredModels"),
		[],
		"automatic discovery no longer leaves a second manual import list",
	)
	var saved_discovered_model := settings.call(
		"dispatch",
		"provider_settings.save_api_model",
		{"providerId": "ollama", "apiModel": "gemma3:4b"},
	) as Dictionary
	_expect_equal(
		saved_discovered_model.get("ok"),
		true,
		"an automatically discovered model can still be selected",
	)
	var runtime := settings.call("runtime_configuration") as Dictionary
	_expect_equal(runtime.get("providerId"), "ollama", "local model becomes the selected provider")
	_expect_equal(runtime.get("modelId"), "gemma3:4b", "selected discovered model id reaches runtime configuration")
	_expect_equal(runtime.get("authRequired"), false, "local runtime records optional authentication")
	_expect(
		String(runtime.get("errorCode", "")) != "PROVIDER_API_KEY_REQUIRED",
		"missing optional local key never blocks runtime configuration",
	)
	provider_service.set("_bindings_by_resident_id", {
		"resident-a": {
			"mode": "model",
			"providerId": "ollama",
			"modelId": "qwen3:8b",
		},
	})
	var blocked_delete := settings.call(
		"dispatch",
		"provider_settings.delete_api_model",
		{"providerId": "ollama", "apiModel": "qwen3:8b"},
	) as Dictionary
	_expect_equal(
		blocked_delete.get("errorCode"),
		"PROVIDER_API_MODEL_IN_USE",
		"a custom model assigned to a resident cannot be deleted",
	)
	provider_service.set("_bindings_by_resident_id", {})
	var deleted := settings.call(
		"dispatch",
		"provider_settings.delete_api_model",
		{"providerId": "ollama", "apiModel": "qwen3:8b"},
	) as Dictionary
	_expect_equal(deleted.get("ok"), true, "unused custom model can be deleted")
	settings.call("refresh")
	provider = _provider_from_view_model(settings.call("get_view_model"), "ollama")
	model_ids.clear()
	for model: Dictionary in provider.get("models", []):
		model_ids.append(String(model.get("modelId", "")))
	_expect_equal(model_ids, ["gemma3:4b"], "deleting one custom model preserves the others")
	request_host.free()


func _test_custom_model_ui_grouping() -> void:
	var screen := ProviderSettingsScreenScript.new()
	screen.set("_selected_provider_id", "ollama")
	screen.set("_render_data", {
		"providers": [
			{"providerId": "deepseek", "displayName": "DeepSeek"},
			{
				"providerId": "volcengine-ark",
				"displayName": "火山方舟",
				"customModels": true,
				"customGroup": false,
			},
			{
				"providerId": "openai-compatible",
				"displayName": "其他兼容接口",
				"customModels": true,
			},
			{
				"providerId": "ollama",
				"displayName": "Ollama（本地）",
				"customModels": true,
			},
			{
				"providerId": "lm-studio",
				"displayName": "LM Studio（本地）",
				"customModels": true,
			},
			{
				"providerId": "ollama-cloud",
				"displayName": "Ollama Cloud",
				"customModels": true,
			},
		],
	})
	var visible: Array[Dictionary] = screen._visible_providers()
	_expect_equal(visible.size(), 3, "compatible services collapse into one player-facing group")
	_expect_equal(
		visible[2].get("displayName"),
		"自定义模型",
		"the player-facing custom group hides the OpenAI Compatible name",
	)
	_expect_equal(
		visible[2].get("providerId"),
		"ollama",
		"the grouped card keeps the selected custom connection active",
	)
	var visible_names: Array[String] = []
	for provider: Dictionary in visible:
		visible_names.append(String(provider.get("displayName", "")))
	_expect_equal(
		visible_names,
		["DeepSeek", "火山方舟", "自定义模型"],
		"the Custom Models card keeps its stable position near the leading providers",
	)
	_expect_equal(
		(screen._use_composite_desktop(Vector2(1920, 1080))),
		true,
		"1920 desktop keeps the formal composite provider settings layout",
	)
	_expect_equal(
		(visible[2].get("customConnections", []) as Array).size(),
		3,
		"the custom model group hides the empty legacy compatible placeholder",
	)
	var custom_connection_ids: Array[String] = []
	for provider: Dictionary in visible[2].get("customConnections", []) as Array:
		custom_connection_ids.append(String(provider.get("providerId", "")))
	_expect_equal(
		custom_connection_ids,
		["ollama", "ollama-cloud", "lm-studio"],
		"the custom connection selector keeps the approved local-first order",
	)
	screen.free()
	var assignment := ResidentAssignmentServiceScript.new()
	_expect_equal(
		assignment._compact_provider_name("ollama", "Ollama（本地）"),
		"自定义 · Ollama",
		"resident model cards identify custom models and their connection source",
	)


func _provider_from_view_model(view_model: Dictionary, provider_id: String) -> Dictionary:
	var data := view_model.get("data", {}) as Dictionary
	for value: Variant in data.get("providers", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get("providerId", "")) == provider_id
		):
			return value as Dictionary
	return {}
