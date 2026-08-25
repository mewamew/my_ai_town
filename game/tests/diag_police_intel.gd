extends "res://tests/support/TownWorldTestCase.gd"
## diag_police_intel.gd — 警察侦查装备（窃听器/定位器）验证:
## 1) 非警察使用被拒 / 目标为空被拒
## 2) 窃听器: 每局 2 次, 消耗后生成对话情报(含目标参与对话的台词与地点)
## 3) 定位器: 每局 3 次, 消耗后生成位置情报(含当前位置与行踪)
## 4) 次数用尽后拒绝使用
## 运行: Godot --headless --path game --script res://tests/diag_police_intel.gd

const POLICE_ID := "resident_wen_xu_01"
const TARGET_ID := "resident_lin_lan_01"
const PARTNER_ID := "resident_tang_xiaoman_01"

const SPACE := "town_outdoor"
const REGION := "outdoor_plaza_01"


func _initialize() -> void:
	print("===== 警察侦查装备(窃听器/定位器) 验证 =====")
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
	_place(residents, TARGET_ID, Vector2(200, 100))
	_place(residents, PARTNER_ID, Vector2(300, 100))
	_seed_conversation(world)

	var police := residents[POLICE_ID] as Dictionary
	var lin := residents[TARGET_ID] as Dictionary

	# 1) 非警察使用被拒
	var rejected := world.call(
		"_activate_police_eavesdrop_action",
		TARGET_ID,
		lin,
		{"action_id": "intel-0", "target_resident_name": "闻叙", "line": "测试"},
	) as Dictionary
	_expect_equal(
		bool(rejected.get("ok", false)),
		false,
		"非警察使用窃听器被拒",
	)
	# 2) 目标为空被拒
	var empty_target := world.call(
		"_activate_police_eavesdrop_action",
		POLICE_ID,
		police,
		{"action_id": "intel-1", "target_resident_name": "", "line": "测试"},
	) as Dictionary
	_expect_equal(
		bool(empty_target.get("ok", false)),
		false,
		"窃听目标为空被拒",
	)
	# 3) 初始窃听余量 2
	_expect_equal(
		int(world.get("_werewolf_state").get("roleSkills", {}).get("police", {}).get("eavesdropCharges", -1)),
		2,
		"初始窃听器 2 次",
	)
	# 4) 窃听林岚 → 成功, 余量 2→1, 情报含对话台词与地点
	var eavesdrop := world.call(
		"_activate_police_eavesdrop_action",
		POLICE_ID,
		police,
		{"action_id": "intel-2", "target_resident_name": "林岚", "line": "让我听听她最近在聊什么"},
	) as Dictionary
	_expect_equal(
		bool(eavesdrop.get("ok", false)),
		true,
		"窃听林岚成功",
	)
	var eavesdrop_summary := String(eavesdrop.get("summary", ""))
	_expect(
		eavesdrop_summary.contains("林岚"),
		"窃听情报含目标名(实际: %s)" % eavesdrop_summary,
	)
	_expect(
		eavesdrop_summary.contains("昨晚你看到什么了吗"),
		"窃听情报含目标对话台词(实际: %s)" % eavesdrop_summary,
	)
	_expect(
		eavesdrop_summary.contains("中心广场"),
		"窃听情报含对话地点(实际: %s)" % eavesdrop_summary,
	)
	_expect_equal(
		int(world.get("_werewolf_state").get("roleSkills", {}).get("police", {}).get("eavesdropCharges", -1)),
		1,
		"窃听后余量 1",
	)
	# 5) 再窃听 → 余量 1→0
	var eavesdrop2 := world.call(
		"_activate_police_eavesdrop_action",
		POLICE_ID,
		police,
		{"action_id": "intel-3", "target_resident_name": "唐小满", "line": "再听听唐小满"},
	) as Dictionary
	_expect_equal(
		bool(eavesdrop2.get("ok", false)),
		true,
		"第二次窃听成功",
	)
	_expect_equal(
		int(world.get("_werewolf_state").get("roleSkills", {}).get("police", {}).get("eavesdropCharges", -1)),
		0,
		"窃听后余量 0",
	)
	# 6) 第三次 → 次数用完被拒
	var eavesdrop3 := world.call(
		"_activate_police_eavesdrop_action",
		POLICE_ID,
		police,
		{"action_id": "intel-4", "target_resident_name": "林岚", "line": "还想听"},
	) as Dictionary
	_expect_equal(
		bool(eavesdrop3.get("ok", false)),
		false,
		"窃听器次数用完被拒",
	)
	# 7) 定位: 初始 3 次, 定位林岚 → 情报含当前位置
	_expect_equal(
		int(world.get("_werewolf_state").get("roleSkills", {}).get("police", {}).get("trackerCharges", -1)),
		3,
		"初始定位器 3 次",
	)
	var tracker := world.call(
		"_activate_police_tracker_action",
		POLICE_ID,
		police,
		{"action_id": "intel-5", "target_resident_name": "林岚", "line": "看看她现在在哪"},
	) as Dictionary
	_expect_equal(
		bool(tracker.get("ok", false)),
		true,
		"定位林岚成功",
	)
	var tracker_summary := String(tracker.get("summary", ""))
	_expect(
		tracker_summary.contains("现在在中心广场"),
		"定位情报含当前位置(实际: %s)" % tracker_summary,
	)
	_expect_equal(
		int(world.get("_werewolf_state").get("roleSkills", {}).get("police", {}).get("trackerCharges", -1)),
		2,
		"定位后余量 2",
	)
	# 8) 连续定位 3 次用完 → 第 4 次被拒
	for i in 2:
		var tracker_more := world.call(
			"_activate_police_tracker_action",
			POLICE_ID,
			police,
			{"action_id": "intel-6-%d" % i, "target_resident_name": "唐小满", "line": "继续定位"},
		) as Dictionary
		_expect_equal(
			bool(tracker_more.get("ok", false)),
			true,
			"定位唐小满成功(%d/2)" % (i + 1),
		)
	var tracker_done := world.call(
		"_activate_police_tracker_action",
		POLICE_ID,
		police,
		{"action_id": "intel-7", "target_resident_name": "林岚", "line": "还想定位"},
	) as Dictionary
	_expect_equal(
		bool(tracker_done.get("ok", false)),
		false,
		"定位器次数用完被拒",
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


## 塞一条林岚与唐小满的模拟对话到 conversation_state.records
func _seed_conversation(world: RefCounted) -> void:
	var conv_state: Object = world.get("conversation_state")
	var records: Dictionary = conv_state.get("records")
	records["diag-intel-conv-1"] = {
		"conversationId": "diag-intel-conv-1",
		"participants": ["林岚", "唐小满"],
		"initiator": "林岚",
		"turns": [
			{
				"turn_id": 1,
				"speaker_resident_id": "resident_lin_lan_01",
				"speaker": "林岚",
				"say": "昨晚你看到什么了吗",
				"narration": "",
				"photos": [],
			},
			{
				"turn_id": 2,
				"speaker_resident_id": "resident_tang_xiaoman_01",
				"speaker": "唐小满",
				"say": "我看到有人深夜在镇公所附近徘徊",
				"narration": "",
				"photos": [],
			},
		],
		"waitingFor": "",
		"status": "ended",
		"startedAt": world.call("get_time"),
		"updatedAt": world.call("get_time"),
		"placeName": "中心广场",
		"endReason": "自然结束",
	}


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
