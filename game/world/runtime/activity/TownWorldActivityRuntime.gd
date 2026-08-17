class_name TownWorldActivityRuntime
extends RefCounted


const OPERATION := "activity.perform"
const WEATHER_ACTIVITY_POLICY := preload(
	"res://world/runtime/activity/TownWorldWeatherActivityPolicy.gd"
)
const ROUTE_QUERY := preload(
	"res://world/data/town/TownWorldRouteQuery.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const SAVE_SCHEMA_VERSION := 1
const IDEMPOTENCY_KEY_SEPARATOR := "|"
const REGION_WORK_CLEARANCE_PX := 36.0
const REGION_WORK_POINT_SPACING_PX := 72.0
const REGION_WORK_PORTAL_CLEARANCE_PX := 120.0
const REGION_WORK_PROP_CLEARANCE_PX := 72.0
const REGION_WORK_MEMBER_LIMIT := 24
const REGION_WORK_ROUTE_SAMPLE_STEP_PX := 40.0
const REGION_WORK_ROUTE_CONNECTION_PX := 120.0
const REGION_WORK_ROUTE_INDEX_CELL_PX := 128.0
const NOT_COMPILED := "ACTIVITY_RUNTIME_DATA_NOT_COMPILED"
const SOURCE_CONTRACT_DIRECT := "activity.perform"
const SOURCE_CONTRACT_LEGACY_PROP := "legacy.agent.use_prop"
const SOURCE_CONTRACT_AGENT_ACTIVITY := "agent.activity"
const RECEIPT_FIELDS := [
	"receiptVersion",
	"validator",
	"ok",
	"validated",
	"status",
	"sourceWorldId",
	"sourceFingerprint",
	"sourceDocumentFingerprints",
	"staticReferencesValidated",
	"activityChainVerified",
	"placeCapabilitiesVerified",
	"scheduleTemplatesResolved",
	"formalExecutable",
	"errors",
]
const SOURCE_DOCUMENT_NAMES := [
	"occupation_catalog.json",
	"activity_definitions.json",
	"activity_slots.json",
	"places.json",
	"props.json",
	"indoor_prop_authoring.json",
	"schedule_templates.json",
]
const STEP_FIELDS := [
	"stepId",
	"operation",
	"target",
	"params",
]
const TARGET_FIELDS := ["activityId", "placeId", "preferredSlotId"]
const PARAM_FIELDS := ["reason"]
static var _shared_region_member_positions: Dictionary = {}
var _configured := false
var _source_fingerprint := ""
var _region_cache_namespace := ""
var _occupations_by_id: Dictionary = {}
var _occupation_id_by_label: Dictionary[String, String] = {}
var _activities_by_id: Dictionary = {}
var _slots_by_id: Dictionary = {}
var _slots_by_activity: Dictionary = {}
var _places_by_name: Dictionary = {}
var _regions_by_id: Dictionary = {}
var _region_member_positions_by_id: Dictionary = {}
var _outdoor_route_samples_by_cell: Dictionary = {}
var _schedules_by_id: Dictionary = {}
var _reservations: Dictionary = {}
var _executions_by_key: Dictionary = {}
var _active_key_by_resident: Dictionary = {}
var _generation := 0
var _revision := 0
var _weather_policy: RefCounted = WEATHER_ACTIVITY_POLICY.new()


func configure(world_data: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	_validate_compiled_envelope(world_data, errors)
	if not errors.is_empty():
		_clear_configuration()
		return _failure(NOT_COMPILED, errors)
	_clear_configuration()
	_source_fingerprint = String(
		(world_data.get("activityIntegrationReceipt", {}) as Dictionary).get(
			"sourceFingerprint",
			"",
		)
	)
	_region_cache_namespace = "%s:%s:%s:%d" % [
		_source_fingerprint,
		str(hash(world_data.get("movementNetwork", {}))),
		str(hash(world_data.get("perceptionRegions", []))),
		int(REGION_WORK_CLEARANCE_PX),
	]
	for value: Variant in world_data.get("occupations", []) as Array:
		var occupation := (value as Dictionary).duplicate(true)
		var occupation_id := String(occupation.get("occupationId", ""))
		_occupations_by_id[occupation_id] = occupation
		_occupation_id_by_label[String(occupation.get("label", ""))] = occupation_id
		for alias_value: Variant in occupation.get("aliases", []) as Array:
			_occupation_id_by_label[String(alias_value)] = occupation_id
	for value: Variant in world_data.get("activityDefinitions", []) as Array:
		var activity := (value as Dictionary).duplicate(true)
		_activities_by_id[String(activity.get("activityId", ""))] = activity
	for value: Variant in world_data.get("places", []) as Array:
		var place := (value as Dictionary).duplicate(true)
		_places_by_name[String(place.get("name", ""))] = place
	for value: Variant in world_data.get("perceptionRegions", []) as Array:
		var region := (value as Dictionary).duplicate(true)
		_regions_by_id[String(region.get("id", ""))] = region
	for value: Variant in world_data.get("scheduleTemplates", []) as Array:
		var schedule := (value as Dictionary).duplicate(true)
		_schedules_by_id[String(schedule.get("scheduleTemplateId", ""))] = schedule
	for value: Variant in world_data.get("activitySlots", []) as Array:
		var authored_slot := (value as Dictionary).duplicate(true)
		for expanded_value: Variant in _expanded_region_slots(
			authored_slot,
		):
			var slot := expanded_value as Dictionary
			if String(slot.get("targetType", "")) == "region":
				slot["memberAnchors"] = _region_members_for_slot(
					slot,
					world_data,
				)
			var slot_id := String(slot.get("slotId", ""))
			var activity_id := String(slot.get("activityId", ""))
			_slots_by_id[slot_id] = slot
			var activity_slots := _slots_by_activity.get(
				activity_id,
				[],
			) as Array
			activity_slots.append(slot)
			_slots_by_activity[activity_id] = activity_slots
	for activity_id_value: Variant in _slots_by_activity:
		(_slots_by_activity[activity_id_value] as Array).sort_custom(
			func(left: Variant, right: Variant) -> bool:
				return String((left as Dictionary).get("slotId", "")) < String(
					(right as Dictionary).get("slotId", "")
				)
		)
	_configured = true
	return {"ok": true, "errorCode": "", "retryable": false}


func is_configured() -> bool:
	return _configured


func reconcile_activity_routines_before_save(
	activity_routines: Dictionary,
	residents: Dictionary,
	direct_source_contract: String,
) -> Array[Dictionary]:
	# Save only routines whose current World action still owns the execution.
	# Any orphan is closed at the save boundary; the resident's newer action is
	# left untouched and can continue on its next wake.
	var orphaned: Array[String] = []
	for resident_id_value: Variant in activity_routines.keys():
		var resident_id := String(resident_id_value)
		var resident := residents.get(resident_id, {}) as Dictionary
		var routine := activity_routines.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		var execution := execution_for_action(
			resident_id,
			String(action.get("action_id", "")),
		) as Dictionary
		var direct_activity_is_active := (
			String(action.get("type", "")) == "用道具"
			and not execution.is_empty()
			and String(execution.get("sourceContract", ""))
			== direct_source_contract
			and String(execution.get("sourceActionId", "")).is_empty()
		)
		var onsite_service_wait_is_active := (
			String(action.get("type", "")) == "待着"
			and not String(action.get("serviceRequestId", "")).strip_edges().is_empty()
			and String(action.get("action_id", "")).begins_with("service-wait:")
		)
		if not direct_activity_is_active and not onsite_service_wait_is_active:
			orphaned.append(resident_id)
	var interrupted_results: Array[Dictionary] = []
	for resident_id in orphaned:
		var routine := activity_routines.get(resident_id, {}) as Dictionary
		activity_routines.erase(resident_id)
		var source_action_id := String(routine.get("sourceActionId", "")).strip_edges()
		if not source_action_id.is_empty():
			interrupted_results.append({
				"residentId": resident_id,
				"actionId": source_action_id,
				"status": "interrupted",
				"reason": "活动安排已经结束，居民继续当前的事情",
			})
	return interrupted_results


func presentation_semantic_for_activity(activity_id: String) -> Dictionary:
	var normalized_id := activity_id.strip_edges()
	if not _configured or not _activities_by_id.has(normalized_id):
		return {}
	var activity := _activities_by_id[normalized_id] as Dictionary
	var activity_kind := String(activity.get("kind", "")).strip_edges()
	var pose_family := String(activity.get("poseFamily", "")).strip_edges()
	var base_icon_key := ACTION_PRESENTATION.activity_icon_key(normalized_id)
	var icon_type := ""
	if activity_kind == "work":
		icon_type = "working"
	elif pose_family == "eat_drink":
		icon_type = "eating"
	elif pose_family == "read_write" and activity_kind == "leisure":
		icon_type = "reading"
	return {
		"activityKind": activity_kind,
		"poseFamily": pose_family,
		"semanticIconType": icon_type,
		"baseIconKey": base_icon_key,
		"label": String(activity.get("label", "")).strip_edges(),
	}


func result_contract_for_activity(activity_id: String) -> Dictionary:
	var normalized_id := activity_id.strip_edges()
	if not _configured or not _activities_by_id.has(normalized_id):
		return {}
	var activity := _activities_by_id[normalized_id] as Dictionary
	return (
		(activity.get("resultContract", {}) as Dictionary).duplicate(true)
		if activity.get("resultContract") is Dictionary
		else {}
	)


func semantic_region_targets(activity_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	if not _configured or not _slots_by_activity.has(activity_id):
		return result
	for value: Variant in _slots_by_activity[activity_id] as Array:
		var slot := value as Dictionary
		var target := slot.get("target", {}) as Dictionary
		var region_id := String(target.get("regionId", ""))
		if (
			String(slot.get("targetType", "")) != "region"
			or target.get("semanticQuery") is not Dictionary
			or (target.get("semanticQuery") as Dictionary).is_empty()
			or region_id.is_empty()
			or seen.has(region_id)
		):
			continue
		seen[region_id] = true
		result.append({
			"kind": "region",
			"ref": region_id,
			"placeId": String(slot.get("placeName", "")),
		})
	return result


func execution_physical_target(execution: Dictionary) -> Dictionary:
	var slot_id := String(execution.get("slotId", ""))
	if not _configured or not _slots_by_id.has(slot_id):
		return {}
	var slot := _slots_by_id[slot_id] as Dictionary
	var target := slot.get("target", {}) as Dictionary
	match String(slot.get("targetType", "")):
		"region":
			return {
				"kind": "region",
				"ref": String(target.get("regionId", "")),
			}
		"prop":
			return {
				"kind": "prop",
				"ref": _target_navigation_prop_name(target),
			}
	return {}


func reset_runtime_state() -> void:
	_reservations.clear()
	_executions_by_key.clear()
	_active_key_by_resident.clear()
	_generation = 0
	_revision = 0


func close() -> void:
	reset_runtime_state()
	_clear_configuration()


func activity_tags(activity_id: String) -> Array[String]:
	if not _configured or not _activities_by_id.has(activity_id):
		return [] as Array[String]
	return (
		(_activities_by_id[activity_id] as Dictionary).get("tags", []) as Array
	).duplicate()


func query_options(
	resident_id: String,
	social_state: Dictionary,
	current_place: String,
	minute_of_day: int,
	weather: String = "晴天",
) -> Dictionary:
	if not _configured:
		return _failure(NOT_COMPILED, ["Activity Runtime 尚未配置编译数据"])
	var normalized_resident_id := resident_id.strip_edges()
	var normalized_place := current_place.strip_edges()
	if normalized_resident_id.is_empty() or not _places_by_name.has(normalized_place):
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["居民或当前地点状态无效"],
		)
	var occupation := _resolve_occupation(social_state)
	var pressured_tags := _schedule_pressure_tags(
		occupation,
		clampi(minute_of_day, 0, 1439),
	)
	var options: Array[Dictionary] = []
	var activity_ids: Array[String] = []
	for activity_id_value: Variant in _slots_by_activity:
		activity_ids.append(String(activity_id_value))
	activity_ids.sort()
	for activity_id in activity_ids:
		var activity := _activities_by_id.get(activity_id, {}) as Dictionary
		var eligible_slots := _eligible_slots(
			activity_id,
			normalized_place,
			social_state,
			occupation,
		)
		if eligible_slots.is_empty():
			continue
		var preferred_slots: Array[Dictionary] = []
		var reservation_available := false
		for slot_value: Variant in eligible_slots:
			var slot := slot_value as Dictionary
			var member := _first_available_member(slot)
			if not member.is_empty():
				reservation_available = true
			preferred_slots.append({
				"slotId": String(slot.get("slotId", "")),
				"label": String(
					(slot.get("target", {}) as Dictionary).get(
						"propName",
						"",
					)
				),
			})
		var role := String((eligible_slots[0] as Dictionary).get("role", ""))
		var place := _places_by_name.get(normalized_place, {}) as Dictionary
		var weather_evaluation := _weather_policy.evaluate(String(weather),
			String(place.get("spaceId", "")),
			activity,
			role,) as Dictionary
		if not bool(weather_evaluation.get("available", true)):
			reservation_available = false
		var pressured := _arrays_intersect(
			activity.get("tags", []) as Array,
			pressured_tags,
		)
		options.append({
			"activityId": activity_id,
			"label": String(activity.get("label", "")),
			"placeId": normalized_place,
			"role": role,
			"available": reservation_available,
			"disabledReason": (
				""
				if reservation_available
				else (
					String(
						weather_evaluation.get(
							"disabledReason",
							"",
						)
					)
					if not bool(
						weather_evaluation.get("available", true)
					)
					else "ACTIVITY_RESERVATION_CONFLICT"
				)
			),
			"preferredSlots": preferred_slots,
			"_schedulePressure": 1 if pressured else 0,
			"_weatherPreference": int(
				weather_evaluation.get("preference", 0)
			),
			"weatherSuitability": String(
				weather_evaluation.get("suitability", "normal")
			),
			"weatherReason": String(
				weather_evaluation.get("reason", "")
			),
		})
	options.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_pressure := int(left.get("_schedulePressure", 0))
		var right_pressure := int(right.get("_schedulePressure", 0))
		if left_pressure != right_pressure:
			return left_pressure > right_pressure
		var left_weather := int(left.get("_weatherPreference", 0))
		var right_weather := int(right.get("_weatherPreference", 0))
		if left_weather != right_weather:
			return left_weather > right_weather
		return String(left.get("activityId", "")) < String(
			right.get("activityId", "")
		)
	)
	for option in options:
		option.erase("_schedulePressure")
		option.erase("_weatherPreference")
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"options": options,
	}


