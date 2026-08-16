class_name ResidentDetailScreen
extends Control


const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")
const RESPONSIVE_VIEWPORT := preload(
	"res://ui/common/ResponsiveViewportPolicy.gd"
)
const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")


signal intent_requested(intent: StringName, payload: Dictionary)
signal action_blocked(intent: StringName, reason: String)
signal view_model_rejected(reason: String)


enum LayoutProfile {
	WIDE,
	STANDARD,
	COMPACT_LANDSCAPE,
	COMPACT_PORTRAIT,
}


const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const TAB_SCENE := preload(
	"res://ui/resident_detail/components/ResidentDetailTabButton.tscn"
)
const CLOSE_SCENE := preload(
	"res://ui/resident_detail/components/ResidentDetailCloseButton.tscn"
)
const REFRESH_SCENE := preload(
	"res://ui/resident_detail/components/ResidentDetailRefreshButton.tscn"
)
const METER_SCENE := preload(
	"res://ui/resident_detail/components/ResidentDetailMeterTrack.tscn"
)
const BACKGROUND_TEXTURE := preload(
	"res://assets/ui/resident_detail/runtime/"
	+ "resident_detail_background.png"
)
const MOBILE_BACKGROUND_TEXTURE := preload(
	"res://assets/ui/resident_detail/runtime/"
	+ "resident_detail_background_transparent_v1.png"
)
const STATUS_DETAIL_PANEL_TEXTURE := preload(
	"res://assets/ui/common/runtime/paper_wood_panel/"
	+ "paper_wood_panel_master_v1_512.png"
)
const RELATIONSHIP_BACKGROUND_TEXTURE := preload(
	"res://assets/ui/resident_detail/runtime/"
	+ "relationship_page_clean_v4.png"
)
const MOBILE_RELATIONSHIP_BACKGROUND_TEXTURE := preload(
	"res://assets/ui/resident_detail/runtime/"
	+ "relationship_page_transparent_v1.png"
)
const MEMORY_BACKGROUND_TEXTURE := preload(
	"res://assets/ui/resident_detail/runtime/"
	+ "memory_page_clean_v4.png"
)
const MOBILE_MEMORY_BACKGROUND_TEXTURE := preload(
	"res://assets/ui/resident_detail/runtime/"
	+ "memory_page_transparent_v1.png"
)
const MEMORY_OPERATION_BACKGROUND_TEXTURE := preload(
	"res://assets/ui/resident_detail/runtime/"
	+ "memory_operation_page_clean_v5.png"
)
const MOBILE_MEMORY_OPERATION_BACKGROUND_TEXTURE := preload(
	"res://assets/ui/resident_detail/runtime/"
	+ "memory_operation_page_transparent_v1.png"
)
const RELATIONSHIP_ROW_TEXTURE := preload(
	"res://assets/ui/resident_detail/runtime/"
	+ "relationship_row_exact_v3.png"
)
const MEMORY_ROW_TEXTURE := preload(
	"res://assets/ui/resident_detail/runtime/"
	+ "memory_row_exact_v3.png"
)
const SCROLLBAR_TRACK_TEXTURE := preload(
	"res://assets/ui/common/scrollbar/wood_v1/variants/dropdown_short/"
	+ "scrollbar_track_wood_v1_dropdown_short.png"
)
const SCROLLBAR_THUMB_TEXTURE := preload(
	"res://assets/ui/common/scrollbar/wood_v1/variants/dropdown_short/"
	+ "scrollbar_thumb_wood_v1_dropdown_short.png"
)
const PAGE_THEME := preload(
	"res://ui/resident_detail/components/ResidentDetailReferenceTypography.tres"
)
const RESIDENT_GRAYSCALE_SHADER := preload(
	"res://world/presentation/lifecycle/resident_grayscale.gdshader"
)
const SELECTED_GREEN := Color("49684a")

const SCOPE := &"resident_detail"
const DESIGN_SIZE := Vector2(1920, 1080)
const MINIMUM_TOUCH_SIZE := Vector2(48, 48)
const VALID_DATA_STATUSES: Array[String] = [
	"ready",
	"loading",
	"partial",
	"stale",
	"error",
	"disabled",
]
const TAB_IDS: Array[String] = [
	"status",
	"relationships",
	"memories",
]
const TAB_LABELS := {
	"status": "状态",
	"relationships": "关系",
	"memories": "记忆",
}
const ACTION_KEYS := {
	"status": "selectStatus",
	"relationships": "selectRelationships",
	"memories": "selectMemories",
}
const ACTION_INTENTS := {
	"close": "resident_detail.close",
	"selectStatus": "resident_detail.select_tab",
	"selectRelationships": "resident_detail.select_tab",
	"selectMemories": "resident_detail.select_tab",
	"refresh": "resident_detail.refresh",
	"retry": "resident_detail.retry",
	"editMemory": "resident_detail.change_memory",
	"deleteMemory": "resident_detail.change_memory",
	"filterInfluencing": "resident_detail.filter_memories",
	"filterAll": "resident_detail.filter_memories",
	"filterPast": "resident_detail.filter_memories",
	"filterDoubtful": "resident_detail.filter_memories",
	"filterAnomalous": "resident_detail.filter_memories",
	"filterInterventions": "resident_detail.filter_memories",
	"filterRelationshipAll": "resident_detail.filter_relationships",
	"filterRelationshipClose": "resident_detail.filter_relationships",
	"filterRelationshipTrust": "resident_detail.filter_relationships",
	"filterRelationshipConflict": "resident_detail.filter_relationships",
	"filterRelationshipDistant": "resident_detail.filter_relationships",
	"filterRelationshipPlayer": "resident_detail.filter_relationships",
	"writeMemory": "resident_detail.change_memory",
	"previousMemoryPage": "resident_detail.page_memories",
	"nextMemoryPage": "resident_detail.page_memories",
}
const OPTIONAL_ACTION_KEYS: Array[String] = [
	"editMemory",
	"deleteMemory",
	"filterInfluencing",
	"filterAll",
	"filterPast",
	"filterDoubtful",
	"filterAnomalous",
	"filterInterventions",
	"filterRelationshipAll",
	"filterRelationshipClose",
	"filterRelationshipTrust",
	"filterRelationshipConflict",
	"filterRelationshipDistant",
	"filterRelationshipPlayer",
	"writeMemory",
	"previousMemoryPage",
	"nextMemoryPage",
]
const VALID_TAB_AVAILABILITIES: Array[String] = [
	"ready",
	"loading",
	"refreshing",
	"partial",
	"stale",
	"error",
	"disabled",
	"unavailable",
]
const FORBIDDEN_PRIVATE_DATA_KEYS: Array[String] = [
	"prompt",
	"systemprompt",
	"rawresponse",
	"rawmodelresponse",
	"rawoutput",
	"chainofthought",
	"privatememorytext",
	"privaterelationshipstate",
	"embedding",
	"retrievalscore",
	"storagepath",
	"agentstoragepath",
	"sourceprompt",
	"providerobject",
	"trace",
	"traceid",
	"operationid",
	"actionid",
	"decisionid",
	"apikey",
	"diagnostics",
	"httpresponse",
	"agentnode",
	"worldnode",
]
const STATUS_FEEDBACK := {
	"ready": "",
	"loading": "正在整理公开摘要，保留上次确认内容。",
	"partial": "部分公开资料暂缺，已保留可用内容。",
	"stale": "当前显示上次确认内容，正在等待更新。",
	"error": "新的公开摘要暂时没有完成整理。",
	"disabled": "居民公开资料暂时无法查看。",
}
const OPERATION_FEEDBACK := {
	"idle": "",
	"loading": "正在处理……",
	# A successful refresh must not create a second banner line that pushes the
	# relationship or memory heading outside its painted slot.
	"success": "",
	"rejected": "这次操作没有完成，原有资料仍然保留。",
	"error": "这次操作暂时没有完成。",
	"disabled": "当前操作尚不可用。",
}

const WIDE_NAME_RECT := Rect2(220, 292, 344, 96)
const WIDE_OCCUPATION_RECT := Rect2(214, 766, 352, 70)
const WIDE_SPRITE_RECT := Rect2(264, 400, 256, 320)
const WIDE_TAB_RECTS: Array[Rect2] = [
	Rect2(908, 72, 228, 110),
	Rect2(1156, 72, 208, 110),
	Rect2(1386, 72, 218, 110),
]
const WIDE_TAB_TEXT_RECTS: Array[Rect2] = [
	Rect2(909, 70, 228, 110),
	Rect2(1153, 70, 208, 110),
	Rect2(1379, 70, 218, 110),
]
const WIDE_CLOSE_RECT := Rect2(1796, 72, 74, 96)
const WIDE_BANNER_RECT := Rect2(660, 200, 1150, 105)
const WIDE_CONTENT_RECT := Rect2(635, 304, 1224, 569)
const WIDE_SECTION_BANNER_RECT := Rect2(675, 205, 1080, 105)
const WIDE_SECTION_CONTENT_RECT := Rect2(660, 382, 1160, 566)
const WIDE_MEMORY_CONTENT_RECT := Rect2(660, 382, 1160, 521)
const WIDE_STATUS_FRESHNESS_RECT := Rect2(660, 883, 970, 76)
const WIDE_STATUS_ACTION_RECT := Rect2(1650, 883, 150, 76)
const WIDE_FRESHNESS_RECT := Rect2(660, 958, 660, 59)
const WIDE_SECTION_ACTION_RECT := Rect2(1363, 958, 214, 59)
const WIDE_ACTION_RECT := Rect2(1609, 958, 187, 59)
const WIDE_MEMORY_FRESHNESS_RECT := Rect2(660, 903, 660, 60)
const WIDE_MEMORY_SECTION_ACTION_RECT := Rect2(1363, 903, 214, 60)
const WIDE_MEMORY_ACTION_RECT := Rect2(1609, 903, 187, 60)
const WIDE_MEMORY_OPERATION_FRESHNESS_RECT := Rect2(660, 928, 660, 60)
const WIDE_MEMORY_OPERATION_SECTION_ACTION_RECT := Rect2(1363, 928, 214, 60)
const WIDE_MEMORY_OPERATION_ACTION_RECT := Rect2(1609, 928, 187, 60)
const WIDE_SECTION_FILTER_RECTS: Array[Rect2] = [
	Rect2(660, 315, 177, 55),
	Rect2(851, 315, 177, 55),
	Rect2(1043, 315, 177, 55),
	Rect2(1234, 315, 177, 55),
	Rect2(1425, 315, 177, 55),
	Rect2(1598, 315, 177, 55),
]
const WIDE_RELATIONSHIP_ROW_RECTS: Array[Rect2] = [
	Rect2(661, 382, 1113, 110),
	Rect2(661, 496, 1113, 110),
	Rect2(661, 610, 1113, 110),
	Rect2(661, 724, 1113, 110),
	Rect2(661, 838, 1113, 110),
]
const WIDE_MEMORY_ROW_RECTS: Array[Rect2] = [
	Rect2(660, 383, 1114, 173),
	Rect2(660, 556, 1114, 173),
	Rect2(660, 729, 1114, 173),
]
const WIDE_MEMORY_OPERATION_RECTS := {
	"title": Rect2(1030, 218, 375, 58),
	"selectedHeading": Rect2(675, 290, 410, 42),
	"selectedBody": Rect2(685, 335, 350, 500),
	"operationHeading": Rect2(1120, 290, 675, 42),
	"editTab": Rect2(1121, 337, 309, 56),
	"deleteTab": Rect2(1451, 337, 317, 56),
	"inputHeading": Rect2(1121, 411, 667, 38),
	"input": Rect2(1121, 450, 609, 290),
	"hint": Rect2(1121, 760, 667, 72),
	"cancel": Rect2(1145, 850, 265, 62),
	"confirm": Rect2(1475, 850, 265, 62),
}
const WIDE_MEMORY_OPERATION_SCROLL_RECTS := {
	"selected": Rect2(1042, 335, 38, 500),
	"input": Rect2(1734, 450, 38, 290),
}
const WIDE_ROW_RECTS: Array[Rect2] = [
	Rect2(745, 317, 1046, 107),
	Rect2(745, 424, 1046, 106),
	Rect2(745, 530, 1046, 108),
	Rect2(745, 638, 1046, 107),
	Rect2(745, 745, 1046, 111),
]

@export var bind_on_ready := false

var _adapter: Object
var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _current_revision := -1
var _layout_profile := LayoutProfile.WIDE
var _layout_profile_override_size := Vector2.ZERO
var _safe_insets_override := Vector4(-1, -1, -1, -1)
var _safe_rect := Rect2()
var _layout_queued := false
var _selected_content_index := -1
var _selected_memory_key := ""
var _selected_content_font: FontVariation
var _last_operation_request_id := ""
var _completed_request_ids: Dictionary = {}
var _local_feedback := ""
var _adapter_contract_available := false
var _memory_operation_visible := false
var _memory_operation_mode := "edit"
var _semantic_focus_request_id := 0

var _background: TextureRect
var _resident_sprite: TextureRect
var _name_label: Label
var _occupation_label: Label
var _banner_label: Label
var _feedback_label: Label
var _freshness_label: Label
var _content_scroll: ScrollContainer
var _content_root: Control
var _meter_overlay_root: Control
var _close_button: ResidentDetailCloseButton
var _action_button: ResidentDetailRefreshButton
var _section_action_button: ResidentDetailRefreshButton
var _memory_operation_root: Control
var _memory_operation_title: Label
var _memory_operation_selected_heading: Label
var _memory_operation_selected_body: RichTextLabel
var _memory_operation_heading: Label
var _memory_operation_edit_tab: Button
var _memory_operation_delete_tab: Button
var _memory_operation_input_heading: Label
var _memory_operation_input: TextEdit
var _memory_operation_hint: Label
var _memory_operation_cancel: ResidentDetailRefreshButton
var _memory_operation_confirm: ResidentDetailRefreshButton
var _content_scroll_chrome: Control
var _selected_memory_scroll_chrome: Control
var _memory_input_scroll_chrome: Control
var _wood_scroll_chromes: Array[Dictionary] = []
var _wood_scroll_refresh_queued := false
var _status_detail_backdrop: Control
var _status_detail_panel: NinePatchRect
var _status_detail_title: Label
var _status_detail_text: RichTextLabel
var _status_detail_row_index := -1
var _tab_buttons: Dictionary = {}
var _section_filter_buttons: Array[Button] = []
var _row_controls: Array[Control] = []
var _focus_controls: Array[Control] = []
var _row_rects: Array[Rect2] = []
var _banner_rect := Rect2()
var _content_rect := Rect2()
var _freshness_rect := Rect2()
var _action_rect := Rect2()
var _section_action_rect := Rect2()
var _section_filter_rects: Array[Rect2] = []
var _close_rect := Rect2()
var _name_rect := Rect2()
var _occupation_rect := Rect2()
var _sprite_rect := Rect2()
var _tab_rects: Array[Rect2] = []
var _tab_text_rects: Array[Rect2] = []
var _wide_layout_scale := Vector2.ONE
var _wide_layout_origin := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = PAGE_THEME
	_selected_content_font = FontVariation.new()
	_selected_content_font.base_font = PAGE_THEME.default_font
	_selected_content_font.variation_embolden = 0.8
	_build_interface()
	resized.connect(_queue_layout)
	get_viewport().size_changed.connect(_queue_layout)
	if _adapter != null:
		_refresh_from_adapter()
	else:
		_enter_adapter_unavailable(
			"RESIDENT_DETAIL_ADAPTER_NOT_BOUND",
			"正式 TownUiAdapter 尚未绑定。"
		)
	_queue_layout()


