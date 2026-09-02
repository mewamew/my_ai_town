extends SceneTree
## 真实会话实测（headless 开新存档 + 真实 provider）
##
## 目标：验证 0.5/s 节流器决策下 tokenrhythm 网关的限流行为。
##   - 段1（0-300s）：pump 每 2s 一次（≈0.5/s 请求节奏），世界时钟 60 倍速连续推进
##     → 预期 rate_limit = 0（低于平台限速线）
##   - 段2（300-360s）：先大步 advance 制造一波居民决策积压，再每 0.2s pump
##     （≈5/s）→ 预期 rate_limit > 0（对照：平台限速仍然存在）
##
## 用法：
##   Godot --headless --path game --script res://tests/diag_live_session.gd
##   可选环境变量：
##     AI_TOWN_LIVE_PROVIDER / AI_TOWN_LIVE_MODEL  覆盖 provider/model（默认读用户存档）
##     AI_TOWN_LIVE_SECONDS                        总时长（默认 360）
## 输出：LIVE_SESSION_REPORT JSON（分段 rate_limit 统计 / 错误分布 / 决策 trace）
##
## 注意：会真实调用 tokenrhythm API（消耗用户 key 额度，约 ¥0.5-1/次运行）。

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
const ADVANCE_GAME_MINUTES := 120.0
const SEGMENT1_SECONDS := 360
const SEGMENT2_SECONDS := 120
const PUMP_INTERVAL_SEG1_MSEC := 2000
const PUMP_INTERVAL_SEG2_MSEC := 200

