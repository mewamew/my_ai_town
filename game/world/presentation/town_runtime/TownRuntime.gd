# 正式 Town 的组合根：世界、居民 Agent 与表现层只通过各自公开接口联合运行。
class_name AiTownRuntime
extends "res://world/maps/town/Town.gd"


signal lifecycle_state_changed(state: Dictionary)
signal startup_completed(result: Dictionary)
signal avatar_mode_changed(mode: String, previous_mode: String)
signal observed_place_changed(result: Dictionary)


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const WORLD_DATA_PATH := "res://world/data/town/town_world.json"
const OPENING := preload("res://world/runtime/TownWorldOpeningConfig.gd")
const WORLD := preload("res://world/runtime/TownWorldRuntime.gd")
const FRAME_BUDGET_RUNTIME := preload(
	"res://world/runtime/presentation/TownWorldFrameBudgetRuntime.gd"
)
const RESIDENT_PRESENTATION := preload(
	"res://world/presentation/residents/ResidentCharacterPresentation.gd"
)
const CONFLICT_PRESENTATION_HOST := preload(
	"res://world/presentation/conflict/TownConflictPresentationHost.gd"
)
const ANIMAL_PRESENTATION := preload(
	"res://world/presentation/animals/TownAnimalPresentation.gd"
)
const ENVIRONMENT_RENDERER := preload("res://world/presentation/environment/TownEnvironmentPresentation.gd")
const UI_ADAPTER := preload("res://world/presentation/ui/TownUiAdapter.gd")
const AVATAR_DESCENT_PRESENTATION := preload(
	"res://world/presentation/town_runtime/AvatarDescentPresentation.gd"
)
const BUILDING_OBSERVATION_HOTSPOT := preload(
	"res://world/presentation/town_runtime/BuildingObservationHotspot.gd"
)
const BUILDING_RESIDENT_MARKER := preload(
	"res://world/presentation/town_runtime/BuildingResidentMarker.gd"
)
const BUILDING_ENTRY_CONFIRM := preload(
	"res://world/presentation/town_runtime/BuildingEntryConfirm.gd"
)
const SPACE_VIEW_SYNC := preload(
	"res://world/presentation/town_runtime/TownSpaceViewSync.gd"
)
const TOUCH_CAMERA_GESTURE := preload(
	"res://ui/mobile/TouchCameraGesture.gd"
)
const MOBILE_MOVEMENT_INPUT := preload(
	"res://ui/mobile/MobileMovementInput.gd"
)
# 表现层激活空间与实际可视空间的周期兜底核对间隔（秒）。
const SPACE_VIEW_SYNC_INTERVAL_SECONDS := 0.5
const RESIDENT_WARDROBE_CATALOG_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
	+ "wardrobe_catalog.json"
)
const FORMAL_PLAYER_AVATAR_TEXTURE := preload(
	"res://assets/characters/player_avatar_white/player_avatar_white_walk_64.png"
)
const AVATAR_MODE_OBSERVER := "observer"
const AVATAR_MODE_DESCENT := "avatar_descent"
const AVATAR_MODE_ACTIVE := "avatar_active"
const OBSERVER_START_POSITION := Vector2(3250.0, 2050.0)
const OBSERVER_START_ZOOM_INDEX := 1
const OBSERVER_PAN_SCREEN_SPEED := 560.0
const OBSERVER_MAGNIFY_STEP_THRESHOLD := 0.18
const AVATAR_WORLD_POSITION_SYNC_INTERVAL_SECONDS := 0.1
const MAP_COLLISION_LAYER := 1
const RESIDENT_COLLISION_LAYER := 4
const GROUND_ANIMAL_COLLISION_LAYER := 8
const AVATAR_COLLISION_MASK := (
	MAP_COLLISION_LAYER
	| RESIDENT_COLLISION_LAYER
	| GROUND_ANIMAL_COLLISION_LAYER
)
const BULLETIN_BOARD_HOTSPOT_CENTER := Vector2(3064.0, 1683.0)
const BULLETIN_BOARD_HOTSPOT_SIZE := Vector2(160.0, 128.0)
const BUILDING_ENTRY_CONFIRM_SIZE := Vector2(214.0, 44.0)
const MOBILE_BUILDING_RESIDENT_MARKER_TOUCH_SCALE := 1.45
const MOBILE_BUILDING_ENTRY_CONFIRM_TOUCH_SCALE := 1.65
const BUILDING_ENTRY_CONFIRM_SCREEN_INSETS := Vector4(175.0, 145.0, 185.0, 70.0)
const RESIDENT_ACTION_MENU_EXTENTS := Vector4(196.0, 341.0, 196.0, 14.0)
const REQUIRED_AGENT_GATEWAY_METHODS: Array[String] = [
	"bind_world",
	"pump",
	"pump_frame_budgeted",
	"prioritize_next_conversation_turn",
	"get_connected_resident_names",
	"get_errors",
]
# Preparing several resident model requests in one render frame can include
# prompt compilation and immediate fake-provider completion. Keep concurrency
# in the Gateway, but fill those lanes over consecutive frames so the town
# never pays the whole burst in one visible frame.
const AGENT_DISPATCH_BUDGET_PER_FRAME := 1
# A conversation click routes and builds its page synchronously. Keep the
# request urgent, but wait for one newly drawn frame before prompt preparation
# starts on the main thread. The deadline prevents a minimized or unavailable
# renderer from leaving a conversation request stuck forever.
const CONVERSATION_AGENT_DISPATCH_HOLD_PROCESS_TURNS := 1
const CONVERSATION_AGENT_DISPATCH_MAX_FIRST_DRAW_WAIT_MSEC := 500

const CONNECTION_ID_BY_PORTAL_ID := {
	# TownBase predates the World connection name for the market interior.
	# All player-facing place semantics still come from World data.
	"market": "connection_market_shop",
}

@export var use_live_model := true
@export var enable_player_avatar := false
@export var enable_test_ui := false
@export var connected_residents: Array[String] = []
@export_file("*.json") var opening_config_path := ""

var session_config: Dictionary = {}
var _world: TownWorldRuntime
var _agent_gateway: Node
var _resident_presentation: Node
var _presentation_screen_anchor_call := Callable()
var _presentation_head_anchor_call := Callable()
var _resident_character_root: Node2D
var _conflict_presentation_host: Node
var _animal_presentation: TownAnimalPresentation
var _environment_renderer: Node
var _ui_adapter: Node
var _followed_resident := ""
var _selected_resident := ""
var _status_panel := PanelContainer.new()
var _environment_label := Label.new()
var _resident_label := Label.new()
var _hint_label := Label.new()
var _startup_error := ""
var _building_observation_hotspots: Dictionary = {}
var _building_resident_markers: Dictionary = {}
var _resident_portrait_path_by_appearance: Dictionary = {}
var _focused_building_place_name := ""
var _building_entry_confirm: BuildingEntryConfirm
var _building_entry_confirm_place_name := ""
var _expanded_building_resident_marker: Node2D
var _observed_place_name := ""
var _view_sync_active := false
var _view_sync_requested := false
var _follow_view_generation := 0
var _active_follow_view_generation := -1
var _follow_view_rollback_space_id := ""
var _follow_view_rollback_place_name := ""
var _follow_view_rollback_origin := Vector2.ZERO
var _space_view_sync_elapsed := 0.0
var _announcement_panel: PanelContainer
var _weather_panel: PanelContainer
var _bulletin_hotspot: Node2D
var _announcement_signal_count := 0
var _last_announcement_feedback := ""
var _last_weather_feedback := ""
var _player_conversation_panel: PanelContainer
var _avatar_place_change_active := false
var _avatar_outdoor_place := ""
var _last_confirmed_avatar_position := Vector2.INF
var _last_confirmed_avatar_space_id := ""
var _avatar_was_moving := false
var _avatar_position_sync_elapsed := AVATAR_WORLD_POSITION_SYNC_INTERVAL_SECONDS
var _animal_state_sync_elapsed := AVATAR_WORLD_POSITION_SYNC_INTERVAL_SECONDS
var _text_input_was_focused := false
var _last_player_command_result: Dictionary = {}
var _last_player_conversation: Dictionary = {}
var _conversation_audio_turn_counts: Dictionary = {}
var _lifecycle_state: Dictionary = {
	"state": "stopped",
	"started": false,
	"paused": false,
	"pauseReasons": [],
}
var _lifecycle_label := Label.new()
var _manual_pause_button: Button
var _world_start_result: Dictionary = {}
var _startup_completion_emitted := false
var _resident_id_by_name: Dictionary = {}
var _resident_name_by_id: Dictionary = {}
var _resident_identity_status := "unavailable"
var _avatar_mode := AVATAR_MODE_OBSERVER
var _avatar_descent_presentation: AvatarDescentPresentation
var _observer_camera_position := OBSERVER_START_POSITION
var _observer_camera_input_enabled := true
var _avatar_movement_input_enabled := true
var _avatar_conflict_input_blocked := false
var _mobile_movement_input: MobileMovementInput = MOBILE_MOVEMENT_INPUT.new()
var _frame_profile_enabled := false
var _last_frame_profile: Dictionary = {}
# A1 探针:仅 AI_TOWN_UI_FRAME_PROBE=1 时加载,关闭时保持 null、零开销。
var _frame_probe: GDScript = null
var _observer_drag_active := false
var _observer_drag_button := MOUSE_BUTTON_NONE
var _observer_magnify_accumulator := 0.0
var _avatar_magnify_accumulator := 0.0
var _touch_camera_gesture: TouchCameraGesture = TOUCH_CAMERA_GESTURE.new()
var _agent_dispatch_hold_process_turns := 0
var _agent_dispatch_not_before_drawn_frame := -1
var _agent_dispatch_first_draw_deadline_msec := 0
var _agent_gateway_pump_scheduled := false
var _agent_gateway_watchdog_active := false
var _agent_gateway_pending_world_advance: Dictionary = {}


# Formal sessions mount TownEnvironmentPresentation after the world starts.
# Suppress TownBase's older preview weather, lights, particles and procedural
# thunder so the same effects are not built and updated twice.
func _build_environment_test() -> void:
	pass


func _update_environment_test(_delta: float) -> void:
	pass


func _ready() -> void:
	if OS.get_environment("AI_TOWN_UI_FRAME_PROBE") == "1":
		_frame_probe = load("res://world/presentation/ui/TownUiFrameProbe.gd")
	_clear_move_action_state()
	_apply_session_presentation_options()
	# The player remains a direct Town child for the stable `Player` node path,
	# while residents live under a nested Y-sort host. Enabling Y-sort on this
	# shared ancestor lets both foot points participate in the same depth order.
	y_sort_enabled = true
	# A Town session always opens in overview. Avatar control is entered only by
	# an explicit observer-HUD intent, never as a side effect of loading Town.
	_avatar_mode = AVATAR_MODE_OBSERVER
	enable_player_avatar = false
	super._ready()
	_configure_formal_player_avatar_sprite()
	_build_avatar_descent_presentation()
	# TownBase 仍保留旧地图演示用的程序雷声；正式天气音频由全局控制器统一播放。
	if _thunder_player != null:
		_thunder_player.stop()
		_thunder_player.volume_db = -80.0
	if enable_player_avatar:
		_enable_avatar_control()
	else:
		_disable_avatar_control()
	_reset_observer_camera(true)
	_build_runtime_hud()
	_start_world()
	if _frame_probe != null:
		set_frame_profile_enabled(true)


func _exit_tree() -> void:
	_agent_gateway_pump_scheduled = false
	_agent_gateway_watchdog_active = false
	_agent_gateway_pending_world_advance.clear()
	if _frame_probe != null:
		_frame_probe.flush()
	if _conflict_presentation_host != null:
		_conflict_presentation_host.unconfigure()
	if _agent_gateway != null and _agent_gateway.has_method("close_session"):
		_agent_gateway.close_session()
	if _world != null and _world.is_running():
		_world.stop()
	# Runtime-only diagnostics are also allocated eagerly, but formal sessions
	# deliberately never mount them. Release only the Nodes that stayed orphaned;
	# mounted UI remains owned by the normal scene hierarchy.
	for value: Variant in [
		_status_panel,
		_environment_label,
		_resident_label,
		_hint_label,
		_lifecycle_label,
	]:
		var node := value as Node
		if is_instance_valid(node) and node.get_parent() == null:
			node.free()
	super._exit_tree()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_background_paused(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_background_paused(false)


func _process(delta: float) -> void:
	var profile_started_usec := (
		Time.get_ticks_usec() if _frame_profile_enabled else 0
	)
	var phase_started_usec := profile_started_usec
	var profile: Dictionary = {}
	# 小动物状态只服务宠物焦点高亮，按化身位置同步节奏（10Hz）刷新即可；
	# 触发抚摸前 _try_pet_nearest_animal 会先直接刷新一次。
	_animal_state_sync_elapsed += delta
	if _animal_state_sync_elapsed >= AVATAR_WORLD_POSITION_SYNC_INTERVAL_SECONDS:
		_animal_state_sync_elapsed = 0.0
		_update_animal_presentation_state()
	if _frame_profile_enabled:
		profile["animalsUsec"] = (
			Time.get_ticks_usec() - phase_started_usec
		)
	if _world == null or not _world.is_running():
		if _frame_profile_enabled:
			profile["totalUsec"] = (
				Time.get_ticks_usec() - profile_started_usec
			)
			_last_frame_profile = profile
			_record_frame_probe()
		return
	phase_started_usec = (
		Time.get_ticks_usec() if _frame_profile_enabled else 0
	)
	var world_advance := _world.advance(delta) as Dictionary
	if _frame_profile_enabled:
		profile["worldUsec"] = (
			Time.get_ticks_usec() - phase_started_usec
		)
		phase_started_usec = Time.get_ticks_usec()
	# The avatar physics lane has already run before this idle phase. Do not let
	# resident prompt preparation or model dispatch occupy the same visible frame;
	# it is scheduled after the frame is submitted, with a headless fallback for
	# production-entry tests and a timer fallback for a renderer that is minimized.
	_schedule_agent_gateway_pump(world_advance)
	if _frame_profile_enabled:
		profile["agentDeferredCount"] = 1 if FRAME_BUDGET_RUNTIME.should_defer_agent_dispatch(
			world_advance,
		) else 0
		profile["agentDispatchScheduled"] = 1
		profile["agentUsec"] = 0
		phase_started_usec = Time.get_ticks_usec()
	var presentation_delta := (
		0.0
		if _world.has_method("is_paused")
			and bool(_world.is_paused())
		else delta
	)
	if _environment_renderer.has_method("set_presentation_paused"):
		_environment_renderer.set_presentation_paused(is_zero_approx(presentation_delta) and bool(_world.is_paused()),)
	_environment_renderer.set_outdoor_visible(not _is_inside_interior())
	_environment_renderer.apply_world_state(_world.get_time(),
		_world.get_weather(),
		presentation_delta,)
	if _frame_profile_enabled:
		profile["environmentUsec"] = (
			Time.get_ticks_usec() - phase_started_usec
		)
		phase_started_usec = Time.get_ticks_usec()
	if _avatar_mode == AVATAR_MODE_OBSERVER and not _followed_resident.is_empty():
		_update_follow_camera()
	if _frame_profile_enabled:
		profile["cameraUsec"] = (
			Time.get_ticks_usec() - phase_started_usec
		)
		phase_started_usec = Time.get_ticks_usec()
	_update_runtime_hud()
	# 周期兜底：表现层激活空间与实际可视空间失配时下一拍自动修正
	# （传送期间的同步由黑屏钩子负责，这里跳过避免中途反复）。
	_space_view_sync_elapsed += delta
	if (
		_space_view_sync_elapsed >= SPACE_VIEW_SYNC_INTERVAL_SECONDS
		and _resident_presentation != null
		and _world != null
		and not _portal_transition_active
	):
		_space_view_sync_elapsed = 0.0
		SPACE_VIEW_SYNC.reconcile(self, _resident_presentation, "periodic")
	if _frame_profile_enabled:
		profile["testHudUsec"] = (
			Time.get_ticks_usec() - phase_started_usec
		)
		profile["totalUsec"] = (
			Time.get_ticks_usec() - profile_started_usec
		)
		_last_frame_profile = profile
		_record_frame_probe()
	if not _startup_completion_emitted:
		_startup_completion_emitted = true
		startup_completed.emit(get_startup_result())


# A1 探针:把本帧既有分项按渲染帧编号写入探针,adapter / HUD 段由各自宿主写入;
# advance 分项(3a/A3 键)带 adv 前缀转录,世界侧慢帧可直接归属到分钟步骤。
func _record_frame_probe() -> void:
	if _frame_probe == null:
		return
	var frame := Engine.get_process_frames()
	for key: String in _last_frame_profile:
		var value: Variant = _last_frame_profile[key]
		if value is int:
			_frame_probe.record(frame, key, value)
	if _world != null and _world.has_method("get_last_advance_profile"):
		var advance_profile := _world.get_last_advance_profile() as Dictionary
		for key: String in advance_profile:
			var value: Variant = advance_profile[key]
			if value is int:
				_frame_probe.record(frame, "adv_" + key, value)
	_frame_probe.maybe_flush()


func set_frame_profile_enabled(enabled: bool) -> void:
	_frame_profile_enabled = enabled
	if _world != null and _world.has_method(
		"set_advance_profile_enabled",
	):
		_world.set_advance_profile_enabled(enabled)
	if not enabled:
		_last_frame_profile.clear()


func get_last_frame_profile() -> Dictionary:
	var result := _last_frame_profile.duplicate(true)
	if (
		_world != null
		and _world.has_method("get_last_advance_profile")
	):
		result["worldProfile"] = _world.get_last_advance_profile() as Dictionary
	return result


func _environment_space_occupancy() -> Dictionary:
	var occupancy: Dictionary = {}
	if _world == null:
		return occupancy
	if _world.has_method("get_all_resident_states"):
		for state_value: Variant in _world.get_all_resident_states() as Array:
			var state := state_value as Dictionary
			var space_id := String(state.get("spaceId", "")).strip_edges()
			if not space_id.is_empty() and space_id != "town_outdoor":
				occupancy[space_id] = int(occupancy.get(space_id, 0)) + 1
	if _world.has_method("get_player_avatar_state"):
		var avatar := _world.get_player_avatar_state() as Dictionary
		var avatar_space_id := String(avatar.get("spaceId", "")).strip_edges()
		if not avatar_space_id.is_empty() and avatar_space_id != "town_outdoor":
			occupancy[avatar_space_id] = (
				int(occupancy.get(avatar_space_id, 0)) + 1
			)
	return occupancy


func _sync_environment_space_occupancy() -> void:
	if (
		_environment_renderer != null
		and _environment_renderer.has_method("set_space_occupancy")
	):
		_environment_renderer.set_space_occupancy(_environment_space_occupancy(),)


func _physics_process(delta: float) -> void:
	var text_input_focused := _is_text_input_focused()
	if text_input_focused:
		_text_input_was_focused = true
		_clear_move_action_state()
		if enable_player_avatar:
			_stop_avatar_visual_motion(false)
			if _avatar_was_moving and _world != null:
				_submit_player_avatar_position(true)
			_avatar_position_sync_elapsed = AVATAR_WORLD_POSITION_SYNC_INTERVAL_SECONDS
			_avatar_was_moving = false
			_update_camera_target()
		return
	if _text_input_was_focused:
		_text_input_was_focused = false
		_clear_move_action_state()
		if enable_player_avatar:
			_stop_avatar_visual_motion()
			_update_camera_target()
		return
	if not enable_player_avatar:
		_player.velocity = Vector2.ZERO
		if _avatar_mode == AVATAR_MODE_OBSERVER:
			_update_observer_camera_input(delta)
		elif _avatar_mode != AVATAR_MODE_DESCENT:
			_update_camera_target()
		return
	if not _avatar_movement_input_enabled or _avatar_conflict_input_blocked:
		_stop_avatar_visual_motion(false)
		_update_camera_target()
		return
	if _world != null and _world.is_paused():
		_stop_avatar_visual_motion()
		_update_camera_target()
		return
	var previous_position := _player.position
	super._physics_process(delta)
	if _world == null or _avatar_place_change_active or _portal_transition_active:
		return
	var moved := _player.position.distance_to(previous_position) > 0.01
	if moved:
		_avatar_position_sync_elapsed += delta
		if _avatar_position_sync_elapsed >= AVATAR_WORLD_POSITION_SYNC_INTERVAL_SECONDS:
			_submit_player_avatar_position(false)
			_avatar_position_sync_elapsed = 0.0
	elif _avatar_was_moving:
		_submit_player_avatar_position(true)
		_avatar_position_sync_elapsed = AVATAR_WORLD_POSITION_SYNC_INTERVAL_SECONDS
	_avatar_was_moving = moved


func _input(event: InputEvent) -> void:
	if not enable_player_avatar or not _is_text_input_focused():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_release_text_input_focus()
		return
	if event is InputEventMouseButton and event.pressed:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner == null or not focus_owner.get_global_rect().has_point(event.position):
			_release_text_input_focus()
	elif event is InputEventScreenTouch and event.pressed:
		var touch := event as InputEventScreenTouch
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner == null or not focus_owner.get_global_rect().has_point(touch.position):
			_release_text_input_focus()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_building_entry_confirm):
		if event.is_action_pressed("ui_cancel"):
			_dismiss_building_entry_confirm()
			get_viewport().set_input_as_handled()
			return
		if _is_primary_pointer_press(event):
			_dismiss_building_entry_confirm()
			get_viewport().set_input_as_handled()
			return
	if is_instance_valid(_expanded_building_resident_marker):
		if event.is_action_pressed("ui_cancel"):
			_collapse_building_resident_marker()
			get_viewport().set_input_as_handled()
			return
		if _is_primary_pointer_press(event):
			_collapse_building_resident_marker()
			get_viewport().set_input_as_handled()
			return
	if _avatar_mode == AVATAR_MODE_OBSERVER:
		if _handle_touch_camera_input(event, true):
			get_viewport().set_input_as_handled()
			return
		if _handle_observer_zoom_input(event):
			get_viewport().set_input_as_handled()
			return
		if not _observer_camera_accepts_input():
			_cancel_observer_drag()
			return
		if event is InputEventMouseMotion:
			if _observer_drag_active:
				_stop_following_for_observer_pan()
				var zoom_value := maxf(_camera.zoom.x, 0.001)
				_set_observer_camera_position(
					_observer_camera_position - event.relative / zoom_value,
					true,
				)
				get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
				if event.pressed:
					_observer_drag_active = true
					_observer_drag_button = event.button_index
				elif event.button_index == _observer_drag_button:
					_cancel_observer_drag()
				get_viewport().set_input_as_handled()
				return
	else:
		if _handle_touch_camera_input(event, false):
			get_viewport().set_input_as_handled()
			return
		if _handle_avatar_zoom_input(event):
			get_viewport().set_input_as_handled()
			return
	if (
		enable_player_avatar
		and event.is_action_pressed("interact")
		and _try_pet_nearest_animal()
	):
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if not enable_test_ui:
		return
	match event.keycode:
		KEY_P:
			set_manual_paused(not bool(_lifecycle_state.get("pauseReasons", []).has("manual")))
		KEY_0:
			_set_zoom_index(OVERVIEW_ZOOM_INDEX)
		KEY_F:
			_set_zoom_index(DEFAULT_ZOOM_INDEX)
			if enable_player_avatar:
				_update_camera_target(true)
			else:
				_update_follow_camera(true)
		KEY_TAB:
			if not enable_player_avatar:
				_follow_next_resident()
		KEY_C:
			_cycle_world_weather()
		KEY_T:
			_world.cycle_time_period_for_test()
		KEY_ESCAPE:
			if _player_conversation_panel != null and _player_conversation_panel.visible:
				_player_conversation_panel.visible = false
			elif _announcement_panel != null and _announcement_panel.visible:
				_close_announcement_panel()
			elif _weather_panel != null and _weather_panel.visible:
				_close_weather_panel()
			else:
				get_tree().quit()


