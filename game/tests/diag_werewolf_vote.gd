extends "res://tests/support/TownWorldTestCase.gd"
## diag_werewolf_vote.gd — 狼人杀化 MVP 验证
## 1) is_night 昼夜窗口
## 2) 夜间暗杀死亡不即时公告,08:00 天亮统一公布
## 3) 8:00 镇民大会投票回合 / 手动投票 / 12:30 开票放逐最高票
## 4) 契约层:exile_vote 字段白名单/校验/canonicalize
## 5) 胜负判定:卧底全灭 → 镇民胜
## 6) 存档快照含 werewolfState
## 运行: Godot --headless --path game --script res://tests/diag_werewolf_vote.gd

const WEREWOLF := preload("res://world/runtime/TownWerewolfRuntime.gd")
const CONTRACT := preload("res://agent/AgentContract.gd")
const CONTRACT_SNAPSHOT := preload("res://agent/contract/AgentContractSnapshot.gd")
const ACTION_VALIDATION := preload("res://world/runtime/action/TownActionValidation.gd")

const CIVILIAN_ID := "resident_lin_lan_01"
const UNDERCOVER_IDS: Array[String] = [
	"resident_xie_mian_01",
	"resident_qiao_yiming_01",
	"resident_hanako_01",
]


func _initialize() -> void:
	print("===== 狼人杀化 MVP 验证 =====")
	_verify_night_window()
	_verify_night_death_deferred()
	_verify_feature_inactive_without_undercover()
	_verify_vote_round()
	_verify_settle_skipped_after_game_over()
	_verify_contract()
	_verify_victory()
	_verify_save_snapshot()
	_finish_suite("WEREWOLF_VOTE_PASS")


# 场景1: 昼夜窗口判定
func _verify_night_window() -> void:
	_expect_equal(WEREWOLF.is_night(1260), true, "21:00 是夜间")
	_expect_equal(WEREWOLF.is_night(1199), false, "19:59 不是夜间")
	_expect_equal(WEREWOLF.is_night(479), true, "07:59 是夜间")
	_expect_equal(WEREWOLF.is_night(480), false, "08:00 不是夜间")
	_expect_equal(WEREWOLF.is_night(720), false, "12:00 不是夜间")


# 场景2: 夜间暗杀 → 入队;推进到 08:00 → 公布
func _verify_night_death_deferred() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "werewolf night defer opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_inject_undercover_stub(world, UNDERCOVER_IDS[0])
	_advance_to_minute_of_day(world, 1260)  # 21:00
	var announcements_before: int = (world.get_announcements() as Array).size()
	var result := world.call(
		"confirm_resident_death",
		CIVILIAN_ID,
		"被谢眠暗杀",
	) as Dictionary
	_expect_equal(result.get("ok"), true, "夜间暗杀死亡确认 ok")
	var state: Dictionary = world.get("_werewolf_state") as Dictionary
	var queue: Array = state.get("pendingDeathAnnouncements", []) as Array
	_expect_equal(queue.size(), 1, "夜间暗杀死亡进入待公布队列")
	var announcements_after_death: int = (world.get_announcements() as Array).size()
	_expect_equal(
		announcements_after_death,
		announcements_before,
		"夜间死亡不即时发公告",
	)
	_expect_equal(
		bool(state.get("gameOver", false)),
		true,
		"夜间死亡当夜即锁定胜负状态",
	)
	_expect_equal(
		bool(state.get("winnerAnnounced", false)),
		false,
		"夜间终局胜负公告压到天亮",
	)
	_advance_to_minute_of_day(world, 480)  # 次日 08:00
	var state_dawn: Dictionary = world.get("_werewolf_state") as Dictionary
	var queue_dawn: Array = state_dawn.get("pendingDeathAnnouncements", []) as Array
	_expect_equal(queue_dawn.size(), 0, "天亮后队列清空")
	var announcements_dawn: int = (world.get_announcements() as Array).size()
	_expect_equal(
		announcements_dawn > announcements_after_death,
		true,
		"天亮后公布死讯 (公告 %d → %d)" % [announcements_after_death, announcements_dawn],
	)
	_expect_equal(
		bool(state_dawn.get("winnerAnnounced", false)),
		true,
		"天亮后补发胜负公告",
	)
	world.call("stop")


