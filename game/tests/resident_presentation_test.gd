extends "res://tests/support/TownWorldTestCase.gd"
## 居民表现与路由 合并套件。
##
## 由以下测试合并而来，断言逐条保留：
## - resident_character_foundation_test.gd
## - resident_outdoor_collision_route_test.gd
## - town_world_player_avatar_test.gd
## - town_animal_presentation_test.gd
## - town_environment_presentation_test.gd
## - resident_wardrobe_runtime_test.gd
## - town_resident_character_host_test.gd
## - resident_character_world_route_test.gd
## - resident_presentation_path_contract_test.gd

class FakeWorld:
	extends RefCounted

	signal resident_state_changed(resident_name: String, state: Dictionary)
	signal resident_place_changed(resident_name: String, change: Dictionary)
	signal world_restored(summary: Dictionary)
	signal resident_action_phase_changed(resident_id: String, phase: Dictionary)

	var revision := 10
	var all_states_query_count := 0
	var movement_query_count := 0
	var identity_status := "confirmed"
	var moving_by_id: Dictionary = {}
	var missing_movement_ids: Dictionary = {}
	var missing_contract_spaces: Dictionary = {}
	var contract_distance_by_space: Dictionary = {}
	var movement_overrides_by_id: Dictionary = {}
	var identities: Array[Dictionary] = [
		{"residentId": "resident-linlan", "residentName": "林岚"},
		{"residentId": "resident-guchuan", "residentName": "顾川"},
	]
	var states: Array[Dictionary] = [
		_state("resident-linlan", "林岚", "town_outdoor", Vector2(20.0, 30.0)),
		_state("resident-guchuan", "顾川", "indoor_clinic", Vector2(60.0, 70.0)),
	]

	func get_world_revision() -> int:
		return revision

	func get_resident_identity_snapshot() -> Dictionary:
		return {
			"status": identity_status,
			"residents": identities.duplicate(true),
		}

	func get_all_resident_states() -> Array[Dictionary]:
		all_states_query_count += 1
		return states.duplicate(true)

	func get_resident_state(resident_ref: String) -> Dictionary:
		for state in states:
			if (
				String(state.get("residentId", "")) == resident_ref
				or String(state.get("name", "")) == resident_ref
			):
				return state.duplicate(true)
		return {}

	func get_resident_movement_snapshot(resident_id: String) -> Dictionary:
		movement_query_count += 1
		if bool(missing_movement_ids.get(resident_id, false)):
			return {}
		for state in states:
			if String(state.get("residentId", "")) != resident_id:
				continue
			var snapshot := {
				"residentId": resident_id,
				"spaceId": String(state.get("spaceId", "")),
				"regionId": String(state.get("regionId", "")),
				"currentPlace": String(state.get("currentPlace", "")),
				"position": state.get("position", Vector2.ZERO) as Vector2,
				"target": {
					"spaceId": String(state.get("spaceId", "")),
					"position": state.get("position", Vector2.ZERO) as Vector2,
				},
				"isMoving": bool(moving_by_id.get(resident_id, false)),
				"presentationPath": [],
				"routeCrossesPortal": false,
				"movementRevision": int(state.get("movementRevision", 1)),
				"worldRevision": revision,
			}
			for key_value: Variant in (
				movement_overrides_by_id.get(resident_id, {}) as Dictionary
			):
				snapshot[key_value] = (
					movement_overrides_by_id[resident_id] as Dictionary
				)[key_value]
			return snapshot
		return {}

	func get_space_character_movement_contract(space_id: String) -> Dictionary:
		if bool(missing_contract_spaces.get(space_id, false)):
			return {}
		return {
			"contractRevision": "town_character_movement_v1",
			"spaceId": space_id,
			"presentationPolicy": {
				"positionAuthority": "world",
				"collisionBlockedReport": "diagnostic_only",
				"presentationWriteBackAllowed": false,
				"presentationRouteAllowed": false,
				"sameSpaceCatchUpMaxDistancePx": (
					contract_distance_by_space.get(space_id, 64)
				),
				"relocateWhen": [
					"space_changed",
					"distance_exceeded",
					"world_restored",
				],
			},
		}

	func get_place_detail(place_name: String) -> Dictionary:
		if place_name == "诊所":
			return {"name": place_name, "spaceId": "indoor_clinic"}
		return {}

	func update_state(resident_id: String, patch: Dictionary) -> void:
		for index in states.size():
			if String(states[index].get("residentId", "")) != resident_id:
				continue
			var next_state := states[index].duplicate(true)
			for key_value: Variant in patch:
				next_state[key_value] = patch[key_value]
			next_state["movementRevision"] = (
				int(next_state.get("movementRevision", 1)) + 1
			)
			states[index] = next_state
			revision += 1
			resident_state_changed.emit(String(next_state.get("name", "")), next_state)
			return

	func publish_action_phase(resident_id: String, phase_name: String) -> void:
		for index in states.size():
			if String(states[index].get("residentId", "")) != resident_id:
				continue
			var next_state := states[index].duplicate(true)
			var phase := {
				"residentId": resident_id,
				"phase": phase_name,
				"worldRevision": revision,
			}
			next_state["actionPhase"] = phase
			states[index] = next_state
			moving_by_id[resident_id] = false
			resident_action_phase_changed.emit(resident_id, phase)
			return

	static func _state(
		resident_id: String,
		resident_name: String,
		space_id: String,
		position: Vector2,
	) -> Dictionary:
		return {
			"residentId": resident_id,
			"name": resident_name,
			"appearance": "",
			"position": position,
			"spaceId": space_id,
			"regionId": "",
			"currentPlace": "",
			"doing": "",
			"body": {},
			"currentAction": null,
			"actionPhase": {"phase": "idle"},
			"movementRevision": 1,
		}

const FROZEN_WHITEBODY_RIG := preload(
	"res://world/presentation/residents/ResidentFrozenWhitebodyRig.gd"
)
const RESIDENT_BODY := preload(
	"res://world/presentation/residents/ResidentCharacterBody.gd"
)
const RESIDENT_PRESENTATION := preload(
	"res://world/presentation/residents/ResidentCharacterPresentation.gd"
)
const RIG_ASSET_ROOT := (
	"res://assets/characters/resident_2d_rig_v1/direction_branches/"
	+ "identity_unification_v1_pending/turntable_strip_v1"
)
const RIG_CONTRACT_PATH := RIG_ASSET_ROOT + "/rig_contract_v1.json"
const RIG_MANIFEST_PATTERN := RIG_ASSET_ROOT + "/rig_v1/%s/rig_manifest.json"
const FREEZE_MANIFEST_PATH := (
	RIG_ASSET_ROOT
	+ "/production_frozen_v2/whitebody_freeze_manifest_v2.json"
)
const REQUIRED_SECTIONS: Array[String] = [
	"frozen_whitebody_rig",
	"body_contract_and_authority",
	"route_sample_smoothing",
	"layer_one_collision_diagnostic",
	"presentation_registry_and_spaces",
]
const WORLD_DATA_PATH := "res://world/data/town/town_world.json"
const COLLISION_PATH := "res://world/maps/town/generated/collision.json"
const CLEARANCE := preload(
	"res://world/data/town/TownOutdoorMovementClearance.gd"
)
const MOVEMENT := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)
const AGENT_CONTRACT := preload("res://agent/AgentContract.gd")
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const CLINIC_AVATAR_SAFE_RETURN := Vector2(4225.0, 1260.0)
const ANIMAL_PRESENTATION := preload(
	"res://world/presentation/animals/TownAnimalPresentation.gd"
)
const TOWN_RUNTIME_DATA_PATH := "res://world/maps/town/generated/runtime.json"
const EXPECTED_SPECIES_COUNTS := {
	"cat": 3,
	"dog": 0,
	"bird": 3,
}
const ENVIRONMENT_RENDERER := preload(
	"res://world/presentation/environment/TownEnvironmentPresentation.gd"
)
const VISUAL_CONFIG_PATH := (
	"res://world/presentation/environment/town_environment_visuals.json"
)
const MAP_SIZE := Vector2i(6688, 3764)
const MAP_MASK_PATHS: Array[String] = [
	"res://world/presentation/environment/assets/town_puddle_mask.png",
	"res://world/presentation/environment/assets/town_shadow_caster_mask.png",
	"res://world/presentation/environment/assets/town_surface_masks.png",
	"res://world/presentation/environment/assets/town_window_emissive_mask.png",
]
const SNOWFLAKE_ATLAS_PATH := (
	"res://world/presentation/environment/assets/particles/snowflake_atlas_v1.png"
)
const RIG := preload(
	"res://world/presentation/residents/ResidentFrozenWhitebodyRig.gd"
)
const BODY := preload(
	"res://world/presentation/residents/ResidentCharacterBody.gd"
)
const CATALOG := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)
const CANDIDATE_POOL := preload(
	"res://world/presentation/session/TownCustomResidentCandidatePool.gd"
)
const CREATOR_SERVICE := preload(
	"res://world/presentation/session/TownCustomResidentCreatorService.gd"
)
const CREATOR_SCREEN := preload(
	"res://ui/custom_resident_creator/CustomResidentCreatorScreen.gd"
)
const WARDROBE_PAGE := preload(
	"res://ui/wardrobe/WardrobePage.tscn"
)
const WARDROBE_CATALOG_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
	+ "wardrobe_catalog.json"
)
const TOWN_RUNTIME_SCENE := preload(
	"res://world/presentation/town_runtime/TownRuntime.tscn"
)
const RESIDENT_ACTION_WORLD_MENU_SCENE := preload(
	"res://ui/resident_action_menu/ResidentActionWorldMenu.tscn"
)
const PRESENTATION := preload(
	"res://world/presentation/residents/ResidentCharacterPresentation.gd"
)
const RESIDENT_ID := "resident_lin_lan_01"
const PRESENTATION_FRAMES_PER_WORLD_MINUTE := 60

var _completed_sections: Dictionary = {}
var _directions: Dictionary = {}
var _moving_frame_count := 0
var _single_root_frame_count := 0
var _phase_change_count := 0


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_scenario_resident_character_foundation()
	_scenario_resident_outdoor_collision_route()
	_scenario_player_avatar()
	_scenario_animal_presentation()
	_scenario_environment_presentation()
	_scenario_resident_wardrobe_runtime()
	_scenario_resident_character_host()
	_scenario_resident_character_world_route()
	_scenario_resident_presentation_path_contract()
	_finish_suite("RESIDENT_PRESENTATION_PASS")


func _scenario_resident_character_foundation() -> void:
	await _test_frozen_whitebody_rig()
	_test_body_contract_and_authority()
	await _test_apply_gate_signatures()
	await _test_route_sample_smoothing()
	await _test_layer_one_collision_diagnostic()
	_test_presentation_registry_and_spaces()
	return
func _test_frozen_whitebody_rig() -> void:
	var parsed_contract: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(RIG_CONTRACT_PATH)
	)
	var parsed_freeze: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(FREEZE_MANIFEST_PATH)
	)
	_expect(parsed_contract is Dictionary, "18-bone rig contract parses")
	_expect(parsed_freeze is Dictionary, "production frozen whitebody manifest parses")
	if not parsed_contract is Dictionary or not parsed_freeze is Dictionary:
		return
	var rig_contract := parsed_contract as Dictionary
	var freeze_manifest := parsed_freeze as Dictionary
	var scale_decision := rig_contract.get("pixel_scale_decision", {}) as Dictionary
	_expect_equal(
		rig_contract.get("status"),
		"runtime_contract_validated",
		"rig contract records automated runtime validation",
	)
	_expect_equal(
		rig_contract.get("approved_whitebody_root"),
		"production_frozen_v2/whitebody",
		"rig contract points at the included frozen whitebody",
	)
	_expect_equal(rig_contract.get("canvas_size"), [627.0, 627.0], "rig canvas stays 627 square")
	_expect_equal(rig_contract.get("foot_anchor"), [314.5, 591.0], "rig keeps the locked foot anchor")
	_expect_equal(
		scale_decision.get("bone2d_count"),
		18.0,
		"locked rig contract has exactly 18 Bone2D nodes",
	)
	_expect_equal(
		scale_decision.get("artwork_part_count"),
		15.0,
		"locked rig contract has exactly 15 visible parts",
	)
	_expect_equal(
		scale_decision.get("transform_only_bones"),
		["root", "clavicle_l", "clavicle_r"],
		"root and both clavicles remain transform-only",
	)
	var hierarchy := rig_contract.get("bone_hierarchy", []) as Array
	_expect_equal(hierarchy.size(), 18, "rig hierarchy declares all 18 bones")
	_expect_equal(
		freeze_manifest.get("foot_anchor"),
		[314.5, 591.0],
		"freeze manifest shares the rig foot anchor",
	)
	for direction_id in ["down", "right", "up"]:
		var parsed_manifest: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(RIG_MANIFEST_PATTERN % direction_id)
		)
		_expect(
			parsed_manifest is Dictionary,
			"%s rig manifest parses" % direction_id,
		)
		if parsed_manifest is Dictionary:
			_expect_equal(
				(parsed_manifest as Dictionary).get("status"),
				"runtime_contract_validated",
				"%s rig manifest records automated runtime validation" % direction_id,
			)
			_expect_equal(
				(parsed_manifest as Dictionary).get("schema"),
				"ai-town.direction-articulated-rig-manifest.v1",
				"%s rig manifest uses the direction schema" % direction_id,
			)
	var motion_policy := freeze_manifest.get("runtime_motion_policy", {}) as Dictionary
	_expect_equal(
		motion_policy.get("use_old_18_bone_walk_experiment"),
		false,
		"old erroneous 18-bone walk experiment stays disabled",
	)
	var rig = FROZEN_WHITEBODY_RIG.new()
	root.add_child(rig)
	await process_frame
	var wrong_freeze_schema := freeze_manifest.duplicate(true)
	wrong_freeze_schema["schema"] = "invalid.schema"
	_expect_equal(
		rig.call("_validate_freeze_manifest", wrong_freeze_schema),
		false,
		"runtime rejects an unsupported frozen whitebody schema",
	)
	var malformed_contract_canvas := rig_contract.duplicate(true)
	malformed_contract_canvas["canvas_size"] = {
		"width": 627,
		"height": 627,
	}
	_expect_equal(
		rig.call("_validate_rig_contract", malformed_contract_canvas),
		false,
		"runtime rejects a non-array rig contract canvas without casting",
	)
	var malformed_contract_hierarchy := rig_contract.duplicate(true)
	var malformed_hierarchy := (
		malformed_contract_hierarchy.get("bone_hierarchy", []) as Array
	)
	malformed_hierarchy[0] = 7
	malformed_contract_hierarchy["bone_hierarchy"] = malformed_hierarchy
	_expect_equal(
		rig.call("_validate_rig_contract", malformed_contract_hierarchy),
		false,
		"runtime rejects non-dictionary rig hierarchy entries",
	)
	var malformed_scale_decision := rig_contract.duplicate(true)
	malformed_scale_decision["pixel_scale_decision"] = "18 / 15"
	_expect_equal(
		rig.call("_validate_rig_contract", malformed_scale_decision),
		false,
		"runtime rejects a malformed rig scale decision container",
	)
	var parsed_down_manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(RIG_MANIFEST_PATTERN % "down")
	)
	_expect(
		parsed_down_manifest is Dictionary,
		"down rig manifest parses for malformed-joint regression",
	)
	if parsed_down_manifest is Dictionary:
		var malformed_joint_manifest := (
			parsed_down_manifest as Dictionary
		).duplicate(true)
		var malformed_joints := (
			malformed_joint_manifest.get("joints", {}) as Dictionary
		)
		malformed_joints["root"] = [314.5]
		malformed_joint_manifest["joints"] = malformed_joints
		_expect_equal(
			rig.call(
				"_direction_manifest_structure_valid",
				malformed_joint_manifest,
				"down",
			),
			false,
			"runtime rejects malformed joint vectors before building bones",
		)
		malformed_joints["root"] = [NAN, 591.0]
		malformed_joint_manifest["joints"] = malformed_joints
		_expect_equal(
			rig.call(
				"_direction_manifest_structure_valid",
				malformed_joint_manifest,
				"down",
			),
			false,
			"runtime rejects non-finite joint coordinates before building bones",
		)
	var state: Dictionary = rig.get_rig_state()
	_expect_equal(
		state.get("contractValid"),
		true,
		"runtime validates frozen sources and rig manifests",
	)
	_expect_equal(state.get("boneCount"), 18, "active direction builds exactly 18 bones")
	_expect_equal(state.get("skeletonCount"), 3, "down/right/up each build a Skeleton2D")
	_expect_equal(state.get("artworkPartCount"), 15, "active direction has 15 visible pieces")
	_expect_equal(
		state.get("visualSource"),
		"classic_resident_complete_set_v1",
		"runtime reports the complete resident set source",
	)
	_expect_equal(
		state.get("wardrobeEnabled"),
		true,
		"whitebody runtime mounts the approved wardrobe layer",
	)
	_expect_equal(
		rig.find_children("*", "Skeleton2D", true, false).size(),
		3,
		"runtime node tree contains three source skeletons",
	)
	_expect_equal(
		rig.find_children("*", "Bone2D", true, false).size(),
		54,
		"three source skeletons each contain the full 18-bone hierarchy",
	)
	_expect_equal(
		rig.find_children("HeadTopAnchor", "Marker2D", true, false).size(),
		3,
		"each source direction derives a head-top anchor from its head artwork bounds",
	)
	_expect(
		rig.get_head_global_position().y < rig.global_position.y - 100.0,
		"head anchor is above the foot-origin instead of reusing it",
	)
	var first_sprites: Array[Node] = rig.find_children(
		"*",
		"Sprite2D",
		true,
		false,
	)
	for sprite_value: Node in first_sprites:
		var part_sprite := sprite_value as Sprite2D
		_expect_equal(
			part_sprite.texture_filter,
			CanvasItem.TEXTURE_FILTER_NEAREST,
			"every skeletal part uses nearest filtering",
		)
	var second_rig = FROZEN_WHITEBODY_RIG.new()
	root.add_child(second_rig)
	await process_frame
	var second_sprites: Array[Node] = second_rig.find_children(
		"*",
		"Sprite2D",
		true,
		false,
	)
	_expect_equal(
		second_sprites.size(),
		first_sprites.size(),
		"each rig builds the same complete artwork set",
	)
	if second_sprites.size() == first_sprites.size():
		for index in first_sprites.size():
			var first_texture := (first_sprites[index] as Sprite2D).texture
			var second_texture := (second_sprites[index] as Sprite2D).texture
			_expect(
				first_texture != null
				and second_texture != null
				and first_texture.get_instance_id() == second_texture.get_instance_id(),
				"resident rigs share texture resources instead of duplicating them",
			)
	second_rig.queue_free()
	rig.set_direction("left")
	state = rig.get_rig_state()
	_expect_equal(state.get("sourceDirection"), "right", "left uses the locked right source")
	_expect_equal(state.get("leftMirrorsRight"), true, "left is an exact runtime mirror")
	var idle_phase := float(state.get("walkPhase", -1.0))
	rig.set_motion(Vector2.ZERO, 0.0, 0.2)
	_expect_equal(
		rig.get_rig_state().get("walkPhase"),
		idle_phase,
		"idle time never advances the gait phase",
	)
	rig.set_motion(Vector2.RIGHT, 12.0, 0.2)
	state = rig.get_rig_state()
	_expect_equal(state.get("activeDirection"), "right", "movement selects the right skeleton")
	_expect(float(state.get("walkPhase", 0.0)) > idle_phase, "real movement distance advances gait")
	rig.set_activity("用道具")
	for _step in 4:
		rig.set_motion(Vector2.ZERO, 0.0, 0.2)
	state = rig.get_rig_state()
	_expect_equal(
		state.get("activityType"),
		"用道具",
		"a confirmed indoor prop action has a readable non-walking pose",
	)
	_expect(
		float(state.get("activityPhase", 0.0)) > 0.0,
		"non-movement activity continues animating instead of freezing",
	)
	rig.set_activity("用道具", "eat_drink")
	_expect_equal(
		rig.get_rig_state().get("activityFamily"),
		"eat_drink",
		"the character rig owns a small reusable lifestyle animation family",
	)
	rig.set_activity("用道具", "work")
	_expect_equal(
		rig.get_rig_state().get("activityEffect"),
		"work_action_cloud",
		"confirmed work shows the reusable hand-side cartoon action cloud",
	)
	_expect_equal(
		rig.get_rig_state().get("activityEffectVisible"),
		true,
		"the work smoke cue is visible only while work is being performed",
	)
	rig.set_activity("")
	_expect_equal(
		rig.get_rig_state().get("activityType"),
		"",
		"clearing the confirmed action returns the resident to ordinary idle",
	)
	_expect_equal(
		rig.get_rig_state().get("activityEffectVisible"),
		false,
		"clearing work also clears its smoke cue",
	)
	var hidden_down_root := rig.get_node(
		"DownFrozenWhitebodyRig/DownSkeleton2D/root"
	) as Bone2D
	var hidden_down_position := hidden_down_root.position
	rig.set_motion(Vector2.RIGHT, 12.0, 0.2)
	_expect_equal(
		hidden_down_root.position,
		hidden_down_position,
		"walking updates only the active direction skeleton",
	)
	rig.queue_free()
	await process_frame
	_completed_sections["frozen_whitebody_rig"] = true



