//! 计划队列的执行标识与动作组账本。
use crate::{
    intent::{BuiltinVerb, Intent},
    topology::Topology,
};
use protocol::{ActionDraft, ActionGroup, ActionResult, VerbKind};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// 一个动作组最多几项。
pub(crate) const GROUP_LIMIT: usize = 8;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionBinding {
    pub action_id: String,
    pub group_id: String,
    pub draft: ActionDraft,
}

impl ActionBinding {
    /// 动作编号：`{组}/{序号}`。
    pub(crate) fn id_for(group: &str, index: usize) -> String {
        format!("{group}/{index}")
    }

    /// 这个动作指定使用道具 id。
    pub(crate) fn uses_prop(&self, id: &str) -> bool {
        self.draft.prop_id.as_deref() == Some(id)
    }
}

/// 队列里的一项。存档按内容区分两种写法（untagged），变体名不进存档。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum QueuedAction {
    /// Agent 或玩家动作组里的一项：结束时写回执。
    Tracked {
        intent: Intent,
        action: Box<ActionBinding>,
    },
    /// 没有动作组、不写回执的一项：只出现在旧存档里（只存意图的队列，以及已删掉的控制台计划）。
    Untracked(Intent),
}

impl QueuedAction {
    pub fn intent(&self) -> &Intent {
        match self {
            Self::Tracked { intent, .. } | Self::Untracked(intent) => intent,
        }
    }

    pub(crate) fn binding(&self) -> Option<&ActionBinding> {
        match self {
            Self::Tracked { action, .. } => Some(action),
            Self::Untracked(_) => None,
        }
    }

    pub fn describe(&self, topo: &Topology) -> String {
        self.intent().describe(topo)
    }

    pub(crate) fn into_parts(self) -> (Intent, Option<ActionBinding>) {
        match self {
            Self::Tracked { intent, action } => (intent, Some(*action)),
            Self::Untracked(intent) => (intent, None),
        }
    }
}

/// 动作账本。`revision` 是安排修订号：旧观察和按旧修订号提交的命令一起作废。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ActionState {
    #[serde(default)]
    pub player_groups: std::collections::BTreeSet<String>,
    #[serde(default)]
    pub player_interactions: std::collections::BTreeSet<String>,
    #[serde(default)]
    pub cancel_after_current: bool,
    pub agent_controlled: bool,
    /// 玩家覆盖、模式切换或强制失能时增加；普通时间推进不改变它。
    pub revision: u64,
    pub groups: BTreeMap<String, ActionGroup>,
}

impl ActionState {
    /// 安排修订号加一：此前的观察作废，按旧修订号提交的命令会被拒绝。
    pub(crate) fn bump_revision(&mut self) {
        self.revision += 1;
    }
}

/// 动作草案属于哪一类：背包操作、前往、停留，其余是道具动作。
pub fn draft_verb_kind(draft: &ActionDraft) -> VerbKind {
    if draft.inventory.is_some() {
        return VerbKind::Inventory;
    }
    match BuiltinVerb::parse(&draft.intent.verb) {
        Some(BuiltinVerb::Goto) => VerbKind::Goto,
        Some(BuiltinVerb::Stay | BuiltinVerb::Sit | BuiltinVerb::Lie | BuiltinVerb::Look) => {
            VerbKind::Stay
        }
        // 动手和道具动作一样是一件有时长的事
        Some(BuiltinVerb::Push | BuiltinVerb::Rob | BuiltinVerb::Steal) | None => VerbKind::Prop,
    }
}

/// 动作组里一条结果对应的草案属于哪一类；按动作编号找草案，找不到时按道具动作。
pub fn result_verb_kind(group: &ActionGroup, result: &ActionResult) -> VerbKind {
    group
        .actions
        .iter()
        .enumerate()
        .find(|(i, _)| ActionBinding::id_for(&group.id, *i) == result.action_id)
        .map_or(VerbKind::Prop, |(_, draft)| draft_verb_kind(draft))
}
