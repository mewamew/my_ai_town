# 正式地图的通用室内壳。
# 具体底图、入口点和出口点由 TownBase.gd 的室内配置注入。
class_name InteriorRoom
extends Node2D

const FLOOR_PROFILES := preload("res://world/maps/town/interiors/InteriorFloorProfiles.gd")
const ROOM_GEOMETRY := preload("res://world/maps/town/interiors/InteriorRoomGeometry.gd")
const WALL_OCCLUSION_SCRIPT := preload("res://world/maps/town/interiors/InteriorWallOcclusion.gd")
const FURNITURE_RUNTIME_SCRIPT := preload(
	"res://world/maps/town/interiors/InteriorFurnitureRuntime.gd"
)
const GEOMETRY_LOAD_TASK := preload(
	"res://world/maps/town/interiors/InteriorGeometryLoadTask.gd"
)
const PREPARATION_WORK_ITEM_TARGET_USEC := (
	InteriorRoomPreparationTask.WORK_ITEM_TARGET_USEC
)

var _floor_profile_id := ""
var _geometry_path := ""
var _occlusion_path := ""
var _geometry_data: Dictionary = {}
var _navigation_grid_data: Dictionary = {}
var _base_navigation_grid_data: Dictionary = {}
var _walkable_cell_lookup := {}
var _geometry_debug_visible := false
var _wall_occlusion: InteriorWallOcclusion
var _furniture_manifest_path := ""
var _furniture_layout_path := ""
var _furniture_runtime: InteriorFurnitureRuntime
var _preparation_task: InteriorRoomPreparationTask


func configure(
	shell_path: String,
	entry_point: Vector2,
	exit_point: Vector2,
	geometry_path: String = "",
	occlusion_path: String = "",
	furniture_manifest_path: String = "",
	furniture_layout_path: String = ""
) -> void:
	if not begin_preparation(
		shell_path,
		entry_point,
		exit_point,
		geometry_path,
		occlusion_path,
		furniture_manifest_path,
		furniture_layout_path,
	):
		return
	while not is_preparation_complete() and not has_preparation_failed():
		prepare_next_stage()


func begin_preparation(
	shell_path: String,
	entry_point: Vector2,
	exit_point: Vector2,
	geometry_path: String = "",
	occlusion_path: String = "",
	furniture_manifest_path: String = "",
	furniture_layout_path: String = "",
	threaded_shell_load: bool = false,
) -> bool:
	if _preparation_task != null:
		return false
	_preparation_task = InteriorRoomPreparationTask.new(
		shell_path,
		entry_point,
		exit_point,
		geometry_path,
		occlusion_path,
		furniture_manifest_path,
		furniture_layout_path,
		threaded_shell_load,
	)
	return true


func prepare_next_stage(
	deadline_usec: int = 0,
	collect_metrics: bool = false,
) -> InteriorRoomPreparationTask.AdvanceStatus:
	if _preparation_task == null:
		return null
	return _preparation_task.advance(self, deadline_usec, collect_metrics)


func is_preparation_complete() -> bool:
	return _preparation_task != null and _preparation_task.is_complete()


func has_preparation_failed() -> bool:
	return _preparation_task != null and _preparation_task.has_failed()


func get_preparation_error() -> String:
	return _preparation_task.error if _preparation_task != null else ""


func cancel_preparation() -> void:
	if _preparation_task != null:
		_preparation_task.cancel()
	if is_instance_valid(_wall_occlusion):
		_wall_occlusion.cancel_configuration()


func preparation_request_shell(task: InteriorRoomPreparationTask) -> void:
	var shell := get_node("RoomShell") as Sprite2D
	if task.threaded_load:
		if (
			not ResourceLoader.exists(task.shell_path, "Texture2D")
			or ResourceLoader.load_threaded_request(
				task.shell_path,
				"Texture2D",
				true,
			) != OK
			):
				task.fail("Interior shell could not be queued: %s" % task.shell_path)
				return
		task.shell_request_active = true
		task.stage = InteriorRoomPreparationTask.Stage.SHELL_WAIT
		return
	shell.texture = _load_texture(task.shell_path)
	if shell.texture == null:
		task.fail("Interior shell is missing: %s" % task.shell_path)
		return
	task.stage = InteriorRoomPreparationTask.Stage.GEOMETRY_REQUEST


