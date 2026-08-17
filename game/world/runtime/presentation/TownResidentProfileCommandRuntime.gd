class_name TownResidentProfileCommandRuntime
extends RefCounted


const PROFILE_EDITOR := preload(
	"res://world/runtime/presentation/TownResidentProfileEditor.gd"
)


static func update_social(
	host,
	resident_ref: String,
	profile: Dictionary,
	place_detail: Callable,
) -> Dictionary:
	var resident_id_result := editable_resident_id(host, resident_ref)
	if resident_id_result.get("ok") != true:
		return resident_id_result
	var validation := PROFILE_EDITOR.validate_social_profile(profile, place_detail)
	if validation.get("ok") != true:
		return host._command_failure(
			String(validation.get("errorCode", "RESIDENT_PROFILE_INVALID")),
			validation.get("errors", []) as Array,
		)
	return commit(
		host,
		String(resident_id_result.get("residentId", "")),
		{},
		validation.get("profile", {}) as Dictionary,
	)


static func update(
	host,
	resident_ref: String,
	profile: Dictionary,
	place_detail: Callable,
) -> Dictionary:
	var resident_id_result := editable_resident_id(host, resident_ref)
	if resident_id_result.get("ok") != true:
		return resident_id_result
	var validation := PROFILE_EDITOR.validate_profile(profile, place_detail)
	if validation.get("ok") != true:
		return host._command_failure(
			String(validation.get("errorCode", "RESIDENT_PROFILE_INVALID")),
			validation.get("errors", []) as Array,
		)
	return commit(
		host,
		String(resident_id_result.get("residentId", "")),
		validation.get("attributes", {}) as Dictionary,
		validation.get("profile", {}) as Dictionary,
	)


static func editable_resident_id(host, resident_ref: String) -> Dictionary:
	if not host._running:
		return host._command_failure(
			"WORLD_NOT_RUNNING",
			["世界尚未运行，不能修改居民本局资料"],
		)
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return host._command_failure(
			"RESIDENT_IDENTITY_NOT_FOUND",
			["没有找到居民：%s" % resident_ref],
		)
	return {"ok": true, "residentId": resident_id}


static func commit(
	host,
	resident_id: String,
	profile_attributes: Dictionary,
	social_profile: Dictionary,
) -> Dictionary:
	var applied := PROFILE_EDITOR.apply(
		host.resident_registry.records[resident_id] as Dictionary,
		profile_attributes,
		social_profile,
	)
	var changed := bool(applied.get("changed", false))
	if changed:
		host._bump_world_revision(false)
		host._emit_resident_state_changed(resident_id)
		host._notify_world_revision()
	return host._decorate_command_result({
		"ok": true,
		"changed": changed,
		"residentId": resident_id,
		"profile": (
			applied.get("profile", {}) as Dictionary
		).duplicate(true),
		"attributes": (
			applied.get("attributes", {}) as Dictionary
		).duplicate(true),
	})
