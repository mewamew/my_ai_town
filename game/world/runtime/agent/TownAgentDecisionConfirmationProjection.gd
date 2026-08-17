class_name TownAgentDecisionConfirmationProjection
extends RefCounted


static func preview(
	decision_id: String,
	handling: String,
	action: Dictionary,
	summary: String,
	public_thought: String,
	confirmed_revision: int,
	confirmed_at: Dictionary,
	display_seconds: float,
	submitted_action: Dictionary,
	conversation_end_reason := "",
	story_provenance: Dictionary = {},
	social_request: Dictionary = {},
	conversation_follow_up: Dictionary = {},
	post_injury_reaction: Dictionary = {},
	decision_can_interrupt_current := false,
	conflict_intent: Dictionary = {},
	decision_wake_snapshot: Dictionary = {},
) -> Dictionary:
	var action_id := String(action.get("action_id", ""))
	return {
		"previewId": "%s::%s" % [decision_id, action_id],
		"decisionId": decision_id,
		"actionId": action_id,
		"handling": handling,
		"summary": summary,
		"publicThought": public_thought,
		"confirmedRevision": confirmed_revision,
		"confirmedAt": confirmed_at.duplicate(true),
		"displaySeconds": display_seconds,
		"holdSeconds": display_seconds,
		"remainingSeconds": display_seconds,
		"conversationEndReason": conversation_end_reason,
		"storyProvenance": story_provenance.duplicate(true),
		"socialRequest": social_request.duplicate(true),
		"conversationFollowUp": conversation_follow_up.duplicate(true),
		"postInjuryReaction": post_injury_reaction.duplicate(true),
		"decisionMayInterruptCurrent": decision_can_interrupt_current,
		"conflictIntent": conflict_intent.duplicate(true),
		"decisionWakeSnapshot": decision_wake_snapshot.duplicate(true),
		"action": action.duplicate(true),
		"submittedAction": submitted_action.duplicate(true),
	}


static func accepted_result(
	handling: String,
	public_action: Dictionary,
	action_phase: Dictionary,
) -> Dictionary:
	return {
		"ok": true,
		"status": "continued" if handling == "continue_current" else "accepted",
		"action": public_action.duplicate(true),
		"actionPhase": action_phase.duplicate(true),
	}
