extends "res://tests/support/TownWorldTestCase.gd"

class AvatarPerceptionWorld:
	extends RefCounted

	var revision := 2

	func get_world_revision() -> int:
		return revision

	func get_player_avatar_state() -> Dictionary:
		return {
			"residentId": "avatar",
			"name": "旅行者",
			"currentPlace": "中心广场",
			"spaceId": "town_outdoor",
			"regionId": "town_center",
			"position": Vector2.ZERO,
			"nearby": [],
		}
## UI 适配与导航 合并套件。
##
## 由以下测试合并而来，断言逐条保留：
## - town_ui_runtime_host_navigation_test.gd
## - formal_ui_runtime_contract_test.gd
## - game_flow_resident_model_assignment_route_test.gd
## - town_session_production_composition_test.gd
## - town_hud_pause_clock_test.gd

class AdapterHarness extends Node:
	const TOWN_UI_ADAPTER_SCRIPT := preload(
		"res://world/presentation/ui/TownUiAdapter.gd"
	)

	signal view_model_changed(scope: String, view_model: Dictionary)
	signal operation_completed(scope: String, operation: Dictionary)

	var view_models: Dictionary = {}
	var dispatches: Array[Dictionary] = []
	var page_contexts: Array[Dictionary] = []
	var custom_resident_creator_service: RefCounted
	var fail_next_lifecycle_pause := false
	var fail_next_lifecycle_resume := false
	var fail_next_resident_view_begin := false
	var fail_next_inner_observation_exit := false
	var resident_view_phase := "running"
	var resident_view_begin_count := 0
	var world_menu_host: Node

	func _init() -> void:
		view_models = {
			"session": _view_model("session", {
				"source": "runtime",
				"capabilityMode": "formal",
				"formalReady": true,
			}),
			"town_hud": _view_model("town_hud", _hud_data(), _hud_actions()),
			"announcements": _announcements_view_model(),
			"conversation": _conversation_view_model(""),
			"resident_action_menu": _resident_action_view_model(),
			"inner_observation": _inner_observation_view_model(),
			"resident_overview": _resident_overview_view_model(),
			"provider_settings": _provider_settings_view_model(),
			"audio_display_settings": _audio_display_settings_view_model(),
			"weather_control": _weather_view_model(),
			"town_log": _town_log_view_model(),
			"place_focus": _place_focus_view_model(),
			"indoor": _indoor_view_model(false),
			"wardrobe": _wardrobe_view_model(),
		}
		view_models["avatar"] = _view_model("avatar", {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"mode": "observer",
		})
		for scope: String in [
			"lifecycle",
			"environment",
			"save",
		]:
			view_models[scope] = _view_model(scope, {
				"source": "runtime",
				"capabilityMode": "formal",
				"formalReady": true,
			})
		var contract_adapter := TOWN_UI_ADAPTER_SCRIPT.new()
		view_models["resident_editor"] = contract_adapter.call(
			"get_view_model",
			"resident_editor",
		) as Dictionary
		view_models["custom_resident_creator"] = _resident_profile_editor_view_model()
		contract_adapter.free()

	func get_view_model(scope: String) -> Dictionary:
		if scope == "custom_resident_creator" and custom_resident_creator_service != null:
			return custom_resident_creator_service.call("get_view_model") as Dictionary
		return (view_models.get(scope, _view_model(scope, {})) as Dictionary).duplicate(true)

	func attach_world_resident_action_menu(
		menu: Control,
		_context: Dictionary,
	) -> Dictionary:
		if menu == null or world_menu_host == null:
			return {
				"ok": false,
				"errorCode": "RESIDENT_WORLD_MENU_TARGET_UNAVAILABLE",
				"retryable": false,
			}
		world_menu_host.add_child(menu)
		menu.position = Vector2.ZERO
		return {"ok": true, "errorCode": "", "retryable": false}

	func dispatch(intent: String, payload: Dictionary = {}) -> Dictionary:
		dispatches.append({
			"intent": intent,
			"payload": payload.duplicate(true),
		})
		if intent == "lifecycle.pause" and fail_next_lifecycle_pause:
			fail_next_lifecycle_pause = false
			return {
				"ok": false,
				"errorCode": "TEST_LIFECYCLE_PAUSE_FAILED",
				"retryable": true,
			}
		if intent == "lifecycle.resume" and fail_next_lifecycle_resume:
			fail_next_lifecycle_resume = false
			return {
				"ok": false,
				"errorCode": "TEST_LIFECYCLE_RESUME_FAILED",
				"retryable": true,
			}
		if (
			intent == "inner_observation.exit"
			and fail_next_inner_observation_exit
		):
			fail_next_inner_observation_exit = false
			return {
				"ok": false,
				"errorCode": "TEST_INNER_OBSERVATION_EXIT_REJECTED",
				"retryable": true,
			}
		if (
			intent.begins_with("resident_profile_editor.")
			and custom_resident_creator_service != null
		):
			return custom_resident_creator_service.call(
				"dispatch",
				intent,
				payload,
			) as Dictionary
		if intent == "resident_overview.update_profile":
			_apply_resident_profile_update(payload)
		if intent == "announcements.composer.open":
			var announcements := (
				view_models.get("announcements", {}) as Dictionary
			).duplicate(true)
			var announcement_data := (
				announcements.get("data", {}) as Dictionary
			)
			var announcement_panel := (
				announcement_data.get("panel", {}) as Dictionary
			)
			var composer := (
				announcement_data.get("composer", {}) as Dictionary
			)
			announcement_panel["mode"] = "compose"
			composer["open"] = true
			composer["inputFocused"] = true
			announcement_data["panel"] = announcement_panel
			announcement_data["composer"] = composer
			announcements["data"] = announcement_data
			announcements["revision"] = (
				int(announcements.get("revision", 0)) + 1
			)
			view_models["announcements"] = announcements
			view_model_changed.emit(
				"announcements",
				announcements.duplicate(true),
			)
		if intent == "announcements.draft.update":
			var announcements := (
				view_models.get("announcements", {}) as Dictionary
			).duplicate(true)
			var loading := announcements.duplicate(true)
			loading["revision"] = int(loading.get("revision", 0)) + 1
			loading["operation"] = {
				"status": "loading",
				"requestId": "announcement-draft-loading",
				"intent": intent,
			}
			view_model_changed.emit("announcements", loading)
			var announcement_data := (
				announcements.get("data", {}) as Dictionary
			)
			var composer := (
				announcement_data.get("composer", {}) as Dictionary
			)
			var draft_text := String(payload.get("text", ""))
			composer["draftText"] = draft_text
			composer["characterCount"] = draft_text.length()
			composer["remainingCount"] = 140 - draft_text.length()
			announcement_data["composer"] = composer
			announcements["data"] = announcement_data
			announcements["revision"] = int(loading.get("revision", 0)) + 1
			view_models["announcements"] = announcements
			view_model_changed.emit(
				"announcements",
				announcements.duplicate(true),
			)
		if intent == "announcements.panel.close":
			var announcements := (
				view_models.get("announcements", {}) as Dictionary
			).duplicate(true)
			var announcement_data := (
				announcements.get("data", {}) as Dictionary
			)
			var composer := (
				announcement_data.get("composer", {}) as Dictionary
			)
			if String(composer.get("draftText", "")).is_empty():
				var announcement_panel := (
					announcement_data.get("panel", {}) as Dictionary
				)
				announcement_panel["open"] = false
				announcement_data["panel"] = announcement_panel
			else:
				announcement_data["dialog"] = {"open": true}
			announcements["data"] = announcement_data
			announcements["revision"] = (
				int(announcements.get("revision", 0)) + 1
			)
			view_models["announcements"] = announcements
			view_model_changed.emit(
				"announcements",
				announcements.duplicate(true),
			)
		if intent == "town_log.close":
			var town_log := (
				view_models.get("town_log", {}) as Dictionary
			).duplicate(true)
			var town_log_data := town_log.get("data", {}) as Dictionary
			var panel := town_log_data.get("panel", {}) as Dictionary
			panel["open"] = false
			town_log_data["panel"] = panel
			town_log["data"] = town_log_data
			town_log["revision"] = int(town_log.get("revision", 0)) + 1
			view_models["town_log"] = town_log
			view_model_changed.emit("town_log", town_log.duplicate(true))
		return {"ok": true, "errorCode": "", "retryable": false}

	func bind_custom_resident_creator_service(service: RefCounted) -> Dictionary:
		if custom_resident_creator_service != null:
			_disconnect_custom_resident_creator_service()
		custom_resident_creator_service = service
		if custom_resident_creator_service != null:
			custom_resident_creator_service.connect(
				"view_model_changed",
				Callable(self, "_on_custom_resident_creator_view_model_changed"),
			)
			custom_resident_creator_service.connect(
				"operation_completed",
				Callable(self, "_on_custom_resident_creator_operation_completed"),
			)
		return {"ok": true, "errorCode": "", "retryable": false}

	func set_custom_resident_creator_route_capabilities(
		_capabilities: Dictionary,
	) -> Dictionary:
		return {"ok": true, "errorCode": "", "retryable": false}

	func begin_resident_view() -> Dictionary:
		resident_view_begin_count += 1
		if fail_next_resident_view_begin:
			fail_next_resident_view_begin = false
			return {
				"ok": false,
				"errorCode": "TEST_RESIDENT_VIEW_BEGIN_FAILED",
				"retryable": true,
			}
		resident_view_phase = "resident_view"
		return {"ok": true, "errorCode": "", "retryable": false}

	func transition_resident_view_to_inner_observation() -> Dictionary:
		if resident_view_phase != "resident_view":
			return {
				"ok": false,
				"errorCode": "RESIDENT_VIEW_NOT_ACTIVE",
				"retryable": false,
			}
		resident_view_phase = "inner_observation"
		return {"ok": true, "errorCode": "", "retryable": false}

	func transition_inner_observation_to_resident_view() -> Dictionary:
		resident_view_phase = "resident_view"
		return {"ok": true, "errorCode": "", "retryable": false}

	func end_resident_view() -> Dictionary:
		resident_view_phase = "running"
		return {"ok": true, "errorCode": "", "retryable": false}

	func _disconnect_custom_resident_creator_service() -> void:
		var view_callback := Callable(
			self,
			"_on_custom_resident_creator_view_model_changed",
		)
		if custom_resident_creator_service.is_connected(
			"view_model_changed",
			view_callback,
		):
			custom_resident_creator_service.disconnect(
				"view_model_changed",
				view_callback,
			)
		var operation_callback := Callable(
			self,
			"_on_custom_resident_creator_operation_completed",
		)
		if custom_resident_creator_service.is_connected(
			"operation_completed",
			operation_callback,
		):
			custom_resident_creator_service.disconnect(
				"operation_completed",
				operation_callback,
			)

	func _on_custom_resident_creator_view_model_changed(
		scope: String,
		view_model: Dictionary,
	) -> void:
		view_model_changed.emit(scope, view_model)

	func _on_custom_resident_creator_operation_completed(
		scope: String,
		operation: Dictionary,
	) -> void:
		operation_completed.emit(scope, operation)

	func _apply_resident_profile_update(payload: Dictionary) -> void:
		var overview := (
			view_models.get("resident_overview", {}) as Dictionary
		).duplicate(true)
		var data := (overview.get("data", {}) as Dictionary).duplicate(true)
		var residents := (data.get("residents", []) as Array).duplicate(true)
		var profile := payload.get("profile", {}) as Dictionary
		var attributes := profile.get("attributes", {}) as Dictionary
		for index in residents.size():
			var resident := (residents[index] as Dictionary).duplicate(true)
			if (
				String(resident.get("residentId", ""))
				!= String(payload.get("residentId", ""))
			):
				continue
			resident["homeLabel"] = String(profile.get("home", ""))
			resident["occupationLabel"] = String(profile.get("job", ""))
			resident["workplaceLabel"] = String(profile.get("workplace", ""))
			resident["genderLabel"] = String(
				attributes.get("gender", resident.get("genderLabel", ""))
			)
			resident["age"] = int(attributes.get("age", resident.get("age", 0)))
			for field in ["desire", "personality", "speech"]:
				resident[field] = String(
					attributes.get(field, resident.get(field, ""))
				)
			residents[index] = resident
			break
		data["residents"] = residents
		overview["data"] = data
		view_models["resident_overview"] = overview

	func set_page_context(scope: String, context: Dictionary) -> Dictionary:
		page_contexts.append({
			"scope": scope,
			"context": context.duplicate(true),
		})
		return {"ok": true, "errorCode": "", "retryable": false}

	func publish(scope: String, data: Dictionary) -> void:
		var next_revision := int(
			(view_models.get(scope, {}) as Dictionary).get("revision", 0)
		) + 1
		var actions := (
			(
				_spectator_actions()
				if String(data.get("displayMode", "")) == "spectator"
				else _conversation_actions(
					not String(data.get("conversationId", "")).is_empty()
				)
			)
			if scope == "conversation"
			else (
				(view_models.get(scope, {}) as Dictionary).get(
					"actions",
					{},
				) as Dictionary
			).duplicate(true)
		)
		var next := _view_model(scope, data, actions, next_revision)
		view_models[scope] = next
		view_model_changed.emit(scope, next.duplicate(true))

	func emit_view_model(scope: String, view_model: Dictionary) -> void:
		view_model_changed.emit(scope, view_model.duplicate(true))

	func emit_operation(
		scope: String,
		intent: String,
		status: String,
	) -> void:
		operation_completed.emit(scope, {
			"requestId": "navigation-%d" % dispatches.size(),
			"intent": intent,
			"status": status,
			"errorCode": "" if status == "success" else "OPERATION_REJECTED",
		})

	func _view_model(
		scope: String,
		data: Dictionary,
		actions: Dictionary = {},
		revision: int = 1,
	) -> Dictionary:
		return {
			"scope": scope,
			"status": "ready",
			"revision": revision,
			"source": String(data.get("source", "")),
			"capabilityMode": String(data.get("capabilityMode", "")),
			"formalReady": bool(data.get("formalReady", false)),
				"data": data.duplicate(true),
				"actions": actions.duplicate(true),
				"operation": {"status": "idle", "requestId": ""},
				"error": null,
			}

	func _action(
		intent: String,
		enabled: bool = true,
		payload: Dictionary = {},
	) -> Dictionary:
		return {
			"intent": intent,
			"enabled": enabled,
			"disabledReason": "" if enabled else "ACTION_DISABLED",
			"payload": payload.duplicate(true),
		}

	func _hud_data() -> Dictionary:
		return {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"timeWeather": {"day": 2, "clock": "10:30", "weatherId": "sunny"},
			"toolbar": {"items": [
				{"id": "weather_control", "toolId": "weather_control", "actionKey": "openWeather"},
				{"id": "town_log", "toolId": "town_log", "actionKey": "openTownLog"},
				{"id": "avatar", "toolId": "avatar", "actionKey": "toggleAvatar"},
				{"id": "more", "toolId": "more", "actionKey": "openMore"},
			]},
			"camera": {"mode": "free", "followTargetId": "resident-lin"},
			"pausePrompt": {"visible": false, "label": ""},
			"residentOverlays": {"items": [], "aggregateCount": 0},
			"residentDirectory": {
				"available": true,
				"totalCount": 2,
				"visibleBudget": 6,
				"selectedResidentId": "resident-hanako",
				"items": [
					{
						"residentId": "resident-hanako",
						"residentName": "花子",
						"behaviorLabel": "整理花房",
						"locationLabel": "花房咖啡馆",
					},
					{
						"residentId": "resident-lin",
						"residentName": "林岚",
						"behaviorLabel": "查看周围",
						"locationLabel": "中央广场",
					},
				],
			},
			"mapInteraction": {"promptLabel": "中央广场"},
			"indoorMarkers": {"visible": false, "residentCount": 0},
			"eventOverlay": {"visible": true, "items": [{
				"announcementId": "announcement-1",
				"title": "广场公告",
			}]},
			"density": {"mode": "near"},
		}

	func _hud_actions() -> Dictionary:
		return {
			"openWeather": _action("town_hud.open_weather"),
			"openTownLog": _action("town_hud.open_town_log"),
			"openResidentManagement": _action("town_hud.open_resident_management"),
			"toggleAvatar": _action("town_hud.toggle_avatar"),
			"openMore": _action("town_hud.open_more"),
			"weatherChange": _action("town_hud.open_weather", false),
			"openEvent": _action("town_hud.open_event"),
			"focusResident": _action("avatar.focus_target"),
			"openMapTarget": _action("town_hud.open_map_target", false),
			"openIndoorTarget": _action("town_hud.open_indoor", false),
			"pause": _action("lifecycle.pause"),
			"resume": _action("lifecycle.resume", false),
			"timeSpeed1": _action("town_hud.set_time_speed", true, {"multiplier": 1}),
			"timeSpeed2": _action("town_hud.set_time_speed", true, {"multiplier": 2}),
			"timeSpeed3": _action("town_hud.set_time_speed", true, {"multiplier": 3}),
			"selectTool": _action("town_hud.select_tool"),
			"cameraZoomIn": _action("town_hud.camera_zoom_in", false),
			"cameraZoomOut": _action("town_hud.camera_zoom_out", false),
			"cameraReset": _action("town_hud.camera_reset", false),
			"cameraFollow": _action("town_hud.camera_follow"),
			"cameraUnfollow": _action("town_hud.camera_unfollow"),
		}

	func _announcements_view_model() -> Dictionary:
		var actions := {}
		var intents := {
			"openComposer": "announcements.composer.open",
			"updateDraft": "announcements.draft.update",
			"publish": "announcements.publish",
			"requestClose": "announcements.panel.close",
			"continueEditing": "announcements.draft.continue",
			"discardDraft": "announcements.draft.discard",
			"retry": "announcements.retry",
			"dismissFeedback": "announcements.feedback.dismiss",
		}
		for key: String in intents:
			actions[key] = _action(String(intents[key]))
		return _view_model("announcements", {
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": true,
			"panel": {
				"open": true,
				"mode": "browse",
				"title": "公告栏",
				"worldContinues": true,
			},
			"items": [],
			"emptyState": {"title": "暂无公告", "message": ""},
			"composer": {
				"open": false,
				"draftText": "",
				"characterCount": 0,
				"characterLimit": 140,
				"remainingCount": 140,
				"validationCode": "",
				"inputFocused": false,
				"softKeyboardVisible": false,
				"keyboardSubmitBehavior": "dismiss_only",
			},
			"dialog": {},
			"feedback": {},
		}, actions)

	func _conversation_view_model(conversation_id: String) -> Dictionary:
		return _view_model("conversation", {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"displayMode": "player",
			"conversationId": conversation_id,
			"residentId": "resident-lin",
			"residentName": "林岚",
			"messages": [],
			"canAttachPhoto": false,
		}, _conversation_actions(not conversation_id.is_empty()))

	func _conversation_actions(active: bool) -> Dictionary:
		return {
			"start": _action("conversation.start", not active),
			"reply": _action("conversation.reply", active),
			"end": _action("conversation.end", active),
			"reject": _action("conversation.reject", active),
			"retry": _action("conversation.retry", false),
		}

	func _spectator_actions() -> Dictionary:
		return {
			"selectSpectatorConversation": _action(
				"conversation.spectator.select"
			),
			"closeSpectator": _action("conversation.spectator.close"),
			"retry": _action("conversation.spectator.retry", false),
		}

	func prepare_missing_spectator_contract() -> void:
		var current := view_models.get("conversation", {}) as Dictionary
		view_models["conversation"] = _view_model("conversation", {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"displayMode": "spectator",
			"conversationId": "",
			"residentId": "",
			"residentName": "",
			"messages": [],
			"canAttachPhoto": false,
		}, _spectator_actions(), int(current.get("revision", 0)) + 1)

	func spectator_data() -> Dictionary:
		return {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"displayMode": "spectator",
			"conversationId": "conversation-spectator-1",
			"residentId": "resident-lin",
			"residentName": "林岚",
			"messages": [{
				"turnId": 1,
				"speakerId": "resident-lin",
				"speaker": "林岚",
				"say": "今天的广场很热闹。",
				"narration": "林岚朝窗外看了一眼。",
				"expressionId": "calm",
				"photos": [],
			}],
			"spectator": {
				"panelOpen": true,
				"activeConversations": [{
					"conversationId": "conversation-spectator-1",
					"participantNames": ["林岚", "唐小满"],
					"entryBubble": {
						"visible": false,
						"label": "旁观对话",
						"screenAnchor": {"x": 344, "y": 560},
					},
				}],
				"selectedConversation": {
					"conversationId": "conversation-spectator-1",
					"placeId": "place-cafe",
					"placeLabel": "咖啡馆",
					"participants": [
						{
							"residentId": "resident-lin",
							"residentName": "林岚",
							"portraitRef": "",
							"expressionId": "calm",
						},
						{
							"residentId": "resident-tang",
							"residentName": "唐小满",
							"portraitRef": "",
							"expressionId": "happy",
						},
					],
				},
				"observer": {
					"canSpeak": false,
					"disabledReason": "SPECTATOR_READ_ONLY",
				},
				"spectatorNotice": "你正在旁观，无法加入对话",
				"autoFollowLatest": false,
				"newConfirmedTurnCount": 0,
			},
		}

	func _provider_settings_view_model() -> Dictionary:
		return _view_model("provider_settings", {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"pageTitle": "模型设置",
			"selectedProviderId": "",
			"formalStatusLabel": "真实 Provider 已配置",
			"providers": [],
			"summary": {
				"availableProviderCount": 0,
				"enabledModelCount": 0,
			},
		}, {
			"back": _action("provider_settings.back"),
		})

	func _audio_display_settings_view_model() -> Dictionary:
		var audio := {
			"masterPercent": 100,
			"musicPercent": 80,
			"ambiencePercent": 80,
			"sfxPercent": 80,
			"uiPercent": 80,
			"muted": false,
		}
		var display := {
			"resolutionId": "1920x1080",
			"windowModeId": "windowed",
			"uiScalePercent": 100,
			"reducedFlashingEnabled": false,
		}
		var settings_data := {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"audio": audio.duplicate(true),
			"display": display.duplicate(true),
			"confirmed": {"audio": audio.duplicate(true), "display": display.duplicate(true)},
			"defaults": {"audio": audio.duplicate(true), "display": display.duplicate(true)},
			"dirty": false,
			"dirtySections": [],
			"uiScaleCapability": {
				"formalReady": true,
				"effectivePercent": 100,
				"supportedPercents": [100],
				"requiredConsumers": ["responsive_layout"],
				"readyConsumers": ["responsive_layout"],
				"disabledReason": "UI_SCALE_AUTOMATIC_BY_LAYOUT_POLICY",
			},
			"confirmation": {
				"active": false,
				"deadlineMsec": 0,
				"remainingSeconds": 0,
			},
			"storage": {"status": "ready", "errorCode": "", "message": ""},
			"feedback": {"kind": "", "code": "", "message": ""},
			"options": {
				"resolutions": [],
				"windowModes": [],
				"uiScalePercents": [100],
			},
		}
		var actions := {}
		for action_name: String in [
			"setAudioValue",
			"toggleMute",
			"selectResolution",
			"selectWindowMode",
			"selectUiScale",
			"toggleReducedFlashing",
			"retry",
			"back",
		]:
			actions[action_name] = _action(
				"audio_display_settings.%s" % action_name,
				true,
			)
		return _view_model("audio_display_settings", settings_data, actions)

	func _resident_action_view_model() -> Dictionary:
		var resident_id := "resident-lin"
		var actions := {}
		var item_actions := {
			"follow": "resident.follow",
			"openStatus": "resident.detail.open",
			"openRelationship": "resident.detail.open",
			"openMemory": "resident.detail.open",
			"openInner": "resident.inner_observation.open",
			"killResident": "resident.death.confirm",
			"close": "resident.action_menu.close",
		}
		for key: String in item_actions:
			actions[key] = _action(String(item_actions[key]))
			if key != "close":
				(actions[key] as Dictionary)["payload"] = {
					"residentId": resident_id,
				}
		(actions["openStatus"] as Dictionary)["payload"]["tab"] = "status"
		(actions["openRelationship"] as Dictionary)["payload"]["tab"] = (
			"relationship"
		)
		(actions["openMemory"] as Dictionary)["payload"]["tab"] = "memory"
		var menu_items: Array[Dictionary] = []
		for item_index in 5:
			var item: Array = [
				["follow", "跟随", "follow", "follow_camera"],
				["status", "状态", "openStatus", "resident_status"],
				[
					"relationship",
					"关系",
					"openRelationship",
					"resident_relationship",
				],
				["memory", "记忆", "openMemory", "resident_memory"],
				["inner", "内心", "openInner", "inner_observation"],
			][item_index]
			menu_items.append({
				"id": item[0],
				"label": item[1],
				"actionKey": item[2],
				"iconKey": item[3],
				"semanticOrder": item_index,
			})
		return _view_model("resident_action_menu", {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"phase": "menu",
			"world": {"paused": false, "pauseLabel": ""},
			"placement": {
				"viewport": {"x": 0, "y": 0, "width": 1280, "height": 720},
				"screenAnchor": {"x": 640, "y": 400},
				"focusRect": {"x": 600, "y": 340, "width": 80, "height": 120},
				"safeRect": {"x": 24, "y": 24, "width": 1232, "height": 672},
				"closeRect": {"x": 1180, "y": 24, "width": 64, "height": 64},
				"avoidRects": [],
				"preferredArc": "up",
				"pixelGrid": 1,
			},
			"menuItems": menu_items,
			"motion": {"itemStaggerMs": 0, "openingDurationMs": 0},
			"feedback": {},
		}, actions)

	func _inner_observation_view_model() -> Dictionary:
		return _view_model("inner_observation", {
			"source": "town_ui_adapter",
			"capabilityMode": "formal",
			"formalReady": true,
			"visibility": "visible",
			"phase": "ready",
			"pauseState": "running",
			"background": {
				"mode": "live_town_frame",
				"available": true,
				"dimmed": true,
				"focusVisible": true,
			},
			"resident": {
				"residentId": "resident-lin",
				"displayName": "林岚",
				"expressionId": "calm",
				"portrait": {
					"assetPath": "",
					"sourceKind": "placeholder",
					"status": "missing",
					"atlasRegion": {
						"x": 0,
						"y": 0,
						"width": 0,
						"height": 0,
					},
				},
			},
			"content": {
				"contentKind": "resident_current_focus",
				"monologueText": "想看看花圃今天有没有新芽。",
				"reasonText": "",
				"playerStatusText": "",
				"empty": false,
				"fallbackUsed": false,
			},
			"generation": {
				"status": "ready",
				"requestId": "inner-navigation-1",
				"retryable": false,
			},
			"motion": {"reduceMotion": false},
		}, {
			"exit": _action("inner_observation.exit"),
			"retry": _action("inner_observation.retry", false),
		})

	func _weather_view_model() -> Dictionary:
		return _view_model("weather_control", {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"currentWeather": {
				"id": "sunny",
				"label": "晴天",
				"description": "天空晴朗。",
				"iconId": "sunny",
			},
			"weatherOptions": [{
				"id": "sunny",
				"label": "晴天",
				"description": "天空晴朗。",
				"iconId": "sunny",
			}, {
				"id": "rainy",
				"label": "小雨",
				"description": "细雨落在小镇。",
				"iconId": "rainy",
			}],
			"mode": {"id": "observer", "label": "观察模式"},
			"affectedPlaces": [],
			"residents": [],
			"feedback": {},
		}, {
			"weatherChange": _action("environment.weather_change"),
			"switchToOverview": _action("avatar.switch_to_overview", false),
		})

	func _town_log_view_model() -> Dictionary:
		var actions := {}
		var intents := {
			"open": "town_log.open",
			"close": "town_log.close",
			"setFilter": "town_log.set_filter",
			"toggleUnread": "town_log.toggle_unread",
			"selectThread": "town_log.select_thread",
			"backToList": "town_log.back_to_list",
			"loadMore": "town_log.load_more",
			"loadMoreDetail": "town_log.load_more_detail",
			"refreshNewer": "town_log.refresh_newer",
			"retry": "town_log.retry",
		}
		for action_key: String in intents:
			actions[action_key] = _action(
				String(intents[action_key]),
				action_key in ["open", "close", "setFilter", "toggleUnread"],
			)
		return _view_model("town_log", {
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": true,
			"panel": {
				"open": true,
				"presentation": "world_log_table",
				"title": "世界日志",
			},
			"state": "ready",
			"errorCode": "",
			"summary": {
				"attentionUnreadThreadCount": 0,
				"totalUnreadThreadCount": 0,
				"hasNewerThreads": false,
			},
			"entryPoint": {
				"unreadCount": 0,
				"unreadCountLabel": "0",
				"hasUnread": false,
				"hasHot": false,
				"attentionToken": "",
				"recentImportantEntry": null,
			},
			"filters": {
				"residentId": "",
				"kindTag": "",
				"day": 0,
				"unreadOnly": false,
			},
			"filterOptions": {
				"residents": [],
				"kinds": [],
				"days": [],
			},
			"rows": [],
			"selectedThreadId": "",
			"detail": null,
			"detailPaging": {
				"cursor": 0,
				"hasMore": false,
				"isLoading": false,
			},
			"paging": {
				"cursor": {},
				"hasMore": false,
				"isLoading": false,
			},
		}, actions)

	func _indoor_view_model(active: bool) -> Dictionary:
		var actions := {
			"returnOutdoor": _action("indoor.return_outdoor", active),
			"focusTarget": _action("indoor.focus_target", active),
			"activateInteraction": _action("indoor.activate_interaction", false),
			"focusEvent": _action("indoor.focus_event", false),
			"retryLoad": _action("indoor.retry_load", false),
			"dismissFeedback": _action("indoor.dismiss_feedback", false),
		}
		return _view_model("indoor", {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"view": {
				"presentationMode": "interior_overlay",
				"entryReason": "runtime" if active else "outdoors",
				"selectedTargetId": "",
				"promptBudget": 6,
				"reduceMotion": true,
			},
			"location": {
				"spaceId": "indoor_library" if active else "",
				"placeName": "图书馆" if active else "小镇",
				"placeTypeLabel": "室内" if active else "户外",
				"title": "图书馆" if active else "小镇",
				"subtitle": "",
			},
			"sceneLoad": {
				"status": "ready" if active else "idle",
				"progressLabel": "",
				"canRetry": false,
				"failureCode": "",
			},
			"residentTargets": [],
			"propTargets": [],
			"doorTargets": [],
			"interactionPrompts": [],
			"observationFeed": [],
			"eventFocus": {
				"active": false,
				"eventId": "",
				"title": "",
				"summary": "",
				"screenAnchor": {"x": 0, "y": 0, "valid": false},
				"isOnScreen": false,
				"edgeDirection": "",
				"relatedTargetIds": [],
				"attentionToken": "",
				"focusState": "unavailable",
			},
			"feedback": {},
			"outdoorFallback": {
				"visible": false,
				"renderOwner": "place_focus",
				"placeName": "",
				"residentSummaries": [],
				"recentEventSummaries": [],
			},
		}, actions)

	func _place_focus_view_model() -> Dictionary:
		return _view_model("place_focus", {
			"source": "town_ui_adapter",
			"capabilityMode": "formal",
			"formalReady": true,
			"place": {
				"placeName": "图书馆",
				"placeType": "公共建筑",
				"spaceId": "indoor_library",
				"summary": "安静的公共阅览空间。",
				"hasInterior": true,
				"residentCount": 0,
			},
			"residents": [],
			"currentEvents": [],
			"interactables": [],
			"recentLogs": [],
		}, {
			"openResident": _action("place_focus.open_resident", false),
			"openEvent": _action("place_focus.open_event", false),
			"openInteractable": _action("place_focus.open_interactable", false),
			"openLog": _action("place_focus.open_log", false),
			"enterInterior": _action("place_focus.enter_interior", true),
			"retry": _action("place_focus.retry", false),
		})

	func _wardrobe_view_model() -> Dictionary:
		var actions := {}
		var intents := {
			"selectCategory": "wardrobe.select_category",
			"selectItem": "wardrobe.select_item",
			"selectPreset": "wardrobe.select_preset",
			"setPreviewDirection": "wardrobe.set_preview_direction",
			"randomize": "wardrobe.randomize",
			"restore": "wardrobe.restore",
			"apply": "wardrobe.apply",
			"cancel": "wardrobe.cancel",
			"retry": "wardrobe.retry",
		}
		for action_key: String in intents:
			actions[action_key] = _action(
				String(intents[action_key]),
				action_key == "cancel",
			)
		var empty_selection := {
			"head": "",
			"expression": "",
			"top": "",
			"bottom": "",
			"shoes": "",
		}
		var view_model := _view_model("wardrobe", {
			"source": "placeholder",
			"capabilityMode": "placeholder",
			"formalReady": false,
			"target": {"residentId": "", "displayName": "", "appearanceRevision": 0},
			"assetContract": {
				"contractId": "paper-doll-144x192-five-slot",
				"frameWidth": 144,
				"frameHeight": 192,
				"directions": ["down", "right", "up", "left"],
				"editableSlots": ["head", "top", "bottom", "shoes"],
				"passThroughSlots": ["expression"],
				"catalogStatus": "placeholder",
			},
			"activeCategoryId": "preset",
			"preview": {
				"status": "disabled",
				"directionId": "down",
				"poseId": "neutral",
				"frameReady": false,
				"placeholderAssetId": "",
			},
			"confirmedSelection": empty_selection.duplicate(true),
			"draftSelection": empty_selection.duplicate(true),
			"selectionDirty": false,
			"appliedToFormalProfile": false,
			"presets": [],
			"categories": [],
			"items": [],
		}, actions)
		view_model["status"] = "disabled"
		view_model["operation"] = {
			"status": "disabled",
			"requestId": "",
			"intent": "",
		}
		view_model["error"] = {
			"kind": "unavailable",
			"code": "WARDROBE_INTERFACE_MISSING",
			"retryable": false,
			"message": "正式换装接口尚未接入。",
			"details": [],
		}
		return view_model

	func _resident_profile_editor_view_model() -> Dictionary:
		return _view_model("custom_resident_creator", {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"residentId": "resident-lin",
			"draftId": "resident-profile-resident-lin",
			"candidatePoolRevision": 1,
			"draft": {
				"name": "林岚",
				"gender": "女",
				"age": 27,
				"appearanceSelection": {
					"hair": "hair_default",
					"top": "top_default",
					"bottom": "bottom_default",
					"shoes": "shoes_default",
				},
				"desire": "照看小镇里的每一株花",
				"personality": "温和、认真",
				"speech": "说话简洁而友善",
				"occupationId": "occupation:咖啡馆经营者",
				"workplaceId": "花房咖啡馆",
				"ownedPlaceId": "花房咖啡馆",
			},
			"resolvedAppearance": {
				"formalReady": false,
				"displayName": "当前搭配",
				"selection": {},
			},
			"options": {
				"genders": [{"id": "女", "label": "女"}, {"id": "男", "label": "男"}],
				"age": {"min": 1, "max": 120, "step": 1},
				"wardrobe": {
					"entryMode": "route_to_formal_wardrobe",
					"runtimeMode": "resident_2d_rig_v1",
					"slotOrder": ["hair", "top", "bottom", "shoes"],
				},
				"occupations": [{"id": "occupation:咖啡馆经营者", "label": "咖啡馆经营者"}],
				"workplaces": [{"id": "花房咖啡馆", "label": "花房咖啡馆"}],
				"ownedPlaces": [{"id": "花房咖啡馆", "label": "花房咖啡馆"}],
			},
			"validation": {
				"status": "valid",
				"summaryLabel": "资料完整，可以保存",
				"issues": [],
				"fieldIssues": {},
			},
		}, {
			"updateFields": _action("resident_profile_editor.update_fields"),
			"openWardrobe": _action("resident_profile_editor.open_wardrobe", false),
			"applyWardrobeResult": _action("resident_profile_editor.apply_wardrobe_result"),
			"saveExisting": _action("resident_profile_editor.save_existing"),
			"cancel": _action("resident_profile_editor.cancel"),
			"retry": _action("resident_profile_editor.retry", false),
		})

	func _resident_overview_view_model() -> Dictionary:
		var residents := [
			{
				"residentId": "resident-hanako",
				"displayName": "花子",
				"identityStatus": "confirmed",
				"genderLabel": "女",
				"age": 27,
				"appearanceId": "resident_wardrobe_v1:look_00",
				"desire": "让花房每天都有新颜色",
				"personality": "热情、细心",
				"speech": "说话明快，常用花草作比喻",
				"portraitRef": "",
				"homeLabel": "北街一号住宅",
				"occupationLabel": "咖啡店店员",
				"workplaceLabel": "花房咖啡馆",
				"currentPlaceLabel": "花房咖啡馆",
				"currentActionLabel": "整理花房",
				"actionPhaseLabel": "行动中",
				"availabilityLabel": "可跟随",
			},
			{
				"residentId": "resident-lin",
				"displayName": "林岚",
				"identityStatus": "confirmed",
				"genderLabel": "男",
				"age": 32,
				"appearanceId": "resident_wardrobe_v1:look_01",
				"desire": "记录小镇每一种植物",
				"personality": "沉静、可靠",
				"speech": "语速舒缓，表达简洁",
				"portraitRef": "",
				"homeLabel": "北街二号住宅",
				"occupationLabel": "植物学家",
				"workplaceLabel": "社区花园",
				"currentPlaceLabel": "中央广场",
				"currentActionLabel": "查看周围",
				"actionPhaseLabel": "行动中",
				"availabilityLabel": "可跟随",
			},
		]
		return _view_model("resident_overview", {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"residentCount": residents.size(),
			"selectedResidentId": "resident-hanako",
			"residents": residents,
			"options": {
				"homes": [
					{"id": "北街一号住宅", "label": "北街一号住宅"},
					{"id": "北街二号住宅", "label": "北街二号住宅"},
				],
				"occupations": [
					{"id": "咖啡店店员", "label": "咖啡店店员"},
					{"id": "植物学家", "label": "植物学家"},
				],
				"workplaces": [
					{"id": "花房咖啡馆", "label": "花房咖啡馆"},
					{"id": "社区花园", "label": "社区花园"},
				],
			},
		}, {
			"follow": _action("resident_overview.follow"),
			"updateProfile": _action("resident_overview.update_profile"),
		})
class StartupRuntimeHarness:
	extends Node

	func get_startup_result() -> Dictionary:
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
		}
class ProviderHarness:
	extends RefCounted

	var validation_calls := 0
	var fail_on_validation_call := -1

	func get_health_snapshot() -> Dictionary:
		return {
			"ok": true,
			"status": "ready",
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": true,
			"providers": [{
				"providerId": "deepseek",
				"label": "DeepSeek",
				"status": "available",
				"errorCode": "",
				"retryable": false,
			}],
		}

	func list_available_models() -> Array[Dictionary]:
		return [{
			"providerId": "deepseek",
			"modelId": "deepseek-v4-flash",
			"id": "deepseek-v4-flash",
			"label": "DeepSeek V4 Flash",
			"available": true,
			"errorCode": "",
			"retryable": false,
			"capabilities": [],
		}]

	func validate_resident_bindings(bindings: Array) -> Dictionary:
		validation_calls += 1
		if validation_calls == fail_on_validation_call:
			return {
				"ok": false,
				"errorCode": "TEST_STOP_BEFORE_PERSIST",
				"retryable": false,
			}
		if bindings.size() != 15:
			return {
				"ok": false,
				"errorCode": "SESSION_LLM_BINDINGS_INVALID",
				"retryable": false,
			}
		for value: Variant in bindings:
			if not value is Dictionary:
				return {
					"ok": false,
					"errorCode": "SESSION_LLM_BINDINGS_INVALID",
					"retryable": false,
				}
			var binding := (value as Dictionary).get("llmBinding", {}) as Dictionary
			if (
				String(binding.get("mode", "")) != "model"
				or String(binding.get("providerId", "")) != "deepseek"
				or String(binding.get("modelId", "")) != "deepseek-v4-flash"
			):
				return {
					"ok": false,
					"errorCode": "SESSION_LLM_BINDINGS_INVALID",
					"retryable": false,
				}
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"residentCount": 15,
		}
