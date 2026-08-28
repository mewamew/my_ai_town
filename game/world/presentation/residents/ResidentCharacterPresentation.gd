class_name ResidentCharacterPresentation
extends Node


signal resident_body_created(resident_id: String, body: Node2D)
signal resident_body_removed(resident_id: String)
signal resident_body_space_changed(
	resident_id: String,
	previous_space_id: String,
	space_id: String,
)
signal occlusion_subjects_changed(subjects: Array[Node2D])
signal occlusion_subject_added(subject: Node2D)
signal occlusion_subject_removed(subject_id: int)
signal occlusion_subject_state_changed(subject: Node2D)
signal presentation_diagnostic(diagnostic: Dictionary)
signal resident_selected(resident_id: String, resident_name: String)

const RESIDENT_BODY := preload(
	"res://world/presentation/residents/ResidentCharacterBody.gd"
)
const REQUIRED_WORLD_METHODS := [
	"get_world_revision",
	"get_resident_identity_snapshot",
	"get_all_resident_states",
	"get_resident_movement_snapshot",
	"get_space_character_movement_contract",
]
const DIAGNOSTIC_LIMIT := 128
const REAL_SECONDS_PER_MOVEMENT_SAMPLE := 1.0

var _world: Object
var _actor_root: Node2D
var _active_space_id := "town_outdoor"
var _active_space_origin := Vector2.ZERO
var _last_world_revision := -1
var _bodies: Dictionary = {}
var _active_occlusion_subjects: Array[Node2D] = []
var _diagnostics: Array[Dictionary] = []
var _resident_id_by_name: Dictionary = {}
var _resident_name_by_id: Dictionary = {}
var _space_contracts: Dictionary = {}
var _selected_resident_id := ""
var _world_paused := false


func bind_world(
	world: Object,
	actor_root: Node2D,
	active_space_id: String = "town_outdoor",
	active_space_origin: Vector2 = Vector2.ZERO,
) -> Dictionary:
	if (
		world == null
		or actor_root == null
		or active_space_id.strip_edges().is_empty()
		or not _is_finite_vector2(active_space_origin)
	):
		return _failure_result(
			"PRESENTATION_BINDING_INVALID",
			"world, actor root, spaceId, and a finite space origin are required",
		)
	for method_name_value: Variant in REQUIRED_WORLD_METHODS:
		var method_name := StringName(String(method_name_value))
		if not world.has_method(method_name):
			return _failure_result(
				"PRESENTATION_WORLD_INTERFACE_MISSING",
				"World is missing %s" % String(method_name),
			)
	unbind_world()
	_world = world
	_actor_root = actor_root
	_active_space_id = active_space_id
	_active_space_origin = active_space_origin
	_last_world_revision = -1
	_resident_id_by_name.clear()
	_resident_name_by_id.clear()
	_space_contracts.clear()
	_selected_resident_id = ""
	_connect_world_signals()
	_sync_world_pause_state()
	if not _actor_root.y_sort_enabled:
		_record_diagnostic(
			"PRESENTATION_Y_SORT_HOST_REQUIRED",
			"warning",
			-1,
			{},
		)
	var sync_result := sync_from_world(true)
	if not bool(sync_result.get("ok", false)):
		unbind_world()
		return sync_result
	return {
		"ok": true,
		"status": "bound",
		"residentCount": _bodies.size(),
		"worldRevision": _last_world_revision,
		"activeSpaceId": _active_space_id,
	}


func unbind_world() -> void:
	_disconnect_world_signals()
	_world = null
	_actor_root = null
	_last_world_revision = -1
	_resident_id_by_name.clear()
	_resident_name_by_id.clear()
	_space_contracts.clear()
	_selected_resident_id = ""
	_world_paused = false
	for resident_id_value: Variant in _bodies.keys():
		var body = _bodies.get(resident_id_value)
		if is_instance_valid(body):
			body.queue_free()
	_bodies.clear()
	_refresh_active_occlusion_subjects()


func prepare_resident_replacement(resident_id: String) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	var body := _bodies.get(normalized_id) as ResidentCharacterBody
	if normalized_id.is_empty() or not is_instance_valid(body):
		return _failure_result(
			"PRESENTATION_REPLACEMENT_BODY_MISSING",
			"Replacement resident body is unavailable",
		)
	body.prepare_for_resident_replacement()
	return {
		"ok": true,
		"status": "ready",
		"residentId": normalized_id,
	}


