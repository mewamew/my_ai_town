class_name InteriorFurnitureRuntime
extends Node2D

signal layout_changed(snapshot: Dictionary)

const WORLD_SCALARS := preload(
	"res://world/data/town/TownWorldScalars.gd"
)
const GEOMETRY := preload(
	"res://world/maps/town/interiors/redesign_v2/common/InteriorAssetGeometry.gd"
)
const RUNTIME_OCCLUSION := preload(
	"res://world/runtime/MapRuntimeOcclusionLayer.gd"
)
const DIRECTIONS: Array[String] = ["down", "right", "up", "left"]
const GRID_SIZE := 32.0
const INVALID_CELL := Vector2i(2147483647, 2147483647)
# 家具定义的像素级重叠校验属于制作阶段。正式运行只需要读取已经烘焙好的
# occupied_cells 和方向贴图；再次把每个家具的源图读成 Image 会把整套家具
# 复制进 CPU 常驻内存，而且与画面没有关系。
const VALIDATE_ASSET_PIXELS_AT_RUNTIME := false

var _manifest_path := ""
var _layout_path := ""
var _definitions: Dictionary = {}
var _items: Array[Node2D] = []
var _debug_roots: Array[CanvasItem] = []
var _occlusion_layer: Node2D
var _errors := PackedStringArray()
var _collision_shape_count := 0
var _visual_effect_count := 0
var _ground_shadow_count := 0
var _debug_visible := false
var _layout_state: Dictionary = {}
var _pixel_light_texture: Texture2D


func configure(manifest_path: String, layout_path: String) -> bool:
	_clear_runtime()
	_manifest_path = manifest_path
	var manifest := _load_json(manifest_path)
	var layout := _load_json(layout_path)
	if manifest.is_empty() or layout.is_empty():
		return false
	# 住宅模板会由多个正式 home_xx 空间共享同一份资产目录，因此布局 room_id
	# 可以是具体住宅 ID，不要求与模板目录 ID 完全相同。
	_load_definitions(manifest)
	if not _errors.is_empty():
		return false
	var result := apply_layout(layout, false)
	if result.get("ok") != true:
		_errors = result.get("errors", PackedStringArray()) as PackedStringArray
		return false
	_layout_path = layout_path
	return true


func set_layout_path(layout_path: String) -> bool:
	if layout_path == _layout_path and is_instance_valid(_occlusion_layer):
		return true
	var layout := _read_json(layout_path)
	if layout.is_empty():
		return false
	var result := apply_layout(layout)
	if result.get("ok") != true:
		return false
	_layout_path = layout_path
	return true


func apply_layout(layout: Dictionary, emit_change := true) -> Dictionary:
	var errors := _validate_layout(layout)
	if not errors.is_empty():
		return {
			"ok": false,
			"changed": false,
			"errors": errors,
			"snapshot": get_layout_snapshot(),
		}
	var normalized := layout.duplicate(true)
	var instances := (normalized.get("instances", []) as Array).duplicate(true)
	instances.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str((left as Dictionary).get("instance_id", "")) < str(
			(right as Dictionary).get("instance_id", "")
		)
	)
	normalized["instances"] = instances
	if normalized == _layout_state and is_instance_valid(_occlusion_layer):
		return {
			"ok": true,
			"changed": false,
			"errors": PackedStringArray(),
			"snapshot": get_layout_snapshot(),
		}
	_clear_scene_nodes()
	_errors.clear()
	_occlusion_layer = RUNTIME_OCCLUSION.new() as Node2D
	_occlusion_layer.name = "FurnitureFootpointOcclusion"
	_occlusion_layer.set("z_step", 1)
	for instance_value in instances:
		_build_instance(instance_value as Dictionary)
	add_child(_occlusion_layer)
	_layout_state = normalized
	set_debug_visible(_debug_visible)
	var snapshot := get_layout_snapshot()
	if emit_change:
		layout_changed.emit(snapshot.duplicate(true))
	return {
		"ok": true,
		"changed": true,
		"errors": PackedStringArray(),
		"snapshot": snapshot,
	}


