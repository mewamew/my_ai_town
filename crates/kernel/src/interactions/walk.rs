//! 同行：带路人领着人走。同行是一场会移动的交谈：聊天成员就是同行的人，带路人以外都是跟随者。
//! 跟随的村民由世界沿带路人的足迹带着走，期间不需要做决定；带路人和玩家操控的人自己走。
//! 到了说好的地方、带路人在某处停下、有人跟丢或身体出状况，世界就结束同行或让那个人退出。
use super::chat::{chat_of, chat_of_mut};
use super::Interactions;
use crate::avatar::{distance, Spot};
use crate::navigation::follow::{Follower, Trail};
use crate::{World, DAY};
use protocol::{
    ActionDraft, IntentDraft, Interaction, InteractionKind, InteractionStatus as Status,
};
use std::collections::BTreeMap;

/// 同行最长多久（分钟）：没写目的地又一直没停下，到时就停下来想想。存档里同行的时长就是它。
pub(crate) const WALK_MINUTES: f64 = 60.0;
/// 同行开始后路上默认不轮流说话：轮次停这么久，有人开口（请求发言）才恢复。
pub(crate) const QUIET_MINUTES: f64 = DAY;
/// 化身或附身的人带路时的步速，是村民步速的几倍：跟随的村民追得上。
pub const LEAD_PACE: f64 = 1.2;
/// 跟随者离带路人（按足迹长度）保持的距离（米）；多人同行时依次往后排开。
const FOLLOW_GAP: f64 = 1.2;
const FOLLOW_SPACING: f64 = 0.9;
/// 落后超过这么多米就加快到 CATCH_UP_PACE 追上去。
const CATCH_UP_BEHIND: f64 = 2.5;
const CATCH_UP_PACE: f64 = 1.5;
/// 世界推进同行的最长间隔（分钟）：跟随者每走这么一小段就按带路人的新位置重算。
const WALK_TICK: f64 = 0.25;
/// 没写目的地时，带路人在一个地点停留这么久（分钟）、跟随的人也在那里，就算到了。
const SETTLE_MINUTES: f64 = 1.5;
/// 跟随者离带路人这么近（米）以内、在同一空间里，到地方时就算一起到了。
const ARRIVE_REACH: f64 = 3.0;
/// 离带路人超过这么远（米）、不在同一空间，或被挡住走不动，累计这么久（分钟）就算跟丢。
const LOST_DISTANCE: f64 = 25.0;
const LOST_MINUTES: f64 = 6.0;
/// 世界替受 Agent 控制的带路人排的「前往」：动作组编号是同行编号加这个后缀。
const LEAD_SUFFIX: &str = "/lead";

/// 同行的运行期状态：带路人的足迹、各人的跟随进度、落后与停留的计时。不存档，读档后重新记。
#[derive(Debug, Clone, Default)]
pub(crate) struct WalkTrails(BTreeMap<String, WalkTrail>);

#[derive(Debug, Clone, Default)]
struct WalkTrail {
    trail: Trail,
    followers: BTreeMap<String, Follower>,
    /// 各跟随者已经落后或被挡住多久（分钟）。
    apart: BTreeMap<String, f64>,
    /// 带路人在当前地点已经停了多久（分钟），以及是哪个地点。
    settled: f64,
    settled_at: Option<String>,
}

impl Interactions {
    /// 进行中的同行。
    pub(crate) fn walks(&self) -> impl Iterator<Item = &Interaction> {
        self.items
            .values()
            .filter(|i| i.status == Status::Running && i.kind.walk_leader().is_some())
    }

    /// 本人所在的、进行中的同行（带路或跟随）。
    pub fn walk_of(&self, actor: &str) -> Option<&Interaction> {
        self.walks()
            .find(|i| i.chat.as_ref().is_some_and(|c| c.members.contains(actor)))
    }

