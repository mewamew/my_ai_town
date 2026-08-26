extends SceneTree


const OFFLINE_REBIND := preload(
	"res://world/presentation/session/TownOfflineResidentModelRebindService.gd"
)
const ASSIGNMENT_SERVICE := preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentService.gd"
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
	var service := OFFLINE_REBIND.new() as RefCounted
	_expect_ok(service.call("configure", _save_store, _agent_store, _fixture.provider()) as Dictionary, "UI/路由故事可配置离线改绑服务")
	var prepared := service.call("prepare", _catalog_slot(), _base_catalog()) as Dictionary
	_expect_ok(prepared, "UI/路由故事可准备失效旧绑定")
	var interrupted: Dictionary = _fixture.create_recoverable_catalog_slot()
	_expect_ok(interrupted, "UI/路由故事可建立真实可恢复目录状态")
	var recoverable_slot := interrupted.get("slot", {}) as Dictionary
	await _test_pending_target_drift(recoverable_slot)
	await _test_host_stale_feedback()
	interrupted = _fixture.create_recoverable_catalog_slot()
	_expect_ok(interrupted, "并发发布后可再次建立恢复路由夹具")
	recoverable_slot = interrupted.get("slot", {}) as Dictionary
	await _test_save_slot_page(prepared)
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
	_expect_ok(
		host.call("_ensure_startup_save_model_coordinator") as Dictionary,
		"Host stale 故事可配置离线改绑协调器",
	)
	var coordinator := host.get("_startup_save_model_coordinator") as Object
	var selected_slot := _catalog_slot()
	var selected_revision := int(
		(selected_slot.get("summary", {}) as Dictionary).get("saveRevision", -1),
	)
	_expect_ok(
		coordinator.call("select_target", selected_slot) as Dictionary,
		"Host stale 故事保存加载页选定修订",
	)
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
	host.call("_resume_startup_save_model_assignment")
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
		"stale 后重新打开可见的加载页（last=%s）" % host.get("_last_result"),
	)
	_expect(
		feedback != null
		and feedback.is_visible_in_tree()
		and feedback.text.contains("存档已更新，请重新选择完整修订"),
		"加载页自身显示明确的 stale 提示（feedback=%s）" % (
			feedback.text if feedback != null else "missing"
		),
	)
	_expect_equal(
		(coordinator.call("target") as Dictionary).get("saveRevision"),
		selected_revision,
		"Host stale 提示仍对应玩家原先确认的修订",
	)
	host.call("_close_startup_load_game")
	root.remove_child(host)
	host.free()
	root.remove_child(adapter)
	adapter.free()
	current_scene = null
	root.remove_child(startup)
	startup.free()


