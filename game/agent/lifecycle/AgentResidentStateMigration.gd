class_name AgentResidentStateMigration
extends RefCounted


const MIGRATION_VERSION := 1
const SHOP_OWNER_DERIVATION_MIGRATION_ID := (
	"2026-08-24-shop-owner-derived-from-occupation"
)


static func migrate(value: Dictionary) -> Dictionary:
	var state := value.duplicate(true)
	var initialization_value: Variant = state.get("initialization")
	if not initialization_value is Dictionary:
		return _result(state, false)
	var initialization := initialization_value as Dictionary
	var places_value: Variant = initialization.get("places")
	if not places_value is Array:
		return _result(state, false)
	var resident_names := _resident_names(initialization)
	var changed := false
	for place_value: Variant in places_value as Array:
		if not place_value is Dictionary:
			continue
		var place := place_value as Dictionary
		if String(place.get("type", "")) != "铺面":
			continue
		var owner_value: Variant = place.get("owner")
		var owner_id_value: Variant = place.get("owner_resident_id")
		if (
			owner_value is String
			and not String(owner_value).is_empty()
			and owner_id_value is String
			and not String(owner_id_value).is_empty()
			and resident_names.get(String(owner_id_value)) == owner_value
		):
			place["owner"] = null
			place["owner_resident_id"] = null
			changed = true
	state["initialization"] = initialization
	return _result(state, changed)


static func _resident_names(initialization: Dictionary) -> Dictionary:
	var names := {}
	var me_value: Variant = initialization.get("me")
	if me_value is Dictionary:
		var me := me_value as Dictionary
		var attributes_value: Variant = me.get("attributes")
		if attributes_value is Dictionary:
			names[String(me.get("resident_id", ""))] = String(
				(attributes_value as Dictionary).get("name", ""),
			)
	var residents_value: Variant = initialization.get("residents")
	if residents_value is Array:
		for resident_value: Variant in residents_value as Array:
			if resident_value is Dictionary:
				var resident := resident_value as Dictionary
				names[String(resident.get("resident_id", ""))] = String(
					resident.get("name", ""),
				)
	names.erase("")
	return names


static func _result(state: Dictionary, changed: bool) -> Dictionary:
	return {
		"ok": true,
		"state": state,
		"applied": (
			[SHOP_OWNER_DERIVATION_MIGRATION_ID]
			if changed
			else []
		),
		"migrationVersion": MIGRATION_VERSION,
	}