func sync_from_world(force_relocate: bool = false) -> Dictionary:
	if _world == null or _actor_root == null:
		return _failure_result(
			"PRESENTATION_NOT_BOUND",
			"bind_world must be called before synchronization",
		)
	var world_revision_value: Variant = _world.get_world_revision()
	if world_revision_value is not int:
		return _failure_result(
			"PRESENTATION_WORLD_REVISION_INVALID",
			"World revision must be an integer",
		)
	var world_revision := int(world_revision_value)
	if world_revision < _last_world_revision:
		return _record_diagnostic(
			"PRESENTATION_STALE_REFRESH_IGNORED",
			"info",
			world_revision,
			{"confirmedRevision": _last_world_revision},
		)
	var identity_snapshot_value: Variant = _world.get_resident_identity_snapshot()
	if identity_snapshot_value is not Dictionary:
		return _failure_result(
			"PRESENTATION_RESIDENT_IDENTITIES_INVALID",
			"World resident identity snapshot must be a Dictionary",
		)
	var identity_snapshot := identity_snapshot_value as Dictionary
	var identity_status_value: Variant = identity_snapshot.get("status")
	if (
		identity_status_value is not String
		or identity_status_value != "confirmed"
	):
		return _failure_result(
			"PRESENTATION_RESIDENT_IDENTITIES_NOT_CONFIRMED",
			"World resident identities must be confirmed",
		)
	var identity_status := String(identity_status_value)
	var identities_value: Variant = identity_snapshot.get("residents")
	if identities_value is not Array:
		return _failure_result(
			"PRESENTATION_RESIDENT_IDENTITIES_INVALID",
			"World resident identities must be an Array",
		)
	var identities := identities_value as Array
	if identities.is_empty():
		return _failure_result(
			"PRESENTATION_RESIDENT_IDENTITIES_MISSING",
			"World returned no resident identities",
		)
	var states_value: Variant = _world.get_all_resident_states()
	if states_value is not Array:
		return _failure_result(
			"PRESENTATION_RESIDENT_STATES_INVALID",
			"World resident states must be an Array",
		)
	var states := states_value as Array
	var state_by_id: Dictionary = {}
	for state_value: Variant in states:
		if state_value is not Dictionary:
			return _failure_result(
				"PRESENTATION_RESIDENT_STATES_INVALID",
				"Every World resident state must be a Dictionary",
			)
		var state := state_value as Dictionary
		var state_resident_id_value: Variant = state.get("residentId")
		if (
			state_resident_id_value is not String
			or String(state_resident_id_value).strip_edges().is_empty()
			or state_by_id.has(String(state_resident_id_value))
		):
			return _failure_result(
				"PRESENTATION_RESIDENT_STATES_INVALID",
				"World resident states require unique string residentIds",
			)
		state_by_id[String(state_resident_id_value)] = state
	var pending_entries: Array[Dictionary] = []
	var next_resident_id_by_name: Dictionary = {}
	var next_resident_name_by_id: Dictionary = {}
	var confirmed_ids: Dictionary = {}
	var presented_ids: Dictionary = {}
	var resident_name_counts: Dictionary = {}
	var failed_resident_ids: Array[String] = []
	var failed_resident_details: Array[Dictionary] = []
	for identity_value: Variant in identities:
		if identity_value is not Dictionary:
			_record_diagnostic(
				"PRESENTATION_RESIDENT_IDENTITY_INVALID",
				"error",
				world_revision,
				{},
			)
			failed_resident_ids.append("")
			continue
		var identity := identity_value as Dictionary
		var resident_id_value: Variant = identity.get("residentId")
		var resident_name_value: Variant = identity.get("residentName")
		var resident_id := (
			String(resident_id_value).strip_edges()
			if resident_id_value is String
			else ""
		)
		var resident_name := (
			String(resident_name_value).strip_edges()
			if resident_name_value is String
			else ""
		)
		if (
			resident_id.is_empty()
			or resident_name.is_empty()
			or confirmed_ids.has(resident_id)
		):
			_record_diagnostic(
				"PRESENTATION_RESIDENT_IDENTITY_INVALID",
				"error",
				world_revision,
				{"residentId": resident_id},
			)
			failed_resident_ids.append(resident_id)
			continue
		next_resident_name_by_id[resident_id] = resident_name
		resident_name_counts[resident_name] = int(
			resident_name_counts.get(resident_name, 0)
		) + 1
		if int(resident_name_counts[resident_name]) == 1:
			next_resident_id_by_name[resident_name] = resident_id
		else:
			next_resident_id_by_name.erase(resident_name)
		confirmed_ids[resident_id] = true
		var state := state_by_id.get(resident_id, {}) as Dictionary
		if state.is_empty():
			_record_diagnostic(
				"PRESENTATION_RESIDENT_STATE_MISSING",
				"error",
				world_revision,
				{"residentId": resident_id},
			)
			failed_resident_ids.append(resident_id)
			continue
		if not bool(state.get("isPresent", true)):
			continue
		presented_ids[resident_id] = true
		var movement_value: Variant = _world.get_resident_movement_snapshot(resident_id,)
		if movement_value is not Dictionary:
			_record_diagnostic(
				"PRESENTATION_MOVEMENT_SNAPSHOT_MISSING",
				"error",
				world_revision,
				{"residentId": resident_id},
			)
			failed_resident_ids.append(resident_id)
			continue
		var movement := movement_value as Dictionary
		var prepared := _prepare_identity_state(
			identity,
			state,
			world_revision,
			movement,
		)
		if not bool(prepared.get("ok", false)):
			failed_resident_ids.append(resident_id)
			failed_resident_details.append({
				"residentId": resident_id,
				"code": String(
					prepared.get(
						"code",
						prepared.get("errorCode", "UNKNOWN"),
					)
				),
			})
			continue
		pending_entries.append(prepared)
	if not failed_resident_ids.is_empty():
		var incomplete_result := _failure_result(
			"PRESENTATION_WORLD_SNAPSHOT_INCOMPLETE",
			"World snapshot is missing required resident presentation data",
		)
		incomplete_result["worldRevision"] = world_revision
		incomplete_result["failedResidentIds"] = failed_resident_ids.duplicate()
		incomplete_result["failedResidentDetails"] = failed_resident_details.duplicate(
			true,
		)
		return incomplete_result
	for entry: Dictionary in pending_entries:
		if not _prepared_identity_state_can_apply(entry):
			var preflight_result := _failure_result(
				"PRESENTATION_WORLD_SNAPSHOT_APPLY_FAILED",
				"World snapshot could not be applied completely",
			)
			preflight_result["worldRevision"] = world_revision
			preflight_result["failedResidentIds"] = [
				String(entry.get("residentId", "")),
			]
			return preflight_result
	for entry: Dictionary in pending_entries:
		if not _apply_prepared_identity_state(
			entry,
			force_relocate,
		):
			var apply_result := _failure_result(
				"PRESENTATION_WORLD_SNAPSHOT_APPLY_FAILED",
				"World snapshot could not be applied completely",
			)
			apply_result["worldRevision"] = world_revision
			apply_result["failedResidentIds"] = [
				String(entry.get("residentId", "")),
			]
			return apply_result
	_resident_id_by_name = next_resident_id_by_name
	_resident_name_by_id = next_resident_name_by_id
	for resident_id_value: Variant in _bodies.keys():
		var resident_id := String(resident_id_value)
		if presented_ids.has(resident_id):
			continue
		var removed_body = _bodies.get(resident_id)
		_bodies.erase(resident_id)
		if is_instance_valid(removed_body):
			removed_body.queue_free()
		var removed_name := String(_resident_name_by_id.get(resident_id, ""))
		if not removed_name.is_empty():
			_resident_id_by_name.erase(removed_name)
		_resident_name_by_id.erase(resident_id)
		resident_body_removed.emit(resident_id)
	_last_world_revision = world_revision
	_refresh_active_occlusion_subjects()
	return {
		"ok": true,
		"status": "confirmed",
		"identityStatus": identity_status,
		"residentCount": _bodies.size(),
		"worldRevision": _last_world_revision,
		"activeSpaceId": _active_space_id,
	}


