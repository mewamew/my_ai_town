extends "res://tests/support/TownWorldTestCase.gd"
const OCCUPATION_RESIDENT_CONTEXT_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationResidentContextRuntime.gd"
)
const PRIVATE_MESSAGE_DELIVERY_RUNTIME := preload(
	"res://world/runtime/social/TownPrivateMessageDeliveryRuntime.gd"
)
const PERFORMANCE_SERVICE_RUNTIME := preload(
	"res://world/runtime/work/TownPerformanceServiceRuntime.gd"
)
## 职业与用工 合并套件。
##
## 由以下测试合并而来，断言逐条保留：
## - town_occupation_service_work_chain_integration_test.gd
## - town_occupation_downstream_closure_integration_test.gd
## - town_staffing_negotiation_integration_test.gd
## - town_occupation_natural_source_test.gd
## - town_world_market_workplace_test.gd
## - town_staffing_runtime_test.gd
## - town_staffing_arrangement_runtime_test.gd

const CRAFT_ID := "resident_lin_lan_01"
const PATIENT_ID := "resident_tang_xiaoman_01"
const CAFE_ID := "resident_a_he_01"
const DOCTOR_ID := "resident_gu_chuan_01"
const LIBRARIAN_ID := "resident_su_he_01"
const BORROWER_ID := "resident_zhao_tang_01"
const BUYER_ID := "resident_chen_zhou_01"
const DINING_CUSTOMER_ID := "resident_shen_yao_01"
const COOK_ID := "resident_lu_qing_01"
const GROCER_ID := "resident_he_yu_01"
const FLOWER_ID := "resident_zhou_ning_01"
const CAFE_CUSTOMER_ID := "resident_bai_yu_01"
const MUSICIAN_ID := "resident_xu_an_01"
const AUDIENCE_ID := "resident_ye_cheng_01"
const WAREHOUSE_ID := "resident_chen_zhou_01"
const CRAFTSPERSON_ID := "resident_lin_lan_01"
const DELIVERY_ID := "resident_jiang_lin_01"
const DINING_WORKER_ID := "resident_shen_yao_01"
const DINING_VISITOR_ID := "resident_lu_qing_01"
const DINING_PEAK_RESIDENT_IDS := [
	"resident_lin_lan_01",
	"resident_tang_xiaoman_01",
	"resident_a_he_01",
	"resident_gu_chuan_01",
	"resident_su_he_01",
	"resident_zhao_tang_01",
	"resident_chen_zhou_01",
	"resident_shen_yao_01",
	"resident_lu_qing_01",
	"resident_he_yu_01",
	"resident_zhou_ning_01",
	"resident_bai_yu_01",
	"resident_jiang_lin_01",
	"resident_xu_an_01",
	"resident_ye_cheng_01",
]
const CAFE_WORKER_ID := "resident_a_he_01"
const CAFE_VISITOR_ID := "resident_tang_xiaoman_01"
const FLOWER_VENDOR_ID := "resident_he_yu_01"
const FORMAL_OPENING := preload(
	"res://tests/support/TownWorldFormalOpeningTestHelper.gd"
)
const STAFFING := preload(
	"res://world/runtime/work/TownStaffingRuntime.gd"
)

var _activity_sequence := 0
var _plan_sequence := 0
var _started_activity_ids: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_scenario_occupation_service_work_chain_integration()
	_scenario_dining_peak_regression()
	_scenario_occupation_downstream_closure_integration()
	_scenario_staffing_negotiation_integration()
	_scenario_occupation_natural_source()
	_scenario_market_workplace()
	_scenario_staffing_runtime()
	_scenario_staffing_arrangement_runtime()
	_finish_suite("TOWN_OCCUPATION_PASS")


func _scenario_occupation_service_work_chain_integration() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(
		OPENING_PATH,
		data,
	) as Dictionary
	_expect_equal(
		opening_result.get("ok"),
		true,
		"职业服务链可加载开局",
	)
	if opening_result.get("ok") != true:
		return
	var opening := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	_prepare_residents(opening)
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(
		started.get("ok"),
		true,
		"职业服务链 World 可启动（%s）" % [started],
	)
	if started.get("ok") != true:
		return
	_test_craft_production(world)
	_test_clinic(world)
	_test_research_sample(world)
	_test_library(world)
	_test_civic_bulletin(world)
	_test_warehouse_audit(world)
	_test_dining_and_cafe(world)
	_test_market_sales(world)
	_test_repair_waits_for_material(world)
	_test_equipment_wear_creates_repair(world)
	_test_performance_requires_audience(world)
	_test_library_assist_and_catalog(world)
	_test_resident_civic_request(world)
	_test_library_due_request_is_natural(world)
	_test_clinic_follow_up_is_natural(world)
	_expect_periodic_task_backlog_bounded(world)
	var prepared := world.call("prepare_save_candidate") as Dictionary
	_expect_equal(
		prepared.get("ok"),
		true,
		"职业服务记录可以保存（%s）" % [prepared],
	)
	var restored: RefCounted = WORLD.new()
	var restore_result := restored.call(
		"restore_from_snapshot",
		data,
		opening,
		prepared.get("snapshot", {}) as Dictionary,
	) as Dictionary
	_expect_equal(
		restore_result.get("ok"),
		true,
		"职业服务记录可以恢复（%s）" % [restore_result],
	)
	if restore_result.get("ok") == true:
		var restored_services := restored.call(
			"get_occupation_service_snapshot",
		) as Dictionary
		_expect(
			(restored_services.get("requests", []) as Array).size()
			>= 8,
			"恢复后保留诊疗、借还、消费、销售、维修和演出记录",
		)
	world.call("stop")
	restored.call("stop")
	return
func _test_craft_production(world: RefCounted) -> void:
	for activity_id: String in [
		"activity_workshop_take_lumber",
		"activity_workshop_grind_parts",
		"activity_workshop_assemble_item",
	]:
		_expect(
			_perform_and_finish(world, CRAFT_ID, activity_id, "工作坊"),
			"工匠制作链完成工序：%s" % activity_id,
		)
	var task := _saved_work_task(world, "craft-production:0")
	_expect_equal(task.get("state"), "completed", "工匠三段制作形成正式结果")
	var crafted_lot_found := false
	for lot_value: Variant in (
		world.call("get_cargo_inventory_snapshot") as Dictionary
	).get("cargoLots", []) as Array:
		var lot := lot_value as Dictionary
		if (
			String(lot.get("itemId", "")) == "crafted_item"
			and String(lot.get("sourcePlaceId", "")) == "工作坊"
			and String(lot.get("destinationPlaceId", "")) == "码头仓库"
		):
			crafted_lot_found = true
			break
	_expect(crafted_lot_found, "工匠成品进入真实货运链")



func _test_clinic_follow_up_is_natural(world: RefCounted) -> void:
	var found := false
	var follow_up_id := ""
	for request_value: Variant in (
		world.call("get_occupation_service_snapshot") as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == "clinic"
			and bool((request.get("context", {}) as Dictionary).get(
				"generatedFromFollowUp",
				false,
			))
		):
			found = true
			follow_up_id = String(
				(request.get("context", {}) as Dictionary).get(
					"followUpId",
					"",
				)
			)
			break
	_expect(found, "配药后的次日复诊会自然形成真实看诊请求")
	var follow_up_message_found := false
	for message_value: Variant in (
		world.call(
			"get_private_messages_for_resident",
			PATIENT_ID,
		) as Array
	):
		var message := message_value as Dictionary
		if (
			String(message.get("source_ref", ""))
			== "clinic-follow-up:%s" % follow_up_id
			and String(message.get("recipient_resident_id", "")) == PATIENT_ID
			and String(message.get("content", "")).begins_with("复诊时间到了")
			and OCCUPATION_RESIDENT_CONTEXT_RUNTIME.can_work_occupation(
				world,
				String(message.get("sender_resident_id", "")),
				"occupation_clinic_practitioner",
			)
		):
			follow_up_message_found = true
			break
	# 这条检查运行时可能已经跨过口信的六小时时效；即使口信已取消，
	# 创建记录仍应保留原发送人、收件人和正文，证明自然链确实产生过口信。
	if not follow_up_message_found:
		follow_up_message_found = _has_message_creation_log(
			world,
			"clinic-follow-up:%s" % follow_up_id,
			PATIENT_ID,
			"复诊时间到了",
			"occupation_clinic_practitioner",
		)
	_expect(
		follow_up_message_found,
		"复诊请求同时形成医师发给患者的具体口信",
	)



func _test_library_assist_and_catalog(world: RefCounted) -> void:
	_expect(_move_to_place(world, BUYER_ID, "图书馆"), "居民前往图书馆查资料")
	var created := world.call(
		"create_occupation_service_request",
		{
			"kind": "library_assist",
			"requesterResidentId": BUYER_ID,
			"subjectRef": "查找小镇旧码头资料",
		},
	) as Dictionary
	_expect_equal(created.get("ok"), true, "居民查资料会形成馆员协助任务")
	_expect(
		_perform_and_finish(
			world,
			LIBRARIAN_ID,
			"activity_library_staff_checkout",
			"图书馆",
		),
		"馆员完成真实资料查找协助",
	)
	var request := world.call(
		"get_occupation_service_request",
		String((created.get("request", {}) as Dictionary).get("requestId", "")),
	) as Dictionary
	_expect_equal(request.get("state"), "completed", "资料协助请求闭环")
	if _has_work_task(
		world,
		LIBRARIAN_ID,
		"library.assist",
		"daily_catalog_plan",
	):
		_expect(
			_perform_and_finish(
				world,
				LIBRARIAN_ID,
				"activity_library_staff_checkout",
				"图书馆",
			),
			"馆员完成每日目录核对",
		)



func _test_resident_civic_request(world: RefCounted) -> void:
	_expect(_move_to_place(world, BUYER_ID, "镇公所"), "居民前往镇公所办事")
	var messages_before := (
		world.call("get_private_messages_for_resident", BUYER_ID) as Array
	).size()
	var created := world.call(
		"create_occupation_service_request",
		{
			"kind": "civic_request",
			"requesterResidentId": BUYER_ID,
			"subjectRef": "申请修整住宅门前道路",
		},
	) as Dictionary
	_expect_equal(created.get("ok"), true, "居民镇务形成管理者任务：%s" % [created])
	_expect(
		_perform_and_finish(
			world,
			BORROWER_ID,
			"activity_town_hall_manage_records",
			"镇公所",
		),
		"小镇管理者处理居民镇务",
	)
	var request := world.call(
		"get_occupation_service_request",
		String((created.get("request", {}) as Dictionary).get("requestId", "")),
	) as Dictionary
	_expect_equal(request.get("state"), "completed", "居民镇务处理闭环")
	_expect(
		(world.call("get_private_messages_for_resident", BUYER_ID) as Array).size()
		> messages_before,
		"镇务办结回执自然形成邮差消息需求",
	)



func _test_clinic(world: RefCounted) -> void:
	# 看诊请求必须引用真实身体状况，且接诊前要先完成问诊对话。
	# 向状况模块注入一条确定的头痛记录，避免依赖随机掷点。
	var conditions_module := world.get("_resident_conditions") as RefCounted
	var condition_residents := conditions_module.get("_residents") as Dictionary
	var patient_condition_entry := condition_residents.get(
		PATIENT_ID,
		{},
	) as Dictionary
	(patient_condition_entry.get("conditions", []) as Array).append({
		"conditionId": "condition-%s-900001" % PATIENT_ID,
		"kind": "headache",
		"label": "头痛得难以集中精神",
		"severity": "noticeable",
		"sourceKind": "formal_activity",
		"sourceRef": "integration-clinic-probe",
		"startedAtMinute": 0,
		"lastChangedAtMinute": 0,
		"state": "active",
		"nextChangeAtMinute": 999999,
	})
	for participant_id in [PATIENT_ID, DOCTOR_ID]:
		var participant_place := String(
			(
				world.call("get_resident_state", participant_id) as Dictionary
			).get("currentPlace", ""),
		)
		if participant_place != "诊所":
			_expect(
				_move_to_place(world, participant_id, "诊所"),
				"%s 能走到诊所" % participant_id,
			)
	var created := world.call(
		"create_occupation_service_request",
		{
			"kind": "clinic",
			"requesterResidentId": PATIENT_ID,
		},
	) as Dictionary
	_expect_equal(created.get("ok"), true, "病人形成真实看诊请求")
	var request_id := String(
		(created.get("request", {}) as Dictionary).get(
			"requestId",
			"",
		),
	)
	_expect(
		_submit_decision_action(world, DOCTOR_ID, {
			"type": "搭话",
			"target_resident_id": PATIENT_ID,
			"say": "你现在最明显的不舒服是什么？",
			"narration": "医师在问诊桌旁看向病人",
			"photos": [],
		}),
		"医师开始真实问诊对话",
	)
	for _step in 5:
		world.call("advance", 0.5)
	var conversation_id := ""
	for _minute in 300:
		var conversations := world.call("get_active_conversations") as Array
		if not conversations.is_empty():
			conversation_id = String(
				(conversations[0] as Dictionary).get("conversationId", ""),
			)
			break
		world.call("advance", 1.0)
	_expect(not conversation_id.is_empty(), "问诊进入真实对话")
	_expect(
		_submit_decision_action(world, PATIENT_ID, {
			"type": "答话",
			"conversation_id": conversation_id,
			"say": "头痛得没法集中精神，想请你看看。",
			"narration": "病人说完后停下来接受检查",
			"photos": [],
			"end": true,
			"medical_response": {
				"request_id": request_id,
				"response_kind": "describe",
			},
		}),
		"病人如实描述身体状况",
	)
	for _step in 5:
		world.call("advance", 0.5)
	_expect(
		_perform_and_finish(
			world,
			DOCTOR_ID,
			"activity_clinic_receive_patient",
			"诊所",
		),
		"医师完成接诊和身体观察",
	)
	var after_consult := world.call(
		"get_occupation_service_request",
		request_id,
	) as Dictionary
	_expect_equal(
		after_consult.get("state"),
		"pending",
		"需要药品时接诊不会直接宣称治好",
	)
	_expect_equal(
		(
			after_consult.get("outcome", {}) as Dictionary
		).get("medicineNeeded"),
		true,
		"接诊结果明确进入配药环节",
	)
	var before_stock := _inventory(
		world.call("get_cargo_inventory_snapshot") as Dictionary,
		"诊所",
		"basic_medicine",
	)
	_expect(
		_perform_and_finish(
			world,
			DOCTOR_ID,
			"activity_clinic_prepare_medicine",
			"诊所",
		),
		"医师完成真实配药",
	)
	var after_treatment := world.call(
		"get_occupation_service_request",
		request_id,
	) as Dictionary
	_expect_equal(
		after_treatment.get("state"),
		"completed",
		"配药结果成立后看诊请求才完成",
	)
	_expect_equal(
		_inventory(
			world.call(
				"get_cargo_inventory_snapshot",
			) as Dictionary,
			"诊所",
			"basic_medicine",
		),
		before_stock,
		"基础药品不维护会耗尽的库存",
	)
	_expect_equal(
		(after_treatment.get("outcome", {}) as Dictionary).get("supplyMode"),
		"base_always_available",
		"配药仍有真实过程，但基础供给始终可用",
	)
	_expect_equal(
		(
			after_treatment.get("outcome", {}) as Dictionary
		).get("status"),
		"treated_follow_up_needed",
		"医疗结果不夸大成已经痊愈",
	)



