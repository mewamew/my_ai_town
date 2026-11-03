//! 持续聊天：活动占位、独立发言轮次和动态成员，不以计时器代替对话。
use super::{check_message, Interactions};
use crate::actor::{Actor, Actors};
use crate::error::{KernelError, Result};
use protocol::{
    ChatEntry, ChatEntryKind, ChatState, FactKind, Interaction, InteractionCommand as Command,
    InteractionStatus as Status,
};
use std::collections::BTreeSet;

/// 交谈互动的聊天状态。交谈邀请创建时就带着聊天状态，只对已确认是交谈的互动调用。
pub(super) fn chat_of(item: &Interaction) -> &ChatState {
    item.chat.as_ref().expect("交谈互动带聊天状态")
}

pub(super) fn chat_of_mut(item: &mut Interaction) -> &mut ChatState {
    item.chat.as_mut().expect("交谈互动带聊天状态")
}

/// 开始新的一轮：每位成员各有一次机会，刚拿过发言权的人排在最后。成员集合按编号排序，
/// 照抄的话，编号靠前的人说完一轮的最后一句会立刻又轮到自己，对方插不上话——
/// 玩家的编号排在村民前面，被村民搭话时，说完第一句就会又显示「轮到你了」。
fn new_round(c: &mut ChatState, last: Option<&str>) {
    let (rest, last): (Vec<_>, Vec<_>) = c
        .members
        .iter()
        .cloned()
        .partition(|m| Some(m.as_str()) != last);
    c.turn_queue = rest.into_iter().chain(last).collect();
}

/// 聊天记录里的一条：谁、哪一类、说了什么、谁听见。
pub(crate) struct ChatLine<'a> {
    pub speaker: &'a str,
    pub kind: ChatEntryKind,
    pub text: &'a str,
    pub audience: BTreeSet<String>,
}

/// 离开聊天的方式。主动离开（告辞、取消）时人数不足交谈仍算完成；
/// 被迫离开（活动失败、外部中断）时人数不足算交谈中断。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum LeaveKind {
    Voluntary,
    Forced,
}

impl Interactions {
    pub(crate) fn start_chat(&mut self, actors: &mut Actors, now: f64, id: &str) {
        let i = self.get_mut(id);
        let joined = if i.kind.walk_leader().is_some() {
            "加入同行"
        } else {
            "加入交谈"
        };
        let (initiator, actor) = (i.initiator.clone(), i.partner.clone());
        let c = chat_of_mut(i);
        c.members = [initiator.clone(), actor.clone()].into();
        c.ever_members = c.members.clone();
        c.turn_queue = vec![initiator, actor.clone()];
        let audience = c.members.clone();
        self.chat_event(
            actors,
            now,
            id,
            ChatLine {
                speaker: &actor,
                kind: ChatEntryKind::Joined,
                text: joined,
                audience,
            },
        );
        self.sync_chat_activity(actors, now, id);
    }

    /// 成员的活动与聊天状态对齐：无期占位、同一参与者集合、同一开始时刻。
    /// 同行里只有跟随的村民占着活动（见 walk.rs），他们只更新参与者集合，旧观察作废。
    pub(super) fn sync_chat_activity(&mut self, actors: &mut Actors, now: f64, id: &str) {
        let i = &self.items[id];
        let c = chat_of(i);
        let (members, locale, verb, started_at) = (
            c.members.clone(),
            i.locale.clone(),
            i.kind.label(),
            i.started_at.expect("进行中的聊天有开始时刻"),
        );
        let walk = i.kind.walk_leader().is_some();
        for actor in &members {
            let a = actors.get_mut(actor).expect("聊天成员存在");
            if walk {
                a.actions.bump_revision();
                if a.current.interaction.as_deref() == Some(id) {
                    a.current.participants = members.clone();
                }
                continue;
            }
            a.reset_idle(now, true);
            a.current.locale = locale.clone();
            a.current.verb = verb.into();
            a.current.interaction = Some(id.into());
            a.current.participants = members.clone();
            a.current.started_at = started_at;
        }
    }

    /// 本人正在参与的、进行中的聊天。同行的带路人和玩家操控的同行者不占活动，按成员查。
    pub(crate) fn active_chat(&self, actor: &Actor) -> Option<&Interaction> {
        match &actor.current.interaction {
            Some(id) => self
                .items
                .get(id)
                .filter(|i| i.status == Status::Running && i.chat.is_some()),
            None => self.walk_of(&actor.id),
        }
    }

