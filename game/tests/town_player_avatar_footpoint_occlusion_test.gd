extends SceneTree


const TOWN_BASE := preload("res://world/maps/town/TownBase.gd")
const RUNTIME_OCCLUSION_LAYER := preload(
	"res://world/runtime/MapRuntimeOcclusionLayer.gd"
)
const EXPECTED_PLAYER_DISPLAY_SCALE := 1.65
const OCCLUSION_SUBJECT_GROUP := "map_occlusion_subject"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var town := TOWN_BASE.new()
	get_root().add_child(town)
	await process_frame
	await process_frame

	var player := town.get_node_or_null("Player") as CharacterBody2D
	_expect(player != null, "formal town builds a Player CharacterBody2D")
	if player == null:
		_finish()
		return

	var visual := player.get_node_or_null("PaperDoll64Visual") as Node2D
	_expect(visual != null, "formal player keeps the PaperDoll64 visual root")
	if visual != null:
		_expect(
			is_equal_approx(visual.scale.x, EXPECTED_PLAYER_DISPLAY_SCALE)
			and is_equal_approx(visual.scale.y, EXPECTED_PLAYER_DISPLAY_SCALE),
			"formal player avatar scale matches resident bone-agent map size"
		)

	var foot_point := player.get_node_or_null("PlayerOcclusionFootPoint") as Marker2D
	_expect(foot_point != null, "formal player has a dedicated occlusion foot-point marker")
	if foot_point != null:
		_expect(
			foot_point.is_in_group(OCCLUSION_SUBJECT_GROUP),
			"only the foot-point marker participates in map occlusion"
		)
		_expect(
			foot_point.global_position.distance_to(player.global_position) <= 0.001,
			"occlusion marker uses the player foot/root position"
		)
		_expect_equal(
			foot_point.z_index,
			player.z_index,
			"occlusion marker preserves player depth for front/back sorting"
		)
	_expect(
		not player.is_in_group(OCCLUSION_SUBJECT_GROUP),
		"whole player body is not an occlusion subject"
	)
	var shadow := player.get_node_or_null("Shadow") as Polygon2D
	_expect(shadow != null, "formal player has a ground shadow")
	if shadow != null:
		_expect(not shadow.z_as_relative, "player ground shadow does not inherit actor depth")
		_expect_equal(
			shadow.z_index,
			TOWN_BASE.OUTDOOR_GROUND_SHADOW_Z_INDEX,
			"outdoor player shadow stays below map foreground occluders",
		)
		town.set("_active_interior_id", "cafe")
		town.call("_update_player_ground_shadow_depth")
		_expect_equal(
			shadow.z_index,
			TOWN_BASE.INTERIOR_GROUND_SHADOW_Z_INDEX,
			"indoor player shadow stays below furniture",
		)
		town.set("_active_interior_id", "")
		town.call("_update_player_ground_shadow_depth")
	await _test_player_collision_contact_filter(town)
	await _test_home_a_bedroom_corner_release(town)
	_test_bulletin_board_occluders_use_footpoint_activation(town)
	_test_foreground_slice_preserves_source_brightness()

	town.queue_free()
	await process_frame
	await process_frame
	_finish()


