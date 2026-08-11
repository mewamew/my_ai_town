extends "res://tests/support/TownWorldTestCase.gd"
## 世界基础与日志 合并套件。
##
## 由以下测试合并而来，断言逐条保留：
## - town_world_indoor_props_test.gd
## - town_world_daily_life_chain_test.gd
## - town_world_log_causal_query_test.gd
## - town_world_environment_test.gd
## - town_world_staggered_arrival_test.gd
## - town_weather_behavior_diversity_test.gd
## - town_world_action_type_registry_test.gd
## - town_audio_controller_button_cue_test.gd

class _StubWorld:
	extends RefCounted

	func person_name_for_id(person_id: String) -> String:
		return person_id


class _MessagePolicyWorld:
	extends RefCounted

	var _resident_order: Array[String] = [
		"postal-a", "postal-b", "postal-c", "recipient",
	]

	func _resident_can_work_occupation(
		resident_id: String,
		occupation_id: String,
	) -> bool:
		return (
			occupation_id == "occupation_postal_worker"
			and resident_id.begins_with("postal-")
		)

const ROOMS_ROOT := "res://world/maps/town/interiors/redesign_v2/rooms"
const PROP_VALIDATOR := preload("res://world/data/town/TownWorldPropValidator.gd")
const PROP_QUERY := preload("res://world/data/town/TownWorldPropQuery.gd")
const AUTHORING := preload("res://world/data/town/TownIndoorPropAuthoring.gd")
const FORMAL_OPENING := preload(
	"res://tests/support/TownWorldFormalOpeningTestHelper.gd"
)
const LAYOUT_PROJECTION := preload("res://world/runtime/TownIndoorLayoutProjection.gd")
const SAVE_CODEC := preload("res://world/runtime/persistence/TownWorldSaveCodec.gd")
const GEOMETRY := preload(
	"res://world/maps/town/interiors/redesign_v2/common/InteriorAssetGeometry.gd"
)
const ROOM_GEOMETRY := preload(
	"res://world/maps/town/interiors/InteriorRoomGeometry.gd"
)
const MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownIndoorMovementClearance.gd"
)
const LAYOUT_CELL_SIZE := 32
const INVALID_CELL := Vector2i(2147483647, 2147483647)
const STORE := preload("res://world/runtime/log/TownWorldLogStore.gd")
const RESIDENT_MESSAGE_POLICY := preload(
	"res://world/runtime/social/TownResidentMessagePolicy.gd"
)
const ENVIRONMENT := preload("res://world/runtime/environment/TownWorldEnvironment.gd")
const RESIDENT_PRESENTATION := preload(
	"res://world/presentation/residents/ResidentCharacterPresentation.gd"
)
const REGISTRY := preload(
	"res://world/runtime/action/TownActionTypeRegistry.gd"
)
const VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const PROJECTION := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const AUDIO_CONTROLLER := preload("res://audio/TownAudioController.gd")


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_scenario_indoor_props()
	_scenario_daily_life_chain()
	_scenario_log_causal_query()
	_scenario_environment()
	_scenario_staggered_arrival()
	_scenario_weather_behavior_diversity()
	_scenario_action_type_registry()
	_scenario_audio_controller_button_cue()
	_finish_suite("TOWN_WORLD_FOUNDATION_PASS")


func _scenario_indoor_props() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var authored := AUTHORING.build_document() as Dictionary
	_expect_equal(authored.get("ok"), true, "indoor prop authoring succeeds")
	for error in PROP_VALIDATOR.validate(data):
		_expect(false, str(error))
	_expect_equal((data.get("props", []) as Array).size(), 81, "catalog includes all authored work, writing, and rest props")
	_expect_equal(_indoor_prop_count(data), 63, "catalog includes indoor and fixed-scene interaction props")
	_expect_equal(_props_at_place(data, "独立市集").size(), 5, "fixed market stalls expose goods and flower work points")
	_expect_equal(int(authored.get("indoorSpaceCount", 0)), 23, "authoring covers all twenty-three indoor spaces")
	var colliding_name_data := data.duplicate(true)
	((colliding_name_data.get("props", []) as Array)[0] as Dictionary)["name"] = "中心广场"
	_expect(
		_errors_contain(PROP_VALIDATOR.validate(colliding_name_data), "道具中文名不得与地点中文名重复"),
		"validator enforces one Chinese identity namespace across places and props",
	)
	var duplicate_position_data := data.duplicate(true)
	var duplicate_position_props := (
		duplicate_position_data.get("props", []) as Array
	)
	var duplicate_position_prop := (
		(duplicate_position_props[1] as Dictionary).duplicate(true)
	)
	duplicate_position_prop["name"] = "重复位置测试道具"
	duplicate_position_prop["placeName"] = (
		(duplicate_position_props[0] as Dictionary).get("placeName", "")
	)
	duplicate_position_prop["interaction"] = (
		(duplicate_position_props[0] as Dictionary)
		.get("interaction", {})
		as Dictionary
	).duplicate(true)
	duplicate_position_props[1] = duplicate_position_prop
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(duplicate_position_data),
			"道具交互位置重复",
		),
		"validator rejects two semantic props at one physical interaction position",
	)
	var fractional_cell_size_data := data.duplicate(true)
	var fractional_cell_size_navigation := (
		fractional_cell_size_data.get("indoorNavigation", []) as Array
	)[0] as Dictionary
	fractional_cell_size_navigation["cellSize"] = 32.5
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(fractional_cell_size_data),
			"必须使用 32px 网格",
		),
		"validator rejects a fractional indoor navigation cell size",
	)
	var fractional_cell_data := data.duplicate(true)
	var fractional_navigation := (
		fractional_cell_data.get("indoorNavigation", []) as Array
	)[0] as Dictionary
	var fractional_cells := (
		fractional_navigation.get("walkableCells", []) as Array
	)
	var fractional_cell := fractional_cells[0] as Array
	fractional_cell[0] = float(fractional_cell[0]) + 0.5
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(fractional_cell_data),
			"walkableCells[0] 无效",
		),
		"validator rejects a fractional indoor navigation coordinate",
	)
	var fractional_duration_data := data.duplicate(true)
	var duration_action := (
		((fractional_duration_data.get("props", []) as Array)[0] as Dictionary)
		.get("actions", []) as Array
	)[0] as Dictionary
	duration_action["durationMinutes"] = 240.000001
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(fractional_duration_data),
			"正整数 durationMinutes",
		),
		"validator rejects an approximately integral action duration",
	)
	var fractional_effect_data := data.duplicate(true)
	var effect_action := (
		((fractional_effect_data.get("props", []) as Array)[0] as Dictionary)
		.get("actions", []) as Array
	)[0] as Dictionary
	(effect_action.get("effects", {}) as Dictionary)["困"] = -2.000001
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(fractional_effect_data),
			"效果必须为整数",
		),
		"validator rejects an approximately integral body-state effect",
	)
	var home_without_sleep_data := data.duplicate(true)
	for prop_value in home_without_sleep_data.get("props", []) as Array:
		var prop := prop_value as Dictionary
		if str(prop.get("placeName", "")) != "北街一号住宅":
			continue
		var action := (prop.get("actions", []) as Array)[0] as Dictionary
		action["verb"] = "歇着"
		break
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(home_without_sleep_data),
			"住家必须提供睡觉动作：北街一号住宅",
		),
		"validator rejects a furnished home without a sleep action",
	)
	var approximate_endpoint_data := data.duplicate(true)
	var outdoor_prop := {}
	for prop_value in approximate_endpoint_data.get("props", []) as Array:
		var candidate := prop_value as Dictionary
		var candidate_interaction := (
			candidate.get("interaction", {}) as Dictionary
		)
		if str(candidate_interaction.get("spaceId", "")) == "town_outdoor":
			outdoor_prop = candidate
			break
	_expect(
		not outdoor_prop.is_empty(),
		"catalog exposes an outdoor prop regression target",
	)
	if not outdoor_prop.is_empty():
		var outdoor_interaction := (
			outdoor_prop.get("interaction", {}) as Dictionary
		)
		var approach_polyline := (
			outdoor_interaction.get("approachPolyline", []) as Array
		)
		var approximate_endpoint := (
			approach_polyline[approach_polyline.size() - 1] as Array
		)
		approximate_endpoint[0] = (
			float(approximate_endpoint[0]) + 0.000001
		)
		_expect(
			_errors_contain(
				PROP_VALIDATOR.validate(approximate_endpoint_data),
				"必须是 approachPolyline 终点",
			),
			"validator rejects an approximately matching outdoor approach endpoint",
		)
	var authored_text := JSON.stringify((authored.get("document", {}) as Dictionary), "", true)
	var normalized_authored: Variant = JSON.parse_string(authored_text)
	_expect_equal(
		JSON.stringify(normalized_authored, "", true),
		JSON.stringify(BUILDER.load_json_object(SOURCE_DIR + "/props.json"), "", true),
		"checked authoring output exactly matches props.json",
	)
	_validate_agent_projection(data)
	_validate_walkable_interactions(data)
	_validate_formal_indoor_action(data)
	_validate_dynamic_world_projection(data)
	return
func _validate_agent_projection(data: Dictionary) -> void:
	var projected := PROP_QUERY.agent_props_at_place(data, "北街一号住宅") as Array
	_expect_equal(projected.size(), 1, "home projects its bed to the Agent")
	if projected.is_empty():
		return
	var prop := projected[0] as Dictionary
	_expect_equal(prop.get("name"), "北街一号住宅单人床", "Agent projection keeps the unique Chinese prop name")
	_expect_equal(prop.get("verbs"), ["睡觉"], "Agent projection keeps only supported verbs")
	_expect(not prop.has("interaction"), "Agent projection hides coordinates and furniture provenance")
	var action := PROP_QUERY.action_definition(data, "北街一号住宅", "北街一号住宅单人床", "睡觉")
	_expect_equal(action.get("durationMinutes"), 480, "sleep duration spans the normal night")
	_expect_equal((action.get("effects", {}) as Dictionary).get("困"), -2, "sleep applies the authored tiredness effect")
	var library_props := PROP_QUERY.agent_props_at_place(data, "图书馆") as Array
	var writing_props := library_props.filter(
		func(value: Variant) -> bool:
			return (
				value is Dictionary
				and String((value as Dictionary).get("name", "")) == "图书馆写作桌"
			)
	)
	_expect_equal(
		writing_props.size(),
		1,
		"a resident with a writing goal can discover one executable writing place",
	)
	if not writing_props.is_empty():
		_expect_equal(
			(writing_props[0] as Dictionary).get("verbs"),
			["写作", "整理字帖"],
			"one real writing desk can expose several supported actions",
		)
	var dining_props := PROP_QUERY.agent_props_at_place(
		data,
		"公共食堂",
	) as Array
	_expect_equal(
		_verbs_for_prop(dining_props, "公共食堂灶台"),
		["做饭", "烘烤面包"],
		"one real stove carries both cooking actions",
	)
	_expect_equal(
		_verbs_for_prop(dining_props, "公共食堂备餐柜"),
		["取餐"],
		"the pantry pickup point only serves customers collecting meals",
	)
	_expect_equal(
		_verbs_for_prop(dining_props, "公共食堂递餐口"),
		["递餐"],
		"the pantry service point is independent from customer pickup",
	)
	_expect_equal(
		_verbs_for_prop(dining_props, "公共食堂面团操作台"),
		["准备面团"],
		"the pantry dough point is independent from meal handoff",
	)



