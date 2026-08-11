extends SceneTree


const SERVICE := preload(
	"res://world/presentation/ui/TownUiPageProjectionService.gd"
)
const INNER_OBSERVATION_OVERLAY := preload(
	"res://ui/inner_observation/InnerObservationOverlay.tscn"
)
const BULLETIN_PANEL := preload("res://ui/bulletin_board/BulletinBoardPanel.gd")
const RESIDENT_MENU := preload("res://ui/resident_action_menu/ResidentActionMenu.gd")
const RESIDENT_DETAIL_SCREEN := preload(
	"res://ui/resident_detail/ResidentDetailScreen.tscn"
)
const INDOOR_OVERLAY := preload("res://ui/indoor_overlay/IndoorOverlay.gd")
const WORLD_LOG_STORE := preload(
	"res://world/runtime/log/TownWorldLogStore.gd"
)


class FakeWorld:
	extends RefCounted

	signal world_revision_changed(revision: int)
	signal environment_changed(time: Dictionary, weather: String)
	signal announcement_published(announcement: Dictionary)
	signal world_event_created(resident_name: String, event: Dictionary)
	signal action_result_created(resident_name: String, result: Dictionary)
	signal resident_place_changed(resident_name: String, change: Dictionary)
	signal player_avatar_place_changed(change: Dictionary)

	var revision := 42
	var weather := "晴天"
	var announcements: Array[Dictionary] = []
	var public_events: Array[Dictionary] = []
	var world_log: RefCounted = WORLD_LOG_STORE.new()
	var activity_needs: Variant = {
		"energy": 82,
		"satiety": 36,
		"stress": 18,
		"socialNeed": 52,
		"solitudeNeed": 76,
	}
	var social_matter_projection := {
		"revision": 42,
		"items": [],
		"history": [{
			"eventId": "social:matter-cafe:response:round-1",
			"matterId": "matter-cafe",
			"matterKind": "place_service_pressure",
			"matterSummary": "3位客人正在等待",
			"occurredAt": 550,
			"worldTime": {
				"day": 1,
				"hour": 9,
				"minute": 10,
			},
			"outcome": "responded",
			"responderResidentIds": ["resident-lin-lan"],
			"responderNames": ["林岚"],
			"responseCount": 1,
			"nonResponderResidentIds": ["resident-luo-xing"],
			"nonResponderNames": ["洛星"],
			"nonResponseCount": 1,
			"resultSummary": "林岚回应了这件事",
			"confirmedRevision": 41,
		}, {
			"eventId": "social:matter-cafe:result:resident-lin-lan",
			"matterId": "matter-cafe",
			"matterKind": "place_service_pressure",
			"matterSummary": "3位客人正在等待",
			"occurredAt": 570,
			"worldTime": {
				"day": 1,
				"hour": 9,
				"minute": 30,
			},
			"outcome": "completed",
			"responderResidentIds": ["resident-lin-lan"],
			"responderNames": ["林岚"],
			"responseCount": 1,
			"nonResponderResidentIds": [],
			"nonResponderNames": [],
			"nonResponseCount": 0,
			"resultSummary": "林岚完成了帮忙",
			"confirmedRevision": 42,
		}],
	}

	func _init() -> void:
		world_log.call("reset", "projection-test")

	func is_running() -> bool:
		return true

	func get_world_revision() -> int:
		return revision

	func get_weather() -> String:
		return weather

	func get_time() -> Dictionary:
		return {"day": 1, "clock": "09:00", "period": "上午"}

	func set_weather(value: String) -> Dictionary:
		if value == "无效天气":
			return {
				"ok": false,
				"errorCode": "INVALID_WEATHER",
				"retryable": false,
				"errors": ["invalid"],
			}
		weather = value
		revision += 1
		world_revision_changed.emit(revision)
		environment_changed.emit({"day": 1, "clock": "09:00"}, weather)
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"changed": true,
			"worldRevision": revision,
		}

	func get_announcements() -> Array[Dictionary]:
		return announcements.duplicate(true)

	func get_public_event_log() -> Array[Dictionary]:
		return public_events.duplicate(true)

	func get_public_social_matter_activity() -> Dictionary:
		return social_matter_projection.duplicate(true)

	func publish_announcement(text: String) -> Dictionary:
		if text == "拒绝发布":
			return {
				"ok": false,
				"errorCode": "ANNOUNCEMENT_REJECTED",
				"retryable": false,
				"errors": ["rejected"],
			}
		var item := {
			"announcement_id": "announcement-%d" % (announcements.size() + 1),
			"text": text,
			"time": {"day": 1, "clock": "09:05", "period": "上午"},
		}
		if text == "今晚广场见。":
			item["scheduled_absolute_minute"] = 20 * 60
			item["scheduled_time_label"] = "第1天 20:00"
		announcements.append(item)
		revision += 1
		announcement_published.emit(item.duplicate(true))
		world_revision_changed.emit(revision)
		var schedule_warning := text == "周五下午三点见。"
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"announcement": item,
			"worldRevision": revision,
			"scheduleRecognized": item.has("scheduled_absolute_minute"),
			"scheduleWarning": schedule_warning,
		}

	func get_resident_identity_snapshot() -> Dictionary:
		return {
			"status": "confirmed",
			"residents": [{
				"residentId": "resident-lin-lan",
				"residentName": "林岚",
			}],
		}

	func get_place_detail(place_name: String) -> Dictionary:
		if place_name != "图书馆":
			return {}
		return {
			"spaceId": "indoor_library",
			"name": "图书馆",
			"type": "公共设施",
			"summary": "可借阅、工作与阅读的正式室内地点",
			"props": [{
				"name": "图书馆阅读位",
				"interaction": {
					"instanceId": "library-reading-seat-01",
					"assetId": "wooden_chair",
				},
				"actions": [{"verb": "阅读"}],
			}],
		}

	func get_indoor_layout_projection(space_id: String) -> Dictionary:
		if space_id != "indoor_library":
			return {}
		return {
			"spaceId": space_id,
			"placeName": "图书馆",
			"props": [{
				"name": "图书馆阅读位",
				"interaction": {
					"instanceId": "library-reading-seat-01",
					"assetId": "wooden_chair",
					"instancePosition": [64.0, 96.0],
				},
				"actions": [{"verb": "阅读"}],
			}],
		}

	func get_resident_state(resident_name: String) -> Dictionary:
		if resident_name != "林岚":
			return {}
		return {
			"name": resident_name,
			"currentPlace": "图书馆",
			"doing": "查找木工资料",
			"body": {
				"困": "不困",
				"饿": "有点饿",
				"累": "不累",
			},
			"activityNeeds": activity_needs,
			"conditions": [
				{
					"conditionId": "condition-headache-1",
					"kind": "headache",
					"label": "头痛得难以集中精神",
					"state": "active",
				},
				{
					"conditionId": "condition-wet-1",
					"kind": "wet",
					"label": "衣服和头发都湿了",
					"state": "recovering",
				},
			],
			"activeNeeds": [
				{"kind": "rest", "label": "降低活动强度并休息"},
				{"kind": "consider_clinic", "label": "可以考虑向诊所提出看诊请求"},
			],
			"recentOutcome": {
				"status": "completed",
				"label": "查阅木工资料",
			},
		}

	func get_resident_detail(resident_name: String) -> Dictionary:
		var runtime_state := get_resident_state(resident_name)
		if runtime_state.is_empty():
			return {}
		return {
			"residentId": "resident-lin-lan",
			"name": resident_name,
			"attributes": {
				"name": resident_name,
				"appearance": "resident_wardrobe_v1:look_01",
				"desire": "把找到的资料读完",
			},
			"socialState": {},
			"runtimeState": runtime_state,
		}

	func emit_public_event(resident_name: String, event: Dictionary) -> void:
		public_events.append({
			"kind": "world_event",
			"residentName": resident_name,
			"payload": event.duplicate(true),
		})
		world_log.call("append_public_event", {
			"eventId": String(event.get("event_id", event.get("eventId", ""))),
			"kind": "world_event",
			"time": (event.get("time", {}) as Dictionary).duplicate(true),
			"worldRevision": revision,
			"residentId": "resident-lin-lan",
			"residentName": resident_name,
			"placeName": "图书馆",
			"payload": event.duplicate(true),
		})
		world_event_created.emit(resident_name, event.duplicate(true))

	func emit_action_result(resident_name: String, result: Dictionary) -> void:
		action_result_created.emit(resident_name, result.duplicate(true))

	func query_world_log_threads(filters: Dictionary = {}) -> Dictionary:
		return world_log.call("query_threads", filters.duplicate(true)) as Dictionary

	func get_world_log_thread_detail(thread_id: String, options: Dictionary = {}) -> Dictionary:
		return world_log.call("get_thread_detail", thread_id, options.duplicate(true)) as Dictionary

	func query_world_log_place_observations(
		place_id: String,
		options: Dictionary = {},
	) -> Dictionary:
		return world_log.call(
			"query_place_observations",
			place_id,
			options.duplicate(true),
		) as Dictionary

	func find_world_log_thread_by_source_event(event_id: String) -> Dictionary:
		return world_log.call(
			"find_thread_by_source_event",
			event_id,
		) as Dictionary

	func get_world_log_causal_chain(
		thread_id: String,
		options: Dictionary = {},
	) -> Dictionary:
		return world_log.call(
			"get_causal_chain",
			thread_id,
			options.duplicate(true),
		) as Dictionary

	func mark_world_log_thread_read(thread_id: String, displayed_through_sequence: int) -> Dictionary:
		return world_log.call("mark_thread_read", thread_id, displayed_through_sequence) as Dictionary

	func get_world_log_filter_catalog() -> Dictionary:
		return world_log.call("get_filter_catalog") as Dictionary


