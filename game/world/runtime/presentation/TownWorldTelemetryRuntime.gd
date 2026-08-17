class_name TownWorldTelemetryRuntime
extends RefCounted


var advance_profile_enabled := false
var advance_profile_scratch: Dictionary = {}
var frame_probe: GDScript = null
var frame_probe_checked := false

var _last_advance_profile: Dictionary = {}
var _agent_request_metrics: Dictionary = {}


func reset_agent_request_metrics() -> void:
	_agent_request_metrics = {
		"decisionCreated": 0,
		"behaviorStarted": 0,
		"wakeRefresh": 0,
		"decisionInvalidated": 0,
		"prefetch": 0,
		"pendingQueuePeak": 0,
		"decisionPendingWithoutAction": 0,
	}


func count_agent_request_metric(key: String, amount: int = 1) -> void:
	_agent_request_metrics[key] = int(_agent_request_metrics.get(key, 0)) + amount


func agent_request_metrics_snapshot() -> Dictionary:
	return _agent_request_metrics.duplicate(true)


func begin_advance_profile() -> Dictionary:
	advance_profile_scratch = {}
	return advance_profile_scratch


func lap(profile: Dictionary, key: String, lap_started_usec: int) -> int:
	if not advance_profile_enabled:
		return 0
	var now_usec := Time.get_ticks_usec()
	profile[key] = int(profile.get(key, 0)) + int(now_usec - lap_started_usec)
	return now_usec


func count_advance_profile(key: String, amount: int) -> void:
	if advance_profile_enabled:
		advance_profile_scratch[key] = (
			int(advance_profile_scratch.get(key, 0)) + amount
		)


func finish_advance_profile(advance_started_usec: int) -> void:
	if not advance_profile_enabled:
		return
	advance_profile_scratch["totalUsec"] = (
		Time.get_ticks_usec() - advance_started_usec
	)
	_last_advance_profile = advance_profile_scratch


func set_advance_profile_enabled(enabled: bool) -> void:
	advance_profile_enabled = enabled
	if not enabled:
		_last_advance_profile.clear()


func last_advance_profile_snapshot() -> Dictionary:
	return _last_advance_profile.duplicate(true)


func ensure_frame_probe() -> void:
	if frame_probe_checked:
		return
	frame_probe_checked = true
	if OS.get_environment("AI_TOWN_UI_FRAME_PROBE") == "1":
		frame_probe = load("res://world/presentation/ui/TownUiFrameProbe.gd")


func update_pending_queue_peak(pending_count: int) -> void:
	if pending_count > int(_agent_request_metrics.get("pendingQueuePeak", 0)):
		_agent_request_metrics["pendingQueuePeak"] = pending_count