func _test_body_contract_and_authority() -> void:
	var body = RESIDENT_BODY.new()
	root.add_child(body)
	body.set_automatic_motion(false)
	var configured: Dictionary = body.configure(
		{"residentId": "resident-linlan", "residentName": "林岚"},
		FakeWorld._state(
			"resident-linlan",
			"林岚",
			"town_outdoor",
			Vector2.ZERO,
		),
	)
	_expect_equal(configured.get("ok"), true, "resident body accepts stable identity")
	_expect_equal(
		body.motion_speed,
		144.0,
		"resident default motion uses the readable town-walking speed",
	)
	_expect_equal(body.collision_layer, 4, "resident body occupies the resident collision layer")
	_expect_equal(
		body.collision_mask,
		11,
		"resident body collides with the map, player and ground animals without blocking other authoritative resident routes",
	)
	_expect(body.is_in_group("map_occlusion_subject"), "resident body joins occlusion subjects")
	_expect_equal(body.z_index, 100, "resident body shares the player depth band")
	var feet := body.get_node("FeetCollision") as CollisionShape2D
	_expect_equal(feet.position, Vector2(0.0, -12.0), "feet collision uses player offset")
	_expect(feet.shape is CircleShape2D, "feet collision is circular")
	if feet.shape is CircleShape2D:
		_expect_equal((feet.shape as CircleShape2D).radius, 18.0, "feet collision uses player radius")
	var rig = body.get_node("FrozenWhitebodyVisual")
	_expect(rig != null, "resident body mounts the frozen skeletal visual")
	if rig != null:
		var rig_state: Dictionary = rig.get_rig_state()
		_expect_equal(rig_state.get("contractValid"), true, "resident body uses a valid rig contract")
		_expect_equal(rig_state.get("boneCount"), 18, "resident body uses the locked 18-bone hierarchy")
		_expect_equal(
			rig_state.get("wardrobeEnabled"),
			true,
			"resident body mounts the approved wardrobe slots",
		)
		_expect(
			body.get_head_global_position().y < body.global_position.y - 100.0,
			"resident body exposes the skeletal head-top position",
		)
	_expect_equal(
		body.find_children("*", "Label", true, false).size(),
		0,
		"resident body creates no name-block substitute",
	)
	var identity_rewrite: Dictionary = body.configure(
		{"residentId": "resident-other", "residentName": "其他"},
		{},
	)
	_expect_equal(
		identity_rewrite.get("code"),
		"PRESENTATION_IDENTITY_IMMUTABLE",
		"configured residentId is immutable",
	)
	_expect_equal(body.get_resident_id(), "resident-linlan", "identity rejection preserves residentId")
	var nonfinite_state := FakeWorld._state(
		"resident-linlan",
		"林岚",
		"town_outdoor",
		Vector2(NAN, 18.0),
	)
	var nonfinite_apply: Dictionary = body.apply_authoritative_state(
		nonfinite_state,
		10,
		Vector2(NAN, 18.0),
		true,
	)
	_expect_equal(
		nonfinite_apply.get("code"),
		"PRESENTATION_AUTHORITY_STATE_INVALID",
		"body rejects a non-finite authority position before mutation",
	)
	_expect_equal(
		body.position,
		Vector2.ZERO,
		"rejected non-finite authority preserves the confirmed body position",
	)
	_expect_equal(
		body.get_presentation_snapshot().get("worldRevision"),
		-1,
		"rejected non-finite authority preserves the confirmed body revision",
	)
	var nonfinite_relocate: Dictionary = body.relocate_authoritatively(
		"town_outdoor",
		Vector2(INF, 18.0),
		10,
	)
	_expect_equal(
		nonfinite_relocate.get("code"),
		"PRESENTATION_AUTHORITY_STATE_INVALID",
		"direct authority relocation rejects a non-finite position",
	)
	_expect_equal(
		body.position,
		Vector2.ZERO,
		"rejected direct relocation preserves the confirmed body position",
	)
	var invalid_initial_body = RESIDENT_BODY.new()
	root.add_child(invalid_initial_body)
	var invalid_initial: Dictionary = invalid_initial_body.configure(
		{"residentId": "resident-invalid", "residentName": "非法居民"},
		FakeWorld._state(
			"resident-invalid",
			"非法居民",
			"town_outdoor",
			Vector2(INF, 0.0),
		),
	)
	_expect_equal(
		invalid_initial.get("code"),
		"PRESENTATION_AUTHORITY_STATE_INVALID",
		"body rejects a non-finite initial position",
	)
	_expect_equal(
		invalid_initial_body.get_resident_id(),
		"",
		"rejected initial position does not bind resident identity",
	)
	invalid_initial_body.queue_free()
	var valid_motion: Dictionary = body.configure_motion(120.0, 50.0)
	_expect_equal(valid_motion.get("ok"), true, "finite motion configuration is accepted")
	for invalid_speed: float in [NAN, INF, -INF]:
		var invalid_speed_result: Dictionary = body.configure_motion(
			invalid_speed,
			50.0,
		)
		_expect_equal(
			invalid_speed_result.get("code"),
			"PRESENTATION_MOTION_CONFIG_INVALID",
			"non-finite motion speed is rejected",
		)
	_expect_equal(body.motion_speed, 120.0, "invalid speed preserves confirmed motion speed")
	for invalid_distance: float in [NAN, INF, -INF]:
		var invalid_distance_result: Dictionary = body.configure_motion(
			120.0,
			invalid_distance,
		)
		_expect_equal(
			invalid_distance_result.get("code"),
			"PRESENTATION_MOTION_CONFIG_INVALID",
			"non-finite correction distance is rejected",
		)
	_expect_equal(
		body.large_correction_distance,
		50.0,
		"invalid distance preserves the confirmed correction distance",
	)
	var small_state := FakeWorld._state(
		"resident-linlan",
		"林岚",
		"town_outdoor",
		Vector2(30.0, 0.0),
	)
	var following: Dictionary = body.apply_authoritative_state(small_state, 11)
	_expect_equal(following.get("status"), "following", "small same-space correction is followed")
	_expect_equal(body.position, Vector2.ZERO, "small correction does not teleport")
	_expect_equal(
		rig.get_rig_state().get("activityType"),
		"idle",
		"a resident without a World action keeps a subtle non-semantic idle pose",
	)
	var large_state := small_state.duplicate(true)
	large_state["position"] = Vector2(90.0, 0.0)
	var large_result: Dictionary = body.apply_authoritative_state(large_state, 12)
	_expect_equal(
		large_result.get("code"),
		"PRESENTATION_LARGE_CORRECTION_RELOCATED",
		"configured large correction threshold relocates explicitly",
	)
	_expect_equal(body.position, Vector2(90.0, 0.0), "large correction reaches authority position")
	var route_state := large_state.duplicate(true)
	route_state["position"] = Vector2(260.0, 0.0)
	route_state["isMoving"] = true
	route_state["target"] = {
		"spaceId": "town_outdoor",
		"placeName": "社区花园",
		"position": Vector2(260.0, 0.0),
	}
	route_state["currentAction"] = {"type": "去"}
	var route_result: Dictionary = body.apply_authoritative_state(route_state, 13)
	_expect_equal(
		route_result.get("status"),
		"following",
		"large World route samples remain continuous presentation targets",
	)
	_expect_equal(
		body.position,
		Vector2(90.0, 0.0),
		"active route samples do not teleport or reset the gait",
	)
	var legacy_thinking_route := route_state.duplicate(true)
	legacy_thinking_route["position"] = Vector2(280.0, 0.0)
	legacy_thinking_route["actionPhase"] = {"phase": "thinking"}
	var thinking_route_result: Dictionary = body.apply_authoritative_state(
		legacy_thinking_route,
		14,
	)
	_expect_equal(
		thinking_route_result.get("status"),
		"following",
		"a legacy thinking label cannot stop a confirmed World action",
	)
	_expect(
		body.has_navigation_target(),
		"confirmed movement stays visible while the next Agent decision is pending",
	)
	var indoor_state := large_state.duplicate(true)
	indoor_state["spaceId"] = "indoor_clinic"
	indoor_state["position"] = Vector2(12.0, 14.0)
	var space_result: Dictionary = body.apply_authoritative_state(indoor_state, 15)
	_expect_equal(
		space_result.get("code"),
		"PRESENTATION_SPACE_RELOCATED",
		"cross-space authority uses explicit relocation",
	)
	_expect_equal(body.get_space_id(), "indoor_clinic", "relocation updates presentation space")
	var lifestyle_state := indoor_state.duplicate(true)
	lifestyle_state["currentAction"] = {
		"action_id": "eat-at-table",
		"type": "用道具",
	}
	lifestyle_state["isMoving"] = false
	lifestyle_state["activityCue"] = {
		"actionType": "用道具",
		"prop": "公共食堂西侧餐桌",
		"verb": "吃饭",
		"anchorKind": "inspect",
		"actorFacing": "up",
		"phase": "performing",
	}
	body.apply_authoritative_state(lifestyle_state, 16)
	_expect_equal(
		rig.get_rig_state().get("activityFamily"),
		"eat_drink",
		"character presentation maps a lifestyle verb to its own animation",
	)
	_expect_equal(
		rig.get_rig_state().get("activeDirection"),
		"up",
		"the character faces the prop's authored interaction direction",
	)
	var expected_lifestyle_families := {
		"歇着": "rest",
		"睡觉": "sleep",
		"阅读": "read_write",
		"点单": "service",
		"洗餐具": "work",
	}
	var lifestyle_revision := 17
	for verb_value: Variant in expected_lifestyle_families:
		var verb := String(verb_value)
		var next_lifestyle_state := lifestyle_state.duplicate(true)
		(next_lifestyle_state.get("activityCue", {}) as Dictionary)["verb"] = verb
		body.apply_authoritative_state(
			next_lifestyle_state,
			lifestyle_revision,
		)
		_expect_equal(
			rig.get_rig_state().get("activityFamily"),
			expected_lifestyle_families[verb],
			"character owns the reusable %s lifestyle animation family"
			% expected_lifestyle_families[verb],
		)
		lifestyle_revision += 1
	var bed_sleep_state := lifestyle_state.duplicate(true)
	bed_sleep_state["activityCue"] = {
		"actionType": "用道具",
		"prop": "北街一号住宅单人床",
		"verb": "睡觉",
		"anchorKind": "use",
		"actorFacing": "right",
		"phase": "performing",
		"instanceId": "home_01_single_bed_01",
		"assetId": "single_bed",
		"instancePosition": [200, 300],
		"direction": "down",
	}
	bed_sleep_state["presentationPath"] = []
	bed_sleep_state["target"] = null
	body.apply_authoritative_state(
		bed_sleep_state,
		lifestyle_revision,
	)
	var sleep_snapshot := body.get_presentation_snapshot()
	var sleep_visual := sleep_snapshot.get("visual", {}) as Dictionary
	_expect_equal(
		sleep_snapshot.get("sleepVisualActive"),
		true,
		"a performing bed sleep hides the walking body and shows the pillow head",
	)
	_expect_equal(
		sleep_visual.get("sleeping"),
		true,
		"the resident frame-animation rig enters its bed sleep presentation",
	)
	_expect_equal(
		sleep_visual.get("activeLoadoutId"),
		rig.get_active_loadout_id(),
		"sleep keeps the sleeping resident's own current appearance",
	)
	var sleep_head := rig.get_node_or_null("SleepHead") as Sprite2D
	var complete_set := rig.get_node_or_null("CompleteResidentSet") as Sprite2D
	_expect(
		sleep_head != null
		and complete_set != null
		and sleep_head.texture == complete_set.texture,
		"the pillow head is cropped from the formal resident frame sheet",
	)
	_expect(
		sleep_head != null
		and sleep_head.region_rect.position.y >= 512.0
		and sleep_head.region_rect.end.y <= 1024.0,
		"the pillow head comes from the formal front idle frame",
	)
	_expect_equal(
		body.collision_layer,
		0,
		"the resident no longer blocks the bedside floor while sleeping",
	)
	lifestyle_revision += 1
	var wake_state := bed_sleep_state.duplicate(true)
	(wake_state.get("activityCue", {}) as Dictionary)["verb"] = "歇着"
	body.apply_authoritative_state(wake_state, lifestyle_revision)
	_expect_equal(
		body.get_presentation_snapshot().get("sleepVisualActive"),
		false,
		"leaving the sleep verb restores the ordinary resident body",
	)
	lifestyle_revision += 1
	var formal_activity_state := indoor_state.duplicate(true)
	formal_activity_state["currentAction"] = {
		"action_id": "activity-read-at-clinic",
		"type": "activity.perform",
	}
	formal_activity_state["isMoving"] = false
	formal_activity_state["activityCue"] = {
		"kind": "activity",
		"label": "阅读资料",
		"phase": "performing",
	}
	body.apply_authoritative_state(
		formal_activity_state,
		lifestyle_revision,
	)
	_expect_equal(
		rig.get_rig_state().get("activityFamily"),
		"read_write",
		"formal activity.perform projection drives the matching animation family",
	)
	var stale_state := indoor_state.duplicate(true)
	stale_state["position"] = Vector2(999.0, 999.0)
	var stale_result: Dictionary = body.apply_authoritative_state(stale_state, 14)
	_expect_equal(
		stale_result.get("code"),
		"PRESENTATION_STALE_AUTHORITY_IGNORED",
		"older authority revision is discarded",
	)
	_expect_equal(body.position, Vector2(12.0, 14.0), "stale authority cannot move the body")
	for diagnostic in body.take_presentation_diagnostics():
		_expect_equal(
			diagnostic.get("worldWriteAttempted"),
			false,
			"presentation diagnostics never write World",
		)
		_expect_equal(
			diagnostic.get("routeChanged"),
			false,
			"presentation diagnostics never change routes",
		)
	body.queue_free()

	var portal_body = RESIDENT_BODY.new()
	root.add_child(portal_body)
	portal_body.set_automatic_motion(false)
	portal_body.configure(
		{
			"residentId": "resident-portal-transition",
			"residentName": "跨门居民",
		},
		FakeWorld._state(
			"resident-portal-transition",
			"跨门居民",
			"town_outdoor",
			Vector2.ZERO,
		),
	)
	portal_body.configure_motion(120.0, 64.0)
	var portal_route := FakeWorld._state(
		"resident-portal-transition",
		"跨门居民",
		"town_outdoor",
		Vector2(24.0, 0.0),
	)
	portal_route["movementRevision"] = 2
	portal_route["isMoving"] = true
	portal_route["currentAction"] = {"type": "去"}
	portal_route["routeCrossesPortal"] = true
	portal_route["target"] = {
		"spaceId": "indoor_clinic",
		"position": Vector2(12.0, 14.0),
	}
	portal_route["presentationPath"] = [
		Vector2.ZERO,
		Vector2(24.0, 0.0),
	]
	portal_body.apply_authoritative_state(
		portal_route,
		20,
		null,
		false,
		0.2,
		true,
	)
	var entered_space := portal_route.duplicate(true)
	entered_space["spaceId"] = "indoor_clinic"
	entered_space["position"] = Vector2(12.0, 14.0)
	entered_space["movementRevision"] = 3
	entered_space["isMoving"] = false
	entered_space["currentAction"] = null
	entered_space["presentationPath"] = []
	var deferred_entry: Dictionary = portal_body.apply_authoritative_state(
		entered_space,
		21,
		null,
		false,
		0.0,
		false,
	)
	_expect_equal(
		deferred_entry.get("status"),
		"space_transition_deferred",
		"World changing spaces does not hide a resident before the visible body reaches the portal",
	)
	_expect_equal(
		portal_body.get_space_id(),
		"town_outdoor",
		"the visible body remains in its old space while approaching the portal",
	)
	_expect_equal(
		portal_body.get_presentation_snapshot().get("spaceActive"),
		true,
		"the resident remains visible until the portal path is complete",
	)
	for _index in 13:
		await physics_frame
		portal_body.advance_presentation(1.0 / 60.0)
	var completed_portal_snapshot: Dictionary = (
		portal_body.get_presentation_snapshot()
	)
	_expect_equal(
		completed_portal_snapshot.get("spaceId"),
		"indoor_clinic",
		"the presentation changes space only after reaching the portal",
	)
	_expect_equal(
		completed_portal_snapshot.get("spaceActive"),
		false,
		"the old-space resident hides only after the portal transition completes",
	)
	var indoor_shadow := portal_body.get_node("Shadow") as Polygon2D
	_expect(not indoor_shadow.z_as_relative, "resident ground shadow uses absolute depth")
	_expect_equal(
		indoor_shadow.z_index,
		RESIDENT_BODY.INTERIOR_GROUND_SHADOW_Z_INDEX,
		"resident entering an interior moves its shadow below furniture",
	)
	portal_body.queue_free()
	_completed_sections["body_contract_and_authority"] = true


# C3 门控用例(docs/居民状态通知链减负方案.md):外观/生命周期材质/睡眠刷新
# 三组签名各自独立——未变化的连续事件不再重复解析或遍历,死亡/复活与
# 入睡/醒来的碰撞层、碰撞掩码、脚部形状、阴影切换保持与现状一致。

func _test_apply_gate_signatures() -> void:
	var body = RESIDENT_BODY.new()
	root.add_child(body)
	body.set_automatic_motion(false)
	var base_state := FakeWorld._state(
		"resident-gate",
		"门控",
		"town_outdoor",
		Vector2.ZERO,
	)
	base_state["appearance"] = "resident_wardrobe_v1:look_00"
	base_state["lifecycle"] = {"appearancePolicy": "normal"}
	var configured: Dictionary = body.configure(
		{"residentId": "resident-gate", "residentName": "门控"},
		base_state.duplicate(true),
	)
	_expect_equal(configured.get("ok"), true, "gate body configures with a wardrobe appearance")
	var revision := 10
	body.apply_authoritative_state(base_state.duplicate(true), revision)
	revision += 1
	var counts_before: Dictionary = body.get_apply_gate_counts()
	for _event in range(5):
		body.apply_authoritative_state(base_state.duplicate(true), revision)
		revision += 1
	var counts_after: Dictionary = body.get_apply_gate_counts()
	_expect_equal(
		counts_after.get("appearanceApply"),
		counts_before.get("appearanceApply"),
		"unchanged appearance events stop re-resolving the wardrobe",
	)
	_expect_equal(
		counts_after.get("lifecycleApply"),
		counts_before.get("lifecycleApply"),
		"unchanged lifecycle events stop re-walking the material subtree",
	)
	_expect_equal(
		counts_after.get("sleepRefresh"),
		counts_before.get("sleepRefresh"),
		"events without a sleep toggle stop refreshing sleep body nodes",
	)
	var restyled_state := base_state.duplicate(true)
	restyled_state["appearance"] = "resident_wardrobe_v1:look_01"
	body.apply_authoritative_state(restyled_state.duplicate(true), revision)
	revision += 1
	var counts_restyled: Dictionary = body.get_apply_gate_counts()
	_expect_equal(
		counts_restyled.get("appearanceApply"),
		int(counts_after.get("appearanceApply", 0)) + 1,
		"a real appearance change still resolves and applies once",
	)
	_expect_equal(
		counts_restyled.get("lifecycleApply"),
		int(counts_after.get("lifecycleApply", 0)) + 1,
		"an appearance change re-applies the lifecycle material state",
	)
	var sleep_state := restyled_state.duplicate(true)
	sleep_state["currentAction"] = {"action_id": "gate-sleep", "type": "用道具"}
	sleep_state["activityCue"] = {
		"actionType": "用道具",
		"prop": "北街一号住宅单人床",
		"verb": "睡觉",
		"anchorKind": "use",
		"actorFacing": "right",
		"phase": "performing",
		"instanceId": "gate_single_bed_01",
		"assetId": "single_bed",
		"instancePosition": [200, 300],
		"direction": "down",
	}
	sleep_state["presentationPath"] = []
	sleep_state["target"] = null
	var sleep_refresh_before := int(
		(body.get_apply_gate_counts() as Dictionary).get("sleepRefresh", 0)
	)
	body.apply_authoritative_state(sleep_state.duplicate(true), revision)
	revision += 1
	await process_frame
	var feet := body.get_node("FeetCollision") as CollisionShape2D
	var shadow := body.get_node("Shadow") as Polygon2D
	_expect(not shadow.z_as_relative, "outdoor resident shadow does not inherit actor depth")
	_expect_equal(
		shadow.z_index,
		RESIDENT_BODY.OUTDOOR_GROUND_SHADOW_Z_INDEX,
		"outdoor resident shadow stays below map foreground occluders",
	)
	_expect_equal(
		(body.get_apply_gate_counts() as Dictionary).get("sleepRefresh"),
		sleep_refresh_before + 1,
		"entering bed sleep refreshes the sleep body nodes exactly once",
	)
	_expect_equal(body.collision_layer, 0, "sleep clears the resident collision layer")
	_expect_equal(body.collision_mask, 0, "sleep clears the resident collision mask")
	_expect_equal(feet.disabled, true, "sleep disables the foot shape")
	_expect_equal(shadow.visible, false, "sleep hides the shadow")
	for _event in range(4):
		body.apply_authoritative_state(sleep_state.duplicate(true), revision)
		revision += 1
	_expect_equal(
		(body.get_apply_gate_counts() as Dictionary).get("sleepRefresh"),
		sleep_refresh_before + 1,
		"repeated sleeping events do not refresh sleep body nodes again",
	)
	var wake_state := sleep_state.duplicate(true)
	(wake_state.get("activityCue", {}) as Dictionary)["verb"] = "歇着"
	body.apply_authoritative_state(wake_state.duplicate(true), revision)
	revision += 1
	await process_frame
	_expect_equal(
		(body.get_apply_gate_counts() as Dictionary).get("sleepRefresh"),
		sleep_refresh_before + 2,
		"waking refreshes the sleep body nodes exactly once more",
	)
	_expect_equal(body.collision_layer, 4, "waking restores the resident collision layer")
	_expect_equal(body.collision_mask, 11, "waking restores the resident collision mask")
	_expect_equal(feet.disabled, false, "waking restores the foot shape")
	_expect_equal(shadow.visible, true, "waking restores the shadow")
	var death_state := restyled_state.duplicate(true)
	death_state["lifecycle"] = {"appearancePolicy": "grayscale"}
	var lifecycle_before_death := int(
		(body.get_apply_gate_counts() as Dictionary).get("lifecycleApply", 0)
	)
	body.apply_authoritative_state(death_state.duplicate(true), revision)
	revision += 1
	await process_frame
	_expect_equal(
		(body.get_apply_gate_counts() as Dictionary).get("lifecycleApply"),
		lifecycle_before_death + 1,
		"death applies the lifecycle material state once",
	)
	_expect_equal(body.collision_layer, 0, "death clears the resident collision layer")
	_expect_equal(body.collision_mask, 0, "death clears the resident collision mask")
	_expect_equal(feet.disabled, true, "death disables the foot shape")
	_expect_equal(shadow.visible, false, "death hides the shadow")
	for _event in range(3):
		body.apply_authoritative_state(death_state.duplicate(true), revision)
		revision += 1
	_expect_equal(
		(body.get_apply_gate_counts() as Dictionary).get("lifecycleApply"),
		lifecycle_before_death + 1,
		"repeated dead events do not re-walk the material subtree",
	)
	var revive_state := restyled_state.duplicate(true)
	revive_state["lifecycle"] = {"appearancePolicy": "normal"}
	body.apply_authoritative_state(revive_state.duplicate(true), revision)
	revision += 1
	await process_frame
	_expect_equal(
		(body.get_apply_gate_counts() as Dictionary).get("lifecycleApply"),
		lifecycle_before_death + 2,
		"revival applies the lifecycle material state once more",
	)
	_expect_equal(body.collision_layer, 4, "revival restores the resident collision layer")
	_expect_equal(body.collision_mask, 11, "revival restores the resident collision mask")
	_expect_equal(feet.disabled, false, "revival restores the foot shape")
	_expect_equal(shadow.visible, true, "revival restores the shadow")
	body.queue_free()



func _test_route_sample_smoothing() -> void:
	var body = RESIDENT_BODY.new()
	root.add_child(body)
	body.set_automatic_motion(false)
	body.configure(
		{"residentId": "resident-smooth", "residentName": "平滑居民"},
		FakeWorld._state(
			"resident-smooth",
			"平滑居民",
			"town_outdoor",
			Vector2.ZERO,
		),
	)
	body.configure_motion(420.0, 64.0)
	var route_state := FakeWorld._state(
		"resident-smooth",
		"平滑居民",
		"town_outdoor",
		Vector2(420.0, 0.0),
	)
	route_state["isMoving"] = true
	route_state["target"] = {
		"spaceId": "town_outdoor",
		"placeName": "社区花园",
		"position": Vector2(900.0, 0.0),
	}
	body.apply_authoritative_state(
		route_state,
		30,
		null,
		false,
		1.0,
	)
	var frame_distances: Array[float] = []
	for _index in 60:
		await physics_frame
		var before: Vector2 = body.position
		body.advance_presentation(1.0 / 60.0)
		frame_distances.append(before.distance_to(body.position))
	_expect(
		body.position.distance_to(Vector2(420.0, 0.0)) < 0.1,
		"one World-minute route sample follows the configured 1x movement speed",
	)
	for distance in frame_distances:
		_expect(
			distance > 6.9 and distance < 7.1,
			"route sample advances evenly at the configured speed",
		)
	route_state["position"] = Vector2(840.0, 0.0)
	route_state["movementRevision"] = 2
	body.apply_authoritative_state(
		route_state,
		31,
		null,
		false,
		1.0 / 3.0,
	)
	for _index in 20:
		await physics_frame
		var before: Vector2 = body.position
		body.advance_presentation(1.0 / 60.0)
		var travelled: float = before.distance_to(body.position)
		_expect(
			travelled > 20.9 and travelled < 21.1,
			"3x simulation uses the same route distance at three times visible speed",
		)
	_expect(
		body.position.distance_to(Vector2(840.0, 0.0)) < 0.1,
		"3x simulation reaches the confirmed sample without a late catch-up jump",
	)
	route_state["position"] = Vector2(1440.0, 0.0)
	route_state["movementRevision"] = 3
	body.apply_authoritative_state(
		route_state,
		32,
		null,
		false,
		1.0,
	)
	await physics_frame
	var before_large_gap: Vector2 = body.position
	body.advance_presentation(1.0 / 60.0)
	var large_gap_travelled: float = before_large_gap.distance_to(
		body.position
	)
	_expect(
		large_gap_travelled > 6.9 and large_gap_travelled < 7.1,
		"an abnormal authority gap no longer forces the resident to chase it in one second",
	)
	body.queue_free()

	var bent_body = RESIDENT_BODY.new()
	root.add_child(bent_body)
	bent_body.set_automatic_motion(false)
	bent_body.configure(
		{
			"residentId": "resident-bent-route",
			"residentName": "折线路径居民",
		},
		FakeWorld._state(
			"resident-bent-route",
			"折线路径居民",
			"town_outdoor",
			Vector2.ZERO,
		),
	)
	bent_body.configure_motion(420.0, 64.0)
	var bent_state := FakeWorld._state(
		"resident-bent-route",
		"折线路径居民",
		"town_outdoor",
		Vector2(120.0, 120.0),
	)
	bent_state["isMoving"] = true
	bent_state["currentAction"] = {"type": "去"}
	bent_state["target"] = {
		"spaceId": "town_outdoor",
		"placeName": "社区花园",
		"position": Vector2(120.0, 120.0),
	}
	bent_state["presentationPath"] = [
		Vector2.ZERO,
		Vector2(0.0, 120.0),
		Vector2(120.0, 120.0),
	]
	bent_body.apply_authoritative_state(
		bent_state,
		40,
		null,
		false,
		1.0,
	)
	for _index in 17:
		await physics_frame
		bent_body.advance_presentation(1.0 / 60.0)
	_expect(
		absf(bent_body.position.x) < 0.1
		and bent_body.position.y > 118.0,
		"presentation follows the confirmed bend instead of cutting its chord",
	)
	var completed_sample := bent_state.duplicate(true)
	completed_sample["currentAction"] = null
	completed_sample["isMoving"] = false
	completed_sample["presentationPath"] = []
	bent_body.apply_authoritative_state(
		completed_sample,
		41,
		null,
		false,
		0.5,
	)
	for _index in 19:
		await physics_frame
		bent_body.advance_presentation(1.0 / 60.0)
	_expect(
		bent_body.position.distance_to(Vector2(120.0, 120.0)) < 0.1,
		"clearing the completed World action preserves the final confirmed bend",
	)
	bent_body.queue_free()
	_completed_sections["route_sample_smoothing"] = true