func _test_library(world: RefCounted) -> void:
	var borrowed := world.call(
		"create_occupation_service_request",
		{
			"kind": "library_loan",
			"requesterResidentId": BORROWER_ID,
			"itemId": "book_plant_reference",
		},
	) as Dictionary
	_expect_equal(borrowed.get("ok"), true, "读者形成真实借书请求")
	var borrow_request_id := String(
		(borrowed.get("request", {}) as Dictionary).get(
			"requestId",
			"",
		),
	)
	_expect(
		_perform_and_finish(
			world,
			LIBRARIAN_ID,
			"activity_library_staff_checkout",
			"图书馆",
		),
		"图书管理员办理借书",
	)
	var borrow_record := world.call(
		"get_occupation_service_request",
		borrow_request_id,
	) as Dictionary
	_expect_equal(
		borrow_record.get("state"),
		"completed",
		"借书后形成真实借阅记录",
	)
	var loan_id := String(
		(
			borrow_record.get("outcome", {}) as Dictionary
		).get("loanId", ""),
	)
	_expect(not loan_id.is_empty(), "借阅记录有稳定编号")
	var returned := world.call(
		"create_occupation_service_request",
		{
			"kind": "library_return",
			"requesterResidentId": BORROWER_ID,
			"subjectRef": loan_id,
		},
	) as Dictionary
	_expect_equal(returned.get("ok"), true, "读者能归还实际借出的书")
	var return_request_id := String(
		(returned.get("request", {}) as Dictionary).get(
			"requestId",
			"",
		),
	)
	_expect(
		_perform_and_finish(
			world,
			LIBRARIAN_ID,
			"activity_library_shelve_returns",
			"图书馆",
		),
		"图书管理员接收归还书籍",
	)
	var return_record := world.call(
		"get_occupation_service_request",
		return_request_id,
	) as Dictionary
	_expect_equal(
		return_record.get("state"),
		"completed",
		"归还后恢复馆藏状态",
	)
	_expect_equal(
		(
			(
				world.call(
					"get_occupation_service_snapshot",
				) as Dictionary
			).get("bookAvailableCopies", {}) as Dictionary
		).get("book_plant_reference"),
		1,
		"归还后可借副本数量恢复",
	)



func _test_research_sample(world: RefCounted) -> void:
	world.call("set_weather", "晴天")
	world.call("queue_weather_roll", 0.0)
	_expect(
		_perform_and_finish(
			world,
			PATIENT_ID,
			"activity_garden_harvest_region",
			"社区花园",
		),
		"园艺师按真实研究项目采集植物样本",
	)
	var sample_found := false
	for lot_value: Variant in (
		world.call("get_cargo_inventory_snapshot") as Dictionary
	).get("cargoLots", []) as Array:
		var lot := lot_value as Dictionary
		if (
			String(lot.get("itemId", "")) == "plant_sample"
			and String(lot.get("sourcePlaceId", "")) == "社区花园"
			and String(lot.get("destinationPlaceId", "")) == "图书馆"
		):
			sample_found = true
			break
	_expect(sample_found, "研究取样形成带来源和去向的真实样本货批")



func _test_civic_bulletin(world: RefCounted) -> void:
	var announcement_count_before := (
		world.call("get_announcements") as Array
	).size()
	_expect(
		_perform_and_finish(
			world,
			BORROWER_ID,
			"activity_town_hall_manage_records",
			"镇公所",
		),
		"小镇管理者完成当天镇务事实核对",
	)
	_expect(
		_has_work_task(
			world,
			BORROWER_ID,
			"bulletin.publish",
			"public_matter",
		),
		"镇务核对结果形成待发布公告",
	)
	_expect(
		_perform_and_finish(
			world,
			BORROWER_ID,
			"activity_bulletin_publish",
			"中心广场",
		),
		"小镇管理者把镇务结果发布到公告系统",
	)
	_expect(
		(world.call("get_announcements") as Array).size()
		> announcement_count_before,
		"镇务公告形成可读取的正式公告记录",
	)



func _test_warehouse_audit(world: RefCounted) -> void:
	_expect(
		_perform_and_finish(
			world,
			BUYER_ID,
			"activity_warehouse_check_manifest",
			"码头仓库",
		),
		"仓库管理员完成当天货单盘点",
	)
	var audit := _saved_work_task(world, "warehouse-daily-audit:0")
	_expect_equal(audit.get("state"), "completed", "日常盘点形成库存记录")
	_expect_equal(
		(audit.get("result", {}) as Dictionary).get("kind"),
		"inventory_record",
		"仓库盘点结果不是只有动作表现",
	)


func _scenario_dining_peak_regression() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var collect_position := _dining_activity_position_key(
		data,
		"activity_dining_collect_meal",
	)
	var serve_position := _dining_activity_position_key(
		data,
		"activity_dining_serve_meal",
	)
	var dough_position := _dining_activity_position_key(
		data,
		"activity_baker_prepare_dough",
	)
	_expect(not collect_position.is_empty(), "公共食堂取餐位置存在")
	_expect(
		serve_position != collect_position,
		"工作人员递餐位置不会与顾客取餐位置互相占用",
	)
	_expect(
		dough_position != collect_position,
		"准备面团位置不会与顾客取餐位置互相占用",
	)
	_expect(
		dough_position != serve_position,
		"准备面团位置不会与工作人员递餐位置互相占用",
	)
	_expect(
		_service_place_positions_are_independent(data),
		"全镇服务地点的顾客请求位置都不会占住工作人员服务位置",
	)
	var batch_world := _start_dining_peak_world(data)
	if batch_world == null:
		return
	_expect(
		_advance_to_minute_of_day(batch_world, 1020),
		"四人供餐场景会推进到晚餐供餐开始",
	)
	_expect(
		_perform_and_finish(
			batch_world,
			COOK_ID,
			"activity_dining_prepare_meal",
			"公共食堂",
		),
		"食堂完成晚餐备餐",
	)
	var customer_ids := _dining_customer_ids()
	var batch_request_ids := _create_dining_orders(
		batch_world,
		customer_ids.slice(0, 8),
	)
	_expect_equal(batch_request_ids.size(), 8, "晚餐高峰形成八份有效订单")
	_expect(
		_perform_and_finish(
			batch_world,
			COOK_ID,
			"activity_dining_serve_meal",
			"公共食堂",
		),
		"食堂完成第一批五分钟递餐",
	)
	_expect_equal(
		_count_completed_requests(batch_world, batch_request_ids),
		4,
		"第一批递餐同时完成四份订单",
	)
	_expect(
		_perform_and_finish(
			batch_world,
			COOK_ID,
			"activity_dining_serve_meal",
			"公共食堂",
		),
		"食堂完成第二批五分钟递餐",
	)
	_expect_equal(
		_count_completed_requests(batch_world, batch_request_ids),
		8,
		"第二批递餐后八份订单全部完成",
	)
	var completion_batches := _dining_completion_batches(
		batch_world,
		batch_request_ids,
	)
	_expect_equal(completion_batches.size(), 2, "八份订单分成两个完成批次")
	for batch_count: int in completion_batches.values():
		_expect_equal(batch_count, 4, "每个递餐批次同时完成四份订单")
	for request_id: String in batch_request_ids:
		var request := batch_world.call(
			"get_occupation_service_request",
			request_id,
		) as Dictionary
		if String(request.get("state", "")) != "completed":
			continue
		_expect_equal(
			(request.get("outcome", {}) as Dictionary).get("batchCapacity"),
			4,
			"四人批次的完成记录保留接待容量",
		)
	batch_world.call("stop")

	var closing_world := _start_dining_peak_world(data)
	if closing_world == null:
		return
	_expect(
		_advance_to_minute_of_day(closing_world, 1020),
		"关餐兜底场景会推进到晚餐供餐开始",
	)
	var all_request_ids := _create_dining_orders(
		closing_world,
		_dining_customer_ids(),
	)
	_expect_equal(
		all_request_ids.size(),
		_dining_customer_ids().size(),
		"除留在食堂工作的主理人外，全镇居民都能形成晚餐订单",
	)
	_expect(
		_advance_to_minute_of_day(closing_world, 1200),
		"未及时堂食时会推进到晚餐关餐",
	)
	for request_id: String in all_request_ids:
		var request := closing_world.call(
			"get_occupation_service_request",
			request_id,
		) as Dictionary
		_expect_equal(request.get("state"), "completed", "每份晚餐订单都有餐食")
		_expect_equal(
			(request.get("outcome", {}) as Dictionary).get("serviceMode"),
			"closing_takeaway",
			"等不及柜台服务的居民会领取打包餐",
		)
		var task := (
			(closing_world.get("work_domain") as TownWorkDomainRuntime).tasks as RefCounted
		).call("task", String(request.get("taskId", ""))) as Dictionary
		_expect(
			task.is_empty()
			or String(task.get("state", "")) in [
				"completed", "failed", "cancelled",
			],
			"打包餐不会留下仍在排队的递餐任务",
		)
	_expect(
		_advance_to_minute_of_day(closing_world, 1210),
		"关餐后十分钟内所有人会走出食堂",
	)
	_expect_equal(
		_count_residents_at_dining(closing_world, _dining_resident_ids()),
		0,
		"晚上八点十分，等待、工作或聊天的居民都不再滞留食堂",
	)
	_expect(
		_advance_to_minute_of_day(closing_world, 1330),
		"关餐兜底场景会继续推进到晚上十点十分",
	)
	_expect_equal(
		_count_residents_at_dining(closing_world, _dining_resident_ids()),
		0,
		"晚上十点十分食堂仍然没有排队和用餐人群",
	)
	closing_world.call("stop")


func _start_dining_peak_world(data: Dictionary) -> RefCounted:
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "晚餐高峰开局可加载")
	if opening_result.get("ok") != true:
		return null
	var opening := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	(opening.get("environment", {}) as Dictionary)["clock"] = "17:00"
	_prepare_residents(opening)
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		var resident_id := String(resident.get("residentId", ""))
		var world_state := resident.get("worldState", {}) as Dictionary
		world_state["place"] = "公共食堂"
		world_state["spaceId"] = "indoor_dining_hall"
		world_state["regionId"] = "region_portal_dining_hall_entry"
		world_state["position"] = [368, 384]
		if resident_id == COOK_ID:
			var social_state := resident.get("socialState", {}) as Dictionary
			social_state["job"] = "食堂主理人"
			social_state["workplace"] = "公共食堂"
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "晚餐高峰世界可启动")
	return world if started.get("ok") == true else null


func _dining_resident_ids() -> Array[String]:
	var result: Array[String] = []
	for resident_id: String in DINING_PEAK_RESIDENT_IDS:
		result.append(resident_id)
	return result


func _dining_activity_position_key(
	data: Dictionary,
	activity_id: String,
) -> String:
	for slot_value: Variant in data.get("activitySlots", []) as Array:
		var slot := slot_value as Dictionary
		if String(slot.get("activityId", "")) != activity_id:
			continue
		var anchors := slot.get("memberAnchors", []) as Array
		if anchors.is_empty():
			return ""
		var position := (anchors[0] as Dictionary).get("position", []) as Array
		if position.size() != 2:
			return ""
		return "%d,%d" % [roundi(float(position[0])), roundi(float(position[1]))]
	return ""


func _service_place_positions_are_independent(data: Dictionary) -> bool:
	for place_value: Variant in data.get("places", []) as Array:
		var place := place_value as Dictionary
		var profile := place.get("serviceProfile", {}) as Dictionary
		if profile.is_empty():
			continue
		var helper_positions := _activity_position_keys(
			data,
			String(profile.get("helperActivityId", "")),
		)
		for request_activity_id: String in profile.get(
			"requestActivityIds",
			[],
		) as Array:
			for position_key: String in _activity_position_keys(
				data,
				request_activity_id,
			):
				if helper_positions.has(position_key):
					return false
	return true


func _activity_position_keys(
	data: Dictionary,
	activity_id: String,
) -> Array[String]:
	var result: Array[String] = []
	for slot_value: Variant in data.get("activitySlots", []) as Array:
		var slot := slot_value as Dictionary
		if String(slot.get("activityId", "")) != activity_id:
			continue
		for anchor_value: Variant in slot.get("memberAnchors", []) as Array:
			var position := (
				(anchor_value as Dictionary).get("position", []) as Array
			)
			if position.size() == 2:
				result.append("%d,%d" % [
					roundi(float(position[0])),
					roundi(float(position[1])),
				])
	return result


func _dining_customer_ids() -> Array[String]:
	var result := _dining_resident_ids()
	result.erase(COOK_ID)
	return result


func _create_dining_orders(
	world: RefCounted,
	resident_ids: Array[String],
) -> Array[String]:
	var result: Array[String] = []
	for resident_id: String in resident_ids:
		var created := world.call(
			"create_occupation_service_request",
			{
				"kind": "dining_order",
				"requesterResidentId": resident_id,
			},
		) as Dictionary
		_expect_equal(created.get("ok"), true, "%s 可以点到晚餐" % resident_id)
		if created.get("ok") == true:
			result.append(String(
				(created.get("request", {}) as Dictionary).get("requestId", ""),
			))
	return result