func _allows_runtime_test_ui() -> bool:
	return enable_test_ui


func get_world_runtime() -> RefCounted:
	return _world


func get_startup_result() -> Dictionary:
	if not _startup_error.is_empty():
		return _local_command_failure(
			"TOWN_RUNTIME_START_FAILED",
			_startup_error,
		)
	if _world == null or not bool(_world.is_running()):
		return _local_command_failure(
			"TOWN_RUNTIME_NOT_STARTED",
			"Town Runtime 尚未完成启动。",
		)
	var result := _world_start_result.duplicate(true)
	result["ok"] = true
	result["errorCode"] = ""
	result["retryable"] = false
	return result


func get_ui_adapter() -> Node:
	return _ui_adapter


func update_resident_bindings(bindings_value: Variant) -> Dictionary:
	if not bindings_value is Array:
		return RESULT_SHAPES.failure("SESSION_LLM_BINDINGS_INVALID")
	var expected_ids: Dictionary = {}
	for identity_value: Variant in session_config.get("residentIdentities", []) as Array:
		if not identity_value is Dictionary:
			return RESULT_SHAPES.failure("SESSION_RESIDENT_IDENTITIES_INVALID")
		var resident_id := String(
			(identity_value as Dictionary).get("residentId", "")
		).strip_edges()
		if resident_id.is_empty() or expected_ids.has(resident_id):
			return RESULT_SHAPES.failure("SESSION_RESIDENT_IDENTITIES_INVALID")
		expected_ids[resident_id] = true
	var seen_ids: Dictionary = {}
	var normalized: Array[Dictionary] = []
	for binding_value: Variant in bindings_value as Array:
		if not binding_value is Dictionary:
			return RESULT_SHAPES.failure("SESSION_LLM_BINDINGS_INVALID")
		var binding := binding_value as Dictionary
		var resident_id := String(binding.get("residentId", "")).strip_edges()
		if (
			resident_id.is_empty()
			or not expected_ids.has(resident_id)
			or seen_ids.has(resident_id)
			or not binding.get("llmBinding", {}) is Dictionary
		):
			return RESULT_SHAPES.failure("SESSION_LLM_BINDINGS_INVALID")
		seen_ids[resident_id] = true
		normalized.append({
			"residentId": resident_id,
			"llmBinding": (
				binding.get("llmBinding", {}) as Dictionary
			).duplicate(true),
		})
	if seen_ids.size() != expected_ids.size():
		return RESULT_SHAPES.failure("SESSION_LLM_BINDINGS_INVALID")
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	var previous := (session_config.get("residentBindings", []) as Array).duplicate(true)
	session_config["residentBindings"] = normalized.duplicate(true)
	if _ui_adapter != null and _ui_adapter.has_method(
		"update_session_resident_bindings"
	):
		_ui_adapter.update_session_resident_bindings(
			normalized.duplicate(true),
		)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": normalized != previous,
		"previousBindings": previous,
		"residentBindings": normalized,
	}


func configure_agent_gateway(gateway: Node) -> Dictionary:
	if is_inside_tree():
		return _local_command_failure(
			"AGENT_GATEWAY_CONFIGURATION_LATE",
			"Agent Gateway 必须在 Town 进入场景树前注入。",
		)
	if gateway == null:
		return _local_command_failure(
			"AGENT_GATEWAY_INVALID",
			"Agent Gateway 不能为空。",
		)
	var missing_methods: Array[String] = []
	for method in REQUIRED_AGENT_GATEWAY_METHODS:
		if not gateway.has_method(method):
			missing_methods.append(method)
	if not missing_methods.is_empty():
		return _local_command_failure(
			"AGENT_GATEWAY_CONTRACT_MISSING",
			"Agent Gateway 缺少公共方法：%s" % ", ".join(missing_methods),
		)
	_agent_gateway = gateway
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"worldRevision": 0,
	}


func get_connected_agent_names() -> Array[String]:
	if _agent_gateway == null:
		return []
	return (_agent_gateway.get_connected_resident_names() as Array[String]).duplicate()


func get_resident_screen_anchor(resident_name: String) -> Dictionary:
	if not _presentation_screen_anchor_call.is_valid():
		return {}
	return _presentation_screen_anchor_call.call(resident_name) as Dictionary


func get_resident_head_screen_anchor(resident_name: String) -> Dictionary:
	if not _presentation_head_anchor_call.is_valid():
		return {}
	return _presentation_head_anchor_call.call(resident_name) as Dictionary


func get_resident_screen_projection(resident_name: String) -> Dictionary:
	var anchor := get_resident_screen_anchor(resident_name)
	if not anchor.has("x") or not anchor.has("y"):
		return {
			"available": false,
			"offscreen": false,
			"direction": "",
			"screenAnchor": {},
			"screenEdgeAnchor": {},
			"coordinateSpace": "viewport_logical",
		}
	var viewport_rect := get_viewport_rect()
	if not viewport_rect.has_area():
		return {
			"available": false,
			"offscreen": false,
			"direction": "",
			"screenAnchor": {},
			"screenEdgeAnchor": {},
			"coordinateSpace": "viewport_logical",
		}
	var point := Vector2(
		float(anchor.get("x", 0.0)),
		float(anchor.get("y", 0.0)),
	)
	var offscreen := not viewport_rect.has_point(point)
	var edge_margin := 32.0
	var edge_point := Vector2(
		clampf(
			point.x,
			viewport_rect.position.x + edge_margin,
			viewport_rect.end.x - edge_margin,
		),
		clampf(
			point.y,
			viewport_rect.position.y + edge_margin,
			viewport_rect.end.y - edge_margin,
		),
	)
	var normalized_anchor := {
		"x": point.x,
		"y": point.y,
		"valid": true,
		"coordinateSpace": "viewport_logical",
	}
	return {
		"available": true,
		"offscreen": offscreen,
		"direction": _screen_edge_direction(
			point - (viewport_rect.position + viewport_rect.size * 0.5)
		) if offscreen else "",
		"screenAnchor": normalized_anchor,
		"screenEdgeAnchor": {
			"x": edge_point.x,
			"y": edge_point.y,
			"valid": offscreen,
			"coordinateSpace": "viewport_logical",
		},
		"coordinateSpace": "viewport_logical",
	}


func get_resident_character_presentation_snapshot() -> Dictionary:
	if (
		_resident_presentation == null
		or not _resident_presentation.has_method("get_presentation_snapshot")
	):
		return {}
	return (
		_resident_presentation.get_presentation_snapshot() as Dictionary
	).duplicate(true)


func _screen_edge_direction(delta: Vector2) -> String:
	if delta.is_zero_approx():
		return ""
	var angle := delta.angle()
	if angle >= -PI * 0.125 and angle < PI * 0.125:
		return "east"
	if angle >= PI * 0.125 and angle < PI * 0.375:
		return "south_east"
	if angle >= PI * 0.375 and angle < PI * 0.625:
		return "south"
	if angle >= PI * 0.625 and angle < PI * 0.875:
		return "south_west"
	if angle >= -PI * 0.375 and angle < -PI * 0.125:
		return "north_east"
	if angle >= -PI * 0.625 and angle < -PI * 0.375:
		return "north"
	if angle >= -PI * 0.875 and angle < -PI * 0.625:
		return "north_west"
	return "west"


func get_active_indoor_screen_anchor(local_position_value: Variant) -> Dictionary:
	if (
		not _is_inside_interior()
		or not local_position_value is Array
		or (local_position_value as Array).size() != 2
	):
		return {}
	var room := _interior_roots.get(_active_interior_id) as Node2D
	if room == null:
		return {}
	var values := local_position_value as Array
	var screen_position := room.get_global_transform_with_canvas() * Vector2(
		float(values[0]),
		float(values[1]),
	)
	return {
		"x": screen_position.x,
		"y": screen_position.y,
		"valid": true,
		"coordinateSpace": "viewport_logical",
	}


func get_active_indoor_exit_screen_anchor() -> Dictionary:
	if not _is_inside_interior():
		return {}
	var room := _interior_roots.get(_active_interior_id) as Node2D
	if room == null:
		return {}
	var marker := room.get_node_or_null("IndoorExitPoint") as Marker2D
	if marker == null:
		return {}
	return get_active_indoor_screen_anchor([
		marker.position.x,
		marker.position.y,
	])


func get_session_summary() -> Dictionary:
	var opening := session_config.get("openingConfig", {}) as Dictionary
	return {
		"revision": 0,
		"mode": String(session_config.get("mode", "new_game")),
		"sessionId": String(session_config.get("sessionId", "")),
		"residentCount": (opening.get("residents", []) as Array).size(),
		"started": _world != null and bool(_world.is_running()),
		"identityStatus": _resident_identity_status,
		"validationMode": String(_world_start_result.get("validationMode", "development")),
		"contentStatus": (
			(_world_start_result.get("contentStatus", {}) as Dictionary).duplicate(true)
			if _world_start_result.has("contentStatus")
			else {}
		),
	}


func get_resident_identity_snapshot() -> Dictionary:
	if (
		_world != null
		and _world.has_method("is_running")
		and bool(_world.is_running())
		and _world.has_method("get_resident_identity_snapshot")
	):
		return (
			_world.get_resident_identity_snapshot() as Dictionary
		).duplicate(true)
	return _resident_identity_snapshot_from_local_map()


func update_resident_roster(
	identities_value: Variant,
	bindings_value: Variant,
	opening_config_value: Variant,
) -> Dictionary:
	if (
		not identities_value is Array
		or not bindings_value is Array
		or not opening_config_value is Dictionary
	):
		return _local_command_failure(
			"SESSION_RESIDENT_ROSTER_INVALID",
			"新居民资料无效",
		)
	var identities := (identities_value as Array).duplicate(true)
	var bindings := (bindings_value as Array).duplicate(true)
	if identities.is_empty() or identities.size() != bindings.size():
		return _local_command_failure(
			"SESSION_RESIDENT_ROSTER_INVALID",
			"居民身份与模型绑定数量不一致",
		)
	session_config["residentIdentities"] = identities
	session_config["residentBindings"] = bindings
	session_config["openingConfig"] = (
		opening_config_value as Dictionary
	).duplicate(true)
	var replacement_resident_ids: Array[String] = []
	for identity_value: Variant in identities:
		if not identity_value is Dictionary:
			continue
		var identity := identity_value as Dictionary
		var resident_id := String(identity.get("residentId", ""))
		var resident_name := String(identity.get("residentName", ""))
		if (
			_resident_name_by_id.has(resident_id)
			and String(_resident_name_by_id.get(resident_id, ""))
			!= resident_name
		):
			replacement_resident_ids.append(resident_id)
	_apply_resident_identities({
		"status": "confirmed",
		"residents": identities,
	})
	# 补位复用原住宅席位的 residentId，对应角色节点也会复用。
	# 死亡消散结束后该节点是隐藏的，因此名单更新时必须用最新
	# World 状态强制同步一次，让 normal 生命周期恢复立绘和位置。
	if (
		_resident_presentation != null
		and _resident_presentation.has_method("sync_from_world")
	):
		for resident_id: String in replacement_resident_ids:
			var prepared := _resident_presentation.prepare_resident_replacement(
				resident_id,
			) as Dictionary
			if not bool(prepared.get("ok", false)):
				return _local_command_failure(
					"SESSION_RESIDENT_PRESENTATION_RESET_FAILED",
					"新居民已入镇，但地图角色无法重置",
				)
		var presentation_result := _resident_presentation.sync_from_world(
			true,
		) as Dictionary
		if not bool(presentation_result.get("ok", false)):
			return _local_command_failure(
				"SESSION_RESIDENT_PRESENTATION_REFRESH_FAILED",
				"新居民已入镇，但地图角色刷新失败：%s" % JSON.stringify(
					presentation_result,
				),
			)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"residentCount": identities.size(),
	}


func _resident_identity_snapshot_from_local_map() -> Dictionary:
	var residents: Array[Dictionary] = []
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in _resident_name_by_id:
		resident_ids.append(String(resident_id_value))
	resident_ids.sort()
	for resident_id in resident_ids:
		residents.append({
			"residentId": resident_id,
			"residentName": String(_resident_name_by_id.get(resident_id, "")),
		})
	return {
		"status": _resident_identity_status,
		"residents": residents,
	}


