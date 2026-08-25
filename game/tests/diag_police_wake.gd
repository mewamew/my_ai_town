extends SceneTree
## diag_police_wake.gd — 警察侦查装备 wake 链路离线验证
##
## 目标：用真实 catalog（狼人杀版 16 居民）建 world，直接检查：
##   1) 闻叙(resident_wen_xu_01) 的 socialState.job 是不是"警察"
##   2) world._werewolf_state.roleSkills.police 里有没有 eavesdropCharges/trackerCharges
##   3) _police_intel_context(world, "resident_wen_xu_01") 返回什么
##   4) 走完整 wake_packet 链路后 snapshot.police_intel 是否有值
##   5) AgentPromptCompiler 编译后 prompt 是否含"窃听"/"定位"动作
## 全程不调用 API（fake provider 不可用则跳过决策编译步骤）。

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
const WAKE_CONTEXT := preload(
	"res://world/runtime/agent/TownAgentWakeContextRuntime.gd"
)
const PROMPT_COMPILER := preload(
	"res://agent/prompt/AgentPromptCompiler.gd"
)

const POLICE_ID := "resident_wen_xu_01"
const TARGET_ID := "resident_lin_lan_01"
const FAR_ID := "resident_tang_xiaoman_01"

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
	print("===== 警察侦查装备 wake 链路验证 =====\n")
	var world := _build_world()
	if world == null:
		quit(1)
		return

	# 1) 闻叙 socialState
	var residents: Dictionary = world.call("residents")
	var wen: Dictionary = residents.get(POLICE_ID, {}) as Dictionary
	var social: Dictionary = wen.get("socialState", {}) as Dictionary
	print("闻叙 socialState.job = '%s'" % String(social.get("job", "")))
	_expect(
		String(social.get("job", "")) == "警察",
		"闻叙 job 为 警察（_resident_is_police 前提）",
	)
	_expect(
		world.call("_resident_is_police", POLICE_ID) == true,
		"world._resident_is_police(resident_wen_xu_01) == true",
	)

	# 2) werewolfState.roleSkills.police
	var werewolf_state: Dictionary = world.get("_werewolf_state")
	var role_skills: Dictionary = werewolf_state.get(
		"roleSkills", {}
	) as Dictionary
	var police_skills: Dictionary = role_skills.get("police", {}) as Dictionary
	print(
		"roleSkills.police = %s" % [JSON.stringify(police_skills)]
	)
	_expect(
		int(police_skills.get("eavesdropCharges", -1)) > 0,
		"police.eavesdropCharges 存在且 > 0",
	)
	_expect(
		int(police_skills.get("trackerCharges", -1)) > 0,
		"police.trackerCharges 存在且 > 0",
	)

	# 3) _police_intel_context 直接调用 —— targets 只列感知范围内的人
	#    林岚移到闻叙旁边(距离 50), 唐小满移到远处(距离 900 > 320)
	var residents_now: Dictionary = world.call("residents")
	_place_test(residents_now, POLICE_ID, Vector2(100, 100))
	_place_test(residents_now, TARGET_ID, Vector2(150, 100))
	_place_test(residents_now, FAR_ID, Vector2(1000, 100))
	var intel: Dictionary = WAKE_CONTEXT._police_intel_context(
		world, POLICE_ID
	)
	print("_police_intel_context = %s" % [JSON.stringify(intel)])
	_expect(not intel.is_empty(), "_police_intel_context 非空")
	_expect(
		int(intel.get("eavesdropCharges", 0)) > 0,
		"intel.eavesdropCharges > 0",
	)
	var intel_targets := intel.get("targets", []) as Array
	_expect(
		intel_targets.has(TARGET_ID),
		"intel.targets 含近处目标（林岚, 距离50）",
	)
	_expect(
		not intel_targets.has(FAR_ID),
		"intel.targets 不含远处目标（唐小满, 距离900）",
	)

	# 4) 完整 wake_packet 链路（手动构造 pendingWake）
	var wen_resident := residents[POLICE_ID] as Dictionary
	wen_resident["pendingWake"] = {
		"events": [],
		"action_results": [],
	}
	var wake: Dictionary = WAKE_CONTEXT.wake_packet(
		world,
		POLICE_ID,
		wen_resident,
		"police-wake-diag",
		[],
		[],
	)
	var snapshot: Dictionary = wake.get("snapshot", {}) as Dictionary
	var wake_intel: Dictionary = snapshot.get(
		"police_intel", {}
	) as Dictionary
	print("snapshot.police_intel = %s" % [JSON.stringify(wake_intel)])
	_expect(not wake_intel.is_empty(), "wake.snapshot.police_intel 非空")

	# 5) AgentPromptCompiler 编译（用无 provider 的 fake 初始化，只验证 prompt 内容）
	var compiler := PROMPT_COMPILER.new(
		world.call("get_agent_initialization", POLICE_ID)
	)
	var compiled: Dictionary = compiler.call(
		"compile", wake, "", ""
	)
	var messages: Array = compiled.get("messages", []) as Array
	var full_content := ""
	for message: Variant in messages:
		var text := String((message as Dictionary).get("content", ""))
		full_content += text
	var has_eavesdrop := full_content.contains("窃听")
	var has_tracker := full_content.contains("定位")
	print(
		"prompt 含窃听=%s 含定位=%s（messages=%d）"
		% [has_eavesdrop, has_tracker, messages.size()]
	)
	_expect(has_eavesdrop, "prompt 含「窃听」动作与说明")
	_expect(has_tracker, "prompt 含「定位」动作与说明")

	print(
		"\nPOLICE_WAKE_RESULT: checks=%d failed=%d"
		% [_checks, _failed]
	)
	quit(1 if _failed > 0 else 0)


func _place_test(
	residents: Dictionary, resident_id: String, pos: Vector2,
) -> void:
	var r: Variant = residents.get(resident_id)
	if not r is Dictionary:
		print("  [FAIL] %s 存在" % resident_id)
		_failed += 1
		_checks += 1
		return
	(r as Dictionary)["spaceId"] = "town_outdoor"
	(r as Dictionary)["regionId"] = "outdoor_plaza_01"
	(r as Dictionary)["currentPlace"] = "中心广场"
	(r as Dictionary)["position"] = pos
	(r as Dictionary)["currentAction"] = {}
	var arrival: Dictionary = (r as Dictionary).get(
		"arrivalState", {}
	) as Dictionary
	arrival["status"] = "arrived"
	(r as Dictionary)["arrivalState"] = arrival


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
