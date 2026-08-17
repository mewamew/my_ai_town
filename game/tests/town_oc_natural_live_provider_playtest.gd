extends SceneTree


const RUN_ENV := "AI_TOWN_RUN_OC_NATURAL_LIVE"
const SOURCE_DIR := "res://world/data/town/source"
const MIN_MODEL_CALLS := 45
const MAX_MODEL_CALLS := 70
const MODEL_TIMEOUT_MSEC := 90000
const BUILDER := preload(
	"res://world/data/town/TownWorldDataBuilder.gd"
)
const RESIDENT_CATALOG := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)
const COMPILER := preload(
	"res://world/presentation/session/TownNewGameOpeningCompiler.gd"
)
const SOUL_PROFILE := preload("res://agent/soul/AgentSoulProfile.gd")
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
const TRACE_EVIDENCE := preload(
	"res://tests/support/TownAgentDecisionTraceEvidence.gd"
)

var _completed_traces: Array[Dictionary] = []
var _health_result: Dictionary = {}
var _oc_resident_names: Dictionary = {}
var _storage_root := "user://tests/town-oc-natural-live/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment(RUN_ENV) != "1":
		print(
			"TOWN_OCCUPATION_NATURAL_LIVE_SKIP: set %s=1"
			% RUN_ENV
		)
		quit(0)
		return
	var saved := (
		PROVIDER_SETTINGS.new().load_saved_runtime_configuration()
		as Dictionary
	)
	var env_key := OS.get_environment("DEEPSEEK_API_KEY").strip_edges()
	if not env_key.is_empty():
		saved = {
			"ok": true,
			"providerId": "deepseek",
			"modelId": "deepseek-v4-flash",
			"providerConfigs": {"deepseek": {"api_key": env_key}},
		}
	var provider_override := OS.get_environment(
		"AI_TOWN_OC_PROVIDER"
	).strip_edges()
	var model_override := OS.get_environment(
		"AI_TOWN_OC_MODEL"
	).strip_edges()
	if provider_override.is_empty() != model_override.is_empty():
		printerr(
			"TOWN_OCCUPATION_NATURAL_LIVE_UNAVAILABLE: "
			+ "AI_TOWN_OC_PROVIDER 与 AI_TOWN_OC_MODEL 必须同时设置"
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
			"TOWN_OCCUPATION_NATURAL_LIVE_UNAVAILABLE: %s"
			% String(saved.get("errorCode", "PROVIDER_NOT_CONFIGURED"))
		)
		quit(2)
		return
	var provider_id := String(saved.get("providerId", ""))
	var model_id := String(saved.get("modelId", ""))
	print(
		"TOWN_OCCUPATION_NATURAL_LIVE_CONTEXT: provider=%s model=%s"
		% [provider_id, model_id]
	)

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
		printerr(
			"TOWN_OCCUPATION_NATURAL_LIVE_COMPILE_FAIL: %s"
			% [compiled]
		)
		quit(1)
		return
	var opening := compiled.get("openingConfig", {}) as Dictionary
	_apply_oc_profiles(opening)
	var bindings := (
		compiled.get("residentBindings", []) as Array[Dictionary]
	)
	var identities: Array[Dictionary] = []
	for binding: Dictionary in bindings:
		identities.append({
			"residentId": String(binding.get("residentId", "")),
			"residentName": String(binding.get("residentName", "")),
		})
	identities.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("residentId", "")) < String(
			right.get("residentId", "")
		)
	)

	var request_host := Node.new()
	request_host.name = "NaturalOccupationProviderRequestHost"
	root.add_child(request_host)
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
		request_host,
	) as Dictionary
	if provider_config.get("ok") != true:
		printerr(
			"TOWN_OCCUPATION_NATURAL_LIVE_PROVIDER_FAIL: %s"
			% [provider_config]
		)
		request_host.free()
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
			"TOWN_OCCUPATION_NATURAL_LIVE_HEALTH_FAIL: started=%s result=%s"
			% [health_started, _health_result]
		)
		request_host.free()
		quit(2)
		return
	print(
		"TOWN_OCCUPATION_NATURAL_LIVE_HEALTH_PASS: provider=%s model=%s"
		% [provider_id, model_id]
	)

	var world: RefCounted = WORLD.new()
	var started := world.call(
		"start_formal",
		world_data,
		opening,
		identities,
	) as Dictionary
	if started.get("ok") != true:
		printerr(
			"TOWN_OCCUPATION_NATURAL_LIVE_WORLD_FAIL: %s"
			% [started]
		)
		request_host.free()
		quit(1)
		return

	var agent_system: RefCounted = AGENT_SYSTEM.new()
	var storage := agent_system.call(
		"configure_test_runtime_storage",
		_storage_root,
	) as Dictionary
	if storage.get("ok") != true:
		printerr(
			"TOWN_OCCUPATION_NATURAL_LIVE_STORAGE_FAIL: %s"
			% [storage]
		)
		world.call("stop")
		request_host.free()
		quit(1)
		return
	var gateway: Node = GATEWAY.new()
	gateway.name = "NaturalOccupationGateway"
	gateway.set("_agent_system", agent_system)
	gateway.debug_decision_completed.connect(
		_on_decision_completed,
	)
	root.add_child(gateway)
	var configured := gateway.call(
		"configure_session",
		{
			"sessionId": "natural-occupation-%d"
				% Time.get_ticks_usec(),
			"slotId": "test-natural-occupation-%d"
				% OS.get_process_id(),
			"saveRevision": 0,
			"restorePending": false,
			"residentIdentities": identities.duplicate(true),
			"residentBindings": bindings.duplicate(true),
			"openingConfig": opening.duplicate(true),
			"capabilityMode": "formal",
			"formalReady": true,
		},
		providers,
		request_host,
	) as Dictionary
	var bound := (
		gateway.call("bind_world", world) as Dictionary
		if configured.get("ok") == true
		else {}
	)
	if configured.get("ok") != true or bound.get("ok") != true:
		printerr(
			"TOWN_OCCUPATION_NATURAL_LIVE_GATEWAY_FAIL: configure=%s bind=%s"
			% [configured, bound]
		)
		_cleanup(gateway, world, request_host)
		quit(1)
		return

	var calls := 0
	var min_model_calls := MIN_MODEL_CALLS
	var min_calls_override := int(OS.get_environment("AI_TOWN_OC_MIN_CALLS"))
	if min_calls_override >= identities.size():
		min_model_calls = mini(min_calls_override, MIN_MODEL_CALLS)
	var max_model_calls := MAX_MODEL_CALLS
	var max_calls_override := int(OS.get_environment("AI_TOWN_OC_MAX_CALLS"))
	if max_calls_override >= min_model_calls:
		max_model_calls = mini(max_calls_override, MAX_MODEL_CALLS)
	var timed_out := false
	var conversation_observed := false
	while calls < max_model_calls:
		var dispatched := int(gateway.call("pump", 1))
		if dispatched > 0:
			calls += dispatched
			if not await _wait_for_model(gateway):
				timed_out = true
				break
		# This is the ordinary World clock. No task, position, activity or
		# decision is submitted by the playtest.
		world.call("advance", 5.0)
		var active_conversations := (
			world.call("get_active_conversations") as Array
		)
		if not active_conversations.is_empty():
			conversation_observed = true
		if (
			calls >= min_model_calls
			and int((world.call("get_time") as Dictionary).get(
				"hour",
				0,
			)) >= 12
			and (
				not conversation_observed
				or active_conversations.is_empty()
			)
		):
			break
		if dispatched == 0:
			world.call("advance", 5.0)

	var report := _natural_report(
		world,
		opening,
		calls,
		gateway.call("get_errors") as Array,
	)
	print(
		"TOWN_OC_NATURAL_LIVE_REPORT: %s"
		% JSON.stringify(report)
	)
	var success := (
		not timed_out
		and calls >= identities.size()
		and (report.get("acceptedActions", []) as Array).size() > 0
		and (report.get("naturalTaskSources", []) as Array).size() > 0
		and int((report.get("decisionTraceCounts", {}) as Dictionary).get(
			"invalidSuccess",
			0,
		)) == 0
		and int((report.get("decisionTraceCounts", {}) as Dictionary).get(
			"fallbackRecovered",
			0,
		)) == 0
		and int((report.get("decisionTraceCounts", {}) as Dictionary).get(
			"providerFailed",
			0,
		)) == 0
		and int((report.get("decisionTraceCounts", {}) as Dictionary).get(
			"worldRejected",
			0,
		)) == 0
		and int(report.get("fallbackCount", 0)) == 0
		and int(report.get("gatewayErrorCount", 0)) == 0
		and (report.get("unhandledGatewayErrors", []) as Array).is_empty()
	)
	_cleanup(gateway, world, request_host)
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	gateway = null
	world = null
	agent_system = null
	providers = null
	request_host = null
	await process_frame
	await create_timer(0.3, true, false, true).timeout
	if success:
		print("TOWN_OC_NATURAL_LIVE_PASS")
		quit(0)
		return
	printerr(
		"TOWN_OC_NATURAL_LIVE_FAIL: timedOut=%s calls=%d"
		% [timed_out, calls]
	)
	quit(1)


