//! 世界事实的只读展示投影；这里不切换活动、不改队列、不发通知。
//! 各子系统的视图函数在各自模块里，这里是给 host 与 Agent 的统一读取入口。
use crate::activity::{travel_minutes_left, ActKind, Activity};
use crate::intent::StopCond;
use crate::topology::{Prop, Topology};
use crate::{
    calendar, content::ContentState, interactions::Interactions, inventory::Inventory,
    props::Props, World,
};
use protocol::{MovementPhase, PlanView, RosterLocale, RosterMember, ServerMsg};
use std::collections::BTreeMap;

impl Activity {
    /// 给观察仪看的当前任务说明。这里只投影已经成为世界事实的活动，
    /// 不暴露内部结构，也不让前端反推执行规则。
    pub(crate) fn plan_text(&self, topo: &Topology) -> String {
        if let Some(label) = self.content_label() {
            return format!("{label}（{}）", self.left_text());
        }
        match &self.kind {
            ActKind::Travel { journey, .. } => {
                let dest = topo.locale_name(&journey.dest_locale);
                if let Some(pending) = &self.pending {
                    format!("前往 {dest} 的操作点，抵达后{}", pending.verb())
                } else {
                    format!("前往 {dest}")
                }
            }
            ActKind::Placeholder {
                cond: StopCond::Never,
            } if self.interaction.is_some() => "正在交谈，等待回应".into(),
            ActKind::Placeholder {
                cond: StopCond::Never,
            } => "等待新计划".into(),
            ActKind::Placeholder {
                cond: StopCond::Duration(m),
            }
            | ActKind::Timed {
                cond: StopCond::Duration(m),
            } if *m <= 0.0 => {
                format!("{}（即将开始下一项）", self.verb)
            }
            _ => format!("{}（{}）", self.verb, self.left_text()),
        }
    }

    pub fn content_label(&self) -> Option<String> {
        match self.content.as_ref()? {
            crate::content::Pending::Reading { content, .. } => {
                Some(format!("阅读《{}》版本 {}", content.title, content.version))
            }
            crate::content::Pending::Writing { placement } => {
                Some(format!("创作《{}》", placement.definition.name))
            }
        }
    }

    /// 还剩多久（人类可读）：「还剩 N 分钟」「至天亮」「至天黑」。无期占位与已到期为空。
    /// 提示词与观察仪同源：给模型看的剩余时长就是观察仪上那一句。
    pub fn left_text(&self) -> String {
        let cond = match &self.kind {
            ActKind::Placeholder { cond } | ActKind::Timed { cond } => cond,
            ActKind::Travel { journey, stage } => {
                return format!("还剩 {:.0} 分钟", travel_minutes_left(journey, stage));
            }
        };
        match cond {
            StopCond::Duration(m) if *m <= 0.0 => String::new(),
            StopCond::Duration(m) => format!("还剩 {m:.0} 分钟"),
            StopCond::Dawn => "至天亮".into(),
            StopCond::Dusk => "至天黑".into(),
            StopCond::Never => String::new(),
        }
    }
}

/// 移动中的人在精确导航地图上的路线与阶段（前端按此插值）。
fn movement(topo: &Topology, a: &crate::world::Actor) -> Option<protocol::MovementView> {
    let ActKind::Travel { journey, .. } = &a.current.kind else {
        return None;
    };
    if !topo.precise_navigation {
        return None;
    }
    Some(protocol::MovementView {
        route: a.locus.locale.clone(),
        navigation_revision: topo.navigation_revision().unwrap_or(1),
        destination_station: journey.dest_station.clone(),
        phase: if a.current.pending.is_some() {
            MovementPhase::Approach
        } else {
            MovementPhase::Travel
        },
    })
}

