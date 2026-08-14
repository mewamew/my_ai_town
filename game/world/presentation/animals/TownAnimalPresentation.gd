class_name TownAnimalPresentation
extends Node


signal animal_petted(result: Dictionary)
signal animal_touch_requested(animal_id: String)
signal resident_animal_interaction(result: Dictionary)

const ANIMAL := preload("res://world/presentation/animals/TownAnimal.gd")
const MAX_MAP_CATS := 3
const DYNAMIC_PROP_SYNC_SECONDS := 0.35
const DEFAULT_ANIMALS: Array[Dictionary] = [
	{
		"id": "cat_mikan",
		"name": "蜜柑",
		"species": "cat",
		"spawn": Vector2(3010.0, 2070.0),
		"roamRect": Rect2(2780.0, 1940.0, 760.0, 430.0),
		"speed": 66.0,
		"tint": Color.WHITE,
	},
	{
		"id": "cat_sumi",
		"name": "小墨",
		"species": "cat",
		"spawn": Vector2(1680.0, 2310.0),
		"roamRect": Rect2(1310.0, 2070.0, 780.0, 470.0),
		"speed": 62.0,
		"tint": Color("#b9c5d6"),
	},
	{
		"id": "cat_huajuan",
		"name": "花卷",
		"species": "cat",
		"spawn": Vector2(4740.0, 1510.0),
		"roamRect": Rect2(4470.0, 1200.0, 680.0, 590.0),
		"speed": 64.0,
		"tint": Color.WHITE,
	},
	{
		"id": "bird_lanling",
		"name": "蓝铃",
		"species": "bird",
		"spawn": Vector2(3260.0, 1860.0),
		"spawnSurface": "ground",
		"roamRect": Rect2(650.0, 320.0, 5550.0, 2900.0),
		"speed": 280.0,
		"tint": Color.WHITE,
		"colorSeed": 0,
		"landingPoints": [
			{"position": Vector2(3110.0, 900.0), "surface": "roof"},
			{"position": Vector2(4230.0, 850.0), "surface": "roof"},
			{"position": Vector2(1650.0, 1510.0), "surface": "roof"},
			{"position": Vector2(3260.0, 1860.0), "surface": "ground"},
			{"position": Vector2(3260.0, 2550.0), "surface": "ground"},
		],
	},
	{
		"id": "bird_xiaoyu",
		"name": "小羽",
		"species": "bird",
		"spawn": Vector2(3260.0, 2550.0),
		"spawnSurface": "ground",
		"roamRect": Rect2(650.0, 320.0, 5550.0, 2900.0),
		"speed": 270.0,
		"tint": Color("#f7d8a0"),
		"colorSeed": 1,
		"landingPoints": [
			{"position": Vector2(1700.0, 2780.0), "surface": "roof"},
			{"position": Vector2(2490.0, 440.0), "surface": "roof"},
			{"position": Vector2(880.0, 2900.0), "surface": "ground"},
			{"position": Vector2(3260.0, 2550.0), "surface": "ground"},
			{"position": Vector2(4010.0, 2210.0), "surface": "ground"},
		],
	},
	{
		"id": "bird_heihei",
		"name": "啾啾",
		"species": "bird",
		"spawn": Vector2(5190.0, 850.0),
		"spawnSurface": "ground",
		"roamRect": Rect2(650.0, 320.0, 5550.0, 2900.0),
		"speed": 292.0,
		"tint": Color("#c8e8ff"),
		"colorSeed": 2,
		"landingPoints": [
			{"position": Vector2(4800.0, 1710.0), "surface": "roof"},
			{"position": Vector2(4900.0, 2320.0), "surface": "roof"},
			{"position": Vector2(6000.0, 2780.0), "surface": "roof"},
			{"position": Vector2(5190.0, 850.0), "surface": "ground"},
			{"position": Vector2(5750.0, 3050.0), "surface": "ground"},
		],
	},
]

