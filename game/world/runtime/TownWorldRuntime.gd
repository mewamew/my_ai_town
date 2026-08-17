class_name TownWorldRuntime
extends TownWorldContract

signal resident_state_changed(resident_name: String, state: Dictionary)
signal resident_action_started(resident_name: String, action: Dictionary)
signal resident_reaction_created(resident_name: String, reaction: Dictionary)
signal resident_action_phase_changed(resident_id: String, phase: Dictionary)
signal resident_activity_started(resident_id: String, event: Dictionary)
signal resident_activity_completed(resident_id: String, event: Dictionary)
signal resident_activity_interrupted(resident_id: String, event: Dictionary)
signal resident_activity_failed(resident_id: String, event: Dictionary)
signal resident_place_changed(resident_name: String, change: Dictionary)
signal resident_perception_changed(resident_name: String, change: Dictionary)
signal player_avatar_state_changed(state: Dictionary)
signal player_avatar_place_changed(change: Dictionary)
signal player_avatar_perception_changed(change: Dictionary)
signal player_command_result_created(result: Dictionary)
signal world_event_created(resident_name: String, event: Dictionary)
signal action_result_created(resident_name: String, result: Dictionary)
signal story_event_created(event: Dictionary)
signal environment_changed(time: Dictionary, weather: String)
signal announcement_published(announcement: Dictionary)
signal social_matter_changed(summary: Dictionary)
signal conversation_changed(conversation_id: String, state: Dictionary)
signal lifecycle_state_changed(state: Dictionary)
signal world_restored(summary: Dictionary)
signal world_revision_changed(revision: int)
signal world_log_changed(change: Dictionary)
signal simulation_speed_changed(speed: int, world_revision: int)
signal conflict_projection_changed(projection: Dictionary)
signal conflict_event_created(event: Dictionary)
signal conflict_follow_up_required(follow_up: Dictionary)