func weather_context(weather: String, current_place: String) -> Dictionary:
	if not _configured:
		return {}
	var result := (
		_weather_policy.public_context(weather) as Dictionary
	).duplicate(true)
	var alternatives: Array[String] = []
	if String(result.get("outdoorPolicy", "")) in [
		"discouraged",
		"unavailable",
	]:
		for activity_id_value: Variant in _slots_by_activity:
			var activity_id := String(activity_id_value)
			var activity := _activities_by_id.get(
				activity_id,
				{},
			) as Dictionary
			if String(activity.get("kind", "")) not in [
				"leisure",
				"need",
				"service",
				"social",
			]:
				continue
			for slot_value: Variant in (
				_slots_by_activity[activity_id] as Array
			):
				var slot := slot_value as Dictionary
				var place_name := String(
					slot.get("placeName", "")
				)
				var place := _places_by_name.get(
					place_name,
					{},
				) as Dictionary
				if (
					String(place.get("spaceId", "")).begins_with(
						"indoor_"
					)
					and place_name != current_place
					and not alternatives.has(place_name)
				):
					alternatives.append(place_name)
	alternatives.sort()
	if alternatives.size() > 6:
		alternatives.resize(6)
	result["indoorAlternatives"] = alternatives
	return result


func activity_weather_availability(
	activity_id: String,
	place_name: String,
	role: String,
	weather: String,
) -> Dictionary:
	if (
		not _configured
		or not _activities_by_id.has(activity_id)
		or not _places_by_name.has(place_name)
	):
		return {
			"available": false,
			"suitability": "unavailable",
			"preference": -100,
			"reason": "",
			"disabledReason": "ACTIVITY_STATE_CHANGED",
		}
	var place := _places_by_name[place_name] as Dictionary
	return _weather_policy.evaluate(weather,
		String(place.get("spaceId", "")),
		_activities_by_id[activity_id] as Dictionary,
		role,) as Dictionary


func schedule_context(
	social_state: Dictionary,
	minute_of_day: int,
) -> Dictionary:
	if not _configured:
		return {}
	var occupation := _resolve_occupation(social_state)
	if occupation.is_empty():
		return {
			"workExpected": false,
			"scheduleLabel": "",
			"windowId": "",
		}
	var schedule_id := String(
		occupation.get("scheduleTemplateId", "")
	)
	var schedule := _schedules_by_id.get(schedule_id, {}) as Dictionary
	var result := {
		"workExpected": false,
		"scheduleLabel": String(schedule.get("label", "")),
		"windowId": "",
	}
	var normalized_minute := clampi(minute_of_day, 0, 1439)
	for window_value: Variant in schedule.get("windows", []) as Array:
		var window := window_value as Dictionary
		if (
			normalized_minute >= int(window.get("startMinute", 0))
			and normalized_minute < int(window.get("endMinute", 0))
		):
			result["workExpected"] = true
			result["windowId"] = String(window.get("windowId", ""))
			break
	return result


func query_preflight_candidates(
	social_state: Dictionary,
	current_place: String,
	activity_id: String,
) -> Array:
	if not _configured or not _activities_by_id.has(activity_id):
		return []
	var occupation := _resolve_occupation(social_state)
	var result: Array = []
	for slot_value: Variant in _eligible_slots(
		activity_id,
		current_place,
		social_state,
		occupation,
	):
		var slot := slot_value as Dictionary
		result.append_array(_candidate_projections_for_slot(slot))
	return result


func routine_descriptor(
	social_state: Dictionary,
	current_place: String,
	activity_id: String,
) -> Dictionary:
	if not _configured or not _activities_by_id.has(activity_id):
		return {}
	var occupation := _resolve_occupation(social_state)
	var eligible_slots := _eligible_slots(
		activity_id,
		current_place,
		social_state,
		occupation,
	)
	if eligible_slots.is_empty():
		return {}
	var activity := _activities_by_id[activity_id] as Dictionary
	var role := String((eligible_slots[0] as Dictionary).get("role", ""))
	var group := _routine_group(activity, role)
	if group.is_empty():
		return {}
	return {
		"activityId": activity_id,
		"group": group,
		"phase": _routine_phase(activity),
	}


func routine_candidates(
	social_state: Dictionary,
	current_place: String,
	group: String,
) -> Array[Dictionary]:
	if not _configured or group not in ["work", "meal"]:
		return []
	var occupation := _resolve_occupation(social_state)
	var result: Array[Dictionary] = []
	var activity_ids: Array[String] = []
	for activity_id_value: Variant in _slots_by_activity:
		activity_ids.append(String(activity_id_value))
	activity_ids.sort()
	for activity_id in activity_ids:
		var activity := _activities_by_id[activity_id] as Dictionary
		var eligible_slots := _eligible_slots(
			activity_id,
			current_place,
			social_state,
			occupation,
		)
		if eligible_slots.is_empty():
			continue
		var role := String((eligible_slots[0] as Dictionary).get("role", ""))
		if _routine_group(activity, role) != group:
			continue
		var available := false
		for slot_value: Variant in eligible_slots:
			if not _first_available_member(slot_value as Dictionary).is_empty():
				available = true
				break
		result.append({
			"activityId": activity_id,
			"label": String(activity.get("label", "")),
			"phase": _routine_phase(activity),
			"available": available,
		})
	return result


