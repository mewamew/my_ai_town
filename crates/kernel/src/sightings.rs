//! 人来人往：有人离开一个地点、来到一个地点时，同在那里的村民看得见。走的人在赶路就看得出往哪去，
//! 化身这样自己走的只知道离开了。只记已知地点（街道、路段不算），同行的人互相不记。
//! 每人上次所在的地点只在运行期记着：读档后从当时的位置重新记，不补发。
use crate::World;
use protocol::{FactKind, InteractionKind};
use std::collections::BTreeMap;

/// 事件对象里标明是来了还是走了，和聊天事件的 `chat:编号:序号` 同一写法。
pub const ARRIVED: &str = "presence:arrived";
pub const LEFT: &str = "presence:left";

impl World {
    /// 每段时间推进后比一比每个人所在的地点，有变化就告诉旧地点和新地点里的人。
    pub(crate) fn note_presence(&mut self) {
        let now_places: Vec<(String, Option<String>)> = self
            .actors
            .values()
            .map(|a| {
                let place = a
                    .present()
                    .then(|| self.enclosing_place(&a.locus.locale))
                    .flatten();
                (a.id.clone(), place)
            })
            .collect();
        let Some(seen) = self.places_seen.as_mut() else {
            self.places_seen = Some(now_places.into_iter().collect::<BTreeMap<_, _>>());
            return;
        };
        let mut moves = Vec::new();
        for (id, place) in now_places {
            match seen.insert(id.clone(), place.clone()) {
                Some(before) if before != place => moves.push((id, before, place)),
                _ => {}
            }
        }
        for (id, before, place) in moves {
            if let Some(old) = &before {
                let text = self.departure_text(&id, old, place.as_deref());
                self.tell_place(&id, old, LEFT, text);
            }
            if let Some(new) = &place {
                let text = self.arrival_text(&id);
                self.tell_place(&id, new, ARRIVED, text);
            }
        }
    }

    /// 处所算在哪个已知地点里：地点本身；两头都只通到同一个地点的路段（走到地点里道具跟前的
    /// 通道）也算在那个地点里，在广场上走到公告栏跟前不算离开了广场。街道和别的路段不算。
    fn enclosing_place(&self, locale: &str) -> Option<String> {
        if self.topo.place_of(locale).is_some() {
            return Some(locale.into());
        }
        let mut ends = self.topo.passages.iter().filter_map(|p| {
            if p.a == locale {
                Some(&p.b)
            } else if p.b == locale {
                Some(&p.a)
            } else {
                None
            }
        });
        let first = ends.next()?;
        (self.topo.place_of(first).is_some() && ends.all(|e| e == first)).then(|| first.clone())
    }

    /// 「何青往苏晴家去了」「陈默跟着旅人走了」「旅人离开了小广场」。
    fn departure_text(&self, id: &str, old: &str, new: Option<&str>) -> String {
        let a = &self.actors[id];
        if let Some(leader) = self.following(id) {
            return format!("{}跟着{}走了", a.name, self.actors[leader].name);
        }
        let heading = match (&a.current.kind, new) {
            (crate::world::ActKind::Travel { journey, .. }, _) => {
                Some(journey.dest_locale.as_str())
            }
            (_, Some(new)) => Some(new),
            _ => None,
        };
        match heading.filter(|d| *d != old) {
            Some(dest) => format!("{}往{}去了", a.name, self.topo.locale_name(dest)),
            None => format!("{}离开了{}", a.name, self.topo.locale_name(old)),
        }
    }

    /// 「何青来了」「陈默跟着旅人来了」。
    fn arrival_text(&self, id: &str) -> String {
        let a = &self.actors[id];
        match self.following(id) {
            Some(leader) => format!("{}跟着{}来了", a.name, self.actors[leader].name),
            None => format!("{}来了", a.name),
        }
    }

    /// 告诉这个地点里能看见的村民：受 Agent 控制、醒着能动、不是同行的伙伴。
    fn tell_place(&mut self, mover: &str, place: &str, mark: &str, text: String) {
        let now = self.minutes;
        let companions: Vec<String> = self
            .interactions
            .walk_of(mover)
            .and_then(|w| w.chat.as_ref())
            .map(|c| c.members.iter().cloned().collect())
            .unwrap_or_default();
        let watchers: Vec<String> = self
            .actors
            .values()
            .filter(|a| {
                a.id != mover
                    && a.present()
                    && a.locus.locale == place
                    && a.actions.agent_controlled
                    && !a.player_controlled()
                    && !a.needs.incapacitated()
                    && !companions.contains(&a.id)
            })
            .map(|a| a.id.clone())
            .collect();
        for id in watchers {
            self.actor_mut(&id).journal.fact(
                now,
                FactKind::Presence,
                text.clone(),
                vec![mover.into(), place.into(), mark.into()],
                None,
                None,
            );
        }
    }

    /// 邀请发出后有一方走开了（不在场、不在同一处所，玩家参与的走出 WITHDRAW_DISTANCE 米）：
    /// 邀请作废，双方都收到通知，在等回应的人随之醒来，不再原地干等。
    pub(crate) fn withdraw_departed_offers(&mut self) {
        let now = self.minutes;
        let stale: Vec<(String, String)> = self
            .interactions
            .items
            .values()
            .filter(|i| i.status == protocol::InteractionStatus::Offered)
            .filter_map(|i| Some((i.id.clone(), self.departed(i)?)))
            .collect();
        for (id, who) in stale {
            let name = self.actors[&who].name.clone();
            self.interactions.end(
                &mut self.actors,
                now,
                &id,
                protocol::InteractionStatus::Cancelled,
                Some(format!("{name}已经走开，邀请作废")),
            );
        }
    }

    /// 邀请双方里走开的那个人；都还在为空。
    fn departed(&self, i: &protocol::Interaction) -> Option<String> {
        const WITHDRAW_DISTANCE: f64 = 8.0;
        let (a, b) = (self.actors.get(&i.initiator)?, self.actors.get(&i.partner)?);
        for x in [a, b] {
            if !x.present() {
                return Some(x.id.clone());
            }
        }
        if self.player_pair_place(&a.id, &b.id, &i.kind).is_some() {
            let reach = crate::avatar::Reach::new(self);
            let (p, q) = (reach.talk_spot(&a.id)?, reach.talk_spot(&b.id)?);
            let near = p.space == q.space
                && crate::avatar::distance(p.position, q.position) <= WITHDRAW_DISTANCE;
            let player = if a.player_controlled() { a } else { b };
            return (!near).then(|| player.id.clone());
        }
        if a.locus.locale == b.locus.locale || matches!(i.kind, InteractionKind::Serve { .. }) {
            return None;
        }
        Some(if a.locus.locale != i.locale { a } else { b }.id.clone())
    }
}
