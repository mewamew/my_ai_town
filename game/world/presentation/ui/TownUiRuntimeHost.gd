class_name TownUiRuntimeHost
extends Control


signal route_changed(route: StringName)
signal pause_requested

const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const HUD_SCENE := preload("res://ui/town/hud/runtime/TownHudOverlay.tscn")
const FEEDBACK_SCENE := preload("res://ui/system_feedback/SystemFeedbackLayer.tscn")
const RESIDENT_ACTION_MENU_SCENE := preload(
	"res://ui/resident_action_menu/ResidentActionWorldMenu.tscn"
)
const INDOOR_RETURN_TEXTURE := preload(
	"res://assets/ui/indoor_overlay/runtime_skin_v4/composite/"
	+ "indoor_return_button_park_v1.png"
)
const HUD_REFERENCE_SIZE := Vector2(1672.0, 941.0)
const INDOOR_BACK_REFERENCE_POSITION := Vector2(56.0, 728.0)
const INDOOR_BACK_REFERENCE_SIZE := Vector2(144.0, 140.0)
const RESIDENT_PROFILE_EDITOR_SERVICE := preload(
	"res://ui/resident_overview/ResidentProfileEditorService.gd"
)
const UI_NODE_RETIREMENT := preload("res://ui/common/AiTownUiNodeRetirement.gd")
const FORMAL_DIALOG := preload(
	"res://ui/common/formal_dialog/FormalConfirmationDialog.gd"
)

const ROUTE_SCENE_PATHS := {
	&"bulletin_board": "res://ui/bulletin_board/BulletinBoardPanel.tscn",
	&"resident_action_menu": "res://ui/resident_action_menu/ResidentActionWorldMenu.tscn",
	&"resident_detail": "res://ui/resident_detail/ResidentDetailScreen.tscn",
	&"inner_observation": "res://ui/inner_observation/InnerObservationOverlay.tscn",
	&"place_focus": "res://ui/place_focus/PlaceFocusPanel.tscn",
	&"provider_settings": "res://ui/provider_settings/ProviderSettingsScreen.tscn",
	&"resident_model_assignment": "res://ui/resident_model_assignment/ResidentModelAssignmentScreen.tscn",
	&"chat": "res://ui/conversation_unified/UnifiedConversationScreen.tscn",
	&"conversation_spectator": "res://ui/conversation_unified/UnifiedConversationScreen.tscn",
	&"weather_control": "res://ui/weather_control/WeatherControlPanel.tscn",
	&"town_log": "res://ui/town_log/TownLogPanel.tscn",
	&"indoor": "res://ui/indoor_overlay/IndoorOverlay.tscn",
	&"wardrobe": "res://ui/wardrobe/WardrobePage.tscn",
	&"resident_management": "res://ui/resident_overview/ResidentOverviewScreen.tscn",
	&"resident_profile_editor": "res://ui/custom_resident_creator/CustomResidentCreatorScreen.tscn",
}
const ROUTE_SCOPES := {
	&"bulletin_board": "announcements",
	&"resident_action_menu": "resident_action_menu",
	&"resident_detail": "resident_detail",
	&"inner_observation": "inner_observation",
	&"place_focus": "place_focus",
	&"provider_settings": "provider_settings",
	&"resident_model_assignment": "resident_model_assignment",
	&"chat": "conversation",
	&"conversation_spectator": "conversation",
	&"weather_control": "weather_control",
	&"town_log": "town_log",
	&"indoor": "indoor",
	&"wardrobe": "wardrobe",
	&"resident_management": "resident_overview",
	&"resident_profile_editor": "custom_resident_creator",
}

var _adapter: Node
var _hud: Control
var _feedback: Control
var _indoor_back_layer: CanvasLayer
var _indoor_back_button: TextureButton
var _observer_mode_active := true
var _observer_indoor_active := false
var _active_page: Control
var _active_route := &"town"
var _heard_audio_operations: Dictionary = {}
var _focus_return_path := NodePath()
var _route_generation := 0
var _route_close_in_progress := false
var _navigation_feedback_revision := 0
var _conversation_route_revision := -1
var _indoor_route_revision := -1
var _indoor_close_scheduled_generation := -1
var _indoor_open_scheduled_generation := -1
var _observer_indoor_route_required := false
var _indoor_return_outdoor_pending := false
var _resident_management_return_state: Dictionary = {}
var _resident_management_return_pending := false
var _resident_profile_editor_service: RefCounted
var _resident_profile_editor_pause_active := false
var _resident_profile_wardrobe_return_pending := false
var _resident_view_return_route := &"" as StringName
var _resident_view_return_payload: Dictionary = {}
var _resident_view_active := false
var _town_log_origin_route := &"town"
var _town_log_origin_payload: Dictionary = {}
var _resident_death_confirmation: FormalConfirmationDialog
var _pending_resident_death_payload: Dictionary = {}
var _resident_assignment_returns_to_provider_settings := false
var _resident_assignment_provider_payload: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_fit_root_to_viewport()
	get_viewport().size_changed.connect(_fit_root_to_viewport)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mount_persistent_layers()
	_apply_adapter_to_persistent_layers()


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_APPLICATION_FOCUS_OUT
		and _resident_view_active
	):
		prepare_for_world_save("application_background")


func _fit_root_to_viewport() -> void:
	# TownRuntime is a Node2D, so Control anchors have no Control parent to
	# resolve against. Keep this top-level UI host pinned to the logical
	# viewport explicitly; its children may then use normal full-rect anchors.
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_layout_indoor_back_button()


func _exit_tree() -> void:
	_pending_resident_death_payload.clear()
	_set_resident_profile_editor_paused(false)
	_unbind_resident_profile_editor_service()
	_finish_resident_view()
	_disconnect_adapter()


func bind_town_ui_adapter(adapter: Node) -> Dictionary:
	var resume_result := _set_resident_profile_editor_paused(false)
	if not bool(resume_result.get("ok", false)):
		return resume_result
	_finish_resident_view()
	_disconnect_adapter()
	_heard_audio_operations.clear()
	_adapter = adapter if is_instance_valid(adapter) else null
	if _adapter == null:
		return _failure("TOWN_UI_ADAPTER_UNAVAILABLE")
	if (
		not _adapter.has_method("get_view_model")
		or not _adapter.has_method("dispatch")
		or not _adapter.has_signal("view_model_changed")
		or not _adapter.has_signal("operation_completed")
	):
		_adapter = null
		return _failure("TOWN_UI_ADAPTER_CONTRACT_MISSING")
	var callback := Callable(self, "_on_view_model_changed")
	if not _adapter.is_connected("view_model_changed", callback):
		_adapter.connect("view_model_changed", callback)
	var operation_callback := Callable(self, "_on_operation_completed")
	if not _adapter.is_connected("operation_completed", operation_callback):
		_adapter.connect("operation_completed", operation_callback)
	if is_node_ready():
		_apply_adapter_to_persistent_layers()
		_apply_adapter(_active_page)
	return {"ok": true, "errorCode": "", "retryable": false}