func preparation_poll_shell(task: InteriorRoomPreparationTask) -> void:
	var status := ResourceLoader.load_threaded_get_status(task.shell_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		task.fail("Interior shell threaded load failed: %s" % task.shell_path)
		return
	var shell := get_node("RoomShell") as Sprite2D
	shell.texture = ResourceLoader.load_threaded_get(task.shell_path) as Texture2D
	task.shell_request_active = false
	if shell.texture == null:
		task.fail("Interior shell is missing: %s" % task.shell_path)
		return
	task.stage = InteriorRoomPreparationTask.Stage.GEOMETRY_REQUEST


func preparation_request_geometry(task: InteriorRoomPreparationTask) -> void:
	_geometry_path = task.geometry_path
	if task.threaded_load and not _geometry_path.is_empty():
		task.geometry_worker = GEOMETRY_LOAD_TASK.new() as InteriorGeometryLoadTask
		task.geometry_worker_id = WorkerThreadPool.add_task(
			task.geometry_worker.run.bind(_geometry_path),
			false,
			"Load interior geometry",
		)
		task.stage = InteriorRoomPreparationTask.Stage.GEOMETRY_WAIT
		return
	_geometry_data = ROOM_GEOMETRY.load_geometry(_geometry_path)
	task.stage = InteriorRoomPreparationTask.Stage.GEOMETRY_APPLY

func preparation_poll_geometry(task: InteriorRoomPreparationTask) -> void:
	if task.geometry_worker_id < 0 or task.geometry_worker == null:
		task.fail("Interior room geometry task is missing")
		return
	if not WorkerThreadPool.is_task_completed(task.geometry_worker_id):
		return
	WorkerThreadPool.wait_for_task_completion(task.geometry_worker_id)
	var loaded := task.geometry_worker.take_result()
	_geometry_data = loaded.get("geometry", {}) as Dictionary
	task.geometry_setup = loaded.get("setup", {}) as Dictionary
	task.geometry_worker_id = -1
	task.geometry_worker = null
	task.stage = InteriorRoomPreparationTask.Stage.GEOMETRY_APPLY


func preparation_apply_geometry(task: InteriorRoomPreparationTask) -> void:
	var shell := get_node("RoomShell") as Sprite2D
	shell.position = Vector2.ZERO
	if not _geometry_path.is_empty() and _geometry_data.is_empty():
		task.fail("Interior room geometry is missing: %s" % _geometry_path)
		return
	if not _geometry_data.is_empty():
		var setup := task.geometry_setup
		if setup.is_empty():
			# 同步兼容路径没有工作线程；正式队列在工作线程预计算此结果。
			setup = ROOM_GEOMETRY.room_setup_from_loaded_geometry(
				_geometry_data,
			) as Dictionary
		shell.position = setup.get("shell_position") as Vector2
		task.entry_point = setup.get("entry_point") as Vector2
		task.exit_point = setup.get("exit_point") as Vector2
		task.geometry_setup.clear()
	(get_node("IndoorEntryPoint") as Marker2D).position = task.entry_point
	(get_node("IndoorExitPoint") as Marker2D).position = task.exit_point
	if not _geometry_data.is_empty():
		_floor_profile_id = str(_geometry_data.get("room_id", ""))
	else:
		_floor_profile_id = FLOOR_PROFILES.profile_id_from_shell_path(task.shell_path)
		if not FLOOR_PROFILES.has_profile(_floor_profile_id):
			task.fail(
				"Interior floor profile is missing: %s" % _floor_profile_id,
			)
			return
	task.stage = InteriorRoomPreparationTask.Stage.COLLISION


func preparation_continue_navigation(
	task: InteriorRoomPreparationTask,
	max_work_items: int,
) -> int:
	if not _geometry_data.is_empty():
		if task.navigation_scan.is_empty():
			task.navigation_scan = (
				ROOM_GEOMETRY.begin_navigation_grid_scan(
					_geometry_data,
					task.entry_point,
					task.exit_point,
				)
			)
		var result := ROOM_GEOMETRY.continue_navigation_grid_scan(
			task.navigation_scan,
			max_work_items,
		) as Dictionary
		if result.get("complete") != true:
			return int(result.get("processed", 0))
		task.navigation_scan = {}
		if result.get("failed") == true:
			task.fail("Interior navigation grid could not be built")
			return int(result.get("processed", 0))
		_navigation_grid_data = result.get("data", {}) as Dictionary
	else:
		# 旧壳配置仅用于兼容工具；正式十间室内全部走已验证几何的游标扫描。
		_navigation_grid_data = FLOOR_PROFILES.build_navigation_grid_data(
			_floor_profile_id,
			task.entry_point,
			task.exit_point,
		)
	_base_navigation_grid_data = _navigation_grid_data.duplicate(true)
	task.stage = InteriorRoomPreparationTask.Stage.OCCLUSION_BEGIN
	return 1


func preparation_begin_occlusion(task: InteriorRoomPreparationTask) -> void:
	var shell := get_node("RoomShell") as Sprite2D
	_occlusion_path = _resolve_occlusion_path(_geometry_path, task.occlusion_path)
	if not _occlusion_path.is_empty() and not _geometry_data.is_empty():
		_wall_occlusion = WALL_OCCLUSION_SCRIPT.new() as InteriorWallOcclusion
		add_child(_wall_occlusion)
		var begun := (
			_wall_occlusion.begin_configuration_threaded(
				shell,
				_geometry_data,
				_geometry_path,
				_occlusion_path,
				task.shell_path,
			)
			if task.threaded_load
			else _wall_occlusion.begin_configuration(
				shell,
				_geometry_data,
				_geometry_path,
				_occlusion_path,
				task.shell_path,
			)
		)
		if not begun:
			_wall_occlusion.queue_free()
			_wall_occlusion = null
			task.fail("Interior wall occlusion could not be loaded")
			return
		task.stage = InteriorRoomPreparationTask.Stage.OCCLUSION_SEGMENT
		return
	task.stage = InteriorRoomPreparationTask.Stage.FURNITURE_BEGIN


func preparation_continue_occlusion(task: InteriorRoomPreparationTask) -> void:
	var result := _wall_occlusion.continue_configuration() as Dictionary
	task.stage_waiting = result.get("waiting") == true
	if result.get("failed") == true:
		task.fail("Interior wall occlusion segment could not be loaded")
		return
	if result.get("complete") == true:
		task.stage = InteriorRoomPreparationTask.Stage.FURNITURE_BEGIN


func preparation_begin_furniture(task: InteriorRoomPreparationTask) -> void:
	_furniture_manifest_path = task.furniture_manifest_path
	_furniture_layout_path = task.furniture_layout_path
	if not _furniture_manifest_path.is_empty() and not _furniture_layout_path.is_empty():
		var load_status := task.continue_furniture_asset_loading()
		if load_status != InteriorRoomPreparationTask.AssetLoadStatus.READY:
			return
		var prepared := task.take_furniture_prepared_data()
		_furniture_runtime = FURNITURE_RUNTIME_SCRIPT.new() as InteriorFurnitureRuntime
		_furniture_runtime.name = "FurnitureRuntime"
		add_child(_furniture_runtime)
		_furniture_runtime.connect(
			"layout_changed",
			_on_furniture_layout_changed
		)
		if not bool(_furniture_runtime.begin_configuration_prepared(
			_furniture_manifest_path,
			_furniture_layout_path,
			prepared.get("definitions", {}) as Dictionary,
			prepared.get("layout", {}) as Dictionary,
			prepared.get("light_image") as Image,
			prepared.get("textures", {}) as Dictionary,
		)):
			var details := PackedStringArray()
			for error in _furniture_runtime.get_errors() as PackedStringArray:
				details.append(error)
			task.fail(
				"Interior furniture layout could not be loaded: %s (%s)"
				% [_furniture_layout_path, "; ".join(details)],
			)
			return
		task.stage = InteriorRoomPreparationTask.Stage.FURNITURE_INSTANCE
		return
	begin_preparation_navigation_lookup(
		task,
		InteriorRoomPreparationTask.Stage.NAVIGATION_LOOKUP,
		InteriorRoomPreparationTask.Stage.COMPLETE,
	)


func preparation_continue_furniture(task: InteriorRoomPreparationTask) -> void:
	var result := _furniture_runtime.continue_configuration() as Dictionary
	if result.get("failed") == true:
		var details := _furniture_runtime.get_errors() as PackedStringArray
		task.fail(
			"Interior furniture instance could not be loaded: %s"
			% "; ".join(details),
		)
		return
	if result.get("complete") == true:
		_furniture_runtime.begin_occupied_room_cell_scan()
		task.begin_furniture_navigation()
		task.stage = InteriorRoomPreparationTask.Stage.FURNITURE_NAVIGATION


func get_floor_profile_id() -> String:
	return _floor_profile_id


func get_geometry_path() -> String:
	return _geometry_path


func get_occlusion_path() -> String:
	return _occlusion_path


func get_furniture_manifest_path() -> String:
	return _furniture_manifest_path


func get_furniture_layout_path() -> String:
	return _furniture_layout_path


func get_furniture_layout_snapshot() -> Dictionary:
	if not is_instance_valid(_furniture_runtime):
		return {}
	return _furniture_runtime.get_layout_snapshot() as Dictionary


func has_furniture_runtime() -> bool:
	return is_instance_valid(_furniture_runtime)


func get_furniture_instance_count() -> int:
	if not is_instance_valid(_furniture_runtime):
		return 0
	return int(_furniture_runtime.get_instance_count())


func get_furniture_collision_shape_count() -> int:
	if not is_instance_valid(_furniture_runtime):
		return 0
	return int(_furniture_runtime.get_collision_shape_count())


func get_furniture_occupied_cells() -> Array[Vector2i]:
	if not is_instance_valid(_furniture_runtime):
		return []
	return _furniture_runtime.get_occupied_room_cells() as Array[Vector2i]


func get_furniture_errors() -> PackedStringArray:
	if not is_instance_valid(_furniture_runtime):
		return PackedStringArray()
	return _furniture_runtime.get_errors() as PackedStringArray


func set_furniture_layout_path(layout_path: String) -> bool:
	if layout_path.is_empty():
		return false
	if not is_instance_valid(_furniture_runtime):
		return false
	if layout_path == _furniture_layout_path:
		return true
	if not bool(_furniture_runtime.set_layout_path(layout_path)):
		return false
	_furniture_layout_path = layout_path
	return true


func apply_furniture_layout(layout: Dictionary) -> Dictionary:
	if not is_instance_valid(_furniture_runtime):
		return {
			"ok": false,
			"changed": false,
			"errors": PackedStringArray(["室内尚未加载家具运行时"]),
		}
	return _furniture_runtime.apply_layout(layout) as Dictionary


func upsert_furniture_instance(instance: Dictionary) -> Dictionary:
	if not is_instance_valid(_furniture_runtime):
		return {
			"ok": false,
			"changed": false,
			"errors": PackedStringArray(["室内尚未加载家具运行时"]),
		}
	return _furniture_runtime.upsert_instance(instance) as Dictionary


func remove_furniture_instance(instance_id: String) -> Dictionary:
	if not is_instance_valid(_furniture_runtime):
		return {
			"ok": false,
			"changed": false,
			"errors": PackedStringArray(["室内尚未加载家具运行时"]),
		}
	return _furniture_runtime.remove_instance(instance_id) as Dictionary


func create_world_layout_projection(base_projection: Dictionary) -> Dictionary:
	if not is_instance_valid(_furniture_runtime):
		return {
			"ok": false,
			"errors": PackedStringArray(["室内尚未加载家具运行时"]),
			"projection": {},
		}
	var navigation := (
		base_projection.get("navigation", {}) as Dictionary
	).duplicate(true)
	navigation["cellSize"] = int(_navigation_grid_data.get("cell_size", 0))
	navigation["walkableCells"] = (
		_navigation_grid_data.get("walkable_cells", []) as Array
	).duplicate(true)
	var identity := {
		"spaceId": str(base_projection.get("spaceId", "")),
		"placeName": str(base_projection.get("placeName", "")),
		"regionId": str(base_projection.get("regionId", "")),
		"roomId": str(base_projection.get("roomId", "")),
	}
	var prop_result := _furniture_runtime.create_agent_prop_projection(base_projection.get("props", []) as Array,
		identity,
		navigation.get("walkableCells", []) as Array,) as Dictionary
	if prop_result.get("ok") != true:
		return {
			"ok": false,
			"errors": prop_result.get("errors", PackedStringArray()),
			"projection": {},
		}
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"projection": {
			"spaceId": identity["spaceId"],
			"placeName": identity["placeName"],
			"regionId": identity["regionId"],
			"roomId": identity["roomId"],
			"navigation": navigation,
			"props": (prop_result.get("props", []) as Array).duplicate(true),
		},
	}


