extends "res://tests/support/TownWorldTestCase.gd"
## diag_role_skills.gd — 狼人杀化身份技能第一批验证：
## 1) night_skill 契约（白名单/校验/canonicalize）
## 2) 20:00 夜间技能快照与提交（医生/图书管理员/卧底）
## 3) 医生守诊挡下暗杀
## 4) 08:00 结算：守护移出死亡队列 + 查验线索投递
## 5) 卧底嫁祸 → 警察案件档案假线索 + 暗杀死因脱敏
## 6) 警察制服额度（2 次）/ 错杀停职
## 运行: Godot --headless --path game --script res://tests/diag_role_skills.gd

const ROLE_SKILL := preload("res://world/runtime/TownRoleSkillRuntime.gd")
const CONTRACT := preload("res://agent/AgentContract.gd")
const CONTRACT_SNAPSHOT := preload("res://agent/contract/AgentContractSnapshot.gd")
const ACTION_VALIDATION := preload("res://world/runtime/action/TownActionValidation.gd")

const DOCTOR_ID := "resident_bai_zhi_01"
const SCHOLAR_ID := "resident_xu_zhao_01"
const UNDERCOVER_ID := "resident_xie_mian_01"
const POLICE_ID := "resident_wen_xu_01"
const CIVILIAN_ID := "resident_lin_lan_01"
const TANG_ID := "resident_tang_xiaoman_01"


func _initialize() -> void:
	print("===== 身份技能 验证 =====")
	_verify_night_skill_contract()
	_verify_night_snapshot_and_submit()
	_verify_doctor_blocks_assassination()
	_verify_night_resolution()
	_verify_frame_and_police_case()
	_verify_police_quota()
	_verify_night_only_team_cap()
	_verify_subdue_option_injection()
	_finish_suite("ROLE_SKILL_PASS")


# 场景1: 契约层 — night_skill 白名单/校验/canonicalize
func _verify_night_skill_contract() -> void:
	var decision := {
		"decision_id": "d1",
		"handling": "continue_current",
		"night_skill": {
			"skill_id": "doctor_protect",
			"target_resident_id": "resident_lin_lan_01",
			"line": "我担心他。",
		},
	}
	_expect_equal(
		ACTION_VALIDATION.validate_decision_shape(decision),
		"",
		"决策形状校验接受 night_skill",
	)
	var wake := {
		"snapshot": {
			"night_skill": {
				"round_day": 1,
				"settle_clock": "次日 08:00",
				"skills": ["doctor_protect", "scholar_inspect"],
				"candidate_ids": ["resident_lin_lan_01", "resident_tang_xiaoman_01"],
			},
		},
	}
	var errors: Array[String] = []
	CONTRACT_SNAPSHOT._validate_night_skill(
		decision["night_skill"],
		wake,
		errors,
	)
	_expect_equal(errors.is_empty(), true, "合法 night_skill 通过校验 (%s)" % str(errors))
	errors = []
	CONTRACT_SNAPSHOT._validate_night_skill(
		{
			"skill_id": "undercover_frame",
			"target_resident_id": "resident_lin_lan_01",
			"line": "让他背锅。",
		},
		wake,
		errors,
	)
	_expect_equal(errors.is_empty(), false, "不在技能列表的 skill_id 被拒绝")
	errors = []
	CONTRACT_SNAPSHOT._validate_night_skill(
		decision["night_skill"],
		{"snapshot": {}},
		errors,
	)
	_expect_equal(errors.is_empty(), false, "无夜间技能阶段时 night_skill 被拒绝")
	var canonical := CONTRACT.canonicalize_decision({
		"decision_id": "d1",
		"handling": "continue_current",
		"night_skill": {
			"skill_id": "doctor_protect",
			"target_resident_id": "resident_lin_lan_01",
			"line": "我担心他。",
			"extra_field": "应被剥离",
		},
	})
	var canonical_skill: Dictionary = canonical.get("night_skill", {}) as Dictionary
	_expect_equal(
		canonical_skill.has("extra_field"),
		false,
		"canonicalize 剥离多余字段",
	)