func _test_layer_one_collision_diagnostic() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	var wall := StaticBody2D.new()
	wall.position = Vector2(45.0, -12.0)
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_collision := CollisionShape2D.new()
	var wall_shape := RectangleShape2D.new()
	wall_shape.size = Vector2(20.0, 1200.0)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	stage.add_child(wall)
	var body = RESIDENT_BODY.new()
	stage.add_child(body)
	body.configure(
		{"residentId": "resident-blocked", "residentName": "受阻居民"},
		FakeWorld._state(
			"resident-blocked",
			"受阻居民",
			"town_outdoor",
			Vector2.ZERO,
		),
	)
	body.configure_motion(120.0, 64.0)
	var target_state := FakeWorld._state(
		"resident-blocked",
		"受阻居民",
		"town_outdoor",
		Vector2(300.0, 0.0),
	)
	target_state["isMoving"] = true
	target_state["target"] = {
		"spaceId": "town_outdoor",
		"placeName": "社区花园",
		"position": Vector2(300.0, 0.0),
	}
	target_state["currentAction"] = {"type": "去"}
	body.apply_authoritative_state(target_state, 20)
	await physics_frame
	for _index in 90:
		await physics_frame
	var diagnostics: Array[Dictionary] = body.take_presentation_diagnostics()
	_expect(
		_has_diagnostic(
			diagnostics,
			"PRESENTATION_LOCAL_AVOIDANCE_BLOCKED",
		),
		"formal layer-one StaticBody produces a blocked diagnostic",
	)
	_expect(body.position.x < 35.0, "resident body does not pass through layer-one furniture")
	_expect(body.has_navigation_target(), "collision does not invent a replacement route")
	target_state["position"] = Vector2(600.0, 0.0)
	target_state["movementRevision"] = 2
	body.apply_authoritative_state(target_state, 21)
	for _index in 10:
		await physics_frame
	_expect(
		body.position.x < 35.0,
		"later large World route samples cannot pull a blocked resident through furniture",
	)
	var snapshot: Dictionary = body.get_presentation_snapshot()
	_expect_equal(
		snapshot.get("continuousRouteFollow"),
		true,
		"blocked route remains a presentation target instead of becoming a teleport",
	)
	for diagnostic in body.take_presentation_diagnostics():
		_expect_equal(
			diagnostic.get("worldWriteAttempted"),
			false,
			"blocked route diagnostics never write World",
		)
		_expect_equal(
			diagnostic.get("routeChanged"),
			false,
			"blocked route diagnostics never replace the World route",
		)
	stage.queue_free()
	await process_frame
	_completed_sections["layer_one_collision_diagnostic"] = true



func _test_presentation_registry_and_spaces() -> void:
	var actor_root := Node2D.new()
	actor_root.y_sort_enabled = true
	root.add_child(actor_root)
	var world := FakeWorld.new()
	var presentation = RESIDENT_PRESENTATION.new()
	root.add_child(presentation)
	var selected_residents: Array[Dictionary] = []
	presentation.resident_selected.connect(
		func(resident_id: String, resident_name: String) -> void:
			selected_residents.append({
				"residentId": resident_id,
				"residentName": resident_name,
			})
	)
	var bound: Dictionary = presentation.bind_world(world, actor_root)
	_expect_equal(bound.get("ok"), true, "presentation binds public World queries")
	_expect_equal(bound.get("residentCount"), 2, "presentation creates the full identity set")
	var outdoor_body: Variant = presentation.get_body("resident-linlan")
	var indoor_body: Variant = presentation.get_body("resident-guchuan")
	_expect(outdoor_body != null and outdoor_body.visible, "active outdoor resident is visible")
	_expect(indoor_body != null and not indoor_body.visible, "inactive indoor resident is hidden")
	var indoor_result: Dictionary = presentation.set_active_space(
		"indoor_clinic",
		Vector2(1000.0, 2000.0),
	)
	_expect_equal(indoor_result.get("ok"), true, "presentation activates an indoor space")
	_expect(outdoor_body != null and not outdoor_body.visible, "outdoor resident hides indoors")
	_expect(indoor_body != null and indoor_body.visible, "matching indoor resident becomes visible")
	if indoor_body != null:
		_expect_equal(
			indoor_body.position,
			Vector2(1060.0, 2070.0),
			"indoor relocation applies the host-provided space origin",
		)
	world.all_states_query_count = 0
	world.movement_query_count = 0
	world.update_state(
		"resident-guchuan",
		{"position": Vector2(80.0, 90.0)},
	)
	_expect_equal(
		presentation.get_last_world_revision(),
		11,
		"public resident signal refreshes the confirmed revision",
	)
	_expect_equal(
		world.all_states_query_count,
		0,
		"one resident signal never triggers a full 15-resident rescan",
	)
	_expect_equal(
		world.movement_query_count,
		1,
		"one resident signal refreshes only that resident movement snapshot",
	)
	var movement_state := (
		world.get_resident_state("resident-guchuan") as Dictionary
	)
	movement_state["position"] = Vector2(180.0, 90.0)
	movement_state["movementRevision"] = (
		int(movement_state.get("movementRevision", 1)) + 1
	)
	world.moving_by_id["resident-guchuan"] = true
	world.movement_overrides_by_id["resident-guchuan"] = {
		"presentationPath": [
			Vector2(80.0, 90.0),
			Vector2(180.0, 90.0),
		],
	}
	for index in world.states.size():
		if String(world.states[index].get("residentId", "")) == "resident-guchuan":
			world.states[index] = movement_state
			break
	world.revision += 1
	world.resident_state_changed.emit("顾川", movement_state)
	_expect(
		indoor_body != null and indoor_body.has_navigation_target(),
		"moving World snapshot starts presentation interpolation",
	)
	_expect_equal(
		indoor_body.get_navigation_target()
			if indoor_body != null
			else Vector2.ZERO,
		# 逐途径点导航下目标是路径首点 (80,90)，投影偏移与本体一致。
		Vector2(1080.0, 2090.0),
		"indoor presentation path uses the same projected coordinates as the body",
	)
	world.movement_query_count = 0
	world.publish_action_phase("resident-guchuan", "thinking")
	_expect_equal(
		world.movement_query_count,
		1,
		"action phase signal refreshes only the affected resident movement",
	)
	_expect(
		indoor_body != null and not indoor_body.has_navigation_target(),
		"thinking phase immediately stops the visible interpolation",
	)
	_expect(
		indoor_body != null and not indoor_body.is_authority_route_active(),
		"thinking phase publishes a stopped presentation route",
	)
	if indoor_body != null:
		var same_revision_state := (
			world.get_resident_state("resident-guchuan") as Dictionary
		)
		same_revision_state["currentAction"] = {"type": "用道具"}
		same_revision_state["activityCue"] = {
			"actionType": "用道具",
			"verb": "阅读",
			"phase": "performing",
			"actorFacing": "down",
		}
		for index in world.states.size():
			if (
				String(world.states[index].get("residentId", ""))
				== "resident-guchuan"
			):
				world.states[index] = same_revision_state
				break
		world.resident_action_phase_changed.emit(
			"resident-guchuan",
			{"phase": "performing", "worldRevision": world.revision},
		)
		_expect_equal(
			indoor_body.get_character_rig().get_rig_state().get("activityFamily"),
			"read_write",
			"same-revision action phase still refreshes the visible activity",
		)
		indoor_body.resident_pressed.emit("resident-guchuan", "顾川")
		_expect_equal(
			selected_residents,
			[{
				"residentId": "resident-guchuan",
				"residentName": "顾川",
			}],
			"resident selection preserves the stable resident ID",
		)
	world.identities.append({
		"residentId": "resident-guchuan-duplicate-name",
		"residentName": "顾川",
	})
	world.states.append(
		FakeWorld._state(
			"resident-guchuan-duplicate-name",
			"顾川",
			"indoor_clinic",
			Vector2(90.0, 100.0),
		)
	)
	world.revision += 1
	var duplicate_name_sync: Dictionary = presentation.sync_from_world(true)
	_expect_equal(
		duplicate_name_sync.get("ok"),
		true,
		"presentation accepts distinct residents with the same display name",
	)
	_expect(
		presentation.get_actor("顾川") == null,
		"ambiguous duplicate names never resolve to an arbitrary resident",
	)
	_expect(
		presentation.get_actor("resident-guchuan") != null
		and presentation.get_actor("resident-guchuan-duplicate-name") != null,
		"both same-name residents remain addressable by stable ID",
	)
	var confirmed_revision := presentation.get_last_world_revision()
	var confirmed_ids := presentation.get_resident_ids()
	var confirmed_linlan: Variant = presentation.get_body("resident-linlan")
	var confirmed_linlan_position: Vector2 = confirmed_linlan.position
	var confirmed_states := world.states.duplicate(true)
	world.identity_status = "pending"
	world.revision += 1
	var pending_identity_sync: Dictionary = presentation.sync_from_world(true)
	_expect_equal(
		pending_identity_sync.get("code"),
		"PRESENTATION_RESIDENT_IDENTITIES_NOT_CONFIRMED",
		"pending resident identities are never presented as formal residents",
	)
	_expect_equal(
		presentation.get_last_world_revision(),
		confirmed_revision,
		"pending identities do not consume the World revision",
	)
	_expect_equal(
		presentation.get_resident_ids(),
		confirmed_ids,
		"pending identities preserve the confirmed registry",
	)
	world.identity_status = "confirmed"
	world.revision = confirmed_revision
	world.states[0]["position"] = Vector2(NAN, 18.0)
	world.revision += 1
	var nonfinite_position_sync: Dictionary = presentation.sync_from_world(true)
	_expect_equal(
		nonfinite_position_sync.get("code"),
		"PRESENTATION_WORLD_SNAPSHOT_INCOMPLETE",
		"non-finite World positions reject the full synchronization",
	)
	_expect_equal(
		presentation.get_last_world_revision(),
		confirmed_revision,
		"non-finite positions do not consume the World revision",
	)
	_expect_equal(
		confirmed_linlan.position,
		confirmed_linlan_position,
		"non-finite positions preserve the confirmed resident node",
	)
	world.states = confirmed_states.duplicate(true)
	world.revision = confirmed_revision
	world.states[0]["position"] = confirmed_linlan_position + Vector2(96.0, 0.0)
	world.states[0]["movementRevision"] = (
		int(world.states[0].get("movementRevision", 1)) + 1
	)
	world.states[1]["appearance"] = "invalid-presentation-appearance"
	world.states[1]["movementRevision"] = (
		int(world.states[1].get("movementRevision", 1)) + 1
	)
	world.revision += 1
	var invalid_appearance_sync: Dictionary = presentation.sync_from_world(true)
	_expect_equal(
		invalid_appearance_sync.get("code"),
		"PRESENTATION_WORLD_SNAPSHOT_APPLY_FAILED",
		"a later invalid appearance rejects the complete presentation batch",
	)
	_expect_equal(
		presentation.get_last_world_revision(),
		confirmed_revision,
		"an invalid appearance does not consume the World revision",
	)
	_expect_equal(
		confirmed_linlan.position,
		confirmed_linlan_position,
		"appearance preflight prevents an earlier resident from being partially applied",
	)
	world.states = confirmed_states.duplicate(true)
	world.revision = confirmed_revision
	world.states[0]["position"] = confirmed_linlan_position + Vector2(100.0, 100.0)
	world.states[1]["spaceId"] = "invalid_contract_space"
	world.contract_distance_by_space["invalid_contract_space"] = INF
	world.revision += 1
	var invalid_contract_sync: Dictionary = presentation.sync_from_world(true)
	_expect_equal(
		invalid_contract_sync.get("code"),
		"PRESENTATION_WORLD_SNAPSHOT_INCOMPLETE",
		"an invalid later movement contract rejects the full synchronization",
	)
	_expect_equal(
		presentation.get_last_world_revision(),
		confirmed_revision,
		"an invalid later contract does not consume the World revision",
	)
	_expect_equal(
		confirmed_linlan.position,
		confirmed_linlan_position,
		"preflight prevents an earlier resident from being partially applied",
	)
	world.contract_distance_by_space.erase("invalid_contract_space")
	world.states = confirmed_states.duplicate(true)
	world.revision = confirmed_revision
	world.states[1]["spaceId"] = "missing_contract_space"
	world.missing_contract_spaces["missing_contract_space"] = true
	world.revision += 1
	var missing_contract_sync: Dictionary = presentation.sync_from_world(true)
	_expect_equal(
		missing_contract_sync.get("code"),
		"PRESENTATION_WORLD_SNAPSHOT_INCOMPLETE",
		"a missing later movement contract rejects the full synchronization",
	)
	_expect_equal(
		presentation.get_last_world_revision(),
		confirmed_revision,
		"a missing later contract does not consume the World revision",
	)
	_expect_equal(
		presentation.get_resident_ids(),
		confirmed_ids,
		"a missing later contract preserves the confirmed registry",
	)
	_expect_equal(
		confirmed_linlan.position,
		confirmed_linlan_position,
		"a missing later contract preserves every confirmed resident node",
	)
	world.missing_contract_spaces.erase("missing_contract_space")
	world.states = confirmed_states.duplicate(true)
	world.revision = confirmed_revision
	world.movement_overrides_by_id["resident-linlan"] = {
		"worldRevision": confirmed_revision - 1,
		"movementRevision": 0,
	}
	world.revision += 1
	var stale_movement_sync: Dictionary = presentation.sync_from_world(true)
	_expect_equal(
		stale_movement_sync.get("code"),
		"PRESENTATION_WORLD_SNAPSHOT_INCOMPLETE",
		"a stale resident movement snapshot rejects the full synchronization",
	)
	_expect_equal(
		presentation.get_last_world_revision(),
		confirmed_revision,
		"a stale movement snapshot cannot confirm a newer World revision",
	)
	_expect_equal(
		confirmed_linlan.position,
		confirmed_linlan_position,
		"a stale movement snapshot preserves the confirmed resident node",
	)
	world.movement_overrides_by_id.erase("resident-linlan")
	world.revision = confirmed_revision
	world.missing_movement_ids["resident-linlan"] = true
	world.revision += 1
	var missing_movement_sync: Dictionary = presentation.sync_from_world(true)
	_expect_equal(
		missing_movement_sync.get("code"),
		"PRESENTATION_WORLD_SNAPSHOT_INCOMPLETE",
		"a missing movement snapshot rejects the full synchronization",
	)
	_expect_equal(
		presentation.get_last_world_revision(),
		confirmed_revision,
		"a rejected movement snapshot does not consume the World revision",
	)
	_expect_equal(
		presentation.get_resident_ids(),
		confirmed_ids,
		"a rejected movement snapshot preserves the confirmed registry",
	)
	_expect(
		presentation.get_body("resident-linlan") == confirmed_linlan,
		"a rejected movement snapshot preserves the confirmed resident body",
	)
	_expect(
		_has_diagnostic(
			presentation.take_presentation_diagnostics(),
			"PRESENTATION_MOVEMENT_SNAPSHOT_MISSING",
		),
		"a rejected movement snapshot records the exact diagnostic",
	)
	world.missing_movement_ids.erase("resident-linlan")
	world.revision = confirmed_revision
	world.identities.append({
		"residentId": "resident-without-state",
		"residentName": "缺少状态",
	})
	world.revision += 1
	var missing_state_sync: Dictionary = presentation.sync_from_world(true)
	_expect_equal(
		missing_state_sync.get("code"),
		"PRESENTATION_WORLD_SNAPSHOT_INCOMPLETE",
		"a missing resident state rejects the full synchronization",
	)
	_expect_equal(
		presentation.get_last_world_revision(),
		confirmed_revision,
		"a rejected resident state does not consume the World revision",
	)
	_expect_equal(
		presentation.get_resident_ids(),
		confirmed_ids,
		"a rejected resident state preserves the confirmed registry",
	)
	_expect(
		presentation.get_body("resident-linlan") == confirmed_linlan,
		"a rejected resident state preserves existing resident bodies",
	)
	world.identities.pop_back()
	world.revision = confirmed_revision
	var missing_contract_root := Node2D.new()
	missing_contract_root.y_sort_enabled = true
	root.add_child(missing_contract_root)
	var missing_contract_world := FakeWorld.new()
	missing_contract_world.missing_contract_spaces["town_outdoor"] = true
	var missing_contract_presentation = RESIDENT_PRESENTATION.new()
	root.add_child(missing_contract_presentation)
	var missing_contract_bind: Dictionary = (
		missing_contract_presentation.bind_world(
			missing_contract_world,
			missing_contract_root,
		)
	)
	_expect_equal(
		missing_contract_bind.get("ok"),
		false,
		"initial binding rejects a missing required movement contract",
	)
	_expect_equal(
		missing_contract_presentation.get_last_world_revision(),
		-1,
		"missing initial contracts do not consume the World revision",
	)
	_expect_equal(
		missing_contract_presentation.get_resident_ids(),
		[],
		"missing initial contracts create no resident bodies",
	)
	missing_contract_presentation.queue_free()
	missing_contract_root.queue_free()
	presentation.unbind_world()
	presentation.queue_free()
	actor_root.queue_free()
	_completed_sections["presentation_registry_and_spaces"] = true



func _has_diagnostic(diagnostics: Array[Dictionary], code: String) -> bool:
	for diagnostic in diagnostics:
		if String(diagnostic.get("code", "")) == code:
			return true
	return false



func _scenario_resident_outdoor_collision_route() -> void:
	_validate_touching_clearance_is_blocked()
	_validate_formal_route_clearance()
	await _validate_bent_sample_follow()
	await _validate_rolling_sample_merge()
	await _validate_short_waypoint_does_not_probe_past_corner()
	await _validate_shared_spawn_separates_from_player()
	await _validate_blocked_hold_and_pause()
	await _validate_unreachable_target_does_not_orbit()
	await _validate_blocked_authority_resync()
	await _validate_blocked_portal_handoff_recovery()
	return
func _validate_touching_clearance_is_blocked() -> void:
	var records := CLEARANCE.collision_records([
		{
			"id": "touching-clearance-fixture",
			"enabled": true,
			"collisionLayer": 1,
			"shape": {
				"type": "polygon",
				"points": [
					{"x": 0.0, "y": 0.0},
					{"x": 10.0, "y": 0.0},
					{"x": 10.0, "y": 10.0},
					{"x": 0.0, "y": 10.0},
				],
			},
		},
	])
	_expect(
		not CLEARANCE.body_origin_is_safe(Vector2(28.0, 17.0), records),
		"feet touching a collision boundary are blocked like Godot physics",
	)
	_expect(
		not CLEARANCE.body_segment_is_safe(
			Vector2(28.0, 7.0),
			Vector2(28.0, 27.0),
			records,
		),
		"a route tangent to collision is blocked like Godot physics",
	)



func _validate_formal_route_clearance() -> void:
	var world_data := _read_json_object(WORLD_DATA_PATH)
	var collision_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(COLLISION_PATH)
	)
	var collision_records: Array[Dictionary] = []
	if collision_value is Array:
		collision_records = CLEARANCE.collision_records(
			collision_value as Array,
		)
	_expect(not world_data.is_empty(), "formal Town World data is readable")
	_expect(
		not collision_records.is_empty(),
		"formal outdoor collision is readable",
	)
	var checked_segments := 0
	var harbor_segments := 0
	for edge_value: Variant in (
		(world_data.get("movementNetwork", {}) as Dictionary).get(
			"edges",
			[],
		) as Array
	):
		var edge := edge_value as Dictionary
		var edge_id := String(edge.get("id", ""))
		var points: Array[Vector2] = []
		for point_value: Variant in edge.get("polyline", []) as Array:
			var point := point_value as Dictionary
			points.append(
				Vector2(
					float(point.get("x", 0.0)),
					float(point.get("y", 0.0)),
				)
			)
		for index in range(1, points.size()):
			checked_segments += 1
			if edge_id.contains("harbor"):
				harbor_segments += 1
			_expect(
				CLEARANCE.body_segment_is_safe(
					points[index - 1],
					points[index],
					collision_records,
				),
				"%s segment %d clears the resident feet collision"
				% [edge_id, index - 1],
			)
	_expect(checked_segments > 0, "formal outdoor routes contain segments")
	_expect(
		harbor_segments > 0,
		"the dock route is included in collision validation",
	)



func _validate_short_waypoint_does_not_probe_past_corner() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	_add_blocking_wall(
		stage,
		Vector2(50.0, -12.0),
		Vector2(8.0, 80.0),
	)
	var body = RESIDENT_BODY.new()
	stage.add_child(body)
	body.set_automatic_motion(false)
	body.configure(
		{
			"residentId": "resident-short-waypoint-test",
			"residentName": "近转弯点测试居民",
		},
		{
			"residentId": "resident-short-waypoint-test",
			"name": "近转弯点测试居民",
			"appearance": "",
			"position": Vector2.ZERO,
			"spaceId": "town_outdoor",
			"regionId": "outdoor_road_01",
			"currentPlace": "小镇道路",
			"doing": "",
			"body": {},
			"currentAction": null,
			"actionPhase": {"phase": "idle"},
			"movementRevision": 1,
		},
	)
	body.configure_motion(720.0, 64.0)
	body.apply_authoritative_state(
		{
			"residentId": "resident-short-waypoint-test",
			"name": "近转弯点测试居民",
			"appearance": "",
			"position": Vector2(12.0, 0.0),
			"spaceId": "town_outdoor",
			"regionId": "outdoor_road_01",
			"currentPlace": "小镇道路",
			"doing": "沿安全短路段移动",
			"body": {},
			"currentAction": {"type": "去"},
			"actionPhase": {"phase": "executing"},
			"movementRevision": 2,
			"isMoving": true,
			"target": {
				"spaceId": "town_outdoor",
				"position": Vector2(12.0, 0.0),
			},
			"presentationPath": [Vector2(12.0, 0.0)],
		},
		2,
	)
	await physics_frame
	body.advance_presentation(1.0 / 60.0)
	_expect(
		body.position.distance_to(Vector2(12.0, 0.0)) < 0.1,
		"a wall beyond a nearby bend does not block the safe segment into it",
	)
	_expect_equal(
		body.get_presentation_snapshot().get("localAvoidanceSteerCount"),
		0,
		"the short safe segment does not trigger false local avoidance",
	)
	stage.queue_free()
	await process_frame



func _validate_shared_spawn_separates_from_player() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	var player := _add_blocking_wall(
		stage,
		Vector2(0.0, -12.0),
		Vector2(28.0, 28.0),
	)
	player.name = "Player"
	player.collision_layer = 2
	var body = RESIDENT_BODY.new()
	stage.add_child(body)
	body.set_automatic_motion(false)
	body.configure(
		{
			"residentId": "resident-shared-spawn-test",
			"residentName": "共享入口测试居民",
		},
		{
			"residentId": "resident-shared-spawn-test",
			"name": "共享入口测试居民",
			"appearance": "",
			"position": Vector2.ZERO,
			"spaceId": "town_outdoor",
			"regionId": "outdoor_road_01",
			"currentPlace": "南入口",
			"doing": "",
			"body": {},
			"currentAction": null,
			"actionPhase": {"phase": "idle"},
			"movementRevision": 1,
		},
	)
	body.configure_motion(240.0, 64.0)
	body.apply_authoritative_state(
		{
			"residentId": "resident-shared-spawn-test",
			"name": "共享入口测试居民",
			"appearance": "",
			"position": Vector2(120.0, 0.0),
			"spaceId": "town_outdoor",
			"regionId": "outdoor_road_01",
			"currentPlace": "小镇道路",
			"doing": "离开共享入口",
			"body": {},
			"currentAction": {"type": "去"},
			"actionPhase": {"phase": "executing"},
			"movementRevision": 2,
			"isMoving": true,
			"target": {
				"spaceId": "town_outdoor",
				"position": Vector2(120.0, 0.0),
			},
			"presentationPath": [Vector2(120.0, 0.0)],
		},
		2,
	)
	await physics_frame
	for _frame in 20:
		body.advance_presentation(1.0 / 60.0)
	_expect(
		body.position.x > 60.0,
		"a resident separates from the player at their shared formal spawn",
	)
	_expect_equal(
		body.get_presentation_snapshot().get("movementBlockedHold"),
		false,
		"shared-spawn separation does not enter a blocked hold",
	)
	stage.queue_free()
	await process_frame



