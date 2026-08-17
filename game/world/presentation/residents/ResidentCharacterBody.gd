class_name ResidentCharacterBody
extends CharacterBody2D

const POINTER_INPUT := preload("res://ui/mobile/PointerInput.gd")


signal visible_space_changed(
	resident_id: String,
	previous_space_id: String,
	space_id: String,
)


signal presentation_diagnostic(diagnostic: Dictionary)
signal resident_pressed(resident_id: String, resident_name: String)
signal death_dissolve_finished(resident_id: String)

const CHARACTER_RIG := preload(
	"res://world/presentation/residents/ResidentFrozenWhitebodyRig.gd"
)
const GRAYSCALE_SHADER := preload(
	"res://world/presentation/lifecycle/resident_grayscale.gdshader"
)
const DEATH_DISSOLVE_EFFECT := preload(
	"res://world/presentation/lifecycle/ResidentDeathDissolveEffect.gd"
)
const DEFAULT_MOTION_SPEED := 144.0
const DEFAULT_LARGE_CORRECTION_DISTANCE := 192.0
# World and presentation share the same 1x walking distance. Higher simulation
# speeds multiply both sides equally, so a resident never needs a late catch-up
# jump to recover an authority position.
const MAX_SIMULATION_SPEED_MULTIPLIER := 3.0
const ARRIVAL_DISTANCE := 0.5
const INTERACTION_SETTLE_DISTANCE := 48.0
const INTERACTION_BLOCKED_SETTLE_DISTANCE := 112.0
const INTERACTION_NON_PROGRESS_SECONDS := 0.75
const MOVEMENT_NON_PROGRESS_HOLD_SECONDS := 1.25
const BLOCKED_HOLD_RETRY_SECONDS := 0.15
const BLOCKED_AUTHORITY_RESYNC_SECONDS := 3.0
# Tiny distance changes while steering around one obstacle are not route
# progress. Requiring one meaningful stride prevents a resident from orbiting
# an unreachable waypoint forever while still resetting quickly during normal
# walking.
const TARGET_MATERIAL_PROGRESS_DISTANCE := 12.0
const MAP_COLLISION_LAYER := 1
const PLAYER_COLLISION_LAYER := 2
const RESIDENT_COLLISION_LAYER := 4
const GROUND_ANIMAL_COLLISION_LAYER := 8
# Residents steer around the map, player, and animals, but never around other
# residents. At higher simulation speeds a mutual body block is promoted to a
# delayed authority resync, which looks like a teleport instead of walking.
const ACTIVE_COLLISION_MASK := (
	(
		MAP_COLLISION_LAYER
		| PLAYER_COLLISION_LAYER
		| GROUND_ANIMAL_COLLISION_LAYER
	)
	& ~RESIDENT_COLLISION_LAYER
)
const LOCAL_AVOIDANCE_LOOKAHEAD := 52.0
const LOCAL_AVOIDANCE_STEP_DISTANCE := 12.0
const LOCAL_AVOIDANCE_MAX_SUBSTEPS := 64
# 慢帧不能把逝去时间一次性换成更长的可见跨步；表现可以暂时落后，逻辑
# 时钟和权威到达判定仍由 World 推进。限幅按居民自己的配置速度计算，避免
# 用默认居民的 8 像素上限误伤测试/扩展用的更高移动速度。
const MIN_PRESENTATION_DISTANCE_PER_ADVANCE := 8.0
const LOCAL_AVOIDANCE_ANGLES := [
	deg_to_rad(35.0),
	deg_to_rad(55.0),
	deg_to_rad(75.0),
	deg_to_rad(90.0),
]
const BLOCKED_DIAGNOSTIC_SECONDS := 1.0
const DIAGNOSTIC_LIMIT := 64
const SUBJECT_GROUP := "map_occlusion_subject"
const OUTDOOR_GROUND_SHADOW_Z_INDEX := 98
const INTERIOR_GROUND_SHADOW_Z_INDEX := -9
const SLEEP_HEAD_CENTER_OFFSET := Vector2(0.0, -180.0)
# 点击区恢复为覆盖整个人的大框（5733d6da 版）。f9 曾缩水到 96×160
# 来规避"隐藏模型误点"，但正确做法是激活空间门控——非激活空间的
# body 已由 _set_hit_area_input_enabled(false) 关闭拾取，可见的人
# 不应该点不中。
const RESIDENT_HIT_AREA_POSITION := Vector2(0.0, -105.0)
const RESIDENT_HIT_AREA_SIZE := Vector2(180.0, 250.0)
const DEATH_GRAYSCALE_SECONDS := 0.42
const DEATH_DISSOLVE_SECONDS := 1.05

var motion_speed := DEFAULT_MOTION_SPEED
var large_correction_distance := DEFAULT_LARGE_CORRECTION_DISTANCE

var _resident_id := ""
var _resident_name := ""
var _space_id := ""
var _authority_revision := -1
var _movement_revision := -1
var _authority_action_token := ""
var _authority_position := Vector2.ZERO
var _target_position := Vector2.ZERO
var _navigation_path: Array[Vector2] = []
var _has_navigation_target := false
var _authority_route_active := false
var _route_crosses_portal := false
var _continuous_route_follow := false
var _target_arrival_seconds_remaining := 0.0
var _route_speed_multiplier := 1.0
var _space_active := true
var _automatic_motion := true
var _built := false
var _avoidance_side := 0
var _avoidance_heading := Vector2.ZERO
var _local_avoidance_steer_count := 0
var _blocked_seconds := 0.0
var _blocked_diagnostic_emitted := false
var _interaction_performing := false
var _closest_target_distance := INF
var _non_progress_seconds := 0.0
var _movement_blocked_hold := false
var _blocked_hold_retry_seconds := 0.0
var _blocked_hold_total_seconds := 0.0
var _blocked_authority_stall_diagnostic_emitted := false
var _presentation_paused := false
var _pending_space_transition := false
var _pending_space_id := ""
var _pending_space_position := Vector2.ZERO
var _pending_space_active := true
var _diagnostics: Array[Dictionary] = []
var _character_rig
var _feet_collision: CollisionShape2D
var _shadow: Polygon2D
var _selection_marker: Line2D
var _hit_area: Area2D
var _appearance_policy := "normal"
var _applied_appearance := ""
var _appearance_apply_count := 0
var _lifecycle_apply_count := 0
var _sleep_refresh_count := 0
var _grayscale_material: ShaderMaterial
var _lifecycle_visual_frozen := false
var _sleep_visual_active := false
var _sleep_head_global_position := Vector2.ZERO
var _sleep_visual_body_position := Vector2.ZERO
var _sleep_body_relocated := false
var _death_dissolve: ResidentDeathDissolveEffect
var _death_visual_active := false
var _death_visual_elapsed := 0.0
var _death_finished_emitted := false


func _ready() -> void:
	_ensure_built()
	set_physics_process(_automatic_motion)
	set_process(false)


func _process(delta: float) -> void:
	_advance_death_visual(delta)


func _physics_process(delta: float) -> void:
	advance_presentation(delta)