func configure_session(config: Dictionary) -> Dictionary:
	if is_inside_tree():
		return {"ok": false, "errors": ["Town session 必须在节点进入场景树前注入"]}
	if typeof(config.get("openingConfig", {})) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["Town session 的 openingConfig 必须是对象"]}
	if config.has("connectedResidents") and typeof(config.get("connectedResidents")) != TYPE_ARRAY:
		return {"ok": false, "errors": ["Town session 的 connectedResidents 必须是数组"]}
	var start_mode := String(config.get("worldStartMode", "development"))
	if not ["development", "formal"].has(start_mode):
		return {"ok": false, "errors": ["Town session 的 worldStartMode 只能是 development 或 formal"]}
	var identity_result := _prepare_resident_identities(
		config.get("openingConfig", {}) as Dictionary,
		config.get("residentIdentities", []),
		start_mode,
	)
	if not bool(identity_result.get("ok", false)):
		return identity_result
	session_config = config.duplicate(true)
	session_config["worldStartMode"] = start_mode
	session_config["residentIdentities"] = (
		identity_result.get("residents", []) as Array
	).duplicate(true)
	session_config["identityStatus"] = String(identity_result.get("status", "unavailable"))
	_apply_resident_identities(identity_result)
	return {"ok": true}


func complete_restored_session(context: Dictionary) -> Dictionary:
	if not bool(session_config.get("restorePending", false)):
		return RESULT_SHAPES.failure("SESSION_CONTINUE_NOT_PENDING")
	if (
		String(context.get("slot_id", ""))
		!= String(session_config.get("slotId", ""))
		or String(context.get("session_id", ""))
		!= String(session_config.get("sessionId", ""))
	):
		return RESULT_SHAPES.failure("SESSION_CONTINUE_CONTEXT_MISMATCH")
	session_config["restorePending"] = false
	session_config["saveRevision"] = int(context.get("save_revision", 0))
	session_config["identityStatus"] = "confirmed"
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
	}


func get_lifecycle_state() -> Dictionary:
	return _lifecycle_state.duplicate(true)


func set_main_menu_open(open: bool) -> Dictionary:
	return _set_pause_reason("main_menu", open)


func set_resident_editor_open(open: bool) -> Dictionary:
	return _set_pause_reason("resident_editor", open)


func set_conversation_overlay_open(open: bool) -> Dictionary:
	if _world == null:
		return _local_command_failure("WORLD_NOT_RUNNING", "世界尚未运行")
	# Conversation is an in-world overlay. It must not freeze time, movement,
	# schedules, or other residents. Resume the legacy reason if an older host
	# left it behind, then report the overlay state without pausing World.
	var reasons := (_world.get_lifecycle_state() as Dictionary).get(
		"pauseReasons",
		[],
	) as Array
	if reasons.has("conversation"):
		_world.resume("conversation")
		_lifecycle_state = _world.get_lifecycle_state() as Dictionary
		_update_lifecycle_test_display()
	return {
		"ok": true,
		"changed": false,
		"open": open,
		"errorCode": "",
		"retryable": false,
	}


func set_manual_paused(paused: bool) -> Dictionary:
	return _set_pause_reason("manual", paused)


func set_background_paused(paused: bool) -> Dictionary:
	return _set_pause_reason("background", paused)


func set_resident_view_paused(paused: bool) -> Dictionary:
	if paused and _avatar_mode != AVATAR_MODE_OBSERVER:
		return _local_command_failure(
			"OBSERVER_MODE_REQUIRED",
			"居民查看只在自由观察模式开放。",
		)
	# Compatibility shim for older page hosts. Resident pages are live overlays
	# and must never alter simulation pause state.
	return {
		"ok": true,
		"status": "confirmed",
		"residentViewOpen": paused,
		"worldPaused": false,
	}


func _update_animal_presentation_state() -> void:
	if _animal_presentation == null or _player == null:
		return
	var world_running := _world != null and bool(_world.is_running())
	var world_paused := (
		bool(_world.is_paused())
		if world_running
		else true
	)
	var outdoors := not _is_inside_interior()
	var can_interact := (
		enable_player_avatar
		and _avatar_mode == AVATAR_MODE_ACTIVE
		and outdoors
		and world_running
		and not world_paused
		and not _is_text_input_focused()
	)
	_animal_presentation.set_runtime_state(
		_player.position,
		can_interact,
		outdoors,
		world_paused,
	)


func _try_pet_nearest_animal() -> bool:
	if _animal_presentation == null or _player == null:
		return false
	_update_animal_presentation_state()
	var result := _animal_presentation.try_pet_nearest(_player.position)
	if (
		result.get("ok") == true
		and _world != null
		and _world.has_method("record_player_animal_pet")
	):
		_world.record_player_animal_pet(String(result.get("animalId", "")),)
	return result.get("ok") == true


func _on_animal_touch_requested(animal_id: String) -> void:
	# 场景触控与 HUD 动作按钮共用同一正式宠物接口；触控命中的是具体
	# 动物，因此不能退化成“只发信号不执行”。HUD 仍会在需要时调用
	# try_pet_nearest_animal_from_ui()，两条入口都由同一运行时状态门控。
	if _animal_presentation == null or _player == null:
		return
	_update_animal_presentation_state()
	var result := _animal_presentation.try_pet_animal(
		animal_id,
		_player.position,
	)
	if (
		result.get("ok") == true
		and _world != null
		and _world.has_method("record_player_animal_pet")
	):
		_world.record_player_animal_pet(String(result.get("animalId", "")),)


func try_pet_nearest_animal_from_ui() -> Dictionary:
	if _try_pet_nearest_animal():
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
		}
	return {
		"ok": false,
		"errorCode": "NO_NEARBY_ANIMAL",
		"retryable": false,
	}


func get_runtime_state() -> Dictionary:
	return {
		"ok": _startup_error.is_empty(),
		"error": _startup_error,
		"time": _world.get_time() if _world != null else {},
		"weather": _world.get_weather() if _world != null else "",
		"residents": _world.get_all_resident_states() if _world != null else [],
		"connectedAgents": _agent_gateway.get_connected_resident_names() if _agent_gateway != null else [],
		"visibleResidents": _resident_presentation.get_visible_resident_names() if _resident_presentation != null else [],
		"visibleIndoorBadges": _resident_presentation.get_visible_badge_names() if _resident_presentation != null else [],
		"animals": (
			_animal_presentation.get_snapshot()
			if _animal_presentation != null
			else {}
		),
		"followedResident": _followed_resident,
		"selectedResident": _selected_resident,
		"viewMode": "interior" if _is_inside_interior() else "town",
		"observedPlace": _observed_place_name,
		"activeInteriorId": _active_interior_id,
		"buildingHotspotCount": _building_observation_hotspots.size(),
		"outdoorWeatherVisible": _environment_renderer.is_outdoor_visible() if _environment_renderer != null else false,
		"announcementPanelOpen": _announcement_panel != null and _announcement_panel.visible,
		"weatherPanelOpen": _weather_panel != null and _weather_panel.visible,
		"announcementCount": (_world.get_announcements() as Array).size() if _world != null else 0,
		"announcementSignalCount": _announcement_signal_count,
		"lastAnnouncementFeedback": _last_announcement_feedback,
		"lastWeatherFeedback": _last_weather_feedback,
		"playerAvatarEnabled": enable_player_avatar,
		"avatarMode": _avatar_mode,
			"observerCameraPosition": _observer_camera_position,
			"observerCameraInputEnabled": _observer_camera_input_enabled,
			"avatarMovementInputEnabled": (
				_avatar_movement_input_enabled
				and not _avatar_conflict_input_blocked
			),
			"avatarMovementInputRequested": _avatar_movement_input_enabled,
			"avatarConflictInputBlocked": _avatar_conflict_input_blocked,
			"cameraZoomIndex": _zoom_index,
		"cameraZoomRatio": _zoom_value_for_index(_zoom_index),
		"cameraZoomStepCount": ZOOM_LEVELS.size(),
		"cameraZoomBand": _observer_camera_density_band(),
		# Observer zoom is a discrete four-step state machine, so a band can only
		# change after an explicit zoom step. There is no continuous threshold at
		# which the HUD could oscillate between two density layouts.
		"cameraZoomBandStable": true,
		"avatarDescent": get_avatar_descent_snapshot(),
		"playerAvatar": _world.get_player_avatar_state() if _world != null else {},
		"playerConversationPanelOpen": _player_conversation_panel != null and _player_conversation_panel.visible,
		"lastPlayerCommandResult": _last_player_command_result.duplicate(true),
		"agentErrors": _agent_gateway.get_errors() if _agent_gateway != null else [],
		"lifecycle": get_lifecycle_state(),
		"testUiEnabled": enable_test_ui,
		"sessionSource": (
			"injected"
			if not session_config.is_empty()
			else ("explicit_path" if not opening_config_path.is_empty() else "unconfigured")
		),
	}


func get_ui_poll_state() -> Dictionary:
	var animal_snapshot := (
		_animal_presentation.get_interaction_snapshot()
		if _animal_presentation != null
		else {}
	)
	return {
		"paused": bool(_lifecycle_state.get("paused", false)),
		"avatarMode": _avatar_mode,
		"cameraZoomBand": _observer_camera_density_band(),
		# 化身 HUD 的摸动物按钮依赖这个轻量状态。不要把完整动物快照
		# 塞进每 100ms 的轮询，只同步会改变操作按钮的两个字段。
		"animalInteraction": {
			"canInteract": bool(animal_snapshot.get("canInteract", false)),
			"focusedAnimalId": String(animal_snapshot.get("focusedAnimalId", "")),
		},
	}


func get_town_hud_runtime_state() -> Dictionary:
	return {
		# A2:town_hud 走轻量投影;无该方法的测试替身回退全量投影。
		"residents": (
			[] if _world == null
			else _world.get_town_hud_resident_states()
			if _world.has_method("get_town_hud_resident_states")
			else _world.get_all_resident_states()
		),
		"visibleIndoorBadges": (
			_resident_presentation.get_visible_badge_names()
			if _resident_presentation != null
			else []
		),
		"followedResident": _followed_resident,
		"viewMode": "interior" if _is_inside_interior() else "town",
		"observedPlace": _observed_place_name,
		"activeInteriorId": _active_interior_id,
		"playerAvatarEnabled": enable_player_avatar,
		"avatarMode": _avatar_mode,
		"cameraZoomIndex": _zoom_index,
		"cameraZoomRatio": _zoom_value_for_index(_zoom_index),
		"cameraZoomStepCount": ZOOM_LEVELS.size(),
		"cameraZoomBand": _observer_camera_density_band(),
		"cameraZoomBandStable": true,
	}


func select_resident(resident_name: String) -> bool:
	if _world == null:
		return false
	var state := _world.get_resident_state(resident_name) as Dictionary
	if state.is_empty() or not bool(state.get("isPresent", true)):
		return false
	_selected_resident = resident_name
	_resident_presentation.set_selected_resident(resident_name)
	return true


func follow_resident(resident_name: String) -> bool:
	if enable_player_avatar:
		return false
	if _world == null:
		return false
	var state := _world.get_resident_state(resident_name,) as Dictionary
	if state.is_empty() or not bool(state.get("isPresent", true)):
		return false
	var actor := (
		_resident_presentation.get_actor(resident_name)
		as ResidentCharacterBody
	)
	if actor == null:
		return false
	_set_followed_resident(resident_name)
	_set_zoom_index(DEFAULT_ZOOM_INDEX)
	_queue_follow_view_sync()
	_update_runtime_hud()
	return true


func cancel_resident_follow() -> void:
	_set_followed_resident("")
	_update_runtime_hud()


func _set_followed_resident(resident_name: String) -> void:
	var normalized := resident_name.strip_edges()
	if _followed_resident == normalized:
		return
	_followed_resident = normalized
	_follow_view_generation += 1


func zoom_observer_camera(step_delta: int) -> Dictionary:
	if _avatar_mode != AVATAR_MODE_OBSERVER:
		return _avatar_mode_failure("OBSERVER_CAMERA_NOT_ACTIVE")
	if step_delta == 0:
		return _avatar_mode_failure("OBSERVER_CAMERA_ZOOM_DELTA_INVALID")
	var previous_index := _zoom_index
	_set_observer_zoom_index(_zoom_index + clampi(step_delta, -1, 1))
	_update_runtime_hud()
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": previous_index != _zoom_index,
		"zoomIndex": _zoom_index,
	}


func set_observer_camera_input_enabled(enabled: bool) -> Dictionary:
	var changed := _observer_camera_input_enabled != enabled
	_observer_camera_input_enabled = enabled
	if changed:
		_clear_move_action_state()
	if not enabled:
		_cancel_observer_drag()
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": changed,
		"enabled": _observer_camera_input_enabled,
	}


func set_avatar_movement_input_enabled(enabled: bool) -> Dictionary:
	var changed := _avatar_movement_input_enabled != enabled
	_avatar_movement_input_enabled = enabled
	if not enabled:
		_mobile_movement_input.clear()
	if changed:
		_clear_move_action_state()
	if not enabled and enable_player_avatar:
		if _avatar_was_moving:
			_submit_player_avatar_position(true)
		_stop_avatar_visual_motion()
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": changed,
		"enabled": (
			_avatar_movement_input_enabled
			and not _avatar_conflict_input_blocked
		),
		"requestedEnabled": _avatar_movement_input_enabled,
		"conflictBlocked": _avatar_conflict_input_blocked,
	}


func set_virtual_movement_input(value: Vector2) -> void:
	_mobile_movement_input.set_value(value)


func _read_move_input() -> Vector2:
	return _mobile_movement_input.merged_with(super._read_move_input())


func _on_conflict_visuals_changed(snapshot: Dictionary) -> void:
	var avatar_id := "person_7f3a91c2d8e4"
	if _world != null and _world.has_method("get_player_avatar_state"):
		avatar_id = String(
			(_world.get_player_avatar_state() as Dictionary).get(
				"residentId",
				avatar_id,
			)
		).strip_edges()
	var paused_actor_ids := snapshot.get(
		"conflictPausedActorIds",
		[],
	) as Array
	var blocked := paused_actor_ids.has(avatar_id)
	if blocked == _avatar_conflict_input_blocked:
		return
	_avatar_conflict_input_blocked = blocked
	_clear_move_action_state()
	if blocked and enable_player_avatar:
		if _avatar_was_moving:
			_submit_player_avatar_position(true)
		_stop_avatar_visual_motion(false)


func _observer_camera_density_band() -> String:
	# 0 is the whole-map overview and 1 is the distant observer start. The
	# normal 1x camera is the middle information band; 2x is the near band.
	if _zoom_index <= 1:
		return "far"
	if _zoom_index == 2:
		return "middle"
	return "near"


func reset_observer_camera() -> Dictionary:
	if _avatar_mode != AVATAR_MODE_OBSERVER:
		return _avatar_mode_failure("OBSERVER_CAMERA_NOT_ACTIVE")
	_set_followed_resident("")
	_reset_observer_camera(true)
	_update_runtime_hud()
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"zoomIndex": _zoom_index,
	}


func observe_place(place_name: String) -> bool:
	if enable_player_avatar:
		return false
	var portal_id := _portal_id_for_place(place_name)
	if portal_id.is_empty() or _view_sync_active or _portal_transition_active:
		return false
	if (_world.get_place_detail(place_name) as Dictionary).is_empty():
		return false
	_set_followed_resident("")
	await _show_observed_interior(place_name, portal_id)
	_update_runtime_hud()
	return _is_inside_interior() and _observed_place_name == place_name


func request_observe_place(place_name: String) -> Dictionary:
	if enable_player_avatar:
		return _local_command_failure(
			"OBSERVER_MODE_REQUIRED",
			"地点聚焦只能在俯瞰模式进入室内。",
		)
	var normalized := place_name.strip_edges()
	if normalized.is_empty():
		return _local_command_failure(
			"PLACE_NAME_REQUIRED",
			"地点聚焦缺少目标地点。",
		)
	var portal_id := _portal_id_for_place(normalized)
	if portal_id.is_empty():
		return _local_command_failure(
			"PLACE_HAS_NO_INTERIOR",
			"这个地点没有可进入的室内。",
		)
	if _view_sync_active or _portal_transition_active:
		return _local_command_failure(
			"VIEW_TRANSITION_IN_PROGRESS",
			"地点视角正在切换，请稍候。",
			true,
		)
	if _world == null or (_world.get_place_detail(normalized) as Dictionary).is_empty():
		return _local_command_failure(
			"PLACE_NOT_FOUND",
			"世界中没有这个地点。",
		)
	call_deferred("_complete_observe_place_request", normalized)
	return {
		"ok": true,
		"accepted": true,
		"pending": true,
		"placeName": normalized,
		"errorCode": "",
		"retryable": false,
	}


func _complete_observe_place_request(place_name: String) -> void:
	var opened := await observe_place(place_name)
	var result := {
		"ok": opened,
		"accepted": opened,
		"pending": false,
		"transitionKind": "observe_place",
		"placeName": place_name,
		"viewMode": "interior" if opened else String(get_runtime_state().get("viewMode", "town")),
		"errorCode": "" if opened else "PLACE_OBSERVATION_REJECTED",
		"retryable": not opened,
	}
	observed_place_changed.emit(result.duplicate(true))


func return_to_town_overview() -> bool:
	if enable_player_avatar:
		return false
	if _view_sync_active or _portal_transition_active:
		return false
	_set_followed_resident("")
	await _show_town_overview()
	_update_runtime_hud()
	return not _is_inside_interior()


func request_return_to_town_overview() -> Dictionary:
	if enable_player_avatar:
		return _local_command_failure(
			"PHYSICAL_EXIT_REQUIRED",
			"化身模式必须走到室内门口离开。",
		)
	if _view_sync_active or _portal_transition_active:
		return _local_command_failure(
			"VIEW_TRANSITION_IN_PROGRESS",
			"室内视角正在切换，请稍候。",
		)
	if not _is_inside_interior():
		return {
			"ok": true,
			"accepted": true,
			"changed": false,
			"pending": false,
			"errorCode": "",
			"retryable": false,
		}
	var place_name := _observed_place_name
	call_deferred(
		"_complete_return_to_town_overview_request",
		place_name,
	)
	return {
		"ok": true,
		"accepted": true,
		"changed": true,
		"pending": true,
		"errorCode": "",
		"retryable": false,
	}


