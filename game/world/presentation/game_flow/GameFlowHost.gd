extends Node


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const STARTUP_SCENE_PATH := "res://ui/startup/StartupScreen.tscn"
const LOAD_GAME_SCENE_PATH := "res://ui/startup/StartupLoadGameScreen.tscn"
const WORLD_INTRO_SCENE_PATH := "res://ui/world_intro/WorldIntroScreen.tscn"
const RESIDENT_SELECTION_SCENE_PATH := "res://ui/resident_selection/ResidentSelectionScreen.tscn"
const TOWN_RUNTIME_SCENE_PATH := (
	"res://world/presentation/town_runtime/TownRuntime.tscn"
)
const AVATAR_MODE_HUD_SCENE_PATH := "res://ui/avatar_mode/runtime/AvatarModeHud.tscn"
const PAUSE_MENU_HOST_SCENE_PATH := "res://ui/pause_menu/PauseMenuNavigationHost.tscn"
const TOWN_UI_RUNTIME_HOST_SCRIPT_PATH := (
	"res://world/presentation/ui/TownUiRuntimeHost.gd"
)
const SESSION_UI_SERVICE := preload(
	"res://world/presentation/session/TownSessionUiService.gd"
)
const SESSION_SAVE_STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const AGENT_SAVE_STORE := preload(
	"res://agent/lifecycle/AgentSaveStore.gd"
)
const SESSION_SAVE_MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const STARTUP_SAVE_CATALOG := preload(
	"res://world/presentation/session/TownStartupSaveCatalog.gd"
)
const AUDIO_DISPLAY_SETTINGS_SERVICE := preload(
	"res://world/presentation/ui/TownAudioDisplaySettingsService.gd"
)
const PROVIDER_SETTINGS_SERVICE := preload(
	"res://world/presentation/ui/TownProviderSettingsService.gd"
)
const UI_PAGE_PROJECTION_SERVICE := preload(
	"res://world/presentation/ui/TownUiPageProjectionService.gd"
)
const TOWN_UI_ADAPTER := preload(
	"res://world/presentation/ui/TownUiAdapter.gd"
)
const UI_VIEW_MODEL := preload(
	"res://ui/common/AiTownUiViewModel.gd"
)
const UI_NODE_RETIREMENT := preload(
	"res://ui/common/AiTownUiNodeRetirement.gd"
)
const PROVIDER_SETTINGS_SCENE_PATH := (
	"res://ui/provider_settings/ProviderSettingsScreen.tscn"
)
const NEW_GAME_OVERWRITE_SCENE_PATH := (
	"res://ui/new_game_overwrite/NewGameOverwriteScreen.tscn"
)
const AUDIO_DISPLAY_SETTINGS_SCENE_PATH := (
	"res://ui/settings/AudioDisplaySettingsScreen.tscn"
)
const CUSTOM_RESIDENT_CREATOR_SCENE_PATH := (
	"res://ui/custom_resident_creator/CustomResidentCreatorScreen.tscn"
)
const CUSTOM_RESIDENT_CREATOR_SERVICE_PATH := (
	"res://world/presentation/session/TownCustomResidentCreatorService.gd"
)
const CUSTOM_RESIDENT_CANDIDATE_POOL := preload(
	"res://world/presentation/session/TownCustomResidentCandidatePool.gd"
)
const CUSTOM_RESIDENT_LIBRARY := preload(
	"res://world/presentation/session/TownCustomResidentLibrary.gd"
)
const RESIDENT_MODEL_ASSIGNMENT_SCENE_PATH := (
	"res://ui/resident_model_assignment/ResidentModelAssignmentScreen.tscn"
)
const RESIDENT_MODEL_ASSIGNMENT_SERVICE := preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentService.gd"
)
const BOOTSTRAP := preload("res://world/presentation/session/TownSessionBootstrap.gd")
const TOWN_ENTRY_LOADING_OVERLAY := preload(
	"res://ui/startup/TownEntryLoadingOverlay.gd"
)
const REPLACEMENT_ARRIVAL_PANEL := preload(
	"res://ui/resident_admission/ReplacementResidentArrivalPanel.gd"
)
const REPLACEMENT_CANDIDATE_POOL := preload(
	"res://world/presentation/session/TownReplacementResidentCandidatePool.gd"
)
const RESIDENT_REPLACEMENT := preload(
	"res://world/runtime/lifecycle/TownResidentReplacementAdmission.gd"
)
const AGENT_SOUL_PROFILE := preload("res://agent/soul/AgentSoulProfile.gd")
const PROVIDER_SERVICE := preload("res://world/integration/TownAgentProviderService.gd")
const GATEWAY := preload("res://world/integration/TownWorldAgentGateway.gd")
const FORMAL_SLOT_ARCHIVER := preload(
	"res://world/integration/TownFormalSlotArchiveService.gd"
)
const FORMAL_OVERWRITE_COMPENSATOR := preload(
	"res://world/presentation/game_flow/GameFlowFormalOverwriteCompensator.gd"
)
const CONFIRMATION_PAGE_BUILDER := preload(
	"res://world/presentation/game_flow/GameFlowConfirmationPageBuilder.gd"
)
const INTERNAL_CATALOG_PATH := (
	"res://world/presentation/session/TownInternalPlaytestCatalog.gd"
)
const FORMAL_CATALOG := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)
const WORLD_DATA_PATH := "res://world/data/town/town_world.json"
const FORMAL_SLOT_ID := "town-main"
const FORMAL_SLOT_DEFINITIONS := [
	{"slotId": "town-main", "displayName": "小镇 1"},
	{"slotId": "town-2", "displayName": "小镇 2"},
	{"slotId": "town-3", "displayName": "小镇 3"},
]
const INTERNAL_PLAYTEST_ENV := "AI_TOWN_INTERNAL_PLAYTEST"
const INTERNAL_PROVIDER_ENV := "AI_TOWN_PLAYTEST_PROVIDER"
const INTERNAL_MODEL_ENV := "AI_TOWN_PLAYTEST_MODEL"
const INTERNAL_WINDOW_TITLE := "我的ai小镇 · 开发内测"
const FORMAL_WINDOW_TITLE := "我的ai小镇"
const FORMAL_UI_CANVAS_LAYER := 100
const FORMAL_RUNTIME_AUDIT_ENV := "AI_TOWN_FORMAL_RUNTIME_AUDIT_PATH"
const DAILY_AUTO_SAVE_REASON := "daily_auto_save"
const DAILY_AUTO_SAVE_RETRY_INTERVAL_MSEC := 5000
const DAILY_AUTO_SAVE_ERROR_HISTORY_LIMIT := 32
const REPLACEMENT_AGENT_ATTRIBUTE_FIELDS: Array[String] = [
	"name",
	"gender",
	"age",
	"appearance",
	"desire",
	"personality",
	"speech",
	"interests",
	"customInterests",
]
const CUSTOM_RESIDENT_LIBRARY_PATH_ENV := "AI_TOWN_CUSTOM_RESIDENT_LIBRARY_PATH"
const CUSTOM_RESIDENT_CREATOR_BLOCKED_REASON := (
	"CUSTOM_RESIDENT_CREATOR_MOUNTING_NOT_AUTHORIZED"
)
const CUSTOM_RESIDENT_CREATOR_MOUNTING_AUTHORIZED := true
const WORLD_INTRO_PAGES := [
	{
		"pageId": "town_lives",
		"kicker": "欢迎来到这里",
		"title": "这座小镇会自己生活",
		"body": "居民有自己的性格、愿望和日程。即使你只是安静地看着，他们也会出门、工作、相遇，并临时决定下一步要做什么。",
		"visualBeat": "wide_town",
	},
	{
		"pageId": "experiences_remain",
		"kicker": "每一天都有回声",
		"title": "经历会留下痕迹",
		"body": "交谈、天气和共同经历会成为记忆，关系也会在真实发生的事情里慢慢变化。今天的一句话，可能在往后的日子里被重新提起。",
		"visualBeat": "lived_moments",
	},
	{
		"pageId": "player_ripples",
		"kicker": "轻轻拨动世界",
		"title": "你的介入会产生涟漪",
		"body": "你可以选择居民、改变天气、发布公告；想和居民直接交谈时，就化身走进小镇。你的每次介入都会成为这里真实发生的事。",
		"visualBeat": "town_reveal",
	},
]
var _bound_scene_id := 0
var _world_intro: Control
var _world_intro_vm: Dictionary = {}
var _world_intro_navigation_pending := false
var _new_game_route_context: Dictionary = {}
var _resident_selection: Control
var _resident_selection_vm: Dictionary = {}
var _bootstrap: BOOTSTRAP
var _provider_service: RefCounted
var _gateway: Node
var _pending_runtime: Node
var _town_runtime: Node
var _town_runtime_scene: PackedScene
var _town_ui_canvas_layer: CanvasLayer
var _avatar_hud: Control
var _pause_host: Control
var _town_ui_host: Control
var _session_ui_service: RefCounted
var _audio_display_settings_service: AUDIO_DISPLAY_SETTINGS_SERVICE
var _provider_settings_ui_service: PROVIDER_SETTINGS_SERVICE
var _ui_page_projection_service: UI_PAGE_PROJECTION_SERVICE
var _startup_ui_adapter: Node
var _town_ui_adapter: Node
var _startup_provider_service: RefCounted
var _startup_provider_settings_service: RefCounted
var _startup_save_store: RefCounted
var _startup_save_catalog: RefCounted
var _delete_archive_service_override: RefCounted
var _formal_archive_service_override: RefCounted
var _startup_settings_page: Control
var _startup_load_game_page: Control
var _startup_load_game_mode := ""
var _pending_load_game_new_game_payload: Dictionary = {}
var _startup_overwrite_page: Control
var _custom_resident_creator_page: Control
var _custom_resident_creator_service: RefCounted
var _custom_resident_candidate_pool: CUSTOM_RESIDENT_CANDIDATE_POOL
var _custom_resident_library: CUSTOM_RESIDENT_LIBRARY
var _resident_model_assignment_page: Control
var _resident_model_assignment_service: RESIDENT_MODEL_ASSIGNMENT_SERVICE
var _resident_model_assignment_committing := false
var _resident_model_assignment_preserved_draft: Dictionary = {}
var _town_entry_loading_overlay: CanvasLayer
var _town_entry_loading_generation := -1
var _town_entry_loading_route_kind := ""
var _town_entry_loading_owner := ""
var _town_entry_loading_context: Dictionary = {}
var _pending_new_game_payload: Dictionary = {}
var _pending_new_game_discovery: Dictionary = {}
var _pending_save_handling_mode := ""
var _pending_save_handling_origin := ""
var _pending_continue_notice: Dictionary = {}
var _overwrite_compensator := FORMAL_OVERWRITE_COMPENSATOR.new()
var _pending_formal_overwrite_archive: Dictionary:
	get:
		return _overwrite_compensator.pending_archive
	set(value):
		_overwrite_compensator.pending_archive = value
var _active_session_config: Dictionary = {}
var _town_ui_route := &"town"
var _pause_open := false
var _pause_focus_return_path := NodePath()
var _pause_return_deferred := false
var _in_session_load_pending := false
var _process_quit_scheduled := false
var _quit_departure_pending := false
var _quit_departure_id := ""
var _quit_execute_process := true
var _flow_generation := 1
var _startup_view_model_revision := 0
var _last_result: Dictionary = {}
var _formal_runtime_audit_written := false
var _formal_runtime_audit_last_write_msec := -1000
var _formal_runtime_audit_requested := false
var _daily_auto_save_day := -1
var _daily_auto_save_last_attempt_day := -1
var _daily_auto_save_last_attempt_msec := -100000
var _daily_auto_save_attempts := 0
var _daily_auto_save_successes := 0
var _replacement_generation_pending := false
var _replacement_last_checked_minute := -1
var _pending_replacement_candidate: Dictionary = {}
var _replacement_arrival_panel: ReplacementResidentArrivalPanel
var _replacement_editor_page: CustomResidentCreatorScreen
var _replacement_editor_service: TownCustomResidentCreatorService
var _replacement_candidate_pool: RefCounted
var _replacement_assignment_active := false
var _replacement_world_admitted := false
var _replacement_admission_committed := false
var _daily_auto_save_last_revision := 0
var _daily_auto_save_failures: Array[Dictionary] = []
var _daily_auto_save_inflight := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	set_process(true)
	set_process_input(true)
	print("AI_TOWN_RENDERER method=%s driver=%s" % [
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(),
	])
	_overwrite_compensator.configure(_record_compensation_last_result)
	_play_cover_music()
	_audio_display_settings_service = AUDIO_DISPLAY_SETTINGS_SERVICE.new()
	_audio_display_settings_service.name = "TownAudioDisplaySettingsService"
	add_child(_audio_display_settings_service)
	_initialize_startup_settings_services()
	_apply_window_mode_marker()
	_formal_runtime_audit_requested = not OS.get_environment(
		FORMAL_RUNTIME_AUDIT_ENV
	).strip_edges().is_empty()
	_bind_current_scene.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree():
		request_quit_game(true)


func _process(_delta: float) -> void:
	_bind_current_scene()
	_poll_resident_replacement()
	if _formal_runtime_audit_requested:
		_write_formal_runtime_audit_if_requested.call_deferred()


func _ensure_town_entry_loading_overlay() -> void:
	if is_instance_valid(_town_entry_loading_overlay):
		return
	_town_entry_loading_overlay = TOWN_ENTRY_LOADING_OVERLAY.new() as CanvasLayer
	_town_entry_loading_overlay.name = "TownEntryLoadingOverlay"
	add_child(_town_entry_loading_overlay)


func _poll_resident_replacement() -> void:
	if (
		_replacement_generation_pending
		or not _pending_replacement_candidate.is_empty()
		or not is_instance_valid(_town_runtime)
		or _provider_service == null
		or _gateway == null
		or _active_session_config.is_empty()
	):
		return
	var world := _town_runtime.get_world_runtime() as TownWorldRuntime
	if (
		world == null
		or not world.has_method("get_public_death_events")
	):
		return
	var current_minute := RESIDENT_REPLACEMENT.world_absolute_minute(world)
	if current_minute < 0 or current_minute == _replacement_last_checked_minute:
		return
	_replacement_last_checked_minute = current_minute
	if RESIDENT_REPLACEMENT.living_resident_count(world) >= 15:
		return
	var death_events := world.get_public_death_events() as Array
	for death_event_value: Variant in death_events:
		if not death_event_value is Dictionary:
			continue
		var death_event := death_event_value as Dictionary
		if current_minute >= _replacement_due_minute(death_event):
			_begin_replacement_persona_generation(death_event)
			return


func _replacement_due_minute(death_event: Dictionary) -> int:
	var time := death_event.get("time", {}) as Dictionary
	var day := maxi(1, int(time.get("day", 1)))
	var clock_parts := String(time.get("clock", "00:00")).split(":")
	var hour := int(clock_parts[0]) if clock_parts.size() > 0 else 0
	var minute := int(clock_parts[1]) if clock_parts.size() > 1 else 0
	var death_minute := (day - 1) * 1440 + hour * 60 + minute
	var event_id := String(death_event.get("event_id", "resident-death"))
	return death_minute + 1 + posmod(event_id.hash(), 1440)


func _begin_replacement_persona_generation(death_event: Dictionary) -> void:
	var bindings := _active_session_config.get("residentBindings", []) as Array
	if bindings.is_empty():
		return
	var source_binding := (bindings[0] as Dictionary).duplicate(true)
	var deceased_id := String(
		death_event.get("deceased_resident_id", "")
	).strip_edges()
	for binding_value: Variant in bindings:
		if (
			binding_value is Dictionary
			and String((binding_value as Dictionary).get("residentId", ""))
			== deceased_id
		):
			source_binding = (binding_value as Dictionary).duplicate(true)
			break
	var provider_result := _provider_service.create_provider_for_resident(
		source_binding,
	) as Dictionary
	if not bool(provider_result.get("ok", false)):
		_present_generated_replacement(
			_build_replacement_candidate(death_event, source_binding, {}),
		)
		return
	var provider: Object = provider_result.get("provider")
	if provider == null or not provider.has_method("request_json"):
		_present_generated_replacement(
			_build_replacement_candidate(death_event, source_binding, {}),
		)
		return
	_replacement_generation_pending = true
	provider.request_json({
		"request_kind": "replacement_resident_persona",
		"messages": [{
			"role": "system",
			"content": (
				"为一座现代中文小镇生成一名新居民。只返回严格 JSON，字段必须为 "
				+ "name、gender、age、desire、personality、speech。gender 只能是男或女，"
				+ "age 为 18 到 80 的整数，其余字段使用简洁自然的中文，不要解释。"
			),
		}, {
			"role": "user",
			"content": "随机生成一名与现有居民不同、能够长期生活的新居民。",
		}],
		"max_tokens": 360,
	}, _on_replacement_persona_generated.bind(
		death_event.duplicate(true),
		source_binding.duplicate(true),
	))


func _on_replacement_persona_generated(
	result: Dictionary,
	death_event: Dictionary,
	source_binding: Dictionary,
) -> void:
	_replacement_generation_pending = false
	var persona: Dictionary = {}
	if bool(result.get("ok", false)) and result.get("json", {}) is Dictionary:
		persona = (result.get("json", {}) as Dictionary).duplicate(true)
	_present_generated_replacement(
		_build_replacement_candidate(death_event, source_binding, persona),
	)


func _build_replacement_candidate(
	death_event: Dictionary,
	source_binding: Dictionary,
	persona: Dictionary,
) -> Dictionary:
	var opening := _active_session_config.get("openingConfig", {}) as Dictionary
	var residents := opening.get("residents", []) as Array
	if residents.is_empty():
		return {}
	var deceased_id := String(
		death_event.get("deceased_resident_id", "")
	).strip_edges()
	var template := (residents[0] as Dictionary).duplicate(true)
	for resident_value: Variant in residents:
		if (
			resident_value is Dictionary
			and String((resident_value as Dictionary).get("residentId", ""))
			== deceased_id
		):
			template = (resident_value as Dictionary).duplicate(true)
			break
	var event_id := String(death_event.get("event_id", "resident-death"))
	var visual_index := posmod(event_id.hash(), residents.size())
	var visual := residents[visual_index] as Dictionary
	var visual_attributes := visual.get("attributes", {}) as Dictionary
	var attributes := (template.get("attributes", {}) as Dictionary).duplicate(true)
	attributes["appearance"] = String(
		visual_attributes.get("appearance", attributes.get("appearance", ""))
	)
	var fallback_names := ["林澄", "周禾", "许岸", "陈野", "沈弦", "顾晴"]
	var proposed_name := String(persona.get("name", "")).strip_edges().left(24)
	var used_names: Dictionary = {}
	for resident_value: Variant in residents:
		if resident_value is Dictionary:
			used_names[String(
				((resident_value as Dictionary).get("attributes", {}) as Dictionary)
				.get("name", "")
			)] = true
	if proposed_name.is_empty() or used_names.has(proposed_name):
		for offset in fallback_names.size():
			var fallback_name := String(
				fallback_names[(visual_index + offset) % fallback_names.size()]
			)
			if not used_names.has(fallback_name):
				proposed_name = fallback_name
				break
	if proposed_name.is_empty() or used_names.has(proposed_name):
		proposed_name = "新居民%d" % (residents.size() + 1)
	attributes["name"] = proposed_name
	var gender := String(persona.get("gender", "")).strip_edges()
	attributes["gender"] = gender if gender in ["男", "女"] else (
		"女" if posmod(event_id.hash(), 2) == 0 else "男"
	)
	attributes["age"] = clampi(int(persona.get("age", 26)), 18, 80)
	attributes["desire"] = _replacement_text_or_fallback(
		persona.get("desire"),
		"在小镇找到能够长久投入的生活",
	)
	attributes["personality"] = _replacement_text_or_fallback(
		persona.get("personality"),
		"安静但愿意帮助别人，对新环境保持好奇",
	)
	attributes["speech"] = _replacement_text_or_fallback(
		persona.get("speech"),
		"说话简洁，熟悉之后会偶尔开玩笑",
	)
	template["attributes"] = attributes
	# World 的十五个住宅席位与 residentId 一一对应。新居民接替死亡
	# 居民的席位，保留内部稳定 ID，但姓名、人设、记忆和 Agent 运行时
	# 都会换成新居民，死亡记录仍留在公共世界日志中。
	var resident_id := deceased_id
	template["residentId"] = resident_id
	var world_state := (template.get("worldState", {}) as Dictionary).duplicate(true)
	world_state["doing"] = "刚刚来到小镇"
	template["worldState"] = world_state
	var binding := source_binding.duplicate(true)
	binding["residentId"] = resident_id
	binding["residentName"] = proposed_name
	return {
		"record": template,
		"identity": {
			"residentId": resident_id,
			"residentName": proposed_name,
		},
		"binding": binding,
		"deathEvent": death_event.duplicate(true),
	}


func _replacement_text_or_fallback(value: Variant, fallback: String) -> String:
	if not value is String:
		return fallback
	var normalized := (value as String).strip_edges()
	return fallback if normalized.is_empty() else normalized.left(160)


func _present_generated_replacement(candidate: Dictionary) -> void:
	if candidate.is_empty() or not is_instance_valid(_town_runtime):
		return
	_pending_replacement_candidate = candidate.duplicate(true)
	_replacement_world_admitted = false
	_replacement_admission_committed = false
	_town_runtime.set_resident_editor_open(true)
	if not is_instance_valid(_replacement_arrival_panel):
		_replacement_arrival_panel = REPLACEMENT_ARRIVAL_PANEL.new()
		_replacement_arrival_panel.name = "ReplacementResidentArrivalPanel"
		_replacement_arrival_panel.edit_requested.connect(
			_on_replacement_arrival_edit_requested,
		)
		var host: Node = (
			_town_ui_canvas_layer
			if is_instance_valid(_town_ui_canvas_layer)
			else self
		)
		host.add_child(_replacement_arrival_panel)
	_replacement_arrival_panel.present(candidate)


func _on_replacement_arrival_edit_requested() -> void:
	if is_instance_valid(_replacement_arrival_panel):
		_replacement_arrival_panel.queue_free()
	_replacement_arrival_panel = null
	_open_replacement_resident_editor()


func _open_replacement_resident_editor() -> void:
	if (
		_pending_replacement_candidate.is_empty()
		or not is_instance_valid(_town_ui_adapter)
		or not is_instance_valid(_town_ui_canvas_layer)
	):
		return
	if is_instance_valid(_replacement_editor_page):
		return
	var record := (
		_pending_replacement_candidate.get("record", {}) as Dictionary
	).duplicate(true)
	var attributes := record.get("attributes", {}) as Dictionary
	var initial_name := String(attributes.get("name", "")).strip_edges()
	var used_names: Array[String] = []
	var opening := _active_session_config.get("openingConfig", {}) as Dictionary
	for value: Variant in opening.get("residents", []) as Array:
		if not value is Dictionary:
			continue
		var resident := value as Dictionary
		if String(resident.get("residentId", "")) == String(record.get("residentId", "")):
			continue
		var name_value := String(
			(resident.get("attributes", {}) as Dictionary).get("name", "")
		).strip_edges()
		if not name_value.is_empty():
			used_names.append(name_value)
	_replacement_candidate_pool = REPLACEMENT_CANDIDATE_POOL.new()
	var pool_result := _replacement_candidate_pool.configure(
		used_names,
		initial_name,
	) as Dictionary
	if not bool(pool_result.get("ok", false)):
		_last_result = pool_result
		_present_generated_replacement(_pending_replacement_candidate)
		return
	_replacement_editor_service = TownCustomResidentCreatorService.new()
	var configured := _replacement_editor_service.configure(
		_replacement_candidate_pool,
		FORMAL_CATALOG.load_catalog(),
		_read_json(WORLD_DATA_PATH),
		{
			"draftId": "replacement-resident-%d" % Time.get_ticks_msec(),
			"revision": 1,
			"initialSource": record,
		},
	) as Dictionary
	if not bool(configured.get("ok", false)):
		_last_result = configured
		_replacement_editor_service = null
		_present_generated_replacement(_pending_replacement_candidate)
		return
	var bound := _town_ui_adapter.bind_custom_resident_creator_service(
		_replacement_editor_service,
	) as Dictionary
	if not bool(bound.get("ok", false)):
		_last_result = bound
		_replacement_editor_service = null
		_present_generated_replacement(_pending_replacement_candidate)
		return
	var page_scene := load(CUSTOM_RESIDENT_CREATOR_SCENE_PATH) as PackedScene
	var page := (
		page_scene.instantiate() as CustomResidentCreatorScreen
		if page_scene != null
		else null
	)
	if page == null:
		_town_ui_adapter.bind_custom_resident_creator_service(null)
		_replacement_editor_service = null
		_present_generated_replacement(_pending_replacement_candidate)
		return
	page.name = "ReplacementResidentEditor"
	page.process_mode = Node.PROCESS_MODE_ALWAYS
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.z_index = 2700
	page.set("presentation_mode", "admission")
	page.set("navigation_back_available", true)
	page.bind_town_ui_adapter(_town_ui_adapter)
	_connect_once(
		page,
		"intent_requested",
		_on_replacement_editor_intent_requested,
	)
	_connect_once(
		page,
		"action_blocked",
		_on_replacement_editor_action_blocked,
	)
	_replacement_editor_page = page
	_town_ui_canvas_layer.add_child(page)
	if page.has_method("focus_default_control"):
		page.call_deferred("focus_default_control")


func _on_replacement_editor_intent_requested(
	intent: String,
	payload: Dictionary,
) -> void:
	var route_only := bool(payload.get("routeOnly", false))
	var dispatch_result := payload.get("dispatchResult", {}) as Dictionary
	if not route_only and not bool(dispatch_result.get("ok", false)):
		_last_result = dispatch_result.duplicate(true)
		return
	if intent == "custom_resident_creator.cancel":
		_close_replacement_resident_editor()
		_present_generated_replacement(_pending_replacement_candidate)
		return
	if intent == "custom_resident_creator.open_wardrobe":
		var handoff := dispatch_result.get("wardrobeHandoff", {}) as Dictionary
		if (
			handoff.is_empty()
			or not is_instance_valid(_replacement_editor_page)
			or not _replacement_editor_page.open_complete_set_wardrobe(
				handoff.duplicate(true),
			)
		):
			_last_result = _failure("CUSTOM_RESIDENT_WARDROBE_ROUTE_UNAVAILABLE", false)
		return
	if intent == "custom_resident_creator.apply_wardrobe_result":
		return
	if intent != "custom_resident_creator.create":
		return
	var edited_source := dispatch_result.get("candidate", {}) as Dictionary
	if edited_source.is_empty():
		_last_result = _failure("CUSTOM_RESIDENT_SELECTION_HANDOFF_MISSING", false)
		return
	_merge_replacement_editor_source(edited_source)
	_close_replacement_resident_editor()
	call_deferred("_open_replacement_model_assignment")


func _on_replacement_editor_action_blocked(
	_intent: String,
	reason: String,
) -> void:
	_last_result = _failure(reason, false)


func _merge_replacement_editor_source(source: Dictionary) -> void:
	var candidate := _pending_replacement_candidate.duplicate(true)
	var record := (candidate.get("record", {}) as Dictionary).duplicate(true)
	var source_attributes := source.get("attributes", {}) as Dictionary
	var attributes := (record.get("attributes", {}) as Dictionary).duplicate(true)
	# 自定义页面的 selectionSummary 等展示元数据不属于
	# World/Agent 居民合同。只合并正式居民字段，避免 UI
	# 后续新增字段时再次泄漏到 Agent 初始化资料。
	for field_name: String in REPLACEMENT_AGENT_ATTRIBUTE_FIELDS:
		if source_attributes.has(field_name):
			attributes[field_name] = source_attributes.get(field_name)
	record["attributes"] = attributes
	var occupation := source.get("occupation", {}) as Dictionary
	var social := (record.get("socialState", {}) as Dictionary).duplicate(true)
	social["job"] = String(occupation.get("name", social.get("job", "")))
	social["workplace"] = String(
		occupation.get("workplacePlace", social.get("workplace", ""))
	)
	record["socialState"] = social
	if source.get("presentation", {}) is Dictionary:
		record["presentation"] = (
			source.get("presentation", {}) as Dictionary
		).duplicate(true)
	var resident_name := String(attributes.get("name", "")).strip_edges()
	var identity := (candidate.get("identity", {}) as Dictionary).duplicate(true)
	identity["residentName"] = resident_name
	var binding := (candidate.get("binding", {}) as Dictionary).duplicate(true)
	binding["residentName"] = resident_name
	candidate["record"] = record
	candidate["identity"] = identity
	candidate["binding"] = binding
	_pending_replacement_candidate = candidate


