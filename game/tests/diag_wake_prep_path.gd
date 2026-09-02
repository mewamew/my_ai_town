extends SceneTree
## diag_wake_prep_path.gd — 真实游戏 wake 准备路径（TownAgentWakePreparationRuntime）狼人杀附件验证
##
## 背景：真实游戏 gateway 的 wake 由 advance_pending_decision_preparation_by_id
## （TownAgentWakePreparationRuntime.advance）分段构建，**不经过**
## TownAgentWakeContextRuntime.wake_packet。本探针验证 finalize 阶段注入的
## 5 个狼人杀附件键：exile_vote / night_skill / undercover_kill_quota_exhausted /
## town_death_cases / police_intel（2026-08-25 修复后）。

const SOURCE_DIR := "res://world/data/town/source"
const BUILDER := preload(
	"res://world/data/town/TownWorldDataBuilder.gd"
)
const RESIDENT_CATALOG := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)
const COMPILER := preload(
	"res://world/presentation/session/TownNewGameOpeningCompiler.gd"
)
const WORLD := preload(
	"res://world/runtime/TownWorldRuntime.gd"
)

const POLICE_ID := "resident_wen_xu_01"
const CIVILIAN_ID := "resident_lin_lan_01"
const PREP_KEYS := [
	"exile_vote",
	"night_skill",
	"undercover_kill_quota_exhausted",
	"town_death_cases",
	"police_intel",
]

var _checks := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [OK] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _run() -> void:
	print("===== 真实准备路径狼人杀附件注入验证 =====\n")
	var world := _build_world()
	if world == null:
		quit(1)
		return

	# 1) 警察闻叙走完整准备管线
	var police_wake: Dictionary = _prepare_decision(world, POLICE_ID, "prep-police-1")
	_expect(not police_wake.is_empty(), "闻叙准备管线完成(拿到 wakePacket)")
	var police_snapshot: Dictionary = police_wake.get("snapshot", {}) as Dictionary
	for key: String in PREP_KEYS:
		_expect(
			police_snapshot.has(key),
			"闻叙 snapshot 含附件键 %s" % key,
		)
	var police_intel: Dictionary = police_snapshot.get("police_intel", {}) as Dictionary
	print(
		"闻叙 snapshot.police_intel = %s"
		% [JSON.stringify(police_intel)]
	)
	_expect(
		not police_intel.is_empty() and int(police_intel.get("trackerCharges", 0)) > 0,
		"闻叙 police_intel 非空且 trackerCharges > 0",
	)

	# 2) 普通居民林岚: 键存在但 police_intel 为空
	var civilian_wake: Dictionary = _prepare_decision(world, CIVILIAN_ID, "prep-civilian-1")
	var civilian_snapshot: Dictionary = civilian_wake.get("snapshot", {}) as Dictionary
	for key: String in PREP_KEYS:
		_expect(
			civilian_snapshot.has(key),
			"林岚 snapshot 含附件键 %s" % key,
		)
	_expect(
		(civilian_snapshot.get("police_intel", {}) as Dictionary).is_empty(),
		"林岚 police_intel 为空(非警察)",
	)

	# 3) 附件键值语义: 第1天非投票窗口时 exile_vote 为空字典但键存在
	_expect(
		(police_snapshot.get("exile_vote", {}) as Dictionary).is_empty(),
		"第1天非投票窗口 exile_vote 为空字典",
	)

	print(
		"\nWAKE_PREP_PATH_RESULT: checks=%d failed=%d"
		% [_checks, _failed]
	)
	quit(1 if _failed > 0 else 0)


## 走完整准备管线(多阶段推进)直到 ready, 返回 wakePacket。
func _prepare_decision(world: RefCounted, resident_id: String, decision_id: String) -> Dictionary:
	var residents: Dictionary = world.call("residents")
	var resident := residents.get(resident_id, {}) as Dictionary
	if resident.is_empty():
		return {}
	resident["decisionPending"] = true
	resident["validDecisionId"] = decision_id
	resident["wakeDispatchQueued"] = true
	resident["pendingWake"] = {"events": [], "action_results": []}
	# 新局开场居民尚未"到达", 准备管线要求在场; 手动置为已到达。
	resident["arrivalState"] = {"status": "arrived"}
	for step in range(40):
		var result := world.call(
			"advance_pending_decision_preparation_by_id",
			resident_id,
			decision_id,
		) as Dictionary
		if bool(result.get("ok", false)) and not bool(result.get("preparationPending", false)):
			var wake: Dictionary = result.get("wakePacket", {}) as Dictionary
			if not wake.is_empty():
				return wake
			return {}
		if bool(result.get("stale", false)):
			return {}
	return {}


func _build_world() -> RefCounted:
	var world_data := BUILDER.build_from_source(SOURCE_DIR)
	var view_model := RESIDENT_CATALOG.build_view_model(
		"302-ai", "deepseek-v4-flash-0731", true, 1,
	) as Dictionary
	var selection := (
		view_model.get("data", {}) as Dictionary
	).duplicate(true)
	selection["selected_resident_ids"] = (
		selection.get("recommended_resident_ids", []) as Array
	).duplicate()
	RESIDENT_CATALOG.update_confirmation_payload(
		selection, "302-ai", "deepseek-v4-flash-0731", 2,
	)
	var compiled := COMPILER.compile(
		selection.get("confirmation_payload", {}) as Dictionary,
		world_data,
		RESIDENT_CATALOG.load_catalog(),
	) as Dictionary
	if compiled.get("ok") != true:
		printerr("COMPILE_FAIL: %s" % [compiled])
		return null
	var opening := compiled.get("openingConfig", {}) as Dictionary
	var identities: Array[Dictionary] = []
	for binding: Variant in (
		compiled.get("residentBindings", []) as Array
	):
		var b := binding as Dictionary
		identities.append({
			"residentId": String(b.get("residentId", "")),
			"residentName": String(b.get("residentName", "")),
		})
	var world: RefCounted = WORLD.new()
	world.call("start_formal", world_data, opening, identities)
	return world
