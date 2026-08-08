class_name TownAnimal
extends CharacterBody2D


signal petted(animal_id: String, display_name: String, species: String)
signal resident_petted(
	animal_id: String,
	display_name: String,
	resident_id: String,
	resident_name: String,
)

const ANIMAL_SPRITE := preload(
	"res://world/presentation/animals/TownAnimalSprite.gd"
)
const OUTDOOR_CLEARANCE := preload(
	"res://world/data/town/TownOutdoorMovementClearance.gd"
)
const FONT := preload(
	"res://assets/fonts/zheng_ge_dian_hei_16/ZhengGeDianHei-16.ttf"
)
const OCCLUSION_SUBJECT_GROUP := "map_occlusion_subject"
const MAP_COLLISION_LAYER := 1
const PLAYER_COLLISION_LAYER := 2
const RESIDENT_COLLISION_LAYER := 4
const GROUND_ANIMAL_COLLISION_LAYER := 8
const GROUND_COLLISION_MASK := (
	MAP_COLLISION_LAYER
	| PLAYER_COLLISION_LAYER
	| RESIDENT_COLLISION_LAYER
)
const PET_REACTION_SECONDS := 1.35
const ARRIVAL_DISTANCE := 24.0
const CAT_ACTIVE_MIN_SECONDS := 24.0
const CAT_ACTIVE_MAX_SECONDS := 46.0
const CAT_HIDDEN_MIN_SECONDS := 3.0
const CAT_HIDDEN_MAX_SECONDS := 7.0
const CAT_FADE_SECONDS := 0.65
const CAT_CORNER_PADDING := 42.0
const CAT_NAVIGATION_CLEARANCE := 16.0
const CAT_NAVIGATION_EDGE_SAMPLE_DISTANCE := 2.0
const CAT_NAVIGATION_REGION_BUCKET_SIZE := 128.0
const CAT_NAVIGATION_WAYPOINT_DISTANCE := 7.0
const CAT_NAVIGATION_MIN_TRAVEL_DISTANCE := 72.0
const CAT_BLOCKED_REPATH_SECONDS := 0.45
const INVALID_CAT_NAVIGATION_CELL := Vector2i(-1, -1)
const BIRD_TAKEOFF_SECONDS := 0.95
const BIRD_LANDING_SECONDS := 1.45
const BIRD_FLIGHT_HEIGHT := 104.0
const BIRD_LANDING_DISTANCE := 52.0
const BIRD_GROUND_Z_INDEX := 100
const BIRD_ROOF_Z_INDEX := 280
const BIRD_FLIGHT_Z_INDEX := 420
# 动物会改变自身高度（尤其是飞鸟），但地面投影始终留在地图前景遮挡之下。
const GROUND_SHADOW_Z_INDEX := 98

var animal_id := ""
var display_name := ""
var species := ""
var roam_rect := Rect2()
var movement_speed := 70.0
var interaction_range := 150.0

var _rng := RandomNumberGenerator.new()
var _visual: TownAnimalSprite
var _foot_point: Marker2D
var _shadow: Polygon2D
var _hint: PanelContainer
var _hint_label: Label
var _target := Vector2.ZERO
var _idle_remaining := 0.0
var _pet_remaining := 0.0
var _pet_count := 0
var _resident_pet_count := 0
var _resident_reservation_id := ""
var _resident_wait_remaining := 0.0
var _simulation_paused := false
var _world_visible := true
var _last_direction := Vector2.RIGHT
var _configured := false
var _cat_lifecycle_state := "active"
var _cat_lifecycle_remaining := 0.0
var _cat_generation := 0
var _cat_coat_seed := 0
var _cat_corner_index := -1
var _cat_navigation_polygons: Array[PackedVector2Array] = []
var _cat_navigation_polygon_bounds: Array[Rect2] = []
var _cat_navigation_polygon_buckets: Dictionary = {}
var _cat_navigation_cells: Dictionary = {}
var _cat_navigation_neighbors_by_cell: Dictionary = {}
var _cat_navigation_cell_size := 24.0
var _cat_navigation_polygon_point_test_count := 0
var _cat_collision_records: Array[Dictionary] = []
var _cat_navigation_path: Array[Vector2] = []
var _cat_navigation_path_index := 0
var _cat_blocked_seconds := 0.0
var _cat_block_recovery_count := 0
var _blocking_normals: Array[Vector2] = []
var _bird_landing_points: Array[Dictionary] = []
var _bird_state := "landed"
var _bird_surface := "ground"
var _bird_state_remaining := 0.0
var _bird_flight_height := 0.0
var _bird_target_landing: Dictionary = {}
var _bird_last_landing_index := -1
var _bird_landing_start := Vector2.ZERO


