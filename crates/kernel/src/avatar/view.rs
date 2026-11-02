//! 玩家控制目标的个人视图：本人、够得着的人与道具、门口、互动与聊天。
use super::*;
use crate::interactions::Interactions;
use protocol::{
    ApproachPerson, AvatarActor, AvatarChatItem, AvatarInteraction, AvatarMode, AvatarPairItem,
    AvatarPropView, AvatarState, AvatarView, Interaction, InteractionObservation, NearbyChat,
    NearbyPerson, PortalView,
};

/// 视图里列出的最近动作回执数。
const FEEDBACK_ACTIONS: usize = 3;
/// 这么远（米）以内还说不上话的人列给玩家，提示走过去。
const APPROACH_RANGE: f64 = 8.0;
/// 附身的居民没有自定外观时，地图标记用名字的第一个字和这个颜色。
const RESIDENT_COLOR: &str = "#397d60";

impl World {
    /// 玩家操控的人的步速（见 WALK_PACE、RUN_PACE）；没有行走地图时为空。
    pub fn avatar_walk(&self) -> Option<protocol::AvatarWalk> {
        let map = self.walk_map.as_ref()?;
        Some(protocol::AvatarWalk {
            metres_per_minute: map.metres_per_minute * WALK_PACE,
            sprint_factor: RUN_PACE / WALK_PACE,
        })
    }

    pub fn avatar_view(&self) -> AvatarView {
        let Some(map) = &self.walk_map else {
            return AvatarView::Unsupported { supported: false };
        };
        let Some(a) = self.actor(self.player_id()) else {
            return AvatarView::Empty {
                actor: (),
                supported: true,
                units: map.svg_units_per_metre,
            };
        };
        let b = Builder {
            w: self,
            a,
            reach: Reach::new(self),
        };
        let awaiting = a.possession.as_ref().is_some_and(|p| p.awaiting_arrival);
        AvatarView::Present(Box::new(AvatarState {
            actor: b.actor(awaiting),
            awaiting_arrival: awaiting,
            can_drop: b.reach.drop_station().is_some(),
            feedback: feedback(a),
            interactions: self
                .interactions
                .for_actor(&a.id)
                .into_iter()
                .map(|i| b.interaction(i))
                .collect(),
            miracles: self.miracles && a.is_avatar(),
            mode: if a.possession.is_some() {
                AvatarMode::Possession
            } else {
                AvatarMode::Avatar
            },
            navigation_revision: self.topo.navigation_revision().unwrap_or(1),
            nearby: b.nearby_people(),
            approach: b.approach_people(),
            nearby_chats: b.reachable_chats(),
            portals: b.nearby_portals(map),
            props: b.reachable_props(),
            reading: self
                .contents
                .readings
                .get(&a.id)
                .and_then(|reads| reads.values().last())
                .map(|r| r.content.view()),
            supported: true,
            units: map.svg_units_per_metre,
        }))
    }
}

/// 拼化身视图的各部分：世界、控制目标、这次视图共用的可达判断。
struct Builder<'a> {
    w: &'a World,
    a: &'a Actor,
    reach: Reach<'a>,
}