func upsert_instance(instance: Dictionary) -> Dictionary:
	var instance_id := str(instance.get("instance_id", "")).strip_edges()
	if instance_id.is_empty():
		return {
			"ok": false,
			"changed": false,
			"errors": PackedStringArray(["家具实例必须有稳定 instance_id"]),
			"snapshot": get_layout_snapshot(),
		}
	var next_layout := get_layout_snapshot()
	var instances := next_layout.get("instances", []) as Array
	var replaced := false
	for index in instances.size():
		if str((instances[index] as Dictionary).get("instance_id", "")) == instance_id:
			instances[index] = instance.duplicate(true)
			replaced = true
			break
	if not replaced:
		instances.append(instance.duplicate(true))
	return apply_layout(next_layout)


func remove_instance(instance_id: String) -> Dictionary:
	var normalized_id := instance_id.strip_edges()
	var next_layout := get_layout_snapshot()
	var instances := next_layout.get("instances", []) as Array
	for index in instances.size():
		if str((instances[index] as Dictionary).get("instance_id", "")) != normalized_id:
			continue
		instances.remove_at(index)
		return apply_layout(next_layout)
	return {
		"ok": true,
		"changed": false,
		"errors": PackedStringArray(),
		"snapshot": next_layout,
	}


func get_manifest_path() -> String:
	return _manifest_path


func get_layout_path() -> String:
	return _layout_path


func get_layout_snapshot() -> Dictionary:
	return _layout_state.duplicate(true)


func get_instance_count() -> int:
	return _items.size()


func get_collision_shape_count() -> int:
	return _collision_shape_count


func get_visual_effect_count() -> int:
	return _visual_effect_count


func get_ground_shadow_count() -> int:
	return _ground_shadow_count


func get_errors() -> PackedStringArray:
	return _errors.duplicate()


func get_occupied_room_cells() -> Array[Vector2i]:
	var occupied := {}
	for item in _items:
		var asset_id := str(item.get_meta("asset_id", ""))
		var direction := str(item.get_meta("direction", "down"))
		if not _definitions.has(asset_id):
			continue
		var definition := _definitions[asset_id] as Dictionary
		for polygon in GEOMETRY.rotated_ground_contact_polygons(definition, direction):
			var translated := PackedVector2Array()
			for point in polygon:
				translated.append(point + item.position)
			for cell in _cells_overlapping_polygon(translated):
				occupied[cell] = true
	var result: Array[Vector2i] = []
	for cell_value in occupied.keys():
		result.append(cell_value as Vector2i)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result


func create_agent_prop_projection(
	base_props: Array,
	identity: Dictionary,
	walkable_cells: Array,
) -> Dictionary:
	var errors := PackedStringArray()
	var walkable := {}
	for value: Variant in walkable_cells:
		if value is Array and (value as Array).size() == 2:
			walkable[Vector2i(int((value as Array)[0]), int((value as Array)[1]))] = true
	if walkable.is_empty():
		return {"ok": false, "errors": PackedStringArray(["室内当前导航网格为空"]), "props": []}
	var instances := {}
	for value: Variant in _layout_state.get("instances", []) as Array:
		var instance := value as Dictionary
		instances[str(instance.get("instance_id", ""))] = instance
	var projected := []
	var bound_instances := {}
	for value: Variant in base_props:
		var prop := value as Dictionary
		var interaction := prop.get("interaction", {}) as Dictionary
		var instance_id := str(interaction.get("instanceId", ""))
		if not instances.has(instance_id):
			continue
		bound_instances[instance_id] = true
		var next_prop := _project_agent_prop(
			prop,
			instances[instance_id] as Dictionary,
			str(interaction.get("anchorId", "")),
			walkable,
			float(interaction.get("maximumAnchorSnapPx", 64.0)),
			errors,
		)
		if not next_prop.is_empty():
			projected.append(next_prop)
	for instance_id_value: Variant in instances:
		var instance_id := str(instance_id_value)
		if bound_instances.has(instance_id):
			continue
		var instance := instances[instance_id_value] as Dictionary
		var semantic_value: Variant = instance.get("agent_prop")
		if not semantic_value is Dictionary:
			continue
		var semantic := semantic_value as Dictionary
		var actions_value: Variant = semantic.get("actions")
		if not actions_value is Array or (actions_value as Array).is_empty():
			continue
		var source_prop := {
			"name": str(semantic.get("name", "")),
			"placeName": str(identity.get("placeName", "")),
			"interaction": {
				"spaceId": str(identity.get("spaceId", "")),
				"regionId": str(identity.get("regionId", "")),
				"roomId": str(identity.get("roomId", "")),
				"instanceId": instance_id,
				"assetId": str(instance.get("asset_id", "")),
				"anchorId": str(semantic.get("anchor_id", "")),
			},
			"actions": (actions_value as Array).duplicate(true),
		}
		var next_prop := _project_agent_prop(
			source_prop,
			instance,
			str(semantic.get("anchor_id", "")),
			walkable,
			float(semantic.get("maximum_anchor_snap_px", 64.0)),
			errors,
		)
		if not next_prop.is_empty():
			projected.append(next_prop)
	projected.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str((left as Dictionary).get("name", "")) < str(
			(right as Dictionary).get("name", "")
		)
	)
	return {"ok": errors.is_empty(), "errors": errors, "props": projected}


