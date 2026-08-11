extends RefCounted


const ISSUE_URL := "https://github.com/mewamew/my_ai_town/issues/new"


static func build_issue_url(overrides: Dictionary = {}) -> String:
	var runtime_info := collect_runtime_info()
	runtime_info.merge(overrides, true)
	var title := "[反馈] 请填写简短标题"
	var body := _build_issue_body(runtime_info)
	return "%s?title=%s&body=%s" % [
		ISSUE_URL,
		title.uri_encode(),
		body.uri_encode(),
	]


static func collect_runtime_info() -> Dictionary:
	var engine_version := Engine.get_version_info()
	return {
		"godotVersion": String(engine_version.get("string", "unknown")),
		"operatingSystem": "%s %s" % [OS.get_name(), OS.get_version()],
		"architecture": Engine.get_architecture_name(),
		"processor": OS.get_processor_name(),
		"gpuVendor": RenderingServer.get_video_adapter_vendor(),
		"gpuName": RenderingServer.get_video_adapter_name(),
		"graphicsApi": RenderingServer.get_video_adapter_api_version(),
		"renderingMethod": RenderingServer.get_current_rendering_method(),
		"renderingDriver": RenderingServer.get_current_rendering_driver_name(),
	}


static func _build_issue_body(runtime_info: Dictionary) -> String:
	return "\n".join(PackedStringArray([
		"## 反馈类型",
		"- [ ] Bug",
		"- [ ] 功能需求",
		"",
		"## 问题或需求描述",
		"请说明实际发生了什么，或希望增加什么功能。",
		"",
		"## 复现步骤（Bug）",
		"1. ",
		"2. ",
		"3. ",
		"",
		"## 期望结果",
		"请说明你原本期待看到什么。",
		"",
		"## 发生频率（Bug）",
		"- [ ] 每次都发生",
		"- [ ] 经常发生",
		"- [ ] 偶尔发生",
		"- [ ] 只发生过一次",
		"",
		"## 补充材料",
		"可以把截图、录屏、存档或相关日志拖到这里。",
		"",
		"## 运行环境（游戏已自动填写）",
	]) + _runtime_info_lines(runtime_info) + PackedStringArray([
		"",
		"> 提交前可以删除不愿公开的运行环境信息；请勿上传 API Key。",
	]))


static func _runtime_info_lines(runtime_info: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		"- Godot：%s" % String(runtime_info.get("godotVersion", "unknown")),
		"- 操作系统：%s" % String(runtime_info.get("operatingSystem", "unknown")),
		"- 系统架构：%s" % String(runtime_info.get("architecture", "unknown")),
		"- 处理器：%s" % String(runtime_info.get("processor", "unknown")),
		"- 显卡：%s %s" % [
			String(runtime_info.get("gpuVendor", "unknown")),
			String(runtime_info.get("gpuName", "unknown")),
		],
		"- 图形接口：%s" % String(runtime_info.get("graphicsApi", "unknown")),
		"- 渲染方式：%s / %s" % [
			String(runtime_info.get("renderingMethod", "unknown")),
			String(runtime_info.get("renderingDriver", "unknown")),
		],
	])
