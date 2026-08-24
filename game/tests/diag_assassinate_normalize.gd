extends "res://tests/support/TownWorldTestCase.gd"
## diag_assassinate_normalize.gd — 验证暗杀容错修复
## 1) LLM 提交暗杀带 cause_id/option_id 时被剥离(不再白名单拒绝)
## 2) actions 渲染含 causes 目标清单

const CONFLICT_CONTRACT := preload("res://agent/conflict/AgentConflictContract.gd")

func _initialize() -> void:
	print("===== 暗杀容错 验证 =====")
	_verify_normalize_strips_extra_fields()
	_verify_render_shows_causes()
	_finish_suite("ASSASSINATE_NORMALIZE_PASS")


func _verify_normalize_strips_extra_fields() -> void:
	var decision := {
		"handling": "replace_current",
		"action": {
			"action_id": "diag-norm-001",
			"type": "暗杀",
			"target_resident_id": "resident_lin_lan_01",
			"cause_id": "assassinate:resident_xie_mian_01:resident_lin_lan_01",
			"attack_kind": "lethal",
			"line": "动手。",
		},
	}
	var normalized := CONFLICT_CONTRACT.normalize_model_decision_references(decision, {})
	var action := normalized.get("action", {}) as Dictionary
	var has_cause := action.has("cause_id")
	var has_attack_kind := action.has("attack_kind")
	print("  剥离 cause_id=%s attack_kind=%s 字段剩=%s" % [
		str(has_cause), str(has_attack_kind), str(action.keys()),
	])
	_expect_equal(has_cause, false, "暗杀动作剥离 cause_id")
	_expect_equal(has_attack_kind, false, "暗杀动作剥离 attack_kind")
	_expect_equal(action.get("type"), "暗杀", "type 保持暗杀")
	_expect_equal(action.get("target_resident_id"), "resident_lin_lan_01", "target 保持")


func _verify_render_shows_causes() -> void:
	var snapshot := {
		"nearby": [
			{
				"resident_id": "resident_lin_lan_01",
				"name": "林岚",
				"available_for_conversation": true,
			},
		],
		"conflict_tension_options": [
			{
				"option_id": "assassinate:resident_xie_mian_01:resident_lin_lan_01",
				"kind": "assassinate",
				"target_resident_id": "resident_lin_lan_01",
				"target_name": "林岚",
				"meaning": "这是卧底的本职行动。",
				"source_kind": "resident_profile_motive",
				"source_summary": "卧底任务：清除镇上居民。",
			},
		],
	}
	var constraints := CONFLICT_CONTRACT.prompt_constraints(snapshot)
	var actions := constraints as Dictionary
	var assassinate := actions.get("暗杀", {}) as Dictionary
	_expect_equal(not assassinate.is_empty(), true, "prompt_constraints 含暗杀动作")
	var causes := assassinate.get("causes", []) as Array
	_expect_equal(causes.size(), 1, "暗杀 causes 含 1 个目标")
	var cause := causes[0] as Dictionary
	_expect_equal(cause.get("target_resident_id"), "resident_lin_lan_01", "cause 目标正确")
	_expect_equal(cause.get("cause_id"), "assassinate:resident_xie_mian_01:resident_lin_lan_01", "cause_id 正确")
