extends RefCounted


static func apply_body_effects(
	resident: Dictionary,
	effects: Dictionary,
	body_levels: Dictionary,
) -> void:
	var body := resident.get("body", {}) as Dictionary
	for state_name_value: Variant in effects:
		var state_name := String(state_name_value)
		if not body_levels.has(state_name):
			continue
		var levels := body_levels[state_name] as Array
		var current_index := levels.find(String(body.get(state_name, levels[0])))
		body[state_name] = levels[clampi(
			current_index + int(effects[state_name_value]),
			0,
			levels.size() - 1,
		)]
	var activity_state := (
		resident.get("activityState", empty_activity_state()) as Dictionary
	).duplicate(true)
	if effects.has("饿"):
		activity_state["satiety"] = need_value_for_body_level(
			String(body.get("饿", "不饿")),
		)
	if effects.has("累"):
		activity_state["energy"] = need_value_for_body_level(
			String(body.get("累", "不累")),
		)
	resident["activityState"] = activity_state


const SLEEP_ACTIVITY_ID := "activity_home_sleep"
const SLEEP_ENERGY_THRESHOLD := 35


# 活动执行/身体需求/工单匹配等纯标量函数族(O 域迁移第八件)。

static func safe_activity_execution(execution: Dictionary) -> Dictionary:
	var label := String(
		execution.get(
			"label",
			execution.get("activityLabel", ""),
		)
	)
	var result_text := "已开始"
	match String(execution.get("status", "")):
		"completed":
			result_text = "已完成"
		"interrupted":
			result_text = "已中断"
		"failed":
			result_text = "未能完成"
	return {
		"activityId": String(execution.get("activityId", "")),
		"label": label,
		"placeId": String(execution.get("placeId", "")),
		"role": String(execution.get("role", "")),
		"result": result_text,
	}

static func activity_progress_doing(
	execution: Dictionary,
	performing_minutes: int,
) -> String:
	var label := String(
		execution.get(
			"activityLabel",
			execution.get("label", "当前活动"),
		)
	).strip_edges()
	if label.is_empty():
		label = "当前活动"
	if label.begins_with("在") and label.length() > 1:
		label = label.substr(1)
	if label.length() > 10:
		label = label.substr(0, 10)
	if String(execution.get("role", "")) != "worker":
		return "正在%s" % label
	match posmod(floori(float(performing_minutes) / 5.0), 3):
		0:
			return "正在%s" % label
		1:
			return "%s进行中" % label
		_:
			return "继续%s" % label

static func empty_activity_state() -> Dictionary:
	return {
		"energy": 50,
		"satiety": 50,
		"stress": 50,
		"socialNeed": 50,
		"solitudeNeed": 50,
	}

static func need_value_for_body_level(level: String) -> int:
	if level.begins_with("很"):
		return 20
	if level.begins_with("有点"):
		return 35
	return 50

static func activity_state_from_body(body: Dictionary) -> Dictionary:
	var state := empty_activity_state()
	state["satiety"] = need_value_for_body_level(
		String(body.get("饿", "不饿")),
	)
	state["energy"] = need_value_for_body_level(
		String(body.get("累", "不累")),
	)
	return state

static func next_activity_state(
	resident: Dictionary,
	effects: Dictionary,
	allowed_keys: Array,
) -> Dictionary:
	var state := (
		resident.get("activityState", empty_activity_state()) as Dictionary
	).duplicate(true)
	for key_value: Variant in effects:
		var key := String(key_value)
		if key in allowed_keys:
			state[key] = clampi(
				int(state.get(key, 50)) + int(effects[key_value]),
				0,
				100,
			)
	return state

static func sync_body_from_activity_needs(
	resident: Dictionary,
	activity_state: Dictionary,
) -> void:
	var body := resident.get("body", {}) as Dictionary
	var satiety := int(activity_state.get("satiety", 50))
	var energy := int(activity_state.get("energy", 50))
	body["饿"] = (
		"很饿"
		if satiety <= 20
		else ("有点饿" if satiety <= 35 else "不饿")
	)
	body["累"] = (
		"很累"
		if energy <= 20
		else ("有点累" if energy <= 35 else "不累")
	)

static func hunger_crossed_decision_threshold(
	previous: Dictionary,
	next: Dictionary,
) -> bool:
	return (
		int(previous.get("satiety", 50)) > 35
		and int(next.get("satiety", 50)) <= 35
	)

static func resident_sleep_needed(resident: Dictionary) -> bool:
	var activity_state := resident.get(
		"activityState",
		empty_activity_state(),
	) as Dictionary
	return int(activity_state.get("energy", 50)) <= SLEEP_ENERGY_THRESHOLD

static func apply_sleep_activity_availability(
	resident: Dictionary,
	option: Dictionary,
) -> void:
	if (
		String(option.get("activityId", "")) != SLEEP_ACTIVITY_ID
		or resident_sleep_needed(resident)
	):
		return
	option["available"] = false
	option["disabledReason"] = "SLEEP_NOT_NEEDED"

static func start_sleep_leave(
	resident: Dictionary,
	action: Dictionary,
	execution: Dictionary,
	work_expected: bool,
	approach_duration: int,
) -> bool:
	if (
		String(execution.get("activityId", "")) != SLEEP_ACTIVITY_ID
		or not work_expected
	):
		return false
	resident["attendanceState"] = {
		"status": "on_leave",
		"untilMinute": (
			int(action.get("startedAbsoluteMinute", 0))
			+ approach_duration
			+ maxi(1, int(action.get("durationMinutes", 0)))
		),
	}
	return true

