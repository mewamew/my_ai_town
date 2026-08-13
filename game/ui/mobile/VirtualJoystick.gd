class_name AiTownVirtualJoystick
extends Control


signal movement_changed(value: Vector2)

const DEAD_ZONE := 0.12

var _pointer_id := -1
var _movement := Vector2.ZERO
var _knob: Control


func configure(knob: Control) -> void:
	_knob = knob
	_reset_knob()


func movement() -> Vector2:
	return _movement


func is_pointer_active() -> bool:
	return _pointer_id >= 0


func cancel() -> void:
	_pointer_id = -1
	_set_movement(Vector2.ZERO)
	_reset_knob()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _pointer_id < 0:
			_pointer_id = touch.index
			_update_pointer(touch.position)
			accept_event()
		elif not touch.pressed and touch.index == _pointer_id:
			cancel()
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _pointer_id:
			_update_pointer(drag.position)
			accept_event()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed and _pointer_id < 0:
			_pointer_id = 0
			_update_pointer(button.position)
			accept_event()
		elif not button.pressed and _pointer_id == 0:
			cancel()
			accept_event()
	elif event is InputEventMouseMotion and _pointer_id == 0:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_update_pointer(motion.position)
			accept_event()


func _update_pointer(local_position: Vector2) -> void:
	var center := size * 0.5
	var radius := maxf(1.0, minf(size.x, size.y) * 0.5)
	var offset := local_position - center
	var normalized := offset.limit_length(radius) / radius
	if normalized.length() < DEAD_ZONE:
		normalized = Vector2.ZERO
	_set_movement(normalized)
	if is_instance_valid(_knob):
		_knob.position = center + normalized * radius * 0.58 - _knob.size * 0.5


func _set_movement(next: Vector2) -> void:
	if _movement.is_equal_approx(next):
		return
	_movement = next
	movement_changed.emit(_movement)


func _reset_knob() -> void:
	if not is_instance_valid(_knob):
		return
	_knob.position = (size - _knob.size) * 0.5
