//! 世界检查点：只保存动态状态，拓扑和场景规则由 host 加载并检查兼容性。
//! 内核不碰文件；恢复不补算离线时间，也不重新执行已经完成的动作。
//! 存档直接序列化运行期的类型（Actor、protocol::Interaction、背包表、作品表、天气状态等），
//! 存档格式就是这些类型的 serde 形状：改字段名或 serde 属性就是改存档格式，要升 SCHEMA_VERSION
//! 并保证旧档能读。这里负责把各子系统的状态收拢成一份存档，以及读档时的整体校验与装回。
use crate::error::{KernelError, Result};
use crate::{
    activity::{ActKind, TravelStage},
    actor::Actor,
    affordance::Affordances,
    content::ContentState,
    intent::{Intent, StopCond},
    path::Journey,
    physiology,
    props::split_supply_key,
    topology::Topology,
    World,
};
use protocol::{At, Locus};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// 当前写出的存档版本。1：无身体字段；2：加身体；3：加背包；4：加玩家化身与附身；5：加天气。
/// 之后只追加带默认值的字段（道具动作的后续、淋湿进度、天气影响身体开关），旧档照常读入，不升版本。
const SCHEMA_VERSION: u32 = 5;

/// `World::checkpoint` 的回滚点。
pub struct WorldCheckpoint {
    snapshot: WorldSnapshot,
    events: Vec<crate::Event>,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WorldSnapshot {
    #[serde(default)]
    weather: Option<crate::weather::WeatherSnapshot>,
    #[serde(default)]
    walk_prop_positions: BTreeMap<String, crate::avatar::Spot>,
    #[serde(default)]
    removed_props: std::collections::BTreeSet<String>,
    #[serde(default)]
    spatial_overrides: BTreeMap<String, crate::navigation::space::Override>,
    #[serde(default)]
    navigation_revision: u64,
    schema_version: u32,
    #[serde(default)]
    inventory: Option<crate::inventory::Inventory>,
    minutes: f64,
    actors: BTreeMap<String, Actor>,
    contents: ContentState,
    /// 旧存档的规划请求表；对应机制已删，读入即丢弃，新存档不写。
    #[serde(default, skip_serializing, rename = "replans")]
    _replans: Option<serde_json::Value>,
    #[serde(default)]
    interactions: BTreeMap<String, protocol::Interaction>,
    #[serde(default)]
    placed_props: BTreeMap<String, crate::props::Placement>,
    #[serde(default)]
    supplies: BTreeMap<String, u32>,
    /// 旧存档没有这一项，按全部开启读入。
    #[serde(default)]
    physiology: protocol::PhysiologySwitches,
    /// 旧存档没有这一项：没有待发生的事，随机流从固定起点开始。
    #[serde(default)]
    happenings: crate::happenings::Happenings,
}

impl World {
    pub fn snapshot(&self) -> WorldSnapshot {
        WorldSnapshot {
            weather: Some(match &self.weather {
                Some(weather) => crate::weather::WeatherSnapshot::Enabled {
                    weather: Box::new(weather.clone()),
                },
                None => crate::weather::WeatherSnapshot::Disabled,
            }),
            walk_prop_positions: self.props.walk_positions.clone(),
            removed_props: self.props.removed.clone(),
            spatial_overrides: self
                .topo
                .navigation
                .as_ref()
                .map(|s| s.overrides.clone())
                .unwrap_or_default(),
            navigation_revision: self.topo.navigation_revision().unwrap_or_default(),
            schema_version: SCHEMA_VERSION,
            inventory: Some(self.inventory.clone()),
            minutes: self.minutes,
            actors: self.actors.clone(),
            contents: self.contents.clone(),
            _replans: None,
            interactions: self.interactions.items.clone(),
            placed_props: self.props.placed.clone(),
            supplies: self.props.supplies.clone(),
            physiology: self.physiology,
            happenings: self.happenings.clone(),
        }
    }

