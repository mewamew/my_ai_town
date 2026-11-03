//! 聊天的只读投影：Agent 观察、玩家历史与名册里的在聊状态。
use super::Interactions;
use crate::actor::{Actor, Actors};
use protocol::{
    ChatObservation, ChatPresence, ChatSummary, Interaction, InteractionObservation,
    InteractionStatus as Status, NearbyChat, SpeechView,
};

/// Agent 一次最多看到最近多少条听见的台词。
const OBSERVED_ENTRIES: usize = 24;
/// 玩家历史每页的聊天数与台词数。
const CHATS_PER_PAGE: usize = 20;
const ENTRIES_PER_PAGE: usize = 50;

impl Interactions {
    /// 参与者对一项互动的观察。聊天只给本人实际收到的最近台词，不能从互动对象读到加入前
    /// 或离开后的内容；其他互动给完整记录。
    pub fn observation(actor: &str, item: &Interaction) -> InteractionObservation {
        let Some(c) = &item.chat else {
            return InteractionObservation::Pair(item.clone());
        };
        let mut entries: Vec<_> = c
            .entries
            .iter()
            .filter(|e| e.audience.contains(actor))
            .rev()
            .take(OBSERVED_ENTRIES)
            .cloned()
            .collect();
        entries.reverse();
        InteractionObservation::Chat(ChatObservation {
            entries,
            id: item.id.clone(),
            initiator: item.initiator.clone(),
            kind: item.kind.clone(),
            locale: item.locale.clone(),
            members: c.members.clone(),
            partner: item.partner.clone(),
            proposal: c.proposal.clone(),
            reason: item.reason.clone(),
            status: item.status,
            turn: c.turn_queue.first().cloned(),
        })
    }

    /// 本人所在处所里进行中的聊天。
    pub(crate) fn nearby_chats(&self, actor: &Actor) -> Vec<NearbyChat> {
        self.running_chats()
            .into_iter()
            .filter(|c| c.locale == actor.locus.locale)
            .collect()
    }

    /// 正在进行的交谈，不论在哪。同行不算：路上的同行不能这样加入。
    pub(crate) fn running_chats(&self) -> Vec<NearbyChat> {
        self.items
            .values()
            .filter(|i| i.status == Status::Running && i.kind.walk_leader().is_none())
            .filter_map(|i| {
                Some(NearbyChat {
                    id: i.id.clone(),
                    locale: i.locale.clone(),
                    members: i.chat.as_ref()?.members.clone(),
                })
            })
            .collect()
    }

    /// 名册上的「在聊」：同行路上安静着（没人开口）时不算，免得画成停下来交谈的样子。
    pub(crate) fn chat_presence(
        &self,
        actors: &Actors,
        actor: &Actor,
        now: f64,
    ) -> Option<ChatPresence> {
        let i = self.active_chat(actor)?;
        let c = i.chat.as_ref()?;
        if i.kind.walk_leader().is_some() && c.resume_at > now {
            return None;
        }
        Some(ChatPresence {
            id: i.id.clone(),
            participants: c.members.iter().map(|a| actors[a].name.clone()).collect(),
            turn: c.turn_queue.first().cloned(),
        })
    }

    pub(crate) fn latest_speech(&self, actor: &str) -> Option<SpeechView> {
        self.latest_speech_entry(actor).map(|(i, e)| SpeechView {
            chat_id: i.id.clone(),
            seq: e.seq,
            at: e.at,
            text: e.text.clone(),
            line: crate::journal::first_sentence(&e.text),
        })
    }

    fn chat_summary(actors: &Actors, i: &Interaction) -> ChatSummary {
        let c = super::chat::chat_of(i);
        ChatSummary {
            id: i.id.clone(),
            locale: i.locale.clone(),
            participants: c
                .ever_members
                .iter()
                .chain([&i.initiator, &i.partner])
                .collect::<std::collections::BTreeSet<_>>()
                .into_iter()
                .map(|a| actors[a].name.clone())
                .collect(),
            status: i.status,
            created_at: i.created_at,
            ended_at: i.ended_at,
            entries: c.entries.len(),
        }
    }

    /// 玩家只读观察入口，与 Agent 的私人观察分开。列表与正文都分页。
    pub(crate) fn chat_history(
        &self,
        actors: &Actors,
        resident: &str,
        request_id: String,
        chat_id: Option<String>,
        offset: usize,
    ) -> protocol::ServerMsg {
        let personal = actors.get(resident).is_some_and(|a| a.player_controlled());
        let heard = |entry: &&protocol::ChatEntry| !personal || entry.audience.contains(resident);
        let mut items: Vec<_> = self
            .items
            .values()
            .filter(|i| i.includes(resident) && i.chat.is_some())
            .collect();
        items.sort_by(|a, b| b.created_at.total_cmp(&a.created_at).then(b.id.cmp(&a.id)));
        let (chats, entries, total) = if let Some(id) = &chat_id {
            let all = items
                .iter()
                .find(|i| &i.id == id)
                .and_then(|i| i.chat.as_ref());
            (
                vec![],
                all.map(|c| {
                    c.entries
                        .iter()
                        .filter(heard)
                        .skip(offset)
                        .take(ENTRIES_PER_PAGE)
                        .cloned()
                        .collect()
                })
                .unwrap_or_default(),
                all.map_or(0, |c| c.entries.iter().filter(heard).count()),
            )
        } else {
            (
                items
                    .iter()
                    .skip(offset)
                    .take(CHATS_PER_PAGE)
                    .map(|i| {
                        let mut summary = Self::chat_summary(actors, i);
                        if personal {
                            summary.entries =
                                super::chat::chat_of(i).entries.iter().filter(heard).count();
                        }
                        summary
                    })
                    .collect(),
                vec![],
                items.len(),
            )
        };
        protocol::ServerMsg::ChatHistory {
            resident: resident.into(),
            request_id,
            chat_id,
            offset,
            total,
            chats,
            entries,
        }
    }
}
