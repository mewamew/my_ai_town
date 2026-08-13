class_name PlaceDirectoryDrawer
extends Control


const UI_KIT := preload(
	"res://ui/common/AiTownUiKit.gd"
)
const DRAWER_TEXTURE := preload(
	"res://assets/ui/town/hud/runtime/place_directory/"
	+ "place_directory_drawer_rgba.png"
)
const FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const SOURCE_SIZE := Vector2(1024.0, 1536.0)
const VISIBLE_ROWS := 6
const HEADER_RECT := Rect2(190, 104, 548, 112)
const CLOSE_RECT := Rect2(772, 116, 98, 98)
const ROW_RECTS := [
	Rect2(174, 278, 638, 182),
	Rect2(174, 468, 638, 182),
	Rect2(174, 658, 638, 182),
	Rect2(174, 848, 638, 182),
	Rect2(174, 1038, 638, 182),
	Rect2(174, 1228, 638, 182),
]
const ICON_RECTS := [
	Rect2(184, 292, 154, 148),
	Rect2(184, 481, 154, 148),
	Rect2(184, 671, 154, 148),
	Rect2(184, 862, 154, 148),
	Rect2(184, 1054, 154, 148),
	Rect2(184, 1246, 154, 148),
]
const NAME_RECTS := [
	Rect2(400, 298, 365, 76),
	Rect2(400, 487, 365, 76),
	Rect2(400, 677, 365, 76),
	Rect2(400, 868, 365, 76),
	Rect2(400, 1060, 365, 76),
	Rect2(400, 1252, 365, 76),
]
const STATE_RECTS := [
	Rect2(400, 391, 365, 58),
	Rect2(400, 579, 365, 58),
	Rect2(400, 769, 365, 58),
	Rect2(400, 960, 365, 58),
	Rect2(400, 1152, 365, 58),
	Rect2(400, 1344, 365, 58),
]
const INK := Color("3f2818")
const MUTED_INK := Color("76583d")
const TOUCH_SWIPE_THRESHOLD := 30.0

signal place_requested(place_name: String)
signal close_requested

@export var preview_font: Font

var _items: Array = []
var _first_visible_index := 0
var _directory_snapshot: Dictionary = {}
var _directory_snapshot_initialized := false
var _background: TextureRect
var _header: Label
var _close_button: Button
var _row_icons: Array[TextureRect] = []
var _row_names: Array[Label] = []
var _row_states: Array[Label] = []
var _row_buttons: Array[Button] = []
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
			preview_font = font
	_build_visuals()
	resized.connect(_layout_children)
	_layout_children()


func apply_directory(data: Dictionary) -> void:
	if _directory_snapshot_initialized and data == _directory_snapshot:
		return
	_directory_snapshot = data.duplicate(true)
	_directory_snapshot_initialized = true
	_items = (data.get("items", []) as Array).duplicate(true)
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

	_header = _make_label(27, INK)
	add_child(_header)
	_close_button = _make_button("关闭地点目录")
	_close_button.accessibility_name = "关闭地点目录"
	_close_button.pressed.connect(close)
	add_child(_close_button)

	for row_index in VISIBLE_ROWS:
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		_row_icons.append(icon)

		var name_label := _make_label(23, INK)
		add_child(name_label)
		_row_names.append(name_label)
		var state_label := _make_label(19, MUTED_INK)
		add_child(state_label)
		_row_states.append(state_label)

		var button := _make_button("打开地点资料")
		button.pressed.connect(_on_row_pressed.bind(row_index))
		button.gui_input.connect(_on_row_gui_input)
		add_child(button)
		_row_buttons.append(button)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if preview_font != null:
		label.add_theme_font_override("font", preview_font)
	return label


func _make_button(tooltip: String) -> Button:
	return UI_KIT.invisible_flat_button(tooltip)


func _layout_children() -> void:
	if not is_instance_valid(_background):
		return
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_scaled_rect(_header, HEADER_RECT)
	_set_scaled_rect(_close_button, CLOSE_RECT)
	for row_index in VISIBLE_ROWS:
		_set_scaled_rect(_row_icons[row_index], ICON_RECTS[row_index])
		_set_scaled_rect(_row_names[row_index], NAME_RECTS[row_index])
		_set_scaled_rect(_row_states[row_index], STATE_RECTS[row_index])
		_set_scaled_rect(_row_buttons[row_index], ROW_RECTS[row_index])


func _set_scaled_rect(control: Control, source_rect: Rect2) -> void:
	var scale_value := Vector2(size.x / SOURCE_SIZE.x, size.y / SOURCE_SIZE.y)
	control.position = (source_rect.position * scale_value).round()
	control.size = (source_rect.size * scale_value).round()


func _render() -> void:
	if not is_instance_valid(_header):
		return
	var last_visible := mini(_first_visible_index + VISIBLE_ROWS, _items.size())
	_header.text = (
		"地点 %d–%d / %d" % [_first_visible_index + 1, last_visible, _items.size()]
		if not _items.is_empty()
		else "地点目录"
	)
	for row_index in VISIBLE_ROWS:
		var item_index := _first_visible_index + row_index
		var populated := item_index < _items.size()
		_row_icons[row_index].visible = populated
		_row_names[row_index].visible = populated
		_row_states[row_index].visible = populated
		_row_buttons[row_index].visible = populated
		if not populated:
			continue
		var item := _items[item_index] as Dictionary
		var place_name := String(item.get("placeName", "未知地点"))
		var place_type := String(item.get("placeType", "地点"))
		var resident_count := int(item.get("residentCount", 0))
		_row_icons[row_index].texture = _icon_texture_for(item, row_index)
		_row_names[row_index].text = place_name
		_row_states[row_index].text = "%d 人 · %s" % [resident_count, place_type]
		_row_buttons[row_index].tooltip_text = "打开%s资料" % place_name
		_row_buttons[row_index].set_meta("place_name", place_name)


func _icon_texture_for(item: Dictionary, fallback_index: int) -> Texture2D:
	var place_name := String(item.get("placeName", ""))
	var place_type := String(item.get("placeType", ""))
	var source_index := fallback_index
	if place_type == "住家":
		source_index = 5
	elif place_name == "诊所":
		source_index = 2
	elif place_name == "镇公所":
		source_index = 4
	elif place_type == "铺面":
		source_index = 1 if place_name.contains("咖啡") else 3
	else:
		source_index = 0
	var atlas := AtlasTexture.new()
	atlas.atlas = DRAWER_TEXTURE
	atlas.region = ICON_RECTS[source_index]
	return atlas


func _on_row_pressed(row_index: int) -> void:
	if _touch_scroll_dragged:
		return
	var item_index := _first_visible_index + row_index
	if item_index < 0 or item_index >= _items.size():
		return
	var place_name := String((_items[item_index] as Dictionary).get("placeName", ""))
	if not place_name.is_empty():
		place_requested.emit(place_name)


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
