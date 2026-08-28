extends "res://tests/support/TownWorldTestCase.gd"
## diag_assembly_state_machine.gd — 警察审讯会状态机验证(2026-08-27)
## 覆盖: 汇报期(校验/收齐/超时) → 审讯期(登记计数/5人上限/逐字稿/主动结束)
##       → 投票期(收齐立即开票/超时兜底) → 散会解冻; 大会冻结(advance 短路);
##       wake 注入(assembly 键); 桥接层(对话钩子); 动作白名单。
## 双轨: FakeWorld 纯状态机 + 真实世界集成(第1天08:00自动触发/冻结/解冻)。
## 运行: Godot --headless --path game --script res://tests/diag_assembly_state_machine.gd

const WEREWOLF := preload("res://world/runtime/TownWerewolfRuntime.gd")

const UNDERCOVER_IDS: Array[String] = [
	"resident_xie_mian_01",
	"resident_qiao_yiming_01",
	"resident_hanako_01",
]


func _initialize() -> void:
	print("===== 警察审讯会状态机验证 =====")
	_verify_fake_state_machine()
	_verify_fake_phase_timeouts()
	_verify_real_world_assembly()
	_finish_suite("ASSEMBLY_STATE_MACHINE_PASS")


# —— 场景1: FakeWorld 全流程状态机 ——