func configure(spec: Dictionary) -> Dictionary:
	animal_id = String(spec.get("id", "")).strip_edges()
	display_name = String(spec.get("name", "")).strip_edges()
	species = String(spec.get("species", "")).strip_edges()
	var spawn_value: Variant = spec.get("spawn", Vector2.ZERO)
	var roam_value: Variant = spec.get("roamRect", Rect2())
	if (
		animal_id.is_empty()
		or display_name.is_empty()
		or species not in ["cat", "bird"]
		or not spawn_value is Vector2
		or not roam_value is Rect2
		or not (roam_value as Rect2).has_area()
	):
		return {
			"ok": false,
			"errorCode": "ANIMAL_CONFIG_INVALID",
			"errors": ["小动物配置缺少 id、名称、种类、出生点或漫游区域"],
		}
	position = spawn_value as Vector2
	roam_rect = roam_value as Rect2
	movement_speed = float(spec.get("speed", movement_speed))
	interaction_range = float(spec.get("interactionRange", interaction_range))
	if spec.has("randomSeed"):
		_rng.seed = int(spec.get("randomSeed", 0))
	else:
		_rng.randomize()
	_cat_coat_seed = int(spec.get("colorSeed", _rng.randi()))
	_ensure_built(spec.get("tint", Color.WHITE) as Color, _cat_coat_seed)
	if species == "cat":
		_cat_generation = 1
		_cat_lifecycle_remaining = _random_cat_active_seconds()
	elif species == "bird":
		var landing_result := _configure_bird_landings(spec)
		if landing_result.get("ok") != true:
			return landing_result
		_bird_state_remaining = _rng.randf_range(7.0, 13.0)
		_apply_bird_surface_state()
	_configured = true
	_choose_next_state()
	return {
		"ok": true,
		"id": animal_id,
		"name": display_name,
		"species": species,
	}


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if _configured:
		set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not _configured or not _world_visible:
		velocity = Vector2.ZERO
		_clear_blocking_normals()
		return
	if _simulation_paused:
		velocity = Vector2.ZERO
		_clear_blocking_normals()
		_visual.advance(
			0.0,
			_last_direction,
			0.0,
			_pet_remaining > 0.0,
			species == "bird" and _bird_state != "landed",
			_bird_flight_height,
		)
		return
	if species == "bird":
		_advance_bird_behavior(delta)
		return
	if species == "cat" and not _advance_cat_lifecycle(delta):
		velocity = Vector2.ZERO
		_clear_blocking_normals()
		_visual.advance(delta, _last_direction, 0.0, false)
		return
	if _pet_remaining > 0.0:
		_pet_remaining = maxf(0.0, _pet_remaining - delta)
		velocity = Vector2.ZERO
		_clear_blocking_normals()
		_visual.advance(delta, _last_direction, 0.0, true)
		if _pet_remaining <= 0.0:
			_hint_label.text = "E  摸摸%s" % display_name
		return
	if _resident_wait_remaining > 0.0:
		_resident_wait_remaining = maxf(0.0, _resident_wait_remaining - delta)
		velocity = Vector2.ZERO
		_clear_blocking_normals()
		_visual.advance(delta, _last_direction, 0.0, false)
		if _resident_wait_remaining <= 0.0:
			_resident_reservation_id = ""
		return
	if _idle_remaining > 0.0:
		_idle_remaining = maxf(0.0, _idle_remaining - delta)
		velocity = Vector2.ZERO
		_clear_blocking_normals()
		_visual.advance(delta, _last_direction, 0.0, false)
		if _idle_remaining <= 0.0:
			_choose_walk_target()
		return
	var offset := _target - position
	var arrival_distance := (
		CAT_NAVIGATION_WAYPOINT_DISTANCE
		if species == "cat" and not _cat_navigation_path.is_empty()
		else ARRIVAL_DISTANCE
	)
	if offset.length() <= arrival_distance:
		if species == "cat" and _advance_cat_navigation_waypoint():
			return
		_choose_next_state()
		return
	var direction := offset.normalized()
	_last_direction = direction
	var requested_velocity := direction * movement_speed
	velocity = _filter_velocity_against_contacts(requested_velocity)
	var before := position
	move_and_slide()
	_capture_blocking_normals(requested_velocity)
	position = Vector2(
		clampf(position.x, roam_rect.position.x, roam_rect.end.x),
		clampf(position.y, roam_rect.position.y, roam_rect.end.y),
	)
	var distance_moved := position.distance_to(before)
	_visual.advance(
		delta,
		direction,
		clampf(distance_moved / maxf(0.001, movement_speed * delta), 0.0, 1.0),
		false,
	)
	if species == "cat" and not _cat_navigation_cells.is_empty():
		if distance_moved >= 0.25:
			_cat_blocked_seconds = 0.0
		else:
			_cat_blocked_seconds += maxf(delta, 0.0)
			if _cat_blocked_seconds >= CAT_BLOCKED_REPATH_SECONDS:
				_cat_blocked_seconds = 0.0
				_cat_block_recovery_count += 1
				_choose_cat_navigation_target(
					_cat_navigation_cell_for_position(_target)
				)
	elif get_slide_collision_count() > 0 or distance_moved < 0.05:
		_choose_walk_target()


func _filter_velocity_against_contacts(
	requested_velocity: Vector2,
) -> Vector2:
	var filtered_velocity := requested_velocity
	var retained_normals: Array[Vector2] = []
	for normal: Vector2 in _blocking_normals:
		if requested_velocity.dot(normal) <= 0.01:
			retained_normals.append(normal)
			if filtered_velocity.dot(normal) < 0.0:
				filtered_velocity = filtered_velocity.slide(normal)
	_blocking_normals = retained_normals
	return filtered_velocity


func _capture_blocking_normals(requested_velocity: Vector2) -> void:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var normal := collision.get_normal().normalized()
		if requested_velocity.dot(normal) >= -0.01:
			continue
		_remember_blocking_normal(normal)
		if velocity.dot(normal) < 0.0:
			velocity = velocity.slide(normal)


func _remember_blocking_normal(normal: Vector2) -> void:
	var normalized := normal.normalized()
	if normalized == Vector2.ZERO:
		return
	for current: Vector2 in _blocking_normals:
		if current.dot(normalized) > 0.98:
			return
	_blocking_normals.append(normalized)


func _clear_blocking_normals() -> void:
	_blocking_normals.clear()


