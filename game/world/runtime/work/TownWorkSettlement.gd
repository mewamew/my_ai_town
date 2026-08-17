class_name TownWorkSettlement
extends RefCounted


const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)


const PRODUCTION_TASK_COORDINATION_RUNTIME := preload(
	"res://world/runtime/work/TownProductionTaskCoordinationRuntime.gd"
)


const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const RESIDENT_MESSAGE_POLICY := preload(
	"res://world/runtime/social/TownResidentMessagePolicy.gd"
)
const RESIDENT_MESSAGE_CONTENT := preload(
	"res://world/runtime/social/TownResidentMessageContent.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const OCCUPATION_SERVICE_DEFINITION := preload(
	"res://world/runtime/work/TownOccupationServiceDefinition.gd"
)
const PERFORMANCE_AUDIENCE_POLICY := preload(
	"res://world/runtime/work/TownPerformanceAudiencePolicy.gd"
)
const PLACE_SERVICE_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownPlaceServiceCommandRuntime.gd"
)
const SOCIAL_MATTER_COMMAND_RUNTIME := preload(
	"res://world/runtime/social/TownSocialMatterCommandRuntime.gd"
)
const POSTAL_MESSAGE_RUNTIME := preload(
	"res://world/runtime/social/TownPostalMessageRuntime.gd"
)

# 活动完成后的工单结算域(自 TownWorldRuntime 下沉)。world 为世界运行时实例;
# 结算是冷路径(每次活动完成一回),子 runtime 与目录 helper 统一经 world 动态访问,
# 恢复/重开局替换子 runtime 后无需重新绑定。

static func refresh_staffing_after_attendance_change(world) -> void:
	var staffing: Variant = world.work_domain.staffing
	if staffing == null or world.environment() == null:
		return
	staffing.rebuild(
		world.residents(),
		int(world.environment().get_absolute_minute()),
	)
	PLACE_SERVICE_COMMAND_RUNTIME.refresh_staffing(world)
	world.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.sync_staffing_matters(world)

# 工单结算分派:一次解析绑定任务,按旧 16 连调的顺序做首配规则分派。
# 规则与各 handler 自身门槛完全一致,handler 内部检查全部保留;不依赖绑定的
# 场所服务/公告栏/取件保持原顺位无条件调用,段间重取任务与旧的逐个重查等价。
static func settle_completed_activity(
	world,
	resident_id: String,
	execution: Dictionary,
) -> void:
	var activity_id := String(execution.get("activityId", ""))
	var task := _bound_settlement_task(world, resident_id, execution)
	if (
		activity_id == "activity_botanist_record_plants"
		and String(task.get("capability", "")) == "research.handoff"
	):
		# 旧序特例:植物研究交接不受 in_progress 门槛约束。
		_complete_research_booklet_work_task(world, resident_id, task)
	elif _settlement_task_in_progress(world, task) and not (
		world.work_domain.services.request(
			String(task.get("sourceRef", "")),
		) as Dictionary
	).is_empty():
		_complete_occupation_service_work_task_before_release(world,
			resident_id,
			execution,
			task,
		)
	_complete_place_service_work_task_before_release(world,
		resident_id,
		execution,
	)
	task = _bound_settlement_task(world, resident_id, execution)
	if _settlement_task_in_progress(world, task):
		var capability := String(task.get("capability", ""))
		var source_kind := String(task.get("sourceKind", ""))
		if (
			activity_id in CONTENT_CATALOG.WAREHOUSE_SETTLEMENT_ACTIVITIES
			and capability == "inventory.release"
			and source_kind == "inventory_request"
		):
			_complete_cargo_release_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
		elif (
			source_kind in ["incoming_cargo", "flower_cargo"]
			and capability in [
				"inventory.receive",
				"retail.receive",
				"cafe.production",
				"food.production",
				"care.treatment",
				"craft.production",
				"library.accession",
			]
		):
			_complete_cargo_receipt_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
		elif activity_id in CONTENT_CATALOG.PRODUCTION_SETTLEMENT_ACTIVITIES:
			_complete_production_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
		elif activity_id in CONTENT_CATALOG.BOTANIST_SETTLEMENT_ACTIVITIES:
			_complete_plant_research_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
		elif (
			activity_id in CONTENT_CATALOG.WORKSHOP_SETTLEMENT_ACTIVITIES
			and capability == "craft.production"
			and source_kind == "production_request"
		):
			_complete_craft_production_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
	_complete_natural_bulletin_work(world,
		resident_id,
		execution,
	)
	task = _bound_settlement_task(world, resident_id, execution)
	if _settlement_task_in_progress(world, task):
		var capability := String(task.get("capability", ""))
		var source_kind := String(task.get("sourceKind", ""))
		if _matches_recurring_occupation_settlement(world,
			activity_id,
			capability,
			source_kind,
			task,
		):
			_complete_recurring_occupation_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
		elif (
			activity_id == "activity_musician_rehearse"
			and capability == "music.rehearse"
			and source_kind == "personal_performance_plan"
		):
			_complete_music_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
		elif (
			activity_id == "activity_library_shelve_returns"
			and capability == "library.accession"
			and source_kind == "research_handoff"
		):
			_complete_research_accession_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
		elif (
			activity_id in CONTENT_CATALOG.BAKER_SETTLEMENT_ACTIVITIES
			and capability == "food.production"
			and source_kind in ["daily_baking_plan", "meal_demand"]
		):
			_complete_food_production_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
		elif (
			activity_id == "activity_flower_arrange_bouquets"
			and capability == "retail.arrange"
			and source_kind == "display_change"
		):
			_complete_retail_preparation_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
		elif (
			not source_kind.is_empty()
			and source_kind == String(CONTENT_CATALOG.FACILITY_CLEANUP_SOURCE_BY_ACTIVITY.get(activity_id, ""))
		):
			_complete_facility_cleanup_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
		elif (
			not capability.is_empty()
			and capability == String(CONTENT_CATALOG.POSTAL_CAPABILITY_BY_ACTIVITY.get(activity_id, ""))
		):
			_complete_postal_process_work_task_before_release(world,
				resident_id,
				execution,
				task,
			)
	_complete_repair_pickup_from_visitor(world,
		resident_id,
		execution,
	)
	_record_equipment_wear_from_activity(world, execution)
	_record_facility_use_from_activity(world,
		resident_id,
		execution,
	)


static func _bound_settlement_task(
	world,
	resident_id: String,
	execution: Dictionary,
) -> Dictionary:
	var binding_key: String = world.activity_work_task_bindings.resolved_key(
		resident_id,
		String(execution.get("actionId", "")),
	)
	return world.work_domain.tasks.task(
		world.activity_work_task_bindings.task_id_for_key(String(binding_key)),
	) as Dictionary


static func _settlement_task_in_progress(_world, task: Dictionary) -> bool:
	return not task.is_empty() and String(task.get("state", "")) == "in_progress"


# 与 _complete_recurring_occupation_work_task_before_release 各分支门槛一一对应;
# 分支自身的深层校验仍在 handler 内执行。
static func _matches_recurring_occupation_settlement(
	world,
	activity_id: String,
	capability: String,
	source_kind: String,
	task: Dictionary,
) -> bool:
	if (
		capability == "message.accept"
		and source_kind == "daily_postal_collection_plan"
		and activity_id == "activity_postal_collect_outgoing_mail"
	):
		return true
	if source_kind == "daily_operation_plan":
		return true
	if (
		capability == "library.assist"
		and source_kind in ["daily_catalog_plan", "catalog_mismatch"]
		and activity_id == "activity_library_staff_checkout"
	):
		return true
	if (
		activity_id in [
			"activity_town_hall_manage_records",
			"activity_town_hall_process_paperwork",
		]
		and (
			(
				capability == "civic.service"
				and source_kind in [
					"resident_request",
					"place_service_change",
					"staffing_matter",
					"public_matter",
				]
			)
			or (
				capability == "staffing.coordinate"
				and source_kind == "staffing_matter"
			)
		)
	):
		return true
	if (
		capability == "food.production"
		and source_kind == "meal_demand"
		and String(task.get("sourceRef", "")).begins_with("meal-period:")
		and activity_id == "activity_dining_prepare_meal"
	):
		return true
	return (
		capability == "inventory.receive"
		and source_kind in [
			"daily_inventory_plan",
			"inventory_request",
			"inventory_discrepancy",
		]
		and activity_id == "activity_warehouse_check_manifest"
	)


static func _complete_place_service_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
) -> void:
	var place_id := String(execution.get("placeId", ""))
	var state: Dictionary = world.work_domain.place_services.state(place_id)
	if (
		state.is_empty()
		or String(execution.get("activityId", ""))
		!= String(state.get("helper_activity_id", ""))
		or (state.get("pending_request_ids", []) as Array).is_empty()
	):
		return
	var request_id := String(
		(state.get("pending_request_ids", []) as Array)[0],
	)
	if not (
		world.work_domain.services.request(request_id) as Dictionary
	).is_empty():
		return
	_complete_bound_place_service_work_task(world,
		resident_id,
		execution,
		place_id,
		request_id,
	)


