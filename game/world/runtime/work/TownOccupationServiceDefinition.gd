class_name TownOccupationServiceDefinition
extends RefCounted


const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)


static func definition(kind: String) -> Dictionary:
	return (
		{
			"clinic": {
				"serviceLabel": "问诊",
				"unstaffedBehavior": "continuity",
				"placeId": CONTENT_CATALOG.PLACE_CLINIC,
				"placeService": true,
				"capability": "care.consult",
				"sourceKind": "resident_care_request",
				"resultKind": "care_outcome",
				"occupationId": "occupation_clinic_practitioner",
				"targetKind": "service_request",
			},
			"library_loan": {
				"serviceLabel": "借阅",
				"unstaffedBehavior": "pause",
				"placeId": CONTENT_CATALOG.PLACE_LIBRARY,
				"placeService": true,
				"capability": "library.loan",
				"sourceKind": "loan_request",
				"resultKind": "loan_record",
				"occupationId": "occupation_librarian",
				"targetKind": "service_request",
			},
			"library_return": {
				"serviceLabel": "还书",
				"unstaffedBehavior": "pause",
				"placeId": CONTENT_CATALOG.PLACE_LIBRARY,
				"placeService": false,
				"capability": "library.return",
				"sourceKind": "returned_book",
				"resultKind": "catalog_state_change",
				"occupationId": "occupation_librarian",
				"targetKind": "service_request",
			},
			"library_assist": {
				"serviceLabel": "馆员协助",
				"unstaffedBehavior": "pause",
				"placeId": CONTENT_CATALOG.PLACE_LIBRARY,
				"placeService": false,
				"capability": "library.assist",
				"sourceKind": "lookup_request",
				"resultKind": "catalog_state_change",
				"occupationId": "occupation_librarian",
				"targetKind": "service_request",
			},
			"civic_request": {
				"serviceLabel": "镇务办理",
				"unstaffedBehavior": "pause",
				"placeId": CONTENT_CATALOG.PLACE_TOWN_HALL,
				"placeService": false,
				"capability": "civic.service",
				"sourceKind": "resident_request",
				"resultKind": "civic_case_update",
				"occupationId": "occupation_town_manager",
				"targetKind": "service_request",
			},
			"repair": {
				"serviceLabel": "维修",
				"unstaffedBehavior": "pause",
				"placeId": CONTENT_CATALOG.PLACE_WORKSHOP,
				"placeService": true,
				"capability": "craft.repair",
				"sourceKind": "repair_request",
				"resultKind": "repair_outcome",
				"occupationId": "occupation_craftsperson",
				"targetKind": "service_request",
			},
			"dining_order": {
				"serviceLabel": "正式供餐",
				"unstaffedBehavior": "continuity",
				"placeId": CONTENT_CATALOG.PLACE_DINING_HALL,
				"placeService": true,
				"capability": "food.service",
				"sourceKind": "meal_demand",
				"resultKind": "meal_handoff",
				"occupationId": "occupation_dining_operator",
				"targetKind": "service_request",
				"defaultItemId": "meal",
			},
			"cafe_order": {
				"serviceLabel": "咖啡点单",
				"unstaffedBehavior": "pause",
				"placeId": CONTENT_CATALOG.PLACE_CAFE,
				"placeService": true,
				"capability": "cafe.order",
				"sourceKind": "customer_order",
				"resultKind": "order_handoff",
				"occupationId": "occupation_cafe_worker",
				"targetKind": "service_request",
				"defaultItemId": CONTENT_CATALOG.ITEM_BREWED_COFFEE,
			},
			"grocer_sale": {
				"serviceLabel": "杂货销售",
				"unstaffedBehavior": "pause",
				"placeId": CONTENT_CATALOG.PLACE_MARKET,
				"placeService": false,
				"capability": "retail.sale",
				"sourceKind": "customer_demand",
				"resultKind": "retail_transfer",
				"occupationId": "occupation_grocer",
				"targetKind": "service_request",
				"defaultItemId": CONTENT_CATALOG.ITEM_GENERAL_GOODS,
			},
			"flower_sale": {
				"serviceLabel": "鲜花销售",
				"unstaffedBehavior": "pause",
				"placeId": CONTENT_CATALOG.PLACE_MARKET,
				"placeService": false,
				"capability": "retail.sale",
				"sourceKind": "customer_demand",
				"resultKind": "retail_transfer",
				"occupationId": "occupation_flower_vendor",
				"targetKind": "service_request",
				"defaultItemId": CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
			},
			"performance": {
				"serviceLabel": "演出",
				"unstaffedBehavior": "pause",
				"placeId": CONTENT_CATALOG.PLACE_PLAZA,
				"placeService": false,
				"capability": "music.perform",
				"sourceKind": "personal_performance_plan",
				"resultKind": "performance_record",
				"occupationId": "occupation_musician",
				"targetKind": "audience_area",
				"targetRef": "outdoor_plaza_01",
			},
		}.get(kind, {}) as Dictionary
	).duplicate(true)


static func clinic_default_subject_ref(resident: Dictionary) -> String:
	var body := resident.get("body", {}) as Dictionary
	return "%s、%s、%s" % [
		String(body.get("困", "不困")),
		String(body.get("饿", "不饿")),
		String(body.get("累", "不累")),
	]


static func item_allowed(kind: String, item_id: String) -> bool:
	return item_id in (
		{
			"dining_order": ["meal"],
			"cafe_order": [CONTENT_CATALOG.ITEM_BREWED_COFFEE, "pastry"],
			"grocer_sale": [
				CONTENT_CATALOG.ITEM_GENERAL_GOODS,
				CONTENT_CATALOG.ITEM_FISH,
				CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
			],
			"flower_sale": [
				CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
				CONTENT_CATALOG.ITEM_BOUQUET,
			],
		}.get(kind, []) as Array
	)
