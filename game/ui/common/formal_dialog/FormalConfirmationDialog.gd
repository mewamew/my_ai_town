class_name FormalConfirmationDialog
extends Control


signal confirmed
signal canceled

const DESIGN_SIZE := Vector2(1024, 640)
const PANEL_TEXTURE := preload(
	"res://assets/ui/common/formal_dialog_v1/runtime/"
	+ "formal_dialog_panel_base_v1_1024x640.png"
)
const INPUT_TEXTURE := preload(
	"res://assets/ui/common/formal_dialog_v1/runtime/"
	+ "formal_dialog_input_frame_v1_1024x192.png"
)
const MEMORY_ICON := preload(
	"res://assets/ui/common/formal_dialog_v1/runtime/"
	+ "formal_dialog_memory_icon_v1_128x128.png"
)
const WARNING_ICON := preload(
	"res://assets/ui/common/system_feedback/icons/warning.svg"
)
const ERROR_ICON := preload(
	"res://assets/ui/common/formal_dialog_v1/runtime/"
	+ "formal_dialog_error_icon_v1_128x128.png"
)
const INFO_ICON := preload(
	"res://assets/ui/common/system_feedback/icons/info.svg"
)
const FONT := preload(
	"res://assets/fonts/zheng_ge_dian_hei_16/ZhengGeDianHei-16.ttf"
)
const PAPER_BUTTON_ROOT := (
	"res://assets/ui/common/formal_dialog_v1/runtime/buttons/"
)
const PRIMARY_BUTTON_ROOT := (
	"res://assets/ui/common/system_feedback/buttons_v3/"
)

var title := ""
var dialog_text := ""
var ok_button_text := "确认"
var cancel_button_text := "取消"
var semantic_kind := "warning"
var semantic_icon: Texture2D
var custom_content_frame_texture: Texture2D

var _veil: ColorRect
var _stage: Control
var _panel: TextureRect
var _icon: TextureRect
var _title_label: Label
var _body_label: Label
var _input_frame: NinePatchRect
var _cancel_button: Button
var _confirm_button: Button
var _custom_content: Control


func _ready() -> void:
	_ensure_interface()
	if not resized.is_connected(_apply_layout):
		resized.connect(_apply_layout)
	_apply_layout()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	_cancel()
	get_viewport().set_input_as_handled()


func popup_centered(_requested_size := Vector2i.ZERO) -> void:
	_ensure_interface()
	_apply_copy()
	_apply_layout()
	visible = true
	move_to_front()
	_cancel_button.grab_focus.call_deferred()


func set_custom_content(control: Control) -> void:
	_ensure_interface()
	if _custom_content == control:
		return
	if is_instance_valid(_custom_content):
		_custom_content.reparent(get_parent())
	_custom_content = control
	if _custom_content == null:
		_input_frame.visible = false
		return
	if _custom_content.get_parent() != _stage:
		_stage.add_child(_custom_content)
	_custom_content.add_theme_stylebox_override(
		"normal",
		StyleBoxEmpty.new()
	)
	_custom_content.add_theme_stylebox_override(
		"focus",
		StyleBoxEmpty.new()
	)
	_custom_content.add_theme_stylebox_override(
		"read_only",
		StyleBoxEmpty.new()
	)
	_custom_content.add_theme_font_override("font", FONT)
	_custom_content.add_theme_font_size_override("font_size", 26)
	_custom_content.add_theme_color_override("font_color", Color("3f2818"))
	_custom_content.add_theme_color_override(
		"font_placeholder_color",
		Color("76583d")
	)
	_custom_content.add_theme_color_override("caret_color", Color("b94d2d"))
	_layout_content()


func _ensure_interface() -> void:
	if _stage != null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1000
	visible = false

	_veil = ColorRect.new()
	_veil.name = "ModalVeil"
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.color = Color("11140fcc")
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_veil)

	_stage = Control.new()
	_stage.name = "FormalDialogStage"
	_stage.size = DESIGN_SIZE
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stage)

	_panel = TextureRect.new()
	_panel.name = "FormalDialogPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.texture = PANEL_TEXTURE
	_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel.stretch_mode = TextureRect.STRETCH_SCALE
	_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_panel)

	_icon = TextureRect.new()
	_icon.name = "SemanticIcon"
	_icon.position = Vector2(130, 108)
	_icon.size = Vector2(104, 104)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_icon)

	_title_label = _make_label("Title", 42)
	_title_label.position = Vector2(258, 112)
	_title_label.size = Vector2(620, 92)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	_body_label = _make_label("Body", 28)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_input_frame = NinePatchRect.new()
	_input_frame.name = "InputAssetFrame"
	_input_frame.texture = INPUT_TEXTURE
	_input_frame.patch_margin_left = 52
	_input_frame.patch_margin_top = 48
	_input_frame.patch_margin_right = 52
	_input_frame.patch_margin_bottom = 48
	_input_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_input_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_input_frame.visible = false
	_stage.add_child(_input_frame)

	_cancel_button = _make_button("Cancel", false)
	_cancel_button.pressed.connect(_cancel)
	_confirm_button = _make_button("Confirm", true)
	_confirm_button.pressed.connect(_confirm)
	_layout_content()


