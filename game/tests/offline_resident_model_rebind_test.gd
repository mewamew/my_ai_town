extends SceneTree


const OFFLINE_REBIND := preload(
	"res://world/presentation/session/TownOfflineResidentModelRebindService.gd"
)
const SAVE_STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const AGENT_STORE := preload("res://agent/lifecycle/AgentSaveStore.gd")
const SAVE_MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const SAVE_CATALOG := preload(
	"res://world/presentation/session/TownStartupSaveCatalog.gd"
)
const ASSIGNMENT_SERVICE := preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentService.gd"
)
const UI_ADAPTER := preload(
	"res://world/presentation/ui/TownUiAdapter.gd"
)
const GAME_FLOW_HOST := preload(
	"res://world/presentation/game_flow/GameFlowHost.gd"
)
const GATEWAY := preload(
	"res://world/integration/TownWorldAgentGateway.gd"
)
const CURRENT_SAVE_FIXTURE_ROOT := (
	"res://tests/fixtures/historical_saves/beta6/town_session_saves/slots/"
	+ "roundtrip-slot-beta6/sessions/roundtrip-session-beta6/revisions/"
	+ "00000000000000000001"
)
const CURRENT_AGENT_FIXTURE_ROOT := (
	"res://tests/fixtures/historical_saves/beta6/agent_saves/"
	+ "roundtrip-slot-beta6/sessions/roundtrip-session-beta6/revisions/1"
)


class FakeProviderService:
	extends RefCounted
	var available := true

	func set_available(value: bool) -> void:
		available = value

	func get_health_snapshot() -> Dictionary:
		if not available:
			return {
				"ok": false,
				"errorCode": "PROVIDER_HEALTH_UNAVAILABLE",
				"retryable": false,
			}
		return {
			"ok": true,
			"formalReady": true,
			"capabilityMode": "formal",
			"source": "runtime",
			"providers": [{
				"providerId": "current-provider",
				"label": "当前服务",
				"status": "available",
			}],
		}

	func list_available_models() -> Array:
		var models: Array[Dictionary] = []
		if not available:
			return models
		for model_id in ["current-model", "current-model-2", "current-model-3"]:
			models.append({
				"providerId": "current-provider",
				"modelId": model_id,
				"label": model_id,
				"available": true,
			})
		return models

	func validate_resident_bindings(bindings: Variant) -> Dictionary:
		if not bindings is Array:
			return _failure("SESSION_LLM_BINDINGS_INVALID")
		var errors: Array[Dictionary] = []
		for value: Variant in bindings as Array:
			if not value is Dictionary:
				return _failure("SESSION_LLM_BINDINGS_INVALID")
			var binding := (value as Dictionary).get("llmBinding", {}) as Dictionary
			if (
				String(binding.get("providerId", "")) != "current-provider"
				or String(binding.get("modelId", ""))
				not in ["current-model", "current-model-2", "current-model-3"]
			):
				errors.append({
					"code": "LLM_MODEL_UNAVAILABLE",
					"meta": {
						"residentId": String((value as Dictionary).get("residentId", "")),
						"providerId": String(binding.get("providerId", "")),
						"modelId": String(binding.get("modelId", "")),
					},
				})
		return (
			{"ok": true, "errorCode": "", "retryable": false}
			if errors.is_empty()
			else {
				"ok": false,
				"errorCode": "LLM_MODEL_UNAVAILABLE",
				"retryable": false,
				"errors": errors,
			}
		)

	func create_provider_for_resident(_binding: Dictionary) -> RefCounted:
		return null

	func get_latest_diagnostic(_resident_id: String = "") -> Dictionary:
		return {}

	func _failure(error_code: String) -> Dictionary:
		return {
			"ok": false,
			"errorCode": error_code,
			"retryable": false,
			"errors": [],
		}


class FailPublishStore:
	extends TownSessionSaveStore

	func publish_manifest(_manifest: Variant) -> Dictionary:
		return {
			"ok": false,
			"errorCode": "SESSION_SAVE_MANIFEST_PUBLISH_FAILED",
			"retryable": true,
		}


