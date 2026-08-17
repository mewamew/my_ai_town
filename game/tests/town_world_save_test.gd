extends "res://tests/support/TownWorldTestCase.gd"
## 存档与恢复合并套件。
##
## 由五个原独立测试合并而来，断言逐条保留：
## - town_world_save_restore_test.gd            → _scenario_save_restore
## - town_world_save_roundtrip_equivalence_test.gd → _scenario_roundtrip_equivalence
## - town_world_restore_corruption_test.gd      → _scenario_restore_corruption
## - town_world_activity_save_roundtrip_test.gd → _scenario_activity_save_roundtrip
## - town_world_save_participant_test.gd        → _scenario_save_participant
##
## 世界构建、唤醒取用、决定构造与断言收尾统一由 TownWorldTestCase 提供。

const SAVE_CODEC := preload("res://world/runtime/persistence/TownWorldSaveCodec.gd")
const FORMAL_OPENING := preload("res://tests/support/TownWorldFormalOpeningTestHelper.gd")

## 往返等价的允许变化字段清单（state 内的斜杠路径；* 匹配单层任意键）。
## mode：increment（必须严格递增）/ cleared（必须为空）/ reset（恢复流程有意重排，
## 类型不变）。清单外的任何字段漂移都判失败。
const ALLOWED_CHANGES := {
	"sequences/worldRevision": "increment",
}

var _restore_events: Array[Dictionary] = []


func _initialize() -> void:
	_scenario_save_restore()
	_scenario_roundtrip_equivalence()
	_scenario_restore_corruption()
	_scenario_activity_save_roundtrip()
	_scenario_save_participant()
	_finish_suite("TOWN_WORLD_SAVE_PASS")


func _on_world_restored(summary: Dictionary) -> void:
	_restore_events.append(summary.duplicate(true))


# —— 场景一：存档与恢复保真 ——