func uses_room_geometry() -> bool:
	return not _geometry_data.is_empty()


func get_navigation_grid_data() -> Dictionary:
	return _navigation_grid_data.duplicate(true)


func local_position_to_navigation_cell(local_position: Vector2) -> Vector2i:
	if not _geometry_data.is_empty():
		return ROOM_GEOMETRY.local_position_to_cell(local_position)
	return FLOOR_PROFILES.local_position_to_cell(local_position)


func is_local_position_walkable(local_position: Vector2) -> bool:
	return is_navigation_cell_walkable(local_position_to_navigation_cell(local_position))


func is_navigation_cell_walkable(cell: Vector2i) -> bool:
	return _walkable_cell_lookup.has(cell)


func get_walkable_navigation_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for offset in FLOOR_PROFILES.CARDINAL_OFFSETS:
		var candidate: Vector2i = cell + offset
		if is_navigation_cell_walkable(candidate):
			neighbors.append(candidate)
	return neighbors


func set_geometry_debug_visible(value: bool) -> void:
	_geometry_debug_visible = value
	if is_instance_valid(_wall_occlusion):
		_wall_occlusion.set_debug_visible(value)
	if is_instance_valid(_furniture_runtime):
		_furniture_runtime.set_debug_visible(value)
	queue_redraw()


