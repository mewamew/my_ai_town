class_name MobileTouchScrollRouter
extends Node


const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")
const TOUCH_DRAG_DEADZONE := 10.0


var _force_touch_runtime := false
var _pointer_index := -1
var _target_control: Control
var _source_control: Control
var _vertical_scrollbar: VScrollBar
var _horizontal_scrollbar: HScrollBar
var _start_position := Vector2.ZERO
var _last_position := Vector2.ZERO
var _drag_started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset()


func configure(force_touch_runtime := false) -> void:
	_force_touch_runtime = force_touch_runtime


func reset() -> void:
	_pointer_index = -1
	_target_control = null
	_source_control = null
	_vertical_scrollbar = null
	_horizontal_scrollbar = null
	_start_position = Vector2.ZERO
	_last_position = Vector2.ZERO
	_drag_started = false


func _input(event: InputEvent) -> void:
	if not _touch_runtime_enabled():
		return
	if consume(event):
		get_viewport().set_input_as_handled()


func consume(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return _consume_touch(event as InputEventScreenTouch)
	if event is InputEventScreenDrag:
		return _consume_drag(event as InputEventScreenDrag)
	return false


func _consume_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		if _pointer_index >= 0:
			return false
		var target := _find_scroll_target(event.position)
		if target.is_empty():
			return false
		_pointer_index = event.index
		_target_control = target.get("control") as Control
		_source_control = target.get(
			"source",
			target.get("control"),
		) as Control
		_vertical_scrollbar = target.get("vertical") as VScrollBar
		_horizontal_scrollbar = target.get("horizontal") as HScrollBar
		_start_position = event.position
		_last_position = event.position
		_drag_started = false
		# A normal tap must still reach the row, button, caret or link below.
		return false
	if event.index != _pointer_index:
		return false
	var suppress_release := _drag_started
	reset()
	if event.canceled:
		return suppress_release
	# A completed drag must not also activate the list row below the finger.
	return suppress_release


func _consume_drag(event: InputEventScreenDrag) -> bool:
	if event.index != _pointer_index or not is_instance_valid(_target_control):
		return false
	# The press can begin before a long press opens Android's native text
	# ActionMode. Recheck here so selection-handle movement is not stolen by the
	# page scroll route after the toolbar appears.
	if is_instance_valid(_source_control) and _text_selection_owns_drag(_source_control):
		reset()
		return false
	if not _target_control.is_visible_in_tree():
		reset()
		return false
	var from_last := event.position - _last_position
	if not _drag_started:
		var from_start := event.position - _start_position
		if from_start.length() < TOUCH_DRAG_DEADZONE:
			_last_position = event.position
			return false
		_drag_started = true
		from_last = from_start
	_scroll_by_finger_delta(from_last)
	_last_position = event.position
	return true


func _scroll_by_finger_delta(delta: Vector2) -> void:
	if _range_can_scroll(_vertical_scrollbar):
		_vertical_scrollbar.value = clampf(
			_vertical_scrollbar.value - delta.y,
			_vertical_scrollbar.min_value,
			maxf(
				_vertical_scrollbar.min_value,
				_vertical_scrollbar.max_value - _vertical_scrollbar.page,
			),
		)
	if _range_can_scroll(_horizontal_scrollbar):
		_horizontal_scrollbar.value = clampf(
			_horizontal_scrollbar.value - delta.x,
			_horizontal_scrollbar.min_value,
			maxf(
				_horizontal_scrollbar.min_value,
				_horizontal_scrollbar.max_value - _horizontal_scrollbar.page,
			),
		)


func _find_scroll_target(position: Vector2) -> Dictionary:
	if not is_inside_tree():
		return {}
	var fallback_target := _find_scroll_target_in_tree(position)
	# Use Godot's GUI hit result whenever available. It respects CanvasLayer,
	# z-order, clipping and overlays, while a scene-tree scan does not.
	var hovered := get_viewport().gui_get_hovered_control()
	if (
		is_instance_valid(hovered)
		and hovered.get_global_rect().has_point(position)
	):
		if _text_selection_owns_drag(hovered):
			return {}
		var current: Node = hovered
		while current != null:
			if current is Control:
				var control := current as Control
				var ranges := _scroll_ranges_for(control)
				var vertical := ranges.get("vertical") as VScrollBar
				var horizontal := ranges.get("horizontal") as HScrollBar
				if _range_can_scroll(vertical) or _range_can_scroll(horizontal):
					return {
						"control": control,
						"source": hovered,
						"vertical": vertical,
						"horizontal": horizontal,
					}
			current = current.get_parent()
		# A valid GUI hit without a scroll ancestor belongs to an overlay or
		# another non-scrollable control. Respect that hit result instead of
		# scrolling a page underneath the overlay.
		return {}
	return fallback_target


func _find_scroll_target_in_tree(position: Vector2) -> Dictionary:
	var candidates: Array[Dictionary] = []
	_collect_scroll_targets(get_tree().root, position, candidates, 0)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_depth := int(left.get("depth", 0))
		var right_depth := int(right.get("depth", 0))
		if left_depth != right_depth:
			return left_depth > right_depth
		return float(left.get("area", INF)) < float(right.get("area", INF))
	)
	return candidates[0]


