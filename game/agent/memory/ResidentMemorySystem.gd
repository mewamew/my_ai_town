class_name AgentResidentMemorySystem
extends RefCounted


const MAX_RESIDENT_STORAGE_SEGMENT_LENGTH := 48
const RESIDENT_STORAGE_KEY_LENGTH := 24

const EvidenceQueueScript := preload("res://agent/memory/ResidentEvidenceQueue.gd")
const AgentContractScript := preload("res://agent/AgentContract.gd")
const AgentJsonScript := preload("res://agent/AgentJson.gd")
const MemoryOrganizerScript := preload("res://agent/memory/MemoryOrganizer.gd")
const MemoryStoreScript := preload("res://agent/memory/ResidentMemoryStore.gd")
const MemoryEntryStoreScript := preload(
	"res://agent/memory/ResidentMemoryEntryStore.gd",
)
const MemoryInterventionStoreScript := preload(
	"res://agent/memory/ResidentMemoryInterventionStore.gd",
)
const FormalMemoryBuilderScript := preload(
	"res://agent/memory/ResidentFormalMemoryBuilder.gd",
)
const MemoryInterventionServiceScript := preload(
	"res://agent/memory/ResidentMemoryInterventionService.gd",
)
const MemorySummaryProjectorScript := preload(
	"res://agent/memory/ResidentMemorySummaryProjector.gd",
)
const MemoryAgingServiceScript := preload(
	"res://agent/memory/ResidentMemoryAgingService.gd",
)
const PromptTextScript := preload("res://agent/prompt/PromptText.gd")

const LEGACY_MEMORY_STATE_VERSION := 5
const MEMORY_STATE_VERSION := 6
const DEFAULT_MEMORY_ROOT := "user://agent_runtime_memory"
const ORGANIZATION_BATCH_SIZE := 4
const FORMAL_RECALL_MAX_ITEMS := 6
const DECISION_IMPORTANT_MEMORY_LIMIT := 2400
const DECISION_MEMORY_TOTAL_LIMIT := 6000
const TOPIC_SEPARATORS := [
	"还没有", "没有", "已经", "正在", "准备", "打算", "继续", "明天",
	"昨天", "今天", "现在", "这个", "那个", "这里", "那里", "因为",
	"所以", "然后", "可能", "需要", "想要", "看到", "听到", "发生",
	"修好", "做好", "完成", "一下", "还是", "觉得", "不能", "可以",
	"我们", "你们", "他们", "她们", "它们", "，", "。", "；", "：",
	"！", "？", ",", ".", ";", ":", "!", "?", "\n", "\t",
]

var _initialization: Dictionary = {}
var _resident_id: String
var _resident_name: String
var _memory_root: String
var _resident_root: String
var _memory_path: String
var _evidence_path: String
var _memory_entries_path: String
var _memory_interventions_path: String
var _store: AgentResidentMemoryStore
var _evidence_queue: AgentResidentEvidenceQueue
var _memory_entry_store: RefCounted
var _memory_intervention_store: RefCounted
var _formal_memory_builder: RefCounted
var _memory_intervention_service: RefCounted
var _memory_summary_projector: RefCounted
var _memory_aging_service: RefCounted
var _organizer: RefCounted
var _known_action_ids: Dictionary = {}
var _observed_identity_ids: Dictionary = {}
var _pending_actions: Dictionary = {}
var _memory: Dictionary = {}
var _unorganized_since_day := 0
var _storage_initialized := false
var _last_context_fields: Array[String] = []
var _last_update: Dictionary = {"status": "idle", "persisted_entries": []}
var _last_organization: Dictionary = {"status": "idle", "errors": []}
var _last_errors: Array[String] = []
static var _standalone_generation := 0


func _init(
	initialization: Dictionary,
	memory_root: String = "",
	photo_content_resolver: Object = null,
) -> void:
	# initialization 为共享只读数据（约定不可变），各组件持引用不再各存深拷贝。
	_initialization = initialization
	_collect_identity_ids(_initialization)
	var me := _initialization.get("me", {}) as Dictionary
	_resident_id = String(me.get("resident_id", ""))
	_resident_name = String((me.get("attributes", {}) as Dictionary).get("name", ""))
	var resolved_root := memory_root
	if resolved_root.is_empty():
		resolved_root = _allocate_standalone_root()
	_memory_root = resolved_root.trim_suffix("/")
	_resident_root = _memory_root.path_join(
		_resident_storage_segment(_resident_id),
	)
	_memory_path = _resident_root.path_join("resident_memory.json")
	_evidence_path = _resident_root.path_join("world_evidence.json")
	_memory_entries_path = _resident_root.path_join("resident_memory_entries.json")
	_memory_interventions_path = _resident_root.path_join(
		"resident_memory_interventions.json",
	)
	_store = MemoryStoreScript.new(_memory_path)
	_evidence_queue = EvidenceQueueScript.new(_evidence_path)
	_memory_entry_store = MemoryEntryStoreScript.new(
		_memory_entries_path,
		_resident_id,
	)
	_memory_intervention_store = MemoryInterventionStoreScript.new(
		_memory_interventions_path,
		_resident_id,
	)
	_formal_memory_builder = FormalMemoryBuilderScript.new(_resident_id)
	_memory_intervention_service = MemoryInterventionServiceScript.new(
		_resident_id,
		_memory_entry_store,
		_memory_intervention_store,
	)
	_memory_summary_projector = MemorySummaryProjectorScript.new()
	_memory_aging_service = MemoryAgingServiceScript.new(_resident_id)
	_memory = _store.call("empty_memory")
	_organizer = MemoryOrganizerScript.new(
		_initialization,
		_store,
		photo_content_resolver,
	)


func prepare_context(wake_packet: Dictionary) -> Dictionary:
	_last_context_fields.clear()
	_last_organization = {"status": "idle", "errors": []}
	var load_result := _load_current_state(true)
	if not bool(load_result.get("ok", false)):
		return _remember_failure(load_result)
	var aging_result := _apply_automatic_memory_aging(
		(wake_packet.get("snapshot", {}) as Dictionary).get("time", {}),
		load_result.get("formal_memory_archive", {}) as Dictionary,
		load_result.get("memory_interventions", {}) as Dictionary,
	)
	if not bool(aging_result.get("ok", false)):
		return _remember_failure(aging_result)
	var ingestion := _ingest_wake(wake_packet)
	if not bool(ingestion.get("ok", false)):
		return _remember_failure(ingestion)
	var context := _context_result(
		wake_packet,
		aging_result.get("formal_memory_archive", {}) as Dictionary,
		aging_result.get("memory_interventions", {}) as Dictionary,
	)
	var response := {
		"ok": true,
		"memory_prompt": context["memory_prompt"],
		"used_action_ids": _known_action_ids.duplicate(),
		"persisted_entries": [],
	}
	var plan := _build_organization_plan(
		wake_packet,
		bool(ingestion.get("added", false)),
		int(ingestion.get("new_items_since_organization", 0)),
	)
	if not bool(plan.get("ok", false)):
		record_organization_failure(plan.get("errors", []))
		return response
	if bool(plan.get("triggered", false)):
		response["organization_request"] = plan["request"]
		response["organization_token"] = plan["token"]
	_last_errors = []
	return response


func retrieve_context(wake_packet: Dictionary) -> Dictionary:
	_last_context_fields.clear()
	var load_result := _load_current_state()
	if not bool(load_result.get("ok", false)):
		return _remember_failure(load_result)
	return _context_result(
		wake_packet,
		load_result.get("formal_memory_archive", {}) as Dictionary,
		load_result.get("memory_interventions", {}) as Dictionary,
	)


func accept_decision(decision: Dictionary, wake_packet: Dictionary) -> Dictionary:
	if decision.get("handling") != "replace_current":
		_last_update = {"status": "unchanged", "persisted_entries": []}
		return {"ok": true, "persisted_entries": []}
	var action_value: Variant = decision.get("action")
	if typeof(action_value) != TYPE_DICTIONARY:
		return _remember_failure(_failure("合法决定缺少动作对象"))
	var action := action_value as Dictionary
	var action_id := String(action.get("action_id", ""))
	if action_id.is_empty():
		return _remember_failure(_failure("action.action_id 不能为空"))
	if _known_action_ids.has(action_id):
		return _remember_failure(_failure("action.action_id 必须在本 Agent 范围内唯一"))
	var current_thought := String(action.get("line", "")).strip_edges()
	var previous_thoughts := String(_memory.get("current_thoughts", ""))
	if not current_thought.is_empty():
		var load_result := _load_current_state(true)
		if not bool(load_result.get("ok", false)):
			return _remember_failure(load_result)
		previous_thoughts = String(_memory.get("current_thoughts", ""))
		_memory["current_thoughts"] = current_thought
		var thought_write := _store.call("replace", _memory) as Dictionary
		if not bool(thought_write.get("ok", false)):
			_memory["current_thoughts"] = previous_thoughts
			return _remember_failure(thought_write)
	var snapshot := wake_packet.get("snapshot", {}) as Dictionary
	_pending_actions[action_id] = {
		"decision_id": String(decision.get("decision_id", "")),
		"action": action.duplicate(true),
		"submitted_at": (snapshot.get("time", {}) as Dictionary).duplicate(true),
		"previous_current_thoughts": previous_thoughts,
	}
	_known_action_ids[action_id] = true
	_collect_identity_ids(action)
	_last_update = {
		"status": "pending_world_result",
		"action_id": action_id,
		"persisted_entries": [],
	}
	return {"ok": true, "persisted_entries": []}