func _prepared_identity_state_can_apply(prepared: Dictionary) -> bool:
	var body = prepared.get("body")
	var authority_state := (
		prepared.get("authorityState", {}) as Dictionary
	)
	if body != null:
		return (
			body.has_method("can_apply_authoritative_state")
			and bool(body.call("can_apply_authoritative_state", authority_state))
		)
	var probe = RESIDENT_BODY.new()
	var initial_state := authority_state.duplicate(true)
	initial_state["position"] = (
		prepared.get("projectedPosition", Vector2.ZERO) as Vector2
	)
	var configured := probe.configure(
		prepared.get("identity", {}) as Dictionary,
		initial_state,
	) as Dictionary
	probe.free()
	return bool(configured.get("ok", false))


func _apply_identity_state(
	identity: Dictionary,
	state: Dictionary,
	world_revision: int,
	force_relocate: bool,
	movement_override: Dictionary = {},
) -> bool:
	var resident_id := String(identity.get("residentId", ""))
	var movement := movement_override
	if movement.is_empty():
		var movement_value: Variant = _world.get_resident_movement_snapshot(resident_id,)
		if movement_value is Dictionary:
			movement = movement_value as Dictionary
	var prepared := _prepare_identity_state(
		identity,
		state,
		world_revision,
		movement,
	)
	if not bool(prepared.get("ok", false)):
		return false
	return _apply_prepared_identity_state(prepared, force_relocate)


