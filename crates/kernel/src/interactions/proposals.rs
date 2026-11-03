//! 交谈里的提议：一方提议一起走（同行）或约个时间地点（约定），被问的人答应或不答应，提议人也可以撤回。
//! 同行：两人交谈时答应了，这场交谈就变成路上的同行，说过的话都还在；人多时两人告辞，另开一场同行。
//! 约定：答应后另记一份约定，交谈照常继续。
use super::chat::{chat_of, chat_of_mut};
use super::{check_message, ChatLine, Interactions, LeaveKind};
use crate::error::{KernelError, Result};
use crate::World;
use protocol::{
    ChatEntryKind, ChatProposal, Interaction, InteractionKind, InteractionStatus as Status,
};

impl World {
    pub(crate) fn propose(
        &mut self,
        actor: &str,
        chat: &str,
        kind: &InteractionKind,
        message: &str,
        to: Option<&str>,
    ) -> Result<Interaction> {
        check_message(message)?;
        let item = self.running_talk(chat)?;
        let c = chat_of(item);
        ensure!(
            c.members.contains(actor),
            KernelError::interaction("本人不在这场交谈中")
        );
        let to = match to {
            Some(to) => to.to_owned(),
            None => {
                let others: Vec<_> = c.members.iter().filter(|m| *m != actor).collect();
                ensure!(
                    others.len() == 1,
                    KernelError::interaction("人多时要用 to 指定问谁")
                );
                others[0].clone()
            }
        };
        ensure!(
            to != actor && c.members.contains(&to),
            KernelError::interaction("提议要问交谈里的另一个人")
        );
        ensure!(
            c.proposal.as_ref().is_none_or(|p| p.by == actor),
            KernelError::interaction("对方的提议还在等你回答，先答应或拒绝")
        );
        match kind {
            InteractionKind::Walk { leader, locale } => {
                super::walk::check_walk(self, actor, &to, leader, locale.as_deref())?;
            }
            InteractionKind::Appointment { locale, at } => {
                super::appointments::check_appointment(self, locale, *at)?;
            }
            _ => {
                return Err(KernelError::interaction(
                    "交谈里只能提议一起走（walk）或约定（appointment）",
                ))
            }
        }
        let now = self.minutes;
        let members = c.members.clone();
        let turn = self.interactions.chat_turn(&self.actors[actor], now);
        if !message.trim().is_empty() {
            self.line(chat, actor, ChatEntryKind::Speech, message);
        }
        let text = self.describe_proposal(kind);
        self.line(chat, actor, ChatEntryKind::Proposed, &text);
        let c = chat_of_mut(self.interactions.get_mut(chat));
        c.proposal = Some(ChatProposal {
            by: actor.into(),
            to: to.clone(),
            interaction: kind.clone(),
            at: now,
        });
        if turn {
            self.interactions
                .advance_chat_turn(&mut self.actors, now, chat, Some(&to), false);
        } else {
            // 不在自己的轮次：被问的人排到最前，马上能回答；他在途的旧回复作废，按新内容重想。
            c.turn_queue.retain(|m| *m != to);
            c.turn_queue.insert(0, to.clone());
            c.resume_at = now;
            c.passes = 0;
            for m in &members {
                self.actor_mut(m).actions.bump_revision();
            }
        }
        Ok(self.interactions[chat].clone())
    }

    pub(crate) fn accept_proposal(
        &mut self,
        actor: &str,
        chat: &str,
        message: &str,
        locale: Option<&str>,
    ) -> Result<Interaction> {
        check_message(message)?;
        let item = self.running_talk(chat)?;
        let c = chat_of(item);
        let proposal = c
            .proposal
            .clone()
            .ok_or_else(|| KernelError::interaction("没有等你回答的提议"))?;
        ensure!(
            proposal.to == actor,
            KernelError::interaction("只有被问的人可以答应，不能替别人答应")
        );
        let mut kind = proposal.interaction.clone();
        if let Some(dest) = locale {
            match &mut kind {
                InteractionKind::Walk { leader, locale } if leader == actor && locale.is_none() => {
                    *locale = Some(dest.into())
                }
                _ => {
                    return Err(KernelError::interaction(
                        "只有带路的人能补目的地，而且提议里还没写目的地",
                    ))
                }
            }
        }
        if matches!(kind, InteractionKind::Appointment { .. }) {
            return self.accept_appointment(chat, actor, &proposal.by, kind, message);
        }
        let InteractionKind::Walk { leader, locale } = &kind else {
            return Err(KernelError::interaction("这项提议不能在交谈里答应"));
        };
        super::walk::check_walk(self, &proposal.by, actor, leader, locale.as_deref())?;
        for id in [&proposal.by, &actor.to_owned()] {
            let a = &self.actors[id];
            ensure!(
                a.present() && a.controllable() && !a.needs.incapacitated(),
                KernelError::interaction("双方须在场、能行动")
            );
        }
        let pair = c.members.len() == 2;
        let now = self.minutes;
        if !message.trim().is_empty() {
            self.line(chat, actor, ChatEntryKind::Speech, message);
        }
        self.line(chat, actor, ChatEntryKind::Accepted, "答应了");
        if pair {
            // 两人交谈：就地变成同行，说过的话留在同一场里。
            let item = self.interactions.get_mut(chat);
            item.kind = kind;
            item.duration_minutes = super::walk::WALK_MINUTES;
            chat_of_mut(item).proposal = None;
            self.begin_walk(chat);
            return Ok(self.interactions[chat].clone());
        }
        // 人多：两人从交谈里告辞，另开一场同行。
        chat_of_mut(self.interactions.get_mut(chat)).proposal = None;
        for id in [proposal.by.as_str(), actor] {
            self.interactions.leave_chat(
                &mut self.actors,
                now,
                id,
                chat,
                LeaveKind::Voluntary,
                "一起走了",
            )?;
        }
        let id = (1..)
            .map(|n| format!("{chat}-walk{n}"))
            .find(|id| self.interactions.get(id).is_none())
            .expect("总有没用过的编号");
        let mut walk = Interactions::new_offer(
            &id,
            &self.actors[&proposal.by],
            actor,
            kind,
            "",
            super::walk::WALK_MINUTES,
            now,
        );
        walk.reply = Some(message.into());
        walk.accepted = Some(true);
        walk.status = Status::Running;
        walk.started_at = Some(now);
        self.interactions.items.insert(id.clone(), walk);
        self.interactions.start_chat(&mut self.actors, now, &id);
        self.begin_walk(&id);
        Ok(self.interactions[&id].clone())
    }

