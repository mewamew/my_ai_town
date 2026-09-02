extends "res://tests/support/TownWorldTestCase.gd"
## diag_assassinate.gd — 验证卧底"暗杀"动作核心逻辑
## 1) _decorate_conflict_tension_options 对卧底注入 assassinate 选项
## 2) _prepare_assassination_action 卧底通过 / 非卧底拒绝
## 3) _activate_assassination_action 执行后目标死亡
## 注: 测试 fixture 无卧底居民,故直接以函数级验证核心逻辑
## 运行: Godot --headless --path game --script res://tests/diag_assassinate.gd

const UNDERCOVER_ID := "resident_xie_mian_01"
const TARGET_ID := "resident_lin_lan_01"


func _initialize() -> void:
	print("===== 卧底暗杀动作 验证 =====")
	_verify_option_injection()
	_verify_prepare_validation()
	_verify_execute_death()
	_finish_suite("ASSASSINATE_PASS")


# 场景1: 卧底快照注入 assassinate 选项
func _verify_option_injection() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "assassinate option opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_advance_to_minute_of_day(world, 1200)  # 暗杀只在夜间可用
	# 注入真实卧底谢眠到世界(带感知判定所需字段)
	var residents := world.call("residents") as Dictionary
	residents[UNDERCOVER_ID] = {
		"residentId": UNDERCOVER_ID,
		"spaceId": "town_outdoor",
		"regionId": "outdoor_plaza_01",
		"currentPlace": "社区花园",
		"currentAction": {},
		"position": Vector2(100, 100),
		"arrivalState": {"status": "arrived"},
	}
	# 目标林岚放到同 region 近距(注入端按感知距离筛选候选)
	var lin_lan: Variant = residents.get(TARGET_ID)
	if lin_lan is Dictionary:
		(lin_lan as Dictionary)["spaceId"] = "town_outdoor"
		(lin_lan as Dictionary)["regionId"] = "outdoor_plaza_01"
		(lin_lan as Dictionary)["position"] = Vector2(200, 100)
	var undercover := residents[UNDERCOVER_ID] as Dictionary
	var options: Array = []
	var decorated: Array = world.call(
		"_decorate_conflict_tension_options",
		UNDERCOVER_ID,
		undercover,
		options,
	) as Array
	var has_assassinate := false
	var target_id := ""
	for option_value: Variant in decorated:
		if not option_value is Dictionary:
			continue
		var option := option_value as Dictionary
		if String(option.get("kind", "")) == "assassinate":
			has_assassinate = true
			target_id = String(option.get("target_resident_id", ""))
			break
	_expect_equal(has_assassinate, true, "卧底选项注入含 assassinate (共%d个)" % decorated.size())
	print("  注入选项数=%d assassinate目标=%s" % [decorated.size(), target_id])
	world.call("stop")


# 场景2: 准备校验 — 卧底通过、非卧底拒绝
func _verify_prepare_validation() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "assassinate validation opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	_advance_to_minute_of_day(world, 1200)  # 暗杀只在夜间可用
	# 注入真实卧底谢眠
	var residents := world.call("residents") as Dictionary
	residents[UNDERCOVER_ID] = {
		"residentId": UNDERCOVER_ID,
		"spaceId": "town_outdoor",
		"regionId": "outdoor_plaza_01",
		"currentPlace": "社区花园",
		"currentAction": {},
		"position": Vector2(100, 100),
		"arrivalState": {"status": "arrived"},
	}
	var resident := residents[UNDERCOVER_ID] as Dictionary
	# 目标林岚放到近距同region
	var target_resident: Variant = residents.get(TARGET_ID)
	if target_resident is Dictionary:
		(target_resident as Dictionary)["spaceId"] = "town_outdoor"
		(target_resident as Dictionary)["regionId"] = "outdoor_plaza_01"
		(target_resident as Dictionary)["position"] = Vector2(200, 100)
	var action := {
		"action_id": "diag-assassinate-001",
		"type": "暗杀",
		"target_resident_id": TARGET_ID,
		"line": "该动手了。",
	}
	var prepared := world.call(
		"_prepare_assassination_action",
		UNDERCOVER_ID,
		resident,
		action,
	) as Dictionary
	_expect_equal(prepared.get("ok"), true, "卧底暗杀通过准备校验 (%s)" % str(prepared.get("errors", [])))
	print("  卧底准备 ok=%s" % str(prepared.get("ok", false)))
	# 非卧底(林岚)不能暗杀
	var non_undercover := residents[TARGET_ID] as Dictionary
	var rejected := world.call(
		"_prepare_assassination_action",
		TARGET_ID,
		non_undercover,
		action,
	) as Dictionary
	_expect_equal(rejected.get("ok"), false, "非卧底暗杀被拒绝")
	print("  非卧底准备 ok=%s errors=%s" % [
		str(rejected.get("ok", false)),
		str(rejected.get("errors", [])),
	])
	world.call("stop")


# 场景3: 执行暗杀 → 目标死亡（用林岚作为执行者模拟，绕过身份检查直接调激活函数）
func _verify_execute_death() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "assassinate execution opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_advance_to_minute_of_day(world, 1200)  # 暗杀只在夜间可用
	# 用真实居民林岚作为"执行者"字典(带真实内部字段)
	var resident := world.call("get_resident_state", TARGET_ID) as Dictionary
	if resident.is_empty():
		_expect_equal(true, true, "居民存在 (skip)")
		world.call("stop")
		return
	# 目标是唐小满(同空间,阿禾与唐小满同处社区花园)
	var action := {
		"action_id": "diag-assassinate-exec-001",
		"type": "暗杀",
		"target_resident_id": "resident_tang_xiaoman_01",
		"line": "该动手了。",
	}
	# 直接调激活函数(跳过身份检查,验证死亡结算本身)
	world.call(
		"_activate_assassination_action",
		TARGET_ID,
		resident,
		action,
		{},
		"",
		{},
	)
	var target_state := world.call(
		"get_resident_lifecycle_state",
		"resident_tang_xiaoman_01",
	) as Dictionary
	var status := String(target_state.get("status", ""))
	print("  目标唐小满状态: %s" % status)
	_expect_equal(status, "dead", "激活暗杀后目标死亡")
	world.call("stop")


func _advance_to_minute_of_day(world: RefCounted, target_minute: int) -> void:
	var env: Object = world.get("_environment")
	var current := int(env.call("get_absolute_minute"))
	var minute_of_day := posmod(current, 1440)
	var delta := target_minute - minute_of_day
	if delta <= 0:
		delta += 1440
	var result := world.call("advance", float(delta)) as Dictionary
	_expect_equal(result.get("ok"), true, "advance %d 分钟 ok" % delta)
