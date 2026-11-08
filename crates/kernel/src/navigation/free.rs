//! 从玩家留下的自由位置步行接回拓扑站点。只在同一行走空间内寻路，不穿门或瞬移；屋里没有
//! 站点时走到门内一侧，就算站在门外画着的到达点上（见 `WalkMap::inside_door`）。
//! 寻路和沿路线推进是行走地图与路线自己的规则；World 只取人物位置、障碍，再装上活动。
//!
//! 站的地方本身走不通（贴着可走地面的边、挨着道具）时，先迈到附近最近的走得通的一点再找路，
//! 迈出去的那一小步不查通不通（`nearest_clear`）。大逃杀第二局里有人站在新放的道具跟前、
//! 落在可走格子外面，之后每个动作都被拒，三个人卡到渴死。
use crate::{
    avatar::{distance, Obstacle, Point, Spot, WalkMap, RADIUS},
    error::{KernelError, Result},
    topology::Topology,
    World,
};
use std::cmp::Reverse;
use std::collections::{BTreeMap, BinaryHeap};

/// 网格寻路最多展开的格点数。
const MAX_EXPANSIONS: usize = 20_000;
/// 读档时接续路线点数的上限：寻路展开的格点数上限，加上起点和终点。
pub(crate) const MAX_WALK_POINTS: usize = MAX_EXPANSIONS + 2;
/// 检查一段路线是否通畅时的采样步长（米）。
const SEGMENT_STEP: f64 = 0.1;
/// 网格寻路的格距（米）。
const GRID_STEP: f64 = 0.5;
/// 只朝最近的这么多个站点寻路。
const NEAREST_GOALS: usize = 16;
/// 网格点离目标站点不超过这个距离（米）且连线通畅时，直接走过去。
const GOAL_REACH: f64 = 2.0;
/// 站的地方走不通时，往外找走得通的一点：每圈往外多这么多米，最远找到这么远。
const ESCAPE_STEP: f64 = 0.25;
const ESCAPE_REACH: f64 = 3.0;
/// 网格代价：直走一格 1000、斜走一格 1414（约 1000 × √2），即每米 2000；
/// 启发值按同一比例把到最近目标的直线距离折成代价。
const STRAIGHT_COST: u64 = 1000;
const DIAGONAL_COST: u64 = 1414;
const COST_PER_METRE: f64 = STRAIGHT_COST as f64 / GRID_STEP;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FreeWalk {
    pub station: String,
    pub points: Vec<Spot>,
    pub next: usize,
}

type Cell = (i32, i32);

impl WalkMap {
    /// 两点之间整段通畅：同一空间，按采样步长逐点检查人物半径内没有阻挡。
    pub(crate) fn segment_clear(&self, a: &Spot, b: &Spot, obstacles: &[Obstacle]) -> bool {
        if a.space != b.space {
            return false;
        }
        let steps = (distance(a.position, b.position) / SEGMENT_STEP)
            .ceil()
            .max(1.) as usize;
        (1..=steps).all(|i| {
            let t = i as f64 / steps as f64;
            self.clear(
                &a.space,
                [
                    a.position[0] + (b.position[0] - a.position[0]) * t,
                    a.position[1] + (b.position[1] - a.position[1]) * t,
                ],
                obstacles,
                RADIUS,
            )
        })
    }

    /// 离 start 最近的一个走得通的点（同一空间、人物半径内没有阻挡、在某个区域里），由近到远一圈圈找，
    /// 最远 ESCAPE_REACH 米；`same_locale` 时只要和 start 同一处所的点。找不到时为 None。
    pub(crate) fn nearest_clear(
        &self,
        start: &Spot,
        obstacles: &[Obstacle],
        same_locale: bool,
    ) -> Option<Spot> {
        let mut r = ESCAPE_STEP;
        while r <= ESCAPE_REACH + 1e-9 {
            let n = ((std::f64::consts::TAU * r / ESCAPE_STEP).ceil() as usize).max(8);
            for i in 0..n {
                let a = i as f64 * std::f64::consts::TAU / n as f64;
                let p = [
                    start.position[0] + r * a.cos(),
                    start.position[1] + r * a.sin(),
                ];
                if !self.clear(&start.space, p, obstacles, RADIUS) {
                    continue;
                }
                match self.locale_at(&start.space, p, &start.locale) {
                    Some(l) if !same_locale || l == start.locale => {
                        return Some(Spot {
                            locale: l.into(),
                            space: start.space.clone(),
                            position: p,
                        })
                    }
                    _ => {}
                }
            }
            r += ESCAPE_STEP;
        }
        None
    }