var _animals: Array[TownAnimal] = []
var _focused_animal: TownAnimal
var _player_position := Vector2.INF
var _can_interact := false
var _world_visible := true
var _simulation_paused := false
var _last_pet_result: Dictionary = {}
var _world: Object
var _resident_presentation: Node
var _dynamic_prop_sync_remaining := 0.0
var _last_animal_world_signatures: Dictionary = {}
var _last_dynamic_prop_signatures: Dictionary = {}
var _resident_cat_assignments: Dictionary = {}
var _last_resident_interaction: Dictionary = {}


func bind_character_root(character_root: Node2D) -> Dictionary:
	if character_root == null:
		return {
			"ok": false,
			"errorCode": "ANIMAL_CHARACTER_ROOT_REQUIRED",
			"errors": ["小动物表现层需要角色 Y 排序根节点"],
		}
	if not _animals.is_empty():
		return {
			"ok": true,
			"status": "already_bound",
			"animalCount": _animals.size(),
		}
	var errors: Array[String] = []
	var configured_cat_count := 0
	for spec: Dictionary in DEFAULT_ANIMALS:
		if String(spec.get("species", "")) == "cat":
			configured_cat_count += 1
			if configured_cat_count > MAX_MAP_CATS:
				errors.append("地图同时配置的猫不能超过 %d 只" % MAX_MAP_CATS)
				continue
		var animal := ANIMAL.new() as TownAnimal
		var configured := animal.configure(spec)
		if configured.get("ok") != true:
			for error_value: Variant in configured.get("errors", []) as Array:
				errors.append(String(error_value))
			animal.free()
			continue
		character_root.add_child(animal)
		animal.petted.connect(_on_animal_petted)
		animal.touch_requested.connect(_on_animal_touch_requested)
		_animals.append(animal)
	return {
		"ok": errors.is_empty(),
		"status": "bound" if errors.is_empty() else "partial",
		"animalCount": _animals.size(),
		"errors": errors,
	}


func bind_outdoor_navigation(runtime_data: Dictionary) -> Dictionary:
	var layers_value: Variant = runtime_data.get("layers")
	if layers_value is not Dictionary:
		return {
			"ok": false,
			"errorCode": "ANIMAL_OUTDOOR_NAVIGATION_REQUIRED",
			"errors": ["正式运行数据缺少有效的 layers 对象"],
		}
	var layers := layers_value as Dictionary
	var navigation_value: Variant = layers.get("navigation")
	if navigation_value is not Dictionary:
		return {
			"ok": false,
			"errorCode": "ANIMAL_OUTDOOR_NAVIGATION_REQUIRED",
			"errors": ["正式运行数据缺少有效的 navigation 对象"],
		}
	var navigation := navigation_value as Dictionary
	if navigation.is_empty():
		return {
			"ok": false,
			"errorCode": "ANIMAL_OUTDOOR_NAVIGATION_REQUIRED",
			"errors": ["正式运行数据的 navigation 对象不能为空"],
		}
	var collision_value: Variant = layers.get("collision")
	var collision_values := (
		collision_value as Array
		if collision_value is Array
		else []
	)
	var errors: Array[String] = []
	var bound_cat_count := 0
	var polygon_point_test_count := 0
	var region_bucket_count := 0
	var collision_shape_count := 0
	for animal: TownAnimal in _animals:
		if animal.species != "cat":
			continue
		var result := animal.configure_outdoor_navigation(
			navigation,
			collision_values,
		)
		if result.get("ok") == true:
			bound_cat_count += 1
			polygon_point_test_count += int(
				result.get("polygonPointTestCount", 0)
			)
			region_bucket_count += int(result.get("regionBucketCount", 0))
			collision_shape_count = maxi(
				collision_shape_count,
				int(result.get("collisionShapeCount", 0)),
			)
			continue
		errors.append("%s:%s" % [
			animal.animal_id,
			String(result.get(
				"errorCode",
				"CAT_NAVIGATION_BINDING_FAILED",
			)),
		])
	var binding_ok := (
		errors.is_empty()
		and bound_cat_count == _cat_count()
		and bound_cat_count > 0
	)
	return {
		"ok": binding_ok,
		"status": "bound" if binding_ok else "rejected",
		"errorCode": (
			""
			if binding_ok
			else "ANIMAL_OUTDOOR_NAVIGATION_REJECTED"
		),
		"boundCatCount": bound_cat_count,
		"polygonPointTestCount": polygon_point_test_count,
		"regionBucketCount": region_bucket_count,
		"collisionShapeCount": collision_shape_count,
		"errors": (
			[]
			if binding_ok
			else (
				errors
				if not errors.is_empty()
				else ["正式小镇没有可绑定导航的猫"]
			)
		),
	}


