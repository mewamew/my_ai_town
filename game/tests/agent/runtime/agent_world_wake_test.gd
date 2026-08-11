extends "res://tests/agent/support/AgentTestCase.gd"


const AGENT_SYSTEM_SCRIPT_PATH := "res://agent/AgentSystem.gd"
const SCRIPTED_MODEL_SCRIPT_PATH := "res://tests/agent/support/ScriptedModelProvider.gd"
const UserTestDataCleanerScript := preload("res://tests/support/UserTestDataCleaner.gd")

var _memory_system_counter := 0
var _memory_test_run_id := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
var _test_root := "user://tests/agent-minimal-loop/%s" % _memory_test_run_id


class ResultCollector:
	var values: Array[Dictionary] = []

	func collect(value: Dictionary) -> void:
		values.append(value.duplicate(true))


func _initialize() -> void:
	_test_same_name_residents_use_distinct_ids()
	_test_runtime_owns_initialization_snapshot()
	_test_runtime_model_provider_can_be_replaced()
	_test_invalid_world_facts_do_not_reach_model()
	_test_talk_targets_resident_id()
	_test_runtime_storage_seams_reject_project_paths()
	_finish_suite("AGENT_WORLD_WAKE_PASS", [_test_root])


func _test_same_name_residents_use_distinct_ids() -> void:
	var agent_system: RefCounted = _new_agent_system()
	var first_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	var second_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	var first := _initialization()
	var second := _initialization()
	first["residents"][0]["name"] = "林岚"
	second["me"]["resident_id"] = "resident-lin-lan-2"
	second["residents"][0]["resident_id"] = "resident-tang-xiao-man-2"
	second["residents"][0]["name"] = "林岚"
	var first_result: Dictionary = agent_system.call("initialize_resident", first, first_model)
	var second_result: Dictionary = agent_system.call("initialize_resident", second, second_model)
	_expect_equal(
		first_result,
		{"ok": true, "resident_id": "resident-lin-lan", "resident_name": "林岚"},
		"first resident initializes with a stable id",
	)
	_expect_equal(
		second_result,
		{"ok": true, "resident_id": "resident-lin-lan-2", "resident_name": "林岚"},
		"same-name resident initializes independently under another id",
	)
	first_model.call("queue_decision", _stay_decision("same-name-1", "same-name-action-1"))
	second_model.call("queue_decision", _stay_decision("same-name-2", "same-name-action-2"))
	var first_results := ResultCollector.new()
	var second_results := ResultCollector.new()
	agent_system.call(
		"request_decision",
		"resident-lin-lan",
		_wake_packet("same-name-1"),
		first_results.collect,
	)
	agent_system.call(
		"request_decision",
		"resident-lin-lan-2",
		_wake_packet("same-name-2"),
		second_results.collect,
	)
	_expect_equal(
		first_results.values[0].get("decision", {}).get("action", {}).get("action_id"),
		"same-name-action-1",
		"first same-name resident receives only its own decision",
	)
	_expect_equal(
		second_results.values[0].get("decision", {}).get("action", {}).get("action_id"),
		"same-name-action-2",
		"second same-name resident receives only its own decision",
	)
	var first_memory: Dictionary = agent_system.call(
		"get_memory_debug_snapshot",
		"resident-lin-lan",
	)
	var second_memory: Dictionary = agent_system.call(
		"get_memory_debug_snapshot",
		"resident-lin-lan-2",
	)
	_expect(
		String(first_memory.get("source", "")).ends_with(
			"/resident-lin-lan/resident_memory.json",
		),
		"first same-name resident keeps an id-scoped memory file",
	)
	_expect(
		String(second_memory.get("source", "")).ends_with(
			"/resident-lin-lan-2/resident_memory.json",
		),
		"second same-name resident keeps a distinct id-scoped memory file",
	)
	var duplicate_id := _initialization()
	duplicate_id["me"]["attributes"]["name"] = "另一个名字"
	var duplicate_result: Dictionary = agent_system.call(
		"initialize_resident",
		duplicate_id,
		(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
	)
	_expect_equal(duplicate_result.get("ok"), false, "duplicate resident id is rejected")
	_expect(_errors_contain(duplicate_result.get("errors", []), "resident-lin-lan"), "duplicate id error identifies the stable id")


func _test_runtime_owns_initialization_snapshot() -> void:
	var agent_system := _new_agent_system()
	var model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	model.call("queue_decision", _stay_decision("owned-initialization", "owned-action"))
	var initialization := _initialization()
	_expect_equal(
		agent_system.call("initialize_resident", initialization, model).get("ok"),
		true,
		"resident runtime accepts its owned initialization fixture",
	)
	initialization["me"]["attributes"]["name"] = "外部篡改名字"
	initialization["residents"][0]["name"] = "外部篡改居民"
	initialization["places"][0]["name"] = "外部篡改地点"
	var results := ResultCollector.new()
	_expect_equal(
		agent_system.call(
			"request_decision",
			"resident-lin-lan",
			_wake_packet("owned-initialization"),
			results.collect,
		).get("ok"),
		true,
		"external initialization mutation does not break the resident",
	)
	var requests := model.call("get_requests") as Array
	_expect_equal(
		(requests[0] as Dictionary).get("initialization"),
		_initialization(),
		"model request keeps the runtime-owned initialization snapshot",
	)
	_expect_equal(
		agent_system.call(
			"get_memory_debug_snapshot",
			"resident-lin-lan",
		).get("resident"),
		"林岚",
		"memory system keeps the runtime-owned resident identity",
	)


func _test_runtime_model_provider_can_be_replaced() -> void:
	var agent_system := _new_agent_system()
	var first_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	var second_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	_expect_ok(
		agent_system.call("initialize_resident", _initialization(), first_model),
		"运行中模型替换测试初始化居民",
	)
	var replaced := agent_system.call(
		"replace_resident_model_provider",
		"resident-lin-lan",
		second_model,
	) as Dictionary
	_expect_equal(replaced.get("ok"), true, "运行中居民模型提供方可以替换")
	second_model.call(
		"queue_decision",
		_stay_decision("provider-replaced", "provider-replaced-action"),
	)
	var results := ResultCollector.new()
	_expect_ok(
		agent_system.call(
			"request_decision",
			"resident-lin-lan",
			_wake_packet("provider-replaced"),
			results.collect,
		),
		"替换后的居民可以继续请求模型",
	)
	_expect_equal(
		(first_model.call("get_requests") as Array).size(),
		0,
		"替换后不再向旧模型提供方发起新请求",
	)
	_expect_equal(
		(second_model.call("get_requests") as Array).size(),
		1,
		"替换后真实 Agent 入口使用新模型提供方",
	)


func _test_invalid_world_facts_do_not_reach_model() -> void:
	var agent_system := _new_agent_system()
	var model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	_expect_ok(
		agent_system.call("initialize_resident", _initialization(), model),
		"非法世界事实门禁测试初始化居民",
	)
	var wake := _wake_packet("invalid-world-facts")
	wake["snapshot"]["time"]["period"] = "下午"
	var results := ResultCollector.new()
	var acceptance: Dictionary = agent_system.call(
		"request_decision",
		"resident-lin-lan",
		wake,
		results.collect,
	)
	_expect_equal(acceptance.get("ok"), false, "不一致的世界时间在进入模型前被拒绝")
	_expect_error_contains(
		acceptance,
		"snapshot.time.period 与 clock 不对应",
		"世界唤醒拒绝结果指出具体契约关系",
	)
	_expect_equal(model.call("get_requests"), [], "非法世界事实不会到达模型 Provider")
	_expect_equal(results.values, [], "非法世界事实不会产生异步模型回调")


func _test_talk_targets_resident_id() -> void:
	var agent_system: RefCounted = _new_agent_system()
	var fake_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	var wake := _wake_packet("talk-by-id")
	wake["snapshot"]["nearby"].append({
		"resident_id": "resident-tang-xiao-man-2",
		"name": "唐小满",
		"doing": "在摊位后整理货物",
	})
	var decision := {
		"decision_id": "talk-by-id",
		"handling": "replace_current",
		"action": {
			"action_id": "talk-by-id-action",
			"type": "搭话",
			"target_resident_id": "resident-tang-xiao-man-2",
			"say": "这批货是刚到的吗？",
			"narration": "",
			"photos": [],
		},
	}
	fake_model.call("queue_decision", decision)
	agent_system.call("initialize_resident", _initialization(), fake_model)
	var results := ResultCollector.new()
	agent_system.call(
		"request_decision",
		"resident-lin-lan",
		wake,
		results.collect,
	)
	_expect_equal(
		results.values,
		[_accepted_decision_result(decision)],
		"talk action selects one of two same-name residents by id",
	)


func _test_runtime_storage_seams_reject_project_paths() -> void:
	var script := load(AGENT_SYSTEM_SCRIPT_PATH) as Script
	var system: RefCounted = script.new()
	if not system.has_method("configure_debug_runtime_storage"):
		_expect(false, "AgentSystem exposes an explicit debug-only runtime storage seam")
		return
	var rejected: Dictionary = system.call(
		"configure_debug_runtime_storage",
		"res://memory",
	)
	_expect_equal(rejected.get("ok"), false, "debug storage seam rejects res://")
	var wrong_prefix: Dictionary = system.call(
		"configure_debug_runtime_storage",
		"user://agent-batch-memory/not-debug",
	)
	_expect_equal(
		wrong_prefix.get("ok"),
		false,
		"debug storage seam rejects another tool's user:// namespace",
	)


func _new_agent_system() -> RefCounted:
	_memory_system_counter += 1
	var memory_root := "%s/%d" % [_test_root, _memory_system_counter]
	var system: RefCounted = (load(AGENT_SYSTEM_SCRIPT_PATH) as Script).new()
	var configuration: Dictionary = system.call(
		"configure_test_runtime_storage",
		memory_root,
	)
	_expect_equal(configuration.get("ok"), true, "minimal loop configures isolated test storage")
	return system


func _initialization() -> Dictionary:
	return {
		"me": {
			"resident_id": "resident-lin-lan",
			"attributes": {
				"name": "林岚",
				"gender": "男",
				"age": 32,
				"desire": "把手艺做好",
				"personality": "话少，慢热",
				"speech": "说话简短",
			},
			"social_state": {"home": "林岚家", "job": "木匠", "workplace": "工作坊"},
		},
		"residents": [{"resident_id": "resident-tang-xiao-man", "name": "唐小满", "gender": "女", "age": 29, "job": "摆杂货摊的", "home": "唐小满家", "workplace": "市集"}],
		"places": [
			{"name": "广场", "type": "公共地点", "owner": null, "owner_resident_id": null, "summary": "碰头、闲坐和聚集的地方"},
			{"name": "工作坊", "type": "铺面", "owner": "林岚", "owner_resident_id": "resident-lin-lan", "summary": "做木工的地方"},
		],
	}


func _wake_packet(decision_id: String) -> Dictionary:
	return {
		"decision_id": decision_id,
		"snapshot": {
			"time": {"day": 1, "clock": "08:10", "period": "上午"},
			"weather": "小雨",
			"me": {"doing": "站在广场上", "current_action": null, "body": {"困": "不困", "饿": "不饿", "累": "不累"}},
			"nearby": [{"resident_id": "resident-tang-xiao-man", "name": "唐小满", "doing": "站在公告栏旁边"}],
			"place": {"name": "广场", "props": [{"name": "长椅", "verbs": ["歇着"]}]},
			"conversation": null,
		},
		"events": [],
		"action_results": [],
	}


func _stay_decision(decision_id: String, action_id: String) -> Dictionary:
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {"action_id": action_id, "type": "待着", "line": "先看看雨"},
	}


func _finalize() -> void:
	UserTestDataCleanerScript.remove_tree(_test_root)
