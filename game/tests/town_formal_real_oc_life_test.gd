extends SceneTree


const RUN_ENV := "AI_TOWN_RUN_FORMAL_REAL_OC_LIFE"
const RUN_MSEC_ENV := "AI_TOWN_REAL_OC_RUN_MSEC"
const STARTUP_SCENE := preload("res://ui/startup/StartupScreen.tscn")
const TRACE_EVIDENCE := preload(
	"res://tests/support/TownAgentDecisionTraceEvidence.gd"
)
const OC_PROFILES: Array[Dictionary] = [
	{
		"name": "岚烬", "gender": "女", "age": 31,
		"desire": "守住自己的荣誉，并让宿敌赫弥为旧日背叛付出代价。",
		"personality": "暗黑骑士，骄傲、克制但绝不退让；赫弥是她公开承认的宿敌。遇到挑衅会先当面对质，矛盾升级时敢于攻击。",
		"speech": "言语简短冷峻，对赫弥直呼其名，不说空泛客套话。",
		"customInterests": ["练剑", "守夜", "追查赫弥"],
	},
	{
		"name": "赫弥", "gender": "女", "age": 29,
		"desire": "作为吸血鬼隐住真实身份，同时彻底压过宿敌岚烬。",
		"personality": "吸血鬼，优雅、敏锐、记仇；岚烬是她多年的宿敌。平时隐藏身份，被岚烬逼问或冒犯时会反击。",
		"speech": "语气温柔但带讥讽，愤怒时仍不失礼。",
		"customInterests": ["夜行", "红酒", "观察人心"],
	},
	{
		"name": "阿莽", "gender": "男", "age": 25,
		"desire": "哪里有热闹和打架就往哪里凑，证明自己最能打。",
		"personality": "只会打架的莽撞家伙，好斗、冲动、爱凑热闹；看见争吵会靠近起哄，乱斗时很可能加入，但不会凭空仇视所有人。",
		"speech": "大嗓门、直来直去，常用短句挑衅或叫好。",
		"customInterests": ["打架", "围观冲突", "比力气"],
	},
	{
		"name": "塞拉", "gender": "女", "age": 34,
		"desire": "找出镇上的怪物，保护普通居民免受吸血鬼伤害。",
		"personality": "猎魔人，谨慎、执着、善于观察；对吸血鬼线索高度敏感，但在没有事实前会调查而不是无故攻击。",
		"speech": "冷静追问细节，说话像在核对证据。",
		"customInterests": ["追踪", "怪物传闻", "武器保养"],
	},
	{
		"name": "伊诺", "gender": "男", "age": 38,
		"desire": "保护镇民、化解仇恨，在危险真正发生时挡在弱者前面。",
		"personality": "牧师，温和、坚定、有同情心；会劝和争执，也会在冲突中保护他人。",
		"speech": "温暖朴素，先听完再劝，不讲长篇大道理。",
		"customInterests": ["倾听", "照顾邻居", "烘焙"],
	},
	{
		"name": "洛汐", "gender": "男", "age": 27,
		"desire": "让不同的人都觉得自己是他最特别的朋友，同时维持轻松自在的生活。",
		"personality": "海王，外向、体贴、擅长暧昧社交；会自然接近多人，但不公开承认自己的多线关系。",
		"speech": "亲切俏皮，会针对不同的人说具体而贴心的话。",
		"customInterests": ["约会", "送小礼物", "听秘密"],
	},
]