static func clear_sleep_leave(resident: Dictionary) -> bool:
	var attendance := resident.get("attendanceState", {}) as Dictionary
	if String(attendance.get("status", "available")) != "on_leave":
		return false
	resident["attendanceState"] = {
		"status": "available",
		"untilMinute": -1,
	}
	return true

static func life_rhythm_snapshot(
	resident: Dictionary,
	minute_of_day: int,
	schedule_context: Dictionary,
) -> Dictionary:
	var rhythm: Dictionary
	if minute_of_day < 420:
		rhythm = {
			"id": "late_night",
			"label": "深夜；通常应休息，也可以因本人情况晚睡或不睡",
			"flexible": true,
		}
	elif minute_of_day < 570:
		rhythm = {
			"id": "morning_start",
			"label": "起床、准备和自由活动；可以早起或赖床",
			"flexible": true,
		}
	elif minute_of_day < 750:
		rhythm = {
			"id": "morning_work",
			"label": "上午工作时段；可以迟到、请假、闭店或放假",
			"flexible": true,
		}
	elif minute_of_day < 870:
		rhythm = {
			"id": "midday_free",
			"label": "午饭、午休和自由活动",
			"flexible": true,
		}
	elif minute_of_day < 1140:
		rhythm = {
			"id": "afternoon_work",
			"label": "下午工作时段；可以请假、闭店或放假",
			"flexible": true,
		}
	elif minute_of_day < 1380:
		rhythm = {
			"id": "evening_free",
			"label": "下班、加班、自由活动或公共活动",
			"flexible": true,
		}
	else:
		rhythm = {
			"id": "night_rest",
			"label": "夜间休息；可以早睡、晚睡或因本人情况不睡",
			"flexible": true,
		}
	var social_state := resident.get("socialState", {}) as Dictionary
	var workplace := String(social_state.get("workplace", ""))
	rhythm["work_expected"] = bool(
		schedule_context.get("workExpected", false),
	)
	rhythm["workplace"] = workplace
	rhythm["schedule_label"] = String(schedule_context.get("scheduleLabel", ""))
	var sleep_needed := resident_sleep_needed(resident)
	rhythm["sleep_needed"] = sleep_needed
	if sleep_needed:
		rhythm["label"] = "%s；当前精力偏低，应优先判断是否回家睡觉，上班时也可以请假" % String(
			rhythm.get("label", ""),
		)
	if bool(rhythm.get("work_expected", false)) and not workplace.is_empty():
		rhythm["label"] = "%s；本职工作地是%s" % [
			String(rhythm.get("label", "")),
			workplace,
		]
	return rhythm

static func meal_period_for_minute(absolute_minute: int) -> Dictionary:
	var minute_of_day := posmod(absolute_minute, 1440)
	for period: Dictionary in [
		{
			"id": "breakfast", "label": "早餐",
			"start": 300, "serviceStart": 360, "end": 600,
		},
		{
			"id": "lunch", "label": "午餐",
			"start": 600, "serviceStart": 660, "end": 840,
		},
		{
			"id": "dinner", "label": "晚餐",
			"start": 960, "serviceStart": 1020, "end": 1200,
		},
	]:
		if minute_of_day >= int(period.get("start", 0)) and minute_of_day < int(
			period.get("end", 0),
		):
			return period.duplicate(true)
	return {}

static func activity_candidate_physical_targets(
	candidates: Array,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for value: Variant in candidates:
		var candidate := value as Dictionary
		var kind := String(candidate.get("targetType", ""))
		var ref := ""
		if kind == "region":
			ref = String(candidate.get("targetRegionId", ""))
		elif kind == "prop":
			ref = String(candidate.get("targetPropName", ""))
		else:
			continue
		var key := "%s:%s" % [kind, ref]
		if ref.is_empty() or seen.has(key):
			continue
		seen[key] = true
		result.append({"kind": kind, "ref": ref})
	return result

static func matching_work_tasks_for_targets(
	tasks: Array,
	physical_targets: Array[Dictionary],
) -> Array:
	if physical_targets.is_empty():
		return tasks.duplicate()
	var result: Array = []
	for value: Variant in tasks:
		var task := value as Dictionary
		var declared_region_targets: Array[Dictionary] = []
		for target_value: Variant in task.get("targets", []) as Array:
			var target := target_value as Dictionary
			if String(target.get("kind", "")) in [
				"region",
				"audience_area",
			]:
				declared_region_targets.append(target)
		if declared_region_targets.is_empty():
			result.append(task)
			continue
		var matches := false
		for declared: Dictionary in declared_region_targets:
			for actual: Dictionary in physical_targets:
				if (
					String(actual.get("kind", "")) == "region"
					and String(declared.get("ref", ""))
					== String(actual.get("ref", ""))
				):
					matches = true
					break
			if matches:
				break
		if matches:
			result.append(task)
	return result

static func onsite_service_wait_minutes(kind: String) -> int:
	# 诊所看诊包含自由问诊、检查和必要的配药；餐饮要等真实备餐。
	# 普通柜台服务窗口对这些真实链条太短。
	match kind:
		"dining_order":
			return 30
		"clinic", "cafe_order":
			return 120
	return 30

static func target_refs_match(
	expected: Dictionary,
	actual: Dictionary,
) -> bool:
	for key_value: Variant in expected:
		var key := String(key_value)
		if not actual.has(key) or actual.get(key) != expected.get(key):
			return false
	return true

static func duplicate_optional_dictionary(value: Variant) -> Variant:
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else null

static func append_unique_story_ids(
	target: Array[String],
	values: Array,
) -> void:
	for value: Variant in values:
		var normalized := String(value).strip_edges()
		if not normalized.is_empty() and not target.has(normalized):
			target.append(normalized)