    /// 本人正在带路。
    pub fn leads_walk(&self, actor: &str) -> bool {
        self.walk_led_by(actor).is_some()
    }

    /// 本人正在带的那场同行。
    pub(crate) fn walk_led_by(&self, actor: &str) -> Option<&Interaction> {
        self.walk_of(actor)
            .filter(|i| i.kind.walk_leader() == Some(actor))
    }
}

impl World {
    /// 本人在同行里跟着谁：跟随者返回带路人的编号，带路人和不在同行里的人为空。
    pub fn following(&self, actor: &str) -> Option<&str> {
        let leader = self.interactions.walk_of(actor)?.kind.walk_leader()?;
        (leader != actor).then_some(leader)
    }

    /// 这个动作组是世界替带路人排的「前往」（见 lead_off）：不经本人的工具调用，村民会话里
    /// 没有对应记录，由世界推进到地方。同行提前结束（跟丢、不跟了、走满时限）时这一步照样
    /// 走完，所以只认同行记录和带路人，不看同行是否还在进行。
    pub fn is_lead_group(&self, actor: &str, group_id: &str) -> bool {
        group_id
            .strip_suffix(LEAD_SUFFIX)
            .and_then(|walk| self.interactions.get(walk))
            .is_some_and(|walk| walk.kind.walk_leader() == Some(actor))
    }

    /// 跟随者由世界带着走：受 Agent 控制、不是带路人、没被玩家操控。
    pub(crate) fn walk_carries(&self, actor: &str, leader: &str) -> bool {
        actor != leader
            && self
                .actors
                .get(actor)
                .is_some_and(|a| a.actions.agent_controlled && !a.player_controlled())
    }

    /// 受 Agent 控制的带路人已经站在说好的目的地、手上没有别的事，同行却还没结束：有人还没跟上
    /// （多半是自己走的化身）。他在原地等，不另作打算；人到齐、有人没跟上或不跟了，同行结束时
    /// 才醒来，醒来看到的就是实际结果，不会对着空屋子说「到了」。
    pub fn awaiting_followers(&self, actor: &str) -> bool {
        let (Some(walk), Some(a)) = (self.interactions.walk_led_by(actor), self.actors.get(actor))
        else {
            return false;
        };
        a.actions.agent_controlled
            && !a.player_controlled()
            && a.plan.is_empty()
            && a.current.action.is_none()
            && a.current.is_open_ended()
            && a.free_walk.is_none()
            && matches!(&walk.kind, InteractionKind::Walk { locale: Some(dest), .. } if *dest == a.locus.locale)
    }

    /// 同行的人到了带路人身边：在同一个地点里，或在同一空间里离他 ARRIVE_REACH 以内
    /// （带路人站在地点入口时，跟着的人停在身后几步、可能还在路上）。
    fn beside_leader(&self, member: &str, leader: &str) -> bool {
        if self.actors[member].locus.locale == self.actors[leader].locus.locale {
            return true;
        }
        let reach = crate::avatar::Reach::new(self);
        reach
            .talk_spot(member)
            .zip(reach.talk_spot(leader))
            .is_some_and(|(m, l)| {
                m.space == l.space && distance(m.position, l.position) <= ARRIVE_REACH
            })
    }

    /// 同行开始（邀请被接受，或交谈里的提议被答应）：成员已经写进聊天，路上默认安静；
    /// 跟随的村民换上「跟着某人」的活动，带路人和玩家操控的人照常自由行动。
    /// 受 Agent 控制的带路人说好了目的地就直接出发。
    pub(crate) fn begin_walk(&mut self, id: &str) {
        let now = self.minutes;
        let item = &self.interactions[id];
        let InteractionKind::Walk { leader, locale } = item.kind.clone() else {
            return;
        };
        let members = chat_of(item).members.clone();
        {
            let c = chat_of_mut(self.interactions.get_mut(id));
            c.proposal = None;
            c.passes = 0;
            c.resume_at = now + QUIET_MINUTES;
            c.turn_queue = std::iter::once(leader.clone())
                .chain(members.iter().filter(|m| **m != leader).cloned())
                .collect();
        }
        for member in &members {
            if self.walk_carries(member, &leader) {
                self.bind_follower(id, member);
            } else {
                self.unbind_walk_member(id, member);
            }
        }
        let mut state = WalkTrail::default();
        if let Some(at) = crate::avatar::Reach::new(self).talk_spot(&leader) {
            state.trail.mark(at);
        }
        self.walk_trails.0.insert(id.into(), state);
        if let Some(dest) = locale {
            self.lead_off(id, &leader, &dest);
        }
    }

