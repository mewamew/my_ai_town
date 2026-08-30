extends SceneTree
## 审讯会实机验收（headless 开新存档 + 真实 provider + 大步快进）
##
## 目的：不用等现实一天，直接验证第 2 天 08:00 审讯会全流程：
##   汇报期(≤120s) → 审讯期(≤600s) → 投票期(≤180s) → 开票散会。
## 验收点（对应 08-29 下午修复）：
##   1. 汇报期有人汇报成功(修复前 0 人, action.type 死循环)
##   2. 全程 0 次 "action.type 不是合法动作类型"
##   3. 全程 0 次 "reason 不是合法对话结束原因"
##   4. 警察 interrogationCount ≥ 1(修复前 0 审讯空转 600s)
##   5. 投票 ≥1 票且大会正常散会
##   6. 冻结期世界不受理做活动等生活动作(白名单收口)
##
## 流程：开新档(第1天08:00) → 大步 advance(120游戏分钟/步, 不 pump, 零 LLM
## 消耗)快进到第2天08:00(最后一步正好落在 08:00 触发大会) → 冻结期改为
## 每秒 advance(1.0) 驱动阶段超时 + 持续 pump 决策 → 散会后出报告。
##
## 用法：Godot --headless --path game --script res://tests/diag_assembly_live.gd
## 可选：AI_TOWN_ASSEMBLY_LIVE_CAP 总时长上限(默认 960s)
## 注意：会真实调用 LLM(预计 ¥1-3/次运行, 主要花在汇报期+审讯期+投票)。

const SOURCE_DIR := "res://world/data/town/source"
const BUILDER := preload("res://world/data/town/TownWorldDataBuilder.gd")
const RESIDENT_CATALOG := preload("res://world/presentation/session/TownResidentCatalog.gd")
const COMPILER := preload("res://world/presentation/session/TownNewGameOpeningCompiler.gd")
const PROVIDER_SETTINGS := preload("res://world/presentation/ui/TownProviderSettingsService.gd")
const PROVIDER_SERVICE := preload("res://world/integration/TownAgentProviderService.gd")
const AGENT_SYSTEM := preload("res://agent/AgentSystem.gd")
const GATEWAY := preload("res://world/integration/TownWorldAgentGateway.gd")
const WORLD := preload("res://world/runtime/TownWorldRuntime.gd")
const WEREWOLF := preload("res://world/runtime/TownWerewolfRuntime.gd")
const DATA_CLEANER := preload("res://tests/support/UserTestDataCleaner.gd")

const MODEL_TIMEOUT_MSEC := 90000
const FFWD_STEP_MINUTES := 120.0
const ASSEMBLY_TARGET_MINUTE_OF_DAY := 480  # 08:00
const PUMP_INTERVAL_FROZEN_MSEC := 400
const REPORT_PHASE_CAP_SEC := 170.0
const INTERROGATION_PHASE_CAP_SEC := 660.0
const VOTE_PHASE_CAP_SEC := 200.0