class ProviderSettingsHarness:
	extends RefCounted

	var stop_before_persist := false
	var runtime_configuration_calls := 0

	func runtime_configuration() -> Dictionary:
		runtime_configuration_calls += 1
		if stop_before_persist:
			return {
				"ok": false,
				"errorCode": "TEST_STOP_BEFORE_PERSIST",
				"retryable": false,
			}
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"providerId": "deepseek",
			"modelId": "deepseek-v4-flash",
			"providerConfigs": {},
		}

	func get_view_model(_scope := "provider_settings") -> Dictionary:
		return {
			"scope": "provider_settings",
			"status": "ready",
			"revision": 1,
			"data": {
				"source": "runtime",
				"capabilityMode": "formal",
				"formalReady": true,
			},
			"actions": {},
			"operation": {
				"requestId": "",
				"intent": "",
				"status": "idle",
				"submittedAtMsec": 0,
				"completedAtMsec": 0,
			},
			"error": null,
		}
class ResultCollector:
	extends RefCounted
	var result: Dictionary = {}

	func collect(value: Dictionary) -> void:
		result = value.duplicate(true)


class AgentGatewayPumpSpy:
	extends Node
	var pump_limits: Array[int] = []

	func pump_frame_budgeted(max_requests := 1) -> int:
		pump_limits.append(max_requests)
		return 1

	func pump(max_requests := -1) -> int:
		pump_limits.append(max_requests)
		return 1

const HOST_SCRIPT := preload(
	"res://world/presentation/ui/TownUiRuntimeHost.gd"
)
const AVATAR_HUD_SCENE := preload(
	"res://ui/avatar_mode/runtime/AvatarModeHud.tscn"
)
const RESIDENT_DIRECTORY_DRAWER := preload(
	"res://ui/town/hud/runtime/ResidentDirectoryDrawer.gd"
)
const SYSTEM_FEEDBACK_TOAST_SCENE := preload(
	"res://ui/common/system_feedback/SystemFeedbackToast.tscn"
)
const PROVIDER_SETTINGS_SCREEN_SCENE := preload(
	"res://ui/provider_settings/ProviderSettingsScreen.tscn"
)
const RESIDENT_PROFILE_EDITOR_SERVICE_SCRIPT := preload(
	"res://ui/resident_overview/ResidentProfileEditorService.gd"
)
const AUDIO_DISPLAY_SETTINGS_SERVICE_SCRIPT := preload(
	"res://world/presentation/ui/TownAudioDisplaySettingsService.gd"
)
const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const ProviderSettingsCompositeDesktop := preload(
	"res://ui/provider_settings/composite/ProviderSettingsCompositeDesktop.gd"
)
const ProviderSettingsTheme := preload(
	"res://ui/provider_settings/ProviderSettingsTheme.gd"
)
const REQUIRED_FORMAL_PATHS: Array[String] = [
	"res://ui/startup/StartupScreen.tscn",
	"res://ui/startup/StartupLoadGameScreen.tscn",
	"res://ui/world_intro/WorldIntroScreen.tscn",
	"res://ui/resident_selection/ResidentSelectionScreen.tscn",
	"res://ui/avatar_mode/runtime/AvatarModeHud.tscn",
	"res://ui/pause_menu/PauseMenuNavigationHost.tscn",
	"res://ui/pause_menu/PauseMenuScreen.tscn",
	"res://ui/provider_settings/ProviderSettingsScreen.tscn",
	"res://ui/new_game_overwrite/NewGameOverwriteScreen.tscn",
	"res://ui/settings/AudioDisplaySettingsScreen.tscn",
	"res://ui/custom_resident_creator/CustomResidentCreatorScreen.tscn",
	"res://ui/resident_model_assignment/ResidentModelAssignmentScreen.tscn",
	"res://ui/town/hud/runtime/TownHudOverlay.tscn",
	"res://ui/system_feedback/SystemFeedbackLayer.tscn",
	"res://ui/bulletin_board/BulletinBoardPanel.tscn",
	"res://ui/resident_action_menu/ResidentActionWorldMenu.tscn",
	"res://ui/resident_detail/ResidentDetailScreen.tscn",
	"res://ui/inner_observation/InnerObservationOverlay.tscn",
	"res://ui/place_focus/PlaceFocusPanel.tscn",
	"res://ui/conversation_unified/UnifiedConversationScreen.tscn",
	"res://ui/weather_control/WeatherControlPanel.tscn",
	"res://ui/town_log/TownLogPanel.tscn",
	"res://ui/indoor_overlay/IndoorOverlay.tscn",
	"res://ui/wardrobe/WardrobePage.tscn",
	"res://ui/wardrobe/runtime_approved_v2/WardrobeApprovedV2Runtime.tscn",
	(
		"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
		+ "wardrobe_catalog.json"
	),
	"res://ui/resident_overview/ResidentOverviewScreen.tscn",
	(
		"res://assets/ui/indoor_overlay/runtime_skin_v21/"
		+ "primitives/buttons/"
		+ "indoor_panel_toggle_arrow_right_v21_64x128.png"
	),
]
const FORBIDDEN_LEGACY_RUNTIME_PATHS: Array[String] = [
	"res://ui/chat/MapChatScreen.tscn",
	"res://ui/chat/MapChatScreen.gd",
	"res://ui/conversation_spectator/ConversationSpectatorScreen.tscn",
	"res://ui/conversation_spectator/ConversationSpectatorScreen.gd",
]
const FORMAL_ROUTE_SCENES := {
	"bulletin_board": "res://ui/bulletin_board/BulletinBoardPanel.tscn",
	"resident_action_menu": "res://ui/resident_action_menu/ResidentActionWorldMenu.tscn",
	"resident_detail": "res://ui/resident_detail/ResidentDetailScreen.tscn",
	"inner_observation": "res://ui/inner_observation/InnerObservationOverlay.tscn",
	"place_focus": "res://ui/place_focus/PlaceFocusPanel.tscn",
	"provider_settings": "res://ui/provider_settings/ProviderSettingsScreen.tscn",
	"chat": "res://ui/conversation_unified/UnifiedConversationScreen.tscn",
	"conversation_spectator": "res://ui/conversation_unified/UnifiedConversationScreen.tscn",
	"weather_control": "res://ui/weather_control/WeatherControlPanel.tscn",
	"town_log": "res://ui/town_log/TownLogPanel.tscn",
	"indoor": "res://ui/indoor_overlay/IndoorOverlay.tscn",
	"wardrobe": "res://ui/wardrobe/WardrobePage.tscn",
	"resident_management": "res://ui/resident_overview/ResidentOverviewScreen.tscn",
}
const CUT8_DEPENDENCY_PATHS: Array[String] = [
	"res://assets/fonts/zheng_ge_dian_hei_16/ZhengGeDianHei-16.ttf",
	"res://assets/characters/paper_doll_64/wardrobe_catalog.json",
	"res://characters/paper_doll/PaperDoll64Sprite.gd",
	"res://world/presentation/session/TownNewGameDraft.gd",
	(
		"res://assets/ui/indoor_overlay/runtime_skin_v8/composite/"
		+ "indoor_title_bar_native_v8.png"
	),
]
const SELF_CONTAINED_SCENES: Array[String] = [
	"res://ui/provider_settings/ProviderSettingsScreen.tscn",
	"res://ui/new_game_overwrite/NewGameOverwriteScreen.tscn",
	"res://ui/settings/AudioDisplaySettingsScreen.tscn",
	"res://ui/system_feedback/SystemFeedbackLayer.tscn",
	"res://ui/bulletin_board/BulletinBoardPanel.tscn",
	"res://ui/resident_action_menu/ResidentActionWorldMenu.tscn",
	"res://ui/resident_detail/ResidentDetailScreen.tscn",
	"res://ui/inner_observation/InnerObservationOverlay.tscn",
	"res://ui/place_focus/PlaceFocusPanel.tscn",
	"res://ui/conversation_unified/UnifiedConversationScreen.tscn",
	"res://ui/weather_control/WeatherControlPanel.tscn",
	"res://ui/town_log/TownLogPanel.tscn",
	"res://ui/indoor_overlay/IndoorOverlay.tscn",
]
const SAFE_EMPTY_BOOT_SCENES: Array[String] = [
	"res://ui/resident_action_menu/ResidentActionWorldMenu.tscn",
	"res://ui/resident_selection/ResidentSelectionScreen.tscn",
	"res://ui/custom_resident_creator/CustomResidentCreatorScreen.tscn",
]
const RESIDENT_SELECTION_RUNTIME_ICONS: Array[String] = [
	"ai_spark.png",
	"back_arrow.png",
	"broom.png",
	"coffee_beans.png",
	"delete_check_red_v53.png",
	"empty_box.png",
	"group.png",
	"map_pin.png",
	"overview_book_v49_cropped.png",
	"overview_scroll_thumb_v49_cropped.png",
	"overview_scroll_track_v49_cropped.png",
	"section_leaf.png",
	"selected_leaf.png",
	"town_clock.png",
	"trash.png",
]
const FORBIDDEN_DIRECTORY_NAMES := {
	"candidate": true,
	"candidates": true,
	"font_candidates": true,
	"font_specimen": true,
	"validation": true,
	"preview": true,
	"previews": true,
	"mock": true,
	"evidence": true,
	"preflight": true,
	"tests": true,
	"test": true,
	"test_area": true,
	"runtime_preview": true,
	"runtime_acceptance": true,
	"gallery": true,
	"tools": true,
}
const FORMAL_EXPORT_INCLUDE_FILTERS: Array[String] = [
	"*",
]
const FORMAL_EXPORT_EXCLUDE_FILTERS: Array[String] = []
const FORMAL_RUNTIME_ASSET_PATHS: Array[String] = [
	"res://assets/fonts/zheng_ge_dian_hei_16/ZhengGeDianHei-16.ttf",
	"res://assets/ui/startup/final/load_game/load_game_open_paper_1672x941.png",
	"res://assets/ui/startup/runtime/startup_save_summary_plaque_v2_exact_460x63.png",
	"res://assets/ui/resident_overview/runtime/resident_overview_editable_shell_1920x1080.png",
	"res://assets/ui/resident_detail/runtime/resident_detail_background.png",
	"res://assets/ui/resident_detail/runtime/close_x_icon.png",
	"res://assets/ui/resident_detail/runtime/refresh_button_surface.png",
	"res://assets/ui/indoor_overlay/runtime/indoor_observation_panel_640x960.png",
	"res://assets/ui/town/hud/runtime/place_directory/place_directory_drawer_rgba.png",
	"res://assets/ui/common/system_feedback/runtime_panel_v3/system_feedback_panel_base_1024x512.png",
	"res://assets/ui/common/system_feedback/runtime_strip_v3/system_feedback_strip_base_1024x96.png",
	"res://assets/ui/common/system_feedback/runtime_toast_v3/system_feedback_toast_base_1024x256.png",
]
const FORMAL_SOURCE_MARKERS := {
	"res://ui/common/AiTownUiTheme.gd": [
		(
			"const REVISION := "
			+ "\"ui.common.system-feedback.style-revision-v2\""
		),
		"const FORMAL_READY := true",
	],
	(
		"res://assets/ui/provider_settings/composite_reference/"
		+ "provider_settings_page_composite_user_reference_v1_contract.json"
	): [
		(
			"\"typographyRevision\": "
			+ "\"provider-settings.composite-typography.v2\""
		),
	],
	"res://ui/place_focus/runtime/PlaceFocusPanel.gd": [
		"\"runtimeStatus\": \"formal_approved\"",
	],
	"res://ui/indoor_overlay/IndoorOverlay.gd": [
		"\"runtimeStatus\": \"formal_approved\"",
		"\"formal_status\"",
	],
}
const FORBIDDEN_FORMAL_SOURCE_TOKENS: Array[String] = [
	"runtimeCandidate",
	"pending_user_visual_review",
	"style-revision-candidate",
	"composite-typography.candidate",
	"page_specific_runtime_candidate_raster",
	"paired-candidate",
]
const RESIDENT_SELECTION_SCENE := preload(
	"res://ui/resident_selection/ResidentSelectionScreen.tscn"
)
const CUSTOM_RESIDENT_LIBRARY_TEST_PATH := (
	"user://tests/town_custom_resident_library/model-route.json"
)
const INTERNAL_CATALOG := preload("res://world/presentation/session/TownInternalPlaytestCatalog.gd")
const RESIDENT_CATALOG := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)
const COMPILER := preload("res://world/presentation/session/TownNewGameOpeningCompiler.gd")
const CUSTOM_POOL := preload(
	"res://world/presentation/session/TownCustomResidentCandidatePool.gd"
)
const CUSTOM_CREATOR := preload(
	"res://world/presentation/session/TownCustomResidentCreatorService.gd"
)
const BOOTSTRAP := preload("res://world/presentation/session/TownSessionBootstrap.gd")
const PROVIDER_SERVICE := preload("res://world/integration/TownAgentProviderService.gd")
const GATEWAY := preload("res://world/integration/TownWorldAgentGateway.gd")
const TOWN_RUNTIME_SCENE := preload("res://world/presentation/town_runtime/TownRuntime.tscn")
const AVATAR_HUD_SCENE_SESSION_PRODUCTION_COMPOSITION := preload("res://ui/avatar_mode/runtime/AvatarModeHud.tscn")
const PAUSE_HOST_SCENE := preload("res://ui/pause_menu/PauseMenuNavigationHost.tscn")
const TOWN_HUD_SCENE := preload("res://ui/town/hud/runtime/TownHudOverlay.tscn")
const AGENT_CONTRACT := preload("res://agent/AgentContract.gd")
const TEST_KEYBOARD_DEVICE_ID := 16
const ADAPTER := preload("res://world/presentation/ui/TownUiAdapter.gd")
const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")
const MOBILE_TOUCH_SCROLL_ROUTER := preload(
	"res://ui/mobile/MobileTouchScrollRouter.gd"
)
const MOBILE_TEXT_INPUT_POLICY := preload(
	"res://ui/mobile/MobileTextInputPolicy.gd"
)
const BULLETIN_HISTORY_RAIL := preload(
	"res://ui/bulletin_board/BulletinBoardHistoryRail.gd"
)
const RESIDENT_DETAIL_CLOSE_BUTTON_SCENE := preload(
	"res://ui/resident_detail/components/ResidentDetailCloseButton.tscn"
)
const RESIDENT_MODEL_ASSIGNMENT_SIMPLIFIED := preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentSimplifiedDesktop.gd"
)
const VIRTUAL_JOYSTICK := preload("res://ui/mobile/VirtualJoystick.gd")
const TOUCH_CAMERA_GESTURE := preload("res://ui/mobile/TouchCameraGesture.gd")
const MOBILE_MOVEMENT_INPUT := preload("res://ui/mobile/MobileMovementInput.gd")

var _adapter: AdapterHarness
var _host: Control
var _avatar_hud: Control
var _pause_request_count := 0


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	await _scenario_dynamic_feedback_text_is_complete()
	await _scenario_mobile_platform_foundation()
	await _scenario_ui_runtime_host_navigation()
	await _scenario_formal_ui_runtime_contract()
	await _scenario_game_flow_resident_model_assignment_route()
	await _scenario_session_production_composition()
	await _scenario_hud_pause_clock()
	_scenario_avatar_perception_only_refreshes_avatar_scope()
	_finish_suite("TOWN_UI_RUNTIME_PASS")


func _scenario_avatar_perception_only_refreshes_avatar_scope() -> void:
	var adapter := ADAPTER.new()
	var world := AvatarPerceptionWorld.new()
	adapter.set("_world", world)
	adapter.set("_session_config", {
		"source": "test",
		"capabilityMode": "formal",
		"formalReady": true,
	})
	adapter.call("_on_player_avatar_perception_changed", {
		"source": "avatar_position",
		"semanticStateChanged": false,
		"nearbyChanged": false,
		"positionChanged": true,
	})
	_expect(
		(adapter.get("_pending_world_refresh_scopes") as Array).is_empty(),
		"化身纯位置感知变化不会排队整套小镇 UI",
	)
	_expect(
		((adapter.get("_view_models") as Dictionary).get("avatar", {}) as Dictionary).is_empty(),
		"化身纯位置感知变化不生成任何化身界面快照",
	)
	_expect(
		(adapter.get("_pending_world_refresh_scopes") as Array).is_empty(),
		"化身纯位置变化不留下 UI 修订抑制或待刷新队列",
	)
	adapter.call("_on_player_avatar_perception_changed", {
		"source": "avatar_position",
		"semanticStateChanged": false,
		"nearbyChanged": true,
		"positionChanged": true,
		"added": ["林岚"],
		"removed": [],
	})
	_expect(
		not ((adapter.get("_view_models") as Dictionary).get("avatar", {}) as Dictionary).is_empty(),
		"附近居民集合变化时仍立即生成化身目标界面",
	)
	adapter.call("_on_world_revision_changed", 2)
	_expect(
		(adapter.get("_pending_world_refresh_scopes") as Array).is_empty(),
		"附近居民位置修订不会在世界修订信号中重新排队 town_hud",
	)
	adapter.free()


func _scenario_mobile_platform_foundation() -> void:
	_expect_equal(
		MOBILE_UI_PROFILE.input_mode(Vector2(960.0, 540.0)),
		"keyboard_mouse",
		"桌面小窗口不能按比例误切到触控模式",
	)
	_expect_equal(
		MOBILE_UI_PROFILE.layout_profile(Vector2(960.0, 540.0)),
		MOBILE_UI_PROFILE.DESKTOP_COMPACT,
		"桌面小窗口必须保持桌面布局分类",
	)
	_expect(
		MOBILE_UI_PROFILE.is_phone_landscape(Vector2(960.0, 540.0)),
		"手机横屏尺寸识别应可独立用于布局测试",
	)
	var expected_bands := {
		Vector2(2048.0, 1536.0): "tablet_4_3",
		Vector2(2160.0, 1440.0): "foldable_or_tablet",
		Vector2(2400.0, 1350.0): "standard_landscape",
		Vector2(2520.0, 1080.0): "ultrawide_phone",
	}
	for viewport: Vector2 in expected_bands:
		_expect_equal(
			MOBILE_UI_PROFILE.adaptive_landscape_band(viewport),
			expected_bands[viewport],
			"手机、平板与折叠屏横屏比例分类正确",
		)
	var safe := MOBILE_UI_PROFILE.safe_rect(
		Vector2(2400.0, 1080.0),
		Vector4(80.0, 20.0, 60.0, 40.0),
	)
	_expect_equal(safe.position, Vector2(80.0, 20.0), "安全区起点扣除左上留白")
	_expect_equal(safe.size, Vector2(2260.0, 1020.0), "安全区尺寸扣除四边留白")
	var design := MOBILE_UI_PROFILE.centered_design_rect(
		Vector2(2520.0, 1080.0),
		Vector2(1920.0, 1080.0),
	)
	_expect_equal(design.position, Vector2(300.0, 0.0), "16:9 前景在 21:9 内居中")
	_expect_equal(design.size, Vector2(1920.0, 1080.0), "居中前景不得横向拉伸")
	_expect_equal(
		MOBILE_UI_PROFILE.uniform_cover_scale(
			Vector2(2520.0, 1080.0),
			Vector2(1920.0, 1080.0),
		),
		1.3125,
		"铺满背景统一等比缩放",
	)
	await _verify_mobile_touch_scroll_router()
	await _verify_resident_directory_source_scaling()
	await _verify_mobile_text_input_policy()
	await _verify_mobile_scene_interaction()
	_verify_mobile_page_layout_assets()
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	_expect(project_text.contains("window/size/resizable.mobile=true"), "Android 窗口允许重新布局")
	_expect(project_text.contains("window/size/viewport_width.mobile=1280"), "Android 使用独立参考宽度")
	_expect(project_text.contains("window/size/viewport_height.mobile=720"), "Android 使用独立参考高度")
	_expect(project_text.contains("window/handheld/orientation=4"), "Android 锁定自动翻转横屏")
	_expect(
		project_text.contains("pointing/emulate_mouse_from_touch=true"),
		"Android 触摸可触发桌面控件点击",
	)
	var export_text := FileAccess.get_file_as_string("res://export_presets.cfg")
	_expect(export_text.contains("permissions/internet=true"), "Android 包允许连接模型服务")
	_expect(
		export_text.contains("command_line/extra_args=\"--rendering-method gl_compatibility\""),
		"Android 包明确使用兼容渲染",
	)
	var game_flow_host := root.get_node_or_null("GameFlowHost")
	_expect(game_flow_host != null, "正式入口由自动加载创建")
	if game_flow_host != null:
		_expect(
			game_flow_host.get_node_or_null("MobileTouchScrollRouter") == null,
			"桌面运行时不能挂载手机触控滚动服务",
		)
		_expect(
			game_flow_host.get_node_or_null("MobileTextInputPolicy") == null,
			"桌面运行时不能接管文本输入",
		)


func _verify_resident_directory_source_scaling() -> void:
	var drawer := RESIDENT_DIRECTORY_DRAWER.new() as Control
	drawer.size = Vector2(720.0, 1080.0)
	root.add_child(drawer)
	await process_frame
	var buttons := drawer.get("_row_buttons") as Array
	var content := (
		(buttons[0] as Button).get_meta("content") as Control
		if not buttons.is_empty()
		else null
	)
	_expect(content != null, "居民目录行内容节点存在")
	if content != null:
		_expect_equal(
			content.size,
			Vector2(604.0, 146.0),
			"居民目录行内容保持原始排版尺寸",
		)
		_expect_equal(
			content.scale,
			Vector2(720.0 / 1024.0, 1080.0 / 1536.0),
			"居民目录头像与文字在平板比例下统一缩放",
		)
	drawer.queue_free()
	await process_frame


func _verify_avatar_skillbar_touch_scaling() -> void:
	var original_size := _avatar_hud.size
	var original_fixture := (_avatar_hud.get("_fixture") as Dictionary).duplicate(true)
	_avatar_hud.set("_fixture", {
		"inputMode": "touch",
		"safeInsets": {"top": 0, "right": 0, "bottom": 0, "left": 0},
		"copyScale": 1.0,
	})
	_avatar_hud.size = Vector2(1280.0, 720.0)
	_avatar_hud.call("_request_rebuild_preserving_joystick")
	await process_frame
	await process_frame
	var snapshot := _avatar_hud.call("get_runtime_snapshot") as Dictionary
	var skillbar_rect := _component_rect(
		snapshot.get("componentRects", []) as Array,
		"skillbar",
	)
	_expect_equal(
		skillbar_rect.size,
		Vector2(496.0, 138.0),
		"触控技能栏外框使用手机版放大尺寸",
	)
	var child_rects := snapshot.get("skillbarChildRects", []) as Array
	var art_size := Vector2.ZERO
	var button_size := Vector2.ZERO
	var all_children_inside := true
	for child_value: Variant in child_rects:
		if not child_value is Dictionary:
			continue
		var child := child_value as Dictionary
		var values := child.get("rect", []) as Array
		if values.size() != 4:
			continue
		var child_size := Vector2(float(values[2]), float(values[3]))
		match String(child.get("name", "")):
			"SkillAttack1Art":
				art_size = child_size
			"SkillAttack1Button":
				button_size = child_size
		all_children_inside = all_children_inside and bool(child.get("insideShell", false))
	_expect(
		is_equal_approx(art_size.x, 58.0 * 496.0 / 310.0)
			and is_equal_approx(art_size.y, 58.0 * 138.0 / 86.0),
		"触控技能图标随技能栏外框同步放大",
	)
	_expect(
		is_equal_approx(button_size.x, 68.0 * 496.0 / 310.0)
			and is_equal_approx(button_size.y, 68.0 * 138.0 / 86.0),
		"触控技能点击区域随技能栏外框同步放大",
	)
	_expect(all_children_inside, "放大后的技能图标与点击区域仍位于技能栏框内")
	_avatar_hud.set("_fixture", original_fixture)
	_avatar_hud.size = original_size
	_avatar_hud.call("_request_rebuild_preserving_joystick")
	await process_frame


func _verify_mobile_touch_scroll_router() -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(120.0, 100.0)
	scroll.size = Vector2(320.0, 240.0)
	root.add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(300.0, 1200.0)
	scroll.add_child(content)
	var router := MOBILE_TOUCH_SCROLL_ROUTER.new() as Node
	root.add_child(router)
	router.configure(true)
	await process_frame
	var point := Vector2(200.0, 200.0)
	_expect(not router.consume(_mobile_touch(0, true, point)), "滚动起点不吞普通点击")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = point - Vector2(0.0, 4.0)
	_expect(not router.consume(drag), "触摸位移未超过阈值时不抢走点击或文本选区")
	drag.position = point - Vector2(0.0, 100.0)
	_expect(router.consume(drag), "手指拖动由滚动路由接管")
	_expect(scroll.scroll_vertical > 0, "手指上拖后竖向滑条同步前进")
	_expect(router.consume(_mobile_touch(0, false, drag.position)), "拖动抬手不误触列表项")
	_expect(not bool(router.get("_drag_started")), "滚动结束后清理拖动状态")
	_expect(not router.consume(_mobile_touch(1, true, point)), "取消场景先建立滚动候选")
	var canceled_touch := _mobile_touch(1, false, point)
	canceled_touch.canceled = true
	_expect(not router.consume(canceled_touch), "系统取消普通触摸时不提交滚动操作")
	_expect_equal(router.get("_pointer_index"), -1, "系统取消触摸后释放滚动指针")
	_expect(not router.consume(_mobile_touch(2, true, point)), "切后台场景先建立滚动候选")
	router.call("_notification", NOTIFICATION_APPLICATION_FOCUS_OUT)
	_expect_equal(router.get("_pointer_index"), -1, "应用切到后台后释放滚动指针")
	_expect(not bool(router.get("_drag_started")), "应用切到后台后清理滚动拖动状态")
	var selection_owner := LineEdit.new()
	selection_owner.position = Vector2(20.0, 20.0)
	selection_owner.size = Vector2(240.0, 72.0)
	content.add_child(selection_owner)
	selection_owner.grab_focus()
	selection_owner.set_meta("mobile_native_text_actions_visible", true)
	_expect(not router.consume(_mobile_touch(3, true, point)), "长按选区场景先建立滚动候选")
	# Synthetic input does not update Viewport.gui_get_hovered_control(), so bind
	# the same source control the real touch hit-test records.
	router.set("_source_control", selection_owner)
	var selection_drag := InputEventScreenDrag.new()
	selection_drag.index = 3
	selection_drag.position = point - Vector2(0.0, 80.0)
	_expect(not router.consume(selection_drag), "原生文本选区出现后不抢走拖动")
	_expect_equal(router.get("_pointer_index"), -1, "文本选区接管拖动后释放页面滚动指针")
	var clip_parent := Control.new()
	clip_parent.position = Vector2(900.0, 100.0)
	clip_parent.size = Vector2(100.0, 100.0)
	clip_parent.clip_contents = true
	root.add_child(clip_parent)
	var clipped_scroll := ScrollContainer.new()
	clipped_scroll.size = Vector2(300.0, 300.0)
	clip_parent.add_child(clipped_scroll)
	var clipped_content := Control.new()
	clipped_content.custom_minimum_size = Vector2(280.0, 900.0)
	clipped_scroll.add_child(clipped_content)
	await process_frame
	_expect(
		not bool(router.call(
			"_point_inside_control_clips",
			clipped_scroll,
			Vector2(1050.0, 150.0),
		)),
		"统一触控滑动不会命中父容器裁剪区外的隐藏列表",
	)
	clip_parent.queue_free()
	router.queue_free()
	scroll.queue_free()
	await process_frame


func _verify_mobile_text_input_policy() -> void:
	var policy := MOBILE_TEXT_INPUT_POLICY.new() as Node
	root.add_child(policy)
	policy.configure(true, true)
	var line := LineEdit.new()
	line.position = Vector2(500.0, 100.0)
	line.size = Vector2(360.0, 80.0)
	root.add_child(line)
	await process_frame
	_expect(
		not line.virtual_keyboard_enabled,
		"移动端输入框初始不自动唤起输入法",
	)
	_expect(
		not line.virtual_keyboard_show_on_focus,
		"页面恢复焦点时不能绕过短按判定自动弹出输入法",
	)
	_expect(line.context_menu_enabled, "移动端输入框保留桌面右键菜单")
	var point := Vector2(540.0, 130.0)
	policy.call("_handle_screen_touch", _mobile_touch(1, true, point))
	_expect_equal(
		(policy.get("_touch_candidates") as Dictionary).size(),
		1,
		"按下输入框后等待区分短按与长按",
	)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = point + Vector2(40.0, 0.0)
	policy.call("_handle_screen_drag", drag)
	var candidates := policy.get("_touch_candidates") as Dictionary
	_expect(
		bool((candidates.get(1, {}) as Dictionary).get("moved", false)),
		"拖动不能误判为点击",
	)
	policy.call("_handle_screen_touch", _mobile_touch(1, false, drag.position))
	_expect_equal(
		(policy.get("_touch_candidates") as Dictionary).size(),
		0,
		"触控结束后清理输入候选状态",
	)
	var canceled_press := _mobile_touch(2, true, point)
	policy.call("_handle_screen_touch", canceled_press)
	var canceled_release := _mobile_touch(2, false, point)
	canceled_release.canceled = true
	policy.call("_handle_screen_touch", canceled_release)
	_expect(
		not bool(policy.get("_keyboard_visible")),
		"系统取消触摸不能误弹输入法",
	)
	line.editable = false
	_expect(
		policy.call("_text_input_at", point) == null,
		"只读输入框不能成为移动端键盘目标",
	)
	line.editable = true
	line.grab_focus()
	policy.call("_show_system_keyboard", line)
	_expect(bool(policy.get("_keyboard_visible")), "短按后记录已打开的系统键盘")
	line.release_focus()
	policy.call("_process", 0.0)
	_expect(
		not bool(policy.get("_keyboard_visible")),
		"输入框失去焦点后收起手动打开的系统键盘",
	)
	policy.call("_handle_screen_touch", _mobile_touch(3, true, point))
	line.grab_focus()
	line.set_meta("mobile_native_text_actions_visible", true)
	policy.set("_native_action_control", line)
	policy.set("_keyboard_control", line)
	policy.set("_keyboard_visible", true)
	policy.set("_keyboard_retry_remaining", 3)
	policy.set("_keyboard_retry_at_msec", 0)
	policy.call("_process", 0.0)
	_expect_equal(
		policy.get("_keyboard_retry_remaining"),
		3,
		"原生长按操作栏建立后不再重复请求键盘",
	)
	policy.call("_notification", NOTIFICATION_APPLICATION_FOCUS_OUT)
	_expect_equal(
		(policy.get("_touch_candidates") as Dictionary).size(),
		0,
		"应用切到后台后清理输入候选状态",
	)
	_expect(
		not line.has_meta("mobile_native_text_actions_visible"),
		"应用切到后台后清理 Android 文本操作栏占用状态",
	)
	policy.call("_handle_screen_touch", _mobile_touch(4, true, point))
	line.set_meta("mobile_native_text_actions_visible", true)
	policy.set("_native_action_control", line)
	policy.queue_free()
	await process_frame
	_expect(
		not line.has_meta("mobile_native_text_actions_visible"),
		"输入策略退出页面时清理 Android 文本操作栏占用状态",
	)
	line.queue_free()
	await process_frame


func _verify_mobile_scene_interaction() -> void:
	for asset_path: String in [
		"res://assets/ui/avatar_mode/runtime/mobile_joystick/mobile_joystick_base_v2.png",
		"res://assets/ui/avatar_mode/runtime/mobile_joystick/mobile_joystick_knob_v2.png",
		"res://assets/ui/avatar_mode/runtime/mobile_context_actions/mobile_talk_action_v1.png",
		"res://assets/ui/avatar_mode/runtime/mobile_context_actions/mobile_pet_cat_action_v1.png",
	]:
		_expect(FileAccess.file_exists(asset_path), "移动端场景交互资产已进入正式资源目录")
	var joystick := VIRTUAL_JOYSTICK.new() as Control
	joystick.size = Vector2(300.0, 300.0)
	root.add_child(joystick)
	var knob := Control.new()
	knob.size = Vector2(120.0, 120.0)
	joystick.add_child(knob)
	joystick.configure(knob)
	var movement_events: Array[Vector2] = []
	joystick.movement_changed.connect(func(value: Vector2) -> void: movement_events.append(value))
	var press := _mobile_touch(7, true, Vector2(285.0, 150.0))
	joystick.call("_gui_input", press)
	_expect((joystick.call("movement") as Vector2).x > 0.7, "摇杆按下后输出连续方向")
	joystick.call("_gui_input", _mobile_touch(7, false, Vector2(285.0, 150.0)))
	_expect((joystick.call("movement") as Vector2).is_zero_approx(), "摇杆抬手后回中并清空移动输入")
	_expect(movement_events.size() >= 2, "摇杆按下与抬手都通知运行时")
	var emulated_mouse_press := InputEventMouseButton.new()
	emulated_mouse_press.device = InputEvent.DEVICE_ID_EMULATION
	emulated_mouse_press.button_index = MOUSE_BUTTON_LEFT
	emulated_mouse_press.pressed = true
	emulated_mouse_press.position = Vector2(285.0, 150.0)
	joystick.call("_gui_input", emulated_mouse_press)
	_expect(
		(joystick.call("movement") as Vector2).is_zero_approx()
		and not bool(joystick.call("is_pointer_active")),
		"触摸生成的鼠标副本不会让摇杆重复接管指针",
	)
	var physical_mouse_press := emulated_mouse_press.duplicate() as InputEventMouseButton
	physical_mouse_press.device = InputEvent.DEVICE_ID_MOUSE
	joystick.call("_gui_input", physical_mouse_press)
	_expect(
		(joystick.call("movement") as Vector2).x > 0.7,
		"真实鼠标仍可操作摇杆以支持桌面调试和外接鼠标",
	)
	physical_mouse_press.pressed = false
	joystick.call("_gui_input", physical_mouse_press)
	joystick.call("_gui_input", _mobile_touch(0, true, Vector2(285.0, 150.0)))
	physical_mouse_press.pressed = false
	joystick.call("_gui_input", physical_mouse_press)
	_expect(
		(joystick.call("movement") as Vector2).x > 0.7
		and bool(joystick.call("is_pointer_active")),
		"外接鼠标抬起不会取消第零根手指控制的摇杆",
	)
	joystick.call("_gui_input", _mobile_touch(0, false, Vector2(285.0, 150.0)))
	var gesture := TOUCH_CAMERA_GESTURE.new()
	_expect(
		not bool(gesture.consume(_mobile_touch(1, true, Vector2(100.0, 100.0))).get("handled", true)),
		"单指起点保留给场景点击",
	)
	var pan := InputEventScreenDrag.new()
	pan.index = 1
	pan.position = Vector2(130.0, 100.0)
	pan.relative = Vector2(30.0, 0.0)
	var pan_result := gesture.consume(pan)
	_expect_equal(pan_result.get("pan"), Vector2(30.0, 0.0), "单指拖动输出镜头平移")
	gesture.consume(_mobile_touch(1, false, pan.position))
	var input := MOBILE_MOVEMENT_INPUT.new()
	input.set_value(Vector2(0.8, 0.0))
	_expect_equal(input.merged_with(Vector2.ZERO), Vector2(0.8, 0.0), "触控移动输入在物理输入为空时生效")
	_expect_equal(input.merged_with(Vector2(1.0, 0.0)), Vector2(1.0, 0.0), "物理输入优先于较弱触控输入")
	var history_rail := BULLETIN_HISTORY_RAIL.new() as Control
	history_rail.size = Vector2(48.0, 240.0)
	root.add_child(history_rail)
	history_rail.call("set_page_state", 0, 4)
	history_rail.call("_gui_input", _mobile_touch(21, true, Vector2(24.0, 30.0)))
	history_rail.call("_gui_input", _mobile_touch(22, false, Vector2(24.0, 210.0)))
	_expect_equal(history_rail.get("_touch_index"), 21, "公告历史滑条忽略另一根手指的抬起")
	history_rail.call("_gui_input", _mobile_touch(21, false, Vector2(24.0, 30.0)))
	_expect_equal(history_rail.get("_touch_index"), -1, "公告历史滑条只由原触点结束拖动")
	var close_button := RESIDENT_DETAIL_CLOSE_BUTTON_SCENE.instantiate() as Control
	close_button.position = Vector2(900.0, 420.0)
	close_button.size = Vector2(96.0, 96.0)
	root.add_child(close_button)
	var close_requests := [0]
	close_button.close_requested.connect(func() -> void: close_requests[0] += 1)
	close_button.call("_gui_input", _mobile_touch(31, true, Vector2(48.0, 48.0)))
	close_button.call("_gui_input", _mobile_touch(32, false, Vector2(48.0, 48.0)))
	_expect_equal(close_requests[0], 0, "居民详情自绘按钮忽略另一根手指的抬起")
	_expect_equal(close_button.get("_touch_index"), 31, "居民详情自绘按钮保留原触点归属")
	close_button.call("_gui_input", _mobile_touch(31, false, Vector2(48.0, 48.0)))
	_expect_equal(close_requests[0], 1, "居民详情自绘按钮由同一触点完成点击")
	close_button.call("_gui_input", _mobile_touch(33, true, Vector2(48.0, 48.0)))
	close_button.call("_gui_input", _mobile_touch(33, false, Vector2(140.0, 48.0)))
	_expect_equal(close_requests[0], 1, "手指移出居民详情自绘按钮后抬起不会误触")
	var assignment := RESIDENT_MODEL_ASSIGNMENT_SIMPLIFIED.new() as Control
	var gesture_owner := Control.new()
	assignment.call("_on_list_gui_input", _mobile_touch(41, true, Vector2(20.0, 20.0)), "resident", gesture_owner)
	var unrelated_drag := InputEventScreenDrag.new()
	unrelated_drag.index = 42
	unrelated_drag.position = Vector2(20.0, 30.0)
	unrelated_drag.relative = Vector2(0.0, 10.0)
	assignment.call("_on_list_gui_input", unrelated_drag, "resident", gesture_owner)
	_expect_equal(
		float((assignment.get("_gesture_accum") as Dictionary).get("resident", -1.0)),
		0.0,
		"模型分配列表忽略另一根手指的拖动",
	)
	assignment.call("_on_list_gui_input", _mobile_touch(42, false, Vector2(20.0, 30.0)), "resident", gesture_owner)
	_expect_equal(
		int((assignment.get("_gesture_touch_index") as Dictionary).get("resident", -1)),
		41,
		"模型分配列表忽略另一根手指的抬起",
	)
	assignment.call("_on_list_gui_input", _mobile_touch(41, false, Vector2(20.0, 20.0)), "resident", gesture_owner)
	_expect_equal(
		int((assignment.get("_gesture_touch_index") as Dictionary).get("resident", -2)),
		-1,
		"模型分配列表只由原触点结束手势",
	)
	assignment.free()
	gesture_owner.free()
	close_button.queue_free()
	history_rail.queue_free()
	joystick.queue_free()
	await process_frame