var _failures: Array[String] = []
var _gateway: Node
var _decisions: Array[Dictionary] = []
var _decision_trace_counts := {
	"accepted": 0,
	"continuedCurrent": 0,
	"internalRetry": 0,
	"fallbackRecovered": 0,
	"providerFailed": 0,
	"staleDiscarded": 0,
	"worldRejected": 0,
	"invalidSuccess": 0,
}
var _conflict_peak := 0
var _conversation_peak := 0
var _announcement_peak := 0
var _finishing := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment(RUN_ENV) != "1":
		print("TOWN_FORMAL_REAL_OC_LIFE_SKIP")
		quit(0)
		return
	OS.set_environment("AI_TOWN_INTERNAL_PLAYTEST", "")
	var host := root.get_node_or_null("GameFlowHost")
	_expect(host != null, "正式 GameFlowHost 已加载")
	if host == null:
		_finish()
		return
	var startup := STARTUP_SCENE.instantiate()
	root.add_child(startup)
	current_scene = startup
	host.call("_bind_current_scene")
	await _wait_frames(5)
	var session := startup.get("_session_view_model") as Dictionary
	var data := session.get("data", {}) as Dictionary
	startup.emit_signal("intent_requested", &"session.new_game", {
		"scope": "session", "actionKey": "newGame",
		"revision": int(session.get("revision", 0)),
		"routeOrigin": "startup", "source": String(data.get("source", "")),
		"capabilityMode": String(data.get("capabilityMode", "")),
		"validationMode": String(data.get("validationMode", "")),
		"formalReady": bool(data.get("formalReady", false)),
		"internalPlaytest": false, "internalLivePlaytest": false,
		"slotId": "town-main",
	})
	await _wait_frames(5)
	if current_scene != null and current_scene.name == "SaveHandlingScreen":
		var overwrite := current_scene as Control
		overwrite.call("debug_request_action", "confirmOverwrite")
		await _wait_frames(6)
	var intro := current_scene
	_expect(intro != null and intro.name == "WorldIntroScreen", "正式新游戏进入世界介绍")
	if intro == null or intro.name != "WorldIntroScreen":
		_finish()
		return
	intro.call("_request_action", "skip")
	await create_timer(0.35).timeout
	await _wait_frames(5)
	var selection := current_scene as Control
	_expect(selection != null and selection.name == "ResidentSelectionScreen", "进入正式选居民页面")
	if selection == null or selection.name != "ResidentSelectionScreen":
		_finish()
		return
	var custom_ids: Array[String] = []
	for profile: Dictionary in OC_PROFILES:
		var custom_id := await _create_custom_resident(host, profile)
		_expect(not custom_id.is_empty(), "创建 OC 居民 %s" % profile.get("name", ""))
		if not custom_id.is_empty():
			custom_ids.append(custom_id)
	if custom_ids.size() != OC_PROFILES.size():
		_finish()
		return
	var selection_vm := host.get("_resident_selection_vm") as Dictionary
	var selection_data := selection_vm.get("data", {}) as Dictionary
	var roster: Array[String] = custom_ids.duplicate()
	for value: Variant in selection_data.get("recommended_resident_ids", []) as Array:
		var resident_id := String(value)
		if not roster.has(resident_id) and roster.size() < 15:
			roster.append(resident_id)
	selection_data["selected_resident_ids"] = roster
	host.call("_update_confirmation_payload", selection_data)
	host.call("_advance_resident_selection_revision")
	await _wait_frames(3)
	_expect(roster.size() == 15, "正式名单包含 15 位居民")
	var confirm := selection.find_child("ConfirmRosterButton", true, false) as Button
	_expect(confirm != null and not confirm.disabled, "正式名单可以确认")
	if confirm == null or confirm.disabled:
		_finish()
		return
	confirm.pressed.emit()
	await _wait_frames(4)
	var assignment := selection.get_node_or_null("ResidentModelAssignmentRoute") as Control
	_expect(assignment != null, "进入正式模型分配页面")
	if assignment == null:
		_finish()
		return
	var adapter := host.get("_startup_ui_adapter") as Node
	var assignment_data := await _wait_for_assignment_target(adapter, 120_000)
	if assignment_data.is_empty():
		_expect(false, "正式 DeepSeek 模型目标在等待后仍不可用")
		_finish()
		return
	var target := (assignment_data.get("targetBinding", {}) as Dictionary).duplicate(true)
	_expect(
		String(target.get("providerId", "")) == "deepseek"
		and not String(target.get("modelId", "")).is_empty(),
		"正式模型目标是已配置的 DeepSeek",
	)
	for resident_value: Variant in assignment_data.get("residents", []) as Array:
		var resident_id := String((resident_value as Dictionary).get("residentId", ""))
		var assigned := assignment.call("_request_action", "assignOne", {
			"residentId": resident_id,
			"llmBinding": target.duplicate(true),
		}, "resident:%s" % resident_id) as Dictionary
		_expect(bool(assigned.get("ok", false)), "给 %s 分配真实模型" % resident_id)
	assignment.call("_open_completion_modal")
	var start_button := assignment.find_child("ModalStartButton", true, false) as Button
	_expect(start_button != null and not start_button.disabled, "正式开始游戏按钮可用")
	if start_button == null or start_button.disabled:
		_finish()
		return
	start_button.pressed.emit()
	if not await _wait_for_town(host, 180_000):
		_finish()
		return
	_gateway = host.get("_gateway") as Node
	var runtime := current_scene
	var world := runtime.call("get_world_runtime") as RefCounted
	# Headless runs have no focused window. Do not let the desktop focus policy
	# freeze the authoritative world that this formal-entry test is observing.
	var resumed := runtime.call("set_background_paused", false) as Dictionary
	_expect(bool(resumed.get("ok", false)), "无窗口正式运行已解除后台暂停")
	_expect(not bool(world.call("is_paused")), "无窗口正式世界正在运行")
	var connected := _gateway.call("get_connected_resident_ids") as Array
	_expect(connected.size() == 15, "15 位真实 Agent 已连接")
	var callback := Callable(self, "_on_decision")
	if not _gateway.is_connected("debug_decision_completed", callback):
		_gateway.connect("debug_decision_completed", callback)
	var started_at := Time.get_ticks_msec()
	var duration := _environment_int(RUN_MSEC_ENV, 1_800_000, 60_000, 86_400_000)
	while Time.get_ticks_msec() - started_at < duration:
		_track(world)
		if _has_final_gateway_error():
			break
		await process_frame
	_track(world)
	_print_report(host, world, custom_ids)
	await _cleanup(host)
	call_deferred("_finish")


