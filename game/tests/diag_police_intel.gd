extends "res://tests/support/TownWorldTestCase.gd"
## diag_police_intel.gd — 警察侦查装备（窃听器/定位器）持续监听验证:
## 1) 安装必须靠近目标(感知范围内, 同暗杀判定): 距离太远被拒
## 2) 靠近后安装成功, 扣次数, 装置状态写入 werewolfState
## 3) 窃听钩子: 被监听目标参与的对话(turn)实时上报, 未监听目标不报
## 4) 定位钩子: 被监听目标"去"动作准备时上报目的地
## 5) 监听 1 天后过期, 钩子不再上报; 装新目标覆盖旧的; 次数用完拒绝
## 运行: Godot --headless --path game --script res://tests/diag_police_intel.gd

const WEREWOLF := preload("res://world/runtime/TownWerewolfRuntime.gd")
const POLICE_ID := "resident_wen_xu_01"
const TARGET_ID := "resident_lin_lan_01"
const PARTNER_ID := "resident_tang_xiaoman_01"

const SPACE := "town_outdoor"
const REGION := "outdoor_plaza_01"


func _initialize() -> void:
	print("===== 警察侦查装备(窃听器/定位器)持续监听 验证 =====")
	_verify_police_intel()
	_finish_suite("POLICE_INTEL_PASS")


