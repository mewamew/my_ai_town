class_name AgentConflictContract
extends RefCounted


const ACTION_TYPES := ["争执", "攻击", "回应冲突", "介入冲突", "离开冲突"]
const ACTION_FIELDS := {
	"争执": ["action_id", "type", "tension_option_id", "line"],
	"攻击": ["action_id", "type", "target_resident_id", "attack_kind", "cause_id", "line"],
	"暗杀": ["action_id", "type", "target_resident_id", "line"],
	"制服": ["action_id", "type", "target_resident_id", "line"],
	"回应冲突": ["action_id", "type", "conflict_id", "response_kind", "line"],
	"介入冲突": ["action_id", "type", "conflict_id", "intervention_kind", "line"],
	"离开冲突": ["action_id", "type", "conflict_id", "reason", "line"],
}
const RESPONSE_KINDS := ["retaliate", "flee", "deescalate"]
const INTERVENTION_KINDS := ["join", "protect", "mediate"]
const ATTACK_KINDS := ["unarmed", "improvised", "lethal"]
const ATTACK_KIND_ALIASES := {
	"blood": "unarmed",
	"bite": "unarmed",
	"grapple": "unarmed",
	"punch": "unarmed",
	"fist": "unarmed",
	"claw": "unarmed",
	"扑咬": "unarmed",
	"撕咬": "unarmed",
	"爪击": "unarmed",
	"袭击": "unarmed",
	"拳脚": "unarmed",
	"扑上去按住她": "unarmed",
	"扑过去": "unarmed",
	"吸血": "unarmed",
	"徒手": "unarmed",
	"刀": "improvised",
	"棍棒": "improvised",
	"武器": "improvised",
	"拔刀": "improvised",
	"致命": "lethal",
	"杀死": "lethal",
	"杀": "lethal",
	"下杀手": "lethal",
	"取命": "lethal",
	"索命": "lethal",
	"致命一击": "lethal",
	"kill": "lethal",
	"murder": "lethal",
}
const TENSION_KINDS := ["challenge", "threaten", "apologize", "disengage", "attack", "assassinate", "subdue"]
# 动作类型别名: LLM 可能用英文/近义词表达动作类型, 提交前归一为合法中文类型。
const ACTION_TYPE_ALIASES := {
	"assassinate": "暗杀",
	"kill": "暗杀",
	"杀死": "暗杀",
	"杀人": "暗杀",
	"下杀手": "暗杀",
	"灭口": "暗杀",
	"subdue": "制服",
	"arrest": "制服",
	"逮捕": "制服",
	"抓捕": "制服",
	"制服": "制服",
	"拿下": "制服",
	"捉拿": "制服",
	"attack": "攻击",
	"打人": "攻击",
	"殴打": "攻击",
	"动手": "攻击",
	"talking": "搭话",
	"talk": "搭话",
	"对话": "搭话",
	"say": "答话",
	"回应": "答话",
	"answer": "答话",
	"stay": "待着",
	"等待": "待着",
	"wait": "待着",
	"休息": "待着",
	"go": "去",
	"move": "去",
	"前往": "去",
	"离开": "去",
}


