class_name TownAgentLifeDestinationQuery
extends RefCounted


const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const SLEEP_ACTIVITY_ID := "activity_home_sleep"
const MAX_DESTINATION_OPTIONS := 8
const MAX_ACTIVITIES_PER_DESTINATION := 3
const NATURAL_LIFE_ACTIVITY_IDS := [
	"activity_cafe_eat_pastry",
	"activity_cafe_order",
	"activity_cafe_rest",
	"activity_dining_eat_meal",
	"activity_dining_collect_meal",
	"activity_dining_return_dishes",
	SLEEP_ACTIVITY_ID,
	"activity_market_buy_general_goods",
	"activity_market_buy_fish",
	"activity_market_buy_flowers",
]


static func options(
	resident: Dictionary,
	destinations: Array,
	has_work_tasks: bool,
	sleep_needed: bool,
	absolute_minute: int,
	weather: String,
	activity_runtime,
) -> Array[Dictionary]:
	var resident_id := String(resident.get("residentId", ""))
	if resident_id.is_empty():
		return []
	var activity_state := resident.get("activityState", {}) as Dictionary
	var meal_needed := int(activity_state.get("satiety", 50)) <= 35
	# 平常仍由职业任务优先；精力或饥饿达到阈值时，生活选项不能被工作遮住。
	if has_work_tasks and not sleep_needed and not meal_needed:
		return []
	var social_state := resident.get("socialState", {}) as Dictionary
	var home_place := String(social_state.get("home", ""))
	var interests: Variant = (
		resident.get("attributes", {}) as Dictionary
	).get("interests", [])
	var minute_of_day := posmod(absolute_minute, 1440)
	var day_index := absolute_minute / 1440
	var result: Array[Dictionary] = []
	for place_value: Variant in destinations:
		var place_id := String(place_value)
		var query := activity_runtime.query_options(
			resident_id,
			social_state,
			place_id,
			minute_of_day,
			weather,
		) as Dictionary
		if query.get("ok") != true:
			continue
		var activities := _activities_for_destination(
			query.get("options", []) as Array,
			place_id,
			home_place,
			interests,
			has_work_tasks,
			sleep_needed,
			activity_runtime,
		)
		if activities.is_empty():
			continue
		result.append({
			"place_id": place_id,
			"activities": activities,
			"interest_match": activities.any(
				func(activity: Dictionary) -> bool:
					return bool(activity.get("interest_match", false)),
			),
			"rotation_key": posmod(
				hash("%s:%d:%s" % [resident_id, day_index, place_id]),
				2147483647,
			),
		})
	result.sort_custom(_destination_precedes)
	if result.size() > MAX_DESTINATION_OPTIONS:
		result.resize(MAX_DESTINATION_OPTIONS)
	for option: Dictionary in result:
		option.erase("interest_match")
		option.erase("rotation_key")
	return result


static func _activities_for_destination(
	options: Array,
	place_id: String,
	home_place: String,
	interests: Variant,
	has_work_tasks: bool,
	sleep_needed: bool,
	activity_runtime,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for option_value: Variant in options:
		var option := (option_value as Dictionary).duplicate(true)
		var activity_id := String(option.get("activityId", ""))
		if (
			not bool(option.get("available", false))
			or String(option.get("role", "")) == "worker"
			or activity_id not in NATURAL_LIFE_ACTIVITY_IDS
		):
			continue
		if activity_id == SLEEP_ACTIVITY_ID and (
			place_id != home_place or not sleep_needed
		):
			continue
		if has_work_tasks and not DINING_SERVICE.activity_allowed_during_work(activity_id):
			continue
		var matched := INTERESTS.matched_labels_for_activity(
			interests,
			activity_runtime.activity_tags(activity_id),
		)
		result.append({
			"activity_id": activity_id,
			"label": String(option.get("label", "")),
			"interest_match": not matched.is_empty(),
			"matched_interests": matched,
		})
	result.sort_custom(_activity_precedes)
	if result.size() > MAX_ACTIVITIES_PER_DESTINATION:
		result.resize(MAX_ACTIVITIES_PER_DESTINATION)
	return result


static func _activity_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_match := bool(left.get("interest_match", false))
	var right_match := bool(right.get("interest_match", false))
	if left_match != right_match:
		return left_match
	return String(left.get("activity_id", "")) < String(
		right.get("activity_id", ""),
	)


static func _destination_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_match := bool(left.get("interest_match", false))
	var right_match := bool(right.get("interest_match", false))
	if left_match != right_match:
		return left_match
	var left_rotation := int(left.get("rotation_key", 0))
	var right_rotation := int(right.get("rotation_key", 0))
	if left_rotation != right_rotation:
		return left_rotation < right_rotation
	return String(left.get("place_id", "")) < String(
		right.get("place_id", ""),
	)
