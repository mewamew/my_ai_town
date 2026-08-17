class_name TownResidentRegistry
extends RefCounted


var records: Dictionary = {}
var order: Array[String] = []
var id_by_name: Dictionary = {}
var name_by_id: Dictionary = {}
var identity_status := "unavailable"


func reset() -> void:
	records.clear()
	order.clear()
	id_by_name.clear()
	name_by_id.clear()
	identity_status = "unavailable"


func install_identities(prepared: Dictionary) -> void:
	id_by_name.clear()
	name_by_id.clear()
	var name_counts: Dictionary = {}
	for value: Variant in prepared.get("residents", []) as Array:
		var identity := value as Dictionary
		var resident_id := String(identity.get("residentId", ""))
		var resident_name := String(identity.get("residentName", ""))
		if resident_id.is_empty() or resident_name.is_empty():
			continue
		name_by_id[resident_id] = resident_name
		name_counts[resident_name] = int(name_counts.get(resident_name, 0)) + 1
		if int(name_counts[resident_name]) == 1:
			id_by_name[resident_name] = resident_id
		else:
			id_by_name.erase(resident_name)
	identity_status = String(prepared.get("status", "unavailable"))
