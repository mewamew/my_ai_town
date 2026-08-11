class_name TownProviderConfigStore
extends RefCounted


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const PROVIDER_STORE_FILES := preload(
	"res://world/presentation/ui/TownProviderStoreFiles.gd"
)
const DEFAULT_PATH := "user://provider_settings.json"
const SCHEMA_VERSION := 2
const PLAINTEXT_CREDENTIAL_KEYS := [
	"apikey",
	"apikeyvalue",
	"authorization",
	"credential",
	"credentials",
	"secret",
	"token",
]
const PROVIDER_CONFIG_KEYS := [
	"enabled",
	"apiKeyRef",
	"endpoint",
	"apiModels",
	"api_key",
	"connectionType",
	"displayName",
	"authRequired",
]

var _path := DEFAULT_PATH


func configure(path: Variant = DEFAULT_PATH) -> Dictionary:
	if typeof(path) != TYPE_STRING:
		return _failure("PROVIDER_CONFIG_PATH_INVALID")
	var candidate := path as String
	if candidate != candidate.strip_edges() or not _user_storage_path_is_valid(candidate):
		return _failure("PROVIDER_CONFIG_PATH_INVALID")
	_path = candidate
	return _success()


func load_config() -> Dictionary:
	var backup_path := "%s.bak" % _path
	_remove_file_if_present("%s.tmp" % _path)
	if not FileAccess.file_exists(_path):
		if FileAccess.file_exists(backup_path):
			var restored := _restore_backup(backup_path)
			if not bool(restored.get("ok", false)):
				return restored
		else:
			return _success({"config": _empty_config()})
	var loaded := _read_validated_config(_path, true)
	if bool(loaded.get("ok", false)):
		_remove_file_if_present(backup_path)
		return loaded
	if not FileAccess.file_exists(backup_path):
		return loaded
	var recovered := _restore_backup(backup_path)
	return recovered if bool(recovered.get("ok", false)) else loaded


func save_config(config_value: Variant) -> Dictionary:
	if typeof(config_value) != TYPE_DICTIONARY:
		return _failure("PROVIDER_CONFIG_INVALID")
	var config := config_value as Dictionary
	if config.has("schemaVersion"):
		var input_schema: Variant = config.get("schemaVersion")
		if (
			typeof(input_schema) != TYPE_INT
			or int(input_schema) not in [1, SCHEMA_VERSION]
		):
			return _failure("PROVIDER_CONFIG_SCHEMA_UNSUPPORTED")
	var normalized := config.duplicate(true)
	normalized["schemaVersion"] = SCHEMA_VERSION
	var validation := _validate_config(normalized, false)
	if not bool(validation.get("ok", false)):
		return validation
	var recovered := load_config()
	if not bool(recovered.get("ok", false)):
		return recovered
	var temporary_path := "%s.tmp" % _path
	var backup_path := "%s.bak" % _path
	_remove_file_if_present(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("PROVIDER_CONFIG_WRITE_FAILED")
	file.store_string(JSON.stringify(normalized, "\t"))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		_remove_file_if_present(temporary_path)
		return _failure("PROVIDER_CONFIG_WRITE_FAILED")
	var written := _read_validated_config(temporary_path, false)
	if (
		not bool(written.get("ok", false))
		or written.get("config", {}) != normalized
	):
		_remove_file_if_present(temporary_path)
		return _failure("PROVIDER_CONFIG_WRITE_VALIDATION_FAILED")
	var replaced := _replace_validated_file(
		temporary_path,
		_path,
		backup_path,
	)
	if replaced != OK:
		_remove_file_if_present(temporary_path)
		return _failure("PROVIDER_CONFIG_WRITE_FAILED")
	return _success()


func clear() -> Dictionary:
	var changed := false
	for candidate: String in [_path, "%s.tmp" % _path, "%s.bak" % _path]:
		if not FileAccess.file_exists(candidate):
			continue
		var error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(candidate)
		)
		if error != OK:
			return _failure("PROVIDER_CONFIG_DELETE_FAILED")
		changed = true
	return _success({"changed": changed})