func set_debug_visible(value: bool) -> void:
	_debug_visible = value
	for debug_root in _debug_roots:
		if is_instance_valid(debug_root):
			debug_root.visible = value


func _validate_layout(layout: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var instances_value: Variant = layout.get("instances")
	if not instances_value is Array:
		errors.append("家具布局 instances 必须为数组")
		return errors
	var seen_ids := {}
	for index in (instances_value as Array).size():
		var value: Variant = (instances_value as Array)[index]
		if not value is Dictionary:
			errors.append("家具布局 instances[%d] 必须为对象" % index)
			continue
		var instance := value as Dictionary
		var instance_id := str(instance.get("instance_id", "")).strip_edges()
		var asset_id := str(instance.get("asset_id", "")).strip_edges()
		var direction := str(instance.get("direction", "down"))
		if instance_id.is_empty():
			errors.append("家具布局 instances[%d] 缺少稳定 instance_id" % index)
		elif seen_ids.has(instance_id):
			errors.append("家具布局 instance_id 重复：%s" % instance_id)
		else:
			seen_ids[instance_id] = true
		if not _definitions.has(asset_id):
			errors.append("布局实例无法解析：%s/%s" % [instance_id, asset_id])
			continue
		if not DIRECTIONS.has(direction):
			errors.append("%s 的方向无效：%s" % [instance_id, direction])
		var position_value: Variant = instance.get("position_px")
		if not position_value is Array or (position_value as Array).size() != 2:
			errors.append("%s 缺少 position_px" % instance_id)
			continue
		if not _is_number((position_value as Array)[0]) or not _is_number((position_value as Array)[1]):
			errors.append("%s 的 position_px 必须是数值坐标" % instance_id)
		var definition := _definitions[asset_id] as Dictionary
		var sprite_path := str(
			(definition.get("visual_sprite", {}) as Dictionary).get(direction, "")
		)
		if _load_texture(sprite_path) == null:
			errors.append("%s 贴图无法加载：%s" % [instance_id, sprite_path])
		if GEOMETRY.ground_contact_collision_shapes(definition, direction).is_empty():
			errors.append("%s 没有连续碰撞形状" % instance_id)
	return errors


func _project_agent_prop(
	prop: Dictionary,
	instance: Dictionary,
	anchor_id: String,
	walkable: Dictionary,
	maximum_snap: float,
	errors: PackedStringArray,
) -> Dictionary:
	var prop_name := str(prop.get("name", ""))
	var asset_id := str(instance.get("asset_id", ""))
	if not _definitions.has(asset_id):
		errors.append("动态道具 %s 缺少家具定义：%s" % [prop_name, asset_id])
		return {}
	var definition := _definitions[asset_id] as Dictionary
	var source_anchor := {}
	for value: Variant in definition.get("interaction_anchor", []) as Array:
		var anchor := value as Dictionary
		if str(anchor.get("id", "")) == anchor_id:
			source_anchor = anchor
			break
	if source_anchor.is_empty():
		errors.append("动态道具 %s 缺少交互锚点：%s" % [prop_name, anchor_id])
		return {}
	var direction := str(instance.get("direction", "down"))
	var instance_position := _point(instance.get("position_px"))
	var source_position := instance_position + GEOMETRY.rotate_point(
		_point(source_anchor.get("position_px")),
		direction,
	)
	var interaction_position := source_position
	if _walkable_cell_for_point(interaction_position, walkable) == INVALID_CELL:
		interaction_position = _nearest_walkable_center(source_position, walkable)
		if (
			interaction_position == Vector2(INF, INF)
			or source_position.distance_to(interaction_position) > maximum_snap
		):
			errors.append("动态道具 %s 的交互锚点无法投影到相邻可行走格" % prop_name)
			return {}
	var result := prop.duplicate(true)
	var interaction := result.get("interaction", {}) as Dictionary
	interaction["position"] = _pair(interaction_position)
	interaction.erase("approachPolyline")
	interaction["instanceId"] = str(instance.get("instance_id", ""))
	interaction["assetId"] = asset_id
	interaction["anchorId"] = anchor_id
	interaction["anchorKind"] = str(source_anchor.get("kind", ""))
	interaction["actorFacing"] = GEOMETRY.rotate_facing(
		str(source_anchor.get("actor_facing", "")),
		direction,
	)
	interaction["sourceAnchorPosition"] = _pair(source_position)
	interaction["anchorSnappedToFloor"] = not source_position.is_equal_approx(interaction_position)
	interaction["instancePosition"] = _pair(instance_position)
	interaction["direction"] = direction
	result["interaction"] = interaction
	return result


func _walkable_cell_for_point(point: Vector2, walkable: Dictionary) -> Vector2i:
	var base := Vector2i(floori(point.x / GRID_SIZE), floori(point.y / GRID_SIZE))
	var candidates: Array[Vector2i] = []
	for offset_y in [-1, 0]:
		for offset_x in [-1, 0]:
			var cell := base + Vector2i(offset_x, offset_y)
			if not walkable.has(cell):
				continue
			var rect := Rect2(Vector2(cell) * GRID_SIZE, Vector2.ONE * GRID_SIZE)
			if rect.grow(0.01).has_point(point):
				candidates.append(cell)
	if candidates.is_empty():
		return INVALID_CELL
	candidates.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance := (_cell_center(left) - point).length_squared()
		var right_distance := (_cell_center(right) - point).length_squared()
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return left.y < right.y or (left.y == right.y and left.x < right.x)
	)
	return candidates[0]


