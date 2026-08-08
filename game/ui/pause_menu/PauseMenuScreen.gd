class_name PauseMenuScreen
extends Control


const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")


signal intent_requested(intent: String, payload: Dictionary)
signal action_blocked(intent: String, reason: String)


enum LayoutMode {
	DESKTOP,
	STANDARD,
	COMPACT_LANDSCAPE,
	COMPACT_PORTRAIT,
}


const UiViewModel = preload("res://ui/common/AiTownUiViewModel.gd")
const PageTheme = preload("res://ui/pause_menu/PauseMenuTheme.gd")

const DESKTOP_SHELL_TEXTURE_PATH := (
	"res://assets/ui/pause_menu/final/composite/"
	+ "pause_menu_commercial_root_v2.png"
)
const DESKTOP_SHELL_SIZE := Vector2(1672.0, 941.0)
const DESKTOP_MIN_VIEWPORT := Vector2(1760.0, 980.0)
const APPROVED_DESKTOP_MAX_SCALE := 1.0
const REQUIRED_SCOPES: Array[String] = [
	"lifecycle",
	"session",
	"save",
	"pause_menu",
]
const ENTRY_ACTION_KEYS := {
	"return_game": "returnGame",
	"save_game": "saveGame",
	"load_game": "openLoadGame",
	"game_settings": "openGameSettings",
}
const OPERATION_LABELS := {
	"idle": "小镇已暂停",
	"loading": "正在处理，请稍候……",
	"success": "操作已完成",
	"rejected": "当前操作未被接受",
	"error": "操作暂时失败",
	"disabled": "此功能当前不可用",
}
const SAVE_ERROR_CODE := "AGENT_SAVE_INTERFACE_MISSING"
const IN_SESSION_CONTINUE_DISABLED_REASON := (
	"IN_SESSION_CONTINUE_NOT_APPLICABLE"
)
const SAVE_CREATE_ALREADY_PENDING := "SAVE_CREATE_ALREADY_PENDING"
const TOUCH_TARGET_MIN := 80.0

const COLOR_SCRIM := Color(0.08, 0.06, 0.04, 0.50)
const COLOR_PAPER := Color("fff0cc")
const COLOR_PAPER_ALT := Color("f3ddb3")
const COLOR_INK := Color("3f2818")
const COLOR_MUTED := Color("76583d")
const COLOR_WOOD := Color("6c3d20")
const COLOR_TERRACOTTA := Color("b94d2d")
const COLOR_MOSS := Color("557b2a")
const COLOR_DISABLED := Color("cbbd9f")
const COLOR_ERROR := Color("8d3526")

var _adapter: Node
var _view_models: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _revision_by_scope: Dictionary = {}
var _confirmed_revision_by_scope: Dictionary = {}
var _rendered_revision_by_scope: Dictionary = {}
var _layout_mode := LayoutMode.DESKTOP
var _last_layout_viewport := Vector2.ZERO
var _last_requested_shell_rect := Rect2()
var _layout_refresh_queued := false
var _render_queued := false
var _initial_focus_queued := false
var _save_create_submission_pending := false
var _local_operation: Dictionary = {}

var _desktop_root: Control
var _desktop_entry_buttons: Dictionary = {}
var _desktop_focus_chain: Array[Button] = []
var _desktop_title_label: Label
var _desktop_subtitle_label: Label
var _desktop_summary_label: Label
var _desktop_source_badge_label: Label
var _desktop_save_heading_label: Label
var _desktop_save_label: Label
var _desktop_save_code_label: Label
var _desktop_operation_label: Label
var _desktop_save_create_button: Button
var _desktop_continue_button: Button
var _desktop_return_start_button: Button
var _desktop_quit_button: Button

var _shell: PanelContainer
var _body_scroll: ScrollContainer
var _body_grid: GridContainer
var _entry_list: VBoxContainer
var _compact_entry_buttons: Array[Button] = []
var _compact_focus_chain: Array[Button] = []
var _summary_column: VBoxContainer
var _title_label: Label
var _subtitle_label: Label
var _source_label: Label
var _town_summary_label: Label
var _llm_summary_label: Label
var _audio_summary_label: Label
var _content_summary_label: Label
var _save_panel: PanelContainer
var _save_heading_label: Label
var _save_reason_label: Label
var _save_create_button: Button
var _continue_button: Button
var _operation_label: Label
var _footer_grid: GridContainer
var _save_actions: GridContainer
var _return_start_button: Button
var _quit_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	_build_desktop_composition()
	_refresh_from_adapter()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_render()


func _unhandled_input(event: InputEvent) -> void:
	if (
		not is_visible_in_tree()
		or not is_processing_unhandled_input()
		or not _lifecycle_is_paused()
		or not event is InputEventKey
		or not event.pressed
		or event.echo
	):
		return
	if event.keycode == KEY_ESCAPE:
		_request_action("returnGame")
		get_viewport().set_input_as_handled()


func bind_town_ui_adapter(adapter: Node) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	_adapter = adapter
	_view_models.clear()
	_last_confirmed_data.clear()
	_revision_by_scope.clear()
	_confirmed_revision_by_scope.clear()
	_rendered_revision_by_scope.clear()
	_local_operation.clear()
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	if is_node_ready():
		_refresh_from_adapter()
		_render()
		_queue_responsive_layout()


func unbind_town_ui_adapter() -> void:
	_disconnect_adapter()
	_adapter = null
	_view_models.clear()
	_last_confirmed_data.clear()
	_revision_by_scope.clear()
	_confirmed_revision_by_scope.clear()
	_rendered_revision_by_scope.clear()
	_local_operation.clear()
	if is_node_ready():
		_render()


func apply_view_model(view_model: Dictionary) -> bool:
	var scope := str(view_model.get("scope", ""))
	if not REQUIRED_SCOPES.has(scope):
		push_error("暂停菜单拒绝未知 scope：%s" % scope)
		return false
	var issues := UiViewModel.validate(view_model, "暂停菜单/%s" % scope)
	if not issues.is_empty():
		for issue: String in issues:
			push_error(issue)
		return false
	var revision := int(view_model.get("revision", 0))
	if revision < int(_revision_by_scope.get(scope, -1)):
		return false
	var render_snapshot := view_model.duplicate(true)
	var incoming_data := (view_model.get("data", {}) as Dictionary).duplicate(true)
	var confirmed_data := (
		_last_confirmed_data.get(scope, {}) as Dictionary
	).duplicate(true)
	var operation_status := str(
		(view_model.get("operation", {}) as Dictionary).get("status", "idle")
	)
	var preserve_confirmed := (
		_last_confirmed_data.has(scope)
		and (
			operation_status in ["loading", "rejected", "error"]
			or (operation_status == "success" and incoming_data.is_empty())
		)
	)
	var render_data := (
		confirmed_data.duplicate(true)
		if preserve_confirmed
		else incoming_data.duplicate(true)
	)
	var rendered_revision := (
		int(_confirmed_revision_by_scope.get(scope, revision))
		if preserve_confirmed
		else revision
	)
	render_snapshot["data"] = render_data
	render_snapshot["revision"] = rendered_revision
	_view_models[scope] = render_snapshot
	_revision_by_scope[scope] = revision
	_rendered_revision_by_scope[scope] = rendered_revision
	if scope == "save":
		var operation := view_model.get("operation", {}) as Dictionary
		if str(operation.get("status", "idle")) != "loading":
			_save_create_submission_pending = false
		if str(operation.get("intent", "")) == "save.create":
			_local_operation.clear()
	elif scope == "pause_menu" and not _local_operation.is_empty():
		var pause_operation := view_model.get("operation", {}) as Dictionary
		if (
			str(pause_operation.get("intent", ""))
			== str(_local_operation.get("intent", ""))
			and str(pause_operation.get("status", "idle")) != "loading"
		):
			_local_operation.clear()
	if not preserve_confirmed:
		_last_confirmed_data[scope] = render_data.duplicate(true)
		_confirmed_revision_by_scope[scope] = revision
	if is_node_ready():
		_queue_render()
	return true