fn roster(world: &World, speed: f64) -> ServerMsg {
    let mut by_locale: BTreeMap<String, Vec<RosterMember>> = BTreeMap::new();
    for a in world.actors.values().filter(|a| a.present()) {
        by_locale
            .entry(a.locus.locale.clone())
            .or_default()
            .push(RosterMember {
                appearance: a.avatar.as_ref().map(|p| p.appearance.clone()),
                chat: world
                    .interactions
                    .chat_presence(&world.actors, a, world.minutes),
                speech: world.interactions.latest_speech(&a.id),
                inventory: world.inventory_view(&a.id),
                id: a.id.clone(),
                name: a.name.clone(),
                kind: a.kind,
                at: a.locus.at.clone(),
                verb: a.current.verb.clone(),
                verb_kind: a.current.verb_kind(),
                movement: movement(&world.topo, a),
                activity: a.current.kind(),
                needs: a.needs.states(),
                body: world.body_view(&a.id),
                plan: {
                    let walk = world.walk_plan(&a.id);
                    let idle = !a.needs.incapacitated()
                        && walk.is_none()
                        && a.current.is_idle()
                        && a.plan.is_empty();
                    PlanView {
                        current: if a.needs.incapacitated() {
                            a.needs.limitation().into()
                        } else if let Some(walk) = walk {
                            walk
                        } else {
                            a.current.plan_text(&world.topo)
                        },
                        upcoming: a
                            .plan
                            .iter()
                            .map(|intent| intent.describe(&world.topo))
                            .collect(),
                        idle,
                    }
                },
                thought: a.journal.view(),
                resident_agent: None,
            });
    }
    ServerMsg::Roster {
        environment: world.weather.as_ref().map(|w| w.view.clone()),
        game_mode: world.game_mode_view(),
        sim_minutes: world.minutes,
        clock: world.clock(),
        speed,
        pace: speed,
        period: calendar::period(world.minutes).into(),
        holds: Vec::new(),
        locales: by_locale
            .into_iter()
            .map(|(locale, members)| RosterLocale { locale, members })
            .collect(),
    }
}

impl World {
    /// 同行里的人在名册上的说明：「跟着旅人走，去陈默家」「带陈默去陈默家」。
    fn walk_plan(&self, actor: &str) -> Option<String> {
        let item = self.interactions.walk_of(actor)?;
        let protocol::InteractionKind::Walk { leader, locale } = &item.kind else {
            return None;
        };
        let to = locale
            .as_ref()
            .map(|l| format!("去{}", self.topo.locale_name(l)))
            .unwrap_or_default();
        let name = |id: &str| {
            self.actors
                .get(id)
                .map_or(String::new(), |a| a.name.clone())
        };
        Some(if leader == actor {
            let others: Vec<_> = item
                .chat
                .as_ref()?
                .members
                .iter()
                .filter(|m| *m != actor)
                .map(|m| name(m))
                .collect();
            format!("带{}{to}", others.join("、"))
        } else if to.is_empty() {
            format!("跟着{}走", name(leader))
        } else {
            format!("跟着{}走，{to}", name(leader))
        })
    }

    // ---------- 子系统的只读入口：改动只走世界的命令 ----------

    pub fn interactions(&self) -> &Interactions {
        &self.interactions
    }
    pub fn inventory(&self) -> &Inventory {
        &self.inventory
    }
    pub fn props(&self) -> &Props {
        &self.props
    }
    pub fn contents(&self) -> &ContentState {
        &self.contents
    }

    // ---------- Roster 流 ----------

    pub fn roster(&self, speed: f64) -> ServerMsg {
        roster(self, speed)
    }

    /// 日志：按天归档的执行记录、想法与「昨天」（观察仪日志页）。
    pub fn diary(&self, actor_id: &str) -> Vec<protocol::DiaryDay> {
        self.actors
            .get(actor_id)
            .map(|a| a.journal.diary(calendar::day_index(self.minutes)))
            .unwrap_or_default()
    }

    // ---------- 道具与背包 ----------

    pub fn can_access_prop(&self, actor: &str, prop: &Prop) -> bool {
        self.sees_prop(actor, &prop.id)
            && self.actors.get(actor).is_some_and(|a| {
                self.inventory
                    .at_hand(&self.props, actor, prop, &a.locus.locale)
            })
    }
}