const OPENING_CONFIG := preload("res://world/runtime/TownWorldOpeningConfig.gd")
const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const WORLD_ENVIRONMENT := preload("res://world/runtime/environment/TownWorldEnvironment.gd")
const WORLD_ADVANCE_RUNTIME := preload("res://world/runtime/time/TownWorldAdvanceRuntime.gd")
const ROUTE_QUERY := preload("res://world/data/town/TownWorldRouteQuery.gd")
const CHARACTER_MOVEMENT_QUERY := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)
const MOVEMENT_CLEARANCE_RUNTIME := preload(
	"res://world/runtime/TownMovementClearanceRuntime.gd"
)
const RESIDENT_POSITION_COMMIT_RUNTIME := preload(
	"res://world/runtime/movement/TownResidentPositionCommitRuntime.gd"
)
const PLAYER_AVATAR_MOVEMENT_COMMAND_RUNTIME := preload(
	"res://world/runtime/movement/TownPlayerAvatarMovementCommandRuntime.gd"
)
const GO_ACTION_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/movement/TownGoActionAdvancementRuntime.gd"
)
const RESIDENT_ARRIVAL_RUNTIME := preload("res://world/runtime/TownResidentArrivalRuntime.gd")
const AGENT_WAKE_STATE_RUNTIME := preload(
	"res://world/runtime/TownAgentWakeStateRuntime.gd"
)
const AGENT_WAKE_PREPARATION_RUNTIME := preload("res://world/runtime/TownAgentWakePreparationRuntime.gd")
const WORLD_PERFORMANCE_PROBE := preload(
	"res://world/runtime/TownWorldPerformanceProbe.gd"
)
const ACTIVITY_OPTION_QUERY := preload(
	"res://world/runtime/activity/TownActivityOptionQuery.gd"
)
const ACTIVITY_REACHABILITY_CACHE := preload("res://world/runtime/activity/TownActivityReachabilityCache.gd")
const ACTIVITY_REGION_ACTION_PREPARER := preload(
	"res://world/runtime/activity/TownActivityRegionActionPreparer.gd"
)
const ACTIVITY_WORK_TASK_BINDING_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityWorkTaskBindingRuntime.gd"
)
const BULLETIN_ACTIVITY_EFFECT_PLANNER := preload(
	"res://world/runtime/activity/TownBulletinActivityEffectPlanner.gd"
)
const ACTIVITY_LIFECYCLE_COMMIT_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityLifecycleCommitRuntime.gd"
)
const ACTIVITY_COMPLETION_PROJECTION := preload(
	"res://world/runtime/activity/TownActivityCompletionProjection.gd"
)
const ACTIVITY_ACTION_SETTLEMENT_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityActionSettlementRuntime.gd"
)
const ACTIVITY_ROUTINE_POLICY := preload(
	"res://world/runtime/activity/TownActivityRoutinePolicy.gd"
)
const LEGACY_PROP_ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownLegacyPropActivityRuntime.gd"
)
const FRAME_BUDGET_RUNTIME := preload(
	"res://world/runtime/presentation/TownWorldFrameBudgetRuntime.gd"
)
const PERFORMANCE_SERVICE_RUNTIME := preload(
	"res://world/runtime/work/TownPerformanceServiceRuntime.gd"
)
const PROP_QUERY := preload("res://world/data/town/TownWorldPropQuery.gd")
const DYNAMIC_PROP_RUNTIME := preload(
	"res://world/runtime/prop/TownDynamicPropRuntime.gd"
)
const PROP_ACTION_PREPARER := preload(
	"res://world/runtime/prop/TownPropActionPreparer.gd"
)
const INDOOR_PATH_QUERY := preload("res://world/data/town/TownIndoorPropPathQuery.gd")
const INDOOR_LAYOUT_PROJECTION := preload(
	"res://world/runtime/TownIndoorLayoutProjection.gd"
)
const SAVE_CODEC := preload("res://world/runtime/persistence/TownWorldSaveCodec.gd")
const SAVE_CANDIDATE_RUNTIME := preload(
	"res://world/runtime/persistence/TownWorldSaveCandidateRuntime.gd"
)
const SAVE_SNAPSHOT_PROJECTION := preload(
	"res://world/runtime/persistence/TownWorldSaveSnapshotProjection.gd"
)
const PERSISTENCE_PREPARATION := preload(
	"res://world/runtime/persistence/TownWorldPersistencePreparation.gd"
)
const RESTORE_COMMIT_PROJECTION := preload(
	"res://world/runtime/persistence/TownWorldRestoreCommitProjection.gd"
)
const RESTORE_COMMIT_RUNTIME := preload(
	"res://world/runtime/persistence/TownWorldRestoreCommitRuntime.gd"
)
const RESTORE_CANDIDATE_RUNTIME := preload(
	"res://world/runtime/persistence/TownWorldRestoreCandidateRuntime.gd"
)
const RESTORE_LAYOUT := preload("res://world/runtime/persistence/TownWorldRestoreLayout.gd")
const RESTORE_PEOPLE := preload("res://world/runtime/persistence/TownWorldRestorePeople.gd")
const RESTORE_WORK := preload("res://world/runtime/persistence/TownWorldRestoreWork.gd")
const ANNOUNCEMENT_PUBLISHER_PROJECTION := preload("res://world/presentation/announcement/TownAnnouncementPublisherProjection.gd")
const WORK_SETTLEMENT := preload(
	"res://world/runtime/work/TownWorkSettlement.gd"
)
const WORK_DOMAIN_RUNTIME := preload(
	"res://world/runtime/work/TownWorkDomainRuntime.gd"
)
const PLACE_SERVICE_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownPlaceServiceCommandRuntime.gd"
)
const RESIDENT_WORK_TASK_PROJECTION := preload(
	"res://world/runtime/work/TownResidentWorkTaskProjection.gd"
)
const CONSUMED_SERVICE_ITEM_PROJECTION := preload(
	"res://world/runtime/work/TownConsumedServiceItemProjection.gd"
)
const CARGO_LOGISTICS_RUNTIME := preload(
	"res://world/runtime/work/TownCargoLogisticsRuntime.gd"
)
const PRODUCTION_TASK_COORDINATION_RUNTIME := preload(
	"res://world/runtime/work/TownProductionTaskCoordinationRuntime.gd"
)
const OCCUPATION_SERVICE_DEFINITION := preload(
	"res://world/runtime/work/TownOccupationServiceDefinition.gd"
)
const WORK_STATE_PROJECTION := preload(
	"res://world/runtime/work/TownWorkStateProjection.gd"
)
const WORK_TASK_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownWorkTaskCommandRuntime.gd"
)
const OCCUPATION_SERVICE_REQUEST_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServiceRequestRuntime.gd"
)
const OCCUPATION_SERVICE_REQUEST_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServiceRequestCommandRuntime.gd"
)
const OCCUPATION_SERVICE_REQUEST_COMMIT := preload(
	"res://world/runtime/work/TownOccupationServiceRequestCommit.gd"
)
const SERVICE_READY_NOTIFICATION_RUNTIME := preload(
	"res://world/runtime/work/TownServiceReadyNotificationRuntime.gd"
)
const CLINIC_SERVICE_REQUEST_POLICY := preload(
	"res://world/runtime/work/TownClinicServiceRequestPolicy.gd"
)
const CUSTOMER_SERVICE_WAIT_RUNTIME := preload(
	"res://world/runtime/work/TownCustomerServiceWaitRuntime.gd"
)
const OCCUPATION_SERVICE_ACTIVITY_POLICY := preload(
	"res://world/runtime/work/TownOccupationServiceActivityPolicy.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const CONVERSATION_STATE := preload(
	"res://world/runtime/conversation/TownConversationState.gd"
)
const CONVERSATION_FOLLOW_UP_OPTION_PROJECTION := preload(
	"res://world/runtime/conversation/TownConversationFollowUpOptionProjection.gd"
)
const CONVERSATION_FOLLOW_UP_OPTION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationFollowUpOptionRuntime.gd"
)
const CONVERSATION_FOLLOW_UP_ACTION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationFollowUpActionRuntime.gd"
)
const CONVERSATION_COMMITMENT_SUBMISSION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationCommitmentSubmissionRuntime.gd"
)
const CONVERSATION_CONFLICT_BRIDGE := preload(
	"res://world/runtime/conversation/TownConversationConflictBridge.gd"
)
const WORLD_LOG_DOMAIN_STATE := preload(
	"res://world/runtime/log/TownWorldLogDomainState.gd"
)
const DOMAIN_LOG_PROJECTION := preload(
	"res://world/runtime/log/TownWorldDomainLogProjection.gd"
)
const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)
const ACTIVITY_LIFECYCLE_EVENT_PROJECTION := preload(
	"res://world/runtime/log/TownActivityLifecycleEventProjection.gd"
)
const RESIDENT_EVENT_QUEUE_RUNTIME := preload(
	"res://world/runtime/event/TownResidentEventQueueRuntime.gd"
)
const WORLD_EVENT_DELIVERY_PROJECTION := preload(
	"res://world/runtime/event/TownWorldEventDeliveryProjection.gd"
)
const WORLD_EVENT_DELIVERY_RUNTIME := preload(
	"res://world/runtime/event/TownWorldEventDeliveryRuntime.gd"
)
const AGENT_DECISION_ACCEPTANCE_POLICY := preload(
	"res://world/runtime/agent/TownAgentDecisionAcceptancePolicy.gd"
)
const AGENT_DECISION_ENVELOPE_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentDecisionEnvelopeRuntime.gd"
)
const AGENT_WAKE_PACKET_PROJECTION := preload(
	"res://world/runtime/agent/TownAgentWakePacketProjection.gd"
)
const AGENT_WAKE_CONTEXT_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentWakeContextRuntime.gd"
)
const AGENT_DECISION_SCHEDULING_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentDecisionSchedulingRuntime.gd"
)
const AGENT_DECISION_SUBMISSION_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentDecisionSubmissionRuntime.gd"
)
const AGENT_DECISION_DISPATCH_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentDecisionDispatchRuntime.gd"
)
const CONFIRMED_ACTION_ACTIVATION_POLICY := preload(
	"res://world/runtime/agent/TownConfirmedActionActivationPolicy.gd"
)
const CONFIRMED_ACTION_ACTIVATION_RUNTIME := preload(
	"res://world/runtime/action/TownConfirmedActionActivationRuntime.gd"
)
const STARTUP_VALIDATOR := preload("res://world/runtime/TownWorldStartupValidator.gd")
const ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownWorldActivityRuntime.gd"
)
const ACTIVITY_ROUTINE_STATE := preload(
	"res://world/runtime/activity/TownActivityRoutineState.gd"
)
const ACTIVITY_EXECUTION_PROJECTION := preload(
	"res://world/runtime/activity/TownActivityExecutionProjection.gd"
)
const ACTIVITY_STEP_EXECUTION_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityStepExecutionRuntime.gd"
)
const ACTIVITY_CANDIDATE_PREFLIGHT_POLICY := preload(
	"res://world/runtime/activity/TownActivityCandidatePreflightPolicy.gd"
)
const AGENT_ACTIVITY_SUBMISSION_RUNTIME := preload(
	"res://world/runtime/activity/TownAgentActivitySubmissionRuntime.gd"
)
const ACTIVITY_ROUTINE_ACTIVATION_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityRoutineActivationRuntime.gd"
)
const ACTIVITY_CANDIDATE_PREFLIGHT_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityCandidatePreflightRuntime.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const WORK_TASK_RUNTIME := preload(
	"res://world/runtime/work/TownWorkTaskRuntime.gd"
)
const STAFFING_RUNTIME := preload(
	"res://world/runtime/work/TownStaffingRuntime.gd"
)
const STAFFING_ASSIGNMENT_POLICY := preload(
	"res://world/runtime/work/TownStaffingAssignmentPolicy.gd"
)
const STAFFING_ASSIGNMENT_COMMIT := preload(
	"res://world/runtime/work/TownStaffingAssignmentCommit.gd"
)
const STAFFING_ASSIGNMENT_SUBMISSION_RUNTIME := preload(
	"res://world/runtime/work/TownStaffingAssignmentSubmissionRuntime.gd"
)
const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const ACTION_PREPARATION_POLICY := preload(
	"res://world/runtime/action/TownActionPreparationPolicy.gd"
)
const ACTION_PREPARATION_RUNTIME := preload(
	"res://world/runtime/action/TownActionPreparationRuntime.gd"
)
const IDLE_ACTION_PREPARATION_RUNTIME := preload(
	"res://world/runtime/action/TownIdleActionPreparationRuntime.gd"
)
const ACTION_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/action/TownActionAdvancementRuntime.gd"
)
const WAIT_ACTION_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/action/TownWaitActionAdvancementRuntime.gd"
)
const PROP_ACTION_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/action/TownPropActionAdvancementRuntime.gd"
)
const ACTION_SETTLEMENT_RUNTIME := preload(
	"res://world/runtime/action/TownActionSettlementRuntime.gd"
)
const ACTION_RESULT_RUNTIME := preload(
	"res://world/runtime/action/TownActionResultRuntime.gd"
)
const ACTION_PREVIEW_RUNTIME := preload(
	"res://world/runtime/action/TownActionPreviewRuntime.gd"
)
const ACTION_VALIDITY_POLICY := preload(
	"res://world/runtime/action/TownActionValidityPolicy.gd"
)
const ACTION_GEOMETRY := preload(
	"res://world/runtime/action/TownActionGeometry.gd"
)
const ACTION_PROJECTION_MODULE := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const ACTION_SUPPORT := preload("res://world/runtime/action/TownActionSupport.gd")
const OCCUPATION_SERVICE_PRESENCE_REQUIRED_KINDS := ACTION_SUPPORT.OCCUPATION_SERVICE_PRESENCE_REQUIRED_KINDS
const ACTIVITY_SCALARS := preload("res://world/runtime/activity/TownActivityScalars.gd")
const PASSIVE_NEED_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/activity/TownPassiveNeedAdvancementRuntime.gd"
)
const SOCIAL_JUDGMENTS := preload("res://world/runtime/social/TownSocialJudgments.gd")
const ANNOUNCEMENT_COMMAND_RUNTIME := preload(
	"res://world/runtime/social/TownAnnouncementCommandRuntime.gd"
)
const BULLETIN_PUBLISH_ACTIVITY_ID := SOCIAL_JUDGMENTS.BULLETIN_PUBLISH_ACTIVITY_ID
const BULLETIN_READ_ACTIVITY_ID := SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID
const COMMUNITY_BULLETIN_PLACE_ID := SOCIAL_JUDGMENTS.COMMUNITY_BULLETIN_PLACE_ID
const SYSTEM_BULLETIN_PUBLISHER_ID := "world"
const ACTION_TIMING := preload(
	"res://world/runtime/action/TownActionTiming.gd"
)
const CARGO_INVENTORY_RUNTIME := preload(
	"res://world/runtime/work/TownCargoInventoryRuntime.gd"
)
const PRODUCTION_RUNTIME := preload(
	"res://world/runtime/work/TownProductionRuntime.gd"
)
const OCCUPATION_SERVICE_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServiceRuntime.gd"
)
const SOCIAL_MATTER_RUNTIME := preload(
	"res://world/runtime/social/TownSocialMatterRuntime.gd"
)
const COMMUNITY_BULLETIN_RUNTIME := preload(
	"res://world/runtime/social/TownCommunityBulletinRuntime.gd"
)
const ANNOUNCEMENT_RESIDENT_RUNTIME := preload("res://world/runtime/social/TownAnnouncementResidentRuntime.gd")
const SOCIAL_MATTER_SOURCE_ADAPTER := preload(
	"res://world/runtime/social/TownSocialMatterSourceAdapter.gd"
)
const SOCIAL_SOURCE_SUBMISSION_RUNTIME := preload(
	"res://world/runtime/social/TownSocialSourceSubmissionRuntime.gd"
)
const INITIAL_SOCIAL_CONTACT_POLICY := preload(
	"res://world/runtime/social/TownInitialSocialContactPolicy.gd"
)
const SOCIAL_RESPONSE_ROUND_RUNTIME := preload(
	"res://world/runtime/social/TownSocialResponseRoundRuntime.gd"
)
const SOCIAL_ASSIGNMENT_RECONCILIATION_RUNTIME := preload(
	"res://world/runtime/social/TownSocialAssignmentReconciliationRuntime.gd"
)
const SOCIAL_ASSIGNMENT_RESULT_RUNTIME := preload(
	"res://world/runtime/social/TownSocialAssignmentResultRuntime.gd"
)
const SOCIAL_GOAL_MATCHING_RUNTIME := preload(
	"res://world/runtime/social/TownSocialGoalMatchingRuntime.gd"
)
const SOCIAL_MATTER_COMMAND_RUNTIME := preload(
	"res://world/runtime/social/TownSocialMatterCommandRuntime.gd"
)
const AGENT_INITIALIZATION_PROJECTION := preload(
	"res://world/runtime/agent/TownAgentInitializationProjection.gd"
)
const AGENT_WORLD_QUERY_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentWorldQueryRuntime.gd"
)
const RESIDENT_PROFILE_COMMAND_RUNTIME := preload(
	"res://world/runtime/presentation/TownResidentProfileCommandRuntime.gd"
)
const RESIDENT_PUBLIC_QUERY_RUNTIME := preload(
	"res://world/runtime/presentation/TownResidentPublicQueryRuntime.gd"
)
const ANIMAL_COMMAND_RUNTIME := preload(
	"res://world/runtime/animals/TownAnimalCommandRuntime.gd"
)
const PLAYER_CONVERSATION_COMMAND_RUNTIME := preload(
	"res://world/runtime/conversation/TownPlayerConversationCommandRuntime.gd"
)
const INDOOR_LAYOUT_COMMAND_RUNTIME := preload(
	"res://world/runtime/prop/TownIndoorLayoutCommandRuntime.gd"
)
const DYNAMIC_PROP_COMMAND_RUNTIME := preload(
	"res://world/runtime/prop/TownDynamicPropCommandRuntime.gd"
)
const SAVE_COMMAND_RUNTIME := preload(
	"res://world/runtime/persistence/TownWorldSaveCommandRuntime.gd"
)
const CARGO_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownCargoCommandRuntime.gd"
)
const WORK_TASK_PUBLIC_RUNTIME := preload(
	"res://world/runtime/work/TownWorkTaskPublicRuntime.gd"
)
const PLANT_RESEARCH_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownPlantResearchCommandRuntime.gd"
)
const OCCUPATION_RESIDENT_CONTEXT_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationResidentContextRuntime.gd"
)
const DINING_ORDER_COORDINATION_RUNTIME := preload(
	"res://world/runtime/work/TownDiningOrderCoordinationRuntime.gd"
)
const ACTIVITY_AVAILABILITY_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityAvailabilityRuntime.gd"
)
const PRIVATE_MESSAGE_QUERY_RUNTIME := preload(
	"res://world/runtime/social/TownPrivateMessageQueryRuntime.gd"
)
const SOCIAL_SOURCE_REFERENCE_VALIDATOR := preload(
	"res://world/runtime/social/TownSocialSourceReferenceValidator.gd"
)
const SOCIAL_AGENT_ADAPTER := preload(
	"res://world/runtime/social/TownSocialAgentAdapter.gd"
)
const RESIDENT_MESSAGE_POLICY := preload(
	"res://world/runtime/social/TownResidentMessagePolicy.gd"
)
const RESIDENT_MESSAGE_CONTENT := preload(
	"res://world/runtime/social/TownResidentMessageContent.gd"
)
const PRIVATE_MESSAGE_RUNTIME := preload(
	"res://world/runtime/social/TownPrivateMessageRuntime.gd"
)
const POSTAL_MESSAGE_RUNTIME := preload(
	"res://world/runtime/social/TownPostalMessageRuntime.gd"
)
const PRIVATE_MESSAGE_DELIVERY_RUNTIME := preload(
	"res://world/runtime/social/TownPrivateMessageDeliveryRuntime.gd"
)
const POSTAL_DELIVERY_ACTION_PREPARER := preload(
	"res://world/runtime/social/TownPostalDeliveryActionPreparer.gd"
)
const SOCIAL_MATTER_PUBLIC_PROJECTION := preload(
	"res://world/runtime/social/TownSocialMatterPublicProjection.gd"
)
const SOCIAL_MATTER_ACTIVITY_PROJECTION := preload(
	"res://world/runtime/social/TownSocialMatterActivityProjection.gd"
)
const SOCIAL_COORDINATION_STATE := preload(
	"res://world/runtime/social/TownSocialCoordinationState.gd"
)
const RELATIONSHIP_EVIDENCE_PROGRESS := preload(
	"res://world/runtime/relationship/TownRelationshipEvidenceProgress.gd"
)
const RESIDENT_CONDITION_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentConditionRuntime.gd"
)
const RESIDENT_CONDITION_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentConditionAdvancementRuntime.gd"
)
const RESIDENT_CONDITION_SETTLEMENT_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentConditionSettlementRuntime.gd"
)
const RESIDENT_SLEEP_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentSleepRuntime.gd"
)
const CLINIC_INTERVIEW_POLICY := preload(
	"res://world/runtime/condition/TownClinicInterviewPolicy.gd"
)
const CLINIC_INTERVIEW_RUNTIME := preload(
	"res://world/runtime/condition/TownClinicInterviewRuntime.gd"
)
const CLINIC_SERVICE_COORDINATION_RUNTIME := preload(
	"res://world/runtime/condition/TownClinicServiceCoordinationRuntime.gd"
)
const CLINIC_CONDITION_SETTLEMENT_RUNTIME := preload(
	"res://world/runtime/condition/TownClinicConditionSettlementRuntime.gd"
)
const CONFLICT_CONTROLLER := preload(
	"res://world/runtime/conflict/TownConflictWorldController.gd"
)
const CONFLICT_AGENT_WORLD_BRIDGE := preload(
	"res://world/runtime/conflict/TownConflictAgentWorldBridge.gd"
)
const CONFLICT_WORLD_COORDINATION_RUNTIME := preload(
	"res://world/runtime/conflict/TownConflictWorldCoordinationRuntime.gd"
)
const RESIDENT_LIFECYCLE_RUNTIME := preload(
	"res://world/runtime/lifecycle/TownResidentLifecycleRuntime.gd"
)
const WORLD_START_PREPARATION := preload(
	"res://world/runtime/lifecycle/TownWorldStartPreparation.gd"
)
const WORLD_START_COMMIT_RUNTIME := preload(
	"res://world/runtime/lifecycle/TownWorldStartCommitRuntime.gd"
)
const WORLD_LIFECYCLE_COMMAND_RUNTIME := preload(
	"res://world/runtime/lifecycle/TownWorldLifecycleCommandRuntime.gd"
)
const WORLD_DEFINITION_STATE := preload(
	"res://world/runtime/lifecycle/TownWorldDefinitionState.gd"
)
const RESIDENT_RUNTIME_FACTORY := preload(
	"res://world/runtime/lifecycle/TownResidentRuntimeFactory.gd"
)
const RESIDENT_REGISTRY := preload(
	"res://world/runtime/lifecycle/TownResidentRegistry.gd"
)
const RESIDENT_DEATH_POLICY := preload(
	"res://world/runtime/lifecycle/TownResidentDeathPolicy.gd"
)
const RESIDENT_DEATH_CONFIRMATION_RUNTIME := preload(
	"res://world/runtime/lifecycle/TownResidentDeathConfirmationRuntime.gd"
)
const RESIDENT_LIFECYCLE_PROJECTION := preload(
	"res://world/presentation/lifecycle/TownResidentLifecycleProjection.gd"
)
const RESIDENT_STATE_PROJECTION := preload(
	"res://world/runtime/presentation/TownResidentStateProjection.gd"
)
const WORLD_TELEMETRY_RUNTIME := preload(
	"res://world/runtime/presentation/TownWorldTelemetryRuntime.gd"
)
const ACTOR_PRESENTATION_STATE := preload(
	"res://world/runtime/presentation/TownWorldActorPresentationState.gd"
)
const RESIDENT_MOVEMENT_PROJECTION := preload(
	"res://world/runtime/presentation/TownResidentMovementProjection.gd"
)
const PLACE_PRESENTATION_QUERY := preload(
	"res://world/runtime/presentation/TownPlacePresentationQuery.gd"
)
const ANIMAL_FACT_RUNTIME := preload(
	"res://world/runtime/animals/TownAnimalFactRuntime.gd"
)
const ACTION_OPTION_DIRECTORY := preload(
	"res://world/runtime/action/TownActionOptionDirectory.gd"
)
const ACTION_OPTION_SOURCE_ADAPTER := preload(
	"res://world/runtime/action/TownActionOptionSourceAdapter.gd"
)
const ACTIVITY_ROUTINE_DURATION_MINUTES := {
	# A work activity is one decision stage. When it finishes the resident
	# receives the result and decides again instead of World silently choosing
	# another workplace activity on the resident's behalf.
	"work": 20,
	"meal": 45,
}
const ACTIVITY_ROUTINE_STEP_CAP_MINUTES := {
	"work": 20,
	"meal": 12,
}
const ACTIVITY_ROUTINE_MAX_STEPS := {
	"work": 1,
	"meal": 3,
}
const DINING_SERVICE := preload("res://world/runtime/work/TownDiningServiceRuntime.gd")
const OCCUPATION_SERVICE_PRESENCE_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServicePresenceAdvancementRuntime.gd"
)
const OCCUPATION_SERVICE_CANCELLATION_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServiceCancellationRuntime.gd"
)
const BODY_LEVELS := {
	"困": ["不困", "有点困", "很困"],
	"饿": ["不饿", "有点饿", "很饿"],
	"累": ["不累", "有点累", "很累"],
}
const ACTIVITY_STATE_KEYS := [
	"energy",
	"satiety",
	"stress",
	"socialNeed",
	"solitudeNeed",
]
const URGENT_EVENT_TYPES := [
	"搭话",
	"对方答话",
	"对话结束",
	"冲突见闻",
	"身体状况变化",
	"居民死亡",
	"天气变了",
]
const MAX_AUTONOMOUS_CONVERSATION_TURNS := 8
const CONVERSATION_SNAPSHOT_TURN_LIMIT := 16
const AUTONOMOUS_CONVERSATION_IDLE_TIMEOUT_SECONDS := 45.0
const RESIDENT_CONVERSATION_PAIR_COOLDOWN_MINUTES := 30
const MAX_ENDED_CONVERSATION_HISTORY := 64
const MAX_ANNOUNCEMENT_HISTORY := 64
const CONFIRMED_ACTION_PREVIEW_SECONDS := ACTION_PREVIEW_RUNTIME.PREVIEW_SECONDS
const MAX_DELIVERED_PRIVATE_MESSAGES := 64
const PERCEPTION_EXIT_HYSTERESIS_PX := 48.0
const POSTAL_TALK_APPROACH_STOP_DISTANCE_PX := 96.0
const PAUSE_REASONS := [
	"main_menu",
	"resident_editor",
	"furniture_editor",
	"manual",
	"background",
]
# Compatibility fallback for malformed legacy openings. New games receive this
# opaque person ID from TownNewGameOpeningCompiler and persist it in their save.
const DEFAULT_PLAYER_AVATAR_ID := "person_7f3a91c2d8e4"
const ALLOWED_SIMULATION_SPEEDS := [1, 2, 3]
const PUBLIC_THOUGHT_MAX_LENGTH := 48
const WAIT_ACTION_MAX_MINUTES := 60
const CONTINUITY_WAIT_MAX_MINUTES := 5
const ACTION_DECISION_PREFETCH_MINUTES := 5
const IDLE_PORTAL_TRIGGER_DISTANCE_PX := 80.0
const IDLE_PORTAL_CLEARANCE_PX := 96.0
const IDLE_RESIDENT_CLEARANCE_PX := 56.0
const IDLE_PARKING_MIN_DISTANCE_PX := 96.0
const IDLE_PARKING_MAX_DISTANCE_PX := 224.0
const IDLE_DEPARTURE_PLACE_CANDIDATE_LIMIT := 2
const OUTDOOR_IDLE_PARKING_MAX_DISTANCE_PX := 640.0
const OUTDOOR_IDLE_PARKING_SAMPLE_STEP_PX := 64.0
const PASSIVE_NEED_TICK_MINUTES := 60
const SLEEP_ACTIVITY_ID := "activity_home_sleep"
const MAX_SOCIAL_RESPONSE_CANDIDATES := 4
const MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT := 1
const SERVICE_FETCH_DURATION_MINUTES := 10
const ESCORT_RETURN_AFTER_MINUTES := 3
const CONVERSATION_FOLLOW_UP_TIMEOUT_MINUTES := 180
const PRIORITY_INTERRUPT_THRESHOLD := 85
const STAFFING_MATTER_REFRESH_INTERVAL_MINUTES := 1440
const NEW_GAME_ARRIVAL_END_MINUTE_OF_DAY := 719
const MAX_AGENT_ACTIVITY_ROUTE_CHECKS_PER_WAKE := 1
const LIFE_RHYTHM_ANCHORS := [
	{"minute": 420, "id": "morning_start"},
	{"minute": 570, "id": "morning_work"},
	{"minute": 750, "id": "midday_free"},
	{"minute": 870, "id": "afternoon_work"},
	{"minute": 1140, "id": "evening_free"},
	{"minute": 1380, "id": "night_rest"},
]

