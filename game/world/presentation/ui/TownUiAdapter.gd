class_name TownUiAdapter
extends Node

signal view_model_changed(scope: String, view_model: Dictionary)
signal operation_completed(scope: String, operation: Dictionary)

const WORLD_SCOPES: Array[String] = [
	"lifecycle",
	"environment",
	"avatar",
	"conversation",
	"announcements",
	"town_hud",
]
const WORLD_SCOPE_REFRESH_MIN_INTERVAL_MSEC := 150
const ALL_SCOPES: Array[String] = [
	"lifecycle",
	"environment",
	"avatar",
	"conversation",
	"announcements",
	"town_hud",
	"session",
	"save",
	"pause_menu",
	"audio_display_settings",
	"provider_settings",
	"custom_resident_creator",
	"resident_editor",
	"resident_model_assignment",
	"weather_control",
	"resident_action_menu",
	"resident_overview",
	"resident_detail",
	"inner_observation",
	"place_focus",
	"indoor",
	"town_log",
	"wardrobe",
]
const CONVERSATION_GATEWAY_ERROR_CODES := [
	"AGENT_RESPONSE_TIMEOUT",
	"AGENT_DECISION_REQUEST_FAILED",
]
const CONVERSATION_WAIT_TIMEOUT_MSEC := 65_000
const DEFAULT_PLAYER_AVATAR_ID := "person_7f3a91c2d8e4"
const AVATAR_ATTACK_KIND_BY_ACTION_ID := {
	"skill_attack_1": "unarmed",
	"skill_attack_2": "avatar_susanoo_strike",
	"skill_attack_3": "avatar_rasengan",
	"skill_attack_4": "avatar_kamehameha",
}
const HUD_PUBLIC_THOUGHT_LIFETIME_MSEC := 2500
const HUD_ACTIVITY_REACTION_LIFETIME_MSEC := 5000
const HUD_SOCIAL_MATTER_LIFETIME_MSEC := 2500
const HUD_OFFSCREEN_VISIBLE_BUDGET := 2
const HUD_TRANSIENT_RESIDENT_VISIBLE_BUDGET := 3
const HUD_RESIDENT_DIRECTORY_SHORT_LABEL_MAX_CHARACTERS := 10
const HUD_PLACE_DIRECTORY_PRIMARY_ORDER := [
	"中心广场",
	"花房咖啡馆",
	"诊所",
	"独立市集",
	"镇公所",
	"北街一号住宅",
]
const SESSION_SAVE_SERVICE_MISSING := "SESSION_SAVE_SERVICE_NOT_BOUND"
const SESSION_CONTINUE_HOST_ROUTING_REQUIRED := "SESSION_CONTINUE_REQUIRES_STARTUP_HOST"
const PROVIDER_HEALTH_ERROR_CODE := "PROVIDER_HEALTH_INTERFACE_MISSING"
const NEW_GAME_DRAFT := preload("res://world/presentation/session/TownNewGameDraft.gd")
const RESIDENT_CATALOG := preload("res://world/presentation/session/TownResidentCatalog.gd")
const RESIDENT_EDITOR_SERVICE := preload(
	"res://world/presentation/session/TownResidentEditorService.gd"
)
const RESIDENT_WARDROBE_CATALOG_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/wardrobe_catalog.json"
)
const CONVERSATION_BUBBLE_PLAYBACK := preload(
	"res://world/presentation/ui/TownConversationBubblePlayback.gd"
)
const HUD_TEXT_FONT := preload(
	"res://assets/fonts/zheng_ge_dian_hei_16/ZhengGeDianHei-16.ttf"
)

var _runtime: Node
var _runtime_head_anchor_call := Callable()
var _world: RefCounted
var _gateway: Node
var _session_save_service: Object
var _ui_route_host: Object
var _audio_display_settings_service: Object
var _provider_settings_service: Object
var _custom_resident_creator_service: Object
var _custom_resident_creator_wardrobe_route_available := false
var _resident_editor_service: Object
var _resident_model_assignment_service: Object
var _resident_model_assignment_startup_state: Dictionary = {}
var _page_projection_service: Object
var _session_config: Dictionary = {}
var _view_models: Dictionary = {}
var _dirty_world_scopes: Dictionary = {}
var _world_revision := -1
var _pending_world_refresh_scopes: Array[String] = []
var _world_refresh_wait_frames := 0
var _world_scope_refreshed_msec: Dictionary = {}
var _request_sequence := 0
var _gateway_error_sequence := 0
var _conversation_wait_started_msec := 0
var _conversation_wait_conversation_id := ""
var _conversation_wait_resident_id := ""
var _conversation_wait_decision_id := ""
var _conversation_network_error: Dictionary = {}
var _pending_player_ended_conversation: Dictionary = {}
var _local_player_close_conversation_id := ""
var _anchor_refresh_elapsed := 0.0
var _resident_id_by_name: Dictionary = {}
var _resident_name_by_id: Dictionary = {}
var _resident_identity_status := "unavailable"
var _focused_nearby_resident_id := ""
var _focused_nearby_target_manual := false
var _avatar_target_revision := 0
var _avatar_attack_sequence := 0
var _spectator_selected_conversation_id := ""
var _spectator_panel_open := false
var _hud_far_conversations: Dictionary = {}
var _hud_far_conversation_order: Array[String] = []
var _hud_far_seen_conversation_ids: Dictionary = {}
var _hud_far_confirmed_revision := -1
var _hud_conversation_bubble_playback: RefCounted = CONVERSATION_BUBBLE_PLAYBACK.new()
var _hud_public_thoughts: Dictionary = {}
var _hud_public_thought_order: Array[String] = []
# 1b:按显式播放身份冻结首次发布的播放时间;身份消失即清除。
var _hud_playback_times: Dictionary = {}
var _town_hud_last_stable_projection: Dictionary = {}
# 1a:候选缺失权威居民状态(或 spaceId 为空)时跳过并计数,不回退锚点。
var _hud_overlay_missing_state_count := 0
var _hud_social_matter_seen_keys: Dictionary = {}
var _hud_social_matter_initialized := false
var _hud_social_matter_projection: Dictionary = {}
var _hud_social_matter_polled_world_revision := -1
var _hud_last_camera_zoom_band := ""
var _hud_pause_started_msec := 0
var _hud_resident_directory_signature: Array = []
var _hud_resident_directory_cache: Dictionary = {}
var _hud_place_directory_static_items: Array[Dictionary] = []
var _hud_place_directory_static_loaded := false
var _hud_place_directory_signature: Array = []
var _hud_place_directory_cache: Dictionary = {}
var _avatar_poll_signature: Dictionary = {}
var _avatar_perception_revision_pending := -1
var _resident_portrait_by_id: Dictionary = {}
var _resident_portrait_ref_by_id: Dictionary = {}
var _resident_portraits_loaded := false
var _resident_view_phase := "running"
# A1 探针:仅 AI_TOWN_UI_FRAME_PROBE=1 时加载,关闭时保持 null、零开销。
var _frame_probe: GDScript = null


func _ready() -> void:
	if OS.get_environment("AI_TOWN_UI_FRAME_PROBE") == "1":
		_frame_probe = load("res://world/presentation/ui/TownUiFrameProbe.gd")


func _process(delta: float) -> void:
	_advance_world_refresh_queue()
	if _conversation_wait_started_msec > 0:
		_refresh_gateway_network_state()
		_expire_conversation_wait_if_needed()
	_anchor_refresh_elapsed += delta
	if _anchor_refresh_elapsed >= 0.1:
		_anchor_refresh_elapsed = 0.0
		var runtime_state: Dictionary = {}
		if _runtime != null and _runtime.has_method("get_ui_poll_state"):
			runtime_state = _runtime.call("get_ui_poll_state") as Dictionary
		elif _runtime != null and _runtime.has_method("get_runtime_state"):
			runtime_state = _runtime.call("get_runtime_state") as Dictionary
		var paused: bool = bool(
			runtime_state.get(
				"paused",
				(runtime_state.get("lifecycle", {}) as Dictionary).get(
					"paused",
					false,
				),
			)
		)
		var pause_state_changed := _sync_hud_pause_state(paused)
		var conversation_bubbles_changed := bool(
			false
			if paused
			else _hud_conversation_bubble_playback.advance(
				_hud_effective_now_msec()
			)
		)
		var social_matter_changed := _sync_hud_social_matter_activity()
		var public_thoughts_changed := (
			false if paused else _prune_hud_public_thoughts()
		)
		var camera_zoom_band := String(
			runtime_state.get("cameraZoomBand", "")
		)
		var camera_zoom_changed := (
			not camera_zoom_band.is_empty()
			and camera_zoom_band != _hud_last_camera_zoom_band
		)
		if not camera_zoom_band.is_empty():
			_hud_last_camera_zoom_band = camera_zoom_band
		var avatar_mode := String(
			runtime_state.get("avatarMode", "observer")
		)
		if avatar_mode in ["avatar_descent", "avatar_active"]:
			var avatar_signature := _current_avatar_poll_signature(
				avatar_mode,
			)
			if avatar_signature != _avatar_poll_signature:
				_avatar_poll_signature = avatar_signature
				_refresh_scope("avatar")
		else:
			_avatar_poll_signature.clear()
		if _spectator_panel_open or not _active_conversation_id().is_empty():
			_refresh_scope("conversation")
		if conversation_bubbles_changed:
			# 尾泡播完后 playback 状态已 erase，但 HUD 快照里的条目只有
			# capture 重跑才会回收；否则旧气泡带着最后一句永远重画
			# （室外靠其它对话信号偶然自愈，安静/室内场景就永久卡住）。
			_capture_current_hud_far_conversations()
		if (
			social_matter_changed
			or public_thoughts_changed
			or camera_zoom_changed
			or pause_state_changed
			or conversation_bubbles_changed
		):
			_refresh_scope("town_hud", true)


func _current_avatar_poll_signature(avatar_mode: String) -> Dictionary:
	var avatar: Dictionary = {}
	if _world != null and _world.has_method("get_player_avatar_state"):
		avatar = _world.get_player_avatar_state() as Dictionary
	var conversation_id := String(avatar.get("conversationId", ""))
	if conversation_id.is_empty() and avatar.get("conversation") is Dictionary:
		conversation_id = String(
			(avatar.get("conversation") as Dictionary).get(
				"conversation_id",
				"",
			)
		)
	return {
		"mode": avatar_mode,
		"place": String(avatar.get("currentPlace", "")),
		"spaceId": String(avatar.get("spaceId", "")),
		"regionId": String(avatar.get("regionId", "")),
		"nearby": (avatar.get("nearby", []) as Array).duplicate(),
		"conversationId": conversation_id,
	}


func _queue_world_scope_refresh(scope: String) -> void:
	if WORLD_SCOPES.has(scope):
		_dirty_world_scopes[scope] = true
	if not _pending_world_refresh_scopes.has(scope):
		_pending_world_refresh_scopes.append(scope)
	_world_refresh_wait_frames = maxi(_world_refresh_wait_frames, 1)


func _advance_world_refresh_queue() -> void:
	if _world_refresh_wait_frames > 0:
		_world_refresh_wait_frames -= 1
		return
	if _pending_world_refresh_scopes.is_empty():
		return
	# 世界高频变化（化身移动、居民走动）会以 10Hz 反复标脏同一批 scope。
	# 每个 scope 的重建都要全量取数+深拷贝+同步通知页面，帧尖峰就是这么来的。
	# 同一 scope 两次重建之间保持最小间隔；静默期后的第一次刷新不延迟，
	# 所以单次交互（暂停、开面板）的响应不受影响。
	var now_msec := Time.get_ticks_msec()
	for index: int in _pending_world_refresh_scopes.size():
		var scope: String = _pending_world_refresh_scopes[index]
		var last_msec := int(_world_scope_refreshed_msec.get(
			scope,
			-WORLD_SCOPE_REFRESH_MIN_INTERVAL_MSEC,
		))
		if now_msec - last_msec < WORLD_SCOPE_REFRESH_MIN_INTERVAL_MSEC:
			continue
		_pending_world_refresh_scopes.remove_at(index)
		_refresh_scope(scope)
		return


func bind_runtime(runtime: Node, world: RefCounted, gateway: Node, session_config: Dictionary = {}) -> void:
	_disconnect_runtime_signals()
	_disconnect_world()
	_runtime = runtime
	_runtime_head_anchor_call = (
		Callable(runtime, "get_resident_head_screen_anchor")
		if runtime != null and runtime.has_method("get_resident_head_screen_anchor")
		else Callable()
	)
	_world = world
	_gateway = gateway
	_session_config = session_config.duplicate(true)
	_resident_portrait_by_id.clear()
	_resident_portrait_ref_by_id.clear()
	_resident_portraits_loaded = false
	_dirty_world_scopes.clear()
	_pending_world_refresh_scopes.clear()
	_world_refresh_wait_frames = 0
	_world_scope_refreshed_msec.clear()
	_resident_view_phase = "running"
	_spectator_selected_conversation_id = ""
	_spectator_panel_open = false
	_pending_player_ended_conversation.clear()
	_local_player_close_conversation_id = ""
	_connect_runtime_signals()
	_clear_hud_far_resident_activity(true)
	_hud_conversation_bubble_playback.clear()
	_clear_hud_public_thoughts()
	_reset_hud_social_matter_activity()
	_hud_playback_times.clear()
	_town_hud_last_stable_projection = {}
	_hud_overlay_missing_state_count = 0
	_hud_last_camera_zoom_band = ""
	_hud_pause_started_msec = 0
	_hud_resident_directory_signature.clear()
	_hud_resident_directory_cache.clear()
	_hud_place_directory_static_items.clear()
	_hud_place_directory_static_loaded = false
	_hud_place_directory_signature.clear()
	_hud_place_directory_cache.clear()
	_avatar_poll_signature.clear()
	_avatar_perception_revision_pending = -1
	_refresh_resident_identities()
	_capture_current_hud_far_conversations()
	_gateway_error_sequence = _latest_gateway_error_sequence(_gateway_errors())
	_conversation_wait_conversation_id = ""
	_conversation_wait_resident_id = ""
	_conversation_wait_decision_id = ""
	if _world != null and _world.has_signal("world_revision_changed"):
		var revision_callable := Callable(self, "_on_world_revision_changed")
		if not _world.is_connected("world_revision_changed", revision_callable):
			_world.connect("world_revision_changed", revision_callable)
	if _world != null and _world.has_signal("conversation_changed"):
		var conversation_callable := Callable(self, "_on_conversation_changed")
		if not _world.is_connected("conversation_changed", conversation_callable):
			_world.connect("conversation_changed", conversation_callable)
	if _world != null and _world.has_signal("simulation_speed_changed"):
		var speed_callable := Callable(self, "_on_simulation_speed_changed")
		if not _world.is_connected("simulation_speed_changed", speed_callable):
			_world.connect("simulation_speed_changed", speed_callable)
	if _world != null and _world.has_signal("player_avatar_perception_changed"):
		var perception_callable := _on_player_avatar_perception_changed
		if not _world.is_connected("player_avatar_perception_changed", perception_callable):
			_world.connect("player_avatar_perception_changed", perception_callable)
	_connect_hud_activity_signals()
	_refresh_all(true)
	set_process(true)


func get_town_hud_resident_head_anchor(resident_id: String) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	var resident_name := _resident_name_for_id(normalized_id)
	if (
		normalized_id.is_empty()
		or resident_name.is_empty()
		or not _runtime_head_anchor_call.is_valid()
	):
		return _town_hud_head_anchor_unavailable()
	var anchor := _runtime_head_anchor_call.call(resident_name) as Dictionary
	if (
		not bool(anchor.get("valid", false))
		or String(anchor.get("kind", "")) != "head"
		or String(anchor.get("coordinateSpace", ""))
		!= "viewport_logical"
	):
		return _town_hud_head_anchor_unavailable()
	return {
		"valid": true,
		"visible": bool(anchor.get("visible", true)),
		"kind": "head",
		"coordinateSpace": "viewport_logical",
		"x": float(anchor.get("x", 0.0)),
		"y": float(anchor.get("y", 0.0)),
		"spaceId": String(anchor.get("spaceId", "")),
	}


func _town_hud_head_anchor_unavailable() -> Dictionary:
	return {
		"valid": false,
		"visible": false,
		"kind": "head",
		"coordinateSpace": "viewport_logical",
		"x": 0.0,
		"y": 0.0,
		"spaceId": "",
	}


func update_session_resident_bindings(bindings: Array) -> Dictionary:
	_session_config["residentBindings"] = bindings.duplicate(true)
	_refresh_scope("pause_menu", true)
	return _success_result()


func update_session_resident_roster(
	identities: Array,
	bindings: Array,
	opening_config: Dictionary,
) -> Dictionary:
	_session_config["residentIdentities"] = identities.duplicate(true)
	_session_config["residentBindings"] = bindings.duplicate(true)
	_session_config["openingConfig"] = opening_config.duplicate(true)
	_resident_portrait_by_id.clear()
	_resident_portrait_ref_by_id.clear()
	_resident_portraits_loaded = false
	_refresh_resident_identities()
	_refresh_all(true)
	return _success_result()


func bind_session_save_service(service: Object) -> Dictionary:
	if service == null:
		_session_save_service = null
		_refresh_save_scopes()
		return _success_result()
	var missing_methods: Array[String] = []
	for method in ["create_save", "get_save_snapshot"]:
		if not service.has_method(method):
			missing_methods.append(method)
	if not missing_methods.is_empty():
		return _local_failure(
			"SESSION_SAVE_SERVICE_CONTRACT_INVALID",
			false,
			"Session save service 缺少公共方法：%s" % ", ".join(missing_methods),
		)
	_session_save_service = service
	_refresh_save_scopes()
	return _success_result()


func bind_ui_route_host(host: Object) -> Dictionary:
	if host == null:
		_ui_route_host = null
		_refresh_scope("town_hud", true)
		return _success_result()
	if not host.has_method("open_page"):
		return _local_failure("TOWN_UI_ROUTE_HOST_CONTRACT_INVALID", false)
	_ui_route_host = host
	_refresh_scope("town_hud", true)
	return _success_result()


func open_ui_page(scope: String, context: Dictionary = {}) -> Dictionary:
	var route: String = String({
		"announcements": "bulletin_board",
		"resident_action_menu": "resident_action_menu",
		"resident_overview": "resident_management",
		"resident_detail": "resident_detail",
		"inner_observation": "inner_observation",
		"place_focus": "place_focus",
	}.get(scope, ""))
	if route.is_empty():
		return _local_failure("TOWN_UI_ROUTE_SCOPE_UNKNOWN", false)
	if _ui_route_host == null or not _ui_route_host.has_method("open_page"):
		return _local_failure("TOWN_UI_ROUTE_HOST_NOT_BOUND", false)
	return _ui_route_host.call("open_page", StringName(route), context.duplicate(true)) as Dictionary


func dismiss_resident_action_menu() -> bool:
	if _ui_route_host == null:
		return true
	if (
		_ui_route_host.has_method("current_route")
		and StringName(_ui_route_host.call("current_route"))
		!= &"resident_action_menu"
	):
		return true
	if not _ui_route_host.has_method("request_back"):
		return false
	return bool(_ui_route_host.call("request_back"))


func attach_world_resident_action_menu(
	menu: Control,
	context: Dictionary,
) -> Dictionary:
	if _runtime == null or not _runtime.has_method(
		"attach_world_resident_action_menu"
	):
		return _local_failure(
			"RESIDENT_WORLD_MENU_HOST_UNAVAILABLE",
			false,
		)
	return _runtime.call(
		"attach_world_resident_action_menu",
		menu,
		context.duplicate(true),
	) as Dictionary


func begin_resident_view() -> Dictionary:
	_resident_view_phase = "resident_view"
	_refresh_scope("lifecycle", true)
	return _success_result()


func transition_resident_view_to_inner_observation() -> Dictionary:
	if _resident_view_phase == "running":
		return _local_failure("RESIDENT_VIEW_NOT_ACTIVE", false)
	_resident_view_phase = "inner_observation"
	_refresh_scope("lifecycle", true)
	return _success_result()


func transition_inner_observation_to_resident_view() -> Dictionary:
	if _resident_view_phase != "inner_observation":
		return _local_failure("INNER_OBSERVATION_VIEW_NOT_ACTIVE", false)
	_resident_view_phase = "resident_view"
	_refresh_scope("lifecycle", true)
	return _success_result()


func end_resident_view() -> Dictionary:
	_resident_view_phase = "running"
	if _runtime != null and _runtime.has_method("clear_resident_selection"):
		_runtime.call("clear_resident_selection")
	_refresh_scope("lifecycle", true)
	return _success_result()


func bind_audio_display_settings_service(service: Object) -> Dictionary:
	return _bind_external_ui_service(
		"audio_display_settings",
		service,
		"_audio_display_settings_service",
	)


func bind_provider_settings_service(service: Object) -> Dictionary:
	return _bind_external_ui_service(
		"provider_settings",
		service,
		"_provider_settings_service",
	)


func reveal_provider_api_key(provider_id: String) -> Dictionary:
	if (
		_provider_settings_service == null
		or not _provider_settings_service.has_method(
			"reveal_saved_api_key"
		)
	):
		return _local_failure(
			"PROVIDER_SETTINGS_SERVICE_NOT_BOUND",
			false,
		)
	return _provider_settings_service.call(
		"reveal_saved_api_key",
		provider_id,
	) as Dictionary


func bind_custom_resident_creator_service(service: Object) -> Dictionary:
	return _bind_external_ui_service(
		"custom_resident_creator",
		service,
		"_custom_resident_creator_service",
	)


func bind_resident_editor_service(service: Object) -> Dictionary:
	return _bind_external_ui_service(
		"resident_editor",
		service,
		"_resident_editor_service",
	)


func set_custom_resident_creator_route_capabilities(
	capabilities: Dictionary,
) -> Dictionary:
	_custom_resident_creator_wardrobe_route_available = bool(
		capabilities.get("wardrobe", false),
	)
	_refresh_scope("custom_resident_creator", true)
	return _success_result()


func bind_resident_model_assignment_service(service: Object) -> Dictionary:
	_resident_model_assignment_startup_state.clear()
	var result := _bind_external_ui_service(
		"resident_model_assignment",
		service,
		"_resident_model_assignment_service",
	)
	_refresh_scope("pause_menu", true)
	return result


func set_resident_model_assignment_startup_state(
	status: String,
	result: Dictionary = {},
) -> Dictionary:
	var normalized_status := status.strip_edges().to_lower()
	if normalized_status in ["", "idle"]:
		_resident_model_assignment_startup_state.clear()
		_refresh_scope("resident_model_assignment", true)
		return _success_result()
	if normalized_status not in ["loading", "rejected", "error"]:
		return _local_failure(
			"RESIDENT_MODEL_ASSIGNMENT_STARTUP_STATUS_INVALID",
			false,
		)
	var error_code := String(
		result.get("errorCode", "RESIDENT_MODEL_ASSIGNMENT_START_FAILED")
	)
	var request_id := String(
		result.get("requestId", "resident-model-start-%d" % Time.get_ticks_msec())
	)
	_resident_model_assignment_startup_state = {
		"status": normalized_status,
		"operation": {
			"requestId": request_id,
			"intent": "session.new_game",
			"status": normalized_status,
			"submittedAtMsec": int(
				result.get("submittedAtMsec", Time.get_ticks_msec())
			),
			"completedAtMsec": (
				0
				if normalized_status == "loading"
				else int(result.get("completedAtMsec", Time.get_ticks_msec()))
			),
		},
		"error": (
			null
			if normalized_status == "loading"
			else {
				"kind": "transport" if bool(result.get("retryable", false)) else "rejected",
				"code": error_code,
				"message": String(result.get("message", error_code)),
				"retryable": bool(result.get("retryable", false)),
				"details": (result.get("errors", []) as Array).duplicate(true),
			}
		),
	}
	_refresh_scope("resident_model_assignment", true)
	return _success_result()


func bind_page_projection_service(service: Object) -> Dictionary:
	_disconnect_external_ui_service(_page_projection_service)
	if service == null:
		_page_projection_service = null
		for scope in [
			"announcements",
			"weather_control",
			"resident_action_menu",
			"resident_overview",
			"resident_detail",
			"inner_observation",
			"place_focus",
			"indoor",
			"town_log",
			"wardrobe",
		]:
			_refresh_scope(scope, true)
		return _success_result()
	for method in ["get_view_model", "dispatch", "set_page_context"]:
		if not service.has_method(method):
			return _local_failure("TOWN_UI_PAGE_SERVICE_CONTRACT_INVALID", false)
	_page_projection_service = service
	if service.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_external_ui_view_model_changed")
		if not service.is_connected("view_model_changed", callback):
			service.connect("view_model_changed", callback)
	if service.has_signal("operation_completed"):
		var operation_callback := Callable(self, "_on_external_ui_operation_completed")
		if not service.is_connected("operation_completed", operation_callback):
			service.connect("operation_completed", operation_callback)
	for scope in [
		"announcements",
		"weather_control",
		"resident_action_menu",
		"resident_overview",
		"resident_detail",
		"inner_observation",
		"place_focus",
		"indoor",
		"town_log",
		"wardrobe",
	]:
		_refresh_scope(scope, true)
	return _success_result()


func set_page_context(scope: String, context: Dictionary) -> Dictionary:
	if _page_projection_service == null:
		return _local_failure("TOWN_UI_PAGE_SERVICE_NOT_BOUND", false)
	return _page_projection_service.call(
		"set_page_context",
		scope,
		context.duplicate(true),
	) as Dictionary


