class_name BulletinBoardHistoryRail
extends Control


signal page_requested(page_index: int)

const TRACK_COLOR := Color("6c3d20")
const THUMB_COLOR := Color("c78a4d")
const THUMB_BORDER := Color("5c351f")
const FOCUS_COLOR := Color("e5a84b")
const MINIMUM_THUMB_HEIGHT := 48.0

var _page_count := 1
var _page_index := 0
var _dragging := false
var _touch_index := -1


func _ready() -> void:
	custom_minimum_size = Vector2(48, 160)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("bulletin_board_touch_target")
	set_meta("gate_touch_id", "history_scroll")
	queue_redraw()


func set_page_state(page_index: int, page_count: int) -> void:
	_page_count = maxi(1, page_count)
	_page_index = clampi(page_index, 0, _page_count - 1)
	tooltip_text = "历史公告第 %d 页，共 %d 页" % [
		_page_index + 1,
		_page_count,
	]
	queue_redraw()


func page_index() -> int:
	return _page_index


func page_count() -> int:
	return _page_count


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if (
			mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP
			and mouse_event.pressed
		):
			_request_page(_page_index - 1)
			accept_event()
		elif (
			mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN
			and mouse_event.pressed
		):
			_request_page(_page_index + 1)
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse_event.pressed
			_touch_index = -1
			if _dragging:
				grab_focus()
				_request_page(_page_for_y(mouse_event.position.y))
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_request_page(_page_for_y((event as InputEventMouseMotion).position.y))
		accept_event()
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			if _touch_index >= 0:
				return
			_dragging = true
			_touch_index = touch_event.index
			grab_focus()
			_request_page(_page_for_y(touch_event.position.y))
		elif touch_event.index == _touch_index:
			_dragging = false
			_touch_index = -1
		else:
			return
		accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _dragging or drag.index != _touch_index:
			return
		_request_page(_page_for_y(drag.position.y))
		accept_event()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.is_action("ui_up") or key_event.is_action("ui_page_up"):
			_request_page(_page_index - 1)
			accept_event()
		elif (
			key_event.is_action("ui_down")
			or key_event.is_action("ui_page_down")
		):
			_request_page(_page_index + 1)
			accept_event()
		elif key_event.is_action("ui_home"):
			_request_page(0)
			accept_event()
		elif key_event.is_action("ui_end"):
			_request_page(_page_count - 1)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dragging = false
		_touch_index = -1
		return
	if what in [NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT]:
		queue_redraw()


func _draw() -> void:
	var track_height := maxf(1.0, floorf(size.y))
	var track_rect := Rect2(
		floorf((size.x - 8.0) * 0.5),
		0,
		8,
		track_height
	)
	draw_rect(track_rect, TRACK_COLOR)
	var thumb_height := maxf(
		MINIMUM_THUMB_HEIGHT,
		floorf(track_height / float(_page_count))
	)
	thumb_height = minf(track_height, thumb_height)
	var travel := maxf(0.0, track_height - thumb_height)
	var ratio := (
		0.0
		if _page_count <= 1
		else float(_page_index) / float(_page_count - 1)
	)
	var thumb_rect := Rect2(
		floorf((size.x - 16.0) * 0.5),
		floorf(travel * ratio),
		16,
		thumb_height
	)
	draw_rect(thumb_rect, THUMB_BORDER)
	draw_rect(thumb_rect.grow(-3.0), THUMB_COLOR)
	if has_focus():
		draw_rect(
			Rect2(Vector2.ZERO, size).grow(-2.0),
			FOCUS_COLOR,
			false,
			3.0
		)


func _page_for_y(local_y: float) -> int:
	if _page_count <= 1:
		return 0
	var ratio := clampf(local_y / maxf(1.0, size.y), 0.0, 0.9999)
	return mini(_page_count - 1, int(floor(ratio * _page_count)))


func _request_page(page_index: int) -> void:
	var clamped := clampi(page_index, 0, _page_count - 1)
	if clamped == _page_index:
		return
	_page_index = clamped
	queue_redraw()
	page_requested.emit(_page_index)