func configure_outdoor_navigation(
	navigation: Dictionary,
	collision_values: Array = [],
) -> Dictionary:
	if species != "cat":
		return {
			"ok": true,
			"status": "not_required",
			"species": species,
		}
	_cat_navigation_polygons.clear()
	_cat_navigation_polygon_bounds.clear()
	_cat_navigation_polygon_buckets.clear()
	_cat_navigation_cells.clear()
	_cat_navigation_neighbors_by_cell.clear()
	_cat_navigation_path.clear()
	_cat_navigation_path_index = 0
	_cat_navigation_polygon_point_test_count = 0
	_cat_collision_records = OUTDOOR_CLEARANCE.collision_records(
		collision_values
	)
	var cell_size_value: Variant = navigation.get("cellSize", 24.0)
	if (
		typeof(cell_size_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(cell_size_value))
		or float(cell_size_value) <= 0.0
	):
		return _cat_navigation_schema_failure(
			"CAT_NAVIGATION_CELL_SIZE_INVALID",
			"小动物导航 cellSize 必须是大于零的有限数值",
		)
	_cat_navigation_cell_size = maxf(
		8.0,
		float(cell_size_value),
	)
	var regions_value: Variant = navigation.get("regions", [])
	if regions_value is not Array:
		return _cat_navigation_schema_failure(
			"CAT_NAVIGATION_REGIONS_REQUIRED",
			"小动物导航 regions 必须是数组",
		)
	for region_index: int in range((regions_value as Array).size()):
		var region_value: Variant = (regions_value as Array)[region_index]
		if region_value is not Dictionary:
			return _cat_navigation_schema_failure(
				"CAT_NAVIGATION_REGION_INVALID",
				"小动物导航区域 %d 必须是对象" % region_index,
			)
		var region := region_value as Dictionary
		var enabled_value: Variant = region.get("enabled", true)
		var type_value: Variant = region.get("type", "")
		if (
			typeof(enabled_value) != TYPE_BOOL
			or typeof(type_value) != TYPE_STRING
		):
			return _cat_navigation_schema_failure(
				"CAT_NAVIGATION_REGION_INVALID",
				"小动物导航区域 %d 的 enabled 或 type 类型无效"
				% region_index,
			)
		if (
			not bool(enabled_value)
			or String(type_value) != "walkable"
		):
			continue
		var shape_value: Variant = region.get("shape")
		if shape_value is not Dictionary:
			return _cat_navigation_schema_failure(
				"CAT_NAVIGATION_REGION_SHAPE_INVALID",
				"小动物可通行区域 %d 的 shape 必须是对象"
				% region_index,
			)
		var shape := shape_value as Dictionary
		var points_value: Variant = shape.get("points", [])
		if points_value is not Array:
			return _cat_navigation_schema_failure(
				"CAT_NAVIGATION_REGION_POINTS_INVALID",
				"小动物可通行区域 %d 的 points 必须是数组"
				% region_index,
			)
		if (points_value as Array).size() < 3:
			return _cat_navigation_schema_failure(
				"CAT_NAVIGATION_REGION_POINTS_INVALID",
				"小动物可通行区域 %d 至少需要三个点"
				% region_index,
			)
		var polygon := PackedVector2Array()
		for point_index: int in range((points_value as Array).size()):
			var point_value: Variant = (points_value as Array)[point_index]
			if point_value is not Dictionary:
				return _cat_navigation_schema_failure(
					"CAT_NAVIGATION_REGION_POINT_INVALID",
					"小动物可通行区域 %d 的点 %d 必须是对象"
					% [region_index, point_index],
				)
			var point := point_value as Dictionary
			var x_value: Variant = point.get("x")
			var y_value: Variant = point.get("y")
			if (
				typeof(x_value) not in [TYPE_INT, TYPE_FLOAT]
				or typeof(y_value) not in [TYPE_INT, TYPE_FLOAT]
				or not is_finite(float(x_value))
				or not is_finite(float(y_value))
			):
				return _cat_navigation_schema_failure(
					"CAT_NAVIGATION_REGION_POINT_INVALID",
					"小动物可通行区域 %d 的点 %d 坐标必须是有限数值"
					% [region_index, point_index],
				)
			polygon.append(Vector2(float(x_value), float(y_value)))
		_cat_navigation_polygons.append(polygon)
		_cat_navigation_polygon_bounds.append(
			_cat_navigation_bounds_for_polygon(polygon)
		)
	_build_cat_navigation_polygon_buckets()
	if _cat_collision_records.is_empty():
		return _cat_navigation_schema_failure(
			"CAT_NAVIGATION_COLLISION_REQUIRED",
			"小动物导航缺少正式室外碰撞数据",
		)
	_build_cat_navigation_cells()
	if _cat_navigation_cells.is_empty():
		return {
			"ok": false,
			"errorCode": "CAT_NAVIGATION_ROAM_AREA_UNAVAILABLE",
			"animalId": animal_id,
			"errors": ["%s 的漫游区域没有安全可通行点" % display_name],
		}
	var spawn_cell := _nearest_cat_navigation_cell(position)
	if not _cat_navigation_cells.has(spawn_cell):
		return {
			"ok": false,
			"errorCode": "CAT_NAVIGATION_SPAWN_UNAVAILABLE",
			"animalId": animal_id,
			"errors": ["%s 找不到安全出生点" % display_name],
		}
	position = _cat_navigation_cells[spawn_cell] as Vector2
	_choose_cat_navigation_target()
	return {
		"ok": true,
		"status": "bound",
		"animalId": animal_id,
		"walkableCellCount": _cat_navigation_cells.size(),
		"polygonPointTestCount": (
			_cat_navigation_polygon_point_test_count
		),
		"collisionShapeCount": _cat_collision_records.size(),
		"regionBucketCount": _cat_navigation_polygon_buckets.size(),
	}


func _cat_navigation_schema_failure(
	error_code: String,
	message: String,
) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"animalId": animal_id,
		"errors": [message],
	}


func set_runtime_state(
	world_visible: bool,
	simulation_paused: bool,
	interaction_focused: bool,
) -> void:
	_world_visible = world_visible
	_simulation_paused = simulation_paused
	visible = world_visible and _cat_lifecycle_state != "hidden"
	_apply_collision_state()
	if _hint != null:
		_hint.visible = (
			world_visible
			and interaction_focused
			and not simulation_paused
			and is_active_for_interaction()
		)
	set_physics_process(world_visible)


func distance_to_player(player_position: Vector2) -> float:
	return position.distance_to(player_position)


func is_within_interaction_range(player_position: Vector2) -> bool:
	return (
		_world_visible
		and not _simulation_paused
		and is_active_for_interaction()
		and distance_to_player(player_position) <= interaction_range
	)


func is_active_for_interaction() -> bool:
	if species == "cat":
		return _cat_lifecycle_state == "active"
	if species == "bird":
		return _bird_state == "landed" and _bird_surface == "ground"
	return true


func reserve_for_resident(resident_id: String, wait_seconds: float = 7.0) -> bool:
	if (
		species != "cat"
		or not is_active_for_interaction()
		or resident_id.strip_edges().is_empty()
		or (
			not _resident_reservation_id.is_empty()
			and _resident_reservation_id != resident_id
		)
	):
		return false
	_resident_reservation_id = resident_id
	_resident_wait_remaining = maxf(wait_seconds, 1.0)
	velocity = Vector2.ZERO
	return true