func _nearest_walkable_center(point: Vector2, walkable: Dictionary) -> Vector2:
	var best := Vector2(INF, INF)
	var best_distance := INF
	for cell_value: Variant in walkable:
		var center := _cell_center(cell_value as Vector2i)
		var distance := center.distance_squared_to(point)
		if distance < best_distance:
			best = center
			best_distance = distance
		elif is_equal_approx(distance, best_distance) and (
			center.y < best.y or (is_equal_approx(center.y, best.y) and center.x < best.x)
		):
			best = center
	return best


func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GRID_SIZE


func _load_definitions(manifest: Dictionary) -> void:
	for record_value in manifest.get("assets", []) as Array:
		var record := record_value as Dictionary
		var asset_id := str(record.get("asset_id", ""))
		var definition_path := _to_resource_path(
			str(record.get("definition_path", ""))
		)
		var definition := _load_json(definition_path)
		if asset_id.is_empty() or definition.is_empty():
			_errors.append("家具定义缺失：%s" % asset_id)
			continue
		if str(definition.get("asset_id", "")) != asset_id:
			_errors.append("%s 的定义 asset_id 不一致" % asset_id)
			continue
		if VALIDATE_ASSET_PIXELS_AT_RUNTIME:
			for error in GEOMETRY.validate_definition(definition):
				_errors.append("%s：%s" % [asset_id, error])
			if not GEOMETRY.occupied_cells_match_ground_contact(definition):
				_errors.append("%s：occupied_cells 不是 ground_contact 的烘焙结果" % asset_id)
		_definitions[asset_id] = definition


func _build_instance(instance: Dictionary) -> void:
	var instance_id := str(instance.get("instance_id", ""))
	var asset_id := str(instance.get("asset_id", ""))
	var direction := str(instance.get("direction", "down"))
	if instance_id.is_empty() or not _definitions.has(asset_id):
		_errors.append("布局实例无法解析：%s/%s" % [instance_id, asset_id])
		return
	if not DIRECTIONS.has(direction):
		_errors.append("%s 的方向无效：%s" % [instance_id, direction])
		return
	var position_value := instance.get("position_px", []) as Array
	if position_value.size() != 2:
		_errors.append("%s 缺少 position_px" % instance_id)
		return
	var definition := _definitions[asset_id] as Dictionary
	var sprite_path := str(
		(definition.get("visual_sprite", {}) as Dictionary).get(direction, "")
	)
	var texture := _load_texture(sprite_path)
	if texture == null:
		_errors.append("%s 贴图无法加载：%s" % [instance_id, sprite_path])
		return
	var anchor := _point(
		(definition.get("visual_anchor", {}) as Dictionary).get(direction, [])
	)

	var item := Node2D.new()
	item.name = instance_id.to_pascal_case()
	item.position = _point(position_value)
	item.set_meta("instance_id", instance_id)
	item.set_meta("asset_id", asset_id)
	item.set_meta("direction", direction)
	add_child(item)
	_items.append(item)

	var body := StaticBody2D.new()
	body.name = "ContinuousGroundCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	item.add_child(body)
	var shape_index := 0
	for shape in GEOMETRY.ground_contact_collision_shapes(definition, direction):
		var collision := CollisionShape2D.new()
		collision.name = "GroundContact_%02d" % shape_index
		collision.shape = shape
		body.add_child(collision)
		shape_index += 1
		_collision_shape_count += 1
	if shape_index == 0:
		_errors.append("%s 没有连续碰撞形状" % instance_id)

	_build_ground_shadows(item, definition, direction)
	_build_debug(item, definition, direction)
	_build_occluder(item, definition, direction, texture, anchor)
	_build_visual_effects(item, definition, direction)