class FakeRuntime:
	extends Node

	signal observed_place_changed(result: Dictionary)

	var world: FakeWorld
	var followed_name := ""
	var selected_name := ""
	var interior_active := true
	var avatar_mode := "observer"
	var player_avatar_enabled := true

	func _init(value: FakeWorld) -> void:
		world = value

	func request_world_weather(weather_id: String) -> Dictionary:
		return world.set_weather(weather_id)

	func publish_player_announcement(text: String) -> Dictionary:
		return world.publish_announcement(text)

	func get_resident_identity_snapshot() -> Dictionary:
		return world.get_resident_identity_snapshot()

	func get_runtime_state() -> Dictionary:
		return {
			"selectedResident": "林岚",
			"followedResident": followed_name,
			"viewMode": "interior" if interior_active else "town",
			"observedPlace": "图书馆" if interior_active else "",
			"activeInteriorId": "library" if interior_active else "",
			"avatarMode": avatar_mode,
			"playerAvatarEnabled": player_avatar_enabled,
			"playerAvatar": {
				"currentPlace": "图书馆" if interior_active else "中心广场",
			},
		}

	func get_lifecycle_state() -> Dictionary:
		return {"paused": false, "pauseReasons": []}

	func get_resident_screen_anchor(_resident_name: String) -> Dictionary:
		return {"x": 960.0, "y": 700.0}

	func get_active_indoor_screen_anchor(values: Array) -> Dictionary:
		return {
			"x": float(values[0]) + 400.0,
			"y": float(values[1]) + 200.0,
			"valid": true,
			"coordinateSpace": "viewport_logical",
		}

	func get_active_indoor_exit_screen_anchor() -> Dictionary:
		return {
			"x": 960.0,
			"y": 920.0,
			"valid": true,
			"coordinateSpace": "viewport_logical",
		}

	func follow_resident(resident_name: String) -> bool:
		followed_name = resident_name
		return resident_name == "林岚"

	func select_resident(resident_name: String) -> bool:
		selected_name = resident_name
		return resident_name == "林岚"

	func return_to_town_overview() -> bool:
		interior_active = false
		return true

	func request_return_to_town_overview() -> Dictionary:
		if player_avatar_enabled:
			return {"ok": false, "errorCode": "PHYSICAL_EXIT_REQUIRED", "retryable": false}
		interior_active = false
		return {"ok": true, "accepted": true, "errorCode": "", "retryable": false}

	func exit_avatar_mode() -> Dictionary:
		avatar_mode = "observer"
		return {"ok": true, "errorCode": "", "retryable": false}


