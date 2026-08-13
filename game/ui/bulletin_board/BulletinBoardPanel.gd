class_name BulletinBoardPanel
extends Control


signal intent_requested(intent: StringName, payload: Dictionary)
signal action_blocked(intent: StringName, reason: String)

const UI_VIEW_MODEL := preload(
	"res://ui/common/AiTownUiViewModel.gd"
)
const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")
const PageTheme := preload("res://ui/bulletin_board/BulletinBoardTheme.gd")
const HistoryRail := preload(
	"res://ui/bulletin_board/BulletinBoardHistoryRail.gd"
)
const DIALOG_SCENE := preload(
	"res://ui/common/system_feedback/SystemFeedbackDialog.tscn"
)
const TOAST_SCENE := preload(
	"res://ui/common/system_feedback/SystemFeedbackToast.tscn"
)

const SCOPE := &"announcements"
const APPROVED_SOURCE := preload(
	"res://assets/ui/bulletin_board/final/"
	+ "bulletin_board_complete_runtime_shell_v1.png"
)
const APPROVED_SOURCE_SIZE := Vector2(1672, 941)
const OVERVIEW_SOURCE := preload(
	"res://assets/ui/bulletin_board/final/"
	+ "bulletin_board_side_panel_shell_v1.png"
)
const OVERVIEW_SOURCE_SIZE := Vector2(640, 960)
const OVERVIEW_DESKTOP_RIGHT_MARGIN := 48.0
const OVERVIEW_DESKTOP_TOP := 64.0
const MINIMUM_TOUCH_SIZE := Vector2(48, 48)
const DRAFT_DEBOUNCE_SECONDS := 0.12
const HISTORY_SWIPE_THRESHOLD := 40.0

const EXPECTED_INTENTS := {
	"openComposer": "announcements.composer.open",
	"updateDraft": "announcements.draft.update",
	"publish": "announcements.publish",
	"requestClose": "announcements.panel.close",
	"continueEditing": "announcements.draft.continue",
	"discardDraft": "announcements.draft.discard",
	"retry": "announcements.retry",
	"dismissFeedback": "announcements.feedback.dismiss",
}
const VALIDATION_COPY := {
	"EMPTY_ANNOUNCEMENT": "请先写点内容。",
	"ANNOUNCEMENT_TOO_LONG_PLACEHOLDER": "超过字数上限，原文已保留。",
}
const OPERATION_COPY := {
	"idle": "小镇时间照常流动",
	"loading": "正在发布，草稿已经保留……",
	"success": "公告已经发布",
	"rejected": "这条公告没有发布，草稿已经保留。",
	"error": "发布暂时没有响应，草稿已经保留。",
	"disabled": "公告栏页面合同尚未就绪。",
}
const WIDE_RECTS := {
	"title": Rect2(610, 118, 300, 80),
	"page": Rect2(918, 126, 142, 64),
	"newer": Rect2(464, 122, 96, 68),
	"older": Rect2(1104, 122, 96, 68),
	"close": Rect2(1218, 122, 108, 68),
	"card_1_time": Rect2(432, 238, 416, 56),
	"card_1_body": Rect2(432, 308, 416, 154),
	"card_2_time": Rect2(432, 516, 416, 56),
	"card_2_body": Rect2(432, 584, 416, 164),
	"empty": Rect2(432, 308, 416, 154),
	"composer_title": Rect2(928, 238, 304, 80),
	"composer_input": Rect2(916, 320, 328, 244),
	"count": Rect2(928, 580, 304, 44),
	"status": Rect2(924, 632, 310, 42),
	"primary": Rect2(908, 680, 342, 86),
	"rail": Rect2(864, 246, 48, 496),
	"list_hit": Rect2(404, 214, 476, 554),
}
const OVERVIEW_RECTS := {
	"title": Rect2(194, 38, 320, 52),
	"close": Rect2(529, 39, 66, 66),
	"recent_title": Rect2(100, 151, 180, 34),
	"card_1_time": Rect2(84, 208, 445, 31),
	"card_1_body": Rect2(84, 248, 445, 96),
	"card_2_time": Rect2(84, 365, 445, 31),
	"card_2_body": Rect2(84, 405, 445, 96),
	"empty": Rect2(84, 248, 445, 96),
	"composer_title": Rect2(100, 536, 190, 35),
	"composer_input": Rect2(72, 598, 490, 166),
	"count": Rect2(74, 789, 490, 28),
	"status": Rect2(74, 822, 490, 28),
	"primary": Rect2(58, 858, 524, 72),
	"rail": Rect2(552, 210, 42, 304),
	"list_hit": Rect2(64, 204, 530, 314),
}

@export_enum("avatar", "overview") var presentation_mode := "avatar"

var _adapter: Node
var _contract_failure := false
var _contract_failure_message := ""
var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _current_revision := -1
var _layout_profile := "standard"
var _composition_kind := "flow"
var _layout_queued := false
var _internal_text_update := false
var _pending_draft_text := ""
var _draft_update_pending := false
var _pending_action_intent := ""
var _last_focus_identity := ""
var _last_feedback_identity := ""
var _history_page := 0
var _history_page_count := 1
var _history_page_size := 2
var _history_anchor_id := ""
var _history_swipe_tracking := false
var _history_swipe_start := Vector2.ZERO
var _items: Array = []
var _visible_item_ids: Array[String] = []
var _safe_insets := Rect2()

var _heading_font: FontVariation
var _button_font: FontVariation
var _metadata_font: FontVariation
var _draft_timer: Timer
var _feedback_timer: Timer
var _town_background: ColorRect
var _map_scrim: ColorRect
var _wide_root: Control
var _overview_root: Control
var _flow_shell: PanelContainer
var _flow_header: GridContainer
var _flow_main_grid: GridContainer
var _flow_main_scroll: ScrollContainer
var _flow_list_panel: PanelContainer
var _flow_composer_panel: PanelContainer
var _flow_cards: VBoxContainer
var _flow_list_summary: Label
var _overlay_scrim: ColorRect
var _dialog_component: Control
var _toast_component: Control
var _wide: Dictionary = {}
var _overview: Dictionary = {}
var _flow: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = PageTheme.create()
	_heading_font = PageTheme.load_heading_font()
	_button_font = PageTheme.load_button_font()
	_metadata_font = PageTheme.load_metadata_font()
	_build_interface()
	_build_timers()
	_refresh_from_adapter()
	resized.connect(_queue_responsive_layout)
	get_viewport().size_changed.connect(_queue_responsive_layout)
	_queue_responsive_layout()
	_render()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if request_back():
			get_viewport().set_input_as_handled()


func request_back() -> bool:
	var dialog := _render_data.get("dialog", {}) as Dictionary
	if bool(dialog.get("open", false)):
		return true
	if _has_pending_editor_text():
		if is_instance_valid(_draft_timer):
			_draft_timer.stop()
		_pending_draft_text = _current_editor_text()
		if not _request_action(
			"updateDraft",
			{"text": _pending_draft_text},
		):
			return true
	return _request_action("requestClose", {})


func _current_editor_text() -> String:
	var editor := _active_surface().get("editor") as TextEdit
	return editor.text if is_instance_valid(editor) else ""


func _has_pending_editor_text() -> bool:
	var composer := _render_data.get("composer", {}) as Dictionary
	return _current_editor_text() != String(composer.get("draftText", ""))


func bind_town_ui_adapter(adapter: Node) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	_adapter = adapter
	_contract_failure = false
	_contract_failure_message = ""
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	_current_revision = -1
	_pending_draft_text = ""
	_draft_update_pending = false
	_pending_action_intent = ""
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	if _adapter == null:
		_set_contract_failure(
			"正式 announcements ViewModel 尚未提供公告栏完整页面字段。"
		)
	else:
		_refresh_from_adapter()
		if _view_model.is_empty():
			_set_contract_failure(
				"正式 announcements ViewModel 尚未提供公告栏完整页面字段。"
			)
	_render()


func unbind_town_ui_adapter() -> void:
	bind_town_ui_adapter(null)


func apply_view_model(view_model: Dictionary) -> bool:
	var issues := _validate_complete_view_model(view_model)
	if not issues.is_empty():
		for issue: String in issues:
			push_error(issue)
		return false
	var incoming_revision := UiViewModel.revision(view_model)
	if _current_revision >= 0 and incoming_revision < _current_revision:
		return false

	var operation_status := UiViewModel.operation_status(view_model)
	var incoming_data := UiViewModel.data(view_model)
	var incoming_composer := incoming_data.get("composer", {}) as Dictionary
	if (
		_draft_update_pending
		and (
			not bool(incoming_composer.get("open", false))
			or String(incoming_composer.get("draftText", ""))
			== _pending_draft_text
		)
	):
		_draft_update_pending = false
	if (
		operation_status in [&"rejected", &"error"]
		and not _last_confirmed_data.is_empty()
	):
		_render_data = _last_confirmed_data.duplicate(true)
	else:
		_render_data = incoming_data.duplicate(true)
	if (
		operation_status in [&"idle", &"success"]
		and not incoming_data.is_empty()
	):
		_last_confirmed_data = incoming_data.duplicate(true)
	if _render_data.is_empty():
		_render_data = incoming_data.duplicate(true)

	_view_model = view_model.duplicate(true)
	_current_revision = incoming_revision
	_contract_failure = false
	_contract_failure_message = ""
	_pending_action_intent = ""
	if is_node_ready():
		_render()
	return true


func current_view_model() -> Dictionary:
	return _view_model.duplicate(true)


func current_revision() -> int:
	return _current_revision


func current_layout_profile() -> String:
	return _layout_profile


func current_presentation_mode() -> String:
	return presentation_mode


func apply_route_payload(payload: Dictionary) -> void:
	var requested_mode := str(payload.get("presentationMode", "")).strip_edges()
	if requested_mode.is_empty():
		requested_mode = str(payload.get("avatarMode", "")).strip_edges()
	var normalized := _normalize_presentation_mode(requested_mode)
	if normalized.is_empty() or normalized == presentation_mode:
		return
	presentation_mode = normalized
	if is_node_ready():
		_queue_responsive_layout()
		_render()


func _normalize_presentation_mode(value: String) -> String:
	match value.to_lower():
		"overview", "observer", "map", "town":
			return "overview"
		"avatar", "avatar_active", "avatar_descent":
			return "avatar"
		_:
			return ""


func debug_set_history_page(page_index: int) -> void:
	_set_history_page(page_index)


func debug_request_action(
	action_key: String,
	payload: Dictionary = {}
) -> bool:
	return _request_action(action_key, payload)


