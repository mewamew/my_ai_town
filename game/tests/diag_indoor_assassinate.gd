extends "res://tests/support/TownWorldTestCase.gd"
## diag_indoor_assassinate.gd — 验证室内远距(门→床627px)暗杀
## 真实卧底谢眠在门口, 目标林岚在床上, 距离627px > 感知320px
## 室内应放行(同屋即够得着), 户外才用感知距离

const UNDERCOVER_ID := "resident_xie_mian_01"
const TARGET_ID := "resident_lin_lan_01"


func _initialize() -> void:
	print("===== 室内暗杀距离 判定验证 =====")
	_verify_indoor_far_ok()
	_verify_outdoor_far_rejected()
	_finish_suite("INDOOR_ASSASSINATE_PASS")


func _inject(world: RefCounted, actor_pos: Vector2, target_pos: Vector2, space: String, region: String) -> Dictionary:
	var residents := world.call("residents") as Dictionary
	residents[UNDERCOVER_ID] = {
		"residentId": UNDERCOVER_ID,
		"spaceId": space,
		"regionId": region,
		"currentPlace": "测试",
		"currentAction": {},
		"position": actor_pos,
		"arrivalState": {"status": "arrived"},
		"socialState": {"home": "住处", "job": "乐师", "workplace": "住处"},
		"attributes": {"name": "谢眠"},
	}
	var lin: Variant = residents.get(TARGET_ID)
	if lin is Dictionary:
		(lin as Dictionary)["spaceId"] = space
		(lin as Dictionary)["regionId"] = region
		(lin as Dictionary)["position"] = target_pos
	return residents[UNDERCOVER_ID] as Dictionary


func _verify_indoor_far_ok() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "indoor far opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	_advance_to_minute_of_day(world, 1200)
	# 门(16,464) → 床(-168,-136) 距离约627px, 室内 home_01
	var actor := _inject(world, Vector2(16, 464), Vector2(-168, -136), "home_01", "region_portal_home_01_entry")
	var action := {
		"action_id": "diag-indoor-%s" % str(Time.get_ticks_usec()),
		"type": "暗杀",
		"target_resident_id": TARGET_ID,
		"line": "摸进来动手。",
	}
	var prepared := world.call("_prepare_assassination_action", UNDERCOVER_ID, actor, action) as Dictionary
	print("  室内门→床627px ok=%s errors=%s" % [str(prepared.get("ok", false)), str(prepared.get("errors", []))])
	_expect_equal(prepared.get("ok"), true, "室内远距暗杀准备通过")
	world.call("stop")


func _verify_outdoor_far_rejected() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "outdoor far opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	_advance_to_minute_of_day(world, 1200)
	# 户外同region但相距600px > 320 感知范围 → 拒绝
	var actor := _inject(world, Vector2(100, 100), Vector2(700, 100), "town_outdoor", "outdoor_plaza_01")
	var action := {
		"action_id": "diag-outdoor-%s" % str(Time.get_ticks_usec()),
		"type": "暗杀",
		"target_resident_id": TARGET_ID,
		"line": "动手。",
	}
	var prepared := world.call("_prepare_assassination_action", UNDERCOVER_ID, actor, action) as Dictionary
	print("  户外600px ok=%s errors=%s" % [str(prepared.get("ok", false)), str(prepared.get("errors", []))])
	_expect_equal(prepared.get("ok"), false, "户外远距暗杀被拒绝")
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
