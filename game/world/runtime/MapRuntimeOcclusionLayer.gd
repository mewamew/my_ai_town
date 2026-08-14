# 正式地图前景遮挡层：人物脚点进入激活多边形后，遮挡图才会升到人物前方。
# 非全局脚点遮挡支持 subject_scoped_occlusion：完整底图留在人物后面，只把
# 触发遮挡的人物附近那一段贴图抬高，避免一块遮挡把其他人一起盖住。
extends Node2D

@export var subject_group: StringName = &"map_occlusion_subject"
@export_range(1, 32, 1) var z_step := 1

const DEFAULT_SUBJECT_SLICE_HALF_EXTENT := 48.0
const SUBJECT_SLICE_SHADER_CODE := """
shader_type canvas_item;

varying vec2 local_position;
uniform vec4 clip_rect;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	if (
		local_position.x < clip_rect.x
		|| local_position.y < clip_rect.y
		|| local_position.x > clip_rect.z
		|| local_position.y > clip_rect.w
	) {
		discard;
	}
	// Godot has already multiplied COLOR by TEXTURE before fragment() runs.
	// Sampling TEXTURE again would square every RGB channel and visibly darken
	// the foreground slice as soon as a character enters its activation area.
}
"""

var _occluders: Array[Polygon2D] = []
var _activation_bounds_by_instance_id: Dictionary = {}
var _subject_overlays: Dictionary = {}
var _subject_slice_shader_resource: Shader
var _last_subject_state: Dictionary = {}
var _subject_state_initialized := false
var _last_candidate_count := 0
var _last_polygon_point_test_count := 0
var _update_count := 0
var _unchanged_skip_count := 0


func _ready() -> void:
	_refresh_occluders()


func _process(_delta: float) -> void:
	# CanvasItem visibility does not stop Node processing. Town keeps inactive
	# interiors mounted, so reject their occlusion layers before scanning the
	# global subject group.
	if not is_visible_in_tree():
		return
	var subjects := _find_subjects()
	var subject_state := _subject_state(subjects)
	if _subject_state_initialized and subject_state == _last_subject_state:
		_unchanged_skip_count += 1
		return
	_last_subject_state = subject_state
	_subject_state_initialized = true
	# An empty visible-subject set must also restore every mask to its authored
	# depth; otherwise the last hidden/indoor actor can leave a foreground mask
	# stranded above the map.
	update_for_subjects(subjects)


func update_for_subject(subject: Node2D) -> void:
	update_for_subjects([subject])


func update_for_subjects(subjects: Array[Node2D]) -> void:
	_update_count += 1
	_last_candidate_count = 0
	_last_polygon_point_test_count = 0
	var valid_subjects: Array[Node2D] = []
	var behind_z := RenderingServer.CANVAS_ITEM_Z_MAX
	for subject in subjects:
		if not is_instance_valid(subject) or not subject.is_inside_tree():
			continue
		valid_subjects.append(subject)
		behind_z = mini(behind_z, subject.z_index - z_step)
	_prune_subject_overlays(valid_subjects)
	_hide_subject_overlays()
	for occluder in _occluders:
		if not is_instance_valid(occluder):
			continue
		var base_z := int(occluder.get_meta("base_z_index", occluder.z_index))
		if _is_subject_scoped_occluder(occluder):
			_update_subject_scoped_occluder(occluder, valid_subjects, behind_z)
			continue
		var resolved_behind_z := (
			base_z if valid_subjects.is_empty() else mini(base_z, behind_z)
		)
		var has_active_subject := false
		var front_z := base_z
		var should_draw_in_front := false
		var sort_mode := str(occluder.get_meta("sort_mode", ""))
		var baseline_y := float(occluder.get_meta("baseline_y", 0.0))
		for subject in valid_subjects:
			var subject_foot := occluder.to_local(subject.global_position)
			if not _activation_bounds_contains(occluder, subject_foot):
				continue
			_last_candidate_count += 1
			_last_polygon_point_test_count += 1
			if not _is_foot_point_active(occluder, subject_foot):
				continue
			has_active_subject = true
			front_z = maxi(front_z, subject.z_index + z_step)
			if sort_mode == "foot_y" and subject_foot.y < baseline_y:
				should_draw_in_front = true
		if not has_active_subject:
			# 未进入遮挡区时必须明确放到人物后面，不能依赖同层节点的绘制顺序。
			if occluder.z_index != resolved_behind_z:
				occluder.z_index = resolved_behind_z
			continue
		var next_z := base_z
		match sort_mode:
			"always_front":
				next_z = front_z
			"foot_y":
				next_z = front_z if should_draw_in_front else resolved_behind_z
			_:
				next_z = base_z
		if occluder.z_index != next_z:
			occluder.z_index = next_z