# 场景3: 无卧底居民的世界 → 狼人杀特性整体停用
func _verify_feature_inactive_without_undercover() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "werewolf feature inactive opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	# 无卧底世界推到第1天 8:00 也不开会
	_advance_to_minute_of_day(world, 480)
	var current_day := int(world.get("_environment").call("get_absolute_minute")) / 1440
	if current_day < 1:
		_advance_to_minute_of_day(world, 480)
	_expect_equal(
		((world.get("_werewolf_state") as Dictionary).get("vote", {}) as Dictionary).is_empty(),
		true,
		"无卧底世界不开启镇民大会",
	)
	# 无卧底世界夜间"暗杀"死亡保持原即时公告语义
	_advance_to_minute_of_day(world, 1260)
	var announcements_before: int = (world.get_announcements() as Array).size()
	var result := world.call(
		"confirm_resident_death",
		CIVILIAN_ID,
		"被谢眠暗杀",
	) as Dictionary
	_expect_equal(result.get("ok"), true, "无卧底世界死亡确认 ok")
	_expect_equal(
		((world.get("_werewolf_state") as Dictionary).get("pendingDeathAnnouncements", []) as Array).size(),
		0,
		"无卧底世界死亡不入夜间待公布队列",
	)
	_expect_equal(
		(world.get_announcements() as Array).size() > announcements_before,
		true,
		"无卧底世界死亡即时公告",
	)
	world.call("stop")


# 场景4: 镇民大会投票 → 开票放逐
func _verify_vote_round() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "werewolf vote round opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_inject_undercover_stub(world, UNDERCOVER_IDS[0])
	_advance_to_minute_of_day(world, 480)  # 08:00
	# 第0天(开局日)不开镇民大会,推到第1天 8:00
	var current_day := int(world.get("_environment").call("get_absolute_minute")) / 1440
	if current_day < 1:
		_advance_to_minute_of_day(world, 480)
	var state: Dictionary = world.get("_werewolf_state") as Dictionary
	var vote: Dictionary = state.get("vote", {}) as Dictionary
	var day := int(world.get("_environment").call("get_absolute_minute")) / 1440
	_expect_equal(int(vote.get("day", -1)), day, "投票回合开启 (day=%d)" % day)
	var candidates: Array = vote.get("candidateIds", []) as Array
	_expect_equal(candidates.size() >= 3, true, "候选人名单非空 (%d人)" % candidates.size())
	_expect_equal(candidates.has(CIVILIAN_ID), true, "林岚在候选人名单中")
	# 3 票投林岚,1 票投唐小满 → 林岚被放逐
	var voters := _alive_voter_ids(world, [CIVILIAN_ID], 4)
	_expect_equal(voters.size() >= 4, true, "有足够在世投票人 (%d)" % voters.size())
	if voters.size() < 4:
		world.call("stop")
		return
	for index: int in voters.size():
		var ballot := {
			"target_resident_id": (
				CIVILIAN_ID if index < 3 else "resident_tang_xiaoman_01"
			),
			"line": "案发那晚他的行踪说不清。",
		}
		WEREWOLF.submit_vote(world, voters[index], ballot)
	var votes: Dictionary = (world.get("_werewolf_state") as Dictionary).get(
		"vote",
		{},
	) as Dictionary
	_expect_equal(
		(votes.get("votes", {}) as Dictionary).size(),
		voters.size(),
		"选票全部登记",
	)
	_advance_to_minute_of_day(world, 750)  # 12:30 开票
	var lifecycle := world.call(
		"get_resident_lifecycle_state",
		CIVILIAN_ID,
	) as Dictionary
	_expect_equal(
		String(lifecycle.get("status", "")),
		"dead",
		"最高票者被放逐 (死因:%s)" % String(lifecycle.get("deathEvent", {}).get("reason", "")),
	)
	var settled: Dictionary = (world.get("_werewolf_state") as Dictionary).get(
		"vote",
		{},
	) as Dictionary
	_expect_equal(settled.is_empty(), true, "开票后投票回合清空")
	world.call("stop")


# 场景5: 终局后 12:30 不再开票(阻止终局后额外放逐)
func _verify_settle_skipped_after_game_over() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "werewolf settle after game over opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_inject_undercover_stub(world, UNDERCOVER_IDS[0])
	_advance_to_minute_of_day(world, 480)  # 08:00
	var current_day := int(world.get("_environment").call("get_absolute_minute")) / 1440
	if current_day < 1:
		_advance_to_minute_of_day(world, 480)
	var vote: Dictionary = (world.get("_werewolf_state") as Dictionary).get(
		"vote",
		{},
	) as Dictionary
	_expect_equal(vote.is_empty(), false, "终局场景投票回合已开启")
	var voters := _alive_voter_ids(world, [CIVILIAN_ID], 1)
	_expect_equal(voters.size() >= 1, true, "终局场景有投票人")
	if voters.size() < 1:
		world.call("stop")
		return
	WEREWOLF.submit_vote(world, voters[0], {
		"target_resident_id": CIVILIAN_ID,
		"line": "开票前胜负已分。",
	})
	var state: Dictionary = world.get("_werewolf_state") as Dictionary
	state["gameOver"] = true
	state["winner"] = "镇民"
	state["winnerAnnounced"] = true
	_advance_to_minute_of_day(world, 750)  # 12:30 开票(应被跳过)
	var lifecycle := world.call(
		"get_resident_lifecycle_state",
		CIVILIAN_ID,
	) as Dictionary
	_expect_equal(
		String(lifecycle.get("status", "")),
		"alive",
		"胜负已定后 12:30 不再放逐最高票者",
	)
	_expect_equal(
		((world.get("_werewolf_state") as Dictionary).get("vote", {}) as Dictionary).is_empty(),
		true,
		"终局后开票时投票回合被作废",
	)
	world.call("stop")


