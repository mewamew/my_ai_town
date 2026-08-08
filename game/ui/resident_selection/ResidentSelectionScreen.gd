extends Control


const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")


const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")


signal resident_selection_requested(resident_id: String, should_select: bool, revision: int)
signal recommended_selection_requested(revision: int)
signal selection_clear_requested(revision: int)
signal roster_confirmation_requested(confirmation_payload: Dictionary, revision: int)
signal custom_resident_requested(revision: int)
signal custom_resident_delete_requested(
	resident_id: String,
	candidate_pool_revision: int,
	revision: int,
)
signal residents_delete_requested(
	resident_ids: Array,
	candidate_pool_revision: int,
	revision: int,
)
signal back_requested(revision: int)


enum LayoutMode {
	DESKTOP,
	STANDARD,
	TABLET,
	PHONE_LANDSCAPE,
	PHONE_PORTRAIT,
}


enum DetailMode {
	SHOWCASE,
	OVERVIEW,
}


const WORLD_BACKDROP_PATH := (
	"res://assets/ui/opening_flow/shared/background/"
	+ "opening_flow_town_background_v1.png"
)
const UI_SHELL_PATH := (
	"res://assets/ui/resident_selection/final/"
	+ "resident_selection_showcase_foreground_v49.png"
)
const OVERVIEW_DETAIL_OVERLAY_PATH := (
	"res://assets/ui/resident_selection/final/"
	+ "resident_selection_overview_detail_overlay_v49.png"
)
const RESIDENT_CARD_MODULE_PATH := (
	"res://assets/ui/resident_selection/final/resident_card_module_v45.png"
)
const COMPACT_UI_SHELL_PATH := (
	"res://assets/ui/resident_selection/final/resident_selection_shell_v4.png"
)
const UI_FONT_PATH := (
	"res://assets/fonts/zheng_ge_dian_hei_16/"
	+ "ZhengGeDianHei-16.ttf"
)
const GLOBAL_UI_THEME_PATH := "res://ui/common/system_feedback/SystemFeedbackTheme.tres"
const ICON_ROOT := "res://assets/ui/resident_selection/icons_v2/"
const OVERVIEW_BOOK_ICON_PATH := ICON_ROOT + "overview_book_v49_cropped.png"
const OVERVIEW_SCROLL_TRACK_PATH := ICON_ROOT + "overview_scroll_track_v49_cropped.png"
const OVERVIEW_SCROLL_THUMB_PATH := ICON_ROOT + "overview_scroll_thumb_v49_cropped.png"
const CUSTOM_DELETE_BUTTON_ROOT := (
	"res://assets/ui/settings/final/controls/v2/button_square_sized/"
)
const CUSTOM_DELETE_BUTTON_NORMAL_PATH := CUSTOM_DELETE_BUTTON_ROOT + "normal.png"
const CUSTOM_DELETE_BUTTON_HOVER_PATH := CUSTOM_DELETE_BUTTON_ROOT + "hover.png"
const CUSTOM_DELETE_BUTTON_PRESSED_PATH := CUSTOM_DELETE_BUTTON_ROOT + "pressed.png"
const CUSTOM_DELETE_BUTTON_DISABLED_PATH := CUSTOM_DELETE_BUTTON_ROOT + "disabled.png"
const COMPLETE_SET_WARDROBE_CATALOG_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
	+ "wardrobe_catalog.json"
)

const FONT_NATIVE_GRID := 16
const FONT_CAPTION := 16
const FONT_CARD := 18
const FONT_CARD_NAME := 20
const FONT_STATUS := 20
const FONT_BODY := 32
const FONT_EMPHASIS := 48
const LINE_SPACING := 6
const STRICT_SESSION_SLOT_COUNT := 15
const SELECTION_SUMMARY_MAX_CHARACTERS := 24
const TOUCH_TARGET_MIN := 48

const DESKTOP_CANVAS := Vector2(1920.0, 1080.0)
const STANDARD_CANVAS := Vector2(1280.0, 720.0)

const COLOR_INK := Color("3f2818")
const COLOR_MUTED := Color("76583d")
const COLOR_PAPER := Color("fff0cc")
const COLOR_GREEN := Color("557b2a")
const COLOR_GREEN_DARK := Color("36511e")
const COLOR_TERRACOTTA := Color("b94d2d")
const COLOR_WOOD := Color("6c3d20")

const OPERATION_STRESS_TEXTS := {
	"normal": "确认居民名单",
	"loading": "正在检查连接",
	"success": "名单已确认",
	"rejected": "名单需要调整",
	"error": "连接暂不可用",
	"disabled": "真实 AI 尚未连接",
}


var _residents: Array[Dictionary] = []
var _selected_by_id: Dictionary = {}
var _delete_selected_by_id: Dictionary = {}
var _delete_mode_active := false
var _recommended_ids: Array[String] = []
var _view_model: Dictionary = {}
var _view_model_actions: Dictionary = {}
var _view_model_revision := 0
var _candidate_pool_revision := 0
var _selection_limit := STRICT_SESSION_SLOT_COUNT
var _connection_label := "开发占位 · 未连接真实 AI"
var _formal_ready := false
var _capability_mode := "placeholder"
var _data_source := "placeholder"
var _resident_catalog_status := "placeholder"
var _internal_playtest := false
var _confirmation_payload: Dictionary = {}
var _draft_revision_floor := 0
var _operation: Dictionary = {}
var _error_value: Variant = null
var _focused_index := 0
var _mobile_detail_open := false
var _resident_page := 0
const RESIDENTS_PER_DESKTOP_PAGE := 6
var _detail_mode := DetailMode.SHOWCASE
var _resident_catalog_by_id: Dictionary = {}
var _detail_walk_frame := 0
var _detail_walk_sheet_path := ""
var _detail_walk_texture: AtlasTexture
var _detail_walk_timer: Timer
var _detail_walk_frame_size := Vector2(64, 80)
var _detail_walk_vertical := false
var _complete_set_sheet_by_appearance: Dictionary = {}

var _layout_mode := LayoutMode.DESKTOP
var _test_previous_content_scale_size := Vector2i.ZERO
var _test_previous_window_size := Vector2i.ZERO
var _functional_regression_active := false
var _content_root: Control
var _world_backdrop: TextureRect
var _shell: TextureRect
var _overview_shell_overlay: TextureRect
var _town_clock: TextureRect
var _back_button: Button
var _back_text: Label
var _title: Label
var _subtitle: Label
var _breadcrumb: HBoxContainer
var _breadcrumb_labels: Array[Label] = []
var _custom_button: Button
var _custom_delete_button: Button
var _connection_box: MarginContainer
var _connection_icon: TextureRect
var _connection_status: Label
var _notice_label: Label
var _roster_scroll: ScrollContainer
var _resident_grid: GridContainer
var _page_previous_button: Button
var _page_status_label: Label
var _page_next_button: Button
var _detail_panel: Control
var _detail_sprite: TextureRect
var _detail_name: Label
var _detail_identity_title: Label
var _detail_meta: Label
var _detail_coffee_icon: TextureRect
var _detail_location_icon: TextureRect
var _detail_location: Label
var _detail_role: Label
var _detail_personality_icon: TextureRect
var _detail_personality_title: Label
var _detail_personality: Label
var _detail_desire_icon: TextureRect
var _detail_desire_title: Label
var _detail_desire: Label
var _detail_speech_icon: TextureRect
var _detail_speech_title: Label
var _detail_speech: Label
var _overview_scroll: ScrollContainer
var _overview_scroll_content: VBoxContainer
var _overview_scroll_track: TextureRect
var _overview_scroll_thumb: TextureRect
var _overview_scroll_dragging := false
var _overview_scroll_drag_offset := 0.0
var _overview_button: Button
var _overview_icon: TextureRect
var _overview_text: Label
var _detail_toggle_button: Button
var _detail_toggle_icon: TextureRect
var _detail_toggle_text: Label
var _footer: Control
var _count_label: Label
var _recommended_button: Button
var _recommended_icon: TextureRect
var _recommended_text: Label
var _clear_button: Button
var _clear_icon: TextureRect
var _clear_text: Label
var _confirm_button: Button
var _confirm_icon: TextureRect
var _confirm_text: Label
var _notice_tween: Tween
var _connection_tween: Tween
var _responsive_layout_queued := false
var _env_capture_operation_state := ""
var _env_capture_connection_state := ""
var _env_detail_content_stress := ""
var _env_safe_insets_raw := ""

var _card_roots: Array[Control] = []
var _card_backgrounds: Array[TextureRect] = []
var _card_focus_buttons: Array[Button] = []
var _card_portraits: Array[TextureRect] = []
var _card_number_labels: Array[Label] = []
var _card_name_slots: Array[MarginContainer] = []
var _card_name_labels: Array[Label] = []
var _card_job_labels: Array[Label] = []
var _card_location_labels: Array[Label] = []
var _card_location_icons: Array[TextureRect] = []
var _card_toggle_buttons: Array[Button] = []
var _card_state_icons: Array[TextureRect] = []

var _text_audit_entries: Array[Dictionary] = []
var _touch_audit_entries: Array[Dictionary] = []


func _enter_tree() -> void:
	var requested_size := _requested_viewport_size()
	if requested_size == Vector2i.ZERO:
		return
	var window := get_window()
	_test_previous_content_scale_size = window.content_scale_size
	_test_previous_window_size = DisplayServer.window_get_size()
	DisplayServer.window_set_size(requested_size)
	window.size = requested_size
	window.content_scale_size = requested_size


func _exit_tree() -> void:
	if _test_previous_window_size != Vector2i.ZERO:
		DisplayServer.window_set_size(_test_previous_window_size)
		get_window().size = _test_previous_window_size
	if _test_previous_content_scale_size != Vector2i.ZERO:
		get_window().content_scale_size = _test_previous_content_scale_size


func _ready() -> void:
	# 测试夹具环境变量启动时读一次，不进每次刷新/布局热路径。
	if OS.is_debug_build():
		_env_capture_operation_state = OS.get_environment(
			"AI_TOWN_CAPTURE_OPERATION_STATE"
		).strip_edges()
		_env_capture_connection_state = OS.get_environment(
			"AI_TOWN_CAPTURE_CONNECTION_STATE"
		).strip_edges()
		_env_detail_content_stress = OS.get_environment(
			"AI_TOWN_DETAIL_CONTENT_STRESS"
		)
		_env_safe_insets_raw = OS.get_environment(
			"AI_TOWN_SAFE_INSETS"
		).strip_edges()
	var entry_profile_enabled := (
		OS.is_debug_build()
		and OS.get_environment("AI_TOWN_ENTRY_PROFILE") == "1"
	)
	var entry_profile_metrics: Dictionary = {}
	var entry_profile_tick := Time.get_ticks_usec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	RenderingServer.set_default_clear_color(Color("152d25"))
	_load_typography()
	if entry_profile_enabled:
		entry_profile_tick = _record_entry_profile_phase(
			entry_profile_metrics, "typographyMsec", entry_profile_tick
		)
	if _view_model.is_empty():
		return
	visible = true
	if entry_profile_enabled:
		entry_profile_tick = _record_entry_profile_phase(
			entry_profile_metrics, "viewModelMsec", entry_profile_tick
		)
	_build_page()
	if entry_profile_enabled:
		entry_profile_tick = _record_entry_profile_phase(
			entry_profile_metrics, "buildPageMsec", entry_profile_tick
		)
	_refresh_all()
	if entry_profile_enabled:
		entry_profile_tick = _record_entry_profile_phase(
			entry_profile_metrics, "refreshAllMsec", entry_profile_tick
		)
	_focus_resident(_focused_index, false)
	if entry_profile_enabled:
		entry_profile_tick = _record_entry_profile_phase(
			entry_profile_metrics, "focusResidentMsec", entry_profile_tick
		)
	# 两个信号常在同一帧先后触发，延迟合并成一次布局。
	get_viewport().size_changed.connect(_queue_responsive_layout)
	resized.connect(_queue_responsive_layout)
	_apply_responsive_layout()
	if entry_profile_enabled:
		entry_profile_tick = _record_entry_profile_phase(
			entry_profile_metrics, "responsiveLayoutMsec", entry_profile_tick
		)
	_start_connection_animation()
	if entry_profile_enabled:
		_record_entry_profile_phase(
			entry_profile_metrics, "connectionPresentationMsec", entry_profile_tick
		)
		print("RESIDENT_SELECTION_ENTRY_PROFILE %s" % JSON.stringify(entry_profile_metrics))
	if (
		OS.is_debug_build()
		and OS.get_environment("AI_TOWN_DETAIL_STATE") == "overview"
	):
		_open_resident_overview()
func _record_entry_profile_phase(
	metrics: Dictionary,
	phase: String,
	previous_usec: int,
) -> int:
	var now := Time.get_ticks_usec()
	metrics[phase] = snappedf(float(now - previous_usec) / 1000.0, 0.01)
	return now


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			_request_back(false)
			get_viewport().set_input_as_handled()
		KEY_ENTER:
			_confirm_roster()
		KEY_R:
			_apply_recommended_selection()


func _input(event: InputEvent) -> void:
	if not _overview_scroll_dragging:
		return
	if event is InputEventMouseMotion:
		_set_overview_scroll_from_global_y((event as InputEventMouseMotion).global_position.y)
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed:
			_overview_scroll_dragging = false


func apply_view_model(snapshot: Dictionary) -> bool:
	var previous_candidate_count := _residents.size()
	var delete_commit_pending := _delete_mode_active and previous_candidate_count > 0
	if not _consume_view_model(snapshot):
		return false
	if delete_commit_pending and _residents.size() < previous_candidate_count:
		_delete_mode_active = false
		_delete_selected_by_id.clear()
	if is_node_ready() and not _card_roots.is_empty():
		if previous_candidate_count != _residents.size():
			_rebuild_page_for_candidate_pool_change()
		else:
			_refresh_all()
			_start_connection_animation()
	elif is_node_ready():
		visible = true
		_build_page()
		_refresh_all()
		_focus_resident(_focused_index, false)
		if not get_viewport().size_changed.is_connected(_apply_responsive_layout):
			get_viewport().size_changed.connect(_apply_responsive_layout)
		if not resized.is_connected(_apply_responsive_layout):
			resized.connect(_apply_responsive_layout)
		_apply_responsive_layout()
		_start_connection_animation()
	return true


func _requested_viewport_size() -> Vector2i:
	if not OS.is_debug_build():
		return Vector2i.ZERO
	var raw := OS.get_environment("AI_TOWN_UI_VIEWPORT").strip_edges().to_lower()
	var pieces := raw.split("x")
	if pieces.size() != 2:
		return Vector2i.ZERO
	var width := int(pieces[0])
	var height := int(pieces[1])
	if width <= 0 or height <= 0:
		return Vector2i.ZERO
	return Vector2i(width, height)


func runtime_layout_snapshot() -> Dictionary:
	var viewport_rect := get_global_rect()
	var out_of_bounds: Array[String] = []
	var controls: Array[Control] = [
		_back_button,
		_title,
		_custom_button,
		_connection_box,
		_roster_scroll,
		_detail_panel,
		_footer,
		_recommended_button,
		_clear_button,
		_confirm_button,
	]
	for control: Control in controls:
		if control == null or not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		if (
			rect.position.x < viewport_rect.position.x - 1.0
			or rect.position.y < viewport_rect.position.y - 1.0
			or rect.end.x > viewport_rect.end.x + 1.0
			or rect.end.y > viewport_rect.end.y + 1.0
		):
			out_of_bounds.append(String(control.name))
	return {
		"layoutMode": _layout_mode_name(_layout_mode),
		"viewportRect": _rect_json(viewport_rect),
		"contentRootRect": (
			_rect_json(_content_root.get_global_rect())
			if _content_root != null
			else {}
		),
		"contentRootScale": (
			[_content_root.scale.x, _content_root.scale.y]
			if _content_root != null
			else [0.0, 0.0]
		),
		"source": _data_source,
		"capabilityMode": _capability_mode,
		"formalReady": _formal_ready,
		"candidatePoolRevision": _candidate_pool_revision,
		"outOfBounds": out_of_bounds,
	}