static func normalize_model_decision_references(value: Dictionary, wake_packet: Dictionary) -> Dictionary:
	var normalized := value.duplicate(true)
	if normalized.get("conflict_intent") is Dictionary:
		var intent_wrapper := {
			"handling": "replace_current",
			"action": (normalized.get("conflict_intent") as Dictionary).duplicate(true),
		}
		var normalized_intent := normalize_model_decision_references(intent_wrapper, wake_packet)
		normalized["conflict_intent"] = normalized_intent.get("action", {}).duplicate(true)
	if String(normalized.get("handling", "")) != "replace_current" or normalized.get("action") is not Dictionary:
		return normalized
	var action := normalized.get("action") as Dictionary
	var action_type := String(action.get("type", "")).strip_edges()
	# 动作类型别名归一化: LLM 可能用英文或近义词写暗杀/攻击,
	# 统一归一为合法类型,避免"type 不是合法动作类型"被拒。
	var normalized_type: String = String(ACTION_TYPE_ALIASES.get(action_type, action_type))
	if normalized_type != action_type:
		action["type"] = normalized_type
		action_type = normalized_type
	if action_type == "暗杀":
		# 暗杀只接受 action_id/type/target_resident_id/line 四个字段（字段白名单）。
		# LLM 常把 prompt 冲突选项行里展示的 option_id（assassinate:卧底:目标）
		# 当作 cause_id 一并提交，导致白名单拒绝"包含未知字段"而丢掉动作。
		# 暗杀不需要原因 id，直接剥离这些多余字段，避免"词不对被丢掉"。
		action.erase("cause_id")
		action.erase("option_id")
		action.erase("attack_kind")
		return normalized
	if action_type == "制服":
		# 制服(警察版暗杀)同样只收四个字段,剥离 LLM 可能带的多余字段。
		action.erase("cause_id")
		action.erase("option_id")
		action.erase("attack_kind")
		return normalized
	if String(action.get("type", "")) != "攻击":
		return normalized
	var attack_kind := String(action.get("attack_kind", "")).strip_edges()
	if ATTACK_KIND_ALIASES.has(attack_kind):
		action["attack_kind"] = String(ATTACK_KIND_ALIASES[attack_kind])
	else:
		var lowered := attack_kind.to_lower()
		if _contains_any(attack_kind, ["致命", "杀死", "杀", "索命", "取命", "下杀手"]) or _contains_any(lowered, ["kill", "murder", "lethal"]):
			action["attack_kind"] = "lethal"
		elif _contains_any(attack_kind, ["刀", "棍", "武器", "瓶", "椅", "抢"]):
			action["attack_kind"] = "improvised"
		elif _contains_any(attack_kind, ["扑", "咬", "拳", "抓", "打", "按", "踢", "袭", "吸血"]) or _contains_any(lowered, ["grapple", "punch", "fist", "claw", "bite"]):
			action["attack_kind"] = "unarmed"
	var target_id := String(action.get("target_resident_id", "")).strip_edges()
	if target_id.is_empty():
		return normalized
	var matches: Array[Dictionary] = []
	for value_option: Variant in _snapshot(wake_packet).get("conflict_tension_options", []) as Array:
		if value_option is Dictionary:
			var option := value_option as Dictionary
			if String(option.get("kind", "")) == "attack" and String(option.get("target_resident_id", "")) == target_id and not String(option.get("option_id", "")).is_empty():
				matches.append(option)
	if matches.size() == 1:
		action["cause_id"] = String(matches[0].get("option_id", ""))
	return normalized


static func _contains_any(value: String, fragments: Array) -> bool:
	for fragment_value: Variant in fragments:
		if value.contains(String(fragment_value)):
			return true
	return false


static func validate_snapshot(snapshot: Dictionary, errors: Array[String]) -> void:
	if snapshot.has("conflicts"):
		_validate_conflicts(snapshot.get("conflicts"), errors)
	if snapshot.has("conflict_injuries"):
		_validate_injuries(snapshot.get("conflict_injuries"), errors)
	if snapshot.has("conflict_tension_options"):
		_validate_tension_options(snapshot.get("conflict_tension_options"), errors)


