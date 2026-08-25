extends SceneTree
## diag_vote_live.gd — 投票链路真实 API 实测
##
## 目标：验证真实模型（tokenrhythm 网关 + deepseek-v4-flash-0731，thinking disabled）
## 收到含 exile_vote 强约束的 prompt 后，决策 JSON 是否真的输出 exile_vote。
##
## 流程：
##   1) 读用户存档 provider（302-ai）→ configure + health check（真实 API）
##   2) 世界 start_formal（catalog 狼人杀版 16 居民，含 3 卧底+警察）
##   3) 大步 advance 推进到第2天 11:00（start_vote_round 开启投票并唤醒全镇）
##   4) 停止推进时钟，持续 pump 消化所有居民的投票决策（window 内 forced=true）
##   5) 统计：模型输出 exile_vote 次数 / submit_vote 记录数 / settle 结果
##
## 关键对照：节流器在 --script 树外不生效（is_inside_tree=false），pump 全速
## （并发 MAX=3 仍限制）→ 排除"排队来不及"因素，纯看模型是否遵守投票约束。
##
## 用法：Godot --headless --path game --script res://tests/diag_vote_live.gd
## 环境变量：AI_TOWN_LIVE_SECONDS（总时长，默认 300）/ AI_TOWN_LIVE_PROVIDER+MODEL 覆盖
## 注意：会真实调用 tokenrhythm API（消耗用户额度，约 ¥0.2-1/次）。

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
const VOTE_DAY2_11_00_MINUTE := 1440 + 660  # 2100
const VOTE_DAY2_12_30_MINUTE := 1440 + 750  # 2190

