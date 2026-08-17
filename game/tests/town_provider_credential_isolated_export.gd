extends SceneTree


const TARGET_ENV := "AI_TOWN_QA_PROJECT_NAME"
const SOURCE_STORE := preload(
	"res://world/presentation/ui/TownProviderCredentialStore.gd"
)
const EXPORT_PATH := "user://provider_credentials.qa_export.enc"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var target_name := OS.get_environment(TARGET_ENV).strip_edges()
	if target_name.is_empty() or target_name == "ai-town":
		printerr("TOWN_PROVIDER_CREDENTIAL_ISOLATED_EXPORT_FAIL: target")
		quit(1)
		return
	var source: RefCounted = SOURCE_STORE.new()
	var api_key := OS.get_environment("DEEPSEEK_API_KEY").strip_edges()
	if api_key.is_empty():
		var loaded := source.call("api_key", "deepseek") as Dictionary
		api_key = String(loaded.get("apiKey", ""))
	if api_key.is_empty():
		printerr("TOWN_PROVIDER_CREDENTIAL_ISOLATED_EXPORT_FAIL: source")
		quit(1)
		return
	ProjectSettings.set_setting("application/config/name", target_name)
	var user_root := ProjectSettings.globalize_path("user://")
	var directory_error := DirAccess.make_dir_recursive_absolute(user_root)
	if directory_error != OK:
		api_key = ""
		printerr("TOWN_PROVIDER_CREDENTIAL_ISOLATED_EXPORT_FAIL: directory")
		quit(1)
		return
	var destination: RefCounted = SOURCE_STORE.new()
	var configured := destination.call("configure", EXPORT_PATH) as Dictionary
	var saved := (
		destination.call("save_api_key", "deepseek", api_key) as Dictionary
		if bool(configured.get("ok", false))
		else configured
	)
	api_key = ""
	if not bool(saved.get("ok", false)):
		destination = null
		source = null
		printerr("TOWN_PROVIDER_CREDENTIAL_ISOLATED_EXPORT_FAIL: destination")
		quit(1)
		return
	destination = null
	source = null
	for _index in 2:
		await process_frame
	_prepare_audio_shutdown()
	print("TOWN_PROVIDER_CREDENTIAL_ISOLATED_EXPORT_PASS")
	quit(0)


func _prepare_audio_shutdown() -> void:
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
