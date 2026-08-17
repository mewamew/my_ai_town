class_name TownWorldLogDomainState
extends RefCounted


const EVENT_JOURNAL_RUNTIME := preload(
	"res://world/runtime/log/TownWorldEventJournalRuntime.gd"
)
const WORLD_LOG_STORE := preload(
	"res://world/runtime/log/TownWorldLogStore.gd"
)

var journal: TownWorldEventJournalRuntime = EVENT_JOURNAL_RUNTIME.new()
var store: RefCounted = WORLD_LOG_STORE.new()
var capture_enabled := false


func reset() -> void:
	journal.reset()
	store = WORLD_LOG_STORE.new()
	store.reset()
	capture_enabled = false
