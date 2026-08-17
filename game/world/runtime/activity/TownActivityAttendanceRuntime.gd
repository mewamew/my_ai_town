class_name TownActivityAttendanceRuntime
extends RefCounted


const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const AGENT_WORLD_QUERY_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentWorldQueryRuntime.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const WORK_SETTLEMENT := preload(
	"res://world/runtime/work/TownWorkSettlement.gd"
)


static func start_sleep_leave(
	host,
	resident: Dictionary,
	action: Dictionary,
	execution: Dictionary,
) -> void:
	if ACTIVITY_SCALARS.start_sleep_leave(
		resident,
		action,
		execution,
		bool(AGENT_WORLD_QUERY_RUNTIME.life_rhythm(
			host,
			resident,
		).get("work_expected", false)),
		ACTION_SUPPORT.prop_approach_duration_minutes(host, action),
	):
		WORK_SETTLEMENT.refresh_staffing_after_attendance_change(host)


static func clear_sleep_leave(host, resident: Dictionary) -> void:
	if ACTIVITY_SCALARS.clear_sleep_leave(resident):
		WORK_SETTLEMENT.refresh_staffing_after_attendance_change(host)