func unbind_runtime() -> void:
	_disconnect_runtime_signals()
	_disconnect_world()
	_runtime = null
	_runtime_head_anchor_call = Callable()
	_world = null
	_gateway = null
	_session_save_service = null
	_ui_route_host = null
	_disconnect_external_ui_service(_audio_display_settings_service)
	_disconnect_external_ui_service(_provider_settings_service)
	_disconnect_external_ui_service(_custom_resident_creator_service)
	_disconnect_external_ui_service(_resident_editor_service)
	_disconnect_external_ui_service(_resident_model_assignment_service)
	_disconnect_external_ui_service(_page_projection_service)
	_audio_display_settings_service = null
	_provider_settings_service = null
	_custom_resident_creator_service = null
	_custom_resident_creator_wardrobe_route_available = false
	_resident_editor_service = null
	_resident_model_assignment_service = null
	_page_projection_service = null
	_session_config.clear()
	_resident_view_phase = "running"
	_view_models.clear()
	_dirty_world_scopes.clear()
	_pending_world_refresh_scopes.clear()
	_world_refresh_wait_frames = 0
	_world_revision = -1
	_gateway_error_sequence = 0
	_conversation_wait_started_msec = 0
	_conversation_wait_conversation_id = ""
	_conversation_wait_resident_id = ""
	_conversation_wait_decision_id = ""
	_conversation_network_error.clear()
	_pending_player_ended_conversation.clear()
	_local_player_close_conversation_id = ""
	_anchor_refresh_elapsed = 0.0
	_resident_id_by_name.clear()
	_resident_name_by_id.clear()
	_resident_identity_status = "unavailable"
	_focused_nearby_resident_id = ""
	_focused_nearby_target_manual = false
	_avatar_target_revision = 0
	_avatar_attack_sequence = 0
	_spectator_selected_conversation_id = ""
	_spectator_panel_open = false
	_clear_hud_far_resident_activity(true)
	_hud_conversation_bubble_playback.clear()
	_clear_hud_public_thoughts()
	_reset_hud_social_matter_activity()
	_hud_playback_times.clear()
	_town_hud_last_stable_projection = {}
	_hud_overlay_missing_state_count = 0
	_hud_last_camera_zoom_band = ""
	_hud_pause_started_msec = 0
	_hud_resident_directory_signature.clear()
	_hud_resident_directory_cache.clear()
	_hud_place_directory_static_items.clear()
	_hud_place_directory_static_loaded = false
	_hud_place_directory_signature.clear()
	_hud_place_directory_cache.clear()
	_avatar_poll_signature.clear()
	set_process(false)


func get_view_model(scope: String) -> Dictionary:
	if not ALL_SCOPES.has(scope):
		return _base_view_model(
			scope,
			"error",
			0,
			{},
			{},
			_idle_operation(),
			_error_payload("UNKNOWN_UI_SCOPE", false, "未知 UI scope。")
		)
	if not _view_models.has(scope) or _dirty_world_scopes.has(scope):
		# 拉取方靠返回值取数；广播只在内容真实变化时发生（_set_view_model 比较判定）。
		_refresh_scope(scope, false)
	return (_view_models.get(scope, {}) as Dictionary).duplicate(true)


func get_all_view_models() -> Dictionary:
	var result: Dictionary = {}
	for scope in ALL_SCOPES:
		result[scope] = get_view_model(scope)
	return result


func prepare_conversation_photo(path: String) -> Dictionary:
	if _spectator_panel_open:
		return _local_failure("SPECTATOR_READ_ONLY", false)
	var resident_id := _active_conversation_resident_id()
	if resident_id.is_empty():
		return _local_failure("CONVERSATION_NOT_ACTIVE", false)
	if (
		_gateway == null
		or not _gateway.has_method("stage_conversation_photo")
		or not _gateway.has_method("can_attach_photo_for_resident")
	):
		return _local_failure("PHOTO_INTERFACE_MISSING", false)
	if not bool(_gateway.call(
		"can_attach_photo_for_resident",
		resident_id,
	)):
		return _local_failure("PHOTO_CAPABILITY_UNAVAILABLE", false)
	var result := _gateway.call(
		"stage_conversation_photo",
		resident_id,
		path,
	) as Dictionary
	result = result.duplicate(true)
	result["residentId"] = resident_id
	result["retryable"] = false
	result["worldRevision"] = _read_world_revision()
	return result


func discard_conversation_photo(ref: String, resident_id: String) -> bool:
	if (
		_gateway == null
		or not _gateway.has_method("discard_staged_conversation_photo")
	):
		return false
	return bool(_gateway.call(
		"discard_staged_conversation_photo",
		resident_id.strip_edges(),
		ref.strip_edges(),
	))


func resolve_conversation_photo_preview(
	ref: String,
	mime_type: String,
) -> Dictionary:
	if (
		_gateway == null
		or not _gateway.has_method("resolve_conversation_photo_preview")
	):
		return _local_failure("PHOTO_INTERFACE_MISSING", false)
	return _gateway.call(
		"resolve_conversation_photo_preview",
		ref,
		mime_type,
	) as Dictionary


func dispatch(intent: String, payload: Dictionary = {}) -> Dictionary:
	var scope := _scope_for_intent(intent)
	var request_id := _next_request_id()
	if scope.is_empty():
		return {
			"ok": false,
			"accepted": false,
			"requestId": request_id,
			"errorCode": "UNKNOWN_UI_INTENT",
			"retryable": false,
		}
	if (
		intent == "custom_resident_creator.open_wardrobe"
		and not _custom_resident_creator_wardrobe_route_available
	):
		return {
			"ok": false,
			"accepted": false,
			"requestId": request_id,
			"errorCode": "CUSTOM_RESIDENT_WARDROBE_ROUTE_UNAVAILABLE",
			"retryable": false,
		}
	var external_service := _external_ui_service(scope)
	if external_service != null:
		return external_service.call(
			"dispatch",
			intent,
			payload.duplicate(true),
		) as Dictionary
	var operation := _operation_payload(request_id, intent, "loading")
	_apply_operation(scope, operation, {})
	var command_result := _execute_intent(intent, payload)
	_complete_operation(scope, operation, command_result)
	return {
		"ok": bool(command_result.get("ok", false)),
		"accepted": true,
		"requestId": request_id,
		"errorCode": str(command_result.get("errorCode", "")),
		"retryable": bool(command_result.get("retryable", false)),
	}


func validate_new_game_draft(draft: Dictionary) -> Dictionary:
	return NEW_GAME_DRAFT.validate(draft)


func _disconnect_world() -> void:
	if _world == null:
		return
	if _world.has_signal("world_revision_changed"):
		var revision_callable := Callable(self, "_on_world_revision_changed")
		if _world.is_connected("world_revision_changed", revision_callable):
			_world.disconnect("world_revision_changed", revision_callable)
	if _world.has_signal("conversation_changed"):
		var conversation_callable := Callable(self, "_on_conversation_changed")
		if _world.is_connected("conversation_changed", conversation_callable):
			_world.disconnect("conversation_changed", conversation_callable)
	if _world.has_signal("simulation_speed_changed"):
		var speed_callable := Callable(self, "_on_simulation_speed_changed")
		if _world.is_connected("simulation_speed_changed", speed_callable):
			_world.disconnect("simulation_speed_changed", speed_callable)
	if _world.has_signal("player_avatar_perception_changed"):
		var perception_callable := _on_player_avatar_perception_changed
		if _world.is_connected("player_avatar_perception_changed", perception_callable):
			_world.disconnect("player_avatar_perception_changed", perception_callable)
	for binding in [
		["lifecycle_state_changed", "_on_adapter_lifecycle_state_changed"],
		["announcement_published", "_on_adapter_announcement_published"],
		["world_restored", "_on_hud_world_restored"],
		["resident_action_phase_changed", "_on_resident_action_phase_changed"],
		["resident_action_started", "_on_hud_resident_action_started"],
		["resident_reaction_created", "_on_hud_resident_reaction_created"],
		["action_result_created", "_on_hud_action_result_created"],
		["resident_activity_completed", "_on_hud_resident_activity_completed"],
		["resident_activity_interrupted", "_on_hud_resident_activity_interrupted"],
		["resident_activity_failed", "_on_hud_resident_activity_failed"],
	]:
		var signal_name := String(binding[0])
		var callback := Callable(self, String(binding[1]))
		if _world.has_signal(signal_name) and _world.is_connected(signal_name, callback):
			_world.disconnect(signal_name, callback)


func _connect_runtime_signals() -> void:
	if _runtime == null:
		return
	for binding in [
		["avatar_mode_changed", "_on_runtime_avatar_mode_changed"],
		["observed_place_changed", "_on_runtime_observed_place_changed"],
	]:
		var signal_name := String(binding[0])
		var callback := Callable(self, String(binding[1]))
		if (
			_runtime.has_signal(signal_name)
			and not _runtime.is_connected(signal_name, callback)
		):
			_runtime.connect(signal_name, callback)


func _disconnect_runtime_signals() -> void:
	if _runtime == null:
		return
	for binding in [
		["avatar_mode_changed", "_on_runtime_avatar_mode_changed"],
		["observed_place_changed", "_on_runtime_observed_place_changed"],
	]:
		var signal_name := String(binding[0])
		var callback := Callable(self, String(binding[1]))
		if (
			_runtime.has_signal(signal_name)
			and _runtime.is_connected(signal_name, callback)
		):
			_runtime.disconnect(signal_name, callback)


func _on_runtime_avatar_mode_changed(
	_mode: String,
	_previous_mode: String,
) -> void:
	_refresh_scope("avatar", true)
	_queue_world_scope_refresh("town_hud")
	_queue_world_scope_refresh("pause_menu")


func _on_runtime_observed_place_changed(_result: Dictionary) -> void:
	# Physical portal transitions change the active presentation space after
	# World has already published its place revision. Refresh the runtime-owned
	# UI scopes again from the completed visual state.
	_refresh_scope("avatar", true)
	_queue_world_scope_refresh("town_hud")


func _connect_hud_activity_signals() -> void:
	if _world == null:
		return
	for binding in [
		["lifecycle_state_changed", "_on_adapter_lifecycle_state_changed"],
		["announcement_published", "_on_adapter_announcement_published"],
		["world_restored", "_on_hud_world_restored"],
		["resident_action_phase_changed", "_on_resident_action_phase_changed"],
		["resident_action_started", "_on_hud_resident_action_started"],
		["resident_reaction_created", "_on_hud_resident_reaction_created"],
		["action_result_created", "_on_hud_action_result_created"],
		["resident_activity_completed", "_on_hud_resident_activity_completed"],
		["resident_activity_interrupted", "_on_hud_resident_activity_interrupted"],
		["resident_activity_failed", "_on_hud_resident_activity_failed"],
	]:
		var signal_name := String(binding[0])
		var callback := Callable(self, String(binding[1]))
		if _world.has_signal(signal_name) and not _world.is_connected(signal_name, callback):
			_world.connect(signal_name, callback)


func _on_adapter_lifecycle_state_changed(_state: Dictionary) -> void:
	_world_revision = maxi(_world_revision, _read_world_revision())
	_refresh_scope("lifecycle", true)
	_queue_world_scope_refresh("town_hud")


func _on_adapter_announcement_published(_announcement: Dictionary) -> void:
	_world_revision = maxi(_world_revision, _read_world_revision())
	_refresh_scope("announcements", true)
	_queue_world_scope_refresh("town_hud")


func _on_world_revision_changed(revision: int) -> void:
	if revision < _world_revision:
		return
	_world_revision = revision
	if (
		_avatar_perception_revision_pending >= 0
		and revision <= _avatar_perception_revision_pending
	):
		# A pure avatar-position perception update already rebuilt the avatar
		# target cards above. It must not fan out into the expensive town HUD
		# projection; minute/world changes carry a different source and still use
		# the normal all-scope invalidation below.
		_avatar_perception_revision_pending = -1
		_dirty_world_scopes.erase("avatar")
		_pending_world_refresh_scopes.erase("avatar")
		return
	_avatar_perception_revision_pending = -1
	for scope in WORLD_SCOPES:
		_dirty_world_scopes[scope] = true
	# A game-minute tick may update many residents at once. Keep that work out
	# of the World signal call stack and spread the visible UI scopes over
	# following frames.
	_queue_world_scope_refresh("environment")
	_queue_world_scope_refresh("town_hud")


func _on_player_avatar_perception_changed(change: Dictionary) -> void:
	if String(change.get("source", "")) != "avatar_position":
		return
	_refresh_scope("avatar", true)
	if bool(change.get("semanticStateChanged", false)):
		return
	_world_revision = maxi(_world_revision, _read_world_revision())
	_avatar_perception_revision_pending = _world_revision


func _on_conversation_changed(
	conversation_id: String,
	state: Dictionary,
) -> void:
	var authoritative_revision := _read_world_revision()
	if (
		authoritative_revision < _world_revision
		and String(state.get("status", "")) != "ended"
	):
		# ended 是该对话的最后一条状态，被 revision 守卫丢弃后 playback
		# 永远学不到结束，尾泡会永久滞留；结束事件必须豁免且可重复自愈。
		return
	_world_revision = maxi(_world_revision, authoritative_revision)
	_capture_player_conversation_end(conversation_id, state)
	_hud_conversation_bubble_playback.ingest(
		state,
		_hud_effective_now_msec(),
	)
	_capture_current_hud_far_conversations()
	_refresh_scope("conversation", true)
	# The conversation page now owns the visible frame. Preserve the HUD bubble
	# state above, then rebuild the covered Town HUD through the existing
	# frame-spread queue instead of extending the click's synchronous call stack.
	_queue_world_scope_refresh("town_hud")


func _capture_player_conversation_end(
	conversation_id: String,
	state: Dictionary,
) -> void:
	if _world == null or not _world.has_method("get_player_avatar_state"):
		return
	var avatar := _world.get_player_avatar_state() as Dictionary
	var player_id := str(
		avatar.get("residentId", DEFAULT_PLAYER_AVATAR_ID)
	).strip_edges()
	var participants := state.get("participants", []) as Array
	if player_id.is_empty() or not participants.has(player_id):
		return
	if str(state.get("status", "")) != "ended":
		if (
			str(_pending_player_ended_conversation.get("conversationId", ""))
			== conversation_id
		):
			_pending_player_ended_conversation.clear()
		return
	if conversation_id == _local_player_close_conversation_id:
		_pending_player_ended_conversation.clear()
		return
	_pending_player_ended_conversation = state.duplicate(true)


func _on_simulation_speed_changed(_speed: int, world_revision: int) -> void:
	if world_revision < _world_revision:
		return
	_world_revision = world_revision
	_queue_world_scope_refresh("town_hud")


func _on_resident_action_phase_changed(
	_resident_id: String,
	phase: Dictionary,
) -> void:
	var phase_revision := int(phase.get("worldRevision", _read_world_revision()))
	if phase_revision < _world_revision:
		return
	_world_revision = maxi(_world_revision, phase_revision)
	_queue_world_scope_refresh("town_hud")


func _on_hud_world_restored(_summary: Dictionary) -> void:
	_clear_hud_far_resident_activity(true)
	_hud_conversation_bubble_playback.clear()
	_clear_hud_public_thoughts()
	_reset_hud_social_matter_activity()
	_hud_far_confirmed_revision = _read_world_revision()
	_refresh_scope("town_hud", true)


func _on_hud_resident_action_started(
	_resident_name: String,
	_action: Dictionary,
) -> void:
	var confirmed_revision := _read_world_revision()
	if confirmed_revision < _world_revision:
		return
	# Ordinary action lines already have a persistent activity semantic. Head
	# bubbles belong to the World's focused preview, explicit social surfaces,
	# conversations and completion reactions; replaying every action here made
	# residents flash and extended a focused preview for another 2.5 seconds.
	_queue_world_scope_refresh("town_hud")


func _on_hud_resident_reaction_created(
	resident_name: String,
	reaction: Dictionary,
) -> void:
	var confirmed_revision := int(
		reaction.get("worldRevision", _read_world_revision())
	)
	if confirmed_revision < _world_revision:
		return
	var resident_id := String(
		reaction.get("residentId", "")
	).strip_edges()
	if resident_id.is_empty():
		resident_id = _resident_id_for_name(resident_name)
	var reaction_id := String(
		reaction.get("reactionId", "")
	).strip_edges()
	var source_action_id := String(
		reaction.get("sourceActionId", "")
	).strip_edges()
	var source_event_id := String(
		reaction.get("sourceEventId", "")
	).strip_edges()
	var reaction_kind := String(
		reaction.get("reactionKind", "action_result"),
	).strip_edges()
	var announcement_id := String(
		reaction.get("announcementId", ""),
	).strip_edges()
	var source_id := source_event_id if not source_event_id.is_empty() else source_action_id
	var public_thought := _hud_public_thought_text(
		String(reaction.get("text", ""))
	)
	if (
		resident_id.is_empty()
		or reaction_id.is_empty()
		or source_id.is_empty()
		or public_thought.is_empty()
	):
		return
	var snapshot_key := "%s:%s" % [resident_id, reaction_id]
	if _hud_public_thoughts.has(snapshot_key):
		return
	var now_msec := _hud_effective_now_msec()
	var head_anchor := get_town_hud_resident_head_anchor(resident_id)
	if not bool(head_anchor.get("valid", false)):
		return
	_hud_public_thoughts[snapshot_key] = {
		"previewId": reaction_id,
		"actionId": source_id,
		"residentId": resident_id,
		"residentName": resident_name,
		"publicThought": public_thought,
		"thoughtKind": (
			"announcement_reaction"
			if reaction_kind == "announcement"
			else "activity_reaction"
		),
		"announcementId": announcement_id,
		"confirmedRevision": confirmed_revision,
		"startedAtMsec": now_msec,
		"expiresAtMsec": (
			now_msec + HUD_ACTIVITY_REACTION_LIFETIME_MSEC
		),
	}
	_hud_public_thought_order.erase(snapshot_key)
	_hud_public_thought_order.push_front(snapshot_key)
	_world_revision = maxi(_world_revision, confirmed_revision)
	_queue_world_scope_refresh("town_hud")


func _on_hud_resident_activity_completed(
	resident_id: String,
	event: Dictionary,
) -> void:
	_capture_hud_resident_activity_result(resident_id, event, "completed")


func _on_hud_resident_activity_interrupted(
	resident_id: String,
	event: Dictionary,
) -> void:
	_capture_hud_resident_activity_result(resident_id, event, "interrupted")


func _on_hud_resident_activity_failed(
	resident_id: String,
	event: Dictionary,
) -> void:
	_capture_hud_resident_activity_result(resident_id, event, "failed")


func _on_hud_action_result_created(
	resident_name: String,
	result: Dictionary,
) -> void:
	var base_icon_key := String(result.get("baseIconKey", "")).strip_edges()
	if base_icon_key.is_empty():
		return
	var resident_id := String(result.get("residentId", "")).strip_edges()
	if resident_id.is_empty():
		resident_id = _resident_id_for_name(resident_name)
	var phase := String(result.get("phase", "failed")).strip_edges()
	if phase not in ["completed", "interrupted", "failed"]:
		phase = "failed"
	var result_label := _hud_action_display_label(
		String(result.get("label", "")),
		phase,
	)
	var reason := String(result.get("reason", "")).strip_edges()
	if not reason.is_empty():
		result_label = (
			"%s：%s" % [result_label, reason]
			if not result_label.is_empty()
			else reason
		)
	_capture_hud_resident_activity_result(
		resident_id,
		{
			"baseIconKey": base_icon_key,
			"sourceActionId": String(result.get("action_id", "")),
			"activityId": String(result.get("sourceActivityId", "")),
			"label": String(result.get("label", "")),
			"result": result_label,
		},
		phase,
	)


func _capture_hud_resident_activity_result(
	resident_id: String,
	event: Dictionary,
	phase: String,
) -> void:
	var base_icon_key := String(event.get("baseIconKey", "")).strip_edges()
	if resident_id.is_empty() or base_icon_key.is_empty():
		return
	var now_msec := _hud_effective_now_msec()
	var source_action_id := String(
		event.get("sourceActionId", event.get("activityId", ""))
	).strip_edges()
	var snapshot_key := "activity-result:%s:%s:%s:%d" % [
		resident_id,
		source_action_id,
		phase,
		_read_world_revision(),
	]
	_hud_public_thoughts[snapshot_key] = {
		"previewId": snapshot_key,
		"actionId": source_action_id,
		"residentId": resident_id,
		"residentName": _resident_name_for_id(resident_id),
		"publicThought": "",
		"thoughtKind": "activity_result",
		"semanticIconType": base_icon_key,
		"phase": phase,
		"label": String(
			event.get("result", event.get("label", ""))
		).strip_edges(),
		"confirmedRevision": _read_world_revision(),
		"startedAtMsec": now_msec,
		"expiresAtMsec": now_msec + HUD_PUBLIC_THOUGHT_LIFETIME_MSEC,
	}
	_hud_public_thought_order.erase(snapshot_key)
	_hud_public_thought_order.push_front(snapshot_key)
	_queue_world_scope_refresh("town_hud")


func _has_active_hud_activity_reaction(resident_id: String) -> bool:
	var now_msec := _hud_effective_now_msec()
	for value: Variant in _hud_public_thoughts.values():
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var snapshot := value as Dictionary
		if (
			String(snapshot.get("residentId", "")) == resident_id
			and String(snapshot.get("thoughtKind", ""))
				== "activity_reaction"
			and int(snapshot.get("expiresAtMsec", 0)) > now_msec
		):
			return true
	return false


func _has_active_hud_activity_result(resident_id: String) -> bool:
	var now_msec := _hud_effective_now_msec()
	for value: Variant in _hud_public_thoughts.values():
		if not value is Dictionary:
			continue
		var snapshot := value as Dictionary
		if (
			String(snapshot.get("residentId", "")) == resident_id
			and String(snapshot.get("thoughtKind", "")) == "activity_result"
			and int(snapshot.get("expiresAtMsec", 0)) > now_msec
		):
			return true
	return false


func _refresh_all(force_emit := false) -> void:
	_world_revision = _read_world_revision()
	for scope in ALL_SCOPES:
		_refresh_scope(scope, force_emit)


func _refresh_world_scopes() -> void:
	var authoritative_revision := _read_world_revision()
	if authoritative_revision < _world_revision:
		return
	_world_revision = authoritative_revision
	for scope in WORLD_SCOPES:
		_refresh_scope(scope, true)


func _refresh_scope(scope: String, force_emit := false) -> void:
	var probe_refresh_started_usec := (
		Time.get_ticks_usec()
		if _frame_probe != null and scope == "town_hud"
		else 0
	)
	var previous_operation: Dictionary = _idle_operation()
	var previous_error: Dictionary = {}
	if _view_models.has(scope):
		var previous: Dictionary = _view_models[scope]
		previous_operation = (previous.get("operation", _idle_operation()) as Dictionary).duplicate(true)
		var previous_error_variant: Variant = previous.get("error")
		if previous_error_variant is Dictionary:
			previous_error = (previous_error_variant as Dictionary).duplicate(true)
	var view_model: Dictionary
	match scope:
		"lifecycle":
			view_model = _build_lifecycle_view_model(previous_operation, previous_error)
		"environment":
			view_model = _build_environment_view_model(previous_operation, previous_error)
		"avatar":
			view_model = _build_avatar_view_model(previous_operation, previous_error)
		"conversation":
			view_model = _build_conversation_view_model(previous_operation, previous_error)
		"announcements":
			if _page_projection_service != null:
				view_model = _page_projection_service.call("get_view_model", scope) as Dictionary
			else:
				view_model = _build_announcements_view_model(previous_operation, previous_error)
		"town_hud":
			var probe_build_started_usec := (
				Time.get_ticks_usec() if probe_refresh_started_usec > 0 else 0
			)
			view_model = _build_town_hud_view_model(previous_operation, previous_error)
			if probe_build_started_usec > 0:
				_frame_probe.record(
					Engine.get_process_frames(),
					"adapterBuildUsec",
					Time.get_ticks_usec() - probe_build_started_usec,
				)
		"session":
			view_model = _build_session_view_model(previous_operation, previous_error)
		"save":
			view_model = _build_save_view_model(previous_operation, previous_error)
		"pause_menu":
			view_model = _build_pause_menu_view_model(previous_operation, previous_error)
		"audio_display_settings", "provider_settings", "custom_resident_creator", "resident_editor", "resident_model_assignment":
			var service := _external_ui_service(scope)
			if service == null:
				view_model = _external_ui_service_missing_view_model(scope)
			else:
				view_model = service.call("get_view_model") as Dictionary
			if scope == "custom_resident_creator":
				view_model = _apply_custom_resident_creator_route_capabilities(
					view_model,
				)
			elif scope == "resident_model_assignment":
				view_model = _apply_resident_model_assignment_startup_state(
					view_model,
				)
		"weather_control", "resident_action_menu", "resident_overview", "resident_detail", "inner_observation", "place_focus", "indoor", "town_log", "wardrobe":
			if _page_projection_service == null:
				view_model = _external_ui_service_missing_view_model(scope)
			else:
				view_model = _page_projection_service.call("get_view_model", scope) as Dictionary
		_:
			return
	_dirty_world_scopes.erase(scope)
	_pending_world_refresh_scopes.erase(scope)
	if WORLD_SCOPES.has(scope):
		_world_scope_refreshed_msec[scope] = Time.get_ticks_msec()
	_set_view_model(scope, view_model, force_emit)
	if probe_refresh_started_usec > 0:
		_frame_probe.record(
			Engine.get_process_frames(),
			"adapterRefreshInclusiveUsec",
			Time.get_ticks_usec() - probe_refresh_started_usec,
		)


func _build_lifecycle_view_model(operation: Dictionary, error: Dictionary) -> Dictionary:
	var state: Dictionary = {}
	if _world != null and _world.has_method("get_lifecycle_state"):
		state = _world.get_lifecycle_state()
	var status := "ready" if bool(state.get("started", false)) else "disabled"
	return _base_view_model(
		"lifecycle",
		status,
		_world_revision,
		{
			"state": str(state.get("state", "stopped")),
			"started": bool(state.get("started", false)),
			"paused": bool(state.get("paused", false)),
			"pauseReasons": (state.get("pauseReasons", []) as Array).duplicate(),
			"residentViewPhase": _resident_view_phase,
		},
		{
			"pause": _action("lifecycle.pause", bool(state.get("started", false)) and not bool(state.get("paused", false))),
			"resume": _action("lifecycle.resume", bool(state.get("started", false)) and bool(state.get("paused", false))),
		},
		operation,
		error
	)