func _read_validated_config(
	path: String,
	allow_legacy_plaintext: bool,
) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("PROVIDER_CONFIG_READ_FAILED")
	var content := file.get_as_text()
	var read_error := file.get_error()
	file = null
	if read_error != OK:
		return _failure("PROVIDER_CONFIG_READ_FAILED")
	var parsed: Variant = JSON.parse_string(content)
	if not parsed is Dictionary:
		return _failure("PROVIDER_CONFIG_INVALID")
	var config := (parsed as Dictionary).duplicate(true)
	var disk_schema: Variant = config.get("schemaVersion", 1)
	if (
		typeof(disk_schema) == TYPE_FLOAT
		and is_finite(float(disk_schema))
		and float(disk_schema) == floorf(float(disk_schema))
	):
		disk_schema = int(disk_schema)
		config["schemaVersion"] = disk_schema
	if typeof(disk_schema) == TYPE_INT and int(disk_schema) == 1:
		config["schemaVersion"] = SCHEMA_VERSION
	config = _migrate_legacy_custom_model(config)
	var validation := _validate_config(config, allow_legacy_plaintext)
	if not bool(validation.get("ok", false)):
		return validation
	return _success({"config": config})


func _migrate_legacy_custom_model(config: Dictionary) -> Dictionary:
	var migrated := config.duplicate(true)
	var providers_value: Variant = migrated.get("providers", {})
	if not providers_value is Dictionary:
		return migrated
	var providers := providers_value as Dictionary
	var selected_models_value: Variant = migrated.get("selectedModelByProvider", {})
	var selected_models: Dictionary = (
		(selected_models_value as Dictionary).duplicate(true)
		if selected_models_value is Dictionary
		else {}
	)
	for provider_id_value: Variant in providers.keys():
		var provider_value: Variant = providers.get(provider_id_value)
		if not provider_value is Dictionary:
			continue
		var provider := (provider_value as Dictionary).duplicate(true)
		var legacy_value: Variant = provider.get("apiModel")
		if typeof(legacy_value) != TYPE_STRING:
			continue
		var legacy_model := (legacy_value as String).strip_edges()
		provider.erase("apiModel")
		if not legacy_model.is_empty():
			var models: Array = (
				(provider.get("apiModels", []) as Array).duplicate()
				if provider.get("apiModels", []) is Array
				else []
			)
			if legacy_model not in models:
				models.append(legacy_model)
			provider["apiModels"] = models
			var provider_id := String(provider_id_value)
			if String(selected_models.get(provider_id, "")) in ["", "custom"]:
				selected_models[provider_id] = legacy_model
		providers[provider_id_value] = provider
	migrated["providers"] = providers
	migrated["selectedModelByProvider"] = selected_models
	return migrated


