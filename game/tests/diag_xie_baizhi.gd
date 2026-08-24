extends "res://tests/support/TownWorldTestCase.gd"
## 验证: 卧底同屋有人时注入 assassinate (用fixture居民林岚当目标)

const UNDERCOVER_ID := "resident_xie_mian_01"
const TARGET_ID := "resident_lin_lan_01"

func _initialize() -> void:
	print("===== 卧底同屋目标 暗杀选项注入 =====\n")
	_verify_option_injection()
	_finish_suite("XIE_BAIZHI_PASS")


func _verify_option_injection() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "xie baizhi opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	var residents := world.call("residents") as Dictionary
	# 注入谢眠(卧底)
	residents[UNDERCOVER_ID] = {
		"residentId": UNDERCOVER_ID,
		"spaceId": "home_01",
		"regionId": "region_portal_home_01_entry",
		"currentPlace": "北街一号住宅",
		"currentAction": {},
		"position": Vector2(56, 328),
		"arrivalState": {"status": "arrived"},
		"socialState": {"job": "乐师", "home": "南街十号住宅"},
		"attributes": {"name": "谢眠"},
	}
	# 林岚(fixture存在, 已在order)移到同屋
	var lin: Variant = residents.get(TARGET_ID)
	if lin is Dictionary:
		(lin as Dictionary)["spaceId"] = "home_01"
		(lin as Dictionary)["regionId"] = "region_portal_home_01_entry"
		(lin as Dictionary)["position"] = Vector2(-24, 328)
		(lin as Dictionary)["currentAction"] = {}
	var xie_pos: Vector2 = (residents[UNDERCOVER_ID] as Dictionary)["position"]
	var lin_pos: Vector2 = (residents[TARGET_ID] as Dictionary)["position"]
	print("  谢眠(%s) 林岚(%s) 距离: %.0fpx (室内放行)" % [
		str(xie_pos), str(lin_pos), xie_pos.distance_to(lin_pos),
	])
	var undercover := residents[UNDERCOVER_ID] as Dictionary
	var options: Array = []
	var decorated: Array = world.call(
		"_decorate_conflict_tension_options",
		UNDERCOVER_ID,
		undercover,
		options,
	) as Array
	print("  注入选项数: %d" % decorated.size())
	var has_assassinate := false
	var has_attack := false
	for v in decorated:
		var o := v as Dictionary
		var kind := String(o.get("kind", ""))
		var tname := String(o.get("target_resident_name", ""))
		print("    kind=%s target=%s" % [kind, tname])
		if kind == "assassinate":
			has_assassinate = true
		if kind == "attack":
			has_attack = true
	_expect_equal(has_assassinate, true, "卧底同屋目标时注入 assassinate 选项")
	_expect_equal(has_attack, true, "卧底同屋目标时注入 attack 选项")
	world.call("stop")
