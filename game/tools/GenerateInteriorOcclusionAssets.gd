extends SceneTree

const GENERATOR := preload(
	"res://tools/interiors/InteriorOcclusionAssetGenerator.gd"
)
const ROOMS_ROOT := "res://world/maps/town/interiors/redesign_v2/rooms"
const ROOM_IDS: Array[String] = [
	"cafe",
	"clinic",
	"dining_hall",
	"dock_warehouse",
	"home_template_a",
	"home_template_b",
	"library",
	"market_shop",
	"town_hall",
	"workshop",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var generator := GENERATOR.new()
	var result := generator.generate(ROOMS_ROOT, ROOM_IDS) as Dictionary
	generator = null
	if result.get("ok") == true:
		print("INTERIOR_OCCLUSION_ASSETS_GENERATED: %d rooms" % ROOM_IDS.size())
		_prepare_audio_shutdown()
		call_deferred("_quit_after_cleanup", 0)
		return
	printerr(
		"INTERIOR_OCCLUSION_ASSET_ERROR: %s" % String(result.get("error", "unknown")),
	)
	_prepare_audio_shutdown()
	call_deferred("_quit_after_cleanup", 1)


func _quit_after_cleanup(exit_code: int) -> void:
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	quit(exit_code)


func _prepare_audio_shutdown() -> void:
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
