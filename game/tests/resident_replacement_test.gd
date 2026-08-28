extends "res://tests/support/TownWorldTestCase.gd"


const AGENT_SOUL_PROFILE := preload("res://agent/soul/AgentSoulProfile.gd")
const AGENT_CONTRACT := preload("res://agent/AgentContract.gd")
const GAME_FLOW_HOST := preload(
	"res://world/presentation/game_flow/GameFlowHost.gd"
)
const RESIDENT_REPLACEMENT := preload(
	"res://world/runtime/lifecycle/TownResidentReplacementAdmission.gd"
)


class ReturnToStartGateway:
	extends Node
	var calls := 0
	var cancel_calls := 0
	var clear_calls := 0
	var messages: Array[Dictionary] = [{
		"message_id": "resident-message-return-test",
		"resident_id": "resident-lin-lan",
		"resident_name": "林岚",
		"content": "下次回来，记得告诉我路上看见了什么。",
	}]

	func cancel_background_departure_messages() -> Dictionary:
		cancel_calls += 1
		return {"ok": true, "changed": true}

	func get_background_departure_messages() -> Array[Dictionary]:
		return messages.duplicate(true)

	func clear_background_departure_messages() -> Dictionary:
		clear_calls += 1
		return {"ok": true, "changed": true}


class EmptyBackgroundDepartureGateway:
	extends Node

	func cancel_background_departure_messages() -> Dictionary:
		return {"ok": true, "changed": false}

	func get_background_departure_messages() -> Array[Dictionary]:
		return []


class DepartureSaveService:
	extends RefCounted
	var request: Dictionary = {}

	func get_save_snapshot() -> Dictionary:
		return {"canSave": true}

	func create_save(value: Dictionary) -> Dictionary:
		request = value.duplicate(true)
		return {"ok": true, "errorCode": "", "retryable": false}


class BaseDepartureHarness:
	extends "res://world/presentation/game_flow/GameFlowHost.gd"

	func _begin_town_entry_loading(
		_route_kind: String,
		_generation := -1,
		_owner := "",
		_context: Dictionary = {},
	) -> void:
		pass

	func _advance_town_entry_loading(
		_progress: float,
		_status_text: String,
	) -> void:
		pass


class ReturnToStartWiringHarness:
	extends "res://world/presentation/game_flow/GameFlowHost.gd"
	var saved_messages: Array = []
	var routed_departures: Array[Dictionary] = []
	var process_quit_count := 0

	func _begin_town_entry_loading(
		_route_kind: String,
		_generation := -1,
		_owner := "",
		_context: Dictionary = {},
	) -> void:
		pass

	func _advance_town_entry_loading(
		_progress: float,
		_status_text: String,
	) -> void:
		pass

	func _prepare_session_departure(
		resident_messages: Array = [],
	) -> Dictionary:
		saved_messages = resident_messages.duplicate(true)
		if (
			saved_messages.is_empty()
			and _gateway != null
			and _gateway.has_method("get_background_departure_messages")
		):
			saved_messages = (
				_gateway.call("get_background_departure_messages") as Array
			).duplicate(true)
		return {"ok": true, "errorCode": "", "retryable": false}

	func _route_to_start_after_departure(
		departure: Dictionary,
	) -> Dictionary:
		routed_departures.append(departure.duplicate(true))
		return departure

	func _schedule_process_quit() -> void:
		process_quit_count += 1


class NeverCompletingProvider:
	extends RefCounted
	var callback := Callable()

	func request_json(_request: Dictionary, on_complete: Callable) -> void:
		callback = on_complete

	func complete(result: Dictionary) -> void:
		if callback.is_valid():
			callback.call(result.duplicate(true))


class ReplacementProviderService:
	extends RefCounted
	var provider: NeverCompletingProvider

	func _init(value: NeverCompletingProvider) -> void:
		provider = value

	func create_provider_for_resident(_binding: Dictionary) -> Dictionary:
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"provider": provider,
		}


