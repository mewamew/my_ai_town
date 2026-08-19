extends "res://tests/agent/support/OpenAICompatibleProviderTestCase.gd"


const PROVIDER_PATH := "res://agent/model/GenericOpenAICompatibleModelProvider.gd"
const PROVIDER_302_PATH := "res://agent/model/ThreeZeroTwoAIModelProvider.gd"
const OLLAMA_CLOUD_PROVIDER_PATH := "res://agent/model/OllamaCloudModelProvider.gd"


func _initialize() -> void:
	var provider_script := load(PROVIDER_PATH) as Script
	_expect(provider_script != null, "通用 OpenAI Compatible Provider 脚本可加载")
	if provider_script != null:
		_test_generic_conservative_request(provider_script)
		_test_dynamic_profile_disables_reasoning(provider_script)
		_test_base_url_completion(provider_script)
		_test_local_api_key_is_optional(provider_script)
		_test_model_catalog_discovery_contract(provider_script)
		_test_missing_messages_rejected(provider_script)
		_test_undeclared_image_input_rejected(provider_script)
		_test_declared_image_input_allowed(provider_script)
		_test_trace_record_limits_are_independent(provider_script)
	var provider_302_script := load(PROVIDER_302_PATH) as Script
	_expect(provider_302_script != null, "302.AI 专用目录过滤脚本可加载")
	if provider_302_script != null:
		_test_302_town_catalog_filter(provider_302_script)
	var ollama_cloud_script := load(OLLAMA_CLOUD_PROVIDER_PATH) as Script
	_expect(ollama_cloud_script != null, "Ollama Cloud 官方直连脚本可加载")
	if ollama_cloud_script != null:
		_test_ollama_cloud_native_protocol(ollama_cloud_script)
	_finish_suite("GENERIC_OPENAI_COMPATIBLE_PROVIDER_PROTOCOL_PASS")


func _test_generic_conservative_request(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("generic-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-compatible-key",
		"endpoint": "https://compatible.example/v1/chat/completions",
		"api_model": "vendor-model",
	})
	var collector := ResultCollector.new()
	provider.call("request_decision", {"messages": [{"role": "user", "content": "决定"}]}, collector.collect)

	_expect_equal(collector.values, [{"ok": true, "decision": _decision("generic-decision")}], "generic compatible provider returns a neutral decision")
	if transport.requests.size() == 1:
		var request := transport.requests[0]
		var body := request.get("body", {}) as Dictionary
		_expect_equal(request.get("url"), "https://compatible.example/v1/chat/completions", "generic provider uses the configured endpoint")
		_expect_equal(body.keys(), ["model", "messages", "stream"], "generic provider sends only conservative compatible fields")
		_expect_equal(body.get("model"), "vendor-model", "generic provider separates the catalog model from the wire model")
		_expect(not JSON.stringify(body).contains("temporary-compatible-key"), "generic key never enters the body")
	_expect(not JSON.stringify(provider.call("get_debug_snapshot")).contains("temporary-compatible-key"), "generic key never enters debug records")


func _test_base_url_completion(provider_script: Script) -> void:
	var cases := {
		"https://compatible.example": "https://compatible.example/v1/chat/completions",
		"https://compatible.example/v1/": "https://compatible.example/v1/chat/completions",
		"https://compatible.example/v1/chat/completions": "https://compatible.example/v1/chat/completions",
	}
	for base_url: String in cases:
		var transport := FakeTransport.new()
		transport.response = _success_response("base-url-decision")
		var provider: RefCounted = provider_script.new(null, transport, {
			"api_key": "temporary-compatible-key",
			"endpoint": base_url,
			"api_model": "vendor/model-name",
		})
		var collector := ResultCollector.new()
		provider.call(
			"request_decision",
			{"messages": [{"role": "user", "content": "决定"}]},
			collector.collect,
		)
		_expect_equal(
			transport.requests[0].get("url") if transport.requests.size() == 1 else "",
			cases[base_url],
			"generic provider normalizes a saved base URL",
		)
	var preset_transport := FakeTransport.new()
	preset_transport.response = _success_response("preset-url-decision")
	var preset_provider: RefCounted = provider_script.new(null, preset_transport, {
		"api_key": "temporary-compatible-key",
		"api_model": "vendor/model-name",
		"preset_provider_id": "302-ai",
		"preset_default_endpoint": "https://api.302.ai/v1",
	})
	var preset_collector := ResultCollector.new()
	preset_provider.call(
		"request_decision",
		{"messages": [{"role": "user", "content": "决定"}]},
		preset_collector.collect,
	)
	_expect_equal(
		preset_transport.requests[0].get("url") if preset_transport.requests.size() == 1 else "",
		"https://api.302.ai/v1/chat/completions",
		"a provider preset completes its default base URL",
	)


