//! 展示需要的结构化信息；中文措辞、时钟格式不承担逻辑标识。
use crate::{BodyConditionKind, HoldCause, Need, PauseKind};
use serde::{Deserialize, Serialize};

/// 世界日志一行的种类；前端按它分类和过滤，正文只用来显示。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventKind {
    /// 世界里发生的事：活动、互动、生命记录、天气、加入与离开等
    #[default]
    World,
    /// 出发与到达
    Movement,
    /// 模型请求与响应的台账行
    Model,
}

/// 日志说的是谁：人物编号与当时的名字。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EventActor {
    pub id: String,
    pub name: String,
}

/// 死亡时正在造成损害的来源：持续低值的需求与身体状况。只有随时间推进的损害有，
/// 直接设数值、道具效果、改生理开关导致的死亡两项都为空。遇害时另记凶手和伤口。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeathCause {
    pub shortages: Vec<Need>,
    pub conditions: Vec<BodyConditionKind>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub killed: Option<crate::Killing>,
}

/// 需要提示卡的事件；前端按种类写标题和说明，不解析正文。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Alert {
    /// 健康耗尽，死亡
    Death(DeathCause),
    /// 新出现受伤、疾病或中毒
    Condition { condition: BodyConditionKind },
    /// 健康危重：无法自主活动或决策，需要他人救助
    Critical,
    /// 额度用尽或故障导致全镇暂停；cause 与 provider 同 `WorldHold`
    Hold {
        pause: PauseKind,
        reason: String,
        #[serde(default)]
        cause: HoldCause,
        #[serde(default, skip_serializing_if = "String::is_empty")]
        provider: String,
    },
}

/// 世界日志一行的结构化部分：种类、说的是谁、需要提示卡时的细节。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct EventInfo {
    pub kind: EventKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub actor: Option<EventActor>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub alert: Option<Alert>,
}

impl EventInfo {
    /// 说的是某个人的世界事件。
    pub fn about(id: &str, name: &str) -> Self {
        Self {
            actor: Some(EventActor {
                id: id.into(),
                name: name.into(),
            }),
            ..Self::default()
        }
    }
    /// 某人出发或到达。
    pub fn movement(id: &str, name: &str) -> Self {
        Self {
            kind: EventKind::Movement,
            ..Self::about(id, name)
        }
    }
    /// 模型请求与响应的台账行。
    pub fn model() -> Self {
        Self {
            kind: EventKind::Model,
            ..Self::default()
        }
    }
    /// 带上提示卡的细节。
    pub fn with_alert(mut self, alert: Option<Alert>) -> Self {
        self.alert = alert;
        self
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TriggerKind {
    QueueLow,
    Notice,
    ActivityFailed,
    #[default]
    Text,
}

/// 一次规划的触发原因。`text` 是人类可读的原因；前端按 `kind` 决定标签，纯文字来源直接显示 `text`。
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct TriggerInfo {
    pub kind: TriggerKind,
    /// 通知或失败发生的原始模拟分钟；纯文字来源没有此字段。
    pub at: Option<f64>,
    pub action: Option<String>,
    pub text: String,
}

impl TriggerInfo {
    pub fn text(text: &str) -> Self {
        Self {
            text: text.into(),
            ..Self::default()
        }
    }
}

/// 一条执行记录：原始时间、展示时钟与正文分开给；死亡这类生命记录另带提示卡的细节。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReceiptView {
    pub sim_minutes: f64,
    pub clock: String,
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub alert: Option<Alert>,
}

/// 村民最近一次决定时的自述想法（只读投影；不是世界事实，观察仪标「自述」）。
/// `line` 是第一句（≤ 20 字），供气泡；`trigger_info` 是那次规划的触发原因。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ThoughtView {
    #[serde(default)]
    pub sim_minutes: f64,
    #[serde(default)]
    pub trigger_info: TriggerInfo,
    pub text: String,
    pub line: String,
    pub clock: String,
}

/// 日志里的一天（天亮到天亮）：世界写的执行记录、当天的想法、次日早上他写的「昨天」。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DiaryDay {
    /// 「D1」「D2」…
    pub label: String,
    pub receipts: Vec<ReceiptView>,
    pub thoughts: Vec<ThoughtView>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    /// 正在进行中的今天
    pub current: bool,
}