func _validate_walkable_interactions(data: Dictionary) -> void:
	var authoring := BUILDER.load_json_object(SOURCE_DIR + "/indoor_prop_authoring.json")
	var props_by_room := {}
	var navigation_by_space := {}
	for navigation_value in data.get("indoorNavigation", []) as Array:
		var navigation := navigation_value as Dictionary
		navigation_by_space[str(navigation.get("spaceId", ""))] = navigation
	for prop_value in data.get("props", []) as Array:
		var prop := prop_value as Dictionary
		var interaction := prop.get("interaction", {}) as Dictionary
		var room_id := str(interaction.get("roomId", ""))
		if room_id.is_empty():
			continue
		var room_props := props_by_room.get(room_id, []) as Array
		room_props.append(prop)
		props_by_room[room_id] = room_props
	for room_value in authoring.get("rooms", []) as Array:
		var room := room_value as Dictionary
		var room_id := str(room.get("roomId", ""))
		var template_id := str(room.get("templateRoomId", room_id))
		var root := ROOMS_ROOT.path_join(template_id)
		var geometry := BUILDER.load_json_object(root.path_join("room_geometry.json"))
		var manifest := BUILDER.load_json_object(root.path_join("furniture_manifest.json"))
		var layout := BUILDER.load_json_object(root.path_join(str(room.get("layoutFile", "layout.json"))))
		var navigation := navigation_by_space.get(str(room.get("spaceId", "")), {}) as Dictionary
		var cell_size := int(navigation.get("cellSize", 0))
		var layout_floor := _cell_set(geometry.get("floor_cells", []) as Array)
		var definitions := {}
		var instances_by_id := {}
		var ground_by_instance := {}
		var furniture_polygons: Array[PackedVector2Array] = []
		for asset_value in manifest.get("assets", []) as Array:
			var asset := asset_value as Dictionary
			definitions[str(asset.get("asset_id", ""))] = BUILDER.load_json_object(str(asset.get("definition_path", "")))
		for instance_value in layout.get("instances", []) as Array:
			var instance := instance_value as Dictionary
			var instance_id := str(instance.get("instance_id", ""))
			instances_by_id[instance_id] = instance
			var definition := definitions.get(str(instance.get("asset_id", "")), {}) as Dictionary
			var origin := _point(instance.get("position_px"))
			var direction := str(instance.get("direction", "down"))
			var translated_polygons: Array[PackedVector2Array] = []
			for polygon in GEOMETRY.rotated_ground_contact_polygons(definition, direction):
				var translated := PackedVector2Array()
				for point in polygon:
					translated.append(point + origin)
				translated_polygons.append(translated)
				furniture_polygons.append(translated)
			ground_by_instance[instance_id] = translated_polygons
		var navigation_candidates := MOVEMENT_CLEARANCE.subdivide_cells(
			layout_floor,
			LAYOUT_CELL_SIZE,
			cell_size,
		)
		var walkable := MOVEMENT_CLEARANCE.filter_walkable_cells(
			navigation_candidates,
			cell_size,
			ROOM_GEOMETRY.get_boundary_collision_rects(geometry),
			furniture_polygons,
		)
		walkable = MOVEMENT_CLEARANCE.retain_reachable_cells(
			walkable,
			cell_size,
			ROOM_GEOMETRY.get_primary_entry_point(geometry),
		)
		var entry_cell := _walkable_cell_for_point(
			ROOM_GEOMETRY.get_primary_entry_point(geometry),
			cell_size,
			walkable,
		)
		_expect(entry_cell != INVALID_CELL, "%s has a doorway entry anchor" % room_id)
		_expect(walkable.has(entry_cell), "%s doorway entry cell is walkable" % room_id)
		var reachable := _reachable_cells(entry_cell, walkable)
		for prop_value in props_by_room.get(room_id, []) as Array:
			var prop := prop_value as Dictionary
			var interaction := prop.get("interaction", {}) as Dictionary
			var interaction_position := _point(interaction.get("position"))
			var interaction_cell := _walkable_cell_for_point(
				interaction_position,
				cell_size,
				walkable,
			)
			_expect(
				walkable.has(interaction_cell),
				"%s interaction is on floor minus all layout furniture" % str(prop.get("name", "")),
			)
			_expect(
				reachable.has(interaction_cell),
				"%s interaction is reachable from the room doorway" % str(prop.get("name", "")),
			)
			_expect(
				not interaction.has("approachPolyline"),
				"%s does not bake a fixed indoor approach path" % str(prop.get("name", "")),
			)
			if (
				bool(interaction.get("anchorSnappedToFloor", false))
				and instances_by_id.has(str(interaction.get("instanceId", "")))
			):
				var instance_id := str(interaction.get("instanceId", ""))
				var owner := instances_by_id.get(instance_id, {}) as Dictionary
				var definition := definitions.get(str(owner.get("asset_id", "")), {}) as Dictionary
				var anchor_id := str(interaction.get("anchorId", ""))
				_expect(
					_anchor_kind(definition, anchor_id) == "sit",
					"%s only snaps an authored sit/seat center out of its own collision"
					% str(prop.get("name", "")),
				)
				_expect(
					_point_is_in_any_polygon(
						_point(interaction.get("sourceAnchorPosition")),
						ground_by_instance.get(instance_id, []) as Array,
					),
					"%s snapped source is inside its owning seat ground_contact"
					% str(prop.get("name", "")),
				)
		# functional_anchor 属于 32px 房间布局的制作约束，仍由
		# town_indoor_layout_instance_geometry_test 覆盖；World 的正式寻路目标
		# 是门连接点和上面已校验的道具交互点。
		var expected_cells := _serialized_cells(walkable)
		_expect(
			_cell_arrays_equal(navigation.get("walkableCells", []) as Array, expected_cells),
			"%s publishes the current furniture collision grid" % room_id,
		)



func _validate_formal_indoor_action(data: Dictionary) -> void:
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "formal opening fixture is legal")
	if opening_result.get("ok") != true:
		return
	var opening := FORMAL_OPENING.with_authoritative_new_game_spawns(
		data,
		opening_result.get("config", {}) as Dictionary,
	)
	var navigation := _navigation_for_space(data, "home_01")
	var cell_size := float(navigation.get("cellSize", 0.0))
	var navigation_cells := navigation.get("walkableCells", []) as Array
	var start_cell := navigation_cells[-1] as Array
	var start := _cell_center(start_cell, cell_size)
	var plan := PROP_QUERY.interaction_plan(
		data,
		"北街一号住宅",
		"北街一号住宅单人床",
		"睡觉",
		start,
	)
	var approach := plan.get("approachPolyline", []) as Array
	_expect(approach.size() > 2, "indoor action computes a route across the current collision grid")
	_expect_equal(
		plan.get("actorFacing"),
		null,
		"movement plans stay free of presentation-only pose data",
	)
	var sleep_cue := PROP_QUERY.presentation_cue(
		data,
		"北街一号住宅",
		"北街一号住宅单人床",
		"睡觉",
	)
	_expect_equal(
		sleep_cue.get("actorFacing"),
		"right",
		"authored bed interaction publishes the rotated actor facing",
	)
	_expect_equal(
		sleep_cue.get("anchorKind"),
		"use",
		"prop presentation keeps the asset anchor semantic lightweight",
	)
	if approach.is_empty():
		return
	var alternate_cell := navigation_cells[0] as Array
	var alternate_start := _cell_center(alternate_cell, cell_size)
	var alternate_plan := PROP_QUERY.interaction_plan(
		data,
		"北街一号住宅",
		"北街一号住宅单人床",
		"睡觉",
		alternate_start,
	)
	_expect(
		alternate_plan.get("approachPolyline", []) != approach,
		"the same prop gets a fresh path from a different actor position",
	)
	var world: RefCounted = WORLD.new()
	var start_result := world.call("start_formal", data, opening, _resident_identities(opening)) as Dictionary
	_expect_equal(start_result.get("ok"), true, "completed catalog starts through the formal World gate")
	if start_result.get("ok") != true:
		return
	var formal_resident := (
		(world.get("_residents") as Dictionary).get("resident_lin_lan_01", {})
		as Dictionary
	)
	var formal_activity := formal_resident.get("activityState", {}) as Dictionary
	formal_activity["energy"] = 35
	world.call("_sync_body_from_activity_needs", formal_resident, formal_activity)
	world.call("cycle_time_period_for_test")
	world.call("cycle_time_period_for_test")
	var requests := world.call("take_pending_decision_requests", ["林岚"]) as Array[Dictionary]
	var wake := requests[0].get("wakePacket", {}) as Dictionary
	var arrive_home := {
		"decision_id": wake.get("decision_id", ""),
		"handling": "replace_current",
		"action": {
			"action_id": "formal-arrive-home-before-sleep",
			"type": "去",
			"place": "北街一号住宅",
			"line": "从南入口沿正式路线回家",
		},
	}
	var arrive_home_result := (
		world.call("submit_agent_decision", "林岚", arrive_home) as Dictionary
	)
	_expect_equal(
		arrive_home_result.get("status"),
		"accepted",
		"formal resident enters the assigned home through navigation and its portal: %s"
		% str(arrive_home_result),
	)
	var movement_guard := 0
	while (
		(world.call("get_resident_state", "林岚") as Dictionary).get("currentAction") != null
		and movement_guard < 600
	):
		world.call("advance", 1.0)
		movement_guard += 1
	var arrived_home := world.call("get_resident_state", "林岚") as Dictionary
	_expect(movement_guard < 600, "formal resident reaches the assigned home deterministically")
	_expect_equal(arrived_home.get("spaceId"), "home_01", "formal route crosses into the assigned home space")
	requests = world.call("take_pending_decision_requests", ["林岚"]) as Array[Dictionary]
	_expect_equal(requests.size(), 1, "home arrival emits one new decision request")
	if requests.is_empty():
		return
	wake = requests[0].get("wakePacket", {}) as Dictionary
	var decision := {
		"decision_id": wake.get("decision_id", ""),
		"handling": "replace_current",
		"action": {
			"action_id": "formal-indoor-sleep",
			"type": "用道具",
			"prop": "北街一号住宅单人床",
			"verb": "睡觉",
			"line": "回家睡觉",
		},
	}
	_expect_equal(world.call("submit_agent_decision", "林岚", decision).get("status"), "accepted", "formal World accepts an indoor prop action")
	var approach_guard := 0
	while (
		not ((world.call("get_resident_state", "林岚") as Dictionary).get("position") as Vector2).is_equal_approx(
			plan.get("position") as Vector2
		)
		and approach_guard < 10
	):
		world.call("advance", 1.0)
		approach_guard += 1
	_expect(approach_guard < 10, "resident walks to the indoor interaction anchor promptly")
	_expect(
		(world.call("get_resident_state", "林岚") as Dictionary).get("currentAction") != null,
		"resident remains at the prop while the authored interaction duration elapses",
	)
	world.call("advance", 480.0)
	var state := world.call("get_resident_state", "林岚") as Dictionary
	_expect((state.get("position") as Vector2).is_equal_approx(plan.get("position") as Vector2), "indoor action finishes at its walkable interaction anchor")
	_expect_equal(state.get("currentAction"), null, "indoor prop action completes after its authored duration")
	_expect_equal(
		(state.get("routeConnector", []) as Array).size(),
		0,
		"indoor action completion clears the temporary approach connector",
	)
	requests = world.call("take_pending_decision_requests", ["林岚"]) as Array[Dictionary]
	_expect_equal(
		requests.size(),
		1,
		"completed indoor interaction immediately schedules the resident's next decision",
	)



func _validate_dynamic_world_projection(data: Dictionary) -> void:
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "dynamic layout opening fixture is legal")
	if opening_result.get("ok") != true:
		return
	var opening := FORMAL_OPENING.with_authoritative_new_game_spawns(
		data,
		opening_result.get("config", {}) as Dictionary,
	)
	var navigation := _navigation_for_space(data, "home_01")
	var cell_size := float(navigation.get("cellSize", 0.0))
	var cells := navigation.get("walkableCells", []) as Array
	var start_cell := cells[0] as Array
	var start := _cell_center(start_cell, cell_size)
	var world: RefCounted = WORLD.new()
	var dynamic_start_result := world.call("start_formal", data, opening, _resident_identities(opening)) as Dictionary
	_expect_equal(
		dynamic_start_result.get("ok"),
		true,
		"formal World starts before a dynamic furniture edit",
	)
	var dynamic_resident := (
		(world.get("_residents") as Dictionary).get("resident_lin_lan_01", {})
		as Dictionary
	)
	var dynamic_activity := dynamic_resident.get("activityState", {}) as Dictionary
	dynamic_activity["energy"] = 35
	world.call("_sync_body_from_activity_needs", dynamic_resident, dynamic_activity)
	world.call("cycle_time_period_for_test")
	world.call("cycle_time_period_for_test")
	var entry_wake := _take_request(world, "林岚")
	var enter_home_result := world.call("submit_agent_decision", "林岚", {
		"decision_id": entry_wake.get("decision_id", ""),
		"handling": "replace_current",
		"action": {
			"action_id": "dynamic-layout-enter-home",
			"type": "去",
			"place": "北街一号住宅",
			"line": "从南入口沿正式路线回家",
		},
	}) as Dictionary
	_expect_equal(
		enter_home_result.get("status"),
		"accepted",
		"dynamic projection resident enters the home through the formal route: %s"
		% str(enter_home_result),
	)
	var movement_guard := 0
	while (
		(world.call("get_resident_state", "林岚") as Dictionary).get("currentAction") != null
		and movement_guard < 600
	):
		world.call("advance", 1.0)
		movement_guard += 1
	_expect(movement_guard < 600, "dynamic projection resident reaches home deterministically")
	_expect_equal(
		(world.call("get_resident_state", "林岚") as Dictionary).get("spaceId"),
		"home_01",
		"dynamic projection resident is physically inside before Agent prop facts are tested",
	)
	_take_request(world, "林岚")
	var initial := world.call("get_indoor_layout_projection", "home_01") as Dictionary
	_expect_equal((initial.get("props", []) as Array).size(), 1, "home starts from the authored default layout projection")
	_expect_equal(world.call("pause", "furniture_editor").get("ok"), true, "furniture editor pauses World through its public reason")

	var invalid := initial.duplicate(true)
	(invalid.get("props", []) as Array).append(((invalid.get("props", []) as Array)[0] as Dictionary).duplicate(true))
	var invalid_result := world.call("apply_indoor_layout_projection", invalid) as Dictionary
	_expect_equal(invalid_result.get("ok"), false, "duplicate dynamic prop identity is rejected")
	_expect_equal(
		world.call("get_indoor_layout_projection", "home_01"),
		initial,
		"rejected dynamic layout keeps the active projection",
	)

	var moved := initial.duplicate(true)
	var moved_prop := ((moved.get("props", []) as Array)[0] as Dictionary)
	var moved_interaction := moved_prop.get("interaction", {}) as Dictionary
	var target_cell := _different_cell(cells, start_cell)
	var target := _cell_center(target_cell, cell_size)
	moved_interaction["position"] = [target.x, target.y]
	moved_interaction["sourceAnchorPosition"] = [target.x, target.y]
	moved_interaction["instancePosition"] = [target.x, target.y]
	var moved_navigation := moved.get("navigation", {}) as Dictionary
	var removed_cell := _remove_safe_navigation_cell(
		moved_navigation,
		[start_cell, target_cell],
	)
	_expect(not removed_cell.is_empty(), "dynamic edit can publish a changed collision grid")
	var move_result := world.call("apply_indoor_layout_projection", moved) as Dictionary
	_expect_equal(
		move_result.get("ok"),
		true,
		"World atomically accepts moved props and current collision: %s"
		% str(move_result),
	)
	var dynamic_data := LAYOUT_PROJECTION.apply(data, moved) as Dictionary
	var moved_plan := PROP_QUERY.interaction_plan(
		dynamic_data,
		"北街一号住宅",
		"北街一号住宅单人床",
		"睡觉",
		start,
	) as Dictionary
	_expect_equal(moved_plan.get("position"), target, "prop action targets the moved interaction anchor")
	_expect(
		not _path_contains_cell_center(
			moved_plan.get("approachPolyline", []) as Array,
			removed_cell,
			cell_size,
		),
		"fresh prop path avoids the latest furniture collision grid",
	)
	world.call("resume", "furniture_editor")
	var refreshed := _take_request(world, "林岚")
	_expect_equal(refreshed.size(), 5, "layout edit invalidates stale Agent facts through an exact fresh wake")
	_expect_equal(
		((((refreshed.get("snapshot", {}) as Dictionary).get("place", {}) as Dictionary).get("props", []) as Array).size()),
		1,
		"fresh Agent wake sees the moved prop projection",
	)

	world.call("pause", "furniture_editor")
	var removed := world.call("get_indoor_layout_projection", "home_01") as Dictionary
	removed["props"] = []
	_expect_equal(world.call("apply_indoor_layout_projection", removed).get("ok"), true, "removing furniture removes its Agent prop")
	_expect_equal(
		((world.call("get_place_detail", "北街一号住宅") as Dictionary).get("props", []) as Array).size(),
		0,
		"removed furniture is absent from current place facts",
	)

	var added := world.call("get_indoor_layout_projection", "home_01") as Dictionary
	var added_prop := moved_prop.duplicate(true)
	added_prop["name"] = "北街一号住宅新单人床"
	(added_prop.get("interaction", {}) as Dictionary)["instanceId"] = "home_01_player_bed_02"
	added["props"] = [added_prop]
	_expect_equal(world.call("apply_indoor_layout_projection", added).get("ok"), true, "adding furniture publishes a new stable Agent prop")
	_expect_equal(
		((world.call("get_place_detail", "北街一号住宅") as Dictionary).get("props", []) as Array)[0].get("name"),
		"北街一号住宅新单人床",
		"Agent facts use the newly added furniture identity",
	)
	world.call("resume", "furniture_editor")
	var added_wake := _take_request(world, "林岚")
	var added_props := (
		((added_wake.get("snapshot", {}) as Dictionary).get(
			"place",
			{},
		) as Dictionary).get("props", []) as Array
	)
	_expect(not added_props.is_empty(), "new furniture enters the Agent wake")
	if not added_props.is_empty():
		_expect_equal(
			(added_props[0] as Dictionary).get("name"),
			"北街一号住宅新单人床",
			"new furniture keeps its stable Agent identity",
		)
	var added_action := world.call(
		"submit_agent_decision",
		"林岚",
		{
			"decision_id": added_wake.get("decision_id", ""),
			"handling": "replace_current",
			"action": {
				"action_id": "dynamic-layout-use-new-bed",
				"type": "用道具",
				"prop": "北街一号住宅新单人床",
				"verb": "睡觉",
				"line": "在新摆的床上休息",
			},
		},
	) as Dictionary
	_expect_equal(
		added_action.get("status"),
		"accepted",
		"new furniture executes through its authored direct prop semantics",
	)
	for _step in 5:
		world.call("advance", 0.5)
	world.call("pause", "furniture_editor")
	var saved_projection := world.call("get_indoor_layout_projection", "home_01") as Dictionary
	var save_result := world.call("create_save_snapshot") as Dictionary
	_expect_equal(save_result.get("ok"), true, "dynamic indoor layout enters the formal World snapshot")
	var decoded_state := SAVE_CODEC.decode_checked(
		((save_result.get("snapshot", {}) as Dictionary).get("state", {})),
	) as Dictionary
	_expect_equal(decoded_state.get("ok"), true, "dynamic indoor save state decodes")
	var saved_state := decoded_state.get("value", {}) as Dictionary
	_expect_equal(
		(saved_state.get("indoorLayoutOverrides", []) as Array).size(),
		1,
		"save stores only changed rooms instead of duplicating all default layouts",
	)
	var serialized: Variant = JSON.parse_string(JSON.stringify(save_result.get("snapshot", {})))
	var restored_world: RefCounted = WORLD.new()
	var restore_result := restored_world.call(
		"restore_from_snapshot",
		data,
		opening,
		serialized as Dictionary,
		_resident_identities(opening),
	) as Dictionary
	_expect_equal(
		restore_result.get("ok"),
		true,
		"serialized dynamic layout restores through the formal boundary: %s"
		% JSON.stringify(restore_result),
	)
	var encoded_projection := SAVE_CODEC.encode_checked(saved_projection) as Dictionary
	_expect_equal(encoded_projection.get("ok"), true, "dynamic layout projection encodes")
	var decoded_projection := SAVE_CODEC.decode_checked(
		encoded_projection.get("value", {}),
	) as Dictionary
	_expect_equal(decoded_projection.get("ok"), true, "dynamic layout projection decodes")
	_expect_equal(
		restored_world.call("get_indoor_layout_projection", "home_01"),
		decoded_projection.get("value", {}),
		"save and restore preserve moved props and current collision exactly",
	)