func runtime_gate_snapshot() -> Dictionary:
	var text_slots: Array = []
	var touch_targets: Array = []
	var regions: Array = []
	for node: Node in get_tree().get_nodes_in_group(
		"bulletin_board_text_slot"
	):
		if not is_ancestor_of(node):
			continue
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var text_control := _gate_text_source(control)
		var font := text_control.get_theme_font("font")
		var font_size := text_control.get_theme_font_size("font_size")
		var text_value := _control_text(text_control)
		text_slots.append({
			"id": str(control.get_meta("gate_text_id", control.name)),
			"text": text_value,
			"rect": _rect_to_array(
				Rect2(control.global_position, control.size)
			),
			"layoutRect": _rect_to_array(
				Rect2(text_control.global_position, text_control.size)
			),
			"fontSize": font_size,
			"fontPath": _gate_font_path(font),
			"glyphSpacing": _gate_glyph_spacing(font),
			"outlineSize": text_control.get_theme_constant(
				"outline_size"
			),
			"lineHeight": font.get_height(font_size),
			"textWidth": font.get_string_size(
				text_value,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size
			).x,
			"wrap": (
				(text_control is Label and (
					(text_control as Label).autowrap_mode
					!= TextServer.AUTOWRAP_OFF
				))
				or text_control is TextEdit
			),
			"maxLines": (
				(text_control as Label).max_lines_visible
				if text_control is Label
				else 0
			),
		})
	for node: Node in get_tree().get_nodes_in_group(
		"bulletin_board_touch_target"
	):
		if not is_ancestor_of(node):
			continue
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		touch_targets.append({
			"id": str(control.get_meta("gate_touch_id", control.name)),
			"rect": _rect_to_array(
				Rect2(control.global_position, control.size)
			),
			"focusMode": control.focus_mode,
			"disabled": (
				(control as BaseButton).disabled
				if control is BaseButton
				else false
			),
		})
	for node: Node in get_tree().get_nodes_in_group(
		"bulletin_board_region"
	):
		if not is_ancestor_of(node):
			continue
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		regions.append({
			"id": str(control.get_meta("gate_region_id", control.name)),
			"rect": _rect_to_array(
				Rect2(control.global_position, control.size)
			),
		})
	var active_surface := _active_surface()
	var active_status := active_surface.get("status") as Label
	var active_count := active_surface.get("count") as Label
	var active_editor := active_surface.get("editor") as TextEdit
	return {
		"scope": str(_view_model.get("scope", "")),
		"layoutProfile": _layout_profile,
		"compositionKind": _composition_kind,
		"presentationMode": presentation_mode,
		"revision": _current_revision,
		"sourceMode": (
				"town_ui_adapter_contract_error"
				if _contract_failure
				else "town_ui_adapter"
		),
		"source": str(_render_data.get("source", "")),
		"capabilityMode": str(
			_render_data.get("capabilityMode", "")
		),
		"formalReady": bool(
			_render_data.get("formalReady", false)
		),
		"operationStatus": (
			"disabled"
			if _contract_failure
			else str(UiViewModel.operation_status(_view_model))
		),
		"wholePageScale": [scale.x, scale.y],
		"viewportRect": _rect_to_array(get_viewport_rect()),
		"boardRect": _rect_to_array(_active_board_rect()),
		"safeInsets": [
			_safe_insets.position.x,
			_safe_insets.position.y,
			_safe_insets.size.x,
			_safe_insets.size.y,
		],
		"mainColumns": _flow_main_grid.columns,
		"historyPage": _history_page,
		"historyPageCount": _history_page_count,
		"historyPageSize": _history_page_size,
		"visibleAnnouncementIds": _visible_item_ids.duplicate(),
		"dialogVisible": _dialog_component.visible,
		"feedbackVisible": _toast_component.visible,
		"mapBackdropVisible": _town_background.visible,
		"mapScrimVisible": _map_scrim.visible,
		"contractFailure": _contract_failure,
		"statusText": active_status.text if active_status != null else "",
		"characterCountText": (
			active_count.text if active_count != null else ""
		),
		"composerText": (
			active_editor.text if active_editor != null else ""
		),
		"primaryActionKey": str(
			(active_surface.get("primary") as Button).get_meta(
				"action_key",
				""
			)
		),
		"minimumSizes": {
			"shell": _flow_shell.get_combined_minimum_size(),
			"header": _flow_header.get_combined_minimum_size(),
			"mainGrid": _flow_main_grid.get_combined_minimum_size(),
			"historyPanel": _flow_list_panel.get_combined_minimum_size(),
			"composerPanel": _flow_composer_panel.get_combined_minimum_size(),
			"editor": (
				(_flow.get("editor") as Control)
					.get_combined_minimum_size()
			),
		},
		"textSlots": text_slots,
		"touchTargets": touch_targets,
		"regions": regions,
		"borderOwnership": _border_ownership_snapshot(),
	}


func _build_interface() -> void:
	_town_background = ColorRect.new()
	_town_background.name = "BulletinBackdrop"
	_town_background.color = Color("173725")
	_town_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_town_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_town_background)

	_map_scrim = ColorRect.new()
	_map_scrim.name = "MapScrim"
	_map_scrim.color = Color(0.08, 0.055, 0.03, 0.46)
	_map_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_map_scrim)

	_build_wide_surface()
	_build_overview_surface()
	_build_flow_surface()
	_build_feedback_surfaces()