func _close_replacement_resident_editor() -> void:
	if is_instance_valid(_replacement_editor_page):
		_replacement_editor_page.unbind_town_ui_adapter()
		_replacement_editor_page.queue_free()
	_replacement_editor_page = null
	if is_instance_valid(_town_ui_adapter):
		_town_ui_adapter.bind_custom_resident_creator_service(null)
	_replacement_editor_service = null
	_replacement_candidate_pool = null


func _open_replacement_model_assignment() -> void:
	if (
		_pending_replacement_candidate.is_empty()
		or not is_instance_valid(_town_ui_adapter)
		or not is_instance_valid(_town_ui_host)
		or _provider_service == null
	):
		_present_generated_replacement(_pending_replacement_candidate)
		return
	var candidate := _pending_replacement_candidate
	var record := candidate.get("record", {}) as Dictionary
	var resident_id := String(record.get("residentId", ""))
	var home_space_id := _replacement_home_space_id(resident_id)
	_resident_model_assignment_service = RESIDENT_MODEL_ASSIGNMENT_SERVICE.new()
	var configured := _resident_model_assignment_service.configure(
		_provider_service,
		{"residents": [record.duplicate(true)]},
		{
			"schemaVersion": 1,
			"sourceScope": "resident_selection",
			"draftRevision": 1,
			"slots": [{
				"residentId": resident_id,
				"spaceId": home_space_id,
				"llmBinding": {},
			}],
		},
		{
			"revision": 1,
			"selectedResidentId": resident_id,
			"singleResidentMode": true,
			"allowedSpaceIds": [home_space_id],
			"applyHandler": _apply_pending_replacement_admission,
		},
	) as Dictionary
	if not bool(configured.get("ok", false)):
		_last_result = configured
		_resident_model_assignment_service = null
		_open_replacement_resident_editor()
		return
	_replacement_assignment_active = true
	_resident_model_assignment_service.back_requested.connect(
		_on_replacement_assignment_back_requested,
	)
	var bound := _town_ui_adapter.bind_resident_model_assignment_service(
		_resident_model_assignment_service,
	) as Dictionary
	if not bool(bound.get("ok", false)):
		_last_result = bound
		_replacement_assignment_active = false
		_resident_model_assignment_service = null
		_open_replacement_resident_editor()
		return
	var opened := _town_ui_host.open_page(
		&"resident_model_assignment",
		{"mode": "resident_admission"},
	) as Dictionary
	if not bool(opened.get("ok", false)):
		_last_result = opened
		_replacement_assignment_active = false
		_open_replacement_resident_editor()


func _replacement_home_space_id(resident_id: String) -> String:
	var resident_ids: Array[String] = []
	var opening := _active_session_config.get("openingConfig", {}) as Dictionary
	for value: Variant in opening.get("residents", []) as Array:
		if value is Dictionary:
			resident_ids.append(String((value as Dictionary).get("residentId", "")))
	resident_ids.sort()
	var index := resident_ids.find(resident_id)
	return "home_%02d" % (index + 1 if index >= 0 else 1)


func _on_replacement_assignment_back_requested(
	_draft: Dictionary,
	_revision: int,
) -> void:
	if not _replacement_assignment_active:
		return
	if _replacement_world_admitted:
		_last_result = _failure(
			"RESIDENT_REPLACEMENT_BINDING_RETRY_REQUIRED",
			true,
		)
		return
	_replacement_assignment_active = false
	_replacement_world_admitted = false
	call_deferred("_restore_replacement_editor_after_assignment_back")


func _restore_replacement_editor_after_assignment_back() -> void:
	if is_instance_valid(_town_ui_adapter):
		_town_ui_adapter.bind_resident_model_assignment_service(null)
	_resident_model_assignment_service = null
	_open_replacement_resident_editor()


func _apply_pending_replacement_admission(
	_draft: Dictionary,
	assignment_bindings: Array,
) -> Dictionary:
	if _pending_replacement_candidate.is_empty():
		return _failure("REPLACEMENT_RESIDENT_CANDIDATE_MISSING", false)
	if assignment_bindings.size() != 1 or not assignment_bindings[0] is Dictionary:
		return _failure("SESSION_LLM_BINDINGS_INVALID", false)
	var candidate := _pending_replacement_candidate.duplicate(true)
	var record := candidate.get("record", {}) as Dictionary
	var identity := candidate.get("identity", {}) as Dictionary
	var binding := (assignment_bindings[0] as Dictionary).duplicate(true)
	binding["residentName"] = String(identity.get("residentName", ""))
	var death_event := candidate.get("deathEvent", {}) as Dictionary
	var world := _town_runtime.get_world_runtime() as TownWorldRuntime
	if world == null:
		return _failure("RESIDENT_REPLACEMENT_WORLD_UNAVAILABLE", true)
	if _replacement_admission_committed:
		binding = (
			candidate.get("committedBinding", binding) as Dictionary
		).duplicate(true)
	else:
		var roster_projection := _build_replacement_session_roster(
			record,
			identity,
			binding,
		) as Dictionary
		if not bool(roster_projection.get("ok", false)):
			_last_result = roster_projection.duplicate(true)
			return roster_projection
		var deceased_id := String(
			death_event.get("deceased_resident_id", "")
		)
		if not _replacement_world_admitted:
			var preview := RESIDENT_REPLACEMENT.preview_agent_initialization(
				world,
				record,
				deceased_id,
			) as Dictionary
			if not bool(preview.get("ok", false)):
				_last_result = preview.duplicate(true)
				return preview
			var preflight := _gateway.preflight_replacement_resident(
				identity,
				binding,
				preview.get("initialization", {}),
			) as Dictionary
			if not bool(preflight.get("ok", false)):
				_last_result = preflight.duplicate(true)
				return preflight
			var world_result := RESIDENT_REPLACEMENT.admit(
				world,
				record,
				deceased_id,
			) as Dictionary
			if not bool(world_result.get("ok", false)):
				_last_result = world_result.duplicate(true)
				return world_result
			_replacement_world_admitted = true
		var gateway_result := _gateway.admit_replacement_resident(
			identity,
			binding,
		) as Dictionary
		if not bool(gateway_result.get("ok", false)):
			_last_result = gateway_result.duplicate(true)
			return gateway_result
		_active_session_config["openingConfig"] = (
			roster_projection.get("openingConfig", {}) as Dictionary
		).duplicate(true)
		_active_session_config["residentIdentities"] = (
			roster_projection.get("residentIdentities", []) as Array
		).duplicate(true)
		_active_session_config["residentBindings"] = (
			roster_projection.get("residentBindings", []) as Array
		).duplicate(true)
		candidate["committedBinding"] = binding.duplicate(true)
		_pending_replacement_candidate = candidate.duplicate(true)
		_replacement_admission_committed = true
	var opening := (
		_active_session_config.get("openingConfig", {}) as Dictionary
	).duplicate(true)
	var identities := (
		_active_session_config.get("residentIdentities", []) as Array
	).duplicate(true)
	var bindings := (
		_active_session_config.get("residentBindings", []) as Array
	).duplicate(true)
	var roster_results: Array = [
		_town_runtime.update_resident_roster(identities, bindings, opening),
		_session_ui_service.update_resident_roster(identities, bindings, opening),
	]
	if is_instance_valid(_town_ui_adapter):
		roster_results.append(_town_ui_adapter.update_session_resident_roster(
			identities,
			bindings,
			opening,
		))
	for roster_result_value: Variant in roster_results:
		if (
			not roster_result_value is Dictionary
			or not bool((roster_result_value as Dictionary).get("ok", false))
		):
			_last_result = _failure(
				"SESSION_RESIDENT_ROSTER_UPDATE_FAILED",
				true,
				[{"result": roster_result_value}],
			)
			return _last_result
	var save_result := _session_ui_service.create_save(
		{"reason": "resident_replacement_admitted"},
	) as Dictionary
	_last_result = save_result.duplicate(true)
	if not bool(save_result.get("ok", false)):
		return save_result
	_pending_replacement_candidate.clear()
	_replacement_assignment_active = false
	_replacement_world_admitted = false
	_replacement_admission_committed = false
	_town_runtime.set_resident_editor_open(false)
	call_deferred("_restore_in_session_resident_assignment_after_admission")
	return save_result


func _build_replacement_session_roster(
	record: Dictionary,
	identity: Dictionary,
	binding: Dictionary,
) -> Dictionary:
	var resident_id := String(identity.get("residentId", ""))
	var opening := (
		_active_session_config.get("openingConfig", {}) as Dictionary
	).duplicate(true)
	var residents := (opening.get("residents", []) as Array).duplicate(true)
	var identities := (
		_active_session_config.get("residentIdentities", []) as Array
	).duplicate(true)
	var bindings := (
		_active_session_config.get("residentBindings", []) as Array
	).duplicate(true)
	var resident_replaced := false
	var identity_replaced := false
	var binding_replaced := false
	for resident_index in residents.size():
		if String((residents[resident_index] as Dictionary).get("residentId", "")) == resident_id:
			residents[resident_index] = record.duplicate(true)
			resident_replaced = true
			break
	for identity_index in identities.size():
		if String((identities[identity_index] as Dictionary).get("residentId", "")) == resident_id:
			identities[identity_index] = identity.duplicate(true)
			identity_replaced = true
			break
	for binding_index in bindings.size():
		if String((bindings[binding_index] as Dictionary).get("residentId", "")) == resident_id:
			bindings[binding_index] = binding.duplicate(true)
			binding_replaced = true
			break
	if not resident_replaced or not identity_replaced or not binding_replaced:
		return _failure("SESSION_RESIDENT_REPLACEMENT_SLOT_MISSING", false)
	opening["residents"] = residents
	opening["agentSoulProfiles"] = AGENT_SOUL_PROFILE.analyze_all(residents)
	identities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	bindings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"openingConfig": opening,
		"residentIdentities": identities,
		"residentBindings": bindings,
	}


func _restore_in_session_resident_assignment_after_admission() -> void:
	if is_instance_valid(_town_ui_adapter):
		_configure_in_session_resident_model_assignment(_town_ui_adapter)


func _reset_replacement_admission_ui() -> void:
	if is_instance_valid(_replacement_arrival_panel):
		_replacement_arrival_panel.queue_free()
	_replacement_arrival_panel = null
	_close_replacement_resident_editor()
	if _replacement_assignment_active and is_instance_valid(_town_ui_adapter):
		_town_ui_adapter.bind_resident_model_assignment_service(null)
	_replacement_assignment_active = false
	_replacement_world_admitted = false
	_replacement_admission_committed = false
	_replacement_candidate_pool = null


func _instantiate_town_runtime() -> Node:
	if _town_runtime_scene == null:
		_town_runtime_scene = load(TOWN_RUNTIME_SCENE_PATH) as PackedScene
	if _town_runtime_scene == null:
		return null
	return _town_runtime_scene.instantiate()


func _instantiate_control_scene(scene_path: String) -> Control:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Control


func _instantiate_control_script(script_path: String) -> Control:
	var script := load(script_path) as Script
	if script == null:
		return null
	return script.new() as Control


func _begin_town_entry_loading(
	route_kind: String,
	generation := -1,
	owner := "",
	context: Dictionary = {},
) -> void:
	_ensure_town_entry_loading_overlay()
	var resolved_generation := (
		_flow_generation if generation < 0 else generation
	)
	var normalized_route_kind := route_kind.strip_edges()
	var already_active := (
		_town_entry_loading_generation == resolved_generation
		and _town_entry_loading_route_kind == normalized_route_kind
		and bool(_town_entry_loading_overlay.call("is_active"))
	)
	_town_entry_loading_generation = resolved_generation
	_town_entry_loading_route_kind = normalized_route_kind
	_town_entry_loading_owner = owner.strip_edges()
	_town_entry_loading_context = context.duplicate(true)
	if not already_active:
		_town_entry_loading_overlay.call("begin", normalized_route_kind)


func _advance_town_entry_loading(progress: float, status_text: String) -> void:
	if not is_instance_valid(_town_entry_loading_overlay):
		return
	if _town_entry_loading_generation != _flow_generation:
		return
	_town_entry_loading_overlay.call("advance", progress, status_text)


func _dismiss_town_entry_loading() -> void:
	if not is_instance_valid(_town_entry_loading_overlay):
		return
	_town_entry_loading_overlay.call("dismiss")
	_town_entry_loading_generation = -1
	_town_entry_loading_route_kind = ""
	_town_entry_loading_owner = ""
	_town_entry_loading_context.clear()


func _dismiss_town_entry_loading_for_generation(generation: int) -> void:
	if generation != _town_entry_loading_generation:
		return
	_dismiss_town_entry_loading()


func _dismiss_town_entry_loading_after_frame(generation: int) -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if (
		generation != _flow_generation
		or generation != _town_entry_loading_generation
	):
		return
	_dismiss_town_entry_loading_for_generation(generation)


func get_formal_runtime_audit_snapshot() -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size
	var input_blockers: Array[Dictionary] = []
	_collect_visible_input_blockers(
		get_tree().current_scene,
		input_blockers,
		viewport_size,
	)
	var adapter_view_models: Dictionary = {}
	var adapter: Node = null
	if is_instance_valid(_town_runtime) and _town_runtime.has_method("get_ui_adapter"):
		adapter = _town_runtime.call("get_ui_adapter") as Node
	if is_instance_valid(adapter) and adapter.has_method("get_view_model"):
		for scope: String in [
			"lifecycle",
			"session",
			"save",
			"pause_menu",
			"avatar",
			"town_hud",
			"conversation",
			"indoor",
		]:
			adapter_view_models[scope] = adapter.call("get_view_model", scope)
	var runtime_state: Dictionary = {}
	if is_instance_valid(_town_runtime) and _town_runtime.has_method("get_runtime_state"):
		runtime_state = _town_runtime.call("get_runtime_state") as Dictionary
	var legacy_layers: Dictionary = {}
	if is_instance_valid(_town_runtime):
		for legacy_name: String in ["PlayerUi", "TownUi"]:
			var legacy_layer := _town_runtime.get_node_or_null(legacy_name) as CanvasLayer
			legacy_layers[legacy_name] = {
				"mounted": legacy_layer != null,
				"visible": legacy_layer != null and legacy_layer.visible,
				"layer": legacy_layer.layer if legacy_layer != null else -1,
			}
	var focus_owner := get_viewport().gui_get_focus_owner()
	return {
		"flow": get_flow_snapshot(),
		"currentScene": (
			String(get_tree().current_scene.name)
			if get_tree().current_scene != null
			else ""
		),
		"treePaused": get_tree().paused,
		"viewportSize": viewport_size,
		"windowSize": DisplayServer.window_get_size(),
		"windowMode": DisplayServer.window_get_mode(),
		"focusOwner": (
			String(focus_owner.get_path())
			if is_instance_valid(focus_owner)
			else ""
		),
		"formalCanvas": {
			"mounted": is_instance_valid(_town_ui_canvas_layer),
			"visible": (
				_town_ui_canvas_layer.visible
				if is_instance_valid(_town_ui_canvas_layer)
				else false
			),
			"layer": (
				_town_ui_canvas_layer.layer
				if is_instance_valid(_town_ui_canvas_layer)
				else -1
			),
		},
		"townUiHost": (
			_town_ui_host.call("debug_snapshot")
			if is_instance_valid(_town_ui_host)
			and _town_ui_host.has_method("debug_snapshot")
			else {}
		),
		"avatarHud": _control_runtime_snapshot(_avatar_hud),
		"pauseHost": _control_runtime_snapshot(_pause_host),
		"legacyLayers": legacy_layers,
		"runtimeState": runtime_state,
		"viewModels": adapter_view_models,
		"visibleInputBlockers": input_blockers,
	}


func _write_formal_runtime_audit_if_requested() -> void:
	var audit_path := OS.get_environment(FORMAL_RUNTIME_AUDIT_ENV).strip_edges()
	if audit_path.is_empty():
		return
	# A failed Continue never mounts TownUiRuntimeHost. Keep the same opt-in
	# audit useful for the real Startup path without writing transient success
	# snapshots before the deferred Town route has finished mounting.
	if not is_instance_valid(_town_ui_host) and not _formal_runtime_audit_written:
		if _last_result.is_empty() or bool(_last_result.get("ok", false)):
			return
	var now_msec := Time.get_ticks_msec()
	if now_msec - _formal_runtime_audit_last_write_msec < 100:
		return
	var file := FileAccess.open(audit_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(get_formal_runtime_audit_snapshot(), "\t"))
	_formal_runtime_audit_written = true
	_formal_runtime_audit_last_write_msec = now_msec


func _control_runtime_snapshot(control: Control) -> Dictionary:
	if not is_instance_valid(control):
		return {"mounted": false}
	return {
		"mounted": true,
		"visible": control.visible,
		"visibleInTree": control.is_visible_in_tree(),
		"mouseFilter": control.mouse_filter,
		"rect": control.get_global_rect(),
		"modulate": control.modulate,
		"selfModulate": control.self_modulate,
		"processMode": control.process_mode,
	}


func _collect_visible_input_blockers(
	root: Node,
	result: Array[Dictionary],
	viewport_size: Vector2,
) -> void:
	if root == null:
		return
	if root is Control:
		var control := root as Control
		if control.is_visible_in_tree() and control.mouse_filter == Control.MOUSE_FILTER_STOP:
			var rect := control.get_global_rect()
			if (
				rect.size.x >= viewport_size.x * 0.9
				and rect.size.y >= viewport_size.y * 0.9
			):
				result.append({
					"path": String(control.get_path()),
					"rect": rect,
					"zIndex": control.z_index,
					"processMode": control.process_mode,
				})
	for child: Node in root.get_children():
		_collect_visible_input_blockers(child, result, viewport_size)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _is_fullscreen_toggle_shortcut(event):
		if (
			is_instance_valid(_audio_display_settings_service)
			and bool(
				_audio_display_settings_service.toggle_fullscreen_from_global_shortcut()
			)
		):
			get_viewport().set_input_as_handled()
		return
	var current := get_tree().current_scene
	if _town_runtime == null or current != _town_runtime or event.keycode != KEY_ESCAPE:
		return
	if is_instance_valid(_town_ui_host) and _town_ui_route != &"town":
		var back_handled := false
		if _town_ui_host.has_method("request_back"):
			back_handled = bool(_town_ui_host.call("request_back"))
		else:
			back_handled = bool(_town_ui_host.call("close_page"))
		if (
			not back_handled
			and _town_ui_host.has_method("present_back_blocked_feedback")
		):
			_town_ui_host.call(
				"present_back_blocked_feedback",
				"当前操作还没完成，请稍后再试。",
			)
		get_viewport().set_input_as_handled()
		return
	if _pause_open:
		var pause_route := (
			String(_pause_host.call("current_route"))
			if _pause_host != null and _pause_host.has_method("current_route")
			else "pause_menu"
		)
		if (
			pause_route in ["audio_display_settings", "load_game"]
			and _pause_host != null
			and _pause_host.has_method("request_back")
			and bool(_pause_host.call("request_back"))
		):
			get_viewport().set_input_as_handled()
			return
		_close_pause_menu()
	else:
		_open_pause_menu()
	get_viewport().set_input_as_handled()


func _is_fullscreen_toggle_shortcut(event: InputEventKey) -> bool:
	return (
		event.keycode == KEY_F11
		or (
			event.alt_pressed
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER]
		)
	)


func get_flow_snapshot() -> Dictionary:
	return {
		"generation": _flow_generation,
		"route": _route_name(get_tree().current_scene),
		"worldIntroRevision": int(_world_intro_vm.get("revision", 0)),
		"worldIntroPageIndex": int(
			(_world_intro_vm.get("data", {}) as Dictionary).get(
				"currentPageIndex", -1
			)
		),
		"internalPlaytest": _internal_playtest_enabled(),
		"lastResult": _last_result.duplicate(true),
		"townStarted": (
			_town_runtime != null
			and _town_runtime.has_method("get_startup_result")
			and bool((_town_runtime.call("get_startup_result") as Dictionary).get("ok", false))
		),
		"avatarHudMounted": is_instance_valid(_avatar_hud),
		"pauseHostMounted": is_instance_valid(_pause_host),
		"townUiHostMounted": is_instance_valid(_town_ui_host),
		"townUiRoute": String(_town_ui_route),
		"pauseOpen": _pause_open,
		"continueEnabled": _adapter_action_enabled("save", "continue"),
		"saveEnabled": _adapter_action_enabled("save", "create"),
		"dailyAutoSave": get_daily_auto_save_diagnostics(),
	}


func get_daily_auto_save_diagnostics() -> Dictionary:
	return {
		"lastSavedDay": _daily_auto_save_day,
		"lastAttemptDay": _daily_auto_save_last_attempt_day,
		"attempts": _daily_auto_save_attempts,
		"successes": _daily_auto_save_successes,
		"lastRevision": _daily_auto_save_last_revision,
		"failures": _daily_auto_save_failures.duplicate(true),
		"inflight": _daily_auto_save_inflight,
	}


func request_return_to_start() -> Dictionary:
	var departure := _prepare_session_departure()
	if not bool(departure.get("ok", false)):
		_last_result = departure.duplicate(true)
		return departure
	var startup_scene := load(STARTUP_SCENE_PATH) as PackedScene
	if startup_scene == null:
		return _record_route_open_failure(
			"GAME_FLOW_STARTUP_ROUTE_FAILED",
			"启动页面暂时打不开，请稍后再试。",
		)
	var route_error := get_tree().change_scene_to_packed(startup_scene)
	if route_error != OK:
		return _present_route_failure_result(
			_failure("GAME_FLOW_STARTUP_ROUTE_FAILED", false, [{
				"godotError": route_error,
			}]),
			"启动页面暂时打不开，请稍后再试。",
		)
	if _pause_open:
		_close_pause_menu()
	_unmount_town_overlays()
	_release_internal_session_refs()
	_flow_generation += 1
	_play_cover_music()
	return departure


func request_quit_game(execute_process_quit := true) -> Dictionary:
	if _quit_departure_pending:
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"pending": true,
			"departureId": _quit_departure_id,
			"quitRequested": true,
			"processQuitExecuted": false,
		}
	if (
		_town_runtime == null
		or not is_instance_valid(_town_runtime)
		or _internal_playtest_enabled()
	):
		var direct_departure := _prepare_session_departure()
		_last_result = direct_departure.duplicate(true)
		if bool(direct_departure.get("ok", false)) and execute_process_quit:
			_prepare_audio_shutdown()
			_schedule_process_quit()
		var direct_result := direct_departure.duplicate(true)
		direct_result["quitRequested"] = bool(
			direct_departure.get("ok", false)
		)
		direct_result["processQuitExecuted"] = (
			bool(direct_departure.get("ok", false))
			and execute_process_quit
		)
		return direct_result
	if _session_ui_service == null:
		var service_missing := _failure(
			"SESSION_SAVE_SERVICE_NOT_CONFIGURED",
			false,
		)
		_last_result = service_missing.duplicate(true)
		return service_missing
	if (
		_gateway == null
		or not is_instance_valid(_gateway)
		or not _gateway.has_method("prepare_departure_messages")
	):
		return _continue_quit_after_optional_messages(
			[],
			execute_process_quit,
		)
	if _quit_departure_id.is_empty():
		_quit_departure_id = "departure-%d" % Time.get_ticks_usec()
	_quit_departure_pending = true
	_quit_execute_process = execute_process_quit
	_begin_town_entry_loading("quit_game")
	_advance_town_entry_loading(0.18, "正在整理并保存小镇…")
	var started := _gateway.call(
		"prepare_departure_messages",
		_quit_departure_id,
		2,
		Callable(self, "_on_quit_departure_messages_ready"),
	) as Dictionary
	if not bool(started.get("ok", false)):
		return _continue_quit_after_optional_messages(
			[],
			execute_process_quit,
		)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"pending": _quit_departure_pending,
		"departureId": _quit_departure_id,
		"quitRequested": true,
		"processQuitExecuted": (
			not _quit_departure_pending and execute_process_quit
		),
	}


func _on_quit_departure_messages_ready(result: Dictionary) -> void:
	if not _quit_departure_pending:
		return
	if not bool(result.get("ok", false)):
		_continue_quit_after_optional_messages(
			[],
			_quit_execute_process,
		)
		return
	var messages_value: Variant = result.get("messages", [])
	if not messages_value is Array:
		_continue_quit_after_optional_messages(
			[],
			_quit_execute_process,
		)
		return
	_continue_quit_after_optional_messages(
		(messages_value as Array).duplicate(true),
		_quit_execute_process,
	)


func _continue_quit_after_optional_messages(
	messages: Array,
	execute_process_quit: bool,
) -> Dictionary:
	_quit_departure_pending = true
	_quit_execute_process = execute_process_quit
	_begin_town_entry_loading("quit_game")
	_advance_town_entry_loading(0.58, "正在保存小镇…")
	var departure := _prepare_session_departure(
		messages.duplicate(true),
	)
	_last_result = departure.duplicate(true)
	_quit_departure_pending = false
	if not bool(departure.get("ok", false)):
		_dismiss_town_entry_loading()
		call_deferred(
			"_present_pause_departure_failure",
			"pause_menu.quit_game",
			departure.duplicate(true),
		)
		return departure
	_advance_town_entry_loading(1.0, "保存成功")
	_quit_departure_id = ""
	if _quit_execute_process:
		_prepare_audio_shutdown()
		_schedule_process_quit()
	else:
		_dismiss_town_entry_loading()
	return departure


func _prepare_audio_shutdown() -> void:
	var audio_controller := get_node_or_null("/root/TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")


func _play_cover_music() -> void:
	var audio_controller := get_node_or_null("/root/TownAudioController")
	if audio_controller != null and audio_controller.has_method("play_cover_music"):
		audio_controller.call("play_cover_music")


func _schedule_process_quit() -> void:
	if _process_quit_scheduled:
		return
	_process_quit_scheduled = true
	# Give the audio thread a short, pause-independent release window after all
	# streams have stopped, then terminate the process.
	get_tree().create_timer(0.5, true, false, true).timeout.connect(
		_complete_process_quit,
		CONNECT_ONE_SHOT,
	)


func _complete_process_quit() -> void:
	_process_quit_scheduled = false
	get_tree().quit()


func _unmount_town_overlays() -> void:
	if is_instance_valid(_town_ui_canvas_layer):
		UI_NODE_RETIREMENT.retire(_town_ui_canvas_layer)
	else:
		if is_instance_valid(_town_ui_host):
			UI_NODE_RETIREMENT.retire(_town_ui_host)
		if is_instance_valid(_pause_host):
			UI_NODE_RETIREMENT.retire(_pause_host)
		if is_instance_valid(_avatar_hud):
			UI_NODE_RETIREMENT.retire(_avatar_hud)
	_town_ui_canvas_layer = null
	_town_ui_host = null
	_pause_host = null
	_avatar_hud = null
	_town_ui_route = &"town"
	_pause_open = false


func _release_internal_session_refs() -> void:
	_dismiss_town_entry_loading()
	_reset_custom_resident_creator_session(true)
	_reset_resident_model_assignment_session()
	_reset_replacement_admission_ui()
	_bootstrap = null
	_provider_service = null
	_gateway = null
	_session_ui_service = null
	_town_ui_adapter = null
	_provider_settings_ui_service = null
	_ui_page_projection_service = null
	_active_session_config.clear()
	_daily_auto_save_day = -1
	_daily_auto_save_last_attempt_day = -1
	_daily_auto_save_last_attempt_msec = -100000
	_daily_auto_save_attempts = 0
	_daily_auto_save_successes = 0
	_daily_auto_save_last_revision = 0
	_daily_auto_save_failures.clear()
	_daily_auto_save_inflight = false
	_replacement_generation_pending = false
	_replacement_last_checked_minute = -1
	_replacement_world_admitted = false
	_pending_replacement_candidate.clear()
	_pending_runtime = null
	_town_runtime = null
	_town_ui_canvas_layer = null
	_world_intro = null
	_world_intro_vm.clear()
	_new_game_route_context.clear()
	_resident_selection = null
	_resident_selection_vm.clear()
	_quit_departure_pending = false
	_quit_departure_id = ""