func legacy_activity_mapping(
	social_state: Dictionary,
	place_name: String,
	prop_name: String,
	action_verb: String,
) -> Dictionary:
	if not _configured:
		return _failure(NOT_COMPILED, ["Activity Runtime 尚未配置编译数据"])
	var occupation := _resolve_occupation(social_state)
	var matches_by_activity := {}
	for slot_value: Variant in _slots_by_id.values():
		var slot := slot_value as Dictionary
		var target := slot.get("target", {}) as Dictionary
		if (
			String(slot.get("placeName", "")) == place_name
			and String(slot.get("targetType", "")) == "prop"
			and String(target.get("propName", "")) == prop_name
			and String(target.get("actionVerb", "")) == action_verb
			and _eligible_slots(
				String(slot.get("activityId", "")),
				place_name,
				social_state,
				occupation,
			).any(func(eligible_value: Variant) -> bool:
				return String(
					(eligible_value as Dictionary).get("slotId", "")
				) == String(slot.get("slotId", ""))
				)
			):
				var activity_id := String(slot.get("activityId", ""))
				if not matches_by_activity.has(activity_id):
					matches_by_activity[activity_id] = []
				(matches_by_activity[activity_id] as Array).append(slot)
	var activity_ids: Array = matches_by_activity.keys()
	activity_ids.sort()
	if activity_ids.is_empty():
		return _failure(
			"ACTIVITY_NO_EXECUTABLE_SLOT",
			["旧用道具动作没有唯一、可执行的 activity 映射"],
		)
	if activity_ids.size() > 1:
		return _failure(
			"ACTIVITY_SLOT_REFERENCE_INVALID",
			["旧用道具动作命中多个 activityId，不能无损转换"],
		)
	var activity_id := String(activity_ids[0])
	var matches := matches_by_activity[activity_id] as Array
	matches.sort_custom(func(left: Variant, right: Variant) -> bool:
		return String((left as Dictionary).get("slotId", "")) < String(
			(right as Dictionary).get("slotId", "")
		)
	)
	var slot := matches[0] as Dictionary
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"activityId": activity_id,
		"placeId": place_name,
		"preferredSlotId": String(slot.get("slotId", "")),
	}


func legacy_activity_candidates(
	social_state: Dictionary,
	place_name: String,
	prop_name: String,
	action_verb: String,
) -> Dictionary:
	var mapping := legacy_activity_mapping(
		social_state,
		place_name,
		prop_name,
		action_verb,
	)
	if mapping.get("ok") != true:
		return mapping
	var activity_id := String(mapping.get("activityId", ""))
	var occupation := _resolve_occupation(social_state)
	var candidates := _eligible_slots(
		activity_id,
		place_name,
		social_state,
		occupation,
	)
	var ordered := _ordered_candidates(
		candidates,
		String(mapping.get("preferredSlotId", "")),
	)
	var projections: Array[Dictionary] = []
	for slot_value: Variant in ordered:
		var slot := slot_value as Dictionary
		projections.append(
			_internal_candidate(slot, _first_available_member(slot))
		)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"activityId": activity_id,
		"candidates": projections,
	}


func validate_step(
	resident_id: String,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
	social_state: Dictionary,
	current_place: String,
	weather: String = "晴天",
) -> Dictionary:
	if not _configured:
		return _failure(NOT_COMPILED, ["Activity Runtime 尚未配置编译数据"])
	var shape_error := _validate_step_shape(
		resident_id,
		plan_id,
		plan_revision,
		step,
	)
	if not shape_error.is_empty():
		return _failure("ACTIVITY_STATE_CHANGED", [shape_error])
	var normalized_resident_id := resident_id.strip_edges()
	var target := step.get("target", {}) as Dictionary
	var activity_id := String(target.get("activityId", "")).strip_edges()
	var place_name := String(target.get("placeId", "")).strip_edges()
	var preferred_slot_id := String(
		target.get("preferredSlotId", "")
	).strip_edges()
	var idempotency_key := _idempotency_key(
		normalized_resident_id,
		plan_id,
		plan_revision,
		step,
	)
	var payload_fingerprint := _step_payload_fingerprint(
		normalized_resident_id,
		plan_id,
		plan_revision,
		step,
	)
	if _executions_by_key.has(idempotency_key):
		var previous := _executions_by_key[idempotency_key] as Dictionary
		if String(previous.get("payloadFingerprint", "")) != payload_fingerprint:
			return _failure(
				"ACTIVITY_STATE_CHANGED",
				["相同幂等键不能提交不同 activity.perform 内容"],
			)
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"idempotent": true,
			"execution": _public_execution(previous),
		}
	if not _activities_by_id.has(activity_id):
		return _failure("ACTIVITY_UNKNOWN", ["activityId 不存在"])
	if not _places_by_name.has(place_name):
		return _failure("ACTIVITY_PLACE_MISMATCH", ["placeId 不存在"])
	if current_place.strip_edges() != place_name:
		return _failure(
			"ACTIVITY_REQUIRES_TRAVEL_STEP",
			["居民尚未位于活动地点；必须先显式提交 move.to_place"],
		)
	var occupation := _resolve_occupation(social_state)
	var candidates := _eligible_slots(
		activity_id,
		place_name,
		social_state,
		occupation,
	)
	if candidates.is_empty():
		return _failure(
			"ACTIVITY_NOT_ELIGIBLE",
			["当前职业、工作地或地点能力不允许该活动"],
		)
	var weather_evaluation := activity_weather_availability(
		activity_id,
		place_name,
		String((candidates[0] as Dictionary).get("role", "")),
		weather,
	)
	if not bool(weather_evaluation.get("available", true)):
		return _failure(
			String(
				weather_evaluation.get(
					"disabledReason",
					"ACTIVITY_WEATHER_UNSAFE",
				)
			),
			[
				String(
					weather_evaluation.get(
						"reason",
						"当前天气不适合这项活动。",
					)
				)
			],
		)
	var ordered := _ordered_candidates(candidates, preferred_slot_id)
	if not preferred_slot_id.is_empty() and ordered.is_empty():
		return _failure(
			"ACTIVITY_SLOT_REFERENCE_INVALID",
			["preferredSlotId 不属于同地点、活动与角色"],
		)
	if ordered.is_empty():
		return _failure(
			"ACTIVITY_NO_EXECUTABLE_SLOT",
			["当前活动没有可执行 slot"],
		)
	var candidate_projections: Array[Dictionary] = []
	for slot_value: Variant in ordered:
		var slot := slot_value as Dictionary
		candidate_projections.append_array(
			_candidate_projections_for_slot(slot)
		)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"idempotent": false,
		"stateRevision": _revision,
		"idempotencyKey": idempotency_key,
		"payloadFingerprint": payload_fingerprint,
		"residentId": normalized_resident_id,
		"activityId": activity_id,
		"activityLabel": String(
			(_activities_by_id[activity_id] as Dictionary).get("label", "")
		),
		"placeId": place_name,
		"reason": String(
			(step.get("params", {}) as Dictionary).get("reason", "")
		),
		"actionId": _activity_action_id(
			normalized_resident_id,
			plan_id,
			plan_revision,
			step,
		),
		"preferredRequested": not preferred_slot_id.is_empty(),
		"candidates": candidate_projections,
	}


func reserve_execution(
	validated: Dictionary,
	slot_id: String,
	member_anchor_id: String,
) -> Dictionary:
	if not _configured:
		return _failure(NOT_COMPILED, ["Activity Runtime 尚未配置编译数据"])
	if validated.get("ok") != true or validated.get("idempotent") == true:
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["只能预约本次新鲜 activity.perform 校验结果"],
		)
	if int(validated.get("stateRevision", -1)) != _revision:
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["活动预约状态已变化，必须重新预检"],
			true,
		)
	var selected := {}
	for candidate_value: Variant in validated.get("candidates", []) as Array:
		var candidate := candidate_value as Dictionary
		if (
			String(candidate.get("slotId", "")) == slot_id
			and String(candidate.get("memberAnchorId", "")) == member_anchor_id
		):
			selected = candidate
			break
	if selected.is_empty():
		return _failure(
			"ACTIVITY_SLOT_REFERENCE_INVALID",
			["预约目标不属于已校验候选"],
		)
	if (
		not bool(selected.get("memberAvailable", false))
		or String(selected.get("memberAnchorId", "")).is_empty()
	):
		return _failure(
			"ACTIVITY_RESERVATION_CONFLICT",
			["活动位的真实物理位置已经被占用"],
			true,
		)
	var reservation_key := _reservation_key(slot_id, member_anchor_id)
	if _reservations.has(reservation_key):
		return _failure(
			"ACTIVITY_RESERVATION_CONFLICT",
			["活动位已经由其他居民预约"],
			true,
		)
	var resident_id := String(validated.get("residentId", ""))
	if _active_key_by_resident.has(resident_id):
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["居民已有活动正在执行"],
		)
	var source_contract := String(validated.get("sourceContract", ""))
	var source_action_id := String(validated.get("sourceActionId", ""))
	if not _valid_source_contract(source_contract, source_action_id):
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["activity.perform 内部来源合同无效"],
		)
	_generation += 1
	_revision += 1
	var idempotency_key := String(validated.get("idempotencyKey", ""))
	var activity := _activities_by_id[
		String(validated.get("activityId", ""))
	] as Dictionary
	var reservation := {
		"reservationKey": reservation_key,
		"residentId": resident_id,
		"idempotencyKey": idempotency_key,
		"slotId": slot_id,
		"memberAnchorId": member_anchor_id,
		"generation": _generation,
		"revision": _revision,
	}
	var execution := {
		"idempotencyKey": idempotency_key,
		"payloadFingerprint": String(
			validated.get("payloadFingerprint", "")
		),
		"residentId": resident_id,
		"actionId": String(validated.get("actionId", "")),
		"sourceContract": source_contract,
		"sourceActionId": source_action_id,
		"activityId": String(validated.get("activityId", "")),
		"activityLabel": String(validated.get("activityLabel", "")),
		"placeId": String(validated.get("placeId", "")),
		"role": String(selected.get("role", "")),
		"slotId": slot_id,
		"memberAnchorId": member_anchor_id,
		"targetType": String(selected.get("targetType", "")),
		"targetPropName": String(selected.get("targetPropName", "")),
		"targetActionVerb": String(selected.get("targetActionVerb", "")),
		"reason": String(validated.get("reason", "")),
		"reservationGeneration": _generation,
		"reservationRevision": _revision,
		"remainingTicks": int(activity.get("durationMinutes", 0)),
		"effectCommit": false,
		"committedEffects": {},
		"status": "executing",
	}
	_reservations[reservation_key] = reservation
	_executions_by_key[idempotency_key] = execution
	_active_key_by_resident[resident_id] = idempotency_key
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"execution": execution.duplicate(true),
	}