func _build_wide_surface() -> void:
	_wide_root = Control.new()
	_wide_root.name = "ApprovedWideComposition"
	_wide_root.size = APPROVED_SOURCE_SIZE
	_register_region(_wide_root, "wide_board")
	add_child(_wide_root)

	var source := TextureRect.new()
	source.name = "ApprovedNoTextSource"
	source.texture = APPROVED_SOURCE
	source.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	source.stretch_mode = TextureRect.STRETCH_KEEP
	source.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	source.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source.position = Vector2.ZERO
	source.size = APPROVED_SOURCE_SIZE
	_wide_root.add_child(source)
	_wide["source"] = source

	_wide["title"] = _place_label(
		_wide_root,
		"WideTitle",
		WIDE_RECTS["title"],
		38,
		PageTheme.INK,
		"wide_title",
		1,
		HORIZONTAL_ALIGNMENT_CENTER,
		true
	)
	_wide["newer"] = _place_button(
		_wide_root,
		"WideNewer",
		"较新",
		WIDE_RECTS["newer"],
		"wood",
		"wide_newer",
		26
	)
	_wide["page"] = _place_label(
		_wide_root,
		"WidePage",
		WIDE_RECTS["page"],
		24,
		PageTheme.INK_MUTED,
		"wide_page",
		1,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_apply_metadata_font(_wide["page"] as Label)
	_wide["older"] = _place_button(
		_wide_root,
		"WideOlder",
		"较早",
		WIDE_RECTS["older"],
		"wood",
		"wide_older",
		26
	)
	_wide["close"] = _place_button(
		_wide_root,
		"WideClose",
		"返回",
		WIDE_RECTS["close"],
		"wood",
		"wide_close",
		26
	)
	(_wide["newer"] as Button).pressed.connect(_on_newer_pressed)
	(_wide["older"] as Button).pressed.connect(_on_older_pressed)
	(_wide["close"] as Button).pressed.connect(
		_request_action.bind("requestClose", {})
	)

	var list_hit := Control.new()
	list_hit.name = "WideHistoryInput"
	list_hit.position = (WIDE_RECTS["list_hit"] as Rect2).position
	list_hit.size = (WIDE_RECTS["list_hit"] as Rect2).size
	list_hit.mouse_filter = Control.MOUSE_FILTER_PASS
	list_hit.gui_input.connect(_on_history_gui_input)
	_wide_root.add_child(list_hit)
	_wide["list_hit"] = list_hit

	var cards: Array[Dictionary] = []
	for index: int in range(2):
		var time_rect := (
			WIDE_RECTS["card_1_time"]
			if index == 0
			else WIDE_RECTS["card_2_time"]
		) as Rect2
		var body_rect := (
			WIDE_RECTS["card_1_body"]
			if index == 0
			else WIDE_RECTS["card_2_body"]
		) as Rect2
		var time_label := _place_label(
			_wide_root,
			"WideCard%dTime" % (index + 1),
			time_rect,
			20,
			PageTheme.INK_MUTED,
			"wide_card_%d_time" % (index + 1),
			1,
			HORIZONTAL_ALIGNMENT_LEFT
		)
		_apply_metadata_font(time_label)
		var body_label := _place_label(
			_wide_root,
			"WideCard%dBody" % (index + 1),
			body_rect,
			25,
			PageTheme.INK,
			"wide_card_%d_body" % (index + 1),
			3,
			HORIZONTAL_ALIGNMENT_LEFT
		)
		body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		cards.append({
			"time": time_label,
			"body": body_label,
		})
	_wide["cards"] = cards
	_wide["empty"] = _place_label(
		_wide_root,
		"WideEmpty",
		WIDE_RECTS["empty"],
		25,
		PageTheme.INK_MUTED,
		"wide_empty",
		3,
		HORIZONTAL_ALIGNMENT_CENTER
	)

	_wide["composer_title"] = _place_label(
		_wide_root,
		"WideComposerTitle",
		WIDE_RECTS["composer_title"],
		30,
		PageTheme.INK,
		"wide_composer_title",
		1,
		HORIZONTAL_ALIGNMENT_LEFT,
		true
	)
	_wide["editor"] = _place_editor(
		_wide_root,
		"WideEditor",
		WIDE_RECTS["composer_input"],
		"wide_composer_input"
	)
	_style_composite_editor(_wide["editor"] as TextEdit)
	(_wide["editor"] as TextEdit).add_theme_font_size_override(
		"font_size",
		21
	)
	_wide["count"] = _place_padded_label(
		_wide_root,
		"WideCount",
		WIDE_RECTS["count"],
		20,
		PageTheme.INK_MUTED,
		"wide_character_count",
		1,
		HORIZONTAL_ALIGNMENT_RIGHT,
		12,
		44,
		0
	)
	_apply_metadata_font(_wide["count"] as Label)
	_wide["status"] = _place_padded_label(
		_wide_root,
		"WideStatus",
		WIDE_RECTS["status"],
		18,
		PageTheme.INK_MUTED,
		"wide_status",
		2,
		HORIZONTAL_ALIGNMENT_CENTER,
		10,
		42,
		0
	)
	_apply_metadata_font(_wide["status"] as Label)
	_wide["primary"] = _place_button(
		_wide_root,
		"WidePrimary",
		"发布公告",
		WIDE_RECTS["primary"],
		"primary",
		"wide_primary",
		32
	)
	_style_composite_button(_wide["primary"] as Button)
	(_wide["primary"] as Button).pressed.connect(
		_on_primary_pressed.bind(_wide["primary"] as Button)
	)
	var rail := HistoryRail.new() as BulletinBoardHistoryRail
	rail.name = "WideHistoryRail"
	rail.position = (WIDE_RECTS["rail"] as Rect2).position
	rail.size = (WIDE_RECTS["rail"] as Rect2).size
	rail.page_requested.connect(_set_history_page)
	_wide_root.add_child(rail)
	_wide["rail"] = rail


func _build_overview_surface() -> void:
	_overview_root = Control.new()
	_overview_root.name = "ApprovedOverviewSidePanel"
	_overview_root.size = OVERVIEW_SOURCE_SIZE
	_overview_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_register_region(_overview_root, "overview_side_panel")
	add_child(_overview_root)

	var source := TextureRect.new()
	source.name = "ApprovedOverviewNoTextSource"
	source.texture = OVERVIEW_SOURCE
	source.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	source.stretch_mode = TextureRect.STRETCH_SCALE
	source.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	source.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source.position = Vector2.ZERO
	source.size = OVERVIEW_SOURCE_SIZE
	_overview_root.add_child(source)
	_overview["source"] = source

	_overview["title"] = _place_label(
		_overview_root,
		"OverviewTitle",
		OVERVIEW_RECTS["title"],
		30,
		PageTheme.INK,
		"overview_title",
		1,
		HORIZONTAL_ALIGNMENT_CENTER,
		true
	)
	_overview["close"] = _place_hit_button(
		_overview_root,
		"OverviewClose",
		OVERVIEW_RECTS["close"],
		"overview_close",
		"关闭公告栏"
	)
	(_overview["close"] as Button).pressed.connect(
		_request_action.bind("requestClose", {})
	)
	_overview["recent_title"] = _place_label(
		_overview_root,
		"OverviewRecentTitle",
		OVERVIEW_RECTS["recent_title"],
		18,
		PageTheme.INK,
		"overview_recent_title",
		1,
		HORIZONTAL_ALIGNMENT_LEFT
	)

	var list_hit := Control.new()
	list_hit.name = "OverviewHistoryInput"
	list_hit.position = (OVERVIEW_RECTS["list_hit"] as Rect2).position
	list_hit.size = (OVERVIEW_RECTS["list_hit"] as Rect2).size
	list_hit.mouse_filter = Control.MOUSE_FILTER_PASS
	list_hit.gui_input.connect(_on_history_gui_input)
	_overview_root.add_child(list_hit)
	_overview["list_hit"] = list_hit

	var cards: Array[Dictionary] = []
	for index: int in range(2):
		var time_rect := (
			OVERVIEW_RECTS["card_1_time"]
			if index == 0
			else OVERVIEW_RECTS["card_2_time"]
		) as Rect2
		var body_rect := (
			OVERVIEW_RECTS["card_1_body"]
			if index == 0
			else OVERVIEW_RECTS["card_2_body"]
		) as Rect2
		var time_label := _place_label(
			_overview_root,
			"OverviewCard%dTime" % (index + 1),
			time_rect,
			14,
			PageTheme.INK_MUTED,
			"overview_card_%d_time" % (index + 1),
			1,
			HORIZONTAL_ALIGNMENT_LEFT
		)
		_apply_metadata_font(time_label)
		var body_label := _place_label(
			_overview_root,
			"OverviewCard%dBody" % (index + 1),
			body_rect,
			19,
			PageTheme.INK,
			"overview_card_%d_body" % (index + 1),
			3,
			HORIZONTAL_ALIGNMENT_LEFT
		)
		body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		cards.append({
			"time": time_label,
			"body": body_label,
		})
	_overview["cards"] = cards
	_overview["empty"] = _place_label(
		_overview_root,
		"OverviewEmpty",
		OVERVIEW_RECTS["empty"],
		19,
		PageTheme.INK_MUTED,
		"overview_empty",
		3,
		HORIZONTAL_ALIGNMENT_CENTER
	)

	_overview["composer_title"] = _place_label(
		_overview_root,
		"OverviewComposerTitle",
		OVERVIEW_RECTS["composer_title"],
		18,
		PageTheme.INK,
		"overview_composer_title",
		1,
		HORIZONTAL_ALIGNMENT_LEFT,
		true
	)
	_overview["editor"] = _place_editor(
		_overview_root,
		"OverviewEditor",
		OVERVIEW_RECTS["composer_input"],
		"overview_composer_input"
	)
	_style_composite_editor(_overview["editor"] as TextEdit)
	(_overview["editor"] as TextEdit).add_theme_font_size_override(
		"font_size",
		19
	)
	_overview["count"] = _place_padded_label(
		_overview_root,
		"OverviewCount",
		OVERVIEW_RECTS["count"],
		14,
		PageTheme.INK_MUTED,
		"overview_character_count",
		1,
		HORIZONTAL_ALIGNMENT_RIGHT,
		8,
		28,
		0
	)
	_apply_metadata_font(_overview["count"] as Label)
	_overview["status"] = _place_padded_label(
		_overview_root,
		"OverviewStatus",
		OVERVIEW_RECTS["status"],
		13,
		PageTheme.INK_MUTED,
		"overview_status",
		2,
		HORIZONTAL_ALIGNMENT_CENTER,
		8,
		28,
		0
	)
	_apply_metadata_font(_overview["status"] as Label)
	_overview["primary"] = _place_button(
		_overview_root,
		"OverviewPrimary",
		"发布公告",
		OVERVIEW_RECTS["primary"],
		"primary",
		"overview_primary",
		28
	)
	_style_composite_button(_overview["primary"] as Button)
	(_overview["primary"] as Button).pressed.connect(
		_on_primary_pressed.bind(_overview["primary"] as Button)
	)

	var rail := HistoryRail.new() as BulletinBoardHistoryRail
	rail.name = "OverviewHistoryRail"
	rail.position = (OVERVIEW_RECTS["rail"] as Rect2).position
	rail.size = (OVERVIEW_RECTS["rail"] as Rect2).size
	rail.modulate = Color(1.0, 1.0, 1.0, 0.0)
	rail.page_requested.connect(_set_history_page)
	_overview_root.add_child(rail)
	_overview["rail"] = rail


func _build_flow_surface() -> void:
	_flow_shell = PanelContainer.new()
	_flow_shell.name = "ResponsiveBoard"
	_flow_shell.add_theme_stylebox_override(
		"panel",
		PageTheme.board_panel()
	)
	_flow_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	_register_region(_flow_shell, "responsive_board")
	add_child(_flow_shell)

	var page := VBoxContainer.new()
	page.name = "ResponsivePage"
	page.add_theme_constant_override("separation", 16)
	_flow_shell.add_child(page)

	_flow_header = GridContainer.new()
	_flow_header.name = "ResponsiveHeader"
	_flow_header.columns = 2
	_flow_header.add_theme_constant_override("h_separation", 16)
	_flow_header.add_theme_constant_override("v_separation", 12)
	page.add_child(_flow_header)
	_flow["title"] = _make_label(
		"公告栏",
		48,
		PageTheme.INK,
		"flow_title",
		1,
		true
	)
	(_flow["title"] as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow_header.add_child(_flow["title"])
	_flow["close"] = _make_button(
		"返回",
		"wood",
		"flow_close",
		32
	)
	(_flow["close"] as Button).custom_minimum_size = Vector2(132, 68)
	(_flow["close"] as Button).pressed.connect(
		_request_action.bind("requestClose", {})
	)
	_flow_header.add_child(_flow["close"])

	var history_header := HBoxContainer.new()
	history_header.add_theme_constant_override("separation", 10)
	page.add_child(history_header)
	_flow["newer"] = _make_button(
		"较新",
		"wood",
		"flow_newer"
	)
	(_flow["newer"] as Button).pressed.connect(_on_newer_pressed)
	history_header.add_child(_flow["newer"])
	_flow["page"] = _make_label(
		"1 / 1",
		28,
		PageTheme.INK_MUTED,
		"flow_page",
		1
	)
	_apply_metadata_font(_flow["page"] as Label)
	(_flow["page"] as Label).horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	(_flow["page"] as Label).size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	history_header.add_child(_flow["page"])
	_flow["older"] = _make_button(
		"较早",
		"wood",
		"flow_older"
	)
	(_flow["older"] as Button).pressed.connect(_on_older_pressed)
	history_header.add_child(_flow["older"])

	_flow_main_scroll = ScrollContainer.new()
	_flow_main_scroll.name = "ResponsiveMainScroll"
	_flow_main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flow_main_scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	page.add_child(_flow_main_scroll)
	_flow_main_grid = GridContainer.new()
	_flow_main_grid.name = "ResponsiveMainGrid"
	_flow_main_grid.columns = 2
	_flow_main_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow_main_grid.add_theme_constant_override("h_separation", 20)
	_flow_main_grid.add_theme_constant_override("v_separation", 20)
	_flow_main_scroll.add_child(_flow_main_grid)

	_flow_list_panel = PanelContainer.new()
	_flow_list_panel.name = "HistoryPanel"
	_flow_list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flow_list_panel.add_theme_stylebox_override(
		"panel",
		PageTheme.section_panel(PageTheme.WOOD_LIGHT, 16)
	)
	_register_region(_flow_list_panel, "flow_history_panel")
	_flow_main_grid.add_child(_flow_list_panel)
	var history_body := VBoxContainer.new()
	history_body.add_theme_constant_override("separation", 12)
	_flow_list_panel.add_child(history_body)
	var history_title := _make_label(
		"以前的公告",
		32,
		PageTheme.INK,
		"flow_history_title",
		1,
		true
	)
	history_body.add_child(history_title)
	_flow_list_summary = _make_label(
		"",
		24,
		PageTheme.INK_MUTED,
		"flow_history_summary",
		2
	)
	_apply_metadata_font(_flow_list_summary)
	history_body.add_child(_flow_list_summary)
	var cards_and_rail := HBoxContainer.new()
	cards_and_rail.name = "CardsAndHistoryRail"
	cards_and_rail.add_theme_constant_override("separation", 12)
	cards_and_rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_and_rail.gui_input.connect(_on_history_gui_input)
	history_body.add_child(cards_and_rail)
	_flow_cards = VBoxContainer.new()
	_flow_cards.name = "AnnouncementCards"
	_flow_cards.add_theme_constant_override("separation", 12)
	_flow_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_and_rail.add_child(_flow_cards)
	var flow_rail := HistoryRail.new() as BulletinBoardHistoryRail
	flow_rail.name = "ResponsiveHistoryRail"
	flow_rail.custom_minimum_size = Vector2(48, 260)
	flow_rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	flow_rail.page_requested.connect(_set_history_page)
	cards_and_rail.add_child(flow_rail)
	_flow["rail"] = flow_rail

	_flow_composer_panel = PanelContainer.new()
	_flow_composer_panel.name = "ComposerPanel"
	_flow_composer_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow_composer_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flow_composer_panel.add_theme_stylebox_override(
		"panel",
		PageTheme.section_panel(PageTheme.TERRACOTTA, 16)
	)
	_register_region(_flow_composer_panel, "flow_composer_panel")
	_flow_main_grid.add_child(_flow_composer_panel)
	var composer_body := VBoxContainer.new()
	composer_body.add_theme_constant_override("separation", 12)
	_flow_composer_panel.add_child(composer_body)
	_flow["composer_title"] = _make_label(
		"写一张公告（发布者：旅行者）",
		48,
		PageTheme.INK,
		"flow_composer_title",
		1,
		true
	)
	composer_body.add_child(_flow["composer_title"])
	_flow["editor"] = _make_editor("FlowEditor", "flow_composer_input")
	(_flow["editor"] as TextEdit).custom_minimum_size = Vector2(0, 196)
	(_flow["editor"] as TextEdit).size_flags_vertical = Control.SIZE_EXPAND_FILL
	composer_body.add_child(_flow["editor"])
	_flow["count"] = _make_label(
		"0 / 0 字",
		28,
		PageTheme.INK_MUTED,
		"flow_character_count",
		1
	)
	_apply_metadata_font(_flow["count"] as Label)
	(_flow["count"] as Label).horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	composer_body.add_child(_flow["count"])
	_flow["validation"] = _make_label(
		"",
		24,
		PageTheme.ERROR_DARK,
		"flow_validation",
		2
	)
	_apply_metadata_font(_flow["validation"] as Label)
	composer_body.add_child(_flow["validation"])
	var status_panel := PanelContainer.new()
	status_panel.name = "OperationStatus"
	status_panel.add_theme_stylebox_override(
		"panel",
		PageTheme.status_style("idle")
	)
	composer_body.add_child(status_panel)
	_flow["status_panel"] = status_panel
	_flow["status"] = _make_label(
		"小镇时间照常流动",
		24,
		PageTheme.INK_MUTED,
		"flow_status",
		3
	)
	_apply_metadata_font(_flow["status"] as Label)
	status_panel.add_child(_flow["status"])
	_flow["primary"] = _make_button(
		"发布公告",
		"primary",
		"flow_primary",
		48
	)
	(_flow["primary"] as Button).custom_minimum_size = Vector2(260, 86)
	(_flow["primary"] as Button).pressed.connect(
		_on_primary_pressed.bind(_flow["primary"] as Button)
	)
	composer_body.add_child(_flow["primary"])


func _build_feedback_surfaces() -> void:
	_overlay_scrim = ColorRect.new()
	_overlay_scrim.name = "FeedbackScrim"
	_overlay_scrim.color = Color(0.08, 0.055, 0.03, 0.68)
	_overlay_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_scrim.visible = false
	add_child(_overlay_scrim)

	_dialog_component = DIALOG_SCENE.instantiate() as Control
	_dialog_component.name = "DraftConfirmation"
	_dialog_component.visible = false
	_dialog_component.action_requested.connect(
		_on_common_feedback_action.bind("dialog")
	)
	_dialog_component.dismiss_requested.connect(
		_on_common_feedback_dismissed.bind("dialog")
	)
	add_child(_dialog_component)

	_toast_component = TOAST_SCENE.instantiate() as Control
	_toast_component.name = "PublishSuccess"
	_toast_component.visible = false
	_toast_component.action_requested.connect(
		_on_common_feedback_action.bind("toast")
	)
	_toast_component.dismiss_requested.connect(
		_on_common_feedback_dismissed.bind("toast")
	)
	add_child(_toast_component)


func _build_timers() -> void:
	_draft_timer = Timer.new()
	_draft_timer.name = "DraftIntentDebounce"
	_draft_timer.one_shot = true
	_draft_timer.wait_time = DRAFT_DEBOUNCE_SECONDS
	_draft_timer.timeout.connect(_flush_draft_intent)
	add_child(_draft_timer)
	_feedback_timer = Timer.new()
	_feedback_timer.name = "FeedbackDismissTimer"
	_feedback_timer.one_shot = true
	_feedback_timer.timeout.connect(
		_request_action.bind("dismissFeedback", {})
	)
	add_child(_feedback_timer)


func _render() -> void:
	if not is_node_ready():
		return
	var data := (
		_contract_failure_data()
		if _contract_failure
		else _render_data
	)
	var panel := data.get("panel", {}) as Dictionary
	var panel_open := bool(panel.get("open", true))
	var items_value: Variant = data.get("items", [])
	_items = (
		(items_value as Array).duplicate(true)
		if items_value is Array
		else []
	)
	_prepare_history_page()
	var page_items := _page_items()
	_visible_item_ids.clear()
	for item_value: Variant in page_items:
		if item_value is Dictionary:
			_visible_item_ids.append(
				str((item_value as Dictionary).get(
					"announcement_id",
					""
				))
			)

	var fixed_art_fits := (
		_layout_profile == "wide"
		and (
			_overview_page_fits(page_items)
			if presentation_mode == "overview"
			else _wide_page_fits(page_items)
		)
	)
	var wants_overview_side := (
		presentation_mode == "overview"
		and fixed_art_fits
		and _overview_side_fits()
	)
	var wants_wide_art := (
		presentation_mode == "avatar"
		and fixed_art_fits
	)
	_composition_kind = (
		"side_panel"
		if wants_overview_side
		else ("wide_art" if wants_wide_art else "flow")
	)
	_wide_root.visible = panel_open and wants_wide_art
	_overview_root.visible = panel_open and wants_overview_side
	_flow_shell.visible = panel_open and not (
		wants_wide_art or wants_overview_side
	)
	_town_background.visible = not wants_overview_side
	_map_scrim.visible = not wants_overview_side
	_map_scrim.color = (
		Color(0.035, 0.055, 0.035, 0.82)
		if wants_wide_art
		else Color(0.08, 0.055, 0.03, 0.46)
	)
	# 三套 surface 每次只有一套可见，只渲染当前这一套。
	if _wide_root.visible:
		_render_surface(_wide, data, page_items, true)
	if _overview_root.visible:
		_render_surface(_overview, data, page_items, true)
	if _flow_shell.visible:
		_render_surface(_flow, data, page_items, false)
		_rebuild_flow_cards(page_items)
	_render_feedback(data)
	_request_semantic_focus(panel)


func _render_surface(
	surface: Dictionary,
	data: Dictionary,
	page_items: Array,
	is_wide: bool
) -> void:
	var panel := data.get("panel", {}) as Dictionary
	var composer := data.get("composer", {}) as Dictionary
	var empty_state := data.get("emptyState", {}) as Dictionary
	var title := surface.get("title") as Label
	title.text = str(panel.get("title", "公告栏"))
	var composer_title := surface.get("composer_title") as Label
	composer_title.text = "写一张公告（发布者：旅行者）"
	var recent_title := surface.get("recent_title") as Label
	if recent_title != null:
		recent_title.text = "最近公告"
	var page_label := surface.get("page") as Label
	if page_label != null:
		page_label.text = (
			"0 / 0"
			if _items.is_empty()
			else "%d / %d" % [_history_page + 1, _history_page_count]
		)
	var newer := surface.get("newer") as Button
	var older := surface.get("older") as Button
	if newer != null:
		newer.disabled = _items.is_empty() or _history_page <= 0
	if older != null:
		older.disabled = (
			_items.is_empty()
			or _history_page >= _history_page_count - 1
		)
	var rail := surface.get("rail") as BulletinBoardHistoryRail
	rail.set_page_state(_history_page, _history_page_count)

	if is_wide:
		var cards := surface.get("cards") as Array
		for index: int in range(cards.size()):
			var card := cards[index] as Dictionary
			var time_label := card["time"] as Label
			var body_label := card["body"] as Label
			var has_item := index < page_items.size()
			time_label.visible = has_item
			body_label.visible = has_item
			if has_item:
				var item := page_items[index] as Dictionary
				time_label.text = _announcement_time_copy(item)
				body_label.text = str(item.get("text", ""))
		var empty_label := surface.get("empty") as Label
		empty_label.visible = _items.is_empty()
		empty_label.text = "%s\n%s" % [
			str(empty_state.get("title", "公告栏还是空的")),
			str(empty_state.get(
				"message",
				"发布一条公告，让全镇都知道。"
			)),
		]

	var editor := surface.get("editor") as TextEdit
	var composer_open := bool(composer.get("open", false))
	var operation_status := (
		"disabled"
		if _contract_failure
		else str(UiViewModel.operation_status(_view_model))
	)
	var dialog := data.get("dialog", {}) as Dictionary
	var feedback := data.get("feedback", {}) as Dictionary
	var editor_enabled := (
		composer_open
		and _action_enabled("updateDraft")
		and operation_status != "loading"
		and not bool(dialog.get("open", false))
		and not (
			bool(feedback.get("visible", false))
			and bool(feedback.get("blocksInput", false))
		)
	)
	_internal_text_update = true
	var draft_text := (
		_pending_draft_text
		if _draft_update_pending and composer_open
		else str(composer.get("draftText", ""))
	)
	if editor.text != draft_text:
		_set_editor_text_preserving_caret(editor, draft_text)
	editor.editable = editor_enabled
	editor.placeholder_text = (
		"把想告诉全镇的事情写在这里……"
		if composer_open
		else "先选择“写一张公告”"
	)
	_internal_text_update = false
	var count := int(composer.get("characterCount", 0))
	var limit := int(composer.get("characterLimit", 0))
	var remaining := int(composer.get("remainingCount", 0))
	var count_label := surface.get("count") as Label
	count_label.text = (
		"%d / %d 字" % [count, limit]
		if limit > 0
		else "字数规则未就绪"
	)
	count_label.add_theme_color_override(
		"font_color",
		PageTheme.ERROR_DARK if remaining < 0 else PageTheme.INK_MUTED
	)
	var validation_code := str(composer.get("validationCode", ""))
	var validation_copy := str(VALIDATION_COPY.get(
		validation_code,
		"暂时无法发布这份公告。" if not validation_code.is_empty() else ""
	))
	if surface.has("validation"):
		var validation := surface.get("validation") as Label
		validation.visible = not validation_copy.is_empty()
		validation.text = validation_copy

	var status_label := surface.get("status") as Label
	status_label.text = _status_copy(operation_status, validation_copy)
	status_label.add_theme_color_override(
		"font_color",
		_status_color(operation_status)
	)
	if surface.has("status_panel"):
		(surface.get("status_panel") as PanelContainer).add_theme_stylebox_override(
			"panel",
			PageTheme.status_style(operation_status)
		)

	var primary := surface.get("primary") as Button
	var action_key := "openComposer"
	var primary_text := "写一张公告"
	if composer_open:
		action_key = "publish"
		primary_text = "发布公告"
	if operation_status == "loading":
		primary_text = "正在发布……"
	if operation_status == "error" and _action_enabled("retry"):
		action_key = "retry"
		primary_text = "重试发布"
	primary.set_meta("action_key", action_key)
	primary.text = primary_text
	primary.disabled = not _action_enabled(action_key)
	var action := UiViewModel.action(_view_model, action_key)
	primary.tooltip_text = UiViewModel.player_reason(
		UiViewModel.disabled_reason(action)
	)

	var close_button := surface.get("close") as Button
	close_button.disabled = not _action_enabled("requestClose")
	close_button.tooltip_text = UiViewModel.player_reason(
		UiViewModel.disabled_reason(
			UiViewModel.action(_view_model, "requestClose")
		)
	)


func _render_feedback(data: Dictionary) -> void:
	var dialog := data.get("dialog", {}) as Dictionary
	var feedback := data.get("feedback", {}) as Dictionary
	var dialog_open := bool(dialog.get("open", false))
	var feedback_visible := bool(feedback.get("visible", false))
	_dialog_component.visible = dialog_open
	_toast_component.visible = feedback_visible
	_overlay_scrim.visible = (
		dialog_open
		or (
			feedback_visible
			and bool(feedback.get("blocksInput", false))
		)
	)
	if dialog_open:
		_dialog_component.call(
			"configure",
			_dialog_view_model(dialog),
			"dialog"
		)
	if feedback_visible:
		_toast_component.call(
			"configure",
			_toast_view_model(feedback),
			"toast"
		)
		var feedback_identity := "%d|%s|%s" % [
			_current_revision,
			UiViewModel.operation_request_id(_view_model),
			str(feedback.get("kind", "")),
		]
		if feedback_identity != _last_feedback_identity:
			_last_feedback_identity = feedback_identity
			var duration_ms := int(feedback.get("durationMs", 0))
			if duration_ms > 0 and _action_enabled("dismissFeedback"):
				_feedback_timer.start(float(duration_ms) / 1000.0)
	else:
		_last_feedback_identity = ""
		_feedback_timer.stop()


func _dialog_view_model(dialog: Dictionary) -> Dictionary:
	var snapshot := _view_model.duplicate(true)
	var data := (snapshot.get("data", {}) as Dictionary).duplicate(true)
	data["feedback"] = {
		"visible": true,
		"component": "confirmation_dialog",
		"tone": "warning",
		"title": str(dialog.get("title", "公告还没有发布")),
		"message": str(dialog.get(
			"message",
			"要继续编辑，还是放弃这份草稿？"
		)),
		"blocking": true,
	}
	snapshot["data"] = data
	var actions := {}
	actions["continueEditing"] = UiViewModel.action(
		_view_model,
		"continueEditing"
	)
	actions["discard"] = UiViewModel.action(
		_view_model,
		"discardDraft"
	)
	snapshot["actions"] = actions
	return snapshot


func _toast_view_model(feedback: Dictionary) -> Dictionary:
	var snapshot := _view_model.duplicate(true)
	var data := (snapshot.get("data", {}) as Dictionary).duplicate(true)
	data["feedback"] = {
		"visible": true,
		"component": "toast",
		"tone": "success",
		"title": str(feedback.get("title", "你发布了公告")),
		"message": str(feedback.get("message", "")),
		"blocking": bool(feedback.get("blocksInput", false)),
	}
	snapshot["data"] = data
	snapshot["actions"] = {
		"dismiss": UiViewModel.action(_view_model, "dismissFeedback"),
	}
	return snapshot


func _rebuild_flow_cards(page_items: Array) -> void:
	UiNodeRetirement.retire_children(_flow_cards)
	_flow_list_summary.visible = (
		_layout_profile == "portrait"
		and bool(
			(_render_data.get("composer", {}) as Dictionary).get(
				"softKeyboardVisible",
				false
			)
		)
	)
	if _flow_list_summary.visible:
		_flow_list_summary.text = "已收录 %d 条公告；关闭键盘后可继续浏览。" % _items.size()
		return
	if _items.is_empty():
		var empty_state := _render_data.get("emptyState", {}) as Dictionary
		var empty := _make_label(
			"%s\n%s" % [
				str(empty_state.get("title", "公告栏还是空的")),
				str(empty_state.get(
					"message",
					"发布一条公告，让全镇都知道。"
				)),
			],
			32,
			PageTheme.INK_MUTED,
			"flow_empty",
			5
		)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_flow_cards.add_child(empty)
		return
	for index: int in range(page_items.size()):
		var item := page_items[index] as Dictionary
		var card := PanelContainer.new()
		card.name = "AnnouncementCard%d" % (index + 1)
		card.add_theme_stylebox_override(
			"panel",
			PageTheme.card_panel()
		)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.set_meta(
			"announcement_id",
			str(item.get("announcement_id", ""))
		)
		_flow_cards.add_child(card)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 8)
		card.add_child(content)
		var time_label := _make_label(
			_announcement_time_copy(item),
			24,
			PageTheme.INK_MUTED,
			"flow_card_%d_time" % (index + 1),
			2
		)
		_apply_metadata_font(time_label)
		content.add_child(time_label)
		var body_label := _make_label(
			str(item.get("text", "")),
			32,
			PageTheme.INK,
			"flow_card_%d_body" % (index + 1),
			0
		)
		body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		content.add_child(body_label)


func _announcement_time_copy(item: Dictionary) -> String:
	var publisher := String(item.get("publisherLabel", "")).strip_edges()
	var time := String(item.get("timeLabel", ""))
	return "%s · %s" % [publisher, time] if not publisher.is_empty() else time


func _prepare_history_page() -> void:
	_history_page_size = 1 if _layout_profile == "portrait" else 2
	_history_page_count = maxi(
		1,
		int(ceil(float(_items.size()) / float(_history_page_size)))
	)
	if not _history_anchor_id.is_empty():
		var anchor_index := _index_of_announcement(_history_anchor_id)
		if anchor_index >= 0:
			_history_page = anchor_index / _history_page_size
	_history_page = clampi(
		_history_page,
		0,
		_history_page_count - 1
	)
	var page_items := _page_items()
	if not page_items.is_empty():
		_history_anchor_id = str(
			(page_items[0] as Dictionary).get("announcement_id", "")
		)
	elif _items.is_empty():
		_history_anchor_id = ""


func _page_items() -> Array:
	if _items.is_empty():
		return []
	var start := _history_page * _history_page_size
	var finish := mini(_items.size(), start + _history_page_size)
	return _items.slice(start, finish)


func _set_history_page(page_index: int) -> void:
	var clamped := clampi(page_index, 0, _history_page_count - 1)
	if clamped == _history_page:
		return
	_history_page = clamped
	var page_items := _page_items()
	_history_anchor_id = (
		str((page_items[0] as Dictionary).get(
			"announcement_id",
			""
		))
		if not page_items.is_empty()
		else ""
	)
	_render()


func _on_newer_pressed() -> void:
	_set_history_page(_history_page - 1)


func _on_older_pressed() -> void:
	_set_history_page(_history_page + 1)


func _on_history_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_history_swipe_tracking = true
			_history_swipe_start = touch.position
			return
		if not _history_swipe_tracking:
			return
		_history_swipe_tracking = false
		var delta_x := touch.position.x - _history_swipe_start.x
		if absf(delta_x) >= HISTORY_SWIPE_THRESHOLD:
			_set_history_page(_history_page - 1 if delta_x > 0.0 else _history_page + 1)
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_history_page(_history_page - 1)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_history_page(_history_page + 1)
		get_viewport().set_input_as_handled()


func _on_editor_text_changed(editor: TextEdit) -> void:
	if _internal_text_update or not editor.is_visible_in_tree():
		return
	_pending_draft_text = editor.text
	_draft_update_pending = true
	_draft_timer.start()


func _set_editor_text_preserving_caret(
	editor: TextEdit,
	text_value: String,
) -> void:
	var caret_line := editor.get_caret_line()
	var caret_column := editor.get_caret_column()
	editor.text = text_value
	var restored_line := clampi(
		caret_line,
		0,
		maxi(editor.get_line_count() - 1, 0),
	)
	editor.set_caret_line(restored_line)
	editor.set_caret_column(
		mini(caret_column, editor.get_line(restored_line).length())
	)


func _flush_draft_intent() -> void:
	_pending_draft_text = _current_editor_text()
	_request_action(
		"updateDraft",
		{"text": _pending_draft_text}
	)


func _on_primary_pressed(button: Button) -> void:
	var action_key := str(button.get_meta("action_key", ""))
	var payload := {}
	if action_key == "publish":
		if is_instance_valid(_draft_timer):
			_draft_timer.stop()
		var current_text := _current_editor_text()
		_pending_draft_text = current_text
		var composer := _render_data.get("composer", {}) as Dictionary
		if current_text != str(composer.get("draftText", "")):
			if not _request_action(
				"updateDraft",
				{"text": current_text},
			):
				return
		payload["text"] = current_text
	_request_action(action_key, payload)


func _on_common_feedback_action(
	action_key: StringName,
	surface: String
) -> void:
	var key := str(action_key)
	if surface == "dialog" and key == "discard":
		key = "discardDraft"
	elif surface == "toast" and key == "dismiss":
		key = "dismissFeedback"
	_request_action(key, {})


func _on_common_feedback_dismissed(surface: String) -> void:
	_request_action(
		"continueEditing" if surface == "dialog" else "dismissFeedback",
		{}
	)


func _request_action(
	action_key: String,
	payload: Dictionary
) -> bool:
	var action := UiViewModel.action(_view_model, action_key)
	var intent := StringName(action.get("intent", ""))
	var enabled := UiViewModel.action_enabled(action)
	var reason := UiViewModel.disabled_reason(action)
	if _contract_failure or intent.is_empty() or not enabled:
		action_blocked.emit(
			intent,
			(
				_contract_failure_message
				if _contract_failure
				else (
					reason
					if not reason.is_empty()
					else "ACTION_DISABLED"
				)
			)
		)
		return false
	if (
		action_key != "updateDraft"
		and _pending_action_intent == str(intent)
	):
		action_blocked.emit(intent, "DUPLICATE_REQUEST_PENDING")
		return false
	var envelope := {}
	var static_payload: Variant = action.get("payload", {})
	if static_payload is Dictionary:
		envelope = (static_payload as Dictionary).duplicate(true)
	envelope.merge(payload, true)
	if action_key != "updateDraft":
		_pending_action_intent = str(intent)
	intent_requested.emit(intent, envelope.duplicate(true))
	if _adapter != null and _adapter.has_method("dispatch"):
		_adapter.call("dispatch", intent, envelope)
	return true


func _action_enabled(action_key: String) -> bool:
	return (
		not _contract_failure
		and UiViewModel.action_enabled(
			UiViewModel.action(_view_model, action_key)
		)
	)


func _refresh_from_adapter() -> void:
	if _adapter == null or not _adapter.has_method("get_view_model"):
		return
	var incoming: Variant = _adapter.call("get_view_model", str(SCOPE))
	if incoming is Dictionary:
		if not apply_view_model(incoming as Dictionary):
			_set_contract_failure(
				"正式 announcements ViewModel 未通过完整页面合同校验。"
			)


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_view_model_changed"),
	)