# 场景6: 契约层 — 决策字段白名单 + exile_vote 校验 + canonicalize
func _verify_contract() -> void:
	var decision := {
		"decision_id": "d1",
		"handling": "continue_current",
		"exile_vote": {
			"target_resident_id": "resident_lin_lan_01",
			"line": "我怀疑他。",
		},
	}
	var shape_error := ACTION_VALIDATION.validate_decision_shape(decision)
	_expect_equal(shape_error, "", "决策形状校验接受 exile_vote (%s)" % shape_error)
	var bad_decision := decision.duplicate(true)
	bad_decision["vote_x"] = {}
	var bad_error := ACTION_VALIDATION.validate_decision_shape(bad_decision)
	_expect_equal(
		String(bad_error).contains("未知字段"),
		true,
		"未知字段仍被拒绝 (%s)" % bad_error,
	)
	var wake := {
		"snapshot": {
			"exile_vote": {
				"round_day": 1,
				"settle_clock": "12:30",
				"candidate_ids": ["resident_lin_lan_01", "resident_tang_xiaoman_01"],
			},
		},
	}
	var errors: Array[String] = []
	CONTRACT_SNAPSHOT._validate_exile_vote(
		{
			"target_resident_id": "resident_lin_lan_01",
			"line": "我怀疑他。",
		},
		wake,
		errors,
	)
	_expect_equal(errors.is_empty(), true, "合法 exile_vote 通过校验 (%s)" % str(errors))
	errors = []
	CONTRACT_SNAPSHOT._validate_exile_vote(
		{
			"target_resident_id": "不存在的人",
			"line": "我怀疑他。",
		},
		wake,
		errors,
	)
	_expect_equal(errors.is_empty(), false, "候选人之外的投票被拒绝")
	errors = []
	CONTRACT_SNAPSHOT._validate_exile_vote(
		{
			"target_resident_id": "resident_lin_lan_01",
			"line": "我怀疑他。",
		},
		{"snapshot": {}},
		errors,
	)
	_expect_equal(errors.is_empty(), false, "无投票回合时提交 exile_vote 被拒绝")
	var canonical := CONTRACT.canonicalize_decision({
		"decision_id": "d1",
		"handling": "continue_current",
		"exile_vote": {
			"target_resident_id": "resident_lin_lan_01",
			"line": "我怀疑他。",
			"extra_field": "应被剥离",
		},
	})
	var canonical_vote: Dictionary = canonical.get("exile_vote", {}) as Dictionary
	_expect_equal(canonical_vote.has("extra_field"), false, "canonicalize 剥离多余字段")
	_expect_equal(
		String(canonical_vote.get("target_resident_id", "")),
		"resident_lin_lan_01",
		"canonicalize 保留合法字段",
	)


# 场景7: 胜负判定 — 用桩世界单元验证(fixture 无卧底居民)
func _verify_victory() -> void:
	var fake := FakeWorld.new()
	fake.undercover_ids = ["u_xie", "u_qiao"]
	fake.alive = {"u_xie": true, "u_qiao": true, "c1": true, "c2": true, "c3": true}
	fake._resident_order = ["u_xie", "u_qiao", "c1", "c2", "c3"]
	fake._residents = {"u_xie": {}, "u_qiao": {}}
	_expect_equal(WEREWOLF.check_victory(fake), false, "双方都在时未分胜负")
	fake.alive["u_xie"] = false
	_expect_equal(WEREWOLF.check_victory(fake), false, "还剩一个卧底未分胜负")
	fake.alive["u_qiao"] = false
	_expect_equal(WEREWOLF.check_victory(fake), true, "卧底全灭 → 镇民胜")
	_expect_equal(String(fake._werewolf_state.get("winner", "")), "镇民", "winner=镇民")
	# 卧底胜:平民数 ≤ 卧底数(屠边)
	var fake2 := FakeWorld.new()
	fake2.undercover_ids = ["u_xie", "u_qiao"]
	fake2.alive = {"u_xie": true, "u_qiao": true, "c1": true, "c2": true, "c3": false}
	fake2._resident_order = ["u_xie", "u_qiao", "c1", "c2", "c3"]
	fake2._residents = {"u_xie": {}, "u_qiao": {}}
	fake2.alive["c2"] = false
	_expect_equal(WEREWOLF.check_victory(fake2), true, "平民1≤卧底2 → 卧底胜")
	_expect_equal(String(fake2._werewolf_state.get("winner", "")), "卧底", "winner=卧底")
	# 无卧底居民的世界不激活胜负判定
	var fake3 := FakeWorld.new()
	fake3.undercover_ids = ["u_xie"]
	fake3.alive = {"c1": true, "c2": true}
	fake3._resident_order = ["c1", "c2"]
	fake3._residents = {}
	_expect_equal(WEREWOLF.check_victory(fake3), false, "无卧底居民不判胜负")
	_expect_equal(fake3.announcements.is_empty(), true, "无卧底居民不发胜负公告")


