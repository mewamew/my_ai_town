class_name TownSaveJournalStates
extends RefCounted
## 存档/恢复日志状态机唯一事实源(批次D之5,三处常量表合一,内容逐字保留)。
## Store/Coordinator 引用本表;restore_completed 的兜底行为在 Store 原地未动。


const SAVE_STAGES: Array[String] = [
	"save_started",
	"world_candidate_written",
	"agent_commit_started",
	"agent_committed",
	"world_committed",
	"manifest_published",
	"agent_commit_failed",
	"agent_commit_uncertain",
	"agent_orphan_isolated",
	"save_reconciled",
	"transaction_failed",
]

const RESTORE_STAGES: Array[String] = [
	"restore_started",
	"restore_world_prepared",
	"restore_agent_started",
	"restore_agent_hydrated",
	"restore_world_validated",
	"restore_agent_commit_started",
	"restore_agent_committed",
	"restore_world_committed",
	"restore_completed",
	"restore_reconciled",
	"transaction_failed",
]

const STAGE_ORDER := {
	"save_started": 1,
	"world_candidate_written": 10,
	"agent_commit_started": 20,
	"agent_committed": 30,
	"world_committed": 40,
	"manifest_published": 50,
	"restore_started": 110,
	"restore_world_prepared": 120,
	"restore_agent_started": 130,
	"restore_agent_hydrated": 140,
	"restore_world_validated": 150,
	"restore_agent_commit_started": 155,
	"restore_agent_committed": 160,
	"restore_world_committed": 170,
	"restore_completed": 180,
	"agent_commit_failed": 210,
	"agent_commit_uncertain": 220,
	"agent_orphan_isolated": 230,
	"transaction_failed": 240,
	"save_reconciled": 250,
	"restore_reconciled": 250,
}

const SAVE_TRANSITIONS := {
	"save_started": ["world_candidate_written", "transaction_failed", "save_reconciled"],
	"world_candidate_written": ["agent_commit_started", "transaction_failed", "save_reconciled"],
	"agent_commit_started": [
		"agent_committed",
		"agent_commit_failed",
		"agent_commit_uncertain",
		"agent_orphan_isolated",
		"save_reconciled",
	],
	"agent_committed": ["world_committed", "agent_orphan_isolated", "save_reconciled"],
	"world_committed": ["manifest_published", "agent_orphan_isolated", "save_reconciled"],
	"agent_commit_failed": ["save_reconciled"],
	"agent_commit_uncertain": ["agent_orphan_isolated", "save_reconciled"],
	"agent_orphan_isolated": ["save_reconciled"],
	"transaction_failed": ["save_reconciled"],
}

const RESTORE_TRANSITIONS := {
	"restore_started": ["restore_world_prepared", "transaction_failed", "restore_reconciled"],
	"restore_world_prepared": ["restore_agent_started", "transaction_failed", "restore_reconciled"],
	"restore_agent_started": ["restore_agent_hydrated", "transaction_failed", "restore_reconciled"],
	"restore_agent_hydrated": ["restore_world_validated", "transaction_failed", "restore_reconciled"],
	"restore_world_validated": [
		"restore_agent_commit_started",
		"transaction_failed",
		"restore_reconciled",
	],
	"restore_agent_commit_started": [
		"restore_agent_committed",
		"transaction_failed",
		"restore_reconciled",
	],
	"restore_agent_committed": [
		"restore_world_committed",
		"transaction_failed",
		"restore_reconciled",
	],
	"restore_world_committed": ["restore_completed", "transaction_failed", "restore_reconciled"],
	"transaction_failed": ["restore_reconciled"],
}

const SAVE_TRANSACTION_FAILED_STAGES: Array[String] = [
	"gate_begin",
	"world_prepare",
	"world_candidate_write",
	"world_validate",
	"gate_validate",
]

const RESTORE_TRANSACTION_FAILED_STAGES: Array[String] = [
	"world_prepare",
	"agent_prepare",
	"agent_resident_set",
	"agent_hydrate",
	"world_validate",
	"gate_validate",
	"agent_commit",
	"world_commit_after_agent",
	"post_commit_validation",
]


static func classify_incomplete(
	kind: String,
	state: String,
	payload: Dictionary,
) -> Dictionary:
	if kind == "save":
		if state in ["agent_commit_started", "agent_commit_uncertain"]:
			return {
				"classification": "agent_commit_uncertain",
				"errorCode": "SESSION_SAVE_AGENT_COMMIT_UNCERTAIN",
			}
		if state in ["agent_committed", "world_committed", "agent_orphan_isolated"]:
			return {
				"classification": "agent_orphan_isolated",
				"errorCode": "SESSION_SAVE_AGENT_ORPHAN_ISOLATED",
			}
	elif kind == "restore":
		if state in ["restore_agent_started", "restore_agent_commit_started"]:
			return {
				"classification": "restore_agent_uncertain",
				"errorCode": "SESSION_CONTINUE_AGENT_COMMIT_UNCERTAIN",
			}
		if state in ["restore_agent_committed", "restore_world_committed"]:
			return {
				"classification": "restore_partial_commit",
				"errorCode": "SESSION_CONTINUE_PARTIAL_COMMIT",
			}
		if state == "transaction_failed":
			var failed_stage := String(payload.get("stage", ""))
			if failed_stage == "agent_commit":
				return {
					"classification": "restore_agent_uncertain",
					"errorCode": "SESSION_CONTINUE_AGENT_COMMIT_UNCERTAIN",
				}
			if failed_stage in ["world_commit_after_agent", "post_commit_validation"]:
				return {
					"classification": "restore_partial_commit",
					"errorCode": "SESSION_CONTINUE_PARTIAL_COMMIT",
				}
	return {
		"classification": "pre_agent_cleanup",
		"errorCode": "SESSION_SAVE_INCOMPLETE_CANDIDATE",
	}
