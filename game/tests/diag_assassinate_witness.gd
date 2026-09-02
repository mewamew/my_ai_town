extends "res://tests/support/TownWorldTestCase.gd"
## diag_assassinate_witness.gd — 验证隐蔽性检查(目击者判定)
## 场景A: 无人目击 → 卧底反馈"无人察觉"
## 场景B: 有清醒目击者同屋 → 目击者收到"目睹暗杀"事件, 卧底反馈"被看见"
## 场景C: 只有睡觉者 → 睡觉者不算目击者

const UNDERCOVER_ID := "resident_xie_mian_01"
const TARGET_ID := "resident_lin_lan_01"
const WITNESS_ID := "resident_tang_xiaoman_01"

func _initialize() -> void:
	print("===== 隐蔽性检查 验证 =====")
	_verify_no_witness()
	_verify_with_witness()
	_verify_sleeping_not_witness()
	_finish_suite("ASSASSINATE_WITNESS_PASS")


func _setup_world(space: String, region: String) -> RefCounted:
	var data := _build_data()
	var opening := _garden_opening(data, "witness opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	_advance_to_minute_of_day(world, 1200)
	var residents := world.call("residents") as Dictionary
	residents[UNDERCOVER_ID] = {
		"residentId": UNDERCOVER_ID,
		"spaceId": space,
		"regionId": region,
		"currentPlace": "测试地点",
		"currentAction": {},
		"position": Vector2(16, 464),
		"arrivalState": {"status": "arrived"},
		"resultQueue": [],
		"eventQueue": [],
	}
	var lin: Variant = residents.get(TARGET_ID)
	if lin is Dictionary:
		(lin as Dictionary)["spaceId"] = space
		(lin as Dictionary)["regionId"] = region
		(lin as Dictionary)["position"] = Vector2(-168, -136)
	return world


func _run_assassinate(world: RefCounted) -> Array:
	var action := {
		"action_id": "diag-witness-%s" % str(Time.get_ticks_usec()),
		"type": "暗杀",
		"target_resident_id": TARGET_ID,
		"line": "动手。",
	}
	var residents := world.call("residents") as Dictionary
	var resident := residents[UNDERCOVER_ID] as Dictionary
	world.call("_activate_assassination_action", UNDERCOVER_ID, resident, action, {}, "", {})
	return resident.get("resultQueue", []) as Array


func _last_reason(results: Array) -> String:
	var reason := ""
	for r in results:
		if String((r as Dictionary).get("action_id", "")).begins_with("diag-witness-"):
			reason = String((r as Dictionary).get("reason", ""))
	return reason


func _verify_no_witness() -> void:
	var world := _setup_world("home_01", "region_portal_home_01_entry")
	var results := _run_assassinate(world)
	var reason := _last_reason(results)
	print("  场景A 反馈: %s" % reason)
	_expect_equal(reason.contains("无人察觉"), true, "无人目击 → 反馈含无人察觉")
	world.call("stop")


func _verify_with_witness() -> void:
	var world := _setup_world("home_01", "region_portal_home_01_entry")
	var residents := world.call("residents") as Dictionary
	var tang: Variant = residents.get(WITNESS_ID)
	if tang is Dictionary:
		(tang as Dictionary)["spaceId"] = "home_01"
		(tang as Dictionary)["regionId"] = "region_portal_home_01_entry"
		(tang as Dictionary)["position"] = Vector2(100, 100)
		(tang as Dictionary)["currentAction"] = {}
	var results := _run_assassinate(world)
	var reason := _last_reason(results)
	print("  场景B 反馈: %s" % reason)
	_expect_equal(reason.contains("看见"), true, "有目击者 → 反馈含看见")
	var tang_events := (residents[WITNESS_ID] as Dictionary).get("eventQueue", []) as Array
	var witnessed := false
	for e in tang_events:
		if String((e as Dictionary).get("type", "")) == "目睹暗杀":
			witnessed = true
			print("  目击事件: %s" % String((e as Dictionary).get("summary", "")))
			_expect_equal(String((e as Dictionary).get("attacker_resident_id", "")), UNDERCOVER_ID, "目击事件带凶手id")
			_expect_equal(String((e as Dictionary).get("victim_resident_id", "")), TARGET_ID, "目击事件带死者id")
	_expect_equal(witnessed, true, "目击者收到目睹暗杀事件")
	world.call("stop")


func _verify_sleeping_not_witness() -> void:
	var world := _setup_world("home_01", "region_portal_home_01_entry")
	var residents := world.call("residents") as Dictionary
	var tang: Variant = residents.get(WITNESS_ID)
	if tang is Dictionary:
		(tang as Dictionary)["spaceId"] = "home_01"
		(tang as Dictionary)["regionId"] = "region_portal_home_01_entry"
		(tang as Dictionary)["position"] = Vector2(100, 100)
		(tang as Dictionary)["currentAction"] = {
			"type": "用道具", "verb": "睡觉", "action_id": "sleep-w", "prop": "床", "line": "睡觉",
		}
	var results := _run_assassinate(world)
	var reason := _last_reason(results)
	print("  场景C 反馈: %s" % reason)
	_expect_equal(reason.contains("无人察觉"), true, "只有睡觉者 → 反馈无人察觉")
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
