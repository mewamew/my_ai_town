extends Control
class_name ResidentDetailTabButton


signal activated(tab_id: String)


const UI_KIT := preload("res://ui/common/AiTownUiKit.gd")
const COLOR_TRANSITION_SECONDS := 0.10
const PRESS_OFFSET_PIXELS := 2

var _tab_id := ""
var _selected := false
var _disabled := false
var _hovered := false
var _pressed := false
var _touch_index := -1
var _focused := false
var _reduced_motion := false
var _normal_color := Color.WHITE
var _selected_color := Color.WHITE
var _hover_color := Color.WHITE
var _pressed_color := Color.WHITE
var _disabled_color := Color.WHITE
var _content_rect := Rect2()
var _shutting_down := false
var _label: Label
var _color_tween: Tween


func _ready() -> void:
	_label = get_node("Label") as Label
	_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	_apply_visual_state(false)


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	_pressed = false
	_touch_index = -1
	if is_instance_valid(_label):
		_apply_visual_state(false)


func configure(config: Dictionary) -> void:
	_label = get_node("Label") as Label
	_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tab_id = str(config.get("tabId", ""))
	_selected = bool(config.get("selected", false))
	_disabled = bool(config.get("disabled", false))
	_reduced_motion = bool(
		config.get("reducedMotion", false)
	)
	_normal_color = config.get(
		"normalColor",
		Color.WHITE
	) as Color
	_selected_color = config.get(
		"selectedColor",
		_normal_color
	) as Color
	_hover_color = config.get(
		"hoverColor",
		_selected_color
	) as Color
	_pressed_color = config.get(
		"pressedColor",
		_hover_color
	) as Color
	_disabled_color = config.get(
		"disabledColor",
		_normal_color
	) as Color
	_content_rect = config.get(
		"contentRect",
		Rect2(Vector2.ZERO, size)
	) as Rect2
	_label.anchor_left = 0.0
	_label.anchor_top = 0.0
	_label.anchor_right = 0.0
	_label.anchor_bottom = 0.0
	_label.text = str(config.get("label", ""))
	_label.add_theme_font_size_override(
		"font_size",
		int(config.get("fontSize", 32))
	)
	_label.add_theme_color_override(
		"font_color",
		Color.WHITE
	)
	tooltip_text = str(config.get("accessibleLabel", _label.text))
	accessibility_name = tooltip_text
	mouse_default_cursor_shape = (
		Control.CURSOR_ARROW
		if _disabled
		else Control.CURSOR_POINTING_HAND
	)
	_apply_disabled_state()
	_apply_visual_state(false)


func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	_apply_visual_state(true)


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
	_apply_visual_state(true)


func get_animation_contract() -> Dictionary:
	return {
		"componentType": "resident_detail_page_private_tab",
		"frameOwner": "FormalResidentDetailShell",
		"contentSlotOwner": (
			"ResidentDetailTabButton/Label"
		),
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
		"debugStateDriverAvailable": true,
		"states": [
			"normal",
			"hover",
			"focus",
			"pressed",
			"selected",
			"disabled",
		],
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
			activated.emit(_tab_id)
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
				activated.emit(_tab_id)
		else:
			return
		_apply_visual_state(true)
		accept_event()
		return
	if event.is_action_pressed("ui_accept"):
		_touch_index = -1
		_pressed = true
		_apply_visual_state(true)
		accept_event()
		return
	if event.is_action_released("ui_accept") and _pressed:
		_pressed = false
		_apply_visual_state(true)
		activated.emit(_tab_id)
		accept_event()


func _on_mouse_entered() -> void:
	_hovered = true
	_apply_visual_state(true)


func _on_mouse_exited() -> void:
	_hovered = false
	_pressed = false
	_touch_index = -1
	_apply_visual_state(true)


func _on_focus_entered() -> void:
	_focused = true
	_apply_visual_state(true)


func _on_focus_exited() -> void:
	_focused = false
	_pressed = false
	_touch_index = -1
	_apply_visual_state(true)


func _apply_disabled_state() -> void:
	UI_KIT.apply_disabled_state(self, _disabled)


func _apply_visual_state(animate: bool) -> void:
	if _label == null:
		return
	var target_color := _target_color()
	if is_instance_valid(_color_tween):
		_color_tween.kill()
	if animate and not _reduced_motion and not _shutting_down:
		_color_tween = create_tween()
		_color_tween.set_trans(Tween.TRANS_QUAD)
		_color_tween.set_ease(Tween.EASE_OUT)
		_color_tween.tween_property(
			_label,
			"modulate",
			target_color,
			COLOR_TRANSITION_SECONDS
		)
	else:
		_label.modulate = target_color
	var press_offset := (
		PRESS_OFFSET_PIXELS
		if _pressed
		else 0
	)
	_label.position = (
		_content_rect.position
		+ Vector2(0, press_offset)
	)
	_label.size = _content_rect.size


func _target_color() -> Color:
	if _disabled:
		return _disabled_color
	if _pressed:
		return _pressed_color
	if _selected:
		return _selected_color
	if _hovered or _focused:
		return _hover_color
	return _normal_color


func _exit_tree() -> void:
	_shutting_down = true
	if is_instance_valid(_color_tween):
		_color_tween.kill()
	_color_tween = null