func _bind_current_scene() -> void:
	var current := get_tree().current_scene
	if current == null or current.get_instance_id() == _bound_scene_id:
		return
	_bound_scene_id = current.get_instance_id()
	_world_intro_navigation_pending = false
	_startup_settings_page = null
	_startup_load_game_page = null
	_startup_load_game_mode = ""
	_pending_load_game_new_game_payload.clear()
	_custom_resident_creator_page = null
	_resident_model_assignment_page = null
	_resident_selection = null
	_world_intro = null
	if current.name == "StartupScreen":
		_bind_startup(current)
	elif current.name == "WorldIntroScreen":
		_bind_world_intro(current as Control)
	elif current.name == "ResidentSelectionScreen":
		_bind_resident_selection(current as Control)
	elif current.has_method("get_ui_adapter") and current.has_method("get_world_runtime"):
		_bind_town_runtime(current)


func _bind_startup(startup: Node) -> void:
	_in_session_load_pending = false
	_town_runtime = null
	_town_ui_canvas_layer = null
	_avatar_hud = null
	_pause_host = null
	_town_ui_host = null
	_town_ui_route = &"town"
	_pause_open = false
	_connect_once(startup, "intent_requested", Callable(self, "_on_startup_intent_requested"))
	_connect_once(startup, "action_blocked", Callable(self, "_on_startup_action_blocked"))
	var startup_view_models := _build_startup_view_models()
	if startup.has_method("apply_view_models"):
		var applied := bool(startup.call(
			"apply_view_models",
			startup_view_models["session"],
			startup_view_models["save"],
		))
		if not applied:
			_last_result = _failure("STARTUP_VIEW_MODEL_REJECTED", false)
	var new_game_button := startup.get_node_or_null("NewGameButton") as Button
	if (
		startup.get_node_or_null("ResidentMessagePopup") == null
		and new_game_button != null
		and not new_game_button.disabled
	):
		new_game_button.call_deferred("grab_focus")
	if _internal_playtest_enabled():
		var notice := startup.get_node_or_null("StartupNotice") as Label
		if notice != null:
			notice.text = "开发内测 · 新游戏使用显式 placeholder；继续游戏已禁用"
			notice.modulate.a = 1.0


func _on_startup_intent_requested(intent: StringName, payload: Dictionary) -> void:
	match String(intent):
		"session.new_game":
			_pending_continue_notice.clear()
			if not _startup_new_game_payload_is_authorized(payload):
				_publish_startup_action_failure(
					intent,
					_failure("STARTUP_NEW_GAME_NOT_AUTHORIZED", false),
				)
				return
			var route_payload := payload.duplicate(true)
			if not _internal_playtest_enabled():
				var catalog := _startup_catalog_snapshot()
				if not bool(catalog.get("ok", false)):
					_publish_startup_action_failure(intent, catalog)
					return
				var slot_id := String(route_payload.get("slotId", "")).strip_edges()
				if slot_id.is_empty():
					slot_id = String(catalog.get("firstEmptySlotId", ""))
				if slot_id.is_empty():
					_open_startup_load_game("overwrite_selection", route_payload)
					return
				route_payload["slotId"] = slot_id
				var selected_slot := _startup_slot_by_id(catalog, slot_id)
				if selected_slot.is_empty():
					_publish_startup_action_failure(
						intent,
						_failure("STARTUP_SAVE_SLOT_ID_INVALID", false),
					)
					return
				if (
					String(selected_slot.get("state", "")) != "empty"
					and not bool(route_payload.get("overwriteConfirmed", false))
				):
					var existing_save := _discover_startup_slot(slot_id)
					if not bool(existing_save.get("ok", false)):
						_publish_startup_action_failure(intent, existing_save)
						return
					_open_new_game_overwrite(route_payload, existing_save)
					return
			_reset_new_game_configuration_context()
			_flow_generation += 1
			_new_game_route_context = route_payload.duplicate(true)
			_world_intro_vm = _build_world_intro_view_model(0, _flow_generation)
			call_deferred("_enter_world_intro", _flow_generation)
		"session.continue":
			if _internal_playtest_enabled():
				_last_result = _failure("SESSION_CONTINUE_FORMAL_ONLY", false)
			else:
				_flow_generation += 1
				call_deferred("_start_formal_continue", _flow_generation)
		"session.continue_slot", "session.confirm_recovery":
			if _internal_playtest_enabled():
				_last_result = _failure("SESSION_CONTINUE_FORMAL_ONLY", false)
			else:
				var slot_id := String(payload.get("slotId", "")).strip_edges()
				if slot_id.is_empty():
					_last_result = _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
					return
				_flow_generation += 1
				call_deferred(
					"_start_formal_continue",
					_flow_generation,
					slot_id,
					bool(payload.get("recoveryConfirmed", false))
						or String(intent) == "session.confirm_recovery",
				)
		"startup.back":
			request_quit_game()
		"startup.open_connection_settings":
			_open_startup_settings(&"provider_settings")
		"startup.open_game_settings":
			_open_startup_settings(&"audio_display_settings")
		"startup.open_load_game":
			_open_startup_load_game("load")
		"startup.quit_game":
			request_quit_game()
		"startup.resident_messages_shown":
			_record_startup_resident_message_receipt(payload)
		_:
			_last_result = _failure("STARTUP_INTENT_UNSUPPORTED", false)


func _on_startup_action_blocked(intent: StringName, reason: String) -> void:
	_last_result = _failure(reason, false)


func _publish_startup_action_failure(
	intent: StringName,
	result: Dictionary,
) -> void:
	_last_result = result.duplicate(true)
	var startup := get_tree().current_scene
	if (
		startup != null
		and startup.name == "StartupScreen"
		and startup.has_method("present_host_result")
	):
		startup.call(
			"present_host_result",
			intent,
			result.duplicate(true),
		)


func _record_route_open_failure(
	error_code: String,
	player_message: String,
	retryable := true,
) -> Dictionary:
	return _present_route_failure_result(
		_failure(error_code, retryable),
		player_message,
	)


func _present_route_failure_result(
	result: Dictionary,
	player_message: String,
) -> Dictionary:
	result = result.duplicate(true)
	result["playerMessage"] = player_message
	_last_result = result.duplicate(true)
	var current := get_tree().current_scene
	if current != null:
		if current.has_method("show_navigation_failure"):
			current.call("show_navigation_failure", player_message)
		elif current.has_method("_show_notice"):
			current.call("_show_notice", player_message)
	return result


func _initialize_startup_settings_services() -> void:
	_startup_ui_adapter = TOWN_UI_ADAPTER.new()
	_startup_ui_adapter.name = "StartupUiAdapter"
	add_child(_startup_ui_adapter)
	_startup_ui_adapter.call(
		"set_custom_resident_creator_route_capabilities",
		{"wardrobe": true},
	)
	_startup_ui_adapter.call(
		"bind_audio_display_settings_service",
		_audio_display_settings_service,
	)
	# Provider binding publishes a synchronous ViewModel callback. Configure the
	# local save catalog first so that callback can never publish a false
	# no-save snapshot before Continue discovery is available.
	_startup_save_store = SESSION_SAVE_STORE.new()
	_startup_save_catalog = STARTUP_SAVE_CATALOG.new()
	var startup_agent_save_store: RefCounted = AGENT_SAVE_STORE.new()
	var save_catalog_configuration := _startup_save_catalog.call(
		"configure",
		_startup_save_store,
		STARTUP_SAVE_CATALOG.DEFAULT_PROFILE_PATH,
		startup_agent_save_store,
	) as Dictionary
	if not bool(save_catalog_configuration.get("ok", false)):
		_last_result = save_catalog_configuration
	_startup_provider_service = PROVIDER_SERVICE.new()
	_startup_provider_service.call("configure", {
		"capabilityMode": "formal",
		"source": "runtime",
		"allowFake": false,
		"providerConfigs": {},
	}, self)
	_startup_provider_settings_service = PROVIDER_SETTINGS_SERVICE.new()
	_connect_once(
		_startup_provider_settings_service,
		"view_model_changed",
		Callable(self, "_on_startup_provider_view_model_changed"),
	)
	_startup_provider_settings_service.call(
		"bind_provider_service",
		_startup_provider_service,
		self,
	)
	_startup_ui_adapter.call(
		"bind_provider_settings_service",
		_startup_provider_settings_service,
	)


func _on_startup_provider_view_model_changed(
	_scope: String,
	_view_model: Dictionary,
) -> void:
	var startup := get_tree().current_scene
	if startup == null or startup.name != "StartupScreen":
		return
	if startup.has_method("apply_view_models"):
		var models := _build_startup_view_models()
		startup.call(
			"apply_view_models",
			models.get("session", {}) as Dictionary,
			models.get("save", {}) as Dictionary,
		)


func _open_startup_settings(route: StringName) -> void:
	_close_startup_settings()
	var startup := get_tree().current_scene as Control
	if startup == null or startup.name != "StartupScreen":
		_record_route_open_failure(
			"STARTUP_SETTINGS_HOST_UNAVAILABLE",
			"设置页面暂时打不开，请稍后再试。",
		)
		return
	var scene_path := (
		PROVIDER_SETTINGS_SCENE_PATH
		if route == &"provider_settings"
		else AUDIO_DISPLAY_SETTINGS_SCENE_PATH
	)
	var page := _instantiate_control_scene(scene_path)
	if page == null:
		_record_route_open_failure(
			"STARTUP_SETTINGS_ROUTE_FAILED",
			"设置页面暂时打不开，请稍后再试。",
		)
		return
	page.name = "%sRoute" % String(route).to_pascal_case()
	page.process_mode = Node.PROCESS_MODE_ALWAYS
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.z_index = 2000
	_startup_settings_page = page
	startup.add_child(page)
	startup.set_process_unhandled_input(false)
	if page.has_method("bind_town_ui_adapter"):
		page.call("bind_town_ui_adapter", _startup_ui_adapter)
	elif page.has_method("bind_adapter"):
		page.call("bind_adapter", _startup_ui_adapter)
	_connect_once(
		page,
		"intent_requested",
		Callable(self, "_on_startup_settings_intent_requested"),
	)


func _open_startup_load_game(
	mode: String = "load",
	new_game_payload: Dictionary = {},
) -> void:
	_close_startup_load_game()
	var startup := get_tree().current_scene as Control
	if startup == null or startup.name != "StartupScreen":
		_record_route_open_failure(
			"STARTUP_LOAD_GAME_HOST_UNAVAILABLE",
			"读取存档页面暂时打不开，请稍后再试。",
		)
		return
	var page := _instantiate_control_scene(LOAD_GAME_SCENE_PATH)
	if page == null:
		_record_route_open_failure(
			"STARTUP_LOAD_GAME_ROUTE_FAILED",
			"读取存档页面暂时打不开，请稍后再试。",
		)
		return
	page.name = "LoadGameRoute"
	page.process_mode = Node.PROCESS_MODE_ALWAYS
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.z_index = 2000
	var view_model := get_startup_load_game_view_model(mode)
	if not bool(page.call("apply_view_model", view_model)):
		page.free()
		_record_route_open_failure(
			"STARTUP_LOAD_GAME_VIEW_MODEL_INVALID",
			"读取存档页面暂时打不开，请稍后再试。",
		)
		return
	_startup_load_game_mode = mode
	_pending_load_game_new_game_payload = new_game_payload.duplicate(true)
	_startup_load_game_page = page
	startup.add_child(page)
	startup.set_process_unhandled_input(false)
	_connect_once(
		page,
		"intent_requested",
		Callable(self, "_on_startup_load_game_intent_requested"),
	)
	_connect_once(
		page,
		"action_blocked",
		Callable(self, "_on_startup_action_blocked"),
	)
	_last_result = {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"loadGameViewModel": view_model.duplicate(true),
	}


func _close_startup_load_game() -> void:
	if is_instance_valid(_startup_load_game_page):
		if _startup_load_game_page.has_method("deactivate_modal_ownership"):
			_startup_load_game_page.call("deactivate_modal_ownership")
		else:
			_startup_load_game_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_startup_load_game_page.hide()
		UI_NODE_RETIREMENT.retire(_startup_load_game_page)
	_startup_load_game_page = null
	_startup_load_game_mode = ""
	_pending_load_game_new_game_payload.clear()
	var startup := get_tree().current_scene as Control
	if startup != null and startup.name == "StartupScreen":
		startup.set_process_unhandled_input(true)
		_refresh_startup_main_menu_view_models()
		var load_game := startup.get_node_or_null("LoadGameButton") as Button
		if load_game != null and not load_game.disabled:
			load_game.call_deferred("grab_focus")


func _on_startup_load_game_intent_requested(
	intent: StringName,
	payload: Dictionary,
) -> void:
	match String(intent):
		"startup.close_load_game":
			_close_startup_load_game()
		"session.continue_slot":
			_on_startup_intent_requested(intent, payload)
		"save.request_delete_slot":
			if _startup_load_game_mode != "load":
				_last_result = _failure(
					"STARTUP_DELETE_SLOT_SELECTION_NOT_AUTHORIZED",
					false,
				)
				return
			var delete_slot_id := String(payload.get("slotId", "")).strip_edges()
			var delete_catalog := _startup_catalog_snapshot()
			var delete_slot := _startup_slot_by_id(delete_catalog, delete_slot_id)
			if delete_slot.is_empty() or String(
				delete_slot.get("state", "empty"),
			) == "empty":
				_last_result = _failure("STARTUP_DELETE_SLOT_EMPTY", false)
				return
			var delete_discovery := _startup_delete_discovery(delete_slot)
			_close_startup_load_game()
			_open_save_handling("delete_save", {}, delete_discovery)
		"startup.select_overwrite_slot":
			if _startup_load_game_mode != "overwrite_selection":
				_last_result = _failure(
					"STARTUP_OVERWRITE_SLOT_SELECTION_NOT_AUTHORIZED",
					false,
				)
				return
			var slot_id := String(payload.get("slotId", "")).strip_edges()
			var catalog := _startup_catalog_snapshot()
			var selected_slot := _startup_slot_by_id(catalog, slot_id)
			if selected_slot.is_empty() or String(
				selected_slot.get("state", "empty"),
			) == "empty":
				_last_result = _failure("STARTUP_OVERWRITE_SLOT_EMPTY", false)
				return
			if not bool(selected_slot.get("continueAvailable", false)):
				var reason := String(
					selected_slot.get(
						"errorCode",
						"STARTUP_OVERWRITE_SLOT_CONFIRMATION_UNAVAILABLE",
					),
				)
				if reason.is_empty():
					reason = "STARTUP_OVERWRITE_SLOT_CONFIRMATION_UNAVAILABLE"
				_last_result = _failure(reason, false)
				if is_instance_valid(_startup_load_game_page):
					_startup_load_game_page.call("_block", intent, reason)
				return
			var route_payload := (
				_pending_load_game_new_game_payload.duplicate(true)
			)
			route_payload["slotId"] = slot_id
			_close_startup_load_game()
			_on_startup_intent_requested(&"session.new_game", route_payload)
		_:
			_last_result = _failure("STARTUP_LOAD_GAME_INTENT_UNSUPPORTED", false)


func _open_new_game_overwrite(
	new_game_payload: Dictionary,
	discovery: Dictionary,
) -> void:
	_open_save_handling(
		"new_game_overwrite",
		new_game_payload,
		discovery,
	)


func _open_continue_recovery(
	discovery: Dictionary,
	route_origin := "continue",
) -> void:
	_open_save_handling(
		"continue_recovery",
		{},
		discovery,
		route_origin,
	)


func _open_save_handling(
	mode: String,
	new_game_payload: Dictionary,
	discovery: Dictionary,
	route_origin := "",
) -> void:
	_close_new_game_overwrite()
	var startup := get_tree().current_scene as Control
	if startup == null or startup.name != "StartupScreen":
		_record_route_open_failure(
			"STARTUP_OVERWRITE_HOST_UNAVAILABLE",
			"存档确认页面暂时打不开，请稍后再试。",
		)
		return
	var page := _instantiate_control_scene(NEW_GAME_OVERWRITE_SCENE_PATH)
	if page == null:
		_record_route_open_failure(
			"STARTUP_OVERWRITE_ROUTE_FAILED",
			"存档确认页面暂时打不开，请稍后再试。",
		)
		return
	page.name = "SaveHandlingRoute"
	page.process_mode = Node.PROCESS_MODE_ALWAYS
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.z_index = 2100
	var view_model := (
		_build_continue_recovery_view_model(discovery)
		if mode == "continue_recovery"
		else _build_delete_save_view_model(discovery)
		if mode == "delete_save"
		else _build_new_game_overwrite_view_model(discovery)
	)
	if not bool(page.call("apply_view_model", view_model)):
		page.free()
		_record_route_open_failure(
			"STARTUP_OVERWRITE_VIEW_MODEL_INVALID",
			"存档确认页面暂时打不开，请稍后再试。",
		)
		return
	_pending_new_game_payload = new_game_payload.duplicate(true)
	_pending_new_game_discovery = discovery.duplicate(true)
	_pending_save_handling_mode = mode
	_pending_save_handling_origin = route_origin.strip_edges()
	_startup_overwrite_page = page
	startup.add_child(page)
	startup.set_process_unhandled_input(false)
	_connect_once(
		page,
		"intent_requested",
		Callable(self, "_on_new_game_overwrite_intent_requested"),
	)


func _close_new_game_overwrite() -> void:
	if is_instance_valid(_startup_overwrite_page):
		if _startup_overwrite_page.has_method("deactivate_modal_ownership"):
			_startup_overwrite_page.call("deactivate_modal_ownership")
		else:
			_startup_overwrite_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_startup_overwrite_page.hide()
		_startup_overwrite_page.queue_free()
	_startup_overwrite_page = null
	_pending_new_game_payload.clear()
	_pending_new_game_discovery.clear()
	_pending_save_handling_mode = ""
	_pending_save_handling_origin = ""
	var startup := get_tree().current_scene as Control
	if startup != null and startup.name == "StartupScreen":
		startup.set_process_unhandled_input(true)


func _on_new_game_overwrite_intent_requested(
	intent: StringName,
	_payload: Dictionary,
) -> void:
	match String(intent):
		"session.cancel_new_game_overwrite", "session.cancel_continue_recovery":
			_close_new_game_overwrite()
		"save.cancel_delete_slot":
			_close_new_game_overwrite()
			_open_startup_load_game("load")
		"session.retry_restore", "session.confirm_recovery":
			var recovery_mode := _pending_save_handling_mode
			var route_origin := _pending_save_handling_origin
			var summary := (
				_pending_new_game_discovery.get("summary", {}) as Dictionary
			).duplicate(true)
			_close_new_game_overwrite()
			_flow_generation += 1
			call_deferred(
				"_start_formal_continue",
				_flow_generation,
				String(summary.get("slotId", "")),
				recovery_mode == "continue_recovery",
				route_origin,
			)
		"session.overwrite_for_new_game":
			_confirm_new_game_overwrite()
		"save.confirm_delete_slot":
			_confirm_delete_save()
		_:
			_last_result = _failure("SESSION_OVERWRITE_INTENT_UNSUPPORTED", false)


func _confirm_new_game_overwrite() -> void:
	if not is_instance_valid(_startup_overwrite_page):
		_last_result = _failure("STARTUP_OVERWRITE_HOST_UNAVAILABLE", false)
		return
	var expected_summary := (
		_pending_new_game_discovery.get("summary", {}) as Dictionary
	)
	var latest := _discover_startup_slot(
		String(expected_summary.get("slotId", "")),
	)
	if not bool(latest.get("ok", false)):
		_apply_new_game_overwrite_failure(latest, _pending_new_game_discovery)
		return
	var latest_summary := latest.get("summary", {}) as Dictionary
	if not _same_formal_save(expected_summary, latest_summary):
		_pending_new_game_discovery = latest.duplicate(true)
		_apply_new_game_overwrite_failure(
			_failure("FORMAL_SLOT_ARCHIVE_SAVE_CHANGED", false),
			latest,
		)
		return
	var route_payload := _pending_new_game_payload.duplicate(true)
	route_payload["overwriteConfirmed"] = true
	route_payload["overwriteExpectedSave"] = {
		"slotId": String(latest_summary.get("slotId", FORMAL_SLOT_ID)),
		"sessionId": String(latest_summary.get("sessionId", "")),
		"saveRevision": int(latest_summary.get("saveRevision", -1)),
	}
	_close_new_game_overwrite()
	_on_startup_intent_requested(&"session.new_game", route_payload)


func _confirm_delete_save() -> void:
	if (
		not is_instance_valid(_startup_overwrite_page)
		or _pending_save_handling_mode != "delete_save"
	):
		_last_result = _failure("STARTUP_DELETE_HOST_UNAVAILABLE", false)
		return
	var expected := (
		_pending_new_game_discovery.get("deleteEvidence", {}) as Dictionary
	)
	var slot_id := String(expected.get("slotId", "")).strip_edges()
	var catalog := _startup_catalog_snapshot()
	if not bool(catalog.get("ok", false)):
		_apply_delete_save_failure(catalog, _pending_new_game_discovery)
		return
	var latest_slot := _startup_slot_by_id(catalog, slot_id)
	if latest_slot.is_empty() or not _same_delete_evidence(expected, latest_slot):
		_apply_delete_save_failure(
			_failure("FORMAL_SLOT_DELETE_SAVE_CHANGED", false),
			_pending_new_game_discovery,
		)
		return
	var latest_summary := latest_slot.get("summary", {}) as Dictionary
	var service: RefCounted = (
		_delete_archive_service_override
		if _delete_archive_service_override != null
		else FORMAL_SLOT_ARCHIVER.new()
	)
	var result := service.call("archive_for_player_delete", {
		"slotId": slot_id,
		"sessionId": String(latest_summary.get("sessionId", "")),
		"saveRevision": int(latest_summary.get("saveRevision", 0)),
		"expectedState": String(latest_slot.get("state", "unknown")),
	}) as Dictionary
	if not bool(result.get("ok", false)):
		_apply_delete_save_failure(result, _pending_new_game_discovery)
		return
	var completed := result.duplicate(true)
	var slot_ids: Array[String] = []
	for definition_value: Variant in FORMAL_SLOT_DEFINITIONS:
		var definition := definition_value as Dictionary
		slot_ids.append(String(definition.get("slotId", "")))
	var profile_cleared := _startup_save_catalog.call(
		"clear_slot_profile",
		slot_id,
		slot_ids,
	) as Dictionary
	_close_new_game_overwrite()
	_refresh_startup_main_menu_view_models()
	_open_startup_load_game("load")
	_last_result = {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"deletedSlotId": slot_id,
		"archivePath": String(completed.get("archivePath", "")),
		"profileReceiptCleared": bool(profile_cleared.get("ok", false)),
	}


func _same_delete_evidence(expected: Dictionary, latest_slot: Dictionary) -> bool:
	var latest_summary := latest_slot.get("summary", {}) as Dictionary
	return (
		String(expected.get("slotId", ""))
		== String(latest_slot.get("slotId", ""))
		and String(expected.get("state", ""))
		== String(latest_slot.get("state", ""))
		and String(expected.get("recoveryState", ""))
		== String(latest_slot.get("recoveryState", ""))
		and String(expected.get("sessionId", ""))
		== String(latest_summary.get("sessionId", ""))
		and int(expected.get("saveRevision", 0))
		== int(latest_summary.get("saveRevision", 0))
	)


func _apply_delete_save_failure(
	result: Dictionary,
	discovery: Dictionary,
) -> void:
	if not is_instance_valid(_startup_overwrite_page):
		return
	_flow_generation += 1
	var view_model := _build_delete_save_view_model(discovery)
	var retryable := bool(result.get("retryable", false))
	view_model["revision"] = maxi(_flow_generation, 1)
	view_model["operation"] = {
		"requestId": "delete-%d" % Time.get_ticks_msec(),
		"intent": "save.confirm_delete_slot",
		"status": "error" if retryable else "rejected",
		"submittedAtMsec": Time.get_ticks_msec(),
		"completedAtMsec": Time.get_ticks_msec(),
	}
	view_model["error"] = {
		"kind": "transport" if retryable else "rejected",
		"code": String(result.get("errorCode", "FORMAL_SLOT_DELETE_FAILED")),
		"retryable": retryable,
		"message": (
			"存档删除暂时失败；原存档仍然完整保留。"
			if retryable
			else "存档情况已经变化，本次删除没有执行。"
		),
		"details": [],
	}
	_startup_overwrite_page.call("apply_view_model", view_model)


func _same_formal_save(left: Dictionary, right: Dictionary) -> bool:
	return (
		String(left.get("slotId", "")) == String(right.get("slotId", ""))
		and String(left.get("sessionId", "")) == String(right.get("sessionId", ""))
		and int(left.get("saveRevision", -1)) == int(right.get("saveRevision", -1))
	)


func _apply_new_game_overwrite_failure(
	result: Dictionary,
	discovery: Dictionary,
) -> void:
	if not is_instance_valid(_startup_overwrite_page):
		return
	_flow_generation += 1
	var view_model := _build_new_game_overwrite_view_model(discovery)
	var retryable := bool(result.get("retryable", false))
	view_model["operation"] = {
		"requestId": "overwrite-%d" % Time.get_ticks_msec(),
		"intent": "session.overwrite_for_new_game",
		"status": "error" if retryable else "rejected",
		"submittedAtMsec": Time.get_ticks_msec(),
		"completedAtMsec": Time.get_ticks_msec(),
	}
	view_model["error"] = {
		"kind": "transport" if retryable else "rejected",
		"code": String(result.get("errorCode", "FORMAL_SLOT_ARCHIVE_FAILED")),
		"retryable": retryable,
		"message": (
			"存档归档暂时失败；原存档仍然保留。"
			if retryable
			else "存档已经变化或不完整，本次覆盖没有执行。"
		),
		"details": [],
	}
	_startup_overwrite_page.call("apply_view_model", view_model)


func _build_new_game_overwrite_view_model(discovery: Dictionary) -> Dictionary:
	return CONFIRMATION_PAGE_BUILDER.new_game_overwrite(
		discovery,
		_flow_generation,
		FORMAL_SLOT_ID,
	)


func _build_delete_save_view_model(discovery: Dictionary) -> Dictionary:
	return CONFIRMATION_PAGE_BUILDER.delete_save(
		discovery,
		_flow_generation,
		FORMAL_SLOT_ID,
	)


func _build_continue_recovery_view_model(discovery: Dictionary) -> Dictionary:
	return CONFIRMATION_PAGE_BUILDER.continue_recovery(
		discovery,
		_flow_generation,
		FORMAL_SLOT_ID,
	)


func _close_startup_settings() -> void:
	if not is_instance_valid(_startup_settings_page):
		_startup_settings_page = null
		return
	var startup := get_tree().current_scene as Control
	if _startup_settings_page.has_method("unbind_town_ui_adapter"):
		_startup_settings_page.call("unbind_town_ui_adapter")
	_startup_settings_page.queue_free()
	_startup_settings_page = null
	if startup != null and startup.name == "StartupScreen":
		startup.set_process_unhandled_input(true)
		if startup.has_method("apply_view_models"):
			var startup_view_models := _build_startup_view_models()
			startup.call(
				"apply_view_models",
				startup_view_models.get("session", {}) as Dictionary,
				startup_view_models.get("save", {}) as Dictionary,
			)
			var new_game := startup.get_node_or_null("NewGameButton") as Button
			if new_game != null and not new_game.disabled:
				new_game.call_deferred("grab_focus")


func _refresh_startup_main_menu_view_models() -> void:
	var startup := get_tree().current_scene
	if (
		startup == null
		or startup.name != "StartupScreen"
		or not startup.has_method("apply_view_models")
	):
		return
	var startup_view_models := _build_startup_view_models()
	startup.call(
		"apply_view_models",
		startup_view_models.get("session", {}) as Dictionary,
		startup_view_models.get("save", {}) as Dictionary,
	)


