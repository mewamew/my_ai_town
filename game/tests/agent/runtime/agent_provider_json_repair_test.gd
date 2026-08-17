extends SceneTree


const PROVIDER := preload("res://agent/model/OpenAICompatibleModelProvider.gd")
const AgentTestCaseScript := preload(
	"res://tests/agent/support/AgentTestCase.gd"
)

var _failures: Array[String] = []
var _results: Array[Dictionary] = []


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
	_finish()


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