func _scenario_save_restore() -> void:
	_restore_events.clear()
	var data := _build_data()
	var opening := _garden_opening(data, "save test opening remains legal")

	var world: RefCounted = WORLD.new()
	world.connect("world_restored", _on_world_restored)
	_expect_equal(world.call("start", data, opening).get("ok"), true, "world starts before save")
	var lin_initial := _take_wake(world, "林岚")
	var tang_initial := _take_wake(world, "唐小满")
	var ahe_initial := _take_wake(world, "阿禾")
	_expect_equal(lin_initial.size(), 5, "new-game wake uses the exact interface envelope")
	_expect_equal(ahe_initial.size(), 5, "all new-game wakes use the exact interface envelope")

	var lin_action_result := world.call("submit_agent_decision", "林岚", _go(lin_initial, "社区花园")) as Dictionary
	_expect_equal(
		lin_action_result.get("status"),
		"accepted",
		"resident begins a movement that must survive save (%s)" % str(lin_action_result),
	)
	world.call("advance", 1.0)
	_expect_equal(
		world.call("submit_agent_decision", "唐小满", _talk(tang_initial, "阿禾", "林岚朝唐小满点了点头")).get("status"),
		"accepted",
		"active conversation begins before save",
	)
	_expect_equal((world.call("get_active_conversations") as Array).size(), 1, "one active conversation exists before save")
	_expect_equal(world.call("set_weather", "小雨").get("changed"), true, "weather changes before save")
	_expect_equal(world.call("publish_announcement", "存档后仍然保留。").get("ok"), true, "announcement exists before save")
	for resident_id: String in world.call("get_resident_ids") as Array[String]:
		_expect_equal(
			(world.call("announcement_knowledge_for", resident_id) as Array).size(),
			1,
			"indoor, outdoor, moving and conversing residents all know the announcement",
		)
	_expect_equal(
		(world.call("get_active_conversations") as Array).size(),
		1,
		"global announcement does not interrupt the active conversation",
	)
	_expect_equal(
		(world.call("get_resident_state", "林岚") as Dictionary).get("doing"),
		"正前往社区花园",
		"global announcement does not replace the moving resident's action",
	)
	_expect_equal(
		world.call("submit_player_avatar_position", "town_outdoor", Vector2(3240, 3580), "在南入口散步").get("ok"),
		true,
		"avatar position changes before save",
	)
	world.call("advance", 0.25)
	world.call("queue_weather_roll", 0.999)
	world.call("pause", "manual")

	var saved_time := world.call("get_time") as Dictionary
	var saved_weather := String(world.call("get_weather"))
	var saved_lin := world.call("get_resident_state", "林岚") as Dictionary
	var saved_avatar := world.call("get_player_avatar_state") as Dictionary
	var saved_conversation := (world.call("get_active_conversations") as Array)[0] as Dictionary
	var save_result := world.call("create_save_snapshot") as Dictionary
	_expect_equal(save_result.get("ok"), true, "running or paused world creates a save snapshot")
	var snapshot := (save_result.get("snapshot", {}) as Dictionary).duplicate(true)
	_expect_equal(snapshot.get("schema"), "town-world-save", "snapshot uses the frozen schema")
	_expect_equal(snapshot.get("schemaVersion"), 2, "snapshot declares version two")
	var json_text := JSON.stringify(snapshot)
	var parsed: Variant = JSON.parse_string(json_text)
	_expect(typeof(parsed) == TYPE_DICTIONARY, "snapshot survives a real JSON serialization round trip")
	var decoded := SAVE_CODEC.decode_checked(snapshot.get("state", {}) as Dictionary) as Dictionary
	_expect_equal(decoded.get("ok"), true, "saved state decodes through the checked codec")
	var decoded_state := decoded.get("value", {}) as Dictionary
	var first_saved_resident := (decoded_state.get("residents", []) as Array)[0] as Dictionary
	_expect(not first_saved_resident.has("validDecisionId"), "waiting decision id is not persisted")
	_expect(not first_saved_resident.has("pendingWake"), "waiting network request is not persisted")
	var saved_environment := ((snapshot.get("state", {}) as Dictionary).get("environment", {}) as Dictionary).duplicate(true)
	var activity_reachability_cache := world.get(
		"activity_reachability_state",
	) as TownActivityReachabilityCache
	var cache_resident := {
		"residentId": "restore-cache-resident",
		"position": Vector2.ZERO,
	}
	var cache_candidate := {
		"targetPropName": "restore-cache-prop",
		"targetActionVerb": "测试",
		"memberPosition": [1.0, 1.0],
	}
	activity_reachability_cache.ensure_minute(123)
	activity_reachability_cache.remember_reachability(
		cache_resident,
		cache_candidate,
		{},
		true,
		{"targetPosition": Vector2.ONE},
	)
	_expect_equal(
		activity_reachability_cache.reachability_count(),
		1,
		"transient activity route cache exists before restore",
	)

	world.call("resume", "manual")
	world.call("set_weather", "下雪")
	world.call("advance", 5.0)
	var restore_result := world.call("restore_from_snapshot", data, opening, parsed as Dictionary) as Dictionary
	_expect_equal(restore_result.get("ok"), true, "JSON-round-tripped snapshot restores (%s)" % str(restore_result.get("errors", [])))
	_expect(
		activity_reachability_cache.reachability_count() == 0
			and activity_reachability_cache.prepared_action_count() == 0
			and activity_reachability_cache.cached_minute() == -1,
		"restore clears transient activity route and prepared-action caches",
	)
	_expect_equal(world.call("get_time"), saved_time, "restore preserves world time")
	_expect_equal(world.call("get_weather"), saved_weather, "restore preserves weather")
	var restored_lin := world.call("get_resident_state", "林岚") as Dictionary
	_expect_equal(
		_without_world_revision(restored_lin),
		_without_world_revision(saved_lin),
		"restore preserves the moving resident's actual state",
	)
	_expect(
		int(restored_lin.get("worldRevision", 0)) > int(saved_lin.get("worldRevision", 0)),
		"restore publishes the preserved resident state at a fresh monotonic World revision",
	)
	_expect_equal(world.call("get_player_avatar_state"), saved_avatar, "restore preserves avatar state")
	_expect_equal((world.call("get_active_conversations") as Array).size(), 1, "restore preserves active conversation")
	_expect_equal(
		(world.call("get_active_conversations") as Array)[0],
		saved_conversation,
		"restore preserves confirmed conversation turns and waiting participant",
	)
	_expect_equal((world.call("get_announcements") as Array).size(), 1, "restore preserves announcement board")
	_expect_equal((world.call("get_lifecycle_state") as Dictionary).get("state"), "running", "restored world starts running without persisting UI pause reasons")
	_expect_equal(_restore_events.size(), 1, "restore emits one summary event for presentation re-query")

	var after_restore_snapshot := world.call("create_save_snapshot") as Dictionary
	_expect_equal(
		(((after_restore_snapshot.get("snapshot", {}) as Dictionary).get("state", {}) as Dictionary).get("environment", {})),
		saved_environment,
		"restore preserves weather RNG, partial minute and forced-roll state",
	)

	var load_requests := world.call("take_pending_decision_requests") as Array[Dictionary]
	_expect_equal(load_requests.size(), 15, "restore creates one fresh request for every resident")
	var ahe_load := _request_for(load_requests, "阿禾")
	var lin_load := _request_for(load_requests, "林岚")
	_expect_equal(ahe_load.size(), 5, "restored request uses the exact interface envelope")
	_expect_equal(lin_load.size(), 5, "moving resident also receives an exact restore wake")
	_expect(String(ahe_load.get("decision_id", "")) != String(ahe_initial.get("decision_id", "")), "load decision id differs from the pre-save request")
	_expect(_has_event(ahe_load, "搭话"), "undelivered urgent conversation event survives save")
	_expect(_has_event(ahe_load, "公告发布"), "global announcement queued behind an in-flight request survives save")
	_expect_equal(
		world.call("submit_agent_decision", "阿禾", _wait(ahe_initial)).get("stale"),
		true,
		"pre-save asynchronous Agent return is stale after load",
	)
	var restored_continue := world.call(
		"submit_agent_decision",
		"林岚",
		{"decision_id": lin_load.get("decision_id", ""), "handling": "continue_current"},
	) as Dictionary
	_expect_equal(
		restored_continue.get("errorCode"),
		"PLAYER_ANNOUNCEMENT_ACTION_REQUIRED",
		"restored player announcement still prevents continuing ordinary movement",
	)
	_expect_equal(
		restored_continue.get("consumed"),
		false,
		"rejected restored continuation keeps the fresh request available",
	)
	_expect_equal(
		world.call(
			"submit_agent_decision",
			"林岚",
			_go(lin_load, "社区花园"),
		).get("status"),
		"accepted",
		"restored resident can replace the old movement after the player announcement",
	)
	var lin_position_before_advance := (world.call("get_resident_state", "林岚") as Dictionary).get("position") as Vector2
	world.call("advance", 1.0)
	_expect(
		(world.call("get_resident_state", "林岚") as Dictionary).get("position") != lin_position_before_advance,
		"restored movement continues from its saved progress",
	)

	var stable_time := world.call("get_time") as Dictionary
	var invalid_version := snapshot.duplicate(true)
	invalid_version["schemaVersion"] = 99
	var invalid_result := world.call("restore_from_snapshot", data, opening, invalid_version) as Dictionary
	_expect_equal(invalid_result.get("ok"), false, "unsupported save version is rejected")
	_expect_equal(world.call("get_time"), stable_time, "rejected restore is atomic and keeps current world")
	var incompatible_data := snapshot.duplicate(true)
	incompatible_data["worldDataVersion"] = int(snapshot.get("worldDataVersion", 0)) + 1
	_expect_equal(
		world.call("restore_from_snapshot", data, opening, incompatible_data).get("ok"),
		false,
		"save from another world data version is rejected",
	)
	world.call("stop")


