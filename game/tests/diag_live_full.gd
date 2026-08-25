extends SceneTree
## diag_live_full.gd — 真实 API 综合实测（新开存档 + 持续监测）
##
## 目标：用真实模型（tokenrhythm 网关 + deepseek-v4-flash-0731，thinking disabled）
## 新开一局完整跑通狼人杀主要链路，并持续输出日志供监测：
##   · 行为流日志（感知到/收到选项/可选/选择了）——finalize 补日志点后的首次真实验证
##   · 投票（第2天 8:00 大会 → 12:30 开票，3bdff56 事件白名单 + ID 容错首次真实验证）
##   · 夜间技能（使用技能：白芷守诊/许照查验/卧底嫁祸）
##   · 暗杀（含警察护盾/巡逻威慑）、追踪装置、查案
##   · 留档写盘（F:/my_ai_town_upstream/logs/requests/role/）
##   · 错误统计（rate_limit/reasoning_only/server/agent_runtime...）
##
## 流程（状态机）：
##   1) 配置 + health check（真实 API）
##   2) start_formal 新开存档 + gateway 装配（含 role archive）
##   3) 大步推进到第1天 20:00 → 停钟等夜间技能提交（90s 上限）
##   4) 推进到第2天 8:00 → 停钟等投票消化（150s 上限）
##   5) 推进到 12:30 开票 → 记录 settle
##   6) 持续推进观察（行为流/暗杀/追踪/查案），直到总时长
##
## 用法：Godot --headless --path game --script res://tests/diag_live_full.gd
## 环境变量：AI_TOWN_LIVE_SECONDS（总时长，默认 600）
## 注意：会真实调用 tokenrhythm API（用户已确认不计话费）。

const SOURCE_DIR := "res://world/data/town/source"
const BUILDER := preload(
	"res://world/data/town/TownWorldDataBuilder.gd"
)
const RESIDENT_CATALOG := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)
const COMPILER := preload(
	"res://world/presentation/session/TownNewGameOpeningCompiler.gd"
)
const PROVIDER_SETTINGS := preload(
	"res://world/presentation/ui/TownProviderSettingsService.gd"
)
const PROVIDER_SERVICE := preload(
	"res://world/integration/TownAgentProviderService.gd"
)
const AGENT_SYSTEM := preload("res://agent/AgentSystem.gd")
const GATEWAY := preload(
	"res://world/integration/TownWorldAgentGateway.gd"
)
const WORLD := preload(
	"res://world/runtime/TownWorldRuntime.gd"
)
const DATA_CLEANER := preload(
	"res://tests/support/UserTestDataCleaner.gd"
)

const MODEL_TIMEOUT_MSEC := 90000
const NIGHT1_START_MINUTE := 1200  # 第1天 20:00（第1天从 0 开始）
const VOTE_DAY2_08_00_MINUTE := 1440 + 480  # 第2天 8:00
const VOTE_DAY2_12_30_MINUTE := 1440 + 750  # 第2天 12:30
const ROLE_ARCHIVE_ROOT := "F:/my_ai_town_upstream/logs/requests/role"

var _health_result: Dictionary = {}
var _completed_traces: Array[Dictionary] = []
var _gateway: Node = null
var _world: RefCounted = null
var _request_host: Node = null
var _storage_root := "user://tests/diag-live-full/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]
var _trace_error_counts: Dictionary = {}
var _trace_action_counts: Dictionary = {}
var _night_skill_submits: Array[String] = []
var _role_archive_files_before := 0
var _settle_vote_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _count_role_archive_files() -> int:
	var dir := DirAccess.open(ROLE_ARCHIVE_ROOT)
	if dir == null:
		return 0
	var count := 0
	for entry: String in dir.get_files():
		if entry.ends_with(".json"):
			count += 1
	return count