func _verify_fake_state_machine() -> void:
	var fake := _make_fake_world()
	fake.absolute_minute = 1440 + 480  # 第1天 08:00
	_expect_equal(WEREWOLF.assembly_phase(fake), "idle", "初始无大会")
	_expect_equal(WEREWOLF.assembly_frozen(fake), false, "初始未冻结")
	# day<1 不开会(第0天 08:00)
	WEREWOLF.start_assembly(fake, 480)
	_expect_equal(WEREWOLF.assembly_phase(fake), "idle", "第0天不开会")
	# 08:00 触发
	WEREWOLF.start_assembly(fake, fake.absolute_minute)
	_expect_equal(WEREWOLF.assembly_phase(fake), "report", "08:00 进入汇报期")
	_expect_equal(WEREWOLF.assembly_frozen(fake), true, "大会期间世界冻结")
	_expect_equal(_announcement_text(fake).contains("警察审讯会开始"), true, "广播开会公告")
	# 同一天重复触发不重开
	WEREWOLF.start_assembly(fake, fake.absolute_minute)
	_expect_equal(WEREWOLF.assembly_phase(fake), "report", "同天不重开")
	# 汇报校验
	_expect_equal(
		WEREWOLF.submit_report(fake, "p", {"kind": "目击", "line": "x"}),
		"警察主持审讯，无需汇报",
		"警察不汇报",
	)
	_expect_equal(
		WEREWOLF.submit_report(fake, "c1", {"kind": "乱写", "line": "x"}),
		"汇报类型 kind 必须是：目击、听到、怀疑、不汇报",
		"非法 kind 拒绝",
	)
	_expect_equal(
		WEREWOLF.submit_report(fake, "c1", {"kind": "目击"}),
		"汇报内容 line 不能为空",
		"目击必须带内容",
	)
	_expect_equal(
		WEREWOLF.submit_report(fake, "c1", {"kind": "目击", "line": "看到他在案发现场"}),
		"",
		"合法汇报通过",
	)
	_expect_equal(
		WEREWOLF.submit_report(fake, "c1", {"kind": "目击", "line": "重复"}),
		"你已经提交过汇报了，一次审讯只能汇报一次",
		"重复汇报拒绝",
	)
	_expect_equal(WEREWOLF.submit_report(fake, "c2", {"kind": "不汇报", "line": ""}), "", "不汇报可空内容")
	# 未收齐(缺 c3)不进审讯期
	_expect_equal(WEREWOLF.assembly_phase(fake), "report", "未收齐仍在汇报期")
	_expect_equal(int(fake._werewolf_state.get("assembly", {}).get("reportElapsed", 0.0)), 0, "reportElapsed 初始 0")
	# 汇报期超时兜底(累计 >60s)
	WEREWOLF.tick_assembly(fake, 61.0)
	_expect_equal(WEREWOLF.assembly_phase(fake), "interrogation", "汇报超时→审讯期")
	var summary: Array = fake._werewolf_state.get("assembly", {}).get("reportSummary", [])
	_expect_equal(summary.size(), 3, "汇报汇总含全部存活非警察")
	var c3_summary := summary[2] as Dictionary
	_expect_equal(String(c3_summary.get("kind", "")), "未汇报", "超时未交视为不汇报")
	# 审讯登记
	_expect_equal(WEREWOLF.begin_interrogation_target(fake, "c3", "p"), false, "平民不能发起审讯")
	_expect_equal(WEREWOLF.begin_interrogation_target(fake, "p", "p"), false, "不能审警察")
	_expect_equal(WEREWOLF.begin_interrogation_target(fake, "p", "c1"), true, "警察发起审讯登记成功")
	var assembly: Dictionary = fake._werewolf_state.get("assembly", {})
	_expect_equal(int(assembly.get("interrogationCount", 0)), 1, "审讯计数=1")
	_expect_equal((assembly.get("interrogated", []) as Array).has("c1"), true, "c1 已登记被审")
	_expect_equal(
		(assembly.get("interrogationTargets", []) as Array).has("c1"),
		false,
		"已审者移出候选",
	)
	_expect_equal(WEREWOLF.begin_interrogation_target(fake, "p", "c1"), false, "已审者不能再审")
	# 逐字稿
	_expect_equal(WEREWOLF.record_interrogation_turn(fake, "p", "c1", 500, "昨晚你去哪了？"), true, "警察问话入逐字稿")
	_expect_equal(WEREWOLF.record_interrogation_turn(fake, "c1", "p", 501, "我一直在家。"), true, "居民回答入逐字稿")
	_expect_equal(WEREWOLF.record_interrogation_turn(fake, "c2", "c3", 502, "闲聊"), false, "平民间对话不入逐字稿")
	_expect_equal(WEREWOLF.record_interrogation_turn(fake, "p", "c1", 503, "  "), false, "空话不入逐字稿")
	var transcript: Array = fake._werewolf_state.get("assembly", {}).get("interrogationTranscript", [])
	_expect_equal(transcript.size(), 2, "逐字稿 2 条")
	_expect_equal(
		String((transcript[0] as Dictionary).get("say", "")),
		"昨晚你去哪了？",
		"逐字稿内容正确",
	)
	# 审讯次数上限
	assembly = fake._werewolf_state.get("assembly", {})
	assembly["interrogationCount"] = WEREWOLF.ASSEMBLY_INTERROGATION_MAX
	fake._werewolf_state["assembly"] = assembly
	_expect_equal(
		WEREWOLF.begin_interrogation_target(fake, "p", "c2"),
		false,
		"审讯满 %d 人后拒绝" % WEREWOLF.ASSEMBLY_INTERROGATION_MAX,
	)
	# 结束审讯
	_expect_equal(WEREWOLF.end_interrogation(fake, "c3"), "只有警察可以结束审讯", "平民不能结束审讯")
	_expect_equal(WEREWOLF.end_interrogation(fake, "p"), "", "警察结束审讯")
	_expect_equal(WEREWOLF.assembly_phase(fake), "vote", "结束审讯→投票期")
	var vote: Dictionary = fake._werewolf_state.get("vote", {})
	_expect_equal((vote.get("candidateIds", []) as Array).size(), 3, "候选=存活非警察")
	_expect_equal(WEREWOLF.submit_vote(fake, "c1", {"target_resident_id": "c2", "line": "我怀疑他"}), "", "投票登记")
	_expect_equal(
		WEREWOLF.submit_vote(fake, "c1", {"target_resident_id": "c2", "line": "改票"}),
		"你已经投过票了，一票不能改",
		"重复投票拒绝",
	)
	_expect_equal(
		WEREWOLF.submit_vote(fake, "c2", {"target_resident_id": "nobody", "line": "x"}),
		"投票目标 nobody 不在候选人名单中",
		"名单外目标拒绝",
	)
	_expect_equal(WEREWOLF.submit_vote(fake, "p", {"target_resident_id": "c1", "line": "线索指向他"}), "", "警察投票")
	_expect_equal(WEREWOLF.submit_vote(fake, "c2", {"target_resident_id": "c1", "line": "附和"}), "", "c2 投票")
	# 最后一人投完 → 立即开票(c1 3票 > c2 1票)
	var before_settle := _announcement_text(fake)
	_expect_equal(WEREWOLF.submit_vote(fake, "c3", {"target_resident_id": "c1", "line": "同意"}), "", "c3 投票(收齐)")
	_expect_equal(bool(fake.alive.get("c1", true)), false, "最高票被放逐")
	_expect_equal(
		_announcement_text(fake).contains("审讯会开票"),
		true,
		"收齐立即开票公告",
	)
	_expect_equal(WEREWOLF.assembly_phase(fake), "idle", "开票后散会")
	_expect_equal(WEREWOLF.assembly_frozen(fake), false, "散会解冻")
	_expect_equal(bool(fake._werewolf_state.get("assembly", {}).get("announced", false)), true, "announced 标记")
	_expect_equal(
		_announcement_text(fake).contains("审讯会结束，小镇时间恢复流动"),
		true,
		"散会广播",
	)
	# 动作白名单
	_verify_assembly_action_whitelist(fake)
	_expect_equal(_announcement_text(fake) != before_settle, true, "开票有公告变化")