func _without_world_revision(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	result.erase("worldRevision")
	if result.get("actionPhase") is Dictionary:
		var action_phase := (result.get("actionPhase", {}) as Dictionary).duplicate(true)
		action_phase.erase("decisionId")
		action_phase.erase("worldRevision")
		result["actionPhase"] = action_phase
	if result.get("actionPresentation") is Dictionary:
		var action_presentation := (result.get("actionPresentation", {}) as Dictionary).duplicate(true)
		action_presentation.erase("confirmedRevision")
		result["actionPresentation"] = action_presentation
	return result


# —— 场景二：save → restore → save 往返等价 ——

func _scenario_roundtrip_equivalence() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "roundtrip test opening remains legal")

	var world: TownWorldRuntime = WORLD.new()
	_expect_equal((world.start(data, opening) as Dictionary).get("ok"), true, "world starts before roundtrip")
	var lin_wake := _take_wake(world, "林岚")
	var tang_wake := _take_wake(world, "唐小满")
	_take_wake(world, "阿禾")
	_expect_equal(
		(world.submit_agent_decision("林岚", _go(lin_wake, "社区花园")) as Dictionary).get("status"),
		"accepted",
		"movement begins before roundtrip",
	)
	world.advance(1.0)
	_expect_equal(
		(world.submit_agent_decision("唐小满", _talk(tang_wake, "阿禾", "唐小满朝阿禾点了点头")) as Dictionary).get("status"),
		"accepted",
		"conversation begins before roundtrip",
	)
	world.set_weather("小雨")
	world.publish_announcement("往返等价测试公告。")
	world.submit_player_avatar_position("town_outdoor", Vector2(3240, 3580), "在南入口散步")
	world.advance(0.25)
	world.pause("manual")

	var first := world.create_save_snapshot() as Dictionary
	_expect_equal(first.get("ok"), true, "first save snapshot succeeds")
	var snapshot_one := (first.get("snapshot", {}) as Dictionary).duplicate(true)
	var parsed: Variant = JSON.parse_string(JSON.stringify(snapshot_one))
	_expect(typeof(parsed) == TYPE_DICTIONARY, "snapshot one survives JSON roundtrip")

	var restore_result := world.restore_from_snapshot(data, opening, parsed as Dictionary) as Dictionary
	_expect_equal(
		restore_result.get("ok"),
		true,
		"snapshot one restores (%s)" % str(restore_result.get("errors", [])),
	)

	var second := world.create_save_snapshot() as Dictionary
	_expect_equal(second.get("ok"), true, "post-restore save snapshot succeeds")
	var snapshot_two := (second.get("snapshot", {}) as Dictionary).duplicate(true)

	_expect_equal(snapshot_two.get("schema"), snapshot_one.get("schema"), "schema is stable across the roundtrip")
	_expect_equal(
		snapshot_two.get("schemaVersion"),
		snapshot_one.get("schemaVersion"),
		"schemaVersion is stable across the roundtrip",
	)

	var diffs: Array[Dictionary] = []
	_collect_diffs(
		"",
		snapshot_one.get("state", {}) as Dictionary,
		snapshot_two.get("state", {}) as Dictionary,
		diffs,
	)

	var unexpected: Array[String] = []
	var seen_allowed := {}
	for diff: Dictionary in diffs:
		var path := String(diff.get("path", ""))
		var rule := _allowed_rule(path)
		if rule.is_empty():
			unexpected.append("%s: %s -> %s" % [path, str(diff.get("a")), str(diff.get("b"))])
			continue
		seen_allowed[rule] = true
		match String(ALLOWED_CHANGES[rule]):
			"increment":
				_expect(
					_as_number(diff.get("b")) > _as_number(diff.get("a")),
					"allowed field %s must strictly increase (%s -> %s)" % [
						path, str(diff.get("a")), str(diff.get("b"))
					],
				)
			"cleared":
				_expect(
					_is_empty_value(diff.get("b")),
					"allowed field %s must be cleared after restore" % path,
				)
			"reset":
				_expect(
					typeof(diff.get("b")) == typeof(diff.get("a")),
					"allowed field %s keeps its type across restore" % path,
				)
	_expect_equal(unexpected, [], "no stable persistent field drifts across save->restore->save")
	_expect(
		seen_allowed.has("sequences/worldRevision"),
		"worldRevision does change across restore (allowed-list stays honest)",
	)
	world.stop()


func _allowed_rule(path: String) -> String:
	for rule: String in ALLOWED_CHANGES:
		if path == rule:
			return rule
		var rule_parts := rule.split("/")
		var path_parts := path.split("/")
		if rule_parts.size() != path_parts.size():
			continue
		var matched := true
		for i in rule_parts.size():
			if rule_parts[i] != "*" and rule_parts[i] != path_parts[i]:
				matched = false
				break
		if matched:
			return rule
	return ""