func _verify_mobile_page_layout_assets() -> void:
	for asset_path: String in [
		"res://assets/ui/resident_detail/runtime/resident_detail_background_transparent_v1.png",
		"res://assets/ui/resident_detail/runtime/relationship_page_transparent_v1.png",
		"res://assets/ui/resident_detail/runtime/memory_page_transparent_v1.png",
		"res://assets/ui/resident_detail/runtime/memory_operation_page_transparent_v1.png",
	]:
		_expect(FileAccess.file_exists(asset_path), "居民详情移动端透明页面资产已进入正式资源目录")
	var loading_source := FileAccess.get_file_as_string(
		"res://ui/startup/TownEntryLoadingOverlay.gd"
	)
	_expect(
		loading_source.contains("TextureRect.STRETCH_KEEP_ASPECT_COVERED"),
		"进入小镇加载底图按比例覆盖完整视口",
	)
	_expect(
		loading_source.contains("AUTO_PROGRESS_CAP := 0.92"),
		"进入小镇加载进度会自动推进到等待上限",
	)
	var overview_source := FileAccess.get_file_as_string(
		"res://ui/resident_overview/ResidentOverviewScreen.gd"
	)
	_expect(
		overview_source.contains("MOBILE_VISIBLE_ROSTER_ROWS := 7"),
		"居民总览移动端一次显示七个可滑动条目",
	)
	var hud_source := FileAccess.get_file_as_string(
		"res://ui/town/hud/runtime/TownHudOverlay.gd"
	)
	_expect(
		hud_source.contains("MOBILE_LEFT_RAIL_RECT")
			and hud_source.contains("MOBILE_RIGHT_RAIL_RECT"),
		"移动端 HUD 左右导轨使用独立比例锁定组件",
	)
	_expect(
		hud_source.contains("mobile_time_component")
			and hud_source.contains("mobile_avatar_component"),
		"移动端 HUD 时间与化身区域不随宽屏横向拉伸",
	)
	_expect(
		hud_source.contains("STRETCH_KEEP_ASPECT_CENTERED")
			and hud_source.contains("MOBILE_TOP_FRAME_BAND_RECT"),
		"移动端 HUD 仅让空白边带延展并保持图标比例",
	)