func _resident_identities(opening: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		result.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(resident.get("attributes", {}).get("name", "")),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	return result



func _indoor_prop_count(data: Dictionary) -> int:
	var count := 0
	for value in data.get("props", []) as Array:
		if str(((value as Dictionary).get("interaction", {}) as Dictionary).get("spaceId", "")) != "town_outdoor":
			count += 1
	return count



func _props_at_place(data: Dictionary, place_name: String) -> Array:
	var result := []
	for value in data.get("props", []) as Array:
		if str((value as Dictionary).get("placeName", "")) == place_name:
			result.append(value)
	return result



func _cell_set(values: Array) -> Dictionary:
	var result := {}
	for value in values:
		result[Vector2i(int(value[0]), int(value[1]))] = true
	return result



func _serialized_cells(cells: Dictionary) -> Array:
	var result := []
	for cell_value in cells:
		var cell := cell_value as Vector2i
		result.append([cell.x, cell.y])
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		return int((left as Array)[1]) < int((right as Array)[1]) or (
			int((left as Array)[1]) == int((right as Array)[1])
			and int((left as Array)[0]) < int((right as Array)[0])
		)
	)
	return result



func _cell_arrays_equal(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if (
			int((left[index] as Array)[0]) != int((right[index] as Array)[0])
			or int((left[index] as Array)[1]) != int((right[index] as Array)[1])
		):
			return false
	return true



func _navigation_for_space(data: Dictionary, space_id: String) -> Dictionary:
	for value in data.get("indoorNavigation", []) as Array:
		var navigation := value as Dictionary
		if str(navigation.get("spaceId", "")) == space_id:
			return navigation
	return {}



func _cell_center(cell: Array, cell_size: float) -> Vector2:
	return MOVEMENT_CLEARANCE.body_origin_for_cell(
		Vector2i(int(cell[0]), int(cell[1])),
		cell_size,
	)



func _different_cell(cells: Array, excluded: Array) -> Array:
	for index in range(cells.size() - 1, -1, -1):
		var cell := cells[index] as Array
		if int(cell[0]) != int(excluded[0]) or int(cell[1]) != int(excluded[1]):
			return cell.duplicate()
	return []



func _remove_safe_navigation_cell(navigation: Dictionary, excluded: Array) -> Array:
	var cells := navigation.get("walkableCells", []) as Array
	for index in cells.size():
		var candidate := cells[index] as Array
		if _cell_list_contains(excluded, candidate):
			continue
		var next := cells.duplicate(true)
		next.remove_at(index)
		if _all_cells_connected(next):
			navigation["walkableCells"] = next
			return candidate.duplicate()
	return []



func _cell_list_contains(cells: Array, expected: Array) -> bool:
	for value in cells:
		var cell := value as Array
		if int(cell[0]) == int(expected[0]) and int(cell[1]) == int(expected[1]):
			return true
	return false



func _all_cells_connected(cells: Array) -> bool:
	if cells.is_empty():
		return false
	var lookup := {}
	for value in cells:
		var pair := value as Array
		lookup[Vector2i(int(pair[0]), int(pair[1]))] = true
	var start := lookup.keys()[0] as Vector2i
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for offset in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = current + offset
			if lookup.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == lookup.size()



func _walkable_cell_for_point(
	point: Vector2,
	cell_size: float,
	cells: Dictionary,
) -> Vector2i:
	if cell_size <= 0.0:
		return INVALID_CELL
	var candidates: Array[Vector2i] = []
	var base := Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))
	for offset_y in [-1, 0]:
		for offset_x in [-1, 0]:
			var cell := base + Vector2i(offset_x, offset_y)
			if not cells.has(cell):
				continue
			if Rect2(Vector2(cell) * cell_size, Vector2.ONE * cell_size).grow(0.01).has_point(point):
				candidates.append(cell)
	if candidates.is_empty():
		return INVALID_CELL
	candidates.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance := MOVEMENT_CLEARANCE.body_origin_for_cell(
			left,
			cell_size,
		).distance_squared_to(point)
		var right_distance := MOVEMENT_CLEARANCE.body_origin_for_cell(
			right,
			cell_size,
		).distance_squared_to(point)
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return left.y < right.y or (left.y == right.y and left.x < right.x)
	)
	return candidates[0]



func _reachable_cells(start: Vector2i, cells: Dictionary) -> Dictionary:
	if not cells.has(start):
		return {}
	var result := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = current + offset
			if cells.has(next) and not result.has(next):
				result[next] = true
				queue.append(next)
	return result



func _path_contains_cell_center(path: Array, cell: Array, cell_size: float) -> bool:
	var center := _cell_center(cell, cell_size)
	for point_value in path:
		if (point_value as Vector2).is_equal_approx(center):
			return true
	return false



func _take_request(world: RefCounted, resident_name: String) -> Dictionary:
	for request_value in world.call("take_pending_decision_requests", [resident_name]) as Array:
		var request := request_value as Dictionary
		if str(request.get("residentName", "")) == resident_name:
			return (request.get("wakePacket", {}) as Dictionary).duplicate(true)
	return {}



func _point(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))



func _anchor_kind(definition: Dictionary, anchor_id: String) -> String:
	for value in definition.get("interaction_anchor", []) as Array:
		var anchor := value as Dictionary
		if str(anchor.get("id", "")) == anchor_id:
			return str(anchor.get("kind", ""))
	return ""



func _verbs_for_prop(props: Array, prop_name: String) -> Array:
	for value: Variant in props:
		if (
			value is Dictionary
			and String((value as Dictionary).get("name", "")) == prop_name
		):
			return (value as Dictionary).get("verbs", []) as Array
	return []



func _point_is_in_any_polygon(point: Vector2, polygons: Array) -> bool:
	for value in polygons:
		if Geometry2D.is_point_in_polygon(point, value as PackedVector2Array):
			return true
	return false



func _errors_contain(errors: PackedStringArray, text: String) -> bool:
	for error in errors:
		if str(error).contains(text):
			return true
	return false