func execution_for_action(
	resident_id: String,
	action_id: String,
) -> Dictionary:
	var key := String(_active_key_by_resident.get(resident_id, ""))
	if key.is_empty() or not _executions_by_key.has(key):
		return {}
	var execution := _executions_by_key[key] as Dictionary
	if String(execution.get("actionId", "")) != action_id:
		return {}
	return execution.duplicate(true)


func execution_source_matches(
	resident_id: String,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
	source_contract: String,
	source_action_id: String,
) -> bool:
	if (
		not _configured
		or not _valid_source_contract(
			source_contract,
			source_action_id,
		)
	):
		return false
	var key := _idempotency_key(
		resident_id,
		plan_id,
		plan_revision,
		step,
	)
	if not _executions_by_key.has(key):
		return false
	var execution := _executions_by_key[key] as Dictionary
	return (
		String(execution.get("residentId", ""))
		== resident_id.strip_edges()
		and String(execution.get("sourceContract", ""))
		== source_contract
		and String(execution.get("sourceActionId", ""))
		== source_action_id
	)


func sync_remaining_ticks(resident_id: String, remaining_ticks: int) -> void:
	var key := String(_active_key_by_resident.get(resident_id, ""))
	if key.is_empty() or not _executions_by_key.has(key):
		return
	var execution := _executions_by_key[key] as Dictionary
	execution["remainingTicks"] = maxi(0, remaining_ticks)


func complete_action(resident_id: String, action_id: String) -> Dictionary:
	var execution := execution_for_action(resident_id, action_id)
	if execution.is_empty():
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["活动执行元数据不存在或已变化"],
		)
	var key := String(execution.get("idempotencyKey", ""))
	var stored := _executions_by_key[key] as Dictionary
	if String(stored.get("status", "")) != "executing":
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["活动不在可完成的 executing 状态"],
		)
	var activity := _activities_by_id[
		String(stored.get("activityId", ""))
	] as Dictionary
	var effects := (
		activity.get("effects", {}) as Dictionary
	).duplicate(true)
	stored["status"] = "effect_pending"
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"effects": effects,
		"execution": stored.duplicate(true),
	}


func commit_completion(
	resident_id: String,
	action_id: String,
	applied_effects: Dictionary,
) -> Dictionary:
	var execution := execution_for_action(resident_id, action_id)
	if execution.is_empty():
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["活动 effect commit 缺少执行元数据"],
		)
	var key := String(execution.get("idempotencyKey", ""))
	var stored := _executions_by_key[key] as Dictionary
	var activity := _activities_by_id[
		String(stored.get("activityId", ""))
	] as Dictionary
	var expected_effects := activity.get("effects", {}) as Dictionary
	if (
		String(stored.get("status", "")) != "effect_pending"
		or stored.get("effectCommit") == true
		or applied_effects != expected_effects
	):
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["Activity effect commit 与权威定义或执行状态不一致"],
		)
	stored["effectCommit"] = true
	stored["committedEffects"] = applied_effects.duplicate(true)
	stored["remainingTicks"] = 0
	stored["status"] = "completed"
	_release_reservation_for_execution(stored)
	_active_key_by_resident.erase(resident_id)
	_revision += 1
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"execution": _public_execution(stored),
	}


func interrupt_action(
	resident_id: String,
	action_id: String,
	reason: String,
) -> Dictionary:
	var execution := execution_for_action(resident_id, action_id)
	if execution.is_empty():
		return {"ok": true, "changed": false}
	var key := String(execution.get("idempotencyKey", ""))
	var stored := _executions_by_key[key] as Dictionary
	stored["status"] = "interrupted"
	stored["interruptReason"] = reason
	_release_reservation_for_execution(stored)
	_active_key_by_resident.erase(resident_id)
	_revision += 1
	return {
		"ok": true,
		"changed": true,
		"execution": _public_execution(stored),
	}


func fail_action(
	resident_id: String,
	action_id: String,
	error_code: String,
) -> Dictionary:
	var execution := execution_for_action(resident_id, action_id)
	if execution.is_empty():
		return {"ok": true, "changed": false}
	var key := String(execution.get("idempotencyKey", ""))
	var stored := _executions_by_key[key] as Dictionary
	stored["status"] = "failed"
	stored["failureCode"] = error_code
	_release_reservation_for_execution(stored)
	_active_key_by_resident.erase(resident_id)
	_revision += 1
	return {
		"ok": true,
		"changed": true,
		"execution": _public_execution(stored),
	}


func create_save_snapshot() -> Dictionary:
	var reservations: Array[Dictionary] = []
	var reservation_keys: Array[String] = []
	for key_value: Variant in _reservations:
		reservation_keys.append(String(key_value))
	reservation_keys.sort()
	for key in reservation_keys:
		reservations.append(
			(_reservations[key] as Dictionary).duplicate(true)
		)
	var executions: Array[Dictionary] = []
	var execution_keys: Array[String] = []
	for key_value: Variant in _executions_by_key:
		execution_keys.append(String(key_value))
	execution_keys.sort()
	for key in execution_keys:
		executions.append(
			(_executions_by_key[key] as Dictionary).duplicate(true)
		)
	return {
		"schemaVersion": SAVE_SCHEMA_VERSION,
		"sourceFingerprint": _source_fingerprint,
		"generation": _generation,
		"revision": _revision,
		"reservations": reservations,
		"executions": executions,
	}


