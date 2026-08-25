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

	func get_health_snapshot() -> Dictionary:
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
	_slot_id = "offline-model-slot-%s-%s" % ["s".repeat(84), identity]
	_session_id = "offline-model-session-%s-%s" % ["r".repeat(80), identity]
	_save_root = "user://tests/town_session_saves/offline_model_%s" % identity
	_agent_root = "user://agent_save_tests/offline_model_%s" % identity
	_profile_path = "user://tests/town_startup_profile/offline_model_%s.json" % identity
	_save_store = SAVE_STORE.new()
	_agent_store = AGENT_STORE.new()
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
		{"residents": []},
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
	first.call("prepare", fresh_slot, {"residents": []})
	second.call("prepare", fresh_slot, {"residents": []})
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
	failure_service.call("prepare", _catalog_slot(), {"residents": []})
	var failed := failure_service.call(
		"apply_bindings",
		_bindings_for("current-provider", "current-model-3"),
	) as Dictionary
	_expect(not bool(failed.get("ok", false)), "manifest 发布失败会返回可重试错误")
	_expect_equal(failed.get("retryable"), true, "磁盘发布失败明确允许玩家重试")
	var after_failure := _save_store.call("list_published", _slot_id) as Dictionary
	_expect_equal(
		(after_failure.get("manifests", []) as Array).size(),
		3,
		"失败提交不影响已有完整修订",
	)
	var leaked_agent := _agent_store.call(
		"load_snapshot",
		{"slot_id": _slot_id, "session_id": _session_id, "save_revision": 4},
	) as Dictionary
	_expect(not bool(leaked_agent.get("ok", false)), "失败提交清理未发布的 Agent 快照")

	await _test_save_slot_page(prepared)
	await _test_game_flow_route(_catalog_slot())


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
	_expect_equal(snapshot.get("saveSlotMode"), true, "模型分配页进入 save_slot 模式")
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
	var startup := Control.new()
	startup.name = "StartupScreen"
	root.add_child(startup)
	current_scene = startup
	var adapter := UI_ADAPTER.new()
	root.add_child(adapter)
	var host := GAME_FLOW_HOST.new()
	root.add_child(host)
	host.set("_startup_save_store", _save_store)
	host.set("_startup_provider_service", FakeProviderService.new())
	host.set("_startup_ui_adapter", adapter)
	var startup_catalog := SAVE_CATALOG.new()
	startup_catalog.call("configure", _save_store, _profile_path, _agent_store)
	host.set("_startup_save_catalog", startup_catalog)
	host.call("_bind_current_scene")
	var projection := host.call("_startup_slot_projection", slot) as Dictionary
	_expect_equal(projection.get("modelEditAvailable"), true, "完整修订开放模型编辑")
	_expect_equal(
		projection.get("modelEditSaveRevision"),
		(slot.get("summary", {}) as Dictionary).get("saveRevision"),
		"加载页钉住被编辑的完整修订",
	)
	var recoverable := slot.duplicate(true)
	recoverable["state"] = "recoverable"
	recoverable["latestEvidenceRevision"] = int(projection.get("saveRevision", 0)) + 1
	var recoverable_projection := host.call(
		"_startup_slot_projection",
		recoverable,
	) as Dictionary
	_expect_equal(recoverable_projection.get("modelEditAvailable"), true, "可回退槽位可编辑最近完整修订")
	_expect_equal(
		recoverable_projection.get("modelEditSaveRevision"),
		projection.get("saveRevision"),
		"可回退槽位明确钉住较旧的完整修订",
	)
	var corrupt := slot.duplicate(true)
	corrupt["state"] = "corrupt"
	corrupt["summary"] = {}
	corrupt["saveBlockers"] = [{"errorCode": "SESSION_SAVE_CORRUPT"}]
	var corrupt_projection := host.call("_startup_slot_projection", corrupt) as Dictionary
	_expect_equal(corrupt_projection.get("modelEditAvailable"), false, "不可修复槽位禁用模型编辑")
	_expect_equal(corrupt_projection.get("modelEditDisabledReason"), "SESSION_SAVE_CORRUPT", "不可修复槽位说明禁用原因")
	var interrupted := slot.duplicate(true)
	interrupted["state"] = "incomplete"
	interrupted["latestEvidenceRevision"] = int(projection.get("saveRevision", 0)) + 1
	var interrupted_projection := host.call(
		"_startup_slot_projection",
		interrupted,
	) as Dictionary
	_expect_equal(interrupted_projection.get("modelEditAvailable"), true, "保存中断槽位仍可编辑最近完整修订")
	host.call("_open_startup_save_model_assignment", slot)
	await process_frame
	var page := host.get("_startup_save_model_page") as Control
	_expect(page != null, "GameFlowHost 从加载页打开离线模型编辑路由")
	if page != null:
		var snapshot := page.call("runtime_gate_snapshot") as Dictionary
		_expect_equal(snapshot.get("saveSlotMode"), true, "Host 路由保留 save_slot 模式")
	_expect(host.get("_gateway") == null, "离线模型编辑不创建 Agent Gateway")
	_expect(host.get("_town_runtime") == null, "离线模型编辑不创建 Town Runtime")
	var routed_service := host.get("_startup_save_model_assignment_service") as Object
	var routed_vm := routed_service.call("get_view_model") as Dictionary
	routed_service.call(
		"dispatch",
		"resident_model_assignment.back",
		{"revision": int(routed_vm.get("revision", -1))},
	)
	for _index in 3:
		await process_frame
	_expect(
		not (host.get("_startup_save_model_preserved_draft") as Dictionary).is_empty(),
		"返回加载页时保留离线模型草稿",
	)
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