func _build_ground_shadows(
	item: Node2D,
	definition: Dictionary,
	direction: String,
) -> void:
	var shadow_root := Node2D.new()
	shadow_root.name = "GroundedFurnitureShadow"
	shadow_root.position = Vector2(5.0, 4.0)
	shadow_root.z_as_relative = false
	shadow_root.z_index = _base_depth_for(item.position.y) - 1
	item.add_child(shadow_root)
	for polygon in GEOMETRY.rotated_ground_contact_polygons(definition, direction):
		if polygon.size() < 3:
			continue
		var shadow := Polygon2D.new()
		shadow.polygon = polygon
		shadow.color = Color(0.07, 0.055, 0.04, 0.24)
		shadow_root.add_child(shadow)
		_ground_shadow_count += 1


func _build_visual_effects(
	item: Node2D,
	definition: Dictionary,
	direction: String,
) -> void:
	for effect_value: Variant in definition.get("visual_effect_anchor", []) as Array:
		if not effect_value is Dictionary:
			continue
		var effect := effect_value as Dictionary
		if str(effect.get("kind", "")) != "warm_light":
			continue
		var anchor := _point(effect.get("position_px", []))
		if bool(effect.get("rotate_with_direction", true)):
			anchor = GEOMETRY.rotate_point(anchor, direction)
		var light := PointLight2D.new()
		light.name = str(effect.get("id", "WarmLight")).to_pascal_case()
		light.position = anchor
		light.color = Color.from_string(
			str(effect.get("color", "#ffd58a")),
			Color(1.0, 0.78, 0.42),
		)
		light.energy = clampf(float(effect.get("energy", 0.46)), 0.0, 2.0)
		light.texture = _get_pixel_light_texture()
		light.texture_scale = maxf(float(effect.get("radius_px", 112.0)) / 48.0, 0.1)
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.shadow_enabled = false
		light.z_as_relative = false
		light.z_index = 95
		item.add_child(light)
		_visual_effect_count += 1


func _get_pixel_light_texture() -> Texture2D:
	if _pixel_light_texture != null:
		return _pixel_light_texture
	const SIZE := 96
	const CENTER := Vector2(47.5, 47.5)
	const RADIUS := 48.0
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			# 跟随正式 3px 像素簇，量化透明度，避免连续高清渐变。
			var sample := Vector2(floori(x / 3) * 3 + 1, floori(y / 3) * 3 + 1)
			var normalized := clampf(sample.distance_to(CENTER) / RADIUS, 0.0, 1.0)
			var alpha := pow(1.0 - normalized, 1.7)
			alpha = floorf(alpha * 8.0 + 0.5) / 8.0
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_pixel_light_texture = ImageTexture.create_from_image(image)
	return _pixel_light_texture


func _build_occluder(
	item: Node2D,
	definition: Dictionary,
	direction: String,
	texture: Texture2D,
	anchor: Vector2
) -> void:
	var size := texture.get_size()
	var visual_rect := Rect2(-anchor, size)
	var occluder := Polygon2D.new()
	occluder.name = "%sVisual" % item.name
	occluder.position = item.position
	occluder.polygon = _rect_polygon(visual_rect)
	occluder.uv = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		size,
		Vector2(0.0, size.y),
	])
	occluder.texture = texture
	occluder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	occluder.z_as_relative = false
	occluder.z_index = _base_depth_for(item.position.y)
	occluder.set_meta("base_z_index", occluder.z_index)
	occluder.set_meta("sort_mode", "foot_y")
	occluder.set_meta("baseline_y", 0.0)
	occluder.set_meta("activation_mode", "foot_inside")
	# The source image stays behind all people. MapRuntimeOcclusionLayer creates
	# a small foreground slice for each active foot point instead of moving the
	# whole furniture image above every resident in the room.
	occluder.set_meta("subject_scoped_occlusion", true)
	occluder.set_meta("subject_slice_half_extent", 48.0)
	occluder.set_meta(
		"activation_polygon",
		GEOMETRY.rotated_occlusion_polygon(definition, direction)
	)
	occluder.set_meta("source_instance_id", str(item.get_meta("instance_id", "")))
	_occlusion_layer.add_child(occluder)


