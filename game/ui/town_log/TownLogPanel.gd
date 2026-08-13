class_name TownLogPanel
extends Control

const POINTER_INPUT := preload("res://ui/mobile/PointerInput.gd")
const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")


signal intent_requested(intent: StringName, payload: Dictionary)
signal action_blocked(intent: StringName, reason: String)
signal view_model_rejected(reason: String)
signal entry_point_changed(entry_point: Dictionary, attention_is_new: bool)

const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")
const PageTheme := preload("res://ui/town_log/TownLogTheme.gd")
const SCOPE := &"town_log"
const MINIMUM_TOUCH_SIZE := Vector2(48, 48)
const WIDE_BREAKPOINT := 1500.0
const ROW_HOVER_TINT := Color("fff4de")
const ROW_PRESS_TINT := Color("e6c89a")
const ROW_MOTION_SECONDS := 0.08
const DETAIL_REVEAL_SECONDS := 0.12
const REQUIRED_DATA_KEYS: Array[String] = [
	"capabilityMode",
	"source",
	"formalReady",
	"panel",
	"state",
	"errorCode",
	"summary",
	"filters",
	"filterOptions",
	"rows",
	"selectedThreadId",
	"detail",
	"detailPaging",
	"paging",
]
const REQUIRED_ACTION_KEYS: Array[String] = [
	"open",
	"close",
	"setFilter",
	"toggleUnread",
	"selectThread",
	"backToList",
	"loadMore",
	"loadMoreDetail",
	"refreshNewer",
	"retry",
]
const KIND_LABELS := {
	"conversation": "对话",
	"work": "工作",
	"production": "生产",
	"research": "研究",
	"cargo": "搬运",
	"inventory": "库存",
	"commerce": "售卖",
	"service": "服务",
	"message": "消息",
	"mail": "邮递",
	"social": "公共事项",
	"public_matter": "公共事项",
	"commitment": "承诺",
	"announcement": "公告",
	"animal": "动物",
	"activity": "日常活动",
	"daily_activity": "日常活动",
	"weather": "天气",
	"conflict": "冲突",
	"health": "医疗",
	"world_change": "世界变化",
}
const STATUS_LABELS := {
	"ongoing": "进行中",
	"waiting": "等待中",
	"completed": "已完成",
	"interrupted": "已中断",
	"failed": "失败",
	"cancelled": "已取消",
}
const ITEM_LABELS := {
	"coffee_beans": "咖啡豆",
	"flour": "面粉",
	"vegetables": "蔬菜",
	"salt": "盐",
	"lumber": "木材",
	"metal": "金属材料",
	"paper": "纸张",
	"basic_medicine": "基础药品",
	"fish": "鱼货",
	"fresh_flowers": "鲜花",
	"plant_sample": "植物样本",
	"meal": "餐食",
	"brewed_coffee": "咖啡",
	"bread": "面包",
	"pastry": "点心",
	"medicine": "药品",
	"crafted_item": "工坊成品",
	"bouquet": "花束",
	"research_booklet": "研究册",
	"general_goods": "杂货",
}

var _adapter: Object
var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _current_revision := -1
var _layout_profile := "wide"
var _available_rect_override := Rect2()
var _available_panes_override: Array[Rect2] = []
var _safe_insets_override := Vector4(-1, -1, -1, -1)
var _entry_anchor_override := Rect2()
var _last_attention_token := ""
var _last_rendered_selected_id := ""
var _row_controls: Array[Control] = []
var _rendered_rows_signature := ""
var _layout_queued := false
var _focus_controls: Array[Control] = []

var _shell: NinePatchRect
var _frame_overlay: NinePatchRect
var _page_margin: MarginContainer
var _page_content: VBoxContainer
var _header: Control
var _header_row: HBoxContainer
var _back_button: Button
var _title: Label
var _unread_summary: Label
var _refresh_button: Button
var _close_button: Button
var _filter_row: HBoxContainer
var _resident_filter: OptionButton
var _kind_filter: OptionButton
var _day_filter: OptionButton
var _unread_button: Button
var _body: HBoxContainer
var _list_column: VBoxContainer
var _table_header_host: MarginContainer
var _table_header: HBoxContainer
var _list_scroll: ScrollContainer
var _list_content: VBoxContainer
var _list_empty: Label
var _load_more_button: Button
var _detail_shell: NinePatchRect
var _detail_scroll: ScrollContainer
var _detail_content: VBoxContainer
var _detail_load_more_button: Button
var _feedback_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = PageTheme.create()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_interface()
	# resized 与 viewport.size_changed 常在同一帧先后触发，
	# 照 PlaceFocusPanel 的延迟合并模式只跑一次布局。
	resized.connect(_queue_layout)
	get_viewport().size_changed.connect(_queue_layout)
	if _adapter != null:
		_refresh_from_adapter()
	elif _view_model.is_empty():
		apply_view_model(_adapter_missing_view_model())
	else:
		_render()
	_apply_layout()


func _exit_tree() -> void:
	_disconnect_adapter()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and request_back():
		get_viewport().set_input_as_handled()


func bind_town_ui_adapter(adapter: Object) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	_adapter = adapter
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	_current_revision = -1
	if _adapter == null:
		if is_node_ready():
			apply_view_model(_adapter_missing_view_model())
		return
	if _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	if is_node_ready():
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
			"STALE_REVISION_%d_LT_%d" % [incoming_revision, _current_revision],
		)
		return false
	var incoming_data := UiViewModel.data(snapshot)
	var operation_status := String(UiViewModel.operation_status(snapshot))
	var page_status := String(snapshot.get("status", ""))
	if (
		operation_status in ["idle", "success"]
		and page_status != "disabled"
		and not incoming_data.is_empty()
	):
		_last_confirmed_data = incoming_data.duplicate(true)
	if (
		operation_status in ["loading", "rejected", "error", "disabled"]
		and not _last_confirmed_data.is_empty()
	):
		_render_data = _last_confirmed_data.duplicate(true)
	else:
		_render_data = incoming_data.duplicate(true)
	_view_model = snapshot.duplicate(true)
	_current_revision = incoming_revision
	if is_node_ready():
		_render()
	return true


func current_view_model() -> Dictionary:
	return _view_model.duplicate(true)


func current_revision() -> int:
	return _current_revision


func current_layout_profile() -> String:
	return _layout_profile


func entry_point_view_model() -> Dictionary:
	return (_render_data.get("entryPoint", {}) as Dictionary).duplicate(true)


func request_open() -> bool:
	return _request_action("open", {})


func request_close() -> bool:
	return _request_action("close", {})


func request_back() -> bool:
	if _layout_profile == "narrow" and not String(
		_render_data.get("selectedThreadId", ""),
	).is_empty():
		return _request_action("backToList", {})
	return request_close()


func set_available_rect(available_rect: Rect2) -> void:
	_available_panes_override.clear()
	_available_rect_override = available_rect
	_apply_layout()


func clear_available_rect_override() -> void:
	_available_rect_override = Rect2()
	_apply_layout()


func set_available_panes(panes: Array) -> void:
	_available_panes_override.clear()
	for pane_value: Variant in panes:
		if pane_value is Rect2 and (pane_value as Rect2).has_area():
			_available_panes_override.append(pane_value as Rect2)
	_available_rect_override = Rect2()
	_apply_layout()


func clear_available_panes_override() -> void:
	_available_panes_override.clear()
	_apply_layout()


func set_safe_insets(insets: Vector4) -> void:
	_safe_insets_override = Vector4(
		maxf(0.0, insets.x),
		maxf(0.0, insets.y),
		maxf(0.0, insets.z),
		maxf(0.0, insets.w),
	)
	_apply_layout()


func clear_safe_insets_override() -> void:
	_safe_insets_override = Vector4(-1, -1, -1, -1)
	_apply_layout()


func set_entry_anchor(anchor_rect: Rect2) -> void:
	_entry_anchor_override = anchor_rect


func clear_entry_anchor() -> void:
	_entry_anchor_override = Rect2()


func focus_default() -> void:
	if _layout_profile == "narrow" and _back_button.visible:
		_back_button.grab_focus()
	elif _resident_filter.visible:
		_resident_filter.grab_focus()
	else:
		_close_button.grab_focus()


func debug_request_action(action_key: String, payload: Dictionary = {}) -> bool:
	return _request_action(action_key, payload)


