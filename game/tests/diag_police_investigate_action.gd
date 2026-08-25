extends "res://tests/support/TownWorldTestCase.gd"
## diag_police_investigate_action.gd — 警察镇公所「查案」动作验证:
## 1) 非警察被拒 / 不在镇公所被拒 / 空 line 被拒
## 2) 白天在镇公所查案成功, 线索含案件档案文案(无案件时给出提示)
## 3) 夜间查案: 线索含"深夜还在外面游荡"行踪疑点(把林岚移到户外清醒)
## 4) 每天限 2 次: 同天第 3 次被拒
## 5) 跨天自动重置: 第 2 天再查成功
## 运行: Godot --headless --path game --script res://tests/diag_police_investigate_action.gd

const POLICE_ID := "resident_wen_xu_01"
const TARGET_ID := "resident_lin_lan_01"

const SPACE := "town_outdoor"
const REGION := "outdoor_plaza_01"


func _initialize() -> void:
	print("===== 警察镇公所查案动作 验证 =====")
	_verify_police_investigate_action()
	_finish_suite("POLICE_INVESTIGATE_ACTION_PASS")


func _verify_police_investigate_action() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "police investigate action opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_inject_role_resident(world, POLICE_ID, "闻叙", "警察")
	var residents: Dictionary = world.call("residents")
	_place(residents, POLICE_ID, Vector2(100, 100))
	_place(residents, TARGET_ID, Vector2(200, 100))

	var police := residents[POLICE_ID] as Dictionary
	var lin := residents[TARGET_ID] as Dictionary
	var start_minute := _minute(world)
	var day_index := start_minute / 1440

	# 1) 非警察查案被拒
	var not_police := world.call(
		"_activate_police_investigate_action",
		TARGET_ID,
		lin,
		{"action_id": "inv-0", "type": "查案", "line": "测试"},
	) as Dictionary
	_expect_equal(
		bool(not_police.get("ok", false)),
		false,
		"非警察查案被拒",
	)
	# 2) 警察不在镇公所(中心广场)查案被拒
	var outside := world.call(
		"_activate_police_investigate_action",
		POLICE_ID,
		police,
		{"action_id": "inv-1", "type": "查案", "line": "想查档案"},
	) as Dictionary
	_expect_equal(
		bool(outside.get("ok", false)),
		false,
		"不在镇公所查案被拒",
	)
	var outside_errors := outside.get("errors", []) as Array
	_expect(
		not outside_errors.is_empty()
			and String(outside_errors[0]).contains("镇公所"),
		"错误文案提示回镇公所",
	)
	# 3) 警察在镇公所但空 line 被拒
	_set_town_hall(residents, POLICE_ID)
	police = residents[POLICE_ID] as Dictionary
	var empty_line := world.call(
		"_activate_police_investigate_action",
		POLICE_ID,
		police,
		{"action_id": "inv-2", "type": "查案", "line": ""},
	) as Dictionary
	_expect_equal(
		bool(empty_line.get("ok", false)),
		false,
		"空 line 查案被拒",
	)
	# 4) 白天第一次查案成功(无死亡案件 → 提示文案)
	var first := world.call(
		"_activate_police_investigate_action",
		POLICE_ID,
		police,
		{"action_id": "inv-3", "type": "查案", "line": "把档案调出来"},
	) as Dictionary
	_expect_equal(bool(first.get("ok", false)), true, "白天查案成功")
	var first_summary := String(first.get("summary", ""))
	_expect(
		first_summary.contains("镇公所档案"),
		"查案线索以镇公所档案开头",
	)
	_expect(
		first_summary.contains("暂时没有新的死亡案件"),
		"无案件时给出档案提示",
	)
	# 5) 夜间查案(推进到当天 20:00): 林岚移到户外清醒 → 行踪疑点
	_place(residents, TARGET_ID, Vector2(200, 100))  # 夜间前复位林岚(户外清醒)
	var night_minute := day_index * 1440 + 1200
	var delta_night := night_minute - _minute(world)
	if delta_night > 0:
		_advance_minutes(world, delta_night)
	_place(residents, TARGET_ID, Vector2(200, 100))  # advance 后拉回户外
	var second := world.call(
		"_activate_police_investigate_action",
		POLICE_ID,
		police,
		{"action_id": "inv-4", "type": "查案", "line": "夜里再查一次"},
	) as Dictionary
	_expect_equal(bool(second.get("ok", false)), true, "夜间查案成功")
	var second_summary := String(second.get("summary", ""))
	_expect(
		second_summary.contains("深夜还在外面游荡")
			or second_summary.contains("深夜不在自己家"),
		"夜间查案给出行踪疑点",
	)
	# 6) 同天第 3 次被拒(每天限 2 次)
	var third := world.call(
		"_activate_police_investigate_action",
		POLICE_ID,
		police,
		{"action_id": "inv-5", "type": "查案", "line": "还想查"},
	) as Dictionary
	_expect_equal(
		bool(third.get("ok", false)),
		false,
		"同天第 3 次查案被拒(每天限 2 次)",
	)
	# 7) 跨天自动重置: 第 2 天再查成功
	var next_day_minute := (day_index + 1) * 1440 + 480
	var delta_next := next_day_minute - _minute(world)
	if delta_next > 0:
		_advance_minutes(world, delta_next)
	var reset := world.call(
		"_activate_police_investigate_action",
		POLICE_ID,
		police,
		{"action_id": "inv-6", "type": "查案", "line": "第二天再查"},
	) as Dictionary
	_expect_equal(bool(reset.get("ok", false)), true, "跨天重置后查案成功")
	world.call("stop")


