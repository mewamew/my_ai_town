class_name TownConflictAgentWorldBridge
extends RefCounted


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const ACTION_TYPES := ["争执", "攻击", "回应冲突", "介入冲突", "离开冲突"]

var _controller: RefCounted
var _name_for_id: Callable


func configure(controller: RefCounted, name_for_id: Callable) -> Dictionary:
	if controller == null or not controller.has_method("get_public_projection") or not controller.has_method("tension_options_for_actor"):
		return _failure("CONFLICT_BRIDGE_CONTROLLER_INVALID")
	if not name_for_id.is_valid():
		return _failure("CONFLICT_BRIDGE_NAME_RESOLVER_REQUIRED")
	_controller = controller
	_name_for_id = name_for_id
	return {"ok": true, "errorCode": ""}


func snapshot_for_actor(actor_id: String, nearby_ids: Array) -> Dictionary:
	if _controller == null or actor_id.strip_edges().is_empty():
		return {
			"conflicts": [],
			"conflict_injuries": [],
			"conflict_tension_options": [],
		}
	var nearby := {}
	for value_id: Variant in nearby_ids:
		var nearby_id := String(value_id).strip_edges()
		if not nearby_id.is_empty() and nearby_id != actor_id:
			nearby[nearby_id] = true
	var projection := (
		_controller.get_agent_projection() as Dictionary
		if _controller.has_method("get_agent_projection")
		else _controller.get_public_projection() as Dictionary
	)
	return {
		"conflicts": _project_conflicts(actor_id, nearby, projection),
		"conflict_injuries": _project_injuries(actor_id, projection),
		"conflict_tension_options": _project_tension_options(actor_id, nearby.keys()),
	}


func prepare_action(actor_id: String, action: Dictionary, issued_snapshot: Dictionary) -> Dictionary:
	if _controller == null:
		return _failure("CONFLICT_BRIDGE_NOT_CONFIGURED")
	var action_type := String(action.get("type", ""))
	if not ACTION_TYPES.has(action_type):
		return _failure("CONFLICT_ACTION_UNKNOWN")
	var prepared := action.duplicate(true)
	if action_type in ["争执", "攻击"]:
		if String(action.get("target_resident_id", "")).begins_with("person_"):
			return _failure("CONFLICT_ATTACK_AVATAR_FORBIDDEN")
		var option_field := "tension_option_id" if action_type == "争执" else "cause_id"
		var option_id := String(action.get(option_field, ""))
		var option := _find_option(issued_snapshot.get("conflict_tension_options", []) as Array, option_id)
		if action_type == "攻击" and option.is_empty():
			# 想打就打：自述起因不在预设选项里也放行，台词即起因摘要，
			# 世界按一条新登记的人设决定冲突入账。
			prepared["source_event_ids"] = []
			prepared["sourceConversationId"] = ""
			prepared["source_summary"] = String(action.get("line", "")).strip_edges()
			prepared["conflict_source_kind"] = "resident_self_declared"
			if prepared["source_summary"].is_empty():
				return _failure("CONFLICT_ATTACK_REASON_REQUIRED")
			return {"ok": true, "errorCode": "", "action": prepared}
		var expected_kind := "attack" if action_type == "攻击" else ""
		if option.is_empty() or (not expected_kind.is_empty() and String(option.get("kind", "")) != expected_kind) or (expected_kind.is_empty() and String(option.get("kind", "")) == "attack"):
			return _failure("CONFLICT_CAUSE_STALE")
		prepared["target_resident_id"] = String(option.get("target_resident_id", ""))
		prepared["tension_kind"] = String(option.get("kind", ""))
		prepared["source_event_ids"] = (option.get("source_event_ids", []) as Array).duplicate(true)
		prepared["sourceConversationId"] = String(option.get("source_conversation_id", ""))
		prepared["source_summary"] = String(option.get("source_summary", ""))
		prepared["conflict_source_kind"] = String(option.get("source_kind", ""))
		if action_type == "攻击" and String(action.get("target_resident_id", "")) != String(option.get("target_resident_id", "")):
			return _failure("CONFLICT_CAUSE_TARGET_MISMATCH")
	else:
		var conflict := _find_conflict(issued_snapshot.get("conflicts", []) as Array, String(action.get("conflict_id", "")))
		if conflict.is_empty():
			return _failure("CONFLICT_REFERENCE_STALE")
	return {"ok": true, "errorCode": "", "action": prepared}