static func _complete_occupation_service_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	var task_id := String(task.get("taskId", ""))
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
	):
		return
	var request_id := String(task.get("sourceRef", ""))
	var request := world.work_domain.services.request(
		request_id,
	) as Dictionary
	if request.is_empty():
		return
	var place_id := String(request.get("placeId", ""))
	if String(execution.get("placeId", "")) != place_id:
		return
	if (
		ACTION_SUPPORT.occupation_service_request_requires_presence(request)
		and not world.work_domain.work_task_is_currently_available(
			task,
			world.residents(),
		)
	):
		var wait_reason := "请求人尚未到达服务地点"
		world.work_domain.services.mark_waiting(
			request_id,
			wait_reason,
		)
		world.work_domain.tasks.release_task(
			String(task.get("taskId", "")),
			resident_id,
			int(task.get("revision", 0)),
			wait_reason,
		)
		return
	var kind := String(request.get("kind", ""))
	var requester_id := String(
		request.get("requesterResidentId", ""),
	)
	var now := int(world._environment.get_absolute_minute())
	var activity_id := String(execution.get("activityId", ""))
	if kind == "cafe_order" and String(request.get("itemId", "")) == (
		CONTENT_CATALOG.ITEM_BREWED_COFFEE
	):
		var process_stage := String(task.get("processStage", "ready"))
		if (
			activity_id == "activity_cafe_brew_coffee"
			and process_stage == "awaiting_brew"
		):
			var process_facts := (
				task.get("processFacts", {}) as Dictionary
			).duplicate(true)
			process_facts["brewedAtMinute"] = now
			process_facts["brewedByResidentId"] = resident_id
			process_facts["nextActivityId"] = (
				"activity_cafe_receive_guests"
			)
			world.work_domain.tasks.advance_process_stage(
				String(task.get("taskId", "")),
				resident_id,
				int(task.get("revision", 0)),
				"ready_handoff",
				process_facts,
			)
			return
		if (
			activity_id != "activity_cafe_receive_guests"
			or process_stage != "ready_handoff"
		):
			return
	var outcome: Dictionary = {}
	var domain_result: Dictionary = {}
	var follow_up_created := false
	match kind:
		"clinic":
			if String(task.get("capability", "")) == "care.consult":
				var clinic_context := (
					request.get("context", {}) as Dictionary
				).duplicate(true)
				var research_record_id := String(
					clinic_context.get("researchRecordId", ""),
				).strip_edges()
				var research_booklet_used := false
				if not research_record_id.is_empty():
					if int(world.work_domain.cargo.inventory_quantity(
						CONTENT_CATALOG.PLACE_CLINIC,
						CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
					)) <= 0:
						world.work_domain.services.mark_waiting(
							request_id,
							"所需研究小册子尚未送达诊所",
						)
						PRODUCTION_TASK_COORDINATION_RUNTIME.sync_specialty_service_demand(
							world,
							kind,
							CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
							request_id,
							now,
						)
						return
					var booklet_change := world.work_domain.cargo.apply_inventory_recipe(
						CONTENT_CATALOG.PLACE_CLINIC,
						{CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET: 1},
						{},
					) as Dictionary
					if booklet_change.get("ok") != true:
						return
					research_booklet_used = true
				var is_follow_up := bool(
					clinic_context.get("generatedFromFollowUp", false),
				)
				var patient := world.resident_registry.records.get(
					requester_id,
					{},
				) as Dictionary
				var body := (
					patient.get("body", {}) as Dictionary
				).duplicate(true)
				var complaint := String(
					request.get("subjectRef", ""),
				)
				var needs_medicine : Variant = (
					false
					if is_follow_up
					else world.CLINIC_SERVICE_COORDINATION_RUNTIME.request_needs_basic_care(world,
						requester_id,
						clinic_context,
					)
				)
				var medical_interview := (
					clinic_context.get("medicalInterview", {}) as Dictionary
				)
				outcome = {
					"kind": "care_outcome" if is_follow_up else "care_observation",
					"patientResidentId": requester_id,
					"complaint": complaint,
					"observedBody": body,
					"advice": (
						"已经完成复诊，继续按观察结果安排日常活动"
						if is_follow_up
						else (
						"需要配取基础药品并继续观察"
						if needs_medicine
						else "先休息、进食或补充睡眠，不宣称已经治愈"
						)
					),
					"medicineNeeded": needs_medicine,
					"researchRecordId": research_record_id,
					"researchBookletUsed": research_booklet_used,
					"interviewStatus": String(
						medical_interview.get("status", ""),
					),
					"interviewConversationId": String(
						medical_interview.get("conversationId", ""),
					),
					"patientResponseKind": String(
						medical_interview.get("patientResponseKind", ""),
					),
					"status": "follow_up_completed" if is_follow_up else "observed",
				}
				if needs_medicine:
					world.work_domain.services.record_progress(
						request_id,
						outcome,
					)
					var follow_up : Variant = world.work_domain.create_clinic_treatment_task(
						request,
						now,
					)
					if follow_up.get("ok") != true:
						return
					world.work_domain.services.attach_follow_up_task(
						request_id,
						String(
							(
								follow_up.get(
									"task",
									{},
								) as Dictionary
							).get("taskId", ""),
						),
					)
					follow_up_created = true
					world._bump_world_revision()
					for candidate_id: String in world.resident_registry.order:
						if world.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.primary_id(world,
							world.resident_registry.records.get(
								candidate_id,
								{},
							) as Dictionary,
						) == "occupation_clinic_practitioner":
							world._schedule_decision(candidate_id, true)
				else:
					domain_result = world.work_domain.services.complete_request(
						request_id,
						resident_id,
						now,
						outcome,
					) as Dictionary
					if is_follow_up and domain_result.get("ok") == true:
						world.work_domain.services.resolve_follow_up(
							String(clinic_context.get("followUpId", "")),
							now,
						)
			elif String(task.get("capability", "")) == "care.treatment":
				var conflict_treatment_context := request.get(
					"context",
					{},
				) as Dictionary
				if bool(conflict_treatment_context.get("generatedFromConflictInjury", false)):
					var treatment_started := world.CLINIC_SERVICE_COORDINATION_RUNTIME.begin_conflict_injury_treatment(world,
						requester_id,
						CONTENT_CATALOG.PLACE_CLINIC,
					) as Dictionary
					if treatment_started.get("ok") != true:
						return
					outcome = {
						"kind": "conflict_care_outcome",
						"patientResidentId": requester_id,
						"complaint": String(request.get("subjectRef", "")),
						"status": "conflict_treatment_started",
						"claim": "已经开始处理冲突造成的伤势，尚未痊愈",
					}
				else:
					var follow_up_result := world.work_domain.services.schedule_follow_up(
						request_id,
						requester_id,
						String(request.get("subjectRef", "身体不适")),
						now + 1440,
						now,
					) as Dictionary
					if follow_up_result.get("ok") != true:
						return
					var scheduled_follow_up := follow_up_result.get(
						"followUp",
						{},
					) as Dictionary
					outcome = {
						"kind": "care_outcome",
						"patientResidentId": requester_id,
						"complaint": String(
							request.get("subjectRef", ""),
						),
						"medicineItemId": "basic_medicine",
						"medicineQuantity": 1,
						"supplyMode": "base_always_available",
						"status": "treated_follow_up_needed",
						"followUpId": String(
							scheduled_follow_up.get("followUpId", ""),
						),
						"followUpDueAtMinute": int(
							scheduled_follow_up.get("dueAtMinute", now + 1440),
						),
						"claim": "已经配药，但不直接宣称痊愈",
					}
				domain_result = world.work_domain.services.complete_request(
					request_id,
					resident_id,
					now,
					outcome,
				) as Dictionary
		"library_loan":
			domain_result = world.work_domain.services.checkout_book(
				request_id,
				resident_id,
				now,
			) as Dictionary
			if domain_result.get("ok") == true:
				outcome = (
					(
						domain_result.get("request", {}) as Dictionary
					).get("outcome", {}) as Dictionary
				).duplicate(true)
			else:
				world.work_domain.services.mark_waiting(
					request_id,
					"所选书籍当前已经借出",
				)
				return
		"library_return":
			domain_result = world.work_domain.services.return_book(
				request_id,
				resident_id,
				now,
			) as Dictionary
			if domain_result.get("ok") == true:
				outcome = (
					(
						domain_result.get("request", {}) as Dictionary
					).get("outcome", {}) as Dictionary
				).duplicate(true)
			else:
				return
		"library_assist":
			outcome = {
				"kind": "catalog_state_change",
				"requesterResidentId": requester_id,
				"query": String(request.get("subjectRef", "查找资料")),
				"assistedByResidentId": resident_id,
				"completedAtMinute": now,
			}
			domain_result = world.work_domain.services.complete_request(
				request_id,
				resident_id,
				now,
				outcome,
			) as Dictionary
		"civic_request":
			outcome = {
				"kind": "civic_case_update",
				"requesterResidentId": requester_id,
				"subject": String(request.get("subjectRef", "日常镇务")),
				"status": "processed",
				"handledByResidentId": resident_id,
				"completedAtMinute": now,
			}
			domain_result = world.work_domain.services.complete_request(
				request_id,
				resident_id,
				now,
				outcome,
			) as Dictionary
			if domain_result.get("ok") == true:
				RESIDENT_MESSAGE_POLICY.send(
					world,
					RESIDENT_MESSAGE_CONTENT.civic_completion(
						resident_id,
						requester_id,
						request_id,
					),
				)
		"repair":
			var repair_context := (
				request.get("context", {}) as Dictionary
			).duplicate(true)
			var complete_on_repair := bool(
				repair_context.get("completeOnRepair", false),
			)
			var crafted_part_used := false
			if (
				complete_on_repair
				and int(world.work_domain.cargo.inventory_quantity(
					CONTENT_CATALOG.PLACE_WAREHOUSE,
					"crafted_item",
				)) > 0
			):
				var part_change := world.work_domain.cargo.apply_inventory_recipe(
					CONTENT_CATALOG.PLACE_WAREHOUSE,
					{"crafted_item": 1},
					{},
				) as Dictionary
				crafted_part_used = part_change.get("ok") == true
			outcome = {
				"kind": "repair_outcome",
				"subjectRef": String(request.get("subjectRef", "")),
				"propName": String(repair_context.get("propName", "")),
				"placeId": String(repair_context.get("placeId", "")),
				"materialItemId": "lumber",
				"materialQuantity": 1,
				"supplyMode": (
					"crafted_specialty_with_base_fallback"
					if crafted_part_used
					else "base_always_available"
				),
				"craftedPartUsed": crafted_part_used,
				"status": "repaired" if complete_on_repair else "ready_for_pickup",
				"deliveredToRequester": complete_on_repair,
				"repairedByResidentId": resident_id,
				"readyAtMinute": now,
			}
			if complete_on_repair:
				var equipment_result := world.work_domain.services.resolve_equipment_fault(
					String(request.get("subjectRef", "")),
					resident_id,
					now,
				) as Dictionary
				if equipment_result.get("ok") != true:
					return
				domain_result = world.work_domain.services.complete_request(
					request_id,
					resident_id,
					now,
					outcome,
				) as Dictionary
			else:
				domain_result = world.work_domain.services.record_progress(
					request_id,
					outcome,
				) as Dictionary
		"dining_order", "cafe_order", "grocer_sale", "flower_sale":
			if (
				kind == "dining_order"
				and not world.work_domain.dining_request_meal_is_ready(request)
			):
				PRODUCTION_TASK_COORDINATION_RUNTIME.sync_meal_period(world, now)
				world.record_place_service_request(place_id, request_id, false)
				world.work_domain.services.mark_waiting(
					request_id,
					(
						"食堂当前不在供餐时间"
						if world.work_domain.meal_period_for_minute(now).is_empty()
						else (
							"当前餐次尚未开始供餐"
							if not world.work_domain.meal_service_is_open(now)
							else "当前餐次尚未完成备餐"
						)
					),
				)
				return
			var item_id := String(request.get("itemId", ""))
			if not OCCUPATION_SERVICE_DEFINITION.item_allowed(kind, item_id):
				return
			var specialty_cargo_used := bool(world.work_domain.cargo.is_specialty_cargo_item(
				item_id,
			))
			var service_context := (
				request.get("context", {}) as Dictionary
			).duplicate(true)
			var delivery_requested := (
				kind == "flower_sale"
				and bool(service_context.get("deliveryRequested", false))
				and not String(
					service_context.get("destinationPlaceId", ""),
				).is_empty()
			)
			var delivery_lot_id := ""
			if specialty_cargo_used:
				var owns_preorder_reservation := (
					String(service_context.get("customerServiceMode", ""))
					== "preorder"
					and int(service_context.get(
						"preorderReservedQuantity",
						0,
					)) > 0
				)
				var available_quantity : Variant = (
					int(world.work_domain.cargo.inventory_quantity(
						place_id,
						item_id,
					))
					if owns_preorder_reservation
					else world.work_domain.unreserved_preorder_inventory_quantity(
						place_id,
						item_id,
					)
				)
				if available_quantity <= 0:
					world.work_domain.services.mark_waiting(
						request_id,
						"%s特色货批尚未到达" % item_id,
					)
					PRODUCTION_TASK_COORDINATION_RUNTIME.sync_specialty_service_demand(
						world,
						kind,
						item_id,
						request_id,
						now,
					)
					return
				if delivery_requested:
					var delivery_result : Variant = world.create_cargo_lot({
						"itemId": item_id,
						"quantity": 1,
						"sourcePlaceId": place_id,
						"destinationPlaceId": String(
							service_context.get("destinationPlaceId", ""),
						),
						"createdAtMinute": now,
						"priority": CONTENT_CATALOG.TASK_PRIORITY["service_result_delivery_lot"],
					})
					if delivery_result.get("ok") != true:
						return
					delivery_lot_id = String(
						(delivery_result.get("lot", {}) as Dictionary).get(
							"lotId",
							"",
						),
					)
				else:
					var service_inputs := {}
					service_inputs[item_id] = 1
					var stock_change := world.work_domain.cargo.apply_inventory_recipe(
						place_id,
						service_inputs,
						{},
					) as Dictionary
					if stock_change.get("ok") != true:
						return
			outcome = {
				"kind": (
					"meal_handoff"
					if kind == "dining_order"
					else (
						"order_handoff"
						if kind == "cafe_order"
						else "retail_transfer"
					)
				),
				"customerResidentId": requester_id,
				"itemId": item_id,
				"quantity": 1,
				"stockDecremented": specialty_cargo_used,
				"deliveryRequested": delivery_requested,
				"deliveryLotId": delivery_lot_id,
				"destinationPlaceId": String(
					service_context.get("destinationPlaceId", ""),
				) if delivery_requested else "",
				"supplyMode": (
					"specialty_cargo"
					if specialty_cargo_used
					else "base_always_available"
				),
			}
			if kind == "dining_order":
				outcome["serviceMode"] = "counter_batch"
				outcome["batchCapacity"] = DINING_SERVICE.BATCH_SIZE
			world.PLACE_SERVICE_COMMAND_RUNTIME.apply_consumed_item(world,
				requester_id,
				item_id,
			)
			domain_result = world.work_domain.services.complete_request(
				request_id,
				resident_id,
				now,
				outcome,
			) as Dictionary
			if domain_result.get("ok") == true:
				var meal_period_ref := String(
					(request.get("context", {}) as Dictionary).get(
						"mealPeriodRef",
						"",
					),
				)
				if meal_period_ref.is_empty():
					meal_period_ref = world.work_domain.meal_period_source_ref(
						int(request.get("createdAtMinute", -1)),
					)
				if not meal_period_ref.is_empty():
					world.work_domain.services.mark_dining_order_completed_for_resident_meal_period(
						requester_id,
						meal_period_ref,
					)
		"performance":
			var residents: Dictionary = world.residents()
			var present_resident_ids: Array[String] = []
			for candidate_id: String in world.resident_order():
				if world.resident_is_present(
					residents.get(candidate_id, {}) as Dictionary,
				):
					present_resident_ids.append(candidate_id)
			var audience_ids := PERFORMANCE_AUDIENCE_POLICY.audience_ids(
				resident_id,
				place_id,
				int(
					(request.get("context", {}) as Dictionary).get(
						"dayIndex",
						-1,
					),
				),
				residents,
				world.resident_order(),
				present_resident_ids,
			)
			if audience_ids.is_empty():
				world.work_domain.services.mark_waiting(
					request_id,
					"现场还没有实际听众",
				)
				return
			outcome = {
				"kind": "performance_record",
				"program": String(request.get("subjectRef", "")),
				"performerResidentId": resident_id,
				"audienceResidentIds": audience_ids,
				"audienceCount": audience_ids.size(),
				"audienceAreaId": "outdoor_plaza_01",
			}
			domain_result = world.work_domain.services.complete_request(
				request_id,
				resident_id,
				now,
				outcome,
			) as Dictionary
			if domain_result.get("ok") == true:
				var performance_day_index := int(
					(request.get("context", {}) as Dictionary).get(
						"dayIndex",
						-1,
					),
				)
				world.PERFORMANCE_SERVICE_RUNTIME.finish_listener_waits(world,
					performance_day_index,
					audience_ids,
				)
				world.PRIVATE_MESSAGE_DELIVERY_RUNTIME.cancel_for_source(world,
					"performance-event:%d" % performance_day_index,
					"演出已经结束",
				)
				world.PERFORMANCE_SERVICE_RUNTIME.close_invitation_sources(world,
					performance_day_index,
					"演出已经结束",
				)
				world.PLACE_SERVICE_COMMAND_RUNTIME.record_staffing_trial(world,
					resident_id,
					"occupation_musician",
					outcome,
				)
	if outcome.is_empty():
		return
	var completed := world.work_domain.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		String(task.get("requestedResultKind", "")),
		{
			"resultRef": "occupation-service-result:%s:%s"
				% [request_id, String(task.get("capability", ""))],
			"facts": outcome,
		},
	) as Dictionary
	if completed.get("ok") != true:
		return
	if kind == "clinic" and not outcome.is_empty():
		world.CLINIC_CONDITION_SETTLEMENT_RUNTIME.settle(world,
			request,
			task,
			resident_id,
			outcome,
			now,
			execution,
		)
	if follow_up_created:
		return
	if domain_result.get("ok") != true:
		return
	var completed_request := world.work_domain.services.request(
		request_id,
	) as Dictionary
	if String(completed_request.get("state", "")) == "completed":
		world.CUSTOMER_SERVICE_WAIT_RUNTIME.finish(world,
			requester_id,
			request_id,
			"已经等到并完成这次服务",
			true,
		)
		if kind == "dining_order":
			DINING_SERVICE.complete_additional_orders(
				world,
				resident_id,
				request_id,
				now,
			)
		if kind == "library_return":
			world.PRIVATE_MESSAGE_DELIVERY_RUNTIME.cancel_for_source(world,
				"library-return:%s" % String(request.get("subjectRef", "")),
				"借阅已经归还，不再需要提醒",
			)
		if kind == "clinic" and bool(
			(request.get("context", {}) as Dictionary).get(
				"generatedFromFollowUp",
				false,
			)
		):
			world.PRIVATE_MESSAGE_DELIVERY_RUNTIME.cancel_for_source(world,
				"clinic-follow-up:%s" % String(
					(request.get("context", {}) as Dictionary).get(
						"followUpId",
						"",
					)
				),
				"复诊已经完成，不再需要提醒",
			)
		if String(
			(request.get("context", {}) as Dictionary).get(
				"customerServiceMode",
				"",
			),
		) == "preorder":
			world.PRIVATE_MESSAGE_DELIVERY_RUNTIME.cancel_for_source(world,
				"preorder:%s" % request_id,
				"预订已经领取",
			)
			SOCIAL_MATTER_COMMAND_RUNTIME.close_resident_request_source(
				world,
				"preorder-pickup:%s" % request_id,
				"preorder-picked-up",
			)
	WORLD_LOG_COMMIT_RUNTIME.append_service(world,
		request,
		task,
		resident_id,
		outcome,
	)
	if (
		kind == "repair"
		and String(outcome.get("status", "")) == "ready_for_pickup"
	):
		world.SERVICE_READY_NOTIFICATION_RUNTIME.notify_repair(world, request, resident_id, now)
		return
	if bool(
		OCCUPATION_SERVICE_DEFINITION.definition(kind).get(
			"placeService",
			false,
		)
	):
		world.record_place_service_request(
			place_id,
			request_id,
			false,
		)