func _validate_bent_sample_follow() -> void:
	var body = RESIDENT_BODY.new()
	root.add_child(body)
	body.set_automatic_motion(false)
	var configured := body.configure(
		{
			"residentId": "resident-outdoor-route-test",
			"residentName": "室外路线测试居民",
		},
		{
			"residentId": "resident-outdoor-route-test",
			"name": "室外路线测试居民",
			"appearance": "",
			"position": Vector2.ZERO,
			"spaceId": "town_outdoor",
			"regionId": "outdoor_road_01",
			"currentPlace": "小镇道路",
			"doing": "",
			"body": {},
			"currentAction": null,
			"actionPhase": {"phase": "idle"},
			"movementRevision": 1,
		},
	) as Dictionary
	_expect_equal(
		configured.get("ok"),
		true,
		"resident body accepts the formal movement state",
	)
	if configured.get("ok") != true:
		body.queue_free()
		return
	body.configure_motion(420.0, 64.0)
	var route_state := {
		"residentId": "resident-outdoor-route-test",
		"name": "室外路线测试居民",
		"appearance": "",
		"position": Vector2(120.0, 120.0),
		"spaceId": "town_outdoor",
		"regionId": "outdoor_road_01",
		"currentPlace": "小镇道路",
		"doing": "沿正式路线移动",
		"body": {},
		"currentAction": {"type": "去"},
		"actionPhase": {"phase": "executing"},
		"movementRevision": 2,
		"isMoving": true,
		"target": {
			"spaceId": "town_outdoor",
			"position": Vector2(120.0, 120.0),
		},
		"presentationPath": [
			Vector2.ZERO,
			Vector2(0.0, 120.0),
			Vector2(120.0, 120.0),
		],
	}
	var applied := body.apply_authoritative_state(
		route_state,
		2,
		null,
		false,
		1.0,
	) as Dictionary
	_expect_equal(
		applied.get("status"),
		"following",
		"resident presentation accepts a confirmed bent sample",
	)
	var previous: Vector2 = body.position
	for frame in 17:
		await physics_frame
		body.advance_presentation(1.0 / 60.0)
		var travelled: float = previous.distance_to(body.position)
		_expect(
			travelled > 0.9 and travelled < 7.1,
			"bent route frame %d advances evenly" % frame,
		)
		_expect(
			absf(body.position.x) < 0.1,
			"resident does not overshoot or oscillate across the first corner",
		)
		previous = body.position
	_expect(
		absf(body.position.x) < 0.1
		and body.position.y > 118.0,
		"resident follows the authored first segment before turning",
	)
	var completed_state := route_state.duplicate(true)
	completed_state["currentAction"] = null
	completed_state["isMoving"] = false
	completed_state["presentationPath"] = []
	completed_state["movementRevision"] = 3
	body.apply_authoritative_state(
		completed_state,
		3,
		null,
		false,
		0.5,
	)
	for frame in 9:
		await physics_frame
		body.advance_presentation(1.0 / 60.0)
		var travelled: float = previous.distance_to(body.position)
		_expect(
				travelled > 0.9 and travelled < 14.1,
				"completed route frame %d respects its half-second follow duration" % frame,
		)
		_expect(
			absf(body.position.y - 120.0) < 0.1,
			"final confirmed bend does not collapse into a direct chord",
		)
		previous = body.position
	_expect(
		body.position.distance_to(Vector2(120.0, 120.0)) < 0.1,
		"resident reaches the confirmed sample endpoint",
	)
	for diagnostic: Dictionary in body.take_presentation_diagnostics():
		_expect(
			String(diagnostic.get("code", ""))
			!= "PRESENTATION_LOCAL_AVOIDANCE_BLOCKED",
			"a collision-safe bend does not enter a blocked oscillation",
		)
	body.queue_free()
	await process_frame



func _validate_rolling_sample_merge() -> void:
	var body = RESIDENT_BODY.new()
	root.add_child(body)
	body.set_automatic_motion(false)
	body.configure(
		{
			"residentId": "resident-rolling-route-test",
			"residentName": "连续路段测试居民",
		},
		{
			"residentId": "resident-rolling-route-test",
			"name": "连续路段测试居民",
			"appearance": "",
			"position": Vector2.ZERO,
			"spaceId": "town_outdoor",
			"regionId": "outdoor_road_01",
			"currentPlace": "小镇道路",
			"doing": "",
			"body": {},
			"currentAction": null,
			"actionPhase": {"phase": "idle"},
			"movementRevision": 1,
		},
	)
	body.configure_motion(120.0, 64.0)
	var first_state := {
		"residentId": "resident-rolling-route-test",
		"name": "连续路段测试居民",
		"appearance": "",
		"position": Vector2(0.0, 120.0),
		"spaceId": "town_outdoor",
		"regionId": "outdoor_road_01",
		"currentPlace": "小镇道路",
		"doing": "正在赶路",
		"body": {},
		"currentAction": {"type": "去", "action_id": "rolling-route"},
		"actionPhase": {"phase": "executing"},
		"movementRevision": 2,
		"isMoving": true,
		"target": {
			"spaceId": "town_outdoor",
			"position": Vector2(0.0, 120.0),
		},
		"presentationPath": [Vector2.ZERO, Vector2(0.0, 120.0)],
	}
	body.apply_authoritative_state(first_state, 2, null, false, 1.0)
	for _frame in 30:
		body.advance_presentation(1.0 / 60.0)
	var halfway: Vector2 = body.position
	_expect(
		absf(halfway.x) < 0.1 and halfway.y > 59.0 and halfway.y < 61.0,
		"the first sample advances continuously before the next World sample",
	)
	body.apply_authoritative_state(first_state, 3, null, false, 1.0)
	body.advance_presentation(1.0 / 60.0)
	_expect(
		absf(body.position.x) < 0.1 and body.position.y > halfway.y,
		"repeating one movement revision keeps local progress instead of restarting",
	)
	var second_state := first_state.duplicate(true)
	second_state["position"] = Vector2(120.0, 120.0)
	second_state["movementRevision"] = 3
	second_state["target"] = {
		"spaceId": "town_outdoor",
		"position": Vector2(120.0, 120.0),
	}
	second_state["presentationPath"] = [
		Vector2(0.0, 120.0),
		Vector2(120.0, 120.0),
	]
	body.apply_authoritative_state(second_state, 4, null, false, 1.0)
	for _frame in 29:
		body.advance_presentation(1.0 / 60.0)
	_expect(
		absf(body.position.x) < 0.1
		and body.position.y > 118.0,
		"a newer sample retains the unplayed corner instead of cutting a chord",
	)
	for _frame in 60:
		body.advance_presentation(1.0 / 60.0)
	_expect(
		body.position.distance_to(Vector2(120.0, 120.0)) < 0.1,
		"merged samples finish at the latest authoritative position",
	)
	body.queue_free()
	await process_frame



func _validate_blocked_hold_and_pause() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	var right_wall := _add_blocking_wall(
		stage,
		Vector2(24.0, -12.0),
		Vector2(8.0, 80.0),
	)
	_add_blocking_wall(stage, Vector2(-24.0, -12.0), Vector2(8.0, 80.0))
	_add_blocking_wall(stage, Vector2(0.0, 12.0), Vector2(80.0, 8.0))
	_add_blocking_wall(stage, Vector2(0.0, -36.0), Vector2(80.0, 8.0))
	var body = RESIDENT_BODY.new()
	stage.add_child(body)
	body.set_automatic_motion(false)
	body.configure(
		{
			"residentId": "resident-blocked-hold-test",
			"residentName": "受阻稳定测试居民",
		},
		{
			"residentId": "resident-blocked-hold-test",
			"name": "受阻稳定测试居民",
			"appearance": "",
			"position": Vector2.ZERO,
			"spaceId": "town_outdoor",
			"regionId": "outdoor_road_01",
			"currentPlace": "码头",
			"doing": "",
			"body": {},
			"currentAction": null,
			"actionPhase": {"phase": "idle"},
			"movementRevision": 1,
		},
	)
	body.configure_motion(120.0, 64.0)
	var target_state := {
		"residentId": "resident-blocked-hold-test",
		"name": "受阻稳定测试居民",
		"appearance": "",
		"position": Vector2(300.0, 0.0),
		"spaceId": "town_outdoor",
		"regionId": "outdoor_road_01",
		"currentPlace": "码头",
		"doing": "前往码头",
		"body": {},
		"currentAction": {"type": "去"},
		"actionPhase": {"phase": "executing"},
		"movementRevision": 2,
		"isMoving": true,
		"target": {
			"spaceId": "town_outdoor",
			"position": Vector2(300.0, 0.0),
		},
		"presentationPath": [Vector2(300.0, 0.0)],
	}
	body.apply_authoritative_state(target_state, 2)
	await physics_frame
	var authority_revision := 2
	var direction_changes := 0
	var last_direction := String(
		(
			body.get_presentation_snapshot().get("visual", {}) as Dictionary
		).get("activeDirection", "")
	)
	for frame in 90:
		if frame > 0 and frame % 20 == 0:
			authority_revision += 1
			var next_sample_x := (
				float((target_state["position"] as Vector2).x) + 20.0
			)
			target_state["position"] = Vector2(next_sample_x, 0.0)
			target_state["movementRevision"] = authority_revision
			target_state["target"] = {
				"spaceId": "town_outdoor",
				"position": Vector2(next_sample_x, 0.0),
			}
			target_state["presentationPath"] = [
				Vector2(next_sample_x, 0.0),
			]
			body.apply_authoritative_state(
				target_state,
				authority_revision,
			)
		body.advance_presentation(1.0 / 60.0)
		var direction := String(
			(
				body.get_presentation_snapshot().get("visual", {})
				as Dictionary
			).get("activeDirection", "")
		)
		if direction != last_direction:
			direction_changes += 1
			last_direction = direction
	var held_snapshot := body.get_presentation_snapshot()
	_expect_equal(
		held_snapshot.get("movementBlockedHold"),
		true,
		"unreachable presentation enters a stable visual hold",
	)
	_expect(
		body.position.distance_to(Vector2.ZERO) < 3.0,
		"blocked resident remains inside its collision-safe settling area",
	)
	_expect(
		direction_changes <= 2,
		"blocked resident keeps a stable visible direction instead of twitching",
	)
	var steer_count := int(
		held_snapshot.get("localAvoidanceSteerCount", 0)
	)
	body.set_presentation_paused(true)
	for _frame in 30:
		body.advance_presentation(1.0 / 60.0)
	var paused_snapshot := body.get_presentation_snapshot()
	_expect_equal(
		paused_snapshot.get("presentationPaused"),
		true,
		"pause reaches the resident presentation body",
	)
	_expect_equal(
		paused_snapshot.get("localAvoidanceSteerCount"),
		steer_count,
		"pause prevents new avoidance updates",
	)
	body.set_presentation_paused(false)
	var blocked_position: Vector2 = body.position
	right_wall.queue_free()
	await physics_frame
	for _frame in 40:
		body.advance_presentation(1.0 / 60.0)
	var resumed_snapshot := body.get_presentation_snapshot()
	_expect_equal(
		resumed_snapshot.get("movementBlockedHold"),
		false,
		"blocked hold retries after the obstacle clears",
	)
	_expect(
		body.position.distance_to(blocked_position) > 1.0,
		"resident resumes the same authoritative route after clearance",
	)
	var performing_state := target_state.duplicate(true)
	performing_state["position"] = Vector2(80.0, 0.0)
	authority_revision += 1
	performing_state["movementRevision"] = authority_revision
	performing_state["isMoving"] = false
	performing_state["currentAction"] = {"type": "做活动"}
	performing_state["activityCue"] = {
		"actionType": "用道具",
		"phase": "performing",
		"actorFacing": "left",
		"verb": "整理渔具",
	}
	performing_state["presentationPath"] = []
	body.apply_authoritative_state(
		performing_state,
		authority_revision,
	)
	var performing_snapshot := body.get_presentation_snapshot()
	var performing_visual := (
		performing_snapshot.get("visual", {}) as Dictionary
	)
	_expect_equal(
		performing_snapshot.get("interactionSettled"),
		true,
		"a blocked resident settles before performing an in-place activity",
	)
	_expect_equal(
		performing_visual.get("activityType"),
		"用道具",
		"agent activity uses the in-place prop animation",
	)
	_expect_equal(
		performing_visual.get("activeDirection"),
		"left",
		"performing activity keeps its authored facing",
	)
	target_state["position"] = Vector2(-300.0, 0.0)
	authority_revision += 1
	target_state["movementRevision"] = authority_revision
	target_state["target"] = {
		"spaceId": "town_outdoor",
		"position": Vector2(-300.0, 0.0),
	}
	target_state["presentationPath"] = [Vector2(-300.0, 0.0)]
	body.apply_authoritative_state(target_state, authority_revision)
	_expect_equal(
		body.get_presentation_snapshot().get("hasNavigationTarget"),
		true,
		"a new authoritative target starts a fresh movement attempt",
	)
	stage.queue_free()
	await process_frame



func _validate_blocked_authority_resync() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	_add_blocking_wall(stage, Vector2(24.0, -12.0), Vector2(8.0, 80.0))
	_add_blocking_wall(stage, Vector2(-24.0, -12.0), Vector2(8.0, 80.0))
	_add_blocking_wall(stage, Vector2(0.0, 12.0), Vector2(80.0, 8.0))
	_add_blocking_wall(stage, Vector2(0.0, -36.0), Vector2(80.0, 8.0))
	var body = RESIDENT_BODY.new()
	stage.add_child(body)
	body.set_automatic_motion(false)
	body.configure(
		{
			"residentId": "resident-blocked-resync-test",
			"residentName": "受阻对齐测试居民",
		},
		{
			"residentId": "resident-blocked-resync-test",
			"residentName": "受阻对齐测试居民",
			"name": "受阻对齐测试居民",
			"appearance": "",
			"position": Vector2.ZERO,
			"spaceId": "town_outdoor",
			"regionId": "outdoor_road_01",
			"currentPlace": "小镇道路",
			"doing": "",
			"body": {},
			"currentAction": null,
			"actionPhase": {"phase": "idle"},
			"movementRevision": 1,
		},
	)
	body.configure_motion(120.0, 64.0)
	var authority_position := Vector2(300.0, 0.0)
	var target_state := {
		"residentId": "resident-blocked-resync-test",
		"name": "受阻对齐测试居民",
		"appearance": "",
		"position": authority_position,
		"spaceId": "town_outdoor",
		"regionId": "outdoor_road_01",
		"currentPlace": "小镇道路",
		"doing": "正在赶路",
		"body": {},
		"currentAction": {"type": "去", "action_id": "blocked-resync"},
		"actionPhase": {"phase": "executing"},
		"movementRevision": 2,
		"isMoving": true,
		"target": {
			"spaceId": "town_outdoor",
			"position": authority_position,
		},
		"presentationPath": [Vector2.ZERO, authority_position],
	}
	body.apply_authoritative_state(target_state, 2, null, false, 1.0)
	for _frame in 300:
		body.advance_presentation(1.0 / 60.0)
	var snapshot := body.get_presentation_snapshot()
	_expect_equal(
		snapshot.get("movementBlockedHold"),
		false,
		"a permanently blocked presentation eventually leaves its visual hold",
	)
	_expect(
		body.position.distance_to(authority_position) < 0.1,
		"blocked presentation realigns to the latest authoritative position",
	)
	var found_resync := false
	for diagnostic: Dictionary in body.take_presentation_diagnostics():
		if String(diagnostic.get("code", "")) == (
			"PRESENTATION_BLOCKED_AUTHORITY_RESYNC"
		):
			found_resync = true
	_expect(found_resync, "blocked authority realignment emits one diagnostic")
	stage.queue_free()
	await process_frame



func _validate_blocked_portal_handoff_recovery() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	_add_blocking_wall(stage, Vector2(24.0, -12.0), Vector2(8.0, 80.0))
	_add_blocking_wall(stage, Vector2(-24.0, -12.0), Vector2(8.0, 80.0))
	_add_blocking_wall(stage, Vector2(0.0, 12.0), Vector2(80.0, 8.0))
	_add_blocking_wall(stage, Vector2(0.0, -36.0), Vector2(80.0, 8.0))
	var body = RESIDENT_BODY.new()
	stage.add_child(body)
	body.set_automatic_motion(false)
	body.configure(
		{
			"residentId": "resident-blocked-portal-test",
			"residentName": "入口受阻测试居民",
		},
		{
			"residentId": "resident-blocked-portal-test",
			"name": "入口受阻测试居民",
			"appearance": "",
			"position": Vector2.ZERO,
			"spaceId": "town_outdoor",
			"regionId": "outdoor_road_01",
			"currentPlace": "小镇道路",
			"doing": "",
			"body": {},
			"currentAction": null,
			"actionPhase": {"phase": "idle"},
			"movementRevision": 1,
		},
	)
	body.configure_motion(120.0, 64.0)
	var outdoor_portal := Vector2(120.0, 0.0)
	body.apply_authoritative_state({
		"residentId": "resident-blocked-portal-test",
		"name": "入口受阻测试居民",
		"appearance": "",
		"position": outdoor_portal,
		"spaceId": "town_outdoor",
		"regionId": "outdoor_road_01",
		"currentPlace": "小镇道路",
		"doing": "正在进门",
		"body": {},
		"currentAction": {"type": "去", "action_id": "portal-cross"},
		"actionPhase": {"phase": "executing"},
		"movementRevision": 2,
		"isMoving": true,
		"routeCrossesPortal": true,
		"target": {
			"spaceId": "town_outdoor",
			"position": outdoor_portal,
		},
		"presentationPath": [Vector2.ZERO, outdoor_portal],
	}, 2, null, false, 1.0)
	var indoor_position := Vector2(400.0, 520.0)
	var deferred := body.apply_authoritative_state({
		"residentId": "resident-blocked-portal-test",
		"name": "入口受阻测试居民",
		"appearance": "",
		"position": indoor_position,
		"spaceId": "indoor_portal_test",
		"regionId": "region_portal_test",
		"currentPlace": "入口测试室内",
		"doing": "正在进门",
		"body": {},
		"currentAction": {"type": "去", "action_id": "portal-cross"},
		"actionPhase": {"phase": "executing"},
		"movementRevision": 3,
		"isMoving": true,
		"routeCrossesPortal": true,
		"target": {
			"spaceId": "indoor_portal_test",
			"position": indoor_position,
		},
		"presentationPath": [],
	}, 3, null, false, 1.0) as Dictionary
	_expect_equal(
		deferred.get("status"),
		"space_transition_deferred",
		"World 先进入室内时表现层保留入口交接",
	)
	for _frame in 300:
		body.advance_presentation(1.0 / 60.0)
	var snapshot := body.get_presentation_snapshot()
	_expect_equal(
		snapshot.get("spaceId"),
		"indoor_portal_test",
		"入口受阻恢复后完成待处理空间切换",
	)
	_expect(
		body.position.distance_to(indoor_position) < 0.1,
		"室内权威坐标不会被写进室外场景后再消失",
	)
	_expect_equal(
		snapshot.get("pendingSpaceTransition"),
		false,
		"入口受阻恢复不会遗留待处理切换",
	)
	var found_recovery := false
	for diagnostic: Dictionary in body.take_presentation_diagnostics():
		if String(diagnostic.get("code", "")) == (
			"PRESENTATION_BLOCKED_PORTAL_HANDOFF_RECOVERED"
		):
			found_recovery = true
	_expect(found_recovery, "入口受阻恢复留下明确诊断")
	stage.queue_free()
	await process_frame



func _validate_unreachable_target_does_not_orbit() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	_add_blocking_wall(stage, Vector2(120.0, -12.0), Vector2(88.0, 88.0))
	var body = RESIDENT_BODY.new()
	stage.add_child(body)
	body.set_automatic_motion(false)
	body.configure(
		{
			"residentId": "resident-unreachable-target-test",
			"residentName": "不可达目标测试居民",
		},
		{
			"residentId": "resident-unreachable-target-test",
			"name": "不可达目标测试居民",
			"appearance": "",
			"position": Vector2.ZERO,
			"spaceId": "town_outdoor",
			"regionId": "outdoor_road_01",
			"currentPlace": "小镇道路",
			"doing": "",
			"body": {},
			"currentAction": null,
			"actionPhase": {"phase": "idle"},
			"movementRevision": 1,
		},
	)
	body.configure_motion(120.0, 64.0)
	var authority_position := Vector2(120.0, 0.0)
	var target_state := {
		"residentId": "resident-unreachable-target-test",
		"name": "不可达目标测试居民",
		"appearance": "",
		"position": authority_position,
		"spaceId": "town_outdoor",
		"regionId": "outdoor_road_01",
		"currentPlace": "小镇道路",
		"doing": "正在赶路",
		"body": {},
		"currentAction": {"type": "去", "action_id": "unreachable-target"},
		"actionPhase": {"phase": "executing"},
		"movementRevision": 2,
		"isMoving": true,
		"target": {
			"spaceId": "town_outdoor",
			"position": authority_position,
		},
		"presentationPath": [Vector2.ZERO, authority_position],
	}
	body.apply_authoritative_state(target_state, 2, null, false, 1.0)
	for _frame in 150:
		body.advance_presentation(1.0 / 60.0)
	var held_snapshot := body.get_presentation_snapshot()
	_expect_equal(
		held_snapshot.get("movementBlockedHold"),
		true,
		"an unreachable waypoint stops in a stable hold instead of orbiting it",
	)
	var held_position: Vector2 = body.position
	for _frame in 30:
		body.advance_presentation(1.0 / 60.0)
	_expect(
		body.position.distance_to(held_position) < 0.1,
		"the unreachable waypoint hold has no repeated turning movement",
	)
	stage.queue_free()
	await process_frame



func _add_blocking_wall(
	parent: Node,
	wall_position: Vector2,
	wall_size: Vector2,
) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = wall_position
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = wall_size
	collision.shape = shape
	wall.add_child(collision)
	parent.add_child(wall)
	return wall