func execute_action(actor_id: String, prepared: Dictionary) -> Dictionary:
	if _controller == null:
		return _failure("CONFLICT_BRIDGE_NOT_CONFIGURED")
	match String(prepared.get("type", "")):
		"争执":
			return _controller.apply_tension_action({
				"requestId": String(prepared.get("action_id", "")), "actorId": actor_id,
				"targetId": String(prepared.get("target_resident_id", "")), "optionId": String(prepared.get("tension_option_id", "")),
				"actionKind": String(prepared.get("tension_kind", "")), "line": String(prepared.get("line", "")),
				"sourceConversationId": String(prepared.get("sourceConversationId", "")),
				"sourceEventIds": (prepared.get("source_event_ids", []) as Array).duplicate(true),
				"sourceSummary": String(prepared.get("source_summary", "")),
			}) as Dictionary
		"攻击":
			var profile_motive := String(prepared.get("conflict_source_kind", "")) == "resident_profile_motive"
			return _controller.begin_attack({
				"requestId": String(prepared.get("action_id", "")), "attackerId": actor_id,
				"targetId": String(prepared.get("target_resident_id", "")), "attackKind": String(prepared.get("attack_kind", "")),
				"causeId": String(prepared.get("cause_id", "")), "causeSummary": String(prepared.get("source_summary", "")),
				"sourceConversationId": String(prepared.get("sourceConversationId", "")),
				"sourceKind": "resident_profile_decision" if profile_motive else "resident_decision",
				"sourceRef": String(prepared.get("cause_id", "")) if profile_motive else String(prepared.get("action_id", "")),
			}) as Dictionary
		"回应冲突":
			return _controller.respond(String(prepared.get("conflict_id", "")), actor_id, String(prepared.get("response_kind", ""))) as Dictionary
		"介入冲突":
			return _controller.intervene(String(prepared.get("conflict_id", "")), actor_id, String(prepared.get("intervention_kind", ""))) as Dictionary
		"离开冲突":
			return _controller.leave_conflict(String(prepared.get("conflict_id", "")), actor_id, String(prepared.get("reason", ""))) as Dictionary
	return _failure("CONFLICT_ACTION_UNKNOWN")


