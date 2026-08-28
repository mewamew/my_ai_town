extends SceneTree


const TestCli := preload("res://tests/agent/support/AgentTestCli.gd")
const AgentTestCaseScript := preload("res://tests/agent/support/AgentTestCase.gd")
const TEST_ROOT := "res://tests/agent"
const LIVE_ROOT := "res://tests/agent/provider/live"
const PROVIDER_TEST_NO_NETWORK_ENV := "AI_TOWN_PROVIDER_TEST_NO_NETWORK"
const FORWARDED_LIVE_OPTIONS := [
	"model",
	"connectivity-only",
	"behavior-only",
	"env-file",
	"timeout-seconds",
	"delay-ms",
]
const LIVE_PROVIDER_FILE_STEMS := {
	"deepseek": [
		"deepseek_live_test.gd",
		"resident_memory_deepseek_live_reaction_test.gd",
	],
	"volcengine-ark": ["volcengine_ark_live_test.gd"],
	"aliyun-bailian": ["alibaba_bailian_live_test.gd"],
	"kimi": ["kimi_live_test.gd"],
	"zhipu-glm": ["zhipu_glm_live_test.gd"],
	"xiaomi-mimo": ["xiaomi_mimo_live_test.gd"],
	"openai-compatible": ["openai_compatible_live_test.gd"],
}

var _options: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_options = TestCli.parse_options(OS.get_cmdline_user_args())
	var option_error := _option_error()
	if not option_error.is_empty():
		printerr("AGENT_TEST_RUNNER_CONFIG_FAIL: %s" % option_error)
		await _quit_after_project_shutdown(2)
		return
	var suites: Array[String] = []
	_collect_suites(TEST_ROOT, suites)
	suites.sort()
	suites = _filter_suites(suites)
	if _options.has("list"):
		for suite: String in suites:
			print(suite.trim_prefix("%s/" % TEST_ROOT))
		await _quit_after_project_shutdown(0)
		return
	if suites.is_empty():
		printerr("AGENT_TEST_RUNNER_CONFIG_FAIL: 没有找到符合条件的测试")
		await _quit_after_project_shutdown(2)
		return

	var started_at := Time.get_ticks_msec()
	var passed := 0
	var failed := 0
	for suite: String in suites:
		var result := _run_suite(suite)
		if result.get("ok") == true:
			passed += 1
			print("[PASS] %s (%d ms)" % [
				suite.trim_prefix("%s/" % TEST_ROOT),
				int(result.get("elapsed_ms", 0)),
			])
		else:
			failed += 1
			printerr("[SUITE FAIL] %s (%d ms, exit=%d)" % [
				suite.trim_prefix("%s/" % TEST_ROOT),
				int(result.get("elapsed_ms", 0)),
				int(result.get("exit_code", -1)),
			])
			var output := String(result.get("output", "")).strip_edges()
			if not output.is_empty():
				printerr(output)

	var elapsed_ms := Time.get_ticks_msec() - started_at
	print("AGENT_TEST_SUMMARY passed=%d failed=%d total=%d elapsed_ms=%d online_llm=%s" % [
		passed,
		failed,
		suites.size(),
		elapsed_ms,
		str(_options.has("online-llm")).to_lower(),
	])
	await _quit_after_project_shutdown(0 if failed == 0 else 1)


func _quit_after_project_shutdown(exit_code: int) -> void:
	AgentTestCaseScript.shutdown_project_autoloads(self)
	await process_frame
	AgentTestCaseScript.shutdown_project_autoloads(self)
	await create_timer(0.6, true, false, true).timeout
	quit(exit_code)


