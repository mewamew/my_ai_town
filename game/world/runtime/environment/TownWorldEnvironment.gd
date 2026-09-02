class_name TownWorldEnvironment
extends RefCounted


const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const DEFAULT_CONFIG_PATH := "res://world/runtime/environment/town_environment.json"
const MINUTES_PER_DAY := 1440
const MAX_SAFE_DAY := 6254999482459
const TIME_ACCUMULATION_EPSILON := 0.000000000001
const WEATHER_TYPES := ["晴天", "阴天", "小雨", "中雨", "大雨", "雷暴", "下雪"]
const NATURAL_WEATHER_CHECK_MIN_MINUTES := 45
const NATURAL_WEATHER_CHECK_MAX_MINUTES := 90
const MANUAL_CYCLE_CLOCKS := ["05:30", "09:30", "12:30", "15:30", "18:30", "22:30"]
const PERIOD_BOUNDARIES := [
	["夜里", 0],
	["清晨", 300],
	["上午", 480],
	["中午", 720],
	["下午", 840],
	["傍晚", 1080],
	["夜里", 1260],
]
const WEATHER_TRANSITIONS := {
	"晴天": {"晴天": 70, "阴天": 20, "小雨": 7, "中雨": 2, "大雨": 0, "雷暴": 1, "下雪": 0},
	"阴天": {"晴天": 25, "阴天": 45, "小雨": 15, "中雨": 7, "大雨": 4, "雷暴": 2, "下雪": 2},
	"小雨": {"晴天": 10, "阴天": 25, "小雨": 38, "中雨": 18, "大雨": 5, "雷暴": 3, "下雪": 1},
	"中雨": {"晴天": 5, "阴天": 18, "小雨": 25, "中雨": 32, "大雨": 14, "雷暴": 6, "下雪": 0},
	"大雨": {"晴天": 4, "阴天": 16, "小雨": 22, "中雨": 24, "大雨": 24, "雷暴": 10, "下雪": 0},
	"雷暴": {"晴天": 5, "阴天": 20, "小雨": 20, "中雨": 20, "大雨": 25, "雷暴": 10, "下雪": 0},
	"下雪": {"晴天": 10, "阴天": 25, "小雨": 5, "中雨": 0, "大雨": 0, "雷暴": 0, "下雪": 60},
}

var _config: Dictionary = {}
var _errors: Array[String] = []
var _day := 1
var _minute_of_day := 0
var _weather := "晴天"
var _forced_weather := ""
var _real_second_accumulator := 0.0
var _event_sequence := 0
var _next_natural_weather_check_absolute_minute := 0
var _rng := RandomNumberGenerator.new()
var _forced_weather_rolls: Array[float] = []


func _init(config_path: String = DEFAULT_CONFIG_PATH) -> void:
	_config = _read_json(config_path)
	_errors = _validate_config(_config)


func get_errors() -> Array[String]:
	return _errors.duplicate()


func start(
	day: Variant,
	clock: Variant,
	weather: Variant,
	random_seed: Variant = 1,
) -> Dictionary:
	if not _errors.is_empty():
		return {"ok": false, "errors": _errors.duplicate()}
	var time_parts := _parse_clock(clock as String) if clock is String else {}
	var errors: Array[String] = []
	if not _is_valid_day(day):
		errors.append("世界天数必须为不溢出绝对分钟的正整数")
	if not clock is String or time_parts.is_empty():
		errors.append("世界时钟必须是 HH:MM")
	if not weather is String or not _weather_types().has(weather as String):
		errors.append("初始天气不是合法天气：%s" % [weather])
	if typeof(random_seed) != TYPE_INT:
		errors.append("天气随机种子必须为整数")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	_day = int(day)
	_minute_of_day = int(time_parts["hour"]) * 60 + int(time_parts["minute"])
	_weather = weather as String
	_real_second_accumulator = 0.0
	_event_sequence = 0
	_forced_weather_rolls.clear()
	_rng.seed = int(random_seed)
	_schedule_next_natural_weather_check()
	return {"ok": true, "time": get_time(), "weather": _weather}