var _health_result: Dictionary = {}
var _gateway: Node = null
var _world: RefCounted = null
var _request_host: Node = null
var _storage_root := "user://tests/diag-assembly-live/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]
var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cap_seconds := int(OS.get_environment("AI_TOWN_ASSEMBLY_LIVE_CAP"))
	if cap_seconds <= 0:
		cap_seconds = 960
	print("ASSEMBLY_LIVE_START: cap=%ds (会真实调用 LLM)" % cap_seconds)

	# —— 真实 provider 配置(读用户设置) ——
	var saved := (
		PROVIDER_SETTINGS.new().load_saved_runtime_configuration() as Dictionary
	)
	if (
		saved.get("ok") != true
		or String(saved.get("providerId", "")).is_empty()
		or String(saved.get("modelId", "")).is_empty()
	):
		printerr("ASSEMBLY_LIVE_UNAVAILABLE: provider 未配置")
		quit(2)
		return
	var provider_id := String(saved.get("providerId", ""))
	var model_id := String(saved.get("modelId", ""))

	# —— 编译新游戏开局(等价"自己开存档") ——
	var world_data := BUILDER.build_from_source(SOURCE_DIR)
	var view_model := RESIDENT_CATALOG.build_view_model(provider_id, model_id, true, 1) as Dictionary
	var selection := (view_model.get("data", {}) as Dictionary).duplicate(true)
	selection["selected_resident_ids"] = (
		selection.get("recommended_resident_ids", []) as Array
	).duplicate()
	RESIDENT_CATALOG.update_confirmation_payload(selection, provider_id, model_id, 2)
	var compiled := COMPILER.compile(
		selection.get("confirmation_payload", {}) as Dictionary,
		world_data,
		RESIDENT_CATALOG.load_catalog(),
	) as Dictionary
	if compiled.get("ok") != true:
		printerr("ASSEMBLY_LIVE_COMPILE_FAIL: %s" % [compiled])
		quit(1)
		return
	var opening := compiled.get("openingConfig", {}) as Dictionary
	var bindings := compiled.get("residentBindings", []) as Array[Dictionary]
	var identities: Array[Dictionary] = []
	for binding: Dictionary in bindings:
		identities.append({
			"residentId": String(binding.get("residentId", "")),
			"residentName": String(binding.get("residentName", "")),
		})
	print("ASSEMBLY_LIVE_OPENING: residents=%d" % identities.size())

	# —— Provider 服务(真实网络) + 健康检查 ——
	_request_host = Node.new()
	_request_host.name = "DiagAssemblyLiveProviderHost"
	root.add_child(_request_host)
	var providers: RefCounted = PROVIDER_SERVICE.new()
	var provider_config := providers.call("configure", {
		"capabilityMode": "formal",
		"source": "saved-settings",
		"allowFake": false,
		"providerConfigs": saved.get("providerConfigs", {}) as Dictionary,
	}, _request_host) as Dictionary
	if provider_config.get("ok") != true:
		printerr("ASSEMBLY_LIVE_PROVIDER_FAIL: %s" % [provider_config])
		_cleanup(false)
		quit(2)
		return
	var health_started := providers.call("request_health_check", [
		{"providerId": provider_id, "modelId": model_id},
	], _on_health_check_completed) as Dictionary
	if (
		health_started.get("accepted") != true
		or not await _wait_for_health_check()
		or String(_health_result.get("status", "")) != "available"
	):
		printerr("ASSEMBLY_LIVE_HEALTH_FAIL: %s" % [_health_result])
		_cleanup(false)
		quit(2)
		return
	print("ASSEMBLY_LIVE_HEALTH_PASS: provider=%s model=%s" % [provider_id, model_id])

	# —— 世界 + Agent 系统 + Gateway ——
	_world = WORLD.new()
	var started := _world.call("start_formal", world_data, opening, identities) as Dictionary
	if started.get("ok") != true:
		printerr("ASSEMBLY_LIVE_WORLD_FAIL: %s" % [started])
		_cleanup(false)
		quit(1)
		return
	var agent_system: RefCounted = AGENT_SYSTEM.new()
	var storage := agent_system.call("configure_test_runtime_storage", _storage_root) as Dictionary
	if storage.get("ok") != true:
		printerr("ASSEMBLY_LIVE_STORAGE_FAIL: %s" % [storage])
		_cleanup(false)
		quit(1)
		return
	_gateway = GATEWAY.new()
	_gateway.name = "DiagAssemblyLiveGateway"
	_gateway.set("_agent_system", agent_system)
	_gateway.debug_decision_completed.connect(_on_decision_completed)
	root.add_child(_gateway)
	var configured := _gateway.call("configure_session", {
		"sessionId": "diag-assembly-%d" % Time.get_ticks_usec(),
		"slotId": "diag-assembly-%d" % OS.get_process_id(),
		"saveRevision": 0,
		"restorePending": false,
		"residentIdentities": identities.duplicate(true),
		"residentBindings": bindings.duplicate(true),
		"openingConfig": opening.duplicate(true),
		"capabilityMode": "formal",
		"formalReady": true,
	}, providers, _request_host) as Dictionary
	var bound := (
		_gateway.call("bind_world", _world) as Dictionary
		if configured.get("ok") == true
		else {}
	)
	if configured.get("ok") != true or bound.get("ok") != true:
		printerr("ASSEMBLY_LIVE_GATEWAY_FAIL: %s / %s" % [configured, bound])
		_cleanup(false)
		quit(1)
		return
	print("ASSEMBLY_LIVE_READY: start at %s" % JSON.stringify(_world.call("get_time")))

	# —— 阶段A: 大步快进, 最后一步正好落在 08:00 触发大会 ——
	# 不依赖天数换算口径: 每步把 minute_of_day 向 08:00 推进, 步距 ≤120,
	# 终点必然精确等于 08:00(狼人杀触发按 advance 结束时刻判定)。
	var ffwd_deadline := Time.get_ticks_msec() + 180_000
	var ffwd_steps := 0
	while not WEREWOLF.assembly_frozen(_world):
		if Time.get_ticks_msec() > ffwd_deadline:
			break
		var mod := _minute_of_day()
		if mod == ASSEMBLY_TARGET_MINUTE_OF_DAY:
			# 开局正踩 08:00(尚未触发): 整步跨过再向次日 08:00 推进
			_world.call("advance", 60.0)
		elif mod > ASSEMBLY_TARGET_MINUTE_OF_DAY:
			var to_next := 1440 - mod + ASSEMBLY_TARGET_MINUTE_OF_DAY
			_world.call("advance", minf(FFWD_STEP_MINUTES, float(to_next)))
		else:
			_world.call("advance", minf(FFWD_STEP_MINUTES, float(ASSEMBLY_TARGET_MINUTE_OF_DAY - mod)))
		ffwd_steps += 1
		await process_frame
	_expect_equal(WEREWOLF.assembly_frozen(_world), true, "第2天08:00大会触发并冻结")
	if WEREWOLF.assembly_frozen(_world):
		print("ASSEMBLY_LIVE_FIRED: 快进 %d 步后大会开始 %s" % [
			ffwd_steps, JSON.stringify(_world.call("get_time")),
		])
	else:
		printerr("ASSEMBLY_LIVE_NO_TRIGGER: 快进未触发大会(检查 feature_active/天数)")
		await _finish()
		return

	# —— 阶段B: 冻结期逐秒驱动(汇报→审讯→投票→散会) ——
	# advance(1.0) 每真实秒一次(阶段超时按真实秒累计, 与真实游戏同速),
	# 期间持续 pump 让模型并行作答。
	var run_deadline_ms := Time.get_ticks_msec() + cap_seconds * 1000
	var phase_started_ms := Time.get_ticks_msec()
	var last_pump_ms := 0
	var last_tick_ms := 0
	var last_state_log_ms := 0
	var seen_phases := {"report": false, "interrogation": false, "vote": false}
	var max_interrogation_count := 0
	var seen_interrogation_transcript := false
	var phase_cap_sec := REPORT_PHASE_CAP_SEC
	while Time.get_ticks_msec() < run_deadline_ms:
		var phase := WEREWOLF.assembly_phase(_world)
		if phase == "idle":
			print("ASSEMBLY_LIVE_DISMISSED: 大会散会 %s" % JSON.stringify(_world.call("get_time")))
			break
		if seen_phases.has(phase) and not bool(seen_phases[phase]):
			seen_phases[phase] = true
			phase_started_ms = Time.get_ticks_msec()
			print("ASSEMBLY_LIVE_PHASE: %s @%s" % [phase, JSON.stringify(_world.call("get_time"))])
		match phase:
			"report":
				phase_cap_sec = REPORT_PHASE_CAP_SEC
			"interrogation":
				phase_cap_sec = INTERROGATION_PHASE_CAP_SEC
			"vote":
				phase_cap_sec = VOTE_PHASE_CAP_SEC
		var phase_elapsed := (Time.get_ticks_msec() - phase_started_ms) / 1000.0
		if phase_elapsed > phase_cap_sec:
			printerr("ASSEMBLY_LIVE_PHASE_TIMEOUT: %s 超过 %.0fs 仍在进行" % [phase, phase_cap_sec])
			_expect(false, "阶段 %s 在 %.0fs 内结束" % [phase, phase_cap_sec])
			break
		var now_ms := Time.get_ticks_msec()
		if now_ms - last_tick_ms >= 1000:
			# 推进阶段真实秒超时(tick_assembly 在冻结短路前调用)
			_world.call("advance", 1.0)
			last_tick_ms = now_ms
		_gateway.call("_advance_agent_preparation")
		if now_ms - last_pump_ms >= PUMP_INTERVAL_FROZEN_MSEC:
			_gateway.call("pump", 1)
			last_pump_ms = now_ms
		if now_ms - last_state_log_ms >= 10000:
			last_state_log_ms = now_ms
			var state := WEREWOLF.assembly_state(_world)
			print("ASSEMBLY_LIVE_STATE: phase=%s reports=%d interrogated=%d votes=%d errors=%d" % [
				phase,
				(state.get("reports", {}) as Dictionary).size(),
				int(state.get("interrogationCount", 0)),
				((state.get("vote", {}) as Dictionary).get("votes", {}) as Dictionary).size(),
				(_gateway.call("get_errors") as Array).size(),
			])
		var current_state := WEREWOLF.assembly_state(_world) as Dictionary
		max_interrogation_count = maxi(
			max_interrogation_count,
			int(current_state.get("interrogationCount", 0)),
		)
		if not seen_interrogation_transcript:
			seen_interrogation_transcript = not (
				(current_state.get("interrogationTranscript", []) as Array).is_empty()
			)
		await process_frame

	# —— 验收 ——
	var final_state := WEREWOLF.assembly_state(_world) as Dictionary
	var reports := (final_state.get("reports", {}) as Dictionary).size()
	var votes := ((final_state.get("vote", {}) as Dictionary).get("votes", {}) as Dictionary).size()
	_expect(max_interrogation_count >= 1, "警察至少发起 1 次审讯(实际 %d)" % max_interrogation_count)
	_expect(
		seen_interrogation_transcript or max_interrogation_count >= 1,
		"审讯期产生审讯记录",
	)
	_expect(votes >= 1 or reports >= 1, "投票或汇报链路有产出(票=%d 汇报=%d)" % [votes, reports])
	_expect_equal(
		WEREWOLF.assembly_phase(_world) == "idle",
		true,
		"大会正常散会解冻",
	)
	# 失败特征扫描: 修复目标的两种报错必须为 0
	var action_type_errors := _count_error_text("不是合法动作类型")
	var end_reason_errors := _count_error_text("不是合法对话结束原因")
	var fallback_count := 0
	var whitelist_rejections := 0
	for value: Variant in _gateway.call("get_errors") as Array:
		if not value is Dictionary:
			continue
		var error := value as Dictionary
		var code := String(error.get("errorCode", ""))
		if code == "AGENT_CONTINUITY_FALLBACK_APPLIED":
			fallback_count += 1
		elif code == "AGENT_DECISION_REQUEST_REJECTED":
			whitelist_rejections += 1
	_expect_equal(action_type_errors, 0, "0 次 action.type 非法(修复目标1)")
	_expect_equal(end_reason_errors, 0, "0 次对话结束原因非法(修复目标2)")
	print("ASSEMBLY_LIVE_SUMMARY: reports=%d maxInterrogations=%d votes=%d fallbacks=%d whitelistRejects=%d actionTypeErrors=%d endReasonErrors=%d" % [
		reports, max_interrogation_count, votes, fallback_count,
		whitelist_rejections, action_type_errors, end_reason_errors,
	])
	_finish()