func _collect_diffs(path: String, a: Variant, b: Variant, diffs: Array[Dictionary]) -> void:
	# 数值按数值等价比较：int/float 表示差异与浮点低位差在 JSON 落盘后本就同一，
	# 不构成持久字段漂移。
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		if not is_equal_approx(float(a), float(b)):
			diffs.append({"path": path, "a": a, "b": b})
		return
	if typeof(a) != typeof(b):
		diffs.append({"path": path, "a": a, "b": b})
		return
	match typeof(a):
		TYPE_DICTIONARY:
			var da := a as Dictionary
			var db := b as Dictionary
			for key: Variant in da:
				var child := "%s/%s" % [path, str(key)] if not path.is_empty() else str(key)
				if not db.has(key):
					diffs.append({"path": child, "a": da[key], "b": "<缺失>"})
					continue
				_collect_diffs(child, da[key], db[key], diffs)
			for key: Variant in db:
				if not da.has(key):
					var child := "%s/%s" % [path, str(key)] if not path.is_empty() else str(key)
					diffs.append({"path": child, "a": "<缺失>", "b": db[key]})
		TYPE_ARRAY:
			var aa := a as Array
			var ab := b as Array
			if aa.size() != ab.size():
				diffs.append({"path": path + "/#size", "a": aa.size(), "b": ab.size()})
				return
			for i in aa.size():
				_collect_diffs("%s/%d" % [path, i], aa[i], ab[i], diffs)
		_:
			if a != b:
				diffs.append({"path": path, "a": a, "b": b})


func _as_number(value: Variant) -> float:
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else -INF


func _is_empty_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_DICTIONARY:
			return (value as Dictionary).is_empty()
		TYPE_ARRAY:
			return (value as Array).is_empty()
		TYPE_STRING:
			return String(value).is_empty()
		_:
			return value == null


# —— 场景三：损坏存档拦截 ——
##
## 区分两类输入：
## - 非法输入（必需字段缺失 / 类型错误 / 非法值 / 字段存在但内容损坏）——
##   必须在准备阶段显式失败（ok=false 且带错误信息），且失败的恢复不得
##   污染运行中的世界（时间/天气/修订号原样，世界仍在运行）；
## - 合法旧版本缺可选域——按迁移规则补默认值恢复成功，不得被误判为损坏。

func _scenario_restore_corruption() -> void:
	var data := _build_data()
	var opening := _load_opening(data)

	var world: TownWorldRuntime = WORLD.new()
	_expect_equal((world.start(data, opening) as Dictionary).get("ok"), true, "world starts before corruption battery")
	world.set_weather("小雨")
	world.advance(0.5)
	world.pause("manual")

	var save_result := world.create_save_snapshot() as Dictionary
	_expect_equal(save_result.get("ok"), true, "clean snapshot exists as the corruption base")
	var clean := (save_result.get("snapshot", {}) as Dictionary).duplicate(true)

	var baseline_time := world.get_time() as Dictionary
	var baseline_weather := String(world.get_weather())
	var baseline_revision := int(world.get_world_revision())

	var illegal_cases: Array[Dictionary] = []

	var missing_residents := clean.duplicate(true)
	(missing_residents.get("state", {}) as Dictionary).erase("residents")
	illegal_cases.append({"name": "必需字段缺失: state.residents", "snapshot": missing_residents})

	var missing_environment := clean.duplicate(true)
	(missing_environment.get("state", {}) as Dictionary).erase("environment")
	illegal_cases.append({"name": "必需字段缺失: state.environment", "snapshot": missing_environment})

	var wrong_type_sequences := clean.duplicate(true)
	(wrong_type_sequences.get("state", {}) as Dictionary)["sequences"] = "不是字典"
	illegal_cases.append({"name": "类型错误: state.sequences 为字符串", "snapshot": wrong_type_sequences})

	var wrong_type_residents := clean.duplicate(true)
	(wrong_type_residents.get("state", {}) as Dictionary)["residents"] = {"不是": "数组"}
	illegal_cases.append({"name": "类型错误: state.residents 为字典", "snapshot": wrong_type_residents})

	var invalid_schema := clean.duplicate(true)
	invalid_schema["schemaVersion"] = 999
	illegal_cases.append({"name": "非法值: schemaVersion=999", "snapshot": invalid_schema})

	var corrupted_resident := clean.duplicate(true)
	var residents_list := ((corrupted_resident.get("state", {}) as Dictionary).get("residents", []) as Array)
	if not residents_list.is_empty():
		residents_list[0] = {"损坏": true}
	illegal_cases.append({"name": "内容损坏: 首个居民记录被替换为垃圾", "snapshot": corrupted_resident})

	for case: Dictionary in illegal_cases:
		var case_name := String(case.get("name", ""))
		print("CORRUPTION_CASE_BEGIN: %s" % case_name)
		var result := world.restore_from_snapshot(data, opening, case.get("snapshot", {}) as Dictionary) as Dictionary
		print("CORRUPTION_CASE_DONE: %s ok=%s" % [case_name, str(result.get("ok"))])
		_expect_equal(result.get("ok"), false, "%s -> 恢复显式失败" % case_name)
		_expect(
			not (result.get("errors", []) as Array).is_empty(),
			"%s -> 失败携带可判定错误信息" % case_name,
		)
		_expect_equal(world.get_time(), baseline_time, "%s -> 失败的恢复不污染世界时间(准备阶段拦截)" % case_name)
		_expect_equal(String(world.get_weather()), baseline_weather, "%s -> 失败的恢复不污染天气" % case_name)
		_expect_equal(int(world.get_world_revision()), baseline_revision, "%s -> 失败的恢复不推进世界修订号" % case_name)
		_expect_equal(world.is_running(), true, "%s -> 世界仍在运行" % case_name)

	var legacy_missing_optional := clean.duplicate(true)
	var legacy_state := legacy_missing_optional.get("state", {}) as Dictionary
	legacy_state.erase("privateMessages")
	legacy_state.erase("privateMessageArchiveSummary")
	var legacy_result := world.restore_from_snapshot(data, opening, legacy_missing_optional) as Dictionary
	_expect_equal(
		legacy_result.get("ok") == true or legacy_result.has("residentCount"),
		true,
		"合法旧版缺可选域(privateMessages) -> 迁移默认值恢复成功(%s)" % str(legacy_result.get("errors", [])),
	)

	# 恢复被上一步成功恢复改变过状态,最后再用干净快照恢复一次收尾自证
	var final_result := world.restore_from_snapshot(data, opening, clean) as Dictionary
	_expect_equal(
		final_result.get("ok") == true or final_result.has("residentCount"),
		true,
		"干净快照在损坏轰炸后仍可恢复",
	)
	world.stop()