func _advance_to_minute_of_day(world: RefCounted, target: int) -> bool:
	for _minute in 1441:
		var now := int(
			(world.get("_environment") as RefCounted).call(
				"get_absolute_minute",
			)
		)
		if posmod(now, 1440) == target:
			return true
		world.call("advance", 1.0)
	return false


func _count_completed_requests(
	world: RefCounted,
	request_ids: Array[String],
) -> int:
	var count := 0
	for request_id: String in request_ids:
		var request := world.call(
			"get_occupation_service_request",
			request_id,
		) as Dictionary
		count += 1 if String(request.get("state", "")) == "completed" else 0
	return count


func _dining_completion_batches(
	world: RefCounted,
	request_ids: Array[String],
) -> Dictionary:
	var result := {}
	for request_id: String in request_ids:
		var request := world.call(
			"get_occupation_service_request",
			request_id,
		) as Dictionary
		if String(request.get("state", "")) != "completed":
			continue
		var completed_at := int(request.get("completedAtMinute", -1))
		result[completed_at] = int(result.get(completed_at, 0)) + 1
	return result


func _count_residents_at_dining(
	world: RefCounted,
	resident_ids: Array[String],
) -> int:
	var count := 0
	for resident_id: String in resident_ids:
		var state := world.call("get_resident_state", resident_id) as Dictionary
		count += 1 if String(state.get("currentPlace", "")) == "公共食堂" else 0
	return count



func _test_dining_and_cafe(world: RefCounted) -> void:
	_expect(
		_advance_to_meal_preparation_window(world),
		"食堂顾客在当前餐次的备餐时段到店",
	)
	var dining_customer_state := world.call(
		"get_resident_state",
		DINING_CUSTOMER_ID,
	) as Dictionary
	_expect(
		String(dining_customer_state.get("currentPlace", "")) == "公共食堂"
		or _move_to_place(world, DINING_CUSTOMER_ID, "公共食堂"),
		"食堂顾客会先到店再点餐",
	)
	var meal_before := _inventory(
		world.call("get_cargo_inventory_snapshot") as Dictionary,
		"公共食堂",
		"meal",
	)
	var meal_order := world.call(
		"create_occupation_service_request",
		{
			"kind": "dining_order",
			"requesterResidentId": DINING_CUSTOMER_ID,
		},
	) as Dictionary
	_expect_equal(meal_order.get("ok"), true, "顾客形成真实取餐请求")
	var meal_request_id := String(
		(meal_order.get("request", {}) as Dictionary).get(
			"requestId",
			"",
		),
	)
	_expect_equal(
		(
			world.call(
				"get_occupation_service_request",
				meal_request_id,
			) as Dictionary
		).get("state"),
		"waiting",
		"尚未备餐时取餐请求先等待",
	)
	_expect(
		_advance_until_work_task(
			world,
			COOK_ID,
			"food.production",
			"meal_demand",
			1440,
		),
		"等到下一次真实备餐时段后，食堂出现备餐任务",
	)
	_expect(
		_perform_and_finish(
			world,
			COOK_ID,
			"activity_dining_prepare_meal",
			"公共食堂",
		),
		"食堂先完成当前餐次备餐",
	)
	_expect(
		_advance_until_service_state(
			world,
			meal_request_id,
			"pending",
			180,
		),
		"备餐完成后会等到正式供餐时间再恢复订单",
	)
	var resumed_meal_request := world.call(
		"get_occupation_service_request",
		meal_request_id,
	) as Dictionary
	_expect_equal(
		resumed_meal_request.get("state"),
		"pending",
		"备餐完成后等待中的取餐请求恢复（%s）" % resumed_meal_request,
	)
	_expect(
		_perform_and_finish(
			world,
			COOK_ID,
			"activity_dining_serve_meal",
			"公共食堂",
		),
		"食堂把备好的实际餐食交给顾客",
	)
	var meal_request := world.call(
		"get_occupation_service_request",
		meal_request_id,
	) as Dictionary
	_expect_equal(meal_request.get("state"), "completed", "取餐请求完成")
	_expect_equal(
		_inventory(
			world.call(
				"get_cargo_inventory_snapshot",
			) as Dictionary,
			"公共食堂",
			"meal",
		),
		meal_before,
		"基础餐食完成实际制作和交付，但不维护有限成品库存",
	)
	_expect_equal(
		(meal_request.get("outcome", {}) as Dictionary).get("supplyMode"),
		"base_always_available",
		"基础供餐使用无限基础供给",
	)
	var repeated_meal_order := world.call(
		"create_occupation_service_request",
		{
			"kind": "dining_order",
			"requesterResidentId": DINING_CUSTOMER_ID,
		},
	) as Dictionary
	_expect_equal(
		repeated_meal_order.get("ok"),
		false,
		"同一居民在本餐次内再次创建取餐请求会被拒绝",
	)
	_expect_equal(
		repeated_meal_order.get("errorCode"),
		"DINING_MEAL_ALREADY_SERVED",
		"重复取餐的错误码是 DINING_MEAL_ALREADY_SERVED",
	)
	var coffee_before := _inventory(
		world.call("get_cargo_inventory_snapshot") as Dictionary,
		"花房咖啡馆",
		"brewed_coffee",
	)
	var cafe_order := world.call(
		"create_occupation_service_request",
		{
			"kind": "cafe_order",
			"requesterResidentId": CAFE_CUSTOMER_ID,
			"itemId": "brewed_coffee",
		},
	) as Dictionary
	_expect_equal(cafe_order.get("ok"), true, "咖啡馆顾客形成真实点单")
	_expect(
		_perform_and_finish(
			world,
			CAFE_ID,
			"activity_cafe_brew_coffee",
			"花房咖啡馆",
		),
		"咖啡店员根据真实订单完成冲煮",
	)
	var cafe_request_id := String(
		(cafe_order.get("request", {}) as Dictionary).get(
			"requestId",
			"",
		),
	)
	_expect_equal(
		(
			world.call(
				"get_occupation_service_request",
				cafe_request_id,
			) as Dictionary
		).get("state"),
		"pending",
		"冲煮后仍需在柜台交付，订单不能提前结束",
	)
	_expect(
		_perform_and_finish(
			world,
			CAFE_ID,
			"activity_cafe_receive_guests",
			"花房咖啡馆",
		),
		"咖啡店员把已冲好的基础饮品交给顾客",
	)
	var cafe_request := world.call(
		"get_occupation_service_request",
		cafe_request_id,
	) as Dictionary
	_expect_equal(cafe_request.get("state"), "completed", "基础饮品订单完成")
	_expect_equal(
		_inventory(
			world.call(
				"get_cargo_inventory_snapshot",
			) as Dictionary,
			"花房咖啡馆",
			"brewed_coffee",
		),
		coffee_before,
		"基础饮品不维护有限成品库存",
	)



func _test_market_sales(world: RefCounted) -> void:
	_expect(
		_move_to_place(world, BUYER_ID, "独立市集"),
		"顾客实际回到独立市集后再购买商品",
	)
	var goods_before := _inventory(
		world.call("get_cargo_inventory_snapshot") as Dictionary,
		"独立市集",
		"general_goods",
	)
	var grocer_sale := world.call(
		"create_occupation_service_request",
		{
			"kind": "grocer_sale",
			"requesterResidentId": BUYER_ID,
			"itemId": "general_goods",
		},
	) as Dictionary
	_expect_equal(grocer_sale.get("ok"), true, "杂货摊形成真实购买请求")
	_expect(
		_perform_and_finish(
			world,
			GROCER_ID,
			"activity_grocer_tidy_stall",
			"独立市集",
		),
		"杂货店主在固定摊位完成实际售卖",
	)
	_expect_equal(
		_inventory(
			world.call(
				"get_cargo_inventory_snapshot",
			) as Dictionary,
			"独立市集",
			"general_goods",
		),
		goods_before,
		"普通杂货完成实际售卖，但不维护有限库存",
	)
	var flower_sale := world.call(
		"create_occupation_service_request",
		{
			"kind": "flower_sale",
			"requesterResidentId": BUYER_ID,
			"itemId": "fresh_flowers",
		},
	) as Dictionary
	_expect_equal(flower_sale.get("ok"), true, "花摊形成真实购买请求")
	_expect(
		_perform_and_finish(
			world,
			FLOWER_ID,
			"activity_flower_watch_stall",
			"独立市集",
		),
		"花店店主没有鲜花库存时不会假装卖出",
	)
	var flower_request := world.call(
		"get_occupation_service_request",
		String(
			(flower_sale.get("request", {}) as Dictionary).get(
				"requestId",
				"",
			),
		),
	) as Dictionary
	_expect_equal(
		flower_request.get("state"),
		"waiting",
		"花摊缺货会明确等待园艺采收和送货",
	)



func _test_repair_waits_for_material(world: RefCounted) -> void:
	var repair := world.call(
		"create_occupation_service_request",
		{
			"kind": "repair",
			"requesterResidentId": BUYER_ID,
			"subjectRef": "坏掉的木凳",
		},
	) as Dictionary
	_expect_equal(repair.get("ok"), true, "居民形成真实维修请求")
	_expect(
		_perform_and_finish(
			world,
			CRAFT_ID,
			"activity_workshop_craft_item",
			"工作坊",
		),
		"工匠尝试处理真实维修件",
	)
	var repair_request := world.call(
		"get_occupation_service_request",
		String(
			(repair.get("request", {}) as Dictionary).get(
				"requestId",
				"",
			),
		),
	) as Dictionary
	_expect_equal(
		repair_request.get("state"),
		"pending",
		"日常维修使用基础材料完成处理并等待领取",
	)
	_expect_equal(
		(repair_request.get("outcome", {}) as Dictionary).get("supplyMode"),
		"base_always_available",
		"普通维修不会因基础木料数量为零发起补货",
	)



func _test_equipment_wear_creates_repair(world: RefCounted) -> void:
	for index in 5:
		var order := world.call(
			"create_occupation_service_request",
			{
				"kind": "cafe_order",
				"requesterResidentId": CAFE_CUSTOMER_ID,
				"itemId": "brewed_coffee",
			},
		) as Dictionary
		_expect_equal(order.get("ok"), true, "连续点单可形成设备使用")
		_expect(
			_perform_and_finish(
				world,
				CAFE_ID,
				"activity_cafe_brew_coffee",
				"花房咖啡馆",
			),
			"咖啡设备完成第 %d 次追加使用" % (index + 1),
		)
		_expect(
			_perform_and_finish(
				world,
				CAFE_ID,
				"activity_cafe_receive_guests",
				"花房咖啡馆",
			),
			"第 %d 份追加咖啡完成交付" % (index + 1),
		)
	var equipment_request: Dictionary = {}
	for request_value: Variant in (
		world.call("get_occupation_service_snapshot") as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == "repair"
			and bool(
				(request.get("context", {}) as Dictionary).get(
					"generatedFromEquipmentWear",
					false,
				)
			)
		):
			equipment_request = request.duplicate(true)
			break
	_expect(not equipment_request.is_empty(), "真实设备使用达到阈值后形成维修任务")
	_expect(
		_perform_and_finish(
			world,
			CRAFT_ID,
			"activity_workshop_craft_item",
			"工作坊",
		),
		"工匠完成设备检修",
	)
	equipment_request = world.call(
		"get_occupation_service_request",
		String(equipment_request.get("requestId", "")),
	) as Dictionary
	_expect_equal(
		equipment_request.get("state"),
		"completed",
		"公共设备检修完成后直接闭环",
	)
	var equipment_conditions := (
		world.call("get_occupation_service_snapshot") as Dictionary
	).get("equipmentConditions", {}) as Dictionary
	var has_usable_equipment := false
	for condition_value: Variant in equipment_conditions.values():
		var condition := condition_value as Dictionary
		if String(condition.get("state", "")) == "usable":
			has_usable_equipment = true
	_expect(has_usable_equipment, "检修后设备恢复可用并保留状态")



func _test_performance_requires_audience(world: RefCounted) -> void:
	var message_count_before := (
		world.call(
			"get_private_messages_for_resident",
			MUSICIAN_ID,
		) as Array
	).size()
	_expect(
		_perform_and_finish(
			world,
			MUSICIAN_ID,
			"activity_musician_rehearse",
			"中心广场",
		),
		"乐师先完成自然产生的排练计划",
	)
	var performance_request: Dictionary = {}
	for request_value: Variant in (
		world.call("get_occupation_service_snapshot") as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == "performance"
			and bool(
				(request.get("context", {}) as Dictionary).get(
					"generatedFromRehearsal",
					false,
				)
			)
		):
			performance_request = request.duplicate(true)
			break
	_expect(not performance_request.is_empty(), "排练完成后自然形成演出计划")
	_expect(
		(
			world.call(
				"get_private_messages_for_resident",
				MUSICIAN_ID,
			) as Array
		).size() >= message_count_before + 2,
		"演出计划自然产生至少两条居民邀请，形成邮差投递需求",
	)
	var invitation_found := false
	var performance_day := int(
		(performance_request.get("context", {}) as Dictionary).get(
			"dayIndex",
			-1,
		)
	)
	for message_value: Variant in world.call(
		"get_private_messages_for_resident",
		MUSICIAN_ID,
	) as Array:
		var message := message_value as Dictionary
		if (
			String(message.get("source_ref", ""))
			== "performance-event:%d" % performance_day
			and String(message.get("sender_resident_id", "")) == MUSICIAN_ID
			and String(message.get("content", ""))
			== "我准备在中心广场演奏，有空可以来听。"
		):
			invitation_found = true
			break
	_expect(invitation_found, "演出口信保留真实演出者和具体邀请内容")
	var audience_id := _activate_one_performance_listener(
		world,
		performance_request,
	)
	_expect(
		not audience_id.is_empty(),
		"至少一位收到邀请的居民实际到场并进入聆听状态",
	)
	_expect(
		_perform_and_finish(
			world,
			MUSICIAN_ID,
			"activity_musician_perform",
			"中心广场",
		),
		"乐师在真实广场区域完成演出",
	)
	performance_request = world.call(
		"get_occupation_service_request",
		String(performance_request.get("requestId", "")),
	) as Dictionary
	_expect_equal(
		performance_request.get("state"),
		"completed",
		"有实际听众时演出才完成",
	)
	_expect(
		(
			(
				performance_request.get("outcome", {}) as Dictionary
			).get("audienceResidentIds", []) as Array
		).has(audience_id),
		"演出结果记录实际在场听众",
	)



