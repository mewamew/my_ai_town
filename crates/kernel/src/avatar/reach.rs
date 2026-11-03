//! 化身与附身者的可达判断：在行走地图上够不够得着人和道具。
//! 几何规则在 WalkMap::reaches；这里取人物位置和障碍。一次视图或命令里障碍表只建一次。
use super::*;
use std::cell::OnceCell;

/// 运行时放在二维地图上的道具占地的半边长（米），与默认地图的道具图标一致。
const RUNTIME_PROP_HALF: f64 = 0.3;

impl World {
    /// 当前挡路的东西：地图自带的障碍里仍在地图上的道具与建筑、运行时放置的空间道具、
    /// 二维地图上运行时放置的道具。被拿走或存起的道具不挡路。
    pub(crate) fn avatar_obstacles(&self) -> Vec<Obstacle> {
        let Some(map) = &self.walk_map else {
            return vec![];
        };
        let standing = |id: &str| {
            self.inventory.on_map(&self.props, id) && self.inventory.location(id).is_none()
        };
        let mut result: Vec<_> = map
            .obstacles
            .iter()
            .filter(|o| self.topo.prop(&o.id).is_none() || standing(&o.id))
            .cloned()
            .collect();
        if let Some(s) = &self.topo.navigation {
            for v in s.overrides.values().filter(|v| standing(&v.prop.id)) {
                let p = &v.prop;
                result.push(Obstacle {
                    id: p.id.clone(),
                    spot: Spot {
                        locale: p.locale.clone(),
                        space: map.space_of(&p.locale).into(),
                        position: [p.position[0], p.position[2]],
                    },
                    half: [p.footprint[0] / 2., p.footprint[1] / 2.],
                });
            }
        }
        for (id, spot) in &self.props.walk_positions {
            if standing(id) {
                result.push(Obstacle {
                    id: id.clone(),
                    spot: spot.clone(),
                    half: [RUNTIME_PROP_HALF, RUNTIME_PROP_HALF],
                });
            }
        }
        result
    }
    pub(crate) fn actor_spot(&self, id: &str) -> Option<Spot> {
        let a = self.actors.get(id)?;
        let map = self.walk_map.as_ref()?;
        map.station_locus(&a.locus)
    }
    /// 道具在行走地图上的操作位置：落地的在落地点，空间道具在操作锚点，其余在地图标记处。
    pub(crate) fn avatar_prop_spot(&self, id: &str) -> Option<Spot> {
        let p = self.topo.prop(id)?;
        let map = self.walk_map.as_ref()?;
        if let Some(crate::inventory::Location::Ground { station, .. }) =
            self.inventory.location(id)
        {
            return map.stations.get(station).cloned();
        }
        if let Some(s) = self.topo.navigation.as_ref().and_then(|s| s.prop(id)) {
            return Some(Spot {
                locale: p.locale.clone(),
                space: map.space_of(&p.locale).into(),
                position: [s.anchor[0], s.anchor[2]],
            });
        }
        self.props
            .walk_positions
            .get(id)
            .or_else(|| map.props.get(id))
            .cloned()
    }
}

/// 同一次视图或命令里的可达判断。障碍表第一次用到时才建，之后复用。
pub(crate) struct Reach<'a> {
    w: &'a World,
    obstacles: OnceCell<Vec<Obstacle>>,
}

impl<'a> Reach<'a> {
    pub(crate) fn new(w: &'a World) -> Self {
        Self {
            w,
            obstacles: OnceCell::new(),
        }
    }

    /// actor 够不够得着 spot；ignored 是目标道具自己，不算遮挡。
    fn reaches(&self, actor: &str, spot: &Spot, limit: f64, ignored: Option<&str>) -> bool {
        let (Some(map), Some(from)) = (&self.w.walk_map, self.w.actor_spot(actor)) else {
            return false;
        };
        map.reaches(&from, spot, limit, ignored, || {
            self.obstacles.get_or_init(|| self.w.avatar_obstacles())
        })
    }

    /// 玩家控制的人操作道具前要走近；随身物品和居民不受限。
    pub(crate) fn prop(&self, actor: &str, prop: &str) -> Result<()> {
        let w = self.w;
        if !w.actors.get(actor).is_some_and(|a| a.player_controlled()) {
            return Ok(());
        }
        ensure!(
            w.actors[actor].present(),
            KernelError::action("化身已经离场")
        );
        if w.inventory.carried_by(prop, actor) {
            return Ok(());
        }
        let spot = w
            .avatar_prop_spot(prop)
            .ok_or_else(|| KernelError::navigation("此道具没有可达的操作位置"))?;
        ensure!(
            self.reaches(actor, &spot, REACH, Some(prop)),
            KernelError::action("请走近道具再操作")
        );
        Ok(())
    }

    /// 说话时这个人在哪：落脚点或自由位置；走在路段上的按进度算（见 WalkMap::transit_spot）。
    pub(crate) fn talk_spot(&self, id: &str) -> Option<Spot> {
        let w = self.w;
        w.actor_spot(id)
            .or_else(|| w.walk_map.as_ref()?.transit_spot(&w.actors.get(id)?.locus))
    }

    /// 有一方是玩家控制时，双方要在交谈距离内且中间没有隔墙。只看距离和遮挡，不管是不是同一个处所，
    /// 走在路上的人也算：处所的分界在画面上看不出来（交谈开始时化身再挪进对方的处所，见 settle_pair_place）。
    pub(crate) fn pair(&self, a: &str, b: &str) -> Result<()> {
        let w = self.w;
        let first = w
            .actors
            .get(a)
            .ok_or_else(|| KernelError::NoSuchActor(a.into()))?;
        let second = w
            .actors
            .get(b)
            .ok_or_else(|| KernelError::NoSuchActor(b.into()))?;
        if !first.player_controlled() && !second.player_controlled() {
            return Ok(());
        }
        let spot = self
            .talk_spot(b)
            .ok_or_else(|| KernelError::interaction("对方不在场"))?;
        ensure!(
            self.talks_to(a, &spot),
            KernelError::interaction("请走到对方附近，不能隔墙交谈")
        );
        Ok(())
    }

    fn talks_to(&self, a: &str, spot: &Spot) -> bool {
        let (Some(map), Some(from)) = (&self.w.walk_map, self.talk_spot(a)) else {
            return false;
        };
        map.within_talk(&from, spot, TALK_REACH, || {
            self.obstacles.get_or_init(|| self.w.avatar_obstacles())
        })
    }

    /// 同一空间里两人隔多远；不在同一空间（隔着墙）为空。
    pub(crate) fn gap(&self, a: &str, b: &str) -> Option<f64> {
        let (from, to) = (self.talk_spot(a)?, self.talk_spot(b)?);
        (from.space == to.space).then(|| distance(from.position, to.position))
    }

    /// 玩家放下物品的落脚点：够得着的站点里最近的一个。
    pub(crate) fn drop_station(&self) -> Option<String> {
        let actor = self.w.player_id();
        let map = self.w.walk_map.as_ref()?;
        let here = self.w.actor_spot(actor)?;
        map.stations
            .iter()
            .filter(|(_, s)| self.reaches(actor, s, REACH, None))
            .min_by(|(_, a), (_, b)| {
                distance(here.position, a.position).total_cmp(&distance(here.position, b.position))
            })
            .map(|(id, _)| id.clone())
    }
}
