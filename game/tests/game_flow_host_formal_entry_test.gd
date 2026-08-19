extends SceneTree


const STARTUP_SCENE := preload("res://ui/startup/StartupScreen.tscn")
const SAVE_STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const SAVE_MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const AGENT_SAVE_STORE := preload(
	"res://agent/lifecycle/AgentSaveStore.gd"
)
const FAKE_MODEL := preload("res://agent/model/FakeModelProvider.gd")
const FORMAL_PROJECT_NAME := "ai-town"
const SLOT_ID := "town-main"
const OLD_SESSION_ID := "formal-host-e2e-old-session"
const WORLD_SLOT := "user://town_session_saves/slots/town-main"
const AGENT_SLOT := "user://agent_saves/town-main"
const PHOTO_SLOT := "user://town_conversation_photos/town-main"
const BACKUP_SLOT := "user://formal_slot_backups/town-main"


class FormalNoNetworkProviderService:
	extends RefCounted

	var providers: Dictionary = {}
	var pending_availability: Array[Dictionary] = []

	func get_health_snapshot() -> Dictionary:
		return {
			"ok": true,
			"status": "ready",
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": true,
			"providers": [{
				"providerId": "test-formal",
				"label": "Test Formal",
				"status": "available",
				"errorCode": "",
				"retryable": false,
			}],
		}

	func list_available_models() -> Array[Dictionary]:
		return [{
			"providerId": "test-formal",
			"modelId": "fixed",
			"id": "fixed",
			"label": "Fixed deterministic model",
			"available": true,
			"errorCode": "",
			"retryable": false,
			"capabilities": [],
		}]

	func validate_resident_bindings(bindings: Array) -> Dictionary:
		if bindings.size() != 15:
			return _failure("SESSION_LLM_BINDINGS_INVALID")
		for value: Variant in bindings:
			if not value is Dictionary:
				return _failure("SESSION_LLM_BINDINGS_INVALID")
			var binding := value as Dictionary
			var llm := binding.get("llmBinding", {}) as Dictionary
			if (
				String(binding.get("residentId", "")).is_empty()
				or String(llm.get("mode", "")) != "model"
				or String(llm.get("providerId", "")) != "test-formal"
				or String(llm.get("modelId", "")) != "fixed"
			):
				return _failure("SESSION_LLM_BINDINGS_INVALID")
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"residentCount": bindings.size(),
			"capabilityMode": "formal",
			"formalReady": true,
		}

	func check_entry_availability(
		bindings: Array,
		on_complete: Callable = Callable(),
	) -> Dictionary:
		var validation := validate_resident_bindings(bindings)
		if not bool(validation.get("ok", false)):
			return validation
		pending_availability.append({
			"bindings": bindings.duplicate(true),
			"onComplete": on_complete,
		})
		return {
			"ok": true,
			"accepted": true,
			"pending": true,
			"status": "checking",
			"errorCode": "",
			"retryable": false,
		}

	func complete_next_availability() -> bool:
		if pending_availability.is_empty():
			return false
		var pending := pending_availability.pop_front() as Dictionary
		var callback := pending.get("onComplete", Callable()) as Callable
		if not callback.is_valid():
			return false
		callback.call({
			"ok": true,
			"accepted": true,
			"pending": false,
			"status": "available",
			"capabilityMode": "formal",
			"formalReady": true,
			"source": "runtime",
			"errorCode": "",
			"retryable": false,
		})
		return true

	func create_provider_for_resident(binding: Dictionary) -> Dictionary:
		var resident_id := String(binding.get("residentId", ""))
		if resident_id.is_empty():
			return _failure("SESSION_RESIDENT_ID_INVALID")
		if not providers.has(resident_id):
			providers[resident_id] = FAKE_MODEL.new()
		return {
			"ok": true,
			"provider": providers[resident_id],
			"providerId": "test-formal",
			"modelId": "fixed",
			"errorCode": "",
			"retryable": false,
		}

	func get_latest_diagnostic(_resident_id: String) -> Dictionary:
		return {}

	func _failure(error_code: String) -> Dictionary:
		return {
			"ok": false,
			"errorCode": error_code,
			"retryable": false,
		}