class FakeGateway:
	extends RefCounted

	var fail_inner_request := false
	var fail_memory_request := false
	var last_memory_intervention: Dictionary = {}

	func get_resident_memory(_resident_id: String) -> Dictionary:
		if fail_memory_request:
			return {
				"ok": false,
				"errorCode": "TEST_MEMORY_TEMPORARILY_UNAVAILABLE",
				"retryable": true,
			}
		return {
			"ok": true,
			"memory": {
				"formal_memory_revision": 7,
				"formal_memories": [{
					"memoryKey": "memory:library-book",
					"subject": "图书馆里的旧册子",
					"interpretation": "今天在图书馆找到了一本旧册子。",
					"state": "influencing",
					"sourceKind": "firsthand",
					"confidence": 60,
					"people": ["玩家"],
					"places": ["图书馆"],
					"worldTime": {"day": 1, "clock": "09:10", "period": "上午"},
				}],
				"interventions": [{
					"memoryKey": "memory:library-book",
					"operation": "edit",
					"status": "active",
					"originalSubject": "一本旧册子",
					"activeSubject": "图书馆里的旧册子",
					"playerText": "那是在图书馆找到的。",
					"createdWorldTime": {"day": 1, "clock": "09:20", "period": "上午"},
				}],
				"relationships": "和唐小满逐渐熟悉。",
				"current_focus": "想把刚找到的资料读完。",
				"important_memory_influence": {
					"available": true,
					"level": 3,
					"segmentCount": 5,
					"label": "持续在意",
				},
				"relationship_progress": [{
					"residentId": "resident_tang_xiaoman_01",
					"displayName": "唐小满",
					"conversationCount": 2,
					"confirmedTurnCount": 6,
					"lastInteractionAt": {
						"day": 1,
						"clock": "09:10",
						"period": "上午",
					},
					"depth": {
						"available": true,
						"level": 3,
						"segmentCount": 5,
						"label": "常有来往",
					},
				}],
			},
		}

	func apply_resident_memory_intervention(
		resident_id: String,
		request: Dictionary,
	) -> Dictionary:
		last_memory_intervention = request.duplicate(true)
		last_memory_intervention["residentId"] = resident_id
		return {"ok": true, "formalMemoryRevision": 8}

	func request_resident_inner_observation(
		resident_id: String,
		request_id: String,
		_confirmed_world_revision: int,
		on_complete: Callable,
	) -> Dictionary:
		if fail_inner_request:
			return {
				"ok": false,
				"errorCode": "INNER_OBSERVATION_PUBLIC_SNAPSHOT_UNAVAILABLE",
				"retryable": true,
			}
		on_complete.call_deferred({
			"residentId": resident_id,
			"requestId": request_id,
			"status": "ready",
			"content": {
				"contentKind": "resident_current_focus",
				"monologueText": "想把刚找到的资料读完。",
				"reasonText": "",
				"playerStatusText": "",
				"empty": false,
				"fallbackUsed": false,
			},
			"errorCode": "",
			"retryable": false,
		})
		return {
			"ok": true,
			"accepted": true,
			"requestId": request_id,
			"errorCode": "",
			"retryable": false,
		}

	func cancel_resident_inner_observation(_request_id: String) -> bool:
		return true


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := FakeWorld.new()
	var runtime := FakeRuntime.new(world)
	var gateway := FakeGateway.new()
	root.add_child(runtime)
	var service := SERVICE.new()
	var bind_result := service.bind(runtime, world, {
		"worldStartMode": "formal",
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
		"logicalViewport": {"x": 0, "y": 0, "width": 1920, "height": 1080},
	}, gateway)
	_expect(bool(bind_result.get("ok", false)), "service bind succeeds")

	for scope in SERVICE.SCOPES:
		_assert_complete_envelope(service.get_view_model(scope), scope)

	var weather := service.get_view_model("weather_control")
	_expect_equal(weather.get("formalReady"), true, "weather is backed by formal runtime")
	_expect_equal(
		((weather.get("data", {}) as Dictionary).get("weatherOptions", []) as Array).size(),
		6,
		"weather exposes six real command choices",
	)
	var weather_success := service.dispatch(
		"environment.weather_change", {"weatherId": "小雨"}
	)
	_expect(bool(weather_success.get("ok", false)), "weather command reaches runtime")
	weather = service.get_view_model("weather_control")
	_expect_equal(
		((weather.get("data", {}) as Dictionary).get("currentWeather", {}) as Dictionary).get("id"),
		"小雨",
		"weather projection reads confirmed world state",
	)
	_expect_equal(
		((weather.get("operation", {}) as Dictionary).get("status")),
		"success",
		"weather success is visible",
	)
	var confirmed_weather_data := (weather.get("data", {}) as Dictionary).duplicate(true)
	var confirmed_weather_revision := int(weather.get("revision", -1))
	var rejected_weather := service.dispatch(
		"environment.weather_change", {"weatherId": "无效天气"}
	)
	_expect(not bool(rejected_weather.get("ok", true)), "invalid weather is rejected")
	weather = service.get_view_model("weather_control")
	_expect_equal(
		(weather.get("operation", {}) as Dictionary).get("status"),
		"rejected",
		"deterministic weather refusal is rejected",
	)
	_expect_equal(
		weather.get("data"),
		confirmed_weather_data,
		"rejected weather preserves last confirmed data",
	)
	_expect_equal(
		int(weather.get("revision", -1)),
		confirmed_weather_revision,
		"rejected weather preserves last confirmed revision",
	)
	runtime.avatar_mode = "avatar_active"
	weather = service.refresh("weather_control")
	_expect_equal(
		((weather.get("data", {}) as Dictionary).get("mode", {}) as Dictionary).get("id"),
		"avatar",
		"weather projection reflects avatar_active without changing observer ownership",
	)
	_expect(
		not bool(((weather.get("actions", {}) as Dictionary).get("weatherChange", {}) as Dictionary).get("enabled", true)),
		"weather command is disabled while avatar control is active",
	)
	_expect(
		bool(service.dispatch("avatar.switch_to_overview", {}).get("ok", false)),
		"weather page can request the existing avatar exit transition",
	)
	_expect_equal(runtime.avatar_mode, "observer", "avatar exit returns to observer mode")

	var announcements := service.get_view_model("announcements")
	_assert_announcement_contract(announcements)
	_assert_page_contracts(service)
	_expect(bool(service.dispatch("announcements.composer.open").get("ok", false)), "composer opens locally")
	_expect(bool(service.dispatch("announcements.draft.update", {"text": "拒绝发布"}).get("ok", false)), "draft update is accepted")
	announcements = service.get_view_model("announcements")
	var confirmed_announcement_data := (announcements.get("data", {}) as Dictionary).duplicate(true)
	var rejected_announcement := service.dispatch(
		"announcements.publish", {"text": "拒绝发布"}
	)
	_expect(not bool(rejected_announcement.get("ok", true)), "runtime can reject announcement")
	announcements = service.get_view_model("announcements")
	_expect_equal(
		(announcements.get("operation", {}) as Dictionary).get("status"),
		"rejected",
		"announcement rejection is visible",
	)
	_expect_equal(
		announcements.get("data"),
		confirmed_announcement_data,
		"rejected announcement preserves draft and confirmed data",
	)
	_expect(
		bool(service.dispatch("announcements.panel.close", {}).get(
			"ok",
			false,
		)),
		"closing a bulletin with a draft is handled by the service",
	)
	announcements = service.get_view_model("announcements")
	var close_confirmation_data := (
		announcements.get("data", {}) as Dictionary
	)
	_expect(
		bool((close_confirmation_data.get("panel", {}) as Dictionary).get(
			"open",
			false,
		)),
		"unsaved bulletin draft keeps the panel open",
	)
	_expect(
		bool((close_confirmation_data.get("dialog", {}) as Dictionary).get(
			"open",
			false,
		)),
		"unsaved bulletin draft opens the discard confirmation",
	)
	_expect(
		bool(service.dispatch("announcements.draft.continue", {}).get(
			"ok",
			false,
		)),
		"bulletin confirmation can return to editing",
	)
	service.dispatch("announcements.draft.update", {"text": "今晚广场见。"})
	var publish_result := service.dispatch(
		"announcements.publish", {"text": "今晚广场见。"}
	)
	_expect(bool(publish_result.get("ok", false)), "announcement publish uses runtime public method")
	announcements = service.get_view_model("announcements")
	_expect_equal(
		((announcements.get("data", {}) as Dictionary).get("items", []) as Array).size(),
		1,
		"confirmed announcement appears from World",
	)
	var scheduled_feedback := (
		(announcements.get("data", {}) as Dictionary).get("feedback", {})
		as Dictionary
	)
	_expect(
		String(scheduled_feedback.get("message", "")).contains("第1天 20:00"),
		"时间公告发布后立即告诉玩家系统识别到的世界时刻",
	)
	service.dispatch("announcements.composer.open")
	service.dispatch(
		"announcements.draft.update",
		{"text": "周五下午三点见。"},
	)
	var warning_publish := service.dispatch(
		"announcements.publish",
		{"text": "周五下午三点见。"},
	)
	_expect(
		bool(warning_publish.get("ok", false)),
		"时间不能解析时仍保留公告本身",
	)
	announcements = service.get_view_model("announcements")
	var warning_feedback := (
		(announcements.get("data", {}) as Dictionary).get("feedback", {})
		as Dictionary
	)
	_expect_equal(
		warning_feedback.get("kind"),
		"warning",
		"时间未识别不用成功样式掩盖",
	)
	_expect(
		String(warning_feedback.get("message", "")).contains("没有识别"),
		"时间未识别会说清没有到点提醒",
	)

	service.set_page_context("resident_action_menu", {
		"residentId": "resident-lin-lan",
		"open": true,
	})
	var resident_menu := service.get_view_model("resident_action_menu")
	_expect_equal(resident_menu.get("formalReady"), true, "resident target and follow are formal")
	var resident_actions := resident_menu.get("actions", {}) as Dictionary
	_expect(bool((resident_actions.get("follow", {}) as Dictionary).get("enabled", false)), "follow is enabled")
	for action_key in ["openStatus", "openRelationship", "openMemory", "openInner"]:
		_expect(
			resident_actions.has(action_key),
			"resident menu keeps the approved %s entry" % action_key,
		)
	_expect(
		bool((resident_actions.get("openInner", {}) as Dictionary).get(
			"enabled",
			false,
		)),
		"inner observation is enabled when the formal gateway is bound",
	)
	_expect(
		not resident_actions.has("openDetail"),
		"resident menu does not invent an unfrozen consolidated entry",
	)
	var follow_result := service.dispatch(
		"resident.follow", {"residentId": "resident-lin-lan"}
	)
	_expect(bool(follow_result.get("ok", false)), "follow reaches runtime")
	_expect_equal(runtime.followed_name, "林岚", "stable ID maps to current display name")

	service.dispatch("resident.detail.open", {
		"residentId": "resident-lin-lan",
		"tab": "status",
	})
	var resident_detail := service.get_view_model("resident_detail")
	var resident_projection := (
		(resident_detail.get("data", {}) as Dictionary).get(
			"resident",
			{},
		) as Dictionary
	)
	_expect_equal(
		resident_projection.get("portrait"),
		(
			"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
			+ "classic_sets/runtime_portraits/lin_lan_front.png"
		),
		"resident detail projects the current wardrobe portrait",
	)
	_expect_equal(
		resident_projection.get("portraitFrameMode"),
		"full_texture",
		"resident detail keeps the complete wardrobe portrait",
	)
	var resident_detail_screen := (
		RESIDENT_DETAIL_SCREEN.instantiate() as ResidentDetailScreen
	)
	resident_detail_screen.set_layout_profile_size_override(
		Vector2(1920, 1080),
	)
	root.add_child(resident_detail_screen)
	await process_frame
	_expect(
		resident_detail_screen.apply_view_model(resident_detail),
		"resident detail screen accepts the portrait projection",
	)
	await process_frame
	var resident_portrait := resident_detail_screen.get_node_or_null(
		"ResidentPortrait",
	) as TextureRect
	_expect(
		resident_portrait != null
		and resident_portrait.visible
		and resident_portrait.texture != null,
		"resident detail screen renders the left portrait",
	)
	resident_detail_screen.queue_free()
	await process_frame
	var resident_content := (
		(resident_detail.get("data", {}) as Dictionary).get(
			"content",
			{},
		) as Dictionary
	)
	var life_meters := resident_content.get("lifeMeters", []) as Array
	var status_rows := resident_content.get("statusRows", []) as Array
	_expect_equal(status_rows.size(), 7, "status projection keeps all seven public rows")
	_expect_equal(
		resident_content.get("preferredStatusRowId"),
		"conditions",
		"active temporary conditions become the preferred public row",
	)
	_expect_equal(
		(status_rows[2] as Dictionary).get("shortText"),
		"头痛、淋湿（恢复中）",
		"condition row uses compact labels while retaining recovery state",
	)
	_expect(
		String((status_rows[2] as Dictionary).get("text", "")).contains(
			"衣服和头发都湿了（恢复中）",
		),
		"condition row keeps the full confirmed description",
	)
	_expect_equal(
		(status_rows[6] as Dictionary).get("shortText"),
		"完成了查阅木工资料",
		"recent row describes the latest confirmed result",
	)
	_expect_equal(life_meters.size(), 5, "five confirmed World needs fill the status meters")
	_expect_equal(
		int((life_meters[0] as Dictionary).get("value", -1)),
		82,
		"energy meter keeps the confirmed numeric value",
	)
	_expect_equal(
		int((life_meters[4] as Dictionary).get("value", -1)),
		76,
		"solitude meter keeps the confirmed numeric value",
	)
	world.activity_needs = {
		"energy": 82,
		"satiety": 36,
		"stress": 18.5,
		"socialNeed": 52,
		"solitudeNeed": 76,
	}
	service.refresh("resident_detail")
	_expect_equal(
		_resident_life_meters(service).size(),
		0,
		"a fractional World need is not disguised as a confirmed integer",
	)
	world.activity_needs = {
		"energy": 82,
		"satiety": 36,
		"stress": 18,
		"socialNeed": 52,
		"solitudeNeed": 76,
		"unknownNeed": 10,
	}
	service.refresh("resident_detail")
	_expect_equal(
		_resident_life_meters(service).size(),
		0,
		"an unknown World need key is not presented as an exact confirmed set",
	)
	world.activity_needs = {
		"energy": 82,
		"satiety": 36,
		"stress": 101,
		"socialNeed": 52,
		"solitudeNeed": 76,
	}
	service.refresh("resident_detail")
	_expect_equal(
		_resident_life_meters(service).size(),
		0,
		"an out-of-range World need is not silently clamped",
	)
	world.activity_needs = {
		"energy": 82,
		"satiety": 36,
		"stress": INF,
		"socialNeed": 52,
		"solitudeNeed": 76,
	}
	service.refresh("resident_detail")
	_expect_equal(
		_resident_life_meters(service).size(),
		0,
		"a non-finite World need is not presented",
	)
	world.activity_needs = "invalid"
	service.refresh("resident_detail")
	_expect_equal(
		_resident_life_meters(service).size(),
		0,
		"a malformed World need envelope does not break resident details",
	)
	world.activity_needs = {
		"energy": 82,
		"satiety": 36,
		"stress": 18,
		"socialNeed": 52,
		"solitudeNeed": 76,
	}
	service.refresh("resident_detail")
	service.dispatch("resident_detail.select_tab", {
		"residentId": "resident-lin-lan",
		"tabId": "relationships",
	})
	resident_detail = service.get_view_model("resident_detail")
	_expect_equal(
		(
			(resident_detail.get("data", {}) as Dictionary).get(
				"resident",
				{},
			) as Dictionary
		).get("portrait"),
		resident_projection.get("portrait"),
		"relationship tab preserves the resident portrait",
	)
	resident_content = (
		(resident_detail.get("data", {}) as Dictionary).get(
			"content",
			{},
		) as Dictionary
	)
	var relationship_items := resident_content.get("items", []) as Array
	_expect_equal(
		relationship_items.size(),
		1,
		"confirmed shared conversations create one relationship row",
	)
	if relationship_items.size() == 1:
		_expect_equal(
			((relationship_items[0] as Dictionary).get(
				"depth",
				{},
			) as Dictionary).get("level"),
			3,
			"relationship row consumes evidence-based interaction depth",
		)
		_expect_equal(
			(relationship_items[0] as Dictionary).get("portraitRef"),
			(
				"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
				+ "classic_sets/runtime_portraits/tang_xiaoman_front.png"
			),
			"relationship row projects the related resident portrait",
		)
	var relationship_actions := resident_detail.get("actions", {}) as Dictionary
	_expect_equal(
		(relationship_actions.get("filterRelationshipClose", {}) as Dictionary).get("intent"),
		"resident_detail.filter_relationships",
		"relationship filter action is exposed to the page",
	)
	service.dispatch("resident_detail.filter_relationships", {
		"residentId": "resident-lin-lan",
		"filterId": "close",
	})
	resident_detail = service.get_view_model("resident_detail")
	resident_content = (
		(resident_detail.get("data", {}) as Dictionary).get(
			"content",
			{},
		) as Dictionary
	)
	_expect_equal(resident_content.get("filterId"), "close", "relationship filter selection is retained")
	_expect_equal(
		(resident_content.get("items", []) as Array).size(),
		1,
		"close relationship filter keeps the deep relationship",
	)
	service.dispatch("resident_detail.filter_relationships", {
		"residentId": "resident-lin-lan",
		"filterId": "distant",
	})
	resident_detail = service.get_view_model("resident_detail")
	resident_content = (
		(resident_detail.get("data", {}) as Dictionary).get(
			"content",
			{},
		) as Dictionary
	)
	_expect_equal(
		(resident_content.get("items", []) as Array).size(),
		0,
		"distant relationship filter removes the deep relationship",
	)
	service.dispatch("resident_detail.select_tab", {
		"residentId": "resident-lin-lan",
		"tabId": "memories",
	})
	resident_detail = service.get_view_model("resident_detail")
	_expect_equal(
		(
			(resident_detail.get("data", {}) as Dictionary).get(
				"resident",
				{},
			) as Dictionary
		).get("portrait"),
		resident_projection.get("portrait"),
		"memory tab preserves the resident portrait",
	)
	resident_content = (
		(resident_detail.get("data", {}) as Dictionary).get(
			"content",
			{},
		) as Dictionary
	)
	var memory_items := resident_content.get("items", []) as Array
	_expect_equal(memory_items.size(), 1, "public memory summary remains visible")
	if memory_items.size() == 1:
		_expect_equal(
			((memory_items[0] as Dictionary).get(
				"influence",
				{},
			) as Dictionary).get("level"),
			3,
			"memory row consumes actual cross-field influence",
		)
		_expect_equal(
			(memory_items[0] as Dictionary).get("sourceLabel"),
			"亲历",
			"formal memory source is projected for the page",
		)
	var memory_actions := resident_detail.get("actions", {}) as Dictionary
	_expect_equal(
		((memory_actions.get("editMemory", {}) as Dictionary).get("payload", {}) as Dictionary).get("expectedRevision"),
		7,
		"memory action carries the confirmed revision",
	)
	service.dispatch("resident_detail.filter_memories", {
		"residentId": "resident-lin-lan",
		"filterId": "interventions",
	})
	resident_detail = service.get_view_model("resident_detail")
	resident_content = (
		(resident_detail.get("data", {}) as Dictionary).get("content", {})
		as Dictionary
	)
	_expect_equal(
		resident_content.get("filterId"),
		"interventions",
		"memory filter selection is retained",
	)
	_expect_equal(
		(resident_content.get("items", []) as Array).size(),
		1,
		"intervention history is projected as its own list",
	)
	service.dispatch("resident_detail.change_memory", {
		"residentId": "resident-lin-lan",
		"memoryKey": "memory:library-book",
		"operation": "edit",
		"playerText": "那是在图书馆找到的。",
		"expectedRevision": 7,
	})
	_expect_equal(
		gateway.last_memory_intervention.get("memoryKey"),
		"memory:library-book",
		"memory edit is forwarded through the World gateway",
	)
	gateway.fail_memory_request = true
	service.set_page_context("resident_action_menu", {
		"residentId": "resident-lin-lan",
		"open": true,
	})
	resident_menu = service.get_view_model("resident_action_menu")
	resident_actions = resident_menu.get("actions", {}) as Dictionary
	for action_key in ["openRelationship", "openMemory"]:
		_expect(
			bool((resident_actions.get(action_key, {}) as Dictionary).get(
				"enabled",
				false,
			)),
			"%s remains reachable while public data is unavailable" % action_key,
		)
	service.dispatch("resident.detail.open", {
		"residentId": "resident-lin-lan",
		"tab": "relationship",
	})
	resident_detail = service.get_view_model("resident_detail")
	resident_content = (
		(resident_detail.get("data", {}) as Dictionary).get(
			"content",
			{},
		) as Dictionary
	)
	_expect_equal(
		resident_content.get("availability"),
		"unavailable",
		"relationship page opens into an explicit unavailable state",
	)
	var retry_action := (
		(resident_detail.get("actions", {}) as Dictionary).get(
			"retry",
			{},
		) as Dictionary
	)
	_expect(
		bool(retry_action.get("enabled", false)),
		"retry stays available for a retryable public-summary read failure",
	)
	gateway.fail_memory_request = false

	gateway.fail_inner_request = true
	service.set_page_context("resident_action_menu", {
		"residentId": "resident-lin-lan",
		"open": true,
	})
	var inner_open_result := service.dispatch(
		"resident.inner_observation.open",
		{"residentId": "resident-lin-lan"},
	)
	_expect(
		bool(inner_open_result.get("ok", false)),
		"inner page remains reachable when its data read fails",
	)
	var inner_view_model := service.get_view_model("inner_observation")
	var inner_data := inner_view_model.get("data", {}) as Dictionary
	var inner_resident := inner_data.get("resident", {}) as Dictionary
	var inner_portrait := inner_resident.get("portrait", {}) as Dictionary
	_expect_equal(
		inner_portrait.get("status"),
		"ready",
		"inner observation resolves the resident wardrobe preview",
	)
	_expect(
		String(inner_portrait.get("assetPath", "")).ends_with(
			"lin_lan_front.png"
		)
		and ResourceLoader.exists(
			String(inner_portrait.get("assetPath", "")),
			"Texture2D",
		),
		"inner observation portrait points to an importable resident image",
	)
	_expect_equal(inner_data.get("visibility"), "visible", "inner failure is shown on its page")
	_expect_equal(inner_data.get("phase"), "failed", "inner data failure has an honest failed phase")
	_expect_equal(
		inner_data.get("content"),
		{},
		"inner data failure never fabricates resident thoughts",
	)
	var unavailable_service := SERVICE.new()
	var unavailable_bind := unavailable_service.bind(
		runtime,
		world,
		{
			"worldStartMode": "formal",
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
		},
		null,
	) as Dictionary
	_expect(
		bool(unavailable_bind.get("ok", false)),
		"inner unavailable fixture binds without a Gateway",
	)
	unavailable_service.set_page_context("resident_action_menu", {
		"residentId": "resident-lin-lan",
		"open": true,
	})
	var unavailable_menu := unavailable_service.get_view_model(
		"resident_action_menu",
	) as Dictionary
	_expect(
		bool((
			(
				unavailable_menu.get("actions", {}) as Dictionary
			).get("openInner", {}) as Dictionary
		).get("enabled", false)),
		"inner entry stays clickable when read-only data is unavailable",
	)
	var unavailable_open := unavailable_service.dispatch(
		"resident.inner_observation.open",
		{"residentId": "resident-lin-lan"},
	) as Dictionary
	_expect(
		bool(unavailable_open.get("ok", false)),
		"inner page does not open when its data source is unavailable",
	)
	var unavailable_inner := unavailable_service.get_view_model(
		"inner_observation",
	) as Dictionary
	var unavailable_data := (
		unavailable_inner.get("data", {}) as Dictionary
	)
	_expect_equal(
		unavailable_data.get("visibility"),
		"visible",
		"inner unavailable state is not presented on the page",
	)
	_expect_equal(
		unavailable_data.get("phase"),
		"failed",
		"inner unavailable state is not an honest failed page",
	)
	_expect_equal(
		unavailable_data.get("formalReady"),
		true,
		"formal inner page is incorrectly disabled with its data source",
	)
	var unavailable_overlay := (
		INNER_OBSERVATION_OVERLAY.instantiate() as Control
	)
	root.add_child(unavailable_overlay)
	_expect(
		bool(unavailable_overlay.call(
			"apply_view_model",
			unavailable_inner,
		))
		and unavailable_overlay.visible,
		"inner unavailable ViewModel does not mount its visible page",
	)
	var inner_heading := unavailable_overlay.find_child(
		"ObservationWhisper",
		true,
		false,
	) as Label
	_expect_equal(
		inner_heading.text if inner_heading != null else "",
		"此刻的心声",
		"inner page uses its formerly empty top slot as a clear heading",
	)
	_expect(
		unavailable_overlay.find_child("PageAdvanceAction", true, false) == null,
		"inner page no longer exposes report-style page confirmation",
	)
	unavailable_overlay.queue_free()

	var town_log := service.get_view_model("town_log")
	_assert_town_log_contract(town_log)
	_expect_equal(town_log.get("status"), "ready", "town log consumes the formal archive")
	_expect_equal(town_log.get("formalReady"), true, "town log is formal with a formal session")
	service.set_page_context("town_log", {"open": true})
	world.emit_public_event("林岚", {
		"event_id": "public-cause-1",
		"type": "天气变了",
		"weather": "小雨",
		"time": {"day": 1, "clock": "09:10", "period": "上午"},
	})
	world.emit_public_event("林岚", {
		"event_id": "public-effect-1",
		"type": "搭话",
		"conversation_id": "conversation-1",
		"participant_resident_ids": ["resident-lin-lan"],
		"turn": {"speaker": "林岚", "say": "早上好。"},
		"causedByEventIds": ["public-cause-1"],
		"time": {"day": 1, "clock": "09:11", "period": "上午"},
	})
	world.emit_action_result("林岚", {
		"action_id": "read-carpentry-1",
		"status": "完成",
		"reason": "找到了需要的木工资料。",
		"time": {"day": 1, "clock": "09:12", "period": "上午"},
	})
	var event_revision := int(service.get_view_model("town_log").get("revision", -1))
	world.emit_public_event("林岚", {
		"event_id": "public-effect-1",
		"type": "搭话",
		"conversation_id": "conversation-1",
		"participant_resident_ids": ["resident-lin-lan"],
		"turn": {"speaker": "林岚", "say": "早上好。"},
		"causedByEventIds": ["public-cause-1"],
		"time": {"day": 1, "clock": "09:11", "period": "上午"},
	})
	town_log = service.get_view_model("town_log")
	_expect_equal(
		int(town_log.get("revision", -1)),
		event_revision,
		"duplicate broadcast delivery does not create a late revision",
	)
	world.world_revision_changed.emit(world.revision - 1)
	_expect_equal(
		int(service.get_view_model("town_log").get("revision", -1)),
		event_revision,
		"late authoritative World revision is discarded",
	)
	_expect(
		bool(service.dispatch("town_log.refresh_newer").get("ok", false)),
		"new archive records refresh on explicit player action",
	)
	_expect(
		bool(service.dispatch("town_log.set_filter", {"key": "kindTag", "value": "conversation"}).get("ok", false)),
		"world log type filter is handled by the archive query",
	)
	town_log = service.get_view_model("town_log")
	var log_rows := (town_log.get("data", {}) as Dictionary).get("rows", []) as Array
	_expect_equal(log_rows.size(), 1, "conversation filter returns one merged thread")
	var conversation_thread_id := (
		String((log_rows[0] as Dictionary).get("threadId", ""))
		if not log_rows.is_empty()
		else ""
	)
	_expect(
		bool(service.dispatch("town_log.select_thread", {"threadId": conversation_thread_id}).get("ok", false)),
		"world log opens a complete thread detail",
	)
	town_log = service.get_view_model("town_log")
	var town_log_data := town_log.get("data", {}) as Dictionary
	_expect_equal(
		((((town_log_data.get("detail", {}) as Dictionary).get("records", [])) as Array).size()),
		1,
		"conversation detail retains the original dialogue line",
	)
	# Reproduce the production sequence: the page can cache the outdoor
	# snapshot before the runtime finishes entering an interior.
	runtime.interior_active = false
	service.refresh("indoor")
	runtime.interior_active = true
	runtime.observed_place_changed.emit({
		"transitionKind": "enter_observer_interior",
	})
	var indoor := service.get_view_model("indoor")
	_expect_equal(indoor.get("status"), "ready", "active formal interior is projected")
	_expect_equal(indoor.get("formalReady"), true, "indoor page uses the formal runtime")
	_expect_equal(
		indoor.get("error"),
		null,
		"successful indoor projection uses the no-error null envelope",
	)
	var indoor_data := indoor.get("data", {}) as Dictionary
	_expect_equal(
		(indoor_data.get("location", {}) as Dictionary).get("spaceId"),
		"indoor_library",
		"indoor location reads the stable World space ID",
	)
	_expect_equal(
		(indoor_data.get("residentTargets", []) as Array).size(),
		1,
		"indoor resident target comes from the current World place",
	)
	var indoor_resident_targets := (
		indoor_data.get("residentTargets", []) as Array
	)
	if indoor_resident_targets.size() == 1:
		_expect_equal(
			(indoor_resident_targets[0] as Dictionary).get("portraitPath"),
			resident_projection.get("portrait"),
			"indoor resident target projects its current portrait",
		)
	_expect_equal(
		(indoor_data.get("propTargets", []) as Array).size(),
		0,
		"indoor does not expose World props as player action targets",
	)
	_expect_equal(
		(indoor_data.get("eventFocus", {}) as Dictionary).get("active"),
		true,
		"latest public event at the active place is exposed to indoor locating",
	)
	var observation_feed := (
		indoor_data.get("observationFeed", []) as Array
	)
	_expect_equal(
		observation_feed.size(),
		1,
		"indoor exposes the newest public dialogue without treating internal action results as town events",
	)
	var observation_kinds: Array[String] = []
	for observation_value: Variant in observation_feed:
		observation_kinds.append(
			String((observation_value as Dictionary).get("kind", "")),
		)
	_expect(
		observation_kinds.has("dialogue")
		and not observation_kinds.has("action")
		and not observation_kinds.has("important"),
		"indoor observation feed keeps only meaningful public observations",
	)
	_expect(
		not bool(service.dispatch("indoor.focus_event", {"eventId": "event:public-effect-1"}).get("ok", false)),
		"world log no longer creates an indoor map locator side effect",
	)
	_expect(
		not indoor_data.has("interactionPrompts")
		and not (indoor.get("actions", {}) as Dictionary).has(
			"activateInteraction"
		),
		"indoor omits the unfrozen player prop interaction capability",
	)
	_expect_equal(
		((indoor.get("actions", {}) as Dictionary).get("returnOutdoor", {}) as Dictionary).get("enabled"),
		false,
		"avatar mode requires walking to the physical exit",
	)
	_expect(
		bool(service.dispatch("indoor.focus_target", {"residentId": "resident-lin-lan"}).get("ok", false)),
		"indoor resident focus resolves stable ID through the runtime",
	)
	_expect_equal(runtime.selected_name, "林岚", "indoor focus selects the World resident")
	indoor = service.get_view_model("indoor")
	var confirmed_indoor_data := (indoor.get("data", {}) as Dictionary).duplicate(true)
	var confirmed_indoor_revision := int(indoor.get("revision", -1))
	var rejected_indoor := service.dispatch("indoor.focus_target", {"targetId": "resident-missing"})
	_expect(not bool(rejected_indoor.get("ok", true)), "unknown indoor target is rejected")
	indoor = service.get_view_model("indoor")
	_expect_equal(indoor.get("data"), confirmed_indoor_data, "indoor rejection preserves confirmed data")
	_expect_equal(int(indoor.get("revision", -1)), confirmed_indoor_revision, "indoor rejection preserves confirmed revision")
	runtime.player_avatar_enabled = false
	indoor = service.refresh("indoor")
	_expect_equal(
		indoor.get("error"),
		null,
		"observer indoor refresh keeps a valid no-error envelope",
	)
	_expect(
		bool(((indoor.get("actions", {}) as Dictionary).get("returnOutdoor", {}) as Dictionary).get("enabled", false)),
		"observer interior exposes the return-outdoor intent",
	)
	_expect(
		bool(service.dispatch("indoor.return_outdoor", {}).get("ok", false)),
		"observer return uses the non-blocking TownRuntime request interface",
	)
	_expect_equal(runtime.interior_active, false, "observer return leaves the active interior")
	for scope in ["wardrobe"]:
		var disabled_vm := service.get_view_model(scope)
		_expect_equal(disabled_vm.get("status"), "disabled", "%s is honestly disabled" % scope)
		_expect_equal(disabled_vm.get("formalReady"), false, "%s is not marked formal" % scope)
		_expect_equal(disabled_vm.get("source"), "placeholder", "%s is an explicit placeholder" % scope)
		_expect_equal(disabled_vm.get("capabilityMode"), "placeholder", "%s has placeholder capability mode" % scope)
		var navigation_action: String = String({
			"indoor": "returnOutdoor",
			"town_log": "close",
			"wardrobe": "cancel",
		}.get(scope, ""))
		for action_key: Variant in (disabled_vm.get("actions", {}) as Dictionary):
			var action_value: Variant = (
				disabled_vm.get("actions", {}) as Dictionary
			).get(action_key)
			_expect(
				action_value is Dictionary
				and bool((action_value as Dictionary).get("enabled", false))
				== (String(action_key) == navigation_action),
				"%s only exposes host-owned navigation action" % scope,
			)
	var wardrobe_apply := service.dispatch("wardrobe.apply", {})
	_expect(not bool(wardrobe_apply.get("ok", true)), "placeholder wardrobe never reports save success")
	_expect_equal(wardrobe_apply.get("errorCode"), "WARDROBE_INTERFACE_MISSING", "wardrobe has stable missing-interface code")

	var development_bind := service.bind(runtime, world, {
		"worldStartMode": "development",
		"source": "placeholder",
		"capabilityMode": "development",
		"formalReady": false,
		"internalPlaytest": true,
	})
	_expect(bool(development_bind.get("ok", false)), "explicit internal development projection binds")
	var development_weather := service.get_view_model("weather_control")
	_expect_equal(development_weather.get("source"), "runtime", "development weather still uses the live World source")
	_expect_equal(development_weather.get("formalReady"), false, "development weather does not impersonate formal")
	_expect_equal(
		(development_weather.get("data", {}) as Dictionary).get("internalPlaytest"),
		true,
		"explicit internal playtest capability is visible to the page",
	)
	var development_wardrobe := service.get_view_model("wardrobe")
	_expect_equal(development_wardrobe.get("source"), "placeholder", "wardrobe remains placeholder in development")
	_expect_equal(development_wardrobe.get("formalReady"), false, "wardrobe never inherits internal playtest readiness")
	service.set_page_context("resident_detail", {
		"residentId": "resident-lin-lan",
		"selectedTab": "status",
		"open": true,
	})
	var development_detail := service.get_view_model("resident_detail")
	var development_detail_data := (
		development_detail.get("data", {}) as Dictionary
	)
	_expect(
		String(development_detail.get("status", "")) in ["ready", "partial"],
		"confirmed resident detail stays readable before formal model readiness",
	)
	_expect_equal(
		development_detail.get("formalReady"),
		false,
		"development resident detail does not impersonate formal readiness",
	)
	_expect_equal(
		(development_detail_data.get("resident", {}) as Dictionary).get("displayName"),
		"林岚",
		"development resident detail keeps the confirmed World identity",
	)
	_expect_equal(
		(development_detail_data.get("content", {}) as Dictionary).get("availability"),
		"ready",
		"development resident detail projects confirmed World status rows",
	)
	service.set_page_context("resident_action_menu", {
		"residentId": "resident-lin-lan",
		"open": true,
	})
	var development_resident_actions := (
		service.get_view_model("resident_action_menu").get("actions", {})
		as Dictionary
	)
	_expect(
		bool((development_resident_actions.get("openStatus", {}) as Dictionary).get("enabled", false)),
		"resident public detail entry is not blocked by model readiness",
	)
	_expect(
		not bool((development_resident_actions.get("openInner", {}) as Dictionary).get("enabled", true)),
		"model-backed inner observation remains gated until formal readiness",
	)
	world.world_log.call("append_public_event", {
		"eventId": "announcement-focus-event-1",
		"kind": "world_event",
		"time": {"day": 1, "clock": "09:13", "period": "上午"},
		"worldRevision": world.revision,
		"residentId": "",
		"residentName": "",
		"placeName": "",
		"payload": {
			"event_id": "announcement-focus-event-1",
			"type": "公告发布",
			"announcement_id": "announcement-focus-1",
			"publisher_resident_id": "player-avatar",
			"publisher_name": "旅行者",
			"text": "现在到中央广场集合。",
			"time": {"day": 1, "clock": "09:13", "period": "上午"},
		},
	})
	service.set_page_context("town_log", {
		"open": true,
		"threadId": "announcement:announcement-focus-1",
	})
	var focused_log_data := (
		service.get_view_model("town_log").get("data", {}) as Dictionary
	)
	_expect_equal(
		focused_log_data.get("selectedThreadId"),
		"announcement:announcement-focus-1",
		"HUD page context opens the requested announcement thread",
	)
	_expect(
		focused_log_data.get("detail") is Dictionary,
		"HUD page context loads the requested announcement detail",
	)

	service.unbind()
	runtime.free()
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	await process_frame
	await create_timer(0.2).timeout
	_finish()