    pub(crate) fn chat_turn(&self, actor: &Actor, now: f64) -> bool {
        self.active_chat(actor).is_some_and(|i| {
            let c = chat_of(i);
            c.resume_at <= now && c.turn_queue.first().is_some_and(|id| id == &actor.id)
        })
    }

    pub(crate) fn chat_command(
        &mut self,
        actors: &mut Actors,
        now: f64,
        actor: &str,
        command: &Command,
    ) -> Result<Interaction> {
        let id = match command {
            Command::Join { interaction_id, .. }
            | Command::Say { interaction_id, .. }
            | Command::Listen { interaction_id }
            | Command::Leave { interaction_id, .. } => interaction_id,
            _ => return Err(KernelError::interaction("不是聊天命令")),
        };
        let item = self
            .items
            .get(id)
            .ok_or_else(|| KernelError::interaction("聊天不存在"))?;
        item.chat
            .as_ref()
            .ok_or_else(|| KernelError::interaction("这项活动不支持持续聊天"))?;
        ensure!(
            item.status == Status::Running,
            KernelError::interaction("聊天已经结束")
        );
        match command {
            Command::Join { message, .. } => self.join_chat(actors, now, actor, id, message)?,
            Command::Say { message, to, .. } => {
                self.say(actors, now, actor, id, message, to.as_deref())?
            }
            Command::Listen { .. } => {
                ensure!(
                    self.chat_turn(&actors[actor], now),
                    KernelError::interaction("尚未轮到本人回应")
                );
                self.advance_chat_turn(actors, now, id, None, true);
            }
            Command::Leave { message, .. } => {
                check_message(message)?;
                let members = self.chat_members(id);
                ensure!(
                    members.contains(actor),
                    KernelError::interaction("本人不在这场聊天中")
                );
                if !message.trim().is_empty() {
                    self.chat_event(
                        actors,
                        now,
                        id,
                        ChatLine {
                            speaker: actor,
                            kind: ChatEntryKind::Speech,
                            text: message,
                            audience: members,
                        },
                    );
                }
                self.leave_chat(actors, now, actor, id, LeaveKind::Voluntary, "主动告辞")?;
            }
            _ => unreachable!("非聊天命令已在上面拒绝"),
        }
        Ok(self.items[id].clone())
    }

    /// 全员暂听时请求发言：排到轮次队首，立刻恢复轮转。返回聊天成员，他们的旧观察都要作废。
    pub(crate) fn request_turn(
        &mut self,
        id: &str,
        actor: &str,
        now: f64,
    ) -> Result<BTreeSet<String>> {
        let i = self
            .items
            .get_mut(id)
            .ok_or_else(|| KernelError::interaction("聊天不存在"))?;
        let running = i.status == Status::Running;
        let c = i
            .chat
            .as_mut()
            .ok_or_else(|| KernelError::interaction("不是聊天"))?;
        ensure!(
            running && c.members.contains(actor) && c.resume_at > now,
            KernelError::interaction("只能在全员暂听时请求发言")
        );
        c.turn_queue.retain(|id| id != actor);
        c.turn_queue.insert(0, actor.into());
        c.resume_at = now;
        c.passes = 0;
        Ok(c.members.clone())
    }

    fn chat_members(&self, id: &str) -> BTreeSet<String> {
        chat_of(&self.items[id]).members.clone()
    }

    fn join_chat(
        &mut self,
        actors: &mut Actors,
        now: f64,
        actor: &str,
        id: &str,
        message: &str,
    ) -> Result<()> {
        check_message(message)?;
        let item = &self.items[id];
        let members = self.chat_members(id);
        ensure!(
            !members.contains(actor),
            KernelError::interaction("已经在这场聊天中")
        );
        ensure!(
            actors[actor].interaction_available() && actors[actor].locus.locale == item.locale,
            KernelError::interaction("先结束当前活动并到聊天地点，再加入")
        );
        ensure!(
            item.kind.walk_leader().is_none() && self.walk_of(actor).is_none(),
            KernelError::interaction("同行路上不能加入别的交谈，同行也不能这样加入")
        );
        let c = chat_of_mut(self.get_mut(id));
        c.members.insert(actor.into());
        c.ever_members.insert(actor.into());
        c.turn_queue.push(actor.into());
        c.passes = 0;
        c.resume_at = now;
        let audience = c.members.clone();
        self.chat_event(
            actors,
            now,
            id,
            ChatLine {
                speaker: actor,
                kind: ChatEntryKind::Joined,
                text: "加入交谈",
                audience: audience.clone(),
            },
        );
        if !message.trim().is_empty() {
            self.chat_event(
                actors,
                now,
                id,
                ChatLine {
                    speaker: actor,
                    kind: ChatEntryKind::Speech,
                    text: message,
                    audience,
                },
            );
        }
        self.sync_chat_activity(actors, now, id);
        Ok(())
    }

