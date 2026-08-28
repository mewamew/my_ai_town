class_name InteriorRoomPreparationTask
extends RefCounted

const FURNITURE_LOAD_TASK := preload(
	"res://world/maps/town/interiors/InteriorFurnitureLoadTask.gd"
)

enum Stage {
	SHELL_REQUEST,
	SHELL_WAIT,
	GEOMETRY_REQUEST,
	GEOMETRY_WAIT,
	GEOMETRY_APPLY,
	COLLISION,
	NAVIGATION,
	NAVIGATION_LOOKUP,
	OCCLUSION_BEGIN,
	OCCLUSION_SEGMENT,
	FURNITURE_BEGIN,
	FURNITURE_INSTANCE,
	FURNITURE_NAVIGATION,
	FURNITURE_NAVIGATION_LOOKUP,
	COMPLETE,
	FAILED,
}

enum FurnitureNavigationPhase {
	OCCUPANCY,
	WALKABLE,
	WALLS,
	BLOCKED,
}

enum AssetLoadStatus {
	WAITING,
	READY,
	FAILED,
}

const WORK_ITEM_TARGET_USEC := 500
const MAX_WORK_ITEMS := 16

class AdvanceStatus:
	extends RefCounted
	var complete := false
	var failed := false
	var waiting := false
	var error := ""
	var stage_name := ""
	var elapsed_usec := 0
	var work_items := 0
	var work_item_limit := 0

	func reset() -> void:
		complete = false
		failed = false
		waiting = false
		error = ""
		stage_name = ""
		elapsed_usec = 0
		work_items = 0
		work_item_limit = 0

var shell_path := ""
var entry_point := Vector2.ZERO
var exit_point := Vector2.ZERO
var geometry_path := ""
var occlusion_path := ""
var furniture_manifest_path := ""
var furniture_layout_path := ""
var threaded_load := false

var stage := Stage.SHELL_REQUEST
var error := ""
var geometry_worker: InteriorGeometryLoadTask
var geometry_worker_id := -1
var geometry_setup: Dictionary = {}
var collision_scan: Dictionary = {}
var collision_rects: Array = []
var collision_cursor := 0
var navigation_scan: Dictionary = {}
var navigation_lookup_cells: Array = []
var navigation_lookup_cursor := 0
var navigation_lookup_next_stage := Stage.COMPLETE
var furniture_load_worker: FURNITURE_LOAD_TASK
var furniture_load_worker_id := -1
var furniture_prepared_data: Dictionary = {}
var furniture_texture_paths: Array[String] = []
var furniture_texture_request_cursor := 0
var furniture_texture_poll_cursor := 0
var furniture_navigation_phase := FurnitureNavigationPhase.OCCUPANCY
var furniture_blocked_cells: Array = []
var furniture_blocked_lookup: Dictionary = {}
var furniture_filtered_walkable: Array = []
var furniture_walkable_cursor := 0
var furniture_wall_lookup: Dictionary = {}
var furniture_wall_cursor := 0
var furniture_blocked_cursor := 0
var stage_waiting := false
var shell_request_active := false
var _advance_status := AdvanceStatus.new()


func _init(
	shell_path_value: String,
	entry_point_value: Vector2,
	exit_point_value: Vector2,
	geometry_path_value: String,
	occlusion_path_value: String,
	furniture_manifest_path_value: String,
	furniture_layout_path_value: String,
	threaded_load_value: bool,
) -> void:
	shell_path = shell_path_value
	entry_point = entry_point_value
	exit_point = exit_point_value
	geometry_path = geometry_path_value
	occlusion_path = occlusion_path_value
	furniture_manifest_path = furniture_manifest_path_value
	furniture_layout_path = furniture_layout_path_value
	threaded_load = threaded_load_value


