//! 目标里的人来了：正停留着的人提前结束停留，在等着的人醒来。何青到了小广场、陈默就在旁边，
//! 不必站完提前排好的 40 分钟才开口；等人「回头再来」的人，那人一来就醒。
use super::{ResidentRuntime, Trace};
use crate::session::{PendingTool, Session};
use kernel::{intent::BuiltinVerb, sightings::ARRIVED, World};
use protocol::{FactKind, GroupStatus};
use serde_json::json;

/// 走到一个地方后开始停留的这么多分钟内，那里已经有目标里的人就提前结束。
const FRESH_STAY_MINUTES: f64 = 1.0;

impl ResidentRuntime {
    pub(super) fn react_to_arrivals(&mut self, world: &mut World, s: &mut Session) {
        let Some(a) = world.actor(&s.actor_id) else {
            return;
        };
        let arrived: Vec<String> = a
            .journal
            .events_after(s.cursors.last_presence)
            .iter()
            .filter(|e| e.kind == FactKind::Presence && e.objects.iter().any(|o| o == ARRIVED))
            .filter_map(|e| e.objects.first().cloned())
            .collect();
        s.cursors.last_presence = a.journal.cursor();
        let Some((fresh_trip, here)) = staying(world, s) else {
            return;
        };
        let relevant = |id: &String| {
            world
                .actor(id)
                .is_some_and(|p| s.goals_mention(id, &p.name))
        };
        // 新来的人；或者刚走到这里开始停留，要找的人早就在这儿
        let who = arrived
            .iter()
            .find(|id| relevant(id))
            .or_else(|| {
                fresh_trip
                    .then(|| here.iter().find(|id| relevant(id)))
                    .flatten()
            })
            .cloned();
        let Some(who) = who else {
            return;
        };
        let name = world.actor(&who).map_or(who.clone(), |p| p.name.clone());
        let reason = format!("{name}在这里，先不站着等了");
        world.interrupt_actions(&s.actor_id, &reason);
        self.record(
            world,
            s,
            Trace::new("stay_cut_short", json!({"person": who, "reason": reason})),
        );
    }
}

/// 正在停留（自己的动作组里当前这一步是停留）：返回这次停留是不是刚走到这里才开始的，
/// 以及同一处所里的其他人。不在停留中为空。
fn staying(world: &World, s: &Session) -> Option<(bool, Vec<String>)> {
    let a = world.actor(&s.actor_id)?;
    let group = s.pending.iter().find_map(|p| match p {
        PendingTool::Actions { group_id, .. } => world
            .action_group(&s.actor_id, group_id)
            .filter(|g| g.status == GroupStatus::Running),
        _ => None,
    })?;
    let step = group.results.len();
    let current = group.actions.get(step)?;
    if BuiltinVerb::parse(&current.intent.verb) != Some(BuiltinVerb::Stay) {
        return None;
    }
    let after_trip = group.actions[..step]
        .iter()
        .any(|d| BuiltinVerb::parse(&d.intent.verb) == Some(BuiltinVerb::Goto));
    let fresh = after_trip && world.minutes() - a.current.started_at <= FRESH_STAY_MINUTES;
    let here = world
        .actor_ids()
        .into_iter()
        .filter(|id| {
            *id != s.actor_id
                && world
                    .actor(id)
                    .is_some_and(|p| p.present() && p.locus.locale == a.locus.locale)
        })
        .collect();
    Some((fresh, here))
}

/// 等待期间（游标之后）来了目标里的人：等待提前结束。
pub(super) fn relevant_arrival(world: &World, s: &Session, after: u64) -> bool {
    let Some(a) = world.actor(&s.actor_id) else {
        return false;
    };
    a.journal.events_after(after).iter().any(|e| {
        e.kind == FactKind::Presence
            && e.objects.iter().any(|o| o == ARRIVED)
            && e.objects.first().is_some_and(|id| {
                world
                    .actor(id)
                    .is_some_and(|p| s.goals_mention(id, &p.name))
            })
    })
}