    /// 受 Agent 控制的带路人说好了目的地：替他安排「前往」，跟随者一起出发。
    fn lead_off(&mut self, id: &str, leader: &str, dest: &str) {
        let Some(a) = self.actors.get(leader) else {
            return;
        };
        if a.player_controlled() || !a.actions.agent_controlled || a.locus.locale == dest {
            return;
        }
        let revision = a.actions.revision;
        let draft = ActionDraft {
            intent: IntentDraft {
                verb: crate::intent::BuiltinVerb::Goto.label().into(),
                locale: Some(dest.into()),
                target: None,
                duration_minutes: None,
                until: None,
            },
            inventory: None,
            prop_id: None,
            recipient: None,
            writing: None,
        };
        let group = format!("{id}{LEAD_SUFFIX}");
        if let Err(error) = self.run_actions_from(leader, &group, revision, &[draft], false) {
            let a = &self.actors[leader];
            let line = format!("{} 没能出发带路：{error}", a.name);
            self.log(a.event_info(), line);
        }
    }

    /// 跟随的村民：换上指向这场同行的无期活动，站在行走地图上的自由位置，由世界带着走。
    pub(crate) fn bind_follower(&mut self, id: &str, actor: &str) {
        let now = self.minutes;
        let item = &self.interactions[id];
        let leader = item.kind.walk_leader().unwrap_or_default().to_owned();
        let members = chat_of(item).members.clone();
        let verb = format!("跟着{}", self.actors.get(&leader).map_or("", |a| &a.name));
        let spot = crate::avatar::Reach::new(self).talk_spot(actor);
        let a = self.actor_mut(actor);
        a.plan.clear();
        a.free_walk = None;
        a.actions.bump_revision();
        if let Some(spot) = spot {
            a.locus = spot.locus();
        }
        let mut activity = crate::activity::Activity::waiting(actor, now, a.locus.locale.clone());
        activity.verb = verb;
        activity.interaction = Some(id.into());
        activity.participants = members;
        a.current = activity;
    }

    /// 带路人和玩家操控的同行者不占活动：原来指向这场同行或交谈的活动换成空等，旧观察作废。
    fn unbind_walk_member(&mut self, id: &str, actor: &str) {
        let now = self.minutes;
        let a = self.actor_mut(actor);
        if a.current.interaction.as_deref() == Some(id) {
            a.reset_idle(now, true);
        } else {
            a.actions.bump_revision();
        }
    }

    /// 玩家接管或交还一个同行者：接管后自己走，交还后由世界带着走。
    pub(crate) fn sync_walk_member(&mut self, actor: &str) {
        let Some(item) = self.interactions.walk_of(actor) else {
            return;
        };
        let (id, leader) = (
            item.id.clone(),
            item.kind.walk_leader().unwrap_or_default().to_owned(),
        );
        if self.walk_carries(actor, &leader) {
            self.bind_follower(&id, actor);
        } else {
            self.unbind_walk_member(&id, actor);
        }
    }

    /// 有同行进行时，世界至少每 WALK_TICK 分钟推进一次跟随者。
    pub(crate) fn walk_boundary(&self) -> f64 {
        if self.interactions.walks().next().is_some() {
            WALK_TICK
        } else {
            f64::INFINITY
        }
    }