func _complete_return_to_town_overview_request(place_name: String) -> void:
	var returned := await return_to_town_overview()
	var result := {
		"ok": returned,
		"accepted": returned,
		"pending": false,
		"transitionKind": "return_outdoor",
		"placeName": place_name,
		"viewMode": String(get_runtime_state().get("viewMode", "town")),
		"errorCode": "" if returned else "RETURN_OUTDOOR_REJECTED",
		"retryable": not returned,
	}
	observed_place_changed.emit(result.duplicate(true))


func open_announcement_panel() -> void:
	if _world == null or _announcement_panel == null:
		return
	_close_weather_panel()
	_announcement_panel.open_panel(_world.get_announcements() as Array)


func publish_player_announcement(text: String) -> Dictionary:
	if _world == null:
		return _local_command_failure("WORLD_NOT_RUNNING", "世界尚未运行")
	var result := _world.publish_announcement(text) as Dictionary
	if result.get("ok") == true:
		var announcement := result.get("announcement", {}) as Dictionary
		_last_announcement_feedback = "世界已确认发布：%s" % String(announcement.get("text", ""))
		if _announcement_panel != null:
			_announcement_panel.show_feedback(_last_announcement_feedback, true)
	else:
		_last_announcement_feedback = "发布未生效：%s" % "; ".join(result.get("errors", []))
		if _announcement_panel != null:
			_announcement_panel.show_feedback(_last_announcement_feedback, false)
	return result


func open_weather_panel() -> void:
	if _world == null or _weather_panel == null:
		return
	_close_announcement_panel()
	_weather_panel.open_panel(_world.get_weather())


func request_world_weather(weather: String) -> Dictionary:
	if _world == null:
		return _local_command_failure("WORLD_NOT_RUNNING", "世界尚未运行")
	var result := _world.set_weather(weather) as Dictionary
	if result.get("ok") == true:
		var confirmed_weather := String(_world.get_weather())
		_last_weather_feedback = (
			"世界已确认天气：%s" % confirmed_weather
			if result.get("changed") == true
			else "世界天气已经是：%s" % confirmed_weather
		)
		if _weather_panel != null:
			_weather_panel.set_current_weather(confirmed_weather)
			_weather_panel.show_feedback(_last_weather_feedback, true)
	else:
		_last_weather_feedback = "天气未生效：%s" % "; ".join(result.get("errors", []))
		if _weather_panel != null:
			_weather_panel.set_current_weather(_world.get_weather())
			_weather_panel.show_feedback(_last_weather_feedback, false)
	return result


func player_start_conversation(target_name: String, say: String, narration: String) -> Dictionary:
	if _agent_gateway == null:
		return _local_command_failure(
			"AGENT_GATEWAY_UNAVAILABLE",
			"居民 Agent 尚未连接。",
		)
	_release_text_input_focus()
	if _world == null:
		return _local_player_command_failure("发起对话", "世界尚未运行", "WORLD_NOT_RUNNING")
	var avatar := _world.get_player_avatar_state() as Dictionary
	if not (avatar.get("nearby", []) as Array).has(target_name):
		return _local_player_command_failure(
			"发起对话",
			"目标不在旅行者的世界感知范围内",
			"TARGET_NOT_NEARBY",
		)
	var connected := _agent_gateway.get_connected_resident_names() as Array[String]
	if not connected.has(target_name):
		return _local_player_command_failure(
			"发起对话",
			"目标居民当前未连接 Agent",
			"AGENT_NOT_CONNECTED",
		)
	var result := _world.player_start_conversation(target_name,
		say,
		narration,
		[],) as Dictionary
	_show_player_command_feedback(result)
	if result.get("ok") == true and _agent_gateway != null:
		_hold_agent_dispatch_for_conversation_first_frame()
		_agent_gateway.prioritize_next_conversation_turn()
	return result


func player_reply_conversation(
	conversation_id: String,
	say: String,
	narration: String,
	end: bool,
) -> Dictionary:
	return player_reply_conversation_with_photos(
		conversation_id,
		say,
		narration,
		[],
		end,
	)


func player_reply_conversation_with_photos(
	conversation_id: String,
	say: String,
	narration: String,
	photos: Array,
	end: bool,
) -> Dictionary:
	_release_text_input_focus()
	if _world == null:
		return _local_player_command_failure("继续对话", "世界尚未运行", "WORLD_NOT_RUNNING")
	var result := _world.player_reply_conversation(conversation_id,
		say,
		narration,
		photos.duplicate(true),
		end,) as Dictionary
	_show_player_command_feedback(result)
	if result.get("ok") == true and _agent_gateway != null:
		_hold_agent_dispatch_for_conversation_first_frame()
		_agent_gateway.prioritize_next_conversation_turn()
	return result


func _hold_agent_dispatch_for_conversation_first_frame() -> void:
	_agent_dispatch_hold_process_turns = maxi(
		_agent_dispatch_hold_process_turns,
		CONVERSATION_AGENT_DISPATCH_HOLD_PROCESS_TURNS,
	)
	_agent_dispatch_not_before_drawn_frame = maxi(
		_agent_dispatch_not_before_drawn_frame,
		Engine.get_frames_drawn() + 1,
	)
	_agent_dispatch_first_draw_deadline_msec = maxi(
		_agent_dispatch_first_draw_deadline_msec,
		Time.get_ticks_msec()
			+ CONVERSATION_AGENT_DISPATCH_MAX_FIRST_DRAW_WAIT_MSEC,
	)


func _pump_agent_gateway_for_frame(world_advance: Dictionary = {}) -> void:
	if _agent_gateway == null:
		return
	# 分钟结算、居民表现刷新、地点通知和感知刷新都可能在同一帧聚集大量
	# 主线程工作；把 Agent 的准备和派发留到下一帧，避免两段重活叠加。
	if FRAME_BUDGET_RUNTIME.should_defer_agent_dispatch(world_advance):
		return
	if _agent_dispatch_not_before_drawn_frame >= 0:
		if DisplayServer.get_name() == "headless":
			if _agent_dispatch_hold_process_turns > 0:
				_agent_dispatch_hold_process_turns -= 1
				return
		elif (
			Engine.get_frames_drawn()
			< _agent_dispatch_not_before_drawn_frame
			and Time.get_ticks_msec()
			< _agent_dispatch_first_draw_deadline_msec
		):
			return
		_agent_dispatch_hold_process_turns = 0
		_agent_dispatch_not_before_drawn_frame = -1
		_agent_dispatch_first_draw_deadline_msec = 0
	_agent_gateway.pump_frame_budgeted(AGENT_DISPATCH_BUDGET_PER_FRAME,)


func _schedule_agent_gateway_pump(world_advance: Dictionary) -> void:
	if _agent_gateway == null:
		return
	_agent_gateway_pending_world_advance = world_advance.duplicate(true)
	if _agent_gateway_pump_scheduled:
		return
	_agent_gateway_pump_scheduled = true
	if DisplayServer.get_name() == "headless":
		# Headless runs have no rendered frame signal. A deferred call still runs
		# after the current process turn, preserving physics-before-Agent order.
		call_deferred("_pump_agent_gateway_after_avatar_frame")
	else:
		RenderingServer.frame_post_draw.connect(
			_pump_agent_gateway_after_avatar_frame,
			CONNECT_ONE_SHOT,
		)
		# A minimized or temporarily unavailable renderer must not starve Agent
		# work forever. Keep only one watchdog pending while normal draw signals
		# continue to arrive; the callback is idempotent when the draw signal wins.
		if not _agent_gateway_watchdog_active:
			_agent_gateway_watchdog_active = true
			get_tree().create_timer(0.5, true, false, true).timeout.connect(
				_on_agent_gateway_pump_watchdog,
				CONNECT_ONE_SHOT,
			)


func _on_agent_gateway_pump_watchdog() -> void:
	_agent_gateway_watchdog_active = false
	_pump_agent_gateway_after_avatar_frame()


func _pump_agent_gateway_after_avatar_frame() -> void:
	if not _agent_gateway_pump_scheduled:
		return
	_agent_gateway_pump_scheduled = false
	var world_advance := _agent_gateway_pending_world_advance.duplicate(true)
	_agent_gateway_pending_world_advance.clear()
	if not is_inside_tree() or _agent_gateway == null:
		return
	_pump_agent_gateway_for_frame(world_advance)


func player_end_conversation(conversation_id: String, narration: String) -> Dictionary:
	_release_text_input_focus()
	if _world == null:
		return _local_player_command_failure("结束对话", "世界尚未运行", "WORLD_NOT_RUNNING")
	var result := _world.player_end_conversation(conversation_id, narration) as Dictionary
	_show_player_command_feedback(result)
	return result


func player_reject_conversation(conversation_id: String, narration: String) -> Dictionary:
	_release_text_input_focus()
	if _world == null:
		return _local_player_command_failure("拒绝对话", "世界尚未运行", "WORLD_NOT_RUNNING")
	var result := _world.player_reject_conversation(conversation_id, narration) as Dictionary
	_show_player_command_feedback(result)
	return result


func _start_world() -> void:
	var world_data := _read_json(WORLD_DATA_PATH)
	var opening_result := _resolve_opening_config(world_data)
	if opening_result.get("ok") != true:
		_fail_start("开局配置无效：%s" % "; ".join(opening_result.get("errors", [])))
		return
	_resolve_session_options(opening_result.get("config", {}) as Dictionary)
	_world = WORLD.new()
	var start_mode := String(session_config.get("worldStartMode", "development"))
	var restoring_formal_session := (
		start_mode == "formal"
		and bool(session_config.get("restorePending", false))
		and String(session_config.get("mode", "")) == "continue"
	)
	var start_method := "start_observer"
	if restoring_formal_session:
		start_method = "start_formal_restore_observer"
	elif start_mode == "formal":
		start_method = "start_formal_observer"
	var started := _world.call(
		start_method,
		world_data,
		opening_result.get("config", {}) as Dictionary,
		_world_resident_identity_input(),
	) as Dictionary
	_world_start_result = started.duplicate(true)
	if started.get("ok") != true:
		_fail_start("世界启动失败：%s" % "; ".join(started.get("errors", [])))
		return
	var avatar_hidden := _world.set_player_avatar_present(false,
		false,) as Dictionary
	if avatar_hidden.get("ok") != true:
		_world.stop()
		_fail_start("旁观模式无法隐藏化身")
		return
	var identity_sync := _adopt_world_resident_identities(
		opening_result.get("config", {}) as Dictionary,
	) as Dictionary
	if identity_sync.get("ok") != true:
		if _world.has_method("stop"):
			_world.stop()
		_fail_start("世界身份集合无效：%s" % "; ".join(identity_sync.get("errors", [])))
		return
	_lifecycle_state = _world.get_lifecycle_state() as Dictionary
	_world.connect("lifecycle_state_changed", _on_world_lifecycle_state_changed)
	_environment_renderer = ENVIRONMENT_RENDERER.new()
	_environment_renderer.name = "TownEnvironmentRenderer"
	add_child(_environment_renderer)
	_resident_character_root = Node2D.new()
	_resident_character_root.name = "ResidentCharacterRoot"
	_resident_character_root.y_sort_enabled = true
	add_child(_resident_character_root)
	_animal_presentation = ANIMAL_PRESENTATION.new() as TownAnimalPresentation
	_animal_presentation.name = "TownAnimalPresentation"
	add_child(_animal_presentation)
	_animal_presentation.animal_touch_requested.connect(
		_on_animal_touch_requested,
	)
	var animal_binding := _animal_presentation.bind_character_root(
		_resident_character_root,
	)
	if animal_binding.get("ok") != true:
		_world.stop()
		_fail_start(
			"小动物表现初始化失败：%s" % "; ".join(
				animal_binding.get("errors", []) as Array,
			)
		)
		return
	var animal_navigation_binding := (
		_animal_presentation.bind_outdoor_navigation(
			_runtime_layer_loader.get_runtime_data() as Dictionary
		)
	)
	if animal_navigation_binding.get("ok") != true:
		_world.stop()
		_fail_start(
			"小动物可通行区域初始化失败：%s" % "; ".join(
				animal_navigation_binding.get("errors", []) as Array,
			)
		)
		return
	_resident_presentation = RESIDENT_PRESENTATION.new()
	_resident_presentation.name = "ResidentCharacterPresentation"
	_presentation_screen_anchor_call = Callable(
		_resident_presentation,
		"get_display_screen_anchor",
	)
	_presentation_head_anchor_call = Callable(
		_resident_presentation,
		"get_display_head_screen_anchor",
	)
	add_child(_resident_presentation)
	var resident_binding := _resident_presentation.bind_world(_world,
		_resident_character_root,) as Dictionary
	if not bool(resident_binding.get("ok", false)):
		_world.stop()
		_fail_start(
			"居民角色表现初始化失败：%s" % String(
				resident_binding.get(
					"code",
					"PRESENTATION_BINDING_FAILED",
				)
			)
		)
		return
	var animal_world_binding := _animal_presentation.bind_world_props(
		_world,
		_resident_presentation,
	)
	if animal_world_binding.get("ok") != true:
		_world.stop()
		_fail_start("小动物动态世界道具初始化失败")
		return
	_resident_presentation.connect("resident_selected", _on_resident_selected)
	_resident_presentation.connect(
		"resident_body_space_changed",
		_on_resident_body_space_changed,
	)
	_conflict_presentation_host = CONFLICT_PRESENTATION_HOST.new()
	_conflict_presentation_host.name = "TownConflictPresentationHost"
	add_child(_conflict_presentation_host)
	var conflict_presentation_binding := _conflict_presentation_host.configure(_world,
		_resident_presentation,
		_resident_character_root,) as Dictionary
	if conflict_presentation_binding.get("ok") != true:
		_world.stop()
		_fail_start(
			"居民冲突表现初始化失败：%s" % String(
				conflict_presentation_binding.get(
					"errorCode",
					"CONFLICT_PRESENTATION_BINDING_FAILED",
				)
			)
		)
		return
	var avatar_state := _world.get_player_avatar_state() as Dictionary
	var avatar_actor_id := String(
		avatar_state.get("residentId", "person_7f3a91c2d8e4")
	).strip_edges()
	var avatar_presentation_binding := _conflict_presentation_host.register_external_actor(avatar_actor_id,
		_player,
		_player_visual_root,) as Dictionary
	if avatar_presentation_binding.get("ok") != true:
		_world.stop()
		_fail_start(
			"化身冲突表现初始化失败：%s" % String(
				avatar_presentation_binding.get(
					"errorCode",
					"CONFLICT_AVATAR_PRESENTATION_BINDING_FAILED",
				)
			)
		)
		return
	_conflict_presentation_host.connect(
		"conflict_visuals_changed",
		_on_conflict_visuals_changed,
	)
	_on_conflict_visuals_changed(
		_conflict_presentation_host.debug_snapshot() as Dictionary,
	)
	_load_resident_marker_portrait_paths()
	_build_building_observation_hotspots()
	_build_bulletin_board_hotspot()
	_world.connect("announcement_published", _on_announcement_published)
	_world.connect("environment_changed", _on_environment_changed)
	_world.connect("resident_place_changed", _on_runtime_resident_place_changed)
	_world.connect("world_restored", _on_runtime_world_restored)
	_world.connect("player_avatar_state_changed", _on_runtime_player_avatar_state_changed)
	_world.connect("player_avatar_place_changed", _on_runtime_player_avatar_place_changed)
	_world.connect("player_avatar_perception_changed", _on_runtime_player_avatar_perception_changed)
	_world.connect("player_command_result_created", _on_runtime_player_command_result_created)
	_world.connect("conversation_changed", _on_runtime_conversation_changed)
	_sync_audio_environment(_world.get_time(), String(_world.get_weather()))
	var gateway_result := _initialize_agent_gateway()
	if gateway_result.get("ok") != true:
		_fail_start("Agent Gateway 初始化失败：%s" % "; ".join(gateway_result.get("errors", [])))
		return
	if _agent_gateway != null:
		_agent_gateway.pump_frame_budgeted(AGENT_DISPATCH_BUDGET_PER_FRAME,)
	_ui_adapter = UI_ADAPTER.new()
	_ui_adapter.name = "TownUiAdapter"
	add_child(_ui_adapter)
	_ui_adapter.bind_runtime(self, _world, _agent_gateway, session_config)
	if enable_player_avatar:
		_set_followed_resident("")
		_avatar_outdoor_place = String((_world.get_player_avatar_state() as Dictionary).get("currentPlace", ""))
		_sync_avatar_visual_from_world(true)
		_set_building_hotspots_available(false)
	else:
		# Observer is an independent outdoor camera. Following the first resident
		# here used to pull a fresh session into that resident's home interior.
		_set_followed_resident("")
		_reset_observer_camera(true)
		_set_building_hotspots_available(true)
	_sync_environment_space_occupancy()
	_update_player_conversation_panel()
	_update_runtime_hud()
	_play_audio_cue("session_start")


func _resolve_opening_config(world_data: Dictionary) -> Dictionary:
	if not session_config.is_empty():
		var opening := (session_config.get("openingConfig", {}) as Dictionary).duplicate(true)
		var errors := OPENING.validate(opening, world_data) as Array[String]
		return {"ok": errors.is_empty(), "config": opening, "errors": errors}
	if opening_config_path.is_empty():
		return {
			"ok": false,
			"errors": ["正式 Town 需要由新游戏或读档 session 注入 openingConfig"],
		}
	return OPENING.load_config(opening_config_path, world_data) as Dictionary


func _initialize_agent_gateway() -> Dictionary:
	if _agent_gateway == null:
		_agent_gateway = _create_agent_gateway()
	if _agent_gateway == null:
		if bool(session_config.get("requireAgentGateway", false)):
			return _local_command_failure(
				"AGENT_GATEWAY_REQUIRED",
				"当前 session 要求正式 Agent Gateway。",
			)
		return {"ok": true, "available": false, "errorCode": "", "retryable": false}
	if _agent_gateway.get_parent() == null:
		add_child(_agent_gateway)
	if not _agent_gateway.has_method("bind_world"):
		return {"ok": false, "errors": ["注入的 Agent Gateway 缺少 bind_world(world)"]}
	var bind_result := _agent_gateway.bind_world(_world) as Dictionary
	if not bool(bind_result.get("ok", false)):
		if String(bind_result.get("errorCode", "")).is_empty():
			bind_result["errorCode"] = "AGENT_GATEWAY_BIND_FAILED"
		bind_result["retryable"] = bool(bind_result.get("retryable", false))
		return bind_result
	return _connect_configured_agents()


