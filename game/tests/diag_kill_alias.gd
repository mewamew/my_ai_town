extends SceneTree
## diag_kill_alias.gd — 验证 attack_kind:"kill" 是否被归一化为 lethal
const CONFLICT := preload("res://agent/conflict/AgentConflictContract.gd")

func _init() -> void:
	print("===== kill 别名归一化 验证 =====")
	var decision := {
		"decision_id": "t-1",
		"handling": "replace_current",
		"action": {
			"action_id": "x-1",
			"type": "攻击",
			"target_resident_id": "resident_lin_lan_01",
			"attack_kind": "kill",
			"cause_id": "profile-attack:resident_hanako_01:resident_lin_lan_01",
			"line": "他睡得正沉，正好动手",
		},
	}
	var wake := {
		"snapshot": {
			"nearby": [{"resident_id": "resident_lin_lan_01"}],
			"conflict_tension_options": [{
				"option_id": "profile-attack:resident_hanako_01:resident_lin_lan_01",
				"kind": "attack",
				"target_resident_id": "resident_lin_lan_01",
			}],
		},
	}
	var normalized := CONFLICT.normalize_model_decision_references(decision, wake)
	var action := normalized.get("action", {}) as Dictionary
	var ak := String(action.get("attack_kind", ""))
	print("归一化前: kill → 归一化后:", ak)
	if ak == "lethal":
		print("[PASS] kill 已归一化为 lethal")
		quit(0)
	else:
		print("[FAIL] kill 未被归一化, 值为:", ak)
		quit(1)
