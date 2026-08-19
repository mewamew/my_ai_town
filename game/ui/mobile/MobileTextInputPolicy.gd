class_name MobileTextInputPolicy
extends Node


const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")
const LONG_PRESS_DURATION_MSEC := 520
const TAP_MAX_TRAVEL := 18.0
const KEYBOARD_RETRY_COUNT := 3
const KEYBOARD_RETRY_INTERVAL_MSEC := 180
const ANDROID_ACTION_CUT := 1
const ANDROID_ACTION_COPY := 2
const ANDROID_ACTION_PASTE := 3
const ANDROID_ACTION_SELECT_ALL := 4


var _force_touch_runtime := false
var _force_android_text_actions := false
var _touch_candidates: Dictionary = {}
var _keyboard_control: Control
var _keyboard_visible := false
var _keyboard_retry_remaining := 0
var _keyboard_retry_at_msec := 0
var _native_action_control: Control
var _native_action_callback: RefCounted
var _native_action_proxy: Variant


class AndroidTextActionCallback:
	extends RefCounted

	var policy: Node

	func _init(owner: Node) -> void:
		policy = owner

	func onCreateActionMode(_mode: Variant, menu: Variant) -> bool:
		# This is Android's own floating ActionMode.  Godot's EditText bridge
		# does not receive the finger coordinates of a LineEdit drawn in the
		# canvas, so the bridge cannot open its native toolbar on its own.
		menu.add(0, ANDROID_ACTION_CUT, 0, "剪切")
		menu.add(0, ANDROID_ACTION_COPY, 1, "复制")
		menu.add(0, ANDROID_ACTION_PASTE, 2, "粘贴")
		menu.add(0, ANDROID_ACTION_SELECT_ALL, 3, "全选")
		return true

	func onPrepareActionMode(_mode: Variant, _menu: Variant) -> bool:
		return false

	func onActionItemClicked(mode: Variant, item: Variant) -> bool:
		policy.call_deferred("_apply_android_text_action", int(item.getItemId()))
		mode.finish()
		return true

	func onDestroyActionMode(_mode: Variant) -> void:
		policy.call_deferred("_clear_android_text_action")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	get_tree().node_added.connect(_on_node_added)
	_configure_subtree(get_tree().root)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	_touch_candidates.clear()
	_clear_android_text_action()
	_hide_virtual_keyboard()


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	_touch_candidates.clear()
	_clear_android_text_action()
	_hide_virtual_keyboard()


func configure(
	force_touch_runtime := false,
	force_android_text_actions := false,
) -> void:
	_force_touch_runtime = force_touch_runtime
	_force_android_text_actions = force_android_text_actions
	_configure_subtree(get_tree().root if is_inside_tree() else null)


func _input(event: InputEvent) -> void:
	if not _touch_runtime_enabled():
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func _process(_delta: float) -> void:
	if not _touch_runtime_enabled():
		return
	if (
		_keyboard_visible
		and (
			not is_instance_valid(_keyboard_control)
			or not _keyboard_control.has_focus()
		)
	):
		_hide_virtual_keyboard()
	var now := Time.get_ticks_msec()
	if (
		_keyboard_visible
		and _keyboard_retry_remaining > 0
		and not is_instance_valid(_native_action_control)
		and now >= _keyboard_retry_at_msec
		and is_instance_valid(_keyboard_control)
		and _keyboard_control.has_focus()
	):
		if OS.get_name() == "Android" and DisplayServer.virtual_keyboard_get_height() <= 0:
			_request_system_keyboard(_keyboard_control)
			_keyboard_retry_remaining -= 1
			_keyboard_retry_at_msec = now + KEYBOARD_RETRY_INTERVAL_MSEC
		else:
			_keyboard_retry_remaining = 0
	for touch_index: Variant in _touch_candidates.keys():
		var candidate: Dictionary = _touch_candidates.get(touch_index, {})
		if (
			candidate.is_empty()
			or bool(candidate.get("moved", false))
			or bool(candidate.get("long_press_handled", false))
		):
			continue
		if now - int(candidate.get("pressed_at", now)) < LONG_PRESS_DURATION_MSEC:
			continue
		candidate["long_press_handled"] = true
		_touch_candidates[touch_index] = candidate
		_begin_long_press(candidate.get("control") as Control)


func _handle_screen_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		var control := _text_input_at(touch.position)
		if control == null:
			_touch_candidates.erase(touch.index)
			return
		_touch_candidates[touch.index] = {
			"control": control,
			"origin": touch.position,
			"pressed_at": Time.get_ticks_msec(),
			"moved": false,
			"long_press_handled": false,
		}
		return
	var candidate: Dictionary = _touch_candidates.get(touch.index, {})
	_touch_candidates.erase(touch.index)
	if touch.canceled:
		return
	if (
		candidate.is_empty()
		or bool(candidate.get("moved", false))
		or bool(candidate.get("long_press_handled", false))
	):
		return
	var elapsed := Time.get_ticks_msec() - int(candidate.get("pressed_at", 0))
	if elapsed >= LONG_PRESS_DURATION_MSEC:
		return
	var control := candidate.get("control") as Control
	if (
		not _is_editable_text_input(control)
		or _text_input_at(touch.position) != control
	):
		return
	# The IME opens only after a complete short tap. Holding or dragging never
	# collapses into the same action as tapping.
	control.call_deferred("grab_focus")
	_show_system_keyboard.call_deferred(control)