var world_definition: TownWorldDefinitionState = WORLD_DEFINITION_STATE.new()
var place_presentation_query: TownPlacePresentationQuery = PLACE_PRESENTATION_QUERY.new()
var _dynamic_prop_runtime: TownDynamicPropRuntime = DYNAMIC_PROP_RUNTIME.new()
var _animal_fact_runtime: TownAnimalFactRuntime = ANIMAL_FACT_RUNTIME.new()
var resident_registry: TownResidentRegistry = RESIDENT_REGISTRY.new()
var actor_presentation_state: TownWorldActorPresentationState = (
	ACTOR_PRESENTATION_STATE.new()
)
var _traveler_relationship_state := TownTravelerRelationshipState.new()
var conversation_state: TownConversationState = CONVERSATION_STATE.new()
var world_log_domain: TownWorldLogDomainState = WORLD_LOG_DOMAIN_STATE.new()
var event_journal: TownWorldEventJournalRuntime:
	get:
		return world_log_domain.journal
var _environment: WORLD_ENVIRONMENT
var _activity_runtime: ACTIVITY_RUNTIME = ACTIVITY_RUNTIME.new()
var activity_routine_state: TownActivityRoutineState = ACTIVITY_ROUTINE_STATE.new()
var _work: TownWorkDomainRuntime = WORK_DOMAIN_RUNTIME.new()
var work_domain: TownWorkDomainRuntime:
	get:
		return _work