func release_resident_reservation(resident_id: String) -> void:
	if resident_id == _resident_reservation_id:
		_resident_reservation_id = ""
		_resident_wait_remaining = 0.0


func begin_resident_pet(
	resident_id: String,
	resident_name: String,
	resident_position: Vector2,
) -> Dictionary:
	if (
		species != "cat"
		or not is_active_for_interaction()
		or resident_id.strip_edges().is_empty()
		or (
			not _resident_reservation_id.is_empty()
			and resident_id != _resident_reservation_id
		)
		or position.distance_to(resident_position) > interaction_range
	):
		return {
			"ok": false,
			"errorCode": "RESIDENT_ANIMAL_INTERACTION_UNAVAILABLE",
			"animalId": animal_id,
		}
	_begin_pet_reaction(resident_position)
	_resident_pet_count += 1
	_resident_reservation_id = resident_id
	_resident_wait_remaining = PET_REACTION_SECONDS
	_hint_label.text = "♥  %s在陪%s" % [resident_name, display_name]
	resident_petted.emit(animal_id, display_name, resident_id, resident_name)
	return {
		"ok": true,
		"status": "resident_petted",
		"animalId": animal_id,
		"displayName": display_name,
		"residentId": resident_id,
		"residentName": resident_name,
		"residentPetCount": _resident_pet_count,
	}


func begin_pet(player_position: Vector2) -> Dictionary:
	if not is_within_interaction_range(player_position):
		return {
			"ok": false,
			"errorCode": "ANIMAL_OUT_OF_RANGE",
			"animalId": animal_id,
		}
	_begin_pet_reaction(player_position)
	_pet_count += 1
	_hint_label.text = "♥  %s很开心" % display_name
	petted.emit(animal_id, display_name, species)
	return {
		"ok": true,
		"status": "petted",
		"animalId": animal_id,
		"displayName": display_name,
		"species": species,
		"petCount": _pet_count,
	}


func get_snapshot() -> Dictionary:
	return {
		"id": animal_id,
		"name": display_name,
		"species": species,
		"position": {"x": position.x, "y": position.y},
		"roamRect": {
			"x": roam_rect.position.x,
			"y": roam_rect.position.y,
			"width": roam_rect.size.x,
			"height": roam_rect.size.y,
		},
		"moving": velocity.length_squared() > 0.0001,
		"petting": _pet_remaining > 0.0,
		"petCount": _pet_count,
		"residentPetCount": _resident_pet_count,
		"residentReservationId": _resident_reservation_id,
		"interactionRange": interaction_range,
		"active": is_active_for_interaction(),
		"lifecycleState": _cat_lifecycle_state if species == "cat" else "persistent",
		"generation": _cat_generation if species == "cat" else 1,
		"coatSeed": _cat_coat_seed if species == "cat" else 0,
		"navigationReady": (
			not _cat_navigation_cells.is_empty()
			if species == "cat"
			else false
		),
		"navigationWaypointCount": (
			maxi(0, _cat_navigation_path.size() - _cat_navigation_path_index)
			if species == "cat"
			else 0
		),
		"blockedRecoveryCount": (
			_cat_block_recovery_count
			if species == "cat"
			else 0
		),
		"birdState": _bird_state if species == "bird" else "",
		"landingSurface": _bird_surface if species == "bird" else "",
		"flightHeight": _bird_flight_height if species == "bird" else 0.0,
		"landingTarget": (
			_bird_landing_snapshot(_bird_target_landing)
			if species == "bird"
			else {}
		),
		"visual": _visual.get_visual_snapshot() if _visual != null else {},
	}


func respawn_cat_from_corner() -> Dictionary:
	if species != "cat":
		return {
			"ok": false,
			"errorCode": "CAT_RESPAWN_ONLY",
		}
	_respawn_cat()
	return get_snapshot()


func send_bird_to_landing(landing_index: int) -> Dictionary:
	if (
		species != "bird"
		or landing_index < 0
		or landing_index >= _bird_landing_points.size()
	):
		return {
			"ok": false,
			"errorCode": "BIRD_LANDING_INVALID",
		}
	_begin_bird_takeoff(landing_index)
	return {
		"ok": true,
		"status": _bird_state,
		"landingIndex": landing_index,
		"target": _bird_landing_snapshot(_bird_target_landing),
	}


func _ensure_built(tint: Color, color_seed: int) -> void:
	if _visual != null:
		return
	name = "TownAnimal_%s" % animal_id
	z_index = 100
	z_as_relative = false
	collision_layer = GROUND_ANIMAL_COLLISION_LAYER
	collision_mask = GROUND_COLLISION_MASK
	_foot_point = Marker2D.new()
	_foot_point.name = "OcclusionFootPoint"
	_foot_point.z_index = z_index
	_foot_point.z_as_relative = false
	_foot_point.add_to_group(OCCLUSION_SUBJECT_GROUP)
	add_child(_foot_point)
	var collision := CollisionShape2D.new()
	collision.name = "FeetCollision"
	collision.position = Vector2(0.0, -7.0)
	var circle := CircleShape2D.new()
	circle.radius = 11.0 if species == "bird" else 14.0
	collision.shape = circle
	add_child(collision)
	_shadow = Polygon2D.new()
	_shadow.name = "Shadow"
	_shadow.position = Vector2(0.0, -2.0)
	_shadow.polygon = _ellipse_points(
		16.0 if species == "bird" else 25.0,
		5.0 if species == "bird" else 7.0,
		18,
	)
	_shadow.color = Color(0.02, 0.03, 0.04, 0.28)
	_shadow.z_as_relative = false
	_shadow.z_index = GROUND_SHADOW_Z_INDEX
	add_child(_shadow)
	_visual = ANIMAL_SPRITE.new() as TownAnimalSprite
	_visual.name = "AnimalSprite"
	add_child(_visual)
	_visual.configure(species, tint, color_seed)
	_build_hint()