func open_page(route: StringName, payload: Dictionary = {}) -> Dictionary:
	if not ROUTE_SCENE_PATHS.has(route):
		return _failure("TOWN_UI_ROUTE_UNKNOWN")
	if not is_instance_valid(_adapter):
		return _failure("TOWN_UI_ADAPTER_UNAVAILABLE")
	if (
		route == &"resident_detail"
		and String(payload.get("residentId", "")).strip_edges().is_empty()
	):
		return _failure("RESIDENT_IDENTITY_REQUIRED")
	var started_resident_view_for_route := false
	if route == &"resident_action_menu":
		var reopening_resident_action := (
			_active_route == &"resident_action_menu"
			and is_instance_valid(_active_page)
		)
		if (
			not reopening_resident_action
			and (
				_active_route != &"town"
				or is_instance_valid(_active_page)
			)
		):
			return _failure("RESIDENT_DIRECT_SELECTION_REQUIRED")
		if not reopening_resident_action:
			var pause_result := _begin_resident_view()
			if not bool(pause_result.get("ok", false)):
				return pause_result
			started_resident_view_for_route = true
	elif route == &"resident_detail" and not _resident_view_active:
		var pause_result := _begin_resident_view()
		if not bool(pause_result.get("ok", false)):
			return pause_result
		started_resident_view_for_route = true
	elif route == &"inner_observation" and (
		not _resident_view_active
		or _active_route != &"resident_action_menu"
	):
		return _failure("INNER_OBSERVATION_UNIQUE_ENTRY_REQUIRED")
	var leaving_resident_view := (
		_resident_view_active
		and _active_route in [
			&"resident_action_menu",
			&"resident_detail",
			&"inner_observation",
		]
		and route not in [
			&"resident_action_menu",
			&"resident_detail",
			&"inner_observation",
		]
	)
	var resident_profile_wardrobe_transition := (
		_active_route == &"resident_profile_editor"
		and route == &"wardrobe"
		and _resident_profile_wardrobe_return_pending
	)
	var scene := _route_scene(route)
	if scene == null:
		if started_resident_view_for_route:
			_finish_resident_view()
		return _failure("TOWN_UI_ROUTE_RESOURCE_UNAVAILABLE")
	var page := scene.instantiate() as Control
	if page == null:
		if started_resident_view_for_route:
			_finish_resident_view()
		return _failure("TOWN_UI_ROUTE_INSTANTIATION_FAILED")
	if leaving_resident_view:
		var finish_result := _finish_resident_view()
		if not bool(finish_result.get("ok", false)):
			page.free()
			return finish_result
	if (
		_active_route == &"resident_profile_editor"
		and route != &"resident_profile_editor"
		and not resident_profile_wardrobe_transition
	):
		var resume_result := _set_resident_profile_editor_paused(false)
		if not bool(resume_result.get("ok", false)):
			page.free()
			return resume_result
	if not is_instance_valid(_active_page):
		_capture_route_focus()
	else:
		if not close_page(
			false,
			(
				route == &"resident_profile_editor"
				or resident_profile_wardrobe_transition
			),
		):
			page.free()
			return _failure("TOWN_UI_ROUTE_CLOSE_FAILED")
	_route_generation += 1
	page.name = "%sRoute" % String(route).to_pascal_case()
	page.process_mode = Node.PROCESS_MODE_ALWAYS
	if route != &"resident_action_menu":
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_disable_placeholder_bootstrap(page, route)
	page.set_meta("route_payload", payload.duplicate(true))
	if page.has_method("apply_route_payload"):
		page.call("apply_route_payload", payload.duplicate(true))
	var scope := String(ROUTE_SCOPES.get(route, ""))
	if (
		not scope.is_empty()
		and _adapter != null
		and _adapter.has_method("set_page_context")
	):
		var context := payload.duplicate(true)
		context["open"] = true
		_adapter.call("set_page_context", scope, context)
	_active_page = page
	_active_route = route
	_apply_adapter(page)
	if route == &"resident_action_menu":
		if not _adapter.has_method("attach_world_resident_action_menu"):
			_active_page = null
			_active_route = &"town"
			page.free()
			if started_resident_view_for_route:
				_finish_resident_view()
			return _failure("RESIDENT_WORLD_MENU_HOST_UNAVAILABLE")
		var attach_result := _adapter.call(
			"attach_world_resident_action_menu",
			page,
			payload.duplicate(true),
		) as Dictionary
		if not bool(attach_result.get("ok", false)):
			_active_page = null
			_active_route = &"town"
			page.free()
			if started_resident_view_for_route:
				_finish_resident_view()
			return attach_result
	else:
		add_child(page)
	_connect_page(page, route)
	if page.get_parent() == self:
		move_child(page, get_child_count() - 1)
	if is_instance_valid(_feedback):
		move_child(_feedback, get_child_count() - 1)
	route_changed.emit(_active_route)
	call_deferred("_focus_open_page", page, _route_generation)
	_play_audio_cue("ui_panel_open", -2.0)
	return {"ok": true, "errorCode": "", "retryable": false}


func _route_scene(route: StringName) -> PackedScene:
	# The resident action page is reached directly from an in-world resident.
	# Keep an explicit packed-scene dependency so editor and exported builds use
	# the same reliable route instead of discovering it through a late string load.
	if route == &"resident_action_menu":
		return RESIDENT_ACTION_MENU_SCENE
	var scene_path := String(ROUTE_SCENE_PATHS.get(route, ""))
	if scene_path.is_empty():
		return null
	return ResourceLoader.load(scene_path, "PackedScene") as PackedScene


func close_page(
	restore_focus := true,
	preserve_resident_editor_pause := false,
) -> bool:
	if not is_instance_valid(_active_page):
		if _resident_profile_editor_pause_active:
			var resume_result := _set_resident_profile_editor_paused(false)
			if not bool(resume_result.get("ok", false)):
				return false
		_active_page = null
		_active_route = &"town"
		_schedule_observer_indoor_route_ensure()
		return false
	var closing_route := _active_route
	if (
		closing_route == &"resident_profile_editor"
		and not preserve_resident_editor_pause
	):
		var resume_result := _set_resident_profile_editor_paused(false)
		if not bool(resume_result.get("ok", false)):
			return false
	if (
		closing_route == &"wardrobe"
		and _resident_profile_wardrobe_return_pending
		and not preserve_resident_editor_pause
	):
		var resume_result := _set_resident_profile_editor_paused(false)
		if not bool(resume_result.get("ok", false)):
			return false
	if _active_page.has_method("unbind_town_ui_adapter"):
		_active_page.call("unbind_town_ui_adapter")
	if closing_route == &"indoor":
		_indoor_close_scheduled_generation = -1
	if (
		restore_focus
		and closing_route in [
			&"resident_action_menu",
			&"resident_detail",
			&"inner_observation",
		]
	):
		_clear_resident_view_return()
		_finish_resident_view()
	var scope := String(ROUTE_SCOPES.get(closing_route, ""))
	if (
		not scope.is_empty()
		and _adapter != null
		and _adapter.has_method("set_page_context")
	):
		_route_close_in_progress = true
		_adapter.call("set_page_context", scope, {"open": false})
		_route_close_in_progress = false
	if (
		not scope.is_empty()
		and is_instance_valid(_feedback)
		and _feedback.has_method("clear_scope")
	):
		_feedback.call("clear_scope", StringName(scope), true)
	if (
		closing_route == &"resident_model_assignment"
		and restore_focus
	):
		_clear_provider_assignment_return()
	UI_NODE_RETIREMENT.retire(_active_page)
	_active_page = null
	_active_route = &"town"
	if (
		closing_route == &"resident_profile_editor"
		and not preserve_resident_editor_pause
	):
		_unbind_resident_profile_editor_service()
	elif (
		closing_route == &"wardrobe"
		and _resident_profile_wardrobe_return_pending
		and not preserve_resident_editor_pause
	):
		_unbind_resident_profile_editor_service()
	if restore_focus:
		_resident_management_return_pending = false
		_resident_management_return_state.clear()
	_route_generation += 1
	var restore_generation := _route_generation
	route_changed.emit(_active_route)
	if closing_route != &"indoor":
		_schedule_observer_indoor_route_ensure()
	if restore_focus:
		call_deferred(
			"_restore_route_focus",
			_focus_return_path,
			restore_generation,
		)
	return true


func current_route() -> StringName:
	return _active_route


func prepare_for_world_save(_reason := "save") -> Dictionary:
	_clear_resident_view_return()
	var recovered_stale_inner_observation := false
	var exit_result := {
		"ok": true,
		"errorCode": "",
		"retryable": false,
	}
	if _active_route == &"inner_observation":
		exit_result = _dispatch_adapter("inner_observation.exit", {})
		if not bool(exit_result.get("ok", false)):
			recovered_stale_inner_observation = true
			if (
				is_instance_valid(_adapter)
				and _adapter.has_method("set_page_context")
			):
				_adapter.call(
					"set_page_context",
					"inner_observation",
					{"open": false},
				)
	if _resident_view_active:
		var finish_result := _finish_resident_view()
		if not bool(finish_result.get("ok", false)):
			return finish_result
	if (
		_active_route in [
			&"resident_action_menu",
			&"resident_detail",
			&"inner_observation",
			&"resident_profile_editor",
		]
		and is_instance_valid(_active_page)
	):
		if not close_page():
			return _failure("TOWN_UI_ROUTE_CLOSE_FAILED")
	return {
		"ok": true,
		"changed": true,
		"errorCode": "",
		"retryable": false,
		"recoveredStaleInnerObservation": recovered_stale_inner_observation,
	}


func present_feedback(view_model: Dictionary) -> Dictionary:
	if not is_instance_valid(_feedback):
		return _failure("TOWN_UI_FEEDBACK_LAYER_UNAVAILABLE")
	if not _feedback.has_method("apply_view_model"):
		return _failure("TOWN_UI_FEEDBACK_CONTRACT_MISSING")
	var issues := _feedback.call(
		"apply_view_model",
		view_model.duplicate(true),
	) as PackedStringArray
	if not issues.is_empty():
		return {
			"ok": false,
			"errorCode": "TOWN_UI_FEEDBACK_VIEW_MODEL_INVALID",
			"retryable": false,
			"issues": Array(issues),
		}
	return {"ok": true, "errorCode": "", "retryable": false}