func _verify_assembly_action_whitelist(fake: FakeWorld) -> void:
	# 重开第2天大会验证各阶段白名单(c1 已在场景1被放逐, 用存活的 c2/c3)。
	fake.absolute_minute = 2 * 1440 + 480
	WEREWOLF.start_assembly(fake, fake.absolute_minute)
	# 汇报期
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "c2", "向警察汇报"), "", "汇报期平民可汇报")
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "c2", "去"), "汇报期只能向警察汇报", "汇报期平民不可去")
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "p", "向警察汇报"), "汇报正在收集中，警察请等待", "汇报期警察等待")
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "dead1", "向警察汇报"), "你已不在镇上", "死者无动作")
	# 审讯期
	WEREWOLF.submit_report(fake, "c2", {"kind": "目击", "line": "a"})
	WEREWOLF.submit_report(fake, "c3", {"kind": "不汇报", "line": ""})
	_expect_equal(WEREWOLF.assembly_phase(fake), "interrogation", "第2天汇报收齐进审讯")
	# 审讯期 wake 裁剪: 被审者(有活跃对话)保留答话选项, 未审者/无对话清空,
	# 警察保留提问选项——否则审讯对话无法进行(被审者无答话选项)。
	var interrogated_snapshot := {
		"conversation": {"conversationId": "c1", "with": "p", "turns": [1]},
		"conversation_follow_up_options": [{"kind": "say"}],
		"life_destination_options": [{"place": "广场"}],
	}
	WEREWOLF.constrain_wake(fake, "c2", interrogated_snapshot)
	_expect_equal(
		(interrogated_snapshot.get("conversation_follow_up_options", []) as Array).size(),
		1,
		"审讯期被审者保留答话选项",
	)
	var idle_civilian_snapshot := {
		"conversation": {},
		"conversation_follow_up_options": [{"kind": "say"}],
	}
	WEREWOLF.constrain_wake(fake, "c3", idle_civilian_snapshot)
	_expect_equal(
		(idle_civilian_snapshot.get("conversation_follow_up_options", []) as Array).size(),
		0,
		"审讯期未审平民无对话选项",
	)
	var police_snapshot := {
		"conversation": {"conversationId": "c1", "with": "c2", "turns": [1]},
		"conversation_follow_up_options": [{"kind": "say"}],
	}
	WEREWOLF.constrain_wake(fake, "p", police_snapshot)
	_expect_equal(
		(police_snapshot.get("conversation_follow_up_options", []) as Array).size(),
		1,
		"审讯期警察保留对话选项",
	)
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "p", "搭话"), "", "审讯期警察搭话")
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "p", "结束审讯"), "", "审讯期警察结束")
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "p", "去"), "审讯期警察只能询问居民或结束审讯", "审讯期警察不可去")
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "c3", "答话"), "", "审讯期平民答话")
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "c3", "待着"), "", "审讯期平民待着")
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "c3", "搭话"), "审讯进行中，请等待投票开始", "审讯期平民不可搭话")
	# 投票期
	WEREWOLF.end_interrogation(fake, "p")
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "c3", "投票放逐"), "", "投票期可投票")
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "p", "搭话"), "投票期只能投票放逐", "投票期警察不可搭话")
	_expect_equal(WEREWOLF.assembly_action_allowed(fake, "c3", "待着"), "投票期只能投票放逐", "投票期不可待着")