func _on_startup_settings_intent_requested(
	intent: StringName,
	_payload: Dictionary,
) -> void:
	if String(intent) in [
		"provider_settings.back",
		"audio_display_settings.back",
	]:
		_close_startup_settings()


func _startup_new_game_payload_is_authorized(payload: Dictionary) -> bool:
	if _internal_playtest_enabled():
		return (
			String(payload.get("source", "")) == "placeholder"
			and String(payload.get("capabilityMode", "")) == "development"
			and String(payload.get("validationMode", "")) == "development"
			and not bool(payload.get("formalReady", true))
			and bool(payload.get("internalPlaytest", false))
		)
	if bool(payload.get("internalLivePlaytest", false)):
		return (
			String(payload.get("source", "")) == "runtime"
			and String(payload.get("capabilityMode", "")) == "formal"
			and String(payload.get("validationMode", "")) in ["development", "formal"]
			and not bool(payload.get("formalReady", true))
		)
	return (
		String(payload.get("source", "")) == "formal"
		and String(payload.get("capabilityMode", "")) == "formal"
		and bool(payload.get("formalReady", false))
	)


func _bind_world_intro(screen: Control) -> void:
	_world_intro = screen
	_connect_once(screen, "intent_requested", Callable(self, "_on_world_intro_intent_requested"))
	_connect_once(
		screen,
		"step_switch_confirmed",
		Callable(self, "_on_world_intro_step_switch_confirmed"),
	)
	if _world_intro_vm.is_empty():
		_world_intro_vm = _build_world_intro_view_model(0, maxi(_flow_generation, 1))
	_apply_world_intro_view_model()


func _enter_world_intro(generation: int) -> void:
	if generation != _flow_generation:
		return
	var intro := _instantiate_control_scene(WORLD_INTRO_SCENE_PATH)
	if intro == null:
		var route_failure := _record_route_open_failure(
			"GAME_FLOW_WORLD_INTRO_ROUTE_FAILED",
			"世界介绍页面暂时打不开，请稍后再试。",
			false,
		)
		_publish_startup_action_failure(
			&"session.new_game",
			route_failure,
		)
		return
	if _world_intro_vm.is_empty():
		_world_intro_vm = _build_world_intro_view_model(
			0,
			maxi(_flow_generation, 1),
		)
	if (
		not intro.has_method("apply_view_model")
		or not bool(intro.call(
			"apply_view_model",
			_world_intro_vm.duplicate(true),
		))
	):
		intro.free()
		var view_model_failure := _record_route_open_failure(
			"WORLD_INTRO_VIEW_MODEL_REJECTED",
			"世界介绍页面暂时打不开，请稍后再试。",
			false,
		)
		_publish_startup_action_failure(
			&"session.new_game",
			view_model_failure,
		)
		return
	var old_scene := get_tree().current_scene
	get_tree().root.add_child(intro)
	get_tree().current_scene = intro
	if old_scene != null and old_scene != intro:
		old_scene.queue_free()
	_bound_scene_id = 0
	_bind_current_scene.call_deferred()


func _on_world_intro_intent_requested(
	intent: StringName,
	payload: Dictionary,
	revision: int,
) -> void:
	if revision != int(_world_intro_vm.get("revision", 0)):
		return
	if String(intent) == "world_intro.back" and _world_intro_navigation_pending:
		return
	if (
		String(payload.get("scope", "")) != "world_intro"
		or String(payload.get("introId", "")) != "town_basics"
	):
		_last_result = _failure("WORLD_INTRO_INTENT_INVALID", false)
		return
	match String(intent):
		"world_intro.back":
			_world_intro_navigation_pending = true
			var startup_scene := load(STARTUP_SCENE_PATH) as PackedScene
			if startup_scene == null:
				_world_intro_navigation_pending = false
				_record_route_open_failure(
					"GAME_FLOW_STARTUP_ROUTE_FAILED",
					"启动页面暂时打不开，请稍后再试。",
				)
				return
			var route_error := get_tree().change_scene_to_packed(startup_scene)
			if route_error != OK:
				_world_intro_navigation_pending = false
				_present_route_failure_result(
					_failure("GAME_FLOW_STARTUP_ROUTE_FAILED", false, [{
						"godotError": route_error,
					}]),
					"启动页面暂时打不开，请稍后再试。",
				)
				return
			_flow_generation += 1
			_world_intro_vm.clear()
			_new_game_route_context.clear()
		"world_intro.previous":
			_set_world_intro_page(
				int((_world_intro_vm.get("data", {}) as Dictionary).get("currentPageIndex", 0)) - 1
			)
		"world_intro.continue":
			var page_index := int(
				(_world_intro_vm.get("data", {}) as Dictionary).get("currentPageIndex", 0)
			)
			if page_index + 1 < WORLD_INTRO_PAGES.size():
				_set_world_intro_page(page_index + 1)
			else:
				_commit_world_intro_route(intent)
		"world_intro.complete", "world_intro.skip":
			_commit_world_intro_route(intent)
		_:
			_last_result = _failure("WORLD_INTRO_INTENT_UNSUPPORTED", false)


func _on_world_intro_step_switch_confirmed(
	target_step: StringName,
	revision: int,
) -> void:
	if (
		target_step != &"resident_roster"
		or revision != int(_world_intro_vm.get("revision", 0))
		or String(
			((_world_intro_vm.get("operation", {}) as Dictionary).get("status", ""))
		) != "success"
	):
		return
	_flow_generation += 1
	call_deferred("_enter_resident_selection", _flow_generation)


func _enter_resident_selection(generation: int) -> void:
	if generation != _flow_generation:
		return
	var packed := load(RESIDENT_SELECTION_SCENE_PATH) as PackedScene
	var selection := packed.instantiate() as Control if packed != null else null
	if selection == null:
		_record_route_open_failure(
			"GAME_FLOW_RESIDENT_SELECTION_ROUTE_FAILED",
			"居民选择页面暂时打不开，请稍后再试。",
		)
		return
	if _resident_selection_vm.is_empty():
		_resident_selection_vm = (
			_build_internal_resident_selection_view_model()
			if _internal_playtest_enabled()
			else _build_formal_resident_selection_view_model()
		)
	if (
		_resident_selection_vm.is_empty()
		or not bool(selection.call(
			"apply_view_model",
			_resident_selection_vm.duplicate(true),
		))
	):
		selection.free()
		_record_route_open_failure(
			"RESIDENT_SELECTION_VIEW_MODEL_INVALID",
			"居民选择页面暂时打不开，请稍后再试。",
		)
		return
	var old_scene := get_tree().current_scene
	get_tree().root.add_child(selection)
	get_tree().current_scene = selection
	if old_scene != null and old_scene != selection:
		old_scene.queue_free()
	_bound_scene_id = 0
	_bind_current_scene.call_deferred()


func _set_world_intro_page(page_index: int) -> void:
	var bounded_index := clampi(page_index, 0, WORLD_INTRO_PAGES.size() - 1)
	var next_revision := int(_world_intro_vm.get("revision", 0)) + 1
	_world_intro_vm = _build_world_intro_view_model(bounded_index, next_revision)
	_apply_world_intro_view_model()


func _commit_world_intro_route(intent: StringName) -> void:
	var data := (_world_intro_vm.get("data", {}) as Dictionary).duplicate(true)
	data["currentPageIndex"] = clampi(
		int(data.get("currentPageIndex", 0)),
		0,
		WORLD_INTRO_PAGES.size() - 1,
	)
	data["transition"] = {
		"phase": "switching_to_resident_roster",
		"reduceMotion": false,
		"targetRoute": "resident_selection",
		"routeCommitted": true,
	}
	var now := Time.get_ticks_msec()
	_world_intro_vm = {
		"scope": "world_intro",
		"status": "ready",
		"revision": int(_world_intro_vm.get("revision", 0)) + 1,
		"data": data,
		"actions": _world_intro_actions(
			int(data.get("currentPageIndex", 0)), true
		),
		"operation": {
			"requestId": "world-intro-%d-%d" % [_flow_generation, now],
			"intent": String(intent),
			"status": "success",
			"submittedAtMsec": now,
			"completedAtMsec": now,
		},
		"error": null,
	}
	_apply_world_intro_view_model()


func _build_world_intro_view_model(page_index: int, revision: int) -> Dictionary:
	var internal_playtest := _internal_playtest_enabled()
	var source := String(
		_new_game_route_context.get(
			"source", "placeholder" if internal_playtest else "formal"
		)
	)
	var capability_mode := String(
		_new_game_route_context.get(
			"capabilityMode", "development" if internal_playtest else "formal"
		)
	)
	var formal_ready := bool(_new_game_route_context.get("formalReady", false))
	var bounded_index := clampi(page_index, 0, WORLD_INTRO_PAGES.size() - 1)
	return {
		"scope": "world_intro",
		"status": "ready",
		"revision": maxi(revision, 1),
		"data": {
			"capabilityMode": capability_mode,
			"source": source,
			"formalReady": formal_ready,
			"introId": "town_basics",
			"flowMode": "new_game",
			"currentPageIndex": bounded_index,
			"pageCount": WORLD_INTRO_PAGES.size(),
			"pages": WORLD_INTRO_PAGES.duplicate(true),
			"transition": {
				"phase": "reading",
				"reduceMotion": false,
				"targetRoute": "resident_selection",
				"routeCommitted": false,
			},
		},
		"actions": _world_intro_actions(bounded_index, false),
		"operation": _idle_operation(),
		"error": null,
	}


func _world_intro_actions(page_index: int, route_committed: bool) -> Dictionary:
	var at_first_page := page_index <= 0
	var at_last_page := page_index + 1 >= WORLD_INTRO_PAGES.size()
	return {
		"back": {
			"intent": "world_intro.back",
			"enabled": not route_committed,
			"disabledReason": "ROUTE_COMMITTED" if route_committed else "",
		},
		"previous": {
			"intent": "world_intro.previous",
			"enabled": not route_committed and not at_first_page,
			"disabledReason": (
				"ROUTE_COMMITTED" if route_committed else "FIRST_PAGE" if at_first_page else ""
			),
		},
		"continue": {
			"intent": "world_intro.complete" if at_last_page else "world_intro.continue",
			"enabled": not route_committed,
			"disabledReason": "ROUTE_COMMITTED" if route_committed else "",
		},
		"skip": {
			"intent": "world_intro.skip",
			"enabled": not route_committed,
			"disabledReason": "ROUTE_COMMITTED" if route_committed else "",
		},
		"retry": {
			"intent": "world_intro.retry",
			"enabled": false,
			"disabledReason": "NO_RETRYABLE_ERROR",
		},
	}


func _apply_world_intro_view_model() -> void:
	if (
		_world_intro == null
		or _world_intro_vm.is_empty()
		or not _world_intro.has_method("apply_view_model")
	):
		return
	if not bool(_world_intro.call("apply_view_model", _world_intro_vm.duplicate(true))):
		_present_route_failure_result(
			_failure("WORLD_INTRO_VIEW_MODEL_REJECTED", false),
			"世界介绍页面暂时打不开，请稍后再试。",
		)


func _bind_resident_selection(screen: Control) -> void:
	_resident_selection = screen
	_connect_once(screen, "resident_selection_requested", Callable(self, "_on_resident_selection_requested"))
	_connect_once(screen, "recommended_selection_requested", Callable(self, "_on_recommended_selection_requested"))
	_connect_once(screen, "selection_clear_requested", Callable(self, "_on_selection_clear_requested"))
	_connect_once(screen, "roster_confirmation_requested", Callable(self, "_on_roster_confirmation_requested"))
	_connect_once(screen, "custom_resident_requested", Callable(self, "_on_custom_resident_requested"))
	_connect_once(
		screen,
		"custom_resident_delete_requested",
		Callable(self, "_on_custom_resident_delete_requested"),
	)
	_connect_once(
		screen,
		"residents_delete_requested",
		Callable(self, "_on_residents_delete_requested"),
	)
	_connect_once(screen, "back_requested", Callable(self, "_on_resident_selection_back_requested"))
	if _resident_selection_vm.is_empty():
		if _internal_playtest_enabled():
			_resident_selection_vm = _build_internal_resident_selection_view_model()
		else:
			_resident_selection_vm = _build_formal_resident_selection_view_model()
	_apply_custom_candidate_pool_projection({}, false)
	_apply_resident_selection_view_model()


func _on_custom_resident_requested(revision: int) -> void:
	if revision != int(_resident_selection_vm.get("revision", 0)):
		_record_route_open_failure(
			"CUSTOM_RESIDENT_CREATOR_ROUTE_REVISION_STALE",
			"新居民创建页面状态已更新，请重新点一次。",
			false,
		)
		return
	if not CUSTOM_RESIDENT_CREATOR_MOUNTING_AUTHORIZED:
		_record_route_open_failure(
			CUSTOM_RESIDENT_CREATOR_BLOCKED_REASON,
			"新居民创建页面暂时打不开，请稍后再试。",
			false,
		)
		return
	_open_custom_resident_creator()


func _on_custom_resident_delete_requested(
	resident_id: String,
	candidate_pool_revision: int,
	revision: int,
) -> void:
	if revision != int(_resident_selection_vm.get("revision", 0)):
		_set_resident_selection_delete_failure(
			_failure("CUSTOM_RESIDENT_DELETE_REVISION_STALE", false),
		)
		return
	if _custom_resident_candidate_pool == null:
		_set_resident_selection_delete_failure(
			_failure("CUSTOM_RESIDENT_CANDIDATE_POOL_NOT_CONFIGURED", false),
		)
		return
	if candidate_pool_revision != int(
		_custom_resident_candidate_pool.candidate_pool_revision(),
	):
		_set_resident_selection_delete_failure(
			_failure("CUSTOM_RESIDENT_CANDIDATE_POOL_REVISION_STALE", false),
		)
		return
	var data := _resident_selection_vm.get("data", {}) as Dictionary
	var residents := data.get("residents", []) as Array
	var deleted_index := -1
	for index in range(residents.size()):
		var resident := residents[index] as Dictionary
		if String(resident.get("resident_id", "")) != resident_id:
			continue
		if String(resident.get("source", "")) != "custom":
			_set_resident_selection_delete_failure(
				_failure("CUSTOM_RESIDENT_DELETE_PRESET_FORBIDDEN", false),
			)
			return
		deleted_index = index
		break
	if deleted_index < 0:
		_set_resident_selection_delete_failure(
			_failure("CUSTOM_RESIDENT_CANDIDATE_NOT_FOUND", false),
		)
		return
	# The legacy one-resident signal must use the same authorization, 15-person
	# floor, revision, selection cleanup, and persistence transaction as batch
	# deletion. This prevents an older UI surface from bypassing the formal gate.
	_on_residents_delete_requested(
		[resident_id],
		candidate_pool_revision,
		revision,
	)


func _on_residents_delete_requested(
	resident_ids: Array,
	candidate_pool_revision: int,
	revision: int,
) -> void:
	if revision != int(_resident_selection_vm.get("revision", 0)):
		_set_resident_selection_delete_failure(
			_failure("RESIDENT_DELETE_REVISION_STALE", false),
		)
		return
	var actions := _resident_selection_vm.get("actions", {}) as Dictionary
	var delete_action := actions.get("delete_residents", {}) as Dictionary
	if not bool(delete_action.get("enabled", false)):
		_set_resident_selection_delete_failure(
			_failure(
				String(delete_action.get(
					"disabled_reason",
					"RESIDENT_DELETE_NOT_AUTHORIZED",
				)),
				false,
			),
		)
		return
	var data := _resident_selection_vm.get("data", {}) as Dictionary
	var residents := data.get("residents", []) as Array
	var resident_by_id: Dictionary = {}
	for value: Variant in residents:
		if value is Dictionary:
			var resident := value as Dictionary
			resident_by_id[String(resident.get("resident_id", ""))] = resident
	var delete_ids: Array[String] = []
	var delete_set: Dictionary = {}
	for value: Variant in resident_ids:
		var resident_id := String(value).strip_edges()
		if resident_id.is_empty() or delete_set.has(resident_id):
			continue
		if not resident_by_id.has(resident_id):
			_set_resident_selection_delete_failure(
				_failure("RESIDENT_DELETE_CANDIDATE_NOT_FOUND", false),
			)
			return
		delete_set[resident_id] = true
		delete_ids.append(resident_id)
	if delete_ids.is_empty():
		_set_resident_selection_delete_failure(
			_failure("RESIDENT_DELETE_SELECTION_EMPTY", false),
		)
		return
	if residents.size() - delete_ids.size() < 15:
		_set_resident_selection_delete_failure(
			_failure("RESIDENT_DELETE_MINIMUM_CANDIDATES_REQUIRED", false),
		)
		return
	var custom_ids: Array[String] = []
	var preset_ids: Array[String] = []
	for resident_id: String in delete_ids:
		var source := String(
			(resident_by_id[resident_id] as Dictionary).get("source", "preset"),
		)
		if source == "custom":
			custom_ids.append(resident_id)
		else:
			preset_ids.append(resident_id)
	if not custom_ids.is_empty():
		if _custom_resident_candidate_pool == null:
			_set_resident_selection_delete_failure(
				_failure("CUSTOM_RESIDENT_CANDIDATE_POOL_NOT_CONFIGURED", false),
			)
			return
		var current_pool_revision := int(
			_custom_resident_candidate_pool.candidate_pool_revision(),
		)
		if candidate_pool_revision != current_pool_revision:
			_set_resident_selection_delete_failure(
				_failure(
					"CUSTOM_RESIDENT_CANDIDATE_POOL_REVISION_STALE",
					false,
				),
			)
			return
		var deleted := _custom_resident_candidate_pool.delete_candidates(custom_ids,
			current_pool_revision) as Dictionary
		if not bool(deleted.get("ok", false)):
			_set_resident_selection_delete_failure(deleted)
			return
		_apply_custom_candidate_pool_projection({}, false)
		data = _resident_selection_vm.get("data", {}) as Dictionary
		residents = data.get("residents", []) as Array
	var kept_residents: Array = []
	var kept_ids: Dictionary = {}
	for value: Variant in residents:
		if not value is Dictionary:
			continue
		var resident := value as Dictionary
		var resident_id := String(resident.get("resident_id", ""))
		if delete_set.has(resident_id):
			continue
		kept_residents.append(resident.duplicate(true))
		kept_ids[resident_id] = true
	data["residents"] = kept_residents
	var excluded := (data.get("excluded_resident_ids", []) as Array).duplicate()
	for resident_id: String in preset_ids:
		if not excluded.has(resident_id):
			excluded.append(resident_id)
	data["excluded_resident_ids"] = excluded
	var selected: Array = []
	for value: Variant in data.get("selected_resident_ids", []) as Array:
		if kept_ids.has(String(value)):
			selected.append(String(value))
	data["selected_resident_ids"] = selected
	var recommended: Array = []
	for value: Variant in data.get("recommended_resident_ids", []) as Array:
		var resident_id := String(value)
		if kept_ids.has(resident_id) and not recommended.has(resident_id):
			recommended.append(resident_id)
	for value: Variant in kept_residents:
		if recommended.size() >= 15:
			break
		var resident_id := String((value as Dictionary).get("resident_id", ""))
		if not resident_id.is_empty() and not recommended.has(resident_id):
			recommended.append(resident_id)
	data["recommended_resident_ids"] = recommended
	var focused_resident_id := String(data.get("focused_resident_id", ""))
	if not kept_ids.has(focused_resident_id):
		focused_resident_id = (
			String((kept_residents[0] as Dictionary).get("resident_id", ""))
			if not kept_residents.is_empty()
			else ""
		)
	data["focused_resident_id"] = focused_resident_id
	_update_confirmation_payload(data)
	_resident_selection_vm["operation"] = _idle_operation()
	_resident_selection_vm["error"] = null
	_advance_resident_selection_revision()
	_last_result = {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"deletedResidentIds": delete_ids,
		"excludedPresetResidentIds": preset_ids,
		"candidatePoolRevision": int(data.get("candidate_pool_revision", 0)),
		"remainingCandidateCount": kept_residents.size(),
	}


func _open_custom_resident_creator() -> void:
	if is_instance_valid(_custom_resident_creator_page):
		return
	var selection := get_tree().current_scene as Control
	if selection == null or selection != _resident_selection:
		_record_route_open_failure(
			"CUSTOM_RESIDENT_CREATOR_ROUTE_HOST_UNAVAILABLE",
			"新居民创建页面暂时打不开，请稍后再试。",
			false,
		)
		return
	var pool_result := _ensure_custom_resident_candidate_pool()
	if not bool(pool_result.get("ok", false)):
		_present_route_failure_result(
			pool_result,
			"新居民创建页面暂时打不开，请稍后再试。",
		)
		return
	var base_catalog := FORMAL_CATALOG.load_catalog() as Dictionary
	var world_data := _read_json(WORLD_DATA_PATH)
	var service_script := load(CUSTOM_RESIDENT_CREATOR_SERVICE_PATH) as Script
	if service_script == null:
		_record_route_open_failure(
			"CUSTOM_RESIDENT_CREATOR_SERVICE_UNAVAILABLE",
			"新居民创建页面暂时打不开，请稍后再试。",
		)
		return
	_custom_resident_creator_service = service_script.new()
	var configured := _custom_resident_creator_service.call(
		"configure",
		_custom_resident_candidate_pool,
		base_catalog,
		world_data,
		{
			"draftId": "custom-resident-%d-%d" % [
				_flow_generation,
				Time.get_ticks_msec(),
			],
			"revision": maxi(int(_resident_selection_vm.get("revision", 1)), 1),
		},
	) as Dictionary
	if not bool(configured.get("ok", false)):
		_custom_resident_creator_service = null
		_present_route_failure_result(
			configured,
			"新居民创建页面暂时打不开，请稍后再试。",
		)
		return
	var bound := _startup_ui_adapter.call(
		"bind_custom_resident_creator_service",
		_custom_resident_creator_service,
	) as Dictionary
	if not bool(bound.get("ok", false)):
		_custom_resident_creator_service = null
		_present_route_failure_result(
			bound,
			"新居民创建页面暂时打不开，请稍后再试。",
		)
		return
	var page_scene := load(CUSTOM_RESIDENT_CREATOR_SCENE_PATH) as PackedScene
	var page: Control = null
	if page_scene != null:
		page = page_scene.instantiate() as Control
	if page == null:
		_startup_ui_adapter.call("bind_custom_resident_creator_service", null)
		_custom_resident_creator_service = null
		_record_route_open_failure(
			"CUSTOM_RESIDENT_CREATOR_ROUTE_FAILED",
			"新居民创建页面暂时打不开，请稍后再试。",
		)
		return
	page.name = "CustomResidentCreatorRoute"
	page.process_mode = Node.PROCESS_MODE_ALWAYS
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.z_index = 2250
	page.set("navigation_back_available", true)
	page.call("bind_town_ui_adapter", _startup_ui_adapter)
	_connect_once(
		page,
		"intent_requested",
		Callable(self, "_on_custom_resident_creator_intent_requested"),
	)
	_connect_once(
		page,
		"action_blocked",
		Callable(self, "_on_custom_resident_creator_action_blocked"),
	)
	_custom_resident_creator_page = page
	selection.set_process_unhandled_input(false)
	selection.add_child(page)
	if page.has_method("focus_default_control"):
		page.call_deferred("focus_default_control")
	call_deferred("_apply_custom_resident_creator_route_affordances")


func _ensure_custom_resident_candidate_pool() -> Dictionary:
	if _custom_resident_candidate_pool != null:
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"candidatePoolRevision": int(
				_custom_resident_candidate_pool.candidate_pool_revision(),
			),
		}
	if _custom_resident_library == null:
		var library_path := _custom_resident_library_path()
		if library_path.is_empty():
			return _failure("CUSTOM_RESIDENT_LIBRARY_PATH_INVALID", false)
		_custom_resident_library = CUSTOM_RESIDENT_LIBRARY.new()
		var library_configured := _custom_resident_library.configure(library_path) as Dictionary
		if not bool(library_configured.get("ok", false)):
			_custom_resident_library = null
			return library_configured
	var library := _custom_resident_library.load_library() as Dictionary
	if not bool(library.get("ok", false)):
		return library
	var base_catalog := FORMAL_CATALOG.load_catalog() as Dictionary
	_custom_resident_candidate_pool = CUSTOM_RESIDENT_CANDIDATE_POOL.new()
	var configured := _custom_resident_candidate_pool.configure(base_catalog,
		{
			"candidatePoolRevision": int(library.get("libraryRevision", 1)),
			"customCandidates": (
				library.get("candidates", []) as Array
			).duplicate(true),
			"persistence": _custom_resident_library,
		}) as Dictionary
	if not bool(configured.get("ok", false)):
		_custom_resident_candidate_pool = null
	return configured


func _custom_resident_library_path() -> String:
	var override := OS.get_environment(
		CUSTOM_RESIDENT_LIBRARY_PATH_ENV,
	).strip_edges()
	if override.is_empty():
		return String(CUSTOM_RESIDENT_LIBRARY.DEFAULT_PATH)
	if (
		override.begins_with("%s/" % String(CUSTOM_RESIDENT_LIBRARY.TEST_ROOT))
		and not override.contains("..")
		and override.ends_with(".json")
	):
		return override
	return ""


func _on_custom_resident_creator_intent_requested(
	intent: String,
	payload: Dictionary,
) -> void:
	if intent not in [
		"custom_resident_creator.cancel",
		"custom_resident_creator.open_wardrobe",
		"custom_resident_creator.apply_wardrobe_result",
		"custom_resident_creator.create",
	]:
		return
	var route_only := bool(payload.get("routeOnly", false))
	var dispatch_result := payload.get("dispatchResult", {}) as Dictionary
	if not route_only and not bool(dispatch_result.get("ok", false)):
		_last_result = dispatch_result.duplicate(true)
		return
	if intent == "custom_resident_creator.cancel":
		call_deferred("_close_custom_resident_creator", true)
		return
	if intent == "custom_resident_creator.open_wardrobe":
		var handoff := dispatch_result.get("wardrobeHandoff", {}) as Dictionary
		if (
			handoff.is_empty()
			or not is_instance_valid(_custom_resident_creator_page)
			or not _custom_resident_creator_page.has_method(
				"open_complete_set_wardrobe",
			)
			or not bool(_custom_resident_creator_page.call(
				"open_complete_set_wardrobe",
				handoff.duplicate(true),
			))
		):
			_last_result = _failure(
				"CUSTOM_RESIDENT_WARDROBE_ROUTE_UNAVAILABLE",
				false,
			)
		return
	if intent == "custom_resident_creator.apply_wardrobe_result":
		return
	var handoff := dispatch_result.get("selectionHandoff", {}) as Dictionary
	if handoff.is_empty():
		_last_result = _failure("CUSTOM_RESIDENT_SELECTION_HANDOFF_MISSING", false)
		return
	call_deferred(
		"_complete_custom_resident_creation",
		handoff.duplicate(true),
		_flow_generation,
	)


func _on_custom_resident_creator_action_blocked(
	_intent: String,
	reason: String,
) -> void:
	_last_result = _failure(reason, false)


func _apply_custom_resident_creator_route_affordances() -> void:
	if not is_instance_valid(_custom_resident_creator_page):
		return
	var wardrobe_action := (
		(_startup_ui_adapter.call(
			"get_view_model",
			"custom_resident_creator",
		) as Dictionary).get("actions", {}) as Dictionary
	).get("openWardrobe", {}) as Dictionary
	var wardrobe_button := _custom_resident_creator_page.find_child(
		"OpenWardrobeButton",
		true,
		false,
	) as Button
	if wardrobe_button == null:
		return
	if bool(wardrobe_action.get("enabled", false)):
		wardrobe_button.tooltip_text = "打开完整衣柜"
	else:
		wardrobe_button.tooltip_text = String(
			wardrobe_action.get(
				"disabledReason",
				"CUSTOM_RESIDENT_WARDROBE_ROUTE_UNAVAILABLE",
			),
		)