func request_back() -> bool:
	if not is_instance_valid(_active_page):
		if _observer_indoor_active:
			return _request_return_outdoor()
		return false
	if _active_route in [&"bulletin_board", &"town_log", &"wardrobe"]:
		if _active_page.has_method("request_back"):
			return bool(_active_page.call("request_back"))
		return false
	if _active_route == &"resident_action_menu":
		_on_resident_action_intent(
			&"resident.action_menu.close",
			{},
			-1,
			"",
		)
		return true
	if _active_route == &"resident_detail":
		if _resident_management_return_pending:
			return _return_to_resident_management()
		if _active_page.has_method("request_close"):
			return bool(_active_page.call("request_close"))
		return false
	if _active_route == &"resident_profile_editor":
		if _active_page.has_method("request_back"):
			return bool(_active_page.call("request_back"))
		return false
	if _active_route == &"inner_observation":
		if _active_page.has_method("request_exit"):
			return bool(_active_page.call("request_exit"))
		return false
	if (
		_active_route in [&"chat", &"conversation_spectator"]
	):
		if _active_page.has_method("request_back"):
			return bool(_active_page.call("request_back"))
		if _active_route == &"conversation_spectator":
			return close_page()
		var result := _dispatch_adapter(
			"conversation.end",
			{"narration": "旅行者结束交谈"},
		)
		return bool(result.get("ok", false))
	if _active_route == &"indoor":
		var indoor_result := _dispatch_adapter("indoor.return_outdoor", {})
		return bool(indoor_result.get("ok", false))
	if _active_route == &"provider_settings":
		if _active_page.has_method("request_back"):
			return bool(_active_page.call("request_back"))
		return false
	if _active_route == &"weather_control":
		if _active_page.has_method("request_back"):
			return bool(_active_page.call("request_back"))
		return false
	return close_page()


func debug_snapshot() -> Dictionary:
	var hud_snapshot: Dictionary = {}
	if is_instance_valid(_hud) and _hud.has_method("audit_snapshot"):
		hud_snapshot = _hud.call("audit_snapshot") as Dictionary
	return {
		"route": String(_active_route),
		"adapterBound": is_instance_valid(_adapter),
		"adapterInstanceId": (
			_adapter.get_instance_id()
			if is_instance_valid(_adapter)
			else 0
		),
		"hudMounted": is_instance_valid(_hud),
		"hudVisible": is_instance_valid(_hud) and _hud.visible,
		"hudVisibleInTree": (
			is_instance_valid(_hud) and _hud.is_visible_in_tree()
		),
		"hudMouseFilter": _hud.mouse_filter if is_instance_valid(_hud) else -1,
		"hudAudit": hud_snapshot,
		"feedbackMounted": is_instance_valid(_feedback),
		"observerIndoorRouteRequired": _observer_indoor_route_required,
		"indoorReturnOutdoorPending": _indoor_return_outdoor_pending,
		"indoorOpenScheduledGeneration": _indoor_open_scheduled_generation,
		"indoorCloseScheduledGeneration": _indoor_close_scheduled_generation,
		"activePage": (
			String(_active_page.name)
			if is_instance_valid(_active_page)
			else ""
		),
	}


func _mount_persistent_layers() -> void:
	if not is_instance_valid(_hud):
		_hud = HUD_SCENE.instantiate() as Control
		_hud.name = "TownHudOverlay"
		add_child(_hud)
		_hud.intent_requested.connect(_on_hud_intent_requested)
	if not is_instance_valid(_indoor_back_button):
		_build_indoor_back_button()
	if not is_instance_valid(_feedback):
		_feedback = FEEDBACK_SCENE.instantiate() as Control
		_feedback.name = "SystemFeedbackLayer"
		add_child(_feedback)


func _apply_adapter_to_persistent_layers() -> void:
	if _adapter == null:
		return
	if is_instance_valid(_feedback):
		_feedback.call("bind_town_ui_adapter", _adapter)
	if is_instance_valid(_hud):
		if _hud.has_method("bind_town_ui_adapter"):
			_hud.call("bind_town_ui_adapter", _adapter)
		var session_vm := _adapter.call("get_view_model", "session") as Dictionary
		var session_data := session_vm.get("data", {}) as Dictionary
		_hud.set("require_formal_ready", bool(session_data.get("formalReady", false)))
		var hud_vm := _adapter.call("get_view_model", "town_hud") as Dictionary
		_hud.call("apply_view_model", hud_vm)
		_sync_indoor_presence_from_town_hud(hud_vm)
		_sync_hud_mode_ownership(
			_adapter.call("get_view_model", "avatar") as Dictionary
		)
	_sync_conversation_route(
		_adapter.call("get_view_model", "conversation") as Dictionary
	)
	_sync_indoor_route(
		_adapter.call("get_view_model", "indoor") as Dictionary
	)


func _apply_adapter(page: Control) -> void:
	if page == null or _adapter == null:
		return
	if page.has_method("bind_town_ui_adapter"):
		page.call("bind_town_ui_adapter", _adapter)
	elif page.has_method("bind_adapter"):
		page.call("bind_adapter", _adapter)


func _capture_route_focus() -> void:
	_focus_return_path = NodePath()
	var focus_owner := get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focus_owner) or not focus_owner is Control:
		return
	_focus_return_path = get_path_to(focus_owner)
	(focus_owner as Control).release_focus()


func _restore_route_focus(path: NodePath, generation: int) -> void:
	if (
		generation != _route_generation
		or _active_route != &"town"
	):
		return
	var target := get_node_or_null(path) as Control if not path.is_empty() else null
	if (
		target == null
		or not target.is_visible_in_tree()
		or target.focus_mode == Control.FOCUS_NONE
		or (target is BaseButton and (target as BaseButton).disabled)
	):
		_focus_avatar_hud_fallback()
		return
	target.grab_focus()


func _focus_open_page(page: Control, generation: int) -> void:
	if (
		generation != _route_generation
		or page != _active_page
		or not is_instance_valid(page)
		or not page.is_inside_tree()
	):
		return
	for method_name: String in ["focus_default_control", "focus_default"]:
		if page.has_method(method_name):
			page.call(method_name)
			return
	for candidate_name: String in ["BackButton", "CloseButton", "ReturnButton"]:
		var candidate := page.find_child(candidate_name, true, false) as BaseButton
		if (
			candidate != null
			and candidate.is_visible_in_tree()
			and not candidate.disabled
			and candidate.focus_mode != Control.FOCUS_NONE
		):
			candidate.grab_focus()
			return


func _focus_avatar_hud_fallback() -> void:
	if (
		is_instance_valid(_hud)
		and _hud.visible
		and _hud.has_method("focus_default_control")
	):
		_hud.call("focus_default_control")
		return
	var parent := get_parent()
	if parent == null:
		return
	var avatar_hud := parent.get_node_or_null("AvatarModeHud") as Control
	if (
		avatar_hud != null
		and avatar_hud.visible
		and avatar_hud.has_method("focus_default_control")
	):
		avatar_hud.call("focus_default_control")


func _connect_page(page: Control, route: StringName) -> void:
	if route == &"conversation_spectator" and page.has_signal("close_requested"):
		page.connect(
			"close_requested",
			Callable(self, "_on_page_close_requested").bind(
				page,
				route,
				_route_generation,
			),
		)
	elif route == &"weather_control" and page.has_signal("closed"):
		page.connect(
			"closed",
			Callable(self, "_on_page_close_requested").bind(
				page,
				route,
				_route_generation,
			),
		)
	elif route == &"place_focus" and page.has_signal("close_requested"):
		page.connect(
			"close_requested",
			Callable(self, "_on_page_close_requested").bind(
				page,
				route,
				_route_generation,
			),
		)
	if route == &"resident_action_menu" and page.has_signal("intent_requested"):
		page.connect(
			"intent_requested",
			Callable(self, "_on_resident_action_intent"),
		)
	elif route == &"inner_observation" and page.has_signal("intent_requested"):
		page.connect(
			"intent_requested",
			Callable(self, "_on_inner_observation_intent"),
		)
	elif route == &"resident_management" and page.has_signal("intent_requested"):
		page.connect(
			"intent_requested",
			Callable(self, "_on_resident_management_intent"),
		)
	elif route == &"resident_profile_editor" and page.has_signal("intent_requested"):
		page.connect(
			"intent_requested",
			Callable(self, "_on_resident_profile_editor_intent"),
		)
	elif page.has_signal("intent_requested"):
		page.connect(
			"intent_requested",
			Callable(self, "_on_self_dispatching_page_intent").bind(route),
		)


func _disable_placeholder_bootstrap(page: Control, route: StringName) -> void:
	match route:
		&"chat":
			page.set("forced_display_mode", "player")
		&"conversation_spectator":
			page.set("forced_display_mode", "spectator")
		&"resident_profile_editor":
			page.set("navigation_back_available", true)
			page.set("presentation_mode", "edit_existing")
		_:
			pass