func _resident_life_meters(service: RefCounted) -> Array:
	var resident_detail: Dictionary = service.get_view_model(
		"resident_detail",
	)
	var data := resident_detail.get("data", {}) as Dictionary
	var content := data.get("content", {}) as Dictionary
	return content.get("lifeMeters", []) as Array


func _assert_page_contracts(service: RefCounted) -> void:
	var bulletin := BULLETIN_PANEL.new()
	_expect(
		(bulletin.call(
			"_validate_complete_view_model",
			service.get_view_model("announcements"),
		) as PackedStringArray).is_empty(),
		"announcements projection satisfies the actual page validator",
	)
	bulletin.free()
	var resident_menu := RESIDENT_MENU.new()
	_expect(
		(resident_menu.call(
			"_validate_snapshot",
			service.get_view_model("resident_action_menu"),
		) as PackedStringArray).is_empty(),
		"resident action projection satisfies the actual page validator",
	)
	resident_menu.free()
	var indoor := INDOOR_OVERLAY.new()
	_expect(
		(indoor.call(
			"_validate_indoor_contract",
			service.get_view_model("indoor"),
		) as PackedStringArray).is_empty(),
		"disabled indoor projection satisfies the actual page validator",
	)
	indoor.free()
func _assert_complete_envelope(view_model: Dictionary, scope: String) -> void:
	for key in ["scope", "status", "revision", "data", "actions", "operation", "error"]:
		_expect(view_model.has(key), "%s envelope contains %s" % [scope, key])
	_expect_equal(view_model.get("scope"), scope, "%s scope is stable" % scope)