class GameFlowRecoveryHarness:
	extends "res://world/presentation/game_flow/GameFlowHost.gd"
	var presented_replacements: Array[Dictionary] = []

	func _present_generated_replacement(candidate: Dictionary) -> void:
		presented_replacements.append(candidate.duplicate(true))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_return_to_start_does_not_wait_for_messages()
	var data := _build_data()
	var opening := _load_opening(data)
	var identities: Array[Dictionary] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		identities.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(
				(resident.get("attributes", {}) as Dictionary).get("name", "")
			),
		})
	var world := WORLD.new()
	var started := world.start(data, opening, identities) as Dictionary
	_expect(
		bool(started.get("ok", false)),
		"世界可以启动：%s" % JSON.stringify(started.get("errors", [])),
	)
	_expect_equal(
		RESIDENT_REPLACEMENT.target_resident_count(world),
		15,
		"十五人世界以十五个居民席位作为补位目标",
	)
	_expect(
		not RESIDENT_REPLACEMENT.replacement_needed(world),
		"居民完整时不需要补位",
	)
	var deceased := identities[0]
	var deceased_name := String(deceased.get("residentName", ""))
	var death := world.confirm_resident_death(
		String(deceased.get("residentId", "")),
		"测试确认的死亡原因",
	) as Dictionary
	_expect(bool(death.get("ok", false)), "居民死亡可以确认")
	var death_event_id := String(
		(death.get("event", {}) as Dictionary).get("event_id", "")
	)
	_expect(
		RESIDENT_REPLACEMENT.replacement_needed(world),
		"居民死亡后需要恢复本局目标人口",
	)
	_verify_async_recovery(opening, death.get("event", {}) as Dictionary)
	var record := ((opening.get("residents", []) as Array)[0] as Dictionary).duplicate(true)
	record["residentId"] = String(deceased.get("residentId", ""))
	var attributes := (record.get("attributes", {}) as Dictionary).duplicate(true)
	attributes["name"] = "补位测试居民"
	record["attributes"] = attributes
	var host := GAME_FLOW_HOST.new()
	host.set("_pending_replacement_candidate", {
		"record": record.duplicate(true),
		"identity": {
			"residentId": String(deceased.get("residentId", "")),
			"residentName": "补位测试居民",
		},
		"binding": {
			"residentId": String(deceased.get("residentId", "")),
			"residentName": "补位测试居民",
		},
	})
	var editor_attributes := attributes.duplicate(true)
	editor_attributes["selectionSummary"] = "UI 列表摘要"
	host.call("_merge_replacement_editor_source", {
		"attributes": editor_attributes,
		"occupation": {},
		"presentation": {},
	})
	var merged_record := (
		(host.get("_pending_replacement_candidate") as Dictionary)
		.get("record", {}) as Dictionary
	)
	_expect(
		not (merged_record.get("attributes", {}) as Dictionary).has(
			"selectionSummary",
		),
		"入镇编辑不会把 UI 专用摘要带入正式居民资料",
	)
	host.free()
	var invalid_record := record.duplicate(true)
	var invalid_attributes := (
		invalid_record.get("attributes", {}) as Dictionary
	).duplicate(true)
	invalid_attributes["selectionSummary"] = "UI 列表摘要"
	invalid_record["attributes"] = invalid_attributes
	var invalid_preview := RESIDENT_REPLACEMENT.preview_agent_initialization(
		world,
		invalid_record,
		String(deceased.get("residentId", "")),
	) as Dictionary
	_expect(bool(invalid_preview.get("ok", false)), "World 可以无副作用预览补位 Agent 资料")
	_expect(
		not AGENT_CONTRACT.validate_initialization(
			invalid_preview.get("initialization", {}),
		).is_empty(),
		"Agent 预检会拒绝泄漏的 UI 字段",
	)
	_expect_equal(RESIDENT_REPLACEMENT.living_resident_count(world), 14, "预检失败前 World 不会提前补位")
	var same_name_record := record.duplicate(true)
	var same_name_attributes := (
		same_name_record.get("attributes", {}) as Dictionary
	).duplicate(true)
	same_name_attributes["name"] = deceased_name
	same_name_record["attributes"] = same_name_attributes
	var same_name_validation := RESIDENT_REPLACEMENT.validate(
		world,
		same_name_record,
		String(deceased.get("residentId", "")),
	) as Dictionary
	_expect(
		bool(same_name_validation.get("ok", false)),
		"补位可以复用已经死亡居民的姓名",
	)
	var admitted := RESIDENT_REPLACEMENT.admit(
		world,
		record,
		String(deceased.get("residentId", "")),
	) as Dictionary
	_expect(bool(admitted.get("ok", false)), "补位居民可以进入运行中的世界")
	_expect_equal(RESIDENT_REPLACEMENT.living_resident_count(world), 15, "补位后恢复十五名在世居民")
	_expect(
		not RESIDENT_REPLACEMENT.replacement_needed(world),
		"补位完成后不会继续生成额外居民",
	)
	_expect_equal(world.get_resident_ids().size(), 15, "新居民接替原有住宅席位")
	_expect_equal(
		(world.get_resident_state(String(deceased.get("residentId", ""))) as Dictionary).get("name"),
		"补位测试居民",
		"同一住宅席位已换成新居民身份",
	)
	_expect_equal(world.get_public_death_events(), [], "完成补位后不再重复处理同一死亡事件")
	var historical_death_name := ""
	for event_value: Variant in world.get_public_event_log():
		if not event_value is Dictionary:
			continue
		var event := event_value as Dictionary
		if String(event.get("eventId", "")) == death_event_id:
			historical_death_name = String(event.get("residentName", ""))
			break
	_expect_equal(
		historical_death_name,
		deceased_name,
		"补位后的死亡历史仍保留死者姓名",
	)
	_expect(
		not world.get_agent_initialization_by_id(
			String(deceased.get("residentId", "")),
		).is_empty(),
		"新居民具备 Agent 初始化资料",
	)
	var save_result := world.create_save_snapshot() as Dictionary
	_expect(bool(save_result.get("ok", false)), "补位后的世界可以保存")
	var restored_opening := opening.duplicate(true)
	var restored_residents := (
		(restored_opening.get("residents", []) as Array).duplicate(true)
	)
	restored_residents[0] = record.duplicate(true)
	restored_opening["residents"] = restored_residents
	restored_opening["agentSoulProfiles"] = AGENT_SOUL_PROFILE.analyze_all(
		restored_residents,
	)
	var restored_identities := identities.duplicate(true)
	restored_identities[0] = {
		"residentId": String(deceased.get("residentId", "")),
		"residentName": "补位测试居民",
	}
	world.stop()
	var restored_world := WORLD.new()
	var restored := restored_world.restore_from_snapshot(
		data,
		restored_opening,
		(save_result.get("snapshot", {}) as Dictionary).duplicate(true),
		restored_identities,
	) as Dictionary
	_expect(
		bool(restored.get("ok", false)),
		"补位后的世界存档可以恢复：%s" % JSON.stringify(restored),
	)
	_expect_equal(RESIDENT_REPLACEMENT.living_resident_count(restored_world), 15, "读档后仍保持十五名在世居民")
	_expect_equal(
		(restored_world.get_resident_state(String(deceased.get("residentId", ""))) as Dictionary).get("name"),
		"补位测试居民",
		"读档后保留新居民身份",
	)
	restored_world.stop()
	_verify_low_population_target_and_restore(data, opening)
	_finish_suite("RESIDENT_REPLACEMENT_PASS")