func _create_agent_gateway() -> Node:
	return null


func _connect_configured_agents() -> Dictionary:
	return {"ok": true, "available": _agent_gateway != null}


func _resolve_session_options(opening: Dictionary) -> void:
	if _resident_name_by_id.is_empty():
		_apply_resident_identities(_compatibility_resident_identities(
			OPENING.resident_names(opening),
		))
	if session_config.has("connectedResidents"):
		connected_residents.clear()
		for value: Variant in session_config.get("connectedResidents", []) as Array:
			var resident_name := String(value)
			if not resident_name.is_empty() and not connected_residents.has(resident_name):
				connected_residents.append(resident_name)
	if connected_residents.is_empty():
		connected_residents = OPENING.resident_names(opening)


func _prepare_resident_identities(
	opening: Dictionary,
	identity_values: Variant,
	start_mode: String,
) -> Dictionary:
	return OPENING.prepare_resident_identities(
		opening,
		identity_values,
		start_mode == "formal",
	) as Dictionary


func _world_resident_identity_input() -> Array:
	if _resident_identity_status != "confirmed":
		return []
	return (
		session_config.get("residentIdentities", []) as Array
	).duplicate(true)


func _adopt_world_resident_identities(opening: Dictionary) -> Dictionary:
	if _world == null or not _world.has_method("get_resident_identity_snapshot"):
		return _identity_failure(
			"SESSION_WORLD_IDENTITY_INTERFACE_MISSING",
			"World 未提供居民身份只读快照。",
		)
	var snapshot := _world.get_resident_identity_snapshot() as Dictionary
	var world_status := String(snapshot.get("status", "unavailable"))
	if not ["confirmed", "compatibility"].has(world_status):
		return _identity_failure(
			"SESSION_WORLD_IDENTITY_STATUS_INVALID",
			"World 居民身份状态无效：%s" % world_status,
		)
	if _resident_identity_status == "confirmed" and world_status != "confirmed":
		return _identity_failure(
			"SESSION_WORLD_IDENTITY_NOT_CONFIRMED",
			"正式 session 的 World 居民身份集合未确认。",
		)
	var world_result := _prepare_resident_identities(
		opening,
		snapshot.get("residents", []),
		"development",
	)
	if world_result.get("ok") != true:
		return _identity_failure(
			"SESSION_WORLD_IDENTITY_SNAPSHOT_INVALID",
			"World 居民身份快照不是完整双键集合。",
		)
	var expected := _resident_identity_snapshot_from_local_map()
	if (
		(world_result.get("residents", []) as Array)
		!= (expected.get("residents", []) as Array)
	):
		return _identity_failure(
			"SESSION_WORLD_IDENTITY_MISMATCH",
			"World 居民身份集合与 session 不一致。",
		)
	var adopted := {
		"status": world_status,
		"residents": (world_result.get("residents", []) as Array).duplicate(true),
	}
	_apply_resident_identities(adopted)
	if not session_config.is_empty():
		session_config["residentIdentities"] = (
			adopted.get("residents", []) as Array
		).duplicate(true)
		session_config["identityStatus"] = world_status
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"status": world_status,
	}


func _compatibility_resident_identities(resident_names: Array[String]) -> Dictionary:
	var residents: Array[Dictionary] = []
	for resident_name in resident_names:
		residents.append({
			"residentId": resident_name,
			"residentName": resident_name,
		})
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"status": "compatibility",
		"residents": residents,
	}


func _apply_resident_identities(result: Dictionary) -> void:
	_resident_id_by_name.clear()
	_resident_name_by_id.clear()
	for value: Variant in result.get("residents", []) as Array:
		var identity := value as Dictionary
		var resident_id := String(identity.get("residentId", ""))
		var resident_name := String(identity.get("residentName", ""))
		if resident_id.is_empty() or resident_name.is_empty():
			continue
		_resident_name_by_id[resident_id] = resident_name
		_resident_id_by_name[resident_name] = resident_id
	_resident_identity_status = String(result.get("status", "unavailable"))


func _identity_failure(error_code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"worldRevision": 0,
		"errors": [message],
	}


func _apply_session_presentation_options() -> void:
	if session_config.has("useLiveModel"):
		use_live_model = bool(session_config.get("useLiveModel"))
	# Legacy saves may contain enablePlayerAvatar=true. Session entry is still
	# observer; the runtime state machine owns later avatar activation.
	enable_player_avatar = false
	if session_config.has("enableTestUi"):
		enable_test_ui = bool(session_config.get("enableTestUi"))


func _enable_avatar_control() -> void:
	_player.visible = true
	_player.collision_layer = 2
	_player.collision_mask = AVATAR_COLLISION_MASK
	if _player_feet_collision != null:
		_player_feet_collision.disabled = false


func _disable_avatar_control() -> void:
	_player.visible = false
	_player.collision_layer = 0
	_player.collision_mask = 0
	if _player_feet_collision != null:
		_player_feet_collision.disabled = true


func get_avatar_mode() -> String:
	return _avatar_mode


func enter_avatar_mode() -> Dictionary:
	if _avatar_mode != AVATAR_MODE_OBSERVER:
		return _avatar_mode_failure("AVATAR_MODE_TRANSITION_INVALID")
	if _world == null or not _world.is_running():
		return _avatar_mode_failure("WORLD_NOT_RUNNING")
	if _view_sync_active or _portal_transition_active:
		return _avatar_mode_failure("OBSERVER_VIEW_TRANSITION_ACTIVE")
	var landing_context := _avatar_view_center_landing_context()
	if landing_context.is_empty():
		return _avatar_mode_failure("AVATAR_VIEW_CENTER_UNAVAILABLE")
	var landing := _world.prepare_player_avatar_descent(String(landing_context.get("spaceId", "")),
		landing_context.get("position", Vector2.ZERO) as Vector2,) as Dictionary
	if landing.get("ok") != true:
		landing["mode"] = _avatar_mode
		return landing
	_set_followed_resident("")
	_avatar_outdoor_place = String(
		landing.get(
			"outdoorReturnPlace",
			(landing.get("state", {}) as Dictionary).get(
				"currentPlace",
				"",
			),
		),
	)
	_sync_avatar_visual_from_world(false, true, false)
	var presentation_started := _set_avatar_mode(AVATAR_MODE_DESCENT)
	if presentation_started.get("ok") != true:
		# The World has already confirmed the avatar landing. A missing or
		# unready visual presentation must not leave movement and collision
		# permanently locked in avatar_descent. Keep that state for the rest of
		# this dispatch so repeated clicks are still rejected, then finish the
		# transition on the next idle turn.
		_complete_avatar_descent_after_presentation_start_failure.call_deferred()
	return {
		"ok": true,
		"mode": _avatar_mode,
		"durationMsec": int(presentation_started.get("durationMsec", 0)),
		"presentationStarted": presentation_started.get("ok") == true,
		"landing": (
			landing.get("landing", {}) as Dictionary
		).duplicate(true),
	}


func _avatar_view_center_landing_context() -> Dictionary:
	var screen_center := (
		_camera.get_screen_center_position()
		if is_inside_tree()
		else _observer_camera_position
	)
	if not screen_center.is_finite():
		return {}
	if not _is_inside_interior():
		return {
			"spaceId": "town_outdoor",
			"position": screen_center,
		}
	if _observed_place_name.is_empty():
		return {}
	var place := _world.get_place_detail(_observed_place_name,) as Dictionary
	var space_id := String(place.get("spaceId", ""))
	var room := _interior_roots.get(_active_interior_id) as Node2D
	if space_id.is_empty() or room == null:
		return {}
	return {
		"spaceId": space_id,
		"position": screen_center - room.position,
	}


func complete_avatar_descent() -> Dictionary:
	if _avatar_mode != AVATAR_MODE_DESCENT:
		return _avatar_mode_failure("AVATAR_MODE_TRANSITION_INVALID")
	_set_avatar_mode(AVATAR_MODE_ACTIVE)
	return {"ok": true, "mode": _avatar_mode}


func exit_avatar_mode() -> Dictionary:
	if _avatar_mode != AVATAR_MODE_ACTIVE:
		return _avatar_mode_failure("AVATAR_MODE_TRANSITION_INVALID")
	if _avatar_conflict_input_blocked:
		return _avatar_mode_failure("AVATAR_CONFLICT_ACTIVE")
	var avatar := _world.get_player_avatar_state() as Dictionary if _world != null else {}
	var conversation_id := String(avatar.get("conversationId", ""))
	if conversation_id.is_empty() and avatar.get("conversation") is Dictionary:
		conversation_id = String((avatar.get("conversation") as Dictionary).get("conversation_id", ""))
	if not conversation_id.is_empty():
		return _avatar_mode_failure("AVATAR_CONVERSATION_ACTIVE")
	var hidden := _world.set_player_avatar_present(false) as Dictionary
	if hidden.get("ok") != true:
		return hidden
	_set_avatar_mode(AVATAR_MODE_OBSERVER)
	call_deferred("_restore_outdoor_observer_view")
	return {"ok": true, "mode": _avatar_mode}


func _set_avatar_mode(next_mode: String) -> Dictionary:
	var previous_mode := _avatar_mode
	_avatar_mode = next_mode
	enable_player_avatar = next_mode == AVATAR_MODE_ACTIVE
	var presentation_result := {"ok": true}
	if next_mode == AVATAR_MODE_DESCENT:
		_prepare_avatar_descent_control()
		if is_instance_valid(_avatar_descent_presentation):
			presentation_result = _avatar_descent_presentation.start(
				_player_visual_root,
				_player_shadow,
				_camera,
			)
		else:
			presentation_result = {
				"ok": false,
				"errorCode": "AVATAR_DESCENT_PRESENTATION_NOT_READY",
			}
	elif enable_player_avatar:
		_enable_avatar_control()
		_set_zoom_index(DEFAULT_ZOOM_INDEX)
		_sync_avatar_visual_from_world(true)
	else:
		if _avatar_descent_presentation != null:
			_avatar_descent_presentation.cancel()
		_stop_avatar_visual_motion()
		_disable_avatar_control()
	# The availability method keeps desktop avatar mode unchanged while allowing
	# mobile avatar taps to route to a building entrance.
	_set_building_hotspots_available(true)
	avatar_mode_changed.emit(_avatar_mode, previous_mode)
	_update_runtime_hud()
	return presentation_result


func _avatar_mode_failure(error_code: String) -> Dictionary:
	return {"ok": false, "errorCode": error_code, "retryable": false, "mode": _avatar_mode}


func get_avatar_descent_snapshot() -> Dictionary:
	if _avatar_descent_presentation == null:
		return {"active": false, "elapsedMsec": 0, "cueEmitted": false, "inputLocked": false}
	return _avatar_descent_presentation.debug_snapshot()


func _configure_formal_player_avatar_sprite() -> void:
	if _player_sprite == null:
		return
	_player_sprite.texture = FORMAL_PLAYER_AVATAR_TEXTURE
	_player_sprite.hframes = 4
	_player_sprite.vframes = 4
	_player_sprite.centered = false
	_player_sprite.position = Vector2(-32.0, -72.0)
	_player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_sprite.frame_coords = Vector2i(0, 0)
	_player_sprite.configure_motion_speed(PLAYER_SPEED)


func _build_avatar_descent_presentation() -> void:
	_avatar_descent_presentation = AVATAR_DESCENT_PRESENTATION.new() as AvatarDescentPresentation
	_avatar_descent_presentation.name = "AvatarDescentPresentation"
	_player.add_child(_avatar_descent_presentation)
	_avatar_descent_presentation.timeline_completed.connect(_on_avatar_descent_timeline_completed)
	_avatar_descent_presentation.input_unlocked.connect(_on_avatar_descent_input_unlocked)
	_avatar_descent_presentation.cue_requested.connect(_on_avatar_descent_cue_requested)


func _prepare_avatar_descent_control() -> void:
	_player.visible = true
	_player.velocity = Vector2.ZERO
	_player.collision_layer = 0
	_player.collision_mask = 0
	if _player_feet_collision != null:
		_player_feet_collision.disabled = true


func _on_avatar_descent_timeline_completed() -> void:
	if _avatar_mode == AVATAR_MODE_DESCENT:
		complete_avatar_descent()


func _complete_avatar_descent_after_presentation_start_failure() -> void:
	if _avatar_mode == AVATAR_MODE_DESCENT:
		complete_avatar_descent()


func _on_avatar_descent_input_unlocked() -> void:
	if _avatar_mode == AVATAR_MODE_DESCENT:
		complete_avatar_descent()


func _on_avatar_descent_cue_requested(cue_id: String) -> void:
	_play_audio_cue(cue_id)


func _update_camera_target(reset_smoothing := false) -> void:
	if _avatar_mode == AVATAR_MODE_OBSERVER:
		_camera.position = _observer_camera_position
		if reset_smoothing:
			_camera.reset_smoothing()
		return
	super._update_camera_target(reset_smoothing)


func _reset_observer_camera(reset_smoothing := false) -> void:
	_observer_drag_active = false
	_observer_drag_button = MOUSE_BUTTON_NONE
	if not _is_inside_interior():
		_set_camera_limits(Rect2(Vector2.ZERO, MAP_SIZE))
		_observer_camera_position = OBSERVER_START_POSITION
	else:
		_observer_camera_position = _observer_camera_bounds().get_center()
	_set_observer_zoom_index(OBSERVER_START_ZOOM_INDEX)
	_update_camera_target(reset_smoothing)


func _restore_outdoor_observer_view() -> void:
	if _avatar_mode != AVATAR_MODE_OBSERVER:
		return
	_set_followed_resident("")
	if _is_inside_interior():
		await _show_town_overview()
	if not is_inside_tree() or _avatar_mode != AVATAR_MODE_OBSERVER:
		return
	_reset_observer_camera(true)


func _update_observer_camera_input(delta: float) -> void:
	if not _observer_camera_accepts_input():
		_cancel_observer_drag()
		return
	var direction := _read_move_input()
	if direction.length_squared() <= 0.0001:
		return
	_stop_following_for_observer_pan()
	direction = direction.normalized()
	var zoom_value := maxf(_camera.zoom.x, 0.001)
	_set_observer_camera_position(
		_observer_camera_position + direction * OBSERVER_PAN_SCREEN_SPEED * delta / zoom_value,
	)


func _observer_camera_accepts_input() -> bool:
	return (
		_observer_camera_input_enabled
		and _avatar_mode == AVATAR_MODE_OBSERVER
		and _world != null
		and not bool(_world.is_paused())
		and not _is_text_input_focused()
	)


func _observer_camera_accepts_zoom_input() -> bool:
	return (
		_observer_camera_input_enabled
		and _avatar_mode == AVATAR_MODE_OBSERVER
		and _world != null
		and bool(_world.is_running())
		and not _is_text_input_focused()
	)


func _handle_observer_zoom_input(event: InputEvent) -> bool:
	if not _observer_camera_accepts_zoom_input():
		return false
	if event is InputEventMouseButton:
		if not event.pressed:
			return false
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_observer_magnify_accumulator = 0.0
			_set_observer_zoom_index(_zoom_index + 1)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_observer_magnify_accumulator = 0.0
			_set_observer_zoom_index(_zoom_index - 1)
			return true
		return false
	if event is InputEventMagnifyGesture:
		var factor := maxf(event.factor, 0.001)
		_observer_magnify_accumulator += log(factor)
		var zoom_step := 0
		if _observer_magnify_accumulator >= OBSERVER_MAGNIFY_STEP_THRESHOLD:
			zoom_step = 1
			_observer_magnify_accumulator -= OBSERVER_MAGNIFY_STEP_THRESHOLD
		elif _observer_magnify_accumulator <= -OBSERVER_MAGNIFY_STEP_THRESHOLD:
			zoom_step = -1
			_observer_magnify_accumulator += OBSERVER_MAGNIFY_STEP_THRESHOLD
		if zoom_step != 0:
			_set_observer_zoom_index(_zoom_index + zoom_step)
		return true
	return false


func _avatar_camera_accepts_zoom_input() -> bool:
	return (
		enable_player_avatar
		and _avatar_mode == AVATAR_MODE_ACTIVE
		and _avatar_movement_input_enabled
		and not _avatar_conflict_input_blocked
		and _world != null
		and bool(_world.is_running())
		and not _is_text_input_focused()
	)


func _handle_avatar_zoom_input(event: InputEvent) -> bool:
	if not _avatar_camera_accepts_zoom_input():
		return false
	if event is InputEventMouseButton:
		if not event.pressed:
			return false
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_avatar_magnify_accumulator = 0.0
			_set_zoom_index(_zoom_index + 1)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_avatar_magnify_accumulator = 0.0
			_set_zoom_index(_zoom_index - 1)
			return true
		return false
	if event is InputEventMagnifyGesture:
		var factor := maxf(event.factor, 0.001)
		_avatar_magnify_accumulator += log(factor)
		var zoom_step := 0
		if _avatar_magnify_accumulator >= OBSERVER_MAGNIFY_STEP_THRESHOLD:
			zoom_step = 1
			_avatar_magnify_accumulator -= OBSERVER_MAGNIFY_STEP_THRESHOLD
		elif _avatar_magnify_accumulator <= -OBSERVER_MAGNIFY_STEP_THRESHOLD:
			zoom_step = -1
			_avatar_magnify_accumulator += OBSERVER_MAGNIFY_STEP_THRESHOLD
		if zoom_step != 0:
			_set_zoom_index(_zoom_index + zoom_step)
		return true
	return false


func _handle_touch_camera_input(event: InputEvent, allow_pan: bool) -> bool:
	if not event is InputEventScreenTouch and not event is InputEventScreenDrag:
		return false
	var accepts_input := (
		_observer_camera_accepts_input()
		if allow_pan
		else _avatar_camera_accepts_zoom_input()
	)
	if not accepts_input:
		_touch_camera_gesture.reset()
		return false
	var gesture := _touch_camera_gesture.consume(event)
	if not bool(gesture.get("handled", false)):
		return false
	var pan := gesture.get("pan", Vector2.ZERO) as Vector2
	if allow_pan and pan.length_squared() > 0.0:
		_stop_following_for_observer_pan()
		var zoom_value := maxf(_camera.zoom.x, 0.001)
		_set_observer_camera_position(
			_observer_camera_position - pan / zoom_value,
			true,
		)
	var pinch_log := float(gesture.get("pinchLog", 0.0))
	if not is_zero_approx(pinch_log):
		_apply_touch_zoom_log(pinch_log, allow_pan)
	return true