func _complete_custom_resident_creation(
	handoff: Dictionary,
	generation: int,
) -> void:
	if generation != _flow_generation or _custom_resident_candidate_pool == null:
		return
	if int(handoff.get("candidatePoolRevision", -1)) != int(
		_custom_resident_candidate_pool.candidate_pool_revision(),
	):
		_last_result = _failure("CUSTOM_RESIDENT_CANDIDATE_POOL_REVISION_STALE", false)
		return
	_apply_custom_candidate_pool_projection(handoff, true)
	var focused_resident_id := String(handoff.get("focusedResidentId", ""))
	if is_instance_valid(_custom_resident_creator_page):
		_custom_resident_creator_page.tree_exited.connect(
			Callable(
				self,
				"_restore_resident_selection_resident_focus",
			).bind(focused_resident_id),
			CONNECT_ONE_SHOT,
		)
	_close_custom_resident_creator(false)


func _apply_custom_candidate_pool_projection(
	handoff: Dictionary,
	advance_revision: bool,
) -> void:
	if _custom_resident_candidate_pool == null or _resident_selection_vm.is_empty():
		return
	var merged := _merge_custom_candidate_projection(_resident_selection_vm)
	if merged.is_empty():
		return
	_resident_selection_vm = merged
	var data := _resident_selection_vm.get("data", {}) as Dictionary
	var focused_id := String(handoff.get("focusedResidentId", ""))
	if not focused_id.is_empty():
		data["focused_resident_id"] = focused_id
	_update_confirmation_payload(data)
	if advance_revision:
		_advance_resident_selection_revision()


func _merge_custom_candidate_projection(view_model: Dictionary) -> Dictionary:
	if _custom_resident_candidate_pool == null or view_model.is_empty():
		return view_model
	var projection := _custom_resident_candidate_pool.get_resident_selection_projection() as Dictionary
	if not bool(projection.get("ok", false)):
		_last_result = projection.duplicate(true)
		return {}
	var data := view_model.get("data", {}) as Dictionary
	var catalog_entries: Array = []
	for value: Variant in data.get("resident_catalog", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("source", "preset")) != "custom":
			catalog_entries.append((value as Dictionary).duplicate(true))
	catalog_entries.append_array(
		(projection.get("catalogEntries", []) as Array).duplicate(true),
	)
	var selection_entries: Array = []
	for value: Variant in data.get("residents", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("source", "preset")) != "custom":
			selection_entries.append((value as Dictionary).duplicate(true))
	selection_entries.append_array(
		(projection.get("selectionEntries", []) as Array).duplicate(true),
	)
	data["resident_catalog"] = catalog_entries
	data["residents"] = selection_entries
	data["candidate_pool_revision"] = int(
		projection.get("candidatePoolRevision", 0),
	)
	return view_model


func _close_custom_resident_creator(restore_focus := true) -> bool:
	if not is_instance_valid(_custom_resident_creator_page):
		_custom_resident_creator_page = null
		return false
	var page := _custom_resident_creator_page
	_custom_resident_creator_page = null
	if page.has_method("unbind_town_ui_adapter"):
		page.call("unbind_town_ui_adapter")
	if restore_focus:
		page.tree_exited.connect(
			Callable(self, "_restore_resident_selection_focus"),
			CONNECT_ONE_SHOT,
		)
	page.queue_free()
	if _startup_ui_adapter != null:
		_startup_ui_adapter.call("bind_custom_resident_creator_service", null)
	_custom_resident_creator_service = null
	if is_instance_valid(_resident_selection):
		_resident_selection.set_process_unhandled_input(true)
	return true


func _reset_custom_resident_creator_session(clear_pool: bool) -> void:
	if is_instance_valid(_custom_resident_creator_page):
		_close_custom_resident_creator(false)
	elif _startup_ui_adapter != null:
		_startup_ui_adapter.call("bind_custom_resident_creator_service", null)
	_custom_resident_creator_service = null
	if clear_pool:
		_custom_resident_candidate_pool = null


func _reset_new_game_configuration_context() -> void:
	_reset_custom_resident_creator_session(true)
	_reset_resident_model_assignment_session()
	# A new save slot starts with a fresh roster/exclusion draft. The custom
	# resident pool is rebuilt from the retained global library when selection
	# opens, so reusable definitions survive without leaking prior save state.
	_resident_selection_vm.clear()


func _restore_resident_selection_focus() -> void:
	if not is_instance_valid(_resident_selection):
		return
	var custom_button := _resident_selection.find_child(
		"CustomResidentButton",
		true,
		false,
	) as Button
	if custom_button != null and not custom_button.disabled:
		custom_button.grab_focus()


func _restore_resident_selection_resident_focus(resident_id: String) -> void:
	if not is_instance_valid(_resident_selection) or resident_id.is_empty():
		return
	var data := _resident_selection_vm.get("data", {}) as Dictionary
	var residents := data.get("residents", []) as Array
	for index in residents.size():
		var resident := residents[index] as Dictionary
		if String(resident.get("resident_id", "")) != resident_id:
			continue
		var focus_button := _resident_selection.find_child(
			"ResidentCardFocus%02d" % index,
			true,
			false,
		) as Button
		if focus_button != null and not focus_button.disabled:
			focus_button.grab_focus()
		return


func _open_resident_model_assignment(draft: Dictionary) -> void:
	if is_instance_valid(_resident_model_assignment_page):
		return
	var selection := get_tree().current_scene as Control
	if selection == null or selection != _resident_selection:
		_record_route_open_failure(
			"RESIDENT_MODEL_ASSIGNMENT_ROUTE_HOST_UNAVAILABLE",
			"居民模型分配页面暂时打不开，请稍后再试。",
		)
		return
	var service_result := _configure_resident_model_assignment_service(draft)
	if not bool(service_result.get("ok", false)):
		var visible_result := service_result.duplicate(true)
		visible_result["playerMessage"] = "居民模型分配页面暂时打不开，请稍后再试。"
		_last_result = visible_result
		selection.call("_show_notice", visible_result["playerMessage"])
		return
	var page := _instantiate_control_scene(RESIDENT_MODEL_ASSIGNMENT_SCENE_PATH)
	if page == null:
		_record_route_open_failure(
			"RESIDENT_MODEL_ASSIGNMENT_ROUTE_FAILED",
			"居民模型分配页面暂时打不开，请稍后再试。",
		)
		return
	page.name = "ResidentModelAssignmentRoute"
	page.process_mode = Node.PROCESS_MODE_ALWAYS
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.z_index = 2300
	page.call("bind_town_ui_adapter", _startup_ui_adapter)
	_connect_once(
		page,
		"back_requested",
		Callable(self, "_on_resident_model_assignment_back_requested"),
	)
	_connect_once(
		page,
		"intent_requested",
		Callable(self, "_on_resident_model_assignment_intent_requested"),
	)
	_connect_once(
		page,
		"action_dispatch_started",
		Callable(self, "_on_resident_model_assignment_action_dispatch_started"),
	)
	_resident_model_assignment_page = page
	selection.set_process_unhandled_input(false)
	selection.add_child(page)


func _configure_resident_model_assignment_service(draft: Dictionary) -> Dictionary:
	_detach_resident_model_assignment_service()
	var catalog_result := _formal_new_game_catalog()
	if not bool(catalog_result.get("ok", false)):
		return catalog_result
	var assignment_draft := _merge_resident_model_assignment_draft(draft)
	var projected_catalog_result := _project_resident_model_assignment_catalog(
		catalog_result.get("catalog", {}) as Dictionary,
		assignment_draft,
	)
	if not bool(projected_catalog_result.get("ok", false)):
		return projected_catalog_result
	var catalog := projected_catalog_result.get("catalog", {}) as Dictionary
	_resident_model_assignment_service = RESIDENT_MODEL_ASSIGNMENT_SERVICE.new()
	_connect_once(
		_resident_model_assignment_service,
		"draft_applied",
		Callable(self, "_on_resident_model_assignment_draft_applied"),
	)
	_connect_once(
		_resident_model_assignment_service,
		"back_requested",
		Callable(self, "_on_resident_model_assignment_service_back_requested"),
	)
	var configured := _resident_model_assignment_service.configure(_startup_provider_service,
		catalog,
		assignment_draft,
		{
			"revision": maxi(int(_resident_selection_vm.get("revision", 1)), 1),
		}) as Dictionary
	if not bool(configured.get("ok", false)):
		_detach_resident_model_assignment_service()
		return configured
	var bound := _startup_ui_adapter.call(
		"bind_resident_model_assignment_service",
		_resident_model_assignment_service,
	) as Dictionary
	if not bool(bound.get("ok", false)):
		_detach_resident_model_assignment_service()
		return bound
	return configured


func _project_resident_model_assignment_catalog(
	catalog: Dictionary,
	draft: Dictionary,
) -> Dictionary:
	var residents_value: Variant = catalog.get("residents", [])
	if not residents_value is Array:
		return _failure("RESIDENT_MODEL_CATALOG_INVALID", false)
	var residents_by_id: Dictionary = {}
	for resident_value: Variant in residents_value as Array:
		if not resident_value is Dictionary:
			return _failure("RESIDENT_MODEL_CATALOG_INVALID", false)
		var resident := resident_value as Dictionary
		var resident_id := String(resident.get("residentId", "")).strip_edges()
		if resident_id.is_empty() or residents_by_id.has(resident_id):
			return _failure("RESIDENT_MODEL_CATALOG_RESIDENT_INVALID", false)
		residents_by_id[resident_id] = resident.duplicate(true)
	var slots_value: Variant = draft.get("slots", [])
	if not slots_value is Array:
		return _failure("SESSION_DRAFT_SLOTS_INVALID", false)
	var slots := slots_value as Array
	if slots.size() != RESIDENT_MODEL_ASSIGNMENT_SERVICE.SLOT_COUNT:
		return _failure("SESSION_HOME_SPACE_COUNT_MISMATCH", false)
	var selected_residents: Array[Dictionary] = []
	var selected_ids: Dictionary = {}
	for slot_value: Variant in slots:
		if not slot_value is Dictionary:
			return _failure("SESSION_DRAFT_SLOT_INVALID", false)
		var resident_id := String(
			(slot_value as Dictionary).get("residentId", "")
		).strip_edges()
		if resident_id.is_empty():
			return _failure("SESSION_RESIDENT_ID_REQUIRED", false)
		if selected_ids.has(resident_id):
			return _failure("SESSION_RESIDENT_ID_DUPLICATED", false)
		if not residents_by_id.has(resident_id):
			return _failure("SESSION_RESIDENT_ID_UNKNOWN", false)
		selected_ids[resident_id] = true
		selected_residents.append(
			(residents_by_id[resident_id] as Dictionary).duplicate(true)
		)
	var projected := catalog.duplicate(true)
	projected["residents"] = selected_residents
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"catalog": projected,
		"residentCount": selected_residents.size(),
	}


func _close_resident_model_assignment(restore_focus := true) -> bool:
	if not is_instance_valid(_resident_model_assignment_page):
		_resident_model_assignment_page = null
		return false
	var page := _resident_model_assignment_page
	_resident_model_assignment_page = null
	if page.has_method("unbind_town_ui_adapter"):
		page.call("unbind_town_ui_adapter")
	if restore_focus:
		page.tree_exited.connect(
			Callable(self, "_restore_resident_selection_confirm_focus"),
			CONNECT_ONE_SHOT,
		)
	page.queue_free()
	if is_instance_valid(_resident_selection):
		_resident_selection.set_process_unhandled_input(true)
	return true


func _restore_resident_selection_confirm_focus() -> void:
	if not is_instance_valid(_resident_selection):
		return
	var confirm_button := _resident_selection.find_child(
		"ConfirmRosterButton",
		true,
		false,
	) as Button
	if confirm_button != null and not confirm_button.disabled:
		confirm_button.grab_focus()


func _on_resident_model_assignment_back_requested(revision: int) -> void:
	var view_model := _startup_ui_adapter.call(
		"get_view_model",
		"resident_model_assignment",
	) as Dictionary
	if revision != int(view_model.get("revision", -1)):
		_last_result = _failure(
			"RESIDENT_MODEL_ASSIGNMENT_ROUTE_REVISION_STALE",
			false,
		)
		return
	# This signal is only the page's presentation acknowledgement. Navigation
	# is owned by the service back_requested signal after dispatch succeeds.


func _on_resident_model_assignment_service_back_requested(
	draft: Dictionary,
	revision: int,
) -> void:
	if _resident_model_assignment_service == null:
		return
	var view_model := _resident_model_assignment_service.get_view_model() as Dictionary
	if revision != int(view_model.get("revision", -1)):
		_last_result = _failure(
			"RESIDENT_MODEL_ASSIGNMENT_ROUTE_REVISION_STALE",
			false,
		)
		return
	_resident_model_assignment_preserved_draft = draft.duplicate(true)
	call_deferred(
		"_complete_resident_model_assignment_back",
		revision,
		_flow_generation,
	)


func _complete_resident_model_assignment_back(
	revision: int,
	generation: int,
) -> void:
	if generation != _flow_generation or _resident_model_assignment_service == null:
		return
	var view_model := _resident_model_assignment_service.get_view_model() as Dictionary
	if revision != int(view_model.get("revision", -1)):
		return
	_close_resident_model_assignment(true)


func _on_resident_model_assignment_intent_requested(
	intent: String,
	payload: Dictionary,
) -> void:
	if intent not in [
		"resident_model_assignment.back",
		"resident_model_assignment.apply_draft",
	]:
		return
	var dispatch_result := payload.get("dispatchResult", {}) as Dictionary
	if not bool(dispatch_result.get("ok", false)):
		_last_result = dispatch_result.duplicate(true)
		if (
			intent == "resident_model_assignment.apply_draft"
			and _town_entry_loading_owner == "resident_model_assignment"
		):
			_dismiss_town_entry_loading()
			if _startup_ui_adapter != null:
				_startup_ui_adapter.call(
					"set_resident_model_assignment_startup_state",
					"idle",
				)


func _on_resident_model_assignment_action_dispatch_started(
	intent: String,
	_payload: Dictionary,
) -> void:
	if intent != "resident_model_assignment.apply_draft":
		return
	_begin_town_entry_loading(
		"new_game",
		_flow_generation,
		"resident_model_assignment",
		{"intent": intent},
	)
	_advance_town_entry_loading(0.12, "正在确认居民模型配置…")
	_publish_resident_model_assignment_starting()


func _on_resident_model_assignment_draft_applied(
	draft: Dictionary,
	_revision: int,
) -> void:
	if _resident_model_assignment_committing:
		return
	var validation := _startup_ui_adapter.call(
		"validate_new_game_draft",
		draft,
	) as Dictionary
	if not bool(validation.get("ok", false)):
		_publish_resident_model_assignment_startup_failure(validation)
		return
	_resident_model_assignment_preserved_draft = draft.duplicate(true)
	_resident_model_assignment_committing = true
	call_deferred(
		"_continue_after_resident_model_assignment",
		draft.duplicate(true),
		_flow_generation,
	)


func _continue_after_resident_model_assignment(
	draft: Dictionary,
	generation: int,
) -> void:
	if generation != _flow_generation:
		_resident_model_assignment_committing = false
		return
	if _resident_model_assignment_service == null:
		_publish_resident_model_assignment_startup_failure(_failure(
			"RESIDENT_MODEL_ASSIGNMENT_SERVICE_NOT_BOUND",
			false,
		))
		return
	var committed := _resident_model_assignment_service.get_committed_draft() as Dictionary
	if committed != draft:
		_publish_resident_model_assignment_startup_failure(_failure(
			"RESIDENT_MODEL_ASSIGNMENT_COMMIT_MISMATCH",
			false,
		))
		return
	_start_formal_new_game(committed)


func _publish_resident_model_assignment_starting() -> void:
	if _startup_ui_adapter == null:
		return
	var result := _startup_ui_adapter.call(
		"set_resident_model_assignment_startup_state",
		"loading",
		{
			"requestId": "resident-model-start-%d" % _flow_generation,
			"submittedAtMsec": Time.get_ticks_msec(),
		},
	) as Dictionary
	if not bool(result.get("ok", false)):
		_last_result = result.duplicate(true)


func _publish_resident_model_assignment_startup_failure(
	result: Dictionary,
) -> void:
	var final_result := result.duplicate(true)
	var discarded := _discard_failed_new_game_session()
	if not bool(discarded.get("ok", false)):
		final_result = _formal_overwrite_compensation_failure(
			result,
			discarded,
			"discard_unpublished_new_game",
		)
	_dismiss_town_entry_loading()
	_discard_pending_runtime()
	if bool(discarded.get("ok", false)):
		final_result = _restore_pending_formal_overwrite(final_result)
	_last_result = final_result.duplicate(true)
	_bootstrap = null
	_resident_model_assignment_committing = false
	if (
		is_instance_valid(_resident_model_assignment_page)
		and _resident_model_assignment_service != null
		and _startup_ui_adapter != null
	):
		var status := (
			"error" if bool(final_result.get("retryable", false)) else "rejected"
		)
		_startup_ui_adapter.call(
			"set_resident_model_assignment_startup_state",
			status,
			final_result.duplicate(true),
		)
		_restore_resident_model_assignment_failure_modal(final_result)
		return
	_set_resident_selection_result(final_result)


func _discard_failed_new_game_session() -> Dictionary:
	if _gateway == null or not is_instance_valid(_gateway):
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"changed": false,
		}
	if not _gateway.has_method("discard_unpublished_new_game"):
		return _failure("AGENT_NEW_GAME_DISCARD_CONTRACT_MISSING", false)
	return _gateway.call(
		"discard_unpublished_new_game",
		not _pending_formal_overwrite_archive.is_empty(),
	) as Dictionary


func _restore_pending_formal_overwrite(
	startup_failure: Dictionary,
) -> Dictionary:
	return _overwrite_compensator.restore_pending(
		startup_failure,
		_resolve_formal_archive_service(),
	)


func _finalize_pending_formal_overwrite() -> Dictionary:
	return _overwrite_compensator.finalize_pending(
		_resolve_formal_archive_service(),
	)


func _formal_overwrite_compensation_failure(
	startup_failure: Dictionary,
	compensation_failure: Dictionary,
	stage: String,
) -> Dictionary:
	return _overwrite_compensator.compensation_failure(
		startup_failure,
		compensation_failure,
		stage,
	)


func _resolve_formal_archive_service() -> RefCounted:
	return (
		_formal_archive_service_override
		if _formal_archive_service_override != null
		else FORMAL_SLOT_ARCHIVER.new()
	)


func _record_compensation_last_result(result: Dictionary) -> void:
	_last_result = result.duplicate(true)


func _restore_resident_model_assignment_failure_modal(
	result: Dictionary,
) -> void:
	if not is_instance_valid(_resident_model_assignment_page):
		return
	var message := _resident_model_assignment_failure_message(result)
	_resident_model_assignment_page.call("_open_completion_modal")
	_resident_model_assignment_page.call(
		"_set_completion_modal_message",
		"暂时无法开始游戏\n%s\n当前模型草稿已保留，可修复后重试。" % message,
	)


func _resident_model_assignment_failure_message(result: Dictionary) -> String:
	var error_code := String(
		result.get("errorCode", "RESIDENT_MODEL_ASSIGNMENT_START_FAILED")
	).strip_edges()
	var player_code := UI_VIEW_MODEL.player_reason(error_code)
	if player_code.is_empty() or player_code == "当前操作暂不可用":
		player_code = UI_VIEW_MODEL.player_reason(
			"RESIDENT_MODEL_ASSIGNMENT_START_FAILED"
		)
	var lines: Array[String] = [
		player_code,
		"错误代码：%s" % error_code,
	]
	var top_level_message := _explicit_player_message(result)
	if not top_level_message.is_empty() and top_level_message != lines[0]:
		lines.append(top_level_message)
	var detail_lines: Array[String] = []
	for collection_name in ["errors", "issues"]:
		var details_value: Variant = result.get(collection_name, [])
		if not details_value is Array:
			continue
		for detail_value: Variant in details_value as Array:
			var detail_message := ""
			if detail_value is Dictionary:
				var detail := detail_value as Dictionary
				detail_message = _explicit_player_message(detail)
				if detail_message.is_empty():
					var meta_value: Variant = detail.get("meta", {})
					if meta_value is Dictionary:
						detail_message = _explicit_player_message(
							meta_value as Dictionary
						)
			if detail_message.is_empty():
				continue
			if not detail_lines.has(detail_message):
				detail_lines.append(detail_message)
	var visible_detail_count := mini(detail_lines.size(), 3)
	for index in visible_detail_count:
		lines.append(detail_lines[index])
	if detail_lines.size() > visible_detail_count:
		lines.append("另有 %d 项配置错误。" % (
			detail_lines.size() - visible_detail_count
		))
	return "\n".join(lines)