func _on_view_model_changed(scope: String, view_model: Dictionary) -> void:
	_sync_external_operation_audio(scope, view_model)
	if scope == "town_hud" and is_instance_valid(_hud):
		_hud.call("apply_view_model", view_model)
		_sync_indoor_presence_from_town_hud(view_model)
	elif scope == "avatar":
		_sync_hud_mode_ownership(view_model)
	elif scope == "conversation":
		_sync_conversation_route(view_model)
	elif scope == "indoor":
		_sync_indoor_route(view_model)
	elif scope == "announcements":
		_sync_bulletin_route(view_model)
	elif scope == "town_log":
		_sync_town_log_route(view_model)


func _sync_bulletin_route(view_model: Dictionary) -> void:
	if _route_close_in_progress or _active_route != &"bulletin_board":
		return
	var data := view_model.get("data", {}) as Dictionary
	var panel := data.get("panel", {}) as Dictionary
	if not bool(panel.get("open", false)):
		close_page()


func _sync_town_log_route(view_model: Dictionary) -> void:
	if _route_close_in_progress or _active_route != &"town_log":
		return
	var data := view_model.get("data", {}) as Dictionary
	var panel := data.get("panel", {}) as Dictionary
	if bool(panel.get("open", false)):
		return
	var origin_route := _town_log_origin_route
	var origin_payload := _town_log_origin_payload.duplicate(true)
	_town_log_origin_route = &"town"
	_town_log_origin_payload.clear()
	_route_close_in_progress = false
	if origin_route == &"place_focus":
		_open_page_with_feedback(
			&"place_focus",
			origin_payload,
			"地点页面暂时打不开，请稍后再试。",
		)
	else:
		close_page()


func _sync_conversation_route(view_model: Dictionary) -> void:
	var incoming_revision := int(view_model.get("revision", -1))
	if incoming_revision >= 0:
		if incoming_revision < _conversation_route_revision:
			return
		_conversation_route_revision = incoming_revision
	var data := view_model.get("data", {}) as Dictionary
	var conversation_id := String(data.get("conversationId", "")).strip_edges()
	var display_mode := String(data.get("displayMode", "")).strip_edges()
	var spectator := data.get("spectator", {}) as Dictionary
	var spectator_panel_open := bool(spectator.get("panelOpen", false))
	var target_route := &"" as StringName
	if display_mode == "spectator" and spectator_panel_open:
		target_route = &"conversation_spectator"
	elif display_mode == "player" and not conversation_id.is_empty():
		target_route = &"chat"
	if target_route != &"" and _active_route != target_route:
		_open_page_with_feedback(
			target_route,
			{
				"conversationId": conversation_id,
				"residentId": String(data.get("residentId", "")),
			},
			"对话页面暂时打不开，请稍后再试。",
		)
	elif (
		target_route == &""
		and _active_route in [&"chat", &"conversation_spectator"]
	):
		close_page()


func _sync_indoor_route(view_model: Dictionary) -> void:
	var incoming_revision := int(view_model.get("revision", -1))
	if incoming_revision >= 0:
		if incoming_revision < _indoor_route_revision:
			return
		_indoor_route_revision = incoming_revision
	_indoor_return_outdoor_pending = false
	_indoor_open_scheduled_generation = -1
	if _active_route == &"indoor":
		_schedule_indoor_route_close()


func _sync_indoor_presence_from_town_hud(view_model: Dictionary) -> void:
	var data := view_model.get("data", {}) as Dictionary
	var indoor_markers := data.get("indoorMarkers", {}) as Dictionary
	_observer_indoor_active = bool(indoor_markers.get("visible", false))
	_observer_indoor_route_required = _observer_indoor_active
	_update_persistent_world_ui_visibility()


func _schedule_observer_indoor_route_ensure() -> void:
	# 室内观察页已取消。室内视角只保留常驻返回按钮，居民仍由世界节点直接选择。
	return


func _schedule_indoor_route_close() -> void:
	if (
		_active_route != &"indoor"
		or not is_instance_valid(_active_page)
	):
		return
	if _indoor_close_scheduled_generation == _route_generation:
		return
	_indoor_close_scheduled_generation = _route_generation
	call_deferred(
		"_complete_indoor_route_close",
		_route_generation,
	)


func _complete_indoor_route_close(generation: int) -> void:
	if _indoor_close_scheduled_generation != generation:
		return
	_indoor_close_scheduled_generation = -1
	if generation != _route_generation:
		return
	if (
		_active_route == &"indoor"
		and is_instance_valid(_active_page)
	):
		close_page()


func _sync_hud_mode_ownership(avatar_view_model: Dictionary) -> void:
	var avatar_data := avatar_view_model.get("data", {}) as Dictionary
	_observer_mode_active = String(avatar_data.get("mode", "")) == "observer"
	_update_persistent_world_ui_visibility()


func _update_persistent_world_ui_visibility() -> void:
	if is_instance_valid(_hud):
		# Observer HUD remains visible indoors. Avatar mode still owns no observer
		# HUD, so entering an interior as the avatar does not show it.
		if _hud.has_method("set_indoor_focus_active"):
			_hud.call("set_indoor_focus_active", _observer_indoor_active)
		if _hud.has_method("set_presentation_mode"):
			_hud.call(
				"set_presentation_mode",
				"observer" if _observer_mode_active else "avatar",
			)
		# Keep far-resident conversation bubbles visible in avatar mode;
		# hide the classic observer shell and controls instead.
		_hud.visible = true
		# The HUD root covers the entire viewport. It must stay transparent to
		# world picking so resident/building Area2D hit targets remain clickable.
		# Individual HUD buttons own their own mouse input.
		_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(_indoor_back_button):
		_indoor_back_button.visible = (
			_observer_mode_active and _observer_indoor_active
		)


func _build_indoor_back_button() -> void:
	_indoor_back_layer = CanvasLayer.new()
	_indoor_back_layer.name = "IndoorBackLayer"
	_indoor_back_layer.layer = 190
	_indoor_back_layer.follow_viewport_enabled = false
	add_child(_indoor_back_layer)

	_indoor_back_button = TextureButton.new()
	_indoor_back_button.name = "IndoorBackButton"
	_indoor_back_button.position = INDOOR_BACK_REFERENCE_POSITION
	_indoor_back_button.size = INDOOR_BACK_REFERENCE_SIZE
	_indoor_back_button.texture_normal = INDOOR_RETURN_TEXTURE
	_indoor_back_button.texture_hover = INDOOR_RETURN_TEXTURE
	_indoor_back_button.texture_pressed = INDOOR_RETURN_TEXTURE
	_indoor_back_button.ignore_texture_size = false
	_indoor_back_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_indoor_back_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_indoor_back_button.set_meta(
		"asset_id",
		"ui.indoor-overlay.v4.composite.return-button-park-v1",
	)
	_indoor_back_button.set_meta("border_owner", true)
	_indoor_back_button.tooltip_text = "返回户外"
	_indoor_back_button.accessibility_name = "返回户外"
	_indoor_back_button.focus_mode = Control.FOCUS_ALL
	_indoor_back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_indoor_back_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_indoor_back_button.visible = false
	_indoor_back_button.pressed.connect(_request_return_outdoor)
	_indoor_back_layer.add_child(_indoor_back_button)
	_layout_indoor_back_button()


func _layout_indoor_back_button() -> void:
	if not is_instance_valid(_indoor_back_button):
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var uniform_scale := minf(
		viewport_size.x / HUD_REFERENCE_SIZE.x,
		viewport_size.y / HUD_REFERENCE_SIZE.y,
	)
	var shell_size := HUD_REFERENCE_SIZE * uniform_scale
	var shell_origin := (viewport_size - shell_size) * 0.5
	if viewport_size.x / viewport_size.y >= HUD_REFERENCE_SIZE.x / HUD_REFERENCE_SIZE.y:
		shell_origin.x = 0.0
	_indoor_back_button.position = (
		shell_origin + INDOOR_BACK_REFERENCE_POSITION * uniform_scale
	).round()
	_indoor_back_button.size = (
		INDOOR_BACK_REFERENCE_SIZE * uniform_scale
	).round()


func _request_return_outdoor() -> bool:
	var result := _dispatch_adapter("indoor.return_outdoor", {})
	if bool(result.get("ok", false)):
		return true
	_present_navigation_failure(
		"暂时无法返回户外，请稍后再试。",
		String(result.get("errorCode", "RETURN_OUTDOOR_REJECTED")),
	)
	return false