func _consume_view_model(snapshot: Dictionary) -> bool:
	var required_root_fields := [
		"scope", "status", "revision", "data", "actions", "operation", "error"
	]
	for field: String in required_root_fields:
		if not snapshot.has(field):
			push_error("居民选择页 ViewModel 缺少字段：%s" % field)
			return false
	if str(snapshot.get("scope", "")) != "resident_selection":
		push_error("居民选择页 ViewModel scope 错误。")
		return false
	if str(snapshot.get("status", "")) != "ready":
		push_error("居民选择页 ViewModel 尚未 ready。")
		return false
	var data_value: Variant = snapshot.get("data", {})
	var actions_value: Variant = snapshot.get("actions", {})
	if not data_value is Dictionary or not actions_value is Dictionary:
		push_error("居民选择页 ViewModel data/actions 结构错误。")
		return false
	var data := data_value as Dictionary
	var required_data_fields := [
		"capabilityMode",
		"source",
		"formalReady",
		"internalPlaytest",
		"selection_limit",
		"connection_label",
		"candidate_pool_revision",
		"focused_resident_id",
		"selected_resident_ids",
		"recommended_resident_ids",
		"confirmation_payload",
		"resident_catalog_status",
		"resident_catalog",
		"residents",
	]
	for field: String in required_data_fields:
		if not data.has(field):
			push_error("居民选择页 ViewModel data 缺少字段：%s" % field)
			return false
	var resident_entries: Variant = data.get("residents", [])
	if (
		not resident_entries is Array
		or resident_entries.size() < STRICT_SESSION_SLOT_COUNT
	):
		push_error("居民选择页本局候选列表至少需要 15 位居民。")
		return false

	_view_model = snapshot.duplicate(true)
	_view_model_revision = int(snapshot.get("revision", 0))
	_view_model_actions = (actions_value as Dictionary).duplicate(true)
	_selection_limit = int(data.get("selection_limit", STRICT_SESSION_SLOT_COUNT))
	if _selection_limit != STRICT_SESSION_SLOT_COUNT:
		push_error("居民选择页 selection_limit 必须固定为 15。")
		return false
	_connection_label = str(data.get("connection_label", "开发占位 · 未连接真实 AI"))
	_candidate_pool_revision = int(data.get("candidate_pool_revision", 0))
	_formal_ready = bool(data.get("formalReady", false))
	_capability_mode = str(data.get("capabilityMode", "placeholder"))
	_data_source = str(data.get("source", "placeholder"))
	_resident_catalog_status = str(data.get("resident_catalog_status", "placeholder"))
	_internal_playtest = bool(data.get("internalPlaytest", false))
	_confirmation_payload = _normalize_roster_draft_for_selection(
		data.get("confirmation_payload", {}) as Dictionary
	)
	_draft_revision_floor = maxi(
		_draft_revision_floor,
		int(_confirmation_payload.get("draftRevision", 0))
	)
	_operation = (snapshot.get("operation", {}) as Dictionary).duplicate(true)
	_error_value = snapshot.get("error")
	_resident_catalog_by_id.clear()
	for catalog_value: Variant in data.get("resident_catalog", []) as Array:
		if not catalog_value is Dictionary:
			continue
		var catalog_entry := catalog_value as Dictionary
		var catalog_resident_id := str(catalog_entry.get("residentId", ""))
		if not catalog_resident_id.is_empty():
			_resident_catalog_by_id[catalog_resident_id] = catalog_entry.duplicate(true)

	_residents.clear()
	var candidate_ids: Dictionary = {}
	for entry: Variant in resident_entries:
		if entry is Dictionary:
			var resident := _normalize_resident_for_selection(entry as Dictionary)
			var resident_id := str(resident.get("resident_id", ""))
			if resident_id.is_empty() or candidate_ids.has(resident_id):
				push_error("居民选择页预设候选 resident_id 缺失或重复。")
				return false
			var catalog_entry := (
				_resident_catalog_by_id.get(resident_id, {}) as Dictionary
			)
			var catalog_attributes := (
				catalog_entry.get("attributes", {}) as Dictionary
			)
			if str(resident.get("speech", "")).strip_edges().is_empty():
				resident["speech"] = str(catalog_attributes.get("speech", "")).strip_edges()
			candidate_ids[resident_id] = true
			_residents.append(resident)
	if _residents.size() < STRICT_SESSION_SLOT_COUNT:
		push_error("居民选择页必须至少保留 15 名候选居民。")
		return false
	for deleted_id: Variant in _delete_selected_by_id.keys():
		if not candidate_ids.has(String(deleted_id)):
			_delete_selected_by_id.erase(deleted_id)

	_recommended_ids.clear()
	for resident_id: Variant in data.get("recommended_resident_ids", []):
		_recommended_ids.append(str(resident_id))
	_selected_by_id.clear()
	for resident_id: Variant in data.get("selected_resident_ids", []):
		_selected_by_id[str(resident_id)] = true

	var focused_resident_id := str(data.get("focused_resident_id", ""))
	_focused_index = 0
	for index in range(_residents.size()):
		if str(_residents[index].get("resident_id", "")) == focused_resident_id:
			_focused_index = index
			break
	_resident_page = floori(
		float(_focused_index) / float(RESIDENTS_PER_DESKTOP_PAGE)
	)
	return true


func _normalize_resident_for_selection(source: Dictionary) -> Dictionary:
	var resident := source.duplicate(true)
	var selection_summary := _normalize_selection_summary_text(str(
		resident.get(
			"selection_summary",
			resident.get(
				"selectionSummary",
				resident.get("one_line_role", "")
			)
		)
	))
	if selection_summary.is_empty():
		selection_summary = _normalize_selection_summary_text(
			str(resident.get("personality", ""))
		)
	resident["selection_summary"] = selection_summary
	return resident


func _normalize_selection_summary_text(value: String) -> String:
	return (
		value
		.replace("\r\n", " ")
		.replace("\r", " ")
		.replace("\n", " ")
		.replace("\t", " ")
		.strip_edges()
	)


func _normalize_roster_draft_for_selection(source: Dictionary) -> Dictionary:
	if source.is_empty():
		return {}
	var slots: Array[Dictionary] = []
	var source_slots: Variant = source.get("slots", [])
	if source_slots is Array:
		for value: Variant in source_slots as Array:
			if not value is Dictionary:
				continue
			var slot := value as Dictionary
			slots.append({
				"residentId": str(slot.get("residentId", "")),
				"spaceId": str(slot.get("spaceId", "")),
			})
	return {
		"schemaVersion": int(source.get("schemaVersion", 0)),
		"sourceScope": str(source.get("sourceScope", "")),
		"draftRevision": int(source.get("draftRevision", 0)),
		"slots": slots,
	}


func _rebuild_page_for_candidate_pool_change() -> void:
	UiNodeRetirement.retire_children(self)
	_card_roots.clear()
	_card_backgrounds.clear()
	_card_focus_buttons.clear()
	_card_portraits.clear()
	_card_number_labels.clear()
	_card_name_slots.clear()
	_card_name_labels.clear()
	_card_job_labels.clear()
	_card_location_labels.clear()
	_card_location_icons.clear()
	_card_toggle_buttons.clear()
	_card_state_icons.clear()
	_breadcrumb_labels.clear()
	_text_audit_entries.clear()
	_touch_audit_entries.clear()
	_focused_index = clampi(_focused_index, 0, _residents.size() - 1)
	_build_page()
	_refresh_all()
	_focus_resident(_focused_index, false)
	_apply_responsive_layout()
	_start_connection_animation()


func _build_error_screen() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("2f241b")
	add_child(backdrop)
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = "居民选择页 ViewModel 读取失败\n请检查 resident_selection_mock.json"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_BODY)
	label.add_theme_color_override("font_color", COLOR_PAPER)
	add_child(label)


func _load_typography() -> void:
	_shared_ui_theme = ResourceLoader.load(GLOBAL_UI_THEME_PATH, "Theme") as Theme
	if _shared_ui_theme == null:
		push_error("居民选择页全局 Theme 读取失败：%s" % GLOBAL_UI_THEME_PATH)
		return
	_ui_font = _shared_ui_theme.get_font("font", "FeedbackBody")
	_ui_medium_font = _shared_ui_theme.get_font("font", "FeedbackCompact")
	_ui_bold_font = _shared_ui_theme.get_font("font", "FeedbackDialogTitle")
	if _ui_font == null or _ui_medium_font == null or _ui_bold_font == null:
		push_error("居民选择页缺少全局 Theme 字体 variation。")
		return
	_ui_resident_name_font = _ui_bold_font
	if _ui_bold_font is FontVariation:
		var resident_name_variation := (
			(_ui_bold_font as FontVariation).duplicate(true) as FontVariation
		)
		resident_name_variation.variation_embolden = 0.55
		resident_name_variation.spacing_glyph = 2
		_ui_resident_name_font = resident_name_variation


var _ui_font: Font
var _ui_medium_font: Font
var _ui_bold_font: Font
var _ui_resident_name_font: Font
var _shared_ui_theme: Theme
static var _alpha_cropped_texture_cache: Dictionary = {}
static var _imported_texture_cache: Dictionary = {}
static var _flat_style_cache: Dictionary = {}


func _build_page() -> void:
	var entry_profile_enabled := (
		OS.is_debug_build()
		and OS.get_environment("AI_TOWN_ENTRY_PROFILE") == "1"
	)
	var entry_profile_metrics: Dictionary = {}
	var entry_profile_tick := Time.get_ticks_usec()
	var backdrop_color := ColorRect.new()
	backdrop_color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop_color.color = Color("173b2c")
	backdrop_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop_color)

	_content_root = Control.new()
	_content_root.name = "ResponsivePageCanvas"
	_content_root.theme = _shared_ui_theme
	add_child(_content_root)

	_world_backdrop = _texture_rect(
		"ResidentSelectionTownBackdrop",
		_load_texture(WORLD_BACKDROP_PATH)
	)
	_world_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content_root.add_child(_world_backdrop)

	_shell = TextureRect.new()
	_shell.name = "ResidentSelectionShell"
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.texture = _load_texture(UI_SHELL_PATH)
	_shell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_shell)
	_overview_shell_overlay = _texture_rect(
		"ResidentOverviewShellOverlay",
		_load_texture(OVERVIEW_DETAIL_OVERLAY_PATH)
	)
	_overview_shell_overlay.visible = false
	_content_root.add_child(_overview_shell_overlay)
	if entry_profile_enabled:
		entry_profile_tick = _record_entry_profile_phase(
			entry_profile_metrics, "staticShellMsec", entry_profile_tick
		)

	_build_header()
	if entry_profile_enabled:
		entry_profile_tick = _record_entry_profile_phase(
			entry_profile_metrics, "headerMsec", entry_profile_tick
		)
	_build_roster()
	if entry_profile_enabled:
		entry_profile_tick = _record_entry_profile_phase(
			entry_profile_metrics, "rosterMsec", entry_profile_tick
		)
	_build_detail_panel()
	if entry_profile_enabled:
		entry_profile_tick = _record_entry_profile_phase(
			entry_profile_metrics, "detailMsec", entry_profile_tick
		)
	_build_footer()
	if entry_profile_enabled:
		_record_entry_profile_phase(
			entry_profile_metrics, "footerMsec", entry_profile_tick
		)
		print("RESIDENT_SELECTION_BUILD_PROFILE %s" % JSON.stringify(entry_profile_metrics))


func _build_header() -> void:
	_town_clock = _texture_rect("TownClock", _load_texture(ICON_ROOT + "town_clock.png"))
	_content_root.add_child(_town_clock)

	_back_button = _button("BackButton", "", FONT_BODY, _request_back)
	_style_surface_button(_back_button, true)
	_apply_bold_font(_back_button)
	_back_button.tooltip_text = "返回上一步：小镇介绍"
	_content_root.add_child(_back_button)
	_back_text = _button_overlay_label(
		_back_button, "BackButtonText", "返回", FONT_BODY, COLOR_PAPER
	)
	_back_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_register_touch("back", _back_button)
	_register_text("back", _back_text, false, 1, "返回")

	_title = _label("PageTitle", "选择初始居民", FONT_EMPHASIS, COLOR_INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_bold_font(_title)
	_content_root.add_child(_title)
	_register_text("page_title", _title, false, 1, "选择本局初始居民")

	_subtitle = _label("PageSubtitle", "决定谁会在小镇开始生活", FONT_CAPTION, COLOR_INK)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_root.add_child(_subtitle)
	_register_text("page_subtitle", _subtitle, false, 1, "决定谁会在小镇开始生活")

	_breadcrumb = HBoxContainer.new()
	_breadcrumb.name = "Breadcrumb"
	_breadcrumb.alignment = BoxContainer.ALIGNMENT_CENTER
	_breadcrumb.add_theme_constant_override("separation", 0)
	_breadcrumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_breadcrumb)
	var crumb_texts := ["小镇介绍", "居民名单", "模型选择"]
	var crumb_widths := [182, 156, 176]
	for crumb_index in range(crumb_texts.size()):
		var crumb_text: String = crumb_texts[crumb_index]
		var crumb := _label(
			"Breadcrumb" + crumb_text,
			crumb_text,
			FONT_CAPTION,
			COLOR_PAPER if crumb_text == "居民名单" else COLOR_INK
		)
		crumb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crumb.custom_minimum_size = Vector2(crumb_widths[crumb_index], 44)
		_apply_bold_font(crumb)
		if crumb_text == "居民名单":
			crumb.add_theme_constant_override("outline_size", 1)
			crumb.add_theme_color_override("font_outline_color", COLOR_WOOD)
		_breadcrumb.add_child(crumb)
		_breadcrumb_labels.append(crumb)
		_register_text(
			"breadcrumb_%d" % crumb_index,
			crumb,
			false,
			1,
			"选择居民模型" if crumb_index == 2 else crumb_text
		)

	_custom_button = _button(
		"CustomResidentButton", "+ 自定义", FONT_CAPTION, _open_custom_resident_entry
	)
	_style_surface_button(_custom_button, false)
	_apply_bold_font(_custom_button)
	_custom_button.disabled = not _action_is_enabled("custom_resident")
	_custom_button.add_theme_color_override("font_color", COLOR_INK)
	_custom_button.add_theme_color_override("font_disabled_color", COLOR_INK)
	_custom_button.tooltip_text = (
		"打开独立的自定义居民创建页"
		if _action_is_enabled("custom_resident")
		else "自定义居民创建页尚未完成"
	)
	_content_root.add_child(_custom_button)
	_register_touch("custom_resident", _custom_button)
	_register_text("custom_resident", _custom_button, false, 1, "+ 自定义")

	_custom_delete_button = _button(
		"CustomResidentDeleteButton",
		"",
		FONT_CAPTION,
		_toggle_delete_mode,
	)
	_style_custom_delete_button(_custom_delete_button, false)
	_custom_delete_button.icon = _alpha_cropped_texture(ICON_ROOT + "trash.png")
	_custom_delete_button.expand_icon = true
	_custom_delete_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_custom_delete_button.add_theme_constant_override("icon_max_width", 36)
	_custom_delete_button.visible = true
	_custom_delete_button.tooltip_text = "进入居民删除模式"
	_content_root.add_child(_custom_delete_button)
	_register_touch("delete_residents", _custom_delete_button)

	_connection_box = MarginContainer.new()
	_connection_box.name = "ConnectionBox"
	_connection_box.add_theme_constant_override("margin_left", 2)
	_connection_box.add_theme_constant_override("margin_top", 2)
	_connection_box.add_theme_constant_override("margin_right", 2)
	_connection_box.add_theme_constant_override("margin_bottom", 2)
	_connection_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_connection_box.tooltip_text = _connection_label
	_connection_box.add_theme_stylebox_override(
		"panel", StyleBoxEmpty.new()
	)
	_content_root.add_child(_connection_box)
	var connection_row := HBoxContainer.new()
	connection_row.alignment = BoxContainer.ALIGNMENT_CENTER
	connection_row.add_theme_constant_override("separation", 0)
	_connection_box.add_child(connection_row)
	_connection_icon = _texture_rect(
		"ConnectionIcon", _load_texture(ICON_ROOT + "empty_box.png")
	)
	_connection_icon.custom_minimum_size = Vector2(24.0, 32.0)
	connection_row.add_child(_connection_icon)
	_connection_status = _label(
		"ConnectionStatus", _connection_display_text(), FONT_CAPTION, COLOR_PAPER
	)
	_connection_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_connection_status.custom_minimum_size = Vector2(70, 32)
	_apply_bold_font(_connection_status)
	connection_row.add_child(_connection_status)
	_register_text("connection_status", _connection_status, false, 1, "连接中")

	_notice_label = _label("PageNotice", "", FONT_CAPTION, COLOR_TERRACOTTA)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_label.max_lines_visible = 2
	_notice_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_content_root.add_child(_notice_label)
	_register_text(
		"operation_notice",
		_notice_label,
		true,
		2,
		"真实 Provider 健康接口尚未接入，请完成模型设置后重试"
	)


