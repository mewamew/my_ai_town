class_name TownWorldDefinitionState
extends RefCounted


var world_data: Dictionary = {}
var base_world_data: Dictionary = {}
var opening: Dictionary = {}
var owners: Dictionary = {}


func reset() -> void:
	world_data.clear()
	base_world_data.clear()
	opening.clear()
	owners.clear()