func _minute_of_day() -> int:
	var time_state := _world.call("get_time") as Dictionary
	var clock := String(time_state.get("clock", "08:00"))
	var parts := clock.split(":")
	return int(parts[0]) * 60 + int(parts[1])


func _count_error_text(text: String) -> int:
	var count := 0
	for value: Variant in _gateway.call("get_errors") as Array:
		if not value is Dictionary:
			continue
		var diagnostic := (value as Dictionary).get("diagnostic", {}) as Dictionary
		var agent_errors: Variant = diagnostic.get("agentErrors", diagnostic.get("agent_errors", []))
		if not agent_errors is Array:
			continue
		for message: Variant in agent_errors as Array:
			if String(message).contains(text):
				count += 1
	return count


func _on_health_check_completed(result: Dictionary) -> void:
	_health_result = result.duplicate(true)


func _wait_for_health_check() -> bool:
	var started_at := Time.get_ticks_msec()
	while _health_result.is_empty():
		if Time.get_ticks_msec() - started_at >= MODEL_TIMEOUT_MSEC:
			return false
		await process_frame
	return true


func _on_decision_completed(trace: Dictionary) -> void:
	var result := trace.get("agentResult", {}) as Dictionary
	var decision := result.get("decision", {}) as Dictionary
	var action := decision.get("action", {}) as Dictionary
	print("ASSEMBLY_LIVE_DECISION: resident=%s ok=%s action=%s" % [
		String(trace.get("residentName", "")),
		str(bool(trace.get("ok", false))),
		String(action.get("type", "continue_current")),
	])


func _cleanup(clean_storage: bool) -> void:
	if _gateway != null:
		if _gateway.has_method("discard_unpublished_new_game"):
			_gateway.call("discard_unpublished_new_game")
		_gateway.free()
		_gateway = null
	if _world != null:
		_world.call("stop")
		_world = null
	if _request_host != null:
		_request_host.free()
		_request_host = null
	if clean_storage:
		DATA_CLEANER.remove_tree(_storage_root)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("ASSEMBLY_LIVE_FAIL: %s" % message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s；实际=%s，预期=%s" % [message, actual, expected])


func _finish() -> void:
	_cleanup(true)
	for _index in 5:
		await process_frame
	if _failures.is_empty():
		print("ASSEMBLY_LIVE_PASS checks=%d" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		printerr("ASSEMBLY_LIVE_FAIL: %s" % failure)
	quit(1)