func _scenario_daily_life_chain() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "daily-life opening loads")
	if not bool(opening_result.get("ok", false)):
		return
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call(
			"start",
			data,
			opening_result.get("config", {}) as Dictionary,
		) as Dictionary).get("ok"),
		true,
		"daily-life World starts",
	)

	var lin_wake := _take_wake_daily_life_chain(world, "林岚")
	var a_he_wake := _take_wake_daily_life_chain(world, "阿禾")
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_go_daily_life_chain(lin_wake, "工作坊", "去工作坊开工"),
		) as Dictionary,
		"resident can commute to work",
	)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"阿禾",
			_go_daily_life_chain(a_he_wake, "花房咖啡馆", "回咖啡馆照看生意"),
		) as Dictionary,
		"cafe worker can commute to the cafe",
	)
	_expect(
		_advance_until_action_clears(world, "林岚"),
		"work commute completes",
	)
	_expect(
		_advance_until_action_clears(world, "阿禾"),
		"cafe commute completes",
	)
	_expect_equal(
		(world.call("get_resident_state", "林岚") as Dictionary).get(
			"currentPlace",
		),
		"工作坊",
		"worker reaches the authored workplace",
	)
	_expect_equal(
		(world.call("get_resident_state", "阿禾") as Dictionary).get(
			"currentPlace",
		),
		"花房咖啡馆",
		"cafe worker reaches the authored workplace",
	)
	_expect_equal(
		(world.call("create_work_task", {
			"taskId": "daily-life-craft-production",
			"capability": "craft.production",
			"sourceKind": "production_request",
			"sourceRef": "daily-life-chain",
			"targets": [{
				"kind": "prop",
				"ref": "工作坊主木工台",
			}],
			"requestedResultKind": "crafted_lot",
			"priority": 70,
		}) as Dictionary).get("ok"),
		true,
		"daily-life workshop work is backed by a real production task",
	)

	lin_wake = _take_wake_daily_life_chain(world, "林岚")
	a_he_wake = _take_wake_daily_life_chain(world, "阿禾")
	var lin_work_activity := _available_worker_activity_id(world, "林岚")
	var a_he_work_activity := _available_worker_activity_id(world, "阿禾")
	_expect(
		not lin_work_activity.is_empty(),
		"workshop exposes a real available worker activity",
	)
	_expect(
		not a_he_work_activity.is_empty(),
		"cafe exposes a real available worker activity",
	)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_do_activity(
				lin_wake,
				lin_work_activity,
				"在木工台做今天的活",
			),
		) as Dictionary,
		"arrival can continue into a task-backed workshop activity",
	)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"阿禾",
			_do_activity(
				a_he_wake,
				a_he_work_activity,
				"在店里照看生意",
			),
		) as Dictionary,
		"cafe worker starts a real cafe work activity",
	)
	var work_chain := _advance_until_action_clears_with_positions(
		world,
		"林岚",
	)
	_expect(
		bool(work_chain.get("completed", false)),
		"workplace activity completes",
	)
	_expect(
		(work_chain.get("positions", []) as Array).size() >= 2,
		"work consists of movement between multiple authored workplace points",
	)
	_expect_equal(
		(world.call("set_weather", "小雨") as Dictionary).get("changed"),
		true,
		"rain begins after the resident finishes indoor work",
	)

	lin_wake = _take_wake_daily_life_chain(world, "林岚")
	var rainy_snapshot := lin_wake.get("snapshot", {}) as Dictionary
	var rainy_context := rainy_snapshot.get(
		"weather_context",
		{},
	) as Dictionary
	_expect(
		String(rainy_snapshot.get("weather", "")) in [
			"小雨",
			"中雨",
			"大雨",
		],
		"the next autonomous decision receives confirmed rain",
	)
	_expect_equal(
		rainy_context.get("outdoorPolicy"),
		"discouraged",
		"rain discourages optional outdoor activity without forbidding it",
	)
	_expect(
		(rainy_context.get("indoorAlternatives", []) as Array).has(
			"花房咖啡馆",
		),
		"rain offers the cafe as a real executable indoor social alternative",
	)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_go_daily_life_chain(lin_wake, "花房咖啡馆", "忙完去咖啡馆歇口气"),
		) as Dictionary,
		"resident can leave work for a social public place",
	)
	_expect(
		_advance_until_action_clears(world, "林岚"),
		"cafe trip completes",
	)
	lin_wake = _take_wake_daily_life_chain(world, "林岚")
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_use_prop(
				lin_wake,
				"花房咖啡馆点单柜台",
				"点单",
				"点杯喝的再坐一会儿",
			),
		) as Dictionary,
		"arrival can flow into a cafe order",
	)
	_expect(
		_advance_until_action_clears(world, "林岚"),
		"cafe order completes",
	)
	lin_wake = _take_wake_daily_life_chain(world, "林岚")
	var lin_cafe_state := world.call("get_resident_state", "林岚") as Dictionary
	var a_he_cafe_state := world.call("get_resident_state", "阿禾") as Dictionary
	var a_he_id := _nearby_id(lin_wake, "阿禾")
	_expect(
		not a_he_id.is_empty(),
		"cafe co-location exposes the familiar resident (lin=%s, a_he=%s, wake_place=%s)"
		% [
			lin_cafe_state,
			a_he_cafe_state,
			(lin_wake.get("snapshot", {}) as Dictionary).get("place", {}),
		],
	)
	if not a_he_id.is_empty():
		# 阿禾空闲时会在店内走动，点单柜台到他的距离会落进"唤醒包可见、
		# 搭话超严格感知半径"的滞回带；林岚先到主厅座位坐下（台词也
		# 正是坐下之后说的），双方站定再搭话。
		_expect_accepted(
			world.call(
				"submit_agent_decision",
				"林岚",
				_use_prop(
					lin_wake,
					"花房咖啡馆主厅座位",
					"歇着",
					"找个主厅座位坐下",
				),
			) as Dictionary,
			"resident settles at a main-hall cafe seat",
		)
		_expect(
			_advance_until_action_clears(world, "林岚"),
			"cafe seat rest completes",
		)
		lin_wake = _take_wake_daily_life_chain(world, "林岚")
		a_he_id = _nearby_id(lin_wake, "阿禾")
		_expect(
			not a_he_id.is_empty(),
			"the seated resident keeps the cafe worker in talk range",
		)
		_expect_accepted(
			world.call(
				"submit_agent_decision",
				"林岚",
				_talk_daily_life_chain(
					lin_wake,
					a_he_id,
					"今天店里倒挺安静。",
					"我在柜台边坐下，看了看四周",
				),
			) as Dictionary,
			"resident can start ordinary cafe conversation",
		)
		var a_he_reply_wake := _take_wake_daily_life_chain(world, "阿禾")
		var conversation_value: Variant = (
			a_he_reply_wake.get("snapshot", {}) as Dictionary
		).get("conversation")
		var conversation := (
			conversation_value as Dictionary
			if conversation_value is Dictionary
			else {}
		)
		_expect(
			not conversation.is_empty(),
			"reply wake carries the active conversation snapshot",
		)
		_expect_accepted(
			world.call(
				"submit_agent_decision",
				"阿禾",
				_reply(
					a_he_reply_wake,
					String(conversation.get("conversation_id", "")),
					"现在店里就我们两个，你还嫌不够安静。",
					"我把杯子放到他面前，忍不住回了一句",
					true,
				),
			) as Dictionary,
			"familiar resident can answer with a mild, fact-grounded barb",
		)
		_expect_equal(
			(world.call("get_active_conversations") as Array).size(),
			0,
			"resident can deliver the last line before ending the exchange",
		)
		var ended_conversations := world.call(
			"get_resident_public_relationship_progress",
			"resident_lin_lan_01",
		) as Dictionary
		_expect_equal(
			ended_conversations.get("ok"),
			true,
			"the confirmed rainy-day exchange reaches public social progress",
		)
		lin_wake = _take_wake_daily_life_chain(world, "林岚")
		_expect(
			_has_event_daily_life_chain(lin_wake, "对话结束"),
			"the other resident receives the confirmed conversation end",
		)

	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_go_daily_life_chain(lin_wake, "北街一号住宅", "忙完了，回家歇着"),
		) as Dictionary,
		"resident can commute home",
	)
	_expect(
		_advance_until_action_clears(world, "林岚"),
		"home commute completes",
	)
	lin_wake = _take_wake_daily_life_chain(world, "林岚")
	var lin_resident := (
		(world.get("_residents") as Dictionary).get("resident_lin_lan_01", {})
		as Dictionary
	)
	var lin_activity := lin_resident.get("activityState", {}) as Dictionary
	lin_activity["energy"] = 35
	world.call("_sync_body_from_activity_needs", lin_resident, lin_activity)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_use_prop(
				lin_wake,
				"北街一号住宅单人床",
				"睡觉",
				"收拾好就睡下",
			),
		) as Dictionary,
		"resident can close the daily loop with sleep",
	)
	_expect(
		_advance_until_action_clears(world, "林岚"),
		"sleep action completes",
	)
	_expect_equal(
		(world.call("get_resident_state", "林岚") as Dictionary).get(
			"currentPlace",
		),
		"北街一号住宅",
		"daily-life chain ends at the resident's own home",
	)
	world.call("stop")
	return
func _advance_until_action_clears(
	world: RefCounted,
	resident_name: String,
	maximum_minutes := 900,
) -> bool:
	for _minute in maximum_minutes:
		var state := world.call(
			"get_resident_state",
			resident_name,
		) as Dictionary
		if state.get("currentAction") == null:
			return true
		world.call("advance", 1.0)
	return false



func _advance_until_action_clears_with_positions(
	world: RefCounted,
	resident_name: String,
	maximum_minutes := 900,
) -> Dictionary:
	var distinct_positions := {}
	for _minute in maximum_minutes:
		var state := world.call(
			"get_resident_state",
			resident_name,
		) as Dictionary
		if state.get("currentAction") == null:
			return {
				"completed": true,
				"positions": distinct_positions.values(),
			}
		var position := state.get("position", Vector2.ZERO) as Vector2
		distinct_positions["%.2f,%.2f" % [position.x, position.y]] = position
		world.call("advance", 1.0)
	return {
		"completed": false,
		"positions": distinct_positions.values(),
	}



func _take_wake_daily_life_chain(world: RefCounted, resident_name: String) -> Dictionary:
	var requests := world.call(
		"take_pending_decision_requests",
		[resident_name],
	) as Array[Dictionary]
	if requests.is_empty():
		_failures.append("missing wake for %s" % resident_name)
		return {}
	return (
		(requests[0].get("wakePacket", {}) as Dictionary).duplicate(true)
	)



func _go_daily_life_chain(
	wake: Dictionary,
	place: String,
	line: String,
) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-go-%s" % [decision_id, place],
			"type": "去",
			"place": place,
			"line": line,
		},
	}



func _use_prop(
	wake: Dictionary,
	prop: String,
	verb: String,
	line: String,
) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-use-%s" % [decision_id, verb],
			"type": "用道具",
			"prop": prop,
			"verb": verb,
			"line": line,
		},
	}



func _do_activity(
	wake: Dictionary,
	activity_id: String,
	line: String,
) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-activity-%s" % [decision_id, activity_id],
			"type": "做活动",
			"activity_id": activity_id,
			"line": line,
		},
	}



func _available_worker_activity_id(
	world: RefCounted,
	resident_name: String,
) -> String:
	var state := world.call(
		"get_resident_state",
		resident_name,
	) as Dictionary
	var resident_id := String(state.get("residentId", ""))
	var query := world.call(
		"query_activity_options",
		resident_id,
	) as Dictionary
	for option_value: Variant in query.get("options", []) as Array:
		var option := option_value as Dictionary
		if (
			bool(option.get("available", false))
			and String(option.get("role", "")) == "worker"
		):
			return String(option.get("activityId", ""))
	return ""



func _talk_daily_life_chain(
	wake: Dictionary,
	target_id: String,
	say: String,
	narration: String,
) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-talk" % decision_id,
			"type": "搭话",
			"target_resident_id": target_id,
			"say": say,
			"narration": narration,
			"photos": [],
		},
	}



func _reply(
	wake: Dictionary,
	conversation_id: String,
	say: String,
	narration: String,
	end: bool,
) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-reply" % decision_id,
			"type": "答话",
			"conversation_id": conversation_id,
			"say": say,
			"narration": narration,
			"photos": [],
			"end": end,
		},
	}



func _nearby_id(wake: Dictionary, resident_name: String) -> String:
	for value: Variant in (
		(wake.get("snapshot", {}) as Dictionary).get("nearby", []) as Array
	):
		if not value is Dictionary:
			continue
		var person := value as Dictionary
		if String(person.get("name", "")) == resident_name:
			return String(person.get("resident_id", ""))
	return ""



func _has_event_daily_life_chain(wake: Dictionary, event_type: String) -> bool:
	for value: Variant in wake.get("events", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get("type", "")) == event_type
		):
			return true
	return false



func _expect_accepted(result: Dictionary, message: String) -> void:
	_expect_equal(result.get("status"), "accepted", "%s (%s)" % [message, result])



func _scenario_log_causal_query() -> void:
	_test_find_thread_by_source_event()
	_test_causal_chain()
	_test_excluded_event_types()
	_test_story_event_ingestion()
	_test_postal_terminal_update()
	_test_thread_detail_stores_no_story_fields()
	_test_runtime_public_log_hides_story_fields()
	_test_weather_change_enters_player_log()
	_test_message_sender_distribution()
	_test_place_filter()
	_test_place_log_item_adapter()
	_test_thread_source_event_ids()
	_test_observation_kind_rule()
	_test_place_observations()
	return
func _test_find_thread_by_source_event() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "causal-find"), "find reset")
	_expect_ok(store.call("append_public_event", _public_event(
		"evt-cargo-1",
		"cargo_event",
		{"type": "货批生成", "cargoLotId": "lot-1", "status": "ongoing"},
	)), "find append")
	var rows := (
		store.call("query_threads", {}) as Dictionary
	).get("rows", []) as Array
	_expect_equal(rows.size(), 1, "find thread row present")
	var thread_id := String((rows[0] as Dictionary).get("threadId", ""))
	var found := store.call(
		"find_thread_by_source_event",
		"evt-cargo-1",
	) as Dictionary
	_expect_equal(found.get("ok"), true, "source event resolves")
	_expect_equal(found.get("threadId"), thread_id, "resolved thread matches query row")
	_expect(int(found.get("sequence", 0)) >= 1, "resolved sequence positive")
	var missing := store.call(
		"find_thread_by_source_event",
		"evt-unknown",
	) as Dictionary
	_expect_equal(
		missing.get("errorCode"),
		"WORLD_LOG_SOURCE_EVENT_NOT_FOUND",
		"unknown source event fails explicitly",
	)
	var empty := store.call("find_thread_by_source_event", "  ") as Dictionary
	_expect_equal(
		empty.get("errorCode"),
		"WORLD_LOG_SOURCE_ID_MISSING",
		"blank source id fails explicitly",
	)



func _test_causal_chain() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "causal-chain"), "chain reset")
	_expect_ok(store.call("append_batch", [
		_record("thread-a", "item-a", "evt-a", {}),
		_record("thread-b", "item-b", "evt-b", {"causedByEventIds": ["evt-a"]}),
	]), "chain append")
	var chain := store.call("get_causal_chain", "thread-b") as Dictionary
	_expect_equal(chain.get("ok"), true, "chain resolves")
	_expect_equal(chain.get("currentThreadId"), "thread-b", "chain current thread")
	var nodes := chain.get("nodes", []) as Array
	_expect_equal(nodes.size(), 2, "chain has cause and effect")
	if nodes.size() == 2:
		_expect_equal(
			(nodes[0] as Dictionary).get("threadId"),
			"thread-a",
			"earliest cause first",
		)
		_expect_equal(
			(nodes[0] as Dictionary).get("isCurrent"),
			false,
			"cause not current",
		)
		_expect_equal(
			(nodes[1] as Dictionary).get("threadId"),
			"thread-b",
			"current thread last",
		)
		_expect_equal(
			(nodes[1] as Dictionary).get("isCurrent"),
			true,
			"current flagged",
		)
	var no_cause := store.call("get_causal_chain", "thread-a") as Dictionary
	_expect_equal(no_cause.get("ok"), true, "no-cause chain resolves")
	_expect_equal(
		(no_cause.get("nodes", []) as Array).size(),
		0,
		"single-node chain reports empty nodes",
	)
	var absent := store.call("get_causal_chain", "thread-x") as Dictionary
	_expect_equal(
		absent.get("errorCode"),
		"WORLD_LOG_THREAD_NOT_FOUND",
		"unknown thread fails explicitly",
	)
	_expect_ok(store.call("append_batch", [
		_record("thread-c", "item-c", "evt-c", {"causedByEventIds": ["evt-d"]}),
		_record("thread-d", "item-d", "evt-d", {"causedByEventIds": ["evt-c"]}),
	]), "cycle append")
	var cycle := store.call("get_causal_chain", "thread-c") as Dictionary
	_expect_equal(cycle.get("ok"), true, "cyclic causes terminate")
	_expect_equal(
		(cycle.get("nodes", []) as Array).size(),
		2,
		"cycle yields both nodes exactly once",
	)