func _run() -> void:
	var total_seconds := int(OS.get_environment("AI_TOWN_LIVE_SECONDS"))
	if total_seconds <= 0:
		total_seconds = 600
	print("LIVE_FULL_START: total=%ds" % total_seconds)

	# —— 读取用户存档的真实 provider 配置（302-ai → tokenrhythm.studio）——
	var saved := (
		PROVIDER_SETTINGS.new().load_saved_runtime_configuration()
		as Dictionary
	)
	var provider_override := OS.get_environment(
		"AI_TOWN_LIVE_PROVIDER"
	).strip_edges()
	var model_override := OS.get_environment(
		"AI_TOWN_LIVE_MODEL"
	).strip_edges()
	if provider_override.is_empty() != model_override.is_empty():
		printerr("LIVE_FULL_UNAVAILABLE: PROVIDER 与 MODEL 必须同时设置")
		quit(2)
		return
	if not provider_override.is_empty():
		saved["providerId"] = provider_override
		saved["modelId"] = model_override
	if (
		saved.get("ok") != true
		or String(saved.get("providerId", "")).is_empty()
		or String(saved.get("modelId", "")).is_empty()
	):
		printerr(
			"LIVE_FULL_UNAVAILABLE: %s"
			% String(saved.get("errorCode", "PROVIDER_NOT_CONFIGURED"))
		)
		quit(2)
		return
	var provider_id := String(saved.get("providerId", ""))
	var model_id := String(saved.get("modelId", ""))
	print("LIVE_FULL_CONTEXT: provider=%s model=%s" % [provider_id, model_id])

	# —— 编译新游戏开局（catalog 狼人杀版 16 居民）——
	var world_data := BUILDER.build_from_source(SOURCE_DIR)
	var view_model := RESIDENT_CATALOG.build_view_model(
		provider_id,
		model_id,
		true,
		1,
	) as Dictionary
	var selection := (
		view_model.get("data", {}) as Dictionary
	).duplicate(true)
	selection["selected_resident_ids"] = (
		selection.get("recommended_resident_ids", []) as Array
	).duplicate()
	RESIDENT_CATALOG.update_confirmation_payload(
		selection,
		provider_id,
		model_id,
		2,
	)
	var compiled := COMPILER.compile(
		selection.get("confirmation_payload", {}) as Dictionary,
		world_data,
		RESIDENT_CATALOG.load_catalog(),
	) as Dictionary
	if compiled.get("ok") != true:
		printerr("LIVE_FULL_COMPILE_FAIL: %s" % [compiled])
		quit(1)
		return
	var opening := compiled.get("openingConfig", {}) as Dictionary
	var bindings := (
		compiled.get("residentBindings", []) as Array[Dictionary]
	)
	var identities: Array[Dictionary] = []
	for binding: Dictionary in bindings:
		identities.append({
			"residentId": String(binding.get("residentId", "")),
			"residentName": String(binding.get("residentName", "")),
		})
	print(
		"LIVE_FULL_OPENING: residents=%d identities=%d"
		% [(opening.get("residents", []) as Array).size(), identities.size()]
	)

	# —— Provider 服务（真实网络）——
	_request_host = Node.new()
	_request_host.name = "DiagLiveFullProviderHost"
	root.add_child(_request_host)
	var providers: RefCounted = PROVIDER_SERVICE.new()
	var provider_config := providers.call(
		"configure",
		{
			"capabilityMode": "formal",
			"source": "saved-settings",
			"allowFake": false,
			"providerConfigs": (
				saved.get("providerConfigs", {}) as Dictionary
			).duplicate(true),
		},
		_request_host,
	) as Dictionary
	if provider_config.get("ok") != true:
		printerr("LIVE_FULL_PROVIDER_FAIL: %s" % [provider_config])
		_cleanup(false)
		quit(2)
		return
	_health_result = {}
	var health_started := providers.call(
		"request_health_check",
		[{"providerId": provider_id, "modelId": model_id}],
		_on_health_check_completed,
	) as Dictionary
	if (
		health_started.get("accepted") != true
		or not await _wait_for_health_check()
		or String(_health_result.get("status", "")) != "available"
	):
		printerr(
			"LIVE_FULL_HEALTH_FAIL: started=%s result=%s"
			% [health_started, _health_result]
		)
		_cleanup(false)
		quit(2)
		return
	print(
		"LIVE_FULL_HEALTH_PASS: provider=%s model=%s latencyMs=%s"
		% [provider_id, model_id, String(_health_result.get("latencyMs", ""))]
	)

	# —— 世界（start_formal = 正式新开局）——
	_world = WORLD.new()
	var started := _world.call(
		"start_formal",
		world_data,
		opening,
		identities,
	) as Dictionary
	if started.get("ok") != true:
		printerr("LIVE_FULL_WORLD_FAIL: %s" % [started])
		_cleanup(false)
		quit(1)
		return
	var werewolf_ids: Array = _world.call("_undercover_resident_ids")
	print(
		"LIVE_FULL_WORLD: 卧底=%s" % ", ".join(werewolf_ids as Array)
	)

	# —— Agent 系统 + Gateway ——
	var agent_system: RefCounted = AGENT_SYSTEM.new()
	var storage := agent_system.call(
		"configure_test_runtime_storage",
		_storage_root,
	) as Dictionary
	if storage.get("ok") != true:
		printerr("LIVE_FULL_STORAGE_FAIL: %s" % [storage])
		_cleanup(false)
		quit(1)
		return
	_gateway = GATEWAY.new()
	_gateway.name = "DiagLiveFullGateway"
	_gateway.set("_agent_system", agent_system)
	_gateway.debug_decision_completed.connect(_on_decision_completed)
	root.add_child(_gateway)
	var configured := _gateway.call(
		"configure_session",
		{
			"sessionId": "diag-live-full-%d" % Time.get_ticks_usec(),
			"slotId": "diag-live-full-%d" % OS.get_process_id(),
			"saveRevision": 0,
			"restorePending": false,
			"residentIdentities": identities.duplicate(true),
			"residentBindings": bindings.duplicate(true),
			"openingConfig": opening.duplicate(true),
			"capabilityMode": "formal",
			"formalReady": true,
		},
		providers,
		_request_host,
	) as Dictionary
	var bound := (
		_gateway.call("bind_world", _world) as Dictionary
		if configured.get("ok") == true
		else {}
	)
	if configured.get("ok") != true or bound.get("ok") != true:
		printerr(
			"LIVE_FULL_GATEWAY_FAIL: configure=%s bind=%s" % [configured, bound]
		)
		_cleanup(false)
		quit(1)
		return
	_role_archive_files_before = _count_role_archive_files()
	print(
		"LIVE_FULL_GATEWAY_PASS: role_archive_files_before=%d"
		% _role_archive_files_before
	)

	# —— 主循环状态机 ——
	var started_ms := Time.get_ticks_msec()
	var total_end_ms := started_ms + total_seconds * 1000
	var phase := "advance_night1"
	var phase_started_ms := started_ms
	var settle_result := ""
	var last_phase_print := ""

	while Time.get_ticks_msec() < total_end_ms:
		_gateway.call("_advance_agent_preparation")
		var absolute_minute := int(
			(_world.get("_environment") as Object).call(
				"get_absolute_minute"
			)
		)
		var minute_of_day := posmod(absolute_minute, 1440)
		var day_index := absolute_minute / 1440
		# 阶段推进：停钟等消化 / 大步推进
		match phase:
			"advance_night1":
				if absolute_minute < NIGHT1_START_MINUTE:
					_world.call("advance", 120.0)
				else:
					phase = "collect_night1"
					phase_started_ms = Time.get_ticks_msec()
					print(
						"LIVE_FULL_NIGHT1: 第%d天 20:00 夜间行动开始, 停钟等技能提交"
						% (day_index + 1)
					)
			"collect_night1":
				if (
					Time.get_ticks_msec() - phase_started_ms >= 90000
					or _night_skill_submits.size() >= 3
				):
					phase = "advance_vote"
					print(
						"LIVE_FULL_NIGHT1_DONE: 夜间技能提交 %d 个 %s"
						% [_night_skill_submits.size(), str(_night_skill_submits)]
					)
			"advance_vote":
				if absolute_minute < VOTE_DAY2_08_00_MINUTE:
					_world.call("advance", 120.0)
				else:
					phase = "collect_vote"
					phase_started_ms = Time.get_ticks_msec()
					var vote := (
						(_world.get("_werewolf_state") as Dictionary).get(
							"vote",
							{},
						) as Dictionary
					)
					print(
						"LIVE_FULL_VOTE_WINDOW: 第2天 8:00 到达, 候选 %d 人, 停钟等投票"
						% (vote.get("candidateIds", []) as Array).size()
					)
			"collect_vote":
				var votes := (
					((_world.get("_werewolf_state") as Dictionary).get(
						"vote",
						{},
					) as Dictionary).get("votes", {}) as Dictionary
				)
				if votes.size() > 0 and last_phase_print != str(votes.size()):
					last_phase_print = str(votes.size())
					print(
						"LIVE_FULL_VOTE_SUBMIT: 已收到 %d 票"
						% votes.size()
					)
				if (
					_completed_traces.size() >= identities.size()
					or Time.get_ticks_msec() - phase_started_ms >= 150000
				):
					_settle_vote_count = votes.size()  # 记录于清空前的最后可靠时点
					phase = "settle"
					print(
						"LIVE_FULL_SETTLE: 推进到 12:30 开票 (traces=%d/%d, votes=%d)"
						% [
							_completed_traces.size(),
							identities.size(),
							votes.size(),
						]
					)
			"settle":
				if absolute_minute < VOTE_DAY2_12_30_MINUTE:
					_world.call("advance", 120.0)
				else:
					var vote_state := (
						(_world.get("_werewolf_state") as Dictionary).get(
							"vote",
							{},
						) as Dictionary
					)
					_settle_vote_count = max(
						_settle_vote_count,
						(vote_state.get("votes", {}) as Dictionary).size(),
					)
					settle_result = (
						"settled" if vote_state.is_empty() else "vote_state_left"
					)
					phase = "observe"
					phase_started_ms = Time.get_ticks_msec()
					print(
						"LIVE_FULL_SETTLED: %s, 进入持续观察"
						% settle_result
					)
			"observe":
				# 持续大步推进（60 倍速等效），观察行为流/暗杀/追踪/查案
				_world.call("advance", 120.0)
			_:
				phase = "observe"
		_gateway.call("pump", 1)
		await process_frame

	_report(provider_id, model_id, settle_result)
	_cleanup(true)
	quit(0)