func _read_json_object(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	return parsed as Dictionary if parsed is Dictionary else {}



func _scenario_player_avatar() -> void:
	_test_observer_avatar_is_absent_until_descent()
	_test_position_place_and_perception()
	_test_descent_relocates_avatar_to_a_valid_outdoor_point()
	_test_player_invitation_requires_reply()
	_test_player_conversation_idle_timeout_only_on_resident_turn()
	_test_player_starts_and_ends_conversation()
	_test_resident_starts_and_player_rejects()
	_test_player_leaving_ends_conversation()
	_test_configured_avatar_id_is_authoritative()
	return
func _test_observer_avatar_is_absent_until_descent() -> void:
	var world := _new_observer_world(_opening_in_garden())
	var observer_state := world.call("get_player_avatar_state") as Dictionary
	_expect_equal(
		observer_state.get("present"),
		false,
		"observer world starts with the avatar absent",
	)
	var hidden_wake := _take_wake_player_avatar(world, "林岚")
	var hidden_nearby := (
		(hidden_wake.get("snapshot", {}) as Dictionary).get("nearby", []) as Array
	)
	_expect(
		not _nearby_has_name(hidden_nearby, "旅行者"),
		"a resident does not know an avatar that has not descended",
	)
	_expect(
		not _has_event_player_avatar(hidden_wake, "有人走了", "旅行者"),
		"initial observer hiding does not fabricate an avatar departure",
	)
	_expect_equal(
		world.call(
			"submit_agent_decision",
			"林岚",
			_wait_player_avatar(hidden_wake),
		).get("status"),
		"accepted",
		"resident can begin ordinary life without avatar knowledge",
	)
	_expire_confirmed_preview(world)
	var descended := world.call(
		"prepare_player_avatar_descent",
		"town_outdoor",
		Vector2(3368, 2772),
	) as Dictionary
	_expect_equal(descended.get("ok"), true, "descent makes the avatar present")
	var arrival_wake := _take_wake_player_avatar(world, "林岚")
	_expect(
		_has_event_player_avatar(arrival_wake, "有人来了", "旅行者"),
		"resident first learns the avatar from confirmed descent",
	)



func _test_position_place_and_perception() -> void:
	var world := _new_world(_opening_near_clinic())
	var initial := world.call("get_player_avatar_state") as Dictionary
	_expect_equal(initial.get("currentPlace"), "小镇道路", "avatar starts at the configured outdoor place")
	var unclassified := world.call("submit_player_avatar_position", "town_outdoor", Vector2(-1000, -1000), "由正式地图碰撞确认的位置") as Dictionary
	_expect_equal(unclassified.get("ok"), false, "world rejects a position outside every legal region")
	var non_finite := world.call("submit_player_avatar_position", "town_outdoor", Vector2(INF, 0), "非法位置") as Dictionary
	_expect_equal(non_finite.get("ok"), false, "world rejects non-finite avatar coordinates")
	var unclassified_state := world.call("get_player_avatar_state") as Dictionary
	_expect_equal(unclassified_state, initial, "rejected unclassified position preserves the authoritative avatar state")
	var cross_space := world.call("submit_player_avatar_position", "indoor_clinic", Vector2.ZERO, "跳过入口") as Dictionary
	_expect_equal(cross_space.get("ok"), false, "position updates cannot bypass a map-space transition")
	_expect_equal(world.call("get_player_avatar_state"), unclassified_state, "rejected cross-space submission preserves world state")

	var gu_initial := _take_wake_player_avatar(world, "顾川")
	_expect_equal(world.call("submit_agent_decision", "顾川", _wait_player_avatar(gu_initial)).get("status"), "accepted", "resident has a stable current action before avatar entry")
	_expire_confirmed_preview(world)
	var place_changes: Array[Dictionary] = []
	world.connect("player_avatar_place_changed", func(change: Dictionary) -> void:
		place_changes.append(change.duplicate(true))
	)
	var entered := world.call("change_player_avatar_place", "诊所") as Dictionary
	_expect_equal(entered.get("ok"), true, "avatar can enter a directly connected indoor place")
	var inside := world.call("get_player_avatar_state") as Dictionary
	_expect_equal(inside.get("currentPlace"), "诊所", "avatar place changes to the indoor destination")
	_expect_equal(inside.get("spaceId"), "indoor_clinic", "avatar enters the indoor map space")
	_expect((inside.get("nearby", []) as Array).has("顾川"), "avatar perception includes the resident in the same indoor region")
	var gu_entry_wake := _take_wake_player_avatar(world, "顾川")
	_expect(_has_event_player_avatar(gu_entry_wake, "有人来了", "旅行者"), "resident perceives the avatar by its world name")
	_expect(not JSON.stringify(gu_entry_wake).contains("玩家"), "resident wake does not expose the player system identity")
	_expect_equal(place_changes.size(), 1, "one confirmed entry emits one avatar place signal")
	_expect_equal(world.call("submit_agent_decision", "顾川", {"decision_id": String(gu_entry_wake.get("decision_id", "")), "handling": "continue_current"}).get("status"), "continued", "resident consumes the entry event while keeping the current action")
	_expire_confirmed_preview(world)
	var rejected_return := world.call(
		"return_player_avatar_outdoors",
		"小镇道路",
		Vector2(-1000, -1000),
	) as Dictionary
	_expect_equal(rejected_return.get("ok"), false, "avatar cannot leave at an unsafe outdoor point")
	_expect_equal((world.call("get_player_avatar_state") as Dictionary).get("currentPlace"), "诊所", "rejected safe return keeps the avatar indoors")

	var moved_inside := world.call(
		"submit_player_avatar_position",
		"indoor_clinic",
		Vector2(400, 64),
		"旅行者走到诊所内侧房间",
	) as Dictionary
	_expect_equal(moved_inside.get("ok"), true, "avatar can move through the full clinic interior beyond the former entrance-only region")
	var deep_inside := world.call("get_player_avatar_state") as Dictionary
	_expect_equal(deep_inside.get("position"), Vector2(400, 64), "world keeps the confirmed indoor local position")
	_expect(not (deep_inside.get("nearby", []) as Array).has("顾川"), "moving far enough inside updates avatar perception")
	var gu_out_of_range := _take_wake_player_avatar(world, "顾川")
	_expect(_has_event_player_avatar(gu_out_of_range, "有人走了", "旅行者"), "resident receives one leaving event when avatar walks out of indoor perception range")
	_expect_equal(world.call("submit_agent_decision", "顾川", {"decision_id": String(gu_out_of_range.get("decision_id", "")), "handling": "continue_current"}).get("status"), "continued", "resident consumes the indoor leaving event")
	_expire_confirmed_preview(world)

	var returned_to_door := world.call(
		"submit_player_avatar_position",
		"indoor_clinic",
		Vector2(16, 752),
		"旅行者走回诊所门口",
	) as Dictionary
	_expect_equal(returned_to_door.get("ok"), true, "avatar can walk back to the authored indoor exit point")
	_expect(((world.call("get_player_avatar_state") as Dictionary).get("nearby", []) as Array).has("顾川"), "returning to the door restores nearby perception")
	var gu_returned := _take_wake_player_avatar(world, "顾川")
	_expect(_has_event_player_avatar(gu_returned, "有人来了", "旅行者"), "resident perceives the avatar returning from deeper inside")
	_expect_equal(world.call("submit_agent_decision", "顾川", {"decision_id": String(gu_returned.get("decision_id", "")), "handling": "continue_current"}).get("status"), "continued", "resident consumes the indoor return event")
	_expire_confirmed_preview(world)
	var collision_authoritative := world.call("submit_player_avatar_position", "indoor_clinic", Vector2(600, 0), "由正式室内碰撞确认的位置") as Dictionary
	_expect_equal(collision_authoritative.get("ok"), false, "world rejects an indoor point outside its authored region")
	_expect_equal((world.call("get_player_avatar_state") as Dictionary).get("position"), Vector2(16, 752), "rejected indoor position preserves the last legal point")

	var exited := world.call(
		"return_player_avatar_outdoors",
		"小镇道路",
		CLINIC_AVATAR_SAFE_RETURN,
	) as Dictionary
	_expect_equal(exited.get("ok"), true, "avatar can leave through the same bidirectional entrance")
	var outdoor_avatar := world.call("get_player_avatar_state") as Dictionary
	_expect_equal(outdoor_avatar.get("currentPlace"), "小镇道路", "avatar returns to the outdoor place")
	_expect_equal(outdoor_avatar.get("position"), CLINIC_AVATAR_SAFE_RETURN, "avatar returns to its safe point away from the shared door endpoint")
	var gu_exit_wake := _take_wake_player_avatar(world, "顾川")
	_expect(_has_event_player_avatar(gu_exit_wake, "有人走了", "旅行者"), "resident receives one avatar-leaving event")
	_expect_equal(place_changes.size(), 2, "exit emits a second confirmed avatar place signal")



func _test_descent_relocates_avatar_to_a_valid_outdoor_point() -> void:
	var world := _new_world(_opening_near_clinic())
	var entered := world.call("change_player_avatar_place", "诊所") as Dictionary
	_expect_equal(entered.get("ok"), true, "descent relocation test starts from a real interior")
	var relocated := world.call(
		"prepare_player_avatar_descent",
		"town_outdoor",
		Vector2(3250, 2050),
	) as Dictionary
	_expect_equal(relocated.get("ok"), true, "avatar descent can relocate from an interior to the authored plaza point")
	var avatar := world.call("get_player_avatar_state") as Dictionary
	_expect_equal(avatar.get("spaceId"), "town_outdoor", "descent relocation always returns to the outdoor map")
	_expect_equal(avatar.get("currentPlace"), "中心广场", "descent relocation derives the formal plaza membership")
	_expect_equal(avatar.get("position"), Vector2(3250, 2050), "descent relocation keeps the fixed safe point")
	var nearest_outdoor := world.call(
		"prepare_player_avatar_descent",
		"town_outdoor",
		Vector2(2968, 1222),
	) as Dictionary
	_expect_equal(
		nearest_outdoor.get("ok"),
		true,
		"an unsafe outdoor view center resolves to the nearest safe point",
	)
	var outdoor_avatar := world.call(
		"get_player_avatar_state",
	) as Dictionary
	_expect(
		Array(
			MOVEMENT.validate_position_state(
				_source_data(),
				outdoor_avatar,
			),
		).is_empty(),
		"resolved outdoor descent remains a legal World position",
	)
	_expect_equal(
		(
			nearest_outdoor.get("landing", {}) as Dictionary
		).get("adjusted"),
		true,
		"unsafe outdoor center reports that it was adjusted",
	)
	var nearest_indoor := world.call(
		"prepare_player_avatar_descent",
		"indoor_clinic",
		Vector2(600, 0),
	) as Dictionary
	_expect_equal(
		nearest_indoor.get("ok"),
		true,
		"an unsafe indoor view center resolves inside the same room",
	)
	var indoor_avatar := world.call(
		"get_player_avatar_state",
	) as Dictionary
	_expect_equal(
		indoor_avatar.get("spaceId"),
		"indoor_clinic",
		"indoor descent does not force the avatar outdoors",
	)
	_expect(
		Array(
			MOVEMENT.validate_position_state(
				_source_data(),
				indoor_avatar,
			),
		).is_empty(),
		"resolved indoor descent remains a legal World position",
	)



func _test_player_starts_and_ends_conversation() -> void:
	var opening := _opening_in_garden()
	var world := _new_world(opening)
	var lin_initial := _take_wake_player_avatar(world, "林岚")
	_expect_equal(
		world.call(
			"submit_agent_decision",
			"林岚",
			_wait_player_avatar(lin_initial),
		).get("status"),
		"accepted",
		"resident starts an ordinary action before the player interrupts",
	)
	_expire_confirmed_preview(world)
	var action_before: Variant = (
		world.call("get_resident_state", "林岚") as Dictionary
	).get("currentAction")
	var player_results: Array[Dictionary] = []
	world.connect("player_command_result_created", func(result: Dictionary) -> void:
		player_results.append(result.duplicate(true))
	)
	var started := world.call(
		"player_start_conversation",
		"林岚",
		"你见过这只猫吗？",
		"旅行者把照片递给林岚",
		[{"ref": "player-photo-1", "mime_type": "image/jpeg"}],
	) as Dictionary
	_expect_equal(started.get("ok"), true, "player can start a conversation with a nearby resident")
	var conversation := started.get("conversation", {}) as Dictionary
	var conversation_id := String(conversation.get("conversationId", ""))
	_expect_equal(conversation.get("initiator"), "player-avatar", "conversation records the avatar's stable residentId as initiator")
	_expect_equal((conversation.get("turns", []) as Array)[0].get("speaker"), "旅行者", "first confirmed turn uses the avatar's world name")

	var lin_invitation := _take_wake_player_avatar(world, "林岚")
	_expect_equal(AGENT_CONTRACT.validate_wake_packet(lin_invitation), [], "player talk produces a valid unchanged-Agent wake packet")
	_expect(not JSON.stringify(lin_invitation.get("events", [])).contains("residentId"), "Agent events do not leak internal recipient fields")
	_expect(_has_event_player_avatar(lin_invitation, "搭话"), "resident receives the player's talk event")
	var reply := _reply(lin_invitation, conversation_id, "没见过，我可以帮你留意。", "林岚仔细看了看照片", false)
	_expect_equal(AGENT_CONTRACT.validate_decision(reply, world.call("get_agent_initialization", "林岚"), lin_invitation, {}), [], "resident reply to player uses the existing Agent contract")
	_expect_equal(world.call("submit_agent_decision", "林岚", reply).get("status"), "accepted", "world accepts the resident reply to player")
	_expire_confirmed_preview(world)
	_expect_equal((world.call("get_player_avatar_state") as Dictionary).get("conversation", {}).get("with"), "林岚", "avatar state exposes the active world conversation")
	_expect_equal(
		(
			world.call("get_resident_state", "林岚") as Dictionary
		).get("currentAction"),
		{
			"action_id": "player-conversation:%s" % conversation_id,
			"type": "答话",
		},
		"accepting the player presents the active conversation while preserving the ordinary action internally",
	)
	var residents_during_talk := world.get("_residents") as Dictionary
	_expect(
		int(
			(
				residents_during_talk.get(
					"resident_lin_lan_01",
					{},
				) as Dictionary
			).get("actionSuspendedAbsoluteMinute", -1),
		) >= 0,
		"accepting the player marks the ordinary action as suspended",
	)

	var player_reply := world.call(
		"player_reply_conversation",
		conversation_id,
		"谢谢你。",
		"旅行者收起照片",
		[],
		false,
	) as Dictionary
	_expect_equal(player_reply.get("ok"), true, "player can continue when the world is waiting for the avatar")
	var lin_reply_wake := _take_wake_player_avatar(world, "林岚")
	_expect_equal(AGENT_CONTRACT.validate_wake_packet(lin_reply_wake), [], "player reply and resident action result satisfy the unchanged Agent contract")
	_expect(_has_event_player_avatar(lin_reply_wake, "对方答话"), "resident receives the player's confirmed reply")

	var ended := world.call("player_end_conversation", conversation_id, "旅行者挥手告别") as Dictionary
	_expect_equal(ended.get("ok"), true, "player can end the active conversation while waiting for the resident")
	var ended_state := world.call("get_conversation", conversation_id) as Dictionary
	_expect_equal(ended_state.get("status"), "ended", "player end command closes the world conversation")
	_expect_equal(ended_state.get("endReason"), "主动结束", "player end command records the formal end reason")
	_expect_equal((world.call("get_player_avatar_state") as Dictionary).get("conversation"), null, "avatar conversation clears after the confirmed end")
	_expect_equal(
		(
			world.call("get_resident_state", "林岚") as Dictionary
		).get("currentAction"),
		action_before,
		"ending the player conversation restores the same ordinary action",
	)
	var residents_after_talk := world.get("_residents") as Dictionary
	_expect_equal(
		int(
			(
				residents_after_talk.get(
					"resident_lin_lan_01",
					{},
				) as Dictionary
			).get("actionSuspendedAbsoluteMinute", -1),
		),
		-1,
		"ending the player conversation clears the suspension marker",
	)
	_expect_equal(player_results.size(), 3, "each accepted player conversation command emits one result")
	var save_result := world.call("create_save_snapshot") as Dictionary
	_expect_equal(
		save_result.get("ok"),
		true,
		"a conversation ended while waiting for a resident can be saved",
	)
	var restored_world := _new_world(opening)
	var restored := restored_world.call(
		"restore_from_snapshot",
		BUILDER.build_from_source(SOURCE_DIR),
		opening,
		save_result.get("snapshot", {}) as Dictionary,
	) as Dictionary
	_expect_equal(
		restored.get("ok"),
		true,
		"the saved terminal player action restores instead of invalidating the save: %s"
		% JSON.stringify(restored),
	)
	_expect_equal(
		(restored_world.call("get_conversation", conversation_id) as Dictionary).get(
			"status",
		),
		"ended",
		"restore preserves the ended conversation history",
	)



func _test_player_invitation_requires_reply() -> void:
	var world := _new_world(_opening_in_garden())
	var lin_initial := _take_wake_player_avatar(world, "林岚")
	_expect_equal(
		world.call(
			"submit_agent_decision",
			"林岚",
			_wait_player_avatar(lin_initial),
		).get("status"),
		"accepted",
		"resident starts an action before the player invitation",
	)
	_expire_confirmed_preview(world)
	var action_before: Variant = (
		world.call("get_resident_state", "林岚") as Dictionary
	).get("currentAction")
	var started := world.call(
		"player_start_conversation",
		"林岚",
		"现在能聊吗？",
		"旅行者试着叫住林岚",
		[],
	) as Dictionary
	_expect_equal(started.get("ok"), true, "player invitation reaches the resident")
	var conversation_id := String(
		(started.get("conversation", {}) as Dictionary).get("conversationId", ""),
	)
	_expect(not conversation_id.is_empty(), "player invitation exposes the conversation id")
	var invitation := _take_wake_player_avatar(world, "林岚")
	# 新契约：所有搭话都必须明确答话，不允许 continue_current 静默走过；
	# 拒绝也要在答话里说明理由并结束对话。
	var ignored := world.call(
		"submit_agent_decision",
		"林岚",
		{
			"decision_id": String(invitation.get("decision_id", "")),
			"handling": "continue_current",
		},
	) as Dictionary
	_expect_equal(ignored.get("ok"), false, "silent ignore is rejected")
	_expect_equal(
		String(ignored.get("errorCode", "")),
		"CONVERSATION_REPLY_REQUIRED",
		"silent ignore returns the reply-required error",
	)
	_expect_equal(
		(world.call("get_active_conversations") as Array).size(),
		1,
		"rejected ignore keeps the invitation open",
	)
	var refused := world.call(
		"submit_agent_decision",
		"林岚",
		_reply(invitation, conversation_id,
			"这会儿不方便，抱歉。", "林岚抱歉地摆了摆手", true),
	) as Dictionary
	_expect_equal(refused.get("status"), "accepted", "resident can refuse with a reason")
	var ended := world.call(
		"get_conversation",
		conversation_id,
	) as Dictionary
	_expect_equal(ended.get("status"), "ended", "refusal ends the invitation")
	_expect_equal(ended.get("endReason"), "主动结束", "refusal reply records the formal end reason")
	_expire_confirmed_preview(world)
	_expect_equal(
		(
			world.call("get_resident_state", "林岚") as Dictionary
		).get("currentAction"),
		action_before,
		"the confirmed refusal restores the ordinary action",
	)



func _test_player_conversation_idle_timeout_only_on_resident_turn() -> void:
	var world := _new_world(_opening_in_garden())
	var lin_initial := _take_wake_player_avatar(world, "林岚")
	_expect_equal(
		world.call(
			"submit_agent_decision",
			"林岚",
			_wait_player_avatar(lin_initial),
		).get("status"),
		"accepted",
		"resident starts an action before the timeout coverage",
	)
	_expire_confirmed_preview(world)
	var started := world.call(
		"player_start_conversation",
		"林岚",
		"现在能聊吗？",
		"旅行者试着叫住林岚",
		[],
	) as Dictionary
	_expect_equal(started.get("ok"), true, "player invitation reaches the resident")
	var conversation_id := String(
		(started.get("conversation", {}) as Dictionary).get("conversationId", ""),
	)
	# 等待居民答话（Provider 静默失败场景）：45 秒闲置兜底必须收尾。
	CONVERSATION_RUNTIME._advance_autonomous_conversation_timeouts(world, 44.0)
	_expect_equal(
		(world.call("get_active_conversations") as Array).size(),
		1,
		"player conversation remains active before the resident-turn deadline",
	)
	CONVERSATION_RUNTIME._advance_autonomous_conversation_timeouts(world, 2.0)
	_expect_equal(
		(world.call("get_active_conversations") as Array).size(),
		0,
		"resident-turn silence closes the player conversation at the deadline",
	)
	_expect_equal(
		(world.call("get_conversation", conversation_id) as Dictionary).get("endReason"),
		"无法继续",
		"resident-turn timeout records the unable-to-continue reason",
	)

	# 等待玩家输入时不设超时：居民答话后闲置再久也不能收。
	var started_second := world.call(
		"player_start_conversation",
		"林岚",
		"那现在呢？",
		"旅行者再次叫住林岚",
		[],
	) as Dictionary
	_expect_equal(started_second.get("ok"), true, "second invitation reaches the resident")
	var second_id := String(
		(started_second.get("conversation", {}) as Dictionary).get("conversationId", ""),
	)
	var invitation := _take_wake_player_avatar(world, "林岚")
	var replied := world.call(
		"submit_agent_decision",
		"林岚",
		_reply(invitation, second_id, "说吧。", "林岚停下来听着", false),
	) as Dictionary
	_expect_equal(replied.get("status"), "accepted", "resident replies and waits for the player")
	_expire_confirmed_preview(world)
	CONVERSATION_RUNTIME._advance_autonomous_conversation_timeouts(world, 90.0)
	_expect_equal(
		(world.call("get_active_conversations") as Array).size(),
		1,
		"waiting on the player never times out",
	)



func _test_resident_starts_and_player_rejects() -> void:
	var world := _new_world(_opening_in_garden())
	var lin_initial := _take_wake_player_avatar(world, "林岚")
	var nearby := (lin_initial.get("snapshot", {}) as Dictionary).get("nearby", []) as Array
	_expect(_nearby_has_name(nearby, "旅行者"), "resident perception exposes the avatar as an ordinary nearby person")
	var talk := _talk_player_avatar(lin_initial, "旅行者", "要一起去河边吗？", "林岚向旅行者发出邀请")
	_expect_equal(AGENT_CONTRACT.validate_decision(talk, world.call("get_agent_initialization", "林岚"), lin_initial, {}), [], "existing Agent contract allows talking to the nearby avatar")
	_expect_equal(world.call("submit_agent_decision", "林岚", talk).get("status"), "accepted", "resident can start a world conversation with the avatar")
	_expire_confirmed_preview(world)
	var avatar_conversation := (world.call("get_player_avatar_state") as Dictionary).get("conversation", {}) as Dictionary
	var conversation_id := String(avatar_conversation.get("conversation_id", ""))
	_expect(not conversation_id.is_empty(), "avatar receives the resident conversation through world state")
	var rejected := world.call("player_reject_conversation", conversation_id, "旅行者摇了摇头") as Dictionary
	_expect_equal(rejected.get("ok"), true, "player can reject an unanswered resident invitation")
	var lin_rejected := _take_wake_player_avatar(world, "林岚")
	_expect(_has_result(lin_rejected, "rejected"), "resident talk action is rejected by the confirmed player refusal")
	_expect(_has_event_player_avatar(lin_rejected, "对话结束"), "resident receives the refusal end event")
	_expect_equal((world.call("get_conversation", conversation_id) as Dictionary).get("endReason"), "拒绝接话", "world records player refusal as the formal reason")



func _test_player_leaving_ends_conversation() -> void:
	var world := _new_world(_opening_in_garden())
	var started := world.call("player_start_conversation", "林岚", "聊一会儿？", "旅行者走近林岚", []) as Dictionary
	var conversation_id := String((started.get("conversation", {}) as Dictionary).get("conversationId", ""))
	var moved := world.call("submit_player_avatar_position", "town_outdoor", Vector2(3240, 3600), "旅行者走向南入口") as Dictionary
	_expect_equal(moved.get("ok"), true, "avatar can submit a connected outdoor position change")
	_expect_equal((world.call("get_conversation", conversation_id) as Dictionary).get("endReason"), "一方离开", "leaving perception range ends the avatar conversation")
	var lin_interrupted := _take_wake_player_avatar(world, "林岚")
	_expect(_has_event_player_avatar(lin_interrupted, "对话结束"), "resident receives the conversation end when the avatar leaves")



func _test_configured_avatar_id_is_authoritative() -> void:
	var opening := _opening_in_garden()
	(opening.get("playerAvatar", {}) as Dictionary)["residentId"] = "traveler-custom-01"
	var world := _new_world(opening)
	_expect_equal((world.call("get_player_avatar_state") as Dictionary).get("residentId"), "traveler-custom-01", "avatar state preserves the configured stable id")
	var started := world.call("player_start_conversation", "林岚", "你好。", "旅行者走近打招呼", []) as Dictionary
	var conversation := started.get("conversation", {}) as Dictionary
	_expect_equal(conversation.get("initiator"), "traveler-custom-01", "conversation uses the configured avatar id")
	var resident_wake := _take_wake_player_avatar(world, "林岚")
	_expect_equal(_nearby_resident_id_player_avatar(resident_wake, "旅行者"), "traveler-custom-01", "Agent perception uses the configured avatar id")
	var talk_events := (resident_wake.get("events", []) as Array).filter(
		func(value: Variant) -> bool:
			return value is Dictionary and String((value as Dictionary).get("type", "")) == "搭话"
	)
	_expect(not talk_events.is_empty(), "configured avatar id still produces the resident talk event")
	if not talk_events.is_empty():
		var turn := ((talk_events[0] as Dictionary).get("turn", {}) as Dictionary)
		_expect_equal(turn.get("speaker_resident_id"), "traveler-custom-01", "talk event keeps the configured avatar id")



func _new_world(opening: Dictionary) -> RefCounted:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	_expect_equal(OPENING.validate(opening, data), [], "player avatar test opening is legal")
	var world: RefCounted = WORLD.new()
	_expect_equal(
		world.call("start", data, opening, _resident_identities(opening)).get("ok"),
		true,
		"player avatar test world starts with stable identities",
	)
	return world



func _new_observer_world(opening: Dictionary) -> RefCounted:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	_expect_equal(OPENING.validate(opening, data), [], "observer opening is legal")
	var world: RefCounted = WORLD.new()
	_expect_equal(
		world.call(
			"start_observer",
			data,
			opening,
			_resident_identities(opening),
		).get("ok"),
		true,
		"observer world starts absent from resident perception",
	)
	return world



func _base_opening() -> Dictionary:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	return ((OPENING.load_config(OPENING_PATH, data) as Dictionary).get("config", {}) as Dictionary).duplicate(true)



func _opening_near_clinic() -> Dictionary:
	var opening := _base_opening()
	opening["playerAvatar"]["worldState"] = {
		"place": "小镇道路",
		"spaceId": "town_outdoor",
		"regionId": "outdoor_road_01",
		"position": [4225, 1260],
		"doing": "站在诊所门外",
	}
	return opening



func _opening_in_garden() -> Dictionary:
	var opening := _base_opening()
	# 全图碰撞净空落地后 (3340,2772) 不再合法，取最近的合法点。
	_set_resident_state(opening, "林岚", Vector2(3344, 2800))
	_set_resident_state(opening, "唐小满", Vector2(3396, 2772))
	opening["playerAvatar"]["worldState"] = {
		"place": "社区花园",
		"spaceId": "town_outdoor",
		"regionId": "outdoor_garden_01",
		"position": [3368, 2772],
		"doing": "站在社区花园里",
	}
	return opening



func _set_resident_state(opening: Dictionary, resident_name: String, position: Vector2) -> void:
	for value: Variant in opening.get("residents", []) as Array:
		var resident := value as Dictionary
		if String(resident.get("attributes", {}).get("name", "")) != resident_name:
			continue
		resident["worldState"] = {
			"place": "社区花园",
			"spaceId": "town_outdoor",
			"regionId": "outdoor_garden_01",
			"position": [position.x, position.y],
			"doing": "在社区花园里",
			"body": {"困": "不困", "饿": "不饿", "累": "不累"},
		}
		return



func _take_wake_player_avatar(world: RefCounted, resident_name: String) -> Dictionary:
	var requests := world.call("take_pending_decision_requests", [resident_name]) as Array[Dictionary]
	if requests.is_empty():
		_failures.append("missing wake request for %s" % resident_name)
		return {}
	return (requests[0].get("wakePacket", {}) as Dictionary).duplicate(true)



func _wait_player_avatar(wake: Dictionary) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-wait" % decision_id,
			"type": "待着",
			"line": "继续待着",
		},
	}