func _on_operation_completed(scope: String, operation: Dictionary) -> void:
	_play_operation_audio_once(scope, operation)
	if (
		scope == "resident_action_menu"
		and _active_route == &"resident_action_menu"
		and String(operation.get("intent", "")) == "resident.death.confirm"
		and String(operation.get("status", "")) == "success"
	):
		_close_resident_view_and_restore_origin()
		return
	if (
		scope == "resident_detail"
		and _active_route == &"resident_detail"
		and String(operation.get("intent", "")) == "resident_detail.close"
		and String(operation.get("status", "")) == "success"
	):
		if _resident_management_return_pending:
			_return_to_resident_management()
			return
		_close_resident_view_and_restore_origin()
		return
	if (
		scope == "indoor"
		and _active_route == &"indoor"
		and String(operation.get("intent", "")) == "indoor.return_outdoor"
		and String(operation.get("status", "")) == "success"
	):
		_indoor_return_outdoor_pending = true
		_observer_indoor_route_required = false
		_indoor_open_scheduled_generation = -1
		_schedule_indoor_route_close()
	if (
		scope == "place_focus"
		and _active_route == &"place_focus"
		and String(operation.get("intent", "")) in [
			"place_focus.enter_interior",
			"place_focus.retry",
		]
		and String(operation.get("status", "")) == "success"
	):
		_open_page_with_feedback(
			&"indoor",
			{
				"entryReason": "place_focus",
				"sourceRoute": "place_focus",
			},
			"室内页面暂时打不开，请稍后再试。",
		)


func _sync_external_operation_audio(scope: String, view_model: Dictionary) -> void:
	if scope not in [
		"audio_display_settings",
		"provider_settings",
		"announcements",
		"weather_control",
		"resident_action_menu",
		"resident_overview",
		"indoor",
		"town_log",
		"wardrobe",
		"town_hud",
	]:
		return
	var operation := view_model.get("operation", {}) as Dictionary
	var status := String(operation.get("status", ""))
	var request_id := String(operation.get("requestId", ""))
	if request_id.is_empty() or status not in ["success", "rejected", "error"]:
		return
	_play_operation_audio_once(scope, operation)


func _play_operation_audio_once(scope: String, operation: Dictionary) -> void:
	if not _operation_audio_scope_is_active(scope):
		return
	var request_id := String(operation.get("requestId", ""))
	if request_id.is_empty():
		return
	var operation_key := "%s:%s" % [scope, request_id]
	if _heard_audio_operations.has(operation_key):
		return
	_heard_audio_operations[operation_key] = true
	_play_operation_audio(operation)


func _operation_audio_scope_is_active(scope: String) -> bool:
	if scope in [
		"town_hud",
		"save",
		"session",
		"lifecycle",
		"audio_display_settings",
	]:
		return true
	return String(ROUTE_SCOPES.get(_active_route, "")) == scope


func _play_operation_audio(operation: Dictionary) -> void:
	var status := String(operation.get("status", ""))
	var intent := String(operation.get("intent", ""))
	if status in ["rejected", "error"]:
		_play_audio_cue("ui_error")
		return
	if status != "success":
		return
	match intent:
		"save.create", "session.save", "session.save_current", "session.create_save":
			_play_audio_cue("save_stamp")
		"wardrobe.apply":
			_play_audio_cue("wardrobe_equip")
		"wardrobe.randomize":
			_play_audio_cue("wardrobe_shuffle")
		"resident.follow", "resident_overview.follow", "town_hud.camera_follow", "town_hud.camera_unfollow":
			_play_audio_cue("camera_lock")
		"town_hud.camera_zoom_in", "town_hud.camera_zoom_out", "town_hud.camera_zoom_reset", "town_hud.camera_reset":
			_play_audio_cue("camera_zoom")
		"lifecycle.pause":
			_play_audio_cue("ui_toggle_on")
		"lifecycle.resume":
			_play_audio_cue("ui_toggle_off")
		"town_hud.set_time_speed":
			_play_audio_cue("ui_select")
		"indoor.focus_target":
			_play_audio_cue("ui_confirm")
		"provider_settings.check_connection":
			_play_audio_cue("ui_success")
		_:
			pass


func _play_audio_cue(cue_id: String, volume_db: float = 0.0) -> void:
	var audio_controller := get_node_or_null("/root/TownAudioController")
	if audio_controller != null and audio_controller.has_method("play_cue"):
		audio_controller.call("play_cue", cue_id, volume_db)


func _on_hud_intent_requested(intent: StringName, payload: Dictionary) -> void:
	match String(intent):
		"town_hud.open_event":
			# 兼容旧 HUD 意图：公告事件属于小镇日志事件链，
			# 不再把玩家带回用来撰写公告的公告栏。
			_open_town_log(payload)
		"town_hud.open_bulletin":
			_open_page_with_feedback(
				&"bulletin_board",
				_bulletin_route_payload(payload),
				"公告栏暂时打不开，请稍后再试。",
			)
		"town_hud.open_resident_action":
			_open_page_with_feedback(
				&"resident_action_menu",
				payload,
				"居民操作暂时打不开，请稍后再试。",
			)
		"conversation.spectator.select":
			var select_result := _dispatch_adapter(String(intent), payload)
			if bool(select_result.get("ok", false)):
				_open_page_with_feedback(
					&"conversation_spectator",
					payload,
					"对话页面暂时打不开，请稍后再试。",
				)
			else:
				_present_navigation_failure(
					"对话页面暂时打不开，请稍后再试。",
					String(select_result.get("errorCode", "")),
				)
		"town_hud.open_conversation_spectator":
			_open_page_with_feedback(
				&"conversation_spectator",
				payload,
				"旁观对话暂时打不开，请稍后再试。",
			)
		"town_hud.open_weather":
			_open_page_with_feedback(
				&"weather_control",
				payload,
				"天气控制暂时打不开，请稍后再试。",
			)
		"town_hud.open_town_log":
			_open_town_log(payload)
		"town_hud.open_wardrobe":
			_open_page_with_feedback(
				&"wardrobe",
				payload,
				"换装页面暂时打不开，请稍后再试。",
			)
		"town_hud.open_indoor_target":
			_open_page_with_feedback(
				&"indoor",
				payload,
				"室内页面暂时打不开，请稍后再试。",
			)
		"town_hud.open_resident_management":
			_open_page_with_feedback(
				&"resident_management",
				payload,
				"居民名单暂时打不开，请稍后再试。",
			)
		"town_hud.open_place_focus":
			var entered := _dispatch_adapter(String(intent), payload)
			if not bool(entered.get("ok", false)):
				_present_navigation_failure(
					"暂时无法进入这个地点，请稍后再试。",
					String(entered.get("errorCode", "PLACE_OBSERVATION_REJECTED")),
				)
		"town_hud.open_more":
			pause_requested.emit()
		"town_hud.toggle_avatar":
			_dispatch_adapter("town_hud.toggle_avatar", {})
			close_page()
		"town_hud.select_tool":
			_open_toolbar_tool(String(payload.get("toolId", "")))
		"avatar.focus_target":
			# Avatar target cycling must not open the observer resident menu.
			_dispatch_adapter(String(intent), payload)
		_:
			_dispatch_adapter(String(intent), payload)


func _bulletin_route_payload(payload: Dictionary) -> Dictionary:
	var routed_payload := payload.duplicate(true)
	if (
		not routed_payload.has("presentationMode")
		and not routed_payload.has("avatarMode")
		and is_instance_valid(_adapter)
		and _adapter.has_method("get_view_model")
	):
		var avatar_view_model := _adapter.call(
			"get_view_model",
			"avatar",
		) as Dictionary
		var avatar_data := avatar_view_model.get("data", {}) as Dictionary
		var avatar_mode := String(avatar_data.get("mode", "observer"))
		routed_payload["avatarMode"] = avatar_mode
		routed_payload["presentationMode"] = (
			"overview"
			if avatar_mode == "observer"
			else "avatar"
		)
	return routed_payload


func _open_toolbar_tool(tool_id: String) -> void:
	match tool_id:
		"weather_control":
			_open_page_with_feedback(
				&"weather_control",
				{},
				"天气控制暂时打不开，请稍后再试。",
			)
		"town_log":
			_open_town_log()
		"avatar":
			_dispatch_adapter("town_hud.toggle_avatar", {})
			close_page()
		"more": pause_requested.emit()
		_: pass