func _mobile_touch(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event


func _scenario_dynamic_feedback_text_is_complete() -> void:
	var long_system_message := (
		"上次保存未完成，系统已经恢复最近一份完整存档。请先检查居民状态、"
		+ "当前地点和模型连接，再决定是否继续刚才的操作。"
	)
	var toast := SYSTEM_FEEDBACK_TOAST_SCENE.instantiate() as Control
	toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	toast.size = Vector2(560, 115)
	toast.set("expanded", false)
	root.add_child(toast)
	await process_frame
	var feedback_issues := toast.call("configure", {
		"scope": "save",
		"status": "ready",
		"revision": 1,
		"data": {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"feedback": {
				"feedbackId": "long-system-feedback-test",
				"component": "toast",
				"tone": "warning",
				"title": "已恢复完整存档",
				"message": long_system_message,
				"blocking": false,
				"dismissPolicy": "auto_or_manual",
				"durationMsec": 3000,
			},
		},
		"actions": {},
		"operation": {"status": "idle", "requestId": ""},
		"error": null,
	}, "toast") as PackedStringArray
	_expect(feedback_issues.is_empty(), "长系统反馈可应用到紧凑提示框")
	await process_frame
	var toast_snapshot := toast.call("runtime_text_snapshot") as Dictionary
	var toast_pages := toast_snapshot.get("pages", []) as Array
	_expect(toast_pages.size() > 1, "紧凑横屏系统反馈会完整分页")
	_expect_equal(
		"".join(toast_pages),
		"已恢复完整存档：%s" % long_system_message,
		"系统反馈分页保留标题和完整正文",
	)
	_expect_equal(
		toast_snapshot.get("overrun"),
		TextServer.OVERRUN_NO_TRIMMING,
		"系统反馈页不再静默裁字或显示省略号",
	)
	_expect_equal(
		toast_snapshot.get("visibleLines"),
		1,
		"紧凑横屏系统反馈当前页实际完整显示一行",
	)
	toast.call("_process", 2.6)
	_expect_equal(
		(toast.call("runtime_text_snapshot") as Dictionary).get("pageIndex"),
		1,
		"系统反馈会轮播到后续正文页",
	)
	_expect(
		int(toast.call("minimum_read_duration_msec")) > 3000,
		"自动提示会为全部正文页保留阅读时间",
	)
	toast.free()

	var long_avatar_message := (
		"当前目标离开了可交互范围，路径也被临时占用，请重新靠近目标后再试。"
	)
	var avatar_hud := AVATAR_HUD_SCENE.instantiate() as Control
	avatar_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	avatar_hud.size = Vector2(1280, 720)
	root.add_child(avatar_hud)
	await process_frame
	avatar_hud.call("configure", {
		"avatar": {
			"scope": "avatar",
			"status": "ready",
			"revision": 1,
			"data": {
				"source": "runtime",
				"capabilityMode": "formal",
				"formalReady": true,
				"mode": "avatar_active",
			},
			"actions": {
				"retry": {
					"intent": "avatar.retry",
					"enabled": true,
					"disabledReason": "",
				},
			},
			"operation": {
				"status": "error",
				"requestId": "avatar-long-error",
				"intent": "avatar.interact",
			},
			"error": {"code": "TARGET_UNREACHABLE", "message": long_avatar_message},
		},
		"conversation": {
			"scope": "conversation",
			"status": "ready",
			"revision": 1,
			"data": {"conversationId": "", "displayMode": "player"},
			"actions": {},
			"operation": {"status": "idle", "requestId": ""},
			"error": null,
		},
	}, {"inputMode": "keyboard_mouse"})
	await process_frame
	await process_frame
	var avatar_feedback := avatar_hud.call("operation_feedback_snapshot") as Dictionary
	var avatar_pages := avatar_feedback.get("pages", []) as Array
	_expect(avatar_pages.size() > 1, "化身长错误会拆成多个两行反馈页")
	_expect_equal(
		"".join(avatar_pages),
		long_avatar_message + "　R 重试",
		"化身错误分页保留完整原因和重试提示",
	)
	_expect_equal(
		avatar_feedback.get("maxLines"),
		2,
		"化身反馈每页保持两行可见区域",
	)
	_expect_equal(
		avatar_feedback.get("overrun"),
		TextServer.OVERRUN_NO_TRIMMING,
		"化身反馈页不再用省略号吞掉重试提示",
	)
	var avatar_visible_lines := int(avatar_feedback.get("visibleLines", 0))
	_expect(
		avatar_visible_lines >= 1 and avatar_visible_lines <= 2,
		"化身操作反馈当前页实际完整显示一至两行",
	)
	avatar_hud.call("_process", 2.1)
	_expect_equal(
		(avatar_hud.call("operation_feedback_snapshot") as Dictionary).get("pageIndex"),
		1,
		"化身操作反馈会显示下一页完整原因",
	)
	avatar_hud.free()

	var provider_screen := PROVIDER_SETTINGS_SCREEN_SCENE.instantiate() as Control
	provider_screen.set("_layout_profile", "phone_portrait")
	provider_screen.set("_view_model", {
		"actions": {},
		"operation": {"status": "idle", "requestId": ""},
		"error": null,
	})
	var long_provider_message := (
		"模型服务已经返回响应，但当前模型名称与服务端可用列表不一致，"
		+ "请检查连接地址、模型名称和访问权限后重新检查。"
	)
	var provider_panel := provider_screen.call("_build_status_section", {
		"providerId": "deepseek",
		"displayName": "DeepSeek",
		"enabled": true,
		"connection": {
			"status": "unavailable",
			"label": "连接失败",
			"message": long_provider_message,
		},
	}) as Control
	var provider_message_label: Label
	for child: Node in provider_panel.find_children("*", "Label", true, false):
		if String(child.get_meta("gate_id", "")) == "connection_status_message":
			provider_message_label = child as Label
			break
	_expect(provider_message_label != null, "模型连接状态正文已创建")
	if provider_message_label != null:
		_expect_equal(provider_message_label.text, long_provider_message, "模型连接结果保留完整错误原文")
		_expect_equal(provider_message_label.max_lines_visible, -1, "模型连接结果不再固定两行")
		_expect_equal(
			provider_message_label.text_overrun_behavior,
			TextServer.OVERRUN_NO_TRIMMING,
			"模型连接结果不再使用省略号裁切",
		)
		_expect(not provider_message_label.clip_text, "模型连接结果不再静默裁字")
		_expect(
			provider_message_label.custom_minimum_size.y > 60.0,
			"紧凑布局会按长错误内容增加正文高度",
		)
	provider_panel.free()
	provider_screen.free()


func _verify_conversation_agent_dispatch_first_frame(runtime: Node) -> void:
	var real_gateway := runtime.get("_agent_gateway") as Node
	var gateway := AgentGatewayPumpSpy.new()
	runtime.set("_agent_gateway", gateway)
	runtime.call("_hold_agent_dispatch_for_conversation_first_frame")
	runtime.call("_pump_agent_gateway_for_frame")
	_expect_equal(
		gateway.pump_limits,
		[],
		"conversation input leaves one process turn free for the first UI frame",
	)
	runtime.call("_pump_agent_gateway_for_frame")
	_expect_equal(
		gateway.pump_limits,
		[1],
		"conversation request resumes with the one-request frame budget",
	)
	runtime.call("_hold_agent_dispatch_for_conversation_first_frame")
	runtime.call("_hold_agent_dispatch_for_conversation_first_frame")
	runtime.call("_pump_agent_gateway_for_frame")
	runtime.call("_pump_agent_gateway_for_frame")
	_expect_equal(
		gateway.pump_limits,
		[1, 1],
		"repeated same-frame holds coalesce without delaying extra frames",
	)
	runtime.set("_agent_gateway", real_gateway)
	gateway.free()


func _setup_ui_runtime_host_navigation() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	# This navigation test has no audio assertions. Stop the project autoload
	# before its deferred ambience start so a headless quit cannot retain an
	# AudioStreamPlaybackMP3 outside the UI ownership under test.
	var audio_autoload := root.get_node_or_null("TownAudioController")
	if audio_autoload != null:
		for child: Node in audio_autoload.get_children():
			if child is AudioStreamPlayer:
				(child as AudioStreamPlayer).stop()
				(child as AudioStreamPlayer).stream = null
		audio_autoload.queue_free()
	_adapter = AdapterHarness.new()
	root.add_child(_adapter)
	_host = HOST_SCRIPT.new() as Control
	_adapter.world_menu_host = _host
	var bind_result := _host.call("bind_town_ui_adapter", _adapter) as Dictionary
	_expect(bool(bind_result.get("ok", false)), "formal Adapter harness binds before host ready")
	_host.pause_requested.connect(_on_pause_requested)
	root.add_child(_host)
	_avatar_hud = AVATAR_HUD_SCENE.instantiate() as Control
	var avatar_issues := _avatar_hud.call(
		"bind_town_ui_adapter",
		_adapter,
	) as PackedStringArray
	_expect(avatar_issues.is_empty(), "Avatar HUD binds the same formal Adapter")
	root.add_child(_avatar_hud)



func _scenario_ui_runtime_host_navigation() -> void:
	_setup_ui_runtime_host_navigation()
	await process_frame
	await process_frame
	await process_frame
	_verify_resident_wardrobe_catalog_failure()
	root.size = Vector2i(1920, 1080)
	_host.call("_fit_root_to_viewport")
	await process_frame
	await process_frame
	_expect_equal(_direct_child_count("TownHudOverlay"), 1, "observer HUD mounts exactly once")
	_expect_equal(_direct_child_count("SystemFeedbackLayer"), 1, "feedback layer mounts exactly once")
	_expect_equal(_host.call("current_route"), &"town", "host starts on town route")
	var transition_notice := _host.call("present_feedback", {
		"scope": "startup",
		"status": "ready",
		"revision": 1,
		"data": {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"feedback": {
				"feedbackId": "startup-latest-save-incomplete-fallback",
				"component": "toast",
				"tone": "warning",
				"title": "已使用最近完整存档",
				"message": "上次保存未完成，已使用最近完整存档",
				"blocking": false,
				"dismissPolicy": "auto_or_manual",
				"durationMsec": 5000,
				"anchor": "viewport_top_right",
				"dedupeKey": "startup.latest-save-incomplete-fallback",
			},
		},
		"actions": {
			"dismiss": {
				"intent": "feedback.dismiss",
				"enabled": true,
				"disabledReason": "",
			},
		},
		"operation": {
			"requestId": "startup-latest-save-incomplete-fallback",
			"intent": "session.continue",
			"status": "success",
			"submittedAtMsec": 0,
			"completedAtMsec": 1,
		},
		"error": null,
	}) as Dictionary
	_expect(
		bool(transition_notice.get("ok", false)),
		"startup transition can present a non-blocking feedback through the host contract",
	)
	await process_frame
	var feedback_layer := _host.get_node_or_null("SystemFeedbackLayer") as Control
	var feedback_snapshot := feedback_layer.call("runtime_gate_snapshot") as Dictionary
	_expect_equal(
		feedback_snapshot.get("activeToastCount"),
		1,
		"incomplete-save fallback is presented as one toast",
	)
	_expect_equal(
		feedback_snapshot.get("activeModalIdentity"),
		"",
		"incomplete-save fallback never opens a blocking modal",
	)
	var hud := _host.get_node_or_null("TownHudOverlay") as Control
	_expect(hud != null and hud.visible, "observer mode owns the visible Town HUD")
	_expect(not _avatar_hud.visible, "observer mode unmounts AvatarModeHud")
	_adapter.publish("avatar", {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"mode": "avatar_descent",
	})
	await process_frame
	_expect(hud != null and hud.visible, "descent keeps HUD visible for conversation bubbles")
	var descent_hud_audit := hud.call("audit_snapshot") as Dictionary
	_expect_equal(
		bool(descent_hud_audit.get("runtimeSkinVisible", true)),
		false,
		"descent mode keeps observer shell hidden"
	)
	_expect(_avatar_hud.visible, "descent mounts AvatarModeHud")
	_expect_equal(
		_avatar_hud.mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"descent locks AvatarModeHud pointer input",
	)
	var descent_snapshot := _avatar_hud.call("get_runtime_snapshot") as Dictionary
	_expect(
		not bool(descent_snapshot.get("wasdVisible", true))
		and not bool(descent_snapshot.get("joystickVisible", true))
		and not bool(descent_snapshot.get("gamepadVisible", true)),
		"descent exposes no movement controls",
	)
	_expect(
		(descent_snapshot.get("intentIds", []) as Array).is_empty(),
		"descent exposes no interactive intents",
	)
	var descent_adapter := descent_snapshot.get("adapterIntegration", {}) as Dictionary
	_expect(
		(descent_adapter.get("focusOrder", []) as Array).is_empty(),
		"descent exposes no keyboard focus targets",
	)
	_adapter.publish("avatar", {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"mode": "avatar_active",
	})
	await process_frame
	_expect(hud != null and hud.visible, "active avatar mode keeps HUD for resident bubbles")
	var active_hud_audit := hud.call("audit_snapshot") as Dictionary
	_expect_equal(
		bool(active_hud_audit.get("runtimeSkinVisible", true)),
		false,
		"active avatar mode keeps observer shell hidden"
	)
	_expect(_avatar_hud.visible, "active avatar mode owns the visible HUD")
	_expect_equal(
		_avatar_hud.mouse_filter,
		Control.MOUSE_FILTER_PASS,
		"active avatar mode enables AvatarModeHud input",
	)
	var active_snapshot := _avatar_hud.call("get_runtime_snapshot") as Dictionary
	_adapter.publish("avatar", {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		# 路由切换期间模拟一个缺少 mode 的部分快照；HUD 应保留上一次
		# 已确认的 active 状态，不能把返回观察按钮一起卸载。
		"focusedTargetId": "resident-lin",
	})
	await process_frame
	var partial_avatar_snapshot := _avatar_hud.call("get_runtime_snapshot") as Dictionary
	_expect(_avatar_hud.visible, "partial avatar snapshot keeps the last visible HUD")
	_expect_equal(
		partial_avatar_snapshot.get("avatarMode"),
		"avatar_active",
		"partial avatar snapshot retains the last confirmed mode",
	)
	_expect(
		"exitMode" in (partial_avatar_snapshot.get("actionIds", []) as Array),
		"partial avatar snapshot retains the return-to-observer action",
	)
	_adapter.publish("avatar", {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"mode": "avatar_active",
	})
	await process_frame
	await _verify_avatar_skillbar_touch_scaling()
	var fixture_before_conversation := (
		_avatar_hud.get("_fixture") as Dictionary
	).duplicate(true)
	var touch_fixture := fixture_before_conversation.duplicate(true)
	touch_fixture["inputMode"] = "touch"
	_avatar_hud.set("_fixture", touch_fixture)
	_avatar_hud.call("_request_rebuild_preserving_joystick")
	await process_frame
	await process_frame
	var held_joystick := _avatar_hud.get("_touch_joystick") as Control
	_expect(held_joystick != null, "触控化身 HUD 提供摇杆")
	if held_joystick != null:
		held_joystick.call(
			"_gui_input",
			_mobile_touch(
				11,
				true,
				Vector2(held_joystick.size.x * 0.9, held_joystick.size.y * 0.5),
			),
		)
		_expect(
			not (_avatar_hud.get("_touch_movement") as Vector2).is_zero_approx(),
			"聊天打开前摇杆能够保持按压方向",
		)
	# The conversation page owns the visible interaction surface. Keep the
	# AvatarModeHud mounted for fast restoration, but hide its skillbar and
	# movement controls so the chat close button and input remain clickable.
	_adapter.publish("conversation", {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"displayMode": "player",
		"conversationId": "avatar-conversation-while-active",
		"residentId": "resident-lin",
		"residentName": "林岚",
		"messages": [],
		"canAttachPhoto": false,
	})
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"chat",
		"active avatar can open the real conversation page",
	)
	_expect(not _avatar_hud.visible, "conversation page hides the active AvatarModeHud")
	_expect(
		(_avatar_hud.get("_touch_movement") as Vector2).is_zero_approx(),
		"聊天打开时立即清空仍被按住的摇杆输入",
	)
	_expect(
		not bool(_avatar_hud.get("_rebuild_after_joystick_release")),
		"聊天隐藏 HUD 不等待可能缺失的触摸抬手事件",
	)
	_avatar_hud.set("_fixture", fixture_before_conversation)
	_expect_equal(
		_avatar_hud.process_mode,
		Node.PROCESS_MODE_ALWAYS,
		"active AvatarModeHud keeps processing while conversation waits",
	)
	var conversation_active_snapshot := _avatar_hud.call("get_runtime_snapshot") as Dictionary
	_expect(
		bool(conversation_active_snapshot.get("suppressedByConversation", false)),
		"conversation projection suppresses the avatar surface",
	)
	_expect(
		not bool(conversation_active_snapshot.get("skillbarVisible", true)),
		"conversation page hides the attack skillbar",
	)
	var conversation_editor := TextEdit.new()
	conversation_editor.name = "ConversationShortcutInputProbe"
	root.add_child(conversation_editor)
	conversation_editor.grab_focus()
	await process_frame
	_expect(
		not bool(_avatar_hud.call("_can_accept_interaction_input")),
		"conversation text focus blocks avatar keyboard shortcuts while HUD is hidden",
	)
	conversation_editor.release_focus()
	conversation_editor.queue_free()
	await process_frame
	_adapter.publish("conversation", {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"displayMode": "player",
		"conversationId": "",
		"residentId": "resident-lin",
		"residentName": "林岚",
		"messages": [],
		"canAttachPhoto": false,
	})
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"town",
		"closing conversation returns to the same active avatar route",
	)
	_expect(_avatar_hud.visible, "closing conversation keeps the active AvatarModeHud mounted")
	# 化身模式已收敛为底部技能槽,不再显示常驻 WASD 移动指引。
	_expect(
		not bool(active_snapshot.get("wasdVisible", true)),
		"active avatar mode keeps movement guidance retired",
	)
	_expect(
		bool(active_snapshot.get("movementHintDismissed", false)),
		"active avatar mode treats the movement hint as already dismissed",
	)
	var original_avatar_hud_size := _avatar_hud.size
	_avatar_hud.size = Vector2(1920.0, 1200.0)
	_avatar_hud.call("_layout_runtime")
	var avatar_16_10_rects := _avatar_hud.call("get_component_rects") as Array
	var avatar_time_status_rect := _component_rect(
		avatar_16_10_rects,
		"time_status",
	)
	var avatar_time_controls_rect := _component_rect(
		avatar_16_10_rects,
		"time_controls",
	)
	var avatar_exit_rect := _component_rect(avatar_16_10_rects, "exit")
	var avatar_skillbar_rect := _component_rect(
		avatar_16_10_rects,
		"skillbar",
	)
	for component_record: Dictionary in avatar_16_10_rects:
		var component_id := String(component_record.get("id", "unknown"))
		var component_rect := _component_rect(
			avatar_16_10_rects,
			component_id,
		)
		_expect(
			component_rect.position.x >= -0.01
			and component_rect.position.y >= -0.01
			and component_rect.end.x <= 1920.01
			and component_rect.end.y <= 1200.01,
			"16:10 avatar HUD component stays inside viewport: %s"
				% component_id,
		)
	_expect(
		avatar_time_status_rect.has_area()
		and avatar_time_status_rect.position.y <= 24.0,
		"16:10 avatar time frame follows the full-height HUD origin",
	)
	_expect(
		avatar_time_controls_rect.has_area()
		and avatar_time_controls_rect.end.x >= 1918.0
		and avatar_time_controls_rect.position.y <= 392.0,
		"16:10 avatar time controls stay aligned to the right HUD edge",
	)
	_expect(
		avatar_exit_rect.has_area()
		and avatar_exit_rect.end.x >= 1904.0
		and avatar_exit_rect.position.y <= 16.0,
		"16:10 return-to-observer frame stays at the display top-right",
	)
	_expect(
		avatar_skillbar_rect.has_area()
		and avatar_skillbar_rect.end.y >= 1188.0,
		"16:10 avatar skillbar stays at the display bottom",
	)
	_avatar_hud.size = original_avatar_hud_size
	_avatar_hud.call("_layout_runtime")

	var avatar_active_rects := _avatar_hud.call("get_component_rects") as Array
	_expect(
		_has_component_rect(avatar_active_rects, "time_status"),
		"化身模式下时间面板默认可见",
	)
	_expect(
		_has_component_rect(avatar_active_rects, "time_controls"),
		"化身模式下时间控制面板默认可见",
	)
	for time_action_id: String in [
		"time_pause",
		"time_speed_1",
		"time_speed_2",
		"time_speed_3",
	]:
		_expect(
			bool(_avatar_hud.call("debug_activate_action", time_action_id)),
			"化身模式时间控件可点击：%s" % time_action_id,
		)
	_expect_dispatch("lifecycle.pause", {"actionId": "time_pause"})
	_expect_dispatch("town_hud.set_time_speed", {"multiplier": 1})
	_expect_dispatch("town_hud.set_time_speed", {"multiplier": 2})
	_expect_dispatch("town_hud.set_time_speed", {"multiplier": 3})
	var baseline_town_hud := (
		_adapter.view_models.get("town_hud", {}) as Dictionary
	).duplicate(true)
	var baseline_town_hud_data := (
		baseline_town_hud.get("data", {}) as Dictionary
	).duplicate(true)
	var baseline_town_hud_actions := (
		baseline_town_hud.get("actions", {}) as Dictionary
	).duplicate(true)
	var degraded_town_hud := baseline_town_hud_data.duplicate(true)
	degraded_town_hud.erase("timeWeather")
	var degraded_actions := baseline_town_hud_actions.duplicate(true)
	degraded_actions.erase("openWeather")
	degraded_actions["weatherChange"] = {
		"intent": "town_hud.open_weather",
		"enabled": true,
		"disabledReason": "",
		"payload": {},
	}
	baseline_town_hud["data"] = degraded_town_hud
	baseline_town_hud["actions"] = degraded_actions
	_adapter.view_models["town_hud"] = baseline_town_hud
	_adapter.publish("town_hud", degraded_town_hud)
	await process_frame
	await process_frame
	var degraded_rects := _avatar_hud.call("get_component_rects") as Array
	_expect(
		_has_component_rect(degraded_rects, "time_status"),
		"时间面板字段缺失时仍保留时间显示（回退 last_confirmed）",
	)
	_expect(
		_avatar_hud.call("debug_activate_action", "weatherChange"),
		"天气按钮在 action key 变化后仍可点（weatherChange 回退）",
	)
	_expect_dispatch("town_hud.open_weather", {"actionId": "weatherChange"})
	# Restore to a canonical payload so 后续测试不受扰。
	baseline_town_hud["data"] = baseline_town_hud_data
	baseline_town_hud["actions"] = baseline_town_hud_actions
	_adapter.view_models["town_hud"] = baseline_town_hud
	_adapter.publish("town_hud", baseline_town_hud_data)
	await process_frame
	await process_frame

	_adapter.publish("avatar", {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"mode": "observer",
	})
	await process_frame
	_expect(hud != null and hud.visible, "observer mode restores Town HUD ownership")
	_expect_equal(
		hud.mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"observer HUD root does not block resident and building world picking",
	)
	_expect(not _avatar_hud.visible, "returning to observer unmounts AvatarModeHud")
	var focus_probe := Button.new()
	focus_probe.name = "FocusReturnProbe"
	focus_probe.text = "focus"
	focus_probe.position = Vector2(12, 12)
	focus_probe.size = Vector2(100, 48)
	_host.add_child(focus_probe)
	focus_probe.grab_focus()
	await process_frame

	_host.call(
		"_on_hud_intent_requested",
		&"town_hud.select_tool",
		{"toolId": "weather_control"},
	)
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"weather_control",
		"weather toolbar toolId opens Weather regardless of visual slot",
	)
	_host.call("close_page")
	await process_frame
	await process_frame

	_host.call(
		"_on_hud_intent_requested",
		&"town_hud.select_tool",
		{"toolId": "town_log"},
	)
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"town_log",
		"log toolbar toolId opens TownLog regardless of visual slot",
	)
	_host.call("close_page")
	await process_frame
	await process_frame

	var avatar_dispatch_count := _adapter.dispatches.size()
	_host.call(
		"_on_hud_intent_requested",
		&"town_hud.select_tool",
		{"toolId": "avatar"},
	)
	_expect_equal(
		_adapter.dispatches.size(),
		avatar_dispatch_count + 1,
		"avatar toolbar tool dispatches exactly one formal toggle",
	)
	_expect_dispatch("town_hud.toggle_avatar", {})
	_expect_equal(
		_host.call("current_route"),
		&"town",
		"avatar toolbar tool does not open a parallel page",
	)

	var pause_count_before_more := _pause_request_count
	_host.call(
		"_on_hud_intent_requested",
		&"town_hud.select_tool",
		{"toolId": "more"},
	)
	_expect_equal(
		_pause_request_count,
		pause_count_before_more + 1,
		"more toolbar tool requests the unique pause/more host",
	)

	var route_before_retired_tool := StringName(_host.call("current_route"))
	var dispatches_before_retired_tool := _adapter.dispatches.size()
	_host.call(
		"_on_hud_intent_requested",
		&"town_hud.select_tool",
		{"toolId": "wardrobe"},
	)
	_expect_equal(
		_host.call("current_route"),
		route_before_retired_tool,
		"retired wardrobe toolId cannot open a primary-toolbar route",
	)
	_expect_equal(
		_adapter.dispatches.size(),
		dispatches_before_retired_tool,
		"retired wardrobe toolId does not dispatch a fallback action",
	)

	_host.call(
		"_on_hud_intent_requested",
		&"town_hud.open_resident_management",
		{},
	)
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"resident_management",
		"resident-management HUD entry opens its dedicated page",
	)
	var management_page := _active_route_page()
	_expect(management_page != null, "resident-management route has one page")
	if management_page != null:
		_expect(
			bool(management_page.call("select_resident_for_test", "resident-lin")),
			"resident-management page can select a stable residentId",
		)
		var modify_button := management_page.find_child(
			"PrimaryActionButton", true, false
		) as BaseButton
		_expect(modify_button != null and not modify_button.disabled, "modify-profile entry is clickable")
		if modify_button != null:
			_adapter.fail_next_lifecycle_pause = true
			modify_button.emit_signal("pressed")
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"resident_management",
		"profile editor pause failure keeps the resident list active",
	)
	_expect(
		_adapter.custom_resident_creator_service == null,
		"profile editor pause failure releases its temporary service",
	)
	management_page = _active_route_page()
	if management_page != null:
		var modify_button := management_page.find_child(
			"PrimaryActionButton", true, false
		) as BaseButton
		if modify_button != null:
			modify_button.emit_signal("pressed")
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"resident_profile_editor",
		"modify-profile entry opens the reused custom resident page",
	)
	_expect_dispatch("lifecycle.pause", {"reason": "resident_editor"})
	var pause_dispatches_before_reopen := _dispatch_count(
		"lifecycle.pause",
		{"reason": "resident_editor"},
	)
	var reopened_editor := _host.call(
		"_open_resident_profile_editor",
		"resident-lin",
	) as Dictionary
	await process_frame
	await process_frame
	_expect(
		bool(reopened_editor.get("ok", false)),
		"reopening the same resident editor route succeeds",
	)
	_expect_equal(
		_host.call("current_route"),
		&"resident_profile_editor",
		"same-route reopen keeps the resident editor active",
	)
	_expect(
		_adapter.custom_resident_creator_service != null,
		"same-route reopen keeps the replacement editor service bound",
	)
	_expect_equal(
		_dispatch_count("lifecycle.pause", {"reason": "resident_editor"}),
		pause_dispatches_before_reopen,
		"same-route reopen does not acquire the pause reason twice",
	)
	var profile_editor_page := _active_route_page()
	_expect(profile_editor_page != null, "resident profile editor route has one page")
	if profile_editor_page != null:
		_expect_equal(
			profile_editor_page.get("presentation_mode"),
			"edit_existing",
			"reused custom page is in edit-existing mode",
		)
		var name_edit := profile_editor_page.find_child(
			"NameEdit",
			true,
			false,
		) as LineEdit
		var home_option := profile_editor_page.find_child(
			"OwnedPlaceOption",
			true,
			false,
		) as BaseButton
		var workplace_option := profile_editor_page.find_child(
			"WorkplaceOption",
			true,
			false,
		) as BaseButton
		var wardrobe_preview := profile_editor_page.find_child(
			"ResidentWardrobeV1Preview",
			true,
			false,
		) as TextureRect
		_expect_equal(
			name_edit.text if name_edit != null else "",
			"林岚",
			"resident profile editor preloads the selected resident name",
		)
		_expect_equal(
			home_option.text if home_option != null else "",
			"北街二号住宅",
			"resident profile editor preloads the selected resident home",
		)
		_expect(
			home_option != null and not home_option.disabled,
			"resident profile editor allows selecting a home",
		)
		_expect(
			workplace_option != null and not workplace_option.disabled,
			"resident profile editor allows selecting a workplace",
		)
		_expect(
			wardrobe_preview != null
			and wardrobe_preview.visible
			and wardrobe_preview.texture != null,
			"resident profile editor renders the selected formal wardrobe preview",
		)
		var editor_view_model := (
			_adapter.custom_resident_creator_service.call("get_view_model")
			as Dictionary
		)
		var editor_data := editor_view_model.get("data", {}) as Dictionary
		var invalid_home := _adapter.custom_resident_creator_service.call(
			"dispatch",
			"resident_profile_editor.update_fields",
			{
				"revision": int(editor_view_model.get("revision", 0)),
				"draftId": String(editor_data.get("draftId", "")),
				"fields": {"ownedPlaceId": "不存在的住宅"},
			},
		) as Dictionary
		_expect(
			not bool(invalid_home.get("ok", false))
			and String(invalid_home.get("errorCode", ""))
				== "RESIDENT_PROFILE_HOME_UNKNOWN",
			"resident profile editor rejects an unavailable home",
		)
		if home_option != null and not home_option.disabled:
			home_option.emit_signal("pressed")
			await process_frame
			var first_home_option := _find_button_with_text(
				profile_editor_page,
				"北街一号住宅",
			)
			_expect(
				first_home_option != null and not first_home_option.disabled,
				"resident profile editor exposes an available home choice",
			)
			if first_home_option != null and not first_home_option.disabled:
				first_home_option.emit_signal("pressed")
				await process_frame
		var current_after_home := (
			_adapter.custom_resident_creator_service.call("get_view_model")
			as Dictionary
		)
		_expect_equal(
			(
				(current_after_home.get("data", {}) as Dictionary).get(
					"draft",
					{},
				) as Dictionary
			).get("ownedPlaceId"),
			"北街一号住宅",
			"resident profile editor stores the selected home in the draft",
		)
		if workplace_option != null and not workplace_option.disabled:
			workplace_option.emit_signal("pressed")
			await process_frame
			var first_workplace_option := _find_button_with_text(
				profile_editor_page,
				"花房咖啡馆",
			)
			_expect(
				first_workplace_option != null and not first_workplace_option.disabled,
				"resident profile editor exposes an available workplace choice",
			)
			if first_workplace_option != null and not first_workplace_option.disabled:
				first_workplace_option.emit_signal("pressed")
				await process_frame
		var current_after_workplace := (
			_adapter.custom_resident_creator_service.call("get_view_model")
			as Dictionary
		)
		_expect_equal(
			(
				(current_after_workplace.get("data", {}) as Dictionary).get(
					"draft",
					{},
				) as Dictionary
			).get("workplaceId"),
			"花房咖啡馆",
			"resident profile editor stores the selected workplace in the draft",
		)
		var resolved_appearance := (
			(editor_view_model.get("data", {}) as Dictionary).get(
				"resolvedAppearance",
				{},
			) as Dictionary
		)
		_expect_equal(
			resolved_appearance.get("appearanceId"),
			"resident_wardrobe_v1:look_01",
			"resident profile editor resolves the persisted formal appearance id",
		)
		_expect_equal(
			resolved_appearance.get("loadoutId"),
			"look_01",
			"resident profile editor resolves the persisted formal loadout",
		)
		_expect(
			bool(resolved_appearance.get("formalReady", false))
			and bool(resolved_appearance.get("directionSetReady", false))
			and ResourceLoader.exists(
				String(resolved_appearance.get("restPath", "")),
				"Texture2D",
			),
			"resident profile editor exposes a complete formal direction set",
		)
		var wardrobe_button := profile_editor_page.find_child(
			"OpenWardrobeButton",
			true,
			false,
		) as BaseButton
		_expect(
			wardrobe_button != null and not wardrobe_button.disabled,
			"profile wardrobe child route is clickable",
		)
		var pause_count_before_wardrobe := _dispatch_count(
			"lifecycle.pause",
			{"reason": "resident_editor"},
		)
		var resume_count_before_wardrobe := _dispatch_count(
			"lifecycle.resume",
			{"reason": "resident_editor"},
		)
		if wardrobe_button != null:
			wardrobe_button.emit_signal("pressed")
		await process_frame
		await process_frame
		_expect_equal(
			_host.call("current_route"),
			&"resident_profile_editor",
			"profile wardrobe stays inside the reused custom resident page",
		)
		var wardrobe_popup := profile_editor_page.find_child(
			"CompleteSetWardrobePopup",
			true,
			false,
		) as PopupPanel
		_expect(
			wardrobe_popup != null and wardrobe_popup.visible,
			"profile wardrobe reuses the formal complete-set popup",
		)
		var next_loadout_card := profile_editor_page.find_child(
			"CompleteSetCard_look_02",
			true,
			false,
		) as BaseButton
		_expect(
			next_loadout_card != null and not next_loadout_card.disabled,
			"profile wardrobe exposes another complete loadout",
		)
		if next_loadout_card != null:
			next_loadout_card.emit_signal("pressed")
		await process_frame
		await process_frame
		var updated_editor_view_model := (
			_adapter.custom_resident_creator_service.call("get_view_model")
			as Dictionary
		)
		var updated_resolved_appearance := (
			(updated_editor_view_model.get("data", {}) as Dictionary).get(
				"resolvedAppearance",
				{},
			) as Dictionary
		)
		_expect_equal(
			updated_resolved_appearance.get("loadoutId"),
			"look_02",
			"profile wardrobe applies the selected complete loadout to the draft",
		)
		_expect(
			wardrobe_popup == null or not wardrobe_popup.visible,
			"selecting a complete loadout closes the wardrobe popup",
		)
		_expect_equal(
			_host.call("current_route"),
			&"resident_profile_editor",
			"wardrobe selection returns to the same resident profile draft",
		)
		_expect_equal(
			_dispatch_count("lifecycle.pause", {"reason": "resident_editor"}),
			pause_count_before_wardrobe,
			"wardrobe popup does not acquire resident-editor pause twice",
		)
		_expect_equal(
			_dispatch_count("lifecycle.resume", {"reason": "resident_editor"}),
			resume_count_before_wardrobe,
			"wardrobe popup keeps the resident editor pause active",
		)
		profile_editor_page = _active_route_page()
		var cancel_button := profile_editor_page.find_child(
			"CancelButton",
			true,
			false,
		) as BaseButton
		_expect(cancel_button != null and not cancel_button.disabled, "profile cancel is clickable")
		if cancel_button != null:
			_adapter.fail_next_lifecycle_resume = true
			cancel_button.emit_signal("pressed")
			await process_frame
			var discard_confirmation := profile_editor_page.find_child(
				"UnsavedProfileConfirmation",
				true,
				false,
			) as Control
			_expect(
				discard_confirmation != null and discard_confirmation.visible,
				"dirty wardrobe selection asks before discarding profile changes",
			)
			if discard_confirmation != null:
				discard_confirmation.emit_signal("confirmed")
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"resident_profile_editor",
		"profile editor resume failure keeps the editor and paused World ownership active",
	)
	profile_editor_page = _active_route_page()
	if profile_editor_page != null:
		var cancel_button := profile_editor_page.find_child(
			"CancelButton",
			true,
			false,
		) as BaseButton
		if cancel_button != null:
			cancel_button.emit_signal("pressed")
			await process_frame
			var discard_confirmation := profile_editor_page.find_child(
				"UnsavedProfileConfirmation",
				true,
				false,
			) as Control
			if discard_confirmation != null:
				discard_confirmation.emit_signal("confirmed")
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"resident_management",
		"profile cancel returns to resident management",
	)
	_expect_dispatch("lifecycle.resume", {"reason": "resident_editor"})
	management_page = _active_route_page()
	if management_page != null:
		var restored := management_page.call("debug_snapshot") as Dictionary
		_expect_equal(
			restored.get("selectedResidentId"),
			"resident-lin",
			"profile cancel preserves the selected resident",
		)
		var modify_again := management_page.find_child(
			"PrimaryActionButton", true, false
		) as BaseButton
		if modify_again != null:
			modify_again.emit_signal("pressed")
	await process_frame
	await process_frame
	profile_editor_page = _active_route_page()
	if profile_editor_page != null:
		var saved_home_option := profile_editor_page.find_child(
			"OwnedPlaceOption",
			true,
			false,
		) as BaseButton
		if saved_home_option != null and not saved_home_option.disabled:
			saved_home_option.emit_signal("pressed")
			await process_frame
			var saved_home_choice := _find_button_with_text(
				profile_editor_page,
				"北街一号住宅",
			)
			if saved_home_choice != null and not saved_home_choice.disabled:
				saved_home_choice.emit_signal("pressed")
				await process_frame
		var saved_workplace_option := profile_editor_page.find_child(
			"WorkplaceOption",
			true,
			false,
		) as BaseButton
		if saved_workplace_option != null and not saved_workplace_option.disabled:
			saved_workplace_option.emit_signal("pressed")
			await process_frame
			var saved_workplace_choice := _find_button_with_text(
				profile_editor_page,
				"花房咖啡馆",
			)
			if saved_workplace_choice != null and not saved_workplace_choice.disabled:
				saved_workplace_choice.emit_signal("pressed")
				await process_frame
		var save_button := profile_editor_page.find_child(
			"CreateButton",
			true,
			false,
		) as BaseButton
		_expect(save_button != null and not save_button.disabled, "profile save is clickable")
		if save_button != null:
			save_button.emit_signal("pressed")
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"resident_management",
		"profile save returns to resident management",
	)
	_expect_dispatch("lifecycle.resume", {"reason": "resident_editor"})
	management_page = _active_route_page()
	if management_page != null:
		var saved_return := management_page.call("debug_snapshot") as Dictionary
		_expect_equal(
			saved_return.get("selectedResidentId"),
			"resident-lin",
			"profile save preserves the selected resident",
		)
		var saved_overview := _adapter.get_view_model("resident_overview") as Dictionary
		var saved_residents := (
			(saved_overview.get("data", {}) as Dictionary).get("residents", []) as Array
		)
		for resident_value: Variant in saved_residents:
			if (
				resident_value is Dictionary
				and String((resident_value as Dictionary).get("residentId", ""))
					== "resident-lin"
			):
				_expect_equal(
					(resident_value as Dictionary).get("homeLabel"),
					"北街一号住宅",
					"profile save persists the selected home in the production entry",
				)
				_expect_equal(
					(resident_value as Dictionary).get("workplaceLabel"),
					"花房咖啡馆",
					"profile save persists the selected workplace in the production entry",
				)
				break
	_expect_dispatch("resident_overview.update_profile", {
		"residentId": "resident-lin",
	})
	if management_page != null:
		var detail_button := management_page.find_child(
			"TertiaryActionButton",
			true,
			false,
		) as BaseButton
		_expect(detail_button != null and not detail_button.disabled, "resident detail entry is clickable")
		if detail_button != null:
			detail_button.emit_signal("pressed")
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"resident_detail",
		"resident detail entry opens the dedicated detail owner",
	)
	_expect(bool(_host.call("request_back")), "resident detail back returns to overview")
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"resident_management",
		"resident detail returns to resident overview",
	)
	management_page = _active_route_page()
	if management_page != null:
		var detail_return := management_page.call("debug_snapshot") as Dictionary
		_expect_equal(
			detail_return.get("selectedResidentId"),
			"resident-lin",
			"resident detail return preserves the selected resident",
		)
		var follow_button := management_page.find_child(
			"SecondaryActionButton",
			true,
			false,
		) as BaseButton
		_expect(follow_button != null and not follow_button.disabled, "follow entry is clickable")
		if follow_button != null:
			follow_button.emit_signal("pressed")
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"town",
		"successful follow closes resident overview to the Town camera",
	)
	_expect_dispatch("resident_overview.follow", {
		"residentId": "resident-lin",
	})

	var resident_editor_open := _host.call(
		"open_page",
		&"resident_editor",
		{"origin": "pause_resident_management"},
	) as Dictionary
	_expect(
		not bool(resident_editor_open.get("ok", true)),
		"ResidentEditor mounting stays blocked until a dedicated route is frozen",
	)
	_expect_equal(
		resident_editor_open.get("errorCode"),
		"TOWN_UI_ROUTE_UNKNOWN",
		"retired ResidentEditor route is absent from the runtime host",
	)
	_expect_equal(
		_host.call("current_route"),
		&"town",
		"blocked ResidentEditor request leaves Town as the active route",
	)
	_expect_single_active_page("blocked ResidentEditor route", 0)
	var resident_editor_context_seen := false
	for context_record: Dictionary in _adapter.page_contexts:
		if String(context_record.get("scope", "")) == "resident_editor":
			resident_editor_context_seen = true
			break
	_expect(
		not resident_editor_context_seen,
		"blocked ResidentEditor request never opens its Adapter page context",
	)
	_expect_equal(
		get_root().get_viewport().gui_get_focus_owner(),
		focus_probe,
		"blocked ResidentEditor request does not disturb Town focus",
	)

	var event_open := _host.call(
		"open_page",
		&"bulletin_board",
		{"announcementId": "announcement-1"},
	) as Dictionary
	_expect(bool(event_open.get("ok", false)), "formal bulletin route opens through its owner")
	await process_frame
	_expect_equal(_host.call("current_route"), &"bulletin_board", "event HUD intent opens bulletin route")
	_expect_single_active_page("event route")
	_expect_context("announcements", true, {"announcementId": "announcement-1"})
	var bulletin_page := _active_route_page()
	if bulletin_page != null:
		_expect(
			bool(bulletin_page.call("debug_request_action", "openComposer", {})),
			"bulletin composer opens for caret stability coverage",
		)
		await process_frame
		var bulletin_surface := (
			bulletin_page.call("_active_surface") as Dictionary
		)
		var bulletin_editor := bulletin_surface.get("editor") as TextEdit
		_expect(
			bulletin_editor != null,
			"bulletin active composition exposes its editor",
		)
		if bulletin_editor != null:
			var draft_text := "今天下午三点开会"
			bulletin_editor.text = draft_text
			bulletin_editor.set_caret_line(0)
			bulletin_editor.set_caret_column(4)
			bulletin_editor.text_changed.emit()
			bulletin_page.call("_flush_draft_intent")
			var draft_timer := bulletin_page.get("_draft_timer") as Timer
			if draft_timer != null:
				draft_timer.stop()
			_expect_equal(
				bulletin_editor.text,
				draft_text,
				"bulletin draft synchronization preserves local text",
			)
			_expect_equal(
				bulletin_editor.get_caret_column(),
				4,
				"bulletin draft synchronization preserves caret column",
			)
			bulletin_editor.text = ""
			bulletin_editor.set_caret_column(0)
			bulletin_editor.text_changed.emit()
			bulletin_page.call("_flush_draft_intent")
			if draft_timer != null:
				draft_timer.stop()
	_expect(
		bool(_host.call("request_back")),
		"bulletin ESC/back delegates to its formal close action",
	)
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"town",
		"bulletin closes after its ViewModel confirms panel.open=false",
	)

	_adapter.dispatch("avatar.focus_target", {"residentId": "resident-lin"})
	var resident_action_payload := {
		"residentId": "resident-lin",
		"residentName": "林岚",
	}
	_host.call(
		"_on_hud_intent_requested",
		&"town_hud.open_resident_action",
		resident_action_payload,
	)
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"resident_action_menu",
		"resident HUD bubble intent opens resident action menu",
	)
	_expect_context("resident_action_menu", true, resident_action_payload)
	_expect_dispatch("avatar.focus_target", {"residentId": "resident-lin"})
	_expect_single_active_page("resident focus route")
	var resident_action_page := _active_route_page()
	var resident_action_halos: Array[Node] = []
	if resident_action_page != null:
		resident_action_halos = resident_action_page.find_children(
			"HaloAsset",
			"TextureRect",
			true,
			false,
		)
	_expect_equal(
		resident_action_halos.size(),
		0,
		"world resident action menu removes the rectangular halo layer",
	)
	# Simulate an Adapter rebind/session refresh that reset only its lifecycle
	# phase while the Host and resident menu stayed mounted.
	var resident_view_begin_count_before_inner := (
		_adapter.resident_view_begin_count
	)
	_adapter.resident_view_phase = "running"
	_host.call(
		"_on_resident_action_intent",
		&"resident.inner_observation.open",
		{"residentId": "resident-lin"},
		1,
		"inner-navigation-open",
	)
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"inner_observation",
		"resident inner action opens its formal page immediately",
	)
	_expect_equal(
		_adapter.resident_view_begin_count,
		resident_view_begin_count_before_inner + 1,
		"resident inner action resynchronizes a stale Adapter lifecycle phase",
	)
	_expect_dispatch(
		"resident.inner_observation.open",
		{"residentId": "resident-lin"},
	)
	_expect_single_active_page("resident inner route")
	var inner_page := _active_route_page()
	_adapter.fail_next_inner_observation_exit = true
	_expect(
		bool(inner_page.call("request_exit")),
		"inner observation submits its first exit request",
	)
	var rejected_exit_state := inner_page.call("debug_state") as Dictionary
	_expect_equal(
		rejected_exit_state.get("exitPending"),
		false,
		"an immediate exit rejection releases the local pending state",
	)
	_expect_equal(
		_host.call("current_route"),
		&"inner_observation",
		"an immediate exit rejection keeps the current page available for retry",
	)
	_expect(
		bool(inner_page.call("request_exit")),
		"inner observation accepts a retry after immediate rejection",
	)
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"town",
		"resident inner exit releases its resident view",
	)

	_adapter.publish("conversation", {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"displayMode": "player",
		"conversationId": "conversation-1",
		"residentId": "resident-lin",
		"residentName": "林岚",
		"messages": [],
		"canAttachPhoto": false,
	})
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"chat",
		"approved MapChat route opens from authoritative conversation data",
	)
	_expect_single_active_page("conversation route")
	var chat_page := _active_route_page()
	_expect(chat_page != null, "conversation route has one MapChat owner")
	if chat_page != null:
		var chat_snapshot := chat_page.call("runtime_gate_snapshot") as Dictionary
		_expect_equal(
			chat_snapshot.get("sourceMode"),
			"town_ui_adapter",
			"formal MapChat never loads its placeholder fixture",
		)
		_expect_equal(
			chat_snapshot.get("source"),
			"runtime",
			"formal MapChat renders authoritative runtime data",
		)
		_expect(
			bool(chat_snapshot.get("referenceLockedWide", false)),
			"1920 baseline keeps the user-approved reference-locked MapChat layout; snapshot=%s root=%s host=%s" % [
				chat_snapshot,
				root.size,
				_host.size,
			],
		)
		_expect(
			not bool(chat_snapshot.get("canAttachPhoto", true))
			and bool(chat_snapshot.get("photoButtonDisabled", false))
			and bool(chat_snapshot.get("originalSendDisabled", false)),
			"missing photo API stays honestly disabled in formal MapChat",
		)
		var chat_focus_owner := get_root().get_viewport().gui_get_focus_owner()
		_expect(
			chat_focus_owner != null and chat_page.is_ancestor_of(chat_focus_owner),
			"MapChat gives initial focus to its own enabled control",
		)
		var draft := chat_page.get("_draft_edit") as TextEdit
		draft.text = "这句还没有发送"
		draft.text_changed.emit()
		var dispatches_before_unsent_back := _adapter.dispatches.size()
		_expect(
			bool(_host.call("request_back")),
			"MapChat ESC/back 没有交给页面处理未发送草稿",
		)
		var confirmation := (
			chat_page.get("_close_confirmation") as FormalConfirmationDialog
		)
		_expect(
			_adapter.dispatches.size() == dispatches_before_unsent_back
			and confirmation.visible,
			"GameFlow ESC/back 绕过了未发送草稿确认",
		)
		confirmation.hide()
		draft.text = ""
		draft.text_changed.emit()
	var dispatch_count_before_chat_back := _adapter.dispatches.size()
	_expect(bool(_host.call("request_back")), "MapChat ESC/back requests a real conversation end")
	_expect_equal(
		_adapter.dispatches.size(),
		dispatch_count_before_chat_back + 1,
		"MapChat ESC/back dispatches exactly one business operation",
	)
	_expect_dispatch(
		"conversation.end",
		{"narration": "旅行者结束交谈"},
	)
	_expect_equal(
		_host.call("current_route"),
		&"chat",
		"MapChat remains mounted until runtime confirms conversation end",
	)

	_adapter.publish("conversation", {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"displayMode": "player",
		"conversationId": "",
		"residentId": "resident-lin",
		"residentName": "林岚",
		"messages": [],
		"canAttachPhoto": false,
	})
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"town",
		"authoritative conversation end closes MapChat",
	)
	_expect_single_active_page("conversation end returns to town", 0)
	_expect_equal(
		get_root().get_viewport().gui_get_focus_owner(),
		focus_probe,
		"authoritative MapChat close restores the pre-route focus owner",
	)

	_adapter.prepare_missing_spectator_contract()
	var missing_spectator_open := _host.call(
		"open_page",
		&"conversation_spectator",
		{"origin": "navigation-test"},
	) as Dictionary
	_expect(
		bool(missing_spectator_open.get("ok", false)),
		"approved ConversationSpectator route opens through its unique owner",
	)
	await process_frame
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"conversation_spectator",
		"explicit spectator entry selects its formal route",
	)
	_expect_single_active_page("missing spectator contract route")
	var missing_spectator_page := _active_route_page()
	_expect(missing_spectator_page != null, "missing spectator contract still mounts the approved page")
	if missing_spectator_page != null:
		var missing_snapshot := missing_spectator_page.call("runtime_gate_snapshot") as Dictionary
		_expect_equal(
			missing_snapshot.get("sourceMode"),
			"town_ui_adapter",
			"formal spectator page only consumes TownUiAdapter",
		)
		_expect_equal(
			missing_snapshot.get("adapterInstanceId"),
			_adapter.get_instance_id(),
			"spectator page receives the host's exact Adapter instance",
		)
		_expect_equal(
			missing_snapshot.get("contractFailureCode"),
			"SPECTATOR_INTERFACE_MISSING",
			"missing data.spectator renders the stable honest interface error",
		)
		_expect(
			not bool(missing_snapshot.get("runtimeMockUsed", true)),
			"formal spectator route never reads its test fixture",
		)
		var missing_focus_owner := get_root().get_viewport().gui_get_focus_owner()
		_expect(
			missing_focus_owner != null
			and missing_spectator_page.is_ancestor_of(missing_focus_owner)
			and String(missing_focus_owner.name) == "CloseConversationButton",
			"missing spectator contract focuses its real close control",
		)
		var missing_spectator_escape := InputEventAction.new()
		missing_spectator_escape.action = &"ui_cancel"
		missing_spectator_escape.pressed = true
		missing_spectator_page.call("_unhandled_input", missing_spectator_escape)
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"town",
		"spectator close_requested returns to town",
	)
	_expect_single_active_page("spectator close_requested", 0)

	var closed_spectator_data := _adapter.spectator_data()
	(closed_spectator_data.get("spectator", {}) as Dictionary)["panelOpen"] = false
	_adapter.publish("conversation", closed_spectator_data)
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"town",
		"spectator availability does not auto-open a closed spectator panel",
	)
	_adapter.publish("conversation", _adapter.spectator_data())
	await process_frame
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"conversation_spectator",
		"authoritative spectator displayMode opens the approved v8 route",
	)
	_expect_single_active_page("authoritative spectator entry")
	var spectator_page := _active_route_page()
	_expect(spectator_page != null, "authoritative spectator entry has one page owner")
	if spectator_page != null:
		var spectator_snapshot := spectator_page.call("runtime_gate_snapshot") as Dictionary
		_expect(
			bool(spectator_snapshot.get("contractAvailable", false))
			and bool(spectator_snapshot.get("formalReady", false)),
			"complete authoritative spectator data renders the formal v8 page",
		)
		_expect_equal(
			spectator_snapshot.get("adapterInstanceId"),
			_adapter.get_instance_id(),
			"authoritative spectator page keeps the host's exact Adapter",
		)
		var spectator_focus_owner := get_root().get_viewport().gui_get_focus_owner()
		_expect(
			spectator_focus_owner != null
			and spectator_page.is_ancestor_of(spectator_focus_owner),
			"formal spectator page owns initial keyboard focus",
		)
		var spectator_dispatch_count := _adapter.dispatches.size()
		_expect(
			bool(spectator_page.call(
				"_request_action",
				"selectSpectatorConversation",
				{"conversationId": "conversation-spectator-1"},
			)),
			"spectator intent_requested accepts the declared Adapter action",
		)
		_expect_equal(
			_adapter.dispatches.size(),
			spectator_dispatch_count + 1,
			"spectator intent is dispatched exactly once through the page Adapter",
		)
		_expect_dispatch(
			"conversation.spectator.select",
			{"conversationId": "conversation-spectator-1"},
		)

	_adapter.publish("conversation", {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"displayMode": "player",
		"conversationId": "conversation-player-switch",
		"residentId": "resident-lin",
		"residentName": "林岚",
		"messages": [],
		"canAttachPhoto": false,
	})
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"chat",
		"displayMode=player replaces spectator with MapChat",
	)
	_expect_single_active_page("spectator to player switch")
	var player_switch_page := _active_route_page()
	_expect(
		player_switch_page != null
		and String(player_switch_page.name) == "ChatRoute",
		"player and spectator owners never render together",
	)
	_adapter.publish("conversation", _adapter.spectator_data())
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"conversation_spectator",
		"displayMode=spectator replaces MapChat with the v8 spectator page",
	)
	_expect_single_active_page("player to spectator switch")
	spectator_page = _active_route_page()

	var retired_spectator_page := spectator_page
	var reopen_spectator := _host.call(
		"open_page",
		&"conversation_spectator",
		{"origin": "reopen"},
	) as Dictionary
	_expect(bool(reopen_spectator.get("ok", false)), "spectator route supports deterministic reopen")
	var current_spectator_page := _active_route_page()
	if is_instance_valid(retired_spectator_page):
		retired_spectator_page.emit_signal("close_requested")
	_expect_equal(
		_host.call("current_route"),
		&"conversation_spectator",
		"late close from retired spectator owner cannot close the replacement",
	)
	await process_frame
	await process_frame
	_expect_single_active_page("spectator route reopened")
	current_spectator_page = _active_route_page()
	var current_conversation_vm := (
		_adapter.view_models.get("conversation", {}) as Dictionary
	).duplicate(true)
	var stale_conversation_vm := current_conversation_vm.duplicate(true)
	stale_conversation_vm["revision"] = int(current_conversation_vm.get("revision", 1)) - 1
	stale_conversation_vm["data"] = {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"displayMode": "player",
		"conversationId": "",
		"messages": [],
		"canAttachPhoto": false,
	}
	_adapter.emit_view_model("conversation", stale_conversation_vm)
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"conversation_spectator",
		"late conversation revision cannot replace or close the spectator route",
	)
	_expect_equal(
		(current_spectator_page.call("runtime_gate_snapshot") as Dictionary).get("revision"),
		current_conversation_vm.get("revision"),
		"spectator page rejects a late revision without regressing its render",
	)
	_expect(
		bool(_host.call("request_back")),
		"GameFlow ESC/back closes the read-only spectator route locally",
	)
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"town",
		"ConversationSpectator ESC returns to town",
	)
	_expect_single_active_page("ConversationSpectator ESC", 0)
	_expect_equal(
		get_root().get_viewport().gui_get_focus_owner(),
		focus_probe,
		"ConversationSpectator ESC restores the pre-route focus owner",
	)
	_adapter.publish("conversation", {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"displayMode": "player",
		"conversationId": "",
		"residentId": "",
		"residentName": "",
		"messages": [],
		"canAttachPhoto": false,
	})
	await process_frame

	var payload := {"origin": "navigation-test", "residentId": "resident-lin"}
	var first_open := _host.call("open_page", &"resident_action_menu", payload) as Dictionary
	var second_open := _host.call("open_page", &"resident_action_menu", payload) as Dictionary
	_expect(bool(first_open.get("ok", false)) and bool(second_open.get("ok", false)), "reopening same route succeeds")
	await process_frame
	await process_frame
	_expect_single_active_page("same route reopened")
	_expect_context("resident_action_menu", true, payload)

	var weather_open := _host.call("open_page", &"weather_control", {}) as Dictionary
	_expect(bool(weather_open.get("ok", false)), "approved Weather route opens")
	await process_frame
	await process_frame
	_expect_equal(_host.call("current_route"), &"weather_control", "Weather owns the active route")
	_expect_single_active_page("Weather route")
	var weather_page := _active_route_page()
	_expect(weather_page != null, "Weather route has one runtime page")
	if weather_page != null:
		var weather_snapshot := weather_page.call("debug_snapshot") as Dictionary
		_expect_equal(weather_snapshot.get("source"), "runtime", "Weather consumes runtime data")
		_expect_equal(weather_snapshot.get("capabilityMode"), "formal", "Weather uses formal capability")
		_expect(bool(weather_snapshot.get("formalReady", false)), "Weather is formally ready")
		_expect_equal(
			(weather_page.get("_adapter") as Node).get_instance_id(),
			_adapter.get_instance_id(),
			"Weather receives the host's exact Adapter",
		)
		_expect(
			weather_page.get_node_or_null("WeatherControlPlaceholderAdapter") == null,
			"formal Weather never starts its placeholder Adapter",
		)
		var weather_focus := get_root().get_viewport().gui_get_focus_owner()
		_expect(
			weather_focus != null and weather_page.is_ancestor_of(weather_focus),
			"Weather owns initial focus",
		)
		var development_data := (
			_adapter._weather_view_model().get("data", {}) as Dictionary
		).duplicate(true)
		development_data["capabilityMode"] = "development"
		development_data["formalReady"] = false
		development_data["internalPlaytest"] = true
		_adapter.publish("weather_control", development_data)
		await process_frame
		var development_dispatch_count := _adapter.dispatches.size()
		_expect(
			bool(weather_page.call("debug_select_weather", "rainy")),
			"internal Weather selects a runtime option",
		)
		weather_page.call("_on_confirm_pressed")
		_expect_equal(
			_adapter.dispatches.size(),
			development_dispatch_count + 1,
			"explicit runtime/development internalPlaytest may dispatch",
		)
		_expect_dispatch("environment.weather_change", {"weatherId": "rainy"})
		development_data["internalPlaytest"] = false
		_adapter.publish("weather_control", development_data)
		await process_frame
		var unauthorized_dispatch_count := _adapter.dispatches.size()
		weather_page.call("debug_select_weather", "rainy")
		weather_page.call("_on_confirm_pressed")
		_expect_equal(
			_adapter.dispatches.size(),
			unauthorized_dispatch_count,
			"runtime/development without internalPlaytest cannot dispatch",
		)
	_expect(bool(_host.call("request_back")), "Weather ESC/back handles an unsaved selection")
	var weather_confirmation := (
		weather_page.get_node_or_null("UnsavedWeatherConfirmation") as FormalConfirmationDialog
		if weather_page != null
		else null
	)
	_expect(
		weather_confirmation != null and weather_confirmation.visible,
		"Weather asks before discarding an unconfirmed selection",
	)
	_expect(bool(_host.call("request_back")), "repeated Weather ESC remains handled")
	_expect_equal(
		_host.call("current_route"),
		&"weather_control",
		"repeated Weather ESC cannot bypass the discard confirmation",
	)
	_expect(
		weather_confirmation != null and weather_confirmation.visible,
		"Weather confirmation remains visible after repeated ESC",
	)
	if weather_confirmation != null:
		weather_confirmation.confirmed.emit()
	await process_frame
	_expect_equal(_host.call("current_route"), &"town", "Weather returns to town")
	_expect_equal(get_root().get_viewport().gui_get_focus_owner(), focus_probe, "Weather restores focus")

	var town_log_open := _host.call("open_page", &"town_log", {}) as Dictionary
	_expect(bool(town_log_open.get("ok", false)), "approved TownLog route opens")
	await process_frame
	await process_frame
	_expect_equal(_host.call("current_route"), &"town_log", "TownLog owns the active route")
	_expect_single_active_page("TownLog route")
	var town_log_page := _active_route_page()
	_expect(town_log_page != null, "TownLog route has one runtime page")
	if town_log_page != null:
		var town_log_snapshot := town_log_page.call("runtime_gate_snapshot") as Dictionary
		_expect_equal(town_log_snapshot.get("sourceMode"), "town_ui_adapter", "formal TownLog never loads a fixture")
		_expect_equal(town_log_snapshot.get("source"), "runtime", "TownLog consumes runtime data")
		_expect(bool(town_log_snapshot.get("formalReady", false)), "TownLog is formally ready")
		_expect_equal(
			(town_log_page.get("_adapter") as Node).get_instance_id(),
			_adapter.get_instance_id(),
			"TownLog receives the host's exact Adapter",
		)
		var town_log_focus := get_root().get_viewport().gui_get_focus_owner()
		_expect(
			town_log_focus != null and town_log_page.is_ancestor_of(town_log_focus),
			"TownLog owns initial focus",
		)
	_expect(bool(_host.call("request_back")), "TownLog ESC/back closes locally")
	await process_frame
	_expect_equal(_host.call("current_route"), &"town", "TownLog returns to town")
	_expect_equal(get_root().get_viewport().gui_get_focus_owner(), focus_probe, "TownLog restores focus")

	var place_focus_open := _host.call(
		"open_page",
		&"place_focus",
		{"placeName": "图书馆"},
	) as Dictionary
	_expect(bool(place_focus_open.get("ok", false)), "observer place intent opens PlaceFocus")
	await process_frame
	await process_frame
	_expect_equal(_host.call("current_route"), &"place_focus", "PlaceFocus owns the active route")
	_expect_single_active_page("PlaceFocus route")
	_adapter.emit_operation("place_focus", "place_focus.enter_interior", "rejected")
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"place_focus",
		"rejected interior entry preserves PlaceFocus and its confirmed data",
	)
	_adapter.publish("indoor", _adapter._indoor_view_model(true).get("data", {}) as Dictionary)
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"place_focus",
		"interior data alone does not replace the explicit PlaceFocus owner",
	)
	_adapter.emit_operation("place_focus", "place_focus.enter_interior", "success")
	await process_frame
	await process_frame
	_expect_equal(
		_host.call("current_route"),
		&"indoor",
		"confirmed PlaceFocus entry opens Indoor without a town-route intermediate",
	)
	_expect_equal(_host.call("current_route"), &"indoor", "explicit Indoor route owns the page")
	_expect_single_active_page("Indoor route")
	var indoor_page := _active_route_page()
	_expect(indoor_page != null, "Indoor route has one runtime page")
	if indoor_page != null:
		var indoor_snapshot := indoor_page.call("runtime_gate_snapshot") as Dictionary
		_expect_equal(indoor_snapshot.get("sourceMode"), "town_ui_adapter", "formal Indoor never loads a fixture")
		_expect(bool(indoor_snapshot.get("formalReady", false)), "Indoor is formally ready")
		_expect_equal(
			(indoor_page.get("_adapter") as Node).get_instance_id(),
				_adapter.get_instance_id(),
				"Indoor receives the host's exact Adapter",
			)
		_host.get_node("SystemFeedbackLayer").call(
			"clear_scope",
			&"navigation",
			false,
		)
		var feedback_revision_before_failed_resident_open := int(
			_host.get("_navigation_feedback_revision")
		)
		var resident_view_finish := _host.call(
			"_finish_resident_view",
		) as Dictionary
		_expect(
			bool(resident_view_finish.get("ok", false)),
			"Indoor failure setup restores the normal unpaused resident-view state",
		)
		_adapter.fail_next_resident_view_begin = true
		_host.call(
			"_open_indoor_resident_action_menu",
			{"residentId": "resident-lin"},
		)
		await process_frame
		await process_frame
		_expect_equal(
			_host.call("current_route"),
			&"indoor",
			"failed resident action open restores Indoor",
		)
		var failed_resident_feedback_snapshot := (
			_host.get_node("SystemFeedbackLayer").call(
				"runtime_gate_snapshot",
			) as Dictionary
		)
		var failed_resident_feedback_identity := "navigation-%d" % int(
			_host.get("_navigation_feedback_revision")
		)
		_expect(
			int(_host.get("_navigation_feedback_revision"))
				> feedback_revision_before_failed_resident_open
			and (
				failed_resident_feedback_snapshot.get(
					"activeToastIdentities",
					[],
				) as Array
			).has(failed_resident_feedback_identity),
			"failed resident action open remains visibly explained after Indoor restore",
		)
		_host.get_node("SystemFeedbackLayer").call(
			"clear_scope",
			&"navigation",
			false,
		)
	var indoor_dispatch_count := _adapter.dispatches.size()
	_expect(bool(_host.call("request_back")), "Indoor ESC/back requests the real outdoor transition")
	_expect_equal(_adapter.dispatches.size(), indoor_dispatch_count + 1, "Indoor back dispatches once")
	_expect_dispatch("indoor.return_outdoor", {})
	_expect_equal(_host.call("current_route"), &"indoor", "Indoor remains until operation confirmation")
	_adapter.emit_operation("indoor", "indoor.return_outdoor", "rejected")
	await process_frame
	_expect_equal(_host.call("current_route"), &"indoor", "rejected Indoor exit preserves the page")
	_adapter.emit_operation("indoor", "indoor.return_outdoor", "success")
	await process_frame
	await process_frame
	_expect_equal(_host.call("current_route"), &"town", "confirmed Indoor exit returns to town")
	_expect_equal(get_root().get_viewport().gui_get_focus_owner(), focus_probe, "Indoor exit restores focus")

	var wardrobe_open := _host.call("open_page", &"wardrobe", {}) as Dictionary
	_expect(bool(wardrobe_open.get("ok", false)), "authorized formal Wardrobe route opens")
	await process_frame
	await process_frame
	_expect_equal(_host.call("current_route"), &"wardrobe", "Wardrobe owns the active route")
	_expect_single_active_page("Wardrobe route")
	var wardrobe_page := _active_route_page()
	_expect(wardrobe_page != null, "Wardrobe route has one runtime page")
	if wardrobe_page != null:
		var wardrobe_snapshot := wardrobe_page.call("debug_snapshot") as Dictionary
		_expect_equal(wardrobe_snapshot.get("scope"), "wardrobe", "Wardrobe keeps its formal Adapter scope")
		_expect_equal(wardrobe_snapshot.get("handoffReady"), false, "Wardrobe does not fake a missing formal handoff")
		_expect_equal(wardrobe_snapshot.get("saveWritesFormalData"), false, "Wardrobe does not fake a formal save")
		_expect(bool(wardrobe_snapshot.get("formalReady", false)), "Wardrobe exposes formal readiness")
		_expect_equal(wardrobe_snapshot.get("assetStatus"), "formal", "Wardrobe uses formal catalog assets")
		_expect_equal(
			wardrobe_snapshot.get("usesTemporaryApproximateAssets"),
			false,
			"Wardrobe does not use temporary approximate assets",
		)
		_expect_equal(
			(wardrobe_page.get("_adapter") as Node).get_instance_id(),
			_adapter.get_instance_id(),
			"Wardrobe receives the host's exact Adapter",
		)
	_expect(bool(_host.call("request_back")), "Wardrobe ESC/back closes locally")
	await process_frame
	_expect_equal(_host.call("current_route"), &"town", "Wardrobe returns to town")
	_expect_equal(get_root().get_viewport().gui_get_focus_owner(), focus_probe, "Wardrobe restores focus")

	var unknown := _host.call("open_page", &"not_a_real_ui_route", {}) as Dictionary
	_expect(not bool(unknown.get("ok", true)), "unknown route is rejected")
	_expect_equal(unknown.get("errorCode"), "TOWN_UI_ROUTE_UNKNOWN", "unknown route uses stable error")
	_expect_equal(_host.call("current_route"), &"town", "unknown route preserves current page")
	var failed_open_with_feedback := _host.call(
		"_open_page_with_feedback",
		&"not_a_real_ui_route",
		{},
		"测试页面暂时打不开。",
	) as Dictionary
	_expect(
		not bool(failed_open_with_feedback.get("ok", true)),
		"failed navigation remains a failed result",
	)
	await process_frame
	var navigation_feedback_snapshot := (
		_host.get_node("SystemFeedbackLayer").call(
			"runtime_gate_snapshot",
		) as Dictionary
	)
	var navigation_feedback_visible := false
	for identity_value: Variant in navigation_feedback_snapshot.get(
		"activeToastIdentities",
		[],
	) as Array:
		if String(identity_value).begins_with("navigation-"):
			navigation_feedback_visible = true
			break
	_expect(
		navigation_feedback_visible,
		"failed navigation shows a visible non-blocking notice",
	)
	_host.get_node("SystemFeedbackLayer").call(
		"clear_scope",
		&"navigation",
		false,
	)
	await process_frame
	_host.call(
		"present_back_blocked_feedback",
		"测试操作尚未完成。",
	)
	await process_frame
	var back_feedback_snapshot := (
		_host.get_node("SystemFeedbackLayer").call(
			"runtime_gate_snapshot",
		) as Dictionary
	)
	var back_feedback_identity := "navigation-%d" % int(
		_host.get("_navigation_feedback_revision")
	)
	_expect(
		(back_feedback_snapshot.get("activeToastIdentities", []) as Array).has(
			back_feedback_identity,
		),
		"blocked back navigation replaces the navigation scope with a visible notice",
	)
	_expect_equal(
		_host.call("current_route"),
		&"town",
		"failed navigation feedback does not replace the current page",
	)
	_expect_equal(_direct_child_count("TownHudOverlay"), 1, "route changes never duplicate HUD")
	_expect_equal(_direct_child_count("SystemFeedbackLayer"), 1, "route changes never duplicate feedback")

	_host.call("close_page")
	await process_frame
	focus_probe.grab_focus()
	await process_frame
	var provider_open := _host.call("open_page", &"provider_settings", {}) as Dictionary
	_expect(bool(provider_open.get("ok", false)), "approved Provider route opens through its owner")
	await process_frame
	await process_frame
	await process_frame
	_expect_equal(_host.call("current_route"), &"provider_settings", "Provider route becomes current")
	_expect_context("provider_settings", true, {})
	_expect_single_active_page("Provider route")
	var provider_page := _active_route_page()
	var back_button := (
		provider_page.find_child("BackButton", true, false) as BaseButton
		if provider_page != null
		else null
	)
	_expect(back_button != null, "Provider route exposes its approved BackButton")
	_expect_equal(
		get_root().get_viewport().gui_get_focus_owner(),
		back_button,
		"Provider route gives initial focus to BackButton",
	)
	var provider_input_vm := _provider_input_stability_view_model(10)
	_expect(
		bool(provider_page.call("apply_view_model", provider_input_vm)),
		"Provider route accepts editable input stability data",
	)
	await process_frame
	await process_frame
	var provider_key_edit := provider_page.find_child(
		"ApiKeyInput",
		true,
		false,
	) as LineEdit
	_expect(provider_key_edit != null, "Provider route exposes API Key input")
	if provider_key_edit != null:
		provider_key_edit.grab_focus()
		provider_key_edit.text = "sk-release-review"
		provider_key_edit.text_changed.emit(provider_key_edit.text)
		provider_key_edit.set_caret_column(7)
		provider_key_edit.select(3, 7)
		var refreshed_provider_vm := _provider_input_stability_view_model(11)
		var refreshed_data := refreshed_provider_vm.get("data", {}) as Dictionary
		(refreshed_data.get("providers", []) as Array)[0]["connection"] = {
			"status": "available",
			"label": "连接正常",
			"message": "后台检查刚刚完成。",
		}
		_expect(
			bool(provider_page.call("apply_view_model", refreshed_provider_vm)),
			"Provider route accepts an asynchronous health refresh",
		)
		await process_frame
		await process_frame
		var rebuilt_key_edit := provider_page.find_child(
			"ApiKeyInput",
			true,
			false,
		) as LineEdit
		_expect(
			rebuilt_key_edit != null and rebuilt_key_edit != provider_key_edit,
			"Provider health refresh rebuilds a replacement API Key input",
		)
		if rebuilt_key_edit != null:
			_expect_equal(
				rebuilt_key_edit.text,
				"sk-release-review",
				"Provider health refresh preserves the local API Key draft",
			)
			_expect_equal(
				get_root().get_viewport().gui_get_focus_owner(),
				rebuilt_key_edit,
				"Provider health refresh restores API Key input focus",
			)
			_expect_equal(
				rebuilt_key_edit.get_caret_column(),
				7,
				"Provider health refresh restores API Key caret column",
			)
			_expect(
				rebuilt_key_edit.has_selection()
				and rebuilt_key_edit.get_selection_from_column() == 3
				and rebuilt_key_edit.get_selection_to_column() == 7,
				"Provider health refresh restores API Key selection",
			)
			rebuilt_key_edit.text = ""
			rebuilt_key_edit.text_changed.emit("")
		var provider_base_url_edit := provider_page.find_child(
			"BaseUrlInput",
			true,
			false,
		) as LineEdit
		_expect(provider_base_url_edit != null, "Provider route exposes Base URL input")
		if provider_base_url_edit != null:
			provider_base_url_edit.grab_focus()
			provider_base_url_edit.text = ""
			provider_base_url_edit.text_changed.emit("")
			var empty_base_url_vm := _provider_input_stability_view_model(12)
			_expect(
				bool(provider_page.call("apply_view_model", empty_base_url_vm)),
				"Provider route accepts a refresh after clearing Base URL",
			)
			await process_frame
			await process_frame
			var rebuilt_base_url_edit := provider_page.find_child(
				"BaseUrlInput",
				true,
				false,
			) as LineEdit
			_expect(
				rebuilt_base_url_edit != null
				and rebuilt_base_url_edit != provider_base_url_edit,
				"Provider refresh rebuilds a replacement Base URL input",
			)
			if rebuilt_base_url_edit != null:
				_expect_equal(
					rebuilt_base_url_edit.text,
					"",
					"Provider refresh preserves an intentionally empty Base URL",
				)
				_expect_equal(
					get_root().get_viewport().gui_get_focus_owner(),
					rebuilt_base_url_edit,
					"Provider refresh restores Base URL input focus",
				)
				_expect(
					provider_page.find_child(
						"InsecureHttpWarning",
						true,
						false,
					) == null,
					"Provider route does not use a passive HTTP warning label",
				)
				var remote_http_url := "http://api.example.com:3000/v1"
				var dispatch_count_before_http := _adapter.dispatches.size()
				rebuilt_base_url_edit.text = remote_http_url
				rebuilt_base_url_edit.text_changed.emit(remote_http_url)
				rebuilt_base_url_edit.text_submitted.emit(remote_http_url)
				await process_frame
				var http_confirmation := provider_page.find_child(
					"InsecureHttpConfirmation",
					true,
					false,
				) as FormalConfirmationDialog
				_expect(
					http_confirmation != null
					and http_confirmation.visible
					and http_confirmation.dialog_text.contains("API Key")
					and http_confirmation.dialog_text.contains("居民记忆")
					and http_confirmation.dialog_text.contains("对话内容"),
					"Provider route explains remote HTTP exposure in the formal dialog",
				)
				_expect_equal(
					_adapter.dispatches.size(),
					dispatch_count_before_http,
					"remote HTTP is not saved before confirmation",
				)
				var cancel_http := http_confirmation.find_child(
					"Cancel",
					true,
					false,
				) as Button
				if cancel_http != null:
					cancel_http.pressed.emit()
				_expect_equal(
					_adapter.dispatches.size(),
					dispatch_count_before_http,
					"canceling remote HTTP keeps the draft without saving",
				)
				rebuilt_base_url_edit.text_submitted.emit(remote_http_url)
				await process_frame
				var confirm_http := http_confirmation.find_child(
					"Confirm",
					true,
					false,
				) as Button
				if confirm_http != null:
					confirm_http.pressed.emit()
				_expect_equal(
					_adapter.dispatches.size(),
					dispatch_count_before_http + 1,
					"confirming remote HTTP dispatches one save",
				)
				var http_save := _adapter.dispatches.back() as Dictionary
				_expect_equal(
					http_save.get("intent"),
					"provider_settings.save_base_url",
					"remote HTTP confirmation resumes the original save action",
				)
				_expect_equal(
					(http_save.get("payload", {}) as Dictionary).get(
						"allowInsecureHttp"
					),
					true,
					"remote HTTP confirmation carries explicit consent",
				)
	await _verify_local_provider_url_autodiscovery(
		provider_page as ProviderSettingsScreen,
		"ollama",
		"Ollama（本地）",
		"http://127.0.0.1:11434/v1",
		20,
	)
	await _verify_local_provider_url_autodiscovery(
		provider_page as ProviderSettingsScreen,
		"lm-studio",
		"LM Studio（本地）",
		"http://127.0.0.1:1234/v1",
		30,
	)
	var dispatch_count_before_back := _adapter.dispatches.size()
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	provider_page.call("_unhandled_input", escape)
	await process_frame
	await process_frame
	_expect_equal(_host.call("current_route"), &"town", "Provider ESC returns to town")
	_expect_single_active_page("Provider ESC closes route", 0)
	_expect_equal(
		_adapter.dispatches.size(),
		dispatch_count_before_back,
		"Provider host navigation does not dispatch a fake business operation",
	)
	_expect_equal(
		get_root().get_viewport().gui_get_focus_owner(),
		focus_probe,
		"closing Provider restores the previous formal focus owner",
	)
	_host.queue_free()
	_avatar_hud.queue_free()
	_adapter.queue_free()
	await process_frame
	await process_frame
	return