# —— 场景四：Activity 完成后的存档往返 ——

func _scenario_activity_save_roundtrip() -> void:
	var data := _build_data()
	var opening := _load_opening(data)
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"Activity World 可启动",
	)
	var performed := world.call(
		"perform_activity_step",
		"resident_su_he_01",
		"save-roundtrip-plan",
		1,
		{
			"stepId": "read-until-complete",
			"operation": "activity.perform",
			"target": {
				"activityId": "activity_library_read",
				"placeId": "图书馆",
			},
			"params": {},
		},
	) as Dictionary
	_expect_equal(performed.get("ok"), true, "Activity 可开始执行")
	var elapsed_real_seconds := 0.0
	var current_action_value: Variant = {}
	while elapsed_real_seconds < 180.0:
		world.call("advance", 5.0)
		elapsed_real_seconds += 5.0
		var resident_state := world.call("get_resident_state", "resident_su_he_01") as Dictionary
		current_action_value = resident_state.get("currentAction")
		if (
			current_action_value == null
			or (
				current_action_value is Dictionary
				and (current_action_value as Dictionary).is_empty()
			)
		):
			break
	_expect(
		current_action_value == null
		or (
			current_action_value is Dictionary
			and (current_action_value as Dictionary).is_empty()
		),
		"Activity 在 180 秒上限内完成并释放当前动作",
	)
	var prepared := world.call("prepare_save_candidate") as Dictionary
	_expect_equal(prepared.get("ok"), true, "完成 Activity 后可生成能回读的 World 保存候选")
	var snapshot := (prepared.get("snapshot", {}) as Dictionary).duplicate(true)
	var restored: RefCounted = WORLD.new()
	_expect_equal(
		(restored.call("restore_from_snapshot", data, opening, snapshot) as Dictionary).get("ok"),
		true,
		"完成 Activity 的存档可恢复",
	)
	restored.call("stop")

	var changed_effect := snapshot.duplicate(true)
	var activity_runtime := (
		(changed_effect.get("state", {}) as Dictionary).get("activityRuntime", {}) as Dictionary
	)
	var executions := activity_runtime.get("executions", []) as Array
	if not executions.is_empty():
		var committed_effects := (
			(executions[0] as Dictionary).get("committedEffects", {}) as Dictionary
		)
		committed_effects["stress"] = -5
	_expect_equal(
		(WORLD.new().call("restore_from_snapshot", data, opening, changed_effect) as Dictionary).get("ok"),
		false,
		"修改后的 Activity 效果仍被拒绝",
	)

	var missing_effect := snapshot.duplicate(true)
	var missing_runtime := (
		(missing_effect.get("state", {}) as Dictionary).get("activityRuntime", {}) as Dictionary
	)
	var missing_executions := missing_runtime.get("executions", []) as Array
	if not missing_executions.is_empty():
		((missing_executions[0] as Dictionary).get("committedEffects", {}) as Dictionary).erase("stress")
	_expect_equal(
		(WORLD.new().call("restore_from_snapshot", data, opening, missing_effect) as Dictionary).get("ok"),
		false,
		"缺字段的 Activity 效果仍被拒绝",
	)

	var nonnumeric_effect := snapshot.duplicate(true)
	var nonnumeric_runtime := (
		(nonnumeric_effect.get("state", {}) as Dictionary).get("activityRuntime", {}) as Dictionary
	)
	var nonnumeric_executions := nonnumeric_runtime.get("executions", []) as Array
	if not nonnumeric_executions.is_empty():
		((nonnumeric_executions[0] as Dictionary).get("committedEffects", {}) as Dictionary)["stress"] = "invalid"
	_expect_equal(
		(WORLD.new().call("restore_from_snapshot", data, opening, nonnumeric_effect) as Dictionary).get("ok"),
		false,
		"非数值 Activity 效果仍被拒绝",
	)
	world.call("stop")


# —— 场景五：存档事务参与方（prepare / commit / abort / cleanup） ——

