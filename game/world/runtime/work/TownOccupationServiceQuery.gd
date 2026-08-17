class_name TownOccupationServiceQuery
extends RefCounted


const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)


static func request_exists(
	occupation_services: TownOccupationServiceRuntime,
	kind: String,
	subject_ref: String,
) -> bool:
	for request_value: Variant in (
		occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == kind
			and String(request.get("subjectRef", "")) == subject_ref
		):
			return true
	return false


static func active_presence_requests(
	occupation_services: TownOccupationServiceRuntime,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for request_value: Variant in (
		occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		if request_value is not Dictionary:
			continue
		var request := request_value as Dictionary
		if (
			String(request.get("state", ""))
			in ["pending", "waiting", "in_progress"]
			and ACTION_SUPPORT.occupation_service_request_requires_presence(
				request,
			)
		):
			result.append(request.duplicate(true))
	return result


static func preorder_needed(
	cargo_inventory: TownCargoInventoryRuntime,
	occupation_services: TownOccupationServiceRuntime,
	kind: String,
	item_id: String,
	place_id: String,
) -> bool:
	if not (
		(kind == "cafe_order" and item_id == "pastry")
		or (
			kind == "grocer_sale"
			and item_id in [
				CONTENT_CATALOG.ITEM_FISH,
				CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
			]
		)
		or (
			kind == "flower_sale"
			and item_id in [
				CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
				CONTENT_CATALOG.ITEM_BOUQUET,
			]
		)
	):
		return false
	return unreserved_preorder_inventory_quantity(
		cargo_inventory,
		occupation_services,
		place_id,
		item_id,
	) <= 0


static func unreserved_preorder_inventory_quantity(
	cargo_inventory: TownCargoInventoryRuntime,
	occupation_services: TownOccupationServiceRuntime,
	place_id: String,
	item_id: String,
) -> int:
	var inventory_quantity := int(
		cargo_inventory.inventory_quantity(place_id, item_id),
	)
	var reserved_quantity := 0
	for request_value: Variant in (
		occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		var context := request.get("context", {}) as Dictionary
		if (
			String(request.get("state", "")) in ["pending", "waiting"]
			and String(request.get("placeId", "")) == place_id
			and String(request.get("itemId", "")) == item_id
			and String(context.get("customerServiceMode", "")) == "preorder"
		):
			reserved_quantity += maxi(
				int(context.get("preorderReservedQuantity", 0)),
				0,
			)
	return maxi(inventory_quantity - reserved_quantity, 0)


static func work_task_is_currently_available(
	task: Dictionary,
	occupation_services: TownOccupationServiceRuntime,
	residents: Dictionary,
) -> bool:
	var request := occupation_services.request(
		String(task.get("sourceRef", "")),
	) as Dictionary
	if request.is_empty():
		return true
	if String(request.get("state", "")) in ["completed", "cancelled"]:
		return false
	if not ACTION_SUPPORT.occupation_service_request_requires_presence(request):
		return true
	var requester := residents.get(
		String(request.get("requesterResidentId", "")),
		{},
	) as Dictionary
	return (
		not requester.is_empty()
		and String(requester.get("currentPlace", ""))
		== String(request.get("placeId", ""))
	)


static func kind_is_staffed(
	kind: String,
	definition: Dictionary,
	staffing: TownStaffingRuntime,
	residents: Dictionary,
) -> bool:
	if (
		kind == "clinic"
		or kind not in ACTION_SUPPORT.OCCUPATION_SERVICE_PRESENCE_REQUIRED_KINDS
	):
		return true
	var occupation_id := String(definition.get("occupationId", ""))
	if occupation_id.is_empty():
		return true
	var post := staffing.post_for_occupation(occupation_id) as Dictionary
	if post.is_empty() or String(post.get("status", "vacant")) == "vacant":
		return false
	var now := int(
		(staffing.snapshot() as Dictionary).get("absoluteMinute", 0),
	)
	for resident_id_value: Variant in post.get(
		"responsibleResidentIds",
		[],
	) as Array:
		var resident := residents.get(
			String(resident_id_value),
			{},
		) as Dictionary
		if resident.is_empty():
			continue
		var attendance := resident.get("attendanceState", {}) as Dictionary
		if (
			String(attendance.get("status", "available")) != "on_leave"
			or int(attendance.get("untilMinute", -1)) <= now
		):
			return true
	return false


static func dining_order_for_resident_meal_period(
	occupation_services: TownOccupationServiceRuntime,
	resident_id: String,
	absolute_minute: int,
	states: Array,
) -> Dictionary:
	var period_ref := meal_period_source_ref(absolute_minute)
	if period_ref.is_empty():
		return {}
	var selected: Dictionary = {}
	var selected_state_rank := states.size()
	for request_value: Variant in (
		occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		if request_value is not Dictionary:
			continue
		var request := request_value as Dictionary
		var request_state := String(request.get("state", ""))
		if (
			String(request.get("kind", "")) == "dining_order"
			and String(request.get("requesterResidentId", "")) == resident_id
			and states.has(request_state)
			and meal_period_source_ref(
				int(request.get("createdAtMinute", -1)),
			) == period_ref
		):
			var state_rank := states.find(request_state)
			if selected.is_empty() or state_rank < selected_state_rank:
				selected = request.duplicate(true)
				selected_state_rank = state_rank
	return selected


static func meal_period_source_ref(absolute_minute: int) -> String:
	var period := ACTIVITY_SCALARS.meal_period_for_minute(absolute_minute)
	if period.is_empty():
		return ""
	return "meal-period:%d:%s" % [
		absolute_minute / 1440,
		String(period.get("id", "")),
	]