func _build_environment_view_model(operation: Dictionary, error: Dictionary) -> Dictionary:
	var time: Dictionary = {}
	var weather_id := ""
	if _world != null:
		if _world.has_method("get_time"):
			time = _world.get_time()
		if _world.has_method("get_weather"):
			weather_id = str(_world.get_weather())
	var period_id := str(time.get("period", ""))
	return _base_view_model(
		"environment",
		"ready" if not time.is_empty() else "disabled",
		_world_revision,
		{
			"day": int(time.get("day", 0)),
			"clock": str(time.get("clock", "")),
			"periodId": period_id,
			"periodLabel": period_id,
			"weatherId": weather_id,
			"weatherLabel": weather_id,
			"outdoorTone": weather_id,
		},
		{"weatherChange": _action("environment.weather_change", not time.is_empty())},
		operation,
		error
	)


func _build_avatar_view_model(operation: Dictionary, error: Dictionary) -> Dictionary:
	var avatar: Dictionary = {}
	if _world != null and _world.has_method("get_player_avatar_state"):
		avatar = _world.get_player_avatar_state()
	var runtime_state: Dictionary = {}
	if _runtime != null and _runtime.has_method("get_runtime_state"):
		runtime_state = _runtime.call("get_runtime_state")
	var connected: Dictionary = {}
	for resident_name in _connected_resident_names():
		connected[resident_name] = true
	var avatar_position := _position_vector(avatar.get("position"))
	var nearby_targets: Array[Dictionary] = []
	for resident_name_variant in avatar.get("nearby", []):
		var resident_name := str(resident_name_variant)
		var is_connected := connected.has(resident_name)
		if not is_connected:
			continue
		var resident_id := _resident_id_for_name(resident_name)
		var can_talk := not resident_id.is_empty()
		var resident_position := avatar_position
		if _world != null and _world.has_method("get_resident_state"):
			var resident_state := (
				_world.get_resident_state(resident_name) as Dictionary
			)
			resident_position = _position_vector(
				resident_state.get("position"),
				avatar_position,
			)
		var screen_anchor := get_town_hud_resident_head_anchor(resident_id)
		var portrait_texture := _resident_portrait_texture(resident_id)
		nearby_targets.append({
			"residentId": resident_id,
			"residentName": resident_name,
			"name": resident_name,
			"targetId": _resident_target_id(resident_id),
			"portraitTexture": portrait_texture,
			"portraitRef": _resident_portrait_ref(resident_id),
			"portraitStatus": (
				"ready" if portrait_texture != null else "unavailable"
			),
			"portraitFallbackText": _resident_portrait_fallback(resident_name),
			"screenAnchor": screen_anchor,
			"canTalk": can_talk,
			"disabledReason": "" if can_talk else "RESIDENT_IDENTITY_UNAVAILABLE",
			"_distanceSquared": avatar_position.distance_squared_to(
				resident_position
			),
		})
	nearby_targets.sort_custom(Callable(self, "_avatar_target_before"))
	for target: Dictionary in nearby_targets:
		target.erase("_distanceSquared")
	_synchronize_focused_nearby_target(nearby_targets)
	nearby_targets = _rotate_targets_to_focus(nearby_targets)
	for target_index in nearby_targets.size():
		nearby_targets[target_index]["isFocused"] = target_index == 0
		nearby_targets[target_index]["targetSlot"] = (
			"current" if target_index == 0 else ("next" if target_index == 1 else "nearby")
		)
	var current_target: Dictionary = (
		nearby_targets[0].duplicate(true) if not nearby_targets.is_empty() else {}
	)
	var next_target: Dictionary = (
		nearby_targets[1].duplicate(true) if nearby_targets.size() >= 2 else {}
	)
	var conversation_id := str(avatar.get("conversationId", ""))
	if conversation_id.is_empty() and avatar.get("conversation") is Dictionary:
		conversation_id = str(
			(avatar.get("conversation") as Dictionary).get("conversation_id", "")
		)
	if (
		conversation_id.is_empty()
		and not _pending_player_ended_conversation.is_empty()
	):
		conversation_id = str(
			_pending_player_ended_conversation.get("conversationId", "")
		)
	var has_conversation := not conversation_id.is_empty()
	var current_can_talk := bool(current_target.get("canTalk", false))
	var avatar_id := String(
		avatar.get("residentId", DEFAULT_PLAYER_AVATAR_ID)
	).strip_edges()
	var avatar_in_brawl := _avatar_in_active_brawl(avatar_id)
	current_can_talk = current_can_talk and not avatar_in_brawl
	var can_switch_target := (
		nearby_targets.size() >= 2
		and not has_conversation
		and not avatar_in_brawl
	)
	var mode := String(runtime_state.get("avatarMode", ""))
	if mode.is_empty():
		mode = "avatar_active" if bool(runtime_state.get("playerAvatarEnabled", false)) else "observer"
	var avatar_attack_animation_active := bool(
		runtime_state.get("avatarConflictInputBlocked", false)
	)
	current_can_talk = current_can_talk and not avatar_attack_animation_active
	can_switch_target = can_switch_target and not avatar_attack_animation_active
	var attack_interface_available := (
		_world != null and _world.has_method("submit_avatar_area_attack")
	)
	var can_attack_target := (
		mode == "avatar_active"
		and not has_conversation
		and not avatar_attack_animation_active
		and attack_interface_available
	)
	var attack_disabled_reason := ""
	if mode != "avatar_active":
		attack_disabled_reason = "AVATAR_MODE_NOT_ACTIVE"
	elif has_conversation:
		attack_disabled_reason = "AVATAR_CONVERSATION_ACTIVE"
	elif avatar_attack_animation_active:
		attack_disabled_reason = "AVATAR_ATTACK_ANIMATION_ACTIVE"
	elif not attack_interface_available:
		attack_disabled_reason = "AVATAR_ATTACK_INTERFACE_MISSING"
	var attack_action := _action(
		"avatar.attack_target",
		can_attack_target,
		attack_disabled_reason,
		{"attackKind": "unarmed"},
	)
	var context_targets: Array[Dictionary] = []
	if not current_target.is_empty():
		context_targets.append({
			"targetId": str(current_target.get("targetId", "")),
			"kind": "resident",
			"label": str(current_target.get("residentName", "")),
			"residentId": str(current_target.get("residentId", "")),
			"residentName": str(current_target.get("residentName", "")),
			"portraitRef": str(current_target.get("portraitRef", "")),
			"portraitStatus": str(current_target.get("portraitStatus", "unavailable")),
			"portraitFallbackText": str(current_target.get("portraitFallbackText", "")),
			"screenAnchor": (
				current_target.get("screenAnchor", {}) as Dictionary
			).duplicate(true),
			"primaryAction": _action(
				"conversation.start",
				current_can_talk and not has_conversation,
				(
					"CONVERSATION_ALREADY_OPEN"
					if has_conversation
					else (
						"AVATAR_CONFLICT_ACTIVE"
						if avatar_in_brawl
						else (
							"AVATAR_ATTACK_ANIMATION_ACTIVE"
							if avatar_attack_animation_active
							else str(current_target.get("disabledReason", ""))
						)
					)
				),
			),
			"attackAction": attack_action.duplicate(true),
		})
	var prompt := _avatar_nearby_prompt(nearby_targets, has_conversation)
	return _base_view_model(
		"avatar",
		"ready" if not avatar.is_empty() else "disabled",
		_world_revision,
		{
			"source": str(_session_config.get("source", "runtime")),
			"capabilityMode": str(_session_config.get("capabilityMode", "development")),
			"formalReady": bool(_session_config.get("formalReady", false)),
			"place": str(avatar.get("currentPlace", "")),
			"spaceId": str(avatar.get("spaceId", "")),
			"regionId": str(avatar.get("regionId", "")),
			"position": _position_payload(avatar.get("position")),
			"nearbyTargets": nearby_targets,
			"currentTarget": current_target,
			"nextTarget": next_target,
			"focusedTargetId": str(current_target.get("targetId", "")),
			"targetRevision": _avatar_target_revision,
			"contextTargets": context_targets,
			"prompt": prompt,
			"mode": mode,
			"conversationId": conversation_id,
			"conflictActive": avatar_in_brawl,
			"attackAnimationActive": avatar_attack_animation_active,
			"identityStatus": _resident_identity_status,
		},
		{
			"openConversation": _action(
				"conversation.start",
				current_can_talk and not has_conversation,
				(
					"CONVERSATION_ALREADY_OPEN"
					if has_conversation
					else (
						"AVATAR_CONFLICT_ACTIVE"
						if avatar_in_brawl
						else (
							"AVATAR_ATTACK_ANIMATION_ACTIVE"
							if avatar_attack_animation_active
							else str(current_target.get(
								"disabledReason",
								"NO_CONNECTED_NEARBY_TARGET",
							))
						)
					)
				),
			),
			"focusTarget": _action(
				"avatar.focus_target",
				can_switch_target,
				"AVATAR_CONFLICT_ACTIVE"
				if avatar_in_brawl
				else "AVATAR_ATTACK_ANIMATION_ACTIVE"
				if avatar_attack_animation_active
				else "CONVERSATION_ALREADY_OPEN"
				if has_conversation
				else (
					"NO_NEARBY_TARGET"
					if nearby_targets.is_empty()
					else "NO_ALTERNATE_NEARBY_TARGET"
				),
			),
			"attackTarget": attack_action,
			"exitMode": _action(
				"avatar.exit_mode",
				(
					mode == "avatar_active"
					and not has_conversation
					and not avatar_in_brawl
					and not avatar_attack_animation_active
				),
				(
					"AVATAR_CONVERSATION_ACTIVE"
					if has_conversation
					else "AVATAR_CONFLICT_ACTIVE"
					if avatar_in_brawl
					else "AVATAR_ATTACK_ANIMATION_ACTIVE"
					if avatar_attack_animation_active
					else "AVATAR_MODE_NOT_ACTIVE"
				),
			),
			"retry": _action(
				"avatar.retry",
				false,
				"NO_RETRYABLE_ERROR",
			),
		},
		operation,
		error
	)


func _build_conversation_view_model(operation: Dictionary, error: Dictionary) -> Dictionary:
	var avatar: Dictionary = {}
	if _world != null and _world.has_method("get_player_avatar_state"):
		avatar = _world.get_player_avatar_state()
	var conversation_id := str(avatar.get("conversationId", ""))
	if conversation_id.is_empty() and avatar.get("conversation") is Dictionary:
		conversation_id = str((avatar.get("conversation") as Dictionary).get("conversation_id", ""))
	if not conversation_id.is_empty():
		_spectator_panel_open = false
		if (
			str(_pending_player_ended_conversation.get("conversationId", ""))
			!= conversation_id
		):
			_pending_player_ended_conversation.clear()
		return _build_player_conversation_view_model(
			avatar,
			conversation_id,
			operation,
			error,
		)
	if not _pending_player_ended_conversation.is_empty():
		_spectator_panel_open = false
		return _build_player_conversation_view_model(
			avatar,
			str(
				_pending_player_ended_conversation.get(
					"conversationId",
					"",
				)
			),
			operation,
			error,
			_pending_player_ended_conversation,
		)
	return _build_spectator_conversation_view_model(operation, error)


func _build_player_conversation_view_model(
	avatar: Dictionary,
	conversation_id: String,
	operation: Dictionary,
	error: Dictionary,
	conversation_override: Dictionary = {},
) -> Dictionary:
	var conversation := conversation_override.duplicate(true)
	if (
		conversation.is_empty()
		and not conversation_id.is_empty()
		and _world != null
		and _world.has_method("get_conversation")
	):
		conversation = _world.get_conversation(conversation_id)
	var conversation_ended := str(conversation.get("status", "")) == "ended"
	var messages := _project_conversation_messages(conversation)
	var player_name := str(avatar.get("name", "旅行者")).strip_edges()
	var player_id := str(
		avatar.get("residentId", DEFAULT_PLAYER_AVATAR_ID)
	).strip_edges()
	var waiting_for_value: Variant = conversation.get("waitingFor", "")
	var raw_waiting_for: Array[String] = []
	if waiting_for_value is Array:
		for item in waiting_for_value:
			if not str(item).is_empty():
				raw_waiting_for.append(str(item))
	elif not str(waiting_for_value).is_empty():
		raw_waiting_for.append(str(waiting_for_value))
	var resident_name := _conversation_resident_name(
		conversation,
		player_name,
		player_id,
	)
	var resident_id := _resident_id_for_name(resident_name)
	var waiting_for := _project_conversation_waiting_for(
		raw_waiting_for,
		player_name,
		player_id,
	)
	var waiting_for_resident := (
		not conversation_ended
		and
		not resident_name.is_empty()
		and (
			raw_waiting_for.has(resident_name)
			or (not resident_id.is_empty() and raw_waiting_for.has(resident_id))
		)
	)
	_update_conversation_wait(
		waiting_for_resident,
		resident_id,
		str(conversation.get("conversationId", conversation_id)),
	)
	var effective_error := {} if conversation_ended else error
	if (
		not waiting_for_resident
		and str(effective_error.get("code", "")) in [
			"AGENT_RESPONSE_TIMEOUT",
			"AGENT_DECISION_REQUEST_FAILED",
		]
	):
		effective_error = {}
	if not _conversation_network_error.is_empty():
		effective_error = _conversation_network_error.duplicate(true)
	var status := (
		"disabled"
		if conversation.is_empty()
		else ("loading" if waiting_for_resident else "ready")
	)
	if not effective_error.is_empty():
		status = "error"
	var effective_operation := operation.duplicate(true)
	if waiting_for_resident and effective_error.is_empty():
		if str(effective_operation.get("status", "")) in ["idle", "success"]:
			effective_operation["status"] = "loading"
	elif not effective_error.is_empty() and str(effective_operation.get("status", "")) == "loading":
		effective_operation["status"] = "error"
	elif not waiting_for_resident and str(effective_operation.get("status", "")) == "loading":
		effective_operation["status"] = "success"
		effective_operation["completedAtMsec"] = Time.get_ticks_msec()
	var has_conversation := not conversation.is_empty()
	var can_attach_photo := (
		has_conversation
		and not conversation_ended
		and not resident_id.is_empty()
		and _gateway != null
		and _gateway.has_method("can_attach_photo_for_resident")
		and bool(_gateway.call(
			"can_attach_photo_for_resident",
			resident_id,
		))
	)
	var end_projection := _player_conversation_end_projection(
		conversation,
		player_name,
		player_id,
		resident_name,
		resident_id,
	)
	return _base_view_model(
		"conversation",
		status,
		_world_revision,
		{
			"source": str(_session_config.get("source", "runtime")),
			"capabilityMode": str(_session_config.get("capabilityMode", "development")),
			"formalReady": bool(_session_config.get("formalReady", false)),
			"displayMode": "player",
			"conversationId": conversation_id,
			"residentId": resident_id,
			"residentName": resident_name,
			"portraitRef": _resident_portrait_ref(resident_id),
			"identityStatus": _resident_identity_status,
			"messages": messages,
			"waitingFor": waiting_for,
			"conversationEnded": conversation_ended,
			"endReason": end_projection.get("endReason", ""),
			"endedAt": end_projection.get("endedAt"),
			"endedById": end_projection.get("endedById", ""),
			"endedByName": end_projection.get("endedByName", ""),
			"endNotice": end_projection.get("endNotice", ""),
			"canAttachPhoto": can_attach_photo,
			"photoCapabilityReason": (
				""
				if can_attach_photo
				else "PHOTO_CAPABILITY_UNAVAILABLE"
			),
		},
		{
			"start": _action(
				"conversation.start",
				not has_conversation and not conversation_ended,
			),
			"reply": _action(
				"conversation.reply",
				has_conversation
				and not conversation_ended
				and not waiting_for_resident,
				(
					"CONVERSATION_ENDED"
					if conversation_ended
					else (
						"WAITING_FOR_RESIDENT"
						if waiting_for_resident
						else ""
					)
				),
			),
			"end": _action(
				"conversation.end",
				has_conversation and not conversation_ended,
				"CONVERSATION_ENDED" if conversation_ended else "",
			),
			"reject": _action(
				"conversation.reject",
				has_conversation and not conversation_ended,
				"CONVERSATION_ENDED" if conversation_ended else "",
			),
			"dismissEnded": _action(
				"conversation.dismiss_ended",
				conversation_ended,
				"CONVERSATION_ACTIVE" if not conversation_ended else "",
			),
			"retry": _action(
				"conversation.retry",
				not conversation_ended
				and waiting_for_resident
				and not effective_error.is_empty()
				and bool(effective_error.get("retryable", false)),
				(
					"CONVERSATION_ENDED"
					if conversation_ended
					else "NO_RETRYABLE_ERROR"
				),
			),
		},
		effective_operation,
		effective_error
	)


func _build_spectator_conversation_view_model(
	operation: Dictionary,
	error: Dictionary,
) -> Dictionary:
	var interface_available := _spectator_interface_available()
	var connected: Dictionary = {}
	for resident_name in _connected_resident_names():
		connected[resident_name] = true
	var active_conversations: Array[Dictionary] = []
	if interface_available:
		for value: Variant in _world.get_active_conversations() as Array:
			if not value is Dictionary:
				continue
			var conversation := value as Dictionary
			if not _is_resident_spectator_conversation(conversation):
				continue
			active_conversations.append(
				_spectator_conversation_summary(conversation, connected)
			)
	active_conversations.sort_custom(Callable(self, "_spectator_conversation_before"))

	var selected_conversation := _selected_spectator_conversation(active_conversations)
	var selected_projection: Dictionary = {}
	var messages: Array[Dictionary] = []
	if not selected_conversation.is_empty():
		selected_projection = _spectator_conversation_projection(
			selected_conversation,
			connected,
		)
		messages = _project_conversation_messages(selected_conversation)
	var panel_open := _spectator_panel_open and not selected_projection.is_empty()
	var can_select := false
	for summary in active_conversations:
		if bool(summary.get("canSpectate", false)):
			can_select = true
			break

	var effective_error := error.duplicate(true)
	if not interface_available:
		effective_error = _error_payload(
			"SPECTATOR_INTERFACE_MISSING",
			false,
			"正式居民对话旁观接口尚未接入。",
		)
	var status := "ready" if interface_available else "disabled"
	if not effective_error.is_empty():
		var operation_status := str(operation.get("status", ""))
		status = operation_status if operation_status in ["rejected", "error"] else "disabled"
	var retryable := bool(effective_error.get("retryable", false))
	var data := {
		"source": str(_session_config.get("source", "runtime")),
		"capabilityMode": str(_session_config.get("capabilityMode", "development")),
		"formalReady": interface_available,
		"displayMode": "spectator",
		"conversationId": str(selected_projection.get("conversationId", "")),
		"residentId": "",
		"residentName": "",
		"identityStatus": _resident_identity_status,
		"messages": messages,
		"waitingFor": _conversation_waiting_for(selected_conversation),
		"canAttachPhoto": false,
		"spectator": {
			"panelOpen": panel_open,
			"activeConversations": active_conversations,
			"selectedConversation": selected_projection,
			"observer": {
				"canSpeak": false,
				"disabledReason": "SPECTATOR_READ_ONLY",
			},
			"spectatorNotice": "你正在旁观，无法加入对话",
			"autoFollowLatest": panel_open,
			"newConfirmedTurnCount": 0,
		},
	}
	var rejected_or_error := str(operation.get("status", "")) in ["rejected", "error"]
	if interface_available and rejected_or_error and _view_models.has("conversation"):
		var confirmed_data := (
			(_view_models["conversation"] as Dictionary).get("data", {}) as Dictionary
		)
		if str(confirmed_data.get("displayMode", "")) == "spectator":
			data = confirmed_data.duplicate(true)
	return _base_view_model(
		"conversation",
		status,
		_world_revision,
		data,
		{
				"selectSpectatorConversation": _action(
					"conversation.spectator.select",
					interface_available and can_select,
					"NO_SPECTATABLE_CONVERSATION"
					if interface_available
					else "SPECTATOR_INTERFACE_MISSING",
				),
				"closeSpectator": _action(
					"conversation.spectator.close",
					interface_available and panel_open,
					"SPECTATOR_PANEL_NOT_OPEN",
				),
				"start": _action("conversation.start", false, "SPECTATOR_READ_ONLY"),
			"reply": _action("conversation.reply", false, "SPECTATOR_READ_ONLY"),
			"end": _action("conversation.end", false, "SPECTATOR_READ_ONLY"),
			"reject": _action("conversation.reject", false, "SPECTATOR_READ_ONLY"),
			"retry": _action(
				"conversation.spectator.retry",
				interface_available and retryable,
				"NO_RETRYABLE_ERROR",
			),
		},
		operation,
		effective_error,
	)


func _spectator_interface_available() -> bool:
	return (
		_world != null
		and _world.has_method("get_active_conversations")
		and _world.has_method("get_conversation")
		and _world.has_method("get_resident_state")
		and _runtime != null
		and _runtime.has_method("get_resident_head_screen_anchor")
		and _gateway != null
		and _gateway.has_method("get_connected_resident_names")
		and _resident_identity_status == "confirmed"
	)


func _is_resident_spectator_conversation(conversation: Dictionary) -> bool:
	var participants := conversation.get("participants", []) as Array
	if participants.size() != 2:
		return false
	var left := _spectator_participant_identity(participants[0])
	var right := _spectator_participant_identity(participants[1])
	return (
		not left.is_empty()
		and not right.is_empty()
		and String(left.get("residentId", ""))
			!= String(right.get("residentId", ""))
	)


func _spectator_participant_identity(participant_ref: Variant) -> Dictionary:
	var normalized_ref := String(participant_ref).strip_edges()
	if normalized_ref.is_empty():
		return {}
	var resident_name := _resident_name_for_id(normalized_ref)
	if not resident_name.is_empty():
		return {
			"residentId": normalized_ref,
			"residentName": resident_name,
		}
	var resident_id := _resident_id_for_name(normalized_ref)
	if resident_id.is_empty():
		return {}
	return {
		"residentId": resident_id,
		"residentName": normalized_ref,
	}


func _spectator_participant_connected(
	identity: Dictionary,
	connected: Dictionary,
) -> bool:
	return (
		connected.has(String(identity.get("residentName", "")))
		or connected.has(String(identity.get("residentId", "")))
	)


func _spectator_conversation_summary(
	conversation: Dictionary,
	connected: Dictionary,
) -> Dictionary:
	var participants := conversation.get("participants", []) as Array
	var participant_ids: Array[String] = []
	var participant_names: Array[String] = []
	for value: Variant in participants:
		var identity := _spectator_participant_identity(value)
		participant_ids.append(String(identity.get("residentId", "")))
		participant_names.append(String(identity.get("residentName", "")))
	var can_spectate := true
	for value: Variant in participants:
		if not _spectator_participant_connected(
			_spectator_participant_identity(value),
			connected,
		):
			can_spectate = false
			break
	var anchor := _spectator_entry_anchor(participant_names)
	var turns := conversation.get("turns", []) as Array
	var latest_turn_id := 0
	if not turns.is_empty() and turns.back() is Dictionary:
		latest_turn_id = int((turns.back() as Dictionary).get("turn_id", 0))
	return {
		"conversationId": str(conversation.get("conversationId", "")),
		"status": str(conversation.get("status", "active")),
		"participantIds": participant_ids,
		"participantNames": participant_names,
		"latestTurnId": latest_turn_id,
		"messageCount": turns.size(),
		"placeId": _spectator_place_id(participant_names),
		"placeLabel": _spectator_place_label(participant_names),
		"canSpectate": can_spectate,
		"disabledReason": "" if can_spectate else "SPECTATOR_PARTICIPANT_NOT_CONNECTED",
		"entryBubble": {
			"visible": can_spectate and not anchor.is_empty(),
			"label": _latest_conversation_speech(conversation),
			"screenAnchor": anchor,
			"anchorKind": "resident_pair",
			"lod": "near",
			"priority": 0,
			"clusterCount": 1,
		},
	}


func _selected_spectator_conversation(
	active_conversations: Array[Dictionary],
) -> Dictionary:
	var candidate_id := _spectator_selected_conversation_id
	if candidate_id.is_empty():
		for summary in active_conversations:
			if bool(summary.get("canSpectate", false)):
				candidate_id = str(summary.get("conversationId", ""))
				break
		if candidate_id.is_empty() and not active_conversations.is_empty():
			candidate_id = str(active_conversations[0].get("conversationId", ""))
	if candidate_id.is_empty() or _world == null or not _world.has_method("get_conversation"):
		return {}
	var conversation := _world.get_conversation(candidate_id) as Dictionary
	if not _is_resident_spectator_conversation(conversation):
		return {}
	return conversation


func _spectator_conversation_projection(
	conversation: Dictionary,
	connected: Dictionary,
) -> Dictionary:
	var participants := conversation.get("participants", []) as Array
	var participant_names: Array[String] = []
	var participant_ids: Array[String] = []
	for value: Variant in participants:
		var identity := _spectator_participant_identity(value)
		participant_ids.append(String(identity.get("residentId", "")))
		participant_names.append(String(identity.get("residentName", "")))
	var messages := _project_conversation_messages(conversation)
	var latest_expression_by_id: Dictionary = {}
	for message in messages:
		var expression_id := str(message.get("expressionId", ""))
		if not expression_id.is_empty():
			latest_expression_by_id[str(message.get("speakerId", ""))] = expression_id
	var participant_projections: Array[Dictionary] = []
	var all_connected := true
	for index in participant_names.size():
		var resident_name := participant_names[index]
		var resident_id := participant_ids[index]
		if not _spectator_participant_connected(
			{
				"residentId": resident_id,
				"residentName": resident_name,
			},
			connected,
		):
			all_connected = false
		participant_projections.append({
			"residentId": resident_id,
			"residentName": resident_name,
			"portraitRef": _resident_portrait_ref(resident_id),
			"portraitStatus": (
				"ready"
				if not _resident_portrait_ref(resident_id).is_empty()
				else "unavailable"
			),
			"portraitFallbackText": _resident_portrait_fallback(resident_name),
			"expressionId": str(latest_expression_by_id.get(resident_id, "")),
			"currentAction": _spectator_public_current_action(resident_name),
		})
	var entry_anchor := _spectator_entry_anchor(participant_names)
	return {
		"conversationId": str(conversation.get("conversationId", "")),
		"status": str(conversation.get("status", "")),
		"placeId": _spectator_place_id(participant_names),
		"placeLabel": _spectator_place_label(participant_names),
		"participants": participant_projections,
		"messages": messages,
		"waitingFor": _project_conversation_waiting_for(
			_conversation_waiting_for(conversation),
			"",
			"",
		),
		"startedAt": _duplicate_public_value(conversation.get("startedAt")),
		"updatedAt": _duplicate_public_value(conversation.get("updatedAt")),
		"endedAt": _duplicate_public_value(conversation.get("endedAt")),
		"endReason": conversation.get("endReason"),
		"canSpectate": all_connected,
		"disabledReason": "" if all_connected else "SPECTATOR_PARTICIPANT_NOT_CONNECTED",
		"entryBubble": {
			"visible": all_connected and not entry_anchor.is_empty(),
			"label": _latest_conversation_speech(conversation),
			"screenAnchor": entry_anchor,
			"anchorKind": "resident_pair",
			"lod": "near",
		},
		"observer": {
			"canSpeak": false,
			"disabledReason": "SPECTATOR_READ_ONLY",
		},
	}


