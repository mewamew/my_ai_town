extends SceneTree


const SETTINGS_SERVICE := preload(
	"res://world/presentation/ui/TownProviderSettingsService.gd"
)
const SETTINGS_SCENE := preload(
	"res://ui/provider_settings/ProviderSettingsScreen.tscn"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_runtime_custom_model_projection()
	await _test_custom_model_input()
	if _failures.is_empty():
		print("PROVIDER_SETTINGS_REGRESSION_PASS")
		quit(0)
		return
	for failure: String in _failures:
		printerr("PROVIDER_SETTINGS_REGRESSION_FAIL: %s" % failure)
	quit(1)


func _test_runtime_custom_model_projection() -> void:
	var service := SETTINGS_SERVICE.new()
	_expect(
		service.call(
			"_chat_completions_url_is_valid",
			"https://api.siliconflow.cn/v1/chat/completions",
		),
		"complete OpenAI-compatible endpoint is accepted",
	)
	_expect(
		not service.call(
			"_chat_completions_url_is_valid",
			"https://api.siliconflow.cn/v1/",
		),
		"provider API root is rejected before the network request",
	)
	var endpoint_error := service.call(
		"_error_payload",
		"PROVIDER_CHAT_COMPLETIONS_URL_REQUIRED",
		false,
		"Base URL 需要填写完整接口，例如：https://api.siliconflow.cn/v1/chat/completions",
	) as Dictionary
	_expect_equal(
		endpoint_error.get("playerMessage"),
		endpoint_error.get("message"),
		"specific provider error is exposed to the UI renderer",
	)
	service.set("_stored_config", {
		"schemaVersion": 1,
		"selectedProviderId": "openai-compatible",
		"selectedModelByProvider": {"openai-compatible": "custom"},
		"providers": {
			"openai-compatible": {
				"enabled": true,
				"endpoint": "https://compatible.example/v1/chat/completions",
				"apiModel": "vendor/model-v2",
			},
		},
	})
	service.set("_credential_keys", {"openai-compatible": "test-key"})
	var configs := service.call("_provider_configs_for_runtime") as Dictionary
	var custom := configs.get("openai-compatible", {}) as Dictionary
	_expect_equal(
		custom.get("api_model"),
		"vendor/model-v2",
		"custom model name reaches the runtime provider config",
	)


func _test_custom_model_input() -> void:
	root.size = Vector2i(1920, 1080)
	var screen := SETTINGS_SCENE.instantiate() as Control
	root.add_child(screen)
	_expect(screen.apply_view_model(_custom_provider_view_model()), "custom provider VM applies")
	await process_frame
	await process_frame
	var input := screen.find_child("ModelNameInput", true, false) as LineEdit
	var save := screen.find_child("SaveModelNameButton", true, false) as Button
	var base_url := screen.find_child("BaseUrlInput", true, false) as LineEdit
	_expect(input != null and input.editable, "custom model name input is editable")
	_expect(save != null, "custom model name has an explicit save action")
	_expect(
		base_url != null
		and base_url.placeholder_text.contains("https://api.siliconflow.cn/v1/chat/completions")
		and base_url.tooltip_text.contains("完整"),
		"custom Base URL field provides a complete API example",
	)
	if input != null and save != null:
		_expect(
			input.get_theme_stylebox("normal") is StyleBoxEmpty,
			"composite model input reuses the card slot without a second frame",
		)
		_expect_equal(
			save.text,
			"保存模型名称",
			"composite save action has an explicit label",
		)
		_expect(
			not input.get_global_rect().intersects(save.get_global_rect()),
			"model input and save action do not overlap",
		)
		var dispatched: Array[Dictionary] = []
		screen.intent_requested.connect(func(intent: StringName, payload: Dictionary) -> void:
			dispatched.append({"intent": String(intent), "payload": payload.duplicate(true)})
		)
		input.text = "vendor/model-v3"
		input.text_changed.emit(input.text)
		_expect(not save.disabled, "typing a model name enables save")
		save.pressed.emit()
		_expect_equal(dispatched.size(), 1, "model name save dispatches once")
		if not dispatched.is_empty():
			_expect_equal(
				dispatched[0].get("intent"),
				"provider_settings.save_api_model",
				"model name uses the dedicated save intent",
			)
			var payload := dispatched[0].get("payload", {}) as Dictionary
			_expect_equal(payload.get("apiModel"), "vendor/model-v3", "typed model is submitted")
	screen.queue_free()
	await process_frame


func _custom_provider_view_model() -> Dictionary:
	var actions := {}
	for key: String in [
		"back", "selectProvider", "setProviderEnabled", "saveKey", "deleteKey",
		"saveBaseUrl", "saveApiModel", "selectModel", "checkConnection",
	]:
		actions[key] = {
			"intent": "provider_settings.%s" % key,
			"enabled": true,
			"disabledReason": "",
		}
	return {
		"scope": "provider_settings",
		"status": "ready",
		"revision": 1,
		"data": {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": false,
			"pageTitle": "模型设置",
			"selectedProviderId": "openai-compatible",
			"formalStatusLabel": "待检查",
			"providers": [{
				"providerId": "openai-compatible",
				"displayName": "OpenAI Compatible",
				"enabled": true,
				"external": true,
				"key": {"saved": true, "maskedValue": "••••", "status": "saved", "errorCode": ""},
				"baseUrl": "https://compatible.example/v1/chat/completions",
				"apiModel": "vendor/model-v2",
				"models": [{
					"modelId": "custom",
					"displayName": "自定义模型",
					"capabilities": ["decision_json", "dialogue"],
					"enabled": true,
				}],
				"connection": {"status": "unchecked", "label": "待检查", "message": ""},
			}],
			"summary": {"availableProviderCount": 0, "enabledModelCount": 1},
		},
		"actions": actions,
		"operation": {
			"requestId": "",
			"intent": "",
			"status": "idle",
			"submittedAtMsec": 0,
			"completedAtMsec": 0,
		},
		"error": null,
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s: expected=%s actual=%s" % [message, expected, actual])