func _verify_police_intel() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "police intel opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_inject_role_resident(world, POLICE_ID, "闻叙", "警察")
	var residents: Dictionary = world.call("residents")
	_place(residents, POLICE_ID, Vector2(100, 100))
	_place(residents, TARGET_ID, Vector2(1000, 100))  # 远离警察
	_place(residents, PARTNER_ID, Vector2(200, 100))

	var police := residents[POLICE_ID] as Dictionary
	var lin := residents[TARGET_ID] as Dictionary
	var tang := residents[PARTNER_ID] as Dictionary

	# 1) 距离太远(900 > 感知范围320) → 安装被拒
	var far := world.call(
		"_activate_police_eavesdrop_action",
		POLICE_ID,
		police,
		{"action_id": "intel-0", "target_resident_id": TARGET_ID, "line": "太远了够不着"},
	) as Dictionary
	_expect_equal(
		bool(far.get("ok", false)),
		false,
		"距离太远安装窃听器被拒",
	)
	# 非警察/空目标/自己 仍被拒
	var rejected := world.call(
		"_activate_police_eavesdrop_action",
		TARGET_ID,
		lin,
		{"action_id": "intel-1", "target_resident_id": POLICE_ID, "line": "测试"},
	) as Dictionary
	_expect_equal(
		bool(rejected.get("ok", false)),
		false,
		"非警察使用窃听器被拒",
	)
	var empty_target := world.call(
		"_activate_police_eavesdrop_action",
		POLICE_ID,
		police,
		{"action_id": "intel-2", "target_resident_id": "", "line": "测试"},
	) as Dictionary
	_expect_equal(
		bool(empty_target.get("ok", false)),
		false,
		"窃听目标为空被拒",
	)
	# 2) 拉近林岚 → 安装成功, 扣次, 装置状态写入
	_place(residents, TARGET_ID, Vector2(120, 100))  # 距离 20
	var install := world.call(
		"_activate_police_eavesdrop_action",
		POLICE_ID,
		police,
		{"action_id": "intel-3", "target_resident_id": TARGET_ID, "line": "让我悄悄给你装上"},
	) as Dictionary
	_expect_equal(
		bool(install.get("ok", false)),
		true,
		"靠近后窃听器安装成功",
	)
	var devices: Dictionary = world.get("_werewolf_state").get("policeDevices", {})
	_expect_equal(
		String(devices.get("eavesdrop", {}).get("targetId", "")),
		TARGET_ID,
		"窃听装置目标为林岚",
	)
	_expect_equal(
		int(world.get("_werewolf_state").get("roleSkills", {}).get("police", {}).get("eavesdropCharges", -1)),
		1,
		"窃听后余量 1",
	)
	# 3) 窃听钩子: 林岚(被监听)参与对话 → 上报; 唐小满(未监听) → 不上报
	var env: Object = world.get("_environment")
	var minute := int(env.call("get_absolute_minute"))
	var hit := world.call(
		"_record_police_eavesdrop_turn",
		"林岚", "唐小满", "我看到有人深夜在镇公所附近徘徊", "中心广场",
	) as bool
	_expect_equal(hit, true, "被监听目标的对话被实时上报")
	var miss := world.call(
		"_record_police_eavesdrop_turn",
		"唐小满", "林岚", "昨晚你看到什么了吗", "中心广场",
	) as bool
	_expect_equal(miss, false, "未监听目标的对话不上报")
	# 4) 定位器: 靠近唐小满安装, 位置钩子上报目的地
	_place(residents, PARTNER_ID, Vector2(200, 100))  # 距离 100
	var tracker_install := world.call(
		"_activate_police_tracker_action",
		POLICE_ID,
		police,
		{"action_id": "intel-4", "target_resident_id": PARTNER_ID, "line": "看看你之后要去哪"},
	) as Dictionary
	_expect_equal(
		bool(tracker_install.get("ok", false)),
		true,
		"定位器安装成功",
	)
	var devices2: Dictionary = world.get("_werewolf_state").get("policeDevices", {})
	_expect_equal(
		String(devices2.get("tracker", {}).get("targetId", "")),
		PARTNER_ID,
		"定位装置目标为唐小满",
	)
	_expect_equal(
		int(world.get("_werewolf_state").get("roleSkills", {}).get("police", {}).get("trackerCharges", -1)),
		2,
		"定位后余量 2",
	)
	var visit := world.call(
		"_record_police_tracker_visit",
		PARTNER_ID, "镇公所", minute,
	) as bool
	_expect_equal(visit, true, "被监听目标的目的地被上报")
	var visit_miss := world.call(
		"_record_police_tracker_visit",
		TARGET_ID, "镇公所", minute,
	) as bool
	_expect_equal(visit_miss, false, "未被定位监听的目标不上报")
	# 5) 监听 1 天后过期 → 钩子不再上报
	_advance_minutes(world, 1441)
	env = world.get("_environment")
	minute = int(env.call("get_absolute_minute"))
	var expired := world.call(
		"_record_police_eavesdrop_turn",
		"林岚", "唐小满", "过期后的话", "中心广场",
	) as bool
	_expect_equal(expired, false, "监听 1 天后过期, 窃听不再上报")
	var expired_visit := world.call(
		"_record_police_tracker_visit",
		PARTNER_ID, "镇公所", minute,
	) as bool
	_expect_equal(expired_visit, false, "监听 1 天后过期, 定位不再上报")
	# 6) 装新目标覆盖旧的
	_place(residents, TARGET_ID, Vector2(110, 100))  # 靠近警察
	world.call(
		"_activate_police_tracker_action",
		POLICE_ID,
		police,
		{"action_id": "intel-5", "target_resident_id": TARGET_ID, "line": "换个目标"},
	)
	var devices3: Dictionary = world.get("_werewolf_state").get("policeDevices", {})
	_expect_equal(
		String(devices3.get("tracker", {}).get("targetId", "")),
		TARGET_ID,
		"装新目标覆盖旧定位装置",
	)
	_expect_equal(
		int(world.get("_werewolf_state").get("roleSkills", {}).get("police", {}).get("trackerCharges", -1)),
		1,
		"覆盖后定位余量 1",
	)
	# 7) 窃听剩 1 次 → 用掉后次数用完拒绝
	world.call(
		"_activate_police_eavesdrop_action",
		POLICE_ID,
		police,
		{"action_id": "intel-6", "target_resident_id": PARTNER_ID, "line": "再装一个"},
	)
	var exhausted := world.call(
		"_activate_police_eavesdrop_action",
		POLICE_ID,
		police,
		{"action_id": "intel-7", "target_resident_id": TARGET_ID, "line": "还想装"},
	) as Dictionary
	_expect_equal(
		bool(exhausted.get("ok", false)),
		false,
		"窃听器次数用完被拒",
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


func _advance_minutes(world: RefCounted, delta: int) -> void:
	var result := world.call("advance", float(delta)) as Dictionary
	_expect_equal(result.get("ok"), true, "advance %d 分钟 ok" % delta)


## 注入测试用角色(范式同 diag_police_alert.gd)
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