class FaultInjectingAgentStore:
	extends AgentSaveStore
	var fail_next_discard := false

	func discard_snapshot(context: Variant) -> Dictionary:
		if fail_next_discard:
			fail_next_discard = false
			return {
				"ok": false,
				"errorCode": "TEST_AGENT_SNAPSHOT_DELETE_FAILED",
				"retryable": true,
				"errors": [{"code": "TEST_AGENT_SNAPSHOT_DELETE_FAILED"}],
			}
		return super.discard_snapshot(context)

var _failures: Array[String] = []
var _checks := 0
var _save_store: RefCounted
var _agent_store: RefCounted
var _slot_id := ""
var _session_id := ""
var _save_root := ""
var _agent_root := ""
var _profile_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var identity := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_slot_id = "town-main"
	_session_id = "offline-model-session-%s-%s" % ["r".repeat(80), identity]
	_save_root = "user://tests/town_session_saves/offline_model_%s" % identity
	_agent_root = "user://agent_save_tests/offline_model_%s" % identity
	_profile_path = "user://tests/town_startup_profile/offline_model_%s.json" % identity
	_save_store = SAVE_STORE.new()
	_agent_store = FaultInjectingAgentStore.new()
	_expect_ok(
		_save_store.call("configure_test_root", _save_root) as Dictionary,
		"离线改绑使用隔离的 World 存档目录",
	)
	_expect_ok(
		_agent_store.call("configure_test_root", _agent_root) as Dictionary,
		"离线改绑使用隔离的 Agent 存档目录",
	)
	var source := _create_source_revision()
	_expect_ok(source, "源完整修订可创建")
	if source.get("ok") == true:
		var context := source.get("context", {}) as Dictionary
		_expect(
			ProjectSettings.globalize_path(String(
				_save_store.call("_revision_root", context),
			)).length() >= 260,
			"离线复制夹具跨过传统 Windows 260 字符路径边界",
		)
		await _test_prepare_and_publish(source)
	await _test_load_page_action()
	await _cleanup()
	if _failures.is_empty():
		print("OFFLINE_RESIDENT_MODEL_REBIND_PASS checks=%d" % _checks)
	else:
		for failure in _failures:
			printerr("OFFLINE_RESIDENT_MODEL_REBIND_FAIL: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_prepare_and_publish(source: Dictionary) -> void:
	var slot := _catalog_slot()
	_expect(not slot.is_empty(), "启动目录可读取源完整修订")
	if slot.is_empty():
		return
	var service: RefCounted = OFFLINE_REBIND.new()
	_expect_ok(
		service.call(
			"configure",
			_save_store,
			_agent_store,
			FakeProviderService.new(),
		) as Dictionary,
		"离线改绑服务可绑定 World 与 Agent Store",
	)
	var prepared := service.call(
		"prepare",
		slot,
		_base_catalog(),
	) as Dictionary
	_expect_ok(prepared, "失效的旧绑定不会阻止编辑页准备")
	_expect_equal(
		((prepared.get("draft", {}) as Dictionary).get("slots", []) as Array).size(),
		2,
		"编辑草稿只包含存档中的居民",
	)
	var assignment := ASSIGNMENT_SERVICE.new()
	_expect_ok(
		assignment.configure(
			FakeProviderService.new(),
			prepared.get("residentCatalog", {}) as Dictionary,
			prepared.get("draft", {}) as Dictionary,
		),
		"模型分配页可带着失效旧绑定打开",
	)
	var assignment_data := (
		assignment.get_view_model().get("data", {}) as Dictionary
	)
	_expect_equal(assignment_data.get("invalidCount"), 2, "失效旧绑定显示为待改绑")

	var source_manifest := (
		source.get("manifest", {}) as Dictionary
	).duplicate(true)
	var source_world_hash := String(
		((source_manifest.get("components", {}) as Dictionary).get(
			"world",
			{},
		) as Dictionary).get("snapshot_sha256", ""),
	)
	var rejected_binding := service.call(
		"apply_bindings",
		_bindings_for("current-provider", "removed-model"),
	) as Dictionary
	_expect_equal(
		rejected_binding.get("errorCode"),
		"LLM_MODEL_UNAVAILABLE",
		"事务提交点拒绝已从当前配置移除的目标模型",
	)
	_expect_equal(
		((_save_store.call("list_published", _slot_id) as Dictionary).get(
			"manifests",
			[],
		) as Array).size(),
		1,
		"无效目标绑定不会预留或发布新修订",
	)
	var applied := service.call(
		"apply_bindings",
		_current_bindings(),
	) as Dictionary
	_expect_ok(applied, "离线改绑发布新的完整修订")
	_expect_equal(
		(applied.get("context", {}) as Dictionary).get("save_revision"),
		2,
		"离线改绑发布下一个修订号",
	)
	var manifests := (
		(_save_store.call("list_published", _slot_id) as Dictionary).get(
			"manifests",
			[],
		) as Array
	)
	_expect_equal(manifests.size(), 2, "原修订与新修订同时保留")
	if manifests.size() != 2:
		return
	var old_manifest := manifests[1] as Dictionary
	var new_manifest := manifests[0] as Dictionary
	_expect_equal(old_manifest, source_manifest, "原 manifest 保持只读")
	_expect_equal(
		((old_manifest.get("components", {}) as Dictionary).get(
			"world",
			{},
		) as Dictionary).get("snapshot_sha256"),
		source_world_hash,
		"原 World 哈希保持不变",
	)
	var new_config := _save_store.call(
		"read_reference",
		new_manifest.get("session_config_ref"),
		new_manifest.get("session_config_sha256"),
	) as Dictionary
	_expect_equal(
		(new_config.get("value", {}) as Dictionary).get("residentBindings"),
		_current_bindings(),
		"新修订只采用当前可用模型绑定",
	)
	var gateway := GATEWAY.new()
	var request_host := Node.new()
	root.add_child(request_host)
	var gateway_config := (new_config.get("value", {}) as Dictionary).duplicate(true)
	gateway_config["slotId"] = _slot_id
	gateway_config["sessionId"] = _session_id
	gateway_config["saveRevision"] = 2
	gateway_config["restorePending"] = true
	_expect_ok(
		gateway.call(
			"configure_session",
			gateway_config,
			FakeProviderService.new(),
			request_host,
		) as Dictionary,
		"正常继续入口可用新修订配置 Gateway",
	)
	_expect_equal(
		gateway.call("get_resident_bindings"),
		_current_bindings(),
		"Gateway 实际采用离线改绑后的居民模型",
	)
	gateway.free()
	root.remove_child(request_host)
	request_host.free()
	var old_world := _save_store.call(
		"read_reference",
		((old_manifest.get("components", {}) as Dictionary).get(
			"world",
			{},
		) as Dictionary).get("snapshot_ref"),
		source_world_hash,
	) as Dictionary
	var new_world_component := (
		(new_manifest.get("components", {}) as Dictionary).get("world", {})
		as Dictionary
	)
	var new_world := _save_store.call(
		"read_reference",
		new_world_component.get("snapshot_ref"),
		new_world_component.get("snapshot_sha256"),
	) as Dictionary
	_expect_equal(new_world.get("value"), old_world.get("value"), "World 快照成对复制")
	var old_agent := _agent_store.call(
		"load_snapshot",
		{"slot_id": _slot_id, "session_id": _session_id, "save_revision": 1},
	) as Dictionary
	var new_agent := _agent_store.call(
		"load_snapshot",
		{"slot_id": _slot_id, "session_id": _session_id, "save_revision": 2},
	) as Dictionary
	_expect_equal(
		new_agent.get("resident_payloads"),
		old_agent.get("resident_payloads"),
		"Agent 快照与同一源修订成对复制",
	)

	var fresh_slot := _catalog_slot()
	var first := OFFLINE_REBIND.new()
	var second := OFFLINE_REBIND.new()
	first.call("configure", _save_store, _agent_store, FakeProviderService.new())
	second.call("configure", _save_store, _agent_store, FakeProviderService.new())
	first.call("prepare", fresh_slot, _base_catalog())
	second.call("prepare", fresh_slot, _base_catalog())
	var next_bindings := _bindings_for("current-provider", "current-model-2")
	_expect_ok(
		second.call("apply_bindings", next_bindings) as Dictionary,
		"并发基线中的先提交者成功",
	)
	var stale := first.call("apply_bindings", next_bindings) as Dictionary
	_expect_equal(
		stale.get("errorCode"),
		"OFFLINE_RESIDENT_MODEL_REBIND_TARGET_STALE",
		"目标修订变化后拒绝迟到提交",
	)

	var failure_service := OFFLINE_REBIND.new()
	var failing_store := FailPublishStore.new()
	_expect_ok(
		failing_store.configure_test_root(_save_root),
		"发布失败替身复用隔离的 World 存档目录",
	)
	failure_service.call(
		"configure",
		failing_store,
		_agent_store,
		FakeProviderService.new(),
	)
	failure_service.call("prepare", _catalog_slot(), _base_catalog())
	(_agent_store as FaultInjectingAgentStore).fail_next_discard = true
	var failed := failure_service.call(
		"apply_bindings",
		_bindings_for("current-provider", "current-model-3"),
	) as Dictionary
	_expect(not bool(failed.get("ok", false)), "manifest 发布失败会返回可重试错误")
	_expect_equal(failed.get("retryable"), true, "磁盘发布失败明确允许玩家重试")
	_expect_equal(
		failed.get("errorCode"),
		"OFFLINE_RESIDENT_MODEL_REBIND_CLEANUP_FAILED",
		"Agent 清理失败使用可恢复的清理错误",
	)
	var after_failure := _save_store.call("list_published", _slot_id) as Dictionary
	_expect_equal(
		(after_failure.get("manifests", []) as Array).size(),
		3,
		"失败提交不影响已有完整修订",
	)
	var preserved_agent := _agent_store.call(
		"load_snapshot",
		{"slot_id": _slot_id, "session_id": _session_id, "save_revision": 4},
	) as Dictionary
	_expect_ok(preserved_agent, "Agent 删除失败时保留未发布修订证据")
	_expect_equal(
		((failed.get("meta", {}) as Dictionary).get("context", {}) as Dictionary).get(
			"save_revision",
		),
		4,
		"清理失败回执标记被保留的修订",
	)
	var retry_service := OFFLINE_REBIND.new()
	_expect_ok(
		retry_service.call(
			"configure",
			_save_store,
			_agent_store,
			FakeProviderService.new(),
		) as Dictionary,
		"Agent 清理失败后可重建离线改绑流程",
	)
	_expect_ok(
		retry_service.call("prepare", _catalog_slot(), _base_catalog()) as Dictionary,
		"重试仍钉住原发布修订",
	)
	var retried := retry_service.call(
		"apply_bindings",
		_bindings_for("current-provider", "current-model-3"),
	) as Dictionary
	_expect_ok(retried, "重试跳过残留修订并成功发布")
	_expect_equal(
		(retried.get("context", {}) as Dictionary).get("save_revision"),
		5,
		"残留 allocation 推动修订号前进",
	)
	var resaved := _publish_copy_of_latest_revision()
	_expect_ok(resaved, "改绑后可再次发布成对存档")
	_expect_equal(
		(resaved.get("context", {}) as Dictionary).get("save_revision"),
		6,
		"改绑后的再次存档使用下一修订",
	)
	var reopened := _fresh_catalog_slot()
	_expect_equal(
		(reopened.get("summary", {}) as Dictionary).get("saveRevision"),
		6,
		"重新扫描读取重试发布的修订",
	)
	_expect_equal(
		(reopened.get("sessionConfig", {}) as Dictionary).get("residentBindings"),
		_bindings_for("current-provider", "current-model-3"),
		"退出并重开后仍保留改绑结果",
	)
	var recoverable_slot := _create_recoverable_catalog_slot()

	await _test_save_slot_page(prepared)
	await _test_game_flow_route(recoverable_slot)


func _test_load_page_action() -> void:
	var scene := load("res://ui/startup/StartupLoadGameScreen.tscn") as PackedScene
	var screen := scene.instantiate() as Control
	root.add_child(screen)
	var intents: Array[String] = []
	var routed_payloads: Array[Dictionary] = []
	screen.intent_requested.connect(
		func(intent: StringName, payload: Dictionary) -> void:
			intents.append(String(intent))
			routed_payloads.append(payload.duplicate(true)),
	)
	var view_model := {
		"scope": "save",
		"status": "ready",
		"revision": 1,
		"data": {
			"mode": "load",
			"providerIndependent": true,
			"slots": [{
				"slotId": "slot-a",
				"displayName": "第一座小镇",
				"sessionId": "session-a",
				"saveRevision": 7,
				"state": "recoverable",
				"continueAvailable": true,
				"modelEditAvailable": true,
				"modelEditSaveRevision": 7,
				"modelEditDisabledReason": "",
			}],
		},
		"actions": {
			"back": _action("startup.close_load_game", true),
			"continueSlot": _action("session.continue_slot", true),
			"deleteSlot": _action("save.request_delete_slot", true),
			"editResidentModels": _action("save.edit_resident_models", true),
		},
		"operation": {},
		"error": null,
	}
	_expect(bool(screen.call("apply_view_model", view_model)), "加载页接受模型编辑动作")
	await process_frame
	var compact_touch_height := (
		(screen.call("_source_rect", Rect2(0, 0, 1, 64)) as Rect2).size.y
		* 720.0
		/ 1080.0
	)
	_expect(
		compact_touch_height >= 48.0,
		"紧凑横屏下删除与模型编辑按钮仍满足 48 像素触控高度",
	)
	var edit_button := screen.find_child("slot-aModelEditAction", true, false) as Button
	_expect(edit_button != null, "完整修订卡片显示更改居民模型按钮")
	if edit_button != null:
		_expect(
			edit_button.size.y >= 48.0,
			"更改居民模型按钮满足触控高度",
		)
		edit_button.grab_focus()
		var refreshed_view_model := view_model.duplicate(true)
		refreshed_view_model["revision"] = 2
		_expect(
			bool(screen.call("apply_view_model", refreshed_view_model)),
			"加载页后台刷新保留模型编辑契约",
		)
		await process_frame
		edit_button = screen.find_child("slot-aModelEditAction", true, false) as Button
		_expect_equal(
			root.get_viewport().gui_get_focus_owner(),
			edit_button,
			"加载页刷新后恢复模型编辑按钮焦点",
		)
		screen.call("debug_request_edit_resident_models", "slot-a")
	_expect_equal(intents, ["save.edit_resident_models"], "加载页发出离线改绑意图")
	_expect_equal(
		(routed_payloads[0] as Dictionary).get("saveRevision")
		if not routed_payloads.is_empty()
		else null,
		7,
		"回退槽位明确编辑的完整修订",
	)
	root.remove_child(screen)
	screen.free()


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
		FakeProviderService.new(),
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
	_expect(
		InputMap.event_is_action(gamepad_accept, "ui_accept"),
		"手柄 A 键映射为界面确认操作",
	)
	_expect_equal(
		root.get_viewport().gui_get_focus_owner(),
		mode_button,
		"切换模式按钮在手柄操作前保持焦点",
	)
	mode_button.pressed.emit()
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
	root.remove_child(screen)
	screen.free()
	root.remove_child(adapter)
	adapter.free()


func _test_game_flow_route(slot: Dictionary) -> void:
	_expect_equal(slot.get("state"), "recoverable", "GameFlow 验收使用真实可修复 catalog 槽位")
	var guarded_service := OFFLINE_REBIND.new()
	guarded_service.call(
		"configure",
		_save_store,
		_agent_store,
		FakeProviderService.new(),
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
	var provider := FakeProviderService.new()
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


func _create_source_revision() -> Dictionary:
	var payloads := {
		"resident-a": {
			"resident_name": "甲居民",
			"payload": FileAccess.get_file_as_bytes(
				"%s/resident_0000.bin" % CURRENT_AGENT_FIXTURE_ROOT,
			),
		},
		"resident-b": {
			"resident_name": "乙居民",
			"payload": FileAccess.get_file_as_bytes(
				"%s/resident_0001.bin" % CURRENT_AGENT_FIXTURE_ROOT,
			),
		},
	}
	var revision_zero := {
		"slot_id": _slot_id,
		"session_id": _session_id,
		"save_revision": 0,
	}
	var created := _agent_store.call(
		"create_new_game",
		revision_zero,
		payloads,
	) as Dictionary
	if created.get("ok") != true:
		return created
	var reserved := _save_store.call(
		"reserve_revision",
		_slot_id,
		_session_id,
	) as Dictionary
	if reserved.get("ok") != true:
		return reserved
	var context := reserved.get("context", {}) as Dictionary
	var agent_saved := _agent_store.call("save_snapshot", context, payloads) as Dictionary
	if agent_saved.get("ok") != true:
		return agent_saved
	var stored := _save_store.call(
		"write_world_candidate",
		context,
		_world_snapshot(),
		_session_config(),
		_world_log_snapshot(),
	) as Dictionary
	if stored.get("ok") != true:
		return stored
	var manifest := SAVE_MANIFEST.build(
		context,
		Time.get_datetime_string_from_system(false, false),
		String(stored.get("sessionConfigRef", "")),
		String(stored.get("sessionConfigSha256", "")),
		["resident-a", "resident-b"],
		{
			"snapshotRef": String(stored.get("snapshotRef", "")),
			"worldRevision": 9,
			"schema": "town-world-save",
			"schemaVersion": 2,
			"worldDataVersion": 4,
			"day": 1,
		},
		String(stored.get("snapshotSha256", "")),
		[],
		{
			"snapshotRef": String(stored.get("worldLogSnapshotRef", "")),
			"snapshotSha256": String(stored.get("worldLogSnapshotSha256", "")),
			"schema": "town-world-log-snapshot",
			"schemaVersion": 1,
			"timelineId": "offline-model-timeline",
			"maxSequence": 0,
			"worldRevision": 9,
		},
	) as Dictionary
	var published := _save_store.call("publish_manifest", manifest) as Dictionary
	if published.get("ok") != true:
		return published
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"context": context,
		"manifest": manifest,
	}


func _catalog_slot() -> Dictionary:
	var catalog := SAVE_CATALOG.new()
	var configured := catalog.call(
		"configure",
		_save_store,
		_profile_path,
		_agent_store,
	) as Dictionary
	if configured.get("ok") != true:
		_failures.append("启动存档目录配置失败：%s" % configured)
		return {}
	var result := catalog.call(
		"get_catalog",
		[
			{"slotId": _slot_id, "displayName": "离线模型小镇"},
			{"slotId": "empty-slot", "displayName": "空槽位"},
		],
	) as Dictionary
	if result.get("ok") != true:
		_failures.append("启动存档目录读取失败：%s" % result)
		return {}
	return ((result.get("slots", []) as Array)[0] as Dictionary).duplicate(true)


func _fresh_catalog_slot() -> Dictionary:
	var fresh_store := SAVE_STORE.new()
	var fresh_agent := AGENT_STORE.new()
	_expect_ok(
		fresh_store.call("configure_test_root", _save_root) as Dictionary,
		"重开时可重新绑定 World 存档目录",
	)
	_expect_ok(
		fresh_agent.call("configure_test_root", _agent_root) as Dictionary,
		"重开时可重新绑定 Agent 存档目录",
	)
	var catalog := SAVE_CATALOG.new()
	_expect_ok(
		catalog.call(
			"configure",
			fresh_store,
			_profile_path.trim_suffix(".json") + "_reopened.json",
			fresh_agent,
		) as Dictionary,
		"重开时可重建启动存档目录",
	)
	var result := catalog.call(
		"get_catalog",
		[
			{"slotId": _slot_id, "displayName": "离线模型小镇"},
			{"slotId": "town-2", "displayName": "空槽位"},
		],
	) as Dictionary
	_expect_ok(result, "重开后可重新扫描存档")
	return (
		((result.get("slots", []) as Array)[0] as Dictionary).duplicate(true)
		if (result.get("slots", []) as Array).size() > 0
		else {}
	)


func _create_recoverable_catalog_slot() -> Dictionary:
	var listed := _save_store.call("list_published", _slot_id) as Dictionary
	var manifests := listed.get("manifests", []) as Array
	_expect(not manifests.is_empty(), "可修复夹具有已发布基线")
	if manifests.is_empty():
		return {}
	var latest := manifests[0] as Dictionary
	var components := latest.get("components", {}) as Dictionary
	var world_component := components.get("world", {}) as Dictionary
	var log_component := components.get("world_log", {}) as Dictionary
	var world := _save_store.call(
		"read_reference",
		world_component.get("snapshot_ref"),
		world_component.get("snapshot_sha256"),
	) as Dictionary
	var config := _save_store.call(
		"read_reference",
		latest.get("session_config_ref"),
		latest.get("session_config_sha256"),
	) as Dictionary
	var world_log := _save_store.call(
		"read_world_log_snapshot",
		log_component.get("snapshot_ref"),
		log_component.get("snapshot_sha256"),
	) as Dictionary
	var source_agent := _agent_store.call(
		"load_snapshot",
		{
			"slot_id": _slot_id,
			"session_id": _session_id,
			"save_revision": int(latest.get("save_revision", 0)),
		},
	) as Dictionary
	var reserved := _save_store.call(
		"reserve_revision",
		_slot_id,
		_session_id,
	) as Dictionary
	_expect_ok(reserved, "可修复夹具预留下一修订")
	var context := reserved.get("context", {}) as Dictionary
	var begun := _save_store.call("begin_intent", context, "save") as Dictionary
	_expect_ok(begun, "可修复夹具建立真实保存 intent")
	var intent_id := String(begun.get("intentId", ""))
	_expect_ok(
		_save_store.call(
			"write_intent_stage", context, "save", intent_id, "save_started", {},
		) as Dictionary,
		"可修复夹具写入保存开始阶段",
	)
	var stored := _save_store.call(
		"write_world_candidate",
		context,
		(world.get("value", {}) as Dictionary).duplicate(true),
		(config.get("value", {}) as Dictionary).duplicate(true),
		(world_log.get("value", {}) as Dictionary).duplicate(true),
	) as Dictionary
	_expect_ok(stored, "可修复夹具写入 World 候选")
	for stage in ["world_candidate_written", "agent_commit_started"]:
		_expect_ok(
			_save_store.call(
				"write_intent_stage", context, "save", intent_id, stage, {},
			) as Dictionary,
			"可修复夹具写入 %s 阶段" % stage,
		)
	_expect_ok(
		_agent_store.call(
			"save_snapshot",
			context,
			(source_agent.get("resident_payloads", {}) as Dictionary).duplicate(true),
		) as Dictionary,
		"可修复夹具写入 Agent 快照",
	)
	_expect_ok(
		_save_store.call(
			"write_intent_stage", context, "save", intent_id, "agent_committed", {},
		) as Dictionary,
		"可修复夹具停在 Agent 已提交阶段",
	)
	var slot := _catalog_slot()
	_expect_equal(slot.get("state"), "recoverable", "真实 catalog 将中断保存分类为可修复")
	_expect(
		not (slot.get("saveBlockers", []) as Array).is_empty(),
		"可修复槽位保留真实保存 blocker",
	)
	_expect_equal(
		(slot.get("reconciliationPlan", {}) as Dictionary).get("repairable"),
		true,
		"恢复协调计划明确可修复",
	)
	return slot


func _publish_copy_of_latest_revision() -> Dictionary:
	var listed := _save_store.call("list_published", _slot_id) as Dictionary
	var manifests := listed.get("manifests", []) as Array
	if manifests.is_empty():
		return {"ok": false, "errorCode": "TEST_SOURCE_MANIFEST_MISSING"}
	var source := manifests[0] as Dictionary
	var components := source.get("components", {}) as Dictionary
	var world_component := components.get("world", {}) as Dictionary
	var log_component := components.get("world_log", {}) as Dictionary
	var world := _save_store.call(
		"read_reference",
		world_component.get("snapshot_ref"),
		world_component.get("snapshot_sha256"),
	) as Dictionary
	var config := _save_store.call(
		"read_reference",
		source.get("session_config_ref"),
		source.get("session_config_sha256"),
	) as Dictionary
	var world_log := _save_store.call(
		"read_world_log_snapshot",
		log_component.get("snapshot_ref"),
		log_component.get("snapshot_sha256"),
	) as Dictionary
	var source_context := {
		"slot_id": _slot_id,
		"session_id": _session_id,
		"save_revision": int(source.get("save_revision", 0)),
	}
	var agent := _agent_store.call("load_snapshot", source_context) as Dictionary
	for result in [world, config, world_log, agent]:
		if not bool((result as Dictionary).get("ok", false)):
			return result as Dictionary
	var reserved := _save_store.call(
		"reserve_revision",
		_slot_id,
		_session_id,
	) as Dictionary
	if reserved.get("ok") != true:
		return reserved
	var context := reserved.get("context", {}) as Dictionary
	var stored := _save_store.call(
		"write_world_candidate",
		context,
		(world.get("value", {}) as Dictionary).duplicate(true),
		(config.get("value", {}) as Dictionary).duplicate(true),
		(world_log.get("value", {}) as Dictionary).duplicate(true),
	) as Dictionary
	if stored.get("ok") != true:
		return stored
	var saved_agent := _agent_store.call(
		"save_snapshot",
		context,
		(agent.get("resident_payloads", {}) as Dictionary).duplicate(true),
	) as Dictionary
	if saved_agent.get("ok") != true:
		return saved_agent
	var manifest := SAVE_MANIFEST.build(
		context,
		Time.get_datetime_string_from_system(false, false),
		stored.get("sessionConfigRef"),
		stored.get("sessionConfigSha256"),
		(source.get("resident_ids", []) as Array).duplicate(),
		{
			"snapshotRef": stored.get("snapshotRef"),
			"worldRevision": world_component.get("world_revision"),
			"schema": world_component.get("schema"),
			"schemaVersion": world_component.get("schema_version"),
			"worldDataVersion": world_component.get("world_data_version"),
			"day": world_component.get("day"),
		},
		stored.get("snapshotSha256"),
		SAVE_MANIFEST.resident_messages(source),
		{
			"snapshotRef": stored.get("worldLogSnapshotRef"),
			"snapshotSha256": stored.get("worldLogSnapshotSha256"),
			"schema": log_component.get("schema"),
			"schemaVersion": log_component.get("schema_version"),
			"timelineId": log_component.get("timeline_id"),
			"maxSequence": log_component.get("max_sequence"),
			"worldRevision": log_component.get("world_revision"),
		},
	) as Dictionary
	var published := _save_store.call("publish_manifest", manifest) as Dictionary
	if published.get("ok") != true:
		return published
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"context": context,
		"manifest": manifest,
	}


