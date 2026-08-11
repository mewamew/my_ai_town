class_name TownAnnouncementTimeParser
extends RefCounted


const MINUTES_PER_DAY := 1440
const NUMERIC_CHARS := "0123456789零一二两三四五六七八九十"
const PERIOD_DEFAULT_HOURS := {
	"清晨": 6,
	"早晨": 8,
	"早上": 8,
	"上午": 9,
	"中午": 12,
	"下午": 14,
	"傍晚": 18,
	"晚上": 20,
	"夜晚": 20,
	"夜里": 22,
}


static func has_time_expression(text: String) -> bool:
	var normalized := text.strip_edges()
	if normalized.is_empty():
		return false
	if _match(normalized, "([0-9一二两三四五六七八九十]+)\\s*(分钟|小时)后") != null:
		return true
	if normalized.contains("半小时后"):
		return true
	if _clock_time(normalized).is_empty() == false:
		return true
	for cue: String in [
		"今天", "今晚", "明天", "明日", "明早", "明晚", "后天",
		"凌晨", "清晨", "早晨", "早上", "上午", "中午", "下午", "傍晚",
		"晚上", "夜晚", "夜里",
	]:
		if normalized.contains(cue):
			return true
	return _match(normalized, "第\\s*[0-9]+\\s*天") != null


static func parse(text: String, now_absolute_minute: int) -> Dictionary:
	var normalized := text.strip_edges()
	if normalized.is_empty() or now_absolute_minute < 0:
		return {}
	# 小镇只有“第 N 天”，没有现实日历的星期与月份基准。
	# 这类写法必须保持未解析，让界面提醒玩家改写，不能错当成今天。
	if _has_unsupported_calendar_day(normalized):
		return {}
	var relative := _relative_time(normalized, now_absolute_minute)
	if not relative.is_empty():
		return relative
	var day_start := now_absolute_minute - posmod(now_absolute_minute, MINUTES_PER_DAY)
	var target_day_start := day_start
	var explicit_day := false
	if normalized.contains("后天"):
		target_day_start += MINUTES_PER_DAY * 2
		explicit_day = true
	elif (
		normalized.contains("明天")
		or normalized.contains("明日")
		or normalized.contains("明早")
		or normalized.contains("明晚")
	):
		target_day_start += MINUTES_PER_DAY
		explicit_day = true
	elif normalized.contains("今天") or normalized.contains("今晚"):
		explicit_day = true
	else:
		var numbered_day := _match(normalized, "第\\s*([0-9]+)\\s*天")
		if numbered_day != null:
			var day_number := int(numbered_day.get_string(1))
			if day_number > 0:
				target_day_start = (day_number - 1) * MINUTES_PER_DAY
				explicit_day = true
	var clock := _clock_time(normalized)
	if clock.is_empty():
		clock = _period_default_time(normalized)
	if clock.is_empty():
		return {}
	var hour := int(clock.get("hour", -1))
	var minute := int(clock.get("minute", -1))
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return {}
	var due := target_day_start + hour * 60 + minute
	if due <= now_absolute_minute:
		# 没写“明天/后天”的过去时刻按无效处理，不能擅自把“下午三点”
		# 改成第二天；玩家重新发布时应写清日期。
		return {}
	var day := int(due / MINUTES_PER_DAY) + 1
	return {
		"scheduled_absolute_minute": due,
		"scheduled_time_label": "第%d天 %02d:%02d" % [day, hour, minute],
		"explicit_day": explicit_day,
	}


static func _has_unsupported_calendar_day(text: String) -> bool:
	return (
		text.contains("下周")
		or text.contains("上周")
		or text.contains("本周")
		or text.contains("这周")
		or text.contains("周末")
		or _match(text, "(周|星期|礼拜)[一二三四五六日天]") != null
		or _match(text, "[0-9一二两三四五六七八九十]+月") != null
		or _match(text, "[0-9一二两三四五六七八九十]+(号|日)") != null
	)


