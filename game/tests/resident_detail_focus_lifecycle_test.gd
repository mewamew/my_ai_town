extends SceneTree


const SCREEN_SCENE := preload("res://ui/resident_detail/ResidentDetailScreen.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var screen := SCREEN_SCENE.instantiate() as ResidentDetailScreen
	get_root().add_child(screen)
	await process_frame

	var first := _view_model(1, "memories")
	_expect(screen.apply_view_model(first), "第一份 ViewModel 应用失败")
	await process_frame
	await process_frame

	var rows := screen.get("_row_controls") as Array
	_expect(rows.size() == 2, "记忆页应创建两条可聚焦内容行")
	var first_row := rows[0] as Control
	first_row.grab_focus()
	_expect(
		str(screen.call("_focused_semantic")) == "row:0",
		"内容行焦点应能记录语义位置",
	)

	# TextEdit 是合法的页面焦点，但不是 Button；它不能传给
	# Array[Button].find()。
	screen.call("_open_memory_change_dialog", "edit")
	await process_frame
	var memory_input := screen.get("_memory_operation_input") as TextEdit
	memory_input.grab_focus()
	_expect(
		str(screen.call("_focused_semantic")) == "",
		"非 Button 焦点不应触发筛选按钮数组的类型错误",
	)
	screen.call("_move_focus", 1)

	# 把一个已移出场景树的控件混入焦点链，邻居重建应安全剔除它。
	var stale_control := Control.new()
	var focus_controls := screen.get("_focus_controls") as Array
	focus_controls.append(stale_control)
	var expected_focus_count := focus_controls.size() - 1
	stale_control.queue_free()
	await process_frame
	screen.call("_apply_focus_neighbors")
	_expect(
		(screen.get("_focus_controls") as Array).size() == expected_focus_count,
		"焦点链不应保留已释放控件",
	)

	# 旧的延迟恢复请求不能越过新的 ViewModel 更新，恢复已经被重建的旧行。
	var current_row := (screen.get("_row_controls") as Array)[0] as Control
	current_row.grab_focus()
	screen.call("_queue_semantic_focus_restore", "row:0")
	memory_input.release_focus()
	var second := _view_model(2, "status")
	_expect(screen.apply_view_model(second), "第二份 ViewModel 应用失败")
	await process_frame
	await process_frame
	_expect(
		screen.get_viewport().gui_get_focus_owner() != current_row,
		"新 ViewModel 后不应恢复已退役的旧内容行",
	)

	print("RESIDENT_DETAIL_FOCUS_LIFECYCLE_PASS")
	screen.queue_free()
	await process_frame
	quit(0)


func _view_model(revision: int, selected_tab: String) -> Dictionary:
	var actions := {}
	for action_key: String in [
		"close",
		"selectStatus",
		"selectRelationships",
		"selectMemories",
		"refresh",
		"retry",
	]:
		actions[action_key] = {
			"intent": "resident_detail.%s" % action_key,
			"enabled": true,
			"disabledReason": "",
			"payload": {},
		}
	actions["close"]["intent"] = "resident_detail.close"
	actions["selectStatus"]["intent"] = "resident_detail.select_tab"
	actions["selectRelationships"]["intent"] = "resident_detail.select_tab"
	actions["selectMemories"]["intent"] = "resident_detail.select_tab"
	actions["refresh"]["intent"] = "resident_detail.refresh"
	actions["retry"]["intent"] = "resident_detail.retry"
	return {
		"scope": "resident_detail",
		"status": "ready",
		"revision": revision,
		"operation": {"status": "idle", "requestId": ""},
		"error": null,
		"data": {
			"capabilityMode": "formal",
			"source": "test",
			"formalReady": true,
			"contractVersion": "1",
			"resident": {
				"residentId": "resident-focus-test",
				"displayName": "焦点测试居民",
				"occupationLabel": "记录员",
				"currentPlaceLabel": "测试室",
			},
			"context": {},
			"selectedTab": selected_tab,
			"tabs": [
				{"id": "status", "label": "状态", "availability": "ready"},
				{"id": "relationships", "label": "关系", "availability": "ready"},
				{"id": "memories", "label": "记忆", "availability": "ready"},
			],
			"content": {
				"availability": "ready",
				"items": [
					{
						"memoryId": "memory-focus-0",
						"kindLabel": "经历",
						"title": "第一条记忆",
						"summary": "第一条公开摘要。",
					},
					{
						"memoryId": "memory-focus-1",
						"kindLabel": "经历",
						"title": "第二条记忆",
						"summary": "第二条公开摘要。",
					},
				],
				"statusRows": [],
			},
			"freshness": {"updatedLabel": "刚刚", "state": "fresh"},
			"privacy": {
				"publicSummaryOnly": true,
				"sanitizedUpstream": true,
				"containsAgentPrivateText": false,
			},
		},
		"actions": actions,
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
