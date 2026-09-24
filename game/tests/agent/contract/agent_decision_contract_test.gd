extends "res://tests/agent/support/AgentTestCase.gd"


const AgentContractScript := preload("res://agent/AgentContract.gd")
const AgentDebugScenariosScript := preload("res://agent/debug/AgentDebugScenarios.gd")


func _initialize() -> void:
	var scenarios: RefCounted = AgentDebugScenariosScript.new()
	var initialization: Dictionary = scenarios.call("initialization")
	var wake: Dictionary = scenarios.call("wake_packet", "decision-contract")
	var valid_actions: Array[Dictionary] = [
		{"action_id": "go-1", "type": "去", "place": "工作坊", "line": "去看看木料。"},
		{"action_id": "prop-1", "type": "用道具", "prop": "长椅", "verb": "歇着", "line": "坐一会儿。"},
		{"action_id": "stay-1", "type": "待着", "line": "先看看周围。"},
		{
			"action_id": "talk-1",
			"type": "搭话",
			"target_resident_id": "resident-tang-xiao-man",
			"say": "早。",
			"narration": "朝她点点头。",
			"photos": [],
		},
	]
	for action: Dictionary in valid_actions:
		var decision := _decision(wake["decision_id"], action)
		_set_assertion_context({"action_type": action["type"], "action_id": action["action_id"]})
		_expect_equal(
			AgentContractScript.validate_decision(decision, initialization, wake, {}),
			[],
			"合法动作决定通过 JSON 契约",
		)
	var null_conversation_wake := wake.duplicate(true)
	null_conversation_wake["snapshot"]["conversation"] = null
	var stray_reply := _decision(null_conversation_wake["decision_id"], {
		"action_id": "reply-without-conversation",
		"type": "答话",
		"conversation_id": "missing-conversation",
		"say": "我听见了。",
		"narration": "我回过头。",
		"photos": [],
		"end": false,
	})
	_expect(
		not AgentContractScript.validate_decision(
			stray_reply,
			initialization,
			null_conversation_wake,
			{},
		).is_empty(),
		"conversation 为 null 时非法答话被安全拒绝而不是触发强制转换崩溃",
	)
	var reply_wake := _reply_wake(wake)
	var reply := _decision(reply_wake["decision_id"], {
		"action_id": "reply-1",
		"type": "答话",
		"conversation_id": "conversation-contract",
		"say": "我听见了。",
		"narration": "放下手里的活。",
		"photos": [],
		"end": false,
	})
	_set_assertion_context({"action_type": "答话", "action_id": "reply-1"})
	_expect_equal(
		AgentContractScript.validate_decision(reply, initialization, reply_wake, {}),
		[],
		"收到对方答话时合法答话决定通过契约",
	)
	var traveler_wake := _traveler_reply_wake(wake, 94)
	var traveler_reply := _decision(traveler_wake["decision_id"], {
		"action_id": "traveler-reply-1",
		"type": "答话",
		"conversation_id": "traveler-conversation-contract",
		"say": "你先在我这里坐会儿，我愿意听你慢慢说。",
		"narration": "把身边的位置让出来。",
		"photos": [],
		"end": false,
		"traveler_affinity_delta": 2,
		"traveler_relationship_beat": {
			"kind": "safe_place",
			"text": "你先在我这里坐会儿，我愿意听你慢慢说。",
		},
	})
	_expect_equal(
		AgentContractScript.validate_decision(
			traveler_reply,
			initialization,
			traveler_wake,
			{},
		),
		[],
		"正向旅行者关系答话包含可核对的关系表现句",
	)
	var canonical_traveler_reply := AgentContractScript.canonicalize_decision(
		traveler_reply,
	)
	_expect(
		not (
			canonical_traveler_reply.get("action", {}) as Dictionary
		).has("traveler_relationship_beat"),
		"关系表现生成标记不会进入世界动作或存档",
	)
	for invalid_beat_case: Dictionary in [
		{
			"id": "missing",
			"beat": null,
			"error": "traveler_relationship_beat 缺失",
		},
		{
			"id": "not-in-say",
			"beat": {"kind": "safe_place", "text": "我会陪着你。"},
			"error": "必须原样出现在 action.say 中",
		},
		{
			"id": "wrong-stage-kind",
			"beat": {
				"kind": "practical_care",
				"text": "你先在我这里坐会儿，我愿意听你慢慢说。",
			},
			"error": "必须来自当前好感阶段允许值",
		},
	]:
		var invalid_beat_reply := traveler_reply.duplicate(true)
		var invalid_beat_action := invalid_beat_reply["action"] as Dictionary
		if invalid_beat_case["beat"] == null:
			invalid_beat_action.erase("traveler_relationship_beat")
		else:
			invalid_beat_action["traveler_relationship_beat"] = (
				invalid_beat_case["beat"] as Dictionary
			).duplicate(true)
		_expect_error_contains(
			{
				"ok": false,
				"errors": AgentContractScript.validate_decision(
					invalid_beat_reply,
					initialization,
					traveler_wake,
					{},
				),
			},
			String(invalid_beat_case["error"]),
			"缺失或伪造的关系表现句会触发模型重试",
		)
	var ordinary_traveler_wake := _traveler_reply_wake(wake, 50)
	var ordinary_traveler_reply := traveler_reply.duplicate(true)
	ordinary_traveler_reply["decision_id"] = ordinary_traveler_wake["decision_id"]
	var ordinary_action := ordinary_traveler_reply["action"] as Dictionary
	ordinary_action["conversation_id"] = "traveler-conversation-contract"
	ordinary_action.erase("traveler_relationship_beat")
	_expect_equal(
		AgentContractScript.validate_decision(
			ordinary_traveler_reply,
			initialization,
			ordinary_traveler_wake,
			{},
		),
		[],
		"普通阶段不强迫居民制造正向关系表现",
	)
	var conflict_reply_wake := _reply_wake(wake)
	conflict_reply_wake["snapshot"]["conflict_tension_options"] = [{
		"option_id": "cause-contract",
		"kind": "attack",
		"target_resident_id": "resident-tang-xiao-man",
		"target_name": "唐小满",
		"tension_id": "",
		"meaning": "她刚才故意撞翻了木架",
		"source_kind": "resident_profile_motive",
		"source_summary": "公开人设允许在此时动手",
	}]
	var conflict_reply := _decision(conflict_reply_wake["decision_id"], {
		"action_id": "reply-attack-1",
		"type": "答话",
		"conversation_id": "conversation-contract",
		"say": "你再这样，我就不客气了。",
		"narration": "话音落下便收住脚步。",
		"photos": [],
		"end": true,
	})
	conflict_reply["conflict_intent"] = {
		"action_id": "attack-after-reply-1",
		"type": "攻击",
		"target_resident_id": "resident-tang-xiao-man",
		"attack_kind": "unarmed",
		"cause_id": "cause-contract",
		"line": "说完便扑上去。",
	}
	_set_assertion_context({"action_type": "答话", "conflict_intent": true})
	_expect_equal(
		AgentContractScript.validate_decision(conflict_reply, initialization, conflict_reply_wake, {}),
		[],
		"结束对话时可随答话提交结构化攻击意图",
	)
	var invalid_conflict_reply := conflict_reply.duplicate(true)
	(invalid_conflict_reply["action"] as Dictionary)["end"] = false
	_set_assertion_context({"conflict_intent": true, "invalid": true})
	_expect_error_contains(
		{"ok": false, "errors": AgentContractScript.validate_decision(invalid_conflict_reply, initialization, conflict_reply_wake, {})},
		"结束对话",
		"未结束对话时不能提交攻击意图",
	)
	var continue_wake := wake.duplicate(true)
	continue_wake["decision_id"] = "continue-contract"
	continue_wake["snapshot"]["me"]["current_action"] = {
		"action_id": "current-action",
		"type": "待着",
	}
	_set_assertion_context({"handling": "continue_current"})
	_expect_equal(
		AgentContractScript.validate_decision(
			{"decision_id": "continue-contract", "handling": "continue_current"},
			initialization,
			continue_wake,
			{},
		),
		[],
		"存在当前动作时可以继续当前动作",
	)

	var invalid_cases: Array[Dictionary] = [
		{"id": "not_object", "decision": [], "error": "决定必须是对象"},
		{"id": "wrong_decision_id", "decision": _decision("other", valid_actions[2]), "error": "decision_id"},
		{"id": "unknown_handling", "decision": {"decision_id": wake["decision_id"], "handling": "later"}, "error": "handling 必须"},
		{"id": "continue_without_current", "decision": {"decision_id": wake["decision_id"], "handling": "continue_current"}, "error": "没有当前动作时不能 continue_current"},
		{"id": "extra_decision_field", "decision": _with_extra(_decision(wake["decision_id"], valid_actions[2])), "error": "decision.reasoning"},
		{"id": "reused_action_id", "decision": _decision(wake["decision_id"], valid_actions[2]), "used": {"stay-1": true}, "error": "action.action_id 必须"},
		{"id": "unknown_talk_target", "decision": _decision(wake["decision_id"], _unknown_target_action()), "error": "target_resident_id 必须来自"},
	]
	for case: Dictionary in invalid_cases:
		_set_assertion_context({"case_id": case["id"], "expected_error": case["error"]})
		var errors: Array[String] = AgentContractScript.validate_decision(
			case["decision"],
			initialization,
			wake,
			case.get("used", {}),
		)
		_expect_error_contains(
			{"ok": false, "errors": errors},
			String(case["error"]),
			"非法模型决定必须由对应 JSON 契约分支拒绝",
		)
	_clear_assertion_context()
	_finish_suite("AGENT_DECISION_CONTRACT_PASS")


