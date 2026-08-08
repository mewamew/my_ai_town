extends CharacterBody2D


const PAPER_DOLL_64_SPRITE_SCRIPT := preload(
	"res://characters/paper_doll/PaperDoll64Sprite.gd"
)
const DOOR_FADE_SECONDS := 0.22
const FEET_COLLISION_RADIUS := 18.0
# 与正式小镇一致：启动页地图前景遮挡的后置层最低为 z=99，行人脚底
# 阴影固定在其下方，避免以后启用环境行人时阴影盖到建筑和围栏上。
const GROUND_SHADOW_Z_INDEX := 98

var reference_position := Vector2.ZERO

var _steps: Array[Dictionary] = []
var _speed := 34.0
var _visual_scale := 0.62
var _loadout_id := "elder_man"
var _step_index := 0
var _point_index := 1
var _step_started := false
var _pause_remaining := 0.0
var _advance_after_pause := false
var _enter_phase := 0
var _enter_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _sprite: PaperDoll64Sprite


func configure(
	loadout_id: String,
	route_steps: Array[Dictionary],
	speed: float,
	visual_scale: float,
	random_seed: int,
	initial_delay: float
) -> void:
	_loadout_id = loadout_id
	_steps.clear()
	for step in route_steps:
		_steps.append(step.duplicate(true))
	_speed = maxf(1.0, speed)
	_visual_scale = maxf(0.1, visual_scale)
	_rng.seed = random_seed
	_pause_remaining = maxf(0.0, initial_delay)
	if _steps.is_empty():
		return
	_randomize_route_start()


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 0
	collision_mask = 1
	_build_feet_collision()
	_build_shadow()
	var visual_root := Node2D.new()
	visual_root.name = "PaperDollVisual"
	visual_root.scale = Vector2.ONE * _visual_scale
	add_child(visual_root)
	_sprite = PAPER_DOLL_64_SPRITE_SCRIPT.new() as PaperDoll64Sprite
	_sprite.name = "CharacterSprite"
	visual_root.add_child(_sprite)
	_sprite.set_loadout(_loadout_id)
	_sprite.configure_motion_speed(_speed)
	z_index = 100
	z_as_relative = false


func advance(delta: float) -> void:
	if _sprite == null or _steps.is_empty():
		return
	if _pause_remaining > 0.0:
		_pause_remaining = maxf(0.0, _pause_remaining - delta)
		velocity = Vector2.ZERO
		_sprite.set_motion(Vector2.ZERO, 0.0)
		if _pause_remaining <= 0.0 and _advance_after_pause:
			_advance_after_pause = false
			_advance_step()
		return

	var step := _steps[_step_index]
	match String(step.get("type", "")):
		"move":
			_advance_move(step, delta)
		"enter":
			_advance_enter(step, delta)
		_:
			_advance_step()


func _advance_move(step: Dictionary, delta: float) -> void:
	var points := step.get("points", PackedVector2Array()) as PackedVector2Array
	if points.size() < 2:
		_advance_step()
		return
	if not _step_started:
		_step_started = true
		_point_index = 1
		reference_position = points[0]
		position = reference_position

	var target: Vector2 = points[_point_index]
	var target_global: Vector2 = (get_parent() as Node2D).to_global(target)
	var offset_global: Vector2 = target_global - global_position
	var distance_global: float = offset_global.length()
	var world_scale := maxf(0.001, absf(global_transform.get_scale().x))
	if distance_global <= world_scale * 0.25:
		position = target
		reference_position = target
		_reach_move_point(points)
		return
	var direction_global: Vector2 = offset_global / distance_global
	var direction_local := (target - position).normalized()
	var desired_distance_global := minf(distance_global, _speed * world_scale * delta)
	var previous_global := global_position
	velocity = direction_global * desired_distance_global / maxf(delta, 0.0001)
	move_and_slide()
	var moved_distance_global := global_position.distance_to(previous_global)
	var moved_distance_world := moved_distance_global / world_scale
	reference_position = position
	_sprite.set_motion(direction_local, moved_distance_world)
	if position.distance_to(target) <= 0.25:
		reference_position = target
		position = target
		_reach_move_point(points)


func _reach_move_point(points: PackedVector2Array) -> void:
	_point_index += 1
	if _point_index < points.size():
		return
	_step_started = false
	if _next_step_type() == "enter":
		_advance_step()
		return
	if _rng.randf() < 0.28:
		_pause_remaining = _rng.randf_range(0.45, 1.7)
		_advance_after_pause = true
		_sprite.set_motion(Vector2.ZERO, 0.0)
	else:
		_advance_step()


