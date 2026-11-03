//! 聊天互动的存档校验：成员、轮次、记录顺序与每个成员的活动都要对得上。
use super::MESSAGE_MAX_CHARS;
use crate::actor::Actor;
use crate::error::{KernelError, Result};
use protocol::{ChatState, Interaction, InteractionKind, InteractionStatus as Status};
use std::collections::{BTreeMap, BTreeSet, HashSet};

/// 每位听者收到过的聊天记录事件：(听者, "chat:{聊天}:{序号}", 时刻)。读档时建一次，
/// 逐条聊天记录查表，不再每条都扫听者的全部事件。
pub(super) struct HeardEvents<'a>(HashSet<(&'a str, &'a str, u64)>);

/// 时刻按位比较；加 0.0 把 -0.0 并到 0.0，和浮点相等的判断一致（时刻都已校验为有限数）。
fn time_key(at: f64) -> u64 {
    (at + 0.0).to_bits()
}

impl<'a> HeardEvents<'a> {
    pub(super) fn build(actors: &'a BTreeMap<String, Actor>) -> Self {
        let mut heard = HashSet::new();
        for (id, a) in actors {
            for e in &a.journal.events {
                for object in e.objects.iter().filter(|o| o.starts_with("chat:")) {
                    heard.insert((id.as_str(), object.as_str(), time_key(e.at)));
                }
            }
        }
        Self(heard)
    }

    fn contains(&self, reader: &str, key: &str, at: f64) -> bool {
        self.0.contains(&(reader, key, time_key(at)))
    }
}

pub(super) fn validate(
    i: &Interaction,
    actors: &BTreeMap<String, Actor>,
    world: &crate::World,
    now: f64,
    heard: &HeardEvents,
) -> Result<()> {
    let c = super::chat::chat_of(i);
    let allowed: BTreeSet<_> = c
        .ever_members
        .iter()
        .cloned()
        .chain([i.initiator.clone(), i.partner.clone()])
        .collect();
    ensure!(
        i.kind.has_chat(),
        KernelError::snapshot("聊天互动必须是交谈或同行")
    );
    validate_walk(i, c, &allowed, world)?;
    validate_proposal(i, c, now)?;
    ensure!(
        c.resume_at.is_finite() && c.resume_at >= 0.0,
        KernelError::snapshot("聊天恢复时刻无效")
    );
    ensure!(
        c.members.is_subset(&c.ever_members) && allowed.iter().all(|id| actors.contains_key(id)),
        KernelError::snapshot("聊天成员无效")
    );
    ensure!(
        c.turn_queue.iter().collect::<BTreeSet<_>>().len() == c.turn_queue.len()
            && c.turn_queue.iter().all(|a| c.members.contains(a)),
        KernelError::snapshot("聊天轮次无效")
    );
    let members_match_status = if i.status == Status::Running {
        c.members.len() >= 2 && !c.turn_queue.is_empty()
    } else {
        c.members.is_empty() && c.turn_queue.is_empty()
    };
    ensure!(
        members_match_status,
        KernelError::snapshot("聊天成员与互动状态不一致")
    );
    validate_entries(i, c, &allowed, heard, now)?;
    super::validation::validate_event_sources(i, &allowed, actors)?;
    for actor in &c.members {
        validate_member_activity(i, c, &actors[actor])?;
    }
    Ok(())
}

/// 聊天记录按序号递增、时间不倒退，每位听者都有对应的事件。
fn validate_entries(
    i: &Interaction,
    c: &ChatState,
    allowed: &BTreeSet<String>,
    heard: &HeardEvents,
    now: f64,
) -> Result<()> {
    let mut last = i.created_at;
    for (n, e) in c.entries.iter().enumerate() {
        ensure!(
            e.seq == n as u64 + 1 && e.at.is_finite() && e.at >= last && e.at <= now,
            KernelError::snapshot("聊天记录顺序无效")
        );
        ensure!(
            allowed.contains(&e.actor)
                && e.audience.is_subset(allowed)
                && e.audience.contains(&e.actor),
            KernelError::snapshot("聊天记录的说话人或听者无效")
        );
        ensure!(
            e.text.chars().count() <= MESSAGE_MAX_CHARS,
            KernelError::snapshot("聊天记录内容无效")
        );
        let key = format!("chat:{}:{}", i.id, e.seq);
        ensure!(
            e.audience
                .iter()
                .all(|reader| heard.contains(reader, &key, e.at)),
            KernelError::snapshot("聊天记录缺少听者事件来源")
        );
        last = e.at;
    }
    Ok(())
}

/// 同行：带路人是到过的人之一，进行中的同行里还在队伍里；目的地是已知地点；地图要能走。
fn validate_walk(
    i: &Interaction,
    c: &ChatState,
    allowed: &BTreeSet<String>,
    world: &crate::World,
) -> Result<()> {
    let InteractionKind::Walk { leader, locale } = &i.kind else {
        return Ok(());
    };
    ensure!(
        allowed.contains(leader)
            && locale
                .as_ref()
                .is_none_or(|l| world.topo.place_of(l).is_some())
            && (i.status != Status::Running
                || (c.members.contains(leader) && world.walk_map.is_some())),
        KernelError::snapshot("存档同行的带路人或目的地无效")
    );
    Ok(())
}

/// 等人回答的提议：只在进行中的交谈里，提议人和被问的人都还在，提议的是一起走。
fn validate_proposal(i: &Interaction, c: &ChatState, now: f64) -> Result<()> {
    let Some(p) = &c.proposal else {
        return Ok(());
    };
    let walk_ok = matches!(&p.interaction, InteractionKind::Walk { leader, .. }
        if *leader == p.by || *leader == p.to);
    ensure!(
        i.status == Status::Running
            && i.kind == InteractionKind::Talk
            && p.by != p.to
            && c.members.contains(&p.by)
            && c.members.contains(&p.to)
            && p.at.is_finite()
            && p.at <= now
            && walk_ok,
        KernelError::snapshot("存档交谈里的提议无效")
    );
    Ok(())
}

/// 在场成员的活动：无期占位、指向这场聊天、参与者集合就是成员集合。
/// 同行里只有跟随的村民占着活动；带路人和玩家操控的人不占，位置也不必在同一处所。
fn validate_member_activity(i: &Interaction, c: &ChatState, a: &Actor) -> Result<()> {
    if let Some(leader) = i.kind.walk_leader() {
        ensure!(a.present(), KernelError::snapshot("同行的人不在场"));
        let carried = a.id != leader && a.actions.agent_controlled && !a.player_controlled();
        let bound = a.current.interaction.as_ref() == Some(&i.id);
        ensure!(
            if carried {
                bound
                    && a.current.participants == c.members
                    && a.current.action.is_none()
                    && a.plan.is_empty()
                    && a.current.is_open_ended()
            } else {
                !bound
            },
            KernelError::snapshot("同行的活动与成员不同步")
        );
        return Ok(());
    }
    ensure!(
        a.controllable() && !a.needs.incapacitated(),
        KernelError::snapshot("聊天成员不能行动")
    );
    ensure!(
        a.locus.locale == i.locale
            && a.current.locale == i.locale
            && a.current.interaction.as_ref() == Some(&i.id)
            && a.current.participants == c.members
            && a.current.action.is_none()
            && a.plan.is_empty()
            && a.current.is_open_ended(),
        KernelError::snapshot("聊天活动与成员不同步")
    );
    Ok(())
}
