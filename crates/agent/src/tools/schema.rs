//! 工具参数 schema。枚举取值从 serde 类型生成，长度上限来自 limits，两处都不手抄。
use super::limits::*;
use crate::{
    memory::MemoryKind,
    notebook::NoteStatus,
    session::{GoalCondition, GoalStatus},
};
use protocol::{FactKind, InteractionCommand, InteractionKind, InventoryAction, UntilPredicate};
use serde::Serialize;
use serde_json::{json, Map, Value};

/// 列出枚举全部变体。match 穷举保证新增变体时这里编译失败，不会漏进 schema。
/// 带字段的变体给一个样例值，只用来取 serde 标签，字段内容无意义。
macro_rules! variants {
    ($ty:ident { $($v:ident),+ $(,)? }) => {
        variants!($ty { $($v => $ty::$v),+ })
    };
    ($ty:ident { $($v:ident => $sample:expr),+ $(,)? }) => {{
        fn exhaustive(v: &$ty) {
            match v { $($ty::$v { .. } => {}),+ }
        }
        let list: Vec<$ty> = vec![$($sample),+];
        list.iter().for_each(exhaustive);
        list
    }};
}

/// 等待能等到的事件。动作结果和阅读结果只来自自己手上的动作，等待时手上没有动作，永远等不到。
pub(super) fn wait_events() -> Vec<FactKind> {
    fact_kinds()
        .into_iter()
        .filter(|k| !matches!(k, FactKind::Action | FactKind::Readable))
        .collect()
}
fn fact_kinds() -> Vec<FactKind> {
    variants!(FactKind {
        Observation,
        Readable,
        Notice,
        Action,
        Speech,
        Interaction,
        Presence
    })
}
pub(crate) fn memory_kinds() -> Vec<MemoryKind> {
    variants!(MemoryKind {
        Episode,
        Recognition,
        Experience
    })
}
pub(crate) fn goal_statuses() -> Vec<GoalStatus> {
    variants!(GoalStatus {
        Active,
        Paused,
        Completed,
        Abandoned,
        Failed
    })
}
pub(crate) fn note_statuses() -> Vec<NoteStatus> {
    variants!(NoteStatus {
        Candidate,
        Supported,
        Rejected
    })
}
pub(crate) fn goal_conditions() -> Vec<GoalCondition> {
    let s = String::new;
    variants!(GoalCondition {
        Action => GoalCondition::Action { verb: s(), locale: s() },
        Interaction => GoalCondition::Interaction { interaction_id: s() },
    })
}
pub(crate) fn inventory_actions() -> Vec<InventoryAction> {
    let s = String::new;
    variants!(InventoryAction {
        PickUp => InventoryAction::PickUp { items: vec![] },
        Drop => InventoryAction::Drop { items: vec![] },
        Store => InventoryAction::Store { items: vec![], container: s() },
        Retrieve => InventoryAction::Retrieve { items: vec![], container: s() },
        Take => InventoryAction::Take { source: s(), action: s(), quantity: 1 },
    })
}
pub(crate) fn until_predicates() -> Vec<UntilPredicate> {
    variants!(UntilPredicate { Dawn, Dusk })
}
pub(crate) fn interaction_kinds() -> Vec<InteractionKind> {
    let s = String::new;
    variants!(InteractionKind {
        Talk => InteractionKind::Talk,
        Give => InteractionKind::Give { items: vec![] },
        Serve => InteractionKind::Serve { prop_id: s(), verb: s() },
        Walk => InteractionKind::Walk { leader: s(), locale: None },
        Appointment => InteractionKind::Appointment { locale: s(), at: 0.0 },
        Touch => InteractionKind::Touch { gesture: protocol::Gesture::Hug },
    })
}
pub(crate) fn interaction_commands() -> Vec<InteractionCommand> {
    let s = String::new;
    variants!(InteractionCommand {
        Join => InteractionCommand::Join { interaction_id: s(), message: s() },
        Say => InteractionCommand::Say { interaction_id: s(), message: s(), to: None },
        Listen => InteractionCommand::Listen { interaction_id: s() },
        Leave => InteractionCommand::Leave { interaction_id: s(), message: s() },
        Offer => InteractionCommand::Offer { partner_id: s(), interaction: InteractionKind::Talk, message: s() },
        Reply => InteractionCommand::Reply { interaction_id: s(), accept: false, message: s() },
        Cancel => InteractionCommand::Cancel { interaction_id: s() },
        Propose => InteractionCommand::Propose { interaction_id: s(), interaction: InteractionKind::Talk, message: s(), to: None },
        Accept => InteractionCommand::Accept { interaction_id: s(), message: s(), locale: None },
        Decline => InteractionCommand::Decline { interaction_id: s(), message: s() },
    })
}