# —— 场景2: 投票期超时兜底开票(第3天: 无人投票流会) ——

func _verify_fake_phase_timeouts() -> void:
	var fake := _make_fake_world()
	fake.absolute_minute = 3 * 1440 + 480
	WEREWOLF.start_assembly(fake, fake.absolute_minute)
	WEREWOLF.submit_report(fake, "c1", {"kind": "目击", "line": "a"})
	WEREWOLF.submit_report(fake, "c2", {"kind": "不汇报", "line": ""})
	WEREWOLF.submit_report(fake, "c3", {"kind": "怀疑", "line": "b"})
	WEREWOLF.end_interrogation(fake, "p")
	_expect_equal(WEREWOLF.assembly_phase(fake), "vote", "第3天进入投票期")
	# 投票期超时(>90s)无人投票 → 流会并散会解冻
	WEREWOLF.tick_assembly(fake, 91.0)
	_expect_equal(
		_announcement_text(fake).contains("审讯会投票流会"),
		true,
		"投票超时无人投→流会公告",
	)
	_expect_equal(WEREWOLF.assembly_phase(fake), "idle", "流会后散会")
	_expect_equal(WEREWOLF.assembly_frozen(fake), false, "流会后解冻")


# —— 场景3: 真实世界集成(手动驱动: 触发/冻结/桥接/立即开票/解冻) ——
# 真实世界开局时间与 agent 决策时序不可控, 故全部手动驱动(start_assembly/
# submit_report/end_interrogation/submit_vote 直调), 只验证世界层集成:
# 冻结(advance 短路)、桥接钩子、wake snapshot 注入、收齐立即开票、解冻恢复。