func _prepare_identity_state(
	identity: Dictionary,
	state: Dictionary,
	world_revision: int,
	movement: Dictionary,
) -> Dictionary:
	var resident_id := String(identity.get("residentId", "")).strip_edges()
	var state_resident_id_value: Variant = state.get("residentId")
	if (
		state_resident_id_value is not String
		or state_resident_id_value != resident_id
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
	):
		_record_diagnostic(
			"PRESENTATION_RESIDENT_STATE_INVALID",
			"error",
			world_revision,
			{"residentId": resident_id},
		)
		return _failure_result(
			"PRESENTATION_RESIDENT_STATE_INVALID",
			"World resident state is malformed",
		)
	if movement.is_empty():
		_record_diagnostic(
			"PRESENTATION_MOVEMENT_SNAPSHOT_MISSING",
			"error",
			world_revision,
			{"residentId": resident_id},
		)
		return _failure_result(
			"PRESENTATION_MOVEMENT_SNAPSHOT_MISSING",
			"World resident movement snapshot is required",
		)
	var movement_resident_id_value: Variant = movement.get("residentId")
	var movement_space_id_value: Variant = movement.get("spaceId")
	var movement_position_value: Variant = movement.get("position")
	var movement_revision_value: Variant = movement.get("movementRevision")
	var movement_world_revision_value: Variant = movement.get("worldRevision")
	var moving_value: Variant = movement.get("isMoving")
	var presentation_path_value: Variant = movement.get(
		"presentationPath",
		[],
	)
	if (
		movement_resident_id_value is not String
		or String(movement_resident_id_value) != resident_id
		or movement_space_id_value is not String
		or String(movement_space_id_value).strip_edges().is_empty()
		or movement_revision_value is not int
		or movement_world_revision_value is not int
		or moving_value is not bool
		or not _is_finite_vector2_value(movement_position_value)
		or not _valid_presentation_path(presentation_path_value)
	):
		_record_diagnostic(
			"PRESENTATION_MOVEMENT_SNAPSHOT_INVALID",
			"error",
			world_revision,
			{"residentId": resident_id},
		)
		return _failure_result(
			"PRESENTATION_MOVEMENT_SNAPSHOT_INVALID",
			"World resident movement snapshot is malformed",
		)
	var target_value: Variant = movement.get("target")
	if (
		target_value is not Dictionary
		or not _valid_target(target_value as Dictionary)
	):
		_record_diagnostic(
			"PRESENTATION_MOVEMENT_SNAPSHOT_INVALID",
			"error",
			world_revision,
			{"residentId": resident_id, "field": "target"},
		)
		return _failure_result(
			"PRESENTATION_MOVEMENT_SNAPSHOT_INVALID",
			"World resident movement target is malformed",
		)
	# The signal projection is a fresh transient dictionary and this method only
	# overlays top-level movement fields. A deep copy repeated every movement
	# sample needlessly cloned the unchanged action/cue dictionaries; preserve
	# isolation with a shallow container copy instead.
	var authority_state := state.duplicate()
	for key: String in [
		"residentId",
		"spaceId",
		"regionId",
		"currentPlace",
		"position",
		"target",
		"isMoving",
		"presentationPath",
		"routeCrossesPortal",
		"movementRevision",
	]:
		authority_state[key] = movement.get(key, authority_state.get(key))
	var body = _bodies.get(resident_id)
	var state_space_id := String(authority_state.get("spaceId", ""))
	authority_state["presentationPath"] = _project_path(
		presentation_path_value as Array,
		state_space_id,
	)
	var movement_contract := _space_movement_contract(
		state_space_id,
		world_revision,
	)
	if movement_contract.is_empty():
		return _failure_result(
			"PRESENTATION_SPACE_MOVEMENT_CONTRACT_INVALID",
			"World space movement contract is required",
		)
	var presentation_policy := (
		movement_contract.get("presentationPolicy", {}) as Dictionary
	)
	var catch_up_distance := float(
		presentation_policy.get("sameSpaceCatchUpMaxDistancePx")
	)
	var projected_position := _project_position(authority_state)
	if not _is_finite_vector2(projected_position):
		_record_diagnostic(
			"PRESENTATION_AUTHORITY_POSITION_INVALID",
			"error",
			world_revision,
			{"residentId": resident_id},
		)
		return _failure_result(
			"PRESENTATION_AUTHORITY_POSITION_INVALID",
			"World resident position must be finite",
		)
	var incoming_world_revision := int(movement_world_revision_value)
	var incoming_movement_revision := int(movement_revision_value)
	if (
		incoming_world_revision > world_revision
		or incoming_world_revision < 0
		or incoming_movement_revision < 0
	):
		return _failure_result(
			"PRESENTATION_MOVEMENT_REVISION_INVALID",
			"World resident movement revisions are invalid",
		)
	if body != null:
		var body_snapshot: Dictionary = body.get_presentation_snapshot()
		var confirmed_world_revision := int(
			body_snapshot.get("worldRevision", -1)
		)
		var confirmed_movement_revision := int(
			body_snapshot.get("movementRevision", -1)
		)
		if (
			incoming_world_revision < confirmed_world_revision
			or incoming_movement_revision < confirmed_movement_revision
		):
			_record_diagnostic(
				"PRESENTATION_STALE_AUTHORITY_REJECTED",
				"error",
				world_revision,
				{
					"residentId": resident_id,
					"confirmedRevision": confirmed_world_revision,
					"confirmedMovementRevision": confirmed_movement_revision,
					"receivedRevision": incoming_world_revision,
					"receivedMovementRevision": incoming_movement_revision,
				},
			)
			return _failure_result(
				"PRESENTATION_STALE_AUTHORITY_REJECTED",
				"World resident movement snapshot is stale",
			)
	elif incoming_world_revision != world_revision:
		return _failure_result(
			"PRESENTATION_MOVEMENT_REVISION_INVALID",
			"Initial resident movement snapshot must match World revision",
		)
	return {
		"ok": true,
		"residentId": resident_id,
		"identity": identity,
		"authorityState": authority_state,
		"movement": movement,
		"body": body,
		"spaceId": state_space_id,
		"catchUpDistance": catch_up_distance,
		"projectedPosition": projected_position,
		"applyWorldRevision": incoming_world_revision,
		"applyMovementRevision": incoming_movement_revision,
	}