func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.name = "PetHint"
	_hint.position = Vector2(-68.0, -106.0 if species != "bird" else -86.0)
	_hint.custom_minimum_size = Vector2(136.0, 36.0)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.z_index = 20
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#fff1c9e8")
	panel_style.border_color = Color("#6d4328")
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 7
	panel_style.corner_radius_top_right = 7
	panel_style.corner_radius_bottom_left = 7
	panel_style.corner_radius_bottom_right = 7
	panel_style.content_margin_left = 8.0
	panel_style.content_margin_right = 8.0
	panel_style.content_margin_top = 4.0
	panel_style.content_margin_bottom = 4.0
	_hint.add_theme_stylebox_override("panel", panel_style)
	add_child(_hint)
	_hint_label = Label.new()
	_hint_label.name = "PetHintLabel"
	_hint_label.text = "E  摸摸%s" % display_name
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_override("font", FONT)
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color("#4d2f1c"))
	_hint.add_child(_hint_label)
	_hint.visible = false


func _choose_next_state() -> void:
	if _rng.randf() < 0.38:
		_idle_remaining = _rng.randf_range(1.1, 3.6)
		velocity = Vector2.ZERO
	else:
		_choose_walk_target()


func _choose_walk_target() -> void:
	_idle_remaining = 0.0
	_clear_blocking_normals()
	if species == "cat" and not _cat_navigation_cells.is_empty():
		_choose_cat_navigation_target()
		return
	_target = Vector2(
		_rng.randf_range(roam_rect.position.x, roam_rect.end.x),
		_rng.randf_range(roam_rect.position.y, roam_rect.end.y),
	)


func _build_cat_navigation_cells() -> void:
	_cat_navigation_cells.clear()
	if _cat_navigation_polygons.is_empty():
		return
	var minimum_cell := Vector2i(
		floori(roam_rect.position.x / _cat_navigation_cell_size),
		floori(roam_rect.position.y / _cat_navigation_cell_size),
	)
	var maximum_cell := Vector2i(
		ceili(roam_rect.end.x / _cat_navigation_cell_size),
		ceili(roam_rect.end.y / _cat_navigation_cell_size),
	)
	for cell_y: int in range(minimum_cell.y, maximum_cell.y + 1):
		for cell_x: int in range(minimum_cell.x, maximum_cell.x + 1):
			var cell := Vector2i(cell_x, cell_y)
			var center := _cat_navigation_cell_center(cell)
			if roam_rect.has_point(center) and _is_cat_navigation_position_clear(center):
				_cat_navigation_cells[cell] = center
	_build_cat_navigation_graph()


func _build_cat_navigation_graph() -> void:
	_cat_navigation_neighbors_by_cell.clear()
	for cell_value: Variant in _cat_navigation_cells:
		var cell := cell_value as Vector2i
		_cat_navigation_neighbors_by_cell[cell] = []
	for cell_value: Variant in _cat_navigation_cells:
		var cell := cell_value as Vector2i
		var start := _cat_navigation_cells[cell] as Vector2
		for direction: Vector2i in [
			Vector2i.RIGHT,
			Vector2i.DOWN,
		]:
			var candidate := cell + direction
			if not _cat_navigation_cells.has(candidate):
				continue
			var finish := _cat_navigation_cells[candidate] as Vector2
			if _is_cat_navigation_edge_clear(start, finish):
				(
					_cat_navigation_neighbors_by_cell[cell] as Array
				).append(candidate)
				(
					_cat_navigation_neighbors_by_cell[candidate] as Array
				).append(cell)


func _cat_navigation_bounds_for_polygon(
	polygon: PackedVector2Array,
) -> Rect2:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	return bounds.grow(0.001)


func _build_cat_navigation_polygon_buckets() -> void:
	_cat_navigation_polygon_buckets.clear()
	for polygon_index: int in range(_cat_navigation_polygon_bounds.size()):
		var bounds := _cat_navigation_polygon_bounds[polygon_index]
		var minimum_bucket := _cat_navigation_bucket_for_position(
			bounds.position
		)
		var maximum_bucket := _cat_navigation_bucket_for_position(bounds.end)
		for bucket_y: int in range(
			minimum_bucket.y,
			maximum_bucket.y + 1,
		):
			for bucket_x: int in range(
				minimum_bucket.x,
				maximum_bucket.x + 1,
			):
				var bucket := Vector2i(bucket_x, bucket_y)
				if not _cat_navigation_polygon_buckets.has(bucket):
					_cat_navigation_polygon_buckets[bucket] = []
				(
					_cat_navigation_polygon_buckets[bucket] as Array
				).append(polygon_index)


func _cat_navigation_bucket_for_position(candidate: Vector2) -> Vector2i:
	return Vector2i(
		floori(candidate.x / CAT_NAVIGATION_REGION_BUCKET_SIZE),
		floori(candidate.y / CAT_NAVIGATION_REGION_BUCKET_SIZE),
	)


func _is_cat_navigation_position_clear(candidate: Vector2) -> bool:
	if (
		_cat_collision_records.is_empty()
		or not OUTDOOR_CLEARANCE.body_origin_is_safe(
			candidate,
			_cat_collision_records,
		)
	):
		return false
	var diagonal_clearance := CAT_NAVIGATION_CLEARANCE * 0.70710678
	for offset: Vector2 in [
		Vector2.ZERO,
		Vector2(CAT_NAVIGATION_CLEARANCE, 0.0),
		Vector2(-CAT_NAVIGATION_CLEARANCE, 0.0),
		Vector2(0.0, CAT_NAVIGATION_CLEARANCE),
		Vector2(0.0, -CAT_NAVIGATION_CLEARANCE),
		Vector2(diagonal_clearance, diagonal_clearance),
		Vector2(-diagonal_clearance, diagonal_clearance),
		Vector2(diagonal_clearance, -diagonal_clearance),
		Vector2(-diagonal_clearance, -diagonal_clearance),
	]:
		var sample := candidate + offset
		var sample_is_walkable := false
		var bucket := _cat_navigation_bucket_for_position(sample)
		for polygon_index_value: Variant in (
			_cat_navigation_polygon_buckets.get(bucket, []) as Array
		):
			var polygon_index := int(polygon_index_value)
			if (
				polygon_index >= _cat_navigation_polygon_bounds.size()
				or not _cat_navigation_polygon_bounds[polygon_index].has_point(
					sample
				)
			):
				continue
			var polygon := _cat_navigation_polygons[polygon_index]
			_cat_navigation_polygon_point_test_count += 1
			if Geometry2D.is_point_in_polygon(sample, polygon):
				sample_is_walkable = true
				break
		if not sample_is_walkable:
			return false
	return true