func _make_label(node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("3f2818"))
	label.add_theme_constant_override("line_spacing", 8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stage.add_child(label)
	return label


func _make_button(node_name: String, primary: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(320, 76)
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 28)
	var text_color := Color("fff8e6") if primary else Color("3f2818")
	for color_name: String in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
	]:
		button.add_theme_color_override(color_name, text_color)
	var paths := (
		{
			"normal": PRIMARY_BUTTON_ROOT + "normal.png",
			"hover": PRIMARY_BUTTON_ROOT + "hover.png",
			"pressed": PRIMARY_BUTTON_ROOT + "pressed.png",
			"focus": PRIMARY_BUTTON_ROOT + "hover.png",
			"disabled": PRIMARY_BUTTON_ROOT + "disabled.png",
		}
		if primary
		else {
			"normal": PAPER_BUTTON_ROOT + "button_paper_normal_v1.png",
			"hover": PAPER_BUTTON_ROOT + "button_paper_hover_v1.png",
			"pressed": PAPER_BUTTON_ROOT + "button_paper_pressed_v1.png",
			"focus": PAPER_BUTTON_ROOT + "button_paper_hover_v1.png",
			"disabled": PAPER_BUTTON_ROOT + "button_paper_normal_v1.png",
		}
	)
	for state: String in paths:
		button.add_theme_stylebox_override(
			state,
			_texture_style(String(paths[state]))
		)
	_stage.add_child(button)
	return button


func _texture_style(path: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = ResourceLoader.load(path, "Texture2D") as Texture2D
	style.texture_margin_left = 28
	style.texture_margin_top = 20
	style.texture_margin_right = 28
	style.texture_margin_bottom = 20
	style.content_margin_left = 18
	style.content_margin_top = 10
	style.content_margin_right = 18
	style.content_margin_bottom = 10
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return style


func _apply_copy() -> void:
	_title_label.text = title
	_body_label.text = dialog_text
	_cancel_button.text = cancel_button_text
	_confirm_button.text = ok_button_text
	_icon.texture = _semantic_icon()
	_input_frame.texture = (
		custom_content_frame_texture
		if custom_content_frame_texture != null
		else INPUT_TEXTURE
	)
	_layout_content()


func _semantic_icon() -> Texture2D:
	if semantic_icon != null:
		return semantic_icon
	match semantic_kind:
		"error":
			return ERROR_ICON
		"memory":
			return MEMORY_ICON
		"info":
			return INFO_ICON
		_:
			return WARNING_ICON


func _layout_content() -> void:
	if _stage == null:
		return
	var has_custom := is_instance_valid(_custom_content) and _custom_content.visible
	_input_frame.visible = has_custom
	if has_custom:
		_body_label.position = Vector2(116, 208)
		_body_label.size = Vector2(792, 82)
		_input_frame.position = Vector2(112, 306)
		_input_frame.size = Vector2(800, 126)
		_custom_content.position = Vector2(146, 336)
		_custom_content.size = Vector2(732, 68)
	else:
		_body_label.position = Vector2(124, 220)
		_body_label.size = Vector2(776, 180)
	_cancel_button.position = Vector2(136, 468)
	_cancel_button.size = Vector2(340, 82)
	_confirm_button.position = Vector2(548, 468)
	_confirm_button.size = Vector2(340, 82)


func _apply_layout() -> void:
	if _stage == null:
		return
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	var available := Vector2(
		maxf(1.0, viewport_size.x - 48.0),
		maxf(1.0, viewport_size.y - 48.0)
	)
	var uniform_scale := minf(
		1.0,
		minf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y)
	)
	_stage.scale = Vector2.ONE * uniform_scale
	_stage.position = (
		(viewport_size - DESIGN_SIZE * uniform_scale) * 0.5
	).floor()
	_layout_content()


func _confirm() -> void:
	visible = false
	confirmed.emit()


func _cancel() -> void:
	visible = false
	canceled.emit()