func _build_roster() -> void:
	_roster_scroll = ScrollContainer.new()
	_roster_scroll.name = "RosterScroll"
	_roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_roster_scroll.follow_focus = true
	_content_root.add_child(_roster_scroll)

	_resident_grid = GridContainer.new()
	_resident_grid.name = "ResidentGrid"
	_resident_grid.columns = 4
	_roster_scroll.add_child(_resident_grid)

	_page_previous_button = _button(
		"ResidentPagePrevious", "", FONT_BODY, _change_resident_page.bind(-1)
	)
	_style_surface_button(_page_previous_button, false)
	_page_previous_button.tooltip_text = "上一页居民"
	_content_root.add_child(_page_previous_button)
	_register_touch("resident_page_previous", _page_previous_button)
	_register_text("resident_page_previous", _page_previous_button, false, 1, "‹")

	_page_status_label = _label("ResidentPageStatus", "", FONT_CAPTION, COLOR_INK)
	_page_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_bold_font(_page_status_label)
	_content_root.add_child(_page_status_label)
	_register_text("resident_page_status", _page_status_label, false, 1, "第 3 / 3 页")

	_page_next_button = _button(
		"ResidentPageNext", "", FONT_BODY, _change_resident_page.bind(1)
	)
	_style_surface_button(_page_next_button, false)
	_page_next_button.tooltip_text = "下一页居民"
	_content_root.add_child(_page_next_button)
	_register_touch("resident_page_next", _page_next_button)
	_register_text("resident_page_next", _page_next_button, false, 1, "›")

	for index in range(_residents.size()):
		var resident := _residents[index]
		var root := Control.new()
		root.name = "ResidentCard%02d" % index
		_resident_grid.add_child(root)
		_card_roots.append(root)

		var card_background := _texture_rect(
			"ResidentCardBackground%02d" % index,
			_load_texture(RESIDENT_CARD_MODULE_PATH)
		)
		card_background.stretch_mode = TextureRect.STRETCH_SCALE
		card_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(card_background)
		_card_backgrounds.append(card_background)

		var focus_button := _button("", "", FONT_BODY, _focus_resident.bind(index, true))
		focus_button.name = "ResidentCardFocus%02d" % index
		focus_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		focus_button.tooltip_text = "%s：%s" % [
			resident.get("display_name", ""),
			resident.get("personality", resident.get("selection_summary", "")),
		]
		focus_button.focus_entered.connect(_focus_resident.bind(index, false))
		root.add_child(focus_button)
		_card_focus_buttons.append(focus_button)
		_register_touch("resident_card_%02d" % index, focus_button)

		var portrait := _texture_rect(
			"ResidentPortrait%02d" % index,
			null,
		)
		root.add_child(portrait)
		_card_portraits.append(portrait)

		var number_label := _label(
			"ResidentNumber%02d" % index,
			str(index + 1),
			FONT_CAPTION,
			COLOR_INK
		)
		number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_bold_font(number_label)
		root.add_child(number_label)
		_card_number_labels.append(number_label)
		_register_text(
			"resident_number_%02d" % index,
			number_label,
			false,
			1,
			"16"
		)

		var name_slot := MarginContainer.new()
		name_slot.name = "ResidentNameSlot%02d" % index
		name_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(name_slot)
		var name_label := _label(
			"ResidentName%02d" % index,
			str(resident.get("display_name", "")),
			FONT_CAPTION,
			COLOR_INK
		)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size = Vector2.ZERO
		_apply_resident_name_font(name_label)
		name_slot.add_child(name_label)
		_card_name_slots.append(name_slot)
		_card_name_labels.append(name_label)
		_register_text(
			"resident_name_%02d" % index,
			name_label,
			false,
			1,
			str(resident.get("display_name", ""))
		)

		var job_label := _label(
			"ResidentJob%02d" % index,
			str(resident.get("occupation", "")),
			FONT_CAPTION,
			COLOR_INK
		)
		job_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		root.add_child(job_label)
		_card_job_labels.append(job_label)
		_register_text(
			"resident_job_%02d" % index,
			job_label,
			true,
			1,
			str(resident.get("occupation", ""))
		)

		var card_location := str(resident.get("card_location", ""))
		if card_location.is_empty():
			card_location = str(resident.get("location", "")).get_slice(" · ", 0)
		var location_icon := _texture_rect(
			"ResidentLocationIcon%02d" % index,
			_load_texture(ICON_ROOT + "map_pin.png")
		)
		root.add_child(location_icon)
		_card_location_icons.append(location_icon)
		var location_label := _label(
			"ResidentLocation%02d" % index,
			card_location,
			FONT_CAPTION,
			COLOR_INK
		)
		location_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		root.add_child(location_label)
		_card_location_labels.append(location_label)
		_register_text(
			"resident_location_%02d" % index,
			location_label,
			true,
			1,
			card_location
		)

		var toggle := _button(
			"ResidentToggle%02d" % index, "", FONT_BODY, _toggle_resident.bind(index)
		)
		toggle.tooltip_text = "加入或移出初始居民名单"
		_style_card_toggle(toggle)
		toggle.disabled = not _action_is_enabled("selection")
		root.add_child(toggle)
		_card_toggle_buttons.append(toggle)
		_register_touch("resident_toggle_%02d" % index, toggle)

		var state_icon := _texture_rect(
			"ResidentStateIcon%02d" % index,
			_load_texture(ICON_ROOT + "selected_leaf.png")
		)
		state_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		state_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toggle.add_child(state_icon)
		_card_state_icons.append(state_icon)


func _build_detail_panel() -> void:
	_detail_panel = Control.new()
	_detail_panel.name = "DetailPanel"
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_content_root.add_child(_detail_panel)

	_detail_name = _label("DetailName", "", FONT_BODY, COLOR_INK)
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_resident_name_font(_detail_name)
	_detail_panel.add_child(_detail_name)
	_register_text("detail_name", _detail_name, false, 1, "唐小满")
	_detail_identity_title = _label(
		"DetailIdentityTitle", "身份", FONT_CAPTION, COLOR_INK
	)
	_detail_identity_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_bold_font(_detail_identity_title)
	_detail_panel.add_child(_detail_identity_title)
	_register_text(
		"detail_identity_title", _detail_identity_title, false, 1, "身份"
	)
	_detail_meta = _label("DetailMeta", "", FONT_BODY, COLOR_INK)
	_detail_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_resident_name_font(_detail_meta)
	_detail_panel.add_child(_detail_meta)
	_register_text("detail_meta", _detail_meta, true, 1, "社区照顾者")

	_detail_coffee_icon = _texture_rect(
		"DetailCoffeeDecoration",
		_load_texture(ICON_ROOT + "coffee_beans.png")
	)
	_detail_panel.add_child(_detail_coffee_icon)

	_detail_location_icon = _texture_rect(
		"DetailLocationIcon",
		_load_texture(ICON_ROOT + "map_pin.png")
	)
	_detail_panel.add_child(_detail_location_icon)

	_detail_location = _label("DetailLocation", "", FONT_CAPTION, COLOR_MUTED)
	_detail_location.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_detail_location.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_panel.add_child(_detail_location)
	_register_text(
		"detail_location", _detail_location, false, 1, "咖啡馆·广场"
	)

	_detail_sprite = _texture_rect("DetailMapSprite", null)
	_detail_panel.add_child(_detail_sprite)

	_detail_role = _label("DetailRole", "", FONT_CAPTION, COLOR_INK)
	_detail_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_role.add_theme_constant_override("line_spacing", 2)
	_detail_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_role.max_lines_visible = 2
	_detail_role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_role.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail_panel.add_child(_detail_role)
	_register_text(
		"detail_role",
		_detail_role,
		false,
		2,
		"温和但总把别人的烦恼揽到自己身上的咖啡馆照顾者"
	)

	_overview_scroll = ScrollContainer.new()
	_overview_scroll.name = "ResidentOverviewScroll"
	_overview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_overview_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_overview_scroll.follow_focus = true
	_overview_scroll.clip_contents = true
	_overview_scroll.visible = false
	_detail_panel.add_child(_overview_scroll)
	_overview_scroll_content = VBoxContainer.new()
	_overview_scroll_content.name = "ResidentOverviewContent"
	_overview_scroll_content.add_theme_constant_override("separation", 18)
	_overview_scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overview_scroll_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_overview_scroll.add_child(_overview_scroll_content)

	var personality_section := _build_overview_section(
		"Personality", "性格", "温柔敏感，容易过度负责并承担他人的压力"
	)
	_detail_personality_icon = personality_section.get("icon") as TextureRect
	_detail_personality_title = personality_section.get("title") as Label
	_detail_personality = personality_section.get("body") as Label
	var desire_section := _build_overview_section(
		"Desire", "心愿", "让花房咖啡馆成为全镇愿意停留的地方"
	)
	_detail_desire_icon = desire_section.get("icon") as TextureRect
	_detail_desire_title = desire_section.get("title") as Label
	_detail_desire = desire_section.get("body") as Label
	var speech_section := _build_overview_section(
		"Speech", "说话方式", "语气温和，先倾听再回应；遇到冲突时会反复确认需求"
	)
	_detail_speech_icon = speech_section.get("icon") as TextureRect
	_detail_speech_title = speech_section.get("title") as Label
	_detail_speech = speech_section.get("body") as Label

	_overview_scroll_track = _texture_rect(
		"ResidentOverviewScrollTrack",
		_load_texture(OVERVIEW_SCROLL_TRACK_PATH)
	)
	_overview_scroll_track.stretch_mode = TextureRect.STRETCH_SCALE
	_overview_scroll_track.visible = false
	_overview_scroll_track.mouse_filter = Control.MOUSE_FILTER_STOP
	_overview_scroll_track.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_overview_scroll_track.gui_input.connect(
		_on_overview_scroll_control_gui_input.bind(false)
	)
	_detail_panel.add_child(_overview_scroll_track)
	_overview_scroll_thumb = _texture_rect(
		"ResidentOverviewScrollThumb",
		_load_texture(OVERVIEW_SCROLL_THUMB_PATH)
	)
	_overview_scroll_thumb.visible = false
	_overview_scroll_thumb.mouse_filter = Control.MOUSE_FILTER_STOP
	_overview_scroll_thumb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_overview_scroll_thumb.gui_input.connect(
		_on_overview_scroll_control_gui_input.bind(true)
	)
	_detail_panel.add_child(_overview_scroll_thumb)

	_overview_button = _button(
		"ResidentOverviewButton", "", FONT_CAPTION, _open_resident_overview
	)
	_style_surface_button(_overview_button, false)
	_apply_bold_font(_overview_button)
	_overview_button.tooltip_text = "查看身份、常驻地点、性格、心愿与说话方式"
	_detail_panel.add_child(_overview_button)
	_overview_icon = _button_icon(
		_overview_button,
		"ResidentOverviewButtonIcon",
		_load_texture(OVERVIEW_BOOK_ICON_PATH)
	)
	_overview_text = _button_overlay_label(
		_overview_button,
		"ResidentOverviewButtonText",
		"居民概览",
		FONT_CAPTION,
		COLOR_INK
	)
	_register_touch("resident_overview", _overview_button)
	_register_text("resident_overview", _overview_text, false, 1, "居民概览")

	_detail_toggle_button = _button(
		"DetailToggleButton", "", FONT_CAPTION, _handle_detail_primary_action
	)
	_style_surface_button(_detail_toggle_button, false)
	_apply_bold_font(_detail_toggle_button)
	_detail_panel.add_child(_detail_toggle_button)
	_detail_toggle_icon = _button_icon(
		_detail_toggle_button,
		"DetailToggleButtonIcon",
		_alpha_cropped_texture(ICON_ROOT + "selected_leaf.png")
	)
	_detail_toggle_text = _button_overlay_label(
		_detail_toggle_button,
		"DetailToggleButtonText",
		"加入名单",
		FONT_CAPTION,
		COLOR_INK
	)
	_register_touch("detail_toggle", _detail_toggle_button)
	_register_text("detail_toggle", _detail_toggle_text, false, 1, "移出名单")

	_detail_walk_timer = Timer.new()
	_detail_walk_timer.name = "DetailWalkTimer"
	_detail_walk_timer.wait_time = 0.16
	_detail_walk_timer.timeout.connect(_advance_detail_walk_frame)
	_detail_panel.add_child(_detail_walk_timer)
	_detail_walk_timer.start()
	_configure_native_overview_scrollbar.call_deferred()


