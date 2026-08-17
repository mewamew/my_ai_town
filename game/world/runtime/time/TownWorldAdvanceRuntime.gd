class_name TownWorldAdvanceRuntime
extends RefCounted


const ACTION_PREVIEW_RUNTIME := preload(
	"res://world/runtime/action/TownActionPreviewRuntime.gd"
)


const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const ACTION_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/action/TownActionAdvancementRuntime.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const CONFLICT_WORLD_COORDINATION_RUNTIME := preload(
	"res://world/runtime/conflict/TownConflictWorldCoordinationRuntime.gd"
)
const PRODUCTION_TASK_COORDINATION_RUNTIME := preload(
	"res://world/runtime/work/TownProductionTaskCoordinationRuntime.gd"
)
const PLACE_SERVICE_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownPlaceServiceCommandRuntime.gd"
)
const SOCIAL_MATTER_COMMAND_RUNTIME := preload(
	"res://world/runtime/social/TownSocialMatterCommandRuntime.gd"
)
const AGENT_DECISION_SCHEDULING_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentDecisionSchedulingRuntime.gd"
)
const RESIDENT_ARRIVAL_RUNTIME := preload(
	"res://world/runtime/TownResidentArrivalRuntime.gd"
)
const RESIDENT_CONDITION_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentConditionAdvancementRuntime.gd"
)
const PRIVATE_MESSAGE_DELIVERY_RUNTIME := preload(
	"res://world/runtime/social/TownPrivateMessageDeliveryRuntime.gd"
)
const OCCUPATION_SERVICE_PRESENCE_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServicePresenceAdvancementRuntime.gd"
)
const ANNOUNCEMENT_RESIDENT_RUNTIME := preload(
	"res://world/runtime/social/TownAnnouncementResidentRuntime.gd"
)
const PASSIVE_NEED_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/activity/TownPassiveNeedAdvancementRuntime.gd"
)