static func validate_action(action: Dictionary, wake_packet: Dictionary, errors: Array[String]) -> void:
	var action_type := String(action.get("type", ""))
	if not ACTION_TYPES.has(action_type):
		return
	_validate_exact_fields(action, ACTION_FIELDS[action_type], "action", errors)
	_required(action, "action_id", "action.action_id", errors)
	_required(action, "line", "action.line", errors)
	if action_type == "争执":
		var option := _tension_option(wake_packet, _required(action, "tension_option_id", "action.tension_option_id", errors))
		if option.is_empty():
			errors.append("action.tension_option_id 必须来自当前争执选项")
		elif String(option.get("kind", "")) == "attack":
			errors.append("攻击选项必须提交攻击动作")
	elif action_type == "攻击":
		var target_id := _required(action, "target_resident_id", "action.target_resident_id", errors)
		var attack_kind := _required(action, "attack_kind", "action.attack_kind", errors)
		var cause_id := _required(action, "cause_id", "action.cause_id", errors)
		if not ATTACK_KINDS.has(attack_kind):
			errors.append("action.attack_kind 不是合法攻击方式")
		if target_id.begins_with("person_"):
			errors.append("action.target_resident_id 不能是玩家化身")
		elif not _nearby_has(wake_packet, target_id):
			errors.append("action.target_resident_id 必须来自 snapshot.nearby")
		var cause := _tension_option(wake_packet, cause_id)
		if cause.is_empty():
			# 不设攻击门槛：居民决定动手即可。没有命中当前预设原因时，
			# 用本人台词作为自述起因，世界侧执行时补登记一条新争执原因。
			if String(action.get("line", "")).strip_edges().is_empty():
				errors.append("使用自述起因攻击时 action.line 必须说明动手缘由")
		elif String(cause.get("kind", "")) != "attack" or String(cause.get("target_resident_id", "")) != target_id:
			errors.append("action.cause_id 必须是该目标当前有效的威胁原因")
	else:
		var conflict := _conflict(wake_packet, _required(action, "conflict_id", "action.conflict_id", errors))
		if conflict.is_empty():
			errors.append("action.conflict_id 必须来自 snapshot.conflicts")
		elif action_type == "回应冲突":
			var kind := _required(action, "response_kind", "action.response_kind", errors)
			if not (conflict.get("response_kinds", []) as Array).has(kind):
				errors.append("action.response_kind 必须来自当前冲突可选回应")
		elif action_type == "介入冲突":
			var kind := _required(action, "intervention_kind", "action.intervention_kind", errors)
			if not (conflict.get("intervention_kinds", []) as Array).has(kind):
				errors.append("action.intervention_kind 必须来自当前冲突可选介入方式")
		else:
			_required(action, "reason", "action.reason", errors)
			if not bool(conflict.get("leave_allowed", false)):
				errors.append("当前冲突不允许该居民离开")


static func prompt_constraints(snapshot: Dictionary) -> Dictionary:
	var medical_follow_up: Dictionary = snapshot.get("medical_follow_up", {}) as Dictionary
	if (
		bool(medical_follow_up.get("required", false))
	):
		if not bool(medical_follow_up.get("at_required_place", false)):
			return {"去": {
				"fields": ["action_id", "type", "place", "line"],
				"places": [String(medical_follow_up.get("place_id", "诊所"))],
				"required": true,
				"reason": "重伤后必须先去诊所接受治疗",
			}}
		var at_clinic_actions := {
			"待着": {
				"fields": ["action_id", "type", "line"],
				"required": true,
				"reason": "已经到诊所，等待医生接诊和治疗",
			},
		}
		if snapshot.get("conversation") is Dictionary:
			at_clinic_actions["答话"] = {
				"fields": [
					"action_id",
					"type",
					"conversation_id",
					"say",
					"narration",
					"photos",
					"end",
					"medical_response",
				],
				"required": true,
				"reason": "正在接受医生问诊，需要按当前对话回答",
			}
		return at_clinic_actions
	if snapshot.get("conversation") is Dictionary:
		return {}
	var actions := {}
	var conflicts: Array = snapshot.get("conflicts", []) as Array
	var already_in_conflict := false
	if not conflicts.is_empty():
		for conflict_value: Variant in conflicts:
			if (
				conflict_value is Dictionary
				and String((conflict_value as Dictionary).get("role", "witness"))
				!= "witness"
			):
				already_in_conflict = true
		actions["回应冲突"] = {"fields": ACTION_FIELDS["回应冲突"].duplicate(), "options": conflicts.duplicate(true)}
		actions["介入冲突"] = {"fields": ACTION_FIELDS["介入冲突"].duplicate(), "options": conflicts.duplicate(true)}
		actions["离开冲突"] = {"fields": ACTION_FIELDS["离开冲突"].duplicate(), "options": conflicts.duplicate(true)}
	var tension_options: Array = snapshot.get("conflict_tension_options", []) as Array
	var dispute_options: Array = []
	var attack_causes: Array = []
	var assassinate_causes: Array = []
	var subdue_causes: Array = []
	for value_option: Variant in tension_options:
		if value_option is not Dictionary:
			continue
		var option := value_option as Dictionary
		var normalized := {
			"option_id": String(option.get("option_id", "")),
			"kind": String(option.get("kind", "")),
			"target_resident_id": String(option.get("target_resident_id", "")),
			"target_name": String(option.get("target_name", "")),
			"meaning": String(option.get("meaning", "")),
			"source_kind": String(option.get("source_kind", "")),
			"source_summary": String(option.get("source_summary", "")),
		}
		if String(option.get("kind", "")) == "attack":
			var cause := normalized.duplicate(true)
			cause["cause_id"] = String(cause.get("option_id", ""))
			cause.erase("option_id")
			attack_causes.append(cause)
		elif String(option.get("kind", "")) == "assassinate":
			var assassinate_cause := normalized.duplicate(true)
			assassinate_cause["cause_id"] = String(assassinate_cause.get("option_id", ""))
			assassinate_cause.erase("option_id")
			assassinate_causes.append(assassinate_cause)
		elif String(option.get("kind", "")) == "subdue":
			var subdue_cause := normalized.duplicate(true)
			subdue_cause["cause_id"] = String(subdue_cause.get("option_id", ""))
			subdue_cause.erase("option_id")
			subdue_causes.append(subdue_cause)
		else:
			dispute_options.append(normalized)
	if not already_in_conflict and not dispute_options.is_empty():
		actions["争执"] = {"fields": ACTION_FIELDS["争执"].duplicate(), "options": dispute_options}
	if not already_in_conflict and not attack_causes.is_empty():
		actions["攻击"] = {"fields": ACTION_FIELDS["攻击"].duplicate(), "causes": attack_causes, "attack_kinds": ATTACK_KINDS.duplicate()}
	if not already_in_conflict and not assassinate_causes.is_empty():
		actions["暗杀"] = {"fields": ACTION_FIELDS["暗杀"].duplicate(), "causes": assassinate_causes}
	if not already_in_conflict and not subdue_causes.is_empty():
		actions["制服"] = {"fields": ACTION_FIELDS["制服"].duplicate(), "causes": subdue_causes}
	return actions


