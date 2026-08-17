class_name TownPlayerConversationCommandRuntime
extends RefCounted


const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)


static func start(
	host,
	target_name: String,
	say: String,
	narration: String,
	photos: Array = [],
) -> Dictionary:
	if not host._running:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "发起对话", false, "世界尚未运行")
	if not CONVERSATION_RUNTIME._active_conversation_for_person(
		host,
		host.player_avatar_id(),
	).is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "发起对话", false, "化身已经在参与一段对话")
	var target_id: String = host._resident_key(target_name)
	if target_id.is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "发起对话", false, "对话目标不是已知居民")
	if not host._resident_is_alive(target_id):
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "发起对话", false, "死亡居民不能参与对话")
	var target := host.resident_registry.records[target_id] as Dictionary
	if not PERCEPTION_RUNTIME._are_nearby(
		host,
		host.actor_presentation_state.player_avatar,
		target,
	):
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "发起对话", false, "对话目标不在化身感知范围内")
	if not CONVERSATION_RUNTIME._active_conversation_for_person(
		host,
		target_id,
	).is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "发起对话", false, "对话目标正在参与另一段对话")
	var action := {
		"target": host.resident_display_name(target_id),
		"target_resident_id": target_id,
		"say": say,
		"narration": narration,
		"photos": photos.duplicate(true),
	}
	var turn_error: String = host.ACTION_SUPPORT.validate_player_turn(action, false)
	if not turn_error.is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "发起对话", false, turn_error)
	host._bump_world_revision(false)
	CONVERSATION_RUNTIME._start_conversation(
		host,
		host._traveler_relationship_state,
		host.player_avatar_id(),
		action,
	)
	host.actor_presentation_state.player_avatar["doing"] = (
		ACTION_PRESENTATION._conversation_doing(host, action)
	)
	host.player_avatar_state_changed.emit(host.get_player_avatar_state())
	host._notify_world_revision()
	return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
		"发起对话",
		true,
		"世界已确认玩家搭话",
		{"conversation": host.get_conversation(String(action.get("conversationId", "")))},
	)


static func reply(
	host,
	conversation_id: String,
	say: String,
	narration: String,
	photos: Array = [],
	end := false,
) -> Dictionary:
	if not host._running:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "继续对话", false, "世界尚未运行")
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(
		host,
		host.player_avatar_id(),
	)
	if conversation.is_empty() or String(conversation.get("conversationId", "")) != conversation_id:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "继续对话", false, "化身当前没有这段活动对话")
	if String(conversation.get("waitingFor", "")) != host.player_avatar_id():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "继续对话", false, "当前对话还没有轮到化身回应")
	var action := {
		"conversation_id": conversation_id,
		"say": say,
		"narration": narration,
		"photos": photos.duplicate(true),
		"end": end,
	}
	var turn_error: String = host.ACTION_SUPPORT.validate_player_turn(action, true)
	if not turn_error.is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "继续对话", false, turn_error)
	host._bump_world_revision(false)
	host.actor_presentation_state.player_avatar["doing"] = (
		ACTION_PRESENTATION._conversation_doing(host, action)
	)
	CONVERSATION_RUNTIME._apply_conversation_reply(
		host,
		host._traveler_relationship_state,
		host.player_avatar_id(),
		action,
	)
	host.player_avatar_state_changed.emit(host.get_player_avatar_state())
	host._notify_world_revision()
	return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
		"继续对话",
		true,
		"世界已确认玩家答话",
		{"conversation": host.get_conversation(conversation_id)},
	)


static func end(host, conversation_id: String, narration := "结束交谈") -> Dictionary:
	if not host._running:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "结束对话", false, "世界尚未运行")
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(
		host,
		host.player_avatar_id(),
	)
	if conversation.is_empty() or String(conversation.get("conversationId", "")) != conversation_id:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "结束对话", false, "化身当前没有这段活动对话")
	var normalized := narration.strip_edges()
	if normalized.is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "结束对话", false, "结束对话需要可观察的动作描述")
	var action := {
		"conversation_id": conversation_id,
		"say": "",
		"narration": normalized,
		"photos": [],
		"end": true,
	}
	host._bump_world_revision(false)
	host.actor_presentation_state.player_avatar["doing"] = normalized
	CONVERSATION_RUNTIME._apply_conversation_reply(
		host,
		host._traveler_relationship_state,
		host.player_avatar_id(),
		action,
	)
	host.player_avatar_state_changed.emit(host.get_player_avatar_state())
	host._notify_world_revision()
	return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
		"结束对话",
		true,
		"世界已确认玩家结束对话",
		{"conversation": host.get_conversation(conversation_id)},
	)


static func reject(
	host,
	conversation_id: String,
	narration := "没有接话",
) -> Dictionary:
	if not host._running:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "拒绝对话", false, "世界尚未运行")
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(
		host,
		host.player_avatar_id(),
	)
	if conversation.is_empty() or String(conversation.get("conversationId", "")) != conversation_id:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "拒绝对话", false, "化身当前没有这段活动对话")
	if not CONVERSATION_RUNTIME._is_initial_invitation_for(
		host,
		host.player_avatar_id(),
		conversation,
	):
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "拒绝对话", false, "只有尚未回应的搭话邀请可以拒绝")
	var normalized := narration.strip_edges()
	if normalized.is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "拒绝对话", false, "拒绝对话需要可观察的动作描述")
	host._bump_world_revision(false)
	host.actor_presentation_state.player_avatar["doing"] = normalized
	CONVERSATION_RUNTIME._end_conversation(
		host,
		host._traveler_relationship_state,
		conversation_id,
		"拒绝接话",
		"rejected",
	)
	host.player_avatar_state_changed.emit(host.get_player_avatar_state())
	host._notify_world_revision()
	return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
		"拒绝对话",
		true,
		"世界已确认玩家拒绝接话",
		{"conversation": host.get_conversation(conversation_id)},
	)