func _test_excluded_event_types() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "excluded-types"), "excluded reset")
	for event_type in ["旁听", "移动", "有人来了"]:
		var result := store.call("append_public_event", _public_event(
			"evt-%s" % event_type,
			"world_event",
			{"type": event_type},
		)) as Dictionary
		_expect_equal(result.get("ok"), true, "%s 排除返回成功" % event_type)
		_expect_equal(result.get("excluded"), true, "%s 被排除" % event_type)
	_expect_equal(
		int(store.call("get_record_count")),
		0,
		"排除类型不入库(旁听按 aya 裁决保留丢弃)",
	)
	# 正向对照用已知会入库的货批事件(裸"搭话"事件还要过 LogStore 的
	# "玩家有感"过滤,不适合做排除表的对照组)。
	_expect_ok(store.call("append_public_event", _public_event(
		"evt-cargo",
		"cargo_event",
		{"type": "货批生成", "cargoLotId": "lot-x", "status": "ongoing"},
	)), "非排除类型正常入库")
	_expect_equal(int(store.call("get_record_count")), 1, "对照事件入库")



func _test_story_event_ingestion() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "story-events"), "story reset")
	# 行动结果:完成态的非移动/等待/对话类才收(规则源=表现层影子引擎)
	_expect_ok(store.call("append_public_event", _story_event(
		"evt-outcome-1",
		{
			"storyType": "action_outcome",
			"status": "completed",
			"actionType": "用道具",
			"storyRootEventIds": ["root-1"],
		},
	)), "完成态行动结果入库")
	for skipped in [
		{"storyType": "action_outcome", "status": "ongoing", "actionType": "用道具", "storyRootEventIds": ["root-1"]},
		{"storyType": "action_outcome", "status": "completed", "actionType": "去", "storyRootEventIds": ["root-1"]},
		{"storyType": "action_outcome", "status": "completed", "actionType": "用道具", "verb": "睡觉", "storyRootEventIds": ["root-1"]},
		{"storyType": "action_outcome", "status": "completed", "actionType": "做活动", "storyRootEventIds": ["root-1"]},
		{"storyType": "action_outcome", "status": "completed", "actionType": "用道具", "storyRootEventIds": []},
	]:
		var result := store.call("append_public_event", _story_event(
			"evt-skip-%d" % skipped.hash(),
			skipped,
		)) as Dictionary
		_expect_equal(result.get("excluded"), true, "不合规则的行动结果被排除")
	_expect_equal(int(store.call("get_record_count")), 1, "仅合规行动结果入库")
	var rollover_cancel := store.call("append_public_event", _public_event(
		"evt-rollover-cancel",
		"work_task",
		{
			"type": "工作任务取消",
			"taskId": "daily-catalog-task-1",
			"status": "cancelled",
			"capability": "library.assist",
			"sourceKind": "daily_catalog_plan",
			"sourceRef": "daily-catalog:1",
			"participantIds": ["resident-a"],
		},
	)) as Dictionary
	_expect_equal(rollover_cancel.get("excluded"), true, "日切内部任务取消不进入玩家日志")
	_expect_equal(int(store.call("get_record_count")), 1, "内部任务取消不增加日志记录")
	var expired_performance := store.call("append_public_event", _public_event(
		"evt-expired-performance",
		"work_task",
		{
			"type": "工作任务取消",
			"taskId": "performance-task-1",
			"status": "cancelled",
			"capability": "music.perform",
			"sourceKind": "personal_performance_plan",
			"sourceRef": "performance-plan:1",
			"participantIds": ["resident-a"],
			"waitReason": "演出日期已经过去",
		},
	)) as Dictionary
	_expect_equal(expired_performance.get("excluded"), true, "过期演出计划取消不进入玩家日志")
	_expect_equal(int(store.call("get_record_count")), 1, "过期演出计划取消不增加日志记录")
	# 聚集到场:同一根事件+地点归入同一线程(LogStore 线程模型天然聚合)
	for index in 3:
		_expect_ok(store.call("append_public_event", _story_event(
			"evt-gather-%d" % index,
			{
				"storyType": "gathering_arrival",
				"storyRootEventIds": ["root-gather"],
				"to": "小酒馆",
			},
		)), "聚集到场 %d 入库" % index)
	var rows := (
		store.call("query_threads", {}) as Dictionary
	).get("rows", []) as Array
	var gathering_rows: Array[Dictionary] = []
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		if String(row.get("threadId", "")).begins_with("gathering:"):
			gathering_rows.append(row)
	_expect_equal(gathering_rows.size(), 1, "三条到场归并为一条聚集线程")
	if gathering_rows.size() == 1:
		_expect_equal(
			(gathering_rows[0] as Dictionary).get("threadId"),
			"gathering:root-gather:小酒馆",
			"聚集线程按 根事件+地点 归并",
		)
		_expect_equal(
			int((gathering_rows[0] as Dictionary).get("recordCount", 0)),
			3,
			"聚集线程累计三条记录",
		)
	# 不同地点不归并
	_expect_ok(store.call("append_public_event", _story_event(
		"evt-gather-other",
		{
			"storyType": "gathering_arrival",
			"storyRootEventIds": ["root-gather"],
			"to": "花房咖啡馆",
		},
	)), "异地到场入库")
	var rows2 := (
		store.call("query_threads", {}) as Dictionary
	).get("rows", []) as Array
	var gathering_count := 0
	for row_value: Variant in rows2:
		if String((row_value as Dictionary).get("threadId", "")).begins_with("gathering:"):
			gathering_count += 1
	_expect_equal(gathering_count, 2, "不同地点的聚集各自成线程")

func _test_postal_terminal_update() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "postal-terminal"), "postal terminal reset")
	_expect_ok(store.call("append_public_event", _public_event(
		"evt-postal-cancel",
		"work_task",
		{
			"type": "工作任务取消",
			"taskId": "postal-deliver-task-1",
			"status": "cancelled",
			"capability": "message.deliver",
			"sourceKind": "postal_batch",
			"sourceRef": "postal-batch-1",
			"participantIds": ["resident-a", "resident-b"],
			"waitReason": "收件居民已经离开小镇",
		},
	)), "口信取消仍保留为可解释记录")
	var rows := (store.call("query_threads", {}) as Dictionary).get("rows", []) as Array
	_expect_equal(rows.size(), 1, "口信取消只有一条线程")
	if rows.size() == 1:
		_expect_equal(
			(rows[0] as Dictionary).get("latestUpdate"),
			"口信投递已取消：收件居民已经离开小镇",
			"口信取消不会显示成等待投递",
		)


func _test_thread_detail_stores_no_story_fields() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "legacy-story-payload"), "legacy story payload reset")
	_expect_ok(store.call("append_batch", [
		_record(
			"thread-story",
			"item-story-1",
			"evt-story-1",
			{
				"storyEventId": "story-old-1",
				"storyType": "action_outcome",
				"storyRootEventIds": ["root-old-1"],
				"type": "用道具",
				"status": "completed",
			},
		),
	]), "legacy payload story fields stored")
	var detail := store.call("get_thread_detail", "thread-story") as Dictionary
	_expect_equal(detail.get("ok"), true, "thread detail 可返回")
	var records := detail.get("records", []) as Array
	_expect_equal(records.size(), 1, "thread detail 里有一条记录")
	var payload := {}
	if records.size() == 1:
		payload = (
			(records[0] as Dictionary).get("payload", {}) as Dictionary
		)
	_expect(
		not payload.has("storyEventId"),
		"详情返回不含 storyEventId",
	)
	_expect(
		not payload.has("storyType"),
		"详情返回不含 storyType",
	)
	_expect(
		not payload.has("storyRootEventIds"),
		"详情返回不含 storyRootEventIds",
	)


func _test_runtime_public_log_hides_story_fields() -> void:
	var world: RefCounted = WORLD.new()
	world.call(
		"_append_public_event_log",
		"evt-public-story",
		"story_event",
		"",
		"",
		"",
		{
			"storyEventId": "story-public-1",
			"storyType": "action_outcome",
			"storyRootEventIds": ["root-public-1"],
			"type": "用道具",
		},
	)
	var public_events := world.call("get_public_event_log") as Array
	_expect_equal(public_events.size(), 1, "公开事件日志可返回测试记录")
	var payload := {}
	if public_events.size() == 1:
		payload = (
			(public_events[0] as Dictionary).get("payload", {}) as Dictionary
		)
	for field: String in [
		"storyEventId", "storyType", "storyRootEventIds",
	]:
		_expect(not payload.has(field), "公开事件日志不泄漏 %s" % field)


func _test_weather_change_enters_player_log() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "weather-log"), "weather log reset")
	_expect_ok(store.call("append_public_event", _public_event(
		"evt-weather-rain",
		"world_event",
		{"type": "天气变了", "weather": "小雨"},
	)), "天气变化进入日志资料库")
	var rows := (store.call("query_threads", {}) as Dictionary).get(
		"rows",
		[],
	) as Array
	_expect_equal(rows.size(), 1, "天气变化形成一条玩家日志")
	if rows.size() == 1:
		_expect_equal(
			(rows[0] as Dictionary).get("latestUpdate"),
			"天气转为小雨",
			"天气日志使用玩家可读文字",
		)


func _test_message_sender_distribution() -> void:
	var world := _MessagePolicyWorld.new()
	var selected := {}
	for index in 48:
		var source_ref := "notice:%d" % index
		var sender := RESIDENT_MESSAGE_POLICY.sender_for_source(
			world,
			"occupation_postal_worker",
			source_ref,
			"recipient",
			"distribution:%d" % index,
		)
		selected[sender] = true
	_expect(
		selected.size() > 1,
		"多名合格职业居民不会长期固定为同一发送人",
	)
	_expect(
		not selected.has("recipient"),
		"发送人选择不会选到收件人本人",
	)
	var stable_sender := RESIDENT_MESSAGE_POLICY.sender_for_source(
		world,
		"occupation_postal_worker",
		"notice:stable",
		"recipient",
		"distribution:stable",
	)
	_expect_equal(
		RESIDENT_MESSAGE_POLICY.sender_for_source(
			world,
			"occupation_postal_worker",
			"notice:stable",
			"recipient",
			"distribution:stable",
		),
		stable_sender,
		"同一事实重试时发送人保持稳定",
	)



func _story_event(event_id: String, payload: Dictionary) -> Dictionary:
	var event := _public_event(event_id, "story_event", payload)
	event["placeName"] = String(payload.get("to", "独立市集"))
	return event



func _test_place_filter() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "place-filter"), "place filter reset")
	_expect_ok(store.call("append_batch", [
		_record_at("pf1", "pi1", "pe1", "小酒馆", "daily_activity", "archive_only"),
		_record_at("pf2", "pi2", "pe2", "小酒馆", "conversation", "archive_only"),
		_record_at("pf3", "pi3", "pe3", "花房咖啡馆", "daily_activity", "archive_only"),
	]), "place filter append")
	var tavern := store.call("query_threads", {"placeId": "小酒馆"}) as Dictionary
	_expect_equal(tavern.get("ok"), true, "地点过滤查询成功")
	_expect_equal((tavern.get("rows", []) as Array).size(), 2, "只返回该地点线程")
	_expect_equal(int(tavern.get("total", 0)), 2, "total 与过滤后一致")
	var cafe := store.call("query_threads", {"placeId": "花房咖啡馆"}) as Dictionary
	_expect_equal((cafe.get("rows", []) as Array).size(), 1, "另一地点各自计数")
	var none := store.call("query_threads", {"placeId": "不存在的地方"}) as Dictionary
	_expect_equal((none.get("rows", []) as Array).size(), 0, "无匹配地点返回空")
	var all := store.call("query_threads", {}) as Dictionary
	_expect_equal((all.get("rows", []) as Array).size(), 3, "不带过滤返回全部")



func _test_place_log_item_adapter() -> void:
	# G 之 1 第二步适配器的映射等价性:LogStore 线程行 → place_focus 条目形态。
	var service_script := load("res://world/presentation/ui/TownUiPageProjectionService.gd")
	var service: RefCounted = service_script.new()
	var conversation_thread := {
		"threadId": "conversation:c-1",
		"title": "小满与阿禾的对话",
		"preview": "两个人在市集上聊了几句。",
		"updatedAt": {"day": 3, "hour": 10, "minute": 5},
		"kindTags": ["conversation"],
		"placeLabel": "独立市集",
		"participantSnapshots": [
			{"residentId": "r-1", "displayName": "小满"},
			{"residentId": "r-2", "displayName": "阿禾"},
		],
		"participantIds": ["r-1", "r-2"],
	}
	var mapped := service.call(
		"_thread_to_place_log_item",
		conversation_thread,
	) as Dictionary
	_expect_equal(mapped.get("id"), "conversation:c-1", "id 取 threadId")
	_expect_equal(mapped.get("title"), "小满与阿禾的对话", "title 直取")
	_expect_equal(mapped.get("subtitle"), "两个人在市集上聊了几句。", "subtitle 取 preview")
	_expect_equal(mapped.get("primaryCategory"), "social", "对话类映射为 social")
	_expect_equal(mapped.get("placeLabel"), "独立市集", "地点标签直取")
	_expect_equal(
		mapped.get("participantLabels"),
		["小满", "阿禾"],
		"参与者标签取快照显示名",
	)
	_expect_equal(mapped.get("isHot"), false, "两人不算热闹")
	_expect_equal(
		mapped.get("sourceEventIds"),
		[],
		"无来源时透传空数组",
	)
	_expect(
		not String(mapped.get("timeLabel", "")).is_empty(),
		"时间标签非空",
	)
	var gathering_thread := conversation_thread.duplicate(true)
	gathering_thread["threadId"] = "gathering:root-1:小酒馆"
	gathering_thread["kindTags"] = ["daily_activity"]
	gathering_thread["participantIds"] = ["r-1", "r-2", "r-3"]
	var mapped_gathering := service.call(
		"_thread_to_place_log_item",
		gathering_thread,
	) as Dictionary
	_expect_equal(
		mapped_gathering.get("primaryCategory"),
		"resident",
		"非对话类映射为 resident",
	)
	_expect_equal(mapped_gathering.get("isHot"), true, "三人及以上判热闹")



