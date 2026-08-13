class_name BuildingEntryConfirm
extends Node2D


signal enter_requested(place_name: String)


const ENTRY_STRIP_TEXTURE := preload(
	"res://assets/ui/building_entry_confirm/final/building_entry_strip_v4.svg"
)
const DOOR_ICON_TEXTURE := preload(
	"res://assets/ui/building_entry_confirm/final/building_entry_door_icon_v2.png"
)
const FONT_PATH := (
	"res://assets/fonts/zheng_ge_dian_hei_16/"
	+ "ZhengGeDianHei-16.ttf"
)
const DISPLAY_SIZE := Vector2(214.0, 44.0)
const ENTRY_FONT_SIZE := 14
const ENTRY_FONT_EMBOLDEN := 0.18
const INK := Color("3f2818")
const PAPER_LIGHT := Color("fff8e6")

var _place_name := ""
var _enter_button: Button
var _door_icon: TextureRect
var _camera_zoom := Vector2.ONE
var _touch_scale_multiplier := 1.0


func configure(
	place_name: String,
	_resident_entries: Array,
	local_anchor: Vector2,
) -> bool:
	var normalized := place_name.strip_edges()
	if normalized.is_empty() or local_anchor != local_anchor:
		return false
	_place_name = normalized
	position = local_anchor
	name = "EnterConfirm_%s" % normalized
	return true


func _ready() -> void:
	z_index = 180
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_interface()
	set_camera_zoom(_camera_zoom)


func set_camera_zoom(camera_zoom: Vector2) -> void:
	var normalized_zoom := Vector2(
		maxf(absf(camera_zoom.x), 0.001),
		maxf(absf(camera_zoom.y), 0.001),
	)
	if camera_zoom.x != camera_zoom.x or camera_zoom.y != camera_zoom.y:
		normalized_zoom = Vector2.ONE
	_camera_zoom = normalized_zoom
	var minimum_zoom := minf(normalized_zoom.x, normalized_zoom.y)
	scale = Vector2.ONE * maxf(1.0, 1.0 / minimum_zoom) * _touch_scale_multiplier


func set_touch_scale_multiplier(multiplier: float) -> void:
	_touch_scale_multiplier = maxf(multiplier, 1.0)
	set_camera_zoom(_camera_zoom)


func display_size() -> Vector2:
	return DISPLAY_SIZE * scale


func debug_asset_snapshot() -> Dictionary:
	return {
		"placeName": _place_name,
		"worldAnchored": true,
		"screenProjectionTracking": false,
		"frameTexturePath": ENTRY_STRIP_TEXTURE.resource_path,
		"nativeFrameSize": ENTRY_STRIP_TEXTURE.get_size(),
		"runtimeFrameScaled": false,
		"minimumScreenSizeLocked": true,
		"cameraZoom": _camera_zoom,
		"screenScale": scale,
		"displaySize": display_size(),
		"fullStripClickable": (
			_enter_button != null
			and _enter_button.position == -DISPLAY_SIZE * 0.5
			and _enter_button.size == DISPLAY_SIZE
		),
		"doorIconTexturePath": DOOR_ICON_TEXTURE.resource_path,
		"visibleSurfaceKind": "image_asset",
		"programmaticFrameCount": 0,
		"enterButtonImageBacked": (
			_enter_button != null
			and _door_icon != null
			and _door_icon.texture != null
		),
		"residentPortraitCount": 0,
	}


func _build_interface() -> void:
	var origin := -DISPLAY_SIZE * 0.5
	var frame := Sprite2D.new()
	frame.name = "ImageAssetFrame"
	frame.position = Vector2.ZERO
	frame.texture = ENTRY_STRIP_TEXTURE
	frame.centered = true
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(frame)

	var title := _label(
		"PlaceName",
		_place_name,
		origin + Vector2(12.0, 7.0),
		Vector2(103.0, 30.0),
		14,
	)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(title)

	_door_icon = TextureRect.new()
	_door_icon.name = "EnterDoorImageAsset"
	_door_icon.position = origin + Vector2(123.0, 9.0)
	_door_icon.size = Vector2(26.0, 26.0)
	_door_icon.texture = DOOR_ICON_TEXTURE
	_door_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_door_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_door_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_door_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_door_icon)

	_enter_button = Button.new()
	_enter_button.name = "EnterInteriorButton"
	_enter_button.position = origin
	_enter_button.size = DISPLAY_SIZE
	_enter_button.flat = true
	_enter_button.text = ""
	_enter_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_enter_button.focus_mode = Control.FOCUS_NONE
	_enter_button.pressed.connect(_on_enter_pressed)
	_enter_button.mouse_entered.connect(_on_enter_hovered.bind(true))
	_enter_button.mouse_exited.connect(_on_enter_hovered.bind(false))
	add_child(_enter_button)

	var button_label := _label(
		"EnterLabel",
		"进入室内",
		origin + Vector2(149.0, 8.0),
		Vector2(61.0, 28.0),
		ENTRY_FONT_SIZE,
	)
	button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(button_label)


func _label(
	label_name: String,
	text_value: String,
	label_position: Vector2,
	label_size: Vector2,
	font_size: int,
) -> Label:
	var label := Label.new()
	label.name = label_name
	label.position = label_position
	label.size = label_size
	label.text = text_value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(FONT_PATH):
		var font_file := load(FONT_PATH) as FontFile
		if font_file != null:
			var font := FontVariation.new()
			font.base_font = font_file
			font.variation_embolden = ENTRY_FONT_EMBOLDEN
			font.spacing_glyph = 1
			label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_outline_color", PAPER_LIGHT)
	label.add_theme_constant_override("outline_size", 1)
	return label


func _on_enter_pressed() -> void:
	enter_requested.emit(_place_name)


func _on_enter_hovered(hovered: bool) -> void:
	if _enter_button == null:
		return
	_door_icon.self_modulate = (
		Color(1.08, 1.06, 0.96, 1.0)
		if hovered
		else Color.WHITE
	)
