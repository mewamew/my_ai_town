//! 线上类型：内核 ↔ 前端（Roster 流与观察仪命令），以及 Agent 与内核共用的动作、事实与互动结构。
//!
//! 协议边界纪律：
//! - Agent 意图不得携带几何；唯一例外是玩家专用的化身状态，以及三维前端碰撞
//!   解算后的 `avatar_input.pose`。`tests/wire.rs` 遍历其余线上变体守住边界。
//! - 时间只以分钟表述；`Transit { elapsed, total }` 是唯一标量度量，
//!   方向以拓扑表达（`toward` = 正在接近的驻留处所 id）。
//! - 枚举一律以 `snake_case` 上线；中文文案只在 Rust 侧的 `label()` 或前端的映射表里，
//!   任何一方都不拿中文做分支条件。

mod weather;
pub use weather::*;

mod actions;
mod avatar;
mod chat;
mod client_msg;
mod content;
mod interactions;
mod location;
mod model_config;
mod needs;
mod notebook;
mod observation;
mod physiology;
mod population;
mod props;
mod resident;
mod roster;
mod server_msg;
mod spatial;

pub use actions::{
    ActionDraft, ActionGroup, ActionResult, ActionStatus, FactKind, GroupStatus, InventoryAction,
    ReadableFact, WorldFact, WritingDraft,
};
pub use avatar::{
    AvatarActor, AvatarChatItem, AvatarCommand, AvatarGoal, AvatarInteraction, AvatarLease,
    AvatarMode, AvatarPairItem, AvatarPose, AvatarPropView, AvatarResultCode, AvatarSession,
    AvatarSight, AvatarState, AvatarView, AvatarWalk, NearbyPerson, PortalView, PositionAck,
    RecentEvent,
};
pub use chat::{
    ChatEntry, ChatEntryKind, ChatObservation, ChatPresence, ChatState, ChatSummary,
    InteractionObservation, NearbyChat, SpeechView,
};
pub use client_msg::{ClientMsg, IntentDraft, UntilPredicate};
pub use content::{
    ContentCommand, ContentDetail, ContentKind, ContentMetadata, ContentOrigin, ContentText,
};
pub use interactions::{Interaction, InteractionCommand, InteractionKind, InteractionStatus};
pub use location::{At, Locus};
pub use model_config::{
    ActiveModelChoice, ModelChoice, ProviderConfigMsg, ProviderKeyMsg, ProviderView,
};
pub use needs::{Need, NeedBand, NeedRules, NeedState, NeedsTuning};
pub use notebook::{
    NoteStatus, NotebookCategory, NotebookCount, NotebookDetail, NotebookDetailQuery,
    NotebookEntry, NotebookLink, NotebookQuery, NotebookSection, NotebookView,
};
pub use observation::{
    Alert, DeathCause, DiaryDay, EventActor, EventInfo, EventKind, ReceiptView, ThoughtView,
    TriggerInfo, TriggerKind,
};
pub use physiology::{
    BodyCondition, BodyConditionKind, BodyEvent, BodyEventKind, BodyView, Killing, Life,
    Physiology, PhysiologySwitches,
};
pub use population::{
    is_hex_color, Appearance, BeardStyle, FaceGear, HairStyle, Headwear, HeldItem, HomeView,
    JoinOutcome, JoinPreview, LibraryFilter, LibraryKind, LookPattern, Outfit, PatternTarget,
    PopulationView, ResidentRegistration, ResidentTemplate, TemplateCard, TemplateFields,
    TemplateStatus, VillagerLook, PATTERN_SIZE,
};
pub use props::{
    Choice, DurationRange, InventorySlot, InventoryView, ItemLocation, LegacyVerbView, PlaceNear,
    PlaceRef, PropActionEntry, PropActionView, PropCapabilities, PropPreview, PropView,
    PropsCatalog, RateRange, StoredItem, SupplyView,
};
pub use resident::{
    ActionResultView, AgentLimitRanges, AgentLimits, AgentState, AgentUsage, EvidenceSource,
    GoalStatus, HoldCause, LimitRange, MemoryKind, MemoryStatus, PauseKind, RequestKind,
    RequestStatus, RequestView, ResidentAgentView, ResidentGoalView, ResidentInteractionView,
    ResidentMemoryView, ResidentUsage, UsageSummary, WorldHold,
};
pub use roster::{
    ActivityKind, MemberKind, MovementPhase, MovementView, PlanView, RosterLocale, RosterMember,
    VerbKind,
};
pub use server_msg::{ServerMsg, WorldSettingsView};
pub use spatial::{Point3, PropPosition, Route, SpatialOverride, SpatialOverridesView};

/// 把值当作 `serde_json::Value` 输出：对象的键按字母序排列。
///
/// 内核视图改用结构体之前由 `serde_json::json!` 拼成，输出时对象键按字母序。视图结构体
/// 自己的字段按字母序声明；嵌进视图、字段声明顺序不是字母序的已有类型用这个函数输出，
/// 线上 JSON 与改动前逐字节一致。
pub fn sorted<T: serde::Serialize, S: serde::Serializer>(
    value: &T,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    use serde::Serialize;
    serde_json::to_value(value)
        .map_err(serde::ser::Error::custom)?
        .serialize(serializer)
}