class ProviderSettingsHarness:
	extends RefCounted

	func get_view_model(_scope := "provider_settings") -> Dictionary:
		return {
			"scope": "provider_settings",
			"status": "ready",
			"revision": 1,
			"data": {
				"source": "runtime",
				"capabilityMode": "formal",
				"formalReady": true,
			},
			"actions": {},
			"operation": {
				"requestId": "",
				"intent": "",
				"status": "idle",
				"submittedAtMsec": 0,
				"completedAtMsec": 0,
			},
			"error": null,
		}

	func runtime_configuration() -> Dictionary:
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"providerId": "test-formal",
			"modelId": "fixed",
			"providerConfigs": {},
		}


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("AI_TOWN_INTERNAL_PLAYTEST", "")
	var project_name := String(
		ProjectSettings.get_setting("application/config/name", "")
	).strip_edges()
	_expect(
		project_name != FORMAL_PROJECT_NAME,
		"formal Host E2E requires a renamed project copy with isolated user storage",
	)
	if project_name == FORMAL_PROJECT_NAME:
		_finish()
		return
	_cleanup_formal_slot()
	var published := _publish_old_formal_pair()
	_expect_ok(published, "old formal World and Agent pair is published")
	if not bool(published.get("ok", false)):
		_finish()
		return

	var host := root.get_node_or_null("GameFlowHost")
	_expect(host != null, "formal GameFlowHost autoload exists")
	if host == null:
		_finish()
		return
	var provider := FormalNoNetworkProviderService.new()
	host.set("_startup_provider_service", provider)
	host.set("_startup_provider_settings_service", ProviderSettingsHarness.new())

	var startup := STARTUP_SCENE.instantiate()
	root.add_child(startup)
	current_scene = startup
	host.call("_bind_current_scene")
	await _wait_frames(4)
	_emit_startup_new_game(startup)
	await _wait_frames(3)
	var overwrite := startup.get_node_or_null("SaveHandlingRoute") as Control
	_expect(
		overwrite != null,
		"existing formal slot opens the real overwrite page; scene=%s last=%s catalog=%s"
		% [
			current_scene,
			host.get("_last_result"),
			host.call("_startup_catalog_snapshot"),
		],
	)
	if overwrite == null:
		_finish()
		return
	_expect(
		bool(overwrite.call("debug_request_action", "confirmOverwrite")),
		"real overwrite confirmation records the exact published save",
	)
	await _wait_frames(5)
	var intro := current_scene
	_expect(
		intro != null and intro.name == "WorldIntroScreen",
		"confirmed formal New Game enters WorldIntro",
	)
	if intro == null or intro.name != "WorldIntroScreen":
		_finish()
		return
	var generation_before_repeated_back := int(host.get("_flow_generation"))
	for _index in 3:
		# Esc delegates to the same back request. Invoke that request directly so
		# this test can also repeat it after the first call detaches the old scene.
		intro.call("_request_back")
	await _wait_frames(5)
	var returned_startup := current_scene
	_expect(
		returned_startup != null and returned_startup.name == "StartupScreen",
		"WorldIntro repeated Esc returns to Startup exactly once",
	)
	_expect_equal(
		int(host.get("_flow_generation")),
		generation_before_repeated_back + 1,
		"WorldIntro repeated Esc advances one navigation generation",
	)
	if returned_startup == null or returned_startup.name != "StartupScreen":
		_finish()
		return
	_emit_startup_new_game(returned_startup)
	await _wait_frames(3)
	overwrite = returned_startup.get_node_or_null("SaveHandlingRoute") as Control
	_expect(overwrite != null, "new game remains usable after repeated Esc")
	if overwrite == null:
		_finish()
		return
	_expect(
		bool(overwrite.call("debug_request_action", "confirmOverwrite")),
		"overwrite confirmation remains usable after repeated Esc",
	)
	await _wait_frames(5)
	intro = current_scene
	_expect(
		intro != null and intro.name == "WorldIntroScreen",
		"new game can re-enter WorldIntro after repeated Esc",
	)
	if intro == null or intro.name != "WorldIntroScreen":
		_finish()
		return
	intro.call("_request_action", "skip")
	await create_timer(0.35).timeout
	await _wait_frames(5)
	var selection := current_scene
	_expect(
		selection != null and selection.name == "ResidentSelectionScreen",
		"WorldIntro enters formal ResidentSelection",
	)
	if selection == null or selection.name != "ResidentSelectionScreen":
		_finish()
		return
	var selection_revision := int(
		(selection.get("_view_model") as Dictionary).get("revision", 0)
	)
	host.call("_on_custom_resident_requested", selection_revision)
	await _wait_frames(3)
	var creator := selection.get_node_or_null(
		"CustomResidentCreatorRoute",
	) as Control
	_expect(creator != null, "formal flow opens the custom resident creator")
	if creator == null:
		_finish()
		return
	var creator_adapter := host.get("_startup_ui_adapter") as Node
	var creator_vm := creator_adapter.call(
		"get_view_model",
		"custom_resident_creator",
	) as Dictionary
	var creator_data := creator_vm.get("data", {}) as Dictionary
	_expect_ok(
		creator_adapter.call(
			"dispatch",
			"custom_resident_creator.update_fields",
			{
				"revision": int(creator_vm.get("revision", 0)),
				"draftId": String(creator_data.get("draftId", "")),
				"fields": {
					"name": "入镇实测居民",
					"gender": "女",
					"age": 29,
					"desire": "验证绑定后能够进入小镇",
					"personality": "耐心、友善，做事前会确认细节",
					"speech": "会清楚说明自己的想法",
				},
			},
		) as Dictionary,
		"formal flow accepts the custom resident profile",
	)
	await _wait_frames(2)
	creator_vm = creator_adapter.call(
		"get_view_model",
		"custom_resident_creator",
	) as Dictionary
	creator_data = creator_vm.get("data", {}) as Dictionary
	for tween in get_processed_tweens():
		tween.kill()
	creator.call("_request_action", "create", {
		"candidatePoolRevision": int(
			creator_data.get("candidatePoolRevision", -1),
		),
	})
	await _wait_frames(5)
	_expect(
		selection.get_node_or_null("CustomResidentCreatorRoute") == null,
		"custom resident creation returns to formal selection",
	)
	var selection_data := (
		(selection.get("_view_model") as Dictionary).get("data", {}) as Dictionary
	)
	var custom_resident_id := ""
	var custom_index := -1
	var residents := selection_data.get("residents", []) as Array
	for index in residents.size():
		var resident := residents[index] as Dictionary
		if String(resident.get("source", "")) == "custom":
			custom_resident_id = String(resident.get("resident_id", ""))
			custom_index = index
			break
	_expect(
		not custom_resident_id.is_empty() and custom_index >= 0,
		"formal selection contains the created custom resident",
	)
	if custom_resident_id.is_empty() or custom_index < 0:
		_finish()
		return
	selection.call("_apply_recommended_selection", false)
	await _wait_frames(3)
	selection_data = (
		(selection.get("_view_model") as Dictionary).get("data", {}) as Dictionary
	)
	var recommended := (
		selection_data.get("selected_resident_ids", []) as Array
	).duplicate()
	var replaced_id := String(recommended[0])
	var replaced_index := -1
	residents = selection_data.get("residents", []) as Array
	for index in residents.size():
		var resident := residents[index] as Dictionary
		if String(resident.get("resident_id", "")) == replaced_id:
			replaced_index = index
			break
	_expect(replaced_index >= 0, "formal selection finds the preset being replaced")
	if replaced_index < 0:
		_finish()
		return
	selection.call("_toggle_resident", replaced_index)
	await _wait_frames(2)
	selection.call("_toggle_resident", custom_index)
	await _wait_frames(3)
	selection_data = (
		(selection.get("_view_model") as Dictionary).get("data", {}) as Dictionary
	)
	_expect_equal(
		(selection_data.get("selected_resident_ids", []) as Array).size(),
		15,
		"formal roster still contains exactly fifteen residents",
	)
	_expect(
		(selection_data.get("selected_resident_ids", []) as Array).has(
			custom_resident_id,
		),
		"formal roster replaces one preset with the custom resident",
	)
	var confirm := selection.find_child(
		"ConfirmRosterButton",
		true,
		false,
	) as Button
	_expect(
		confirm != null and not confirm.disabled,
		"formal recommended roster enables confirmation",
	)
	if confirm == null or confirm.disabled:
		_finish()
		return
	confirm.pressed.emit()
	await _wait_frames(3)
	var assignment := selection.get_node_or_null(
		"ResidentModelAssignmentRoute",
	) as Control
	_expect(assignment != null, "formal route mounts ResidentModelAssignment")
	if assignment == null:
		_finish()
		return
	var adapter := host.get("_startup_ui_adapter") as Node
	var assignment_vm := adapter.call(
		"get_view_model",
		"resident_model_assignment",
	) as Dictionary
	var assignment_data := assignment_vm.get("data", {}) as Dictionary
	var assignment_resident_ids: Array[String] = []
	for resident_value: Variant in assignment_data.get("residents", []) as Array:
		assignment_resident_ids.append(String(
			(resident_value as Dictionary).get("residentId", "")
		))
	_expect_equal(
		assignment_resident_ids.size(),
		15,
		"model assignment receives only the final fifteen residents",
	)
	_expect(
		assignment_resident_ids.has(custom_resident_id)
		and not assignment_resident_ids.has(replaced_id),
		"model assignment receives the custom resident instead of the replaced preset",
	)
	var target := (
		assignment_data.get("targetBinding", {}) as Dictionary
	).duplicate(true)
	for resident_value: Variant in assignment_data.get("residents", []) as Array:
		var resident_id := String(
			(resident_value as Dictionary).get("residentId", "")
		)
		_expect_ok(
			assignment.call(
				"_request_action",
				"assignOne",
				{
					"residentId": resident_id,
					"llmBinding": target.duplicate(true),
				},
				"resident:%s" % resident_id,
			) as Dictionary,
			"formal assignment accepts %s" % resident_id,
		)
	assignment_vm = adapter.call(
		"get_view_model",
		"resident_model_assignment",
	) as Dictionary
	_expect_equal(
		int(
			(assignment_vm.get("data", {}) as Dictionary).get(
				"completedCount",
				0,
			),
		),
		15,
		"formal assignment completes all fifteen residents",
	)

	assignment.call("_open_completion_modal")
	var modal_start := assignment.find_child(
		"ModalStartButton",
		true,
		false,
	) as Button
	_expect(
		modal_start != null and modal_start.visible and not modal_start.disabled,
		"completion modal exposes Start Game",
	)
	if modal_start == null or modal_start.disabled:
		_finish()
		return
	modal_start.pressed.emit()
	_expect(
		await _wait_for_pending_availability(provider),
		"formal Host reaches the deterministic model boundary",
	)
	_expect(
		provider.complete_next_availability(),
		"first availability check completes through the real Bootstrap",
	)
	var failing_runtime := host.get("_pending_runtime") as Node
	_expect(
		failing_runtime != null and failing_runtime.has_method("get_world_runtime"),
		"failure branch still uses the real TownRuntime",
	)
	if failing_runtime != null:
		# The formal runtime requires its configured Gateway. Removing that one
		# dependency after Bootstrap makes the real _ready() path fail
		# deterministically, before GameFlowHost publishes the scene.
		failing_runtime.set("_agent_gateway", null)
	await _wait_frames(5)
	_expect_equal(
		current_scene,
		selection,
		"real Town startup failure keeps ResidentModelAssignment owner current",
	)
	var failed_result := host.get("_last_result") as Dictionary
	_expect_equal(
		failed_result.get("errorCode"),
		"TOWN_RUNTIME_START_FAILED",
		"real Town startup failure reaches GameFlowHost: %s"
		% JSON.stringify(failed_result),
	)
	_expect_equal(
		failed_result.get("overwriteCompensated"),
		true,
		"failed Town startup restores the confirmed old save",
	)
	_expect(
		DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(WORLD_SLOT))
		and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(AGENT_SLOT)),
		"failed Town startup restores both old formal participants",
	)
	_expect(
		(host.get("_pending_formal_overwrite_archive") as Dictionary).is_empty(),
		"successful compensation clears the in-memory recovery marker",
	)

	assignment.call("_open_completion_modal")
	modal_start = assignment.find_child(
		"ModalStartButton",
		true,
		false,
	) as Button
	_expect(
		modal_start != null and modal_start.visible and not modal_start.disabled,
		"compensated failure can retry from the same formal page",
	)
	if modal_start == null or modal_start.disabled:
		_finish()
		return
	modal_start.pressed.emit()
	_expect(
		await _wait_for_pending_availability(provider),
		"retry reaches the same deterministic model boundary",
	)
	_expect(
		provider.complete_next_availability(),
		"retry availability completes through the real Bootstrap",
	)
	_expect(
		await _wait_for_town(host),
		"retry enters the real TownRuntime",
	)
	_expect(
		await _wait_for_initial_baseline(host),
		"formal Town binding publishes the initial paired baseline; debug=%s"
		% JSON.stringify(_formal_baseline_debug(host)),
	)
	var flow := host.call("get_flow_snapshot") as Dictionary
	_expect_equal(flow.get("route"), "town", "formal Host publishes the Town route")
	_expect_equal(flow.get("townStarted"), true, "formal World is running")
	_expect_equal(
		flow.get("internalPlaytest"),
		false,
		"formal route never enables internal playtest",
	)
	var formal_runtime := host.get("_town_runtime") as Node
	var avatar_canvas := (
		formal_runtime.get_node_or_null("AvatarUiCanvasLayer") as CanvasLayer
		if formal_runtime != null
		else null
	)
	_expect(
		avatar_canvas != null,
		"real formal Town mounts the independent avatar CanvasLayer",
	)
	if avatar_canvas != null:
		_expect_equal(
			avatar_canvas.layer,
			110,
			"avatar CanvasLayer stays above replaceable town pages and pause UI",
		)
		_expect(avatar_canvas.visible, "formal avatar CanvasLayer remains visible")
	var production_avatar_hud := (
		avatar_canvas.get_node_or_null("AvatarModeHud") as Control
		if avatar_canvas != null
		else null
	)
	_expect(
		production_avatar_hud != null,
		"real formal Town mounts AvatarModeHud under the independent layer",
	)
	if production_avatar_hud != null:
		_expect_equal(
			production_avatar_hud.process_mode,
			Node.PROCESS_MODE_ALWAYS,
			"formal AvatarModeHud keeps processing across pause and page changes",
		)
	var formal_audit := host.call("get_formal_runtime_audit_snapshot") as Dictionary
	var avatar_audit := formal_audit.get("avatarCanvas", {}) as Dictionary
	_expect(
		bool(avatar_audit.get("mounted", false))
			and bool(avatar_audit.get("visible", false))
			and int(avatar_audit.get("layer", -1)) == 110,
		"formal runtime audit records the independent avatar layer",
	)
	var gateway := host.get("_gateway") as Node
	_expect(
		gateway != null,
		"successful formal Town retains the real Agent Gateway",
	)
	if gateway != null:
		var connected_resident_ids := (
			gateway.call("get_connected_resident_ids") as Array
		)
		_expect_equal(
			connected_resident_ids.size(),
			15,
			"all fifteen Agent residents connect",
		)
		_expect(
			connected_resident_ids.has(custom_resident_id)
			and not connected_resident_ids.has(replaced_id),
			"the custom resident enters Town and the replaced preset stays out",
		)
	var baseline_listing := SAVE_STORE.new().call(
		"list_published",
		SLOT_ID,
	) as Dictionary
	_expect_ok(
		baseline_listing,
		"successful formal entry can discover its initial paired baseline",
	)
	var baseline_manifests := (
		baseline_listing.get("manifests", []) as Array
	)
	_expect_equal(
		baseline_manifests.size(),
		1,
		"successful formal entry publishes exactly one active baseline",
	)
	if baseline_manifests.size() == 1:
		var baseline_manifest := baseline_manifests[0] as Dictionary
		_expect_equal(
			baseline_manifest.get("save_revision"),
			1,
			"initial formal baseline is revision 1",
		)
		_expect(
			String(baseline_manifest.get("session_id", "")) != OLD_SESSION_ID,
			"initial formal baseline belongs to the new session",
		)
	var town_adapter := (
		(host.get("_town_runtime") as Node).call("get_ui_adapter") as Node
	)
	var avatar_entry := town_adapter.call(
		"dispatch",
		"town_hud.select_tool",
		{"toolId": "avatar"},
	) as Dictionary
	_expect_ok(
		avatar_entry,
		"real formal Town enters avatar mode through the selected-model route",
	)
	# The descent animation is time-based rather than frame-count based. A
	# headless runner can advance 120 process frames in far less than 1.1s,
	# leaving the real runtime in avatar_descent even though it is healthy.
	await _wait_for_avatar_active(formal_runtime)
	_expect_equal(
		formal_runtime.call("get_avatar_mode"),
		"avatar_active",
		"real formal Town completes avatar descent",
	)
	_expect(
		production_avatar_hud != null and production_avatar_hud.visible,
		"real formal avatar mode keeps AvatarModeHud visible",
	)
	var formal_town_ui_host := host.get("_town_ui_host") as Node
	var route_open := formal_town_ui_host.call(
		"open_page",
		&"town_log",
		{},
	) as Dictionary
	_expect_ok(route_open, "real formal Town can open a primary page over avatar mode")
	await _wait_frames(2)
	_expect(
		production_avatar_hud != null and production_avatar_hud.visible,
		"opening a real town page does not hide AvatarModeHud",
	)
	host.call("_open_pause_menu")
	await _wait_frames(2)
	_expect(
		production_avatar_hud != null and production_avatar_hud.visible,
		"opening the real pause menu does not hide AvatarModeHud",
	)
	host.call("_close_pause_menu")
	formal_town_ui_host.call("close_page")
	await _wait_frames(2)
	var manual_save := town_adapter.call("dispatch", "save.create", {
		"reason": "release_manual_save_regression",
	}) as Dictionary
	_expect_ok(
		manual_save,
		"formal Town can create a second save through the same action used by the pause menu",
	)
	_expect(
		production_avatar_hud != null and production_avatar_hud.visible,
		"saving the active formal Town does not hide AvatarModeHud",
	)
	var manual_listing := SAVE_STORE.new().call(
		"list_published",
		SLOT_ID,
	) as Dictionary
	var manual_manifests := manual_listing.get("manifests", []) as Array
	_expect_equal(
		manual_manifests.size(),
		2,
		"manual save publishes revision 2 after the initial baseline",
	)
	if manual_manifests.size() == 2:
		var revisions: Array[int] = []
		for manifest_value: Variant in manual_manifests:
			revisions.append(int(
				(manifest_value as Dictionary).get("save_revision", 0),
			))
		revisions.sort()
		_expect_equal(
			revisions,
			[1, 2],
			"manual save advances the published set to revision 2",
		)
	_expect(
		not _backup_contains_old_pair(),
		"successful baseline retires the old automatic recovery archive",
	)
	_expect(
		(host.get("_pending_formal_overwrite_archive") as Dictionary).is_empty(),
		"successful Town publication clears the finalized compensation marker",
	)

	if gateway != null:
		_expect_ok(
			gateway.call("close_session") as Dictionary,
			"test closes the published Agent session before isolated cleanup",
		)
	var final_scene := current_scene
	current_scene = null
	if final_scene != null and is_instance_valid(final_scene):
		final_scene.free()
	await _wait_frames(3)
	if is_instance_valid(host):
		host.free()
	await _wait_frames(1)
	_cleanup_formal_slot()
	call_deferred("_finish")