func _create_custom_resident(host: Node, profile: Dictionary) -> String:
	var revision := int((host.get("_resident_selection_vm") as Dictionary).get("revision", 0))
	host.call("_on_custom_resident_requested", revision)
	await _wait_frames(4)
	var service_value: Variant = host.get("_custom_resident_creator_service")
	if not service_value is RefCounted:
		return ""
	var service := service_value as RefCounted
	var vm := service.call("get_view_model") as Dictionary
	var creator_data := vm.get("data", {}) as Dictionary
	var updated := service.call("dispatch", "custom_resident_creator.update_fields", {
		"revision": int(vm.get("revision", 0)),
		"draftId": String(creator_data.get("draftId", "")),
		"fields": profile.duplicate(true),
	}) as Dictionary
	if not bool(updated.get("ok", false)):
		return ""
	vm = service.call("get_view_model") as Dictionary
	creator_data = vm.get("data", {}) as Dictionary
	var created := service.call("dispatch", "custom_resident_creator.create", {
		"revision": int(vm.get("revision", 0)),
		"draftId": String(creator_data.get("draftId", "")),
		"candidatePoolRevision": int(creator_data.get("candidatePoolRevision", -1)),
	}) as Dictionary
	if not bool(created.get("ok", false)):
		return ""
	host.call("_on_custom_resident_creator_intent_requested", "custom_resident_creator.create", {
		"dispatchResult": created.duplicate(true),
	})
	await _wait_frames(5)
	return String((created.get("candidate", {}) as Dictionary).get("residentId", ""))


func _on_decision(trace: Dictionary) -> void:
	var evidence := TRACE_EVIDENCE.classify(trace) as Dictionary
	var kind := String(evidence.get("kind", ""))
	_decision_trace_counts[kind] = int(_decision_trace_counts.get(kind, 0)) + 1
	if kind not in [TRACE_EVIDENCE.ACCEPTED, TRACE_EVIDENCE.CONTINUED_CURRENT]:
		return
	var decision := evidence.get("decision", {}) as Dictionary
	var action := evidence.get("action", {}) as Dictionary
	var action_type := String(action.get("type", "")).strip_edges()
	if kind == TRACE_EVIDENCE.CONTINUED_CURRENT:
		action_type = "继续当前"
	var conflict_intent := decision.get("conflict_intent", {}) as Dictionary
	_decisions.append({
		"residentId": String(trace.get("residentId", "")),
		"residentName": String(trace.get("residentName", "")),
		"ok": bool(trace.get("ok", false)),
		"recovered": bool(trace.get("recovered", false)),
		"stale": bool(trace.get("stale", false)),
		"actionType": action_type,
		"line": String(action.get("line", "")).left(240),
		"say": String(action.get("say", "")).left(240),
		"narration": String(action.get("narration", "")).left(240),
		"targetResidentId": String(action.get("target_resident_id", action.get("targetResidentId", ""))),
		"conflictIntentType": String(conflict_intent.get("type", "")),
		"conflictIntentTargetResidentId": String(conflict_intent.get("target_resident_id", "")),
		"conflictIntentLine": String(conflict_intent.get("line", "")).left(240),
	})