func prepare_restore(
	value: Variant,
	resident_actions: Dictionary,
) -> Dictionary:
	if not _configured:
		return _failure(NOT_COMPILED, ["Activity Runtime 尚未配置编译数据"])
	if value == null:
		for action_value: Variant in resident_actions.values():
			var action := (
				action_value as Dictionary
				if action_value is Dictionary
				else {}
			)
			if String(action.get("action_id", "")).begins_with("activity-"):
				return _failure(
					"ACTIVITY_STATE_CHANGED",
					["旧 v2 存档缺少 activityRuntime，却包含活动执行动作"],
				)
		return {
			"ok": true,
			"legacyMissing": true,
			"state": _empty_save_state(),
		}
	if not value is Dictionary:
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["activityRuntime 存档字段必须是对象"],
		)
	var state := value as Dictionary
	var allowed := [
		"schemaVersion",
		"sourceFingerprint",
		"generation",
		"revision",
		"reservations",
		"executions",
	]
	if not _has_exact_keys(state, allowed):
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["activityRuntime 存档字段不完整或包含未知字段"],
		)
	if (
		typeof(state.get("schemaVersion")) != TYPE_INT
		or int(state.get("schemaVersion", 0)) != SAVE_SCHEMA_VERSION
		or String(state.get("sourceFingerprint", "")).is_empty()
	):
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["activityRuntime 与当前编译活动数据不一致"],
		)
	if (
		typeof(state.get("generation")) != TYPE_INT
		or typeof(state.get("revision")) != TYPE_INT
		or int(state.get("generation", -1)) < 0
		or int(state.get("revision", -1)) < 0
		or not state.get("reservations") is Array
		or not state.get("executions") is Array
	):
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["activityRuntime 存档计数或集合非法"],
		)
	var migration := TownSaveSchemaRegistry.migrate_activity_runtime_state(
		state,
		_source_fingerprint,
	)
	if migration.get("ok") != true:
		return _failure(
			"ACTIVITY_STATE_CHANGED",
			["activityRuntime 旧存档迁移失败"],
		)
	state = migration.get("state", state) as Dictionary
	var reservation_by_key := {}
	for value_item: Variant in state.get("reservations", []) as Array:
		if not value_item is Dictionary:
			return _failure(
				"ACTIVITY_STATE_CHANGED",
				["activityRuntime reservation 必须是对象"],
			)
		var reservation := value_item as Dictionary
		if not _has_exact_keys(reservation, [
			"reservationKey",
			"residentId",
			"idempotencyKey",
			"slotId",
			"memberAnchorId",
			"generation",
			"revision",
		]):
			return _failure(
				"ACTIVITY_STATE_CHANGED",
				["activityRuntime reservation 字段不完整或包含未知字段"],
			)
		var reservation_key := String(
			reservation.get("reservationKey", "")
		)
		var expected_key := _reservation_key(
			String(reservation.get("slotId", "")),
			String(reservation.get("memberAnchorId", "")),
		)
		if (
			reservation_key.is_empty()
			or reservation_key != expected_key
			or reservation_by_key.has(reservation_key)
			or not _slot_member_exists(
				String(reservation.get("slotId", "")),
				String(reservation.get("memberAnchorId", "")),
			)
			or typeof(reservation.get("generation")) != TYPE_INT
			or typeof(reservation.get("revision")) != TYPE_INT
			or int(reservation.get("generation", 0)) <= 0
			or int(reservation.get("revision", 0)) <= 0
			or int(reservation.get("generation", 0))
			> int(state.get("generation", 0))
			or int(reservation.get("revision", 0))
			> int(state.get("revision", 0))
		):
			return _failure(
				"ACTIVITY_RESERVATION_CONFLICT",
				["activityRuntime reservation 冲突或引用漂移"],
			)
		reservation_by_key[reservation_key] = reservation.duplicate(true)
	var execution_by_key := {}
	var prepared_executions: Array = []
	var active_by_resident := {}
	var matched_reservations := {}
	for value_item: Variant in state.get("executions", []) as Array:
		if not value_item is Dictionary:
			return _failure(
				"ACTIVITY_STATE_CHANGED",
				["activityRuntime execution 必须是对象"],
			)
		var execution := (value_item as Dictionary).duplicate(true)
		var execution_fields := [
			"idempotencyKey",
			"payloadFingerprint",
			"residentId",
			"actionId",
			"sourceContract",
			"sourceActionId",
			"activityId",
			"activityLabel",
			"placeId",
			"role",
			"slotId",
			"memberAnchorId",
			"targetType",
			"targetPropName",
			"targetActionVerb",
			"reason",
			"reservationGeneration",
			"reservationRevision",
			"remainingTicks",
			"effectCommit",
			"committedEffects",
			"status",
		]
		var status := String(execution.get("status", ""))
		if status == "interrupted":
			execution_fields.append("interruptReason")
		elif status == "failed":
			execution_fields.append("failureCode")
		if not _has_exact_keys(execution, execution_fields):
			return _failure(
				"ACTIVITY_STATE_CHANGED",
				["activityRuntime execution 字段不完整或包含未知字段"],
			)
		var key := String(execution.get("idempotencyKey", ""))
		var resident_id := String(execution.get("residentId", ""))
		if (
			key.is_empty()
			or execution_by_key.has(key)
			or not _execution_references_compiled_data(execution)
			or status not in [
				"executing",
				"completed",
				"interrupted",
				"failed",
			]
			or typeof(execution.get("reservationGeneration")) != TYPE_INT
			or typeof(execution.get("reservationRevision")) != TYPE_INT
			or typeof(execution.get("remainingTicks")) != TYPE_INT
			or typeof(execution.get("effectCommit")) != TYPE_BOOL
			or not execution.get("committedEffects") is Dictionary
			or not execution.get("sourceContract") is String
			or not execution.get("sourceActionId") is String
		):
			return _failure(
				"ACTIVITY_STATE_CHANGED",
				["activityRuntime execution 引用漂移或幂等键重复"],
			)
		var compiled_slot := (
			_slots_by_id[String(execution.get("slotId", ""))]
			as Dictionary
		)
		var compiled_target := compiled_slot.get("target", {}) as Dictionary
		execution["targetType"] = String(
			compiled_slot.get("targetType", "")
		)
		execution["targetPropName"] = _target_navigation_prop_name(
			compiled_target,
		)
		execution["targetActionVerb"] = _target_navigation_action_verb(
			compiled_target,
		)
		prepared_executions.append(execution)
		if status == "executing":
			var restored_action := resident_actions.get(
				resident_id,
				{},
			) as Dictionary
			var execution_reservation_key := _reservation_key(
				String(execution.get("slotId", "")),
				String(execution.get("memberAnchorId", "")),
			)
			var linked_reservation := reservation_by_key.get(
				execution_reservation_key,
				{},
			) as Dictionary
			if (
				active_by_resident.has(resident_id)
				or String(restored_action.get("action_id", ""))
				!= String(execution.get("actionId", ""))
				or String(restored_action.get("sourceContract", ""))
				!= String(execution.get("sourceContract", ""))
				or String(restored_action.get("sourceActionId", ""))
				!= String(execution.get("sourceActionId", ""))
				or linked_reservation.is_empty()
				or String(linked_reservation.get("residentId", ""))
				!= resident_id
				or String(linked_reservation.get("idempotencyKey", ""))
				!= key
				or int(linked_reservation.get("generation", -1))
				!= int(execution.get("reservationGeneration", -2))
				or int(linked_reservation.get("revision", -1))
				!= int(execution.get("reservationRevision", -2))
				or execution.get("effectCommit") != false
				or not (
					execution.get("committedEffects", {}) as Dictionary
				).is_empty()
			):
				return _failure(
					"ACTIVITY_STATE_CHANGED",
					["活动执行与居民当前动作或 reservation 不一致"],
				)
			active_by_resident[resident_id] = key
			matched_reservations[execution_reservation_key] = true
		elif (
			String(
				(
					reservation_by_key.get(
						_reservation_key(
							String(execution.get("slotId", "")),
							String(execution.get("memberAnchorId", "")),
						),
						{},
					) as Dictionary
				).get("idempotencyKey", "")
			)
			== key
			or (
				status == "completed"
				and execution.get("effectCommit") != true
			)
			or (
				status in ["interrupted", "failed"]
				and (
					execution.get("effectCommit") != false
					or not (
						execution.get(
							"committedEffects",
							{},
						) as Dictionary
					).is_empty()
				)
			)
		):
			return _failure(
				"ACTIVITY_RESERVATION_CONFLICT",
				["非 executing 活动不得持有 reservation"],
			)
		execution_by_key[key] = execution
	if matched_reservations.size() != reservation_by_key.size():
		return _failure(
			"ACTIVITY_RESERVATION_CONFLICT",
			["activityRuntime 存在没有 executing execution 的孤儿 reservation"],
		)
	var prepared_state := state.duplicate(true)
	# The global source fingerprint changes when unrelated activities or slots
	# are added. The exact reservation/execution checks above are the real
	# compatibility boundary for an existing save. Once every referenced
	# activity, slot, member anchor, action and effect still matches, migrate
	# the prepared state to the current compiled fingerprint.
	prepared_state["sourceFingerprint"] = _source_fingerprint
	prepared_state["executions"] = prepared_executions
	return {
		"ok": true,
		"legacyMissing": false,
		"state": prepared_state,
	}


func apply_prepared_restore(prepared: Dictionary) -> void:
	reset_runtime_state()
	var state := prepared.get("state", {}) as Dictionary
	_generation = int(state.get("generation", 0))
	_revision = int(state.get("revision", 0))
	for value: Variant in state.get("reservations", []) as Array:
		var reservation := (value as Dictionary).duplicate(true)
		_reservations[String(
			reservation.get("reservationKey", "")
		)] = reservation
	for value: Variant in state.get("executions", []) as Array:
		var execution := (value as Dictionary).duplicate(true)
		var key := String(execution.get("idempotencyKey", ""))
		_executions_by_key[key] = execution
		if String(execution.get("status", "")) == "executing":
			_active_key_by_resident[
				String(execution.get("residentId", ""))
			] = key


func _validate_compiled_envelope(
	world_data: Dictionary,
	errors: Array[String],
) -> void:
	var receipt_value: Variant = world_data.get(
		"activityIntegrationReceipt"
	)
	if not receipt_value is Dictionary:
		errors.append("缺少 activityIntegrationReceipt")
		return
	var receipt := receipt_value as Dictionary
	var source_document_value: Variant = receipt.get(
		"sourceDocumentFingerprints"
	)
	var source_document_fingerprints := (
		source_document_value as Dictionary
		if source_document_value is Dictionary
		else {}
	)
	if not _has_exact_keys(receipt, RECEIPT_FIELDS):
		errors.append("activityIntegrationReceipt 字段不完整或包含未知字段")
	if (
		receipt.get("receiptVersion") != 1
		or receipt.get("validator") != "TownWorldActivityValidator"
		or receipt.get("ok") != true
		or receipt.get("validated") != true
		or receipt.get("formalExecutable") != true
		or receipt.get("staticReferencesValidated") != true
		or receipt.get("activityChainVerified") != true
		or receipt.get("placeCapabilitiesVerified") != true
		or receipt.get("scheduleTemplatesResolved") != true
		or String(receipt.get("status", "")) != "formal_executable"
		or String(receipt.get("sourceWorldId", "")).is_empty()
		or String(receipt.get("sourceWorldId", ""))
		!= String(world_data.get("worldId", ""))
		or String(receipt.get("sourceFingerprint", "")).is_empty()
		or not receipt.get("sourceDocumentFingerprints") is Dictionary
		or not _has_exact_keys(
			source_document_fingerprints,
			SOURCE_DOCUMENT_NAMES,
		)
		or not receipt.get("errors") is Array
		or not (receipt.get("errors") as Array).is_empty()
	):
		errors.append("activityIntegrationReceipt 未授权正式执行")
	for document_name in SOURCE_DOCUMENT_NAMES:
		if String(
			source_document_fingerprints.get(document_name, "")
		).is_empty():
			errors.append(
				"activityIntegrationReceipt 文档指纹为空：%s"
				% document_name
			)
	for section in [
		"occupations",
		"activityDefinitions",
		"activitySlots",
		"scheduleTemplates",
	]:
		if (
			not world_data.get(section) is Array
			or (world_data.get(section) as Array).is_empty()
		):
			errors.append("缺少编译活动段：%s" % section)
	var occupation_ids := {}
	var occupation_labels := {}
	for value: Variant in world_data.get("occupations", []) as Array:
		if not value is Dictionary:
			errors.append("occupations 必须只包含对象")
			continue
		var occupation := value as Dictionary
		var occupation_id := String(occupation.get("occupationId", ""))
		var label := String(occupation.get("label", ""))
		if (
			occupation_id.is_empty()
			or label.is_empty()
			or occupation_ids.has(occupation_id)
			or occupation_labels.has(label)
		):
			errors.append("occupations identity 非法或重复")
		occupation_ids[occupation_id] = occupation
		occupation_labels[label] = occupation_id
	var activity_ids := {}
	for value: Variant in world_data.get("activityDefinitions", []) as Array:
		if not value is Dictionary:
			errors.append("activityDefinitions 必须只包含对象")
			continue
		var activity := value as Dictionary
		var activity_id := String(activity.get("activityId", ""))
		if activity_id.is_empty() or activity_ids.has(activity_id):
			errors.append("activityDefinitions activityId 非法或重复")
		activity_ids[activity_id] = activity
	var schedule_ids := {}
	for value: Variant in world_data.get("scheduleTemplates", []) as Array:
		if not value is Dictionary:
			errors.append("scheduleTemplates 必须只包含对象")
			continue
		var schedule := value as Dictionary
		var schedule_id := String(schedule.get("scheduleTemplateId", ""))
		if schedule_id.is_empty() or schedule_ids.has(schedule_id):
			errors.append("scheduleTemplates ID 非法或重复")
		schedule_ids[schedule_id] = schedule
	for occupation_value: Variant in occupation_ids.values():
		var occupation := occupation_value as Dictionary
		if not schedule_ids.has(
			String(occupation.get("scheduleTemplateId", ""))
		):
			errors.append("occupation 引用未编译 scheduleTemplate")
	var places := {}
	for value: Variant in world_data.get("places", []) as Array:
		if value is Dictionary:
			var place := value as Dictionary
			places[String(place.get("name", ""))] = place
	var props := {}
	for value: Variant in world_data.get("props", []) as Array:
		if value is Dictionary:
			var prop := value as Dictionary
			props[String(prop.get("name", ""))] = prop
	var regions := {}
	for value: Variant in world_data.get("perceptionRegions", []) as Array:
		if value is Dictionary:
			var region := value as Dictionary
			regions[String(region.get("id", ""))] = region
	var slot_ids := {}
	for value: Variant in world_data.get("activitySlots", []) as Array:
		if not value is Dictionary:
			errors.append("activitySlots 必须只包含对象")
			continue
		var slot := value as Dictionary
		var slot_id := String(slot.get("slotId", ""))
		var place_name := String(slot.get("placeName", ""))
		var activity_id := String(slot.get("activityId", ""))
		var target := slot.get("target", {}) as Dictionary
		var target_type := String(slot.get("targetType", ""))
		var navigation_prop_name := _target_navigation_prop_name(target)
		if (
			slot_id.is_empty()
			or slot_ids.has(slot_id)
			or not places.has(place_name)
			or not activity_ids.has(activity_id)
			or (
				target_type == "prop"
				and not props.has(navigation_prop_name)
			)
			or (
				target_type not in ["prop", "region"]
				and not navigation_prop_name.is_empty()
				and not props.has(navigation_prop_name)
			)
			or (
				target_type == "region"
				and (
					not regions.has(String(target.get("regionId", "")))
					or String(
						(
							regions.get(
								String(target.get("regionId", "")),
								{},
							) as Dictionary
						).get("placeName", "")
					) != place_name
				)
			)
			or not slot.get("memberAnchors") is Array
			or (
				target_type != "region"
				and (slot.get("memberAnchors") as Array).is_empty()
			)
		):
			errors.append("activitySlots 引用未编译地点、活动、道具或 member")
		slot_ids[slot_id] = slot