    fn say(
        &mut self,
        actors: &mut Actors,
        now: f64,
        actor: &str,
        id: &str,
        message: &str,
        to: Option<&str>,
    ) -> Result<()> {
        check_message(message)?;
        ensure!(
            !message.trim().is_empty(),
            KernelError::interaction("发言不能为空；只想听请使用 listen")
        );
        ensure!(
            self.chat_turn(&actors[actor], now),
            KernelError::interaction("尚未轮到本人发言，请等待")
        );
        let members = self.chat_members(id);
        ensure!(
            !to.is_some_and(|v| v == actor || !members.contains(v)),
            KernelError::interaction("回应对象必须是另一名在场参与者")
        );
        self.chat_event(
            actors,
            now,
            id,
            ChatLine {
                speaker: actor,
                kind: ChatEntryKind::Speech,
                text: message,
                audience: members,
            },
        );
        self.advance_chat_turn(actors, now, id, to, false);
        Ok(())
    }

    pub(super) fn advance_chat_turn(
        &mut self,
        actors: &mut Actors,
        now: f64,
        id: &str,
        to: Option<&str>,
        pass: bool,
    ) {
        let walk = self.items[id].kind.walk_leader().is_some();
        let c = chat_of_mut(self.get_mut(id));
        let done = c.turn_queue.remove(0);
        if c.turn_queue.is_empty() {
            new_round(c, Some(&done));
        }
        // 一轮内尚未回应的被提问者优先，不剥夺其他人的本轮机会。
        if let Some(index) = to.and_then(|to| c.turn_queue.iter().position(|a| a == to)) {
            let next = c.turn_queue.remove(index);
            c.turn_queue.insert(0, next);
        }
        c.passes = if pass { c.passes + 1 } else { 0 };
        if c.passes >= c.members.len() {
            // 大家都在听：交谈隔一分钟再轮；同行路上就安静下来，有人开口再说。
            c.resume_at = now
                + if walk {
                    super::walk::QUIET_MINUTES
                } else {
                    1.0
                };
            c.passes = 0;
        }
        self.sync_chat_activity(actors, now, id);
    }