func _on_view_model_changed(
	scope_value: Variant,
	view_model: Dictionary
) -> void:
	if StringName(scope_value) != SCOPE:
		return
	if not apply_view_model(view_model):
		_set_contract_failure(
			"正式 announcements ViewModel 更新不完整，页面动作已禁用。"
		)


func _validate_complete_view_model(
	view_model: Dictionary
) -> PackedStringArray:
	var issues := UiViewModel.validate(view_model, "公告栏")
	if StringName(view_model.get("scope", "")) != SCOPE:
		issues.append("公告栏.scope 必须是 announcements")
	var data_value: Variant = view_model.get("data", {})
	if not data_value is Dictionary:
		return issues
	var data := data_value as Dictionary
	for key: String in [
		"capabilityMode",
		"source",
		"formalReady",
		"panel",
		"items",
		"emptyState",
		"composer",
		"dialog",
		"feedback",
	]:
		if not data.has(key):
			issues.append("公告栏.data 缺少 %s" % key)
	if typeof(data.get("formalReady", null)) != TYPE_BOOL:
		issues.append("公告栏.data.formalReady 必须是 bool")
	if (
		str(data.get("source", "")) == "placeholder"
		and bool(data.get("formalReady", true))
	):
		issues.append("公告栏 placeholder 不得 formalReady=true")
	for dictionary_key: String in [
		"panel",
		"emptyState",
		"composer",
		"dialog",
		"feedback",
	]:
		if typeof(data.get(dictionary_key, null)) != TYPE_DICTIONARY:
			issues.append(
				"公告栏.data.%s 必须是 Dictionary" % dictionary_key
			)
	if typeof(data.get("items", null)) != TYPE_ARRAY:
		issues.append("公告栏.data.items 必须是 Array")
	else:
		for item_value: Variant in data.get("items", []) as Array:
			if not item_value is Dictionary:
				issues.append("公告栏.data.items[] 必须是 Dictionary")
				continue
			var item := item_value as Dictionary
			for item_key: String in [
				"announcement_id",
				"text",
				"time",
				"timeLabel",
			]:
				if not item.has(item_key):
					issues.append(
						"公告栏.data.items[] 缺少 %s" % item_key
					)
	var panel := data.get("panel", {}) as Dictionary
	if str(panel.get("mode", "")) not in ["browse", "compose"]:
		issues.append("公告栏.data.panel.mode 必须是 browse/compose")
	if not bool(panel.get("worldContinues", false)):
		issues.append("公告栏打开期间 worldContinues 必须为 true")
	var composer := data.get("composer", {}) as Dictionary
	for composer_key: String in [
		"open",
		"draftText",
		"characterCount",
		"characterLimit",
		"remainingCount",
		"validationCode",
		"inputFocused",
		"softKeyboardVisible",
		"keyboardSubmitBehavior",
	]:
		if not composer.has(composer_key):
			issues.append(
				"公告栏.data.composer 缺少 %s" % composer_key
			)
	if (
		not composer.is_empty()
		and str(composer.get("keyboardSubmitBehavior", ""))
		!= "dismiss_only"
	):
		issues.append(
			"公告栏软键盘提交行为必须是 dismiss_only"
		)
	var actions_value: Variant = view_model.get("actions", {})
	if actions_value is Dictionary:
		var actions := actions_value as Dictionary
		for action_key: String in EXPECTED_INTENTS:
			var action_value: Variant = actions.get(action_key)
			if not action_value is Dictionary:
				issues.append(
					"公告栏.actions 缺少 %s" % action_key
				)
				continue
			var action := action_value as Dictionary
			if str(action.get("intent", "")) != str(
				EXPECTED_INTENTS[action_key]
			):
				issues.append(
					"公告栏.actions.%s.intent 不匹配" % action_key
				)
			if typeof(action.get("enabled", null)) != TYPE_BOOL:
				issues.append(
					"公告栏.actions.%s.enabled 必须是 bool"
					% action_key
				)
			if typeof(action.get("disabledReason", null)) != TYPE_STRING:
				issues.append(
					"公告栏.actions.%s.disabledReason 必须是 String"
					% action_key
				)
	return issues