func _project_conflicts(
	actor_id: String,
	nearby: Dictionary,
	projection: Dictionary,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value_conflict: Variant in projection.get("activeConflicts", []) as Array:
		if value_conflict is not Dictionary: continue
		var conflict := value_conflict as Dictionary
		var ids: Array = conflict.get("participantIds", []) as Array
		var participant := ids.has(actor_id)
		var close := false
		for value_id: Variant in ids:
			if nearby.has(String(value_id)): close = true
		if not participant and not close: continue
		var names: Array[String] = []
		for value_id: Variant in ids: names.append(String(_name_for_id.call(String(value_id))))
		var responses: Array[String] = []
		if String(conflict.get("phase", "")) == "unilateral_hit" and String(conflict.get("targetId", "")) == actor_id:
			responses.assign(["retaliate", "flee", "deescalate"])
		var interventions: Array[String] = []
		if not participant: interventions.assign(["join", "protect", "mediate"])
		result.append({
			"conflict_id": String(conflict.get("conflictId", "")), "phase": String(conflict.get("phase", "")),
			"role": String((conflict.get("participantRoles", {}) as Dictionary).get(actor_id, "witness")),
			"participant_resident_ids": ids.duplicate(), "participant_names": names,
			"response_kinds": responses, "intervention_kinds": interventions, "leave_allowed": participant,
		})
	return result


func _project_tension_options(actor_id: String, nearby_ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value_option: Variant in _controller.tension_options_for_actor(actor_id, nearby_ids) as Array:
		if value_option is not Dictionary: continue
		var option := value_option as Dictionary
		var target_id := String(option.get("targetId", ""))
		result.append({
			"option_id": String(option.get("optionId", "")), "kind": String(option.get("kind", "")),
			"target_resident_id": target_id, "target_name": String(_name_for_id.call(target_id)),
			"tension_id": String(option.get("tensionId", "")), "meaning": String(option.get("meaning", "")),
			"source_event_ids": (option.get("sourceEventIds", []) as Array).duplicate(true),
			"source_kind": String(option.get("sourceKind", "")), "source_summary": String(option.get("sourceSummary", "")),
			"source_conversation_id": String(option.get("sourceConversationId", "")),
		})
	return result


func _project_injuries(
	actor_id: String,
	projection: Dictionary,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value_injury: Variant in projection.get("injuries", []) as Array:
		if value_injury is not Dictionary:
			continue
		var injury := value_injury as Dictionary
		if str(injury.get("actorId", "")) != actor_id:
			continue
		var source_actor_id := str(injury.get("sourceActorId", ""))
		var source_actor_name: Variant = _name_for_id.call(source_actor_id)
		result.append({
			"injury_id": "%s:%s" % [
				str(injury.get("sourceConflictId", "")),
				str(injury.get("appliedAtMinute", 0)),
			],
			"severity": str(injury.get("severity", "")),
			"source_actor_id": source_actor_id,
			"source_actor_name": source_actor_name if source_actor_name is String else "",
			"treatment_status": str(injury.get("treatmentStatus", "")),
			"cause_summary": str(injury.get("causeSummary", "")),
			"source_conflict_id": str(injury.get("sourceConflictId", "")),
		})
	return result


func _find_option(options: Array, option_id: String) -> Dictionary:
	for value_option: Variant in options:
		if value_option is Dictionary and String((value_option as Dictionary).get("option_id", "")) == option_id: return (value_option as Dictionary).duplicate(true)
	return {}

func _find_conflict(conflicts: Array, conflict_id: String) -> Dictionary:
	for value_conflict: Variant in conflicts:
		if value_conflict is Dictionary and String((value_conflict as Dictionary).get("conflict_id", "")) == conflict_id: return (value_conflict as Dictionary).duplicate(true)
	return {}

func _failure(code: String) -> Dictionary:
	return RESULT_SHAPES.failure(code)


static func action_result_text(action_type: String) -> String:
	return String({
		"争执": "争执已经发生",
		"攻击": "攻击已经发生",
		"回应冲突": "已经作出冲突回应",
		"介入冲突": "已经介入冲突",
		"离开冲突": "已经离开冲突",
	}.get(action_type, "冲突动作已经确认"))


static func action_error_text(error_code: String) -> String:
	return String({
		"CONFLICT_CAUSE_STALE": "引发冲突的事情已经失效",
		"CONFLICT_CAUSE_TARGET_MISMATCH": "冲突对象已经变化",
		"CONFLICT_REFERENCE_STALE": "这场冲突已经结束或发生变化",
		"CONFLICT_TARGET_OUT_OF_RANGE": "目标已经离开可作用范围",
		"CONFLICT_TENSION_TARGET_OUT_OF_RANGE": "对方已经走远",
		"CONFLICT_ACTORS_NOT_IN_SAME_SPACE": "双方已不在同一地点",
		"CONFLICT_ATTACKER_NOT_PRESENT": "发起者当前不在场",
		"CONFLICT_TARGET_NOT_PRESENT": "目标当前不在场",
	}.get(error_code, "当前无法执行这项冲突动作"))