    /// 玩家操控的人带路时放慢到 LEAD_PACE，不然跟随的村民追不上。
    pub(crate) fn player_pace(&self, actor: &str, pace: f64) -> f64 {
        if self.interactions.leads_walk(actor) {
            pace.min(LEAD_PACE)
        } else {
            pace
        }
    }

    /// 推进全部同行 minutes 分钟：记下带路人的足迹，带着跟随者走，再看有没有人跟丢、到了没有。
    pub(crate) fn advance_walks(&mut self, minutes: f64) {
        let ids: Vec<String> = self.interactions.walks().map(|i| i.id.clone()).collect();
        self.walk_trails.0.retain(|id, _| ids.contains(id));
        for id in ids {
            self.advance_walk(&id, minutes);
        }
    }

    fn advance_walk(&mut self, id: &str, minutes: f64) {
        let item = &self.interactions[id];
        let (leader, locale) = match &item.kind {
            InteractionKind::Walk { leader, locale } => (leader.clone(), locale.clone()),
            _ => return,
        };
        let leader_ok = self
            .actors
            .get(&leader)
            .is_some_and(|a| a.present() && !a.needs.incapacitated());
        if !leader_ok {
            let name = self.actor_name(&leader);
            return self.finish_walk(
                id,
                Status::Interrupted,
                format!("{name}没法再带路，同行结束"),
            );
        }
        let Some(map) = self.walk_map.clone() else {
            return self.finish_walk(id, Status::Interrupted, "这里没有行走地图，同行结束".into());
        };
        let reach = crate::avatar::Reach::new(self);
        let leader_spot = reach.talk_spot(&leader);
        drop(reach);
        let state = self.walk_trails.0.entry(id.into()).or_default();
        if let Some(at) = leader_spot.clone() {
            state.trail.mark(at);
        }
        let followers: Vec<String> = chat_of(&self.interactions[id])
            .members
            .iter()
            .filter(|m| **m != leader)
            .cloned()
            .collect();
        // 带路人已经停在目的地等着：还没走到他身边的人也算落后，等满 LOST_MINUTES 就算没跟上，
        // 不然站在二十几米外不进来的人会让他一直干等到同行超时
        let waiting = self.awaiting_followers(&leader);
        let obstacles = self.avatar_obstacles();
        for (rank, follower) in followers.iter().enumerate() {
            let able = self
                .actors
                .get(follower)
                .is_some_and(|a| a.present() && !a.needs.incapacitated());
            if !able {
                self.drop_follower(id, follower, "停下了");
                continue;
            }
            let here = crate::avatar::Reach::new(self).talk_spot(follower);
            let mut stuck = false;
            if self.walk_carries(follower, &leader) {
                if let Some(here) = &here {
                    let gap = FOLLOW_GAP + FOLLOW_SPACING * rank as f64;
                    let state = self.walk_trails.0.get_mut(id).expect("上面已建");
                    let progress = state.followers.entry(follower.clone()).or_default();
                    let behind = leader_spot
                        .as_ref()
                        .filter(|l| l.space == here.space)
                        .map_or(f64::INFINITY, |l| distance(l.position, here.position));
                    let pace = if behind > gap + CATCH_UP_BEHIND {
                        CATCH_UP_PACE
                    } else {
                        1.0
                    };
                    let step = map.follow_trail(
                        here,
                        &state.trail,
                        progress,
                        gap,
                        minutes * map.metres_per_minute * pace,
                        &obstacles,
                    );
                    stuck = step.stuck;
                    if let Some(spot) = step.moved {
                        self.place_follower(follower, spot);
                    }
                }
            }
            let here = crate::avatar::Reach::new(self).talk_spot(follower);
            let together = match (&here, &leader_spot) {
                (Some(h), Some(l)) => {
                    h.space == l.space && distance(h.position, l.position) <= LOST_DISTANCE
                }
                // 带路人走在没有几何的路段上：看不出远近，不算落后
                (_, None) => true,
                _ => false,
            } && (!waiting || self.beside_leader(follower, &leader));
            let state = self.walk_trails.0.get_mut(id).expect("上面已建");
            let apart = state.apart.entry(follower.clone()).or_default();
            *apart = if together && !stuck {
                0.
            } else {
                *apart + minutes
            };
            if *apart >= LOST_MINUTES {
                let name = self.actor_name(&leader);
                let why = if waiting { "没跟上" } else { "跟丢了" };
                self.drop_follower(id, follower, &format!("{why}{name}"));
            }
        }
        if let Some(state) = self.walk_trails.0.get_mut(id) {
            let keep = state
                .followers
                .values()
                .map(|f| f.next)
                .min()
                .unwrap_or(usize::MAX);
            state
                .trail
                .trim(keep.min(state.trail.base + state.trail.points.len()));
        }
        if self.interactions[id].status != Status::Running {
            return;
        }
        self.follow_new_destination(id, &leader);
        let locale = self.interactions[id].kind.clone().walk_locale().or(locale);
        self.check_arrival(id, &leader, locale.as_deref(), minutes);
    }