    /// 事务回滚点：世界快照加上尚未发出的世界日志。普通存档恢复不重放日志，事务回滚要把它们还回去。
    pub fn checkpoint(&self) -> WorldCheckpoint {
        WorldCheckpoint {
            snapshot: self.snapshot(),
            events: self.events.clone(),
        }
    }
    pub fn restore_checkpoint(&mut self, checkpoint: WorldCheckpoint) -> Result<()> {
        self.restore_snapshot(checkpoint.snapshot)?;
        self.events = checkpoint.events;
        Ok(())
    }
    /// 在候选世界上完成全部恢复步骤并校验，成功才整体替换当前世界；失败时当前世界不变。
    /// 人口是存档自己的动态状态，不要求与启动时预生成的人物集合相同。
    pub fn restore_snapshot(&mut self, mut snapshot: WorldSnapshot) -> Result<()> {
        // 地图自带的道具加上存档里的运行时放置。
        crate::props::check_room(
            self.topo.props().len() - self.props.placed.len(),
            snapshot.placed_props.len(),
        )
        .map_err(|_| KernelError::snapshot("存档自定义道具数量超限"))?;
        if snapshot.schema_version == 1 {
            migrate_collapsed(&mut snapshot);
        }
        // 能力判断依赖开关，校验互动等状态前先写到每个人身上。
        for a in snapshot.actors.values_mut() {
            a.needs.switches = snapshot.physiology;
        }
        let mut candidate = self.restore_candidate(&snapshot)?;
        candidate.physiology = snapshot.physiology;
        snapshot.validate(&candidate)?;
        candidate.minutes = snapshot.minutes;
        candidate.actors = snapshot.actors;
        // 旧存档没有已见尸体名单：当时已有的尸体算作人人都见过，读档后不补发一串发现。
        let dead: std::collections::BTreeSet<String> = candidate
            .actors
            .values()
            .filter(|a| a.needs.body.dead)
            .map(|a| a.id.clone())
            .collect();
        for a in candidate.actors.values_mut() {
            a.bodies_seen.get_or_insert_with(|| dead.clone());
        }
        candidate.interactions = crate::interactions::Interactions::restore(snapshot.interactions);
        candidate.contents = snapshot.contents;
        candidate.happenings = snapshot.happenings;
        candidate.props.removed = snapshot.removed_props;
        candidate.inventory.revision = self.inventory.revision;
        candidate.events.clear();
        // 恢复不补发任何请求：Agent 运行器自己按世界状态决定何时唤醒。
        if snapshot.schema_version == 1 {
            candidate.settle_legacy_supplies();
        }
        candidate.placer = self.placer.take();
        *self = candidate;
        Ok(())
    }

    /// 从存档重建道具表、作品、空间覆盖、补给和背包；人物与互动在校验后再装入。
    fn restore_candidate(&self, snapshot: &WorldSnapshot) -> Result<World> {
        let restored_props = snapshot
            .placed_props
            .iter()
            .map(|(id, p)| {
                ensure!(
                    id == &p.instance.id,
                    KernelError::snapshot("存档道具实例编号不一致")
                );
                self.props.validate_placement(&self.topo, p)
            })
            .collect::<Result<Vec<_>>>()?;
        let mut candidate = World::new(
            self.props.base_topology(&self.topo),
            snapshot.minutes,
            self.need_rules.clone(),
        );
        candidate.walk_map = self.walk_map.clone();
        candidate.weather = self.restored_weather(snapshot)?;
        candidate.props.base_locales = self.props.base_locales.clone();
        for id in self.props.placed.keys() {
            candidate.topo.remove_prop(id);
        }
        for prop in restored_props {
            candidate.topo.push_prop(prop);
        }
        candidate.props.placed = snapshot.placed_props.clone();
        candidate.validate_walk_props(&snapshot.walk_prop_positions)?;
        candidate.props.walk_positions = snapshot.walk_prop_positions.clone();
        for p in candidate.topo.props_mut() {
            if self.props.is_removed(&p.id) {
                p.withdrawn = false;
            }
        }
        snapshot.contents.restore_props(&mut candidate.topo)?;
        // 关联的公告栏也可能来自存档，须在全部实例就位后检查。
        for prop in candidate.topo.props() {
            candidate.topo.check_board(
                prop.board.as_deref(),
                &prop.locale,
                prop.readable.as_ref(),
            )?;
        }
        candidate.affordances.rebuild(&candidate.topo);
        candidate.restore_navigation(snapshot)?;
        for id in &snapshot.removed_props {
            candidate.remove_prop(id)?;
        }
        // 回放移除会推进修订号；存档里的修订号才是客户端见过的最后一个，最后再对齐。
        if let Some(s) = &mut candidate.topo.navigation {
            s.navigation_revision = snapshot.navigation_revision.max(1);
        }
        candidate.props.supplies = snapshot.supplies.clone();
        let inventory = snapshot.inventory.clone().unwrap_or_default();
        inventory.validate(
            &candidate.topo,
            &candidate.props,
            &snapshot.actors,
            &snapshot.removed_props,
        )?;
        candidate.inventory.apply(&mut candidate.topo, inventory);
        candidate.affordances.rebuild(&candidate.topo);
        Ok(candidate)
    }