func configure(identity: Dictionary, initial_state: Dictionary) -> Dictionary:
	var resident_id := String(identity.get("residentId", "")).strip_edges()
	var resident_name := String(identity.get("residentName", "")).strip_edges()
	if resident_id.is_empty() or resident_name.is_empty():
		return _failure_result(
			"PRESENTATION_IDENTITY_INVALID",
			"residentId and residentName are required",
		)
	if not _resident_id.is_empty() and resident_id != _resident_id:
		return _failure_result(
			"PRESENTATION_IDENTITY_IMMUTABLE",
			"residentId cannot change after configuration",
		)
	var initial_position_value: Variant = initial_state.get("position")
	var movement_revision_value: Variant = initial_state.get(
		"movementRevision",
	)
	var appearance_value: Variant = initial_state.get(
		"appearance",
		identity.get("appearance", ""),
	)
	if (
		not _is_finite_vector2_value(initial_position_value)
		or movement_revision_value is not int
		or int(movement_revision_value) < 0
		or appearance_value is not String
	):
		return _failure_result(
			"PRESENTATION_AUTHORITY_STATE_INVALID",
			"initial position and movement revision must be valid",
		)
	_ensure_built()
	if not _character_rig.set_resident_appearance(
		resident_id,
		String(appearance_value),
	):
		return _failure_result(
			"PRESENTATION_APPEARANCE_INVALID",
			"resident wardrobe appearance could not be resolved",
		)
	_resident_id = resident_id
	_resident_name = resident_name
	name = "ResidentCharacter_%s" % resident_id
	_character_rig.set_resident_appearance(
		_resident_id,
		String(
			initial_state.get(
				"appearance",
				identity.get("appearance", ""),
			),
		),
	)
	_applied_appearance = String(appearance_value)
	_apply_lifecycle_appearance(initial_state, true)
	_space_id = String(initial_state.get("spaceId", ""))
	_update_ground_shadow_depth()
	_movement_revision = int(movement_revision_value)
	_authority_action_token = ""
	position = initial_position_value as Vector2
	_authority_position = position
	_target_position = position
	_navigation_path.clear()
	_has_navigation_target = false
	_authority_route_active = false
	_route_crosses_portal = false
	_continuous_route_follow = false
	_target_arrival_seconds_remaining = 0.0
	_route_speed_multiplier = 1.0
	_local_avoidance_steer_count = 0
	_interaction_performing = false
	_reset_target_progress()
	_reset_local_avoidance()
	return {
		"ok": true,
		"status": "configured",
		"residentId": _resident_id,
		"residentName": _resident_name,
	}


func configure_motion(
	speed: float = DEFAULT_MOTION_SPEED,
	correction_distance: float = DEFAULT_LARGE_CORRECTION_DISTANCE,
) -> Dictionary:
	if (
		not is_finite(speed)
		or not is_finite(correction_distance)
		or speed <= 0.0
		or correction_distance <= ARRIVAL_DISTANCE
	):
		return _failure_result(
			"PRESENTATION_MOTION_CONFIG_INVALID",
			"speed and correction distance must be finite and positive",
		)
	motion_speed = speed
	large_correction_distance = correction_distance
	return {
		"ok": true,
		"status": "configured",
		"motionSpeed": motion_speed,
		"largeCorrectionDistance": large_correction_distance,
	}


func can_apply_authoritative_state(state: Dictionary) -> bool:
	_ensure_built()
	if (
		state.has("appearance")
		and (
			state.get("appearance") is not String
			or not _character_rig.can_resolve_resident_appearance(
				_resident_id,
				String(state.get("appearance", "")),
			)
		)
	):
		return false
	return true