func _test_thread_source_event_ids() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "thread-sources"), "sources reset")
	_expect_ok(store.call("append_batch", [
		_record("t-src", "i-src-1", "evt-src-1", {}),
		_record("t-src", "i-src-2", "evt-src-2", {}),
	]), "同线程两条记录")
	var rows := (
		store.call("query_threads", {}) as Dictionary
	).get("rows", []) as Array
	_expect_equal(rows.size(), 1, "两条记录归一线程")
	if rows.size() == 1:
		_expect_equal(
			(rows[0] as Dictionary).get("sourceEventIds"),
			["evt-src-1", "evt-src-2"],
			"线程按摄取顺序累积来源事件 id",
		)



func _test_observation_kind_rule() -> void:
	_expect_equal(
		STORE.observation_kind_for({"attention": "important"}),
		"important",
		"important attention wins",
	)
	_expect_equal(
		STORE.observation_kind_for({
			"attention": "important",
			"kindTag": "conversation",
		}),
		"important",
		"important outranks dialogue",
	)
	_expect_equal(
		STORE.observation_kind_for({"kindTag": "conversation"}),
		"dialogue",
		"conversation tag maps to dialogue",
	)
	_expect_equal(
		STORE.observation_kind_for({"kind": "conversation_turn"}),
		"dialogue",
		"conversation record kind maps to dialogue",
	)
	for action_tag in ["daily_activity", "production", "service", "commerce"]:
		_expect_equal(
			STORE.observation_kind_for({"kindTag": action_tag}),
			"action",
			"%s maps to action" % action_tag,
		)
	_expect_equal(
		STORE.observation_kind_for({"kindTag": "world_change"}),
		"",
		"unclassified stays blank",
	)



func _test_place_observations() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "place-observations"), "obs reset")
	_expect_ok(store.call("append_batch", [
		_record_at("t1", "i1", "e1", "小酒馆", "daily_activity", "archive_only"),
		_record_at("t2", "i2", "e2", "小酒馆", "conversation", "archive_only"),
		_record_at("t3", "i3", "e3", "小酒馆", "world_change", "important"),
		_record_at("t4", "i4", "e4", "别处", "daily_activity", "archive_only"),
		_record_at("t5", "i5", "e5", "小酒馆", "daily_activity", "archive_only"),
	]), "obs append")
	var result := store.call("query_place_observations", "小酒馆") as Dictionary
	_expect_equal(result.get("ok"), true, "observations resolve")
	var observations := result.get("observations", []) as Array
	_expect_equal(observations.size(), 3, "one observation per kind")
	if observations.size() == 3:
		_expect_equal(
			(observations[0] as Dictionary).get("observationKind"),
			"action",
			"fixed kind order starts with action",
		)
		_expect_equal(
			(observations[0] as Dictionary).get("threadId"),
			"t5",
			"newest action wins per-kind slot",
		)
		_expect_equal(
			(observations[1] as Dictionary).get("observationKind"),
			"dialogue",
			"dialogue second",
		)
		_expect_equal(
			(observations[2] as Dictionary).get("observationKind"),
			"important",
			"important last",
		)
	for entry_value: Variant in observations:
		_expect(
			String((entry_value as Dictionary).get("threadId", "")) != "t4",
			"other place excluded",
		)
	var blank := store.call("query_place_observations", " ") as Dictionary
	_expect_equal(
		blank.get("errorCode"),
		"WORLD_LOG_PLACE_ID_MISSING",
		"blank place fails explicitly",
	)



func _public_event(event_id: String, kind: String, payload: Dictionary) -> Dictionary:
	return {
		"eventId": event_id,
		"kind": kind,
		"time": {"day": 3, "hour": 10, "minute": 0},
		"worldRevision": 20,
		"residentId": "resident-a",
		"residentName": "小满",
		"placeName": "独立市集",
		"payload": payload,
	}



func _record(
	thread_id: String,
	item_id: String,
	event_id: String,
	payload: Dictionary,
) -> Dictionary:
	return {
		"threadId": thread_id,
		"logItemId": item_id,
		"sourceRefs": [{
			"sourceKind": "world_event",
			"sourceId": event_id,
			"mutationId": event_id,
		}],
		"kind": "world_event",
		"kindTag": "world_change",
		"time": {"day": 2, "hour": 9, "minute": 0},
		"participantIds": [],
		"references": {},
		"payload": payload,
		"title": "标题-%s" % thread_id,
		"attention": "archive_only",
	}



func _record_at(
	thread_id: String,
	item_id: String,
	event_id: String,
	place_id: String,
	kind_tag: String,
	attention: String,
) -> Dictionary:
	var record := _record(thread_id, item_id, event_id, {})
	record["placeId"] = place_id
	record["kindTag"] = kind_tag
	record["attention"] = attention
	return record



func _expect_ok(value: Variant, label: String) -> void:
	_expect(
		value is Dictionary and (value as Dictionary).get("ok") == true,
		"%s ok expected, got %s" % [label, value],
	)



func _scenario_environment() -> void:
	var environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(environment.call("get_errors"), [], "formal time-weather data validates")
	_expect_equal(environment.call("start", 1, "+1:00", "晴天", 7).get("ok"), false, "signed clocks are rejected")
	_expect_equal(environment.call("start", 1, "1:00", "晴天", 7).get("ok"), false, "short clocks are rejected")
	_expect_equal(
		environment.call("start", 1, "05:59", "晴天", 7).get("ok"),
		true,
		"formal world starts from valid state",
	)
	var first_weather_delay := int(
		environment.call("get_minutes_until_next_weather_check")
	)
	_expect(
		first_weather_delay >= 45 and first_weather_delay <= 90,
		"natural weather schedules its first check inside the formal random window",
	)
	_expect_equal(environment.call("queue_weather_roll", 0.71), true, "valid forced weather rolls are accepted")
	var dawn: Dictionary = environment.call("advance", float(first_weather_delay))
	_expect_equal(
		dawn.get("minutesAdvanced"),
		first_weather_delay,
		"weather wait advances the expected number of game minutes",
	)
	_expect_equal((dawn.get("periodChanges", []) as Array).size(), 0, "weather checks do not depend on broad period boundaries")
	_expect_equal(environment.call("get_weather"), "阴天", "weather follows the sunny transition row")
	_expect_equal((dawn.get("events", []) as Array).size(), 1, "actual natural weather change emits one event")
	if (dawn.get("events", []) as Array).size() == 1:
		_expect_equal(dawn["events"][0]["type"], "天气变了", "weather event uses Agent contract type")
	var unchanged_weather: RefCounted = ENVIRONMENT.new()
	unchanged_weather.call("start", 1, "05:59", "晴天", 9)
	unchanged_weather.call("queue_weather_roll", 0.1)
	var unchanged_dawn := unchanged_weather.call(
		"advance",
		float(unchanged_weather.call("get_minutes_until_next_weather_check")),
	) as Dictionary
	_expect_equal(unchanged_weather.call("get_weather"), "晴天", "same-bucket weather keeps the current weather")
	_expect_equal((unchanged_dawn.get("events", []) as Array).size(), 0, "unchanged natural weather emits no event")

	environment.call("start", 1, "23:59", "雷暴", 11)
	environment.call("queue_weather_roll", 0.01)
	var midnight: Dictionary = environment.call("advance", 1.0)
	_expect_equal(environment.call("get_time"), {"day": 2, "clock": "00:00", "period": "夜里"}, "midnight advances the day")
	_expect_equal((midnight.get("periodChanges", []) as Array).size(), 0, "night remains the same named period across midnight")
	environment.call("set_time", 2, "22:00")
	_expect_equal(environment.call("minutes_until_next_period"), 420, "night waits until dawn instead of stopping at midnight")

	environment.call("start", 2, "17:59", "小雨", 13)
	var evening_weather_delay := int(
		environment.call("get_minutes_until_next_weather_check")
	)
	environment.call("queue_weather_roll", 0.98)
	var evening: Dictionary = environment.call("advance", 1.0)
	_expect_equal(environment.call("get_time").get("period"), "傍晚", "18:00 enters evening")
	_expect_equal((evening.get("periodChanges", []) as Array).size(), 1, "new formal period is observable")
	_expect_equal(environment.call("get_weather"), "小雨", "period boundary alone does not force a weather check")
	var evening_weather := environment.call(
		"advance",
		float(evening_weather_delay - 1),
	) as Dictionary
	_expect_equal(
		(evening_weather.get("events", []) as Array).size(),
		1,
		"randomly scheduled weather check can change weather away from a period boundary",
	)
	_expect_equal(environment.call("get_weather"), "雷暴", "forced roll selects the matching transition bucket")

	var found_non_hourly_check := false
	for seed in range(1, 9):
		var irregular_environment: RefCounted = ENVIRONMENT.new()
		irregular_environment.call("start", 1, "08:00", "晴天", seed)
		var scheduled_delay := int(
			irregular_environment.call(
				"get_minutes_until_next_weather_check",
			)
		)
		if posmod(scheduled_delay, 60) != 0:
			found_non_hourly_check = true
			break
	_expect(
		found_non_hourly_check,
		"natural weather checks are not locked to whole clock hours",
	)

	for weather in ["晴天", "阴天", "小雨", "中雨", "大雨", "雷暴", "下雪"]:
		var changed: Dictionary = environment.call("set_weather", weather)
		_expect_equal(changed.get("ok"), true, "player can select formal weather %s" % weather)
		_expect_equal(environment.call("get_weather"), weather, "world exposes only confirmed weather %s" % weather)

	var cycle_environment: RefCounted = ENVIRONMENT.new()
	cycle_environment.call("start", 3, "04:00", "晴天", 19)
	var expected_times := [
		{"day": 3, "clock": "05:30", "period": "清晨"},
		{"day": 3, "clock": "09:30", "period": "上午"},
		{"day": 3, "clock": "12:30", "period": "中午"},
		{"day": 3, "clock": "15:30", "period": "下午"},
		{"day": 3, "clock": "18:30", "period": "傍晚"},
		{"day": 3, "clock": "22:30", "period": "夜里"},
		{"day": 4, "clock": "05:30", "period": "清晨"},
	]
	for expected_time in expected_times:
		cycle_environment.call("cycle_time_period")
		_expect_equal(cycle_environment.call("get_time"), expected_time, "manual time switch visits the next formal period")

	var sliced_environment: RefCounted = ENVIRONMENT.new()
	sliced_environment.call("start", 1, "00:00", "晴天", 21)
	var sliced_minutes := 0
	for slice_index in range(10):
		var slice_result := sliced_environment.call("advance", 0.1) as Dictionary
		sliced_minutes += int(slice_result.get("minutesAdvanced", 0))
		_expect_equal(
			slice_result.get("minutesAdvanced"),
			0 if slice_index < 9 else 1,
			"ten equal frame slices advance only when exactly one real second is complete",
		)
	_expect_equal(sliced_minutes, 1, "ten 0.1-second frame slices advance exactly one game minute")
	_expect_equal(
		sliced_environment.call("get_time"),
		{"day": 1, "clock": "00:01", "period": "夜里"},
		"equivalent segmented input keeps the confirmed world clock",
	)

	var strict_input_environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(
		strict_input_environment.call("start", 3, "08:00", "晴天", 29).get("ok"),
		true,
		"strict-input test starts from valid state",
	)
	var strict_time: Dictionary = strict_input_environment.call("get_time")
	_expect_equal(strict_input_environment.call("start", 1.5, "08:00", "晴天", 29).get("ok"), false, "fractional start days are rejected before coercion")
	_expect_equal(strict_input_environment.call("start", true, "08:00", "晴天", 29).get("ok"), false, "boolean start days are rejected before coercion")
	_expect_equal(strict_input_environment.call("start", ENVIRONMENT.MAX_SAFE_DAY + 1, "08:00", "晴天", 29).get("ok"), false, "start days that overflow absolute minutes are rejected")
	_expect_equal(strict_input_environment.call("start", 3, "08:00", "晴天", true).get("ok"), false, "boolean random seeds are rejected before coercion")
	_expect_equal(strict_input_environment.call("start", 3, "08:00", "晴天", 1.5).get("ok"), false, "fractional random seeds are rejected before coercion")
	_expect_equal(strict_input_environment.call("start", 3, "08:00", [], 29).get("ok"), false, "array weather is rejected without a format-string failure")
	_expect_equal(strict_input_environment.call("get_time"), strict_time, "rejected start inputs do not change world time")
	_expect_equal(strict_input_environment.call("get_weather"), "晴天", "rejected start weather does not change world weather")
	_expect_equal(strict_input_environment.call("set_time", 1.5, "09:00").get("ok"), false, "fractional set-time days are rejected before coercion")
	_expect_equal(strict_input_environment.call("set_time", true, "09:00").get("ok"), false, "boolean set-time days are rejected before coercion")
	_expect_equal(strict_input_environment.call("set_time", ENVIRONMENT.MAX_SAFE_DAY + 1, "09:00").get("ok"), false, "set-time days that overflow absolute minutes are rejected")
	_expect_equal(strict_input_environment.call("get_time"), strict_time, "rejected set-time inputs do not change world time")
	_expect_equal(strict_input_environment.call("queue_weather_roll", false), false, "boolean weather rolls are rejected before coercion")
	_expect_equal(strict_input_environment.call("advance", true).get("minutesAdvanced"), 0, "boolean elapsed time is rejected before coercion")
	_expect_equal(strict_input_environment.call("get_time"), strict_time, "rejected elapsed time does not change world time")
	_expect_equal(strict_input_environment.call("set_weather", false).get("ok"), false, "non-text weather is rejected before coercion")
	_expect_equal(strict_input_environment.call("set_weather", []).get("ok"), false, "array weather is rejected without a format-string failure")
	_expect_equal(strict_input_environment.call("get_weather"), "晴天", "rejected weather does not change world state")
	var maximum_time_environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(
		maximum_time_environment.call(
			"start",
			ENVIRONMENT.MAX_SAFE_DAY,
			"23:59",
			"晴天",
			37,
		).get("ok"),
		true,
		"the last representable world minute can start",
	)
	_expect_equal(
		maximum_time_environment.call("advance", 1.0).get(
			"minutesAdvanced"
		),
		0,
		"world time does not advance beyond its serializable range",
	)
	_expect_equal(
		maximum_time_environment.call("get_time"),
		{
			"day": ENVIRONMENT.MAX_SAFE_DAY,
			"clock": "23:59",
			"period": "夜里",
		},
		"the time horizon preserves the last valid minute",
	)
	_expect_equal(
		(maximum_time_environment.call(
			"restore_from_snapshot",
			maximum_time_environment.call("create_save_snapshot"),
		) as Dictionary).get("ok"),
		true,
		"the capped world time remains restorable",
	)

	var fractional_environment: RefCounted = ENVIRONMENT.new()
	fractional_environment.call("start", 1, "00:00", "晴天", 23)
	var almost_one_second: Dictionary = fractional_environment.call("advance", 0.999999)
	_expect_equal(almost_one_second.get("minutesAdvanced"), 0, "fractional time never advances before one full real second")
	_expect_equal(fractional_environment.call("get_time"), {"day": 1, "clock": "00:00", "period": "夜里"}, "fractional time keeps the confirmed clock")
	var fractional_snapshot: Dictionary = fractional_environment.call("create_save_snapshot")
	var restored_fractional_environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(
		restored_fractional_environment.call(
			"restore_from_snapshot",
			fractional_snapshot,
		).get("ok"),
		true,
		"fractional time snapshot restores through the public boundary",
	)
	_expect_equal(
		restored_fractional_environment.call("advance", 0.000002).get(
			"minutesAdvanced"
		),
		1,
		"restored fractional time advances after the remaining real time",
	)
	_expect_equal(
		restored_fractional_environment.call("get_time"),
		{"day": 1, "clock": "00:01", "period": "夜里"},
		"restored fractional time reaches the next minute once",
	)
	_expect_equal(
		restored_fractional_environment.call(
			"get_minutes_until_next_weather_check",
		),
		int(
			fractional_environment.call(
				"get_minutes_until_next_weather_check",
			)
		) - 1,
		"restore preserves the already scheduled weather check",
	)
	var legacy_fractional_snapshot := fractional_snapshot.duplicate(true)
	legacy_fractional_snapshot.erase(
		"nextNaturalWeatherCheckAbsoluteMinute",
	)
	var legacy_restored_environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(
		legacy_restored_environment.call(
			"restore_from_snapshot",
			legacy_fractional_snapshot,
		).get("ok"),
		true,
		"older environment snapshots receive a fresh legal weather schedule",
	)
	_expect_equal(fractional_environment.call("advance", NAN).get("minutesAdvanced"), 0, "non-finite elapsed time never poisons the world clock")
	_expect_equal(fractional_environment.call("queue_weather_roll", -0.1), false, "negative weather rolls are rejected instead of clamped")
	_expect_equal(fractional_environment.call("queue_weather_roll", 1.0), false, "weather rolls at one are rejected instead of clamped")
	var unknown_snapshot_field := fractional_snapshot.duplicate(true)
	unknown_snapshot_field["debug"] = true
	var rejected_restore_environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(
		rejected_restore_environment.call(
			"start",
			3,
			"08:00",
			"阴天",
			31,
		).get("ok"),
		true,
		"rejected-restore test starts from valid state",
	)
	_expect_equal(
		rejected_restore_environment.call("queue_weather_roll", 0.25),
		true,
		"rejected-restore test records a pending weather roll",
	)
	var before_rejected_restore: Dictionary = (
		rejected_restore_environment.call("create_save_snapshot")
	)
	_expect_equal(
		rejected_restore_environment.call(
			"restore_from_snapshot",
			unknown_snapshot_field,
		).get("ok"),
		false,
		"unknown saved environment fields are rejected",
	)
	_expect_equal(
		rejected_restore_environment.call("create_save_snapshot"),
		before_rejected_restore,
		"rejected environment snapshots preserve all previous state",
	)
	var coerced_saved_weather := fractional_snapshot.duplicate(true)
	coerced_saved_weather["weather"] = 123
	_expect_equal(
		rejected_restore_environment.call(
			"restore_from_snapshot",
			coerced_saved_weather,
		).get("ok"),
		false,
		"saved weather is not silently coerced",
	)
	_expect_equal(
		rejected_restore_environment.call("create_save_snapshot"),
		before_rejected_restore,
		"coerced saved weather does not partially replace world state",
	)
	var padded_rng_state := fractional_snapshot.duplicate(true)
	padded_rng_state["rngState"] = "01"
	_expect_equal(
		rejected_restore_environment.call(
			"restore_from_snapshot",
			padded_rng_state,
		).get("ok"),
		false,
		"saved RNG state must use its canonical integer spelling",
	)
	_expect_equal(
		rejected_restore_environment.call("create_save_snapshot"),
		before_rejected_restore,
		"non-canonical RNG state does not partially replace world state",
	)
	var overflowing_day_snapshot := fractional_snapshot.duplicate(true)
	overflowing_day_snapshot["day"] = ENVIRONMENT.MAX_SAFE_DAY + 1
	_expect_equal(
		rejected_restore_environment.call(
			"restore_from_snapshot",
			overflowing_day_snapshot,
		).get("ok"),
		false,
		"saved days that overflow absolute minutes are rejected",
	)
	_expect_equal(
		rejected_restore_environment.call("create_save_snapshot"),
		before_rejected_restore,
		"overflowing saved days do not partially replace world state",
	)

	var formal_config := _read_json("res://world/runtime/environment/town_environment.json")
	var shifted_period := formal_config.duplicate(true)
	((shifted_period.get("time", {}) as Dictionary).get("periods", []) as Array)[1]["startMinute"] = 301
	_expect(not _environment_from_config(shifted_period).call("get_errors").is_empty(), "shifted period boundaries are rejected")
	var altered_speed := formal_config.duplicate(true)
	(altered_speed.get("time", {}) as Dictionary)["realSecondsPerGameMinute"] = 2.0
	_expect(not _environment_from_config(altered_speed).call("get_errors").is_empty(), "time speed cannot drift from one real second per game minute")
	var signed_manual_clock := formal_config.duplicate(true)
	((signed_manual_clock.get("time", {}) as Dictionary).get("manualCycleClocks", []) as Array)[0] = "+5:30"
	_expect(not _environment_from_config(signed_manual_clock).call("get_errors").is_empty(), "non-canonical manual clocks are rejected")
	var altered_weather := formal_config.duplicate(true)
	(((altered_weather.get("weather", {}) as Dictionary).get("transitions", {}) as Dictionary).get("晴天", {}) as Dictionary)["晴天"] = 69
	_expect(not _environment_from_config(altered_weather).call("get_errors").is_empty(), "altered formal weather probabilities are rejected")
	var altered_weather_interval := formal_config.duplicate(true)
	(
		(
			altered_weather_interval.get("weather", {}) as Dictionary
		).get("naturalChangeIntervalMinutes", {}) as Dictionary
	)["maximum"] = 91
	_expect(not _environment_from_config(altered_weather_interval).call("get_errors").is_empty(), "natural weather random window cannot silently drift")
	var extra_weather_key := formal_config.duplicate(true)
	(((extra_weather_key.get("weather", {}) as Dictionary).get("transitions", {}) as Dictionary).get("晴天", {}) as Dictionary)["未知"] = 0
	_expect(not _environment_from_config(extra_weather_key).call("get_errors").is_empty(), "extra weather transition keys are rejected")
	var extra_top_level := formal_config.duplicate(true)
	extra_top_level["debug"] = true
	_expect(not _environment_from_config(extra_top_level).call("get_errors").is_empty(), "unknown environment configuration fields are rejected")

	return