func _on_self_dispatching_page_intent(
	intent: StringName,
	payload: Dictionary,
	route: StringName,
) -> void:
	if (
		route == &"resident_model_assignment"
		and String(intent) == "resident_model_assignment.apply_draft"
	):
		var dispatch_result := payload.get("dispatchResult", {}) as Dictionary
		if bool(dispatch_result.get("ok", false)):
			if _resident_assignment_returns_to_provider_settings:
				call_deferred(
					"_return_to_provider_settings_from_assignment",
				)
			else:
				close_page()
		return
	if (
		route == &"provider_settings"
		and String(intent) == "provider_settings.open_model_assignment"
	):
		call_deferred(
			"_open_resident_assignment_from_provider_settings",
			payload.duplicate(true),
		)
		return
	if (
		route == &"resident_model_assignment"
		and String(intent) == "resident_model_assignment.back"
		and _resident_assignment_returns_to_provider_settings
	):
		call_deferred("_return_to_provider_settings_from_assignment")
		return
	if route == &"wardrobe" and _resident_profile_wardrobe_return_pending:
		if String(intent) == "resident_profile_editor.apply_wardrobe_result":
			var dispatch_result := payload.get("dispatchResult", {}) as Dictionary
			if bool(dispatch_result.get("ok", false)):
				call_deferred(
					"_return_to_resident_profile_editor_from_wardrobe",
				)
			return
		if String(intent) == "wardrobe.cancel":
			call_deferred(
				"_return_to_resident_profile_editor_from_wardrobe",
			)
			return
	if (
		route == &"town_log"
		and String(intent) == "town_log.close"
	):
		# The page dispatches the close intent after emitting it. Route changes
		# are driven by the confirmed panel.open=false ViewModel so the Adapter
		# remains bound long enough to update its state.
		return
	if (
		route == &"bulletin_board"
		and String(intent) == "announcements.panel.close"
	):
		# A non-empty draft turns this intent into a confirmation dialog. Wait
		# for the announcements ViewModel before deciding whether to close.
		return
	if (
		route == &"resident_detail"
		and String(intent) == "resident_detail.close"
	):
		# A formally bound ResidentDetailScreen dispatches this intent itself
		# after emitting it. Keep the page and Adapter bound until the matching
		# operation_completed(success) callback closes the route.
		if (
			is_instance_valid(_active_page)
			and _active_page.has_method("adapter_contract_available")
			and bool(_active_page.call("adapter_contract_available"))
		):
			return
		# Only the explicit no-Adapter fallback may close locally.
		if _resident_management_return_pending:
			_return_to_resident_management()
			return
		_finish_resident_view()
		close_page()
		return
	if route == &"place_focus":
		match String(intent):
			"place_focus.open_resident":
				pass
			"place_focus.open_event", "place_focus.open_log":
				_open_town_log(payload, &"place_focus")
	elif (
		route == &"indoor"
		and String(intent) == "indoor.focus_target"
	):
		call_deferred(
			"_open_indoor_resident_action_menu",
			payload.duplicate(true),
		)
		return
	if _intent_closes_route(String(intent), route):
		close_page()


func _open_resident_assignment_from_provider_settings(
	payload: Dictionary,
) -> void:
	_resident_assignment_returns_to_provider_settings = true
	_resident_assignment_provider_payload = payload.duplicate(true)
	var resident_ids := payload.get("residentIds", []) as Array
	var selected_resident_id := (
		String(resident_ids[0]) if not resident_ids.is_empty() else ""
	)
	var route_payload := {
		"mode": "in_session",
		"returnToProviderSettings": true,
		"selectedResidentId": selected_resident_id,
	}
	var result := open_page(&"resident_model_assignment", route_payload)
	if not bool(result.get("ok", false)):
		_clear_provider_assignment_return()
		_present_navigation_failure(
			"居民模型分配暂时打不开，请稍后再试。",
			String(result.get("errorCode", "")),
		)
		return
	if not selected_resident_id.is_empty():
		call_deferred(
			"_select_resident_for_provider_assignment",
			selected_resident_id,
		)


func _select_resident_for_provider_assignment(resident_id: String) -> void:
	if (
		_active_route != &"resident_model_assignment"
		or resident_id.is_empty()
		or not is_instance_valid(_adapter)
	):
		return
	var view_model := _adapter.get_view_model(
		"resident_model_assignment",
	) as Dictionary
	_dispatch_adapter(
		"resident_model_assignment.select_resident",
		{
			"residentId": resident_id,
			"revision": int(view_model.get("revision", -1)),
		},
	)


func _return_to_provider_settings_from_assignment() -> void:
	if not _resident_assignment_returns_to_provider_settings:
		return
	var payload := _resident_assignment_provider_payload.duplicate(true)
	_clear_provider_assignment_return()
	var result := open_page(&"provider_settings", payload)
	if not bool(result.get("ok", false)):
		_present_navigation_failure(
			"模型设置暂时打不开，请稍后再试。",
			String(result.get("errorCode", "")),
		)


func _clear_provider_assignment_return() -> void:
	_resident_assignment_returns_to_provider_settings = false
	_resident_assignment_provider_payload.clear()


func _open_town_log(
	payload: Dictionary = {},
	origin_route: StringName = &"town",
) -> Dictionary:
	_town_log_origin_route = origin_route
	_town_log_origin_payload.clear()
	if origin_route == &"place_focus":
		_town_log_origin_payload = _resident_action_return_payload(
			origin_route,
			_active_page,
		)
	var result := open_page(&"town_log", payload)
	if not bool(result.get("ok", false)):
		_town_log_origin_route = &"town"
		_town_log_origin_payload.clear()
		_present_navigation_failure(
			"小镇日志暂时打不开，请稍后再试。",
			String(result.get("errorCode", "")),
		)
	return result


func _on_resident_management_intent(
	intent: StringName,
	payload: Dictionary,
) -> void:
	match String(intent):
		"resident_overview.close", "resident_management.close":
			close_page()
		"resident_overview.follow":
			var dispatch_result := payload.get("dispatchResult", {}) as Dictionary
			if bool(dispatch_result.get("ok", false)):
				close_page()
		"resident_overview.open_detail", "resident_management.open_detail":
			if is_instance_valid(_active_page) and _active_page.has_method("navigation_state"):
				_resident_management_return_state = (
					_active_page.call("navigation_state") as Dictionary
				).duplicate(true)
			_resident_management_return_state["selectedResidentId"] = String(
				payload.get(
					"residentId",
					_resident_management_return_state.get("selectedResidentId", ""),
				)
			)
			_resident_management_return_state["editing"] = false
			_resident_management_return_pending = true
			var detail_opened := open_page(
				&"resident_detail",
				_resident_detail_route_payload(payload),
			)
			if not bool(detail_opened.get("ok", false)):
				_resident_management_return_pending = false
				_present_navigation_failure(
					"居民详情暂时打不开，请稍后再试。",
					String(detail_opened.get("errorCode", "")),
				)
		"resident_overview.edit_profile":
			var profile_opened := _open_resident_profile_editor(
				String(payload.get("residentId", "")),
			)
			if not bool(profile_opened.get("ok", false)):
				_present_navigation_failure(
					"居民资料编辑暂时打不开，请稍后再试。",
					String(profile_opened.get("errorCode", "")),
				)


func _open_resident_profile_editor(resident_id: String) -> Dictionary:
	if resident_id.strip_edges().is_empty():
		return _failure("RESIDENT_IDENTITY_NOT_FOUND")
	if is_instance_valid(_active_page) and _active_page.has_method("navigation_state"):
		_resident_management_return_state = (
			_active_page.call("navigation_state") as Dictionary
		).duplicate(true)
	_resident_management_return_state["selectedResidentId"] = resident_id
	_resident_management_return_state["editing"] = true
	_resident_management_return_pending = true
	_unbind_resident_profile_editor_service()
	var service := RESIDENT_PROFILE_EDITOR_SERVICE.new() as RefCounted
	var configured := service.call("configure", _adapter, resident_id) as Dictionary
	if not bool(configured.get("ok", false)):
		_resident_management_return_pending = false
		return configured
	var bound := _adapter.call(
		"bind_custom_resident_creator_service",
		service,
	) as Dictionary
	if not bool(bound.get("ok", false)):
		_resident_management_return_pending = false
		return bound
	_adapter.call(
		"set_custom_resident_creator_route_capabilities",
		{"wardrobe": true},
	)
	_resident_profile_editor_service = service
	var pause_result := _set_resident_profile_editor_paused(true)
	if not bool(pause_result.get("ok", false)):
		_unbind_resident_profile_editor_service()
		_resident_management_return_pending = false
		return pause_result
	var opened := open_page(
		&"resident_profile_editor",
		{"residentId": resident_id, "presentationMode": "edit_existing"},
	)
	if not bool(opened.get("ok", false)):
		var resume_result := _set_resident_profile_editor_paused(false)
		_unbind_resident_profile_editor_service()
		_resident_management_return_pending = false
		if not bool(resume_result.get("ok", false)):
			return resume_result
	return opened