static func render_snapshot_lines(snapshot: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var injuries: Array = snapshot.get("conflict_injuries", []) as Array
	if not injuries.is_empty():
		lines.append("当前冲突造成的伤势：")
		for value_injury: Variant in injuries:
			if value_injury is not Dictionary:
				continue
			var injury := value_injury as Dictionary
			lines.append(
				"- %s；来源%s；治疗状态%s；%s"
				% [
					"重伤" if String(injury.get("severity", "")) == "heavy" else "轻伤",
					String(injury.get("source_actor_name", "对方")),
					String(injury.get("treatment_status", "")),
					String(injury.get("cause_summary", "")),
				]
			)
	var conflicts: Array = snapshot.get("conflicts", []) as Array
	if not conflicts.is_empty():
		lines.append("当前可回应冲突：")
		for value_conflict: Variant in conflicts:
			if value_conflict is Dictionary:
				var conflict := value_conflict as Dictionary
				lines.append("- %s；阶段%s；参与者%s" % [String(conflict.get("conflict_id", "")), String(conflict.get("phase", "")), ",".join(conflict.get("participant_names", []) as Array)])
	var options: Array = snapshot.get("conflict_tension_options", []) as Array
	if not options.is_empty():
		lines.append("当前有权威依据的争执或攻击选项：")
		for value_option: Variant in options:
			if value_option is Dictionary:
				var option := value_option as Dictionary
				lines.append("- %s [%s] 对%s：%s" % [String(option.get("option_id", "")), String(option.get("kind", "")), String(option.get("target_name", "")), String(option.get("meaning", ""))])
	return lines


static func _validate_conflicts(value: Variant, errors: Array[String]) -> void:
	if value is not Array:
		errors.append("snapshot.conflicts 必须是数组")
		return
	var seen := {}
	for index in (value as Array).size():
		var path := "snapshot.conflicts[%d]" % index
		if (value as Array)[index] is not Dictionary:
			errors.append("%s 必须是对象" % path)
			continue
		var conflict := (value as Array)[index] as Dictionary
		var conflict_id := _required(conflict, "conflict_id", "%s.conflict_id" % path, errors)
		if seen.has(conflict_id): errors.append("%s.conflict_id 重复" % path)
		seen[conflict_id] = true
		var ids := conflict.get("participant_resident_ids", []) as Array
		var names := conflict.get("participant_names", []) as Array
		if ids.size() < 2 or ids.size() != names.size(): errors.append("%s 参与者编号与姓名必须一一对应且至少两人" % path)
		_validate_kinds(conflict.get("response_kinds"), RESPONSE_KINDS, "%s.response_kinds" % path, errors)
		_validate_kinds(conflict.get("intervention_kinds"), INTERVENTION_KINDS, "%s.intervention_kinds" % path, errors)
		if conflict.get("leave_allowed") is not bool: errors.append("%s.leave_allowed 必须是布尔值" % path)


static func _validate_tension_options(value: Variant, errors: Array[String]) -> void:
	if value is not Array:
		errors.append("snapshot.conflict_tension_options 必须是数组")
		return
	var seen := {}
	for index in (value as Array).size():
		var path := "snapshot.conflict_tension_options[%d]" % index
		if (value as Array)[index] is not Dictionary:
			errors.append("%s 必须是对象" % path); continue
		var option := (value as Array)[index] as Dictionary
		var option_id := _required(option, "option_id", "%s.option_id" % path, errors)
		if seen.has(option_id): errors.append("%s.option_id 重复" % path)
		seen[option_id] = true
		var kind := _required(option, "kind", "%s.kind" % path, errors)
		if not TENSION_KINDS.has(kind): errors.append("%s.kind 不是合法争执选项" % path)
		_required(option, "target_resident_id", "%s.target_resident_id" % path, errors)
		_required(option, "target_name", "%s.target_name" % path, errors)
		_required(option, "meaning", "%s.meaning" % path, errors)
		if kind == "attack" and String(option.get("tension_id", "")).is_empty() and String(option.get("source_kind", "")) != "resident_profile_motive":
			errors.append("%s 无争执攻击只能来自居民本人公开人设动机" % path)


static func _validate_injuries(value: Variant, errors: Array[String]) -> void:
	if value is not Array:
		errors.append("snapshot.conflict_injuries 必须是数组")
		return
	var seen := {}
	for index in (value as Array).size():
		var path := "snapshot.conflict_injuries[%d]" % index
		if (value as Array)[index] is not Dictionary:
			errors.append("%s 必须是对象" % path)
			continue
		var injury := (value as Array)[index] as Dictionary
		var injury_id := _required(injury, "injury_id", "%s.injury_id" % path, errors)
		if seen.has(injury_id):
			errors.append("%s.injury_id 重复" % path)
		seen[injury_id] = true
		var severity := _required(injury, "severity", "%s.severity" % path, errors)
		if severity not in ["light", "heavy"]:
			errors.append("%s.severity 不是合法伤势程度" % path)
		_required(injury, "source_actor_id", "%s.source_actor_id" % path, errors)
		_required(injury, "treatment_status", "%s.treatment_status" % path, errors)


static func _snapshot(wake_packet: Dictionary) -> Dictionary:
	return wake_packet.get("snapshot", {}) as Dictionary

static func _tension_option(wake_packet: Dictionary, option_id: String) -> Dictionary:
	for value_option: Variant in _snapshot(wake_packet).get("conflict_tension_options", []) as Array:
		if value_option is Dictionary and String((value_option as Dictionary).get("option_id", "")) == option_id: return value_option as Dictionary
	return {}

static func _conflict(wake_packet: Dictionary, conflict_id: String) -> Dictionary:
	for value_conflict: Variant in _snapshot(wake_packet).get("conflicts", []) as Array:
		if value_conflict is Dictionary and String((value_conflict as Dictionary).get("conflict_id", "")) == conflict_id: return value_conflict as Dictionary
	return {}

static func _nearby_has(wake_packet: Dictionary, resident_id: String) -> bool:
	for value_person: Variant in _snapshot(wake_packet).get("nearby", []) as Array:
		if value_person is Dictionary and String((value_person as Dictionary).get("resident_id", "")) == resident_id: return true
	return false

static func _required(value: Dictionary, field: String, path: String, errors: Array[String]) -> String:
	if value.get(field) is not String or String(value.get(field, "")).strip_edges().is_empty():
		errors.append("%s 必须是非空文本" % path); return ""
	return String(value.get(field)).strip_edges()

static func _validate_kinds(value: Variant, allowed: Array, path: String, errors: Array[String]) -> void:
	if value is not Array:
		errors.append("%s 必须是数组" % path); return
	for index in (value as Array).size():
		if (value as Array)[index] is not String or not allowed.has(String((value as Array)[index])): errors.append("%s[%d] 不是合法选项" % [path, index])

static func _validate_exact_fields(value: Dictionary, fields: Array, path: String, errors: Array[String]) -> void:
	for key: Variant in value.keys():
		if key is not String or not fields.has(String(key)): errors.append("%s.%s 不是允许字段" % [path, String(key)])