var private_message_runtime: TownPrivateMessageRuntime = PRIVATE_MESSAGE_RUNTIME.new()
var activity_work_task_bindings: TownActivityWorkTaskBindingRuntime = (
	ACTIVITY_WORK_TASK_BINDING_RUNTIME.new()
)
var _social_matters: SOCIAL_MATTER_RUNTIME = SOCIAL_MATTER_RUNTIME.new()
var _community_bulletin: COMMUNITY_BULLETIN_RUNTIME = COMMUNITY_BULLETIN_RUNTIME.new()
var _social_sources: SOCIAL_MATTER_SOURCE_ADAPTER = SOCIAL_MATTER_SOURCE_ADAPTER.new()
var _social_agent_adapter: SOCIAL_AGENT_ADAPTER = SOCIAL_AGENT_ADAPTER.new()
var _resident_conditions: TownResidentConditionRuntime = RESIDENT_CONDITION_RUNTIME.new()
var _resident_sleep: TownResidentSleepRuntime = RESIDENT_SLEEP_RUNTIME.new()
var _clinic_interviews: TownClinicInterviewPolicy = CLINIC_INTERVIEW_POLICY.new()
var _conflict_controller: TownConflictWorldController
var _conflict_agent_world_bridge: TownConflictAgentWorldBridge = (
	CONFLICT_AGENT_WORLD_BRIDGE.new()
)
var _resident_lifecycle: TownResidentLifecycleRuntime = RESIDENT_LIFECYCLE_RUNTIME.new()
var _action_options: TownActionOptionDirectory = ACTION_OPTION_DIRECTORY.new()
var _action_option_sources: TownActionOptionSourceAdapter = ACTION_OPTION_SOURCE_ADAPTER.new()
var _running := false
var _pause_reasons: Array[String] = []
var _runtime_generation := 0
var _world_revision := 0
var _simulation_speed := 1
var _tick_weather_override := ""
var _save_candidate_runtime: RefCounted = SAVE_CANDIDATE_RUNTIME.new()
var _restore_candidate_runtime: RefCounted = RESTORE_CANDIDATE_RUNTIME.new()
var activity_reachability_state: TownActivityReachabilityCache = (
	ACTIVITY_REACHABILITY_CACHE.new()
)
var perception_spatial := PERCEPTION_RUNTIME.SpatialState.new()
var _processing_tick_absolute_minute := -1
var frame_budget_runtime: TownWorldFrameBudgetRuntime = FRAME_BUDGET_RUNTIME.new()
var social_coordination_state: TownSocialCoordinationState = SOCIAL_COORDINATION_STATE.new()
var telemetry: TownWorldTelemetryRuntime = WORLD_TELEMETRY_RUNTIME.new()
var _agent_wake_preparation_runtime := AGENT_WAKE_PREPARATION_RUNTIME.new()
func get_agent_request_metrics() -> Dictionary:
	return telemetry.agent_request_metrics_snapshot()