# 场景2: 20:00 夜间技能快照与提交
func _verify_night_snapshot_and_submit() -> void:
	var world := _new_skill_world("role skill snapshot opening")
	_expect_equal(ROLE_SKILL.police_can_subdue(world), true, "警察初始额度可用")
	_advance_to_minute_of_day(world, 1200)  # 20:00 夜间行动开始
	var doctor_snapshot := ROLE_SKILL.night_skill_snapshot(world, DOCTOR_ID)
	_expect_equal(
		(doctor_snapshot.get("skills", []) as Array).has("doctor_protect"),
		true,
		"医生 20:00 拿到守诊技能",
	)
	var scholar_snapshot := ROLE_SKILL.night_skill_snapshot(world, SCHOLAR_ID)
	_expect_equal(
		(scholar_snapshot.get("skills", []) as Array).has("scholar_inspect"),
		true,
		"图书管理员 20:00 拿到查验技能",
	)
	var frame_snapshot := ROLE_SKILL.night_skill_snapshot(world, UNDERCOVER_ID)
	_expect_equal(
		(frame_snapshot.get("skills", []) as Array).has("undercover_frame"),
		true,
		"卧底 20:00 拿到嫁祸技能",
	)
	var lin_name := String(world.call("_resident_display_name", CIVILIAN_ID))
	var tang_name := String(world.call("_resident_display_name", TANG_ID))
	ROLE_SKILL.submit_night_skill(world, DOCTOR_ID, {
		"skill_id": "doctor_protect",
		"target_resident_id": CIVILIAN_ID,
		"line": "今晚守着他。",
	})
	ROLE_SKILL.submit_night_skill(world, SCHOLAR_ID, {
		"skill_id": "scholar_inspect",
		"target_resident_id": TANG_ID,
		"line": "查查她夜里在哪。",
	})
	ROLE_SKILL.submit_night_skill(world, UNDERCOVER_ID, {
		"skill_id": "undercover_frame",
		"target_resident_id": CIVILIAN_ID,
		"line": "让他背锅。",
	})
	var skills: Dictionary = (
		world.get("_werewolf_state") as Dictionary
	).get("roleSkills", {}) as Dictionary
	_expect_equal(
		String((skills.get("doctor", {}) as Dictionary).get("submissionTargetId", "")),
		CIVILIAN_ID,
		"医生守护提交成功",
	)
	_expect_equal(
		((skills.get("scholar", {}) as Dictionary).get("submission", {}) as Dictionary).is_empty(),
		false,
		"查验提交成功",
	)
	_expect_equal(
		String((skills.get("frame", {}) as Dictionary).get("pendingTargetId", "")),
		CIVILIAN_ID,
		"嫁祸提交成功",
	)
	_expect_equal(
		ROLE_SKILL.night_skill_snapshot(world, DOCTOR_ID).is_empty(),
		true,
		"已提交技能的居民不再重复拿到 night_skill",
	)
	world.call("stop")


# 场景3: 医生守诊在暗杀执行时挡刀
func _verify_doctor_blocks_assassination() -> void:
	var world := _new_skill_world("role skill doctor block opening")
	_advance_to_minute_of_day(world, 1200)
	var lin_name := String(world.call("_resident_display_name", CIVILIAN_ID))
	ROLE_SKILL.submit_night_skill(world, DOCTOR_ID, {
		"skill_id": "doctor_protect",
		"target_resident_id": CIVILIAN_ID,
		"line": "今晚守着他。",
	})
	_advance_to_minute_of_day(world, 1260)  # 21:00 夜深
	var residents: Dictionary = world.call("residents")
	var actor := residents.get(UNDERCOVER_ID, {}) as Dictionary
	var target := residents.get(CIVILIAN_ID, {}) as Dictionary
	actor["spaceId"] = target.get("spaceId", "")
	actor["regionId"] = target.get("regionId", "")
	actor["currentPlace"] = target.get("currentPlace", "")
	actor["position"] = (target.get("position", Vector2.ZERO) as Vector2) + Vector2(20, 0)
	var action := {
		"action_id": "diag-role-doctor-block",
		"type": "暗杀",
		"target_resident_id": CIVILIAN_ID,
		"line": "别出声。",
	}
	world.call(
		"_activate_assassination_action",
		UNDERCOVER_ID,
		actor,
		action,
		{},
		"",
		{},
	)
	var lifecycle := world.call(
		"get_resident_lifecycle_state",
		CIVILIAN_ID,
	) as Dictionary
	_expect_equal(
		String(lifecycle.get("status", "")),
		"alive",
		"医生守护的暗杀目标没有死亡",
	)
	_expect_equal(
		((world.get("_werewolf_state") as Dictionary).get("pendingDeathAnnouncements", []) as Array).size(),
		0,
		"被挡下的暗杀不入天亮死亡队列",
	)
	var second_action := {
		"action_id": "diag-role-doctor-block-second",
		"type": "暗杀",
		"target_resident_id": TANG_ID,
		"line": "再试一次。",
	}
	var second_prepared := world.call(
		"_prepare_assassination_action",
		UNDERCOVER_ID,
		actor,
		second_action,
	) as Dictionary
	_expect_equal(second_prepared.get("ok"), false, "被医生挡下后同夜不能再杀")
	world.call("stop")


