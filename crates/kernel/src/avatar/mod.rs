//! 化身身份与生命周期。动作、交谈、背包的结算仍由原领域模块负责。
//! 名字、外观与读档规则在 Profile 上；World 只做进场、离场与改资料的编排。
mod commands;
mod geometry;
mod placement;
mod reach;
mod view;
pub use crate::possession::Control;
use crate::{
    actor::Actor,
    error::{KernelError, Result},
    topology::Topology,
    World,
};
pub(crate) use geometry::distance;
pub use geometry::{
    Area, Obstacle, Point, Portal, Spot, Surface, WalkMap, RADIUS, REACH, TALK_REACH,
};
use protocol::{Appearance, At, Locus, MemberKind};
pub(crate) use reach::Reach;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const ID: &str = "player_avatar";
/// 玩家操控的人（化身和附身的村民）走路是村民步速的几倍。村民的步速和模拟时间绑在一起，
/// 路线时长、到达时刻都按它算；玩家操控的人只求跟手，走多快不进入任何村民的计算。
pub const WALK_PACE: f64 = 2.5;
/// 按住奔跑键时是村民步速的几倍。
pub const RUN_PACE: f64 = 4.0;
/// 化身名字最多几个字；地图标记最多几个字符。
const NAME_MAX_CHARS: usize = 24;
const MARKER_MAX_CHARS: usize = 2;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Profile {
    pub appearance: Appearance,
    pub last_locus: Locus,
    #[serde(flatten)]
    pub control: Control,
}

impl Profile {
    /// 名字 1–24 字，没有控制字符。
    fn check_name(name: &str) -> Result<()> {
        ensure!(
            !name.trim().is_empty()
                && name.trim().chars().count() <= NAME_MAX_CHARS
                && !name.chars().any(char::is_control),
            KernelError::action("名字须为 1–24 字")
        );
        Ok(())
    }

    /// 标记至多两个字符，颜色是 #RRGGBB；捏过的长相也要合格。
    fn check_appearance(appearance: &Appearance) -> Result<()> {
        ensure!(
            appearance.marker.chars().count() <= MARKER_MAX_CHARS
                && protocol::is_hex_color(&appearance.color),
            KernelError::action("外观颜色须为六位十六进制颜色，标记至多两个字符")
        );
        if let Some(look) = &appearance.look {
            look.check().map_err(KernelError::action)?;
        }
        Ok(())
    }

    /// 读档校验：化身不是居民、离场时不占活动、在场与上次的位置合法、回执账本合法。
    /// 自由位置和位置上报写入时用同一条规则（`WalkMap::check_free_locus`）；落脚点要在所在区域里。
    fn validate(&self, a: &Actor, map: Option<&WalkMap>, topo: &Topology) -> Result<()> {
        ensure!(
            a.id == ID && a.home.is_none() && !a.actions.agent_controlled,
            KernelError::snapshot("化身不能注册为居民 Agent")
        );
        ensure!(
            a.present()
                || (a.plan.is_empty()
                    && a.current.action.is_none()
                    && a.current.interaction.is_none()),
            KernelError::snapshot("离场化身仍占用活动")
        );
        let map = map.ok_or_else(|| KernelError::snapshot("化身存档缺少行走地图"))?;
        for l in [&self.last_locus, &a.locus] {
            match l.at {
                At::Offstage => continue,
                At::Free { .. } => map.check_free_locus(l, topo)?,
                _ => {
                    let s = map
                        .station_locus(l)
                        .ok_or_else(|| KernelError::snapshot("化身位置无效"))?;
                    ensure!(
                        s.position.iter().all(|x| x.is_finite())
                            && map.locale_at(&s.space, s.position, &s.locale)
                                == Some(s.locale.as_str()),
                        KernelError::snapshot("化身位置不属于所在区域")
                    );
                }
            }
        }
        ensure!(
            self.control.receipts_valid(),
            KernelError::snapshot("化身回执账本无效")
        );
        Ok(())
    }
}

impl Actor {
    /// 第一次进入小镇的化身：没有住宅，不交给 Agent。
    fn new_avatar(name: &str, appearance: Appearance, spot: &Spot, now: f64) -> Self {
        let mut a = Actor::waiting(ID, name.trim(), &spot.locale, String::new(), now);
        a.kind = MemberKind::Avatar;
        a.avatar = Some(Profile {
            appearance,
            last_locus: spot.locus(),
            control: Control::default(),
        });
        a
    }
}

