extends "res://tests/agent/support/OpenAICompatibleProviderTestCase.gd"


const PROVIDER_PATH := "res://agent/model/MiniMaxModelProvider.gd"


func _initialize() -> void:
	var provider_script := load(PROVIDER_PATH) as Script
	_expect(provider_script != null, "MiniMax Provider script loads")
	if provider_script != null:
		_test_m3_request(provider_script)
		_test_m2_compatibility(provider_script)
		_test_unknown_model_rejected(provider_script)
	_finish_suite("MINIMAX_PROVIDER_PROTOCOL_PASS")


func _test_m3_request(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("minimax-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-minimax-key",
		"model": "MiniMax-M3",
		"input_modalities": ["text", "image"],
	})
	var collector := ResultCollector.new()
	var messages := [{
		"role": "user",
		"content": [
			{"type": "image_url", "image_url": {"url": "data:image/png;base64,AA=="}},
			{"type": "text", "text": "只返回决定 JSON"},
		],
	}]
	provider.call(
		"request_decision",
		{"messages": messages},
		collector.collect,
	)

	_expect_equal(
		collector.values,
		[{"ok": true, "decision": _decision("minimax-decision")}],
		"MiniMax returns a provider-neutral decision",
	)
	_expect_equal(transport.requests.size(), 1, "MiniMax sends one request")
	if transport.requests.size() == 1:
		var request := transport.requests[0]
		var body := request.get("body", {}) as Dictionary
		_expect_equal(
			request.get("url"),
			"https://api.minimaxi.com/v1/chat/completions",
			"MiniMax uses the official mainland endpoint",
		)
		_expect_equal(body.get("model"), "MiniMax-M3", "MiniMax sends M3 through the compatible endpoint")
		_expect_equal(body.get("messages"), messages, "MiniMax M3 visual content passes through unchanged")
		_expect_equal(body.get("reasoning_split"), true, "MiniMax separates reasoning from answer content")
		_expect_equal(body.get("thinking"), {"type": "disabled"}, "MiniMax M3 disables thinking for short structured decisions")
		_expect_equal(body.get("max_completion_tokens"), 2048, "MiniMax uses its documented output token field")
		_expect(not body.has("max_tokens"), "MiniMax omits the legacy max_tokens field")
		_expect(not JSON.stringify(body).contains("temporary-minimax-key"), "MiniMax key never enters the body")

	var maximum_request_collector := ResultCollector.new()
	provider.call(
		"request_decision",
		{
			"messages": [{"role": "user", "content": "验证 M3 输出上限"}],
			"max_tokens": 600000,
		},
		maximum_request_collector.collect,
	)
	_expect_equal(
		maximum_request_collector.values,
		[{"ok": true, "decision": _decision("minimax-decision")}],
		"MiniMax M3 accepts a second structured request",
	)
	_expect_equal(transport.requests.size(), 2, "MiniMax accepts a second request")
	if transport.requests.size() == 2:
		var maximum_request := transport.requests[1]
		var maximum_body := maximum_request.get("body", {}) as Dictionary
		_expect_equal(
			maximum_body.get("max_completion_tokens"),
			524288,
			"MiniMax M3 clamps output to its documented 512K maximum",
		)


func _test_m2_compatibility(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("minimax-m2-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-minimax-key",
		"model": "MiniMax-M2.7",
	})
	var collector := ResultCollector.new()
	provider.call(
		"request_decision",
		{
			"messages": [{"role": "user", "content": "保留 M2 兼容性"}],
			"max_tokens": 524288,
		},
		collector.collect,
	)
	_expect_equal(
		collector.values,
		[{"ok": true, "decision": _decision("minimax-m2-decision")}],
		"MiniMax keeps M2.7 available",
	)
	_expect_equal(transport.requests.size(), 1, "MiniMax M2.7 sends one request")
	if transport.requests.size() == 1:
		var body := transport.requests[0].get("body", {}) as Dictionary
		_expect_equal(body.get("model"), "MiniMax-M2.7", "MiniMax keeps the selected M2 model id")
		_expect_equal(body.get("max_completion_tokens"), 204800, "MiniMax M2 keeps its documented 200K output maximum")
		_expect(not body.has("thinking"), "MiniMax omits the M3-only thinking option for M2 models")


func _test_unknown_model_rejected(provider_script: Script) -> void:
	var provider: RefCounted = provider_script.new(null, null, {
		"api_key": "temporary-minimax-key",
		"model": "MiniMax-unknown",
	})
	_expect(
		_errors_contain(provider.call("validate_configuration"), "不支持模型"),
		"MiniMax rejects unknown models",
	)