func _validate_config(
	config: Dictionary,
	allow_legacy_plaintext: bool,
) -> Dictionary:
	if (
		config.size() != 4
		or not config.has("schemaVersion")
		or not config.has("selectedProviderId")
		or not config.has("selectedModelByProvider")
		or not config.has("providers")
	):
		return _failure("PROVIDER_CONFIG_INVALID")
	for key_value: Variant in config.keys():
		if (
			typeof(key_value) != TYPE_STRING
			or key_value not in [
				"schemaVersion",
				"selectedProviderId",
				"selectedModelByProvider",
				"providers",
			]
		):
			return _failure("PROVIDER_CONFIG_INVALID")
	var schema_value: Variant = config.get("schemaVersion")
	if typeof(schema_value) != TYPE_INT:
		return _failure("PROVIDER_CONFIG_SCHEMA_UNSUPPORTED")
	if int(schema_value) != SCHEMA_VERSION:
		return _failure("PROVIDER_CONFIG_SCHEMA_UNSUPPORTED")
	var selected_provider: Variant = config.get("selectedProviderId", "")
	if typeof(selected_provider) != TYPE_STRING:
		return _failure("PROVIDER_CONFIG_INVALID")
	if not _provider_id_is_valid(selected_provider as String, true):
		return _failure("PROVIDER_CONFIG_INVALID")
	var selected_models: Variant = config.get("selectedModelByProvider", {})
	if not selected_models is Dictionary:
		return _failure("PROVIDER_CONFIG_INVALID")
	for provider_id_value: Variant in (selected_models as Dictionary).keys():
		if (
			typeof(provider_id_value) != TYPE_STRING
			or not _provider_id_is_valid(provider_id_value as String)
		):
			return _failure("PROVIDER_CONFIG_INVALID")
		var model_id: Variant = (selected_models as Dictionary).get(
			provider_id_value
		)
		if (
			typeof(model_id) != TYPE_STRING
			or not _model_id_is_valid(model_id as String)
		):
			return _failure("PROVIDER_CONFIG_INVALID")
	var providers_value: Variant = config.get("providers", {})
	if not providers_value is Dictionary:
		return _failure("PROVIDER_CONFIG_INVALID")
	if _contains_plaintext_credential(config):
		if (
			not allow_legacy_plaintext
			or not _only_supported_legacy_plaintext(config)
		):
			return _failure("PROVIDER_CONFIG_PLAINTEXT_CREDENTIAL_FORBIDDEN")
	for provider_id_value: Variant in (providers_value as Dictionary).keys():
		if (
			typeof(provider_id_value) != TYPE_STRING
			or not _provider_id_is_valid(provider_id_value as String)
		):
			return _failure("PROVIDER_CONFIG_INVALID")
		var provider_value: Variant = (providers_value as Dictionary).get(
			provider_id_value
		)
		if not provider_value is Dictionary:
			return _failure("PROVIDER_CONFIG_INVALID")
		var provider := provider_value as Dictionary
		if not _provider_config_shape_is_valid(provider):
			return _failure("PROVIDER_CONFIG_INVALID")
		if provider.has("enabled") and typeof(provider.get("enabled")) != TYPE_BOOL:
			return _failure("PROVIDER_CONFIG_INVALID")
		if provider.has("apiKeyRef"):
			var reference: Variant = provider.get("apiKeyRef")
			if (
				typeof(reference) != TYPE_STRING
				or (
					not (reference as String).is_empty()
					and reference != _key_ref(provider_id_value as String)
				)
			):
				return _failure("PROVIDER_CONFIG_INVALID")
		if provider.has("endpoint"):
			var endpoint: Variant = provider.get("endpoint")
			if (
				typeof(endpoint) != TYPE_STRING
				or (
					not (endpoint as String).is_empty()
					and not _endpoint_is_valid(endpoint as String)
				)
			):
				return _failure("PROVIDER_CONFIG_INVALID")
		if provider.has("apiModels"):
			var models_value: Variant = provider.get("apiModels")
			if not models_value is Array:
				return _failure("PROVIDER_CONFIG_INVALID")
			var known_models: Dictionary = {}
			for model_value: Variant in models_value as Array:
				if (
					typeof(model_value) != TYPE_STRING
					or not _model_id_is_valid(model_value as String)
					or known_models.has(model_value)
				):
					return _failure("PROVIDER_CONFIG_INVALID")
				known_models[model_value] = true
		if provider.has("connectionType"):
			var connection_type: Variant = provider.get("connectionType")
			if (
				typeof(connection_type) != TYPE_STRING
				or connection_type != "openai-compatible-profile"
			):
				return _failure("PROVIDER_CONFIG_INVALID")
		if provider.has("displayName"):
			var display_name: Variant = provider.get("displayName")
			if (
				typeof(display_name) != TYPE_STRING
				or not _display_name_is_valid(display_name as String)
			):
				return _failure("PROVIDER_CONFIG_INVALID")
		if provider.has("authRequired") and typeof(
			provider.get("authRequired")
		) != TYPE_BOOL:
			return _failure("PROVIDER_CONFIG_INVALID")
	if not _json_safe(config):
		return _failure("PROVIDER_CONFIG_INVALID")
	return _success()