    /// 可以接回的站点：同一空间、拓扑里也有（`known`）、本身不被挡住；同一处所里有就只取
    /// 同一处所的。按距离从近到远排好。
    fn station_goals<'a>(
        &'a self,
        start: &Spot,
        obstacles: &[Obstacle],
        known: impl Fn(&str) -> bool,
    ) -> Vec<(&'a String, &'a Spot)> {
        let mut goals: Vec<_> = self
            .stations
            .iter()
            .filter(|(id, s)| {
                s.space == start.space
                    && known(id)
                    && self.clear(&s.space, s.position, obstacles, RADIUS)
            })
            .collect();
        if goals.iter().any(|(_, s)| s.locale == start.locale) {
            goals.retain(|(_, s)| s.locale == start.locale);
        }
        goals.sort_by(|a, b| {
            distance(start.position, a.1.position)
                .total_cmp(&distance(start.position, b.1.position))
        });
        goals.truncate(NEAREST_GOALS);
        goals
    }

    /// 屋里没有站点时接回的地方：门外画着的到达点，换到门内那一侧（`inside_door`，到达点上的人
    /// 本来就画在那里）。跟着别人进了没摆道具的屋子停在门里的人，从这里接回路网（回声湾的灯塔：
    /// 之前每次想走都报「当前空间没有可接续的导航站点」）。按距离从近到远排好。
    fn door_goals(
        &self,
        start: &Spot,
        obstacles: &[Obstacle],
        known: impl Fn(&str) -> bool,
    ) -> Vec<(String, Spot)> {
        let mut goals: Vec<_> = self
            .stations
            .iter()
            .filter(|(id, s)| s.space != start.space && known(id))
            .map(|(id, s)| (id.clone(), self.inside_door(s)))
            .filter(|(_, inside)| {
                inside.space == start.space
                    && self.clear(&inside.space, inside.position, obstacles, RADIUS)
            })
            .collect();
        goals.sort_by(|a, b| {
            distance(start.position, a.1.position)
                .total_cmp(&distance(start.position, b.1.position))
        });
        goals.truncate(NEAREST_GOALS);
        goals
    }

    /// 从 start 走回最近能到的站点：通常直线可达；复杂家具之间用网格寻路。
    fn route_to_station(
        &self,
        start: Spot,
        goals: &[(&String, &Spot)],
        obstacles: &[Obstacle],
    ) -> Option<FreeWalk> {
        for (id, goal) in goals {
            if self.segment_clear(&start, goal, obstacles) {
                return Some(FreeWalk {
                    station: (*id).clone(),
                    points: vec![start, (*goal).clone()],
                    next: 1,
                });
            }
        }
        self.grid_route(start, goals, obstacles)
    }

    /// 以起点为原点的网格 A* 寻路，最多展开 MAX_EXPANSIONS 个格点。
    fn grid_route(
        &self,
        start: Spot,
        goals: &[(&String, &Spot)],
        obstacles: &[Obstacle],
    ) -> Option<FreeWalk> {
        let point = |(x, y): Cell| -> Point {
            [
                start.position[0] + f64::from(x) * GRID_STEP,
                start.position[1] + f64::from(y) * GRID_STEP,
            ]
        };
        let spot = |cell: Cell| Spot {
            position: point(cell),
            ..start.clone()
        };
        let heuristic = |cell: Cell| -> u64 {
            let nearest = goals
                .iter()
                .map(|(_, g)| distance(point(cell), g.position))
                .fold(f64::INFINITY, f64::min);
            (nearest * COST_PER_METRE) as u64
        };
        let mut queue = BinaryHeap::from([Reverse((heuristic((0, 0)), 0u64, (0, 0)))]);
        let mut best = BTreeMap::from([((0, 0), 0u64)]);
        let mut parents: BTreeMap<Cell, Cell> = BTreeMap::new();
        let mut expanded = 0;
        while let Some(Reverse((_, cost, cell))) = queue.pop() {
            if best[&cell] != cost {
                continue;
            }
            expanded += 1;
            if expanded > MAX_EXPANSIONS {
                break;
            }
            let here = spot(cell);
            if let Some((id, goal)) = goals.iter().find(|(_, goal)| {
                distance(here.position, goal.position) <= GOAL_REACH
                    && self.segment_clear(&here, goal, obstacles)
            }) {
                let mut points = vec![(*goal).clone(), here];
                let mut cursor = cell;
                while let Some(parent) = parents.get(&cursor) {
                    cursor = *parent;
                    points.push(spot(cursor));
                }
                points.reverse();
                return Some(FreeWalk {
                    station: (*id).clone(),
                    points,
                    next: 1,
                });
            }
            for (next, step) in neighbours(cell) {
                let n = cost + step;
                if best.get(&next).is_some_and(|old| *old <= n)
                    || !self.segment_clear(&here, &spot(next), obstacles)
                {
                    continue;
                }
                best.insert(next, n);
                parents.insert(next, cell);
                queue.push(Reverse((n + heuristic(next), n, next)));
            }
        }
        None
    }
}