# 场景4: 08:00 结算 — 守护移除队列 + 查验投递线索
func _verify_night_resolution() -> void:
	var world := _new_skill_world("role skill night resolve opening")
	_advance_to_minute_of_day(world, 1200)
	var lin_name := String(world.call("_resident_display_name", CIVILIAN_ID))
	var tang_name := String(world.call("_resident_display_name", TANG_ID))
	ROLE_SKILL.submit_night_skill(world, DOCTOR_ID, {
		"skill_id": "doctor_protect",
		"target_resident_id": CIVILIAN_ID,
		"line": "今晚守着他。",
	})
	ROLE_SKILL.submit_night_skill(world, SCHOLAR_ID, {
		"skill_id": "scholar_inspect",
		"target_resident_id": TANG_ID,
		"line": "查查她夜里在哪。",
	})
	# 模拟夜里林岚被暗杀、已进入待公布队列（医生守护应在天亮前摘除）。
	var state: Dictionary = world.get("_werewolf_state") as Dictionary
	var queue: Array = state.get("pendingDeathAnnouncements", []) as Array
	queue.append({
		"event": {
			"event_id": "diag-role-skill-fake-death",
			"deceased_resident_id": CIVILIAN_ID,
			"deceased_resident_name": lin_name,
			"reason": "被谢眠暗杀",
			"attacker_resident_id": UNDERCOVER_ID,
		},
	})
	state["pendingDeathAnnouncements"] = queue
	_advance_to_minute_of_day(world, 480)  # 次日 08:00
	var state_dawn: Dictionary = world.get("_werewolf_state") as Dictionary
	_expect_equal(
		(state_dawn.get("pendingDeathAnnouncements", []) as Array).size(),
		0,
		"医生守护的目标从天亮死亡队列中移除",
	)
	var skills: Dictionary = state_dawn.get("roleSkills", {}) as Dictionary
	_expect_equal(
		String((skills.get("doctor", {}) as Dictionary).get("lastProtectedId", "")),
		CIVILIAN_ID,
		"医生守护记录写入",
	)
	_expect_equal(
		int((skills.get("scholar", {}) as Dictionary).get("charges", 0)),
		2,
		"查验扣减一次额度",
	)
	var scholar_resident: Dictionary = (
		world.call("residents") as Dictionary
	).get(SCHOLAR_ID, {}) as Dictionary
	var has_clue := false
	for queue_key: String in ["eventQueue", "inflightEvents"]:
		for event_value: Variant in scholar_resident.get(queue_key, []) as Array:
			var event := event_value as Dictionary
			if String(event.get("type", "")) == "查验结果":
				has_clue = true
				_expect_equal(
					String(event.get("summary", "")).contains(tang_name),
					true,
					"查验线索指向被查验目标",
				)
	_expect_equal(has_clue, true, "图书管理员收到查验结果事件")
	world.call("stop")


# 场景5: 嫁祸消费 → 警察档案死因脱敏 + 假线索
func _verify_frame_and_police_case() -> void:
	var world := _new_skill_world("role skill frame opening")
	_advance_to_minute_of_day(world, 1200)
	var lin_name := String(world.call("_resident_display_name", CIVILIAN_ID))
	ROLE_SKILL.submit_night_skill(world, UNDERCOVER_ID, {
		"skill_id": "undercover_frame",
		"target_resident_id": CIVILIAN_ID,
		"line": "让他背锅。",
	})
	_advance_to_minute_of_day(world, 480)  # 天亮（本轮无凶案，嫁祸保持待用）
	var state: Dictionary = world.get("_werewolf_state") as Dictionary
	_expect_equal(
		bool((state.get("roleSkills", {}) as Dictionary).get("frame", {}).get("used", false)),
		false,
		"没有凶案时嫁祸不被消费",
	)
	var result := world.call(
		"confirm_resident_death",
		TANG_ID,
		"被谢眠暗杀",
	) as Dictionary
	_expect_equal(result.get("ok"), true, "暗杀死亡确认 ok")
	var frame: Dictionary = (
		(world.get("_werewolf_state") as Dictionary).get("roleSkills", {}) as Dictionary
	).get("frame", {}) as Dictionary
	_expect_equal(bool(frame.get("used", false)), true, "嫁祸在暗杀发生时消费")
	var cases: Array = world.call("_police_death_cases", POLICE_ID) as Array
	var found := false
	for case_value: Variant in cases:
		var case := case_value as Dictionary
		if String(case.get("deceased_resident_id", "")) != TANG_ID:
			continue
		found = true
		_expect_equal(String(case.get("reason", "")), "被暗杀", "警察档案死因脱敏")
		_expect_equal(String(case.get("attacker_resident_id", "")), "", "警察档案不直接给凶手")
		_expect_equal(
			String(case.get("clue", "")).contains(lin_name),
			true,
			"嫁祸线索指向被嫁祸者 (%s)" % String(case.get("clue", "")),
		)
	_expect_equal(found, true, "警察案件档案包含新案件")
	world.call("stop")