func discard_unconfirmed_decision(decision: Dictionary) -> Dictionary:
	if decision.get("handling") != "replace_current":
		return {"ok": true, "changed": false, "action_id": ""}
	var action_value: Variant = decision.get("action")
	if not action_value is Dictionary:
		return _failure("待撤销决定缺少动作对象")
	var action := action_value as Dictionary
	var action_id := String(action.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return _failure("待撤销决定缺少 action.action_id")
	if not _pending_actions.has(action_id):
		return {"ok": true, "changed": false, "action_id": action_id}
	var pending := _pending_actions[action_id] as Dictionary
	if String(pending.get("decision_id", "")) != String(
		decision.get("decision_id", "")
	):
		return _failure("待撤销动作不属于当前决定")
	var restore_result := _restore_pending_current_thought(pending)
	if not bool(restore_result.get("ok", false)):
		return restore_result
	_pending_actions.erase(action_id)
	_known_action_ids.erase(action_id)
	_last_update = {
		"status": "unconfirmed_decision_discarded",
		"action_id": action_id,
		"persisted_entries": [],
	}
	return {"ok": true, "changed": true, "action_id": action_id}


func accept_organization(token_value: Variant, candidate: Variant) -> Dictionary:
	if _organizer == null:
		return _organization_failure(_failure("居民记忆整理器尚未配置"), false)
	var context := _organization_context(token_value)
	if not bool(context.get("ok", false)):
		return _organization_failure(
			context,
			bool(context.get("safe_to_continue", false)),
		)
	var validation := _organizer.call(
		"validate_candidate",
		candidate,
		context["old_memory"],
		context["evidence_items"],
	) as Dictionary
	if not bool(validation.get("ok", false)):
		if bool(validation.get("retryable", false)):
			var retry_request := _organizer.call(
				"build_retry_request",
				context["old_memory"],
				context["evidence_items"],
				validation,
			) as Dictionary
			if bool(retry_request.get("ok", false)):
				var result := _organization_failure(validation, true)
				result["retry_request"] = retry_request
				return result
		return _organization_failure(validation, true)
	var archive_read := _memory_entry_store.call("read") as Dictionary
	if not bool(archive_read.get("ok", false)):
		return _organization_failure(archive_read, true)
	var intervention_read := _memory_intervention_store.call("read") as Dictionary
	if not bool(intervention_read.get("ok", false)):
		return _organization_failure(intervention_read, true)
	var old_archive := (archive_read["archive"] as Dictionary).duplicate(true)
	var old_intervention_log := (intervention_read["log"] as Dictionary).duplicate(true)
	var formal_result := _formal_memory_builder.call(
		"build",
		old_archive,
		old_intervention_log,
		context["evidence_items"],
		validation["memory"],
	) as Dictionary
	if not bool(formal_result.get("ok", false)):
		return _organization_failure(formal_result, true)
	var archive_validation := _memory_entry_store.call(
		"validate",
		formal_result["archive"],
	) as Dictionary
	if not bool(archive_validation.get("ok", false)):
		return _organization_failure(archive_validation, true)
	var log_validation := _memory_intervention_store.call(
		"validate",
		formal_result["intervention_log"],
	) as Dictionary
	if not bool(log_validation.get("ok", false)):
		return _organization_failure(log_validation, true)
	var organized_memory := (validation["memory"] as Dictionary).duplicate(true)
	var formal_entries := (
		(archive_validation["archive"] as Dictionary).get("entries", []) as Array
	)
	if not formal_entries.is_empty():
		var projected := _memory_summary_projector.call(
			"project",
			organized_memory,
			formal_entries,
		) as Dictionary
		var projected_validation := _store.call("validate", projected) as Dictionary
		if not bool(projected_validation.get("ok", false)):
			return _organization_failure(projected_validation, true)
		organized_memory = (projected_validation["memory"] as Dictionary).duplicate(true)
	var replacement := _store.call("replace", organized_memory) as Dictionary
	if not bool(replacement.get("ok", false)):
		var verification := _store.call("read") as Dictionary
		var old_intact := (
			bool(verification.get("ok", false))
			and _memory_digest(verification["memory"] as Dictionary)
				== _memory_digest(context["old_memory"] as Dictionary)
		)
		return _organization_failure(replacement, old_intact)
	var archive_write := _memory_entry_store.call(
		"replace",
		archive_validation["archive"],
	) as Dictionary
	if not bool(archive_write.get("ok", false)):
		var summary_rollback := _store.call("replace", context["old_memory"]) as Dictionary
		return _organization_failure(
			_combined_failure(archive_write, [summary_rollback]),
			bool(summary_rollback.get("ok", false)),
		)
	var log_write := _memory_intervention_store.call(
		"replace",
		log_validation["log"],
	) as Dictionary
	if not bool(log_write.get("ok", false)):
		var summary_rollback := _store.call("replace", context["old_memory"]) as Dictionary
		var archive_rollback := _memory_entry_store.call("replace", old_archive) as Dictionary
		return _organization_failure(
			_combined_failure(log_write, [summary_rollback, archive_rollback]),
			bool(summary_rollback.get("ok", false)) and bool(archive_rollback.get("ok", false)),
		)
	var mark_result := _evidence_queue.call("mark_organized") as Dictionary
	if not bool(mark_result.get("ok", false)):
		var rollback := _store.call("replace", context["old_memory"]) as Dictionary
		var archive_rollback := _memory_entry_store.call("replace", old_archive) as Dictionary
		var log_rollback := _memory_intervention_store.call("replace", old_intervention_log) as Dictionary
		var rollback_ok := (
			bool(rollback.get("ok", false))
			and bool(archive_rollback.get("ok", false))
			and bool(log_rollback.get("ok", false))
		)
		return _organization_failure(
			_combined_failure(mark_result, [rollback, archive_rollback, log_rollback]),
			rollback_ok,
		)
	_memory = (replacement["memory"] as Dictionary).duplicate(true)
	_unorganized_since_day = 0
	_last_update = {
		"status": "organized",
		"persisted_entries": [_memory.duplicate(true)],
	}
	_last_organization = {
		"status": "organized",
		"errors": [],
		"persisted_entries": [_memory.duplicate(true)],
	}
	_last_errors = []
	return {
		"ok": true,
		"memory": _memory.duplicate(true),
		"formal_memory_revision": int((archive_write["archive"] as Dictionary)["revision"]),
	}


func apply_memory_intervention(request: Variant) -> Dictionary:
	var load_result := _load_current_state(true)
	if not bool(load_result.get("ok", false)):
		return load_result
	var archive_read := _memory_entry_store.call("read") as Dictionary
	var log_read := _memory_intervention_store.call("read") as Dictionary
	if not bool(archive_read.get("ok", false)):
		return archive_read
	if not bool(log_read.get("ok", false)):
		return log_read
	var old_archive := (archive_read["archive"] as Dictionary).duplicate(true)
	var old_log := (log_read["log"] as Dictionary).duplicate(true)
	var old_summary := _memory.duplicate(true)
	var applied := _memory_intervention_service.call("apply", request) as Dictionary
	if not bool(applied.get("ok", false)):
		return applied
	var new_archive_read := _memory_entry_store.call("read") as Dictionary
	if not bool(new_archive_read.get("ok", false)):
		var rollback := _rollback_subjective_memory(old_summary, old_archive, old_log)
		return _combined_failure(new_archive_read, [rollback])
	var projected := _memory_summary_projector.call(
		"project",
		old_summary,
		(new_archive_read["archive"] as Dictionary).get("entries", []),
	) as Dictionary
	var summary_validation := _store.call("validate", projected) as Dictionary
	if not bool(summary_validation.get("ok", false)):
		var rollback := _rollback_subjective_memory(old_summary, old_archive, old_log)
		return _combined_failure(summary_validation, [rollback])
	var summary_write := _store.call("replace", summary_validation["memory"]) as Dictionary
	if not bool(summary_write.get("ok", false)):
		var rollback := _rollback_subjective_memory(old_summary, old_archive, old_log)
		return _combined_failure(summary_write, [rollback])
	_memory = (summary_write["memory"] as Dictionary).duplicate(true)
	_last_update = {
		"status": "memory_intervention_applied",
		"persisted_entries": [_memory.duplicate(true)],
	}
	return {
		"ok": true,
		"revision": int(applied.get("revision", 0)),
		"memory": _memory.duplicate(true),
		"changed_memory": (applied.get("memory", {}) as Dictionary).duplicate(true),
	}


func _apply_automatic_memory_aging(
	world_time: Variant,
	archive_snapshot: Dictionary,
	intervention_snapshot: Dictionary,
) -> Dictionary:
	if _memory_aging_service == null:
		return {
			"ok": true,
			"changed": false,
			"formal_memory_archive": archive_snapshot.duplicate(true),
			"memory_interventions": intervention_snapshot.duplicate(true),
		}
	var old_archive := archive_snapshot.duplicate(true)
	var old_log := intervention_snapshot.duplicate(true)
	var old_summary := _memory.duplicate(true)
	var evaluated := _memory_aging_service.call(
		"evaluate",
		old_archive,
		old_log,
		world_time,
	) as Dictionary
	if not bool(evaluated.get("ok", false)):
		return evaluated
	if not bool(evaluated.get("changed", false)):
		return {
			"ok": true,
			"changed": false,
			"formal_memory_archive": (
				evaluated.get("archive", old_archive) as Dictionary
			).duplicate(true),
			"memory_interventions": (
				evaluated.get("intervention_log", old_log) as Dictionary
			).duplicate(true),
		}
	var archive_validation := _memory_entry_store.call(
		"validate",
		evaluated.get("archive"),
	) as Dictionary
	if not bool(archive_validation.get("ok", false)):
		return archive_validation
	var log_validation := _memory_intervention_store.call(
		"validate",
		evaluated.get("intervention_log"),
	) as Dictionary
	if not bool(log_validation.get("ok", false)):
		return log_validation
	var projected := _memory_summary_projector.call(
		"project",
		old_summary,
		(archive_validation["archive"] as Dictionary).get("entries", []),
	) as Dictionary
	var summary_validation := _store.call("validate", projected) as Dictionary
	if not bool(summary_validation.get("ok", false)):
		return summary_validation
	var archive_write := _memory_entry_store.call(
		"replace",
		archive_validation["archive"],
	) as Dictionary
	if not bool(archive_write.get("ok", false)):
		return archive_write
	var log_write := _memory_intervention_store.call(
		"replace",
		log_validation["log"],
	) as Dictionary
	if not bool(log_write.get("ok", false)):
		var archive_rollback := _memory_entry_store.call("replace", old_archive) as Dictionary
		return _combined_failure(log_write, [archive_rollback])
	var summary_write := _store.call(
		"replace",
		summary_validation["memory"],
	) as Dictionary
	if not bool(summary_write.get("ok", false)):
		var rollback := _rollback_subjective_memory(old_summary, old_archive, old_log)
		return _combined_failure(summary_write, [rollback])
	_memory = (summary_write["memory"] as Dictionary).duplicate(true)
	_last_update = {
		"status": "memory_aged",
		"persisted_entries": [_memory.duplicate(true)],
		"changes": (evaluated.get("changes", []) as Array).duplicate(true),
	}
	return {
		"ok": true,
		"changed": true,
		"revision": int(evaluated.get("revision", 0)),
		"changes": (evaluated.get("changes", []) as Array).duplicate(true),
		"formal_memory_archive": (
			archive_validation["archive"] as Dictionary
		).duplicate(true),
		"memory_interventions": (
			log_validation["log"] as Dictionary
		).duplicate(true),
	}


func _rollback_subjective_memory(
	old_summary: Dictionary,
	old_archive: Dictionary,
	old_log: Dictionary,
) -> Dictionary:
	var summary_result := _store.call("replace", old_summary) as Dictionary
	var archive_result := _memory_entry_store.call("replace", old_archive) as Dictionary
	var log_result := _memory_intervention_store.call("replace", old_log) as Dictionary
	_memory = old_summary.duplicate(true)
	var ok := (
		bool(summary_result.get("ok", false))
		and bool(archive_result.get("ok", false))
		and bool(log_result.get("ok", false))
	)
	return _combined_failure(
		{"ok": ok, "errors": []},
		[summary_result, archive_result, log_result],
	)


func _combined_failure(primary: Dictionary, related_results: Array) -> Dictionary:
	var errors: Array = primary.get("errors", []).duplicate()
	var rollback_failed := false
	for result_value: Variant in related_results:
		if typeof(result_value) != TYPE_DICTIONARY:
			continue
		var result := result_value as Dictionary
		if not bool(result.get("ok", false)):
			rollback_failed = true
			errors.append_array(result.get("errors", []))
	if bool(primary.get("ok", false)) and not rollback_failed:
		return {"ok": true}
	return {
		"ok": false,
		"errors": errors,
		"rollback_failed": rollback_failed,
	}


func record_organization_failure(errors: Variant) -> Dictionary:
	var messages: Array[String] = []
	if typeof(errors) == TYPE_ARRAY:
		for error_value: Variant in errors as Array:
			messages.append(String(error_value))
	if messages.is_empty():
		messages.append("居民记忆整理失败")
	return _organization_failure({"ok": false, "errors": messages}, true)


func get_read_only_memory() -> Dictionary:
	var load_result := _load_current_state()
	if not bool(load_result.get("ok", false)):
		return load_result
	var archive := (
		load_result.get("formal_memory_archive", {}) as Dictionary
	).duplicate(true)
	var intervention_log := (
		load_result.get("memory_interventions", {}) as Dictionary
	).duplicate(true)
	var important_memories := _player_visible_text(
		_memory["important_memories"]
	)
	return {
		"ok": true,
		"memory": {
			"formal_memory_revision": int(archive.get("revision", 0)),
			"formal_memories": _public_formal_memories(
				archive.get("entries", []),
			),
			"interventions": _public_interventions(
				intervention_log.get(
					"interventions",
					[],
				),
			),
			"important_memories": important_memories,
			"relationships": _player_visible_text(_memory["relationships"]),
			# 内心观察只能读取居民此刻真实保存的想法。current_focus 仍为
			# 记忆页保留历史回退，但不能再把旧记忆冒充成当前内心。
			"current_inner_thought": _player_visible_text(
				_memory["current_thoughts"],
			),
			"current_focus": _public_current_focus(
				_memory["current_thoughts"],
				archive.get("entries", []),
				important_memories,
			),
			"next_plan": _player_visible_text(_memory["short_term_goals"]),
			"current_judgment": _current_judgment(
				archive.get("entries", []),
			),
			"memory_certainties": _memory_certainty_summaries(
				archive.get("entries", []),
			),
			"memory_doubts": _memory_state_summaries(
				archive.get("entries", []),
				"doubtful",
			),
			"memory_contradictions": _memory_state_summaries(
				archive.get("entries", []),
				"anomalous",
			),
			"public_basis": _public_basis(
				archive.get("entries", []),
			),
			"important_memory_influence": _public_memory_influence(
				important_memories,
			),
		},
	}


func find_expressed_memory_claim(spoken_text: String) -> Dictionary:
	var normalized_spoken := _claim_text(spoken_text)
	if normalized_spoken.length() < 4:
		return {"ok": true, "matched": false}
	var entry_result := _memory_entry_store.call("read") as Dictionary
	if not bool(entry_result.get("ok", false)):
		return entry_result
	var entries := (entry_result["archive"] as Dictionary).get("entries", []) as Array
	var best_score := 0.0
	var best_entry: Dictionary = {}
	for index in range(entries.size() - 1, -1, -1):
		var entry := entries[index] as Dictionary
		if String(entry.get("state", "")) not in ["influencing", "doubtful", "anomalous"]:
			continue
		var remembered_text := _claim_text(String(entry.get("subject", "")))
		var separator := remembered_text.find("说")
		if separator >= 0 and separator + 1 < remembered_text.length():
			remembered_text = remembered_text.substr(separator + 1)
		var score := _claim_similarity(normalized_spoken, remembered_text)
		if score > best_score:
			best_score = score
			best_entry = entry
	if best_score < 0.58 or best_entry.is_empty():
		return {"ok": true, "matched": false}
	return {
		"ok": true,
		"matched": true,
		"claim_root_id": String(best_entry.get("claim_root_id", "")),
		"memory_id": String(best_entry.get("memory_id", "")),
	}


func _current_judgment(entries: Variant) -> String:
	if typeof(entries) != TYPE_ARRAY:
		return ""
	for index in range((entries as Array).size() - 1, -1, -1):
		var entry := (entries as Array)[index] as Dictionary
		if String(entry.get("state", "")) not in ["influencing", "doubtful", "anomalous"]:
			continue
		var interpretation := _player_visible_text(entry.get("interpretation", "")).strip_edges()
		if not interpretation.is_empty():
			return interpretation
	return ""


func _public_current_focus(
	current_thoughts: Variant,
	entries: Variant,
	important_memories: String,
) -> String:
	var current := _player_visible_text(current_thoughts).strip_edges()
	if not current.is_empty():
		return current
	if typeof(entries) == TYPE_ARRAY:
		for index in range((entries as Array).size() - 1, -1, -1):
			var entry_value: Variant = (entries as Array)[index]
			if typeof(entry_value) != TYPE_DICTIONARY:
				continue
			var entry := entry_value as Dictionary
			if String(entry.get("state", "")) not in [
				"influencing",
				"doubtful",
				"anomalous",
			]:
				continue
			var subject := _player_visible_text(entry.get("subject", ""))
			if not subject.strip_edges().is_empty():
				return subject.strip_edges()
	return important_memories.strip_edges()


func _memory_state_summaries(entries: Variant, state: String) -> Array[String]:
	var result: Array[String] = []
	if typeof(entries) != TYPE_ARRAY:
		return result
	for entry_value: Variant in entries as Array:
		var entry := entry_value as Dictionary
		if String(entry.get("state", "")) == state:
			result.append(_player_visible_text(entry.get("subject", "")))
	return result


func _memory_certainty_summaries(entries: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(entries) != TYPE_ARRAY:
		return result
	for index in range((entries as Array).size() - 1, -1, -1):
		var entry := (entries as Array)[index] as Dictionary
		if (
			String(entry.get("state", "")) == "influencing"
			and int(entry.get("confidence", 0)) >= 86
		):
			var subject := _player_visible_text(entry.get("subject", "")).strip_edges()
			if not subject.is_empty():
				result.append(subject)
		if result.size() >= 2:
			break
	return result


func _claim_text(value: String) -> String:
	var result := value.to_lower().strip_edges()
	for separator: String in [" ", "\t", "\r", "\n", "，", "。", "！", "？", "：", "；", ",", ".", "!", "?", ":", ";", "“", "”", "\"", "'"]:
		result = result.replace(separator, "")
	return result


func _claim_similarity(left: String, right: String) -> float:
	if left.is_empty() or right.is_empty():
		return 0.0
	if left.contains(right) or right.contains(left):
		return float(mini(left.length(), right.length())) / float(maxi(left.length(), right.length()))
	var left_pairs := {}
	for index in range(left.length() - 1):
		left_pairs[left.substr(index, 2)] = true
	var right_pairs := {}
	for index in range(right.length() - 1):
		right_pairs[right.substr(index, 2)] = true
	var shared := 0
	for pair: Variant in left_pairs:
		if right_pairs.has(pair):
			shared += 1
	var denominator := maxi(1, mini(left_pairs.size(), right_pairs.size()))
	return float(shared) / float(denominator)


func _public_basis(entries: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(entries) != TYPE_ARRAY:
		return result
	for index in range((entries as Array).size() - 1, -1, -1):
		var entry := (entries as Array)[index] as Dictionary
		if String(entry.get("state", "")) not in ["influencing", "doubtful", "anomalous"]:
			continue
		var subject := _player_visible_text(entry.get("subject", "")).strip_edges()
		if not subject.is_empty():
			result.append(subject)
		if result.size() >= 2:
			break
	return result


func _public_formal_memories(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for entry_value: Variant in value as Array:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry := entry_value as Dictionary
		result.append({
			"memoryKey": String(entry.get("memory_id", "")),
			"subject": _player_visible_text(entry.get("subject", "")),
			"interpretation": _player_visible_text(
				entry.get("interpretation", ""),
			),
			"people": _public_person_labels(entry.get("people", [])),
			"places": (entry.get("places", []) as Array).duplicate(),
			"topics": (entry.get("topics", []) as Array).duplicate(),
			"worldTime": (entry.get("world_time", {}) as Dictionary).duplicate(true),
			"sourceKind": String(entry.get("source_kind", "")),
			"confidence": int(entry.get("confidence", 0)),
			"state": String(entry.get("state", "past")),
		})
	return result


func _public_person_labels(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for person_value: Variant in value as Array:
		var label := _public_person_label(person_value)
		if not label.is_empty() and not result.has(label):
			result.append(label)
	return result


func _public_person_label(value: Variant) -> String:
	var person := String(value).strip_edges()
	if person.is_empty():
		return ""
	var me := _initialization.get("me", {}) as Dictionary
	if person == String(me.get("resident_id", "")):
		return String((me.get("attributes", {}) as Dictionary).get("name", "")).strip_edges()
	for resident_value: Variant in _initialization.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		if person == String(resident.get("resident_id", "")):
			return String(resident.get("name", "")).strip_edges()
	if _looks_like_internal_person_id(person):
		return ""
	return _player_visible_text(person).strip_edges()


func _looks_like_internal_person_id(value: String) -> bool:
	var normalized := value.to_lower().strip_edges()
	return (
		normalized.begins_with("resident-")
		or normalized.begins_with("resident_")
		or normalized.begins_with("player-")
		or normalized.begins_with("player_")
		or normalized.begins_with("avatar-")
		or normalized.begins_with("avatar_")
	)


func _public_interventions(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item_value: Variant in value as Array:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item := item_value as Dictionary
		if String(item.get("kind", "")) == "soften":
			continue
		var original_version := item.get("original_version", {}) as Dictionary
		var active_version := item.get("active_version", {}) as Dictionary
		result.append({
			"memoryKey": String(item.get("memory_id", "")),
			"operation": String(item.get("operation", "")),
			"playerText": String(item.get("player_text", "")),
			"originalSubject": _player_visible_text(
				String(original_version.get("subject", "")),
			),
			"originalInterpretation": _player_visible_text(
				String(original_version.get("interpretation", "")),
			),
			"activeSubject": _player_visible_text(
				String(active_version.get("subject", "")),
			),
			"activeInterpretation": _player_visible_text(
				String(active_version.get("interpretation", "")),
			),
			"createdWorldTime": (
				item.get("created_world_time", {}) as Dictionary
			).duplicate(true),
			"status": String(item.get("status", "active")),
		})
	return result


func _public_memory_influence(important_memories: String) -> Dictionary:
	var normalized := important_memories.strip_edges()
	if normalized.is_empty():
		return {
			"available": true,
			"level": 0,
			"segmentCount": 5,
			"label": "尚未形成",
		}
	var level := 1
	for field_name: String in [
		"current_thoughts",
		"short_term_goals",
		"long_term_goals",
		"relationships",
	]:
		if _texts_share_public_topic(
			normalized,
			String(_memory.get(field_name, "")),
		):
			level += 1
	return {
		"available": true,
		"level": mini(level, 5),
		"segmentCount": 5,
		"label": _memory_influence_label(level),
	}


func _texts_share_public_topic(left: String, right: String) -> bool:
	var normalized_right := right.strip_edges()
	if normalized_right.is_empty():
		return false
	for topic: String in _public_topic_terms(left):
		if normalized_right.contains(topic):
			return true
	return false


func _public_topic_terms(text: String) -> Array[String]:
	var normalized := text
	for separator: String in TOPIC_SEPARATORS:
		normalized = normalized.replace(separator, " ")
	var terms: Array[String] = []
	for segment: String in normalized.split(" ", false):
		var clean := segment.strip_edges()
		if clean.length() < 2:
			continue
		if clean.length() == 2:
			if not _is_common_topic(clean) and not terms.has(clean):
				terms.append(clean)
			continue
		for index in range(clean.length() - 1):
			var topic := clean.substr(index, 2)
			if not _is_common_topic(topic) and not terms.has(topic):
				terms.append(topic)
	return terms


func _memory_influence_label(level: int) -> String:
	match clampi(level, 0, 5):
		0:
			return "尚未形成"
		1:
			return "留下印象"
		2:
			return "偶尔想起"
		3:
			return "持续在意"
		4:
			return "明显影响"
		_:
			return "深刻影响"


func seed_debug_memory(memory: Variant) -> Dictionary:
	if _storage_initialized or not _known_action_ids.is_empty() or not _pending_actions.is_empty():
		return _failure("居民记忆开始演进后不能再写入调试初始值")
	var validation := _store.call("validate", memory) as Dictionary
	if not bool(validation.get("ok", false)):
		return validation
	var replacement := _store.call("replace", validation["memory"]) as Dictionary
	if not bool(replacement.get("ok", false)):
		return replacement
	var queue_initialization := _evidence_queue.call("initialize_empty") as Dictionary
	if not bool(queue_initialization.get("ok", false)):
		_clear_resident_storage()
		return queue_initialization
	var archive_initialization := _memory_entry_store.call(
		"initialize_empty",
	) as Dictionary
	if not bool(archive_initialization.get("ok", false)):
		_clear_resident_storage()
		return archive_initialization
	var intervention_initialization := _memory_intervention_store.call(
		"initialize_empty",
	) as Dictionary
	if not bool(intervention_initialization.get("ok", false)):
		_clear_resident_storage()
		return intervention_initialization
	_memory = (replacement["memory"] as Dictionary).duplicate(true)
	_storage_initialized = true
	_last_update = {
		"status": "seeded",
		"persisted_entries": [_memory.duplicate(true)],
	}
	_last_organization = {"status": "idle", "errors": []}
	_last_errors = []
	return {"ok": true, "memory": _memory.duplicate(true)}


func get_debug_snapshot() -> Dictionary:
	var memory_result := _store.call("read") as Dictionary
	var evidence_result := _evidence_queue.call("read") as Dictionary
	var errors: Array = []
	var memory_exists := FileAccess.file_exists(_memory_path)
	var evidence_exists := FileAccess.file_exists(_evidence_path)
	var resident_directory_exists := DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(_resident_root),
	)
	if memory_exists != evidence_exists:
		errors.append("居民记忆与世界证据文件不完整")
	elif not memory_exists and resident_directory_exists:
		errors.append("居民记忆与世界证据文件缺失")
	if not bool(memory_result.get("ok", false)):
		errors.append_array(memory_result.get("errors", []))
	if not bool(evidence_result.get("ok", false)):
		errors.append_array(evidence_result.get("errors", []))
	var memory := (
		(memory_result["memory"] as Dictionary).duplicate(true)
		if bool(memory_result.get("ok", false))
		else {}
	)
	var evidence: Array = (
		(evidence_result["items"] as Array).duplicate(true)
		if bool(evidence_result.get("ok", false))
		else []
	)
	var active_fields := 0
	for field_name: String in MemoryStoreScript.FIELDS:
		# current_thoughts 是当前焦点摘要，不是旧版 active item；待确认
		# 动作仍由 pending_action_count 计入，保持存档调试指标兼容。
		if field_name == "current_thoughts":
			continue
		if not String(memory.get(field_name, "")).strip_edges().is_empty():
			active_fields += 1
	return {
		"resident_id": _resident_id,
		"resident": _resident_name,
		"source": _memory_path,
		"evidence_source": _evidence_path,
		"context": _last_context_fields.duplicate(),
		"context_item_count": _last_context_fields.size(),
		"active_item_count": active_fields + _pending_actions.size(),
		"pending_action_count": _pending_actions.size(),
		"evidence_item_count": evidence.size(),
		"evidence": evidence,
		"memory": memory,
		"read_errors": errors if not errors.is_empty() else _last_errors.duplicate(),
		"limits": {
			"organization_batch": ORGANIZATION_BATCH_SIZE,
			"evidence_queue": EvidenceQueueScript.MAX_ITEMS,
			"memory": _store.call("capacity"),
		},
		"last_update": _last_update.duplicate(true),
		"last_organization": _last_organization.duplicate(true),
	}


func validate_structured_memory(value: Variant) -> Dictionary:
	return _store.call("validate", value)


func capture_persistent_state() -> Dictionary:
	var load_result := _load_current_state(true)
	if not bool(load_result.get("ok", false)):
		return _remember_failure(load_result)
	var queue_capture := _evidence_queue.call("capture_state") as Dictionary
	if not bool(queue_capture.get("ok", false)):
		return _remember_failure(queue_capture)
	var archive_capture := _memory_entry_store.call("read") as Dictionary
	if not bool(archive_capture.get("ok", false)):
		return _remember_failure(archive_capture)
	var intervention_capture := _memory_intervention_store.call("read") as Dictionary
	if not bool(intervention_capture.get("ok", false)):
		return _remember_failure(intervention_capture)
	var pending: Array[Dictionary] = []
	var pending_ids: Array = _pending_actions.keys()
	pending_ids.sort()
	for action_id: Variant in pending_ids:
		pending.append((_pending_actions[action_id] as Dictionary).duplicate(true))
	var action_ids: Array = _known_action_ids.keys()
	action_ids.sort()
	var identity_ids: Array = _observed_identity_ids.keys()
	identity_ids.sort()
	return {
		"ok": true,
		"memory_state": {
			"memory_state_version": MEMORY_STATE_VERSION,
			"resident_id": _resident_id,
			"resident_name": _resident_name,
			"memory": _memory.duplicate(true),
			"evidence_queue": (
				queue_capture["queue_state"] as Dictionary
			).duplicate(true),
			"formal_memory_archive": (
				archive_capture["archive"] as Dictionary
			).duplicate(true),
			"memory_interventions": (
				intervention_capture["log"] as Dictionary
			).duplicate(true),
			"pending_actions": pending,
			"known_action_ids": action_ids,
			"observed_identity_ids": identity_ids,
			"unorganized_since_day": _unorganized_since_day,
		},
	}


func apply_persistent_state(value: Variant) -> Dictionary:
	if (
		FileAccess.file_exists(_memory_path)
		or FileAccess.file_exists(_evidence_path)
		or FileAccess.file_exists(_memory_entries_path)
		or FileAccess.file_exists(_memory_interventions_path)
	):
		return _failure("居民记忆恢复目标不是空目录")
	var validation := _validate_persistent_state(value)
	if not bool(validation.get("ok", false)):
		return validation
	var state := validation["memory_state"] as Dictionary
	var memory_replacement := _store.call("replace", state["memory"]) as Dictionary
	if not bool(memory_replacement.get("ok", false)):
		return memory_replacement
	var queue_application := _evidence_queue.call(
		"apply_state",
		state["evidence_queue"],
	) as Dictionary
	if not bool(queue_application.get("ok", false)):
		_clear_resident_storage()
		return queue_application
	var archive_application := _memory_entry_store.call(
		"replace",
		state["formal_memory_archive"],
	) as Dictionary
	if not bool(archive_application.get("ok", false)):
		_clear_resident_storage()
		return archive_application
	var intervention_application := _memory_intervention_store.call(
		"replace",
		state["memory_interventions"],
	) as Dictionary
	if not bool(intervention_application.get("ok", false)):
		_clear_resident_storage()
		return intervention_application
	_pending_actions.clear()
	for pending_value: Variant in state["pending_actions"]:
		var pending := pending_value as Dictionary
		var action := pending["action"] as Dictionary
		_pending_actions[String(action["action_id"])] = pending.duplicate(true)
	_known_action_ids.clear()
	for action_id: Variant in state["known_action_ids"]:
		_known_action_ids[String(action_id)] = true
	_observed_identity_ids.clear()
	for identity_id: Variant in state["observed_identity_ids"]:
		_observed_identity_ids[String(identity_id)] = true
	_collect_identity_ids(_initialization)
	_memory = (state["memory"] as Dictionary).duplicate(true)
	_unorganized_since_day = int(state["unorganized_since_day"])
	_storage_initialized = true
	_last_update = {"status": "restored", "persisted_entries": []}
	_last_organization = {"status": "idle", "errors": []}
	_last_errors = []
	return {"ok": true, "used_action_ids": _known_action_ids.duplicate()}


func _validate_persistent_state(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民记忆持久状态必须是对象")
	var state := value as Dictionary
	var legacy_fields := [
		"memory_state_version",
		"resident_id",
		"resident_name",
		"memory",
		"evidence_queue",
		"pending_actions",
		"known_action_ids",
		"observed_identity_ids",
		"unorganized_since_day",
	]
	var current_fields := legacy_fields.duplicate()
	current_fields.append_array([
		"formal_memory_archive",
		"memory_interventions",
	])
	var state_version := int(state.get("memory_state_version", -1))
	var legacy_state := (
		state_version == LEGACY_MEMORY_STATE_VERSION
		and _has_exact_fields(state, legacy_fields)
	)
	var current_state := (
		state_version == MEMORY_STATE_VERSION
		and _has_exact_fields(state, current_fields)
	)
	if not legacy_state and not current_state:
		return _failure("居民记忆持久状态字段不完整或包含未知字段")
	if state.get("resident_id") != _resident_id:
		return _failure("居民记忆身份与恢复目标不一致")
	if (
		typeof(state.get("resident_name")) != TYPE_STRING
		or typeof(state.get("pending_actions")) != TYPE_ARRAY
		or typeof(state.get("known_action_ids")) != TYPE_ARRAY
		or typeof(state.get("observed_identity_ids")) != TYPE_ARRAY
		or typeof(state.get("unorganized_since_day")) != TYPE_INT
		or int(state.get("unorganized_since_day")) < 0
	):
		return _failure("居民记忆持久状态字段类型损坏")
	var memory_validation := _store.call("validate", state.get("memory")) as Dictionary
	if not bool(memory_validation.get("ok", false)):
		return memory_validation
	var queue_validation := _evidence_queue.call(
		"validate_state",
		state.get("evidence_queue"),
	) as Dictionary
	if not bool(queue_validation.get("ok", false)):
		return queue_validation
	var archive_value: Variant = (
		_memory_entry_store.call("empty_archive")
		if legacy_state
		else state.get("formal_memory_archive")
	)
	var archive_validation := _memory_entry_store.call(
		"validate",
		archive_value,
	) as Dictionary
	if not bool(archive_validation.get("ok", false)):
		return archive_validation
	var intervention_value: Variant = (
		_memory_intervention_store.call("empty_log")
		if legacy_state
		else state.get("memory_interventions")
	)
	var intervention_validation := _memory_intervention_store.call(
		"validate",
		intervention_value,
	) as Dictionary
	if not bool(intervention_validation.get("ok", false)):
		return intervention_validation
	if (
		int((archive_validation["archive"] as Dictionary)["revision"])
		!= int((intervention_validation["log"] as Dictionary)["revision"])
	):
		return _failure("居民正式记忆与介入记录 revision 不一致")
	var known_ids: Array[String] = []
	var known_set := {}
	for action_id_value: Variant in state["known_action_ids"]:
		if (
			typeof(action_id_value) != TYPE_STRING
			or String(action_id_value).strip_edges().is_empty()
			or known_set.has(action_id_value)
		):
			return _failure("居民记忆动作编号索引损坏")
		known_ids.append(String(action_id_value))
		known_set[String(action_id_value)] = true
	var sorted_ids := known_ids.duplicate()
	sorted_ids.sort()
	if known_ids != sorted_ids:
		return _failure("居民记忆动作编号索引必须按字典序排列")
	var identity_ids: Array[String] = []
	var identity_set := {}
	for identity_id_value: Variant in state["observed_identity_ids"]:
		if (
			typeof(identity_id_value) != TYPE_STRING
			or String(identity_id_value).strip_edges().is_empty()
			or identity_set.has(identity_id_value)
		):
			return _failure("居民记忆人物编号索引损坏")
		identity_ids.append(String(identity_id_value))
		identity_set[String(identity_id_value)] = true
	var sorted_identity_ids := identity_ids.duplicate()
	sorted_identity_ids.sort()
	if identity_ids != sorted_identity_ids:
		return _failure("居民记忆人物编号索引必须按字典序排列")
	var queue_state := queue_validation["queue_state"] as Dictionary
	for item_value: Variant in queue_state["items"]:
		var wake := (item_value as Dictionary)["wake_packet"] as Dictionary
		for result_value: Variant in wake.get("action_results", []) as Array:
			var result_action_id := String(
				(result_value as Dictionary).get("action_id", ""),
			)
			if not known_set.has(result_action_id):
				return _failure("居民证据动作结果不在已使用动作编号索引中")
	var pending: Array[Dictionary] = []
	var pending_set := {}
	for pending_value: Variant in state["pending_actions"]:
		if typeof(pending_value) != TYPE_DICTIONARY:
			return _failure("居民待确认动作必须是对象")
		var pending_item := pending_value as Dictionary
		if not _has_pending_action_fields(pending_item):
			return _failure("居民待确认动作字段损坏")
		if (
			typeof(pending_item.get("decision_id")) != TYPE_STRING
			or String(pending_item.get("decision_id")).strip_edges().is_empty()
			or typeof(pending_item.get("previous_current_thoughts", "")) != TYPE_STRING
			or not _evidence_queue.call(
				"validate_intent_shape",
				pending_item.get("action"),
			)
			or not _valid_saved_time(pending_item.get("submitted_at"))
		):
			return _failure("居民待确认动作类型损坏")
		var action_id := String((pending_item["action"] as Dictionary).get("action_id", ""))
		if (
			action_id.strip_edges().is_empty()
			or pending_set.has(action_id)
			or not known_set.has(action_id)
		):
			return _failure("居民待确认动作编号损坏")
		pending_set[action_id] = true
		pending.append(pending_item.duplicate(true))
	return {
		"ok": true,
		"memory_state": {
			"memory_state_version": MEMORY_STATE_VERSION,
			"resident_id": _resident_id,
			"resident_name": String(state["resident_name"]),
			"memory": (memory_validation["memory"] as Dictionary).duplicate(true),
			"evidence_queue": (
				queue_state
			).duplicate(true),
			"formal_memory_archive": (
				archive_validation["archive"] as Dictionary
			).duplicate(true),
			"memory_interventions": (
				intervention_validation["log"] as Dictionary
			).duplicate(true),
			"pending_actions": pending,
			"known_action_ids": known_ids,
			"observed_identity_ids": identity_ids,
			"unorganized_since_day": int(state["unorganized_since_day"]),
		},
	}


func _load_current_state(initialize_missing: bool = false) -> Dictionary:
	var resident_directory_exists := DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(_resident_root),
	)
	var memory_result := _store.call("read") as Dictionary
	if not bool(memory_result.get("ok", false)):
		return memory_result
	var queue_result := _evidence_queue.ensure_ready()
	if not bool(queue_result.get("ok", false)):
		return queue_result
	var archive_result := _memory_entry_store.call("read") as Dictionary
	if not bool(archive_result.get("ok", false)):
		return archive_result
	var intervention_result := _memory_intervention_store.call("read") as Dictionary
	if not bool(intervention_result.get("ok", false)):
		return intervention_result
	var memory_exists := FileAccess.file_exists(_memory_path)
	var evidence_exists := FileAccess.file_exists(_evidence_path)
	var archive_exists := FileAccess.file_exists(_memory_entries_path)
	var interventions_exist := FileAccess.file_exists(_memory_interventions_path)
	if memory_exists != evidence_exists:
		return _failure("居民记忆与世界证据文件不完整")
	if archive_exists != interventions_exist:
		return _failure("居民正式记忆与介入记录文件不完整")
	if not memory_exists:
		if _storage_initialized or resident_directory_exists:
			return _failure("居民记忆与世界证据文件缺失")
		if initialize_missing:
			var initialization := _store.call(
				"replace",
				_store.call("empty_memory"),
			) as Dictionary
			if not bool(initialization.get("ok", false)):
				return initialization
			var queue_initialization := _evidence_queue.call(
				"initialize_empty",
			) as Dictionary
			if not bool(queue_initialization.get("ok", false)):
				_clear_resident_storage()
				return queue_initialization
	if initialize_missing and not archive_exists:
		var archive_initialization := _memory_entry_store.call(
			"initialize_empty",
		) as Dictionary
		if not bool(archive_initialization.get("ok", false)):
			_clear_resident_storage()
			return archive_initialization
		var intervention_initialization := _memory_intervention_store.call(
			"initialize_empty",
		) as Dictionary
		if not bool(intervention_initialization.get("ok", false)):
			_clear_resident_storage()
			return intervention_initialization
	_memory = (memory_result["memory"] as Dictionary).duplicate(true)
	if initialize_missing or memory_exists:
		_storage_initialized = true
	return {
		"ok": true,
		"formal_memory_archive": (
			archive_result.get("archive", {}) as Dictionary
		).duplicate(true),
		"memory_interventions": (
			intervention_result.get("log", {}) as Dictionary
		).duplicate(true),
	}


func _ingest_wake(wake_packet: Dictionary) -> Dictionary:
	var matched_intents: Array[Dictionary] = []
	var evidence_wake := wake_packet.duplicate(true)
	var evidence_results: Array[Dictionary] = []
	for result_value: Variant in wake_packet.get("action_results", []) as Array:
		var result := result_value as Dictionary
		var action_id := String(result.get("action_id", ""))
		if _pending_actions.has(action_id):
			var pending := _pending_actions[action_id] as Dictionary
			matched_intents.append(
				(pending["action"] as Dictionary).duplicate(true),
			)
			evidence_results.append(result.duplicate(true))
		elif not _is_continuity_action_id(action_id):
			evidence_results.append(result.duplicate(true))
	evidence_wake["action_results"] = evidence_results
	var append_result := _evidence_queue.append_wake(
		evidence_wake,
		matched_intents,
		false,
		true,
	)
	if not bool(append_result.get("ok", false)):
		return append_result
	_collect_identity_ids(wake_packet)
	_collect_identity_ids(matched_intents)
	for result_value: Variant in wake_packet.get("action_results", []) as Array:
		var action_id := String((result_value as Dictionary).get("action_id", ""))
		if _pending_actions.has(action_id):
			var pending := _pending_actions[action_id] as Dictionary
			var restore_result := _restore_pending_current_thought(pending)
			if not bool(restore_result.get("ok", false)):
				return restore_result
		_pending_actions.erase(action_id)
	if bool(append_result.get("added", false)) and _unorganized_since_day == 0:
		_unorganized_since_day = _wake_day(wake_packet)
	return append_result


func _is_continuity_action_id(action_id: String) -> bool:
	# These actions are created and completed by World while continuing an
	# already-submitted service, performance or conversation promise. They are
	# not new Agent intentions, so requiring a fabricated pending action would
	# turn an ordinary World continuation into a memory ingestion failure.
	if (
		action_id.begins_with("service-wait:")
		or action_id.begins_with("performance-listen:")
		or action_id.begins_with("commitment:")
		or action_id.begins_with("escort-follower:")
	):
		return true
	var marker_index := action_id.find("-continuity")
	if marker_index <= 0:
		return false
	var prefix := action_id.left(marker_index)
	var generation_marker := prefix.rfind("-g")
	if generation_marker <= 0:
		return false
	var decision_sequence := prefix.substr(generation_marker + 2).split(
		"-",
		false,
	)
	return (
		decision_sequence.size() == 2
		and String(decision_sequence[0]).is_valid_int()
		and String(decision_sequence[1]).is_valid_int()
	)


func _context_result(
	wake_packet: Dictionary,
	archive_snapshot: Dictionary,
	intervention_snapshot: Dictionary,
) -> Dictionary:
	var formal_entries := archive_snapshot.get("entries", []) as Array
	var interventions := intervention_snapshot.get("interventions", []) as Array
	var selected := _select_decision_memory(
		wake_packet,
		formal_entries,
		_suppressed_memory_ids(interventions),
		_priority_memory_ids(interventions),
	)
	_last_context_fields.clear()
	for field_name: String in MemoryStoreScript.FIELDS:
		if not String(selected.get(field_name, "")).strip_edges().is_empty():
			_last_context_fields.append(field_name)
	return {
		"ok": true,
		"memory_prompt": _render_decision_memory(selected),
	}


func _render_decision_memory(value: Dictionary) -> String:
	var sections: Array[String] = []
	var labels := {
		"important_memories": "重要记忆",
		"relationships": "人物关系",
		"current_thoughts": "当前想法",
		"long_term_goals": "长期目标",
		"short_term_goals": "短期目标",
	}
	for field_name: String in MemoryStoreScript.FIELDS:
		var text := String(value.get(field_name, "")).strip_edges()
		if not text.is_empty():
			sections.append("[%s]\n%s" % [
				labels[field_name],
				PromptTextScript.escape_dynamic(text),
			])
	return "\n\n".join(sections)


func _select_decision_memory(
	wake_packet: Dictionary,
	formal_entries: Array = [],
	suppressed_memory_ids: Dictionary = {},
	priority_memory_ids: Dictionary = {},
) -> Dictionary:
	var selected := _store.call("empty_memory") as Dictionary
	for field_name: String in [
		"current_thoughts",
		"long_term_goals",
		"short_term_goals",
	]:
		selected[field_name] = String(_memory.get(field_name, ""))

	var person_anchors: Array[String] = []
	var subject_anchors: Array[String] = []
	var snapshot := wake_packet.get("snapshot", {}) as Dictionary
	var place := snapshot.get("place", {}) as Dictionary
	_append_anchor(subject_anchors, place.get("name"))
	_append_anchor(subject_anchors, snapshot.get("weather"))
	var me := snapshot.get("me", {}) as Dictionary
	_append_context_text(person_anchors, subject_anchors, me.get("doing"))
	var current_action: Variant = me.get("current_action")
	if typeof(current_action) == TYPE_DICTIONARY:
		_append_action_context(
			person_anchors,
			subject_anchors,
			current_action as Dictionary,
		)
	for prop_value: Variant in place.get("props", []) as Array:
		_append_anchor(subject_anchors, (prop_value as Dictionary).get("name"))
	for nearby_value: Variant in snapshot.get("nearby", []) as Array:
		var nearby := nearby_value as Dictionary
		_append_anchor(person_anchors, nearby.get("resident_id"))
		_append_anchor(person_anchors, nearby.get("name"))
		_append_context_text(person_anchors, subject_anchors, nearby.get("doing"))
	var conversation: Variant = snapshot.get("conversation")
	if typeof(conversation) == TYPE_DICTIONARY:
		var conversation_data := conversation as Dictionary
		_append_anchor(person_anchors, conversation_data.get("with_resident_id"))
		_append_anchor(person_anchors, conversation_data.get("with"))
		_append_turn_anchors(
			person_anchors,
			subject_anchors,
			conversation_data.get("turns", []) as Array,
		)
	for event_value: Variant in wake_packet.get("events", []) as Array:
		var event := event_value as Dictionary
		_append_anchor(person_anchors, event.get("who_resident_id"))
		_append_anchor(person_anchors, event.get("who"))
		_append_anchor(subject_anchors, event.get("weather"))
		_append_context_text(person_anchors, subject_anchors, event.get("text"))
		_append_context_text(person_anchors, subject_anchors, event.get("reason"))
		_append_turn_anchors(
			person_anchors,
			subject_anchors,
			event.get("turns", []) as Array,
		)
		if typeof(event.get("turn")) == TYPE_DICTIONARY:
			_append_turn_context(
				person_anchors,
				subject_anchors,
				event["turn"] as Dictionary,
			)
		for speaker_value: Variant in event.get("speakers", []) as Array:
			_append_anchor(person_anchors, speaker_value)
		for speaker_id_value: Variant in event.get("speaker_resident_ids", []) as Array:
			_append_anchor(person_anchors, speaker_id_value)
	for result_value: Variant in wake_packet.get("action_results", []) as Array:
		var result := result_value as Dictionary
		_append_context_text(person_anchors, subject_anchors, result.get("reason"))

	var relationships := String(_memory.get("relationships", ""))
	selected["relationships"] = _matching_memory_items(
		relationships,
		person_anchors,
	)
	var important := String(_memory.get("important_memories", ""))
	var memory_anchors := person_anchors.duplicate()
	memory_anchors.append_array(subject_anchors)
	selected["important_memories"] = _matching_memory_items(
		important,
		memory_anchors,
	)
	var ranked_formal_memories := _rank_relevant_formal_memories(
		formal_entries,
		person_anchors,
		subject_anchors,
		_wake_day(wake_packet),
		suppressed_memory_ids,
		priority_memory_ids,
	)
	selected["important_memories"] = _merge_formal_memory_recall(
		String(selected.get("important_memories", "")),
		ranked_formal_memories,
		_decision_important_memory_budget(selected),
	)
	return selected


func _append_turn_anchors(
	person_anchors: Array[String],
	subject_anchors: Array[String],
	turns: Array,
) -> void:
	for turn_value: Variant in turns:
		if typeof(turn_value) == TYPE_DICTIONARY:
			_append_turn_context(
				person_anchors,
				subject_anchors,
				turn_value as Dictionary,
			)


func _append_turn_context(
	person_anchors: Array[String],
	subject_anchors: Array[String],
	turn: Dictionary,
) -> void:
	_append_anchor(person_anchors, turn.get("speaker_resident_id"))
	_append_anchor(person_anchors, turn.get("speaker"))
	_append_context_text(person_anchors, subject_anchors, turn.get("say"))
	_append_context_text(person_anchors, subject_anchors, turn.get("narration"))


func _append_action_context(
	person_anchors: Array[String],
	subject_anchors: Array[String],
	action: Dictionary,
) -> void:
	_append_anchor(person_anchors, action.get("target_resident_id"))
	for field_name: String in ["place", "prop", "verb", "line", "say", "narration"]:
		_append_context_text(person_anchors, subject_anchors, action.get(field_name))


func _append_context_text(
	person_anchors: Array[String],
	subject_anchors: Array[String],
	value: Variant,
) -> void:
	if typeof(value) != TYPE_STRING:
		return
	var text := String(value).strip_edges()
	if text.is_empty():
		return
	var topic_text := text
	for resident_value: Variant in _initialization.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		var name := String(resident.get("name", ""))
		if not name.is_empty() and text.contains(name):
			_append_anchor(person_anchors, name)
			_append_anchor(person_anchors, resident.get("resident_id"))
			topic_text = topic_text.replace(name, " ")
		for field_name: String in ["home", "job", "workplace"]:
			var public_subject := String(resident.get(field_name, ""))
			if not public_subject.is_empty() and text.contains(public_subject):
				_append_anchor(subject_anchors, public_subject)
				topic_text = topic_text.replace(public_subject, " ")
	var me := _initialization.get("me", {}) as Dictionary
	var social_state := me.get("social_state", {}) as Dictionary
	for field_name: String in ["home", "job", "workplace"]:
		var own_subject := String(social_state.get(field_name, ""))
		if not own_subject.is_empty() and text.contains(own_subject):
			_append_anchor(subject_anchors, own_subject)
			topic_text = topic_text.replace(own_subject, " ")
	for place_value: Variant in _initialization.get("places", []) as Array:
		var place_name := String((place_value as Dictionary).get("name", ""))
		if not place_name.is_empty() and text.contains(place_name):
			_append_anchor(subject_anchors, place_name)
			topic_text = topic_text.replace(place_name, " ")
	for separator: String in TOPIC_SEPARATORS:
		topic_text = topic_text.replace(separator, " ")
	for segment: String in topic_text.split(" ", false):
		var clean := segment.strip_edges()
		if clean.length() < 2:
			continue
		if clean.length() == 2:
			if not _is_common_topic(clean):
				_append_anchor(subject_anchors, clean)
			continue
		for index in range(clean.length() - 1):
			var topic := clean.substr(index, 2)
			if not _is_common_topic(topic):
				_append_anchor(subject_anchors, topic)


func _player_visible_text(value: Variant) -> String:
	var text := String(value)
	var identity_ids: Array = _observed_identity_ids.keys()
	identity_ids.sort_custom(func(left: Variant, right: Variant) -> bool:
		return String(left).length() > String(right).length()
	)
	for identity_id: Variant in identity_ids:
		text = _without_identity_id(text, identity_id)
	for empty_wrapper: String in ["（）", "()", "（ ）", "( )", "（  ）", "(  )"]:
		text = text.replace(empty_wrapper, "")
	return text


func _without_identity_id(text: String, value: Variant) -> String:
	var identity_id := String(value)
	if identity_id.is_empty():
		return text
	return text \
		.replace("（%s）" % identity_id, "") \
		.replace("(%s)" % identity_id, "") \
		.replace(identity_id, "")


func _collect_identity_ids(value: Variant) -> void:
	if typeof(value) == TYPE_ARRAY:
		for item: Variant in value as Array:
			_collect_identity_ids(item)
		return
	if typeof(value) != TYPE_DICTIONARY:
		return
	var data := value as Dictionary
	for key_value: Variant in data:
		var key := String(key_value)
		var item: Variant = data[key_value]
		if (
			(key == "resident_id" or key.ends_with("_resident_id"))
		):
			_remember_identity_id(item)
		elif (
			(key == "resident_ids" or key.ends_with("_resident_ids"))
			and typeof(item) == TYPE_ARRAY
		):
			for identity_id: Variant in item as Array:
				_remember_identity_id(identity_id)
		_collect_identity_ids(item)


const MAX_OBSERVED_IDENTITY_IDS := 256


func _remember_identity_id(value: Variant) -> void:
	if typeof(value) != TYPE_STRING:
		return
	var identity_id := String(value).strip_edges()
	if identity_id.is_empty() or _observed_identity_ids.has(identity_id):
		return
	# 防止长会话中无上限增长；淘汰最早观察到的编号。
	if _observed_identity_ids.size() >= MAX_OBSERVED_IDENTITY_IDS:
		var oldest: Variant = _observed_identity_ids.keys()[0]
		_observed_identity_ids.erase(oldest)
	_observed_identity_ids[identity_id] = true


const COMMON_TOPIC_WORDS := {
	"今天": true, "现在": true, "已经": true, "没有": true, "这个": true,
	"那个": true, "这里": true, "那里": true, "事情": true, "一下": true,
	"还是": true, "觉得": true, "因为": true, "所以": true, "然后": true,
	"可以": true, "不能": true, "正在": true, "准备": true, "发生": true,
	"打算": true, "继续": true, "明天": true, "昨天": true, "可能": true,
	"需要": true, "想要": true, "看到": true, "听到": true, "我在": true,
	"你在": true, "他在": true, "她在": true, "它在": true, "我要": true,
	"你要": true, "他要": true, "她要": true, "它要": true, "我想": true,
	"你想": true, "他想": true, "她想": true, "它想": true, "我会": true,
	"你会": true, "他会": true, "她会": true, "它会": true, "在找": true,
	"在看": true, "在听": true, "在做": true, "在修": true,
}


func _is_common_topic(value: String) -> bool:
	return COMMON_TOPIC_WORDS.has(value)


func _append_anchor(anchors: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_STRING:
		return
	var text := String(value).strip_edges()
	if text.is_empty() or anchors.has(text):
		return
	anchors.append(text)


func _contains_anchor(text: String, anchors: Array[String]) -> bool:
	for anchor: String in anchors:
		if text.contains(anchor):
			return true
	return false


func _matching_memory_items(text: String, anchors: Array[String]) -> String:
	if text.strip_edges().is_empty() or anchors.is_empty():
		return ""
	var normalized := text.replace("\r", "\n").replace("；", "\n").replace(";", "\n")
	var grouped: Array[String] = []
	var current := ""
	for item_value: Variant in normalized.split("\n", false):
		var item := String(item_value).strip_edges()
		if item.is_empty():
			continue
		if _contains_known_person_anchor(item) and not current.is_empty():
			grouped.append(current)
			current = item
		elif current.is_empty():
			current = item
		else:
			current += "；%s" % item
	if not current.is_empty():
		grouped.append(current)
	var selected: Array[String] = []
	for item: String in grouped:
		if _contains_anchor(item, anchors):
			selected.append(item)
	return "；".join(selected)


func _rank_relevant_formal_memories(
	entries: Array,
	person_anchors: Array[String],
	subject_anchors: Array[String],
	current_day: int,
	suppressed_memory_ids: Dictionary,
	priority_memory_ids: Dictionary = {},
) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for entry_value: Variant in entries:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry := entry_value as Dictionary
		var memory_id := String(entry.get("memory_id", ""))
		if suppressed_memory_ids.has(memory_id):
			continue
		var priority := priority_memory_ids.has(memory_id)
		var relevance := _formal_memory_relevance(
			entry,
			person_anchors,
			subject_anchors,
		)
		if relevance <= 0 and not priority:
			continue
		var ranked_entry := entry.duplicate(true)
		var state := String(entry.get("state", "past"))
		var state_score := 0
		if state in ["doubtful", "anomalous"]:
			state_score = 30
		elif state in ["influencing", "corrected"]:
			state_score = 20
		var memory_day := int(
			(entry.get("world_time", {}) as Dictionary).get("day", 1),
		)
		var recency_score := maxi(0, 8 - absi(current_day - memory_day))
		ranked_entry["_recall_score"] = (
			(240 if priority else 0)
			+ relevance
			+ state_score
			+ int(entry.get("confidence", 0)) / 10
			+ recency_score
		)
		ranked.append(ranked_entry)
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score := int(left.get("_recall_score", 0))
		var right_score := int(right.get("_recall_score", 0))
		if left_score != right_score:
			return left_score > right_score
		var left_revision := int(left.get("updated_revision", 0))
		var right_revision := int(right.get("updated_revision", 0))
		if left_revision != right_revision:
			return left_revision > right_revision
		return String(left.get("memory_id", "")) < String(
			right.get("memory_id", ""),
		)
	)
	for entry: Dictionary in ranked:
		entry.erase("_recall_score")
	return ranked


func _suppressed_memory_ids(interventions: Array) -> Dictionary:
	var suppressed := {}
	for intervention_value: Variant in interventions:
		if typeof(intervention_value) != TYPE_DICTIONARY:
			continue
		var intervention := intervention_value as Dictionary
		if (
			String(intervention.get("status", "")) == "active"
			and String(intervention.get("kind", "")) == "suppress"
		):
			suppressed[String(intervention.get("memory_id", ""))] = true
	return suppressed


func _priority_memory_ids(interventions: Array) -> Dictionary:
	var prioritized := {}
	for intervention_value: Variant in interventions:
		if typeof(intervention_value) != TYPE_DICTIONARY:
			continue
		var intervention := intervention_value as Dictionary
		if String(intervention.get("status", "")) != "active":
			continue
		if (
			String(intervention.get("kind", "")) == "suppress"
			or String(intervention.get("operation", "")) == "delete"
		):
			continue
		var memory_id := String(intervention.get("memory_id", "")).strip_edges()
		if not memory_id.is_empty():
			prioritized[memory_id] = true
	return prioritized


func _formal_memory_relevance(
	entry: Dictionary,
	person_anchors: Array[String],
	subject_anchors: Array[String],
) -> int:
	var score := 0
	for person_value: Variant in entry.get("people", []) as Array:
		if _value_matches_anchors(String(person_value), person_anchors):
			score += 120
	var source_resident_id := String(entry.get("source_resident_id", ""))
	if _value_matches_anchors(source_resident_id, person_anchors):
		score += 90
	var content := "%s\n%s" % [
		String(entry.get("subject", "")),
		String(entry.get("interpretation", "")),
	]
	for anchor: String in person_anchors:
		if not anchor.is_empty() and content.contains(anchor):
			score += 60
	for place_value: Variant in entry.get("places", []) as Array:
		if _value_matches_anchors(String(place_value), subject_anchors):
			score += 50
	for topic_value: Variant in entry.get("topics", []) as Array:
		if _value_matches_anchors(String(topic_value), subject_anchors):
			score += 30
	var matched_subject_anchors := 0
	for anchor: String in subject_anchors:
		if not anchor.is_empty() and content.contains(anchor):
			matched_subject_anchors += 1
			if matched_subject_anchors >= 6:
				break
	score += matched_subject_anchors * 6
	return score


func _value_matches_anchors(value: String, anchors: Array[String]) -> bool:
	var normalized := value.strip_edges()
	if normalized.is_empty():
		return false
	for anchor: String in anchors:
		if (
			not anchor.is_empty()
			and (
				normalized == anchor
				or normalized.contains(anchor)
				or anchor.contains(normalized)
			)
		):
			return true
	return false


func _merge_formal_memory_recall(
	selected_summary: String,
	ranked_entries: Array[Dictionary],
	character_limit: int,
) -> String:
	var result := selected_summary.strip_edges()
	var recalled_count := 0
	for entry: Dictionary in ranked_entries:
		if recalled_count >= FORMAL_RECALL_MAX_ITEMS:
			break
		var subject := String(entry.get("subject", "")).strip_edges()
		var interpretation := String(
			entry.get("interpretation", ""),
		).strip_edges()
		if subject.is_empty() or result.contains(subject):
			continue
		var line := subject
		if not interpretation.is_empty() and interpretation != subject:
			line += "；%s" % interpretation
		var candidate := line if result.is_empty() else "%s\n%s" % [result, line]
		if candidate.length() > character_limit:
			continue
		result = candidate
		recalled_count += 1
	return result


func _decision_important_memory_budget(selected: Dictionary) -> int:
	var other_characters := 0
	for field_name: String in MemoryStoreScript.FIELDS:
		if field_name == "important_memories":
			continue
		other_characters += String(selected.get(field_name, "")).length()
	return maxi(
		0,
		mini(
			DECISION_IMPORTANT_MEMORY_LIMIT,
			DECISION_MEMORY_TOTAL_LIMIT - other_characters,
		),
	)


func _contains_known_person_anchor(text: String) -> bool:
	var me := _initialization.get("me", {}) as Dictionary
	var attributes := me.get("attributes", {}) as Dictionary
	for value: Variant in [
		me.get("resident_id"),
		attributes.get("name"),
	]:
		var anchor := String(value).strip_edges()
		if not anchor.is_empty() and text.contains(anchor):
			return true
	for resident_value: Variant in _initialization.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		for value: Variant in [
			resident.get("resident_id"),
			resident.get("name"),
		]:
			var anchor := String(value).strip_edges()
			if not anchor.is_empty() and text.contains(anchor):
				return true
	for identity_id: Variant in _observed_identity_ids:
		var anchor := String(identity_id).strip_edges()
		if not anchor.is_empty() and text.contains(anchor):
			return true
	return false


func _build_organization_plan(
	wake_packet: Dictionary,
	added_item: bool,
	new_count: int,
) -> Dictionary:
	if _organizer == null:
		return {"ok": true, "triggered": false}
	if new_count <= 0:
		return {"ok": true, "triggered": false}
	var current_day := _wake_day(wake_packet)
	var conversation_ended := added_item and _has_conversation_end(wake_packet)
	var snapshot := wake_packet.get("snapshot", {}) as Dictionary
	var conversation_active := (
		typeof(snapshot.get("conversation")) == TYPE_DICTIONARY
		and not conversation_ended
	)
	var batch_ready := (
		not conversation_active
		and added_item
		and new_count >= ORGANIZATION_BATCH_SIZE
	)
	var crossed_day := (
		not conversation_active
		and _unorganized_since_day > 0
		and current_day > _unorganized_since_day
	)
	if not conversation_ended and not batch_ready and not crossed_day:
		return {"ok": true, "triggered": false}
	# 绝大多数唤醒尚未达到整理条件。只有真正要生成整理请求时才复制
	# 完整证据队列，避免历史越长、普通行走帧越容易出现周期停顿。
	var queue_result := _evidence_queue.call("read") as Dictionary
	if not bool(queue_result.get("ok", false)):
		return queue_result
	var items := queue_result["items"] as Array
	if items.is_empty():
		return {"ok": true, "triggered": false}
	var request := _organizer.call("build_request", _memory, items) as Dictionary
	if not bool(request.get("ok", false)):
		return request
	return {
		"ok": true,
		"triggered": true,
		"request": request,
		"token": {
			"memory_digest": _memory_digest(_memory),
			"queue_digest": _queue_digest(items),
			"current_day": current_day,
		},
	}


func _organization_context(token_value: Variant) -> Dictionary:
	if typeof(token_value) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["居民记忆整理令牌非法"], "safe_to_continue": true}
	var token := token_value as Dictionary
	if not _has_exact_fields(token, ["memory_digest", "queue_digest", "current_day"]):
		return {"ok": false, "errors": ["居民记忆整理令牌字段损坏"], "safe_to_continue": true}
	var load_result := _load_current_state()
	if not bool(load_result.get("ok", false)):
		return load_result
	var queue_result := _evidence_queue.call("read") as Dictionary
	if not bool(queue_result.get("ok", false)):
		return queue_result
	var items := queue_result["items"] as Array
	if (
		String(token.get("memory_digest", "")) != _memory_digest(_memory)
		or String(token.get("queue_digest", "")) != _queue_digest(items)
	):
		return {
			"ok": false,
			"errors": ["居民记忆整理结果已经过期"],
			"safe_to_continue": true,
		}
	return {
		"ok": true,
		"old_memory": _memory.duplicate(true),
		"evidence_items": items.duplicate(true),
	}


func _has_conversation_end(wake_packet: Dictionary) -> bool:
	for event_value: Variant in wake_packet.get("events", []) as Array:
		if (event_value as Dictionary).get("type") == "对话结束":
			return true
	return false


func _wake_day(wake_packet: Dictionary) -> int:
	var snapshot := wake_packet.get("snapshot", {}) as Dictionary
	var time := snapshot.get("time", {}) as Dictionary
	return int(time.get("day", 0))


func _memory_digest(value: Dictionary) -> String:
	return AgentJsonScript.content_sha256(value)


func _queue_digest(value: Array) -> String:
	return AgentJsonScript.content_sha256(value)


func _allocate_standalone_root() -> String:
	_standalone_generation += 1
	return "%s/standalone_%d_%d_%d" % [
		DEFAULT_MEMORY_ROOT,
		OS.get_process_id(),
		Time.get_ticks_usec(),
		_standalone_generation,
	]


static func _resident_storage_segment(resident_id: String) -> String:
	if resident_id.length() <= MAX_RESIDENT_STORAGE_SEGMENT_LENGTH:
		return resident_id
	return "resident-%s" % (
		resident_id.sha256_text().left(RESIDENT_STORAGE_KEY_LENGTH)
	)


func _remember_failure(result: Dictionary) -> Dictionary:
	_last_errors.assign(result.get("errors", []))
	_last_update = {
		"status": "error",
		"errors": _last_errors.duplicate(),
		"persisted_entries": [],
	}
	return result


func _organization_failure(result: Dictionary, safe_to_continue: bool) -> Dictionary:
	var failure := result.duplicate(true)
	failure["ok"] = false
	failure["safe_to_continue"] = safe_to_continue
	_last_errors.assign(failure.get("errors", []))
	_last_update = {
		"status": "organization_error",
		"errors": _last_errors.duplicate(),
		"persisted_entries": [],
	}
	_last_organization = {
		"status": "organization_error",
		"errors": _last_errors.duplicate(),
		"persisted_entries": [],
	}
	return failure


func _clear_resident_storage() -> void:
	for path: String in [_memory_path, "%s.tmp" % _memory_path, "%s.bak" % _memory_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_evidence_queue.call("erase_storage")
	_memory_entry_store.call("erase_storage")
	_memory_intervention_store.call("erase_storage")


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_name: Variant in fields:
		if not value.has(field_name):
			return false
	return true


func _has_pending_action_fields(value: Dictionary) -> bool:
	if _has_exact_fields(value, ["decision_id", "action", "submitted_at"]):
		return true
	return _has_exact_fields(value, [
		"decision_id",
		"action",
		"submitted_at",
		"previous_current_thoughts",
	])


func _restore_pending_current_thought(pending: Dictionary) -> Dictionary:
	var action := pending.get("action", {}) as Dictionary
	var action_line := String(action.get("line", "")).strip_edges()
	var previous := String(pending.get("previous_current_thoughts", ""))
	if action_line.is_empty() or String(_memory.get("current_thoughts", "")).strip_edges() != action_line:
		return {"ok": true}
	_memory["current_thoughts"] = previous
	var write_result := _store.replace(_memory)
	if not bool(write_result.get("ok", false)):
		_memory["current_thoughts"] = action_line
		return write_result
	return {"ok": true}


func _valid_saved_time(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var time := value as Dictionary
	if not _has_exact_fields(time, ["day", "clock", "period"]):
		return false
	var clock := String(time.get("clock", ""))
	return (
		typeof(time.get("day")) == TYPE_INT
		and int(time.get("day")) > 0
		and typeof(time.get("clock")) == TYPE_STRING
		and clock.length() == 5
		and clock[2] == ":"
		and clock.substr(0, 2).is_valid_int()
		and clock.substr(3, 2).is_valid_int()
		and int(clock.substr(0, 2)) >= 0
		and int(clock.substr(0, 2)) <= 23
		and int(clock.substr(3, 2)) >= 0
		and int(clock.substr(3, 2)) <= 59
		and typeof(time.get("period")) == TYPE_STRING
		and String(time.get("period")) in AgentContractScript.PERIODS
		and AgentContractScript.period_for_clock(clock)
			== String(time.get("period"))
	)


func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}