func _test_library_due_request_is_natural(world: RefCounted) -> void:
	_expect(
		_move_to_place(world, BORROWER_ID, "图书馆"),
		"借书人先实际回到图书馆",
	)
	var borrowed := world.call(
		"create_occupation_service_request",
		{
			"kind": "library_loan",
			"requesterResidentId": BORROWER_ID,
			"itemId": "book_town_history",
		},
	) as Dictionary
	_expect_equal(borrowed.get("ok"), true, "自然逾期检查先形成真实借阅")
	_expect(
		_perform_and_finish(
			world,
			LIBRARIAN_ID,
			"activity_library_staff_checkout",
			"图书馆",
		),
		"第二本书完成真实借出",
	)
	var loan_request := world.call(
		"get_occupation_service_request",
		String(
			(borrowed.get("request", {}) as Dictionary).get(
				"requestId",
				"",
			),
		),
	) as Dictionary
	var loan_id := String(
		(loan_request.get("outcome", {}) as Dictionary).get("loanId", ""),
	)
	_expect(not loan_id.is_empty(), "第二次借阅留下到期时间")
	world.call("advance", 4351.0)
	var due_return_found := false
	for request_value: Variant in (
		world.call("get_occupation_service_snapshot") as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == "library_return"
			and String(request.get("subjectRef", "")) == loan_id
			and bool(
				(request.get("context", {}) as Dictionary).get(
					"generatedFromDueLoan",
					false,
				)
			)
		):
			due_return_found = true
			break
	_expect(due_return_found, "借阅到期后自然形成归还任务")
	var due_message_found := false
	for message_value: Variant in world.call(
		"get_private_messages_for_resident",
		BORROWER_ID,
	) as Array:
		var message := message_value as Dictionary
		if (
			String(message.get("source_ref", "")) == "library-return:%s" % loan_id
			and String(message.get("recipient_resident_id", "")) == BORROWER_ID
			and String(message.get("content", ""))
			== "你借的书到归还时间了，有空请带回图书馆。"
			and OCCUPATION_RESIDENT_CONTEXT_RUNTIME.can_work_occupation(
				world,
				String(message.get("sender_resident_id", "")),
				"occupation_librarian",
			)
		):
			due_message_found = true
			break
	_expect(due_message_found, "借阅到期形成馆员发给借阅人的具体口信")


func _has_message_creation_log(
	world: RefCounted,
	source_ref: String,
	recipient_id: String,
	content_prefix: String,
	sender_occupation_id: String,
) -> bool:
	var store := world.get("_world_log_store") as RefCounted
	if store == null:
		return false
	var snapshot := store.call(
		"create_save_snapshot",
		int(world.get("_world_revision")),
	) as Dictionary
	for record_value: Variant in snapshot.get("records", []) as Array:
		var record := record_value as Dictionary
		var payload := record.get("payload", {}) as Dictionary
		if (
			String(payload.get("type", "")) != "消息创建"
			or String(payload.get("sourceRef", "")) != source_ref
			or String(payload.get("recipientResidentId", "")) != recipient_id
			or not String(payload.get("content", "")).begins_with(content_prefix)
		):
			continue
		var sender_id := String(payload.get("senderResidentId", ""))
		return bool(world.call(
			"_resident_can_work_occupation",
			sender_id,
			sender_occupation_id,
		))
	return false



func _expect_periodic_task_backlog_bounded(world: RefCounted) -> void:
	var prepared := world.call("prepare_save_candidate") as Dictionary
	var state := (
		prepared.get("snapshot", {}) as Dictionary
	).get("state", {}) as Dictionary
	var counts := {
		"daily_baking_plan": 0,
		"personal_performance_plan": 0,
		"warehouse_audit": 0,
		"daily_town_state": 0,
	}
	for task_value: Variant in (
		state.get("workTasks", {}) as Dictionary
	).get("tasks", []) as Array:
		var task := task_value as Dictionary
		if String(task.get("state", "")) in [
			"completed",
			"failed",
			"cancelled",
		]:
			continue
		var source_kind := String(task.get("sourceKind", ""))
		var source_ref := String(task.get("sourceRef", ""))
		if counts.has(source_kind):
			counts[source_kind] = int(counts.get(source_kind, 0)) + 1
		elif source_ref.begins_with("warehouse-audit:"):
			counts["warehouse_audit"] = int(counts["warehouse_audit"]) + 1
		elif source_ref.begins_with("daily-town-state:"):
			counts["daily_town_state"] = int(counts["daily_town_state"]) + 1
	for key: String in counts:
		_expect(
			int(counts.get(key, 0)) <= 1,
			"跨日运行不会堆积重复周期任务：%s=%d"
				% [key, int(counts.get(key, 0))],
		)



func _prepare_residents(opening: Dictionary) -> void:
	var assignments := {
		CRAFT_ID: ["工匠", "工作坊", "indoor_workshop", "region_portal_workshop_entry", [0, 384]],
		PATIENT_ID: ["园艺师", "社区花园", "indoor_clinic", "region_portal_clinic_entry", [464, 496]],
		CAFE_ID: ["咖啡店店员", "花房咖啡馆", "indoor_flower_cafe", "region_portal_cafe_entry", [464, 304]],
		DOCTOR_ID: ["草药医师", "诊所", "indoor_clinic", "region_portal_clinic_entry", [464, 368]],
		LIBRARIAN_ID: ["图书管理员", "图书馆", "indoor_library", "region_portal_library_entry", [720, 336]],
		BORROWER_ID: ["小镇管理者", "镇公所", "indoor_library", "region_portal_library_entry", [720, 432]],
		BUYER_ID: ["仓库管理员", "码头仓库", "indoor_market_shop", "region_portal_market_shop_entry", [320, 700]],
		DINING_CUSTOMER_ID: ["邮差", "小镇道路", "indoor_dining_hall", "region_portal_dining_hall_entry", [688, 384]],
		COOK_ID: ["食堂主理人", "公共食堂", "indoor_dining_hall", "region_portal_dining_hall_entry", [368, 384]],
		GROCER_ID: ["杂货店主", "独立市集", "indoor_market_shop", "region_portal_market_shop_entry", [224, 800]],
		FLOWER_ID: ["花店店主", "独立市集", "indoor_market_shop", "region_portal_market_shop_entry", [1024, 800]],
		CAFE_CUSTOMER_ID: ["植物研究员", "社区花园", "indoor_flower_cafe", "region_portal_cafe_entry", [464, 496]],
		"resident_jiang_lin_01": ["送货员", "码头仓库", "indoor_workshop", "region_portal_workshop_entry", [-160, 144]],
		MUSICIAN_ID: ["乐师", "中心广场", "town_outdoor", "outdoor_plaza_01", [3300, 1950]],
		AUDIENCE_ID: ["渔夫", "渔港", "town_outdoor", "outdoor_plaza_01", [3260, 2020]],
	}
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		var resident_id := String(resident.get("residentId", ""))
		if not assignments.has(resident_id):
			continue
		var assignment := assignments[resident_id] as Array
		var social_state := resident.get("socialState", {}) as Dictionary
		social_state["job"] = String(assignment[0])
		social_state["workplace"] = String(assignment[1])
		var world_state := resident.get("worldState", {}) as Dictionary
		world_state["place"] = _place_for_space(
			String(assignment[2]),
			String(assignment[3]),
		)
		world_state["spaceId"] = String(assignment[2])
		world_state["regionId"] = String(assignment[3])
		world_state["position"] = (assignment[4] as Array).duplicate()



func _place_for_space(space_id: String, region_id: String) -> String:
	if space_id == "town_outdoor":
		return "中心广场" if region_id == "outdoor_plaza_01" else "小镇道路"
	return {
		"indoor_workshop": "工作坊",
		"indoor_clinic": "诊所",
		"indoor_flower_cafe": "花房咖啡馆",
		"indoor_library": "图书馆",
		"indoor_market_shop": "独立市集",
		"indoor_dining_hall": "公共食堂",
	}.get(space_id, "")



func _perform_and_finish(
	world: RefCounted,
	resident_id: String,
	activity_id: String,
	place_id: String,
) -> bool:
	_activity_sequence += 1
	var performed := world.call(
		"perform_activity_step",
		resident_id,
		"occupation-service-test-plan-%d" % _activity_sequence,
		0,
		{
			"stepId": "service-step:%s:%d"
				% [activity_id, _activity_sequence],
			"operation": "activity.perform",
			"target": {
				"activityId": activity_id,
				"placeId": place_id,
			},
			"params": {"reason": "处理一条真实职业服务请求"},
		},
	) as Dictionary
	if String(performed.get("errorCode", "")) == (
		"ACTIVITY_REQUIRES_TRAVEL_STEP"
	):
		if not _move_to_place(world, resident_id, place_id):
			return false
		_activity_sequence += 1
		performed = world.call(
			"perform_activity_step",
			resident_id,
			"occupation-service-test-plan-%d" % _activity_sequence,
			0,
			{
				"stepId": "service-step:%s:%d"
					% [activity_id, _activity_sequence],
				"operation": "activity.perform",
				"target": {
					"activityId": activity_id,
					"placeId": place_id,
				},
				"params": {"reason": "处理一条真实职业服务请求"},
			},
		) as Dictionary
	if performed.get("ok") != true:
		_failures.append(
			"活动 %s 无法开始：%s" % [activity_id, performed],
		)
		return false
	for _minute in 180:
		var state := world.call(
			"get_resident_state",
			resident_id,
		) as Dictionary
		if state.get("currentAction") == null:
			return true
		world.call("advance", 1.0)
	return false



func _advance_until_work_task(
	world: RefCounted,
	resident_id: String,
	capability: String,
	source_kind: String,
	max_minutes: int,
) -> bool:
	for _minute in max_minutes + 1:
		if _has_work_task(world, resident_id, capability, source_kind):
			return true
		world.call("advance", 1.0)
	return false



func _advance_to_meal_preparation_window(world: RefCounted) -> bool:
	for _minute in 1440:
		var now := int(
			(world.get("_environment") as RefCounted).call(
				"get_absolute_minute",
			)
		)
		var minute_of_day := posmod(now, 1440)
		if (
			minute_of_day in range(300, 360)
			or minute_of_day in range(600, 660)
			or minute_of_day in range(960, 1020)
		):
			return true
		world.call("advance", 1.0)
	return false



func _activate_one_performance_listener(
	world: RefCounted,
	performance_request: Dictionary,
) -> String:
	var day_index := int(
		(performance_request.get("context", {}) as Dictionary).get(
			"dayIndex",
			-1,
		)
	)
	if day_index < 0:
		return ""
	var source_ref := "performance-event:%d" % day_index
	var private_message_runtime := (
		world.private_message_runtime as TownPrivateMessageRuntime
	)
	var message_ids := private_message_runtime.sorted_message_ids()
	for message_id: String in message_ids:
		var message := private_message_runtime.message(message_id)
		if (
			String(message.get("state", "")) != "pending"
			or String(message.get("sourceRef", "")) != source_ref
		):
			continue
		var recipient_id := String(
			message.get("recipientResidentId", ""),
		)
		var now := int(
			(world.get("_environment") as RefCounted).call(
				"get_absolute_minute",
			)
		)
		message["state"] = "delivered"
		message["deliveredAtMinute"] = now
		message["deliveredByResidentId"] = DINING_CUSTOMER_ID
		private_message_runtime.set_message(message_id, message)
		PRIVATE_MESSAGE_DELIVERY_RUNTIME.activate_follow_up(
			world,
			message_id,
			message,
			now,
		)
		var residents := (world.get("resident_registry") as TownResidentRegistry).records as Dictionary
		var listener := residents.get(recipient_id, {}) as Dictionary
		listener["currentPlace"] = "中心广场"
		listener["spaceId"] = "town_outdoor"
		listener["regionId"] = "outdoor_plaza_01"
		listener["position"] = Vector2(3260, 2020)
		listener["currentAction"] = {}
		residents[recipient_id] = listener
		(world.get("resident_registry") as TownResidentRegistry).records = residents
		PERFORMANCE_SERVICE_RUNTIME.begin_listener_wait(
			world,
			recipient_id,
			day_index,
		)
		return recipient_id
	return ""



func _advance_until_service_state(
	world: RefCounted,
	request_id: String,
	expected_state: String,
	max_minutes: int,
) -> bool:
	for _minute in max_minutes + 1:
		var request := world.call(
			"get_occupation_service_request",
			request_id,
		) as Dictionary
		if String(request.get("state", "")) == expected_state:
			return true
		world.call("advance", 1.0)
	return false



func _submit_decision_action(
	world: RefCounted,
	resident_id: String,
	action_fields: Dictionary,
) -> bool:
	var requests: Array = []
	for _attempt in 30:
		requests = world.call(
			"take_pending_decision_requests_by_ids",
			[resident_id],
		) as Array
		if not requests.is_empty():
			break
		world.call("advance", 1.0)
	if requests.is_empty():
		_failures.append("%s 没有可提交的决定" % resident_id)
		return false
	var wake := (
		(requests[0] as Dictionary).get("wakePacket", {}) as Dictionary
	)
	var decision_id := String(wake.get("decision_id", ""))
	var action := action_fields.duplicate(true)
	action["action_id"] = "%s-%s" % [
		decision_id,
		String(action.get("type", "act")),
	]
	var accepted := world.call(
		"submit_agent_decision_by_id",
		resident_id,
		{
			"decision_id": decision_id,
			"handling": "replace_current",
			"action": action,
		},
	) as Dictionary
	if accepted.get("status") != "accepted":
		_failures.append(
			"%s 的 %s 决定未接受：%s"
			% [resident_id, String(action.get("type", "")), accepted],
		)
		return false
	return true