    /// 存档里的天气；没有天气字段的旧档按当前世界的规则与种子从读档时刻重新开始。
    fn restored_weather(
        &self,
        snapshot: &WorldSnapshot,
    ) -> Result<Option<crate::weather::WeatherState>> {
        Ok(match &snapshot.weather {
            Some(crate::weather::WeatherSnapshot::Enabled { weather }) => {
                Some(weather.as_ref().clone())
            }
            Some(crate::weather::WeatherSnapshot::Disabled) => None,
            None => self
                .weather
                .as_ref()
                .map(|w| {
                    crate::weather::WeatherState::new(
                        w.rules.clone(),
                        w.rng.seed,
                        snapshot.minutes,
                        w.view.world_id.clone(),
                    )
                })
                .transpose()?,
        })
    }

    /// 撤掉当前拓扑里的运行时空间覆盖，换成存档里的那套。
    fn restore_navigation(&mut self, snapshot: &WorldSnapshot) -> Result<()> {
        let previous: Vec<_> = self
            .topo
            .navigation
            .as_ref()
            .map(|s| s.overrides.keys().cloned().collect())
            .unwrap_or_default();
        for id in previous {
            self.topo.remove_override(&id);
        }
        if !snapshot.spatial_overrides.is_empty() {
            let speed = crate::navigation::walk_speed(self.walk_map.as_deref())?;
            for v in snapshot.spatial_overrides.values() {
                self.topo.install_override(v.clone(), speed)?;
            }
        }
        Ok(())
    }

    /// schema 1 没有补给结算：正在消耗补给的旧动作取消，已发生的效果保留。
    fn settle_legacy_supplies(&mut self) {
        let now = self.minutes;
        for id in self.actor_ids() {
            let consuming = physiology::body_spot(self, &self.actors[&id])
                .is_some_and(|s| s.action.as_ref().is_some_and(|a| a.supply.is_some()));
            if consuming {
                self.interrupt_actions(&id, "升级消耗品结算：保留已发生效果，取消未完成旧动作");
                self.actor_mut(&id).reset_idle(now, false);
            }
        }
    }
}

/// schema 1 的失能字段：保留饱腹和精力，取消旧的定时苏醒。
fn migrate_collapsed(snapshot: &mut WorldSnapshot) {
    let now = snapshot.minutes;
    for actor in snapshot.actors.values_mut() {
        if actor.needs.collapsed.take().is_some() {
            actor.reset_idle(now, true);
            actor.journal.record(
                now,
                "旧失能记录迁移：保留饱腹和精力，取消旧定时苏醒；水分 85、健康 100，不追溯损害",
            );
        }
    }
}

impl WorldSnapshot {
    /// 已知旧档按世界身份派生独立天气种子，不补算过去的天气。`current` 是当前世界的天气。
    pub fn migrate_weather(
        &mut self,
        current: Option<&crate::weather::WeatherState>,
        world_id: &str,
    ) -> Result<()> {
        if self.schema_version >= 5 {
            return Ok(());
        }
        let seed = format!("weather-v1:{world_id}")
            .bytes()
            .fold(2166136261u32, |hash, b| {
                (hash ^ u32::from(b)).wrapping_mul(16777619)
            })
            .max(1);
        self.weather = Some(match current {
            Some(w) => crate::weather::WeatherSnapshot::Enabled {
                weather: Box::new(crate::weather::WeatherState::new(
                    w.rules.clone(),
                    seed,
                    self.minutes,
                    world_id.into(),
                )?),
            },
            None => crate::weather::WeatherSnapshot::Disabled,
        });
        Ok(())
    }
    /// 存档里的人物身份（id、住宅），按 id 排序；旧档的兼容标识由此重算。
    pub fn identities(&self) -> Vec<(String, String)> {
        self.actors
            .values()
            .map(|a| (a.id.clone(), a.home.clone().unwrap_or_default()))
            .collect()
    }