func _explicit_player_message(payload: Dictionary) -> String:
	if not payload.has("playerMessage"):
		return ""
	var message_value: Variant = payload.get("playerMessage")
	if typeof(message_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return ""
	var message := String(message_value).strip_edges()
	if message.is_empty():
		return ""
	return UI_VIEW_MODEL.player_reason(message)


func _complete_resident_model_assignment_town_transition() -> void:
	if not _resident_model_assignment_committing:
		return
	_resident_model_assignment_committing = false
	_close_resident_model_assignment(false)
	_detach_resident_model_assignment_service()


func _reset_resident_model_assignment_session() -> void:
	if is_instance_valid(_resident_model_assignment_page):
		_close_resident_model_assignment(false)
	_detach_resident_model_assignment_service()
	_resident_model_assignment_preserved_draft.clear()


func _detach_resident_model_assignment_service() -> void:
	if _startup_ui_adapter != null:
		_startup_ui_adapter.call("bind_resident_model_assignment_service", null)
	_resident_model_assignment_service = null
	_resident_model_assignment_committing = false


func _merge_resident_model_assignment_draft(selection_draft: Dictionary) -> Dictionary:
	var merged := selection_draft.duplicate(true)
	if _resident_model_assignment_preserved_draft.is_empty():
		return merged
	var previous_slots := (
		_resident_model_assignment_preserved_draft.get("slots", []) as Array
	)
	var previous_by_resident: Dictionary = {}
	for slot_value: Variant in previous_slots:
		if not slot_value is Dictionary:
			continue
		var previous_slot := slot_value as Dictionary
		var resident_id := String(previous_slot.get("residentId", ""))
		if not resident_id.is_empty():
			previous_by_resident[resident_id] = previous_slot.duplicate(true)
	var current_slots := (merged.get("slots", []) as Array).duplicate(true)
	var current_resident_ids: Array[String] = []
	var preserved_count := 0
	var added_resident_ids: Array[String] = []
	for index in current_slots.size():
		if not current_slots[index] is Dictionary:
			continue
		var slot := (current_slots[index] as Dictionary).duplicate(true)
		var resident_id := String(slot.get("residentId", ""))
		current_resident_ids.append(resident_id)
		if previous_by_resident.has(resident_id):
			var preserved_slot := previous_by_resident[resident_id] as Dictionary
			slot["llmBinding"] = (
				preserved_slot.get("llmBinding", {}) as Dictionary
			).duplicate(true)
			preserved_count += 1
		else:
			slot["llmBinding"] = {
				"mode": "model",
				"providerId": "",
				"modelId": "",
			}
			added_resident_ids.append(resident_id)
		current_slots[index] = slot
	merged["slots"] = current_slots
	var removed_resident_ids: Array[String] = []
	for previous_resident_id: String in previous_by_resident:
		if not current_resident_ids.has(previous_resident_id):
			removed_resident_ids.append(previous_resident_id)
	if not added_resident_ids.is_empty() or not removed_resident_ids.is_empty():
		_last_result = {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"changed": true,
			"modelDraftMerge": {
				"policy": "resident_id",
				"preservedCount": preserved_count,
				"addedResidentIds": added_resident_ids,
				"invalidatedResidentIds": removed_resident_ids,
			},
		}
	return merged


func _bind_town_runtime(runtime: Node) -> void:
	_town_runtime = runtime
	_hide_legacy_runtime_ui(runtime)
	var adapter: Node = runtime.call("get_ui_adapter")
	if adapter == null:
		_last_result = _failure("TOWN_UI_ADAPTER_UNAVAILABLE", false)
		return
	_town_ui_adapter = adapter
	_session_ui_service = SESSION_UI_SERVICE.new()
	var save_configuration := _session_ui_service.call(
		"configure",
		runtime,
		runtime.call("get_world_runtime"),
		_agent_save_participant(),
		_active_session_config,
	) as Dictionary
	var save_binding := adapter.call(
		"bind_session_save_service",
		_session_ui_service,
	) as Dictionary
	var baseline_result: Dictionary = {}
	if not bool(save_binding.get("ok", false)):
		_last_result = save_binding
	elif not bool(save_configuration.get("ok", false)):
		_last_result = save_configuration
	else:
		baseline_result = _publish_initial_formal_baseline(adapter)
		if not bool(baseline_result.get("ok", false)):
			# Keep the running Town mounted. The save-scope operation published by
			# the Adapter remains the stable visible error, and every departure
			# path retries/refuses to leave until a complete pair can be published.
			_last_result = baseline_result.duplicate(true)
		elif not _pending_formal_overwrite_archive.is_empty():
			var finalized := _finalize_pending_formal_overwrite()
			if not bool(finalized.get("ok", false)):
				_last_result = finalized.duplicate(true)
	adapter.call(
		"bind_audio_display_settings_service",
		_audio_display_settings_service,
	)
	_provider_settings_ui_service = PROVIDER_SETTINGS_SERVICE.new()
	_provider_settings_ui_service.bind_provider_service(_provider_service,
		self)
	adapter.call(
		"bind_provider_settings_service",
		_provider_settings_ui_service,
	)
	var resident_model_binding := (
		_configure_in_session_resident_model_assignment(adapter)
	)
	if not bool(resident_model_binding.get("ok", false)):
		_last_result = resident_model_binding.duplicate(true)
	_ui_page_projection_service = UI_PAGE_PROJECTION_SERVICE.new()
	var projection_binding := _ui_page_projection_service.bind(runtime,
		runtime.call("get_world_runtime"),
		_active_session_config,
		_gateway) as Dictionary
	if not bool(projection_binding.get("ok", false)):
		_last_result = projection_binding
		return
	var page_service_binding := adapter.call(
		"bind_page_projection_service",
		_ui_page_projection_service,
	) as Dictionary
	if not bool(page_service_binding.get("ok", false)):
		_last_result = page_service_binding
		return
	_town_ui_canvas_layer = _ensure_formal_ui_canvas_layer(runtime)
	if _town_ui_canvas_layer.get_node_or_null("TownUiRuntimeHost") == null:
		_town_ui_host = _instantiate_control_script(TOWN_UI_RUNTIME_HOST_SCRIPT_PATH)
		if _town_ui_host == null:
			_last_result = _failure("TOWN_UI_RUNTIME_HOST_LOAD_FAILED", false)
			return
		_town_ui_host.name = "TownUiRuntimeHost"
		_town_ui_host.z_index = 20
		var town_ui_binding := _town_ui_host.call(
			"bind_town_ui_adapter",
			adapter,
		) as Dictionary
		if not bool(town_ui_binding.get("ok", false)):
			_town_ui_host.free()
			_town_ui_host = null
			_last_result = town_ui_binding
			return
		_town_ui_canvas_layer.add_child(_town_ui_host)
		adapter.call("bind_ui_route_host", _town_ui_host)
		_connect_once(
			_town_ui_host,
			"pause_requested",
			Callable(self, "_on_town_ui_pause_requested"),
		)
		_connect_once(
			_town_ui_host,
			"route_changed",
			Callable(self, "_on_town_ui_route_changed"),
		)
	else:
		_town_ui_host = _town_ui_canvas_layer.get_node("TownUiRuntimeHost") as Control
		var existing_town_ui_binding := _town_ui_host.call(
			"bind_town_ui_adapter",
			adapter,
		) as Dictionary
		if not bool(existing_town_ui_binding.get("ok", false)):
			_last_result = existing_town_ui_binding
			return
		adapter.call("bind_ui_route_host", _town_ui_host)
	# TownUiRuntimeHost may select its authoritative conversation route from the
	# Adapter during _ready(), before GameFlowHost has connected route_changed.
	# Always connect idempotently and then sample the current route so ESC cannot
	# mistake a mounted formal page for the bare Town route.
	_connect_once(
		_town_ui_host,
		"pause_requested",
		Callable(self, "_on_town_ui_pause_requested"),
	)
	_connect_once(
		_town_ui_host,
		"route_changed",
		Callable(self, "_on_town_ui_route_changed"),
	)
	if _town_ui_host.has_method("current_route"):
		_on_town_ui_route_changed(
			_town_ui_host.call("current_route") as StringName,
		)
	if _town_ui_canvas_layer.get_node_or_null("AvatarModeHud") == null:
		_avatar_hud = _instantiate_control_scene(AVATAR_MODE_HUD_SCENE_PATH)
		if _avatar_hud == null:
			_last_result = _failure("AVATAR_MODE_HUD_LOAD_FAILED", false)
			return
		_avatar_hud.name = "AvatarModeHud"
		_avatar_hud.z_index = 10
		var avatar_issues := _avatar_hud.call(
			"bind_town_ui_adapter",
			adapter,
		) as PackedStringArray
		if not avatar_issues.is_empty():
			_last_result = _failure("AVATAR_MODE_HUD_ADAPTER_BIND_FAILED", false, [{
				"issues": Array(avatar_issues),
			}])
			_avatar_hud.free()
			_avatar_hud = null
			return
		_town_ui_canvas_layer.add_child(_avatar_hud)
		_connect_once(
			_avatar_hud,
			"intent_requested",
			Callable(self, "_on_avatar_hud_intent_requested"),
		)
	else:
		_avatar_hud = _town_ui_canvas_layer.get_node("AvatarModeHud") as Control
		var existing_avatar_issues := _avatar_hud.call(
			"bind_town_ui_adapter",
			adapter,
		) as PackedStringArray
		if not existing_avatar_issues.is_empty():
			_last_result = _failure("AVATAR_MODE_HUD_ADAPTER_BIND_FAILED", false, [{
				"issues": Array(existing_avatar_issues),
			}])
			return
		_connect_once(
			_avatar_hud,
			"intent_requested",
			Callable(self, "_on_avatar_hud_intent_requested"),
		)
	if _town_ui_canvas_layer.get_node_or_null("PauseMenuNavigationHost") == null:
		_pause_host = _instantiate_control_scene(PAUSE_MENU_HOST_SCENE_PATH)
		if _pause_host == null:
			_last_result = _failure("PAUSE_MENU_HOST_LOAD_FAILED", false)
			return
		_pause_host.name = "PauseMenuNavigationHost"
		_pause_host.z_index = 30
		_pause_host.hide()
		_pause_host.call("bind_town_ui_adapter", adapter)
		_town_ui_canvas_layer.add_child(_pause_host)
		_connect_once(_pause_host, "intent_requested", Callable(self, "_on_pause_intent_requested"))
	else:
		_pause_host = _town_ui_canvas_layer.get_node("PauseMenuNavigationHost") as Control
		_pause_host.call("bind_town_ui_adapter", adapter)
		_connect_once(_pause_host, "intent_requested", Callable(self, "_on_pause_intent_requested"))
	if baseline_result.is_empty() or bool(baseline_result.get("ok", false)):
		_last_result = runtime.call("get_startup_result") as Dictionary
	var bound_world := runtime.call("get_world_runtime") as Object
	if bound_world != null and bound_world.has_signal("environment_changed"):
		_connect_once(
			bound_world,
			"environment_changed",
			Callable(self, "_on_town_environment_changed"),
		)
		_daily_auto_save_day = int(
			(bound_world.call("get_time") as Dictionary).get("day", -1)
		)
		_daily_auto_save_last_attempt_day = -1
	_present_pending_continue_notice()


func _on_town_environment_changed(time: Dictionary, _weather: String) -> void:
	if (
		_internal_playtest_enabled()
		or _session_ui_service == null
		or not is_instance_valid(_session_ui_service)
	):
		return
	var day := int(time.get("day", -1))
	if day <= 0 or day <= _daily_auto_save_day:
		return
	var now_msec := Time.get_ticks_msec()
	if (
		_daily_auto_save_inflight
		or (
			_daily_auto_save_last_attempt_day == day
			and now_msec - _daily_auto_save_last_attempt_msec
			< DAILY_AUTO_SAVE_RETRY_INTERVAL_MSEC
		)
	):
		return
	_daily_auto_save_inflight = true
	_daily_auto_save_last_attempt_day = day
	_daily_auto_save_last_attempt_msec = now_msec
	_daily_auto_save_attempts += 1
	var result := _session_ui_service.call("create_save", {
		"reason": DAILY_AUTO_SAVE_REASON,
	}) as Dictionary
	_daily_auto_save_inflight = false
	if bool(result.get("ok", false)):
		_daily_auto_save_day = day
		_daily_auto_save_successes += 1
		_daily_auto_save_last_revision = int(
			(result.get("manifest", {}) as Dictionary).get(
				"save_revision",
				_daily_auto_save_last_revision,
			)
		)
		return
	var failure := {
		"day": day,
		"errorCode": String(
			result.get("errorCode", "SESSION_SAVE_DAILY_AUTO_SAVE_FAILED")
		),
		"retryable": bool(result.get("retryable", false)),
	}
	_daily_auto_save_failures.append(failure)
	if _daily_auto_save_failures.size() > DAILY_AUTO_SAVE_ERROR_HISTORY_LIMIT:
		_daily_auto_save_failures.pop_front()


func _agent_save_participant() -> Object:
	if (
		_gateway == null
		or not is_instance_valid(_gateway)
		or not _gateway.has_method("get_agent_save_participant")
	):
		return null
	var participant: Object = _gateway.call("get_agent_save_participant")
	if participant == null or not is_instance_valid(participant):
		return null
	return participant


func _present_pending_continue_notice() -> void:
	if _pending_continue_notice.is_empty():
		return
	if (
		not is_instance_valid(_town_ui_host)
		or not _town_ui_host.has_method("present_feedback")
	):
		return
	var notice_id := String(
		_pending_continue_notice.get(
			"noticeId",
			"latest_save_incomplete_fallback",
		),
	)
	var message := String(_pending_continue_notice.get("message", ""))
	if message.is_empty():
		_pending_continue_notice.clear()
		return
	var presented := _town_ui_host.call("present_feedback", {
		"scope": "startup",
		"status": "ready",
		"revision": 1,
		"data": {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"feedback": {
				"feedbackId": "startup-%s" % notice_id,
				"component": "toast",
				"tone": "warning",
				"title": "已使用最近完整存档",
				"message": message,
				"blocking": false,
				"dismissPolicy": "auto_or_manual",
				"durationMsec": 5000,
				"anchor": "viewport_top_right",
				"dedupeKey": "startup.%s" % notice_id,
			},
		},
		"actions": {
			"dismiss": {
				"intent": "feedback.dismiss",
				"enabled": true,
				"disabledReason": "",
			},
		},
		"operation": {
			"requestId": "startup-%s" % notice_id,
			"intent": "session.continue",
			"status": "success",
			"submittedAtMsec": 0,
			"completedAtMsec": Time.get_ticks_msec(),
		},
		"error": null,
	}) as Dictionary
	if bool(presented.get("ok", false)):
		_pending_continue_notice.clear()


func _publish_initial_formal_baseline(adapter: Node) -> Dictionary:
	if (
		String(_active_session_config.get("worldStartMode", "")) != "formal"
		or String(_active_session_config.get("mode", "")) != "new_game"
		or int(_active_session_config.get("saveRevision", 0)) > 0
	):
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"changed": false,
		}
	if _session_ui_service == null or adapter == null:
		return _failure("SESSION_BASELINE_SAVE_SERVICE_NOT_CONFIGURED", false)
	var before := _session_ui_service.call("get_save_snapshot") as Dictionary
	if bool(before.get("canContinue", false)):
		return _failure("SESSION_BASELINE_SAVE_ALREADY_PUBLISHED", false)
	var dispatched := adapter.call("dispatch", "save.create", {
		"reason": "new_game_baseline",
	}) as Dictionary
	var after := _session_ui_service.call("get_save_snapshot") as Dictionary
	var result := after.get("lastResult", {}) as Dictionary
	if not bool(dispatched.get("ok", false)) or not bool(result.get("ok", false)):
		if result.is_empty():
			return _failure(
				String(dispatched.get("errorCode", "SESSION_BASELINE_SAVE_FAILED")),
				bool(dispatched.get("retryable", false)),
			)
		return result.duplicate(true)
	var manifest := result.get("manifest", {}) as Dictionary
	var revision := int(manifest.get("save_revision", 0))
	if revision <= 0 or not bool(after.get("canContinue", false)):
		return _failure("SESSION_BASELINE_SAVE_NOT_PUBLISHED", false)
	_active_session_config["saveRevision"] = revision
	var profile_result := _record_last_played_slot(
		String(_active_session_config.get("slotId", "")),
	)
	if not bool(profile_result.get("ok", false)):
		return profile_result
	return result.duplicate(true)


func _ensure_formal_ui_canvas_layer(runtime: Node) -> CanvasLayer:
	var existing := runtime.get_node_or_null("FormalUiCanvasLayer") as CanvasLayer
	if existing != null:
		existing.layer = FORMAL_UI_CANVAS_LAYER
		return existing
	var layer := CanvasLayer.new()
	layer.name = "FormalUiCanvasLayer"
	layer.layer = FORMAL_UI_CANVAS_LAYER
	runtime.add_child(layer)
	return layer


func _hide_legacy_runtime_ui(runtime: Node) -> void:
	for legacy_name in ["PlayerUi", "TownUi"]:
		var legacy_layer := runtime.get_node_or_null(legacy_name) as CanvasLayer
		if legacy_layer != null:
			legacy_layer.visible = false


func _on_resident_selection_requested(
	resident_id: String,
	should_select: bool,
	revision: int,
) -> void:
	if revision != int(_resident_selection_vm.get("revision", 0)):
		return
	var data := _resident_selection_vm.get("data", {}) as Dictionary
	var selected: Array = (data.get("selected_resident_ids", []) as Array).duplicate()
	var selection_limit := int(data.get("selection_limit", 15))
	if should_select and not selected.has(resident_id) and selected.size() < selection_limit:
		selected.append(resident_id)
	elif not should_select:
		selected.erase(resident_id)
	data["selected_resident_ids"] = selected
	data["focused_resident_id"] = resident_id
	_update_confirmation_payload(data)
	_advance_resident_selection_revision()


func _on_recommended_selection_requested(revision: int) -> void:
	if revision != int(_resident_selection_vm.get("revision", 0)):
		return
	var data := _resident_selection_vm.get("data", {}) as Dictionary
	data["selected_resident_ids"] = (
		data.get("recommended_resident_ids", []) as Array
	).duplicate()
	_update_confirmation_payload(data)
	_advance_resident_selection_revision()


func _on_selection_clear_requested(revision: int) -> void:
	if revision != int(_resident_selection_vm.get("revision", 0)):
		return
	var data := _resident_selection_vm.get("data", {}) as Dictionary
	data["selected_resident_ids"] = []
	_update_confirmation_payload(data)
	_advance_resident_selection_revision()


func _on_resident_selection_back_requested(revision: int) -> void:
	if (
		not _resident_selection_vm.is_empty()
		and revision != int(_resident_selection_vm.get("revision", 0))
	):
		return
	_flow_generation += 1
	_world_intro_vm = _build_world_intro_view_model(
		WORLD_INTRO_PAGES.size() - 1,
		_flow_generation,
	)
	call_deferred("_enter_world_intro", _flow_generation)


func _on_roster_confirmation_requested(payload: Dictionary, revision: int) -> void:
	if revision != int(_resident_selection_vm.get("revision", 0)):
		return
	var expected := (
		(_resident_selection_vm.get("data", {}) as Dictionary).get("confirmation_payload", {})
		as Dictionary
	)
	if not _resident_selection_drafts_match(payload, expected):
		_set_resident_selection_result(_failure("SESSION_DRAFT_REVISION_STALE", false))
		return
	if _internal_playtest_enabled():
		_start_internal_new_game(payload)
	else:
		_open_resident_model_assignment(payload)


func _resident_selection_drafts_match(
	actual: Dictionary,
	expected: Dictionary,
) -> bool:
	for field in ["schemaVersion", "sourceScope", "draftRevision"]:
		if actual.get(field) != expected.get(field):
			return false
	var actual_slots_value: Variant = actual.get("slots", [])
	var expected_slots_value: Variant = expected.get("slots", [])
	if not actual_slots_value is Array or not expected_slots_value is Array:
		return false
	var actual_slots := actual_slots_value as Array
	var expected_slots := expected_slots_value as Array
	if actual_slots.size() != expected_slots.size():
		return false
	for index in actual_slots.size():
		if not actual_slots[index] is Dictionary or not expected_slots[index] is Dictionary:
			return false
		var actual_slot := actual_slots[index] as Dictionary
		var expected_slot := expected_slots[index] as Dictionary
		if (
			String(actual_slot.get("residentId", ""))
			!= String(expected_slot.get("residentId", ""))
			or String(actual_slot.get("spaceId", ""))
			!= String(expected_slot.get("spaceId", ""))
		):
			return false
		if actual_slot.has("llmBinding") and not actual_slot.get("llmBinding") is Dictionary:
			return false
	return true


func _start_internal_new_game(draft: Dictionary) -> void:
	var generation := _flow_generation
	_begin_town_entry_loading(
		"new_game",
		generation,
		"resident_selection",
		{"intent": "session.new_game"},
	)
	await get_tree().process_frame
	if generation != _flow_generation:
		_dismiss_town_entry_loading_for_generation(generation)
		return
	var world_data := _read_json(WORLD_DATA_PATH)
	var catalog := _build_internal_catalog(world_data)
	if catalog.is_empty():
		_set_resident_selection_result(_failure("SESSION_PLACEHOLDER_CATALOG_INVALID", false))
		return
	var provider_id := OS.get_environment(INTERNAL_PROVIDER_ENV).strip_edges()
	if provider_id.is_empty():
		provider_id = "fake"
	var model_id := OS.get_environment(INTERNAL_MODEL_ENV).strip_edges()
	if model_id.is_empty():
		model_id = _default_model_id(provider_id)
	var normalized_draft := draft.duplicate(true)
	for slot_value: Variant in normalized_draft.get("slots", []) as Array:
		var slot := slot_value as Dictionary
		slot["llmBinding"] = {
			"mode": "model",
			"providerId": provider_id,
			"modelId": model_id,
		}
	_set_resident_selection_loading()
	_advance_town_entry_loading(0.32, "正在准备小镇地图…")
	_bootstrap = BOOTSTRAP.new()
	_provider_service = PROVIDER_SERVICE.new()
	var provider_configuration := _provider_service.call(
		"configure",
		{
			"capabilityMode": "development",
			"source": "placeholder",
			"allowFake": provider_id == "fake",
			"providerConfigs": {},
		},
		self,
	) as Dictionary
	if not bool(provider_configuration.get("ok", false)):
		_set_resident_selection_result(provider_configuration)
		return
	_gateway = GATEWAY.new()
	_pending_runtime = _instantiate_town_runtime()
	if _pending_runtime == null:
		_set_resident_selection_result(
			_failure("TOWN_RUNTIME_SCENE_UNAVAILABLE", false),
		)
		return
	_advance_town_entry_loading(0.52, "正在连接小镇居民…")
	var identity := "%d-%d" % [Time.get_unix_time_from_system(), _flow_generation]
	var begin_result := _bootstrap.begin_new_game_from_catalog(normalized_draft,
		world_data,
		catalog,
		_provider_service,
		_gateway,
		_pending_runtime,
		{
			"worldStartMode": "development",
			"internalPlaytest": true,
			"sessionId": "internal-session-%s" % identity,
			"slotId": "internal-slot-%s" % identity,
			"requestHost": self,
			"useLiveModel": provider_id != "fake",
				"enablePlayerAvatar": false,
				"avatarInitialMode": "observer",
		},
		Callable(self, "_on_bootstrap_completed").bind(_flow_generation)) as Dictionary
	if not bool(begin_result.get("accepted", false)) and not bool(begin_result.get("ok", false)):
		_set_resident_selection_result(begin_result)


func _start_formal_new_game(draft: Dictionary) -> void:
	if not _pending_formal_overwrite_archive.is_empty():
		# A prior startup failure could not finish restoring the confirmed old
		# save. Resolve that exact archive before any new overwrite attempt; the
		# player can submit again only after this compensation has completed.
		_publish_resident_model_assignment_startup_failure(
			_failure("FORMAL_SLOT_OVERWRITE_COMPENSATION_REQUIRED", false)
		)
		return
	var generation := _flow_generation
	_begin_town_entry_loading(
		"new_game",
		generation,
		"resident_model_assignment",
		{"intent": "resident_model_assignment.apply_draft"},
	)
	await get_tree().process_frame
	if generation != _flow_generation:
		_dismiss_town_entry_loading_for_generation(generation)
		return
	var world_data := _read_json(WORLD_DATA_PATH)
	var world_ready := bool(
		(world_data.get("contentStatus", {}) as Dictionary).get(
			"worldReady",
			false,
		)
	)
	if not world_ready:
		_publish_resident_model_assignment_startup_failure(
			_failure("WORLD_DATA_INCOMPLETE", false)
		)
		return
	var catalog_result := _formal_new_game_catalog()
	if not bool(catalog_result.get("ok", false)):
		_publish_resident_model_assignment_startup_failure(catalog_result)
		return
	var catalog := catalog_result.get("catalog", {}) as Dictionary
	if _startup_provider_settings_service == null:
		_publish_resident_model_assignment_startup_failure(
			_failure("PROVIDER_SETTINGS_SERVICE_NOT_BOUND", false)
		)
		return
	var normalized_draft := draft.duplicate(true)
	var binding_validation := _startup_provider_service.call(
		"validate_resident_bindings",
		_build_resident_binding_payload(normalized_draft),
	) as Dictionary
	if not bool(binding_validation.get("ok", false)):
		_publish_resident_model_assignment_startup_failure(binding_validation)
		return
	var overwrite_result := _archive_confirmed_formal_slot()
	if not bool(overwrite_result.get("ok", false)):
		_publish_resident_model_assignment_startup_failure(overwrite_result)
		return
	_advance_town_entry_loading(0.32, "正在准备小镇地图…")
	_bootstrap = BOOTSTRAP.new()
	_provider_service = _startup_provider_service
	_gateway = GATEWAY.new()
	_pending_runtime = _instantiate_town_runtime()
	if _pending_runtime == null:
		_publish_resident_model_assignment_startup_failure(
			_failure("TOWN_RUNTIME_SCENE_UNAVAILABLE", false),
		)
		return
	_advance_town_entry_loading(0.52, "正在连接小镇居民…")
	var identity := "%d-%d" % [Time.get_unix_time_from_system(), _flow_generation]
	var slot_id := String(
		_new_game_route_context.get("slotId", FORMAL_SLOT_ID)
	).strip_edges()
	if slot_id.is_empty():
		slot_id = FORMAL_SLOT_ID
	var begin_result := _bootstrap.begin_new_game_from_catalog(normalized_draft,
		world_data,
		catalog,
		_provider_service,
		_gateway,
		_pending_runtime,
		{
			"worldStartMode": "formal",
			"internalPlaytest": false,
			"internalLivePlaytest": false,
			"sessionId": "session-%s" % identity,
			"slotId": slot_id,
			"requestHost": self,
			"useLiveModel": true,
				"enablePlayerAvatar": false,
				"avatarInitialMode": "observer",
		},
		Callable(self, "_on_bootstrap_completed").bind(_flow_generation)) as Dictionary
	if not bool(begin_result.get("accepted", false)) and not bool(begin_result.get("ok", false)):
		_publish_resident_model_assignment_startup_failure(begin_result)


func _build_resident_binding_payload(draft: Dictionary) -> Array[Dictionary]:
	var bindings: Array[Dictionary] = []
	for slot_value: Variant in draft.get("slots", []) as Array:
		var slot := slot_value as Dictionary
		bindings.append({
			"residentId": String(slot.get("residentId", "")),
			"llmBinding": (
				slot.get("llmBinding", {}) as Dictionary
			).duplicate(true),
		})
	return bindings


func _configure_in_session_resident_model_assignment(
	adapter: Node,
) -> Dictionary:
	if (
		adapter == null
		or _provider_service == null
		or _active_session_config.is_empty()
	):
		return _failure(
			"RESIDENT_MODEL_ASSIGNMENT_RUNTIME_DEPENDENCY_MISSING",
			false,
		)
	var opening := _active_session_config.get("openingConfig", {}) as Dictionary
	var opening_residents_value: Variant = opening.get("residents", [])
	var bindings_value: Variant = _active_session_config.get(
		"residentBindings",
		[],
	)
	if (
		not opening_residents_value is Array
		or not bindings_value is Array
		or (opening_residents_value as Array).is_empty()
		or (opening_residents_value as Array).size()
		!= (bindings_value as Array).size()
	):
		return _failure("SESSION_LLM_BINDINGS_INVALID", false)
	var base_entries_by_id: Dictionary = {}
	for entry_value: Variant in (
		FORMAL_CATALOG.load_catalog().get("residents", []) as Array
	):
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		base_entries_by_id[String(entry.get("residentId", ""))] = (
			entry.duplicate(true)
		)
	var catalog_residents: Array[Dictionary] = []
	for resident_value: Variant in opening_residents_value as Array:
		if not resident_value is Dictionary:
			return _failure("SESSION_RESIDENT_IDENTITIES_INVALID", false)
		var opening_resident := resident_value as Dictionary
		var resident_id := String(
			opening_resident.get("residentId", "")
		).strip_edges()
		if resident_id.is_empty():
			return _failure("SESSION_RESIDENT_IDENTITIES_INVALID", false)
		if base_entries_by_id.has(resident_id):
			catalog_residents.append(
				(base_entries_by_id[resident_id] as Dictionary).duplicate(true)
			)
		else:
			# Save 内的自定义居民已经带着显示名与灵魂属性；模型分配页
			# 只依赖这些字段，头像缺失时会使用姓名首字作为稳定回退。
			catalog_residents.append({
				"residentId": resident_id,
				"attributes": (
					opening_resident.get("attributes", {}) as Dictionary
				).duplicate(true),
				"presentation": {},
			})
	var bindings_by_id: Dictionary = {}
	for binding_value: Variant in bindings_value as Array:
		if not binding_value is Dictionary:
			return _failure("SESSION_LLM_BINDINGS_INVALID", false)
		var binding := binding_value as Dictionary
		var resident_id := String(binding.get("residentId", "")).strip_edges()
		if (
			resident_id.is_empty()
			or bindings_by_id.has(resident_id)
			or not binding.get("llmBinding", {}) is Dictionary
		):
			return _failure("SESSION_LLM_BINDINGS_INVALID", false)
		bindings_by_id[resident_id] = (
			binding.get("llmBinding", {}) as Dictionary
		).duplicate(true)
	var ordered_resident_ids: Array[String] = []
	for resident in catalog_residents:
		ordered_resident_ids.append(String(resident.get("residentId", "")))
	ordered_resident_ids.sort()
	var slots: Array[Dictionary] = []
	for index in ordered_resident_ids.size():
		var resident_id := ordered_resident_ids[index]
		if not bindings_by_id.has(resident_id):
			return _failure("SESSION_LLM_BINDINGS_INVALID", false)
		slots.append({
			"residentId": resident_id,
			"spaceId": "home_%02d" % (index + 1),
			"llmBinding": (
				bindings_by_id[resident_id] as Dictionary
			).duplicate(true),
		})
	_resident_model_assignment_service = RESIDENT_MODEL_ASSIGNMENT_SERVICE.new()
	var configured := _resident_model_assignment_service.configure(
		_provider_service,
		{"residents": catalog_residents},
		{
			"schemaVersion": 1,
			"sourceScope": "resident_selection",
			"draftRevision": 1,
			"slots": slots,
		},
		{
			"revision": 1,
			"applyHandler": _apply_in_session_resident_model_bindings,
		},
	) as Dictionary
	if not bool(configured.get("ok", false)):
		_resident_model_assignment_service = null
		return configured
	var bound := adapter.bind_resident_model_assignment_service(
		_resident_model_assignment_service,
	) as Dictionary
	if not bool(bound.get("ok", false)):
		_resident_model_assignment_service = null
		return bound
	return configured


func _apply_in_session_resident_model_bindings(
	_draft: Dictionary,
	bindings: Array,
) -> Dictionary:
	if (
		_gateway == null
		or not is_instance_valid(_gateway)
		or not _gateway.has_method("update_resident_bindings")
		or not is_instance_valid(_town_runtime)
		or not _town_runtime.has_method("update_resident_bindings")
		or _session_ui_service == null
		or not _session_ui_service.has_method("update_resident_bindings")
	):
		return _failure(
			"RESIDENT_MODEL_ASSIGNMENT_RUNTIME_DEPENDENCY_MISSING",
			false,
		)
	var previous_bindings := (
		_active_session_config.get("residentBindings", []) as Array
	).duplicate(true)
	var gateway_result := _gateway.update_resident_bindings(
		bindings.duplicate(true),
	) as Dictionary
	if not bool(gateway_result.get("ok", false)):
		return gateway_result
	var runtime_result := _town_runtime.update_resident_bindings(
		bindings.duplicate(true),
	) as Dictionary
	if not bool(runtime_result.get("ok", false)):
		_gateway.update_resident_bindings(previous_bindings)
		return runtime_result
	var session_result := _session_ui_service.update_resident_bindings(
		bindings.duplicate(true),
	) as Dictionary
	if not bool(session_result.get("ok", false)):
		_town_runtime.update_resident_bindings(previous_bindings)
		_gateway.update_resident_bindings(previous_bindings)
		return session_result
	_active_session_config["residentBindings"] = bindings.duplicate(true)
	var save_result := _session_ui_service.create_save(
		{"reason": "resident_model_rebind"},
	) as Dictionary
	if not bool(save_result.get("ok", false)):
		var rollback_errors: Array[Dictionary] = []
		for rollback_value: Variant in [
			_session_ui_service.update_resident_bindings(
				previous_bindings,
			),
			_town_runtime.update_resident_bindings(
				previous_bindings,
			),
			_gateway.update_resident_bindings(
				previous_bindings,
			),
		]:
			if (
				not rollback_value is Dictionary
				or not bool((rollback_value as Dictionary).get("ok", false))
			):
				rollback_errors.append({"result": rollback_value})
		_active_session_config["residentBindings"] = previous_bindings
		if not rollback_errors.is_empty():
			return _failure(
				"RESIDENT_MODEL_ASSIGNMENT_ROLLBACK_FAILED",
				true,
				rollback_errors,
			)
		_last_result = save_result.duplicate(true)
		return save_result
	_last_result = save_result.duplicate(true)
	var result := save_result.duplicate(true)
	result["changed"] = bool(gateway_result.get("changed", true))
	return result


func _formal_new_game_catalog() -> Dictionary:
	if _custom_resident_candidate_pool != null:
		var merged := _custom_resident_candidate_pool.get_merged_catalog() as Dictionary
		if merged.is_empty():
			return _failure("CUSTOM_RESIDENT_MERGED_CATALOG_UNAVAILABLE", false)
		if (
			int(merged.get("schemaVersion", 0)) != 1
			or String(merged.get("worldId", "")) != "town"
			or not merged.get("residents") is Array
		):
			return _failure("CUSTOM_RESIDENT_MERGED_CATALOG_INVALID", false)
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"catalog": merged.duplicate(true),
			"source": "resident_selection_candidate_pool",
		}
	var catalog := FORMAL_CATALOG.load_catalog() as Dictionary
	var validation := FORMAL_CATALOG.validate(catalog) as Dictionary
	if not bool(validation.get("ok", false)):
		return validation
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"catalog": catalog.duplicate(true),
		"source": "formal_base_catalog",
	}