func _talk_player_avatar(wake: Dictionary, target: String, say: String, narration: String) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-talk" % decision_id,
			"type": "搭话",
			"target_resident_id": _nearby_resident_id_player_avatar(wake, target),
			"say": say,
			"narration": narration,
			"photos": [],
		},
	}



func _reply(wake: Dictionary, conversation_id: String, say: String, narration: String, end: bool) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {"action_id": "%s-reply" % decision_id, "type": "答话", "conversation_id": conversation_id, "say": say, "narration": narration, "photos": [], "end": end},
	}



func _expire_confirmed_preview(world: RefCounted) -> void:
	for _step in 5:
		world.call("advance", 0.5)



func _has_event_player_avatar(wake: Dictionary, event_type: String, who := "") -> bool:
	for value: Variant in wake.get("events", []) as Array:
		var event := value as Dictionary
		if String(event.get("type", "")) == event_type and (who.is_empty() or String(event.get("who", "")) == who):
			return true
	return false



func _has_result(wake: Dictionary, status: String) -> bool:
	for value: Variant in wake.get("action_results", []) as Array:
		if String((value as Dictionary).get("status", "")) == status:
			return true
	return false



func _nearby_has_name(nearby: Array, name: String) -> bool:
	for value: Variant in nearby:
		if String((value as Dictionary).get("name", "")) == name:
			return true
	return false



func _nearby_resident_id_player_avatar(wake: Dictionary, name: String) -> String:
	var nearby := (wake.get("snapshot", {}) as Dictionary).get("nearby", []) as Array
	for value: Variant in nearby:
		var person := value as Dictionary
		if String(person.get("name", "")) == name:
			return String(person.get("resident_id", ""))
	return ""



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



func _source_data() -> Dictionary:
	return BUILDER.build_from_source(SOURCE_DIR)



func _scenario_animal_presentation() -> void:
	var character_root := Node2D.new()
	character_root.name = "CharacterRoot"
	character_root.y_sort_enabled = true
	get_root().add_child(character_root)
	var presentation := ANIMAL_PRESENTATION.new() as TownAnimalPresentation
	get_root().add_child(presentation)
	var binding := presentation.bind_character_root(character_root)
	_expect_equal(binding.get("ok"), true, "animal presentation binds to the shared character root")
	_expect_equal(binding.get("animalCount"), 6, "formal town creates three cats and three birds")
	var navigation_binding := presentation.bind_outdoor_navigation(
		_read_json(TOWN_RUNTIME_DATA_PATH)
	)
	_expect_equal(
		navigation_binding.get("ok"),
		true,
		"all cats bind the formal outdoor walkable regions",
	)
	_expect_equal(
		navigation_binding.get("boundCatCount"),
		3,
		"all three cats receive collision-safe roaming paths",
	)
	_expect(
		int(navigation_binding.get("regionBucketCount", 0)) > 0,
		"cat navigation builds a spatial index for formal walkable regions",
	)
	_expect(
		int(navigation_binding.get("polygonPointTestCount", 0)) > 0
		and int(navigation_binding.get("polygonPointTestCount", 0)) < 500000,
		"formal navigation stays within the indexed polygon-query budget",
	)
	_expect(
		int(navigation_binding.get("collisionShapeCount", 0)) > 0,
		"cat navigation filters every roaming cell through formal collision",
	)
	await process_frame

	var snapshot := presentation.get_snapshot()
	_expect_equal(snapshot.get("speciesCounts"), EXPECTED_SPECIES_COUNTS, "town contains cats and birds but no dogs")
	var animals := snapshot.get("animals", []) as Array
	var cat_palette_seeds: Array[float] = []
	var bird_palette_seeds: Array[float] = []
	for animal_value: Variant in animals:
		var animal := animal_value as Dictionary
		var visual := animal.get("visual", {}) as Dictionary
		_expect_equal(
			visual.get("hasSprite2D"),
			true,
			"%s owns a directional Sprite2D" % String(animal.get("id", "")),
		)
		_expect_equal(
			visual.get("hasSkeleton2D"),
			false,
			"%s no longer owns a Skeleton2D" % String(animal.get("id", "")),
		)
		var animal_species := String(animal.get("species", ""))
		_expect_equal(
			visual.get("animationMode"),
			(
				"Sprite2D directional flight frames"
				if animal_species == "bird"
				else "Sprite2D directional action frames"
			),
			"%s uses its directional frame animation" % String(animal.get("id", "")),
		)
		if animal_species == "cat":
			_expect_equal(
				animal.get("navigationReady"),
				true,
				"%s only roams through formal walkable cells" % String(animal.get("id", "")),
			)
			_expect(
				int(animal.get("navigationWaypointCount", 0)) > 0,
				"%s receives a connected navigation path" % String(animal.get("id", "")),
			)
			var cat_body := character_root.get_node(
				"TownAnimal_%s" % String(animal.get("id", ""))
			) as TownAnimal
			_expect(
				_cat_navigation_edges_are_clear(cat_body),
				"%s navigation graph never crosses an unsafe walkable gap"
				% String(animal.get("id", "")),
			)
			_expect(
				(visual.get("availableWalkDirections", []) as Array).has("right"),
				"%s exposes the imported right walk cycle" % String(animal.get("id", "")),
			)
			_expect_equal(
				visual.get("colorMode"),
				"seeded mixed coat",
				"%s uses a stable mixed coat palette" % String(animal.get("id", "")),
			)
			_expect_equal(
				(visual.get("coatColors", []) as Array).size(),
				3,
				"%s receives front, back and patch coat colors" % String(animal.get("id", "")),
			)
			cat_palette_seeds.append(float(visual.get("paletteSeed", 0.0)))
		elif animal_species == "bird":
			_expect_equal(
				visual.get("availableFlightDirections"),
				["front", "right", "back", "left"],
				"%s exposes four-direction flight frames" % String(animal.get("id", "")),
			)
			_expect_equal(
				visual.get("colorMode"),
				"seeded natural bird palette",
				"%s uses an independently seeded bird palette" % String(animal.get("id", "")),
			)
			_expect_equal(
				(visual.get("birdColors", []) as Array).size(),
				2,
				"%s receives feather and belly colors" % String(animal.get("id", "")),
			)
			bird_palette_seeds.append(float(visual.get("paletteSeed", 0.0)))
	_expect_equal(cat_palette_seeds.size(), 3, "all three cats expose mixed-coat palette seeds")
	_expect(
		not is_equal_approx(cat_palette_seeds[0], cat_palette_seeds[1]),
		"separate cats receive distinct mixed coat palettes",
	)
	_expect_equal(bird_palette_seeds.size(), 3, "all three birds expose palette seeds")
	_expect(
		not is_equal_approx(bird_palette_seeds[0], bird_palette_seeds[1])
		and not is_equal_approx(bird_palette_seeds[1], bird_palette_seeds[2]),
		"the three birds use visibly different natural palettes",
	)
	_expect_equal(
		character_root.find_children("*", "Skeleton2D", true, false).size(),
		0,
		"animal presentation contains no legacy Skeleton2D nodes",
	)
	var cat_visual := character_root.get_node(
		"TownAnimal_cat_mikan/AnimalSprite"
	) as TownAnimalSprite
	var cat_body := character_root.get_node(
		"TownAnimal_cat_mikan"
	) as TownAnimal
	var before_respawn := cat_body.get_snapshot()
	var before_generation := int(before_respawn.get("generation", 0))
	var before_coat_seed := int(before_respawn.get("coatSeed", 0))
	var respawned := cat_body.respawn_cat_from_corner()
	_expect_equal(
		respawned.get("generation"),
		before_generation + 1,
		"cat generation increments when it re-enters from a corner",
	)
	_expect(
		int(respawned.get("coatSeed", 0)) != before_coat_seed,
		"every cat re-entry rolls a fresh realistic mixed coat",
	)
	_expect(
		_position_is_inside_roam_rect(
			respawned.get("position", {}) as Dictionary,
			respawned.get("roamRect", {}) as Dictionary,
		),
		"cat re-enters at the nearest safe walkable point inside its roam area",
	)
	cat_body.set("_cat_lifecycle_state", "active")
	cat_body.modulate.a = 1.0
	cat_body.position = Vector2(3010.0, 2070.0)
	cat_body.set_physics_process(false)
	cat_body.set("_idle_remaining", 0.0)
	var original_movement_speed := cat_body.movement_speed
	var recovery_count_before := int(
		cat_body.get_snapshot().get("blockedRecoveryCount", 0)
	)
	cat_body.movement_speed = 0.0
	cat_body.call("_physics_process", 0.5)
	_expect_equal(
		cat_body.get_snapshot().get("blockedRecoveryCount"),
		recovery_count_before + 1,
		"cat replans after movement remains blocked beyond the recovery threshold",
	)
	cat_body.movement_speed = original_movement_speed
	cat_body.call("_clear_blocking_normals")
	cat_body.call("_remember_blocking_normal", Vector2.LEFT)
	var blocked_velocity := cat_body.call(
		"_filter_velocity_against_contacts",
		Vector2.RIGHT * original_movement_speed,
	) as Vector2
	_expect_equal(
		blocked_velocity,
		Vector2.ZERO,
		"cat does not keep pushing into a remembered collision",
	)
	var released_velocity := cat_body.call(
		"_filter_velocity_against_contacts",
		Vector2.LEFT * original_movement_speed,
	) as Vector2
	_expect_equal(
		released_velocity,
		Vector2.LEFT * original_movement_speed,
		"cat releases collision contact when moving away",
	)
	cat_body.set_physics_process(true)
	cat_visual.advance(0.5, Vector2.RIGHT, 1.0, false)
	var cat_walk_visual := cat_visual.get_visual_snapshot()
	_expect_equal(cat_walk_visual.get("usingWalkFrames"), true, "right movement starts the cat walk atlas")
	_expect_equal(cat_walk_visual.get("frameCount"), 16, "cat right walk atlas exposes sixteen frames")
	_expect_equal(cat_walk_visual.get("direction"), "right", "cat right walk keeps its requested direction")
	cat_visual.advance(0.5, Vector2.LEFT, 1.0, false)
	var cat_left_walk_visual := cat_visual.get_visual_snapshot()
	_expect_equal(cat_left_walk_visual.get("usingWalkFrames"), true, "left movement starts its own cat walk atlas")
	_expect_equal(cat_left_walk_visual.get("frameCount"), 20, "cat left walk atlas exposes twenty frames")
	_expect_equal(cat_left_walk_visual.get("direction"), "left", "cat left walk keeps its requested direction")
	cat_visual.advance(0.5, Vector2.DOWN, 1.0, false)
	var cat_front_walk_visual := cat_visual.get_visual_snapshot()
	_expect_equal(cat_front_walk_visual.get("usingWalkFrames"), true, "front movement starts its own cat walk atlas")
	_expect_equal(cat_front_walk_visual.get("frameCount"), 18, "cat front walk atlas exposes eighteen frames")
	_expect_equal(cat_front_walk_visual.get("direction"), "front", "cat front walk keeps its requested direction")
	cat_visual.advance(0.5, Vector2.UP, 1.0, false)
	var cat_back_walk_visual := cat_visual.get_visual_snapshot()
	_expect_equal(cat_back_walk_visual.get("usingWalkFrames"), true, "back movement starts its own cat walk atlas")
	_expect_equal(cat_back_walk_visual.get("frameCount"), 18, "cat back walk atlas exposes eighteen frames")
	_expect_equal(cat_back_walk_visual.get("direction"), "back", "cat back walk keeps its requested direction")

	var bird_body := character_root.get_node(
		"TownAnimal_bird_lanling"
	) as TownAnimal
	var bird_visual := bird_body.get_node("AnimalSprite") as TownAnimalSprite
	var bird_shadow := bird_body.get_node("Shadow") as Polygon2D
	_expect(not bird_shadow.z_as_relative, "bird shadow does not inherit flight depth")
	_expect_equal(
		bird_shadow.z_index,
		TownAnimal.GROUND_SHADOW_Z_INDEX,
		"bird shadow stays below map foreground occluders",
	)
	var roof_takeoff := bird_body.send_bird_to_landing(0)
	_expect_equal(roof_takeoff.get("ok"), true, "bird can select an authored rooftop landing")
	bird_body.call("_physics_process", TownAnimal.BIRD_TAKEOFF_SECONDS * 0.5)
	var takeoff_visual := bird_visual.get_visual_snapshot()
	_expect_equal(takeoff_visual.get("usingLandingFrames"), true, "bird takeoff reverses the six-frame landing atlas")
	_expect_equal(takeoff_visual.get("frameCount"), 6, "takeoff unfolds through six wing and feet phases")
	_expect(
		float(bird_body.get_snapshot().get("flightHeight", 0.0)) > 0.0,
		"bird rises above its moving ground shadow",
	)
	bird_body.call("_physics_process", TownAnimal.BIRD_TAKEOFF_SECONDS * 0.5)
	bird_body.call("_physics_process", 0.01)
	var flying_visual := bird_visual.get_visual_snapshot()
	_expect_equal(flying_visual.get("usingLandingFrames"), false, "cruising leaves the landing atlas")
	_expect_equal(flying_visual.get("usingFlightFrames"), true, "cruising starts the flight atlas")
	_expect_equal(flying_visual.get("frameCount"), 4, "each flight direction has four wing phases")
	var roof_target := (
		roof_takeoff.get("target", {}) as Dictionary
	).get("position", {}) as Dictionary
	bird_body.position = Vector2(
		float(roof_target.get("x", 0.0)) - 8.0,
		float(roof_target.get("y", 0.0)),
	)
	bird_body.call("_physics_process", 0.01)
	bird_body.call("_physics_process", 0.01)
	var landing_visual := bird_visual.get_visual_snapshot()
	_expect_equal(
		landing_visual.get("usingLandingFrames"),
		true,
		"bird switches to the dedicated landing atlas before touchdown",
	)
	_expect_equal(
		landing_visual.get("frameCount"),
		6,
		"each direction has six braking, feet-down and wing-folding frames",
	)
	bird_body.call("_physics_process", TownAnimal.BIRD_LANDING_SECONDS)
	var roof_snapshot := bird_body.get_snapshot()
	_expect_equal(roof_snapshot.get("birdState"), "landed", "bird completes its rooftop landing")
	_expect_equal(roof_snapshot.get("landingSurface"), "roof", "bird remembers that it is perched on a roof")
	_expect_equal(bird_body.z_index, TownAnimal.BIRD_ROOF_Z_INDEX, "roof bird renders above the building")
	_expect_equal(
		bird_shadow.z_index,
		TownAnimal.GROUND_SHADOW_Z_INDEX,
		"rooftop bird never lifts its ground shadow onto the roof",
	)
	_expect(
		not bird_body.get_node("OcclusionFootPoint").is_in_group("map_occlusion_subject"),
		"roof bird does not make the roof fade as if it stood behind it",
	)
	var ground_takeoff := bird_body.send_bird_to_landing(3)
	bird_body.call("_physics_process", TownAnimal.BIRD_TAKEOFF_SECONDS)
	var ground_target := (
		ground_takeoff.get("target", {}) as Dictionary
	).get("position", {}) as Dictionary
	bird_body.position = Vector2(
		float(ground_target.get("x", 0.0)) - 8.0,
		float(ground_target.get("y", 0.0)),
	)
	bird_body.call("_physics_process", 0.01)
	bird_body.call("_physics_process", TownAnimal.BIRD_LANDING_SECONDS)
	_expect_equal(
		bird_body.get_snapshot().get("landingSurface"),
		"ground",
		"bird also lands on authored ground points",
	)

	var cat_position := Vector2(3010.0, 2070.0)
	presentation.set_runtime_state(cat_position, true, true, false)
	snapshot = presentation.get_snapshot()
	_expect_equal(snapshot.get("focusedAnimalId"), "cat_mikan", "nearest pettable animal owns the E prompt")
	var pet_result := presentation.try_pet_nearest(cat_position)
	_expect_equal(pet_result.get("ok"), true, "E interaction can pet the nearest animal")
	_expect_equal(pet_result.get("animalId"), "cat_mikan", "pet interaction targets the focused animal")
	snapshot = presentation.get_snapshot()
	var petted_cat := _animal_snapshot(snapshot, "cat_mikan")
	_expect_equal(petted_cat.get("petCount"), 1, "pet reaction count is observable")
	_expect_equal(petted_cat.get("petting"), true, "pet interaction enters the sprite reaction state")
	cat_visual.advance(0.1, Vector2.ZERO, 0.0, true)
	var bob_phase := float(
		cat_visual.get_visual_snapshot().get("pettingBobPhase", -1.0)
	)
	cat_visual.advance(0.0, Vector2.ZERO, 0.0, true)
	_expect_equal(
		cat_visual.get_visual_snapshot().get("pettingBobPhase"),
		bob_phase,
		"paused animation delta freezes the petting reaction",
	)

	presentation.set_runtime_state(cat_position, false, true, true)
	snapshot = presentation.get_snapshot()
	_expect_equal(snapshot.get("focusedAnimalId"), "", "paused world clears the animal interaction prompt")
	_expect_equal(
		presentation.try_pet_nearest(cat_position).get("errorCode"),
		"ANIMAL_INTERACTION_UNAVAILABLE",
		"paused world rejects new pet interactions",
	)
	var reserved := cat_body.reserve_for_resident(
		"resident-pause-test",
		30.0,
	)
	_expect_equal(reserved, true, "cat can be reserved for a resident interaction")
	presentation.set_process(false)
	presentation.set("_world", RefCounted.new())
	presentation.set("_resident_cat_assignments", {
		"resident-pause-test": {
			"animalId": "cat_mikan",
			"residentName": "暂停测试居民",
		},
	})
	presentation.set_runtime_state(cat_position, false, true, true)
	_expect(
		(
			presentation.get("_resident_cat_assignments") as Dictionary
		).has("resident-pause-test"),
		"pause preserves an in-progress resident and cat interaction",
	)
	presentation.set_runtime_state(cat_position, false, false, false)
	_expect_equal(
		(presentation.get("_resident_cat_assignments") as Dictionary).size(),
		0,
		"hiding the world still cancels resident and cat interactions",
	)

	var occlusion_feet := 0
	for node: Node in get_nodes_in_group("map_occlusion_subject"):
		if node.name == "OcclusionFootPoint":
			occlusion_feet += 1
	_expect_equal(occlusion_feet, 6, "all six ground animals expose one map occlusion foot point")
	_test_invalid_navigation_binding(presentation)
	_test_invalid_cat_navigation_schema(cat_body)

	presentation.queue_free()
	character_root.queue_free()
	await process_frame
	return
func _animal_snapshot(snapshot: Dictionary, animal_id: String) -> Dictionary:
	for value: Variant in snapshot.get("animals", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("id", "")) == animal_id:
			return value as Dictionary
	return {}



func _position_is_inside_roam_rect(
	position_value: Dictionary,
	roam_value: Dictionary,
) -> bool:
	var position := Vector2(
		float(position_value.get("x", 0.0)),
		float(position_value.get("y", 0.0)),
	)
	var roam := Rect2(
		float(roam_value.get("x", 0.0)),
		float(roam_value.get("y", 0.0)),
		float(roam_value.get("width", 0.0)),
		float(roam_value.get("height", 0.0)),
	)
	return roam.has_point(position)



func _cat_navigation_edges_are_clear(animal: TownAnimal) -> bool:
	var cells := animal.get("_cat_navigation_cells") as Dictionary
	for cell_value: Variant in cells:
		var cell := cell_value as Vector2i
		var start := cells[cell] as Vector2
		var neighbors := animal.call("_cat_navigation_neighbors", cell) as Array
		for neighbor_value: Variant in neighbors:
			var neighbor := neighbor_value as Vector2i
			if (
				neighbor.x < cell.x
				or (neighbor.x == cell.x and neighbor.y < cell.y)
			):
				continue
			var finish := cells.get(neighbor, start) as Vector2
			var sample_count := maxi(1, ceili(start.distance_to(finish) / 2.0))
			for sample_index: int in range(1, sample_count):
				var sample := start.lerp(
					finish,
					float(sample_index) / float(sample_count),
				)
				if not bool(
					animal.call("_is_cat_navigation_position_clear", sample)
				):
					return false
	return true



func _test_invalid_navigation_binding(
	presentation: TownAnimalPresentation,
) -> void:
	var cases: Array[Dictionary] = [
		{
			"label": "non-object runtime layers",
			"runtimeData": {"layers": "bad"},
			"errorCode": "ANIMAL_OUTDOOR_NAVIGATION_REQUIRED",
		},
		{
			"label": "non-object navigation layer",
			"runtimeData": {"layers": {"navigation": "bad"}},
			"errorCode": "ANIMAL_OUTDOOR_NAVIGATION_REQUIRED",
		},
		{
			"label": "malformed walkable shape through production binding",
			"runtimeData": {
				"layers": {
					"navigation": {
						"regions": [{
							"enabled": true,
							"type": "walkable",
							"shape": "bad",
						}],
					},
				},
			},
			"errorCode": "ANIMAL_OUTDOOR_NAVIGATION_REJECTED",
		},
	]
	for case: Dictionary in cases:
		var result := presentation.bind_outdoor_navigation(
			case.get("runtimeData", {}) as Dictionary
		)
		var label := String(case.get("label", "invalid runtime navigation"))
		_expect_equal(
			result.get("ok"),
			false,
			"%s is rejected without a script error" % label,
		)
		_expect_equal(
			result.get("errorCode"),
			case.get("errorCode"),
			"%s returns a stable binding error" % label,
		)
		_expect(
			not (result.get("errors", []) as Array).is_empty(),
			"%s returns a startup reason" % label,
		)



func _test_invalid_cat_navigation_schema(animal: TownAnimal) -> void:
	var cases: Array[Dictionary] = [
		{
			"label": "non-numeric cell size",
			"navigation": {
				"cellSize": {},
				"regions": [],
			},
			"errorCode": "CAT_NAVIGATION_CELL_SIZE_INVALID",
		},
		{
			"label": "non-object region",
			"navigation": {"regions": ["bad"]},
			"errorCode": "CAT_NAVIGATION_REGION_INVALID",
		},
		{
			"label": "non-object shape",
			"navigation": {
				"regions": [{
					"enabled": true,
					"type": "walkable",
					"shape": "bad",
				}],
			},
			"errorCode": "CAT_NAVIGATION_REGION_SHAPE_INVALID",
		},
		{
			"label": "non-array points",
			"navigation": {
				"regions": [{
					"enabled": true,
					"type": "walkable",
					"shape": {"points": "bad"},
				}],
			},
			"errorCode": "CAT_NAVIGATION_REGION_POINTS_INVALID",
		},
		{
			"label": "non-object point",
			"navigation": {
				"regions": [{
					"enabled": true,
					"type": "walkable",
					"shape": {"points": [
						{"x": 0.0, "y": 0.0},
						"bad",
						{"x": 24.0, "y": 24.0},
					]},
				}],
			},
			"errorCode": "CAT_NAVIGATION_REGION_POINT_INVALID",
		},
		{
			"label": "non-numeric point coordinate",
			"navigation": {
				"regions": [{
					"enabled": true,
					"type": "walkable",
					"shape": {"points": [
						{"x": 0.0, "y": 0.0},
						{"x": [], "y": 24.0},
						{"x": 24.0, "y": 24.0},
					]},
				}],
			},
			"errorCode": "CAT_NAVIGATION_REGION_POINT_INVALID",
		},
		{
			"label": "undersized polygon",
			"navigation": {
				"regions": [{
					"enabled": true,
					"type": "walkable",
					"shape": {"points": [
						{"x": 0.0, "y": 0.0},
						{"x": 24.0, "y": 24.0},
					]},
				}],
			},
			"errorCode": "CAT_NAVIGATION_REGION_POINTS_INVALID",
		},
	]
	for case: Dictionary in cases:
		var result := animal.configure_outdoor_navigation(
			case.get("navigation", {}) as Dictionary
		)
		var label := String(case.get("label", "invalid navigation"))
		_expect_equal(
			result.get("ok"),
			false,
			"%s is rejected without a script error" % label,
		)
		_expect_equal(
			result.get("errorCode"),
			case.get("errorCode"),
			"%s returns a stable schema error" % label,
		)
		_expect(
			not (result.get("errors", []) as Array).is_empty(),
			"%s returns a player-visible startup reason" % label,
		)