static func _complete_facility_cleanup_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	var activity_id := String(execution.get("activityId", ""))
	var expected_source := String(CONTENT_CATALOG.FACILITY_CLEANUP_SOURCE_BY_ACTIVITY.get(activity_id, ""))
	if expected_source.is_empty():
		return
	var task_id := String(task.get("taskId", ""))
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("sourceKind", "")) != expected_source
	):
		return
	var now := int(world._environment.get_absolute_minute())
	var cleaned := (
		world.work_domain.services.clean_dirty_dish(
			resident_id,
			now,
		)
		if expected_source == "dirty_dishes"
		else world.work_domain.services.clean_used_cafe_table(
			resident_id,
			now,
		)
	) as Dictionary
	if cleaned.get("ok") != true:
		return
	world.work_domain.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		String(task.get("requestedResultKind", "")),
		{
			"resultRef": "%s-result:%s"
				% [expected_source, task_id],
			"facts": {
				"placeId": String(execution.get("placeId", "")),
				"workerResidentId": resident_id,
				"remainingCount": int(cleaned.get(
					(
						"dirtyDishCount"
						if expected_source == "dirty_dishes"
						else "usedCafeTableCount"
					),
					0,
				)),
			},
		},
	)
	world.work_domain.sync_facility_cleanup_task(expected_source, now)