func _is_cat_navigation_edge_clear(start: Vector2, finish: Vector2) -> bool:
	var distance := start.distance_to(finish)
	var segment_count := maxi(
		1,
		ceili(distance / CAT_NAVIGATION_EDGE_SAMPLE_DISTANCE),
	)
	for index: int in range(1, segment_count):
		var fraction := float(index) / float(segment_count)
		if not _is_cat_navigation_position_clear(start.lerp(finish, fraction)):
			return false
	return true


func _cat_navigation_cell_center(cell: Vector2i) -> Vector2:
	return (
		Vector2(cell)
		* _cat_navigation_cell_size
		+ Vector2.ONE * _cat_navigation_cell_size * 0.5
	)


func _cat_navigation_cell_for_position(candidate: Vector2) -> Vector2i:
	return Vector2i(
		floori(candidate.x / _cat_navigation_cell_size),
		floori(candidate.y / _cat_navigation_cell_size),
	)


func _nearest_cat_navigation_cell(candidate: Vector2) -> Vector2i:
	var nearest := Vector2i.ZERO
	var nearest_distance := INF
	for cell_value: Variant in _cat_navigation_cells:
		var cell := cell_value as Vector2i
		var center := _cat_navigation_cells[cell] as Vector2
		var distance := center.distance_squared_to(candidate)
		if distance < nearest_distance:
			nearest = cell
			nearest_distance = distance
	return nearest


func _cat_navigation_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for neighbor_value: Variant in (
		_cat_navigation_neighbors_by_cell.get(cell, []) as Array
	):
		neighbors.append(neighbor_value as Vector2i)
	return neighbors


func _choose_cat_navigation_target(
	blocked_cell: Vector2i = INVALID_CAT_NAVIGATION_CELL,
) -> void:
	_idle_remaining = 0.0
	_clear_blocking_normals()
	_cat_navigation_path.clear()
	_cat_navigation_path_index = 0
	if _cat_navigation_cells.is_empty():
		return
	var start := _nearest_cat_navigation_cell(position)
	if not _cat_navigation_cells.has(start):
		return
	var previous: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var queue_index := 0
	var candidates: Array[Vector2i] = []
	while queue_index < queue.size():
		var current := queue[queue_index]
		queue_index += 1
		var current_position := _cat_navigation_cells[current] as Vector2
		if (
			current != start
			and current_position.distance_to(position)
			>= CAT_NAVIGATION_MIN_TRAVEL_DISTANCE
		):
			candidates.append(current)
		for neighbor: Vector2i in _cat_navigation_neighbors(current):
			if neighbor == blocked_cell or previous.has(neighbor):
				continue
			previous[neighbor] = current
			queue.append(neighbor)
	if candidates.is_empty():
		_idle_remaining = _rng.randf_range(1.1, 3.6)
		velocity = Vector2.ZERO
		_target = position
		return
	var destination := candidates[_rng.randi_range(0, candidates.size() - 1)]
	var reverse_cells: Array[Vector2i] = [destination]
	var cursor := destination
	while cursor != start:
		cursor = previous[cursor] as Vector2i
		reverse_cells.append(cursor)
	reverse_cells.reverse()
	for path_cell: Vector2i in reverse_cells:
		_cat_navigation_path.append(
			_cat_navigation_cells[path_cell] as Vector2
		)
	while (
		_cat_navigation_path_index < _cat_navigation_path.size() - 1
		and position.distance_to(
			_cat_navigation_path[_cat_navigation_path_index]
		) <= CAT_NAVIGATION_WAYPOINT_DISTANCE
	):
		_cat_navigation_path_index += 1
	_target = _cat_navigation_path[_cat_navigation_path_index]


func _advance_cat_navigation_waypoint() -> bool:
	if _cat_navigation_path.is_empty():
		return false
	if _cat_navigation_path_index >= _cat_navigation_path.size() - 1:
		_cat_navigation_path.clear()
		_cat_navigation_path_index = 0
		return false
	_cat_navigation_path_index += 1
	_target = _cat_navigation_path[_cat_navigation_path_index]
	_clear_blocking_normals()
	return true


func _begin_pet_reaction(actor_position: Vector2) -> void:
	var facing := actor_position - position
	if facing.length_squared() > 0.0001:
		_last_direction = facing.normalized()
	_pet_remaining = PET_REACTION_SECONDS
	velocity = Vector2.ZERO
	_spawn_hearts()


func _advance_cat_lifecycle(delta: float) -> bool:
	match _cat_lifecycle_state:
		"active":
			if _pet_remaining <= 0.0 and _resident_wait_remaining <= 0.0:
				_cat_lifecycle_remaining -= delta
			if _cat_lifecycle_remaining <= 0.0:
				_cat_lifecycle_state = "vanishing"
				_cat_lifecycle_remaining = CAT_FADE_SECONDS
				_resident_reservation_id = ""
				_resident_wait_remaining = 0.0
			return true
		"vanishing":
			_cat_lifecycle_remaining = maxf(
				0.0,
				_cat_lifecycle_remaining - delta,
			)
			modulate.a = clampf(
				_cat_lifecycle_remaining / CAT_FADE_SECONDS,
				0.0,
				1.0,
			)
			if _cat_lifecycle_remaining <= 0.0:
				_cat_lifecycle_state = "hidden"
				_cat_lifecycle_remaining = _rng.randf_range(
					CAT_HIDDEN_MIN_SECONDS,
					CAT_HIDDEN_MAX_SECONDS,
				)
				visible = false
				_apply_collision_state()
			return false
		"hidden":
			_cat_lifecycle_remaining = maxf(
				0.0,
				_cat_lifecycle_remaining - delta,
			)
			if _cat_lifecycle_remaining <= 0.0:
				_respawn_cat()
			return false
		"appearing":
			visible = _world_visible
			_cat_lifecycle_remaining = maxf(
				0.0,
				_cat_lifecycle_remaining - delta,
			)
			modulate.a = 1.0 - clampf(
				_cat_lifecycle_remaining / CAT_FADE_SECONDS,
				0.0,
				1.0,
			)
			if _cat_lifecycle_remaining <= 0.0:
				_cat_lifecycle_state = "active"
				_cat_lifecycle_remaining = _random_cat_active_seconds()
				modulate.a = 1.0
				_choose_walk_target()
			return false
	return true