func present_host_result(intent: String, result: Dictionary) -> void:
	var ok := bool(result.get("ok", false))
	var status := "success" if ok else (
		"error" if bool(result.get("retryable", false)) else "rejected"
	)
	var text_value := "操作已完成"
	if not ok:
		text_value = _player_message_for_reason(
			str(result.get("errorCode", "ACTION_REJECTED"))
		)
	elif intent == "pause_menu.return_to_start":
		text_value = "小镇已保存，正在返回主菜单……"
	elif intent == "pause_menu.quit_game":
		text_value = "小镇已保存，正在退出游戏……"
	_set_local_operation(intent, status, text_value)


func debug_snapshot() -> Dictionary:
	var pause_data := _scope_data("pause_menu")
	var session_data := _scope_data("session")
	var content_data := pause_data.get("contentSummary", {}) as Dictionary
	var resident_count := int(session_data.get("residentCount", 0))
	var resident_capacity := int(
		session_data.get(
			"residentCapacity",
			content_data.get("residentCapacity", 0)
		)
	)
	var desktop_active := _desktop_root.visible
	var active_shell := _desktop_root if desktop_active else _shell
	var active_operation := (
		_desktop_operation_label.text
		if desktop_active
		else _operation_label.text
	)
	return {
		"sourceMode": "town_ui_adapter",
		"source": str(pause_data.get("source", "")),
		"capabilityMode": str(pause_data.get("capabilityMode", "")),
		"formalReady": bool(pause_data.get("formalReady", false)),
		"layoutMode": LayoutMode.keys()[_layout_mode],
		"scopes": _view_models.keys(),
		"incomingRevisionByScope": _revision_by_scope.duplicate(true),
		"confirmedRevisionByScope": _confirmed_revision_by_scope.duplicate(true),
		"renderedRevisionByScope": _rendered_revision_by_scope.duplicate(true),
		"themeVariation": (
			"PauseMenuCompleteDesktop"
			if desktop_active
			else str(_shell.theme_type_variation)
		),
		"bodyColumns": _body_grid.columns,
		"footerColumns": _footer_grid.columns,
		"saveActionColumns": _save_actions.columns,
		"shellRect": Rect2(
			active_shell.position,
			active_shell.size * active_shell.scale
		),
		"layoutViewport": _last_layout_viewport,
		"requestedShellRect": _last_requested_shell_rect,
		"minimumSizes": {
			"shell": _shell.get_combined_minimum_size(),
			"page": (
				(_shell.get_child(0) as Control).get_combined_minimum_size()
			),
			"bodyScroll": _body_scroll.get_combined_minimum_size(),
			"bodyGrid": _body_grid.get_combined_minimum_size(),
			"entries": _entry_list.get_combined_minimum_size(),
			"summary": _summary_column.get_combined_minimum_size(),
			"footer": _footer_grid.get_combined_minimum_size(),
		},
		"operationText": active_operation,
		"touchTargetHeight": TOUCH_TARGET_MIN,
		"saveDisabledStable": (
			_save_create_button != null
			and _save_create_button.disabled
			and _continue_button != null
			and _continue_button.disabled
			and _desktop_save_create_button != null
			and _desktop_save_create_button.disabled
			and _desktop_continue_button != null
			and _desktop_continue_button.disabled
		),
		"savePresentation": _save_presentation(_scope_vm("save")),
		"saveUsesLockedVisual": (
			_layout_mode == LayoutMode.DESKTOP
			and not _save_is_available(_scope_vm("save"))
		),
		"inlineSaveStatus": true,
		"compactSaveHeadingText": (
			_save_heading_label.text if _save_heading_label != null else ""
		),
		"compactSaveReasonText": (
			_save_reason_label.text if _save_reason_label != null else ""
		),
		"saveCreate": {
			"desktopDisabled": _desktop_save_create_button.disabled,
			"desktopFocusMode": _desktop_save_create_button.focus_mode,
			"compactDisabled": _save_create_button.disabled,
			"compactFocusMode": _save_create_button.focus_mode,
			"submissionPending": _save_create_submission_pending,
			"action": UiViewModel.action(_scope_vm("save"), "create"),
		},
		"inSessionContinue": {
			"desktopDisabled": _desktop_continue_button.disabled,
			"desktopFocusMode": _desktop_continue_button.focus_mode,
			"compactDisabled": _continue_button.disabled,
			"compactFocusMode": _continue_button.focus_mode,
			"disabledReason": IN_SESSION_CONTINUE_DISABLED_REASON,
			"visible": (
				_desktop_continue_button.visible
				or _continue_button.visible
			),
		},
		"desktopCompleteShellVisible": _desktop_root.visible,
		"legacyShellVisible": _shell.visible,
		"approvedCompositionScale": _desktop_root.scale,
		"visiblePauseContentOwnerCount": (
			int(_desktop_root.visible) + int(_shell.visible)
		),
		"desktopButtonRects": _desktop_button_rects(),
		"residentCount": resident_count,
		"residentCapacity": resident_capacity,
		"desktopSummaryText": (
			_desktop_summary_label.text
			if _desktop_summary_label != null
			else ""
		),
		"desktopSaveHeadingText": (
			_desktop_save_heading_label.text
			if _desktop_save_heading_label != null
			else ""
		),
		"desktopReturnStartText": (
			_desktop_return_start_button.text
			if _desktop_return_start_button != null
			else ""
		),
		"desktopQuitText": (
			_desktop_quit_button.text
			if _desktop_quit_button != null
			else ""
		),
		"focusOrder": _focus_chain_names(
			_desktop_focus_chain
			if desktop_active
			else _compact_focus_chain
		),
	}


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_view_model_changed"),
	)


func _refresh_from_adapter() -> void:
	if _adapter == null or not _adapter.has_method("get_view_model"):
		return
	for scope: String in REQUIRED_SCOPES:
		var snapshot: Variant = _adapter.call("get_view_model", scope)
		if snapshot is Dictionary:
			apply_view_model(snapshot as Dictionary)


func _on_view_model_changed(scope: String, view_model: Dictionary) -> void:
	if REQUIRED_SCOPES.has(scope):
		apply_view_model(view_model)


func _build_interface() -> void:
	theme = PageTheme.create()
	var scrim := ColorRect.new()
	scrim.color = COLOR_SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	_shell = PanelContainer.new()
	_shell.name = "PauseMenuShell"
	_shell.theme_type_variation = &"PauseMenuShellDesktop"
	_shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shell)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	_shell.add_child(page)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	page.add_child(header)

	_title_label = _make_label("暂停菜单", 48, COLOR_INK)
	_title_label.name = "PageTitle"
	_title_label.add_theme_constant_override("outline_size", 1)
	_title_label.add_theme_color_override(
		"font_outline_color",
		Color("fff8e6")
	)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_title_label)
	_subtitle_label = _make_label("小镇时间已停下，可以安心调整。", 24, COLOR_MUTED)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_subtitle_label)
	_source_label = _make_label("", 16, COLOR_MUTED)
	_source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_source_label)

	_body_scroll = ScrollContainer.new()
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_body_scroll)

	_body_grid = GridContainer.new()
	_body_grid.columns = 2
	_body_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_grid.add_theme_constant_override("h_separation", 24)
	_body_grid.add_theme_constant_override("v_separation", 16)
	_body_scroll.add_child(_body_grid)

	_entry_list = VBoxContainer.new()
	_entry_list.name = "MenuEntries"
	_entry_list.add_theme_constant_override("separation", 12)
	_entry_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_grid.add_child(_entry_list)

	_summary_column = VBoxContainer.new()
	_summary_column.name = "TownSummary"
	_summary_column.add_theme_constant_override("separation", 12)
	_summary_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_grid.add_child(_summary_column)
	_build_summary_column()

	_footer_grid = GridContainer.new()
	_footer_grid.columns = 3
	_footer_grid.add_theme_constant_override("h_separation", 16)
	_footer_grid.add_theme_constant_override("v_separation", 12)
	page.add_child(_footer_grid)

	_operation_label = _make_label("", 24, COLOR_MUTED)
	_operation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_operation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer_grid.add_child(_operation_label)

	_return_start_button = _make_button("返回标题", "quiet")
	_return_start_button.name = "CompactReturnStart"
	_return_start_button.pressed.connect(_request_action.bind("returnToStart"))
	_footer_grid.add_child(_return_start_button)
	_quit_button = _make_button("退出游戏", "danger")
	_quit_button.name = "CompactQuit"
	_quit_button.pressed.connect(_request_action.bind("quitGame"))
	_footer_grid.add_child(_quit_button)


