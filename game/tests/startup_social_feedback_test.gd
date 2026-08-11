extends SceneTree


const STARTUP_SCENE := preload("res://ui/startup/StartupScreen.tscn")
const STARTUP_SCREEN := preload("res://ui/startup/StartupScreen.gd")
const HELP_FEEDBACK_PANEL := preload(
	"res://ui/startup/StartupHelpFeedbackPanel.gd"
)
const FEEDBACK_REPORT := preload("res://ui/startup/GameFeedbackReport.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var checks := 0
	var startup := STARTUP_SCENE.instantiate() as Control
	root.add_child(startup)
	await process_frame

	for button_name: String in [
		"GitHubButton",
		"BilibiliButton",
	]:
		var button := startup.get_node_or_null(button_name) as TextureButton
		checks += _expect(button != null, "%s 必须存在。" % button_name, failures)
		if button == null:
			continue
		checks += _expect(
			button.texture_normal != null and button.texture_hover != null,
			"%s 必须具备默认态和悬停态图片。" % button_name,
			failures,
		)
		checks += _expect(
			button.texture_normal.get_size() == Vector2(179.0, 176.0)
			and button.texture_hover.get_size() == Vector2(179.0, 176.0),
			"%s 的图片尺寸必须保持一致。" % button_name,
			failures,
		)
		checks += _expect(
			button.focus_mode == Control.FOCUS_ALL,
			"%s 必须支持键盘焦点。" % button_name,
			failures,
		)
		checks += _expect(
			not button.tooltip_text.is_empty(),
			"%s 必须说明按钮用途。" % button_name,
			failures,
		)
		var reference_rect := button.get_meta("startup_reference_rect") as Rect2
		checks += _expect(
			reference_rect.position.x >= 0.0
			and reference_rect.position.y >= 0.0
			and reference_rect.end.x <= 1920.0
			and reference_rect.end.y <= 1080.0,
			"%s 必须位于启动页参考画布内。" % button_name,
			failures,
		)

	var help_feedback_button := startup.get_node_or_null(
		"HelpFeedbackButton"
	) as TextureButton
	checks += _expect(
		help_feedback_button != null,
		"启动页必须提供帮助与反馈入口。",
		failures,
	)
	if help_feedback_button != null:
		checks += _expect(
			help_feedback_button.texture_normal != null
			and help_feedback_button.texture_hover != null,
			"帮助与反馈入口必须使用纸飞机的默认态和悬停态图片。",
			failures,
		)
		checks += _expect(
			help_feedback_button.texture_normal.get_size() == Vector2(179.0, 176.0)
			and help_feedback_button.texture_hover.get_size() == Vector2(179.0, 176.0),
			"纸飞机的默认态和悬停态图片尺寸必须一致。",
			failures,
		)
		checks += _expect(
			not help_feedback_button.tooltip_text.is_empty(),
			"纸飞机必须说明按钮用途。",
			failures,
		)
		var feedback_caption := help_feedback_button.get_node_or_null(
			"ButtonCaption"
		) as Label
		checks += _expect(
			feedback_caption != null and feedback_caption.text == "反馈",
			"纸飞机按钮必须准确显示“反馈”二字。",
			failures,
		)
		checks += _expect(
			help_feedback_button.clip_contents,
			"纸飞机按钮必须裁切越过木框的内容。",
			failures,
		)
		checks += _expect(
			help_feedback_button.focus_mode == Control.FOCUS_ALL,
			"帮助与反馈入口必须支持键盘焦点。",
			failures,
		)
		var help_rect := help_feedback_button.get_meta(
			"startup_reference_rect"
		) as Rect2
		checks += _expect(
			help_rect.position.x >= 0.0
			and help_rect.position.y >= 0.0
			and help_rect.end.x <= 1920.0
			and help_rect.end.y <= 1080.0,
			"帮助与反馈入口必须位于启动页参考画布内。",
			failures,
		)
		checks += _expect(
			help_rect.size == Vector2(96.0, 94.0),
			"纸飞机必须与旁边两个社交按钮保持同一显示尺寸。",
			failures,
		)
		help_feedback_button.pressed.emit()
		await process_frame

	var help_panel := startup.get_node_or_null(
		"StartupHelpFeedbackPanel"
	) as Control
	checks += _expect(help_panel != null, "横向反馈选项必须可以展开。", failures)
	if help_panel != null:
		var expected_captions := {
			"GitHubIssueButton": "提交 Issue",
			"AlternativeFeedbackButton": "提交反馈",
		}
		for panel_button_name: String in expected_captions:
			var panel_button := help_panel.find_child(
				panel_button_name,
				true,
				false,
			) as Button
			checks += _expect(
				panel_button != null,
				"横向反馈选项缺少 %s。" % panel_button_name,
				failures,
			)
			if panel_button != null:
				checks += _expect(
					panel_button.focus_mode == Control.FOCUS_ALL,
					"%s 必须支持键盘焦点。" % panel_button_name,
					failures,
				)
				var focus_style := panel_button.get_theme_stylebox("focus")
				checks += _expect(
					focus_style.get_border_width(SIDE_LEFT) == 0
					and focus_style.get_border_width(SIDE_TOP) == 0
					and focus_style.get_border_width(SIDE_RIGHT) == 0
					and focus_style.get_border_width(SIDE_BOTTOM) == 0,
					"%s 的键盘焦点不得显示黄色点选框。" % panel_button_name,
					failures,
				)
				var option_icon := panel_button.get_node_or_null(
					"OptionIcon"
				) as TextureRect
				var option_caption := panel_button.get_node_or_null(
					"OptionCaption"
				) as Label
				checks += _expect(
					option_icon != null and option_icon.texture != null,
					"%s 必须显示子图标。" % panel_button_name,
					failures,
				)
				checks += _expect(
					option_caption != null
					and option_caption.text == String(expected_captions[panel_button_name]),
					"%s 必须显示设计稿确认的文字说明。" % panel_button_name,
					failures,
				)
		checks += _expect(
			help_panel.size.x > help_panel.size.y * 1.5,
			"反馈选项必须使用横向弹窗布局。",
			failures,
		)
		var panel_rect := help_panel.get_meta("startup_reference_rect") as Rect2
		checks += _expect(
			panel_rect.get_center().x == 1720.0,
			"横向反馈选项必须以纸飞机中心线向两侧展开。",
			failures,
		)
		var dropdown_frame := help_panel.get_node_or_null(
			"DropdownFrame"
		) as TextureRect
		checks += _expect(
			dropdown_frame != null
			and dropdown_frame.texture != null
			and dropdown_frame.texture.get_size() == Vector2(416.0, 233.0),
			"横向反馈选项必须使用设计稿确认的完整图片框。",
			failures,
		)
	checks += _expect(
		STARTUP_SCREEN.GITHUB_URL
		== "https://github.com/mewamew/my_ai_town",
		"GitHub 按钮必须打开仓库主页。",
		failures,
	)
	checks += _expect(
		STARTUP_SCREEN.BILIBILI_URL
		== "https://space.bilibili.com/3546572358945017",
		"哔哩哔哩按钮必须打开项目主页。",
		failures,
	)
	checks += _expect(
		HELP_FEEDBACK_PANEL.FEISHU_FEEDBACK_URL
		== (
			"https://jcnndrf8pn45.feishu.cn/share/base/form/"
			+ "shrcnaQyfFoz7npOKF6kqVulsFg"
		),
		"提交反馈必须打开公开的飞书反馈表单。",
		failures,
	)

	var issue_url := FEEDBACK_REPORT.build_issue_url({
		"godotVersion": "4.7.test",
		"operatingSystem": "TestOS 1",
		"architecture": "test-arch",
		"processor": "Test CPU",
		"gpuVendor": "Test Vendor",
		"gpuName": "Test GPU",
		"graphicsApi": "Test API",
		"renderingMethod": "test-method",
		"renderingDriver": "test-driver",
	})
	var decoded_issue_url := issue_url.uri_decode()
	checks += _expect(
		issue_url.begins_with(
			"https://github.com/mewamew/my_ai_town/issues/new?"
		),
		"提交 Issue 必须打开本仓库的新建 Issue 页面。",
		failures,
	)
	for expected_text: String in [
		"反馈类型",
		"Bug",
		"功能需求",
		"问题或需求描述",
		"复现步骤（Bug）",
		"期望结果",
		"发生频率（Bug）",
		"4.7.test",
		"TestOS 1",
		"test-arch",
		"Test CPU",
		"Test Vendor Test GPU",
		"Test API",
		"test-method / test-driver",
		"请勿上传 API Key",
	]:
		checks += _expect(
			decoded_issue_url.contains(expected_text),
			"Issue 自动填写内容缺少：%s" % expected_text,
			failures,
		)
	checks += _expect(
		not decoded_issue_url.contains("游戏版本"),
		"Release 版本来源确定前，Issue 不得自动填写游戏版本。",
		failures,
	)
	checks += _expect(
		not decoded_issue_url.contains("系统内存")
		and not decoded_issue_url.contains("显存"),
		"反馈入口不得通过系统命令收集内存或显存信息。",
		failures,
	)

	startup.free()
	_prepare_project_shutdown()
	await process_frame
	await create_timer(0.2).timeout
	_finish(failures, checks)


func _expect(
	condition: bool,
	message: String,
	failures: Array[String],
) -> int:
	if not condition:
		failures.append(message)
	return 1


func _prepare_project_shutdown() -> void:
	var audio_controller := root.get_node_or_null("TownAudioController")
	if (
		audio_controller != null
		and audio_controller.has_method("prepare_shutdown")
	):
		audio_controller.call("prepare_shutdown")


func _finish(failures: Array[String], checks: int) -> void:
	if failures.is_empty():
		print("STARTUP_SOCIAL_FEEDBACK_PASS checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error(
		"STARTUP_SOCIAL_FEEDBACK_FAILED checks=%d failures=%d"
		% [checks, failures.size()]
	)
	quit(1)
