class_name InteriorOcclusionLoadTask
extends RefCounted

var _mutex := Mutex.new()
var _result: Dictionary = {}


func run(
	geometry: Dictionary,
	geometry_path: String,
	occlusion_path: String,
	shell_path: String,
) -> void:
	var validator := InteriorOcclusionManifest.new()
	validator.set_file_only_texture_validation(true)
	var result := validator.begin_load_staged(
		geometry,
		geometry_path,
		occlusion_path,
		shell_path,
	) as Dictionary
	var segments: Array[Dictionary] = []
	while result.get("ok") == true:
		var step := validator.validate_next_segment() as Dictionary
		if step.get("ok") != true:
			result = step
			break
		if step.get("segment") is Dictionary:
			segments.append(
				(step.get("segment") as Dictionary).duplicate(true),
			)
		if step.get("complete") == true:
			result = {"ok": true, "segments": segments}
			break
	if result.get("ok") == true:
		var images: Dictionary = {}
		for segment in segments:
			var texture_path := String(segment.get("foreground_texture_path"))
			var image := Image.new()
			if image.load(ProjectSettings.globalize_path(texture_path)) != OK:
				result = {
					"ok": false,
					"code": "TEXTURE_LOAD_FAILED",
					"error": "segment texture image could not be loaded: %s" % texture_path,
				}
				break
			images[texture_path] = image
		if result.get("ok") == true:
			result["images"] = images
	_mutex.lock()
	_result = result
	_mutex.unlock()


func take_result() -> Dictionary:
	_mutex.lock()
	var result := _result
	_result = {}
	_mutex.unlock()
	return result
