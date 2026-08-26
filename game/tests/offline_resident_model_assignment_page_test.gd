extends SceneTree


const OFFLINE_REBIND := preload(
	"res://world/presentation/session/TownOfflineResidentModelRebindService.gd"
)
const ASSIGNMENT_SERVICE := preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentService.gd"
)
const FEEDBACK_POLICY := preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentFeedbackPolicy.gd"
)
const UI_ADAPTER := preload("res://world/presentation/ui/TownUiAdapter.gd")
const FIXTURE := preload("res://tests/support/OfflineResidentModelRebindFixture.gd")


var _failures: Array[String] = []
var _checks := 0
var _fixture: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var identity := "p%d%d" % [
		OS.get_process_id() % 1000,
		Time.get_ticks_usec() % 100000,
	]
	_fixture = FIXTURE.new()
	_expect_ok(
		_fixture.call("configure", identity) as Dictionary,
		"模型分配页专项使用隔离夹具",
	)
	_expect_ok(
		_fixture.call("create_source_revision") as Dictionary,
		"模型分配页专项创建完整修订",
	)
	var service := OFFLINE_REBIND.new() as RefCounted
	_expect_ok(service.call(
		"configure",
		_fixture.get("save_store"),
		_fixture.get("agent_store"),
		_fixture.call("provider"),
	) as Dictionary, "模型分配页专项配置离线服务")
	var prepared := service.call(
		"prepare",
		_fixture.call("catalog_slot"),
		_fixture.call("base_catalog"),
	) as Dictionary
	_expect_ok(prepared, "模型分配页专项准备旧绑定草稿")
	await _test_save_slot_page(prepared)
	_fixture.call("cleanup")
	_fixture = null
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
	await create_timer(0.3, true, false, true).timeout
	if _failures.is_empty():
		print("OFFLINE_RESIDENT_MODEL_ASSIGNMENT_PAGE_PASS checks=%d" % _checks)
	else:
		for failure in _failures:
			printerr("OFFLINE_RESIDENT_MODEL_ASSIGNMENT_PAGE_FAIL: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_save_slot_page(prepared: Dictionary) -> void:
	var valid_draft := (prepared.get("draft", {}) as Dictionary).duplicate(true)
	var slots := valid_draft.get("slots", []) as Array
	for index in slots.size():
		var slot := (slots[index] as Dictionary).duplicate(true)
		slot["llmBinding"] = {
			"mode": "model",
			"providerId": "current-provider",
			"modelId": "current-model",
		}
		slots[index] = slot
	valid_draft["slots"] = slots
	var assignment := ASSIGNMENT_SERVICE.new()
	assignment.configure(
		_fixture.call("provider"),
		prepared.get("residentCatalog", {}) as Dictionary,
		valid_draft,
	)
	_expect(
		String(FEEDBACK_POLICY.error_message(
			"SESSION_SAVE_MANIFEST_PUBLISH_FAILED",
		)).contains("重试"),
		"磁盘发布失败给出明确重试说明",
	)
	_expect(
		String(FEEDBACK_POLICY.error_message(
			"OFFLINE_RESIDENT_MODEL_REBIND_TARGET_STALE",
		)).contains("返回加载页"),
		"并发冲突提示重新选择最新修订",
	)
	var adapter := UI_ADAPTER.new()
	root.add_child(adapter)
	adapter.bind_resident_model_assignment_service(assignment)
	var scene := load(
		"res://ui/resident_model_assignment/ResidentModelAssignmentScreen.tscn",
	) as PackedScene
	var screen := scene.instantiate() as Control
	screen.call("apply_route_payload", {"mode": "save_slot"})
	screen.call("bind_town_ui_adapter", adapter)
	root.add_child(screen)
	await process_frame
	var snapshot := screen.call("runtime_gate_snapshot") as Dictionary
	_expect_equal(snapshot.get("routeMode"), "save_slot", "模型分配页使用单一 save_slot RouteMode")
	var original_viewport_size := root.size
	var layout_cases := [
		[Vector2i(1920, 1080), "wide", "宽屏"],
		[Vector2i(960, 540), "compact", "紧凑横屏"],
		[Vector2i(540, 960), "portrait", "紧凑竖屏"],
	]
	for layout_case_value: Variant in layout_cases:
		var layout_case := layout_case_value as Array
		root.size = layout_case[0] as Vector2i
		for _index in 5:
			await process_frame
		snapshot = screen.call("runtime_gate_snapshot") as Dictionary
		_expect_equal(root.size, layout_case[0], "%s 使用真实 viewport 尺寸" % String(layout_case[2]))
		_expect_equal(
			snapshot.get("profile"),
			layout_case[1],
			"%s 使用预期布局" % String(layout_case[2]),
		)
		_expect(
			screen.is_visible_in_tree()
			and screen.get_global_rect().intersects(Rect2(Vector2.ZERO, screen.size)),
			"%s 页面仍可见且没有整体裁出 viewport" % String(layout_case[2]),
		)
		var page_scroll := screen.get("_page_scroll") as ScrollContainer
		var page_panel := screen.get("_page_panel") as Control
		if String(layout_case[1]) in ["compact", "portrait"]:
			_expect(
				page_scroll != null and page_scroll.is_visible_in_tree(),
				"%s 页面滚动容器可见" % String(layout_case[2]),
			)
			_expect(
				page_panel != null
				and page_panel.size.y > screen.size.y
				and page_scroll.get_v_scroll_bar().max_value
				> page_scroll.get_v_scroll_bar().page,
				"%s 超长内容通过滚动承载，没有压缩或静默裁切" % String(layout_case[2]),
			)
		var touch_targets := snapshot.get("touchTargets", []) as Array
		for target_value: Variant in touch_targets:
			var target := target_value as Dictionary
			var physical_rect := _physical_gate_rect(
				target.get("rect", []) as Array,
				screen,
			)
			_expect(
				physical_rect.size.x >= 48.0 and physical_rect.size.y >= 48.0,
				"%s 可见操作区 %s 的真实命中区至少 48×48（rect=%s）" % [
					String(layout_case[2]),
					String(target.get("id", "")),
					physical_rect,
				],
			)
		_expect_touch_targets_do_not_overlap(touch_targets, screen, String(layout_case[2]))
		if String(layout_case[1]) in ["compact", "portrait"]:
			await _exercise_gamepad(screen, assignment, String(layout_case[2]))
	root.size = Vector2i(960, 540)
	for _index in 5:
		await process_frame
	var mode_button := screen.find_child("ModeButton", true, false) as Button
	var keyboard_mode_before := String(
		(assignment.get_view_model().get("data", {}) as Dictionary).get("mode", ""),
	)
	mode_button.grab_focus()
	await _send_key(KEY_ENTER)
	_expect(
		String(
			(assignment.get_view_model().get("data", {}) as Dictionary).get("mode", ""),
		) != keyboard_mode_before,
		"紧凑横屏下键盘 Enter 可操作当前焦点",
	)
	var mode_view_model := assignment.call("get_view_model") as Dictionary
	assignment.call(
		"dispatch",
		"resident_model_assignment.set_mode",
		{
			"revision": int(mode_view_model.get("revision", -1)),
			"mode": "single",
		},
	)
	root.size = Vector2i(1920, 1080)
	for _index in 5:
		await process_frame
	var list_fallback := screen.find_child(
		"ResidentPortraitFallback0",
		true,
		false,
	) as Label
	var detail_fallback := screen.find_child(
		"SelectedResidentPortraitFallback",
		true,
		false,
	) as Label
	_expect(
		list_fallback != null and list_fallback.visible and list_fallback.text == "甲",
		"列表区头像缺失时显示姓名首字",
	)
	_expect(
		detail_fallback != null and detail_fallback.visible and detail_fallback.text == "甲",
		"详情区头像缺失时显示姓名首字",
	)
	var apply_button := screen.find_child("ApplyDraftButton", true, false) as Button
	_expect(
		apply_button != null and apply_button.text == "保存到此存档",
		"save_slot 模式使用存档专用提交文案",
	)
	var back_button := screen.find_child("BackButton", true, false) as Button
	_expect(
		back_button != null and back_button.text == "← 返回加载存档",
		"save_slot 模式显示正确的返回目标",
	)
	screen.call("_open_completion_modal")
	await process_frame
	var native_body := screen.get("_native_modal_body") as Label
	var native_start := screen.get("_native_modal_start_button") as Button
	var simplified := screen.find_child(
		"ResidentModelAssignmentOriginalSimplifiedV34",
		true,
		false,
	) as Control
	var simplified_button_labels := simplified.get("_button_labels") as Dictionary
	var simplified_primary := simplified.get("_completion_message_primary") as Label
	var simplified_secondary := simplified.get("_completion_message_secondary") as Label
	var simplified_start_copy := simplified_button_labels.get("modal_start") as Label
	var completion_controls_ready := (
		native_body != null
		and native_start != null
		and simplified_primary != null
		and simplified_secondary != null
		and simplified_start_copy != null
	)
	_expect(completion_controls_ready, "两套完成弹窗控件均已创建")
	if completion_controls_ready:
		_expect_equal(
			native_body.text,
			"%s\n%s" % [simplified_primary.text, simplified_secondary.text],
			"响应式与宽屏完成文案来自同一策略",
		)
		_expect_equal(
			native_start.text,
			simplified_start_copy.text,
			"响应式与宽屏完成按钮文案一致",
		)
	screen.call("_close_completion_modal")
	await process_frame
	await _assert_shared_failure_copy(screen, assignment, simplified)
	root.size = original_viewport_size
	for _index in 3:
		await process_frame
	root.remove_child(screen)
	screen.free()
	root.remove_child(adapter)
	adapter.free()


func _exercise_gamepad(
	screen: Control,
	assignment: RefCounted,
	layout_name: String,
) -> void:
	var mode_button := screen.find_child("ModeButton", true, false) as Button
	_expect(mode_button != null and mode_button.is_visible_in_tree(), "%s 模式按钮可见" % layout_name)
	if mode_button == null:
		return
	mode_button.grab_focus()
	for _index in 2:
		await process_frame
	var gamepad_down := InputEventJoypadButton.new()
	gamepad_down.button_index = JOY_BUTTON_DPAD_DOWN
	gamepad_down.pressed = true
	Input.parse_input_event(gamepad_down)
	await process_frame
	gamepad_down = gamepad_down.duplicate()
	gamepad_down.pressed = false
	Input.parse_input_event(gamepad_down)
	await process_frame
	var traversed := root.get_viewport().gui_get_focus_owner() as Control
	_expect(
		traversed != null and traversed != mode_button,
		"%s 手柄方向键实际移动焦点" % layout_name,
	)
	var before_mode := String(
		(assignment.get_view_model().get("data", {}) as Dictionary).get("mode", ""),
	)
	mode_button.grab_focus()
	for _index in 2:
		await process_frame
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	Input.parse_input_event(accept)
	await process_frame
	accept = accept.duplicate()
	accept.pressed = false
	Input.parse_input_event(accept)
	await process_frame
	var after_mode := String(
		(assignment.get_view_model().get("data", {}) as Dictionary).get("mode", ""),
	)
	_expect(after_mode != before_mode, "%s 手柄 A 键执行当前焦点操作" % layout_name)


func _assert_shared_failure_copy(
	screen: Control,
	assignment: RefCounted,
	simplified: Control,
) -> void:
	var view_model := assignment.call("get_view_model") as Dictionary
	view_model["revision"] = int(view_model.get("revision", 0)) + 1
	view_model["status"] = "rejected"
	view_model["operation"] = {
		"requestId": "shared-feedback",
		"intent": "resident_model_assignment.apply_draft",
		"status": "rejected",
		"submittedAtMsec": 0,
		"completedAtMsec": Time.get_ticks_msec(),
	}
	view_model["error"] = {
		"kind": "rejected",
		"code": "LLM_MODEL_UNAVAILABLE",
		"retryable": false,
		"message": "目标 Provider 或模型当前不可用，原绑定与草稿已保留。",
		"details": [],
	}
	_expect(bool(screen.call("apply_view_model", view_model)), "页面接受共享失败反馈样本")
	await process_frame
	var native_operation := screen.get("_operation_label") as Label
	var simplified_labels := simplified.get("_labels") as Dictionary
	var simplified_operation := simplified_labels.get("Operation") as Label
	_expect_equal(
		native_operation.text if native_operation != null else "missing",
		simplified_operation.text if simplified_operation != null else "missing",
		"响应式与宽屏失败文案来自同一 FeedbackPolicy",
	)


func _expect_touch_targets_do_not_overlap(
	targets: Array,
	screen: Control,
	layout_name: String,
) -> void:
	var key_ids := [
		"BackButton", "ProviderSettingsButton", "ModeButton", "RefreshButton",
		"AssignButton", "ApplyDraftButton", "Simplified:back", "Simplified:mode",
		"Simplified:provider_settings", "Simplified:assign", "Simplified:apply",
	]
	var key_targets: Array[Dictionary] = []
	for target_value: Variant in targets:
		var target := target_value as Dictionary
		if String(target.get("id", "")) in key_ids:
			key_targets.append(target)
	for left_index in key_targets.size():
		var left := key_targets[left_index]
		var left_rect := _physical_gate_rect(left.get("rect", []) as Array, screen)
		for right_index in range(left_index + 1, key_targets.size()):
			var right := key_targets[right_index]
			var right_rect := _physical_gate_rect(right.get("rect", []) as Array, screen)
			_expect(
				not left_rect.intersects(right_rect),
				"%s 关键操作区 %s 与 %s 不重叠" % [
					layout_name,
					String(left.get("id", "")),
					String(right.get("id", "")),
				],
			)


func _physical_gate_rect(values: Array, screen: Control) -> Rect2:
	if values.size() != 4 or screen == null or screen.size.x <= 0.0 or screen.size.y <= 0.0:
		return Rect2()
	var rect := Rect2(
		float(values[0]),
		float(values[1]),
		float(values[2]),
		float(values[3]),
	)
	var to_display := Vector2(root.size) / screen.size
	return Rect2(rect.position * to_display, rect.size * to_display)


func _send_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(bool(result.get("ok", false)), "%s：%s" % [message, result])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s（actual=%s expected=%s）" % [message, actual, expected])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