func _text_selection_owns_drag(control: Control) -> bool:
	var current: Node = control
	while current != null:
		if current is LineEdit or current is TextEdit:
			return (
				(current as Control).has_focus()
				and (current as Control).has_meta("mobile_native_text_actions_visible")
			)
		current = current.get_parent()
	return false


func _collect_scroll_targets(
	node: Node,
	position: Vector2,
	candidates: Array[Dictionary],
	depth: int,
) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		var control := node as Control
		if (
			control.mouse_filter != Control.MOUSE_FILTER_IGNORE
			and control.get_global_rect().has_point(position)
			and _point_inside_control_clips(control, position)
		):
			var ranges := _scroll_ranges_for(control)
			var vertical := ranges.get("vertical") as VScrollBar
			var horizontal := ranges.get("horizontal") as HScrollBar
			if _range_can_scroll(vertical) or _range_can_scroll(horizontal):
				candidates.append({
					"control": control,
					"vertical": vertical,
					"horizontal": horizontal,
					"depth": depth,
					"area": control.size.x * control.size.y,
				})
	for child: Node in node.get_children():
		_collect_scroll_targets(child, position, candidates, depth + 1)


func _point_inside_control_clips(control: Control, position: Vector2) -> bool:
	var current: Node = control.get_parent()
	while current != null:
		if current is Control:
			var parent_control := current as Control
			if (
				parent_control.clip_contents
				and not parent_control.get_global_rect().has_point(position)
			):
				return false
		current = current.get_parent()
	return true


func _scroll_ranges_for(control: Control) -> Dictionary:
	if control is ScrollContainer:
		var scroll := control as ScrollContainer
		return {
			"vertical": (
				scroll.get_v_scroll_bar()
				if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
				else null
			),
			"horizontal": (
				scroll.get_h_scroll_bar()
				if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
				else null
			),
		}
	if control is RichTextLabel:
		var rich := control as RichTextLabel
		return {
			"vertical": rich.get_v_scroll_bar() if rich.scroll_active else null,
			"horizontal": null,
		}
	if control is TextEdit:
		var edit := control as TextEdit
		return {
			"vertical": edit.get_v_scroll_bar(),
			"horizontal": edit.get_h_scroll_bar(),
		}
	return {}


func _range_can_scroll(range: Range) -> bool:
	return (
		is_instance_valid(range)
		and range.max_value - range.page > range.min_value + 0.5
	)


func _touch_runtime_enabled() -> bool:
	return _force_touch_runtime or MOBILE_UI_PROFILE.is_mobile_runtime()