/// 无字段枚举的线上取值。
pub(crate) fn names<T: Serialize>(list: &[T]) -> Vec<String> {
    list.iter().map(crate::labels::wire_name).collect()
}
/// 带标签枚举某个变体的标签取值。
fn tag_of<T: Serialize>(value: &T, tag: &str) -> Value {
    serde_json::to_value(value).expect("枚举可序列化")[tag].clone()
}

fn object(properties: Value, required: &[&str]) -> Value {
    json!({
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": false
    })
}
fn string(max: usize) -> Value {
    json!({"type":"string","maxLength":max})
}
fn text(max: usize) -> Value {
    json!({"type":"string","minLength":1,"maxLength":max})
}
fn described(mut schema: Value, description: &str) -> Value {
    schema["description"] = json!(description);
    schema
}
fn enumeration<T: Serialize>(list: &[T]) -> Value {
    json!({"type":"string","enum":names(list)})
}
fn strings(max_items: usize, item_chars: usize) -> Value {
    json!({"type":"array","items":string(item_chars),"maxItems":max_items})
}
fn ids(min_items: usize, max_items: usize) -> Value {
    json!({
        "type": "array",
        "items": {"type":"integer","minimum":1},
        "minItems": min_items,
        "maxItems": max_items
    })
}

/// 带标签枚举：平铺全部分支的字段，标签字段用 enum 列出取值。每个分支都要的字段标为必填，
/// 只有部分分支要的字段由运行时校验时提示，schema 不再重复一份分支定义。
fn tagged<T: Serialize>(
    tag: &str,
    list: &[T],
    branch: impl Fn(&T) -> (Value, Vec<&'static str>),
) -> Value {
    let mut properties = Map::new();
    let mut tags = Vec::new();
    let mut always: Option<Vec<&str>> = None;
    for variant in list {
        tags.push(tag_of(variant, tag));
        let (fields, required) = branch(variant);
        properties.extend(fields.as_object().cloned().unwrap_or_default());
        always = Some(match always {
            None => required,
            Some(common) => common
                .into_iter()
                .filter(|f| required.contains(f))
                .collect(),
        });
    }
    properties.insert(tag.into(), json!({"type":"string","enum":tags}));
    let required: Vec<&str> = std::iter::once(tag)
        .chain(always.unwrap_or_default())
        .collect();
    object(Value::Object(properties), &required)
}

fn items() -> Value {
    described(
        json!({"type":"array","items":{"type":"string"},"minItems":1,"maxItems":ITEMS_MAX}),
        "实际物品 ID，来自 inventory 或可见道具",
    )
}

fn intent() -> Value {
    object(
        json!({
            "verb": described(json!({"type":"string"}), "前往、停留，或可见道具的 action_id"),
            "locale": described(json!({"type":"string"}), "前往的目的地点"),
            "target": described(json!({"type":"string"}), "精确落脚点 ID，通常省略"),
            "duration_minutes": {"type":"number","exclusiveMinimum":0,"maximum":DURATION_MINUTES_MAX},
            "until": enumeration(&until_predicates())
        }),
        &["verb"],
    )
}

fn inventory() -> Value {
    tagged("operation", &inventory_actions(), |action| match action {
        InventoryAction::PickUp { .. } | InventoryAction::Drop { .. } => {
            (json!({"items":items()}), vec!["items"])
        }
        InventoryAction::Store { .. } | InventoryAction::Retrieve { .. } => (
            json!({"items":items(),"container":{"type":"string"}}),
            vec!["items", "container"],
        ),
        InventoryAction::Take { .. } => (
            json!({
                "source": {"type":"string"},
                "action": {"type":"string"},
                "quantity": {"type":"integer","minimum":1,"maximum":TAKE_QUANTITY_MAX}
            }),
            vec!["source", "action", "quantity"],
        ),
    })
}

fn action() -> Value {
    object(
        json!({
            "intent": intent(),
            "inventory": inventory(),
            "writing": object(
                json!({"title":text(WRITING_TITLE_CHARS),"text":text(WRITING_TEXT_CHARS)}),
                &["title", "text"],
            ),
            "recipient": described(json!({"type":"string"}), "接受者村民 ID，仅道具声明支持时填"),
            "prop_id": described(json!({"type":"string"}), "道具 ID，与 intent 同级")
        }),
        &["intent"],
    )
}

fn condition() -> Value {
    tagged("kind", &goal_conditions(), |c| match c {
        GoalCondition::Action { .. } => (
            json!({"verb":{"type":"string"},"locale":{"type":"string"}}),
            vec!["verb", "locale"],
        ),
        GoalCondition::Interaction { .. } => (
            json!({"interaction_id":{"type":"string"}}),
            vec!["interaction_id"],
        ),
    })
}

fn interaction() -> Value {
    tagged("kind", &interaction_kinds(), |k| match k {
        InteractionKind::Talk => (json!({}), vec![]),
        InteractionKind::Give { .. } => (json!({"items":items()}), vec!["items"]),
        InteractionKind::Serve { .. } => (
            json!({"prop_id":{"type":"string"},"verb":{"type":"string"}}),
            vec!["prop_id", "verb"],
        ),
        InteractionKind::Walk { .. } => (
            json!({
                "leader": described(json!({"type":"string"}), "同行时谁带路：self 是自己，或填对方 ID"),
                "locale": described(json!({"type":"string"}), "同行的目的地或约定的见面地点，known_places.id；同行由自己带路时写上，世界直接带大家出发")
            }),
            vec!["leader"],
        ),
        InteractionKind::Appointment { .. } => (
            json!({
                "locale": {"type":"string"},
                "at": described(json!({"type":"string"}), "约定时刻，写成 D日数 HH:MM，例如 D3 14:00；要在十分钟以后、一天以内")
            }),
            vec!["locale", "at"],
        ),
        InteractionKind::Touch { .. } => (
            json!({
                "gesture": described(json!({"type":"string","enum":["hold_hands","lean","hug"]}), "亲近的方式：hold_hands 牵手，lean 依偎，hug 拥抱")
            }),
            vec!["gesture"],
        ),
    })
}

pub(super) fn memory_search() -> Value {
    object(
        json!({
            "query": text(QUERY_CHARS),
            "directory": {"type":"string"},
            "offset": {"type":"integer","minimum":0},
            "limit": {"type":"integer","minimum":1,"maximum":SEARCH_LIMIT_MAX}
        }),
        &["query"],
    )
}
pub(super) fn memory_read() -> Value {
    object(
        json!({
            "path": {"type":"string"},
            "offset": {"type":"integer","minimum":0},
            "limit": {"type":"integer","minimum":1,"maximum":READ_LIMIT_MAX}
        }),
        &["path"],
    )
}
pub(super) fn reflect() -> Value {
    let quote = object(
        json!({"event_id":{"type":"integer","minimum":1},"text":text(QUOTE_CHARS)}),
        &["event_id", "text"],
    );
    let note = object(
        json!({
            "path": {"type":"string"},
            "title": string(NOTE_TITLE_CHARS),
            "text": string(NOTE_TEXT_CHARS),
            "event_ids": ids(1, NOTE_EVENT_IDS_MAX),
            "status": enumeration(&note_statuses()),
            "reading_quotes": described(
                json!({"type":"array","maxItems":QUOTES_MAX,"items":quote}),
                "引用阅读内容时填实际原文"
            )
        }),
        &["path", "title", "text", "event_ids", "status"],
    );
    object(
        json!({
            "through_event": {"type":"integer","minimum":1},
            "summary": text(REFLECT_SUMMARY_CHARS),
            "notes": described(
                json!({"type":"array","maxItems":NOTES_MAX,"items":note}),
                "由你决定记什么，允许空数组；引用书中原文先用 read_content 核对"
            )
        }),
        &["through_event", "summary", "notes"],
    )
}
pub(super) fn read_content() -> Value {
    object(
        json!({"event_id":{"type":"integer","minimum":1}}),
        &["event_id"],
    )
}
pub(super) fn observe() -> Value {
    object(json!({}), &[])
}
pub(super) fn recall() -> Value {
    object(
        json!({
            "text": string(QUERY_CHARS),
            "object": {"type":"string"},
            "kind": enumeration(&memory_kinds()),
            "since": {"type":"number","minimum":0},
            "until": {"type":"number","minimum":0},
            "limit": {"type":"integer","minimum":1,"maximum":RECALL_LIMIT_MAX}
        }),
        &[],
    )
}
pub(super) fn inspect() -> Value {
    object(json!({"id":{"type":"string"}}), &["id"])
}
/// 玩法动作：能交哪些 action、target 怎么填由开着的玩法在工具说明里写。
pub(super) fn mode_action() -> Value {
    object(
        json!({
            "action": {"type":"string","minLength":1,"maxLength":32},
            "target": {"type":"string","maxLength":32},
            "text": string(MODE_TEXT_CHARS),
            "reason": string(MODE_REASON_CHARS)
        }),
        &["action"],
    )
}
/// 玩法动作里一段话、一句理由的上限。
const MODE_TEXT_CHARS: usize = 600;
const MODE_REASON_CHARS: usize = 200;
pub(super) fn set_goal() -> Value {
    object(
        json!({
            "id": {"type":"string","minLength":1,"maxLength":GOAL_ID_BYTES},
            "title": text(GOAL_TITLE_CHARS),
            "condition": condition(),
            "status": enumeration(&goal_statuses()),
            "next_steps": strings(GOAL_STEPS_MAX, GOAL_STEP_CHARS),
            "commitment": string(GOAL_TEXT_CHARS),
            "reason": string(GOAL_TEXT_CHARS),
            "due_clock": {"type":"string","maxLength":16,"description":"约定时刻，如 D2 14:00；省略沿用，空串清除"}
        }),
        &["id", "title", "status"],
    )
}
pub(super) fn run_actions() -> Value {
    object(
        json!({"actions":{"type":"array","items":action(),"minItems":1,"maxItems":ACTIONS_MAX}}),
        &["actions"],
    )
}
pub(super) fn interact() -> Value {
    interaction_operations(|c| {
        !matches!(
            c,
            InteractionCommand::Offer { .. } | InteractionCommand::Reply { .. }
        )
    })
}
/// 交谈轮次的 interact：say、listen、leave，以及提议一起走和回答提议。
pub(super) fn chat_interact() -> Value {
    interaction_operations(|c| {
        matches!(
            c,
            InteractionCommand::Say { .. }
                | InteractionCommand::Listen { .. }
                | InteractionCommand::Leave { .. }
                | InteractionCommand::Propose { .. }
                | InteractionCommand::Accept { .. }
                | InteractionCommand::Decline { .. }
        )
    })
}
fn interaction_operations(keep: impl Fn(&InteractionCommand) -> bool) -> Value {
    let id = || json!({"interaction_id":{"type":"string"}});
    let message = || string(MESSAGE_CHARS);
    let commands: Vec<_> = interaction_commands()
        .into_iter()
        .filter(|c| keep(c))
        .collect();
    tagged("operation", &commands, |c| match c {
        InteractionCommand::Join { .. } | InteractionCommand::Leave { .. } => {
            let mut fields = id();
            fields["message"] = message();
            (fields, vec!["interaction_id", "message"])
        }
        InteractionCommand::Say { .. } => {
            let mut fields = id();
            fields["message"] = text(MESSAGE_CHARS);
            fields["to"] = json!({"type":"string"});
            (fields, vec!["interaction_id", "message"])
        }
        InteractionCommand::Listen { .. } | InteractionCommand::Cancel { .. } => {
            (id(), vec!["interaction_id"])
        }
        InteractionCommand::Offer { .. } => offer_fields(),
        InteractionCommand::Reply { .. } => reply_fields(),
        InteractionCommand::Propose { .. } => {
            let mut fields = id();
            fields["interaction"] = interaction();
            fields["message"] = message();
            fields["to"] = json!({"type":"string"});
            (fields, vec!["interaction_id", "interaction", "message"])
        }
        InteractionCommand::Accept { .. } => {
            let mut fields = id();
            fields["message"] = message();
            fields["locale"] = described(
                json!({"type":"string"}),
                "自己带路而提议没写目的地时，补上要去的 known_places.id",
            );
            (fields, vec!["interaction_id"])
        }
        InteractionCommand::Decline { .. } => {
            let mut fields = id();
            fields["message"] = message();
            (fields, vec!["interaction_id"])
        }
    })
}
/// 发邀请与回应邀请的参数；独立工具和 interact 的分支共用。
fn offer_fields() -> (Value, Vec<&'static str>) {
    (
        json!({"partner_id":{"type":"string"},"interaction":interaction(),"message":string(MESSAGE_CHARS)}),
        vec!["partner_id", "interaction", "message"],
    )
}
fn reply_fields() -> (Value, Vec<&'static str>) {
    (
        json!({"interaction_id":{"type":"string"},"accept":{"type":"boolean"},"message":string(MESSAGE_CHARS)}),
        vec!["interaction_id", "accept", "message"],
    )
}
pub(super) fn wait_for() -> Value {
    object(
        json!({
            "minutes": {"type":"number","minimum":WAIT_MINUTES.start(),"maximum":WAIT_MINUTES.end()},
            "event": enumeration(&wait_events()),
            "reason": string(WAIT_REASON_CHARS)
        }),
        &["reason"],
    )
}

/// 上下文原文读取独立于长期记忆开关。
pub(super) fn context_read() -> Value {
    object(
        json!({
            "source":{"type":"integer","minimum":1},
            "pointer":string(512),
            "offset":{"type":"integer","minimum":0},
            "limit":{"type":"integer","minimum":1,"maximum":crate::context::input::PAGE_CHARS}
        }),
        &["source"],
    )
}

pub(super) fn offer_invitation() -> Value {
    let (fields, required) = offer_fields();
    object(fields, &required)
}
pub(super) fn reply_invitation() -> Value {
    let (fields, required) = reply_fields();
    object(fields, &required)
}