func _report(provider_id: String, model_id: String, settle_result: String) -> void:
	var archive_after := _count_role_archive_files()
	var report := {
		"provider": provider_id,
		"model": model_id,
		"totalTraces": _completed_traces.size(),
		"errorCounts": _trace_error_counts,
		"actionTypes": _trace_action_counts,
		"submittedVotes": _settle_vote_count,
		"settle": settle_result,
		"nightSkillSubmits": _night_skill_submits,
		"roleArchiveFiles": archive_after - _role_archive_files_before,
	}
	print("LIVE_FULL_REPORT: %s" % JSON.stringify(report))
	var verdict := ""
	if _trace_error_counts.has("rate_limit"):
		verdict = "存在限流，需关注节流/退避是否兜住"
	elif _trace_error_counts.is_empty() or (
		_trace_error_counts.size() == 1
		and _trace_error_counts.values()[0] <= 3
	):
		verdict = "基本无错误，链路健康"
	else:
		verdict = "存在错误，需逐项排查"
	print("LIVE_FULL_VERDICT: %s" % verdict)
	print("LIVE_FULL_DONE")


func _wait_for_health_check() -> bool:
	var started_at := Time.get_ticks_msec()
	while _health_result.is_empty():
		if Time.get_ticks_msec() - started_at >= MODEL_TIMEOUT_MSEC:
			return false
		await process_frame
	return true


