//! 校验双方活动、同意记录与事件来源，全部通过后才允许恢复世界。
//! 时刻与时长只查取值范围和先后关系，不和当前常量比相等：常量以后再改，旧存档照样能读。
use super::{INVITE_MINUTES, MESSAGE_MAX_CHARS};
use crate::error::{KernelError, Result};
use crate::{
    activity::ActKind, actor::Actor, intent::StopCond, inventory::MAX_TRANSFER, topology::Topology,
    World, DAY, ID_MAX_BYTES,
};

// 邀请有效期不超过一天，读档的范围校验才不会拒收新存档。
const _: () = assert!(INVITE_MINUTES <= DAY);
use protocol::{Interaction, InteractionKind, InteractionStatus as Status};
use std::collections::{BTreeMap, BTreeSet};

pub(crate) fn validate(
    items: &BTreeMap<String, Interaction>,
    actors: &BTreeMap<String, Actor>,
    world: &World,
    now: f64,
) -> Result<()> {
    let heard = super::chat_validation::HeardEvents::build(actors);
    // 一个人同时只在一场进行中的交谈或同行里
    let mut talking = BTreeSet::new();
    for c in items
        .values()
        .filter(|i| i.status == Status::Running)
        .filter_map(|i| i.chat.as_ref())
    {
        for m in &c.members {
            ensure!(
                talking.insert(m.as_str()),
                KernelError::snapshot("一个人同时在两场交谈或同行里")
            );
        }
    }
    for (id, item) in items {
        validate_item(id, item, actors, &world.topo, now)?;
        if item.chat.is_some() {
            super::chat_validation::validate(item, actors, world, now, &heard)?;
            continue;
        }
        let participants: BTreeSet<_> = [item.initiator.clone(), item.partner.clone()].into();
        validate_event_sources(item, &participants, actors)?;
        let appointment = matches!(item.kind, InteractionKind::Appointment { .. });
        if item.status == Status::Running && !appointment {
            for actor in &participants {
                validate_running_participant(item, &participants, &actors[actor], now)?;
            }
        }
        validate_kind(item, world)?;
    }
    for (id, a) in actors {
        match &a.current.interaction {
            Some(key) => ensure!(
                items.get(key).is_some_and(|i| {
                    i.includes(id)
                        && i.status == Status::Running
                        && i.chat.as_ref().is_none_or(|c| c.members.contains(id))
                }),
                KernelError::snapshot("活动引用了无效互动")
            ),
            None => ensure!(
                a.current.participants.len() == 1,
                KernelError::snapshot("多人活动缺少共同互动编号")
            ),
        }
    }
    Ok(())
}

/// 身份、时间与状态机的一致性。
fn validate_item(
    id: &str,
    item: &Interaction,
    actors: &BTreeMap<String, Actor>,
    topo: &Topology,
    now: f64,
) -> Result<()> {
    ensure!(
        id == item.id && !id.is_empty() && id.len() <= ID_MAX_BYTES,
        KernelError::snapshot("存档互动编号无效")
    );
    // 玩家搭话可以在路上（见 World::player_pair_place），交谈的地点也可以是路段
    let place_ok = topo.is_dwell(&item.locale)
        || (item.kind.has_chat() && topo.locales.contains_key(&item.locale));
    ensure!(
        item.initiator != item.partner
            && actors.contains_key(&item.initiator)
            && actors.contains_key(&item.partner)
            && place_ok,
        KernelError::snapshot("存档互动的双方或地点无效")
    );
    ensure!(
        item.created_at.is_finite()
            && item.created_at >= 0.0
            && item.created_at <= now
            && item.expires_at > item.created_at
            && item.expires_at - item.created_at <= DAY,
        KernelError::snapshot("存档互动的创建或过期时间无效")
    );
    ensure!(
        item.duration_minutes > 0.0 && item.duration_minutes <= DAY,
        KernelError::snapshot("存档互动时长无效")
    );
    ensure!(
        item.message.chars().count() <= MESSAGE_MAX_CHARS
            && item
                .reply
                .as_ref()
                .is_none_or(|r| r.chars().count() <= MESSAGE_MAX_CHARS),
        KernelError::snapshot("存档互动消息超长")
    );
    ensure!(
        item.reply.is_some() == item.accepted.is_some(),
        KernelError::snapshot("存档互动的回应与同意记录不一致")
    );
    ensure!(
        !item.started_at.is_some_and(|t| {
            !t.is_finite() || t < item.created_at || t > now || t >= item.expires_at
        }),
        KernelError::snapshot("存档互动开始时间无效")
    );
    ensure!(
        !item.ended_at.is_some_and(|t| {
            !t.is_finite() || t < item.started_at.unwrap_or(item.created_at) || t > now
        }),
        KernelError::snapshot("存档互动结束时间无效")
    );
    ensure!(
        item.status.terminal() == item.ended_at.is_some(),
        KernelError::snapshot("存档互动的结束状态与结束时间不一致")
    );
    let state_ok = match item.status {
        Status::Offered => {
            item.accepted.is_none() && item.started_at.is_none() && item.expires_at > now
        }
        Status::Running | Status::Succeeded => {
            item.accepted == Some(true) && item.started_at.is_some()
        }
        Status::Declined => item.accepted == Some(false),
        _ => true,
    };
    ensure!(
        state_ok,
        KernelError::snapshot("存档互动的状态与同意记录不一致")
    );
    Ok(())
}