func _verify_real_world_assembly() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "assembly real world opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_inject_undercover_stub(world, UNDERCOVER_IDS[0])
	var police_id := _inject_police_stub(world)
	_expect_equal(police_id.is_empty(), false, "找到可注入的警察居民")
	if police_id.is_empty():
		world.call("stop")
		return
	var civilians := _alive_civilian_ids(world, police_id)
	_expect_equal(civilians.size() >= 2, true, "有足够平民居民 (%d)" % civilians.size())
	# 手动开启第1天审讯会
	WEREWOLF.start_assembly(world, 1440 + 480)
	_expect_equal(WEREWOLF.assembly_phase(world), "report", "手动开会进入汇报期")
	_expect_equal(WEREWOLF.assembly_frozen(world), true, "真实世界大会冻结")
	# 冻结: advance 不再推进分钟
	var env: Object = world.get("_environment")
	var minute_before := int(env.call("get_absolute_minute"))
	var frozen_result := world.call("advance", 30.0) as Dictionary
	_expect_equal(frozen_result.get("ok"), true, "冻结期间 advance 仍返回 ok")
	_expect_equal(frozen_result.get("frozen"), true, "advance 返回 frozen 标记")
	_expect_equal(int(frozen_result.get("minutesAdvanced", -1)), 0, "冻结期间分钟不推进")
	_expect_equal(int(env.call("get_absolute_minute")), minute_before, "冻结后环境分钟不变")
	# wake snapshot 注入: 汇报期居民(提示+kinds)
	var civilian_snap: Dictionary = WEREWOLF.assembly_wake_snapshot(world, civilians[0])
	_expect_equal(String(civilian_snap.get("phase", "")), "report", "居民 snapshot 汇报期")
	_expect_equal(civilian_snap.get("frozen"), true, "居民 snapshot 标注冻结")
	_expect_equal(
		(civilian_snap.get("kinds", []) as Array).size(),
		4,
		"居民 snapshot 含 4 种汇报类型",
	)
	# constrain_wake: 大会期间裁剪日常选项
	var probe_snapshot := {
		"life_destination_options": [{"place": "广场"}],
		"conflict_tension_options": [{"kind": "攻击"}],
		"work_tasks": [{"taskId": "t1"}],
		"conversation": {"conversationId": "c1"},
		"conversation_follow_up_options": [{"kind": "say"}],
		"nearby": [{"resident_id": "r1"}],
	}
	WEREWOLF.constrain_wake(world, civilians[0], probe_snapshot)
	_expect_equal(
		(probe_snapshot.get("life_destination_options", []) as Array).size(),
		0,
		"constrain_wake 清空出行选项",
	)
	_expect_equal(
		(probe_snapshot.get("conflict_tension_options", []) as Array).size(),
		0,
		"constrain_wake 清空冲突选项",
	)
	# 汇报收齐 → 审讯期
	for index: int in civilians.size():
		var kind: String = ["目击", "听到", "怀疑", "不汇报"][index % 4]
		var line := "" if kind == "不汇报" else "第 %d 条线索" % index
		_expect_equal(
			WEREWOLF.submit_report(world, civilians[index], {"kind": kind, "line": line}),
			"",
			"%s 汇报成功" % civilians[index],
		)
	_expect_equal(WEREWOLF.assembly_phase(world), "interrogation", "真实世界汇报收齐进审讯")
	# 桥接层: 对话钩子(对话引擎 → world → WEREWOLF_RUNTIME)
	var bridge_started: bool = world.call(
		"_record_assembly_interrogation_started",
		police_id,
		civilians[0],
	)
	_expect_equal(bridge_started, true, "桥接审讯登记成功")
	_expect_equal(
		int((world.get("_werewolf_state") as Dictionary).get("assembly", {}).get("interrogationCount", 0)),
		1,
		"桥接后审讯计数=1",
	)
	var bridge_turn: bool = world.call(
		"_record_assembly_interrogation_turn",
		police_id,
		civilians[0],
		"你昨晚在哪里？",
	)
	_expect_equal(bridge_turn, true, "桥接逐字稿记录成功")
	var transcript: Array = (world.get("_werewolf_state") as Dictionary).get(
		"assembly", {},
	).get("interrogationTranscript", [])
	_expect_equal(transcript.size(), 1, "真实世界逐字稿 1 条")
	# 警察 wake snapshot 注入(汇报汇总)
	var police_snap: Dictionary = WEREWOLF.assembly_wake_snapshot(world, police_id)
	_expect_equal(String(police_snap.get("phase", "")), "interrogation", "警察 snapshot 审讯期")
	_expect_equal(String(police_snap.get("role", "")), "police", "警察 snapshot role=police")
	_expect_equal(
		(police_snap.get("reportSummary", []) as Array).size(),
		civilians.size(),
		"警察 snapshot 含全部汇报汇总",
	)
	# 警察结束审讯 → 投票期
	_expect_equal(WEREWOLF.end_interrogation(world, police_id), "", "真实世界警察结束审讯")
	_expect_equal(WEREWOLF.assembly_phase(world), "vote", "真实世界进入投票期")
	# 全员投票(全部投 civilians[1]) → 收齐立即开票散会
	var target_id := civilians[1]
	var voters: Array[String] = [police_id]
	voters.append_array(civilians)
	for voter: String in voters:
		var vote_error := WEREWOLF.submit_vote(world, voter, {
			"target_resident_id": target_id,
			"line": "根据审讯记录放逐他。",
		})
		_expect_equal(vote_error, "", "%s 投票成功" % voter)
	_expect_equal(WEREWOLF.assembly_phase(world), "idle", "真实世界全员投完立即散会")
	_expect_equal(WEREWOLF.assembly_frozen(world), false, "真实世界散会解冻")
	_expect_equal(
		(world.call("get_announcements") as Array).size() > 0,
		true,
		"真实世界有开票公告",
	)
	# 解冻后 advance 恢复推进
	var minute_after_settle := int(env.call("get_absolute_minute"))
	var resumed := world.call("advance", 30.0) as Dictionary
	_expect_equal(resumed.get("frozen") != true, true, "解冻后不再冻结")
	_expect_equal(int(resumed.get("minutesAdvanced", 0)) > 0, true, "解冻后分钟恢复推进")
	_expect_equal(int(env.call("get_absolute_minute")) > minute_after_settle, true, "解冻后环境分钟前进")
	world.call("stop")


