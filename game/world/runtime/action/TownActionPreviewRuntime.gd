class_name TownActionPreviewRuntime
extends RefCounted


const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const DECISION_CONFIRMATION_PROJECTION := preload(
	"res://world/runtime/agent/TownAgentDecisionConfirmationProjection.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const ACTION_PROJECTION := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const CONFIRMED_ACTION_ACTIVATION_RUNTIME := preload(
	"res://world/runtime/action/TownConfirmedActionActivationRuntime.gd"
)

const PREVIEW_SECONDS := 2.5


static func set_observed_resident(
	host,
	resident_ref: String,
	enabled: bool,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var requested_id: String = host._resident_key(resident_ref)
	if enabled and requested_id.is_empty():
		return host._command_failure(
			"RESIDENT_NOT_FOUND",
			["找不到要观察的居民"],
		)
	var next_id := requested_id if enabled else ""
	if next_id == host.actor_presentation_state.observed_action_preview_resident_id:
		return host._decorate_command_result({
			"ok": true,
			"changed": false,
			"residentId": next_id,
		})
	release_observed(host)
	host.actor_presentation_state.observed_action_preview_resident_id = next_id
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"residentId": next_id,
	})


static func confirm(
	host,
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	handling: String,
	action: Dictionary,
	conversation_end_reason := "",
	story_provenance: Dictionary = {},
	social_request: Dictionary = {},
	conversation_follow_up: Dictionary = {},
	post_injury_reaction: Dictionary = {},
	decision_can_interrupt_current := false,
	conflict_intent: Dictionary = {},
	decision_wake_snapshot: Dictionary = {},
) -> Dictionary:
	ACTION_VALIDATION.clear_rejected_action_streak(resident)
	var preview := DECISION_CONFIRMATION_PROJECTION.preview(
		decision_id,
		handling,
		action,
		ACTION_PRESENTATION._action_preview_summary(
			host,
			action,
			handling == "continue_current",
		),
		ACTION_PRESENTATION._public_surface_thought(host, action),
		host._world_revision,
		host.get_time(),
		PREVIEW_SECONDS,
		ACTION_PROJECTION.submitted_action_for_preview(action),
		conversation_end_reason,
		story_provenance,
		social_request,
		conversation_follow_up,
		post_injury_reaction,
		decision_can_interrupt_current,
		conflict_intent,
		decision_wake_snapshot,
	)
	if (
		handling == "continue_current"
		or resident_id != host.actor_presentation_state.observed_action_preview_resident_id
	):
		resident["confirmedActionPreview"] = {}
		activate(host, resident_id, resident, preview, true)
	else:
		resident["confirmedActionPreview"] = preview
		host._bump_world_revision()
		host.resident_action_phase_changed.emit(
			resident_id,
			ACTION_PRESENTATION._resident_action_phase_projection(host, resident),
		)
		host._emit_resident_state_changed(resident_id)
	var phase := ACTION_PRESENTATION._resident_action_phase_projection(host, resident)
	return DECISION_CONFIRMATION_PROJECTION.accepted_result(
		handling,
		host.ACTION_PROJECTION_MODULE.public_current_action(action),
		phase,
	)


static func advance(host, real_seconds: float) -> void:
	if not is_finite(real_seconds) or real_seconds <= 0.0:
		return
	var resident_id: String = (
		host.actor_presentation_state.observed_action_preview_resident_id
	)
	if resident_id.is_empty() or not host.resident_registry.records.has(resident_id):
		return
	var resident := host.resident_registry.records[resident_id] as Dictionary
	var preview := resident.get("confirmedActionPreview", {}) as Dictionary
	if preview.is_empty():
		return
	preview["remainingSeconds"] = maxf(
		0.0,
		float(preview.get("remainingSeconds", 0.0)) - real_seconds,
	)
	resident["confirmedActionPreview"] = preview
	if float(preview.get("remainingSeconds", 0.0)) <= 0.0:
		finish(host, resident_id, resident)


static func activate(
	host,
	resident_id: String,
	resident: Dictionary,
	preview: Dictionary,
	prepared_action_is_fresh := false,
) -> void:
	CONFIRMED_ACTION_ACTIVATION_RUNTIME.activate(
		host,
		resident_id,
		resident,
		preview,
		prepared_action_is_fresh,
	)


static func finish(host, resident_id: String, resident: Dictionary) -> void:
	var preview := resident.get("confirmedActionPreview", {}) as Dictionary
	if preview.is_empty():
		return
	resident["confirmedActionPreview"] = {}
	activate(host, resident_id, resident, preview)


static func has_observed(host) -> bool:
	var resident_id: String = (
		host.actor_presentation_state.observed_action_preview_resident_id
	)
	if resident_id.is_empty() or not host.resident_registry.records.has(resident_id):
		return false
	var resident := host.resident_registry.records[resident_id] as Dictionary
	return not (
		resident.get("confirmedActionPreview", {}) as Dictionary
	).is_empty()


static func release_observed(host) -> void:
	var resident_id: String = (
		host.actor_presentation_state.observed_action_preview_resident_id
	)
	if resident_id.is_empty() or not host.resident_registry.records.has(resident_id):
		return
	var resident := host.resident_registry.records[resident_id] as Dictionary
	if (resident.get("confirmedActionPreview", {}) as Dictionary).is_empty():
		return
	finish(host, resident_id, resident)