func start(
	world_data: Dictionary,
	opening_config: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	return _start_with_validation(
		world_data,
		opening_config,
		false,
		resident_identities,
		true,
		false,
	)

func start_observer(
	world_data: Dictionary,
	opening_config: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	return _start_with_validation(
		world_data,
		opening_config,
		false,
		resident_identities,
		false,
		false,
	)

func start_formal(
	world_data: Dictionary,
	opening_config: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	return _start_with_validation(
		world_data,
		opening_config,
		true,
		resident_identities,
		true,
		true,
	)

func start_formal_observer(
	world_data: Dictionary,
	opening_config: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	return _start_with_validation(
		world_data,
		opening_config,
		true,
		resident_identities,
		false,
		true,
	)

func start_formal_restore_observer(
	world_data: Dictionary,
	opening_config: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	return _start_with_validation(
		world_data,
		opening_config,
		true,
		resident_identities,
		false,
		false,
	)

func validate_startup(
	world_data: Dictionary,
	opening_config: Dictionary,
	require_world_ready := true,
	resident_identities: Variant = [],
) -> Dictionary:
	var result := STARTUP_VALIDATOR.validate(
		world_data,
		opening_config,
		require_world_ready,
	) as Dictionary
	if result.get("ok") == true:
		var identities := OPENING_CONFIG.prepare_resident_identities(
			opening_config,
			resident_identities,
			require_world_ready,
		) as Dictionary
		if identities.get("ok") != true:
			result["ok"] = false
			result["errorCode"] = String(identities.get("errorCode", "WORLD_RESIDENT_IDENTITIES_INVALID"))
			result["retryable"] = false
			result["errors"] = (identities.get("errors", []) as Array).duplicate()
			result["issues"] = [{
				"code": String(result["errorCode"]),
				"scope": "opening.residentIdentities",
				"subject": "residentIdentities",
				"message": String((result["errors"] as Array)[0]),
			}]
			result["identityStatus"] = "invalid"
		else:
			result["identityStatus"] = String(identities.get("status", "unavailable"))
			result["residentIdentityCount"] = (identities.get("residents", []) as Array).size()
	result["worldRevision"] = _world_revision
	return result

func validate_new_game_resident_spawns(
	world_data: Dictionary,
	opening_config: Dictionary,
) -> Dictionary:
	var errors := CHARACTER_MOVEMENT_QUERY.validate_formal_new_game_spawns(
		world_data,
		opening_config,
	) as PackedStringArray
	if errors.is_empty():
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"spawnPolicy": "staggered_south_entry",
			"worldRevision": _world_revision,
		}
	return {
		"ok": false,
		"errorCode": "WORLD_RESIDENT_SPAWN_INVALID",
		"retryable": false,
		"errors": Array(errors),
		"issues": [{
			"code": "WORLD_RESIDENT_SPAWN_INVALID",
			"scope": "opening.residents.worldState",
			"subject": "residentSpawn",
			"message": String(errors[0]),
		}],
		"worldRevision": _world_revision,
	}

func _begin_world_run() -> void:
	_running = true
	world_log_domain.capture_enabled = true
	_connect_work_task_log_source()
	_connect_production_task_schedule_source()
	OCCUPATION_RESIDENT_CONTEXT_RUNTIME.sync_staffing_matters(self)

func _announce_world_lifecycle(speed_was_reset: bool) -> Dictionary:
	var lifecycle := get_lifecycle_state()
	_notify_world_revision()
	if speed_was_reset:
		simulation_speed_changed.emit(_simulation_speed, _world_revision)
	lifecycle_state_changed.emit(lifecycle.duplicate(true))
	return lifecycle

## 装机清单交叉校验(批次D之3):运行时组合层维护的子系统安装清单,
## 启动/恢复两条路径装机完成后断言全部就位,兜"新增子系统漏改一处=
## 存档后子系统失联"。缺失时 push_error 会被测试的引擎错误检测抓红。
func _assert_subsystems_installed(context: String) -> void:
	var checklist := {
		"environment": _environment,
		"workTasks": _work.tasks,
		"occupationServices": _work.services,
		"socialMatters": _social_matters,
		"communityBulletin": _community_bulletin,
		"residentConditions": _resident_conditions,
		"residentSleep": _resident_sleep,
		"clinicInterviews": _clinic_interviews,
		"conflictController": _conflict_controller,
		"conflictAgentWorldBridge": _conflict_agent_world_bridge,
		"residentLifecycle": _resident_lifecycle,
		"actionOptions": _action_options,
		"activityRuntime": _activity_runtime,
		"cargoInventory": _work.cargo,
		"staffing": _work.staffing,
		"worldLogStore": world_log_domain.store,
	}
	for key: String in checklist:
		if checklist[key] == null:
			push_error("装机清单校验失败(%s):子系统 %s 未安装" % [context, key])

func _start_with_validation(
	world_data: Dictionary,
	opening_config: Dictionary,
	require_world_ready: bool,
	resident_identities: Variant,
	initial_player_avatar_present: bool,
	validate_new_game_spawns: bool,
) -> Dictionary:
	return WORLD_START_COMMIT_RUNTIME.start(
		self,
		world_data,
		opening_config,
		require_world_ready,
		resident_identities,
		initial_player_avatar_present,
		validate_new_game_spawns,
	)


func is_running() -> bool:
	return _running

func is_paused() -> bool:
	return _running and not _pause_reasons.is_empty()

func get_world_revision() -> int:
	return _world_revision

func get_simulation_speed() -> int:
	return _simulation_speed

func set_observed_action_preview_resident(
	resident_ref: String,
	enabled: bool,
) -> Dictionary:
	return ACTION_PREVIEW_RUNTIME.set_observed_resident(
		self, resident_ref, enabled,
	)

func set_simulation_speed(speed: int) -> Dictionary:
	return WORLD_LIFECYCLE_COMMAND_RUNTIME.set_speed(self, speed)

func get_lifecycle_state() -> Dictionary:
	return WORLD_LIFECYCLE_COMMAND_RUNTIME.state(self)

func get_indoor_layout_projection(space_id: String) -> Dictionary:
	return _dynamic_prop_runtime.layout_projection(
		world_definition.world_data,
		space_id,
	)

func get_space_character_movement_contract(space_id: String) -> Dictionary:
	return CHARACTER_MOVEMENT_QUERY.space_contract(world_definition.world_data, space_id) as Dictionary

func apply_indoor_layout_projection(projection: Dictionary) -> Dictionary:
	return INDOOR_LAYOUT_COMMAND_RUNTIME.apply(self, projection)

func pause(reason: String) -> Dictionary:
	return WORLD_LIFECYCLE_COMMAND_RUNTIME.pause(self, reason)

func resume(reason: String) -> Dictionary:
	return WORLD_LIFECYCLE_COMMAND_RUNTIME.resume(self, reason)

func stop() -> Dictionary:
	return WORLD_LIFECYCLE_COMMAND_RUNTIME.stop(self)

func create_save_snapshot() -> Dictionary:
	return SAVE_COMMAND_RUNTIME.create_snapshot(self)

func prepare_save_candidate() -> Dictionary:
	return _decorate_command_result(PERSISTENCE_PREPARATION.prepare_save_candidate(
		self,
		world_log_domain.journal,
		world_log_domain.store,
		world_definition.world_data,
		world_definition.opening,
		resident_registry.identity_status,
		resident_registry.order,
		resident_registry.name_by_id,
		_save_candidate_runtime,
		_runtime_generation,
		_world_revision,
	))

func validate_save_candidate(token: String) -> Dictionary:
	return _decorate_command_result(_save_candidate_runtime.validate(
		token,
		_running,
		_runtime_generation,
		_world_revision,
	))

func commit_save_candidate(
	token: String,
	snapshot_ref: String,
	world_log_snapshot_ref := "",
) -> Dictionary:
	return _decorate_command_result(_save_candidate_runtime.commit(
		token,
		snapshot_ref,
		String(world_log_snapshot_ref),
		_running,
		_runtime_generation,
		_world_revision,
	))

func abort_save_candidate(token: String) -> Dictionary:
	return _decorate_command_result(_save_candidate_runtime.abort(token))

func cleanup_save_candidate(token: String) -> Dictionary:
	return _decorate_command_result(_save_candidate_runtime.cleanup(token))

func prepare_restore_candidate(
	world_data: Dictionary,
	opening_config: Dictionary,
	snapshot: Dictionary,
	resident_identities: Variant = [],
	require_world_ready := true,
	world_log_snapshot: Dictionary = {},
) -> Dictionary:
	return _decorate_command_result(PERSISTENCE_PREPARATION.prepare_restore_candidate(
		self,
		world_data,
		opening_config,
		snapshot,
		resident_identities,
		require_world_ready,
		world_log_snapshot,
		_running,
		resident_registry.identity_status,
		_restore_candidate_runtime,
		_runtime_generation,
		_world_revision,
	))

func validate_restore_candidate(token: String) -> Dictionary:
	return _decorate_command_result(_restore_candidate_runtime.validate(
		token,
		_runtime_generation,
		_world_revision,
	))

func commit_restore_candidate(token: String) -> Dictionary:
	return _commit_restore_candidate(token, true)

func commit_restore_candidate_for_observer(token: String) -> Dictionary:
	return _commit_restore_candidate(token, false)

func _commit_restore_candidate(
	token: String,
	player_avatar_present: bool,
) -> Dictionary:
	return RESTORE_COMMIT_RUNTIME.commit_candidate(self, token,
		player_avatar_present, _person_name_for_id,)

func abort_restore_candidate(token: String) -> Dictionary:
	return _decorate_command_result(_restore_candidate_runtime.abort(token))

func cleanup_restore_candidate(token: String) -> Dictionary:
	return _decorate_command_result(_restore_candidate_runtime.cleanup(token))

func restore_from_snapshot(
	world_data: Dictionary,
	opening_config: Dictionary,
	snapshot: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	return SAVE_COMMAND_RUNTIME.restore_snapshot(
		self,
		world_data,
		opening_config,
		snapshot,
		resident_identities,
	)

func advance(real_seconds: float) -> Dictionary:
	return WORLD_ADVANCE_RUNTIME.advance(self, real_seconds, _community_bulletin)


func set_advance_profile_enabled(enabled: bool) -> void:
	telemetry.set_advance_profile_enabled(enabled)

func get_last_advance_profile() -> Dictionary:
	return telemetry.last_advance_profile_snapshot()

func set_weather(weather: String) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var result := _environment.set_weather(weather) as Dictionary
	if result.get("changed") == true:
		_bump_world_revision(false)
		CONVERSATION_FOLLOW_UP_ACTION_RUNTIME.pause_active_for_reconsideration(
			self,
			"天气已经变为%s，需要重新决定是否继续刚才的约定" % String(result.get("weather", weather)),
		)
		WORLD_EVENT_DELIVERY_RUNTIME.broadcast(
			self,
			result.get("event", {}) as Dictionary,
		)
		ACTIVITY_AVAILABILITY_RUNTIME.interrupt_unsafe_weather(self)
		_notify_world_revision()
		environment_changed.emit(get_time(), get_weather())
	return _decorate_command_result(result, "INVALID_WEATHER")

func cycle_time_period_for_test() -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var previous_absolute := int(_environment.get_absolute_minute())
	var result := _environment.cycle_time_period() as Dictionary
	if result.get("ok") == true:
		_bump_world_revision(false)
	var current_absolute := int(_environment.get_absolute_minute())
	for absolute_minute in range(previous_absolute + 1, current_absolute + 1):
		RESIDENT_ARRIVAL_RUNTIME.advance(
			self, absolute_minute, IDLE_RESIDENT_CLEARANCE_PX,
		)
		ACTION_ADVANCEMENT_RUNTIME.advance_all(self, absolute_minute)
		RESIDENT_CONDITION_ADVANCEMENT_RUNTIME.advance(self, absolute_minute)
		SOCIAL_MATTER_COMMAND_RUNTIME.advance(self, absolute_minute)
		ANNOUNCEMENT_RESIDENT_RUNTIME.advance_schedules(
			self, _community_bulletin, absolute_minute,
		)
		PASSIVE_NEED_ADVANCEMENT_RUNTIME.advance(self, absolute_minute)
		PERCEPTION_RUNTIME._refresh_perception(self, true, _traveler_relationship_state)
		AGENT_DECISION_SCHEDULING_RUNTIME.schedule_life_rhythm(
			self, absolute_minute, LIFE_RHYTHM_ANCHORS,
		)
	if result.get("ok") == true:
		_notify_world_revision()
	environment_changed.emit(get_time(), get_weather())
	return _decorate_command_result(result, "INVALID_TIME")

func queue_weather_roll(value: float) -> void:
	if _environment != null:
		_environment.queue_weather_roll(value)

func get_time() -> Dictionary:
	return _environment.get_time() as Dictionary if _environment != null else {}


func get_weather() -> String:
	if not _tick_weather_override.is_empty():
		return _tick_weather_override
	return String(_environment.get_weather()) if _environment != null else ""


func get_resident_names() -> Array[String]:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.names(self)


func get_resident_ids() -> Array[String]:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.ids(self)


func create_private_message(
	sender_ref: String,
	recipient_ref: String,
	content: String,
	message_kind: String = "private",
	announcement_id: String = "",
	expires_at_minute: int = -1,
	source_ref: String = "",
) -> Dictionary:
	return POSTAL_MESSAGE_RUNTIME.create(
		self,
		sender_ref,
		recipient_ref,
		content,
		message_kind,
		announcement_id,
		expires_at_minute,
		source_ref,
	)


func get_private_message(message_id: String) -> Dictionary:
	return PRIVATE_MESSAGE_QUERY_RUNTIME.message(self, message_id)


func get_private_messages_for_resident(
	resident_ref: String,
) -> Array[Dictionary]:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	return private_message_runtime.messages_for_resident(
		resident_id,
		resident_registry.name_by_id,
	)



func create_work_task(spec: Dictionary) -> Dictionary:
	return WORK_TASK_PUBLIC_RUNTIME.create(self, spec)

func get_work_tasks_for_resident(
	resident_ref: String,
) -> Array[Dictionary]:
	return WORK_TASK_PUBLIC_RUNTIME.query_for_resident(self, resident_ref)
func get_staffing_snapshot() -> Dictionary:
	return _work.staffing_snapshot(_running)


func get_cargo_inventory_snapshot() -> Dictionary:
	return _work.cargo_snapshot(_running)


func get_occupation_service_snapshot() -> Dictionary:
	return _work.service_snapshot(_running)


func get_occupation_service_request(request_id: String) -> Dictionary:
	return _work.service_request(_running, request_id)


func create_occupation_service_request(spec: Dictionary) -> Dictionary:
	return OCCUPATION_SERVICE_REQUEST_COMMAND_RUNTIME.create(self, spec)


func create_cargo_lot(spec: Dictionary) -> Dictionary:
	return CARGO_COMMAND_RUNTIME.create(self, spec, "local_inventory")


func create_world_result_cargo_lot(spec: Dictionary) -> Dictionary:
	return CARGO_COMMAND_RUNTIME.create(self, spec, "world_result")


func create_external_supply_cargo_lot(
	spec: Dictionary,
) -> Dictionary:
	return CARGO_COMMAND_RUNTIME.create(self, spec, "external_supply")


func pickup_cargo_lot(
	lot_id: String,
	resident_ref: String,
) -> Dictionary:
	return CARGO_COMMAND_RUNTIME.pickup(self, lot_id, resident_ref)


func deliver_cargo_lot(
	lot_id: String,
	resident_ref: String,
) -> Dictionary:
	return CARGO_COMMAND_RUNTIME.deliver(self, lot_id, resident_ref)


func get_production_snapshot() -> Dictionary:
	return _work.production_snapshot(_running)


func create_plant_research(
	requester_ref: String,
	question: String,
	source_kind := "personal_research_plan",
) -> Dictionary:
	return PLANT_RESEARCH_COMMAND_RUNTIME.create(
		self, requester_ref, question, source_kind,
	)


func get_plant_research_projects() -> Array[Dictionary]:
	return (
		_work.production.plant_research_projects() as Array[Dictionary]
		if _running
		else []
	)


func complete_work_task(
	task_id: String,
	resident_ref: String,
	result_kind: String,
	evidence: Dictionary,
) -> Dictionary:
	return WORK_TASK_PUBLIC_RUNTIME.complete(
		self, task_id, resident_ref, result_kind, evidence,
	)


func get_resident_identity_snapshot() -> Dictionary:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.identity_snapshot(self)


func get_resident_state(resident_ref: String) -> Dictionary:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.state(self, resident_ref)


func get_resident_lifecycle_state(resident_ref: String) -> Dictionary:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.lifecycle_state(self, resident_ref)


func get_public_death_events() -> Array[Dictionary]:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.public_death_events(self)


func confirm_resident_death(
	resident_ref: String,
	reason: String,
	expected_lifecycle_revision: int = -1,
	expected_world_instance_token: String = "",
) -> Dictionary:
	return RESIDENT_DEATH_CONFIRMATION_RUNTIME.confirm(
		self,
		resident_ref,
		reason,
		expected_lifecycle_revision,
		expected_world_instance_token,
	)


func get_resident_action_phase(resident_ref: String) -> Dictionary:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.action_phase(self, resident_ref)

func get_resident_public_relationship_progress(
	resident_ref: String,
) -> Dictionary:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.relationship_progress(self, resident_ref)

func query_activity_options(
	resident_id: String,
	resident_override: Dictionary = {},
	max_uncached_reachability_checks := -1,
	priority_activity_id := "",
) -> Dictionary:
	return ACTIVITY_OPTION_QUERY.query(
		self,
		activity_reachability_state,
		resident_id,
		resident_override,
		max_uncached_reachability_checks,
		priority_activity_id,
	)


func perform_activity_step(
	resident_id: String,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
) -> Dictionary:
	return ACTIVITY_STEP_EXECUTION_RUNTIME.perform(
		self,
		resident_id,
		plan_id,
		plan_revision,
		step,
		ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_DIRECT,
		"",
		-1,
		true,
	)


func get_resident_movement_snapshot(resident_ref: String) -> Dictionary:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.movement_snapshot(self, resident_ref)


func get_all_resident_states() -> Array[Dictionary]:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.all_states(self)


# town_hud 专用轻量投影(A2):只算 HUD 实际消费的键,语义与完整投影键裁剪恒等。
func get_town_hud_resident_states() -> Array[Dictionary]:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.hud_states(self)


func get_resident_detail(resident_ref: String) -> Dictionary:
	return RESIDENT_PUBLIC_QUERY_RUNTIME.detail(self, resident_ref)


func update_resident_social_profile(
	resident_ref: String,
	profile: Dictionary,
) -> Dictionary:
	return RESIDENT_PROFILE_COMMAND_RUNTIME.update_social(
		self,
		resident_ref,
		profile,
		Callable(self, "get_place_detail"),
	)


func update_resident_profile(
	resident_ref: String,
	profile: Dictionary,
) -> Dictionary:
	return RESIDENT_PROFILE_COMMAND_RUNTIME.update(
		self,
		resident_ref,
		profile,
		Callable(self, "get_place_detail"),
	)



func get_place_names() -> Array[String]:
	return place_presentation_query.names(world_definition.world_data)


func get_place_detail(place_name: String) -> Dictionary:
	return place_presentation_query.detail(
		world_definition.world_data,
		resident_registry.records,
		resident_registry.order,
		world_definition.owners,
		actor_presentation_state.player_avatar,
		actor_presentation_state.player_avatar_present,
		PROP_ACTION_PREPARER.query_data(self),
		place_name,
		Callable(self, "_resident_is_present"),
		Callable(self, "_resident_display_name"),
		Callable(self, "_person_name_for_id"),
	)


func upsert_dynamic_prop(
	prop_id: String,
	display_name: String,
	position: Vector2,
	active: bool = true,
) -> Dictionary:
	return DYNAMIC_PROP_COMMAND_RUNTIME.upsert(
		self, prop_id, display_name, position, active,
	)


func remove_dynamic_prop(prop_id: String) -> Dictionary:
	return upsert_dynamic_prop(prop_id, prop_id, Vector2.ZERO, false)


func get_dynamic_prop_snapshot() -> Array[Dictionary]:
	return _dynamic_prop_runtime.snapshot()


func upsert_animal_presence(state: Dictionary) -> Dictionary:
	return ANIMAL_COMMAND_RUNTIME.upsert_presence(
		self,
		state,
		Callable(self, "_animal_place_for_position"),
	)


func _animal_place_for_position(position: Vector2) -> String:
	var membership := PERCEPTION_RUNTIME._membership(
		self,
		"town_outdoor",
		position,
	)
	if membership.is_empty():
		membership = PERCEPTION_RUNTIME._nearest_outdoor_membership(self, position)
	return String(membership.get("placeName", ""))


func set_animal_public_attention(
	animal_id: String,
	active: bool,
	expires_at: int,
	source_event_ids: Array = [],
) -> Dictionary:
	return ANIMAL_COMMAND_RUNTIME.set_public_attention(
		self, animal_id, active, expires_at, source_event_ids,
	)


func get_animal_fact_snapshot() -> Array[Dictionary]:
	return _animal_fact_runtime.public_snapshot()


func record_place_service_request(
	place_id: String,
	request_id: String,
	active: bool,
	expires_at := -1,
) -> Dictionary:
	return PLACE_SERVICE_COMMAND_RUNTIME.record_request(
		self,
		place_id,
		request_id,
		active,
		int(expires_at),
	)


func set_place_service_open(
	place_id: String,
	open: bool,
	changed_by_resident_id: String = "",
) -> Dictionary:
	return PLACE_SERVICE_COMMAND_RUNTIME.set_open(
		self,
		place_id,
		open,
		changed_by_resident_id,
	)


func get_place_service_state_snapshots() -> Array[Dictionary]:
	return PLACE_SERVICE_COMMAND_RUNTIME.snapshots(self)


func get_all_place_details() -> Array[Dictionary]:
	return place_presentation_query.all_details(
		world_definition.world_data,
		resident_registry.records,
		resident_registry.order,
		world_definition.owners,
		actor_presentation_state.player_avatar,
		actor_presentation_state.player_avatar_present,
		PROP_ACTION_PREPARER.query_data(self),
		Callable(self, "_resident_is_present"),
		Callable(self, "_resident_display_name"),
		Callable(self, "_person_name_for_id"),
	)


func get_player_avatar_state() -> Dictionary:
	return RESIDENT_STATE_PROJECTION.project_player_avatar(
		actor_presentation_state.player_avatar,
		actor_presentation_state.player_avatar_present,
		Callable(self, "_resident_display_name"),
	)


func get_public_conflict_projection() -> Dictionary:
	return CONFLICT_WORLD_COORDINATION_RUNTIME.public_projection(self)


func submit_conflict_attack(intent: Dictionary) -> Dictionary:
	return CONFLICT_WORLD_COORDINATION_RUNTIME.submit_attack(self, intent)


func submit_conflict_tension_action(intent: Dictionary) -> Dictionary:
	return CONFLICT_WORLD_COORDINATION_RUNTIME.submit_tension_action(self, intent)


func submit_avatar_area_attack(intent: Dictionary) -> Dictionary:
	return CONFLICT_WORLD_COORDINATION_RUNTIME.submit_avatar_area_attack(self, intent)

func submit_conflict_response(
	conflict_id: String,
	actor_id: String,
	response_kind: String,
) -> Dictionary:
	return CONFLICT_WORLD_COORDINATION_RUNTIME.submit_response(
		self, conflict_id, actor_id, response_kind,
	)


func leave_conflict(
	conflict_id: String,
	actor_id: String,
	reason: String,
) -> Dictionary:
	return CONFLICT_WORLD_COORDINATION_RUNTIME.leave(
		self, conflict_id, actor_id, reason,
	)


func set_player_avatar_present(
	present: bool,
	emit_events := true,
) -> Dictionary:
	return PLAYER_AVATAR_MOVEMENT_COMMAND_RUNTIME.set_present(
		self,
		present,
		emit_events,
	)


func submit_player_avatar_position(space_id: String, position: Vector2, doing := "") -> Dictionary:
	return PLAYER_AVATAR_MOVEMENT_COMMAND_RUNTIME.submit_position(
		self,
		space_id,
		position,
		doing,
	)


func prepare_player_avatar_descent(space_id: String, position: Vector2) -> Dictionary:
	return PLAYER_AVATAR_MOVEMENT_COMMAND_RUNTIME.prepare_descent(
		self,
		space_id,
		position,
	)


func change_player_avatar_place(target_place: String) -> Dictionary:
	return PLAYER_AVATAR_MOVEMENT_COMMAND_RUNTIME.change_place(
		self,
		target_place,
	)


func return_player_avatar_outdoors(
	connection_place: String,
	safe_return_position: Vector2,
) -> Dictionary:
	return PLAYER_AVATAR_MOVEMENT_COMMAND_RUNTIME.return_outdoors(
		self,
		connection_place,
		safe_return_position,
	)


func player_start_conversation(target_name: String, say: String, narration: String, photos: Array = []) -> Dictionary:
	return PLAYER_CONVERSATION_COMMAND_RUNTIME.start(
		self, target_name, say, narration, photos,
	)


func player_reply_conversation(
	conversation_id: String,
	say: String,
	narration: String,
	photos: Array = [],
	end := false,
) -> Dictionary:
	return PLAYER_CONVERSATION_COMMAND_RUNTIME.reply(
		self, conversation_id, say, narration, photos, end,
	)


func player_end_conversation(conversation_id: String, narration: String = "结束交谈") -> Dictionary:
	return PLAYER_CONVERSATION_COMMAND_RUNTIME.end(
		self, conversation_id, narration,
	)


func player_reject_conversation(conversation_id: String, narration: String = "没有接话") -> Dictionary:
	return PLAYER_CONVERSATION_COMMAND_RUNTIME.reject(
		self, conversation_id, narration,
	)


func get_place_exterior_anchor(place_name: String) -> Dictionary:
	return place_presentation_query.exterior_anchor(world_definition.world_data, place_name)


func get_place_observation_hotspot(place_name: String) -> Dictionary:
	return place_presentation_query.observation_hotspot(
		world_definition.world_data,
		place_name,
	)


func get_place_connection_id(place_name: String) -> String:
	return place_presentation_query.connection_id(world_definition.world_data, place_name)


func get_place_name_for_connection(connection_id: String) -> String:
	return place_presentation_query.place_name_for_connection(
		world_definition.world_data,
		connection_id,
	)

func get_announcements() -> Array[Dictionary]:
	return ANNOUNCEMENT_PUBLISHER_PROJECTION.project(self, _community_bulletin.get_announcements(true) as Array[Dictionary])

func get_public_event_log() -> Array[Dictionary]:
	return world_log_domain.journal.external_public_events()

func publish_announcement(text: String) -> Dictionary:
	return ANNOUNCEMENT_COMMAND_RUNTIME.publish(
		self,
		_player_avatar_id(),
		text,
		"",
		"board",
	)


func publish_resident_announcement(
	resident_ref: String,
	text: String,
	matter_id := "",
	delivery_mode := "",
) -> Dictionary:
	return ANNOUNCEMENT_COMMAND_RUNTIME.publish_resident(
		self, resident_ref, text, matter_id, delivery_mode,
	)


func read_announcement(
	resident_ref: String,
	announcement_id: String,
) -> Dictionary:
	return ANNOUNCEMENT_COMMAND_RUNTIME.read(self, resident_ref, announcement_id)


func relay_announcement(
	speaker_ref: String,
	listener_ref: String,
	announcement_id: String,
) -> Dictionary:
	return ANNOUNCEMENT_COMMAND_RUNTIME.relay(
		self,
		speaker_ref,
		listener_ref,
		announcement_id,
	)


func withdraw_announcement(announcement_id: String) -> Dictionary:
	return ANNOUNCEMENT_COMMAND_RUNTIME.withdraw(self, announcement_id)


func announcement_unread_count(resident_ref: String) -> int:
	return ANNOUNCEMENT_COMMAND_RUNTIME.unread_count(self, resident_ref)


func announcement_knowledge_for(
	resident_ref: String,
) -> Array[Dictionary]:
	return ANNOUNCEMENT_COMMAND_RUNTIME.knowledge_for(self, resident_ref)


func sync_place_service_pressure(place_state: Dictionary) -> Dictionary:
	return SOCIAL_SOURCE_SUBMISSION_RUNTIME.sync(
		self,
		"sync_place_service_pressure",
		place_state,
	)


func sync_resident_request(request_state: Dictionary) -> Dictionary:
	return SOCIAL_SOURCE_SUBMISSION_RUNTIME.sync(
		self,
		"sync_resident_request",
		request_state,
	)


func sync_conversation_commitment(commitment_state: Dictionary) -> Dictionary:
	return SOCIAL_SOURCE_SUBMISSION_RUNTIME.sync(
		self,
		"sync_conversation_commitment",
		commitment_state,
	)


func sync_animal_attention(animal_state: Dictionary) -> Dictionary:
	return SOCIAL_SOURCE_SUBMISSION_RUNTIME.sync(
		self,
		"sync_animal_attention",
		animal_state,
	)


func sync_job_vacancy(vacancy_state: Dictionary) -> Dictionary:
	return SOCIAL_SOURCE_SUBMISSION_RUNTIME.sync(
		self,
		"sync_job_vacancy",
		vacancy_state,
	)


func record_social_awareness(
	matter_id: String,
	resident_ref: String,
	acquired_via: String,
	source_id: String,
) -> Dictionary:
	return SOCIAL_MATTER_COMMAND_RUNTIME.record_awareness(
		self, matter_id, resident_ref, acquired_via, source_id,
	)


func begin_social_response_round(
	matter_id: String,
	candidates: Array,
	response_window_minutes: int,
) -> Dictionary:
	return SOCIAL_RESPONSE_ROUND_RUNTIME.begin(
		self,
		matter_id,
		candidates,
		response_window_minutes,
	)


func begin_social_response_round_for_residents(
	matter_id: String,
	resident_refs: Array,
	response_window_minutes: int,
) -> Dictionary:
	return SOCIAL_RESPONSE_ROUND_RUNTIME.begin_for_residents(
		self,
		matter_id,
		resident_refs,
		response_window_minutes,
	)


func submit_social_response(
	resident_ref: String,
	response: Dictionary,
) -> Dictionary:
	return SOCIAL_MATTER_COMMAND_RUNTIME.submit_response(
		self, resident_ref, response,
	)


func mark_social_candidate_terminal(
	matter_id: String,
	resident_ref: String,
	reason: String,
	expected_response_round_id: String = "",
) -> Dictionary:
	return SOCIAL_MATTER_COMMAND_RUNTIME.mark_candidate_terminal(
		self,
		matter_id,
		resident_ref,
		reason,
		expected_response_round_id,
	)


func get_social_matter_summaries(
	include_closed := false,
) -> Array[Dictionary]:
	return SOCIAL_MATTER_COMMAND_RUNTIME.summaries(self, include_closed)


func get_public_social_matter_activity() -> Dictionary:
	return SOCIAL_MATTER_ACTIVITY_PROJECTION.build(self)


func get_agent_social_matters(
	resident_ref: String,
) -> Array[Dictionary]:
	return SOCIAL_MATTER_COMMAND_RUNTIME.agent_matters(self, resident_ref)


func get_agent_social_exposures(
	resident_ref: String,
) -> Array[Dictionary]:
	return SOCIAL_MATTER_COMMAND_RUNTIME.agent_exposures(self, resident_ref)


func take_social_response_results(
	resident_ref: String,
) -> Array[Dictionary]:
	return SOCIAL_MATTER_COMMAND_RUNTIME.take_response_results(self, resident_ref)


func get_agent_initialization(resident_ref: String) -> Dictionary:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty() or not _resident_is_alive(resident_id):
		return {}
	return AGENT_INITIALIZATION_PROJECTION.build(self, resident_id)


func get_agent_initialization_by_id(resident_id: String) -> Dictionary:
	return get_agent_initialization(resident_id)


func take_pending_decision_requests(
	resident_filter: Array = [],
	materialize_snapshots: bool = true,
) -> Array[Dictionary]:
	return AGENT_DECISION_DISPATCH_RUNTIME.take(
		self,
		resident_filter,
		materialize_snapshots,
	)

func take_pending_decision_requests_by_ids(
	resident_ids: Array,
	materialize_snapshots: bool = true,
) -> Array[Dictionary]:
	return AGENT_DECISION_DISPATCH_RUNTIME.take_by_ids(
		self,
		resident_ids,
		materialize_snapshots,
	)

func take_pending_decision_envelopes_by_ids(resident_ids: Array) -> Array[Dictionary]:
	return take_pending_decision_requests_by_ids(resident_ids, false)


func refresh_pending_decision_request_by_id(
	resident_ref: String,
	decision_id: String,
) -> Dictionary:
	return AGENT_DECISION_DISPATCH_RUNTIME.refresh_by_id(
		self,
		resident_ref,
		decision_id,
	)

func advance_pending_decision_preparation_by_id(resident_ref: String, decision_id: String) -> Dictionary:
	return _agent_wake_preparation_runtime.advance(
		self,
		_dynamic_prop_runtime,
		resident_ref,
		decision_id,
	)
func redispatch_decision_request_by_id(resident_id: String, decision_id: String) -> bool:
	return redispatch_decision_request(resident_id, decision_id)
func redispatch_decision_request(
	resident_ref: String,
	decision_id: String,
) -> bool:
	return AGENT_DECISION_DISPATCH_RUNTIME.redispatch(
		self,
		resident_ref,
		decision_id,
	)

func submit_agent_decision_by_id(
	resident_id: String,
	decision: Dictionary,
) -> Dictionary:
	return AGENT_DECISION_DISPATCH_RUNTIME.submit_by_id(
		self,
		resident_id,
		decision,
	)

func submit_agent_decision(resident_name: String, decision: Dictionary) -> Dictionary:
	return AGENT_DECISION_SUBMISSION_RUNTIME.submit(self, resident_name, decision)


func _append_action_result_without_schedule(
	resident_id: String,
	action_id: String,
	status: String,
	reason: String,
	presentation: Dictionary = {},
) -> void:
	ACTION_RESULT_RUNTIME.append_without_schedule(
		self,
		resident_id,
		action_id,
		status,
		reason,
		presentation,
	)


func get_conversation(conversation_id: String) -> Dictionary:
	if not conversation_state.records.has(conversation_id):
		return {}
	return (conversation_state.records[conversation_id] as Dictionary).duplicate(true)


func get_active_conversations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[String] = []
	for conversation_id_value: Variant in conversation_state.records:
		ids.append(String(conversation_id_value))
	ids.sort()
	for conversation_id in ids:
		var conversation := conversation_state.records[conversation_id] as Dictionary
		if String(conversation.get("status", "")) == "active":
			result.append(conversation.duplicate(true))
	return result


# 表现状态通知的唯一发射口(docs/居民状态通知链减负方案.md C2):载荷为
# EMIT_KEYS 轻投影,发射条件与载荷语义只在这里定义。
func _emit_resident_state_changed(resident_ref: String) -> void:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		resident_state_changed.emit("", {})
		return
	var projected_state := RESIDENT_STATE_PROJECTION.project_emit(
		self,
		resident_registry.records[resident_id] as Dictionary,
	)
	resident_state_changed.emit(
		String(resident_registry.name_by_id.get(resident_id, "")),
		projected_state,
	)


# 感知模块读接口(F 之 2:12 共享符号去私有穿透;字典按引用返回,
# 感知侧的 nearby 就地更新语义不变)。
func environment() -> RefCounted:
	return _environment


func world_data() -> Dictionary:
	return world_definition.world_data


func residents() -> Dictionary:
	return resident_registry.records


func resident_order() -> Array:
	return resident_registry.order


func player_avatar() -> Dictionary:
	return actor_presentation_state.player_avatar


func player_avatar_present() -> bool:
	return actor_presentation_state.player_avatar_present


func resident_is_present(resident: Dictionary) -> bool:
	return _resident_is_present(resident)


func resident_display_name(resident_ref: String) -> String:
	return _resident_display_name(resident_ref)


func person_id_for_name(person_ref: String) -> String:
	return _person_id_for_name(person_ref)


func person_name_for_id(person_id: String) -> String:
	return _person_name_for_id(person_id)


func player_avatar_id() -> String:
	return _player_avatar_id()


func queue_world_event(resident_name: String, source: Dictionary) -> Dictionary:
	return WORLD_EVENT_DELIVERY_RUNTIME.queue(self, resident_name, source)


func bump_world_revision(notify := true) -> void:
	_bump_world_revision(notify)


func _resident_is_present(resident: Dictionary) -> bool:
	var resident_id := String(resident.get("residentId", "")).strip_edges()
	if resident_id == _player_avatar_id():
		return actor_presentation_state.player_avatar_present
	if resident_id.is_empty() or not _resident_is_alive(resident_id):
		return false
	return (
		String(
			(
				resident.get("arrivalState", {}) as Dictionary
			).get("status", "arrived"),
		)
		== "arrived"
	)


func _resident_is_alive(resident_id: String) -> bool:
	return bool(_resident_lifecycle.is_alive(resident_id))


func _player_avatar_id() -> String:
	var resident_id := String(actor_presentation_state.player_avatar.get("residentId", "")).strip_edges()
	return DEFAULT_PLAYER_AVATAR_ID if resident_id.is_empty() else resident_id


func _person_state(person_ref: String) -> Dictionary:
	var resident_id := _resident_key(person_ref)
	if not resident_id.is_empty():
		return resident_registry.records[resident_id] as Dictionary
	if person_ref in [_player_avatar_id(), String(actor_presentation_state.player_avatar.get("name", ""))]:
		return actor_presentation_state.player_avatar
	return {}


func _person_id_for_name(person_ref: String) -> String:
	var resident_id := _resident_key(person_ref)
	if not resident_id.is_empty():
		return resident_id
	if person_ref in [_player_avatar_id(), String(actor_presentation_state.player_avatar.get("name", ""))]:
		return _player_avatar_id()
	return ""


func _person_name_for_id(person_id: String) -> String:
	if resident_registry.name_by_id.has(person_id):
		return String(resident_registry.name_by_id[person_id])
	if person_id == _player_avatar_id():
		return String(actor_presentation_state.player_avatar.get("name", ""))
	return ""


func _resident_key(resident_ref: String) -> String:
	var normalized := resident_ref.strip_edges()
	if resident_registry.records.has(normalized):
		return normalized
	return String(resident_registry.id_by_name.get(normalized, ""))


func _resident_display_name(resident_ref: String) -> String:
	var resident_id := _resident_key(resident_ref)
	return String(resident_registry.name_by_id.get(resident_id, ""))


func _schedule_decision(
	resident_name: String,
	invalidate: bool,
	prefetch := false,
	allow_current_activity_interrupt := false,
	force_fresh := false,
	wake_while_current_action := false,
) -> void:
	AGENT_DECISION_SCHEDULING_RUNTIME.schedule(
		self,
		resident_name,
		invalidate,
		prefetch,
		allow_current_activity_interrupt,
		force_fresh,
		wake_while_current_action,
	)




func _complete_private_message_delivery(
	initiator_ref: String,
	target_ref: String,
	turn: Dictionary,
) -> void:
	PRIVATE_MESSAGE_DELIVERY_RUNTIME.complete_delivery(
		self, initiator_ref, target_ref, turn,
		Callable(self, "_resident_can_accept_work_task"), Callable(self, "_task_acceptance_occupation_id"),
	)



func _connect_work_task_log_source() -> void:
	if _work.tasks == null or not _work.tasks.has_signal("task_committed"):
		return
	var callback := _on_work_task_committed_for_log
	if not _work.tasks.is_connected("task_committed", callback):
		_work.tasks.connect("task_committed", callback)


func _disconnect_work_task_log_source() -> void:
	if _work.tasks == null or not _work.tasks.has_signal("task_committed"):
		return
	var callback := _on_work_task_committed_for_log
	if _work.tasks.is_connected("task_committed", callback):
		_work.tasks.disconnect("task_committed", callback)


func _connect_production_task_schedule_source() -> void:
	var callback := _on_production_task_created
	if not _work.production_task_created.is_connected(callback):
		_work.production_task_created.connect(callback)


func _on_production_task_created(task: Dictionary) -> void:
	for resident_id: String in resident_registry.order:
		var occupation_id := OCCUPATION_RESIDENT_CONTEXT_RUNTIME.primary_id(
			self,
			resident_registry.records.get(resident_id, {}) as Dictionary,
		)
		if (task.get("eligibleOccupationIds", []) as Array).has(occupation_id):
			_schedule_decision(resident_id, true)


func _on_work_task_committed_for_log(task: Dictionary) -> void:
	WORLD_LOG_COMMIT_RUNTIME.work_task_committed(self, task)


func record_player_animal_pet(animal_id: String) -> Dictionary:
	return WORLD_LOG_COMMIT_RUNTIME.record_player_animal_pet(self, animal_id)


func query_world_log_threads(filters: Dictionary = {}) -> Dictionary:
	return world_log_domain.store.query_threads(filters.duplicate(true)) as Dictionary


func query_world_log_place_observations(
	place_id: String,
	options: Dictionary = {},
) -> Dictionary:
	return world_log_domain.store.query_place_observations(
		place_id,
		options.duplicate(true),
	) as Dictionary


func find_world_log_thread_by_source_event(event_id: String) -> Dictionary:
	return world_log_domain.store.find_thread_by_source_event(event_id) as Dictionary


func get_world_log_causal_chain(thread_id: String, options: Dictionary = {}) -> Dictionary:
	return world_log_domain.store.get_causal_chain(thread_id, options.duplicate(true)) as Dictionary


func get_world_log_thread_detail(thread_id: String, options: Dictionary = {}) -> Dictionary:
	return world_log_domain.store.get_thread_detail(thread_id, options.duplicate(true)) as Dictionary


func mark_world_log_thread_read(thread_id: String, displayed_through_sequence: int) -> Dictionary:
	return world_log_domain.store.mark_thread_read(thread_id, displayed_through_sequence) as Dictionary


func get_world_log_filter_catalog() -> Dictionary:
	return world_log_domain.store.get_filter_catalog() as Dictionary


func get_world_log_debug_snapshot() -> Dictionary:
	return {
		"timelineId": String(world_log_domain.store.get_timeline_id()),
		"recordCount": int(world_log_domain.store.get_record_count()),
		"consistencyError": world_log_domain.journal.consistency_error(),
	}


func _complete_agent_submission(result: Dictionary) -> Dictionary:
	var probe_started_usec := WORLD_PERFORMANCE_PROBE.start_lap()
	SOCIAL_MATTER_COMMAND_RUNTIME.schedule_receipt_wakes(self)
	probe_started_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_started_usec, "submission_social_receipts")
	_notify_world_revision()
	WORLD_PERFORMANCE_PROBE.record_lap(probe_started_usec, "submission_revision_notify")
	return result


func _bump_world_revision(notify := true) -> void:
	_world_revision += 1
	if notify:
		_notify_world_revision()


func _notify_world_revision() -> void:
	world_revision_changed.emit(_world_revision)


func _reset_social_runtimes() -> void:
	_social_matters = SOCIAL_MATTER_RUNTIME.new()
	_community_bulletin = COMMUNITY_BULLETIN_RUNTIME.new()
	_social_sources = SOCIAL_MATTER_SOURCE_ADAPTER.new()
	_social_agent_adapter = SOCIAL_AGENT_ADAPTER.new()
	_community_bulletin.bind_social_runtime(
		_social_matters,
	)
	_social_sources.bind_social_runtime(
		_social_matters,
	)
	_social_agent_adapter.bind_social_runtime(
		_social_matters,
	)


func _connect_conflict_controller_signals() -> void:
	if _conflict_controller == null:
		return
	for binding: Array in [
		["conflict_projection_changed", "_on_conflict_projection_changed"],
		["conflict_event_created", "_on_conflict_event_created"],
		["conflict_follow_up_required", "_on_conflict_follow_up_required"],
	]:
		var callback := Callable(self, String(binding[1]))
		if not _conflict_controller.is_connected(String(binding[0]), callback):
			_conflict_controller.connect(String(binding[0]), callback)


func _disconnect_conflict_controller_signals() -> void:
	if _conflict_controller == null:
		return
	for binding: Array in [
		["conflict_projection_changed", "_on_conflict_projection_changed"],
		["conflict_event_created", "_on_conflict_event_created"],
		["conflict_follow_up_required", "_on_conflict_follow_up_required"],
	]:
		var callback := Callable(self, String(binding[1]))
		if _conflict_controller.is_connected(String(binding[0]), callback):
			_conflict_controller.disconnect(String(binding[0]), callback)


func _on_conflict_projection_changed(projection: Dictionary) -> void:
	CONFLICT_WORLD_COORDINATION_RUNTIME.projection_changed(self, projection)


func _on_conflict_event_created(event: Dictionary) -> void:
	CONFLICT_WORLD_COORDINATION_RUNTIME.event_created(self, event)


func _on_conflict_follow_up_required(follow_up: Dictionary) -> void:
	CONFLICT_WORLD_COORDINATION_RUNTIME.follow_up_required(self, follow_up)


func _command_failure(
	error_code: String,
	errors: Array,
	extra: Dictionary = {},
	retryable := false,
) -> Dictionary:
	var result := {"ok": false, "errors": errors.duplicate(true)}
	for key: Variant in extra:
		var value: Variant = extra[key]
		if value is Dictionary:
			result[key] = (value as Dictionary).duplicate(true)
		elif value is Array:
			result[key] = (value as Array).duplicate(true)
		else:
			result[key] = value
	return _decorate_command_result(result, error_code, retryable)


func _decorate_command_result(
	source: Dictionary,
	error_code_on_failure := "",
	retryable := false,
) -> Dictionary:
	var result := source.duplicate(true)
	var ok: bool = result.get("ok") == true
	if ok:
		result["errorCode"] = ""
		result["retryable"] = false
	else:
		result["errorCode"] = (
			String(error_code_on_failure)
			if not String(error_code_on_failure).is_empty()
			else String(result.get("errorCode", ""))
		)
		result["retryable"] = (
			retryable
			if not String(error_code_on_failure).is_empty()
			else bool(result.get("retryable", false))
		)
	result["worldRevision"] = _world_revision
	return result


func _authoritative_absolute_minute() -> int:
	# 分钟结算循环内取当前 tick 的分钟;循环外取环境时钟。
	if _processing_tick_absolute_minute >= 0:
		return _processing_tick_absolute_minute
	return int(_environment.get_absolute_minute())


func _resident_can_accept_work_task(
	resident_id: String,
	task: Dictionary,
) -> bool:
	var resident := resident_registry.records.get(resident_id, {}) as Dictionary
	return _work.resident_can_accept_work_task(
		resident_id,
		task,
		resident,
		world_definition.world_data,
		_resident_is_present(resident),
		int(_environment.get_absolute_minute()),
	)


# 口信发送策略的最小能力端口；该策略需要能被轻量测试替身独立验证。
func _resident_can_work_occupation(
	resident_id: String,
	occupation_id: String,
) -> bool:
	return OCCUPATION_RESIDENT_CONTEXT_RUNTIME.can_work_occupation(
		self, resident_id, occupation_id,
	)


func _task_acceptance_occupation_id(
	resident_id: String,
	task: Dictionary,
) -> String:
	return _work.task_acceptance_occupation_id(
		resident_id,
		task,
		resident_registry.records.get(resident_id, {}) as Dictionary,
		world_definition.world_data,
		int(_environment.get_absolute_minute()),
	)


func broadcast_announcement(text: String) -> Dictionary:
	return ANNOUNCEMENT_COMMAND_RUNTIME.publish(
		self,
		_player_avatar_id(),
		text,
		"",
		"town_bell",
	)

func _private_message_delivery_task_for_talk(
	postal_resident_id: String,
	recipient_id: String,
	spoken_content: String,
) -> Dictionary:
	return private_message_runtime.delivery_task_for_talk(
		postal_resident_id,
		recipient_id,
		spoken_content,
		_work.tasks,
		Callable(self, "_resident_can_accept_work_task"),
	)



func _prepare_postal_talk_approach(
	resident: Dictionary,
	target: Dictionary,
	prepared: Dictionary,
) -> Dictionary:
	return POSTAL_DELIVERY_ACTION_PREPARER.prepare(
		world_definition.world_data,
		ACTION_GEOMETRY.indoor_navigation_for_space(self, String(resident.get("spaceId", ""))),
		resident,
		target,
		prepared,
		Callable(self, "_perception_membership_for_position"),
	)


func _perception_membership_for_position(
	space_id: String,
	position: Vector2,
) -> Dictionary:
	return PERCEPTION_RUNTIME._membership(self, space_id, position)
