class_name MobileOrientationGate
extends CanvasLayer


const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")

var _shield: Control
var _message: Label
var _is_blocking := false


func _ready() -> void:
	layer = 10_000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	_update_overlay()


func _process(_delta: float) -> void:
	_update_overlay()


func _build_overlay() -> void:
	_shield = Control.new()
	_shield.name = "LandscapeOnlyShield"
	_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_shield.focus_mode = Control.FOCUS_ALL
	_shield.visible = false
	add_child(_shield)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.035, 0.047, 0.067, 0.97)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield.add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "MessageCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "MessagePanel"
	panel.custom_minimum_size = Vector2(460.0, 220.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)

	_message = Label.new()
	_message.name = "Message"
	_message.text = "请将设备横向使用\n旋转后即可继续游戏"
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 32)
	_message.add_theme_color_override("font_color", Color(0.96, 0.91, 0.78))
	_message.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04))
	_message.add_theme_constant_override("outline_size", 6)
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_message)


func _update_overlay() -> void:
	if not is_instance_valid(_shield):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var should_block := MOBILE_UI_PROFILE.is_portrait_runtime(viewport_size)
	var panel := _message.get_parent() as Control
	if panel != null:
		panel.custom_minimum_size = Vector2(
			clampf(viewport_size.x * 0.86, 280.0, 460.0),
			clampf(viewport_size.y * 0.28, 160.0, 220.0),
		)
	_message.add_theme_font_size_override(
		"font_size",
		clampi(int(viewport_size.x / 12.0), 22, 32),
	)
	if should_block == _is_blocking:
		return
	_is_blocking = should_block
	_shield.visible = should_block
	if should_block:
		_shield.grab_focus()
	else:
		get_viewport().gui_release_focus()