func _verify_resident_wardrobe_catalog_failure() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
		+ "wardrobe_catalog.json",
	))
	_expect(parsed is Dictionary, "formal resident wardrobe catalog parses")
	if not parsed is Dictionary:
		return
	var catalog := parsed as Dictionary
	var service := RESIDENT_PROFILE_EDITOR_SERVICE_SCRIPT.new()
	var valid_result := service.call(
		"_parse_wardrobe_catalog",
		catalog,
	) as Dictionary
	_expect(
		bool(valid_result.get("ok", false)),
		"resident profile editor accepts the shipped formal wardrobe catalog",
	)
	_expect_equal(
		(valid_result.get("appearances", {}) as Dictionary).size(),
		16,
		"resident profile editor resolves every shipped formal loadout",
	)
	for malformed_schema: Dictionary in [
		{"reason": "null schema", "value": null},
		{"reason": "non-string schema", "value": 1},
	]:
		var corrupted_schema := catalog.duplicate(true)
		corrupted_schema["schema"] = malformed_schema.get("value")
		_expect_resident_wardrobe_catalog_rejected(
			service,
			corrupted_schema,
			String(malformed_schema.get("reason", "")),
		)
	var missing_schema := catalog.duplicate(true)
	missing_schema.erase("schema")
	_expect_resident_wardrobe_catalog_rejected(
		service,
		missing_schema,
		"missing schema",
	)
	for malformed_entry: Dictionary in [
		{"reason": "null head id", "field": "id", "value": null},
		{"reason": "non-string head id", "field": "id", "value": []},
	]:
		var corrupted_head := catalog.duplicate(true)
		var heads := corrupted_head.get("heads", []) as Array
		var first_head := heads[0] as Dictionary
		first_head[String(malformed_entry.get("field", ""))] = (
			malformed_entry.get("value")
		)
		heads[0] = first_head
		corrupted_head["heads"] = heads
		_expect_resident_wardrobe_catalog_rejected(
			service,
			corrupted_head,
			String(malformed_entry.get("reason", "")),
		)
	var missing_head_id := catalog.duplicate(true)
	var heads_without_id := missing_head_id.get("heads", []) as Array
	var head_without_id := heads_without_id[0] as Dictionary
	head_without_id.erase("id")
	heads_without_id[0] = head_without_id
	missing_head_id["heads"] = heads_without_id
	_expect_resident_wardrobe_catalog_rejected(
		service,
		missing_head_id,
		"missing head id",
	)
	var source_loadouts := catalog.get("loadouts", []) as Array
	if source_loadouts.is_empty() or not source_loadouts[0] is Dictionary:
		_expect(false, "formal resident wardrobe catalog has a loadout fixture")
		return
	for field_name: String in [
		"id",
		"appearanceId",
		"label",
		"headId",
		"outfitId",
		"portraitPath",
	]:
		for malformed_value: Variant in [null, 1]:
			var corrupted_loadout := catalog.duplicate(true)
			var malformed_loadouts := (
				corrupted_loadout.get("loadouts", []) as Array
			)
			var malformed_loadout := malformed_loadouts[0] as Dictionary
			malformed_loadout[field_name] = malformed_value
			malformed_loadouts[0] = malformed_loadout
			corrupted_loadout["loadouts"] = malformed_loadouts
			_expect_resident_wardrobe_catalog_rejected(
				service,
				corrupted_loadout,
				"%s %s" % [
					"null" if malformed_value == null else "non-string",
					field_name,
				],
			)
		var missing_loadout_field := catalog.duplicate(true)
		var incomplete_loadouts := (
			missing_loadout_field.get("loadouts", []) as Array
		)
		var incomplete_loadout := incomplete_loadouts[0] as Dictionary
		incomplete_loadout.erase(field_name)
		incomplete_loadouts[0] = incomplete_loadout
		missing_loadout_field["loadouts"] = incomplete_loadouts
		_expect_resident_wardrobe_catalog_rejected(
			service,
			missing_loadout_field,
			"missing %s" % field_name,
		)
	for direction_id: String in ["down", "right", "up"]:
		var corrupted_direction := catalog.duplicate(true)
		var loadouts := corrupted_direction.get("loadouts", []) as Array
		var first_loadout := loadouts[0] as Dictionary
		var directions := first_loadout.get("directions", {}) as Dictionary
		var direction := directions.get(direction_id, {}) as Dictionary
		direction["restPath"] = (
			"res://missing/%s_resident_wardrobe_rest.png" % direction_id
		)
		directions[direction_id] = direction
		first_loadout["directions"] = directions
		loadouts[0] = first_loadout
		corrupted_direction["loadouts"] = loadouts
		_expect_resident_wardrobe_catalog_rejected(
			service,
			corrupted_direction,
			"missing %s direction resource" % direction_id,
		)
	for malformed_rest_path: Dictionary in [
		{"reason": "null direction rest path", "value": null},
		{"reason": "non-string direction rest path", "value": 1},
	]:
		var malformed_direction_catalog := catalog.duplicate(true)
		var malformed_direction_loadouts := (
			malformed_direction_catalog.get("loadouts", []) as Array
		)
		var malformed_direction_loadout := (
			malformed_direction_loadouts[0] as Dictionary
		)
		var malformed_directions := (
			malformed_direction_loadout.get("directions", {}) as Dictionary
		)
		var malformed_down := malformed_directions.get("down", {}) as Dictionary
		malformed_down["restPath"] = malformed_rest_path.get("value")
		malformed_directions["down"] = malformed_down
		malformed_direction_loadout["directions"] = malformed_directions
		malformed_direction_loadouts[0] = malformed_direction_loadout
		malformed_direction_catalog["loadouts"] = malformed_direction_loadouts
		_expect_resident_wardrobe_catalog_rejected(
			service,
			malformed_direction_catalog,
			String(malformed_rest_path.get("reason", "")),
		)
	var missing_rest_path := catalog.duplicate(true)
	var missing_rest_loadouts := missing_rest_path.get("loadouts", []) as Array
	var missing_rest_loadout := missing_rest_loadouts[0] as Dictionary
	var missing_rest_directions := (
		missing_rest_loadout.get("directions", {}) as Dictionary
	)
	var missing_down := missing_rest_directions.get("down", {}) as Dictionary
	missing_down.erase("restPath")
	missing_rest_directions["down"] = missing_down
	missing_rest_loadout["directions"] = missing_rest_directions
	missing_rest_loadouts[0] = missing_rest_loadout
	missing_rest_path["loadouts"] = missing_rest_loadouts
	_expect_resident_wardrobe_catalog_rejected(
		service,
		missing_rest_path,
		"missing direction rest path",
	)
	var mismatched_identity := catalog.duplicate(true)
	var identity_loadouts := mismatched_identity.get("loadouts", []) as Array
	var identity_loadout := identity_loadouts[0] as Dictionary
	identity_loadout["appearanceId"] = "resident_wardrobe_v1:not_look_00"
	identity_loadouts[0] = identity_loadout
	mismatched_identity["loadouts"] = identity_loadouts
	_expect_resident_wardrobe_catalog_rejected(
		service,
		mismatched_identity,
		"appearance id and loadout id mismatch",
	)



func _expect_resident_wardrobe_catalog_rejected(
	service: RefCounted,
	catalog: Dictionary,
	reason: String,
) -> void:
	var result := service.call("_parse_wardrobe_catalog", catalog) as Dictionary
	_expect(
		not bool(result.get("ok", false)),
		"resident profile editor rejects formal wardrobe catalog: %s" % reason,
	)
	_expect_equal(
		result.get("errorCode"),
		"RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID",
		"invalid formal wardrobe catalog reports a stable error: %s" % reason,
	)
	_expect(
		(result.get("appearances", {}) as Dictionary).is_empty(),
		"invalid formal wardrobe catalog publishes no appearances: %s" % reason,
	)



func _direct_child_count(name_value: String) -> int:
	var count := 0
	for child: Node in _host.get_children():
		if String(child.name) == name_value:
			count += 1
	return count



func _active_route_page_count() -> int:
	var count := 0
	for child: Node in _host.get_children():
		if child.has_meta("route_payload") and not child.is_queued_for_deletion():
			count += 1
	return count



func _active_route_page() -> Control:
	for child: Node in _host.get_children():
		if child.has_meta("route_payload") and not child.is_queued_for_deletion():
			return child as Control
	return null


func _has_component_rect(component_rects: Array, id: String) -> bool:
	for entry in component_rects:
		if String((entry as Dictionary).get("id", "")) == id:
			return true
	return false


func _component_rect(component_rects: Array, id: String) -> Rect2:
	for entry_value: Variant in component_rects:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		if String(entry.get("id", "")) != id:
			continue
		var values := entry.get("rect", []) as Array
		if values.size() != 4:
			return Rect2()
		return Rect2(
			float(values[0]),
			float(values[1]),
			float(values[2]),
			float(values[3]),
		)
	return Rect2()


func _expect_single_active_page(message: String, expected: int = 1) -> void:
	_expect_equal(_active_route_page_count(), expected, "%s has one active page owner" % message)



func _expect_context(
	scope: String,
	open: bool,
	payload_subset: Dictionary,
) -> void:
	for index: int in range(_adapter.page_contexts.size() - 1, -1, -1):
		var record := _adapter.page_contexts[index]
		if String(record.get("scope", "")) != scope:
			continue
		var context := record.get("context", {}) as Dictionary
		if bool(context.get("open", not open)) != open:
			continue
		var matches := true
		for key: Variant in payload_subset:
			if context.get(key) != payload_subset[key]:
				matches = false
				break
		_expect(matches, "page payload reaches set_page_context for %s" % scope)
		return
	_failures.append("missing set_page_context for %s open=%s" % [scope, open])



func _expect_dispatch(intent: String, payload_subset: Dictionary) -> void:
	for record_value: Dictionary in _adapter.dispatches:
		if String(record_value.get("intent", "")) != intent:
			continue
		var payload := record_value.get("payload", {}) as Dictionary
		var matches := true
		for key: Variant in payload_subset:
			if payload.get(key) != payload_subset[key]:
				matches = false
				break
		if matches:
			return
	_failures.append("missing dispatch %s with payload %s" % [intent, payload_subset])



func _dispatch_count(intent: String, payload_subset: Dictionary) -> int:
	var result := 0
	for record_value: Dictionary in _adapter.dispatches:
		if String(record_value.get("intent", "")) != intent:
			continue
		var payload := record_value.get("payload", {}) as Dictionary
		var matches := true
		for key: Variant in payload_subset:
			if payload.get(key) != payload_subset[key]:
				matches = false
				break
		if matches:
			result += 1
	return result



func _on_pause_requested() -> void:
	_pause_request_count += 1



func _scenario_formal_ui_runtime_contract() -> void:
	_expect(
		float(ProjectSettings.get_setting(
			"gui/timers/tooltip_delay_sec",
			0.0,
		)) >= 3155760000.0,
		"正式版本必须保持原生悬停文字提示禁用",
	)
	for path in REQUIRED_FORMAL_PATHS:
		_expect(
			ResourceLoader.exists(path) or FileAccess.file_exists(path),
			"正式 UI 文件缺失：%s" % path,
		)
	if OS.get_environment("AI_TOWN_FORMAL_UI_FULL_CLOSURE") == "1":
		for path in CUT8_DEPENDENCY_PATHS:
			_expect(
				ResourceLoader.exists(path) or FileAccess.file_exists(path),
				"第8刀正式依赖缺失：%s" % path,
			)
		for path in SELF_CONTAINED_SCENES:
			_expect(
				ResourceLoader.load(path) is PackedScene,
				"正式 UI 场景无法加载：%s" % path,
			)
		for path in SAFE_EMPTY_BOOT_SCENES:
			var scene := ResourceLoader.load(path) as PackedScene
			var instance := (
				scene.instantiate() as Control
				if scene != null
				else null
			)
			_expect(
				instance != null,
				"正式 UI 空态场景无法实例化：%s" % path,
			)
			if instance != null:
				root.add_child(instance)
				_expect(
					not instance.visible,
					"正式 UI 未注入数据时应保持隐藏：%s" % path,
				)
				root.remove_child(instance)
				instance.free()
		for path in REQUIRED_FORMAL_PATHS:
			if path.ends_with(".tscn"):
				_expect(
					ResourceLoader.load(path) is PackedScene,
					"组合分支下正式 UI 场景无法加载：%s" % path,
				)
		_test_resident_selection_runtime_contract()
		await _test_custom_creator_runtime_contract()
		await _test_startup_load_focus_stability()
		_test_startup_continue_failure_contract()
	_test_formal_export_filters()
	_test_formal_runtime_asset_paths()
	_test_formal_dependency_closure()
	_test_formal_route_registry_contract()
	_test_hud_16_10_layout_contract()
	for path in FORMAL_SOURCE_MARKERS:
		var source := FileAccess.get_file_as_string(path)
		for marker: String in FORMAL_SOURCE_MARKERS[path]:
			_expect(
				source.contains(marker),
				"正式 UI 晋升标记缺失：%s (%s)" % [path, marker],
			)
		for forbidden_token in FORBIDDEN_FORMAL_SOURCE_TOKENS:
			_expect(
				not source.contains(forbidden_token),
				"正式 UI 仍含候选状态：%s (%s)" % [
					path,
					forbidden_token,
				],
			)
	_test_public_error_copy_contract()
	_test_provider_composite_source_provenance_contract()
	_test_provider_custom_asset_contract()
	_test_provider_settings_error_copy_contract()
	await _test_provider_model_assignment_return_contract()
	_test_visible_error_label_contract()
	_test_world_intro_empty_view_model_contract()
	return


func _test_hud_16_10_layout_contract() -> void:
	var layout := TownHudTypographyContract.layout_for(Vector2(1920.0, 1200.0))
	var avatar_rect := Rect2()
	for target_value: Variant in layout.get("targets", []) as Array:
		var target := target_value as Dictionary
		if String(target.get("id", "")) == "avatar_toggle":
			avatar_rect = target.get("rect", Rect2()) as Rect2
			break
	_expect(
		avatar_rect.has_area() and avatar_rect.end.y >= 1180.0,
		"16:10 HUD keeps the avatar control anchored to the display bottom",
	)

	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	host.size = Vector2(1920.0, 1200.0)
	root.add_child(host)
	var overlay := TOWN_HUD_SCENE.instantiate() as Control
	host.add_child(overlay)
	overlay.call("_apply_layout")
	var outer := overlay.find_child(
		"ConfirmedObserverV5StaticShell",
		true,
		false,
	) as NinePatchRect
	_expect(outer != null, "16:10 HUD mounts its formal shell")
	if outer != null:
		var rendered_size := outer.size * outer.scale
		_expect(
			rendered_size.distance_to(Vector2(1920.0, 1200.0)) <= 1.1,
			"16:10 HUD fills the entire display instead of centering a 16:9 shell",
		)
	host.queue_free()


func _test_provider_composite_source_provenance_contract() -> void:
	var contract_path := (
		"res://assets/ui/provider_settings/composite_reference/"
		+ "provider_settings_page_composite_user_reference_v1_contract.json"
	)
	var contract := _read_json(contract_path)
	_expect(not contract.is_empty(), "模型设置合成参考合同必须可解析")
	if contract.is_empty():
		return
	_expect(
		contract.get("status") == "user-authority-for-final-effect",
		"模型设置合成参考保留用户确认状态",
	)
	_expect(
		not contract.has("path"),
		"模型设置合成参考不得声明仓库中不存在的来源路径",
	)
	_expect(
		_valid_sha256(contract.get("sha256")),
		"模型设置合成参考保留有效 SHA-256 来源记录",
	)
	var source_size := contract.get("sourceSize", []) as Array
	_expect(
		source_size.size() == 2
		and is_equal_approx(float(source_size[0]), 1672.0)
		and is_equal_approx(float(source_size[1]), 941.0),
		"模型设置合成参考保留来源尺寸",
	)


func _test_provider_custom_asset_contract() -> void:
	_expect(
		ProviderSettingsTheme.runtime_assets_ready(),
		"模型设置正式页所需独立图像资产必须全部可加载",
	)
	_expect(
		ProviderSettingsTheme.STATUS_LOADING_CUSTOM_PATH.ends_with(
			"status_loading_custom_v5.png"
		),
		"检查中状态使用无时钟的三节点正式底板",
	)
	_expect(
		ProviderSettingsTheme.PROVIDER_FORMAL_LOADING_PATH.ends_with(
			"provider_checking_connection_v1.png"
		),
		"页头检查动画复用三节点连接图标，不显示时钟",
	)
	_expect_equal(
		ProviderSettingsTheme.composite_background_path({
			"providerId": "openai-compatible-2",
			"customGroup": true,
			"deletableConnection": true,
		}),
		ProviderSettingsTheme.CUSTOM_COMPATIBLE_BACKGROUND_PATH,
		"新增中转连接使用同时容纳 Base URL 与 API Key 的正式底板",
	)



func _test_public_error_copy_contract() -> void:
	_expect(
		UiViewModel.public_error_message({"error": null}).is_empty(),
		"无失败时不得生成继续游戏错误文案",
	)
	var public_copy := UiViewModel.public_error_message({
		"error": {
			"code": "SESSION_PROVIDER_SETTINGS_NOT_READY",
			"message": "模型设置暂不可用，请完成配置后重试。",
			"retryable": false,
			"details": ["INTERNAL_PROVIDER_TRACE"],
		},
	})
	_expect(
		public_copy == "模型设置暂不可用，请完成配置后重试。",
		"继续游戏失败必须读取公开文案",
	)
	_expect(
		not public_copy.contains("SESSION_PROVIDER_SETTINGS_NOT_READY")
		and not public_copy.contains("INTERNAL_PROVIDER_TRACE"),
		"继续游戏失败文案不得泄露内部码或详情",
	)
	_expect(
		UiViewModel.public_error_message({
			"error": {
				"code": "SESSION_PROVIDER_SETTINGS_NOT_READY",
				"message": "SESSION_PROVIDER_SETTINGS_NOT_READY",
				"retryable": false,
				"details": ["INTERNAL_PROVIDER_TRACE"],
			},
		}).is_empty(),
		"内部码不得被当作公开错误文案",
	)



func _test_provider_settings_error_copy_contract() -> void:
	var scene := ResourceLoader.load(
		"res://ui/provider_settings/ProviderSettingsScreen.tscn"
	) as PackedScene
	var screen := scene.instantiate() as Control if scene != null else null
	_expect(screen != null, "模型设置正式页无法实例化")
	if screen == null:
		return
	var internal_error := {
		"code": "PROVIDER_SECRET_BACKEND_TRACE",
		"message": "backend shard provider-east-03 rejected request",
		"details": ["credential_slot=prod-secret", "trace=provider-9821"],
	}
	var title := str(screen.call(
		"_operation_title",
		{"status": "error"},
		{},
		internal_error,
	))
	var message := str(screen.call(
		"_operation_message",
		{"status": "error"},
		{},
		internal_error,
	))
	_expect(title == "连接检查失败", "模型设置失败标题使用稳定公开文案")
	_expect(message == "当前操作暂不可用", "未知模型错误使用稳定公开文案")
	var rendered_copy := "%s\n%s" % [title, message]
	_expect(
		not rendered_copy.contains(str(internal_error.get("code")))
		and not rendered_copy.contains(str(internal_error.get("message")))
		and not rendered_copy.contains("credential_slot")
		and not rendered_copy.contains("provider-9821"),
		"模型设置正式页不得泄露内部错误码、消息或详情",
	)
	var public_message := str(screen.call(
		"_operation_message",
		{"status": "error"},
		{},
		{
			"code": "PROVIDER_AUTH_FAILED",
			"message": "adapter returned HTTP 401",
			"playerMessage": "API Key 认证失败，请重新填写。",
			"details": ["authorization header rejected"],
		},
	))
	_expect(
		public_message == "API Key 认证失败，请重新填写。",
		"模型设置正式页保留明确提供的公开错误文案",
	)
	screen.free()
	var composite := ProviderSettingsCompositeDesktop.new()
	var composite_title := str(composite.call(
		"_operation_title",
		{"status": "error"},
		{},
		internal_error,
	))
	var composite_message := str(composite.call(
		"_operation_message",
		{"status": "error"},
		{},
		internal_error,
	))
	_expect(
		composite_title == "连接检查失败",
		"模型设置桌面正式页失败标题使用稳定公开文案",
	)
	_expect(
		composite_message == "当前操作暂不可用",
		"模型设置桌面正式页未知错误使用稳定公开文案",
	)
	var composite_copy := "%s\n%s" % [
		composite_title,
		composite_message,
	]
	_expect(
		not composite_copy.contains(str(internal_error.get("code")))
		and not composite_copy.contains(str(internal_error.get("message")))
		and not composite_copy.contains("credential_slot")
		and not composite_copy.contains("provider-9821"),
		"模型设置桌面正式页不得泄露内部错误码、消息或详情",
	)
	composite.free()


func _test_provider_model_assignment_return_contract() -> void:
	var provider_scene := ResourceLoader.load(
		"res://ui/provider_settings/ProviderSettingsScreen.tscn"
	) as PackedScene
	var provider_screen := (
		provider_scene.instantiate() as Control
		if provider_scene != null
		else null
	)
	_expect(provider_screen != null, "模型设置页可进入居民模型重新分配流程")
	if provider_screen == null:
		return
	root.add_child(provider_screen)
	provider_screen.set("_last_model_deletion", {
		"providerId": "ollama",
		"apiModel": "qwen3:8b",
	})
	var blocked_vm := _provider_input_stability_view_model(2)
	blocked_vm["status"] = "rejected"
	blocked_vm["operation"] = {
		"requestId": "delete-in-use",
		"intent": "provider_settings.delete_api_model",
		"status": "rejected",
		"submittedAtMsec": 1,
		"completedAtMsec": 2,
	}
	blocked_vm["error"] = {
		"kind": "unavailable",
		"code": "PROVIDER_API_MODEL_IN_USE",
		"retryable": false,
		"message": "请先重新分配居民模型。",
		"details": ["resident-a", "resident-b"],
	}
	_expect(
		bool(provider_screen.call("apply_view_model", blocked_vm)),
		"占用中的自定义模型会显示重新分配入口",
	)
	var routed := {"intent": "", "payload": {}}
	provider_screen.intent_requested.connect(func(
		intent: StringName,
		payload: Dictionary,
	) -> void:
		routed["intent"] = String(intent)
		routed["payload"] = payload.duplicate(true)
	)
	provider_screen.call("_open_blocked_model_assignment")
	_expect_equal(
		String(routed.get("intent", "")),
		"provider_settings.open_model_assignment",
		"去分配模型只发出页面路由意图，不误派发给设置服务",
	)
	_expect_equal(
		(routed.get("payload", {}) as Dictionary).get("modelId"),
		"qwen3:8b",
		"重新分配路由保留被占用模型",
	)
	_expect_equal(
		((routed.get("payload", {}) as Dictionary).get(
			"residentIds",
			[],
		) as Array).size(),
		2,
		"重新分配路由携带受影响居民",
	)
	root.remove_child(provider_screen)
	provider_screen.free()

	var assignment_scene := ResourceLoader.load(
		"res://ui/resident_model_assignment/ResidentModelAssignmentScreen.tscn"
	) as PackedScene
	var assignment_page := (
		assignment_scene.instantiate() as Control
		if assignment_scene != null
		else null
	)
	_expect(assignment_page != null, "居民模型分配页支持返回模型设置模式")
	if assignment_page != null:
		assignment_page.set("return_to_provider_settings", true)
		root.add_child(assignment_page)
		await process_frame
		var modal_confirm := assignment_page.find_child(
			"ResponsiveModalStart",
			true,
			false,
		) as Button
		var responsive_apply := assignment_page.find_child(
			"ApplyDraftButton",
			true,
			false,
		) as Button
		_expect(
			modal_confirm != null and modal_confirm.text == "确认并返回",
			"返回模式完成确认不再显示开始游戏",
		)
		_expect(
			responsive_apply != null
			and responsive_apply.text == "确认并返回模型设置",
			"返回模式底部动作明确返回模型设置",
		)
		assignment_page.set("_view_model", {
			"data": {"formalReady": true},
			"operation": {"status": "idle"},
		})
		var presentation := assignment_page.call(
			"_presentation_view_model"
		) as Dictionary
		_expect(
			bool((presentation.get("data", {}) as Dictionary).get(
				"returnToProviderSettings",
				false,
			)),
			"返回模式传入 1920 组合页面",
		)
		root.remove_child(assignment_page)
		assignment_page.free()

	var runtime_adapter := AdapterHarness.new()
	root.add_child(runtime_adapter)
	var runtime_host := HOST_SCRIPT.new() as Control
	runtime_adapter.world_menu_host = runtime_host
	var bound := runtime_host.call(
		"bind_town_ui_adapter",
		runtime_adapter,
	) as Dictionary
	root.add_child(runtime_host)
	_expect(bool(bound.get("ok", false)), "正式运行页接入分配返回流程")
	runtime_host.call(
		"_on_self_dispatching_page_intent",
		&"provider_settings.open_model_assignment",
		{
			"modelId": "qwen3:8b",
			"residentIds": ["resident-a"],
		},
		&"provider_settings",
	)
	await process_frame
	await process_frame
	_expect_equal(
		runtime_host.call("current_route"),
		&"resident_model_assignment",
		"正式运行页从模型设置打开居民模型分配页",
	)
	var routed_assignment := runtime_host.get("_active_page") as Control
	_expect(
		is_instance_valid(routed_assignment)
		and bool(routed_assignment.get("return_to_provider_settings")),
		"模型设置来源会启用确认返回模式",
	)
	runtime_host.call(
		"_on_self_dispatching_page_intent",
		&"resident_model_assignment.back",
		{},
		&"resident_model_assignment",
	)
	await process_frame
	await process_frame
	_expect_equal(
		runtime_host.call("current_route"),
		&"provider_settings",
		"居民模型分配返回动作回到模型设置",
	)
	runtime_host.call("close_page", false)
	root.remove_child(runtime_host)
	runtime_host.free()
	root.remove_child(runtime_adapter)
	runtime_adapter.free()



func _test_visible_error_label_contract() -> void:
	var internal_error := {
		"code": "INTERNAL_UI_BACKEND_TRACE",
		"message": "backend shard private-07 rejected request",
		"details": ["credential_slot=prod-secret", "trace=ui-7719"],
	}
	var operation := {
		"status": "error",
		"requestId": "internal-request",
		"message": "",
	}
	# 正式路由页 ResidentActionWorldMenu 的文字反馈由宿主 SystemFeedbackLayer
	# 承载(其安全文案有独立验收);这里定点校验共享基类 _render_feedback
	# 的安全文案实现,基类场景仍是该实现的唯一文本渲染载体。
	var action_scene := ResourceLoader.load(
		"res://ui/resident_action_menu/ResidentActionMenu.tscn"
	) as PackedScene
	var action_menu := (
		action_scene.instantiate() as Control
		if action_scene != null
		else null
	)
	_expect(action_menu != null, "居民操作菜单错误文案反例无法实例化")
	if action_menu != null:
		root.add_child(action_menu)
		action_menu.set("_view_model", {
			"operation": operation,
			"error": internal_error,
		})
		action_menu.call("_render_feedback", {"feedback": {}, "placement": {}})
		_expect_safe_error_label(
			action_menu.find_child("FeedbackLabel", true, false) as Label,
			"居民操作菜单",
			internal_error,
		)
		root.remove_child(action_menu)
		action_menu.free()

	var indoor_scene := ResourceLoader.load(
		"res://ui/indoor_overlay/IndoorOverlay.tscn"
	) as PackedScene
	var indoor := (
		indoor_scene.instantiate() as Control
		if indoor_scene != null
		else null
	)
	_expect(indoor != null, "室内观察错误文案反例无法实例化")
	if indoor != null:
		root.add_child(indoor)
		var indoor_snapshot := indoor.call(
			"runtime_gate_snapshot"
		) as Dictionary
		_expect(
			bool(indoor_snapshot.get("panelToggleOutsidePanel", false)),
			"室内观察收起箭头由面板外侧的独立按钮承载",
		)
		_expect(
			String(indoor_snapshot.get("panelToggleAsset", "")).ends_with(
				"indoor_panel_toggle_arrow_right_v21_64x128.png"
			),
			"室内观察使用已确认的 64×128 外置箭头资产",
		)
		var panel_toggle := indoor.get("_panel_toggle_button") as TextureButton
		_expect(
			panel_toggle != null
			and panel_toggle.get_parent() == indoor
			and panel_toggle.size == Vector2(64.0, 128.0),
			"室内观察外置箭头保持独立节点与精确运行尺寸",
		)
		indoor.set("_view_model", {
			"operation": operation,
			"error": internal_error,
		})
		indoor.set("_render_data", {
			"sceneLoad": {"status": "error"},
		})
		indoor.call("_render_events")
		_expect_safe_error_label(
			indoor.get("_status_label") as Label,
			"室内观察",
			internal_error,
		)
		root.remove_child(indoor)
		indoor.free()

	var log_scene := ResourceLoader.load(
		"res://ui/town_log/TownLogPanel.tscn"
	) as PackedScene
	var town_log := (
		log_scene.instantiate() as Control
		if log_scene != null
		else null
	)
	_expect(town_log != null, "小镇日志错误文案反例无法实例化")
	if town_log != null:
		root.add_child(town_log)
		town_log.set("_view_model", {
			"operation": operation,
			"error": internal_error,
			"actions": {},
		})
		town_log.call("_render_feedback")
		_expect_safe_error_label(
			town_log.get("_feedback_label") as Label,
			"小镇日志",
			internal_error,
		)
		root.remove_child(town_log)
		town_log.free()

	var settings_script := load(
		"res://ui/settings/AudioDisplaySettingsImageLayout.gd"
	) as Script
	var settings := (
		settings_script.new() as Control
		if settings_script != null
		else null
	)
	_expect(settings != null, "声音画面设置错误文案反例无法实例化")
	if settings != null:
		root.add_child(settings)
		settings.call("apply_snapshot", {
			"operation": operation,
			"error": internal_error,
			"actions": {},
		}, {})
		_expect_safe_error_label(
			settings.get("_status_label") as Label,
			"声音画面设置",
			internal_error,
		)
		root.remove_child(settings)
		settings.free()



func _expect_safe_error_label(
	label: Label,
	page_name: String,
	internal_error: Dictionary
) -> void:
	_expect(label != null, "%s公开错误 Label 必须存在" % page_name)
	if label == null:
		return
	var copy := label.text
	_expect(
		copy == "当前操作暂不可用",
		"%s未知错误必须显示稳定公开文案" % page_name,
	)
	_expect(
		not copy.contains(str(internal_error.get("code")))
		and not copy.contains(str(internal_error.get("message")))
		and not copy.contains("credential_slot")
		and not copy.contains("ui-7719"),
		"%s不得泄露内部错误码、消息或详情" % page_name,
	)



func _test_world_intro_empty_view_model_contract() -> void:
	var scene := ResourceLoader.load(
		"res://ui/world_intro/WorldIntroScreen.tscn"
	) as PackedScene
	var intro := scene.instantiate() as Control if scene != null else null
	_expect(intro != null, "世界介绍空 ViewModel 反例无法实例化")
	if intro == null:
		return
	root.add_child(intro)
	_expect_world_intro_empty_controls(intro, "首次入树")
	intro.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	for viewport_size: Vector2 in [
		Vector2(1920, 1080),
		Vector2(1280, 720),
		Vector2(820, 1180),
	]:
		intro.size = viewport_size
		intro.call("_apply_responsive_layout")
		intro.call("_refresh_actions")
		_expect_world_intro_empty_controls(
			intro,
			"空态刷新 %dx%d" % [
				int(viewport_size.x),
				int(viewport_size.y),
			],
		)
	root.remove_child(intro)
	intro.free()



func _expect_world_intro_empty_controls(
	intro: Control,
	scenario: String
) -> void:
	for button_name: String in [
		"BackButton",
		"PreviousButton",
		"SkipButton",
		"ContinueButton",
	]:
		var button := intro.find_child(button_name, true, false) as Button
		_expect(
			button != null and button.disabled and not button.visible,
			"世界介绍%s按钮必须禁用并隐藏：%s" % [
				scenario,
				button_name,
			],
		)
	var page_label := intro.find_child("PageStatus", true, false) as Label
	_expect(
		page_label != null
		and not page_label.visible
		and page_label.text.is_empty(),
		"世界介绍%s页码必须隐藏且不得显示 1/0" % scenario,
	)



func _test_resident_selection_runtime_contract() -> void:
	var icon_root := "res://assets/ui/resident_selection/icons_v2/"
	for icon_name in RESIDENT_SELECTION_RUNTIME_ICONS:
		var path := icon_root + icon_name
		_expect(
			ResourceLoader.load(path) is Texture2D,
			"居民选择正式运行图标无法加载：%s" % path,
		)

	var scene := ResourceLoader.load(
		"res://ui/resident_selection/ResidentSelectionScreen.tscn"
	) as PackedScene
	var selection := scene.instantiate() as Control if scene != null else null
	_expect(selection != null, "居民选择正式页无法实例化")
	if selection == null:
		return
	root.add_child(selection)
	_expect(not selection.visible, "居民选择正式页空态必须隐藏")
	_expect(
		bool(selection.call(
			"apply_view_model",
			_resident_selection_view_model(),
		)),
		"居民选择正式页无法应用运行时 ViewModel",
	)
	_expect(selection.visible, "居民选择正式页注入数据后必须显示")
	var detail_sprite := selection.find_child(
		"DetailMapSprite",
		true,
		false,
	) as TextureRect
	_expect(
		detail_sprite != null and detail_sprite.texture == null,
		"15 位居民图片路径为空时详情区必须显示安全空态",
	)
	selection.call("_set_detail_walk_sheet", "")
	_expect(
		detail_sprite != null and detail_sprite.texture == null,
		"重复刷新空图片路径不得触发纹理加载或破坏空态",
	)
	var walk_sheet_path := (
		"res://assets/characters/paper_doll_64/compiled/"
		+ "neutral_hoodie_walk_64.png"
	)
	selection.call("_set_detail_walk_sheet", walk_sheet_path)
	var cached_walk_texture := detail_sprite.texture if detail_sprite != null else null
	if detail_sprite != null:
		detail_sprite.texture = null
	selection.call("_set_detail_walk_sheet", walk_sheet_path)
	_expect(
		detail_sprite != null
		and cached_walk_texture != null
		and detail_sprite.texture == cached_walk_texture,
		"居民头像切换后重复使用缓存行走图时必须恢复正确纹理",
	)
	_expect(
		selection.find_child("TownClock", true, false) is TextureRect
		and (
			selection.find_child("TownClock", true, false) as TextureRect
		).texture != null,
		"居民选择正式页动态 TownClock 图标未进入运行树",
	)
	selection.call("_open_resident_overview")
	var overview_track := selection.find_child(
		"ResidentOverviewScrollTrack",
		true,
		false,
	) as TextureRect
	var overview_point := (
		overview_track.get_global_rect().get_center()
		if overview_track != null
		else Vector2.ZERO
	)
	var emulated_scroll_press := InputEventMouseButton.new()
	emulated_scroll_press.device = InputEvent.DEVICE_ID_EMULATION
	emulated_scroll_press.button_index = MOUSE_BUTTON_LEFT
	emulated_scroll_press.pressed = true
	emulated_scroll_press.global_position = overview_point
	selection.call(
		"_on_overview_scroll_control_gui_input",
		emulated_scroll_press,
		false,
	)
	_expect(
		not bool(selection.get("_overview_scroll_dragging")),
		"居民选择滚动条不能重复接收触摸模拟鼠标事件",
	)
	selection.call(
		"_on_overview_scroll_control_gui_input",
		_mobile_touch(17, true, overview_point),
		false,
	)
	_expect(
		bool(selection.get("_overview_scroll_dragging"))
		and int(selection.get("_overview_scroll_touch_index")) == 17,
		"居民选择滚动条必须直接接收原生触摸按下",
	)
	var overview_drag := InputEventScreenDrag.new()
	overview_drag.index = 17
	overview_drag.position = overview_point + Vector2(0.0, 24.0)
	selection.call("_input", overview_drag)
	selection.call("_input", _mobile_touch(17, false, overview_drag.position))
	_expect(
		not bool(selection.get("_overview_scroll_dragging"))
		and int(selection.get("_overview_scroll_touch_index")) == -1,
		"居民选择滚动条触摸结束后必须释放拖动状态",
	)
	root.remove_child(selection)
	selection.free()



func _resident_selection_view_model() -> Dictionary:
	var residents: Array[Dictionary] = []
	var recommended_ids: Array[String] = []
	for index in 15:
		var resident_id := "resident-%02d" % index
		recommended_ids.append(resident_id)
		residents.append({
			"resident_id": resident_id,
			"display_name": "居民%02d" % index,
			"occupation": "小镇居民",
			"one_line_role": "认真生活",
			"selection_summary": "认真生活",
			"personality": "平和",
			"desire": "建设小镇",
			"speech": "你好",
			"location": "中央广场",
			"sprite_path": "",
		})
	var actions := {}
	for action_key: String in [
		"selection",
		"recommend",
		"clear",
		"confirm",
		"custom_resident",
		"delete_custom_resident",
		"delete_residents",
		"back",
	]:
		actions[action_key] = {
			"intent": "resident_selection.%s" % action_key,
			"enabled": true,
			"disabled_reason": "",
		}
	return {
		"scope": "resident_selection",
		"status": "ready",
		"revision": 1,
		"data": {
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": true,
			"internalPlaytest": false,
			"selection_limit": 15,
			"connection_label": "模型将在下一步分配",
			"candidate_pool_revision": 1,
			"focused_resident_id": "resident-00",
			"selected_resident_ids": [],
			"recommended_resident_ids": recommended_ids,
			"confirmation_payload": {},
			"resident_catalog_status": "formal",
			"resident_catalog": [],
			"residents": residents,
		},
		"actions": actions,
		"operation": _startup_operation("", "idle", ""),
		"error": null,
	}



