class_name UnavailableModelProvider
extends "res://agent/model/ModelProvider.gd"


const ERROR_CODE := "LLM_MODEL_UNAVAILABLE"


func get_provider_descriptor() -> Dictionary:
	return {
		"id": "unavailable",
		"label": "模型不可用",
		"transport_label": "等待重新配置",
		"external": false,
	}


func request_decision(_model_request: Dictionary, on_complete: Callable) -> void:
	if on_complete.is_valid():
		on_complete.call({
			"ok": false,
			"errorCode": ERROR_CODE,
			"retryable": false,
			"errors": ["当前模型不可用，请先在模型设置中重新配置。"],
		})


func cancel_request(_request_id: String) -> bool:
	return false


func cancel_all_requests() -> int:
	return 0
