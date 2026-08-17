class_name TownResidentConditionAdvancementRuntime
extends RefCounted


const EXPOSURE_WEATHER := ["小雨", "中雨", "大雨", "雷暴", "下雪"]


static func advance(host, absolute_minute: int) -> void:
	var weather: String = host.get_weather()
	var weather_is_exposure := weather in EXPOSURE_WEATHER
	for resident_id in host.resident_registry.order:
		var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
		if not host.resident_is_present(resident):
			continue
		var outdoors := String(resident.get("spaceId", "")) == "town_outdoor"
		var active := host._resident_conditions.get_active_exposure(
			resident_id,
		) as Dictionary
		var active_facts := active.get("facts", {}) as Dictionary
		var exposure_still_matches := (
			not active.is_empty()
			and outdoors
			and weather_is_exposure
			and String(active_facts.get("weather", "")) == weather
		)
		if not active.is_empty() and not exposure_still_matches:
			host._resident_conditions.end_ambient_exposure(
				resident_id,
				String(active.get("exposureId", "")),
			)
			active = {}
		if active.is_empty() and outdoors and weather_is_exposure:
			var started := host._resident_conditions.begin_world_weather_exposure(
				resident_id,
				{
					"exposureId": "weather-exposure:%s:%d" % [resident_id, absolute_minute],
					"sourceKind": "weather_exposure",
					"sourceRef": "weather:%s:%d" % [weather, absolute_minute],
					"startedAtMinute": absolute_minute,
					"weather": weather,
					"outdoors": true,
					"placeId": String(resident.get("currentPlace", "")),
					"riskTags": ["weather_exposure"],
				},
			) as Dictionary
			if started.get("ok") == true:
				active = host._resident_conditions.get_active_exposure(
					resident_id,
				) as Dictionary
		var context := {
			"riskTags": (
				(active.get("riskTags", []) as Array).duplicate()
				if not active.is_empty()
				else []
			),
			"reliefTags": [],
			"lifeState": host.CLINIC_CONDITION_SETTLEMENT_RUNTIME.life_state(host, resident),
		}
		var advanced := host._resident_conditions.advance_resident(
			resident_id,
			absolute_minute,
			context,
		) as Dictionary
		if advanced.get("ok") == true and not (advanced.get("events", []) as Array).is_empty():
			host.CLINIC_CONDITION_SETTLEMENT_RUNTIME.record_condition_result(host, resident_id, advanced)
			host._bump_world_revision(false)
			host._emit_resident_state_changed(resident_id)
