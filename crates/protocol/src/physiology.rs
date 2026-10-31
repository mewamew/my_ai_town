//! 身体事实、生命历史及可执行能力；前端与 Agent 不推导死亡。
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BodyConditionKind {
    Injury,
    Illness,
    Poison,
}
impl BodyConditionKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::Injury => "受伤",
            Self::Illness => "疾病",
            Self::Poison => "中毒",
        }
    }
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BodyCondition {
    pub kind: BodyConditionKind,
    pub severity: f64,
    pub since: f64,
    pub source: String,
}
/// 生命历史里一条记录的来源。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BodyEventKind {
    /// 需求压力的通知
    Pressure,
    /// 使用道具带来的变化
    Prop,
    Death,
    /// 行动能力转换（失能、恢复行走或劳作）
    Ability,
    /// 直接设数值。游戏里已经没有这个入口，只为读旧存档和测试保留
    Experiment,
    /// 新的受伤、疾病或中毒
    Condition,
    Cure,
    Revive,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BodyEvent {
    pub at: f64,
    pub kind: BodyEventKind,
    pub source: String,
    pub text: String,
}
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Physiology {
    pub dead: bool,
    pub conditions: Vec<BodyCondition>,
    /// 饥饿、缺水、过劳的累计危险分钟，恢复到安全值后逐步消退。
    pub exposure: [f64; 3],
    /// 露天淋雨雪的累计进度，到上限着凉生病后清零；在室内或遮蔽处逐步变干。旧存档没有这一项。
    #[serde(default)]
    pub wet: f64,
    pub history: Vec<BodyEvent>,
    /// 遇害身亡时记下凶手和伤口；其他死因没有，复活时清掉。旧存档没有这一项。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub killed: Option<Killing>,
}
/// 遇害：谁下的手、留下什么伤。村民发现尸体时看得见伤口，看不见凶手。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Killing {
    pub by: crate::EventActor,
    pub wound: String,
}
/// 世界级生理开关：关掉的一项数值冻结，不限制活动，不进入村民观察。
/// `weather` 是天气影响身体：露天淋雨雪额外消耗精力，淋久了生病。旧存档没有这一项，按关闭读入。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PhysiologySwitches {
    pub fullness: bool,
    pub energy: bool,
    pub water: bool,
    pub health: bool,
    #[serde(default)]
    pub weather: bool,
}
impl Default for PhysiologySwitches {
    fn default() -> Self {
        Self {
            fullness: true,
            energy: true,
            water: true,
            health: true,
            weather: false,
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Life {
    Alive,
    Dead,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BodyView {
    pub revision: u64,
    pub life: Life,
    pub conditions: Vec<BodyCondition>,
    pub can_decide: bool,
    pub can_move: bool,
    pub can_labor: bool,
    pub limitation: String,
    pub causes: Vec<String>,
    pub exposure: [f64; 3],
    pub history: Vec<BodyEvent>,
    /// 遇害者身上的伤口；活人和其他死因没有。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wound: Option<String>,
}