func _test_custom_creator_runtime_contract() -> void:
	var control_states := {
		"age_minus": ["disabled", "normal", "pressed"],
		"age_plus": ["disabled", "normal", "pressed"],
		"age_value": ["disabled", "normal", "pressed"],
		"back": ["disabled", "hover", "normal", "pressed"],
		"cancel": ["disabled", "hover", "normal", "pressed"],
		"core_field": ["disabled", "error", "hover", "normal"],
		"create": ["disabled", "hover", "loading", "normal", "pressed"],
		"create_decoration": ["normal"],
		"dropdown_arrow": ["disabled", "hover", "normal", "pressed"],
		"dropdown_field": ["disabled", "hover", "normal", "pressed"],
		"dropdown_popup/item": [
			"disabled", "hover", "normal", "pressed", "selected",
		],
		"dropdown_popup/panel": ["normal"],
		"dropdown_popup/separator": ["normal"],
		"gender": ["disabled", "selected", "unselected"],
		"name_field": ["disabled", "error", "hover", "normal"],
		"status": ["disabled", "error", "loading", "success", "warning"],
		"status_icon": ["disabled", "error", "loading", "success", "warning"],
		"status_icon_reference": ["success"],
		"wardrobe": ["disabled", "hover", "loading", "normal", "pressed"],
	}
	var control_root := (
		"res://assets/ui/custom_resident_creator/runtime/controls/v4/"
	)
	for family: String in control_states:
		for state: String in control_states[family]:
			var path := "%s%s/%s.png" % [control_root, family, state]
			_expect(
				ResourceLoader.load(path) is Texture2D,
				"自定义居民正式控件资产无法加载：%s" % path,
			)

	var scene := ResourceLoader.load(
		"res://ui/custom_resident_creator/CustomResidentCreatorScreen.tscn"
	) as PackedScene
	var creator := scene.instantiate() as Control if scene != null else null
	_expect(creator != null, "自定义居民正式页无法实例化")
	if creator == null:
		return
	root.add_child(creator)
	_expect(not creator.visible, "自定义居民正式页空态必须隐藏")
	_expect(
		bool(creator.call("apply_view_model", _custom_creator_view_model())),
		"自定义居民正式页无法应用运行时 ViewModel",
	)
	_expect(creator.visible, "自定义居民正式页注入数据后必须显示")
	var creator_name_edit := creator.find_child("NameEdit", true, false) as LineEdit
	_expect(creator_name_edit != null, "自定义居民正式页缺少姓名输入框")
	if creator_name_edit != null:
		creator_name_edit.grab_focus()
		creator_name_edit.text = "测试居民正在编辑"
		creator_name_edit.text_changed.emit(creator_name_edit.text)
		creator_name_edit.set_caret_column(4)
		var creator_refresh := _custom_creator_view_model()
		creator_refresh["revision"] = 2
		var creator_refresh_data := creator_refresh.get("data", {}) as Dictionary
		(creator_refresh_data.get("draft", {}) as Dictionary)["age"] = 28
		_expect(
			bool(creator.call("apply_view_model", creator_refresh)),
			"自定义居民正式页接受无关字段刷新",
		)
		_expect_equal(
			creator_name_edit.text,
			"测试居民正在编辑",
			"自定义居民无关刷新保留尚未提交的姓名",
		)
		_expect_equal(
			creator_name_edit.get_caret_column(),
			4,
			"自定义居民无关刷新保留姓名光标",
		)
		_expect_equal(
			root.get_viewport().gui_get_focus_owner(),
			creator_name_edit,
			"自定义居民无关刷新保留输入焦点",
		)
		var creator_confirmed := creator_refresh.duplicate(true)
		creator_confirmed["revision"] = 3
		var confirmed_data := creator_confirmed.get("data", {}) as Dictionary
		(confirmed_data.get("draft", {}) as Dictionary)["name"] = "测试居民正在编辑"
		_expect(
			bool(creator.call("apply_view_model", creator_confirmed)),
			"自定义居民正式页接受已确认的姓名",
		)
		_expect(
			not (creator.get("_local_text_drafts") as Dictionary).has("name"),
			"自定义居民确认姓名后清理本地待确认状态",
		)
		var interest_option := creator.find_child(
			"InterestOption",
			true,
			false,
		) as Button
		_expect(interest_option != null, "自定义居民正式页缺少兴趣下拉框")
		if interest_option != null:
			creator.call("_open_dropdown_popup", "interests", interest_option)
			var custom_interest_edit := creator.get("_interest_custom_edit") as LineEdit
			_expect(custom_interest_edit != null, "兴趣下拉框缺少自定义兴趣输入")
			if custom_interest_edit != null:
				custom_interest_edit.grab_focus()
				custom_interest_edit.text = "观察云朵"
				custom_interest_edit.text_changed.emit(custom_interest_edit.text)
				custom_interest_edit.set_caret_column(3)
				var interest_refresh := creator_confirmed.duplicate(true)
				interest_refresh["revision"] = 4
				var interest_refresh_data := (
					interest_refresh.get("data", {}) as Dictionary
				)
				(interest_refresh_data.get("draft", {}) as Dictionary)["age"] = 29
				_expect(
					bool(creator.call("apply_view_model", interest_refresh)),
					"自定义居民兴趣输入期间接受无关字段刷新",
				)
				await process_frame
				var rebuilt_interest_edit := (
					creator.get("_interest_custom_edit") as LineEdit
				)
				_expect(
					rebuilt_interest_edit != null
					and rebuilt_interest_edit != custom_interest_edit,
					"兴趣状态刷新会创建替换输入框",
				)
				if rebuilt_interest_edit != null:
					_expect_equal(
						rebuilt_interest_edit.text,
						"观察云朵",
						"兴趣状态刷新保留未提交的自定义兴趣",
					)
					_expect_equal(
						rebuilt_interest_edit.get_caret_column(),
						3,
						"兴趣状态刷新保留自定义兴趣光标",
					)
					_expect_equal(
						root.get_viewport().gui_get_focus_owner(),
						rebuilt_interest_edit,
						"兴趣状态刷新保留自定义兴趣焦点",
					)
	root.remove_child(creator)
	creator.free()



func _custom_creator_view_model() -> Dictionary:
	var actions := {}
	for action_key: String in [
		"updateFields",
		"openWardrobe",
		"applyWardrobeResult",
		"create",
		"cancel",
		"retry",
	]:
		actions[action_key] = {
			"intent": "custom_resident_creator.%s" % action_key,
			"enabled": true,
			"disabledReason": "",
		}
	return {
		"scope": "custom_resident_creator",
		"status": "ready",
		"revision": 1,
		"data": {
			"capabilityMode": "formal",
			"source": "formal",
			"formalReady": true,
			"draftId": "draft-contract-test",
			"candidatePoolRevision": 1,
			"draft": {
				"name": "测试居民",
				"gender": "女",
				"age": 27,
				"appearanceSelection": {},
					"desire": "好好生活",
					"personality": "平和",
					"speech": "你好",
					"interests": ["阅读"],
					"customInterests": [],
					"occupationId": "",
					"workplaceId": "",
				},
			"resolvedAppearance": {
				"formalReady": false,
				"selection": {},
				"displayName": "外观待选",
			},
			"options": {
				"genders": [{"id": "女"}, {"id": "男"}],
					"occupations": [],
					"workplaces": [],
					"interests": [{"id": "阅读", "label": "阅读"}],
					"wardrobe": {
					"entryMode": "route_to_formal_wardrobe",
					"runtimeMode": "resident_2d_rig_v1",
					"slotOrder": ["hair", "top", "bottom", "shoes"],
				},
			},
			"validation": {
				"status": "valid",
				"issues": [],
				"summaryLabel": "资料完整，可以创建",
			},
		},
		"actions": actions,
		"operation": _startup_operation("", "idle", ""),
		"error": null,
	}


func _provider_input_stability_view_model(revision: int) -> Dictionary:
	var actions := {}
	for action_key: String in [
		"back",
		"selectProvider",
		"saveKey",
		"deleteKey",
		"saveBaseUrl",
		"selectModel",
		"checkConnection",
		"retry",
	]:
		actions[action_key] = {
			"intent": "provider_settings.%s" % action_key,
			"enabled": true,
			"disabledReason": "",
		}
	return {
		"scope": "provider_settings",
		"status": "ready",
		"revision": revision,
		"data": {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"pageTitle": "模型设置",
			"selectedProviderId": "deepseek",
			"formalStatusLabel": "等待后台检查",
			"providers": [{
				"providerId": "deepseek",
				"displayName": "DeepSeek",
				"enabled": true,
				"external": true,
				"key": {
					"saved": false,
					"maskedValue": "",
					"status": "missing",
					"errorCode": "PROVIDER_API_KEY_REQUIRED",
				},
				"baseUrl": "https://api.deepseek.com",
				"models": [],
				"connection": {
					"status": "checking",
					"label": "正在检查",
					"message": "正在后台检查连接。",
				},
			}],
			"summary": {
				"availableProviderCount": 0,
				"enabledModelCount": 0,
			},
		},
		"actions": actions,
		"operation": {
			"requestId": "provider-health-%d" % revision,
			"intent": "provider_settings.check_connection",
			"status": "loading",
			"submittedAtMsec": 1,
			"completedAtMsec": 0,
		},
		"error": null,
	}


func _verify_local_provider_url_autodiscovery(
	screen: ProviderSettingsScreen,
	provider_id: String,
	display_name: String,
	default_url: String,
	revision: int,
) -> void:
	var initial_vm := _local_provider_url_view_model(
		provider_id,
		display_name,
		default_url,
		revision,
	)
	_expect(
		screen.apply_view_model(initial_vm),
		"%s local URL settings render" % display_name,
	)
	await process_frame
	await process_frame
	var url_edit := screen.find_child("BaseUrlInput", true, false) as LineEdit
	var key_edit := screen.find_child("ApiKeyInput", true, false) as LineEdit
	var save_button := screen.find_child("SaveKeyButton", true, false) as Button
	_expect(key_edit == null, "%s does not expose an API Key input" % display_name)
	_expect(
		url_edit != null and url_edit.editable and url_edit.text == default_url,
		"%s exposes its editable default service URL" % display_name,
	)
	_expect(
		save_button != null and not save_button.disabled,
		"%s enables saving from its service URL" % display_name,
	)
	var local_provider := (
		(initial_vm.get("data", {}) as Dictionary).get("providers", []) as Array
	)[0] as Dictionary
	screen.call("_perform_provider_selection", local_provider)
	await process_frame
	await process_frame
	var switched_url_edit := screen.find_child(
		"BaseUrlInput",
		true,
		false,
	) as LineEdit
	var switched_save_button := screen.find_child(
		"SaveKeyButton",
		true,
		false,
	) as Button
	_expect(
		switched_url_edit != null and switched_url_edit.text == default_url,
		"%s provider selection keeps the default service URL visible" % display_name,
	)
	_expect(
		switched_save_button != null and not switched_save_button.disabled,
		"%s provider selection keeps service URL saving enabled" % display_name,
	)
	var dispatch_start := _adapter.dispatches.size()
	if switched_save_button != null and not switched_save_button.disabled:
		switched_save_button.pressed.emit()
	await process_frame
	var save_dispatch := (
		_adapter.dispatches[dispatch_start] as Dictionary
		if _adapter.dispatches.size() > dispatch_start
		else {}
	)
	_expect_equal(
		save_dispatch.get("intent"),
		"provider_settings.save_connection",
		"%s saves the local connection instead of an API Key" % display_name,
	)
	_expect_equal(
		(save_dispatch.get("payload", {}) as Dictionary).get("baseUrl"),
		default_url,
		"%s saves the visible service URL" % display_name,
	)
	_expect_equal(
		(save_dispatch.get("payload", {}) as Dictionary).get("apiKey"),
		"",
		"%s saves without a placeholder API Key" % display_name,
	)
	var saved_vm := _local_provider_url_view_model(
		provider_id,
		display_name,
		default_url,
		revision + 1,
	)
	((saved_vm.get("data", {}) as Dictionary).get("providers", []) as Array)[0][
		"baseUrl"
	] = default_url
	saved_vm["operation"] = {
		"requestId": "%s-url-save" % provider_id,
		"intent": "provider_settings.save_connection",
		"status": "success",
		"submittedAtMsec": 1,
		"completedAtMsec": 2,
	}
	_expect(
		screen.apply_view_model(saved_vm),
		"%s accepts its saved URL result" % display_name,
	)
	await process_frame
	await process_frame
	await process_frame
	var discovery_dispatch := (
		_adapter.dispatches[_adapter.dispatches.size() - 1] as Dictionary
		if not _adapter.dispatches.is_empty()
		else {}
	)
	_expect_equal(
		discovery_dispatch.get("intent"),
		"provider_settings.discover_models",
		"%s automatically reads models after saving its URL" % display_name,
	)
	_expect_equal(
		(discovery_dispatch.get("payload", {}) as Dictionary).get("providerId"),
		provider_id,
		"%s model discovery targets the selected local service" % display_name,
	)


func _local_provider_url_view_model(
	provider_id: String,
	display_name: String,
	default_url: String,
	revision: int,
) -> Dictionary:
	var actions := {}
	for action_key: String in [
		"back",
		"selectProvider",
		"setProviderEnabled",
		"saveConnection",
		"discoverModels",
		"saveApiModel",
		"deleteApiModel",
		"selectModel",
		"checkConnection",
	]:
		actions[action_key] = {
			"intent": "provider_settings.%s" % action_key,
			"enabled": true,
			"disabledReason": "",
		}
	return {
		"scope": "provider_settings",
		"status": "ready",
		"revision": revision,
		"data": {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
			"pageTitle": "模型设置",
			"selectedProviderId": provider_id,
			"providers": [{
				"providerId": provider_id,
				"displayName": display_name,
				"enabled": true,
				"external": true,
				"authRequired": false,
				"customModels": true,
				"customGroup": true,
				"modelCatalogSupported": true,
				"key": {"saved": false, "status": "optional"},
				"baseUrl": "",
				"defaultBaseUrl": default_url,
				"models": [],
				"discoveredModels": [],
				"connection": {
					"status": "not_configured",
					"errorCode": "PROVIDER_MODEL_SELECTION_REQUIRED",
				},
			}],
			"summary": {
				"availableProviderCount": 0,
				"enabledModelCount": 0,
			},
		},
		"actions": actions,
		"operation": {"status": "idle", "requestId": ""},
		"error": null,
	}


func _test_startup_load_focus_stability() -> void:
	var scene := ResourceLoader.load(
		"res://ui/startup/StartupLoadGameScreen.tscn",
	) as PackedScene
	var screen := scene.instantiate() as Control if scene != null else null
	_expect(screen != null, "加载游戏正式页无法实例化")
	if screen == null:
		return
	root.add_child(screen)
	var initial_vm := _startup_load_focus_view_model(1)
	_expect(
		bool(screen.call("apply_view_model", initial_vm)),
		"加载游戏正式页接受存档列表",
	)
	await process_frame
	var second_slot_action := screen.find_child(
		"slot-bAction",
		true,
		false,
	) as Button
	_expect(second_slot_action != null, "加载游戏页缺少第二个存档按钮")
	if second_slot_action != null:
		second_slot_action.grab_focus()
		var refreshed_vm := _startup_load_focus_view_model(2)
		var refreshed_data := refreshed_vm.get("data", {}) as Dictionary
		var slots := refreshed_data.get("slots", []) as Array
		(slots[0] as Dictionary)["day"] = 8
		_expect(
			bool(screen.call("apply_view_model", refreshed_vm)),
			"加载游戏正式页接受存档后台刷新",
		)
		await process_frame
		var rebuilt_second_action := screen.find_child(
			"slot-bAction",
			true,
			false,
		) as Button
		_expect(
			rebuilt_second_action != null
			and rebuilt_second_action != second_slot_action,
			"存档后台刷新创建替换按钮",
		)
		_expect_equal(
			root.get_viewport().gui_get_focus_owner(),
			rebuilt_second_action,
			"存档后台刷新保留当前存档按钮焦点",
		)
	root.remove_child(screen)
	screen.free()


func _startup_load_focus_view_model(revision: int) -> Dictionary:
	return {
		"scope": "save",
		"status": "ready",
		"revision": revision,
		"data": {
			"mode": "load",
			"providerIndependent": true,
			"pageTitle": "加载游戏",
			"slots": [
				{
					"slotId": "slot-a",
					"displayName": "第一座小镇",
					"state": "healthy",
					"continueAvailable": true,
					"day": 7,
				},
				{
					"slotId": "slot-b",
					"displayName": "第二座小镇",
					"state": "healthy",
					"continueAvailable": true,
					"day": 3,
				},
			],
		},
		"actions": {
			"back": {
				"intent": "startup.close_load_game",
				"enabled": true,
				"disabledReason": "",
			},
			"continueSlot": {
				"intent": "session.continue_slot",
				"enabled": true,
				"disabledReason": "",
			},
			"deleteSlot": {
				"intent": "save.request_delete_slot",
				"enabled": true,
				"disabledReason": "",
			},
		},
		"operation": {
			"requestId": "",
			"intent": "",
			"status": "idle",
		},
		"error": null,
	}



func _test_startup_continue_failure_contract() -> void:
	var scene := ResourceLoader.load(
		"res://ui/startup/StartupScreen.tscn"
	) as PackedScene
	var startup := scene.instantiate() as Control if scene != null else null
	_expect(startup != null, "正式启动页无法实例化")
	if startup == null:
		return
	root.add_child(startup)
	var startup_intents: Array[String] = []
	startup.connect(
		"intent_requested",
		func(intent: String, _payload: Dictionary) -> void:
			startup_intents.append(intent),
	)
	var normal_applied := bool(startup.call(
		"apply_view_models",
		_startup_session_view_model(1),
		_startup_save_view_model(1),
	))
	_expect(normal_applied, "正式启动页无法应用正常 Continue ViewModel")
	var normal_snapshot := startup.call(
		"get_route_contract_snapshot"
	) as Dictionary
	_expect(
		String(normal_snapshot.get("continueErrorText", "")).is_empty(),
		"正常 Continue 不得显示失败文案",
	)
	_expect(
		bool(startup.call("request_continue_to_host")),
		"正常 Continue 必须可提交",
	)

	var failed_session := _startup_session_view_model(2)
	failed_session["status"] = "error"
	failed_session["operation"] = _startup_operation(
		"session.continue",
		"rejected",
		"continue-failed-public",
	)
	failed_session["error"] = {
		"code": "SESSION_PROVIDER_SETTINGS_NOT_READY",
		"message": "模型设置暂不可用，请完成配置后重试。",
		"retryable": false,
		"details": ["INTERNAL_PROVIDER_TRACE"],
	}
	_expect(
		bool(startup.call(
			"apply_view_models",
			failed_session,
			_startup_save_view_model(2),
		)),
		"正式启动页无法应用 Continue 失败 ViewModel",
	)
	var public_snapshot := startup.call(
		"get_route_contract_snapshot"
	) as Dictionary
	var public_message := String(
		public_snapshot.get("continueErrorText", "")
	)
	_expect(
		public_message == "模型设置暂不可用，请完成配置后重试。",
		"主 Continue 必须用公开失败文案替换提交提示",
	)
	var summary_label := startup.find_child(
		"SaveSummary",
		true,
		false,
	) as Label
	_expect(
		summary_label != null and summary_label.text == public_message,
		"主 Continue 失败文案必须在启动页可见",
	)
	_expect(
		not public_message.contains("SESSION_PROVIDER_SETTINGS_NOT_READY")
		and not public_message.contains("INTERNAL_PROVIDER_TRACE"),
		"主 Continue 可见文案不得泄露内部码或详情",
	)

	var code_only_session := _startup_session_view_model(3)
	code_only_session["status"] = "error"
	code_only_session["operation"] = _startup_operation(
		"session.continue",
		"rejected",
		"continue-failed-code-only",
	)
	code_only_session["error"] = {
		"code": "SESSION_PROVIDER_SETTINGS_NOT_READY",
		"message": "SESSION_PROVIDER_SETTINGS_NOT_READY",
		"retryable": false,
		"details": ["INTERNAL_PROVIDER_TRACE"],
	}
	_expect(
		bool(startup.call(
			"apply_view_models",
			code_only_session,
			_startup_save_view_model(3),
		)),
		"正式启动页无法应用无公开文案的 Continue 失败",
	)
	var fallback_message := String(
		(startup.call("get_route_contract_snapshot") as Dictionary).get(
			"continueErrorText",
			"",
		)
	)
	_expect(
		fallback_message == "继续游戏暂未完成，请重试。",
		"无公开失败文案时必须显示稳定通用提示",
	)
	_expect(
		not fallback_message.contains("SESSION_PROVIDER_SETTINGS_NOT_READY")
		and not fallback_message.contains("INTERNAL_PROVIDER_TRACE"),
		"Continue 通用提示不得泄露内部码或详情",
	)

	_expect(
		bool(startup.call(
			"apply_view_models",
			_startup_session_view_model(4),
			_startup_save_view_model(4),
		)),
		"正式启动页无法从 Continue 失败恢复正常状态",
	)
	var recovered_snapshot := startup.call(
		"get_route_contract_snapshot"
	) as Dictionary
	_expect(
		String(recovered_snapshot.get("continueErrorText", "")).is_empty(),
		"Continue 恢复正常后必须清除失败文案",
	)
	startup_intents.clear()
	_expect(
		bool(startup.call("request_new_game_to_host")),
		"开始新游戏请求可提交给 Host",
	)
	var repeated_escape := InputEventKey.new()
	repeated_escape.keycode = KEY_ESCAPE
	repeated_escape.pressed = true
	for _index in 3:
		startup.call("_unhandled_input", repeated_escape)
	_expect_equal(
		startup_intents,
		["session.new_game"],
		"开始新游戏等待 Host 时连续 Esc 不得再发退出请求",
	)
	_expect(
		not bool(startup.call("request_return_to_host")),
		"开始新游戏等待 Host 时直接返回请求也会被拦住",
	)
	_expect_equal(
		startup_intents,
		["session.new_game"],
		"等待 Host 时重复返回不会产生第二个导航意图",
	)
	root.remove_child(startup)
	startup.free()



func _startup_session_view_model(revision: int) -> Dictionary:
	return {
		"scope": "session",
		"status": "ready",
		"revision": revision,
		"data": {
			"source": "formal",
			"capabilityMode": "formal",
			"formalReady": true,
			"validationMode": "formal",
			"providerStatus": "available",
			"loadSummary": {"compactTownSummary": "春日镇"},
		},
		"actions": {
			"newGame": {
				"intent": "session.new_game",
				"enabled": true,
				"disabledReason": "",
			},
			"continue": {
				"intent": "session.continue",
				"enabled": true,
				"disabledReason": "",
			},
			"loadGame": {
				"intent": "startup.load_game",
				"enabled": true,
				"disabledReason": "",
			},
		},
		"operation": _startup_operation("", "idle", ""),
		"error": null,
	}



func _startup_save_view_model(revision: int) -> Dictionary:
	return {
		"scope": "save",
		"status": "ready",
		"revision": revision,
		"data": {
			"source": "formal",
			"capabilityMode": "formal",
			"formalReady": true,
			"canContinue": true,
			"selectedSaveId": "slot-a:1",
			"slots": [{
				"slotId": "slot-a",
				"sessionId": "session-a",
				"saveRevision": 1,
			}],
		},
		"actions": {
			"continue": {
				"intent": "session.continue",
				"enabled": true,
				"disabledReason": "",
			},
		},
		"operation": _startup_operation("", "idle", ""),
		"error": null,
	}



func _startup_operation(
	intent: String,
	status: String,
	request_id: String,
) -> Dictionary:
	return {
		"requestId": request_id,
		"intent": intent,
		"status": status,
		"submittedAtMsec": 0,
		"completedAtMsec": 0,
	}



func _test_formal_export_filters() -> void:
	var preset_source := FileAccess.get_file_as_string(
		"res://export_presets.cfg"
	)
	_expect(
		not preset_source.is_empty(),
		"正式导出配置必须存在",
	)
	for pattern: String in FORMAL_EXPORT_INCLUDE_FILTERS:
		_expect(
			_export_filter_contains(
				preset_source,
				"include_filter",
				pattern,
			),
			"正式导出必须包含运行数据：%s" % pattern,
		)
	for pattern: String in FORMAL_EXPORT_EXCLUDE_FILTERS:
		_expect(
			_export_filter_contains(
				preset_source,
				"exclude_filter",
				pattern,
			),
			"正式导出必须排除开发资源：%s" % pattern,
		)



func _test_formal_dependency_closure() -> void:
	var pending: Array[String] = REQUIRED_FORMAL_PATHS.duplicate()
	var visited: Dictionary = {}
	while not pending.is_empty():
		var path: String = pending.pop_front()
		if path.is_empty() or visited.has(path):
			continue
		visited[path] = true
		_expect(
			not _path_has_forbidden_directory(path),
			"正式运行依赖混入开发资源：%s" % path,
		)
		if not ResourceLoader.exists(path):
			continue
		var dependencies: PackedStringArray = (
			ResourceLoader.get_dependencies(path)
		)
		for dependency_value: String in dependencies:
			var dependency := String(dependency_value).get_slice(
				"::",
				0,
			)
			if dependency.begins_with("res://"):
				pending.append(dependency)
	for legacy_path: String in FORBIDDEN_LEGACY_RUNTIME_PATHS:
		_expect(
			not visited.has(legacy_path),
			"正式运行依赖仍引用退役页面：%s" % legacy_path,
		)



func _test_formal_route_registry_contract() -> void:
	var host_source := FileAccess.get_file_as_string(
		"res://world/presentation/ui/TownUiRuntimeHost.gd"
	)
	_expect(not host_source.is_empty(), "正式 UI Host 源码必须可读取")
	for route: String in FORMAL_ROUTE_SCENES:
		var scene_path := String(FORMAL_ROUTE_SCENES[route])
		_expect(
			host_source.contains(
				"&\"%s\": \"%s\"" % [route, scene_path]
			),
			"正式 UI 路由未指向唯一页面：%s -> %s" % [
				route,
				scene_path,
			],
		)
	for legacy_path: String in FORBIDDEN_LEGACY_RUNTIME_PATHS:
		_expect(
			not host_source.contains(legacy_path),
			"正式 UI Host 仍引用退役页面：%s" % legacy_path,
		)



func _test_formal_runtime_asset_paths() -> void:
	for path: String in FORMAL_RUNTIME_ASSET_PATHS:
		_expect(
			not _path_has_forbidden_directory(path),
			"正式运行素材仍使用开发目录：%s" % path,
		)
		_expect(
			ResourceLoader.exists(path) or FileAccess.file_exists(path),
			"正式运行素材缺失：%s" % path,
		)
	var resident_catalog := _read_json(
		"res://world/data/town/resident_catalog.json"
	)
	var residents_value: Variant = resident_catalog.get("residents", [])
	_expect(residents_value is Array, "正式居民目录必须包含 residents 数组")
	if not residents_value is Array:
		return
	for resident_value: Variant in residents_value:
		_expect(resident_value is Dictionary, "正式居民条目必须是对象")
		if not resident_value is Dictionary:
			continue
		var resident: Dictionary = resident_value
		var resident_id := String(resident.get("residentId", "unknown"))
		var presentation_value: Variant = resident.get("presentation", {})
		_expect(
			presentation_value is Dictionary,
			"正式居民展示信息必须是对象：%s" % resident_id,
		)
		if not presentation_value is Dictionary:
			continue
		var presentation: Dictionary = presentation_value
		for field: String in ["spritePath", "portraitPath"]:
			var path := String(presentation.get(field, ""))
			_expect(
				not path.is_empty(),
				"正式居民素材路径为空：%s.%s" % [resident_id, field],
			)
			_expect(
				not _path_has_forbidden_directory(path),
				"正式居民素材仍使用开发目录：%s.%s -> %s" % [
					resident_id,
					field,
					path,
				],
			)
			_expect(
				ResourceLoader.exists(path) or FileAccess.file_exists(path),
				"正式居民素材缺失：%s.%s -> %s" % [
					resident_id,
					field,
					path,
				],
			)



func _export_filter_contains(
	source: String,
	key: String,
	expected_pattern: String,
) -> bool:
	for line: String in source.split("\n"):
		if not line.begins_with("%s=" % key):
			continue
		var raw := line.trim_prefix("%s=" % key).strip_edges()
		if raw.begins_with("\"") and raw.ends_with("\""):
			raw = raw.substr(1, raw.length() - 2)
		var patterns := raw.split(",", false)
		for pattern: String in patterns:
			if pattern.strip_edges() == expected_pattern:
				return true
	return false



func _path_has_forbidden_directory(path: String) -> bool:
	for component: String in path.trim_prefix("res://").split("/"):
		if FORBIDDEN_DIRECTORY_NAMES.has(component.to_lower()):
			return true
	return false



func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value as Dictionary if value is Dictionary else {}



func _valid_sha256(value: Variant) -> bool:
	if not value is String or (value as String).length() != 64:
		return false
	for character in (value as String).to_lower():
		if character not in "0123456789abcdef":
			return false
	return true



