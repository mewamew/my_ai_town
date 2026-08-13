extends RefCounted

const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")


static func is_primary_press(event: InputEvent) -> bool:
	return (
		(event is InputEventScreenTouch and event.pressed)
		or (
			not MOBILE_UI_PROFILE.is_mobile_runtime()
			and
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		)
	)


static func is_primary_release(event: InputEvent) -> bool:
	return (
		(event is InputEventScreenTouch and not event.pressed)
		or (
			not MOBILE_UI_PROFILE.is_mobile_runtime()
			and
			event is InputEventMouseButton
			and not event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		)
	)


static func position(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position
	if event is InputEventMouse:
		return (event as InputEventMouse).position
	return Vector2.INF
