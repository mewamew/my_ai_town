class_name TownConsumedServiceItemProjection
extends RefCounted


const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)


static func activity_state_after_consumption(
	activity_state: Dictionary,
	item_id: String,
) -> Dictionary:
	var result := activity_state.duplicate(true)
	if item_id == "meal":
		result["satiety"] = clampi(int(result.get("satiety", 50)) + 35, 0, 100)
	elif item_id in [CONTENT_CATALOG.ITEM_BREWED_COFFEE, "pastry"]:
		result["energy"] = clampi(int(result.get("energy", 50)) + 15, 0, 100)
		if item_id == "pastry":
			result["satiety"] = clampi(int(result.get("satiety", 50)) + 12, 0, 100)
	else:
		return {}
	return result
