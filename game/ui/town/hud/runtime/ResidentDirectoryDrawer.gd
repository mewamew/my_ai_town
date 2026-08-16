class_name ResidentDirectoryDrawer
extends Control


const UI_KIT := preload(
	"res://ui/common/AiTownUiKit.gd"
)
const DRAWER_TEXTURE := preload(
	"res://assets/ui/town/hud/runtime/resident_directory/resident_directory_drawer_rgba.png"
)
const TRACK_TEXTURE := preload(
	"res://assets/ui/town/hud/runtime/resident_directory/resident_directory_scroll_track.png"
)
const THUMB_TEXTURE := preload(
	"res://assets/ui/town/hud/runtime/resident_directory/resident_directory_scroll_thumb.png"
)
const PLACE_DIRECTORY_TEXTURE := preload(
	"res://assets/ui/town/hud/runtime/place_directory/"
	+ "place_directory_drawer_rgba.png"
)
const ROW_NORMAL_TEXTURE := preload(
	"res://assets/ui/town/hud/runtime/resident_directory/"
	+ "resident_directory_row_normal_v4.png"
)
const ROW_SELECTED_TEXTURE := preload(
	"res://assets/ui/town/hud/runtime/resident_directory/"
	+ "resident_directory_row_selected_v4.png"
)
const FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const VISIBLE_ROWS := 6
const TOUCH_SWIPE_THRESHOLD := 30.0
const SOURCE_SIZE := Vector2(1024.0, 1536.0)
const HEADER_RECT := Rect2(190, 122, 548, 118)
const CLOSE_RECT := Rect2(760, 130, 102, 104)
const ROW_RECTS := [
	Rect2(174, 285, 628, 160),
	Rect2(174, 462, 628, 160),
	Rect2(174, 639, 628, 160),
	Rect2(174, 816, 628, 160),
	Rect2(174, 993, 628, 160),
	Rect2(174, 1170, 628, 160),
]
const ROW_CONTENT_SIZE := Vector2(604.0, 146.0)
# These slots are expressed in the source artwork's coordinate system.  The
# old HBox/VBox tree let container minimum sizes decide where the glyphs landed
# after the drawer was scaled, which is why the names could drift or disappear
# on a foldable/tablet.  Absolute slots keep the portrait, name and status on
# the painted row at every aspect ratio.
const ROW_PORTRAIT_RECT := Rect2(8.0, 10.0, 96.0, 126.0)
const ROW_NAME_RECT := Rect2(122.0, 5.0, 462.0, 64.0)
const ROW_STATUS_RECT := Rect2(122.0, 76.0, 462.0, 58.0)
const TRACK_RECT := Rect2(818, 320, 42, 1012)
const THUMB_HEIGHT := 212.0
const INK := Color("#3B2416")
const MUTED_INK := Color("#76563B")
const SELECTED_INK := Color("#7A4A12")

signal resident_requested(resident_id: String)
signal close_requested

@export var preview_font: Font

var _items: Array = []
var _selected_resident_id := ""
var _first_visible_index := 0
var _directory_snapshot: Dictionary = {}
var _directory_snapshot_initialized := false
var _background: TextureRect
var _header: Label
var _close_visual: TextureRect
var _close_button: Button
var _track: TextureRect
var _thumb: TextureRect
var _row_buttons: Array[Button] = []
var _row_selection: Array[TextureRect] = []
var _row_portraits: Array[TextureRect] = []
var _row_initials: Array[Label] = []
var _row_names: Array[Label] = []
var _row_statuses: Array[Label] = []
var _row_dots: Array[Label] = []
var _touch_scroll_tracking := false
var _touch_scroll_start := Vector2.ZERO
var _touch_scroll_last_y := 0.0
var _touch_scroll_pointer := -1
var _touch_scroll_dragged := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	if preview_font == null and ResourceLoader.exists(FONT_PATH):
		var font_file := load(FONT_PATH) as FontFile
		if font_file != null:
			var font := FontVariation.new()
			font.base_font = font_file
			font.spacing_glyph = 2
			font.spacing_space = 0
			font.variation_embolden = 0.0
			preview_font = font
	_build_visuals()
	if (
		OS.is_debug_build()
		and OS.get_environment("AI_TOWN_HUD_RESIDENT_DIRECTORY_GUIDES") == "1"
	):
		_build_layout_guides()
	resized.connect(_layout_children)
	_layout_children()


