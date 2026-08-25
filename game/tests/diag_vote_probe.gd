extends "res://tests/support/TownWorldTestCase.gd"
## diag_vote_probe.gd — 投票链路探针（注入狼人杀角色版）：
## 注入 3 卧底+警察+医生 → feature_active=true → 推进到第2天 11:00 开大会
## → 检查 vote 状态 / vote_snapshot / wake.snapshot.exile_vote → 直接 submit_vote
## → 推进 12:30 开票清空回合。纯本地、不调 API。
## 运行: Godot --headless --path game --script res://tests/diag_vote_probe.gd

const WEREWOLF := preload("res://world/runtime/TownWerewolfRuntime.gd")
const PROMPT_COMPILER := preload("res://agent/prompt/AgentPromptCompiler.gd")

const CIVILIAN_ID := "resident_lin_lan_01"
const UNDERCOVER_ID := "resident_xie_mian_01"
const QIAO_ID := "resident_qiao_yiming_01"
const HANAKO_ID := "resident_hanako_01"
const POLICE_ID := "resident_wen_xu_01"
const DOCTOR_ID := "resident_bai_zhi_01"
const TARGET_NAME := "唐小满"


func _initialize() -> void:
	print("===== 投票链路探针(注入狼人杀角色) =====\n")
	_verify_vote_chain()
	_finish_suite("VOTE_PROBE_PASS")