func _apply_prepared_identity_state(
	prepared: Dictionary,
	force_relocate: bool,
) -> bool:
	var resident_id := String(prepared.get("residentId", ""))
	var identity := prepared.get("identity", {}) as Dictionary
	var authority_state := (
		prepared.get("authorityState", {}) as Dictionary
	)
	var movement := prepared.get("movement", {}) as Dictionary
	var body = prepared.get("body")
	var state_space_id := String(prepared.get("spaceId", ""))
	var catch_up_distance := float(prepared.get("catchUpDistance", 0.0))
	var projected_position := (
		prepared.get("projectedPosition", Vector2.ZERO) as Vector2
	)
	var apply_world_revision := int(
		prepared.get("applyWorldRevision", -1)
	)
	var apply_movement_revision := int(
		prepared.get("applyMovementRevision", -1)
	)
	var created_body := body == null
	if body == null:
		body = RESIDENT_BODY.new()
		_actor_root.add_child(body)
		var initial_state := authority_state.duplicate(true)
		initial_state["position"] = projected_position
		var configured: Dictionary = body.configure(identity, initial_state)
		if not bool(configured.get("ok", false)):
			body.queue_free()
			_record_diagnostic(
				String(configured.get("code", "PRESENTATION_BODY_CONFIG_FAILED")),
				"error",
				apply_world_revision,
				configured,
			)
			return false
		body.presentation_diagnostic.connect(_on_body_diagnostic)
		body.resident_pressed.connect(_on_resident_pressed)
		body.visible_space_changed.connect(_on_body_visible_space_changed)
		body.occlusion_state_changed.connect(_on_body_occlusion_state_changed)
	var motion_configured: Dictionary = body.configure_motion(
		RESIDENT_BODY.DEFAULT_MOTION_SPEED,
		catch_up_distance,
	)
	if not bool(motion_configured.get("ok", false)):
		if created_body:
			body.queue_free()
		_record_diagnostic(
			String(
				motion_configured.get(
					"code",
					"PRESENTATION_MOTION_CONFIG_FAILED",
				)
			),
			"error",
			apply_world_revision,
			motion_configured,
		)
		return false
	var active := state_space_id == _active_space_id
	body.set_presentation_paused(_world_paused)
	var applied: Dictionary = body.apply_authoritative_state(
		authority_state,
		apply_world_revision,
		projected_position,
		force_relocate and active,
		_world_route_sample_duration()
		if authority_state.get("isMoving", false) == true
		else 0.0,
		active,
	)
	if not bool(applied.get("ok", false)):
		if created_body:
			body.queue_free()
		return false
	if String(applied.get("status", "")) != "space_transition_deferred":
		body.set_space_active(
			String(body.get_presentation_snapshot().get("spaceId", ""))
			== _active_space_id
		)
	var applied_snapshot: Dictionary = body.get_presentation_snapshot()
	if (
		int(applied_snapshot.get("worldRevision", -1))
		!= apply_world_revision
		or int(applied_snapshot.get("movementRevision", -1))
		!= apply_movement_revision
		or not _is_finite_vector2(body.position)
	):
		if created_body:
			body.queue_free()
		return false
	if created_body:
		_bodies[resident_id] = body
		resident_body_created.emit(resident_id, body)
	body.set_selected(resident_id == _selected_resident_id)
	return true


func _sync_changed_resident(state: Dictionary) -> void:
	if _world == null or _actor_root == null:
		return
	var resident_id := String(state.get("residentId", ""))
	if resident_id.is_empty():
		var resident_name := String(state.get("name", ""))
		resident_id = String(_resident_id_by_name.get(resident_name, ""))
	if resident_id.is_empty() or not _bodies.has(resident_id):
		sync_from_world(false)
		return
	var movement_value: Variant = _world.get_resident_movement_snapshot(resident_id,)
	if movement_value is not Dictionary:
		_record_diagnostic(
			"PRESENTATION_MOVEMENT_SNAPSHOT_MISSING",
			"error",
			_last_world_revision,
			{"residentId": resident_id},
		)
		return
	var movement := movement_value as Dictionary
	var world_revision_value: Variant = movement.get("worldRevision")
	if world_revision_value is not int:
		_record_diagnostic(
			"PRESENTATION_MOVEMENT_SNAPSHOT_INVALID",
			"error",
			_last_world_revision,
			{"residentId": resident_id},
		)
		return
	var world_revision := int(world_revision_value)
	if world_revision < _last_world_revision:
		_record_diagnostic(
			"PRESENTATION_STALE_REFRESH_IGNORED",
			"info",
			world_revision,
			{"confirmedRevision": _last_world_revision},
		)
		return
	var identity := {
		"residentId": resident_id,
		"residentName": String(
			_resident_name_by_id.get(
				resident_id,
				state.get("name", ""),
			)
		),
	}
	var applied := _apply_identity_state(
		identity,
		state,
		world_revision,
		false,
		movement,
	)
	if applied:
		_last_world_revision = maxi(_last_world_revision, world_revision)


func _world_route_sample_duration() -> float:
	var simulation_speed := 1
	if _world != null and _world.has_method("get_simulation_speed"):
		simulation_speed = maxi(
			1,
			int(_world.get_simulation_speed()),
		)
	# World produces one movement sample per game minute. At 2x/3x those
	# samples arrive 2x/3x as often, so the visible resident must finish the
	# same sample in the correspondingly shorter real time.
	return REAL_SECONDS_PER_MOVEMENT_SAMPLE / float(simulation_speed)