func _exit_tree() -> void:
	_disconnect_adapter()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var cancel_requested := event.is_action_pressed(&"ui_cancel")
	if event is InputEventKey:
		cancel_requested = (
			cancel_requested
			or (event as InputEventKey).keycode == KEY_ESCAPE
		)
	if cancel_requested:
		if _memory_operation_visible:
			_close_memory_operation_panel()
			get_viewport().set_input_as_handled()
			return
		if (
			is_instance_valid(_status_detail_backdrop)
			and _status_detail_backdrop.visible
		):
			_close_status_detail_popup()
			get_viewport().set_input_as_handled()
			return
		_request_action("close", {})
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_focus_next"):
		_move_focus(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_focus_prev"):
		_move_focus(-1)
		get_viewport().set_input_as_handled()
		return
	if (
		event.is_action_pressed(&"ui_left")
		or event.is_action_pressed(&"ui_right")
	):
		var focused := get_viewport().gui_get_focus_owner()
		var tab_index := -1
		for index: int in TAB_IDS.size():
			if _tab_buttons.get(TAB_IDS[index]) == focused:
				tab_index = index
				break
		if tab_index >= 0:
			var direction := (
				-1 if event.is_action_pressed(&"ui_left") else 1
			)
			for step: int in TAB_IDS.size():
				var next_index := posmod(
					tab_index + direction * (step + 1),
					TAB_IDS.size()
				)
				var next_tab := _tab_buttons.get(
					TAB_IDS[next_index]
				) as Control
				if _is_focusable_control(next_tab):
					next_tab.grab_focus()
					break
			get_viewport().set_input_as_handled()


func bind_town_ui_adapter(adapter: Object) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	_adapter = adapter
	_reset_view_model_state()
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	if not is_node_ready():
		return
	if _adapter == null:
		_enter_adapter_unavailable(
			"RESIDENT_DETAIL_ADAPTER_NOT_BOUND",
			"正式 TownUiAdapter 尚未绑定。"
		)
	else:
		_refresh_from_adapter()


func unbind_town_ui_adapter() -> void:
	bind_town_ui_adapter(null)


func apply_view_model(snapshot: Dictionary) -> bool:
	var issues := _validate_view_model(snapshot)
	if not issues.is_empty():
		var reason := "\n".join(issues)
		view_model_rejected.emit(reason)
		return false
	var incoming_revision := UiViewModel.revision(snapshot)
	if _current_revision >= 0 and incoming_revision < _current_revision:
		view_model_rejected.emit(
			"STALE_REVISION_%d_LT_%d"
			% [incoming_revision, _current_revision]
		)
		return false

	var incoming_data := UiViewModel.data(snapshot)
	var operation_status := str(
		UiViewModel.operation_status(snapshot)
	)
	var data_status := str(snapshot.get("status", "disabled"))
	var same_resident := _same_resident(
		incoming_data,
		_last_confirmed_data
	)
	if (
		data_status in ["ready", "partial", "stale"]
		and operation_status in ["idle", "success", "disabled"]
		and not incoming_data.is_empty()
	):
		_last_confirmed_data = incoming_data.duplicate(true)
	if (
		operation_status in ["loading", "rejected", "error"]
		and not _last_confirmed_data.is_empty()
		and (incoming_data.is_empty() or same_resident)
	):
		_render_data = _last_confirmed_data.duplicate(true)
	elif (
		data_status in ["loading", "error"]
		and not _last_confirmed_data.is_empty()
		and (incoming_data.is_empty() or same_resident)
	):
		_render_data = _last_confirmed_data.duplicate(true)
	else:
		_render_data = incoming_data.duplicate(true)
	if _render_data.is_empty():
		_render_data = incoming_data.duplicate(true)

	_view_model = snapshot.duplicate(true)
	_current_revision = incoming_revision
	_adapter_contract_available = true
	_local_feedback = ""
	_update_operation_receipt()
	if is_node_ready():
		_cancel_semantic_focus_restore()
		var focused_semantic := _focused_semantic()
		_render()
		_queue_semantic_focus_restore(focused_semantic)
	return true


func current_revision() -> int:
	return _current_revision


func current_view_model() -> Dictionary:
	return _view_model.duplicate(true)


func current_render_data() -> Dictionary:
	return _render_data.duplicate(true)


func current_layout_profile() -> String:
	return _layout_profile_name(_layout_profile)


func adapter_contract_available() -> bool:
	return _adapter_contract_available


func set_layout_profile_size_override(profile_size: Vector2) -> void:
	_layout_profile_override_size = profile_size.round()
	_queue_layout()


func clear_layout_profile_size_override() -> void:
	_layout_profile_override_size = Vector2.ZERO
	_queue_layout()


func set_safe_insets_override(insets: Vector4) -> void:
	_safe_insets_override = Vector4(
		maxf(0.0, insets.x),
		maxf(0.0, insets.y),
		maxf(0.0, insets.z),
		maxf(0.0, insets.w)
	).round()
	_queue_layout()


func clear_safe_insets_override() -> void:
	_safe_insets_override = Vector4(-1, -1, -1, -1)
	_queue_layout()


func focus_default() -> void:
	var selected_tab := str(
		_render_data.get("selectedTab", "status")
	)
	var tab := _tab_buttons.get(selected_tab) as Control
	if _is_focusable_control(tab):
		_queue_focus_grab(tab)
		return
	for control: Control in _focus_controls:
		if _is_focusable_control(control):
			_queue_focus_grab(control)
			return


func request_close() -> bool:
	return _request_action("close", {})


func request_refresh() -> bool:
	return _request_action(_primary_action_key(), {})


func request_tab(tab_id: String) -> bool:
	if tab_id not in TAB_IDS:
		return false
	return _request_action(
		str(ACTION_KEYS[tab_id]),
		{"tabId": tab_id}
	)


func runtime_gate_snapshot() -> Dictionary:
	var text_slots: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(
		"resident_detail_text_slot"
	):
		if not is_ancestor_of(node):
			continue
		var label := node as Label
		if label == null or not label.is_visible_in_tree():
			continue
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		text_slots.append({
			"id": str(label.get_meta("gate_id", label.name)),
			"text": label.text,
			"rect": _rect_payload(label.get_global_rect()),
			"fontSize": font_size,
			"lineHeight": (
				font.get_height(font_size) if font != null else 0.0
			),
			"lineCount": label.get_line_count(),
			"visibleLineCount": label.get_visible_line_count(),
			"maxLines": label.max_lines_visible,
			"safeLineCapacity": int(label.get_meta(
				"safe_line_capacity",
				label.max_lines_visible,
			)),
			"overrun": label.text_overrun_behavior,
		})
	var touch_targets: Array[Dictionary] = []
	for control: Control in _focus_controls:
		if not _is_focusable_control(control):
			continue
		touch_targets.append({
			"id": str(control.name),
			"rect": _rect_payload(control.get_global_rect()),
			"focusMode": control.focus_mode,
		})
	return {
		"scope": str(_view_model.get("scope", "")),
		"revision": _current_revision,
		"status": str(_view_model.get("status", "")),
		"operationStatus": str(
			UiViewModel.operation_status(_view_model)
		),
		"formalReady": bool(
			_render_data.get("formalReady", false)
		),
		"source": str(_render_data.get("source", "")),
		"adapterContractAvailable": _adapter_contract_available,
		"selectedTab": str(
			_render_data.get("selectedTab", "status")
		),
		"layoutProfile": current_layout_profile(),
		"wholePageScale": [scale.x, scale.y],
		"safeRect": _rect_payload(_safe_rect),
		"backgroundAsset": (
			_background.texture.resource_path
			if _background.texture != null
			else ""
		),
		"rowCount": _row_controls.size(),
		"textSlots": text_slots,
		"touchTargets": touch_targets,
		"privacyChecked": not _contains_forbidden_private_data(
			_render_data
		),
	}


func _build_interface() -> void:
	_background = TextureRect.new()
	_background.name = "FormalResidentDetailShell"
	_background.texture = (
		MOBILE_BACKGROUND_TEXTURE
		if MOBILE_UI_PROFILE.is_mobile_runtime()
		else BACKGROUND_TEXTURE
	)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_resident_sprite = TextureRect.new()
	_resident_sprite.name = "ResidentPortrait"
	_resident_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_resident_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_resident_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_resident_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_resident_sprite)

	_name_label = _make_label(
		"ResidentName",
		48,
		Color("3f2818"),
		HORIZONTAL_ALIGNMENT_CENTER,
		1
	)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_name_label)
	_occupation_label = _make_label(
		"ResidentOccupation",
		28,
		Color("3f2818"),
		HORIZONTAL_ALIGNMENT_CENTER,
		1
	)
	_occupation_label.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS
	)
	add_child(_occupation_label)

	for tab_id: String in TAB_IDS:
		var tab := TAB_SCENE.instantiate() as ResidentDetailTabButton
		tab.name = "Tab_%s" % tab_id
		tab.activated.connect(_on_tab_activated)
		add_child(tab)
		_tab_buttons[tab_id] = tab

	_close_button = CLOSE_SCENE.instantiate() as ResidentDetailCloseButton
	_close_button.name = "Close"
	_close_button.close_requested.connect(_on_close_requested)
	add_child(_close_button)

	_banner_label = _make_label(
		"DetailBanner",
		32,
		Color("3f2818"),
		HORIZONTAL_ALIGNMENT_CENTER,
		2
	)
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_banner_label)

	for index: int in 6:
		var filter_button := Button.new()
		filter_button.name = "SectionFilter_%d" % index
		filter_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		filter_button.clip_text = true
		filter_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		filter_button.focus_mode = Control.FOCUS_ALL
		filter_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		filter_button.add_theme_font_size_override("font_size", 27)
		filter_button.add_theme_color_override("font_color", Color("3f2818"))
		filter_button.add_theme_color_override("font_hover_color", Color("b94d2d"))
		filter_button.add_theme_color_override("font_pressed_color", Color("6c3d20"))
		filter_button.add_theme_color_override("font_focus_color", Color("b94d2d"))
		filter_button.add_theme_color_override("font_disabled_color", Color("806a5b"))
		var empty_style := StyleBoxEmpty.new()
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			filter_button.add_theme_stylebox_override(state, empty_style)
		filter_button.pressed.connect(_on_section_filter_pressed.bind(index))
		filter_button.visible = false
		add_child(filter_button)
		_section_filter_buttons.append(filter_button)

	_content_scroll = ScrollContainer.new()
	_content_scroll.name = "ContentScroll"
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_content_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content_scroll)

	_content_root = Control.new()
	_content_root.name = "Content"
	_content_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_content_scroll.add_child(_content_root)
	_content_scroll_chrome = _build_wood_scroll_chrome(
		self,
		"ContentWoodScrollbar",
		_content_scroll.get_v_scroll_bar(),
	)

	_meter_overlay_root = Control.new()
	_meter_overlay_root.name = "LifeMeterOverlay"
	_meter_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter_overlay_root.visible = false
	add_child(_meter_overlay_root)

	_feedback_label = _make_label(
		"StatusFeedback",
		24,
		Color("8f3b23"),
		HORIZONTAL_ALIGNMENT_CENTER,
		2
	)
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_feedback_label)

	_freshness_label = _make_label(
		"Freshness",
		32,
		Color("3f2818"),
		HORIZONTAL_ALIGNMENT_LEFT,
		1
	)
	_freshness_label.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS
	)
	add_child(_freshness_label)

	_action_button = REFRESH_SCENE.instantiate() as ResidentDetailRefreshButton
	_action_button.name = "PrimaryAction"
	_action_button.refresh_requested.connect(_on_primary_action_requested)
	add_child(_action_button)

	_section_action_button = REFRESH_SCENE.instantiate() as ResidentDetailRefreshButton
	_section_action_button.name = "SectionAction"
	_section_action_button.refresh_requested.connect(_on_section_action_requested)
	_section_action_button.visible = false
	add_child(_section_action_button)

	_build_status_detail_popup()
	_build_memory_operation_panel()


func _build_memory_operation_panel() -> void:
	_memory_operation_root = Control.new()
	_memory_operation_root.name = "MemoryOperation"
	_memory_operation_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_memory_operation_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_memory_operation_root.visible = false
	add_child(_memory_operation_root)

	_memory_operation_title = _make_label(
		"MemoryOperationTitle", 30, Color("3f2818"), HORIZONTAL_ALIGNMENT_CENTER, 1,
	)
	_memory_operation_title.text = "记忆操作"
	_memory_operation_root.add_child(_memory_operation_title)

	_memory_operation_selected_heading = _make_label(
		"MemoryOperationSelectedHeading", 23, Color("3f2818"), HORIZONTAL_ALIGNMENT_CENTER, 1,
	)
	_memory_operation_selected_heading.text = "已选记忆"
	_memory_operation_root.add_child(_memory_operation_selected_heading)

	_memory_operation_selected_body = RichTextLabel.new()
	_memory_operation_selected_body.name = "MemoryOperationSelectedBody"
	# 正文较长时由这个控件自己接收滚轮；否则 scroll_active 虽然开启，
	# 玩家把鼠标放在正文上仍无法查看框外内容。
	_memory_operation_selected_body.mouse_filter = Control.MOUSE_FILTER_STOP
	_memory_operation_selected_body.fit_content = false
	# 记忆正文长度来自运行数据；短文不显示滚动，超长内容仍可完整查看。
	_memory_operation_selected_body.scroll_active = true
	_memory_operation_selected_body.bbcode_enabled = false
	_memory_operation_selected_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_memory_operation_selected_body.add_theme_font_override(
		"normal_font", PAGE_THEME.default_font
	)
	_memory_operation_selected_body.add_theme_font_size_override(
		"normal_font_size", 20
	)
	_memory_operation_selected_body.add_theme_color_override(
		"default_color", Color("3f2818")
	)
	_memory_operation_selected_body.add_theme_constant_override("line_separation", 3)
	_memory_operation_selected_body.add_to_group("resident_detail_text_slot")
	_memory_operation_selected_body.set_meta("gate_id", "MemoryOperationSelectedBody")
	_memory_operation_root.add_child(_memory_operation_selected_body)

	_memory_operation_heading = _make_label(
		"MemoryOperationHeading", 23, Color("3f2818"), HORIZONTAL_ALIGNMENT_CENTER, 1,
	)
	_memory_operation_heading.text = "可执行操作"
	_memory_operation_root.add_child(_memory_operation_heading)

	_memory_operation_edit_tab = _make_memory_operation_tab("改写记忆", "edit")
	_memory_operation_delete_tab = _make_memory_operation_tab("删除记忆", "delete")

	_memory_operation_input_heading = _make_label(
		"MemoryOperationInputHeading", 22, Color("3f2818"), HORIZONTAL_ALIGNMENT_LEFT, 1,
	)
	_memory_operation_input_heading.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS
	)
	_memory_operation_root.add_child(_memory_operation_input_heading)

	_memory_operation_input = TextEdit.new()
	_memory_operation_input.name = "MemoryOperationInput"
	_memory_operation_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_memory_operation_input.add_theme_font_override("font", PAGE_THEME.default_font)
	_memory_operation_input.add_theme_font_size_override("font_size", 20)
	_memory_operation_input.add_theme_color_override("font_color", Color("3f2818"))
	_memory_operation_input.add_theme_color_override("caret_color", Color("6c3d20"))
	_memory_operation_input.text_changed.connect(_on_memory_input_text_changed)
	var empty_style := StyleBoxEmpty.new()
	for state: String in ["normal", "focus", "read_only"]:
		_memory_operation_input.add_theme_stylebox_override(state, empty_style)
	_memory_operation_root.add_child(_memory_operation_input)

	_memory_operation_hint = _make_label(
		"MemoryOperationHint", 19, Color("806a5b"), HORIZONTAL_ALIGNMENT_CENTER, 3,
	)
	_memory_operation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_memory_operation_root.add_child(_memory_operation_hint)

	_memory_operation_cancel = REFRESH_SCENE.instantiate() as ResidentDetailRefreshButton
	_memory_operation_cancel.name = "CancelMemoryOperation"
	_memory_operation_cancel.refresh_requested.connect(_close_memory_operation_panel)
	_memory_operation_cancel.configure({
		"label": "取消", "accessibleLabel": "取消记忆操作", "fontSize": 25,
		"disabled": false, "surfaceVisible": false,
	})
	_memory_operation_root.add_child(_memory_operation_cancel)

	_memory_operation_confirm = REFRESH_SCENE.instantiate() as ResidentDetailRefreshButton
	_memory_operation_confirm.name = "ConfirmMemoryOperation"
	_memory_operation_confirm.refresh_requested.connect(_confirm_memory_operation)
	_memory_operation_confirm.configure({
		"label": "确认修改", "accessibleLabel": "确认修改记忆", "fontSize": 25,
		"disabled": false, "surfaceVisible": false,
	})
	_memory_operation_root.add_child(_memory_operation_confirm)

	_selected_memory_scroll_chrome = _build_wood_scroll_chrome(
		_memory_operation_root,
		"SelectedMemoryWoodScrollbar",
		_memory_operation_selected_body.get_v_scroll_bar(),
	)
	_memory_input_scroll_chrome = _build_wood_scroll_chrome(
		_memory_operation_root,
		"MemoryInputWoodScrollbar",
		_memory_operation_input.get_v_scroll_bar(),
	)