# 场景6: 警察制服额度与错杀停职
func _verify_police_quota() -> void:
	var world := _new_skill_world("role skill police quota opening")
	_expect_equal(ROLE_SKILL.police_can_subdue(world), true, "初始可以制服")
	_expect_equal(ROLE_SKILL.police_charges_remaining(world), 2, "初始额度 2")
	ROLE_SKILL.record_subdue_result(world, CIVILIAN_ID, false)
	_expect_equal(ROLE_SKILL.police_can_subdue(world), false, "错杀平民后停职")
	_expect_equal(ROLE_SKILL.police_charges_remaining(world), 0, "错杀后额度清零")
	var police_resident: Dictionary = (
		world.call("residents") as Dictionary
	).get(POLICE_ID, {}) as Dictionary
	var action := {
		"action_id": "diag-role-skill-subdue",
		"type": "制服",
		"target_resident_id": CIVILIAN_ID,
		"line": "跟我走一趟。",
	}
	var prepared := world.call(
		"_prepare_subdue_action",
		POLICE_ID,
		police_resident,
		action,
	) as Dictionary
	_expect_equal(prepared.get("ok"), false, "停职后制服被拒绝")
	_expect_equal(
		String((prepared.get("errors", []) as Array)[0]).contains("额度"),
		true,
		"拒绝原因包含额度说明",
	)
	# 正确制服只扣额度、不停职。
	var skills: Dictionary = (
		world.get("_werewolf_state") as Dictionary
	).get("roleSkills", {}) as Dictionary
	var police: Dictionary = skills.get("police", {}) as Dictionary
	police["charges"] = 2
	police["disarmed"] = false
	skills["police"] = police
	ROLE_SKILL.record_subdue_result(world, UNDERCOVER_ID, true)
	_expect_equal(ROLE_SKILL.police_can_subdue(world), true, "正确制服后仍可继续")
	_expect_equal(ROLE_SKILL.police_charges_remaining(world), 1, "正确制服扣 1 次额度")
	world.call("stop")


# 场景7: 暗杀只在夜间可用 + 全队每晚最多一次（含被医生挡下）
func _verify_night_only_team_cap() -> void:
	var world := _new_skill_world("role skill night gate opening")
	var residents: Dictionary = world.call("residents")
	var actor := residents.get(UNDERCOVER_ID, {}) as Dictionary
	var day_action := {
		"action_id": "diag-role-skill-day-kill",
		"type": "暗杀",
		"target_resident_id": CIVILIAN_ID,
		"line": "现在动手。",
	}
	var day_prepared := world.call(
		"_prepare_assassination_action",
		UNDERCOVER_ID,
		actor,
		day_action,
	) as Dictionary
	_expect_equal(day_prepared.get("ok"), false, "白天暗杀准备被拒绝")
	_expect_equal(
		String((day_prepared.get("errors", []) as Array)[0]).contains("夜间"),
		true,
		"白天拒绝原因说明只能在夜间动手",
	)
	_advance_to_minute_of_day(world, 1200)  # 进入第一晚
	# 巡逻威慑: 把警察移到远处(镇公所室内, 与目标不同区域), 避免"附近有
	# 警察"拦截本场景的暗杀判定(巡逻威慑机制由 diag_police_patrol 单独验证)。
	_move_police_away(residents)
	var target := residents.get(CIVILIAN_ID, {}) as Dictionary
	actor["spaceId"] = target.get("spaceId", "")
	actor["regionId"] = target.get("regionId", "")
	actor["currentPlace"] = target.get("currentPlace", "")
	actor["position"] = (target.get("position", Vector2.ZERO) as Vector2) + Vector2(20, 0)
	var night_prepared := world.call(
		"_prepare_assassination_action",
		UNDERCOVER_ID,
		actor,
		day_action,
	) as Dictionary
	_expect_equal(night_prepared.get("ok"), true, "夜间暗杀准备通过")
	# 直接激活一次成功暗杀（杀唐小满），随后全队当夜不可再杀。
	var kill_action := {
		"action_id": "diag-role-skill-night-kill",
		"type": "暗杀",
		"target_resident_id": TANG_ID,
		"line": "别出声。",
	}
	world.call(
		"_activate_assassination_action",
		UNDERCOVER_ID,
		actor,
		kill_action,
		{},
		"",
		{},
	)
	_expect_equal(
		String(world.call("get_resident_lifecycle_state", TANG_ID).get("status", "")),
		"dead",
		"夜间第一次暗杀成功",
	)
	var second_prepared := world.call(
		"_prepare_assassination_action",
		UNDERCOVER_ID,
		actor,
		day_action,
	) as Dictionary
	_expect_equal(second_prepared.get("ok"), false, "同夜第二次暗杀被拒绝")
	_expect_equal(
		String((second_prepared.get("errors", []) as Array)[0]).contains("今晚"),
		true,
		"同夜拒绝原因包含全队配额说明",
	)
	_advance_to_minute_of_day(world, 1200)  # 下一晚，配额重置
	_move_police_away(residents)
	var next_night_prepared := world.call(
		"_prepare_assassination_action",
		UNDERCOVER_ID,
		actor,
		day_action,
	) as Dictionary
	_expect_equal(next_night_prepared.get("ok"), true, "新的一晚恢复暗杀额度")
	world.call("stop")


