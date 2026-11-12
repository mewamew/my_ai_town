//! 存档里只增不改的那部分：每个人的事件、过完的日子、做完的动作组、结束了的互动。
//! 它们只会越攒越多，所以不进 world.json：host 把新增的追加写进流水文件，读档时读回来装上
//! （内核不碰文件，这里只管拆和装）。内存里的世界照旧带着全部历史，规则和读档校验都不知道拆过。
use crate::error::{KernelError, Result};
use crate::{
    action_state::ActionState,
    actor::Actor,
    journal::{DayRecord, Journal},
    snapshot::WorldSnapshot,
    World,
};
use protocol::{ActionGroup, GroupStatus, Interaction, WorldFact};
use std::collections::{BTreeMap, BTreeSet};

/// 流水里的一条。
#[derive(Debug, Clone)]
pub enum Record {
    /// 某人的一条事件；每个人的事件按编号从小到大写。
    Event { actor: String, fact: WorldFact },
    /// 某人过完的一天（日志页用）。
    Day { actor: String, day: DayRecord },
    /// 某人做完的一组动作。做完的动作组不会再变：读档校验要求它带齐全部回执。
    Actions { actor: String, group: ActionGroup },
    /// 结束了的互动。同一编号再出现时后写的算数。
    Interaction(Box<Interaction>),
}

/// 哪些已经写进流水了。host 按存档留一份，写成一条记一条（`note`）。
#[derive(Debug, Clone, Default)]
pub struct Archived {
    /// 每人写到了第几号事件
    events: BTreeMap<String, u64>,
    /// 每人写了几天
    days: BTreeMap<String, usize>,
    /// 每人写过的动作组
    groups: BTreeMap<String, BTreeSet<String>>,
    /// 写过的互动和它当时的样子（`stamp`）
    interactions: BTreeMap<String, u64>,
}

impl Archived {
    /// 这一条已经在流水里了。
    pub fn note(&mut self, record: &Record) {
        match record {
            Record::Event { actor, fact } => {
                self.events.insert(actor.clone(), fact.event_id);
            }
            Record::Day { actor, .. } => *self.days.entry(actor.clone()).or_default() += 1,
            Record::Actions { actor, group } => {
                self.groups
                    .entry(actor.clone())
                    .or_default()
                    .insert(group.id.clone());
            }
            Record::Interaction(item) => {
                self.interactions.insert(item.id.clone(), stamp(item));
            }
        }
    }
}

/// 拆开的世界：world.json 里的当前状态，和这次要追加进流水的部分。
pub struct Detached {
    pub snapshot: WorldSnapshot,
    pub records: Vec<Record>,
}

impl World {
    /// 存盘用：把还没写进流水的历史拆出来，快照里只留当前状态（今天的流水、正在做的动作组、
    /// 没结束的互动都算当前状态）。只克隆当前状态和新增的那几条，不随历史变长而变慢。
    /// `archived` 记的东西这个世界里对不上（世界重置过，不是接着那份流水往下走的）时返回 None，
    /// 调用方另起一份流水，从空的 `Archived` 重新拆。
    pub fn detach(&self, archived: &Archived) -> Option<Detached> {
        let known = |id: &String| self.actors.contains_key(id);
        if !(archived.events.keys().all(known)
            && archived.days.keys().all(known)
            && archived.groups.keys().all(known))
        {
            return None;
        }
        let mut records = Vec::new();
        let mut actors = BTreeMap::new();
        for (id, a) in &self.actors {
            let cursor = archived.events.get(id).copied().unwrap_or(0);
            let days = archived.days.get(id).copied().unwrap_or(0);
            if a.journal.cursor() < cursor || a.journal.days.len() < days {
                return None;
            }
            for fact in a.journal.events_after(cursor) {
                records.push(Record::Event {
                    actor: id.clone(),
                    fact: fact.clone(),
                });
            }
            for day in &a.journal.days[days..] {
                records.push(Record::Day {
                    actor: id.clone(),
                    day: day.clone(),
                });
            }
            let done = archived.groups.get(id);
            let mut found = 0;
            let mut running = BTreeMap::new();
            for (group_id, group) in &a.actions.groups {
                if group.status == GroupStatus::Running {
                    running.insert(group_id.clone(), group.clone());
                } else if done.is_some_and(|d| d.contains(group_id)) {
                    found += 1;
                } else {
                    records.push(Record::Actions {
                        actor: id.clone(),
                        group: group.clone(),
                    });
                }
            }
            if found != done.map_or(0, BTreeSet::len) {
                return None;
            }
            actors.insert(id.clone(), current_state(a, running));
        }
        let mut found = 0;
        let mut open = BTreeMap::new();
        for (id, item) in &self.interactions.items {
            if !item.status.terminal() {
                open.insert(id.clone(), item.clone());
                continue;
            }
            match archived.interactions.get(id) {
                // 结束了的互动照理不再变；万一变了（和写进流水时的样子对不上）就再写一份新的
                Some(written) => {
                    found += 1;
                    if *written != stamp(item) {
                        records.push(Record::Interaction(Box::new(item.clone())));
                    }
                }
                None => records.push(Record::Interaction(Box::new(item.clone()))),
            }
        }
        if found != archived.interactions.len() {
            return None;
        }
        Some(Detached {
            snapshot: self.snapshot_with(actors, open),
            records,
        })
    }
}

