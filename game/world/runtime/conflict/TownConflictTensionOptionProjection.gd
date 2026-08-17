class_name TownConflictTensionOptionProjection
extends RefCounted


const CONFLICT_JUDGMENTS := preload(
	"res://world/runtime/conflict/TownConflictJudgments.gd"
)


static func decorate(
	resident_id: String,
	resident: Dictionary,
	options: Array,
	player_avatar_id: String,
	profile: Dictionary,
	has_active_conversation: bool,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in options:
		if value is not Dictionary:
			continue
		var projected := (value as Dictionary).duplicate(true)
		if String(projected.get("kind", "")) != "challenge":
			result.append(projected)
			continue
		var target_id := String(
			projected.get("target_resident_id", ""),
		).strip_edges()
		# 玩家化身永远不是攻击候选：人设再凶也不对化身生成攻击原因。
		if target_id == player_avatar_id:
			continue
		var cause := CONFLICT_JUDGMENTS.resident_conflict_cause_for_target(
			resident,
			target_id,
		)
		var profile_cause := CONFLICT_JUDGMENTS.resident_profile_conflict_motive(
			resident,
			target_id,
			profile,
		)
		if cause.is_empty():
			cause = profile_cause
			if cause.is_empty():
				continue
			_apply_profile_attack_identity(projected, resident_id, target_id)
		elif has_active_conversation and not profile_cause.is_empty():
			var profile_attack := projected.duplicate(true)
			_apply_profile_attack_identity(profile_attack, resident_id, target_id)
			profile_attack["source_event_ids"] = []
			_apply_cause(profile_attack, profile_cause)
			result.append(profile_attack)
		projected["source_event_ids"] = (
			cause.get("sourceEventIds", []) as Array
		).duplicate()
		_apply_cause(projected, cause)
		result.append(projected)
	return result


static func _apply_profile_attack_identity(
	option: Dictionary,
	resident_id: String,
	target_id: String,
) -> void:
	option["option_id"] = "profile-attack:%s:%s" % [resident_id, target_id]
	option["kind"] = "attack"
	option["tension_id"] = ""


static func _apply_cause(option: Dictionary, cause: Dictionary) -> void:
	option["source_kind"] = String(cause.get("sourceKind", ""))
	option["source_summary"] = String(cause.get("summary", ""))
	option["source_conversation_id"] = String(cause.get("conversationId", ""))
	if String(cause.get("sourceKind", "")) == "resident_profile_motive":
		option["meaning"] = (
			"这是本人公开人设形成的攻击倾向。想打就打，不需要对方先动手；"
			+ "动手时台词和动作描述必须符合本人身份与说话方式，让旁观者看得出"
			+ "“这就是他会做的事”。人设依据：%s"
			% String(cause.get("summary", ""))
		)
	else:
		option["meaning"] = (
			"只可依据本轮列出的真实事件当面质问；不能把怀疑当作事实。依据：%s"
			% String(cause.get("summary", ""))
		)