func advance(real_seconds: Variant) -> Dictionary:
	var result := {
		"minutesAdvanced": 0,
		"minuteTicks": [],
		"periodChanges": [],
		"events": [],
	}
	if typeof(real_seconds) not in [TYPE_INT, TYPE_FLOAT] or not _errors.is_empty():
		return result
	var elapsed_seconds := float(real_seconds)
	if not is_finite(elapsed_seconds) or elapsed_seconds <= 0.0:
		return result
	_real_second_accumulator += elapsed_seconds
	var seconds_per_minute := float((_config.get("time", {}) as Dictionary).get(
		"realSecondsPerGameMinute",
		1.0,
	))
	while (
		_real_second_accumulator > seconds_per_minute
		or absf(_real_second_accumulator - seconds_per_minute) <= TIME_ACCUMULATION_EPSILON
	):
		if _day == MAX_SAFE_DAY and _minute_of_day == MINUTES_PER_DAY - 1:
			_real_second_accumulator = 0.0
			break
		_real_second_accumulator -= seconds_per_minute
		if absf(_real_second_accumulator) <= TIME_ACCUMULATION_EPSILON:
			_real_second_accumulator = 0.0
		var previous_period := period_for_minute(_minute_of_day)
		_minute_of_day += 1
		if _minute_of_day >= MINUTES_PER_DAY:
			_minute_of_day = 0
			_day += 1
		result["minutesAdvanced"] = int(result["minutesAdvanced"]) + 1
		var current_period := period_for_minute(_minute_of_day)
		if current_period != previous_period:
			(result["periodChanges"] as Array).append({
				"from": previous_period,
				"to": current_period,
				"time": get_time(),
			})
		var weather_changed := false
		if (
			get_absolute_minute()
			>= _next_natural_weather_check_absolute_minute
		):
			var weather_event := _apply_natural_weather()
			_schedule_next_natural_weather_check()
			if not weather_event.is_empty():
				weather_changed = true
				(result["events"] as Array).append(weather_event)
		var minute_tick := get_time()
		minute_tick["weather"] = _weather
		minute_tick["weatherChanged"] = weather_changed
		(result["minuteTicks"] as Array).append(minute_tick)
	return result


func set_weather(weather: Variant) -> Dictionary:
	if not _errors.is_empty():
		return {"ok": false, "errors": _errors.duplicate()}
	if not weather is String or not _weather_types().has(weather as String):
		return {"ok": false, "errors": ["天气不是合法值：%s" % [weather]]}
	var weather_value := weather as String
	if weather_value == _weather:
		return {"ok": true, "changed": false, "weather": _weather}
	_weather = weather_value
	return {
		"ok": true,
		"changed": true,
		"weather": _weather,
		"event": _weather_event(),
	}


## 强制固定天气:传入合法天气后,小镇天气固定不变(自然天气不再随机变化);
## 传入空字符串 "" 解除强制,恢复自然天气。
func set_forced_weather(weather: Variant) -> Dictionary:
	if not _errors.is_empty():
		return {"ok": false, "errors": _errors.duplicate()}
	var weather_value := String(weather).strip_edges()
	if not weather_value.is_empty() and not _weather_types().has(weather_value):
		return {"ok": false, "errors": ["天气不是合法值：%s" % [weather]]}
	_forced_weather = weather_value
	if not weather_value.is_empty() and _weather != weather_value:
		_weather = weather_value
		return {
			"ok": true,
			"changed": true,
			"forced": weather_value,
			"weather": _weather,
			"event": _weather_event(),
		}
	return {
		"ok": true,
		"changed": false,
		"forced": _forced_weather,
		"weather": _weather,
	}


func get_forced_weather() -> String:
	return _forced_weather