func _apply_oc_profiles(opening: Dictionary) -> void:
	var profiles := [
		{
			"role": "吸血鬼",
			"desire": "寻找新鲜血液和刺激，但不想让小镇彻底讨厌自己",
			"personality": "夜里精神很好，喜欢靠近别人，偶尔会把人当猎物；白天也努力过普通日子",
			"speech": "说话带着暧昧和试探，常把危险念头藏在玩笑里",
		},
		{
			"role": "海王",
			"desire": "让身边每个人都觉得自己特别",
			"personality": "对谁都热情，习惯同时维持很多暧昧关系，遇到追问会先转移话题",
			"speech": "很会夸人，承诺听起来动人但不总是具体",
		},
		{
			"role": "猎魔人",
			"desire": "保护小镇不被危险侵入",
			"personality": "警惕、爱调查，看到异常会追查，但会先核对事实",
			"speech": "说话像在记调查笔记，先问证据再下结论",
		},
		{
			"role": "牧师",
			"desire": "让冲突中的人重新坐下来慢慢说话",
			"personality": "温和、克制、愿意倾听，遇到争执会尝试调停",
			"speech": "语气安静，常把双方的话重新说一遍",
		},
		{
			"role": "暗黑骑士",
			"desire": "用自己的方式守住尊严和承诺",
			"personality": "沉默、重承诺，遇到挑衅会正面回应，但不会无缘无故伤人",
			"speech": "句子短，措辞像宣誓，答应的事一定会记住",
		},
		{
			"role": "好斗居民",
			"desire": "让镇上的日子热闹起来，也不放过任何一场架势",
			"personality": "行动直接，喜欢凑热闹，看到争执就想插手，但仍会自己判断要不要动手",
			"speech": "说话快，容易起哄，也会在别人认真劝阻时停下来想想",
		},
	]
	var residents := opening.get("residents", []) as Array
	if residents.size() >= 2:
		var first_name := String(((residents[0] as Dictionary).get("attributes", {}) as Dictionary).get("name", "第一位居民"))
		var second_name := String(((residents[1] as Dictionary).get("attributes", {}) as Dictionary).get("name", "第二位居民"))
		(profiles[0] as Dictionary)["personality"] += "；与%s有一笔没有说开的旧怨，见面时很难完全客气" % second_name
		(profiles[1] as Dictionary)["personality"] += "；与%s互相看不顺眼，但都还没有把事情说破" % first_name
	if profiles.size() >= 6:
		(profiles[5] as Dictionary)["personality"] += "；如果%s和%s起冲突，第一反应是靠近看热闹，必要时才插手" % [String(((residents[0] as Dictionary).get("attributes", {}) as Dictionary).get("name", "前者")), String(((residents[1] as Dictionary).get("attributes", {}) as Dictionary).get("name", "后者"))]
	for index in mini(profiles.size(), residents.size()):
		var resident := residents[index] as Dictionary
		var attributes := resident.get("attributes", {}) as Dictionary
		var profile := profiles[index] as Dictionary
		var role := String(profile.get("role", "")).strip_edges()
		attributes["desire"] = String(profile.get("desire", ""))
		attributes["personality"] = "%s；%s" % [role, String(profile.get("personality", ""))]
		attributes["speech"] = String(profile.get("speech", ""))
		resident["attributes"] = attributes
		_oc_resident_names[String(attributes.get("name", ""))] = String(profile.get("role", ""))
	# 这些 OC 文本是在编译后为正式 live 场景准备的测试输入；重新执行与
	# 新游戏完全相同的一次性分析，确保真实 Agent 收到的就是本轮 OC 资料。
	opening["agentSoulProfiles"] = SOUL_PROFILE.analyze_all(residents)
	var anchor_state: Dictionary = {}
	for resident_value: Variant in residents:
		if not resident_value is Dictionary:
			continue
		var candidate_state := (resident_value as Dictionary).get("worldState", {}) as Dictionary
		if String(candidate_state.get("spaceId", "")) == "town_outdoor":
			anchor_state = candidate_state.duplicate(true)
			break
	if anchor_state.is_empty() and not residents.is_empty():
		anchor_state = ((residents[0] as Dictionary).get("worldState", {}) as Dictionary).duplicate(true)
	for index in mini(profiles.size(), residents.size()):
		var resident := residents[index] as Dictionary
		var state := anchor_state.duplicate(true)
		state["doing"] = "在镇上的公共地方"
		resident["worldState"] = state
	var soul_identity_summary := {}
	for resident_id: Variant in opening.get("agentSoulProfiles", {}) as Dictionary:
		var profile := (opening.get("agentSoulProfiles", {}) as Dictionary)[resident_id] as Dictionary
		soul_identity_summary[String(resident_id)] = (profile.get("special_identities", []) as Array).duplicate(true)
	print("TOWN_OC_NATURAL_LIVE_ROSTER ", JSON.stringify({"roles": _oc_resident_names, "soulIdentities": soul_identity_summary, "anchor": anchor_state}))