func apply_authoritative_state(
	state: Dictionary,
	world_revision: int,
	projected_position: Variant = null,
	force_relocate: bool = false,
	follow_duration_seconds: float = 0.0,
	next_space_active: bool = true,
) -> Dictionary:
	if _resident_id.is_empty():
		return _failure_result(
			"PRESENTATION_NOT_CONFIGURED",
			"configure must be called before applying authority",
		)
	var state_resident_id := String(state.get("residentId", ""))
	if state_resident_id != _resident_id:
		return _record_diagnostic(
			"PRESENTATION_IDENTITY_MISMATCH",
			"error",
			world_revision,
			String(state.get("spaceId", "")),
			position,
			0.0,
			{"receivedResidentId": state_resident_id},
		)
	var movement_revision_value: Variant = state.get("movementRevision")
	var next_position_value: Variant = (
		projected_position
		if projected_position != null
		else state.get("position")
	)
	var target_value: Variant = state.get("target")
	var presentation_path_value: Variant = state.get("presentationPath", [])
	if (
		movement_revision_value is not int
		or int(movement_revision_value) < 0
		or not _is_finite_vector2_value(next_position_value)
		or not is_finite(follow_duration_seconds)
		or follow_duration_seconds < 0.0
		or (
			target_value != null
			and (
				target_value is not Dictionary
				or not _valid_target(target_value as Dictionary)
			)
		)
		or not _valid_presentation_path(presentation_path_value)
		or (
			state.has("currentAction")
			and state.get("currentAction") != null
			and state.get("currentAction") is not Dictionary
		)
		or (
			state.has("activityCue")
			and state.get("activityCue") is not Dictionary
		)
		or (
			state.has("actionPhase")
			and state.get("actionPhase") is not Dictionary
		)
		or (
			state.has("appearance")
			and state.get("appearance") is not String
		)
		or (
			state.has("lifecycle")
			and state.get("lifecycle") is not Dictionary
		)
	):
		return _failure_result(
			"PRESENTATION_AUTHORITY_STATE_INVALID",
			"authority state contains malformed or non-finite values",
		)
	var movement_revision := int(movement_revision_value)
	var previous_movement_revision := _movement_revision
	var next_position := next_position_value as Vector2
	if (
		world_revision < _authority_revision
		or (
			world_revision == _authority_revision
			and movement_revision < _movement_revision
		)
	):
		return _record_diagnostic(
			"PRESENTATION_STALE_AUTHORITY_IGNORED",
			"info",
			world_revision,
			String(state.get("spaceId", "")),
			position,
			0.0,
			{
				"confirmedRevision": _authority_revision,
				"confirmedMovementRevision": _movement_revision,
				"receivedMovementRevision": movement_revision,
			},
		)
	# 睡眠期间本体会暂时跟随床上的表现位置。每次新的 World 快照到达前，
	# 先还原到上一次确认的权威位置，避免把表现层位置当成新的导航起点。
	_restore_authority_position_before_refresh()
	# C3(docs/居民状态通知链减负方案.md):三组独立签名门控——外观签名真变化
	# 才解析与应用;生命周期材质在外观或 appearancePolicy 变化时才重新应用;
	# 睡眠身体节点刷新由 _apply_sleep_visual 按实际切换单独门控。
	var appearance_changed := (
		state.has("appearance")
		and String(state.get("appearance", "")) != _applied_appearance
	)
	if (
		appearance_changed
		and not _character_rig.set_resident_appearance(
			_resident_id,
			String(state.get("appearance", "")),
		)
	):
		return _failure_result(
			"PRESENTATION_APPEARANCE_INVALID",
			"resident wardrobe appearance could not be resolved",
		)
	_authority_revision = world_revision
	_movement_revision = movement_revision
	_authority_position = next_position
	_resident_name = String(state.get("name", _resident_name))
	if appearance_changed:
		_applied_appearance = String(state.get("appearance", ""))
		_appearance_apply_count += 1
	if (
		appearance_changed
		or _lifecycle_policy_for_state(state) != _appearance_policy
	):
		_apply_lifecycle_appearance(state)
	var current_action_type := ""
	var current_action_id := ""
	var current_action_value: Variant = state.get("currentAction")
	if current_action_value is Dictionary:
		current_action_type = String(
			(current_action_value as Dictionary).get("type", "")
		)
		current_action_id = String(
			(current_action_value as Dictionary).get("action_id", "")
		)
	var current_action_token := (
		"%s:%s" % [current_action_type, current_action_id]
		if not current_action_type.is_empty()
		else ""
	)
	var action_changed := (
		current_action_token != _authority_action_token
	)
	_authority_action_token = current_action_token
	var activity_cue := (
		state.get("activityCue", {}) as Dictionary
		if state.get("activityCue") is Dictionary
		else {}
	)
	var action_phase := (
		state.get("actionPhase", {}) as Dictionary
	)
	var phase_name := String(action_phase.get("phase", ""))
	# World exposes several public currentAction names for the same prop-backed
	# activity. The presentation cue is the stable contract for deciding when
	# the resident has stopped approaching and is now working in place.
	_interaction_performing = (
		String(activity_cue.get("actionType", "")) == "用道具"
		and String(activity_cue.get("phase", "")) == "performing"
	)
	var rig_action_type := (
		"idle" if current_action_type.is_empty() else current_action_type
	)
	if current_action_type in ["activity.perform", "做活动"]:
		rig_action_type = "用道具"
	if (
		rig_action_type == "用道具"
		and String(activity_cue.get("phase", "")) == "approaching"
	):
		rig_action_type = "idle"
	_character_rig.set_activity(
		rig_action_type,
		_activity_family_for_cue(activity_cue),
	)
	var previous_route_crosses_portal := _route_crosses_portal
	_authority_route_active = _state_has_active_route(state)
	_route_crosses_portal = (
		_authority_route_active
		and state.get("routeCrossesPortal", false) == true
	)
	if (
		not _authority_route_active
		and String(activity_cue.get("phase", "")) == "performing"
	):
		_character_rig.set_direction(
			String(activity_cue.get("actorFacing", ""))
		)
	_apply_sleep_visual(
		activity_cue,
		next_position,
		state.get("position"),
	)
	if _authority_route_active:
		_continuous_route_follow = true
	var next_space_id := String(state.get("spaceId", ""))
	# World can publish the far side of a portal before the visible body reaches
	# the doorway. If a newer authoritative sample returns to the body's current
	# space, the old handoff is no longer valid and must not complete later.
	if _pending_space_transition and next_space_id == _space_id:
		_clear_pending_space_transition()
	var correction_distance := position.distance_to(next_position)
	if next_space_id != _space_id:
		if (
			not force_relocate
			and (
				_pending_space_transition
				or (
					_has_navigation_target
					and (
						previous_route_crosses_portal
						or _route_crosses_portal
					)
				)
			)
		):
			_pending_space_transition = true
			_pending_space_id = next_space_id
			_pending_space_position = next_position
			_pending_space_active = next_space_active
			return {
				"ok": true,
				"status": "space_transition_deferred",
				"residentId": _resident_id,
				"worldRevision": _authority_revision,
				"movementRevision": _movement_revision,
				"spaceId": _space_id,
				"pendingSpaceId": _pending_space_id,
				"targetPosition": _vector_payload(_target_position),
				"worldWriteAttempted": false,
			}
		return _relocate(
			next_space_id,
			next_position,
			world_revision,
			"PRESENTATION_SPACE_RELOCATED",
			correction_distance,
		)
	if force_relocate:
		return _relocate(
			next_space_id,
			next_position,
			world_revision,
			"PRESENTATION_FORCED_RELOCATE",
			correction_distance,
		)
	if (
		correction_distance > large_correction_distance
		and not _continuous_route_follow
	):
		return _relocate(
			next_space_id,
			next_position,
			world_revision,
			"PRESENTATION_LARGE_CORRECTION_RELOCATED",
			correction_distance,
		)
	if phase_name == "thinking" and current_action_type.is_empty():
		_target_position = position
		_navigation_path.clear()
		_has_navigation_target = false
		_authority_route_active = false
		_continuous_route_follow = false
		_target_arrival_seconds_remaining = 0.0
		_route_speed_multiplier = 1.0
		_reset_local_avoidance()
		_reset_target_progress()
		velocity = Vector2.ZERO
		_character_rig.reset_locomotion()
		return {
			"ok": true,
			"status": "held",
			"residentId": _resident_id,
			"worldRevision": _authority_revision,
			"movementRevision": _movement_revision,
			"spaceId": _space_id,
			"targetPosition": _vector_payload(_target_position),
			"worldWriteAttempted": false,
		}
	# World clears currentAction immediately after publishing the final route
	# sample. Presentation may still be interpolating that confirmed sample.
	# Preserve its already-authoritative bends until the body reaches the same
	# endpoint; replacing them with a direct chord would cut across collision at
	# the last corner.
	var preserve_completed_sample_path := (
		not _authority_route_active
		and (presentation_path_value as Array).is_empty()
		and _continuous_route_follow
		and _has_navigation_target
		and not _navigation_path.is_empty()
		and _navigation_path[-1].distance_to(next_position)
			<= ARRIVAL_DISTANCE
	)
	var next_navigation_path: Array[Vector2] = []
	if preserve_completed_sample_path:
		next_navigation_path = _navigation_path.duplicate()
	elif (
		not action_changed
		and movement_revision == previous_movement_revision
	):
		# Unrelated World refreshes may repeat the same movement sample. Keep the
		# already-consumed local progress instead of rebuilding it from the sample.
		next_navigation_path = _navigation_path.duplicate()
	elif (
		not action_changed
		and previous_movement_revision >= 0
		and movement_revision > previous_movement_revision
	):
		next_navigation_path = _merged_navigation_path(
			presentation_path_value as Array,
			next_position,
		)
	else:
		next_navigation_path = _prepared_navigation_path(
			presentation_path_value as Array,
			next_position,
		)
	var next_local_target := (
		next_navigation_path[0]
		if not next_navigation_path.is_empty()
		else next_position
	)
	var target_changed := (
		not _target_position.is_equal_approx(next_local_target)
		or not _navigation_paths_equal(
			_navigation_path,
			next_navigation_path,
		)
	)
	_navigation_path = next_navigation_path
	_target_position = next_local_target
	if (
		_interaction_performing
		and (
			correction_distance <= INTERACTION_SETTLE_DISTANCE
			or (
				_movement_blocked_hold
				and correction_distance
				<= INTERACTION_BLOCKED_SETTLE_DISTANCE
			)
		)
	):
		_settle_interaction_presentation()
		_apply_sleep_visual_body_position()
		return {
			"ok": true,
			"status": "interaction_settled",
			"residentId": _resident_id,
			"worldRevision": _authority_revision,
			"movementRevision": _movement_revision,
			"spaceId": _space_id,
			"targetPosition": _vector_payload(_target_position),
			"worldWriteAttempted": false,
		}
	_has_navigation_target = (
		correction_distance > ARRIVAL_DISTANCE
		or not _navigation_path.is_empty()
	)
	if target_changed:
		if action_changed and not current_action_token.is_empty():
			_reset_target_progress(
				position.distance_to(_target_position)
			)
		else:
			_rebase_target_progress(
				position.distance_to(_target_position)
			)
	if (
		(target_changed or movement_revision != previous_movement_revision)
		and _continuous_route_follow
		and follow_duration_seconds > 0.0
	):
		_target_arrival_seconds_remaining = follow_duration_seconds
		_route_speed_multiplier = clampf(
			1.0 / follow_duration_seconds,
			1.0,
			MAX_SIMULATION_SPEED_MULTIPLIER,
		)
	elif not _continuous_route_follow:
		_target_arrival_seconds_remaining = 0.0
		_route_speed_multiplier = 1.0
	if not _has_navigation_target and not _authority_route_active:
		_continuous_route_follow = false
		_target_arrival_seconds_remaining = 0.0
		_route_speed_multiplier = 1.0
	_apply_sleep_visual_body_position()
	return {
		"ok": true,
		"status": "following" if _has_navigation_target else "confirmed",
		"residentId": _resident_id,
		"worldRevision": _authority_revision,
		"movementRevision": _movement_revision,
		"spaceId": _space_id,
		"targetPosition": _vector_payload(_target_position),
		"worldWriteAttempted": false,
	}


func relocate_authoritatively(
	space_id: String,
	target_position: Vector2,
	world_revision: int,
) -> Dictionary:
	if (
		space_id.strip_edges().is_empty()
		or not _is_finite_vector2_value(target_position)
	):
		return _failure_result(
			"PRESENTATION_AUTHORITY_STATE_INVALID",
			"relocation requires a spaceId and finite target position",
		)
	if world_revision < _authority_revision:
		return _record_diagnostic(
			"PRESENTATION_STALE_AUTHORITY_IGNORED",
			"info",
			world_revision,
			space_id,
			target_position,
			position.distance_to(target_position),
			{"confirmedRevision": _authority_revision},
		)
	_authority_revision = world_revision
	return _relocate(
		space_id,
		target_position,
		world_revision,
		"PRESENTATION_EXPLICIT_RELOCATE",
		position.distance_to(target_position),
	)