func _apply_touch_zoom_log(pinch_log: float, observer: bool) -> void:
	if observer:
		_observer_magnify_accumulator += pinch_log
		if _observer_magnify_accumulator >= OBSERVER_MAGNIFY_STEP_THRESHOLD:
			_observer_magnify_accumulator -= OBSERVER_MAGNIFY_STEP_THRESHOLD
			_set_observer_zoom_index(_zoom_index + 1)
		elif _observer_magnify_accumulator <= -OBSERVER_MAGNIFY_STEP_THRESHOLD:
			_observer_magnify_accumulator += OBSERVER_MAGNIFY_STEP_THRESHOLD
			_set_observer_zoom_index(_zoom_index - 1)
		return
	_avatar_magnify_accumulator += pinch_log
	if _avatar_magnify_accumulator >= OBSERVER_MAGNIFY_STEP_THRESHOLD:
		_avatar_magnify_accumulator -= OBSERVER_MAGNIFY_STEP_THRESHOLD
		_set_zoom_index(_zoom_index + 1)
	elif _avatar_magnify_accumulator <= -OBSERVER_MAGNIFY_STEP_THRESHOLD:
		_avatar_magnify_accumulator += OBSERVER_MAGNIFY_STEP_THRESHOLD
		_set_zoom_index(_zoom_index - 1)


func _is_primary_pointer_press(event: InputEvent) -> bool:
	return (
		(
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		)
		or (event is InputEventScreenTouch and event.pressed)
	)


func _cancel_observer_drag() -> void:
	_observer_drag_active = false
	_observer_drag_button = MOUSE_BUTTON_NONE
	_touch_camera_gesture.reset()


func _stop_following_for_observer_pan() -> void:
	if _followed_resident.is_empty():
		return
	_set_followed_resident("")


func _set_observer_zoom_index(value: int) -> void:
	_set_zoom_index(value)
	if not _followed_resident.is_empty():
		_update_follow_camera(true)
		return
	if _zoom_index == OVERVIEW_ZOOM_INDEX:
		_observer_camera_position = MAP_SIZE * 0.5
	_set_observer_camera_position(_observer_camera_position, true)


func _set_observer_camera_position(position: Vector2, reset_smoothing := false) -> void:
	var zoom_value := maxf(_camera.zoom.x, 0.001)
	var half_view := get_viewport_rect().size * 0.5 / zoom_value
	var camera_bounds := _observer_camera_bounds()
	var next_position := position
	if half_view.x * 2.0 >= camera_bounds.size.x:
		next_position.x = camera_bounds.get_center().x
	else:
		next_position.x = clampf(
			next_position.x,
			camera_bounds.position.x + half_view.x,
			camera_bounds.end.x - half_view.x,
		)
	if half_view.y * 2.0 >= camera_bounds.size.y:
		next_position.y = camera_bounds.get_center().y
	else:
		next_position.y = clampf(
			next_position.y,
			camera_bounds.position.y + half_view.y,
			camera_bounds.end.y - half_view.y,
		)
	_observer_camera_position = next_position
	_update_camera_target(reset_smoothing)


func _observer_camera_bounds() -> Rect2:
	if not _is_inside_interior():
		return Rect2(Vector2.ZERO, MAP_SIZE)
	return Rect2(
		Vector2(_camera.limit_left, _camera.limit_top),
		Vector2(
			_camera.limit_right - _camera.limit_left,
			_camera.limit_bottom - _camera.limit_top,
		),
	)


func _on_camera_viewport_size_changed() -> void:
	super._on_camera_viewport_size_changed()
	_update_building_resident_marker_zoom()
	if (
		_avatar_mode == AVATAR_MODE_OBSERVER
		and _zoom_index != OVERVIEW_ZOOM_INDEX
	):
		_set_observer_camera_position(_observer_camera_position, true)


func _set_zoom_index(value: int) -> void:
	super._set_zoom_index(value)
	_update_building_resident_marker_zoom()


func _update_building_resident_marker_zoom() -> void:
	if _camera == null:
		return
	for marker_value: Variant in _building_resident_markers.values():
		var marker := marker_value as Node
		if marker != null and marker.has_method("set_camera_zoom"):
			marker.call("set_camera_zoom", _camera.zoom)
	if (
		is_instance_valid(_building_entry_confirm)
		and _building_entry_confirm.has_method("set_camera_zoom")
	):
		_building_entry_confirm.call("set_camera_zoom", _camera.zoom)


func _update_follow_camera(reset_smoothing := false) -> void:
	if _avatar_mode != AVATAR_MODE_OBSERVER or _world == null or _followed_resident.is_empty():
		return
	var state := _world.get_resident_state(_followed_resident) as Dictionary
	if state.is_empty() or not bool(state.get("isPresent", true)):
		_set_followed_resident("")
		return
	var actor := (
		_resident_presentation.get_actor(_followed_resident)
		as ResidentCharacterBody
	)
	if actor == null:
		_set_followed_resident("")
		return
	var actor_space_id := actor.get_space_id()
	if not _follow_view_matches_space(actor_space_id):
		_queue_follow_view_sync()
		return
	if not actor.visible or not actor.position.is_finite():
		_set_followed_resident("")
		return
	_player.position = actor.position
	_observer_camera_position = _player.position
	_update_camera_target(reset_smoothing)
	# The current commercial HUD intentionally has no ordinary resident action
	# preview. Do not register an invisible observation hold with World while
	# following; background and focused residents execute confirmed actions
	# immediately. Resident-to-resident conversations keep their separate,
	# visible spectator entry.


func _follow_next_resident() -> void:
	if _world == null:
		return
	var present_residents: Array[String] = []
	for resident_name in connected_residents:
		var state := _world.get_resident_state(resident_name,) as Dictionary
		if bool(state.get("isPresent", true)):
			present_residents.append(resident_name)
	if present_residents.is_empty():
		_set_followed_resident("")
		return
	var index := present_residents.find(_followed_resident)
	_set_followed_resident(
		present_residents[(index + 1) % present_residents.size()]
	)
	_set_zoom_index(DEFAULT_ZOOM_INDEX)
	_queue_follow_view_sync()


func _cycle_world_weather() -> void:
	var weather_types := ["晴天", "阴天", "小雨", "中雨", "大雨", "雷暴", "下雪"]
	var index := weather_types.find(String(_world.get_weather()))
	_world.set_weather(weather_types[(index + 1) % weather_types.size()])


func _build_runtime_hud() -> void:
	pass


func _on_resident_selected(
	_resident_id: String,
	resident_name: String,
) -> void:
	if (
		_avatar_mode != AVATAR_MODE_OBSERVER
		and not (
			MOBILE_UI_PROFILE.is_mobile_runtime()
			and _avatar_mode == AVATAR_MODE_ACTIVE
		)
	):
		return
	if not select_resident(resident_name):
		return
	if _ui_adapter == null or not _ui_adapter.has_method("open_ui_page"):
		clear_resident_selection()
		return
	var routed := _ui_adapter.open_ui_page("resident_action_menu",
		{
			"residentId": _resident_id_by_name.get(resident_name, ""),
			"residentName": resident_name,
		},) as Dictionary
	if not bool(routed.get("ok", false)):
		clear_resident_selection()


func attach_world_resident_action_menu(
	menu: Control,
	context: Dictionary,
) -> Dictionary:
	if menu == null or _resident_presentation == null:
		return RESULT_SHAPES.failure("RESIDENT_WORLD_MENU_TARGET_UNAVAILABLE")
	var resident_ref := String(context.get("residentId", "")).strip_edges()
	if resident_ref.is_empty():
		resident_ref = String(context.get("residentName", "")).strip_edges()
	if resident_ref.is_empty():
		resident_ref = _selected_resident
	var body := _resident_presentation.get_actor(resident_ref) as Node2D
	var menu_parent: Node2D = body if body != null and body.visible else null
	var menu_position := Vector2.ZERO
	if menu_parent == null:
		# 室内居民没有可见本体，五项菜单锚到其房顶头像所在标记；
		# 不在任何房顶名单中的隐藏居民仍然拒绝挂载，避免菜单落在空处。
		for marker_value: Variant in _building_resident_markers.values():
			var marker := marker_value as Node2D
			if marker == null or not marker.visible:
				continue
			if bool(marker.contains_resident(resident_ref)):
				menu_parent = marker
				menu_position = marker.menu_anchor_for_resident(resident_ref,) as Vector2
				break
	if menu_parent == null:
		return RESULT_SHAPES.failure("RESIDENT_WORLD_MENU_TARGET_NOT_VISIBLE")
	# 可见居民的 Control 根节点必须挂在身体脚点，六个气泡只使用这个
	# 根节点下的局部坐标展开。屏幕边界修正会把根节点推离身体，导致整套
	# 菜单看起来像是跟着对话气泡走。没有可见身体时，屋顶居民标记才需要
	# 用边界修正保住菜单可见性。
	if menu_parent != body:
		menu_position = _resident_action_menu_safe_anchor(menu_parent, menu_position)
	menu_parent.add_child(menu)
	menu.position = menu_position
	if MOBILE_UI_PROFILE.is_mobile_runtime() and menu_parent == body:
		# World bubbles must retain a finger-sized on-screen hit target even when
		# the observer camera is zoomed out to show the whole town.
		var minimum_zoom := minf(
			maxf(absf(_camera.zoom.x), 0.001),
			maxf(absf(_camera.zoom.y), 0.001),
		)
		menu.scale = Vector2.ONE * maxf(1.0, 1.0 / minimum_zoom)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentId": (
			String(body.get_resident_id())
			if body != null
			else resident_ref
		),
		"residentName": (
			String(body.get_resident_name())
			if body != null
			else resident_ref
		),
	}


func clear_resident_selection() -> void:
	_selected_resident = ""
	if _resident_presentation != null:
		_resident_presentation.set_selected_resident("")


func _on_building_pressed(place_name: String) -> void:
	if _avatar_mode != AVATAR_MODE_OBSERVER:
		_show_player_command_feedback(
			_local_command_failure(
				"OBSERVER_MODE_REQUIRED",
				"化身模式下不能从建筑入口进入室内。",
				false,
			)
		)
		return
	var normalized := place_name.strip_edges()
	if normalized.is_empty() or _portal_id_for_place(normalized).is_empty():
		_show_player_command_feedback(
			_local_command_failure(
				"PLACE_HAS_NO_INTERIOR",
				"这个地点没有可进入的室内。",
				false,
			)
		)
		return
	if (
		_ui_adapter != null
		and _ui_adapter.has_method("dismiss_resident_action_menu")
		and not bool(_ui_adapter.call("dismiss_resident_action_menu"))
	):
		return
	_show_building_entry_confirm(normalized)


func _show_building_entry_confirm(place_name: String) -> void:
	var normalized := place_name.strip_edges()
	if normalized.is_empty() or _portal_id_for_place(normalized).is_empty():
		return
	if (
		is_instance_valid(_building_entry_confirm)
		and _building_entry_confirm_place_name == normalized
	):
		return
	_dismiss_building_entry_confirm()
	_collapse_building_resident_marker()
	var hotspot := _building_observation_hotspots.get(normalized, null) as Node2D
	if hotspot == null:
		return
	var marker := _building_resident_markers.get(normalized, null) as Node2D
	var resident_entries: Array = []
	var local_anchor := Vector2(0.0, -150.0)
	var entry_display_size := _building_entry_confirm_display_size()
	if marker != null:
		resident_entries = marker.resident_entries() as Array
		var marker_display_size := marker.display_size() as Vector2
		local_anchor = marker.position + Vector2(
			0.0,
			-marker_display_size.y * 0.5
				- entry_display_size.y * 0.5
				- 8.0 * entry_display_size.y / BUILDING_ENTRY_CONFIRM_SIZE.y,
		)
	local_anchor = _building_entry_confirm_safe_anchor(
		hotspot,
		local_anchor,
		entry_display_size,
	)
	var confirm := BUILDING_ENTRY_CONFIRM.new() as Node2D
	if not bool(confirm.configure(normalized,
		resident_entries,
		local_anchor,)):
		confirm.free()
		return
	if MOBILE_UI_PROFILE.is_mobile_runtime():
		confirm.set_touch_scale_multiplier(
			MOBILE_BUILDING_ENTRY_CONFIRM_TOUCH_SCALE
		)
	confirm.set_camera_zoom(_camera.zoom)
	confirm.connect("enter_requested", _on_building_entry_confirmed)
	hotspot.add_child(confirm)
	_building_entry_confirm = confirm
	_building_entry_confirm_place_name = normalized


func _on_building_entry_confirmed(place_name: String) -> void:
	if _avatar_mode != AVATAR_MODE_OBSERVER:
		_show_player_command_feedback(
			_local_command_failure(
				"OBSERVER_MODE_REQUIRED",
				"化身模式下不能从建筑入口进入室内。",
				false,
			)
		)
		return
	_dismiss_building_entry_confirm()
	var requested := request_observe_place(place_name)
	if bool(requested.get("ok", false)):
		_clear_focused_building()
		return
	_show_player_command_feedback(
		_local_command_failure(
			String(requested.get("errorCode", "PLACE_OBSERVATION_REJECTED")),
			String(requested.get("reason", "暂时无法进入这个地点。")),
			bool(requested.get("retryable", true)),
		)
	)


func _on_building_resident_pressed(
	resident_id: String,
	resident_name: String,
) -> void:
	_dismiss_building_entry_confirm()
	_collapse_building_resident_marker()
	_on_resident_selected(resident_id, resident_name)


func _on_building_resident_marker_expanded(
	place_name: String,
	expanded: bool,
) -> void:
	var marker := _building_resident_markers.get(place_name, null) as Node2D
	if not expanded:
		if marker == _expanded_building_resident_marker:
			_expanded_building_resident_marker = null
		return
	if (
		is_instance_valid(_expanded_building_resident_marker)
		and _expanded_building_resident_marker != marker
	):
		_expanded_building_resident_marker.collapse()
	_expanded_building_resident_marker = marker
	_dismiss_building_entry_confirm()


func _collapse_building_resident_marker() -> void:
	if is_instance_valid(_expanded_building_resident_marker):
		var marker := _expanded_building_resident_marker
		_expanded_building_resident_marker = null
		marker.collapse()
	else:
		_expanded_building_resident_marker = null


func _dismiss_building_entry_confirm() -> void:
	if is_instance_valid(_building_entry_confirm):
		_building_entry_confirm.queue_free()
	_building_entry_confirm = null
	_building_entry_confirm_place_name = ""


func _building_entry_confirm_safe_anchor(
	hotspot: Node2D,
	desired_local_anchor: Vector2,
	confirm_display_size: Vector2 = BUILDING_ENTRY_CONFIRM_SIZE,
) -> Vector2:
	if hotspot == null or _camera == null or not _camera.is_inside_tree():
		return desired_local_anchor
	var zoom_value := maxf(_camera.zoom.x, 0.001)
	var viewport_size := get_viewport_rect().size
	var camera_center := _camera.get_screen_center_position()
	var world_half_size := viewport_size * 0.5 / zoom_value
	var confirm_half_size := confirm_display_size * 0.5
	var safe_left := (
		camera_center.x
		- world_half_size.x
		+ BUILDING_ENTRY_CONFIRM_SCREEN_INSETS.x / zoom_value
		+ confirm_half_size.x
	)
	var safe_top := (
		camera_center.y
		- world_half_size.y
		+ BUILDING_ENTRY_CONFIRM_SCREEN_INSETS.y / zoom_value
		+ confirm_half_size.y
	)
	var safe_right := (
		camera_center.x
		+ world_half_size.x
		- BUILDING_ENTRY_CONFIRM_SCREEN_INSETS.z / zoom_value
		- confirm_half_size.x
	)
	var safe_bottom := (
		camera_center.y
		+ world_half_size.y
		- BUILDING_ENTRY_CONFIRM_SCREEN_INSETS.w / zoom_value
		- confirm_half_size.y
	)
	var desired_global := hotspot.to_global(desired_local_anchor)
	if safe_left <= safe_right:
		desired_global.x = clampf(desired_global.x, safe_left, safe_right)
	if safe_top <= safe_bottom:
		desired_global.y = clampf(desired_global.y, safe_top, safe_bottom)
	return hotspot.to_local(desired_global)


func _building_entry_confirm_display_size() -> Vector2:
	if _camera == null:
		return BUILDING_ENTRY_CONFIRM_SIZE
	var minimum_zoom := minf(
		maxf(absf(_camera.zoom.x), 0.001),
		maxf(absf(_camera.zoom.y), 0.001),
	)
	var touch_scale := (
		MOBILE_BUILDING_ENTRY_CONFIRM_TOUCH_SCALE
		if MOBILE_UI_PROFILE.is_mobile_runtime()
		else 1.0
	)
	return (
		BUILDING_ENTRY_CONFIRM_SIZE
		* maxf(1.0, 1.0 / minimum_zoom)
		* touch_scale
	)


func _resident_action_menu_safe_anchor(
	menu_parent: Node2D,
	desired_local_anchor: Vector2,
) -> Vector2:
	if menu_parent == null or _camera == null or not _camera.is_inside_tree():
		return desired_local_anchor
	var zoom_value := maxf(_camera.zoom.x, 0.001)
	var viewport_size := get_viewport_rect().size
	var camera_center := _camera.get_screen_center_position()
	var world_half_size := viewport_size * 0.5 / zoom_value
	var safe_left := (
		camera_center.x
		- world_half_size.x
		+ BUILDING_ENTRY_CONFIRM_SCREEN_INSETS.x / zoom_value
		+ RESIDENT_ACTION_MENU_EXTENTS.x
	)
	var safe_top := (
		camera_center.y
		- world_half_size.y
		+ BUILDING_ENTRY_CONFIRM_SCREEN_INSETS.y / zoom_value
		+ RESIDENT_ACTION_MENU_EXTENTS.y
	)
	var safe_right := (
		camera_center.x
		+ world_half_size.x
		- BUILDING_ENTRY_CONFIRM_SCREEN_INSETS.z / zoom_value
		- RESIDENT_ACTION_MENU_EXTENTS.z
	)
	var safe_bottom := (
		camera_center.y
		+ world_half_size.y
		- BUILDING_ENTRY_CONFIRM_SCREEN_INSETS.w / zoom_value
		+ RESIDENT_ACTION_MENU_EXTENTS.w
	)
	var desired_global := menu_parent.to_global(desired_local_anchor)
	if safe_left <= safe_right:
		desired_global.x = clampf(desired_global.x, safe_left, safe_right)
	if safe_top <= safe_bottom:
		desired_global.y = clampf(desired_global.y, safe_top, safe_bottom)
	return menu_parent.to_local(desired_global)