func is_geometry_debug_visible() -> bool:
	return _geometry_debug_visible


func has_wall_occlusion() -> bool:
	return is_instance_valid(_wall_occlusion)


func update_wall_occlusion_subjects(subjects: Array[Node2D]) -> bool:
	if not is_instance_valid(_wall_occlusion):
		return false
	return bool(_wall_occlusion.update_for_subjects(subjects))


func upsert_wall_occlusion_subject(subject: Node2D) -> bool:
	if not is_instance_valid(_wall_occlusion):
		return false
	return bool(_wall_occlusion.upsert_subject(subject))


func remove_wall_occlusion_subject(subject_id: int) -> bool:
	if not is_instance_valid(_wall_occlusion):
		return false
	return bool(_wall_occlusion.remove_subject(subject_id))


func clear_wall_occlusion_subjects() -> bool:
	if not is_instance_valid(_wall_occlusion):
		return false
	return bool(_wall_occlusion.clear_subjects())


func get_floor_local_bounds() -> Rect2:
	if not _geometry_data.is_empty():
		return ROOM_GEOMETRY.get_floor_local_bounds(_geometry_data)
	var navigation_size := _navigation_grid_data.get("size", [0, 0]) as Array
	var origin_cell := _navigation_grid_data.get("origin_cell", [0, 0]) as Array
	if navigation_size.size() < 2 or origin_cell.size() < 2:
		return Rect2()
	return Rect2(
		Vector2(float(origin_cell[0]), float(origin_cell[1])) * FLOOR_PROFILES.GRID_SIZE,
		Vector2(float(navigation_size[0]), float(navigation_size[1])) * FLOOR_PROFILES.GRID_SIZE
	)