# 场景8: 存档快照含 werewolfState
func _verify_save_snapshot() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "werewolf save opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	var snapshot := world.call("create_save_snapshot") as Dictionary
	_expect_equal(snapshot.get("ok"), true, "存档快照创建 ok")
	var state: Dictionary = (
		snapshot.get("snapshot", {}) as Dictionary
	).get("state", {}) as Dictionary
	_expect_equal(state.has("werewolfState"), true, "存档 state 含 werewolfState")
	world.call("stop")


# --- 辅助 ---

## 只把卧底 id 塞进 world._residents(fixture 世界没有卧底居民):
## 满足 feature_active 的"世界存在卧底"判定;不进 _resident_order/生命周期,
## 因此不影响候选人名单与胜负计数之外的旧断言。
func _inject_undercover_stub(world: RefCounted, undercover_id: String) -> void:
	var residents := world.call("residents") as Dictionary
	residents[undercover_id] = {
		"residentId": undercover_id,
		"arrivalState": {"status": "arrived"},
	}


## 推进到下一个指定 minute_of_day(跨天自动加 1440)
## 默认时间换算 realSecondsPerGameMinute=1:advance(N) 即推进 N 游戏分钟。
func _advance_to_minute_of_day(world: RefCounted, target_minute: int) -> void:
	var env: Object = world.get("_environment")
	var current := int(env.call("get_absolute_minute"))
	var minute_of_day := posmod(current, 1440)
	var delta := target_minute - minute_of_day
	if delta <= 0:
		delta += 1440
	var result := world.call("advance", float(delta)) as Dictionary
	_expect_equal(result.get("ok"), true, "advance %d 分钟 ok" % delta)


## 取 n 个在世且不在排除名单中的投票人
func _alive_voter_ids(world: RefCounted, exclude: Array[String], count: int) -> Array[String]:
	var voters: Array[String] = []
	var residents: Dictionary = world.call("residents")
	for resident_key_value: Variant in residents.keys():
		var resident_id := String(resident_key_value)
		if resident_id.is_empty() or exclude.has(resident_id):
			continue
		if not world.call("_resident_is_alive", resident_id):
			continue
		voters.append(resident_id)
		if voters.size() >= count:
			break
	return voters


## 胜负判定的桩世界:只实现 check_victory 用到的接口
class FakeWorld:
	extends RefCounted
	const SYSTEM_BULLETIN_PUBLISHER_ID := "world"
	var _running := true
	var _werewolf_state: Dictionary = {}
	var _resident_order: Array[String] = []
	var _residents: Dictionary = {}
	var undercover_ids: Array[String] = []
	var alive: Dictionary = {}
	var announcements: Array[String] = []

	func _init() -> void:
		_werewolf_state = {
			"pendingDeathAnnouncements": [],
			"vote": {},
			"gameOver": false,
			"winner": "",
			"winnerAnnounced": false,
		}

	func _resident_is_alive(resident_id: String) -> bool:
		return bool(alive.get(resident_id, false))

	func _undercover_resident_ids() -> Array[String]:
		return undercover_ids

	func _resident_display_name(resident_id: String) -> String:
		return resident_id

	func _time_label() -> String:
		return "桩世界"

	func _publish_community_announcement(
		_publisher: String,
		text: String,
		_matter: String,
		_mode: String,
	) -> Dictionary:
		announcements.append(text)
		return {"ok": true}

	func broadcast_announcement(text: String) -> Dictionary:
		announcements.append(text)
		return {"ok": true}

	func get_announcements() -> Array:
		return []

	func _schedule_decision(_resident_id: String, _urgent: bool) -> void:
		pass