func set_active_space(space_id: String, space_origin: Vector2) -> Dictionary:
	if (
		space_id.strip_edges().is_empty()
		or not _is_finite_vector2(space_origin)
	):
		return _failure_result(
			"PRESENTATION_SPACE_INVALID",
			"active spaceId and a finite origin are required",
		)
	var previous_space_id := _active_space_id
	var previous_space_origin := _active_space_origin
	_active_space_id = space_id
	_active_space_origin = space_origin
	var sync_result := sync_from_world(true)
	if not bool(sync_result.get("ok", false)):
		_active_space_id = previous_space_id
		_active_space_origin = previous_space_origin
		return sync_result
	# A resident with a pending portal handoff can bypass the normal snapshot
	# refresh. Apply the active-space input boundary immediately so a hidden
	# outdoor body cannot keep receiving pointer events inside a room.
	for body_value: Variant in _bodies.values():
		var body := body_value as Node2D
		if body == null or not body.has_method("get_space_id"):
			continue
		body.set_space_active(
			String(body.get_space_id()) == _active_space_id
		)
	_refresh_active_occlusion_subjects()
	return sync_result


func get_body(resident_id: String) -> Variant:
	return _bodies.get(resident_id)


func can_select_resident(resident_id: String) -> bool:
	var body := _bodies.get(resident_id) as ResidentCharacterBody
	return (
		body != null
		and body.get_space_id() == _active_space_id
		and body.can_receive_pointer_input()
	)


func get_actor(resident_ref: String) -> Node2D:
	return get_body(_resident_id_for_ref(resident_ref))


func get_display_screen_anchor(resident_ref: String) -> Dictionary:
	var body: Variant = get_body(_resident_id_for_ref(resident_ref))
	if body == null or not body.visible:
		return {}
	var screen_position: Vector2 = body.get_global_transform_with_canvas().origin
	return {"x": screen_position.x, "y": screen_position.y}


func get_display_head_screen_anchor(resident_ref: String) -> Dictionary:
	var body: Variant = get_body(_resident_id_for_ref(resident_ref))
	if body == null or not body.visible:
		return {}
	var screen_position: Vector2 = body.get_head_screen_position()
	var viewport_rect: Rect2 = body.get_viewport_rect()
	var visible_in_viewport: bool = (
		viewport_rect.has_area()
		and viewport_rect.has_point(screen_position)
	)
	return {
		"x": screen_position.x,
		"y": screen_position.y,
		"valid": true,
		"visible": visible_in_viewport,
		"kind": "head",
		"coordinateSpace": "viewport_logical",
		"spaceId": body.get_space_id(),
	}


func get_visible_resident_names() -> Array[String]:
	var result: Array[String] = []
	for resident_id_value: Variant in _bodies:
		var resident_id := String(resident_id_value)
		var body = _bodies.get(resident_id)
		if body != null and body.visible:
			result.append(String(_resident_name_by_id.get(resident_id, "")))
	result.sort()
	return result


func get_active_occlusion_subjects() -> Array[Node2D]:
	var snapshot: Array[Node2D] = []
	snapshot.assign(_active_occlusion_subjects)
	return snapshot


func get_visible_badge_names() -> Array[String]:
	return []


func set_selected_resident(resident_ref: String) -> void:
	_selected_resident_id = _resident_id_for_ref(resident_ref)
	for resident_id_value: Variant in _bodies:
		var resident_id := String(resident_id_value)
		var body = _bodies.get(resident_id)
		if body != null:
			body.set_selected(resident_id == _selected_resident_id)


func set_observed_interior(
	place_name: String,
	interior_origin: Vector2,
) -> Dictionary:
	if _world == null or not _world.has_method("get_place_detail"):
		return _failure_result(
			"PRESENTATION_PLACE_INTERFACE_MISSING",
			"World get_place_detail is required for interior observation",
		)
	var place_value: Variant = _world.get_place_detail(place_name)
	if place_value is not Dictionary:
		return _failure_result(
			"PRESENTATION_PLACE_NOT_FOUND",
			"Observed place detail is invalid",
		)
	var place := place_value as Dictionary
	var space_id := String(place.get("spaceId", ""))
	if space_id.is_empty():
		return _failure_result(
			"PRESENTATION_PLACE_NOT_FOUND",
			"Observed place has no World space",
		)
	return set_active_space(space_id, interior_origin)


func clear_observed_interior() -> Dictionary:
	return set_active_space("town_outdoor", Vector2.ZERO)


func get_resident_ids() -> Array[String]:
	var result: Array[String] = []
	for resident_id_value: Variant in _bodies.keys():
		result.append(String(resident_id_value))
	result.sort()
	return result


func get_active_space_id() -> String:
	return _active_space_id


func get_last_world_revision() -> int:
	return _last_world_revision


func get_presentation_snapshot() -> Dictionary:
	var bodies: Array[Dictionary] = []
	for resident_id in get_resident_ids():
		var body: Variant = get_body(resident_id)
		if body != null:
			bodies.append(body.get_presentation_snapshot())
	return {
		"residentCount": _bodies.size(),
		"residentIds": get_resident_ids(),
		"activeSpaceId": _active_space_id,
		"activeSpaceOrigin": _vector_payload(_active_space_origin),
		"worldRevision": _last_world_revision,
		"worldPaused": _world_paused,
		"ySortEnabled": _actor_root != null and _actor_root.y_sort_enabled,
		"visibleResidentNames": get_visible_resident_names(),
		"bodySnapshots": bodies,
		"diagnosticCount": _diagnostics.size(),
		"legacyActorCount": 0,
	}