func _respawn_cat() -> void:
	var corners: Array[Vector2] = [
		roam_rect.position + Vector2.ONE * CAT_CORNER_PADDING,
		Vector2(
			roam_rect.end.x - CAT_CORNER_PADDING,
			roam_rect.position.y + CAT_CORNER_PADDING,
		),
		roam_rect.end - Vector2.ONE * CAT_CORNER_PADDING,
		Vector2(
			roam_rect.position.x + CAT_CORNER_PADDING,
			roam_rect.end.y - CAT_CORNER_PADDING,
		),
	]
	if not _cat_navigation_cells.is_empty():
		var safe_corners: Array[Vector2] = []
		for corner: Vector2 in corners:
			var safe_cell := _nearest_cat_navigation_cell(corner)
			if _cat_navigation_cells.has(safe_cell):
				safe_corners.append(
					_cat_navigation_cells[safe_cell] as Vector2
				)
		if not safe_corners.is_empty():
			corners = safe_corners
	var next_corner := _rng.randi_range(0, corners.size() - 1)
	if next_corner == _cat_corner_index:
		next_corner = (next_corner + 1) % corners.size()
	_cat_corner_index = next_corner
	position = corners[next_corner]
	var next_seed := _rng.randi()
	if next_seed % 10007 == _cat_coat_seed % 10007:
		next_seed += 1
	_cat_coat_seed = next_seed
	_cat_generation += 1
	_visual.randomize_cat_coat(_cat_coat_seed)
	_cat_lifecycle_state = "appearing"
	_cat_lifecycle_remaining = CAT_FADE_SECONDS
	modulate.a = 0.0
	visible = _world_visible
	_apply_collision_state()
	_pet_remaining = 0.0
	_resident_reservation_id = ""
	_resident_wait_remaining = 0.0
	_cat_navigation_path.clear()
	_cat_navigation_path_index = 0
	_cat_blocked_seconds = 0.0
	_clear_blocking_normals()
	velocity = Vector2.ZERO


func _random_cat_active_seconds() -> float:
	return _rng.randf_range(
		CAT_ACTIVE_MIN_SECONDS,
		CAT_ACTIVE_MAX_SECONDS,
	)


func _configure_bird_landings(spec: Dictionary) -> Dictionary:
	_bird_landing_points.clear()
	var landing_values: Variant = spec.get("landingPoints", [])
	if landing_values is not Array:
		return {
			"ok": false,
			"errorCode": "BIRD_LANDING_CONFIG_INVALID",
			"errors": ["鸟类配置的 landingPoints 必须是数组"],
		}
	for value: Variant in landing_values as Array:
		if value is not Dictionary:
			continue
		var landing := value as Dictionary
		var landing_position: Variant = landing.get("position")
		var surface := String(landing.get("surface", "ground"))
		if landing_position is not Vector2 or surface not in ["ground", "roof"]:
			continue
		_bird_landing_points.append({
			"position": landing_position as Vector2,
			"surface": surface,
		})
	if _bird_landing_points.size() < 2:
		return {
			"ok": false,
			"errorCode": "BIRD_LANDING_CONFIG_INVALID",
			"errors": ["鸟类至少需要两个屋顶或地面落点"],
		}
	_bird_surface = String(spec.get("spawnSurface", "ground"))
	if _bird_surface not in ["ground", "roof"]:
		_bird_surface = "ground"
	return {"ok": true}


func _advance_bird_behavior(delta: float) -> void:
	if _pet_remaining > 0.0:
		_pet_remaining = maxf(0.0, _pet_remaining - delta)
		velocity = Vector2.ZERO
		_visual.advance(delta, _last_direction, 0.0, true)
		if _pet_remaining <= 0.0:
			_hint_label.text = "E  摸摸%s" % display_name
		return
	match _bird_state:
		"landed":
			velocity = Vector2.ZERO
			_bird_flight_height = 0.0
			_visual.advance(delta, _last_direction, 0.0, false)
			_bird_state_remaining = maxf(
				0.0,
				_bird_state_remaining - delta,
			)
			if _bird_state_remaining <= 0.0:
				_begin_bird_takeoff(_choose_bird_landing_index())
		"taking_off":
			velocity = Vector2.ZERO
			_bird_state_remaining = maxf(
				0.0,
				_bird_state_remaining - delta,
			)
			var takeoff_progress := 1.0 - (
				_bird_state_remaining / BIRD_TAKEOFF_SECONDS
			)
			_bird_flight_height = lerpf(
				0.0,
				BIRD_FLIGHT_HEIGHT,
				clampf(takeoff_progress, 0.0, 1.0),
			)
			var target := (
				_bird_target_landing.get("position", position) as Vector2
			)
			var direction := (target - position).normalized()
			if direction.length_squared() > 0.0001:
				_last_direction = direction
			_visual.advance(
				delta,
				_last_direction,
				0.2,
				false,
				true,
				_bird_flight_height,
				1.0 - clampf(takeoff_progress, 0.0, 1.0),
			)
			_apply_bird_surface_state()
			if _bird_state_remaining <= 0.0:
				_bird_state = "flying"
		"flying":
			var target := (
				_bird_target_landing.get("position", position) as Vector2
			)
			var offset := target - position
			if offset.length() <= BIRD_LANDING_DISTANCE:
				_bird_state = "landing"
				_bird_state_remaining = BIRD_LANDING_SECONDS
				_bird_landing_start = position
				velocity = Vector2.ZERO
				return
			var direction := offset.normalized()
			_last_direction = direction
			velocity = direction * movement_speed
			var before := position
			move_and_slide()
			var distance_moved := position.distance_to(before)
			_bird_flight_height = (
				BIRD_FLIGHT_HEIGHT
				+ sin(Time.get_ticks_msec() * 0.005) * 7.0
			)
			_visual.advance(
				delta,
				direction,
				clampf(
					distance_moved
					/ maxf(0.001, movement_speed * delta),
					0.0,
					1.0,
				),
				false,
				true,
				_bird_flight_height,
			)
			_apply_bird_surface_state()
		"landing":
			_bird_state_remaining = maxf(
				0.0,
				_bird_state_remaining - delta,
			)
			var landing_progress := 1.0 - (
				_bird_state_remaining / BIRD_LANDING_SECONDS
			)
			var target := (
				_bird_target_landing.get("position", position) as Vector2
			)
			position = _bird_landing_start.lerp(
				target,
				smoothstep(0.0, 1.0, clampf(landing_progress, 0.0, 1.0)),
			)
			var direction := target - _bird_landing_start
			if direction.length_squared() > 0.0001:
				_last_direction = direction.normalized()
			_bird_flight_height = lerpf(
				BIRD_FLIGHT_HEIGHT,
				0.0,
				clampf(landing_progress, 0.0, 1.0),
			)
			_visual.advance(
				delta,
				_last_direction,
				0.35,
				false,
				true,
				_bird_flight_height,
				clampf(landing_progress, 0.0, 1.0),
			)
			_apply_bird_surface_state()
			if _bird_state_remaining <= 0.0:
				position = target
				_bird_state = "landed"
				_bird_surface = String(
					_bird_target_landing.get("surface", "ground"),
				)
				_bird_state_remaining = _bird_landed_wait_seconds()
				_bird_flight_height = 0.0
				velocity = Vector2.ZERO
				_apply_bird_surface_state()
				_visual.advance(
					delta,
					_last_direction,
					0.0,
					false,
				)