func advance_presentation(delta: float) -> void:
	_ensure_built()
	if (
		_presentation_paused
		or _lifecycle_visual_frozen
		or not _space_active
		or not _has_navigation_target
		or delta <= 0.0
	):
		velocity = Vector2.ZERO
		if not _has_navigation_target:
			_reset_local_avoidance()
		_set_visible_rig_motion(
			Vector2.ZERO,
			0.0,
			(
				0.0
				if _presentation_paused or _lifecycle_visual_frozen
				else maxf(delta, 0.0)
			),
		)
		return
	if _movement_blocked_hold:
		_blocked_hold_total_seconds += delta
		if (
			_blocked_hold_total_seconds
				>= BLOCKED_AUTHORITY_RESYNC_SECONDS
			and position.distance_to(_authority_position) > ARRIVAL_DISTANCE
		):
			if _pending_space_transition:
				_recover_blocked_portal_handoff()
				return
			# A same-space obstruction is a presentation failure, not permission to
			# move the visible resident through walls. Keep the confirmed route and
			# resume it only after the corridor clears.
			if not _blocked_authority_stall_diagnostic_emitted:
				_blocked_authority_stall_diagnostic_emitted = true
				_record_diagnostic(
					"PRESENTATION_BLOCKED_AUTHORITY_STALLED",
					"info",
					_authority_revision,
					_space_id,
					_authority_position,
					position.distance_to(_authority_position),
					{"relocated": false},
				)
		_blocked_hold_retry_seconds = maxf(
			0.0,
			_blocked_hold_retry_seconds - delta,
		)
		if (
			_blocked_hold_retry_seconds > 0.0
			or not _blocked_route_is_clear()
		):
			if _blocked_hold_retry_seconds <= 0.0:
				_blocked_hold_retry_seconds = BLOCKED_HOLD_RETRY_SECONDS
			velocity = Vector2.ZERO
			_set_visible_rig_motion(Vector2.ZERO, 0.0, delta)
			return
		_movement_blocked_hold = false
		_reset_target_progress(position.distance_to(_target_position))
	var offset := _target_position - position
	var distance := offset.length()
	if distance <= ARRIVAL_DISTANCE:
		_advance_navigation_target()
		if not _has_navigation_target:
			velocity = Vector2.ZERO
			if not _authority_route_active:
				_continuous_route_follow = false
				_route_speed_multiplier = 1.0
			_reset_local_avoidance()
			_set_visible_rig_motion(Vector2.ZERO, 0.0, delta)
			return
		offset = _target_position - position
		distance = offset.length()
	var direction := offset / distance
	if (
		_interaction_performing
		and distance <= INTERACTION_BLOCKED_SETTLE_DISTANCE
		and test_move(
			global_transform,
			direction * minf(distance, LOCAL_AVOIDANCE_LOOKAHEAD),
		)
	):
		_settle_interaction_presentation()
		return
	var speed_multiplier := (
		_route_speed_multiplier if _continuous_route_follow else 1.0
	)
	var path_distance := _remaining_navigation_distance()
	var requested_distance := minf(
		minf(
			path_distance,
			motion_speed * speed_multiplier * delta,
		),
		maxf(
			MIN_PRESENTATION_DISTANCE_PER_ADVANCE,
			motion_speed * MAX_SIMULATION_SPEED_MULTIPLIER / 60.0,
		),
	)
	if _target_arrival_seconds_remaining > 0.0:
		_target_arrival_seconds_remaining = maxf(
			0.0,
			_target_arrival_seconds_remaining - delta,
		)
	var before := position
	var remaining_distance := requested_distance
	var substep_count := 0
	var original_collision_mask := collision_mask
	# Player and residents share the formal South-entrance spawn. If the player
	# is still standing there when a resident arrives, their feet begin already
	# overlapping and every avoidance probe reports a collision. Ignore only the
	# player layer until this resident has separated; normal avoidance resumes on
	# the first non-overlapping frame.
	if _feet_overlaps_collision_layer(PLAYER_COLLISION_LAYER):
		collision_mask &= ~PLAYER_COLLISION_LAYER
	while (
		remaining_distance > 0.001
		and substep_count < LOCAL_AVOIDANCE_MAX_SUBSTEPS
	):
		var remaining_offset := _target_position - position
		if remaining_offset.length() <= ARRIVAL_DISTANCE:
			_advance_navigation_target()
			if not _has_navigation_target:
				break
			remaining_offset = _target_position - position
		var step_distance := minf(
			minf(
				remaining_distance,
				LOCAL_AVOIDANCE_STEP_DISTANCE,
			),
			remaining_offset.length(),
		)
		var desired_direction := remaining_offset.normalized()
		var steering_direction := _local_avoidance_direction(
			desired_direction,
			step_distance,
		)
		if steering_direction == Vector2.ZERO:
			break
		var step_before := position
		var collision := move_and_collide(
			steering_direction * step_distance,
		)
		var step_travelled := position.distance_to(step_before)
		# A real collision invalidates the rest of this frame's planned motion.
		# Do not spend the remaining distance by steering back into the same
		# obstacle; the next physics frame will probe from the settled position.
		if collision != null:
			var obstacle_normal := collision.get_normal().normalized()
			var tangent := obstacle_normal.orthogonal().normalized()
			if -tangent.dot(steering_direction) > tangent.dot(
				steering_direction,
			):
				tangent = -tangent
			_avoidance_heading = tangent
			_avoidance_side = (
				1
				if desired_direction.cross(tangent) >= 0.0
				else -1
			)
			break
		if step_travelled <= 0.001:
			break
		remaining_distance -= step_travelled
		substep_count += 1
	collision_mask = original_collision_mask
	var travelled := position.distance_to(before)
	velocity = (
		(position - before) / delta
		if travelled > 0.001
		else Vector2.ZERO
	)
	if travelled <= 0.001:
		_blocked_seconds += delta
		if (
			_blocked_seconds >= BLOCKED_DIAGNOSTIC_SECONDS
			and not _blocked_diagnostic_emitted
		):
			_blocked_diagnostic_emitted = true
			_record_diagnostic(
				"PRESENTATION_LOCAL_AVOIDANCE_BLOCKED",
				"info",
				_authority_revision,
				_space_id,
				_target_position,
				position.distance_to(_target_position),
				{
					"lookaheadPx": LOCAL_AVOIDANCE_LOOKAHEAD,
					"collisionMask": collision_mask,
				},
			)
	else:
		_blocked_seconds = 0.0
		_blocked_diagnostic_emitted = false
	var target_distance := position.distance_to(_target_position)
	if (
		target_distance + TARGET_MATERIAL_PROGRESS_DISTANCE
			< _closest_target_distance
	):
		_closest_target_distance = target_distance
		_non_progress_seconds = 0.0
	else:
		_non_progress_seconds += delta
	if (
		_interaction_performing
		and target_distance <= INTERACTION_BLOCKED_SETTLE_DISTANCE
		and _non_progress_seconds >= INTERACTION_NON_PROGRESS_SECONDS
	):
		_settle_interaction_presentation()
		return
	if (
		not _interaction_performing
		and _non_progress_seconds >= MOVEMENT_NON_PROGRESS_HOLD_SECONDS
	):
		if _can_settle_at_occupied_resident_target():
			_settle_occupied_resident_target()
			return
		_hold_blocked_presentation()
		return
	_set_visible_rig_motion(
		velocity.normalized() if travelled > 0.001 else Vector2.ZERO,
		travelled,
		delta,
	)
	if position.distance_to(_target_position) <= ARRIVAL_DISTANCE:
		_advance_navigation_target()


func _set_visible_rig_motion(
	direction: Vector2,
	distance_delta: float,
	delta: float,
) -> void:
	var viewport := get_viewport()
	if viewport == null:
		_character_rig.set_motion(direction, distance_delta, delta)
		return
	if viewport.get_camera_2d() == null:
		_character_rig.set_motion(direction, distance_delta, delta)
		return
	var screen_position := (
		viewport.get_canvas_transform() * global_position
	)
	var animation_rect := viewport.get_visible_rect().grow(160.0)
	if animation_rect.has_point(screen_position):
		_character_rig.set_motion(direction, distance_delta, delta)


func set_space_active(active: bool) -> void:
	_space_active = active
	visible = active
	_set_hit_area_input_enabled(active)
	var physically_active := _resident_is_physically_active()
	_refresh_sleep_body_nodes()
	set_physics_process(
		_automatic_motion
		and physically_active
		and not _presentation_paused
	)
	if not active:
		velocity = Vector2.ZERO
		_character_rig.set_motion(Vector2.ZERO, 0.0, 0.0)