func _verify_return_to_start_does_not_wait_for_messages() -> void:
	var gateway := ReturnToStartGateway.new()
	var host := ReturnToStartWiringHarness.new()
	var runtime := Node.new()
	var save_service := RefCounted.new()
	host.set("_gateway", gateway)
	host.set("_town_runtime", runtime)
	host.set("_session_ui_service", save_service)
	var result := host.request_return_to_start()
	_expect_equal(gateway.calls, 0, "返回主菜单不会临时请求居民留言")
	_expect_equal(gateway.cancel_calls, 1, "返回主菜单会取消后台留言任务")
	_expect_equal(host.saved_messages, gateway.messages, "返回主菜单会保存后台已准备的居民留言")
	_expect_equal(host.routed_departures.size(), 1, "留言保存后只返回一次主菜单")
	_expect_equal(host.process_quit_count, 0, "返回主菜单不会退出游戏进程")
	_expect(bool(result.get("ok", false)), "返回主菜单保存链路成功结束")
	host.free()
	runtime.free()
	gateway.free()

	var base_gateway := ReturnToStartGateway.new()
	var base_host := BaseDepartureHarness.new()
	var base_runtime := Node.new()
	var base_save_service := DepartureSaveService.new()
	base_host.set("_gateway", base_gateway)
	base_host.set("_town_runtime", base_runtime)
	base_host.set("_session_ui_service", base_save_service)
	var base_result := base_host.call("_prepare_session_departure") as Dictionary
	_expect(bool(base_result.get("ok", false)), "正式退出保存会成功结束")
	_expect_equal(
		base_save_service.request.get("residentMessages", []),
		base_gateway.messages,
		"正式退出保存会带上后台已准备的居民留言",
	)
	_expect_equal(base_gateway.clear_calls, 1, "保存成功后清理后台留言缓存")
	base_host.free()
	base_runtime.free()
	base_gateway.free()

	var empty_gateway := EmptyBackgroundDepartureGateway.new()
	var empty_host := ReturnToStartWiringHarness.new()
	var empty_runtime := Node.new()
	var empty_save_service := RefCounted.new()
	empty_host.set("_gateway", empty_gateway)
	empty_host.set("_town_runtime", empty_runtime)
	empty_host.set("_session_ui_service", empty_save_service)
	empty_host.request_return_to_start()
	_expect_equal(empty_host.saved_messages, [], "没有后台留言时保存空留言列表")
	empty_host.free()
	empty_runtime.free()
	empty_gateway.free()

