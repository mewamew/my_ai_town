extends "res://tests/agent/support/AgentPromptTestCase.gd"


const AGENT_CONTRACT := preload("res://agent/AgentContract.gd")
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)


func _initialize() -> void:
	var compiler_script := _load_prompt_compiler()
	if compiler_script != null:
		_test_medical_response_contract(compiler_script)
		_test_service_request_and_world_destination_constraints(compiler_script)
		_test_onsite_service_requires_task_advancing_action(compiler_script)
		_test_traveler_relationship_context(compiler_script)
	_finish_prompt_test("AGENT_SERVICE_PROMPT_PASS")


func _test_medical_response_contract(compiler_script: Script) -> void:
	var wake := _wake_packet("medical-reply-1", "晴天")
	wake["snapshot"]["conversation"] = {
		"conversation_id": "conversation-medical-1",
		"with_resident_id": "resident-tang-xiao-man",
		"with": "唐小满",
		"turns": [{
			"turn_id": 1,
			"speaker_resident_id": "resident-tang-xiao-man",
			"speaker": "唐小满",
			"say": "哪里不舒服？",
			"narration": "",
			"photos": [],
		}],
		"medical_context": {
			"request_id": "clinic-request-1",
			"role": "patient",
			"status": "active",
			"conversation_id": "conversation-medical-1",
			"reported_summary": "头痛，需要问诊",
			"attempt_count": 1,
			"patient_response_kind": "",
			"response_options": ["describe", "decline"],
		},
	}
	wake["events"] = [{
		"event_id": "medical-reply-event-1",
		"time": {"day": 1, "clock": "08:10", "period": "上午"},
		"type": "对方答话",
		"conversation_id": "conversation-medical-1",
		"turn": (
			wake["snapshot"]["conversation"]["turns"][0] as Dictionary
		).duplicate(true),
	}]
	_expect_equal(
		AGENT_CONTRACT.validate_wake_packet(wake),
		[],
		"patient medical conversation is accepted by the wake contract",
	)
	var fabricated_projection := wake.duplicate(true)
	fabricated_projection["snapshot"]["conversation"]["medical_context"][
		"conversation_id"
	] = ""
	_expect(
		not AGENT_CONTRACT.validate_wake_packet(
			fabricated_projection,
		).is_empty(),
		"active medical projection cannot exist without a real conversation",
	)
	var scripted_projection := wake.duplicate(true)
	scripted_projection["snapshot"]["conversation"]["medical_context"][
		"patient_response_kind"
	] = "scripted_answer"
	_expect(
		not AGENT_CONTRACT.validate_wake_packet(
			scripted_projection,
		).is_empty(),
		"medical projection rejects a scripted patient response kind",
	)
	var compiler: RefCounted = compiler_script.new(_initialization())
	var request := compiler.call("compile", wake, "") as Dictionary
	var constraints := request.get("derived_constraints", {}) as Dictionary
	_expect_equal(
		constraints.get("medical_response"),
		{
			"fields": ["request_id", "response_kind"],
			"request_id": "clinic-request-1",
			"response_kinds": ["describe", "decline"],
			"required": true,
		},
		"patient receives exact medical response choices",
	)
	var actions := constraints.get("actions", {}) as Dictionary
	_expect(
		((actions.get("答话", {}) as Dictionary).get("fields", []) as Array).has(
			"medical_response",
		),
		"patient reply action exposes the required structured field",
	)
	var messages := request.get("messages", []) as Array
	_expect(
		messages.size() == 2
		and String((messages[1] as Dictionary).get("content", "")).contains(
			"medical_response 必须是对象",
		),
		"prompt states the exact medical response shape",
	)
	var decision := {
		"decision_id": "medical-reply-1",
		"handling": "replace_current",
		"action": {
			"action_id": "medical-reply-1-answer",
			"type": "答话",
			"conversation_id": "conversation-medical-1",
			"say": "从早上开始一直头痛，我愿意说清楚。",
			"narration": "",
			"photos": [],
			"end": false,
			"medical_response": {
				"request_id": "clinic-request-1",
				"response_kind": "describe",
			},
		},
	}
	_expect_equal(
		AGENT_CONTRACT.validate_decision(
			decision,
			_initialization(),
			wake,
			{},
		),
		[],
		"exact patient medical response is accepted",
	)
	var missing_response := decision.duplicate(true)
	missing_response["action"].erase("medical_response")
	_expect(
		not AGENT_CONTRACT.validate_decision(
			missing_response,
			_initialization(),
			wake,
			{},
		).is_empty(),
		"patient cannot omit the required structured response",
	)
	var wrong_request := decision.duplicate(true)
	wrong_request["action"]["medical_response"]["request_id"] = "other-request"
	_expect(
		not AGENT_CONTRACT.validate_decision(
			wrong_request,
			_initialization(),
			wake,
			{},
		).is_empty(),
		"patient cannot answer a different medical request",
	)
	var ordinary_wake := wake.duplicate(true)
	ordinary_wake["decision_id"] = "ordinary-reply-null-medical"
	ordinary_wake["snapshot"]["conversation"]["medical_context"] = null
	var ordinary_request := compiler.call("compile", ordinary_wake, "") as Dictionary
	var ordinary_actions := (
		ordinary_request.get("derived_constraints", {}) as Dictionary
	).get("actions", {}) as Dictionary
	_expect(
		not ((ordinary_actions.get("答话", {}) as Dictionary).get(
			"fields",
			[],
		) as Array).has("medical_response"),
		"ordinary conversation does not expose the medical field",
	)
	var ordinary_decision := decision.duplicate(true)
	ordinary_decision["decision_id"] = "ordinary-reply-null-medical"
	ordinary_decision["action"]["action_id"] = (
		"ordinary-reply-null-medical-answer"
	)
	ordinary_decision["action"].erase("medical_response")
	_expect_equal(
		AGENT_CONTRACT.validate_decision(
			ordinary_decision,
			_initialization(),
			ordinary_wake,
			{},
		),
		[],
		"ordinary reply remains valid without a medical response",
	)
	var canonical_ordinary := AGENT_CONTRACT.canonicalize_decision(
		ordinary_decision,
	)
	_expect(
		not (
			canonical_ordinary.get("action", {}) as Dictionary
		).has("medical_response"),
		"ordinary reply canonicalization does not read a missing optional field",
	)
	_expect_equal(
		(
			AGENT_CONTRACT.canonicalize_decision(decision).get(
				"action",
				{},
			) as Dictionary
		).get("medical_response"),
		decision["action"]["medical_response"],
		"medical reply canonicalization retains the structured response",
	)