func can_receive_pointer_input() -> bool:
	return (
		_space_active
		and visible
		and is_inside_tree()
		and _hit_area != null
		and _hit_area.input_pickable
		and _hit_area.collision_layer != 0
		and not _lifecycle_visual_frozen
	)


func set_automatic_motion(enabled: bool) -> void:
	_automatic_motion = enabled
	set_physics_process(
		enabled
		and _resident_is_physically_active()
		and not _presentation_paused
	)


func set_presentation_paused(paused: bool) -> void:
	_presentation_paused = paused
	set_physics_process(
		_automatic_motion
		and _resident_is_physically_active()
		and not paused
	)
	if paused:
		velocity = Vector2.ZERO


func set_selected(selected: bool) -> void:
	_ensure_built()
	_selection_marker.visible = (
		selected
		and not _sleep_visual_active
		and not _lifecycle_visual_frozen
		and _space_id == "town_outdoor"
	)


func get_resident_id() -> String:
	return _resident_id


func get_resident_name() -> String:
	return _resident_name


func get_space_id() -> String:
	return _space_id


func get_authority_revision() -> int:
	return _authority_revision


func get_movement_revision() -> int:
	return _movement_revision


func get_navigation_target() -> Vector2:
	return _target_position


func has_navigation_target() -> bool:
	return _has_navigation_target


func is_authority_route_active() -> bool:
	return _authority_route_active


func get_character_rig() -> Variant:
	_ensure_built()
	return _character_rig


func get_head_global_position() -> Vector2:
	_ensure_built()
	return _character_rig.get_head_global_position()


func get_head_screen_position() -> Vector2:
	_ensure_built()
	return _character_rig.get_head_screen_position()


func get_presentation_snapshot() -> Dictionary:
	return {
		"residentId": _resident_id,
		"residentName": _resident_name,
		"spaceId": _space_id,
		"worldRevision": _authority_revision,
		"movementRevision": _movement_revision,
		"position": _vector_payload(position),
		"targetPosition": _vector_payload(_target_position),
		"navigationPath": _vector_array_payload(_navigation_path),
		"hasNavigationTarget": _has_navigation_target,
		"authorityRouteActive": _authority_route_active,
		"routeCrossesPortal": _route_crosses_portal,
		"continuousRouteFollow": _continuous_route_follow,
		"targetArrivalSecondsRemaining": _target_arrival_seconds_remaining,
		"routeSpeedMultiplier": _route_speed_multiplier,
		"collisionMask": collision_mask,
		"localAvoidanceActive": _avoidance_side != 0,
		"localAvoidanceSide": _avoidance_side,
		"localAvoidanceSteerCount": _local_avoidance_steer_count,
		"localAvoidanceBlockedSeconds": _blocked_seconds,
		"interactionPerforming": _interaction_performing,
		"interactionSettled": (
			_interaction_performing and not _has_navigation_target
		),
		"appearancePolicy": _appearance_policy,
		"deathVisualActive": _death_visual_active,
		"deathVisualProgress": clampf(
			_death_visual_elapsed / DEATH_DISSOLVE_SECONDS,
			0.0,
			1.0,
		),
		"sleepVisualActive": _sleep_visual_active,
		"sleepHeadGlobalPosition": _vector_payload(
			_sleep_head_global_position
		),
		"targetNonProgressSeconds": _non_progress_seconds,
		"movementBlockedHold": _movement_blocked_hold,
		"blockedHoldRetrySeconds": _blocked_hold_retry_seconds,
		"blockedHoldTotalSeconds": _blocked_hold_total_seconds,
			"presentationPaused": _presentation_paused,
			"spaceActive": _space_active,
			"pendingSpaceTransition": _pending_space_transition,
			"pendingSpaceId": _pending_space_id,
			"worldWriteAttempted": false,
		"visual": _character_rig.get_rig_state(),
	}


func _lifecycle_policy_for_state(state: Dictionary) -> String:
	var lifecycle := (
		state.get("lifecycle", {}) as Dictionary
		if state.get("lifecycle") is Dictionary
		else {}
	)
	var next_policy := String(
		lifecycle.get("appearancePolicy", "normal"),
	)
	if next_policy not in ["normal", "grayscale"]:
		next_policy = "normal"
	return next_policy


func _apply_lifecycle_appearance(
	state: Dictionary,
	initial_state: bool = false,
) -> void:
	_lifecycle_apply_count += 1
	var next_policy := _lifecycle_policy_for_state(state)
	var previous_policy := _appearance_policy
	_appearance_policy = next_policy
	var dead := next_policy == "grayscale"
	_lifecycle_visual_frozen = dead
	if dead:
		if _grayscale_material == null:
			_grayscale_material = ShaderMaterial.new()
			_grayscale_material.shader = GRAYSCALE_SHADER
		_grayscale_material.set_shader_parameter(
			"grayscale_strength",
			0.0
			if not initial_state and previous_policy != "grayscale"
			else 1.0,
		)
		_character_rig.material = _grayscale_material
		if not initial_state and previous_policy != "grayscale":
			_begin_death_visual()
	else:
		_death_visual_active = false
		_death_visual_elapsed = 0.0
		_death_finished_emitted = false
		set_process(false)
		if _death_dissolve != null:
			_death_dissolve.cancel()
		_character_rig.visible = true
		_character_rig.modulate = Color.WHITE
		_character_rig.material = null
	_set_descendants_use_parent_material(_character_rig, dead)
	_refresh_sleep_body_nodes()


func is_death_dissolve_active() -> bool:
	return _death_visual_active


func prepare_for_resident_replacement() -> void:
	# 补位居民复用稳定席位 ID，但是一个全新的身份。旧居民
	# 死亡前累积的移动修订号不能用来拒绝新居民的初始位置。
	_authority_revision = -1
	_movement_revision = -1
	_applied_appearance = ""
	_apply_lifecycle_appearance({
		"lifecycle": {"appearancePolicy": "normal"},
	})
	_authority_action_token = ""
	velocity = Vector2.ZERO
	_has_navigation_target = false
	_authority_route_active = false
	_navigation_path.clear()
	_target_position = position
	_authority_position = position
	_reset_target_progress()
	_reset_local_avoidance()


func _begin_death_visual() -> void:
	if _death_visual_active or _death_finished_emitted:
		return
	_death_visual_active = true
	_death_visual_elapsed = 0.0
	velocity = Vector2.ZERO
	_has_navigation_target = false
	_authority_route_active = false
	_interaction_performing = false
	_character_rig.modulate = Color.WHITE
	if _selection_marker != null:
		_selection_marker.visible = false
	if _shadow != null:
		_shadow.visible = false
	_refresh_sleep_body_nodes()
	_death_dissolve.start(_resident_id)
	set_process(true)


func _advance_death_visual(delta: float) -> void:
	if not _death_visual_active:
		return
	_death_visual_elapsed += maxf(delta, 0.0)
	var grayscale_progress := clampf(
		_death_visual_elapsed / DEATH_GRAYSCALE_SECONDS,
		0.0,
		1.0,
	)
	if _grayscale_material != null:
		_grayscale_material.set_shader_parameter(
			"grayscale_strength",
			grayscale_progress,
		)
	var dissolve_progress := clampf(
		(_death_visual_elapsed - DEATH_GRAYSCALE_SECONDS * 0.70)
		/ maxf(
			DEATH_DISSOLVE_SECONDS - DEATH_GRAYSCALE_SECONDS * 0.70,
			0.01,
		),
		0.0,
		1.0,
	)
	_character_rig.modulate.a = 1.0 - dissolve_progress
	if _death_visual_elapsed < DEATH_DISSOLVE_SECONDS:
		return
	_death_visual_active = false
	_character_rig.visible = false
	set_process(false)
	if not _death_finished_emitted:
		_death_finished_emitted = true
		death_dissolve_finished.emit(_resident_id)


func _set_descendants_use_parent_material(root: Node, enabled: bool) -> void:
	for child in root.get_children():
		if child is CanvasItem:
			(child as CanvasItem).use_parent_material = enabled
		_set_descendants_use_parent_material(child, enabled)