func _verify_async_recovery(
	opening: Dictionary,
	death_event: Dictionary,
) -> void:
	var provider := NeverCompletingProvider.new()
	var provider_service := ReplacementProviderService.new(provider)
	var host := GameFlowRecoveryHarness.new()
	var resident_id := String(death_event.get("deceased_resident_id", ""))
	var binding := {
		"residentId": resident_id,
		"residentName": "待补位居民",
	}
	host.set("_provider_service", provider_service)
	host.set("_active_session_config", {
		"openingConfig": opening.duplicate(true),
		"residentBindings": [binding.duplicate(true)],
	})
	host.call(
		"_begin_replacement_persona_generation",
		death_event.duplicate(true),
	)
	_expect_equal(
		host.get("_replacement_generation_pending"),
		true,
		"补位资料请求未回调时保持等待状态",
	)
	var generation_id := int(host.get("_active_replacement_generation_id"))
	host.call(
		"_on_replacement_persona_timeout",
		generation_id,
		death_event.duplicate(true),
		binding.duplicate(true),
	)
	_expect_equal(
		host.get("_replacement_generation_pending"),
		false,
		"补位资料请求超时后解除等待状态",
	)
	_expect_equal(
		host.presented_replacements.size(),
		1,
		"补位资料请求超时后生成一份本地默认候选人",
	)
	_expect(
		not host.presented_replacements[0].is_empty(),
		"补位资料超时使用的本地候选人资料完整",
	)
	provider.complete({"ok": true, "json": {"name": "迟到居民"}})
	_expect_equal(
		host.presented_replacements.size(),
		1,
		"补位资料超时后的迟到回调不会重复弹出候选人",
	)

	host.free()


