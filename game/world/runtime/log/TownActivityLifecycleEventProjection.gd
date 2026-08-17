class_name TownActivityLifecycleEventProjection
extends RefCounted


const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)


static func event(
	lifecycle: String,
	execution: Dictionary,
	reason: String,
	time: Dictionary,
) -> Dictionary:
	var label := String(
		execution.get("label", execution.get("activityLabel", "活动"))
	)
	var result_text := ""
	match lifecycle:
		"started":
			result_text = "开始%s" % label
		"completed":
			result_text = "完成%s" % label
		"interrupted":
			result_text = "%s被中断" % label
		"failed":
			result_text = "%s未能完成" % label
		_:
			return {}
	if not reason.strip_edges().is_empty() and lifecycle in [
		"interrupted",
		"failed",
	]:
		result_text = "%s：%s" % [result_text, reason.strip_edges()]
	var activity_id := String(execution.get("activityId", ""))
	return {
		"activityId": activity_id,
		"label": label,
		"baseIconKey": ACTION_PRESENTATION.activity_icon_key(activity_id),
		"phase": lifecycle,
		"placeId": String(execution.get("placeId", "")),
		"role": String(execution.get("role", "")),
		"result": result_text,
		"time": time.duplicate(true),
	}
