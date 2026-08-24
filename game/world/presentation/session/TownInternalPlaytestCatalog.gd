class_name TownInternalPlaytestCatalog
extends RefCounted


const FORMAL_CATALOG := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)


static func build_view_model(provider_id: String, model_id: String) -> Dictionary:
	var source := FORMAL_CATALOG.build_view_model(
		provider_id,
		model_id,
		true,
		1,
	) as Dictionary
	if source.is_empty():
		return {}
	var view_model := source.duplicate(true)
	var data := view_model.get("data", {}) as Dictionary
	var residents := data.get("residents", []) as Array
	var selected_ids: Array[String] = []
	for index in mini(15, residents.size()):
		selected_ids.append(String((residents[index] as Dictionary).get("resident_id", "")))
	data["capabilityMode"] = "development"
	data["source"] = "placeholder"
	data["formalReady"] = false
	data["internalPlaytest"] = true
	data["selection_limit"] = 15
	data["connection_label"] = "开发内测 · 显式 placeholder · Save/Continue 禁用"
	data["resident_catalog_status"] = "development-placeholder"
	data["selected_resident_ids"] = selected_ids.duplicate()
	data["recommended_resident_ids"] = selected_ids.duplicate()
	update_confirmation_payload(data, provider_id, model_id, 1)
	var actions := view_model.get("actions", {}) as Dictionary
	var confirm := actions.get("confirm", {}) as Dictionary
	confirm["enabled"] = true
	confirm["disabled_reason"] = ""
	view_model["scope"] = "resident_selection"
	view_model["status"] = "ready"
	view_model["revision"] = 1
	view_model["operation"] = {
		"requestId": "",
		"intent": "",
		"status": "idle",
		"submittedAtMsec": 0,
		"completedAtMsec": 0,
	}
	view_model["error"] = null
	return view_model


static func update_confirmation_payload(
	data: Dictionary,
	provider_id: String,
	model_id: String,
	draft_revision: int,
) -> void:
	var selected := data.get("selected_resident_ids", []) as Array
	var ordered_ids: Array[String] = []
	for resident_value: Variant in data.get("residents", []) as Array:
		var resident_id := String((resident_value as Dictionary).get("resident_id", ""))
		if selected.has(resident_id):
			ordered_ids.append(resident_id)
	var slots: Array[Dictionary] = []
	for index in mini(15, ordered_ids.size()):
		slots.append({
			"residentId": ordered_ids[index],
			"spaceId": "home_%02d" % (index + 1),
			"llmBinding": {
				"mode": "model",
				"providerId": provider_id,
				"modelId": model_id,
			},
		})
	data["confirmation_payload"] = {
		"schemaVersion": 1,
		"sourceScope": "resident_selection",
		"draftRevision": draft_revision,
		"slots": slots,
	}


static func build_catalog(world_data: Dictionary, view_model: Dictionary) -> Dictionary:
	if view_model.is_empty():
		return {}
	var catalog_values := (
		(view_model.get("data", {}) as Dictionary).get("resident_catalog", [])
		as Array
	)
	var residents: Array[Dictionary] = []
	for value: Variant in catalog_values:
		if not value is Dictionary:
			continue
		var entry := (value as Dictionary).duplicate(true)
		var occupation := entry.get("occupation", {}) as Dictionary
		if String(occupation.get("workplacePlace", "")) == "市集铺面":
			occupation["workplacePlace"] = "独立市集"
		residents.append(entry)
	return {
		"schemaVersion": 1,
		"worldId": String(world_data.get("worldId", "")),
		"openingDefaults": {
			"environment": {
				"day": 1,
				"clock": "08:00",
				"weather": "晴天",
				"randomSeed": 20260720,
			},
			"residentBody": {"困": "不困", "饿": "不饿", "累": "不累"},
			"residentDoing": "在{home}整理行李",
			"playerAvatar": {
				"name": "旅行者",
				"worldState": {
					"place": "南入口",
					"spaceId": "town_outdoor",
					"regionId": "outdoor_south_gate_01",
					"position": [3204, 3180],
					"doing": "刚刚抵达小镇",
				},
			},
			},
			"residents": residents,
		}


static func default_model_id(provider_id: String) -> String:
	match provider_id:
		"deepseek":
			return "deepseek-v4-flash"
		"zhipu-glm":
			return "glm-5.2"
		"kimi":
			return "kimi-k2.6"
		_:
			return "fake"
