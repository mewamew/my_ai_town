extends "res://tests/support/TownWorldTestCase.gd"
## diag_undercover_indoor.gd — 验证卧底"同屋暗杀"即时动作可用
## 场景: 谢眠(卧底)夜间进屋 home_01, 目标林岚同屋
## 新架构: 暗杀走 ACTION 管线(_prepare_assassination_action), 已无
## _decorate_conflict_tension_options 快照装饰; 室内同 space/region 即放行。

const UNDERCOVER_ID := "resident_xie_mian_01"
const TARGET_ID := "resident_lin_lan_01"


func _initialize() -> void:
	print("===== 卧底屋内暗杀 验证 =====")
	var data := _build_data()
	var opening := _garden_opening(data, "undercover indoor opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		_finish_suite("UNDERCOVER_INDOOR_PASS")
		return
	_advance_to_night(world)
	var residents := world.call("residents") as Dictionary
	# 注入卧底(门口) + 目标(床上), 同屋 home_01
	residents[UNDERCOVER_ID] = {
		"residentId": UNDERCOVER_ID,
		"spaceId": "home_01",
		"regionId": "region_portal_home_01_entry",
		"currentPlace": "北街一号住宅",
		"currentAction": {},
		"position": Vector2(16, 464),
		"arrivalState": {"status": "arrived"},
	}
	var lin: Variant = residents.get(TARGET_ID)
	if lin is Dictionary:
		(lin as Dictionary)["spaceId"] = "home_01"
		(lin as Dictionary)["regionId"] = "region_portal_home_01_entry"
		(lin as Dictionary)["position"] = Vector2(-168, -136)
	var undercover := residents[UNDERCOVER_ID] as Dictionary
	var action := {
		"action_id": "diag-indoor-assassinate-001",
		"type": "暗杀",
		"target_resident_id": TARGET_ID,
		"line": "该动手了。",
	}
	var prepared := world.call(
		"_prepare_assassination_action",
		UNDERCOVER_ID,
		undercover,
		action,
	) as Dictionary
	print("  准备 ok=%s errors=%s" % [str(prepared.get("ok", false)), str(prepared.get("errors", []))])
	_expect_equal(
		prepared.get("ok"),
		true,
		"卧底同屋暗杀通过准备 (%s)" % str(prepared.get("errors", [])),
	)
	world.call("stop")
	_finish_suite("UNDERCOVER_INDOOR_PASS")


func _advance_to_night(world: RefCounted) -> void:
	var env: Object = world.get("_environment")
	var current := int(env.call("get_absolute_minute"))
	var minute_of_day := posmod(current, 1440)
	var delta := 1200 - minute_of_day
	if delta <= 0:
		delta += 1440
	var result := world.call("advance", float(delta)) as Dictionary
	_expect_equal(result.get("ok"), true, "advance 到夜间 ok")
