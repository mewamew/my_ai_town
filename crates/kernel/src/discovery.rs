//! 发现尸体：活着、醒着、能行动的人和尸体在同一处所时（走进来、醒过来，或者事情就发生在眼前），
//! 记一条亲眼看到的事实、发一条显著通知，并像身体紧急时那样打断手上的安排。
//! 遇害的尸体看得见伤口、看得出是被人杀死的，看不出是谁干的；凶手自己不记。每人每具尸体只记一次。
use crate::{actor::Actor, props::Completion, World};
use protocol::{GroupStatus, Killing};

/// 一具尸体：编号、名字、所在处所、遇害记录。
struct Body {
    id: String,
    name: String,
    locale: String,
    killed: Option<Killing>,
}

impl World {
    /// 每个时间片末尾查一遍谁和没见过的尸体待在一起。
    pub(crate) fn notice_bodies(&mut self) {
        let bodies: Vec<Body> = self
            .actors
            .values()
            .filter(|a| a.present() && a.needs.body.dead)
            .map(|a| Body {
                id: a.id.clone(),
                name: a.name.clone(),
                locale: a.locus.locale.clone(),
                killed: a.needs.body.killed.clone(),
            })
            .collect();
        if bodies.is_empty() {
            return;
        }
        for id in self.actor_ids() {
            let a = &self.actors[&id];
            if !self.can_notice(a) {
                continue;
            }
            let seen = a.bodies_seen.as_ref();
            let found: Vec<&Body> = bodies
                .iter()
                .filter(|b| {
                    b.locale == a.locus.locale
                        && b.id != id
                        && !seen.is_some_and(|s| s.contains(&b.id))
                })
                .collect();
            for body in found {
                self.discover(&id, body);
            }
        }
    }

    /// 能发现东西的人：在场、活着、能行动、没在睡觉；化身是玩家的眼睛，不记。
    fn can_notice(&self, a: &Actor) -> bool {
        let asleep = crate::physiology::body_spot(self, a)
            .and_then(|s| s.action.as_ref())
            .is_some_and(|action| action.completion == Completion::Sleep);
        a.present() && !a.is_avatar() && !a.needs.incapacitated() && !asleep
    }

    fn discover(&mut self, id: &str, body: &Body) {
        let now = self.minutes;
        let killer = body.killed.as_ref().is_some_and(|k| k.by.id == id);
        let place = self.topo.locale_name(&body.locale);
        let a = self.actor_mut(id);
        a.bodies_seen
            .get_or_insert_with(Default::default)
            .insert(body.id.clone());
        if killer {
            return;
        }
        let text = match &body.killed {
            Some(k) => format!(
                "发现{}倒在{place}，已经没有呼吸，{}，像是被人杀死的",
                body.name, k.wound
            ),
            None => format!("发现{}倒在{place}，已经没有呼吸", body.name),
        };
        a.journal.record_seen(
            now,
            text.clone(),
            vec![body.id.clone(), body.locale.clone()],
        );
        a.notify(now, text.clone());
        let info = a.event_info();
        let log = format!("{} {text}", a.name);
        let busy = a.actions.agent_controlled
            && !a.player_controlled()
            && (a.current.interaction.is_some()
                || a.actions
                    .groups
                    .values()
                    .any(|g| g.status == GroupStatus::Running));
        self.log(info, log);
        if busy {
            self.interrupt_actions(id, "发现有人死了，重新考虑当前安排");
        }
    }
}