func _emit_startup_new_game(startup: Node) -> void:
	var startup_session := startup.get("_session_view_model") as Dictionary
	var startup_data := startup_session.get("data", {}) as Dictionary
	startup.emit_signal("intent_requested", &"session.new_game", {
		"scope": "session",
		"actionKey": "newGame",
		"revision": int(startup_session.get("revision", 0)),
		"routeOrigin": "startup",
		"source": String(startup_data.get("source", "")),
		"capabilityMode": String(startup_data.get("capabilityMode", "")),
		"validationMode": String(startup_data.get("validationMode", "")),
		"formalReady": bool(startup_data.get("formalReady", false)),
		"internalPlaytest": bool(startup_data.get("internalPlaytest", false)),
		"internalLivePlaytest": bool(
			startup_data.get("internalLivePlaytest", false),
		),
		"slotId": SLOT_ID,
	})


func _publish_old_formal_pair() -> Dictionary:
	var store: RefCounted = SAVE_STORE.new()
	var reserved := store.call(
		"reserve_revision",
		SLOT_ID,
		OLD_SESSION_ID,
	) as Dictionary
	if not bool(reserved.get("ok", false)):
		return reserved
	var context := reserved.get("context", {}) as Dictionary
	var candidate := store.call(
		"write_world_candidate",
		context,
		{
			"schema": "town-world-save",
			"schemaVersion": 1,
			"worldDataVersion": 1,
			"worldRevision": 12,
			"state": {
				"environment": {
					"day": 3,
				},
			},
		},
		{
			"sessionId": OLD_SESSION_ID,
			"slotId": SLOT_ID,
			"residentIdentities": [{
				"residentId": "resident-old",
				"residentName": "旧居民",
			}],
			"residentBindings": [{
				"residentId": "resident-old",
				"llmBinding": {
					"mode": "model",
					"providerId": "test-formal",
					"modelId": "fixed",
				},
			}],
		},
	) as Dictionary
	if not bool(candidate.get("ok", false)):
		return candidate
	var revision := int(context.get("save_revision", 0))
	var agent_store: RefCounted = AGENT_SAVE_STORE.new()
	var agent_created := agent_store.call(
		"create_new_game",
		{
			"slot_id": SLOT_ID,
			"session_id": OLD_SESSION_ID,
			"save_revision": revision,
		},
		{
			"resident-old": {
				"resident_name": "旧居民",
				"payload": "{}".to_utf8_buffer(),
			},
		},
	) as Dictionary
	if not bool(agent_created.get("ok", false)):
		return agent_created
	var manifest := SAVE_MANIFEST.build(
		context,
		"2026-07-27T12:00:00+08:00",
		String(candidate.get("sessionConfigRef", "")),
		String(candidate.get("sessionConfigSha256", "")),
		["resident-old"],
		{
			"snapshotRef": String(candidate.get("snapshotRef", "")),
			"worldRevision": 12,
			"schema": "town-world-save",
			"schemaVersion": 1,
			"worldDataVersion": 1,
		},
		String(candidate.get("snapshotSha256", "")),
	)
	return store.call("publish_manifest", manifest) as Dictionary


