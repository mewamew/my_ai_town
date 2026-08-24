extends SceneTree
## diag_intent_kill.gd — 验证 conflict_intent.attack_kind="kill" 能通过校验
const INTENT := preload("res://agent/conflict/AgentConflictIntent.gd")

func _init() -> void:
	print("===== conflict_intent kill 归一化验证 =====")
	var intent := {
		"action_id": "x-1-动手",
		"type": "攻击",
		"target_resident_id": "resident_lin_lan_01",
		"attack_kind": "kill",
		"cause_id": "profile-attack:resident_hanako_01:resident_lin_lan_01",
		"line": "他睡得正沉，正好动手",
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
	var errors := INTENT.validate(intent, wake)
	print("校验错误数:", errors.size())
	if errors.is_empty():
		print("[PASS] kill 通过校验(已归一化为lethal)")
		quit(0)
	else:
		for e in errors:
			print("[FAIL]", e)
		quit(1)