func get_shell_local_bounds() -> Rect2:
	if not _geometry_data.is_empty():
		return ROOM_GEOMETRY.get_shell_local_bounds(_geometry_data)
	var shell := get_node("RoomShell") as Sprite2D
	if shell.texture == null:
		return Rect2()
	var size := shell.texture.get_size()
	return Rect2(shell.position - size * 0.5, size)


func _draw() -> void:
	if not _geometry_debug_visible:
		return
	var grid_size := (
		ROOM_GEOMETRY.GRID_SIZE
		if not _geometry_data.is_empty()
		else FLOOR_PROFILES.GRID_SIZE
	)
	for serialized_cell in _navigation_grid_data.get("walkable_cells", []) as Array:
		var cell := Vector2i(int(serialized_cell[0]), int(serialized_cell[1]))
		var rect := Rect2(Vector2(cell) * grid_size, Vector2.ONE * grid_size)
		draw_rect(rect, Color(0.20, 0.82, 0.46, 0.18), true)
		draw_rect(rect, Color(0.28, 0.95, 0.60, 0.48), false, 1.0)
	var blocker_rects: Array[Rect2] = (
		ROOM_GEOMETRY.get_boundary_collision_rects(_geometry_data)
		if not _geometry_data.is_empty()
		else FLOOR_PROFILES.get_boundary_collision_rects(_floor_profile_id)
	)
	for rect in blocker_rects:
		draw_rect(rect, Color(0.93, 0.18, 0.22, 0.25), true)
		draw_rect(rect, Color(1.0, 0.28, 0.32, 0.72), false, 2.0)
	draw_circle(
		(get_node("IndoorEntryPoint") as Marker2D).position,
		11.0,
		Color(0.10, 0.88, 1.0, 0.95)
	)
	draw_circle(
		(get_node("IndoorExitPoint") as Marker2D).position,
		9.0,
		Color(1.0, 0.34, 0.72, 0.95)
	)