func _make_memory_operation_tab(copy: String, operation: String) -> Button:
	var button := Button.new()
	button.name = "MemoryOperation%sTab" % operation.capitalize()
	button.text = copy
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", Color("3f2818"))
	button.add_theme_color_override("font_hover_color", Color("b94d2d"))
	button.add_theme_color_override("font_pressed_color", Color("6c3d20"))
	button.pressed.connect(_set_memory_operation_mode.bind(operation))
	_memory_operation_root.add_child(button)
	return button


func _build_wood_scroll_chrome(
	parent: Control,
	node_name: String,
	scrollbar: VScrollBar,
) -> Control:
	if scrollbar == null:
		return null
	scrollbar.self_modulate.a = 0.0
	scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := Control.new()
	chrome.name = node_name
	chrome.visible = false
	chrome.z_index = 30
	chrome.mouse_filter = Control.MOUSE_FILTER_STOP
	chrome.mouse_default_cursor_shape = Control.CURSOR_DRAG
	parent.add_child(chrome)
	var track := TextureRect.new()
	track.name = "Track"
	track.texture = SCROLLBAR_TRACK_TEXTURE
	track.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	track.stretch_mode = TextureRect.STRETCH_SCALE
	track.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.add_child(track)
	var thumb := TextureRect.new()
	thumb.name = "Thumb"
	thumb.texture = SCROLLBAR_THUMB_TEXTURE
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_SCALE
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.add_child(thumb)
	var chrome_data := {
		"scrollbar": scrollbar,
		"chrome": chrome,
		"track": track,
		"thumb": thumb,
	}
	_wood_scroll_chromes.append(chrome_data)
	scrollbar.value_changed.connect(_refresh_wood_scrollbars.unbind(1))
	chrome.gui_input.connect(_on_wood_scrollbar_gui_input.bind(chrome_data))
	return chrome


func _refresh_wood_scrollbars() -> void:
	for value: Variant in _wood_scroll_chromes:
		var chrome_data := value as Dictionary
		var scrollbar := chrome_data["scrollbar"] as VScrollBar
		var chrome := chrome_data["chrome"] as Control
		var track := chrome_data["track"] as TextureRect
		var thumb := chrome_data["thumb"] as TextureRect
		var scroll_owner := scrollbar.get_parent() as CanvasItem
		var can_scroll := (
			is_instance_valid(scrollbar)
			and scrollbar.max_value > scrollbar.page + 0.5
			and is_instance_valid(scroll_owner)
			and scroll_owner.is_visible_in_tree()
		)
		chrome.visible = can_scroll
		if not can_scroll:
			continue
		track.position = Vector2(7, 0)
		track.size = Vector2(24, chrome.size.y)
		var thumb_height := minf(72.0, chrome.size.y)
		thumb.size = Vector2(32, thumb_height)
		var travel := maxf(0.0, chrome.size.y - thumb_height)
		var scroll_range := maxf(1.0, scrollbar.max_value - scrollbar.page)
		var progress := clampf(scrollbar.value / scroll_range, 0.0, 1.0)
		thumb.position = Vector2(3, roundf(travel * progress))


func _queue_wood_scrollbar_refresh() -> void:
	if _wood_scroll_refresh_queued or not is_inside_tree():
		return
	_wood_scroll_refresh_queued = true
	get_tree().process_frame.connect(
		_on_wood_scrollbar_refresh_frame,
		CONNECT_ONE_SHOT,
	)


func _on_wood_scrollbar_refresh_frame() -> void:
	_wood_scroll_refresh_queued = false
	_refresh_wood_scrollbars()


func _on_wood_scrollbar_gui_input(
	event: InputEvent,
	chrome_data: Dictionary,
) -> void:
	var scrollbar := chrome_data["scrollbar"] as VScrollBar
	var chrome := chrome_data["chrome"] as Control
	var thumb := chrome_data["thumb"] as TextureRect
	if scrollbar == null or chrome == null or thumb == null:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			scrollbar.value -= maxf(48.0, scrollbar.page * 0.28)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			scrollbar.value += maxf(48.0, scrollbar.page * 0.28)
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_set_wood_scrollbar_from_y(scrollbar, chrome, thumb, mouse_event.position.y)
		else:
			return
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if not bool(motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			return
		_set_wood_scrollbar_from_y(scrollbar, chrome, thumb, motion.position.y)
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_set_wood_scrollbar_from_y(
			scrollbar,
			chrome,
			thumb,
			(event as InputEventScreenTouch).position.y,
		)
	elif event is InputEventScreenDrag:
		_set_wood_scrollbar_from_y(
			scrollbar,
			chrome,
			thumb,
			(event as InputEventScreenDrag).position.y,
		)
	else:
		return
	chrome.accept_event()


func _set_wood_scrollbar_from_y(
	scrollbar: VScrollBar,
	chrome: Control,
	thumb: TextureRect,
	local_y: float,
) -> void:
	var travel := maxf(1.0, chrome.size.y - thumb.size.y)
	var progress := clampf((local_y - thumb.size.y * 0.5) / travel, 0.0, 1.0)
	scrollbar.value = progress * maxf(0.0, scrollbar.max_value - scrollbar.page)


func _on_memory_input_text_changed() -> void:
	_queue_wood_scrollbar_refresh()


func _render() -> void:
	var resident := _render_data.get("resident", {}) as Dictionary
	_name_label.text = str(
		resident.get("displayName", "居民详情")
	)
	var occupation := str(resident.get("occupationLabel", ""))
	var place := str(resident.get("currentPlaceLabel", ""))
	_occupation_label.text = " · ".join(
		[occupation, place].filter(func(value: String) -> bool: return not value.is_empty())
	)
	if _occupation_label.text.is_empty():
		_occupation_label.text = "公开身份资料暂不可用"
	_apply_portrait(
		str(resident.get("portrait", "")),
		str(resident.get("portraitFrameMode", "auto")),
	)
	_apply_portrait_policy(str(resident.get("appearancePolicy", "normal")))

	var selected_tab := str(
		_render_data.get("selectedTab", "status")
	)
	if selected_tab not in TAB_IDS:
		selected_tab = "status"
	_apply_page_background(selected_tab)
	var tabs := _tabs_by_id()
	for tab_id: String in TAB_IDS:
		var tab_data := tabs.get(tab_id, {}) as Dictionary
		var availability := str(
			tab_data.get("availability", "disabled")
		)
		var action := UiViewModel.action(
			_view_model,
			str(ACTION_KEYS[tab_id])
		)
		var enabled := (
			availability in ["ready", "partial", "stale"]
			and UiViewModel.action_enabled(action)
		)
		var tab := _tab_buttons[tab_id] as ResidentDetailTabButton
		tab.configure({
			"tabId": tab_id,
			"label": str(tab_data.get("label", TAB_LABELS[tab_id])),
			"accessibleLabel": "居民详情：%s" % str(TAB_LABELS[tab_id]),
			"contentRect": Rect2(Vector2.ZERO, tab.size),
			"selected": tab_id == selected_tab,
			"disabled": not enabled,
			"reducedMotion": _reduced_motion_requested(),
			"fontSize": _tab_font_size(),
			"normalColor": Color("3f2818"),
			"selectedColor": Color("b94d2d"),
			"hoverColor": Color("8f3b23"),
			"pressedColor": Color("6c3d20"),
			"disabledColor": Color("806a5b"),
		})
		if not enabled:
			var disabled_reason := str(
				tab_data.get("disabledReason", "")
			)
			if disabled_reason.is_empty():
				disabled_reason = UiViewModel.disabled_reason(action)
			tab.tooltip_text = _player_copy_for_disabled(disabled_reason)
			tab.accessibility_name = "%s，已禁用：%s" % [
				str(TAB_LABELS[tab_id]),
				tab.tooltip_text,
			]
		else:
			tab.accessibility_name = "居民详情：%s" % str(
				TAB_LABELS[tab_id]
			)

	var close_action := UiViewModel.action(_view_model, "close")
	_close_button.configure({
		"accessibleLabel": "关闭居民详情",
		"disabled": not UiViewModel.action_enabled(close_action),
		"reducedMotion": _reduced_motion_requested(),
		"normalColor": Color.WHITE,
		"hoverColor": Color("fff0c2"),
		"pressedColor": Color("d6aa70"),
		"disabledColor": Color(0.72, 0.72, 0.72, 0.58),
	})
	var close_reason := UiViewModel.disabled_reason(close_action)
	if not UiViewModel.action_enabled(close_action):
		var close_copy := _player_copy_for_disabled(close_reason)
		_close_button.tooltip_text = close_copy
		_close_button.accessibility_name = "关闭居民详情，已禁用：%s" % close_copy

	var primary_key := _primary_action_key()
	var primary_action := UiViewModel.action(_view_model, primary_key)
	_action_button.configure({
		"label": "重试" if primary_key == "retry" else "刷新",
		"accessibleLabel": (
			"重新获取公开摘要"
			if primary_key == "retry"
			else "刷新公开摘要"
		),
		"fontSize": _action_font_size(),
		"disabled": not UiViewModel.action_enabled(primary_action),
		"reducedMotion": _reduced_motion_requested(),
		"surfaceVisible": true,
	})
	var primary_reason := UiViewModel.disabled_reason(primary_action)
	_action_button.tooltip_text = (
		_player_copy_for_disabled(primary_reason)
		if not primary_reason.is_empty()
		else _action_button.accessibility_name
	)
	if not primary_reason.is_empty():
		_action_button.accessibility_name = "%s，已禁用：%s" % [
			"重试" if primary_key == "retry" else "刷新",
			_action_button.tooltip_text,
		]
	_configure_section_chrome(selected_tab)
	_update_feedback_copy()
	_update_freshness_copy()
	_apply_responsive_layout()


func _configure_section_chrome(selected_tab: String) -> void:
	var is_section_page := (
		_layout_profile == LayoutProfile.WIDE
		and selected_tab in ["relationships", "memories"]
		and not _memory_operation_visible
	)
	_section_action_button.visible = is_section_page
	for button: Button in _section_filter_buttons:
		button.visible = is_section_page
	if _memory_operation_visible:
		_action_button.set_surface_visible(false)
		_action_button.set_label_font_size(24)
		_section_action_button.set_surface_visible(false)
		_section_action_button.set_label_font_size(24)
		_freshness_label.add_theme_font_size_override("font_size", 20)
		return
	if not is_section_page:
		_action_button.set_surface_visible(true)
		_action_button.set_label_font_size(_action_font_size())
		_freshness_label.add_theme_font_size_override("font_size", 32)
		return
	_action_button.set_surface_visible(false)
	_action_button.set_label_font_size(24)
	_freshness_label.add_theme_font_size_override("font_size", 20)
	var filter_copy: Array[String] = []
	var filter_ids: Array[String] = []
	var filter_action_keys: Array[String] = []
	var action_copy := ""
	if selected_tab == "relationships":
		filter_copy = ["全部", "亲近", "信任", "矛盾", "疏远", "与你有关"]
		filter_ids = ["all", "close", "trust", "conflict", "distant", "player"]
		filter_action_keys = [
			"filterRelationshipAll",
			"filterRelationshipClose",
			"filterRelationshipTrust",
			"filterRelationshipConflict",
			"filterRelationshipDistant",
			"filterRelationshipPlayer",
		]
		action_copy = "关系脉络"
	else:
		filter_copy = ["全部", "正在影响", "往事", "存疑", "异常", "我的介入"]
		filter_ids = ["all", "influencing", "past", "doubtful", "anomalous", "interventions"]
		filter_action_keys = [
			"filterAll",
			"filterInfluencing",
			"filterPast",
			"filterDoubtful",
			"filterAnomalous",
			"filterInterventions",
		]
		action_copy = "记忆操作"
	var content := _render_data.get("content", {}) as Dictionary
	var selected_filter_id := str(content.get("filterId", "all"))
	for index: int in mini(filter_copy.size(), _section_filter_buttons.size()):
		var filter_button := _section_filter_buttons[index]
		filter_button.text = filter_copy[index]
		var selected := (
			selected_tab in ["relationships", "memories"]
			and index < filter_ids.size()
			and filter_ids[index] == selected_filter_id
		)
		filter_button.add_theme_color_override(
			"font_color",
			Color("b94d2d") if selected else Color("3f2818")
		)
		filter_button.add_theme_color_override("font_hover_color", Color("b94d2d"))
		if index < filter_action_keys.size():
			var filter_action := UiViewModel.action(
				_view_model,
				filter_action_keys[index],
			)
			var filter_enabled := UiViewModel.action_enabled(filter_action)
			filter_button.disabled = not filter_enabled
			filter_button.focus_mode = (
				Control.FOCUS_ALL if filter_enabled else Control.FOCUS_NONE
			)
			filter_button.mouse_filter = Control.MOUSE_FILTER_STOP
			filter_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			filter_button.accessibility_name = "%s筛选：%s" % [
				"关系" if selected_tab == "relationships" else "记忆",
				filter_copy[index],
			]
			filter_button.tooltip_text = (
				_player_copy_for_disabled(UiViewModel.disabled_reason(filter_action))
				if not filter_enabled
				else ""
			)
		else:
			filter_button.disabled = true
			filter_button.focus_mode = Control.FOCUS_NONE
			filter_button.mouse_filter = Control.MOUSE_FILTER_STOP
			filter_button.mouse_default_cursor_shape = Control.CURSOR_ARROW
			filter_button.accessibility_name = filter_copy[index]
			filter_button.tooltip_text = "当前筛选不可用"
	for index: int in range(filter_copy.size(), _section_filter_buttons.size()):
		_section_filter_buttons[index].visible = false
	_section_action_button.configure({
		"label": action_copy,
		"accessibleLabel": action_copy,
		"fontSize": 24,
		"disabled": false,
		"reducedMotion": _reduced_motion_requested(),
		"surfaceVisible": false,
	})


func _apply_page_background(selected_tab: String) -> void:
	var mobile := MOBILE_UI_PROFILE.is_mobile_runtime()
	if _memory_operation_visible:
		_background.texture = (
			MOBILE_MEMORY_OPERATION_BACKGROUND_TEXTURE
			if mobile
			else MEMORY_OPERATION_BACKGROUND_TEXTURE
		)
		return
	match selected_tab:
		"relationships":
			_background.texture = (
				MOBILE_RELATIONSHIP_BACKGROUND_TEXTURE
				if mobile
				else RELATIONSHIP_BACKGROUND_TEXTURE
			)
		"memories":
			_background.texture = (
				MOBILE_MEMORY_BACKGROUND_TEXTURE
				if mobile
				else MEMORY_BACKGROUND_TEXTURE
			)
		_:
			_background.texture = (
				MOBILE_BACKGROUND_TEXTURE
				if mobile
				else BACKGROUND_TEXTURE
			)


func _open_memory_change_dialog(operation := "edit") -> void:
	if str(_render_data.get("selectedTab", "status")) != "memories":
		return
	var items := ((_render_data.get("content", {}) as Dictionary).get("items", []) as Array)
	if items.is_empty():
		_local_feedback = "请先选择一条记忆。"
		_present_local_feedback()
		return
	_sync_selected_memory_index(items)
	_memory_operation_visible = true
	_memory_operation_mode = operation if operation in ["edit", "delete"] else "edit"
	_apply_page_background("memories")
	_refresh_memory_operation_copy()
	_apply_responsive_layout()
	# `_apply_responsive_layout()` rebuilds the chain before the panel is made
	# visible. Rebuild once more after the visibility transition so the
	# operation controls are available to keyboard and controller navigation.
	_update_focus_chain()
	_memory_operation_edit_tab.grab_focus.call_deferred()


func _close_memory_operation_panel() -> void:
	if not _memory_operation_visible:
		return
	_memory_operation_visible = false
	_apply_page_background(str(_render_data.get("selectedTab", "memories")))
	_apply_responsive_layout()
	_update_focus_chain()


func _set_memory_operation_mode(operation: String) -> void:
	if operation not in ["edit", "delete"]:
		return
	_memory_operation_mode = operation
	_refresh_memory_operation_copy()


func _selected_memory_item() -> Dictionary:
	var content := _render_data.get("content", {}) as Dictionary
	var items := content.get("items", []) as Array
	if items.is_empty():
		return {}
	var index := clampi(_selected_content_index, 0, items.size() - 1)
	var indexed_item := items[index] as Dictionary
	if (
		_selected_memory_key.is_empty()
		or str(indexed_item.get("memoryId", "")) == _selected_memory_key
	):
		return indexed_item.duplicate(true)
	if not _selected_memory_key.is_empty():
		for item_value: Variant in items:
			if typeof(item_value) != TYPE_DICTIONARY:
				continue
			var item := item_value as Dictionary
			if str(item.get("memoryId", "")) == _selected_memory_key:
				return item.duplicate(true)
	return indexed_item.duplicate(true)


func _sync_selected_memory_index(items: Array) -> void:
	if items.is_empty():
		return
	if not _selected_memory_key.is_empty():
		if (
			_selected_content_index >= 0
			and _selected_content_index < items.size()
			and str((items[_selected_content_index] as Dictionary).get("memoryId", "")) == _selected_memory_key
		):
			return
		for index: int in items.size():
			var item := items[index] as Dictionary
			if str(item.get("memoryId", "")) == _selected_memory_key:
				_selected_content_index = index
				return
	_selected_content_index = clampi(_selected_content_index, 0, items.size() - 1)
	var selected_item := items[_selected_content_index] as Dictionary
	_selected_memory_key = str(selected_item.get("memoryId", ""))


func _refresh_memory_operation_copy() -> void:
	var item := _selected_memory_item()
	var kind_label := str(item.get("kindLabel", "记忆"))
	var title := str(item.get("title", "未命名记忆"))
	var summary := str(item.get("summary", ""))
	var related_labels: Array[String] = []
	for value: Variant in item.get("relatedResidents", []) as Array:
		if value is Dictionary:
			var label := str((value as Dictionary).get("label", ""))
			if not label.is_empty():
				related_labels.append(label)
	_memory_operation_selected_body.clear()
	_memory_operation_selected_body.add_text("类型：")
	_memory_operation_selected_body.push_color(Color("b94d2d"))
	_memory_operation_selected_body.add_text(kind_label)
	_memory_operation_selected_body.pop()
	_memory_operation_selected_body.add_text("\n\n")
	_memory_operation_selected_body.push_color(Color("b94d2d"))
	_memory_operation_selected_body.add_text("【%s】" % kind_label)
	_memory_operation_selected_body.pop()
	_memory_operation_selected_body.add_text(" %s\n%s\n\n" % [title, summary])
	_memory_operation_selected_body.add_text(
		"时间：%s\n来源：%s\n相关人物：%s\n与你有关：" % [
			str(item.get("timeLabel", "未注明")),
			_memory_source_label(item),
			"、".join(related_labels) if not related_labels.is_empty() else "无",
		]
	)
	_memory_operation_selected_body.push_color(Color("b94d2d"))
	_memory_operation_selected_body.add_text(
		"是" if bool(item.get("playerInvolved", false)) else "否"
	)
	_memory_operation_selected_body.pop()
	_memory_operation_selected_body.scroll_to_line(0)
	var deleting := _memory_operation_mode == "delete"
	_memory_operation_input_heading.text = (
		"删除后，这段记忆不会再影响居民："
		if deleting
		else "请输入改写后的内容："
	)
	_memory_operation_input.editable = not deleting
	# 批准参考中的编辑框初始为空，原记忆只在左栏展示。
	_memory_operation_input.text = ""
	_memory_operation_hint.text = (
		"删除会保留一次你的介入记录，居民之后仍可能因证据重新想起。"
		if deleting
		else "系统会根据居民之后重新遇到当事人、看到证据或听到其他说法，自行判断更加确信、开始怀疑、修正或发现被篡改。"
	)
	_memory_operation_confirm.configure({
		"label": "确认删除" if deleting else "确认修改",
		"accessibleLabel": "确认删除记忆" if deleting else "确认修改记忆",
		"fontSize": 25,
		"disabled": false,
		"surfaceVisible": false,
	})
	_apply_memory_operation_tab_style(_memory_operation_edit_tab, not deleting)
	_apply_memory_operation_tab_style(_memory_operation_delete_tab, deleting)


func _apply_memory_operation_tab_style(button: Button, selected: bool) -> void:
	var text_color := Color("b94d2d") if selected else Color("3f2818")
	var empty := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, empty)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("font_hover_pressed_color", text_color)