func _move_to_place(
	world: RefCounted,
	resident_id: String,
	place_id: String,
) -> bool:
	var requests: Array = []
	for _attempt in 10:
		requests = world.call(
			"take_pending_decision_requests_by_ids",
			[resident_id],
		) as Array
		if not requests.is_empty():
			break
		world.call("advance", 1.0)
	if requests.is_empty():
		_failures.append("%s 没有可提交的移动决定" % resident_id)
		return false
	var wake := (
		(requests[0] as Dictionary).get("wakePacket", {}) as Dictionary
	)
	var decision_id := String(wake.get("decision_id", ""))
	var accepted := world.call(
		"submit_agent_decision_by_id",
		resident_id,
		{
			"decision_id": decision_id,
			"handling": "replace_current",
			"action": {
				"action_id": "%s-move" % decision_id,
				"type": "去",
				"place": place_id,
				"line": "前往职业活动地点。",
			},
		},
	) as Dictionary
	if accepted.get("status") != "accepted":
		_failures.append("移动决定未接受：%s" % [accepted])
		return false
	for _minute in 900:
		var state := world.call(
			"get_resident_state",
			resident_id,
		) as Dictionary
		if state.get("currentAction") == null:
			return String(state.get("currentPlace", "")) == place_id
		world.call("advance", 1.0)
	return false



func _has_work_task(
	world: RefCounted,
	resident_id: String,
	capability: String,
	source_kind: String,
) -> bool:
	for task_value: Variant in world.call(
		"get_work_tasks_for_resident",
		resident_id,
	) as Array:
		var task := task_value as Dictionary
		if (
			String(task.get("capability", "")) == capability
			and String(task.get("source_kind", "")) == source_kind
		):
			return true
	return false



func _saved_work_task(world: RefCounted, task_id: String) -> Dictionary:
	var prepared := world.call("prepare_save_candidate") as Dictionary
	var state := (
		prepared.get("snapshot", {}) as Dictionary
	).get("state", {}) as Dictionary
	for task_value: Variant in (
		state.get("workTasks", {}) as Dictionary
	).get("tasks", []) as Array:
		var task := task_value as Dictionary
		if String(task.get("taskId", "")) == task_id:
			return task.duplicate(true)
	return {}



func _inventory(
	snapshot: Dictionary,
	place_id: String,
	item_id: String,
) -> int:
	return int(
		(
			(
				snapshot.get("inventories", {}) as Dictionary
			).get(place_id, {}) as Dictionary
		).get(item_id, 0),
	)



func _has_active_lot(
	snapshot: Dictionary,
	item_id: String,
	source_place_id: String,
	destination_place_id: String,
) -> bool:
	for value: Variant in snapshot.get("cargoLots", []) as Array:
		var lot := value as Dictionary
		if (
			String(lot.get("itemId", "")) == item_id
			and String(lot.get("sourcePlaceId", ""))
			== source_place_id
			and String(lot.get("destinationPlaceId", ""))
			== destination_place_id
			and String(lot.get("state", ""))
			in [
				"awaiting_release",
				"available",
				"in_transit",
				"awaiting_receipt",
			]
		):
			return true
	return false



func _scenario_occupation_downstream_closure_integration() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(
		OPENING_PATH,
		data,
	) as Dictionary
	_expect(
		opening_result.get("ok") == true,
		"职业下游闭环可以加载开局",
	)
	if opening_result.get("ok") != true:
		return
	var opening := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	_prepare_residents_occupation_downstream_closure_integration(opening)
	var world: RefCounted = WORLD.new()
	var start_result := world.call("start", data, opening) as Dictionary
	_expect(
		start_result.get("ok") == true,
		"职业下游闭环 World 可以启动：%s" % [start_result],
	)
	if start_result.get("ok") != true:
		return
	_test_warehouse_release_and_repair_pickup(world)
	_test_flower_preparation(world)
	_test_dining_cleanup(world)
	_test_cafe_cleanup(world)
	var prepared := world.call("prepare_save_candidate") as Dictionary
	_expect(
		prepared.get("ok") == true,
		"出库、领取和清洁结果可以保存",
	)
	var restored: RefCounted = WORLD.new()
	_expect(
		(
			restored.call(
				"restore_from_snapshot",
				data,
				opening,
				prepared.get("snapshot", {}) as Dictionary,
			) as Dictionary
		).get("ok") == true,
		"出库、领取和清洁结果可以恢复",
	)
	var restored_service := restored.call(
		"get_occupation_service_snapshot",
	) as Dictionary
	_expect_equal(
		restored_service.get("dirtyDishCount"),
		0,
		"恢复后餐具清洁状态保持完成",
	)
	_expect_equal(
		restored_service.get("usedCafeTableCount"),
		0,
		"恢复后咖啡桌清洁状态保持完成",
	)
	world.call("stop")
	restored.call("stop")
	return
func _prepare_residents_occupation_downstream_closure_integration(opening: Dictionary) -> void:
	for value: Variant in opening.get("residents", []) as Array:
		var resident := value as Dictionary
		var resident_id := String(resident.get("residentId", ""))
		match resident_id:
			CRAFTSPERSON_ID:
				_set_job_and_place(
					resident,
					"工匠",
					"工作坊",
					"工作坊",
					"indoor_workshop",
					Vector2(16, 752),
				)
			DELIVERY_ID:
				_set_job_and_place(
					resident,
					"送货员",
					"码头仓库",
					"码头仓库",
					"indoor_dock_warehouse",
					Vector2(432, 784),
				)
			DINING_WORKER_ID:
				_set_job_and_place(
					resident,
					"食堂主理人",
					"公共食堂",
					"公共食堂",
					"indoor_dining_hall",
					Vector2(528, 1040),
				)
			CAFE_WORKER_ID:
				_set_job_and_place(
					resident,
					"咖啡店店员",
					"花房咖啡馆",
					"花房咖啡馆",
					"indoor_flower_cafe",
					Vector2(464, 304),
				)
			CAFE_VISITOR_ID:
				# redesign_v2 室内改版后 (112,688) 不再是正式可走格，
				# 改用最近的合法格。
				_set_world_place(
					resident,
					"花房咖啡馆",
					"indoor_flower_cafe",
					Vector2(176, 752),
				)
			FLOWER_VENDOR_ID:
				_set_job_and_place(
					resident,
					"花店店主",
					"独立市集",
					"独立市集",
					"indoor_market_shop",
					Vector2(624, 912),
				)



func _set_job_and_place(
	resident: Dictionary,
	job: String,
	workplace: String,
	place_id: String,
	space_id: String,
	position: Vector2,
) -> void:
	var social_state := resident.get("socialState", {}) as Dictionary
	social_state["job"] = job
	social_state["workplace"] = workplace
	_set_world_place(resident, place_id, space_id, position)



func _set_world_place(
	resident: Dictionary,
	place_id: String,
	space_id: String,
	position: Vector2,
) -> void:
	var world_state := resident.get("worldState", {}) as Dictionary
	world_state["place"] = place_id
	world_state["spaceId"] = space_id
	world_state["regionId"] = String({
		"工作坊": "region_portal_workshop_entry",
		"码头仓库": "region_portal_dock_warehouse_entry",
		"公共食堂": "region_portal_dining_hall_entry",
		"花房咖啡馆": "region_portal_cafe_entry",
		"独立市集": "region_portal_market_shop_entry",
	}.get(place_id, ""))
	world_state["position"] = [position.x, position.y]



func _test_warehouse_release_and_repair_pickup(
	world: RefCounted,
) -> void:
	# 基础木料已改为无限供给、不走货批；特种木料按现行模型先经
	# 南入口外部供应入库，仓库才有货可以向工作坊出库。
	var supply_lot := world.call(
		"create_external_supply_cargo_lot",
		{
			"itemId": "special_lumber",
			"quantity": 1,
			"destinationPlaceId": "码头仓库",
			"priority": 99,
		},
	) as Dictionary
	_expect(
		supply_lot.get("ok") == true,
		"特种木料以外部供应货批抵达南入口",
	)
	var supply_lot_id := String(
		(supply_lot.get("lot", {}) as Dictionary).get("lotId", ""),
	)
	# 配送任务机制会在送货员抵达来源地时自动领取货批，无需手动 pickup。
	_expect(
		_move_to_place_occupation_downstream_closure_integration(world, DELIVERY_ID, "南入口"),
		"送货员前往南入口接货",
	)
	_expect(
		_move_to_place_occupation_downstream_closure_integration(world, DELIVERY_ID, "码头仓库"),
		"送货员把特种木料送到码头仓库",
	)
	_expect_equal(
		_lot(world, supply_lot_id).get("state"),
		"awaiting_receipt",
		"外部供应货批送达码头仓库待验收",
	)
	_expect(
		_perform_and_finish_occupation_downstream_closure_integration(
			world,
			WAREHOUSE_ID,
			"activity_warehouse_check_cargo",
			"码头仓库",
			"验收外部供应入库",
		),
		"仓管验收后特种木料进入仓库库存",
	)
	var created_lot := world.call(
		"create_cargo_lot",
		{
			"itemId": "special_lumber",
			"quantity": 1,
			"sourcePlaceId": "码头仓库",
			"destinationPlaceId": "工作坊",
			"priority": 99,
		},
	) as Dictionary
	_expect(
		created_lot.get("ok") == true,
		"工作坊缺料会形成仓库木料货批",
	)
	var lot_id := String(
		(created_lot.get("lot", {}) as Dictionary).get(
			"lotId",
			"",
		),
	)
	_expect_equal(
		_lot(world, lot_id).get("state"),
		"awaiting_release",
		"仓库木料先等待仓管核准",
	)
	_expect(
		_perform_and_finish_occupation_downstream_closure_integration(
			world,
			WAREHOUSE_ID,
			"activity_warehouse_check_manifest",
			"码头仓库",
			"核对并放行工作坊木料",
		),
		"仓管可以完成真实出库任务",
	)
	var released_lot := _lot(world, lot_id)
	_expect_equal(
		released_lot.get("state"),
		"available",
		"核准后货批才可由送货员领取",
	)
	_expect_equal(
		released_lot.get("releasedByResidentId"),
		WAREHOUSE_ID,
		"出库记录保存实际仓管",
	)
	_expect(
		(world.call(
			"pickup_cargo_lot",
			lot_id,
			DELIVERY_ID,
		) as Dictionary).get("ok") == true,
		"送货员在仓库领取已放行货批",
	)
	_expect(
		_move_to_place_occupation_downstream_closure_integration(world, DELIVERY_ID, "工作坊"),
		"送货员带着货批前往工作坊",
	)
	_expect(
		String(_lot(world, lot_id).get("state", ""))
		== "awaiting_receipt",
		"送货员到达后把木料交到工作坊等待验收",
	)
	_expect(
		_perform_and_finish_occupation_downstream_closure_integration(
			world,
			CRAFTSPERSON_ID,
			"activity_workshop_take_lumber",
			"工作坊",
			"验收送达的木料",
		),
		"工匠验收后木料才进入工作坊库存",
	)
	var request_result := world.call(
		"create_occupation_service_request",
		{
			"kind": "repair",
			"requesterResidentId": DELIVERY_ID,
			"subjectRef": "broken-delivery-crate",
		},
	) as Dictionary
	_expect(
		request_result.get("ok") == true,
		"居民可以提交真实维修委托",
	)
	var request_id := String(
		(request_result.get("request", {}) as Dictionary).get(
			"requestId",
			"",
		),
	)
	_expect(
		_perform_and_finish_occupation_downstream_closure_integration(
			world,
			CRAFTSPERSON_ID,
			"activity_workshop_craft_item",
			"工作坊",
			"使用已入库木料修好委托物",
		),
		"工匠完成维修并形成待领取结果",
	)
	var ready_request := world.call(
		"get_occupation_service_request",
		request_id,
	) as Dictionary
	_expect_equal(
		ready_request.get("state"),
		"pending",
		"修好不等于已经交给委托人",
	)
	_expect_equal(
		(ready_request.get("outcome", {}) as Dictionary).get("status"),
		"ready_for_pickup",
		"维修结果明确等待领取",
	)
	_expect(
		_perform_and_finish_occupation_downstream_closure_integration(
			world,
			DELIVERY_ID,
			"activity_workshop_inspect_finished",
			"工作坊",
			"领取自己的修理件",
		),
		"委托人到成品架领取修理件",
	)
	var picked_up_request := world.call(
		"get_occupation_service_request",
		request_id,
	) as Dictionary
	_expect_equal(
		picked_up_request.get("state"),
		"completed",
		"实际领取后维修委托才完成",
	)
	_expect_equal(
		(
			picked_up_request.get("outcome", {}) as Dictionary
		).get("deliveredToRequester"),
		true,
		"维修结果记录已经交给本人",
	)



func _test_flower_preparation(world: RefCounted) -> void:
	var created_lot := world.call(
		"create_world_result_cargo_lot",
		{
			"itemId": "fresh_flowers",
			"quantity": 4,
			"sourcePlaceId": "社区花园",
			"destinationPlaceId": "独立市集",
			"priority": 99,
		},
	) as Dictionary
	_expect(
		created_lot.get("ok") == true,
		"花园收获形成真实鲜花货批",
	)
	var lot_id := String(
		(created_lot.get("lot", {}) as Dictionary).get(
			"lotId",
			"",
		),
	)
	_expect(
		_move_to_place_occupation_downstream_closure_integration(world, DELIVERY_ID, "社区花园"),
		"送货员前往花园领取鲜花",
	)
	var flower_lot := _lot(world, lot_id)
	var pickup_ok := String(flower_lot.get("state", "")) == "in_transit"
	if String(flower_lot.get("state", "")) == "available":
		pickup_ok = (
			world.call(
				"pickup_cargo_lot",
				lot_id,
				DELIVERY_ID,
			) as Dictionary
		).get("ok") == true
	_expect(
		pickup_ok,
		"送货员领取真实鲜花货批",
	)
	_expect(
		_move_to_place_occupation_downstream_closure_integration(world, DELIVERY_ID, "独立市集"),
		"送货员把鲜花送到独立市集",
	)
	_expect_equal(
		_lot(world, lot_id).get("state"),
		"awaiting_receipt",
		"鲜花到达后等待花店店主验收",
	)
	_expect(
		_perform_and_finish_occupation_downstream_closure_integration(
			world,
			FLOWER_VENDOR_ID,
			"activity_flower_arrange_bouquets",
			"独立市集",
			"先验收送到花摊的鲜花",
		),
		"花店店主把鲜花验收入市集库存",
	)
	_expect_equal(
		_inventory_occupation_downstream_closure_integration(world, "独立市集", "fresh_flowers"),
		4,
		"验收后鲜花进入有限库存",
	)
	_expect(
		_has_task(world, FLOWER_VENDOR_ID, "retail.arrange"),
		"鲜花库存形成整理花束任务",
	)
	_expect(
		_perform_and_finish_occupation_downstream_closure_integration(
			world,
			FLOWER_VENDOR_ID,
			"activity_flower_arrange_bouquets",
			"独立市集",
			"把库存鲜花整理成花束",
		),
		"花店店主完成真实花束整理",
	)
	_expect_equal(
		_inventory_occupation_downstream_closure_integration(world, "独立市集", "fresh_flowers"),
		2,
		"整理花束消耗两份鲜花",
	)
	_expect_equal(
		_inventory_occupation_downstream_closure_integration(world, "独立市集", "bouquet"),
		1,
		"整理后形成可售花束库存",
	)