var _health_result: Dictionary = {}
var _completed_traces: Array[Dictionary] = []
var _gateway: Node = null
var _world: RefCounted = null
var _request_host: Node = null
var _storage_root := "user://tests/diag-live-session/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var total_seconds := int(OS.get_environment("AI_TOWN_LIVE_SECONDS"))
	if total_seconds <= 0:
		total_seconds = SEGMENT1_SECONDS + SEGMENT2_SECONDS
	var seg1_override := int(OS.get_environment("AI_TOWN_LIVE_SEG1"))
	var seg1_seconds: int = mini(total_seconds, SEGMENT1_SECONDS)
	if seg1_override >= 0 and seg1_override <= total_seconds:
		seg1_seconds = seg1_override
	var seg2_seconds := total_seconds - seg1_seconds
	print(
		"LIVE_SESSION_START: total=%ds seg1=%ds(0.5/s) seg2=%ds(5/s) advance=%.0f游戏分钟/次"
		% [total_seconds, seg1_seconds, seg2_seconds, ADVANCE_GAME_MINUTES]
	)

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
		printerr(
			"LIVE_SESSION_UNAVAILABLE: AI_TOWN_LIVE_PROVIDER 与 "
			+ "AI_TOWN_LIVE_MODEL 必须同时设置"
		)
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
			"LIVE_SESSION_UNAVAILABLE: %s"
			% String(saved.get("errorCode", "PROVIDER_NOT_CONFIGURED"))
		)
		quit(2)
		return
	var provider_id := String(saved.get("providerId", ""))
	var model_id := String(saved.get("modelId", ""))
	print(
		"LIVE_SESSION_CONTEXT: provider=%s model=%s"
		% [provider_id, model_id]
	)

	# —— 编译新游戏开局（等价"新开存档"）——
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
		printerr("LIVE_SESSION_COMPILE_FAIL: %s" % [compiled])
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
		"LIVE_SESSION_OPENING: residents=%d identities=%d"
		% [(opening.get("residents", []) as Array).size(), identities.size()]
	)

	# —— Provider 服务（真实网络）——
	_request_host = Node.new()
	_request_host.name = "DiagLiveSessionProviderHost"
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
		printerr("LIVE_SESSION_PROVIDER_FAIL: %s" % [provider_config])
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
			"LIVE_SESSION_HEALTH_FAIL: started=%s result=%s"
			% [health_started, _health_result]
		)
		_cleanup(false)
		quit(2)
		return
	print(
		"LIVE_SESSION_HEALTH_PASS: provider=%s model=%s latencyMs=%s"
		% [
			provider_id,
			model_id,
			String(_health_result.get("latencyMs", "")),
		]
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
		printerr("LIVE_SESSION_WORLD_FAIL: %s" % [started])
		_cleanup(false)
		quit(1)
		return
	# 官方倍率仅允许 1/2/3；游戏 UI 的"60 倍"由大步 advance 等效实现，
	# 这里同样用 ADVANCE_GAME_MINUTES 大步推进模拟高速世界。

	# —— Agent 系统 + Gateway ——
	var agent_system: RefCounted = AGENT_SYSTEM.new()
	var storage := agent_system.call(
		"configure_test_runtime_storage",
		_storage_root,
	) as Dictionary
	if storage.get("ok") != true:
		printerr("LIVE_SESSION_STORAGE_FAIL: %s" % [storage])
		_cleanup(false)
		quit(1)
		return
	_gateway = GATEWAY.new()
	_gateway.name = "DiagLiveSessionGateway"
	_gateway.set("_agent_system", agent_system)
	_gateway.debug_decision_completed.connect(_on_decision_completed)
	_gateway.debug_decision_dispatched.connect(
		func(trace: Dictionary) -> void:
			print(
				"LIVE_SESSION_DISPATCHED: resident=%s id=%s attempt=%d"
				% [
					String(trace.get("residentId", "")),
					String(trace.get("decisionId", "")).left(12),
					int(trace.get("attempt", 0)),
				]
			)
	)
	root.add_child(_gateway)
	var configured := _gateway.call(
		"configure_session",
		{
			"sessionId": "diag-live-%d" % Time.get_ticks_usec(),
			"slotId": "diag-live-%d" % OS.get_process_id(),
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
			"LIVE_SESSION_GATEWAY_FAIL: configure=%s bind=%s"
			% [configured, bound]
		)
		_cleanup(false)
		quit(1)
		return
	print("LIVE_SESSION_READY: gateway bound, session active")
	print(
		"LIVE_SESSION_DIAG: is_paused=%s lifecycle=%s"
		% [
			str(bool(_world.call("is_paused"))),
			JSON.stringify(_world.call("get_lifecycle_state")),
		]
	)

	# —— 主循环：段1（0.5/s 节奏）→ 段2（5/s 对照）——
	var started_ms := Time.get_ticks_msec()
	var seg1_end_ms := started_ms + seg1_seconds * 1000
	var total_end_ms := started_ms + total_seconds * 1000
	var last_pump_ms := 0
	var pump_interval_ms := PUMP_INTERVAL_SEG1_MSEC
	var last_report_ms := started_ms
	var dispatched_total := 0
	var diag_counter := 0

	while Time.get_ticks_msec() < total_end_ms:
		var now_ms := Time.get_ticks_msec()
		if now_ms >= seg1_end_ms and pump_interval_ms == PUMP_INTERVAL_SEG1_MSEC:
			# 段2 切换：同一大步推进节奏下改为快速 pump（5/s 对照）
			print("LIVE_SESSION_SEG2_START: pump 5/s 对照段")
			pump_interval_ms = PUMP_INTERVAL_SEG2_MSEC
		# 每帧推进准备队列（等价 TownRuntime 树内帧预算：refresh 多帧完成
		# → dispatch → provider 请求发出）。--script 模式 root 不在场景树内，
		# pump_frame_budgeted 会退化成 pump，只能直接调用私有推进。
		_gateway.call("_advance_agent_preparation")
		if now_ms - last_pump_ms >= pump_interval_ms:
			if pump_interval_ms == PUMP_INTERVAL_SEG1_MSEC:
				# 大步推进模拟 60 倍速世界：每 pump 一次跨 120 游戏分钟，
				# life_rhythm 锚点（每 150-300 游戏分钟一波）持续制造决策积压。
				_world.call("advance", ADVANCE_GAME_MINUTES)
			# 段2：只快速 pump 消化积压（不再推进时钟），对照 5/s 请求率
			var dispatched := int(_gateway.call("pump", 1))
			if dispatched > 0:
				dispatched_total += dispatched
			last_pump_ms = now_ms
		diag_counter += 1
		if diag_counter % 400 == 0:
			var prep_queue := _gateway.get("_agent_preparation_queue") as Array
			var inflight := _gateway.get("_inflight") as Dictionary
			var inflight_info: Array = []
			for key: Variant in inflight:
				var entry := inflight[key] as Dictionary
				inflight_info.append({
					"id": String(key).left(12),
					"resident": String(entry.get("residentId", "")),
					"stage": String(entry.get("preparationStage", "")),
					"superseded": bool(entry.get("superseded", false)),
					"ageMs": Time.get_ticks_msec()
						- int(entry.get("startedAtMsec", 0)),
					"attempt": int(entry.get("attempt", 0)),
				})
			print(
				"LIVE_SESSION_DIAG: loop=%d elapsed=%ds time=%s prepQueue=%d inflight=%s"
				% [
					diag_counter,
					(now_ms - started_ms) / 1000,
					JSON.stringify(_world.call("get_time")),
					prep_queue.size(),
					JSON.stringify(inflight_info),
				]
			)
		if now_ms - last_report_ms >= 30000:
			last_report_ms = now_ms
			print(
				"LIVE_SESSION_PROGRESS: elapsed=%ds dispatched=%d traces=%d errors=%d"
				% [
					(now_ms - started_ms) / 1000,
					dispatched_total,
					_completed_traces.size(),
					(_gateway.call("get_errors") as Array).size(),
				]
			)
		await process_frame

	_report(provider_id, model_id, seg1_seconds, dispatched_total)
	_cleanup(true)
	quit(0)


func _report(
	provider_id: String,
	model_id: String,
	seg1_seconds: int,
	dispatched_total: int,
) -> void:
	var errors := _gateway.call("get_errors") as Array
	var rate_limit_errors := 0
	var fallback_count := 0
	var other_errors: Array[Dictionary] = []
	for value: Variant in errors:
		if not value is Dictionary:
			continue
		var error := value as Dictionary
		var diagnostic := error.get("diagnostic", {}) as Dictionary
		var error_type := String(
			diagnostic.get("error_type", "")
		)
		var error_code := String(error.get("errorCode", ""))
		if error_type == "rate_limit":
			rate_limit_errors += 1
		elif error_code == "AGENT_CONTINUITY_FALLBACK_APPLIED":
			fallback_count += 1
		else:
			other_errors.append({
				"resident": String(error.get("residentName", "")),
				"errorCode": error_code,
				"errorType": error_type,
				"retryable": bool(error.get("retryable", false)),
				"agentErrors": (
					diagnostic.get("agentErrors", []) as Array
				).duplicate(true),
			})
	var trace_ok := 0
	var trace_failed := 0
	var action_types := {}
	for trace: Dictionary in _completed_traces:
		if bool(trace.get("ok", false)):
			trace_ok += 1
		else:
			trace_failed += 1
		var result := trace.get("agentResult", {}) as Dictionary
		var decision := result.get("decision", {}) as Dictionary
		var action := decision.get("action", {}) as Dictionary
		var action_type := String(action.get("type", "continue_current"))
		action_types[action_type] = int(action_types.get(action_type, 0)) + 1
	var time_state := _world.call("get_time") as Dictionary
	var report := {
		"provider": provider_id,
		"model": model_id,
		"segment1Seconds": seg1_seconds,
		"segment1Rate": "0.5/s",
		"segment2Rate": "5/s",
		"dispatched": dispatched_total,
		"decisionTraces": {
			"ok": trace_ok,
			"failed": trace_failed,
		},
		"actionTypes": action_types,
		"errors": {
			"rateLimit": rate_limit_errors,
			"continuityFallback": fallback_count,
			"other": other_errors,
		},
		"gameTime": {
			"day": time_state.get("day", 1),
			"clock": time_state.get("clock", "08:00"),
		},
	}
	print("LIVE_SESSION_REPORT: %s" % JSON.stringify(report))
	var verdict := "rate_limit=0 → 0.5/s 低于平台限速线" \
		if rate_limit_errors == 0 \
		else "rate_limit=%d → 仍有限流" % rate_limit_errors
	print("LIVE_SESSION_VERDICT: %s" % verdict)
	print("LIVE_SESSION_DONE")


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
	var submission := trace.get("worldSubmission", {}) as Dictionary
	var diagnostic := trace.get("diagnostic", {}) as Dictionary
	var error_code := String(
		submission.get(
			"errorCode",
			diagnostic.get("error_type", ""),
		),
	)
	print(
		"LIVE_SESSION_DECISION: resident=%s ok=%s action=%s target=%s error=%s"
		% [
			String(trace.get("residentName", "")),
			str(bool(trace.get("ok", false))),
			String(action.get("type", "continue_current")),
			String(
				action.get(
					"place",
					action.get(
						"activity_id",
						action.get(
							"recipient_resident_id",
							action.get("target_resident_id", ""),
						),
					),
				),
			),
			error_code,
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