func _item_by_id(items: Array, item_id: String) -> Dictionary:
	for value: Variant in items:
		var item := value as Dictionary
		if String(item.get("id", "")) == item_id:
			return item.duplicate(true)
	return {}


func _assert_announcement_contract(view_model: Dictionary) -> void:
	var data := view_model.get("data", {}) as Dictionary
	for key in ["capabilityMode", "source", "formalReady", "panel", "items", "emptyState", "composer", "dialog", "feedback"]:
		_expect(data.has(key), "announcements data contains %s" % key)
	for key in ["openComposer", "updateDraft", "publish", "requestClose", "continueEditing", "discardDraft", "retry", "dismissFeedback"]:
		_expect((view_model.get("actions", {}) as Dictionary).get(key) is Dictionary, "announcements action contains %s" % key)


func _assert_town_log_contract(view_model: Dictionary) -> void:
	var data := view_model.get("data", {}) as Dictionary
	for key in ["capabilityMode", "source", "formalReady", "panel", "state", "errorCode", "summary", "entryPoint", "filters", "filterOptions", "rows", "selectedThreadId", "detail", "detailPaging", "paging"]:
		_expect(data.has(key), "town_log data contains %s" % key)
	for key in ["open", "close", "setFilter", "toggleUnread", "selectThread", "backToList", "loadMore", "loadMoreDetail", "refreshNewer", "retry"]:
		_expect((view_model.get("actions", {}) as Dictionary).get(key) is Dictionary, "town_log action contains %s" % key)
	_expect(not data.has("expandedCausalChain"), "town_log no longer exposes causal UI")
	_expect(not data.has("compactCard"), "town_log no longer exposes compact causal cards")


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s: expected %s, got %s" % [message, expected, actual])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TOWN_UI_PAGE_PROJECTION_SERVICE_PASS")
		quit(0)
		return
	for failure in _failures:
		printerr("TOWN_UI_PAGE_PROJECTION_SERVICE_FAIL: %s" % failure)
	quit(1)