func _backup_contains_old_pair() -> bool:
	var directory := DirAccess.open(BACKUP_SLOT)
	if directory == null:
		return false
	for name: String in directory.get_directories():
		var root_path := "%s/%s" % [BACKUP_SLOT, name]
		if (
			DirAccess.dir_exists_absolute(
				ProjectSettings.globalize_path("%s/world_slot" % root_path),
			)
			and DirAccess.dir_exists_absolute(
				ProjectSettings.globalize_path("%s/agent_slot" % root_path),
			)
			and FileAccess.file_exists("%s/archive.receipt.json" % root_path)
		):
			return true
	return false


func _wait_for_pending_availability(
	provider: FormalNoNetworkProviderService,
) -> bool:
	for _index in 60:
		if not provider.pending_availability.is_empty():
			return true
		await process_frame
	return false


func _wait_for_town(host: Node) -> bool:
	for _index in 180:
		if (
			String(
				(host.call("get_flow_snapshot") as Dictionary).get(
					"route",
					"",
				),
			) == "town"
		):
			return true
		await process_frame
	return false


func _wait_for_avatar_active(runtime: Node, timeout_msec: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + maxi(timeout_msec, 1)
	while is_instance_valid(runtime):
		if String(runtime.call("get_avatar_mode")) == "avatar_active":
			return true
		if Time.get_ticks_msec() >= deadline:
			return false
		await process_frame
	return false


func _wait_for_initial_baseline(host: Node) -> bool:
	for _index in 180:
		var service: Variant = host.get("_session_ui_service")
		if service is Object and is_instance_valid(service):
			var snapshot := service.call("get_save_snapshot") as Dictionary
			if (
				bool(snapshot.get("canContinue", false))
				and (
					host.get("_pending_formal_overwrite_archive") as Dictionary
				).is_empty()
			):
				return true
		await process_frame
	return false


func _formal_baseline_debug(host: Node) -> Dictionary:
	var service: Variant = host.get("_session_ui_service")
	return {
		"lastResult": (host.get("_last_result") as Dictionary).duplicate(true),
		"saveSnapshot": (
			(service as Object).call("get_save_snapshot") as Dictionary
			if service is Object and is_instance_valid(service)
			else {}
		),
	}


func _wait_frames(count: int) -> void:
	for _index in count:
		await process_frame


func _cleanup_formal_slot() -> void:
	for path: String in [WORLD_SLOT, AGENT_SLOT, PHOTO_SLOT, BACKUP_SLOT]:
		_remove_tree(path)


func _remove_tree(path: String) -> void:
	var allowed := (
		path == WORLD_SLOT
		or path.begins_with("%s/" % WORLD_SLOT)
		or path == AGENT_SLOT
		or path.begins_with("%s/" % AGENT_SLOT)
		or path == PHOTO_SLOT
		or path.begins_with("%s/" % PHOTO_SLOT)
		or path == BACKUP_SLOT
		or path.begins_with("%s/" % BACKUP_SLOT)
	)
	if not allowed:
		_failures.append("refused cleanup outside the isolated formal slot")
		return
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		_failures.append("cannot open cleanup path: %s" % path)
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("%s/%s" % [path, file_name]),
		)
	for directory_name: String in directory.get_directories():
		_remove_tree("%s/%s" % [path, directory_name])
	DirAccess.remove_absolute(absolute)


func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(
		bool(result.get("ok", false)),
		"%s (error=%s result=%s)" % [
			message,
			result.get("errorCode", ""),
			JSON.stringify(result),
		],
	)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(
		actual == expected,
		"%s (actual=%s expected=%s)" % [message, actual, expected],
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _failure(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
	}


func _finish() -> void:
	if _failures.is_empty():
		print("GAME_FLOW_HOST_FORMAL_ENTRY_PASS")
		quit(0)
		return
	for failure: String in _failures:
		printerr("GAME_FLOW_HOST_FORMAL_ENTRY_FAIL: %s" % failure)
	quit(1)
