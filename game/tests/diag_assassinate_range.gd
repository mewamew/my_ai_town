extends "res://tests/support/TownWorldTestCase.gd"
## diag_assassinate_range.gd — 用真实卧底身份验证暗杀感知距离判定
## 场景: 谢眠(卧底) vs 林岚(目标)
## 1) 近距(≤320px同region) → 暗杀准备通过
## 2) 远距(>320px同region) → 拒绝
## 3) 不同region同space → 拒绝

const UNDERCOVER_ID := "resident_xie_mian_01"  # 真实卧底
const TARGET_ID := "resident_lin_lan_01"


func _initialize() -> void:
	print("===== 暗杀感知距离 判定验证(真实卧底身份) =====")
	_verify_near_target_ok()
	_verify_far_target_rejected()
	_verify_diff_region_rejected()
	_finish_suite("ASSASSINATE_RANGE_PASS")


# 注入谢眠(卧底)到世界
func _inject_undercover(world: RefCounted, position: Vector2, space: String, region: String) -> Dictionary:
	var residents := world.call("residents") as Dictionary
	var undercover := {
		"residentId": UNDERCOVER_ID,
		"spaceId": space,
		"regionId": region,
		"currentPlace": "测试地点",
		"currentAction": {},
		"position": position,
		"arrivalState": {"status": "arrived"},
		"socialState": {"home": "住处", "job": "乐师", "workplace": "住处"},
		"attributes": {"name": "谢眠"},
	}
	residents[UNDERCOVER_ID] = undercover
	return undercover


# 把林岚放到指定位置
func _place_target(world: RefCounted, position: Vector2, space: String, region: String) -> void:
	var residents := world.call("residents") as Dictionary
	var target: Variant = residents.get(TARGET_ID)
	if target == null:
		return
	var t := target as Dictionary
	t["spaceId"] = space
	t["regionId"] = region
	t["position"] = position


func _run_prepare(world: RefCounted, actor: Dictionary) -> Dictionary:
	var action := {
		"action_id": "diag-range-%s" % str(Time.get_ticks_usec()),
		"type": "暗杀",
		"target_resident_id": TARGET_ID,
		"line": "动手。",
	}
	return world.call("_prepare_assassination_action", UNDERCOVER_ID, actor, action) as Dictionary


func _verify_near_target_ok() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "range near opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	_advance_to_minute_of_day(world, 1200)
	var actor := _inject_undercover(world, Vector2(100, 100), "town_outdoor", "outdoor_plaza_01")
	_place_target(world, Vector2(200, 100), "town_outdoor", "outdoor_plaza_01")
	var prepared := _run_prepare(world, actor)
	print("  近距(100px同region) ok=%s errors=%s" % [
		str(prepared.get("ok", false)),
		str(prepared.get("errors", [])),
	])
	_expect_equal(prepared.get("ok"), true, "卧底近距暗杀准备通过")
	world.call("stop")


func _verify_far_target_rejected() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "range far opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	_advance_to_minute_of_day(world, 1200)
	var actor := _inject_undercover(world, Vector2(100, 100), "town_outdoor", "outdoor_plaza_01")
	# 距离 600px > 320px 感知范围
	_place_target(world, Vector2(700, 100), "town_outdoor", "outdoor_plaza_01")
	var prepared := _run_prepare(world, actor)
	print("  远距(600px) ok=%s errors=%s" % [
		str(prepared.get("ok", false)),
		str(prepared.get("errors", [])),
	])
	_expect_equal(prepared.get("ok"), false, "卧底远距暗杀被拒绝")
	world.call("stop")


func _verify_diff_region_rejected() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "range region opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	_advance_to_minute_of_day(world, 1200)
	var actor := _inject_undercover(world, Vector2(100, 100), "town_outdoor", "outdoor_plaza_01")
	# 同space不同region(距离近也不行)
	_place_target(world, Vector2(150, 100), "town_outdoor", "outdoor_garden_01")
	var prepared := _run_prepare(world, actor)
	print("  不同region ok=%s errors=%s" % [
		str(prepared.get("ok", false)),
		str(prepared.get("errors", [])),
	])
	_expect_equal(prepared.get("ok"), false, "卧底跨region暗杀被拒绝")
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