static func _relative_time(text: String, now_absolute_minute: int) -> Dictionary:
	var match_result := _match(
		text,
		"([0-9一二两三四五六七八九十]+)\\s*(分钟|小时)后",
	)
	if match_result == null:
		if text.contains("半小时后"):
			return _relative_result(now_absolute_minute, 30)
		return {}
	var amount := _number(String(match_result.get_string(1)))
	if amount <= 0:
		return {}
	var unit := String(match_result.get_string(2))
	return _relative_result(
		now_absolute_minute,
		amount * (60 if unit == "小时" else 1),
	)


static func _relative_result(now_absolute_minute: int, delta: int) -> Dictionary:
	var due := now_absolute_minute + delta
	var minute_of_day := posmod(due, MINUTES_PER_DAY)
	return {
		"scheduled_absolute_minute": due,
		"scheduled_time_label": "第%d天 %02d:%02d" % [
			int(due / MINUTES_PER_DAY) + 1,
			int(minute_of_day / 60),
			minute_of_day % 60,
		],
		"explicit_day": true,
	}


static func _clock_time(text: String) -> Dictionary:
	var colon := _match(text, "(^|[^0-9])([01]?[0-9]|2[0-3]):([0-5][0-9])([^0-9]|$)")
	if colon != null:
		return {
			"hour": int(colon.get_string(2)),
			"minute": int(colon.get_string(3)),
		}
	var point := _match(
		text,
		"(凌晨|清晨|早晨|早上|上午|中午|下午|傍晚|晚上|夜晚|夜里|今晚|明早|明晚)?\\s*([0-9一二两三四五六七八九十]+)\\s*[点时](半|([0-9一二两三四五六七八九十]+)\\s*分?)?",
	)
	if point == null:
		return {}
	# 防止无效小时被正则从数字尾部截断匹配，例如把“25点”误读成“5点”。
	var point_start := point.get_start()
	if point_start > 0 and NUMERIC_CHARS.contains(text.substr(point_start - 1, 1)):
		return {}
	var period := String(point.get_string(1))
	var hour := _number(String(point.get_string(2)))
	var minute := 0
	var minute_part := String(point.get_string(3))
	if minute_part == "半":
		minute = 30
	elif not String(point.get_string(4)).is_empty():
		minute = _number(String(point.get_string(4)))
	if period in ["下午", "傍晚", "晚上", "夜晚", "夜里", "今晚", "明晚"] and hour < 12:
		hour += 12
	elif period == "中午" and hour < 11:
		hour += 12
	elif period == "凌晨" and hour == 12:
		hour = 0
	return {"hour": hour, "minute": minute}


static func _period_default_time(text: String) -> Dictionary:
	for period: String in PERIOD_DEFAULT_HOURS:
		if text.contains(period):
			return {"hour": int(PERIOD_DEFAULT_HOURS[period]), "minute": 0}
	if text.contains("明早"):
		return {"hour": 8, "minute": 0}
	if text.contains("今晚") or text.contains("明晚"):
		return {"hour": 20, "minute": 0}
	return {}


static func _number(value: String) -> int:
	if value.is_valid_int():
		return int(value)
	var digits := {
		"零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
		"五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
	}
	if value == "十":
		return 10
	if value.contains("十"):
		var parts := value.split("十", false)
		var tens := 1
		var ones := 0
		if value.begins_with("十"):
			var suffix := value.substr(1)
			ones = int(digits.get(suffix, -1))
			if ones < 0:
				return -1
		else:
			tens = int(digits.get(String(parts[0]), -1))
			if tens < 0:
				return -1
			if parts.size() > 1:
				ones = int(digits.get(String(parts[1]), -1))
				if ones < 0:
					return -1
		return tens * 10 + ones
	return int(digits.get(value, -1))


static func _match(text: String, pattern: String) -> RegExMatch:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return null
	return regex.search(text)