func _confirm_memory_operation() -> void:
	var item := _selected_memory_item()
	if item.is_empty():
		return
	var action_key := "deleteMemory" if _memory_operation_mode == "delete" else "editMemory"
	var player_text := _memory_operation_input.text.strip_edges()
	if action_key == "editMemory" and player_text.is_empty():
		_memory_operation_hint.text = "改写内容不能为空。"
		_memory_operation_input.grab_focus()
		return
	if _request_action(action_key, {
		"memoryKey": str(item.get("memoryId", "")),
		"playerText": player_text,
	}):
		_close_memory_operation_panel()


func _apply_memory_operation_visibility() -> void:
	_memory_operation_root.visible = _memory_operation_visible
	_banner_label.visible = not _memory_operation_visible
	_content_scroll.visible = not _memory_operation_visible
	_meter_overlay_root.visible = false if _memory_operation_visible else _meter_overlay_root.visible
	_freshness_label.visible = true
	_action_button.visible = true
	_section_action_button.visible = (
		_memory_operation_visible or _section_action_button.visible
	)
	for button: Button in _section_filter_buttons:
		button.visible = button.visible and not _memory_operation_visible


func _layout_memory_operation_panel() -> void:
	if not is_instance_valid(_memory_operation_root):
		return
	_memory_operation_root.position = Vector2.ZERO
	_memory_operation_root.size = size
	var sx := _wide_layout_scale.x
	var sy := _wide_layout_scale.y
	var controls := {
		"title": _memory_operation_title,
		"selectedHeading": _memory_operation_selected_heading,
		"selectedBody": _memory_operation_selected_body,
		"operationHeading": _memory_operation_heading,
		"editTab": _memory_operation_edit_tab,
		"deleteTab": _memory_operation_delete_tab,
		"inputHeading": _memory_operation_input_heading,
		"input": _memory_operation_input,
		"hint": _memory_operation_hint,
		"cancel": _memory_operation_cancel,
		"confirm": _memory_operation_confirm,
	}
	for key: String in controls:
		var control := controls[key] as Control
		var rect := _map_rect(WIDE_MEMORY_OPERATION_RECTS[key] as Rect2, sx, sy)
		control.position = rect.position
		control.size = rect.size
	for label_data: Array in [
		[_memory_operation_title, 1],
		[_memory_operation_selected_heading, 1],
		[_memory_operation_heading, 1],
		[_memory_operation_input_heading, 1],
		[_memory_operation_hint, 3],
	]:
		var label := label_data[0] as Label
		_fit_label_lines_to_rect(
			label,
			int(label_data[1]),
			label.size.y,
			label.text,
		)
	var selected_scroll_rect := _map_rect(
		WIDE_MEMORY_OPERATION_SCROLL_RECTS["selected"] as Rect2,
		sx,
		sy,
	)
	_selected_memory_scroll_chrome.position = selected_scroll_rect.position
	_selected_memory_scroll_chrome.size = selected_scroll_rect.size
	var input_scroll_rect := _map_rect(
		WIDE_MEMORY_OPERATION_SCROLL_RECTS["input"] as Rect2,
		sx,
		sy,
	)
	_memory_input_scroll_chrome.position = input_scroll_rect.position
	_memory_input_scroll_chrome.size = input_scroll_rect.size
	_queue_wood_scrollbar_refresh()


func _render_content() -> void:
	_clear_content()
	var selected_tab := str(
		_render_data.get("selectedTab", "status")
	)
	_banner_label.max_lines_visible = 1 if selected_tab == "status" else 2
	_banner_label.autowrap_mode = (
		TextServer.AUTOWRAP_OFF
		if selected_tab == "status"
		else TextServer.AUTOWRAP_WORD_SMART
	)
	if selected_tab != "status":
		_close_status_detail_popup()
	var content := _render_data.get("content", {}) as Dictionary
	if content.is_empty():
		_banner_label.text = _contract_unavailable_message()
		_apply_banner_feedback()
		var empty := _make_label(
			"UnavailableContent",
			_content_font_size(),
			Color("6c3d20"),
			HORIZONTAL_ALIGNMENT_CENTER,
			3
		)
		empty.text = (
			"居民公开详情暂不可用。\n"
			+ "可查看的居民资料尚未准备好。"
		)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var empty_rect := _empty_content_local_rect()
		empty.position = empty_rect.position
		empty.size = empty_rect.size
		_content_root.add_child(empty)
		_update_focus_chain()
		return
	match selected_tab:
		"relationships":
			_render_relationships(content)
		"memories":
			_render_memories(content)
		_:
			_render_status(content)
	_apply_banner_feedback()
	_update_focus_chain()


func _render_status(content: Dictionary) -> void:
	var rows := content.get("statusRows", []) as Array
	var meters := content.get("lifeMeters", []) as Array
	_ensure_content_row_capacity(rows.size())
	_prepare_content_extent(rows.size())
	if _selected_content_index < 0 or _selected_content_index >= rows.size():
		_selected_content_index = _preferred_status_row_index(content, rows)
	for index: int in mini(rows.size(), _row_rects.size()):
		var row := rows[index] as Dictionary
		var row_root := _new_row_control(index, _row_rects[index])
		var slots := _status_slots(_row_rects[index])
		_add_row_label(
			row_root,
			"StatusLabel",
			str(row.get("label", "")),
			slots["label"],
			Color("b94d2d"),
			HORIZONTAL_ALIGNMENT_CENTER,
			1
		)
		_add_row_label(
			row_root,
			"ShortText",
			_status_row_short_text(row),
			slots["summary"],
			Color("3f2818"),
			HORIZONTAL_ALIGNMENT_LEFT,
			1 if _layout_profile == LayoutProfile.COMPACT_LANDSCAPE else 2
		)
		if index == _selected_content_index:
			_add_selected_marker(row_root)
	_render_life_meter_overlay(meters)
	var selected := (
		rows[_selected_content_index] as Dictionary
		if _selected_content_index >= 0 and _selected_content_index < rows.size()
		else {}
	)
	_banner_label.text = "%s · %s" % [
		str(selected.get("label", "当前详情")),
		str(selected.get("shortText", "")),
	]


func _status_row_short_text(row: Dictionary) -> String:
	var copy := String(row.get("shortText", ""))
	var count_start := copy.find("（共")
	if count_start < 0:
		return copy
	var count_copy := copy.substr(count_start + 1).trim_suffix("）")
	return "%s，点击查看" % count_copy


func _render_life_meter_overlay(meters: Array) -> void:
	_meter_overlay_root.visible = not meters.is_empty()
	for index: int in mini(5, mini(meters.size(), _row_rects.size())):
		var meter := meters[index] as Dictionary
		if meter.is_empty() or not bool(meter.get("available", true)):
			continue
		var row_rect := _row_rects[index]
		var slots := _status_slots(row_rect)
		var meter_row := Control.new()
		meter_row.name = "LifeMeterRow_%d" % index
		meter_row.position = row_rect.position
		meter_row.size = row_rect.size
		meter_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_meter_overlay_root.add_child(meter_row)
		_add_meter_overlay_label(
			meter_row,
			"MeterLabel",
			str(meter.get("label", "")),
			slots["meterLabel"],
			row_rect,
		)
		_add_meter_overlay_label(
			meter_row,
			"MeterValue",
			str(meter.get("shortLevelLabel", meter.get("levelLabel", ""))),
			slots["meterValue"],
			row_rect,
		)
		var track := METER_SCENE.instantiate() as ResidentDetailMeterTrack
		track.name = "MeterTrack"
		var track_rect := slots["track"] as Rect2
		track.position = track_rect.position - row_rect.position
		track.size = track_rect.size
		meter_row.add_child(track)
		if not track.configure(
			str(meter.get("tone", "normal")),
			int(meter.get("segmentsFilled", 0)),
			int(meter.get("segmentCount", 5)),
		):
			track.visible = false


func _add_meter_overlay_label(
	row: Control,
	node_name: String,
	copy: String,
	global_rect: Rect2,
	row_rect: Rect2,
) -> void:
	var label := _make_label(
		node_name,
		_content_font_size(),
		Color("3f2818"),
		HORIZONTAL_ALIGNMENT_LEFT,
		1,
	)
	label.text = copy
	label.position = global_rect.position - row_rect.position
	label.size = global_rect.size
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)


func _preferred_status_row_index(
	content: Dictionary,
	rows: Array,
) -> int:
	if rows.is_empty():
		return -1
	var preferred_id := String(
		content.get("preferredStatusRowId", "doing"),
	)
	for index: int in rows.size():
		if String((rows[index] as Dictionary).get("id", "")) == preferred_id:
			return index
	return mini(3, rows.size() - 1)


func _ensure_content_row_capacity(row_count: int) -> void:
	if row_count <= _row_rects.size() or _row_rects.is_empty():
		return
	var row_height := _row_rects[0].size.y
	while _row_rects.size() < row_count:
		var previous := _row_rects[-1]
		_row_rects.append(Rect2(
			Vector2(previous.position.x, previous.end.y),
			Vector2(previous.size.x, row_height),
		))


func _render_relationships(content: Dictionary) -> void:
	var items := content.get("items", []) as Array
	if items.is_empty():
		var availability := str(content.get("availability", "disabled"))
		if availability != "ready":
			_banner_label.text = _unavailable_section_copy(
				"关系",
				availability
			)
			return
		_banner_label.text = "关系 · 这名居民与他人的真实联系"
		return
	if _selected_content_index < 0 or _selected_content_index >= items.size():
		_selected_content_index = 0
	_prepare_content_extent(items.size())
	if items.size() == 1 and bool(
		(items[0] as Dictionary).get("summaryOnly", false)
	):
		var summary_item := items[0] as Dictionary
		_render_public_summary(
			"关系概览",
			str(summary_item.get("relationshipLabel", "公开摘要")),
			str(summary_item.get("summary", "")),
			str(summary_item.get("updatedLabel", ""))
		)
		_banner_label.text = "关系 · 这名居民与他人的真实联系"
		return
	for index: int in items.size():
		var item := items[index] as Dictionary
		var row_rect := _content_row_rect(index)
		var row_root := _new_row_control(index, row_rect)
		_add_relationship_portrait(row_root, item)
		_add_local_row_label(
			row_root,
			"RelationName",
			str(item.get("displayName", "")),
			Rect2(145, 6, 180, 34),
			23,
			Color("3f2818"),
			HORIZONTAL_ALIGNMENT_LEFT,
			1,
		)
		_add_local_row_label(
			row_root,
			"RelationIdentity",
			"身份：%s" % str(item.get("identityLabel", "居民")),
			Rect2(145, 40, 180, 54),
			18,
			Color("3f2818"),
			HORIZONTAL_ALIGNMENT_LEFT,
			2,
		)
		var familiarity := item.get("familiarity", {}) as Dictionary
		var tension := item.get("tension", {}) as Dictionary
		_add_local_row_label(
			row_root,
			"RelationMeters",
			"关系称呼：%s\n亲近：%s\n相处：%s" % [
				str(item.get("relationshipLabel", "关系")),
				str(familiarity.get("label", "尚不了解")),
				str(tension.get("label", "没有明显矛盾")),
			],
			Rect2(340, 5, 225, 98),
			17,
			Color("3f2818"),
			HORIZONTAL_ALIGNMENT_LEFT,
			3,
		)
		var recent_copy := str(item.get("recentInteractionSummary", ""))
		if recent_copy.is_empty():
			recent_copy = str(item.get("summary", ""))
		var updated_copy := str(item.get("updatedLabel", ""))
		_add_local_row_label(
			row_root,
			"RelationRecentInteraction",
			"最近一次关键互动：\n%s%s" % [
				recent_copy,
				"\n%s" % updated_copy if not updated_copy.is_empty() else "",
			],
			Rect2(590, 5, 500, 96),
			20,
			Color("3f2818"),
			HORIZONTAL_ALIGNMENT_LEFT,
			4,
		)
		row_root.tooltip_text = "%s · %s\n%s" % [
			str(item.get("displayName", "")),
			str(item.get("relationshipLabel", "关系")),
			recent_copy,
		]
	_banner_label.text = "关系 · 这名居民与他人的真实联系"