static func _complete_research_accession_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	if String(execution.get("activityId", "")) != (
		"activity_library_shelve_returns"
	):
		return
	var task_id := String(task.get("taskId", ""))
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("capability", "")) != "library.accession"
		or String(task.get("sourceKind", "")) != "research_handoff"
	):
		return
	var record_id := String(task.get("sourceRef", ""))
	var now := int(world._environment.get_absolute_minute())
	var accession_result := world.work_domain.services.record_accession(
		record_id,
		resident_id,
		now,
	) as Dictionary
	if accession_result.get("ok") != true:
		return
	var accession := accession_result.get(
		"accession",
		{},
	) as Dictionary
	var production_result := world.work_domain.production.record_research_accession(
		record_id,
		accession,
		now,
	) as Dictionary
	if production_result.get("ok") != true:
		return
	var accession_task_completion := world.work_domain.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		"accession_record",
		{
			"resultRef": String(
				accession.get("accessionId", ""),
			),
			"facts": accession.duplicate(true),
		},
	) as Dictionary
	if accession_task_completion.get("ok") != true:
		return
	var researcher_id := ""
	for project_value: Variant in world.work_domain.production.plant_research_projects():
		var project := project_value as Dictionary
		var record := project.get("record", {}) as Dictionary
		if String(record.get("recordId", "")) == record_id:
			researcher_id = String(record.get("workerResidentId", ""))
			break
	if not researcher_id.is_empty() and researcher_id != resident_id:
		RESIDENT_MESSAGE_POLICY.send(
			world,
			RESIDENT_MESSAGE_CONTENT.research_accessioned(
				resident_id,
				researcher_id,
				record_id,
			),
		)


static func _complete_cargo_receipt_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	var task_id := String(task.get("taskId", ""))
	if task_id.is_empty():
		return
	if (
		String(task.get("state", "")) != "in_progress"
		or String(task.get("sourceKind", "")) not in [
			"incoming_cargo",
			"flower_cargo",
		]
		or String(task.get("capability", "")) not in [
			"inventory.receive",
			"retail.receive",
			"cafe.production",
			"food.production",
			"care.treatment",
			"craft.production",
			"library.accession",
		]
	):
		return
	var lot_id := String(task.get("sourceRef", ""))
	var lot := world.work_domain.cargo.cargo_lot(
		lot_id,
	) as Dictionary
	var place_id := String(execution.get("placeId", ""))
	if (
		String(lot.get("state", "")) != "awaiting_receipt"
		or String(lot.get("destinationPlaceId", "")) != place_id
	):
		return
	var received := world.work_domain.cargo.receive(
		lot_id,
		resident_id,
		place_id,
		int(world._environment.get_absolute_minute()),
	) as Dictionary
	if received.get("ok") != true:
		return
	world.work_domain.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		String(task.get("requestedResultKind", "")),
		{
			"resultRef": "cargo-receipt:%s" % lot_id,
			"facts": {
				"lotId": lot_id,
				"placeId": place_id,
				"receiverResidentId": resident_id,
				"itemId": String(lot.get("itemId", "")),
				"quantity": int(lot.get("quantity", 0)),
			},
		},
	)
	WORLD_LOG_COMMIT_RUNTIME.append_cargo(world,
		"货批入库",
		received.get("lot", {}) as Dictionary,
		resident_id,
		"completed",
	)
	if place_id == CONTENT_CATALOG.PLACE_MARKET:
		world.work_domain.sync_market_preparation_tasks(
			int(world._environment.get_absolute_minute()),
		)
	var received_item_id := String(lot.get("itemId", ""))
	if received_item_id == CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET:
		world.CARGO_COMMAND_RUNTIME.schedule_occupation_decisions(
			world,
			(
				"occupation_clinic_practitioner"
				if place_id == CONTENT_CATALOG.PLACE_CLINIC
				else "occupation_grocer"
			),
		)
	elif received_item_id == "pastry" and place_id == CONTENT_CATALOG.PLACE_CAFE:
		world.CARGO_COMMAND_RUNTIME.schedule_occupation_decisions(
			world, "occupation_cafe_worker",
		)


static func _complete_cargo_release_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	if String(execution.get("activityId", "")) not in CONTENT_CATALOG.WAREHOUSE_SETTLEMENT_ACTIVITIES:
		return
	var task_id := String(task.get("taskId", ""))
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("capability", "")) != "inventory.release"
		or String(task.get("sourceKind", "")) != "inventory_request"
		or String(execution.get("placeId", "")) != CONTENT_CATALOG.PLACE_WAREHOUSE
	):
		return
	var lot_id := String(task.get("sourceRef", ""))
	var lot := world.work_domain.cargo.cargo_lot(
		lot_id,
	) as Dictionary
	var now := int(world._environment.get_absolute_minute())
	if String(lot.get("state", "")) == "awaiting_release":
		var released := world.work_domain.cargo.release(
			lot_id,
			resident_id,
			CONTENT_CATALOG.PLACE_WAREHOUSE,
			now,
		) as Dictionary
		if released.get("ok") != true:
			return
		lot = released.get("lot", {}) as Dictionary
	if String(lot.get("state", "")) != "available":
		return
	var active_delivery := world.work_domain.tasks.active_task_for_source(
		"cargo_available",
		lot_id,
	) as Dictionary
	if active_delivery.is_empty():
		var delivery_result : Variant = world.CARGO_COMMAND_RUNTIME.create_delivery_task(world,
			lot,
			int(task.get("priority", 70)),
		)
		if delivery_result.get("ok") != true:
			return
	world.work_domain.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		"release_lot",
		{
			"resultRef": "cargo-release:%s" % lot_id,
			"facts": {
				"lotId": lot_id,
				"itemId": String(lot.get("itemId", "")),
				"quantity": int(lot.get("quantity", 0)),
				"sourcePlaceId": CONTENT_CATALOG.PLACE_WAREHOUSE,
				"releasedByResidentId": resident_id,
				"releasedAtMinute": now,
			},
		},
	)
	world._bump_world_revision()
	WORLD_LOG_COMMIT_RUNTIME.append_cargo(world,
		"货批放货",
		lot,
		resident_id,
		"ongoing",
	)
	world.CARGO_COMMAND_RUNTIME.schedule_occupation_decisions(
		world, "occupation_delivery_worker",
	)


