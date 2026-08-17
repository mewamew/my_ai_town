class_name TownWorldActorPresentationState
extends RefCounted


var player_avatar: Dictionary = {}
var player_avatar_present := true
var observed_action_preview_resident_id := ""


func reset() -> void:
	player_avatar.clear()
	player_avatar_present = true
	observed_action_preview_resident_id = ""
