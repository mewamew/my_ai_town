extends "res://tests/support/TownWorldTestCase.gd"
## diag_police_alert.gd — 警察警觉护盾 + 警察死亡强线索验证:
## 1) 警察每局 1 次警觉免死: 夜间暗杀警察被挡下, 不死亡, 护盾次数归零
## 2) 挡下同样消耗全队当晚配额(不能换目标继续杀)
## 3) 护盾耗尽后第二天夜再暗杀警察 → 正常死亡
## 4) 暗杀普通居民不触发护盾(直接死亡)
## 运行: Godot --headless --path game --script res://tests/diag_police_alert.gd

const WEREWOLF := preload("res://world/runtime/TownWerewolfRuntime.gd")
const UNDERCOVER_ID := "resident_xie_mian_01"
const POLICE_ID := "resident_wen_xu_01"
const CIVILIAN_ID := "resident_lin_lan_01"

const SPACE := "town_outdoor"
const REGION := "outdoor_plaza_01"


func _initialize() -> void:
	print("===== 警察警觉护盾 验证 =====")
	_verify_police_alert()
	_finish_suite("POLICE_ALERT_PASS")


func _verify_police_alert() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "police alert opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_advance_to_minute_of_day(world, 1200)  # 第1天 20:00 夜间
	_inject_role_resident(world, UNDERCOVER_ID, "谢眠", "乐师")
	_inject_role_resident(world, POLICE_ID, "闻叙", "警察")
	var residents: Dictionary = world.call("residents")
	_place(residents, UNDERCOVER_ID, Vector2(100, 100))
	_place(residents, POLICE_ID, Vector2(120, 100))
	_place(residents, CIVILIAN_ID, Vector2(300, 100))
	var xie := residents[UNDERCOVER_ID] as Dictionary
	# 初始护盾 1 次
	_expect_equal(
		WEREWOLF.police_alert_charges(world),
		1,
		"初始警察警觉护盾 1 次",
	)
	# 1) 夜间暗杀警察 → 被护盾挡下, 不死亡
	world.call(
		"_activate_assassination_action",
		UNDERCOVER_ID,
		xie,
		{
			"action_id": "alert-test-1",
			"target_resident_id": POLICE_ID,
			"line": "夜深了，我去串个门",
		},
		{},
		"",
		{},
	)
	_expect_equal(
		world.call("_resident_is_alive", POLICE_ID),
		true,
		"护盾挡下: 警察没有死亡",
	)
	_expect_equal(
		WEREWOLF.police_alert_charges(world),
		0,
		"护盾消耗后归零",
	)
	# 2) 当晚配额已消耗(同医生守诊)
	var kill_night := WEREWOLF.night_index(
		int((world.get("_environment") as Object).call("get_absolute_minute")),
	)
	_expect_equal(
		world.get("_werewolf_state").get("undercoverKillLastNight"),
		kill_night,
		"挡下后全队当晚配额已消耗",
	)
	# 3) 换普通居民目标也杀不了(配额已用)
	world.call(
		"_activate_assassination_action",
		UNDERCOVER_ID,
		xie,
		{
			"action_id": "alert-test-2",
			"target_resident_id": CIVILIAN_ID,
			"line": "换个目标",
		},
		{},
		"",
		{},
	)
	_expect_equal(
		world.call("_resident_is_alive", CIVILIAN_ID),
		true,
		"当晚配额已用, 普通居民也没被杀",
	)
	# 4) 第二天夜: 护盾已耗尽, 暗杀警察成功
	_advance_to_minute_of_day(world, 1200)  # 推进到第2天 20:00
	world.call(
		"_activate_assassination_action",
		UNDERCOVER_ID,
		residents[UNDERCOVER_ID] as Dictionary,
		{
			"action_id": "alert-test-3",
			"target_resident_id": POLICE_ID,
			"line": "这次没人保护你了",
		},
		{},
		"",
		{},
	)
	_expect_equal(
		world.call("_resident_is_alive", POLICE_ID),
		false,
		"护盾耗尽后暗杀警察成功",
	)
	# 5) 第三次夜间(第3天): 普通居民无护盾, 直接被杀
	_advance_to_minute_of_day(world, 1200)
	world.call(
		"_activate_assassination_action",
		UNDERCOVER_ID,
		residents[UNDERCOVER_ID] as Dictionary,
		{
			"action_id": "alert-test-4",
			"target_resident_id": CIVILIAN_ID,
			"line": "普通居民没有护盾",
		},
		{},
		"",
		{},
	)
	_expect_equal(
		world.call("_resident_is_alive", CIVILIAN_ID),
		false,
		"普通居民无护盾直接死亡",
	)
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


## 注入测试用角色(范式同 diag_role_skills.gd)
func _inject_role_resident(
	world: RefCounted,
	resident_id: String,
	resident_name: String,
	job: String,
) -> void:
	var residents: Dictionary = world.call("residents")
	if residents.has(resident_id):
		return
	var source := residents.get(CIVILIAN_ID, {}) as Dictionary
	var home_anchor: Dictionary = {}
	if not source.is_empty():
		var lifecycle: Object = world.get("_resident_lifecycle")
		var source_state: Dictionary = lifecycle.call(
			"get_resident_state",
			CIVILIAN_ID,
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


func _advance_to_minute_of_day(world: RefCounted, target_minute: int) -> void:
	var env: Object = world.get("_environment")
	var current := int(env.call("get_absolute_minute"))
	var minute_of_day := posmod(current, 1440)
	var delta := target_minute - minute_of_day
	if delta <= 0:
		delta += 1440
	var result := world.call("advance", float(delta)) as Dictionary
	_expect_equal(result.get("ok"), true, "advance %d 分钟 ok" % delta)
