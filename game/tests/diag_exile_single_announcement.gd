extends "res://tests/support/TownWorldTestCase.gd"
## diag_exile_single_announcement.gd — 放逐只保留一条公告(修复①验证)
## 1) 放逐:开票广播(town_bell)后不再补发 board 死亡公告 → 公告数恰 +1
## 2) 放逐语义不回退:被放逐者 lifecycle=dead / 投票回合清空 / 卧底仍在 → 游戏未结束
## 3) 对照:普通死亡(非放逐)仍即时发 board 死亡公告 → 屏蔽未误伤
## 运行: Godot --headless --path game --script res://tests/diag_exile_single_announcement.gd

const WEREWOLF := preload("res://world/runtime/TownWerewolfRuntime.gd")

const CIVILIAN_ID := "resident_lin_lan_01"


func _initialize() -> void:
	print("===== 放逐单公告验证 =====")
	_verify_exile_single_announcement()
	_verify_normal_death_still_announced()
	_finish_suite("EXILE_SINGLE_ANNOUNCEMENT_PASS")


# 场景1: 放逐只发 1 条(放逐公告),不补发死亡公告
func _verify_exile_single_announcement() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "exile single announcement opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_inject_undercover_stub(world, "resident_xie_mian_01")
	_advance_to_minute_of_day(world, 480)  # 08:00
	var current_day := int(world.get("_environment").call("get_absolute_minute")) / 1440
	if current_day < 1:
		_advance_to_minute_of_day(world, 480)
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
	var before: Array = world.get_announcements() as Array
	var before_count: int = before.size()
	_advance_to_minute_of_day(world, 750)  # 12:30 开票
	var after: Array = world.get_announcements() as Array
	# 关键断言:放逐后公告数恰 +1(只有 town_bell 放逐公告,无 board 死亡公告)
	_expect_equal(
		after.size() - before_count,
		1,
		"放逐公告数恰 +1 (修复前为 +2: 放逐公告+死亡公告)",
	)
	# 新公告副本 = 放逐公告(town_bell),而非死亡公告(board)
	var newcomers: Array = after.slice(before_count)
	_expect_equal(newcomers.size(), 1, "新增恰好 1 条公告")
	if newcomers.size() >= 1:
		var newcomer: Dictionary = newcomers[0] as Dictionary
		var text := String(newcomer.get("text", ""))
		var mode := String(newcomer.get("delivery_mode", ""))
		_expect_equal(mode, "town_bell", "放逐公告走 town_bell 广播")
		_expect_equal(text.contains("放逐出镇"), true, "公告为放逐开票文案 (%s)" % text)
		_expect_equal(text.contains("死亡"), false, "公告无死亡字样 (%s)" % text)
	# 放逐语义不回退
	var lifecycle := world.call(
		"get_resident_lifecycle_state",
		CIVILIAN_ID,
	) as Dictionary
	_expect_equal(
		String(lifecycle.get("status", "")),
		"dead",
		"被放逐者 lifecycle=dead (死因:%s)"
		% String(lifecycle.get("deathEvent", {}).get("reason", "")),
	)
	var settled: Dictionary = (world.get("_werewolf_state") as Dictionary).get(
		"vote",
		{},
	) as Dictionary
	_expect_equal(settled.is_empty(), true, "开票后投票回合清空")
	var game_over: bool = bool(
		(world.get("_werewolf_state") as Dictionary).get("gameOver", false)
	)
	_expect_equal(game_over, false, "卧底仍在 → 游戏未结束 (check_victory 未误触)")
	world.call("stop")


# 场景2: 对照 — 普通死亡(非放逐)仍即时发 board 死亡公告
func _verify_normal_death_still_announced() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "normal death still announced opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_inject_undercover_stub(world, "resident_xie_mian_01")
	_advance_to_minute_of_day(world, 540)  # 09:00(白天,非夜间 → 不 defer)
	var before_count: int = (world.get_announcements() as Array).size()
	var result := world.call(
		"confirm_resident_death",
		CIVILIAN_ID,
		"被谢眠暗杀",
	) as Dictionary
	_expect_equal(result.get("ok"), true, "普通死亡确认 ok")
	var after: Array = world.get_announcements() as Array
	_expect_equal(
		after.size() - before_count,
		1,
		"普通死亡仍即时发公告 +1",
	)
	if after.size() - before_count >= 1:
		var newcomer: Dictionary = after[before_count] as Dictionary
		var mode := String(newcomer.get("delivery_mode", ""))
		var text := String(newcomer.get("text", ""))
		_expect_equal(mode, "board", "普通死亡公告走 board 发布")
		_expect_equal(text.contains("死亡"), true, "死亡公告含死亡字样 (%s)" % text)
	world.call("stop")


# --- 辅助(与 diag_werewolf_vote.gd 一致) ---

## 注入一个"真实存活"的卧底居民:registry records + lifecycle(alive) +
## resident_order 三处齐全,避免 check_victory 把它当成已死而误判"卧底全灭
## → 镇民胜"并额外广播胜负公告,污染放逐公告计数。
func _inject_undercover_stub(world: RefCounted, undercover_id: String) -> void:
	var residents := world.call("residents") as Dictionary
	if residents.has(undercover_id):
		return
	var source := residents.get(CIVILIAN_ID, {}) as Dictionary
	var home_anchor: Dictionary = {}
	var lifecycle: Object = world.get("_resident_lifecycle")
	if not source.is_empty():
		var source_state: Dictionary = lifecycle.call(
			"get_resident_state",
			CIVILIAN_ID,
		)
		home_anchor = (
			source_state.get("homeAnchor", {}) as Dictionary
		).duplicate(true)
	var resident := {
		"residentId": undercover_id,
		"attributes": {
			"name": "卧底测试员",
			"gender": "男",
			"age": 30,
			"desire": "测试用",
			"personality": "测试用",
			"speech": "测试用",
			"interests": [],
			"customInterests": [],
		},
		"profileAttributes": {"name": "卧底测试员"},
		"socialState": {
			"job": "无业",
			"home": "镇公所",
			"workplace": "镇公所",
			"money": 0,
			"reputation": 0,
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
	residents[undercover_id] = resident
	var initialized := lifecycle.call(
		"initialize_resident",
		undercover_id,
		"卧底测试员",
		home_anchor,
	) as Dictionary
	_expect_equal(initialized.get("ok"), true, "%s 注入生命周期" % undercover_id)
	var order := world.resident_order() as Array
	if not order.has(undercover_id):
		order.append(undercover_id)


## 推进到下一个指定 minute_of_day(跨天自动加 1440)
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