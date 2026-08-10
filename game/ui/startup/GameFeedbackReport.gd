extends RefCounted


const FEEDBACK_URL := "https://github.com/mewamew/my_ai_town/issues/new"


static func build_url() -> String:
	var version := String(ProjectSettings.get_setting("application/config/version", "unknown"))
	var channel := String(ProjectSettings.get_setting("application/config/channel", "release"))
	var version_label := "v%s-%s" % [version, channel]
	var godot_info := Engine.get_version_info()
	var godot_version := "%s.%s.%s" % [
		godot_info.get("major", "?"),
		godot_info.get("minor", "?"),
		godot_info.get("status", "unknown"),
	]
	var os_name := OS.get_name()
	var os_version := _runtime_call_string(OS, "get_version", "unknown")
	var architecture := _runtime_call_string(Engine, "get_architecture_name", "unknown")
	if architecture == "unknown":
		architecture = OS.get_environment("PROCESSOR_ARCHITEW6432")
		if architecture.is_empty():
			architecture = OS.get_environment("PROCESSOR_ARCHITECTURE")
		if architecture.is_empty():
			architecture = "unknown"
	var gpu_vendor := _runtime_call_string(RenderingServer, "get_video_adapter_vendor", "unknown")
	var gpu_name := _runtime_call_string(RenderingServer, "get_video_adapter_name", "unknown")
	var gpu_api_version := _runtime_call_string(RenderingServer, "get_video_adapter_api_version", "")
	var gpu_driver := _runtime_call_string(
		RenderingServer,
		"get_current_rendering_driver_name",
		"",
	)
	var gpu_api := _format_gpu_api(gpu_driver, RenderingServer.get_current_rendering_method())
	if not gpu_api_version.is_empty():
		gpu_api += " " + gpu_api_version
	var memory_info: Variant = (
		OS.call("get_memory_info") if OS.has_method("get_memory_info") else {}
	)
	var system_memory_text := "unknown"
	if memory_info is Dictionary:
		system_memory_text = _format_memory(float((memory_info as Dictionary).get("physical", 0.0)))
	var video_memory_text := _get_video_memory_text(
		architecture,
		gpu_vendor,
		gpu_name,
	)
	var body := """## 环境信息
- 游戏版本：%s
- Godot 版本：%s
- 操作系统：%s (%s)
- 架构：%s
- GPU：%s / %s
- 内存：%s
- 显存：%s

## 问题描述
<!-- 请在这里描述你遇到的问题 -->

## 复现步骤
1.
2.
3.

## 预期行为
<!-- 你觉得应该发生什么 -->

## 截图/日志
<!-- 如果可以，请附上截图或日志 -->""" % [
		version_label,
		godot_version,
		os_name,
		os_version,
		architecture,
		gpu_name if gpu_vendor.is_empty() else gpu_vendor + " " + gpu_name,
		gpu_api,
		system_memory_text,
		video_memory_text,
	]
	return "%s?body=%s" % [FEEDBACK_URL, body.uri_encode()]


static func _runtime_call_string(
	object: Object,
	method_name: String,
	fallback: String,
) -> String:
	if not object.has_method(method_name):
		return fallback
	var value: Variant = object.call(method_name)
	return fallback if value == null or String(value).is_empty() else String(value)


static func _runtime_call_number(
	object: Object,
	method_name: String,
	fallback: float,
) -> float:
	if not object.has_method(method_name):
		return fallback
	var value: Variant = object.call(method_name)
	return float(value) if value is int or value is float else fallback


static func _get_video_memory_bytes() -> float:
	var rendering_server_value := _runtime_call_number(
		RenderingServer,
		"get_video_adapter_memory",
		0.0,
	)
	if rendering_server_value > 0.0:
		return rendering_server_value
	if OS.get_name() != "Windows":
		return 0.0
	var command := (
		"$values = Get-ItemProperty -Path "
		+ "'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Video\\*\\0000' "
		+ "-Name 'HardwareInformation.qwMemorySize' -ErrorAction SilentlyContinue "
		+ "| ForEach-Object { $_.'HardwareInformation.qwMemorySize' }; "
		+ "($values | Measure-Object -Maximum).Maximum"
	)
	var output: Array[String] = []
	var exit_code := OS.execute(
		"powershell.exe",
		PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", command]),
		output,
		true,
	)
	if exit_code != 0 or output.is_empty():
		return 0.0
	return float(output[0].strip_edges().to_int())


static func _get_video_memory_text(
	architecture: String,
	gpu_vendor: String,
	gpu_name: String,
) -> String:
	var bytes := _get_video_memory_bytes()
	if bytes > 0.0:
		return _format_memory(bytes)
	if OS.get_name() != "macOS":
		return "unknown"
	var mac_video_memory := _get_macos_video_memory_text()
	if not mac_video_memory.is_empty():
		return mac_video_memory
	var apple_gpu := (architecture + " " + gpu_vendor + " " + gpu_name).to_lower()
	if apple_gpu.contains("arm64") or apple_gpu.contains("apple"):
		return "共享系统内存"
	return "unknown"


static func _get_macos_video_memory_text() -> String:
	var output: Array[String] = []
	var exit_code := OS.execute(
		"/usr/sbin/system_profiler",
		PackedStringArray(["SPDisplaysDataType", "-json"]),
		output,
		true,
	)
	if exit_code != 0 or output.is_empty():
		return ""
	var parsed: Variant = JSON.parse_string(output[0])
	return _find_macos_memory_value(parsed)


static func _find_macos_memory_value(value: Variant) -> String:
	if value is Dictionary:
		var dictionary := value as Dictionary
		for key: String in ["spdisplays_vram", "spdisplays_vram_nvidia", "spdisplays_vram_amd"]:
			var candidate := String(dictionary.get(key, ""))
			if candidate.contains("GB") or candidate.contains("MB"):
				return candidate
		for child: Variant in dictionary.values():
			var nested := _find_macos_memory_value(child)
			if not nested.is_empty():
				return nested
	elif value is Array:
		for child: Variant in value:
			var nested := _find_macos_memory_value(child)
			if not nested.is_empty():
				return nested
	return ""


static func _format_gpu_api(driver: String, rendering_method: String) -> String:
	match driver.to_lower():
		"metal":
			return "Metal"
		"vulkan", "moltenvk":
			return "Vulkan"
		"opengl3", "opengl3_angle":
			return "OpenGL"
	match rendering_method:
		"forward_plus", "mobile":
			return "Vulkan"
		"gl_compatibility":
			return "OpenGL"
	return driver if not driver.is_empty() else rendering_method


static func _format_memory(bytes: float) -> String:
	if bytes <= 0.0:
		return "unknown"
	return "%d GB" % maxi(1, roundi(bytes / 1073741824.0))