func _test_dining_cleanup(world: RefCounted) -> void:
	_expect(
		_perform_and_finish_occupation_downstream_closure_integration(
			world,
			DINING_VISITOR_ID,
			"activity_dining_return_dishes",
			"公共食堂",
			"吃完后归还餐具",
		),
		"居民归还的餐具进入待洗状态",
	)
	var service_state := world.call(
		"get_occupation_service_snapshot",
	) as Dictionary
	_expect_equal(
		service_state.get("dirtyDishCount"),
		1,
		"归还餐具形成真实清洁数量",
	)
	_expect(
		_has_task(world, DINING_WORKER_ID, "food.cleanup"),
		"脏餐具形成食堂清洁任务",
	)
	_expect(
		_perform_and_finish_occupation_downstream_closure_integration(
			world,
			DINING_WORKER_ID,
			"activity_dining_wash_dishes",
			"公共食堂",
			"清洗居民归还的餐具",
		),
		"食堂主理人完成真实餐具清洁",
	)
	service_state = world.call(
		"get_occupation_service_snapshot",
	) as Dictionary
	_expect_equal(
		service_state.get("dirtyDishCount"),
		0,
		"洗完后待洗餐具数量归零",
	)



func _test_cafe_cleanup(world: RefCounted) -> void:
	_expect(
		_perform_and_finish_occupation_downstream_closure_integration(
			world,
			CAFE_VISITOR_ID,
			"activity_cafe_rest",
			"花房咖啡馆",
			"在咖啡馆座位休息",
		),
		"居民实际使用咖啡馆座位",
	)
	var service_state := world.call(
		"get_occupation_service_snapshot",
	) as Dictionary
	_expect_equal(
		service_state.get("usedCafeTableCount"),
		1,
		"使用过的桌位进入待整理状态",
	)
	_expect(
		_has_task(world, CAFE_WORKER_ID, "cafe.handoff"),
		"使用过的桌位形成咖啡馆整理任务",
	)
	_expect(
		_perform_and_finish_occupation_downstream_closure_integration(
			world,
			CAFE_WORKER_ID,
			"activity_cafe_tidy_tables",
			"花房咖啡馆",
			"整理客人用过的桌位",
		),
		"咖啡店员完成真实桌位整理",
	)
	service_state = world.call(
		"get_occupation_service_snapshot",
	) as Dictionary
	_expect_equal(
		service_state.get("usedCafeTableCount"),
		0,
		"整理后待处理桌位数量归零",
	)



func _perform_and_finish_occupation_downstream_closure_integration(
	world: RefCounted,
	resident_id: String,
	activity_id: String,
	place_id: String,
	reason: String,
) -> bool:
	_plan_sequence += 1
	var performed := world.call(
		"perform_activity_step",
		resident_id,
		"closure-plan-%d" % _plan_sequence,
		0,
		{
			"stepId": "closure-step",
			"operation": "activity.perform",
			"target": {
				"activityId": activity_id,
				"placeId": place_id,
			},
			"params": {"reason": reason},
		},
	) as Dictionary
	if performed.get("ok") != true:
		_failures.append(
			"活动 %s 未开始：%s" % [activity_id, performed],
		)
		return false
	return _advance_until_clear(world, resident_id)



func _move_to_place_occupation_downstream_closure_integration(
	world: RefCounted,
	resident_id: String,
	place_id: String,
) -> bool:
	var requests: Array = []
	for _attempt in 10:
		requests = world.call(
			"take_pending_decision_requests_by_ids",
			[resident_id],
		) as Array
		if not requests.is_empty():
			break
		world.call("advance", 1.0)
	if requests.is_empty():
		_failures.append("%s 没有可提交的移动决定" % resident_id)
		return false
	var wake := (
		(requests[0] as Dictionary).get(
			"wakePacket",
			{},
		) as Dictionary
	)
	var decision_id := String(wake.get("decision_id", ""))
	var accepted := world.call(
		"submit_agent_decision_by_id",
		resident_id,
		{
			"decision_id": decision_id,
			"handling": "replace_current",
			"action": {
				"action_id": "%s-move" % decision_id,
				"type": "去",
				"place": place_id,
				"line": "带着货物前往目的地。",
			},
		},
	) as Dictionary
	if accepted.get("status") != "accepted":
		_failures.append("移动决定未接受：%s" % [accepted])
		return false
	if not _advance_until_clear(world, resident_id, 900):
		return false
	return String(
		(world.call(
			"get_resident_state",
			resident_id,
		) as Dictionary).get("currentPlace", ""),
	) == place_id



func _advance_until_clear(
	world: RefCounted,
	resident_id: String,
	max_minutes := 240,
) -> bool:
	for _minute in max_minutes:
		var state := world.call(
			"get_resident_state",
			resident_id,
		) as Dictionary
		if state.get("currentAction") == null:
			return true
		world.call("advance", 1.0)
	return false



func _lot(world: RefCounted, lot_id: String) -> Dictionary:
	for value: Variant in (
		world.call("get_cargo_inventory_snapshot") as Dictionary
	).get("cargoLots", []) as Array:
		var lot := value as Dictionary
		if String(lot.get("lotId", "")) == lot_id:
			return lot
	return {}



func _inventory_occupation_downstream_closure_integration(
	world: RefCounted,
	place_id: String,
	item_id: String,
) -> int:
	var snapshot := world.call(
		"get_cargo_inventory_snapshot",
	) as Dictionary
	return int(
		(
			(
				snapshot.get("inventories", {}) as Dictionary
			).get(place_id, {}) as Dictionary
		).get(item_id, 0),
	)



func _has_task(
	world: RefCounted,
	resident_id: String,
	capability: String,
) -> bool:
	for value: Variant in world.call(
		"get_work_tasks_for_resident",
		resident_id,
	) as Array:
		if String((value as Dictionary).get(
			"capability",
			"",
		)) == capability:
			return true
	return false



func _scenario_staffing_negotiation_integration() -> void:
	var world_data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(
		OPENING_PATH,
		world_data,
	) as Dictionary
	_expect(
		opening_result.get("ok") == true,
		"opening fixture loads",
	)
	if opening_result.get("ok") != true:
		return
	var opening := FORMAL_OPENING.with_authoritative_outdoor_spawns(
		world_data,
		opening_result.get("config", {}) as Dictionary,
	)
	var occupations := (
		world_data.get("occupations", []) as Array
	).duplicate()
	occupations.sort_custom(
		func(left: Variant, right: Variant) -> bool:
			return String((left as Dictionary).get(
				"occupationId",
				"",
			)) < String((right as Dictionary).get(
				"occupationId",
				"",
			))
	)
	var residents := opening.get("residents", []) as Array
	for index: int in mini(residents.size(), occupations.size()):
		var occupation := occupations[index] as Dictionary
		var social_state := (
			(residents[index] as Dictionary).get(
				"socialState",
				{},
			) as Dictionary
		)
		social_state["job"] = String(occupation.get("label", ""))
		social_state["workplace"] = String(
			occupation.get("primaryWorkplacePlace", ""),
		)
	var cafe_index := _resident_index_for_job(
		residents,
		"咖啡店店员",
	)
	var grocer_index := _resident_index_for_job(
		residents,
		"杂货店主",
	)
	_expect(cafe_index >= 0, "recommended fixture contains cafe worker")
	_expect(grocer_index >= 0, "recommended fixture contains grocer")
	if cafe_index < 0 or grocer_index < 0:
		return
	var duplicate_social := (
		(residents[cafe_index] as Dictionary).get(
			"socialState",
			{},
		) as Dictionary
	)
	duplicate_social["job"] = "杂货店主"
	duplicate_social["workplace"] = "独立市集"

	var world: RefCounted = WORLD.new()
	var started := world.call(
		"start_formal",
		world_data,
		opening,
		_resident_identities(opening),
	) as Dictionary
	_expect(started.get("ok") == true, "world accepts repeated jobs")
	if started.get("ok") != true:
		return
	var staffing := world.call("get_staffing_snapshot") as Dictionary
	_expect_equal(
		(staffing.get("vacantPostIds", []) as Array).size(),
		1,
		"repeated occupation creates one vacancy",
	)
	_expect_equal(
		(staffing.get("duplicatePostIds", []) as Array).size(),
		1,
		"repeated occupation remains visible",
	)
	var closed_cafe := _place_service_state(
		world,
		"花房咖啡馆",
	)
	_expect_equal(
		closed_cafe.get("open"),
		false,
		"vacant cafe remains visible but service is closed",
	)
	_expect_equal(
		closed_cafe.get("owner_id"),
		"",
		"vacant service does not pick an arbitrary legacy owner",
	)
	var vacancy_matter_id := _job_vacancy_matter_id(world)
	_expect(
		not vacancy_matter_id.is_empty(),
		"vacancy creates a public staffing matter",
	)
	if vacancy_matter_id.is_empty():
		return
	var volunteer_id := String(
		(residents[cafe_index] as Dictionary).get(
			"residentId",
			"",
		)
	)
	var submitted_count := 0
	for resident_value: Variant in residents:
		var resident_id := String(
			(resident_value as Dictionary).get("residentId", ""),
		)
		var matter := _agent_matter(
			world,
			resident_id,
			vacancy_matter_id,
		)
		if matter.is_empty():
			continue
		var option_id := (
			"volunteer_transfer"
			if resident_id == volunteer_id
			else "keep_current_job"
		)
		var options := matter.get("options", []) as Array
		if not options.any(
			func(value: Variant) -> bool:
				return String((value as Dictionary).get(
					"option_id",
					"",
				)) == option_id
		):
			continue
		var response := world.call(
			"submit_social_response",
			resident_id,
			{
				"response_id": "staffing-response:%s" % resident_id,
				"matter_id": vacancy_matter_id,
				"matter_revision": int(matter.get("revision", 0)),
				"response_round_id": String(
					matter.get("response_round_id", ""),
				),
				"option_id": option_id,
				"public_text": "",
			},
		) as Dictionary
		_expect(
			response.get("ok") == true,
			"candidate response is accepted: %s" % resident_id,
		)
		submitted_count += 1
	_expect(submitted_count > 0, "staffing round has candidates")
	var settled := world.call(
		"get_staffing_snapshot",
	) as Dictionary
	_expect_equal(
		settled.get("vacantPostIds"),
		[],
		"World-selected volunteer fills the vacancy",
	)
	_expect_equal(
		settled.get("duplicatePostIds"),
		[],
		"voluntary transfer resolves the duplicate",
	)
	var volunteer_initialization := world.call(
		"get_agent_initialization",
		volunteer_id,
	) as Dictionary
	_expect_equal(
		(
			(
				volunteer_initialization.get(
					"me",
					{},
				) as Dictionary
			).get(
				"social_state",
				{},
			) as Dictionary
		).get("job"),
		"咖啡店店员",
		"occupation changes only after the resident volunteers and World settles",
	)
	var pending_cafe := _place_service_state(
		world,
		"花房咖啡馆",
	)
	_expect_equal(
		pending_cafe.get("open"),
		false,
		"the reassigned service waits until its new worker reaches town",
	)
	_expect_equal(
		pending_cafe.get("owner_id"),
		"",
		"an absent worker is not exposed as an active service owner",
	)
	var volunteer_state := world.call(
		"get_resident_state",
		volunteer_id,
	) as Dictionary
	var arrival_state := (
		volunteer_state.get("arrivalState", {}) as Dictionary
	)
	var minutes_until_arrival := (
		int(arrival_state.get("scheduledAbsoluteMinute", -1))
		- _absolute_minute(world.call("get_time"))
	)
	_expect(
		minutes_until_arrival > 0,
		"the reassigned resident keeps the first-morning arrival schedule",
	)
	if minutes_until_arrival > 0:
		world.call("advance", float(minutes_until_arrival))
	var reopened_cafe := _place_service_state(
		world,
		"花房咖啡馆",
	)
	_expect_equal(
		reopened_cafe.get("open"),
		true,
		"service reopens when the newly responsible worker arrives",
	)
	_expect_equal(
		reopened_cafe.get("owner_id"),
		volunteer_id,
		"the arrived formal worker becomes the service responsibility",
	)
	return
func _resident_index_for_job(residents: Array, job: String) -> int:
	for index: int in residents.size():
		if String(
			(
				(residents[index] as Dictionary).get(
					"socialState",
					{},
				) as Dictionary
			).get("job", ""),
		) == job:
			return index
	return -1



func _resident_identities(opening: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		result.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(
				(resident.get("attributes", {}) as Dictionary).get(
					"name",
					"",
				)
			),
		})
	return result



func _job_vacancy_matter_id(world: RefCounted) -> String:
	for value: Variant in world.call(
		"get_social_matter_summaries",
		false,
	) as Array:
		var matter := value as Dictionary
		if String(matter.get("kind", "")) == "job_vacancy":
			return String(matter.get("matter_id", ""))
	return ""



