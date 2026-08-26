extends SceneTree


const OFFLINE_REBIND := preload(
	"res://world/presentation/session/TownOfflineResidentModelRebindService.gd"
)
const UI_ADAPTER := preload("res://world/presentation/ui/TownUiAdapter.gd")
const GAME_FLOW_HOST := preload("res://world/presentation/game_flow/GameFlowHost.gd")
const SAVE_CATALOG := preload("res://world/presentation/session/TownStartupSaveCatalog.gd")
const STARTUP_REBIND_COORDINATOR := preload(
	"res://world/presentation/game_flow/TownStartupOfflineResidentModelRebindCoordinator.gd"
)
const RECONCILIATION := preload(
	"res://world/presentation/session/TownSaveReconciliationService.gd"
)
const FIXTURE := preload("res://tests/support/OfflineResidentModelRebindFixture.gd")


var _failures: Array[String] = []
var _checks := 0
var _fixture: RefCounted
var _save_store: RefCounted
var _agent_store: RefCounted
var _slot_id := ""
var _session_id := ""
var _profile_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var identity := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_fixture = FIXTURE.new()
	_expect_ok(_fixture.configure("ui_%s" % identity), "UI/路由故事使用共享隔离夹具")
	_save_store = _fixture.save_store
	_agent_store = _fixture.agent_store
	_slot_id = _fixture.slot_id
	_session_id = _fixture.session_id
	_profile_path = _fixture.profile_path
	_expect_ok(_fixture.create_source_revision(), "UI/路由故事可创建源完整修订")
	var interrupted: Dictionary = _fixture.create_recoverable_catalog_slot()
	_expect_ok(interrupted, "UI/路由故事可建立真实可恢复目录状态")
	var recoverable_slot := interrupted.get("slot", {}) as Dictionary
	await _test_pending_target_drift(recoverable_slot)
	await _test_host_stale_feedback()
	await _test_host_replaced_session_stale_feedback()
	interrupted = _fixture.create_recoverable_catalog_slot()
	_expect_ok(interrupted, "并发发布后可再次建立恢复路由夹具")
	recoverable_slot = interrupted.get("slot", {}) as Dictionary
	await _test_game_flow_route(recoverable_slot)
	_fixture.cleanup()
	_save_store = null
	_agent_store = null
	_fixture = null
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
	await create_timer(0.3, true, false, true).timeout
	if _failures.is_empty():
		print("OFFLINE_RESIDENT_MODEL_REBIND_UI_ROUTE_PASS checks=%d" % _checks)
	else:
		for failure in _failures:
			printerr("OFFLINE_RESIDENT_MODEL_REBIND_UI_ROUTE_FAIL: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_pending_target_drift(recoverable_slot: Dictionary) -> void:
	var adapter := UI_ADAPTER.new()
	root.add_child(adapter)
	var coordinator := STARTUP_REBIND_COORDINATOR.new() as Node
	root.add_child(coordinator)
	_expect_ok(coordinator.call(
		"configure",
		_save_store,
		_agent_store,
		_fixture.provider(),
		adapter,
		_base_catalog(),
	) as Dictionary, "并发发布夹具可配置启动页协调器")
	var selected := coordinator.call("select_target", recoverable_slot) as Dictionary
	_expect_ok(selected, "恢复前由协调器保存完整目标")
	var selected_revision := int(
		(recoverable_slot.get("summary", {}) as Dictionary).get("saveRevision", -1),
	)
	_expect_equal(
		(coordinator.call("target") as Dictionary).get("saveRevision"),
		selected_revision,
		"coordinator.target 钉住玩家确认的完整修订",
	)
	var reconciliation := RECONCILIATION.new() as RefCounted
	_expect_ok(reconciliation.call(
		"configure",
		_save_store,
		_agent_store,
	) as Dictionary, "并发发布夹具可配置恢复协调服务")
	var plan := recoverable_slot.get("reconciliationPlan", {}) as Dictionary
	_expect_ok(reconciliation.call("execute", plan, {
		"confirmed": true,
		"planId": String(plan.get("planId", "")),
	}) as Dictionary, "玩家确认后完成真实恢复协调")
	var healthy_slot := _catalog_slot()
	var concurrent := OFFLINE_REBIND.new() as RefCounted
	_expect_ok(concurrent.call(
		"configure",
		_save_store,
		_agent_store,
		_fixture.provider(),
	) as Dictionary, "并发发布者可配置")
	_expect_ok(concurrent.call(
		"prepare",
		healthy_slot,
		_base_catalog(),
	) as Dictionary, "并发发布者钉住协调后的健康修订")
	_expect_ok(concurrent.call(
		"apply_bindings",
		_bindings_for("current-provider", "current-model-2"),
	) as Dictionary, "恢复协调后可模拟并发发布")
	var concurrent_slot := _catalog_slot()
	var startup := Control.new()
	startup.name = "StartupScreen"
	root.add_child(startup)
	var resumed := coordinator.call("resume", startup, concurrent_slot) as Dictionary
	_expect_equal(
		resumed.get("errorCode"),
		"STARTUP_SAVE_MODEL_EDIT_TARGET_STALE",
		"恢复协调后出现并发发布时拒绝静默切换到最新修订",
	)
	_expect_equal(
		(coordinator.call("target") as Dictionary).get("saveRevision"),
		selected_revision,
		"stale 后 coordinator.target 仍保留原确认修订",
	)
	root.remove_child(startup)
	startup.free()
	root.remove_child(coordinator)
	coordinator.free()
	root.remove_child(adapter)
	adapter.free()


func _test_host_stale_feedback() -> void:
	var startup := Control.new()
	startup.name = "StartupScreen"
	root.add_child(startup)
	current_scene = startup
	var adapter := UI_ADAPTER.new()
	root.add_child(adapter)
	var host := GAME_FLOW_HOST.new()
	root.add_child(host)
	host.set("_startup_save_store", _save_store)
	host.set("_startup_agent_save_store", _agent_store)
	host.set("_startup_provider_service", _fixture.provider())
	host.set("_startup_ui_adapter", adapter)
	var startup_catalog := SAVE_CATALOG.new()
	startup_catalog.call("configure", _save_store, _profile_path, _agent_store)
	host.set("_startup_save_catalog", startup_catalog)
	host.call("_bind_current_scene")
	host.call("_open_startup_load_game", "load")
	for _index in 2:
		await process_frame
	var selected_slot := _catalog_slot()
	var selected_projection := host.call(
		"_startup_slot_projection",
		selected_slot,
	) as Dictionary
	var concurrent := OFFLINE_REBIND.new() as RefCounted
	_expect_ok(concurrent.call(
		"configure",
		_save_store,
		_agent_store,
		_fixture.provider(),
	) as Dictionary, "Host stale 故事可配置并发发布者")
	_expect_ok(concurrent.call(
		"prepare",
		selected_slot,
		_base_catalog(),
	) as Dictionary, "Host stale 故事并发发布者钉住原修订")
	_expect_ok(concurrent.call(
		"apply_bindings",
		_bindings_for("current-provider", "current-model-3"),
	) as Dictionary, "Host stale 故事产生更新后的完整修订")
	host.call(
		"_on_startup_load_game_intent_requested",
		&"save.edit_resident_models",
		{
			"slotId": selected_projection.get("slotId"),
			"sessionId": selected_projection.get("sessionId"),
			"saveRevision": selected_projection.get("modelEditSaveRevision"),
		},
	)
	for _index in 3:
		await process_frame
	var load_page := host.get("_startup_load_game_page") as Control
	var feedback := (
		load_page.find_child("LoadGameFeedback", true, false) as Label
		if load_page != null
		else null
	)
	_expect(
		load_page != null and load_page.visible,
		"首次点击发现 revision 变化时仍停留在可见加载页（last=%s）" % host.get(
			"_last_result",
		),
	)
	_expect(
		feedback != null
		and feedback.is_visible_in_tree()
		and feedback.text.contains("存档已更新，请重新选择完整修订"),
		"首次点击 revision 漂移时加载页自身显示 stale 提示（feedback=%s）" % (
			feedback.text if feedback != null else "missing"
		),
	)
	host.call("_close_startup_load_game")
	root.remove_child(host)
	host.free()
	root.remove_child(adapter)
	adapter.free()
	current_scene = null
	root.remove_child(startup)
	startup.free()


func _test_host_replaced_session_stale_feedback() -> void:
	var fixture := FIXTURE.new() as RefCounted
	var identity := "s%d%d" % [
		OS.get_process_id() % 1000,
		Time.get_ticks_usec() % 10000,
	]
	_expect_ok(
		fixture.call("configure", identity) as Dictionary,
		"同修订 session 替换故事使用隔离夹具",
	)
	_expect_ok(
		fixture.call("create_source_revision") as Dictionary,
		"同修订 session 替换故事创建原始修订",
	)
	var original_slot := fixture.call("catalog_slot") as Dictionary
	var startup := Control.new()
	startup.name = "StartupScreen"
	root.add_child(startup)
	current_scene = startup
	var adapter := UI_ADAPTER.new()
	root.add_child(adapter)
	var host := GAME_FLOW_HOST.new()
	root.add_child(host)
	host.set("_startup_save_store", fixture.get("save_store"))
	host.set("_startup_agent_save_store", fixture.get("agent_store"))
	host.set("_startup_provider_service", fixture.call("provider"))
	host.set("_startup_ui_adapter", adapter)
	var startup_catalog := SAVE_CATALOG.new()
	startup_catalog.call(
		"configure",
		fixture.get("save_store"),
		fixture.get("profile_path"),
		fixture.get("agent_store"),
	)
	host.set("_startup_save_catalog", startup_catalog)
	host.call("_bind_current_scene")
	host.call("_open_startup_load_game", "load")
	for _index in 2:
		await process_frame
	var selected_projection := host.call(
		"_startup_slot_projection",
		original_slot,
	) as Dictionary
	fixture.call("cleanup")
	var replacement_session := "offline-model-session-%s-new%d" % [
		"s".repeat(80),
		OS.get_process_id() % 1000,
	]
	fixture.set("session_id", replacement_session)
	_expect_ok(
		fixture.call("create_source_revision") as Dictionary,
		"删除槽位后以相同 revision 创建新 session",
	)
	var replacement_slot := fixture.call("catalog_slot") as Dictionary
	var replacement_summary := replacement_slot.get("summary", {}) as Dictionary
	_expect_equal(
		replacement_summary.get("saveRevision"),
		selected_projection.get("modelEditSaveRevision"),
		"替换 session 特意复用相同 saveRevision",
	)
	_expect(
		String(replacement_summary.get("sessionId", ""))
		!= String(selected_projection.get("sessionId", "")),
		"替换槽位的 sessionId 已变化",
	)
	host.call(
		"_on_startup_load_game_intent_requested",
		&"save.edit_resident_models",
		{
			"slotId": selected_projection.get("slotId"),
			"sessionId": selected_projection.get("sessionId"),
			"saveRevision": selected_projection.get("modelEditSaveRevision"),
		},
	)
	for _index in 3:
		await process_frame
	var load_page := host.get("_startup_load_game_page") as Control
	var feedback := (
		load_page.find_child("LoadGameFeedback", true, false) as Label
		if load_page != null
		else null
	)
	_expect(
		feedback != null
		and feedback.is_visible_in_tree()
		and feedback.text.contains("存档已更新，请重新选择完整修订"),
		"相同 revision 但 session 已替换时，当前加载页显示 stale 提示",
	)
	host.call("_close_startup_load_game")
	root.remove_child(host)
	host.free()
	root.remove_child(adapter)
	adapter.free()
	current_scene = null
	root.remove_child(startup)
	startup.free()
	fixture.call("cleanup")


func _test_game_flow_route(slot: Dictionary) -> void:
	var original_viewport_size := root.size
	_expect_equal(slot.get("state"), "recoverable", "GameFlow 验收使用真实可修复 catalog 槽位")
	var guarded_service := OFFLINE_REBIND.new()
	guarded_service.call(
		"configure",
		_save_store,
		_agent_store,
		_fixture.provider(),
	)
	var guarded_prepare := guarded_service.call(
		"prepare",
		slot,
		_base_catalog(),
	) as Dictionary
	_expect_equal(
		guarded_prepare.get("errorCode"),
		"OFFLINE_RESIDENT_MODEL_REBIND_RECOVERY_REQUIRED",
		"存在可修复 blocker 时离线模块明确要求先协调恢复",
	)
	var startup := Control.new()
	startup.name = "StartupScreen"
	root.add_child(startup)
	current_scene = startup
	var adapter := UI_ADAPTER.new()
	root.add_child(adapter)
	var host := GAME_FLOW_HOST.new()
	root.add_child(host)
	host.set("_startup_save_store", _save_store)
	host.set("_startup_agent_save_store", _agent_store)
	var provider: RefCounted = _fixture.provider()
	host.set("_startup_provider_service", provider)
	host.set("_startup_ui_adapter", adapter)
	var startup_catalog := SAVE_CATALOG.new()
	startup_catalog.call("configure", _save_store, _profile_path, _agent_store)
	host.set("_startup_save_catalog", startup_catalog)
	host.call("_bind_current_scene")
	var projection := host.call("_startup_slot_projection", slot) as Dictionary
	_expect_equal(projection.get("modelEditAvailable"), true, "可修复槽位保留模型编辑入口")
	_expect_equal(
		projection.get("modelEditRecoveryRequired"),
		true,
		"模型编辑入口明确先进入恢复协调",
	)
	_expect_equal(
		projection.get("modelEditSaveRevision"),
		(slot.get("summary", {}) as Dictionary).get("saveRevision"),
		"恢复前仍钉住最近完整修订",
	)
	host.set("_startup_load_game_mode", "load")
	host.call(
		"_on_startup_load_game_intent_requested",
		&"save.edit_resident_models",
		{
			"slotId": _slot_id,
			"sessionId": projection.get("sessionId"),
			"saveRevision": projection.get("modelEditSaveRevision"),
		},
	)
	await process_frame
	_expect(host.get("_startup_overwrite_page") != null, "可修复槽位先打开恢复确认页")
	host.call(
		"_on_new_game_overwrite_intent_requested",
		&"session.confirm_recovery",
		{},
	)
	for _index in 5:
		await process_frame
	var coordinator := host.get("_startup_save_model_coordinator") as Object
	var page := coordinator.call("page") as Control if coordinator != null else null
	_expect(page != null, "恢复协调完成后打开离线模型编辑路由")
	if page != null:
		var snapshot := page.call("runtime_gate_snapshot") as Dictionary
		_expect_equal(snapshot.get("routeMode"), "save_slot", "Host 路由保留单一 save_slot 模式")
	_expect(host.get("_gateway") == null, "离线模型编辑不创建 Agent Gateway")
	_expect(host.get("_town_runtime") == null, "离线模型编辑不创建 Town Runtime")
	var routed_service := coordinator.call("assignment") as Object
	var routed_vm := routed_service.call("get_view_model") as Dictionary
	routed_service.call(
		"dispatch",
		"resident_model_assignment.select_model",
		{
			"revision": int(routed_vm.get("revision", -1)),
			"providerId": "current-provider",
			"modelId": "current-model-2",
		},
	)
	routed_vm = routed_service.call("get_view_model") as Dictionary
	routed_service.call(
		"dispatch",
		"resident_model_assignment.assign_one",
		{
			"revision": int(routed_vm.get("revision", -1)),
			"residentId": "resident-a",
			"llmBinding": {
				"mode": "model",
				"providerId": "current-provider",
				"modelId": "current-model-2",
			},
		},
	)
	var changed_draft := routed_service.call("get_session_draft") as Dictionary
	var manifests_before_rejected_apply := (
		(_save_store.call("list_published", _slot_id) as Dictionary).get(
			"manifests",
			[],
		) as Array
	).size()
	provider.call("set_unavailable_models", ["current-model-2"])
	routed_vm = routed_service.call("get_view_model") as Dictionary
	var rejected_apply := routed_service.call(
		"dispatch",
		"resident_model_assignment.apply_draft",
		{"revision": int(routed_vm.get("revision", -1))},
	) as Dictionary
	_expect_equal(
		rejected_apply.get("errorCode"),
		"LLM_MODEL_UNAVAILABLE",
		"save_slot 提交时所选模型失效会直接拒绝",
	)
	_expect_equal(
		routed_service.call("get_session_draft"),
		changed_draft,
		"另有可用模型时也不会自动替换玩家草稿",
	)
	_expect_equal(
		((_save_store.call("list_published", _slot_id) as Dictionary).get(
			"manifests",
			[],
		) as Array).size(),
		manifests_before_rejected_apply,
		"目标模型失效时不会发布新 manifest",
	)
	await process_frame
	var rejected_provider_button := page.find_child(
		"ProviderSettingsButton",
		true,
		false,
	) as Button
	_expect(
		rejected_provider_button != null and rejected_provider_button.visible,
		"提交校验失败后显示返回模型配置入口",
	)
	provider.call("set_unavailable_models", [])
	routed_vm = routed_service.call("get_view_model") as Dictionary
	routed_service.call(
		"dispatch",
		"resident_model_assignment.refresh",
		{"revision": int(routed_vm.get("revision", -1))},
	)
	provider.set_available(false)
	routed_vm = routed_service.call("get_view_model") as Dictionary
	routed_service.call(
		"dispatch",
		"resident_model_assignment.refresh",
		{"revision": int(routed_vm.get("revision", -1))},
	)
	await process_frame
	root.size = Vector2i(1920, 1080)
	for _index in 3:
		await process_frame
	var provider_button := page.find_child("ProviderSettingsButton", true, false) as Button
	var composite := page.find_child(
		"ResidentModelAssignmentOriginalSimplifiedV34",
		true,
		false,
	) as Control
	var composite_provider_button := (
		composite.call("focus_target", "provider_settings") as Button
		if composite != null
		else null
	)
	_expect(
		provider_button != null and provider_button.visible,
		"Provider 不可用时响应式页显示返回模型配置入口",
	)
	_expect(
		composite_provider_button != null and composite_provider_button.visible,
		"Provider 不可用时宽屏页显示返回模型配置入口",
	)
	composite.call("emit_signal", "provider_settings_pressed")
	for _index in 2:
		await process_frame
	_expect(
		host.get("_startup_settings_page") != null,
		"返回模型配置入口真正打开 Provider 设置页",
	)
	var preserved := coordinator.call("preserved_draft") as Dictionary
	_expect_equal(
		preserved.get("draft"),
		changed_draft,
		"前往模型配置时保留当前草稿",
	)
	provider.set_available(true)
	host.call("_on_startup_settings_intent_requested", &"provider_settings.back", {})
	for _index in 4:
		await process_frame
	coordinator = host.get("_startup_save_model_coordinator") as Object
	routed_service = coordinator.call("assignment") as Object
	_expect_equal(
		routed_service.call("get_session_draft"),
		changed_draft,
		"从模型配置返回后恢复原草稿",
	)
	routed_vm = routed_service.call("get_view_model") as Dictionary
	routed_service.call(
		"dispatch",
		"resident_model_assignment.back",
		{"revision": int(routed_vm.get("revision", -1))},
	)
	for _index in 3:
		await process_frame
	_expect(
		host.get("_startup_load_game_page") != null,
		"离线模型页返回后重新扫描并打开加载存档页",
	)
	root.size = original_viewport_size
	for _index in 3:
		await process_frame
	host.call("_close_startup_load_game")
	await process_frame
	root.remove_child(host)
	host.free()
	root.remove_child(adapter)
	adapter.free()
	current_scene = null
	root.remove_child(startup)
	startup.free()



func _catalog_slot() -> Dictionary:
	return _fixture.catalog_slot()


func _base_catalog() -> Dictionary:
	return _fixture.base_catalog()


func _bindings_for(provider_id: String, model_id: String) -> Array[Dictionary]:
	return _fixture.bindings_for(provider_id, model_id)


func _action(intent: String, enabled: bool) -> Dictionary:
	return {
		"intent": intent,
		"enabled": enabled,
		"disabledReason": "" if enabled else "ACTION_NOT_AVAILABLE",
	}


func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(bool(result.get("ok", false)), "%s：%s" % [message, result])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s（actual=%s expected=%s）" % [message, actual, expected])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