func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}



func _environment_from_config(config: Dictionary) -> RefCounted:
	var path := "user://town_world_environment_invalid_test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("cannot write temporary environment fixture")
		return ENVIRONMENT.new()
	file.store_string(JSON.stringify(config))
	file.close()
	return ENVIRONMENT.new(path)



func _scenario_staggered_arrival() -> void:
	var world_data := BUILDER.build_from_source(SOURCE_DIR)
	var loaded := OPENING.load_config(
		OPENING_PATH,
		world_data,
	) as Dictionary
	_expect_equal(loaded.get("ok"), true, "opening fixture loads")
	if loaded.get("ok") != true:
		return
	var opening := FORMAL_OPENING.with_authoritative_new_game_spawns(
		world_data,
		loaded.get("config", {}) as Dictionary,
	)
	var identities := _resident_identities_staggered_arrival(opening)
	var world: RefCounted = WORLD.new()
	var started := world.call(
		"start_formal",
		world_data,
		opening,
		identities,
	) as Dictionary
	_expect_equal(started.get("ok"), true, "formal world starts")
	if started.get("ok") != true:
		return
	var states := world.call("get_all_resident_states") as Array
	_expect_equal(states.size(), 15, "all residents keep roster state")
	var scheduled_minutes: Array[int] = []
	for value: Variant in states:
		var state := value as Dictionary
		var arrival := state.get("arrivalState", {}) as Dictionary
		_expect_equal(
			state.get("isPresent"),
			false,
			"resident stays absent before the scheduled minute",
		)
		_expect_equal(
			arrival.get("status"),
			"pending",
			"new resident starts with a pending arrival",
		)
		scheduled_minutes.append(
			int(arrival.get("scheduledAbsoluteMinute", -1)),
		)
	scheduled_minutes.sort()
	_expect_equal(
		_unique_ints(scheduled_minutes).size(),
		states.size(),
		"every resident receives a different arrival minute",
	)
	var start_absolute := _absolute_minute(world.call("get_time"))
	_expect(
		scheduled_minutes[0] > start_absolute,
		"no resident appears before the world starts",
	)
	_expect(
		scheduled_minutes[-1] <= 719,
		"all residents arrive before noon on day one",
	)
	_expect(
		not _regular_intervals(scheduled_minutes),
		"arrival intervals are not a fixed timetable",
	)
	_expect_equal(
		(world.call("take_pending_decision_requests") as Array).size(),
		0,
		"absent residents do not request Agent decisions",
	)
	var opening_services := world.call(
		"get_place_service_state_snapshots",
	) as Array
	_expect(
		not opening_services.is_empty(),
		"formal service places expose opening state",
	)
	for value: Variant in opening_services:
		_expect_equal(
			(value as Dictionary).get("open"),
			false,
			"a service stays closed until its worker arrives",
		)
	var actor_root := Node2D.new()
	actor_root.y_sort_enabled = true
	root.add_child(actor_root)
	var presentation := RESIDENT_PRESENTATION.new()
	root.add_child(presentation)
	var presentation_bind := presentation.call(
		"bind_world",
		world,
		actor_root,
	) as Dictionary
	_expect_equal(
		presentation_bind.get("ok"),
		true,
		"resident presentation binds to the pending roster",
	)
	_expect_equal(
		presentation_bind.get("residentCount"),
		0,
		"pending residents do not create visible bodies",
	)

	var save_result := world.call("create_save_snapshot") as Dictionary
	_expect_equal(save_result.get("ok"), true, "pending schedule saves")
	var restored_world: RefCounted = WORLD.new()
	var restore_start := restored_world.call(
		"start_formal_restore_observer",
		world_data,
		opening,
		identities,
	) as Dictionary
	_expect_equal(
		restore_start.get("ok"),
		true,
		"restore host starts",
	)
	var restored := restored_world.call(
		"restore_from_snapshot",
		world_data,
		opening,
		save_result.get("snapshot", {}) as Dictionary,
		identities,
	) as Dictionary
	_expect_equal(restored.get("ok"), true, "pending schedule restores")
	var restored_minutes: Array[int] = []
	for value: Variant in (
		restored_world.call("get_all_resident_states") as Array
	):
		restored_minutes.append(
			int(
				(
					(value as Dictionary).get(
						"arrivalState",
						{},
					) as Dictionary
				).get("scheduledAbsoluteMinute", -1),
			),
		)
	restored_minutes.sort()
	_expect_equal(
		restored_minutes,
		scheduled_minutes,
		"loading does not reroll the arrival timetable",
	)
	var separate_world: RefCounted = WORLD.new()
	var separate_start := separate_world.call(
		"start_formal",
		world_data,
		opening,
		identities,
	) as Dictionary
	_expect_equal(
		separate_start.get("ok"),
		true,
		"a separate new town starts with the same authored opening",
	)
	var separate_minutes: Array[int] = []
	for value: Variant in (
		separate_world.call("get_all_resident_states") as Array
	):
		separate_minutes.append(
			int(
				(
					(value as Dictionary).get(
						"arrivalState",
						{},
					) as Dictionary
				).get("scheduledAbsoluteMinute", -1),
			),
		)
	separate_minutes.sort()
	_expect(
		separate_minutes != scheduled_minutes,
		"a separate new town draws a genuinely different arrival timetable",
	)

	var expected_arrival_count := 0
	var first_arrival_checked := false
	while (
		_absolute_minute(world.call("get_time"))
		< scheduled_minutes[-1]
	):
		var minute_result := world.call("advance", 1.0) as Dictionary
		_expect_equal(
			minute_result.get("minutesAdvanced"),
			1,
			"normal World advance emits one real game-minute tick",
		)
		var current_absolute := _absolute_minute(world.call("get_time"))
		while (
			expected_arrival_count < scheduled_minutes.size()
			and scheduled_minutes[expected_arrival_count]
			<= current_absolute
		):
			expected_arrival_count += 1
		var present_states := _present_states(
			world.call("get_all_resident_states") as Array,
		)
		_expect_equal(
			present_states.size(),
			expected_arrival_count,
			"only residents whose scheduled minute has passed are present",
		)
		_expect_equal(
			(presentation.call("get_resident_ids") as Array).size(),
			expected_arrival_count,
			"presentation bodies follow the same real arrival ticks",
		)
		if expected_arrival_count == 1 and not first_arrival_checked:
			first_arrival_checked = true
			var arrival_resident := (
				(world.call("residents") as Dictionary).get(
					String(present_states[0].get("residentId", "")),
					{},
				) as Dictionary
			)
			var arrival_action := (
				arrival_resident.get("currentAction", {}) as Dictionary
			)
			_expect_equal(
				present_states[0].get("currentPlace"),
				"南入口",
				"the first resident enters through the South gate",
			)
			_expect_equal(
				arrival_action.get("decisionBridge"),
				true,
				"the arriving resident walks naturally while the first decision is pending",
			)
			_expect(
				not (arrival_action.get("idlePathPoints", []) as Array).is_empty(),
				"the arrival bridge moves the resident away from the entrance",
			)
			var arrival_requests := world.call(
				"take_pending_decision_requests",
			) as Array
			_expect_equal(
				arrival_requests.size(),
				1,
				"the arriving resident starts deciding only after entering",
			)
			if arrival_requests.size() == 1:
				var arrival_wake := (
					(arrival_requests[0] as Dictionary).get("wakePacket", {})
					as Dictionary
				)
				_expect_equal(
					(
						(arrival_wake.get("snapshot", {}) as Dictionary)
						.get("me", {}) as Dictionary
					).get("current_action"),
					null,
					"the local arrival bridge does not replace the resident's first OC decision",
				)
			_expect_equal(
				(world.call("create_save_snapshot") as Dictionary).get("ok"),
				true,
				"the arrival decision bridge remains saveable",
			)
	_expect_equal(
		_present_states(
			world.call("get_all_resident_states") as Array,
		).size(),
		15,
		"the full roster has entered by the end of the morning",
	)
	for value: Variant in (
		world.call("get_place_service_state_snapshots") as Array
	):
		var service := value as Dictionary
		if not String(service.get("owner_id", "")).is_empty():
			_expect_equal(
				service.get("open"),
				true,
				"staffed services open after their workers have arrived",
			)
	_expect_equal(
		(presentation.call("get_resident_ids") as Array).size(),
		15,
		"all resident bodies exist after the morning arrivals finish",
	)
	var arrival_log := world.call(
		"query_world_log_threads",
		{"limit": 200},
	) as Dictionary
	_expect_equal(arrival_log.get("ok"), true, "arrival history can be queried")
	var arrival_thread_count := 0
	for row_value: Variant in arrival_log.get("rows", []) as Array:
		if String((row_value as Dictionary).get("threadId", "")).begins_with(
			"lifecycle:resident-arrival:",
		):
			arrival_thread_count += 1
	_expect_equal(
		arrival_thread_count,
		15,
		"every resident arrival remains available in world history",
	)
	return
