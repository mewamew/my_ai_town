class_name ResidentOverviewScreen
extends Control


signal intent_requested(intent: StringName, payload: Dictionary)


const UI_KIT := preload(
	"res://ui/common/AiTownUiKit.gd"
)
const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")
const SCOPE := "resident_overview"
const SHELL_TEXTURE := preload(
	"res://assets/ui/resident_overview/runtime/"
	+ "resident_overview_editable_shell_1920x1080.png"
)
const MOBILE_BACKDROP_TEXTURE := preload(
	"res://assets/ui/opening_flow/shared/background/"
	+ "opening_flow_town_background_v1.png"
)
const MAIN_MENU_FONT_FILE := preload(
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const DESIGN_SIZE := Vector2(1920, 1080)
const INK := Color("3f2818")
const MUTED_INK := Color("76583d")
const GREEN_INK := Color("49684a")
const LIGHT_INK := Color("f7e7c8")
const ERROR_INK := Color("9a3f2f")
const CAPTURE_SAFE_RECT := Rect2(48, 48, 1824, 984)
const CAPTURE_SAFE_COLOR := Color("42d9ff")
const CAPTURE_SLOT_COLOR := Color("6dff8d")
const CAPTURE_HOST_COLOR := Color("ffd166")
const CAPTURE_BASELINE_COLOR := Color("ff5ad6")
const CAPTURE_BUTTON_COLOR := Color("ff8f3f")
const MOBILE_VISIBLE_ROSTER_ROWS := 7
const MOBILE_ROSTER_PAGE_STEP := 4
const MOBILE_ROSTER_ROW_SOURCE_RECT := Rect2(48, 150, 352, 48)

var _adapter: Object
var _view_model: Dictionary = {}
var _items: Array[Dictionary] = []
var _selected_resident_id := ""
var _route_payload: Dictionary = {}
var _route_selection_pending := false
var _feedback_text := ""
var _feedback_error := false

var _font: FontVariation
var _selected_font: FontVariation
var _mobile_backdrop: TextureRect
var _canvas: Control
var _back_label: Label
var _title_label: Label
var _subtitle_label: Label
var _count_label: Label
var _mode_label: Label
var _mobile_roster_faces: Array[NinePatchRect] = []
var _roster_labels: Array[Label] = []
var _roster_buttons: Array[Button] = []
var _detail_labels: Dictionary = {}
var _portrait: TextureRect
var _back_button: Button
var _primary_button: Button
var _secondary_button: Button
var _tertiary_button: Button
var _primary_label: Label
var _secondary_label: Label
var _tertiary_label: Label
var _safe_area_capture_mode := false
var _safe_area_capture_overlay: Control
var _layout_queued := false
var _mobile_roster_offset := 0
var _mobile_roster_pointer := -1
var _mobile_roster_press_y := 0.0
var _mobile_roster_dragged := false


func _ready() -> void:
	# This page is mounted below a top-level CanvasLayer host. Pin the page to
	# the actual viewport first, then center the fixed ImageGen canvas inside it.
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = FontVariation.new()
	_font.base_font = MAIN_MENU_FONT_FILE
	_font.spacing_glyph = 2
	_font.spacing_space = 0
	_font.variation_embolden = 0.0
	_selected_font = FontVariation.new()
	_selected_font.base_font = MAIN_MENU_FONT_FILE
	_selected_font.spacing_glyph = 2
	_selected_font.spacing_space = 0
	_selected_font.variation_embolden = 0.8
	_build_interface()
	resized.connect(_queue_layout)
	get_viewport().size_changed.connect(_queue_layout)
	_apply_layout()
	if _adapter != null:
		_refresh_from_adapter()
	_apply_route_selection()
	_render()


func _exit_tree() -> void:
	_disconnect_adapter()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var cancel_requested := event.is_action_pressed(&"ui_cancel")
	if event is InputEventKey:
		cancel_requested = cancel_requested or (event as InputEventKey).keycode == KEY_ESCAPE
	if not cancel_requested:
		return
	intent_requested.emit(&"resident_overview.close", {})
	get_viewport().set_input_as_handled()


func bind_town_ui_adapter(adapter: Object) -> void:
	_disconnect_adapter()
	_adapter = adapter
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		_adapter.connect(
			"view_model_changed",
			Callable(self, "_on_view_model_changed"),
		)
	if is_node_ready():
		_refresh_from_adapter()
		_render()


func unbind_town_ui_adapter() -> void:
	_disconnect_adapter()
	_adapter = null


func apply_route_payload(payload: Dictionary) -> void:
	_route_payload = payload.duplicate(true)
	_route_selection_pending = true
	if is_node_ready():
		_apply_route_selection()
		_render()


func navigation_state() -> Dictionary:
	return {
		"selectedResidentId": _selected_resident_id,
		"editing": false,
		"focusControl": "primary",
	}


func focus_default_control() -> void:
	for index in _roster_buttons.size():
		if (
			index < _items.size()
			and not _roster_buttons[index].disabled
			and String(_items[index].get("residentId", "")) == _selected_resident_id
		):
			_roster_buttons[index].grab_focus()
			return
	if not _primary_button.disabled:
		_primary_button.grab_focus()
	elif not _back_button.disabled:
		_back_button.grab_focus()


func debug_snapshot() -> Dictionary:
	var selected := _selected_item()
	return {
		"scope": String(_view_model.get("scope", "")),
		"residentCount": _items.size(),
		"selectedResidentId": _selected_resident_id,
		"selectedHome": String(selected.get("homeLabel", "")),
		"selectedOccupation": String(selected.get("occupationLabel", "")),
		"selectedWorkplace": String(selected.get("workplaceLabel", "")),
		"editing": false,
		"saving": false,
		"draft": {},
		"feedback": _feedback_text,
		"fontPath": MAIN_MENU_FONT_FILE.resource_path,
		"fontSpacingGlyph": _font.spacing_glyph if _font != null else -1,
		"viewportSize": size,
		"canvasPosition": _canvas.position if _canvas != null else Vector2.ZERO,
		"canvasDisplaySize": (
			DESIGN_SIZE * _canvas.scale
			if _canvas != null
			else Vector2.ZERO
		),
		"headerTitleCenterX": _label_host_center_x(_title_label),
		"headerSubtitleCenterX": _label_host_center_x(_subtitle_label),
		"headerCountAlignment": (
			_count_label.horizontal_alignment
			if _count_label != null
			else HORIZONTAL_ALIGNMENT_LEFT
		),
		"headerModeAlignment": (
			_mode_label.horizontal_alignment
			if _mode_label != null
			else HORIZONTAL_ALIGNMENT_LEFT
		),
		"safeAreaCaptureMode": _safe_area_capture_mode,
		"safeAreaOverlayMounted": is_instance_valid(
			_safe_area_capture_overlay
		),
		"typography": debug_typography_snapshot(),
	}


func set_safe_area_capture_mode(enabled: bool) -> void:
	_safe_area_capture_mode = enabled
	if not enabled:
		if is_instance_valid(_safe_area_capture_overlay):
			_safe_area_capture_overlay.visible = false
			_safe_area_capture_overlay.queue_free()
		_safe_area_capture_overlay = null
		return
	if is_instance_valid(_safe_area_capture_overlay):
		_safe_area_capture_overlay.visible = true
		_safe_area_capture_overlay.queue_redraw()
		return
	_safe_area_capture_overlay = Control.new()
	_safe_area_capture_overlay.name = &"ResidentOverviewCaptureOnlySafeArea"
	_safe_area_capture_overlay.position = Vector2.ZERO
	_safe_area_capture_overlay.size = DESIGN_SIZE
	_safe_area_capture_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe_area_capture_overlay.z_index = 1000
	_safe_area_capture_overlay.set_meta("capture_only", true)
	_safe_area_capture_overlay.draw.connect(
		_draw_safe_area_capture_overlay.bind(_safe_area_capture_overlay)
	)
	_canvas.add_child(_safe_area_capture_overlay)
	_safe_area_capture_overlay.queue_redraw()


func debug_typography_snapshot() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	_append_typography_record(records, "header.back", "header", _back_label)
	_append_typography_record(records, "header.title", "header", _title_label)
	_append_typography_record(
		records,
		"header.subtitle",
		"header",
		_subtitle_label,
	)
	_append_typography_record(records, "header.count", "header", _count_label)
	_append_typography_record(records, "header.mode", "header", _mode_label)
	for index in _roster_labels.size():
		_append_typography_record(
			records,
			"roster.%02d" % index,
			"roster",
			_roster_labels[index],
		)
	for key in [
		"identity",
		"occupation",
		"availability",
		"left_title",
		"left_body",
		"right_title",
		"right_body",
		"summary_title",
		"summary_body",
		"feedback",
		"portrait_title",
		"home",
		"occupation_side",
		"workplace",
		"side_identity",
		"side_location",
	]:
		_append_typography_record(
			records,
			"detail.%s" % key,
			"detail",
			_detail_labels.get(key) as Label,
		)
	_append_typography_record(
		records,
		"action.modify",
		"action",
		_primary_label,
	)
	_append_typography_record(
		records,
		"action.follow",
		"action",
		_secondary_label,
	)
	_append_typography_record(
		records,
		"action.detail",
		"action",
		_tertiary_label,
	)
	return records


func select_resident_for_test(resident_id: String) -> bool:
	if not _has_resident(resident_id):
		return false
	_selected_resident_id = resident_id
	_feedback_text = ""
	_render()
	return true


func _build_interface() -> void:
	if MOBILE_UI_PROFILE.is_mobile_runtime():
		_mobile_backdrop = TextureRect.new()
		_mobile_backdrop.name = &"ResidentOverviewMobileBackdrop"
		_mobile_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_mobile_backdrop.texture = MOBILE_BACKDROP_TEXTURE
		_mobile_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_mobile_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_mobile_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mobile_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_mobile_backdrop)
	_canvas = Control.new()
	_canvas.name = &"ResidentOverviewCanvas"
	_canvas.size = DESIGN_SIZE
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_canvas)

	var background := TextureRect.new()
	background.name = &"ResidentOverviewImageGenShell"
	background.texture = SHELL_TEXTURE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.size = DESIGN_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.add_child(background)

	_back_label = _add_label(
		"返回",
		Rect2(69, 52, 150, 44),
		25,
		INK,
	)
	_back_label.name = &"HeaderBackLabel"
	_title_label = _add_label(
		"居民总览",
		Rect2(570, 48, 780, 38),
		28,
		INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_title_label.name = &"HeaderTitleLabel"
	_subtitle_label = _add_label(
		"查看本局居民的住所、职业、位置与公开行动",
		Rect2(560, 86, 800, 24),
		16,
		MUTED_INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_subtitle_label.name = &"HeaderSubtitleLabel"
	_count_label = _add_label(
		"0 位居民",
		Rect2(1530, 51, 290, 32),
		22,
		INK,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	_count_label.name = &"HeaderResidentCountLabel"
	_mode_label = _add_label(
		"本局资料可修改",
		Rect2(1480, 86, 340, 27),
		19,
		GREEN_INK,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	_mode_label.name = &"HeaderModeLabel"

	for index in 15:
		# The paper rows are separated by ornamental rules. Keep the glyph band
		# inside the row's true writable strip instead of centering against the
		# full painted row including its rule.
		var row_rect := (
			Rect2(48, 146 + index * 100.0, 360, 86)
			if MOBILE_UI_PROFILE.is_mobile_runtime()
			else Rect2(62, 150 + index * 48.15, 330, 36)
		)
		if MOBILE_UI_PROFILE.is_mobile_runtime():
			var row_texture := AtlasTexture.new()
			row_texture.atlas = SHELL_TEXTURE
			row_texture.region = MOBILE_ROSTER_ROW_SOURCE_RECT
			var row_face := NinePatchRect.new()
			row_face.name = StringName("ResidentOverviewRosterFace%02d" % index)
			row_face.position = row_rect.position
			row_face.size = row_rect.size
			row_face.texture = row_texture
			row_face.patch_margin_left = 14
			row_face.patch_margin_top = 12
			row_face.patch_margin_right = 14
			row_face.patch_margin_bottom = 12
			row_face.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
			row_face.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
			row_face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			row_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_canvas.add_child(row_face)
			_mobile_roster_faces.append(row_face)
		var row_label := _add_label(
			"",
			row_rect.grow(-10.0) if MOBILE_UI_PROFILE.is_mobile_runtime() else row_rect,
			22 if MOBILE_UI_PROFILE.is_mobile_runtime() else 17,
			MUTED_INK,
		)
		row_label.name = StringName("ResidentRosterLabel%02d" % index)
		_roster_labels.append(row_label)
		var row_button := _add_button(
			"ResidentRow%02d" % index,
			row_rect,
			"选择第 %d 位居民" % (index + 1),
		)
		row_button.pressed.connect(_select_row.bind(index))
		row_button.gui_input.connect(_on_mobile_roster_input)
		_roster_buttons.append(row_button)

	_detail_labels["identity"] = _add_label(
		"",
		Rect2(505, 220, 255, 40),
		21,
		INK,
	)
	(_detail_labels["identity"] as Label).name = &"DetailIdentityLabel"
	_detail_labels["occupation"] = _add_label(
		"",
		Rect2(790, 220, 210, 40),
		20,
		INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	(_detail_labels["occupation"] as Label).name = &"DetailOccupationLabel"
	_detail_labels["availability"] = _add_label(
		"",
		Rect2(1028, 220, 360, 40),
		20,
		GREEN_INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	(_detail_labels["availability"] as Label).name = &"DetailAvailabilityLabel"

	_detail_labels["left_title"] = _add_label(
		"位置与日程",
		Rect2(505, 304, 390, 36),
		23,
		INK,
	)
	(_detail_labels["left_title"] as Label).name = &"DetailLocationTitleLabel"
	_detail_labels["left_body"] = _add_label(
		"",
		Rect2(505, 357, 405, 178),
		20,
		MUTED_INK,
		HORIZONTAL_ALIGNMENT_LEFT,
		true,
	)
	(_detail_labels["left_body"] as Label).name = &"DetailLocationBodyLabel"
	_detail_labels["right_title"] = _add_label(
		"当前公开行动",
		Rect2(950, 304, 390, 36),
		23,
		INK,
	)
	(_detail_labels["right_title"] as Label).name = &"DetailActionTitleLabel"
	_detail_labels["right_body"] = _add_label(
		"",
		Rect2(950, 357, 405, 178),
		20,
		MUTED_INK,
		HORIZONTAL_ALIGNMENT_LEFT,
		true,
	)
	(_detail_labels["right_body"] as Label).name = &"DetailActionBodyLabel"
	_detail_labels["summary_title"] = _add_label(
		"公开状态摘要",
		Rect2(505, 624, 300, 36),
		23,
		INK,
	)
	(_detail_labels["summary_title"] as Label).name = &"DetailSummaryTitleLabel"
	_detail_labels["summary_body"] = _add_label(
		"",
		Rect2(505, 677, 830, 104),
		20,
		MUTED_INK,
		HORIZONTAL_ALIGNMENT_LEFT,
		true,
	)
	(_detail_labels["summary_body"] as Label).name = &"DetailSummaryBodyLabel"
	_detail_labels["feedback"] = _add_label(
		"",
		Rect2(505, 827, 835, 50),
		20,
		GREEN_INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	(_detail_labels["feedback"] as Label).name = &"DetailFeedbackLabel"

	_detail_labels["portrait_title"] = _add_label(
		"居民形象",
		Rect2(1460, 173, 355, 40),
		24,
		INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	(_detail_labels["portrait_title"] as Label).name = &"DetailPortraitTitleLabel"
	_portrait = TextureRect.new()
	_portrait.name = &"ResidentPortrait"
	_portrait.position = Vector2(1545, 280)
	_portrait.size = Vector2(225, 225)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_portrait)

	_detail_labels["home"] = _add_label(
		"",
		Rect2(1457, 566, 355, 40),
		20,
		INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	(_detail_labels["home"] as Label).name = &"DetailHomeLabel"
	_detail_labels["occupation_side"] = _add_label(
		"",
		Rect2(1457, 639, 355, 40),
		20,
		INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	(_detail_labels["occupation_side"] as Label).name = &"DetailSideOccupationLabel"
	_detail_labels["workplace"] = _add_label(
		"",
		Rect2(1457, 711, 355, 40),
		20,
		INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	(_detail_labels["workplace"] as Label).name = &"DetailWorkplaceLabel"
	_detail_labels["side_identity"] = _add_label(
		"",
		Rect2(1463, 790, 343, 34),
		19,
		GREEN_INK,
		HORIZONTAL_ALIGNMENT_LEFT,
	)
	(_detail_labels["side_identity"] as Label).name = &"DetailSideIdentityLabel"
	_detail_labels["side_location"] = _add_label(
		"",
		Rect2(1463, 832, 343, 34),
		19,
		GREEN_INK,
		HORIZONTAL_ALIGNMENT_LEFT,
	)
	(_detail_labels["side_location"] as Label).name = &"DetailSideLocationLabel"

	var primary_rect := Rect2(405, 958, 330, 88)
	var secondary_rect := Rect2(790, 958, 340, 88)
	var tertiary_rect := Rect2(1184, 958, 340, 88)
	_primary_label = _add_action_label(
		"修改资料",
		primary_rect,
		27,
		INK,
	)
	_primary_label.name = &"PrimaryActionLabel"
	_secondary_label = _add_action_label(
		"跟随居民",
		secondary_rect,
		27,
		LIGHT_INK,
	)
	_secondary_label.name = &"SecondaryActionLabel"
	_tertiary_label = _add_action_label(
		"查看关系",
		tertiary_rect,
		27,
		INK,
	)
	_tertiary_label.name = &"TertiaryActionLabel"

	_back_button = _add_button(
		"BackButton",
		Rect2(54, 31, 130, 72),
		"返回观察 HUD",
	)
	_back_button.pressed.connect(
		func() -> void: intent_requested.emit(&"resident_overview.close", {})
	)
	_primary_button = _add_button(
		"PrimaryActionButton",
		primary_rect,
		"修改当前居民资料",
	)
	_primary_button.pressed.connect(_on_primary_pressed)
	_secondary_button = _add_button(
		"SecondaryActionButton",
		secondary_rect,
		"跟随当前居民",
	)
	_secondary_button.pressed.connect(_on_secondary_pressed)
	_tertiary_button = _add_button(
		"TertiaryActionButton",
		tertiary_rect,
		"查看当前居民关系",
	)
	_tertiary_button.pressed.connect(_request_detail)


func _add_action_label(
	text: String,
	button_rect: Rect2,
	font_size: int,
	color: Color,
) -> Label:
	# Every live label uses the same four-sided inset from its image button well.
	return _add_label(
		text,
		button_rect.grow(-12.0),
		font_size,
		color,
		HORIZONTAL_ALIGNMENT_CENTER,
	)


func _label_host_center_x(label: Label) -> float:
	if label == null or not label.get_parent() is Control:
		return -1.0
	var host := label.get_parent() as Control
	return host.position.x + host.size.x * 0.5


func _add_label(
	text: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	alignment := HORIZONTAL_ALIGNMENT_LEFT,
	wrap := false,
) -> Label:
	var container := MarginContainer.new()
	container.position = rect.position.round()
	container.size = rect.size.round()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_theme_constant_override("margin_left", 7)
	container.add_theme_constant_override("margin_right", 7)
	container.add_theme_constant_override("margin_top", 3)
	container.add_theme_constant_override("margin_bottom", 3)
	_canvas.add_child(container)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP if wrap else VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.max_lines_visible = 4 if wrap else 1
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_constant_override("line_spacing", 6)
	container.add_child(label)
	return label


func _add_button(node_name: String, rect: Rect2, tooltip: String) -> Button:
	return UI_KIT.invisible_nav_button(_canvas, node_name, rect, tooltip)


func _append_typography_record(
	records: Array[Dictionary],
	id: String,
	group: String,
	label: Label,
) -> void:
	if label == null or not is_instance_valid(label) or _canvas == null:
		return
	var rect := _control_rect_in_canvas(label)
	var host_rect := rect
	if label.get_parent() is Control:
		host_rect = _control_rect_in_canvas(label.get_parent() as Control)
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var ascent := font.get_ascent(font_size) if font != null else 0.0
	var descent := font.get_descent(font_size) if font != null else 0.0
	var line_height := font.get_height(font_size) if font != null else 0.0
	var line_spacing := float(label.get_theme_constant("line_spacing"))
	var visible_lines := maxi(1, label.get_visible_line_count())
	var measured_width := 0.0
	if font != null:
		for line_value: Variant in label.text.split("\n", true):
			measured_width = maxf(
				measured_width,
				font.get_string_size(
					String(line_value),
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					font_size,
				).x,
			)
	var text_height := (
		line_height * visible_lines
		+ line_spacing * maxi(visible_lines - 1, 0)
	)
	var line_top := rect.position.y
	match label.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			line_top += maxf(0.0, (rect.size.y - text_height) * 0.5)
		VERTICAL_ALIGNMENT_BOTTOM:
			line_top += maxf(0.0, rect.size.y - text_height)
	var displayed_width := minf(measured_width, rect.size.x)
	var ink_x := rect.position.x
	match label.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			ink_x += maxf(0.0, (rect.size.x - displayed_width) * 0.5)
		HORIZONTAL_ALIGNMENT_RIGHT:
			ink_x += maxf(0.0, rect.size.x - displayed_width)
	var first_baseline := line_top + ascent
	var last_baseline := (
		first_baseline
		+ (line_height + line_spacing) * maxi(visible_lines - 1, 0)
	)
	records.append({
		"id": id,
		"group": group,
		"text": label.text,
		"visible": label.visible and not label.text.is_empty(),
		"rect": rect,
		"hostRect": host_rect,
		"fontSize": font_size,
		"ascent": ascent,
		"descent": descent,
		"lineHeight": line_height,
		"visibleLineCount": visible_lines,
		"horizontalAlignment": label.horizontal_alignment,
		"verticalAlignment": label.vertical_alignment,
		"overrun": label.text_overrun_behavior,
		"clipText": label.clip_text,
		"singleLine": label.autowrap_mode == TextServer.AUTOWRAP_OFF,
		"measuredWidth": measured_width,
		"displayedWidth": displayed_width,
		"ellipsisRequired": measured_width > rect.size.x,
		"firstBaselineY": first_baseline,
		"lastBaselineY": last_baseline,
		"inkRect": Rect2(
			Vector2(ink_x, line_top),
			Vector2(displayed_width, minf(text_height, rect.size.y)),
		),
		"hostTopClearance": line_top - host_rect.position.y,
		"hostBottomClearance": (
			host_rect.end.y - minf(last_baseline + descent, rect.end.y)
		),
	})


func _control_rect_in_canvas(control: Control) -> Rect2:
	if control == null or _canvas == null:
		return Rect2()
	var relative := (
		_canvas.get_global_transform().affine_inverse()
		* control.get_global_transform()
	)
	return Rect2(
		relative.origin,
		Vector2(
			control.size.x * relative.x.length(),
			control.size.y * relative.y.length(),
		),
	)


func _draw_safe_area_capture_overlay(canvas: Control) -> void:
	if not _safe_area_capture_mode or canvas == null:
		return
	canvas.draw_rect(CAPTURE_SAFE_RECT, CAPTURE_SAFE_COLOR, false, 2.0)
	for record in debug_typography_snapshot():
		if not bool(record.get("visible", false)):
			continue
		var host_rect := record.get("hostRect", Rect2()) as Rect2
		var rect := record.get("rect", Rect2()) as Rect2
		if host_rect.has_area():
			canvas.draw_rect(host_rect, CAPTURE_HOST_COLOR, false, 1.0)
		if rect.has_area():
			canvas.draw_rect(rect, CAPTURE_SLOT_COLOR, false, 1.0)
			var baseline_y := float(record.get("firstBaselineY", -1.0))
			if baseline_y >= rect.position.y and baseline_y <= rect.end.y:
				canvas.draw_line(
					Vector2(rect.position.x, baseline_y),
					Vector2(rect.end.x, baseline_y),
					CAPTURE_BASELINE_COLOR,
					1.0,
				)
	for button in [
		_back_button,
		_primary_button,
		_secondary_button,
		_tertiary_button,
	]:
		if button == null or not button.visible:
			continue
		var rect := _control_rect_in_canvas(button)
		if rect.has_area():
			canvas.draw_rect(rect, CAPTURE_BUTTON_COLOR, false, 2.0)


func _apply_layout() -> void:
	if _canvas == null:
		_layout_queued = false
		return
	var viewport_size := get_viewport_rect().size
	# Do not inherit a stale page rect from a previously sized Host. The image,
	# labels and hit targets all share this exact viewport-centered transform.
	position = Vector2.ZERO
	size = viewport_size
	var scale_factor := minf(
		viewport_size.x / DESIGN_SIZE.x,
		viewport_size.y / DESIGN_SIZE.y,
	)
	_canvas.scale = Vector2.ONE * scale_factor
	_canvas.position = (viewport_size - DESIGN_SIZE * scale_factor) * 0.5
	_layout_queued = false


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	_apply_layout.call_deferred()


func _refresh_from_adapter() -> void:
	if _adapter == null or not _adapter.has_method("get_view_model"):
		return
	var snapshot: Variant = _adapter.call("get_view_model", SCOPE)
	if snapshot is Dictionary:
		_apply_view_model(snapshot as Dictionary)


func _apply_view_model(view_model: Dictionary) -> void:
	if String(view_model.get("scope", "")) != SCOPE:
		return
	_view_model = view_model.duplicate(true)
	var data := view_model.get("data", {}) as Dictionary
	_items.clear()
	for value: Variant in data.get("residents", []) as Array:
		if value is Dictionary:
			_items.append((value as Dictionary).duplicate(true))
	_apply_route_selection()
	_render()


func _apply_route_selection() -> void:
	var requested := String(_route_payload.get("selectedResidentId", ""))
	if (
		_route_selection_pending
		and not requested.is_empty()
		and _has_resident(requested)
	):
		_selected_resident_id = requested
		_route_selection_pending = false
	elif _selected_resident_id.is_empty() or not _has_resident(_selected_resident_id):
		var data := _view_model.get("data", {}) as Dictionary
		_selected_resident_id = String(data.get("selectedResidentId", ""))
	if (
		(_selected_resident_id.is_empty() or not _has_resident(_selected_resident_id))
		and not _items.is_empty()
	):
		_selected_resident_id = String(_items[0].get("residentId", ""))
	if _route_selection_pending and (requested.is_empty() or not _items.is_empty()):
		_route_selection_pending = false


func _has_resident(resident_id: String) -> bool:
	for item in _items:
		if String(item.get("residentId", "")) == resident_id:
			return true
	return false


func _selected_item() -> Dictionary:
	for item in _items:
		if String(item.get("residentId", "")) == _selected_resident_id:
			return item.duplicate(true)
	return {}


func _render() -> void:
	if _count_label == null:
		return
	var mobile_last := mini(
		_mobile_roster_offset + MOBILE_VISIBLE_ROSTER_ROWS,
		_items.size(),
	)
	_count_label.text = (
		"%d 位 · %d-%d" % [
			_items.size(),
			_mobile_roster_offset + 1,
			mobile_last,
		]
		if MOBILE_UI_PROFILE.is_mobile_runtime() and not _items.is_empty()
		else "%d 位居民" % _items.size()
	)
	_mode_label.text = "本局居民总览"
	for index in 15:
		var item_index := (
			_mobile_roster_offset + index
			if MOBILE_UI_PROFILE.is_mobile_runtime()
			else index
		)
		var visible := (
			index < MOBILE_VISIBLE_ROSTER_ROWS and item_index < _items.size()
			if MOBILE_UI_PROFILE.is_mobile_runtime()
			else item_index < _items.size()
		)
		_roster_labels[index].visible = visible
		_roster_buttons[index].visible = visible
		if index < _mobile_roster_faces.size():
			_mobile_roster_faces[index].visible = visible
		if not visible:
			continue
		var item := _items[item_index]
		var selected := String(item.get("residentId", "")) == _selected_resident_id
		_roster_labels[index].text = "%02d  %s  %s" % [
			item_index + 1,
			String(item.get("displayName", "未命名居民")),
			String(item.get("occupationLabel", "暂无职业")),
		]
		_roster_labels[index].add_theme_color_override(
			"font_color",
			GREEN_INK if selected else MUTED_INK,
		)
		_roster_labels[index].add_theme_font_override(
			"font",
			_selected_font if selected else _font,
		)
		_roster_buttons[index].disabled = false
		_roster_buttons[index].focus_mode = Control.FOCUS_ALL

	var selected := _selected_item()
	var available := not selected.is_empty()
	var actions := _view_model.get("actions", {}) as Dictionary
	var follow_enabled := bool(
		(actions.get("follow", {}) as Dictionary).get("enabled", false),
	)
	var update_enabled := bool(
		(actions.get("updateProfile", {}) as Dictionary).get("enabled", false),
	)
	_primary_button.disabled = not available or not update_enabled
	_secondary_button.disabled = not available or not follow_enabled
	_tertiary_button.disabled = not available

	if not available:
		_render_unavailable()
		return
	_render_portrait(
		String(selected.get("portraitRef", "")),
		String(selected.get("portraitFrameMode", "legacy_atlas_64x64")),
	)
	_render_overview(selected)


func _render_unavailable() -> void:
	(_detail_labels["identity"] as Label).text = "居民资料暂不可用"
	(_detail_labels["occupation"] as Label).text = ""
	(_detail_labels["availability"] as Label).text = "等待运行数据"
	(_detail_labels["left_body"] as Label).text = "世界尚未返回居民详情。"
	(_detail_labels["right_body"] as Label).text = ""
	(_detail_labels["summary_body"] as Label).text = ""
	(_detail_labels["feedback"] as Label).text = "请返回小镇后重试。"
	(_detail_labels["home"] as Label).text = ""
	(_detail_labels["occupation_side"] as Label).text = ""
	(_detail_labels["workplace"] as Label).text = ""
	(_detail_labels["side_identity"] as Label).text = ""
	(_detail_labels["side_location"] as Label).text = ""
	_portrait.texture = null


func _render_overview(selected: Dictionary) -> void:
	var resident_name := String(selected.get("displayName", "未命名居民"))
	var gender := String(selected.get("genderLabel", "未知"))
	var age := int(selected.get("age", 0))
	var home := String(selected.get("homeLabel", "住处未知"))
	var occupation := String(selected.get("occupationLabel", "暂无职业"))
	var workplace := String(selected.get("workplaceLabel", "工作地点未知"))
	var location := String(selected.get("currentPlaceLabel", "位置未知"))
	var action := String(selected.get("currentActionLabel", "暂无公开行动"))
	var phase := String(selected.get("actionPhaseLabel", "状态已同步"))
	var availability := String(selected.get("availabilityLabel", "可跟随"))
	(_detail_labels["identity"] as Label).text = "姓名  %s" % resident_name
	(_detail_labels["occupation"] as Label).text = "职业  %s" % occupation
	(_detail_labels["availability"] as Label).text = "可用状态  %s" % availability
	(_detail_labels["left_title"] as Label).text = "位置与日程"
	(_detail_labels["left_body"] as Label).text = (
		"住处  %s\n当前位置  %s\n工作地点  %s" % [home, location, workplace]
	)
	(_detail_labels["right_title"] as Label).text = "当前公开行动"
	(_detail_labels["right_body"] as Label).text = (
		"正在  %s\n行动阶段  %s\n资料状态  已从世界回读" % [action, phase]
	)
	(_detail_labels["summary_title"] as Label).text = "公开状态摘要"
	(_detail_labels["summary_body"] as Label).text = (
		"%s目前在%s，正在%s。\n深入资料可从居民详情继续查看。"
		% [resident_name, location, action]
	)
	_set_feedback(
		_feedback_text
		if not _feedback_text.is_empty()
		else "本页只读汇总本局居民；关系、记忆和完整状态进入居民详情。",
		_feedback_error,
	)
	(_detail_labels["home"] as Label).text = "住处  %s" % home
	(_detail_labels["occupation_side"] as Label).text = "职业  %s" % occupation
	(_detail_labels["workplace"] as Label).text = "工作地点  %s" % workplace
	(_detail_labels["side_identity"] as Label).text = "身份  %s · %d 岁" % [
		gender,
		age,
	]
	var side_location := _detail_labels["side_location"] as Label
	side_location.text = "当前位置  %s" % location
	side_location.tooltip_text = side_location.text
	_primary_label.text = "修改资料"
	_secondary_label.text = "跟随居民"
	_secondary_label.add_theme_color_override("font_color", LIGHT_INK)
	_tertiary_label.text = "查看关系"
	_primary_button.tooltip_text = "修改当前居民的本局资料"
	_secondary_button.tooltip_text = "定位并跟随当前居民"
	_tertiary_button.tooltip_text = "打开当前居民的关系摘要"


func _set_feedback(text: String, error: bool) -> void:
	var label := _detail_labels["feedback"] as Label
	label.text = text
	label.add_theme_color_override("font_color", ERROR_INK if error else GREEN_INK)


func show_navigation_failure(message: String) -> void:
	_feedback_text = message.strip_edges()
	_feedback_error = true
	if _feedback_text.is_empty():
		_feedback_text = "页面暂时打不开，请稍后再试。"
	if is_node_ready() and not _view_model.is_empty():
		_render()


func _render_portrait(
	sprite_path: String,
	frame_mode: String = "legacy_atlas_64x64",
) -> void:
	_portrait.texture = null
	if sprite_path.is_empty() or not ResourceLoader.exists(sprite_path):
		return
	var sprite := ResourceLoader.load(sprite_path, "Texture2D") as Texture2D
	if sprite == null:
		return
	if frame_mode == "full_texture":
		_portrait.texture = sprite
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = sprite
	atlas.region = Rect2(0, 0, 64, 64)
	_portrait.texture = atlas


func _select_row(index: int) -> void:
	if _mobile_roster_dragged:
		return
	var item_index := (
		_mobile_roster_offset + index
		if MOBILE_UI_PROFILE.is_mobile_runtime()
		else index
	)
	if item_index < 0 or item_index >= _items.size():
		return
	_selected_resident_id = String(_items[item_index].get("residentId", ""))
	_feedback_text = ""
	_feedback_error = false
	_render()


func _on_mobile_roster_input(event: InputEvent) -> void:
	if not MOBILE_UI_PROFILE.is_mobile_runtime():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _mobile_roster_pointer < 0:
			_mobile_roster_pointer = touch.index
			_mobile_roster_press_y = touch.position.y
			_mobile_roster_dragged = false
		elif not touch.pressed and touch.index == _mobile_roster_pointer:
			if _mobile_roster_dragged:
				var direction := (
					MOBILE_ROSTER_PAGE_STEP
					if touch.position.y < _mobile_roster_press_y
					else -MOBILE_ROSTER_PAGE_STEP
				)
				_mobile_roster_offset = clampi(
					_mobile_roster_offset + direction,
					0,
					maxi(_items.size() - MOBILE_VISIBLE_ROSTER_ROWS, 0),
				)
				_render()
				accept_event()
			_mobile_roster_pointer = -1
			_reset_mobile_roster_drag.call_deferred()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if (
			drag.index == _mobile_roster_pointer
			and absf(drag.position.y - _mobile_roster_press_y) >= 24.0
		):
			_mobile_roster_dragged = true
			accept_event()


func _reset_mobile_roster_drag() -> void:
	_mobile_roster_dragged = false


func _on_primary_pressed() -> void:
	if _selected_resident_id.is_empty():
		return
	intent_requested.emit(&"resident_overview.edit_profile", {
		"residentId": _selected_resident_id,
	})


func _on_secondary_pressed() -> void:
	_request_follow()


func _request_follow() -> void:
	if (
		_selected_resident_id.is_empty()
		or _adapter == null
		or not _adapter.has_method("dispatch")
	):
		return
	var result := _adapter.call(
		"dispatch",
		"resident_overview.follow",
		{"residentId": _selected_resident_id},
	) as Dictionary
	if not bool(result.get("ok", false)):
		_feedback_text = _error_message(String(result.get("errorCode", "")))
		_feedback_error = true
		_render()
	intent_requested.emit(&"resident_overview.follow", {
		"residentId": _selected_resident_id,
		"dispatchResult": result.duplicate(true),
	})


func _request_detail() -> void:
	if _selected_resident_id.is_empty():
		return
	intent_requested.emit(&"resident_overview.open_detail", {
		"residentId": _selected_resident_id,
		"tab": "relationships",
	})


func _error_message(error_code: String) -> String:
	return {
		"RESIDENT_IDENTITY_NOT_FOUND": "没有找到这位居民，请重新选择。",
		"RESIDENT_FOLLOW_REJECTED": "当前无法跟随这位居民。",
	}.get(error_code, "操作没有完成，当前居民信息没有变化。")


func _on_view_model_changed(scope: String, view_model: Dictionary) -> void:
	if scope == SCOPE:
		_apply_view_model(view_model)


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_view_model_changed"),
	)