    /// 到了没有：说好的目的地，带路人和跟随者都在那里就算到；没写目的地时，带路人在一个地点
    /// 停够 SETTLE_MINUTES、跟随者也在那里才算。走满 WALK_MINUTES 还没到就先停下。
    fn check_arrival(&mut self, id: &str, leader: &str, locale: Option<&str>, minutes: f64) {
        let members: Vec<String> = chat_of(&self.interactions[id])
            .members
            .iter()
            .cloned()
            .collect();
        let here = self.actors[leader].locus.locale.clone();
        let settled_place = self.topo.place_of(&here).is_some()
            && !self.actors[leader].current.is_travel()
            && self.actors[leader].free_walk.is_none();
        let all_here = members.iter().all(|m| self.beside_leader(m, leader));
        let arrived = match locale {
            Some(dest) => here == dest && all_here && !self.actors[leader].current.is_travel(),
            None => {
                let state = self.walk_trails.0.entry(id.into()).or_default();
                if settled_place && all_here && state.settled_at.as_deref() == Some(here.as_str()) {
                    state.settled += minutes;
                } else {
                    state.settled = 0.;
                    state.settled_at = (settled_place && all_here).then(|| here.clone());
                }
                state.settled >= SETTLE_MINUTES
            }
        };
        if arrived {
            self.step_followers_into(&members, leader, &here);
            let place = self.topo.locale_name(&here);
            return self.finish_walk(id, Status::Succeeded, format!("到了{place}，同行结束"));
        }
        let started = self.interactions[id].started_at.unwrap_or(self.minutes);
        if self.minutes - started >= WALK_MINUTES {
            self.finish_walk(
                id,
                Status::Interrupted,
                format!("走了 {WALK_MINUTES:.0} 分钟还没到，先停下来"),
            );
        }
    }

    /// 到了以后，还站在地点外面一两步的跟随村民往前挪进去，醒来时就在那个地点里。
    fn step_followers_into(&mut self, members: &[String], leader: &str, place: &str) {
        let Some(map) = self.walk_map.clone() else {
            return;
        };
        let obstacles = self.avatar_obstacles();
        let toward = crate::avatar::Reach::new(self).talk_spot(leader);
        for m in members {
            if self.actors[m].locus.locale == place || !self.walk_carries(m, leader) {
                continue;
            }
            let (Some(from), Some(toward)) =
                (crate::avatar::Reach::new(self).talk_spot(m), &toward)
            else {
                continue;
            };
            if let Some(spot) = map.step_into(place, &from, toward.position, &obstacles) {
                self.place_follower(m, spot);
            }
        }
    }