# 场景7: 警察选项注入 — 闻叙(警察)对感知范围内居民注入 subdue
# 与 _prepare_subdue_action 判定一致(同 spaceId+同 regionId+距离),选项出现=提交能通过
func _verify_subdue_option_injection() -> void:
	var world := _new_skill_world("role skill subdue option opening")
	var residents: Dictionary = world.call("residents")
	var police: Variant = residents.get(POLICE_ID)
	if not police is Dictionary:
		_expect_equal(police is Dictionary, true, "闻叙已注入")
		world.call("stop")
		return
	var police_dict := police as Dictionary
	police_dict["spaceId"] = "town_outdoor"
	police_dict["regionId"] = "outdoor_plaza_01"
	police_dict["position"] = Vector2(100, 100)
	var civilian: Variant = residents.get(CIVILIAN_ID)
	if civilian is Dictionary:
		var civilian_dict := civilian as Dictionary
		civilian_dict["spaceId"] = "town_outdoor"
		civilian_dict["regionId"] = "outdoor_plaza_01"
		civilian_dict["position"] = Vector2(200, 100)
		civilian_dict["currentAction"] = {}
	var decorated: Array = world.call(
		"_decorate_conflict_tension_options",
		POLICE_ID,
		police_dict,
		[],
	) as Array
	var has_subdue := false
	var target_id := ""
	for option_value: Variant in decorated:
		if not option_value is Dictionary:
			continue
		var option := option_value as Dictionary
		if String(option.get("kind", "")) == "subdue":
			has_subdue = true
			target_id = String(option.get("target_resident_id", ""))
			break
	_expect_equal(has_subdue, true, "警察选项注入含 subdue (共%d个)" % decorated.size())
	print("  注入选项数=%d subdue目标=%s" % [decorated.size(), target_id])
	world.call("stop")


# --- 辅助 ---

## 把警察移到远处(镇公所室内, 与目标不同 space), 隔离巡逻威慑机制。
func _move_police_away(residents: Dictionary) -> void:
	var police_res: Variant = residents.get(POLICE_ID, {})
	if police_res is Dictionary:
		(police_res as Dictionary)["spaceId"] = "indoor_town_hall"
		(police_res as Dictionary)["regionId"] = "region_portal_town_hall_entry"
		(police_res as Dictionary)["currentPlace"] = "镇公所"
		(police_res as Dictionary)["currentAction"] = {}


func _new_skill_world(label: String) -> RefCounted:
	var data := _build_data()
	var opening := _garden_opening(data, label)
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts (%s)" % label)
	if started.get("ok") != true:
		return world
	_inject_role_resident(world, DOCTOR_ID, "白芷", "医生")
	_inject_role_resident(world, SCHOLAR_ID, "许照", "图书管理员")
	_inject_role_resident(world, UNDERCOVER_ID, "谢眠", "乐师")
	_inject_role_resident(world, POLICE_ID, "闻叙", "警察")
	return world


## 注入测试用角色：进入 residents/_resident_order + 初始化生命周期。
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
			"gender": "女" if resident_id != UNDERCOVER_ID else "男",
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