func _advance_enter(step: Dictionary, delta: float) -> void:
	if not _step_started:
		_step_started = true
		_enter_phase = 0
		_enter_timer = DOOR_FADE_SECONDS
		velocity = Vector2.ZERO
		_sprite.set_motion(Vector2.ZERO, 0.0)

	match _enter_phase:
		0:
			_enter_timer = maxf(0.0, _enter_timer - delta)
			modulate.a = clampf(_enter_timer / DOOR_FADE_SECONDS, 0.0, 1.0)
			if _enter_timer <= 0.0:
				_enter_phase = 1
				_enter_timer = _rng.randf_range(
					float(step.get("wait_min", 3.0)),
					float(step.get("wait_max", 7.0))
				)
		1:
			modulate.a = 0.0
			_enter_timer = maxf(0.0, _enter_timer - delta)
			if _enter_timer <= 0.0:
				_enter_phase = 2
				_enter_timer = DOOR_FADE_SECONDS
				_face_next_move_direction()
		2:
			_enter_timer = maxf(0.0, _enter_timer - delta)
			modulate.a = 1.0 - clampf(_enter_timer / DOOR_FADE_SECONDS, 0.0, 1.0)
			if _enter_timer <= 0.0:
				modulate.a = 1.0
				_step_started = false
				_advance_step()


func _face_next_move_direction() -> void:
	var next_index := posmod(_step_index + 1, _steps.size())
	for offset in range(_steps.size()):
		var candidate := _steps[posmod(next_index + offset, _steps.size())]
		if String(candidate.get("type", "")) != "move":
			continue
		var points := candidate.get("points", PackedVector2Array()) as PackedVector2Array
		if points.size() >= 2:
			_sprite.set_motion(points[1] - points[0], 0.0)
		return


func _next_step_type() -> String:
	return String(_steps[posmod(_step_index + 1, _steps.size())].get("type", ""))


func _advance_step() -> void:
	_step_index = posmod(_step_index + 1, _steps.size())
	_step_started = false
	_point_index = 1
	velocity = Vector2.ZERO


func _randomize_route_start() -> void:
	var move_step_indices := PackedInt32Array()
	for index in range(_steps.size()):
		var step := _steps[index]
		if String(step.get("type", "")) != "move":
			continue
		var points := step.get("points", PackedVector2Array()) as PackedVector2Array
		if points.size() >= 2:
			move_step_indices.append(index)
	if move_step_indices.is_empty():
		return
	_step_index = move_step_indices[_rng.randi_range(0, move_step_indices.size() - 1)]
	var points := (
		_steps[_step_index].get("points", PackedVector2Array()) as PackedVector2Array
	)
	var segment_start := _rng.randi_range(0, points.size() - 2)
	var progress := _rng.randf_range(0.08, 0.92)
	reference_position = points[segment_start].lerp(points[segment_start + 1], progress)
	position = reference_position
	_point_index = segment_start + 1
	_step_started = true


func _build_feet_collision() -> void:
	var feet_collision := CollisionShape2D.new()
	feet_collision.name = "FeetCollision"
	feet_collision.position = Vector2(0.0, -12.0)
	var feet_shape := CircleShape2D.new()
	feet_shape.radius = FEET_COLLISION_RADIUS
	feet_collision.shape = feet_shape
	add_child(feet_collision)


func _build_shadow() -> void:
	var shadow := Polygon2D.new()
	shadow.name = "FootShadow"
	shadow.position = Vector2(0.0, -2.0)
	shadow.polygon = PackedVector2Array([
		Vector2(-30.0, 0.0),
		Vector2(-20.0, -7.0),
		Vector2(20.0, -7.0),
		Vector2(30.0, 0.0),
		Vector2(20.0, 7.0),
		Vector2(-20.0, 7.0),
	])
	shadow.color = Color(0.03, 0.04, 0.05, 0.30)
	shadow.z_as_relative = false
	shadow.z_index = GROUND_SHADOW_Z_INDEX
	add_child(shadow)


func is_inside() -> bool:
	return (
		not _steps.is_empty()
		and
		String(_steps[_step_index].get("type", "")) == "enter"
		and _enter_phase == 1
	)