func _base_catalog() -> Dictionary:
	return {
		"residents": [
			{
				"residentId": "resident-a",
				"attributes": {"name": "甲居民"},
				"presentation": {"portraitRef": "res://missing/portrait-a.png"},
			},
			{
				"residentId": "resident-b",
				"attributes": {"name": "乙居民"},
				"presentation": {},
			},
		],
	}


func _session_config() -> Dictionary:
	var fixture := _read_json("%s/session_config.json" % CURRENT_SAVE_FIXTURE_ROOT)
	return {
		"mode": "continue",
		"sessionId": _session_id,
		"openingConfig": (
			fixture.get("openingConfig", {}) as Dictionary
		).duplicate(true),
		"residentIdentities": [
			{"residentId": "resident-a", "residentName": "甲居民"},
			{"residentId": "resident-b", "residentName": "乙居民"},
		],
		"residentBindings": _bindings_for("retired-provider", "retired-model"),
		"connectedResidents": ["甲居民", "乙居民"],
		"worldStartMode": "formal",
		"useLiveModel": true,
		"enablePlayerAvatar": false,
		"enableTestUi": false,
	}


func _current_bindings() -> Array[Dictionary]:
	return _bindings_for("current-provider", "current-model")


func _bindings_for(provider_id: String, model_id: String) -> Array[Dictionary]:
	return [
		{
			"residentId": "resident-a",
			"llmBinding": {
				"mode": "model",
				"providerId": provider_id,
				"modelId": model_id,
			},
		},
		{
			"residentId": "resident-b",
			"llmBinding": {
				"mode": "model",
				"providerId": provider_id,
				"modelId": model_id,
			},
		},
	]


func _world_snapshot() -> Dictionary:
	return _read_json("%s/world_snapshot.json" % CURRENT_SAVE_FIXTURE_ROOT)


func _world_log_snapshot() -> Dictionary:
	return {
		"schema": "town-world-log-snapshot",
		"schemaVersion": 1,
		"timelineId": "offline-model-timeline",
		"worldRevision": 9,
		"maxSequence": 0,
		"records": [],
		"readState": {},
	}


func _action(intent: String, enabled: bool) -> Dictionary:
	return {
		"intent": intent,
		"enabled": enabled,
		"disabledReason": "" if enabled else "ACTION_NOT_AVAILABLE",
	}


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _cleanup() -> void:
	if _agent_store != null:
		_agent_store.call("cleanup_test_root")
	if _save_store != null:
		_save_store.call("cleanup_test_root")
	if FileAccess.file_exists(_profile_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_profile_path))
	var reopened_profile := _profile_path.trim_suffix(".json") + "_reopened.json"
	if FileAccess.file_exists(reopened_profile):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(reopened_profile))
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	await create_timer(0.3, true, false, true).timeout


func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(bool(result.get("ok", false)), "%s：%s" % [message, result])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s（actual=%s expected=%s）" % [message, actual, expected])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