func _build_desktop_composition() -> void:
	_desktop_root = Control.new()
	_desktop_root.name = "PauseMenuCompleteDesktop"
	_desktop_root.size = DESKTOP_SHELL_SIZE
	_desktop_root.visible = false
	_desktop_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_desktop_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_desktop_root)

	var shell_texture := ResourceLoader.load(
		DESKTOP_SHELL_TEXTURE_PATH,
		"Texture2D"
	) as Texture2D
	if shell_texture == null:
		push_error("暂停菜单完整桌面底板加载失败：%s" % DESKTOP_SHELL_TEXTURE_PATH)
	else:
		var shell_visual := TextureRect.new()
		shell_visual.name = "CompleteDesktopShellTexture"
		shell_visual.texture = shell_texture
		shell_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shell_visual.stretch_mode = TextureRect.STRETCH_KEEP
		shell_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		shell_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shell_visual.position = Vector2.ZERO
		shell_visual.size = DESKTOP_SHELL_SIZE
		_desktop_root.add_child(shell_visual)

	_desktop_title_label = _place_desktop_label(
		"暂停菜单",
		Rect2(380, 160, 912, 82),
		36,
		COLOR_INK,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_desktop_title_label.name = "DesktopPageTitle"
	_desktop_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desktop_subtitle_label = _place_desktop_label(
		"",
		Rect2(0, 0, 1, 1),
		16,
		COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_desktop_subtitle_label.visible = false

	var entry_layout := [
		{
			"id": "return_game",
			"label": "继续游戏",
			"rect": Rect2(297, 267, 520, 105),
			"tone": "primary",
		},
		{
			"id": "save_game",
			"label": "保存游戏",
			"rect": Rect2(297, 382, 520, 105),
			"tone": "quiet",
		},
		{
			"id": "load_game",
			"label": "加载游戏",
			"rect": Rect2(297, 497, 520, 105),
			"tone": "quiet",
		},
		{
			"id": "game_settings",
			"label": "游戏设置",
			"rect": Rect2(297, 612, 520, 105),
			"tone": "quiet",
		},
	]
	for spec_value: Variant in entry_layout:
		var spec := spec_value as Dictionary
		var entry_id := str(spec["id"])
		var button := _make_desktop_button(
			str(spec["label"]),
			spec["rect"] as Rect2,
			133.0,
			str(spec["tone"])
		)
		button.name = "DesktopEntry_%s" % entry_id
		button.pressed.connect(_on_entry_pressed.bind(entry_id))
		_desktop_root.add_child(button)
		_desktop_entry_buttons[entry_id] = button

	_desktop_summary_label = _place_desktop_label(
		"",
		Rect2(1018, 286, 336, 180),
		28,
		COLOR_INK,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_desktop_summary_label.name = "DesktopTownSummary"
	_desktop_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desktop_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_summary_label.max_lines_visible = 3
	_desktop_summary_label.add_theme_constant_override("line_spacing", 8)
	_desktop_source_badge_label = _place_desktop_label(
		"",
		Rect2(0, 0, 1, 1),
		14,
		COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_desktop_source_badge_label.name = "DesktopSourceBadge"
	_desktop_source_badge_label.visible = false

	var save_card := MarginContainer.new()
	save_card.name = "DesktopSaveCardTextSafeArea"
	save_card.position = Vector2(1014, 516)
	save_card.size = Vector2(336, 188)
	for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		save_card.add_theme_constant_override(side, 12)
	save_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desktop_root.add_child(save_card)
	var save_stack := VBoxContainer.new()
	save_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	save_stack.add_theme_constant_override("separation", 8)
	save_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_card.add_child(save_stack)

	_desktop_save_heading_label = _make_desktop_card_label("", 28, COLOR_INK)
	_desktop_save_heading_label.name = "DesktopSaveHeading"
	_desktop_save_heading_label.max_lines_visible = 1
	save_stack.add_child(_desktop_save_heading_label)

	_desktop_save_label = _make_desktop_card_label("", 28, COLOR_INK)
	_desktop_save_label.name = "DesktopSaveReason"
	_desktop_save_label.max_lines_visible = 1
	save_stack.add_child(_desktop_save_label)
	_desktop_save_code_label = _place_desktop_label(
		"",
		Rect2(0, 0, 1, 1),
		13,
		COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_desktop_save_code_label.name = "DesktopSaveCode"
	_desktop_save_code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desktop_save_code_label.max_lines_visible = 1
	_desktop_save_code_label.visible = false

	_desktop_operation_label = _make_desktop_card_label("", 28, COLOR_MUTED)
	_desktop_operation_label.name = "DesktopOperationStatus"
	_desktop_operation_label.max_lines_visible = 1
	save_stack.add_child(_desktop_operation_label)

	_desktop_save_create_button = _make_desktop_button(
		"",
		Rect2(844, 500, 258, 180),
		0.0,
		"disabled"
	)
	_desktop_save_create_button.name = "DesktopSaveCreateDisabled"
	_desktop_save_create_button.tooltip_text = (
		"保存当前小镇：%s" % SAVE_ERROR_CODE
	)
	_desktop_save_create_button.focus_mode = Control.FOCUS_NONE
	_desktop_save_create_button.visible = false
	_desktop_save_create_button.pressed.connect(_request_save_create)
	_desktop_root.add_child(_desktop_save_create_button)
	_desktop_continue_button = _make_desktop_button(
		"",
		Rect2(1102, 500, 258, 180),
		0.0,
		"disabled"
	)
	_desktop_continue_button.name = "DesktopContinueDisabled"
	_desktop_continue_button.tooltip_text = (
		"继续上次游戏：%s" % SAVE_ERROR_CODE
	)
	_desktop_continue_button.focus_mode = Control.FOCUS_NONE
	_desktop_continue_button.disabled = true
	_desktop_continue_button.visible = false
	_desktop_root.add_child(_desktop_continue_button)
	_desktop_save_create_button.move_to_front()
	_desktop_continue_button.move_to_front()
	_desktop_save_code_label.move_to_front()

	_desktop_return_start_button = _make_desktop_button(
		"返回标题",
		Rect2(383, 786, 408, 100),
		102.0,
		"quiet"
	)
	_desktop_return_start_button.name = "DesktopReturnStart"
	_desktop_return_start_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desktop_return_start_button.add_theme_font_size_override("font_size", 32)
	_make_button_text_transparent(_desktop_return_start_button)
	_desktop_return_start_button.pressed.connect(
		_request_action.bind("returnToStart")
	)
	_desktop_root.add_child(_desktop_return_start_button)
	var return_start_text := _place_desktop_label(
		"返回标题",
		Rect2(486, 801, 286, 74),
		32,
		COLOR_INK,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	return_start_text.name = "DesktopReturnStartText"
	return_start_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desktop_quit_button = _make_desktop_button(
		"退出游戏",
		Rect2(875, 786, 418, 100),
		134.0,
		"danger"
	)
	_desktop_quit_button.name = "DesktopQuit"
	_desktop_quit_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desktop_quit_button.add_theme_font_size_override("font_size", 32)
	_make_button_text_transparent(_desktop_quit_button)
	_desktop_quit_button.pressed.connect(_request_action.bind("quitGame"))
	_desktop_root.add_child(_desktop_quit_button)
	var quit_text := _place_desktop_label(
		"退出游戏",
		Rect2(994, 801, 296, 74),
		32,
		COLOR_INK,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	quit_text.name = "DesktopQuitText"
	quit_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_summary_column() -> void:
	var summary_panel := PanelContainer.new()
	summary_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(COLOR_PAPER_ALT, COLOR_WOOD, 4)
	)
	_summary_column.add_child(summary_panel)
	var summary := VBoxContainer.new()
	summary.add_theme_constant_override("separation", 8)
	summary_panel.add_child(summary)
	summary.add_child(_make_label("当前小镇", 32, COLOR_INK))
	_town_summary_label = _make_body_label()
	summary.add_child(_town_summary_label)
	_llm_summary_label = _make_body_label()
	summary.add_child(_llm_summary_label)
	_audio_summary_label = _make_body_label()
	summary.add_child(_audio_summary_label)
	_content_summary_label = _make_body_label()
	summary.add_child(_content_summary_label)

	_save_panel = PanelContainer.new()
	_save_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(COLOR_DISABLED, COLOR_MUTED, 4)
	)
	_summary_column.add_child(_save_panel)
	var save_content := VBoxContainer.new()
	save_content.add_theme_constant_override("separation", 8)
	_save_panel.add_child(save_content)
	_save_heading_label = _make_label("存档暂不可用", 32, COLOR_INK)
	_save_heading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_content.add_child(_save_heading_label)
	_save_reason_label = _make_body_label()
	_save_reason_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_save_reason_label.clip_text = true
	_save_reason_label.max_lines_visible = 2
	save_content.add_child(_save_reason_label)
	_save_actions = GridContainer.new()
	_save_actions.columns = 2
	_save_actions.add_theme_constant_override("h_separation", 12)
	_save_actions.add_theme_constant_override("v_separation", 12)
	save_content.add_child(_save_actions)
	_save_create_button = _make_button("保存当前小镇", "quiet")
	_save_create_button.name = "CompactSaveCreateDisabled"
	_save_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_create_button.pressed.connect(_request_save_create)
	_save_actions.add_child(_save_create_button)
	_continue_button = _make_button("继续上次游戏", "disabled")
	_continue_button.name = "CompactContinueDisabled"
	_continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_button.disabled = true
	_continue_button.focus_mode = Control.FOCUS_NONE
	_continue_button.visible = false
	_save_actions.add_child(_continue_button)


func _render() -> void:
	if _shell == null:
		return
	var pause_vm := _scope_vm("pause_menu")
	var pause_data := pause_vm.get("data", {}) as Dictionary
	var session_data := _scope_data("session")
	var save_vm := _scope_vm("save")
	var content := pause_data.get("contentSummary", {}) as Dictionary
	var resident_count := int(session_data.get("residentCount", 0))
	var resident_capacity := int(
		session_data.get(
			"residentCapacity",
			content.get("residentCapacity", 0)
		)
	)
	var resident_summary := (
		"%d / %d 位" % [resident_count, resident_capacity]
		if resident_capacity > 0
		else "%d 位" % resident_count
	)

	var formal_ready := bool(pause_data.get("formalReady", false))
	_source_label.text = (
		"正式小镇"
		if formal_ready
		else "开发占位 · formalReady=false"
	)
	var entries := pause_data.get("entries", []) as Array
	_rebuild_entries(entries)
	_render_desktop_entries(entries)

	var paused := bool(_scope_data("lifecycle").get("paused", false))
	_town_summary_label.text = (
		"状态：%s" % ("已暂停" if paused else "未暂停")
		+ "　居民：%s" % resident_summary
	)
	var llm := pause_data.get("llmSummary", {}) as Dictionary
	_llm_summary_label.text = (
		"LLM：%s　Provider：%d"
		% [str(llm.get("status", "unavailable")), int(llm.get("providerCount", 0))]
	)
	var audio := pause_data.get("audioVideoSummary", {}) as Dictionary
	_audio_summary_label.text = (
		"主音量：%d%%　静音：%s"
		% [
			roundi(float(audio.get("masterVolume", 0.0)) * 100.0),
			"是" if bool(audio.get("muted", false)) else "否",
		]
	)
	_content_summary_label.text = (
		"地图包：%s　居民：%s"
		% [
			str(content.get("mapPackName", "未接入")),
			resident_summary,
		]
	)
	var current_town := pause_data.get("currentTownSummary", {}) as Dictionary
	var town_name := str(current_town.get("slotName", "当前小镇"))
	var day := int(current_town.get("day", 0))
	var clock := str(current_town.get("clock", "--:--"))
	var weather := str(current_town.get("weatherLabel", "天气未知"))
	var mode_label := str(current_town.get("avatarModeLabel", "观察模式"))
	_desktop_summary_label.text = (
		"当前小镇 · %s\n第%d天 · %s · %s\n%d位居民 · %s"
	) % [town_name, day, weather, clock, resident_count, mode_label]

	var save_presentation := _save_presentation(save_vm)
	_save_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(
			COLOR_PAPER_ALT if _save_is_available(save_vm) else COLOR_DISABLED,
			COLOR_WOOD if _save_is_available(save_vm) else COLOR_MUTED,
			4
		)
	)
	_save_heading_label.text = str(save_presentation.get("heading", "存档状态"))
	_save_reason_label.text = str(save_presentation.get("detail", ""))
	_desktop_save_heading_label.text = "存档状态"
	_desktop_save_label.text = _desktop_save_detail(save_presentation)
	_desktop_save_code_label.text = ""
	_apply_save_create_button_state(save_vm, _save_create_button)
	_apply_in_session_continue_state(_continue_button)
	_apply_save_create_button_state(save_vm, _desktop_save_create_button)
	_apply_in_session_continue_state(_desktop_continue_button)
	_render_operation(pause_vm, save_vm)
	_apply_action_button_state("returnToStart", _return_start_button)
	_apply_action_button_state("quitGame", _quit_button)
	_apply_action_button_state("returnToStart", _desktop_return_start_button)
	_apply_action_button_state("quitGame", _desktop_quit_button)
	_configure_focus_chains()
	_queue_initial_focus()
	_queue_responsive_layout()


func _rebuild_entries(entries: Array) -> void:
	_compact_entry_buttons.clear()
	UiNodeRetirement.retire_children(_entry_list)
	if entries.is_empty():
		var unavailable := _make_label(
			"暂停菜单尚未接入正式 TownUiAdapter scope。",
			32,
			COLOR_MUTED,
		)
		unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_entry_list.add_child(unavailable)
		return
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var entry_id := str(entry.get("id", ""))
		var tone := str(entry.get("tone", "quiet"))
		if entry_id == "save_game" and _save_is_available(_scope_vm("save")):
			tone = "quiet"
		var button := _make_button(str(entry.get("label", entry_id)), tone)
		button.name = "CompactEntry_%s" % entry_id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_entry_pressed.bind(entry_id))
		var action_key := str(ENTRY_ACTION_KEYS.get(entry_id, ""))
		var action := _pause_action(action_key)
		button.disabled = not _entry_is_enabled(
		entry_id,
			tone,
			action
		)
		button.focus_mode = (
			Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		)
		_entry_list.add_child(button)
		_compact_entry_buttons.append(button)


func _render_desktop_entries(entries: Array) -> void:
	for button_value: Variant in _desktop_entry_buttons.values():
		if button_value is Button:
			var button := button_value as Button
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var entry_id := str(entry.get("id", ""))
		var button_value: Variant = _desktop_entry_buttons.get(entry_id)
		if not button_value is Button:
			continue
		var button := button_value as Button
		button.text = str(entry.get("label", entry_id))
		var tone := str(entry.get("tone", "quiet"))
		var action_key := str(ENTRY_ACTION_KEYS.get(entry_id, ""))
		var action := _pause_action(action_key)
		button.disabled = not _entry_is_enabled(
			entry_id,
			tone,
			action
		)
		button.focus_mode = (
			Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		)


func _on_entry_pressed(entry_id: String) -> void:
	if entry_id == "save_game":
		_request_save_create()
		return
	var entry := _entry_definition(entry_id)
	if str(entry.get("tone", "")) == "disabled":
		var disabled_action_key := str(ENTRY_ACTION_KEYS.get(entry_id, ""))
		var action := _pause_action(disabled_action_key)
		var intent := str(action.get("intent", ""))
		var reason := str(
			entry.get(
				"disabledReason",
				action.get("disabledReason", SAVE_ERROR_CODE)
			)
		)
		_set_local_operation(
			intent,
			"rejected",
			_player_message_for_reason(
				reason if not reason.is_empty() else SAVE_ERROR_CODE
			)
		)
		action_blocked.emit(
			intent,
			reason if not reason.is_empty() else SAVE_ERROR_CODE
		)
		return
	var action_key := str(ENTRY_ACTION_KEYS.get(entry_id, ""))
	if not action_key.is_empty():
		_request_action(action_key)


func _entry_definition(entry_id: String) -> Dictionary:
	var entries := _scope_data("pause_menu").get("entries", []) as Array
	for entry_value: Variant in entries:
		if entry_value is Dictionary:
			var entry := entry_value as Dictionary
			if str(entry.get("id", "")) == entry_id:
				return entry
	return {}


func _request_action(action_key: String) -> void:
	var action := _pause_action(action_key)
	if action.is_empty():
		_set_local_operation("", "rejected", "当前操作不可用")
		action_blocked.emit("", "MISSING_ACTION")
		return
	var intent := str(action.get("intent", ""))
	var enabled := bool(action.get("enabled", true))
	var reason := str(action.get("disabledReason", ""))
	if action_key == "returnGame" and not _lifecycle_is_paused():
		_set_local_operation("lifecycle.resume", "rejected", "小镇当前没有暂停")
		action_blocked.emit("lifecycle.resume", "WORLD_NOT_PAUSED")
		return
	if not enabled or intent.is_empty():
		_set_local_operation(
			intent,
			"rejected",
			_player_message_for_reason(
				reason if not reason.is_empty() else "ACTION_DISABLED"
			)
		)
		action_blocked.emit(intent, reason if not reason.is_empty() else "ACTION_DISABLED")
		return
	var payload_value: Variant = action.get("payload", {})
	var payload := {} if not payload_value is Dictionary else (
		payload_value as Dictionary
	).duplicate(true)
	match intent:
		"pause_menu.return_to_start":
			_set_local_operation(intent, "loading", "正在保存并返回主菜单……")
		"pause_menu.quit_game":
			_set_local_operation(intent, "loading", "正在保存并退出游戏……")
		"pause_menu.open_audio_video":
			_set_local_operation(intent, "loading", "正在打开游戏设置……")
		"pause_menu.open_load_game":
			_set_local_operation(intent, "loading", "正在读取本地存档……")
	intent_requested.emit(intent, payload.duplicate(true))
	if _adapter != null and _adapter.has_method("dispatch"):
		_adapter.call("dispatch", intent, payload)


func _request_save_create() -> void:
	var action := UiViewModel.action(_scope_vm("save"), "create")
	var intent := str(action.get("intent", ""))
	if _save_create_submission_pending:
		_set_local_operation(intent, "loading", "保存正在进行，请稍候……")
		action_blocked.emit(intent, SAVE_CREATE_ALREADY_PENDING)
		return
	var reason := str(action.get("disabledReason", ""))
	if (
		action.is_empty()
		or intent != "save.create"
		or not bool(action.get("enabled", false))
	):
		_set_local_operation(
			intent,
			"rejected",
			_player_message_for_reason(
				reason if not reason.is_empty() else "ACTION_DISABLED"
			)
		)
		action_blocked.emit(
			intent,
			reason if not reason.is_empty() else "ACTION_DISABLED"
		)
		return
	var payload_value: Variant = action.get("payload", {})
	var payload := (
		(payload_value as Dictionary).duplicate(true)
		if payload_value is Dictionary
		else {}
	)
	_local_operation.clear()
	_save_create_submission_pending = true
	_queue_render()
	intent_requested.emit(intent, payload.duplicate(true))
	if _adapter != null and _adapter.has_method("dispatch"):
		_adapter.call("dispatch", intent, payload)


func _pause_action(action_key: String) -> Dictionary:
	if action_key.is_empty():
		return {}
	return UiViewModel.action(_scope_vm("pause_menu"), action_key)


func _entry_is_enabled(
	entry_id: String,
	tone: String,
	action: Dictionary
) -> bool:
	if entry_id == "save_game":
		return _save_is_available(_scope_vm("save"))
	return (
		tone != "disabled"
		and not action.is_empty()
		and bool(action.get("enabled", true))
	)


func _apply_action_button_state(action_key: String, button: Button) -> void:
	var action := _pause_action(action_key)
	button.disabled = action.is_empty() or not bool(action.get("enabled", true))
	button.focus_mode = (
		Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
	)


func _apply_save_create_button_state(
	save_vm: Dictionary,
	button: Button
) -> void:
	var action := UiViewModel.action(save_vm, "create")
	var disabled_reason := str(action.get("disabledReason", ""))
	button.disabled = (
		_save_create_submission_pending
		or action.is_empty()
		or str(action.get("intent", "")) != "save.create"
		or not bool(action.get("enabled", false))
	)
	button.focus_mode = (
		Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
	)
	button.text = str(
		_save_presentation(save_vm).get("buttonLabel", "保存当前小镇")
	)
	button.tooltip_text = (
		_player_message_for_reason(disabled_reason)
		if button.disabled and not disabled_reason.is_empty()
		else ("保存正在进行" if _save_create_submission_pending else "")
	)
	button.mouse_default_cursor_shape = (
		Control.CURSOR_FORBIDDEN
		if button.disabled
		else Control.CURSOR_POINTING_HAND
	)


func _apply_in_session_continue_state(button: Button) -> void:
	button.disabled = true
	button.focus_mode = Control.FOCUS_NONE
	button.visible = false
	button.tooltip_text = IN_SESSION_CONTINUE_DISABLED_REASON
	button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN


func _render_operation(pause_vm: Dictionary, save_vm: Dictionary) -> void:
	var operation := pause_vm.get("operation", {}) as Dictionary
	var save_operation := save_vm.get("operation", {}) as Dictionary
	var save_status := str(save_operation.get("status", "idle"))
	var save_has_request := not str(save_operation.get("requestId", "")).is_empty()
	if _save_create_submission_pending or (save_status != "idle" and save_has_request):
		operation = save_operation
	if not _local_operation.is_empty():
		operation = _local_operation
	var status := str(operation.get("status", "disabled"))
	var operation_text := str(operation.get("displayText", ""))
	if operation_text.is_empty() and operation == save_operation:
		operation_text = str(
			_save_presentation(save_vm).get("operationText", "")
		)
	if operation_text.is_empty():
		operation_text = str(OPERATION_LABELS.get(status, OPERATION_LABELS.disabled))
	_operation_label.text = operation_text
	_desktop_operation_label.text = (
		operation_text
		if not _local_operation.is_empty()
		else _desktop_save_operation_text(save_vm)
	)
	match status:
		"idle":
			_operation_label.add_theme_color_override("font_color", COLOR_INK)
			_desktop_operation_label.add_theme_color_override(
				"font_color",
				COLOR_INK
			)
		"success":
			_operation_label.add_theme_color_override("font_color", COLOR_MOSS)
			_desktop_operation_label.add_theme_color_override(
				"font_color",
				COLOR_MOSS
			)
		"rejected", "error":
			_operation_label.add_theme_color_override("font_color", COLOR_ERROR)
			_desktop_operation_label.add_theme_color_override(
				"font_color",
				COLOR_ERROR
			)
		_:
			_operation_label.add_theme_color_override("font_color", COLOR_MUTED)
			_desktop_operation_label.add_theme_color_override(
				"font_color",
				COLOR_MUTED
			)


func _save_presentation(save_vm: Dictionary) -> Dictionary:
	var data := save_vm.get("data", {}) as Dictionary
	var action := UiViewModel.action(save_vm, "create")
	var operation := save_vm.get("operation", {}) as Dictionary
	var available := _save_is_available(save_vm)
	var status := str(operation.get("status", "idle"))
	if _save_create_submission_pending:
		status = "loading"
	var confirmed_summary := _confirmed_save_summary(data)
	var error_message := _save_error_player_message(save_vm)
	if not available:
		return {
			"status": "disabled",
			"heading": "存档暂不可用",
			"detail": error_message,
			"buttonLabel": "暂不可保存",
			"operationText": error_message,
			"confirmedSummary": confirmed_summary,
		}
	match status:
		"loading":
			return {
				"status": "loading",
				"heading": "正在保存当前小镇",
				"detail": (
					"上次确认：%s" % confirmed_summary
					if not confirmed_summary.is_empty()
					else "正在建立这座小镇的第一份手动存档"
				),
				"buttonLabel": "正在保存……",
				"operationText": "正在保存当前小镇……",
				"confirmedSummary": confirmed_summary,
			}
		"success":
			return {
				"status": "success",
				"heading": "小镇已保存",
				"detail": (
					confirmed_summary
					if not confirmed_summary.is_empty()
					else "当前进度已经安全保存"
				),
				"buttonLabel": "再次保存",
				"operationText": "小镇已保存",
				"confirmedSummary": confirmed_summary,
			}
		"rejected":
			return _failed_save_presentation(
				"本次保存未完成",
				"本次保存未完成，已保留上次确认进度",
				error_message,
				confirmed_summary,
				"rejected"
			)
		"error":
			return _failed_save_presentation(
				"保存失败",
				"保存失败，已保留上次确认进度",
				error_message,
				confirmed_summary,
				"error"
			)
	var detail := confirmed_summary
	if detail.is_empty():
		detail = "可以保存当前小镇，记录此刻的世界与居民进度"
	return {
		"status": "idle",
		"heading": (
			"当前小镇已保存"
			if not confirmed_summary.is_empty()
			else "可以保存当前小镇"
		),
		"detail": detail,
		"buttonLabel": (
			"再次保存" if not confirmed_summary.is_empty() else "保存当前小镇"
		),
		"operationText": (
			"存档状态已在本页展开"
			if not confirmed_summary.is_empty()
			else "可以保存当前小镇"
		),
		"confirmedSummary": confirmed_summary,
		"actionEnabled": bool(action.get("enabled", false)),
	}


func _failed_save_presentation(
	heading: String,
	operation_text: String,
	error_message: String,
	confirmed_summary: String,
	status: String
) -> Dictionary:
	var detail := error_message
	if not confirmed_summary.is_empty():
		detail += " · 上次确认：%s" % confirmed_summary
	return {
		"status": status,
		"heading": heading,
		"detail": detail,
		"buttonLabel": "重新保存",
		"operationText": operation_text,
		"confirmedSummary": confirmed_summary,
	}


func _desktop_save_detail(presentation: Dictionary) -> String:
	var status := str(presentation.get("status", "idle"))
	var confirmed := str(presentation.get("confirmedSummary", "")).strip_edges()
	match status:
		"disabled":
			return "尚未建立正式存档"
		"loading":
			return (
				"上次确认 · %s" % confirmed
				if not confirmed.is_empty()
				else "正在写入第一份存档"
			)
		"success", "idle":
			return _desktop_confirmed_save_copy(confirmed)
		"rejected", "error":
			return (
				"已保留 · %s" % confirmed
				if not confirmed.is_empty()
				else "当前小镇仍在运行中"
			)
	return str(presentation.get("detail", ""))


func _desktop_confirmed_save_copy(confirmed: String) -> String:
	if confirmed.is_empty():
		return "尚未创建手动存档"
	var date_time_index := confirmed.rfind(" · ")
	if date_time_index >= 0:
		var date_time := confirmed.substr(date_time_index + 3).strip_edges()
		var time_separator := date_time.rfind(" ")
		if time_separator >= 0 and date_time.length() >= time_separator + 6:
			return "最近保存 · %s" % date_time.substr(time_separator + 1, 5)
	return "最近保存 · 已确认"


func _desktop_save_operation_text(save_vm: Dictionary) -> String:
	var presentation := _save_presentation(save_vm)
	var status := str(presentation.get("status", "idle"))
	match status:
		"loading":
			return "正在保存当前进度"
		"success", "idle":
			return (
				"当前进度已安全保存"
				if not str(presentation.get("confirmedSummary", "")).is_empty()
				else "可以随时保存当前进度"
			)
		"rejected", "error":
			return "已保留上次确认存档"
		"disabled":
			return "当前进度仅保留在本局"
	return "存档状态未知"


func _save_is_available(save_vm: Dictionary) -> bool:
	var data := save_vm.get("data", {}) as Dictionary
	var action := UiViewModel.action(save_vm, "create")
	return (
		bool(data.get("canSave", false))
		or (
			str(action.get("intent", "")) == "save.create"
			and bool(action.get("enabled", false))
		)
	)


func _confirmed_save_summary(data: Dictionary) -> String:
	var slots := data.get("slots", []) as Array
	if slots.is_empty():
		return ""
	var selected_save_id := str(data.get("selectedSaveId", ""))
	var selected: Dictionary = {}
	for slot_value: Variant in slots:
		if not slot_value is Dictionary:
			continue
		var slot := slot_value as Dictionary
		if selected.is_empty():
			selected = slot
		if (
			not selected_save_id.is_empty()
			and str(slot.get("saveId", "")) == selected_save_id
		):
			selected = slot
			break
	if selected.is_empty():
		return ""
	var parts: Array[String] = []
	var save_revision := int(
		selected.get("saveRevision", selected.get("revision", 0))
	)
	if save_revision > 0:
		parts.append("第 %d 次保存" % save_revision)
	var saved_at := str(selected.get("savedAt", "")).strip_edges()
	if not saved_at.is_empty():
		parts.append(saved_at.replace("T", " "))
	if parts.is_empty():
		parts.append("已有完整存档")
	return " · ".join(parts)


func _save_error_player_message(save_vm: Dictionary) -> String:
	var error_value: Variant = save_vm.get("error")
	if error_value is Dictionary:
		var error := error_value as Dictionary
		var player_message := str(error.get("playerMessage", "")).strip_edges()
		if not player_message.is_empty():
			return player_message
		var code := str(error.get("code", ""))
		if not code.is_empty():
			return _player_message_for_reason(code)
	var action := UiViewModel.action(save_vm, "create")
	return _player_message_for_reason(str(action.get("disabledReason", "")))


func _player_message_for_reason(reason: String) -> String:
	if reason in [
		"AGENT_SAVE_INTERFACE_MISSING",
		"SESSION_SAVE_SERVICE_NOT_BOUND",
		"SESSION_SAVE_SERVICE_NOT_CONFIGURED",
	]:
		return "存档服务尚未准备好，当前进度仍保留在游戏中"
	match reason:
		"SESSION_SAVE_FORMAL_WORLD_REQUIRED":
			return "当前小镇尚未进入可保存状态"
		"SESSION_SAVE_IDENTITY_NOT_CONFIRMED":
			return "居民身份仍在确认，完成后即可保存"
		"SESSION_SAVE_AGENT_CONTEXT_MISMATCH":
			return "居民进度尚未同步，当前不能保存"
		"SESSION_SAVE_WORLD_PREPARE_FAILED", \
		"WORLD_SAVE_RESTORE_VALIDATION_FAILED":
			return "当前小镇状态暂时无法写入存档，已保留上次确认进度"
		"SESSION_SAVE_STORE_WRITE_FAILED", \
		"SESSION_SAVE_STORE_CLEANUP_FAILED", \
		"SESSION_SAVE_SLOT_LEASE_RELEASE_FAILED":
			return "本机存档目录写入失败，请检查磁盘空间或文件权限后重试"
		"SESSION_SAVE_AGENT_COMMIT_FAILED", \
		"SESSION_SAVE_AGENT_COMMIT_UNCERTAIN":
			return "居民进度写入未完成，已保留上次确认进度"
		"WORLD_DATA_INCOMPLETE":
			return "小镇仍在准备中，完成后即可保存"
		"SAVE_CREATE_ALREADY_PENDING":
			return "保存正在进行，请稍候"
		"PROVIDER_SETTINGS_SERVICE_NOT_BOUND":
			return "LLM 设置当前不可用"
		"ROUTE_NOT_CONNECTED":
			return "该内容已在当前页面显示"
		"SESSION_LOAD_REQUIRES_FORMAL_SESSION":
			return "正式小镇启动后才可加载其他存档"
		"IN_SESSION_LOAD_HOST_UNAVAILABLE", "IN_SESSION_LOAD_ROUTE_FAILED":
			return "加载页面暂时无法打开，当前小镇未受影响"
		"IN_SESSION_DELETE_SLOT_NOT_AVAILABLE":
			return "局内加载页不提供删除存档"
		"":
			return "当前操作暂不可用"
	return "操作未完成，当前进度已保留"


func _set_local_operation(intent: String, status: String, text_value: String) -> void:
	_local_operation = {
		"requestId": "pause-local",
		"intent": intent,
		"status": status,
		"submittedAtMsec": Time.get_ticks_msec(),
		"completedAtMsec": (
			0 if status == "loading" else Time.get_ticks_msec()
		),
		"displayText": text_value,
	}
	if is_node_ready():
		_render_operation(_scope_vm("pause_menu"), _scope_vm("save"))


func _scope_vm(scope: String) -> Dictionary:
	var value: Variant = _view_models.get(scope, {})
	return {} if not value is Dictionary else (value as Dictionary)


func _scope_data(scope: String) -> Dictionary:
	var data_value: Variant = _scope_vm(scope).get("data", {})
	return {} if not data_value is Dictionary else (data_value as Dictionary)


func _lifecycle_is_paused() -> bool:
	return bool(_scope_data("lifecycle").get("paused", false))


func _configure_focus_chains() -> void:
	_desktop_focus_chain.clear()
	for entry_id: String in [
		"return_game",
		"save_game",
		"load_game",
		"game_settings",
	]:
		var button_value: Variant = _desktop_entry_buttons.get(entry_id)
		if button_value is Button:
			var button := button_value as Button
			if not button.disabled:
				_desktop_focus_chain.append(button)
	if (
		_desktop_save_create_button != null
		and _desktop_save_create_button.visible
		and not _desktop_save_create_button.disabled
	):
		_desktop_focus_chain.append(_desktop_save_create_button)
	for footer_button: Button in [
		_desktop_return_start_button,
		_desktop_quit_button,
	]:
		if footer_button != null and not footer_button.disabled:
			_desktop_focus_chain.append(footer_button)
	_set_focus_chain(_desktop_focus_chain)
	if (
		_desktop_return_start_button != null
		and _desktop_quit_button != null
	):
		_desktop_return_start_button.focus_neighbor_right = (
			_desktop_return_start_button.get_path_to(_desktop_quit_button)
		)
		_desktop_quit_button.focus_neighbor_left = (
			_desktop_quit_button.get_path_to(_desktop_return_start_button)
		)

	_compact_focus_chain.clear()
	for button: Button in _compact_entry_buttons:
		if not button.disabled:
			_compact_focus_chain.append(button)
	if _save_create_button != null and not _save_create_button.disabled:
		_compact_focus_chain.append(_save_create_button)
	for footer_button: Button in [_return_start_button, _quit_button]:
		if footer_button != null and not footer_button.disabled:
			_compact_focus_chain.append(footer_button)
	_set_focus_chain(_compact_focus_chain)
	if _return_start_button != null and _quit_button != null:
		_return_start_button.focus_neighbor_right = (
			_return_start_button.get_path_to(_quit_button)
		)
		_quit_button.focus_neighbor_left = (
			_quit_button.get_path_to(_return_start_button)
		)


func _set_focus_chain(chain: Array[Button]) -> void:
	if chain.is_empty():
		return
	for index: int in range(chain.size()):
		var button := chain[index]
		var previous := chain[(index - 1 + chain.size()) % chain.size()]
		var next := chain[(index + 1) % chain.size()]
		button.focus_mode = Control.FOCUS_ALL
		button.focus_previous = button.get_path_to(previous)
		button.focus_next = button.get_path_to(next)
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_neighbor_bottom = button.get_path_to(next)


func _queue_initial_focus() -> void:
	if _initial_focus_queued or not is_inside_tree():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if (
		focus_owner != null
		and focus_owner.is_visible_in_tree()
		and focus_owner.focus_mode != Control.FOCUS_NONE
	):
		return
	_initial_focus_queued = true
	call_deferred("_apply_initial_focus")


func _apply_initial_focus() -> void:
	_initial_focus_queued = false
	var active_chain := (
		_desktop_focus_chain
		if _layout_mode == LayoutMode.DESKTOP
		else _compact_focus_chain
	)
	if active_chain.is_empty():
		return
	var target := active_chain[0]
	if target.is_visible_in_tree() and not target.disabled:
		target.grab_focus()


func _focus_chain_names(chain: Array[Button]) -> Array[String]:
	var names: Array[String] = []
	for button: Button in chain:
		names.append(str(button.name))
	return names


func _apply_responsive_layout() -> void:
	if _shell == null:
		return
	var viewport_size := get_viewport_rect().size
	_last_layout_viewport = viewport_size
	if _uses_formal_approved_composition():
		_apply_formal_approved_layout(viewport_size)
		return
	_desktop_root.scale = Vector2.ONE
	if (
		viewport_size.x >= DESKTOP_MIN_VIEWPORT.x
		and viewport_size.y >= DESKTOP_MIN_VIEWPORT.y
	):
		_layout_mode = LayoutMode.DESKTOP
	elif viewport_size.x >= 1080.0 and viewport_size.y >= 640.0:
		_layout_mode = LayoutMode.STANDARD
	elif viewport_size.x >= viewport_size.y:
		_layout_mode = LayoutMode.COMPACT_LANDSCAPE
	else:
		_layout_mode = LayoutMode.COMPACT_PORTRAIT

	var desktop_active := _layout_mode == LayoutMode.DESKTOP
	_desktop_root.visible = desktop_active
	_shell.visible = not desktop_active
	if desktop_active:
		_desktop_root.size = DESKTOP_SHELL_SIZE
		_desktop_root.position = Vector2(
			floorf((viewport_size.x - DESKTOP_SHELL_SIZE.x) * 0.5),
			floorf((viewport_size.y - DESKTOP_SHELL_SIZE.y) * 0.5)
		)
		_body_grid.columns = 2
		_footer_grid.columns = 3
		_save_actions.columns = 1
		_last_requested_shell_rect = Rect2(
			_desktop_root.position,
			DESKTOP_SHELL_SIZE
		)
		_configure_focus_chains()
		_queue_initial_focus()
		return

	var outer_margin_x := 96.0 if _layout_mode == LayoutMode.DESKTOP else 32.0
	var outer_margin_y := 64.0 if _layout_mode == LayoutMode.DESKTOP else 32.0
	if _layout_mode == LayoutMode.COMPACT_PORTRAIT:
		outer_margin_x = 16.0
		outer_margin_y = 16.0
	var max_size := Vector2(1520.0, 904.0)
	var shell_size := Vector2(
		minf(max_size.x, viewport_size.x - outer_margin_x * 2.0),
		minf(max_size.y, viewport_size.y - outer_margin_y * 2.0)
	)
	shell_size.x = floorf(maxf(shell_size.x, 320.0))
	shell_size.y = floorf(maxf(shell_size.y, 320.0))
	_shell.position = Vector2(
		floorf((viewport_size.x - shell_size.x) * 0.5),
		floorf((viewport_size.y - shell_size.y) * 0.5)
	)
	_shell.size = shell_size
	_last_requested_shell_rect = Rect2(_shell.position, shell_size)

	var is_two_column := _layout_mode == LayoutMode.DESKTOP
	_body_grid.columns = 2 if is_two_column else 1
	_entry_list.custom_minimum_size.x = 440.0 if is_two_column else 0.0
	_summary_column.custom_minimum_size.x = 480.0 if is_two_column else 0.0
	_shell.theme_type_variation = (
		&"PauseMenuShellDesktop"
		if shell_size.x >= 720.0 and shell_size.y >= 520.0
		else &"PauseMenuShellCompact"
	)
	_title_label.add_theme_font_size_override(
		"font_size",
		64 if is_two_column else 48
	)
	var wide_footer := shell_size.x >= 720.0
	_footer_grid.columns = 3 if wide_footer else 1
	_save_actions.columns = 1
	_return_start_button.custom_minimum_size.x = 280.0 if wide_footer else 0.0
	_quit_button.custom_minimum_size.x = 200.0 if wide_footer else 0.0
	_configure_focus_chains()
	_queue_initial_focus()


func _uses_formal_approved_composition() -> bool:
	return true


func _apply_formal_approved_layout(viewport_size: Vector2) -> void:
	_layout_mode = LayoutMode.DESKTOP
	_desktop_root.visible = true
	_shell.visible = false
	_desktop_root.size = DESKTOP_SHELL_SIZE
	var fit_scale := minf(
		viewport_size.x / DESKTOP_SHELL_SIZE.x,
		viewport_size.y / DESKTOP_SHELL_SIZE.y
	)
	fit_scale = clampf(fit_scale, 0.01, APPROVED_DESKTOP_MAX_SCALE)
	_desktop_root.scale = Vector2(fit_scale, fit_scale)
	var fitted_size := DESKTOP_SHELL_SIZE * fit_scale
	_desktop_root.position = Vector2(
		floorf((viewport_size.x - fitted_size.x) * 0.5),
		floorf((viewport_size.y - fitted_size.y) * 0.5)
	)
	_body_grid.columns = 2
	_footer_grid.columns = 3
	_save_actions.columns = 1
	_last_requested_shell_rect = Rect2(
		_desktop_root.position,
		fitted_size
	)
	_configure_focus_chains()
	_queue_initial_focus()


func _queue_responsive_layout() -> void:
	if _layout_refresh_queued:
		return
	_layout_refresh_queued = true
	call_deferred("_apply_queued_responsive_layout")


func _queue_render() -> void:
	if _render_queued or not is_inside_tree():
		return
	_render_queued = true
	call_deferred("_apply_queued_render")


func _apply_queued_render() -> void:
	_render_queued = false
	_render()


func _apply_queued_responsive_layout() -> void:
	_layout_refresh_queued = false
	_apply_responsive_layout()


func _place_desktop_label(
	text_value: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment
) -> Label:
	var label := _make_label(text_value, font_size, color)
	var font := theme.default_font if theme != null else label.get_theme_font("font")
	var line_height := font.get_height(font_size) if font != null else float(font_size)
	var inset := maxf(8.0, ceilf(line_height * 0.25))
	label.position = rect.position + Vector2(inset, inset)
	label.size = rect.size - Vector2(inset * 2.0, inset * 2.0)
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_desktop_root.add_child(label)
	return label


func _make_desktop_card_label(
	text_value: String,
	font_size: int,
	color: Color,
) -> Label:
	var label := _make_label(text_value, font_size, color)
	var font := theme.default_font if theme != null else label.get_theme_font("font")
	label.custom_minimum_size.y = ceilf(font.get_height(font_size))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_desktop_button(
	text_value: String,
	rect: Rect2,
	content_left: float,
	tone: String
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.custom_minimum_size = Vector2(rect.size.x, TOUCH_TARGET_MIN)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 32)
	button.add_theme_color_override("font_color", COLOR_INK)
	button.add_theme_color_override("font_hover_color", COLOR_INK)
	button.add_theme_color_override("font_pressed_color", COLOR_INK)
	button.add_theme_color_override("font_focus_color", COLOR_INK)
	button.add_theme_color_override("font_disabled_color", COLOR_INK)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(
			state,
			_desktop_action_style(state, content_left)
		)
	if tone == "disabled":
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	else:
		_attach_desktop_focus_accent(button, content_left)
	return button


func _make_button_text_transparent(button: Button) -> void:
	var transparent := Color(0.0, 0.0, 0.0, 0.0)
	for color_name: String in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_disabled_color",
	]:
		button.add_theme_color_override(color_name, transparent)


func _desktop_action_style(
	state: String,
	content_left: float
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	if state == "hover":
		style.bg_color = Color(1.0, 0.82, 0.44, 0.12)
	elif state == "pressed":
		style.bg_color = Color(0.50, 0.20, 0.08, 0.14)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = content_left
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _attach_desktop_focus_accent(
	button: Button,
	content_left: float
) -> void:
	var accent := ColorRect.new()
	accent.name = "DesktopFocusAccent"
	accent.color = Color("b9782f")
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var safe_left := maxf(content_left, 16.0)
	accent.position = Vector2(safe_left, button.size.y - 18.0)
	accent.size = Vector2(
		maxf(24.0, button.size.x - safe_left - 16.0),
		4.0
	)
	accent.visible = false
	button.add_child(accent)
	button.focus_entered.connect(accent.show)
	button.focus_exited.connect(accent.hide)


func _desktop_button_rects() -> Dictionary:
	var rects := {}
	if _desktop_root == null:
		return rects
	for child: Node in _desktop_root.get_children():
		if child is Button:
			var button := child as Button
			rects[button.name] = Rect2(button.position, button.size)
	return rects


func _make_body_label() -> Label:
	var label := _make_label("", 24, COLOR_INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text_value: String, tone: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0.0, TOUCH_TARGET_MIN)
	button.add_theme_font_size_override("font_size", 32)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var colors := {
		"normal": COLOR_PAPER_ALT,
		"hover": Color("ffe8b8"),
		"pressed": Color("e3bf83"),
		"disabled": COLOR_DISABLED,
	}
	if tone == "primary":
		colors.normal = COLOR_TERRACOTTA
		colors.hover = Color("cf613e")
		colors.pressed = Color("943821")
	elif tone == "danger":
		colors.normal = COLOR_PAPER_ALT
		colors.hover = Color("e4b095")
		colors.pressed = Color("c78161")
	elif tone == "disabled":
		colors.normal = COLOR_DISABLED
		colors.hover = COLOR_DISABLED
		colors.pressed = COLOR_DISABLED
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(
			state,
			_panel_style(colors[state], COLOR_WOOD, 3)
		)
	button.add_theme_color_override("font_color", COLOR_INK)
	button.add_theme_color_override("font_hover_color", COLOR_INK)
	button.add_theme_color_override("font_pressed_color", COLOR_INK)
	button.add_theme_color_override("font_disabled_color", COLOR_INK)
	return button


func _panel_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 20.0
	style.content_margin_top = 16.0
	style.content_margin_right = 20.0
	style.content_margin_bottom = 16.0
	return style