func _render_memories(content: Dictionary) -> void:
	var items := content.get("items", []) as Array
	if items.is_empty():
		var availability := str(content.get("availability", "disabled"))
		if availability != "ready":
			_banner_label.text = _unavailable_section_copy(
				"记忆",
				availability
			)
			return
		_banner_label.text = "记忆 · 仍在影响这名居民的经历"
		return
	_sync_selected_memory_index(items)
	_prepare_content_extent(items.size())
	if items.size() == 1 and str(
		(items[0] as Dictionary).get("kindId", "")
	) == "public_summary":
		var summary_item := items[0] as Dictionary
		_render_public_summary(
			str(summary_item.get("title", "近期记忆")),
			str(summary_item.get("kindLabel", "公开摘要")),
			str(summary_item.get("summary", "")),
			str(summary_item.get("timeLabel", "")),
			summary_item.get("influence", {}) as Dictionary
		)
		_banner_label.text = "记忆 · 仍在影响这名居民的经历"
		return
	for index: int in items.size():
		var item := items[index] as Dictionary
		var row_rect := _content_row_rect(index)
		var row_root := _new_row_control(index, row_rect)
		if index == _selected_content_index:
			_add_selected_marker(row_root)
		var kind_label := str(item.get("kindLabel", "记忆"))
		_add_local_row_label(
			row_root,
			"MemoryKind",
			"【%s】" % kind_label,
			Rect2(18, 4, 140, 32),
			20,
			Color("b94d2d"),
			HORIZONTAL_ALIGNMENT_LEFT,
			1,
		)
		_add_local_row_label(
			row_root,
			"MemoryTitle",
			str(item.get("title", "")),
			Rect2(156, 4, 430, 32),
			21,
			Color("3f2818"),
			HORIZONTAL_ALIGNMENT_LEFT,
			1,
		)
		_add_local_row_label(
			row_root,
			"MemorySummary",
			str(item.get("summary", "")),
			Rect2(18, 38, 600, 122),
			20,
			Color("3f2818"),
			HORIZONTAL_ALIGNMENT_LEFT,
			5,
		)
		var related_labels: Array[String] = []
		for resident_value: Variant in item.get("relatedResidents", []) as Array:
			if resident_value is Dictionary:
				var related_label := str((resident_value as Dictionary).get("label", ""))
				if not related_label.is_empty():
					related_labels.append(related_label)
		if bool(item.get("playerInvolved", false)):
			related_labels.push_front("玩家")
		var related_copy := "、".join(related_labels) if not related_labels.is_empty() else "无"
		_add_local_row_label(
			row_root,
			"MemoryMeta",
			"时间：%s\n来源：%s\n相关人物：%s\n与你有关：%s" % [
				str(item.get("timeLabel", "未注明")),
				_memory_source_label(item),
				related_copy,
				"是" if bool(item.get("playerInvolved", false)) else "否",
			],
			Rect2(690, 8, 380, 150),
			18,
			Color("3f2818"),
			HORIZONTAL_ALIGNMENT_LEFT,
			5,
		)
		row_root.tooltip_text = "【%s】%s\n%s\n时间：%s\n相关人物：%s" % [
			kind_label,
			str(item.get("title", "")),
			str(item.get("summary", "")),
			str(item.get("timeLabel", "未注明")),
			related_copy,
		]
	_banner_label.text = "记忆 · 仍在影响这名居民的经历"


func _memory_source_label(item: Dictionary) -> String:
	var explicit := str(item.get("sourceLabel", ""))
	if not explicit.is_empty():
		return explicit
	if bool(item.get("playerInvolved", false)):
		return "和你有关"
	for value: Variant in item.get("relatedResidents", []) as Array:
		if value is Dictionary:
			var label := str((value as Dictionary).get("label", ""))
			if not label.is_empty():
				return label
	return "她自己"


func _render_public_summary(
	title: String,
	kind_label: String,
	summary: String,
	updated_label: String,
	progress: Dictionary = {},
) -> void:
	var body_rect := _summary_body_rect()
	var row := Control.new()
	row.name = "ContentRow_0"
	row.position = body_rect.position
	row.size = body_rect.size
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.focus_mode = Control.FOCUS_ALL
	row.tooltip_text = summary
	row.gui_input.connect(_on_row_gui_input.bind(0))
	_content_root.add_child(row)
	_row_controls.append(row)
	if _selected_content_index == 0:
		_add_selected_marker(row)

	var kind := _make_label(
		"SummaryKind",
		maxi(22, _content_font_size() - 4),
		Color("b94d2d"),
		HORIZONTAL_ALIGNMENT_LEFT,
		1
	)
	kind.text = kind_label
	kind.position = Vector2(12.0, 18.0)
	kind.size = Vector2(row.size.x - 24.0, 44.0)
	row.add_child(kind)

	var heading := _make_label(
		"SummaryTitle",
		_content_font_size() + 4,
		Color("3f2818"),
		HORIZONTAL_ALIGNMENT_LEFT,
		2
	)
	heading.text = title
	heading.position = Vector2(12.0, 66.0)
	heading.size = Vector2(row.size.x - 24.0, 72.0)
	row.add_child(heading)

	var summary_label := _make_label(
		"SummaryBody",
		_content_font_size(),
		Color("3f2818"),
		HORIZONTAL_ALIGNMENT_LEFT,
		6
	)
	summary_label.text = summary
	summary_label.tooltip_text = summary
	summary_label.position = Vector2(12.0, 150.0)
	summary_label.size = Vector2(
		row.size.x - 24.0,
		maxf(88.0, row.size.y - 222.0)
	)
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(summary_label)

	if bool(progress.get("available", false)):
		summary_label.size.y = maxf(88.0, row.size.y - 260.0)
		var progress_caption := _make_label(
			"SummaryProgressLabel",
			maxi(24, _content_font_size() - 4),
			Color("6c3d20"),
			HORIZONTAL_ALIGNMENT_LEFT,
			1
		)
		progress_caption.text = "影响程度 · %s" % str(
			progress.get("label", "尚未形成")
		)
		progress_caption.position = Vector2(
			12.0,
			maxf(0.0, row.size.y - 98.0)
		)
		progress_caption.size = Vector2(
			minf(420.0, row.size.x * 0.46),
			28.0
		)
		row.add_child(progress_caption)
		_add_evidence_progress_track(
			row,
			Rect2(
				Vector2(
					12.0,
					maxf(0.0, row.size.y - 68.0)
				),
				Vector2(
					minf(420.0, row.size.x * 0.46),
					60.0
				)
			),
			progress,
			"影响程度",
			true
		)

	if not updated_label.is_empty():
		var updated := _make_label(
			"SummaryUpdated",
			maxi(24, _content_font_size() - 4),
			Color("806a5b"),
			HORIZONTAL_ALIGNMENT_RIGHT,
			1
		)
		updated.text = updated_label
		updated.position = Vector2(
			12.0,
			maxf(0.0, row.size.y - 54.0)
		)
		updated.size = Vector2(row.size.x - 24.0, 42.0)
		row.add_child(updated)


func _add_evidence_progress_track(
	parent: Control,
	global_rect: Rect2,
	progress: Dictionary,
	progress_name: String,
	rect_is_local: bool = false,
) -> void:
	if not bool(progress.get("available", true)):
		return
	var segment_count := int(progress.get("segmentCount", 5))
	var level := clampi(
		int(
			progress.get(
				"level",
				progress.get("segmentsFilled", 0),
			)
		),
		0,
		segment_count
	)
	var track := METER_SCENE.instantiate() as ResidentDetailMeterTrack
	track.name = "%sProgressTrack" % progress_name
	track.position = (
		global_rect.position
		if rect_is_local
		else global_rect.position - parent.global_position
	)
	track.size = global_rect.size
	track.tooltip_text = "%s · %s · %d/%d" % [
		progress_name,
		str(progress.get("label", "尚未形成")),
		level,
		segment_count,
	]
	track.set_meta("progressName", progress_name)
	track.set_meta("level", level)
	track.set_meta("segmentCount", segment_count)
	parent.add_child(track)
	var configured := track.configure(
		"normal",
		level,
		segment_count
	)
	if configured:
		return
	track.queue_free()
	_add_row_label(
		parent,
		"%sProgressUnavailable" % progress_name,
		"%s · %s" % [
			progress_name,
			str(progress.get("label", "暂不可用")),
		],
		global_rect,
		Color("806a5b"),
		HORIZONTAL_ALIGNMENT_CENTER,
		1
	)


func _add_summary_parchment() -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = BACKGROUND_TEXTURE
	var texture_size := BACKGROUND_TEXTURE.get_size()
	atlas.region = Rect2(
		Vector2(texture_size.x * 0.40, texture_size.y * 0.84),
		Vector2(texture_size.x * 0.36, texture_size.y * 0.035)
	)
	var parchment := TextureRect.new()
	parchment.name = "SummaryParchment"
	parchment.texture = atlas
	parchment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	parchment.stretch_mode = TextureRect.STRETCH_SCALE
	parchment.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parchment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parchment.position = Vector2.ZERO
	parchment.size = _content_root.size
	_content_root.add_child(parchment)
	_content_root.move_child(parchment, 0)


func _summary_body_rect() -> Rect2:
	var horizontal_padding := (
		110.0
		if _layout_profile == LayoutProfile.WIDE
		else 28.0
	)
	var vertical_padding := (
		24.0
		if _layout_profile == LayoutProfile.COMPACT_LANDSCAPE
		else 42.0
	)
	return Rect2(
		Vector2(horizontal_padding, vertical_padding),
		Vector2(
			maxf(1.0, _content_rect.size.x - horizontal_padding * 2.0),
			maxf(1.0, _content_rect.size.y - vertical_padding * 2.0)
		)
	)


func _new_row_control(index: int, row_rect: Rect2) -> Control:
	var selected_tab := str(_render_data.get("selectedTab", "status"))
	var row: Control = Panel.new() if selected_tab == "status" else Control.new()
	row.name = "ContentRow_%d" % index
	row.position = row_rect.position - _content_rect.position
	row.size = row_rect.size
	row.set_meta("selected", index == _selected_content_index)
	if selected_tab in ["relationships", "memories"]:
		var surface := TextureRect.new()
		surface.name = "RowImageSurface"
		surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		surface.texture = (
			RELATIONSHIP_ROW_TEXTURE
			if selected_tab == "relationships"
			else MEMORY_ROW_TEXTURE
		)
		surface.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		surface.stretch_mode = TextureRect.STRETCH_SCALE
		surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(surface)
	else:
		var status_surface := StyleBoxFlat.new()
		status_surface.bg_color = Color(0.98, 0.86, 0.64, 0.10)
		status_surface.border_color = (
			SELECTED_GREEN if index == _selected_content_index else Color("8f6a43")
		)
		status_surface.set_border_width_all(2)
		(row as Panel).add_theme_stylebox_override("panel", status_surface)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.focus_mode = Control.FOCUS_ALL
	row.tooltip_text = "查看完整公开摘要"
	row.gui_input.connect(_on_row_gui_input.bind(index))
	_content_root.add_child(row)
	_row_controls.append(row)
	return row


func _content_row_rect(index: int) -> Rect2:
	if _row_rects.is_empty():
		return Rect2()
	if index < _row_rects.size():
		return _row_rects[index]
	var last := _row_rects[-1]
	var step_y := last.size.y
	if _row_rects.size() > 1:
		step_y = last.position.y - _row_rects[-2].position.y
	return Rect2(
		Vector2(last.position.x, last.position.y + step_y * float(index - _row_rects.size() + 1)),
		last.size,
	)


func _prepare_content_extent(row_count: int) -> void:
	var content_height := _content_rect.size.y
	if row_count > 0 and not _row_rects.is_empty():
		var last_rect := _content_row_rect(row_count - 1)
		content_height = maxf(
			content_height,
			last_rect.end.y - _content_rect.position.y,
		)
	_content_root.custom_minimum_size = Vector2(_content_rect.size.x, content_height)
	_content_root.size = _content_root.custom_minimum_size
	_queue_wood_scrollbar_refresh()


func _add_selected_marker(row: Control) -> void:
	var marker := ColorRect.new()
	marker.name = "SelectedMarker"
	marker.position = Vector2(0, roundf((row.size.y - 48.0) * 0.5))
	marker.size = Vector2(7, 48)
	marker.color = SELECTED_GREEN
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(marker)


func _add_row_label(
	row: Control,
	node_name: String,
	copy: String,
	global_rect: Rect2,
	color: Color,
	alignment: HorizontalAlignment,
	max_lines: int
) -> void:
	var label := _make_label(
		node_name,
		_content_font_size(),
		color,
		alignment,
		max_lines
	)
	label.text = copy
	label.position = global_rect.position - row.global_position
	label.size = global_rect.size
	label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
		if max_lines > 1
		else TextServer.AUTOWRAP_OFF
	)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	_fit_label_lines_to_rect(label, max_lines, global_rect.size.y, copy)


func _add_local_row_label(
	row: Control,
	node_name: String,
	copy: String,
	local_rect: Rect2,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment,
	max_lines: int,
) -> void:
	var label := _make_label(
		node_name,
		font_size,
		color,
		alignment,
		max_lines,
	)
	label.text = copy
	label.position = local_rect.position
	label.size = local_rect.size
	label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
		if max_lines > 1
		else TextServer.AUTOWRAP_OFF
	)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	_fit_label_lines_to_rect(label, max_lines, local_rect.size.y, copy)


func _fit_label_lines_to_rect(
	label: Label,
	requested_lines: int,
	available_height: float,
	full_copy: String,
) -> void:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var line_spacing := maxi(0, label.get_theme_constant("line_spacing"))
	var line_height := (
		font.get_height(font_size) + float(line_spacing)
		if font != null
		else float(font_size + line_spacing)
	)
	var safe_line_capacity := maxi(
		1,
		int(floor(available_height / maxf(1.0, line_height))),
	)
	label.max_lines_visible = mini(requested_lines, safe_line_capacity)
	label.set_meta("full_copy", full_copy)
	label.set_meta("safe_line_capacity", safe_line_capacity)


func _add_relationship_portrait(row: Control, item: Dictionary) -> void:
	var resource_path := _relationship_portrait_path(item)
	if resource_path.is_empty() or not ResourceLoader.exists(resource_path):
		return
	var texture := ResourceLoader.load(resource_path, "Texture2D") as Texture2D
	if texture == null:
		return
	var portrait_slot := Control.new()
	portrait_slot.name = "RelationshipPortraitSlot"
	portrait_slot.position = Vector2(30, 9)
	portrait_slot.size = Vector2(80, 80)
	portrait_slot.clip_contents = true
	portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait_slot)
	var portrait := TextureRect.new()
	portrait.name = "RelationshipPortrait"
	if texture.get_size().x >= 400 and texture.get_size().y >= 320:
		var portrait_crop := AtlasTexture.new()
		portrait_crop.atlas = texture
		portrait_crop.region = Rect2(112, 32, 288, 288)
		portrait.texture = portrait_crop
	else:
		portrait.texture = texture
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_slot.add_child(portrait)


func _relationship_portrait_path(item: Dictionary) -> String:
	var projected_path := str(item.get("portraitRef", "")).strip_edges()
	if (
		not projected_path.is_empty()
		and ResourceLoader.exists(projected_path, "Texture2D")
	):
		return projected_path
	var resident_id := str(item.get("residentId", ""))
	if resident_id.is_empty():
		return ""
	var parts := resident_id.split("_")
	if not parts.is_empty() and parts[0] == "resident":
		parts.remove_at(0)
	if not parts.is_empty() and parts[-1].is_valid_int():
		parts.remove_at(parts.size() - 1)
	if parts.is_empty():
		return ""
	return (
		"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
		+ "classic_sets/runtime_portraits/%s_front.png" % "_".join(parts)
	)