func _verify_vote_chain() -> void:
	var world := _new_skill_world("vote probe opening")
	var env: Object = world.get("_environment")
	var residents: Dictionary = world.call("residents")
	print(
		"  居民=%d 卧底谢眠=%s 警察闻叙=%s feature_active=%s" % [
			residents.size(),
			str(residents.has(UNDERCOVER_ID)),
			str(residents.has(POLICE_ID)),
			str(WEREWOLF.feature_active(world)),
		]
	)
	# 第1天 11:00 (day_index=0 不开会) → 第2天 11:00 开会
	_advance_to_minute_of_day(world, 660)
	print("  第1天 11:00 后 absolute_minute=%d" % int(env.call("get_absolute_minute")))
	_advance_to_minute_of_day(world, 660)
	print("  第2天 11:00 后 absolute_minute=%d" % int(env.call("get_absolute_minute")))
	var state: Dictionary = world.get("_werewolf_state")
	var vote := state.get("vote", {}) as Dictionary
	_expect_equal(vote.is_empty(), false, "第2天 11:00 后 vote 回合已开启")
	if vote.is_empty():
		world.call("stop")
		return
	print(
		"  回合 day=%d 候选 %d 人: %s" % [
			int(vote.get("day", -1)),
			(vote.get("candidateNames", []) as Array).size(),
			", ".join(vote.get("candidateNames", []) as Array),
		]
	)
	# 1) vote_snapshot 对在世普通居民应非空
	var snapshot: Dictionary = WEREWOLF.vote_snapshot(world, CIVILIAN_ID)
	_expect_equal(snapshot.is_empty(), false, "vote_snapshot(林岚) 非空")
	if not snapshot.is_empty():
		print(
			"  vote_snapshot: round_day=%d settle=%s forced=%s 候选=%d" % [
				int(snapshot.get("round_day", 0)),
				String(snapshot.get("settle_clock", "")),
				str(bool(snapshot.get("forced", false))),
				(snapshot.get("candidate_names", []) as Array).size(),
			]
		)
	# 2) wake 链: 唤醒林岚 → take → snapshot.exile_vote
	world.call("_schedule_decision", CIVILIAN_ID, true)
	var envelopes: Array = world.call(
		"take_pending_decision_requests_by_ids", [CIVILIAN_ID]
	) as Array
	var exile_in_wake: Dictionary = {}
	var wake_packet: Dictionary = {}
	for envelope_value: Variant in envelopes:
		var envelope := envelope_value as Dictionary
		if String(envelope.get("residentId", "")) != CIVILIAN_ID:
			continue
		wake_packet = envelope.get("wakePacket", {}) as Dictionary
		exile_in_wake = (
			(wake_packet.get("snapshot", {}) as Dictionary).get("exile_vote", {}) as Dictionary
		)
		break
	_expect_equal(exile_in_wake.is_empty(), false, "wake.snapshot.exile_vote 非空")
	if not exile_in_wake.is_empty():
		print(
			"  wake.exile_vote: forced=%s 候选=%d" % [
				str(bool(exile_in_wake.get("forced", false))),
				(exile_in_wake.get("candidate_names", []) as Array).size(),
			]
		)
	# 2.5) prompt 渲染: compile 后检查 exile_vote 约束文本 + 方案A 投票放逐动作
	var probe_decision_id := String(wake_packet.get("decision_id", ""))
	if not wake_packet.is_empty():
		var initialization: Dictionary = world.call(
			"get_agent_initialization", CIVILIAN_ID
		)
		var compiler := PROMPT_COMPILER.new(initialization)
		var compiled := compiler.compile(wake_packet, "", "") as Dictionary
		var user_content := ""
		var full_content := ""
		var messages := compiled.get("messages", []) as Array
		for message_value: Variant in messages:
			if message_value is Dictionary:
				full_content += String((message_value as Dictionary).get("content", ""))
		if messages.size() > 1:
			user_content = String((messages[1] as Dictionary).get("content", ""))
		var has_exile := user_content.contains("exile_vote")
		var has_forced := user_content.contains("必须提交")
		var has_vote_action := user_content.contains("投票放逐")
		var has_no_plaza := full_content.contains("不需要去任何地方")
		_expect_equal(has_exile, true, "prompt 含 exile_vote 约束")
		_expect_equal(has_forced, true, "prompt 含必须提交文案")
		_expect_equal(has_vote_action, true, "方案A: prompt 含投票放逐动作选项")
		_expect_equal(has_no_plaza, true, "prompt 明确投票不需要去任何地方")
		print(
			"  prompt: 含exile_vote=%s 含必须提交=%s 含投票放逐动作=%s 不需去广场=%s 长度=%d" % [
				str(has_exile),
				str(has_forced),
				str(has_vote_action),
				str(has_no_plaza),
				user_content.length(),
			]
		)
		if has_vote_action:
			var at := user_content.find("投票放逐")
			var start := maxi(0, at - 150)
			var end := mini(user_content.length(), at + 400)
			print("  --- prompt 投票放逐动作上下文 ---")
			print(user_content.substr(start, end - start))
			print("  --- 结束 ---")
	# 3) submit_vote 直接提交(附件通道)
	var votes_before: int = (
			(state.get("vote", {}) as Dictionary).get("votes", {}) as Dictionary
		).size()
	var submit_error := WEREWOLF.submit_vote(
		world,
		CIVILIAN_ID,
		{"target_resident_name": TARGET_NAME, "line": "我觉得谢眠可疑"},
	)
	_expect_equal(submit_error, "", "submit_vote 返回空(记录成功)")
	var after_state: Dictionary = world.get("_werewolf_state")
	var after_vote: Dictionary = after_state.get("vote", {}) as Dictionary
	var votes_after: int = (after_vote.get("votes", {}) as Dictionary).size()
	_expect_equal(votes_after > votes_before, true, "submit_vote 已记录(林岚→谢眠)")
	# 3.5) 方案A: submit_agent_decision 走完整提交链, action.type==投票放逐
	# 先无效目标(应拒绝不记录), 再有效目标(应记录)
	var resident2 := "resident_tang_xiaoman_01"
	world.call("_schedule_decision", resident2, true)
	var envelopes2: Array = world.call(
		"take_pending_decision_requests_by_ids", [resident2]
	) as Array
	var wake2: Dictionary = {}
	for envelope_value: Variant in envelopes2:
		var envelope := envelope_value as Dictionary
		if String(envelope.get("residentId", "")) != resident2:
			continue
		wake2 = envelope.get("wakePacket", {}) as Dictionary
		break
	var decision_id2 := String(wake2.get("decision_id", ""))
	var votes_before_2: Dictionary = (
			(world.get("_werewolf_state") as Dictionary).get("vote", {}) as Dictionary
		).get("votes", {}) as Dictionary
	var bad_result: Dictionary = world.call(
		"submit_agent_decision",
		resident2,
		{
			"decision_id": decision_id2,
			"handling": "replace_current",
			"action": {
				"action_id": decision_id2 + "-投票放逐",
				"type": "投票放逐",
				"target_resident_name": "不存在的人",
				"line": "试一下",
			},
		},
	)
	_expect_equal(
		bool(bad_result.get("ok", false)),
		false,
		"投票放逐无效目标被拒绝",
	)
	if not bool(bad_result.get("ok", false)):
		var bad_errors := bad_result.get("errors", []) as Array
		_expect_equal(
			bad_errors.is_empty(),
			false,
			"拒绝携带错误信息",
		)
		if not bad_errors.is_empty():
			print("  无效目标拒绝: %s" % String(bad_errors[0]))
	var votes_mid: Dictionary = (
			(world.get("_werewolf_state") as Dictionary).get("vote", {}) as Dictionary
		).get("votes", {}) as Dictionary
	_expect_equal(votes_mid.size(), votes_before_2.size(), "无效目标未记录投票")
	# 有效目标: 需重新取 wake(第一次 reject 后同 decision_id 已失效)
	world.call("_schedule_decision", resident2, true)
	var envelopes3: Array = world.call(
		"take_pending_decision_requests_by_ids", [resident2]
	) as Array
	var wake3: Dictionary = {}
	for envelope_value: Variant in envelopes3:
		var envelope := envelope_value as Dictionary
		if String(envelope.get("residentId", "")) != resident2:
			continue
		wake3 = envelope.get("wakePacket", {}) as Dictionary
		break
	var decision_id3 := String(wake3.get("decision_id", ""))
	var ok_result: Dictionary = world.call(
		"submit_agent_decision",
		resident2,
		{
			"decision_id": decision_id3,
			"handling": "replace_current",
			"action": {
				"action_id": decision_id3 + "-投票放逐",
				"type": "投票放逐",
				"target_resident_name": "林岚",
				"line": "我投林岚一票",
			},
		},
	)
	_expect_equal(bool(ok_result.get("ok", false)), true, "投票放逐有效目标已记录")
	if not bool(ok_result.get("ok", false)):
		var ok_errors := ok_result.get("errors", []) as Array
		if not ok_errors.is_empty():
			print("  有效目标提交失败: %s" % String(ok_errors[0]))
	if bool(ok_result.get("ok", false)):
		var votes_final: Dictionary = (
				(world.get("_werewolf_state") as Dictionary).get("vote", {}) as Dictionary
			).get("votes", {}) as Dictionary
		var recorded: Dictionary = votes_final.get(resident2, {}) as Dictionary
		_expect_equal(
			String(recorded.get("target_resident_name", "")),
			"林岚",
			"唐小满投票放逐林岚已落账",
		)
	# 4) 推进 12:30 开票 → vote 回合清空
	_advance_to_minute_of_day(world, 750)
	var settled: Dictionary = (
		(world.get("_werewolf_state") as Dictionary).get("vote", {}) as Dictionary
	)
	_expect_equal(settled.is_empty(), true, "开票后 vote 回合清空")
	world.call("stop")


# --- 辅助(范式同 diag_role_skills) ---

func _new_skill_world(label: String) -> RefCounted:
	var data := _build_data()
	var opening := _garden_opening(data, label)
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts (%s)" % label)
	if started.get("ok") != true:
		return world
	_inject_role_resident(world, UNDERCOVER_ID, "谢眠", "乐师")
	_inject_role_resident(world, QIAO_ID, "乔一鸣", "木匠")
	_inject_role_resident(world, HANAKO_ID, "花子", "旅人")
	_inject_role_resident(world, POLICE_ID, "闻叙", "警察")
	_inject_role_resident(world, DOCTOR_ID, "白芷", "医生")
	return world


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