func _resolve_occupation(social_state: Dictionary) -> Dictionary:
	var explicit_id := String(
		social_state.get("occupationId", "")
	).strip_edges()
	if not explicit_id.is_empty() and _occupations_by_id.has(explicit_id):
		return _occupations_by_id[explicit_id] as Dictionary
	var label := String(social_state.get("job", "")).strip_edges()
	var occupation_id := String(_occupation_id_by_label.get(label, ""))
	return (
		_occupations_by_id.get(occupation_id, {}) as Dictionary
	)


func _routine_group(activity: Dictionary, role: String) -> String:
	if role == "worker":
		return "work"
	for tag_value: Variant in activity.get("tags", []) as Array:
		if String(tag_value).begins_with("routine.meal."):
			return "meal"
	return ""


func _routine_phase(activity: Dictionary) -> String:
	for tag_value: Variant in activity.get("tags", []) as Array:
		var tag := String(tag_value)
		if tag.begins_with("routine.meal."):
			return tag.trim_prefix("routine.meal.")
	return ""


func _eligible_slots(
	activity_id: String,
	place_name: String,
	social_state: Dictionary,
	occupation: Dictionary,
) -> Array:
	var result := []
	for value: Variant in _slots_by_activity.get(activity_id, []) as Array:
		var slot := value as Dictionary
		if String(slot.get("placeName", "")) != place_name:
			continue
		var role := String(slot.get("role", ""))
		if role == "worker":
			if (
				occupation.is_empty()
				or not _worker_activity_allowed(
					occupation,
					_activities_by_id[activity_id] as Dictionary,
					_places_by_name[place_name] as Dictionary,
					slot,
				)
			):
				continue
		result.append(slot)
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		return String((left as Dictionary).get("slotId", "")) < String(
			(right as Dictionary).get("slotId", "")
		)
	)
	return result


func _worker_activity_allowed(
	occupation: Dictionary,
	activity: Dictionary,
	place: Dictionary,
	slot: Dictionary,
) -> bool:
	if not _arrays_intersect(
		occupation.get("allowedActivityTags", []) as Array,
		activity.get("tags", []) as Array,
	):
		return false
	var place_name := String(place.get("name", ""))
	var primary_workplace := String(
		occupation.get("primaryWorkplacePlace", ""),
	)
	var related_workplaces := occupation.get(
		"relatedWorkplacePlaces",
		[],
	) as Array
	var target := slot.get("target", {}) as Dictionary
	var semantic_region_work := (
		String(slot.get("targetType", "")) == "region"
		and target.get("semanticQuery") is Dictionary
		and not (target.get("semanticQuery") as Dictionary).is_empty()
	)
	if (
		not semantic_region_work
		and
		place_name != primary_workplace
		and not related_workplaces.has(place_name)
	):
		return false
	# The required capability proves the occupation's home base. A related
	# place is usable only through an authored activity and a real work task;
	# it does not need to pretend it owns the home-base capability.
	if semantic_region_work or place_name != primary_workplace:
		return true
	var capabilities := place.get("capabilities", {}) as Dictionary
	for value: Variant in occupation.get(
		"requiredPlaceCapabilitiesAny",
		[],
	) as Array:
		if capabilities.get(String(value)) == true:
			return true
	return false


func _ordered_candidates(
	candidates: Array,
	preferred_slot_id: String,
) -> Array:
	if preferred_slot_id.is_empty():
		return candidates.duplicate()
	var preferred := {}
	for value: Variant in candidates:
		var slot := value as Dictionary
		if String(slot.get("slotId", "")) == preferred_slot_id:
			preferred = slot
			break
	if preferred.is_empty():
		return []
	var result := [preferred]
	if String(preferred.get("fallback", "")) != "same_activity_other_slot":
		return result
	for value: Variant in candidates:
		var slot := value as Dictionary
		if (
			String(slot.get("slotId", "")) != preferred_slot_id
			and String(slot.get("placeName", ""))
			== String(preferred.get("placeName", ""))
			and String(slot.get("activityId", ""))
			== String(preferred.get("activityId", ""))
			and String(slot.get("role", ""))
			== String(preferred.get("role", ""))
			and String(slot.get("targetType", ""))
			== String(preferred.get("targetType", ""))
		):
			result.append(slot)
			break
	return result


func _first_available_member(slot: Dictionary) -> Dictionary:
	var members := (slot.get("memberAnchors", []) as Array).duplicate(true)
	members.sort_custom(func(left: Variant, right: Variant) -> bool:
		return String((left as Dictionary).get("memberAnchorId", "")) < String(
			(right as Dictionary).get("memberAnchorId", "")
		)
	)
	for value: Variant in members:
		var member := value as Dictionary
		var key := _reservation_key(
			String(slot.get("slotId", "")),
			String(member.get("memberAnchorId", "")),
		)
		if not _reservations.has(key):
			return member
	return {}


func _internal_candidate(
	slot: Dictionary,
	member: Dictionary,
) -> Dictionary:
	var target := slot.get("target", {}) as Dictionary
	var position := member.get("position", []) as Array
	return {
		"slotId": String(slot.get("slotId", "")),
		"memberAnchorId": String(member.get("memberAnchorId", "")),
		"memberAvailable": not member.is_empty(),
		"memberPosition": position.duplicate(),
		"placeId": String(slot.get("placeName", "")),
		"activityId": String(slot.get("activityId", "")),
		"role": String(slot.get("role", "")),
		"sceneId": String(slot.get("sceneId", "")),
		"targetType": String(slot.get("targetType", "")),
		"targetPropName": _target_navigation_prop_name(target),
		"targetActionVerb": _target_navigation_action_verb(target),
		"targetRegionId": String(target.get("regionId", "")),
	}


func _candidate_projections_for_slot(
	slot: Dictionary,
) -> Array[Dictionary]:
	if String(slot.get("targetType", "")) != "region":
		return [
			_internal_candidate(
				slot,
				_first_available_member(slot),
			),
		]
	var result: Array[Dictionary] = []
	for value: Variant in slot.get("memberAnchors", []) as Array:
		var member := value as Dictionary
		var reservation_key := _reservation_key(
			String(slot.get("slotId", "")),
			String(member.get("memberAnchorId", "")),
		)
		if _reservations.has(reservation_key):
			continue
		result.append(_internal_candidate(slot, member))
	return result


func _target_navigation_prop_name(target: Dictionary) -> String:
	return String(
		target.get(
			"propName",
			target.get(
				"navigationPropName",
				target.get("navigationLabel", ""),
			),
		)
	)


func _target_navigation_action_verb(target: Dictionary) -> String:
	return String(
		target.get(
			"actionVerb",
			target.get("navigationActionVerb", ""),
		)
	)