func _archive_confirmed_formal_slot() -> Dictionary:
	var interrupted_recovery := _recover_interrupted_formal_overwrites()
	if not bool(interrupted_recovery.get("ok", false)):
		return interrupted_recovery
	var target_slot_id := String(
		_new_game_route_context.get("slotId", FORMAL_SLOT_ID),
	).strip_edges()
	if target_slot_id.is_empty():
		return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
	if not bool(_new_game_route_context.get("overwriteConfirmed", false)):
		var unexpected_save := _discover_startup_slot(target_slot_id)
		if bool(unexpected_save.get("ok", false)):
			return _failure("FORMAL_SLOT_OVERWRITE_CONFIRMATION_REQUIRED", false)
		if String(unexpected_save.get("errorCode", "")) not in [
			"SESSION_SAVE_NO_PUBLISHED_REVISION",
			"SESSION_SAVE_AGENT_SNAPSHOT_INVALID",
			"SESSION_SAVE_AGENT_RESIDENT_SET_MISMATCH",
		]:
			return unexpected_save
		# Agent creates revision 0 before the first paired World publication. A
		# crash in that narrow window must never become Continue, but it also must
		# not permanently brick New Game. Recoverably isolate that unpaired slot;
		# any World-side state makes this fail closed for explicit reconciliation.
		var orphan_archiver: RefCounted = FORMAL_SLOT_ARCHIVER.new()
		return orphan_archiver.call(
			"archive_unpaired_agent_slot_for_new_game",
			target_slot_id,
		) as Dictionary
	var expected_value: Variant = _new_game_route_context.get(
		"overwriteExpectedSave",
	)
	if not expected_value is Dictionary:
		return _failure("FORMAL_SLOT_ARCHIVE_CONTEXT_INVALID", false)
	var expected := expected_value as Dictionary
	var latest := _discover_startup_slot(target_slot_id)
	if not bool(latest.get("ok", false)):
		return latest
	var latest_summary := latest.get("summary", {}) as Dictionary
	if not _same_formal_save(expected, latest_summary):
		return _failure("FORMAL_SLOT_ARCHIVE_SAVE_CHANGED", false)
	var archiver: RefCounted = _resolve_formal_archive_service()
	var archived := archiver.call("archive_for_new_game", {
		"slotId": String(latest_summary.get("slotId", FORMAL_SLOT_ID)),
		"sessionId": String(latest_summary.get("sessionId", "")),
		"saveRevision": int(latest_summary.get("saveRevision", -1)),
	}) as Dictionary
	if bool(archived.get("ok", false)):
		_pending_formal_overwrite_archive = {
			"slotId": String(latest_summary.get("slotId", FORMAL_SLOT_ID)),
			"sessionId": String(latest_summary.get("sessionId", "")),
			"saveRevision": int(latest_summary.get("saveRevision", -1)),
			"archivePath": String(archived.get("archivePath", "")),
		}
	_last_result = archived.duplicate(true)
	return archived


func _start_formal_continue(
	generation: int,
	requested_slot_id := "",
	recovery_confirmed := false,
	route_kind_override := "",
) -> void:
	if generation != _flow_generation:
		return
	var discovery := (
		_discover_formal_save(true)
		if String(requested_slot_id).strip_edges().is_empty()
		else _discover_startup_slot(
			String(requested_slot_id).strip_edges(),
			true,
		)
	)
	if not bool(discovery.get("ok", false)):
		_publish_startup_result(discovery)
		return
	if (
		bool(discovery.get("requiresRecoveryConfirmation", false))
		and not bool(recovery_confirmed)
	):
		_open_continue_recovery(
			discovery,
			"load_game"
			if not String(requested_slot_id).strip_edges().is_empty()
			else "continue",
		)
		return
	var route_kind := route_kind_override.strip_edges()
	if not route_kind in ["continue", "load_game"]:
		route_kind = (
			"load_game"
			if not String(requested_slot_id).strip_edges().is_empty()
			else "continue"
		)
	_begin_town_entry_loading(
		route_kind,
		generation,
		"startup_load_game" if route_kind == "load_game" else "startup",
		{
			"slotId": String(requested_slot_id).strip_edges(),
			"intent": (
				"session.continue_slot"
				if route_kind == "load_game"
				else "session.continue"
			),
		},
	)
	await get_tree().process_frame
	if generation != _flow_generation:
		_dismiss_town_entry_loading_for_generation(generation)
		return
	_advance_town_entry_loading(0.18, "正在读取小镇存档…")
	var world_data := _read_json(WORLD_DATA_PATH)
	if not bool(
		(world_data.get("contentStatus", {}) as Dictionary).get(
			"worldReady",
			false,
		)
	):
		_publish_startup_result(_failure("WORLD_DATA_INCOMPLETE", false))
		return
	if _startup_provider_settings_service == null:
		_publish_startup_result(_failure("PROVIDER_SETTINGS_SERVICE_NOT_BOUND", false))
		return
	var provider_runtime := _startup_provider_settings_service.call(
		"runtime_configuration"
	) as Dictionary
	var manifest := discovery.get("manifest", {}) as Dictionary
	var saved_config := discovery.get("sessionConfig", {}) as Dictionary
	var identities := (
		saved_config.get("residentIdentities", []) as Array
	).duplicate(true)
	var bindings: Array[Dictionary] = []
	var resident_names: Array[String] = []
	for value: Variant in saved_config.get("residentBindings", []) as Array:
		if value is Dictionary:
			bindings.append((value as Dictionary).duplicate(true))
	for value: Variant in identities:
		var identity := value as Dictionary
		resident_names.append(String(identity.get("residentName", "")))
	if bindings.is_empty():
		_publish_startup_result(_failure(
			"SESSION_SAVE_RESIDENT_BINDINGS_MISSING",
			false,
		))
		return
	_provider_service = PROVIDER_SERVICE.new()
	var provider_configuration := _provider_service.call("configure", {
		"capabilityMode": "formal",
		"source": "runtime",
		"allowFake": false,
		"providerConfigs": (
			provider_runtime.get("providerConfigs", {}) as Dictionary
		).duplicate(true),
	}, self) as Dictionary
	if not bool(provider_configuration.get("ok", false)):
		_publish_startup_result(provider_configuration)
		return
	_advance_town_entry_loading(0.34, "正在检查居民连接…")
	var health_started := _provider_service.call(
		"request_health_check",
		bindings.duplicate(true),
		Callable(self, "_on_formal_continue_provider_health_completed").bind(
			generation,
			discovery.duplicate(true),
			world_data.duplicate(true),
			identities.duplicate(true),
			bindings.duplicate(true),
			resident_names.duplicate(),
		),
	) as Dictionary
	if not bool(health_started.get("accepted", false)):
		_publish_startup_result(health_started)


func _on_formal_continue_provider_health_completed(
	health_result: Dictionary,
	generation: int,
	discovery: Dictionary,
	world_data: Dictionary,
	identities: Array,
	bindings: Array,
	resident_names: Array,
) -> void:
	if generation != _flow_generation:
		return
	if not bool(health_result.get("ok", false)):
		_publish_startup_result(health_result)
		return
	var binding_validation := _provider_service.call(
		"check_entry_availability",
		bindings.duplicate(true),
	) as Dictionary
	if not bool(binding_validation.get("ok", false)):
		_publish_startup_result(binding_validation)
		return
	_advance_town_entry_loading(0.52, "正在准备小镇地图…")
	var manifest := discovery.get("manifest", {}) as Dictionary
	var saved_config := discovery.get("sessionConfig", {}) as Dictionary
	var slot_id := String(manifest.get("slot_id", "")).strip_edges()
	if slot_id.is_empty():
		_publish_startup_result(_failure("SESSION_SAVE_CONTEXT_INVALID", false))
		return
	_gateway = GATEWAY.new()
	var restore_revision := int(manifest.get("save_revision", 0))
	var session_id := String(manifest.get("session_id", ""))
	var gateway_config := {
		"sessionId": session_id,
		"slotId": slot_id,
		"saveRevision": restore_revision,
		"restorePending": true,
		"residentIdentities": identities.duplicate(true),
		"residentBindings": bindings.duplicate(true),
		"capabilityMode": "formal",
		"formalReady": true,
	}
	var gateway_result := _gateway.call(
		"configure_session",
		gateway_config,
		_provider_service,
		self,
	) as Dictionary
	if not bool(gateway_result.get("ok", false)):
		_publish_startup_result(gateway_result)
		_gateway = null
		return
	var runtime := _instantiate_town_runtime()
	if runtime == null:
		_publish_startup_result(
			_failure("TOWN_RUNTIME_SCENE_UNAVAILABLE", false),
		)
		return
	var gateway_injection := runtime.call(
		"configure_agent_gateway",
		_gateway,
	) as Dictionary
	if not bool(gateway_injection.get("ok", false)):
		runtime.free()
		_publish_startup_result(gateway_injection)
		return
	var restored_session_config := {
		"mode": "continue",
		"sessionId": session_id,
		"slotId": slot_id,
		"saveRevision": restore_revision,
		"restorePending": true,
		"openingConfig": (
			saved_config.get("openingConfig", {}) as Dictionary
		).duplicate(true),
		"residentIdentities": identities.duplicate(true),
		"residentBindings": bindings.duplicate(true),
		"connectedResidents": resident_names.duplicate(),
		"worldStartMode": "formal",
		"capabilityMode": "formal",
		"source": "runtime",
		"formalReady": true,
		"providerFormalReady": true,
		"internalPlaytest": false,
		"internalLivePlaytest": false,
		"requireAgentGateway": true,
		"useLiveModel": true,
		"enablePlayerAvatar": false,
		"avatarInitialMode": "observer",
		"enableTestUi": false,
	}
	var runtime_configuration := runtime.call(
		"configure_session",
		restored_session_config,
	) as Dictionary
	if not bool(runtime_configuration.get("ok", false)):
		runtime.free()
		_publish_startup_result(runtime_configuration)
		return
	_pending_runtime = runtime
	if runtime is CanvasItem:
		(runtime as CanvasItem).hide()
	get_tree().root.add_child(runtime)
	_advance_town_entry_loading(0.68, "正在恢复小镇…")
	await get_tree().process_frame
	if generation != _flow_generation or not is_instance_valid(runtime):
		_discard_pending_runtime()
		return
	var startup_result := runtime.call("get_startup_result") as Dictionary
	if not bool(startup_result.get("ok", false)):
		_discard_pending_runtime()
		_publish_startup_result(startup_result)
		return
	var restore_service := SESSION_UI_SERVICE.new()
	var service_result := restore_service.call(
		"configure",
		runtime,
		runtime.call("get_world_runtime"),
		_agent_save_participant(),
		restored_session_config,
	) as Dictionary
	if not bool(service_result.get("ok", false)):
		_discard_pending_runtime()
		_publish_startup_result(service_result)
		return
	var restored := restore_service.call(
		"continue_revision",
		session_id,
		restore_revision,
		world_data,
		identities,
		_gateway,
	) as Dictionary
	if not bool(restored.get("ok", false)):
		_discard_pending_runtime()
		_publish_startup_result(restored)
		return
	_advance_town_entry_loading(0.88, "正在布置小镇…")
	if runtime.has_method("complete_restored_session"):
		var completion := runtime.call(
			"complete_restored_session",
			restored.get("context", {}) as Dictionary,
		) as Dictionary
		if not bool(completion.get("ok", false)):
			_discard_pending_runtime()
			_publish_startup_result(completion)
			return
	restored_session_config["restorePending"] = false
	restored_session_config["saveRevision"] = int(
		(restored.get("context", {}) as Dictionary).get(
			"save_revision",
			restore_revision,
		)
	)
	restored_session_config["identityStatus"] = "confirmed"
	_active_session_config = restored_session_config.duplicate(true)
	_pending_continue_notice = (
		discovery.get("continueNotice", {}) as Dictionary
	).duplicate(true)
	var profile_result := _record_last_played_slot(slot_id)
	_last_result = (
		restored.duplicate(true)
		if bool(profile_result.get("ok", false))
		else profile_result.duplicate(true)
	)
	if runtime is CanvasItem:
		(runtime as CanvasItem).show()
	call_deferred("_enter_pending_town", generation)


func _on_bootstrap_completed(result: Dictionary, generation: int) -> void:
	if generation != _flow_generation:
		_discard_pending_runtime()
		return
	_last_result = result.duplicate(true)
	if not bool(result.get("ok", false)):
		_publish_resident_model_assignment_startup_failure(result)
		return
	_active_session_config = (
		result.get("sessionConfig", {}) as Dictionary
	).duplicate(true)
	_advance_town_entry_loading(0.88, "正在布置小镇…")
	call_deferred("_enter_pending_town", generation)


func _enter_pending_town(generation: int) -> void:
	if generation != _flow_generation:
		return
	if _pending_runtime == null:
		_publish_resident_model_assignment_startup_failure(
			_failure("SESSION_TOWN_RUNTIME_MISSING", false)
		)
		return
	var old_scene := get_tree().current_scene
	var runtime := _pending_runtime
	if runtime.get_parent() == null:
		get_tree().root.add_child(runtime)
	var startup_result := (
		runtime.call("get_startup_result") as Dictionary
		if runtime.has_method("get_startup_result")
		else _failure("TOWN_RUNTIME_STARTUP_RESULT_MISSING", false)
	)
	if not bool(startup_result.get("ok", false)):
		_publish_resident_model_assignment_startup_failure(startup_result)
		return
	_pending_runtime = null
	get_tree().current_scene = runtime
	_complete_resident_model_assignment_town_transition()
	if old_scene != null and old_scene != runtime:
		old_scene.queue_free()
	if is_instance_valid(_town_entry_loading_overlay):
		_town_entry_loading_overlay.call("complete")
	_bound_scene_id = 0
	_bind_current_scene.call_deferred()
	call_deferred("_dismiss_town_entry_loading_after_frame", generation)


func _open_pause_menu() -> void:
	if _town_runtime == null or _pause_host == null:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		_pause_focus_return_path = focus_owner.get_path()
		focus_owner.release_focus()
	else:
		_pause_focus_return_path = NodePath()
	_town_runtime.call("set_main_menu_open", true)
	_pause_host.show()
	_pause_open = true
	_sync_town_runtime_input_gates()


func _close_pause_menu() -> void:
	if _town_runtime == null or _pause_host == null:
		return
	var focus_return_path := _pause_focus_return_path
	_pause_focus_return_path = NodePath()
	_town_runtime.call("set_main_menu_open", false)
	_pause_host.hide()
	_pause_open = false
	get_viewport().gui_release_focus()
	_sync_town_runtime_input_gates()
	call_deferred("_restore_pause_focus", focus_return_path)


func _restore_pause_focus(focus_return_path: NodePath) -> void:
	if _pause_open or _town_ui_route != &"town" or focus_return_path.is_empty():
		return
	var focus_target := get_node_or_null(focus_return_path) as Control
	if (
		focus_target != null
		and focus_target.is_visible_in_tree()
		and focus_target.focus_mode != Control.FOCUS_NONE
	):
		focus_target.grab_focus()


func _on_pause_intent_requested(intent: StringName, payload: Dictionary) -> void:
	match String(intent):
		"lifecycle.resume":
			_close_pause_menu()
		"pause_menu.open_load_game":
			_open_in_session_load_game()
		"session.continue_slot", "session.confirm_recovery":
			call_deferred(
				"_complete_in_session_load_game",
				payload.duplicate(true),
				String(intent) == "session.confirm_recovery",
			)
		"pause_menu.return_to_start":
			# The intent is emitted from a pause-menu button's pressed signal. Freeing
			# the overlay tree synchronously here invalidates both the signal emitter
			# and the screen's remaining dispatch work. Leave the signal stack first.
			if not _pause_return_deferred:
				_pause_return_deferred = true
				call_deferred("_complete_pause_return_to_start")
		"pause_menu.quit_game":
			var quit_result := request_quit_game()
			if not bool(quit_result.get("ok", false)):
				call_deferred(
					"_present_pause_departure_failure",
					"pause_menu.quit_game",
					quit_result.duplicate(true),
				)
		"pause_menu.open_llm_settings":
			if is_instance_valid(_town_ui_host):
				_pause_host.hide()
				var settings_opened := _town_ui_host.call(
					"open_page",
					&"provider_settings",
				) as Dictionary
				if not bool(settings_opened.get("ok", false)):
					_pause_host.show()
					if _pause_host.has_method("present_host_result"):
						_pause_host.call(
							"present_host_result",
							"pause_menu.open_llm_settings",
							settings_opened,
						)
		"pause_menu.open_resident_models":
			if is_instance_valid(_town_ui_host):
				_pause_host.hide()
				var assignment_opened := _town_ui_host.open_page(
					&"resident_model_assignment",
					{"mode": "in_session"},
				) as Dictionary
				if not bool(assignment_opened.get("ok", false)):
					_pause_host.show()
					if _pause_host.has_method("present_host_result"):
						_pause_host.present_host_result(
							"pause_menu.open_resident_models",
							assignment_opened,
						)


func _open_in_session_load_game() -> void:
	if _in_session_load_pending:
		return
	if not is_instance_valid(_pause_host) or not _pause_open:
		_last_result = _failure("IN_SESSION_LOAD_HOST_UNAVAILABLE", false)
		return
	var view_model := get_startup_load_game_view_model("load")
	var data := view_model.get("data", {}) as Dictionary
	data["inSession"] = true
	data["pageTitle"] = "加载游戏"
	var actions := view_model.get("actions", {}) as Dictionary
	actions["deleteSlot"] = {
		"intent": "save.request_delete_slot",
		"enabled": false,
		"disabledReason": "IN_SESSION_DELETE_SLOT_NOT_AVAILABLE",
	}
	if not bool(_pause_host.call("open_load_game", view_model)):
		_last_result = _failure("IN_SESSION_LOAD_ROUTE_FAILED", false)
		_pause_host.call(
			"present_host_result",
			"pause_menu.open_load_game",
			_last_result,
		)
		return
	_last_result = {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"loadGameViewModel": view_model.duplicate(true),
	}


func _complete_in_session_load_game(
	payload: Dictionary,
	recovery_confirmed: bool,
) -> void:
	if _in_session_load_pending:
		return
	_in_session_load_pending = true
	var slot_id := String(payload.get("slotId", "")).strip_edges()
	if slot_id.is_empty():
		_present_in_session_load_failure(
			_failure("STARTUP_SAVE_SLOT_ID_INVALID", false),
		)
		return
	var discovery := _discover_startup_slot(slot_id)
	if not bool(discovery.get("ok", false)):
		_present_in_session_load_failure(discovery)
		return
	if not ResourceLoader.exists(STARTUP_SCENE_PATH, "PackedScene"):
		_present_in_session_load_failure(
			_failure("GAME_FLOW_STARTUP_ROUTE_FAILED", false),
		)
		return
	var startup_scene := load(STARTUP_SCENE_PATH) as PackedScene
	if startup_scene == null:
		_present_in_session_load_failure(
			_failure("GAME_FLOW_STARTUP_ROUTE_FAILED", false),
		)
		return
	var departure := _prepare_session_departure()
	if not bool(departure.get("ok", false)):
		_present_in_session_load_failure(departure)
		return

	var route_error := get_tree().change_scene_to_packed(startup_scene)
	if route_error != OK:
		_present_in_session_load_failure(
			_failure("GAME_FLOW_STARTUP_ROUTE_FAILED", false, [{
				"godotError": route_error,
			}]),
		)
		return
	_unmount_town_overlays()
	_release_internal_session_refs()
	_flow_generation += 1
	var generation := _flow_generation
	await get_tree().process_frame
	if generation != _flow_generation:
		return
	_bound_scene_id = 0
	_bind_current_scene()
	call_deferred(
		"_start_formal_continue",
		generation,
		slot_id,
		recovery_confirmed,
		"load_game",
	)


func _present_in_session_load_failure(result: Dictionary) -> void:
	_in_session_load_pending = false
	_last_result = result.duplicate(true)
	if is_instance_valid(_pause_host):
		if String(_pause_host.call("current_route")) == "load_game":
			_pause_host.call("close_load_game")
		_pause_host.call(
			"present_host_result",
			"pause_menu.open_load_game",
			result.duplicate(true),
		)


func _complete_pause_return_to_start() -> void:
	_pause_return_deferred = false
	var result := request_return_to_start()
	if not bool(result.get("ok", false)):
		_present_pause_departure_failure(
			"pause_menu.return_to_start",
			result,
		)


func _present_pause_departure_failure(
	intent: String,
	result: Dictionary,
) -> void:
	if is_instance_valid(_pause_host):
		_pause_host.call(
			"present_host_result",
			intent,
			result.duplicate(true),
		)


func _on_avatar_hud_intent_requested(_intent: String, _payload: Dictionary) -> void:
	# AvatarModeHud is a self-dispatching page bound to the shared Adapter.
	# In particular, avatar.focus_target only changes the selected nearby target;
	# it is not a request to open ResidentActionMenu. Explicit resident-action
	# entry points remain owned by TownUiRuntimeHost.
	pass


func _on_town_ui_pause_requested() -> void:
	if not _pause_open:
		_open_pause_menu()


func _on_town_ui_route_changed(route: StringName) -> void:
	_town_ui_route = route
	if (
		is_instance_valid(_town_runtime)
		and _town_runtime.has_method("set_place_focus_route_active")
	):
		_town_runtime.call(
			"set_place_focus_route_active",
			route == &"place_focus",
		)
	_sync_town_runtime_input_gates()
	if (
		route == &"town"
		and _pause_open
		and is_instance_valid(_pause_host)
		and not _pause_host.visible
	):
		_pause_host.show()


func _sync_town_runtime_input_gates() -> void:
	if not is_instance_valid(_town_runtime):
		return
	var gameplay_input_enabled := _town_ui_route == &"town" and not _pause_open
	if _town_runtime.has_method("set_observer_camera_input_enabled"):
		_town_runtime.call(
			"set_observer_camera_input_enabled",
			gameplay_input_enabled,
		)
	if _town_runtime.has_method("set_avatar_movement_input_enabled"):
		_town_runtime.call(
			"set_avatar_movement_input_enabled",
			gameplay_input_enabled,
		)


func _build_startup_view_models() -> Dictionary:
	var internal_playtest := _internal_playtest_enabled()
	var world_data := _read_json(WORLD_DATA_PATH)
	var world_ready := bool(
		(world_data.get("contentStatus", {}) as Dictionary).get("worldReady", false)
	)
	var catalog_validation := FORMAL_CATALOG.validate(
		FORMAL_CATALOG.load_catalog()
	) as Dictionary
	var catalog_ready := bool(catalog_validation.get("ok", false))
	var provider_ready := false
	if _startup_provider_settings_service != null:
		var provider_vm := _startup_provider_settings_service.call(
			"get_view_model"
		) as Dictionary
		provider_ready = bool(
			(provider_vm.get("data", {}) as Dictionary).get("formalReady", false)
		)
	# New Game only needs the formal World and resident catalog. Provider keys,
	# health, and model choices belong to the later resident-model assignment.
	var formal_route_ready := (
		not internal_playtest
		and world_ready
		and catalog_ready
	)
	var startup_catalog := _startup_catalog_snapshot()
	var save_discovery := _discover_formal_save()
	var saved_summary := save_discovery.get("summary", {}) as Dictionary
	var has_formal_save := bool(save_discovery.get("ok", false))
	var startup_slots: Array[Dictionary] = []
	if bool(startup_catalog.get("ok", false)):
		for slot_value: Variant in startup_catalog.get("slots", []) as Array:
			if slot_value is Dictionary:
				startup_slots.append(_startup_slot_projection(slot_value as Dictionary))
	var continue_gate := _startup_continue_gate(
		internal_playtest,
		world_ready,
		catalog_ready,
		save_discovery,
	)
	var continue_enabled := bool(continue_gate.get("enabled", false))
	var continue_reason := String(continue_gate.get("disabledReason", ""))
	var continue_formal_ready := bool(continue_gate.get("formalReady", false))
	var source := "placeholder" if internal_playtest else "formal"
	var capability_mode := "development" if internal_playtest else "formal"
	var validation_mode := "development" if internal_playtest else "formal"
	var new_game_enabled := internal_playtest or formal_route_ready
	var new_game_error := (
		"" if new_game_enabled else (
			String(catalog_validation.get("errorCode", "FORMAL_SESSION_CATALOG_MISSING"))
			if not catalog_ready
			else "WORLD_DATA_INCOMPLETE" if not world_ready
			else "STARTUP_NEW_GAME_NOT_READY"
		)
	)
	var revision := _next_startup_view_model_revision()
	return {
		"session": {
			"scope": "session",
			"status": "ready",
			"revision": revision,
			"data": {
				"mode": (
					"development_new_game"
					if internal_playtest
					else "startup"
				),
				"sessionId": "",
				"canEnterTown": false,
				"residentCount": 0,
				"providerStatus": (
					"development_placeholder"
					if internal_playtest
					else "available" if provider_ready else "configuration_required"
				),
				"loadSummary": {
					"stageId": "ready" if new_game_enabled else "blocked",
					"stageLabel": (
						"开发内测入口已就绪"
						if internal_playtest
						else "正式入口已就绪" if formal_route_ready else "正式入口尚未就绪"
					),
					"progress": 1.0 if new_game_enabled else 0.0,
					"detail": (
						"显式 placeholder + fake/fake；不开放存档"
						if internal_playtest
						else (
							"正式 World 数据仍在校验中"
							if not world_ready
							else "正式居民目录仍在校验中"
							if not catalog_ready
							else (
								"可以开始新游戏；模型设置只管理凭据，居民模型稍后分配"
								if not provider_ready
								else "正式 World 与居民资料均已就绪"
							)
						)
					),
					"lastPlayedSlotId": String(
						startup_catalog.get("lastPlayedSlotId", ""),
					),
					"compactTownSummary": (
						"%s · 第 %d 天" % [
							String(saved_summary.get("slotName", "小镇")),
							int(saved_summary.get("day", 0)),
						]
						if has_formal_save
						else ""
					),
				},
				"draftRevision": 0,
				"identityStatus": "placeholder" if internal_playtest else "confirmed",
				"validationMode": validation_mode,
				"source": source,
				"capabilityMode": capability_mode,
				"formalReady": formal_route_ready,
				"internalPlaytest": internal_playtest,
				"internalLivePlaytest": false,
				"residentMessageSlotId": String(
					startup_catalog.get("lastPlayedSlotId", ""),
				),
				"residentMessages": (
					(startup_catalog.get("residentMessages", []) as Array).duplicate(true)
					if bool(startup_catalog.get("ok", false))
					else []
				),
			},
			"actions": {
				"newGame": {
					"intent": "session.new_game",
					"enabled": new_game_enabled,
					"disabledReason": new_game_error,
				},
				"continue": {
					"intent": "session.continue",
					"enabled": continue_enabled,
					"disabledReason": continue_reason,
				},
				"loadGame": {
					"intent": "startup.open_load_game",
					"enabled": not internal_playtest and bool(startup_catalog.get("ok", false)),
					"disabledReason": (
						""
						if not internal_playtest and bool(startup_catalog.get("ok", false))
						else "SESSION_CONTINUE_FORMAL_ONLY" if internal_playtest else String(
							startup_catalog.get("errorCode", "STARTUP_SAVE_CATALOG_UNAVAILABLE"),
						)
					),
				},
			},
			"operation": _idle_operation(),
			"error": null,
		},
		"save": {
			"scope": "save",
			"status": "ready",
			"revision": revision,
			"data": {
				"slots": startup_slots,
				"lastPlayedSlotId": String(
					startup_catalog.get("lastPlayedSlotId", ""),
				),
				"firstEmptySlotId": String(
					startup_catalog.get("firstEmptySlotId", ""),
				),
				"slotsFull": bool(startup_catalog.get("slotsFull", false)),
				"selectedSaveId": (
					"%s:%d" % [
						String(saved_summary.get("slotId", FORMAL_SLOT_ID)),
						int(saved_summary.get("saveRevision", 0)),
					]
					if has_formal_save
					else ""
				),
				"canSave": false,
				"canContinue": continue_enabled,
				"source": source,
				"capabilityMode": capability_mode,
				"formalReady": continue_formal_ready,
			},
			"actions": {
				"create": {
					"intent": "save.create",
					"enabled": false,
					"disabledReason": "SESSION_SAVE_REQUIRES_ACTIVE_SESSION",
				},
				"continue": {
					"intent": "session.continue",
					"enabled": continue_enabled,
					"disabledReason": continue_reason,
				},
			},
			"operation": _idle_operation(),
			"error": null,
		},
	}


