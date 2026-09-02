extends SceneTree
## diag_role_stance.gd — 身份立场层 + 角色规则注入的 production 链路验证
##
## 目标（真实 catalog 建 world, 不调 API）:
##   1) 卧底三人(谢眠/乔一鸣/花子): get_agent_initialization 的 me.is_undercover==true
##      → compile 后 system 含 undercover.md(卧底行动规则) + 身份立场(卧底声明)
##      + 个人守则(resident_<id>.md), 且 role_stance 在 <rules> 之前
##   2) 警察(闻叙): system 含 police.md + 身份立场(警察声明), 无 is_undercover
##   3) 普通居民(林岚/米芽): 无 role_stance 无 role_rules, 与官方行为一致
## 修复背景: 此前生产链路无人设置 me.is_undercover, 卧底专属规则从未注入。

const SOURCE_DIR := "res://world/data/town/source"
const BUILDER := preload("res://world/data/town/TownWorldDataBuilder.gd")
const RESIDENT_CATALOG := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)
const COMPILER := preload(
	"res://world/presentation/session/TownNewGameOpeningCompiler.gd"
)
const WORLD := preload("res://world/runtime/TownWorldRuntime.gd")
const PROMPT_COMPILER := preload("res://agent/prompt/AgentPromptCompiler.gd")

const UNDERCOVER_IDS := [
	"resident_xie_mian_01", "resident_qiao_yiming_01", "resident_hanako_01",
]
const POLICE_ID := "resident_wen_xu_01"
const CIVILIAN_ID := "resident_lin_lan_01"
const CIVILIAN2_ID := "resident_mi_ya_01"

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
	print("===== 身份立场层 + 角色规则 production 链路验证 =====\n")
	var world := _build_world()
	if world == null:
		quit(1)
		return

	for undercover_id: String in UNDERCOVER_IDS:
		_verify_undercover(world, undercover_id)
	_verify_police(world)
	_verify_civilian(world, CIVILIAN_ID)
	_verify_civilian(world, CIVILIAN2_ID)

	print(
		"\nROLE_STANCE_RESULT: checks=%d failed=%d"
		% [_checks, _failed]
	)
	quit(1 if _failed > 0 else 0)


func _verify_undercover(world: RefCounted, resident_id: String) -> void:
	var init: Dictionary = world.call("get_agent_initialization", resident_id)
	var me: Dictionary = init.get("me", {}) as Dictionary
	var resident_name := String(
		(me.get("attributes", {}) as Dictionary).get("name", resident_id)
	)
	print("--- 卧底 %s(%s) ---" % [resident_name, resident_id])
	_expect(
		bool(me.get("is_undercover", false)) == true,
		"me.is_undercover == true（undercover.md 注入前提）",
	)
	var system_text := _compile_system(world, resident_id, init)
	_expect(
		system_text.contains("卧底行动规则"),
		"system 含 undercover.md（卧底行动规则）",
	)
	_expect(
		system_text.contains("潜伏在镇上的卧底杀手"),
		"system 含身份立场（卧底覆盖声明）",
	)
	_expect(
		system_text.contains("绝不主动向警察闻叙"),
		"身份立场明确'不主动配合警察/自曝'",
	)
	var stance_at := system_text.find("</role_stance>")
	var rules_at := system_text.find("<rules>")
	_expect(
		stance_at >= 0 and rules_at >= 0 and stance_at < rules_at,
		"身份立场在 <rules> 通用规则之前",
	)
	_expect(
		not system_text.contains("全镇唯一的执法者"),
		"卧底不误注入警察身份立场",
	)
	var personal := ""
	if resident_id == "resident_xie_mian_01":
		personal = "谢眠的个人守则"
	elif resident_id == "resident_qiao_yiming_01":
		personal = "乔一鸣的个人守则"
	elif resident_id == "resident_hanako_01":
		personal = "花子的个人守则"
	_expect(
		system_text.contains(personal),
		"system 含个人守则（%s.md）" % resident_id,
	)


func _verify_police(world: RefCounted) -> void:
	var init: Dictionary = world.call("get_agent_initialization", POLICE_ID)
	var me: Dictionary = init.get("me", {}) as Dictionary
	print("--- 警察 闻叙 ---")
	_expect(
		bool(me.get("is_undercover", false)) == false,
		"警察 me.is_undercover == false",
	)
	var system_text := _compile_system(world, POLICE_ID, init)
	_expect(
		system_text.contains("警察查案规则"),
		"system 含 police.md（警察查案规则）",
	)
	_expect(
		system_text.contains("全镇唯一的执法者"),
		"system 含身份立场（警察覆盖声明）",
	)
	var stance_at := system_text.find("</role_stance>")
	var rules_at := system_text.find("<rules>")
	_expect(
		stance_at >= 0 and rules_at >= 0 and stance_at < rules_at,
		"身份立场在 <rules> 通用规则之前",
	)
	_expect(
		not system_text.contains("潜伏在镇上的卧底杀手"),
		"警察不误注入卧底身份立场",
	)


func _verify_civilian(world: RefCounted, resident_id: String) -> void:
	var init: Dictionary = world.call("get_agent_initialization", resident_id)
	var me_init: Dictionary = init.get("me", {}) as Dictionary
	var attrs_init: Dictionary = me_init.get("attributes", {}) as Dictionary
	var resident_name := String(attrs_init.get("name", resident_id))
	print("--- 普通居民 %s ---" % resident_name)
	var system_text := _compile_system(world, resident_id, init)
	_expect(
		not system_text.contains("<role_stance>"),
		"%s 无身份立场层" % resident_name,
	)
	# 普通居民允许有个人规则(resident_<id>.md, 如林岚), 但绝不能有身份专属规则。
	_expect(
		not system_text.contains("卧底行动规则"),
		"%s 无卧底专属规则" % resident_name,
	)
	_expect(
		not system_text.contains("警察查案规则"),
		"%s 无警察专属规则" % resident_name,
	)


func _compile_system(
	world: RefCounted, resident_id: String, init: Dictionary,
) -> String:
	var compiler := PROMPT_COMPILER.new(init)
	var wake := {
		"snapshot": {
			"me": {},
			"nearby": [],
			"place": {},
		},
		"pending_wake": {
			"events": [],
			"action_results": [],
		},
	}
	var compiled: Dictionary = compiler.call("compile", wake, "", "")
	var messages: Array = compiled.get("messages", []) as Array
	if messages.is_empty():
		_expect(false, "%s compile 返回 messages" % resident_id)
		return ""
	return String((messages[0] as Dictionary).get("content", ""))


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