func take_presentation_diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for diagnostic in _diagnostics:
		result.append(diagnostic.duplicate(true))
	_diagnostics.clear()
	return result


func _project_position(state: Dictionary) -> Vector2:
	var position_value: Variant = state.get("position")
	if not _is_finite_vector2_value(position_value):
		return Vector2(INF, INF)
	var local_position := position_value as Vector2
	if String(state.get("spaceId", "")) == _active_space_id:
		return _active_space_origin + local_position
	return local_position


func _project_path(values: Array, space_id: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var origin := (
		_active_space_origin
		if space_id == _active_space_id
		else Vector2.ZERO
	)
	for point_value: Variant in values:
		result.append(origin + point_value as Vector2)
	return result


func _valid_presentation_path(value: Variant) -> bool:
	if value is not Array:
		return false
	for point_value: Variant in value as Array:
		if not _is_finite_vector2_value(point_value):
			return false
	return true


func _space_movement_contract(
	space_id: String,
	world_revision: int = -1,
) -> Dictionary:
	if _space_contracts.has(space_id):
		# This private cache is consumed read-only by _prepare_identity_state.
		# Deep-copying the complete movement contract for every resident movement
		# sample recreated the largest presentation cost despite the cache hit.
		return _space_contracts.get(space_id, {}) as Dictionary
	var contract_value: Variant = _world.get_space_character_movement_contract(space_id,)
	if contract_value is not Dictionary:
		_record_diagnostic(
			"PRESENTATION_SPACE_MOVEMENT_CONTRACT_MISSING",
			"error",
			world_revision,
			{"spaceId": space_id},
		)
		return {}
	var contract := contract_value as Dictionary
	if contract.is_empty():
		_record_diagnostic(
			"PRESENTATION_SPACE_MOVEMENT_CONTRACT_MISSING",
			"error",
			world_revision,
			{"spaceId": space_id},
		)
		return {}
	var contract_space_id_value: Variant = contract.get("spaceId")
	var presentation_policy_value: Variant = contract.get(
		"presentationPolicy",
	)
	if (
		contract_space_id_value is not String
		or contract_space_id_value != space_id
		or presentation_policy_value is not Dictionary
	):
		_record_diagnostic(
			"PRESENTATION_SPACE_MOVEMENT_CONTRACT_INVALID",
			"error",
			world_revision,
			{"spaceId": space_id},
		)
		return {}
	var presentation_policy := presentation_policy_value as Dictionary
	var distance_value: Variant = presentation_policy.get(
		"sameSpaceCatchUpMaxDistancePx",
	)
	if (
		(distance_value is not int and distance_value is not float)
		or not is_finite(float(distance_value))
		or float(distance_value) <= RESIDENT_BODY.ARRIVAL_DISTANCE
	):
		_record_diagnostic(
			"PRESENTATION_SPACE_MOVEMENT_CONTRACT_INVALID",
			"error",
			world_revision,
			{"spaceId": space_id},
		)
		return {}
	_space_contracts[space_id] = contract.duplicate(true)
	return _space_contracts[space_id] as Dictionary


func _resident_id_for_ref(resident_ref: String) -> String:
	if _bodies.has(resident_ref):
		return resident_ref
	return String(_resident_id_by_name.get(resident_ref, ""))


func _connect_world_signals() -> void:
	_connect_world_signal(
		&"resident_state_changed",
		Callable(self, "_on_resident_state_changed"),
	)
	_connect_world_signal(
		&"resident_place_changed",
		Callable(self, "_on_resident_place_changed"),
	)
	_connect_world_signal(
		&"world_restored",
		Callable(self, "_on_world_restored"),
	)
	_connect_world_signal(
		&"resident_action_phase_changed",
		Callable(self, "_on_resident_action_phase_changed"),
	)
	_connect_world_signal(
		&"lifecycle_state_changed",
		Callable(self, "_on_world_lifecycle_state_changed"),
	)


func _disconnect_world_signals() -> void:
	_disconnect_world_signal(
		&"resident_state_changed",
		Callable(self, "_on_resident_state_changed"),
	)
	_disconnect_world_signal(
		&"resident_place_changed",
		Callable(self, "_on_resident_place_changed"),
	)
	_disconnect_world_signal(
		&"world_restored",
		Callable(self, "_on_world_restored"),
	)
	_disconnect_world_signal(
		&"resident_action_phase_changed",
		Callable(self, "_on_resident_action_phase_changed"),
	)
	_disconnect_world_signal(
		&"lifecycle_state_changed",
		Callable(self, "_on_world_lifecycle_state_changed"),
	)


func _connect_world_signal(signal_name: StringName, callable: Callable) -> void:
	if _world == null or not _world.has_signal(signal_name):
		return
	if not _world.is_connected(signal_name, callable):
		_world.connect(signal_name, callable)


func _disconnect_world_signal(signal_name: StringName, callable: Callable) -> void:
	if _world == null or not _world.has_signal(signal_name):
		return
	if _world.is_connected(signal_name, callable):
		_world.disconnect(signal_name, callable)


func _on_resident_state_changed(_resident_name: String, state: Dictionary) -> void:
	_sync_changed_resident(state)


func _on_resident_place_changed(_resident_name: String, change: Dictionary) -> void:
	var state_value: Variant = change.get("state")
	if state_value is not Dictionary:
		sync_from_world(false)
		return
	var state := state_value as Dictionary
	if state.is_empty():
		sync_from_world(false)
		return
	_sync_changed_resident(state)


func _on_world_restored(_summary: Dictionary) -> void:
	_space_contracts.clear()
	_sync_world_pause_state()
	sync_from_world(true)


func _on_world_lifecycle_state_changed(state: Dictionary) -> void:
	_apply_world_paused(bool(state.get("paused", false)))


func _sync_world_pause_state() -> void:
	if _world == null:
		_apply_world_paused(false)
		return
	if _world.has_method("get_lifecycle_state"):
		var lifecycle_value: Variant = _world.get_lifecycle_state()
		if lifecycle_value is Dictionary:
			_apply_world_paused(
				bool((lifecycle_value as Dictionary).get("paused", false))
			)
			return
	if _world.has_method("is_paused"):
		_apply_world_paused(bool(_world.is_paused()))


func _apply_world_paused(paused: bool) -> void:
	_world_paused = paused
	for body_value: Variant in _bodies.values():
		if is_instance_valid(body_value):
			(body_value as ResidentCharacterBody).set_presentation_paused(
				paused
			)


func _on_resident_action_phase_changed(
	resident_id: String,
	_phase: Dictionary,
) -> void:
	if _world == null or not _world.has_method("get_resident_state"):
		return
	var state_value: Variant = _world.get_resident_state(resident_id)
	if state_value is not Dictionary:
		return
	var state := state_value as Dictionary
	if state.is_empty():
		return
	_sync_changed_resident(state)


func _on_body_diagnostic(diagnostic: Dictionary) -> void:
	_append_diagnostic(diagnostic)
	presentation_diagnostic.emit(diagnostic.duplicate(true))


func _on_resident_pressed(
	resident_id: String,
	resident_name: String,
) -> void:
	if not can_select_resident(resident_id):
		return
	resident_selected.emit(resident_id, resident_name)


func _on_body_visible_space_changed(
	resident_id: String,
	previous_space_id: String,
	space_id: String,
) -> void:
	resident_body_space_changed.emit(
		resident_id,
		previous_space_id,
		space_id,
	)
	var body := _bodies.get(resident_id) as Node2D
	_update_active_occlusion_subject(body)


func _on_body_occlusion_state_changed(subject: Node2D) -> void:
	if not is_instance_valid(subject) or not subject.has_method("get_space_id"):
		return
	_update_active_occlusion_subject(subject)


func _update_active_occlusion_subject(subject: Node2D) -> void:
	if not is_instance_valid(subject) or not subject.has_method("get_space_id"):
		return
	var should_be_active := (
		subject.visible
		and String(subject.get_space_id()) == _active_space_id
	)
	var is_active := _active_occlusion_subjects.has(subject)
	if should_be_active and not is_active:
		_active_occlusion_subjects.append(subject)
		occlusion_subject_added.emit(subject)
	elif not should_be_active and is_active:
		_active_occlusion_subjects.erase(subject)
		occlusion_subject_removed.emit(subject.get_instance_id())
	elif is_active:
		occlusion_subject_state_changed.emit(subject)


func _refresh_active_occlusion_subjects() -> void:
	var next_subjects: Array[Node2D] = []
	for body_value: Variant in _bodies.values():
		var body := body_value as Node2D
		if (
			is_instance_valid(body)
			and body.visible
			and body.has_method("get_space_id")
			and String(body.get_space_id()) == _active_space_id
		):
			next_subjects.append(body)
	if next_subjects == _active_occlusion_subjects:
		return
	_active_occlusion_subjects = next_subjects
	occlusion_subjects_changed.emit(get_active_occlusion_subjects())


func _record_diagnostic(
	code: String,
	severity: String,
	world_revision: int,
	details: Dictionary,
) -> Dictionary:
	var diagnostic := {
		"ok": severity != "error",
		"status": "diagnostic",
		"code": code,
		"severity": severity,
		"worldRevision": world_revision,
		"activeSpaceId": _active_space_id,
		"retryable": false,
		"worldWriteAttempted": false,
		"routeChanged": false,
		"details": details.duplicate(true),
	}
	_append_diagnostic(diagnostic)
	presentation_diagnostic.emit(diagnostic.duplicate(true))
	return diagnostic


func _append_diagnostic(diagnostic: Dictionary) -> void:
	_diagnostics.append(diagnostic.duplicate(true))
	if _diagnostics.size() > DIAGNOSTIC_LIMIT:
		_diagnostics.pop_front()


func _failure_result(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": "rejected",
		"code": code,
		"message": message,
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


func _is_finite_vector2_value(value: Variant) -> bool:
	return value is Vector2 and _is_finite_vector2(value as Vector2)


func _is_finite_vector2(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


func _vector_payload(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