func _verify_low_population_target_and_restore(
	data: Dictionary,
	full_opening: Dictionary,
) -> void:
	var opening := _opening_with_resident_count(full_opening, 5)
	var identities := _identities_from_opening(opening)
	var world := WORLD.new()
	var started := world.start(data, opening, identities) as Dictionary
	_expect(
		bool(started.get("ok", false)),
		"五人世界可以启动：%s" % JSON.stringify(started.get("errors", [])),
	)
	_expect_equal(
		RESIDENT_REPLACEMENT.target_resident_count(world),
		5,
		"五人世界以五个居民席位作为补位目标",
	)
	_expect(
		not RESIDENT_REPLACEMENT.replacement_needed(world),
		"五人均在世时不会按十五人目标补位",
	)
	var deceased := identities[0]
	var resident_id := String(deceased.get("residentId", ""))
	var death := world.confirm_resident_death(
		resident_id,
		"少人口补位回归",
	) as Dictionary
	_expect(bool(death.get("ok", false)), "五人世界可以确认居民死亡")
	_expect_equal(
		RESIDENT_REPLACEMENT.living_resident_count(world),
		4,
		"五人世界死亡后剩余四名在世居民",
	)
	_expect_equal(
		RESIDENT_REPLACEMENT.target_resident_count(world),
		5,
		"死亡不会改变本局五人目标",
	)
	_expect(
		RESIDENT_REPLACEMENT.replacement_needed(world),
		"五人世界死亡后只需恢复原有席位",
	)
	var saved := world.create_save_snapshot() as Dictionary
	_expect(bool(saved.get("ok", false)), "五人世界死亡后可以保存")
	world.stop()

	var restored_world := WORLD.new()
	var restored := restored_world.restore_from_snapshot(
		data,
		opening,
		(saved.get("snapshot", {}) as Dictionary).duplicate(true),
		identities,
	) as Dictionary
	_expect(
		bool(restored.get("ok", false)),
		"五人世界死亡存档可以恢复：%s" % JSON.stringify(restored),
	)
	_expect_equal(
		RESIDENT_REPLACEMENT.target_resident_count(restored_world),
		5,
		"读档后仍从居民席位恢复五人目标",
	)
	_expect_equal(
		RESIDENT_REPLACEMENT.living_resident_count(restored_world),
		4,
		"读档后保留死亡状态而不虚增居民",
	)
	_expect(
		RESIDENT_REPLACEMENT.replacement_needed(restored_world),
		"读档后继续等待唯一缺失席位的补位",
	)
	var replacement_record := (
		(opening.get("residents", []) as Array)[0] as Dictionary
	).duplicate(true)
	var replacement_attributes := (
		replacement_record.get("attributes", {}) as Dictionary
	).duplicate(true)
	replacement_attributes["name"] = "五人镇补位居民"
	replacement_record["attributes"] = replacement_attributes
	var admitted := RESIDENT_REPLACEMENT.admit(
		restored_world,
		replacement_record,
		resident_id,
	) as Dictionary
	_expect(bool(admitted.get("ok", false)), "五人世界读档后可以完成补位")
	_expect_equal(
		RESIDENT_REPLACEMENT.living_resident_count(restored_world),
		5,
		"五人世界补位后只恢复到五名在世居民",
	)
	_expect_equal(
		RESIDENT_REPLACEMENT.target_resident_count(restored_world),
		5,
		"补位不会把五人世界扩张到十五人",
	)
	_expect(
		not RESIDENT_REPLACEMENT.replacement_needed(restored_world),
		"恢复五人目标后补位流程停止",
	)
	restored_world.stop()


func _opening_with_resident_count(
	opening: Dictionary,
	resident_count: int,
) -> Dictionary:
	var result := opening.duplicate(true)
	var residents := (result.get("residents", []) as Array).slice(
		0,
		resident_count,
		1,
		true,
	)
	var resident_ids: Dictionary = {}
	for resident_value: Variant in residents:
		resident_ids[String((resident_value as Dictionary).get("residentId", ""))] = true
	var owners: Dictionary = {}
	for place_value: Variant in (result.get("ownerAssignments", {}) as Dictionary):
		var place_name := String(place_value)
		var owner_id := String(
			(result.get("ownerAssignments", {}) as Dictionary).get(place_name, ""),
		)
		if resident_ids.has(owner_id):
			owners[place_name] = owner_id
	result["residents"] = residents
	result["ownerAssignments"] = owners
	result["agentSoulProfiles"] = AGENT_SOUL_PROFILE.analyze_all(residents)
	return result


func _identities_from_opening(opening: Dictionary) -> Array[Dictionary]:
	var identities: Array[Dictionary] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		identities.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(
				(resident.get("attributes", {}) as Dictionary).get("name", ""),
			),
		})
	return identities
