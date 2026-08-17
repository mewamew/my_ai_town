class_name TownWorldLifecycleCommandRuntime
extends RefCounted


const RESIDENT_CONDITION_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentConditionRuntime.gd"
)
const RESIDENT_SLEEP_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentSleepRuntime.gd"
)
const CLINIC_INTERVIEW_POLICY := preload(
	"res://world/runtime/condition/TownClinicInterviewPolicy.gd"
)
const CONFLICT_WORLD_COORDINATION_RUNTIME := preload(
	"res://world/runtime/conflict/TownConflictWorldCoordinationRuntime.gd"
)


static func state(host) -> Dictionary:
	var reasons: Array[String] = host._pause_reasons.duplicate()
	reasons.sort()
	return {
		"state": "stopped" if not host._running else (
			"paused" if not reasons.is_empty() else "running"
		),
		"started": host._running,
		"paused": host._running and not reasons.is_empty(),
		"pauseReasons": reasons,
	}


static func set_speed(host, speed: int) -> Dictionary:
	if not host._running:
		return host._command_failure(
			"WORLD_NOT_RUNNING",
			["世界尚未运行"],
			{"simulationSpeed": host._simulation_speed},
		)
	if not host.ALLOWED_SIMULATION_SPEEDS.has(speed):
		return host._command_failure(
			"INVALID_SIMULATION_SPEED",
			["世界倍率只允许 1、2 或 3"],
			{
				"simulationSpeed": host._simulation_speed,
				"allowedSimulationSpeeds": host.ALLOWED_SIMULATION_SPEEDS.duplicate(),
			},
		)
	if speed == host._simulation_speed:
		return host._decorate_command_result({
			"ok": true,
			"changed": false,
			"simulationSpeed": host._simulation_speed,
		})
	host._simulation_speed = speed
	host.simulation_speed_changed.emit(
		host._simulation_speed,
		host._world_revision,
	)
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"simulationSpeed": host._simulation_speed,
	})


static func pause(host, reason: String) -> Dictionary:
	if not host._running:
		return host._command_failure(
			"WORLD_NOT_RUNNING",
			["世界尚未运行"],
			{"state": state(host)},
		)
	var normalized := reason.strip_edges()
	if not host.PAUSE_REASONS.has(normalized):
		return host._command_failure(
			"INVALID_PAUSE_REASON",
			["未知暂停原因：%s" % normalized],
			{"state": state(host)},
		)
	if host._pause_reasons.has(normalized):
		return host._decorate_command_result({
			"ok": true,
			"changed": false,
			"state": state(host),
		})
	host._pause_reasons.append(normalized)
	host._bump_world_revision()
	var lifecycle := state(host)
	host.lifecycle_state_changed.emit(lifecycle.duplicate(true))
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"state": lifecycle,
	})


static func resume(host, reason: String) -> Dictionary:
	if not host._running:
		return host._command_failure(
			"WORLD_NOT_RUNNING",
			["世界尚未运行"],
			{"state": state(host)},
		)
	var normalized := reason.strip_edges()
	if not host.PAUSE_REASONS.has(normalized):
		return host._command_failure(
			"INVALID_PAUSE_REASON",
			["未知暂停原因：%s" % normalized],
			{"state": state(host)},
		)
	if not host._pause_reasons.has(normalized):
		return host._decorate_command_result({
			"ok": true,
			"changed": false,
			"state": state(host),
		})
	host._pause_reasons.erase(normalized)
	host._bump_world_revision()
	var lifecycle := state(host)
	host.lifecycle_state_changed.emit(lifecycle.duplicate(true))
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"state": lifecycle,
	})


static func stop(host) -> Dictionary:
	if not host._running:
		return host._decorate_command_result({
			"ok": true,
			"changed": false,
			"state": state(host),
			"simulationSpeed": host._simulation_speed,
		})
	host.AGENT_DECISION_SCHEDULING_RUNTIME.invalidate_all_pending_decisions(host)
	host.world_log_domain.capture_enabled = false
	host._pause_reasons.clear()
	host.frame_budget_runtime.reset()
	host.activity_reachability_state.clear()
	host._agent_wake_preparation_runtime.clear()
	host.actor_presentation_state.observed_action_preview_resident_id = ""
	host._tick_weather_override = ""
	host._dynamic_prop_runtime.clear_dynamic_props()
	host._animal_fact_runtime.reset()
	host._activity_runtime.reset_runtime_state()
	host.activity_routine_state.reset()
	host.activity_work_task_bindings.reset()
	host.private_message_runtime.reset()
	host._work.reset_after_stop()
	host._resident_conditions = RESIDENT_CONDITION_RUNTIME.new()
	host._resident_sleep = RESIDENT_SLEEP_RUNTIME.new()
	host._clinic_interviews = CLINIC_INTERVIEW_POLICY.new()
	host._disconnect_conflict_controller_signals()
	host._conflict_controller = null
	host._conflict_agent_world_bridge.reset_pending_knowledge_wakes()
	var speed_was_reset := bool(host._simulation_speed != 1)
	host._simulation_speed = 1
	host._running = false
	host._bump_world_revision()
	if speed_was_reset:
		host.simulation_speed_changed.emit(
			host._simulation_speed,
			host._world_revision,
		)
	var lifecycle := state(host)
	host.lifecycle_state_changed.emit(lifecycle.duplicate(true))
	host.conflict_projection_changed.emit(
		CONFLICT_WORLD_COORDINATION_RUNTIME.empty_projection()
	)
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"state": lifecycle,
		"simulationSpeed": host._simulation_speed,
	})