func _expanded_region_slots(slot: Dictionary) -> Array[Dictionary]:
	if String(slot.get("targetType", "")) != "region":
		return [slot]
	var authored_target := slot.get("target", {}) as Dictionary
	var semantic_query_value: Variant = authored_target.get("semanticQuery")
	if (
		semantic_query_value is not Dictionary
		or (semantic_query_value as Dictionary).is_empty()
	):
		return [slot]
	var semantic_query := semantic_query_value as Dictionary
	var regions: Array[Dictionary] = []
	for region_value: Variant in _regions_by_id.values():
		var region := region_value as Dictionary
		var place_name := String(region.get("placeName", ""))
		if (
			String(region.get("spaceId", "")) != "town_outdoor"
			or not _places_by_name.has(place_name)
			or not _semantic_query_matches_place(
				semantic_query,
				_places_by_name[place_name] as Dictionary,
			)
		):
			continue
		regions.append(region)
	regions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("id", "")) < String(right.get("id", ""))
	)
	var result: Array[Dictionary] = []
	var authored_region_id := String(authored_target.get("regionId", ""))
	for region: Dictionary in regions:
		var region_id := String(region.get("id", ""))
		var expanded := slot.duplicate(true)
		var expanded_target := (
			expanded.get("target", {}) as Dictionary
		).duplicate(true)
		expanded_target["regionId"] = region_id
		expanded["target"] = expanded_target
		expanded["placeName"] = String(region.get("placeName", ""))
		if region_id != authored_region_id:
			expanded["slotId"] = "%s__%s" % [
				String(slot.get("slotId", "")),
				region_id,
			]
		result.append(expanded)
	return result


func _semantic_query_matches_place(
	query: Dictionary,
	place: Dictionary,
) -> bool:
	var declared_condition := false
	var visible_features_any := query.get(
		"visibleFeaturesAny",
		[],
	) as Array
	if not visible_features_any.is_empty():
		declared_condition = true
		if not _arrays_intersect(
			visible_features_any,
			place.get("visibleFeatures", []) as Array,
		):
			return false
	var capabilities_any := query.get(
		"placeCapabilitiesAny",
		[],
	) as Array
	if not capabilities_any.is_empty():
		declared_condition = true
		var capabilities := place.get("capabilities", {}) as Dictionary
		var capability_matched := false
		for value: Variant in capabilities_any:
			if capabilities.get(String(value)) == true:
				capability_matched = true
				break
		if not capability_matched:
			return false
	return declared_condition


func _region_members_for_slot(
	slot: Dictionary,
	world_data: Dictionary,
) -> Array[Dictionary]:
	var target := slot.get("target", {}) as Dictionary
	var region_id := String(target.get("regionId", ""))
	var region := _regions_by_id.get(region_id, {}) as Dictionary
	if (
		region.is_empty()
		or String(region.get("placeName", ""))
		!= String(slot.get("placeName", ""))
		or String(region.get("spaceId", "")) != "town_outdoor"
	):
		return []
	var candidates: Array[Vector2] = []
	var shared_cache_key := "%s:%s" % [
		_region_cache_namespace,
		region_id,
	]
	if _region_member_positions_by_id.has(region_id):
		candidates.assign(
			_region_member_positions_by_id[region_id] as Array
		)
	elif _shared_region_member_positions.has(shared_cache_key):
		candidates.assign(
			_shared_region_member_positions[shared_cache_key] as Array
		)
		_region_member_positions_by_id[region_id] = candidates.duplicate()
	else:
		candidates = _safe_region_work_positions(
			region,
			world_data,
		)
		_region_member_positions_by_id[region_id] = candidates.duplicate()
		_shared_region_member_positions[shared_cache_key] = candidates.duplicate()
	var members: Array[Dictionary] = []
	for index in candidates.size():
		var member_index := index + 1
		members.append({
			"memberAnchorId": "member_region_%s_%02d" % [
				String(slot.get("slotId", "")).trim_prefix("slot_"),
				member_index,
			],
			"anchorId": "region_point_%02d" % member_index,
			"position": [
				snappedf(candidates[index].x, 0.001),
				snappedf(candidates[index].y, 0.001),
			],
		})
	return members


func _safe_region_work_positions(
	region: Dictionary,
	world_data: Dictionary,
) -> Array[Vector2]:
	var shape := region.get("shape", {}) as Dictionary
	if String(shape.get("type", "")) != "grid_cells":
		return []
	var cell_size := float(shape.get("cellSize", 0.0))
	if cell_size <= 0.0:
		return []
	var forbidden_points := _region_work_forbidden_points(world_data)
	_ensure_outdoor_route_sample_index(world_data)
	var ranked_candidates: Array[Dictionary] = []
	var region_seed := hash(String(region.get("id", "")))
	for value: Variant in shape.get("cells", []) as Array:
		if value is not Array or (value as Array).size() != 2:
			continue
		var pair := value as Array
		var candidate := Vector2(
			(float(pair[0]) + 0.5) * cell_size,
			(float(pair[1]) + 0.5) * cell_size,
		)
		if _region_work_point_is_forbidden(
				candidate,
				forbidden_points,
			):
			continue
		var cell_x := int(pair[0])
		var cell_y := int(pair[1])
		ranked_candidates.append({
			"position": candidate,
			"rank": posmod(
				(cell_x * 73856093) ^ (cell_y * 19349663) ^ region_seed,
				2147483647,
			),
		})
	ranked_candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_rank := int(left.get("rank", 0))
		var right_rank := int(right.get("rank", 0))
		if left_rank != right_rank:
			return left_rank < right_rank
		var left_position := left.get("position", Vector2.ZERO) as Vector2
		var right_position := right.get("position", Vector2.ZERO) as Vector2
		return (
			left_position.y < right_position.y
			or (
				is_equal_approx(left_position.y, right_position.y)
				and left_position.x < right_position.x
			)
		)
	)
	var result: Array[Vector2] = []
	for ranked: Dictionary in ranked_candidates:
		var candidate := ranked.get("position", Vector2.ZERO) as Vector2
		var route_samples := _region_work_route_samples(candidate)
		if (
			route_samples.is_empty()
			or _point_near_region_candidates(
				candidate,
				result,
				REGION_WORK_POINT_SPACING_PX,
			)
			or not ROUTE_QUERY.outdoor_polyline_is_safe([candidate])
			or not _region_work_point_connects_to_route(
				candidate,
				route_samples,
			)
		):
			continue
		result.append(candidate)
		if result.size() >= REGION_WORK_MEMBER_LIMIT:
			break
	return result


func _ensure_outdoor_route_sample_index(world_data: Dictionary) -> void:
	if not _outdoor_route_samples_by_cell.is_empty():
		return
	var movement := world_data.get("movementNetwork", {}) as Dictionary
	for value: Variant in movement.get("edges", []) as Array:
		var edge := value as Dictionary
		var points: Array[Vector2] = []
		for point_value: Variant in edge.get("polyline", []) as Array:
			if point_value is not Dictionary:
				continue
			var point := point_value as Dictionary
			points.append(Vector2(
				float(point.get("x", 0.0)),
				float(point.get("y", 0.0)),
			))
		for index in range(1, points.size()):
			var from := points[index - 1]
			var to := points[index]
			var steps := maxi(
				1,
				ceili(from.distance_to(to) / REGION_WORK_ROUTE_SAMPLE_STEP_PX),
			)
			for step in range(steps + 1):
				_add_outdoor_route_sample(
					from.lerp(to, float(step) / float(steps)),
				)


func _add_outdoor_route_sample(position: Vector2) -> void:
	var key := _route_sample_cell(position)
	var samples := _outdoor_route_samples_by_cell.get(key, []) as Array
	for value: Variant in samples:
		if (value as Vector2).distance_squared_to(position) <= 1.0:
			return
	samples.append(position)
	_outdoor_route_samples_by_cell[key] = samples


func _region_work_route_samples(position: Vector2) -> Array[Vector2]:
	var center := Vector2i(
		floori(position.x / REGION_WORK_ROUTE_INDEX_CELL_PX),
		floori(position.y / REGION_WORK_ROUTE_INDEX_CELL_PX),
	)
	var nearby: Array[Vector2] = []
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var key := "%d:%d" % [
				center.x + offset_x,
				center.y + offset_y,
			]
			for value: Variant in _outdoor_route_samples_by_cell.get(
				key,
				[],
			) as Array:
				var sample := value as Vector2
				if position.distance_to(sample) <= REGION_WORK_ROUTE_CONNECTION_PX:
					nearby.append(sample)
	nearby.sort_custom(func(left: Vector2, right: Vector2) -> bool:
		return position.distance_squared_to(left) < position.distance_squared_to(right)
	)
	return nearby


func _region_work_point_connects_to_route(
	position: Vector2,
	nearby: Array[Vector2],
) -> bool:
	for sample: Vector2 in nearby:
		if ROUTE_QUERY.outdoor_polyline_is_safe([position, sample]):
			return true
	return false


func _route_sample_cell(position: Vector2) -> String:
	return "%d:%d" % [
		floori(position.x / REGION_WORK_ROUTE_INDEX_CELL_PX),
		floori(position.y / REGION_WORK_ROUTE_INDEX_CELL_PX),
	]


