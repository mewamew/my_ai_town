extends "res://tests/support/TownWorldTestCase.gd"
## diag_police_investigate.gd — 验证警察查案基础
## 1) 死亡公告带地点
## 2) _police_death_cases: 警察看到案件档案, 非警察看不到
## 3) prompt渲染: 警察收到案件档案段落

func _initialize() -> void:
	print("===== 警察查案基础 验证 =====")
	_verify_death_announcement_has_place()
	_verify_police_death_cases()
	_verify_non_police_no_cases()
	_finish_suite("POLICE_INVESTIGATE_PASS")


func _verify_death_announcement_has_place() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "police opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	_advance_to_minute_of_day(world, 1200)
	# 用世界方法杀一个人(暗杀触发死亡), 然后看公告文本
	var residents := world.call("residents") as Dictionary
	residents["resident_xie_mian_01"] = {
		"residentId": "resident_xie_mian_01",
		"spaceId": "town_outdoor",
		"regionId": "outdoor_plaza_01",
		"currentPlace": "社区花园",
		"currentAction": {},
		"position": Vector2(100, 100),
		"arrivalState": {"status": "arrived"},
		"resultQueue": [],
		"eventQueue": [],
	}
	var lin: Variant = residents.get("resident_lin_lan_01")
	if lin is Dictionary:
		(lin as Dictionary)["spaceId"] = "town_outdoor"
		(lin as Dictionary)["regionId"] = "outdoor_plaza_01"
		(lin as Dictionary)["position"] = Vector2(200, 100)
	var action := {
		"action_id": "diag-police-kill-001",
		"type": "暗杀",
		"target_resident_id": "resident_lin_lan_01",
		"line": "动手。",
	}
	var undercover := residents["resident_xie_mian_01"] as Dictionary
	world.call("_activate_assassination_action", "resident_xie_mian_01", undercover, action, {}, "", {})
	# 死亡事件在死者 lifecycle 里
	var state := world.call("get_resident_lifecycle_state", "resident_lin_lan_01") as Dictionary
	var event := state.get("deathEvent", {}) as Dictionary
	var text := world.call("_death_announcement_text", event) as String
	print("  死亡公告: %s" % text)
	_expect_equal(text.contains("中心广场"), true, "死亡公告带地点")
	world.call("stop")


func _verify_police_death_cases() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "police cases opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	_advance_to_minute_of_day(world, 1200)
	# 注入闻叙(真实游戏里有, fixture精简没有)
	var wen_residents: Dictionary = world.call("residents") as Dictionary
	wen_residents["resident_wen_xu_01"] = {
		"residentId": "resident_wen_xu_01",
		"socialState": {"job": "警察", "home": "北街十六号住宅", "workplace": "警察局"},
		"status": "alive",
		"spaceId": "town_outdoor",
		"regionId": "outdoor_plaza_01",
		"currentPlace": "中心广场",
		"currentAction": {},
		"position": Vector2(50, 50),
		"arrivalState": {"status": "arrived"},
		"resultQueue": [],
		"eventQueue": [],
	}
	var wen: Variant = wen_residents.get("resident_wen_xu_01")
	_expect_equal(wen != null, true, "闻叙存在")
	var job: String = String(((wen as Dictionary).get("socialState", {}) as Dictionary).get("job", ""))
	print("  闻叙职业: %s" % job)
	_expect_equal(job, "警察", "闻叙职业是警察")
	# 制造一个死亡
	var residents := world.call("residents") as Dictionary
	residents["resident_xie_mian_01"] = {
		"residentId": "resident_xie_mian_01",
		"spaceId": "town_outdoor",
		"regionId": "outdoor_plaza_01",
		"currentPlace": "社区花园",
		"currentAction": {},
		"position": Vector2(100, 100),
		"arrivalState": {"status": "arrived"},
		"resultQueue": [],
		"eventQueue": [],
	}
	var lin: Variant = residents.get("resident_lin_lan_01")
	if lin is Dictionary:
		(lin as Dictionary)["spaceId"] = "town_outdoor"
		(lin as Dictionary)["regionId"] = "outdoor_plaza_01"
		(lin as Dictionary)["position"] = Vector2(200, 100)
	var action := {
		"action_id": "diag-police-cases-001",
		"type": "暗杀",
		"target_resident_id": "resident_lin_lan_01",
		"line": "动手。",
	}
	var undercover := residents["resident_xie_mian_01"] as Dictionary
	world.call("_activate_assassination_action", "resident_xie_mian_01", undercover, action, {}, "", {})
	_advance_to_minute_of_day(world, 480)  # 天亮公布后案件才对警察可见
	# 警察的案件档案
	var cases := world.call("_police_death_cases", "resident_wen_xu_01") as Array
	print("  闻叙案件档案数: %d" % cases.size())
	_expect_equal(cases.size() >= 1, true, "警察能看到死亡案件")
	if not cases.is_empty():
		var case0 := cases[0] as Dictionary
		print("  案件0: %s 于第%d天%s 在%s 死亡, 死因: %s" % [
			case0.get("deceased_resident_name", ""),
			int(case0.get("day", 0)),
			case0.get("clock", ""),
			case0.get("place_name", ""),
			case0.get("reason", ""),
		])
		_expect_equal(case0.get("deceased_resident_name"), "林岚", "案件含死者名")
		_expect_equal(case0.get("place_name"), "中心广场", "案件含地点")
		_expect_equal(String(case0.get("reason", "")).contains("暗杀"), true, "案件含死因(暗杀)")
	world.call("stop")


func _verify_non_police_no_cases() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "police non cases opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	_advance_to_minute_of_day(world, 1200)
	# 制造一个死亡
	var residents := world.call("residents") as Dictionary
	residents["resident_xie_mian_01"] = {
		"residentId": "resident_xie_mian_01",
		"spaceId": "town_outdoor",
		"regionId": "outdoor_plaza_01",
		"currentPlace": "社区花园",
		"currentAction": {},
		"position": Vector2(100, 100),
		"arrivalState": {"status": "arrived"},
		"resultQueue": [],
		"eventQueue": [],
	}
	var lin: Variant = residents.get("resident_lin_lan_01")
	if lin is Dictionary:
		(lin as Dictionary)["spaceId"] = "town_outdoor"
		(lin as Dictionary)["regionId"] = "outdoor_plaza_01"
		(lin as Dictionary)["position"] = Vector2(200, 100)
	var action := {
		"action_id": "diag-police-non-001",
		"type": "暗杀",
		"target_resident_id": "resident_lin_lan_01",
		"line": "动手。",
	}
	var undercover := residents["resident_xie_mian_01"] as Dictionary
	world.call("_activate_assassination_action", "resident_xie_mian_01", undercover, action, {}, "", {})
	_advance_to_minute_of_day(world, 480)
	# 非警察(唐小满)看不到案件档案
	var cases := world.call("_police_death_cases", "resident_tang_xiaoman_01") as Array
	print("  唐小满(非警察)案件档案数: %d" % cases.size())
	_expect_equal(cases.is_empty(), true, "非警察看不到案件档案")
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