func _make_label(
	node_name: String,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment,
	max_lines: int
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.max_lines_visible = max_lines
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if max_lines > 1:
		label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_to_group("resident_detail_text_slot")
	label.set_meta("gate_id", node_name)
	return label


func _clear_content() -> void:
	_row_controls.clear()
	UiNodeRetirement.retire_children(_content_root)
	if is_instance_valid(_meter_overlay_root):
		UiNodeRetirement.retire_children(_meter_overlay_root)
		_meter_overlay_root.visible = false
	_prepare_content_extent(0)


func _apply_portrait(resource_path: String, frame_mode := "auto") -> void:
	_resident_sprite.texture = null
	if resource_path.is_empty() or not resource_path.begins_with("res://"):
		_resident_sprite.visible = false
		return
	var texture := ResourceLoader.load(resource_path, "Texture2D") as Texture2D
	if texture == null:
		_resident_sprite.visible = false
		return
	if (
		frame_mode != "full_texture"
		and texture.get_size().x >= 64
		and texture.get_size().y >= 80
	):
		var frame := AtlasTexture.new()
		frame.atlas = texture
		frame.region = Rect2(0, 0, 64, 80)
		_resident_sprite.texture = frame
	else:
		_resident_sprite.texture = texture
	_resident_sprite.visible = true


func _apply_portrait_policy(policy: String) -> void:
	if policy != "grayscale":
		_resident_sprite.material = null
		return
	var material := ShaderMaterial.new()
	material.shader = RESIDENT_GRAYSCALE_SHADER
	material.set_shader_parameter("grayscale_strength", 1.0)
	_resident_sprite.material = material


func _update_feedback_copy() -> void:
	var data_status := str(_view_model.get("status", "disabled"))
	var operation_status := str(
		UiViewModel.operation_status(_view_model)
	)
	var error_message := UiViewModel.error_message(_view_model)
	var copy := _local_feedback
	if copy.is_empty() and operation_status in ["rejected", "error", "disabled"]:
		copy = error_message
	if copy.is_empty():
		copy = str(OPERATION_FEEDBACK.get(operation_status, ""))
	if copy.is_empty() and data_status != "ready":
		copy = error_message
	if copy.is_empty():
		copy = str(STATUS_FEEDBACK.get(data_status, ""))
	_feedback_label.text = copy
	_feedback_label.visible = false


func _apply_banner_feedback() -> void:
	var detail_copy := _banner_label.text.strip_edges()
	var feedback_copy := _feedback_label.text.strip_edges()
	if feedback_copy.is_empty():
		_banner_label.tooltip_text = detail_copy
		return
	if detail_copy.is_empty() or detail_copy == feedback_copy:
		_banner_label.text = feedback_copy
		_banner_label.tooltip_text = feedback_copy
		return
	_banner_label.text = "%s\n%s" % [feedback_copy, detail_copy]
	_banner_label.tooltip_text = "%s\n%s" % [feedback_copy, detail_copy]


func _build_status_detail_popup() -> void:
	_status_detail_backdrop = Control.new()
	_status_detail_backdrop.name = "StatusDetailBackdrop"
	_status_detail_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_detail_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_status_detail_backdrop.z_index = 900
	_status_detail_backdrop.visible = false
	_status_detail_backdrop.gui_input.connect(
		_on_status_detail_backdrop_input,
	)
	add_child(_status_detail_backdrop)

	_status_detail_panel = NinePatchRect.new()
	_status_detail_panel.name = "StatusDetailPopup"
	_status_detail_panel.texture = STATUS_DETAIL_PANEL_TEXTURE
	_status_detail_panel.patch_margin_left = 96
	_status_detail_panel.patch_margin_top = 72
	_status_detail_panel.patch_margin_right = 96
	_status_detail_panel.patch_margin_bottom = 72
	_status_detail_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_status_detail_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_status_detail_panel.gui_input.connect(_on_status_detail_panel_input)
	_status_detail_backdrop.add_child(_status_detail_panel)

	_status_detail_title = _make_label(
		"StatusDetailTitle",
		32,
		Color("6c3d20"),
		HORIZONTAL_ALIGNMENT_LEFT,
		1,
	)
	_status_detail_panel.add_child(_status_detail_title)

	_status_detail_text = RichTextLabel.new()
	_status_detail_text.name = "StatusDetailText"
	_status_detail_text.bbcode_enabled = false
	_status_detail_text.fit_content = false
	_status_detail_text.scroll_active = true
	_status_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_detail_text.mouse_filter = Control.MOUSE_FILTER_STOP
	_status_detail_text.add_theme_font_override(
		"normal_font",
		PAGE_THEME.default_font,
	)
	_status_detail_text.add_theme_font_size_override("normal_font_size", 26)
	_status_detail_text.add_theme_color_override("default_color", Color("3f2818"))
	_status_detail_panel.add_child(_status_detail_text)


func _open_status_detail_popup(row_index: int) -> void:
	var content := _render_data.get("content", {}) as Dictionary
	var rows := content.get("statusRows", []) as Array
	if row_index < 0 or row_index >= rows.size():
		return
	var row := rows[row_index] as Dictionary
	var full_text := String(
		row.get("text", row.get("shortText", "")),
	).strip_edges()
	if full_text.is_empty():
		return
	_status_detail_row_index = row_index
	_status_detail_title.text = "当前%s" % String(row.get("label", "详情"))
	_status_detail_text.text = full_text
	_status_detail_text.accessibility_name = "%s：%s" % [
		_status_detail_title.text,
		full_text,
	]
	_status_detail_text.scroll_to_line(0)
	_status_detail_backdrop.visible = true
	_status_detail_backdrop.move_to_front()
	_layout_status_detail_popup()


func _close_status_detail_popup() -> void:
	_status_detail_row_index = -1
	if is_instance_valid(_status_detail_backdrop):
		_status_detail_backdrop.visible = false


func _layout_status_detail_popup() -> void:
	if not is_instance_valid(_status_detail_panel):
		return
	var margin := 16.0
	var panel_width := minf(700.0, _safe_rect.size.x - margin * 2.0)
	var panel_height := minf(360.0, _safe_rect.size.y - margin * 2.0)
	if _layout_profile in [
		LayoutProfile.COMPACT_LANDSCAPE,
		LayoutProfile.COMPACT_PORTRAIT,
	]:
		panel_width = minf(560.0, _safe_rect.size.x - margin * 2.0)
		panel_height = minf(320.0, _safe_rect.size.y - margin * 2.0)
	var row_rect := Rect2()
	if (
		_status_detail_row_index >= 0
		and _status_detail_row_index < _row_controls.size()
	):
		var row := _row_controls[_status_detail_row_index]
		row_rect = Rect2(row.global_position, row.size)
	var x := _safe_rect.position.x + (_safe_rect.size.x - panel_width) * 0.58
	var y := _safe_rect.position.y + margin
	if row_rect.has_area():
		x = clampf(
			row_rect.position.x + 90.0,
			_safe_rect.position.x + margin,
			_safe_rect.end.x - panel_width - margin,
		)
		var above := row_rect.position.y - panel_height - 10.0
		var below := row_rect.end.y + 10.0
		y = (
			above
			if above >= _safe_rect.position.y + margin
			else minf(below, _safe_rect.end.y - panel_height - margin)
		)
	_status_detail_panel.position = Vector2(x, y).round()
	_status_detail_panel.size = Vector2(panel_width, panel_height).round()
	_status_detail_title.position = Vector2(72, 54)
	_status_detail_title.size = Vector2(panel_width - 144, 54)
	_status_detail_text.position = Vector2(72, 112)
	_status_detail_text.size = Vector2(panel_width - 144, panel_height - 170)


func _on_status_detail_backdrop_input(event: InputEvent) -> void:
	var close_requested := false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		close_requested = (
			mouse_event.button_index == MOUSE_BUTTON_LEFT
			and mouse_event.pressed
		)
	elif event is InputEventScreenTouch:
		close_requested = (event as InputEventScreenTouch).pressed
	if close_requested:
		_close_status_detail_popup()
		_status_detail_backdrop.accept_event()


func _on_status_detail_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_status_detail_panel.accept_event()


func _empty_content_local_rect() -> Rect2:
	if _layout_profile == LayoutProfile.COMPACT_PORTRAIT:
		return Rect2(Vector2.ZERO, _content_rect.size)
	if _layout_profile == LayoutProfile.WIDE:
		return Rect2(
			Vector2(110, 0),
			Vector2(minf(620.0, _content_rect.size.x * 0.55), _content_rect.size.y)
		)
	return Rect2(
		Vector2(24, 0),
		Vector2(maxf(1.0, _content_rect.size.x * 0.62 - 48.0), _content_rect.size.y)
	)


func _update_freshness_copy() -> void:
	var freshness := _render_data.get("freshness", {}) as Dictionary
	var updated := str(freshness.get("updatedLabel", ""))
	var state := str(freshness.get("state", "unavailable"))
	if updated.is_empty():
		updated = "公开摘要尚未接通"
	_freshness_label.text = "%s · %s" % [
		updated,
		_freshness_state_copy(state),
	]


func _freshness_state_copy(state: String) -> String:
	match state:
		"fresh":
			return "公开摘要"
		"stale":
			return "上次确认内容"
		"partial":
			return "部分资料可用"
		_:
			return "资料未就绪"


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	_apply_responsive_layout.call_deferred()


func _apply_responsive_layout() -> void:
	_layout_queued = false
	if not is_instance_valid(_background):
		return
	var viewport_size := size.round()
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var profile_size := (
		_layout_profile_override_size
		if _layout_profile_override_size.x > 0.0
		else viewport_size
	)
	# These pages are one painted composition. Mobile keeps that composition and
	# scales it once; individual panel reflow would detach text from the artwork.
	_layout_profile = (
		LayoutProfile.WIDE
		if MOBILE_UI_PROFILE.is_mobile_runtime()
		else _select_layout_profile(profile_size)
	)
	_safe_rect = _compute_safe_rect(viewport_size)
	var design_frame := RESPONSIVE_VIEWPORT.centered_design_rect(
		viewport_size,
		DESIGN_SIZE,
	)
	_background.position = design_frame.position
	_background.size = design_frame.size
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	if _layout_profile == LayoutProfile.WIDE:
		_apply_wide_geometry(viewport_size)
	else:
		_apply_reflow_geometry(viewport_size)
	_configure_section_chrome(str(_render_data.get("selectedTab", "status")))
	_apply_static_rects()
	_render_content()
	_apply_memory_operation_visibility()
	_layout_memory_operation_panel()


func _apply_wide_geometry(viewport_size: Vector2) -> void:
	var design_frame := RESPONSIVE_VIEWPORT.centered_design_rect(
		viewport_size,
		DESIGN_SIZE,
	)
	var uniform_scale := design_frame.size.x / DESIGN_SIZE.x
	_wide_layout_scale = Vector2.ONE * uniform_scale
	_wide_layout_origin = design_frame.position
	var sx := uniform_scale
	var sy := uniform_scale
	var selected_tab := str(_render_data.get("selectedTab", "status"))
	var is_section_page := selected_tab in ["relationships", "memories"]
	var is_memory_operation := _memory_operation_visible
	_name_rect = _map_rect(WIDE_NAME_RECT, sx, sy)
	_occupation_rect = _map_rect(WIDE_OCCUPATION_RECT, sx, sy)
	_sprite_rect = _map_rect(WIDE_SPRITE_RECT, sx, sy)
	_close_rect = _map_rect(WIDE_CLOSE_RECT, sx, sy)
	_banner_rect = _map_rect(
		WIDE_SECTION_BANNER_RECT if is_section_page else WIDE_BANNER_RECT,
		sx,
		sy
	)
	var wide_content_rect := WIDE_CONTENT_RECT
	if selected_tab == "memories" and not is_memory_operation:
		wide_content_rect = WIDE_MEMORY_CONTENT_RECT
	elif is_section_page:
		wide_content_rect = WIDE_SECTION_CONTENT_RECT
	_content_rect = _map_rect(wide_content_rect, sx, sy)
	if is_memory_operation:
		_freshness_rect = _map_rect(WIDE_MEMORY_OPERATION_FRESHNESS_RECT, sx, sy)
		_section_action_rect = _map_rect(
			WIDE_MEMORY_OPERATION_SECTION_ACTION_RECT, sx, sy
		)
		_action_rect = _map_rect(WIDE_MEMORY_OPERATION_ACTION_RECT, sx, sy)
	elif selected_tab == "memories":
		_freshness_rect = _map_rect(WIDE_MEMORY_FRESHNESS_RECT, sx, sy)
		_section_action_rect = _map_rect(WIDE_MEMORY_SECTION_ACTION_RECT, sx, sy)
		_action_rect = _map_rect(WIDE_MEMORY_ACTION_RECT, sx, sy)
	else:
		_freshness_rect = _map_rect(
			WIDE_FRESHNESS_RECT if is_section_page else WIDE_STATUS_FRESHNESS_RECT,
			sx,
			sy
		)
		_section_action_rect = _map_rect(WIDE_SECTION_ACTION_RECT, sx, sy)
		_action_rect = _map_rect(
			WIDE_ACTION_RECT if is_section_page else WIDE_STATUS_ACTION_RECT,
			sx,
			sy
		)
	_tab_rects.clear()
	_tab_text_rects.clear()
	_row_rects.clear()
	_section_filter_rects.clear()
	for rect: Rect2 in WIDE_TAB_RECTS:
		_tab_rects.append(_map_rect(rect, sx, sy))
	for rect: Rect2 in WIDE_TAB_TEXT_RECTS:
		_tab_text_rects.append(_map_rect(rect, sx, sy))
	var source_row_rects := WIDE_ROW_RECTS
	if selected_tab == "relationships":
		source_row_rects = WIDE_RELATIONSHIP_ROW_RECTS
	elif selected_tab == "memories":
		source_row_rects = WIDE_MEMORY_ROW_RECTS
	for rect: Rect2 in source_row_rects:
		_row_rects.append(_map_rect(rect, sx, sy))
	for rect: Rect2 in WIDE_SECTION_FILTER_RECTS:
		_section_filter_rects.append(_map_rect(rect, sx, sy))


func _apply_reflow_geometry(viewport_size: Vector2) -> void:
	_wide_layout_scale = Vector2(
		viewport_size.x / DESIGN_SIZE.x,
		viewport_size.y / DESIGN_SIZE.y,
	)
	_wide_layout_origin = Vector2.ZERO
	var safe := _safe_rect
	_section_action_rect = Rect2()
	_section_filter_rects.clear()
	var compact_landscape := (
		_layout_profile == LayoutProfile.COMPACT_LANDSCAPE
	)
	var compact_portrait := (
		_layout_profile == LayoutProfile.COMPACT_PORTRAIT
	)
	var gap := 8.0 if compact_landscape else 12.0
	var header_height := (
		52.0
		if compact_landscape
		else (92.0 if compact_portrait else 116.0)
	)
	var tab_height := 52.0 if compact_landscape else 72.0
	var banner_height := 56.0 if compact_landscape else 82.0
	var footer_height := 54.0 if compact_landscape else 76.0
	var close_size := 52.0 if compact_landscape else 64.0
	_close_rect = Rect2(
		Vector2(safe.end.x - close_size, safe.position.y),
		Vector2(close_size, close_size)
	)
	_name_rect = Rect2(
		Vector2(safe.position.x + 16.0, safe.position.y),
		Vector2(
			safe.size.x - close_size - 32.0,
			header_height * 0.52
		)
	)
	_occupation_rect = Rect2(
		Vector2(safe.position.x + 16.0, _name_rect.end.y),
		Vector2(
			safe.size.x - close_size - 32.0,
			header_height * 0.40
		)
	)
	_sprite_rect = Rect2()
	_resident_sprite.visible = false
	var tab_top := safe.position.y + header_height
	var tab_width := (safe.size.x - gap * 2.0) / 3.0
	_tab_rects.clear()
	_tab_text_rects.clear()
	for index: int in 3:
		var tab_rect := Rect2(
			Vector2(
				safe.position.x + (tab_width + gap) * index,
				tab_top
			),
			Vector2(tab_width, tab_height)
		)
		_tab_rects.append(tab_rect)
		_tab_text_rects.append(tab_rect)
	_banner_rect = Rect2(
		Vector2(safe.position.x, tab_top + tab_height + gap),
		Vector2(safe.size.x, banner_height)
	)
	var content_top := _banner_rect.end.y + gap
	var content_bottom := safe.end.y - footer_height - gap
	_content_rect = Rect2(
		Vector2(safe.position.x, content_top),
		Vector2(safe.size.x, maxf(48.0, content_bottom - content_top))
	)
	_freshness_rect = Rect2(
		Vector2(safe.position.x, safe.end.y - footer_height),
		Vector2(maxf(120.0, safe.size.x - 170.0), footer_height)
	)
	_action_rect = Rect2(
		Vector2(safe.end.x - 150.0, safe.end.y - footer_height),
		Vector2(150, footer_height)
	)
	_row_rects.clear()
	var row_height := (
		64.0
		if compact_landscape
		else maxf(56.0, _content_rect.size.y / 5.0)
	)
	for index: int in 5:
		_row_rects.append(Rect2(
			Vector2(
				_content_rect.position.x,
				_content_rect.position.y + row_height * index
			),
			Vector2(_content_rect.size.x, row_height)
		))


func _apply_static_rects() -> void:
	_name_label.position = _name_rect.position
	_name_label.size = _name_rect.size
	_occupation_label.position = _occupation_rect.position
	_occupation_label.size = _occupation_rect.size
	_resident_sprite.position = _sprite_rect.position
	_resident_sprite.size = _sprite_rect.size
	_resident_sprite.visible = (
		_sprite_rect.has_area() and _resident_sprite.texture != null
	)
	_close_button.position = _close_rect.position
	_close_button.size = _close_rect.size
	_banner_label.position = _banner_rect.position
	_banner_label.size = _banner_rect.size
	_layout_status_detail_popup()
	_content_scroll.position = _content_rect.position
	_content_scroll.size = _content_rect.size
	_content_scroll_chrome.position = Vector2(
		_content_rect.end.x - 40.0,
		_content_rect.position.y + 4.0,
	)
	_content_scroll_chrome.size = Vector2(
		38.0,
		maxf(1.0, _content_rect.size.y - 8.0),
	)
	_content_root.position = Vector2.ZERO
	var content_canvas_height := _content_rect.size.y
	if not _row_rects.is_empty():
		content_canvas_height = maxf(
			content_canvas_height,
			_row_rects[-1].end.y - _content_rect.position.y
		)
	_content_root.custom_minimum_size = Vector2(
		_content_rect.size.x,
		content_canvas_height
	)
	_content_root.size = _content_root.custom_minimum_size
	_meter_overlay_root.position = Vector2.ZERO
	_meter_overlay_root.size = size
	_feedback_label.position = Rect2(
		Vector2(_content_rect.position.x, _content_rect.position.y - 34.0),
		Vector2(_content_rect.size.x, 36.0)
	).position
	_feedback_label.size = Vector2(_content_rect.size.x, 36.0)
	_freshness_label.position = _freshness_rect.position
	_freshness_label.size = _freshness_rect.size
	_action_button.position = _action_rect.position
	_action_button.size = _action_rect.size
	_section_action_button.position = _section_action_rect.position
	_section_action_button.size = _section_action_rect.size
	for index: int in _section_filter_buttons.size():
		var filter_button := _section_filter_buttons[index]
		if index < _section_filter_rects.size():
			filter_button.position = _section_filter_rects[index].position
			filter_button.size = _section_filter_rects[index].size
		else:
			filter_button.visible = false
	for index: int in TAB_IDS.size():
		var tab := _tab_buttons[TAB_IDS[index]] as ResidentDetailTabButton
		tab.position = _tab_rects[index].position
		tab.size = _tab_rects[index].size
		var config_rect := Rect2(
			_tab_text_rects[index].position - _tab_rects[index].position,
			_tab_text_rects[index].size
		)
		var current := _tabs_by_id().get(TAB_IDS[index], {}) as Dictionary
		var availability := str(current.get("availability", "disabled"))
		var action := UiViewModel.action(
			_view_model,
			str(ACTION_KEYS[TAB_IDS[index]])
		)
		tab.configure({
			"tabId": TAB_IDS[index],
			"label": str(current.get("label", TAB_LABELS[TAB_IDS[index]])),
			"contentRect": config_rect,
			"selected": TAB_IDS[index] == str(_render_data.get("selectedTab", "status")),
			"disabled": not (
				availability in ["ready", "partial", "stale"]
				and UiViewModel.action_enabled(action)
			),
			"fontSize": _tab_font_size(),
			"normalColor": Color("3f2818"),
			"selectedColor": Color("b94d2d"),
			"hoverColor": Color("8f3b23"),
			"pressedColor": Color("6c3d20"),
			"disabledColor": Color("806a5b"),
		})
	_queue_wood_scrollbar_refresh()


func _status_slots(row_rect: Rect2) -> Dictionary:
	if _layout_profile == LayoutProfile.WIDE:
		var sx := _wide_layout_scale.x
		var sy := _wide_layout_scale.y
		var origin_x := _wide_layout_origin.x
		return {
			"label": Rect2(Vector2(origin_x + 760.0 * sx, row_rect.position.y), Vector2(82.0 * sx, row_rect.size.y)),
			"summary": Rect2(Vector2(origin_x + 850.0 * sx, row_rect.position.y), Vector2(300.0 * sx, row_rect.size.y)),
			"meterLabel": Rect2(Vector2(origin_x + 1170.0 * sx, row_rect.position.y), Vector2(82.0 * sx, row_rect.size.y)),
			"meterValue": Rect2(Vector2(origin_x + 1260.0 * sx, row_rect.position.y), Vector2(92.0 * sx, row_rect.size.y)),
			"track": Rect2(Vector2(origin_x + 1371.0 * sx, row_rect.position.y + roundf((row_rect.size.y - 94.0 * sy) * 0.5)), Vector2(420.0 * sx, 94.0 * sy)),
		}
	if _layout_profile == LayoutProfile.COMPACT_PORTRAIT:
		var top_height := row_rect.size.y * 0.46
		var bottom_height := row_rect.size.y - top_height
		var track_width := minf(250.0, row_rect.size.x * 0.62)
		return {
			"label": Rect2(row_rect.position, Vector2(76, top_height)),
			"summary": Rect2(row_rect.position + Vector2(80, 0), Vector2(row_rect.size.x - 80, top_height)),
			"meterLabel": Rect2(row_rect.position + Vector2(8, top_height), Vector2(72, bottom_height)),
			"meterValue": Rect2(row_rect.position + Vector2(82, top_height), Vector2(row_rect.size.x - track_width - 90, bottom_height)),
			"track": Rect2(Vector2(row_rect.end.x - track_width, row_rect.position.y + top_height + 4), Vector2(track_width, maxf(48.0, bottom_height - 8))),
		}
	var track_width := clampf(row_rect.size.x * 0.40, 300.0, 420.0)
	var left_width := row_rect.size.x - track_width - 12.0
	return {
		"label": Rect2(row_rect.position + Vector2(8, 0), Vector2(78, row_rect.size.y)),
		"summary": Rect2(row_rect.position + Vector2(90, 0), Vector2(maxf(140.0, left_width - 280.0), row_rect.size.y)),
		"meterLabel": Rect2(Vector2(row_rect.position.x + left_width - 180.0, row_rect.position.y), Vector2(78, row_rect.size.y)),
		"meterValue": Rect2(Vector2(row_rect.position.x + left_width - 98.0, row_rect.position.y), Vector2(98, row_rect.size.y)),
		"track": Rect2(Vector2(row_rect.end.x - track_width, row_rect.position.y + maxf(0.0, (row_rect.size.y - 94.0) * 0.5)), Vector2(track_width, minf(94.0, row_rect.size.y))),
	}


func _map_rect(rect: Rect2, sx: float, sy: float) -> Rect2:
	return Rect2(
		(
			_wide_layout_origin
			+ rect.position * Vector2(sx, sy)
		).round(),
		(rect.size * Vector2(sx, sy)).round()
	)


func _select_layout_profile(profile_size: Vector2) -> LayoutProfile:
	var aspect := profile_size.x / maxf(profile_size.y, 1.0)
	if profile_size.x >= 1500.0 and profile_size.y >= 840.0:
		return LayoutProfile.WIDE
	if profile_size.x >= 1000.0 and aspect >= 1.2:
		return LayoutProfile.STANDARD
	if aspect >= 1.2:
		return LayoutProfile.COMPACT_LANDSCAPE
	return LayoutProfile.COMPACT_PORTRAIT


func _layout_profile_name(profile: LayoutProfile) -> String:
	match profile:
		LayoutProfile.WIDE:
			return "wide"
		LayoutProfile.STANDARD:
			return "standard"
		LayoutProfile.COMPACT_LANDSCAPE:
			return "compact_landscape"
		_:
			return "compact_portrait"


func _compute_safe_rect(viewport_size: Vector2) -> Rect2:
	var default_margin := (
		48.0 if _layout_profile == LayoutProfile.WIDE else 18.0
	)
	var insets := Vector4(
		default_margin,
		default_margin,
		default_margin,
		default_margin
	)
	if _safe_insets_override.x >= 0.0:
		insets = _safe_insets_override
	return Rect2(
		Vector2(insets.x, insets.y),
		Vector2(
			maxf(1.0, viewport_size.x - insets.x - insets.z),
			maxf(1.0, viewport_size.y - insets.y - insets.w)
		)
	)


func _update_focus_chain() -> void:
	_focus_controls.clear()
	if _memory_operation_visible:
		for control: Control in [
			_memory_operation_edit_tab,
			_memory_operation_delete_tab,
			_memory_operation_input,
			_memory_operation_cancel,
			_memory_operation_confirm,
		]:
			if _is_focusable_control(control):
				_focus_controls.append(control)
		if _is_focusable_control(_close_button):
			_focus_controls.append(_close_button)
		_apply_focus_neighbors()
		return
	for tab_id: String in TAB_IDS:
		var tab := _tab_buttons.get(tab_id) as Control
		if _is_focusable_control(tab):
			_focus_controls.append(tab)
	for filter_button: Button in _section_filter_buttons:
		if _is_focusable_control(filter_button):
			_focus_controls.append(filter_button)
	for row: Control in _row_controls:
		if _is_focusable_control(row):
			_focus_controls.append(row)
	if (
		_is_focusable_control(_section_action_button)
	):
		_focus_controls.append(_section_action_button)
	if _is_focusable_control(_action_button):
		_focus_controls.append(_action_button)
	if _is_focusable_control(_close_button):
		_focus_controls.append(_close_button)
	_apply_focus_neighbors()


func _apply_focus_neighbors() -> void:
	var valid_controls: Array[Control] = []
	for control: Control in _focus_controls:
		if _is_focusable_control(control):
			valid_controls.append(control)
	_focus_controls = valid_controls
	if _focus_controls.is_empty():
		return
	for index: int in _focus_controls.size():
		var current := _focus_controls[index]
		var previous := _focus_controls[posmod(index - 1, _focus_controls.size())]
		var next := _focus_controls[(index + 1) % _focus_controls.size()]
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_neighbor_left = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_neighbor_right = current.get_path_to(next)


func _move_focus(direction: int) -> void:
	var available: Array[Control] = []
	for control: Control in _focus_controls:
		if _is_focusable_control(control):
			available.append(control)
	if available.is_empty():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not is_instance_valid(focused):
		focus_default()
		return
	var index := available.find(focused)
	if index < 0:
		focus_default()
		return
	var target := available[posmod(index + direction, available.size())]
	if not _is_focusable_control(target):
		focus_default()
		return
	target.grab_focus()


func _focused_semantic() -> String:
	var focused := get_viewport().gui_get_focus_owner()
	if (
		focused == null
		or not is_instance_valid(focused)
		or not focused.is_inside_tree()
		or not is_ancestor_of(focused)
	):
		return ""
	for tab_id: String in TAB_IDS:
		if _tab_buttons.get(tab_id) == focused:
			return "tab:%s" % tab_id
	var filter_index := -1
	if focused is Button:
		filter_index = _section_filter_buttons.find(focused as Button)
	if filter_index >= 0:
		return "filter:%d" % filter_index
	var row_index := _row_controls.find(focused)
	if row_index >= 0:
		return "row:%d" % row_index
	if focused == _action_button:
		return "primary"
	if focused == _section_action_button:
		return "section_action"
	if focused == _close_button:
		return "close"
	return ""


func _restore_semantic_focus(semantic: String) -> void:
	if semantic.is_empty():
		return
	var target: Control
	if semantic.begins_with("tab:"):
		target = _tab_buttons.get(semantic.trim_prefix("tab:")) as Control
	elif semantic.begins_with("filter:"):
		var filter_index := int(semantic.trim_prefix("filter:"))
		if filter_index >= 0 and filter_index < _section_filter_buttons.size():
			target = _section_filter_buttons[filter_index]
	elif semantic.begins_with("row:"):
		var row_index := int(semantic.trim_prefix("row:"))
		if row_index >= 0 and row_index < _row_controls.size():
			target = _row_controls[row_index]
	elif semantic == "primary":
		target = _action_button
	elif semantic == "section_action":
		target = _section_action_button
	elif semantic == "close":
		target = _close_button
	if _is_focusable_control(target):
		target.grab_focus()
	else:
		focus_default()


func _is_focusable_control(value: Variant) -> bool:
	if not is_instance_valid(value) or not value is Control:
		return false
	var control := value as Control
	return (
		control.is_inside_tree()
		and is_ancestor_of(control)
		and control.is_visible_in_tree()
		and control.focus_mode != Control.FOCUS_NONE
		and (
			not control is BaseButton
			or not (control as BaseButton).disabled
		)
	)


func _queue_focus_grab(control: Control) -> void:
	call_deferred("_grab_focus_if_valid", control)


func _grab_focus_if_valid(control: Control) -> void:
	if _is_focusable_control(control):
		control.grab_focus()


func _cancel_semantic_focus_restore() -> void:
	_semantic_focus_request_id += 1


func _queue_semantic_focus_restore(semantic: String) -> void:
	if semantic.is_empty():
		return
	_semantic_focus_request_id += 1
	call_deferred(
		"_restore_semantic_focus_if_current",
		semantic,
		_semantic_focus_request_id,
	)


func _restore_semantic_focus_if_current(
	semantic: String,
	request_id: int,
) -> void:
	if request_id != _semantic_focus_request_id or not is_inside_tree():
		return
	_restore_semantic_focus(semantic)


func _on_tab_activated(tab_id: String) -> void:
	if _memory_operation_visible:
		_close_memory_operation_panel()
	request_tab(tab_id)


func _on_close_requested() -> void:
	if _memory_operation_visible:
		_close_memory_operation_panel()
		return
	request_close()


func _on_primary_action_requested() -> void:
	request_refresh()


func _on_section_action_requested() -> void:
	if str(_render_data.get("selectedTab", "status")) == "memories":
		_open_memory_change_dialog("edit")
		return
	request_refresh()


func _on_section_filter_pressed(index: int) -> void:
	var selected_tab := str(_render_data.get("selectedTab", "status"))
	if selected_tab not in ["relationships", "memories"]:
		return
	var filter_ids: Array[String]
	var action_keys: Array[String]
	if selected_tab == "relationships":
		filter_ids = ["all", "close", "trust", "conflict", "distant", "player"]
		action_keys = [
			"filterRelationshipAll",
			"filterRelationshipClose",
			"filterRelationshipTrust",
			"filterRelationshipConflict",
			"filterRelationshipDistant",
			"filterRelationshipPlayer",
		]
	else:
		filter_ids = ["all", "influencing", "past", "doubtful", "anomalous", "interventions"]
		action_keys = [
			"filterAll",
			"filterInfluencing",
			"filterPast",
			"filterDoubtful",
			"filterAnomalous",
			"filterInterventions",
		]
	if index < 0 or index >= filter_ids.size() or index >= action_keys.size():
		return
	_request_action(action_keys[index], {"filterId": filter_ids[index]})


func _on_row_gui_input(event: InputEvent, index: int) -> void:
	var activate := false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		activate = (
			mouse_event.button_index == MOUSE_BUTTON_LEFT
			and not mouse_event.pressed
		)
	elif event is InputEventScreenTouch:
		activate = not (event as InputEventScreenTouch).pressed
	else:
		activate = event.is_action_pressed(&"ui_accept")
	if not activate:
		return
	_selected_content_index = index
	if str(_render_data.get("selectedTab", "status")) == "memories":
		var items := ((_render_data.get("content", {}) as Dictionary).get("items", []) as Array)
		if index >= 0 and index < items.size() and items[index] is Dictionary:
			_selected_memory_key = str((items[index] as Dictionary).get("memoryId", ""))
	_finish_row_activation.call_deferred(index)
	get_viewport().set_input_as_handled()


func _finish_row_activation(index: int) -> void:
	_render_content()
	if String(_render_data.get("selectedTab", "status")) == "status":
		_open_status_detail_popup(index)


func _request_action(action_key: String, extra_payload: Dictionary) -> bool:
	var action := UiViewModel.action(_view_model, action_key)
	var intent := StringName(action.get("intent", ""))
	if intent.is_empty():
		_local_feedback = "当前操作尚不可用。"
		_present_local_feedback()
		action_blocked.emit(intent, "MISSING_INTENT")
		return false
	if not UiViewModel.action_enabled(action):
		var reason := UiViewModel.disabled_reason(action)
		if reason.is_empty():
			reason = "ACTION_DISABLED"
		_local_feedback = _player_copy_for_disabled(reason)
		_present_local_feedback()
		action_blocked.emit(intent, reason)
		return false
	var payload := (action.get("payload", {}) as Dictionary).duplicate(true)
	var resident := _render_data.get("resident", {}) as Dictionary
	payload.merge(extra_payload, true)
	payload["residentId"] = str(resident.get("residentId", ""))
	payload["revision"] = _current_revision
	payload["selectedTab"] = str(
		_render_data.get("selectedTab", "status")
	)
	intent_requested.emit(intent, payload.duplicate(true))
	if _adapter == null or not _adapter.has_method("dispatch"):
		if action_key == "close":
			return true
			_local_feedback = "居民公开资料暂时无法查看。"
		_present_local_feedback()
		action_blocked.emit(intent, "TOWN_UI_ADAPTER_DISPATCH_MISSING")
		return false
	var result: Variant = _adapter.call("dispatch", str(intent), payload)
	if result is Dictionary and not bool((result as Dictionary).get("ok", false)):
		var error_code := str(
			(result as Dictionary).get("errorCode", "ACTION_REJECTED")
		)
		_local_feedback = _player_copy_for_disabled(error_code)
		_present_local_feedback()
		action_blocked.emit(intent, error_code)
		return false
	return true


func _present_local_feedback() -> void:
	_cancel_semantic_focus_restore()
	var focused_semantic := _focused_semantic()
	_update_feedback_copy()
	_render_content()
	_queue_semantic_focus_restore(focused_semantic)


func _player_copy_for_disabled(reason: String) -> String:
	if reason.contains("RELATION"):
		return "关系公开摘要暂不可用。"
	if reason.contains("MEMORY"):
		return "记忆公开摘要暂不可用。"
	if reason.contains("INTERFACE") or reason.contains("SCOPE"):
		return "居民公开资料暂时无法查看。"
	return "当前操作尚不可用。"


func _unavailable_section_copy(section_label: String, availability: String) -> String:
	match availability:
		"partial":
			return "%s公开摘要暂不完整，正在保留已确认内容。" % section_label
		"stale":
			return "%s公开摘要正在等待更新。" % section_label
		"loading":
			return "正在整理%s公开摘要。" % section_label
		"error":
			return "%s公开摘要暂时没有完成整理。" % section_label
		_:
			return "%s公开摘要暂不可用。" % section_label


func _refresh_from_adapter() -> void:
	if _adapter == null or not _adapter.has_method("get_view_model"):
		_enter_adapter_unavailable(
			"RESIDENT_DETAIL_ADAPTER_CONTRACT_INVALID",
			"TownUiAdapter 缺少 get_view_model。"
		)
		return
	var incoming: Variant = _adapter.call("get_view_model", str(SCOPE))
	if not incoming is Dictionary:
		_enter_adapter_unavailable(
			"RESIDENT_DETAIL_VIEW_MODEL_MISSING",
			"TownUiAdapter 尚未返回居民详情完整 ViewModel。"
		)
		return
	if not apply_view_model(incoming as Dictionary) and _view_model.is_empty():
		_enter_adapter_unavailable(
			"RESIDENT_DETAIL_VIEW_MODEL_INCOMPLETE",
			"TownUiAdapter 尚未提供居民详情完整字段。"
		)


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_view_model_changed"),
	)