func _begin_bird_takeoff(landing_index: int) -> void:
	if _bird_landing_points.is_empty():
		return
	var normalized_index := clampi(
		landing_index,
		0,
		_bird_landing_points.size() - 1,
	)
	_bird_last_landing_index = normalized_index
	_bird_target_landing = (
		_bird_landing_points[normalized_index] as Dictionary
	).duplicate(true)
	_bird_state = "taking_off"
	_bird_state_remaining = BIRD_TAKEOFF_SECONDS
	_bird_flight_height = 0.0
	velocity = Vector2.ZERO
	_apply_bird_surface_state()


func _choose_bird_landing_index() -> int:
	if _bird_landing_points.is_empty():
		return 0
	var next_index := _rng.randi_range(
		0,
		_bird_landing_points.size() - 1,
	)
	if (
		_bird_landing_points.size() > 1
		and next_index == _bird_last_landing_index
	):
		next_index = (next_index + 1) % _bird_landing_points.size()
	return next_index


func _bird_landed_wait_seconds() -> float:
	if _bird_surface == "roof":
		return _rng.randf_range(10.0, 20.0)
	return _rng.randf_range(8.0, 16.0)


func _apply_bird_surface_state() -> void:
	if species != "bird" or _shadow == null or _foot_point == null:
		return
	var airborne := _bird_state != "landed"
	var on_roof := not airborne and _bird_surface == "roof"
	if airborne:
		z_index = BIRD_FLIGHT_Z_INDEX
		_shadow.visible = true
		_shadow.scale = Vector2.ONE * 0.72
		_shadow.modulate.a = 0.42
	elif on_roof:
		z_index = BIRD_ROOF_Z_INDEX
		_shadow.visible = false
	else:
		z_index = BIRD_GROUND_Z_INDEX
		_shadow.visible = true
		_shadow.scale = Vector2.ONE
		_shadow.modulate.a = 1.0
	_apply_collision_state()
	_foot_point.z_index = z_index
	if airborne or on_roof:
		if _foot_point.is_in_group(OCCLUSION_SUBJECT_GROUP):
			_foot_point.remove_from_group(OCCLUSION_SUBJECT_GROUP)
	elif not _foot_point.is_in_group(OCCLUSION_SUBJECT_GROUP):
		_foot_point.add_to_group(OCCLUSION_SUBJECT_GROUP)


func _apply_collision_state() -> void:
	var participates := _world_visible
	if species == "cat":
		participates = (
			participates
			and _cat_lifecycle_state != "hidden"
		)
	elif species == "bird":
		participates = (
			participates
			and _bird_state == "landed"
			and _bird_surface == "ground"
		)
	collision_layer = (
		GROUND_ANIMAL_COLLISION_LAYER if participates else 0
	)
	collision_mask = GROUND_COLLISION_MASK if participates else 0


func _bird_landing_snapshot(landing: Dictionary) -> Dictionary:
	if landing.is_empty():
		return {}
	var landing_position := landing.get("position", Vector2.ZERO) as Vector2
	return {
		"position": {
			"x": landing_position.x,
			"y": landing_position.y,
		},
		"surface": String(landing.get("surface", "ground")),
	}


func _spawn_hearts() -> void:
	for index: int in 3:
		var heart := Polygon2D.new()
		heart.name = "PetHeart"
		heart.polygon = PackedVector2Array([
			Vector2(0.0, 5.0),
			Vector2(-9.0, -3.0),
			Vector2(-8.0, -10.0),
			Vector2(-3.0, -13.0),
			Vector2(0.0, -8.0),
			Vector2(3.0, -13.0),
			Vector2(8.0, -10.0),
			Vector2(9.0, -3.0),
		])
		heart.color = Color("#ff6f91")
		heart.position = Vector2(-22.0 + float(index) * 22.0, -70.0 - float(index % 2) * 8.0)
		heart.z_index = 30
		add_child(heart)
		var tween := heart.create_tween()
		tween.set_parallel(true)
		tween.tween_property(heart, "position:y", heart.position.y - 54.0, 0.85)
		tween.tween_property(heart, "modulate:a", 0.0, 0.85).set_delay(0.18 + float(index) * 0.06)
		tween.chain().tween_callback(heart.queue_free)


func _ellipse_points(
	radius_x: float,
	radius_y: float,
	segments: int,
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index: int in segments:
		var angle := TAU * float(index) / float(segments)
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points