static func _complete_production_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	var activity_id := String(execution.get("activityId", ""))
	if activity_id not in CONTENT_CATALOG.PRODUCTION_SETTLEMENT_ACTIVITIES:
		return
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
	):
		return
	var now := int(world._environment.get_absolute_minute())
	var capability := String(task.get("capability", ""))
	var resolution := {}
	if (
		activity_id == "activity_fisher_catch_in_region"
		and capability == "fishing.harvest"
	):
		resolution = world.work_domain.production.resolve_fishing(
			now,
			world.get_weather(),
		) as Dictionary
		if resolution.get("ok") != true:
			return
		var fishing_quantity := int(resolution.get("quantity", 0))
		if fishing_quantity <= 0:
			_complete_bound_production_task(world,
				task,
				resident_id,
				"empty-catch:%s:%d"
					% [resident_id, now],
				{
					"regionId": String(
						resolution.get("regionId", ""),
					),
					"outcome": "empty",
					"quantity": 0,
					"weather": world.get_weather(),
				},
			)
			return
		var fishing_lot_result : Variant = world.create_world_result_cargo_lot({
			"lotId": "",
			"itemId": CONTENT_CATALOG.ITEM_FISH,
			"quantity": fishing_quantity,
			"sourcePlaceId": CONTENT_CATALOG.PLACE_FISHING_PORT,
			"destinationPlaceId": CONTENT_CATALOG.PLACE_MARKET,
			"createdAtMinute": now,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["fishing_catch_lot"],
		})
		if fishing_lot_result.get("ok") != true:
			return
		var fishing_lot := fishing_lot_result.get(
			"lot",
			{},
		) as Dictionary
		_complete_bound_production_task(world,
			task,
			resident_id,
			"catch-result:%s"
				% String(fishing_lot.get("lotId", "")),
			{
				"regionId": String(
					resolution.get("regionId", ""),
				),
				"itemId": CONTENT_CATALOG.ITEM_FISH,
				"quantity": fishing_quantity,
				"cargoLotId": String(
					fishing_lot.get("lotId", ""),
				),
			},
		)
	elif (
		activity_id == "activity_farm_water_beds"
		and capability == "garden.care"
	):
		resolution = world.work_domain.production.resolve_garden_care(
			String(task.get("sourceRef", "")),
		) as Dictionary
		if resolution.get("ok") != true:
			return
		_complete_bound_production_task(world,
			task,
			resident_id,
			"garden-care-result:%s"
				% String(task.get("sourceRef", "")),
			{
				"plotId": String(task.get("sourceRef", "")),
				"regionId": "outdoor_garden_01",
				"stateChanged": true,
			},
		)
	elif (
		activity_id == "activity_garden_harvest_region"
		and capability == "garden.harvest"
		and String(task.get("sourceKind", "")) == "sample_request"
	):
		var sample_lot_result : Variant = world.create_world_result_cargo_lot({
			"lotId": "",
			"itemId": CONTENT_CATALOG.ITEM_PLANT_SAMPLE,
			"quantity": 1,
			"sourcePlaceId": CONTENT_CATALOG.PLACE_GARDEN,
			"destinationPlaceId": CONTENT_CATALOG.PLACE_LIBRARY,
			"createdAtMinute": now,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["plant_sample_lot"],
		})
		if sample_lot_result.get("ok") != true:
			return
		var sample_lot := sample_lot_result.get("lot", {}) as Dictionary
		_complete_bound_production_task(world,
			task,
			resident_id,
			"plant-sample:%s" % String(sample_lot.get("lotId", "")),
			{
				"projectId": String(task.get("sourceRef", "")),
				"regionId": "outdoor_garden_01",
				"itemId": CONTENT_CATALOG.ITEM_PLANT_SAMPLE,
				"quantity": 1,
				"cargoLotId": String(sample_lot.get("lotId", "")),
				"collectedByResidentId": resident_id,
			},
		)
	elif (
		activity_id == "activity_garden_harvest_region"
		and capability == "garden.harvest"
	):
		resolution = world.work_domain.production.resolve_garden_harvest(
			String(task.get("sourceRef", "")),
		) as Dictionary
		if resolution.get("ok") != true:
			return
		var flower_quantity := int(resolution.get("quantity", 0))
		var flower_lot_result : Variant = world.create_world_result_cargo_lot({
			"lotId": "",
			"itemId": CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
			"quantity": flower_quantity,
			"sourcePlaceId": CONTENT_CATALOG.PLACE_GARDEN,
			"destinationPlaceId": CONTENT_CATALOG.PLACE_MARKET,
			"createdAtMinute": now,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["garden_harvest_lot"],
		})
		if flower_lot_result.get("ok") != true:
			return
		var flower_lot := flower_lot_result.get(
			"lot",
			{},
		) as Dictionary
		_complete_bound_production_task(world,
			task,
			resident_id,
			"garden-harvest-result:%s"
				% String(flower_lot.get("lotId", "")),
			{
				"plotId": String(task.get("sourceRef", "")),
				"regionId": "outdoor_garden_01",
				"itemId": CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
				"quantity": flower_quantity,
				"cargoLotId": String(
					flower_lot.get("lotId", ""),
				),
			},
		)


static func _complete_plant_research_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	var activity_id := String(execution.get("activityId", ""))
	var expected_capability := String(CONTENT_CATALOG.PLANT_RESEARCH_CAPABILITY_BY_ACTIVITY.get(activity_id, ""))
	if expected_capability.is_empty():
		return
	var task_id := String(task.get("taskId", ""))
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("capability", ""))
		!= expected_capability
	):
		return
	var project_id := String(task.get("sourceRef", ""))
	var now := int(world._environment.get_absolute_minute())
	var resolution := {}
	match expected_capability:
		"research.observe":
			var observation_region_id := ""
			for target_value: Variant in task.get("targets", []) as Array:
				var target := target_value as Dictionary
				if String(target.get("kind", "")) == "region":
					observation_region_id = String(target.get("ref", ""))
					break
			var place_features: Array = []
			for place_value: Variant in world.world_definition.world_data.get("places", []) as Array:
				var place := place_value as Dictionary
				if String(place.get("name", "")) == String(
					execution.get("placeId", ""),
				):
					place_features = (
						place.get("visibleFeatures", []) as Array
					).duplicate()
					break
			resolution = world.work_domain.production.record_plant_observation(
				project_id,
				resident_id,
				world.get_weather(),
				now,
				observation_region_id,
				String(execution.get("placeId", "")),
				place_features,
			) as Dictionary
		"research.verify":
			resolution = world.work_domain.production.record_plant_verification(
				project_id,
				resident_id,
				now,
			) as Dictionary
		"research.record":
			resolution = world.work_domain.production.finish_plant_research_record(
				project_id,
				resident_id,
				now,
			) as Dictionary
	if resolution.get("ok") != true:
		return
	var project := resolution.get("project", {}) as Dictionary
	var completed := world.work_domain.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		"research_record",
		{
			"resultRef": "%s:%s"
				% [expected_capability, project_id],
			"facts": {
				"projectId": project_id,
				"stage": String(project.get("stage", "")),
				"workerResidentId": resident_id,
				"activityId": activity_id,
			},
		},
	) as Dictionary
	if completed.get("ok") != true:
		return
	match expected_capability:
		"research.observe":
			PRODUCTION_TASK_COORDINATION_RUNTIME.create_plant_research_stage_task(
				world, project, "verify",
			)
		"research.verify":
			PRODUCTION_TASK_COORDINATION_RUNTIME.create_plant_research_stage_task(
				world, project, "record",
			)
		"research.record":
			var record := resolution.get("record", {}) as Dictionary
			var record_id := String(record.get("recordId", ""))
			if record_id.is_empty():
				return
			world.create_work_task({
				"taskId": "research-accession-task:%s" % project_id,
				"capability": "library.accession",
				"sourceKind": "research_handoff",
				"sourceRef": record_id,
				"targets": [{
					"kind": "prop",
					"ref": "图书馆还书车",
				}],
				"requestedResultKind": "accession_record",
				"priority": CONTENT_CATALOG.TASK_PRIORITY["research_accession_follow_up"],
			})