func _on_view_model_changed(scope_value: Variant, snapshot: Dictionary) -> void:
	if StringName(scope_value) != SCOPE:
		return
	if not apply_view_model(snapshot):
		view_model_rejected.emit(
			"TownUiAdapter resident_detail 更新未通过完整合同校验。"
		)


func _enter_adapter_unavailable(code: String, message: String) -> void:
	_adapter_contract_available = false
	var revision := maxi(_current_revision, 0)
	var actions := {}
	var intents := {
		"close": "resident_detail.close",
		"selectStatus": "resident_detail.select_tab",
		"selectRelationships": "resident_detail.select_tab",
		"selectMemories": "resident_detail.select_tab",
		"refresh": "resident_detail.refresh",
		"retry": "resident_detail.retry",
		"editMemory": "resident_detail.change_memory",
		"deleteMemory": "resident_detail.change_memory",
	}
	for action_key: String in intents:
		actions[action_key] = {
			"intent": intents[action_key],
			"enabled": action_key == "close",
			"disabledReason": "" if action_key == "close" else code,
			"payload": {},
		}
	_view_model = {
		"scope": str(SCOPE),
		"status": "disabled",
		"revision": revision,
		"data": {
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": false,
			"contractVersion": "resident-detail-v1-unavailable",
			"resident": {
				"residentId": "",
				"displayName": "居民详情",
				"occupationLabel": "",
				"currentPlaceLabel": "",
				"portrait": "",
				"identityStatus": "unavailable",
			},
			"context": {
				"worldRunState": "unknown",
				"contextLabel": "资料未就绪",
				"presentationMode": "fullscreen_overlay",
			},
			"selectedTab": "status",
			"tabs": [
				{"id": "status", "label": "状态", "availability": "disabled", "disabledReason": code},
				{"id": "relationships", "label": "关系", "availability": "disabled", "disabledReason": "RESIDENT_RELATIONSHIP_PUBLIC_INTERFACE_MISSING"},
				{"id": "memories", "label": "记忆", "availability": "disabled", "disabledReason": "RESIDENT_MEMORY_PUBLIC_INTERFACE_MISSING"},
			],
			"content": {},
			"freshness": {
				"state": "unavailable",
				"lastConfirmedRevision": revision,
				"updatedLabel": "公开摘要尚未接通",
				"retainedFromRevision": 0,
				"retainedSections": [],
				"unavailableSections": ["status", "relationships", "memories"],
			},
			"privacy": {
				"policyId": "resident-detail-public-summary-v1",
				"publicSummaryOnly": true,
				"sanitizedUpstream": true,
				"containsAgentPrivateText": false,
			},
		},
		"actions": actions,
		"operation": {
			"requestId": "",
			"intent": "",
			"status": "disabled",
			"submittedAtMsec": 0,
			"completedAtMsec": 0,
		},
		"error": {
			"kind": "unavailable",
			"code": code,
			"message": message,
			"retryable": false,
		},
	}
	_render_data = (_view_model["data"] as Dictionary).duplicate(true)
	_current_revision = revision
	_local_feedback = "居民公开资料暂时无法查看。"
	if is_node_ready():
		_render()