func preparation_continue_collision(
	task: InteriorRoomPreparationTask,
	max_work_items: int,
) -> int:
	var processed := 0
	if task.collision_rects.is_empty():
		if not _geometry_data.is_empty():
			if task.collision_scan.is_empty():
				task.collision_scan = (
					ROOM_GEOMETRY.begin_boundary_collision_scan(_geometry_data)
				)
			var result := ROOM_GEOMETRY.continue_boundary_collision_scan(
				task.collision_scan,
				max_work_items,
			) as Dictionary
			processed += int(result.get("processed", 0))
			if result.get("complete") != true:
				return processed
			task.collision_scan = {}
			task.collision_rects = result.get("rects", []) as Array
		else:
			# 旧壳配置仅用于兼容工具；正式室内使用上面的游标扫描。
			task.collision_rects = (
				FLOOR_PROFILES.get_boundary_collision_rects(_floor_profile_id)
			)
	var wall := get_node("WallCollision") as StaticBody2D
	while (
		task.collision_cursor < task.collision_rects.size()
		and processed < max_work_items
	):
		var rect := task.collision_rects[task.collision_cursor] as Rect2
		var collision := CollisionShape2D.new()
		collision.name = "WallSection_%02d" % task.collision_cursor
		collision.position = rect.get_center()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collision.shape = shape
		wall.add_child(collision)
		task.collision_cursor += 1
		processed += 1
	if task.collision_cursor >= task.collision_rects.size():
		task.collision_rects = []
		task.collision_cursor = 0
		task.stage = InteriorRoomPreparationTask.Stage.NAVIGATION
	return processed