func _provider_config_shape_is_valid(provider: Dictionary) -> bool:
	for key_value: Variant in provider.keys():
		if (
			typeof(key_value) != TYPE_STRING
			or key_value not in PROVIDER_CONFIG_KEYS
		):
			return false
	return true


func _display_name_is_valid(display_name: String) -> bool:
	if (
		display_name.is_empty()
		or display_name != display_name.strip_edges()
		or display_name.length() > 48
	):
		return false
	for character: String in display_name:
		var codepoint := character.unicode_at(0)
		if codepoint < 32 or codepoint == 127:
			return false
	return true


func _endpoint_is_valid(endpoint: String) -> bool:
	var scheme := ""
	if endpoint.begins_with("https://"):
		scheme = "https://"
	elif endpoint.begins_with("http://"):
		scheme = "http://"
	if (
		endpoint != endpoint.strip_edges()
		or scheme.is_empty()
		or endpoint.contains("?")
		or endpoint.contains("#")
		or endpoint.contains("@")
		or endpoint.contains("\\")
	):
		return false
	for character: String in endpoint:
		var codepoint := character.unicode_at(0)
		if codepoint <= 32 or codepoint == 127:
			return false
	var remainder := endpoint.trim_prefix(scheme)
	var slash_index := remainder.find("/")
	var authority := remainder if slash_index < 0 else remainder.left(slash_index)
	if authority.is_empty():
		return false
	var host := authority
	var port := ""
	if authority.begins_with("["):
		var bracket_index := authority.find("]")
		if bracket_index <= 1:
			return false
		host = authority.left(bracket_index + 1)
		var suffix := authority.substr(bracket_index + 1)
		if not suffix.is_empty():
			if not suffix.begins_with(":"):
				return false
			port = suffix.trim_prefix(":")
	else:
		if authority.count(":") > 1:
			return false
		var colon_index := authority.rfind(":")
		if colon_index >= 0:
			host = authority.left(colon_index)
			port = authority.substr(colon_index + 1)
	if host.is_empty() or host.begins_with(".") or host.ends_with("."):
		return false
	if scheme == "http://" and not _loopback_host_is_valid(host):
		return false
	if host.begins_with("["):
		var address := host.substr(1, host.length() - 2)
		if not address.is_valid_ip_address():
			return false
	else:
		if host.length() > 253:
			return false
		var normalized_host := host.to_lower()
		var numeric_host := true
		for character: String in normalized_host:
			if character not in "0123456789.":
				numeric_host = false
				break
		if numeric_host and not _canonical_ipv4_is_valid(normalized_host):
			return false
		for label: String in normalized_host.split("."):
			if (
				label.is_empty()
				or label.length() > 63
				or label.begins_with("-")
				or label.ends_with("-")
			):
				return false
			for character: String in label:
				if character not in "0123456789abcdefghijklmnopqrstuvwxyz-":
					return false
	if not port.is_empty():
		if not TownSaveScalars.ascii_digits(port):
			return false
		var port_number := int(port)
		if (
			port_number < 1
			or port_number > 65535
			or str(port_number) != port
		):
			return false
	elif authority.ends_with(":"):
		return false
	return true


func _loopback_host_is_valid(host: String) -> bool:
	var normalized := host.to_lower()
	if normalized == "localhost" or normalized == "[::1]":
		return true
	return normalized.begins_with("127.") and _canonical_ipv4_is_valid(normalized)


func _canonical_ipv4_is_valid(host: String) -> bool:
	var labels := host.split(".", false)
	if labels.size() != 4:
		return false
	for label: String in labels:
		if not TownSaveScalars.ascii_digits(label):
			return false
		var octet := int(label)
		if octet < 0 or octet > 255 or str(octet) != label:
			return false
	return true


