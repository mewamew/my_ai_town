//! 双方互动的两种投影：给模型看的观察 JSON，给观察仪看的摘要行。
//! 两者面向不同读者、字段不同，但都只从这里取参与者与结果文案。
use kernel::World;
use protocol::{Interaction, InteractionKind, InteractionStatus, ResidentInteractionView};
use serde_json::{json, Value};
use std::collections::BTreeSet;

/// 给模型的观察：只露出被赠予的那几件物品，不露出对方的其他随身物和未读正文。约定的时刻（at）
/// 发出前统一写成「D3 14:00」（context::clean）。
pub fn observation(world: &World, actor: &str, interaction: &Interaction) -> Value {
    let mut view = json!(kernel::interactions::Interactions::observation(
        actor,
        interaction
    ));
    if let InteractionKind::Give { items } = &interaction.kind {
        let offered = world
            .topo
            .props()
            .iter()
            .filter(|p| items.contains(&p.id) && !p.withdrawn);
        view["offered_items"] = json!(crate::observation::item_stacks(world, offered, true));
    }
    view
}

/// 参与者：进行中的聊天只算在场成员，结束后算所有到过的人加发起者与受邀者。
fn participants(interaction: &Interaction) -> Vec<&String> {
    let both = [&interaction.initiator, &interaction.partner];
    match &interaction.chat {
        Some(c) if interaction.status == InteractionStatus::Running => c.members.iter().collect(),
        Some(c) => c
            .ever_members
            .iter()
            .chain(both)
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect(),
        None => both.to_vec(),
    }
}

fn result_text(interaction: &Interaction) -> String {
    if let Some(last) = interaction.changes.last() {
        return last.clone();
    }
    match interaction.status {
        InteractionStatus::Offered => "邀请已发出，对方尚未同意".into(),
        InteractionStatus::Running if interaction.kind.walk_leader().is_some() => {
            "正在同行，到了地方会结束".into()
        }
        InteractionStatus::Running
            if matches!(interaction.kind, InteractionKind::Appointment { .. }) =>
        {
            "约好了，到时在约好的地方见".into()
        }
        InteractionStatus::Running if interaction.chat.is_some() => {
            "大家正在交谈，可继续说话、倾听或告辞".into()
        }
        _ => "双方已同意，等待世界结果".into(),
    }
}

/// 给观察仪的摘要行。
pub fn summary(world: &World, interaction: &Interaction) -> ResidentInteractionView {
    ResidentInteractionView {
        id: interaction.id.clone(),
        title: interaction.kind.label().into(),
        status: interaction.status,
        participants: participants(interaction)
            .into_iter()
            .filter_map(|id| world.actor(id).map(|a| a.name.clone()))
            .collect(),
        result: result_text(interaction),
    }
}