func bind_world_props(
	world: Object,
	resident_presentation: Node,
) -> Dictionary:
	if (
		world == null
		or not world.has_method("upsert_dynamic_prop")
		or not world.has_method("remove_dynamic_prop")
		or not world.has_method("upsert_animal_presence")
		or resident_presentation == null
		or not resident_presentation.has_method("get_body")
	):
		return {
			"ok": false,
			"errorCode": "ANIMAL_WORLD_PROP_BINDING_INVALID",
		}
	unbind_world_props()
	_world = world
	_resident_presentation = resident_presentation
	_last_animal_world_signatures.clear()
	_last_dynamic_prop_signatures.clear()
	if world.has_signal("resident_action_started"):
		world.connect("resident_action_started", _on_resident_action_started)
	set_process(true)
	_sync_cat_world_props()
	return {
		"ok": true,
		"status": "bound",
		"dynamicCatCount": _cat_count(),
		"maxActiveCats": MAX_MAP_CATS,
	}


func unbind_world_props() -> void:
	if (
		_world != null
		and _world.has_signal("resident_action_started")
		and _world.is_connected(
			"resident_action_started",
			_on_resident_action_started,
		)
	):
		_world.disconnect(
			"resident_action_started",
			_on_resident_action_started,
		)
	_world = null
	_resident_presentation = null
	_last_animal_world_signatures.clear()
	_last_dynamic_prop_signatures.clear()
	_resident_cat_assignments.clear()
	set_process(false)


func _process(delta: float) -> void:
	if _world == null:
		return
	if _world_visible and not _simulation_paused:
		_update_resident_cat_interactions()
	_dynamic_prop_sync_remaining -= maxf(delta, 0.0)
	if _dynamic_prop_sync_remaining <= 0.0:
		_dynamic_prop_sync_remaining = DYNAMIC_PROP_SYNC_SECONDS
		_sync_cat_world_props()


func set_runtime_state(
	player_position: Vector2,
	can_interact: bool,
	world_visible: bool,
	simulation_paused: bool,
) -> void:
	var player_position_changed := (
		can_interact
		and not player_position.is_equal_approx(_player_position)
	)
	if (
		can_interact == _can_interact
		and world_visible == _world_visible
		and simulation_paused == _simulation_paused
		and not player_position_changed
	):
		return
	_player_position = player_position
	_can_interact = can_interact
	_world_visible = world_visible
	_simulation_paused = simulation_paused
	_focused_animal = _nearest_pettable_animal() if can_interact else null
	for animal: TownAnimal in _animals:
		animal.set_runtime_state(
			world_visible,
			simulation_paused,
			animal == _focused_animal,
		)
	if _world != null and not world_visible:
		_cancel_resident_cat_assignments()


func try_pet_nearest(player_position: Vector2 = Vector2.INF) -> Dictionary:
	if player_position != Vector2.INF:
		_player_position = player_position
	if not _can_interact or not _world_visible or _simulation_paused:
		return {
			"ok": false,
			"errorCode": "ANIMAL_INTERACTION_UNAVAILABLE",
		}
	_focused_animal = _nearest_pettable_animal()
	if _focused_animal == null:
		return {
			"ok": false,
			"errorCode": "NO_NEARBY_ANIMAL",
		}
	var result := _focused_animal.begin_pet(_player_position)
	if result.get("ok") == true:
		_last_pet_result = result.duplicate(true)
	return result