func _on_health_check_completed(result: Dictionary) -> void:
	_health_result = result.duplicate(true)


func _on_decision_completed(trace: Dictionary) -> void:
	_completed_traces.append(trace.duplicate(true))
	var result := trace.get("agentResult", {}) as Dictionary
	var decision := result.get("decision", {}) as Dictionary
	var action := decision.get("action", {}) as Dictionary
	var action_type := String(action.get("type", "continue_current"))
	_trace_action_counts[action_type] = (
		int(_trace_action_counts.get(action_type, 0)) + 1
	)
	var ok := bool(trace.get("ok", false))
	if not ok:
		var submission := trace.get("worldSubmission", {}) as Dictionary
		var err_code := String(submission.get("errorCode", ""))
		if err_code.is_empty():
			err_code = String(submission.get("error", ""))
		if err_code.is_empty():
			err_code = "unknown"
		_trace_error_counts[err_code] = (
			int(_trace_error_counts.get(err_code, 0)) + 1
		)
	# 夜间技能提交（动作通道 + 附件通道）
	var has_night_skill := decision.has("night_skill")
	if action_type == "使用技能" or has_night_skill:
		var skill_id := ""
		if has_night_skill:
			skill_id = String(
				(decision.get("night_skill", {}) as Dictionary).get(
					"skill_id",
					"",
				)
			)
		else:
			skill_id = String(action.get("skill_id", ""))
		_night_skill_submits.append(
			"%s:%s" % [
				String(trace.get("residentName", "")),
				skill_id,
			]
		)
	print(
		"LIVE_FULL_DECISION: %s ok=%s action=%s err=%s"
		% [
			String(trace.get("residentName", "")),
			str(ok),
			action_type,
			String(
				(trace.get("worldSubmission", {}) as Dictionary).get(
					"errorCode",
					"",
				)
			),
		]
	)


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


func _finalize() -> void:
	if _gateway == null:
		DATA_CLEANER.remove_tree(_storage_root)