func _run_suite(suite: String) -> Dictionary:
	var arguments := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		suite,
	])
	if suite.begins_with(LIVE_ROOT):
		arguments.append("--")
		for option_name: String in FORWARDED_LIVE_OPTIONS:
			if not _options.has(option_name):
				continue
			var value: Variant = _options[option_name]
			arguments.append(
				"--%s" % option_name
				if value is bool and bool(value)
				else "--%s=%s" % [option_name, value]
			)
	var output: Array = []
	var started_at := Time.get_ticks_msec()
	var previous_no_network := OS.get_environment(PROVIDER_TEST_NO_NETWORK_ENV)
	if not suite.begins_with(LIVE_ROOT):
		# 离线子测试不得继承玩家本机已保存的 Provider 连接状态并发起健康检查。
		# 生产设置服务已经提供这项测试开关；runner 负责在子进程范围内启用。
		OS.set_environment(PROVIDER_TEST_NO_NETWORK_ENV, "1")
	var exit_code := OS.execute(
		OS.get_executable_path(),
		arguments,
		output,
		true,
	)
	if previous_no_network.is_empty():
		OS.unset_environment(PROVIDER_TEST_NO_NETWORK_ENV)
	else:
		OS.set_environment(PROVIDER_TEST_NO_NETWORK_ENV, previous_no_network)
	var text_output := "\n".join(output)
	var script_error := (
		text_output.contains("SCRIPT ERROR:")
		or text_output.contains("Parse Error:")
		or text_output.contains("Failed to load script \"res://tests/agent/")
	)
	# 子测试输出被本 runner 捕获、不会完整透传给外层，普通引擎错误
	# （行首 ERROR:，如脱树 get_tree、退出资源泄漏）必须在这里判定。
	# 注意 Godot 4.7 中 push_error 输出同样是行首 ERROR:——离线套件
	# 的测试在通过路径上不应触发 push_error。
	var engine_error := false
	for line: String in text_output.split("\n"):
		if line.begins_with("ERROR:"):
			engine_error = true
			break
	return {
		"ok": exit_code == 0 and not script_error and not engine_error,
		"exit_code": exit_code,
		"engine_error": engine_error,
		"elapsed_ms": Time.get_ticks_msec() - started_at,
		"output": text_output,
	}


func _collect_suites(directory_path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = directory.get_next()
			continue
		var path := directory_path.path_join(entry)
		if directory.current_is_dir():
			_collect_suites(path, result)
		elif entry.ends_with("_test.gd"):
			result.append(path)
		entry = directory.get_next()
	directory.list_dir_end()


func _filter_suites(suites: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var group_text := String(_options.get("group", "")).strip_edges()
	var groups: Array[String] = []
	for group_value: String in group_text.split(",", false):
		var group := group_value.strip_edges()
		if not group.is_empty() and not groups.has(group):
			groups.append(group)
	var suite_filter := String(_options.get("suite", "")).strip_edges()
	var provider_filter := String(_options.get("provider", "")).strip_edges()
	for suite: String in suites:
		var is_live := suite.begins_with(LIVE_ROOT)
		if is_live and not _options.has("online-llm"):
			continue
		var relative_path := suite.trim_prefix("%s/" % TEST_ROOT)
		var provider_suite_stems: Array = []
		if not provider_filter.is_empty():
			provider_suite_stems = LIVE_PROVIDER_FILE_STEMS[provider_filter]
		if is_live and not provider_filter.is_empty() and not provider_suite_stems.has(
			suite.get_file()
		):
			continue
		var group_matches := groups.is_empty()
		for group: String in groups:
			if relative_path.begins_with("%s/" % group):
				group_matches = true
				break
		if not group_matches:
			continue
		if not suite_filter.is_empty() and not relative_path.contains(suite_filter):
			continue
		result.append(suite)
	return result


func _option_error() -> String:
	if _options.has("provider") and not _options.has("online-llm"):
		return "--provider 只用于 --online-llm 联网测试"
	var provider_id := String(_options.get("provider", "")).strip_edges()
	if not provider_id.is_empty() and not LIVE_PROVIDER_FILE_STEMS.has(provider_id):
		return "未知联网 Provider：%s" % provider_id
	return ""