    fn validate(&self, world: &World) -> Result<()> {
        ensure!(
            (1..=SCHEMA_VERSION).contains(&self.schema_version),
            KernelError::snapshot(format!("不支持的世界存档版本 {}", self.schema_version))
        );
        ensure!(
            self.schema_version < 3 || self.inventory.is_some(),
            KernelError::snapshot("新存档缺少背包状态")
        );
        self.happenings.validate()?;
        ensure!(
            self.minutes.is_finite() && self.minutes >= 0.0,
            KernelError::snapshot("存档的世界时间无效")
        );
        ensure!(
            self.schema_version < 5 || self.weather.is_some(),
            KernelError::snapshot("v5 存档缺少天气状态")
        );
        if let Some(w) = &world.weather {
            w.validate(self.minutes)?;
        }
        self.validate_supplies(&world.topo)?;
        self.contents.validate_actors(&self.actors, self.minutes)?;
        world.validate_avatar(&self.actors)?;
        let mut names = std::collections::BTreeSet::new();
        for (id, a) in &self.actors {
            ensure!(
                names.insert(a.name.trim()),
                KernelError::snapshot(format!("存档中的村民 {id} 与他人重名"))
            );
            self.validate_actor(id, a, world)?;
        }
        crate::interactions::validation::validate(
            &self.interactions,
            &self.actors,
            world,
            self.minutes,
        )
    }

    /// 补给余量必须对应一个带有限补给的动作，且不超过初始量。
    fn validate_supplies(&self, topo: &Topology) -> Result<()> {
        for (key, remaining) in &self.supplies {
            let (prop, action_id) =
                split_supply_key(key).ok_or_else(|| KernelError::snapshot("资源状态编号无效"))?;
            let action = topo
                .prop(prop)
                .and_then(|p| {
                    p.verbs
                        .iter()
                        .filter_map(|v| v.action.as_ref())
                        .find(|a| a.id == action_id)
                })
                .or_else(|| {
                    self.placed_props
                        .get(prop)
                        .and_then(|p| p.definition.actions.iter().find(|a| a.id == action_id))
                });
            ensure!(
                action
                    .and_then(|a| a.supply.as_ref())
                    .is_some_and(|s| *remaining <= s.initial),
                KernelError::snapshot("资源剩余状态无效")
            );
        }
        Ok(())
    }