func _test_service_request_and_world_destination_constraints(
	compiler_script: Script,
) -> void:
	var wake := _wake_packet("service-task-prompt-1", "晴天")
	wake["snapshot"]["place"]["destinations"] = [
		"中心广场",
		"图书馆",
	]
	wake["snapshot"]["work_tasks"] = [{
		"task_id": "service-task:clinic:request-1",
		"capability": "care.consultation",
		"source_kind": "clinic_request",
		"source_ref": "request-1",
		"targets": [{
			"kind": "service_request",
			"ref": "request-1",
		}],
		"expected_result": "consultation_record",
		"state": "pending",
		"priority": 85,
		"process_stage": "awaiting_interview",
		"service_request": {
			"request_id": "request-1",
			"kind": "clinic",
			"requester_resident_id": "resident-tang-xiao-man",
			"requester_name": "唐小满",
			"requester_current_place": "诊所",
			"subject_ref": "头疼",
			"item_id": "",
			"place_id": "诊所",
			"state": "pending",
			"wait_reason": "",
			"medical_dialogue": {
				"request_id": "request-1",
				"role": "clinician",
				"status": "required",
				"conversation_id": "",
				"reported_summary": "头疼",
				"attempt_count": 0,
				"patient_response_kind": "",
				"response_options": [],
			},
		},
	}]
	_expect_equal(
		AGENT_CONTRACT.validate_wake_packet(wake),
		[],
		"service request task is accepted by the Agent wake contract",
	)
	var mismatched_wake := wake.duplicate(true)
	mismatched_wake["snapshot"]["work_tasks"][0]["source_ref"] = (
		"another-request"
	)
	_expect(
		not AGENT_CONTRACT.validate_wake_packet(
			mismatched_wake,
		).is_empty(),
		"service request cannot detach from its World task source",
	)
	var compiler: RefCounted = compiler_script.new(_initialization())
	var request := compiler.call("compile", wake, "") as Dictionary
	var messages := request.get("messages", []) as Array
	_expect_equal(messages.size(), 2, "service request prompt compiles")
	if messages.size() != 2:
		return
	var user_text := String(
		(messages[1] as Dictionary).get("content", ""),
	)
	_expect(
		user_text.contains("当前可前往地点：中心广场、图书馆"),
		"dynamic prompt renders the World travel allowlist",
	)
	_expect(
		user_text.contains("唐小满")
		and user_text.contains("头疼")
		and user_text.contains("医患对话：状态required"),
		"service request details are rendered instead of rejected or hidden",
	)
	var actions := (
		request.get("derived_constraints", {}) as Dictionary
	).get("actions", {}) as Dictionary
	_expect_equal(
		(
			(actions.get("去", {}) as Dictionary).get(
				"places",
				[],
			)
		),
		["中心广场", "图书馆"],
		"travel constraints use the World allowlist exactly",
	)