var _health_result: Dictionary = {}
var _completed_traces: Array[Dictionary] = []
var _gateway: Node = null
var _world: RefCounted = null
var _request_host: Node = null
var _storage_root := "user://tests/diag-vote-live/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var total_seconds := int(OS.get_environment("AI_TOWN_LIVE_SECONDS"))
	if total_seconds <= 0:
		total_seconds = 300
	print("VOTE_LIVE_START: total=%ds" % total_seconds)

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
		printerr("VOTE_LIVE_UNAVAILABLE: PROVIDER 与 MODEL 必须同时设置")
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
			"VOTE_LIVE_UNAVAILABLE: %s"
			% String(saved.get("errorCode", "PROVIDER_NOT_CONFIGURED"))
		)
		quit(2)
		return
	var provider_id := String(saved.get("providerId", ""))
	var model_id := String(saved.get("modelId", ""))
	print("VOTE_LIVE_CONTEXT: provider=%s model=%s" % [provider_id, model_id])

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
		printerr("VOTE_LIVE_COMPILE_FAIL: %s" % [compiled])
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
		"VOTE_LIVE_OPENING: residents=%d identities=%d"
		% [(opening.get("residents", []) as Array).size(), identities.size()]
	)

	# —— Provider 服务（真实网络）——
	_request_host = Node.new()
	_request_host.name = "DiagVoteLiveProviderHost"
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
		printerr("VOTE_LIVE_PROVIDER_FAIL: %s" % [provider_config])
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
			"VOTE_LIVE_HEALTH_FAIL: started=%s result=%s"
			% [health_started, _health_result]
		)
		_cleanup(false)
		quit(2)
		return
	print(
		"VOTE_LIVE_HEALTH_PASS: provider=%s model=%s latencyMs=%s"
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
		printerr("VOTE_LIVE_WORLD_FAIL: %s" % [started])
		_cleanup(false)
		quit(1)
		return
	var werewolf_ids: Array = _world.call("_undercover_resident_ids")
	print(
		"VOTE_LIVE_WORLD: 卧底=%s feature_active=%s"
		% [
			", ".join(werewolf_ids as Array),
			str(bool(_world.get("WEREWOLF_RUNTIME") != null)),
		]
	)

	# —— Agent 系统 + Gateway ——
	var agent_system: RefCounted = AGENT_SYSTEM.new()
	var storage := agent_system.call(
		"configure_test_runtime_storage",
		_storage_root,
	) as Dictionary
	if storage.get("ok") != true:
		printerr("VOTE_LIVE_STORAGE_FAIL: %s" % [storage])
		_cleanup(false)
		quit(1)
		return
	_gateway = GATEWAY.new()
	_gateway.name = "DiagVoteLiveGateway"
	_gateway.set("_agent_system", agent_system)
	_gateway.debug_decision_completed.connect(_on_decision_completed)
	root.add_child(_gateway)
	var configured := _gateway.call(
		"configure_session",
		{
			"sessionId": "diag-vote-live-%d" % Time.get_ticks_usec(),
			"slotId": "diag-vote-live-%d" % OS.get_process_id(),
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
			"VOTE_LIVE_GATEWAY_FAIL: configure=%s bind=%s" % [configured, bound]
		)
		_cleanup(false)
		quit(1)
		return

	# —— 主循环：推进到第2天 11:00 → 停钟等投票 → 12:30 开票 ——
	var started_ms := Time.get_ticks_msec()
	var total_end_ms := started_ms + total_seconds * 1000
	var reached_vote_window := false
	var window_reached_ms := 0
	var settle_done := false
	var advance_accumulator := 0.0

	while Time.get_ticks_msec() < total_end_ms:
		_gateway.call("_advance_agent_preparation")
		var absolute_minute := int(
			(_world.get("_environment") as Object).call(
				"get_absolute_minute"
			)
		)
		if not reached_vote_window and absolute_minute < VOTE_DAY2_11_00_MINUTE:
			# 大步推进（60 倍速等效），每帧 120 游戏分钟
			advance_accumulator += 1.0
			if advance_accumulator >= 1.0:
				advance_accumulator = 0.0
				_world.call("advance", 120.0)
		elif not reached_vote_window:
			reached_vote_window = true
			window_reached_ms = Time.get_ticks_msec()
			var vote := (
				(_world.get("_werewolf_state") as Dictionary).get(
					"vote",
					{},
				) as Dictionary
			)
			print(
				"VOTE_LIVE_WINDOW: 第2天 11:00 到达, 候选 %d 人, 唤醒全镇"
				% (vote.get("candidateNames", []) as Array).size()
			)
		elif not settle_done:
			# 投票窗口：停钟，泵完全部决策（模型无节流压力，纯看是否输出 exile_vote）
			var votes := (
				((_world.get("_werewolf_state") as Dictionary).get(
					"vote",
					{},
				) as Dictionary).get("votes", {}) as Dictionary
			)
			if votes.size() > 0:
				print(
					"VOTE_LIVE_SUBMIT: 已收到 %d 票 %s"
					% [votes.size(), JSON.stringify(votes)]
				)
			if (
				_completed_traces.size() >= identities.size()
				or Time.get_ticks_msec() - window_reached_ms >= 120000
			):
				print(
					"VOTE_LIVE_SETTLE: 推进到 12:30 开票 (traces=%d/%d)"
					% [_completed_traces.size(), identities.size()]
				)
				_world.call("advance", float(VOTE_DAY2_12_30_MINUTE - absolute_minute))
				settle_done = true
		_gateway.call("pump", 1)
		await process_frame

	_report(provider_id, model_id)
	_cleanup(true)
	quit(0)


func _report(provider_id: String, model_id: String) -> void:
	var vote_state := (
		(_world.get("_werewolf_state") as Dictionary).get("vote", {}) as Dictionary
	)
	var votes := vote_state.get("votes", {}) as Dictionary
	var exile_in_decisions := 0
	var exile_targets: Array[String] = []
	for trace: Dictionary in _completed_traces:
		var result := trace.get("agentResult", {}) as Dictionary
		var decision := result.get("decision", {}) as Dictionary
		if decision.has("exile_vote"):
			exile_in_decisions += 1
			var vote_value := decision.get("exile_vote", {}) as Dictionary
			exile_targets.append(
				String(vote_value.get("target_resident_name", ""))
			)
	var report := {
		"provider": provider_id,
		"model": model_id,
		"completedTraces": _completed_traces.size(),
		"modelOutputExileVote": exile_in_decisions,
		"exileTargets": exile_targets,
		"submittedVotes": votes.size(),
		"settled": vote_state.is_empty(),
	}
	print("VOTE_LIVE_REPORT: %s" % JSON.stringify(report))
	var verdict := ""
	if votes.size() > 0:
		verdict = "有人投票 → 模型遵守 exile_vote 约束"
	elif exile_in_decisions > 0:
		verdict = "模型输出了 exile_vote 但提交链丢失 → 提交链问题"
	else:
		verdict = "模型未输出 exile_vote → 模型/网关无视投票约束（prompt 渲染正常）"
	print("VOTE_LIVE_VERDICT: %s" % verdict)
	print("VOTE_LIVE_DONE")


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
	var has_exile := decision.has("exile_vote")
	var exile_target := ""
	if has_exile:
		exile_target = String(
			(decision.get("exile_vote", {}) as Dictionary).get(
				"target_resident_name",
				"",
			)
		)
	var submission := trace.get("worldSubmission", {}) as Dictionary
	print(
		"VOTE_LIVE_DECISION: %s ok=%s action=%s exile_vote=%s target=%s err=%s"
		% [
			String(trace.get("residentName", "")),
			str(bool(trace.get("ok", false))),
			String(action.get("type", "continue_current")),
			str(has_exile),
			exile_target,
			String(submission.get("errorCode", "")),
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