    pub(crate) fn leave_chat(
        &mut self,
        actors: &mut Actors,
        now: f64,
        actor: &str,
        id: &str,
        kind: LeaveKind,
        reason: &str,
    ) -> Result<()> {
        let c = self.items[id]
            .chat
            .as_ref()
            .ok_or_else(|| KernelError::interaction("不是持续聊天"))?;
        ensure!(
            c.members.contains(actor),
            KernelError::interaction("本人不在这场聊天中")
        );
        let audience = c.members.clone();
        self.chat_event(
            actors,
            now,
            id,
            ChatLine {
                speaker: actor,
                kind: ChatEntryKind::Left,
                text: reason,
                audience,
            },
        );
        let c = chat_of_mut(self.get_mut(id));
        c.members.remove(actor);
        c.turn_queue.retain(|v| v != actor);
        c.passes = 0;
        if c.proposal
            .as_ref()
            .is_some_and(|p| p.by == actor || p.to == actor)
        {
            c.proposal = None;
        }
        if c.turn_queue.is_empty() {
            // 走的人是这一轮最后一个：其他人这一轮都轮过了，最后开口的人排到新一轮末尾。
            let last = c
                .entries
                .iter()
                .rev()
                .find(|e| e.kind == ChatEntryKind::Speech && c.members.contains(&e.actor))
                .map(|e| e.actor.clone());
            new_round(c, last.as_deref());
        }
        let remaining = c.members.len();
        release(actors, now, actor, id);
        let leader = self.items[id].kind.walk_leader().map(str::to_owned);
        let leader_left = leader.as_deref() == Some(actor);
        if remaining >= 2 && !leader_left {
            self.sync_chat_activity(actors, now, id);
            return Ok(());
        }
        let who = actors.get(actor).map_or(actor, |a| a.name.as_str());
        let Some(leader) = leader else {
            self.end_chat(actors, now, id, &format!("{who}走开了，交谈结束"));
            if kind == LeaveKind::Forced {
                let i = self.get_mut(id);
                i.status = Status::Interrupted;
                i.reason = Some(reason.into());
            }
            return Ok(());
        };
        // 同行：带路人不走了，或最后一个跟随的人退出。还在一起（同一处所）就算好好结束了。
        let together = chat_of(&self.items[id])
            .members
            .iter()
            .map(String::as_str)
            .chain([actor])
            .all(|m| actors[m].locus.locale == actors[&leader].locus.locale);
        let text = match (kind, leader_left) {
            (LeaveKind::Forced, _) => format!("{reason}，同行结束"),
            (LeaveKind::Voluntary, true) => format!("{who}不带路了，同行结束"),
            (LeaveKind::Voluntary, false) => format!("{who}不跟了，同行结束"),
        };
        self.end_chat(actors, now, id, &text);
        let i = self.get_mut(id);
        i.status = match kind {
            LeaveKind::Forced => Status::Interrupted,
            LeaveKind::Voluntary if together => Status::Succeeded,
            LeaveKind::Voluntary => Status::Cancelled,
        };
        Ok(())
    }

    pub(crate) fn end_chat(&mut self, actors: &mut Actors, now: f64, id: &str, reason: &str) {
        let i = self.get_mut(id);
        i.status = Status::Succeeded;
        i.ended_at = Some(now);
        i.reason = Some(reason.into());
        i.changes.push(reason.into());
        let c = chat_of_mut(i);
        let members = std::mem::take(&mut c.members);
        c.turn_queue.clear();
        c.proposal = None;
        for actor in &members {
            release(actors, now, actor, id);
        }
        if let Some(actor) = members.first() {
            self.chat_event(
                actors,
                now,
                id,
                ChatLine {
                    speaker: actor,
                    kind: ChatEntryKind::Ended,
                    text: reason,
                    audience: members.clone(),
                },
            );
        }
    }

    pub(crate) fn chat_event(&mut self, actors: &mut Actors, now: f64, id: &str, line: ChatLine) {
        let ChatLine {
            speaker: actor,
            kind,
            text,
            audience,
        } = line;
        let name = actors[actor].name.clone();
        let i = self.get_mut(id);
        let locale = i.locale.clone();
        let c = chat_of_mut(i);
        let seq = c.entries.len() as u64 + 1;
        c.entries.push(ChatEntry {
            seq,
            at: now,
            actor: actor.into(),
            name: name.clone(),
            kind,
            text: text.into(),
            audience: audience.clone(),
        });
        if kind == ChatEntryKind::Speech {
            self.note_speech(
                actor,
                super::SpeechRef {
                    at: now,
                    chat: id.into(),
                    seq,
                },
            );
        }
        let (fact_kind, line) = if kind == ChatEntryKind::Speech {
            (FactKind::Speech, format!("{name} 说：{text}"))
        } else {
            (FactKind::Interaction, format!("{name}：{text}"))
        };
        for reader in &audience {
            let event = actors.get_mut(reader).expect("听者存在").journal.fact(
                now,
                fact_kind,
                line.clone(),
                vec![
                    actor.into(),
                    id.into(),
                    locale.clone(),
                    format!("chat:{id}:{seq}"),
                ],
                None,
                None,
            );
            self.get_mut(id)
                .event_ids
                .entry(reader.clone())
                .or_default()
                .push(event);
        }
    }
}

/// 离开或结束聊天时放开一个人：活动指向这场聊天的回到空等；同行的带路人和玩家操控的同行者
/// 没占活动，正在做的事（比如带路的「前往」）照旧，只让旧观察作废。
fn release(actors: &mut Actors, now: f64, actor: &str, id: &str) {
    let a = actors.get_mut(actor).expect("聊天成员存在");
    if a.current.interaction.as_deref() == Some(id) {
        a.reset_idle(now, true);
    } else {
        a.actions.bump_revision();
    }
}