func take_presentation_diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for diagnostic in _diagnostics:
		result.append(diagnostic.duplicate(true))
	_diagnostics.clear()
	return result


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	z_index = 100
	z_as_relative = false
	add_to_group(SUBJECT_GROUP)
	collision_layer = RESIDENT_COLLISION_LAYER
	collision_mask = ACTIVE_COLLISION_MASK
	_feet_collision = CollisionShape2D.new()
	_feet_collision.name = "FeetCollision"
	_feet_collision.position = Vector2(0.0, -12.0)
	_feet_collision.disabled = false
	var feet_shape := CircleShape2D.new()
	feet_shape.radius = 18.0
	_feet_collision.shape = feet_shape
	add_child(_feet_collision)
	_shadow = Polygon2D.new()
	_shadow.name = "Shadow"
	_shadow.position = Vector2(0.0, -3.0)
	_shadow.polygon = PackedVector2Array([
		Vector2(-30.0, 0.0),
		Vector2(-20.0, -7.0),
		Vector2(20.0, -7.0),
		Vector2(30.0, 0.0),
		Vector2(20.0, 7.0),
		Vector2(-20.0, 7.0),
	])
	_shadow.color = Color(0.02, 0.03, 0.04, 0.32)
	_shadow.z_as_relative = false
	_shadow.z_index = INTERIOR_GROUND_SHADOW_Z_INDEX
	add_child(_shadow)
	_selection_marker = Line2D.new()
	_selection_marker.name = "SelectionMarker"
	_selection_marker.position = Vector2(0.0, -2.0)
	_selection_marker.width = 3.0
	_selection_marker.default_color = Color(1.0, 0.83, 0.31, 0.92)
	_selection_marker.closed = true
	var marker_points := PackedVector2Array()
	for index in 32:
		var angle := TAU * float(index) / 32.0
		marker_points.append(
			Vector2(cos(angle) * 36.0, sin(angle) * 11.0)
		)
	_selection_marker.points = marker_points
	_selection_marker.visible = false
	add_child(_selection_marker)
	_character_rig = CHARACTER_RIG.new()
	_character_rig.name = "FrozenWhitebodyVisual"
	add_child(_character_rig)
	_death_dissolve = DEATH_DISSOLVE_EFFECT.new()
	_death_dissolve.name = "DeathDissolveEffect"
	add_child(_death_dissolve)
	_hit_area = Area2D.new()
	_hit_area.name = "ResidentHitArea"
	_hit_area.position = RESIDENT_HIT_AREA_POSITION
	_hit_area.collision_layer = 1
	_hit_area.collision_mask = 0
	_hit_area.input_pickable = true
	_hit_area.input_event.connect(_on_hit_area_input)
	add_child(_hit_area)
	var hit_shape := CollisionShape2D.new()
	hit_shape.name = "ResidentHitShape"
	var hit_rectangle := RectangleShape2D.new()
	hit_rectangle.size = RESIDENT_HIT_AREA_SIZE
	hit_shape.shape = hit_rectangle
	_hit_area.add_child(hit_shape)


func _relocate(
	space_id: String,
	target_position: Vector2,
	world_revision: int,
	code: String,
	distance: float,
) -> Dictionary:
	var previous_space_id := _space_id
	_space_id = space_id
	_update_ground_shadow_depth()
	position = target_position
	_target_position = target_position
	_navigation_path.clear()
	velocity = Vector2.ZERO
	_has_navigation_target = false
	_authority_route_active = false
	_route_crosses_portal = false
	_continuous_route_follow = false
	_target_arrival_seconds_remaining = 0.0
	_route_speed_multiplier = 1.0
	_local_avoidance_steer_count = 0
	_clear_pending_space_transition()
	_reset_target_progress()
	_reset_local_avoidance()
	# Relocation is a movement correction. Keep the current confirmed activity
	# and facing instead of clearing a pose that was applied from the same
	# authority state immediately before this correction.
	_character_rig.reset_locomotion()
	_refresh_sleep_body_nodes()
	_apply_sleep_visual_body_position()
	if previous_space_id != _space_id:
		visible_space_changed.emit(
			_resident_id,
			previous_space_id,
			_space_id,
		)
	return _record_diagnostic(
		code,
		"info",
		world_revision,
		space_id,
		target_position,
		distance,
		{},
	)


func _update_ground_shadow_depth() -> void:
	if not is_instance_valid(_shadow):
		return
	_shadow.z_as_relative = false
	_shadow.z_index = (
		OUTDOOR_GROUND_SHADOW_Z_INDEX
		if _space_id == "town_outdoor"
		else INTERIOR_GROUND_SHADOW_Z_INDEX
	)


func _record_diagnostic(
	code: String,
	severity: String,
	world_revision: int,
	space_id: String,
	target_position: Vector2,
	distance: float,
	details: Dictionary,
) -> Dictionary:
	var diagnostic := {
		"ok": severity != "error",
		"status": "diagnostic",
		"code": code,
		"severity": severity,
		"residentId": _resident_id,
		"residentName": _resident_name,
		"worldRevision": world_revision,
		"movementRevision": _movement_revision,
		"spaceId": space_id,
		"actualPosition": _vector_payload(position),
		"targetPosition": _vector_payload(target_position),
		"distance": distance,
		"retryable": false,
		"worldWriteAttempted": false,
		"routeChanged": false,
		"details": details.duplicate(true),
	}
	_diagnostics.append(diagnostic)
	if _diagnostics.size() > DIAGNOSTIC_LIMIT:
		_diagnostics.pop_front()
	presentation_diagnostic.emit(diagnostic.duplicate(true))
	return diagnostic


func _state_has_active_route(state: Dictionary) -> bool:
	if state.has("isMoving"):
		return state.get("isMoving", false) == true
	var action_value: Variant = state.get("currentAction")
	if action_value is not Dictionary:
		return false
	var action := action_value as Dictionary
	return String(action.get("type", "")) == "去"


func _recover_blocked_portal_handoff() -> void:
	# While World has already crossed a portal, _authority_position belongs to
	# the pending space. Relocating that coordinate in the outdoor scene sends
	# the resident off-map. Recover to the last confirmed outdoor route point,
	# then perform the already-pending space transition normally.
	var portal_position := (
		_navigation_path[-1]
		if not _navigation_path.is_empty()
		else _target_position
	)
	var recovery_distance := position.distance_to(portal_position)
	position = portal_position
	_target_position = portal_position
	_navigation_path.clear()
	_has_navigation_target = false
	velocity = Vector2.ZERO
	_record_diagnostic(
		"PRESENTATION_BLOCKED_PORTAL_HANDOFF_RECOVERED",
		"info",
		_authority_revision,
		_space_id,
		portal_position,
		recovery_distance,
		{"pendingSpaceId": _pending_space_id},
	)
	_complete_pending_space_transition()


func _local_avoidance_direction(
	desired_direction: Vector2,
	step_distance: float,
) -> Vector2:
	# Never probe beyond the current route bend. A wall after a nearby corner
	# does not block the short segment leading into that corner.
	var probe_distance := minf(
		position.distance_to(_target_position),
		maxf(step_distance, LOCAL_AVOIDANCE_LOOKAHEAD),
	)
	var direct_collision := move_and_collide(
		desired_direction * probe_distance,
		true,
	)
	if direct_collision == null:
		_avoidance_side = 0
		_avoidance_heading = Vector2.ZERO
		return desired_direction
	var obstacle_normal := direct_collision.get_normal().normalized()
	var first_tangent := obstacle_normal.orthogonal().normalized()
	var second_tangent := -first_tangent
	if _avoidance_heading != Vector2.ZERO:
		if second_tangent.dot(_avoidance_heading) > first_tangent.dot(
			_avoidance_heading,
		):
			var swap_heading := first_tangent
			first_tangent = second_tangent
			second_tangent = swap_heading
	elif (
		(position + second_tangent * probe_distance).distance_to(
			_target_position,
		)
		< (position + first_tangent * probe_distance).distance_to(
			_target_position,
		)
	):
		var swap_progress := first_tangent
		first_tangent = second_tangent
		second_tangent = swap_progress
	var tangent_candidates: Array[Vector2] = [
		first_tangent,
		second_tangent,
	]
	for tangent in tangent_candidates:
		var candidate: Vector2 = (
			tangent * 0.9 + desired_direction * 0.1
		).normalized()
		if test_move(global_transform, candidate * probe_distance):
			candidate = tangent
		if test_move(global_transform, candidate * probe_distance):
			continue
		_avoidance_heading = candidate
		_avoidance_side = (
			1
			if desired_direction.cross(candidate) >= 0.0
			else -1
		)
		_local_avoidance_steer_count += 1
		return candidate
	var preferred_side := _avoidance_side if _avoidance_side != 0 else 1
	for side in [preferred_side, -preferred_side]:
		for angle in LOCAL_AVOIDANCE_ANGLES:
			var fallback := desired_direction.rotated(float(side) * angle)
			if test_move(global_transform, fallback * step_distance):
				continue
			_avoidance_heading = fallback
			_avoidance_side = side
			_local_avoidance_steer_count += 1
			return fallback
	return Vector2.ZERO


