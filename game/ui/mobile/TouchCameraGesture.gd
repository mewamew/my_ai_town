class_name TouchCameraGesture
extends RefCounted


var _positions: Dictionary = {}
var _pinch_distance := 0.0


func reset() -> void:
	_positions.clear()
	_pinch_distance = 0.0


func active_touch_count() -> int:
	return _positions.size()


func consume(event: InputEvent) -> Dictionary:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_positions[touch.index] = touch.position
		else:
			_positions.erase(touch.index)
		_sync_pinch_baseline()
		# Keep the initial press available to Area2D/Control hit testing. Consuming
		# it here made residents, animals and building entrances almost impossible
		# to tap because the camera recognizer won before physics picking ran.
		return {
			"handled": not touch.pressed,
			"pan": Vector2.ZERO,
			"pinchLog": 0.0,
		}
	if not event is InputEventScreenDrag:
		return {"handled": false, "pan": Vector2.ZERO, "pinchLog": 0.0}
	var drag := event as InputEventScreenDrag
	if not _positions.has(drag.index):
		_positions[drag.index] = drag.position - drag.relative
	_positions[drag.index] = drag.position
	if _positions.size() < 2:
		_pinch_distance = 0.0
		return {"handled": true, "pan": drag.relative, "pinchLog": 0.0}
	var distance := _current_pinch_distance()
	var pinch_log := 0.0
	if _pinch_distance > 0.0 and distance > 0.0:
		pinch_log = log(distance / _pinch_distance)
	_pinch_distance = distance
	return {"handled": true, "pan": Vector2.ZERO, "pinchLog": pinch_log}


func _sync_pinch_baseline() -> void:
	_pinch_distance = _current_pinch_distance() if _positions.size() >= 2 else 0.0


func _current_pinch_distance() -> float:
	var keys := _positions.keys()
	if keys.size() < 2:
		return 0.0
	return (_positions[keys[0]] as Vector2).distance_to(
		_positions[keys[1]] as Vector2
	)
