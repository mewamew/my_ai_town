class_name ResidentModelAssignmentRouteMode
extends RefCounted


const NEW_GAME := "new_game"
const IN_SESSION := "in_session"
const RESIDENT_ADMISSION := "resident_admission"
const SAVE_SLOT := "save_slot"
const VALUES: Array[String] = [
	NEW_GAME,
	IN_SESSION,
	RESIDENT_ADMISSION,
	SAVE_SLOT,
]


static func normalize(value: Variant) -> String:
	var mode := String(value).strip_edges()
	return mode if VALUES.has(mode) else NEW_GAME


static func is_in_session(mode: String) -> bool:
	return mode in [IN_SESSION, RESIDENT_ADMISSION]


static func is_single_resident(mode: String) -> bool:
	return mode == RESIDENT_ADMISSION


static func is_save_slot(mode: String) -> bool:
	return mode == SAVE_SLOT