func set_time(day: Variant, clock: Variant) -> Dictionary:
	if not _errors.is_empty():
		return {"ok": false, "errors": _errors.duplicate()}
	var parts := _parse_clock(clock as String) if clock is String else {}
	var errors: Array[String] = []
	if not _is_valid_day(day):
		errors.append("世界天数必须为不溢出绝对分钟的正整数")
	if not clock is String or parts.is_empty():
		errors.append("世界时钟必须是 HH:MM")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var previous := get_time()
	_day = int(day)
	_minute_of_day = int(parts["hour"]) * 60 + int(parts["minute"])
	_real_second_accumulator = 0.0
	_schedule_next_natural_weather_check()
	return {"ok": true, "previous": previous, "time": get_time()}


func cycle_time_period() -> Dictionary:
	if not _errors.is_empty():
		return {"ok": false, "errors": _errors.duplicate()}
	var clock_values := (_config.get("time", {}) as Dictionary).get("manualCycleClocks", []) as Array
	if clock_values.is_empty():
		return {"ok": false, "errors": ["手动切换时间缺少正式时段钟点"]}
	var current_period := period_for_minute(_minute_of_day)
	for value: Variant in clock_values:
		var clock := String(value)
		var parts := _parse_clock(clock)
		var minute := int(parts.get("hour", 0)) * 60 + int(parts.get("minute", 0))
		if minute > _minute_of_day and period_for_minute(minute) != current_period:
			return set_time(_day, clock)
	return set_time(_day + 1, String(clock_values[0]))


func queue_weather_roll(value: Variant) -> bool:
	if not _errors.is_empty() or typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var roll := float(value)
	if not is_finite(roll) or roll < 0.0 or roll >= 1.0:
		return false
	_forced_weather_rolls.append(roll)
	return true


func get_time() -> Dictionary:
	return {
		"day": _day,
		"clock": "%02d:%02d" % [_minute_of_day / 60, _minute_of_day % 60],
		"period": period_for_minute(_minute_of_day),
	}


func get_weather() -> String:
	return _weather


func get_weather_types() -> Array[String]:
	return _weather_types()


func get_minutes_until_next_weather_check() -> int:
	return maxi(
		0,
		_next_natural_weather_check_absolute_minute - get_absolute_minute(),
	)


func create_save_snapshot() -> Dictionary:
	return {
		"day": _day,
		"minuteOfDay": _minute_of_day,
		"weather": _weather,
		"realSecondAccumulator": _real_second_accumulator,
		"eventSequence": _event_sequence,
		"nextNaturalWeatherCheckAbsoluteMinute": (
			_next_natural_weather_check_absolute_minute
		),
		"rngState": str(_rng.state),
		"forcedWeatherRolls": _forced_weather_rolls.duplicate(),
	}


