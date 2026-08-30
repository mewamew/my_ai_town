extends "res://tests/agent/support/AgentTestCase.gd"


const AgentContractScript := preload("res://agent/AgentContract.gd")
const AgentDebugScenariosScript := preload("res://agent/debug/AgentDebugScenarios.gd")


func _initialize() -> void:
	var scenarios: RefCounted = AgentDebugScenariosScript.new()
	var valid: Dictionary = scenarios.call("wake_packet", "wake-contract")
	_expect_equal(
		AgentContractScript.validate_wake_packet(valid),
		[],
		"标准世界唤醒包通过 JSON 契约",
	)
	var condition_event_wake := valid.duplicate(true)
	condition_event_wake["events"] = [{
		"event_id": "world-event-condition-1",
		"type": "身体状况变化",
		"time": {"day": 1, "clock": "08:11", "period": "上午"},
		"eventId": "condition-event-000001",
		"eventType": "condition_started",
		"residentId": "resident-tang-xiao-man",
		"conditionId": "condition-resident-tang-xiao-man-000001",
		"conditionKind": "headache",
		"label": "头疼",
		"severity": "noticeable",
		"state": "active",
		"atMinute": 491,
		"sourceRef": "sleep-action-1",
	}]
	_expect_equal(
		AgentContractScript.validate_wake_packet(condition_event_wake),
		[],
		"世界自然产生的身体状况事件可以唤醒居民 Agent",
	)
	# 居民死亡: 旧档(beta5/beta6)可合法携带排队死亡事件(SAVED_EVENT_FIELDS),
	# 恢复后随 wake 重放, 契约必须放行且字段校验与恢复校验一致。
	var death_event_wake := valid.duplicate(true)
	death_event_wake["events"] = [{
		"event_id": "world-event-death-1",
		"type": "居民死亡",
		"time": {"day": 2, "clock": "08:00", "period": "上午"},
		"deceased_resident_id": "resident-ah-e",
		"deceased_resident_name": "阿禾",
		"reason": "夜里遇害",
		"location": {"placeName": "镇公所"},
		"residentId": "resident-tang-xiao-man",
	}]
	_expect_equal(
		AgentContractScript.validate_wake_packet(death_event_wake),
		[],
		"旧档恢复重放的居民死亡事件可以唤醒居民 Agent",
	)
	var death_event_missing_location_wake := death_event_wake.duplicate(true)
	(death_event_missing_location_wake["events"][0] as Dictionary).erase("location")
	var death_event_errors: Array[String] = AgentContractScript.validate_wake_packet(
		death_event_missing_location_wake
	)
	_expect_error_contains(
		{"ok": false, "errors": death_event_errors},
		"events[0].location",
		"居民死亡事件缺少 location 必须由契约拒绝",
	)
	var cases: Array[Dictionary] = [
		{"id": "not_object", "value": "wake", "error": "唤醒包必须是对象"},
		{"id": "empty_decision_id", "value": _with(valid, ["decision_id"], ""), "error": "decision_id"},
		{"id": "invalid_weather", "value": _with(valid, ["snapshot", "weather"], "未知"), "error": "snapshot.weather"},
		{"id": "invalid_clock", "value": _with(valid, ["snapshot", "time", "clock"], "25:90"), "error": "snapshot.time.clock"},
		{"id": "invalid_period", "value": _with(valid, ["snapshot", "time", "period"], "午夜"), "error": "snapshot.time.period 不是合法时段"},
		{"id": "period_clock_mismatch", "value": _with(valid, ["snapshot", "time", "period"], "下午"), "error": "snapshot.time.period 与 clock 不对应"},
		{"id": "missing_body_state", "value": _without(valid, ["snapshot", "me", "body", "困"]), "error": "snapshot.me.body.困 缺失"},
		{"id": "invalid_body_level", "value": _with(valid, ["snapshot", "me", "body", "困"], "有一点困"), "error": "snapshot.me.body.困 不是合法程度"},
		{"id": "extra_body_state", "value": _with(valid, ["snapshot", "me", "body", "心情"], "开心"), "error": "snapshot.me.body.心情 不是合法身体状态"},
		{"id": "invalid_event_type", "value": _with_event(valid, "未知事件"), "error": "events[0].type"},
		{"id": "invalid_result_status", "value": _with_result(valid, "unknown"), "error": "action_results[0].status"},
	]
	for case: Dictionary in cases:
		_set_assertion_context({"case_id": case["id"], "expected_error": case["error"]})
		var errors: Array[String] = AgentContractScript.validate_wake_packet(case["value"])
		_expect_error_contains(
			{"ok": false, "errors": errors},
			String(case["error"]),
			"非法世界唤醒包必须由对应契约分支拒绝",
		)
	_clear_assertion_context()
	_finish_suite("AGENT_WAKE_CONTRACT_PASS")


func _with(source: Dictionary, path: Array[String], value: Variant) -> Dictionary:
	var result := source.duplicate(true)
	var target: Dictionary = result
	for index in path.size() - 1:
		target = target[path[index]] as Dictionary
	target[path[-1]] = value
	return result


func _without(source: Dictionary, path: Array[String]) -> Dictionary:
	var result := source.duplicate(true)
	var target: Dictionary = result
	for index in path.size() - 1:
		target = target[path[index]] as Dictionary
	target.erase(path[-1])
	return result


func _with_event(source: Dictionary, event_type: String) -> Dictionary:
	var result := source.duplicate(true)
	result["events"] = [{
		"event_id": "event-contract",
		"type": event_type,
		"who_resident_id": "resident-tang-xiao-man",
		"who": "唐小满",
		"time": {"day": 1, "clock": "08:11", "period": "上午"},
	}]
	return result


func _with_result(source: Dictionary, status: String) -> Dictionary:
	var result := source.duplicate(true)
	result["action_results"] = [{
		"action_id": "action-contract",
		"status": status,
		"reason": "世界反馈",
		"time": {"day": 1, "clock": "08:12", "period": "上午"},
	}]
	return result
