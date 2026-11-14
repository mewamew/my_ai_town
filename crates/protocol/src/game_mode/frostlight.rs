//! 霜灯镇：所有库存、政策、劳动和结局由世界结算，页面只呈现已确认的状态。
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FrostlightPhase {
    Preparation,
    Cold,
    Storm,
    Over,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct FrostlightPolicies {
    pub extended_shift: bool,
    pub soup: bool,
    pub mutual_aid: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FrostlightStation {
    pub id: String,
    pub name: String,
    pub locale: String,
    pub available: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FrostlightWork {
    pub kind: String,
    pub locale: String,
    /// 预计完工时刻；实际须等待走路与劳动动作组成功，受阻时可以更晚。
    pub ends_at: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FrostlightPerson {
    pub id: String,
    pub name: String,
    pub role: String,
    pub contribution: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub work: Option<FrostlightWork>,
    pub gone: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FrostlightNews {
    pub at: f64,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FrostlightEnding {
    pub kind: String,
    pub title: String,
    pub text: String,
    pub survivors: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FrostlightView {
    pub phase: FrostlightPhase,
    pub now: f64,
    pub until: f64,
    pub storm_at: f64,
    pub ends_at: f64,
    pub temperature: f64,
    pub shelter_temperature: f64,
    pub cold_minutes: f64,
    pub hunger_minutes: f64,
    pub unrest_minutes: f64,
    pub fuel: f64,
    pub food: f64,
    pub materials: f64,
    pub heat: u32,
    pub stress: f64,
    pub hope: f64,
    pub discontent: f64,
    pub insulation: u32,
    pub generator: String,
    pub stations: Vec<FrostlightStation>,
    pub policies: FrostlightPolicies,
    pub aid_used: bool,
    pub people: Vec<FrostlightPerson>,
    pub news: Vec<FrostlightNews>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ending: Option<FrostlightEnding>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FrostlightContext {
    pub phase: String,
    pub me: String,
    pub goal: String,
    pub now: String,
    pub resources: String,
    pub stations: Vec<String>,
    pub actions: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub news: Vec<String>,
}