static func _complete_craft_production_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	var activity_id := String(execution.get("activityId", ""))
	if activity_id not in CONTENT_CATALOG.WORKSHOP_SETTLEMENT_ACTIVITIES:
		return
	var task_id := String(task.get("taskId", ""))
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("capability", "")) != "craft.production"
		or String(task.get("sourceKind", "")) != "production_request"
	):
		return
	var process_stage := String(task.get("processStage", "ready"))
	var process_facts := (
		task.get("processFacts", {}) as Dictionary
	).duplicate(true)
	var now := int(world._environment.get_absolute_minute())
	if (
		activity_id == "activity_workshop_take_lumber"
		and process_stage == "materials_planned"
	):
		process_facts["materialsTakenAtMinute"] = now
		process_facts["nextActivityId"] = "activity_workshop_grind_parts"
		world.work_domain.tasks.advance_process_stage(
			task_id,
			resident_id,
			int(task.get("revision", 0)),
			"materials_taken",
			process_facts,
		)
		return
	if (
		activity_id == "activity_workshop_grind_parts"
		and process_stage == "materials_taken"
	):
		process_facts["partsPreparedAtMinute"] = now
		process_facts["nextActivityId"] = "activity_workshop_assemble_item"
		world.work_domain.tasks.advance_process_stage(
			task_id,
			resident_id,
			int(task.get("revision", 0)),
			"parts_prepared",
			process_facts,
		)
		return
	if (
		activity_id != "activity_workshop_assemble_item"
		or process_stage != "parts_prepared"
	):
		return
	var destination_place_id := String(
		process_facts.get("destinationPlaceId", CONTENT_CATALOG.PLACE_WAREHOUSE),
	)
	var lot_result : Variant = world.create_world_result_cargo_lot({
		"itemId": String(
			process_facts.get("productItemId", "crafted_item"),
		),
		"quantity": 1,
		"sourcePlaceId": CONTENT_CATALOG.PLACE_WORKSHOP,
		"destinationPlaceId": destination_place_id,
		"createdAtMinute": now,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["craft_output_lot"],
	})
	if lot_result.get("ok") != true:
		return
	var lot := lot_result.get("lot", {}) as Dictionary
	world.work_domain.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		String(task.get("requestedResultKind", "")),
		{
			"resultRef": "crafted-lot:%s" % String(lot.get("lotId", "")),
			"facts": {
				"workerResidentId": resident_id,
				"activityId": activity_id,
				"itemId": String(lot.get("itemId", "crafted_item")),
				"quantity": int(lot.get("quantity", 1)),
				"cargoLotId": String(lot.get("lotId", "")),
				"destinationPlaceId": destination_place_id,
				"baseSupplyItems": (
					process_facts.get("baseSupplyItems", []) as Array
				).duplicate(),
			},
		},
	)


static func _complete_music_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	if String(execution.get("activityId", "")) != (
		"activity_musician_rehearse"
	):
		return
	var task_id := String(task.get("taskId", ""))
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("capability", "")) != "music.rehearse"
		or String(task.get("sourceKind", ""))
		!= "personal_performance_plan"
	):
		return
	_complete_bound_production_task(world,
		task,
		resident_id,
		"rehearsal:%s" % task_id,
		{
			"workerResidentId": resident_id,
			"activityId": "activity_musician_rehearse",
			"placeId": String(execution.get("placeId", "")),
			"rehearsedAtMinute": int(
				world._environment.get_absolute_minute(),
			),
		},
	)
	var now := int(world._environment.get_absolute_minute())
	var day_index := now / 1440
	var program := "第%d日广场演奏" % (day_index + 1)
	var performance := {}
	for request_value: Variant in (
		world.work_domain.services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var existing_request := request_value as Dictionary
		var existing_context := existing_request.get("context", {}) as Dictionary
		if (
			String(existing_request.get("kind", "")) == "performance"
			and String(existing_request.get("state", "")) in ["pending", "waiting"]
			and int(existing_context.get("dayIndex", -1)) == day_index
		):
			var merged := world.work_domain.services.merge_request_context(
				String(existing_request.get("requestId", "")),
				{"generatedFromRehearsal": true},
			) as Dictionary
			if merged.get("ok") == true:
				performance = merged.duplicate(true)
			break
	if performance.is_empty():
		performance = world.create_occupation_service_request({
			"kind": "performance",
			"requesterResidentId": resident_id,
			"subjectRef": program,
			"context": {
				"generatedFromRehearsal": true,
				"dayIndex": day_index,
			},
		})
	if performance.get("ok") != true:
		return
	world.work_domain.ensure_production_task({
		"taskId": "performance-bulletin:%d" % day_index,
		"capability": "bulletin.publish",
		"sourceKind": "public_matter",
		"sourceRef": "performance-event:%d" % day_index,
		"targets": [{
			"kind": "prop",
			"ref": "中心广场公告栏张贴处",
		}],
		"requestedResultKind": "bulletin_publish",
		"createdAtMinute": now,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["performance_bulletin"],
		"processStage": "confirmed_post",
		"processFacts": {
			"text": "%s准备在中心广场演奏，愿意的居民可以到场听。" % (
				world.resident_display_name(resident_id)
			),
			"deliveryMode": "board",
			"nextActivityId": world.BULLETIN_PUBLISH_ACTIVITY_ID,
		},
	})
	var invitee_ids: Array[String] = []
	for candidate_id: String in world.resident_registry.order:
		if candidate_id != resident_id and world.resident_is_present(
			world.resident_registry.records.get(candidate_id, {}) as Dictionary,
		):
			invitee_ids.append(candidate_id)
	invitee_ids.sort()
	var invite_count := mini(2, invitee_ids.size())
	var invite_start := (
		posmod(day_index, invitee_ids.size())
		if not invitee_ids.is_empty()
		else 0
	)
	for invite_index in invite_count:
		var invitee_id := invitee_ids[
			posmod(invite_start + invite_index, invitee_ids.size())
		]
		RESIDENT_MESSAGE_POLICY.send(
			world,
			RESIDENT_MESSAGE_CONTENT.performance_invitation(
				resident_id,
				invitee_id,
				day_index,
				now + 240,
			),
		)


static func _complete_food_production_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	if String(execution.get("activityId", "")) not in CONTENT_CATALOG.BAKER_SETTLEMENT_ACTIVITIES:
		return
	var task_id := String(task.get("taskId", ""))
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("capability", "")) != "food.production"
		or String(task.get("sourceKind", "")) not in [
			"daily_baking_plan",
			"meal_demand",
		]
	):
		return
	var activity_id := String(execution.get("activityId", ""))
	var process_stage := String(task.get("processStage", "ready"))
	var process_facts := (
		task.get("processFacts", {}) as Dictionary
	).duplicate(true)
	var now := int(world._environment.get_absolute_minute())
	if (
		activity_id == "activity_baker_prepare_dough"
		and process_stage == "planned"
	):
		process_facts["doughPreparedAtMinute"] = now
		process_facts["preparedByResidentId"] = resident_id
		process_facts["nextActivityId"] = "activity_baker_bake_bread"
		world.work_domain.tasks.advance_process_stage(
			task_id,
			resident_id,
			int(task.get("revision", 0)),
			"dough_prepared",
			process_facts,
		)
		return
	if (
		activity_id != "activity_baker_bake_bread"
		or process_stage != "dough_prepared"
	):
		return
	var item_id := String(process_facts.get("productItemId", "pastry"))
	var destination_place_id := String(
		process_facts.get("destinationPlaceId", CONTENT_CATALOG.PLACE_CAFE),
	)
	var lot_result : Variant = world.create_world_result_cargo_lot({
		"lotId": "",
		"itemId": item_id,
		"quantity": 2,
		"sourcePlaceId": CONTENT_CATALOG.PLACE_DINING_HALL,
		"destinationPlaceId": destination_place_id,
		"createdAtMinute": now,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["baked_goods_lot"],
	})
	if lot_result.get("ok") != true:
		return
	var lot := lot_result.get("lot", {}) as Dictionary
	world.work_domain.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		String(task.get("requestedResultKind", "")),
		{
			"resultRef": "food-batch:%s" % String(lot.get("lotId", "")),
			"facts": {
				"placeId": CONTENT_CATALOG.PLACE_DINING_HALL,
				"workerResidentId": resident_id,
				"activityId": activity_id,
				"baseSupplyUsed": ["flour"],
				"itemId": item_id,
				"quantity": 2,
				"cargoLotId": String(lot.get("lotId", "")),
				"destinationPlaceId": destination_place_id,
			},
		},
	)


static func _complete_retail_preparation_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	if String(execution.get("activityId", "")) != (
		"activity_flower_arrange_bouquets"
	):
		return
	var task_id := String(task.get("taskId", ""))
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("capability", "")) != "retail.arrange"
		or String(task.get("sourceKind", "")) != "display_change"
	):
		return
	var inputs := {CONTENT_CATALOG.ITEM_FRESH_FLOWERS: 2}
	var outputs := {CONTENT_CATALOG.ITEM_BOUQUET: 1}
	var transformed := world.work_domain.cargo.apply_inventory_recipe(
		CONTENT_CATALOG.PLACE_MARKET,
		inputs,
		outputs,
	) as Dictionary
	if transformed.get("ok") != true:
		return
	world.work_domain.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		"bouquet_lot",
		{
			"resultRef": "bouquet-batch:%s" % task_id,
			"facts": {
				"placeId": CONTENT_CATALOG.PLACE_MARKET,
				"workerResidentId": resident_id,
				"consumed": inputs.duplicate(true),
				"produced": outputs.duplicate(true),
			},
		},
	)
	world.work_domain.sync_market_preparation_tasks(
		int(world._environment.get_absolute_minute()),
	)


