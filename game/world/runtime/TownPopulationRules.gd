class_name TownPopulationRules
extends RefCounted


const MIN_RESIDENT_COUNT := 1
const DEFAULT_RESIDENT_COUNT := 15
const MAX_RESIDENT_COUNT := 15


static func supports_resident_count(count: int) -> bool:
	return count >= MIN_RESIDENT_COUNT and count <= MAX_RESIDENT_COUNT


static func rule_snapshot() -> Dictionary:
	return {
		"minimum": MIN_RESIDENT_COUNT,
		"default": DEFAULT_RESIDENT_COUNT,
		"maximum": MAX_RESIDENT_COUNT,
	}