func restore_from_snapshot(snapshot: Dictionary) -> Dictionary:
	var errors: Array[String] = _errors.duplicate()
	var legacy_snapshot_fields := [
		"day",
		"minuteOfDay",
		"weather",
		"realSecondAccumulator",
		"eventSequence",
		"rngState",
		"forcedWeatherRolls",
	]
	var current_snapshot_fields := legacy_snapshot_fields.duplicate()
	current_snapshot_fields.append(
		"nextNaturalWeatherCheckAbsoluteMinute",
	)
	var has_scheduled_check := snapshot.has(
		"nextNaturalWeatherCheckAbsoluteMinute",
	)
	if (
		not _keys_match(snapshot, current_snapshot_fields)
		and not _keys_match(snapshot, legacy_snapshot_fields)
	):
		errors.append("存档天气状态字段不完整或包含未知字段")
	if typeof(snapshot.get("day")) != TYPE_INT:
		errors.append("存档世界天数必须是整数")
	if typeof(snapshot.get("minuteOfDay")) != TYPE_INT:
		errors.append("存档世界分钟必须是整数")
	if typeof(snapshot.get("eventSequence")) != TYPE_INT:
		errors.append("存档天气事件序号必须是整数")
	if (
		has_scheduled_check
		and (
			typeof(
				snapshot.get(
					"nextNaturalWeatherCheckAbsoluteMinute",
				)
			)
			!= TYPE_INT
		)
	):
		errors.append("存档下次自然天气检查时间必须是整数")
	if (
		typeof(snapshot.get("realSecondAccumulator")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(
			float(snapshot.get("realSecondAccumulator", NAN))
		)
	):
		errors.append("存档时间累积量必须是有限数字")
	var day := int(snapshot.get("day", 0))
	var minute_of_day := int(snapshot.get("minuteOfDay", -1))
	if not snapshot.get("weather") is String:
		errors.append("存档天气必须是文本")
	var weather := (
		String(snapshot.get("weather", ""))
		if snapshot.get("weather") is String
		else ""
	)
	var accumulator := float(snapshot.get("realSecondAccumulator", -1.0))
	var event_sequence := int(snapshot.get("eventSequence", -1))
	var next_weather_check := int(
		snapshot.get("nextNaturalWeatherCheckAbsoluteMinute", -1)
	)
	if not snapshot.get("rngState") is String:
		errors.append("存档天气随机状态必须是文本")
	var rng_state_text := (
		String(snapshot.get("rngState", ""))
		if snapshot.get("rngState") is String
		else ""
	)
	if not _is_valid_day(snapshot.get("day")):
		errors.append("存档世界天数必须为不溢出绝对分钟的正整数")
	if minute_of_day < 0 or minute_of_day >= MINUTES_PER_DAY:
		errors.append("存档世界分钟必须位于一天范围内")
	if not _weather_types().has(weather):
		errors.append("存档天气不是合法天气：%s" % weather)
	var seconds_per_minute := float(
		(_config.get("time", {}) as Dictionary).get(
			"realSecondsPerGameMinute",
			1.0,
		)
	)
	if accumulator < 0.0 or accumulator >= seconds_per_minute:
		errors.append("存档时间累积量不在合法范围内")
	if event_sequence < 0:
		errors.append("存档天气事件序号不能为负数")
	var restored_absolute_minute := (
		(day - 1) * MINUTES_PER_DAY + minute_of_day
	)
	if (
		has_scheduled_check
		and (
			next_weather_check <= restored_absolute_minute
			or next_weather_check
			> restored_absolute_minute + NATURAL_WEATHER_CHECK_MAX_MINUTES
		)
	):
		errors.append("存档下次自然天气检查时间不在合法范围内")
	if (
		rng_state_text.is_empty()
		or not rng_state_text.is_valid_int()
		or rng_state_text.begins_with("+")
		or (
			rng_state_text.is_valid_int()
			and str(int(rng_state_text)) != rng_state_text
		)
	):
		errors.append("存档天气随机状态无效")
	var forced_rolls: Array[float] = []
	if typeof(snapshot.get("forcedWeatherRolls")) != TYPE_ARRAY:
		errors.append("存档天气测试序列必须是数组")
	else:
		for value: Variant in snapshot.get("forcedWeatherRolls", []) as Array:
			if (
				typeof(value) not in [TYPE_INT, TYPE_FLOAT]
				or not is_finite(float(value))
				or float(value) < 0.0
				or float(value) >= 1.0
			):
				errors.append("存档天气测试序列包含非法概率")
				continue
			forced_rolls.append(float(value))
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	_day = day
	_minute_of_day = minute_of_day
	_weather = weather
	_real_second_accumulator = accumulator
	_event_sequence = event_sequence
	_rng.state = int(rng_state_text)
	_forced_weather_rolls = forced_rolls
	if has_scheduled_check:
		_next_natural_weather_check_absolute_minute = next_weather_check
	else:
		_schedule_next_natural_weather_check()
	return {"ok": true, "time": get_time(), "weather": _weather}


func get_minute_of_day() -> int:
	return _minute_of_day


func get_absolute_minute() -> int:
	return (_day - 1) * MINUTES_PER_DAY + _minute_of_day


func minutes_until_next_period() -> int:
	var current_period := period_for_minute(_minute_of_day)
	var periods := (_config.get("time", {}) as Dictionary).get("periods", []) as Array
	for value: Variant in periods:
		var period := value as Dictionary
		var start := int(period.get("startMinute", -1))
		if start > _minute_of_day and String(period.get("name", "")) != current_period:
			return start - _minute_of_day
	for value: Variant in periods:
		var period := value as Dictionary
		if String(period.get("name", "")) != current_period:
			return MINUTES_PER_DAY - _minute_of_day + int(period.get("startMinute", 0))
	return MINUTES_PER_DAY


func period_for_minute(minute_of_day: int) -> String:
	var normalized := posmod(minute_of_day, MINUTES_PER_DAY)
	var result := ""
	for period_value: Variant in (_config.get("time", {}) as Dictionary).get("periods", []) as Array:
		var period := period_value as Dictionary
		if int(period.get("startMinute", -1)) <= normalized:
			result = String(period.get("name", ""))
		else:
			break
	return result


func _apply_natural_weather() -> Dictionary:
	# 强制固定天气模式下,自然天气不再变化。
	if not _forced_weather.is_empty():
		return {}
	var transitions := (_config.get("weather", {}) as Dictionary).get("transitions", {}) as Dictionary
	var row := transitions.get(_weather, {}) as Dictionary
	var roll: float = float(_forced_weather_rolls.pop_front()) if not _forced_weather_rolls.is_empty() else _rng.randf()
	var threshold := float(roll) * 100.0
	var cumulative := 0.0
	var next_weather := _weather
	for weather_name in _weather_types():
		cumulative += float(row.get(weather_name, 0.0))
		if threshold < cumulative:
			next_weather = weather_name
			break
	if next_weather == _weather:
		return {}
	_weather = next_weather
	return _weather_event()


func _schedule_next_natural_weather_check() -> void:
	_next_natural_weather_check_absolute_minute = (
		get_absolute_minute()
		+ _rng.randi_range(
			NATURAL_WEATHER_CHECK_MIN_MINUTES,
			NATURAL_WEATHER_CHECK_MAX_MINUTES,
		)
	)


func _weather_event() -> Dictionary:
	_event_sequence += 1
	return {
		"event_id": "weather-%d" % _event_sequence,
		"time": get_time(),
		"type": "天气变了",
		"weather": _weather,
	}


func _weather_types() -> Array[String]:
	var result: Array[String] = []
	for value: Variant in (_config.get("weather", {}) as Dictionary).get("types", []) as Array:
		result.append(String(value))
	return result


func _parse_clock(clock: String) -> Dictionary:
	if (
		clock.length() != 5
		or clock.substr(2, 1) != ":"
		or not _is_ascii_digit(clock.substr(0, 1))
		or not _is_ascii_digit(clock.substr(1, 1))
		or not _is_ascii_digit(clock.substr(3, 1))
		or not _is_ascii_digit(clock.substr(4, 1))
	):
		return {}
	var parts := clock.split(":")
	var hour := int(parts[0])
	var minute := int(parts[1])
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return {}
	return {"hour": hour, "minute": minute}


func _is_ascii_digit(character: String) -> bool:
	return WORLD_SCALARS.is_ascii_digit(character)


func _is_valid_day(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT
		and int(value) > 0
		and int(value) <= MAX_SAFE_DAY
	)


func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _validate_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _keys_match(config, ["schemaVersion", "time", "weather"]):
		errors.append("时间天气数据包含未知或缺失字段")
	if not _is_integer_number(config.get("schemaVersion")) or int(config.get("schemaVersion")) != 1:
		errors.append("时间天气数据 schemaVersion 必须为 1")
	var time_value: Variant = config.get("time")
	if not time_value is Dictionary:
		errors.append("时间天气数据 time 必须是对象")
	var time := time_value as Dictionary if time_value is Dictionary else {}
	if not _keys_match(time, ["realSecondsPerGameMinute", "manualCycleClocks", "periods"]):
		errors.append("时间配置包含未知或缺失字段")
	var seconds_value: Variant = time.get("realSecondsPerGameMinute")
	if (
		typeof(seconds_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(seconds_value))
		or float(seconds_value) != 1.0
	):
		errors.append("realSecondsPerGameMinute 必须为 1")
	var manual_value: Variant = time.get("manualCycleClocks")
	if not manual_value is Array or manual_value != MANUAL_CYCLE_CLOCKS:
		errors.append("手动切换时间必须使用正式六时段钟点")
	var periods_value: Variant = time.get("periods")
	if not periods_value is Array or not _periods_match(periods_value as Array):
		errors.append("时段数据必须符合正式六时段边界")
	var weather_value: Variant = config.get("weather")
	if not weather_value is Dictionary:
		errors.append("时间天气数据 weather 必须是对象")
	var weather := weather_value as Dictionary if weather_value is Dictionary else {}
	if not _keys_match(
		weather,
		["naturalChangeIntervalMinutes", "types", "transitions"],
	):
		errors.append("天气配置包含未知或缺失字段")
	var interval_value: Variant = weather.get("naturalChangeIntervalMinutes")
	if not interval_value is Dictionary:
		errors.append("自然天气检查间隔必须是对象")
	else:
		var interval := interval_value as Dictionary
		if (
			not _keys_match(interval, ["minimum", "maximum"])
			or not _is_integer_number(interval.get("minimum"))
			or not _is_integer_number(interval.get("maximum"))
			or int(interval.get("minimum", 0))
			!= NATURAL_WEATHER_CHECK_MIN_MINUTES
			or int(interval.get("maximum", 0))
			!= NATURAL_WEATHER_CHECK_MAX_MINUTES
		):
			errors.append("自然天气检查间隔必须为 45 至 90 游戏分钟")
	if weather.get("types", []) != WEATHER_TYPES:
		errors.append("天气类型必须符合世界规格")
	var transitions_value: Variant = weather.get("transitions")
	if not transitions_value is Dictionary:
		errors.append("天气转移表必须是对象")
	var transitions := transitions_value as Dictionary if transitions_value is Dictionary else {}
	var transition_keys: Array = transitions.keys()
	transition_keys.sort()
	var expected_keys: Array = WEATHER_TYPES.duplicate()
	expected_keys.sort()
	if transition_keys != expected_keys:
		errors.append("天气转移表必须只包含七种当前天气")
	for current_weather in WEATHER_TYPES:
		var row_value: Variant = transitions.get(current_weather)
		if not row_value is Dictionary:
			errors.append("天气转移行必须是对象：%s" % current_weather)
			continue
		var row := row_value as Dictionary
		var row_keys: Array = row.keys()
		row_keys.sort()
		if row_keys != expected_keys:
			errors.append("天气转移行必须只包含七种下一天气：%s" % current_weather)
			continue
		for next_weather in WEATHER_TYPES:
			var probability: Variant = row.get(next_weather)
			if (
				not _is_integer_number(probability)
				or int(probability) != int((WEATHER_TRANSITIONS[current_weather] as Dictionary)[next_weather])
			):
				errors.append("天气转移概率不符合世界规格：%s → %s" % [current_weather, next_weather])
	return errors


func _periods_match(periods: Array) -> bool:
	if periods.size() != PERIOD_BOUNDARIES.size():
		return false
	for index in periods.size():
		var value: Variant = periods[index]
		if not value is Dictionary:
			return false
		var period := value as Dictionary
		var expected := PERIOD_BOUNDARIES[index] as Array
		if (
			period.size() != 2
			or not period.get("name") is String
			or String(period.get("name", "")) != String(expected[0])
			or not _is_integer_number(period.get("startMinute"))
			or int(period.get("startMinute")) != int(expected[1])
		):
			return false
	return true


func _keys_match(value: Dictionary, expected: Array) -> bool:
	var actual: Array = value.keys()
	actual.sort()
	var normalized_expected := expected.duplicate()
	normalized_expected.sort()
	return actual == normalized_expected


func _is_integer_number(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) == roundf(float(value))
	)