func advance(
	room: InteriorRoom,
	deadline_usec: int = 0,
	collect_metrics: bool = false,
) -> AdvanceStatus:
	_advance_status.reset()
	if is_complete() or has_failed():
		_advance_status.complete = is_complete()
		_advance_status.failed = has_failed()
		_advance_status.error = error
		return _advance_status
	var started_usec := Time.get_ticks_usec() if collect_metrics else 0
	stage_waiting = false
	var work_item_limit := _work_item_limit(deadline_usec)
	var work_items := 1
	match stage:
		Stage.SHELL_REQUEST:
			_set_metric_stage("shell_request", collect_metrics)
			room.preparation_request_shell(self)
		Stage.SHELL_WAIT:
			_set_metric_stage("shell_wait", collect_metrics)
			room.preparation_poll_shell(self)
			if stage == Stage.SHELL_WAIT:
				work_items = 0
		Stage.GEOMETRY_REQUEST:
			_set_metric_stage("geometry_request", collect_metrics)
			room.preparation_request_geometry(self)
		Stage.GEOMETRY_WAIT:
			_set_metric_stage("geometry_wait", collect_metrics)
			room.preparation_poll_geometry(self)
			if stage == Stage.GEOMETRY_WAIT:
				work_items = 0
		Stage.GEOMETRY_APPLY:
			_set_metric_stage("geometry_apply", collect_metrics)
			room.preparation_apply_geometry(self)
		Stage.COLLISION:
			_set_metric_stage("collision", collect_metrics)
			work_items = room.preparation_continue_collision(self, work_item_limit)
		Stage.NAVIGATION:
			_set_metric_stage("navigation", collect_metrics)
			work_items = room.preparation_continue_navigation(self, work_item_limit)
		Stage.NAVIGATION_LOOKUP, Stage.FURNITURE_NAVIGATION_LOOKUP:
			_set_metric_stage(
				"navigation_lookup"
				if stage == Stage.NAVIGATION_LOOKUP
				else "furniture_navigation_lookup",
				collect_metrics,
			)
			work_items = room.preparation_continue_navigation_lookup(
				self,
				work_item_limit,
			)
		Stage.OCCLUSION_BEGIN:
			_set_metric_stage("occlusion_begin", collect_metrics)
			room.preparation_begin_occlusion(self)
		Stage.OCCLUSION_SEGMENT:
			_set_metric_stage("occlusion_segment", collect_metrics)
			room.preparation_continue_occlusion(self)
		Stage.FURNITURE_BEGIN:
			_set_metric_stage("furniture_begin", collect_metrics)
			room.preparation_begin_furniture(self)
		Stage.FURNITURE_INSTANCE:
			_set_metric_stage("furniture_instance", collect_metrics)
			room.preparation_continue_furniture(self)
		Stage.FURNITURE_NAVIGATION:
			_set_metric_stage("furniture_navigation", collect_metrics)
			work_items = room.preparation_continue_furniture_navigation(
				self,
				work_item_limit,
			)
	_advance_status.complete = is_complete()
	_advance_status.failed = has_failed()
	_advance_status.waiting = (
		stage == Stage.SHELL_WAIT
		or stage == Stage.GEOMETRY_WAIT
		or stage_waiting
	)
	_advance_status.error = error
	if collect_metrics:
		_advance_status.elapsed_usec = Time.get_ticks_usec() - started_usec
		_advance_status.work_items = work_items
		_advance_status.work_item_limit = work_item_limit
	return _advance_status


func fail(message: String) -> void:
	error = message
	stage = Stage.FAILED
	push_error(message)


func complete() -> void:
	stage = Stage.COMPLETE
	_release_transient_state()


func is_complete() -> bool:
	return stage == Stage.COMPLETE


func has_failed() -> bool:
	return stage == Stage.FAILED


func begin_navigation_lookup(cells: Array, next_stage: Stage) -> void:
	navigation_lookup_cells = cells
	navigation_lookup_cursor = 0
	navigation_lookup_next_stage = next_stage


func clear_navigation_lookup() -> void:
	navigation_lookup_cells = []
	navigation_lookup_cursor = 0


func begin_furniture_navigation() -> void:
	furniture_navigation_phase = FurnitureNavigationPhase.OCCUPANCY
	furniture_blocked_cells = []
	furniture_blocked_lookup = {}
	furniture_filtered_walkable = []
	furniture_walkable_cursor = 0
	furniture_wall_lookup = {}
	furniture_wall_cursor = 0
	furniture_blocked_cursor = 0