func runtime_gate_snapshot() -> Dictionary:
	var rows := _render_data.get("rows", []) as Array
	var detail_value: Variant = _render_data.get("detail")
	var detail_records := 0
	var row_previews_present := false
	var mail_role_names_resolved := false
	for row_value: Variant in rows:
		if not row_value is Dictionary:
			continue
		var row := row_value as Dictionary
		for key in ["preview", "latestText", "latestUpdate"]:
			if not String(row.get(key, "")).strip_edges().is_empty():
				row_previews_present = true
				break
		if row_previews_present:
			break
	if detail_value is Dictionary:
		var detail := detail_value as Dictionary
		var detail_thread := detail.get("thread", {}) as Dictionary
		var detail_record_values := detail.get("records", []) as Array
		detail_records = detail_record_values.size()
		if _is_private_message_thread(detail_thread):
			var mail_context := _mail_context(detail_thread, detail_record_values)
			mail_role_names_resolved = (
				String(mail_context.get("senderName", "")) != "寄件居民"
				and String(mail_context.get("recipientName", "")) != "收件居民"
				and String(mail_context.get("courierName", "")) != "投递居民"
			)
	return {
		"capabilityMode": String(_render_data.get("capabilityMode", "")),
		"placeholderBadgeVisible": false,
		"sourceMode": "town_ui_adapter" if _adapter != null else "unavailable",
		"source": String(_render_data.get("source", "")),
		"formalReady": bool(_render_data.get("formalReady", false)),
		"operationStatus": String(
			(_view_model.get("operation", {}) as Dictionary).get("status", "idle"),
		),
		"panelVisible": _shell.visible if _shell != null else false,
		"drawerVisible": _shell.visible if _shell != null else false,
		"layoutProfile": _layout_profile,
		"rowCount": rows.size(),
		"entryCount": rows.size(),
		"selectedThreadId": String(_render_data.get("selectedThreadId", "")),
		"detailRecordCount": detail_records,
		"conversationLineTimesVisible": false,
		"causalUiPresent": false,
		"mapFocusPresent": false,
		"imageAssetFamily": "world_log/runtime/reference_table_v2+reference_table_v5+reference_table_v6",
		"imageControlsComplete": true,
		"rowPreviewsPresent": row_previews_present,
		"eventPreviewMode": "detail_and_tooltip",
		"eventPreviewLineCount": 2,
		"interactionMotion": "row_tint_80ms_detail_fade_120ms",
		"popupSelectionStyle": "single_row_no_nested_arrow",
		"detailLayout": "reference_plain",
		"headerLayout": "outer_frame_with_bottom_divider",
		"mailDetailSupported": true,
		"mailRoleNamesResolved": mail_role_names_resolved,
		"mailRoleColorCount": 3,
		"tableCellBorderMode": "single_right_bottom",
		"tableColorStates": [
			"header",
			"normal_a",
			"normal_b",
			"unread",
			"selected",
		],
		"shellRect": _rect_to_array(_shell.get_global_rect()) if _shell != null else [],
		"listRect": _rect_to_array(_list_column.get_global_rect()) if _list_column != null else [],
		"tableHeaderRect": _rect_to_array(_table_header.get_global_rect()) if _table_header != null else [],
		"listScrollRect": _rect_to_array(_list_scroll.get_global_rect()) if _list_scroll != null else [],
		"scrollbarRect": (
			_rect_to_array(_list_scroll.get_v_scroll_bar().get_global_rect())
			if _list_scroll != null and _list_scroll.get_v_scroll_bar().visible
			else []
		),
		"scrollbarVisible": (
			_list_scroll.get_v_scroll_bar().visible
			if _list_scroll != null
			else false
		),
		"headerScrollbarGutter": (
			_table_header_host.get_theme_constant("margin_right")
			if _table_header_host != null
			else 0
		),
		"detailRect": _rect_to_array(_detail_shell.get_global_rect()) if _detail_shell != null else [],
		"filterCount": 3,
		"focusControlCount": _focus_controls.size(),
	}


func _build_interface() -> void:
	_shell = NinePatchRect.new()
	_shell.name = "WorldLogShell"
	_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	PageTheme.configure_nine_patch(_shell, PageTheme.panel_texture(), [4, 4, 4, 4])
	add_child(_shell)

	_page_margin = MarginContainer.new()
	_page_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		_page_margin.add_theme_constant_override("margin_%s" % side, 26)
	_shell.add_child(_page_margin)

	_page_content = VBoxContainer.new()
	_page_content.add_theme_constant_override("separation", 8)
	_page_margin.add_child(_page_content)
	_build_header()
	_build_filters()
	_build_body()

	_feedback_label = _make_label("", &"TownLogBodyMuted", 1)
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.visible = false
	_page_content.add_child(_feedback_label)

	_frame_overlay = NinePatchRect.new()
	_frame_overlay.name = "ReferenceTableOuterFrame"
	_frame_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PageTheme.configure_nine_patch(
		_frame_overlay,
		PageTheme.outer_frame_texture(),
		[26, 26, 26, 26],
	)
	_frame_overlay.draw_center = false
	_shell.add_child(_frame_overlay)


func _build_header() -> void:
	_header = Control.new()
	_header.custom_minimum_size = Vector2(0, 62)
	_page_content.add_child(_header)
	var divider := TextureRect.new()
	divider.name = "HeaderBottomDivider"
	divider.anchor_left = 0.0
	divider.anchor_top = 1.0
	divider.anchor_right = 1.0
	divider.anchor_bottom = 1.0
	divider.offset_top = -8.0
	divider.texture = PageTheme.header_divider_texture()
	divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	divider.stretch_mode = TextureRect.STRETCH_SCALE
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(divider)
	_header_row = HBoxContainer.new()
	_header_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_header_row.offset_left = 10
	_header_row.offset_top = 3
	_header_row.offset_right = -16
	_header_row.offset_bottom = -11
	_header_row.add_theme_constant_override("separation", 10)
	_header.add_child(_header_row)

	_back_button = _make_button("返回", "backToList", PageTheme.icon_texture("back"))
	_back_button.name = "BackButton"
	_back_button.pressed.connect(func() -> void: _request_action("backToList", {}))
	_header_row.add_child(_back_button)

	var journal := TextureRect.new()
	journal.custom_minimum_size = Vector2(38, 38)
	journal.texture = PageTheme.icon_texture("journal")
	journal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	journal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	journal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_row.add_child(journal)

	_title = _make_label("世界日志", &"TownLogTitle", 1)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_row.add_child(_title)

	_unread_summary = _make_label("", &"TownLogListPlace", 1)
	_unread_summary.custom_minimum_size.x = 190
	_unread_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_unread_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_unread_summary.add_theme_color_override("font_color", PageTheme.TERRACOTTA)
	_header_row.add_child(_unread_summary)

	_refresh_button = _make_button("查看新内容", "refreshNewer", PageTheme.icon_texture("refresh"))
	_refresh_button.pressed.connect(func() -> void: _request_action("refreshNewer", {}))
	_header_row.add_child(_refresh_button)

	_close_button = _make_button("", "close", PageTheme.icon_texture("close"))
	_close_button.name = "CloseButton"
	_close_button.custom_minimum_size = Vector2(52, 48)
	_close_button.add_theme_constant_override("icon_max_width", 48)
	_apply_flat_icon_button_style(_close_button)
	_close_button.pressed.connect(func() -> void: request_close())
	_header_row.add_child(_close_button)


func _build_filters() -> void:
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 10)
	_page_content.add_child(_filter_row)
	_resident_filter = _make_option_button("全部居民", PageTheme.icon_texture("resident"))
	_kind_filter = _make_option_button("全部类型", PageTheme.icon_texture("kind"))
	_day_filter = _make_option_button("全部日期", PageTheme.icon_texture("calendar"))
	_filter_row.add_child(_resident_filter)
	_filter_row.add_child(_kind_filter)
	_filter_row.add_child(_day_filter)
	_resident_filter.item_selected.connect(_on_resident_filter_selected)
	_kind_filter.item_selected.connect(_on_kind_filter_selected)
	_day_filter.item_selected.connect(_on_day_filter_selected)
	_unread_button = _make_button("只看未读", "toggleUnread", PageTheme.toggle_texture(false))
	_unread_button.custom_minimum_size.x = 138
	_unread_button.toggle_mode = true
	_apply_unread_toggle_style(_unread_button)
	_unread_button.visible = false
	_unread_button.pressed.connect(_on_unread_pressed)
	_filter_row.add_child(_unread_button)