func _build_debug(item: Node2D, definition: Dictionary, direction: String) -> void:
	var debug_root := Node2D.new()
	debug_root.name = "FurnitureGeometryDebug"
	debug_root.z_as_relative = false
	debug_root.z_index = 1300
	item.add_child(debug_root)
	_debug_roots.append(debug_root)
	for rect in GEOMETRY.occupied_cell_rects(definition, direction):
		var fill := Polygon2D.new()
		fill.polygon = _rect_polygon(rect)
		fill.color = Color(0.06, 0.80, 0.76, 0.10)
		debug_root.add_child(fill)
		var outline := Line2D.new()
		outline.points = _rect_polygon(rect)
		outline.closed = true
		outline.width = 1.0
		outline.default_color = Color(0.18, 0.92, 0.88, 0.72)
		debug_root.add_child(outline)
	for polygon in GEOMETRY.rotated_ground_contact_polygons(definition, direction):
		var fill := Polygon2D.new()
		fill.polygon = polygon
		fill.color = Color(0.96, 0.54, 0.10, 0.42)
		debug_root.add_child(fill)
		var outline := Line2D.new()
		outline.points = polygon
		outline.closed = true
		outline.width = 2.0
		outline.default_color = Color(1.0, 0.72, 0.20, 0.98)
		debug_root.add_child(outline)
	var occlusion_outline := Line2D.new()
	occlusion_outline.points = GEOMETRY.rotated_occlusion_polygon(definition, direction)
	occlusion_outline.closed = true
	occlusion_outline.width = 2.0
	occlusion_outline.default_color = Color(0.84, 0.36, 0.96, 0.92)
	debug_root.add_child(occlusion_outline)


func _cells_overlapping_polygon(polygon: PackedVector2Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if polygon.size() < 3:
		return result
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	var first := Vector2i(floori(bounds.position.x / GRID_SIZE), floori(bounds.position.y / GRID_SIZE))
	var last := Vector2i(
		ceili(bounds.end.x / GRID_SIZE) - 1,
		ceili(bounds.end.y / GRID_SIZE) - 1
	)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var top_left := Vector2(x, y) * GRID_SIZE
			var cell_polygon := PackedVector2Array([
				top_left,
				top_left + Vector2(GRID_SIZE, 0.0),
				top_left + Vector2(GRID_SIZE, GRID_SIZE),
				top_left + Vector2(0.0, GRID_SIZE),
			])
			for intersection in Geometry2D.intersect_polygons(polygon, cell_polygon):
				if _polygon_area(intersection) > 0.01:
					result.append(Vector2i(x, y))
					break
	return result


func _polygon_area(points: PackedVector2Array) -> float:
	return WORLD_SCALARS.polygon_area(points)


func _clear_scene_nodes() -> void:
	for child in get_children():
		child.free()
	_items.clear()
	_debug_roots.clear()
	_collision_shape_count = 0
	_visual_effect_count = 0
	_ground_shadow_count = 0
	_occlusion_layer = null


func _clear_runtime() -> void:
	_clear_scene_nodes()
	_definitions.clear()
	_errors.clear()
	_layout_state.clear()
	_layout_path = ""


func _base_depth_for(local_y: float) -> int:
	return clampi(12 + roundi((local_y + 256.0) / 16.0), 0, 90)


func _load_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		_errors.append("JSON 文件不存在：%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is not Dictionary:
		_errors.append("JSON 无法解析：%s" % path)
		return {}
	return parsed as Dictionary


func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


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


func _to_resource_path(path: String) -> String:
	if path.begins_with("res://"):
		return path
	if path.begins_with("game/"):
		return "res://" + path.trim_prefix("game/")
	return path


func _point(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() == 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO


func _pair(point: Vector2) -> Array:
	return [int(roundf(point.x)), int(roundf(point.y))]


func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