func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}



func _scenario_environment_presentation() -> void:
	_verify_committed_config_and_assets()
	var renderer := ENVIRONMENT_RENDERER.new()
	renderer.name = "EnvironmentUnderTest"
	root.add_child(renderer)
	await process_frame
	await process_frame

	_expect_equal(
		renderer.apply_world_state(
			{"clock": "22:30", "period": "夜里"},
			"雷暴",
			0.25,
		),
		true,
		"canonical world state is accepted",
	)
	_expect_equal(
		renderer.apply_world_state([], "雷暴", 0.25),
		false,
		"wrong time type is rejected before conversion",
	)
	_expect_equal(
		renderer.apply_world_state({"clock": "+1:00"}, "雷暴", 0.25),
		false,
		"signed clock text is rejected",
	)
	_expect_equal(
		renderer.apply_world_state({"clock": "25:00"}, "雷暴", 0.25),
		false,
		"out-of-range clock text is rejected instead of clamped",
	)
	_expect_equal(
		renderer.apply_world_state({"clock": "22:30"}, 1, 0.25),
		false,
		"wrong weather type is rejected before conversion",
	)
	_expect_equal(
		renderer.apply_world_state({"clock": "22:30"}, "台风", 0.25),
		false,
		"unknown weather is rejected",
	)
	_expect_equal(
		renderer.apply_world_state({"clock": "22:30"}, "雷暴", NAN),
		false,
		"non-finite delta is rejected",
	)
	_expect_equal(
		renderer.apply_world_state({"clock": "22:30"}, "雷暴", -0.1),
		false,
		"negative delta is rejected",
	)
	_expect(
		renderer.visual_state([], "晴天").is_empty(),
		"visual state rejects a malformed time envelope",
	)
	_expect(
		renderer.visual_state({"clock": "12:00"}, "台风").is_empty(),
		"visual state rejects unknown weather",
	)
	_expect(
		ENVIRONMENT_RENDERER.weather_style_for_accessibility([]).is_empty(),
		"accessibility projection rejects a malformed weather style",
	)
	_expect(
		ENVIRONMENT_RENDERER.weather_style_for_accessibility(
			{"lightning": []},
		).is_empty(),
		"accessibility projection rejects a malformed lightning value",
	)
	renderer.apply_world_state(
		{"clock": "22:30", "period": "夜里"},
		"雷暴",
		0.10,
	)
	renderer.apply_world_state(
		{"clock": "22:30", "period": "夜里"},
		"雷暴",
		0.25,
	)
	renderer.apply_world_state(
		{"clock": "22:30", "period": "夜里"},
		"雷暴",
		0.25,
	)
	_expect(renderer.get_lightning_flash() > 0.0, "storm produces a readable double-pulse flash")
	_expect(renderer.get_node_or_null("FormalWorldDayNightTint") != null, "day/night tint exists")
	_expect(renderer.get_node_or_null("FormalWorldWeatherOverlay") != null, "weather overlay exists")
	var local_root := renderer.get_node_or_null("FormalWorldLocalEnvironment")
	var snow_particles: GPUParticles2D = null
	_expect(local_root != null, "local environment root exists")
	if local_root != null:
		_expect(
			local_root.get_node_or_null("FormalWorldWaterMotion") != null,
			"formal water motion exists",
		)
		var water_overlay := local_root.get_node_or_null(
			"FormalWorldWaterMotion",
		) as Sprite2D
		if water_overlay != null:
			var water_material := water_overlay.material as ShaderMaterial
			_expect(
				water_material != null
					and float(
						water_material.get_shader_parameter("world_per_screen_px"),
					) > 0.0,
				"water detail receives camera-aware overview LOD",
			)
		_expect(
			local_root.get_node_or_null("FormalWorldDirectionalShadow") != null,
			"moving sun, moon, and cloud shadow overlay exists",
		)
		_expect(
			local_root.get_node_or_null("FormalWorldGroundWeather") != null,
			"authored ground wetness and puddle surface exists",
		)
		var window_emissive := local_root.get_node_or_null(
			"FormalWorldWindowEmissive",
		) as Sprite2D
		_expect(
			window_emissive != null,
			"exact window emissive mask exists",
		)
		var window_projection := local_root.get_node_or_null(
			"FormalWorldWindowGroundProjection",
		) as Sprite2D
		_expect(
			window_projection != null,
			"window light projects onto authored ground",
		)
		if window_emissive != null:
			_expect(
				window_emissive.z_index > 101,
				"window emissive renders above dynamic facade occluders",
			)
			var emissive_material := (
				window_emissive.material as ShaderMaterial
			)
			_expect(
				emissive_material != null
					and emissive_material.shader != null
					and emissive_material.shader.code.contains(
						"render_mode unshaded, blend_add",
					)
					and float(
						emissive_material.get_shader_parameter("night_factor"),
					) > 0.99,
				"night window emissive bypasses the world tint and contributes light",
			)
		if window_projection != null:
			_expect(
				window_projection.z_index < 100,
				"window ground projection remains below facade occluders",
			)
			var projection_material := (
				window_projection.material as ShaderMaterial
			)
			_expect(
				projection_material != null
					and projection_material.shader != null
					and projection_material.shader.code.contains(
						"render_mode unshaded, blend_add",
					)
					and float(
						projection_material.get_shader_parameter("night_factor"),
					) > 0.99,
				"night window projection bypasses the world tint and contributes light",
			)
		_expect(
			local_root.get_node_or_null("FormalWorldNightMotes") == null,
			"removed night particles are not mounted",
		)
		var light_root := local_root.get_node_or_null("FormalWorldLocalLights")
		_expect(
			light_root != null and light_root.get_child_count() >= 18,
			"formal lamp cores and ground light pools exist",
		)
		var has_active_light := false
		if light_root != null:
			for child in light_root.get_children():
				if child is PointLight2D and (child as PointLight2D).energy > 0.0:
					has_active_light = true
					break
		_expect(has_active_light, "night state activates local lights")
		var smoke_root := local_root.get_node_or_null("FormalWorldChimneySmoke")
		_expect(smoke_root != null and smoke_root.get_child_count() == 20, "all mapped home chimneys exist")
		var smoke_spaces: Array[String] = []
		for smoke_state in renderer.get_smoke_emitter_snapshot():
			var smoke_space := String(smoke_state.get("spaceId", ""))
			if not smoke_spaces.has(smoke_space):
				smoke_spaces.append(smoke_space)
		smoke_spaces.sort()
		var expected_home_spaces: Array[String] = []
		for home_number in range(1, 16):
			expected_home_spaces.append("home_%02d" % home_number)
		_expect(smoke_spaces == expected_home_spaces, "every formal home has at least one mapped chimney")
		if smoke_root != null:
			for child in smoke_root.get_children():
				_expect(
					child is GPUParticles2D and not (child as GPUParticles2D).emitting,
					"unoccupied homes do not emit smoke",
				)
		var window_light_material: ShaderMaterial = null
		if window_emissive != null:
			window_light_material = window_emissive.material as ShaderMaterial
		_expect(
			window_light_material != null
				and int(window_light_material.get_shader_parameter("light_region_count")) == 0
				and not window_emissive.visible,
			"unoccupied homes and workplaces keep window lights off",
		)
		_expect_equal(
			renderer.set_space_occupancy({"home_02": 1}),
			true,
			"canonical occupancy is accepted",
		)
		_expect(
			window_light_material != null
				and int(window_light_material.get_shader_parameter("light_region_count")) == 1
				and window_emissive.visible,
			"an occupied home turns on only its own facade light",
		)
		renderer.apply_world_state(
			{"clock": "22:30", "period": "夜里"},
			"晴天",
			1.2,
		)
		var active_home_02 := 0
		var active_other_homes := 0
		for smoke_state in renderer.get_smoke_emitter_snapshot():
			if float(smoke_state.get("activity", 0.0)) <= 0.0:
				continue
			if String(smoke_state.get("spaceId", "")) == "home_02":
				active_home_02 += 1
			else:
				active_other_homes += 1
		_expect(active_home_02 == 2, "all chimneys on an occupied home emit together")
		_expect(active_other_homes == 0, "unoccupied home chimneys remain stopped")
		_expect_equal(
			renderer.set_space_occupancy({"home_02": 1.5}),
			false,
			"fractional occupancy is rejected before conversion",
		)
		renderer.apply_world_state(
			{"clock": "22:30", "period": "夜里"},
			"晴天",
			0.0,
		)
		var retained_home_02 := 0
		for smoke_state in renderer.get_smoke_emitter_snapshot():
			if (
				String(smoke_state.get("spaceId", "")) == "home_02"
				and float(smoke_state.get("activity", 0.0)) > 0.0
			):
				retained_home_02 += 1
		_expect(
			retained_home_02 == 2,
			"rejected occupancy update preserves the last confirmed state",
		)
		_expect_equal(
			renderer.set_space_occupancy({
				"town_outdoor": 1,
				"indoor_clinic": 1,
				"home_02": 1,
			}),
			true,
			"occupancy accepts every referenced formal space type",
		)
		for unknown_space_id in ["unknown_space", "home_99"]:
			_expect_equal(
				renderer.set_space_occupancy({unknown_space_id: 1}),
				false,
				"unknown space ids are rejected",
			)
		renderer.apply_world_state(
			{"clock": "22:30", "period": "夜里"},
			"晴天",
			1.8,
		)
		var retained_after_unknown_space := 0
		for smoke_state in renderer.get_smoke_emitter_snapshot():
			if (
				String(smoke_state.get("spaceId", "")) == "home_02"
				and bool(smoke_state.get("emitting", false))
				and is_equal_approx(
					float(smoke_state.get("activity", 0.0)),
					1.0,
				)
			):
				retained_after_unknown_space += 1
		_expect_equal(
			retained_after_unknown_space,
			2,
			"unknown space ids preserve the last confirmed occupancy atomically",
		)
		_expect_equal(
			renderer.set_space_occupancy({" home_02": 1}),
			false,
			"non-canonical space ids are rejected",
		)
		_expect_equal(
			renderer.set_space_occupancy({"home\n02": 1}),
			false,
			"control characters in space ids are rejected",
		)
		_expect_equal(
			renderer.set_space_occupancy([]),
			false,
			"wrong occupancy envelope type is rejected",
		)
		_expect_equal(renderer.set_space_occupancy({}), true, "empty occupancy clears")
		renderer.apply_world_state(
			{"clock": "22:30", "period": "夜里"},
			"晴天",
			1.8,
		)
		for smoke_state in renderer.get_smoke_emitter_snapshot():
			_expect(
				not bool(smoke_state.get("emitting", true)),
				"smoke stops after the occupied home becomes empty",
			)
		_expect_equal(
			renderer.set_space_occupancy({"indoor_workshop": 1}),
			true,
			"occupied workplace lighting accepts the formal indoor space",
		)
		_expect(
			window_light_material != null
				and int(window_light_material.get_shader_parameter("light_region_count")) == 1
				and window_emissive.visible,
			"an occupied workplace turns on its own facade light",
		)
		_expect_equal(
			renderer.set_space_occupancy({}),
			true,
			"clearing occupancy is accepted after workplace lighting",
		)
		_expect(
			window_light_material != null
				and int(window_light_material.get_shader_parameter("light_region_count")) == 0
				and not window_emissive.visible,
			"empty workplaces turn their facade lights off immediately",
		)
		var snow_root := local_root.get_node_or_null("FormalWorldSnowfall")
		snow_particles = (
			snow_root.get_node_or_null("FormalWorldSnowParticles") as GPUParticles2D
			if snow_root != null
			else null
		)
		_expect(snow_particles != null, "authored snowfall particles exist")
		if snow_particles != null:
			_expect(
				not snow_particles.local_coords,
				"snow remains in world space when the camera moves",
			)
			var snow_atlas_material := snow_particles.material as CanvasItemMaterial
			_expect(
				snow_atlas_material != null
				and snow_atlas_material.particles_animation
				and snow_atlas_material.particles_anim_h_frames == 2
				and snow_atlas_material.particles_anim_v_frames == 2,
				"snow uses the authored four-frame pixel atlas",
			)
	var light_rain := renderer.visual_state({"clock": "12:00"}, "小雨")
	var medium_rain := renderer.visual_state({"clock": "12:00"}, "中雨")
	var heavy_rain := renderer.visual_state({"clock": "12:00"}, "大雨")
	_expect(
		float(light_rain.get("rainDensity", 0.0))
		< float(medium_rain.get("rainDensity", 0.0)),
		"light rain is sparser than medium rain",
	)
	_expect(
		float(medium_rain.get("rainDensity", 0.0))
		< float(heavy_rain.get("rainDensity", 0.0)),
		"medium rain is sparser than heavy rain",
	)
	_expect(
		float(light_rain.get("puddleStrength", 0.0))
		< float(heavy_rain.get("puddleStrength", 0.0)),
		"heavy rain produces stronger puddles than light rain",
	)
	renderer.apply_world_state({"clock": "12:00"}, "下雪", 1.0)
	_expect(
		snow_particles != null and snow_particles.amount_ratio > 0.0,
		"snow weather activates the authored world-space flakes",
	)
	renderer.set_presentation_paused(true)
	_expect_equal(
		snow_particles.speed_scale if snow_particles != null else -1.0,
		0.0,
		"pause freezes snow particle simulation",
	)
	for smoke: GPUParticles2D in renderer.get("_smoke_particles"):
		_expect_equal(smoke.speed_scale, 0.0, "pause freezes chimney smoke particles")
	renderer.set_presentation_paused(false)
	_expect_equal(
		snow_particles.speed_scale if snow_particles != null else -1.0,
		1.0,
		"resume restores snow particle simulation",
	)
	for smoke: GPUParticles2D in renderer.get("_smoke_particles"):
		_expect_equal(smoke.speed_scale, 1.0, "resume restores chimney smoke particles")

	_expect_equal(
		renderer.set_outdoor_visible("false"),
		false,
		"wrong visibility type is rejected before conversion",
	)
	_expect(renderer.is_outdoor_visible(), "rejected visibility keeps the confirmed state")
	_expect_equal(renderer.set_outdoor_visible(false), true, "boolean visibility is accepted")
	_expect(not renderer.is_outdoor_visible(), "interior state disables outdoor presentation")
	if local_root != null:
		_expect(not (local_root as CanvasItem).visible, "local outdoor effects hide indoors")

	for call_index in 2:
		_expect_equal(
			renderer.apply_world_state(
				{"clock": "12:00", "period": "中午"},
				"晴天",
				1e308,
			),
			true,
			"large finite delta call %d uses bounded presentation time" % (call_index + 1),
		)
	var elapsed_visuals: Array[CanvasItem] = []
	var weather_layer := renderer.get_node_or_null(
		"FormalWorldWeatherOverlay",
	) as CanvasLayer
	if weather_layer != null and weather_layer.get_child_count() == 1:
		elapsed_visuals.append(weather_layer.get_child(0) as CanvasItem)
	if local_root != null:
		for elapsed_visual_name in [
			"FormalWorldWaterMotion",
			"FormalWorldGroundWeather",
			"FormalWorldDirectionalShadow",
		]:
			var elapsed_visual := local_root.get_node_or_null(
				elapsed_visual_name,
			) as CanvasItem
			if elapsed_visual != null:
				elapsed_visuals.append(elapsed_visual)
	_expect_equal(
		elapsed_visuals.size(),
		4,
		"all elapsed shader consumers are available for overflow verification",
	)
	for elapsed_visual in elapsed_visuals:
		var elapsed_material := elapsed_visual.material as ShaderMaterial
		_expect(
			elapsed_material != null
				and is_finite(
					float(elapsed_material.get_shader_parameter("elapsed")),
				),
			"%s keeps a finite bounded elapsed shader value" % elapsed_visual.name,
		)
	_expect(
		is_finite(renderer.get_lightning_flash()),
		"large finite deltas preserve finite lightning state",
	)
	for smoke_state in renderer.get_smoke_emitter_snapshot():
		_expect(
			is_finite(float(smoke_state.get("activity", NAN)))
				and is_finite(float(smoke_state.get("amountRatio", NAN))),
			"large finite deltas preserve finite smoke state",
		)

	renderer.queue_free()
	await process_frame
	return
func _verify_committed_config_and_assets() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(VISUAL_CONFIG_PATH),
	)
	_expect(parsed is Dictionary, "visual config is a JSON object")
	if not parsed is Dictionary:
		return
	var config := parsed as Dictionary
	_expect_equal(config.get("schemaVersion"), 1.0, "visual config schema is fixed")
	var config_keys := config.keys()
	config_keys.sort()
	_expect_equal(
		config_keys,
		[
			"localLights",
			"schemaVersion",
			"smokeEmitters",
			"timeKeyframes",
			"weather",
			"windowFacadeHints",
		],
		"visual config uses the closed production envelope",
	)
	var weather := config.get("weather", {}) as Dictionary
	var weather_ids := weather.keys()
	weather_ids.sort()
	var expected_weather_ids := [
		"下雪",
		"中雨",
		"大雨",
		"小雨",
		"晴天",
		"阴天",
		"雷暴",
	]
	expected_weather_ids.sort()
	_expect_equal(weather_ids, expected_weather_ids, "all and only formal weather styles exist")
	var keyframes := config.get("timeKeyframes", []) as Array
	_expect_equal(keyframes.size(), 8, "day/night interpolation keeps eight keyframes")
	_expect_equal(
		(keyframes.front() as Dictionary).get("minute"),
		0.0,
		"day/night interpolation starts at midnight",
	)
	_expect_equal(
		(keyframes.back() as Dictionary).get("minute"),
		1440.0,
		"day/night interpolation closes the full day",
	)
	_expect_equal(
		(config.get("windowFacadeHints", []) as Array).size(),
		22,
		"all formal building facade hints exist",
	)
	_expect_equal(
		(config.get("localLights", []) as Array).size(),
		9,
		"all formal map light anchors exist",
	)
	_expect_equal(
		(config.get("smokeEmitters", []) as Array).size(),
		20,
		"all formal residential chimney emitters exist",
	)
	for path in MAP_MASK_PATHS:
		var texture := load(path) as Texture2D
		_expect(texture != null, "%s loads as a Godot texture" % path)
		if texture != null:
			_expect_equal(texture.get_size(), Vector2(MAP_SIZE), "%s matches the town map" % path)
	var snowflake_atlas := load(SNOWFLAKE_ATLAS_PATH) as Texture2D
	_expect(snowflake_atlas != null, "snowflake atlas loads as a Godot texture")
	if snowflake_atlas != null:
		_expect_equal(
			snowflake_atlas.get_size(),
			Vector2(316, 316),
			"snowflake atlas keeps its authored four-frame sheet",
		)