func _scenario_game_flow_resident_model_assignment_route() -> void:
	OS.set_environment("AI_TOWN_INTERNAL_PLAYTEST", "")
	OS.set_environment(
		"AI_TOWN_CUSTOM_RESIDENT_LIBRARY_PATH",
		CUSTOM_RESIDENT_LIBRARY_TEST_PATH,
	)
	_remove_custom_resident_library_test_file()
	var host := root.get_node_or_null("GameFlowHost")
	_expect(host != null, "formal GameFlowHost autoload exists")
	if host == null:
		return
	var provider := ProviderHarness.new()
	var settings := ProviderSettingsHarness.new()
	host.set("_startup_provider_service", provider)
	host.set("_startup_provider_settings_service", settings)
	host.call("_reset_resident_model_assignment_session")

	var selection := RESIDENT_SELECTION_SCENE.instantiate() as Control
	var initial_view_model := host.call(
		"_build_formal_resident_selection_view_model",
	) as Dictionary
	var initial_data := initial_view_model.get("data", {}) as Dictionary
	var initial_actions := initial_view_model.get("actions", {}) as Dictionary
	var custom_action := initial_actions.get("custom_resident", {}) as Dictionary
	_expect_equal(
		(initial_data.get("resident_catalog", []) as Array).size(),
		16,
		"formal base catalog keeps all 16 read-only presets",
	)
	_expect_equal(custom_action.get("enabled"), true, "approved custom creator is enabled")
	_expect_equal(
		custom_action.get("disabled_reason"),
		"",
		"approved custom creator has no mounting gate",
	)
	_expect(
		bool(selection.call("apply_view_model", initial_view_model)),
		"formal ResidentSelection ViewModel applies before mounting",
	)
	root.add_child(selection)
	current_scene = selection
	host.set("_bound_scene_id", 0)
	host.call("_bind_current_scene")
	await _wait_frames(3)
	selection.call("_change_resident_page", 2)
	var third_page_resident_id := String(
		((selection.get("_residents") as Array)[12] as Dictionary).get(
			"resident_id",
			"",
		),
	)
	selection.call("_toggle_resident", 12)
	await _wait_frames(2)
	var selection_data_after_third_page_toggle := (
		(selection.get("_view_model") as Dictionary).get("data", {}) as Dictionary
	)
	_expect_equal(
		selection.get("_resident_page"),
		2,
		"third-page selection stays on the third page after Host refresh",
	)
	_expect_equal(
		selection_data_after_third_page_toggle.get("focused_resident_id"),
		third_page_resident_id,
		"Host refresh keeps the clicked third-page resident focused",
	)
	_expect(
		(selection_data_after_third_page_toggle.get(
			"selected_resident_ids",
			[],
		) as Array).has(third_page_resident_id),
		"third-page selection survives the Host round trip",
	)
	selection.call("_toggle_resident", 12)
	await _wait_frames(2)
	selection.call("_change_resident_page", -2)
	var custom_button := selection.find_child(
		"CustomResidentButton",
		true,
		false,
	) as Button
	_expect(
		custom_button != null and not custom_button.disabled,
		"custom creator entry is enabled",
	)
	_expect(
		selection.is_connected(
			"custom_resident_requested",
			Callable(host, "_on_custom_resident_requested"),
		),
		"ResidentSelection custom signal is wired only to the dedicated creator route",
	)
	var creator_selection_revision := int(
		(selection.get("_view_model") as Dictionary).get("revision", 0)
	)
	host.call("_on_custom_resident_requested", creator_selection_revision - 1)
	await process_frame
	var stale_notice := selection.find_child("PageNotice", true, false) as Label
	_expect(
		stale_notice != null
		and stale_notice.visible
		and stale_notice.text.contains("重新点一次"),
		"stale custom creator navigation gives the player a visible recovery hint",
	)
	host.call(
		"_on_custom_resident_requested",
		creator_selection_revision,
	)
	await _wait_frames(3)
	_expect(
		selection.get_node_or_null("ResidentEditorRoute") == null,
		"custom request never mounts ResidentEditor",
	)
	var creator := selection.get_node_or_null(
		"CustomResidentCreatorRoute",
	) as Control
	_expect(creator != null, "custom request mounts the dedicated creator")
	if creator != null:
		_expect_equal(
			creator.get("_adapter"),
			host.get("_startup_ui_adapter"),
			"custom creator uses the same formal pre-game Adapter",
		)
		_expect_equal(
			(host.call("get_flow_snapshot") as Dictionary).get("route"),
			"custom_resident_creator",
			"flow snapshot exposes the custom creator overlay",
		)
		var creator_vm := (host.get("_startup_ui_adapter") as Node).call(
			"get_view_model",
			"custom_resident_creator",
		) as Dictionary
		var wardrobe_action := (
			creator_vm.get("actions", {}) as Dictionary
		).get("openWardrobe", {}) as Dictionary
		_expect_equal(
			wardrobe_action.get("enabled"),
			true,
			"formal complete-set wardrobe is available from the custom creator",
		)
		_expect_equal(
			wardrobe_action.get("disabledReason"),
			"",
			"available wardrobe has no stale missing-route reason",
		)
		var wardrobe_button := creator.find_child(
			"OpenWardrobeButton",
			true,
			false,
		) as Button
		_expect(
			wardrobe_button != null and not wardrobe_button.disabled,
			"creator exposes the formal complete-set wardrobe entry",
		)
		if wardrobe_button != null and not wardrobe_button.disabled:
			wardrobe_button.pressed.emit()
			await _wait_frames(2)
			var wardrobe_popup := creator.get("_complete_set_popup") as PopupPanel
			_expect(
				wardrobe_popup != null and wardrobe_popup.visible,
				"creator opens its formal complete-set wardrobe",
			)
			if wardrobe_popup != null:
				wardrobe_popup.hide()
		var selection_revision_before_cancel := int(
			(selection.get("_view_model") as Dictionary).get("revision", 0),
		)
		var pool_revision_before_cancel := int(
			(host.get("_custom_resident_candidate_pool") as Object).call(
				"candidate_pool_revision",
			),
		)
		creator.call("_request_action", "cancel")
		await _wait_frames(3)
		_expect(
			selection.get_node_or_null("CustomResidentCreatorRoute") == null,
			"custom creator cancel returns to ResidentSelection",
		)
		_expect_equal(
			int((selection.get("_view_model") as Dictionary).get("revision", 0)),
			selection_revision_before_cancel,
			"custom creator cancel leaves ResidentSelection revision unchanged",
		)
		_expect_equal(
			int((host.get("_custom_resident_candidate_pool") as Object).call(
				"candidate_pool_revision",
			)),
			pool_revision_before_cancel,
			"custom creator cancel leaves candidate-pool revision unchanged",
		)
	_expect_equal(
		(
			((selection.get("_view_model") as Dictionary).get("data", {}) as Dictionary)
			.get("resident_catalog", []) as Array
		).size(),
		16,
		"cancelled custom request leaves the 16-preset catalog unchanged",
	)
	var selection_revision := int(
		(selection.get("_view_model") as Dictionary).get("revision", 0),
	)
	host.call("_on_custom_resident_requested", selection_revision)
	await _wait_frames(3)
	creator = selection.get_node_or_null("CustomResidentCreatorRoute") as Control
	_expect(creator != null, "custom creator reopens against the same session pool")
	if creator != null:
		var creator_adapter := host.get("_startup_ui_adapter") as Node
		var full_personality := (
			"耐心且谨慎，喜欢先核对公开事实，再把复杂问题讲得清楚完整"
		)
		var creation_vm := creator_adapter.call(
			"get_view_model",
			"custom_resident_creator",
		) as Dictionary
		var creation_data := creation_vm.get("data", {}) as Dictionary
		_expect_ok(
			creator_adapter.call(
				"dispatch",
				"custom_resident_creator.update_fields",
				{
					"revision": int(creation_vm.get("revision", 0)),
					"draftId": String(creation_data.get("draftId", "")),
					"fields": {
						"name": "路由测试居民",
						"gender": "女",
						"age": 29,
						"desire": "确认候选池只在开局选择流程中存在",
						"personality": full_personality,
						"speech": "先核对事实再回答",
					},
				},
			) as Dictionary,
			"creator accepts a complete formal draft",
		)
		await _wait_frames(2)
		creation_vm = creator_adapter.call(
			"get_view_model",
			"custom_resident_creator",
		) as Dictionary
		creation_data = creation_vm.get("data", {}) as Dictionary
		# ResidentSelection owns a looping connection pulse. Kill the old target's
		# tween before the candidate-count rebuild frees and replaces that target.
		for tween in get_processed_tweens():
			tween.kill()
		creator.call("_request_action", "create", {
			"candidatePoolRevision": int(
				creation_data.get("candidatePoolRevision", -1),
			),
		})
		await _wait_frames(4)
		_expect(
			selection.get_node_or_null("CustomResidentCreatorRoute") == null,
			"successful creation returns to ResidentSelection",
		)
		var projected_data := (
			(selection.get("_view_model") as Dictionary).get("data", {}) as Dictionary
		)
		var custom_resident_id := ""
		var custom_selection_entry: Dictionary = {}
		for resident_value: Variant in projected_data.get("residents", []) as Array:
			var resident := resident_value as Dictionary
			if String(resident.get("source", "")) == "custom":
				custom_resident_id = String(resident.get("resident_id", ""))
				custom_selection_entry = resident.duplicate(true)
				break
		_expect(not custom_resident_id.is_empty(), "created candidate is projected once")
		_expect_equal(
			(projected_data.get("residents", []) as Array).size(),
			17,
			"selection projection appends one custom entry",
		)
		_expect_equal(
			projected_data.get("focused_resident_id"),
			custom_resident_id,
			"selection projection focuses the new custom resident",
		)
		_expect(
			not (projected_data.get("selected_resident_ids", []) as Array).has(
				custom_resident_id,
			),
			"created candidate is not auto-selected into the final 15",
		)
		_expect_equal(
			custom_selection_entry.get("selection_summary"),
			full_personality.left(24),
			"ResidentSelection receives the dedicated <=24-character summary",
		)
		_expect_equal(
			custom_selection_entry.get("one_line_role"),
			custom_selection_entry.get("selection_summary"),
			"legacy one-line role maps to the dedicated selection summary",
		)
		_expect_equal(
			custom_selection_entry.get("personality"),
			full_personality,
			"ResidentSelection keeps the complete personality independently",
		)
		_expect(
			String(custom_selection_entry.get("selection_summary", "")).length() <= 24,
			"ResidentSelection summary respects the 24-character contract",
		)
		var merged_catalog := host.call("_formal_new_game_catalog") as Dictionary
		_expect_equal(
			((merged_catalog.get("catalog", {}) as Dictionary).get(
				"residents",
				[],
			) as Array).size(),
			17,
			"opening/model assignment sees pool.get_merged_catalog",
		)
		var assignment_selection_data := projected_data.duplicate(true)
		var assignment_selected_ids := (
			assignment_selection_data.get(
				"recommended_resident_ids",
				[],
			) as Array
		).duplicate()
		var replaced_assignment_resident_id := String(
			assignment_selected_ids.pop_front()
		)
		assignment_selected_ids.append(custom_resident_id)
		assignment_selection_data["selected_resident_ids"] = (
			assignment_selected_ids
		)
		RESIDENT_CATALOG.update_confirmation_payload(
			assignment_selection_data,
			"",
			"",
			23,
		)
		var assignment_projection := host.call(
			"_project_resident_model_assignment_catalog",
			merged_catalog.get("catalog", {}) as Dictionary,
			assignment_selection_data.get(
				"confirmation_payload",
				{},
			) as Dictionary,
		) as Dictionary
		_expect(
			bool(assignment_projection.get("ok", false)),
			"model assignment projects the selected custom roster (result=%s)" % assignment_projection,
		)
		var assignment_catalog_residents := (
			(assignment_projection.get("catalog", {}) as Dictionary).get(
				"residents",
				[],
			) as Array
		)
		var assignment_catalog_ids: Array[String] = []
		for assignment_resident_value: Variant in assignment_catalog_residents:
			assignment_catalog_ids.append(String(
				(assignment_resident_value as Dictionary).get("residentId", "")
			))
		_expect_equal(
			assignment_catalog_residents.size(),
			15,
			"model assignment receives exactly the selected fifteen residents",
		)
		_expect(
			assignment_catalog_ids.has(custom_resident_id)
			and not assignment_catalog_ids.has(
				replaced_assignment_resident_id,
			),
			"model assignment keeps the custom resident and excludes the replaced preset",
		)
		_expect(
			selection.is_connected(
				"residents_delete_requested",
				Callable(host, "_on_residents_delete_requested"),
			),
			"resident delete-mode confirmation is wired to the session Host handler",
		)
		selection.call("_toggle_resident", 16)
		await _wait_frames(2)
		var selected_custom_data := (
			(selection.get("_view_model") as Dictionary).get("data", {}) as Dictionary
		)
		_expect(
			(selected_custom_data.get("selected_resident_ids", []) as Array).has(
				custom_resident_id,
			),
			"custom candidate can be selected before deletion",
		)
		var deleted_preset_id := String(
			((selected_custom_data.get("residents", []) as Array)[0] as Dictionary).get(
				"resident_id",
				"",
			),
		)
		var delete_button := selection.find_child(
			"CustomResidentDeleteButton",
			true,
			false,
		) as Button
		_expect(
			delete_button != null and delete_button.visible and not delete_button.disabled,
			"delete-mode button remains visible for every focused resident",
		)
		if delete_button != null:
			delete_button.pressed.emit()
			await _wait_frames(1)
			_expect(
				bool(selection.get("_delete_mode_active")),
				"one delete-button click enters the independent delete mode",
			)
			selection.call("_toggle_resident", 16)
			selection.call("_toggle_resident", 0)
			await _wait_frames(1)
			var delete_selected := (
				selection.get("_delete_selected_by_id") as Dictionary
			)
			_expect(
				delete_selected.has(custom_resident_id)
				and delete_selected.has(deleted_preset_id)
				and (
					((selection.get("_view_model") as Dictionary).get("data", {}) as Dictionary)
					.get("selected_resident_ids", []) as Array
				).has(custom_resident_id),
				"delete mode batch-marks preset and custom residents independently from the roster",
			)
			var delete_state_icon := selection.find_child(
				"ResidentStateIcon16",
				true,
				false,
			) as TextureRect
			var delete_texture := delete_state_icon.texture as AtlasTexture
			_expect(
				delete_state_icon != null
				and delete_state_icon.visible
				and delete_texture != null
				and delete_texture.atlas.resource_path.ends_with(
					"icons_v2/delete_check_red_v53.png",
				),
				"delete mode uses its authored red check instead of the roster leaf",
			)
			var delete_confirm := selection.find_child(
				"ConfirmRosterButton",
				true,
				false,
			) as Button
			delete_confirm.pressed.emit()
			await _wait_frames(4)
		var deleted_projection := (
			(selection.get("_view_model") as Dictionary).get("data", {}) as Dictionary
		)
		_expect_equal(
			(deleted_projection.get("residents", []) as Array).size(),
			15,
			"one delete-mode confirmation removes the marked preset and custom residents",
		)
		_expect(
			not (deleted_projection.get("selected_resident_ids", []) as Array).has(
				custom_resident_id,
			),
			"deleting a selected custom candidate also removes it from the roster draft",
		)
		_expect_equal(
			(
				((host.call("_formal_new_game_catalog") as Dictionary).get(
					"catalog",
					{},
				) as Dictionary).get("residents", []) as Array
			).size(),
			16,
			"confirmed delete removes the candidate from the merged session catalog",
		)
		_expect(
			(deleted_projection.get("excluded_resident_ids", []) as Array).has(
				deleted_preset_id,
			),
			"batch preset deletion is preserved as a session exclusion",
		)
		_expect_equal(
			(deleted_projection.get("resident_catalog", []) as Array).size(),
			16,
			"session preset deletion never mutates the read-only base catalog",
		)
		var floor_resident_id := String(
			((deleted_projection.get("residents", []) as Array)[0] as Dictionary).get(
				"resident_id",
				"",
			),
		)
		host.call(
			"_on_residents_delete_requested",
			[floor_resident_id],
			int(deleted_projection.get("candidate_pool_revision", 0)),
			int((host.get("_resident_selection_vm") as Dictionary).get("revision", 0)),
		)
		_expect_equal(
			(host.get("_last_result") as Dictionary).get("errorCode"),
			"RESIDENT_DELETE_MINIMUM_CANDIDATES_REQUIRED",
			"Host rejects every deletion that would leave fewer than 15 candidates",
		)
		_expect_equal(
			(
				((host.get("_resident_selection_vm") as Dictionary).get(
					"data",
					{},
				) as Dictionary).get("residents", []) as Array
			).size(),
			15,
			"rejected floor deletion leaves the candidate list unchanged",
		)
	host.set("_resident_editor_saved_catalog", {"residents": []})
	selection.call("_apply_recommended_selection", false)
	await _wait_frames(2)

	var confirm := selection.find_child(
		"ConfirmRosterButton",
		true,
		false,
	) as Button
	var current_roster_draft := (
		selection.call("_build_current_roster_draft") as Dictionary
	)
	_expect(
		confirm != null and not confirm.disabled,
		"formal 15-resident roster can continue: selected=%d residents=%d tooltip=%s roster=%s validation=%s"
		% [
			(selection.get("_selected_by_id") as Dictionary).size(),
			(selection.get("_residents") as Array).size(),
			confirm.tooltip_text if confirm != null else "<missing>",
			JSON.stringify(current_roster_draft),
			JSON.stringify(
				selection.call(
					"_validate_confirmation_payload",
					current_roster_draft,
				),
			),
		],
	)
	if confirm == null or confirm.disabled:
		return
	var expected_before_confirm := (
		(host.get("_resident_selection_vm") as Dictionary).get("data", {}) as Dictionary
	).get("confirmation_payload", {}) as Dictionary
	var emitted_before_confirm := selection.call(
		"_build_current_roster_draft",
	) as Dictionary
	_expect(
		bool(host.call(
			"_resident_selection_drafts_match",
			emitted_before_confirm,
			expected_before_confirm,
		)),
		"ResidentSelection emits the Host-authoritative resident/space draft",
	)
	_expect(
		not (
			(emitted_before_confirm.get("slots", []) as Array)[0] as Dictionary
		).has("llmBinding"),
		"selection input may omit llmBinding for service normalization",
	)
	confirm.pressed.emit()
	await _wait_frames(3)
	var page := selection.get_node_or_null(
		"ResidentModelAssignmentRoute",
	) as Control
	_expect(
		page != null,
		"roster confirmation opens the approved assignment page (lastResult=%s)" % [
			JSON.stringify(host.get("_last_result")),
		],
	)
	if page == null:
		return
	_expect_equal(
		page.get("_adapter"),
		host.get("_startup_ui_adapter"),
		"assignment page uses the one formal pre-game TownUiAdapter",
	)
	_expect_equal(
		(host.call("get_flow_snapshot") as Dictionary).get("route"),
		"resident_model_assignment",
		"formal flow snapshot exposes the assignment overlay route",
	)
	var confirmed_draft := (
		((selection.get("_view_model") as Dictionary).get("data", {}) as Dictionary)
		.get("confirmation_payload", {}) as Dictionary
	).duplicate(true)
	host.call("_open_resident_model_assignment", confirmed_draft)
	host.call("_open_resident_model_assignment", confirmed_draft)
	_expect_equal(
		selection.find_children(
			"ResidentModelAssignmentRoute",
			"Control",
			true,
			false,
		).size(),
		1,
		"assignment route has one owner",
	)
	var adapter := host.get("_startup_ui_adapter") as Node
	var view_model := adapter.call(
		"get_view_model",
		"resident_model_assignment",
	) as Dictionary
	_expect_equal(view_model.get("status"), "ready", "formal assignment scope is ready")
	_expect_equal(
		(view_model.get("data", {}) as Dictionary).get("formalReady"),
		true,
		"formal assignment data is runtime-ready",
	)
	_expect_equal(
		((view_model.get("data", {}) as Dictionary).get("residents", []) as Array).size(),
		15,
		"assignment scope receives the confirmed 15-slot draft",
	)
	_expect_equal(host.get("_bootstrap"), null, "opening assignment does not start or persist")

	host.call(
		"_on_resident_model_assignment_back_requested",
		int(view_model.get("revision", 0)) - 1,
	)
	await _wait_frames(2)
	_expect(
		selection.get_node_or_null("ResidentModelAssignmentRoute") != null,
		"stale Back revision does not close the page",
	)
	_expect_equal(
		(host.get("_last_result") as Dictionary).get("errorCode"),
		"RESIDENT_MODEL_ASSIGNMENT_ROUTE_REVISION_STALE",
		"stale Back exposes the stable route error",
	)
	var assignment_rows := (
		(view_model.get("data", {}) as Dictionary).get("residents", []) as Array
	)
	var preserved_resident_id := String(
		(assignment_rows[0] as Dictionary).get("residentId", "")
	)
	var target_binding := {
		"mode": "model",
		"providerId": "deepseek",
		"modelId": "deepseek-v4-flash",
	}
	_expect_ok(
		_dispatch_assignment(
			adapter,
			"resident_model_assignment.select_resident",
			{"residentId": preserved_resident_id},
		),
		"working draft selects a resident before Back",
	)
	_expect_ok(
		_dispatch_assignment(
			adapter,
			"resident_model_assignment.assign_one",
			{
				"residentId": preserved_resident_id,
				"llmBinding": target_binding,
			},
		),
		"working draft changes before Back",
	)

	page.call("_request_back")
	await process_frame
	var dirty_back_confirmation := page.get(
		"_exit_confirmation",
	) as FormalConfirmationDialog
	_expect(
		dirty_back_confirmation != null and dirty_back_confirmation.visible,
		"dirty Back asks once before leaving model assignment",
	)
	page.call("_request_back")
	await process_frame
	_expect(
		selection.get_node_or_null("ResidentModelAssignmentRoute") == page
		and dirty_back_confirmation != null
		and dirty_back_confirmation.visible,
		"repeated Back cannot bypass the dirty assignment confirmation",
	)
	if dirty_back_confirmation != null:
		dirty_back_confirmation.confirmed.emit()
	await _wait_frames(3)
	_expect(
		selection.get_node_or_null("ResidentModelAssignmentRoute") == null,
		"Back returns to the same ResidentSelection owner",
	)
	_expect_equal(
		root.get_viewport().gui_get_focus_owner(),
		confirm,
		"Back restores ResidentSelection confirm focus",
	)
	_expect_equal(
		(host.call("get_flow_snapshot") as Dictionary).get("route"),
		"resident_selection",
		"formal flow snapshot returns to ResidentSelection after Back",
	)
	var preserved_draft := (
		host.get("_resident_model_assignment_preserved_draft") as Dictionary
	)
	_expect_equal(
		_binding_for(preserved_draft, preserved_resident_id),
		target_binding,
		"service back_requested preserves the current working model draft",
	)
	_validate_resident_id_merge(
		host,
		initial_data.get("resident_catalog", []) as Array,
		confirmed_draft,
		preserved_resident_id,
	)

	confirm.pressed.emit()
	await _wait_frames(3)
	page = selection.get_node_or_null("ResidentModelAssignmentRoute") as Control
	_expect(page != null, "assignment route can be opened again for ESC")
	if page != null:
		var reopened_view_model := adapter.call(
			"get_view_model",
			"resident_model_assignment",
		) as Dictionary
		_expect_equal(
			_binding_for_view_model(reopened_view_model, preserved_resident_id),
			target_binding,
			"reopening merges the preserved working draft by residentId",
		)
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		page.call("_unhandled_input", escape)
		await _wait_frames(3)
		_expect(
			selection.get_node_or_null("ResidentModelAssignmentRoute") == null,
			"clean ESC returns to the same ResidentSelection owner",
		)
		_expect_equal(
			root.get_viewport().gui_get_focus_owner(),
			confirm,
			"ESC restores ResidentSelection confirm focus",
		)

	confirm.pressed.emit()
	await _wait_frames(3)
	page = selection.get_node_or_null("ResidentModelAssignmentRoute") as Control
	_expect(page != null, "assignment route can be opened again for commit")
	if page != null:
		var commit_view_model := adapter.call(
			"get_view_model",
			"resident_model_assignment",
		) as Dictionary
		for resident_value: Variant in (
			(commit_view_model.get("data", {}) as Dictionary).get(
				"residents",
				[],
			) as Array
		):
			var resident_id := String(
				(resident_value as Dictionary).get("residentId", "")
			)
			_expect_ok(
				_dispatch_assignment(
					adapter,
					"resident_model_assignment.assign_one",
					{
						"residentId": resident_id,
						"llmBinding": target_binding,
					},
				),
				"all 15 residents receive a formal binding before apply",
			)
		commit_view_model = adapter.call(
			"get_view_model",
			"resident_model_assignment",
		) as Dictionary
		_expect_equal(
			int((commit_view_model.get("data", {}) as Dictionary).get(
				"completedCount",
				0,
			)),
			15,
			"completion modal starts from exactly 15 valid assignments",
		)
		var apply_intents: Array[String] = []
		page.connect(
			"intent_requested",
			func(intent: String, _payload: Dictionary) -> void:
				if intent == "resident_model_assignment.apply_draft":
					apply_intents.append(intent)
		)
		settings.stop_before_persist = true
		_expect_equal(host.get("_bootstrap"), null, "draft is not persisted before apply")
		page.call("_open_completion_modal")
		var modal_start := page.find_child(
			"ModalStartButton",
			true,
			false,
		) as Button
		_expect(
			modal_start != null and not modal_start.disabled,
			"completion modal exposes one operable Start Game Button",
		)
		var before_start_view_model := adapter.call(
			"get_view_model",
			"resident_model_assignment",
		) as Dictionary
		var revision_before_start := int(before_start_view_model.get("revision", -1))
		var runtime_calls_before_start := settings.runtime_configuration_calls
		var provider_validation_calls_before_start := provider.validation_calls
		provider.fail_on_validation_call = provider_validation_calls_before_start + 2
		if modal_start != null and not modal_start.disabled:
			modal_start.pressed.emit()
		var loading_view_model := adapter.call(
			"get_view_model",
			"resident_model_assignment",
		) as Dictionary
		_expect_equal(
			(loading_view_model.get("operation", {}) as Dictionary).get("status"),
			"loading",
			"accepted apply keeps the assignment page in startup loading",
		)
		_expect(
			selection.get_node_or_null("ResidentModelAssignmentRoute") == page,
			"assignment owner remains mounted while startup is pending",
		)
		await _wait_frames(2)
		loading_view_model = adapter.call(
			"get_view_model",
			"resident_model_assignment",
		) as Dictionary
		_expect_equal(
			apply_intents.size(),
			1,
			"one Start Game click dispatches applyDraft exactly once",
		)
		_expect_equal(
			loading_view_model.get("revision"),
			revision_before_start + 2,
			"one Start Game click publishes the service loading and completion revisions",
		)
		await _wait_frames(4)
		_expect(
			selection.get_node_or_null("ResidentModelAssignmentRoute") == page,
			"startup failure keeps the assignment owner mounted",
		)
		_expect_equal(
			(host.get("_last_result") as Dictionary).get("errorCode"),
			"TEST_STOP_BEFORE_PERSIST",
			"Host continuation starts only from draft_applied and stops before persistence",
		)
		var failure_view_model := adapter.call(
			"get_view_model",
			"resident_model_assignment",
		) as Dictionary
		_expect_equal(
			failure_view_model.get("status"),
			"rejected",
			"non-retryable startup failure is projected onto the assignment page",
		)
		_expect_equal(
			(failure_view_model.get("error", {}) as Dictionary).get("code"),
			"TEST_STOP_BEFORE_PERSIST",
			"assignment page receives the real startup errorCode",
		)
		_expect_equal(
			failure_view_model.get("revision"),
			loading_view_model.get("revision"),
			"Host startup failure preserves the confirmed service revision",
		)
		_expect_equal(
			(((host.get("_resident_model_assignment_service") as Object).call(
				"get_committed_draft",
			) as Dictionary).get("slots", []) as Array).size(),
			15,
			"startup failure preserves the committed 15-slot draft",
		)
		_expect_equal(
			settings.runtime_configuration_calls,
			runtime_calls_before_start,
			"formal start does not gate final bindings on the unrelated selected Provider",
		)
		_expect_equal(
			provider.validation_calls,
			provider_validation_calls_before_start + 2,
			"single applyDraft performs one service validation and one Host binding preflight",
		)
		_expect_equal(
			page.get("_completion_modal_open"),
			true,
			"startup failure reopens the existing completion modal",
		)
		var failure_modal_body := page.get("_native_modal_body") as Label
		_expect(
			failure_modal_body != null
			and failure_modal_body.text.contains("TEST_STOP_BEFORE_PERSIST"),
			"startup failure remains visibly actionable in the completion modal",
		)
		var detailed_failure_message := host.call(
			"_resident_model_assignment_failure_message",
			{
				"ok": false,
				"errorCode": "SESSION_OPENING_CONFIG_INVALID",
				"retryable": false,
				"errors": [{
					"path": "openingConfig",
					"code": "SESSION_OPENING_CONFIG_INVALID",
					"meta": {
						"playerMessage": "居民开局属性包含未允许字段",
					},
				}],
			},
		) as String
		_expect(
			detailed_failure_message.contains("SESSION_OPENING_CONFIG_INVALID")
			and detailed_failure_message.contains("居民开局属性包含未允许字段"),
			"startup failure exposes nested validation detail instead of only an error code",
		)
		var archive_failure_message := host.call(
			"_resident_model_assignment_failure_message",
			{
				"ok": false,
				"errorCode": "FORMAL_SLOT_ARCHIVE_STORE_FAILED",
				"retryable": true,
			},
		) as String
		_expect(
			archive_failure_message.begins_with("存档暂时无法处理")
			and not archive_failure_message.contains("居民模型分配尚未完成"),
			"archive startup failure keeps storage copy instead of model-assignment copy",
		)
		var runtime_failure_message := host.call(
			"_resident_model_assignment_failure_message",
			{
				"ok": false,
				"errorCode": "TOWN_RUNTIME_SCENE_UNAVAILABLE",
				"retryable": false,
			},
		) as String
		_expect(
			runtime_failure_message.begins_with("小镇场景暂不可用")
			and not runtime_failure_message.contains("居民模型分配尚未完成"),
			"runtime startup failure keeps scene copy instead of model-assignment copy",
		)
		var unknown_startup_failure_message := host.call(
			"_resident_model_assignment_failure_message",
			{
				"ok": false,
				"errorCode": "TEST_UNKNOWN_STARTUP_FAILURE",
				"retryable": true,
			},
		) as String
		_expect(
			unknown_startup_failure_message.begins_with("小镇暂时无法启动")
			and not unknown_startup_failure_message.contains("居民模型分配尚未完成"),
			"unknown startup failure uses generic startup copy instead of model-assignment copy",
		)
		var internal_failure := {
			"ok": false,
			"errorCode": "TEST_UNKNOWN_INTERNAL_FAILURE",
			"message": "backend shard provider-east-03 rejected request",
			"errors": [{
				"message": "credential_slot=prod-secret trace=provider-9821",
				"meta": {
					"message": "private validation trace resident-17",
				},
			}],
		}
		var private_assignment_message := host.call(
			"_resident_model_assignment_failure_message",
			internal_failure,
		) as String
		_expect(
			not private_assignment_message.contains("backend shard")
			and not private_assignment_message.contains("credential_slot")
			and not private_assignment_message.contains("private validation trace"),
			"startup failure ignores internal messages without playerMessage",
		)
		var private_continue_message := host.call(
			"_startup_failure_message",
			internal_failure,
			"继续游戏失败",
		) as String
		_expect(
			private_continue_message == "继续游戏失败：请稍后重试",
			"continue failure uses stable copy for unknown internal errors",
		)
		_expect_equal(
			host.get("_resident_model_assignment_committing"),
			false,
			"startup failure releases the duplicate-submit guard for retry",
		)
		_expect_equal(host.get("_bootstrap"), null, "test stop prevents any bootstrap persistence")

		# Exercise the accepted-bootstrap transition boundary without inventing a
		# Provider success. The bootstrap contract hands Host a ready runtime; Host
		# must make it current before it releases the model-assignment owner.
		var accepted_runtime := StartupRuntimeHarness.new()
		accepted_runtime.name = "AcceptedTownRuntimeBoundary"
		host.set("_resident_model_assignment_committing", true)
		host.set("_pending_runtime", accepted_runtime)
		host.call("_enter_pending_town", host.get("_flow_generation"))
		_expect_equal(
			current_scene,
			accepted_runtime,
			"accepted bootstrap switches current_scene directly to Town runtime",
		)
		_expect(
			not is_instance_valid(page) or page.is_queued_for_deletion(),
			"assignment owner closes only after the Town runtime is current",
		)
		_expect_equal(
			host.get("_resident_model_assignment_service"),
			null,
			"accepted Town transition releases the assignment service",
		)
		await _wait_frames(3)
		current_scene = null
		if is_instance_valid(accepted_runtime):
			accepted_runtime.free()

	host.call("_reset_resident_model_assignment_session")
	if is_instance_valid(selection):
		selection.free()
	current_scene = null



func _wait_frames(count: int) -> void:
	for _index in count:
		await process_frame


func _find_button_with_text(root: Node, expected: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == expected:
			return button
	return null



func _dispatch_assignment(
	adapter: Node,
	intent: String,
	payload: Dictionary,
) -> Dictionary:
	var current := adapter.call(
		"get_view_model",
		"resident_model_assignment",
	) as Dictionary
	var routed_payload := payload.duplicate(true)
	routed_payload["revision"] = int(current.get("revision", -1))
	return adapter.call("dispatch", intent, routed_payload) as Dictionary



func _binding_for(draft: Dictionary, resident_id: String) -> Dictionary:
	for slot_value: Variant in draft.get("slots", []) as Array:
		if not slot_value is Dictionary:
			continue
		var slot := slot_value as Dictionary
		if String(slot.get("residentId", "")) == resident_id:
			return (slot.get("llmBinding", {}) as Dictionary).duplicate(true)
	return {}



func _binding_for_view_model(view_model: Dictionary, resident_id: String) -> Dictionary:
	for resident_value: Variant in (
		(view_model.get("data", {}) as Dictionary).get("residents", []) as Array
	):
		if not resident_value is Dictionary:
			continue
		var resident := resident_value as Dictionary
		if String(resident.get("residentId", "")) == resident_id:
			return (resident.get("llmBinding", {}) as Dictionary).duplicate(true)
	return {}



func _validate_resident_id_merge(
	host: Node,
	catalog: Array,
	confirmed_draft: Dictionary,
	replaced_resident_id: String,
) -> void:
	var current_ids: Array[String] = []
	for slot_value: Variant in confirmed_draft.get("slots", []) as Array:
		if slot_value is Dictionary:
			current_ids.append(String((slot_value as Dictionary).get("residentId", "")))
	var replacement_id := ""
	for catalog_value: Variant in catalog:
		if not catalog_value is Dictionary:
			continue
		var entry := catalog_value as Dictionary
		var candidate := String(entry.get("resident_id", entry.get("residentId", "")))
		if not candidate.is_empty() and not current_ids.has(candidate):
			replacement_id = candidate
			break
	_expect(not replacement_id.is_empty(), "16-resident catalog provides one replacement candidate")
	if replacement_id.is_empty():
		return
	var changed_draft := confirmed_draft.duplicate(true)
	var changed_slots := (changed_draft.get("slots", []) as Array).duplicate(true)
	var replacement_slot := (changed_slots[0] as Dictionary).duplicate(true)
	replacement_slot["residentId"] = replacement_id
	replacement_slot.erase("llmBinding")
	changed_slots[0] = replacement_slot
	changed_draft["slots"] = changed_slots
	var merged := host.call(
		"_merge_resident_model_assignment_draft",
		changed_draft,
	) as Dictionary
	_expect_equal(
		_binding_for(merged, replacement_id),
		{"mode": "model", "providerId": "", "modelId": ""},
		"a newly selected resident is explicitly invalidated to unassigned",
	)
	_expect(
		_binding_for(merged, replaced_resident_id).is_empty(),
		"a removed resident binding is not silently carried into another slot",
	)
	var merge_receipt := (
		(host.get("_last_result") as Dictionary).get("modelDraftMerge", {})
		as Dictionary
	)
	_expect_equal(merge_receipt.get("policy"), "resident_id", "roster changes use residentId merge policy")
	_expect(
		(merge_receipt.get("invalidatedResidentIds", []) as Array).has(
			replaced_resident_id,
		),
		"merge receipt reports the removed resident binding",
	)



func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(
		bool(result.get("ok", false)) and bool(result.get("accepted", false)),
		"%s (result=%s)" % [message, result],
	)



func _remove_custom_resident_library_test_file() -> void:
	if FileAccess.file_exists(CUSTOM_RESIDENT_LIBRARY_TEST_PATH):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(CUSTOM_RESIDENT_LIBRARY_TEST_PATH),
		)
	var backup_path := "%s.bak" % CUSTOM_RESIDENT_LIBRARY_TEST_PATH
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))


