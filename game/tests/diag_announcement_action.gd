extends "res://tests/support/TownWorldTestCase.gd"
## diag_announcement_action.gd — 验证"发布公告"动作
## 1) 广场可发, 公告生效(公告栏有公告)
## 2) 非广场拒绝
## 3) 编译分流: 卧底system含卧底规则, 警察system含警察规则, 普通居民不含

const PROMPT_COMPILER := preload("res://agent/prompt/AgentPromptCompiler.gd")

func _initialize() -> void:
	print("===== 发布公告动作 + 编译分流 验证 =====")
	_verify_publish_in_plaza()
	_verify_publish_not_in_plaza()
	_verify_compile_role_split()
	_finish_suite("ANNOUNCEMENT_ACTION_PASS")


func _setup_world(place: String) -> RefCounted:
	var data := _build_data()
	var opening := _garden_opening(data, "announcement opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	var residents := world.call("residents") as Dictionary
	var lin: Variant = residents.get("resident_lin_lan_01")
	if lin is Dictionary:
		(lin as Dictionary)["currentPlace"] = place
	return world


func _run_publish(world: RefCounted) -> Dictionary:
	var action := {
		"action_id": "diag-ann-%s" % str(Time.get_ticks_usec()),
		"type": "发布公告",
		"text": "今晚8点在花园有聚会，请大家务必到场。",
		"line": "张贴公告。",
	}
	return world.call(
		"_prepare_announcement_action",
		"resident_lin_lan_01",
		(world.call("residents") as Dictionary)["resident_lin_lan_01"] as Dictionary,
		action,
	) as Dictionary


func _verify_publish_in_plaza() -> void:
	var world := _setup_world("中心广场")
	var prepared := _run_publish(world)
	print("  广场发布 ok=%s" % str(prepared.get("ok", false)))
	_expect_equal(prepared.get("ok"), true, "中心广场可发布公告")
	world.call("stop")


func _verify_publish_not_in_plaza() -> void:
	var world := _setup_world("北街一号住宅")
	var prepared := _run_publish(world)
	print("  非广场发布 ok=%s errors=%s" % [
		str(prepared.get("ok", false)),
		str(prepared.get("errors", [])),
	])
	_expect_equal(prepared.get("ok"), false, "非中心广场拒绝发布")
	world.call("stop")


func _verify_compile_role_split() -> void:
	var initialization := {
		"me": {
			"resident_id": "resident_mi_ya_01",
			"social_state": {"job": "木匠", "home": "北街一号住宅"},
			"attributes": {"name": "米娅", "personality": "普通居民", "desire": "正常生活"},
		},
		"residents": [],
	}
	# 普通居民: 无角色规则
	var compiler_common := PROMPT_COMPILER.new(initialization)
	var baseline_common := compiler_common.get("_baseline_prompt") as String
	_expect_equal(baseline_common.contains("角色专属规则"), false, "普通居民无角色规则")
	# 卧底: 含卧底规则
	var init_undercover := initialization.duplicate(true)
	(init_undercover["me"] as Dictionary)["is_undercover"] = true
	var compiler_undercover := PROMPT_COMPILER.new(init_undercover)
	var baseline_under := compiler_undercover.get("_baseline_prompt") as String
	print("  卧底system含角色规则=%s" % str(baseline_under.contains("卧底行动规则")))
	_expect_equal(baseline_under.contains("卧底行动规则"), true, "卧底system含卧底规则")
	_expect_equal(baseline_under.contains("用公告制造机会"), true, "卧底system含公告引导")
	# 警察: 含警察规则
	var init_police := initialization.duplicate(true)
	((init_police["me"] as Dictionary)["social_state"] as Dictionary)["job"] = "警察"
	var compiler_police := PROMPT_COMPILER.new(init_police)
	var baseline_police := compiler_police.get("_baseline_prompt") as String
	print("  警察system含角色规则=%s" % str(baseline_police.contains("警察查案规则")))
	_expect_equal(baseline_police.contains("警察查案规则"), true, "警察system含警察规则")
	_expect_equal(baseline_police.contains("用公告发动全镇"), true, "警察system含公告引导")