func _set_contract_failure(message: String) -> void:
	_contract_failure = true
	_contract_failure_message = message
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	_current_revision = -1
	_pending_draft_text = ""
	_draft_update_pending = false
	if is_node_ready():
		_render()


func _contract_failure_data() -> Dictionary:
	return {
		"capabilityMode": "unavailable",
		"source": "town_ui_adapter",
		"formalReady": false,
		"panel": {
			"open": true,
			"mode": "browse",
			"title": "公告栏",
			"worldContinues": true,
			"focusTarget": "requestClose",
		},
		"items": [],
		"emptyState": {
			"title": "公告栏暂不可用",
			"message": _contract_failure_message,
		},
		"composer": {
			"open": false,
			"draftText": "",
			"characterCount": 0,
			"characterLimit": 0,
			"remainingCount": 0,
			"validationCode": "",
			"inputFocused": false,
			"softKeyboardVisible": false,
			"keyboardSubmitBehavior": "dismiss_only",
		},
		"dialog": {
			"open": false,
			"kind": "none",
			"title": "",
			"message": "",
		},
		"feedback": {
			"visible": false,
			"kind": "none",
			"title": "",
			"message": "",
			"durationMs": 0,
			"blocksInput": false,
		},
	}


func _queue_responsive_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_queued = false
	var viewport_rect := get_viewport_rect()
	var viewport_size := Vector2(
		floorf(viewport_rect.size.x),
		floorf(viewport_rect.size.y)
	)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var parsed_insets := _read_safe_insets()
	var base_inset := 24.0
	var available_before_base := Vector2(
		viewport_size.x - parsed_insets.x - parsed_insets.z,
		viewport_size.y - parsed_insets.y - parsed_insets.w
	)
	var aspect := (
		available_before_base.x
		/ maxf(1.0, available_before_base.y)
	)
	if available_before_base.x < 960.0 or available_before_base.y < 640.0:
		base_inset = 16.0
	var left := maxf(parsed_insets.x, base_inset)
	var top := maxf(parsed_insets.y, base_inset)
	var right := maxf(parsed_insets.z, base_inset)
	var bottom := maxf(parsed_insets.w, base_inset)
	_safe_insets = Rect2(left, top, right, bottom)
	var available := Vector2(
		maxf(1.0, viewport_size.x - left - right),
		maxf(1.0, viewport_size.y - top - bottom)
	)
	_layout_profile = _layout_profile_for_available(available, aspect)

	_wide_root.position = Vector2(
		floorf((viewport_size.x - APPROVED_SOURCE_SIZE.x) * 0.5),
		floorf((viewport_size.y - APPROVED_SOURCE_SIZE.y) * 0.5)
	)
	_wide_root.size = APPROVED_SOURCE_SIZE
	var overview_right_margin := maxf(
		right,
		OVERVIEW_DESKTOP_RIGHT_MARGIN
	)
	var overview_top := maxf(top, OVERVIEW_DESKTOP_TOP)
	_overview_root.position = Vector2(
		floorf(
			viewport_size.x
			- overview_right_margin
			- OVERVIEW_SOURCE_SIZE.x
		),
		floorf(overview_top)
	)
	_overview_root.size = OVERVIEW_SOURCE_SIZE
	var max_flow_width := 1520.0
	var flow_width := minf(available.x, max_flow_width)
	var flow_height := available.y
	_flow_shell.position = Vector2(
		floorf(left + (available.x - flow_width) * 0.5),
		floorf(top)
	)
	_flow_shell.size = Vector2(
		floorf(flow_width),
		floorf(flow_height)
	)
	match _layout_profile:
		"standard":
			_flow_main_grid.columns = 2 if available.x >= 1160.0 else 1
		"compact_landscape":
			_flow_main_grid.columns = 2
		"portrait":
			_flow_main_grid.columns = 1
		_:
			_flow_main_grid.columns = 2
	_flow_header.columns = 1 if _layout_profile == "portrait" else 2
	(_flow["rail"] as Control).visible = _layout_profile != "portrait"
	_flow_list_panel.custom_minimum_size = Vector2(
		0,
		330 if _flow_main_grid.columns == 1 else 470
	)
	_flow_composer_panel.custom_minimum_size = Vector2(
		0,
		430
	)
	call_deferred(
		"_apply_flow_geometry",
		viewport_size,
		left,
		top,
		right,
		bottom
	)
	_layout_feedback(viewport_size, left, top, right, bottom)
	_render()