func _scenario_resident_wardrobe_runtime() -> void:
	var wardrobe := _read_json_resident_wardrobe_runtime(WARDROBE_CATALOG_PATH)
	_expect_equal(
		(wardrobe.get("loadouts", []) as Array).size(),
		16,
		"wardrobe publishes sixteen approved loadouts",
	)
	_expect_equal(
		(wardrobe.get("residentAssignments", {}) as Dictionary).size(),
		16,
		"wardrobe binds all sixteen preset residents",
	)
	_expect_equal(
		CATALOG.validate(CATALOG.load_catalog()).get("ok"),
		true,
		"resident catalog and portrait bindings validate",
	)

	var rig = RIG.new()
	root.add_child(rig)
	await process_frame
	var rig_state: Dictionary = rig.get_rig_state()
	_expect_equal(
		rig_state.get("contractValid"),
		true,
		"resident rig mounts the wardrobe without weakening its base contract",
	)
	_expect_equal(
		rig_state.get("wardrobeEnabled"),
		true,
		"resident wardrobe is active",
	)
	_expect_equal(
		rig_state.get("renderMode"),
		"complete_sprite_sheet",
		"resident runtime displays one complete character sheet",
	)
	_expect_equal(
		rig_state.get("completeSetFrame"),
		rig_state.get("completeSetIdleFrame"),
		"complete-set resident starts on the centered idle frame",
	)
	var complete_set_sprite := rig.get_node("CompleteResidentSet") as Sprite2D
	var visible_sole_y := (
		complete_set_sprite.position.y
		+ (469.0 - 256.0) * complete_set_sprite.scale.y
	)
	_expect(
		visible_sole_y > 5.5 and visible_sole_y < 6.5,
		"complete-set shoe sole shares the feet collision ground point",
	)
	rig.set_motion(Vector2.DOWN, 12.0, 1.0 / 60.0)
	rig.reset_locomotion()
	rig_state = rig.get_rig_state()
	_expect_equal(
		rig_state.get("completeSetFrame"),
		rig_state.get("completeSetIdleFrame"),
		"stopping after movement restores the centered idle frame",
	)
	_expect_equal(
		rig.get_active_loadout_id(),
		"look_00",
		"unknown resident uses the deterministic first approved loadout",
	)
	_expect(
		rig.set_resident_appearance("resident_lin_lan_01", ""),
		"resident assignment resolves an omitted appearance",
	)
	_expect_equal(
		rig.get_active_loadout_id(),
		"look_01",
		"resident assignment selects the expected loadout",
	)
	_expect(
		rig.set_resident_appearance(
			"resident_lin_lan_01",
			"paper_doll_64:neutral_hoodie",
		),
		"legacy preset resolves through the approved alias table",
	)
	_expect_equal(
		rig.get_active_loadout_id(),
		"look_01",
		"legacy appearance preserves the resident look",
	)
	_expect(
		not rig.set_resident_appearance(
			"resident_lin_lan_01",
			"resident_wardrobe_v1:not_a_loadout",
		),
		"unknown new wardrobe ids fail closed",
	)
	_expect_equal(
		rig.get_active_loadout_id(),
		"look_01",
		"rejected appearance leaves the active look unchanged",
	)
	var unique_part_hashes: Dictionary = {}
	for loadout_value: Variant in wardrobe.get("loadouts", []) as Array:
		var loadout := loadout_value as Dictionary
		for direction_value: Variant in (
			loadout.get("directions", {}) as Dictionary
		).values():
			for sha_value: Variant in (
				(direction_value as Dictionary).get("partSha256", {})
				as Dictionary
			).values():
				unique_part_hashes[String(sha_value)] = true
		_expect(
			rig.set_resident_appearance(
				"",
				String(loadout.get("appearanceId", "")),
			),
			"every approved loadout applies to the in-game rig",
		)
	_expect(
		int(
			rig.get_rig_state().get("loadedWardrobeTextureCount", 0),
		) <= unique_part_hashes.size() + 45,
		"identical wardrobe parts share one decoded texture by content hash",
	)
	rig.queue_free()
	await process_frame

	var body = BODY.new()
	root.add_child(body)
	body.set_automatic_motion(false)
	var invalid := body.configure(
		{
			"residentId": "resident_lin_lan_01",
			"residentName": "林岚",
		},
		{
			"position": Vector2.ZERO,
			"movementRevision": 0,
			"appearance": "resident_wardrobe_v1:not_a_loadout",
		},
	)
	_expect_equal(
		invalid.get("code"),
		"PRESENTATION_APPEARANCE_INVALID",
		"resident body rejects an unknown wardrobe id before identity mutation",
	)
	var configured := body.configure(
		{
			"residentId": "resident_lin_lan_01",
			"residentName": "林岚",
		},
		{
			"position": Vector2.ZERO,
			"movementRevision": 0,
			"appearance": "resident_wardrobe_v1:look_01",
		},
	)
	_expect_equal(
		configured.get("ok"),
		true,
		"resident body accepts its approved appearance",
	)
	_expect_equal(
		body.collision_layer,
		4,
		"complete-set appearance preserves the resident collision layer",
	)
	_expect_equal(
		body.collision_mask,
		11,
		"complete-set appearance preserves map, player, and ground-animal collision masks",
	)
	var feet_collision := body.get_node("FeetCollision") as CollisionShape2D
	_expect(
		feet_collision != null and not feet_collision.disabled,
		"complete-set appearance keeps the resident feet collision active",
	)
	var newer_state := {
		"residentId": "resident_lin_lan_01",
		"position": Vector2.ZERO,
		"spaceId": "town",
		"movementRevision": 1,
		"appearance": "resident_wardrobe_v1:look_02",
	}
	_expect_equal(
		body.apply_authoritative_state(newer_state, 5).get("ok"),
		true,
		"newer authority applies its wardrobe appearance",
	)
	var stale_state := newer_state.duplicate(true)
	stale_state["movementRevision"] = 0
	stale_state["appearance"] = "resident_wardrobe_v1:look_03"
	_expect_equal(
		body.apply_authoritative_state(stale_state, 4).get("code"),
		"PRESENTATION_STALE_AUTHORITY_IGNORED",
		"stale wardrobe authority is ignored",
	)
	_expect_equal(
		(
			body.get_presentation_snapshot().get("visual", {})
			as Dictionary
		).get("activeLoadoutId"),
		"look_02",
		"stale authority cannot roll back the active wardrobe",
	)
	body.queue_free()
	await process_frame

	var base_catalog := CATALOG.load_catalog()
	var old_sprite_path := (
		"res://assets/characters/paper_doll_64/compiled/"
		+ "neutral_hoodie_walk_64.png"
	)
	var legacy_candidate := {
		"residentId": "custom_resident_legacy_0001",
		"source": "custom",
		"attributes": {
			"name": "旧居民",
			"gender": "女",
			"age": 27,
			"desire": "继续住在小镇",
			"personality": "安静",
			"speech": "简短",
			"selectionSummary": "旧存档居民",
		},
		"appearance": {
			"appearanceId": "paper_doll_64:neutral_hoodie",
			"loadoutId": "neutral_hoodie",
			"selection": {
				"head": "neutral_hoodie",
				"top_hands": "neutral_hoodie",
				"bottom": "neutral_hoodie",
				"shoes": "neutral_hoodie",
			},
			"atlasRef": old_sprite_path,
			"formalReady": true,
			"directionSetReady": true,
		},
		"occupation": {
			"name": "园丁",
			"workplacePlace": "社区花园",
			"ownedPlace": "",
		},
		"presentation": {
			"spritePath": old_sprite_path,
			"locationLabel": "社区花园",
		},
	}
	var migrated_pool = CANDIDATE_POOL.new()
	var migrated_configuration := migrated_pool.configure(
		base_catalog,
		{
			"candidatePoolRevision": 7,
			"customCandidates": [legacy_candidate],
		},
	) as Dictionary
	_expect_equal(
		migrated_configuration.get("ok"),
		true,
		(
			"persisted v1 custom residents migrate without blocking the pool: %s"
			% JSON.stringify(migrated_configuration)
		),
	)
	var migrated_candidates: Array = migrated_pool.get_custom_candidates()
	if migrated_candidates.is_empty():
		_failures.append(
			"persisted v1 migration retains one custom resident",
		)
		return
	_expect_equal(
		(
			(migrated_candidates[0] as Dictionary).get("attributes", {})
			as Dictionary
		).get("appearance"),
		"resident_wardrobe_v1:look_01",
		"legacy preset aliases preserve the closest approved appearance",
	)
	_expect(
		not (
			(migrated_candidates[0] as Dictionary).get(
				"occupation",
				{},
			) as Dictionary
		).has("ownedPlace"),
		"legacy owned-place data is removed while interests use the resident profile",
	)
	var mixed_candidates: Array = []
	for index in range(2):
		var mixed_candidate := legacy_candidate.duplicate(true)
		mixed_candidate["residentId"] = "custom_resident_mixed_%04d" % index
		var mixed_appearance := (
			(mixed_candidate.get("appearance", {}) as Dictionary).duplicate(true)
		)
		mixed_appearance["appearanceId"] = (
			"paper_doll_64:mix__h-%s__t-suit_man"
			% ("neutral_hoodie" if index == 0 else "elder_man")
			+ "__b-skirt_woman__s-street_creator"
		)
		mixed_candidate["appearance"] = mixed_appearance
		mixed_candidates.append(mixed_candidate)
	var mixed_pool = CANDIDATE_POOL.new()
	_expect_equal(
		mixed_pool.configure(
			base_catalog,
			{
				"candidatePoolRevision": 7,
				"customCandidates": mixed_candidates,
			},
		).get("ok"),
		true,
		"legacy mixed wardrobes migrate without blocking the pool",
	)
	var migrated_mixed: Array = mixed_pool.get_custom_candidates()
	var first_mixed_appearance := String(
		(
			(migrated_mixed[0] as Dictionary).get("attributes", {})
			as Dictionary
		).get("appearance", "")
	)
	var second_mixed_appearance := String(
		(
			(migrated_mixed[1] as Dictionary).get("attributes", {})
			as Dictionary
		).get("appearance", "")
	)
	_expect(
		first_mixed_appearance.begins_with("resident_wardrobe_v1:look_")
		and second_mixed_appearance.begins_with("resident_wardrobe_v1:look_")
		and first_mixed_appearance != second_mixed_appearance,
		"legacy mixed wardrobes migrate deterministically without collapsing to one look",
	)

	var current_pool = CANDIDATE_POOL.new()
	_expect_equal(
		current_pool.configure(base_catalog).get("ok"),
		true,
		"current custom resident pool configures",
	)
	var creator_service = CREATOR_SERVICE.new()
	_expect_equal(
		creator_service.configure(
			current_pool,
			base_catalog,
			_read_json_resident_wardrobe_runtime("res://world/data/town/town_world.json"),
		).get("ok"),
		true,
		"custom resident creator publishes the new wardrobe contract",
	)
	var creator_screen = CREATOR_SCREEN.new()
	_expect(
		creator_screen.apply_view_model(creator_service.get_view_model()),
		"formal custom resident page accepts and previews the new wardrobe",
	)
	creator_screen.free()

	var wardrobe_page = WARDROBE_PAGE.instantiate()
	root.add_child(wardrobe_page)
	await process_frame
	var wardrobe_snapshot := wardrobe_page.debug_snapshot() as Dictionary
	_expect_equal(
		wardrobe_snapshot.get("selectionMode"),
		"complete_set_only",
		"wardrobe only exposes complete resident sets",
	)
	_expect_equal(
		wardrobe_snapshot.get("activeCategoryId"),
		"preset",
		"wardrobe opens directly on complete sets",
	)
	_expect_equal(
		wardrobe_snapshot.get("catalogTotalEntryCount"),
		16,
		"wardrobe lists all sixteen resident sets",
	)
	var wardrobe_hit_rects := (
		wardrobe_page.get_hit_target_rects_in_viewport() as Dictionary
	)
	_expect(
		not wardrobe_hit_rects.has("category_head")
		and not wardrobe_hit_rects.has("category_top_hands")
		and not wardrobe_hit_rects.has("category_bottom")
		and not wardrobe_hit_rects.has("category_shoes"),
		"wardrobe does not expose split clothing controls",
	)
	wardrobe_page.queue_free()
	await process_frame
	return
func _read_json_resident_wardrobe_runtime(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path),
	)
	return parsed as Dictionary if parsed is Dictionary else {}



func _scenario_resident_character_host() -> void:
	var world_data := _read_json(WORLD_DATA_PATH)
	var opening_result := OPENING.load_config(OPENING_PATH, world_data)
	var opening := opening_result.get("config", {}) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "formal opening loader normalizes the fixture")
	if not bool(opening_result.get("ok", false)):
		return
	var identities: Array[Dictionary] = []
	var connected_residents: Array[String] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		var attributes := resident.get("attributes", {}) as Dictionary
		identities.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(attributes.get("name", "")),
		})
		connected_residents.append(String(attributes.get("name", "")))
	var runtime := TOWN_RUNTIME_SCENE.instantiate() as Node
	var configured := runtime.call("configure_session", {
		"openingConfig": opening,
		"residentIdentities": identities,
		"connectedResidents": connected_residents,
		"worldStartMode": "development",
		"requireAgentGateway": false,
		"enableTestUi": false,
		"source": "production_host_test",
	}) as Dictionary
	_expect_equal(configured.get("ok"), true, "production TownRuntime accepts the complete identity set")
	if not bool(configured.get("ok", false)):
		runtime.free()
		return
	root.add_child(runtime)
	await _wait_frames(5)
	var startup := runtime.call("get_startup_result") as Dictionary
	_expect_equal(startup.get("ok"), true, "production TownRuntime starts with resident characters")
	if not bool(startup.get("ok", false)):
		runtime.queue_free()
		await process_frame
		return
	var presentation_snapshot := (
		runtime.call("get_resident_character_presentation_snapshot") as Dictionary
	)
	_expect_equal(presentation_snapshot.get("residentCount"), 15, "host registers all 15 stable residents")
	_expect_equal(
		(presentation_snapshot.get("residentIds", []) as Array).size(),
		15,
		"host publishes 15 stable resident IDs",
	)
	_expect_equal(
		presentation_snapshot.get("legacyActorCount"),
		0,
		"new host reports no legacy actor rendering",
	)
	_expect_equal(
		(runtime as Node2D).y_sort_enabled,
		true,
		"formal runtime shares Y sorting between the player and resident host",
	)
	_expect_equal(presentation_snapshot.get("ySortEnabled"), true, "resident root enables Y sorting")
	_expect_equal(
		presentation_snapshot.get("activeSpaceId"),
		"town_outdoor",
		"resident host starts in the outdoor space",
	)
	_expect(
		runtime.get_node_or_null("TownResidentPresentation") == null,
		"legacy TownResidentPresentation is not mounted",
	)
	var resident_root := runtime.get_node_or_null("ResidentCharacterRoot") as Node2D
	_expect(resident_root != null, "production host mounts the unique resident character root")
	if resident_root == null:
		runtime.queue_free()
		await process_frame
		return
	var resident_body_count := 0
	var resident_label_count := 0
	for child: Node in resident_root.get_children():
		if child is ResidentCharacterBody:
			resident_body_count += 1
			resident_label_count += child.find_children(
				"*",
				"Label",
				true,
				false,
			).size()
	_expect_equal(
		resident_body_count,
		15,
		"shared character root has exactly 15 resident bodies",
	)
	_expect_equal(
		resident_label_count,
		0,
		"complete resident characters do not render legacy name blocks",
	)
	var world := runtime.call("get_world_runtime") as RefCounted
	var outdoor_body := _resident_body(resident_root, "resident_lin_lan_01")
	var indoor_body := _resident_body(resident_root, "resident_gu_chuan_01")
	_expect(outdoor_body != null, "outdoor stable resident body is registered")
	_expect(indoor_body != null, "indoor stable resident body is registered")
	if outdoor_body != null:
		_assert_character_contract(outdoor_body, true, "outdoor resident")
		var world_menu := RESIDENT_ACTION_WORLD_MENU_SCENE.instantiate() as Control
		var menu_mount := runtime.call(
			"attach_world_resident_action_menu",
			world_menu,
			{"residentId": "resident_lin_lan_01"},
		) as Dictionary
		_expect_equal(
			menu_mount.get("ok"),
			true,
			"resident action menu mounts on the visible resident body",
		)
		if world_menu != null:
			_expect_equal(
				world_menu.get_parent(),
				outdoor_body,
				"resident action menu parent is the resident body, not a bubble layer",
			)
			_expect(
				world_menu.position.is_equal_approx(Vector2.ZERO),
				"resident action menu root stays at the body origin",
			)
			world_menu.queue_free()
		var movement := (
			world.call(
				"get_resident_movement_snapshot",
				"resident_lin_lan_01",
			) as Dictionary
		)
		_expect_equal(
			outdoor_body.get_movement_revision(),
			movement.get("movementRevision"),
			"body consumes the public movement revision",
		)
		var movement_contract := world.call(
			"get_space_character_movement_contract",
			"town_outdoor",
		) as Dictionary
		var presentation_policy := (
			movement_contract.get("presentationPolicy", {}) as Dictionary
		)
		_expect_equal(
			outdoor_body.large_correction_distance,
			float(presentation_policy.get("sameSpaceCatchUpMaxDistancePx", 0.0)),
			"body consumes the public same-space catch-up threshold",
		)
	if indoor_body != null:
		_assert_character_contract(indoor_body, false, "inactive indoor resident")
	var outdoor_collision := (
		runtime.find_child("WorldBlockCollision", true, false) as StaticBody2D
	)
	_expect(outdoor_collision != null, "formal outdoor StaticBody collision is mounted")
	var observed: Variant = await runtime.call("observe_place", "诊所")
	_expect_equal(observed, true, "observer portal enters the formal clinic")
	await _wait_frames(3)
	presentation_snapshot = (
		runtime.call("get_resident_character_presentation_snapshot") as Dictionary
	)
	_expect_equal(
		presentation_snapshot.get("activeSpaceId"),
		"indoor_clinic",
		"portal switch activates the World clinic space",
	)
	_expect(
		not (presentation_snapshot.get("visibleResidentNames", []) as Array).has("林岚"),
		"outdoor resident hides after the portal switch",
	)
	_expect(
		(presentation_snapshot.get("visibleResidentNames", []) as Array).has("顾川"),
		"clinic resident becomes a complete visible character",
	)
	if indoor_body != null:
		_assert_character_contract(indoor_body, true, "active indoor resident")
		var clinic_room := runtime.find_child("IndoorClinic", true, false) as Node2D
		_expect(clinic_room != null and clinic_room.visible, "formal clinic room is active")
		if clinic_room != null:
			var furniture_collision := _first_furniture_collision(clinic_room)
			_expect(
				furniture_collision != null,
				"formal clinic furniture exposes layer-one StaticBody collision",
			)
	var returned: Variant = await runtime.call("return_to_town_overview")
	_expect_equal(returned, true, "observer portal returns to the outdoor map")
	await _wait_frames(3)
	presentation_snapshot = (
		runtime.call("get_resident_character_presentation_snapshot") as Dictionary
	)
	_expect_equal(
		presentation_snapshot.get("activeSpaceId"),
		"town_outdoor",
		"portal return reactivates the outdoor resident space",
	)
	var save_result := world.call("create_save_snapshot") as Dictionary
	var saved := (save_result.get("snapshot", {}) as Dictionary).duplicate(true)
	_expect_equal(save_result.get("ok"), true, "World creates a restore snapshot")
	_expect_equal(saved.get("schema"), "town-world-save", "World produces a formal restore snapshot")
	var restored := world.call(
		"restore_from_snapshot",
		world_data,
		opening,
		saved,
		identities,
	) as Dictionary
	if restored.get("ok") != true:
		printerr(
			"TOWN_RESIDENT_CHARACTER_HOST_RESTORE_DIAGNOSTIC: ",
			restored,
		)
	_expect_equal(restored.get("ok"), true, "development restore commits through the public World API")
	await _wait_frames(2)
	presentation_snapshot = (
		runtime.call("get_resident_character_presentation_snapshot") as Dictionary
	)
	_expect_equal(
		presentation_snapshot.get("residentCount"),
		15,
		"restore preserves the complete stable resident registry",
	)
	_expect_equal(
		presentation_snapshot.get("worldRevision"),
		world.call("get_world_revision"),
		"world_restored forces presentation to the confirmed revision",
	)
	for body_snapshot_value: Variant in (
		presentation_snapshot.get("bodySnapshots", []) as Array
	):
		var body_snapshot := body_snapshot_value as Dictionary
		_expect_equal(
			body_snapshot.get("worldWriteAttempted"),
			false,
			"resident presentation never writes authority during restore",
		)
	runtime.queue_free()
	await _wait_frames(3)
	return
func _assert_character_contract(
	body: ResidentCharacterBody,
	active: bool,
	label: String,
) -> void:
	_expect_equal(body.visible, active, "%s has correct active-space visibility" % label)
	_expect_equal(
		body.collision_layer,
		4 if active else 0,
		"%s occupies the resident collision layer only in its active space"
		% label,
	)
	_expect_equal(
		body.collision_mask,
		11 if active else 0,
		"%s detects the map, player and ground animals without blocking other authoritative resident routes"
		% label,
	)
	var feet := body.get_node("FeetCollision") as CollisionShape2D
	_expect(
		feet != null and not feet.disabled,
		"%s keeps a compact feet shape for local avoidance" % label,
	)
	_expect(body.is_in_group("map_occlusion_subject"), "%s participates in occlusion" % label)
	var rig: Variant = body.get_character_rig()
	_expect(rig != null, "%s mounts the frozen skeletal runtime" % label)
	if rig == null:
		return
	var rig_state: Dictionary = rig.get_rig_state()
	_expect_equal(
		rig_state.get("contractValid"),
		true,
		"%s validates the production_frozen_v2 contract" % label,
	)
	_expect_equal(
		rig_state.get("boneCount"),
		18,
		"%s builds the locked 18-bone hierarchy" % label,
	)
	_expect_equal(
		rig_state.get("artworkPartCount"),
		15,
		"%s builds the locked 15 visible parts" % label,
	)
	_expect_equal(
		rig_state.get("visualSource"),
		"classic_resident_complete_set_v1",
		"%s uses the approved complete resident set" % label,
	)
	_expect_equal(
		rig_state.get("wardrobeEnabled"),
		true,
		"%s mounts the approved wardrobe slots" % label,
	)
	_expect_equal(
		rig.find_children("*", "Skeleton2D", true, false).size(),
		3,
		"%s carries down/right/up source skeletons" % label,
	)



func _first_furniture_collision(room: Node2D) -> StaticBody2D:
	for node in room.find_children("ContinuousGroundCollision", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		if body.collision_layer == 1:
			return body
	return null



func _resident_body(
	resident_root: Node2D,
	resident_id: String,
) -> ResidentCharacterBody:
	for child in resident_root.get_children():
		if (
			child is ResidentCharacterBody
			and (child as ResidentCharacterBody).get_resident_id() == resident_id
		):
			return child as ResidentCharacterBody
	return null



func _wait_frames(count: int) -> void:
	for _index in count:
		await process_frame



func _scenario_resident_character_world_route() -> void:
	var world_data := _read_json(WORLD_DATA_PATH)
	var opening_result := OPENING.load_config(OPENING_PATH, world_data) as Dictionary
	var opening := opening_result.get("config", {}) as Dictionary
	var identities: Array[Dictionary] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		var attributes := resident.get("attributes", {}) as Dictionary
		identities.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(attributes.get("name", "")),
		})
	var world: RefCounted = WORLD.new()
	var started := world.call("start", world_data, opening, identities) as Dictionary
	if not bool(started.get("ok", false)):
		printerr(
			"RESIDENT_CHARACTER_WORLD_ROUTE_START_DIAGNOSTIC: ",
			started,
		)
	_expect_equal(started.get("ok"), true, "development World starts")
	var actor_root := Node2D.new()
	actor_root.y_sort_enabled = true
	root.add_child(actor_root)
	var presentation: Node = PRESENTATION.new()
	root.add_child(presentation)
	var bound := presentation.call("bind_world", world, actor_root) as Dictionary
	if not bool(bound.get("ok", false)):
		printerr(
			"RESIDENT_CHARACTER_WORLD_ROUTE_BIND_DIAGNOSTIC: ",
			bound,
		)
	_expect_equal(bound.get("ok"), true, "resident presentation binds")
	var body := presentation.call("get_body", RESIDENT_ID) as CharacterBody2D
	_expect(body != null, "stable residentId resolves to a body")
	if body == null:
		return
	body.call("set_automatic_motion", false)
	_expect(_submit_go(world, "社区花园"), "outbound route is accepted")
	await _run_route(world, body)
	_expect(_submit_go(world, "中心广场"), "return route is accepted")
	await _run_route(world, body)
	for direction_name: String in ["down", "right", "up", "left"]:
		_expect(
			bool(_directions.get(direction_name, false)),
			"real World routes drive %s skeletal direction" % direction_name,
		)
	_expect(_moving_frame_count > 0, "World routes produce moving presentation frames")
	_expect(
		_single_root_frame_count == _moving_frame_count,
		"every moving frame exposes exactly one character visual owner",
	)
	_expect(
		_phase_change_count >= 8,
		"real distance advances the skeletal gait phase continuously",
	)
	world.call("stop")
	presentation.queue_free()
	actor_root.queue_free()
	await process_frame
	return
func _submit_go(world: RefCounted, place_name: String) -> bool:
	var requests := world.call(
		"take_pending_decision_requests_by_ids",
		[RESIDENT_ID],
	) as Array
	if requests.is_empty():
		return false
	var wake := (requests[0] as Dictionary).get("wakePacket", {}) as Dictionary
	var decision_id := String(wake.get("decision_id", ""))
	var accepted := world.call(
		"submit_agent_decision_by_id",
		RESIDENT_ID,
		{
			"decision_id": decision_id,
			"handling": "replace_current",
			"action": {
				"action_id": "%s-route" % decision_id,
				"type": "去",
				"place": place_name,
				"line": "去%s" % place_name,
			},
		},
	) as Dictionary
	return bool(accepted.get("ok", false))



func _run_route(world: RefCounted, body: CharacterBody2D) -> void:
	var route_guard := 0
	while route_guard < 60:
		var resident_state := world.call(
			"get_resident_state",
			RESIDENT_ID,
		) as Dictionary
		if resident_state.get("currentAction") == null:
			break
		var before_world := (
			world.call("get_resident_movement_snapshot", RESIDENT_ID) as Dictionary
		).get("position", Vector2.ZERO) as Vector2
		world.call("advance", 1.0)
		var movement := world.call(
			"get_resident_movement_snapshot",
			RESIDENT_ID,
		) as Dictionary
		var after_world := movement.get("position", Vector2.ZERO) as Vector2
		var world_distance := before_world.distance_to(after_world)
		var moving_frames_this_sample := 0
		var last_phase := -1.0
		for _frame in PRESENTATION_FRAMES_PER_WORLD_MINUTE:
			await physics_frame
			var before_body: Vector2 = body.position
			body.call(
				"advance_presentation",
				1.0 / float(PRESENTATION_FRAMES_PER_WORLD_MINUTE),
			)
			var travelled := before_body.distance_to(body.position)
			if travelled <= 0.01:
				continue
			moving_frames_this_sample += 1
			_moving_frame_count += 1
			var rig: Node2D = body.call("get_character_rig")
			var rig_state := rig.call("get_rig_state") as Dictionary
			var direction_name := String(rig_state.get("activeDirection", ""))
			_directions[direction_name] = true
			var visible_roots := 0
			for source_name: String in ["Down", "Right", "Up"]:
				var direction_root := rig.get_node(
					"%sFrozenWhitebodyRig" % source_name
				) as Node2D
				if direction_root.visible:
					visible_roots += 1
			var render_mode := String(
				rig_state.get("renderMode", "articulated_rig")
			)
			var has_single_visual_owner := (
				visible_roots == 0
				if render_mode == "complete_sprite_sheet"
				else visible_roots == 1
			)
			if has_single_visual_owner:
				_single_root_frame_count += 1
			var phase := float(rig_state.get("walkPhase", 0.0))
			if last_phase >= 0.0 and not is_equal_approx(last_phase, phase):
				_phase_change_count += 1
			last_phase = phase
		if world_distance > 0.01:
			_expect(
				moving_frames_this_sample > 0
				and moving_frames_this_sample
				<= PRESENTATION_FRAMES_PER_WORLD_MINUTE,
				"each World sample advances continuously without inventing extra distance",
			)
			_expect(
				body.position.distance_to(after_world) < 0.2,
				(
					"presentation reaches the confirmed sample without chasing behind World"
					+ " (body=%s, world=%s, distance=%.3f)"
					% [
						body.position,
						after_world,
						body.position.distance_to(after_world),
					]
				),
			)
			var before_late_sample_frame: Vector2 = body.position
			await physics_frame
			body.call(
				"advance_presentation",
				1.0 / float(PRESENTATION_FRAMES_PER_WORLD_MINUTE),
			)
			_expect(
				before_late_sample_frame.distance_to(body.position) <= 0.01,
				"presentation does not drift past a confirmed World sample",
			)
		route_guard += 1
	var final_world_position := (
		world.call("get_resident_movement_snapshot", RESIDENT_ID) as Dictionary
	).get("position", Vector2.ZERO) as Vector2
	for _frame in 3:
		await physics_frame
		body.call(
			"advance_presentation",
			1.0 / float(PRESENTATION_FRAMES_PER_WORLD_MINUTE),
		)
	_expect(
		body.position.distance_to(final_world_position) < 0.2,
		"presentation finishes exactly at the final World sample",
	)
	_expect(route_guard < 60, "World route completes before the guard")



func _scenario_resident_presentation_path_contract() -> void:
	var world: RefCounted = WORLD.new()
	var expected: Array[Vector2] = [
		Vector2(12.0, 24.0),
		Vector2(48.0, 24.0),
		Vector2(48.0, 72.0),
	]
	var prop_path := world.call(
		"_resident_presentation_path",
		{
			"position": expected[0],
			"currentAction": {
				"type": "用道具",
				"pathPoints": expected,
			},
		},
	) as Array[Vector2]
	_expect_equal(
		prop_path,
		expected,
		"prop approach exposes the authored polyline to presentation",
	)
	var malformed_path := world.call(
		"_resident_presentation_path",
		{
			"position": Vector2.ZERO,
			"currentAction": {
				"type": "用道具",
				"pathPoints": [Vector2.ZERO, {"x": 10, "y": 20}],
			},
		},
	) as Array[Vector2]
	_expect_equal(
		malformed_path,
		[],
		"malformed prop paths are rejected instead of becoming direct chords",
	)
	return
