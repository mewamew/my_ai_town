class_name AgentConflictIntent
extends RefCounted


const FIELDS := [
	"action_id",
	"type",
	"target_resident_id",
	"attack_kind",
	"cause_id",
	"line",
]
const CONFLICT_CONTRACT := preload("res://agent/conflict/AgentConflictContract.gd")


static func validate(value: Variant, wake_packet: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if value is not Dictionary:
		errors.append("conflict_intent 必须是对象")
		return errors
	var intent := value as Dictionary
	for key_value: Variant in intent:
		if not FIELDS.has(String(key_value)):
			errors.append("conflict_intent 包含未知字段：%s" % String(key_value))
	for field_name: String in FIELDS:
		if not intent.has(field_name):
			errors.append("conflict_intent 缺少字段：%s" % field_name)
	if not errors.is_empty():
		return errors
	if String(intent.get("type", "")) != "攻击":
		errors.append("conflict_intent.type 必须是攻击")
	if not _non_empty(intent.get("action_id")):
		errors.append("conflict_intent.action_id 必须是非空文本")
	var attack := intent.duplicate(true)
	# 先归一化 attack_kind 别名(kill/murder/致命等 → 合法值),
	# 再走严格校验,避免 LLM 写 kill 被"不是合法攻击方式"打回。
	attack = CONFLICT_CONTRACT.normalize_model_decision_references(
		{"handling": "replace_current", "action": attack},
		wake_packet,
	).get("action", attack)
	CONFLICT_CONTRACT.validate_action(attack, wake_packet, errors)
	return errors


static func canonicalize(value: Dictionary) -> Dictionary:
	var canonical := {}
	for field_name: String in FIELDS:
		if value.has(field_name):
			canonical[field_name] = value[field_name]
	return canonical


static func _non_empty(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty()