func _feet_overlaps_collision_layer(layer: int) -> bool:
	if (
		layer <= 0
		or _feet_collision == null
		or _feet_collision.shape == null
		or not is_inside_tree()
	):
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _feet_collision.shape
	query.transform = _feet_collision.global_transform
	query.collision_mask = layer
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(
		query,
		1,
	).is_empty()


func _reset_local_avoidance() -> void:
	_avoidance_side = 0
	_avoidance_heading = Vector2.ZERO
	_blocked_seconds = 0.0
	_blocked_diagnostic_emitted = false


func _reset_target_progress(distance: float = INF) -> void:
	_closest_target_distance = distance
	_non_progress_seconds = 0.0
	_movement_blocked_hold = false
	_blocked_hold_retry_seconds = 0.0
	_blocked_hold_total_seconds = 0.0
	_blocked_authority_stall_diagnostic_emitted = false


func _rebase_target_progress(distance: float) -> void:
	_closest_target_distance = distance


func _hold_blocked_presentation() -> void:
	var diagnostic_was_emitted := _blocked_diagnostic_emitted
	_movement_blocked_hold = true
	_blocked_hold_retry_seconds = BLOCKED_HOLD_RETRY_SECONDS
	velocity = Vector2.ZERO
	_reset_local_avoidance()
	_blocked_diagnostic_emitted = diagnostic_was_emitted
	_character_rig.reset_locomotion()
	if _blocked_diagnostic_emitted:
		return
	_blocked_diagnostic_emitted = true
	_record_diagnostic(
		"PRESENTATION_LOCAL_AVOIDANCE_BLOCKED",
		"info",
		_authority_revision,
		_space_id,
		_target_position,
		position.distance_to(_target_position),
		{
			"lookaheadPx": LOCAL_AVOIDANCE_LOOKAHEAD,
			"collisionMask": collision_mask,
			"visualHold": true,
			"nonProgressSeconds": _non_progress_seconds,
		},
	)


func _blocked_route_is_clear() -> bool:
	var offset := _target_position - position
	var distance := offset.length()
	if distance <= ARRIVAL_DISTANCE:
		return true
	var direction := offset.normalized()
	if not test_move(
		global_transform,
		direction * minf(distance, LOCAL_AVOIDANCE_LOOKAHEAD),
	):
		return true
	# Local avoidance already had a full movement window before entering this
	# hold. Retrying merely because another tangent exists repeats the same
	# circling pattern forever. Resume only after the direct corridor actually
	# clears; otherwise keep the resident still until authority realignment.
	return false


func _can_settle_at_occupied_resident_target() -> bool:
	if (
		_authority_route_active
		or position.distance_to(_target_position)
			> INTERACTION_BLOCKED_SETTLE_DISTANCE
	):
		return false
	var offset := _target_position - position
	if offset.length() <= ARRIVAL_DISTANCE:
		return true
	var collision := move_and_collide(
		offset.normalized()
			* minf(offset.length(), LOCAL_AVOIDANCE_LOOKAHEAD),
		true,
	)
	return (
		collision != null
		and collision.get_collider() is ResidentCharacterBody
	)


func _settle_occupied_resident_target() -> void:
	velocity = Vector2.ZERO
	_navigation_path.clear()
	_target_position = position
	_has_navigation_target = false
	_authority_route_active = false
	_continuous_route_follow = false
	_target_arrival_seconds_remaining = 0.0
	_route_speed_multiplier = 1.0
	_reset_local_avoidance()
	_reset_target_progress()
	_character_rig.reset_locomotion()


func _settle_interaction_presentation() -> void:
	velocity = Vector2.ZERO
	_navigation_path.clear()
	_has_navigation_target = false
	_authority_route_active = false
	_continuous_route_follow = false
	_target_arrival_seconds_remaining = 0.0
	_route_speed_multiplier = 1.0
	_reset_local_avoidance()
	_reset_target_progress()
	_character_rig.reset_locomotion()


func _activity_family_for_cue(cue: Dictionary) -> String:
	var cue_is_prop_action := (
		String(cue.get("actionType", "")) == "用道具"
		or String(cue.get("kind", "")) == "activity"
	)
	if (
		not cue_is_prop_action
		or String(cue.get("phase", "")) != "performing"
	):
		return ""
	var verb := String(
		cue.get(
			"verb",
			cue.get(
				"targetActionVerb",
				cue.get("label", ""),
			),
		)
	).strip_edges()
	if verb.contains("睡"):
		return "sleep"
	if verb.contains("吃") or verb.contains("喝") or verb.contains("饮"):
		return "eat_drink"
	if verb.contains("歇") or verb.contains("休息") or verb.contains("坐"):
		return "rest"
	for keyword in [
		"阅读",
		"资料",
		"书",
		"填表",
		"档案",
		"货单",
	]:
		if verb.contains(keyword):
			return "read_write"
	for keyword in [
		"点单",
		"办事",
		"看诊",
		"检查",
		"取药",
		"交接",
		"议事",
	]:
		if verb.contains(keyword):
			return "service"
	return "work"


func _apply_sleep_visual(
	cue: Dictionary,
	projected_authority_position: Vector2,
	authority_local_position_value: Variant,
) -> void:
	var instance_position_value: Variant = cue.get("instancePosition")
	# C3:睡眠可视状态可在外观/生命周期均不变时切换,刷新只跟随实际切换。
	var was_sleep_visual_active := _sleep_visual_active
	var should_sleep_in_bed := (
		_activity_family_for_cue(cue) == "sleep"
		and String(cue.get("phase", "")) == "performing"
		and not _authority_route_active
		and String(cue.get("assetId", "")) == "single_bed"
		and String(cue.get("direction", "")) == "down"
		and _is_finite_number_pair(instance_position_value)
		and _is_finite_vector2_value(authority_local_position_value)
	)
	if not should_sleep_in_bed:
		_sleep_visual_active = false
		_sleep_head_global_position = Vector2.ZERO
		_sleep_visual_body_position = Vector2.ZERO
		_character_rig.set_sleep_pose(false)
		if was_sleep_visual_active:
			_refresh_sleep_body_nodes()
		return
	var instance_local_position := _vector_from_value(
		instance_position_value
	)
	var authority_local_position := _vector_from_value(
		authority_local_position_value
	)
	var space_projection_offset := (
		projected_authority_position - authority_local_position
	)
	var head_in_actor_root := (
		space_projection_offset
		+ instance_local_position
		+ SLEEP_HEAD_CENTER_OFFSET
	)
	_sleep_visual_body_position = head_in_actor_root
	var parent := get_parent()
	_sleep_head_global_position = (
		(parent as Node2D).to_global(head_in_actor_root)
		if parent is Node2D
		else head_in_actor_root
	)
	_sleep_visual_active = bool(
		_character_rig.set_sleep_pose(
			true,
			_sleep_head_global_position,
		)
	)
	if not _sleep_visual_active:
		_sleep_head_global_position = Vector2.ZERO
		_sleep_visual_body_position = Vector2.ZERO
	if _sleep_visual_active != was_sleep_visual_active:
		_refresh_sleep_body_nodes()


func _restore_authority_position_before_refresh() -> void:
	if not _sleep_body_relocated:
		return
	position = _authority_position
	_sleep_body_relocated = false