func _test_onsite_service_requires_task_advancing_action(
	compiler_script: Script,
) -> void:
	var wake := _wake_packet("cafe-service-priority-1", "晴天")
	var task_id := "service-task:花房咖啡馆:occupation-service-000007:4"
	var place_snapshot := {
		"name": "花房咖啡馆",
		"destinations": [],
		"visible_props": [],
		"props": [],
		"activities": [{
			"activity_id": "activity_cafe_brew_coffee",
			"label": "冲咖啡",
			"role": "worker",
			"route_check_deferred": false,
			"advances_current_work_task": true,
			"work_task_ids": [task_id],
			"work_task_capabilities": ["cafe.order"],
			"interest_match": false,
			"matched_interests": [],
		}],
		"service_control": {},
		"message_recipients": [],
	}
	ACTION_SUPPORT.focus_agent_place_snapshot_on_service_task(
		{"currentPlace": "花房咖啡馆"},
		place_snapshot,
		{
			"task_id": task_id,
			"place_id": "花房咖啡馆",
		},
	)
	wake["snapshot"]["place"] = place_snapshot
	_expect_equal(
		String(place_snapshot.get("required_work_task_id", "")),
		task_id,
		"现场服务任务向 Agent 快照写入硬约束标记",
	)
	wake["snapshot"]["work_tasks"] = [{
		"task_id": task_id,
		"capability": "cafe.order",
		"source_kind": "customer_order",
		"source_ref": "occupation-service-000007",
		"targets": [{
			"kind": "service_request",
			"ref": "occupation-service-000007",
		}],
		"expected_result": "order_handoff",
		"state": "accepted",
		"priority": 85,
		"process_stage": "awaiting_brew",
		"next_step": {
			"instruction": "到服务地点处理这位顾客的真实请求",
			"place_id": "花房咖啡馆",
		},
		"service_request": {
			"request_id": "occupation-service-000007",
			"kind": "cafe_order",
			"requester_resident_id": "resident-tang-xiao-man",
			"requester_name": "唐小满",
			"requester_current_place": "花房咖啡馆",
			"subject_ref": "",
			"item_id": "brewed_coffee",
			"place_id": "花房咖啡馆",
			"state": "pending",
			"wait_reason": "",
		},
	}]
	_expect_equal(
		AGENT_CONTRACT.validate_wake_packet(wake),
		[],
		"现场优先服务任务通过唤醒契约",
	)
	var compiler: RefCounted = compiler_script.new(_initialization())
	var request := compiler.call("compile", wake, "") as Dictionary
	var messages := request.get("messages", []) as Array
	_expect(
		messages.size() == 2
		and String((messages[1] as Dictionary).get("content", "")).contains(
			"必须立即推进职业任务",
		),
		"现场优先服务任务使用硬性执行提示",
	)
	var idle_decision := {
		"decision_id": "cafe-service-priority-1",
		"handling": "replace_current",
		"action": {
			"action_id": "cafe-service-priority-idle",
			"type": "待着",
			"line": "我继续坐着休息。",
		},
	}
	_expect(
		not AGENT_CONTRACT.validate_decision(
			idle_decision,
			_initialization(),
			wake,
			{},
		).is_empty(),
		"现场优先服务任务拒绝继续待着",
	)
	var work_decision := {
		"decision_id": "cafe-service-priority-1",
		"handling": "replace_current",
		"action": {
			"action_id": "cafe-service-priority-brew",
			"type": "做活动",
			"activity_id": "activity_cafe_brew_coffee",
			"line": "顾客正在等，我先把这杯咖啡冲好。",
		},
	}
	_expect_equal(
		AGENT_CONTRACT.validate_decision(
			work_decision,
			_initialization(),
			wake,
			{},
		),
		[],
		"现场优先服务任务允许执行匹配的工作活动",
	)