func _test_dynamic_profile_disables_reasoning(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("dynamic-profile-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-compatible-key",
		"endpoint": "http://192.168.1.29:11433/v1",
		"api_model": "llama-local",
		"preset_provider_id": "openai-compatible-2",
		"allow_insecure_http": true,
	})
	provider.call(
		"request_decision",
		{"messages": [{"role": "user", "content": "决定"}]},
		ResultCollector.new().collect,
	)
	_expect_equal(
		transport.requests[0].get("body", {}).get("reasoning_effort")
			if transport.requests.size() == 1
			else null,
		"none",
		"动态兼容连接默认关闭思考，给居民动作 JSON 留出预算",
	)


func _test_local_api_key_is_optional(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("local-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"endpoint": "http://127.0.0.1:11434/v1",
		"api_model": "qwen3:8b",
		"preset_provider_id": "ollama",
		"preset_provider_label": "Ollama（本地）",
		"preset_api_key_required": false,
	})
	var collector := ResultCollector.new()
	provider.call(
		"request_decision",
		{"messages": [{"role": "user", "content": "决定"}]},
		collector.collect,
	)
	_expect_equal(collector.values.size(), 1, "local compatible provider works without a key")
	_expect_equal(transport.requests.size(), 1, "local compatible request reaches transport")
	if transport.requests.size() == 1:
		var headers := transport.requests[0].get("headers", PackedStringArray()) as PackedStringArray
		var body := transport.requests[0].get("body", {}) as Dictionary
		_expect(
			not "\n".join(headers).contains("Authorization:"),
			"local request omits the Authorization header when no key is configured",
		)
		_expect_equal(
			body.get("reasoning_effort"),
			"none",
			"Ollama OpenAI compatibility disables reasoning so resident JSON is not starved",
		)
	var lm_transport := FakeTransport.new()
	lm_transport.response = _success_response("lm-studio-decision")
	var lm_provider: RefCounted = provider_script.new(null, lm_transport, {
		"endpoint": "http://127.0.0.1:1234/v1",
		"api_model": "qwen3.5-9b",
		"preset_provider_id": "lm-studio",
		"preset_provider_label": "LM Studio（本地）",
		"preset_api_key_required": false,
	})
	lm_provider.call(
		"request_decision",
		{"messages": [{"role": "user", "content": "决定"}]},
		ResultCollector.new().collect,
	)
	_expect_equal(
		lm_transport.requests[0].get("body", {}).get("reasoning_effort")
			if lm_transport.requests.size() == 1
			else null,
		"none",
		"LM Studio OpenAI compatibility disables reasoning for resident JSON",
	)


func _test_model_catalog_discovery_contract(provider_script: Script) -> void:
	var provider_302: RefCounted = provider_script.new(null, null, {
		"endpoint": "https://api.302.ai/v1/chat/completions",
		"preset_provider_id": "302-ai",
	})
	_expect_equal(
		provider_302.call("model_catalog_endpoint"),
		"https://api.302.ai/v1/models?llm=1&include_custom_models=1",
		"302 model discovery uses the documented model-list query",
	)
	var local_provider: RefCounted = provider_script.new(null, null, {
		"endpoint": "http://127.0.0.1:11434/v1",
		"preset_provider_id": "ollama",
	})
	_expect_equal(
		local_provider.call("model_catalog_endpoint"),
		"http://127.0.0.1:11434/v1/models",
		"local model discovery uses the standard OpenAI-compatible endpoint",
	)
	var parsed := provider_302.call("_model_catalog_result", {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": 200,
		"body": JSON.stringify({
			"data": [
				{"id": "vendor/model-a"},
				{"id": "vendor/model-b"},
				{"id": "vendor/model-a"},
			],
		}).to_utf8_buffer(),
	}) as Dictionary
	_expect_equal(
		parsed.get("models", []),
		["vendor/model-a", "vendor/model-b"],
		"discovered model ids are validated and deduplicated",
	)
	var alternate_shape := provider_302.call("_model_catalog_result", {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": 200,
		"body": JSON.stringify({
			"models": [
				{"name": "llama-3"},
				{"model": "qwen-local"},
			],
		}).to_utf8_buffer(),
	}) as Dictionary
	_expect_equal(
		alternate_shape.get("models", []),
		["llama-3", "qwen-local"],
		"local model catalog accepts name and model aliases",
	)