static func _complete_recurring_occupation_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	var task_id := String(task.get("taskId", ""))
	if task.is_empty() or String(task.get("state", "")) != "in_progress":
		return
	var activity_id := String(execution.get("activityId", ""))
	var capability := String(task.get("capability", ""))
	var source_kind := String(task.get("sourceKind", ""))
	var source_ref := String(task.get("sourceRef", ""))
	var now := int(world._environment.get_absolute_minute())
	if (
		capability == "message.accept"
		and source_kind == "daily_postal_collection_plan"
		and activity_id == "activity_postal_collect_outgoing_mail"
	):
		var waiting_message_count := POSTAL_MESSAGE_RUNTIME.waiting_message_count(world)
		_complete_bound_production_task(world,
			task,
			resident_id,
			"postal-collection:%s" % source_ref,
			{
				"workerResidentId": resident_id,
				"activityId": activity_id,
				"completedAtMinute": now,
				"waitingMessageCount": waiting_message_count,
			},
		)
		return
	if source_kind == "daily_operation_plan":
		var daily_operation_activities := CONTENT_CATALOG.DAILY_OPERATION_ACTIVITY_BY_CAPABILITY
		if String(daily_operation_activities.get(capability, "")) == (
			activity_id
		):
			_complete_bound_production_task(world,
				task,
				resident_id,
				"daily-operation:%s" % source_ref,
				{
					"workerResidentId": resident_id,
					"activityId": activity_id,
					"completedAtMinute": now,
					"inventoryChanged": false,
				},
			)
		return
	if (
		capability == "library.assist"
		and source_kind in ["daily_catalog_plan", "catalog_mismatch"]
		and activity_id == "activity_library_staff_checkout"
	):
		_complete_bound_production_task(world,
			task,
			resident_id,
			"catalog-check:%s" % source_ref,
			{
				"workerResidentId": resident_id,
				"checkedAtMinute": now,
				"catalogConsistent": true,
			},
		)
		return
	if (
		capability == "civic.service"
		and source_kind in [
			"resident_request",
			"place_service_change",
			"staffing_matter",
			"public_matter",
		]
		and activity_id in [
			"activity_town_hall_manage_records",
			"activity_town_hall_process_paperwork",
		]
	):
		var facts := (task.get("processFacts", {}) as Dictionary).duplicate(true)
		facts["workerResidentId"] = resident_id
		facts["completedAtMinute"] = now
		var completed := world.work_domain.tasks.complete_task(
			task_id,
			resident_id,
			int(task.get("revision", 0)),
			"civic_case_update",
			{
				"resultRef": "civic-review:%s" % source_ref,
				"facts": facts,
			},
		) as Dictionary
		if completed.get("ok") != true:
			return
		var weather := String(facts.get("weather", world.get_weather()))
		var bulletin_text := "今日天气%s，镇上公共服务按当前安排运行。" % weather
		if int(facts.get("vacancyCount", 0)) > 0:
			bulletin_text = "%s 当前有岗位需要居民协商接手。" % bulletin_text
		world.work_domain.ensure_production_task({
			"taskId": "civic-bulletin:%s" % source_ref,
			"capability": "bulletin.publish",
			"sourceKind": "public_matter",
			"sourceRef": "civic-bulletin:%s" % source_ref,
			"targets": [{
				"kind": "prop",
				"ref": "中心广场公告栏张贴处",
			}],
			"requestedResultKind": "bulletin_publish",
			"createdAtMinute": now,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["civic_bulletin"],
			"processStage": "confirmed_post",
			"processFacts": {
				"text": bulletin_text,
				"deliveryMode": (
					"town_bell"
					if weather in ["大雨", "雷暴", "下雪"]
					else "board"
				),
				"nextActivityId": world.BULLETIN_PUBLISH_ACTIVITY_ID,
			},
		})
		return
	if (
		capability == "staffing.coordinate"
		and source_kind == "staffing_matter"
		and activity_id in [
			"activity_town_hall_manage_records",
			"activity_town_hall_process_paperwork",
		]
	):
		var staffing_facts := (
			(task.get("processFacts", {}) as Dictionary).duplicate(true)
		)
		staffing_facts["workerResidentId"] = resident_id
		staffing_facts["reviewedAtMinute"] = now
		_complete_bound_production_task(world,
			task,
			resident_id,
			"staffing-review:%s" % source_ref,
			staffing_facts,
		)
		return
	if (
		capability == "food.production"
		and source_kind == "meal_demand"
		and source_ref.begins_with("meal-period:")
		and activity_id == "activity_dining_prepare_meal"
	):
		_complete_bound_production_task(world,
			task,
			resident_id,
			"prepared:%s" % source_ref,
			{
				"periodId": String(
					(task.get("processFacts", {}) as Dictionary).get(
						"periodId",
						"",
					),
				),
				"placeId": CONTENT_CATALOG.PLACE_DINING_HALL,
				"workerResidentId": resident_id,
				"preparedAtMinute": now,
				"baseSupplyUsed": true,
			},
		)
		var completed_task := world.work_domain.tasks.task(
			String(task.get("taskId", "")),
		) as Dictionary
		if String(completed_task.get("state", "")) == "completed":
			DINING_SERVICE.publish_meal_menu_announcement(
				world,
				world.work_domain.meal_period_for_minute(int(
					completed_task.get("createdAtMinute", now),
				)) as Dictionary,
				now,
			)
		world.OCCUPATION_SERVICE_PRESENCE_ADVANCEMENT_RUNTIME.activate_waiting_dining_orders(world)
		world.CARGO_COMMAND_RUNTIME.schedule_occupation_decisions(
			world, "occupation_dining_operator",
		)
		return
	if (
		capability == "inventory.receive"
		and source_kind in [
			"daily_inventory_plan",
			"inventory_request",
			"inventory_discrepancy",
		]
		and activity_id == "activity_warehouse_check_manifest"
	):
		_complete_bound_production_task(world,
			task,
			resident_id,
			"inventory-audit:%s" % source_ref,
			{
				"sourceKind": source_kind,
				"sourceRef": source_ref,
				"workerResidentId": resident_id,
				"checkedAtMinute": now,
				"discrepancyFound": source_kind == "inventory_discrepancy",
			},
		)


static func _complete_postal_process_work_task_before_release(
	world,
	resident_id: String,
	execution: Dictionary,
	task: Dictionary,
) -> void:
	var activity_id := String(execution.get("activityId", ""))
	var expected_capability := String(CONTENT_CATALOG.POSTAL_CAPABILITY_BY_ACTIVITY.get(activity_id, ""))
	if expected_capability.is_empty():
		return
	var task_id := String(task.get("taskId", ""))
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("capability", "")) != expected_capability
	):
		return
	var batch_id := String(task.get("sourceRef", ""))
	var now := int(world._environment.get_absolute_minute())
	var message_count := POSTAL_MESSAGE_RUNTIME.batch_message_count(world, batch_id)
	if message_count <= 0:
		world.work_domain.tasks.cancel_task(task_id, "本批消息已经不存在")
		return
	var result_kind := (
		"message_batch_sorted"
		if expected_capability == "message.sort"
		else "message_batch_prepared"
	)
	var completed := world.work_domain.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		result_kind,
		{
			"resultRef": "%s:%s" % [result_kind, batch_id],
			"facts": {
				"batchId": batch_id,
				"messageCount": message_count,
				"workerResidentId": resident_id,
				"completedAtMinute": now,
			},
		},
	) as Dictionary
	if completed.get("ok") != true:
		return
	if expected_capability == "message.sort":
		POSTAL_MESSAGE_RUNTIME.set_batch_delivery_stage(
			world,
			batch_id,
			"sorted",
			"__awaiting_mailbag__",
			now,
		)
		world.work_domain.ensure_production_task({
			"taskId": "postal-prepare-task:%s" % batch_id,
			"capability": "message.prepare",
			"sourceKind": "postal_batch_sorted",
			"sourceRef": batch_id,
			"targets": [{"kind": "route", "ref": "小镇道路"}],
			"requestedResultKind": "message_batch_prepared",
			"createdAtMinute": now,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["postal_mailbag"],
		})
	else:
		POSTAL_MESSAGE_RUNTIME.set_batch_delivery_stage(
			world,
			batch_id,
			"out_for_delivery",
			"__resident_delivery__",
			now,
		)
		world.POSTAL_MESSAGE_RUNTIME.reserve_delivery_tasks(world, batch_id)
		world.CARGO_COMMAND_RUNTIME.schedule_occupation_decisions(
			world, "occupation_postal_worker",
		)


static func _complete_bound_production_task(
	world,
	task: Dictionary,
	resident_id: String,
	result_ref: String,
	facts: Dictionary,
) -> void:
	world.work_domain.tasks.complete_task(
		String(task.get("taskId", "")),
		resident_id,
		int(task.get("revision", 0)),
		String(task.get("requestedResultKind", "")),
		{
			"resultRef": result_ref,
			"facts": facts,
		},
	)


static func _complete_bound_place_service_work_task(
	world,
	resident_id: String,
	execution: Dictionary,
	place_id: String,
	request_id: String,
) -> void:
	var action_id := String(execution.get("actionId", ""))
	var binding_key: String = world.activity_work_task_bindings.resolved_key(
		resident_id,
		action_id,
	)
	var task_id := String(
		world.activity_work_task_bindings.task_id_for_key(String(binding_key)),
	)
	if task_id.is_empty():
		return
	var task := world.work_domain.tasks.task(task_id) as Dictionary
	if (
		task.is_empty()
		or String(task.get("sourceRef", "")) != request_id
		or String(task.get("state", "")) != "in_progress"
	):
		return
	world.work_domain.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		String(task.get("requestedResultKind", "")),
		{
			"resultRef": "service-result:%s" % task_id,
			"facts": {
				"placeId": place_id,
				"requestId": request_id,
				"activityId": String(
					execution.get("activityId", ""),
				),
				"workerResidentId": resident_id,
			},
		},
	)