func _on_resident_profile_editor_intent(
	intent: StringName,
	payload: Dictionary,
) -> void:
	if String(intent) == "resident_profile_editor.open_wardrobe":
		var dispatch_result := payload.get("dispatchResult", {}) as Dictionary
		if not bool(dispatch_result.get("ok", false)):
			return
		var handoff := dispatch_result.get("wardrobeHandoff", {}) as Dictionary
		if handoff.is_empty():
			return
		if (
			not is_instance_valid(_active_page)
			or not _active_page.has_method("open_complete_set_wardrobe")
			or not bool(_active_page.call(
				"open_complete_set_wardrobe",
				handoff.duplicate(true),
			))
		):
			_present_navigation_failure(
				"换装页面暂时打不开，请稍后再试。",
				"RESIDENT_PROFILE_WARDROBE_ROUTE_UNAVAILABLE",
			)
		return
	if String(intent) not in [
		"resident_profile_editor.cancel",
		"resident_profile_editor.save_existing",
	]:
		return
	var dispatch_result := payload.get("dispatchResult", {}) as Dictionary
	if (
		String(intent) == "resident_profile_editor.cancel"
		or bool(dispatch_result.get("ok", false))
	):
		call_deferred("_return_from_resident_profile_editor")


func _return_to_resident_profile_editor_from_wardrobe() -> void:
	if (
		_active_route != &"wardrobe"
		or not _resident_profile_wardrobe_return_pending
		or _resident_profile_editor_service == null
	):
		return
	var resident_id := String(
		_resident_management_return_state.get("selectedResidentId", ""),
	)
	var opened := open_page(
		&"resident_profile_editor",
		{"residentId": resident_id, "presentationMode": "edit_existing"},
	)
	if bool(opened.get("ok", false)):
		_resident_profile_wardrobe_return_pending = false
	else:
		_present_navigation_failure(
			"居民资料页面暂时打不开，请稍后再试。",
			String(opened.get("errorCode", "")),
		)


func _return_from_resident_profile_editor() -> void:
	if _active_route != &"resident_profile_editor":
		return
	var return_payload := _resident_management_return_state.duplicate(true)
	return_payload["editing"] = false
	return_payload["focusControl"] = "primary"
	var opened := open_page(&"resident_management", return_payload)
	if bool(opened.get("ok", false)):
		_resident_management_return_pending = false
		_unbind_resident_profile_editor_service()
	else:
		_present_navigation_failure(
			"居民列表暂时打不开，请稍后再试。",
			String(opened.get("errorCode", "")),
		)


func _unbind_resident_profile_editor_service() -> void:
	if (
		is_instance_valid(_adapter)
		and _adapter.has_method("bind_custom_resident_creator_service")
		and _resident_profile_editor_service != null
	):
		_adapter.call("bind_custom_resident_creator_service", null)
	_resident_profile_editor_service = null
	_resident_profile_wardrobe_return_pending = false


func _set_resident_profile_editor_paused(paused: bool) -> Dictionary:
	if paused == _resident_profile_editor_pause_active:
		return {"ok": true, "errorCode": "", "retryable": false}
	var intent := "lifecycle.pause" if paused else "lifecycle.resume"
	var result := _dispatch_adapter(intent, {"reason": "resident_editor"})
	if bool(result.get("ok", false)):
		_resident_profile_editor_pause_active = paused
	return result


func _return_to_resident_management() -> bool:
	if not _resident_management_return_pending:
		return false
	var return_payload := _resident_management_return_state.duplicate(true)
	_resident_management_return_pending = false
	return_payload["focusControl"] = "status"
	var opened: Dictionary = open_page(&"resident_management", return_payload)
	if not bool(opened.get("ok", false)):
		_resident_management_return_pending = true
		_present_navigation_failure(
			"居民列表暂时打不开，请稍后再试。",
			String(opened.get("errorCode", "")),
		)
	return bool(opened.get("ok", false))


func _on_page_close_requested(
	page: Control,
	route: StringName,
	generation: int,
) -> void:
	if (
		generation != _route_generation
		or route != _active_route
		or page != _active_page
	):
		return
	close_page()


func _on_resident_action_intent(
	intent: StringName,
	payload: Dictionary,
	_revision: int,
	_request_id: String,
) -> void:
	match String(intent):
		"resident.death.confirm":
			_show_resident_death_confirmation(payload)
		"resident.action_menu.close":
			var close_result := _dispatch_adapter(String(intent), payload)
			if bool(close_result.get("ok", false)):
				_close_resident_view_and_restore_origin()
		"resident.detail.open":
			var detail_result := _dispatch_adapter(String(intent), payload)
			if bool(detail_result.get("ok", false)):
				var open_result := open_page(
					&"resident_detail",
					_resident_detail_route_payload(payload),
				)
				if not bool(open_result.get("ok", false)):
					_dispatch_adapter("resident_detail.close", payload)
					_present_navigation_failure(
						"居民详情暂时打不开，请稍后再试。",
					)
		"resident.inner_observation.open":
			# The Host can stay mounted while the Adapter is rebound during a
			# session refresh. Reconfirm the resident-view phase before moving
			# into the inner page instead of trusting the Host-side boolean.
			var resident_view_result := _begin_resident_view(true)
			if not bool(resident_view_result.get("ok", false)):
				_present_navigation_failure(
					"内心页面暂时打不开，请稍后再试。",
					String(resident_view_result.get("errorCode", "")),
				)
				return
			var transition_result := (
				_transition_resident_view_to_inner_observation()
			)
			if not bool(transition_result.get("ok", false)):
				_present_navigation_failure(
					"内心页面暂时打不开，请稍后再试。",
					String(transition_result.get("errorCode", "")),
				)
				return
			var open_result := open_page(&"inner_observation", payload)
			if not bool(open_result.get("ok", false)):
				_transition_inner_observation_to_resident_view()
				_present_navigation_failure(
					"内心页面暂时打不开，请稍后再试。",
					String(open_result.get("errorCode", "")),
				)
				return
			var inner_result := _dispatch_adapter(String(intent), payload)
			if not bool(inner_result.get("ok", false)):
				close_page(false)
				_transition_inner_observation_to_resident_view()
				var return_result := open_page(
					&"resident_action_menu",
					_resident_detail_route_payload(payload),
				)
				if not bool(return_result.get("ok", false)):
					_finish_resident_view()
				_present_navigation_failure(
					"内心页面暂时打不开，请稍后再试。",
					String(inner_result.get("errorCode", "")),
				)
		"resident.follow":
			var result := _dispatch_adapter(String(intent), payload)
			if bool(result.get("ok", false)):
				_clear_resident_view_return()
				_finish_resident_view()
				close_page()
		_:
			_dispatch_adapter(String(intent), payload)


func _show_resident_death_confirmation(payload: Dictionary) -> void:
	if _resident_death_confirmation == null:
		_resident_death_confirmation = FORMAL_DIALOG.new()
		_resident_death_confirmation.name = "ResidentDeathConfirmation"
		_resident_death_confirmation.title = "确认杀死居民？"
		_resident_death_confirmation.ok_button_text = "确认杀死"
		_resident_death_confirmation.cancel_button_text = "取消"
		_resident_death_confirmation.semantic_kind = "error"
		_resident_death_confirmation.confirmed.connect(
			_confirm_resident_death,
		)
		_resident_death_confirmation.canceled.connect(
			_cancel_resident_death_confirmation,
		)
		add_child(_resident_death_confirmation)
	_pending_resident_death_payload = payload.duplicate(true)
	var resident_name := String(
		payload.get("residentName", "这名居民"),
	).strip_edges()
	if resident_name.is_empty():
		resident_name = "这名居民"
	_resident_death_confirmation.dialog_text = (
		"%s 会永久死亡，行动、对话与工作都会立即结束，死亡会记入小镇历史。"
		% resident_name
	)
	_resident_death_confirmation.popup_centered()


func _cancel_resident_death_confirmation() -> void:
	_pending_resident_death_payload.clear()


func _confirm_resident_death() -> void:
	if _pending_resident_death_payload.is_empty():
		return
	var payload := _pending_resident_death_payload.duplicate(true)
	_pending_resident_death_payload.clear()
	_dispatch_adapter("resident.death.confirm", payload)


func _on_inner_observation_intent(
	intent: StringName,
	payload: Dictionary,
	_revision: int,
	_request_id: String,
) -> void:
	var result := _dispatch_adapter(String(intent), payload)
	if (
		String(intent) == "inner_observation.exit"
		and bool(result.get("ok", false))
	):
		_close_resident_view_and_restore_origin()


func _resident_detail_route_payload(payload: Dictionary) -> Dictionary:
	var routed := payload.duplicate(true)
	var requested_tab := String(
		routed.get(
			"selectedTab",
			routed.get("tab", "status"),
		),
	).strip_edges()
	var selected_tab := String({
		"relationship": "relationships",
		"memory": "memories",
	}.get(requested_tab, requested_tab))
	if selected_tab not in ["status", "relationships", "memories"]:
		selected_tab = "status"
	routed["selectedTab"] = selected_tab
	return routed