func _agent_matter(
	world: RefCounted,
	resident_id: String,
	matter_id: String,
) -> Dictionary:
	for value: Variant in world.call(
		"get_agent_social_matters",
		resident_id,
	) as Array:
		if String((value as Dictionary).get(
			"matter_id",
			"",
		)) == matter_id:
			return (value as Dictionary).duplicate(true)
	return {}



func _place_service_state(
	world: RefCounted,
	place_id: String,
) -> Dictionary:
	for value: Variant in world.call(
		"get_place_service_state_snapshots",
	) as Array:
		if String((value as Dictionary).get(
			"place_id",
			"",
		)) == place_id:
			return (value as Dictionary).duplicate(true)
	return {}



func _absolute_minute(time_value: Variant) -> int:
	var time := time_value as Dictionary
	var parts := String(time.get("clock", "00:00")).split(":")
	return (
		(int(time.get("day", 1)) - 1) * 1440
		+ int(parts[0]) * 60
		+ int(parts[1])
	)



func _scenario_occupation_natural_source() -> void:
	var world_data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(
		OPENING_PATH,
		world_data,
	) as Dictionary
	_expect_equal(
		opening_result.get("ok"),
		true,
		"十五职业自然来源检查可以加载开局",
	)
	if opening_result.get("ok") != true:
		return
	var opening := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	_assign_all_occupations(opening, world_data)
	var world: RefCounted = WORLD.new()
	var started := world.call("start", world_data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "十五职业自然来源 World 可以启动")
	if started.get("ok") != true:
		return
	_expect_equal(
		_selected_occupation_ids(opening, world_data).size(),
		15,
		"默认十五人覆盖十五种不同职业",
	)
	_expect_task(
		world,
		opening,
		"渔夫",
		"fishing.harvest",
		"fishing_conditions",
	)
	_expect_task(
		world,
		opening,
		"园艺师",
		"garden.care",
		"plant_state",
	)
	_expect_task(
		world,
		opening,
		"园艺师",
		"garden.harvest",
		"flowering_state",
	)
	_expect_task(
		world,
		opening,
		"食堂主理人",
		"food.production",
		"daily_baking_plan",
	)
	_expect_task(
		world,
		opening,
		"食堂主理人",
		"food.production",
		"meal_demand",
	)
	_expect_task(
		world,
		opening,
		"仓库管理员",
		"inventory.receive",
		"daily_inventory_plan",
	)
	_expect_task(
		world,
		opening,
		"小镇管理者",
		"civic.service",
		"public_matter",
	)
	_expect_task(
		world,
		opening,
		"工匠",
		"craft.production",
		"production_request",
	)
	_expect_task(
		world,
		opening,
		"邮差",
		"message.accept",
		"daily_postal_collection_plan",
	)
	_expect_task(
		world,
		opening,
		"咖啡店店员",
		"cafe.handoff",
		"daily_operation_plan",
	)
	_expect_task(
		world,
		opening,
		"草药医师",
		"care.treatment",
		"daily_operation_plan",
	)
	_expect_task(
		world,
		opening,
		"杂货店主",
		"retail.stock",
		"daily_operation_plan",
	)
	_expect_task(
		world,
		opening,
		"花店店主",
		"retail.sale",
		"daily_operation_plan",
	)
	_expect_no_task(
		world,
		opening,
		"咖啡店店员",
		"cafe.production",
		"stock_below_threshold",
		"基础咖啡不按零库存自然生成生产任务",
	)
	_expect_task(
		world,
		opening,
		"植物研究员",
		"research.observe",
		"abnormal_plant",
	)
	_expect_task(
		world,
		opening,
		"园艺师",
		"garden.harvest",
		"sample_request",
	)

	# Time is the only input here. No test task, action, resident position or
	# Agent decision is inserted. At 09:00 the ordinary daytime work plan makes
	# one real rehearsal task available to the musician.
	world.call("advance", 60.0)
	_expect_task(
		world,
		opening,
		"图书管理员",
		"library.assist",
		"daily_catalog_plan",
	)
	_expect_task(
		world,
		opening,
		"乐师",
		"music.rehearse",
		"personal_performance_plan",
	)
	_expect_task(
		world,
		opening,
		"乐师",
		"music.perform",
		"public_event",
	)
	_expect_market_customer_activities(world_data)
	world.call("stop")
	return
func _assign_all_occupations(
	opening: Dictionary,
	world_data: Dictionary,
) -> void:
	var residents := opening.get("residents", []) as Array
	var occupations := world_data.get("occupations", []) as Array
	_expect_equal(residents.size(), occupations.size(), "夹具居民数量覆盖十五职业")
	for index in mini(residents.size(), occupations.size()):
		var resident := residents[index] as Dictionary
		var occupation := occupations[index] as Dictionary
		var social := resident.get("socialState", {}) as Dictionary
		social["job"] = String(occupation.get("label", ""))
		social["workplace"] = String(
			occupation.get("primaryWorkplacePlace", ""),
		)



func _selected_occupation_ids(
	opening: Dictionary,
	world_data: Dictionary,
) -> Dictionary:
	var result := {}
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		var job := String(
			(resident.get("socialState", {}) as Dictionary).get(
				"job",
				"",
			),
		)
		for occupation_value: Variant in (
			world_data.get("occupations", []) as Array
		):
			var occupation := occupation_value as Dictionary
			if (
				String(occupation.get("label", "")) == job
				or (occupation.get("aliases", []) as Array).has(job)
			):
				result[String(
					occupation.get("occupationId", ""),
				)] = true
	return result



func _expect_task(
	world: RefCounted,
	opening: Dictionary,
	job: String,
	capability: String,
	source_kind: String,
) -> void:
	var resident_id := _resident_id_for_job(opening, job)
	_expect(not resident_id.is_empty(), "开局包含职业：%s" % job)
	for task_value: Variant in world.call(
		"get_work_tasks_for_resident",
		resident_id,
	) as Array:
		var task := task_value as Dictionary
		if (
			String(task.get("capability", "")) == capability
			and String(task.get("source_kind", "")) == source_kind
		):
			return
	_failures.append(
		"%s 没有由正式开局自然产生 %s/%s"
		% [job, capability, source_kind],
	)



func _expect_no_task(
	world: RefCounted,
	opening: Dictionary,
	job: String,
	capability: String,
	source_kind: String,
	message: String,
) -> void:
	var resident_id := _resident_id_for_job(opening, job)
	_expect(not resident_id.is_empty(), "开局包含职业：%s" % job)
	for task_value: Variant in world.call(
		"get_work_tasks_for_resident",
		resident_id,
	) as Array:
		var task := task_value as Dictionary
		if (
			String(task.get("capability", "")) == capability
			and String(task.get("source_kind", "")) == source_kind
		):
			_failures.append(message)
			return



func _resident_id_for_job(opening: Dictionary, job: String) -> String:
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		if String(
			(resident.get("socialState", {}) as Dictionary).get(
				"job",
				"",
			),
		) == job:
			return String(resident.get("residentId", ""))
	return ""



func _expect_market_customer_activities(world_data: Dictionary) -> void:
	var required := {
		"activity_market_buy_general_goods": false,
		"activity_market_buy_fish": false,
		"activity_market_buy_flowers": false,
	}
	var worker_positions := {}
	var visitor_positions := {}
	for slot_value: Variant in world_data.get("activitySlots", []) as Array:
		var slot := slot_value as Dictionary
		if String(slot.get("placeName", "")) != "独立市集":
			continue
		var activity_id := String(slot.get("activityId", ""))
		if required.has(activity_id):
			required[activity_id] = true
			for member_value: Variant in slot.get(
				"memberAnchors",
				[],
			) as Array:
				visitor_positions[str(
					(member_value as Dictionary).get("position", []),
				)] = true
		elif String(slot.get("role", "")) == "worker":
			for member_value: Variant in slot.get(
				"memberAnchors",
				[],
			) as Array:
				worker_positions[str(
					(member_value as Dictionary).get("position", []),
				)] = true
	for activity_id: String in required:
		_expect(
			bool(required[activity_id]),
			"市集提供真实顾客活动：%s" % activity_id,
		)
	for position_value: Variant in visitor_positions:
		_expect(
			not worker_positions.has(position_value),
			"市集顾客位不与店主工作位重叠：%s" % position_value,
		)



func _scenario_market_workplace() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(
		OPENING_PATH,
		data,
	) as Dictionary
	_expect_equal(
		opening_result.get("ok"),
		true,
		"市集工作检查可加载开局",
	)
	if opening_result.get("ok") != true:
		return
	var opening := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	var resident_id := "resident_he_yu_01"
	var resident_name := "何雨"
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		if String(resident.get("residentId", "")) != resident_id:
			continue
		var social_state := resident.get("socialState", {}) as Dictionary
		social_state["job"] = "花店店主"
		social_state["workplace"] = "独立市集"
		var world_state := resident.get("worldState", {}) as Dictionary
		world_state["place"] = "市集"
		world_state["spaceId"] = "town_outdoor"
		world_state["regionId"] = "outdoor_market_01"
		world_state["position"] = [4086, 2058]
		break
	var world: RefCounted = WORLD.new()
	world.connect("resident_activity_started", _on_activity_started)
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"花店工作地点 World 可启动",
	)
	var wake := _take_wake_market_workplace(world, resident_name)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			resident_name,
			_go_market_workplace(wake, "独立市集"),
		) as Dictionary,
		"花店店主能从室外市集进入独立市集",
	)
	_expect(
		_advance_until_action_clears(world, resident_name),
		"花店店主进入独立市集的路线能走完",
	)
	var indoor_state := world.call(
		"get_resident_state",
		resident_name,
	) as Dictionary
	_expect_equal(
		indoor_state.get("currentPlace"),
		"独立市集",
		"花店店主最终处于室内市集地点",
	)
	_expect_equal(
		indoor_state.get("spaceId"),
		"indoor_market_shop",
		"花店店主不再停留在室外地图",
	)
	_expect_equal(
		(
			world.call(
				"create_work_task",
				{
					"taskId": "market_arrange_flowers",
					"capability": "retail.arrange",
					"sourceKind": "display_change",
					"sourceRef": "north_flower_stall",
					"targets": [{
						"kind": "prop",
						"ref": "独立市集北侧花摊",
					}],
					"requestedResultKind": "bouquet_lot",
					"priority": 70,
				},
			) as Dictionary
		).get("ok"),
		true,
		"花摊有真实陈列任务",
	)
	wake = _take_wake_market_workplace(world, resident_name)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			resident_name,
			_use_prop(
				wake,
				"独立市集北侧花摊",
				"整理花束",
				"整理今天要卖的花束",
			),
		) as Dictionary,
		"花店店主能在室内开始整理花束",
	)
	var positions := {}
	_expect(
		_advance_routine_until_clear(world, resident_name, positions),
		"花店店主的室内工作过程能结束",
	)
	_expect(
		_started_activity_ids == ["activity_flower_arrange_bouquets"],
		"一次决定只整理花束，不会自动续选看摊，实际为 %s"
		% [_started_activity_ids],
	)
	_expect(
		positions.size() >= 1,
		"整理花束确实到达真实花摊位置，实际为 %s"
		% [positions.keys()],
	)
	_expect_equal(
		(
			world.call(
				"create_work_task",
				{
					"taskId": "market_watch_flower_stall",
					"capability": "retail.sale",
					"sourceKind": "customer_demand",
					"sourceRef": "south_flower_stall_customer",
					"targets": [{
						"kind": "prop",
						"ref": "独立市集南侧花摊",
					}],
					"requestedResultKind": "retail_transfer",
					"priority": 70,
				},
			) as Dictionary
		).get("ok"),
		true,
		"花摊有真实售卖任务",
	)
	wake = _take_wake_market_workplace(world, resident_name)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			resident_name,
			_use_prop(
				wake,
				"独立市集南侧花摊",
				"看顾花摊",
				"花束理好了，接着看顾摊位",
			),
		) as Dictionary,
		"花店店主重新判断后可以选择看顾另一处花摊",
	)
	var second_positions := {}
	_expect(
		_advance_routine_until_clear(
			world,
			resident_name,
			second_positions,
		),
		"重新决定后的看摊阶段能结束",
	)
	_expect_equal(
		_started_activity_ids,
		[
			"activity_flower_arrange_bouquets",
			"activity_flower_watch_stall",
		],
		"两个工作阶段来自两次居民决定",
	)
	_expect(
		second_positions.size() >= 1,
		"第二次决定到达另一处真实花摊位置",
	)
	world.call("stop")
	return
func _take_wake_market_workplace(world: RefCounted, resident_name: String) -> Dictionary:
	var requests := world.call(
		"take_pending_decision_requests",
		[resident_name],
	) as Array[Dictionary]
	if requests.is_empty():
		_failures.append("缺少 %s 的决定请求" % resident_name)
		return {}
	return (
		(requests[0].get("wakePacket", {}) as Dictionary).duplicate(true)
	)



func _go_market_workplace(wake: Dictionary, place: String) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-go-market" % decision_id,
			"type": "去",
			"place": place,
			"line": "去室内花摊开店",
		},
	}



func _use_prop(
	wake: Dictionary,
	prop: String,
	verb: String,
	line: String,
) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-%s" % [decision_id, verb],
			"type": "用道具",
			"prop": prop,
			"verb": verb,
			"line": line,
		},
	}



func _advance_until_action_clears(
	world: RefCounted,
	resident_name: String,
	maximum_minutes := 900,
) -> bool:
	for _minute in maximum_minutes:
		var state := world.call(
			"get_resident_state",
			resident_name,
		) as Dictionary
		if state.get("currentAction") == null:
			return true
		world.call("advance", 1.0)
	return false



func _advance_routine_until_clear(
	world: RefCounted,
	resident_name: String,
	positions: Dictionary,
	maximum_minutes := 180,
) -> bool:
	for _minute in maximum_minutes:
		var state := world.call(
			"get_resident_state",
			resident_name,
		) as Dictionary
		if state.get("currentAction") == null:
			return true
		var cue_value: Variant = state.get("activityCue")
		if (
			cue_value is Dictionary
			and String(
				(cue_value as Dictionary).get("phase", "")
			) == "performing"
		):
			var position := state.get("position", Vector2.ZERO) as Vector2
			positions["%d,%d" % [roundi(position.x), roundi(position.y)]] = true
		world.call("advance", 1.0)
	return false



