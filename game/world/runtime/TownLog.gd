class_name TownLog
extends RefCounted
## 统一的运行时日志分隔器：
## - line(category, message) 在"日志类别切换"时自动补一个空行，
##   让 [AGENT] 的密集行为流水与 [CATMOUSE]/[WEREWOLF] 关键事件分块。
## - section(title) 打印游戏阶段横幅（天亮/大会/开票/胜负）。
## 注意：只在类静态变量里记上一次类别，不写文件、不改变日志内容本身；
## 文件落盘仍由 Godot --log-file 决定。

static var _last_category := ""


static func line(category: String, message: String) -> void:
	var normalized := category.strip_edges().to_upper()
	if normalized.is_empty():
		normalized = "INFO"
	if _last_category != "" and _last_category != normalized:
		print("")
	print("[%s] %s" % [normalized, message])
	_last_category = normalized


static func section(title: String) -> void:
	# 阶段横幅永远独占一段：前后各空一行，连续两个阶段也不会粘在一起。
	print("")
	print("============ %s ============" % title)
	print("")
	_last_category = ""


static func reset() -> void:
	_last_category = ""