func begin_preparation_navigation_lookup(
	task: InteriorRoomPreparationTask,
	stage: InteriorRoomPreparationTask.Stage,
	next_stage: InteriorRoomPreparationTask.Stage,
) -> void:
	_walkable_cell_lookup = {}
	task.begin_navigation_lookup(
		_navigation_grid_data.get("walkable_cells", []) as Array,
		next_stage,
	)
	task.stage = stage


func preparation_continue_navigation_lookup(
	task: InteriorRoomPreparationTask,
	max_work_items: int,
) -> int:
	var processed := 0
	while (
		task.navigation_lookup_cursor < task.navigation_lookup_cells.size()
		and processed < max_work_items
	):
		var serialized_cell := (
			task.navigation_lookup_cells[task.navigation_lookup_cursor] as Array
		)
		if serialized_cell.size() >= 2:
			_walkable_cell_lookup[Vector2i(
				int(serialized_cell[0]),
				int(serialized_cell[1]),
			)] = true
		task.navigation_lookup_cursor += 1
		processed += 1
	if task.navigation_lookup_cursor >= task.navigation_lookup_cells.size():
		var next_stage := task.navigation_lookup_next_stage
		task.clear_navigation_lookup()
		if next_stage == InteriorRoomPreparationTask.Stage.COMPLETE:
			queue_redraw()
			task.complete()
		else:
			task.stage = next_stage
	return processed


func _rebuild_navigation_lookup() -> void:
	_walkable_cell_lookup.clear()
	for serialized_cell in _navigation_grid_data.get("walkable_cells", []) as Array:
		if serialized_cell is Array and serialized_cell.size() >= 2:
			_walkable_cell_lookup[Vector2i(
				int(serialized_cell[0]),
				int(serialized_cell[1])
			)] = true


func preparation_continue_furniture_navigation(
	task: InteriorRoomPreparationTask,
	max_work_items: int,
) -> int:
	if (
		task.furniture_navigation_phase
		== InteriorRoomPreparationTask.FurnitureNavigationPhase.OCCUPANCY
	):
		var occupancy_result := (
			_furniture_runtime.continue_occupied_room_cell_scan(max_work_items)
			as Dictionary
		)
		var processed := int(occupancy_result.get("processed", 0))
		if occupancy_result.get("complete") != true:
			return processed
		task.furniture_blocked_cells = (
			_furniture_runtime.get_scanned_occupied_room_cells()
		)
		task.furniture_blocked_lookup = (
			_furniture_runtime.get_scanned_occupied_room_cell_lookup()
		)
		task.furniture_filtered_walkable = []
		task.furniture_walkable_cursor = 0
		task.furniture_navigation_phase = (
			InteriorRoomPreparationTask.FurnitureNavigationPhase.WALKABLE
		)
		return processed
	if (
		task.furniture_navigation_phase
		== InteriorRoomPreparationTask.FurnitureNavigationPhase.WALKABLE
	):
		var source_walkable := (
			_navigation_grid_data.get("walkable_cells", []) as Array
		)
		var processed := 0
		while (
			task.furniture_walkable_cursor < source_walkable.size()
			and processed < max_work_items
		):
			var serialized_cell := (
				source_walkable[task.furniture_walkable_cursor] as Array
			)
			var cell := Vector2i(int(serialized_cell[0]), int(serialized_cell[1]))
			if not task.furniture_blocked_lookup.has(cell):
				task.furniture_filtered_walkable.append(serialized_cell)
			task.furniture_walkable_cursor += 1
			processed += 1
		if task.furniture_walkable_cursor >= source_walkable.size():
			task.furniture_wall_lookup = {}
			task.furniture_wall_cursor = 0
			task.furniture_navigation_phase = (
				InteriorRoomPreparationTask.FurnitureNavigationPhase.WALLS
			)
		return processed
	if (
		task.furniture_navigation_phase
		== InteriorRoomPreparationTask.FurnitureNavigationPhase.WALLS
	):
		var wall_cells := _navigation_grid_data.get("wall_cells", []) as Array
		var processed := 0
		while (
			task.furniture_wall_cursor < wall_cells.size()
			and processed < max_work_items
		):
			var serialized_cell := wall_cells[task.furniture_wall_cursor] as Array
			task.furniture_wall_lookup[Vector2i(
				int(serialized_cell[0]),
				int(serialized_cell[1]),
			)] = true
			task.furniture_wall_cursor += 1
			processed += 1
		if task.furniture_wall_cursor >= wall_cells.size():
			task.furniture_blocked_cursor = 0
			task.furniture_navigation_phase = (
				InteriorRoomPreparationTask.FurnitureNavigationPhase.BLOCKED
			)
		return processed
	var wall_cells := _navigation_grid_data.get("wall_cells", []) as Array
	var processed := 0
	while (
		task.furniture_blocked_cursor < task.furniture_blocked_cells.size()
		and processed < max_work_items
	):
		var cell := (
			task.furniture_blocked_cells[task.furniture_blocked_cursor] as Vector2i
		)
		if not task.furniture_wall_lookup.has(cell):
			task.furniture_wall_lookup[cell] = true
			wall_cells.append([cell.x, cell.y])
		task.furniture_blocked_cursor += 1
		processed += 1
	if task.furniture_blocked_cursor >= task.furniture_blocked_cells.size():
		_navigation_grid_data["walkable_cells"] = task.furniture_filtered_walkable
		begin_preparation_navigation_lookup(
			task,
			InteriorRoomPreparationTask.Stage.FURNITURE_NAVIGATION_LOOKUP,
			InteriorRoomPreparationTask.Stage.COMPLETE,
		)
	return processed