func _test_302_town_catalog_filter(provider_script: Script) -> void:
	var provider: RefCounted = provider_script.new(null, null, {
		"endpoint": "https://api.302.ai/v1",
		"preset_provider_id": "302-ai",
	})
	var parsed := provider.call("_model_catalog_result", {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": 200,
		"body": JSON.stringify({
			"data": [
				{"id": "gpt-5.5"},
				{"id": "codex-mini-latest"},
				{"id": "text-embedding-3-large"},
				{"id": "doubao-seed-2-1-pro-260101"},
				{"id": "doubao-seed-2-1-pro-260628"},
				{"id": "kimi-k3"},
				{"id": "some-image-generator"},
			],
		}).to_utf8_buffer(),
	}) as Dictionary
	_expect_equal(
		parsed.get("models", []),
		["gpt-5.5", "kimi-k3", "doubao-seed-2-1-pro-260628"],
		"302.AI keeps only supported resident chat families and the latest dated release",
	)


func _test_ollama_cloud_native_protocol(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _http_response(200, {
		"message": {
			"role": "assistant",
			"content": JSON.stringify(_decision("ollama-cloud-decision")),
		},
		"done": true,
		"done_reason": "stop",
		"prompt_eval_count": 14,
		"eval_count": 8,
	})
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-ollama-cloud-key",
		"endpoint": "https://ollama.com/api",
		"api_model": "gpt-oss:120b",
		"preset_provider_id": "ollama-cloud",
		"preset_provider_label": "Ollama Cloud",
		"preset_default_endpoint": "https://ollama.com/api",
		"preset_api_key_required": true,
	})
	var collector := ResultCollector.new()
	provider.call(
		"request_decision",
		{"messages": [{"role": "user", "content": "决定"}]},
		collector.collect,
	)
	_expect_equal(
		collector.values,
		[{"ok": true, "decision": _decision("ollama-cloud-decision")}],
		"native Ollama Cloud responses reach the resident decision parser",
	)
	_expect_equal(transport.requests.size(), 1, "Ollama Cloud sends one direct request")
	if transport.requests.size() == 1:
		var request := transport.requests[0]
		_expect_equal(
			request.get("url"),
			"https://ollama.com/api/chat",
			"Ollama Cloud uses the documented native chat endpoint",
		)
		_expect_equal(
			request.get("body", {}).get("model"),
			"gpt-oss:120b",
			"Ollama Cloud sends the selected cloud model",
		)
		_expect_equal(
			request.get("body", {}).get("think"),
			"low",
			"GPT-OSS uses its lowest supported native thinking level",
		)
		_expect(
			"Authorization: Bearer temporary-ollama-cloud-key" in request.get(
				"headers",
				PackedStringArray(),
			),
			"Ollama Cloud sends its key only in the authorization header",
		)
	_expect_equal(
		provider.call("model_catalog_endpoint"),
		"https://ollama.com/api/tags",
		"Ollama Cloud discovers models through the documented tags endpoint",
	)
	var catalog := provider.call("_model_catalog_result", {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": 200,
		"body": JSON.stringify({
			"models": [
				{"name": "gpt-oss:120b"},
				{"model": "qwen3-coder:480b-cloud"},
			],
		}).to_utf8_buffer(),
	}) as Dictionary
	_expect_equal(
		catalog.get("models", []),
		["gpt-oss:120b", "qwen3-coder:480b-cloud"],
		"Ollama Cloud parses the official tags response",
	)
	var qwen_provider: RefCounted = provider_script.new(null, FakeTransport.new(), {
		"api_key": "temporary-ollama-cloud-key",
		"endpoint": "https://ollama.com/api",
		"api_model": "qwen3:235b-cloud",
		"preset_provider_id": "ollama-cloud",
		"preset_api_key_required": true,
	})
	_expect_equal(
		qwen_provider.call("_build_request_body", {
			"messages": [{"role": "user", "content": "决定"}],
		}).get("think"),
		false,
		"Ollama Cloud disables thinking when the native model supports it",
	)