func apply_directory(data: Dictionary) -> void:
	if _directory_snapshot_initialized and data == _directory_snapshot:
		return
	_directory_snapshot = data.duplicate(true)
	_directory_snapshot_initialized = true
	_items = (data.get("items", []) as Array).duplicate(true)
	_selected_resident_id = String(data.get("selectedResidentId", ""))
	_first_visible_index = clampi(
		_first_visible_index,
		0,
		maxi(_items.size() - VISIBLE_ROWS, 0),
	)
	_render()


func open() -> void:
	visible = true
	focus_first_row()


func close() -> void:
	visible = false
	close_requested.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func focus_first_row() -> void:
	for button in _row_buttons:
		if button.visible and not button.disabled:
			button.grab_focus()
			return


func _build_visuals() -> void:
	_background = TextureRect.new()
	_background.texture = DRAWER_TEXTURE
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_header = _make_label(27, INK, HORIZONTAL_ALIGNMENT_LEFT)
	add_child(_header)

	var close_atlas := AtlasTexture.new()
	close_atlas.atlas = PLACE_DIRECTORY_TEXTURE
	close_atlas.region = CLOSE_RECT
	_close_visual = TextureRect.new()
	_close_visual.texture = close_atlas
	_close_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_close_visual.stretch_mode = TextureRect.STRETCH_SCALE
	_close_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_close_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_close_visual)

	_close_button = _make_button("收起居民目录")
	_close_button.accessibility_name = "关闭居民目录"
	_close_button.pressed.connect(close)
	add_child(_close_button)

	_track = TextureRect.new()
	_track.texture = TRACK_TEXTURE
	_track.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_track.stretch_mode = TextureRect.STRETCH_SCALE
	_track.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_track)
	_thumb = TextureRect.new()
	_thumb.texture = THUMB_TEXTURE
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_SCALE
	_thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_thumb)

	for row_index in VISIBLE_ROWS:
		var selection := TextureRect.new()
		selection.texture = ROW_NORMAL_TEXTURE
		selection.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		selection.stretch_mode = TextureRect.STRETCH_SCALE
		selection.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(selection)
		_row_selection.append(selection)

		var button := _make_button("聚焦并跟随居民")
		button.pressed.connect(_on_row_pressed.bind(row_index))
		button.gui_input.connect(_on_row_gui_input)
		add_child(button)
		_row_buttons.append(button)

		var content := Control.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(content)
		var portrait := TextureRect.new()
		portrait.position = ROW_PORTRAIT_RECT.position
		portrait.size = ROW_PORTRAIT_RECT.size
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(portrait)
		_row_portraits.append(portrait)
		var initial := _make_label(20, INK, HORIZONTAL_ALIGNMENT_CENTER)
		initial.position = ROW_PORTRAIT_RECT.position
		initial.size = ROW_PORTRAIT_RECT.size
		content.add_child(initial)
		_row_initials.append(initial)
		var name_label := _make_label(23, INK, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.position = ROW_NAME_RECT.position
		name_label.size = ROW_NAME_RECT.size
		name_label.add_theme_font_size_override("font_size", 26)
		content.add_child(name_label)
		_row_names.append(name_label)
		var status_label := _make_label(19, MUTED_INK, HORIZONTAL_ALIGNMENT_LEFT)
		status_label.position = ROW_STATUS_RECT.position
		status_label.size = ROW_STATUS_RECT.size
		status_label.add_theme_font_size_override("font_size", 21)
		content.add_child(status_label)
		_row_statuses.append(status_label)
		var dot := _make_label(20, SELECTED_INK, HORIZONTAL_ALIGNMENT_CENTER)
		dot.position = Rect2(570, 52, 28, 42).position
		dot.size = Rect2(570, 52, 28, 42).size
		dot.visible = false
		content.add_child(dot)
		_row_dots.append(dot)
		button.set_meta("content", content)


func _make_label(
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment,
) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if preview_font != null:
		label.add_theme_font_override("font", preview_font)
	return label


func _make_button(tooltip: String) -> Button:
	return UI_KIT.invisible_flat_button(tooltip)


func _build_layout_guides() -> void:
	_attach_guide(_header, Color("6dff8d"), 2.0)
	for row_index in VISIBLE_ROWS:
		_attach_guide(_row_buttons[row_index], Color("ffd166"), 1.0)
		_attach_guide(_row_portraits[row_index], Color("42d9ff"), 1.0)
		_attach_guide(_row_names[row_index], Color("6dff8d"), 1.0)
		_attach_guide(_row_statuses[row_index], Color("6dff8d"), 1.0)


func _attach_guide(control: Control, color: Color, width: float) -> void:
	var guide := ReferenceRect.new()
	guide.name = &"RuntimeSafeGuide"
	guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	guide.border_color = color
	guide.border_width = width
	guide.editor_only = false
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide.z_index = 100
	control.add_child(guide)


func _layout_children() -> void:
	if not is_instance_valid(_background):
		return
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_scaled_rect(_header, HEADER_RECT)
	_set_scaled_rect(_close_visual, CLOSE_RECT)
	_set_scaled_rect(_close_button, CLOSE_RECT)
	_set_scaled_rect(_track, TRACK_RECT)
	for row_index in VISIBLE_ROWS:
		var rect := _scaled_rect(ROW_RECTS[row_index])
		_row_selection[row_index].position = rect.position
		_row_selection[row_index].size = rect.size
		_row_buttons[row_index].position = rect.position
		_row_buttons[row_index].size = rect.size
		var content := _row_buttons[row_index].get_meta("content") as Control
		# Keep every child in the authored source coordinate space, then apply one
		# uniform transform.  This prevents container minimum sizes and non-uniform
		# viewport scaling from moving the glyphs away from their painted slots.
		var scale_value := _scale()
		content.position = rect.position + Vector2(12, 7) * scale_value
		content.size = ROW_CONTENT_SIZE
		content.scale = scale_value
	_layout_thumb()


func _set_scaled_rect(control: Control, source_rect: Rect2) -> void:
	var rect := _scaled_rect(source_rect)
	control.position = rect.position
	control.size = rect.size


func _scaled_rect(source_rect: Rect2) -> Rect2:
	var scale_value := _scale()
	return Rect2(source_rect.position * scale_value, source_rect.size * scale_value)


func _scale() -> Vector2:
	return Vector2(size.x / SOURCE_SIZE.x, size.y / SOURCE_SIZE.y)


func _render() -> void:
	if not is_instance_valid(_header):
		return
	var last_visible := mini(_first_visible_index + VISIBLE_ROWS, _items.size())
	_header.text = (
		"居民 %d–%d / %d" % [_first_visible_index + 1, last_visible, _items.size()]
		if not _items.is_empty()
		else "居民目录"
	)
	for row_index in VISIBLE_ROWS:
		var item_index := _first_visible_index + row_index
		var populated := item_index < _items.size()
		_row_buttons[row_index].visible = populated
		(_row_buttons[row_index].get_meta("content") as Control).visible = populated
		_row_selection[row_index].visible = populated
		if not populated:
			continue
		var item := _items[item_index] as Dictionary
		var resident_id := String(item.get("residentId", ""))
		var resident_name := String(item.get("residentName", "未知居民"))
		var portrait_value: Variant = item.get("portraitTexture")
		var portrait := _row_portraits[row_index]
		portrait.texture = portrait_value as Texture2D if portrait_value is Texture2D else null
		portrait.visible = portrait.texture != null
		_row_initials[row_index].visible = portrait.texture == null
		_row_initials[row_index].text = String(item.get("portraitFallbackText", resident_name.left(1)))
		_row_names[row_index].text = resident_name
		var behavior := String(item.get("behaviorLabel", "")).strip_edges()
		var short_behavior := String(
			item.get("behaviorShortLabel", behavior)
		).strip_edges()
		var location := String(item.get("locationLabel", "")).strip_edges()
		var full_status := behavior if not behavior.is_empty() else location
		_row_statuses[row_index].text = (
			short_behavior if not short_behavior.is_empty() else full_status
		)
		var selected := resident_id == _selected_resident_id
		_row_selection[row_index].texture = (
			ROW_SELECTED_TEXTURE if selected else ROW_NORMAL_TEXTURE
		)
		_row_dots[row_index].text = ""
		_row_buttons[row_index].set_meta("resident_id", resident_id)
		_row_buttons[row_index].set_meta("full_behavior_label", full_status)
		_row_buttons[row_index].tooltip_text = (
			"%s\n%s" % [resident_name, full_status]
			if not full_status.is_empty()
			else resident_name
		)
	_layout_thumb()


func _layout_thumb() -> void:
	if not is_instance_valid(_thumb):
		return
	var track := _scaled_rect(TRACK_RECT)
	var max_offset := maxi(_items.size() - VISIBLE_ROWS, 0)
	var thumb_source_height := (
		TRACK_RECT.size.y
		if max_offset == 0
		else maxf(THUMB_HEIGHT, TRACK_RECT.size.y * VISIBLE_ROWS / maxf(_items.size(), 1))
	)
	var travel_source := TRACK_RECT.size.y - thumb_source_height
	var progress := float(_first_visible_index) / float(max_offset) if max_offset > 0 else 0.0
	var thumb_rect := Rect2(
		Vector2(TRACK_RECT.position.x, TRACK_RECT.position.y + travel_source * progress),
		Vector2(TRACK_RECT.size.x, thumb_source_height),
	)
	_set_scaled_rect(_thumb, thumb_rect)
	_thumb.visible = not _items.is_empty()


func _on_row_pressed(row_index: int) -> void:
	if _touch_scroll_dragged:
		return
	var item_index := _first_visible_index + row_index
	if item_index < 0 or item_index >= _items.size():
		return
	var resident_id := String((_items[item_index] as Dictionary).get("residentId", ""))
	if not resident_id.is_empty():
		resident_requested.emit(resident_id)


func _on_row_gui_input(event: InputEvent) -> void:
	if _handle_touch_scroll(event):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_by(1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_by(-1)
			accept_event()


func _gui_input(event: InputEvent) -> void:
	if _handle_touch_scroll(event):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_by(1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_by(-1)
			accept_event()


func _handle_touch_scroll(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_scroll_pointer < 0:
			_touch_scroll_tracking = true
			_touch_scroll_start = touch.position
			_touch_scroll_last_y = touch.position.y
			_touch_scroll_pointer = touch.index
			_touch_scroll_dragged = false
			return false
		if touch.pressed or touch.index != _touch_scroll_pointer:
			return false
		_touch_scroll_tracking = false
		_touch_scroll_pointer = -1
		if _touch_scroll_dragged:
			accept_event()
			_reset_touch_scroll_dragged.call_deferred()
			return true
		return false
	if event is InputEventScreenDrag and _touch_scroll_tracking:
		var drag := event as InputEventScreenDrag
		if drag.index != _touch_scroll_pointer:
			return false
		var delta_y := drag.position.y - _touch_scroll_last_y
		if absf(delta_y) < TOUCH_SWIPE_THRESHOLD:
			return _touch_scroll_dragged
		var steps := maxi(1, int(absf(delta_y) / TOUCH_SWIPE_THRESHOLD))
		_scroll_by(-steps if delta_y > 0.0 else steps)
		_touch_scroll_last_y = drag.position.y
		_touch_scroll_dragged = true
		accept_event()
		return true
	return false


func _reset_touch_scroll_dragged() -> void:
	_touch_scroll_dragged = false


func _scroll_by(delta: int) -> void:
	var next_index := clampi(
		_first_visible_index + delta,
		0,
		maxi(_items.size() - VISIBLE_ROWS, 0),
	)
	if next_index == _first_visible_index:
		return
	_first_visible_index = next_index
	_render()