func _test_save_slot_page(prepared: Dictionary) -> void:
	var valid_draft := (prepared.get("draft", {}) as Dictionary).duplicate(true)
	var slots := valid_draft.get("slots", []) as Array
	for index in slots.size():
		var slot := (slots[index] as Dictionary).duplicate(true)
		slot["llmBinding"] = {
			"mode": "model",
			"providerId": "current-provider",
			"modelId": "current-model",
		}
		slots[index] = slot
	valid_draft["slots"] = slots
	var assignment := ASSIGNMENT_SERVICE.new()
	assignment.configure(
		_fixture.provider(),
		prepared.get("residentCatalog", {}) as Dictionary,
		valid_draft,
	)
	_expect(
		String(assignment.call(
			"_error_message",
			"SESSION_SAVE_MANIFEST_PUBLISH_FAILED",
		)).contains("重试"),
		"磁盘发布失败给出明确重试说明",
	)
	_expect(
		String(assignment.call(
			"_error_message",
			"OFFLINE_RESIDENT_MODEL_REBIND_TARGET_STALE",
		)).contains("返回加载页"),
		"并发冲突提示重新选择最新修订",
	)
	var adapter := UI_ADAPTER.new()
	root.add_child(adapter)
	adapter.bind_resident_model_assignment_service(assignment)
	var scene := load(
		"res://ui/resident_model_assignment/ResidentModelAssignmentScreen.tscn",
	) as PackedScene
	var screen := scene.instantiate() as Control
	screen.call("apply_route_payload", {"mode": "save_slot"})
	screen.call("bind_town_ui_adapter", adapter)
	root.add_child(screen)
	await process_frame
	var snapshot := screen.call("runtime_gate_snapshot") as Dictionary
	_expect_equal(snapshot.get("routeMode"), "save_slot", "模型分配页只保留一个 save_slot RouteMode")
	var layout_cases := [
		[Vector2(1920, 1080), "wide", "宽屏"],
		[Vector2(960, 540), "compact", "紧凑横屏"],
		[Vector2(540, 960), "portrait", "紧凑竖屏"],
	]
	for layout_case_value: Variant in layout_cases:
		var layout_case := layout_case_value as Array
		screen.call("_apply_responsive_layout_for_size", layout_case[0] as Vector2)
		await process_frame
		snapshot = screen.call("runtime_gate_snapshot") as Dictionary
		_expect_equal(
			snapshot.get("profile"),
			layout_case[1],
			"%s 使用预期布局" % String(layout_case[2]),
		)
		for target_value: Variant in snapshot.get("touchTargets", []) as Array:
			var target := target_value as Dictionary
			_expect(
				bool(target.get("minimumMet", false)),
				"%s 可见操作区 %s 满足 48 像素" % [
					String(layout_case[2]),
					String(target.get("id", "")),
				],
			)
		_expect_touch_targets_do_not_overlap(
			snapshot.get("touchTargets", []) as Array,
			String(layout_case[2]),
		)
	screen.call("_apply_responsive_layout_for_size", Vector2(1920, 1080))
	await process_frame
	var list_fallback := screen.find_child(
		"ResidentPortraitFallback0",
		true,
		false,
	) as Label
	var detail_fallback := screen.find_child(
		"SelectedResidentPortraitFallback",
		true,
		false,
	) as Label
	_expect(
		list_fallback != null and list_fallback.visible and list_fallback.text == "甲",
		"列表区头像缺失时显示姓名首字",
	)
	_expect(
		detail_fallback != null and detail_fallback.visible and detail_fallback.text == "甲",
		"详情区头像缺失时显示姓名首字",
	)
	screen.call("_apply_responsive_layout_for_size", Vector2(960, 540))
	await process_frame
	var mode_button := screen.find_child("ModeButton", true, false) as Button
	mode_button.grab_focus()
	var keyboard_accept := InputEventKey.new()
	keyboard_accept.keycode = KEY_ENTER
	keyboard_accept.pressed = true
	Input.parse_input_event(keyboard_accept)
	keyboard_accept = keyboard_accept.duplicate()
	keyboard_accept.pressed = false
	Input.parse_input_event(keyboard_accept)
	await process_frame
	_expect_equal(
		((assignment.get_view_model().get("data", {}) as Dictionary).get("mode")),
		"batch",
		"键盘 Enter 可操作当前焦点",
	)
	var gamepad_accept := InputEventJoypadButton.new()
	gamepad_accept.button_index = JOY_BUTTON_A
	gamepad_accept.pressed = true
	mode_button.grab_focus()
	for _index in 3:
		await process_frame
		if root.get_viewport().gui_get_focus_owner() != mode_button:
			mode_button.grab_focus()
	_expect(
		InputMap.event_is_action(gamepad_accept, "ui_accept"),
		"手柄 A 键映射为界面确认操作",
	)
	var gamepad_down := InputEventJoypadButton.new()
	gamepad_down.button_index = JOY_BUTTON_DPAD_DOWN
	gamepad_down.pressed = true
	_expect(
		InputMap.event_is_action(gamepad_down, "ui_down"),
		"手柄方向键映射为界面向下导航",
	)
	Input.parse_input_event(gamepad_down)
	for _index in 2:
		await process_frame
	gamepad_down = gamepad_down.duplicate()
	gamepad_down.pressed = false
	Input.parse_input_event(gamepad_down)
	await process_frame
	var traversed_focus := root.get_viewport().gui_get_focus_owner() as Control
	_expect(
		traversed_focus != null and traversed_focus != mode_button,
		"手柄方向键实际移动页面焦点",
	)
	mode_button.grab_focus()
	for _index in 2:
		await process_frame
	Input.parse_input_event(gamepad_accept)
	await process_frame
	gamepad_accept = gamepad_accept.duplicate()
	gamepad_accept.pressed = false
	Input.parse_input_event(gamepad_accept)
	await process_frame
	_expect_equal(
		((assignment.get_view_model().get("data", {}) as Dictionary).get("mode")),
		"single",
		"手柄 A 键可操作当前焦点",
	)
	var apply_button := screen.find_child("ApplyDraftButton", true, false) as Button
	_expect(
		apply_button != null and apply_button.text == "保存到此存档",
		"save_slot 模式使用存档专用提交文案",
	)
	var back_button := screen.find_child("BackButton", true, false) as Button
	_expect(
		back_button != null and back_button.text == "← 返回加载存档",
		"save_slot 模式显示正确的返回目标",
	)
	screen.call("_open_completion_modal")
	await process_frame
	var native_body := screen.get("_native_modal_body") as Label
	var native_start := screen.get("_native_modal_start_button") as Button
	var simplified := screen.find_child(
		"ResidentModelAssignmentOriginalSimplifiedV34",
		true,
		false,
	) as Control
	var simplified_button_labels := simplified.get("_button_labels") as Dictionary
	var simplified_primary := simplified.get("_completion_message_primary") as Label
	var simplified_secondary := simplified.get("_completion_message_secondary") as Label
	var simplified_start_copy := simplified_button_labels.get("modal_start") as Label
	var completion_controls_ready := (
		native_body != null
		and native_start != null
		and simplified_primary != null
		and simplified_secondary != null
		and simplified_start_copy != null
	)
	_expect(completion_controls_ready, "两套完成弹窗控件均已创建")
	if completion_controls_ready:
		_expect_equal(
			native_body.text,
			"%s\n%s" % [simplified_primary.text, simplified_secondary.text],
			"响应式与宽屏完成文案来自同一策略",
		)
		_expect_equal(
			native_start.text,
			simplified_start_copy.text,
			"响应式与宽屏完成按钮文案一致",
		)
	root.remove_child(screen)
	screen.free()
	root.remove_child(adapter)
	adapter.free()