    fn validate_actor(&self, id: &str, a: &Actor, world: &World) -> Result<()> {
        ensure!(
            id == a.id,
            KernelError::snapshot(format!("存档中的村民 {id} 编号与键不一致"))
        );
        ensure!(
            a.home.as_deref().is_none_or(|h| world.topo.is_dwell(h)),
            KernelError::snapshot(format!("存档中的村民 {id} 的住宅不存在"))
        );
        ensure!(
            world.topo.locales.contains_key(&a.locus.locale)
                && world.topo.locales.contains_key(&a.current.locale),
            KernelError::snapshot(format!("存档中的村民 {id} 的位置或活动处所无效"))
        );
        ensure!(
            a.current.started_at.is_finite()
                && a.current.started_at <= self.minutes
                && a.current.participants.contains(id),
            KernelError::snapshot(format!("存档中的村民 {id} 的活动时间或参与者无效"))
        );
        a.needs.validate(self.minutes, &world.need_rules)?;
        ensure!(
            self.schema_version < 2 || a.needs.collapsed.is_none(),
            KernelError::snapshot("新存档不能包含旧失能字段")
        );
        crate::action_snapshot::validate(a, self.minutes)?;
        validate_locus(&a.locus, &world.topo)?;
        validate_activity(&a.current.kind, &world.topo)?;
        for item in &a.plan {
            validate_plan_item(item.intent(), &world.topo, &world.affordances)?;
        }
        Ok(())
    }
}

fn validate_locus(locus: &Locus, topo: &Topology) -> Result<()> {
    match &locus.at {
        At::Station { station } => ensure!(
            topo.station_in(station, &locus.locale),
            KernelError::snapshot("存档落脚点无效")
        ),
        At::Transit {
            elapsed,
            total,
            toward,
        } => ensure!(
            elapsed.is_finite()
                && total.is_finite()
                && *total > 0.0
                && (0.0..=*total).contains(elapsed)
                && topo.is_dwell(toward),
            KernelError::snapshot("存档移动位置无效")
        ),
        _ => {}
    }
    Ok(())
}

fn validate_activity(kind: &ActKind, topo: &Topology) -> Result<()> {
    match kind {
        ActKind::Placeholder { cond } | ActKind::Timed { cond } => check_cond(cond),
        ActKind::Travel { journey, stage } => validate_journey(journey, stage, topo),
    }
}

fn validate_journey(journey: &Journey, stage: &TravelStage, topo: &Topology) -> Result<()> {
    ensure!(
        topo.is_dwell(&journey.dest_locale)
            && topo.station_in(&journey.dest_station, &journey.dest_locale),
        KernelError::snapshot("存档行程目的地无效")
    );
    ensure!(
        journey.lead_wait.is_finite() && journey.lead_wait >= 0.0,
        KernelError::snapshot("存档穿门等待无效")
    );
    for w in &journey.walks {
        ensure!(
            topo.locales.contains_key(&w.edge) && topo.is_dwell(&w.toward),
            KernelError::snapshot("存档行程路段处所无效")
        );
        ensure!(
            w.total.is_finite()
                && w.total > 0.0
                && w.extra.is_finite()
                && w.extra >= 0.0
                && (0.0..=w.total).contains(&w.from_progress)
                && (0.0..=w.total).contains(&w.to_progress),
            KernelError::snapshot("存档行程路段进度无效")
        );
    }
    match stage {
        TravelStage::Lead { left } => ensure!(
            left.is_finite() && *left >= 0.0,
            KernelError::snapshot("存档穿门进度无效")
        ),
        TravelStage::Walking { idx, t } => ensure!(
            t.is_finite()
                && *t >= 0.0
                && journey.walks.get(*idx).is_some_and(|w| *t <= w.duration()),
            KernelError::snapshot("存档行走进度无效")
        ),
    }
    Ok(())
}

fn validate_plan_item(intent: &Intent, topo: &Topology, affordances: &Affordances) -> Result<()> {
    match intent {
        Intent::Goto { locale, station } => ensure!(
            topo.is_dwell(locale)
                && station
                    .as_ref()
                    .is_none_or(|id| topo.station_in(id, locale)),
            KernelError::snapshot("存档计划目的地无效")
        ),
        Intent::Stay { cond, .. } => check_cond(cond)?,
        Intent::Do { verb, cond, .. } => {
            ensure!(
                affordances.is_verb(verb),
                KernelError::snapshot(format!("存档计划动作 {verb} 已不存在"))
            );
            if let Some(cond) = cond {
                check_cond(cond)?;
            }
        }
    }
    Ok(())
}

fn check_cond(cond: &StopCond) -> Result<()> {
    ensure!(
        !matches!(cond, StopCond::Duration(m) if !m.is_finite() || *m < 0.0),
        KernelError::snapshot("存档活动剩余时长无效")
    );
    Ok(())
}