func _scenario_save_participant() -> void:
	_restore_events.clear()
	var source_data := _build_data()
	var ready_data := source_data.duplicate(true)
	ready_data["contentStatus"] = {
		"stage": "world_ready",
		"worldReady": true,
		"pendingSections": [],
	}
	var incomplete_data := ready_data.duplicate(true)
	incomplete_data["contentStatus"] = {
		"stage": "outdoor_ready",
		"worldReady": false,
		"pendingSections": ["indoorProps"],
	}
	var opening := FORMAL_OPENING.with_authoritative_new_game_spawns(
		ready_data,
		_build_participant_opening(ready_data),
	)
	var identities := _resident_identities(opening)
	_expect_equal(OPENING.validate(opening, ready_data), [], "participant opening is legal")

	var stopped_world: RefCounted = WORLD.new()
	var stopped_prepare := stopped_world.call("prepare_save_candidate") as Dictionary
	_expect_equal(stopped_prepare.get("errorCode"), "WORLD_NOT_RUNNING", "save prepare failure is stable")
	_expect_equal(stopped_world.call("get_world_revision"), 0, "failed save prepare has no side effect")

	var world: RefCounted = WORLD.new()
	world.connect("world_restored", _on_world_restored)
	var start_result := world.call("start_formal", ready_data, opening, identities) as Dictionary
	_expect_equal(start_result.get("ok"), true, "formal world starts for transaction test")
	world.call("cycle_time_period_for_test")
	world.call("cycle_time_period_for_test")
	var resident_name := String((identities[0] as Dictionary).get("residentName", ""))
	var resident_id := String((identities[0] as Dictionary).get("residentId", ""))
	var movement_before_save := world.call("get_resident_movement_snapshot", resident_id) as Dictionary
	_expect_equal(
		movement_before_save.get("movementRevision"),
		3,
		"first-day arrival and its entry step are authoritative movement states",
	)
	_expect_equal(movement_before_save.get("residentId"), resident_id, "movement snapshot is stable-ID keyed")
	var initial_wake := _take_wake(world, resident_name)
	var identity_before := world.call("get_resident_identity_snapshot") as Dictionary
	var revision_before_prepare := int(world.call("get_world_revision"))
	var time_before_prepare := world.call("get_time") as Dictionary

	var abortable_save := world.call("prepare_save_candidate") as Dictionary
	_expect_equal(
		abortable_save.get("ok"),
		true,
		"World prepares a save candidate: %s" % JSON.stringify(abortable_save),
	)
	_expect_equal(world.call("get_world_revision"), revision_before_prepare, "save prepare does not bump revision")
	_expect_equal(world.call("get_time"), time_before_prepare, "save prepare does not advance time")
	_expect_equal(
		world.call("get_resident_identity_snapshot"),
		identity_before,
		"save prepare does not alter identity",
	)
	var abortable_save_token := _candidate_token(abortable_save)
	_expect_equal(
		(world.call("validate_save_candidate", abortable_save_token) as Dictionary).get("ok"),
		true,
		"prepared save candidate validates",
	)
	var aborted_save := world.call("abort_save_candidate", abortable_save_token) as Dictionary
	_expect_equal(
		(aborted_save.get("candidate", {}) as Dictionary).get("state"),
		"aborted",
		"future Agent failure can abort the World save candidate",
	)
	_expect_equal(world.call("get_world_revision"), revision_before_prepare, "save abort leaves gameplay unchanged")
	_expect_equal(
		(world.call("cleanup_save_candidate", abortable_save_token) as Dictionary).get("ok"),
		true,
		"aborted save candidate can be cleaned",
	)
	_expect_equal(
		(world.call("validate_save_candidate", abortable_save_token) as Dictionary).get("errorCode"),
		"WORLD_SAVE_CANDIDATE_NOT_FOUND",
		"cleaned save candidate is no longer addressable",
	)

	var stale_save := world.call("prepare_save_candidate") as Dictionary
	var stale_save_token := _candidate_token(stale_save)
	_expect_equal(world.call("set_weather", "阴天").get("changed"), true, "World changes after save prepare")
	var stale_save_commit := world.call(
		"commit_save_candidate",
		stale_save_token,
		"opaque-stale-world-revision",
	) as Dictionary
	_expect_equal(
		stale_save_commit.get("errorCode"),
		"WORLD_SAVE_CANDIDATE_STALE",
		"save candidate rejects a changed World revision",
	)
	_expect_equal(stale_save_commit.get("retryable"), true, "stale save candidate can be prepared again")
	world.call("abort_save_candidate", stale_save_token)
	world.call("cleanup_save_candidate", stale_save_token)
	_expect_equal(world.call("set_weather", "晴天").get("changed"), true, "test returns to the baseline weather")

	var previous_save := world.call("prepare_save_candidate") as Dictionary
	var previous_token := _candidate_token(previous_save)
	var previous_commit := world.call(
		"commit_save_candidate",
		previous_token,
		"opaque-world-revision-1",
	) as Dictionary
	_expect_equal(previous_commit.get("ok"), true, "previous World component becomes committed")
	_expect_equal(
		world.call("commit_save_candidate", previous_token, "opaque-world-revision-1").get("ok"),
		true,
		"save commit is idempotent for the same snapshotRef",
	)
	var saved_snapshot := (previous_save.get("snapshot", {}) as Dictionary).duplicate(true)
	_expect_equal(world.call("set_weather", "小雨").get("changed"), true, "world changes after previous candidate")
	var interrupted_save := world.call("prepare_save_candidate") as Dictionary
	var interrupted_token := _candidate_token(interrupted_save)
	_expect_equal(
		world.call("commit_save_candidate", interrupted_token, "opaque-world-revision-2").get("ok"),
		true,
		"new World candidate can commit before common manifest publication",
	)
	var previous_still_complete := world.call("validate_save_candidate", previous_token) as Dictionary
	_expect_equal(previous_still_complete.get("ok"), true, "new candidate does not delete previous complete revision")
	_expect_equal(
		(previous_still_complete.get("candidate", {}) as Dictionary).get("snapshotRef"),
		"opaque-world-revision-1",
		"previous complete snapshot reference stays intact",
	)
	var interrupted_abort := world.call("abort_save_candidate", interrupted_token) as Dictionary
	_expect_equal(
		interrupted_abort.get("cleanupSnapshotRef"),
		"opaque-world-revision-2",
		"unpublished committed candidate returns its orphan reference for session cleanup",
	)
	world.call("cleanup_save_candidate", interrupted_token)
	_expect_equal(
		(world.call("validate_save_candidate", previous_token) as Dictionary).get("ok"),
		true,
		"aborting the interrupted candidate does not affect previous revision",
	)
	world.call("cleanup_save_candidate", previous_token)

	var state_before_rejections := _observable_state(world)
	var incomplete_restore := world.call(
		"prepare_restore_candidate",
		incomplete_data,
		opening,
		saved_snapshot,
		identities,
	) as Dictionary
	_expect_equal(
		incomplete_restore.get("errorCode"),
		"WORLD_DATA_INCOMPLETE",
		"formal restore cannot bypass pending indoorProps",
	)
	_expect_equal(_observable_state(world), state_before_rejections, "formal readiness rejection is side-effect free")

	var drifted_identities := identities.duplicate(true)
	var first_id := String((drifted_identities[0] as Dictionary).get("residentId", ""))
	var second_id := String((drifted_identities[1] as Dictionary).get("residentId", ""))
	(drifted_identities[0] as Dictionary)["residentId"] = second_id
	(drifted_identities[1] as Dictionary)["residentId"] = first_id
	var identity_drift := world.call(
		"prepare_restore_candidate",
		ready_data,
		opening,
		saved_snapshot,
		drifted_identities,
		true,
	) as Dictionary
	_expect_equal(
		identity_drift.get("errorCode"),
		"WORLD_RESTORE_IDENTITY_DRIFT",
		"running confirmed World rejects an ID-to-name mapping drift",
	)
	_expect_equal(_observable_state(world), state_before_rejections, "identity drift rejection is side-effect free")

	var abortable_restore := world.call(
		"prepare_restore_candidate",
		ready_data,
		opening,
		saved_snapshot,
		identities,
		true,
	) as Dictionary
	_expect_equal(abortable_restore.get("ok"), true, "formal restore prepares without committing")
	var abortable_restore_token := _candidate_token(abortable_restore)
	_expect_equal(_observable_state(world), state_before_rejections, "restore prepare preserves live World")
	_expect_equal(
		world.call("validate_restore_candidate", abortable_restore_token).get("ok"),
		true,
		"restore candidate validates before other participants commit",
	)
	_expect_equal(
		world.call("abort_restore_candidate", abortable_restore_token).get("ok"),
		true,
		"future Agent prepare failure can abort the restore candidate",
	)
	_expect_equal(
		world.call("abort_restore_candidate", abortable_restore_token).get("ok"),
		true,
		"restore abort is idempotent before cleanup",
	)
	_expect_equal(_observable_state(world), state_before_rejections, "restore abort preserves live World")
	world.call("cleanup_restore_candidate", abortable_restore_token)

	var stale_restore := world.call(
		"prepare_restore_candidate",
		ready_data,
		opening,
		saved_snapshot,
		identities,
		true,
	) as Dictionary
	var stale_restore_token := _candidate_token(stale_restore)
	_expect_equal(world.call("set_weather", "下雪").get("changed"), true, "live World changes after restore prepare")
	var stale_commit := world.call("commit_restore_candidate", stale_restore_token) as Dictionary
	_expect_equal(
		stale_commit.get("errorCode"),
		"WORLD_RESTORE_CANDIDATE_STALE",
		"restore commit rejects a changed base World",
	)
	_expect_equal(stale_commit.get("retryable"), true, "stale restore can be prepared again")
	_expect_equal(world.call("get_weather"), "下雪", "stale restore never replaces current state")
	world.call("abort_restore_candidate", stale_restore_token)
	world.call("cleanup_restore_candidate", stale_restore_token)

	var committed_restore := world.call(
		"prepare_restore_candidate",
		ready_data,
		opening,
		saved_snapshot,
		identities,
		true,
	) as Dictionary
	var committed_restore_token := _candidate_token(committed_restore)
	var base_generation := int((committed_restore.get("candidate", {}) as Dictionary).get("baseGeneration", -1))
	var restore_commit := world.call("commit_restore_candidate", committed_restore_token) as Dictionary
	_expect_equal(restore_commit.get("ok"), true, "prepared formal restore commits atomically")
	_expect_equal(world.call("get_weather"), "晴天", "commit activates the saved World state")
	var movement_after_restore := world.call("get_resident_movement_snapshot", resident_id) as Dictionary
	_expect_equal(
		movement_after_restore.get("movementRevision"),
		movement_before_save.get("movementRevision"),
		"restore preserves the saved authoritative movement revision",
	)
	_expect_equal(
		movement_after_restore.get("worldRevision"),
		(_restore_events[0] as Dictionary).get("worldRevision") if not _restore_events.is_empty() else -1,
		"world_restored is the host's hard-relocate point for the restored movement snapshot",
	)
	_expect_equal(
		(_restore_events[0] as Dictionary).get("residentRelocationRequired") if not _restore_events.is_empty() else false,
		true,
		"restore explicitly requires the host to relocate every resident body",
	)
	_expect_equal(
		int((restore_commit.get("commitReceipt", {}) as Dictionary).get("runtimeGeneration", -1)),
		base_generation + 1,
		"restore commit advances runtime generation exactly once",
	)
	_expect_equal(
		(restore_commit.get("commitReceipt", {}) as Dictionary).get("identitySnapshot"),
		identity_before,
		"post-restore receipt proves the confirmed identity mapping",
	)
	_expect_equal(_restore_events.size(), 1, "only commit emits world_restored")
	var repeated_restore_commit := world.call("commit_restore_candidate", committed_restore_token) as Dictionary
	_expect_equal(repeated_restore_commit.get("ok"), true, "restore commit response can be retried")
	_expect_equal(
		repeated_restore_commit.get("commitReceipt"),
		restore_commit.get("commitReceipt"),
		"idempotent restore commit returns the same receipt",
	)
	_expect_equal(_restore_events.size(), 1, "idempotent commit does not restore twice")
	_expect_equal(
		world.call("submit_agent_decision", resident_name, _wait(initial_wake, "等待存档事务完成")).get("stale"),
		true,
		"pre-restore asynchronous return is stale after generation changes",
	)
	_expect_equal(
		world.call("cleanup_restore_candidate", committed_restore_token).get("ok"),
		true,
		"committed restore candidate can be cleaned after verification",
	)
	world.call("stop")