func _test_traveler_relationship_context(compiler_script: Script) -> void:
	var wake := _wake_packet("traveler-relationship-prompt-1", "晴天")
	wake["snapshot"]["conversation"] = {
		"conversation_id": "conversation-traveler-1",
		"with_resident_id": "player-avatar",
		"with": "旅行者",
		"turns": [{
			"turn_id": 1,
			"speaker_resident_id": "player-avatar",
			"speaker": "旅行者",
			"say": "你好。",
			"narration": "",
			"photos": [],
		}],
		"traveler_relationship": {
			"affinity": 28,
			"affinity_label": "明显疏远",
			"familiarity_level": 3,
			"familiarity_label": "熟悉",
			"conversation_count": 8,
			"attack_count": 1,
			"last_change": "化身攻击-10",
		},
	}
	wake["events"] = [{
		"event_id": "traveler-relationship-event-1",
		"time": {"day": 1, "clock": "08:11", "period": "上午"},
		"type": "搭话",
		"conversation_id": "conversation-traveler-1",
		"turn": (wake["snapshot"]["conversation"]["turns"][0] as Dictionary).duplicate(true),
	}]
	_expect_equal(
		AGENT_CONTRACT.validate_wake_packet(wake),
		[],
		"traveler relationship context is accepted by the wake contract",
	)
	var compiler: RefCounted = compiler_script.new(_initialization())
	var avatar_memory := (
		"[关于化身的个人记忆]\n[具体记忆]\n"
		+ "- 旅行者上次说会帮忙寻找走失的猫（来源：本人亲历；状态：active）"
	)
	var request := compiler.call("compile", wake, avatar_memory) as Dictionary
	var actions := (request.get("derived_constraints", {}) as Dictionary).get("actions", {}) as Dictionary
	var reply_fields := (actions.get("答话", {}) as Dictionary).get("fields", []) as Array
	_expect(
		reply_fields.has("traveler_affinity_delta"),
		"traveler conversation still requires the Agent-selected affinity delta",
	)
	var messages := request.get("messages", []) as Array
	var user_text := String((messages[1] as Dictionary).get("content", "")) if messages.size() == 2 else ""
	_expect(
		user_text.contains("与旅行者的关系：好感28（明显疏远）")
		and user_text.contains("最近一次关系变化：化身攻击-10")
		and user_text.contains("熟悉旅行者但对其反感")
		and user_text.contains("可以记得旧事，同时保持疏远")
		and user_text.contains("寻找走失的猫"),
		"familiarity and affinity combine without hiding confirmed avatar memory",
	)
	_expect(
		user_text.contains("普通寒暄、重复旧话和仅仅完成对话填 0")
		and user_text.contains("不能因为变熟自动增加")
		and user_text.contains("真诚关心时应填 +2")
		and user_text.contains("不能因为本人话少")
		and user_text.contains("兑现对本人的承诺")
		and user_text.contains("证据不足填 0"),
		"traveler affinity changes require evidence instead of rewarding every chat",
	)
	_expect(
		user_text.contains("不写成任务回执、客服答复或关系总结")
		and user_text.contains("话少表示少说一两句")
		and user_text.contains("回应旅行者真正表达的意思")
		and user_text.contains("不要习惯性用“你有事？”")
		and user_text.contains("好感表现参考"),
		"traveler relationship guidance requires natural visible behavior",
	)
	var caring_wake := wake.duplicate(true)
	var caring_conversation := (
		caring_wake["snapshot"]["conversation"] as Dictionary
	)
	caring_conversation["traveler_relationship"] = {
		"affinity": 53,
		"affinity_label": "开始在意",
		"familiarity_level": 2,
		"familiarity_label": "有些熟悉",
		"conversation_count": 3,
		"attack_count": 0,
		"last_change": "居民回应+1",
	}
	var caring_request := compiler.call("compile", caring_wake, avatar_memory) as Dictionary
	var caring_actions := (
		caring_request.get("derived_constraints", {}) as Dictionary
	).get("actions", {}) as Dictionary
	var caring_reply_fields := (
		(caring_actions.get("答话", {}) as Dictionary).get("fields", [])
		as Array
	)
	var caring_messages := caring_request.get("messages", []) as Array
	var caring_text := String(
		(caring_messages[1] as Dictionary).get("content", "")
	) if caring_messages.size() == 2 else ""
	_expect(
		caring_text.contains("好感53（开始在意）")
		and caring_text.contains("答完后多说一句只会对在意的人说的话")
		and caring_reply_fields.has("traveler_relationship_beat")
		and caring_text.contains("必须原样出现在 action.say 中")
		and caring_text.contains("personal_view、reciprocal_question"),
		"the first visible affinity stage changes concrete conversation behavior",
	)
	var close_wake := caring_wake.duplicate(true)
	var close_conversation := close_wake["snapshot"]["conversation"] as Dictionary
	var close_relationship := (
		close_conversation["traveler_relationship"] as Dictionary
	)
	close_relationship["affinity"] = 94
	close_relationship["affinity_label"] = "很亲近"
	var close_request := compiler.call("compile", close_wake, avatar_memory) as Dictionary
	var close_messages := close_request.get("messages", []) as Array
	var close_text := String(
		(close_messages[1] as Dictionary).get("content", "")
	) if close_messages.size() == 2 else ""
	_expect(
		close_text.contains("听出自己不是普通熟人")
		and close_text.contains("必须先接住这份情绪")
		and close_text.contains("至少落实一项个人关系信号")
		and close_text.contains("单纯叫对方休息不算")
		and close_text.contains("personal_stake、safe_place、shared_rapport")
		and close_text.contains("禁止照抄例句"),
		"the closest stage requires relationship-specific content",
	)
