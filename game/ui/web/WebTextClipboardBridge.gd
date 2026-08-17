class_name WebTextClipboardBridge
extends Node


var _window: Variant
var _paste_callback: Variant
var _copy_callback: Variant
var _cut_callback: Variant


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web") or not ClassDB.class_exists("JavaScriptBridge"):
		return
	_window = JavaScriptBridge.get_interface("window")
	_paste_callback = JavaScriptBridge.create_callback(_on_paste)
	_copy_callback = JavaScriptBridge.create_callback(_on_copy)
	_cut_callback = JavaScriptBridge.create_callback(_on_cut)
	# Godot's default Web clipboard path is asynchronous and can be rejected by
	# browser permission policy. Handle the browser event directly so desktop Web
	# keeps the same Cmd/Ctrl shortcuts as the native build.
	_window.addEventListener("paste", _paste_callback)
	_window.addEventListener("copy", _copy_callback)
	_window.addEventListener("cut", _cut_callback)


func _exit_tree() -> void:
	if _window == null:
		return
	_window.removeEventListener("paste", _paste_callback)
	_window.removeEventListener("copy", _copy_callback)
	_window.removeEventListener("cut", _cut_callback)
	_window = null
	_paste_callback = null
	_copy_callback = null
	_cut_callback = null


func _on_paste(args: Array) -> void:
	var line := _focused_line_edit()
	if line == null or args.is_empty():
		return
	var event: Variant = args[0]
	var clipboard_data: Variant = event.clipboardData
	if clipboard_data == null:
		return
	var pasted_text := str(clipboard_data.getData("text/plain"))
	event.preventDefault()
	_replace_line_selection(line, pasted_text)


func _on_copy(args: Array) -> void:
	var line := _focused_line_edit()
	if line == null or not line.has_selection() or args.is_empty():
		return
	var event: Variant = args[0]
	var clipboard_data: Variant = event.clipboardData
	if clipboard_data == null:
		return
	clipboard_data.setData("text/plain", line.get_selected_text())
	event.preventDefault()


func _on_cut(args: Array) -> void:
	var line := _focused_line_edit()
	if line == null or not line.has_selection() or args.is_empty():
		return
	var event: Variant = args[0]
	var clipboard_data: Variant = event.clipboardData
	if clipboard_data == null:
		return
	clipboard_data.setData("text/plain", line.get_selected_text())
	event.preventDefault()
	_replace_line_selection(line, "")


func _focused_line_edit() -> LineEdit:
	if not is_inside_tree():
		return null
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner as LineEdit if focus_owner is LineEdit else null


func _replace_line_selection(line: LineEdit, replacement: String) -> void:
	var from_column := line.caret_column
	var to_column := line.caret_column
	if line.has_selection():
		from_column = line.get_selection_from_column()
		to_column = line.get_selection_to_column()
	line.text = line.text.left(from_column) + replacement + line.text.substr(to_column)
	line.caret_column = from_column + replacement.length()
	line.deselect()