func _update_subject_scoped_occluder(
	occluder: Polygon2D,
	valid_subjects: Array[Node2D],
	behind_z: int,
) -> void:
	# The full furniture image is the background layer. It must never be moved in
	# front of every resident just because one resident entered the activation
	# polygon.
	var base_z := int(occluder.get_meta("base_z_index", occluder.z_index))
	var resolved_behind_z := base_z if valid_subjects.is_empty() else mini(base_z, behind_z)
	if occluder.z_index != resolved_behind_z:
		occluder.z_index = resolved_behind_z
	var sort_mode := str(occluder.get_meta("sort_mode", ""))
	var baseline_y := float(occluder.get_meta("baseline_y", 0.0))
	for subject in valid_subjects:
		var subject_foot := occluder.to_local(subject.global_position)
		if not _activation_bounds_contains(occluder, subject_foot):
			continue
		_last_candidate_count += 1
		_last_polygon_point_test_count += 1
		if not _is_foot_point_active(occluder, subject_foot):
			continue
		if sort_mode == "foot_y" and subject_foot.y >= baseline_y:
			continue
		if sort_mode != "foot_y" and sort_mode != "always_front":
			continue
		var overlay := _subject_overlay_for(occluder, subject, subject_foot)
		if not is_instance_valid(overlay):
			continue
		overlay.visible = true
		overlay.z_index = _z_index_with_offset(subject.z_index, z_step)
		overlay.modulate = occluder.modulate


func _subject_overlay_for(
	occluder: Polygon2D,
	subject: Node2D,
	subject_foot: Vector2,
) -> Polygon2D:
	var key := "%d:%d" % [occluder.get_instance_id(), subject.get_instance_id()]
	var overlay := _subject_overlays.get(key) as Polygon2D
	if not is_instance_valid(overlay):
		overlay = Polygon2D.new()
		overlay.name = "%sSubjectOverlay_%d" % [occluder.name, subject.get_instance_id()]
		overlay.texture_filter = occluder.texture_filter
		overlay.texture = occluder.texture
		overlay.polygon = occluder.polygon
		overlay.uv = occluder.uv
		overlay.color = occluder.color
		overlay.z_as_relative = false
		overlay.set_meta("subject_overlay", true)
		var material := ShaderMaterial.new()
		material.shader = _subject_slice_shader()
		overlay.material = material
		add_child(overlay)
		_subject_overlays[key] = overlay
	var slice := _subject_slice_rect(occluder, subject_foot)
	if not slice.has_area():
		overlay.visible = false
		return overlay
	overlay.position = occluder.position
	var material := overlay.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter(
			"clip_rect",
			Vector4(slice.position.x, slice.position.y, slice.end.x, slice.end.y),
		)
	return overlay


func _subject_slice_rect(occluder: Polygon2D, subject_foot: Vector2) -> Rect2:
	var source_bounds := _polygon_bounds(occluder.polygon)
	if not source_bounds.has_area():
		return Rect2()
	var half_extent := maxf(
		float(occluder.get_meta(
			"subject_slice_half_extent",
			DEFAULT_SUBJECT_SLICE_HALF_EXTENT,
		)),
		1.0,
	)
	var horizontal := source_bounds.size.x >= source_bounds.size.y
	var slice := source_bounds
	if horizontal:
		var center_x := clampf(
			subject_foot.x,
			source_bounds.position.x,
			source_bounds.end.x,
		)
		slice.position.x = center_x - half_extent
		slice.size.x = half_extent * 2.0
	else:
		var center_y := clampf(
			subject_foot.y,
			source_bounds.position.y,
			source_bounds.end.y,
		)
		slice.position.y = center_y - half_extent
		slice.size.y = half_extent * 2.0
	return _intersection_rect(source_bounds, slice)


func _intersection_rect(first: Rect2, second: Rect2) -> Rect2:
	var left := maxf(first.position.x, second.position.x)
	var top := maxf(first.position.y, second.position.y)
	var right := minf(first.end.x, second.end.x)
	var bottom := minf(first.end.y, second.end.y)
	return Rect2(left, top, right - left, bottom - top) if right > left and bottom > top else Rect2()


func _z_index_with_offset(z_index: int, offset: int) -> int:
	return clampi(
		z_index + offset,
		RenderingServer.CANVAS_ITEM_Z_MIN,
		RenderingServer.CANVAS_ITEM_Z_MAX,
	)


func _subject_slice_shader() -> Shader:
	if _subject_slice_shader_resource == null:
		_subject_slice_shader_resource = Shader.new()
		_subject_slice_shader_resource.code = SUBJECT_SLICE_SHADER_CODE
	return _subject_slice_shader_resource


func _is_subject_scoped_occluder(occluder: Polygon2D) -> bool:
	if bool(occluder.get_meta("subject_scoped_occlusion", false)):
		return true
	return str(occluder.get_meta("activation_mode", "foot_inside")) != "global"