func _layout_profile_for_available(
	available: Vector2,
	aspect: float,
) -> String:
	if available.x >= 1720.0 and available.y >= 980.0:
		return "wide"
	if available.x >= 960.0 and available.y >= 640.0:
		return "standard"
	if (
		(available.x >= 720.0 and aspect >= 1.2)
		or available.y < 640.0
	):
		return "compact_landscape"
	return "portrait"


func _apply_flow_geometry(
	viewport_size: Vector2,
	left: float,
	top: float,
	right: float,
	bottom: float
) -> void:
	var available := Vector2(
		maxf(1.0, viewport_size.x - left - right),
		maxf(1.0, viewport_size.y - top - bottom)
	)
	var flow_width := minf(available.x, 1520.0)
	_flow_shell.position = Vector2(
		floorf(left + (available.x - flow_width) * 0.5),
		floorf(top)
	)
	_flow_shell.size = Vector2(
		floorf(flow_width),
		floorf(available.y)
	)


func _layout_feedback(
	viewport_size: Vector2,
	left: float,
	top: float,
	right: float,
	bottom: float
) -> void:
	_overlay_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe_width := viewport_size.x - left - right
	var safe_height := viewport_size.y - top - bottom
	var dialog_width := minf(727.0, safe_width)
	var dialog_height := 342.0 if dialog_width >= 600.0 else minf(
		430.0,
		safe_height
	)
	_dialog_component.position = Vector2(
		floorf(left + (safe_width - dialog_width) * 0.5),
		floorf(top + (safe_height - dialog_height) * 0.5)
	)
	_dialog_component.size = Vector2(
		floorf(dialog_width),
		floorf(dialog_height)
	)
	var toast_width := minf(450.0, safe_width)
	var toast_height := 115.0
	_toast_component.position = Vector2(
		floorf(left + (safe_width - toast_width) * 0.5),
		floorf(top + (safe_height - toast_height) * 0.5)
	)
	_toast_component.size = Vector2(
		floorf(toast_width),
		floorf(toast_height)
	)