func _decision(decision_id: String, action: Dictionary) -> Dictionary:
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": action.duplicate(true),
	}


func _reply_wake(source: Dictionary) -> Dictionary:
	var wake := source.duplicate(true)
	wake["decision_id"] = "reply-contract"
	wake["snapshot"]["conversation"] = {
		"conversation_id": "conversation-contract",
		"with_resident_id": "resident-tang-xiao-man",
		"with": "唐小满",
		"turns": [],
	}
	wake["events"] = [{
		"event_id": "reply-event",
		"type": "对方答话",
		"conversation_id": "conversation-contract",
		"turn": {
			"turn_id": 1,
			"speaker_resident_id": "resident-tang-xiao-man",
			"speaker": "唐小满",
			"say": "木架好了吗？",
			"narration": "",
			"photos": [],
		},
		"time": {"day": 1, "clock": "08:12", "period": "上午"},
	}]
	return wake


func _traveler_reply_wake(source: Dictionary, affinity: int) -> Dictionary:
	var wake := _reply_wake(source)
	wake["decision_id"] = "traveler-reply-contract"
	var conversation := wake["snapshot"]["conversation"] as Dictionary
	conversation["conversation_id"] = "traveler-conversation-contract"
	conversation["with_resident_id"] = "player-avatar"
	conversation["with"] = "旅行者"
	conversation["traveler_relationship"] = {
		"affinity": affinity,
		"affinity_label": "很亲近" if affinity >= 90 else "普通",
		"familiarity_level": 3,
		"familiarity_label": "熟悉",
		"conversation_count": 8,
		"attack_count": 0,
	}
	var event := (wake["events"] as Array)[0] as Dictionary
	event["conversation_id"] = "traveler-conversation-contract"
	var turn := event["turn"] as Dictionary
	turn["speaker_resident_id"] = "player-avatar"
	turn["speaker"] = "旅行者"
	turn["say"] = "今天心里有点乱，想和你说说。"
	return wake


func _with_extra(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result["reasoning"] = "不允许暴露"
	return result


func _unknown_target_action() -> Dictionary:
	return {
		"action_id": "talk-unknown",
		"type": "搭话",
		"target_resident_id": "resident-missing",
		"say": "有人吗？",
		"narration": "四处张望。",
		"photos": [],
	}
