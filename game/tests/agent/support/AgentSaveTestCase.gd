class_name AgentSaveTestCase
extends "res://tests/agent/support/AgentTestCase.gd"


const AGENT_SYSTEM_SCRIPT_PATH := "res://agent/AgentSystem.gd"
const SCRIPTED_MODEL_SCRIPT_PATH := "res://tests/agent/support/ScriptedModelProvider.gd"
const STORE_SCRIPT_PATH := "res://agent/lifecycle/AgentSaveStore.gd"
const CODEC_SCRIPT_PATH := "res://agent/lifecycle/ResidentStateCodec.gd"
const SAVE_FIXTURE_SCRIPT_PATH := "res://tests/support/AgentSaveTestFixture.gd"

var _run_id := ""
var _test_root := ""
var _runtime_root_base := ""
var _store: RefCounted
var _test_store_configured := false


class ResultCollector:
	var values: Array[Dictionary] = []

	func collect(value: Dictionary) -> void:
		values.append(value.duplicate(true))


func _setup_save_test(suite_id: String) -> bool:
	_run_id = "%s_%d_%d" % [
		suite_id,
		OS.get_process_id(),
		int(Time.get_unix_time_from_system() * 1000000.0),
	]
	_test_root = "user://agent_save_tests/%s" % _run_id
	_runtime_root_base = "%s/runtime" % _test_root
	_store = (load(STORE_SCRIPT_PATH) as Script).new()
	var configuration: Dictionary = _store.call("configure_test_root", _test_root)
	_expect_ok(configuration, "存档测试使用隔离目录")
	_test_store_configured = configuration.get("ok") == true
	return _test_store_configured


func _finish_save_test(pass_label: String) -> void:
	_cleanup_test_store()
	_prepare_project_shutdown()
	if _failures.is_empty():
		print(pass_label)
		call_deferred("_quit_after_shutdown", 0)
		return
	for failure: String in _failures:
		printerr(failure)
	call_deferred("_quit_after_shutdown", 1)


func _finalize() -> void:
	_cleanup_test_store()


func _cleanup_test_store() -> void:
	if not _test_store_configured:
		return
	var result: Dictionary = _store.call("cleanup_test_root")
	_expect_ok(result, "隔离存档测试目录已清理")
	if result.get("ok") == true:
		_test_store_configured = false


func _begin_pending_decision(system: RefCounted, decision_id: String, action_id: String) -> Dictionary:
	var model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	model.call("set_auto_complete", false)
	model.call("queue_decision", _stay_decision(decision_id, action_id))
	var initialized: Dictionary = system.call("initialize_resident", _initialization(), model)
	_expect_ok(initialized, "resident initializes for %s" % decision_id)
	var results := ResultCollector.new()
	var accepted: Dictionary = system.call("request_decision", "resident-lin-lan", _wake_packet(decision_id), results.collect)
	_expect_ok(accepted, "request starts for %s" % decision_id)
	return {"model": model, "results": results}

func _complete_and_expect_delivery(pending: Dictionary, message: String) -> void:
	(pending["model"] as RefCounted).call("complete_next")
	_expect_equal((pending["results"] as ResultCollector).values.size(), 1, message)

func _complete_and_expect_stale(pending: Dictionary, message: String) -> void:
	(pending["model"] as RefCounted).call("complete_next")
	var values := (pending["results"] as ResultCollector).values
	_expect_equal(values.size(), 1, message)
	if values.size() == 1:
		_expect_equal(values[0].get("stale"), true, "%s；过期状态明确" % message)

func _new_agent_system() -> RefCounted:
	var system: RefCounted = (load(AGENT_SYSTEM_SCRIPT_PATH) as Script).new(_store)
	var configuration: Dictionary = system.call(
		"configure_test_runtime_storage",
		_runtime_root_base,
	)
	_expect_ok(configuration, "lifecycle system configures isolated runtime storage")
	return system

func _overwrite_snapshot_manifest(context: Dictionary, contents: String) -> void:
	var fixture: Script = load(SAVE_FIXTURE_SCRIPT_PATH) as Script
	_expect(
		fixture.call("overwrite_snapshot_manifest", _test_root, context, contents),
		"corrupt manifest fixture is created",
	)

func _context(slot_id: String, session_id: String, save_revision: int) -> Dictionary:
	return {
		"slot_id": "%s_%s" % [_run_id, slot_id],
		"session_id": session_id,
		"save_revision": save_revision,
	}

func _initialization() -> Dictionary:
	return _initialization_for("林岚")

func _initialization_for(resident_name: String, resident_id := "") -> Dictionary:
	if resident_id.is_empty():
		resident_id = _resident_id_for_name(resident_name)
	var other_name := "唐小满" if resident_name != "唐小满" else "林岚"
	var other_id := _resident_id_for_name(other_name)
	return {
		"me": {
			"resident_id": resident_id,
			"attributes": {
				"name": resident_name,
				"gender": "男",
				"age": 32,
				"desire": "把手艺做好",
				"personality": "话少，慢热",
				"speech": "说话简短",
			},
			"social_state": {"home": "林岚家", "job": "木匠", "workplace": "工作坊"},
		},
		"residents": [
			{
				"resident_id": other_id,
				"name": other_name,
				"gender": "女",
				"age": 29,
				"job": "摆杂货摊的",
				"home": "%s家" % other_name,
				"workplace": "市集",
			},
		],
		"places": [{"name": "广场", "type": "公共地点", "owner": null, "owner_resident_id": null, "summary": "碰头的地方"}],
	}

func _paired_initialization(
	resident_id: String,
	resident_name: String,
	other_id: String,
	other_name: String,
	owner_id: String,
	owner_name: String,
) -> Dictionary:
	var initialization := _initialization_for(resident_name, resident_id)
	initialization["residents"] = [{
		"resident_id": other_id,
		"name": other_name,
		"gender": "女",
		"age": 29,
		"job": "摆杂货摊的",
		"home": "共同住处",
		"workplace": "共同工坊",
	}]
	initialization["places"] = [
		{
			"name": "广场",
			"type": "公共地点",
			"owner": null,
			"owner_resident_id": null,
			"summary": "碰头的地方",
		},
		{
			"name": "共同住处",
			"type": "住家",
			"owner": owner_name,
			"owner_resident_id": owner_id,
			"summary": "共同生活的地方",
		},
	]
	return initialization

func _resident_id_for_name(resident_name: String) -> String:
	if resident_name == "林岚":
		return "resident-lin-lan"
	if resident_name == "唐小满":
		return "resident-tang-xiao-man"
	if resident_name == "阿禾":
		return "resident-a-he"
	return "resident-other"

func _wake_packet(decision_id: String) -> Dictionary:
	return {
		"decision_id": decision_id,
		"snapshot": {
			"time": {"day": 1, "clock": "08:10", "period": "上午"},
			"weather": "小雨",
			"me": {"doing": "站着", "current_action": null, "body": {"困": "不困", "饿": "不饿", "累": "不累"}},
			"nearby": [],
			"place": {"name": "广场", "props": []},
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