func _reset_view_model_state() -> void:
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	_current_revision = -1
	_selected_content_index = -1
	_selected_memory_key = ""
	_last_operation_request_id = ""
	_completed_request_ids.clear()
	_local_feedback = ""
	_adapter_contract_available = false


func _validate_view_model(snapshot: Dictionary) -> PackedStringArray:
	var issues := UiViewModel.validate(snapshot, "居民详情")
	if UiViewModel.scope(snapshot) != SCOPE:
		issues.append("居民详情.scope 必须是 resident_detail")
	var status := str(snapshot.get("status", ""))
	if status not in VALID_DATA_STATUSES:
		issues.append("居民详情.status 无效：%s" % status)
	var data_value: Variant = snapshot.get("data", {})
	if not data_value is Dictionary:
		return issues
	var data := data_value as Dictionary
	for key: String in [
		"capabilityMode",
		"source",
		"formalReady",
		"contractVersion",
		"resident",
		"context",
		"selectedTab",
		"tabs",
		"content",
		"freshness",
		"privacy",
	]:
		if not data.has(key):
			issues.append("居民详情.data 缺少字段：%s" % key)
	if not data.get("resident", {}) is Dictionary:
		issues.append("居民详情.data.resident 必须是 Dictionary")
	if not data.get("context", {}) is Dictionary:
		issues.append("居民详情.data.context 必须是 Dictionary")
	var tabs_value: Variant = data.get("tabs", [])
	if not tabs_value is Array:
		issues.append("居民详情.data.tabs 必须是 Array")
	else:
		var tab_ids: Array[String] = []
		for tab_value: Variant in tabs_value as Array:
			if not tab_value is Dictionary:
				issues.append("居民详情.data.tabs 项必须是 Dictionary")
				continue
			var tab := tab_value as Dictionary
			for tab_field: String in ["id", "label", "availability"]:
				if not tab.has(tab_field):
					issues.append(
						"居民详情.data.tabs 项缺少字段：%s"
						% tab_field
					)
			var tab_id := str(tab.get("id", ""))
			tab_ids.append(tab_id)
			var availability := str(tab.get("availability", ""))
			if availability not in VALID_TAB_AVAILABILITIES:
				issues.append(
					"居民详情标签 %s availability 无效：%s"
					% [tab_id, availability]
				)
			if (
				availability in ["disabled", "unavailable", "error"]
				and str(tab.get("disabledReason", "")).is_empty()
			):
				issues.append(
					"居民详情禁用标签 %s 缺少 disabledReason"
					% tab_id
				)
		if tab_ids != TAB_IDS:
			issues.append(
				"居民详情 tabs 必须严格为 status/relationships/memories"
			)
	if not data.get("content", {}) is Dictionary:
		issues.append("居民详情.data.content 必须是 Dictionary")
	if not data.get("freshness", {}) is Dictionary:
		issues.append("居民详情.data.freshness 必须是 Dictionary")
	if not data.get("privacy", {}) is Dictionary:
		issues.append("居民详情.data.privacy 必须是 Dictionary")
	else:
		var privacy := data.get("privacy", {}) as Dictionary
		if not bool(privacy.get("publicSummaryOnly", false)):
			issues.append("居民详情只允许 publicSummaryOnly 数据")
		if not bool(privacy.get("sanitizedUpstream", false)):
			issues.append("居民详情数据必须由上游脱敏")
		if bool(privacy.get("containsAgentPrivateText", true)):
			issues.append("居民详情禁止 Agent 私有原文")
	if _contains_forbidden_private_data(data):
		issues.append("居民详情.data 含禁止的 Agent/World 私有字段")
	var selected_tab := str(data.get("selectedTab", ""))
	if selected_tab not in TAB_IDS:
		issues.append("居民详情.selectedTab 无效：%s" % selected_tab)
	var actions_value: Variant = snapshot.get("actions", {})
	if not actions_value is Dictionary:
		issues.append("居民详情.actions 必须是 Dictionary")
	else:
		var actions := actions_value as Dictionary
		for action_key_value: Variant in actions:
			var action_key := str(action_key_value)
			if not ACTION_INTENTS.has(action_key):
				issues.append(
					"居民详情.actions 含未声明动作：%s" % action_key
				)
		for action_key: String in ACTION_INTENTS:
			var action_value: Variant = actions.get(action_key)
			if not action_value is Dictionary:
				if action_key in OPTIONAL_ACTION_KEYS:
					continue
				issues.append("居民详情.actions 缺少动作：%s" % action_key)
				continue
			var action := action_value as Dictionary
			for action_field: String in [
				"intent",
				"enabled",
				"disabledReason",
			]:
				if not action.has(action_field):
					issues.append(
						"居民详情 action %s 缺少字段：%s"
						% [action_key, action_field]
					)
			if str(action.get("intent", "")) != str(
				ACTION_INTENTS[action_key]
			):
				issues.append(
					"居民详情 action %s intent 与正式合同不一致"
					% action_key
				)
			if (
				not bool(action.get("enabled", false))
				and str(action.get("disabledReason", "")).is_empty()
			):
				issues.append(
					"居民详情禁用 action %s 缺少 disabledReason"
					% action_key
				)
			if (
				bool(action.get("enabled", false))
				and not str(action.get("disabledReason", "")).is_empty()
			):
				issues.append(
					"居民详情可用 action %s 不得携带 disabledReason"
					% action_key
				)
			if (
				action.has("payload")
				and not action.get("payload") is Dictionary
			):
				issues.append(
					"居民详情 action %s payload 必须是 Dictionary"
					% action_key
				)
		var close_value: Variant = actions.get("close")
		if (
			close_value is Dictionary
			and not bool((close_value as Dictionary).get("enabled", false))
		):
			issues.append("居民详情 close 必须始终可用")
	return issues


func _contains_forbidden_private_data(value: Variant) -> bool:
	if value is Dictionary:
		for key_value: Variant in (value as Dictionary):
			var normalized := (
				str(key_value)
				.to_lower()
				.replace("_", "")
				.replace("-", "")
				.replace(" ", "")
				.replace(".", "")
				.replace(":", "")
			)
			if normalized in FORBIDDEN_PRIVATE_DATA_KEYS:
				return true
			if _contains_forbidden_private_data((value as Dictionary)[key_value]):
				return true
	elif value is Array:
		for item: Variant in value as Array:
			if _contains_forbidden_private_data(item):
				return true
	return false


func _same_resident(first: Dictionary, second: Dictionary) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	var first_id := str((first.get("resident", {}) as Dictionary).get("residentId", ""))
	var second_id := str((second.get("resident", {}) as Dictionary).get("residentId", ""))
	return not first_id.is_empty() and first_id == second_id


func _tabs_by_id() -> Dictionary:
	var result := {}
	for value: Variant in _render_data.get("tabs", []) as Array:
		if value is Dictionary:
			var tab := value as Dictionary
			result[str(tab.get("id", ""))] = tab
	return result


func _primary_action_key() -> String:
	var error_value: Variant = _view_model.get("error", null)
	if error_value is Dictionary:
		var error := error_value as Dictionary
		if bool(error.get("retryable", false)):
			return "retry"
	return "refresh"


func _contract_unavailable_message() -> String:
	if not _adapter_contract_available:
		return "居民公开资料暂时无法查看。"
	var message := UiViewModel.error_message(_view_model)
	if message.is_empty():
		return "居民公开资料暂时无法查看。"
	return message


func _update_operation_receipt() -> void:
	var operation := UiViewModel.operation(_view_model)
	var request_id := str(operation.get("requestId", ""))
	var status := str(operation.get("status", "idle"))
	if request_id.is_empty() or status in ["idle", "loading"]:
		_last_operation_request_id = request_id
		return
	if _completed_request_ids.has(request_id):
		return
	_completed_request_ids[request_id] = true
	_last_operation_request_id = request_id
	if _completed_request_ids.size() > 32:
		_completed_request_ids.erase(_completed_request_ids.keys()[0])


func _reduced_motion_requested() -> bool:
	return bool(
		(_render_data.get("context", {}) as Dictionary).get(
			"reducedMotion",
			false
		)
	)


func _tab_font_size() -> int:
	return 28 if _layout_profile != LayoutProfile.WIDE else 32


func _action_font_size() -> int:
	return 28 if _layout_profile == LayoutProfile.COMPACT_PORTRAIT else 32


func _content_font_size() -> int:
	return 24 if _layout_profile == LayoutProfile.COMPACT_PORTRAIT else 28


func _rect_payload(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
	}
