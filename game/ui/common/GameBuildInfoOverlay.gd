extends CanvasLayer


const RELEASE_CHANNEL := "release"


func _ready() -> void:
	layer = 250
	var root := Control.new()
	root.name = "GameBuildInfoRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var label := Label.new()
	label.name = "GameBuildInfoLabel"
	label.anchor_left = 1.0
	label.anchor_top = 1.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = -720.0
	label.offset_top = -54.0
	label.offset_right = -24.0
	label.offset_bottom = -18.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.82))
	label.add_theme_constant_override("outline_size", 6)
	var version := String(ProjectSettings.get_setting("application/config/version", "unknown"))
	var channel := String(ProjectSettings.get_setting("application/config/channel", RELEASE_CHANNEL))
	var version_label := "v%s-%s" % [version, channel]
	if channel.to_lower() == "beta":
		label.text = "当前为测试版本，不代表最终品质 · " + version_label
	else:
		label.text = version_label
	root.add_child(label)