/// 八个相邻格点和走过去的代价。
fn neighbours((x, y): Cell) -> impl Iterator<Item = (Cell, u64)> {
    (-1i32..=1)
        .flat_map(move |dx| (-1i32..=1).map(move |dy| (dx, dy)))
        .filter(|&(dx, dy)| dx != 0 || dy != 0)
        .map(move |(dx, dy)| {
            let cost = if dx != 0 && dy != 0 {
                DIAGONAL_COST
            } else {
                STRAIGHT_COST
            };
            ((x + dx, y + dy), cost)
        })
}

impl FreeWalk {
    /// 路线总长（米）。
    pub(crate) fn length(&self) -> f64 {
        self.points
            .windows(2)
            .map(|p| distance(p[0].position, p[1].position))
            .sum()
    }

    /// 从 here 沿路线走 metres 米，返回走到的位置；路线被挡住时报错，调用方保留原位置。
    pub(crate) fn advance(
        &mut self,
        map: &WalkMap,
        mut here: Spot,
        mut metres: f64,
        obstacles: &[Obstacle],
    ) -> Result<Spot> {
        while self.next < self.points.len() && metres > 1e-9 {
            let dest = &self.points[self.next];
            let d = distance(here.position, dest.position);
            let t = if d < 1e-9 { 1. } else { (metres / d).min(1.) };
            let p = [
                here.position[0] + (dest.position[0] - here.position[0]) * t,
                here.position[1] + (dest.position[1] - here.position[1]) * t,
            ];
            let target = Spot {
                locale: map
                    .locale_at(&here.space, p, &here.locale)
                    .unwrap_or(&here.locale)
                    .into(),
                space: here.space.clone(),
                position: p,
            };
            // 站的地方本身走不通时，往外迈的这一步不查（见 nearest_clear）
            ensure!(
                map.segment_clear(&here, &target, obstacles)
                    || !map.clear(&here.space, here.position, obstacles, RADIUS),
                KernelError::navigation("接续路线被阻挡，保留当前位置")
            );
            here = target;
            metres -= d * t;
            if t >= 1. {
                self.next += 1;
            } else {
                break;
            }
        }
        Ok(here)
    }

