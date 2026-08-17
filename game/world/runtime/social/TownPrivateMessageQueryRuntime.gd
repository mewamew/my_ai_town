class_name TownPrivateMessageQueryRuntime
extends RefCounted


static func distribution_token(
	host,
	source_ref: String,
	context_hint: String,
) -> String:
	return host.private_message_runtime.distribution_token(
		source_ref,
		context_hint,
		int(host._environment.get_absolute_minute()),
	)


static func message(host, message_id: String) -> Dictionary:
	if not host.private_message_runtime.has(message_id):
		return {}
	return host.private_message_runtime.public_message(
		host.private_message_runtime.message(message_id),
		host.resident_registry.name_by_id,
	)