func _on_announcement_published(_announcement: Dictionary) -> void:
	_announcement_signal_count += 1
	_play_audio_cue("bulletin_stamp")
	_play_major_event_music()
	if _announcement_panel != null:
		_announcement_panel.set_announcements(_world.get_announcements() as Array)


func _on_environment_changed(time: Dictionary, weather: String) -> void:
	if _weather_panel != null:
		_weather_panel.set_current_weather(weather)
	_sync_audio_environment(time, weather)


func _sync_audio_environment(time: Dictionary, weather: String) -> void:
	var audio_controller := get_node_or_null("/root/TownAudioController")
	if audio_controller != null and audio_controller.has_method("sync_environment"):
		audio_controller.sync_environment(time, weather)


func _play_major_event_music() -> void:
	var audio_controller := get_node_or_null("/root/TownAudioController")
	if (
		audio_controller != null
		and audio_controller.has_method("play_major_event_music")
	):
		audio_controller.play_major_event_music()


func _on_world_lifecycle_state_changed(state: Dictionary) -> void:
	_lifecycle_state = state.duplicate(true)
	_update_lifecycle_test_display()
	lifecycle_state_changed.emit(_lifecycle_state.duplicate(true))


func _on_runtime_player_avatar_state_changed(_state: Dictionary) -> void:
	_update_player_conversation_panel()


func _on_runtime_resident_place_changed(
	_resident_name: String,
	_change: Dictionary,
) -> void:
	_sync_environment_space_occupancy()
	_sync_building_resident_markers()


func _on_resident_body_space_changed(
	resident_id: String,
	_previous_space_id: String,
	_space_id: String,
) -> void:
	_sync_building_resident_markers()
	var followed_actor := (
		_resident_presentation.get_actor(_followed_resident)
		as ResidentCharacterBody
	)
	if followed_actor != null and followed_actor.get_resident_id() == resident_id:
		_queue_follow_view_sync()


func _on_runtime_world_restored(_summary: Dictionary) -> void:
	# The roof markers belong to TownRuntime, so restore them from the committed
	# world snapshot in the same signal instead of waiting for a later movement
	# or agent decision event.
	_sync_environment_space_occupancy()
	_sync_building_resident_markers()


func _on_runtime_player_avatar_place_changed(_change: Dictionary) -> void:
	_sync_environment_space_occupancy()
	_update_player_conversation_panel()


func _on_runtime_player_avatar_perception_changed(_change: Dictionary) -> void:
	_update_player_conversation_panel()


func _on_runtime_player_command_result_created(result: Dictionary) -> void:
	_last_player_command_result = result.duplicate(true)
	var command := String(result.get("command", ""))
	if command != "更新位置":
		if result.get("ok") != true:
			_play_audio_cue("ui_error")
		elif command in ["发起对话", "继续对话"]:
			_play_audio_cue("message_send")
	if String(result.get("command", "")) != "更新位置" or result.get("ok") != true:
		_show_player_command_feedback(result)


func _on_runtime_conversation_changed(conversation_id: String, state: Dictionary) -> void:
	var avatar_state := {
		"name": "旅行者",
		"residentId": "",
	}
	if _world != null:
		avatar_state = _world.get_player_avatar_state() as Dictionary
	if _conversation_includes_avatar(state, avatar_state):
		_last_player_conversation = state.duplicate(true)
		var turns := state.get("turns", []) as Array
		var previous_count := int(_conversation_audio_turn_counts.get(conversation_id, 0))
		var cue := _conversation_audio_cue_for_change(
			state,
			previous_count,
			avatar_state,
		)
		if not cue.is_empty():
			_play_audio_cue(cue)
		_conversation_audio_turn_counts[conversation_id] = turns.size()
	_update_player_conversation_panel()


func _conversation_includes_avatar(
	state: Dictionary,
	avatar_state: Dictionary,
) -> bool:
	var avatar_name := String(avatar_state.get("name", "旅行者"))
	var avatar_id := String(
		avatar_state.get("residentId", "")
	).strip_edges()
	var participants := state.get("participants", []) as Array
	return (
		(not avatar_id.is_empty() and participants.has(avatar_id))
		or participants.has(avatar_name)
	)


func _conversation_audio_cue_for_change(
	state: Dictionary,
	previous_count: int,
	avatar_state: Dictionary,
) -> String:
	if not _conversation_includes_avatar(state, avatar_state):
		return ""
	var turns := state.get("turns", []) as Array
	if turns.size() <= previous_count or turns.is_empty():
		return ""
	var newest_turn := turns.back() as Dictionary
	var avatar_id := String(
		avatar_state.get("residentId", "")
	).strip_edges()
	var avatar_name := String(avatar_state.get("name", "旅行者"))
	var speaker_id := String(
		newest_turn.get("speaker_resident_id", "")
	).strip_edges()
	var speaker_name := String(newest_turn.get("speaker", ""))
	var player_spoke := (
		(not avatar_id.is_empty() and speaker_id == avatar_id)
		or speaker_name == avatar_name
	)
	if player_spoke:
		return ""
	return "dialogue_open" if previous_count == 0 else "message_reply"


func _play_audio_cue(cue_id: String) -> void:
	var audio_controller := get_node_or_null("/root/TownAudioController")
	if audio_controller != null and audio_controller.has_method("play_cue"):
		audio_controller.play_cue(cue_id)


func _set_audio_indoor(indoor: bool) -> void:
	var audio_controller := get_node_or_null("/root/TownAudioController")
	if audio_controller != null and audio_controller.has_method("set_indoor"):
		audio_controller.set_indoor(indoor)


func _emit_footstep_effect() -> void:
	var audio_controller := get_node_or_null("/root/TownAudioController")
	if audio_controller != null and audio_controller.has_method("play_footstep"):
		audio_controller.play_footstep()


func _close_announcement_panel() -> void:
	if _announcement_panel != null:
		_announcement_panel.close_panel()


func _close_weather_panel() -> void:
	if _weather_panel != null:
		_weather_panel.close_panel()


func _build_building_observation_hotspots() -> void:
	if (
		_world == null
		or not _world.has_method("get_all_place_details")
		or not _world.has_method("get_place_observation_hotspot")
	):
		return
	var hotspot_index := 0
	for place_value: Variant in _world.get_all_place_details() as Array:
		if not place_value is Dictionary:
			continue
		var place := place_value as Dictionary
		var place_name := String(place.get("name", "")).strip_edges()
		if place_name.is_empty():
			continue
		var hotspot_spec := _world.get_place_observation_hotspot(place_name,) as Dictionary
		if hotspot_spec.is_empty():
			continue
		var hotspot_center := (
			hotspot_spec.get("center", Vector2.ZERO) as Vector2
		)
		var hotspot_size := (
			hotspot_spec.get("size", Vector2.ZERO) as Vector2
		)
		if (
			hotspot_center == Vector2.ZERO
			or hotspot_size.x <= 0.0
			or hotspot_size.y <= 0.0
		):
			continue
		var hotspot := BUILDING_OBSERVATION_HOTSPOT.new() as Area2D
		hotspot_index += 1
		hotspot.name = "ObservePlace%02d" % hotspot_index
		hotspot.configure(place_name,
			hotspot_center,
			hotspot_size,)
		hotspot.connect("activated", _on_building_pressed)
		add_child(hotspot)
		_building_observation_hotspots[place_name] = hotspot
		var marker := BUILDING_RESIDENT_MARKER.new() as Node2D
		if MOBILE_UI_PROFILE.is_mobile_runtime():
			marker.set_touch_scale_multiplier(
				MOBILE_BUILDING_RESIDENT_MARKER_TOUCH_SCALE
			)
		var marker_anchor := Vector2(
			0.0,
			-hotspot_size.y * 0.5 - 46.0,
		)
		if not bool(marker.configure(place_name, marker_anchor)):
			marker.free()
			continue
		marker.connect("resident_activated", _on_building_resident_pressed)
		marker.connect(
			"expanded_changed",
			_on_building_resident_marker_expanded,
		)
		hotspot.add_child(marker)
		_building_resident_markers[place_name] = marker
	_update_building_resident_marker_zoom()
	_sync_building_resident_markers()


func _load_resident_marker_portrait_paths() -> void:
	_resident_portrait_path_by_appearance.clear()
	if not FileAccess.file_exists(RESIDENT_WARDROBE_CATALOG_PATH):
		return
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(RESIDENT_WARDROBE_CATALOG_PATH)
	)
	if not parsed is Dictionary:
		return
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
		_resident_portrait_path_by_appearance[appearance_id] = portrait_path


func _sync_building_resident_markers() -> void:
	if _world == null or _building_resident_markers.is_empty():
		return
	var residents_by_space: Dictionary = {}
	for state_value: Variant in _world.get_all_resident_states() as Array:
		if not state_value is Dictionary:
			continue
		var state := state_value as Dictionary
		var space_id := String(state.get("spaceId", "")).strip_edges()
		if _resident_presentation != null:
			var body := (
				_resident_presentation.get_actor(
					String(state.get("residentId", "")),
				)
				as ResidentCharacterBody
			)
			if body != null:
				space_id = body.get_space_id().strip_edges()
		if (
			space_id.is_empty()
			or space_id == "town_outdoor"
			or not bool(state.get("isPresent", true))
		):
			continue
		var portrait_path := String(
			_resident_portrait_path_by_appearance.get(
				String(state.get("appearance", "")),
				"",
			)
		)
		if portrait_path.is_empty():
			continue
		var entries := residents_by_space.get(space_id, []) as Array
		entries.append({
			"residentId": String(state.get("residentId", "")),
			"name": String(state.get("name", "")),
			"portraitPath": portrait_path,
		})
		residents_by_space[space_id] = entries
	for place_value: Variant in _world.get_all_place_details() as Array:
		if not place_value is Dictionary:
			continue
		var place := place_value as Dictionary
		var place_name := String(place.get("name", ""))
		var marker := _building_resident_markers.get(place_name, null) as Node2D
		if marker == null:
			continue
		marker.set_residents((residents_by_space.get(String(place.get("spaceId", "")), []) as Array),)


func _build_bulletin_board_hotspot() -> void:
	var hotspot := BUILDING_OBSERVATION_HOTSPOT.new() as Area2D
	hotspot.name = "BulletinBoardHotspot"
	hotspot.configure("公告栏",
		BULLETIN_BOARD_HOTSPOT_CENTER,
		BULLETIN_BOARD_HOTSPOT_SIZE,)
	hotspot.connect("activated", _on_bulletin_board_pressed)
	add_child(hotspot)
	_bulletin_hotspot = hotspot


func _on_bulletin_board_pressed(_entity_name: String) -> void:
	if _ui_adapter == null or not _ui_adapter.has_method("open_ui_page"):
		_show_player_command_feedback(
			_local_command_failure(
				"BULLETIN_BOARD_UI_UNAVAILABLE",
				"公告栏暂时不可用。",
				true,
			)
		)
		return
	var routed := _ui_adapter.open_ui_page("announcements",
		{"entryReason": "town_bulletin_board"},) as Dictionary
	if bool(routed.get("ok", false)):
		return
	_show_player_command_feedback(
		_local_command_failure(
			String(
				routed.get(
					"errorCode",
					"BULLETIN_BOARD_UI_UNAVAILABLE",
				)
			),
			"公告栏暂时不可用。",
			bool(routed.get("retryable", true)),
		)
	)


func _set_building_hotspots_available(available: bool) -> void:
	var building_available := (
		available and _avatar_mode == AVATAR_MODE_OBSERVER
	)
	if not building_available:
		_dismiss_building_entry_confirm()
		_collapse_building_resident_marker()
		_clear_focused_building()
	for hotspot_value: Variant in _building_observation_hotspots.values():
		(hotspot_value as Node2D).set_available(building_available)
	for marker_value: Variant in _building_resident_markers.values():
		(marker_value as Node2D).set_available(
			building_available and _avatar_mode == AVATAR_MODE_OBSERVER
		)
	if _bulletin_hotspot != null:
		# Publishing a town-wide announcement is an observer-mode lever.
		# Avatar mode is intentionally limited to physical movement,
		# conversation and photo sharing.
		_bulletin_hotspot.set_available(
			available and _avatar_mode == AVATAR_MODE_OBSERVER
		)


func set_place_focus_route_active(active: bool) -> void:
	if not active:
		_clear_focused_building()


func _clear_focused_building() -> void:
	_focused_building_place_name = ""
	for hotspot_value: Variant in _building_observation_hotspots.values():
		var hotspot := hotspot_value as Node2D
		if hotspot != null and hotspot.has_method("set_focused"):
			hotspot.set_focused(false)


func _portal_id_for_place(place_name: String) -> String:
	if (
		_world == null
		or not _world.has_method("get_place_connection_id")
	):
		return ""
	var connection_id := String(
		_world.get_place_connection_id(place_name)
	)
	if connection_id.is_empty():
		return ""
	for portal_id_value: Variant in CONNECTION_ID_BY_PORTAL_ID:
		if String(CONNECTION_ID_BY_PORTAL_ID[portal_id_value]) == connection_id:
			return String(portal_id_value)
	var portal_id := connection_id.trim_prefix("connection_")
	return portal_id if not _exterior_portal_spec(portal_id).is_empty() else ""


func _place_name_for_portal_id(portal_id: String) -> String:
	if (
		_world == null
		or not _world.has_method("get_place_name_for_connection")
	):
		return ""
	var connection_id := String(
		CONNECTION_ID_BY_PORTAL_ID.get(
			portal_id,
			"connection_%s" % portal_id,
		)
	)
	return String(
		_world.get_place_name_for_connection(connection_id)
	)


func _submit_player_avatar_position(force_stopped: bool) -> Dictionary:
	if _world == null or not enable_player_avatar:
		return {}
	var avatar := _world.get_player_avatar_state() as Dictionary
	var space_id := String(avatar.get("spaceId", ""))
	var position := _avatar_world_position()
	if (
		not force_stopped
		and space_id == _last_confirmed_avatar_space_id
		and position.distance_to(_last_confirmed_avatar_position) < 1.0
	):
		return {"ok": true, "command": "更新位置", "reason": "无需重复提交"}
	var doing := (
		"站在%s" % String(avatar.get("currentPlace", "小镇里"))
		if force_stopped
		else "在%s行走" % String(avatar.get("currentPlace", "小镇里"))
	)
	var result := _world.submit_player_avatar_position(space_id,
		position,
		doing,) as Dictionary
	if result.get("ok") == true:
		# Dictionary.get 的默认值参数会被无条件求值；这里不能把
		# get_player_avatar_state 写成默认值，否则每次提交都多一次深拷贝。
		var confirmed := (
			result["state"] as Dictionary
			if result.get("state") is Dictionary
			else _world.get_player_avatar_state() as Dictionary
		)
		_last_confirmed_avatar_space_id = String(confirmed.get("spaceId", ""))
		_last_confirmed_avatar_position = confirmed.get("position", Vector2.ZERO) as Vector2
	else:
		_sync_avatar_visual_from_world(true)
	return result


func _avatar_world_position() -> Vector2:
	if not _is_inside_interior():
		return _player.position
	var room := _interior_roots.get(_active_interior_id) as Node2D
	return _player.position - room.position if room != null else _player.position


func _sync_avatar_visual_from_world(
	reset_camera := false,
	allow_inactive := false,
	update_camera := true,
) -> void:
	if _world == null or (not enable_player_avatar and not allow_inactive):
		return
	var avatar := _world.get_player_avatar_state() as Dictionary
	var space_id := String(avatar.get("spaceId", ""))
	var position := avatar.get("position", Vector2.ZERO) as Vector2
	if space_id == "town_outdoor":
		if _is_inside_interior():
			return
		_player.position = position
	else:
		if not _is_inside_interior():
			return
		var room := _interior_roots.get(_active_interior_id) as Node2D
		if room == null:
			return
		_player.position = room.position + position
	_clear_player_blocking_normals()
	_last_confirmed_avatar_space_id = space_id
	_last_confirmed_avatar_position = position
	if update_camera:
		_update_camera_target(reset_camera)


func _current_player_conversation() -> Dictionary:
	if _world == null:
		return {}
	var avatar := _world.get_player_avatar_state() as Dictionary
	var snapshot: Variant = avatar.get("conversation")
	if typeof(snapshot) == TYPE_DICTIONARY:
		var conversation_id := String((snapshot as Dictionary).get("conversation_id", ""))
		var conversation := _world.get_conversation(conversation_id) as Dictionary
		if not conversation.is_empty():
			_last_player_conversation = conversation.duplicate(true)
			return conversation
	return _last_player_conversation.duplicate(true)


func _update_player_conversation_panel() -> void:
	if not enable_player_avatar or _world == null or _player_conversation_panel == null:
		return
	var connected: Array = []
	if _agent_gateway != null:
		connected = _agent_gateway.get_connected_resident_names() as Array[String]
	_player_conversation_panel.update_state(_world.get_player_avatar_state() as Dictionary,
		_current_player_conversation(),
		connected,)


func _show_player_command_feedback(result: Dictionary) -> void:
	_last_player_command_result = result.duplicate(true)
	if _player_conversation_panel != null:
		_player_conversation_panel.show_feedback(result)


func _local_player_command_failure(
	command: String,
	reason: String,
	error_code := "CONVERSATION_COMMAND_REJECTED",
) -> Dictionary:
	var result := _local_command_failure(error_code, reason)
	result["command"] = command
	result["reason"] = reason
	_show_player_command_feedback(result)
	return result


