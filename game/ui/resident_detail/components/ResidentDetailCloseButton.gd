extends Control
class_name ResidentDetailCloseButton


signal close_requested


const UI_KIT := preload("res://ui/common/AiTownUiKit.gd")
const ICON_SIZE := Vector2(48, 48)
const COLOR_TRANSITION_SECONDS := 0.10
const PRESS_OFFSET_PIXELS := 2

var _disabled := false
var _hovered := false
var _pressed := false
var _touch_index := -1
var _focused := false
var _reduced_motion := false
var _normal_color := Color.WHITE
var _hover_color := Color.WHITE
var _pressed_color := Color.WHITE
var _disabled_color := Color.WHITE
var _shutting_down := false
var _icon: TextureRect
var _color_tween: Tween


func _ready() -> void:
	_icon = get_node("Icon") as TextureRect
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	resized.connect(_layout_icon)
	_layout_icon()
	_apply_visual_state(false)


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	_pressed = false
	_touch_index = -1
	if is_instance_valid(_icon):
		_layout_icon()
		_apply_visual_state(false)


func configure(config: Dictionary) -> void:
	_icon = get_node("Icon") as TextureRect
	_disabled = bool(config.get("disabled", false))
	_reduced_motion = bool(
		config.get("reducedMotion", false)
	)
	_normal_color = config.get(
		"normalColor",
		Color.WHITE
	) as Color
	_hover_color = config.get(
		"hoverColor",
		_normal_color
	) as Color
	_pressed_color = config.get(
		"pressedColor",
		_hover_color
	) as Color
	_disabled_color = config.get(
		"disabledColor",
		_normal_color
	) as Color
	tooltip_text = str(
		config.get("accessibleLabel", "关闭")
	)
	accessibility_name = tooltip_text
	mouse_default_cursor_shape = (
		Control.CURSOR_ARROW
		if _disabled
		else Control.CURSOR_POINTING_HAND
	)
	_apply_disabled_state()
	_layout_icon()
	_apply_visual_state(false)


func set_disabled(value: bool) -> void:
	if _disabled == value:
		return
	_disabled = value
	_pressed = false
	_touch_index = -1
	_apply_disabled_state()
	_apply_visual_state(true)


func set_reduced_motion(value: bool) -> void:
	_reduced_motion = value
	_apply_visual_state(false)


func set_debug_interaction_state(state: String) -> void:
	_hovered = state == "hover" or state == "pressed"
	_focused = state == "focus"
	_pressed = state == "pressed"
	_layout_icon()
	_apply_visual_state(true)


func get_component_contract() -> Dictionary:
	return {
		"componentType": (
			"resident_detail_page_private_close_button"
		),
		"frameOwner": "FormalResidentDetailShell",
		"iconOwner": (
			"ResidentDetailCloseButton/Icon"
		),
		"iconAsset": (
			"res://assets/ui/resident_detail/runtime/"
			+ "close_x_icon.png"
		),
		"iconNativeSize": [262, 262],
		"iconDisplaySize": [48, 48],
		"drawsFrame": false,
		"drawsFill": false,
		"drawsUnderline": false,
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
			close_requested.emit()
		_layout_icon()
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
				close_requested.emit()
		else:
			return
		_layout_icon()
		_apply_visual_state(true)
		accept_event()
		return
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		accept_event()
		return
	if event.is_action_pressed("ui_accept"):
		_touch_index = -1
		_pressed = true
		_layout_icon()
		_apply_visual_state(true)
		accept_event()
		return
	if event.is_action_released("ui_accept") and _pressed:
		_pressed = false
		_layout_icon()
		_apply_visual_state(true)
		close_requested.emit()
		accept_event()


func _on_mouse_entered() -> void:
	_hovered = true
	_apply_visual_state(true)


func _on_mouse_exited() -> void:
	_hovered = false
	_pressed = false
	_touch_index = -1
	_layout_icon()
	_apply_visual_state(true)


func _on_focus_entered() -> void:
	_focused = true
	_apply_visual_state(true)


func _on_focus_exited() -> void:
	_focused = false
	_pressed = false
	_touch_index = -1
	_layout_icon()
	_apply_visual_state(true)


func _apply_disabled_state() -> void:
	UI_KIT.apply_disabled_state(self, _disabled)


func _layout_icon() -> void:
	if _icon == null:
		return
	var press_offset := (
		PRESS_OFFSET_PIXELS
		if _pressed
		else 0
	)
	_icon.position = (
		(size - ICON_SIZE) * 0.5
		+ Vector2(0, press_offset)
	).round()
	_icon.size = ICON_SIZE


func _apply_visual_state(animate: bool) -> void:
	if _icon == null:
		return
	var target_color := _target_color()
	if is_instance_valid(_color_tween):
		_color_tween.kill()
	if animate and not _reduced_motion and not _shutting_down:
		_color_tween = create_tween()
		_color_tween.set_trans(Tween.TRANS_QUAD)
		_color_tween.set_ease(Tween.EASE_OUT)
		_color_tween.tween_property(
			_icon,
			"modulate",
			target_color,
			COLOR_TRANSITION_SECONDS
		)
	else:
		_icon.modulate = target_color


func _target_color() -> Color:
	if _disabled:
		return _disabled_color
	if _pressed:
		return _pressed_color
	if _hovered or _focused:
		return _hover_color
	return _normal_color


func _exit_tree() -> void:
	_shutting_down = true
	if is_instance_valid(_color_tween):
		_color_tween.kill()
	_color_tween = null
