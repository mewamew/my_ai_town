//! 道具与背包的线上视图：动作说明、道具列表、背包与容器、道具编辑能力表。
//! 视图结构体的字段按字母序声明，序列化结果与改用结构体之前的 JSON 逐字节一致。
use crate::{ContentMetadata, Locus};
use serde::{Deserialize, Serialize};

/// 可携带道具的位置：在谁身上、存在哪个容器里，或放在哪个落脚点。也是存档里背包表的值。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum ItemLocation {
    Carried { actor: String },
    Stored { container: String },
    Ground { locale: String, station: String },
}

/// 摆道具时玩家在地图上点的位置，坐标系同化身的行走坐标（米）。只是选点偏好：
/// 放置器照旧按留白规则找空位，取离这一点最近的那个。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PlaceNear {
    pub space: String,
    pub position: [f64; 2],
}

/// 有限补给：初始份数与每次消耗的份数。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SupplyView {
    pub cost: u32,
    pub initial: u32,
}

/// 道具动作的说明：用时、效果、条件与结果。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PropActionView {
    pub conditions: Vec<String>,
    pub consumes_item: bool,
    pub effects: Vec<String>,
    pub id: String,
    pub label: String,
    pub minutes: f64,
    /// 只能对在场的别人用（复活、伤人）：玩家选对象时不列自己。
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub others_only: bool,
    pub portion_name: Option<String>,
    pub recipient: bool,
    /// 只有道具列表给出：补给剩余份数，没有有限补给时为 null。动作说明里没有这个键。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub remaining: Option<Option<u32>>,
    pub result: String,
    pub supply: Option<SupplyView>,
}

/// 旧格式地图道具的动作：只有动作词与时长，没有效果定义。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LegacyVerbView {
    pub conditions: Vec<String>,
    pub effects: Vec<String>,
    pub id: String,
    pub label: String,
    pub minutes: Option<f64>,
    pub result: String,
}

/// 道具列表里的一个动作。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum PropActionEntry {
    Defined(PropActionView),
    Legacy(LegacyVerbView),
}

/// 设定中心道具页的一件道具。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PropView {
    pub actions: Vec<PropActionEntry>,
    pub board: Option<String>,
    pub bulletin_board: bool,
    /// 运行时放置的道具（不是地图自带的）。
    pub custom: bool,
    pub definition: Option<String>,
    pub id: String,
    pub locale: String,
    #[serde(serialize_with = "crate::sorted")]
    pub location: Option<ItemLocation>,
    pub location_name: Option<String>,
    pub name: String,
    pub occupants: Vec<String>,
    pub on_map: bool,
    pub portable: bool,
    /// 精确导航地图上放下的物品、运行中放进来的道具画在哪里。
    pub position: Option<[f64; 3]>,
    pub readable: Option<ContentMetadata>,
    pub stack_limit: u32,
    pub storage_slots: u32,
    /// 二维行走地图上道具的位置。
    #[serde(serialize_with = "crate::sorted")]
    pub walk_position: Option<Locus>,
    pub withdrawn: bool,
}

/// 背包里的一格：同样的物品叠在一起。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InventorySlot {
    pub actions: Vec<PropActionView>,
    pub definition: Option<String>,
    pub items: Vec<String>,
    pub name: String,
    pub quantity: usize,
    pub readable: Option<ContentMetadata>,
}

/// 一个人的背包：格数上限、已用格数与每一格。
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct InventoryView {
    pub capacity: usize,
    pub slots: Vec<InventorySlot>,
    pub used: usize,
}

/// 容器里存着的一件物品。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StoredItem {
    pub definition: Option<String>,
    pub id: String,
    pub name: String,
}

/// 道具编辑器里的一个选项。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Choice {
    pub id: String,
    pub label: String,
}

/// 动作时长的范围（分钟，整数）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DurationRange {
    pub max: u32,
    pub min: u32,
}

/// 恢复速度的范围（点/分钟）；上限是整数。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RateRange {
    pub max: u32,
    pub min: f64,
}

/// 道具编辑器能选的效果、条件与完成方式。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PropCapabilities {
    pub completion_effects: Vec<Choice>,
    pub completions: Vec<Choice>,
    pub conditions: Vec<Choice>,
    pub duration: DurationRange,
    pub effects: Vec<Choice>,
    pub max_actions: usize,
    pub needs: Vec<Choice>,
    pub rate: RateRange,
    pub schema_version: u32,
    pub supports_recipients: bool,
    pub supports_supply: bool,
}

/// 道具目录：定义、各定义的动作说明、实例、可选能力与可放置地点。
/// 线上按字段名字母序输出（`ServerMsg` 里经 `crate::sorted`）。
#[derive(Debug, Clone, Serialize)]
pub struct PropsCatalog {
    pub capabilities: PropCapabilities,
    pub definition_actions: std::collections::BTreeMap<String, Vec<PropActionView>>,
    /// 道具定义原文，即内核 `props::Definition` 的 JSON：类型和校验规则在内核，protocol 不依赖内核。
    pub definitions: Vec<serde_json::Value>,
    pub instances: Vec<PropView>,
    pub locations: Vec<PlaceRef>,
    pub persistent: bool,
    pub schema_version: u32,
    pub spatial: Option<crate::SpatialOverridesView>,
    pub world_id: String,
}

/// 地点的编号与名字；residential 是能分给村民当住宅的地点，道具页按它把住宅单独分一组。
#[derive(Debug, Clone, Serialize)]
pub struct PlaceRef {
    pub id: String,
    pub name: String,
    pub residential: bool,
}

/// 道具与作品命令成功时的内容。
#[derive(Debug, Clone, Serialize)]
#[serde(untagged)]
pub enum PropPreview {
    /// 校验或保存道具定义：定义原文（内核 `props::Definition` 的 JSON），校验时另带各动作说明。
    Definition {
        definition: serde_json::Value,
        #[serde(skip_serializing_if = "Option::is_none")]
        actions: Option<Vec<PropActionView>>,
    },
    /// 作品详情。
    Content(Box<crate::ContentDetail>),
    /// 只有成败、没有内容的操作：移除、放置。
    Done {},
}