func _hide_subject_overlays() -> void:
	for overlay_value: Variant in _subject_overlays.values():
		var overlay := overlay_value as Polygon2D
		if is_instance_valid(overlay):
			overlay.visible = false


func _prune_subject_overlays(subjects: Array[Node2D]) -> void:
	# ResidentCharacterBody instances are recreated when a resident changes
	# space or presentation identity. Keep overlays only for subjects that are
	# still in the current map subject set; otherwise every recreation would
	# leave a Polygon2D + ShaderMaterial child behind indefinitely.
	var active_subject_ids := {}
	for subject in subjects:
		if is_instance_valid(subject) and subject.is_inside_tree():
			active_subject_ids[subject.get_instance_id()] = true
	for key_value: Variant in _subject_overlays.keys():
		var key := String(key_value)
		var separator := key.rfind(":")
		var overlay := _subject_overlays.get(key_value) as Polygon2D
		var subject_id := -1
		if separator >= 0:
			subject_id = int(key.substr(separator + 1))
		if (
			separator < 0
			or not active_subject_ids.has(subject_id)
			or not is_instance_valid(overlay)
		):
			if is_instance_valid(overlay):
				overlay.free()
			_subject_overlays.erase(key_value)


func get_performance_snapshot() -> Dictionary:
	return {
		"occluderCount": _occluders.size(),
		"candidateCount": _last_candidate_count,
		"polygonPointTestCount": _last_polygon_point_test_count,
		"updateCount": _update_count,
		"unchangedSkipCount": _unchanged_skip_count,
		"subjectOverlayCount": _subject_overlays.size(),
	}


func _is_foot_point_active(occluder: Polygon2D, local_foot_point: Vector2) -> bool:
	# 少数确实需要永久前置的特效仍可显式声明 global；正式地图遮罩默认都按脚点触发。
	if str(occluder.get_meta("activation_mode", "foot_inside")) == "global":
		return true
	var activation_polygon := _activation_polygon_for(occluder)
	return (
		activation_polygon.size() >= 3
		and Geometry2D.is_point_in_polygon(local_foot_point, activation_polygon)
	)


func _activation_bounds_contains(
	occluder: Polygon2D,
	local_foot_point: Vector2,
) -> bool:
	if str(occluder.get_meta("activation_mode", "foot_inside")) == "global":
		return true
	var instance_id := occluder.get_instance_id()
	if not _activation_bounds_by_instance_id.has(instance_id):
		_activation_bounds_by_instance_id[instance_id] = (
			_polygon_bounds(_activation_polygon_for(occluder))
		)
	var bounds := (
		_activation_bounds_by_instance_id.get(instance_id, Rect2()) as Rect2
	)
	return bounds.has_area() and bounds.has_point(local_foot_point)


func _activation_polygon_for(occluder: Polygon2D) -> PackedVector2Array:
	# 视觉裁切形状与触发形状可以分开。未单独配置时，沿用当前紫色遮罩形状。
	var value: Variant = occluder.get_meta("activation_polygon", occluder.polygon)
	if value is PackedVector2Array:
		return value as PackedVector2Array
	if value is Array:
		var points := PackedVector2Array()
		for point_value in value as Array:
			if point_value is Vector2:
				points.append(point_value as Vector2)
		return points
	return occluder.polygon


func _find_subjects() -> Array[Node2D]:
	var subjects: Array[Node2D] = []
	for candidate in get_tree().get_nodes_in_group(subject_group):
		if (
			candidate is Node2D
			and (candidate as Node2D).is_visible_in_tree()
		):
			subjects.append(candidate as Node2D)
	return subjects


func _refresh_occluders() -> void:
	_clear_subject_overlays()
	_occluders.clear()
	_activation_bounds_by_instance_id.clear()
	_last_subject_state.clear()
	_subject_state_initialized = false
	for child in get_children():
		if child is Polygon2D:
			var occluder := child as Polygon2D
			_occluders.append(occluder)
			_activation_bounds_by_instance_id[
				occluder.get_instance_id()
			] = _polygon_bounds(_activation_polygon_for(occluder))


func _subject_state(subjects: Array[Node2D]) -> Dictionary:
	var state: Dictionary = {}
	for subject in subjects:
		if not is_instance_valid(subject) or not subject.is_inside_tree():
			continue
		state[subject.get_instance_id()] = [
			subject.global_position,
			subject.z_index,
		]
	return state


func _clear_subject_overlays() -> void:
	for overlay_value: Variant in _subject_overlays.values():
		var overlay := overlay_value as Node
		if is_instance_valid(overlay):
			overlay.free()
	_subject_overlays.clear()


func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum).grow(0.001)