func try_pet_animal(animal_id: String, player_position: Vector2) -> Dictionary:
	_player_position = player_position
	if not _can_interact or not _world_visible or _simulation_paused:
		return {"ok": false, "errorCode": "ANIMAL_INTERACTION_UNAVAILABLE"}
	for animal: TownAnimal in _animals:
		if animal.animal_id != animal_id:
			continue
		var result := animal.begin_pet(player_position)
		if result.get("ok") == true:
			_focused_animal = animal
			_last_pet_result = result.duplicate(true)
		return result
	return {"ok": false, "errorCode": "ANIMAL_NOT_FOUND"}


func get_snapshot() -> Dictionary:
	var animal_snapshots: Array[Dictionary] = []
	var species_counts := {"cat": 0, "dog": 0, "bird": 0}
	for animal: TownAnimal in _animals:
		var snapshot := animal.get_snapshot()
		animal_snapshots.append(snapshot)
		var animal_species := String(snapshot.get("species", ""))
		if species_counts.has(animal_species):
			species_counts[animal_species] = int(species_counts[animal_species]) + 1
	return {
		"animalCount": _animals.size(),
		"speciesCounts": species_counts,
		"activeCatCount": _active_cat_count(),
		"maxActiveCats": MAX_MAP_CATS,
		"dynamicWorldPropCount": (
			(_world.get_dynamic_prop_snapshot() as Array).size()
			if _world != null
			and _world.has_method("get_dynamic_prop_snapshot")
			else 0
		),
		"focusedAnimalId": (
			_focused_animal.animal_id
			if is_instance_valid(_focused_animal)
			else ""
		),
		"worldVisible": _world_visible,
		"simulationPaused": _simulation_paused,
		"canInteract": _can_interact,
		"lastPetResult": _last_pet_result.duplicate(true),
		"lastResidentInteraction": _last_resident_interaction.duplicate(true),
		"animals": animal_snapshots,
	}


func get_interaction_snapshot() -> Dictionary:
	# TownUiAdapter polls this at 10Hz while avatar mode is active. Keep the
	# poll independent from the full animal snapshot, which also walks every
	# animal, dynamic prop, and visual snapshot for diagnostics and save data.
	return {
		"focusedAnimalId": (
			_focused_animal.animal_id
			if is_instance_valid(_focused_animal)
			else ""
		),
		"canInteract": _can_interact,
	}


func _nearest_pettable_animal() -> TownAnimal:
	var nearest: TownAnimal
	var nearest_distance := INF
	for animal: TownAnimal in _animals:
		if not animal.is_within_interaction_range(_player_position):
			continue
		var distance := animal.distance_to_player(_player_position)
		if (
			distance <= animal.interaction_range
			and distance < nearest_distance
		):
			nearest = animal
			nearest_distance = distance
	return nearest


func _on_animal_petted(
	animal_id: String,
	display_name: String,
	species: String,
) -> void:
	var result := {
		"ok": true,
		"status": "petted",
		"animalId": animal_id,
		"displayName": display_name,
		"species": species,
	}
	animal_petted.emit(result)


func _on_animal_touch_requested(animal_id: String) -> void:
	animal_touch_requested.emit(animal_id)