func _active_surface() -> Dictionary:
	match _composition_kind:
		"wide_art":
			return _wide
		"side_panel":
			return _overview
		_:
			return _flow


func _active_board_rect() -> Rect2:
	match _composition_kind:
		"wide_art":
			return Rect2(_wide_root.global_position, _wide_root.size)
		"side_panel":
			return Rect2(
				_overview_root.global_position,
				_overview_root.size
			)
		_:
			return Rect2(_flow_shell.global_position, _flow_shell.size)


func _overview_side_fits() -> bool:
	var viewport_size := get_viewport_rect().size.floor()
	return (
		viewport_size.x
		>= OVERVIEW_SOURCE_SIZE.x + OVERVIEW_DESKTOP_RIGHT_MARGIN
		and viewport_size.y
		>= OVERVIEW_SOURCE_SIZE.y + OVERVIEW_DESKTOP_TOP
	)


func _request_semantic_focus(panel: Dictionary) -> void:
	var target := str(panel.get("focusTarget", ""))
	var identity := "%d|%s|%s" % [
		_current_revision,
		target,
		_composition_kind,
	]
	if identity == _last_focus_identity:
		return
	_last_focus_identity = identity
	call_deferred("_apply_semantic_focus", target)


func _apply_semantic_focus(target: String) -> void:
	var surface := _active_surface()
	var focus_target: Control
	match target:
		"composerInput":
			focus_target = surface.get("editor") as Control
		"publish", "openComposer", "retry":
			focus_target = surface.get("primary") as Control
		"requestClose":
			focus_target = surface.get("close") as Control
		_:
			if target.begins_with("announcement-"):
				focus_target = surface.get("rail") as Control
			else:
				focus_target = surface.get("close") as Control
	if (
		focus_target != null
		and focus_target.is_visible_in_tree()
		and focus_target.focus_mode != Control.FOCUS_NONE
	):
		focus_target.grab_focus()


func _wide_page_fits(page_items: Array) -> bool:
	var font := theme.default_font
	if font == null:
		return false
	for item_value: Variant in page_items:
		if not item_value is Dictionary:
			continue
		var text_value := str((item_value as Dictionary).get("text", ""))
		var measured := font.get_multiline_string_size(
			text_value,
			HORIZONTAL_ALIGNMENT_LEFT,
			416.0,
			25,
			9
		)
		if measured.y > 154.0:
			return false
	return true


func _overview_page_fits(page_items: Array) -> bool:
	var font := theme.default_font
	if font == null:
		return false
	for item_value: Variant in page_items:
		if not item_value is Dictionary:
			continue
		var text_value := str((item_value as Dictionary).get("text", ""))
		var measured := font.get_multiline_string_size(
			text_value,
			HORIZONTAL_ALIGNMENT_LEFT,
			445.0,
			19,
			6
		)
		if measured.y > 96.0:
			return false
	return true


func _status_copy(
	operation_status: String,
	validation_copy: String
) -> String:
	if _contract_failure:
		return _contract_failure_message
	var error_message := UiViewModel.error_message(_view_model)
	if operation_status in ["rejected", "error", "disabled"]:
		if not error_message.is_empty():
			return error_message
	if not validation_copy.is_empty():
		return validation_copy
	return str(OPERATION_COPY.get(
		operation_status,
		"小镇时间照常流动"
	))


func _status_color(operation_status: String) -> Color:
	match operation_status:
		"success":
			return PageTheme.MOSS_DARK
		"rejected", "error":
			return PageTheme.ERROR_DARK
		"loading":
			return Color("684815")
		"disabled":
			return Color("51483c")
		_:
			return PageTheme.INK_MUTED


func _index_of_announcement(announcement_id: String) -> int:
	for index: int in range(_items.size()):
		var item_value: Variant = _items[index]
		if (
			item_value is Dictionary
			and str((item_value as Dictionary).get(
				"announcement_id",
				""
			)) == announcement_id
		):
			return index
	return -1


func _read_safe_insets() -> Vector4:
	if not OS.is_debug_build():
		return Vector4.ZERO
	var raw := OS.get_environment("AI_TOWN_BULLETIN_SAFE_INSETS")
	if raw.is_empty():
		return Vector4.ZERO
	var parts := raw.split(",")
	if parts.size() != 4:
		return Vector4.ZERO
	return Vector4(
		maxf(0.0, float(parts[0])),
		maxf(0.0, float(parts[1])),
		maxf(0.0, float(parts[2])),
		maxf(0.0, float(parts[3]))
	)


func _make_label(
	text_value: String,
	font_size: int,
	color: Color,
	gate_id: String,
	max_lines: int,
	heading: bool = false
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if heading and _heading_font != null:
		label.add_theme_font_override("font", _heading_font)
	label.autowrap_mode = (
		TextServer.AUTOWRAP_OFF
		if max_lines == 1
		else TextServer.AUTOWRAP_WORD_SMART
	)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.max_lines_visible = max_lines
	var minimum_lines := 1 if max_lines <= 1 else mini(max_lines, 2)
	label.custom_minimum_size.y = ceilf(
		float(font_size) * 1.5 * float(minimum_lines)
	)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_register_text(label, gate_id)
	return label


func _place_label(
	parent: Control,
	node_name: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	gate_id: String,
	max_lines: int,
	alignment: HorizontalAlignment,
	heading: bool = false
) -> Label:
	var label := _make_label(
		"",
		font_size,
		color,
		gate_id,
		max_lines,
		heading
	)
	label.name = node_name
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	parent.add_child(label)
	return label


func _place_padded_label(
	parent: Control,
	node_name: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	gate_id: String,
	max_lines: int,
	alignment: HorizontalAlignment,
	horizontal_padding: int,
	label_height: int,
	vertical_offset: int
) -> Label:
	var slot := Control.new()
	slot.name = node_name + "SafeSlot"
	slot.position = rect.position
	slot.size = rect.size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(slot)
	var label := _make_label(
		"",
		font_size,
		color,
		gate_id,
		max_lines
	)
	label.name = node_name
	label.horizontal_alignment = alignment
	label.position = Vector2(horizontal_padding, vertical_offset)
	label.size = Vector2(
		maxf(1.0, rect.size.x - horizontal_padding * 2.0),
		label_height
	)
	label.remove_from_group("bulletin_board_text_slot")
	label.remove_meta("gate_text_id")
	slot.add_child(label)
	_register_text(slot, gate_id)
	slot.set_meta("gate_text_source", label.name)
	return label


func _make_button(
	text_value: String,
	variant: String,
	gate_id: String,
	font_size: int = 32
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(96, 68)
	button.focus_mode = Control.FOCUS_ALL
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size", font_size)
	if _button_font != null:
		button.add_theme_font_override("font", _button_font)
	_style_button(button, variant)
	_register_text(button, gate_id + "_text")
	_register_touch(button, gate_id)
	return button


func _place_button(
	parent: Control,
	node_name: String,
	text_value: String,
	rect: Rect2,
	variant: String,
	gate_id: String,
	font_size: int = 32
) -> Button:
	var button := _make_button(
		text_value,
		variant,
		gate_id,
		font_size
	)
	button.name = node_name
	button.position = rect.position
	button.size = rect.size
	button.custom_minimum_size = rect.size
	parent.add_child(button)
	return button


func _place_hit_button(
	parent: Control,
	node_name: String,
	rect: Rect2,
	gate_id: String,
	tooltip: String
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.position = rect.position
	button.size = rect.size
	button.custom_minimum_size = rect.size
	button.text = ""
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_ALL
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"focus",
		"disabled",
	]:
		button.add_theme_stylebox_override(
			state,
			PageTheme.composite_content_style()
		)
	_register_touch(button, gate_id)
	parent.add_child(button)
	return button


func _make_editor(node_name: String, gate_id: String) -> TextEdit:
	var editor := TextEdit.new()
	editor.name = node_name
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.scroll_fit_content_height = false
	editor.context_menu_enabled = true
	editor.shortcut_keys_enabled = true
	editor.focus_mode = Control.FOCUS_ALL
	editor.add_theme_font_size_override("font_size", 32)
	editor.add_theme_color_override("font_color", PageTheme.INK)
	editor.text_changed.connect(_on_editor_text_changed.bind(editor))
	_register_text(editor, gate_id)
	_register_touch(editor, gate_id)
	return editor


func _place_editor(
	parent: Control,
	node_name: String,
	rect: Rect2,
	gate_id: String
) -> TextEdit:
	var editor := _make_editor(node_name, gate_id)
	editor.position = rect.position
	editor.size = rect.size
	editor.custom_minimum_size = rect.size
	parent.add_child(editor)
	return editor


func _style_button(button: Button, variant: String) -> void:
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"focus",
		"disabled",
	]:
		button.add_theme_stylebox_override(
			state,
			(
				PageTheme.secondary_button_asset_style(state)
				if variant == "wood"
				else PageTheme.button_style(variant, state)
			)
		)
	var light_ink := variant in ["primary", "wood", "danger", "success"]
	var active_color := (
		PageTheme.BUTTON_INK if light_ink else PageTheme.INK
	)
	for color_name: String in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
	]:
		button.add_theme_color_override(color_name, active_color)
	button.add_theme_color_override(
		"font_disabled_color",
		Color("51483c")
	)


func _style_composite_button(button: Button) -> void:
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"focus",
		"disabled",
	]:
		button.add_theme_stylebox_override(
			state,
			PageTheme.composite_content_style(8)
		)
	button.add_theme_color_override(
		"font_hover_color",
		PageTheme.PAPER_LIGHT
	)
	button.add_theme_color_override(
		"font_focus_color",
		PageTheme.HONEY
	)
	button.add_theme_color_override(
		"font_pressed_color",
		PageTheme.PAPER_SOFT
	)


func _style_composite_editor(editor: TextEdit) -> void:
	for state: String in ["normal", "focus", "read_only"]:
		editor.add_theme_stylebox_override(
			state,
			PageTheme.composite_content_style(12)
		)


func _apply_metadata_font(label: Label) -> void:
	if _metadata_font != null:
		label.add_theme_font_override("font", _metadata_font)