func _startup_slot_projection(slot: Dictionary) -> Dictionary:
	var summary := slot.get("summary", {}) as Dictionary
	return {
		"slotId": String(slot.get("slotId", "")),
		"displayName": String(slot.get("displayName", "")),
		"sessionId": String(summary.get("sessionId", "")),
		"state": String(slot.get("state", "empty")),
		"recoveryState": String(slot.get("recoveryState", "none")),
		"continueAvailable": bool(slot.get("continueAvailable", false)),
		"requiresRecoveryConfirmation": bool(
			slot.get("requiresRecoveryConfirmation", false),
		),
		"recoveryProgressRollback": bool(
			slot.get("recoveryProgressRollback", false),
		),
		"saveId": (
			"%s:%d" % [
				String(slot.get("slotId", "")),
				int(summary.get("saveRevision", 0)),
			]
			if not summary.is_empty()
			else ""
		),
		"saveRevision": int(summary.get("saveRevision", 0)),
		"savedAt": String(summary.get("savedAt", "")),
		"residentCount": int(summary.get("residentCount", 0)),
		"day": int(summary.get("day", 0)),
		"worldRevision": int(summary.get("worldRevision", 0)),
		"errorCode": String(slot.get("errorCode", "")),
		"damageDetails": (
			slot.get("damageDetails", {}) as Dictionary
		).duplicate(true),
		"continueNotice": (
			slot.get("continueNotice", {}) as Dictionary
		).duplicate(true),
		"agentIntegrity": String(slot.get("agentIntegrity", "not_applicable")),
	}


func get_startup_load_game_view_model(mode := "load") -> Dictionary:
	var catalog := _startup_catalog_snapshot()
	var slots: Array[Dictionary] = []
	if bool(catalog.get("ok", false)):
		for slot_value: Variant in catalog.get("slots", []) as Array:
			if slot_value is Dictionary:
				slots.append(_startup_slot_projection(slot_value as Dictionary))
	var delete_available := false
	for projected_slot: Dictionary in slots:
		if String(projected_slot.get("state", "empty")) != "empty":
			delete_available = true
			break
	var error_code := String(catalog.get("errorCode", ""))
	return {
		"scope": "save",
		"status": "ready" if bool(catalog.get("ok", false)) else "error",
		"revision": maxi(_flow_generation, 1),
		"data": {
			"mode": String(mode),
			"pageTitle": "加载游戏" if String(mode) == "load" else "选择要覆盖的小镇",
			"slots": slots,
			"lastPlayedSlotId": String(catalog.get("lastPlayedSlotId", "")),
			"providerIndependent": true,
			"savedAtFormat": "full_local_datetime",
			"showsResidentCount": true,
			"showsRecoveryState": true,
		},
		"actions": {
			"back": {
				"intent": "startup.close_load_game",
				"enabled": true,
				"disabledReason": "",
			},
			"continueSlot": {
				"intent": "session.continue_slot",
				"enabled": not slots.is_empty(),
				"disabledReason": (
					"" if not slots.is_empty() else "SESSION_SAVE_NO_PUBLISHED_REVISION"
				),
			},
			"selectOverwriteSlot": {
				"intent": "startup.select_overwrite_slot",
				"enabled": String(mode) == "overwrite_selection",
				"disabledReason": (
					"" if String(mode) == "overwrite_selection" else "ACTION_NOT_AVAILABLE"
				),
			},
			"deleteSlot": {
				"intent": "save.request_delete_slot",
				"enabled": String(mode) == "load" and delete_available,
				"disabledReason": (
					""
					if String(mode) == "load" and delete_available
					else "SESSION_SAVE_NO_PUBLISHED_REVISION"
					if String(mode) == "load"
					else "ACTION_NOT_AVAILABLE_IN_MODE"
				),
			},
		},
		"operation": _idle_operation(),
		"error": (
			null
			if error_code.is_empty()
			else {
				"kind": "unavailable",
				"code": error_code,
				"retryable": bool(catalog.get("retryable", false)),
				"message": "本地小镇存档目录暂时不可用。",
				"details": [],
			}
		),
	}


func _startup_slot_by_id(catalog: Dictionary, slot_id: String) -> Dictionary:
	for slot_value: Variant in catalog.get("slots", []) as Array:
		if (
			slot_value is Dictionary
			and String((slot_value as Dictionary).get("slotId", "")) == slot_id
		):
			return (slot_value as Dictionary).duplicate(true)
	return {}


func _startup_delete_discovery(slot: Dictionary) -> Dictionary:
	var summary := (slot.get("summary", {}) as Dictionary).duplicate(true)
	if summary.is_empty():
		summary = {
			"slotId": String(slot.get("slotId", "")),
			"sessionId": "",
			"saveRevision": 0,
			"savedAt": "",
			"residentCount": 0,
			"worldRevision": 0,
			"day": 0,
		}
	var evidence := {
		"slotId": String(slot.get("slotId", "")),
		"state": String(slot.get("state", "empty")),
		"recoveryState": String(slot.get("recoveryState", "none")),
		"sessionId": String(summary.get("sessionId", "")),
		"saveRevision": int(summary.get("saveRevision", 0)),
	}
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"summary": summary,
		"displayName": String(slot.get("displayName", evidence["slotId"])),
		"slotState": String(slot.get("state", "empty")),
		"recoveryState": String(slot.get("recoveryState", "none")),
		"damageDetails": (
			slot.get("damageDetails", {}) as Dictionary
		).duplicate(true),
		"deleteEvidence": evidence,
	}


func _startup_continue_gate(
	internal_playtest: bool,
	world_ready: bool,
	catalog_ready: bool,
	save_discovery: Dictionary,
) -> Dictionary:
	var save_ready := bool(save_discovery.get("ok", false))
	var formal_ready := (
		not internal_playtest
		and world_ready
		and catalog_ready
		and save_ready
	)
	var disabled_reason := ""
	if not formal_ready:
		disabled_reason = (
			"SESSION_CONTINUE_FORMAL_ONLY"
			if internal_playtest
			else "WORLD_DATA_INCOMPLETE"
			if not world_ready
			else "FORMAL_SESSION_CATALOG_MISSING"
			if not catalog_ready
			else String(
				save_discovery.get(
					"errorCode",
					"SESSION_SAVE_NO_PUBLISHED_REVISION",
				),
			)
		)
	return {
		"enabled": formal_ready,
		"disabledReason": disabled_reason,
		"formalReady": formal_ready,
	}


func _idle_operation() -> Dictionary:
	return AiTownUiViewModel.idle_operation()


func _next_startup_view_model_revision() -> int:
	_startup_view_model_revision = maxi(
		_startup_view_model_revision + 1,
		_flow_generation,
	)
	return _startup_view_model_revision


func _build_internal_resident_selection_view_model() -> Dictionary:
	var catalog := _load_internal_catalog()
	if catalog == null:
		return {}
	var provider_id := OS.get_environment(INTERNAL_PROVIDER_ENV).strip_edges()
	if provider_id.is_empty():
		provider_id = "fake"
	var model_id := OS.get_environment(INTERNAL_MODEL_ENV).strip_edges()
	if model_id.is_empty():
		model_id = _default_model_id(provider_id)
	return _block_custom_resident_creation(
		catalog.call("build_view_model", provider_id, model_id) as Dictionary
	)


func _build_formal_resident_selection_view_model() -> Dictionary:
	var pool_result := _ensure_custom_resident_candidate_pool()
	if not bool(pool_result.get("ok", false)):
		_last_result = pool_result.duplicate(true)
		return {}
	var provider_id := ""
	var model_id := ""
	var provider_ready := false
	if _startup_provider_settings_service != null:
		var runtime_config := _startup_provider_settings_service.call(
			"runtime_configuration"
		) as Dictionary
		provider_id = String(runtime_config.get("providerId", ""))
		model_id = String(runtime_config.get("modelId", ""))
		var provider_vm := _startup_provider_settings_service.call(
			"get_view_model"
		) as Dictionary
		provider_ready = (
			bool(runtime_config.get("ok", false))
			and bool((provider_vm.get("data", {}) as Dictionary).get("formalReady", false))
		)
	var view_model := _block_custom_resident_creation(FORMAL_CATALOG.build_view_model(
		provider_id,
		model_id,
		provider_ready,
		maxi(_flow_generation, 1),
	) as Dictionary)
	return _merge_custom_candidate_projection(view_model)


func _block_custom_resident_creation(view_model: Dictionary) -> Dictionary:
	if view_model.is_empty():
		return view_model
	var data := view_model.get("data", {}) as Dictionary
	data["candidate_pool_revision"] = (
		int(_custom_resident_candidate_pool.candidate_pool_revision())
		if _custom_resident_candidate_pool != null
		else 0
	)
	var actions := view_model.get("actions", {}) as Dictionary
	var enabled := (
		CUSTOM_RESIDENT_CREATOR_MOUNTING_AUTHORIZED
		and not _internal_playtest_enabled()
	)
	actions["custom_resident"] = {
		"enabled": enabled,
		"disabled_reason": "" if enabled else CUSTOM_RESIDENT_CREATOR_BLOCKED_REASON,
	}
	actions["delete_custom_resident"] = {
		"enabled": enabled,
		"disabled_reason": "" if enabled else CUSTOM_RESIDENT_CREATOR_BLOCKED_REASON,
	}
	var selection_action := actions.get("selection", {}) as Dictionary
	var delete_enabled := bool(selection_action.get("enabled", false))
	actions["delete_residents"] = {
		"enabled": delete_enabled,
		"disabled_reason": (
			""
			if delete_enabled
			else String(selection_action.get("disabled_reason", "RESIDENT_SELECTION_DISABLED"))
		),
	}
	return view_model


func _update_confirmation_payload(data: Dictionary) -> void:
	if not _internal_playtest_enabled():
		var provider_id := ""
		var model_id := ""
		if _startup_provider_settings_service != null:
			var runtime_config := _startup_provider_settings_service.call(
				"runtime_configuration"
			) as Dictionary
			provider_id = String(runtime_config.get("providerId", ""))
			model_id = String(runtime_config.get("modelId", ""))
		FORMAL_CATALOG.update_confirmation_payload(
			data,
			provider_id,
			model_id,
			int(_resident_selection_vm.get("revision", 1)),
		)
		return
	var provider_id := OS.get_environment(INTERNAL_PROVIDER_ENV).strip_edges()
	if provider_id.is_empty():
		provider_id = "fake"
	var model_id := OS.get_environment(INTERNAL_MODEL_ENV).strip_edges()
	if model_id.is_empty():
		model_id = _default_model_id(provider_id)
	var catalog := _load_internal_catalog()
	if catalog == null:
		return
	catalog.call(
		"update_confirmation_payload",
		data,
		provider_id,
		model_id,
		int(_resident_selection_vm.get("revision", 1)),
	)


func _build_internal_catalog(world_data: Dictionary) -> Dictionary:
	var catalog := _load_internal_catalog()
	if catalog == null:
		return {}
	return catalog.call(
		"build_catalog",
		world_data,
		_resident_selection_vm,
	) as Dictionary


func _advance_resident_selection_revision() -> void:
	_resident_selection_vm["revision"] = int(_resident_selection_vm.get("revision", 0)) + 1
	var data := _resident_selection_vm.get("data", {}) as Dictionary
	var payload := data.get("confirmation_payload", {}) as Dictionary
	payload["draftRevision"] = int(_resident_selection_vm.get("revision", 1))
	_apply_resident_selection_view_model()


func _set_resident_selection_loading() -> void:
	if _resident_selection_vm.is_empty():
		return
	_resident_selection_vm["operation"] = {
		"requestId": "game-flow-%d" % _flow_generation,
		"intent": "session.new_game",
		"status": "loading",
		"submittedAtMsec": Time.get_ticks_msec(),
		"completedAtMsec": 0,
	}
	_resident_selection_vm["error"] = null
	_advance_resident_selection_revision()


func _set_resident_selection_result(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	_dismiss_town_entry_loading()
	if _resident_selection_vm.is_empty():
		return
	var retryable := bool(result.get("retryable", false))
	_resident_selection_vm["operation"] = {
		"requestId": "game-flow-%d" % _flow_generation,
		"intent": "session.new_game",
		"status": "error" if retryable else "rejected",
		"submittedAtMsec": 0,
		"completedAtMsec": Time.get_ticks_msec(),
	}
	_resident_selection_vm["error"] = {
		"kind": "transport" if retryable else "rejected",
		"code": String(result.get("errorCode", "SESSION_BOOTSTRAP_FAILED")),
		"retryable": retryable,
		"message": "",
		"details": (result.get("errors", []) as Array).duplicate(true),
	}
	_advance_resident_selection_revision()


func _set_resident_selection_delete_failure(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	if _resident_selection_vm.is_empty():
		return
	var retryable := bool(result.get("retryable", false))
	var error_code := String(result.get(
		"errorCode",
		"RESIDENT_DELETE_FAILED",
	))
	_resident_selection_vm["operation"] = {
		"requestId": "resident-delete-%d" % Time.get_ticks_msec(),
		"intent": "resident_selection.delete_residents",
		"status": "error" if retryable else "rejected",
		"submittedAtMsec": 0,
		"completedAtMsec": Time.get_ticks_msec(),
	}
	_resident_selection_vm["error"] = {
		"kind": "transport" if retryable else "rejected",
		"code": error_code,
		"retryable": retryable,
		"message": _resident_selection_delete_failure_message(error_code),
		"details": (result.get("errors", []) as Array).duplicate(true),
	}
	_advance_resident_selection_revision()


func _resident_selection_delete_failure_message(error_code: String) -> String:
	match error_code:
		"RESIDENT_DELETE_MINIMUM_CANDIDATES_REQUIRED":
			return "本局至少需要保留 15 名候选居民。"
		"RESIDENT_DELETE_REVISION_STALE", \
		"CUSTOM_RESIDENT_DELETE_REVISION_STALE", \
		"CUSTOM_RESIDENT_CANDIDATE_POOL_REVISION_STALE", \
		"CUSTOM_RESIDENT_LIBRARY_REVISION_STALE":
			return "居民名单已更新，请核对红色标记后重试。"
		"CUSTOM_RESIDENT_LIBRARY_WRITE_FAILED", \
		"CUSTOM_RESIDENT_LIBRARY_RECOVERY_FAILED":
			return "自定义居民库暂时无法保存，红色标记已保留，请重试。"
		"RESIDENT_DELETE_SELECTION_EMPTY":
			return "请先标记要删除的居民。"
		"RESIDENT_DELETE_CANDIDATE_NOT_FOUND", \
		"CUSTOM_RESIDENT_CANDIDATE_NOT_FOUND":
			return "所选居民已不在候选名单中，请重新选择。"
		_:
			return "当前无法删除居民，红色标记已保留。"


func _apply_resident_selection_view_model() -> void:
	if (
		_resident_selection != null
		and not _resident_selection_vm.is_empty()
		and _resident_selection.has_method("apply_view_model")
	):
		_resident_selection.call("apply_view_model", _resident_selection_vm.duplicate(true))


func _discard_pending_runtime() -> void:
	if _pending_runtime != null and is_instance_valid(_pending_runtime):
		_pending_runtime.free()
	_pending_runtime = null
	if _gateway != null and is_instance_valid(_gateway) and _gateway.get_parent() == null:
		_gateway.free()
	_gateway = null


func _discard_internal_agent_slot() -> Dictionary:
	if (
		_gateway == null
		or not is_instance_valid(_gateway)
	):
		return {"ok": true, "errorCode": "", "retryable": false, "changed": false}
	if not _gateway.has_method("discard_unpublished_new_game"):
		return _failure("AGENT_NEW_GAME_DISCARD_CONTRACT_MISSING", false)
	return _gateway.call("discard_unpublished_new_game") as Dictionary


func _prepare_session_departure(resident_messages: Array = []) -> Dictionary:
	if _town_runtime == null or not is_instance_valid(_town_runtime):
		return {"ok": true, "errorCode": "", "retryable": false, "changed": false}
	if _internal_playtest_enabled():
		return _discard_internal_agent_slot()
	if _session_ui_service == null:
		return _failure("SESSION_SAVE_SERVICE_NOT_CONFIGURED", false)
	if (
		is_instance_valid(_town_ui_host)
		and _town_ui_host.has_method("prepare_for_world_save")
	):
		var ui_barrier := (
			_town_ui_host.call(
				"prepare_for_world_save",
				"session_departure",
			) as Dictionary
		)
		if not bool(ui_barrier.get("ok", false)):
			return ui_barrier
	var snapshot := _session_ui_service.call("get_save_snapshot") as Dictionary
	if not bool(snapshot.get("canSave", false)):
		return _failure(
			String(snapshot.get("disabledReason", "SESSION_SAVE_NOT_AVAILABLE")),
			false,
		)
	var saved := _session_ui_service.call("create_save", {
		"reason": "session_departure",
		"residentMessages": resident_messages.duplicate(true),
	}) as Dictionary
	if not bool(saved.get("ok", false)):
		return saved
	if _gateway != null and _gateway.has_method("close_session"):
		var closed := _gateway.call("close_session") as Dictionary
		if not bool(closed.get("ok", false)):
			# The paired World/Agent save has already been published. Session
			# cleanup is best-effort and must not trap the player in the game or
			# turn a successful save into a reported failure.
			saved["agentCloseWarning"] = {
				"errorCode": String(closed.get(
					"errorCode",
					"AGENT_SESSION_CLOSE_FAILED",
				)),
				"retryable": bool(closed.get("retryable", false)),
			}
	return saved


func _discover_formal_save(
	include_config := false,
	test_store_root := "",
) -> Dictionary:
	if test_store_root.is_empty():
		var catalog := _startup_catalog_snapshot()
		if not bool(catalog.get("ok", false)):
			return catalog
		var slot := catalog.get("continueSlot", {}) as Dictionary
		if slot.is_empty() or not bool(slot.get("continueAvailable", false)):
			var error_code := String(slot.get("errorCode", "")).strip_edges()
			if error_code.is_empty():
				error_code = "SESSION_SAVE_NO_PUBLISHED_REVISION"
			return _failure(
				error_code,
				false,
			)
		return _catalog_slot_discovery(slot, include_config)
	var store: RefCounted = SESSION_SAVE_STORE.new()
	var configured := store.call(
		"configure_test_root",
		test_store_root,
	) as Dictionary
	if not bool(configured.get("ok", false)):
		return configured
	var listed := store.call("list_published", FORMAL_SLOT_ID) as Dictionary
	if not bool(listed.get("ok", false)):
		return listed
	var manifests := listed.get("manifests", []) as Array
	if manifests.is_empty():
		return _failure("SESSION_SAVE_NO_PUBLISHED_REVISION", false)
	var manifest := (manifests[0] as Dictionary).duplicate(true)
	var result := {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"manifest": manifest,
		"summary": SESSION_SAVE_MANIFEST.summary(manifest),
	}
	if not include_config:
		return result
	var loaded := store.call(
		"read_reference",
		String(manifest.get("session_config_ref", "")),
		String(manifest.get("session_config_sha256", "")),
	) as Dictionary
	if not bool(loaded.get("ok", false)):
		return loaded
	result["sessionConfig"] = (
		loaded.get("value", {}) as Dictionary
	).duplicate(true)
	return result


func _discover_startup_slot(slot_id: String, include_config := false) -> Dictionary:
	var catalog := _startup_catalog_snapshot()
	if not bool(catalog.get("ok", false)):
		return catalog
	for slot_value: Variant in catalog.get("slots", []) as Array:
		if not slot_value is Dictionary:
			continue
		var slot := slot_value as Dictionary
		if String(slot.get("slotId", "")) != slot_id:
			continue
		if not bool(slot.get("continueAvailable", false)):
			var error_code := String(slot.get("errorCode", "")).strip_edges()
			if error_code.is_empty():
				error_code = "SESSION_SAVE_NO_PUBLISHED_REVISION"
			return _failure(
				error_code,
				false,
			)
		return _catalog_slot_discovery(slot, include_config)
	return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)


func _catalog_slot_discovery(slot: Dictionary, include_config: bool) -> Dictionary:
	var manifest := (slot.get("manifest", {}) as Dictionary).duplicate(true)
	var summary := (slot.get("summary", {}) as Dictionary).duplicate(true)
	if manifest.is_empty() or summary.is_empty():
		return _failure("SESSION_SAVE_NO_PUBLISHED_REVISION", false)
	var result := {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"manifest": manifest,
		"summary": summary,
		"slotState": String(slot.get("state", "healthy")),
		"recoveryState": String(slot.get("recoveryState", "current")),
		"requiresRecoveryConfirmation": bool(
			slot.get("requiresRecoveryConfirmation", false),
		),
		"recoveryProgressRollback": bool(
			slot.get("recoveryProgressRollback", false),
		),
		"damageDetails": (
			slot.get("damageDetails", {}) as Dictionary
		).duplicate(true),
		"continueNotice": (
			slot.get("continueNotice", {}) as Dictionary
		).duplicate(true),
		"agentIntegrity": String(
			slot.get("agentIntegrity", "manifest_committed_unverified"),
		),
	}
	if include_config:
		result["sessionConfig"] = (
			slot.get("sessionConfig", {}) as Dictionary
		).duplicate(true)
	return result


func _startup_catalog_snapshot() -> Dictionary:
	var interrupted_recovery := _recover_interrupted_formal_overwrites()
	if not bool(interrupted_recovery.get("ok", false)):
		return interrupted_recovery
	if _startup_save_catalog == null:
		return _failure("STARTUP_SAVE_CATALOG_CONTRACT_INVALID", false)
	return _startup_save_catalog.call(
		"get_catalog",
		FORMAL_SLOT_DEFINITIONS.duplicate(true),
	) as Dictionary


func _recover_interrupted_formal_overwrites() -> Dictionary:
	return _overwrite_compensator.recover_interrupted(
		_internal_playtest_enabled(),
		FORMAL_SLOT_DEFINITIONS,
		_resolve_formal_archive_service(),
	)


func _record_last_played_slot(slot_id: String) -> Dictionary:
	if _startup_save_catalog == null:
		return _failure("STARTUP_SAVE_CATALOG_CONTRACT_INVALID", false)
	var slot_ids: Array[String] = []
	for definition_value: Variant in FORMAL_SLOT_DEFINITIONS:
		var definition := definition_value as Dictionary
		slot_ids.append(String(definition.get("slotId", "")))
	return _startup_save_catalog.call(
		"record_last_played",
		slot_id,
		slot_ids,
	) as Dictionary


func _record_startup_resident_message_receipt(payload: Dictionary) -> void:
	if _startup_save_catalog == null:
		_last_result = _failure(
			"STARTUP_SAVE_CATALOG_CONTRACT_INVALID",
			false,
		)
		return
	var slot_ids: Array[String] = []
	for definition_value: Variant in FORMAL_SLOT_DEFINITIONS:
		var definition := definition_value as Dictionary
		slot_ids.append(String(definition.get("slotId", "")))
	var recorded := _startup_save_catalog.call(
		"record_resident_messages_shown",
		payload.get("slotId"),
		payload.get("messageIds"),
		slot_ids,
	) as Dictionary
	if not bool(recorded.get("ok", false)):
		_last_result = recorded.duplicate(true)


func _publish_startup_result(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	var loading_owner := _town_entry_loading_owner
	var loading_context := _town_entry_loading_context.duplicate(true)
	_dismiss_town_entry_loading()
	if (
		loading_owner == "startup_load_game"
		and is_instance_valid(_startup_load_game_page)
	):
		_publish_startup_load_game_result(result, loading_context)
		return
	var startup := get_tree().current_scene
	if startup == null or startup.name != "StartupScreen":
		return
	var models := _build_startup_view_models()
	for scope in ["session", "save"]:
		var view_model := models.get(scope, {}) as Dictionary
		view_model["operation"] = {
			"requestId": "startup-%d" % _flow_generation,
			"intent": "session.continue",
			"status": (
				"error" if bool(result.get("retryable", false)) else "rejected"
			),
			"submittedAtMsec": 0,
			"completedAtMsec": Time.get_ticks_msec(),
		}
		view_model["error"] = {
			"kind": "transport" if bool(result.get("retryable", false)) else "rejected",
			"code": String(result.get("errorCode", "SESSION_CONTINUE_FAILED")),
			"retryable": bool(result.get("retryable", false)),
			"message": _startup_failure_message(result, "继续游戏失败"),
			"details": (result.get("errors", []) as Array).duplicate(true),
		}
	if startup.has_method("apply_view_models"):
		startup.call("apply_view_models", models["session"], models["save"])


func _publish_startup_load_game_result(
	result: Dictionary,
	loading_context: Dictionary,
) -> void:
	if not is_instance_valid(_startup_load_game_page):
		return
	var view_model := get_startup_load_game_view_model("load")
	view_model["status"] = (
		"error" if bool(result.get("retryable", false)) else "rejected"
	)
	view_model["operation"] = {
		"requestId": "startup-load-%d" % _flow_generation,
		"intent": "session.continue_slot",
		"status": (
			"error" if bool(result.get("retryable", false)) else "rejected"
		),
		"submittedAtMsec": 0,
		"completedAtMsec": Time.get_ticks_msec(),
	}
	view_model["error"] = {
		"kind": "transport" if bool(result.get("retryable", false)) else "rejected",
		"code": String(result.get("errorCode", "SESSION_CONTINUE_FAILED")),
		"retryable": bool(result.get("retryable", false)),
		"message": _startup_failure_message(result, "加载存档失败"),
		"details": (result.get("errors", []) as Array).duplicate(true),
	}
	_startup_load_game_page.call("apply_view_model", view_model)
	_restore_startup_load_game_focus.call_deferred(
		String(loading_context.get("slotId", "")),
	)


func _restore_startup_load_game_focus(slot_id: String) -> void:
	if not is_instance_valid(_startup_load_game_page):
		return
	for node: Node in _startup_load_game_page.find_children(
		"*",
		"Button",
		true,
		false,
	):
		var button := node as Button
		if (
			button != null
			and not button.disabled
			and String(button.get_meta("slot_id", "")) == slot_id
			and String(button.get_meta("action_key", "")) != "deleteSlot"
		):
			button.grab_focus()
			return


func _startup_failure_message(result: Dictionary, prefix: String) -> String:
	var error_code := String(
		result.get("errorCode", "SESSION_CONTINUE_FAILED")
	).strip_edges()
	if error_code.is_empty():
		error_code = "SESSION_CONTINUE_FAILED"
	var player_code := UI_VIEW_MODEL.player_reason(error_code)
	var player_message := _explicit_player_message(result)
	if player_message.is_empty():
		player_message = player_code
	if player_message.is_empty() or player_message == "当前操作暂不可用":
		player_message = "请稍后重试"
	return "%s：%s" % [prefix, player_message]


func _default_model_id(provider_id: String) -> String:
	var catalog := _load_internal_catalog()
	if catalog == null:
		return ""
	return String(catalog.call("default_model_id", provider_id))


func _load_internal_catalog() -> Script:
	if not _internal_playtest_enabled():
		return null
	return load(INTERNAL_CATALOG_PATH) as Script


func _apply_window_mode_marker() -> void:
	DisplayServer.window_set_title(
		INTERNAL_WINDOW_TITLE if _internal_playtest_enabled() else FORMAL_WINDOW_TITLE
	)


func _internal_playtest_enabled() -> bool:
	return (
		OS.is_debug_build()
		and OS.get_environment(INTERNAL_PLAYTEST_ENV) == "1"
	)


func _route_name(scene: Node) -> String:
	if scene == null:
		return "none"
	if scene.name == "StartupScreen":
		return "startup"
	if scene.name == "WorldIntroScreen":
		return "world_intro"
	if scene.name == "ResidentSelectionScreen":
		if is_instance_valid(_custom_resident_creator_page):
			return "custom_resident_creator"
		if is_instance_valid(_resident_model_assignment_page):
			return "resident_model_assignment"
		return "resident_selection"
	if scene.has_method("get_world_runtime"):
		return "town"
	return String(scene.name)


func _adapter_action_enabled(scope: String, action_name: String) -> bool:
	if _town_runtime == null or not is_instance_valid(_town_runtime):
		return false
	var adapter: Node = _town_runtime.call("get_ui_adapter")
	if adapter == null or not adapter.has_method("get_view_model"):
		return false
	var view_model := adapter.call("get_view_model", scope) as Dictionary
	var action := (
		view_model.get("actions", {}) as Dictionary
	).get(action_name, {}) as Dictionary
	return bool(action.get("enabled", false))


func _connect_once(target: Object, signal_name: String, callback: Callable) -> void:
	if target.has_signal(signal_name) and not target.is_connected(signal_name, callback):
		target.connect(signal_name, callback)


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _failure(error_code: String, retryable: bool, errors: Array = []) -> Dictionary:
	return RESULT_SHAPES.failure_with(error_code, retryable, errors)