func _build_body() -> void:
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_page_content.add_child(_body)

	_list_column = VBoxContainer.new()
	_list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_column.size_flags_stretch_ratio = 1.55
	_list_column.add_theme_constant_override("separation", 0)
	_body.add_child(_list_column)
	_table_header_host = MarginContainer.new()
	_list_column.add_child(_table_header_host)
	_table_header = HBoxContainer.new()
	_table_header.custom_minimum_size = Vector2(0, 40)
	_table_header.add_theme_constant_override("separation", 0)
	_table_header_host.add_child(_table_header)
	_build_table_header()
	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_column.add_child(_list_scroll)
	var list_scrollbar := _list_scroll.get_v_scroll_bar()
	list_scrollbar.visibility_changed.connect(_sync_table_scrollbar_gutter)
	list_scrollbar.resized.connect(_sync_table_scrollbar_gutter)
	_list_content = VBoxContainer.new()
	_list_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_content.add_theme_constant_override("separation", 0)
	_list_scroll.add_child(_list_content)
	_list_empty = _make_label("暂无记录", &"TownLogBodyMuted", 1)
	_list_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list_empty.custom_minimum_size = Vector2(0, 90)
	_list_column.add_child(_list_empty)
	_load_more_button = _make_button("继续加载", "loadMore")
	_apply_pagination_style(_load_more_button)
	_load_more_button.pressed.connect(func() -> void: _request_action("loadMore", {}))
	_list_column.add_child(_load_more_button)

	_detail_shell = NinePatchRect.new()
	_detail_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_shell.size_flags_stretch_ratio = 1.0
	_detail_shell.custom_minimum_size.x = 480
	PageTheme.configure_nine_patch(_detail_shell, PageTheme.flyout_texture())
	_body.add_child(_detail_shell)
	var detail_margin := MarginContainer.new()
	detail_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		detail_margin.add_theme_constant_override("margin_%s" % side, 20)
	_detail_shell.add_child(detail_margin)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 12)
	detail_margin.add_child(detail_box)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_box.add_child(_detail_scroll)
	_detail_content = VBoxContainer.new()
	_detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_content.add_theme_constant_override("separation", 12)
	_detail_scroll.add_child(_detail_content)
	_detail_load_more_button = _make_button("继续加载详情", "loadMoreDetail")
	_apply_pagination_style(_detail_load_more_button)
	_detail_load_more_button.pressed.connect(
		func() -> void: _request_action("loadMoreDetail", {}),
	)
	detail_box.add_child(_detail_load_more_button)


func _build_table_header() -> void:
	_clear_children(_table_header)
	for spec: Dictionary in _column_specs():
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override(
			"panel",
			PageTheme.table_cell_style("header"),
		)
		cell.custom_minimum_size.x = float(spec["width"])
		cell.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL
			if bool(spec["expand"])
			else Control.SIZE_SHRINK_BEGIN
		)
		var label := _make_label(String(spec["label"]), &"TownLogListTime", 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(label)
		_table_header.add_child(cell)


func _render() -> void:
	var panel := _render_data.get("panel", {}) as Dictionary
	_shell.visible = bool(panel.get("open", false))
	if not _shell.visible:
		return
	_title.text = String(panel.get("title", "世界日志"))
	var selected_id := String(_render_data.get("selectedThreadId", ""))
	var selection_changed := selected_id != _last_rendered_selected_id
	_render_header()
	_render_filters()
	_render_rows(selection_changed)
	_render_detail(selection_changed)
	_render_feedback()
	MOBILE_UI_PROFILE.apply_mobile_typography(self, 23, 4, 34)
	_apply_layout()
	_update_attention_token()
	_last_rendered_selected_id = selected_id


func _render_header() -> void:
	var summary := _render_data.get("summary", {}) as Dictionary
	var total := int(summary.get("totalUnreadThreadCount", 0))
	_unread_summary.text = (
		"%d 条未读  ●" % total
		if total > 0
		else "全部已读"
	)
	_refresh_button.visible = bool(summary.get("hasNewerThreads", false))
	_refresh_button.disabled = not _action_enabled("refreshNewer")


func _render_filters() -> void:
	var filters := _render_data.get("filters", {}) as Dictionary
	var options := _render_data.get("filterOptions", {}) as Dictionary
	_fill_resident_options(
		options.get("residents", []) as Array,
		String(filters.get("residentId", "")),
	)
	_fill_kind_options(
		options.get("kinds", []) as Array,
		String(filters.get("kindTag", "")),
	)
	_fill_day_options(options.get("days", []) as Array, int(filters.get("day", 0)))
	_unread_button.button_pressed = bool(filters.get("unreadOnly", false))
	_unread_button.icon = PageTheme.toggle_texture(_unread_button.button_pressed)
	_apply_unread_toggle_style(_unread_button)
	for control: Control in [_resident_filter, _kind_filter, _day_filter, _unread_button]:
		control.modulate = Color.WHITE if _action_enabled("setFilter") else Color(0.7, 0.66, 0.58)
	_resident_filter.disabled = not _action_enabled("setFilter")
	_kind_filter.disabled = not _action_enabled("setFilter")
	_day_filter.disabled = not _action_enabled("setFilter")
	_unread_button.disabled = not _action_enabled("toggleUnread")


func _render_rows(animate_selection := false) -> void:
	var rows := _render_data.get("rows", []) as Array
	var selected_id := String(_render_data.get("selectedThreadId", ""))
	# 行内容、选中态与分页都没变时不销毁重建；视图模型其他部分的刷新
	# 不应拖着整张表重建（loadMore 之后行数越多越明显）。
	var paging_state := _render_data.get("paging", {}) as Dictionary
	var rows_signature := "%s|%s|%s|%s|%s" % [
		str(rows.hash()),
		selected_id,
		str(bool(paging_state.get("hasMore", false))),
		str(_action_enabled("loadMore")),
		_layout_profile,
	]
	if not animate_selection and rows_signature == _rendered_rows_signature:
		return
	_rendered_rows_signature = rows_signature
	_clear_children(_list_content)
	_row_controls.clear()
	for row_index in rows.size():
		var value: Variant = rows[row_index]
		if not value is Dictionary:
			continue
		var row := value as Dictionary
		var selected := String(row.get("threadId", "")) == selected_id
		var control := _make_table_row(
			row,
			selected,
			row_index,
			animate_selection and selected,
		)
		_list_content.add_child(control)
		_row_controls.append(control)
	_list_empty.visible = rows.is_empty()
	var paging := _render_data.get("paging", {}) as Dictionary
	_load_more_button.visible = bool(paging.get("hasMore", false))
	_load_more_button.disabled = not _action_enabled("loadMore")
	call_deferred("_sync_table_scrollbar_gutter")


func _make_table_row(
	row: Dictionary,
	selected: bool,
	row_index: int,
	animate_selected := false,
) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(
		0,
		72 if MOBILE_UI_PROFILE.is_mobile_runtime() else 60,
	)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.focus_mode = Control.FOCUS_ALL
	panel.add_theme_stylebox_override("panel", PageTheme.transparent_style())
	var preview := _row_preview(row)
	panel.tooltip_text = (
		String(row.get("title", ""))
		if preview.is_empty()
		else "%s\n%s" % [String(row.get("title", "")), preview]
	)
	var row_box := HBoxContainer.new()
	row_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_box.add_theme_constant_override("separation", 0)
	panel.add_child(row_box)
	var values := _row_values(row)
	var specs := _column_specs()
	var cell_state := (
		"selected"
		if selected
		else (
			"unread"
			if bool(row.get("unread", false))
			else ("normal_a" if row_index % 2 == 0 else "normal_b")
		)
	)
	for index in specs.size():
		var spec := specs[index]
		var cell_panel := PanelContainer.new()
		cell_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell_panel.add_theme_stylebox_override(
			"panel",
			PageTheme.table_cell_style(cell_state),
		)
		cell_panel.custom_minimum_size.x = float(spec["width"])
		cell_panel.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL
			if bool(spec["expand"])
			else Control.SIZE_SHRINK_BEGIN
		)
		var cell: Control
		if index == 0:
			var center := CenterContainer.new()
			center.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon := TextureRect.new()
			icon.texture = (
				PageTheme.icon_texture("selected_unread" if selected else "unread")
				if bool(row.get("unread", false))
				else null
			)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(12, 12)
			center.add_child(icon)
			cell = center
		else:
			var line_count := 2 if index == 3 else 1
			var label := _make_label(
				String(values[index]),
				&"TownLogListTitle",
				line_count,
			)
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			if index == 3:
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			if selected:
				label.add_theme_color_override("font_color", PageTheme.PAPER_LIGHT)
			cell = label
		cell_panel.add_child(cell)
		row_box.add_child(cell_panel)
	var thread_id := String(row.get("threadId", ""))
	panel.mouse_entered.connect(func() -> void:
		_animate_control_tint(panel, ROW_HOVER_TINT, ROW_MOTION_SECONDS)
	)
	panel.mouse_exited.connect(func() -> void:
		_animate_control_tint(panel, Color.WHITE, ROW_MOTION_SECONDS)
	)
	panel.focus_entered.connect(func() -> void:
		_animate_control_tint(panel, ROW_HOVER_TINT, ROW_MOTION_SECONDS)
	)
	panel.focus_exited.connect(func() -> void:
		_animate_control_tint(panel, Color.WHITE, ROW_MOTION_SECONDS)
	)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if POINTER_INPUT.is_primary_press(event):
			panel.modulate = ROW_PRESS_TINT
			_request_action("selectThread", {"threadId": thread_id})
			accept_event()
		elif event.is_action_pressed("ui_accept"):
			_request_action("selectThread", {"threadId": thread_id})
			accept_event()
	)
	if animate_selected:
		panel.modulate = Color("ffe0b8")
		_animate_control_tint(panel, Color.WHITE, DETAIL_REVEAL_SECONDS)
	return panel