func _build_overview_section(
	section_id: String,
	title_text: String,
	stress_text: String
) -> Dictionary:
	var section := VBoxContainer.new()
	section.name = "Overview%sSection" % section_id
	section.add_theme_constant_override("separation", 4)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_overview_scroll_content.add_child(section)
	var header := HBoxContainer.new()
	header.name = "Overview%sHeader" % section_id
	header.add_theme_constant_override("separation", 6)
	header.custom_minimum_size = Vector2(0, 40)
	section.add_child(header)
	var icon := _texture_rect(
		"Detail%sDecoration" % section_id,
		_load_texture(ICON_ROOT + "section_leaf.png")
	)
	icon.custom_minimum_size = Vector2(40, 40)
	header.add_child(icon)
	var title := _label(
		"Detail%sTitle" % section_id,
		title_text,
		FONT_CAPTION,
		COLOR_INK
	)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_bold_font(title)
	header.add_child(title)
	var body_margin := MarginContainer.new()
	body_margin.name = "Overview%sBodyMargin" % section_id
	body_margin.add_theme_constant_override("margin_left", 38)
	body_margin.add_theme_constant_override("margin_right", 12)
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(body_margin)
	var body := _label(
		"Detail%s" % section_id, "", FONT_CAPTION, COLOR_INK
	)
	body.clip_text = true
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.max_lines_visible = 32
	body.add_theme_constant_override("line_spacing", 4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body_margin.add_child(body)
	_register_text(
		"detail_%s_title" % section_id.to_snake_case(),
		title,
		false,
		1,
		title_text
	)
	_register_text(
		"detail_%s" % section_id.to_snake_case(),
		body,
		false,
		32,
		_profile_stress_text(stress_text)
	)
	return {"section": section, "icon": icon, "title": title, "body": body}


func _build_footer() -> void:
	_footer = Control.new()
	_footer.name = "FooterActions"
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(_footer)

	_count_label = _label("SelectionCount", "", FONT_CAPTION, COLOR_INK)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_bold_font(_count_label)
	_footer.add_child(_count_label)
	_register_text(
		"selection_count",
		_count_label,
		true,
		1,
		"已选 15 / 16 · 适合当前小镇规模"
	)

	_recommended_button = _button(
		"RecommendedButton", "", FONT_CAPTION, _apply_recommended_selection
	)
	_style_surface_button(_recommended_button, false)
	_apply_bold_font(_recommended_button)
	_recommended_button.disabled = not _action_is_enabled("recommend")
	_footer.add_child(_recommended_button)
	_recommended_icon = _button_icon(
		_recommended_button,
		"RecommendedButtonIcon",
		_load_texture(ICON_ROOT + "group.png")
	)
	_recommended_text = _button_overlay_label(
		_recommended_button,
		"RecommendedButtonText",
		"推荐组合",
		FONT_CAPTION,
		COLOR_INK
	)
	_register_touch("recommend", _recommended_button)
	_register_text("recommend", _recommended_text, false, 1, "推荐组合")

	_clear_button = _button("ClearButton", "", FONT_CAPTION, _clear_selection)
	_style_surface_button(_clear_button, false)
	_apply_bold_font(_clear_button)
	_footer.add_child(_clear_button)
	_clear_icon = _button_icon(
		_clear_button, "ClearButtonIcon", _load_texture(ICON_ROOT + "broom.png")
	)
	_clear_text = _button_overlay_label(
		_clear_button, "ClearButtonText", "清空", FONT_CAPTION, COLOR_INK
	)
	_register_touch("clear", _clear_button)
	_register_text("clear", _clear_text, false, 1, "清空")

	_confirm_button = _button(
		"ConfirmRosterButton", "", FONT_CAPTION, _confirm_roster
	)
	_confirm_button.add_theme_color_override("font_color", Color("fff1cf"))
	_confirm_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_confirm_button.add_theme_color_override("font_pressed_color", Color("ffe2aa"))
	_confirm_button.add_theme_color_override("font_disabled_color", Color("583a25"))
	_style_primary_button(_confirm_button)
	_apply_bold_font(_confirm_button)
	_footer.add_child(_confirm_button)
	_confirm_icon = _button_icon(
		_confirm_button,
		"ConfirmRosterButtonIcon",
		_load_texture(ICON_ROOT + "selected_leaf.png")
	)
	_confirm_text = _button_overlay_label(
		_confirm_button,
		"ConfirmRosterButtonText",
		"确认居民名单",
		FONT_CAPTION,
		Color("583a25")
	)
	_register_touch("confirm", _confirm_button)
	_register_text("confirm", _confirm_text, false, 1, "选择居民模型")


func _focus_resident(index: int, reveal_mobile_detail: bool = false) -> void:
	if index < 0 or index >= _residents.size():
		return
	_focused_index = index
	if reveal_mobile_detail and _layout_mode in [
		LayoutMode.PHONE_LANDSCAPE, LayoutMode.PHONE_PORTRAIT
	]:
		_mobile_detail_open = true
		_apply_responsive_layout()
	_refresh_cards()
	_refresh_detail()


func _toggle_resident(index: int) -> void:
	if index < 0 or index >= _residents.size():
		return
	if _delete_mode_active:
		_toggle_delete_candidate(index)
		return
	_focused_index = index
	var resident_id := str(_residents[index].get("resident_id", ""))
	var will_select := not _selected_by_id.has(resident_id)
	if will_select and _selected_by_id.size() >= _selection_limit:
		_refresh_all()
		return
	var request_revision := _view_model_revision
	if will_select:
		_selected_by_id[resident_id] = true
	else:
		_selected_by_id.erase(resident_id)
	_invalidate_roster_draft_for_selection_change()
	resident_selection_requested.emit(resident_id, will_select, request_revision)
	_refresh_all()
	_animate_card_state(index, _selected_by_id.has(resident_id))


func _toggle_focused_resident() -> void:
	_toggle_resident(_focused_index)


func _toggle_delete_candidate(index: int) -> void:
	if index < 0 or index >= _residents.size():
		return
	_focused_index = index
	var resident_id := String(_residents[index].get("resident_id", ""))
	if resident_id.is_empty():
		return
	var is_marked := _delete_selected_by_id.has(resident_id)
	if not is_marked and _delete_selected_by_id.size() >= _maximum_deletable_count():
		_show_notice("本局至少需要保留 15 名候选居民。")
		_refresh_all()
		return
	if is_marked:
		_delete_selected_by_id.erase(resident_id)
	else:
		_delete_selected_by_id[resident_id] = true
	_refresh_all()
	_animate_delete_marker(index, not is_marked)


func _handle_detail_primary_action() -> void:
	if _detail_mode == DetailMode.OVERVIEW:
		_close_resident_overview()
		return
	_toggle_focused_resident()


func _open_resident_overview() -> void:
	if _detail_mode == DetailMode.OVERVIEW:
		return
	_detail_mode = DetailMode.OVERVIEW
	if _overview_scroll != null:
		_overview_scroll.scroll_vertical = 0
	_refresh_detail()
	_configure_detail_geometry()
	_refresh_overview_scroll_indicator.call_deferred()
	if _detail_toggle_button != null:
		_detail_toggle_button.grab_focus.call_deferred()


func _close_resident_overview() -> void:
	if _detail_mode == DetailMode.SHOWCASE:
		return
	_overview_scroll_dragging = false
	_detail_mode = DetailMode.SHOWCASE
	_refresh_detail()
	_configure_detail_geometry()
	if _overview_button != null:
		_overview_button.grab_focus.call_deferred()


func _configure_native_overview_scrollbar() -> void:
	if _overview_scroll == null:
		return
	var scroll_bar := _overview_scroll.get_v_scroll_bar()
	if scroll_bar == null:
		return
	# The page-specific track and thumb own the visible boundary. The native
	# scrollbar remains the authoritative value/range source for wheel, touchpad,
	# keyboard and programmatic scrolling.
	scroll_bar.modulate.a = 0.0
	scroll_bar.value_changed.connect(
		func(_value: float) -> void:
			_refresh_overview_scroll_indicator()
	)
	_refresh_overview_scroll_indicator.call_deferred()


func _refresh_overview_scroll_indicator() -> void:
	if (
		_overview_scroll == null
		or _overview_scroll_track == null
		or _overview_scroll_thumb == null
	):
		return
	var scroll_bar := _overview_scroll.get_v_scroll_bar()
	var overview_visible := _detail_mode == DetailMode.OVERVIEW
	_overview_scroll_track.visible = overview_visible
	_overview_scroll_thumb.visible = overview_visible
	if not overview_visible or scroll_bar == null:
		return
	var track_rect := _overview_scroll_track.get_rect()
	var can_scroll := scroll_bar.max_value > scroll_bar.page + 0.5
	var visible_fraction := clampf(
		scroll_bar.page / maxf(scroll_bar.page, scroll_bar.max_value),
		0.12,
		1.0
	)
	# Keep the page-specific ornament as a quiet edge affordance.  A short
	# disabled thumb is intentional when the current copy does not overflow;
	# expanding it to the full rail made the control dominate the profile.
	var thumb_height := clampf(
		track_rect.size.y * visible_fraction,
		28.0,
		minf(56.0, track_rect.size.y)
	)
	if not can_scroll:
		thumb_height = minf(36.0, track_rect.size.y)
	var travel := maxf(0.0, track_rect.size.y - thumb_height)
	var scroll_range := maxf(1.0, scroll_bar.max_value - scroll_bar.page)
	var progress := clampf(scroll_bar.value / scroll_range, 0.0, 1.0)
	_set_rect(
		_overview_scroll_thumb,
		Rect2(
			track_rect.position.x - 2.0,
			track_rect.position.y + travel * progress,
			track_rect.size.x + 4.0,
			thumb_height
		)
	)


func _on_overview_scroll_control_gui_input(
	event: InputEvent,
	dragging_thumb: bool
) -> void:
	if _detail_mode != DetailMode.OVERVIEW:
		return
	var scroll_bar := _overview_scroll.get_v_scroll_bar()
	if scroll_bar == null:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			scroll_bar.value -= maxf(48.0, scroll_bar.page * 0.16)
			get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			scroll_bar.value += maxf(48.0, scroll_bar.page * 0.16)
			get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_overview_scroll_dragging = mouse_button.pressed
			if mouse_button.pressed:
				_overview_scroll_drag_offset = (
					mouse_button.global_position.y
					- _overview_scroll_thumb.get_global_rect().position.y
					if dragging_thumb
					else _overview_scroll_thumb.size.y * 0.5
				)
				_set_overview_scroll_from_global_y(mouse_button.global_position.y)
			get_viewport().set_input_as_handled()


func _set_overview_scroll_from_global_y(global_y: float) -> void:
	if _overview_scroll == null or _overview_scroll_track == null:
		return
	var scroll_bar := _overview_scroll.get_v_scroll_bar()
	if scroll_bar == null or scroll_bar.max_value <= scroll_bar.page + 0.5:
		return
	var track_rect := _overview_scroll_track.get_global_rect()
	var travel := maxf(1.0, track_rect.size.y - _overview_scroll_thumb.size.y)
	var thumb_y := global_y - track_rect.position.y - _overview_scroll_drag_offset
	var progress := clampf(thumb_y / travel, 0.0, 1.0)
	scroll_bar.value = progress * (scroll_bar.max_value - scroll_bar.page)


func _set_detail_walk_sheet(
	path: String,
	frame_size: Vector2 = Vector2(64, 80),
	vertical := false,
) -> void:
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty():
		_detail_walk_sheet_path = ""
		_detail_walk_frame = 0
		_detail_walk_texture = null
		if _detail_sprite != null:
			_detail_sprite.texture = null
		return
	if (
		normalized_path == _detail_walk_sheet_path
		and _detail_walk_texture != null
		and _detail_walk_frame_size == frame_size
		and _detail_walk_vertical == vertical
	):
		if _detail_sprite != null:
			_detail_sprite.texture = _detail_walk_texture
		_update_detail_walk_texture()
		return
	_detail_walk_sheet_path = normalized_path
	_detail_walk_frame_size = frame_size
	_detail_walk_vertical = vertical
	_detail_walk_frame = 1 if vertical else 0
	var sheet := _load_texture(normalized_path)
	if sheet == null:
		_detail_walk_texture = null
		if _detail_sprite != null:
			_detail_sprite.texture = null
		return
	_detail_walk_texture = AtlasTexture.new()
	_detail_walk_texture.atlas = sheet
	if _detail_sprite != null:
		_detail_sprite.texture = _detail_walk_texture
	_update_detail_walk_texture()


func _advance_detail_walk_frame() -> void:
	if _detail_mode != DetailMode.SHOWCASE or not _detail_panel.visible:
		return
	_detail_walk_frame = (_detail_walk_frame + 1) % 4
	_update_detail_walk_texture()


func _update_detail_walk_texture() -> void:
	if _detail_walk_texture == null:
		return
	_detail_walk_texture.region = Rect2(
		(
			Vector2(0.0, float(_detail_walk_frame) * _detail_walk_frame_size.y)
			if _detail_walk_vertical
			else Vector2(float(_detail_walk_frame) * _detail_walk_frame_size.x, 0.0)
		),
		_detail_walk_frame_size,
	)


func _complete_set_sheet_for_resident(resident: Dictionary) -> String:
	if _complete_set_sheet_by_appearance.is_empty():
		_load_complete_set_sheet_index()
	return String(
		_complete_set_sheet_by_appearance.get(
			String(resident.get("appearance_id", "")),
			"",
		),
	)


func _load_complete_set_sheet_index() -> void:
	_complete_set_sheet_by_appearance["__loaded__"] = true
	if not FileAccess.file_exists(COMPLETE_SET_WARDROBE_CATALOG_PATH):
		return
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(COMPLETE_SET_WARDROBE_CATALOG_PATH),
	)
	if not parsed is Dictionary:
		return
	for value: Variant in (parsed as Dictionary).get("loadouts", []) as Array:
		if not value is Dictionary:
			continue
		var loadout := value as Dictionary
		var appearance_id := String(loadout.get("appearanceId", ""))
		var sheet_path := String(loadout.get("spriteSheetPath", ""))
		if (
			not appearance_id.is_empty()
			and ResourceLoader.exists(sheet_path, "Texture2D")
		):
			_complete_set_sheet_by_appearance[appearance_id] = sheet_path


func _change_resident_page(delta: int) -> void:
	if _layout_mode != LayoutMode.DESKTOP:
		return
	var page_count := maxi(1, ceili(float(_residents.size()) / RESIDENTS_PER_DESKTOP_PAGE))
	var next_page := clampi(_resident_page + delta, 0, page_count - 1)
	if next_page == _resident_page:
		return
	_resident_page = next_page
	_focused_index = mini(
		_resident_page * RESIDENTS_PER_DESKTOP_PAGE,
		_residents.size() - 1
	)
	_refresh_all()


func _refresh_resident_pagination() -> void:
	if _page_previous_button == null:
		return
	var desktop := _layout_mode == LayoutMode.DESKTOP
	var page_count := maxi(1, ceili(float(_residents.size()) / RESIDENTS_PER_DESKTOP_PAGE))
	_resident_page = clampi(_resident_page, 0, page_count - 1)
	for index in range(_card_roots.size()):
		var card_visible := (
			not desktop
			or index / RESIDENTS_PER_DESKTOP_PAGE == _resident_page
		)
		_card_roots[index].visible = card_visible
		if card_visible and _card_portraits[index].texture == null:
			_card_portraits[index].texture = _resident_portrait_texture(
				_residents[index],
			)
	_page_previous_button.visible = desktop
	_page_status_label.visible = desktop
	_page_next_button.visible = desktop
	_page_previous_button.disabled = _resident_page == 0
	_page_next_button.disabled = _resident_page >= page_count - 1
	_page_status_label.text = "%d / %d" % [_resident_page + 1, page_count]


func _apply_recommended_selection(show_feedback: bool = true) -> void:
	if _delete_mode_active:
		_exit_delete_mode(true)
		return
	var request_revision := _view_model_revision
	_selected_by_id.clear()
	for resident_id: String in _recommended_ids:
		if _selected_by_id.size() >= STRICT_SESSION_SLOT_COUNT:
			break
		_selected_by_id[resident_id] = true
	_invalidate_roster_draft_for_selection_change()
	recommended_selection_requested.emit(request_revision)
	_refresh_all()
	if show_feedback:
		_animate_recommended_selection()


func _clear_selection() -> void:
	if _delete_mode_active:
		_delete_selected_by_id.clear()
		_refresh_all()
		_show_notice("已清除全部删除标记。")
		return
	var request_revision := _view_model_revision
	var previously_selected: Array[int] = []
	for index in range(_residents.size()):
		var resident_id := str(_residents[index].get("resident_id", ""))
		if _selected_by_id.has(resident_id):
			previously_selected.append(index)
	_selected_by_id.clear()
	_invalidate_roster_draft_for_selection_change()
	selection_clear_requested.emit(request_revision)
	_refresh_all()
	for order in range(previously_selected.size()):
		_animate_card_state(previously_selected[order], false, float(order) * 0.025)


