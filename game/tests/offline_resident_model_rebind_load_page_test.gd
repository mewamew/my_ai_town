extends SceneTree


const OFFLINE_REBIND := preload(
	"res://world/presentation/session/TownOfflineResidentModelRebindService.gd"
)
const STARTUP_REBIND_COORDINATOR := preload(
	"res://world/presentation/game_flow/TownStartupOfflineResidentModelRebindCoordinator.gd"
)
const FIXTURE := preload("res://tests/support/OfflineResidentModelRebindFixture.gd")


var _failures: Array[String] = []
var _checks := 0
var _fixture: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var identity := "l%d%d" % [
		OS.get_process_id() % 10000,
		Time.get_ticks_usec() % 1000000,
	]
	_fixture = FIXTURE.new()
	_expect_ok(_fixture.call("configure", identity) as Dictionary, "加载页专项使用隔离夹具")
	_expect_ok(_fixture.call("create_source_revision") as Dictionary, "加载页专项创建健康修订")
	var healthy_slot := _fixture.call("catalog_slot") as Dictionary
	var interrupted := _fixture.call("create_recoverable_catalog_slot") as Dictionary
	_expect_ok(interrupted, "加载页专项建立真实保存中断槽位")
	await _test_slot_state_matrix(
		healthy_slot,
		interrupted.get("slot", {}) as Dictionary,
		identity,
	)
	await _test_load_page_action()
	_fixture.call("cleanup")
	_fixture = null
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
	await create_timer(0.3, true, false, true).timeout
	if _failures.is_empty():
		print("OFFLINE_RESIDENT_MODEL_REBIND_LOAD_PAGE_PASS checks=%d" % _checks)
	else:
		for failure in _failures:
			printerr("OFFLINE_RESIDENT_MODEL_REBIND_LOAD_PAGE_FAIL: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_slot_state_matrix(
	healthy_slot: Dictionary,
	interrupted_slot: Dictionary,
	identity: String,
) -> void:
	var fallback_case := _damaged_slot_case("fallback-%s" % identity, true)
	var corrupt_case := _damaged_slot_case("corrupt-%s" % identity, false)
	_expect_ok(fallback_case, "四态矩阵可建立真实旧完整修订回退槽位")
	_expect_ok(corrupt_case, "四态矩阵可建立真实不可修复槽位")
	if fallback_case.get("ok") != true or corrupt_case.get("ok") != true:
		_cleanup_case_fixture(fallback_case)
		_cleanup_case_fixture(corrupt_case)
		return
	var fallback_slot := fallback_case.get("slot", {}) as Dictionary
	var corrupt_slot := corrupt_case.get("slot", {}) as Dictionary
	_expect_equal(fallback_slot.get("state"), "recoverable", "真实损坏样本分类为可回退")
	_expect_equal(corrupt_slot.get("state"), "corrupt", "无旧完整修订的损坏样本分类为不可修复")
	var cases := [
		{
			"name": "健康槽位",
			"slot": healthy_slot,
			"editEnabled": true,
			"editReason": "编辑完整修订",
			"description": "第",
		},
		{
			"name": "真实可回退槽位",
			"slot": fallback_slot,
			"editEnabled": false,
			"editReason": "请先完成存档恢复，再重新选择完整修订",
			"description": "损坏修订",
		},
		{
			"name": "不可修复槽位",
			"slot": corrupt_slot,
			"editEnabled": false,
			"editReason": "当前没有可用的完整存档",
			"description": "存档损坏",
		},
		{
			"name": "保存中断槽位",
			"slot": interrupted_slot,
			"editEnabled": true,
			"editReason": "编辑完整修订",
			"description": "保存未完成",
		},
	]
	var scene := load("res://ui/startup/StartupLoadGameScreen.tscn") as PackedScene
	var screen := scene.instantiate() as Control
	root.add_child(screen)
	var revision := 10
	for case_value: Variant in cases:
		var state_case := case_value as Dictionary
		var projected := _load_page_slot(state_case.get("slot", {}) as Dictionary)
		var view_model := _load_page_view_model([projected], revision)
		revision += 1
		_expect(
			bool(screen.call("apply_view_model", view_model)),
			"%s 可渲染加载页状态" % String(state_case.get("name", "")),
		)
		await process_frame
		var slot_id := String(projected.get("slotId", ""))
		var edit := screen.find_child("%sModelEditAction" % slot_id, true, false) as Button
		var primary := screen.find_child("%sAction" % slot_id, true, false) as Button
		var recovery := screen.find_child("%sRecovery" % slot_id, true, false) as Label
		_expect_equal(
			not edit.disabled if edit != null else false,
			bool(state_case.get("editEnabled", false)),
			"%s 的改绑按钮状态正确" % String(state_case.get("name", "")),
		)
		_expect(
			edit != null and edit.tooltip_text.contains(String(state_case.get("editReason", ""))),
			"%s 的改绑说明明确（tooltip=%s）" % [
				String(state_case.get("name", "")),
				edit.tooltip_text if edit != null else "missing",
			],
		)
		_expect_equal(
			primary.disabled if primary != null else true,
			not (
				bool(projected.get("continueAvailable", false))
				or bool(projected.get("diagnosticAvailable", false))
			),
			"%s 的主操作状态符合目录能力" % String(state_case.get("name", "")),
		)
		_expect(
			recovery != null
			and recovery.text.contains(String(state_case.get("description", ""))),
			"%s 显示对应的存档状态说明" % String(state_case.get("name", "")),
		)
	root.remove_child(screen)
	screen.free()
	_cleanup_case_fixture(fallback_case)
	_cleanup_case_fixture(corrupt_case)