func _test_player_collision_contact_filter(town: Node) -> void:
	var player := town.get_node("Player") as CharacterBody2D
	player.position = Vector2(-2000.0, -2000.0)
	var wall := StaticBody2D.new()
	wall.name = "PlayerContactFilterTestWall"
	wall.position = player.position + Vector2(28.0, 0.0)
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_collision := CollisionShape2D.new()
	var wall_shape := RectangleShape2D.new()
	wall_shape.size = Vector2(20.0, 80.0)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	town.add_child(wall)
	await physics_frame

	town.call("_clear_player_blocking_normals")
	town.call("_remember_player_blocking_normal", Vector2.LEFT)
	var pressed_into_wall := town.call(
		"_filter_player_velocity_against_contacts",
		Vector2.RIGHT * 144.0,
	) as Vector2
	_expect(
		absf(pressed_into_wall.x) <= 0.001,
		"held input cannot restore velocity into the blocking wall",
	)
	var along_wall := town.call(
		"_filter_player_velocity_against_contacts",
		Vector2(144.0, 144.0),
	) as Vector2
	_expect(
		absf(along_wall.x) <= 0.001 and along_wall.y > 0.0,
		"diagonal input keeps its stable along-wall component",
	)
	wall.position.y -= 100.0
	await physics_frame
	var past_wall_corner := town.call(
		"_filter_player_velocity_against_contacts",
		Vector2.RIGHT * 144.0,
	) as Vector2
	_expect(
		past_wall_corner.x > 0.0,
		"clearing a wall corner releases its remembered blocking normal",
	)
	_expect_equal(
		(town.get("_player_blocking_normals") as Array).size(),
		0,
		"a cleared wall corner does not leave a stale collision contact",
	)

	wall.position.y += 100.0
	await physics_frame
	town.call("_remember_player_blocking_normal", Vector2.LEFT)
	var away_from_wall := town.call(
		"_filter_player_velocity_against_contacts",
		Vector2.LEFT * 144.0,
	) as Vector2
	_expect(
		away_from_wall.x < 0.0,
		"deliberate movement away from the wall releases the contact",
	)
	_expect_equal(
		(town.get("_player_blocking_normals") as Array).size(),
		0,
		"released collision contact does not affect later movement",
	)
	wall.queue_free()


func _test_home_a_bedroom_corner_release(town: Node) -> void:
	var player := town.get_node("Player") as CharacterBody2D
	var room: Node2D = await town.call("_prepare_interior_room", "home_a")
	_expect(room != null, "home template A exists for bedroom corner clearance")
	if room == null:
		return
	player.position = room.position + Vector2(-174.0, 180.0)
	await physics_frame
	town.call("_clear_player_blocking_normals")
	town.call("_remember_player_blocking_normal", Vector2.RIGHT)
	var against_partition := town.call(
		"_filter_player_velocity_against_contacts",
		Vector2.LEFT * 144.0,
	) as Vector2
	_expect(
		absf(against_partition.x) <= 0.001,
		"home A bedroom partition blocks movement while the avatar still touches it",
	)

	player.position = room.position + Vector2(-174.0, 240.0)
	await physics_frame
	var below_partition := town.call(
		"_filter_player_velocity_against_contacts",
		Vector2.LEFT * 144.0,
	) as Vector2
	_expect(
		below_partition.x < 0.0,
		"home A bedroom entrance releases left movement below the partition corner",
	)


func _test_bulletin_board_occluders_use_footpoint_activation(town: Node) -> void:
	for occluder_id in ["occ_089", "occ_090", "occ_091"]:
		var occluder := _find_descendant(town, occluder_id) as Polygon2D
		_expect(occluder != null, "%s exists in formal town runtime occlusion layer" % occluder_id)
		if occluder == null:
			continue
		_expect_equal(
			str(occluder.get_meta("activation_mode", "")),
			"foot_inside",
			"%s uses foot-point activation instead of global y-sort activation" % occluder_id
		)
		var activation_polygon: Variant = occluder.get_meta(
			"activation_polygon",
			PackedVector2Array(),
		)
		_expect(
			activation_polygon is PackedVector2Array
			and (activation_polygon as PackedVector2Array).size() >= 3,
			"%s has an explicit foot-point activation polygon" % occluder_id
		)


func _test_foreground_slice_preserves_source_brightness() -> void:
	var layer := RUNTIME_OCCLUSION_LAYER.new()
	var shader := layer.call("_subject_slice_shader") as Shader
	_expect(shader != null, "subject-scoped foreground slice builds its clipping shader")
	if shader == null:
		layer.free()
		return
	_expect(
		not shader.code.contains("texture(TEXTURE, UV) * COLOR"),
		"foreground slice does not multiply the map texture twice and darken it",
	)
	layer.free()


func _find_descendant(root_node: Node, node_name: String) -> Node:
	if root_node.name == node_name:
		return root_node
	for child in root_node.get_children():
		var found := _find_descendant(child, node_name)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])


func _finish() -> void:
	_prepare_audio_shutdown()
	if _failures.is_empty():
		print("TOWN_PLAYER_AVATAR_FOOTPOINT_OCCLUSION_PASS")
		call_deferred("_quit_after_cleanup", 0)
		return
	for failure in _failures:
		push_error(failure)
	print("TOWN_PLAYER_AVATAR_FOOTPOINT_OCCLUSION_FAIL")
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