    /// 读档校验：点数与进度合法，终点就是拓扑与行走地图里同一个站点（或它门内的那一侧），
    /// 全程在同一空间的区域内。进度 0 是还在往第一个点走（从走不通的地方迈出来的路线）。
    pub(crate) fn validate(&self, topo: &Topology, map: Option<&WalkMap>) -> Result<()> {
        ensure!(
            self.points.len() >= 2
                && self.points.len() <= MAX_WALK_POINTS
                && self.next <= self.points.len(),
            KernelError::snapshot("接续行走进度无效")
        );
        let last = self.points.last().expect("上面已确认至少两个点");
        ensure!(
            topo.station_in(&self.station, &last.locale),
            KernelError::snapshot("接续站点无效")
        );
        ensure!(
            map.and_then(|m| m.stations.get(&self.station).map(|s| (m, s)))
                .is_some_and(|(m, s)| [s.clone(), m.inside_door(s)]
                    .iter()
                    .any(|end| end.space == last.space && end.position == last.position)),
            KernelError::snapshot("接续路线终点与站点不一致")
        );
        for p in &self.points {
            ensure!(
                p.space == last.space,
                KernelError::snapshot("接续路线不能跨空间")
            );
            ensure!(
                p.position.iter().all(|v| v.is_finite())
                    && map.is_some_and(|m| m.locale_at(&p.space, p.position, &p.locale).is_some()),
                KernelError::snapshot("接续路线无效")
            );
        }
        Ok(())
    }
}

impl World {
    /// 人物从当前自由位置走回最近能到的拓扑站点的路线。
    pub(crate) fn free_route(&self, actor: &str) -> Result<FreeWalk> {
        let map = self
            .walk_map
            .as_ref()
            .ok_or_else(|| KernelError::navigation("缺少行走地图"))?;
        let start = self
            .actor_spot(actor)
            .ok_or_else(|| KernelError::navigation("自由位置无效"))?;
        let obstacles = self.avatar_obstacles();
        let known = |id: &str| self.topo.stations.contains_key(id);
        let mut goals = map.station_goals(&start, &obstacles, known);
        let doors = if goals.is_empty() {
            map.door_goals(&start, &obstacles, known)
        } else {
            Vec::new()
        };
        goals.extend(doors.iter().map(|(id, spot)| (id, spot)));
        ensure!(
            !goals.is_empty(),
            KernelError::navigation("当前空间没有可接续的导航站点")
        );
        map.route_to_station(start.clone(), &goals, &obstacles)
            .or_else(|| {
                // 站的地方本身走不通：先迈到最近走得通的一点，再从那里找路。路线从那一点开始，
                // 进度停在 0（先走到第一个点）；站的地方不进路线，存档里的路线点都在区域里。
                if map.clear(&start.space, start.position, &obstacles, RADIUS) {
                    return None;
                }
                let step = map.nearest_clear(&start, &obstacles, false)?;
                let mut walk = map.route_to_station(step, &goals, &obstacles)?;
                walk.next = 0;
                Some(walk)
            })
            .ok_or_else(|| KernelError::navigation("当前位置无法接回导航，请移到通路或门口再交还"))
    }

    pub(crate) fn start_free_approach(
        &mut self,
        actor: &str,
        now: f64,
        queued: crate::action_state::QueuedAction,
    ) -> Result<()> {
        self.actors[actor].needs.check_action(true, None)?;
        let route = self.free_route(actor)?;
        let minutes = route.length() / self.walk_map.as_ref().unwrap().metres_per_minute;
        let (intent, binding) = queued.into_parts();
        let a = self.actor_mut(actor);
        a.current = crate::world::Activity::new(
            actor,
            now,
            a.locus.locale.clone(),
            crate::intent::BuiltinVerb::Goto.label(),
            crate::world::ActKind::Timed {
                cond: crate::intent::StopCond::Duration(minutes),
            },
        );
        a.current.pending = Some(intent);
        a.current.action = binding;
        a.free_walk = Some(route);
        Ok(())
    }

    /// 接续行走推进 minutes 分钟；被挡住时报错，位置不变。
    pub(crate) fn advance_free_walk(&mut self, actor: &str, minutes: f64) -> Result<()> {
        if self.actors[actor].free_walk.is_none() {
            return Ok(());
        }
        let map = self
            .walk_map
            .clone()
            .ok_or_else(|| KernelError::navigation("缺少行走地图"))?;
        let obstacles = self.avatar_obstacles();
        let here = self
            .actor_spot(actor)
            .ok_or_else(|| KernelError::navigation("自由位置无效"))?;
        let a = self.actor_mut(actor);
        let mut route = a.free_walk.take().expect("上面已确认有接续路线");
        let reached = route.advance(&map, here, minutes * map.metres_per_minute, &obstacles);
        a.free_walk = Some(route);
        a.locus = reached?.locus();
        Ok(())
    }
}