func _border_ownership_snapshot() -> Dictionary:
	var layers := [
		"page_shell",
		"section_frame",
		"content_slot",
		"operation_control",
	]
	var records: Array = []
	if _composition_kind == "wide_art":
		var composite_id := (
			"ui.bulletin-board.complete-runtime-shell-v1"
		)
		for edge_id: String in [
			"wide.page_outer_frame",
			"wide.title_strip_frame",
			"wide.history_section_frame",
			"wide.history_card_1_frame",
			"wide.history_card_2_frame",
			"wide.composer_section_frame",
			"wide.composer_input_slot",
			"wide.character_count_slot",
			"wide.operation_status_slot",
			"wide.primary_action_slot",
			"wide.section_divider",
		]:
			records.append({
				"edgeId": edge_id,
				"layer": (
					"page_shell"
					if edge_id == "wide.page_outer_frame"
					else (
						"section_frame"
						if (
							"section_frame" in edge_id
							or edge_id == "wide.section_divider"
						)
						else "content_slot"
					)
				),
				"owner": "ApprovedNoTextSource",
				"assetId": composite_id,
				"assetDirectory": (
					"res://assets/ui/bulletin_board/final/"
				),
				"componentType": "complete_composite_shell",
				"registeredAsStyleBoxTexture": false,
				"duplicateOwners": [],
			})
		var editor_duplicates: Array = []
		if _control_has_visible_border(
			_wide["editor"] as Control,
			["normal", "focus", "read_only"]
		):
			editor_duplicates.append("WideEditor")
		var primary_duplicates: Array = []
		if _control_has_visible_border(
			_wide["primary"] as Control,
			["normal", "hover", "pressed", "focus", "disabled"]
		):
			primary_duplicates.append("WidePrimary")
		for record: Dictionary in records:
			if record["edgeId"] == "wide.composer_input_slot":
				record["duplicateOwners"] = editor_duplicates
			elif record["edgeId"] == "wide.primary_action_slot":
				record["duplicateOwners"] = primary_duplicates
		for button_key: String in ["newer", "older", "close"]:
			var button_control := _wide[button_key] as Control
			records.append({
				"edgeId": "wide.%s_button_frame" % button_key,
				"layer": "operation_control",
				"owner": button_control.name,
				"assetId": (
					"ui.bulletin-board.primitive.secondary-button-v1"
				),
				"assetDirectory": (
					"res://assets/ui/bulletin_board/final/primitives/"
				),
				"componentType": (
					"page_exclusive_nine_slice_stylebox_texture"
				),
				"registeredAsStyleBoxTexture": (
					_control_uses_stylebox_texture(
						button_control,
						[
							"normal",
							"hover",
							"pressed",
							"focus",
							"disabled",
						]
					)
				),
				"runtimeTexturePath": (
					_control_stylebox_texture_path(button_control)
				),
				"duplicateOwners": [],
			})
		records.append({
			"edgeId": "wide.history_scroll_track",
			"layer": "operation_control",
			"owner": "WideHistoryRail",
			"assetId": "ui.bulletin-board.history-rail",
			"assetDirectory": (
				"res://ui/bulletin_board/BulletinBoardHistoryRail.gd"
			),
			"componentType": "runtime_drawn_control",
			"registeredAsStyleBoxTexture": false,
			"duplicateOwners": [],
		})
	elif _composition_kind == "side_panel":
		for edge_id: String in [
			"overview.page_outer_frame",
			"overview.title_strip_frame",
			"overview.history_section_frame",
			"overview.history_card_1_frame",
			"overview.history_card_2_frame",
			"overview.composer_section_frame",
			"overview.composer_input_slot",
			"overview.character_count_slot",
			"overview.operation_status_slot",
			"overview.primary_action_slot",
			"overview.history_scroll_groove",
		]:
			var duplicate_owners: Array = []
			if (
				edge_id == "overview.composer_input_slot"
				and _control_has_visible_border(
					_overview["editor"] as Control,
					["normal", "focus", "read_only"]
				)
			):
				duplicate_owners.append("OverviewEditor")
			elif (
				edge_id == "overview.primary_action_slot"
				and _control_has_visible_border(
					_overview["primary"] as Control,
					["normal", "hover", "pressed", "focus", "disabled"]
				)
			):
				duplicate_owners.append("OverviewPrimary")
			records.append({
				"edgeId": edge_id,
				"layer": (
					"page_shell"
					if edge_id == "overview.page_outer_frame"
					else (
						"section_frame"
						if "section_frame" in edge_id
						else "content_slot"
					)
				),
				"owner": "ApprovedOverviewNoTextSource",
				"assetId": (
					"ui.bulletin-board.overview-side-panel-shell-v1"
				),
				"assetDirectory": (
					"res://assets/ui/bulletin_board/final/"
				),
				"componentType": "complete_composite_shell",
				"registeredAsStyleBoxTexture": false,
				"duplicateOwners": duplicate_owners,
			})
		records.append({
			"edgeId": "overview.close_hit_target",
			"layer": "operation_control",
			"owner": "OverviewClose",
			"assetId": "overview-shell-baked-close-control",
			"assetDirectory": (
				"res://assets/ui/bulletin_board/final/"
			),
			"componentType": "transparent_hit_target_over_baked_asset",
			"registeredAsStyleBoxTexture": false,
			"duplicateOwners": [],
		})
	else:
		var flow_owners := [
			[
				"flow.page_outer_frame",
				"page_shell",
				"ResponsiveBoard",
			],
			[
				"flow.history_section_frame",
				"section_frame",
				"HistoryPanel",
			],
			[
				"flow.composer_section_frame",
				"section_frame",
				"ComposerPanel",
			],
			[
				"flow.composer_input_slot",
				"content_slot",
				"FlowEditor",
			],
			[
				"flow.operation_status_slot",
				"content_slot",
				"OperationStatus",
			],
			[
				"flow.primary_button_frame",
				"operation_control",
				"FlowPrimary",
			],
			[
				"flow.newer_button_frame",
				"operation_control",
				"FlowNewer",
			],
			[
				"flow.older_button_frame",
				"operation_control",
				"FlowOlder",
			],
			[
				"flow.close_button_frame",
				"operation_control",
				"FlowClose",
			],
			[
				"flow.history_scroll_track",
				"operation_control",
				"ResponsiveHistoryRail",
			],
		]
		for entry: Array in flow_owners:
			var uses_secondary_asset: bool = str(entry[2]) in [
				"FlowNewer",
				"FlowOlder",
				"FlowClose",
			]
			var secondary_control: Control = null
			if uses_secondary_asset:
				secondary_control = {
					"FlowNewer": _flow["newer"],
					"FlowOlder": _flow["older"],
					"FlowClose": _flow["close"],
				}.get(entry[2]) as Control
			records.append({
				"edgeId": entry[0],
				"layer": entry[1],
				"owner": entry[2],
				"assetId": (
					(
						"ui.bulletin-board.primitive."
						+ "secondary-button-v1"
					)
					if uses_secondary_asset
					else "ui.bulletin-board.style.%s" % entry[0]
				),
				"assetDirectory": (
					(
						"res://assets/ui/bulletin_board/final/primitives/"
					)
					if uses_secondary_asset
					else "res://ui/bulletin_board/"
				),
				"componentType": (
					"page_exclusive_nine_slice_stylebox_texture"
					if uses_secondary_asset
					else "runtime_style_or_drawn_control"
				),
				"registeredAsStyleBoxTexture": (
					_control_uses_stylebox_texture(
						secondary_control,
						[
							"normal",
							"hover",
							"pressed",
							"focus",
							"disabled",
						]
					)
					if uses_secondary_asset
					else false
				),
				"runtimeTexturePath": (
					_control_stylebox_texture_path(secondary_control)
					if uses_secondary_asset
					else ""
				),
				"duplicateOwners": [],
			})
		for card: Node in _flow_cards.get_children():
			if not card is PanelContainer:
				continue
			records.append({
				"edgeId": "flow.%s_frame" % card.name,
				"layer": "content_slot",
				"owner": card.name,
				"assetId": "ui.bulletin-board.style.announcement-card",
				"assetDirectory": (
					"res://ui/bulletin_board/BulletinBoardTheme.gd"
				),
				"componentType": "runtime_stylebox_flat",
				"registeredAsStyleBoxTexture": false,
				"duplicateOwners": [],
			})
	return {
		"hierarchy": layers,
		"records": records,
	}


func _control_has_visible_border(
	control: Control,
	style_names: Array[String]
) -> bool:
	for style_name: String in style_names:
		var style := control.get_theme_stylebox(style_name)
		if style is StyleBoxFlat:
			var flat := style as StyleBoxFlat
			if (
				flat.border_color.a > 0.0
				and (
					flat.border_width_left > 0
					or flat.border_width_top > 0
					or flat.border_width_right > 0
					or flat.border_width_bottom > 0
				)
			):
				return true
		elif style is StyleBoxTexture:
			return true
	return false


func _control_uses_stylebox_texture(
	control: Control,
	style_names: Array[String]
) -> bool:
	if control == null:
		return false
	for style_name: String in style_names:
		if not control.get_theme_stylebox(style_name) is StyleBoxTexture:
			return false
	return true


func _control_stylebox_texture_path(control: Control) -> String:
	if control == null:
		return ""
	var style := control.get_theme_stylebox("normal")
	if not style is StyleBoxTexture:
		return ""
	var texture := (style as StyleBoxTexture).texture
	return texture.resource_path if texture != null else ""


func _register_text(control: Control, gate_id: String) -> void:
	control.add_to_group("bulletin_board_text_slot")
	control.set_meta("gate_text_id", gate_id)


func _register_touch(control: Control, gate_id: String) -> void:
	control.custom_minimum_size = control.custom_minimum_size.max(
		MINIMUM_TOUCH_SIZE
	)
	control.focus_mode = Control.FOCUS_ALL
	control.add_to_group("bulletin_board_touch_target")
	control.set_meta("gate_touch_id", gate_id)


func _register_region(control: Control, gate_id: String) -> void:
	control.add_to_group("bulletin_board_region")
	control.set_meta("gate_region_id", gate_id)


func _control_text(control: Control) -> String:
	if control is Label:
		return (control as Label).text
	if control is Button:
		return (control as Button).text
	if control is TextEdit:
		return (control as TextEdit).text
	return ""


func _gate_text_source(control: Control) -> Control:
	var source_name := str(control.get_meta("gate_text_source", ""))
	if source_name.is_empty():
		return control
	var source := control.get_node_or_null(NodePath(source_name)) as Control
	return source if source != null else control


func _gate_font_path(font: Font) -> String:
	if font == null:
		return ""
	if font is FontVariation:
		return _gate_font_path((font as FontVariation).base_font)
	return font.resource_path


func _gate_glyph_spacing(font: Font) -> int:
	if font is FontVariation:
		return (font as FontVariation).spacing_glyph
	return 0


func _rect_to_array(rect: Rect2) -> Array:
	return UI_VIEW_MODEL.rect_to_array(rect)