func _damaged_slot_case(case_id: String, with_fallback: bool) -> Dictionary:
	var fixture := FIXTURE.new() as RefCounted
	var configured := fixture.call("configure", case_id) as Dictionary
	if configured.get("ok") != true:
		return configured
	var source := fixture.call("create_source_revision") as Dictionary
	if source.get("ok") != true:
		return source
	if with_fallback:
		var rebind := OFFLINE_REBIND.new() as RefCounted
		var service_configured := rebind.call(
			"configure",
			fixture.get("save_store"),
			fixture.get("agent_store"),
			fixture.call("provider"),
		) as Dictionary
		if service_configured.get("ok") != true:
			return service_configured
		var prepared := rebind.call(
			"prepare",
			fixture.call("catalog_slot"),
			fixture.call("base_catalog"),
		) as Dictionary
		if prepared.get("ok") != true:
			return prepared
		var applied := rebind.call(
			"apply_bindings",
			fixture.call("bindings_for", "current-provider", "current-model"),
		) as Dictionary
		if applied.get("ok") != true:
			return applied
	var store := fixture.get("save_store") as RefCounted
	var listed := store.call("list_published", fixture.get("slot_id")) as Dictionary
	var manifests := listed.get("manifests", []) as Array
	if manifests.is_empty():
		return {"ok": false, "errorCode": "TEST_DAMAGED_MANIFEST_MISSING"}
	var latest := manifests[0] as Dictionary
	var world_component := (
		(latest.get("components", {}) as Dictionary).get("world", {}) as Dictionary
	)
	var reference := String(world_component.get("snapshot_ref", ""))
	var damaged := FileAccess.open(
		"%s/%s" % [String(fixture.get("save_root")), reference],
		FileAccess.WRITE,
	)
	if damaged == null:
		return {"ok": false, "errorCode": "TEST_DAMAGED_WORLD_WRITE_FAILED"}
	damaged.store_string("{}\n")
	damaged = null
	var slot := fixture.call("catalog_slot") as Dictionary
	return {
		"ok": not slot.has("fixtureError"),
		"errorCode": String((slot.get("fixtureError", {}) as Dictionary).get("errorCode", "")),
		"slot": slot,
		"fixture": fixture,
	}


func _cleanup_case_fixture(case_result: Dictionary) -> void:
	var fixture := case_result.get("fixture") as RefCounted
	if fixture != null:
		fixture.call("cleanup")


func _load_page_slot(slot: Dictionary) -> Dictionary:
	var summary := slot.get("summary", {}) as Dictionary
	var edit := STARTUP_REBIND_COORDINATOR.project_slot_edit(slot)
	return {
		"slotId": String(slot.get("slotId", "")),
		"displayName": String(slot.get("displayName", "测试小镇")),
		"sessionId": String(summary.get("sessionId", "")),
		"saveRevision": int(summary.get("saveRevision", 0)),
		"state": String(slot.get("state", "empty")),
		"recoveryState": String(slot.get("recoveryState", "none")),
		"continueAvailable": bool(slot.get("continueAvailable", false)),
		"diagnosticAvailable": bool(slot.get("diagnosticAvailable", false)),
		"requiresRecoveryConfirmation": bool(slot.get("requiresRecoveryConfirmation", false)),
		"savedAt": String(summary.get("savedAt", "")),
		"residentCount": int(summary.get("residentCount", 0)),
		"day": int(summary.get("day", 0)),
		"worldRevision": int(summary.get("worldRevision", 0)),
		"damageDetails": (slot.get("damageDetails", {}) as Dictionary).duplicate(true),
		"errorCode": String(slot.get("errorCode", "")),
		"modelEditAvailable": bool(edit.get("modelEditAvailable", false)),
		"modelEditSaveRevision": int(edit.get("modelEditSaveRevision", 0)),
		"modelEditDisabledReason": String(edit.get("modelEditDisabledReason", "")),
		"modelEditRecoveryRequired": bool(edit.get("modelEditRecoveryRequired", false)),
	}


func _load_page_view_model(slots: Array, revision: int) -> Dictionary:
	return {
		"scope": "save",
		"status": "ready",
		"revision": revision,
		"data": {
			"mode": "load",
			"providerIndependent": true,
			"slots": slots,
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
	var original_viewport_size := root.size
	for layout_value: Variant in [
		[Vector2i(960, 540), "960×540"],
		[Vector2i(540, 960), "540×960"],
	]:
		var layout := layout_value as Array
		root.size = layout[0] as Vector2i
		for _index in 3:
			await process_frame
		var compact_actions: Array[Button] = [
			screen.find_child("slot-aAction", true, false) as Button,
			screen.find_child("slot-aDeleteAction", true, false) as Button,
			screen.find_child("slot-aModelEditAction", true, false) as Button,
		]
		for button: Button in compact_actions:
			_expect(
				button != null and button.size.x >= 48.0 and button.size.y >= 48.0,
				"%s 的 %s 真实触控区至少为 48×48" % [
					String(layout[1]),
					button.name if button != null else "missing",
				],
			)
		for left_index in compact_actions.size():
			for right_index in range(left_index + 1, compact_actions.size()):
				if compact_actions[left_index] == null or compact_actions[right_index] == null:
					_expect(false, "%s 的关键操作按钮完整" % String(layout[1]))
					continue
				_expect(
					not compact_actions[left_index].get_global_rect().intersects(
						compact_actions[right_index].get_global_rect(),
					),
					"%s 的主操作、删除和改绑按钮互不重叠" % String(layout[1]),
				)
	root.size = original_viewport_size
	for _index in 3:
		await process_frame
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
