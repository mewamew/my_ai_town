extends Control
class_name ResidentDetailRefreshButton


signal refresh_requested


const UI_KIT := preload("res://ui/common/AiTownUiKit.gd")
const SURFACE_RECT := Rect2(1, 6, 148, 63)
const COLOR_TRANSITION_SECONDS := 0.10
const PRESS_OFFSET_PIXELS := 2

var _disabled := false
var _hovered := false
var _pressed := false
var _touch_index := -1
var _focused := false
var _reduced_motion := false
var _surface_visible := true
var _shutting_down := false
var _surface: TextureRect
var _label: Label
var _surface_tween: Tween
var _label_tween: Tween


func _ready() -> void:
	_surface = get_node("Surface") as TextureRect
	_label = get_node("Label") as Label
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	resized.connect(_layout_content)
	_layout_content()
	_apply_visual_state(false)


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	_pressed = false
	_touch_index = -1
	if is_instance_valid(_surface) and is_instance_valid(_label):
		_layout_content()
		_apply_visual_state(false)


func configure(config: Dictionary) -> void:
	_surface = get_node("Surface") as TextureRect
	_label = get_node("Label") as Label
	_disabled = bool(config.get("disabled", false))
	_reduced_motion = bool(
		config.get("reducedMotion", false)
	)
	_surface_visible = bool(config.get("surfaceVisible", true))
	_surface.visible = _surface_visible
	_label.text = str(config.get("label", "刷新"))
	_label.add_theme_font_size_override(
		"font_size",
		int(config.get("fontSize", 32))
	)
	tooltip_text = str(
		config.get("accessibleLabel", "刷新公开摘要")
	)
	accessibility_name = tooltip_text
	mouse_default_cursor_shape = (
		Control.CURSOR_ARROW
		if _disabled
		else Control.CURSOR_POINTING_HAND
	)
	_apply_disabled_state()
	_layout_content()
	_apply_visual_state(false)


func set_disabled(value: bool) -> void:
	if _disabled == value:
		return
	_disabled = value
	_pressed = false
	_touch_index = -1
	_apply_disabled_state()
	_layout_content()
	_apply_visual_state(true)


func set_reduced_motion(value: bool) -> void:
	_reduced_motion = value
	_apply_visual_state(false)


func set_surface_visible(value: bool) -> void:
	_surface_visible = value
	if is_instance_valid(_surface):
		_surface.visible = value


func set_label_font_size(value: int) -> void:
	if is_instance_valid(_label):
		_label.add_theme_font_size_override("font_size", value)


func set_debug_interaction_state(state: String) -> void:
	_hovered = state == "hover" or state == "pressed"
	_focused = state == "focus"
	_pressed = state == "pressed"
	_layout_content()
	_apply_visual_state(true)


func get_component_contract() -> Dictionary:
	return {
		"componentType": (
			"resident_detail_page_private_refresh_button"
		),
		"frameOwner": (
			"ResidentDetailRefreshButton/Surface"
		),
		"footerFrameOwner": "FormalResidentDetailShell",
		"surfaceAsset": (
			"res://assets/ui/resident_detail/runtime/"
			+ "refresh_button_surface.png"
		),
		"surfaceNativeSize": [787, 333],
		"surfaceRect": [1, 6, 148, 63],
		"surfaceFillsAvailableRect": true,
		"surfaceInsets": [1, 6, 1, 7],
		"labelRect": [0, 0, 150, 76],
		"textOwner": (
			"ResidentDetailRefreshButton/Label"
		),
		"drawsFooterFrame": false,
		"geometryTween": false,
		"colorTransitionMilliseconds": int(
			COLOR_TRANSITION_SECONDS * 1000.0
		),
		"pressOffsetPixels": PRESS_OFFSET_PIXELS,
		"pressOffsetUsesIntegerPixels": true,
		"reducedMotionSupported": true,
		"inputModes": [
			"mouse",
			"keyboard",
			"gamepad",
			"touch",
		],
	}


func _gui_input(event: InputEvent) -> void:
	if _disabled:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		_touch_index = -1
		_pressed = mouse_event.pressed
		if _pressed:
			grab_focus()
		elif _hovered:
			refresh_requested.emit()
		_layout_content()
		_apply_visual_state(true)
		accept_event()
		return
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			if _touch_index >= 0:
				return
			_touch_index = touch_event.index
			_pressed = true
			grab_focus()
		elif touch_event.index == _touch_index:
			_touch_index = -1
			_pressed = false
			if (
				not touch_event.canceled
				and Rect2(Vector2.ZERO, size).has_point(touch_event.position)
			):
				refresh_requested.emit()
		else:
			return
		_layout_content()
		_apply_visual_state(true)
		accept_event()
		return
	if event.is_action_pressed("ui_accept"):
		_touch_index = -1
		_pressed = true
		_layout_content()
		_apply_visual_state(true)
		accept_event()
		return
	if event.is_action_released("ui_accept") and _pressed:
		_pressed = false
		_layout_content()
		_apply_visual_state(true)
		refresh_requested.emit()
		accept_event()


func _on_mouse_entered() -> void:
	_hovered = true
	_apply_visual_state(true)


func _on_mouse_exited() -> void:
	_hovered = false
	_pressed = false
	_touch_index = -1
	_layout_content()
	_apply_visual_state(true)


func _on_focus_entered() -> void:
	_focused = true
	_apply_visual_state(true)


func _on_focus_exited() -> void:
	_focused = false
	_pressed = false
	_touch_index = -1
	_layout_content()
	_apply_visual_state(true)


func _apply_disabled_state() -> void:
	UI_KIT.apply_disabled_state(self, _disabled)


func _layout_content() -> void:
	if _surface == null or _label == null:
		return
	var press_offset := (
		PRESS_OFFSET_PIXELS
		if _pressed
		else 0
	)
	var offset := Vector2(0, press_offset)
	_surface.position = SURFACE_RECT.position + offset
	_surface.size = Vector2(
		maxf(1.0, size.x - 2.0),
		maxf(1.0, size.y - 13.0),
	)
	_label.position = offset
	_label.size = size


func _apply_visual_state(animate: bool) -> void:
	if _surface == null or _label == null:
		return
	var surface_color := Color.WHITE
	var label_color := Color("3f2818")
	if _disabled:
		surface_color = Color(0.72, 0.72, 0.72, 0.58)
		label_color = Color("806a5b")
	elif _pressed:
		surface_color = Color("d6aa70")
		label_color = Color("6c3d20")
	elif _hovered or _focused:
		surface_color = Color("fff0c2")
		label_color = Color("b94d2d")
	if is_instance_valid(_surface_tween):
		_surface_tween.kill()
	if is_instance_valid(_label_tween):
		_label_tween.kill()
	if animate and not _reduced_motion and not _shutting_down:
		_surface_tween = create_tween()
		_surface_tween.tween_property(
			_surface,
			"modulate",
			surface_color,
			COLOR_TRANSITION_SECONDS
		)
		_label_tween = create_tween()
		_label_tween.tween_property(
			_label,
			"modulate",
			label_color,
			COLOR_TRANSITION_SECONDS
		)
	else:
		_surface.modulate = surface_color
		_label.modulate = label_color


func _exit_tree() -> void:
	_shutting_down = true
	if is_instance_valid(_surface_tween):
		_surface_tween.kill()
	if is_instance_valid(_label_tween):
		_label_tween.kill()
	_surface_tween = null
	_label_tween = null