func _handle_screen_drag(drag: InputEventScreenDrag) -> void:
	var candidate: Dictionary = _touch_candidates.get(drag.index, {})
	if candidate.is_empty():
		return
	var origin := candidate.get("origin", drag.position) as Vector2
	if origin.distance_to(drag.position) > TAP_MAX_TRAVEL:
		candidate["moved"] = true
		_touch_candidates[drag.index] = candidate


func _begin_long_press(control: Control) -> void:
	if not _is_editable_text_input(control):
		return
	control.grab_focus()
	_show_system_keyboard(control)
	# Let the Android editor bridge establish its window token before requesting
	# the floating ActionMode. Some OEM input methods drop a toolbar requested in
	# the same call stack as the first showSoftInput request.
	_show_android_text_actions.call_deferred(control)


func _show_android_text_actions(control: Control) -> void:
	if not _is_editable_text_input(control) or not control.has_focus():
		return
	if not _native_text_actions_enabled():
		return
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return
	var android_runtime: Variant = Engine.get_singleton("AndroidRuntime")
	var activity: Variant = android_runtime.getActivity()
	if activity == null:
		return
	if is_instance_valid(_native_action_control):
		if _native_action_control == control:
			return
		_clear_android_text_action()
	_native_action_control = control
	control.set_meta("mobile_native_text_actions_visible", true)
	_native_action_callback = AndroidTextActionCallback.new(self)
	_native_action_proxy = JavaClassWrapper.create_proxy(
		_native_action_callback,
		["android.view.ActionMode$Callback"],
	)
	if _native_action_proxy == null:
		_clear_android_text_action()
		return
	var show_action_mode := func() -> void:
		# TYPE_FLOATING is the same system toolbar used by native Android text
		# fields.  The app supplies no custom panel or replacement menu.
		activity.startActionMode(_native_action_proxy, 1)
	activity.runOnUiThread(
		android_runtime.createRunnableFromGodotCallable(show_action_mode)
	)


func _apply_android_text_action(action_id: int) -> void:
	if not is_instance_valid(_native_action_control):
		_clear_android_text_action()
		return
	match action_id:
		ANDROID_ACTION_CUT:
			if _native_action_control is LineEdit:
				(_native_action_control as LineEdit).menu_option(0)
			elif _native_action_control is TextEdit:
				(_native_action_control as TextEdit).menu_option(0)
		ANDROID_ACTION_COPY:
			if _native_action_control is LineEdit:
				(_native_action_control as LineEdit).menu_option(1)
			elif _native_action_control is TextEdit:
				(_native_action_control as TextEdit).menu_option(1)
		ANDROID_ACTION_PASTE:
			if _native_action_control is LineEdit:
				(_native_action_control as LineEdit).menu_option(2)
			elif _native_action_control is TextEdit:
				(_native_action_control as TextEdit).menu_option(2)
		ANDROID_ACTION_SELECT_ALL:
			if _native_action_control is LineEdit:
				(_native_action_control as LineEdit).select_all()
			elif _native_action_control is TextEdit:
				(_native_action_control as TextEdit).select_all()
	_clear_android_text_action()


func _clear_android_text_action() -> void:
	if is_instance_valid(_native_action_control):
		_native_action_control.remove_meta("mobile_native_text_actions_visible")
	_native_action_control = null
	_native_action_proxy = null
	_native_action_callback = null


func _on_node_added(node: Node) -> void:
	_configure_text_input(node)


func _configure_subtree(node: Node) -> void:
	if node == null:
		return
	_configure_text_input(node)
	for child: Node in node.get_children():
		_configure_subtree(child)


func _configure_text_input(node: Node) -> void:
	if not _touch_runtime_enabled() or not (node is LineEdit or node is TextEdit):
		return
	var control := node as Control
	if control.has_meta("mobile_text_input_policy"):
		return
	control.set_meta("mobile_text_input_policy", true)
	if node is LineEdit:
		var line := node as LineEdit
		# Keep the editor's desktop context menu enabled, but keep the keyboard disabled
		# until the policy has classified a real short tap.  Screens such as
		# Provider Settings and the resident editor intentionally call
		# grab_focus() for keyboard navigation; that must not pop the IME on entry.
		line.context_menu_enabled = true
		line.shortcut_keys_enabled = true
		line.virtual_keyboard_enabled = false
		line.virtual_keyboard_show_on_focus = false
		line.focus_exited.connect(_on_text_input_focus_exited.bind(line))
	else:
		var edit := node as TextEdit
		edit.context_menu_enabled = true
		edit.shortcut_keys_enabled = true
		edit.virtual_keyboard_enabled = false
		edit.virtual_keyboard_show_on_focus = false
		edit.focus_exited.connect(_on_text_input_focus_exited.bind(edit))