func _on_activity_started(
	resident_id: String,
	event: Dictionary,
) -> void:
	if resident_id == "resident_he_yu_01":
		_started_activity_ids.append(String(event.get("activityId", "")))



func _expect_accepted(result: Dictionary, message: String) -> void:
	_expect_equal(
		result.get("status"),
		"accepted",
		"%s（%s）" % [message, result],
	)



func _scenario_staffing_runtime() -> void:
	var world_data := BUILDER.build_from_source(SOURCE_DIR)
	var runtime: RefCounted = STAFFING.new()
	_expect_ok(
		runtime.call("configure", world_data) as Dictionary,
		"staffing runtime configures from formal occupations",
	)
	var residents := {}
	var occupations := world_data.get("occupations", []) as Array
	for index: int in occupations.size():
		var occupation := occupations[index] as Dictionary
		residents["resident_staffing_%02d" % index] = {
			"socialState": {
				"job": String(occupation.get("label", "")),
			},
		}
	var covered := runtime.call("rebuild", residents) as Dictionary
	_expect_ok(covered, "one resident per occupation covers all posts")
	var covered_snapshot := covered.get("snapshot", {}) as Dictionary
	_expect_equal(
		(covered_snapshot.get("posts", []) as Array).size(),
		15,
		"staffing snapshot contains the fifteen formal posts",
	)
	_expect_equal(
		covered_snapshot.get("vacantPostIds"),
		[],
		"recommended staffing has no vacancy",
	)
	_expect_equal(
		covered_snapshot.get("duplicatePostIds"),
		[],
		"recommended staffing has no duplicate",
	)
	var grocer := runtime.call(
		"post_for_occupation",
		"occupation_grocer",
	) as Dictionary
	var flower_vendor := runtime.call(
		"post_for_occupation",
		"occupation_flower_vendor",
	) as Dictionary
	_expect_equal(
		grocer.get("physicalCapacity"),
		3,
		"grocer post sees three fixed market stalls",
	)
	_expect_equal(
		flower_vendor.get("physicalCapacity"),
		2,
		"flower-vendor post sees two fixed flower stalls",
	)

	var duplicated := residents.duplicate(true)
	var grocer_resident_id := ""
	var postal_resident_id := ""
	for resident_id_value: Variant in duplicated:
		var resident_id := String(resident_id_value)
		var job := String(
			(
				duplicated[resident_id].get(
					"socialState",
					{},
				) as Dictionary
			).get("job", ""),
		)
		if job == "杂货店主":
			grocer_resident_id = resident_id
		elif job == "邮差":
			postal_resident_id = resident_id
	_expect(not grocer_resident_id.is_empty(), "fixture contains grocer")
	_expect(not postal_resident_id.is_empty(), "fixture contains postal worker")
	if not grocer_resident_id.is_empty() and not postal_resident_id.is_empty():
		(
			duplicated[postal_resident_id].get(
				"socialState",
				{},
			) as Dictionary
		)["job"] = "杂货店主"
	var conflict := runtime.call("rebuild", duplicated) as Dictionary
	_expect_ok(conflict, "duplicates and vacancies remain valid world state")
	var conflict_snapshot := conflict.get("snapshot", {}) as Dictionary
	_expect_equal(
		(conflict_snapshot.get("vacantPostIds", []) as Array).size(),
		1,
		"one removed occupation creates one visible vacancy",
	)
	_expect_equal(
		(conflict_snapshot.get("duplicatePostIds", []) as Array).size(),
		1,
		"the repeated occupation creates one visible duplicate",
	)
	var duplicate_grocer := runtime.call(
		"post_for_occupation",
		"occupation_grocer",
	) as Dictionary
	var vacant_postal := runtime.call(
		"post_for_occupation",
		"occupation_postal_worker",
	) as Dictionary
	_expect_equal(
		(duplicate_grocer.get("assignedResidentIds", []) as Array).size(),
		2,
		"staffing runtime does not silently choose which duplicate must leave",
	)
	_expect_equal(
		(vacant_postal.get("assignedResidentIds", []) as Array).size(),
		0,
		"staffing runtime does not silently fill a vacancy",
	)
	_expect(
		not String(vacant_postal.get("vacancyEffect", "")).is_empty(),
		"vacant post exposes its service degradation consequence",
	)

	# 3c 依赖投影跳过:周期维护点边界用例
	var probe_runtime: RefCounted = STAFFING.new()
	_expect_ok(
		probe_runtime.call("configure", world_data) as Dictionary,
		"3c probe runtime configures",
	)
	var probe_residents := residents.duplicate(true)
	_expect_ok(
		probe_runtime.call(
			"rebuild",
			probe_residents,
			500,
		) as Dictionary,
		"3c baseline rebuild at minute 500",
	)
	var skipped := probe_runtime.call(
		"rebuild_if_dependencies_changed",
		probe_residents,
		530,
	) as Dictionary
	_expect(
		bool(skipped.get("skipped", false)),
		"unchanged inputs skip periodic rebuild",
	)
	_expect_equal(
		(skipped.get("snapshot", {}) as Dictionary).get("absoluteMinute"),
		530,
		"skipped maintenance backfills absoluteMinute",
	)
	_expect_equal(
		(probe_runtime.call("snapshot") as Dictionary).get("absoluteMinute"),
		530,
		"snapshot() reflects backfilled absoluteMinute",
	)
	var reordered := {}
	var reversed_ids := probe_residents.keys()
	reversed_ids.reverse()
	for resident_id_value: Variant in reversed_ids:
		reordered[resident_id_value] = probe_residents[resident_id_value]
	_expect(
		bool((probe_runtime.call(
			"rebuild_if_dependencies_changed",
			reordered,
			531,
		) as Dictionary).get("skipped", false)),
		"input collection order does not defeat skip",
	)
	var shift_pair := _find_shift_capable(probe_runtime)
	_expect(
		not shift_pair.is_empty(),
		"fixture offers a shift-capable pairing",
	)
	if not shift_pair.is_empty():
		_expect_ok(
			probe_runtime.call(
				"create_arrangement",
				String(shift_pair.get("residentId", "")),
				String(shift_pair.get("occupationId", "")),
				"shift",
				531,
				540,
				600,
			) as Dictionary,
			"3c shift arrangement 09:00-10:00 created",
		)
		_expect(
			not bool((probe_runtime.call(
				"rebuild_if_dependencies_changed",
				probe_residents,
				540,
			) as Dictionary).get("skipped", false)),
			"new arrangement forces rebuild",
		)
		_expect(
			bool((probe_runtime.call(
				"rebuild_if_dependencies_changed",
				probe_residents,
				570,
			) as Dictionary).get("skipped", false)),
			"09:30 within shift window skips",
		)
		_expect(
			not bool((probe_runtime.call(
				"rebuild_if_dependencies_changed",
				probe_residents,
				600,
			) as Dictionary).get("skipped", false)),
			"10:00 shift expiry flips projection and forces rebuild",
		)
	var leave_residents := probe_residents.duplicate(true)
	(leave_residents[grocer_resident_id] as Dictionary)["attendanceState"] = {
		"status": "on_leave",
		"untilMinute": 660,
	}
	_expect(
		not bool((probe_runtime.call(
			"rebuild_if_dependencies_changed",
			leave_residents,
			630,
		) as Dictionary).get("skipped", false)),
		"on_leave change forces rebuild",
	)
	_expect(
		bool((probe_runtime.call(
			"rebuild_if_dependencies_changed",
			leave_residents,
			645,
		) as Dictionary).get("skipped", false)),
		"mid-leave maintenance skips",
	)
	_expect(
		not bool((probe_runtime.call(
			"rebuild_if_dependencies_changed",
			leave_residents,
			660,
		) as Dictionary).get("skipped", false)),
		"leave untilMinute expiry forces rebuild",
	)
	return
func _find_shift_capable(runtime: RefCounted) -> Dictionary:
	var snapshot := runtime.call("snapshot") as Dictionary
	for post_value: Variant in snapshot.get("posts", []) as Array:
		var post := post_value as Dictionary
		var assigned := post.get("assignedResidentIds", []) as Array
		if assigned.is_empty():
			continue
		var occupation_id := String(post.get("occupationId", ""))
		var resident_id := String(assigned[0])
		var modes: Array = runtime.call(
			"allowed_assignment_modes",
			resident_id,
			occupation_id,
		)
		if modes.has("shift"):
			return {
				"residentId": resident_id,
				"occupationId": occupation_id,
			}
	return {}



func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(
		bool(result.get("ok", false)),
		"%s: %s" % [message, result],
	)



func _scenario_staffing_arrangement_runtime() -> void:
	var world_data := BUILDER.build_from_source(SOURCE_DIR)
	var runtime: RefCounted = STAFFING.new()
	_expect_ok_staffing_arrangement_runtime(
		runtime.call("configure", world_data) as Dictionary,
		"岗位安排运行时可以配置",
	)
	var residents := {}
	var resident_by_occupation := {}
	for index: int in (
		world_data.get("occupations", []) as Array
	).size():
		var occupation := (
			world_data.get("occupations", []) as Array
		)[index] as Dictionary
		var occupation_id := String(
			occupation.get("occupationId", ""),
		)
		var resident_id := "resident_arrangement_%02d" % index
		residents[resident_id] = {
			"socialState": {
				"job": String(occupation.get("label", "")),
			},
		}
		resident_by_occupation[occupation_id] = resident_id
	_expect_ok_staffing_arrangement_runtime(
		runtime.call("rebuild", residents, 600) as Dictionary,
		"开局职业形成初始资格",
	)
	var cafe_id := String(
		resident_by_occupation.get("occupation_cafe_worker", ""),
	)
	_expect_equal(
		runtime.call(
			"allowed_assignment_modes",
			cafe_id,
			"occupation_clinic_practitioner",
		),
		["part_time"],
		"没有诊疗资格的居民只能作为不覆盖岗位的帮工",
	)
	var clinic_help := runtime.call(
		"create_arrangement",
		cafe_id,
		"occupation_clinic_practitioner",
		"part_time",
		600,
	) as Dictionary
	_expect_ok_staffing_arrangement_runtime(clinic_help, "无诊疗资格居民可以自愿帮工")
	_expect_equal(
		(
			clinic_help.get("arrangement", {}) as Dictionary
		).get("coversPost"),
		false,
		"帮工不会冒充诊疗负责人",
	)

	var botanist_id := String(
		resident_by_occupation.get("occupation_botanist", ""),
	)
	_expect_equal(
		runtime.call(
			"allowed_assignment_modes",
			botanist_id,
			"occupation_musician",
		),
		["trial"],
		"没有正式演出记录时只能先试演",
	)
	var trial := runtime.call(
		"create_arrangement",
		botanist_id,
		"occupation_musician",
		"trial",
		600,
	) as Dictionary
	_expect_ok_staffing_arrangement_runtime(trial, "居民可以建立乐师试岗")
	_expect(
		(
			runtime.call(
				"active_assignment_occupation_ids",
				botanist_id,
				600,
			) as Array
		).has("occupation_musician"),
		"表演试岗授权实际演出活动",
	)
	var trial_result := runtime.call(
		"record_trial_result",
		String(
			(trial.get("arrangement", {}) as Dictionary).get(
				"arrangementId",
				"",
			),
		),
		true,
		{"performanceRecordId": "performance-test-001"},
		640,
	) as Dictionary
	_expect_ok_staffing_arrangement_runtime(trial_result, "实际演出结果可以完成试岗")
	_expect_equal(
		runtime.call(
			"allowed_assignment_modes",
			botanist_id,
			"occupation_musician",
		),
		["transfer", "part_time", "shift"],
		"试演成功后才形成乐师资格",
	)

	var postal_id := String(
		resident_by_occupation.get("occupation_postal_worker", ""),
	)
	var grocer_id := String(
		resident_by_occupation.get("occupation_grocer", ""),
	)
	(
		residents[postal_id].get("socialState", {}) as Dictionary
	)["job"] = "杂货店主"
	_expect_ok_staffing_arrangement_runtime(
		runtime.call("rebuild", residents, 600) as Dictionary,
		"重复杂货岗位形成邮差空缺",
	)
	var morning_shift := runtime.call(
		"create_arrangement",
		grocer_id,
		"occupation_postal_worker",
		"shift",
		600,
		480,
		960,
	) as Dictionary
	_expect_ok_staffing_arrangement_runtime(morning_shift, "直接岗位可以协商上午轮班")
	var morning_snapshot := runtime.call(
		"rebuild",
		residents,
		600,
	) as Dictionary
	_expect_equal(
		(
			runtime.call(
				"post_for_occupation",
				"occupation_postal_worker",
			) as Dictionary
		).get("status"),
		"covered_by_arrangement",
		"轮班时段内岗位由真实轮班安排覆盖",
	)
	_expect(
		(
			(
				morning_snapshot.get("snapshot", {}) as Dictionary
			).get("vacantPostIds", []) as Array
		).is_empty(),
		"轮班时段内邮差岗位不再报告空缺",
	)
	runtime.call("rebuild", residents, 1100)
	_expect_equal(
		(
			runtime.call(
				"post_for_occupation",
				"occupation_postal_worker",
			) as Dictionary
		).get("status"),
		"vacant",
		"轮班时段外岗位重新显示真实空缺",
	)

	var persistent := runtime.call(
		"persistent_snapshot",
	) as Dictionary
	var restored: RefCounted = STAFFING.new()
	_expect_ok_staffing_arrangement_runtime(
		restored.call("configure", world_data) as Dictionary,
		"恢复运行时可以配置",
	)
	_expect_ok_staffing_arrangement_runtime(
		restored.call(
			"restore_persistent_snapshot",
			persistent,
			residents,
			600,
		) as Dictionary,
		"资格、兼职、轮班和试岗记录可以恢复",
	)
	_expect(
		bool(restored.call(
			"is_qualified",
			botanist_id,
			"occupation_musician",
		)),
		"恢复后保留由实际表现形成的资格",
	)
	return
func _expect_ok_staffing_arrangement_runtime(result: Dictionary, message: String) -> void:
	_expect(
		result.get("ok") == true,
		"%s：%s" % [message, result],
	)