func _refresh_all() -> void:
	_refresh_resident_pagination()
	_refresh_cards()
	_refresh_detail()
	_refresh_count()
	_refresh_operation()


func _refresh_operation() -> void:
	if _notice_label == null:
		return
	var status := str(_operation.get("status", "idle"))
	var capture_status := _env_capture_operation_state
	if capture_status in ["idle", "loading", "success", "rejected", "error", "disabled"]:
		status = capture_status
	if status == "idle":
		_notice_label.text = ""
		_notice_label.visible = false
		_subtitle.visible = _layout_mode == LayoutMode.DESKTOP
		return
	var message := str(_operation.get("message", ""))
	if status in ["rejected", "error", "disabled"] and _error_value is Dictionary:
		message = str((_error_value as Dictionary).get("message", message))
	if message.is_empty():
		message = str(OPERATION_STRESS_TEXTS.get(status, "操作状态已更新"))
	_notice_label.text = message
	_notice_label.visible = true
	_subtitle.visible = false


func _refresh_cards() -> void:
	if _card_roots.size() != _residents.size():
		return
	for index in range(_residents.size()):
		var resident_id := str(_residents[index].get("resident_id", ""))
		var is_selected := (
			_delete_selected_by_id.has(resident_id)
			if _delete_mode_active
			else _selected_by_id.has(resident_id)
		)
		var is_focused := index == _focused_index
		_style_resident_card(_card_focus_buttons[index], is_selected, is_focused)
		_card_state_icons[index].texture = (
			_alpha_cropped_texture(ICON_ROOT + "delete_check_red_v53.png")
			if _delete_mode_active
			else _load_texture(ICON_ROOT + "selected_leaf.png")
		)
		# Delete mode uses its own authored red check only after the player
		# marks a card. Unmarked cards keep the empty frame baked into the
		# page shell; the roster leaf never participates in deletion.
		_card_state_icons[index].visible = is_selected
		_card_state_icons[index].modulate = Color.WHITE
		_card_toggle_buttons[index].disabled = (
			not _delete_action_is_enabled()
			if _delete_mode_active
			else not _action_is_enabled("selection")
		)
		_card_toggle_buttons[index].tooltip_text = (
			"取消删除标记" if is_selected else "标记为从本局候选列表删除"
			if _delete_mode_active
			else "加入或移出初始居民名单"
		)
		_card_portraits[index].modulate = (
			Color("ffd5c7") if _delete_mode_active and is_selected else Color.WHITE
		)


func _animate_card_state(index: int, is_selected: bool, delay: float = 0.0) -> void:
	if index < 0 or index >= _card_state_icons.size():
		return
	var icon := _card_state_icons[index]
	icon.pivot_offset = icon.size * 0.5
	icon.visible = true
	icon.modulate.a = 0.0 if is_selected else 1.0
	icon.scale = Vector2(0.45, 0.45) if is_selected else Vector2.ONE
	icon.rotation = -0.08 if is_selected else 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(icon, "modulate:a", 1.0 if is_selected else 0.0, 0.10).set_delay(delay)
	tween.tween_property(
		icon,
		"scale",
		Vector2.ONE if is_selected else Vector2(0.55, 0.55),
		0.13
	).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "rotation", 0.0, 0.13).set_delay(delay)
	if not is_selected:
		var icon_ref: WeakRef = weakref(icon)
		tween.chain().tween_callback(
			func() -> void:
				var target := icon_ref.get_ref() as TextureRect
				if target != null:
					target.visible = false
		)


func _animate_delete_marker(index: int, is_marked: bool) -> void:
	if index < 0 or index >= _card_state_icons.size():
		return
	var icon := _card_state_icons[index]
	icon.texture = _alpha_cropped_texture(ICON_ROOT + "delete_check_red_v53.png")
	icon.pivot_offset = icon.size * 0.5
	icon.visible = true
	icon.modulate = Color.WHITE
	icon.scale = Vector2.ONE
	icon.rotation = 0.0
	var tween := create_tween()
	if is_marked:
		var resting_x := icon.position.x
		tween.tween_property(icon, "position:x", resting_x - 2.0, 0.06)
		tween.tween_property(icon, "position:x", resting_x + 2.0, 0.08)
		tween.tween_property(icon, "position:x", resting_x, 0.06)
	else:
		tween.tween_property(icon, "modulate:a", 0.0, 0.10)
		var icon_ref: WeakRef = weakref(icon)
		tween.tween_callback(
			func() -> void:
				var target := icon_ref.get_ref() as TextureRect
				if target != null:
					target.visible = false
		)


func _animate_recommended_selection() -> void:
	var order := 0
	for index in range(_residents.size()):
		var resident_id := str(_residents[index].get("resident_id", ""))
		if _selected_by_id.has(resident_id):
			_animate_card_state(index, true, float(order) * 0.035)
			order += 1


func _refresh_detail() -> void:
	if _residents.is_empty() or _detail_name == null:
		return
	var resident := _residents[_focused_index]
	var complete_set_sheet := _complete_set_sheet_for_resident(resident)
	if not complete_set_sheet.is_empty():
		_set_detail_walk_sheet(complete_set_sheet, Vector2(512, 512), true)
	elif str(resident.get("portrait_frame_mode", "")) == "full_texture":
		_set_detail_walk_sheet("")
		_detail_sprite.texture = _resident_portrait_texture(resident)
	else:
		_set_detail_walk_sheet(str(resident.get("sprite_path", "")))
	_detail_name.text = str(resident.get("display_name", ""))
	_detail_meta.text = str(resident.get("occupation", ""))
	_detail_location.text = (
		"常在："
		+ str(resident.get("location", "")).replace(" · ", "·")
	)
	var role_text := str(resident.get("selection_summary", ""))
	var personality_text := str(resident.get("personality", ""))
	var desire_text := str(resident.get("desire", ""))
	var speech_text := str(resident.get("speech", ""))
	if _env_detail_content_stress == "240":
		personality_text = _profile_stress_text(
			"温柔敏感，也会认真记录邻居的困难与小镇每天发生的变化。"
		)
		desire_text = _profile_stress_text(
			"希望咖啡馆成为大家愿意停留、交流并互相理解的地方。"
		)
		speech_text = _profile_stress_text(
			"说话温和，会先倾听再回应，遇到冲突时会确认彼此真正的需求。"
		)
	if speech_text.is_empty():
		speech_text = "暂无说话方式资料"
	# _detail_role 在下方被固定隐藏，不再为它做逐字排版平衡（约 80 次 shaping）。
	_detail_role.text = role_text
	_detail_role.tooltip_text = personality_text
	_detail_personality.text = personality_text
	_detail_personality.tooltip_text = personality_text
	_detail_desire.text = desire_text
	_detail_desire.tooltip_text = desire_text
	_detail_speech.text = speech_text
	_detail_speech.tooltip_text = speech_text
	var overview_visible := _detail_mode == DetailMode.OVERVIEW
	_detail_name.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT
		if overview_visible and _detail_panel.size.x >= 380.0
		else HORIZONTAL_ALIGNMENT_CENTER
	)
	_detail_identity_title.visible = false
	_detail_meta.visible = overview_visible
	if overview_visible:
		if _layout_mode == LayoutMode.DESKTOP:
			_layout_detail_identity_row(Rect2(34, 14, 420, 80))
		elif _detail_panel.size.x < 380.0:
			_layout_detail_identity_row(
				Rect2(20, 12, maxf(160.0, _detail_panel.size.x - 40.0), 76)
			)
		else:
			_layout_detail_identity_row(
				Rect2(20, 10, maxf(160.0, _detail_panel.size.x - 40.0), 68)
			)
	_detail_location_icon.visible = overview_visible
	_detail_location.visible = overview_visible
	# selection_summary is already represented by the complete sections below;
	# the overview header intentionally keeps only the identity/occupation.
	_detail_role.visible = false
	_detail_coffee_icon.visible = false
	_detail_sprite.visible = not overview_visible
	_overview_button.visible = not overview_visible
	_overview_scroll.visible = overview_visible
	_overview_shell_overlay.visible = (
		overview_visible and _layout_mode == LayoutMode.DESKTOP
	)
	var resident_id := str(resident.get("resident_id", ""))
	var is_selected := _selected_by_id.has(resident_id)
	if overview_visible:
		_detail_toggle_text.text = "收起资料"
		_detail_toggle_icon.texture = _alpha_cropped_texture(ICON_ROOT + "back_arrow.png")
		_detail_toggle_button.tooltip_text = "收起资料，返回人物走动展示"
		_detail_toggle_button.disabled = false
	elif _delete_mode_active:
		var delete_marked := _delete_selected_by_id.has(resident_id)
		_detail_toggle_text.text = "取消删除" if delete_marked else "标记删除"
		_detail_toggle_icon.texture = _alpha_cropped_texture(ICON_ROOT + "trash.png")
		_detail_toggle_button.tooltip_text = (
			"取消这个居民的删除标记"
			if delete_marked
			else "标记为从本局候选列表删除"
		)
		_detail_toggle_button.disabled = not _delete_action_is_enabled()
	else:
		_detail_toggle_text.text = "移出名单" if is_selected else "加入名单"
		_detail_toggle_icon.texture = _alpha_cropped_texture(
			ICON_ROOT + ("trash.png" if is_selected else "selected_leaf.png")
		)
		_detail_toggle_button.tooltip_text = "加入或移出本局初始居民名单"
		_detail_toggle_button.disabled = not _action_is_enabled("selection")
	_refresh_delete_mode_control()
	if _overview_scroll_content != null:
		_overview_scroll_content.queue_sort()
	_refresh_overview_scroll_indicator.call_deferred()


func _profile_stress_text(seed: String) -> String:
	var normalized := seed.strip_edges()
	if normalized.is_empty():
		normalized = "居民完整资料"
	var value := ""
	while value.length() < 240:
		value += normalized
	return value.substr(0, 240)


func _refresh_count() -> void:
	if _count_label == null:
		return
	if _delete_mode_active:
		var delete_count := _delete_selected_by_id.size()
		var max_delete := _maximum_deletable_count()
		_count_label.text = (
			"删除模式 · 已标记 %d / %d" % [delete_count, max_delete]
			if _layout_mode == LayoutMode.DESKTOP
			else "待删 %d / %d" % [delete_count, max_delete]
		)
		_count_label.visible = _layout_mode != LayoutMode.PHONE_PORTRAIT
		_recommended_icon.visible = true
		_recommended_icon.texture = _alpha_cropped_texture(
			ICON_ROOT + "delete_check_red_v53.png",
		)
		_recommended_text.text = "取消删除"
		_clear_icon.texture = _alpha_cropped_texture(ICON_ROOT + "broom.png")
		_clear_text.text = "清除标记"
		_confirm_icon.texture = _alpha_cropped_texture(ICON_ROOT + "trash.png")
		_confirm_text.text = "删除选中 %d 人" % delete_count
		_recommended_button.disabled = false
		_clear_button.disabled = delete_count == 0
		_confirm_button.disabled = (
			delete_count == 0
			or delete_count > max_delete
			or not _delete_action_is_enabled()
		)
		_confirm_button.tooltip_text = (
			"确认从本局候选列表删除已标记居民"
			if not _confirm_button.disabled
			else "请先勾选要删除的居民；本局至少保留 15 人"
		)
		return
	var count := _selected_by_id.size()
	_recommended_icon.visible = true
	_recommended_icon.texture = _load_texture(ICON_ROOT + "group.png")
	_clear_icon.texture = _load_texture(ICON_ROOT + "broom.png")
	_confirm_icon.texture = _load_texture(ICON_ROOT + "selected_leaf.png")
	_recommended_text.text = "推荐组合" if _layout_mode == LayoutMode.DESKTOP else "推荐"
	_clear_text.text = "清空"
	_count_label.text = (
		"已选 %d / %d · 本局入镇名单" % [count, STRICT_SESSION_SLOT_COUNT]
		if _layout_mode == LayoutMode.DESKTOP
		else "已选 %d / %d" % [count, STRICT_SESSION_SLOT_COUNT]
	)
	_count_label.visible = _layout_mode != LayoutMode.PHONE_PORTRAIT
	_confirm_text.text = (
		"确认 · %d/%d" % [count, STRICT_SESSION_SLOT_COUNT]
		if _layout_mode == LayoutMode.PHONE_PORTRAIT
		else "选择居民模型"
	)
	_clear_button.disabled = count == 0 or not _action_is_enabled("clear")
	var current_draft := _build_current_roster_draft()
	var payload_validation := _validate_confirmation_payload(current_draft)
	var can_submit_session := (
		_submission_is_authorized()
		and count == STRICT_SESSION_SLOT_COUNT
		and bool(payload_validation.get("passed", false))
		and _payload_matches_selection(current_draft)
	)
	_confirm_button.disabled = not can_submit_session
	if not _confirm_action_authorizes_roster():
		_confirm_button.tooltip_text = UiViewModel.player_reason(
			str(_action_config("confirm").get(
				"disabled_reason",
				"当前不能进入居民模型选择。",
			))
		)
	elif not _submission_is_authorized():
		_confirm_button.tooltip_text = "当前会话尚未就绪，不能进入居民模型选择"
	elif count < STRICT_SESSION_SLOT_COUNT:
		_confirm_button.tooltip_text = "还差 %d 位居民；选满 15 位后进入模型选择" % (
			STRICT_SESSION_SLOT_COUNT - count
		)
	elif not bool(payload_validation.get("passed", false)):
		_confirm_button.tooltip_text = "15 槽居民草稿不完整"
	else:
		_confirm_button.tooltip_text = "保留本局名单并进入居民模型选择"


func _open_custom_resident_entry() -> void:
	if not _action_is_enabled("custom_resident"):
		_show_notice(str(_action_config("custom_resident").get(
			"disabled_reason", "自定义居民创建页尚未完成。"
		)))
		return
	custom_resident_requested.emit(_view_model_revision)
	_show_notice("正在打开独立的自定义居民创建页。")


func _refresh_delete_mode_control() -> void:
	if _custom_delete_button == null:
		return
	_custom_delete_button.visible = true
	_custom_delete_button.disabled = (
		not _delete_mode_active
		and (not _delete_action_is_enabled() or _maximum_deletable_count() <= 0)
	)
	_style_custom_delete_button(_custom_delete_button, _delete_mode_active)
	_custom_delete_button.tooltip_text = (
		"退出居民删除模式"
		if _delete_mode_active
		else "进入居民删除模式"
		if not _custom_delete_button.disabled
		else "本局至少需要保留 15 名候选居民"
	)
	if _custom_button != null:
		_custom_button.disabled = (
			_delete_mode_active or not _action_is_enabled("custom_resident")
		)


func _delete_action_is_enabled() -> bool:
	if _view_model_actions.has("delete_residents"):
		return _action_is_enabled("delete_residents")
	if _view_model_actions.has("delete_custom_resident"):
		return _action_is_enabled("delete_custom_resident")
	return _action_is_enabled("selection")


func _maximum_deletable_count() -> int:
	return maxi(0, _residents.size() - STRICT_SESSION_SLOT_COUNT)


func _toggle_delete_mode() -> void:
	if _delete_mode_active:
		_exit_delete_mode(true)
		return
	if not _delete_action_is_enabled():
		_show_notice("当前会话不能删除居民。")
		return
	if _maximum_deletable_count() <= 0:
		_show_notice("本局至少需要保留 15 名候选居民，当前没有可删除名额。")
		return
	_delete_mode_active = true
	_delete_selected_by_id.clear()
	if _detail_mode == DetailMode.OVERVIEW:
		_close_resident_overview()
	_refresh_all()
	_apply_responsive_layout()
	_show_notice("删除模式：勾选居民后，在底栏确认删除。")