func _test_missing_messages_rejected(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("unexpected-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-compatible-key",
		"endpoint": "https://compatible.example/v1/chat/completions",
		"api_model": "vendor-model",
	})
	var collector := ResultCollector.new()
	provider.call("request_decision", {"request_kind": "resident_decision"}, collector.collect)

	_expect_equal(transport.requests.size(), 0, "requests without compiled messages never reach the transport")
	_expect_equal(collector.values, [{"ok": false, "errors": ["模型调用失败"]}], "missing messages return the neutral failure packet")
	var diagnostics := provider.call("get_diagnostics") as Array
	_expect_equal(diagnostics.size(), 1, "missing messages create one diagnostic")
	if diagnostics.size() == 1:
		_expect_equal(diagnostics[0].get("error_type"), "request_validation", "missing messages are classified as request validation")


func _test_undeclared_image_input_rejected(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("unexpected-visual-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-compatible-key",
		"endpoint": "https://compatible.example/v1/chat/completions",
		"api_model": "vendor-model",
		"input_modalities": ["text"],
	})
	var collector := ResultCollector.new()
	provider.call("request_decision", {
		"messages": [{
			"role": "user",
			"content": [
				{"type": "text", "text": "看看这张图"},
				{"type": "image_url", "image_url": {"url": "data:image/png;base64,AA=="}},
			],
		}],
	}, collector.collect)

	_expect_equal(transport.requests.size(), 0, "image input never reaches a text-only model")
	_expect_equal(collector.values, [{"ok": false, "errors": ["模型调用失败"]}], "unsupported image input returns the neutral failure packet")
	var diagnostics := provider.call("get_diagnostics") as Array
	_expect_equal(diagnostics.size(), 1, "unsupported image input creates one diagnostic")
	if diagnostics.size() == 1:
		_expect_equal(diagnostics[0].get("error_type"), "request_validation", "unsupported image input is request validation")


func _test_declared_image_input_allowed(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("visual-custom-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-compatible-key",
		"endpoint": "https://compatible.example/v1/chat/completions",
		"api_model": "visual-vendor-model",
		"input_modalities": ["text", "image"],
	})
	var collector := ResultCollector.new()
	var messages := [{
		"role": "user",
		"content": [
			{"type": "text", "text": "看看这张图"},
			{"type": "image_url", "image_url": {"url": "data:image/png;base64,AA=="}},
		],
	}]
	provider.call("request_decision", {"messages": messages}, collector.collect)

	_expect_equal(collector.values, [{"ok": true, "decision": _decision("visual-custom-decision")}], "declared custom visual input completes")
	_expect_equal(transport.requests.size(), 1, "declared custom visual input reaches the transport")
	if transport.requests.size() == 1:
		_expect_equal(
			transport.requests[0].get("body", {}).get("messages"),
			messages,
			"custom visual content passes through unchanged",
		)


func _test_trace_record_limits_are_independent(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("retained-response")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-compatible-key",
		"endpoint": "https://compatible.example/v1/chat/completions",
		"api_model": "vendor-model",
		"record_limit": 2,
	})
	var collector := ResultCollector.new()
	provider.call(
		"request_decision",
		{"messages": [{"role": "user", "content": "valid request"}]},
		collector.collect,
	)
	provider.call("request_decision", {"request_kind": "invalid-1"}, collector.collect)
	provider.call("request_decision", {"request_kind": "invalid-2"}, collector.collect)
	var snapshot := provider.call("get_debug_snapshot") as Dictionary
	_expect_equal((snapshot.get("model_requests", []) as Array).size(), 2, "model requests use their own record limit")
	_expect_equal((snapshot.get("requests", []) as Array).size(), 1, "provider requests retain sparse history independently")
	_expect_equal((snapshot.get("responses", []) as Array).size(), 1, "responses retain sparse history independently")
	_expect_equal((snapshot.get("diagnostics", []) as Array).size(), 2, "diagnostics use their own record limit")
	_expect_equal((snapshot.get("results", []) as Array).size(), 2, "results use their own record limit")
	_expect_equal(
		(snapshot.get("responses", []) as Array)[0].get("choices", [])[0].get("message", {}).get("content"),
		JSON.stringify(_decision("retained-response")),
		"sparse response history keeps the older completed response",
	)