func _model_id_is_valid(model_id: String) -> bool:
	if model_id.is_empty() or model_id != model_id.strip_edges():
		return false
	for character: String in model_id:
		var codepoint := character.unicode_at(0)
		if codepoint < 32 or codepoint == 127:
			return false
	return true


func _contains_plaintext_credential(value: Variant) -> bool:
	if value is Dictionary:
		for key_value: Variant in (value as Dictionary).keys():
			if typeof(key_value) != TYPE_STRING:
				return true
			var normalized_key := (
				(key_value as String).to_lower().replace("_", "").replace("-", "")
			)
			if (
				normalized_key in PLAINTEXT_CREDENTIAL_KEYS
				and normalized_key != "apikeyref"
			):
				return true
			if _contains_plaintext_credential((value as Dictionary)[key_value]):
				return true
	elif value is Array:
		for item: Variant in value as Array:
			if _contains_plaintext_credential(item):
				return true
	return false


func _only_supported_legacy_plaintext(config: Dictionary) -> bool:
	var scrubbed := config.duplicate(true)
	var providers_value: Variant = scrubbed.get("providers", {})
	if not providers_value is Dictionary:
		return false
	var providers := providers_value as Dictionary
	for provider_id_value: Variant in providers.keys():
		var provider_value: Variant = providers.get(provider_id_value)
		if not provider_value is Dictionary:
			return false
		var provider := provider_value as Dictionary
		if not provider.has("api_key"):
			continue
		var key_value: Variant = provider.get("api_key")
		if (
			typeof(key_value) != TYPE_STRING
			or (key_value as String).strip_edges().is_empty()
		):
			return false
		provider.erase("api_key")
	return not _contains_plaintext_credential(scrubbed)


func _json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for item: Variant in value as Array:
				if not _json_safe(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key_value: Variant in (value as Dictionary).keys():
				if (
					typeof(key_value) != TYPE_STRING
					or not _json_safe((value as Dictionary)[key_value])
				):
					return false
			return true
	return false


func _provider_id_is_valid(provider_id: String, allow_empty := false) -> bool:
	if provider_id.is_empty():
		return allow_empty
	if provider_id != provider_id.strip_edges():
		return false
	for character: String in provider_id:
		if character not in "0123456789abcdefghijklmnopqrstuvwxyz-_":
			return false
	return true


func _user_storage_path_is_valid(path: String) -> bool:
	return PROVIDER_STORE_FILES.user_storage_path_is_valid(path)


func _restore_backup(backup_path: String) -> Dictionary:
	var backup := _read_validated_config(backup_path, true)
	if not bool(backup.get("ok", false)):
		return _failure("PROVIDER_CONFIG_RECOVERY_FAILED")
	_remove_file_if_present(_path)
	var restore_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(backup_path),
		ProjectSettings.globalize_path(_path),
	)
	if restore_error != OK:
		return _failure("PROVIDER_CONFIG_RECOVERY_FAILED")
	return backup


func _replace_validated_file(
	temporary_path: String,
	final_path: String,
	backup_path: String,
) -> Error:
	return PROVIDER_STORE_FILES.replace_validated_file(temporary_path, final_path, backup_path)


func _remove_file_if_present(path: String) -> void:
	PROVIDER_STORE_FILES.remove_file_if_present(path)


func _empty_config() -> Dictionary:
	return {
		"schemaVersion": SCHEMA_VERSION,
		"selectedProviderId": "",
		"selectedModelByProvider": {},
		"providers": {},
	}


func _key_ref(provider_id: String) -> String:
	return "secure_store.llm.%s.api_key" % provider_id


func _success(extra: Dictionary = {}) -> Dictionary:
	return RESULT_SHAPES.success_with(extra)


func _failure(error_code: String) -> Dictionary:
	return RESULT_SHAPES.failure(error_code)