func _exit_delete_mode(show_feedback: bool) -> void:
	_delete_mode_active = false
	_delete_selected_by_id.clear()
	_refresh_all()
	_apply_responsive_layout()
	if show_feedback:
		_show_notice("已退出居民删除模式，入镇名单没有改变。")


func _confirm_delete_selection() -> void:
	if not _delete_mode_active:
		return
	var delete_count := _delete_selected_by_id.size()
	if delete_count <= 0:
		_show_notice("请先勾选要删除的居民。")
		return
	if delete_count > _maximum_deletable_count():
		_show_notice("本局至少需要保留 15 名候选居民。")
		return
	var resident_ids: Array = []
	for resident: Dictionary in _residents:
		var resident_id := String(resident.get("resident_id", ""))
		if _delete_selected_by_id.has(resident_id):
			resident_ids.append(resident_id)
	# Keep the independent delete selection until an authoritative ViewModel
	# actually contains fewer candidates. A stale revision or failed global-file
	# write can then restore the controls without losing the player's red marks.
	_custom_delete_button.disabled = true
	_confirm_button.disabled = true
	call_deferred(
		"_emit_residents_delete_request",
		resident_ids,
		_candidate_pool_revision,
		_view_model_revision,
	)


func _emit_residents_delete_request(
	resident_ids: Array,
	candidate_pool_revision: int,
	revision: int,
) -> void:
	residents_delete_requested.emit(
		resident_ids,
		candidate_pool_revision,
		revision,
	)


func _request_back(close_local_layer_first := true) -> void:
	if close_local_layer_first and _delete_mode_active:
		_exit_delete_mode(true)
		return
	if not _action_is_enabled("back"):
		_show_notice(str(_action_config("back").get("disabled_reason", "当前无法返回。")))
		return
	back_requested.emit(_view_model_revision)
	_show_notice("正在返回小镇介绍。")


func _confirm_roster() -> void:
	if _delete_mode_active:
		_confirm_delete_selection()
		return
	if not _confirm_action_authorizes_roster():
		_show_notice(str(_action_config("confirm").get(
			"disabled_reason", "当前不能进入居民模型选择。"
		)))
		return
	if not _submission_is_authorized():
		_show_notice("当前会话尚未就绪，未进入居民模型选择。")
		return
	if _selected_by_id.size() != STRICT_SESSION_SLOT_COUNT:
		_show_notice("还差 %d 位居民；选满 15 位后才能进入模型选择。" % (
			STRICT_SESSION_SLOT_COUNT - _selected_by_id.size()
		))
		return
	var roster_draft := _build_current_roster_draft()
	var validation := _validate_confirmation_payload(roster_draft)
	if not bool(validation.get("passed", false)):
		_show_notice("15 槽居民草稿不完整，未进入模型选择。")
		return
	if not _payload_matches_selection(roster_draft):
		_show_notice("15 槽草稿与当前已选居民不一致，未发出提交意图。")
		return
	_confirmation_payload = roster_draft.duplicate(true)
	_draft_revision_floor = int(roster_draft.get("draftRevision", 1))
	roster_confirmation_requested.emit(roster_draft, _view_model_revision)
	_show_notice("名单草稿已保留；正在进入居民模型选择。")


func _build_current_roster_draft() -> Dictionary:
	if not _confirmation_payload.is_empty():
		return _confirmation_payload.duplicate(true)
	var slots: Array[Dictionary] = []
	for resident: Dictionary in _residents:
		var resident_id := str(resident.get("resident_id", ""))
		if resident_id.is_empty() or not _selected_by_id.has(resident_id):
			continue
		slots.append({
			"residentId": resident_id,
			"spaceId": "home_%02d" % (slots.size() + 1),
		})
	return {
		"schemaVersion": 1,
		"sourceScope": "resident_selection",
		"draftRevision": maxi(_draft_revision_floor + 1, 1),
		"slots": slots,
	}


func _invalidate_roster_draft_for_selection_change() -> void:
	if not _confirmation_payload.is_empty():
		_draft_revision_floor = maxi(
			_draft_revision_floor,
			int(_confirmation_payload.get("draftRevision", 0))
		)
	_confirmation_payload.clear()


func _is_explicit_development_submission() -> bool:
	return (
		not _formal_ready
		and _internal_playtest
		and _capability_mode == "development"
		and _data_source == "placeholder"
	)


func _submission_is_authorized() -> bool:
	if not _confirm_action_authorizes_roster():
		return false
	var formal_submission := (
		_capability_mode == "formal"
		and _data_source != "placeholder"
		and _resident_catalog_status == "formal"
	)
	return formal_submission or _is_explicit_development_submission()


func _confirm_action_authorizes_roster() -> bool:
	if _action_is_enabled("confirm"):
		return true
	# Compatibility for the current formal Host VM: its legacy catalog builder
	# still disables this action when no Provider is configured. Provider/model
	# assignment belongs to the next page, so only that exact stale reason may be
	# normalized here. Every other Host disabled reason remains authoritative.
	return (
		_capability_mode == "formal"
		and _data_source != "placeholder"
		and _resident_catalog_status == "formal"
		and str(_action_config("confirm").get("disabled_reason", ""))
		== "PROVIDER_CONFIGURATION_REQUIRED"
	)


func _payload_matches_selection(payload: Dictionary) -> bool:
	var slots_value: Variant = payload.get("slots", [])
	if not slots_value is Array:
		return false
	var payload_ids: Dictionary = {}
	for slot_value: Variant in slots_value:
		if not slot_value is Dictionary:
			return false
		payload_ids[str((slot_value as Dictionary).get("residentId", ""))] = true
	if payload_ids.size() != STRICT_SESSION_SLOT_COUNT:
		return false
	if _selected_by_id.size() != STRICT_SESSION_SLOT_COUNT:
		return false
	for resident_id: Variant in _selected_by_id:
		if not payload_ids.has(str(resident_id)):
			return false
	return true