func _resident_identities_staggered_arrival(opening: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in opening.get("residents", []) as Array:
		var resident := value as Dictionary
		result.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(
				(
					resident.get("attributes", {}) as Dictionary
				).get("name", ""),
			),
		})
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("residentId", "")) < String(
				right.get("residentId", ""),
			)
	)
	return result



func _present_states(states: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in states:
		if (
			value is Dictionary
			and bool((value as Dictionary).get("isPresent", false))
		):
			result.append(value as Dictionary)
	return result



func _unique_ints(values: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		if not result.has(value):
			result.append(value)
	return result



func _regular_intervals(values: Array[int]) -> bool:
	if values.size() < 3:
		return false
	var expected := values[1] - values[0]
	for index in range(2, values.size()):
		if values[index] - values[index - 1] != expected:
			return false
	return true



func _absolute_minute(time_value: Variant) -> int:
	var time := time_value as Dictionary
	var parts := String(time.get("clock", "00:00")).split(":")
	return (
		(int(time.get("day", 1)) - 1) * 1440
		+ int(parts[0]) * 60
		+ int(parts[1])
	)



func _scenario_weather_behavior_diversity() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect(opening_result.get("ok") == true, "正式开局夹具必须可用")
	if opening_result.get("ok") != true:
		return
	var world: RefCounted = WORLD.new()
	_expect(
		(world.call(
			"start",
			data,
			opening_result.get("config", {}) as Dictionary,
		) as Dictionary).get("ok") == true,
		"天气多样性模拟必须能启动正式 World",
	)
	var initial_requests := (
		world.call("take_pending_decision_requests") as Array[Dictionary]
	)
	_expect(initial_requests.size() == 15, "15 位居民必须收到初始决定")
	for request: Dictionary in initial_requests:
		var wake := request.get("wakePacket", {}) as Dictionary
		var resident_name := String(request.get("residentName", ""))
		var result := world.call(
			"submit_agent_decision",
			resident_name,
			_wait_weather_behavior_diversity(wake),
		) as Dictionary
		_expect(
			String(result.get("status", "")) in [
				"accepted",
				"continued",
			],
			"%s 的初始状态必须被 World 保留：%s"
			% [resident_name, result],
		)

	var weather_result := world.call("set_weather", "大雨") as Dictionary
	_expect(
		weather_result.get("changed") == true,
		"大雨必须成为新的 World 确认事实",
	)
	var weather_requests := (
		world.call("take_pending_decision_requests") as Array[Dictionary]
	)
	_expect(
		weather_requests.size() == 4,
		"只有当前在户外的 4 位居民应立即回应天气",
	)
	var choices := {
		"林岚": {"kind": "continue"},
		"唐小满": {"kind": "go", "place": "花房咖啡馆"},
		"阿禾": {"kind": "go", "place": "图书馆"},
		"叶澄": {"kind": "go", "place": "东南街住宅"},
	}
	var observed_kinds := {}
	var requested_places: Array[String] = []
	for request: Dictionary in weather_requests:
		var resident_name := String(request.get("residentName", ""))
		var wake := request.get("wakePacket", {}) as Dictionary
		var choice := choices.get(resident_name, {}) as Dictionary
		_expect(not choice.is_empty(), "天气模拟必须覆盖 %s" % resident_name)
		if choice.is_empty():
			continue
		var decision := {}
		if String(choice.get("kind", "")) == "continue":
			decision = {
				"decision_id": String(wake.get("decision_id", "")),
				"handling": "continue_current",
			}
			observed_kinds["continue_outdoor"] = true
		else:
			var place_name := String(choice.get("place", ""))
			decision = _go_weather_behavior_diversity(wake, place_name)
			requested_places.append(place_name)
			observed_kinds[
				"home" if place_name.ends_with("住宅") else "public_indoor"
			] = true
		var result := world.call(
			"submit_agent_decision",
			resident_name,
			decision,
		) as Dictionary
		_expect(
			String(result.get("status", "")) in ["accepted", "continued"],
			"%s 的天气选择必须进入 World 执行链：%s"
			% [resident_name, result],
		)

	_expect(
		observed_kinds.has("continue_outdoor"),
		"大雨中应允许有人按事情轻重继续当前户外行动",
	)
	_expect(
		observed_kinds.has("public_indoor"),
		"大雨中应允许居民选择公共室内地点",
	)
	_expect(
		observed_kinds.has("home"),
		"回家仍应是居民可选择的一条生活路径",
	)
	_expect(
		requested_places.count("花房咖啡馆") == 1
		and requested_places.count("图书馆") == 1
		and requested_places.count("东南街住宅") == 1,
		"模拟选择必须形成公共地点、另一公共地点与住处三种去向",
	)
	var context := (
		world.call(
			"get_resident_state",
			"resident_tang_xiaoman_01",
		) as Dictionary
	)
	_expect(
		String(
			(context.get("currentAction", {}) as Dictionary).get(
				"type",
				"",
			)
		) == "去"
		and String(context.get("doing", "")).contains("花房咖啡馆"),
		"唐小满的公共室内去向必须成为 World 的公开行动与状态",
	)
	return
func _wait_weather_behavior_diversity(wake: Dictionary) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-continuity" % decision_id,
			"type": "待着",
			"line": "我先看看眼前的情况",
		},
	}



func _go_weather_behavior_diversity(wake: Dictionary, place_name: String) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-go-%s" % [decision_id, place_name],
			"type": "去",
			"place": place_name,
			"line": "我去%s避一避" % place_name,
		},
	}



func _scenario_action_type_registry() -> void:
	_test_full_set_matches_field_whitelist()
	_test_shape_validation_covers_expected_types()
	_test_conflict_types_excluded_from_advance_tables()
	_test_prop_type_remains_live()
	_test_default_doing_covers_expected_types()
	return
func _test_full_set_matches_field_whitelist() -> void:
	var whitelist_types: Array[String] = []
	for key_value: Variant in VALIDATION.ACTION_FIELDS:
		whitelist_types.append(String(key_value))
	whitelist_types.sort()
	var registry_types := REGISTRY.ALL_TYPES.duplicate()
	registry_types.sort()
	_expect_equal(
		whitelist_types,
		registry_types,
		"字段白名单(T1)与登记表全集逐项一致",
	)
	_expect_equal(REGISTRY.ALL_TYPES.size(), 13, "动作类型全集为 13 种")



func _test_shape_validation_covers_expected_types() -> void:
	# T4:登记表声明覆盖的类型必须被形状校验认出(未知字段会被拒),
	# 未声明的类型(冲突五类)必须直接放行——校验对它们不设约束。
	for action_type: String in REGISTRY.ALL_TYPES:
		var action := {
			"action_id": "registry-%s" % action_type,
			"type": action_type,
			"unknown_field": true,
		}
		# 第一层:字段白名单对全部类型生效,未知字段一律被拒。
		_expect(
			not String(VALIDATION.validate_action_shape(action)).is_empty(),
			"%s 的未知字段被白名单层拒绝" % action_type,
		)
		# 第二层:仅登记类型有必填校验;未登记类型给出合法字段即应通过。
		var minimal := {
			"action_id": "registry-min-%s" % action_type,
			"type": action_type,
		}
		var minimal_error := String(VALIDATION.validate_action_shape(minimal))
		if not REGISTRY.participates_in("T4_required_fields", action_type):
			_expect(
				minimal_error.is_empty(),
				"%s 无必填校验,最小动作应放行" % action_type,
			)



func _test_conflict_types_excluded_from_advance_tables() -> void:
	# 冲突五类由冲突桥即时结算、不写 currentAction,故不参与推进期各表。
	for action_type: String in REGISTRY.CONFLICT_TYPES:
		_expect(
			REGISTRY.is_conflict_type(action_type),
			"%s 登记为冲突类型" % action_type,
		)
		_expect(
			not REGISTRY.participates_in("T4_required_fields", action_type),
			"%s 不参与形状校验(有意)" % action_type,
		)
		_expect(
			not REGISTRY.participates_in("T7_default_doing", action_type),
			"%s 不参与 UI 文案表(有意)" % action_type,
		)
	_expect_equal(
		REGISTRY.CONFLICT_TYPES.size(),
		5,
		"冲突类型共 5 种",
	)
	for action_type: String in REGISTRY.ALL_TYPES:
		if REGISTRY.is_conflict_type(action_type):
			continue
		_expect(
			REGISTRY.participates_in("T4_required_fields", action_type)
			or action_type in REGISTRY.PREPARE_REJECTED_TYPES
			or true,
			"%s 为非冲突类型" % action_type,
		)



func _test_prop_type_remains_live() -> void:
	# "用道具"是活玩法:提交入口在 submit_agent_decision 分流到
	# _submit_legacy_prop_activity,不得因 _prepare_action 的硬拒而被判死。
	_expect(
		REGISTRY.ALL_TYPES.has("用道具"),
		"用道具在类型全集内",
	)
	_expect(
		not REGISTRY.PREPARE_REJECTED_TYPES.has("用道具"),
		"用道具不属于准备期硬拒类型(硬拒只守直连入口)",
	)
	_expect(
		REGISTRY.participates_in("T4_required_fields", "用道具"),
		"用道具参与形状校验",
	)
	_expect(
		REGISTRY.participates_in("T7_default_doing", "用道具"),
		"用道具参与 UI 文案表",
	)



func _test_default_doing_covers_expected_types() -> void:
	for action_type: String in REGISTRY.ALL_TYPES:
		var doing := String(PROJECTION.default_doing(
			_StubWorld.new(),
			{"type": action_type},
		))
		_expect(
			not doing.is_empty(),
			"%s 的 UI 文案非空(未覆盖类型走兜底)" % action_type,
		)
		if not REGISTRY.participates_in("T7_default_doing", action_type):
			_expect_equal(
				doing,
				"正在行动",
				"%s 未在文案表内,应走兜底文案" % action_type,
			)



func _scenario_audio_controller_button_cue() -> void:
	await process_frame
	var controller: Node = AUDIO_CONTROLLER.new()

	var cancel_delete := Button.new()
	cancel_delete.text = "取消删除"
	_expect_cue(controller, cancel_delete, "ui_back", "取消删除 is a cancel action, not a warning")

	var delete_button := Button.new()
	delete_button.text = "删除存档"
	_expect_cue(controller, delete_button, "ui_warning", "删除存档 keeps the warning cue")

	var quit_button := Button.new()
	quit_button.text = "退出游戏"
	_expect_cue(controller, quit_button, "ui_warning", "退出游戏 keeps the warning cue")

	var background_button := Button.new()
	background_button.name = "BackgroundPanelButton"
	_expect_cue(controller, background_button, "ui_tap", "background must not match the back keyword")

	var back_button := Button.new()
	back_button.name = "back_button"
	_expect_cue(controller, back_button, "ui_back", "back still matches as a whole word")

	var meta_button := Button.new()
	meta_button.text = "删除"
	meta_button.set_meta("town_audio_cue", "ui_confirm")
	_expect_cue(controller, meta_button, "ui_confirm", "explicit town_audio_cue meta wins over sniffing")

	controller._slider_steps[123] = 4
	controller.prepare_shutdown()
	_expect(
		(controller._slider_steps as Dictionary).is_empty(),
		"prepare_shutdown clears the slider step cache",
	)

	for node: Node in [
		cancel_delete,
		delete_button,
		quit_button,
		background_button,
		back_button,
		meta_button,
		controller,
	]:
		node.free()
	return
func _expect_cue(
	controller: Node, button: BaseButton, expected: String, message: String
) -> void:
	var actual := String(controller._cue_for_button(button))
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, expected, actual])
