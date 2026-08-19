extends SceneTree


const PROVIDER := preload("res://agent/model/OpenAICompatibleModelProvider.gd")
const AgentTestCaseScript := preload(
	"res://tests/agent/support/AgentTestCase.gd"
)

var _failures: Array[String] = []
var _results: Array[Dictionary] = []
var _thinking_results: Array[Dictionary] = []


func _initialize() -> void:
	AgentTestCaseScript.shutdown_project_autoloads(self)
	var provider := PROVIDER.new(null, null, {
		"api_key": "test-only",
		"model": "test-model",
	})
	var decision := {
		"decision_id": "repair-1",
		"handling": "replace_current",
		"action": {
			"action_id": "repair-action",
			"type": "待着",
		},
	}
	var malformed_content := "```json\n%s\n```" % JSON.stringify(decision)
	var response := {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": 200,
		"body": JSON.stringify({
			"choices": [{
				"finish_reason": "stop",
				"message": {"content": malformed_content},
			}],
		}).to_utf8_buffer(),
	}
	provider.call(
		"_handle_transport_result",
		response,
		Callable(self, "_collect"),
		Time.get_ticks_msec(),
		{"url": "test://provider"},
	)
	_expect_equal(_results.size(), 1, "外层代码围栏不会阻塞决定")
	if _results.size() == 1:
		_expect_equal(_results[0].get("ok"), true, "修复后的 JSON 仍通过 Provider")
		_expect_equal(
			_results[0].get("decision"),
			decision,
			"修复只去掉外层噪声，不改动决定内容",
		)
	var diagnostics := provider.call("get_diagnostics") as Array
	_expect_equal(diagnostics.size(), 1, "修复过程留下内部诊断记录")
	if diagnostics.size() == 1:
		_expect_equal(
			(diagnostics[0] as Dictionary).get("json_repaired"),
			true,
			"诊断标记本地 JSON 修复",
		)
	var thinking_provider := PROVIDER.new(null, null, {
		"api_key": "test-only",
		"model": "test-model",
	})
	var thinking_response := {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": 200,
		"body": JSON.stringify({
			"choices": [{
				"finish_reason": "stop",
				"message": {
					"reasoning_content": "先分析，但不应进入居民动作。",
					"content": (
						"<think>{\"wrong\":true}</think>\n%s"
						% JSON.stringify(decision)
					),
				},
			}],
		}).to_utf8_buffer(),
	}
	thinking_provider.call(
		"_handle_transport_result",
		thinking_response,
		Callable(self, "_collect_thinking"),
		Time.get_ticks_msec(),
		{"url": "test://thinking"},
	)
	_expect_equal(_thinking_results.size(), 1, "思考字段和 think 标签不会阻塞决定")
	if _thinking_results.size() == 1:
		_expect_equal(
			_thinking_results[0].get("decision"),
			decision,
			"解析优先使用清理后的最终 content",
		)
	var thinking_diagnostics := thinking_provider.call("get_diagnostics") as Array
	if thinking_diagnostics.size() == 1:
		_expect_equal(
			(thinking_diagnostics[0] as Dictionary).get("reasoning_present"),
			true,
			"诊断标记独立 reasoning_content",
		)
		_expect_equal(
			(thinking_diagnostics[0] as Dictionary).get("thinking_block_removed"),
			true,
			"诊断标记清理 think 标签",
		)
	var reasoning_only_provider := PROVIDER.new(null, null, {
		"api_key": "test-only",
		"model": "test-model",
	})
	reasoning_only_provider.call(
		"_handle_transport_result",
		{
			"result": HTTPRequest.RESULT_SUCCESS,
			"status_code": 200,
			"body": JSON.stringify({
				"choices": [{
					"finish_reason": "stop",
					"message": {
						"reasoning_content": "只有思考，没有最终回答。",
						"content": "",
					},
				}],
			}).to_utf8_buffer(),
		},
		Callable(self, "_collect_reasoning_only"),
		Time.get_ticks_msec(),
		{"url": "test://reasoning-only"},
	)
	var reasoning_only_diagnostics := reasoning_only_provider.call(
		"get_diagnostics",
	) as Array
	_expect_equal(
		reasoning_only_diagnostics[0].get("error_type")
			if reasoning_only_diagnostics.size() == 1
			else "",
		"reasoning_only_response",
		"只有思考内容时返回明确诊断",
	)
	_finish()


func _collect_thinking(result: Dictionary) -> void:
	_thinking_results.append(result.duplicate(true))


func _collect_reasoning_only(_result: Dictionary) -> void:
	pass


func _collect(result: Dictionary) -> void:
	_results.append(result.duplicate(true))


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append(
			"%s: expected %s, got %s" % [message, expected, actual]
		)


func _finish() -> void:
	var exit_code := 0 if _failures.is_empty() else 1
	if _failures.is_empty():
		print("AGENT_PROVIDER_JSON_REPAIR_PASS")
	else:
		for failure: String in _failures:
			printerr("AGENT_PROVIDER_JSON_REPAIR_FAIL: %s" % failure)
	await _prepare_shutdown()
	quit(exit_code)


func _prepare_shutdown() -> void:
	AgentTestCaseScript.shutdown_project_autoloads(self)
	await create_timer(0.6, true, false, true).timeout