    pub(crate) fn decline_proposal(
        &mut self,
        actor: &str,
        chat: &str,
        message: &str,
    ) -> Result<Interaction> {
        check_message(message)?;
        let item = self.running_talk(chat)?;
        let proposal = chat_of(item)
            .proposal
            .clone()
            .ok_or_else(|| KernelError::interaction("没有等你回答的提议"))?;
        ensure!(
            proposal.to == actor || proposal.by == actor,
            KernelError::interaction("这项提议与你无关")
        );
        let now = self.minutes;
        let turn = self.interactions.chat_turn(&self.actors[actor], now);
        if !message.trim().is_empty() {
            self.line(chat, actor, ChatEntryKind::Speech, message);
        }
        let text = if proposal.by == actor {
            "撤回了提议"
        } else {
            "没有答应"
        };
        self.line(chat, actor, ChatEntryKind::Declined, text);
        chat_of_mut(self.interactions.get_mut(chat)).proposal = None;
        if turn {
            self.interactions
                .advance_chat_turn(&mut self.actors, now, chat, None, false);
        }
        Ok(self.interactions[chat].clone())
    }

    /// 进行中的交谈（不是同行，也不是别的互动）。
    fn running_talk(&self, chat: &str) -> Result<&Interaction> {
        let item = self
            .interactions
            .get(chat)
            .ok_or_else(|| KernelError::interaction("交谈不存在"))?;
        ensure!(
            item.status == Status::Running && item.kind == InteractionKind::Talk,
            KernelError::interaction("只能在进行中的交谈里提议和回答")
        );
        Ok(item)
    }

    /// 给交谈里的全部成员记一条。
    fn line(&mut self, chat: &str, speaker: &str, kind: ChatEntryKind, text: &str) {
        let now = self.minutes;
        let audience = chat_of(&self.interactions[chat]).members.clone();
        self.interactions.chat_event(
            &mut self.actors,
            now,
            chat,
            ChatLine {
                speaker,
                kind,
                text,
                audience,
            },
        );
    }

    /// 答应交谈里的约定：另记一份进行中的约定，交谈照常继续。
    fn accept_appointment(
        &mut self,
        chat: &str,
        actor: &str,
        by: &str,
        kind: InteractionKind,
        message: &str,
    ) -> Result<Interaction> {
        let now = self.minutes;
        let InteractionKind::Appointment { locale, at } = kind.clone() else {
            unreachable!("调用方已确认是约定");
        };
        let duration = super::appointments::check_appointment(self, &locale, at)?;
        if !message.trim().is_empty() {
            self.line(chat, actor, ChatEntryKind::Speech, message);
        }
        self.line(chat, actor, ChatEntryKind::Accepted, "答应了");
        chat_of_mut(self.interactions.get_mut(chat)).proposal = None;
        let id = (1..)
            .map(|n| format!("{chat}-appt{n}"))
            .find(|id| self.interactions.get(id).is_none())
            .expect("总有没用过的编号");
        let mut item =
            Interactions::new_offer(&id, &self.actors[by], actor, kind, "", duration, now);
        item.expires_at = item.expires_at.min(at);
        item.reply = Some(message.into());
        item.accepted = Some(true);
        item.status = Status::Running;
        item.started_at = Some(now);
        self.interactions.items.insert(id.clone(), item.clone());
        let text = format!(
            "约好了：{}",
            super::appointments::describe(self, &locale, at)
        );
        self.interactions.fact(&mut self.actors, now, &item, &text);
        Ok(self.interactions[chat].clone())
    }

    /// 提议的说法：「一起走：旅人带路，去陈默家」「约定：D13 14:00 在小广场见」。
    pub(crate) fn describe_proposal(&self, kind: &InteractionKind) -> String {
        if let InteractionKind::Appointment { locale, at } = kind {
            return format!("约定：{}", super::appointments::describe(self, locale, *at));
        }
        let InteractionKind::Walk { leader, locale } = kind else {
            return kind.label().into();
        };
        let name = self.actors.get(leader).map_or(leader.as_str(), |a| &a.name);
        match locale {
            Some(dest) => format!("一起走：{name}带路，去{}", self.topo.locale_name(dest)),
            None => format!("一起走：{name}带路"),
        }
    }
}