static func advance(host, real_seconds: float, community_bulletin) -> Dictionary:
	var advance_started_usec := Time.get_ticks_usec() if host.telemetry.advance_profile_enabled else 0
	var advance_profile: Dictionary = host.telemetry.begin_advance_profile()
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if host.is_paused():
		return host._decorate_command_result({
			"ok": true,
			"paused": true,
			"simulationSpeed": host._simulation_speed,
			"pauseReasons": host.get_lifecycle_state().get("pauseReasons", []),
			"minutesAdvanced": 0,
			"events": [],
		})
	var deferred_work: Dictionary = host.frame_budget_runtime.process_deferred_work(
		host,
		advance_profile,
		host._traveler_relationship_state,
	)
	var processed_presentation_refreshes := int(
		deferred_work.get("presentationProcessed", 0)
	)
	var processed_place_change_signals := int(deferred_work.get("placeProcessed", 0))
	var processed_deferred_perception := bool(deferred_work.get("perceptionProcessed", false))
	CONVERSATION_RUNTIME._advance_autonomous_conversation_timeouts(
		host,
		host._traveler_relationship_state,
		real_seconds,
	)
	var environment_update := host._environment.advance(
		real_seconds * float(host._simulation_speed),
	) as Dictionary
	if int(environment_update.get("minutesAdvanced", 0)) > 0:
		host._bump_world_revision(false)
	for time_value: Variant in environment_update.get("minuteTicks", []) as Array:
		var minute_tick := time_value as Dictionary
		# 环境时钟已一次推进到终态，逐分钟结算必须使用当前 tick 的分钟。
		host._processing_tick_absolute_minute = host.ACTION_SUPPORT.absolute_minute(minute_tick)
		host._tick_weather_override = String(minute_tick.get("weather", ""))
		if bool(minute_tick.get("weatherChanged", false)):
			host.ACTIVITY_AVAILABILITY_RUNTIME.interrupt_unsafe_weather(host)
		var absolute_minute: int = host.ACTION_SUPPORT.absolute_minute(minute_tick)
		var lap_usec := Time.get_ticks_usec() if host.telemetry.advance_profile_enabled else 0
		RESIDENT_ARRIVAL_RUNTIME.advance(
			host, absolute_minute, host.IDLE_RESIDENT_CLEARANCE_PX,
		)
		lap_usec = host.telemetry.lap(advance_profile, "residentArrivalsUsec", lap_usec)
		ACTION_ADVANCEMENT_RUNTIME.advance_all(host, absolute_minute)
		lap_usec = host.telemetry.lap(advance_profile, "actionsUsec", lap_usec)
		RESIDENT_CONDITION_ADVANCEMENT_RUNTIME.advance(host, absolute_minute)
		lap_usec = host.telemetry.lap(advance_profile, "residentConditionsUsec", lap_usec)
		CONFLICT_WORLD_COORDINATION_RUNTIME.advance(host)
		lap_usec = host.telemetry.lap(advance_profile, "conflictUsec", lap_usec)
		PRIVATE_MESSAGE_DELIVERY_RUNTIME.expire_time_sensitive(host, absolute_minute)
		lap_usec = host.telemetry.lap(advance_profile, "privateMessageExpiryUsec", lap_usec)
		DINING_SERVICE.settle_period_close(host, absolute_minute)
		OCCUPATION_SERVICE_PRESENCE_ADVANCEMENT_RUNTIME.sync(host, absolute_minute)
		lap_usec = host.telemetry.lap(advance_profile, "occupationPresenceUsec", lap_usec)
		SOCIAL_MATTER_COMMAND_RUNTIME.advance(host, absolute_minute)
		lap_usec = host.telemetry.lap(advance_profile, "socialMattersUsec", lap_usec)
		ANNOUNCEMENT_RESIDENT_RUNTIME.advance_schedules(
			host, community_bulletin, absolute_minute,
		)
		PASSIVE_NEED_ADVANCEMENT_RUNTIME.advance(host, absolute_minute)
		lap_usec = host.telemetry.lap(advance_profile, "passiveNeedsUsec", lap_usec)
		if posmod(absolute_minute, 30) == 0:
			host._work.staffing.rebuild_if_dependencies_changed(
				host.resident_registry.records,
				absolute_minute,
			)
			lap_usec = host.telemetry.lap(advance_profile, "staffingRebuildUsec", lap_usec)
			PLACE_SERVICE_COMMAND_RUNTIME.refresh_staffing(host)
			lap_usec = host.telemetry.lap(advance_profile, "placeServiceUsec", lap_usec)
			host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.sync_staffing_matters(host)
			lap_usec = host.telemetry.lap(advance_profile, "staffingMattersUsec", lap_usec)
			PRODUCTION_TASK_COORDINATION_RUNTIME.sync(host, absolute_minute)
			lap_usec = host.telemetry.lap(advance_profile, "productionTasksUsec", lap_usec)
		host.frame_budget_runtime.refresh_or_defer_perception(
			host,
			host._traveler_relationship_state,
		)
		lap_usec = host.telemetry.lap(advance_profile, "perceptionUsec", lap_usec)
		AGENT_DECISION_SCHEDULING_RUNTIME.schedule_life_rhythm(
			host, absolute_minute, host.LIFE_RHYTHM_ANCHORS,
		)
		host.telemetry.lap(advance_profile, "lifeRhythmUsec", lap_usec)
	host._processing_tick_absolute_minute = -1
	host._tick_weather_override = ""
	for event_value: Variant in environment_update.get("events", []) as Array:
		host.WORLD_EVENT_DELIVERY_RUNTIME.broadcast(host, event_value as Dictionary)
	if int(environment_update.get("minutesAdvanced", 0)) > 0:
		host._notify_world_revision()
		host.environment_changed.emit(host.get_time(), host.get_weather())
	ACTION_PREVIEW_RUNTIME.advance(host, real_seconds)
	host.telemetry.finish_advance_profile(advance_started_usec)
	var advanced_events := environment_update.get("events", []) as Array
	return {
		"ok": true,
		"observationPreviewActive": ACTION_PREVIEW_RUNTIME.has_observed(host),
		"simulationSpeed": host._simulation_speed,
		"minutesAdvanced": int(environment_update.get("minutesAdvanced", 0)),
		"events": advanced_events.duplicate(true) if not advanced_events.is_empty() else [],
		"deferredPresentationRefreshesProcessed": processed_presentation_refreshes,
		"deferredPresentationRefreshCount": host.frame_budget_runtime.presentation_refresh_count(),
		"deferredPlaceChangeSignalsProcessed": processed_place_change_signals,
		"deferredPlaceChangeSignalCount": host.frame_budget_runtime.place_change_signal_count(),
		"deferredPerceptionProcessed": processed_deferred_perception,
		"errorCode": "",
		"retryable": false,
		"worldRevision": host._world_revision,
	}