/// 互动挂着的事件都属于可以听到它的人（`allowed`），且事件确实提到这项互动。聊天与双人互动共用。
pub(super) fn validate_event_sources(
    item: &Interaction,
    allowed: &BTreeSet<String>,
    actors: &BTreeMap<String, Actor>,
) -> Result<()> {
    for (actor, ids) in &item.event_ids {
        ensure!(
            allowed.contains(actor),
            KernelError::snapshot("存档互动事件属于局外人")
        );
        ensure!(
            ids.iter().all(|id| {
                actors[actor]
                    .journal
                    .event(*id)
                    .is_some_and(|e| e.objects.contains(&item.id))
            }),
            KernelError::snapshot("存档互动事件来源无效")
        );
    }
    Ok(())
}

/// 进行中的双人活动：双方的活动都指向这项互动，且剩余时长一致。
fn validate_running_participant(
    item: &Interaction,
    participants: &BTreeSet<String>,
    a: &Actor,
    now: f64,
) -> Result<()> {
    let started_at = item.started_at.expect("进行中的互动有开始时刻");
    let remain = item.duration_minutes - (now - started_at);
    let expected_verb = match &item.kind {
        InteractionKind::Serve { verb, .. } if a.id == item.partner => verb.as_str(),
        _ => item.kind.label(),
    };
    ensure!(
        a.actions.agent_controlled && !a.needs.incapacitated(),
        KernelError::snapshot("存档互动参与者不能行动")
    );
    ensure!(
        a.locus.locale == item.locale
            && a.current.locale == item.locale
            && a.current.interaction.as_ref() == Some(&item.id)
            && a.current.participants == *participants
            && a.current.action.is_none()
            && a.plan.is_empty()
            && a.current.verb == expected_verb
            && a.current.started_at == started_at,
        KernelError::snapshot("存档的双方互动活动不同步")
    );
    ensure!(
        remain > 0.0
            && matches!(&a.current.kind, ActKind::Timed { cond: StopCond::Duration(m) } if (*m - remain).abs() < 1e-6),
        KernelError::snapshot("存档的双方互动剩余时长不同步")
    );
    Ok(())
}

fn validate_kind(item: &Interaction, world: &World) -> Result<()> {
    match &item.kind {
        InteractionKind::Give { items } => {
            ensure!(
                !items.is_empty()
                    && items.len() <= MAX_TRANSFER
                    && items.iter().collect::<BTreeSet<_>>().len() == items.len(),
                KernelError::snapshot("存档赠品列表无效")
            );
            if item.status == Status::Running {
                world.inventory.check_gift(
                    &world.topo,
                    &world.props,
                    &item.initiator,
                    &item.partner,
                    items,
                )?;
            }
        }
        // 时长已在 validate_item 里查过范围；不和道具当前的标称时长比相等，改了道具时长旧存档照样能读。
        InteractionKind::Serve { prop_id, verb } => {
            let spot = world
                .affordances
                .for_prop(prop_id, verb)
                .ok_or_else(|| KernelError::snapshot("存档餐饮道具无效"))?;
            ensure!(
                spot.restores_fullness()
                    && world
                        .topo
                        .prop(prop_id)
                        .is_some_and(|p| p.locale == item.locale),
                KernelError::snapshot("存档餐饮服务条件无效")
            );
        }
        InteractionKind::Talk => {}
        InteractionKind::Walk { .. } => unreachable!("同行带聊天状态，按聊天校验"),
        // 时刻只查范围：约好的时间和地点在存档里，读档后照常提醒和判定
        InteractionKind::Appointment { locale, at } => ensure!(
            at.is_finite()
                && *at >= item.created_at
                && *at <= item.created_at + crate::DAY
                && world.topo.place_of(locale).is_some(),
            KernelError::snapshot("存档约定的时间或地点无效")
        ),
    }
    Ok(())
}