    /// 受 Agent 控制的带路人改了去处（到了一处又往别处走）：同行的目的地跟着改，到那儿才算到。
    fn follow_new_destination(&mut self, id: &str, leader: &str) {
        let crate::world::ActKind::Travel { journey, .. } = &self.actors[leader].current.kind
        else {
            return;
        };
        let dest = journey.dest_locale.clone();
        if self.topo.place_of(&dest).is_none() || self.actors[leader].player_controlled() {
            return;
        }
        if let InteractionKind::Walk { locale, .. } = &mut self.interactions.get_mut(id).kind {
            if locale.as_deref() != Some(dest.as_str()) {
                *locale = Some(dest);
            }
        }
    }

    /// 跟随者挪到新位置：处所跟着位置走。
    fn place_follower(&mut self, actor: &str, spot: Spot) {
        let a = self.actor_mut(actor);
        a.current.locale = spot.locale.clone();
        a.locus = spot.locus();
    }

    /// 一个跟随者退出同行（跟丢、倒下、离开小镇）；只剩带路人时同行随之结束。
    fn drop_follower(&mut self, id: &str, actor: &str, why: &str) {
        let now = self.minutes;
        let name = self.actor_name(actor);
        let reason = format!("{name}{why}");
        if let Err(e) = self.interactions.leave_chat(
            &mut self.actors,
            now,
            actor,
            id,
            super::LeaveKind::Forced,
            &reason,
        ) {
            self.log(
                protocol::EventInfo::default(),
                format!("{actor} 退出同行 {id} 失败：{e}"),
            );
        }
        if let Some(state) = self.walk_trails.0.get_mut(id) {
            state.followers.remove(actor);
            state.apart.remove(actor);
        }
    }

    /// 结束一场同行：聊天随之结束，跟随的村民回到空等；状态按结束原因写。
    pub(crate) fn finish_walk(&mut self, id: &str, status: Status, reason: String) {
        let now = self.minutes;
        if self.interactions[id].status != Status::Running {
            return;
        }
        self.interactions
            .end_chat(&mut self.actors, now, id, &reason);
        let item = self.interactions.get_mut(id);
        item.status = status;
        self.walk_trails.0.remove(id);
    }

    /// 跟上一场进行中的同行（路过时加入，或带路人又邀了一个人）：成为跟随者，手头没做完的事按中断结算。
    /// 村民要和带路人在同一处所，玩家要走到带路人身边。
    pub(crate) fn join_walk(
        &mut self,
        actor: &str,
        id: &str,
        message: &str,
    ) -> crate::error::Result<Interaction> {
        use crate::error::KernelError;
        super::check_message(message)?;
        let item = self
            .interactions
            .get(id)
            .filter(|i| i.status == Status::Running)
            .ok_or_else(|| KernelError::interaction("同行已经结束"))?;
        let leader = item.kind.walk_leader().unwrap_or_default().to_owned();
        ensure!(
            !chat_of(item).members.contains(actor),
            KernelError::interaction("已经在这场同行里")
        );
        ensure!(
            self.talk_available(actor),
            KernelError::interaction("先结束手头的交谈或同行，再跟上")
        );
        let near = if self.actors[actor].player_controlled() {
            crate::avatar::Reach::new(self).pair(actor, &leader).is_ok()
        } else {
            self.actors[actor].locus.locale == self.actors[&leader].locus.locale
        };
        ensure!(near, KernelError::interaction("要先走到带路的人身边"));
        let now = self.minutes;
        self.actor_mut(actor)
            .interrupt_actions(now, "跟上同行，结束原活动安排");
        {
            let c = chat_of_mut(self.interactions.get_mut(id));
            c.members.insert(actor.into());
            c.ever_members.insert(actor.into());
            c.turn_queue.push(actor.into());
        }
        let audience = chat_of(&self.interactions[id]).members.clone();
        let mut lines = vec![(protocol::ChatEntryKind::Joined, "加入同行")];
        if !message.trim().is_empty() {
            lines.push((protocol::ChatEntryKind::Speech, message));
        }
        for (kind, text) in lines {
            let line = super::ChatLine {
                speaker: actor,
                kind,
                text,
                audience: audience.clone(),
            };
            self.interactions
                .chat_event(&mut self.actors, now, id, line);
        }
        if self.walk_carries(actor, &leader) {
            self.bind_follower(id, actor);
        } else {
            self.unbind_walk_member(id, actor);
        }
        self.interactions
            .sync_chat_activity(&mut self.actors, now, id);
        Ok(self.interactions[id].clone())
    }

