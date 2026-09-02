extends "res://tests/support/TownWorldTestCase.gd"
## diag_police_patrol.gd — 巡逻威慑机制验证(警察夜间巡逻防暗杀):
## 1) 目标感知范围内有清醒警察 → 卧底暗杀选项不注入(_decorate)
## 2) 同上 → _prepare_assassination_action 执行拒绝("附近有警察")
## 3) 警察不在场(移到不同 space) → 暗杀选项重新出现且准备通过
## 4) 警察睡着了 → 威慑不生效(睡觉的警察不算), 可暗杀
## 运行: Godot --headless --path game --script res://tests/diag_police_patrol.gd

const WEREWOLF := preload("res://world/runtime/TownWerewolfRuntime.gd")
const POLICE_ID := "resident_wen_xu_01"
const UNDERCOVER_ID := "resident_xie_mian_01"
const TARGET_ID := "resident_lin_lan_01"

const SPACE := "town_outdoor"
const REGION := "outdoor_plaza_01"


func _initialize() -> void:
	print("===== 巡逻威慑(警察在场防暗杀) 验证 =====")
	_verify_police_patrol()
	_finish_suite("POLICE_PATROL_PASS")


func _verify_police_patrol() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "police patrol opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_inject_role_resident(world, UNDERCOVER_ID, "谢眠", "乐师")
	_inject_role_resident(world, POLICE_ID, "闻叙", "警察")
	var residents: Dictionary = world.call("residents")
	_advance_to_minute_of_day(world, 1200)  # 夜间 20:00
	# 夜间复位: 卧底/目标/警察 全在户外同区域, 互相在感知范围内
	_place(residents, UNDERCOVER_ID, Vector2(100, 100))
	_place(residents, TARGET_ID, Vector2(120, 100))
	_place(residents, POLICE_ID, Vector2(110, 100))
	var undercover := residents[UNDERCOVER_ID] as Dictionary
	var target := residents[TARGET_ID] as Dictionary
	var police := residents[POLICE_ID] as Dictionary

	# 1) 警察在目标身边(清醒) → 卧底暗杀选项不注入
	var decorated: Array = world.call(
		"_decorate_conflict_tension_options",
		UNDERCOVER_ID,
		undercover,
		[],
	) as Array
	var has_assassinate := false
	for option_value: Variant in decorated:
		if not option_value is Dictionary:
			continue
		if String((option_value as Dictionary).get("kind", "")) == "assassinate":
			has_assassinate = true
			break
	_expect_equal(
		has_assassinate,
		false,
		"目标身边有清醒警察 → 暗杀选项不注入 (共%d个选项)" % decorated.size(),
	)
	# 2) 执行侧同样拒绝
	var action := {
		"action_id": "patrol-0",
		"type": "暗杀",
		"target_resident_id": TARGET_ID,
		"line": "动手。",
	}
	var prepared := world.call(
		"_prepare_assassination_action",
		UNDERCOVER_ID,
		undercover,
		action,
	) as Dictionary
	_expect_equal(bool(prepared.get("ok", false)), false, "警察在场暗杀准备被拒")
	var errors := prepared.get("errors", []) as Array
	_expect(
		not errors.is_empty() and String(errors[0]).contains("警察"),
		"拒绝文案提及警察在场",
	)
	# 3) 警察离开(移到不同 space) → 暗杀恢复
	_move_police_away(residents)
	var decorated2: Array = world.call(
		"_decorate_conflict_tension_options",
		UNDERCOVER_ID,
		undercover,
		[],
	) as Array
	var has_assassinate2 := false
	for option_value: Variant in decorated2:
		if not option_value is Dictionary:
			continue
		if String((option_value as Dictionary).get("kind", "")) == "assassinate":
			has_assassinate2 = true
			break
	_expect_equal(
		has_assassinate2,
		true,
		"警察离开后暗杀选项恢复 (共%d个选项)" % decorated2.size(),
	)
	var prepared2 := world.call(
		"_prepare_assassination_action",
		UNDERCOVER_ID,
		undercover,
		action,
	) as Dictionary
	_expect_equal(bool(prepared2.get("ok", false)), true, "警察离开后暗杀准备通过")
	# 4) 警察回来但睡着了 → 威慑不生效
	_place(residents, POLICE_ID, Vector2(110, 100))
	police = residents[POLICE_ID] as Dictionary
	police["currentAction"] = {"type": "用道具", "verb": "睡觉", "prop": "床"}
	var decorated3: Array = world.call(
		"_decorate_conflict_tension_options",
		UNDERCOVER_ID,
		undercover,
		[],
	) as Array
	var has_assassinate3 := false
	for option_value: Variant in decorated3:
		if not option_value is Dictionary:
			continue
		if String((option_value as Dictionary).get("kind", "")) == "assassinate":
			has_assassinate3 = true
			break
	_expect_equal(
		has_assassinate3,
		true,
		"警察睡着(不算清醒) → 暗杀选项恢复",
	)
	world.call("stop")


## 把警察移到远处(镇公所室内, 与目标不同 space)
func _move_police_away(residents: Dictionary) -> void:
	var police_res: Variant = residents.get(POLICE_ID, {})
	if police_res is Dictionary:
		(police_res as Dictionary)["spaceId"] = "indoor_town_hall"
		(police_res as Dictionary)["regionId"] = "region_portal_town_hall_entry"
		(police_res as Dictionary)["currentPlace"] = "镇公所"
		(police_res as Dictionary)["currentAction"] = {}


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


func _advance_to_minute_of_day(world: RefCounted, target_minute: int) -> void:
	var env: Object = world.get("_environment")
	var current := int(env.call("get_absolute_minute"))
	var minute_of_day := posmod(current, 1440)
	var delta := target_minute - minute_of_day
	if delta <= 0:
		delta += 1440
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