func _project_conversation_messages(conversation: Dictionary) -> Array[Dictionary]:
	# 《表现层规格》要求"点击气泡可以旁观完整对话"，数据侧必须全量投影；
	# 控制节点数量的优化只能做在 UI 侧（如 MapChatScreen 的增量追加）。
	var messages: Array[Dictionary] = []
	for value: Variant in conversation.get("turns", []) as Array:
		if not value is Dictionary:
			continue
		var turn := value as Dictionary
		var speaker_name := str(turn.get("speaker", ""))
		var speaker_id := str(turn.get("speaker_resident_id", ""))
		if speaker_id.is_empty():
			speaker_id = _resident_id_for_name(speaker_name)
		var public_action: Variant = turn.get("action")
		if public_action is Dictionary:
			public_action = (public_action as Dictionary).duplicate(true)
		elif not public_action is String:
			public_action = ""
		messages.append({
			"turnId": int(turn.get("turn_id", 0)),
			"speakerId": speaker_id,
			"speaker": speaker_name,
			"say": str(turn.get("say", "")),
			"narration": str(turn.get("narration", "")),
			"action": public_action,
			"expressionId": str(turn.get("expression_id", turn.get("expressionId", ""))),
			"photos": (turn.get("photos", []) as Array).duplicate(true),
		})
	return messages


func _latest_conversation_speech(conversation: Dictionary) -> String:
	var turns := conversation.get("turns", []) as Array
	for index: int in range(turns.size() - 1, -1, -1):
		if not turns[index] is Dictionary:
			continue
		var speech := String((turns[index] as Dictionary).get("say", ""))
		if not speech.strip_edges().is_empty():
			return speech.strip_edges()
	return ""


func _conversation_waiting_for(conversation: Dictionary) -> Array[String]:
	var waiting_for: Array[String] = []
	var value: Variant = conversation.get("waitingFor", "")
	if value is Array:
		for item: Variant in value as Array:
			if not str(item).is_empty():
				waiting_for.append(str(item))
	elif not str(value).is_empty():
		waiting_for.append(str(value))
	return waiting_for


func _spectator_entry_anchor(
	participant_names: Array[String],
) -> Dictionary:
	if participant_names.size() != 2:
		return {}
	var anchors: Array[Vector2] = []
	for resident_name in participant_names:
		var resident_id := _resident_id_for_name(resident_name)
		var value := get_town_hud_resident_head_anchor(resident_id)
		if (
			not bool(value.get("valid", false))
			or not bool(value.get("visible", false))
			or not value.has("x")
			or not value.has("y")
		):
			return {}
		anchors.append(
			Vector2(
				float(value.get("x", 0.0)),
				float(value.get("y", 0.0)),
			)
		)
	var sum := Vector2.ZERO
	for anchor in anchors:
		sum += anchor
	var midpoint := sum / float(anchors.size())
	return {"x": midpoint.x, "y": midpoint.y}


func _spectator_place_id(participant_names: Array[String]) -> String:
	if participant_names.is_empty():
		return ""
	var state := _world.get_resident_state(participant_names[0]) as Dictionary
	return str(state.get("spaceId", ""))


func _spectator_place_label(participant_names: Array[String]) -> String:
	if participant_names.is_empty():
		return ""
	var state := _world.get_resident_state(participant_names[0]) as Dictionary
	return str(state.get("currentPlace", ""))


func _spectator_public_current_action(resident_name: String) -> Variant:
	var state := _world.get_resident_state(resident_name) as Dictionary
	var action: Variant = state.get("currentAction")
	if action is Dictionary:
		return (action as Dictionary).duplicate(true)
	return null


