class_name TownWorkStateProjection
extends RefCounted


static func staffing(
	running: bool,
	runtime: TownStaffingRuntime,
) -> Dictionary:
	if running:
		return runtime.snapshot() as Dictionary
	return {
		"schemaVersion": 1,
		"posts": [],
		"vacantPostIds": [],
		"duplicatePostIds": [],
		"capacityConflictPostIds": [],
		"unassignedResidentIds": [],
	}


static func cargo_inventory(
	running: bool,
	runtime: TownCargoInventoryRuntime,
) -> Dictionary:
	if running:
		return runtime.snapshot() as Dictionary
	return {
		"schemaVersion": 1,
		"inventories": {},
		"cargoLots": [],
		"lotSequence": 0,
		"archiveSummary": {
			"terminalLotCount": 0,
			"deliveredLotCount": 0,
			"cancelledLotCount": 0,
			"quantityByItem": {},
		},
	}


static func occupation_services(
	running: bool,
	runtime: TownOccupationServiceRuntime,
) -> Dictionary:
	if running:
		return runtime.snapshot() as Dictionary
	return {
		"schemaVersion": 1,
		"requestSequence": 0,
		"requestTerminalSequence": 0,
		"loanSequence": 0,
		"followUpSequence": 0,
		"accessionSequence": 0,
		"requests": [],
		"loans": [],
		"bookAvailableCopies": {},
		"dirtyDishCount": 0,
		"usedCafeTableCount": 0,
		"accessionRecords": [],
		"equipmentConditions": {},
		"scheduledFollowUps": [],
		"archiveSummary": {
			"requests": {
				"terminalCount": 0,
				"completedCount": 0,
				"cancelledCount": 0,
				"countByKind": {},
			},
			"returnedLoans": {"count": 0, "countByBook": {}},
			"resolvedFollowUps": {"count": 0},
			"accessions": {"count": 0},
		},
	}


static func occupation_service_request(
	running: bool,
	runtime: TownOccupationServiceRuntime,
	request_id: String,
) -> Dictionary:
	return runtime.request(request_id.strip_edges()) if running else {}


static func occupation_post_is_vacant(
	runtime: TownStaffingRuntime,
	occupation_id: String,
) -> bool:
	if runtime == null:
		return true
	var post := runtime.post_for_occupation(occupation_id) as Dictionary
	return post.is_empty() or String(post.get("status", "vacant")) == "vacant"