func _region_work_forbidden_points(
	world_data: Dictionary,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var movement := world_data.get("movementNetwork", {}) as Dictionary
	for value: Variant in movement.get("nodes", []) as Array:
		var node := value as Dictionary
		if (
			String(node.get("spaceId", "")) != "town_outdoor"
			or not String(node.get("id", "")).begins_with("portal_")
		):
			continue
		var point := node.get("position", {}) as Dictionary
		result.append({
			"position": Vector2(
				float(point.get("x", 0.0)),
				float(point.get("y", 0.0)),
			),
			"clearance": REGION_WORK_PORTAL_CLEARANCE_PX,
		})
	for value: Variant in world_data.get("props", []) as Array:
		var interaction := (
			(value as Dictionary).get("interaction", {}) as Dictionary
		)
		if String(interaction.get("spaceId", "")) != "town_outdoor":
			continue
		var position_value: Variant = interaction.get("position")
		if position_value is not Array or (position_value as Array).size() != 2:
			continue
		var pair := position_value as Array
		result.append({
			"position": Vector2(float(pair[0]), float(pair[1])),
			"clearance": REGION_WORK_PROP_CLEARANCE_PX,
		})
	return result


func _region_work_point_is_forbidden(
	position: Vector2,
	forbidden_points: Array[Dictionary],
) -> bool:
	for forbidden: Dictionary in forbidden_points:
		if position.distance_to(
			forbidden.get("position", Vector2.INF) as Vector2,
		) < float(forbidden.get("clearance", 0.0)):
			return true
	return false


func _point_near_region_candidates(
	point: Vector2,
	candidates: Array[Vector2],
	clearance: float,
) -> bool:
	for candidate: Vector2 in candidates:
		if point.distance_to(candidate) < clearance:
			return true
	return false


func _validate_step_shape(
	resident_id: String,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
) -> String:
	if not _has_exact_keys(step, STEP_FIELDS):
		return "activity.perform 顶层字段不完整或包含未知字段"
	if step.get("operation") != OPERATION:
		return "operation 必须为 activity.perform"
	if resident_id.strip_edges().is_empty():
		return "residentId 执行上下文必须为非空稳定文本"
	if plan_id.strip_edges().is_empty():
		return "planId 执行上下文必须为非空稳定文本"
	if plan_revision < 0:
		return "planRevision 必须为非负整数"
	if (
		not step.get("stepId") is String
		or String(step.get("stepId", "")).strip_edges().is_empty()
	):
		return "stepId 必须为非空稳定文本"
	if not step.get("target") is Dictionary:
		return "target 必须为对象"
	var target := step.get("target") as Dictionary
	for key_value: Variant in target:
		if not key_value is String or key_value not in TARGET_FIELDS:
			return "target 包含未知字段：%s" % str(key_value)
	for field in ["activityId", "placeId"]:
		if (
			not target.get(field) is String
			or String(target.get(field, "")).strip_edges().is_empty()
		):
			return "target.%s 必须为非空文本" % field
	if target.has("preferredSlotId") and (
		not target.get("preferredSlotId") is String
		or String(target.get("preferredSlotId", "")).strip_edges().is_empty()
	):
		return "target.preferredSlotId 必须为非空文本"
	if not step.get("params") is Dictionary:
		return "params 必须为对象"
	var params := step.get("params") as Dictionary
	for key_value: Variant in params:
		if not key_value is String or key_value not in PARAM_FIELDS:
			return "params 包含未知字段：%s" % str(key_value)
	if params.has("reason") and not params.get("reason") is String:
		return "params.reason 必须为文本"
	return ""


func _schedule_pressure_tags(
	occupation: Dictionary,
	minute_of_day: int,
) -> Array:
	if occupation.is_empty():
		return []
	var schedule_id := String(
		occupation.get("scheduleTemplateId", "")
	)
	var schedule := _schedules_by_id.get(schedule_id, {}) as Dictionary
	for value: Variant in schedule.get("windows", []) as Array:
		var window := value as Dictionary
		if (
			minute_of_day >= int(window.get("startMinute", 0))
			and minute_of_day < int(window.get("endMinute", 0))
		):
			return (
				window.get("activityTagsAny", []) as Array
			).duplicate()
	return []


func _release_reservation_for_execution(execution: Dictionary) -> void:
	_reservations.erase(
		_reservation_key(
			String(execution.get("slotId", "")),
			String(execution.get("memberAnchorId", "")),
		)
	)


func _slot_member_exists(slot_id: String, member_anchor_id: String) -> bool:
	if not _slots_by_id.has(slot_id):
		return false
	for value: Variant in (
		_slots_by_id[slot_id] as Dictionary
	).get("memberAnchors", []) as Array:
		if String((value as Dictionary).get("memberAnchorId", "")) == member_anchor_id:
			return true
	return false


func _execution_references_compiled_data(execution: Dictionary) -> bool:
	var activity_id := String(execution.get("activityId", ""))
	var slot_id := String(execution.get("slotId", ""))
	var member_id := String(execution.get("memberAnchorId", ""))
	if (
		not _activities_by_id.has(activity_id)
		or not _slots_by_id.has(slot_id)
		or not _slot_member_exists(slot_id, member_id)
	):
		return false
	var slot := _slots_by_id[slot_id] as Dictionary
	var target := slot.get("target", {}) as Dictionary
	var activity := _activities_by_id[activity_id] as Dictionary
	var committed_effects := (
		execution.get("committedEffects", {}) as Dictionary
	)
	return (
		_valid_source_contract(
			String(execution.get("sourceContract", "")),
			String(execution.get("sourceActionId", "")),
		)
		and String(slot.get("activityId", "")) == activity_id
		and String(slot.get("placeName", ""))
		== String(execution.get("placeId", ""))
		and String(slot.get("role", ""))
		== String(execution.get("role", ""))
		and String(execution.get("targetType", "")) in [
			"prop",
			"point",
			"region",
			"route",
		]
		and _target_navigation_prop_name(target)
		== String(execution.get("targetPropName", ""))
		and _target_navigation_action_verb(target)
		== String(execution.get("targetActionVerb", ""))
		and String(activity.get("label", ""))
		== String(execution.get("activityLabel", ""))
		and (
			String(execution.get("status", "")) != "completed"
			or _effects_match_compiled_contract(
				committed_effects,
				activity.get("effects", {}) as Dictionary,
			)
		)
	)


func _effects_match_compiled_contract(
	actual: Dictionary,
	expected: Dictionary,
) -> bool:
	if not _has_exact_keys(actual, expected.keys()):
		return false
	for key_value: Variant in expected:
		var actual_value: Variant = actual.get(key_value)
		var expected_value: Variant = expected.get(key_value)
		if (
			typeof(actual_value) not in [TYPE_INT, TYPE_FLOAT]
			or typeof(expected_value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(actual_value))
			or not is_finite(float(expected_value))
			or float(actual_value) != float(expected_value)
		):
			return false
	return true


func _valid_source_contract(
	source_contract: String,
	source_action_id: String,
) -> bool:
	if source_contract == SOURCE_CONTRACT_DIRECT:
		return source_action_id.is_empty()
	if source_contract == SOURCE_CONTRACT_LEGACY_PROP:
		return (
			not source_action_id.is_empty()
			and source_action_id == source_action_id.strip_edges()
		)
	if source_contract == SOURCE_CONTRACT_AGENT_ACTIVITY:
		return (
			not source_action_id.is_empty()
			and source_action_id == source_action_id.strip_edges()
		)
	return false


func _public_execution(execution: Dictionary) -> Dictionary:
	return {
		"activityId": String(execution.get("activityId", "")),
		"label": String(execution.get("activityLabel", "")),
		"placeId": String(execution.get("placeId", "")),
		"role": String(execution.get("role", "")),
		"status": String(execution.get("status", "")),
	}


func _idempotency_key(
	resident_id: String,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
) -> String:
	return "%s%s%s%s%s%s%d" % [
		resident_id.strip_edges(),
		IDEMPOTENCY_KEY_SEPARATOR,
		plan_id.strip_edges(),
		IDEMPOTENCY_KEY_SEPARATOR,
		String(step.get("stepId", "")).strip_edges(),
		IDEMPOTENCY_KEY_SEPARATOR,
		plan_revision,
	]


func _activity_action_id(
	resident_id: String,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
) -> String:
	return "activity-%s" % _sha256_text(
		"%s%s%s%s%s%s%d" % [
			resident_id.strip_edges(),
			IDEMPOTENCY_KEY_SEPARATOR,
			plan_id.strip_edges(),
			IDEMPOTENCY_KEY_SEPARATOR,
			String(step.get("stepId", "")).strip_edges(),
			IDEMPOTENCY_KEY_SEPARATOR,
			plan_revision,
		]
	)


func _step_payload_fingerprint(
	resident_id: String,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
) -> String:
	var target := step.get("target", {}) as Dictionary
	var params := step.get("params", {}) as Dictionary
	return JSON.stringify({
		"operation": String(step.get("operation", "")),
		"residentId": resident_id.strip_edges(),
		"planId": plan_id.strip_edges(),
		"stepId": String(step.get("stepId", "")),
		"planRevision": plan_revision,
		"target": {
			"activityId": String(target.get("activityId", "")),
			"placeId": String(target.get("placeId", "")),
			"preferredSlotId": String(target.get("preferredSlotId", "")),
		},
		"params": {"reason": String(params.get("reason", ""))},
	})


func _reservation_key(slot_id: String, member_anchor_id: String) -> String:
	var slot := _slots_by_id.get(slot_id, {}) as Dictionary
	for member_value: Variant in slot.get("memberAnchors", []) as Array:
		var member := member_value as Dictionary
		if String(member.get("memberAnchorId", "")) != member_anchor_id:
			continue
		var position := member.get("position", []) as Array
		if position.size() == 2:
			return "%s\u001f%s,%s" % [
				String(slot.get("sceneId", "")),
				str(position[0]),
				str(position[1]),
			]
	return "%s\u001f%s" % [slot_id, member_anchor_id]


func _sha256_text(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


func _empty_save_state() -> Dictionary:
	return {
		"schemaVersion": SAVE_SCHEMA_VERSION,
		"sourceFingerprint": _source_fingerprint,
		"generation": 0,
		"revision": 0,
		"reservations": [],
		"executions": [],
	}


func _clear_configuration() -> void:
	_configured = false
	_source_fingerprint = ""
	_region_cache_namespace = ""
	_occupations_by_id.clear()
	_occupation_id_by_label.clear()
	_activities_by_id.clear()
	_slots_by_id.clear()
	_slots_by_activity.clear()
	_places_by_name.clear()
	_regions_by_id.clear()
	_region_member_positions_by_id.clear()
	_outdoor_route_samples_by_cell.clear()
	_schedules_by_id.clear()
	reset_runtime_state()


func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key_value: Variant in expected:
		if not value.has(key_value):
			return false
	return true


func _arrays_intersect(left: Array, right: Array) -> bool:
	for value: Variant in left:
		if value in right:
			return true
	return false


func _failure(
	error_code: String,
	errors: Array,
	retryable := false,
) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"errors": errors.duplicate(true),
	}