func _open_indoor_resident_action_menu(payload: Dictionary) -> void:
	if _active_route != &"indoor" or not is_instance_valid(_active_page):
		return
	var resident_id := String(payload.get("residentId", "")).strip_edges()
	if resident_id.is_empty():
		return
	_resident_view_return_route = &"indoor"
	_resident_view_return_payload = {
		"entryReason": "return_from_resident",
		"residentId": resident_id,
	}
	var preserved_focus_return_path := _focus_return_path
	if not close_page(false):
		_clear_resident_view_return()
		_present_navigation_failure(
			"居民操作暂时打不开，请稍后再试。",
			"TOWN_UI_ROUTE_CLOSE_FAILED",
		)
		return
	var opened := open_page(&"resident_action_menu", {
		"residentId": resident_id,
	})
	_focus_return_path = preserved_focus_return_path
	if bool(opened.get("ok", false)):
		return
	var return_route := _resident_view_return_route
	var return_payload := _resident_view_return_payload.duplicate(true)
	_clear_resident_view_return()
	if return_route != &"":
		var restored := _open_page_with_feedback(
			return_route,
			return_payload,
			"原页面暂时无法恢复，请稍后再试。",
		)
		_focus_return_path = preserved_focus_return_path
		if not bool(restored.get("ok", false)):
			return
	_present_navigation_failure(
		"居民操作暂时打不开，请稍后再试。",
		String(opened.get("errorCode", "")),
	)


func _close_resident_view_and_restore_origin() -> void:
	var return_route := _resident_view_return_route
	var return_payload := _resident_view_return_payload.duplicate(true)
	_clear_resident_view_return()
	_finish_resident_view()
	if return_route == &"":
		close_page()
		return
	var preserved_focus_return_path := _focus_return_path
	if not close_page(false):
		_present_navigation_failure(
			"原页面暂时无法恢复，请稍后再试。",
			"TOWN_UI_ROUTE_CLOSE_FAILED",
		)
		return
	_open_page_with_feedback(
		return_route,
		return_payload,
		"原页面暂时无法恢复，请稍后再试。",
	)
	_focus_return_path = preserved_focus_return_path


func _clear_resident_view_return() -> void:
	_resident_view_return_route = &""
	_resident_view_return_payload.clear()


func _begin_resident_view(force_resync := false) -> Dictionary:
	if _resident_view_active and not force_resync:
		return {"ok": true, "errorCode": "", "retryable": false}
	if not _adapter.has_method("begin_resident_view"):
		return _failure("RESIDENT_VIEW_LIFECYCLE_INTERFACE_MISSING")
	var result := _adapter.call("begin_resident_view") as Dictionary
	if bool(result.get("ok", false)):
		_resident_view_active = true
	return result


func _transition_resident_view_to_inner_observation() -> Dictionary:
	if not _resident_view_active:
		return _failure("RESIDENT_VIEW_NOT_ACTIVE")
	if not _adapter.has_method(
		"transition_resident_view_to_inner_observation"
	):
		return _failure("RESIDENT_VIEW_PHASE_INTERFACE_MISSING")
	return _adapter.call(
		"transition_resident_view_to_inner_observation"
	) as Dictionary


func _transition_inner_observation_to_resident_view() -> Dictionary:
	if not _resident_view_active:
		return _failure("RESIDENT_VIEW_NOT_ACTIVE")
	if not _adapter.has_method(
		"transition_inner_observation_to_resident_view"
	):
		return _failure("RESIDENT_VIEW_PHASE_INTERFACE_MISSING")
	return _adapter.call(
		"transition_inner_observation_to_resident_view"
	) as Dictionary


func _finish_resident_view() -> Dictionary:
	if not _resident_view_active:
		return {"ok": true, "errorCode": "", "retryable": false}
	if not is_instance_valid(_adapter) or not _adapter.has_method("end_resident_view"):
		return _failure("RESIDENT_VIEW_LIFECYCLE_INTERFACE_MISSING")
	var result := _adapter.call("end_resident_view") as Dictionary
	if bool(result.get("ok", false)):
		_resident_view_active = false
	return result


func _resident_action_return_payload(
	origin_route: StringName,
	page: Control,
) -> Dictionary:
	if not is_instance_valid(page):
		return {}
	if page.has_method("navigation_state"):
		return (
			page.call("navigation_state") as Dictionary
		).duplicate(true)
	if (
		origin_route == &"place_focus"
		and page.has_method("current_view_model")
	):
		var view_model := page.call("current_view_model") as Dictionary
		var data := view_model.get("data", {}) as Dictionary
		var place := data.get("place", {}) as Dictionary
		var place_name := String(place.get("placeName", "")).strip_edges()
		return {"placeName": place_name} if not place_name.is_empty() else {}
	if origin_route == &"indoor":
		return {"entryReason": "return_from_resident"}
	return {}


func _dispatch_adapter(intent: String, payload: Dictionary) -> Dictionary:
	if not is_instance_valid(_adapter) or not _adapter.has_method("dispatch"):
		return _failure("TOWN_UI_ADAPTER_UNAVAILABLE")
	return _adapter.call("dispatch", intent, payload.duplicate(true)) as Dictionary


func _open_page_with_feedback(
	route: StringName,
	payload: Dictionary,
	message: String,
) -> Dictionary:
	var result := open_page(route, payload)
	if not bool(result.get("ok", false)):
		_present_navigation_failure(
			message,
			String(result.get("errorCode", "")),
		)
	return result


func _present_navigation_failure(
	message: String,
	error_code := "TOWN_UI_ROUTE_OPEN_FAILED",
) -> void:
	if (
		is_instance_valid(_active_page)
		and _active_page.has_method("show_navigation_failure")
	):
		_active_page.call("show_navigation_failure", message)
		return
	_present_navigation_feedback(
		"页面没有打开",
		message,
		error_code,
		"navigation.open",
	)


func present_back_blocked_feedback(
	message := "当前操作还没完成，请稍后再试。",
) -> void:
	_present_navigation_feedback(
		"暂时无法返回",
		message,
		"TOWN_UI_BACK_BLOCKED",
		"navigation.back",
	)


func _present_navigation_feedback(
	title: String,
	message: String,
	error_code: String,
	intent: String,
) -> void:
	_navigation_feedback_revision += 1
	present_feedback({
		"scope": "navigation",
		"status": "ready",
		"revision": _navigation_feedback_revision,
		"data": {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"feedback": {
				"feedbackId": "navigation-%d" % _navigation_feedback_revision,
				"component": "toast",
				"tone": "error",
				"title": title,
				"message": message,
				"blocking": false,
				"dismissPolicy": "auto_or_manual",
				"durationMsec": 4500,
				"anchor": "viewport_top_right",
				"dedupeKey": (
					"navigation.%s"
					% (
						error_code
						if not error_code.is_empty()
						else "route_open_failed"
					)
				),
			},
		},
		"actions": {},
		"operation": {
			"requestId": "navigation-%d" % _navigation_feedback_revision,
			"intent": intent,
			"status": "error",
			"submittedAtMsec": 0,
			"completedAtMsec": 0,
		},
		"error": {
			"code": (
				error_code
				if not error_code.is_empty()
				else "TOWN_UI_ROUTE_OPEN_FAILED"
			),
			"message": message,
			"retryable": true,
		},
	})


func _intent_closes_route(intent: String, route: StringName) -> bool:
	return intent in {
		&"provider_settings": ["provider_settings.back"],
		&"resident_model_assignment": ["resident_model_assignment.back"],
		&"wardrobe": ["wardrobe.cancel"],
		&"resident_detail": ["resident_detail.close"],
	}.get(route, [])


func _disconnect_adapter() -> void:
	_clear_provider_assignment_return()
	_clear_resident_view_return()
	_conversation_route_revision = -1
	_indoor_route_revision = -1
	_indoor_close_scheduled_generation = -1
	_indoor_open_scheduled_generation = -1
	_observer_indoor_route_required = false
	_indoor_return_outdoor_pending = false
	_resident_profile_wardrobe_return_pending = false
	_town_log_origin_route = &"town"
	_town_log_origin_payload.clear()
	if not is_instance_valid(_adapter):
		_adapter = null
		return
	var previous_adapter := _adapter
	_adapter = null
	var callback := Callable(self, "_on_view_model_changed")
	if (
		previous_adapter.has_signal("view_model_changed")
		and previous_adapter.is_connected("view_model_changed", callback)
	):
		previous_adapter.disconnect("view_model_changed", callback)
	var operation_callback := Callable(self, "_on_operation_completed")
	if (
		previous_adapter.has_signal("operation_completed")
		and previous_adapter.is_connected("operation_completed", operation_callback)
	):
		previous_adapter.disconnect("operation_completed", operation_callback)


func _failure(error_code: String) -> Dictionary:
	return RESULT_SHAPES.failure(error_code)
