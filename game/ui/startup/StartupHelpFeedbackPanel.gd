class_name StartupHelpFeedbackPanel
extends Control


signal external_open_failed(message: String)


const GAME_FEEDBACK_REPORT := preload(
	"res://ui/startup/GameFeedbackReport.gd"
)
const UI_FONT := preload(
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const ISSUE_ICON := preload(
	"res://assets/ui/startup/runtime/social_links/feedback_options/issue.png"
)
const FEEDBACK_ICON := preload(
	"res://assets/ui/startup/runtime/social_links/feedback_options/feedback.png"
)
const DROPDOWN_FRAME := preload(
	"res://assets/ui/startup/runtime/social_links/feedback_options/dropdown_frame.png"
)
const FEISHU_FEEDBACK_URL := (
	"https://jcnndrf8pn45.feishu.cn/share/base/form/"
	+ "shrcnaQyfFoz7npOKF6kqVulsFg"
)


func _ready() -> void:
	name = "StartupHelpFeedbackPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		get_viewport().set_input_as_handled()
		_close()


func _build_interface() -> void:
	name = "StartupHelpFeedbackPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP

	var frame := TextureRect.new()
	frame.name = "DropdownFrame"
	frame.position = Vector2.ZERO
	frame.size = Vector2(208.0, 116.5)
	frame.texture = DROPDOWN_FRAME
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var content := Control.new()
	content.name = "OptionHitAreas"
	content.position = Vector2.ZERO
	content.size = Vector2(208.0, 116.5)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	var issue_button := _add_option_card(
		content,
		"GitHubIssueButton",
		"提交 Issue",
		ISSUE_ICON,
		Rect2(18.5, 22.0, 79.0, 84.0),
		_open_github_issue,
	)
	var alternative_feedback_button := _add_option_card(
		content,
		"AlternativeFeedbackButton",
		"提交反馈",
		FEEDBACK_ICON,
		Rect2(108.5, 22.0, 79.0, 84.0),
		_open_alternative_feedback,
	)

	issue_button.focus_neighbor_right = issue_button.get_path_to(alternative_feedback_button)
	alternative_feedback_button.focus_neighbor_left = (
		alternative_feedback_button.get_path_to(issue_button)
	)
	issue_button.grab_focus.call_deferred()


func _add_option_card(
	parent: Control,
	node_name: String,
	caption_text: String,
	icon: Texture2D,
	rect: Rect2,
	callback: Callable,
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.position = rect.position
	button.size = rect.size
	button.text = ""
	button.tooltip_text = caption_text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", _interaction_style(Color(1.0, 0.96, 0.82, 0.12)))
	button.add_theme_stylebox_override("pressed", _interaction_style(Color(0.55, 0.34, 0.16, 0.12)))
	button.add_theme_stylebox_override("focus", _interaction_style(Color(1.0, 0.96, 0.82, 0.08)))
	button.pressed.connect(callback)
	parent.add_child(button)

	var icon_rect := TextureRect.new()
	icon_rect.name = "OptionIcon"
	icon_rect.position = Vector2(22.5, 10.0)
	icon_rect.size = Vector2(34.0, 34.0)
	icon_rect.texture = icon
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon_rect)

	var caption := Label.new()
	caption.name = "OptionCaption"
	caption.position = Vector2(2.0, 51.0)
	caption.size = Vector2(75.0, 24.0)
	caption.text = caption_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font", UI_FONT)
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", Color("3f2818"))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(caption)
	return button


func _interaction_style(
	background: Color,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.anti_aliasing = false
	return style


func _open_alternative_feedback() -> void:
	_open_external_url(FEISHU_FEEDBACK_URL, "玩家反馈表单")


func _open_github_issue() -> void:
	_open_external_url(
		GAME_FEEDBACK_REPORT.build_issue_url(),
		"GitHub 新建 Issue 页面",
	)


func _open_external_url(url: String, destination_name: String) -> void:
	var open_error := OS.shell_open(url)
	if open_error == OK:
		_close()
		return
	push_warning(
		"帮助与反馈选项无法打开外部链接：%s (%s)"
		% [url, error_string(open_error)]
	)
	external_open_failed.emit(
		"暂时无法打开%s，请稍后再试。" % destination_name
	)


func _close() -> void:
	queue_free()