impl Builder<'_> {
    fn actor(&self, awaiting: bool) -> AvatarActor {
        let (w, a) = (self.w, self.a);
        let appearance = a
            .avatar
            .as_ref()
            .map(|p| p.appearance.clone())
            .unwrap_or_else(|| Appearance {
                marker: a.name.chars().take(1).collect(),
                color: RESIDENT_COLOR.into(),
                profile: None,
                look: None,
            });
        AvatarActor {
            activity: a.current.verb.clone(),
            appearance,
            body: w.body_view(&a.id),
            busy: !a.interaction_available() || awaiting,
            id: a.id.clone(),
            inventory: w.inventory_view(&a.id),
            locus: a.locus.clone(),
            name: a.name.clone(),
            // 化身没有身体需求。
            needs: if a.is_avatar() {
                vec![]
            } else {
                a.needs.states()
            },
            present: a.present(),
            remaining: a.current.left_text(),
            revision: a.actions.revision,
        }
    }

    /// 够得着、能看到的人（隔着处所分界、走在路上的也算，见 Reach::pair）。
    fn nearby_people(&self) -> Vec<NearbyPerson> {
        let a = self.a;
        self.w
            .actors
            .values()
            .filter(|b| b.id != a.id && b.present() && self.reach.pair(&a.id, &b.id).is_ok())
            .map(|b| {
                let can_talk = self.w.talk_available(&b.id);
                NearbyPerson {
                    activity: b.current.verb.clone(),
                    available: b.interaction_available(),
                    can_talk,
                    busy: (!can_talk).then(|| self.busy_reason(b)),
                    dead: b.needs.body.dead,
                    id: b.id.clone(),
                    name: b.name.clone(),
                }
            })
            .collect()
    }

    /// 为什么现在和他聊不了，写给玩家看。
    fn busy_reason(&self, b: &Actor) -> String {
        if b.needs.body.dead {
            "已经死了".into()
        } else if b.needs.incapacitated() {
            "倒下了，没法回应".into()
        } else if let Some(id) = &b.current.interaction {
            let with_me = self
                .w
                .interactions
                .get(id)
                .is_some_and(|i| i.includes(&self.a.id));
            if with_me {
                "正在和你说话"
            } else {
                "正在和别人说话"
            }
            .into()
        } else if let Err(e) = self.w.check_weather_chat(&b.id) {
            e.to_string()
        } else {
            "现在没法回应".into()
        }
    }

    /// 附近（同一空间 APPROACH_RANGE 米内）还说不上话、能走过去找的人：离得远，或者中间隔着东西。
    fn approach_people(&self) -> Vec<ApproachPerson> {
        let a = self.a;
        self.w
            .actors
            .values()
            .filter(|b| {
                b.id != a.id
                    && b.present()
                    && !b.needs.incapacitated()
                    && self.reach.pair(&a.id, &b.id).is_err()
            })
            .filter_map(|b| {
                let (distance, visible) = self.reach.gap(&a.id, &b.id)?;
                (distance <= APPROACH_RANGE).then(|| ApproachPerson {
                    id: b.id.clone(),
                    name: b.name.clone(),
                    distance: (distance * 10.).round() / 10.,
                    blocked: !visible && distance <= TALK_REACH,
                })
            })
            .collect()
    }

    /// 眼前或随身、而且够得着的道具，带动作说明和容器里的东西。
    fn reachable_props(&self) -> Vec<AvatarPropView> {
        let (w, a) = (self.w, self.a);
        w.topo
            .props()
            .iter()
            .filter(|p| {
                !p.withdrawn
                    && w.inventory.at_hand(&w.props, &a.id, p, &a.locus.locale)
                    && self.reach.prop(&a.id, &p.id).is_ok()
            })
            .map(|p| AvatarPropView {
                actions: p
                    .verbs
                    .iter()
                    .filter_map(|v| v.action.as_ref())
                    .map(|x| crate::props::action_description_for(x, w.physiology()))
                    .collect(),
                bulletin_board: p.bulletin_board,
                carried: w.inventory.carried_by(&p.id, &a.id),
                contents: w.container_items(&a.id, &p.id),
                id: p.id.clone(),
                name: p.name.clone(),
                portable: p.portable,
                storage_slots: p.storage_slots,
            })
            .collect()
    }

    /// 同一空间里伸手够得着的门口。
    fn nearby_portals(&self, map: &WalkMap) -> Vec<PortalView> {
        let Some(here) = self.w.actor_spot(&self.a.id) else {
            return vec![];
        };
        map.portals
            .iter()
            .filter(|p| {
                p.from.space == here.space && distance(p.from.position, here.position) <= REACH
            })
            .map(|p| PortalView {
                id: p.id.clone(),
                label: p.label.clone(),
            })
            .collect()
    }

    /// 附近的聊天：成员都够得着（不隔墙）才列出。
    /// 能加入的交谈：在场的人都够得着（不管在哪个处所，加入时化身挪进去，见 step_player_into）。
    fn reachable_chats(&self) -> Vec<NearbyChat> {
        let actor = &self.a.id;
        self.w
            .interactions
            .running_chats()
            .into_iter()
            .filter(|c| {
                c.members
                    .iter()
                    .all(|id| self.reach.pair(actor, id).is_ok())
            })
            .collect()
    }

    /// 互动的观察，加上邀请内容与玩家此刻能不能发言、能不能请求发言。
    fn interaction(&self, i: &Interaction) -> AvatarInteraction {
        let actor = &self.a.id;
        let can_speak = self.w.chat_turn(actor);
        let can_request_turn = i
            .chat
            .as_ref()
            .is_some_and(|c| c.members.contains(actor) && c.resume_at > self.w.minutes);
        match Interactions::observation(actor, i) {
            InteractionObservation::Chat(c) => AvatarInteraction::Chat(AvatarChatItem {
                can_request_turn,
                can_speak,
                entries: c.entries,
                expires_at: i.expires_at,
                id: c.id,
                initiator: c.initiator,
                kind: c.kind,
                locale: c.locale,
                members: c.members,
                message: i.message.clone(),
                partner: c.partner,
                reason: i.reason.clone(),
                reply: i.reply.clone(),
                status: c.status,
                turn: c.turn,
                response_error: None,
            }),
            InteractionObservation::Pair(p) => AvatarInteraction::Pair(AvatarPairItem {
                accepted: p.accepted,
                can_request_turn,
                can_speak,
                changes: p.changes,
                created_at: p.created_at,
                duration_minutes: p.duration_minutes,
                ended_at: p.ended_at,
                event_ids: p.event_ids,
                expires_at: p.expires_at,
                id: p.id,
                initiator: p.initiator,
                kind: p.kind,
                locale: p.locale,
                message: p.message,
                partner: p.partner,
                reason: p.reason,
                reply: p.reply,
                started_at: p.started_at,
                status: p.status,
                response_error: None,
            }),
        }
    }
}

/// 最近几个动作回执里的变化与失败原因，新的在前。
fn feedback(a: &Actor) -> Vec<String> {
    let mut results: Vec<_> = a.actions.groups.values().flat_map(|g| &g.results).collect();
    results.sort_by(|x, y| {
        y.ended_at
            .total_cmp(&x.ended_at)
            .then_with(|| y.action_id.cmp(&x.action_id))
    });
    results
        .into_iter()
        .take(FEEDBACK_ACTIONS)
        .flat_map(|r| r.changes.iter().cloned().chain(r.reason.iter().cloned()))
        .collect()
}