func continue_furniture_asset_loading() -> AssetLoadStatus:
	if furniture_load_worker == null and furniture_load_worker_id < 0:
		furniture_load_worker = FURNITURE_LOAD_TASK.new()
		furniture_load_worker_id = WorkerThreadPool.add_task(
			furniture_load_worker.run.bind(
				furniture_manifest_path,
				furniture_layout_path,
			),
			false,
			"Load interior furniture data",
		)
		stage_waiting = true
		return AssetLoadStatus.WAITING
	if furniture_load_worker_id >= 0:
		if not WorkerThreadPool.is_task_completed(furniture_load_worker_id):
			stage_waiting = true
			return AssetLoadStatus.WAITING
		WorkerThreadPool.wait_for_task_completion(furniture_load_worker_id)
		furniture_load_worker_id = -1
		furniture_prepared_data = furniture_load_worker.take_result()
		furniture_load_worker = null
		if furniture_prepared_data.get("ok") != true:
			var errors := furniture_prepared_data.get(
				"errors",
				PackedStringArray(),
			) as PackedStringArray
			fail("Interior furniture data could not be loaded: %s" % "; ".join(errors))
			return AssetLoadStatus.FAILED
		furniture_texture_paths.clear()
		for path_value: Variant in (
			furniture_prepared_data.get("texture_paths", []) as Array
		):
			furniture_texture_paths.append(String(path_value))
	while furniture_texture_request_cursor < furniture_texture_paths.size():
		var path := furniture_texture_paths[furniture_texture_request_cursor]
		if (
			not ResourceLoader.exists(path, "Texture2D")
			or ResourceLoader.load_threaded_request(path, "Texture2D", true) != OK
		):
			fail("Interior furniture texture could not be queued: %s" % path)
			return AssetLoadStatus.FAILED
		furniture_texture_request_cursor += 1
		return AssetLoadStatus.WAITING
	while furniture_texture_poll_cursor < furniture_texture_paths.size():
		var path := furniture_texture_paths[furniture_texture_poll_cursor]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			stage_waiting = true
			return AssetLoadStatus.WAITING
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			fail("Interior furniture texture threaded load failed: %s" % path)
			return AssetLoadStatus.FAILED
		var texture := ResourceLoader.load_threaded_get(path) as Texture2D
		if texture == null:
			fail("Interior furniture texture is missing: %s" % path)
			return AssetLoadStatus.FAILED
		var textures := furniture_prepared_data.get("textures", {}) as Dictionary
		textures[path] = texture
		furniture_prepared_data["textures"] = textures
		furniture_texture_poll_cursor += 1
		return AssetLoadStatus.WAITING
	return AssetLoadStatus.READY


func take_furniture_prepared_data() -> Dictionary:
	var data := furniture_prepared_data
	furniture_prepared_data = {}
	furniture_texture_paths.clear()
	return data


func cancel() -> void:
	if geometry_worker_id >= 0:
		WorkerThreadPool.wait_for_task_completion(geometry_worker_id)
		geometry_worker_id = -1
	geometry_worker = null
	geometry_setup.clear()
	if furniture_load_worker_id >= 0:
		WorkerThreadPool.wait_for_task_completion(furniture_load_worker_id)
		furniture_load_worker_id = -1
	furniture_load_worker = null
	if shell_request_active:
		_consume_threaded_resource(shell_path)
		shell_request_active = false
	for index in range(
		furniture_texture_poll_cursor,
		furniture_texture_request_cursor,
	):
		_consume_threaded_resource(furniture_texture_paths[index])
	_release_transient_state()


func _consume_threaded_resource(path: String) -> void:
	var status := ResourceLoader.load_threaded_get_status(path)
	if (
		status == ResourceLoader.THREAD_LOAD_IN_PROGRESS
		or status == ResourceLoader.THREAD_LOAD_LOADED
	):
		ResourceLoader.load_threaded_get(path)


func _release_transient_state() -> void:
	collision_scan.clear()
	collision_rects.clear()
	navigation_scan.clear()
	clear_navigation_lookup()
	furniture_prepared_data.clear()
	furniture_texture_paths.clear()
	furniture_blocked_cells.clear()
	furniture_blocked_lookup.clear()
	furniture_filtered_walkable.clear()
	furniture_wall_lookup.clear()


func _work_item_limit(deadline_usec: int) -> int:
	if deadline_usec <= 0:
		return MAX_WORK_ITEMS
	var remaining_usec := maxi(deadline_usec - Time.get_ticks_usec(), 1)
	return clampi(
		remaining_usec / WORK_ITEM_TARGET_USEC,
		1,
		MAX_WORK_ITEMS,
	)


func _set_metric_stage(value: String, collect_metrics: bool) -> void:
	if collect_metrics:
		_advance_status.stage_name = value