## 把居民移到指定户外位置
func _place(residents: Dictionary, resident_id: String, pos: Vector2) -> void:
	var r: Variant = residents.get(resident_id)
	if not r is Dictionary:
		_expect(false, "%s 存在" % resident_id)
		return
	(r as Dictionary)["spaceId"] = SPACE
	(r as Dictionary)["regionId"] = REGION
	(r as Dictionary)["currentPlace"] = "中心广场"
	(r as Dictionary)["position"] = pos
	(r as Dictionary)["currentAction"] = {}


## 把居民放进镇公所(currentPlace 判定)
func _set_town_hall(residents: Dictionary, resident_id: String) -> void:
	var r: Variant = residents.get(resident_id)
	if not r is Dictionary:
		_expect(false, "%s 存在" % resident_id)
		return
	(r as Dictionary)["currentPlace"] = "镇公所"


func _minute(world: RefCounted) -> int:
	var env: Object = world.get("_environment")
	return int(env.call("get_absolute_minute"))


func _advance_minutes(world: RefCounted, delta: int) -> void:
	var result := world.call("advance", float(delta)) as Dictionary
	_expect_equal(result.get("ok"), true, "advance %d 分钟 ok" % delta)


## 注入测试用角色(范式同 diag_police_intel.gd)
func _inject_role_resident(
	world: RefCounted,
	resident_id: String,
	resident_name: String,
	job: String,
) -> void:
	var residents: Dictionary = world.call("residents")
	if residents.has(resident_id):
		return
	var source := residents.get(TARGET_ID, {}) as Dictionary
	var home_anchor: Dictionary = {}
	if not source.is_empty():
		var lifecycle: Object = world.get("_resident_lifecycle")
		var source_state: Dictionary = lifecycle.call(
			"get_resident_state",
			TARGET_ID,
		)
		home_anchor = (
			source_state.get("homeAnchor", {}) as Dictionary
		).duplicate(true)
	var resident := {
		"residentId": resident_id,
		"attributes": {
			"name": resident_name,
			"gender": "男",
			"age": 30,
			"desire": "测试用",
			"personality": "测试用",
			"speech": "测试用",
			"interests": [],
			"customInterests": [],
		},
		"profileAttributes": {"name": resident_name},
		"socialState": {
			"job": job,
			"home": "诊所",
			"workplace": "诊所",
			"money": 40,
			"reputation": 40,
		},
		"arrivalState": {"status": "arrived"},
		"currentAction": {},
		"doing": "在镇上",
		"body": {"困": "不困", "饿": "不饿", "累": "不累"},
	}
	if not source.is_empty():
		resident["spaceId"] = source.get("spaceId", "town_outdoor")
		resident["regionId"] = source.get("regionId", "")
		resident["currentPlace"] = source.get("currentPlace", "")
		resident["position"] = source.get("position", Vector2.ZERO)
		resident["nearby"] = (source.get("nearby", []) as Array).duplicate()
	residents[resident_id] = resident
	var lifecycle: Object = world.get("_resident_lifecycle")
	var initialized := lifecycle.call(
		"initialize_resident",
		resident_id,
		resident_name,
		home_anchor,
	) as Dictionary
	_expect_equal(initialized.get("ok"), true, "%s 注入生命周期" % resident_name)
	var order: Array = world.resident_order()
	if not order.has(resident_id):
		order.append(resident_id)