static func _complete_research_booklet_work_task(
	world,
	resident_id: String,
	task: Dictionary,
) -> void:
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("capability", "")) != "research.handoff"
	):
		return
	var now := int(world._environment.get_absolute_minute())
	var facts := (task.get("processFacts", {}) as Dictionary).duplicate(true)
	var destination_place_id := String(
		facts.get("destinationPlaceId", CONTENT_CATALOG.PLACE_MARKET),
	)
	var lot_result : Variant = world.create_world_result_cargo_lot({
		"itemId": CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
		"quantity": 1,
		"sourcePlaceId": CONTENT_CATALOG.PLACE_LIBRARY,
		"destinationPlaceId": destination_place_id,
		"createdAtMinute": now,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["research_booklet_lot"],
	})
	if lot_result.get("ok") != true:
		return
	var lot := lot_result.get("lot", {}) as Dictionary
	world.work_domain.tasks.complete_task(
		String(task.get("taskId", "")),
		resident_id,
		int(task.get("revision", 0)),
		String(task.get("requestedResultKind", "")),
		{
			"resultRef": "research-booklet:%s" % String(lot.get("lotId", "")),
			"facts": {
				"recordId": String(facts.get("recordId", "")),
				"workerResidentId": resident_id,
				"itemId": CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
				"cargoLotId": String(lot.get("lotId", "")),
				"destinationPlaceId": destination_place_id,
			},
		},
	)


static func _complete_natural_bulletin_work(
	world,
	resident_id: String,
	execution: Dictionary,
) -> void:
	if String(execution.get("activityId", "")) != world.BULLETIN_PUBLISH_ACTIVITY_ID:
		return
	var task : Variant = world.WORK_TASK_PUBLIC_RUNTIME.natural_bulletin_task_for_resident(world, resident_id)
	if task.is_empty():
		return
	var claimed := world.work_domain.claim_specific_work_task(
		task,
		"occupation_town_manager",
		resident_id,
		world.residents(),
	) as Dictionary
	if claimed.get("ok") != true:
		return
	task = claimed.get("task", {}) as Dictionary
	var facts := task.get("processFacts", {}) as Dictionary
	var publish_result := world.publish_resident_announcement(
		resident_id,
		String(facts.get("text", "")),
		"",
		String(facts.get("deliveryMode", "board")),
	) as Dictionary
	if publish_result.get("ok") != true:
		return
	var announcement := publish_result.get("announcement", {}) as Dictionary
	world.work_domain.tasks.complete_task(
		String(task.get("taskId", "")),
		resident_id,
		int(task.get("revision", 0)),
		"bulletin_publish",
		{
			"resultRef": "bulletin-publish:%s" % String(
				announcement.get("announcement_id", ""),
			),
			"facts": {
				"announcementId": String(
					announcement.get("announcement_id", ""),
				),
				"publisherResidentId": resident_id,
				"deliveryMode": String(
					announcement.get("delivery_mode", "board"),
				),
			},
		},
	)
	world.PLACE_SERVICE_COMMAND_RUNTIME.record_staffing_trial(world,
		resident_id,
		"occupation_town_manager",
		{"announcementId": String(announcement.get("announcement_id", ""))},
	)


static func _complete_repair_pickup_from_visitor(
	world,
	resident_id: String,
	execution: Dictionary,
) -> void:
	if (
		String(execution.get("activityId", ""))
		!= "activity_workshop_inspect_finished"
		or String(execution.get("role", "")) != "visitor"
		or String(execution.get("placeId", "")) != CONTENT_CATALOG.PLACE_WORKSHOP
	):
		return
	var now := int(world._environment.get_absolute_minute())
	var service_snapshot := world.work_domain.services.snapshot(
	) as Dictionary
	for value: Variant in service_snapshot.get("requests", []) as Array:
		var request := value as Dictionary
		var outcome := request.get("outcome", {}) as Dictionary
		if (
			String(request.get("kind", "")) != "repair"
			or String(request.get("requesterResidentId", ""))
			!= resident_id
			or String(request.get("state", ""))
			not in ["pending", "waiting"]
			or String(outcome.get("status", ""))
			!= "ready_for_pickup"
		):
			continue
		var pickup_outcome := outcome.duplicate(true)
		pickup_outcome["status"] = "picked_up"
		pickup_outcome["deliveredToRequester"] = true
		pickup_outcome["pickedUpByResidentId"] = resident_id
		pickup_outcome["pickedUpAtMinute"] = now
		var completed := world.work_domain.services.complete_request(
			String(request.get("requestId", "")),
			String(outcome.get("repairedByResidentId", "")),
			now,
			pickup_outcome,
		) as Dictionary
		if completed.get("ok") == true:
			world.PRIVATE_MESSAGE_DELIVERY_RUNTIME.cancel_for_source(world,
				"repair-pickup:%s" % String(request.get("requestId", "")),
				"修理件已经领取",
			)
			SOCIAL_MATTER_COMMAND_RUNTIME.close_resident_request_source(
				world,
				"repair-pickup:%s" % String(request.get("requestId", "")),
				"repair-item-picked-up",
			)
			world.record_place_service_request(
				CONTENT_CATALOG.PLACE_WORKSHOP,
				String(request.get("requestId", "")),
				false,
			)
		return


static func _record_equipment_wear_from_activity(world, execution: Dictionary) -> void:
	var activity_id := String(execution.get("activityId", ""))
	if activity_id not in [
		"activity_cafe_brew_coffee",
		"activity_dining_prepare_meal",
		"activity_library_staff_checkout",
		"activity_clinic_receive_patient",
		"activity_warehouse_move_cargo",
		"activity_flower_arrange_bouquets",
	]:
		return
	var target := world._activity_runtime.execution_physical_target(
		execution,
	) as Dictionary
	var prop_name := String(target.get("ref", "")).strip_edges()
	if prop_name.is_empty() and String(
		execution.get("targetType", ""),
	) == "prop":
		prop_name = String(
			execution.get("targetPropName", ""),
		).strip_edges()
	if prop_name.is_empty():
		return
	var recorded := world.work_domain.services.record_equipment_use(
		prop_name,
		String(execution.get("placeId", "")),
		activity_id,
		int(world._environment.get_absolute_minute()),
		6,
	) as Dictionary
	if recorded.get("ok") == true:
		PRODUCTION_TASK_COORDINATION_RUNTIME.sync_craft_chain(
			world,
			int(world._environment.get_absolute_minute()),
		)


static func _record_facility_use_from_activity(
	world,
	resident_id: String,
	execution: Dictionary,
) -> void:
	if String(execution.get("role", "")) != "visitor":
		return
	var activity_id := String(execution.get("activityId", ""))
	var now : Variant = world._authoritative_absolute_minute()
	var occupation_request_spec : Variant = world.PLACE_SERVICE_COMMAND_RUNTIME.visitor_occupation_service_spec(
		world,
		resident_id,
		activity_id,
	)
	if not occupation_request_spec.is_empty():
		var request_kind := String(
			occupation_request_spec.get("kind", ""),
		)
		var request_subject := String(
			occupation_request_spec.get("subjectRef", ""),
		)
		var active_clinic_request : Variant = (
			world.work_domain.active_clinic_request_for_resident(resident_id)
			if request_kind == "clinic"
			else {}
		)
		if not active_clinic_request.is_empty():
			world.CUSTOMER_SERVICE_WAIT_RUNTIME.begin(world,
				resident_id,
				String(active_clinic_request.get("requestId", "")),
				String(active_clinic_request.get("placeId", "")),
				active_clinic_request.get("context", {}) as Dictionary,
			)
		elif request_kind != "dining_order" and not (
			request_kind == "library_return"
			and bool(world.work_domain.services.has_active_request(
				request_kind,
				request_subject,
			))
		):
			world.create_occupation_service_request(occupation_request_spec)
	if activity_id == "activity_dining_eat_meal":
		# 用餐可能从一个餐次的末尾跨到下一个餐次；优先使用连续用餐
		# 例程在开始时保存的餐次，而不是完成这一阶段时的当前时刻。
		var meal_period_ref := ""
		var meal_routine := world.activity_routine_state.records.get(
			resident_id,
			{},
		) as Dictionary
		if String(meal_routine.get("group", "")) == "meal":
			meal_period_ref = String(
				meal_routine.get("mealPeriodRef", ""),
			).strip_edges()
		if meal_period_ref.is_empty():
			meal_period_ref = String(world.work_domain.meal_period_source_ref(int(now)))
		if (
			not meal_period_ref.is_empty()
			and not world.work_domain.services.has_dining_order_completed_for_resident_meal_period(
				resident_id,
				meal_period_ref,
			)
		):
			world.PLACE_SERVICE_COMMAND_RUNTIME.apply_consumed_item(world, resident_id, "meal")
			world.work_domain.services.mark_dining_order_completed_for_resident_meal_period(
				resident_id,
				meal_period_ref,
			)
		return
	if activity_id == "activity_dining_return_dishes":
		var recorded_dish := world.work_domain.services.record_dirty_dish(
			resident_id,
			now,
		) as Dictionary
		if recorded_dish.get("ok") == true:
			world.work_domain.sync_facility_cleanup_task("dirty_dishes", now)
	elif activity_id == "activity_cafe_rest":
		var recorded_table := world.work_domain.services.record_used_cafe_table(
			resident_id,
			now,
		) as Dictionary
		if recorded_table.get("ok") == true:
			world.work_domain.sync_facility_cleanup_task("used_table", now)