    /// 带路人又邀了一个人同行：对方答应后跟上他正在带的那一场，这份邀请就此办完。
    pub(crate) fn merge_walk_offer(&mut self, offer: &str, walk: &str) {
        let now = self.minutes;
        let item = self.interactions[offer].clone();
        let leader = self.actor_name(&item.initiator);
        self.interactions.end_chat(
            &mut self.actors,
            now,
            offer,
            &format!("跟上了{leader}带的同行"),
        );
        if let Err(error) = self.join_walk(&item.partner, walk, "") {
            let line = format!("{} 没能跟上同行：{error}", self.actor_name(&item.partner));
            self.log(protocol::EventInfo::default(), line);
        }
    }

    /// 某人退出或离场时，他带的同行跟着结束（化身离开小镇、带路人倒下）。
    pub(crate) fn end_walks_of(&mut self, actor: &str, reason: &str) {
        let Some(item) = self.interactions.walk_of(actor) else {
            return;
        };
        let id = item.id.clone();
        if item.kind.walk_leader() == Some(actor) {
            let name = self.actor_name(actor);
            self.finish_walk(
                &id,
                Status::Interrupted,
                format!("{name}{reason}，同行结束"),
            );
        } else {
            self.drop_follower(&id, actor, reason);
        }
    }

    fn actor_name(&self, id: &str) -> String {
        self.actors
            .get(id)
            .map_or_else(|| id.to_owned(), |a| a.name.clone())
    }
}

/// 同行的时长与目的地规则：只给检查互动内容用。
pub(crate) fn check_walk(
    w: &World,
    actor: &str,
    partner: &str,
    leader: &str,
    locale: Option<&str>,
) -> crate::error::Result<f64> {
    use crate::error::KernelError;
    ensure!(
        w.walk_map.is_some(),
        KernelError::interaction("这张地图不支持同行")
    );
    ensure!(
        leader == actor || leader == partner,
        KernelError::interaction("带路的人须是同行的一方")
    );
    if let Some(dest) = locale {
        ensure!(
            w.topo.place_of(dest).is_some(),
            KernelError::interaction(format!("目的地 {dest} 不是已知地点"))
        );
        // 两人都已在那儿：同行一开始就算到了，交谈跟着结束，什么也没走
        let there = |id: &str| w.actors.get(id).is_some_and(|a| a.locus.locale == dest);
        ensure!(
            !(there(actor) && there(partner)),
            KernelError::interaction(format!(
                "两人已经都在{}，同行要选别的地点",
                w.topo.locale_name(dest)
            ))
        );
    }
    for id in [actor, partner] {
        // 带路人正在带别人：同一个目的地（或不写）就并进那一场，多人同行
        let joining = |i: &Interaction| {
            id == leader
                && i.kind.walk_leader() == Some(leader)
                && (locale.is_none()
                    || i.kind
                        == (InteractionKind::Walk {
                            leader: leader.into(),
                            locale: locale.map(str::to_owned),
                        }))
        };
        ensure!(
            w.interactions.walk_of(id).is_none_or(joining),
            KernelError::interaction("有人已经在同行中，先结束原来的同行")
        );
    }
    Ok(WALK_MINUTES)
}