func _resident_identities(opening: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		result.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(resident.get("attributes", {}).get("name", "")),
		})
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("residentId", "")) < String(right.get("residentId", ""))
	)
	return result


func _build_participant_opening(data: Dictionary) -> Dictionary:
	var homes: Array[Dictionary] = []
	for place_value: Variant in data.get("places", []) as Array:
		var place := place_value as Dictionary
		if String(place.get("type", "")) == "住家":
			homes.append(place.duplicate(true))
	homes.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("spaceId", "")) < String(right.get("spaceId", ""))
	)
	var resident_names: Array[String] = []
	var resident_ids: Array[String] = []
	for index in homes.size():
		resident_names.append("事务测试居民%02d" % (index + 1))
		resident_ids.append("save-resident-%02d" % (index + 1))
	var residents: Array[Dictionary] = []
	var home_owners := {}
	for index in homes.size():
		var resident_name := resident_names[index]
		var resident_id := resident_ids[index]
		var home_name := String(homes[index].get("name", ""))
		home_owners[home_name] = resident_id
		residents.append({
			"residentId": resident_id,
			"attributes": {
				"name": resident_name,
				"gender": "男" if index % 2 == 0 else "女",
				"age": 20 + index,
				"appearance": "resident_wardrobe_v1:look_%02d" % ((index + 1) % 16),
				"desire": "验证完整存档事务",
				"personality": "稳定",
				"speech": "简短",
			},
			"socialState": {
				"home": home_name,
				"job": "事务测试居民",
				"workplace": "中心广场",
			},
			"worldState": _world_state_at_place(data, home_name, "在%s" % home_name),
		})
	var owners := {}
	var next_owner := 0
	for place_value: Variant in data.get("places", []) as Array:
		var place := place_value as Dictionary
		if String(place.get("type", "")) == "公共地点":
			continue
		var place_name := String(place.get("name", ""))
		if home_owners.has(place_name):
			owners[place_name] = home_owners[place_name]
			continue
		owners[place_name] = resident_ids[next_owner % resident_ids.size()]
		next_owner += 1
	var avatar_state := _world_state_at_place(data, "南入口", "站在南入口")
	avatar_state.erase("body")
	return {
		"schemaVersion": 1,
		"worldId": String(data.get("worldId", "")),
		"environment": {
			"day": 1,
			"clock": "09:20",
			"weather": "晴天",
			"randomSeed": 20260717,
		},
		"residents": residents,
		"ownerAssignments": owners,
		"playerAvatar": {
			"residentId": "player-avatar",
			"name": "事务测试玩家",
			"worldState": avatar_state,
		},
	}


func _world_state_at_place(data: Dictionary, place_name: String, doing: String) -> Dictionary:
	for region_value: Variant in data.get("perceptionRegions", []) as Array:
		var region := region_value as Dictionary
		if String(region.get("placeName", "")) != place_name:
			continue
		return {
			"place": place_name,
			"spaceId": String(region.get("spaceId", "")),
			"regionId": String(region.get("id", "")),
			"position": _point_in_shape(region.get("shape", {}) as Dictionary),
			"doing": doing,
			"body": {"困": "不困", "饿": "不饿", "累": "不累"},
		}
	return {}


func _point_in_shape(shape: Dictionary) -> Array[float]:
	if String(shape.get("type", "")) == "grid_cells":
		var cells := shape.get("cells", []) as Array
		var cell := cells[0] as Array
		var cell_size := float(shape.get("cellSize", 1))
		return [(float(cell[0]) + 0.5) * cell_size, (float(cell[1]) + 0.5) * cell_size]
	return [
		float(shape.get("x", 0.0)) + float(shape.get("width", 0.0)) * 0.5,
		float(shape.get("y", 0.0)) + float(shape.get("height", 0.0)) * 0.5,
	]
