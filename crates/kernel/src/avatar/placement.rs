//! 默认二维地图的运行时道具位置。已有布局只迁入一次，随后与世界共同保存。
use super::*;
use protocol::PlaceNear;

/// 矩形区域里每边取几个候选点（等分成多一份，边上不放）。
const RECT_CANDIDATES: u32 = 12;
/// 放置点周围要空出的半径（米），与运行时道具的占地一致。
const CLEARANCE: f64 = 0.3;
/// 离门口和人物至少多远（米）。
const KEEP_AWAY: f64 = 1.;
/// 离已有道具至少多远（米）；满足时取离已有道具最远的点。
const MIN_SPACING: f64 = 0.8;

impl WalkMap {
    /// 在处所的区域里给新道具找位置：不挡路、不贴门口和人，离已有道具至少 MIN_SPACING；
    /// 玩家点了同一空间里的位置就取离它最近的，否则离已有道具尽量远。
    /// `occupied` 是已有道具的位置，`people` 是人物的位置。
    fn plan_prop_spot<'s>(
        &'s self,
        locale: &str,
        occupied: impl Iterator<Item = &'s Spot>,
        people: &[Spot],
        obstacles: &[Obstacle],
        near: Option<&PlaceNear>,
    ) -> Option<Spot> {
        let surface = self.surfaces.iter().find(|s| s.locale == locale)?;
        let space = &surface.space;
        let occupied: Vec<_> = self
            .props
            .values()
            .chain(occupied)
            .filter(|p| p.space == *space)
            .collect();
        let doors: Vec<_> = self.portals.iter().map(|d| &d.from).collect();
        let people: Vec<_> = people.iter().collect();
        let beside = |spots: &[&Spot], p: Point| {
            spots
                .iter()
                .any(|s| s.space == *space && distance(s.position, p) < KEEP_AWAY)
        };
        let wanted = near.filter(|n| n.space == *space).map(|n| n.position);
        let mut best: Option<(f64, Point)> = None;
        for p in candidates(&surface.area)? {
            if !self.clear(space, p, obstacles, CLEARANCE)
                || beside(&doors, p)
                || beside(&people, p)
            {
                continue;
            }
            let d = occupied
                .iter()
                .map(|q| distance(p, q.position))
                .fold(f64::INFINITY, f64::min);
            let score = wanted.map_or(d, |w| -distance(p, w));
            if d >= MIN_SPACING && best.is_none_or(|(s, _)| score > s) {
                best = Some((score, p));
            }
        }
        best.map(|(_, position)| Spot {
            locale: locale.into(),
            space: space.clone(),
            position,
        })
    }
}

/// 区域里的候选点：矩形取等分网格，格子取每格中心；走廊不放道具。
fn candidates(area: &Area) -> Option<Vec<Point>> {
    let n = RECT_CANDIDATES;
    match area {
        Area::Rect { min, max } => Some(
            (1..=n)
                .flat_map(|r| {
                    (1..=n).map(move |c| {
                        [
                            min[0] + (max[0] - min[0]) * f64::from(c) / f64::from(n + 1),
                            min[1] + (max[1] - min[1]) * f64::from(r) / f64::from(n + 1),
                        ]
                    })
                })
                .collect(),
        ),
        Area::Cells { size, cells } => Some(
            cells
                .iter()
                .map(|(x, y)| [(f64::from(*x) + 0.5) * size, (f64::from(*y) + 0.5) * size])
                .collect(),
        ),
        Area::Corridor { .. } => None,
    }
}

impl World {
    pub fn needs_walk_prop_layout(&self) -> bool {
        self.topo.navigation.is_none()
            && self.walk_map.is_some()
            && self
                .props
                .placed
                .keys()
                .any(|id| self.lacks_walk_position(id))
    }

    /// 自己立在地上、还没有二维位置的运行时道具。放在落脚点、带在身上或存进容器的东西跟着所在处走，
    /// 不要二维位置；也不能补给它们，否则地点里没有空位时读档就失败了。
    fn lacks_walk_position(&self, id: &str) -> bool {
        !self.props.walk_positions.contains_key(id)
            && !self.props.is_removed(id)
            && self.inventory.location(id).is_none()
    }

    /// host 在恢复完成后传入旧 prop-layout；内核不读取文件，也不接受客户端坐标。
    pub fn restore_walk_props(&mut self, legacy: BTreeMap<String, (String, Point)>) -> Result<()> {
        if self.topo.navigation.is_some() || self.walk_map.is_none() {
            return Ok(());
        }
        let mut positions = self.props.walk_positions.clone();
        for (id, placement) in &self.props.placed {
            if !self.lacks_walk_position(id) {
                continue;
            }
            let spot = legacy
                .get(id)
                .map(|(space, position)| Spot {
                    locale: placement.instance.locale.clone(),
                    space: space.clone(),
                    position: *position,
                })
                .or_else(|| self.plan_walk_prop(&placement.instance.locale, &positions, None));
            if let Some(spot) = spot {
                positions.insert(id.clone(), spot);
            } else {
                return Err(KernelError::navigation("没有可用的二维道具位置"));
            }
        }
        self.validate_walk_props(&positions)?;
        self.props.walk_positions = positions;
        Ok(())
    }

    pub(crate) fn validate_walk_props(&self, positions: &BTreeMap<String, Spot>) -> Result<()> {
        for (id, p) in positions {
            let locale = self
                .props
                .placed
                .get(id)
                .map(|p| p.instance.locale.as_str());
            ensure!(
                locale == Some(p.locale.as_str())
                    && p.position.iter().all(|v| v.is_finite())
                    && self
                        .walk_map
                        .as_ref()
                        .is_some_and(|m| m.locale_at(&p.space, p.position, &p.locale)
                            == Some(p.locale.as_str())),
                KernelError::snapshot("二维道具位置与地图或实例不匹配")
            );
        }
        Ok(())
    }

    /// 新道具在二维地图上的位置：人物位置、障碍由世界给出，选点规则在 WalkMap。
    pub(crate) fn plan_walk_prop(
        &self,
        locale: &str,
        positions: &BTreeMap<String, Spot>,
        near: Option<&PlaceNear>,
    ) -> Option<Spot> {
        let map = self.walk_map.as_ref()?;
        let people: Vec<_> = self
            .actors
            .values()
            .filter_map(|a| map.station_locus(&a.locus))
            .collect();
        map.plan_prop_spot(
            locale,
            positions.values(),
            &people,
            &self.avatar_obstacles(),
            near,
        )
    }
}
