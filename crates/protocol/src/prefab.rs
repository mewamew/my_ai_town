//! 预制开局的冻结计划与提交游标；世界变化和游标在同一检查点提交。
use crate::{
    Climate, GameModeChoice, ModelChoice, PhysiologySwitches, PlaceNear, TemplateFields,
    VillagerLook, WeatherKind,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PrefabSetupSelection {
    pub players: usize,
    pub models: Vec<Option<ModelChoice>>,
    pub needs: bool,
    pub picks: Vec<(String, String)>,
    pub seeds: Vec<(String, u32)>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PrefabSetupPlan {
    pub prefab: String,
    /// 只用于恢复开局界面；执行始终使用已经冻结的 steps，不重新解释客户端选项。
    pub selection: PrefabSetupSelection,
    pub steps: Vec<PrefabSetupStep>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PrefabSetupState {
    pub id: String,
    pub plan: PrefabSetupPlan,
    pub next_step: usize,
    pub joined: Vec<String>,
}

impl PrefabSetupState {
    pub fn complete(&self) -> bool {
        self.next_step == self.plan.steps.len()
    }
}

/// 只开放开局所需的操作，不接受任意嵌套客户端命令。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum PrefabSetupStep {
    Worldview {
        text: String,
    },
    Physiology {
        switches: PhysiologySwitches,
    },
    Climate {
        climate: Climate,
    },
    Weather {
        weather: WeatherKind,
    },
    RemoveProp {
        id: String,
    },
    PlaceProp {
        instance: Value,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        near: Option<PlaceNear>,
    },
    Limits {
        limits: Value,
    },
    Join {
        template_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        model: Option<ModelChoice>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        persona: Option<Box<TemplateFields>>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        look: Option<Box<VillagerLook>>,
    },
    GameMode {
        choice: GameModeChoice,
    },
}