func _validate_confirmation_payload(payload: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	if int(payload.get("schemaVersion", 0)) <= 0:
		failures.append("schemaVersion")
	if str(payload.get("sourceScope", "")) != "resident_selection":
		failures.append("sourceScope")
	if int(payload.get("draftRevision", 0)) <= 0:
		failures.append("draftRevision")
	var slots_value: Variant = payload.get("slots", [])
	if not slots_value is Array:
		return {
			"passed": false,
			"slotCount": 0,
			"failures": ["slots_not_array"],
		}
	var slots := slots_value as Array
	if slots.size() != STRICT_SESSION_SLOT_COUNT:
		failures.append("slot_count")
	var homes: Dictionary = {}
	var residents: Dictionary = {}
	for slot_value: Variant in slots:
		if not slot_value is Dictionary:
			failures.append("slot_not_dictionary")
			continue
		var slot := slot_value as Dictionary
		var resident_id := str(slot.get("residentId", ""))
		var space_id := str(slot.get("spaceId", ""))
		if resident_id.is_empty() or residents.has(resident_id):
			failures.append("resident_id_unique")
		residents[resident_id] = true
		if space_id.is_empty() or homes.has(space_id):
			failures.append("space_id_unique")
		homes[space_id] = true
		if slot.has("llmBinding"):
			failures.append("resident_selection_must_not_assign_llm_binding")
	for home_index in range(1, STRICT_SESSION_SLOT_COUNT + 1):
		var expected_home := "home_%02d" % home_index
		if not homes.has(expected_home):
			failures.append("missing_" + expected_home)
	return {
		"passed": failures.is_empty(),
		"slotCount": slots.size(),
		"uniqueResidentCount": residents.size(),
		"uniqueSpaceCount": homes.size(),
		"expectedHomesComplete": failures.filter(
			func(value: String) -> bool: return value.begins_with("missing_")
		).is_empty(),
		"failures": failures,
	}


func _action_config(action_id: String) -> Dictionary:
	var action_value: Variant = _view_model_actions.get(action_id, {})
	if action_value is Dictionary:
		return action_value as Dictionary
	return {}


func _action_is_enabled(action_id: String) -> bool:
	return bool(_action_config(action_id).get("enabled", false))


func _show_notice(message: String) -> void:
	if _notice_label == null:
		return
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_label.text = message
	_notice_label.visible = true
	_notice_label.modulate.a = 1.0
	if _subtitle != null:
		_subtitle.visible = false
	var notice_text := message
	_notice_tween = create_tween()
	_notice_tween.tween_interval(2.7)
	_notice_tween.tween_property(_notice_label, "modulate:a", 0.0, 0.45)
	_notice_tween.finished.connect(
		func() -> void:
			if _notice_label == null or _notice_label.text != notice_text:
				return
			_notice_label.text = ""
			_notice_label.visible = false
			_notice_label.modulate.a = 1.0
			if _subtitle != null:
				_subtitle.visible = _layout_mode == LayoutMode.DESKTOP
	)


func _connection_state() -> String:
	var operation_status := str(_operation.get("status", "idle"))
	if operation_status in ["error", "rejected", "disabled"] or _error_value != null:
		return "disconnected"
	var can_show_connected := (
		_formal_ready
		and _data_source != "placeholder"
		and _capability_mode != "development"
	)
	var capture_state := _env_capture_connection_state
	if capture_state in ["disconnected", "connecting"]:
		return capture_state
	if capture_state == "connected":
		return "connected" if can_show_connected else "disconnected"
	if (
		can_show_connected
		and "已连接" in _connection_label
		and "未连接" not in _connection_label
	):
		return "connected"
	if "连接中" in _connection_label:
		return "connecting"
	return "disconnected"


func _connection_display_text() -> String:
	match _connection_state():
		"connected":
			return "已连接"
		"connecting":
			return "连接中"
		_:
			return "未连接"


func _start_connection_animation() -> void:
	if (
		_connection_icon == null
		or _connection_status == null
		or _connection_box == null
		or not _connection_box.visible
	):
		return
	# 无限循环 tween 必须持有并在重建前 kill，否则每次刷新叠加一条永久 tween。
	if _connection_tween != null and _connection_tween.is_valid():
		_connection_tween.kill()
	_connection_tween = null
	_connection_box.tooltip_text = _connection_label
	var state := _connection_state()
	_connection_status.text = _connection_display_text()
	_connection_icon.rotation = 0.0
	_connection_icon.scale = Vector2.ONE
	_connection_icon.modulate.a = 1.0
	match state:
		"connected":
			_connection_icon.texture = _load_texture(ICON_ROOT + "selected_leaf.png")
			_connection_icon.modulate = COLOR_PAPER
			_connection_icon.pivot_offset = _connection_icon.size * 0.5
			_connection_icon.scale = Vector2(0.88, 0.88)
			_connection_tween = create_tween().set_loops()
			_connection_tween.tween_property(_connection_icon, "scale", Vector2.ONE, 0.42)
			_connection_tween.parallel().tween_property(
				_connection_icon, "modulate:a", 1.0, 0.42
			).from(0.72)
			_connection_tween.tween_property(
				_connection_icon, "scale", Vector2(0.88, 0.88), 0.62
			)
			_connection_tween.parallel().tween_property(
				_connection_icon, "modulate:a", 0.72, 0.62
			)
		"connecting":
			_connection_icon.texture = _load_texture(ICON_ROOT + "ai_spark.png")
			_connection_icon.modulate = COLOR_INK
			_connection_icon.pivot_offset = _connection_icon.size * 0.5
			_connection_tween = create_tween().set_loops()
			_connection_tween.tween_property(_connection_icon, "rotation", 0.20, 0.28)
			_connection_tween.tween_property(_connection_icon, "rotation", -0.20, 0.28)
		_:
			_connection_icon.texture = _load_texture(ICON_ROOT + "empty_box.png")
			_connection_icon.modulate = COLOR_INK


func _queue_responsive_layout() -> void:
	if _responsive_layout_queued:
		return
	_responsive_layout_queued = true
	call_deferred("_apply_queued_responsive_layout")


func _apply_queued_responsive_layout() -> void:
	_responsive_layout_queued = false
	if not is_node_ready():
		return
	_apply_responsive_layout()


func _apply_responsive_layout() -> void:
	if _content_root == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var available_rect := _available_viewport_rect()
	_layout_mode = _layout_mode_for_size(available_rect.size)
	var canvas_size := _canvas_size_for_mode(_layout_mode, available_rect.size)
	_content_root.position = (
		available_rect.position + (available_rect.size - canvas_size) * 0.5
	).round()
	_content_root.size = canvas_size.round()
	_shell.texture = _load_texture(
		UI_SHELL_PATH
		if _layout_mode == LayoutMode.DESKTOP
		else COMPACT_UI_SHELL_PATH
	)
	_shell.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if _layout_mode in [LayoutMode.PHONE_LANDSCAPE, LayoutMode.PHONE_PORTRAIT]
		else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	_apply_header_layout()
	_apply_body_layout()
	_apply_footer_layout()
	_refresh_detail()
	_refresh_count()


func _layout_mode_for_size(viewport_size: Vector2) -> LayoutMode:
	var aspect := viewport_size.x / maxf(1.0, viewport_size.y)
	if viewport_size.x >= 1920.0 and viewport_size.y >= 1080.0:
		return LayoutMode.DESKTOP
	if viewport_size.x >= 1280.0 and viewport_size.y >= 720.0:
		return LayoutMode.STANDARD
	if viewport_size.x >= 900.0 and viewport_size.y >= 680.0:
		return LayoutMode.TABLET
	if aspect >= 1.2:
		return LayoutMode.PHONE_LANDSCAPE
	return LayoutMode.PHONE_PORTRAIT


func _canvas_size_for_mode(mode: LayoutMode, available_size: Vector2) -> Vector2:
	match mode:
		LayoutMode.DESKTOP:
			return DESKTOP_CANVAS
		LayoutMode.STANDARD:
			return STANDARD_CANVAS
		_:
			return available_size


func _available_viewport_rect() -> Rect2:
	var insets := _safe_insets()
	var available_size := Vector2(
		maxf(1.0, size.x - insets.x - insets.z),
		maxf(1.0, size.y - insets.y - insets.w)
	)
	return Rect2(Vector2(insets.x, insets.y), available_size)


func _safe_insets() -> Vector4:
	var pieces := _env_safe_insets_raw.split(",")
	if pieces.size() != 4:
		return Vector4.ZERO
	return Vector4(
		maxf(0.0, float(pieces[0])),
		maxf(0.0, float(pieces[1])),
		maxf(0.0, float(pieces[2])),
		maxf(0.0, float(pieces[3]))
	)


func _apply_header_layout() -> void:
	var desktop := _layout_mode == LayoutMode.DESKTOP
	var mobile := _layout_mode in [
		LayoutMode.PHONE_LANDSCAPE, LayoutMode.PHONE_PORTRAIT
	]
	if desktop:
		_set_rect(_town_clock, Rect2(928, 82, 64, 64))
		_set_rect(_back_button, Rect2(240, 180, 178, 66))
		_set_rect(_back_text, Rect2(0, 0, 178, 66))
		_set_rect(_title, Rect2(525, 158, 854, 72))
		_set_rect(_subtitle, Rect2(605, 222, 694, 28))
		_set_rect(_breadcrumb, Rect2(698, 267, 514, 48))
		_set_rect(_custom_button, Rect2(1434, 178, 124, 68))
		_set_rect(_custom_delete_button, Rect2(1595, 184, 60, 58))
		_set_rect(_connection_box, Rect2(1572, 180, 106, 66))
		_set_rect(_notice_label, Rect2(605, 220, 694, 32))
		_title.add_theme_font_size_override("font_size", FONT_EMPHASIS)
		_back_text.add_theme_font_size_override("font_size", FONT_BODY)
		_town_clock.visible = true
		_subtitle.visible = _notice_label.text.is_empty()
		_notice_label.visible = not _notice_label.text.is_empty()
		_breadcrumb.visible = true
	elif not mobile:
		var canvas_width := _content_root.size.x
		_set_rect(_town_clock, Rect2(canvas_width * 0.5 - 32, 8, 64, 64))
		_set_rect(_back_button, Rect2(16, 10, 136, 74))
		_set_rect(_back_text, Rect2(0, 4, 136, 66))
		_set_rect(_title, Rect2(180, 8, canvas_width - 564, 74))
		_set_rect(_subtitle, Rect2())
		_set_rect(_breadcrumb, Rect2())
		_set_rect(_custom_button, Rect2(canvas_width - 384, 10, 164, 74))
		_set_rect(_custom_delete_button, Rect2(canvas_width - 84, 18, 60, 58))
		_set_rect(_connection_box, Rect2(canvas_width - 236, 4, 220, 88))
		_set_rect(_notice_label, Rect2(180, 84, canvas_width - 360, 128))
		_title.add_theme_font_size_override("font_size", FONT_BODY)
		_back_text.add_theme_font_size_override("font_size", FONT_CAPTION)
		_town_clock.visible = true
		_notice_label.visible = not _notice_label.text.is_empty()
		_subtitle.visible = false
		_breadcrumb.visible = false
	else:
		var canvas_width := _content_root.size.x
		_set_rect(_town_clock, Rect2(canvas_width * 0.5 - 24, 4, 48, 48))
		_set_rect(_back_button, Rect2(8, 40, 64, 74))
		_set_rect(_back_text, Rect2(0, 4, 64, 66))
		_set_rect(_title, Rect2(80, 40, canvas_width - 160, 74))
		_set_rect(_subtitle, Rect2())
		_set_rect(_breadcrumb, Rect2())
		_set_rect(_custom_button, Rect2())
		_set_rect(_custom_delete_button, Rect2(canvas_width - 72, 48, 60, 58))
		_set_rect(_connection_box, Rect2(canvas_width - 72, 40, 64, 74))
		_set_rect(_notice_label, Rect2(24, 114, canvas_width - 48, 128))
		_title.add_theme_font_size_override("font_size", FONT_BODY)
		_back_text.add_theme_font_size_override("font_size", FONT_CAPTION)
		_title.text = "居民名单"
		_custom_button.visible = false
		_town_clock.visible = true
		_notice_label.visible = not _notice_label.text.is_empty()
		_subtitle.visible = false
		_breadcrumb.visible = false
		_connection_status.visible = false
	if not mobile:
		_title.text = "选择要删除的居民" if _delete_mode_active else "选择初始居民"
		_subtitle.text = (
			"勾选后从本局候选列表移除 · 至少保留 15 人"
			if _delete_mode_active
			else "决定谁会在小镇开始生活"
		)
		_back_text.visible = true
		_custom_button.visible = true
		_connection_status.visible = true
		_connection_status.text = _connection_display_text()
	else:
		_title.text = "删除居民" if _delete_mode_active else "居民名单"
		_back_text.visible = true
	# Provider/model connectivity belongs to the following model-assignment
	# page. ResidentSelection keeps the state internally for submission gates,
	# but does not expose a redundant header badge.
	_set_rect(_connection_box, Rect2())
	_connection_box.visible = false
	_connection_icon.visible = false
	_connection_status.visible = false


func _apply_body_layout() -> void:
	var card_size := Vector2(198, 124)
	var columns := 4
	var separation := Vector2i(16, 18)
	match _layout_mode:
		LayoutMode.DESKTOP:
			_set_rect(_roster_scroll, Rect2(245, 323, 920, 522))
			_set_rect(_detail_panel, Rect2(1177, 326, 494, 570))
			columns = 2
			card_size = Vector2(451, 164)
			separation = Vector2i(18, 13)
		LayoutMode.STANDARD:
			_set_rect(_roster_scroll, Rect2(54, 100, 664, 516))
			_set_rect(_detail_panel, Rect2(738, 100, 488, 516))
			card_size = Vector2(160, 120)
			separation = Vector2i(8, 12)
		LayoutMode.TABLET:
			var body_top := 100.0
			var body_height := _content_root.size.y - 188.0
			var roster_width := floorf(_content_root.size.x * 0.68)
			_set_rect(_roster_scroll, Rect2(20, body_top, roster_width - 28, body_height))
			_set_rect(
				_detail_panel,
				Rect2(roster_width + 8, body_top, _content_root.size.x - roster_width - 28, body_height)
			)
			card_size = Vector2(
				floorf((roster_width - 52.0) / 4.0),
				120.0
			)
			separation = Vector2i(8, 12)
		LayoutMode.PHONE_LANDSCAPE:
			var body_rect := Rect2(
				16,
				120,
				_content_root.size.x - 32,
				_content_root.size.y - 200
			)
			_set_rect(_roster_scroll, body_rect)
			_set_rect(_detail_panel, body_rect)
			card_size = Vector2(
				floorf((body_rect.size.x - 36.0) / 4.0),
				120.0
			)
			separation = Vector2i(8, 12)
		LayoutMode.PHONE_PORTRAIT:
			var body_rect := Rect2(
				12,
				120,
				_content_root.size.x - 24,
				_content_root.size.y - 204
			)
			_set_rect(_roster_scroll, body_rect)
			_set_rect(_detail_panel, body_rect)
			columns = 2
			card_size = Vector2(
				floorf((body_rect.size.x - 12.0) / 2.0),
				132.0
			)
			separation = Vector2i(8, 12)
	_configure_grid(columns, card_size, separation)
	_configure_detail_geometry()
	if _layout_mode == LayoutMode.DESKTOP:
		_set_rect(_page_previous_button, Rect2(469, 851, 141, 48))
		_set_rect(_page_status_label, Rect2(610, 853, 162, 44))
		_set_rect(_page_next_button, Rect2(772, 851, 143, 48))
	else:
		_set_rect(_page_previous_button, Rect2())
		_set_rect(_page_status_label, Rect2())
		_set_rect(_page_next_button, Rect2())
	var mobile := _layout_mode in [
		LayoutMode.PHONE_LANDSCAPE, LayoutMode.PHONE_PORTRAIT
	]
	_roster_scroll.visible = not mobile or not _mobile_detail_open
	_detail_panel.visible = not mobile or _mobile_detail_open
	_detail_role.max_lines_visible = 3 if _detail_panel.size.x < 430.0 else 2
	_refresh_resident_pagination()


func _configure_grid(columns: int, card_size: Vector2, separation: Vector2i) -> void:
	_resident_grid.columns = columns
	_resident_grid.add_theme_constant_override("h_separation", separation.x)
	_resident_grid.add_theme_constant_override("v_separation", separation.y)
	for index in range(_card_roots.size()):
		var root := _card_roots[index]
		root.custom_minimum_size = card_size.round()
		_card_backgrounds[index].visible = _layout_mode == LayoutMode.DESKTOP
		if _layout_mode == LayoutMode.DESKTOP:
			_set_rect(_card_portraits[index], Rect2(16, 14, 154, 138))
			_set_rect(_card_number_labels[index], Rect2(173, 15, 36, 32))
			_set_rect(_card_name_slots[index], Rect2(181, 52, 243, 30))
			_set_rect(_card_job_labels[index], Rect2(181, 84, 243, 30))
			_set_rect(_card_location_icons[index], Rect2(175, 113, 32, 32))
			_set_rect(_card_location_labels[index], Rect2(202, 114, 222, 30))
			_set_rect(
				_card_toggle_buttons[index],
				Rect2(card_size.x - TOUCH_TARGET_MIN, 0, TOUCH_TARGET_MIN, TOUCH_TARGET_MIN)
			)
			_card_state_icons[index].set_anchors_and_offsets_preset(
				Control.PRESET_TOP_LEFT
			)
			_set_rect(
				_card_state_icons[index],
				Rect2(1, 20, 26, 26) if _delete_mode_active else Rect2(-6, 6, 52, 52),
			)
			_card_name_labels[index].add_theme_font_size_override(
				"font_size", FONT_CARD_NAME
			)
			_card_job_labels[index].add_theme_font_size_override("font_size", FONT_CARD)
			_card_location_labels[index].add_theme_font_size_override("font_size", FONT_CARD)
			_card_name_labels[index].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_card_number_labels[index].visible = true
			_card_job_labels[index].visible = true
			_card_location_icons[index].visible = true
			_card_location_labels[index].visible = true
		else:
			_set_rect(
				_card_toggle_buttons[index],
				Rect2(card_size.x - TOUCH_TARGET_MIN, 0, TOUCH_TARGET_MIN, TOUCH_TARGET_MIN)
			)
			_card_state_icons[index].set_anchors_and_offsets_preset(
				Control.PRESET_TOP_LEFT
			)
			_set_rect(
				_card_state_icons[index],
				Rect2(1, 20, 26, 26) if _delete_mode_active else Rect2(-4, 0, 56, 56),
			)
			var portrait_height := card_size.y - 52.0
			var portrait_width := minf(64.0, maxf(40.0, card_size.x * 0.34))
			_set_rect(
				_card_portraits[index],
				Rect2(6, 4, portrait_width, portrait_height)
			)
			_set_rect(
				_card_name_slots[index],
				Rect2(8, card_size.y - 48.0, card_size.x - 16.0, 48)
			)
			_set_rect(_card_number_labels[index], Rect2())
			_set_rect(_card_job_labels[index], Rect2())
			_set_rect(_card_location_icons[index], Rect2())
			_set_rect(_card_location_labels[index], Rect2())
			_card_name_labels[index].add_theme_font_size_override(
				"font_size", FONT_BODY
			)
			_card_name_labels[index].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_card_number_labels[index].visible = false
			_card_job_labels[index].visible = false
			_card_location_icons[index].visible = false
			_card_location_labels[index].visible = false


func _configure_detail_geometry() -> void:
	var panel_size := _detail_panel.size
	if _layout_mode == LayoutMode.DESKTOP:
		_set_rect(_overview_shell_overlay, Rect2(1174, 324, 500, 575))
		if _detail_mode == DetailMode.SHOWCASE:
			_set_rect(_detail_name, Rect2(32, 6, 430, 100))
			_set_rect(_detail_sprite, Rect2(117, 88, 260, 300))
			_set_rect(_overview_button, Rect2(24, 406, 446, 58))
			_center_button_icon_and_text(
				_overview_button, _overview_icon, _overview_text, Vector2(48, 48), 8.0
			)
			_set_rect(_detail_toggle_button, Rect2(24, 480, 446, 60))
			_center_button_icon_and_text(
				_detail_toggle_button,
				_detail_toggle_icon,
				_detail_toggle_text,
				Vector2(44, 44),
				8.0
			)
		else:
			_layout_detail_identity_row(Rect2(34, 14, 420, 80))
			_set_rect(_detail_identity_title, Rect2())
			_set_rect(_detail_role, Rect2())
			_set_rect(_detail_location_icon, Rect2(38, 115, 40, 40))
			_set_rect(_detail_location, Rect2(76, 116, 360, 38))
			_set_rect(_overview_scroll, Rect2(42, 176, 414, 330))
			# The formal overview shell already owns a narrow vertical guide on the
			# reading area's right edge.  Center the scrollbar on that guide and
			# give it the same span as the scroll viewport.
			_set_rect(_overview_scroll_track, Rect2(451, 190, 14, 300))
			_set_rect(_detail_toggle_button, Rect2(24, 523, 446, 52))
			_center_button_icon_and_text(
				_detail_toggle_button,
				_detail_toggle_icon,
				_detail_toggle_text,
				Vector2(44, 44),
				8.0
			)
		_overview_scroll_content.custom_minimum_size = Vector2(
			maxf(300.0, _overview_scroll.size.x - 34.0), 0.0
		)
		_refresh_overview_scroll_indicator.call_deferred()
		return
	var margin := 20.0
	var content_width := maxf(160.0, panel_size.x - margin * 2.0)
	if _detail_mode == DetailMode.SHOWCASE:
		_set_rect(_detail_name, Rect2(margin, 8, content_width, 64))
		_set_rect(
			_detail_sprite,
			Rect2(roundf((panel_size.x - 104.0) * 0.5), 108, 104, 164)
		)
		_set_rect(
			_overview_button,
			Rect2(margin, maxf(286.0, panel_size.y - 138.0), content_width, 58)
		)
		_center_button_icon_and_text(
			_overview_button, _overview_icon, _overview_text, Vector2(48, 48), 8.0
		)
	else:
		if panel_size.x < 380.0:
			_layout_detail_identity_row(Rect2(margin, 12, content_width, 76))
			_set_rect(_detail_identity_title, Rect2())
			_set_rect(_detail_role, Rect2())
			_set_rect(_detail_location_icon, Rect2(margin, 102, 40, 40))
			_set_rect(_detail_location, Rect2(margin + 42, 103, content_width - 46, 38))
			_set_rect(
				_overview_scroll,
				Rect2(margin + 12, 160, content_width - 34, maxf(132.0, panel_size.y - 234.0))
			)
			_set_rect(
				_overview_scroll_track,
				Rect2(panel_size.x - margin - 14, 168, 8, maxf(108.0, panel_size.y - 258.0))
			)
		else:
			_layout_detail_identity_row(Rect2(margin, 10, content_width, 68))
			_set_rect(_detail_identity_title, Rect2())
			_set_rect(_detail_role, Rect2())
			_set_rect(_detail_location_icon, Rect2(margin, 82, 40, 40))
			_set_rect(_detail_location, Rect2(margin + 42, 83, content_width - 46, 38))
			_set_rect(
				_overview_scroll,
				Rect2(margin + 12, 140, content_width - 34, maxf(132.0, panel_size.y - 218.0))
			)
			_set_rect(
				_overview_scroll_track,
				Rect2(panel_size.x - margin - 14, 148, 8, maxf(108.0, panel_size.y - 242.0))
			)
	_set_rect(
		_detail_toggle_button,
		Rect2(margin, maxf(350.0, panel_size.y - 66.0), content_width, 58)
	)
	_center_button_icon_and_text(
		_detail_toggle_button,
		_detail_toggle_icon,
		_detail_toggle_text,
		Vector2(44, 44),
		8.0
	)
	_overview_scroll_content.custom_minimum_size = Vector2(
		maxf(140.0, _overview_scroll.size.x - 30.0), 0.0
	)
	_refresh_overview_scroll_indicator.call_deferred()


func _apply_footer_layout() -> void:
	var mobile := _layout_mode in [
		LayoutMode.PHONE_LANDSCAPE, LayoutMode.PHONE_PORTRAIT
	]
	if _layout_mode == LayoutMode.DESKTOP:
		_set_rect(_footer, Rect2(343, 924, 1221, 78))
		_set_rect(_count_label, Rect2(0, 0, 385, 78))
		_count_label.add_theme_font_size_override("font_size", FONT_STATUS)
		_set_rect(_recommended_button, Rect2(412, 0, 211, 78))
		_set_rect(_clear_button, Rect2(649, 0, 167, 78))
		_set_rect(_confirm_button, Rect2(848, 0, 373, 78))
		_set_rect(
			_recommended_icon,
			Rect2(42, 22, 34, 34) if _delete_mode_active else Rect2(22, 3, 72, 72),
		)
		_set_rect(
			_recommended_text,
			Rect2(88, 0, 80, 78) if _delete_mode_active else Rect2(88, 0, 110, 78),
		)
		_set_rect(
			_clear_icon,
			Rect2(21, 22, 34, 34) if _delete_mode_active else Rect2(20, 3, 72, 72),
		)
		_set_rect(
			_clear_text,
			Rect2(67, 0, 80, 78) if _delete_mode_active else Rect2(84, 0, 64, 78),
		)
		_set_rect(
			_confirm_icon,
			Rect2(86, 18, 42, 42) if _delete_mode_active else Rect2(100, 7, 64, 64),
		)
		_set_rect(
			_confirm_text,
			Rect2(138, 0, 150, 78) if _delete_mode_active else Rect2(157, 0, 186, 78),
		)
		if not _delete_mode_active:
			_recommended_text.text = "推荐组合"
	elif not mobile:
		_set_rect(
			_footer,
			Rect2(24, _content_root.size.y - 86, _content_root.size.x - 48, 74)
		)
		var footer_width := _footer.size.x
		_set_rect(_count_label, Rect2(8, 5, 288, 64))
		_count_label.add_theme_font_size_override("font_size", FONT_STATUS)
		_set_rect(_recommended_button, Rect2(footer_width - 648, 5, 164, 64))
		_set_rect(_clear_button, Rect2(footer_width - 472, 5, 120, 64))
		_set_rect(_confirm_button, Rect2(footer_width - 340, 5, 332, 64))
		_set_rect(
			_recommended_icon,
			Rect2(23, 16, 32, 32) if _delete_mode_active else Rect2(13, 4, 56, 56),
		)
		_set_rect(
			_recommended_text,
			Rect2(62, 0, 84, 64) if _delete_mode_active else Rect2(54, 0, 110, 64),
		)
		_set_rect(
			_clear_icon,
			Rect2(8, 16, 32, 32) if _delete_mode_active else Rect2(11, 4, 56, 56),
		)
		_set_rect(
			_clear_text,
			Rect2(43, 0, 69, 64) if _delete_mode_active else Rect2(54, 0, 58, 64),
		)
		_set_rect(
			_confirm_icon,
			Rect2(68, 12, 40, 40) if _delete_mode_active else Rect2(64, 0, 64, 64),
		)
		_set_rect(
			_confirm_text,
			Rect2(116, 0, 150, 64) if _delete_mode_active else Rect2(119, 0, 173, 64),
		)
		if not _delete_mode_active:
			_recommended_text.text = "推荐"
	else:
		_set_rect(
			_footer,
			Rect2(8, _content_root.size.y - 82, _content_root.size.x - 16, 74)
		)
		_set_rect(_count_label, Rect2(8, 5, maxf(0.0, _footer.size.x - 324.0), 64))
		_count_label.add_theme_font_size_override("font_size", FONT_CAPTION)
		_set_rect(
			_confirm_button,
			Rect2(maxf(8.0, _footer.size.x - 308.0), 5, minf(300.0, _footer.size.x - 16.0), 64)
		)
		_set_rect(_recommended_button, Rect2())
		_set_rect(_clear_button, Rect2())
		_set_rect(_confirm_icon, Rect2(40, 0, 64, 64))
		_set_rect(
			_confirm_text,
			Rect2(95, 0, maxf(120.0, _confirm_button.size.x - 103.0), 64)
		)
	_recommended_button.visible = not mobile
	_clear_button.visible = not mobile


func _texture_alpha_bounds(texture: Texture2D) -> Rect2:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2(Vector2.ZERO, texture.get_size())
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.05:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2(Vector2.ZERO, texture.get_size())
	return Rect2(
		Vector2(min_x, min_y),
		Vector2(max_x - min_x + 1, max_y - min_y + 1)
	)


func _button(
	node_name: String,
	button_text: String,
	font_size: int,
	callback: Callable
) -> Button:
	var button := Button.new()
	if not node_name.is_empty():
		button.name = node_name
	button.text = button_text
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if font_size == FONT_CAPTION and _ui_medium_font != null:
		button.add_theme_font_override("font", _ui_medium_font)
	elif _ui_font != null:
		button.add_theme_font_override("font", _ui_font)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_constant_override("outline_size", 1)
	button.add_theme_color_override("font_outline_color", Color("2e1b10"))
	button.add_theme_color_override("font_color", COLOR_INK)
	button.add_theme_color_override("font_hover_color", COLOR_WOOD)
	button.add_theme_color_override("font_pressed_color", COLOR_TERRACOTTA)
	button.pressed.connect(callback)
	return button


func _label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if font_size == FONT_CAPTION and _ui_medium_font != null:
		label.add_theme_font_override("font", _ui_medium_font)
	elif _ui_font != null:
		label.add_theme_font_override("font", _ui_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", LINE_SPACING)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _texture_rect(node_name: String, texture: Texture2D) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.name = node_name
	texture_rect.texture = texture
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture_rect


func _button_icon(button: Button, node_name: String, texture: Texture2D) -> TextureRect:
	var icon := _texture_rect(node_name, texture)
	button.add_child(icon)
	return icon


func _button_overlay_label(
	button: Button,
	node_name: String,
	text: String,
	font_size: int,
	color: Color
) -> Label:
	var label := _label(node_name, text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override("font_outline_color", Color("2e1b10"))
	_apply_bold_font(label)
	button.add_child(label)
	return label


func _register_text(
	entry_id: String,
	control: Control,
	clipping_allowed: bool,
	max_lines: int,
	stress_text: String
) -> void:
	_text_audit_entries.append({
		"id": entry_id,
		"control": control,
		"clipping_allowed": clipping_allowed,
		"max_lines": max_lines,
		"stress": stress_text,
	})


func _register_touch(entry_id: String, control: Control) -> void:
	_touch_audit_entries.append({"id": entry_id, "control": control})


func _apply_bold_font(control: Control) -> void:
	if _ui_bold_font != null:
		control.add_theme_font_override("font", _ui_bold_font)


func _apply_resident_name_font(control: Control) -> void:
	if _ui_resident_name_font != null:
		control.add_theme_font_override("font", _ui_resident_name_font)


func _style_resident_card(button: Button, is_selected: bool, is_focused: bool) -> void:
	var normal_background := Color.TRANSPARENT
	if is_focused:
		normal_background = Color(0.76, 0.30, 0.17, 0.08)
	elif is_selected:
		normal_background = Color(0.35, 0.50, 0.18, 0.06)
	button.add_theme_stylebox_override(
		"normal",
		_flat_style(normal_background, Color.TRANSPARENT, 0, 2)
	)
	button.add_theme_stylebox_override(
		"hover",
		_flat_style(Color(1.0, 0.84, 0.48, 0.10), Color.TRANSPARENT, 0, 2)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_flat_style(Color(0.52, 0.24, 0.10, 0.12), Color.TRANSPARENT, 0, 2)
	)
	button.add_theme_stylebox_override(
		"focus",
		_flat_style(Color(1.0, 0.84, 0.48, 0.08), Color.TRANSPARENT, 0, 2)
	)


func _style_card_toggle(button: Button) -> void:
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override(
		"hover",
		_flat_style(Color(1.0, 0.86, 0.52, 0.12), Color.TRANSPARENT, 0, 2)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_flat_style(Color(0.45, 0.20, 0.08, 0.12), Color.TRANSPARENT, 0, 2)
	)
	button.add_theme_stylebox_override(
		"focus", _flat_style(Color(1.0, 0.86, 0.52, 0.08), Color.TRANSPARENT, 0, 2)
	)


func _style_surface_button(button: Button, dark_surface: bool) -> void:
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override(
		"hover",
		_flat_style(Color(1.0, 0.83, 0.45, 0.13), Color.TRANSPARENT, 0, 3)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_flat_style(Color(0.35, 0.17, 0.07, 0.16), Color.TRANSPARENT, 0, 3)
	)
	button.add_theme_stylebox_override(
		"focus",
		_flat_style(Color(1.0, 0.83, 0.45, 0.10), Color.TRANSPARENT, 0, 3)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_flat_style(Color(0.24, 0.18, 0.11, 0.09), Color.TRANSPARENT, 0, 3)
	)
	if dark_surface:
		button.add_theme_color_override("font_color", COLOR_PAPER)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color("ffe0a1"))


func _style_custom_delete_button(button: Button, active: bool) -> void:
	var state_paths := {
		"normal": (
			CUSTOM_DELETE_BUTTON_PRESSED_PATH
			if active
			else CUSTOM_DELETE_BUTTON_NORMAL_PATH
		),
		"hover": CUSTOM_DELETE_BUTTON_HOVER_PATH,
		"pressed": CUSTOM_DELETE_BUTTON_PRESSED_PATH,
		"focus": CUSTOM_DELETE_BUTTON_HOVER_PATH,
		"disabled": CUSTOM_DELETE_BUTTON_DISABLED_PATH,
	}
	for state: String in state_paths:
		button.add_theme_stylebox_override(
			state,
			_delete_badge_style(_load_texture(String(state_paths[state]))),
		)
	button.add_theme_color_override("icon_normal_color", Color.WHITE)
	button.add_theme_color_override("icon_hover_color", Color("fff2bd"))
	button.add_theme_color_override("icon_pressed_color", Color("cbb58e"))
	button.add_theme_color_override("icon_focus_color", Color.WHITE)
	button.add_theme_color_override("icon_disabled_color", Color("7a7368"))
	button.add_theme_constant_override("outline_size", 0)


func _delete_badge_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.content_margin_left = 8.0
	style.content_margin_top = 7.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.draw_center = true
	return style


func _style_primary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override(
		"hover",
		_flat_style(Color(1.0, 0.77, 0.35, 0.16), Color.TRANSPARENT, 0, 3)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_flat_style(Color(0.28, 0.11, 0.05, 0.18), Color.TRANSPARENT, 0, 3)
	)
	button.add_theme_stylebox_override(
		"focus",
		_flat_style(Color(1.0, 0.77, 0.35, 0.10), Color.TRANSPARENT, 0, 3)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_flat_style(Color(0.21, 0.17, 0.13, 0.18), Color.TRANSPARENT, 0, 3)
	)


# 同参数的样式共用一份 Resource；每次刷新为全部卡片各新建 4 份 StyleBoxFlat
# 是本页最大的对象分配来源。
func _flat_style(
	background_color: Color,
	border_color: Color,
	border_width: int,
	corner_radius: int
) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d" % [
		background_color.to_html(true),
		border_color.to_html(true),
		border_width,
		corner_radius,
	]
	if _flat_style_cache.has(key):
		return _flat_style_cache[key]
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 4.0
	style.content_margin_top = 4.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 4.0
	_flat_style_cache[key] = style
	return style


func _sprite_frame(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var sheet := _load_texture(path)
	if sheet == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0.0, 0.0, 64.0, 80.0)
	return atlas


func _resident_portrait_texture(resident: Dictionary) -> Texture2D:
	var portrait_path := str(resident.get("portrait_path", ""))
	var frame_mode := str(
		resident.get("portrait_frame_mode", "legacy_first_frame"),
	)
	if not portrait_path.is_empty() and frame_mode == "full_texture":
		return _load_texture(portrait_path)
	var fallback_path := (
		portrait_path
		if not portrait_path.is_empty()
		else str(resident.get("sprite_path", ""))
	)
	return _sprite_frame(fallback_path)


func _atlas_texture_region(source: Texture2D, region: Rect2) -> Texture2D:
	if source == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	return atlas


func _alpha_cropped_texture(path: String) -> Texture2D:
	if _alpha_cropped_texture_cache.has(path):
		return _alpha_cropped_texture_cache[path] as Texture2D
	var source := _load_texture(path)
	if source == null:
		return null
	var cropped := _atlas_texture_region(source, _texture_alpha_bounds(source))
	_alpha_cropped_texture_cache[path] = cropped
	return cropped


func _load_texture(path: String) -> Texture2D:
	# 导入资源按路径缓存，跳过每次的 exists+load；
	# 磁盘图片回退路径（自定义头像等可能变化）保持不缓存。
	if _imported_texture_cache.has(path):
		return _imported_texture_cache[path]
	if ResourceLoader.exists(path, "Texture2D"):
		var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
		if imported != null:
			_imported_texture_cache[path] = imported
			return imported
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("无法读取 UI 纹理：%s (%s)" % [path, error_string(error)])
		return null
	return ImageTexture.create_from_image(image)


func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position.round()
	control.size = rect.size.round()


func _layout_detail_identity_row(row_rect: Rect2) -> void:
	# The name and occupation are one semantic line.  Measure the live fonts so
	# the pair stays centered for long names, custom residents and 130% copy.
	var name_font := _detail_name.get_theme_font("font")
	var name_font_size := _detail_name.get_theme_font_size("font_size")
	var meta_font := _detail_meta.get_theme_font("font")
	var meta_font_size := _detail_meta.get_theme_font_size("font_size")
	var name_width := 1.0
	var meta_width := 1.0
	if name_font != null:
		name_width = ceilf(
			name_font.get_string_size(
				_detail_name.text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				name_font_size
			).x
		) + 4.0
	if meta_font != null:
		meta_width = ceilf(
			meta_font.get_string_size(
				_detail_meta.text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				meta_font_size
			).x
		) + 4.0
	var gap := 16.0
	var available_width := maxf(1.0, row_rect.size.x)
	if name_width + gap + meta_width > available_width:
		name_width = minf(name_width, floorf(available_width * 0.44))
		meta_width = maxf(1.0, available_width - name_width - gap)
	var group_width := minf(available_width, name_width + gap + meta_width)
	var start_x := row_rect.position.x + (available_width - group_width) * 0.5
	var name_safe_width := minf(
		available_width - (start_x - row_rect.position.x),
		maxf(160.0, name_width)
	)
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_detail_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Both fields use the same font tier and the same optical vertical offset so
	# the actual Chinese glyphs share one visual baseline inside the header.
	_set_rect(
		_detail_name,
		Rect2(
			start_x,
			row_rect.position.y + 4.0,
			name_safe_width,
			row_rect.size.y
		)
	)
	_set_rect(
		_detail_meta,
		Rect2(
			start_x + name_width + gap,
			row_rect.position.y + 4.0,
			meta_width,
			row_rect.size.y
		)
	)


func _center_button_icon_and_text(
	button: Button,
	icon: TextureRect,
	label: Label,
	icon_size: Vector2,
	gap: float
) -> void:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var visible_text_width := 0.0
	if font != null:
		visible_text_width = ceilf(
			font.get_string_size(
				label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
			).x
		)
	else:
		visible_text_width = float(label.text.length() * font_size)
	visible_text_width = maxf(1.0, visible_text_width + 4.0)
	var safe_text_width := maxf(112.0, ceilf(visible_text_width * 1.35) + 4.0)
	var group_width := icon_size.x + gap + visible_text_width
	var start_x := roundf(maxf(0.0, (button.size.x - group_width) * 0.5))
	var optical_y_offset := 5.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_set_rect(
		icon,
		Rect2(
			start_x,
			roundf((button.size.y - icon_size.y) * 0.5 + optical_y_offset),
			icon_size.x,
			icon_size.y
		)
	)
	_set_rect(
		label,
		Rect2(
			start_x + icon_size.x + gap,
			optical_y_offset,
			minf(safe_text_width, button.size.x - start_x - icon_size.x - gap),
			button.size.y
		)
	)


func _layout_mode_name(mode: LayoutMode) -> String:
	match mode:
		LayoutMode.DESKTOP:
			return "desktop_1920"
		LayoutMode.STANDARD:
			return "standard_1280"
		LayoutMode.TABLET:
			return "tablet_reflow"
		LayoutMode.PHONE_LANDSCAPE:
			return "phone_landscape_roster_or_detail"
		_:
			return "phone_portrait_roster_or_detail"


func _rect_json(rect: Rect2) -> Dictionary:
	return {
		"x": roundi(rect.position.x),
		"y": roundi(rect.position.y),
		"width": roundi(rect.size.x),
		"height": roundi(rect.size.y),
	}