func _sync_cat_world_props() -> void:
	if _world == null:
		return
	for animal: TownAnimal in _animals:
		var snapshot := animal.get_snapshot()
		var animal_state := {
			"animal_id": animal.animal_id,
			"display_name": animal.display_name,
			"species": animal.species,
			"exists": (
				true
				if animal.species == "bird"
				else animal.is_active_for_interaction()
			),
			"position": animal.position,
			"generation": int(snapshot.get("generation", 0)),
		}
		var animal_signature := [
			animal_state.get("display_name"),
			animal_state.get("species"),
			animal_state.get("exists"),
			animal_state.get("position"),
			animal_state.get("generation"),
		]
		if (
			_last_animal_world_signatures.get(animal.animal_id)
			!= animal_signature
		):
			var animal_result := _world.upsert_animal_presence(animal_state,) as Dictionary
			if animal_result.get("ok") == true:
				_last_animal_world_signatures[
					animal.animal_id
				] = animal_signature
		if animal.species != "cat":
			continue
		var prop_id := _dynamic_prop_id(animal.animal_id)
		var active := (
			_world_visible
			and not _simulation_paused
			and animal.is_active_for_interaction()
		)
		var prop_signature := (
			[true, animal.position]
			if active
			else [false]
		)
		if _last_dynamic_prop_signatures.get(prop_id) == prop_signature:
			continue
		var prop_result := _world.upsert_dynamic_prop(prop_id,
			"流浪猫·%s" % animal.display_name,
			animal.position,
			active,) as Dictionary
		if prop_result.get("ok") == true:
			_last_dynamic_prop_signatures[prop_id] = prop_signature


func _on_resident_action_started(
	resident_name: String,
	action: Dictionary,
) -> void:
	var prop_id := String(action.get("dynamicPropId", ""))
	if prop_id.is_empty() or String(action.get("verb", "")) != "摸摸":
		return
	var animal := _animal_for_dynamic_prop(prop_id)
	var resident_id := String(action.get("residentId", ""))
	if (
		animal == null
		or resident_id.is_empty()
		or not animal.reserve_for_resident(resident_id, 30.0)
	):
		return
	_resident_cat_assignments[resident_id] = {
		"animalId": animal.animal_id,
		"residentName": resident_name,
	}
	_sync_cat_world_props()


func _update_resident_cat_interactions() -> void:
	if _resident_presentation == null:
		return
	var completed: Array[String] = []
	for resident_id_value: Variant in _resident_cat_assignments:
		var resident_id := String(resident_id_value)
		var assignment := (
			_resident_cat_assignments.get(resident_id, {}) as Dictionary
		)
		var animal := _animal_by_id(
			String(assignment.get("animalId", "")),
		)
		var body := _resident_presentation.call("get_body", resident_id) as Node2D
		if (
			animal == null
			or body == null
			or not body.visible
			or not animal.is_active_for_interaction()
		):
			if animal != null:
				animal.release_resident_reservation(resident_id)
			completed.append(resident_id)
			continue
		if body.position.distance_to(animal.position) > animal.interaction_range:
			continue
		var result := animal.begin_resident_pet(
			resident_id,
			String(assignment.get("residentName", resident_id)),
			body.position,
		)
		if result.get("ok") == true:
			_last_resident_interaction = result.duplicate(true)
			resident_animal_interaction.emit(result.duplicate(true))
		completed.append(resident_id)
	for resident_id: String in completed:
		_resident_cat_assignments.erase(resident_id)


func _cancel_resident_cat_assignments() -> void:
	for resident_id_value: Variant in _resident_cat_assignments:
		var resident_id := String(resident_id_value)
		var assignment := (
			_resident_cat_assignments.get(resident_id, {}) as Dictionary
		)
		var animal := _animal_by_id(
			String(assignment.get("animalId", "")),
		)
		if animal != null:
			animal.release_resident_reservation(resident_id)
	_resident_cat_assignments.clear()


func _animal_by_id(animal_id: String) -> TownAnimal:
	for animal: TownAnimal in _animals:
		if animal.animal_id == animal_id:
			return animal
	return null


func _animal_for_dynamic_prop(prop_id: String) -> TownAnimal:
	for animal: TownAnimal in _animals:
		if _dynamic_prop_id(animal.animal_id) == prop_id:
			return animal
	return null


func _dynamic_prop_id(animal_id: String) -> String:
	return "dynamic_animal_%s" % animal_id


func _cat_count() -> int:
	var count := 0
	for animal: TownAnimal in _animals:
		if animal.species == "cat":
			count += 1
	return count


func _active_cat_count() -> int:
	var count := 0
	for animal: TownAnimal in _animals:
		if (
			animal.species == "cat"
			and animal.is_active_for_interaction()
		):
			count += 1
	return count