func _wait_for_model(gateway: Node) -> bool:
	var started_at := Time.get_ticks_msec()
	while int(gateway.call("get_debug_inflight_count")) > 0:
		if Time.get_ticks_msec() - started_at >= MODEL_TIMEOUT_MSEC:
			return false
		# 正式运行由 TownRuntime 每帧推进一次 Gateway 准备预算。此实测
		# 没有挂载 TownRuntime，因此只在准备队列非空时复现同一推进动作；
		# Provider 已经发出请求后不再接纳下一位居民，保持串行计数。
		var preparation_queue := gateway.get("_agent_preparation_queue") as Array
		if not preparation_queue.is_empty():
			gateway.call("pump_frame_budgeted", 1)
		await process_frame
	return true


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
	var submission_errors := (
		submission.get("errors", []) as Array
		if submission.get("errors") is Array
		else []
	)
	print(
		"TOWN_OCCUPATION_NATURAL_LIVE_DECISION: resident=%s ok=%s action=%s target=%s error=%s details=%s"
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
			submission_errors,
		]
	)


func _natural_report(
	world: RefCounted,
	opening: Dictionary,
	calls: int,
	gateway_errors: Array,
) -> Dictionary:
	var accepted_actions: Array[Dictionary] = []
	var trace_counts := {}
	for trace: Dictionary in _completed_traces:
		var evidence := TRACE_EVIDENCE.classify(trace) as Dictionary
		var kind := String(evidence.get("kind", ""))
		trace_counts[kind] = int(trace_counts.get(kind, 0)) + 1
		if kind != TRACE_EVIDENCE.ACCEPTED:
			continue
		var decision := evidence.get("decision", {}) as Dictionary
		var action := evidence.get("action", {}) as Dictionary
		accepted_actions.append({
			"resident": String(trace.get("residentName", "")),
			"type": String(action.get("type", "")),
			"target": String(
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
			"line": String(action.get("line", "")).left(240),
			"say": String(action.get("say", "")).left(240),
			"narration": String(action.get("narration", "")).left(240),
			"conflictIntent": (
				(decision.get("conflict_intent", {}) as Dictionary).duplicate(true)
				if decision.get("conflict_intent") is Dictionary
				else {}
			),
		})
	var task_sources := {}
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident_id := String(
			(resident_value as Dictionary).get("residentId", ""),
		)
		for task_value: Variant in world.call(
			"get_work_tasks_for_resident",
			resident_id,
		) as Array:
			var task := task_value as Dictionary
			task_sources[
				"%s/%s"
				% [
					String(task.get("source_kind", "")),
					String(task.get("capability", "")),
				]
			] = true
	var sorted_sources: Array[String] = []
	for source_value: Variant in task_sources:
		sorted_sources.append(String(source_value))
	sorted_sources.sort()
	var services := world.call(
		"get_occupation_service_snapshot",
	) as Dictionary
	var cargo := world.call(
		"get_cargo_inventory_snapshot",
	) as Dictionary
	var social_activity := world.call(
		"get_public_social_matter_activity",
	) as Dictionary
	var conversation_report := _conversation_report(world)
	var oc_names: Array[String] = []
	for name: String in _oc_resident_names:
		oc_names.append(name)
	var oc_actions: Array[Dictionary] = []
	for action_value: Variant in accepted_actions:
		if oc_names.has(String((action_value as Dictionary).get("resident", ""))):
			oc_actions.append((action_value as Dictionary).duplicate(true))
	var conflict_projection := world.call("get_public_conflict_projection") as Dictionary
	var gateway_error_projection := _safe_gateway_errors(gateway_errors)
	var unhandled_gateway_errors: Array[Dictionary] = []
	var fallback_count := 0
	for error_value: Variant in gateway_error_projection:
		var error := error_value as Dictionary
		if bool(error.get("final", false)):
			unhandled_gateway_errors.append(error.duplicate(true))
		if String(error.get("errorCode", "")) == "AGENT_CONTINUITY_FALLBACK_APPLIED":
			fallback_count += 1
	return {
		"modelCalls": calls,
		"decisionTraceCounts": trace_counts,
		"time": world.call("get_time"),
		"acceptedActions": accepted_actions,
		"naturalTaskSources": sorted_sources,
		"serviceRequests": (
			services.get("requests", []) as Array
		).size(),
		"cargoLots": (cargo.get("cargoLots", []) as Array).size(),
		"privateMessages": _private_message_count(world, opening),
		"socialMatterActiveCount": (
			social_activity.get("items", []) as Array
		).size(),
		"socialMatterHistoryCount": (
			social_activity.get("history", []) as Array
		).size(),
		"conversationObserved": bool(
			conversation_report.get("observed", false),
		),
		"activeConversationCount": int(
			conversation_report.get("activeCount", 0),
		),
		"endedConversationCount": int(
			conversation_report.get("endedCount", 0),
		),
		"conversationTurnCounts": (
			conversation_report.get("turnCounts", []) as Array
		).duplicate(),
		"ocActions": oc_actions,
		"activeConflictCount": (conflict_projection.get("activeConflicts", []) as Array).size(),
		"conflictEventCount": (conflict_projection.get("events", []) as Array).size(),
		"announcementCount": (world.call("get_announcements") as Array).size(),
		"gatewayErrorCount": gateway_error_projection.size(),
		"recoverableGatewayEvents": gateway_error_projection,
		"fallbackCount": fallback_count,
		"unhandledGatewayErrors": unhandled_gateway_errors,
	}


func _conversation_report(world: RefCounted) -> Dictionary:
	var snapshot_result := world.call("create_save_snapshot") as Dictionary
	var snapshot := snapshot_result.get("snapshot", {}) as Dictionary
	var state := snapshot.get("state", {}) as Dictionary
	var active_count := 0
	var ended_count := 0
	var turn_counts: Array[int] = []
	for conversation_value: Variant in state.get(
		"conversations",
		[],
	) as Array:
		if not conversation_value is Dictionary:
			continue
		var conversation := conversation_value as Dictionary
		var status := String(conversation.get("status", ""))
		if status == "active":
			active_count += 1
		elif status == "ended":
			ended_count += 1
		turn_counts.append(
			(conversation.get("turns", []) as Array).size(),
		)
	return {
		"observed": active_count + ended_count > 0,
		"activeCount": active_count,
		"endedCount": ended_count,
		"turnCounts": turn_counts,
	}


func _safe_gateway_errors(errors: Array) -> Array[Dictionary]:
	var projected: Array[Dictionary] = []
	for value: Variant in errors:
		if not value is Dictionary:
			continue
		var error := value as Dictionary
		var diagnostic := error.get("diagnostic", {}) as Dictionary
		projected.append({
			"resident": String(error.get("residentName", "")),
			"errorCode": String(error.get("errorCode", "")),
			"final": bool(error.get("final", false)),
			"retryable": bool(error.get("retryable", false)),
			"agentErrors": (
				diagnostic.get(
					"agentErrors",
					diagnostic.get("agent_errors", []),
				) as Array
			).duplicate(true),
		})
	return projected


func _private_message_count(
	world: RefCounted,
	opening: Dictionary,
) -> int:
	var message_ids := {}
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident_id := String(
			(resident_value as Dictionary).get("residentId", ""),
		)
		for message_value: Variant in world.call(
			"get_private_messages_for_resident",
			resident_id,
		) as Array:
			message_ids[String(
				(message_value as Dictionary).get("message_id", ""),
			)] = true
	return message_ids.size()


func _cleanup(
	gateway: Node,
	world: RefCounted,
	request_host: Node,
) -> void:
	gateway.call("discard_unpublished_new_game")
	world.call("stop")
	# 测试随即退出，queue_free 没有下一帧可执行，会留下两个 Node。
	# 此时所有 Provider 请求已经结束，可以同步释放测试宿主与 Gateway。
	gateway.free()
	request_host.free()
	DATA_CLEANER.remove_tree(_storage_root)


func _finalize() -> void:
	DATA_CLEANER.remove_tree(_storage_root)
