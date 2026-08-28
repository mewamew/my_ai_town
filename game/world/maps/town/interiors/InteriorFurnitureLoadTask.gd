class_name InteriorFurnitureLoadTask
extends RefCounted

const LIGHT_SIZE := 96
const LIGHT_CENTER := Vector2(47.5, 47.5)
const LIGHT_RADIUS := 48.0

var _mutex := Mutex.new()
var _result: Dictionary = {}


func run(manifest_path: String, layout_path: String) -> void:
	var errors := PackedStringArray()
	var manifest := _load_json(manifest_path)
	var layout := _load_json(layout_path)
	if manifest.is_empty():
		errors.append("家具 manifest 无法解析：%s" % manifest_path)
	if layout.is_empty():
		errors.append("家具布局无法解析：%s" % layout_path)
	var definitions: Dictionary = {}
	for record_value: Variant in manifest.get("assets", []) as Array:
		if not record_value is Dictionary:
			errors.append("家具 manifest 含有非法资产记录")
			continue
		var record := record_value as Dictionary
		var asset_id := str(record.get("asset_id", ""))
		var definition_path := _resource_path(
			str(record.get("definition_path", "")),
		)
		var definition := _load_json(definition_path)
		if asset_id.is_empty() or definition.is_empty():
			errors.append("家具定义缺失：%s" % asset_id)
			continue
		if str(definition.get("asset_id", "")) != asset_id:
			errors.append("%s 的定义 asset_id 不一致" % asset_id)
			continue
		definitions[asset_id] = definition
	var normalized_layout := layout.duplicate(true)
	var instances := (normalized_layout.get("instances", []) as Array)
	instances.sort_custom(
		func(left: Variant, right: Variant) -> bool:
			return str((left as Dictionary).get("instance_id", "")) < str(
				(right as Dictionary).get("instance_id", ""),
			)
	)
	var texture_paths: Array[String] = []
	var seen_textures: Dictionary = {}
	var requires_light_texture := false
	for instance_value: Variant in instances:
		if not instance_value is Dictionary:
			continue
		var instance := instance_value as Dictionary
		var definition := definitions.get(
			str(instance.get("asset_id", "")),
			{},
		) as Dictionary
		var direction := str(instance.get("direction", "down"))
		var sprite_path := str(
			(definition.get("visual_sprite", {}) as Dictionary).get(direction, ""),
		)
		if not sprite_path.is_empty() and not seen_textures.has(sprite_path):
			seen_textures[sprite_path] = true
			texture_paths.append(sprite_path)
		for effect_value: Variant in (
			definition.get("visual_effect_anchor", []) as Array
		):
			if (
				effect_value is Dictionary
				and str((effect_value as Dictionary).get("kind", "")) == "warm_light"
			):
				requires_light_texture = true
	var light_image := _build_light_image() if requires_light_texture else null
	_mutex.lock()
	_result = {
		"ok": errors.is_empty(),
		"errors": errors,
		"definitions": definitions,
		"layout": normalized_layout,
		"texture_paths": texture_paths,
		"light_image": light_image,
	}
	_mutex.unlock()


func take_result() -> Dictionary:
	_mutex.lock()
	var result := _result
	_result = {}
	_mutex.unlock()
	return result


func _load_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _resource_path(path: String) -> String:
	if path.begins_with("res://"):
		return path
	if path.begins_with("game/"):
		return "res://" + path.trim_prefix("game/")
	return path


func _build_light_image() -> Image:
	var image := Image.create_empty(
		LIGHT_SIZE,
		LIGHT_SIZE,
		false,
		Image.FORMAT_RGBA8,
	)
	for y in LIGHT_SIZE:
		for x in LIGHT_SIZE:
			var sample := Vector2(floori(x / 3) * 3 + 1, floori(y / 3) * 3 + 1)
			var normalized := clampf(
				sample.distance_to(LIGHT_CENTER) / LIGHT_RADIUS,
				0.0,
				1.0,
			)
			var alpha := pow(1.0 - normalized, 1.7)
			alpha = floorf(alpha * 8.0 + 0.5) / 8.0
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return image