func _track(world: RefCounted) -> void:
	_conversation_peak = maxi(_conversation_peak, (world.call("get_active_conversations") as Array).size())
	_announcement_peak = maxi(_announcement_peak, (world.call("get_announcements") as Array).size())
	var projection := world.call("get_public_conflict_projection") as Dictionary
	_conflict_peak = maxi(_conflict_peak, (projection.get("conflicts", []) as Array).size())


func _print_report(host: Node, world: RefCounted, custom_ids: Array[String]) -> void:
	var errors := _gateway.call("get_errors") as Array
	var final_errors := 0
	var fallback_count := 0
	var error_codes := {}
	for value: Variant in errors:
		if not value is Dictionary:
			continue
		var error := value as Dictionary
		var code := String(error.get("errorCode", ""))
		error_codes[code] = int(error_codes.get(code, 0)) + 1
		if code == "AGENT_CONTINUITY_FALLBACK_APPLIED":
			fallback_count += 1
		elif bool(error.get("final", false)):
			final_errors += 1
	var oc_decisions: Array[Dictionary] = []
	var oc_action_counts := {}
	for decision: Dictionary in _decisions:
		if custom_ids.has(String(decision.get("residentId", ""))):
			oc_decisions.append(decision)
			var resident_name := String(decision.get("residentName", ""))
			var action_type := String(decision.get("actionType", ""))
			var resident_counts := oc_action_counts.get(resident_name, {}) as Dictionary
			resident_counts[action_type] = int(resident_counts.get(action_type, 0)) + 1
			oc_action_counts[resident_name] = resident_counts
	var request_metrics := _gateway.call("get_request_metrics") as Dictionary
	_expect(final_errors == 0, "真实运行未处理最终错误为 0")
	_expect(fallback_count == 0, "真实运行 continuity fallback 为 0")
	_expect(
		int(_decision_trace_counts.get("invalidSuccess", 0)) == 0,
		"Agent 成功结果不存在无法解释的空决定",
	)
	_expect(
		int(_decision_trace_counts.get("providerFailed", 0)) == 0,
		"真实运行不存在未恢复的 Provider 决策失败",
	)
	_expect(
		int(_decision_trace_counts.get("fallbackRecovered", 0)) == 0,
		"真实运行不存在由 continuity fallback 接管的决定",
	)
	_expect(
		int(_decision_trace_counts.get("worldRejected", 0)) == 0,
		"真实运行不存在被世界拒绝的非过期决定",
	)
	_expect(_decisions.size() > 0, "真实运行至少完成一次居民决策")
	_expect(int(request_metrics.get("providerDispatch", 0)) > 0, "真实运行至少派发一次 Provider 请求")
	print("TOWN_FORMAL_REAL_OC_LIFE_REPORT: %s" % JSON.stringify({
		"time": world.call("get_time"),
		"decisionCount": _decisions.size(),
		"decisionTraceCounts": _decision_trace_counts.duplicate(true),
		"ocDecisionCount": oc_decisions.size(),
		"ocActionCounts": oc_action_counts,
		"ocDecisions": oc_decisions.slice(maxi(oc_decisions.size() - 80, 0)),
		"conversationPeak": _conversation_peak,
		"announcementPeak": _announcement_peak,
		"conflictPeak": _conflict_peak,
		"conflictProjection": world.call("get_public_conflict_projection"),
		"announcements": world.call("get_announcements"),
		"publicEvents": (world.call("get_public_event_log") as Array).slice(-100),
		"autoSave": host.call("get_daily_auto_save_diagnostics"),
		"fallbackCount": fallback_count,
		"fallbackRate": float(fallback_count) / float(maxi(_decisions.size(), 1)),
		"gatewayErrorCodes": error_codes,
		"requestMetrics": request_metrics,
		"unhandledFinalErrors": final_errors,
	}))


