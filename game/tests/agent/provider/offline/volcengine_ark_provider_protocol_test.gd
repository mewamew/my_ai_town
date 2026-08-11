extends "res://tests/agent/support/OpenAICompatibleProviderTestCase.gd"


const PROVIDER_PATH := "res://agent/model/VolcengineArkModelProvider.gd"


func _initialize() -> void:
	var provider_script := load(PROVIDER_PATH) as Script
	_expect(provider_script != null, "火山方舟 Provider 脚本可加载")
	if provider_script != null:
		_test_ark_request(provider_script)
		_test_ark_model_catalog(provider_script)
		_test_ark_overdue_error(provider_script)
	_finish_suite("VOLCENGINE_ARK_PROVIDER_PROTOCOL_PASS")


func _test_ark_request(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("ark-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-ark-key",
		"model": "doubao-seed-2-1-turbo-260628",
		"input_modalities": ["text", "image"],
	})
	var collector := ResultCollector.new()
	var messages := [{
		"role": "user",
		"content": [
			{"type": "image_url", "image_url": {"url": "https://example.invalid/image.png"}},
			{"type": "text", "text": "只返回决定 JSON"},
		],
	}]
	provider.call("request_decision", {"messages": messages}, collector.collect)

	_expect_equal(collector.values, [{"ok": true, "decision": _decision("ark-decision")}], "Ark returns a neutral decision")
	_expect_equal(transport.requests.size(), 1, "Ark sends one request")
	if transport.requests.size() == 1:
		var request := transport.requests[0]
		var body := request.get("body", {}) as Dictionary
		_expect_equal(request.get("url"), "https://ark.cn-beijing.volces.com/api/v3/chat/completions", "Ark uses the Beijing compatible endpoint")
		_expect_equal(body.get("model"), "doubao-seed-2-1-turbo-260628", "Ark sends the selected model")
		_expect_equal(body.get("messages"), messages, "Ark visual content passes through unchanged")
		_expect_equal(body.get("thinking"), {"type": "disabled"}, "Ark uses conservative non-thinking mode")
		_expect(not body.has("response_format"), "Ark avoids an unverified structured-output field")

	var third_party_transport := FakeTransport.new()
	third_party_transport.response = _success_response("third-party-decision")
	var third_party_provider: RefCounted = provider_script.new(
		null,
		third_party_transport,
		{
			"api_key": "temporary-ark-key",
			"model": "kimi-k2-thinking-251104",
		},
	)
	var third_party_collector := ResultCollector.new()
	third_party_provider.call(
		"request_decision",
		{"messages": [{"role": "user", "content": "只返回决定 JSON"}]},
		third_party_collector.collect,
	)
	_expect_equal(
		third_party_collector.values,
		[{"ok": true, "decision": _decision("third-party-decision")}],
		"Ark returns third-party decisions without Doubao-only options",
	)
	_expect_equal(
		third_party_transport.requests.size(),
		1,
		"Ark sends one third-party request",
	)
	if third_party_transport.requests.size() == 1:
		var third_party_body := (
			third_party_transport.requests[0].get("body", {}) as Dictionary
		)
		_expect_equal(
			third_party_body.get("model"),
			"kimi-k2-thinking-251104",
			"Ark sends the selected third-party model id",
		)
		_expect(
			not third_party_body.has("thinking"),
			"Ark does not force Doubao thinking options onto third-party models",
		)

func _test_ark_overdue_error(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _http_response(403, {
		"code": "AccountOverdueError",
		"message": "Account overdue",
	})
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-ark-key",
		"model": "doubao-account-model",
	})
	var collector := ResultCollector.new()
	provider.call("request_decision", {"messages": [{"role": "user", "content": "决定 JSON"}]}, collector.collect)
	var diagnostics := provider.call("get_diagnostics") as Array
	_expect_equal(diagnostics.size(), 1, "Ark provider errors create one diagnostic")
	if diagnostics.size() == 1:
		_expect_equal(diagnostics[0].get("error_type"), "billing", "Ark overdue errors are classified as billing")
		_expect_equal(diagnostics[0].get("retryable"), false, "Ark overdue errors are not retried")
		_expect_equal(diagnostics[0].get("provider_error_message"), "Account overdue", "Ark top-level error message is retained")


func _test_ark_model_catalog(provider_script: Script) -> void:
	var provider: RefCounted = provider_script.new(null, null, {
		"api_key": "temporary-ark-key",
	})
	_expect_equal(
		provider.call("model_catalog_endpoint"),
		"https://ark.cn-beijing.volces.com/api/v3/models",
		"Ark derives its model catalog from the original chat endpoint",
	)
	var parsed := provider.call("_model_catalog_result", {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": 200,
		"body": JSON.stringify({
			"data": [
				{"id": "doubao-seed-2-1-pro-260528"},
				{"id": "doubao-seed-2-1-pro-260628"},
				{"id": "doubao-seed-2-1-turbo-260628"},
				{"id": "doubao-seed-character-251128"},
				{"id": "doubao-seed-character-260628"},
				{"id": "deepseek-v4-pro-260425"},
				{"id": "deepseek-v4-flash-ga-260731"},
				{"id": "kimi-k2-thinking-251104"},
				{"id": "glm-5-2-260617"},
				{"id": "qwen3-32b-20250429"},
				{"id": "mistral-7b-instruct-v0.2"},
				{"id": "deepseek-r1-distill-qwen-32b-250120"},
				{"id": "deepseek-v3-2-251201"},
				{"id": "doubao-seed-code-preview-251028"},
				{"id": "doubao-seed-character-260628"},
				{"id": "doubao-seedream-5-0-260128"},
				{"id": "doubao-seedance-2-0-260128"},
				{"id": "doubao-embedding-vision-251215"},
				{"id": "hyper3d-gen2-260112"},
				{"id": "doubao-pro-32k-241215"},
			],
		}).to_utf8_buffer(),
	}) as Dictionary
	_expect_equal(
		parsed.get("models", []),
		[
			"doubao-seed-2-1-pro-260628",
			"doubao-seed-2-1-turbo-260628",
			"doubao-seed-character-260628",
			"deepseek-v4-pro-260425",
			"deepseek-v4-flash-ga-260731",
			"glm-5-2-260617",
		],
		"Ark keeps only the current models proven usable through the chat API",
	)
