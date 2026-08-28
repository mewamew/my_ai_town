extends SceneTree

const TOWN_BASE := preload("res://world/maps/town/TownBase.gd")
const UNIQUE_INTERIOR_PORTALS := {
	"cafe": "cafe",
	"library": "library",
	"town_hall": "town_hall",
	"clinic": "clinic",
	"market": "market",
	"dining_hall": "dining_hall",
	"workshop": "workshop",
	"dock_warehouse": "dock_warehouse",
	"home_a": "home_01",
	"home_b": "home_02",
}
const MAX_BLOCKING_FRAME_USEC := 25000

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_existing_wall_furniture_blocker_advances()
	var startup_started := Time.get_ticks_msec()
	var town := TOWN_BASE.new()
	root.add_child(town)
	var startup_msec := Time.get_ticks_msec() - startup_started
	var roots := town.get("_interior_roots") as Dictionary
	var build_queue := town.get_node_or_null("InteriorRoomBuildQueue")
	_expect(
		build_queue != null,
		"Town owns a frame-budgeted interior preparation queue",
	)
	if build_queue != null:
		var disabled_profile := build_queue.get_profile_snapshot() as Dictionary
		_expect(
			not build_queue.is_profiling_enabled(),
			"interior preparation profiling is disabled during normal play",
		)
		_expect(
			not disabled_profile.has("rooms") and disabled_profile.size() == 2,
			"disabled profiling does not allocate room or stage statistics",
		)
		build_queue.set_profiling_enabled(true)
		_expect(
			build_queue.is_profiling_enabled(),
			"performance tests can explicitly enable interior profiling",
		)
		_expect_equal(
			build_queue.get_frame_target_usec(),
			8000,
			"interior preparation has an explicit eight-millisecond frame target",
		)
	_expect_equal(
		roots.size(),
		0,
		"cold Town startup leaves every interior definition uninstantiated",
	)
	_expect_equal(
		_count_exterior_portals(town),
		TOWN_BASE.EXTERIOR_INTERIOR_PORTALS.size(),
		"cold Town startup still creates every lightweight exterior portal",
	)
	var player := town.get_node_or_null("Player") as CharacterBody2D
	_expect(player != null, "cold Town startup still creates the player")
	if player == null:
		await _finish(town, {"startup_msec": startup_msec})
		return
	await process_frame
	await process_frame
	await process_frame
	var cold_static_mib := (
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	)
	var cold_peak_static_mib := (
		float(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / 1048576.0
	)
	var cold_room_count := (town.get("_interior_roots") as Dictionary).size()
	var prewarm_longest_frame_usec := 0
	if build_queue != null:
		for _index in 30:
			var frame_started_usec := Time.get_ticks_usec()
			await process_frame
			prewarm_longest_frame_usec = maxi(
				prewarm_longest_frame_usec,
				Time.get_ticks_usec() - frame_started_usec,
			)
			if int(
				(build_queue.get_profile_snapshot() as Dictionary).get(
					"completed_room_count",
					0,
				)
			) >= 1:
				break
		_expect(
			int(
				(build_queue.get_profile_snapshot() as Dictionary).get(
					"completed_room_count",
					0,
				)
			) >= 1,
			"delayed prewarm completes its one nearest room in bounded frames",
		)
	var approach_spec := _portal_spec_for("dock_warehouse")
	var approach_door := approach_spec.get("door", Vector2.INF) as Vector2
	if not approach_door.is_finite():
		_expect(false, "dock warehouse portal exposes a finite door position")
	else:
		player.position = approach_door + Vector2(
			0.0,
			TOWN_BASE.INTERIOR_APPROACH_PREWARM_DISTANCE - 20.0,
		)
		town.call("_prewarm_approaching_interior")
		_expect(
			build_queue != null and build_queue.is_pending("dock_warehouse"),
			"approaching a cold room queues it before the door threshold",
		)
		for _index in 120:
			if (town.get("_interior_roots") as Dictionary).has("dock_warehouse"):
				break
			await process_frame
		_expect(
			(town.get("_interior_roots") as Dictionary).has("dock_warehouse"),
			"approaching room finishes before entering through its door",
		)
	var max_first_entry_msec := 0
	var first_entry_msec := 0
	var controller_checked := false
	for interior_id_value: Variant in UNIQUE_INTERIOR_PORTALS.keys():
		var interior_id := String(interior_id_value)
		var portal_id := String(UNIQUE_INTERIOR_PORTALS[interior_id])
		town.set("_blocked_exterior_reentry_portal_id", "")
		var first_entry_started := Time.get_ticks_msec()
		await town.call("_enter_interior", player, portal_id)
		var entry_msec := Time.get_ticks_msec() - first_entry_started
		if first_entry_msec == 0:
			first_entry_msec = entry_msec
		max_first_entry_msec = maxi(max_first_entry_msec, entry_msec)
		_expect_equal(
			String(town.get("_active_interior_id")),
			interior_id,
			"%s can be entered after lazy construction" % interior_id,
		)
		var room := (town.get("_interior_roots") as Dictionary).get(
			interior_id,
		) as InteriorRoom
		_expect(room != null, "%s is cached after first entry" % interior_id)
		if room == null:
			continue
		_expect(room.visible, "%s is visible while active" % interior_id)
		_expect(
			room.has_wall_occlusion(),
			"%s loads its pre-generated wall occlusion" % interior_id,
		)
		_expect(
			room.has_furniture_runtime(),
			"%s loads its furniture runtime" % interior_id,
		)
		_expect(
			not room.get_navigation_grid_data().is_empty(),
			"%s builds navigation data" % interior_id,
		)
		var navigation := room.get_navigation_grid_data()
		var entry_cell := _serialized_cell(navigation.get("entry_cell"))
		var exit_cell := _serialized_cell(navigation.get("exit_cell"))
		_expect(
			room.is_navigation_cell_walkable(entry_cell),
			"%s entry cell is actually walkable" % interior_id,
		)
		_expect(
			room.is_navigation_cell_walkable(exit_cell),
			"%s exit cell is actually walkable" % interior_id,
		)
		var entry_neighbors := room.get_walkable_navigation_neighbors(entry_cell)
		var neighbors_are_valid := not entry_neighbors.is_empty()
		for neighbor in entry_neighbors:
			neighbors_are_valid = (
				neighbors_are_valid
				and room.is_navigation_cell_walkable(neighbor)
				and absi(neighbor.x - entry_cell.x) + absi(neighbor.y - entry_cell.y) == 1
			)
		_expect(
			neighbors_are_valid,
			"%s navigation returns only walkable cardinal neighbors" % interior_id,
		)
		var layout_instances := (
			room.get_furniture_layout_snapshot().get("instances", []) as Array
		)
		_expect_equal(
			room.get_furniture_instance_count(),
			layout_instances.size(),
			"%s instantiates every authored furniture item" % interior_id,
		)
		var has_authored_furniture := not layout_instances.is_empty()
		_expect(
			(room.get_furniture_collision_shape_count() > 0)
			== has_authored_furniture,
			"%s furniture collision presence matches the authored layout" % interior_id,
		)
		var occupied_cells := room.get_furniture_occupied_cells()
		var furniture_cells_block_navigation := (
			not occupied_cells.is_empty() if has_authored_furniture else occupied_cells.is_empty()
		)
		for occupied_cell in occupied_cells:
			if room.is_navigation_cell_walkable(occupied_cell):
				furniture_cells_block_navigation = false
				break
		_expect(
			furniture_cells_block_navigation,
			"%s furniture occupancy matches and constrains navigation" % interior_id,
		)
		var wall := room.get_node_or_null("WallCollision") as StaticBody2D
		_expect(
			wall != null and wall.get_child_count() > 0,
			"%s builds wall collisions" % interior_id,
		)
		await physics_frame
		var wall_shape := _first_collision_shape(wall)
		_expect(
			wall_shape != null
			and _physics_point_hits(
				town,
				_shape_interior_global_point(wall_shape),
				wall,
			),
			"%s wall collision participates in the physics space" % interior_id,
		)
		var furniture_body := _first_furniture_collision_body(room)
		var furniture_shape := _first_collision_shape(furniture_body)
		_expect(
			(
				furniture_body != null
				and furniture_shape != null
				and _physics_point_hits(
					town,
					_shape_interior_global_point(furniture_shape),
					furniture_body,
				)
			)
			if has_authored_furniture
			else furniture_body == null,
			"%s furniture physics presence matches the authored layout" % interior_id,
		)
		var player_foot := (
			town.get_node("Player/PlayerOcclusionFootPoint") as Node2D
		)
		_expect_equal(
			player_foot.z_index,
			player.z_index,
			"%s entry keeps player occlusion depth synchronized" % interior_id,
		)
		if not controller_checked:
			var controller := town.get_node_or_null("InteriorOcclusionController")
			_expect(controller != null, "Town owns an event-driven occlusion controller")
			if controller != null:
				controller.set_process(false)
				controller.mark_subject_dirty(
					town.get_node("Player/PlayerOcclusionFootPoint") as Node2D,
				)
				_expect(
					controller.process_pending(),
					"one dirty subject state refreshes active room occlusion",
				)
				var static_refreshes := 0
				for _static_frame in 120:
					if controller.process_pending():
						static_refreshes += 1
				_expect_equal(
					static_refreshes,
					0,
					"120 static frames perform no resident scan or occlusion refresh",
				)
				controller.set_process(true)
			controller_checked = true
		await town.call("_exit_interior", player, interior_id)
		_expect(not room.visible, "%s hides after exit" % interior_id)
		_expect_equal(
			player_foot.z_index,
			player.z_index,
			"%s exit keeps player occlusion depth synchronized" % interior_id,
		)
		town.set("_blocked_exterior_reentry_portal_id", "")
		await town.call("_enter_interior", player, portal_id)
		_expect(
			(town.get("_interior_roots") as Dictionary).get(interior_id) == room,
			"%s re-entry reuses the cached room" % interior_id,
		)
		await town.call("_exit_interior", player, interior_id)
	_expect_equal(
		(town.get("_interior_roots") as Dictionary).size(),
		UNIQUE_INTERIOR_PORTALS.size(),
		"the regression exercises every unique interior definition",
	)
	await process_frame
	await process_frame
	var all_rooms_static_mib := (
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	)
	var all_rooms_peak_static_mib := (
		float(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / 1048576.0
	)
	var build_profile := (
		build_queue.get_profile_snapshot() as Dictionary
		if build_queue != null
		else {}
	)
	var max_room_cpu_usec := 0
	var max_room_wall_usec := 0
	var slowest_stage := ""
	var slowest_stage_usec := 0
	var max_stage_work_items := 0
	var all_collision_scans_are_batched := true
	var all_navigation_scans_are_batched := true
	var all_furniture_filters_are_batched := true
	var all_navigation_lookups_are_batched := true
	var all_furniture_asset_loads_are_staged := true
	for room_profile_value: Variant in (
		build_profile.get("rooms", {}) as Dictionary
	).values():
		var room_profile := room_profile_value as Dictionary
		var stage_calls := room_profile.get("stage_calls", {}) as Dictionary
		max_stage_work_items = maxi(
			max_stage_work_items,
			int(room_profile.get("max_stage_work_items", 0)),
		)
		all_collision_scans_are_batched = (
			all_collision_scans_are_batched
			and int(stage_calls.get("collision", 0)) > 1
		)
		all_navigation_scans_are_batched = (
			all_navigation_scans_are_batched
			and int(stage_calls.get("navigation", 0)) > 1
		)
		all_furniture_filters_are_batched = (
			all_furniture_filters_are_batched
			and int(stage_calls.get("furniture_navigation", 0)) > 1
		)
		all_navigation_lookups_are_batched = (
			all_navigation_lookups_are_batched
			and int(stage_calls.get("furniture_navigation_lookup", 0)) > 1
		)
		all_furniture_asset_loads_are_staged = (
			all_furniture_asset_loads_are_staged
			and int(stage_calls.get("furniture_begin", 0)) > 1
		)
		max_room_cpu_usec = maxi(
			max_room_cpu_usec,
			int(room_profile.get("cpu_usec", 0)),
		)
		max_room_wall_usec = maxi(
			max_room_wall_usec,
			int(room_profile.get("wall_usec", 0)),
		)
		for stage_name_value: Variant in (
			room_profile.get("stages", {}) as Dictionary
		).keys():
			var stage_name := String(stage_name_value)
			var stage_usec := int(
				(room_profile.get("stages", {}) as Dictionary).get(stage_name, 0),
			)
			if stage_usec > slowest_stage_usec:
				slowest_stage_usec = stage_usec
				slowest_stage = stage_name
	_expect_equal(
		build_profile.get("completed_room_count"),
		UNIQUE_INTERIOR_PORTALS.size(),
		"the build queue completes every unique interior definition",
	)
	_expect(
		prewarm_longest_frame_usec <= MAX_BLOCKING_FRAME_USEC,
		"delayed prewarm keeps the longest observed frame under 25 ms",
	)
	_expect(
		int(build_profile.get("max_frame_work_usec", 0))
		<= MAX_BLOCKING_FRAME_USEC,
		"all room preparation work stays under the blocking-frame ceiling",
	)
	_expect(
		int(build_profile.get("max_stage_usec", 0)) <= MAX_BLOCKING_FRAME_USEC,
		"no individual preparation stage can hide a long synchronous pause",
	)
	_expect(
		max_stage_work_items <= 16,
		"every preparation call respects the conservative 16-item batch ceiling",
	)
	_expect(
		all_collision_scans_are_batched,
		"every room advances collision preparation across multiple bounded batches",
	)
	_expect(
		all_navigation_scans_are_batched,
		"every room advances navigation preparation across multiple bounded batches",
	)
	_expect(
		all_furniture_filters_are_batched,
		"every room advances furniture navigation across multiple bounded batches",
	)
	_expect(
		all_navigation_lookups_are_batched,
		"every room advances the final navigation lookup across multiple bounded batches",
	)
	_expect(
		all_furniture_asset_loads_are_staged,
		"every room loads furniture data and textures across multiple resumable steps",
	)
	await _finish(town, {
		"startup_msec": startup_msec,
		"first_entry_msec": first_entry_msec,
		"max_first_entry_msec": max_first_entry_msec,
		"cold_static_mib": cold_static_mib,
		"cold_peak_static_mib": cold_peak_static_mib,
		"cold_room_count": cold_room_count,
		"prewarm_longest_frame_usec": prewarm_longest_frame_usec,
		"build_max_frame_usec": int(build_profile.get("max_frame_work_usec", 0)),
		"build_max_stage_usec": int(build_profile.get("max_stage_usec", 0)),
		"max_room_cpu_usec": max_room_cpu_usec,
		"max_room_wall_usec": max_room_wall_usec,
		"slowest_stage": slowest_stage,
		"all_rooms_static_mib": all_rooms_static_mib,
		"all_rooms_peak_static_mib": all_rooms_peak_static_mib,
	})


func _test_existing_wall_furniture_blocker_advances() -> void:
	var room := InteriorRoom.new()
	room.set("_navigation_grid_data", {
		"walkable_cells": [],
		"wall_cells": [[3, 4]],
	})
	var task := InteriorRoomPreparationTask.new(
		"",
		Vector2.ZERO,
		Vector2.ZERO,
		"",
		"",
		"",
		"",
		false,
	)
	task.furniture_navigation_phase = (
		InteriorRoomPreparationTask.FurnitureNavigationPhase.BLOCKED
	)
	task.furniture_blocked_cells = [Vector2i(3, 4)]
	task.furniture_wall_lookup = {Vector2i(3, 4): true}
	var processed := room.preparation_continue_furniture_navigation(task, 1)
	_expect_equal(
		processed,
		1,
		"an occupied cell already present in wall navigation consumes one work item",
	)
	_expect_equal(
		task.furniture_blocked_cursor,
		1,
		"an occupied cell already present in wall navigation advances the cursor",
	)
	room.free()


func _count_exterior_portals(town: Node) -> int:
	var count := 0
	for portal_spec in TOWN_BASE.EXTERIOR_INTERIOR_PORTALS:
		if town.get_node_or_null(String(portal_spec.get("node_name", ""))) != null:
			count += 1
	return count


func _portal_spec_for(interior_id: String) -> Dictionary:
	for portal_spec in TOWN_BASE.EXTERIOR_INTERIOR_PORTALS:
		if String(portal_spec.get("interior_id", "")) == interior_id:
			return portal_spec
	return {}


func _serialized_cell(value: Variant) -> Vector2i:
	var pair := value as Array
	return Vector2i(int(pair[0]), int(pair[1])) if pair.size() >= 2 else Vector2i.ZERO


func _first_collision_shape(body: StaticBody2D) -> CollisionShape2D:
	if not is_instance_valid(body):
		return null
	for child in body.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape != null:
			return child as CollisionShape2D
	return null


func _first_furniture_collision_body(room: InteriorRoom) -> StaticBody2D:
	for node in room.find_children(
		"ContinuousGroundCollision",
		"StaticBody2D",
		true,
		false,
	):
		if node is StaticBody2D:
			return node as StaticBody2D
	return null


func _shape_interior_global_point(collision: CollisionShape2D) -> Vector2:
	var local_point := Vector2.ZERO
	if collision.shape is ConvexPolygonShape2D:
		var points := (collision.shape as ConvexPolygonShape2D).points
		if not points.is_empty():
			for point in points:
				local_point += point
			local_point /= float(points.size())
	return collision.to_global(local_point)


func _physics_point_hits(
	host: Node,
	global_point: Vector2,
	expected_collider: CollisionObject2D,
) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_point
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for hit in host.get_world_2d().direct_space_state.intersect_point(query, 32):
		if (hit as Dictionary).get("collider") == expected_collider:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(
		actual == expected,
		"%s: expected %s, got %s" % [message, expected, actual],
	)


func _finish(town: Node, metrics: Dictionary) -> void:
	if is_instance_valid(town):
		town.queue_free()
	await process_frame
	await process_frame
	_prepare_audio_shutdown()
	if _failures.is_empty():
		print(
			"TOWN_INTERIOR_LAZY_LOADING_PASS checks=%d startupMsec=%d prewarmMaxFrameUsec=%d buildMaxFrameUsec=%d buildMaxStageUsec=%d slowestStage=%s maxRoomCpuUsec=%d maxRoomWallUsec=%d firstEntryMsec=%d maxFirstEntryMsec=%d coldRooms=%d coldStaticMiB=%.1f coldPeakStaticMiB=%.1f allRoomsStaticMiB=%.1f allRoomsPeakStaticMiB=%.1f"
			% [
				_checks,
				int(metrics.get("startup_msec", 0)),
				int(metrics.get("prewarm_longest_frame_usec", 0)),
				int(metrics.get("build_max_frame_usec", 0)),
				int(metrics.get("build_max_stage_usec", 0)),
				String(metrics.get("slowest_stage", "")),
				int(metrics.get("max_room_cpu_usec", 0)),
				int(metrics.get("max_room_wall_usec", 0)),
				int(metrics.get("first_entry_msec", 0)),
				int(metrics.get("max_first_entry_msec", 0)),
				int(metrics.get("cold_room_count", 0)),
				float(metrics.get("cold_static_mib", 0.0)),
				float(metrics.get("cold_peak_static_mib", 0.0)),
				float(metrics.get("all_rooms_static_mib", 0.0)),
				float(metrics.get("all_rooms_peak_static_mib", 0.0)),
			]
		)
		call_deferred("_quit_after_cleanup", 0)
		return
	for failure in _failures:
		printerr("TOWN_INTERIOR_LAZY_LOADING_FAIL: %s" % failure)
	printerr(
		"TOWN_INTERIOR_LAZY_LOADING_METRICS startupMsec=%d prewarmMaxFrameUsec=%d buildMaxFrameUsec=%d buildMaxStageUsec=%d slowestStage=%s maxRoomCpuUsec=%d maxRoomWallUsec=%d firstEntryMsec=%d maxFirstEntryMsec=%d"
		% [
			int(metrics.get("startup_msec", 0)),
			int(metrics.get("prewarm_longest_frame_usec", 0)),
			int(metrics.get("build_max_frame_usec", 0)),
			int(metrics.get("build_max_stage_usec", 0)),
			String(metrics.get("slowest_stage", "")),
			int(metrics.get("max_room_cpu_usec", 0)),
			int(metrics.get("max_room_wall_usec", 0)),
			int(metrics.get("first_entry_msec", 0)),
			int(metrics.get("max_first_entry_msec", 0)),
		]
	)
	call_deferred("_quit_after_cleanup", 1)


func _quit_after_cleanup(exit_code: int) -> void:
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	quit(exit_code)


func _prepare_audio_shutdown() -> void:
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
