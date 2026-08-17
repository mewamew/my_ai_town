class_name TownDynamicPropCommandRuntime
extends RefCounted


const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)


static func upsert(
	host,
	prop_id: String,
	display_name: String,
	position: Vector2,
	active: bool = true,
) -> Dictionary:
	var identity: Dictionary = host._dynamic_prop_runtime.normalize_identity(
		prop_id,
		display_name,
	)
	if identity.get("ok") != true:
		return identity
	host.place_presentation_query.clear_presentation_cue_cache()
	var placement := (
		PERCEPTION_RUNTIME.dynamic_prop_placement(host, position)
		if active and host._running
		else {}
	)
	return host._dynamic_prop_runtime.upsert_normalized(
		identity,
		position,
		active,
		host._running,
		placement,
	)
