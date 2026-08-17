class_name TownVisitorOccupationServiceSpec
extends RefCounted


const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)


static func build(
	resident_id: String,
	activity_id: String,
	absolute_minute: int,
	context: Dictionary = {},
) -> Dictionary:
	match activity_id:
		"activity_cafe_order":
			return {
				"kind": "cafe_order",
				"requesterResidentId": resident_id,
				"itemId": CONTENT_CATALOG.ITEM_BREWED_COFFEE,
			}
		"activity_clinic_consult":
			var request := {
				"kind": "clinic",
				"requesterResidentId": resident_id,
			}
			var condition_context := context.get("clinicCondition", {}) as Dictionary
			if not condition_context.is_empty():
				request["subjectRef"] = String(condition_context.get("subjectRef", ""))
				request["context"] = (
					condition_context.get("context", {}) as Dictionary
				).duplicate(true)
			return request
		"activity_library_checkout":
			var borrowed_loan := context.get("borrowedLoan", {}) as Dictionary
			if not borrowed_loan.is_empty():
				return {
					"kind": "library_return",
					"requesterResidentId": resident_id,
					"subjectRef": String(borrowed_loan.get("loanId", "")),
				}
			var book_ids := [
				"book_plant_reference",
				"book_town_history",
				"book_practical_crafts",
			]
			return {
				"kind": "library_loan",
				"requesterResidentId": resident_id,
				"itemId": book_ids[posmod(hash(resident_id), book_ids.size())],
			}
		"activity_library_research":
			return {
				"kind": "library_assist",
				"requesterResidentId": resident_id,
				"subjectRef": "请馆员协助查找资料",
			}
		"activity_town_hall_civic_service", "activity_town_hall_fill_form":
			return {
				"kind": "civic_request",
				"requesterResidentId": resident_id,
				"subjectRef": "居民提交的日常镇务",
			}
		"activity_town_hall_meeting":
			if bool(context.get("performanceActive", false)):
				return {}
			return {
				"kind": "performance",
				"requesterResidentId": resident_id,
				"subjectRef": performance_subject(resident_id, absolute_minute),
				"context": {"generatedFromResidentInvitation": true},
			}
		"activity_workshop_handoff_repair":
			return {
				"kind": "repair",
				"requesterResidentId": resident_id,
				"subjectRef": "居民带来交接的日常器物",
			}
		"activity_dining_collect_meal":
			return {
				"kind": "dining_order",
				"requesterResidentId": resident_id,
				"itemId": "meal",
			}
		"activity_market_buy_general_goods":
			return _sale(
				"grocer_sale",
				resident_id,
				CONTENT_CATALOG.ITEM_GENERAL_GOODS,
			)
		"activity_market_buy_fish":
			return _sale(
				"grocer_sale",
				resident_id,
				CONTENT_CATALOG.ITEM_FISH,
			)
		"activity_market_buy_flowers":
			var flower_home := String(context.get("flowerHome", ""))
			var wants_delivery := (
				not flower_home.is_empty()
				and posmod(hash("%s:%d" % [
					resident_id,
					absolute_minute / 1440,
				]), 2) == 0
			)
			return {
				"kind": "flower_sale",
				"requesterResidentId": resident_id,
				"itemId": CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
				"context": {
					"deliveryRequested": wants_delivery,
					"destinationPlaceId": flower_home,
				},
			}
	return {}


static func performance_subject(resident_id: String, absolute_minute: int) -> String:
	return "居民邀请的广场小演出:%s:%d" % [
		resident_id,
		absolute_minute / 1440,
	]


static func _sale(kind: String, resident_id: String, item_id: String) -> Dictionary:
	return {
		"kind": kind,
		"requesterResidentId": resident_id,
		"itemId": item_id,
	}
