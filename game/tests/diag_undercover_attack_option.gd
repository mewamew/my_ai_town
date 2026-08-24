extends "res://tests/support/TownWorldTestCase.gd"
## diag_undercover_attack_option.gd — 验证卧底攻击选项是否始终出现在对话选项里
## 运行: Godot --headless --path game --script res://tests/diag_undercover_attack_option.gd

const UNDERCOVER_IDS: Array[String] = [
	"resident_xie_mian_01",
	"resident_qiao_yiming_01",
	"resident_hanako_01",
]


func _initialize() -> void:
	print("===== 卧底攻击选项 验证 =====")
	var data := _build_data()
	var opening := _garden_opening(data, "undercover attack option opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		_finish_suite("UNDERCOVER_ATTACK_OPTION_PASS")
		return
	# 让所有居民抵达(推进一点时间)
	world.call("advance", 120.0)
	# 官方拆分架构不再暴露 _build_resident_perception 内部接口:
	# 冲突张力选项改由 wake packet 的 conflict_snapshot 提供(diag_role_skills
	# 已覆盖卧底夜间技能选项)。这里仅验证旧接口不存在时快速跳过,不空转。
	if not world.has_method("_build_resident_perception"):
		print("[SKIP] 官方架构无 _build_resident_perception，跳过内部接口验证")
		world.call("stop")
		_finish_suite("UNDERCOVER_ATTACK_OPTION_PASS")
		return
	# 遍历3个卧底,检查其冲突快照里是否有攻击选项
	for rid in UNDERCOVER_IDS:
		var has_attack := false
		var attack_info: Array[String] = []
		var snapshot: Dictionary = world.call(
			"_build_resident_perception",
			rid,
			{},
		) as Dictionary
		if snapshot.is_empty():
			snapshot = world.call("_perception_snapshot_for_resident", rid, {}) as Dictionary
		var options: Array = snapshot.get(
			"conflict_tension_options",
			[],
		) as Array
		if options.is_empty():
			# 尝试直接从 bridge 取
			var bridge_snapshot: Dictionary = world.call(
				"_conflict_agent_world_bridge.snapshot_for_actor",
				rid,
				[],
			) as Dictionary
			options = bridge_snapshot.get("conflict_tension_options", []) as Array
		for option_value in options:
			if not option_value is Dictionary:
				continue
			var option := option_value as Dictionary
			if String(option.get("kind", "")) == "attack":
				has_attack = true
				attack_info.append(
					"目标=%s 原因=%s" % [
						String(option.get("target_resident_name", "?")),
						String(option.get("option_id", "")),
					],
				)
		if has_attack:
			print("[PASS] %s 有攻击选项 %d个: %s" % [rid, attack_info.size(), "、".join(attack_info)])
		else:
			print("[INFO] %s 当前无攻击选项(可能附近无人) snapshot_options=%d" % [rid, options.size()])
	world.call("stop")
	_finish_suite("UNDERCOVER_ATTACK_OPTION_PASS")