func _duplicate_public_value(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


func _spectator_conversation_before(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("conversationId", "")) < str(right.get("conversationId", ""))


func _build_announcements_view_model(operation: Dictionary, error: Dictionary) -> Dictionary:
	var announcements: Array = []
	if _world != null and _world.has_method("get_announcements"):
		announcements = _world.get_announcements()
	return _base_view_model(
		"announcements",
		"ready" if _world != null else "disabled",
		_world_revision,
		{"items": announcements.duplicate(true)},
		{"publish": _action("announcements.publish", _world != null)},
		operation,
		error
	)


func _build_town_hud_view_model(operation: Dictionary, error: Dictionary) -> Dictionary:
	var lifecycle := _scope_data("lifecycle")
	var environment := _scope_data("environment")
	var avatar := _scope_data("avatar")
	var announcements := _scope_data("announcements")
	var runtime_state: Dictionary = {}
	if (
		_runtime != null
		and _runtime.has_method("get_town_hud_runtime_state")
	):
		runtime_state = _runtime.call(
			"get_town_hud_runtime_state"
		) as Dictionary
	elif _runtime != null and _runtime.has_method("get_runtime_state"):
		runtime_state = _runtime.call("get_runtime_state") as Dictionary
	var started := bool(lifecycle.get("started", false))
	var paused := bool(lifecycle.get("paused", false))
	var pause_reasons := (lifecycle.get("pauseReasons", []) as Array).duplicate()
	var simulation_speed := 0
	var simulation_speed_interface_available := (
		_world != null
		and _world.has_method("get_simulation_speed")
		and _world.has_method("set_simulation_speed")
	)
	if simulation_speed_interface_available:
		simulation_speed = int(_world.get_simulation_speed())
	var can_set_simulation_speed := started and simulation_speed_interface_available
	var simulation_speed_disabled_reason := (
		"WORLD_NOT_RUNNING"
		if not started
		else "SIMULATION_SPEED_INTERFACE_MISSING"
	)
	var social_matter_activity := _hud_social_matter_activity(started)
	var resident_overlays := _hud_resident_overlays(
		runtime_state,
		avatar,
		started,
		paused,
	)
	var resident_directory := _hud_resident_directory(runtime_state)
	var place_directory := _hud_place_directory(runtime_state)
	var event_overlay := _hud_event_overlay(announcements)
	var event_overlay_items := event_overlay.get("items", []) as Array
	var latest_event_payload := {}
	if not event_overlay_items.is_empty():
		var latest_event := event_overlay_items[event_overlay_items.size() - 1] as Dictionary
		var latest_announcement_id := String(
			latest_event.get("eventId", ""),
		).strip_edges()
		if not latest_announcement_id.is_empty():
			latest_event_payload = {
				"threadId": "announcement:%s" % latest_announcement_id,
			}
	var offscreen_activity := _hud_offscreen_activity_disabled()
	var far_resident_activity := _hud_far_resident_activity(runtime_state, started)
	var view_mode := str(runtime_state.get("viewMode", "unavailable"))
	var active_interior_id := str(runtime_state.get("activeInteriorId", ""))
	var avatar_mode := str(runtime_state.get("avatarMode", "observer"))
	var followed_resident := str(runtime_state.get("followedResident", ""))
	var follow_target_id := _resident_id_for_name(followed_resident)
	if follow_target_id.is_empty():
		var overlay_items := resident_overlays.get("items", []) as Array
		if not overlay_items.is_empty():
			follow_target_id = str((overlay_items[0] as Dictionary).get("residentId", ""))
	if follow_target_id.is_empty():
		var directory_items := resident_directory.get("items", []) as Array
		if not directory_items.is_empty():
			follow_target_id = str((directory_items[0] as Dictionary).get("residentId", ""))
	var player_avatar_enabled := bool(runtime_state.get("playerAvatarEnabled", false))
	var can_follow := (
		started
		and not player_avatar_enabled
		and not follow_target_id.is_empty()
		and _runtime != null
		and _runtime.has_method("follow_resident")
	)
	var can_unfollow := (
		started
		and not player_avatar_enabled
		and not followed_resident.is_empty()
		and _runtime != null
		and _runtime.has_method("cancel_resident_follow")
	)
	var can_open_event := (
		started
		and bool(event_overlay.get("visible", false))
		and _ui_route_host != null
	)
	var can_open_formal_page := started and _ui_route_host != null
	var can_toggle_avatar := (
		started
		and _ui_route_host != null
		and avatar_mode in ["observer", "avatar_active"]
		and _runtime != null
		and (
			(
				avatar_mode == "observer"
				and _runtime.has_method("enter_avatar_mode")
			)
			or (
				avatar_mode == "avatar_active"
				and _runtime.has_method("exit_avatar_mode")
			)
		)
	)
	var can_focus_resident := not (resident_overlays.get("items", []) as Array).is_empty()
	var can_control_observer_camera := (
		started
		and not player_avatar_enabled
		and view_mode == "town"
		and _runtime != null
		and _runtime.has_method("zoom_observer_camera")
		and _runtime.has_method("reset_observer_camera")
	)
	var camera_zoom_band := _hud_effective_zoom_band(runtime_state)
	var status := "ready" if started else "disabled"
	if not error.is_empty():
		status = "error"
	return _base_view_model(
		"town_hud",
		status,
		_world_revision,
		{
			"source": str(_session_config.get("source", "runtime")),
			"capabilityMode": str(_session_config.get("capabilityMode", "development")),
			"formalReady": bool(_session_config.get("formalReady", false)),
			"timeWeather": {
				"day": int(environment.get("day", 0)),
				"clock": str(environment.get("clock", "")),
				"periodId": str(environment.get("periodId", "")),
				"periodLabel": str(environment.get("periodLabel", "")),
				"weatherId": str(environment.get("weatherId", "")),
				"weatherLabel": str(environment.get("weatherLabel", "")),
				"outdoorTone": str(environment.get("outdoorTone", "")),
				"simulationSpeed": simulation_speed,
				"options": [],
			},
			"toolbar": {
				"activeToolId": (
					"avatar"
					if avatar_mode in ["avatar_descent", "avatar_active"]
					else ""
				),
				"items": [
					_hud_toolbar_item(
						"weather_control",
						"天气",
						"openWeather",
						can_open_formal_page,
						"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
					),
					_hud_toolbar_item(
						"town_log",
						"日志",
						"openTownLog",
						can_open_formal_page,
						"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
					),
					_hud_toolbar_item(
						"avatar",
						"化身",
						"toggleAvatar",
						can_toggle_avatar,
						(
							"AVATAR_MODE_TRANSITION_IN_PROGRESS"
							if avatar_mode == "avatar_descent"
							else "AVATAR_MODE_INTERFACE_MISSING"
						),
					),
					_hud_toolbar_item(
						"more",
						"更多",
						"openMore",
						can_open_formal_page,
						"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
					),
				],
			},
			"camera": {
				"mode": "following" if not followed_resident.is_empty() else "free",
				"focusedResidentId": (
					_resident_id_for_name(followed_resident)
					if not followed_resident.is_empty()
					else ""
				),
				"focusedResidentName": followed_resident,
				"zoomStep": int(runtime_state.get("cameraZoomIndex", -1)),
				"zoomRatio": float(runtime_state.get("cameraZoomRatio", 0.0)),
				"zoomStepCount": int(runtime_state.get("cameraZoomStepCount", 0)),
				"canDrag": can_control_observer_camera,
				"canReset": can_control_observer_camera,
				"followTargetId": follow_target_id,
			},
			"pausePrompt": {
				"visible": paused,
				"reasonCodes": pause_reasons,
				"label": "小镇时间已暂停" if paused else "",
			},
			"residentOverlays": resident_overlays,
			"residentDirectory": resident_directory,
			"placeDirectory": place_directory,
			"mapInteraction": {
				"mode": view_mode,
				"spaceId": str(avatar.get("spaceId", "")),
				"hoverTargetId": "",
				"selectedTargetId": str(runtime_state.get("observedPlace", "")),
				"promptCode": "",
				"promptLabel": str(runtime_state.get("observedPlace", "")),
			},
			"indoorMarkers": {
				"visible": not active_interior_id.is_empty(),
				"buildingId": active_interior_id,
				"residentCount": (runtime_state.get("visibleIndoorBadges", []) as Array).size(),
				"items": _hud_indoor_items(runtime_state),
			},
			"eventOverlay": event_overlay,
				"offscreenActivity": offscreen_activity,
				"socialMatterActivity": social_matter_activity,
				"farResidentActivity": far_resident_activity,
			"density": {
				"zoomBand": camera_zoom_band,
				"hysteresisActive": bool(
					runtime_state.get("cameraZoomBandStable", false)
				),
				"suppressedCount": int(resident_overlays.get("aggregateCount", 0)),
			},
		},
		{
			"pause": _action("lifecycle.pause", started and not paused, "WORLD_ALREADY_PAUSED", {"reason": "manual"}),
			"resume": _action("lifecycle.resume", started and paused, "WORLD_NOT_PAUSED", {"reason": "manual"}),
			"timeSpeed1": _action(
				"town_hud.set_time_speed",
				can_set_simulation_speed,
				simulation_speed_disabled_reason,
				{"multiplier": 1},
			),
			"timeSpeed2": _action(
				"town_hud.set_time_speed",
				can_set_simulation_speed,
				simulation_speed_disabled_reason,
				{"multiplier": 2},
			),
			"timeSpeed3": _action(
				"town_hud.set_time_speed",
				can_set_simulation_speed,
				simulation_speed_disabled_reason,
				{"multiplier": 3},
			),
			"openWeather": _action(
				"town_hud.open_weather",
				can_open_formal_page,
				"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
			),
			"openTownLog": _action(
				"town_hud.open_town_log",
				can_open_formal_page,
				"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
			),
			"openBulletin": _action(
				"town_hud.open_bulletin",
				can_open_formal_page,
				"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
			),
			"openResidentManagement": _action(
				"town_hud.open_resident_management",
				can_open_formal_page,
				"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
			),
			"openPlaceFocus": _action(
				"town_hud.open_place_focus",
				can_open_formal_page
					and not (place_directory.get("items", []) as Array).is_empty(),
				"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
			),
			"toggleAvatar": _action(
				"town_hud.toggle_avatar",
				can_toggle_avatar,
				(
					"AVATAR_MODE_TRANSITION_IN_PROGRESS"
					if avatar_mode == "avatar_descent"
					else "AVATAR_MODE_INTERFACE_MISSING"
				),
			),
			"openMore": _action(
				"town_hud.open_more",
				can_open_formal_page,
				"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
			),
			"weatherChange": _action(
				"town_hud.open_weather",
				can_open_formal_page,
				"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
			),
			"selectTool": _action(
				"town_hud.select_tool",
				started and _ui_route_host != null,
				"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
			),
			"cameraZoomIn": _action(
				"town_hud.camera_zoom_in",
				can_control_observer_camera,
				"OBSERVER_CAMERA_NOT_ACTIVE",
			),
			"cameraZoomOut": _action(
				"town_hud.camera_zoom_out",
				can_control_observer_camera,
				"OBSERVER_CAMERA_NOT_ACTIVE",
			),
			"cameraReset": _action(
				"town_hud.camera_reset",
				can_control_observer_camera,
				"OBSERVER_CAMERA_NOT_ACTIVE",
			),
			"cameraFollow": _action("town_hud.camera_follow", can_follow, "NO_FOLLOW_TARGET"),
			"cameraUnfollow": _action("town_hud.camera_unfollow", can_unfollow, "CAMERA_NOT_FOLLOWING"),
			"focusResident": _action("avatar.focus_target", can_focus_resident, "NO_RESIDENT_TARGET"),
			"openIndoorTarget": _action(
				"town_hud.open_indoor_target",
				can_open_formal_page and not active_interior_id.is_empty(),
				"NO_ACTIVE_INTERIOR",
			),
			"openEvent": _action(
				"town_hud.open_town_log",
				can_open_event,
				"NO_EVENT",
				latest_event_payload,
			),
		},
		operation,
		error,
	)


func _hud_effective_zoom_band(runtime_state: Dictionary) -> String:
	# Following one resident is an explicit personal focus, regardless of the
	# observer camera's last zoom step. It uses the same icon-plus-text density
	# as an indoor or event close view.
	if not str(runtime_state.get("followedResident", "")).is_empty():
		return "near"
	# An interior is already a focused place. Its residents must keep their
	# readable public action text even when the observer camera itself remains
	# on the ordinary middle zoom step.
	if not str(runtime_state.get("activeInteriorId", "")).is_empty():
		return "near"
	var camera_zoom_band := str(
		runtime_state.get("cameraZoomBand", "unavailable")
	)
	if camera_zoom_band not in ["far", "middle", "near"]:
		return "unavailable"
	return camera_zoom_band


func _scope_data(scope: String) -> Dictionary:
	# Dependent view models can be requested before the queued per-frame refresh
	# reaches their source scopes. Refresh only a dirty dependency here so HUD
	# never renders one frame from a stale lifecycle/avatar/environment state.
	# 不强制 emit：内容没变时给页面重发 view_model_changed 只会让每个
	# 绑定页在化身移动的 10Hz 刷新里白做整套深拷贝对比。
	if _dirty_world_scopes.has(scope):
		_refresh_scope(scope)
	var view_model := _view_models.get(scope, {}) as Dictionary
	return (view_model.get("data", {}) as Dictionary).duplicate(true)


func _hud_toolbar_item(
	tool_id: String,
	label: String,
	action_key: String,
	enabled: bool,
	disabled_reason: String,
) -> Dictionary:
	return {
		# `id` remains as a render-key compatibility alias. New consumers must
		# route by the explicit toolId/actionKey pair, never by visual index.
		"id": tool_id,
		"toolId": tool_id,
		"actionKey": action_key,
		"label": label,
		"badge": 0,
		"enabled": enabled,
		"disabledReason": "" if enabled else disabled_reason,
	}


func _hud_resident_overlays(
	runtime_state: Dictionary,
	_avatar: Dictionary,
	started: bool,
	paused: bool,
) -> Dictionary:
	_sync_hud_pause_state(paused)
	if not started:
		_clear_hud_public_thoughts()
		return _empty_hud_resident_overlays()
	var candidates: Array[Dictionary] = []
	var owned_resident_ids: Dictionary = {}
	var now_msec := _hud_effective_now_msec()
	var followed_resident_id := _resident_id_for_name(
		String(runtime_state.get("followedResident", ""))
	)
	# 1a:构建完整候选集,不做锚点过滤 / 预算截断 / 聚合计数;
	# 可见性过滤、visibleBudget 与 aggregateCount 由消费层每帧活读锚点执行。
	# spaceId / indoor 取权威居民状态,不从锚点推导。
	var resident_states_by_id: Dictionary = {}
	for value: Variant in runtime_state.get("residents", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var state := value as Dictionary
		var state_resident_id := String(state.get("residentId", "")).strip_edges()
		if state_resident_id.is_empty():
			state_resident_id = _resident_id_for_name(
				String(state.get("name", "")).strip_edges()
			)
		if not state_resident_id.is_empty():
			resident_states_by_id[state_resident_id] = state
	for value: Variant in runtime_state.get("residents", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var state := value as Dictionary
		var resident_name := String(state.get("name", "")).strip_edges()
		var resident_id := _resident_id_for_name(resident_name)
		if (
			not followed_resident_id.is_empty()
			and resident_id != followed_resident_id
		):
			continue
		var phase := state.get("actionPhase", {}) as Dictionary
		if _has_active_hud_activity_reaction(resident_id):
			continue
		var public_thought := _hud_public_thought_text(
			String(phase.get("publicThought", ""))
		)
		var remaining_seconds := maxf(
			0.0,
			float(phase.get("remainingSeconds", 0.0)),
		)
		if (
			resident_id.is_empty()
			or String(phase.get("phase", "")) != "executing_preview"
			or String(phase.get("previewId", "")).strip_edges().is_empty()
			or public_thought.is_empty()
			or remaining_seconds <= 0.0
		):
			continue
		var space_id := String(state.get("spaceId", "")).strip_edges()
		if space_id.is_empty():
			_hud_overlay_missing_state_count += 1
			continue
		owned_resident_ids[resident_id] = true
		candidates.append(_hud_public_thought_item(
			String(phase.get("previewId", "")),
			String(phase.get("actionId", "")),
			resident_id,
			resident_name,
			public_thought,
			int(phase.get("confirmedRevision", _world_revision)),
			now_msec,
			now_msec + int(round(remaining_seconds * 1000.0)),
			space_id,
			"action_intention",
			phase,
		))
	for snapshot_key_value: Variant in _hud_public_thought_order:
		var snapshot_key := String(snapshot_key_value)
		var snapshot := _hud_public_thoughts.get(
			snapshot_key,
			{},
		) as Dictionary
		if (
			snapshot.is_empty()
			or String(snapshot.get("publicThought", "")).strip_edges().is_empty()
		):
			continue
		var resident_id := String(snapshot.get("residentId", ""))
		if (
			owned_resident_ids.has(resident_id)
			or (
				not followed_resident_id.is_empty()
				and resident_id != followed_resident_id
			)
			or int(snapshot.get("expiresAtMsec", 0)) <= now_msec
		):
			continue
		var snapshot_state := resident_states_by_id.get(
			resident_id,
			{},
		) as Dictionary
		var space_id := String(snapshot_state.get("spaceId", "")).strip_edges()
		if space_id.is_empty():
			_hud_overlay_missing_state_count += 1
			continue
		owned_resident_ids[resident_id] = true
		candidates.append(_hud_public_thought_item(
			String(snapshot.get("previewId", "")),
			String(snapshot.get("actionId", "")),
			resident_id,
			String(snapshot.get("residentName", "")),
			String(snapshot.get("publicThought", "")),
			int(snapshot.get("confirmedRevision", _world_revision)),
			int(snapshot.get("startedAtMsec", now_msec)),
			int(snapshot.get("expiresAtMsec", now_msec)),
			space_id,
			String(
				snapshot.get("thoughtKind", "action_intention")
			),
			snapshot,
		))
	candidates.sort_custom(Callable(self, "_hud_public_thought_before"))
	return {
		"source": "world_confirmed_public_thought",
		"contentKind": "public_thought",
		"focusRequired": not followed_resident_id.is_empty(),
		"focusedOnly": not followed_resident_id.is_empty(),
		"focusedResidentId": followed_resident_id,
		"focusedResidentName": String(
			runtime_state.get("followedResident", "")
		),
		"visibleBudget": HUD_TRANSIENT_RESIDENT_VISIBLE_BUDGET,
		"aggregateCount": 0,
		"missingResidentStateCount": _hud_overlay_missing_state_count,
		"items": candidates,
	}


func _empty_hud_resident_overlays() -> Dictionary:
	return {
		"source": "world_confirmed_public_thought",
		"contentKind": "public_thought",
		"focusRequired": false,
		"focusedOnly": false,
		"focusedResidentId": "",
		"focusedResidentName": "",
		"visibleBudget": HUD_TRANSIENT_RESIDENT_VISIBLE_BUDGET,
		"aggregateCount": 0,
		"missingResidentStateCount": _hud_overlay_missing_state_count,
		"items": [],
	}


func _hud_public_thought_item(
	preview_id: String,
	action_id: String,
	resident_id: String,
	resident_name: String,
	public_thought: String,
	confirmed_revision: int,
	started_at_msec: int,
	expires_at_msec: int,
	space_id: String,
	thought_kind := "action_intention",
	presentation: Dictionary = {},
) -> Dictionary:
	var item := {
		"contentKind": "public_thought",
		"thoughtKind": thought_kind,
		"thoughtId": preview_id,
		"previewId": preview_id,
		"actionId": action_id,
		"residentId": resident_id,
		"residentName": resident_name,
		"name": resident_name,
		"label": public_thought,
		"behaviorLabel": "",
		"thoughtLabel": public_thought,
		"expressionId": "",
		"importance": "normal",
		"displayRank": (
			0
			if thought_kind in ["activity_reaction", "announcement_reaction"]
			else (1 if thought_kind == "action_intention" else 10)
		),
		"playbackIdentity": "%s|%s|%s" % [
			resident_id,
			thought_kind,
			preview_id,
		],
		"confirmedRevision": confirmed_revision,
		"startedAtMsec": started_at_msec,
		"expiresAtMsec": expires_at_msec,
		"spaceId": space_id,
		"indoor": space_id != "town_outdoor",
		"action": _action(
			(
				"town_hud.open_town_log"
				if thought_kind == "announcement_reaction"
				else "town_hud.open_resident_action"
			),
			_ui_route_host != null,
			"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
			(
				{
					"threadId": "announcement:%s" % String(
						presentation.get("announcementId", ""),
					),
				}
				if thought_kind == "announcement_reaction"
				else {
					"residentId": resident_id,
					"residentName": resident_name,
				}
			),
		),
	}
	for field: String in [
		"baseIconKey",
		"phase",
		"waitReason",
		"sourceActivityId",
		"visibleSpaceId",
		"announcementId",
	]:
		if presentation.has(field):
			item[field] = presentation[field]
	var formal_label := String(presentation.get("label", "")).strip_edges()
	if not formal_label.is_empty():
		item["formalActionLabel"] = _hud_action_display_label(
			formal_label,
			"approaching",
			String(presentation.get("waitReason", "")),
		)
	return item


func _hud_public_thought_text(value: String) -> String:
	var normalized := value.strip_edges()
	for separator: String in ["\r", "\n", "\t"]:
		normalized = normalized.replace(separator, " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	const MAX_BUBBLE_DISPLAY_UNITS := 18.0
	const ELLIPSIS_DISPLAY_UNITS := 1.0
	if _hud_text_display_units(normalized) <= MAX_BUBBLE_DISPLAY_UNITS:
		return normalized
	var content_limit := MAX_BUBBLE_DISPLAY_UNITS - ELLIPSIS_DISPLAY_UNITS
	var split_at := _hud_prefix_length_for_display_units(
		normalized,
		content_limit,
	)
	var prefix := normalized.left(split_at).strip_edges()
	return prefix if prefix.ends_with("…") else prefix + "…"


func _hud_prefix_length_for_display_units(
	value: String,
	max_units: float,
) -> int:
	var units := 0.0
	for index: int in value.length():
		var next_units := units + _hud_character_display_units(value, index)
		if next_units > max_units:
			return index
		units = next_units
	return value.length()


func _hud_text_display_units(value: String) -> float:
	var units := 0.0
	for index: int in value.length():
		units += _hud_character_display_units(value, index)
	return units


func _hud_character_display_units(value: String, index: int) -> float:
	var character := value.substr(index, 1)
	return maxf(
		0.5,
		HUD_TEXT_FONT.get_string_size(
			character,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			20,
		).x / 20.0,
	)


func _hud_public_thought_before(left: Dictionary, right: Dictionary) -> bool:
	var left_rank := int(left.get("displayRank", 10))
	var right_rank := int(right.get("displayRank", 10))
	if left_rank != right_rank:
		return left_rank < right_rank
	var left_revision := int(left.get("confirmedRevision", 0))
	var right_revision := int(right.get("confirmedRevision", 0))
	if left_revision != right_revision:
		return left_revision > right_revision
	return String(left.get("residentId", "")) < String(
		right.get("residentId", "")
	)


func _prune_hud_public_thoughts() -> bool:
	if _hud_pause_started_msec > 0:
		return false
	var now_msec := _hud_effective_now_msec()
	var expired: Array[String] = []
	for snapshot_key_value: Variant in _hud_public_thought_order:
		var snapshot_key := String(snapshot_key_value)
		var snapshot := _hud_public_thoughts.get(
			snapshot_key,
			{},
		) as Dictionary
		if (
			snapshot.is_empty()
			or int(snapshot.get("expiresAtMsec", 0)) <= now_msec
		):
			expired.append(snapshot_key)
	for snapshot_key: String in expired:
		_hud_public_thoughts.erase(snapshot_key)
		_hud_public_thought_order.erase(snapshot_key)
	return not expired.is_empty()


func _clear_hud_public_thoughts() -> void:
	_hud_public_thoughts.clear()
	_hud_public_thought_order.clear()


func _hud_effective_now_msec() -> int:
	return (
		_hud_pause_started_msec
		if _hud_pause_started_msec > 0
		else Time.get_ticks_msec()
	)


func _sync_hud_pause_state(paused: bool) -> bool:
	var now_msec := Time.get_ticks_msec()
	if paused:
		if _hud_pause_started_msec == 0:
			_hud_pause_started_msec = now_msec
			_hud_conversation_bubble_playback.set_paused(true, now_msec)
			return true
		return false
	if _hud_pause_started_msec == 0:
		return false
	var paused_duration := maxi(0, now_msec - _hud_pause_started_msec)
	_hud_pause_started_msec = 0
	_hud_conversation_bubble_playback.set_paused(false, now_msec)
	if paused_duration <= 0:
		return true
	_shift_hud_snapshot_times(_hud_public_thoughts, paused_duration)
	_shift_hud_snapshot_times(_hud_far_conversations, paused_duration)
	return true


func _shift_hud_snapshot_times(
	snapshots: Dictionary,
	offset_msec: int,
) -> void:
	for key_value: Variant in snapshots.keys():
		var key := String(key_value)
		var snapshot := snapshots.get(key, {}) as Dictionary
		if snapshot.is_empty():
			continue
		for field: String in ["startedAtMsec", "expiresAtMsec"]:
			var value := int(snapshot.get(field, 0))
			if value > 0:
				snapshot[field] = value + offset_msec
		snapshots[key] = snapshot


func _reset_hud_social_matter_activity() -> void:
	_hud_social_matter_seen_keys.clear()
	_hud_social_matter_initialized = false
	_hud_social_matter_projection.clear()
	_hud_social_matter_polled_world_revision = -1


func _hud_social_matter_activity(started: bool) -> Dictionary:
	if not started:
		return {
			"available": false,
			"disabledReason": "WORLD_NOT_RUNNING",
			"revision": _world_revision,
			"items": [],
			"history": [],
		}
	_sync_hud_social_matter_activity()
	var active_items: Array[Dictionary] = []
	var now_msec := _hud_effective_now_msec()
	for snapshot_key_value: Variant in _hud_public_thought_order:
		var snapshot_key := String(snapshot_key_value)
		if not snapshot_key.begins_with("social:"):
			continue
		var snapshot := (
			_hud_public_thoughts.get(snapshot_key, {}) as Dictionary
		)
		if (
			snapshot.is_empty()
			or int(snapshot.get("expiresAtMsec", 0)) <= now_msec
		):
			continue
		active_items.append(snapshot.duplicate(true))
	return {
		"available": (
			_world != null
			and _world.has_method("get_public_social_matter_activity")
		),
		"disabledReason": (
			""
			if (
				_world != null
				and _world.has_method("get_public_social_matter_activity")
			)
			else "SOCIAL_MATTER_PUBLIC_INTERFACE_MISSING"
		),
		"revision": int(
			_hud_social_matter_projection.get("revision", _world_revision)
		),
		"items": active_items,
		"history": (
			_hud_social_matter_projection.get("history", []) as Array
		).duplicate(true),
	}


func _sync_hud_social_matter_activity() -> bool:
	if (
		_world == null
		or not _world.has_method("get_public_social_matter_activity")
	):
		return false
	var world_revision := _read_world_revision()
	if world_revision == _hud_social_matter_polled_world_revision:
		return false
	var projection_value: Variant = _world.get_public_social_matter_activity()
	if typeof(projection_value) != TYPE_DICTIONARY:
		return false
	var projection := (projection_value as Dictionary).duplicate(true)
	_hud_social_matter_polled_world_revision = world_revision
	_hud_social_matter_projection = projection
	var items_value: Variant = projection.get("items", [])
	if typeof(items_value) != TYPE_ARRAY:
		return false
	var items := items_value as Array
	if not _hud_social_matter_initialized:
		for value: Variant in items:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var initial_key := _hud_social_matter_snapshot_key(
				value as Dictionary
			)
			if not initial_key.is_empty():
				_hud_social_matter_seen_keys[initial_key] = true
		_hud_social_matter_initialized = true
		return false
	var changed := false
	for value: Variant in items:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var item := value as Dictionary
		var snapshot_key := _hud_social_matter_snapshot_key(item)
		if (
			snapshot_key.is_empty()
			or _hud_social_matter_seen_keys.has(snapshot_key)
		):
			continue
		_hud_social_matter_seen_keys[snapshot_key] = true
		var resident_id := String(item.get("residentId", "")).strip_edges()
		var resident_name := String(
			item.get("residentName", "")
		).strip_edges()
		var phase := String(item.get("phase", "")).strip_edges()
		var icon_type := String(item.get("iconType", "")).strip_edges()
		if icon_type not in ["", "observing", "reading"]:
			icon_type = ""
		var summary := _hud_social_matter_summary(item, phase)
		if (
			resident_id.is_empty()
			or resident_name.is_empty()
			or (icon_type.is_empty() and summary.is_empty())
		):
			continue
		var head_anchor := get_town_hud_resident_head_anchor(resident_id)
		if (
			not bool(head_anchor.get("valid", false))
			or not bool(head_anchor.get("visible", false))
		):
			continue
		var now_msec := _hud_effective_now_msec()
		var matter_id := String(item.get("matterId", "")).strip_edges()
		var preview_id := "social:%s" % snapshot_key
		_hud_public_thoughts[preview_id] = {
			"previewId": preview_id,
			"actionId": matter_id,
			"socialMatterId": matter_id,
			"residentId": resident_id,
			"residentName": resident_name,
			"publicThought": summary,
			"thoughtKind": "social_matter_%s" % phase,
			"semanticIconType": icon_type,
			"confirmedRevision": int(item.get("confirmedRevision", 0)),
			"startedAtMsec": now_msec,
			"expiresAtMsec": now_msec + HUD_SOCIAL_MATTER_LIFETIME_MSEC,
			"phase": phase,
			"expiresAtAbsoluteMinute": int(
				item.get("expiresAtAbsoluteMinute", -1)
			),
		}
		_hud_public_thought_order.erase(preview_id)
		_hud_public_thought_order.push_front(preview_id)
		changed = true
	return changed


func _hud_social_matter_snapshot_key(item: Dictionary) -> String:
	var matter_id := String(item.get("matterId", "")).strip_edges()
	var resident_id := String(item.get("residentId", "")).strip_edges()
	var phase := String(item.get("phase", "")).strip_edges()
	var confirmed_revision := int(item.get("confirmedRevision", -1))
	if (
		matter_id.is_empty()
		or resident_id.is_empty()
		or phase not in ["observing", "reading", "responding", "executing"]
		or confirmed_revision < 0
	):
		return ""
	return "%s:%s:%s:%d" % [
		matter_id,
		resident_id,
		phase,
		confirmed_revision,
	]


func _hud_social_matter_summary(item: Dictionary, phase: String) -> String:
	var raw := ""
	match phase:
		"observing", "reading":
			raw = String(item.get("reasonSummary", ""))
		"responding":
			raw = String(item.get("promiseSummary", ""))
		"executing":
			raw = String(item.get("executionSummary", ""))
		_:
			return ""
	return _hud_public_thought_text(raw)


func _hud_far_resident_activity(
	runtime_state: Dictionary,
	started: bool,
) -> Dictionary:
	if not started:
		_clear_hud_far_resident_activity(true)
	var available := (
		_world != null
		and _runtime != null
		and _runtime.has_method("get_resident_head_screen_anchor")
		and _resident_identity_status == "confirmed"
	)
	var conversation_items: Array[Dictionary] = []
	var followed_resident_id := _resident_id_for_name(
		String(runtime_state.get("followedResident", ""))
	)
	var connected: Dictionary = {}
	for resident_name in _connected_resident_names():
		connected[resident_name] = true

	for conversation_id_value: Variant in _hud_far_conversation_order:
		var conversation_id := String(conversation_id_value)
		var stored_conversation := (
			_hud_far_conversations.get(conversation_id, {}) as Dictionary
		)
		if stored_conversation.is_empty():
			continue
		var participant_ids := (
			stored_conversation.get("participantIds", []) as Array
		)
		if (
			not followed_resident_id.is_empty()
			and not participant_ids.has(followed_resident_id)
		):
			continue
		var participant_names := (
			stored_conversation.get("participantNames", []) as Array
		)
		var can_spectate := _spectator_interface_available()
		if can_spectate:
			for resident_name_value: Variant in participant_names:
				if not connected.has(String(resident_name_value)):
					can_spectate = false
					break
		var conversation_item := stored_conversation.duplicate(true)
		conversation_item["action"] = _action(
			"conversation.spectator.select",
			can_spectate,
			(
				""
				if can_spectate
				else "SPECTATOR_PARTICIPANT_NOT_CONNECTED"
			),
			{"conversationId": conversation_id},
		)
		conversation_items.append(conversation_item)

	var all_items: Array[Dictionary] = []
	all_items.append_array(conversation_items)
	var zoom_band := _hud_effective_zoom_band(runtime_state)
	var owned_resident_ids: Dictionary = {}
	for conversation_value: Variant in conversation_items:
		for participant_value: Variant in (
			(conversation_value as Dictionary).get(
				"participantIds",
				[],
			) as Array
		):
			owned_resident_ids[String(participant_value)] = true
	for state_value: Variant in runtime_state.get("residents", []) as Array:
		if typeof(state_value) != TYPE_DICTIONARY:
			continue
		var state := state_value as Dictionary
		var resident_name := String(state.get("name", "")).strip_edges()
		var resident_id := String(
			state.get("residentId", "")
		).strip_edges()
		if resident_id.is_empty() and not resident_name.is_empty():
			resident_id = _resident_id_for_name(resident_name)
		if resident_id.is_empty() or owned_resident_ids.has(resident_id):
			continue
		if (
			not followed_resident_id.is_empty()
			and resident_id != followed_resident_id
		):
			continue
		if _has_active_hud_activity_result(resident_id):
			continue
		var semantic := _hud_live_resident_semantic(state)
		var icon_type := String(
			semantic.get("iconType", "")
		).strip_edges()
		if icon_type.is_empty():
			continue
		var current_action_value: Variant = state.get("currentAction")
		var current_action := (
			current_action_value as Dictionary
			if current_action_value is Dictionary
			else {}
		)
		var action_id := String(
			current_action.get("action_id", "state")
		).strip_edges()
		if action_id.is_empty():
			action_id = "state"
		var phase := String(semantic.get("phase", "")).strip_edges()
		all_items.append({
			"overlayId": "resident-live:%s:%s:%s:%s" % [
				resident_id,
				action_id,
				phase,
				icon_type,
			],
			"kind": "semantic_icon",
			"sourceActionId": action_id,
			"residentId": resident_id,
			"residentName": resident_name,
			"playbackIdentity": "%s|%s|%s|%s" % [
				resident_id,
				action_id,
				phase,
				icon_type,
			],
			"anchorKind": "resident",
			"anchorPolicy": "live_resident_head",
			"motionPolicy": "follow_resident",
			"startedAtMsec": _hud_effective_now_msec(),
			"expiresAtMsec": 0,
			"confirmedRevision": _world_revision,
			"semanticKind": String(
				semantic.get("semanticKind", "activity")
			),
			"iconType": icon_type,
			"phase": phase,
			"markerKey": String(semantic.get("markerKey", "")),
			"label": String(semantic.get("label", "")),
			"thoughtLabel": String(semantic.get("thoughtLabel", "")),
			"showLabel": zoom_band in ["middle", "near"],
			"animate": bool(semantic.get("animate", false)),
			"source": String(
				semantic.get("source", "world.resident.actionPresentation")
			),
			"action": _action(
				"town_hud.open_resident_action",
				_ui_route_host != null,
				"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
				{
					"residentId": resident_id,
					"residentName": resident_name,
				},
			),
		})
		owned_resident_ids[resident_id] = true
	var now_msec := _hud_effective_now_msec()
	for snapshot_key_value: Variant in _hud_public_thought_order:
		var snapshot_key := String(snapshot_key_value)
		var snapshot := _hud_public_thoughts.get(
			snapshot_key,
			{},
		) as Dictionary
		if (
			snapshot.is_empty()
			or int(snapshot.get("expiresAtMsec", 0)) <= now_msec
		):
			continue
		var resident_id := String(snapshot.get("residentId", ""))
		if (
			owned_resident_ids.has(resident_id)
			or (
				not followed_resident_id.is_empty()
				and resident_id != followed_resident_id
			)
		):
			continue
		var resident_name := String(snapshot.get("residentName", ""))
		var action_id := String(snapshot.get("actionId", ""))
		var semantic := _hud_far_activity_semantic(snapshot)
		if (
			String(snapshot.get("thoughtKind", "")).begins_with(
				"social_matter_"
			)
			and String(semantic.get("kind", "")) != "semantic_icon"
		):
			continue
		if (
			String(snapshot.get("thoughtKind", ""))
				== "activity_reaction"
			and String(semantic.get("kind", "")) != "semantic_icon"
		):
			continue
		var far_item := {
			"overlayId": "resident:%s:%s" % [resident_id, action_id],
			"kind": String(semantic.get("kind", "activity_ellipsis")),
			"sourceActionId": action_id,
			"residentId": resident_id,
			"residentName": resident_name,
			"playbackIdentity": "%s|%s|%s|%s" % [
				resident_id,
				String(snapshot.get("previewId", "")),
				String(semantic.get("phase", "")),
				String(semantic.get("iconType", "")),
			],
			"anchorKind": "resident",
			"anchorPolicy": "live_resident_head",
			"motionPolicy": "follow_resident",
			"startedAtMsec": int(snapshot.get("startedAtMsec", now_msec)),
			"expiresAtMsec": int(snapshot.get("expiresAtMsec", now_msec)),
			"confirmedRevision": int(
				snapshot.get("confirmedRevision", _world_revision)
			),
			"semanticKind": String(semantic.get("semanticKind", "")),
			"iconType": String(semantic.get("iconType", "")),
			"phase": String(semantic.get("phase", "")),
			"markerKey": String(semantic.get("markerKey", "")),
			"label": String(
				snapshot.get("label", snapshot.get("publicThought", ""))
			),
			"showLabel": zoom_band in ["middle", "near"],
			"animate": bool(semantic.get("animate", false)),
			"source": String(semantic.get("source", "world.action.line")),
			"action": _action(
				"town_hud.open_resident_action",
				_ui_route_host != null,
				"TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
				{
					"residentId": resident_id,
					"residentName": resident_name,
				},
			),
		}
		all_items.append(far_item)
		owned_resident_ids[resident_id] = true
	return {
		"available": available,
		"disabledReason": (
			"" if available else "FAR_RESIDENT_ACTIVITY_INTERFACE_MISSING"
		),
		"revision": _world_revision,
		"visibleBudget": all_items.size(),
		"aggregateCount": 0,
		"items": all_items,
	}


func _hud_live_resident_semantic(state: Dictionary) -> Dictionary:
	var presentation_value: Variant = state.get("actionPresentation")
	if presentation_value is Dictionary:
		var presentation := presentation_value as Dictionary
		var base_icon_key := String(
			presentation.get("baseIconKey", "")
		).strip_edges()
		var phase := String(presentation.get("phase", "")).strip_edges()
		if not base_icon_key.is_empty() and phase in [
			"approaching",
			"performing",
			"waiting",
			"interrupted",
			"completed",
			"failed",
		]:
			return {
				"semanticKind": "activity",
				"iconType": base_icon_key,
				"phase": phase,
				"markerKey": _hud_action_phase_marker_key(phase),
				"label": _hud_action_display_label(
					String(presentation.get("label", "")),
					phase,
					String(presentation.get("waitReason", "")),
				),
				"thoughtLabel": _hud_public_thought_text(
					String(presentation.get("publicThought", "")),
				),
				"animate": phase == "performing",
				"source": "world.resident.actionPresentation",
			}
	var cue_value: Variant = state.get("activityCue")
	var cue := (
		cue_value as Dictionary
		if cue_value is Dictionary
		else {}
	)
	var cue_phase := String(cue.get("phase", "")).strip_edges()
	if cue_phase == "approaching":
		return {
			"semanticKind": "action",
			"iconType": "walking",
			"source": "world.resident.activityCue.phase",
		}
	var cue_icon := String(
		cue.get("semanticIconType", "")
	).strip_edges()
	if (
		cue_phase == "performing"
		and cue_icon in [
			"eating",
			"working",
			"observing",
			"reading",
		]
	):
		return {
			"semanticKind": "activity",
			"iconType": cue_icon,
			"source": "world.resident.activityCue.semanticIconType",
		}
	var current_action_value: Variant = state.get("currentAction")
	var current_action := (
		current_action_value as Dictionary
		if current_action_value is Dictionary
		else {}
	)
	if (
		String(current_action.get("type", "")) == "去"
		or bool(state.get("isMoving", false))
	):
		return {
			"semanticKind": "action",
			"iconType": "walking",
			"source": "world.resident.movement",
		}
	var body_value: Variant = state.get("body")
	var body := (
		body_value as Dictionary
		if body_value is Dictionary
		else {}
	)
	if String(body.get("累", "")) == "很累":
		return {
			"semanticKind": "body",
			"iconType": "tired",
			"source": "world.resident.body",
		}
	return {}


func _hud_action_phase_marker_key(phase: String) -> String:
	match phase:
		"approaching":
			return "phase_approaching"
		"waiting":
			return "phase_waiting"
		"interrupted":
			return "phase_interrupted"
		"completed":
			return "result_completed"
		"failed":
			return "result_failed"
	return ""


func _hud_action_display_label(
	label: String,
	phase: String,
	wait_reason := "",
) -> String:
	var normalized := label.strip_edges()
	if normalized.is_empty():
		return ""
	match phase:
		"approaching":
			return normalized if normalized.begins_with("前往") else "准备去%s" % normalized
		"performing":
			return normalized if normalized.begins_with("正在") else "正在%s" % normalized
		"waiting":
			if normalized.begins_with("等待"):
				return normalized
			match wait_reason:
				"slot_busy":
					return "等待空位：%s" % normalized
				"route_blocked":
					return "暂时受阻：%s" % normalized
				"idle":
					return normalized
			return "等待%s" % normalized
		"completed":
			return normalized if normalized.begins_with("完成") else "完成%s" % normalized
		"failed":
			return normalized if "失败" in normalized or "未能" in normalized else "%s失败" % normalized
		"interrupted":
			return normalized if "中断" in normalized else "%s被中断" % normalized
	return normalized


func _hud_far_activity_semantic(snapshot: Dictionary) -> Dictionary:
	var explicit_icon := String(
		snapshot.get("semanticIconType", "")
	).strip_edges()
	if not explicit_icon.is_empty():
		var phase := String(snapshot.get("phase", "")).strip_edges()
		return {
			"kind": "semantic_icon",
			"semanticKind": "activity",
			"iconType": explicit_icon,
			"phase": phase,
			"markerKey": _hud_action_phase_marker_key(phase),
			"animate": phase == "performing",
			"source": "world.activity.semantic",
		}
	if String(snapshot.get("thoughtKind", "")) == "activity_reaction":
		return {
			"kind": "activity_ellipsis",
			"semanticKind": "",
			"iconType": "",
			"source": "agent.reaction.public_text",
		}
	if String(snapshot.get("actionType", "")) == "去":
		return {
			"kind": "semantic_icon",
			"semanticKind": "action",
			"iconType": "walking",
			"source": "world.currentAction.type",
		}
	var body := snapshot.get("body", {}) as Dictionary
	if String(body.get("累", "")) == "很累":
		return {
			"kind": "semantic_icon",
			"semanticKind": "body",
			"iconType": "tired",
			"source": "world.body.累",
		}
	return {
		"kind": "activity_ellipsis",
		"semanticKind": "",
		"iconType": "",
		"source": "world.action.line",
	}
func _hud_far_conversation_participants_visible(participant_ids: Array) -> bool:
	if not _runtime_head_anchor_call.is_valid():
		return true
	for participant_id_value: Variant in participant_ids:
		var resident_name := _resident_name_for_id(
			String(participant_id_value).strip_edges()
		)
		if resident_name.is_empty():
			return false
		var anchor := _runtime_head_anchor_call.call(resident_name) as Dictionary
		if (
			not bool(anchor.get("valid", false))
			or not bool(anchor.get("visible", true))
		):
			return false
	return true


func _capture_current_hud_far_conversations() -> void:
	if (
		_world == null
		or not _world.has_method("get_active_conversations")
		or _resident_identity_status != "confirmed"
	):
		return
	var now_msec := _hud_effective_now_msec()
	for value: Variant in _world.get_active_conversations() as Array:
		if not value is Dictionary:
			continue
		var conversation := value as Dictionary
		if not _is_resident_spectator_conversation(conversation):
			continue
		_hud_conversation_bubble_playback.ingest(conversation, now_msec)
	var visible_bubbles: Array[Dictionary] = []
	visible_bubbles.assign(
		_hud_conversation_bubble_playback.visible_items(now_msec) as Array
	)
	var visible_ids: Dictionary = {}
	var confirmed_revision := _read_world_revision()
	for bubble: Dictionary in visible_bubbles:
		var conversation_id := String(
			bubble.get("conversationId", "")
		).strip_edges()
		if conversation_id.is_empty():
			continue
		if (
			String(bubble.get("status", "active")) == "ended"
			and not _hud_far_conversation_participants_visible(
				bubble.get("participantIds", []) as Array,
			)
		):
			# 已结束且参与者已经走出视野的对话不再补画尾泡，直接交给
			# hidden_ids 清理，避免旧气泡在原地滞留。
			continue
		visible_ids[conversation_id] = true
		var existing := _hud_far_conversations.get(
			conversation_id,
			{},
		) as Dictionary
		var participant_ids: Array[String] = []
		for participant_value: Variant in bubble.get("participantIds", []) as Array:
			var identity := _spectator_participant_identity(participant_value)
			var participant_id := String(identity.get("residentId", ""))
			if participant_id.is_empty():
				participant_id = String(participant_value).strip_edges()
			if not participant_id.is_empty():
				participant_ids.append(participant_id)
		if participant_ids.size() != 2 and not existing.is_empty():
			participant_ids.clear()
			for participant_value: Variant in existing.get("participantIds", []) as Array:
				participant_ids.append(String(participant_value))
		var participant_names: Array[String] = []
		if not existing.is_empty():
			for participant_value: Variant in existing.get("participantNames", []) as Array:
				participant_names.append(String(participant_value))
		if participant_names.size() != participant_ids.size():
			participant_names.clear()
			for participant_id: String in participant_ids:
				participant_names.append(_resident_name_for_id(participant_id))
		var item := existing.duplicate(true)
		if item.is_empty():
			_hud_far_seen_conversation_ids[conversation_id] = true
			item = {
				"overlayId": "conversation:%s" % conversation_id,
				"kind": "spectator_conversation",
				"conversationId": conversation_id,
				"playbackIdentity": "conversation|%s" % conversation_id,
				"anchorKind": "resident_pair",
				"anchorPolicy": "live_resident_head",
				"motionPolicy": "follow_resident",
				"startedAtMsec": int(
					bubble.get("conversationStartedAtMsec", now_msec)
				),
				"expiresAtMsec": 0,
			}
		item["participantIds"] = participant_ids
		item["participantNames"] = participant_names
		item["bubbleText"] = String(bubble.get("bubbleText", ""))
		item["label"] = item["bubbleText"]
		item["speakerId"] = String(bubble.get("speakerId", ""))
		item["speakerName"] = String(bubble.get("speakerName", ""))
		item["turnId"] = int(bubble.get("turnId", 0))
		item["segmentIndex"] = int(bubble.get("segmentIndex", 0))
		item["playbackStatus"] = String(bubble.get("status", "active"))
		item["bubbleStartedAtMsec"] = int(
			bubble.get("bubbleStartedAtMsec", now_msec)
		)
		item["confirmedRevision"] = confirmed_revision
		_hud_far_conversations[conversation_id] = item
		if not _hud_far_conversation_order.has(conversation_id):
			_hud_far_conversation_order.push_back(conversation_id)
	_hud_far_confirmed_revision = maxi(
		_hud_far_confirmed_revision,
		confirmed_revision,
	)
	var hidden_ids: Array[String] = []
	for conversation_id_value: Variant in _hud_far_conversation_order:
		var conversation_id := String(conversation_id_value)
		if not visible_ids.has(conversation_id):
			hidden_ids.append(conversation_id)
	for conversation_id in hidden_ids:
		_hud_far_conversations.erase(conversation_id)
		_hud_far_conversation_order.erase(conversation_id)


func _clear_hud_far_resident_activity(clear_seen: bool) -> void:
	_hud_far_conversations.clear()
	_hud_far_conversation_order.clear()
	if clear_seen:
		_hud_far_seen_conversation_ids.clear()
		_hud_far_confirmed_revision = -1


func _hud_resident_directory(runtime_state: Dictionary) -> Dictionary:
	var state_by_name: Dictionary = {}
	var ordered_names: Array[String] = []
	var signature: Array = []
	for value: Variant in runtime_state.get("residents", []) as Array:
		if not (value is Dictionary):
			continue
		var state := value as Dictionary
		var resident_name := String(state.get("name", "")).strip_edges()
		if resident_name.is_empty() or state_by_name.has(resident_name):
			continue
		state_by_name[resident_name] = state
		ordered_names.append(resident_name)
		signature.append([
			resident_name,
			String(state.get("currentPlace", "")),
			String(state.get("spaceId", "")),
			String(state.get("doing", "")),
		])
	var remaining_names: Array[String] = []
	for resident_name_value: Variant in _resident_id_by_name:
		var resident_name := String(resident_name_value)
		if not state_by_name.has(resident_name):
			remaining_names.append(resident_name)
	remaining_names.sort()
	ordered_names.append_array(remaining_names)
	var followed_name := String(runtime_state.get("followedResident", ""))
	var selected_resident_id := _resident_id_for_name(followed_name)
	signature.append(["selected", selected_resident_id])
	if (
		signature == _hud_resident_directory_signature
		and not _hud_resident_directory_cache.is_empty()
	):
		return _hud_resident_directory_cache.duplicate(true)
	var items: Array[Dictionary] = []
	for resident_name in ordered_names:
		var resident_id := _resident_id_for_name(resident_name)
		if resident_id.is_empty():
			continue
		var state := state_by_name.get(resident_name, {}) as Dictionary
		var location_label := String(state.get("currentPlace", "")).strip_edges()
		if location_label.is_empty():
			location_label = String(state.get("spaceId", "")).strip_edges()
		var behavior_label := String(state.get("doing", "")).strip_edges()
		# ResidentDirectoryDrawer 默认收起。头像资源只在玩家打开目录时加载，
		# 避免首个 HUD 刷新同步读取 15 张图片，阻塞正常游玩帧。
		var portrait_texture: Texture2D = null
		if _resident_portraits_loaded:
			portrait_texture = _resident_portrait_texture(resident_id)
		items.append({
			"residentId": resident_id,
			"residentName": resident_name,
			"behaviorLabel": behavior_label,
			"behaviorShortLabel": _hud_behavior_short_label(behavior_label),
			"locationLabel": location_label,
			"portraitTexture": portrait_texture,
			"portraitStatus": "ready" if portrait_texture != null else "unavailable",
			"portraitFallbackText": _resident_portrait_fallback(resident_name),
			"selected": resident_id == selected_resident_id,
		})
	var result := {
		"available": not items.is_empty(),
		"totalCount": items.size(),
		"visibleBudget": 6,
		"selectedResidentId": selected_resident_id,
		"items": items,
	}
	_hud_resident_directory_signature = signature
	_hud_resident_directory_cache = result
	return result.duplicate(true)


func _hud_behavior_short_label(value: String) -> String:
	var normalized := value.strip_edges()
	for separator in ["\r", "\n", "\t"]:
		normalized = normalized.replace(separator, " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	if normalized.length() <= HUD_RESIDENT_DIRECTORY_SHORT_LABEL_MAX_CHARACTERS:
		return normalized
	return normalized.left(
		HUD_RESIDENT_DIRECTORY_SHORT_LABEL_MAX_CHARACTERS - 1
	) + "…"


func _hud_place_directory(runtime_state: Dictionary) -> Dictionary:
	if not _hud_place_directory_static_loaded:
		_hud_place_directory_static_items = _load_hud_place_directory_items()
		_hud_place_directory_static_loaded = true
	var resident_count_by_place: Dictionary = {}
	for value: Variant in runtime_state.get("residents", []) as Array:
		if not (value is Dictionary):
			continue
		var place_name := String(
			(value as Dictionary).get("currentPlace", "")
		).strip_edges()
		if place_name.is_empty():
			continue
		resident_count_by_place[place_name] = (
			int(resident_count_by_place.get(place_name, 0)) + 1
		)
	var signature: Array = []
	for static_item: Dictionary in _hud_place_directory_static_items:
		var place_name := String(static_item.get("placeName", ""))
		signature.append([
			place_name,
			int(resident_count_by_place.get(place_name, 0)),
		])
	if (
		signature == _hud_place_directory_signature
		and not _hud_place_directory_cache.is_empty()
	):
		return _hud_place_directory_cache.duplicate(true)
	var items: Array[Dictionary] = []
	for static_item: Dictionary in _hud_place_directory_static_items:
		var item := static_item.duplicate(true)
		var place_name := String(item.get("placeName", ""))
		item["residentCount"] = int(
			resident_count_by_place.get(place_name, 0)
		)
		items.append(item)
	var result := {
		"available": not items.is_empty(),
		"totalCount": items.size(),
		"visibleBudget": 6,
		"items": items,
	}
	_hud_place_directory_signature = signature
	_hud_place_directory_cache = result
	return result.duplicate(true)


func _load_hud_place_directory_items() -> Array[Dictionary]:
	var details: Array = []
	if _world != null and _world.has_method("get_all_place_details"):
		details = _world.get_all_place_details() as Array
	var detail_by_name: Dictionary = {}
	var remaining_names: Array[String] = []
	for value: Variant in details:
		if not (value is Dictionary):
			continue
		var detail := value as Dictionary
		var place_name := String(detail.get("name", "")).strip_edges()
		if place_name.is_empty() or detail_by_name.has(place_name):
			continue
		detail_by_name[place_name] = detail
		remaining_names.append(place_name)
	remaining_names.sort()
	var ordered_names: Array[String] = []
	for place_name: String in HUD_PLACE_DIRECTORY_PRIMARY_ORDER:
		if not detail_by_name.has(place_name):
			continue
		ordered_names.append(place_name)
		remaining_names.erase(place_name)
	ordered_names.append_array(remaining_names)
	var items: Array[Dictionary] = []
	for place_name: String in ordered_names:
		var detail := detail_by_name.get(place_name, {}) as Dictionary
		items.append({
			"placeName": place_name,
			"placeType": String(detail.get("type", "地点")),
			"spaceId": String(detail.get("spaceId", "")),
			"focusable": true,
		})
	return items


func _resident_portrait_texture(resident_id: String) -> Texture2D:
	_ensure_resident_portraits_loaded()
	return _resident_portrait_by_id.get(resident_id) as Texture2D


func _resident_portrait_ref(resident_id: String) -> String:
	_ensure_resident_portraits_loaded()
	return String(_resident_portrait_ref_by_id.get(resident_id, ""))


func _ensure_resident_portraits_loaded() -> void:
	if not _resident_portraits_loaded:
		_resident_portraits_loaded = true
		var catalog := RESIDENT_CATALOG.load_catalog()
		for value: Variant in catalog.get("residents", []) as Array:
			if not (value is Dictionary):
				continue
			var entry := value as Dictionary
			var entry_id := String(entry.get("residentId", ""))
			var presentation := entry.get("presentation", {}) as Dictionary
			var portrait_path := String(presentation.get("portraitPath", ""))
			var sprite_path := (
				portrait_path
				if not portrait_path.is_empty()
				else String(presentation.get("spritePath", ""))
			)
			if entry_id.is_empty() or not ResourceLoader.exists(sprite_path):
				continue
			_resident_portrait_ref_by_id[entry_id] = sprite_path
			var texture := load(sprite_path) as Texture2D
			if texture == null:
				continue
			if not portrait_path.is_empty():
				_resident_portrait_by_id[entry_id] = texture
			else:
				var portrait := AtlasTexture.new()
				portrait.atlas = texture
				portrait.region = Rect2(0, 0, 64, 64)
				_resident_portrait_by_id[entry_id] = portrait
		_load_session_resident_portraits()


func _load_session_resident_portraits() -> void:
	if not FileAccess.file_exists(RESIDENT_WARDROBE_CATALOG_PATH):
		return
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(RESIDENT_WARDROBE_CATALOG_PATH)
	)
	if not parsed is Dictionary:
		return
	var portrait_by_appearance: Dictionary = {}
	for loadout_value: Variant in (parsed as Dictionary).get("loadouts", []) as Array:
		if not loadout_value is Dictionary:
			continue
		var loadout := loadout_value as Dictionary
		var appearance_id := String(loadout.get("appearanceId", "")).strip_edges()
		var portrait_path := String(loadout.get("portraitPath", "")).strip_edges()
		if (
			appearance_id.is_empty()
			or portrait_path.is_empty()
			or not ResourceLoader.exists(portrait_path)
		):
			continue
		portrait_by_appearance[appearance_id] = portrait_path
	var opening := _session_config.get("openingConfig", {}) as Dictionary
	var residents_value: Variant = opening.get(
		"residents",
		_session_config.get("residentIdentities", []),
	)
	if not residents_value is Array:
		return
	for resident_value: Variant in residents_value as Array:
		if not resident_value is Dictionary:
			continue
		var resident := resident_value as Dictionary
		var resident_id := String(resident.get("residentId", "")).strip_edges()
		var attributes := resident.get("attributes", {}) as Dictionary
		var appearance_id := String(attributes.get("appearance", "")).strip_edges()
		var portrait_path := String(
			portrait_by_appearance.get(appearance_id, "")
		)
		if resident_id.is_empty() or portrait_path.is_empty():
			continue
		var texture := ResourceLoader.load(portrait_path, "Texture2D") as Texture2D
		if texture == null:
			continue
		_resident_portrait_ref_by_id[resident_id] = portrait_path
		_resident_portrait_by_id[resident_id] = texture


func _hud_indoor_items(runtime_state: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for resident_name_value in runtime_state.get("visibleIndoorBadges", []) as Array:
		var resident_name := str(resident_name_value)
		var resident_id := _resident_id_for_name(resident_name)
		if resident_id.is_empty():
			continue
		items.append({
			"residentId": resident_id,
			"name": resident_name,
		})
	return items


func _hud_event_overlay(announcements: Dictionary) -> Dictionary:
	var source_items := announcements.get("items", []) as Array
	var items: Array[Dictionary] = []
	for value in source_items:
		if not (value is Dictionary):
			continue
		var announcement := value as Dictionary
		var schedule_label := String(
			announcement.get("scheduleLabel", ""),
		).strip_edges()
		var schedule_status := String(
			announcement.get("scheduleStatus", ""),
		).strip_edges()
		var summary := str(announcement.get("text", ""))
		if not schedule_label.is_empty():
			summary += "\n%s · %s" % [schedule_label, schedule_status]
		items.append({
			"eventId": str(announcement.get("announcement_id", "")),
			"title": str(announcement.get("text", "")),
			"summary": summary,
			"direction": "",
			"screenAnchor": {},
			"targetId": "",
		})
	return {
		"visible": not items.is_empty(),
		"unreadCount": items.size(),
		"items": items,
	}


func _hud_offscreen_activity_disabled() -> Dictionary:
	# Product ruling: ordinary residents never create off-screen HUD entries.
	# The section remains as an empty compatibility envelope for the approved
	# observer HUD. Urgent world events continue through eventOverlay/log.
	return {
		"available": false,
		"disabledReason": "PRODUCT_OFFSCREEN_RESIDENT_ACTIVITY_DISABLED",
		"visibleBudget": HUD_OFFSCREEN_VISIBLE_BUDGET,
		"aggregateCount": 0,
		"unreadCount": 0,
		"confirmedRevision": _world_revision,
		"items": [],
	}


func _build_session_view_model(operation: Dictionary, error: Dictionary) -> Dictionary:
	var runtime_state: Dictionary = {}
	if _runtime != null and _runtime.has_method("get_session_summary"):
		runtime_state = _runtime.call("get_session_summary")
	var is_started := bool(runtime_state.get("started", false))
	var continue_reason := _continue_disabled_reason(runtime_state)
	return _base_view_model(
		"session",
		("ready" if is_started else "disabled") if error.is_empty() else "error",
		int(runtime_state.get("revision", 0)),
		{
			"mode": str(runtime_state.get("mode", "new_game")),
			"sessionId": str(runtime_state.get("sessionId", "")),
			"canEnterTown": is_started,
			"residentCount": int(runtime_state.get("residentCount", 0)),
			"providerStatus": "unavailable",
			"loadSummary": {},
			"draftRevision": 0,
			"identityStatus": str(runtime_state.get("identityStatus", _resident_identity_status)),
			"validationMode": str(runtime_state.get("validationMode", "development")),
			"source": str(_session_config.get("source", "runtime")),
			"capabilityMode": str(_session_config.get("capabilityMode", "development")),
			"formalReady": bool(_session_config.get("formalReady", false)),
			"internalPlaytest": bool(_session_config.get("internalPlaytest", false)),
		},
		{
			"newGame": _action("session.new_game", false, PROVIDER_HEALTH_ERROR_CODE),
			"continue": _action("session.continue", false, continue_reason),
		},
		operation,
		error
	)


func _build_save_view_model(operation: Dictionary, error: Dictionary) -> Dictionary:
	var snapshot := _read_save_snapshot()
	var can_save := bool(snapshot.get("canSave", false))
	var can_continue := false
	var disabled_reason := str(snapshot.get("disabledReason", ""))
	if disabled_reason.is_empty() and not can_save:
		disabled_reason = (
			SESSION_SAVE_SERVICE_MISSING
			if _session_save_service == null
			else "SESSION_SAVE_NOT_AVAILABLE"
		)
	var continue_reason := _continue_disabled_reason()
	var effective_error := error
	if effective_error.is_empty() and _session_save_service == null:
		effective_error = _error_payload(
			SESSION_SAVE_SERVICE_MISSING,
			false,
			"Session save service 尚未绑定。",
		)
	var revision := int(snapshot.get("revision", 0))
	return _base_view_model(
		"save",
		"ready" if can_save else "disabled",
		revision,
		{
			"slots": (snapshot.get("slots", []) as Array).duplicate(true),
			"selectedSaveId": str(snapshot.get("selectedSaveId", "")),
			"canSave": can_save,
			"canContinue": can_continue,
			"source": str(snapshot.get("source", _session_config.get("source", "runtime"))),
			"capabilityMode": str(snapshot.get("capabilityMode", _session_config.get("capabilityMode", "development"))),
			"formalReady": bool(snapshot.get("formalReady", false)),
		},
		{
			"create": _action("save.create", can_save, disabled_reason),
			"continue": _action("session.continue", false, continue_reason),
		},
		operation,
		effective_error,
	)


func _read_save_snapshot() -> Dictionary:
	if _session_save_service == null or not _session_save_service.has_method("get_save_snapshot"):
		return {}
	var value: Variant = _session_save_service.call("get_save_snapshot")
	if not (value is Dictionary):
		return {
			"canSave": false,
			"disabledReason": "SESSION_SAVE_SNAPSHOT_INVALID",
		}
	return (value as Dictionary).duplicate(true)


func _continue_disabled_reason(runtime_state: Dictionary = {}) -> String:
	var effective_state := runtime_state
	if effective_state.is_empty() and _runtime != null and _runtime.has_method("get_session_summary"):
		effective_state = _runtime.call("get_session_summary") as Dictionary
	var content_status := effective_state.get("contentStatus", {}) as Dictionary
	var pending_sections := content_status.get("pendingSections", []) as Array
	if pending_sections.has("indoorProps") or not bool(content_status.get("worldReady", true)):
		return "WORLD_DATA_INCOMPLETE"
	var save_snapshot := _read_save_snapshot()
	var service_reason := str(save_snapshot.get("continueDisabledReason", ""))
	if not service_reason.is_empty():
		return service_reason
	return SESSION_CONTINUE_HOST_ROUTING_REQUIRED


func _refresh_save_scopes() -> void:
	var previous_operation := _idle_operation()
	if _view_models.has("save"):
		previous_operation = (
			(_view_models["save"] as Dictionary).get("operation", _idle_operation())
			as Dictionary
		).duplicate(true)
	_set_view_model(
		"save",
		_build_save_view_model(previous_operation, {}),
		true,
	)
	_refresh_scope("session", true)
	_refresh_scope("pause_menu", true)


func _build_pause_menu_view_model(operation: Dictionary, error: Dictionary) -> Dictionary:
	var runtime_state: Dictionary = {}
	if _runtime != null and _runtime.has_method("get_session_summary"):
		runtime_state = _runtime.call("get_session_summary")
	var resident_count := int(runtime_state.get("residentCount", 0))
	var capability_mode := str(_session_config.get("capabilityMode", "development"))
	var source := str(_session_config.get("source", "runtime"))
	var formal_ready := bool(_session_config.get("formalReady", false))
	var save_snapshot := _read_save_snapshot()
	var save_available := bool(save_snapshot.get("canSave", false))
	var save_status_reason := str(
		save_snapshot.get("disabledReason", SESSION_SAVE_SERVICE_MISSING)
	)
	if save_available:
		save_status_reason = ""
	var load_available := formal_ready and save_available
	var load_disabled_reason := (
		"" if load_available else (
			save_status_reason
			if not save_status_reason.is_empty()
			else "SESSION_LOAD_REQUIRES_FORMAL_SESSION"
		)
	)
	var environment := _scope_data("environment")
	var avatar := _scope_data("avatar")
	var slot_id := str(_session_config.get("slotId", ""))
	var slot_name := str({
		"town-main": "小镇 1",
		"town-2": "小镇 2",
		"town-3": "小镇 3",
	}.get(slot_id, "当前小镇"))
	var avatar_mode := str(avatar.get("mode", "observer"))
	var avatar_mode_label := (
		"观察模式" if avatar_mode == "observer" else "化身模式"
	)
	var provider_vm := get_view_model("provider_settings")
	var provider_data := provider_vm.get("data", {}) as Dictionary
	var provider_count := (provider_data.get("providers", []) as Array).size()
	var provider_model_count := 0
	for provider_value: Variant in provider_data.get("providers", []) as Array:
		if provider_value is Dictionary:
			provider_model_count += (
				(provider_value as Dictionary).get("models", []) as Array
			).size()
	var provider_route_available := _provider_settings_service != null
	var resident_models_available := _resident_model_assignment_service != null
	var audio_vm := get_view_model("audio_display_settings")
	var audio_data := audio_vm.get("data", {}) as Dictionary
	var audio := audio_data.get("audio", {}) as Dictionary
	return _base_view_model(
		"pause_menu",
		"ready",
		maxi(_world_revision, 0),
		{
			"source": source,
			"capabilityMode": capability_mode,
			"formalReady": formal_ready,
			"entries": [
				{"id": "return_game", "icon": "resume", "label": "继续游戏", "tone": "primary"},
				{"id": "save_game", "icon": "save", "label": "保存游戏", "tone": "quiet" if save_available else "disabled", "disabledReason": save_status_reason},
				{"id": "load_game", "icon": "load", "label": "加载游戏", "tone": "quiet" if load_available else "disabled", "disabledReason": load_disabled_reason},
				{"id": "resident_models", "icon": "resident_models", "label": "居民模型", "tone": "quiet" if resident_models_available else "disabled", "disabledReason": "" if resident_models_available else "RESIDENT_MODEL_ASSIGNMENT_SERVICE_NOT_BOUND"},
				{"id": "game_settings", "icon": "settings", "label": "游戏设置", "tone": "quiet"},
			],
			"currentTownSummary": {
				"slotId": slot_id,
				"slotName": slot_name,
				"day": int(environment.get("day", 0)),
				"clock": str(environment.get("clock", "")),
				"weatherId": str(environment.get("weatherId", "")),
				"weatherLabel": str(environment.get("weatherLabel", "")),
				"residentCount": resident_count,
				"avatarMode": avatar_mode,
				"avatarModeLabel": avatar_mode_label,
			},
			"llmSummary": {
				"status": "available" if _gateway != null else "unavailable",
				"providerCount": provider_count,
				"modelCount": provider_model_count,
				"source": source,
				"capabilityMode": capability_mode,
				"formalReady": formal_ready,
			},
			"audioVideoSummary": {
				"masterVolume": float(audio.get("masterPercent", 0)) / 100.0,
				"musicVolume": float(audio.get("musicPercent", 0)) / 100.0,
				"ambienceVolume": float(audio.get("ambiencePercent", 0)) / 100.0,
				"sfxVolume": float(audio.get("sfxPercent", 0)) / 100.0,
				"uiVolume": float(audio.get("uiPercent", 0)) / 100.0,
				"muted": bool(audio.get("muted", false)),
				"source": source,
				"capabilityMode": capability_mode,
				"formalReady": formal_ready,
			},
			"contentSummary": {
				"residentCount": resident_count,
				"residentCapacity": 15,
				"mapPackId": "town",
				"mapPackName": "固定单地图 · 地图包冻结",
				"source": source,
				"capabilityMode": capability_mode,
				"formalReady": formal_ready,
			},
		},
		{
			"returnGame": _action("lifecycle.resume", true, "", {"reason": "main_menu"}),
			"saveGame": _action("save.create", save_available, save_status_reason),
			"openLoadGame": _action(
				"pause_menu.open_load_game",
				load_available,
				load_disabled_reason,
			),
			"openGameSettings": _action("pause_menu.open_audio_video", true),
			"openResidentModels": _action(
				"pause_menu.open_resident_models",
				resident_models_available,
				"" if resident_models_available else "RESIDENT_MODEL_ASSIGNMENT_SERVICE_NOT_BOUND",
			),
			"returnToStart": _action("pause_menu.return_to_start", true),
			"quitGame": _action("pause_menu.quit_game", true),
		},
		operation,
		error,
	)


func _execute_intent(intent: String, payload: Dictionary) -> Dictionary:
	match intent.get_slice(".", 0):
		"lifecycle":
			return _execute_lifecycle_intent(intent, payload)
		"environment":
			return _execute_environment_intent(intent, payload)
		"announcements":
			return _execute_announcements_intent(intent, payload)
		"conversation":
			return _execute_conversation_intent(intent, payload)
		"avatar":
			return _execute_avatar_intent(intent, payload)
		"town_hud":
			return _execute_town_hud_intent(intent, payload)
		"session":
			return _execute_session_intent(intent, payload)
		"save":
			return _execute_save_intent(intent, payload)
		"pause_menu":
			return _execute_pause_menu_intent(intent, payload)
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _execute_lifecycle_intent(intent: String, payload: Dictionary) -> Dictionary:
	match intent:
		"lifecycle.pause":
			return _call_runtime_lifecycle("pause", str(payload.get("reason", "manual")))
		"lifecycle.resume":
			return _call_runtime_lifecycle("resume", str(payload.get("reason", "manual")))
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _execute_environment_intent(intent: String, payload: Dictionary) -> Dictionary:
	match intent:
		"environment.weather_change":
			if _world != null and _world.has_method("set_weather"):
				return _normalize_command_result(_world.set_weather(str(payload.get("weatherId", ""))))
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _execute_announcements_intent(intent: String, payload: Dictionary) -> Dictionary:
	match intent:
		"announcements.publish":
			if _runtime != null and _runtime.has_method("publish_player_announcement"):
				return _normalize_command_result(_runtime.call(
					"publish_player_announcement",
					str(payload.get("text", ""))
				))
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _execute_conversation_intent(intent: String, payload: Dictionary) -> Dictionary:
	if (
		intent in [
			"conversation.start",
			"conversation.reply",
			"conversation.end",
			"conversation.reject",
		]
		and _spectator_panel_open
	):
		return _local_failure("SPECTATOR_READ_ONLY", false)
	match intent:
		"conversation.start":
			if _runtime != null and _runtime.has_method("player_start_conversation"):
				var avatar_state := _world.get_player_avatar_state() as Dictionary if (
					_world != null
					and _world.has_method("get_player_avatar_state")
				) else {}
				var avatar_id := String(
					avatar_state.get("residentId", DEFAULT_PLAYER_AVATAR_ID)
				).strip_edges()
				if _avatar_in_active_brawl(avatar_id):
					return _local_failure("AVATAR_CONFLICT_ACTIVE", false)
				_pending_player_ended_conversation.clear()
				_local_player_close_conversation_id = ""
				var resident_id := str(payload.get("residentId", "")).strip_edges()
				if resident_id.is_empty():
					resident_id = _focused_nearby_resident_id
				var resident_name := _resident_name_for_id(resident_id)
				if resident_name.is_empty():
					return _local_failure("RESIDENT_IDENTITY_NOT_FOUND", false)
				return _normalize_command_result(_runtime.call(
					"player_start_conversation",
					resident_name,
					str(payload.get("say", "")),
					str(payload.get("narration", "旅行者开口搭话"))
				))
		"conversation.reply":
			return _execute_conversation_reply_intent(payload)
		"conversation.end":
			if _runtime != null and _runtime.has_method("player_end_conversation"):
				var conversation_id := _active_conversation_id()
				_local_player_close_conversation_id = conversation_id
				var end_result := _normalize_command_result(_runtime.call(
					"player_end_conversation",
					conversation_id,
					str(payload.get("narration", "旅行者结束交谈"))
				))
				if bool(end_result.get("ok", false)):
					_pending_player_ended_conversation.clear()
				_local_player_close_conversation_id = ""
				return end_result
		"conversation.reject":
			if _runtime != null and _runtime.has_method("player_reject_conversation"):
				var conversation_id := _active_conversation_id()
				_local_player_close_conversation_id = conversation_id
				var reject_result := _normalize_command_result(_runtime.call(
					"player_reject_conversation",
					conversation_id,
					str(payload.get("narration", "旅行者没有接话"))
				))
				if bool(reject_result.get("ok", false)):
					_pending_player_ended_conversation.clear()
				_local_player_close_conversation_id = ""
				return reject_result
		"conversation.dismiss_ended":
			if _pending_player_ended_conversation.is_empty():
				return _local_failure("NO_ENDED_CONVERSATION_TO_DISMISS", false)
			_pending_player_ended_conversation.clear()
			_conversation_wait_started_msec = 0
			_conversation_network_error.clear()
			_refresh_scope("conversation", true)
			return _success_result()
		"conversation.retry":
			_conversation_network_error.clear()
			_conversation_wait_started_msec = Time.get_ticks_msec()
			# TownRuntime already drains one Agent request per frame. Let the next
			# frame pick up this retry instead of synchronously draining every
			# queued resident request from the button callback.
			_refresh_scope("conversation", true)
			return _success_result()
		"conversation.spectator.select":
			return _select_spectator_conversation(payload)
		"conversation.spectator.close":
			_spectator_panel_open = false
			_spectator_selected_conversation_id = ""
			_hud_conversation_bubble_playback.set_paused(
				false,
				_hud_effective_now_msec(),
			)
			_refresh_scope("conversation", true)
			return _success_result()
		"conversation.spectator.retry":
			if not _spectator_interface_available():
				return _local_failure("SPECTATOR_INTERFACE_MISSING", false)
			var conversation_view_model := get_view_model("conversation")
			var spectator_error: Variant = conversation_view_model.get("error")
			if (
				not spectator_error is Dictionary
				or not bool((spectator_error as Dictionary).get("retryable", false))
			):
				return _local_failure("NO_RETRYABLE_ERROR", false)
			_refresh_scope("conversation", true)
			return _success_result()
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _execute_avatar_intent(intent: String, payload: Dictionary) -> Dictionary:
	match intent:
		"avatar.focus_target":
			return _focus_nearby_target(payload)
		"avatar.attack_target":
			return _attack_avatar_target(payload)
		"avatar.enter_mode":
			if _runtime != null and _runtime.has_method("enter_avatar_mode"):
				return _normalize_command_result(_runtime.call("enter_avatar_mode"))
		"avatar.exit_mode", "avatar.switch_to_overview":
			if _runtime != null and _runtime.has_method("exit_avatar_mode"):
				return _normalize_command_result(_runtime.call("exit_avatar_mode"))
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _execute_town_hud_intent(intent: String, payload: Dictionary) -> Dictionary:
	match intent:
		"town_hud.ensure_resident_directory_portraits":
			_ensure_resident_portraits_loaded()
			_hud_resident_directory_signature.clear()
			_hud_resident_directory_cache.clear()
			_refresh_scope("town_hud", true)
			return _success_result()
		"town_hud.toggle_avatar":
			return _toggle_hud_avatar_mode()
		"town_hud.set_time_speed":
			if _world == null or not _world.has_method("get_lifecycle_state"):
				return _local_failure("WORLD_NOT_RUNNING", false)
			var lifecycle_state := _world.get_lifecycle_state() as Dictionary
			if not bool(lifecycle_state.get("started", false)):
				return _local_failure("WORLD_NOT_RUNNING", false)
			if not _world.has_method("set_simulation_speed"):
				return _local_failure("SIMULATION_SPEED_INTERFACE_MISSING", false)
			var multiplier := int(payload.get("multiplier", 0))
			if not multiplier in [1, 2, 3]:
				return _normalize_command_result(
					_world.set_simulation_speed(multiplier)
				)
			# The time controls form one mutually exclusive group: selecting 1x/2x/3x
			# after pressing pause must resume manual time control as well. Other pause
			# reasons (menus and editors) remain owned by their corresponding hosts.
			var pause_reasons := (
				lifecycle_state.get("pauseReasons", []) as Array
			)
			if pause_reasons.has("manual"):
				var resume_result := _call_runtime_lifecycle("resume", "manual")
				if not bool(resume_result.get("ok", false)):
					return resume_result
			return _normalize_command_result(
				_world.set_simulation_speed(multiplier)
			)
		"town_hud.select_tool":
			var tool_id := String(payload.get("toolId", ""))
			if tool_id == "avatar":
				return _toggle_hud_avatar_mode()
			if tool_id in ["weather_control", "town_log", "more"]:
				return _success_result()
			return _local_failure("TOWN_HUD_TOOL_UNKNOWN", false)
		"town_hud.open_event":
			if _runtime != null and _runtime.has_method("open_announcement_panel"):
				_runtime.call("open_announcement_panel")
				return _success_result()
		"town_hud.open_weather":
			if _runtime != null and _runtime.has_method("open_weather_panel"):
				_runtime.call("open_weather_panel")
				return _success_result()
		"town_hud.open_resident_management":
			return _success_result()
		"town_hud.open_place_focus":
			if _runtime == null or not _runtime.has_method("request_observe_place"):
				return _local_failure("PLACE_OBSERVATION_INTERFACE_MISSING", false)
			var place_name := String(payload.get("placeName", "")).strip_edges()
			if place_name.is_empty():
				return _local_failure("PLACE_NAME_REQUIRED", false)
			return _normalize_command_result(
				_runtime.call("request_observe_place", place_name)
			)
		"town_hud.camera_follow":
			return _execute_hud_camera_follow(payload)
		"town_hud.camera_unfollow":
			if _runtime != null and _runtime.has_method("cancel_resident_follow"):
				_runtime.call("cancel_resident_follow")
				return _success_result()
		"town_hud.camera_zoom_in":
			if _runtime != null and _runtime.has_method("zoom_observer_camera"):
				return _normalize_command_result(
					_runtime.call("zoom_observer_camera", 1)
				)
		"town_hud.camera_zoom_out":
			if _runtime != null and _runtime.has_method("zoom_observer_camera"):
				return _normalize_command_result(
					_runtime.call("zoom_observer_camera", -1)
				)
		"town_hud.camera_reset":
			if _runtime != null and _runtime.has_method("reset_observer_camera"):
				return _normalize_command_result(
					_runtime.call("reset_observer_camera")
				)
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _execute_session_intent(intent: String, payload: Dictionary) -> Dictionary:
	match intent:
		"session.new_game":
			var validation := validate_new_game_draft(payload)
			if not bool(validation.get("ok", false)):
				return validation
			return _local_failure(PROVIDER_HEALTH_ERROR_CODE, false)
		"session.continue":
			return _local_failure(_continue_disabled_reason(), false)
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _execute_save_intent(intent: String, payload: Dictionary) -> Dictionary:
	match intent:
		"save.create":
			return _execute_save_create(payload)
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _execute_pause_menu_intent(intent: String, _payload: Dictionary) -> Dictionary:
	match intent:
		"pause_menu.open_audio_video", "pause_menu.open_load_game", "pause_menu.open_resident_models", "pause_menu.return_to_start", "pause_menu.quit_game":
			return _success_result()
		"pause_menu.open_save_status", "pause_menu.open_residents_map_pack":
			return _local_failure("ROUTE_NOT_CONNECTED", false)
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _execute_conversation_reply_intent(payload: Dictionary) -> Dictionary:
	if _runtime != null and _runtime.has_method("player_reply_conversation"):
		var photo_ref := str(payload.get("photoRef", "")).strip_edges()
		var photo_mime_type := str(
			payload.get("photoMimeType", "")
		).strip_edges()
		if photo_ref.is_empty() != photo_mime_type.is_empty():
			return _local_failure("PHOTO_PAYLOAD_INVALID", false)
		var resident_id := _active_conversation_resident_id()
		var photos: Array = []
		if not photo_ref.is_empty():
			if (
				resident_id.is_empty()
				or _gateway == null
				or not _gateway.has_method(
					"can_attach_photo_for_resident"
				)
				or not bool(_gateway.call(
					"can_attach_photo_for_resident",
					resident_id,
				))
			):
				return _local_failure(
					"PHOTO_CAPABILITY_UNAVAILABLE",
					false,
				)
			if (
				not _gateway.has_method(
					"has_staged_conversation_photo"
				)
				or not bool(_gateway.call(
					"has_staged_conversation_photo",
					resident_id,
					photo_ref,
					photo_mime_type,
				))
			):
				return _local_failure("PHOTO_REF_NOT_STAGED", false)
			photos.append({
				"ref": photo_ref,
				"mime_type": photo_mime_type,
			})
			if (
				not _gateway.has_method(
					"prepare_conversation_photo_commit"
				)
				or not bool(_gateway.call(
					"prepare_conversation_photo_commit",
					resident_id,
					photo_ref,
					photo_mime_type,
				))
			):
				return _local_failure("PHOTO_COMMIT_FAILED", true)
		var reply_result: Dictionary
		if not photos.is_empty():
			if not _runtime.has_method(
				"player_reply_conversation_with_photos"
			):
				return _local_failure("PHOTO_INTERFACE_MISSING", false)
			reply_result = _normalize_command_result(_runtime.call(
				"player_reply_conversation_with_photos",
				_active_conversation_id(),
				str(payload.get("say", "")),
				str(
					payload.get(
						"narration",
						"旅行者继续交谈",
					)
				),
				photos,
				false,
			))
		else:
			reply_result = _normalize_command_result(_runtime.call(
				"player_reply_conversation",
				_active_conversation_id(),
				str(payload.get("say", "")),
				str(
					payload.get(
						"narration",
						"旅行者继续交谈",
					)
				),
				false,
			))
		if (
			bool(reply_result.get("ok", false))
			and not photo_ref.is_empty()
			and _gateway.has_method("commit_conversation_photo")
		):
			var photo_committed := bool(_gateway.call(
				"commit_conversation_photo",
				resident_id,
				photo_ref,
				photo_mime_type,
			))
			if not photo_committed:
				push_warning(
					"Conversation photo remained staged after "
					+ "the World accepted the turn."
				)
		return reply_result
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _select_spectator_conversation(payload: Dictionary) -> Dictionary:
	if not _spectator_interface_available():
		return _local_failure("SPECTATOR_INTERFACE_MISSING", false)
	var conversation_id := str(payload.get("conversationId", "")).strip_edges()
	if conversation_id.is_empty():
		return _local_failure("SPECTATOR_SELECTION_REJECTED", false)
	var conversation := _world.get_conversation(conversation_id) as Dictionary
	if (
		conversation.is_empty()
		or str(conversation.get("status", "")) not in ["active", "ended"]
		or not _is_resident_spectator_conversation(conversation)
	):
		return _local_failure("SPECTATOR_SELECTION_REJECTED", false)
	var connected: Dictionary = {}
	for resident_name in _connected_resident_names():
		connected[resident_name] = true
	for value: Variant in conversation.get("participants", []) as Array:
		if not _spectator_participant_connected(
			_spectator_participant_identity(value),
			connected,
		):
			return _local_failure("SPECTATOR_PARTICIPANT_NOT_CONNECTED", false)
	_spectator_selected_conversation_id = conversation_id
	_spectator_panel_open = true
	_hud_conversation_bubble_playback.set_paused(
		true,
		_hud_effective_now_msec(),
	)
	return _success_result()
	return _local_failure("UI_INTENT_NOT_AVAILABLE", false)


func _execute_save_create(payload: Dictionary) -> Dictionary:
	if _session_save_service == null:
		return _local_failure(SESSION_SAVE_SERVICE_MISSING, false)
	if not _session_save_service.has_method("create_save"):
		return _local_failure("SESSION_SAVE_SERVICE_CONTRACT_INVALID", false)
	if (
		_ui_route_host != null
		and _ui_route_host.has_method("prepare_for_world_save")
	):
		var close_result := _ui_route_host.call(
			"prepare_for_world_save",
			String(payload.get("reason", "manual_save")),
		) as Dictionary
		if not bool(close_result.get("ok", false)):
			return close_result
	var snapshot := _read_save_snapshot()
	if not bool(snapshot.get("canSave", false)):
		return _local_failure(
			str(snapshot.get("disabledReason", "SESSION_SAVE_NOT_AVAILABLE")),
			false,
		)
	var result := _normalize_command_result(
		_session_save_service.call("create_save", payload.duplicate(true))
	)
	_refresh_save_scopes()
	return result


func _execute_hud_camera_follow(payload: Dictionary) -> Dictionary:
	if _runtime == null or not _runtime.has_method("follow_resident"):
		return _local_failure("CAMERA_FOLLOW_NOT_CONNECTED", false)
	var resident_id := str(payload.get("residentId", "")).strip_edges()
	if resident_id.is_empty():
		var hud := get_view_model("town_hud")
		resident_id = str(
			((hud.get("data", {}) as Dictionary).get("camera", {}) as Dictionary)
			.get("followTargetId", "")
		)
	var resident_name := _resident_name_for_id(resident_id)
	if resident_name.is_empty():
		return _local_failure("RESIDENT_IDENTITY_NOT_FOUND", false)
	if not bool(_runtime.call("follow_resident", resident_name)):
		return _local_failure("CAMERA_FOLLOW_REJECTED", false)
	return _success_result()


func _toggle_hud_avatar_mode() -> Dictionary:
	if _runtime == null or not _runtime.has_method("get_runtime_state"):
		return _local_failure("AVATAR_MODE_INTERFACE_MISSING", false)
	var runtime_state := _runtime.call("get_runtime_state") as Dictionary
	var avatar_mode := String(runtime_state.get("avatarMode", "observer"))
	if avatar_mode == "observer" and _runtime.has_method("enter_avatar_mode"):
		return _normalize_command_result(_runtime.call("enter_avatar_mode"))
	if avatar_mode == "avatar_active" and _runtime.has_method("exit_avatar_mode"):
		return _normalize_command_result(_runtime.call("exit_avatar_mode"))
	if avatar_mode == "avatar_descent":
		return _local_failure("AVATAR_MODE_TRANSITION_IN_PROGRESS", false)
	return _local_failure("AVATAR_MODE_TRANSITION_INVALID", false)


func _call_runtime_lifecycle(method: String, reason: String) -> Dictionary:
	if _runtime == null:
		return _local_failure("WORLD_NOT_RUNNING", false)
	if reason == "background":
		return _local_failure("BACKGROUND_LIFECYCLE_UI_FORBIDDEN", false)
	var paused := method == "pause"
	var runtime_method: String = {
		"main_menu": "set_main_menu_open",
		"resident_editor": "set_resident_editor_open",
		"manual": "set_manual_paused",
	}.get(reason, "")
	if runtime_method.is_empty():
		return _local_failure("INVALID_PAUSE_REASON", false)
	if not _runtime.has_method(runtime_method):
		return _local_failure("WORLD_NOT_RUNNING", false)
	return _normalize_command_result(_runtime.call(runtime_method, paused))


func _complete_operation(scope: String, operation: Dictionary, result: Dictionary) -> void:
	var final_operation := operation.duplicate(true)
	var ok := bool(result.get("ok", false))
	final_operation["status"] = "success" if ok else (
		"rejected" if not bool(result.get("retryable", false)) else "error"
	)
	final_operation["completedAtMsec"] = Time.get_ticks_msec()
	var error: Dictionary = {}
	if not ok:
		error = _error_from_result(result)
	_apply_operation(scope, final_operation, error)
	if WORLD_SCOPES.has(scope):
		var result_revision := int(result.get("worldRevision", _read_world_revision()))
		if result_revision >= _world_revision:
			_world_revision = result_revision
			# The operation state above is the only response the clicked page needs
			# synchronously. Rebuild authoritative world projections one at a time
			# on following frames so a single click cannot rebuild all six scopes.
			for world_scope in WORLD_SCOPES:
				_queue_world_scope_refresh(world_scope)
	operation_completed.emit(scope, final_operation.duplicate(true))


func _apply_operation(scope: String, operation: Dictionary, error: Dictionary) -> void:
	if not _view_models.has(scope):
		_refresh_scope(scope, true)
	var view_model: Dictionary = (_view_models.get(scope, {}) as Dictionary).duplicate(true)
	if view_model.is_empty():
		return
	view_model["operation"] = operation.duplicate(true)
	if str(operation.get("status", "")) == "loading":
		view_model["status"] = "loading"
	elif not error.is_empty():
		view_model["status"] = "error"
	view_model["error"] = null if error.is_empty() else error.duplicate(true)
	_set_view_model(scope, view_model, true)


# 外部页面服务的 revision 只在内容真实变化时推进（见 TownUiPageProjectionService
# _store_view_model），因此含 revision 的整体比较对未变内容能在 revision 处提前
# 退出，既便宜又正确；把 revision 排除出比较会迫使相等判定整棵深走，
# 实测在帧时基准上不划算。town_hud 例外：顶层 revision / item 级
# confirmedRevision / 播放时间戳每次构建必变，emit 判定走稳定内容投影（1b）。
func _set_view_model(scope: String, view_model: Dictionary, force_emit: bool) -> void:
	if scope == "town_hud":
		var probe_norm_started_usec := (
			Time.get_ticks_usec() if _frame_probe != null else 0
		)
		_normalize_town_hud_playback_times(view_model)
		var projection := _town_hud_stable_projection(view_model)
		var changed_hud: bool = (
			force_emit
			or not _view_models.has(scope)
			or projection != _town_hud_last_stable_projection
		)
		_town_hud_last_stable_projection = projection
		_view_models[scope] = view_model.duplicate(true)
		if probe_norm_started_usec > 0:
			_frame_probe.record(
				Engine.get_process_frames(),
				"adapterNormalizeAndDiffUsec",
				Time.get_ticks_usec() - probe_norm_started_usec,
			)
		if changed_hud:
			view_model_changed.emit(scope, view_model.duplicate(true))
		return
	var changed: bool = (
		force_emit
		or not _view_models.has(scope)
		or _view_models[scope] != view_model
	)
	_view_models[scope] = view_model.duplicate(true)
	if changed:
		view_model_changed.emit(scope, view_model.duplicate(true))


# 1b:同一播放身份连续存在时冻结首次发布的 startedAtMsec / expiresAtMsec,
# 身份消失即清除记录;身份成分(phase / iconType)翻转即新身份、新时间。
# 这样无论静默还是由别的 item 带出的整包 emit,未变化 item 的动画相位
# 与过期时刻都不重置。
func _normalize_town_hud_playback_times(view_model: Dictionary) -> void:
	var data := view_model.get("data", {}) as Dictionary
	var seen: Dictionary = {}
	for section_key: String in ["residentOverlays", "farResidentActivity"]:
		var section := data.get(section_key, {}) as Dictionary
		for value: Variant in section.get("items", []) as Array:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var item := value as Dictionary
			var identity := String(
				item.get("playbackIdentity", "")
			).strip_edges()
			if identity.is_empty() or not item.has("startedAtMsec"):
				continue
			if _hud_playback_times.has(identity):
				var stored := _hud_playback_times[identity] as Dictionary
				item["startedAtMsec"] = int(stored.get("startedAtMsec", 0))
				if item.has("expiresAtMsec") and stored.has("expiresAtMsec"):
					item["expiresAtMsec"] = int(
						stored.get("expiresAtMsec", 0)
					)
			else:
				var record := {
					"startedAtMsec": int(item.get("startedAtMsec", 0)),
				}
				if item.has("expiresAtMsec"):
					record["expiresAtMsec"] = int(
						item.get("expiresAtMsec", 0)
					)
				_hud_playback_times[identity] = record
			seen[identity] = true
	for identity_value: Variant in _hud_playback_times.keys():
		if not seen.has(String(identity_value)):
			_hud_playback_times.erase(String(identity_value))


# 1b 稳定内容投影:剔除顶层 revision、far 段 revision 与 item 级
# 播放时间 / confirmedRevision / 坐标残留;剔除清单与 far 层
# _stable_overlay_section 对齐。只用于 emit 判定,payload 不受影响。
func _town_hud_stable_projection(view_model: Dictionary) -> Dictionary:
	# town_hud 的稳定投影只用于比较是否需要广播。这里不能再对整棵
	# ViewModel 做深拷贝：居民目录、地点目录和 HUD 条目包含大量嵌套
	# 字典，单纯为了去掉几个播放时间字段就会把这段比较推到毫秒级。
	# 其余字段保持只读引用，只有会被清理的 scope 和 item 做浅复制。
	var projection := view_model.duplicate(false)
	projection.erase("revision")
	var source_data := view_model.get("data", {}) as Dictionary
	var data := source_data.duplicate(false)
	projection["data"] = data
	for section_key: String in [
		"residentOverlays",
		"farResidentActivity",
		"offscreenActivity",
	]:
		var source_section := source_data.get(section_key, {}) as Dictionary
		var section := source_section.duplicate(false)
		section.erase("revision")
		section.erase("confirmedRevision")
		# 累计诊断计数不驱动广播:候选被丢弃已由 items 差异触发 emit。
		section.erase("missingResidentStateCount")
		var stable_items: Array = []
		for value: Variant in source_section.get("items", []) as Array:
			if typeof(value) != TYPE_DICTIONARY:
				stable_items.append(value)
				continue
			var item := (value as Dictionary).duplicate(false)
			for field: String in [
				"screenAnchor",
				"headScreenAnchor",
				"startedAtMsec",
				"expiresAtMsec",
				"confirmedRevision",
			]:
				item.erase(field)
			stable_items.append(item)
		section["items"] = stable_items
		data[section_key] = section
	return projection


func _refresh_gateway_network_state() -> void:
	if _gateway == null:
		return
	var errors := _gateway_errors()
	var latest_sequence := _gateway_error_sequence
	if _conversation_wait_started_msec > 0:
		for index in range(errors.size()):
			var error_sequence := _gateway_error_sequence_for_record(
				errors[index],
				index,
			)
			if error_sequence <= _gateway_error_sequence:
				continue
			latest_sequence = maxi(latest_sequence, error_sequence)
		# Gateway failures are recovered inside the Agent/World boundary. Do not
		# project Provider/Gateway diagnostics into the player conversation; the
		# normal path is a fresh decision or a natural continuity close.
	else:
		latest_sequence = _latest_gateway_error_sequence(errors)
	_gateway_error_sequence = latest_sequence


func _expire_conversation_wait_if_needed(now_msec: int = -1) -> void:
	var effective_now_msec := (
		Time.get_ticks_msec()
		if now_msec < 0
		else now_msec
	)
	if (
		_conversation_wait_started_msec <= 0
		or (
			effective_now_msec - _conversation_wait_started_msec
			< CONVERSATION_WAIT_TIMEOUT_MSEC
		)
	):
		return
	# A Gateway fallback normally closes the conversation before this guard. If
	# a final recovery result was lost during a transition, close the player
	# conversation through the normal World path instead of exposing a timeout
	# or provider error in the UI.
	var conversation_id := _active_conversation_id()
	if (
		_runtime != null
		and _runtime.has_method("player_end_conversation")
		and not conversation_id.is_empty()
	):
		_local_player_close_conversation_id = conversation_id
		_runtime.call(
			"player_end_conversation",
			conversation_id,
			"话题自然停了下来",
		)
		_local_player_close_conversation_id = ""
	_conversation_wait_started_msec = 0
	_conversation_wait_conversation_id = ""
	_conversation_wait_resident_id = ""
	_conversation_wait_decision_id = ""
	_conversation_network_error.clear()
	_refresh_scope("conversation", true)


func _update_conversation_wait(
	waiting_for_resident: bool,
	resident_id: String = "",
	conversation_id: String = "",
) -> void:
	if waiting_for_resident:
		var normalized_resident_id := resident_id.strip_edges()
		var normalized_conversation_id := conversation_id.strip_edges()
		var wait_changed := (
			_conversation_wait_started_msec <= 0
			or normalized_resident_id != _conversation_wait_resident_id
			or normalized_conversation_id != _conversation_wait_conversation_id
		)
		if wait_changed:
			_gateway_error_sequence = _latest_gateway_error_sequence(
				_gateway_errors(),
			)
			_conversation_wait_started_msec = Time.get_ticks_msec()
			_conversation_wait_resident_id = normalized_resident_id
			_conversation_wait_conversation_id = normalized_conversation_id
			_conversation_wait_decision_id = ""
			_conversation_network_error.clear()
		var current_decision_id := _resident_pending_decision_id(
			normalized_resident_id,
		)
		if not current_decision_id.is_empty():
			_conversation_wait_decision_id = current_decision_id
		return
	_conversation_wait_started_msec = 0
	_conversation_wait_conversation_id = ""
	_conversation_wait_resident_id = ""
	_conversation_wait_decision_id = ""
	_conversation_network_error.clear()


func _resident_pending_decision_id(resident_id: String) -> String:
	if (
		_world == null
		or resident_id.is_empty()
		or not _world.has_method("get_resident_action_phase")
	):
		return ""
	var phase := _world.get_resident_action_phase(resident_id,) as Dictionary
	return String(phase.get("decisionId", "")).strip_edges()


func _is_current_conversation_final_error(error: Dictionary) -> bool:
	# Gateway/Provider failures are internal recovery signals. Even the final
	# exhausted attempt must never become a player-facing conversation error;
	# the wait guard closes the conversation naturally instead.
	return false


func _gateway_errors() -> Array:
	if _gateway != null and _gateway.has_method("get_errors"):
		return _gateway.call("get_errors")
	return []


func _latest_gateway_error_sequence(errors: Array) -> int:
	var latest_sequence := 0
	for index in range(errors.size()):
		latest_sequence = maxi(
			latest_sequence,
			_gateway_error_sequence_for_record(errors[index], index),
		)
	return latest_sequence


func _gateway_error_sequence_for_record(value: Variant, index: int) -> int:
	if value is Dictionary:
		var explicit_sequence := int(
			(value as Dictionary).get("errorSequence", 0),
		)
		if explicit_sequence > 0:
			return explicit_sequence
	# Compatibility for test doubles and old session-local Gateway records.
	return index + 1


func _connected_resident_names() -> Array[String]:
	var result: Array[String] = []
	if _gateway != null and _gateway.has_method("get_connected_resident_names"):
		for item in _gateway.call("get_connected_resident_names"):
			result.append(str(item))
	return result


func _refresh_resident_identities() -> void:
	_resident_id_by_name.clear()
	_resident_name_by_id.clear()
	_resident_identity_status = "unavailable"
	var snapshot: Dictionary = {}
	if _runtime != null and _runtime.has_method("get_resident_identity_snapshot"):
		snapshot = _runtime.call("get_resident_identity_snapshot") as Dictionary
	elif _session_config.has("residentIdentities"):
		snapshot = {
			"status": str(_session_config.get("identityStatus", "confirmed")),
			"residents": (_session_config.get("residentIdentities", []) as Array).duplicate(true),
		}
	for value: Variant in snapshot.get("residents", []) as Array:
		if not (value is Dictionary):
			continue
		var identity := value as Dictionary
		var resident_id := str(identity.get("residentId", "")).strip_edges()
		var resident_name := str(identity.get("residentName", "")).strip_edges()
		if (
			resident_id.is_empty()
			or resident_name.is_empty()
			or _resident_name_by_id.has(resident_id)
			or _resident_id_by_name.has(resident_name)
		):
			continue
		_resident_name_by_id[resident_id] = resident_name
		_resident_id_by_name[resident_name] = resident_id
	_resident_identity_status = str(snapshot.get("status", "unavailable"))


func _resident_id_for_name(resident_name: String) -> String:
	return str(_resident_id_by_name.get(resident_name, ""))


func _resident_name_for_id(resident_id: String) -> String:
	return str(_resident_name_by_id.get(resident_id, ""))


func _resident_target_id(resident_id: String) -> String:
	return "" if resident_id.is_empty() else "resident:%s" % resident_id


func _resident_portrait_fallback(resident_name: String) -> String:
	return "？" if resident_name.is_empty() else resident_name.left(1)


func _avatar_target_before(left: Dictionary, right: Dictionary) -> bool:
	var left_distance := float(left.get("_distanceSquared", INF))
	var right_distance := float(right.get("_distanceSquared", INF))
	if not is_equal_approx(left_distance, right_distance):
		return left_distance < right_distance
	var left_id := str(left.get("residentId", ""))
	var right_id := str(right.get("residentId", ""))
	if left_id == right_id:
		return str(left.get("residentName", "")) < str(right.get("residentName", ""))
	return left_id < right_id


func _synchronize_focused_nearby_target(targets: Array[Dictionary]) -> void:
	var available_ids: Array[String] = []
	for target in targets:
		var resident_id := str(target.get("residentId", ""))
		if not resident_id.is_empty():
			available_ids.append(resident_id)
	if not available_ids.has(_focused_nearby_resident_id):
		_focused_nearby_target_manual = false
	var next_focus := (
		_focused_nearby_resident_id
		if _focused_nearby_target_manual
		else (available_ids[0] if not available_ids.is_empty() else "")
	)
	_set_focused_nearby_target(next_focus)


func _set_focused_nearby_target(resident_id: String) -> void:
	if resident_id == _focused_nearby_resident_id:
		return
	_focused_nearby_resident_id = resident_id
	_avatar_target_revision += 1


func _rotate_targets_to_focus(targets: Array[Dictionary]) -> Array[Dictionary]:
	if targets.is_empty() or _focused_nearby_resident_id.is_empty():
		return targets
	var focus_index := -1
	for target_index in targets.size():
		if str(targets[target_index].get("residentId", "")) == _focused_nearby_resident_id:
			focus_index = target_index
			break
	if focus_index <= 0:
		return targets
	var result: Array[Dictionary] = []
	for offset in targets.size():
		result.append(targets[(focus_index + offset) % targets.size()].duplicate(true))
	return result


func _focus_nearby_target(payload: Dictionary) -> Dictionary:
	var avatar_view_model := get_view_model("avatar")
	var data := avatar_view_model.get("data", {}) as Dictionary
	var targets := data.get("nearbyTargets", []) as Array
	var requested_resident_id := str(payload.get("residentId", "")).strip_edges()
	if requested_resident_id.is_empty():
		var requested_target_id := str(payload.get("targetId", "")).strip_edges()
		if requested_target_id.begins_with("resident:"):
			requested_resident_id = requested_target_id.trim_prefix("resident:")
	var available_ids: Array[String] = []
	for target_variant in targets:
		if not (target_variant is Dictionary):
			continue
		var resident_id := str((target_variant as Dictionary).get("residentId", ""))
		if not resident_id.is_empty():
			available_ids.append(resident_id)
	if not requested_resident_id.is_empty():
		if not available_ids.has(requested_resident_id):
			return _local_failure("AVATAR_TARGET_NOT_NEARBY", false)
	elif available_ids.size() >= 2:
		var current_index := available_ids.find(_focused_nearby_resident_id)
		requested_resident_id = available_ids[(current_index + 1) % available_ids.size()]
	else:
		return _local_failure("AVATAR_NO_ALTERNATE_TARGET", false)
	_focused_nearby_target_manual = true
	_set_focused_nearby_target(requested_resident_id)
	return _success_result()


func _attack_avatar_target(payload: Dictionary) -> Dictionary:
	if _world == null or not _world.has_method("submit_avatar_area_attack"):
		return _local_failure("AVATAR_ATTACK_INTERFACE_MISSING", false)
	var runtime_state: Dictionary = {}
	if _runtime != null and _runtime.has_method("get_runtime_state"):
		runtime_state = _runtime.call("get_runtime_state") as Dictionary
	if String(runtime_state.get("avatarMode", "")) != "avatar_active":
		return _local_failure("AVATAR_MODE_NOT_ACTIVE", false)
	if not _active_conversation_id().is_empty():
		return _local_failure("AVATAR_CONVERSATION_ACTIVE", false)
	if bool(runtime_state.get("avatarConflictInputBlocked", false)):
		return _local_failure("AVATAR_ATTACK_ANIMATION_ACTIVE", false)
	var avatar := _world.get_player_avatar_state() as Dictionary
	var avatar_id := String(
		avatar.get("residentId", DEFAULT_PLAYER_AVATAR_ID),
	).strip_edges()
	if avatar_id.is_empty() or not bool(avatar.get("present", true)):
		return _local_failure("AVATAR_NOT_PRESENT", false)
	var attack_kind := String(payload.get("attackKind", "unarmed"))
	var action_id := String(payload.get("actionId", "")).strip_edges()
	if AVATAR_ATTACK_KIND_BY_ACTION_ID.has(action_id):
		# 技能槽是键盘与按钮触发的权威来源，防止过期的通用攻击负载把
		# 2/3/4 技能退化回默认空手攻击。
		attack_kind = String(AVATAR_ATTACK_KIND_BY_ACTION_ID[action_id])
	if not [
		"unarmed",
		"avatar_susanoo_strike",
		"avatar_rasengan",
		"avatar_kamehameha",
	].has(attack_kind):
		return _local_failure("AVATAR_ATTACK_KIND_UNSUPPORTED", false)
	_avatar_attack_sequence += 1
	var request_id := "avatar-attack-%06d" % _avatar_attack_sequence
	return _normalize_command_result(
		_world.submit_avatar_area_attack({
				"requestId": request_id,
				"attackerId": avatar_id,
				"attackKind": attack_kind,
				"sourceKind": "avatar_intent",
				"sourceRef": request_id,
			},)
	)


func _avatar_in_active_brawl(avatar_id: String) -> bool:
	var normalized_id := avatar_id.strip_edges()
	if (
		normalized_id.is_empty()
		or _world == null
		or not _world.has_method("get_public_conflict_projection")
	):
		return false
	var projection := _world.get_public_conflict_projection() as Dictionary
	for conflict_value: Variant in projection.get(
		"activeConflicts",
		[],
	) as Array:
		if conflict_value is not Dictionary:
			continue
		var conflict := conflict_value as Dictionary
		var presentation := conflict.get("presentation", {}) as Dictionary
		if String(presentation.get("mode", "")) != "shared_brawl_cloud":
			continue
		if (conflict.get("participantIds", []) as Array).has(normalized_id):
			return true
	return false


func _avatar_nearby_prompt(targets: Array[Dictionary], has_conversation: bool) -> Dictionary:
	if has_conversation:
		return {
			"code": "CONVERSATION_ALREADY_OPEN",
			"message": "当前对话已打开。",
		}
	if targets.is_empty():
		return {
			"code": "NO_NEARBY_INTERACTION",
			"message": "靠近已连接的居民后可以互动。",
		}
	if targets.size() >= 2:
		return {
			"code": "MULTIPLE_NEARBY_RESIDENTS",
			"message": "附近有多位居民，可以切换当前目标。",
		}
	return {
		"code": "NEARBY_RESIDENT_READY",
		"message": "可以与当前居民交谈。",
	}


func _active_conversation_id() -> String:
	if _world == null or not _world.has_method("get_player_avatar_state"):
		return ""
	var avatar: Dictionary = _world.get_player_avatar_state()
	var conversation_id := str(avatar.get("conversationId", ""))
	if conversation_id.is_empty() and avatar.get("conversation") is Dictionary:
		conversation_id = str((avatar.get("conversation") as Dictionary).get("conversation_id", ""))
	return conversation_id


func _active_conversation_resident_id() -> String:
	if _world == null or not _world.has_method("get_player_avatar_state"):
		return ""
	var avatar := _world.get_player_avatar_state() as Dictionary
	var conversation_id := _active_conversation_id()
	if conversation_id.is_empty() or not _world.has_method("get_conversation"):
		return ""
	var conversation := _world.get_conversation(conversation_id,) as Dictionary
	var resident_name := _conversation_resident_name(
		conversation,
		str(avatar.get("name", "旅行者")),
		str(avatar.get("residentId", DEFAULT_PLAYER_AVATAR_ID)),
	)
	return _resident_id_for_name(resident_name)


func _conversation_resident_name(
	conversation: Dictionary,
	player_name: String,
	player_id: String = "",
) -> String:
	for participant_variant in conversation.get("participants", []):
		var participant := str(participant_variant)
		if participant == player_name or (
			not player_id.is_empty() and participant == player_id
		):
			continue
		var resolved_name := _resident_name_for_id(participant)
		if not resolved_name.is_empty():
			return resolved_name
		if not _resident_id_for_name(participant).is_empty():
			return participant
	return ""


func _project_conversation_waiting_for(
	raw_waiting_for: Array[String],
	player_name: String,
	player_id: String,
) -> Array[String]:
	var result: Array[String] = []
	for participant_ref: String in raw_waiting_for:
		var display_name := participant_ref
		if participant_ref == player_id and not player_name.is_empty():
			display_name = player_name
		else:
			var resident_name := _resident_name_for_id(participant_ref)
			if not resident_name.is_empty():
				display_name = resident_name
		if not display_name.is_empty() and not result.has(display_name):
			result.append(display_name)
	return result


func _player_conversation_end_projection(
	conversation: Dictionary,
	player_name: String,
	player_id: String,
	resident_name: String,
	resident_id: String,
) -> Dictionary:
	if str(conversation.get("status", "")) != "ended":
		return {
			"endReason": "",
			"endedAt": null,
			"endedById": "",
			"endedByName": "",
			"endNotice": "",
		}
	var ended_by_id := ""
	var ended_by_name := ""
	var turns := conversation.get("turns", []) as Array
	if not turns.is_empty() and turns.back() is Dictionary:
		var final_turn := turns.back() as Dictionary
		var final_speaker_id := str(
			final_turn.get("speaker_resident_id", "")
		).strip_edges()
		var final_speaker_name := str(
			final_turn.get("speaker", "")
		).strip_edges()
		if (
			final_speaker_id != player_id
			and final_speaker_name != player_name
		):
			ended_by_id = final_speaker_id
			ended_by_name = final_speaker_name
	if ended_by_id.is_empty():
		ended_by_id = resident_id
	if ended_by_name.is_empty():
		ended_by_name = resident_name
	var end_reason := str(conversation.get("endReason", "")).strip_edges()
	var end_notice := (
		"%s结束了对话" % ended_by_name
		if not ended_by_name.is_empty()
		else "对话已结束"
	)
	if end_reason == "一方离开":
		end_notice = "距离太远，对话结束了"
	elif end_reason == "无法继续":
		end_notice = (
			"%s结束了这次交谈" % ended_by_name
			if not ended_by_name.is_empty()
			else "这次交谈已经结束"
		)
	return {
		"endReason": end_reason,
		"endedAt": _duplicate_public_value(conversation.get("endedAt")),
		"endedById": ended_by_id,
		"endedByName": ended_by_name,
		"endNotice": end_notice,
	}


func _position_payload(value: Variant) -> Dictionary:
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Array and (value as Array).size() >= 2:
		return {"x": float((value as Array)[0]), "y": float((value as Array)[1])}
	if value is Dictionary:
		return {
			"x": float((value as Dictionary).get("x", 0.0)),
			"y": float((value as Dictionary).get("y", 0.0)),
		}
	return {"x": 0.0, "y": 0.0}


func _position_vector(
	value: Variant,
	fallback: Vector2 = Vector2.ZERO,
) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(
			float((value as Array)[0]),
			float((value as Array)[1]),
		)
	if value is Dictionary:
		return Vector2(
			float((value as Dictionary).get("x", fallback.x)),
			float((value as Dictionary).get("y", fallback.y)),
		)
	return fallback


func _read_world_revision() -> int:
	return AiTownUiViewModel.world_revision(_world)


func _normalize_command_result(result_variant: Variant) -> Dictionary:
	if not (result_variant is Dictionary):
		return _local_failure("COMMAND_RESULT_INVALID", false)
	var result: Dictionary = (result_variant as Dictionary).duplicate(true)
	if not result.has("ok"):
		result["ok"] = false
	if not result.has("errorCode"):
		result["errorCode"] = "" if bool(result.get("ok", false)) else "COMMAND_REJECTED"
	if not result.has("retryable"):
		result["retryable"] = false
	if not result.has("worldRevision"):
		result["worldRevision"] = _read_world_revision()
	return result


func _success_result() -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"worldRevision": _read_world_revision(),
	}


func _local_failure(error_code: String, retryable: bool, message := "") -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"worldRevision": _read_world_revision(),
		"message": message,
	}


func _error_from_result(result: Dictionary) -> Dictionary:
	var raw_code := str(result.get("errorCode", "COMMAND_REJECTED"))
	# Provider, Agent, World-prepare and session transaction details belong in
	# diagnostic logs. Keep the player-facing operation understandable and
	# preserve the last confirmed view model while the runtime remains alive.
	if (
		raw_code.begins_with("AGENT_")
		or raw_code.begins_with("PROVIDER_")
		or raw_code.begins_with("LLM_")
		or raw_code.begins_with("WORLD_AGENT_")
		or raw_code.begins_with("SESSION_SAVE_")
		or raw_code.begins_with("WORLD_SAVE_")
		or raw_code.begins_with("SESSION_CONTINUE_")
	):
		return _error_payload(
			"TOWN_OPERATION_NOT_COMPLETED",
			bool(result.get("retryable", false)),
			"这次小镇状态更新没有完成，当前状态已保留。",
			[],
		)
	var message := str(result.get("message", ""))
	if message.is_empty():
		message = str(result.get("reason", ""))
	return _error_payload(
		raw_code,
		bool(result.get("retryable", false)),
		message,
		result.get("errors", [])
	)


func _error_payload(code: String, retryable: bool, message: String, details: Variant = []) -> Dictionary:
	return {
		"kind": _error_kind(code),
		"code": code,
		"retryable": retryable,
		"message": message,
		"details": details if details is Array else [],
	}


func _error_kind(code: String) -> String:
	if code in ["AGENT_RESPONSE_TIMEOUT"]:
		return "timeout"
	if code in ["AGENT_DECISION_REQUEST_FAILED"]:
		return "transport"
	if code in [
		"AGENT_SAVE_INTERFACE_MISSING",
		"SESSION_SAVE_SERVICE_NOT_BOUND",
		"SESSION_CONTINUE_REQUIRES_STARTUP_HOST",
		"WORLD_DATA_INCOMPLETE",
		"PROVIDER_HEALTH_INTERFACE_MISSING",
		"BACKGROUND_LIFECYCLE_UI_FORBIDDEN",
		"SPECTATOR_INTERFACE_MISSING",
		"INNER_OBSERVATION_INTERFACE_MISSING",
		"PHOTO_INTERACTION_INTERFACE_MISSING",
	]:
		return "unavailable"
	if (
		code.begins_with("SESSION_DRAFT_")
		or code.begins_with("SESSION_HOME_")
		or code.begins_with("SESSION_LLM_")
	):
		return "validation"
	if code in ["COMMAND_RESULT_INVALID", "UNKNOWN_UI_SCOPE", "UNKNOWN_UI_INTENT"]:
		return "internal"
	return "rejected"


func _scope_for_intent(intent: String) -> String:
	return TownUiIntentScopeTable.scope_for_intent(intent)

func _bind_external_ui_service(
	scope: String,
	service: Object,
	property_name: StringName,
) -> Dictionary:
	var previous := get(property_name) as Object
	_disconnect_external_ui_service(previous)
	if service == null:
		set(property_name, null)
		_refresh_scope(scope, true)
		return _success_result()
	if not service.has_method("get_view_model") or not service.has_method("dispatch"):
		return _local_failure("%s_SERVICE_CONTRACT_INVALID" % scope.to_upper(), false)
	set(property_name, service)
	if service.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_external_ui_view_model_changed")
		if not service.is_connected("view_model_changed", callback):
			service.connect("view_model_changed", callback)
	if service.has_signal("operation_completed"):
		var operation_callback := Callable(self, "_on_external_ui_operation_completed")
		if not service.is_connected("operation_completed", operation_callback):
			service.connect("operation_completed", operation_callback)
	_refresh_scope(scope, true)
	return _success_result()


func _disconnect_external_ui_service(service: Object) -> void:
	if service == null:
		return
	if service.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_external_ui_view_model_changed")
		if service.is_connected("view_model_changed", callback):
			service.disconnect("view_model_changed", callback)
	if service.has_signal("operation_completed"):
		var operation_callback := Callable(self, "_on_external_ui_operation_completed")
		if service.is_connected("operation_completed", operation_callback):
			service.disconnect("operation_completed", operation_callback)


func _on_external_ui_view_model_changed(
	scope: String,
	view_model: Dictionary,
) -> void:
	if scope in [
		"audio_display_settings",
		"provider_settings",
		"custom_resident_creator",
		"resident_editor",
		"resident_model_assignment",
		"announcements",
		"weather_control",
		"resident_action_menu",
		"resident_overview",
		"resident_detail",
		"inner_observation",
		"place_focus",
		"indoor",
		"town_log",
		"wardrobe",
	]:
		if scope == "custom_resident_creator":
			view_model = _apply_custom_resident_creator_route_capabilities(
				view_model,
			)
		elif scope == "resident_model_assignment":
			view_model = _apply_resident_model_assignment_startup_state(
				view_model,
			)
		_set_view_model(scope, view_model, true)
		if scope in ["audio_display_settings", "provider_settings"]:
			_refresh_scope("pause_menu", true)


func _on_external_ui_operation_completed(scope: String, operation: Dictionary) -> void:
	operation_completed.emit(scope, operation.duplicate(true))


func _external_ui_service(scope: String) -> Object:
	match scope:
		"audio_display_settings":
			return _audio_display_settings_service
		"provider_settings":
			return _provider_settings_service
		"custom_resident_creator":
			return _custom_resident_creator_service
		"resident_editor":
			return _resident_editor_service
		"resident_model_assignment":
			return _resident_model_assignment_service
		"announcements", "weather_control", "resident_action_menu", "resident_overview", "resident_detail", "inner_observation", "place_focus", "indoor", "town_log", "wardrobe":
			return _page_projection_service
	return null


func _external_ui_service_missing_view_model(scope: String) -> Dictionary:
	if scope == "custom_resident_creator":
		return _custom_resident_creator_service_missing_view_model()
	if scope == "resident_editor":
		var service := RESIDENT_EDITOR_SERVICE.new()
		service.set(
			"_configuration_error",
			"RESIDENT_EDITOR_SERVICE_NOT_BOUND",
		)
		return service.get_view_model() as Dictionary
	if scope == "resident_model_assignment":
		return _resident_model_assignment_service_missing_view_model()
	var error_code := "%s_SERVICE_NOT_BOUND" % scope.to_upper()
	return _base_view_model(
		scope,
		"disabled",
		0,
		{
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": false,
		},
		{},
		_idle_operation(),
		_error_payload(error_code, false, "正式 UI 服务尚未绑定。"),
	)


func _resident_model_assignment_service_missing_view_model() -> Dictionary:
	var error_code := "RESIDENT_MODEL_ASSIGNMENT_SERVICE_NOT_BOUND"
	var actions := {}
	var intents := {
		"selectResident": "resident_model_assignment.select_resident",
		"setFilter": "resident_model_assignment.set_filter",
		"setMode": "resident_model_assignment.set_mode",
		"selectBatchResident": "resident_model_assignment.select_batch_resident",
		"selectAllBatch": "resident_model_assignment.select_all_batch",
		"selectInvalid": "resident_model_assignment.select_invalid",
		"selectUnassigned": "resident_model_assignment.select_unassigned",
		"clearBatchSelection": "resident_model_assignment.clear_batch_selection",
		"selectProvider": "resident_model_assignment.select_provider",
		"selectModel": "resident_model_assignment.select_model",
		"assignOne": "resident_model_assignment.assign_one",
		"assignBatch": "resident_model_assignment.assign_batch",
		"applyDraft": "resident_model_assignment.apply_draft",
		"refresh": "resident_model_assignment.refresh",
		"back": "resident_model_assignment.back",
	}
	for action_key in intents:
		actions[action_key] = _action(String(intents[action_key]), false, error_code)
	return _base_view_model(
		"resident_model_assignment",
		"disabled",
		0,
		{
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": false,
			"draftRevision": 0,
			"residentCount": 15,
			"completedCount": 0,
			"invalidCount": 0,
			"unassignedCount": 15,
			"dirty": false,
			"mode": "single",
			"filter": "all",
			"selectedResidentId": "",
			"selectedProviderId": "",
			"selectedModelId": "",
			"selectedBatchResidentIds": [],
			"residents": [],
			"providers": [],
			"targetBinding": {
				"mode": "model",
				"providerId": "",
				"modelId": "",
			},
			"selectedResident": {},
		},
		actions,
		_idle_operation(),
		_error_payload(
			error_code,
			false,
			"正式居民模型分配服务尚未绑定。",
		),
	)


func _custom_resident_creator_service_missing_view_model() -> Dictionary:
	var error_code := "CUSTOM_RESIDENT_CREATOR_SERVICE_NOT_BOUND"
	var actions := {}
	var intents := {
		"updateFields": "custom_resident_creator.update_fields",
		"openWardrobe": "custom_resident_creator.open_wardrobe",
		"applyWardrobeResult": "custom_resident_creator.apply_wardrobe_result",
		"create": "custom_resident_creator.create",
		"cancel": "custom_resident_creator.cancel",
		"retry": "custom_resident_creator.retry",
	}
	for action_key in intents:
		actions[action_key] = _action(String(intents[action_key]), false, error_code)
	return _base_view_model(
		"custom_resident_creator",
		"disabled",
		0,
		{
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": false,
			"draftId": "",
			"candidatePoolRevision": 0,
			"draft": {},
			"resolvedAppearance": {},
			"options": {},
			"validation": {
				"status": "unavailable",
				"issues": [{
					"code": error_code,
					"message": "正式自定义居民创建服务尚未绑定。",
				}],
				"fieldIssues": {},
			},
		},
		actions,
		_idle_operation(),
		_error_payload(
			error_code,
			false,
			"正式自定义居民创建服务尚未绑定。",
		),
	)


func _apply_custom_resident_creator_route_capabilities(
	view_model: Dictionary,
) -> Dictionary:
	var result := view_model.duplicate(true)
	if result.is_empty() or _custom_resident_creator_wardrobe_route_available:
		return result
	var actions := result.get("actions", {}) as Dictionary
	var open_wardrobe := actions.get("openWardrobe", {}) as Dictionary
	if open_wardrobe.is_empty():
		open_wardrobe = _action(
			"custom_resident_creator.open_wardrobe",
			false,
			"CUSTOM_RESIDENT_WARDROBE_ROUTE_UNAVAILABLE",
		)
	else:
		open_wardrobe["enabled"] = false
		open_wardrobe["disabledReason"] = (
			"CUSTOM_RESIDENT_WARDROBE_ROUTE_UNAVAILABLE"
		)
	actions["openWardrobe"] = open_wardrobe
	result["actions"] = actions
	return result


func _apply_resident_model_assignment_startup_state(
	view_model: Dictionary,
) -> Dictionary:
	var result := view_model.duplicate(true)
	if result.is_empty() or _resident_model_assignment_startup_state.is_empty():
		return result
	var startup_state := _resident_model_assignment_startup_state
	var status := String(startup_state.get("status", ""))
	result["status"] = status
	result["operation"] = (
		startup_state.get("operation", {}) as Dictionary
	).duplicate(true)
	var error_value: Variant = startup_state.get("error")
	result["error"] = (
		(error_value as Dictionary).duplicate(true)
		if error_value is Dictionary
		else null
	)
	if status == "loading":
		var actions := (result.get("actions", {}) as Dictionary).duplicate(true)
		for action_key: Variant in actions:
			var action := (actions[action_key] as Dictionary).duplicate(true)
			action["enabled"] = false
			action["disabledReason"] = "RESIDENT_MODEL_ASSIGNMENT_STARTING"
			actions[action_key] = action
		result["actions"] = actions
	return result


func _next_request_id() -> String:
	_request_sequence += 1
	return AiTownUiViewModel.request_id("town-ui", _request_sequence)


func _base_view_model(
	scope: String,
	status: String,
	revision: int,
	data: Dictionary,
	actions: Dictionary,
	operation: Dictionary,
	error: Dictionary
) -> Dictionary:
	return AiTownUiViewModel.envelope(
		scope, status, maxi(revision, 0), data, actions, operation, error
	)


func _action(
	intent: String,
	enabled: bool,
	disabled_reason := "",
	payload: Dictionary = {},
) -> Dictionary:
	var result := {
		"intent": intent,
		"enabled": enabled,
		"disabledReason": "" if enabled else disabled_reason,
	}
	if not payload.is_empty():
		result["payload"] = payload.duplicate(true)
	return result


func _idle_operation() -> Dictionary:
	return AiTownUiViewModel.idle_operation()


func _operation_payload(request_id: String, intent: String, status: String) -> Dictionary:
	return {
		"requestId": request_id,
		"intent": intent,
		"status": status,
		"submittedAtMsec": Time.get_ticks_msec(),
		"completedAtMsec": 0,
	}