func _apply_furniture_navigation_blockers() -> void:
	if not is_instance_valid(_furniture_runtime):
		return
	var blocked_lookup := {}
	for cell in _furniture_runtime.get_occupied_room_cells() as Array[Vector2i]:
		blocked_lookup[cell] = true
	var filtered_walkable: Array = []
	for serialized_cell in _navigation_grid_data.get("walkable_cells", []) as Array:
		var cell := Vector2i(int(serialized_cell[0]), int(serialized_cell[1]))
		if not blocked_lookup.has(cell):
			filtered_walkable.append(serialized_cell)
	var wall_cells: Array = (_navigation_grid_data.get("wall_cells", []) as Array).duplicate(true)
	var wall_lookup := {}
	for serialized_cell in wall_cells:
		wall_lookup["%d,%d" % [int(serialized_cell[0]), int(serialized_cell[1])]] = true
	for cell in blocked_lookup.keys():
		var typed_cell := cell as Vector2i
		var key := "%d,%d" % [typed_cell.x, typed_cell.y]
		if not wall_lookup.has(key):
			wall_cells.append([typed_cell.x, typed_cell.y])
	_navigation_grid_data["walkable_cells"] = filtered_walkable
	_navigation_grid_data["wall_cells"] = wall_cells
	_rebuild_navigation_lookup()


func _on_furniture_layout_changed(snapshot: Dictionary) -> void:
	_navigation_grid_data = _base_navigation_grid_data.duplicate(true)
	_apply_furniture_navigation_blockers()
	# 局部灯光、炉火和蒸汽必须读取家具资产中精确登记的效果锚点。
	# 在效果锚点合同落地前，不允许用家具根节点加猜测偏移生成视觉效果。
	@warning_ignore("unused_parameter")
	var _unused_snapshot := snapshot
	queue_redraw()


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
		if imported != null:
			return imported
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _resolve_occlusion_path(geometry_path: String, configured_path: String) -> String:
	if not configured_path.is_empty():
		return configured_path
	if geometry_path.is_empty():
		return ""
	var sibling_path := geometry_path.get_base_dir().path_join("wall_occlusion.json")
	return sibling_path if FileAccess.file_exists(sibling_path) else ""
