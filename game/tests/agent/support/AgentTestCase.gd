class_name AgentTestCase
extends SceneTree


const TestFormat := preload("res://tests/agent/support/AgentTestFormat.gd")
const _BaseUserTestDataCleaner := preload("res://tests/support/UserTestDataCleaner.gd")

var _failures: Array[String] = []
var _assertion_context: Dictionary = {}


func _set_assertion_context(context: Dictionary) -> void:
	_assertion_context = context.duplicate(true)


func _clear_assertion_context() -> void:
	_assertion_context.clear()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_record_failure(message, "expect_true", true, condition)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_record_failure(message, "expect_equal", expected, actual)


func _expect_ok(result: Dictionary, message: String) -> void:
	if result.get("ok") == true:
		return
	_record_failure(message, "expect_ok", {"ok": true}, result)


func _accepted_decision_result(decision: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"decision": decision.duplicate(true),
		"actionIdRepaired": false,
		"staleConversationReplyDiscarded": false,
		"socialResponseErrors": [],
		"socialAttentionErrors": [],
		"socialRequestErrors": [],
		"conversationFollowUpErrors": [],
	}


func _expect_error_contains(result: Dictionary, fragment: String, message: String) -> void:
	var errors: Variant = result.get("errors", [])
	if _errors_contain(errors, fragment):
		return
	_record_failure(
		message,
		"expect_error_contains",
		{"errors_contain": fragment},
		result,
	)


func _errors_contain(errors: Variant, fragment: String) -> bool:
	if typeof(errors) != TYPE_ARRAY:
		return false
	for error: Variant in errors as Array:
		if String(error).contains(fragment):
			return true
	return false


func _record_failure(
	message: String,
	assertion: String,
	expected: Variant,
	actual: Variant,
) -> void:
	_failures.append(TestFormat.failure(
		String(get_script().resource_path),
		message,
		assertion,
		expected,
		actual,
		get_stack(),
		_assertion_context,
	))


func _finish_suite(pass_label: String, cleanup_paths: Array[String] = []) -> void:
	for path: String in cleanup_paths:
		if not _BaseUserTestDataCleaner.remove_tree(path):
			_record_failure(
				"测试隔离目录清理失败",
				"cleanup",
				true,
				{"path": path, "removed": false},
			)
	_prepare_project_shutdown()
	if _failures.is_empty():
		print(pass_label)
		call_deferred("_quit_after_shutdown", 0)
		return
	for failure: String in _failures:
		printerr(failure)
	call_deferred("_quit_after_shutdown", 1)


func _prepare_project_shutdown() -> void:
	shutdown_project_autoloads(self)


static func shutdown_project_autoloads(tree: SceneTree) -> void:
	var scene_root := tree.get_root()
	if scene_root == null:
		return
	var game_flow_host := scene_root.get_node_or_null("GameFlowHost")
	if game_flow_host != null:
		if game_flow_host.has_method("prepare_shutdown"):
			game_flow_host.call("prepare_shutdown")
		game_flow_host.free()
	var audio_controller := scene_root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	if audio_controller != null and is_instance_valid(audio_controller):
		audio_controller.free()


func _quit_after_shutdown(exit_code: int) -> void:
	await process_frame
	_prepare_project_shutdown()
	# 音频线程需要与正式退出流程相同的释放窗口，避免只剩播放对象的假通过。
	await create_timer(0.6, true, false, true).timeout
	quit(exit_code)