func _on_text_input_focus_exited(control: Control) -> void:
	if not is_instance_valid(control):
		return
	# Reset the gate after every edit session so a later programmatic focus
	# (opening another page, restoring a draft, or cycling a tab) stays silent.
	if control is LineEdit:
		(control as LineEdit).virtual_keyboard_enabled = false
		(control as LineEdit).virtual_keyboard_show_on_focus = false
	elif control is TextEdit:
		(control as TextEdit).virtual_keyboard_enabled = false
		(control as TextEdit).virtual_keyboard_show_on_focus = false
	if control == _keyboard_control:
		_clear_android_text_action()
		_hide_virtual_keyboard()


func _show_system_keyboard(control: Control) -> void:
	if (
		not _is_editable_text_input(control)
		or not control.has_focus()
	):
		return
	if control is LineEdit:
		(control as LineEdit).virtual_keyboard_enabled = false
	elif control is TextEdit:
		(control as TextEdit).virtual_keyboard_enabled = false
	_request_system_keyboard(control)
	_keyboard_control = control
	_keyboard_visible = true
	_keyboard_retry_remaining = KEYBOARD_RETRY_COUNT if OS.get_name() == "Android" else 0
	_keyboard_retry_at_msec = Time.get_ticks_msec() + KEYBOARD_RETRY_INTERVAL_MSEC


func _request_system_keyboard(control: Control) -> void:
	if not _is_editable_text_input(control) or not control.has_focus():
		return
	var text := ""
	var keyboard_type := DisplayServer.KEYBOARD_TYPE_DEFAULT
	var max_length := -1
	var cursor_start := -1
	var cursor_end := -1
	if control is LineEdit:
		var line := control as LineEdit
		text = line.text
		keyboard_type = int(line.virtual_keyboard_type) as DisplayServer.VirtualKeyboardType
		max_length = line.max_length
		cursor_start = line.caret_column
		if line.has_selection():
			cursor_start = line.get_selection_from_column()
			cursor_end = line.get_selection_to_column()
	elif control is TextEdit:
		var edit := control as TextEdit
		text = edit.text
		keyboard_type = int(edit.virtual_keyboard_type) as DisplayServer.VirtualKeyboardType
		cursor_start = edit.get_caret_column()
		if edit.has_selection():
			cursor_start = edit.get_selection_from_column()
			cursor_end = edit.get_selection_to_column()
	DisplayServer.virtual_keyboard_show(
		text,
		control.get_global_rect(),
		keyboard_type,
		max_length,
		cursor_start,
		cursor_end,
	)


func _hide_virtual_keyboard() -> void:
	if _keyboard_visible:
		DisplayServer.virtual_keyboard_hide()
	_keyboard_control = null
	_keyboard_visible = false
	_keyboard_retry_remaining = 0
	_keyboard_retry_at_msec = 0


func _text_input_at(position: Vector2) -> Control:
	if not is_inside_tree():
		return null
	# Touch-to-mouse emulation is dispatched before the original touch event, so
	# the viewport already knows the real topmost GUI control. Prefer that result
	# over scene-tree order; an overlay must never activate an editor behind it.
	var hovered := get_viewport().gui_get_hovered_control()
	if (
		is_instance_valid(hovered)
		and hovered.get_global_rect().has_point(position)
	):
		return _text_input_ancestor(hovered)
	var candidates: Array[Control] = []
	_collect_text_inputs(get_tree().root, position, candidates)
	return candidates.back() if not candidates.is_empty() else null


func _collect_text_inputs(
	node: Node,
	position: Vector2,
	result: Array[Control],
) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is LineEdit or node is TextEdit:
		var control := node as Control
		if (
			_is_editable_text_input(control)
			and control.mouse_filter != Control.MOUSE_FILTER_IGNORE
			and control.get_global_rect().has_point(position)
			and _point_inside_control_clips(control, position)
		):
			result.append(control)
	for child: Node in node.get_children():
		_collect_text_inputs(child, position, result)


func _text_input_ancestor(control: Control) -> Control:
	var current: Node = control
	while current != null:
		if current is LineEdit or current is TextEdit:
			var text_input := current as Control
			return text_input if _is_editable_text_input(text_input) else null
		current = current.get_parent()
	return null


func _is_editable_text_input(control: Control) -> bool:
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		return false
	if control is LineEdit:
		return (control as LineEdit).editable
	if control is TextEdit:
		return (control as TextEdit).editable
	return false


func _point_inside_control_clips(control: Control, position: Vector2) -> bool:
	var current: Node = control.get_parent()
	while current != null:
		if current is Control:
			var parent_control := current as Control
			if parent_control.clip_contents and not parent_control.get_global_rect().has_point(position):
				return false
		current = current.get_parent()
	return true


func _touch_runtime_enabled() -> bool:
	return _force_touch_runtime or MOBILE_UI_PROFILE.is_mobile_runtime()


func _native_text_actions_enabled() -> bool:
	return _force_android_text_actions or (
		OS.get_name() == "Android" and Engine.has_singleton("AndroidRuntime")
	)