func _wait_for_assignment_target(adapter: Node, timeout_msec: int) -> Dictionary:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < timeout_msec:
		var assignment_vm := adapter.call(
			"get_view_model",
			"resident_model_assignment",
		) as Dictionary
		var assignment_data := assignment_vm.get("data", {}) as Dictionary
		var target := assignment_data.get("targetBinding", {}) as Dictionary
		if (
			String(target.get("providerId", "")) == "deepseek"
			and not String(target.get("modelId", "")).is_empty()
		):
			return assignment_data.duplicate(true)
		var provider_status := _safe_deepseek_status(adapter)
		if (
			not provider_status.is_empty()
			and String(provider_status.get("status", "")) not in [
				"",
				"checking",
				"unchecked",
			]
			and String(provider_status.get("status", "")) != "available"
		):
			print(
				"TOWN_FORMAL_REAL_OC_PROVIDER_STATUS: %s"
				% JSON.stringify(provider_status)
			)
			return {}
		await process_frame
	print(
		"TOWN_FORMAL_REAL_OC_PROVIDER_STATUS: %s"
		% JSON.stringify(_safe_deepseek_status(adapter))
	)
	return {}


func _safe_deepseek_status(adapter: Node) -> Dictionary:
	var settings_vm := adapter.call("get_view_model", "provider_settings") as Dictionary
	var data := settings_vm.get("data", {}) as Dictionary
	for provider_value: Variant in data.get("providers", []) as Array:
		if not provider_value is Dictionary:
			continue
		var provider := provider_value as Dictionary
		if String(provider.get("providerId", "")) != "deepseek":
			continue
		var connection := provider.get("connection", {}) as Dictionary
		var models: Array[Dictionary] = []
		for model_value: Variant in provider.get("models", []) as Array:
			if not model_value is Dictionary:
				continue
			var model := model_value as Dictionary
			models.append({
				"modelId": String(model.get("modelId", "")),
				"enabled": bool(model.get("enabled", false)),
				"available": bool(model.get("available", false)),
				"healthStatus": String(model.get("healthStatus", "")),
				"errorCode": String(model.get("errorCode", "")),
			})
		return {
			"providerId": "deepseek",
			"keySaved": bool((provider.get("key", {}) as Dictionary).get("saved", false)),
			"enabled": bool(provider.get("enabled", false)),
			"status": String(connection.get("status", "")),
			"errorCode": String(connection.get("errorCode", "")),
			"retryable": bool(connection.get("retryable", false)),
			"models": models,
		}
	return {}


func _has_final_gateway_error() -> bool:
	if _gateway == null or not is_instance_valid(_gateway):
		return false
	for error_value: Variant in _gateway.call("get_errors") as Array:
		if error_value is Dictionary and bool((error_value as Dictionary).get("final", false)):
			return true
	return false


func _wait_for_town(host: Node, timeout_msec: int) -> bool:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < timeout_msec:
		if current_scene != null and current_scene.name == "TownRuntime":
			return true
		await process_frame
	_failures.append("真实 DeepSeek 正式开局未进入 Town")
	print("TOWN_FORMAL_REAL_OC_START_FAILURE: %s" % JSON.stringify(host.get("_last_result")))
	return false


func _cleanup(host: Node) -> void:
	var runtime := current_scene
	if runtime != null and is_instance_valid(runtime):
		runtime.set_process(false)
		runtime.set_physics_process(false)
	var started_at := Time.get_ticks_msec()
	while (
		_gateway != null and is_instance_valid(_gateway)
		and not (_gateway.get("_inflight") as Dictionary).is_empty()
		and Time.get_ticks_msec() - started_at < 45_000
	):
		await process_frame
	if runtime != null and is_instance_valid(runtime):
		runtime.queue_free()
	current_scene = null
	if is_instance_valid(host) and host.has_method("_release_internal_session_refs"):
		host.call("_release_internal_session_refs")
	await _wait_frames(3)


func _wait_frames(count: int) -> void:
	for _index in count:
		await process_frame


func _environment_int(name: String, fallback: int, minimum: int, maximum: int) -> int:
	var value := OS.get_environment(name).strip_edges()
	return clampi(int(value), minimum, maximum) if value.is_valid_int() else fallback


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	call_deferred("_finish_after_cleanup")


func _finish_after_cleanup() -> void:
	for _index in 5:
		await process_frame
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	await create_timer(0.3, true, false, true).timeout
	if _failures.is_empty():
		print("TOWN_FORMAL_REAL_OC_LIFE_PASS")
		quit(0)
		return
	printerr("TOWN_FORMAL_REAL_OC_LIFE_FAIL: %s" % "; ".join(_failures))
	quit(1)