func _render_detail(animate_entry := false) -> void:
	_clear_children(_detail_content)
	var selected_id := String(_render_data.get("selectedThreadId", ""))
	var detail_value: Variant = _render_data.get("detail")
	var has_detail := not selected_id.is_empty() and detail_value is Dictionary
	if not has_detail:
		var empty := _make_label("选择一条记录查看完整过程", &"TownLogBodyMuted", 1)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_detail_content.add_child(empty)
	else:
		var detail := detail_value as Dictionary
		var thread := detail.get("thread", {}) as Dictionary
		_detail_content.add_child(_detail_heading(thread))
		if _is_conversation_thread(thread):
			_render_conversation_detail(detail)
		elif _is_private_message_thread(thread):
			_render_message_detail(detail)
		else:
			_render_event_detail(detail)
	var paging := _render_data.get("detailPaging", {}) as Dictionary
	_detail_load_more_button.visible = has_detail and bool(paging.get("hasMore", false))
	_detail_load_more_button.disabled = not _action_enabled("loadMoreDetail")
	if animate_entry and has_detail:
		_detail_content.modulate = Color(1, 1, 1, 0.72)
		_animate_control_tint(
			_detail_content,
			Color.WHITE,
			DETAIL_REVEAL_SECONDS,
		)


func _detail_heading(thread: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var title := _make_label(String(thread.get("title", "事件详情")), &"TownLogHeading", 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var time_and_place: Array[String] = []
	var time_range := _thread_time_range(thread)
	if not time_range.is_empty():
		time_and_place.append(time_range)
	var place := String(thread.get("placeLabel", ""))
	if not place.is_empty():
		time_and_place.append(place)
	if not time_and_place.is_empty():
		box.add_child(_make_label(" · ".join(time_and_place), &"TownLogListPlace", 1))
	var participants := _participant_label(thread)
	if not participants.is_empty():
		box.add_child(_make_label("参与者：%s" % participants, &"TownLogListPlace", 1))
	box.add_child(_make_reference_separator(true))
	return box


func _render_conversation_detail(detail: Dictionary) -> void:
	var rendered_lines := 0
	var rendered_turns: Dictionary = {}
	for value: Variant in detail.get("records", []) as Array:
		if not value is Dictionary:
			continue
		var record := value as Dictionary
		var payload := record.get("payload", {}) as Dictionary
		var turns: Array[Dictionary] = []
		var turn_value: Variant = payload.get("turn")
		if turn_value is Dictionary:
			turns.append(turn_value as Dictionary)
		var turn_values: Variant = payload.get("turns")
		if turn_values is Array:
			for historical_turn: Variant in turn_values as Array:
				if historical_turn is Dictionary:
					turns.append(historical_turn as Dictionary)
		for turn_index in turns.size():
			var turn := turns[turn_index]
			var speaker := String(
				turn.get("speaker", turn.get("speakerName", record.get("residentName", "居民"))),
			)
			var text := _conversation_text(turn)
			if text.is_empty():
				continue
			var explicit_turn_id := str(
				turn.get("turn_id", turn.get("turnId", "")),
			).strip_edges()
			var turn_key := (
				"turn:%s" % explicit_turn_id
				if not explicit_turn_id.is_empty()
				else "record:%d:turn:%d" % [
					int(record.get("sequence", 0)),
					turn_index,
				]
			)
			if rendered_turns.has(turn_key):
				continue
			rendered_turns[turn_key] = true
			var line := VBoxContainer.new()
			line.add_theme_constant_override("separation", 2)
			var speaker_label := _make_label(speaker, &"TownLogListTitle", 1)
			speaker_label.add_theme_color_override(
				"font_color",
				PageTheme.TERRACOTTA if rendered_lines % 2 else PageTheme.MOSS,
			)
			line.add_child(speaker_label)
			var copy := _make_label(text, &"TownLogBody", 2)
			copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_child(copy)
			_detail_content.add_child(line)
			rendered_lines += 1
	if rendered_lines == 0:
		_detail_content.add_child(_make_label("这段对话还没有可回看的发言。", &"TownLogBodyMuted", 2))
	else:
		var thread := detail.get("thread", {}) as Dictionary
		if String(thread.get("status", "")) != "ongoing":
			_detail_content.add_child(_make_reference_separator(false))
			var ending := _make_label("对话结束", &"TownLogListPlace", 1)
			ending.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_detail_content.add_child(ending)


func _render_message_detail(detail: Dictionary) -> void:
	var records := detail.get("records", []) as Array
	var thread := detail.get("thread", {}) as Dictionary
	var mail_context := _mail_context(thread, records)
	_detail_content.add_child(_make_mail_route_line(mail_context))
	var content := ""
	for value: Variant in records:
		if not value is Dictionary:
			continue
		var record := value as Dictionary
		var payload := record.get("payload", {}) as Dictionary
		var candidate := String(payload.get("content", record.get("text", ""))).strip_edges()
		if not candidate.is_empty():
			content = candidate
			break
	_detail_content.add_child(_make_label("口信原文", &"TownLogListTitle", 1))
	var letter_text := _make_label(
		content if not content.is_empty() else "这封口信没有留下可回看的正文。",
		&"TownLogBody" if not content.is_empty() else &"TownLogBodyMuted",
		6,
	)
	letter_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_content.add_child(letter_text)
	_detail_content.add_child(_make_reference_separator(false))
	_detail_content.add_child(_make_label("投递过程", &"TownLogListTitle", 1))
	_render_process_records(records, true, mail_context)


func _render_event_detail(detail: Dictionary) -> void:
	var records := detail.get("records", []) as Array
	if records.is_empty():
		_detail_content.add_child(_make_label("暂无可显示的过程记录。", &"TownLogBodyMuted", 2))
		return
	_render_process_records(records, false, {})


func _render_process_records(
	records: Array,
	message_mode: bool,
	mail_context: Dictionary,
) -> void:
	var process_box := VBoxContainer.new()
	process_box.add_theme_constant_override("separation", 0)
	for record_index in records.size():
		var value: Variant = records[record_index]
		if not value is Dictionary:
			continue
		var record := value as Dictionary
		var line := HBoxContainer.new()
		line.custom_minimum_size.y = 46
		line.add_theme_constant_override("separation", 10)
		var time_label := _make_label(
			_time_label(record.get("time", {}) as Dictionary, false),
			&"TownLogListTime",
			1,
		)
		time_label.custom_minimum_size.x = 58
		time_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		line.add_child(time_label)
		line.add_child(_make_timeline_axis(record_index, records.size()))
		var summary: Control
		if message_mode:
			summary = _make_colored_process_line(
				_mail_process_parts(record, mail_context),
			)
		else:
			var summary_text := _record_process_summary(record, false)
			summary = _make_label(summary_text, &"TownLogBody", 2)
			(summary as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(summary)
		process_box.add_child(line)
	_detail_content.add_child(process_box)


func _render_feedback() -> void:
	var operation := _view_model.get("operation", {}) as Dictionary
	var status := String(operation.get("status", "idle"))
	var error_value: Variant = _view_model.get("error")
	_feedback_label.visible = status in ["loading", "rejected", "error", "disabled"]
	match status:
		"loading":
			_feedback_label.text = "正在整理世界日志……"
		"rejected":
			_feedback_label.text = "这次操作没有完成，原有记录仍然保留。"
		"error", "disabled":
			_feedback_label.text = (
				UiViewModel.public_operation_error_message(error_value as Dictionary)
				if error_value is Dictionary
				else "当前操作暂不可用"
			)
		_:
			_feedback_label.text = ""


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_apply_queued_layout")


func _apply_queued_layout() -> void:
	_layout_queued = false
	if not is_node_ready():
		return
	_apply_layout()


func _apply_layout() -> void:
	if _shell == null:
		return
	var previous_profile := _layout_profile
	var available := _available_rect()
	var insets := _safe_insets()
	var safe := Rect2(
		available.position + Vector2(insets.x, insets.y),
		available.size - Vector2(insets.x + insets.z, insets.y + insets.w),
	)
	var margin := 20.0 if safe.size.x >= 900 else 10.0
	var size := Vector2(
		minf(1680.0, maxf(520.0, safe.size.x - margin * 2.0)),
		minf(810.0, maxf(600.0, safe.size.y - margin * 2.0)),
	)
	if MOBILE_UI_PROFILE.is_mobile_runtime():
		# World log owns the whole mobile page; a small safe-area inset is the only
		# gap, avoiding the desktop floating-window look and exposed map corners.
		margin = 0.0
		size = safe.size
	_shell.position = safe.position + (safe.size - size) * 0.5
	_shell.size = size
	_layout_profile = "wide" if size.x >= WIDE_BREAKPOINT else "narrow"
	var selected := not String(_render_data.get("selectedThreadId", "")).is_empty()
	_back_button.visible = _layout_profile == "narrow" and selected
	_detail_shell.visible = _layout_profile == "wide" or selected
	_list_column.visible = _layout_profile == "wide" or not selected
	_filter_row.visible = _layout_profile == "wide" or not selected
	_table_header.visible = _layout_profile == "wide" or not selected
	_unread_summary.visible = _layout_profile == "wide"
	_close_button.visible = not (_layout_profile == "narrow" and selected)
	_build_table_header()
	if previous_profile != _layout_profile and _list_content != null:
		_render_rows()
	for option: OptionButton in [_resident_filter, _kind_filter, _day_filter]:
		option.custom_minimum_size.x = 0.0 if _layout_profile == "narrow" else 300.0
		option.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL
			if _layout_profile == "narrow"
			else Control.SIZE_SHRINK_BEGIN
		)
	_unread_button.visible = false
	call_deferred("_sync_table_scrollbar_gutter")


func _sync_table_scrollbar_gutter() -> void:
	if _table_header_host == null or _list_scroll == null:
		return
	var scrollbar := _list_scroll.get_v_scroll_bar()
	var gutter := ceili(scrollbar.size.x) if scrollbar.visible else 0
	_table_header_host.add_theme_constant_override("margin_right", gutter)


func _animate_control_tint(
	control: Control,
	target: Color,
	duration: float,
) -> void:
	if control == null or not is_instance_valid(control):
		return
	var active_value: Variant = (
		control.get_meta("town_log_interaction_tween")
		if control.has_meta("town_log_interaction_tween")
		else null
	)
	if active_value is Tween and (active_value as Tween).is_valid():
		(active_value as Tween).kill()
	var tween := control.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate", target, duration)
	control.set_meta("town_log_interaction_tween", tween)


func _available_rect() -> Rect2:
	if not _available_panes_override.is_empty():
		var best := _available_panes_override[0]
		for pane: Rect2 in _available_panes_override:
			if pane.get_area() > best.get_area():
				best = pane
		return best
	if _available_rect_override.has_area():
		return _available_rect_override
	return Rect2(Vector2.ZERO, size)


func _safe_insets() -> Vector4:
	if _safe_insets_override.x >= 0:
		return _safe_insets_override
	return Vector4.ZERO


func _request_action(action_key: String, payload: Dictionary) -> bool:
	var actions := _view_model.get("actions", {}) as Dictionary
	var action := actions.get(action_key, {}) as Dictionary
	var intent := StringName(action.get("intent", ""))
	if intent == &"" or not bool(action.get("enabled", false)):
		var reason := String(action.get("disabledReason", "ACTION_DISABLED"))
		action_blocked.emit(intent, reason)
		return false
	var public_payload := payload.duplicate(true)
	public_payload["revision"] = _current_revision
	intent_requested.emit(intent, public_payload.duplicate(true))
	if _adapter != null and _adapter.has_method("dispatch"):
		var dispatch_payload := public_payload.duplicate(true)
		dispatch_payload.erase("revision")
		_adapter.call("dispatch", String(intent), dispatch_payload)
	return true


func _action_enabled(action_key: String) -> bool:
	var action := (_view_model.get("actions", {}) as Dictionary).get(action_key, {}) as Dictionary
	return bool(action.get("enabled", false))


func _on_resident_filter_selected(index: int) -> void:
	_request_action("setFilter", {"key": "residentId", "value": _resident_filter.get_item_metadata(index)})


func _on_kind_filter_selected(index: int) -> void:
	_request_action("setFilter", {"key": "kindTag", "value": _kind_filter.get_item_metadata(index)})


func _on_day_filter_selected(index: int) -> void:
	_request_action("setFilter", {"key": "day", "value": _day_filter.get_item_metadata(index)})


func _on_unread_pressed() -> void:
	_request_action("toggleUnread", {"unreadOnly": _unread_button.button_pressed})


func _fill_resident_options(values: Array, selected_id: String) -> void:
	_resident_filter.set_block_signals(true)
	_resident_filter.clear()
	_resident_filter.add_item("全部居民")
	_resident_filter.set_item_metadata(0, "")
	var selected := 0
	for value: Variant in values:
		if not value is Dictionary:
			continue
		var resident := value as Dictionary
		var resident_id := String(resident.get("residentId", ""))
		_resident_filter.add_item(String(resident.get("displayName", resident_id)))
		var index := _resident_filter.item_count - 1
		_resident_filter.set_item_metadata(index, resident_id)
		if resident_id == selected_id:
			selected = index
	_resident_filter.select(selected)
	_resident_filter.set_block_signals(false)


func _fill_kind_options(values: Array, selected_kind: String) -> void:
	_kind_filter.set_block_signals(true)
	_kind_filter.clear()
	_kind_filter.add_item("全部类型")
	_kind_filter.set_item_metadata(0, "")
	var selected := 0
	for value: Variant in values:
		if not value is Dictionary:
			continue
		var kind := String((value as Dictionary).get("kindTag", ""))
		_kind_filter.add_item(_kind_label(kind))
		var index := _kind_filter.item_count - 1
		_kind_filter.set_item_metadata(index, kind)
		if kind == selected_kind:
			selected = index
	_kind_filter.select(selected)
	_kind_filter.set_block_signals(false)


func _fill_day_options(values: Array, selected_day: int) -> void:
	_day_filter.set_block_signals(true)
	_day_filter.clear()
	_day_filter.add_item("全部日期")
	_day_filter.set_item_metadata(0, 0)
	var selected := 0
	for value: Variant in values:
		var day := int(value)
		_day_filter.add_item("第 %d 天" % day)
		var index := _day_filter.item_count - 1
		_day_filter.set_item_metadata(index, day)
		if day == selected_day:
			selected = index
	_day_filter.select(selected)
	_day_filter.set_block_signals(false)


func _make_option_button(label: String, icon: Texture2D) -> OptionButton:
	var option := OptionButton.new()
	option.text = label
	option.icon = null
	option.expand_icon = false
	option.custom_minimum_size = Vector2(300, 52)
	option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	option.focus_mode = Control.FOCUS_ALL
	option.add_theme_stylebox_override("normal", PageTheme.control_style("normal"))
	option.add_theme_stylebox_override("hover", PageTheme.control_style("hover"))
	option.add_theme_stylebox_override("pressed", PageTheme.control_style("selected"))
	option.add_theme_stylebox_override("focus", PageTheme.control_style("hover"))
	# 参考图素材本身已经包含右侧箭头，透明占位可避免叠出第二个箭头。
	var arrow_image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	arrow_image.fill(Color.TRANSPARENT)
	option.add_theme_icon_override("arrow", ImageTexture.create_from_image(arrow_image))
	option.add_theme_color_override("font_color", PageTheme.INK)
	option.add_theme_color_override("font_hover_color", PageTheme.INK)
	option.add_theme_color_override("font_pressed_color", PageTheme.INK)
	option.add_theme_color_override("font_focus_color", PageTheme.INK)
	option.add_theme_font_size_override("font_size", 19)
	option.add_theme_constant_override("icon_max_width", 28)
	if icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		icon_rect.anchor_top = 0.5
		icon_rect.anchor_bottom = 0.5
		icon_rect.offset_left = 14
		icon_rect.offset_top = -12
		icon_rect.offset_right = 38
		icon_rect.offset_bottom = 12
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		option.add_child(icon_rect)
	_focus_controls.append(option)
	return option


func _make_button(text_value: String, _action_key: String, icon: Texture2D = null) -> Button:
	var button := Button.new()
	button.text = text_value
	button.icon = icon
	button.expand_icon = icon != null
	button.custom_minimum_size = MINIMUM_TOUCH_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_constant_override("icon_max_width", 30)
	_apply_button_state(button, false)
	_focus_controls.append(button)
	return button


func _apply_button_state(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", PageTheme.button_style("selected" if selected else "normal"))
	button.add_theme_stylebox_override("hover", PageTheme.button_style("hover"))
	button.add_theme_stylebox_override("pressed", PageTheme.button_style("selected"))
	button.add_theme_stylebox_override("focus", PageTheme.button_style("hover"))
	button.add_theme_stylebox_override("disabled", PageTheme.button_style("disabled"))
	button.add_theme_color_override("font_color", PageTheme.PAPER_LIGHT if selected else PageTheme.INK)
	button.add_theme_color_override("font_hover_color", PageTheme.PAPER_LIGHT)
	button.add_theme_color_override("font_pressed_color", PageTheme.PAPER_LIGHT)
	button.add_theme_color_override("font_focus_color", PageTheme.PAPER_LIGHT)
	button.add_theme_color_override("font_disabled_color", PageTheme.DISABLED)
	button.add_theme_font_size_override("font_size", 19)


func _apply_pagination_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", PageTheme.detail_style("pagination"))
	button.add_theme_stylebox_override("hover", PageTheme.button_style("hover"))
	button.add_theme_stylebox_override("pressed", PageTheme.button_style("selected"))
	button.add_theme_stylebox_override("focus", PageTheme.button_style("hover"))
	button.add_theme_stylebox_override("disabled", PageTheme.button_style("disabled"))


func _apply_flat_icon_button_style(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, PageTheme.transparent_style())


func _apply_unread_toggle_style(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, PageTheme.transparent_style())
	button.add_theme_color_override("font_color", PageTheme.INK)
	button.add_theme_color_override("font_hover_color", PageTheme.TERRACOTTA_DARK)
	button.add_theme_color_override("font_pressed_color", PageTheme.TERRACOTTA_DARK)
	button.add_theme_color_override("font_focus_color", PageTheme.TERRACOTTA_DARK)
	button.add_theme_color_override("font_disabled_color", PageTheme.DISABLED)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_constant_override("icon_max_width", 28)


func _make_label(text_value: String, variation: StringName, lines: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.theme_type_variation = variation
	label.max_lines_visible = lines
	label.clip_text = lines == 1
	return label


func _column_specs() -> Array[Dictionary]:
	if _layout_profile == "narrow":
		return [
			{"label": "", "width": 34.0, "expand": false},
			{"label": "时间", "width": 76.0, "expand": false},
			{"label": "类型", "width": 90.0, "expand": false},
			{"label": "事件", "width": 180.0, "expand": true},
		]
	return [
		{"label": "", "width": 42.0, "expand": false},
		{"label": "时间", "width": 92.0, "expand": false},
		{"label": "类型", "width": 116.0, "expand": false},
		{"label": "事件", "width": 240.0, "expand": true},
		{"label": "居民", "width": 154.0, "expand": false},
		{"label": "地点", "width": 110.0, "expand": false},
		{"label": "状态", "width": 112.0, "expand": false},
	]


func _row_values(row: Dictionary) -> Array[String]:
	return [
		"",
		_time_label(row.get("updatedAt", {}) as Dictionary, false),
		_kind_label(String(row.get("kind", "world_change"))),
		String(row.get("title", "世界事件")),
		_participant_label(row),
		String(row.get("placeLabel", "")),
		String(STATUS_LABELS.get(String(row.get("status", "ongoing")), row.get("status", ""))),
	]


func _participant_label(thread: Dictionary) -> String:
	var names: Array[String] = []
	for value: Variant in thread.get("participantSnapshots", []) as Array:
		if value is Dictionary:
			var name := String((value as Dictionary).get("displayName", "")).strip_edges()
			if not name.is_empty() and not names.has(name):
				names.append(name)
	if names.size() > 3:
		return "%s 等 %d 人" % [names[0], names.size()]
	return "、".join(names)


func _time_label(time: Dictionary, include_day := true) -> String:
	var day := int(time.get("day", 0))
	var hour := int(time.get("hour", 0))
	var minute := int(time.get("minute", 0))
	var clock := String(time.get("clock", ""))
	if clock.is_empty():
		clock = "%02d:%02d" % [hour, minute]
	return ("第%d天 " % day if include_day and day > 0 else "") + clock


func _thread_time_range(thread: Dictionary) -> String:
	var start := thread.get("startedAt", {}) as Dictionary
	var finish := thread.get("updatedAt", {}) as Dictionary
	if start.is_empty():
		start = finish
	if finish.is_empty():
		finish = start
	if start.is_empty():
		return ""
	var day := int(start.get("day", finish.get("day", 0)))
	var start_clock := _time_label(start, false)
	var finish_clock := _time_label(finish, false)
	if start_clock == finish_clock:
		return _time_label(finish, true)
	return "%s%s–%s" % ["第%d天 " % day if day > 0 else "", start_clock, finish_clock]


func _make_reference_separator(dashed: bool) -> TextureRect:
	var separator := TextureRect.new()
	separator.texture = PageTheme.separator_texture(dashed)
	separator.custom_minimum_size = Vector2(0, 8)
	separator.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	separator.stretch_mode = TextureRect.STRETCH_SCALE
	separator.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return separator


func _make_timeline_axis(index: int, total: int) -> Control:
	var axis := Control.new()
	axis.custom_minimum_size = Vector2(34, 46)
	axis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var connector := TextureRect.new()
	connector.texture = PageTheme.timeline_connector_texture()
	connector.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	connector.stretch_mode = TextureRect.STRETCH_SCALE
	connector.position = Vector2(14, 23 if index == 0 else 0)
	connector.size = Vector2(5, 23 if index in [0, total - 1] else 46)
	connector.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	axis.add_child(connector)
	var node := TextureRect.new()
	node.texture = PageTheme.timeline_node_texture()
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.position = Vector2(10, 17)
	node.size = Vector2(12, 12)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	axis.add_child(node)
	return axis


func _kind_label(kind: String) -> String:
	return String(KIND_LABELS.get(kind, kind if not kind.is_empty() else "世界变化"))


func _is_conversation_thread(thread: Dictionary) -> bool:
	return (
		String(thread.get("kind", "")) == "conversation"
		or (thread.get("kindTags", []) as Array).has("conversation")
	)


func _is_private_message_thread(thread: Dictionary) -> bool:
	return String(thread.get("threadId", "")).begins_with("message:")


func _row_preview(row: Dictionary) -> String:
	for key in ["preview", "latestText", "latestUpdate"]:
		var value := String(row.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return "查看完整过程"


func _make_ornamental_separator() -> TextureRect:
	var separator := TextureRect.new()
	separator.texture = PageTheme.separator_texture()
	separator.custom_minimum_size = Vector2(0, 14)
	separator.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	separator.stretch_mode = TextureRect.STRETCH_SCALE
	separator.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return separator


func _conversation_text(turn: Dictionary) -> String:
	for key in ["say", "text", "content", "line", "utterance"]:
		var text := String(turn.get(key, "")).strip_edges()
		if not text.is_empty():
			return text
	return ""


func _record_summary(record: Dictionary) -> String:
	var payload := record.get("payload", {}) as Dictionary
	var event_type := String(payload.get("type", "")).strip_edges()
	var actor := _record_actor_name(record)
	var parts: Array[String] = []
	if not actor.is_empty():
		parts.append(actor)
	if not event_type.is_empty():
		parts.append(event_type)
	var is_announcement_event := event_type in [
		"公告发布",
		"公告阅读",
		"公告转告",
		"钟声公告",
		"公告撤回",
	]
	if is_announcement_event:
		var announcement_text_value: Variant = payload.get("text", "")
		var announcement_text := (
			(announcement_text_value as String).strip_edges()
			if announcement_text_value is String
			else ""
		)
		if not announcement_text.is_empty() and not parts.has(announcement_text):
			parts.append(announcement_text)
		var announcement_reason_value: Variant = payload.get("reason", "")
		var announcement_reason := (
			(announcement_reason_value as String).strip_edges()
			if announcement_reason_value is String
			else ""
		)
		if (
			not announcement_reason.is_empty()
			and not announcement_text.contains(announcement_reason)
		):
			parts.append("原因：%s" % announcement_reason)
	var animal_name := String(payload.get("animalName", "")).strip_edges()
	if not animal_name.is_empty() and not parts.has(animal_name):
		parts.append(animal_name)
	var item_label := _item_label(payload)
	if not item_label.is_empty():
		var quantity := int(payload.get("quantity", 0))
		parts.append(
			"%s ×%d" % [item_label, quantity]
			if quantity > 0
			else item_label
		)
	var source_place := String(payload.get("sourcePlaceId", "")).strip_edges()
	var destination_place := String(payload.get("destinationPlaceId", "")).strip_edges()
	if not source_place.is_empty() and not destination_place.is_empty():
		parts.append("%s → %s" % [source_place, destination_place])
	for role in [
		["requesterName", "委托人"],
		["workerName", "承办人"],
		["carrierName", "运送人"],
	]:
		var role_name := String(payload.get(role[0], "")).strip_edges()
		if not role_name.is_empty() and role_name != actor:
			parts.append("%s：%s" % [role[1], role_name])
	for key in ["summary", "result", "content", "reason", "line"]:
		if is_announcement_event and key == "reason":
			continue
		var raw_value: Variant = payload.get(key, "")
		if not raw_value is String:
			continue
		var text := String(raw_value).strip_edges()
		if not text.is_empty() and not parts.has(text):
			parts.append(text)
			break
	if parts.is_empty():
		return String(record.get("title", "事件状态已更新"))
	return " · ".join(parts)


func _record_actor_name(record: Dictionary) -> String:
	var actor := String(record.get("residentName", "")).strip_edges()
	if not actor.is_empty():
		return actor
	var resident_id := String(record.get("residentId", "")).strip_edges()
	for value: Variant in record.get("participantSnapshots", []) as Array:
		if not value is Dictionary:
			continue
		var snapshot := value as Dictionary
		if (
			resident_id.is_empty()
			or String(snapshot.get("residentId", "")) == resident_id
		):
			var display_name := String(snapshot.get("displayName", "")).strip_edges()
			if not display_name.is_empty():
				return display_name
	return ""


func _item_label(payload: Dictionary) -> String:
	for key in ["itemName", "itemLabel"]:
		var explicit := String(payload.get(key, "")).strip_edges()
		if not explicit.is_empty():
			return explicit
	var item_id := String(payload.get("itemId", "")).strip_edges()
	return String(ITEM_LABELS.get(item_id, item_id))


func _record_process_summary(record: Dictionary, message_mode: bool) -> String:
	var payload := record.get("payload", {}) as Dictionary
	var postal_summary := _postal_process_summary(payload)
	if not postal_summary.is_empty():
		return postal_summary
	var event_type := String(payload.get("type", "")).strip_edges()
	if message_mode:
		match event_type:
			"消息创建":
				return "口信已交给投递流程"
			"消息送达":
				return "口信已经当面送达"
			"消息取消":
				var reason := String(payload.get("reason", "")).strip_edges()
				return "口信取消%s" % ("：%s" % reason if not reason.is_empty() else "")
	return _record_summary(record)


func _mail_context(thread: Dictionary, records: Array) -> Dictionary:
	var names_by_id: Dictionary = {}
	var ordered_names: Array[String] = []
	for value: Variant in thread.get("participantSnapshots", []) as Array:
		if not value is Dictionary:
			continue
		var snapshot := value as Dictionary
		var resident_id := String(snapshot.get("residentId", "")).strip_edges()
		var display_name := String(snapshot.get("displayName", "")).strip_edges()
		if not resident_id.is_empty() and not display_name.is_empty():
			names_by_id[resident_id] = display_name
		if not display_name.is_empty() and not ordered_names.has(display_name):
			ordered_names.append(display_name)
	var sender_id := ""
	var recipient_id := ""
	var courier_id := ""
	var courier_name := ""
	for value: Variant in records:
		if not value is Dictionary:
			continue
		var record := value as Dictionary
		var payload := record.get("payload", {}) as Dictionary
		if sender_id.is_empty():
			sender_id = String(
				payload.get("senderResidentId", payload.get("sender_resident_id", "")),
			).strip_edges()
		if recipient_id.is_empty():
			recipient_id = String(
				payload.get(
					"recipientResidentId",
					payload.get("recipient_resident_id", ""),
				),
			).strip_edges()
		if courier_id.is_empty():
			courier_id = String(
				payload.get(
					"deliveredByResidentId",
					payload.get("delivered_by_resident_id", ""),
				),
			).strip_edges()
		if (
			courier_name.is_empty()
			and String(payload.get("capability", "")).begins_with("message.")
		):
			courier_name = String(record.get("residentName", "")).strip_edges()
	var sender_name := String(names_by_id.get(sender_id, "")).strip_edges()
	var recipient_name := String(names_by_id.get(recipient_id, "")).strip_edges()
	if sender_name.is_empty() and not ordered_names.is_empty():
		sender_name = ordered_names[0]
	if recipient_name.is_empty() and ordered_names.size() >= 2:
		recipient_name = ordered_names[1]
	var mapped_courier_name := String(names_by_id.get(courier_id, "")).strip_edges()
	if not mapped_courier_name.is_empty():
		courier_name = mapped_courier_name
	if courier_name.is_empty() and ordered_names.size() >= 3:
		courier_name = ordered_names[2]
	return {
		"senderName": sender_name if not sender_name.is_empty() else "寄件居民",
		"recipientName": (
			recipient_name if not recipient_name.is_empty() else "收件居民"
		),
		"courierName": courier_name if not courier_name.is_empty() else "投递居民",
	}


func _make_mail_route_line(context: Dictionary) -> Control:
	return _make_colored_process_line([
		{"text": "寄件人：", "color": PageTheme.INK_MUTED},
		{"text": String(context.get("senderName", "寄件居民")), "color": PageTheme.TERRACOTTA},
		{"text": "  →  收件人：", "color": PageTheme.INK_MUTED},
		{"text": String(context.get("recipientName", "收件居民")), "color": PageTheme.MOSS},
		{"text": "  ·  投递人：", "color": PageTheme.INK_MUTED},
		{"text": String(context.get("courierName", "投递居民")), "color": PageTheme.COURIER_BLUE},
	])


func _mail_process_parts(record: Dictionary, context: Dictionary) -> Array[Dictionary]:
	var payload := record.get("payload", {}) as Dictionary
	var event_type := String(payload.get("type", "")).strip_edges()
	var capability := String(payload.get("capability", "")).strip_edges()
	var status := String(payload.get("status", "")).to_lower()
	var sender := String(context.get("senderName", "寄件居民"))
	var recipient := String(context.get("recipientName", "收件居民"))
	var courier := String(context.get("courierName", "投递居民"))
	if (
		event_type == "消息取消"
		or status in ["failed", "cancelled", "canceled", "rejected", "expired"]
	):
		var reason := String(
			payload.get("reason", payload.get("waitReason", "")),
		).strip_edges()
		var outcome := (
			"取消了这封口信"
			if event_type == "消息取消" or status in ["cancelled", "canceled"]
			else "没能完成这封口信"
		)
		var result: Array[Dictionary] = [
			{"text": courier, "color": PageTheme.COURIER_BLUE},
			{"text": " " + outcome, "color": PageTheme.INK},
		]
		if not reason.is_empty():
			result.append({"text": "：" + reason, "color": PageTheme.INK_MUTED})
		return result
	if event_type == "消息创建":
		return [
			{"text": sender, "color": PageTheme.TERRACOTTA},
			{"text": " 把口信交给投递流程，收件人是 ", "color": PageTheme.INK},
			{"text": recipient, "color": PageTheme.MOSS},
		]
	if event_type == "消息送达":
		return [
			{"text": courier, "color": PageTheme.COURIER_BLUE},
			{"text": " 已把 ", "color": PageTheme.INK},
			{"text": sender, "color": PageTheme.TERRACOTTA},
			{"text": " 的口信当面交给 ", "color": PageTheme.INK},
			{"text": recipient, "color": PageTheme.MOSS},
		]
	if capability == "message.sort":
		return [
			{"text": courier, "color": PageTheme.COURIER_BLUE},
			{
				"text": " 已完成信件分拣" if status == "completed" else " 正在分拣这封口信",
				"color": PageTheme.INK,
			},
		]
	if capability == "message.prepare":
		return [
			{"text": courier, "color": PageTheme.COURIER_BLUE},
			{
				"text": " 已把口信装入邮袋" if status == "completed" else " 正在整理邮袋",
				"color": PageTheme.INK,
			},
		]
	if capability == "message.deliver":
		return [
			{"text": courier, "color": PageTheme.COURIER_BLUE},
			{
				"text": " 已完成投递任务" if status == "completed" else " 正在前往 ",
				"color": PageTheme.INK,
			},
			{"text": "" if status == "completed" else recipient, "color": PageTheme.MOSS},
			{"text": "" if status == "completed" else " 所在地点", "color": PageTheme.INK},
		]
	var actor := String(record.get("residentName", "")).strip_edges()
	var parts: Array[Dictionary] = []
	if not actor.is_empty():
		parts.append({"text": actor, "color": PageTheme.COURIER_BLUE})
		parts.append({"text": " · ", "color": PageTheme.INK_MUTED})
	parts.append({"text": _record_summary(record), "color": PageTheme.INK})
	return parts


func _make_colored_process_line(parts: Array[Dictionary]) -> RichTextLabel:
	var line := RichTextLabel.new()
	line.bbcode_enabled = false
	line.fit_content = true
	line.scroll_active = false
	line.selection_enabled = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.y = 30
	line.add_theme_font_size_override("normal_font_size", 19)
	line.add_theme_color_override("default_color", PageTheme.INK)
	for part: Dictionary in parts:
		var text_value := String(part.get("text", ""))
		if text_value.is_empty():
			continue
		line.push_color(part.get("color", PageTheme.INK) as Color)
		line.add_text(text_value)
		line.pop()
	return line


func _postal_process_summary(payload: Dictionary) -> String:
	var capability := String(payload.get("capability", ""))
	var status := String(payload.get("status", "")).to_lower()
	var process_stage := String(payload.get("processStage", ""))
	if status in ["failed", "cancelled", "canceled", "rejected", "expired"]:
		var reason := String(
			payload.get("reason", payload.get("waitReason", "")),
		).strip_edges()
		var prefix := (
			"口信投递已取消"
			if status in ["cancelled", "canceled"]
			else "口信投递未完成"
		)
		return "%s：%s" % [prefix, reason] if not reason.is_empty() else prefix
	if capability == "message.sort":
		if status == "completed":
			return "信件已经分拣完成"
		if status in ["accepted", "in_progress"]:
			return "正在分拣信件"
		return "信件正在等待分拣"
	if capability == "message.prepare":
		if status == "completed":
			return "口信已经装入邮袋"
		if status in ["accepted", "in_progress"]:
			return "正在整理邮袋"
		return "口信等待装袋"
	if capability == "message.deliver":
		if status == "completed":
			return "口信已经当面送达"
		if status in ["accepted", "in_progress"] or process_stage == "out_for_delivery":
			return "正在前往收件人所在地点"
		if process_stage == "awaiting_sort":
			return "口信正在等待分拣"
		if process_stage == "awaiting_prepare":
			return "口信正在等待装袋"
		return "口信等待投递"
	return ""


func _clear_children(node: Node) -> void:
	UiNodeRetirement.retire_children(node)


func _update_attention_token() -> void:
	var entry_point := entry_point_view_model()
	var token := String(entry_point.get("attentionToken", ""))
	var is_new := not token.is_empty() and token != _last_attention_token
	_last_attention_token = token
	entry_point_changed.emit(entry_point, is_new)


func _disconnect_adapter() -> void:
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if _adapter.is_connected("view_model_changed", callback):
			_adapter.disconnect("view_model_changed", callback)


func _refresh_from_adapter() -> void:
	if _adapter == null or not _adapter.has_method("get_view_model"):
		apply_view_model(_adapter_missing_view_model())
		return
	apply_view_model(_adapter.call("get_view_model", String(SCOPE)) as Dictionary)


func _on_view_model_changed(scope: String, snapshot: Dictionary) -> void:
	if scope == String(SCOPE):
		apply_view_model(snapshot)


func _validate_view_model(snapshot: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if snapshot.is_empty():
		issues.append("TOWN_LOG_VIEW_MODEL_EMPTY")
		return issues
	var data := snapshot.get("data", {}) as Dictionary
	var actions := snapshot.get("actions", {}) as Dictionary
	for key: String in REQUIRED_DATA_KEYS:
		if not data.has(key):
			issues.append("TOWN_LOG_DATA_MISSING_%s" % key.to_upper())
	for key: String in REQUIRED_ACTION_KEYS:
		if not actions.has(key):
			issues.append("TOWN_LOG_ACTION_MISSING_%s" % key.to_upper())
	if not data.get("rows", []) is Array:
		issues.append("TOWN_LOG_ROWS_INVALID")
	if not data.get("filters", {}) is Dictionary:
		issues.append("TOWN_LOG_FILTERS_INVALID")
	return issues


func _adapter_missing_view_model() -> Dictionary:
	var actions: Dictionary = {}
	for key: String in REQUIRED_ACTION_KEYS:
		actions[key] = {
			"intent": "town_log.%s" % key.to_snake_case(),
			"enabled": false,
			"disabledReason": "TOWN_LOG_ADAPTER_MISSING",
			"payload": {},
		}
	return {
		"scope": String(SCOPE),
		"revision": 0,
		"status": "disabled",
		"data": {
			"capabilityMode": "unavailable",
			"source": "unavailable",
			"formalReady": false,
			"panel": {"open": false, "title": "世界日志"},
			"state": "disabled",
			"errorCode": "TOWN_LOG_ADAPTER_MISSING",
			"summary": {"attentionUnreadThreadCount": 0, "totalUnreadThreadCount": 0, "hasNewerThreads": false},
			"entryPoint": {"unreadCount": 0, "hasUnread": false, "attentionToken": ""},
			"filters": {"residentId": "", "kindTag": "", "day": 0, "unreadOnly": false},
			"filterOptions": {"residents": [], "kinds": [], "days": []},
			"rows": [],
			"selectedThreadId": "",
			"detail": null,
			"detailPaging": {"cursor": 0, "hasMore": false, "isLoading": false},
			"paging": {"cursor": {}, "hasMore": false, "isLoading": false},
		},
		"actions": actions,
		"operation": {"requestId": "", "intent": "", "status": "disabled", "submittedAtMsec": 0, "completedAtMsec": 0},
		"error": {"kind": "unavailable", "code": "TOWN_LOG_ADAPTER_MISSING", "message": "世界日志资料库尚未绑定。", "retryable": false, "details": []},
	}


func _rect_to_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