func _expect_touch_targets_do_not_overlap(targets: Array, layout_name: String) -> void:
	var key_ids := [
		"BackButton", "ProviderSettingsButton", "ModeButton", "RefreshButton",
		"AssignButton", "ApplyDraftButton", "Simplified:back", "Simplified:mode",
		"Simplified:provider_settings", "Simplified:assign", "Simplified:apply",
	]
	var key_targets: Array[Dictionary] = []
	for target_value: Variant in targets:
		var target := target_value as Dictionary
		if String(target.get("id", "")) in key_ids:
			key_targets.append(target)
	for left_index in key_targets.size():
		var left := key_targets[left_index]
		var left_rect := _rect_from_gate(left.get("rect", []) as Array)
		for right_index in range(left_index + 1, key_targets.size()):
			var right := key_targets[right_index]
			var right_rect := _rect_from_gate(right.get("rect", []) as Array)
			_expect(
				not left_rect.intersects(right_rect),
				"%s 关键操作区 %s 与 %s 不重叠" % [
					layout_name,
					String(left.get("id", "")),
					String(right.get("id", "")),
				],
			)


func _rect_from_gate(values: Array) -> Rect2:
	if values.size() != 4:
		return Rect2()
	return Rect2(
		float(values[0]),
		float(values[1]),
		float(values[2]),
		float(values[3]),
	)


func _test_game_flow_route(slot: Dictionary) -> void:
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
	page.call("_apply_responsive_layout_for_size", Vector2(1920, 1080))
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