# —— 辅助 ——

func _make_fake_world() -> FakeWorld:
	var fake := FakeWorld.new()
	fake._werewolf_state = WEREWOLF.default_state()
	fake._resident_order = ["p", "c1", "c2", "c3"]
	fake._residents = {"u1": {}}
	fake.undercover_ids = ["u1"]
	fake.police_ids = ["p"]
	fake.alive = {"p": true, "c1": true, "c2": true, "c3": true, "u1": false}
	fake.absolute_minute = 1440 + 480
	return fake


func _announcement_text(fake: FakeWorld) -> String:
	return " || ".join(
		PackedStringArray(fake.announcements.map(func(s: Variant) -> String: return String(s)))
	)


func _inject_police_stub(world: RefCounted) -> String:
	var residents: Dictionary = world.call("residents")
	for key_value: Variant in residents.keys():
		var resident_id := String(key_value)
		if resident_id.is_empty():
			continue
		if not world.call("_resident_is_alive", resident_id):
			continue
		var registry: Object = world.get("resident_registry")
		var records: Dictionary = registry.get("records")
		var record := records.get(resident_id, {}) as Dictionary
		record["socialState"] = {"job": "警察"}
		return resident_id
	return ""


func _alive_civilian_ids(world: RefCounted, police_id: String) -> Array[String]:
	var civilians: Array[String] = []
	var residents: Dictionary = world.call("residents")
	for key_value: Variant in residents.keys():
		var resident_id := String(key_value)
		if resident_id.is_empty() or resident_id == police_id:
			continue
		if world.call("_resident_is_alive", resident_id):
			civilians.append(resident_id)
	return civilians


## 只把卧底 id 塞进 world._residents(fixture 世界没有卧底居民):
## 满足 feature_active 的"世界存在卧底"判定。
func _inject_undercover_stub(world: RefCounted, undercover_id: String) -> void:
	var residents := world.call("residents") as Dictionary
	residents[undercover_id] = {
		"residentId": undercover_id,
		"arrivalState": {"status": "arrived"},
	}


## 推进到下一个指定 minute_of_day(跨天自动加 1440);realSecondsPerGameMinute=1。
func _advance_to_minute_of_day(world: RefCounted, target_minute: int) -> void:
	var env: Object = world.get("_environment")
	var current := int(env.call("get_absolute_minute"))
	var minute_of_day := posmod(current, 1440)
	var delta := target_minute - minute_of_day
	if delta <= 0:
		delta += 1440
	var result := world.call("advance", float(delta)) as Dictionary
	_expect_equal(result.get("ok"), true, "advance %d 分钟 ok" % delta)


## 警察审讯会状态机桩世界: 实现 TWR assembly 状态机调用面。
class FakeWorld:
	extends RefCounted
	var _running := true
	var _werewolf_state: Dictionary = {}
	var _resident_order: Array[String] = []
	var _residents: Dictionary = {}
	var undercover_ids: Array[String] = []
	var police_ids: Array[String] = []
	var alive: Dictionary = {}
	var announcements: Array[String] = []
	var absolute_minute := 1440 + 480

	func _resident_is_alive(resident_id: String) -> bool:
		return bool(alive.get(resident_id, false))

	func _resident_is_police(resident_id: String) -> bool:
		return police_ids.has(resident_id)

	func _undercover_resident_ids() -> Array[String]:
		return undercover_ids

	func _resident_display_name(resident_id: String) -> String:
		return resident_id

	func _time_label() -> String:
		return "桩世界"

	func _authoritative_absolute_minute() -> int:
		return absolute_minute

	func broadcast_announcement(text: String) -> Dictionary:
		announcements.append(text)
		return {"ok": true}

	func get_announcements() -> Array:
		return announcements

	func _schedule_decision(
		_resident_id: String,
		_urgent := false,
		_a := false,
		_b := false,
		_c := false,
		_d := false,
	) -> void:
		pass

	func confirm_resident_death(resident_id: String, _reason: String) -> Dictionary:
		alive[resident_id] = false
		announcements.append("%s 被放逐出镇" % resident_id)
		return {"ok": true}