func _scenario_session_production_composition() -> void:
	# Camera coordinates are defined against the shipped 1920x1080 logical
	# viewport. Headless DisplayServer sizes vary by host and otherwise turn this
	# product assertion into an unrelated map-edge clamp assertion.
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	var world_data := _read_json_session_production_composition("res://world/data/town/town_world.json")
	_expect(
		not FileAccess.file_exists(
			"res://ui/resident_selection/mock/resident_selection_mock.json"
		),
		"internal playtest catalog does not depend on the retired UI mock",
	)
	var formal_selection_vm := RESIDENT_CATALOG.build_view_model(
		"fake",
		"fake",
		true,
		2,
	) as Dictionary
	var formal_selection_data := (
		formal_selection_vm.get("data", {}) as Dictionary
	)
	formal_selection_data["selected_resident_ids"] = (
		formal_selection_data.get("recommended_resident_ids", []) as Array
	).duplicate()
	RESIDENT_CATALOG.update_confirmation_payload(
		formal_selection_data,
		"fake",
		"fake",
		3,
	)
	var formal_draft := (
		formal_selection_data.get("confirmation_payload", {}) as Dictionary
	)
	var formal_catalog := RESIDENT_CATALOG.load_catalog()
	var formal_compiled := COMPILER.compile(
		formal_draft,
		world_data,
		formal_catalog,
	)
	_expect_ok_session_production_composition(
		formal_compiled,
		"formal Catalog to confirmation draft to Compiler chain succeeds",
	)
	_verify_custom_resident_pipeline(world_data, formal_catalog)
	var fallback_owner_catalog := formal_catalog.duplicate(true)
	(
		fallback_owner_catalog.get("shopOwnerCandidates", {}) as Dictionary
	)["工作坊"] = [
		"resident_shen_qiao_01",
		"resident_wen_xu_01",
	]
	var fallback_compiled := COMPILER.compile(
		formal_draft,
		world_data,
		fallback_owner_catalog,
	)
	_expect_ok_session_production_composition(
		fallback_compiled,
		"shop ownership falls back to the first selected formal candidate",
	)
	if bool(fallback_compiled.get("ok", false)):
		_expect_equal(
			(
				fallback_compiled.get("openingConfig", {}) as Dictionary
			).get("ownerAssignments", {}).get("工作坊"),
			"resident_shen_qiao_01",
			"fallback owner follows the authoritative candidate order",
		)
	var missing_owner_catalog := formal_catalog.duplicate(true)
	(
		missing_owner_catalog.get("shopOwnerCandidates", {}) as Dictionary
	)["工作坊"] = ["resident_cheng_yan_01"]
	_expect(
		_result_has_error_code(
			COMPILER.compile(formal_draft, world_data, missing_owner_catalog),
			"SESSION_CATALOG_PLACE_OWNER_MISSING",
		),
		"Compiler fails closed when no shop owner candidate was selected",
	)
	var bad_sprite_catalog := formal_catalog.duplicate(true)
	(
		(
			(bad_sprite_catalog.get("residents", []) as Array)[0]
			as Dictionary
		).get("presentation", {}) as Dictionary
	)["spritePath"] = "res://missing-resident-whitebody.png"
	_expect(
		_result_has_error_code(
			COMPILER.compile(formal_draft, world_data, bad_sprite_catalog),
			"SESSION_CATALOG_PORTRAIT_MISSING",
		),
		"Compiler rejects a formal catalog with a missing resident sprite",
	)
	var legacy_appearance_catalog := formal_catalog.duplicate(true)
	(
		(
			(legacy_appearance_catalog.get("residents", []) as Array)[0]
			as Dictionary
		).get("attributes", {}) as Dictionary
	)["appearance"] = "paper_doll_64:legacy"
	_expect(
		_result_has_error_code(
			COMPILER.compile(
				formal_draft,
				world_data,
				legacy_appearance_catalog,
			),
			"SESSION_CATALOG_APPEARANCE_INVALID",
		),
		"Compiler rejects an appearance outside the approved wardrobe catalog",
	)
	var selection_vm := INTERNAL_CATALOG.build_view_model("fake", "fake")
	var selection_data := selection_vm.get("data", {}) as Dictionary
	_expect_equal(selection_data.get("capabilityMode"), "development", "internal VM is visibly development")
	_expect_equal(selection_data.get("source"), "placeholder", "internal VM declares placeholder source")
	_expect_equal(selection_data.get("formalReady"), false, "internal VM never impersonates formal")
	_expect_equal(selection_data.get("internalPlaytest"), true, "internal VM requires explicit playtest flag")
	var draft := (selection_data.get("confirmation_payload", {}) as Dictionary).duplicate(true)
	_expect_equal((draft.get("slots", []) as Array).size(), 15, "internal draft has all 15 homes")
	for slot_value: Variant in draft.get("slots", []) as Array:
		var llm := (slot_value as Dictionary).get("llmBinding", {}) as Dictionary
		_expect_equal(llm.get("providerId"), "fake", "host owns development provider normalization")
		_expect_equal(llm.get("modelId"), "fake", "mock_provider never reaches Provider catalog")
	var catalog := INTERNAL_CATALOG.build_catalog(world_data, selection_vm)
	var compiled := COMPILER.compile(draft, world_data, catalog)
	_expect_ok_session_production_composition(compiled, "development placeholder compiles through the production compiler")
	if not bool(compiled.get("ok", false)):
		return
	var bindings := compiled.get("residentBindings", []) as Array[Dictionary]
	_expect_equal(bindings.size(), 15, "compiler produces the complete resident binding set")
	var boundary_world: RefCounted = WORLD.new()
	var identities: Array[Dictionary] = []
	for binding in bindings:
		identities.append({
			"residentId": String(binding.get("residentId", "")),
			"residentName": String(binding.get("residentName", "")),
		})
	var boundary_start := boundary_world.call(
		"start",
		world_data,
		compiled.get("openingConfig", {}) as Dictionary,
		identities,
	) as Dictionary
	_expect_ok_session_production_composition(boundary_start, "compiled opening starts a boundary World")
	for binding in bindings:
		var resident_id := String(binding.get("residentId", ""))
		var initialization := boundary_world.call("get_agent_initialization_by_id", resident_id) as Dictionary
		var contract_errors := AGENT_CONTRACT.validate_initialization(initialization)
		_expect(
			contract_errors.is_empty(),
			"World initialization satisfies AgentContract for %s: %s" % [resident_id, contract_errors],
		)
	boundary_world.call("stop")

	var request_host := Node.new()
	request_host.name = "ProductionProviderRequestHost"
	root.add_child(request_host)
	var provider_service: RefCounted = PROVIDER_SERVICE.new()
	_expect_ok_session_production_composition(provider_service.call("configure", {
		"capabilityMode": "development",
		"source": "placeholder",
		"allowFake": true,
		"providerConfigs": {},
	}, request_host), "provider service configures explicitly")

	var formal_gateway: Node = GATEWAY.new()
	var formal_runtime := Node.new()
	var formal_bootstrap: RefCounted = BOOTSTRAP.new()
	var formal_collector := ResultCollector.new()
	formal_bootstrap.call(
		"begin_new_game_from_catalog",
		draft,
		world_data,
		catalog,
		provider_service,
		formal_gateway,
		formal_runtime,
		{
			"worldStartMode": "formal",
			"internalPlaytest": false,
			"sessionId": "formal-preflight-session",
			"slotId": "formal-preflight-slot",
			"requestHost": request_host,
		},
		formal_collector.collect,
	)
	var formal_result := formal_collector.result
	_expect_equal(formal_result.get("ok"), false, "formal startup remains gated")
	_expect_equal(
		formal_result.get("errorCode"),
		"SESSION_RUNTIME_CONTRACT_MISSING",
		"formal startup accepts the arrival opening and stops at the intentionally incomplete runtime spy",
	)
	var unconfigured_bind := formal_gateway.call("bind_world", null) as Dictionary
	_expect_equal(
		unconfigured_bind.get("errorCode"),
		"AGENT_GATEWAY_SESSION_NOT_CONFIGURED",
		"formal World rejection has no Agent/Gateway side effect",
	)
	var agent_stage_failure := formal_gateway.call(
		"_agent_stage_failure",
		"AGENT_NEW_GAME_PREPARE_FAILED",
		"start_new_game",
		"",
		{"ok": false, "errors": ["Agent slot already exists"]},
	) as Dictionary
	_expect_equal(
		((((agent_stage_failure.get("errors", []) as Array)[0]) as Dictionary).get("agentErrors", []) as Array),
		["Agent slot already exists"],
		"Gateway preserves non-sensitive Agent stage errors for formal startup diagnosis",
	)
	formal_runtime.free()
	formal_gateway.free()

	var gateway: Node = GATEWAY.new()
	var runtime: Node = TOWN_RUNTIME_SCENE.instantiate()
	var bootstrap: RefCounted = BOOTSTRAP.new()
	var identity := str(Time.get_ticks_usec())
	var slot_id := "test-live-composition-slot-%s" % identity
	var session_id := "composition-session-%s" % identity
	var bootstrap_collector := ResultCollector.new()
	var accepted := bootstrap.call(
		"begin_new_game_from_catalog",
		draft,
		world_data,
		catalog,
		provider_service,
		gateway,
		runtime,
		{
			"worldStartMode": "development",
			"internalPlaytest": true,
			"sessionId": session_id,
			"slotId": slot_id,
			"requestHost": request_host,
			"useLiveModel": false,
			"enablePlayerAvatar": true,
		},
		bootstrap_collector.collect,
	) as Dictionary
	var bootstrap_result := bootstrap_collector.result
	_expect_equal(accepted.get("accepted"), true, "development bootstrap accepts the explicit request")
	_expect_ok_session_production_composition(bootstrap_result, "bootstrap produces a configured Town Runtime")
	if not bool(bootstrap_result.get("ok", false)):
		runtime.free()
		gateway.free()
		request_host.queue_free()
		return
	root.add_child(runtime)
	await process_frame
	await process_frame
	await process_frame
	var startup := runtime.call("get_startup_result") as Dictionary
	_expect_ok_session_production_composition(startup, "configured production Town Runtime starts")
	if not bool(startup.get("ok", false)):
		runtime.queue_free()
		await process_frame
		request_host.queue_free()
		return
	_verify_conversation_agent_dispatch_first_frame(runtime)
	_expect_equal(runtime.call("get_connected_agent_names").size(), 15, "one gateway connects all 15 residents")
	_expect_equal(gateway.call("get_connected_resident_ids").size(), 15, "gateway routes the stable ID set")
	var first_id := String((bindings[0] as Dictionary).get("residentId", ""))
	for _frame in 60:
		if not (gateway.call("get_last_submission", first_id) as Dictionary).is_empty():
			break
		await process_frame
	_expect(
		not (gateway.call("get_last_submission", first_id) as Dictionary).is_empty(),
		"initial World wake triggers a real Fake AgentSystem decision and World submission (metrics=%s debug=%s errors=%s)" % [
			gateway.call("get_request_metrics"),
			gateway.call("get_resident_debug_snapshot", first_id),
			gateway.call("get_errors"),
		],
	)
	_expect_equal((gateway.call("get_errors") as Array).size(), 0, "production Gateway has no hidden per-resident errors")
	_expect_equal(
		runtime.get_node_or_null("TownUi"),
		null,
		"formal runtime does not instantiate the legacy TownUi canvas or scene banner",
	)
	for legacy_node_name: String in [
		"PlayerUi",
		"CameraControls",
		"MapControlPanel",
		"CafeFurnitureEditEntryPanel",
		"CafeFurnitureEditorPanel",
	]:
		_expect(
			runtime.find_child(legacy_node_name, true, false) == null,
			"formal runtime never mounts legacy test control %s" % legacy_node_name,
		)
	var state_before_test_keys := runtime.call("get_runtime_state") as Dictionary
	_expect_equal(state_before_test_keys.get("testUiEnabled"), false, "formal runtime keeps test UI disabled")
	_expect_equal(state_before_test_keys.get("avatarMode"), "observer", "Town always opens in observer mode")
	_expect_equal(state_before_test_keys.get("playerAvatarEnabled"), false, "Town load never auto-descends into avatar control")
	_expect_equal(state_before_test_keys.get("viewMode"), "town", "observer starts on the outdoor Town map")
	_expect_equal(state_before_test_keys.get("activeInteriorId"), "", "observer does not inherit a resident interior")
	_expect_equal(state_before_test_keys.get("followedResident"), "", "observer does not auto-follow the first connected resident")
	_expect_equal(
		state_before_test_keys.get("observerCameraPosition"),
		Vector2(3250, 2050),
		"observer starts from the stable central plaza camera point",
	)
	_expect_equal(state_before_test_keys.get("cameraZoomIndex"), 1, "observer starts at a pannable outdoor zoom")
	_expect_equal(state_before_test_keys.get("cameraZoomBand"), "far", "observer start drives the far HUD density band")
	_expect_equal(state_before_test_keys.get("cameraZoomRatio"), 0.5, "observer start publishes the real 0.5x camera ratio")
	_expect_equal(state_before_test_keys.get("cameraZoomStepCount"), 4, "observer camera publishes all four discrete zoom steps")
	var observer_text_input := LineEdit.new()
	observer_text_input.name = "ObserverMovementInputFocusProbe"
	runtime.add_child(observer_text_input)
	observer_text_input.grab_focus()
	await process_frame
	var observer_position_before_typing := (
		(runtime.call("get_runtime_state") as Dictionary).get(
			"observerCameraPosition",
			Vector2.ZERO,
		) as Vector2
	)
	_send_physical_key(&"move_down", KEY_S, true)
	await physics_frame
	await physics_frame
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("observerCameraPosition"),
		observer_position_before_typing,
		"typing a movement key never pans the observer camera behind a text input",
	)
	observer_text_input.release_focus()
	await process_frame
	await physics_frame
	_expect(
		not Input.is_action_pressed("move_down"),
		"closing observer text input clears its stale movement action",
	)
	_send_physical_key(&"move_down", KEY_S, false)
	observer_text_input.queue_free()
	_send_physical_key(&"move_right", KEY_D, true)
	await physics_frame
	await physics_frame
	_send_physical_key(&"move_right", KEY_D, false)
	var state_after_observer_pan := runtime.call("get_runtime_state") as Dictionary
	_expect(
		(state_after_observer_pan.get("observerCameraPosition", Vector2.ZERO) as Vector2).x > 3250.0,
		"observer WASD input pans the camera without activating the avatar",
	)
	var blocked_camera_position := (
		state_after_observer_pan.get("observerCameraPosition", Vector2.ZERO) as Vector2
	)
	var camera_input_blocked := runtime.call(
		"set_observer_camera_input_enabled",
		false,
	) as Dictionary
	_expect_equal(camera_input_blocked.get("ok"), true, "formal host can block observer camera input")
	_expect_equal(camera_input_blocked.get("enabled"), false, "observer camera input reports blocked")
	Input.action_press("move_right")
	await physics_frame
	await physics_frame
	Input.action_release("move_right")
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("observerCameraPosition"),
		blocked_camera_position,
		"blocked observer camera ignores held WASD behind a formal page",
	)
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	runtime.call("_unhandled_input", wheel_up)
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("cameraZoomIndex"),
		1,
		"blocked observer camera ignores wheel zoom behind a formal page",
	)
	var camera_input_restored := runtime.call(
		"set_observer_camera_input_enabled",
		true,
	) as Dictionary
	_expect_equal(camera_input_restored.get("enabled"), true, "formal host restores observer camera input")
	runtime.call("_unhandled_input", wheel_up)
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("cameraZoomIndex"),
		2,
		"observer mouse wheel changes the outdoor camera zoom",
	)
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("cameraZoomBand"),
		"middle",
		"1x observer zoom drives the middle HUD density band",
	)
	var adapter: Node = runtime.call("get_ui_adapter")
	_expect(adapter != null, "Town Runtime exposes its unique Adapter")
	var audio_display_service: Node = AUDIO_DISPLAY_SETTINGS_SERVICE_SCRIPT.new()
	audio_display_service.name = "TownAudioDisplaySettingsService"
	runtime.add_child(audio_display_service)
	var audio_display_binding := adapter.call(
		"bind_audio_display_settings_service",
		audio_display_service,
	) as Dictionary
	_expect(
		bool(audio_display_binding.get("ok", false)),
		"formal runtime binds the audio/display settings service",
	)
	await process_frame
	var world_runtime: RefCounted = runtime.call("get_world_runtime")
	var editor_pause_time := world_runtime.call("get_time") as Dictionary
	var editor_pause := adapter.call(
		"dispatch",
		"lifecycle.pause",
		{"reason": "resident_editor"},
	) as Dictionary
	_expect_ok_session_production_composition(editor_pause, "resident editor pauses through the formal Adapter")
	world_runtime.call("advance", 3.0)
	_expect_equal(
		world_runtime.call("get_time"),
		editor_pause_time,
		"resident editor keeps formal World time stopped",
	)
	var editor_resume := adapter.call(
		"dispatch",
		"lifecycle.resume",
		{"reason": "resident_editor"},
	) as Dictionary
	_expect_ok_session_production_composition(editor_resume, "resident editor resumes through the formal Adapter")
	world_runtime.call("advance", 1.0)
	_expect(
		world_runtime.call("get_time") != editor_pause_time,
		"formal World time advances after leaving resident editor",
	)
	var speed_three := adapter.call(
		"dispatch",
		"town_hud.set_time_speed",
		{"multiplier": 3},
	) as Dictionary
	_expect_ok_session_production_composition(
		speed_three,
		"formal time controls select 3x speed",
	)
	var manual_pause := adapter.call(
		"dispatch",
		"lifecycle.pause",
		{"reason": "manual"},
	) as Dictionary
	_expect_ok_session_production_composition(
		manual_pause,
		"formal time controls pause manually",
	)
	var manual_pause_time := world_runtime.call("get_time") as Dictionary
	world_runtime.call("advance", 2.0)
	_expect_equal(
		world_runtime.call("get_time"),
		manual_pause_time,
		"manual pause keeps formal World time stopped",
	)
	var normal_speed := adapter.call(
		"dispatch",
		"town_hud.set_time_speed",
		{"multiplier": 1},
	) as Dictionary
	_expect_ok_session_production_composition(
		normal_speed,
		"selecting 1x clears manual pause",
	)
	_expect_equal(
		world_runtime.call("get_simulation_speed"),
		1,
		"selecting 1x restores normal simulation speed",
	)
	_expect(
		not bool(
			(world_runtime.call("get_lifecycle_state") as Dictionary).get(
				"paused",
				true,
			)
		),
		"selecting 1x leaves the formal World running",
	)
	world_runtime.call("advance", 1.0)
	_expect(
		world_runtime.call("get_time") != manual_pause_time,
		"formal World time advances after selecting 1x",
	)
	_expect_equal(
		(runtime.call("set_manual_paused", true) as Dictionary).get("ok"),
		true,
		"manual pause can coexist with the pause menu",
	)
	_expect_equal(
		(runtime.call("set_main_menu_open", true) as Dictionary).get("ok"),
		true,
		"pause menu adds only its own pause reason",
	)
	_expect_equal(
		(runtime.call("set_main_menu_open", false) as Dictionary).get("ok"),
		true,
		"closing pause menu clears only the menu pause reason",
	)
	var pause_after_menu_close := runtime.call("get_lifecycle_state") as Dictionary
	_expect(
		bool(pause_after_menu_close.get("paused", false))
		and (pause_after_menu_close.get("pauseReasons", []) as Array).has("manual"),
		"closing pause menu preserves an earlier manual pause",
	)
	var resume_after_menu_close := adapter.call(
		"dispatch",
		"town_hud.set_time_speed",
		{"multiplier": 1},
	) as Dictionary
	_expect_ok_session_production_composition(
		resume_after_menu_close,
		"selecting a speed resumes the preserved manual pause",
	)
	_expect(
		not bool(
			(runtime.call("get_lifecycle_state") as Dictionary).get(
				"paused",
				true,
			)
		),
		"pause-menu and manual-pause sequence returns to running",
	)
	_expect_equal(
		(runtime.call("set_manual_paused", true) as Dictionary).get("ok"),
		true,
		"manual pause can coexist with an application background pause",
	)
	_expect_equal(
		(runtime.call("set_background_paused", true) as Dictionary).get("ok"),
		true,
		"background pause adds only its own pause reason",
	)
	var speed_while_background_paused := adapter.call(
		"dispatch",
		"town_hud.set_time_speed",
		{"multiplier": 2},
	) as Dictionary
	_expect_ok_session_production_composition(
		speed_while_background_paused,
		"speed selection clears manual pause while backgrounded",
	)
	var background_only_pause := runtime.call("get_lifecycle_state") as Dictionary
	_expect(
		bool(background_only_pause.get("paused", false))
		and not (background_only_pause.get("pauseReasons", []) as Array).has("manual")
		and (background_only_pause.get("pauseReasons", []) as Array).has("background"),
		"speed selection never clears the application-owned background pause",
	)
	_expect_equal(
		(runtime.call("set_background_paused", false) as Dictionary).get("ok"),
		true,
		"foregrounding clears the final background pause reason",
	)
	_expect(
		not bool(
			(runtime.call("get_lifecycle_state") as Dictionary).get(
				"paused",
				true,
			)
		),
		"manual and background pause sequence returns to running",
	)
	var observer_hud := adapter.call("get_view_model", "town_hud") as Dictionary
	await _capture_resident_directory_if_requested(runtime, adapter, observer_hud)
	var observer_actions := observer_hud.get("actions", {}) as Dictionary
	for action_key: String in ["cameraZoomIn", "cameraZoomOut", "cameraReset"]:
		_expect(
			bool((observer_actions.get(action_key, {}) as Dictionary).get("enabled", false)),
			"formal observer HUD enables %s" % action_key,
		)
	var hud_zoom_out := adapter.call(
		"dispatch",
		"town_hud.camera_zoom_out",
		{},
	) as Dictionary
	_expect_equal(hud_zoom_out.get("ok"), true, "observer HUD zoom reaches TownRuntime")
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("cameraZoomIndex"),
		1,
		"observer HUD zoom changes the same formal camera state",
	)
	var hud_reset := adapter.call("dispatch", "town_hud.camera_reset", {}) as Dictionary
	_expect_equal(hud_reset.get("ok"), true, "observer HUD reset reaches TownRuntime")
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("observerCameraPosition"),
		Vector2(3250, 2050),
		"observer HUD reset restores the stable outdoor camera point",
	)
	var drag_start := (
		(runtime.call("get_runtime_state") as Dictionary).get(
			"observerCameraPosition",
			Vector2.ZERO,
		) as Vector2
	)
	var drag_press := InputEventMouseButton.new()
	drag_press.button_index = MOUSE_BUTTON_MIDDLE
	drag_press.pressed = true
	runtime.call("_unhandled_input", drag_press)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.relative = Vector2(-120.0, 80.0)
	runtime.call("_unhandled_input", drag_motion)
	var drag_release := InputEventMouseButton.new()
	drag_release.button_index = MOUSE_BUTTON_MIDDLE
	drag_release.pressed = false
	runtime.call("_unhandled_input", drag_release)
	_expect(
		(runtime.call("get_runtime_state") as Dictionary).get(
			"observerCameraPosition",
			Vector2.ZERO,
		) != drag_start,
		"observer middle-button drag pans the same formal camera",
	)
	runtime.call("reset_observer_camera")
	var pause_result := runtime.call("set_main_menu_open", true) as Dictionary
	_expect_equal(pause_result.get("ok"), true, "Pause reason is accepted by the formal World")
	var paused_camera_state := runtime.call("get_runtime_state") as Dictionary
	var paused_camera_position := paused_camera_state.get(
		"observerCameraPosition",
		Vector2.ZERO,
	) as Vector2
	var paused_zoom_index := int(paused_camera_state.get("cameraZoomIndex", -1))
	runtime.call("_unhandled_input", drag_press)
	runtime.call("_unhandled_input", drag_motion)
	runtime.call("_unhandled_input", wheel_up)
	runtime.call("_unhandled_input", drag_release)
	var camera_after_paused_mouse := runtime.call("get_runtime_state") as Dictionary
	_expect_equal(
		camera_after_paused_mouse.get("observerCameraPosition"),
		paused_camera_position,
		"Pause blocks observer drag even if the Host input flag has not changed yet",
	)
	_expect_equal(
		camera_after_paused_mouse.get("cameraZoomIndex"),
		paused_zoom_index + 1,
		"Pause keeps observer wheel zoom available without advancing World time",
	)
	var paused_magnify := InputEventMagnifyGesture.new()
	paused_magnify.factor = 1.25
	runtime.call("_unhandled_input", paused_magnify)
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("cameraZoomIndex"),
		paused_zoom_index + 2,
		"Pause keeps trackpad pinch zoom available without advancing World time",
	)
	_expect_equal(
		(runtime.call("set_main_menu_open", false) as Dictionary).get("ok"),
		true,
		"closing Pause resumes the formal World",
	)
	for logical_viewport: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.content_scale_size = logical_viewport
		root.size = logical_viewport
		await process_frame
		runtime.call("_reset_observer_camera", true)
		_expect_equal(
			(runtime.call("get_runtime_state") as Dictionary).get(
				"observerCameraPosition"
			),
			Vector2(3250, 2050),
			"%dx%d logical viewport preserves the central-plaza observer reset"
				% [logical_viewport.x, logical_viewport.y],
		)
		runtime.call("_set_observer_camera_position", Vector2.ZERO, true)
		_expect_equal(
			(runtime.call("get_runtime_state") as Dictionary).get(
				"observerCameraPosition"
			),
			Vector2(logical_viewport) / 0.5 * 0.5,
			"%dx%d logical viewport clamps against its own visible half extents"
				% [logical_viewport.x, logical_viewport.y],
		)
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	await process_frame
	runtime.call("_reset_observer_camera", true)
	var player_sprite := runtime.get_node("Player/PaperDoll64Visual/CharacterSprite") as Sprite2D
	_expect_equal(
		player_sprite.texture.resource_path,
		"res://assets/characters/player_avatar_white/player_avatar_white_walk_64.png",
		"formal Town consumes the delivered player avatar atlas",
	)
	_expect_equal(player_sprite.hframes, 4, "formal avatar atlas has four action columns")
	_expect_equal(player_sprite.vframes, 4, "formal avatar atlas has four direction rows")
	_expect_equal(player_sprite.position, Vector2(-32.0, -72.0), "formal avatar keeps the delivered root anchor")
	_expect_equal(
		player_sprite.get_parent().scale,
		Vector2.ONE * 1.65,
		"formal avatar keeps the town-door resident display size",
	)
	var avatar_hud := AVATAR_HUD_SCENE_SESSION_PRODUCTION_COMPOSITION.instantiate() as Control
	runtime.add_child(avatar_hud)
	var avatar_issues := avatar_hud.call("bind_town_ui_adapter", adapter) as PackedStringArray
	_expect_equal(
		avatar_issues,
		PackedStringArray(),
		"approved AvatarModeHud binds without a parallel ViewModel",
	)
	runtime.call(
		"_set_observer_camera_position",
		Vector2(3260, 2050),
		true,
	)
	var descent := adapter.call("dispatch", "town_hud.select_tool", {"toolId": "avatar"}) as Dictionary
	_expect_equal(descent.get("ok"), true, "observer HUD explicitly starts avatar descent")
	_expect_equal(runtime.call("get_avatar_mode"), "avatar_descent", "descent is a distinct locked runtime state")
	var landing_state := (runtime.call("get_runtime_state") as Dictionary).get("playerAvatar", {}) as Dictionary
	_expect_equal(landing_state.get("spaceId"), "town_outdoor", "avatar descent is prepared on the outdoor map")
	_expect_equal(landing_state.get("currentPlace"), "中心广场", "avatar descent derives the current view-center membership")
	_expect(
		(
			landing_state.get("position", Vector2.INF) as Vector2
		).distance_to(Vector2(3260, 2050)) < 16.0,
		"avatar descent follows the live view center and uses its nearest safe point",
	)
	_expect_equal((runtime.call("get_avatar_descent_snapshot") as Dictionary).get("inputLocked"), true, "descent locks player input")
	var descent_player_position := (runtime.get_node("Player") as Node2D).position
	var descent_camera_state := runtime.call("get_runtime_state") as Dictionary
	Input.action_press("move_right")
	await physics_frame
	await physics_frame
	Input.action_release("move_right")
	runtime.call("_unhandled_input", wheel_up)
	_expect_equal(
		(runtime.get_node("Player") as Node2D).position,
		descent_player_position,
		"avatar descent ignores movement input until the unlock edge",
	)
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("cameraZoomIndex"),
		descent_camera_state.get("cameraZoomIndex"),
		"avatar descent ignores observer wheel input",
	)
	await create_timer(0.35).timeout
	var beam_snapshot := runtime.call("get_avatar_descent_snapshot") as Dictionary
	_expect_equal(beam_snapshot.get("cueEmitted"), true, "300ms beam edge emits the delivered descent cue once")
	await create_timer(0.8).timeout
	_expect_equal(runtime.call("get_avatar_mode"), "avatar_active", "old 1100ms input edge activates avatar")
	var active_building_hotspots := (
		runtime.get("_building_observation_hotspots") as Dictionary
	)
	_expect(
		not active_building_hotspots.is_empty(),
		"avatar runtime keeps the formal building hotspot set available for gating",
	)
	for hotspot_value: Variant in active_building_hotspots.values():
		var hotspot := hotspot_value as Area2D
		_expect(
			hotspot != null and not bool(hotspot.call("is_available")),
			"avatar mode disables building entry hotspots",
		)
	var active_player_body := runtime.get_node("Player") as CharacterBody2D
	_expect_equal(
		active_player_body.collision_mask,
		13,
		"active avatar collides with the map, residents and ground animals",
	)
	_expect_equal(
		(
			runtime.call(
				"get_avatar_descent_snapshot",
			) as Dictionary
		).get("unlockEmitted"),
		true,
		"descent emits its input-unlock edge even if a slow headless frame also finishes the visual tail",
	)
	await create_timer(0.35).timeout
	_expect_equal((runtime.call("get_avatar_descent_snapshot") as Dictionary).get("active"), false, "old 1450ms edge completes all descent effects")
	var active_player_position := (runtime.get_node("Player") as Node2D).position
	Input.action_press("move_right")
	await physics_frame
	await physics_frame
	Input.action_release("move_right")
	_expect(
		(runtime.get_node("Player") as Node2D).position.x > active_player_position.x,
		"avatar active opens player movement only after descent unlock",
	)
	var text_input := LineEdit.new()
	text_input.name = "MovementInputFocusProbe"
	runtime.add_child(text_input)
	text_input.grab_focus()
	await process_frame
	var position_before_text_input := (runtime.get_node("Player") as Node2D).position
	_send_physical_key(&"move_down", KEY_S, true)
	await physics_frame
	await physics_frame
	_expect_equal(
		(runtime.get_node("Player") as Node2D).position,
		position_before_text_input,
		"typing a movement key never moves the avatar behind a text input",
	)
	text_input.release_focus()
	await process_frame
	await physics_frame
	_expect_equal(
		(runtime.get_node("Player") as Node2D).position,
		position_before_text_input,
		"closing text input clears a swallowed movement key instead of moving forever",
	)
	_expect(
		not Input.is_action_pressed("move_down"),
		"text-input handoff releases the stale down action",
	)
	_send_physical_key(&"move_down", KEY_S, false)
	_send_physical_key(&"move_right", KEY_D, true)
	await physics_frame
	await physics_frame
	_send_physical_key(&"move_right", KEY_D, false)
	_expect(
		(runtime.get_node("Player") as Node2D).position.x > position_before_text_input.x,
		"fresh movement input works after text input closes",
	)
	text_input.queue_free()
	var avatar_player := runtime.get_node("Player") as Node2D
	avatar_player.position = Vector2(4225.0, 1120.0)
	avatar_player.force_update_transform()
	runtime.call("_check_interior_auto_portals")
	await _wait_avatar_place_transition(runtime)
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("viewMode"),
		"interior",
		"avatar enters from the visible clinic doorway",
	)
	_expect_equal(
		runtime.call("get_avatar_mode"),
		"avatar_active",
		"physical indoor entry preserves avatar mode",
	)
	_expect(
		avatar_hud.visible,
		"AvatarModeHud stays visible after physical indoor entry",
	)
	runtime.call("_exit_interior", avatar_player, "clinic")
	await _wait_avatar_place_transition(runtime)
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("viewMode"),
		"town",
		"avatar physically returns to the outdoor town",
	)
	_expect_equal(
		runtime.call("get_avatar_mode"),
		"avatar_active",
		"physical outdoor return preserves avatar mode until the player exits it",
	)
	_expect(
		avatar_hud.visible,
		"AvatarModeHud returns after the indoor-to-outdoor transition",
	)
	runtime.call("_check_interior_auto_portals")
	await process_frame
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("viewMode"),
		"town",
		"the exit doorway does not immediately pull the avatar back indoors",
	)
	avatar_player.position = Vector2(4225.0, 1260.0)
	avatar_player.force_update_transform()
	runtime.call("_check_interior_auto_portals")
	avatar_player.position = Vector2(4225.0, 1120.0)
	avatar_player.force_update_transform()
	runtime.call("_check_interior_auto_portals")
	await _wait_avatar_place_transition(runtime)
	_expect_equal(
		(runtime.call("get_runtime_state") as Dictionary).get("viewMode"),
		"interior",
		"leaving the doorway re-enables a later physical entry",
	)
	runtime.call("_exit_interior", avatar_player, "clinic")
	await _wait_avatar_place_transition(runtime)
	_expect(
		bool(avatar_hud.call("debug_activate_action", "exitMode")),
		"returned AvatarModeHud keeps the return-to-observer action enabled",
	)
	await _wait_frames(2)
	_expect_equal(
		runtime.call("get_avatar_mode"),
		"observer",
		"indoor roundtrip can still return to observer mode",
	)
	var observer_building_hotspots := (
		runtime.get("_building_observation_hotspots") as Dictionary
	)
	for hotspot_value: Variant in observer_building_hotspots.values():
		var hotspot := hotspot_value as Area2D
		_expect(
			hotspot != null and bool(hotspot.call("is_available")),
			"observer mode restores building entry hotspots",
		)
	state_before_test_keys = runtime.call("get_runtime_state") as Dictionary
	var player_position_before_test_keys := (runtime.get_node("Player") as Node2D).position
	for keycode: Key in [KEY_P, KEY_C, KEY_T, KEY_J]:
		var key_event := InputEventKey.new()
		key_event.keycode = keycode
		key_event.pressed = true
		runtime.call("_unhandled_input", key_event)
	var state_after_test_keys := runtime.call("get_runtime_state") as Dictionary
	_expect_equal(
		state_after_test_keys.get("weather"),
		state_before_test_keys.get("weather"),
		"formal runtime ignores the C weather test shortcut",
	)
	_expect_equal(
		state_after_test_keys.get("time"),
		state_before_test_keys.get("time"),
		"formal runtime ignores the T time test shortcut",
	)
	_expect_equal(
		state_after_test_keys.get("lifecycle"),
		state_before_test_keys.get("lifecycle"),
		"formal runtime ignores the P manual-pause test shortcut",
	)
	_expect_equal(
		(runtime.get_node("Player") as Node2D).position,
		player_position_before_test_keys,
		"formal runtime ignores the J house-teleport test shortcut",
	)
	var avatar_vm := adapter.call("get_view_model", "avatar") as Dictionary
	_expect_equal(avatar_vm.get("scope"), "avatar", "AvatarModeHud receives the canonical avatar scope")
	var pause_vm := adapter.call("get_view_model", "pause_menu") as Dictionary
	_expect_equal(pause_vm.get("scope"), "pause_menu", "pause host uses the same canonical Adapter")
	_expect_equal(pause_vm.get("data", {}).get("internalPlaytest", null), null, "pause scope does not invent a second session draft")
	var save_vm := adapter.call("get_view_model", "save") as Dictionary
	_expect_equal(save_vm.get("status"), "disabled", "save stays disabled for tomorrow playtest")
	_expect_equal(
		save_vm.get("error", {}).get("code"),
		"SESSION_SAVE_SERVICE_NOT_BOUND",
		"save stays unavailable until the formal session save service is bound",
	)
	var pause_host := PAUSE_HOST_SCENE.instantiate() as Control
	runtime.add_child(pause_host)
	pause_host.call("bind_town_ui_adapter", adapter)
	await process_frame
	_expect_equal(
		bool((pause_host.call("debug_snapshot") as Dictionary).get("adapterBound", false)),
		true,
		"PauseMenuNavigationHost binds the same Adapter",
	)
	pause_host.call(
		"_on_pause_intent_requested",
		&"pause_menu.open_audio_video",
		{},
	)
	pause_host.call(
		"_on_pause_intent_requested",
		&"pause_menu.open_audio_video",
		{},
	)
	var pause_open_queued := pause_host.call("debug_snapshot") as Dictionary
	_expect_equal(
		pause_open_queued.get("route"),
		"pause_menu",
		"audio/display settings preserves the rendered pause route for the click frame",
	)
	_expect_equal(
		pause_open_queued.get("pauseVisible"),
		true,
		"audio/display settings keeps the pause page visible while its route is pending",
	)
	_expect_equal(
		pause_open_queued.get("settingsOpenPending"),
		true,
		"the first audio/display click owns the pending route transition",
	)
	await process_frame
	var pause_settings_opened := pause_host.call("debug_snapshot") as Dictionary
	_expect_equal(
		pause_settings_opened.get("route"),
		"audio_display_settings",
		"audio/display settings opens after the stable pause frame",
	)
	_expect_equal(
		pause_settings_opened.get("settingsInstanceCount"),
		1,
		"repeated audio/display clicks create only one settings page",
	)
	_expect_equal(
		pause_settings_opened.get("pauseVisible"),
		false,
		"the pause page hides only after settings is mounted",
	)
	_expect_equal(
		pause_host.call("close_audio_display_settings"),
		true,
		"audio/display settings returns to pause after the deferred transition",
	)
	await process_frame
	var failed_descent_camera := runtime.get_node("PlayerCamera") as Camera2D
	failed_descent_camera.zoom = Vector2.ONE * 1_000_000.0
	var failed_descent := adapter.call(
		"dispatch",
		"town_hud.select_tool",
		{"toolId": "avatar"},
	) as Dictionary
	_expect_equal(
		failed_descent.get("ok"),
		true,
		"avatar entry remains accepted when the optional descent presentation cannot start",
	)
	_expect_equal(
		runtime.call("get_avatar_mode"),
		"avatar_descent",
		"failed presentation keeps the transition locked until the deferred recovery turn",
	)
	_expect_equal(
		(runtime.call("get_avatar_descent_snapshot") as Dictionary).get("active"),
		false,
		"invalid camera transform makes the real descent presentation reject start",
	)
	var repeated_failed_descent := adapter.call(
		"dispatch",
		"town_hud.select_tool",
		{"toolId": "avatar"},
	) as Dictionary
	_expect_equal(
		repeated_failed_descent.get("errorCode"),
		"AVATAR_MODE_TRANSITION_IN_PROGRESS",
		"a repeated click cannot start or reverse the failed descent recovery",
	)
	await process_frame
	var recovered_avatar_state := runtime.call("get_runtime_state") as Dictionary
	var recovered_player := runtime.get_node("Player") as CharacterBody2D
	var recovered_feet := recovered_player.get_node("FeetCollision") as CollisionShape2D
	_expect_equal(
		runtime.call("get_avatar_mode"),
		"avatar_active",
		"failed descent presentation completes avatar entry on the next idle turn",
	)
	_expect_equal(
		recovered_avatar_state.get("playerAvatarEnabled"),
		true,
		"failed presentation recovery enables avatar control",
	)
	_expect_equal(recovered_player.collision_layer, 2, "failed presentation recovery restores the avatar collision layer")
	_expect_equal(recovered_player.collision_mask, 13, "failed presentation recovery restores the avatar collision mask")
	_expect_equal(recovered_feet.disabled, false, "failed presentation recovery restores feet collision")
	_expect_equal(failed_descent_camera.zoom, Vector2.ONE, "failed presentation recovery restores gameplay camera zoom")

	var agent_participant: RefCounted = gateway.call("get_agent_save_participant")
	var context := gateway.call("get_agent_save_context") as Dictionary
	runtime.queue_free()
	await process_frame
	if agent_participant != null and not context.is_empty():
		var deleted := agent_participant.call("delete_game", context) as Dictionary
		_expect_ok_session_production_composition(deleted, "composition smoke removes its complete Agent slot")
	request_host.queue_free()
	return
func _capture_resident_directory_if_requested(
	runtime: Node,
	adapter: Node,
	view_model: Dictionary,
) -> void:
	var output_dir := OS.get_environment(
		"AI_TOWN_HUD_RESIDENT_DIRECTORY_CAPTURE_DIR"
	).strip_edges()
	if output_dir.is_empty():
		return
	var directory := (
		(view_model.get("data", {}) as Dictionary)
		.get("residentDirectory", {}) as Dictionary
	)
	_expect_equal(directory.get("totalCount"), 15, "resident directory capture uses all 15 runtime residents")
	var overlay := runtime.find_child("TownHudOverlay", true, false) as TownHudOverlay
	var capture_layer: CanvasLayer
	if overlay == null:
		capture_layer = CanvasLayer.new()
		capture_layer.name = &"ResidentDirectoryCaptureLayer"
		runtime.add_child(capture_layer)
		overlay = TOWN_HUD_SCENE.instantiate() as TownHudOverlay
		capture_layer.add_child(overlay)
		await _wait_frames(3)
	_expect(overlay != null, "resident directory capture mounts the formal Town HUD wrapper")
	if not overlay.intent_requested.is_connected(adapter.dispatch):
		overlay.intent_requested.connect(
			func(intent: StringName, payload: Dictionary) -> void:
				adapter.call("dispatch", String(intent), payload.duplicate(true))
		)
	overlay.require_formal_ready = false
	_expect(overlay.apply_view_model(view_model), "resident directory capture applies the live runtime VM")
	await _wait_frames(3)
	var nav_button := (overlay.get("_buttons") as Dictionary).get("nav_residents") as Button
	_expect(nav_button != null and not nav_button.disabled, "resident directory runtime entry is enabled")
	if nav_button == null or nav_button.disabled:
		return
	nav_button.pressed.emit()
	await _wait_frames(3)
	var drawer := overlay.get("_resident_directory") as ResidentDirectoryDrawer
	_expect(drawer != null and drawer.visible, "resident directory drawer opens in the real Town")
	if drawer == null or not drawer.visible:
		return
	var items := directory.get("items", []) as Array
	DirAccess.make_dir_recursive_absolute(output_dir)
	for viewport in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		DisplayServer.window_set_size(viewport)
		root.size = viewport
		await _wait_frames(5)
		RenderingServer.force_draw(false)
		var image := root.get_texture().get_image()
		var path := output_dir.path_join(
			"observer_hud_resident_directory_runtime_%dx%d.png" % [viewport.x, viewport.y]
		)
		_expect(image != null and not image.is_empty(), "resident directory runtime image is readable")
		if image != null and not image.is_empty():
			if image.get_size() != viewport:
				image.resize(viewport.x, viewport.y, Image.INTERPOLATE_NEAREST)
			_expect_equal(image.save_png(path), OK, "resident directory runtime image is saved")
	if items.size() > 1:
		var camera_follow_action := (
			(view_model.get("actions", {}) as Dictionary).get("cameraFollow", {}) as Dictionary
		)
		_expect(
			bool(camera_follow_action.get("enabled", false)),
			"resident directory live camera-follow action is enabled: %s" % camera_follow_action,
		)
		drawer.call("_on_row_pressed", 1)
		await _wait_frames(3)
		var expected_name := String((items[1] as Dictionary).get("residentName", ""))
		_expect_equal(
			(runtime.call("get_runtime_state") as Dictionary).get("followedResident"),
			expected_name,
			"resident directory row dispatches the real camera follow",
		)
		runtime.call("cancel_resident_follow")
		await create_timer(0.6).timeout
		if String((runtime.call("get_runtime_state") as Dictionary).get("viewMode", "")) != "town":
			var returned: Variant = await runtime.call("return_to_town_overview")
			_expect(bool(returned), "resident directory capture restores the outdoor overview")
		await create_timer(0.4).timeout
		_expect_equal(
			(runtime.call("get_runtime_state") as Dictionary).get("viewMode"),
			"town",
			"resident directory capture leaves the observer outdoors",
		)
	var place_nav_button := (
		(overlay.get("_buttons") as Dictionary).get("nav_places") as Button
	)
	_expect(
		place_nav_button != null and not place_nav_button.disabled,
		"place directory runtime entry is enabled",
	)
	if place_nav_button != null and not place_nav_button.disabled:
		place_nav_button.pressed.emit()
		await _wait_frames(3)
		var place_drawer := overlay.get("_place_directory") as PlaceDirectoryDrawer
		_expect(
			place_drawer != null and place_drawer.visible and not drawer.visible,
			"place directory opens and closes resident directory",
		)
		if place_drawer != null and place_drawer.visible:
			for viewport in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
				DisplayServer.window_set_size(viewport)
				root.size = viewport
				await _wait_frames(5)
				RenderingServer.force_draw(false)
				var image := root.get_texture().get_image()
				var path := output_dir.path_join(
					"observer_hud_place_directory_runtime_%dx%d.png"
					% [viewport.x, viewport.y]
				)
				_expect(image != null and not image.is_empty(), "place directory runtime image is readable")
				if image != null and not image.is_empty():
					if image.get_size() != viewport:
						image.resize(viewport.x, viewport.y, Image.INTERPOLATE_NEAREST)
					_expect_equal(image.save_png(path), OK, "place directory runtime image is saved")
			place_drawer.close()
	else:
		drawer.close()
	if capture_layer != null:
		capture_layer.queue_free()
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	await _wait_frames(3)



func _wait_avatar_place_transition(runtime: Node) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while (
		(
			bool(runtime.get("_avatar_place_change_active"))
			or bool(runtime.get("_portal_transition_active"))
		)
		and Time.get_ticks_msec() < deadline
	):
		await process_frame
	_expect(
		not bool(runtime.get("_avatar_place_change_active"))
		and not bool(runtime.get("_portal_transition_active")),
		"avatar physical place transition completes",
	)



func _verify_custom_resident_pipeline(
	world_data: Dictionary,
	base_catalog: Dictionary,
) -> void:
	var pool: RefCounted = CUSTOM_POOL.new()
	_expect_ok_session_production_composition(
		pool.call("configure", base_catalog) as Dictionary,
		"custom candidate pool accepts the strict 16-resident base catalog",
	)
	var creator: RefCounted = CUSTOM_CREATOR.new()
	_expect_ok_session_production_composition(
		creator.call(
			"configure",
			pool,
			base_catalog,
			world_data,
			{"draftId": "formal-custom-pipeline", "revision": 1},
		) as Dictionary,
		"custom creator configures against the formal catalog and World",
	)
	var creator_vm := creator.call("get_view_model") as Dictionary
	var creator_data := creator_vm.get("data", {}) as Dictionary
	_expect_ok_session_production_composition(
		creator.call(
			"dispatch",
			"custom_resident_creator.update_fields",
			{
				"revision": int(creator_vm.get("revision", 0)),
				"draftId": String(creator_data.get("draftId", "")),
				"fields": {
					"name": "正式管线居民",
					"gender": "女",
					"age": 29,
					"desire": "参与正式小镇生活",
					"personality": "耐心且谨慎，愿意核对事实",
					"speech": "先核对事实再回答",
				},
			},
		) as Dictionary,
		"custom creator accepts a complete formal profile",
	)
	creator_vm = creator.call("get_view_model") as Dictionary
	creator_data = creator_vm.get("data", {}) as Dictionary
	var created := creator.call(
		"dispatch",
		"custom_resident_creator.create",
		{
			"revision": int(creator_vm.get("revision", 0)),
			"draftId": String(creator_data.get("draftId", "")),
			"candidatePoolRevision": int(
				creator_data.get("candidatePoolRevision", -1),
			),
		},
	) as Dictionary
	_expect_ok_session_production_composition(created, "custom creator publishes one formal candidate")
	if created.get("ok") != true:
		return
	var candidate := created.get("candidate", {}) as Dictionary
	var attributes := candidate.get("attributes", {}) as Dictionary
	_expect(
		String(attributes.get("appearance", "")).begins_with(
			"resident_wardrobe_v1:",
		),
		"custom creator publishes one approved World appearance id",
	)
	_expect(
		candidate.get("appearance") is Dictionary,
		"custom creator keeps appearance as a top-level authority",
	)
	var legacy_candidate := candidate.duplicate(true)
	(
		legacy_candidate.get("attributes", {}) as Dictionary
	)["appearance"] = "paper_doll_64:legacy"
	var legacy_result := pool.call(
		"create_candidate",
		legacy_candidate,
		int(pool.call("candidate_pool_revision")),
	) as Dictionary
	_expect_equal(
		legacy_result.get("errorCode"),
		"CUSTOM_RESIDENT_APPEARANCE_NOT_READY",
		"candidate pool rejects an appearance outside the approved wardrobe",
	)
	var custom_id := String(candidate.get("residentId", ""))
	var merged_catalog := pool.call("get_merged_catalog") as Dictionary
	var projection := pool.call(
		"get_resident_selection_projection",
	) as Dictionary
	var selection_vm := RESIDENT_CATALOG.build_view_model(
		"fake",
		"fake",
		true,
		20,
	) as Dictionary
	var selection_data := selection_vm.get("data", {}) as Dictionary
	(selection_data.get("resident_catalog", []) as Array).append_array(
		(projection.get("catalogEntries", []) as Array).duplicate(true),
	)
	(selection_data.get("residents", []) as Array).append_array(
		(projection.get("selectionEntries", []) as Array).duplicate(true),
	)
	var selected := (
		selection_data.get("recommended_resident_ids", []) as Array
	).duplicate()
	selected.remove_at(1)
	selected.append(custom_id)
	selection_data["selected_resident_ids"] = selected
	RESIDENT_CATALOG.update_confirmation_payload(
		selection_data,
		"fake",
		"fake",
		21,
	)
	var custom_draft := (
		selection_data.get("confirmation_payload", {}) as Dictionary
	)
	_expect_equal(
		(custom_draft.get("slots", []) as Array).size(),
		RESIDENT_CATALOG.SELECTION_LIMIT,
		"merged custom candidate produces a complete 15-resident draft",
	)
	var compiled := COMPILER.compile(custom_draft, world_data, merged_catalog)
	_expect_ok_session_production_composition(
		compiled,
		"Creator to CandidatePool to Catalog selection compiles formally",
	)



func _read_json_session_production_composition(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}



func _send_physical_key(
	action: StringName,
	keycode: Key,
	pressed: bool,
) -> void:
	var event := InputEventKey.new()
	event.device = TEST_KEYBOARD_DEVICE_ID
	event.keycode = keycode
	event.pressed = pressed
	if pressed:
		_expect(
			InputMap.event_is_action(event, action),
			"physical key %s uses the shipped %s InputMap binding" % [
				keycode,
				action,
			],
		)
	Input.parse_input_event(event)
	Input.flush_buffered_events()



func _expect_ok_session_production_composition(result: Dictionary, message: String) -> void:
	_expect(bool(result.get("ok", false)), "%s: %s" % [message, result])



func _result_has_error_code(result: Dictionary, error_code: String) -> bool:
	for error_value: Variant in result.get("errors", []) as Array:
		if (
			error_value is Dictionary
			and String((error_value as Dictionary).get("code", ""))
			== error_code
		):
			return true
	return false



func _scenario_hud_pause_clock() -> void:
	var adapter := ADAPTER.new()
	root.add_child(adapter)
	await process_frame
	var initial_now := Time.get_ticks_msec()
	var original_started := initial_now - 200
	var original_expires := initial_now + 800
	adapter.set("_hud_public_thoughts", {
		"resident-a:action-a": {
			"startedAtMsec": original_started,
			"expiresAtMsec": original_expires,
		},
	})
	adapter.set("_hud_far_conversations", {
		"conversation-a": {
			"startedAtMsec": original_started,
			"expiresAtMsec": 0,
		},
	})
	_expect(
		bool(adapter.call("_sync_hud_pause_state", true)),
		"entering pause starts the presentation hold",
	)
	adapter.set("_hud_pause_started_msec", Time.get_ticks_msec() - 1600)
	_expect(
		not bool(adapter.call("_prune_hud_public_thoughts")),
		"paused presentation never expires transient HUD items",
	)
	_expect(
		bool(adapter.call("_sync_hud_pause_state", false)),
		"resuming closes the presentation hold",
	)
	var thoughts := adapter.get("_hud_public_thoughts") as Dictionary
	var shifted := (
		thoughts.get("resident-a:action-a", {}) as Dictionary
	)
	_expect(
		int(shifted.get("startedAtMsec", 0)) >= original_started + 1500,
		"resume shifts the transient start time by the pause duration",
	)
	_expect(
		int(shifted.get("expiresAtMsec", 0)) >= original_expires + 1500,
		"resume preserves the transient's remaining visible lifetime",
	)
	var conversations := adapter.get("_hud_far_conversations") as Dictionary
	var conversation := (
		conversations.get("conversation-a", {}) as Dictionary
	)
	_expect_equal(
		conversation.get("expiresAtMsec"),
		0,
		"indefinite active conversations remain indefinite across pause",
	)
	adapter.queue_free()
	await process_frame