impl World {
    pub fn avatar(&self) -> Option<&Actor> {
        self.actors.values().find(|a| a.is_avatar())
    }
    pub fn avatar_enter(&mut self, name: &str, appearance: Appearance) -> Result<()> {
        ensure!(
            self.possessed().is_none(),
            KernelError::action("请先交还村民")
        );
        let map = self
            .walk_map
            .clone()
            .ok_or_else(|| KernelError::navigation("此地图暂不支持化身"))?;
        self.check_avatar_profile(name, &appearance)?;
        let origin = self.avatar_origin()?;
        let spot = map
            .station_locus(&origin)
            .ok_or_else(|| KernelError::navigation("化身保存的位置没有几何"))?;
        let spot = map
            .safe_near(&spot, &self.avatar_obstacles())
            .ok_or_else(|| KernelError::navigation("入口附近没有安全位置"))?;
        if self.avatar().is_none() {
            ensure!(
                !self.actors.contains_key(ID),
                KernelError::action("化身编号已被占用")
            );
            let a = Actor::new_avatar(name, appearance, &spot, self.minutes);
            self.actors.insert(ID.into(), a);
        }
        let now = self.minutes;
        let a = self.actor_mut(ID);
        a.locus = spot.locus();
        a.reset_idle(now, true);
        let a = &self.actors[ID];
        self.log(a.event_info(), format!("{} 来到小镇", a.name));
        Ok(())
    }
    /// 化身从哪里进场：离开过的回到上次的位置，第一次来从地图入口进来。
    fn avatar_origin(&self) -> Result<Locus> {
        if let Some(a) = self.avatar() {
            ensure!(!a.present(), KernelError::action("化身已经在场"));
            return Ok(a.avatar.as_ref().expect("化身有资料").last_locus.clone());
        }
        let entry = self
            .topo
            .spawn_candidates(None)?
            .into_iter()
            .next()
            .ok_or_else(|| KernelError::navigation("地图没有入口"))?;
        let station = entry
            .station
            .or_else(|| self.topo.default_station.get(&entry.locale).cloned())
            .ok_or_else(|| KernelError::navigation("入口没有落脚点"))?;
        Ok(Locus {
            at: At::Station { station },
            locale: entry.locale,
        })
    }
    /// 名字与外观的格式规则在 Profile 上；名字不能和居民重名要看人物表。
    fn check_avatar_profile(&self, name: &str, appearance: &Appearance) -> Result<()> {
        Profile::check_name(name)?;
        ensure!(
            !self
                .actors
                .values()
                .any(|a| !a.is_avatar() && a.name.trim() == name.trim()),
            KernelError::action("名字与居民重复")
        );
        Profile::check_appearance(appearance)
    }
    pub fn avatar_profile(&mut self, name: &str, appearance: Appearance) -> Result<()> {
        ensure!(
            self.possessed().is_none(),
            KernelError::action("附身不能修改村民身份")
        );
        self.check_avatar_profile(name, &appearance)?;
        let a = self
            .actors
            .get_mut(ID)
            .ok_or_else(|| KernelError::action("尚未创建化身"))?;
        a.name = name.trim().into();
        a.avatar.as_mut().expect("化身资料").appearance = appearance;
        Ok(())
    }
    pub fn avatar_leave(&mut self) -> Result<()> {
        let Some(a) = self.avatar() else {
            return Ok(());
        };
        if !a.present() {
            return Ok(());
        }
        let locus = a.locus.clone();
        let name = a.name.clone();
        self.end_walks_of(ID, "离开了小镇");
        self.interrupt_actions(ID, "化身离开小镇");
        let now = self.minutes;
        let a = self.actor_mut(ID);
        a.avatar.as_mut().expect("化身资料").last_locus = locus;
        a.locus.at = At::Offstage;
        a.reset_idle(now, true);
        let info = a.event_info();
        self.log(info, format!("{name} 离开小镇"));
        Ok(())
    }
    pub fn avatar_stop(&mut self) {
        let id = self.player_id().to_owned();
        if self.actors.contains_key(&id) {
            self.interrupt_actions(&id, "停止当前活动");
            let now = self.minutes;
            self.actor_mut(&id).reset_idle(now, false);
        }
    }
    pub fn avatar_control_epoch(&mut self, epoch: String) {
        if let Some(p) = self.player_control_mut() {
            p.reset(epoch);
        }
    }
    pub fn avatar_remember(&mut self, sequence: u64, receipt: serde_json::Value) {
        if let Some(p) = self.player_control_mut() {
            p.remember(sequence, receipt);
        }
    }
    pub(crate) fn validate_avatar(&self, actors: &BTreeMap<String, Actor>) -> Result<()> {
        ensure!(
            actors.values().filter(|a| a.is_avatar()).count() <= 1,
            KernelError::snapshot("世界只能有一个化身")
        );
        ensure!(
            actors
                .values()
                .filter(|a| a.possession.is_some() || (a.is_avatar() && a.present()))
                .count()
                <= 1,
            KernelError::snapshot("玩家控制目标不能重复")
        );
        for a in actors.values() {
            ensure!(
                a.is_avatar() == a.avatar.is_some(),
                KernelError::snapshot("化身身份与资料不一致")
            );
            if let Some(p) = &a.avatar {
                p.validate(a, self.walk_map.as_deref(), &self.topo)?;
            }
            self.validate_player_actor(a)?;
        }
        Ok(())
    }
}