func _local_command_failure(error_code: String, reason: String, retryable := false) -> Dictionary:
	return {
		"ok": false,
		"errors": [reason],
		"reason": reason,
		"errorCode": error_code,
		"retryable": retryable,
		"worldRevision": (
			int(_world.get_world_revision())
			if _world != null and _world.has_method("get_world_revision")
			else 0
		),
	}


func _is_text_input_focused() -> bool:
	return _is_text_input_control(get_viewport().gui_get_focus_owner())


func _is_text_input_control(control: Control) -> bool:
	return control is LineEdit or control is TextEdit


func _release_text_input_focus() -> void:
	if _player_conversation_panel != null and _player_conversation_panel.has_method("release_text_focus"):
		_player_conversation_panel.release_text_focus()
	var focus_owner := get_viewport().gui_get_focus_owner()
	if _is_text_input_control(focus_owner):
		focus_owner.release_focus()


func _stop_avatar_visual_motion(reset_movement_tracking := true) -> void:
	_player.velocity = Vector2.ZERO
	if _player_sprite != null:
		_player_sprite.set_motion(Vector2.ZERO, 0.0)
	if reset_movement_tracking:
		_avatar_was_moving = false


func _set_pause_reason(reason: String, paused: bool) -> Dictionary:
	if _world == null:
		return _local_command_failure("WORLD_NOT_RUNNING", "世界尚未运行")
	if paused and enable_player_avatar and _avatar_was_moving:
		_submit_player_avatar_position(true)
		_stop_avatar_visual_motion()
	var result := (
		_world.pause(reason)
		if paused
		else _world.resume(reason)
	) as Dictionary
	_lifecycle_state = _world.get_lifecycle_state() as Dictionary
	_update_lifecycle_test_display()
	return result


func _update_lifecycle_test_display() -> void:
	if not enable_test_ui or _manual_pause_button == null:
		return
	var reasons := _lifecycle_state.get("pauseReasons", []) as Array
	_lifecycle_label.text = (
		"世界：暂停（%s）" % "、".join(reasons)
		if bool(_lifecycle_state.get("paused", false))
		else "世界：运行中"
	)
	_manual_pause_button.text = "继续世界（P）" if reasons.has("manual") else "暂停世界（P）"


func _on_portal_black_covering(entering_interior: bool) -> Dictionary:
	# 黑屏遮盖阶段预热：先把表现层切到目标空间并强制对齐权威位置，
	# 玩家淡入后看到的就是正常运行中的画面，而不是先看见再吸附。
	if _resident_presentation == null or _world == null:
		return {
			"ok": false,
			"code": "PRESENTATION_SPACE_SYNC_UNAVAILABLE",
		}
	if (
		_active_follow_view_generation >= 0
		and _active_follow_view_generation != _follow_view_generation
	):
		_restore_follow_view_presentation()
		return {
			"ok": false,
			"code": "FOLLOW_VIEW_TRANSITION_STALE",
		}
	return SPACE_VIEW_SYNC.reconcile(
		self,
		_resident_presentation,
		"portal_enter" if entering_interior else "portal_exit",
	) as Dictionary


func _enter_interior(body: Node2D, portal_id: String) -> void:
	if not enable_player_avatar:
		await super._enter_interior(body, portal_id)
		return
	if (
		body != _player
		or _world == null
		or _is_inside_interior()
		or _portal_transition_active
		or _avatar_place_change_active
		or portal_id == _blocked_exterior_reentry_portal_id
	):
		return
	var place_name := _place_name_for_portal_id(portal_id)
	if place_name.is_empty():
		return
	_avatar_place_change_active = true
	var avatar_before_entry := _world.get_player_avatar_state() as Dictionary
	var threshold_space_id := String(
		avatar_before_entry.get("spaceId", ""),
	)
	var threshold_position := _player.position
	var exterior_anchor := _world.get_place_exterior_anchor(place_name,) as Dictionary
	# The visible doorway overlaps authored building collision, so its sprite
	# trigger coordinate is not itself a legal World position. Physical overlap
	# proves that the avatar reached the door; record the matching formal
	# exterior connection point before crossing spaces.
	if (
		not exterior_anchor.is_empty()
		and String(exterior_anchor.get("spaceId", ""))
		== threshold_space_id
	):
		threshold_position = exterior_anchor.get(
			"position",
			threshold_position,
		) as Vector2
	var threshold_result := _world.submit_player_avatar_position(threshold_space_id,
		threshold_position,
		"走到%s门外" % place_name,) as Dictionary
	if threshold_result.get("ok") != true:
		_show_player_command_feedback(threshold_result)
		_avatar_place_change_active = false
		_sync_avatar_visual_from_world(true)
		return
	_avatar_outdoor_place = String((threshold_result.get("state", {}) as Dictionary).get("currentPlace", ""))
	var result := _world.change_player_avatar_place(place_name) as Dictionary
	_show_player_command_feedback(result)
	if result.get("ok") != true:
		_avatar_place_change_active = false
		_sync_avatar_visual_from_world(true)
		return
	var target_interior_id := String(
		_exterior_portal_spec(portal_id).get("interior_id", ""),
	)
	var target_room := _interior_roots.get(target_interior_id) as Node2D
	var presentation_result := (
		_resident_presentation.set_observed_interior(
			place_name,
			target_room.position,
		) as Dictionary
		if target_room != null
		else {
			"ok": false,
			"code": "PRESENTATION_INTERIOR_ROOM_UNAVAILABLE",
		}
	)
	if presentation_result.get("ok") != true:
		var rollback := _world.return_player_avatar_outdoors(
			_avatar_outdoor_place,
			threshold_position,
		) as Dictionary
		_show_player_command_feedback(
			presentation_result if rollback.get("ok") == true else rollback,
		)
		_avatar_place_change_active = false
		_sync_avatar_visual_from_world(true)
		return
	await super._enter_interior(body, portal_id)
	if not is_inside_tree():
		return
	if _is_inside_interior():
		_set_audio_indoor(true)
		_play_audio_cue("door_enter")
		_observed_place_name = place_name
		_environment_renderer.set_outdoor_visible(false)
		_set_building_hotspots_available(false)
		_sync_avatar_visual_from_world(true)
	_avatar_place_change_active = false
	observed_place_changed.emit({
		"ok": _is_inside_interior(),
		"accepted": _is_inside_interior(),
		"pending": false,
		"transitionKind": "avatar_enter_indoor",
		"placeName": place_name,
		"viewMode": "interior" if _is_inside_interior() else "town",
		"errorCode": "" if _is_inside_interior() else "AVATAR_INTERIOR_ENTRY_INCOMPLETE",
		"retryable": not _is_inside_interior(),
	})


func _exit_interior(body: Node2D, interior_id: String) -> void:
	if not enable_player_avatar:
		await super._exit_interior(body, interior_id)
		return
	if (
		body != _player
		or _world == null
		or not _is_inside_interior()
		or interior_id != _active_interior_id
		or _portal_transition_active
		or _avatar_place_change_active
	):
		return
	_avatar_place_change_active = true
	var previous_place_name := _observed_place_name
	var avatar_before_exit := _world.get_player_avatar_state() as Dictionary
	var portal_spec := _exterior_portal_spec(_active_exterior_portal_id)
	var safe_return_position := portal_spec.get(
		"return",
		Vector2(INF, INF),
	) as Vector2
	var result := _world.return_player_avatar_outdoors(_avatar_outdoor_place,
		safe_return_position,) as Dictionary
	_show_player_command_feedback(result)
	if result.get("ok") != true:
		_avatar_place_change_active = false
		_sync_avatar_visual_from_world(true)
		return
	var presentation_result := (
		_resident_presentation.clear_observed_interior() as Dictionary
	)
	if presentation_result.get("ok") != true:
		var rollback := (
			_world.change_player_avatar_place(previous_place_name) as Dictionary
		)
		if rollback.get("ok") == true:
			var restored_avatar := (
				rollback.get("state", {}) as Dictionary
				if rollback.get("state") is Dictionary
				else _world.get_player_avatar_state() as Dictionary
			)
			var restored_position := avatar_before_exit.get(
				"position",
				Vector2.ZERO,
			) as Vector2
			var restored_space_id := String(
				restored_avatar.get("spaceId", ""),
			)
			rollback = _world.submit_player_avatar_position(
				restored_space_id,
				restored_position,
				String(avatar_before_exit.get("doing", "")),
			) as Dictionary
		_show_player_command_feedback(
			presentation_result if rollback.get("ok") == true else rollback,
		)
		_avatar_place_change_active = false
		_sync_avatar_visual_from_world(true)
		return
	await super._exit_interior(body, interior_id)
	if not is_inside_tree():
		return
	_set_audio_indoor(false)
	_play_audio_cue("door_exit")
	_observed_place_name = ""
	_environment_renderer.set_outdoor_visible(true)
	_set_building_hotspots_available(true)
	_sync_avatar_visual_from_world(true)
	_avatar_place_change_active = false
	observed_place_changed.emit({
		"ok": not _is_inside_interior(),
		"accepted": not _is_inside_interior(),
		"pending": false,
		"transitionKind": "avatar_return_outdoor",
		"placeName": previous_place_name,
		"viewMode": "town" if not _is_inside_interior() else "interior",
		"errorCode": "" if not _is_inside_interior() else "AVATAR_OUTDOOR_RETURN_INCOMPLETE",
		"retryable": _is_inside_interior(),
	})


func _show_observed_interior(place_name: String, portal_id: String) -> bool:
	_view_sync_active = true
	if _is_inside_interior() and _active_exterior_portal_id != portal_id:
		# 不在退出前切空间：_exit_interior 有一系列守卫可能提前返回，
		# 提前切走会导致"房间仍可见、表现层已切室外"的永久冻结失配。
		# 退出成功的路径内部会自行 clear_observed_interior。
		await _exit_interior(_player, _active_interior_id)
	if not _is_inside_interior():
		# This guard only prevents the avatar's automatic doorway re-entry after
		# a physical exit. Observer mode enters from an explicit building click,
		# so a previously exited building must remain selectable immediately.
		_blocked_exterior_reentry_portal_id = ""
		var portal_spec := _exterior_portal_spec(portal_id)
		var target_interior_id := String(
			portal_spec.get("interior_id", ""),
		)
		var target_room := (
			_interior_roots.get(target_interior_id) as Node2D
		)
		if target_room == null:
			_view_sync_active = false
			return false
		var prepared := _resident_presentation.set_observed_interior(
			place_name,
			target_room.position,
		) as Dictionary
		if prepared.get("ok") != true:
			_view_sync_active = false
			return false
		await _enter_interior(_player, portal_id)
	if _is_inside_interior() and _active_exterior_portal_id == portal_id:
		# 只有确实处于目标房间才设置观察空间；退出/进入失败时保持原状，
		# 交给 SPACE_VIEW_SYNC 周期兜底修正到实际可见空间。
		_observed_place_name = place_name
		_environment_renderer.set_outdoor_visible(false)
		_set_building_hotspots_available(false)
	_view_sync_active = false
	return _is_inside_interior() and _active_exterior_portal_id == portal_id


func _show_town_overview() -> bool:
	_view_sync_active = true
	if _is_inside_interior():
		# 先完成退出再切空间：提前切走一旦遇到退出守卫提前返回，
		# 室内居民会被永久冻结在可见画面中。退出成功路径内部会自行
		# clear_observed_interior 并复位 _observed_place_name。
		var prepared := (
			_resident_presentation.clear_observed_interior()
			as Dictionary
		)
		if prepared.get("ok") != true:
			_view_sync_active = false
			return false
		await _exit_interior(_player, _active_interior_id)
	else:
		var prepared := (
			_resident_presentation.clear_observed_interior()
			as Dictionary
		)
		if prepared.get("ok") != true:
			_view_sync_active = false
			return false
		_observed_place_name = ""
	if not enable_player_avatar:
		_blocked_exterior_reentry_portal_id = ""
	if not _is_inside_interior():
		_environment_renderer.set_outdoor_visible(true)
		_set_building_hotspots_available(true)
	_view_sync_active = false
	return not _is_inside_interior()


func _queue_follow_view_sync() -> void:
	if _view_sync_requested or _view_sync_active or _world == null or _followed_resident.is_empty():
		return
	_view_sync_requested = true
	call_deferred("_sync_followed_resident_view")


func _sync_followed_resident_view() -> void:
	_view_sync_requested = false
	if _view_sync_active or _world == null or _followed_resident.is_empty():
		return
	var state := _world.get_resident_state(_followed_resident) as Dictionary
	if state.is_empty() or not bool(state.get("isPresent", true)):
		_set_followed_resident("")
		return
	var actor := (
		_resident_presentation.get_actor(_followed_resident)
		as ResidentCharacterBody
	)
	if actor == null:
		_set_followed_resident("")
		return
	var actor_space_id := actor.get_space_id()
	var follow_generation := _follow_view_generation
	var followed_resident_id := actor.get_resident_id()
	if actor_space_id == "town_outdoor":
		if _is_inside_interior():
			var returned := await _run_follow_town_overview_transition(
				follow_generation,
			)
			if not _finish_follow_view_attempt(
				follow_generation,
				followed_resident_id,
				actor_space_id,
			):
				return
			if not returned:
				_set_followed_resident("")
				return
		_update_follow_camera(true)
		return
	var place_name := _place_name_for_space_id(actor_space_id)
	var portal_id := _portal_id_for_place(place_name)
	if portal_id.is_empty():
		_set_followed_resident("")
		return
	if not _is_inside_interior() or _observed_place_name != place_name:
		_capture_follow_view_rollback_presentation()
		_active_follow_view_generation = follow_generation
		var entered := await _show_observed_interior(place_name, portal_id)
		if _active_follow_view_generation == follow_generation:
			_active_follow_view_generation = -1
		_clear_follow_view_rollback_presentation()
		if not _finish_follow_view_attempt(
			follow_generation,
			followed_resident_id,
			actor_space_id,
		):
			return
		if not entered:
			_set_followed_resident("")
			return
	_update_follow_camera(true)


func _run_follow_town_overview_transition(generation: int) -> bool:
	_capture_follow_view_rollback_presentation()
	_active_follow_view_generation = generation
	var returned := await _show_town_overview()
	if _active_follow_view_generation == generation:
		_active_follow_view_generation = -1
	_clear_follow_view_rollback_presentation()
	return returned


func _finish_follow_view_attempt(
	generation: int,
	resident_id: String,
	space_id: String,
) -> bool:
	var actor := (
		_resident_presentation.get_actor(_followed_resident)
		as ResidentCharacterBody
	)
	var current := (
		generation == _follow_view_generation
		and not _followed_resident.is_empty()
		and actor != null
		and actor.get_resident_id() == resident_id
		and actor.get_space_id() == space_id
	)
	if current:
		return true
	if not _followed_resident.is_empty():
		_queue_follow_view_sync()
	return false


func _capture_follow_view_rollback_presentation() -> void:
	_follow_view_rollback_space_id = String(
		_resident_presentation.get_active_space_id(),
	)
	_follow_view_rollback_place_name = _observed_place_name
	_follow_view_rollback_origin = Vector2.ZERO
	if _is_inside_interior():
		var room := _interior_roots.get(_active_interior_id) as Node2D
		if room != null:
			_follow_view_rollback_origin = room.position


func _restore_follow_view_presentation() -> Dictionary:
	if _follow_view_rollback_space_id == "town_outdoor":
		return (
			_resident_presentation.clear_observed_interior() as Dictionary
		)
	if not _follow_view_rollback_place_name.is_empty():
		return _resident_presentation.set_observed_interior(
			_follow_view_rollback_place_name,
			_follow_view_rollback_origin,
		) as Dictionary
	return {
		"ok": false,
		"code": "FOLLOW_VIEW_ROLLBACK_SPACE_UNAVAILABLE",
	}


func _clear_follow_view_rollback_presentation() -> void:
	_follow_view_rollback_space_id = ""
	_follow_view_rollback_place_name = ""
	_follow_view_rollback_origin = Vector2.ZERO


func _follow_view_matches_space(space_id: String) -> bool:
	if space_id.is_empty() or _resident_presentation == null:
		return false
	if String(_resident_presentation.get_active_space_id()) != space_id:
		return false
	if space_id == "town_outdoor":
		return not _is_inside_interior()
	if not _is_inside_interior():
		return false
	return _place_name_for_space_id(space_id) == _observed_place_name


func _place_name_for_space_id(space_id: String) -> String:
	if (
		space_id.is_empty()
		or _world == null
		or not _world.has_method("get_all_place_details")
	):
		return ""
	for place_value: Variant in _world.get_all_place_details() as Array:
		if not place_value is Dictionary:
			continue
		var place := place_value as Dictionary
		if String(place.get("spaceId", "")) == space_id:
			return String(place.get("name", ""))
	return ""


func _update_runtime_hud() -> void:
	if not enable_test_ui:
		return
	if not _startup_error.is_empty():
		_resident_label.text = _startup_error
		return
	var time := _world.get_time() as Dictionary
	_environment_label.text = "第 %d 天 %s · %s · %s" % [time.get("day", 1), time.get("clock", "00:00"), time.get("period", ""), _world.get_weather()]
	var lines: Array[String] = []
	if enable_player_avatar:
		var avatar := _world.get_player_avatar_state() as Dictionary
		var gateway_errors := _agent_gateway.get_errors() as Array
		lines.append("旅行者｜%s｜附近：%s" % [
			avatar.get("currentPlace", ""),
			"、".join(avatar.get("nearby", [])) if not (avatar.get("nearby", []) as Array).is_empty() else "无",
		])
		lines.append("DeepSeek Agent：%d 个已连接｜错误：%d" % [connected_residents.size(), gateway_errors.size()])
	for resident_name in connected_residents:
		var state := _world.get_resident_state(resident_name) as Dictionary
		var marker := "▶" if resident_name == _followed_resident else " "
		lines.append("%s %s｜%s｜%s" % [marker, resident_name, state.get("currentPlace", ""), state.get("doing", "")])
	_resident_label.text = "\n".join(lines)
	_update_lifecycle_test_display()


func _fail_start(message: String) -> void:
	_startup_error = message
	_resident_label.text = message
	push_error(message)
	_startup_completion_emitted = true
	startup_completed.emit(_local_command_failure(
		"TOWN_RUNTIME_START_FAILED",
		message,
	))


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}