func _apply_sleep_visual_body_position() -> void:
	if (
		not _sleep_visual_active
		or _authority_route_active
		or _has_navigation_target
	):
		return
	var parent := get_parent()
	position = (
		(parent as Node2D).to_local(_sleep_head_global_position)
		if parent is Node2D
		else _sleep_visual_body_position
	)
	if _hit_area != null:
		_hit_area.position = to_local(_sleep_head_global_position)
	_sleep_body_relocated = true


# C3 计数口(测试断言用):三组门控各自的实际执行次数。
func get_apply_gate_counts() -> Dictionary:
	return {
		"appearanceApply": _appearance_apply_count,
		"lifecycleApply": _lifecycle_apply_count,
		"sleepRefresh": _sleep_refresh_count,
	}


func _refresh_sleep_body_nodes() -> void:
	_sleep_refresh_count += 1
	var physically_active := _resident_is_physically_active()
	collision_layer = RESIDENT_COLLISION_LAYER if physically_active else 0
	collision_mask = ACTIVE_COLLISION_MASK if physically_active else 0
	set_physics_process(
		_automatic_motion
		and physically_active
		and not _presentation_paused
	)
	# 脚部形状是本地避让契约的一部分：非活动空间的活居民仍保留紧凑脚形；
	# 睡眠或死亡表现期间必须关闭，避免不可行动的身体继续阻挡路线。
	if _feet_collision != null:
		_feet_collision.set_deferred(
			"disabled",
			_sleep_visual_active or _lifecycle_visual_frozen,
		)
	if _shadow != null:
		_shadow.visible = (
			not _sleep_visual_active
			and not _lifecycle_visual_frozen
		)
	if _selection_marker != null and _sleep_visual_active:
		_selection_marker.visible = false
	if _hit_area != null:
		_set_hit_area_input_enabled(_space_active)
		_hit_area.position = (
			to_local(_sleep_head_global_position)
			if _sleep_visual_active
			else RESIDENT_HIT_AREA_POSITION
		)


func _resident_is_physically_active() -> bool:
	return (
		_space_active
		and not _lifecycle_visual_frozen
		and not _sleep_visual_active
	)


func _set_hit_area_input_enabled(active: bool) -> void:
	if _hit_area == null:
		return
	var enabled := active and not _lifecycle_visual_frozen
	_hit_area.input_pickable = enabled
	_hit_area.collision_layer = 1 if enabled else 0


func _is_finite_number_pair(value: Variant) -> bool:
	if value is not Array:
		return false
	var pair := value as Array
	if pair.size() != 2:
		return false
	for component: Variant in pair:
		if component is not int and component is not float:
			return false
		if not is_finite(float(component)):
			return false
	return true


func _vector_from_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	var pair := value as Array
	return Vector2(float(pair[0]), float(pair[1]))


func _failure_result(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": "rejected",
		"code": code,
		"message": message,
		"residentId": _resident_id,
		"retryable": false,
		"worldWriteAttempted": false,
		"routeChanged": false,
	}


func _valid_target(target: Dictionary) -> bool:
	var target_space_id_value: Variant = target.get("spaceId")
	return (
		target_space_id_value is String
		and not String(target_space_id_value).strip_edges().is_empty()
		and _is_finite_vector2_value(target.get("position"))
	)


func _valid_presentation_path(value: Variant) -> bool:
	if value is not Array:
		return false
	for point_value: Variant in (value as Array):
		if not _is_finite_vector2_value(point_value):
			return false
	return true


func _prepared_navigation_path(
	values: Array,
	final_position: Vector2,
) -> Array[Vector2]:
	var points := _normalized_navigation_path(values, final_position)
	if points.is_empty():
		if position.distance_to(final_position) > ARRIVAL_DISTANCE:
			points.append(final_position)
		return points
	if points[-1].distance_to(final_position) > 0.001:
		points.append(final_position)
	var nearest_segment := 0
	var nearest_distance := INF
	if points.size() > 1:
		for index in range(points.size() - 1):
			var projected := Geometry2D.get_closest_point_to_segment(
				position,
				points[index],
				points[index + 1],
			)
			var distance := position.distance_to(projected)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_segment = index
	var result: Array[Vector2] = []
	var start_index := mini(nearest_segment + 1, points.size() - 1)
	for index in range(start_index, points.size()):
		if position.distance_to(points[index]) > ARRIVAL_DISTANCE:
			result.append(points[index])
	return result


func _normalized_navigation_path(
	values: Array,
	final_position: Vector2,
) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for point_value: Variant in values:
		var point := point_value as Vector2
		if points.is_empty() or points[-1].distance_to(point) > 0.001:
			points.append(point)
	if points.is_empty() or points[-1].distance_to(final_position) > 0.001:
		points.append(final_position)
	return points


func _merged_navigation_path(
	values: Array,
	final_position: Vector2,
) -> Array[Vector2]:
	if _navigation_path.is_empty():
		return _prepared_navigation_path(values, final_position)
	var incoming := _normalized_navigation_path(values, final_position)
	if incoming.is_empty():
		return _navigation_path.duplicate()
	var result := _navigation_path.duplicate()
	var join_index := -1
	for index in range(incoming.size() - 1, -1, -1):
		if result[-1].distance_to(incoming[index]) <= ARRIVAL_DISTANCE:
			join_index = index
			break
	if join_index < 0:
		# A skipped or corrected authority sample has no safe overlap with the
		# local queue. Rebase from the visible position without replaying history.
		return _prepared_navigation_path(values, final_position)
	for index in range(join_index + 1, incoming.size()):
		if result[-1].distance_to(incoming[index]) > 0.001:
			result.append(incoming[index])
	return result


func _navigation_paths_equal(
	left: Array[Vector2],
	right: Array[Vector2],
) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if not left[index].is_equal_approx(right[index]):
			return false
	return true


func _remaining_navigation_distance() -> float:
	if not _has_navigation_target:
		return 0.0
	var result := position.distance_to(_target_position)
	var previous := _target_position
	for point: Vector2 in _navigation_path:
		if point.is_equal_approx(previous):
			continue
		result += previous.distance_to(point)
		previous = point
	return result


func _advance_navigation_target() -> void:
	if position.distance_to(_target_position) <= ARRIVAL_DISTANCE:
		position = _target_position
	while (
		not _navigation_path.is_empty()
		and _navigation_path[0].distance_to(position) <= ARRIVAL_DISTANCE
	):
		_navigation_path.pop_front()
	if not _navigation_path.is_empty():
		_target_position = _navigation_path[0]
		_has_navigation_target = true
		_reset_local_avoidance()
		_reset_target_progress(position.distance_to(_target_position))
		return
	_has_navigation_target = false
	if _pending_space_transition:
		_complete_pending_space_transition()
		return
	if not _authority_route_active:
		_continuous_route_follow = false
		_route_speed_multiplier = 1.0
	_reset_local_avoidance()
	_reset_target_progress()


func _complete_pending_space_transition() -> void:
	var pending_space_id := _pending_space_id
	var pending_position := _pending_space_position
	var pending_active := _pending_space_active
	_clear_pending_space_transition()
	_relocate(
		pending_space_id,
		pending_position,
		_authority_revision,
		"PRESENTATION_SPACE_RELOCATED",
		position.distance_to(pending_position),
	)
	set_space_active(pending_active)


func _clear_pending_space_transition() -> void:
	_pending_space_transition = false
	_pending_space_id = ""
	_pending_space_position = Vector2.ZERO
	_pending_space_active = true


func _is_finite_vector2_value(value: Variant) -> bool:
	if value is not Vector2:
		return false
	var vector := value as Vector2
	return is_finite(vector.x) and is_finite(vector.y)


func _on_hit_area_input(
	_viewport: Node,
	event: InputEvent,
	_shape_index: int,
) -> void:
	if (
		not can_receive_pointer_input()
		or not POINTER_INPUT.is_primary_press(event)
	):
		return
	resident_pressed.emit(_resident_id, _resident_name)
	get_viewport().set_input_as_handled()


func _vector_payload(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _vector_array_payload(values: Array[Vector2]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Vector2 in values:
		result.append(_vector_payload(value))
	return result