impl WorldSnapshot {
    /// 读档用：把流水装回只有当前状态的快照，得到和拆之前一样的完整快照；返回装回了哪些，
    /// 之后的存盘从这里接着往下写。
    pub fn attach(&mut self, records: impl IntoIterator<Item = Record>) -> Result<Archived> {
        let mut archived = Archived::default();
        let mut ended = BTreeSet::new();
        for record in records {
            archived.note(&record);
            match record {
                Record::Event { actor, fact } => {
                    let journal = &mut self.actor_of(&actor)?.journal;
                    ensure!(
                        journal.cursor() < fact.event_id,
                        KernelError::snapshot("流水里的事件编号没有递增")
                    );
                    journal.events.push(fact);
                }
                Record::Day { actor, day } => self.actor_of(&actor)?.journal.days.push(day),
                Record::Actions { actor, group } => {
                    let groups = &mut self.actor_of(&actor)?.actions.groups;
                    ensure!(
                        groups.insert(group.id.clone(), group).is_none(),
                        KernelError::snapshot("流水里的动作组在存档里重复出现")
                    );
                }
                Record::Interaction(item) => {
                    // 后写的盖掉先写的；world.json 里留着的是没结束的互动，不该同时在流水里
                    ensure!(
                        ended.contains(&item.id) || !self.interactions.contains_key(&item.id),
                        KernelError::snapshot("流水里的互动在存档里重复出现")
                    );
                    ended.insert(item.id.clone());
                    self.interactions.insert(item.id.clone(), *item);
                }
            }
        }
        Ok(archived)
    }

    fn actor_of(&mut self, id: &str) -> Result<&mut Actor> {
        self.actors
            .get_mut(id)
            .ok_or_else(|| KernelError::snapshot(format!("流水里的记录属于存档里没有的人 {id}")))
    }
}

/// 人物写进 world.json 的样子：事件、过完的日子和做完的动作组在流水里，这里不带。
/// 每个字段都写出来：以后给人物加字段，编译器会要求在这里决定它算当前状态还是历史。
fn current_state(a: &Actor, running: BTreeMap<String, ActionGroup>) -> Actor {
    Actor {
        kind: a.kind,
        avatar: a.avatar.clone(),
        possession: a.possession.clone(),
        free_walk: a.free_walk.clone(),
        player_events: a.player_events.clone(),
        id: a.id.clone(),
        name: a.name.clone(),
        locus: a.locus.clone(),
        current: a.current.clone(),
        plan: a.plan.clone(),
        actions: ActionState {
            player_groups: a.actions.player_groups.clone(),
            player_interactions: a.actions.player_interactions.clone(),
            cancel_after_current: a.actions.cancel_after_current,
            agent_controlled: a.actions.agent_controlled,
            revision: a.actions.revision,
            groups: running,
        },
        journal: Journal {
            events: Vec::new(),
            today: a.journal.today.clone(),
            thoughts_today: a.journal.thoughts_today.clone(),
            days: Vec::new(),
            thought: a.journal.thought.clone(),
        },
        home: a.home.clone(),
        needs: a.needs.clone(),
        bodies_seen: a.bodies_seen.clone(),
        lost: a.lost.clone(),
        places_known: a.places_known.clone(),
        found: a.found.clone(),
    }
}

/// 一项互动的样子：状态、各个时刻和每一部分的长度。聊天记录和事件来源只会往后加、不会改，
/// 所以量长度就够认出「写进流水之后又变了」，不用把整场交谈重新比一遍。
fn stamp(item: &Interaction) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    std::mem::discriminant(&item.status).hash(&mut hasher);
    std::mem::discriminant(&item.kind).hash(&mut hasher);
    item.accepted.hash(&mut hasher);
    for at in [
        Some(item.created_at),
        Some(item.expires_at),
        Some(item.duration_minutes),
        item.started_at,
        item.ended_at,
    ] {
        at.map(f64::to_bits).hash(&mut hasher);
    }
    let lengths = [
        item.locale.len(),
        item.message.len(),
        item.reply.as_ref().map_or(0, String::len),
        item.reason.as_ref().map_or(0, String::len),
        item.changes.len(),
        item.changes.iter().map(String::len).sum(),
        item.event_ids.len(),
        item.event_ids.values().map(Vec::len).sum(),
    ];
    lengths.hash(&mut hasher);
    if let Some(chat) = &item.chat {
        let lengths = [
            chat.entries.len(),
            chat.members.len(),
            chat.ever_members.len(),
            chat.turn_queue.len(),
            chat.passes,
        ];
        lengths.hash(&mut hasher);
        chat.resume_at.to_bits().hash(&mut hasher);
        chat.proposal.is_some().hash(&mut hasher);
    }
    hasher.finish()
}
