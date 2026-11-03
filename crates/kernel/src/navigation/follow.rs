//! 跟着人走：沿带路人走过的足迹走，保持几步距离；足迹换了空间（带路人进出门）就在那里穿过去。
//! 足迹由同行模块每拍记下，这里只管沿足迹推进一个人。足迹不存档，读档后从带路人当时的位置重新记。
use crate::avatar::{distance, Obstacle, Point, Spot, WalkMap, RADIUS};
use std::cmp::Reverse;
use std::collections::{BTreeMap, BinaryHeap};

/// 带路人每走这么远（米）记一个足迹点。
pub(crate) const CRUMB_SPACING: f64 = 0.3;
/// 绕路寻路的格距（米）与最多展开的格点数。
const GRID_STEP: f64 = 0.5;
const MAX_EXPANSIONS: usize = 3_000;
/// 绕路走到离足迹点这么近（米）就算回到足迹上。
const DETOUR_REACH: f64 = 0.6;
/// 足迹点被挡住、又找不到绕行路线时，离得这么近（米）就直接站过去，免得卡死在家具边。
const HOP_LIMIT: f64 = 2.0;

/// 一个跟随者在足迹上的进度：下一个要走到的足迹点（绝对序号），以及绕开障碍时临时的路线。
#[derive(Debug, Clone, Default)]
pub(crate) struct Follower {
    pub next: usize,
    detour: Vec<Point>,
}

/// 带路人的足迹：points[0] 的绝对序号是 base；跟随者都走过的旧点会裁掉。
#[derive(Debug, Clone, Default)]
pub(crate) struct Trail {
    pub base: usize,
    pub points: Vec<Spot>,
}

impl Trail {
    /// 记下带路人此刻的位置：离上一个点够远或换了空间才记。
    pub(crate) fn mark(&mut self, at: Spot) {
        let fresh = self.points.last().is_none_or(|last| {
            last.space != at.space || distance(last.position, at.position) >= CRUMB_SPACING
        });
        if fresh {
            self.points.push(at);
        }
    }

    fn get(&self, index: usize) -> Option<&Spot> {
        index
            .checked_sub(self.base)
            .and_then(|i| self.points.get(i))
    }

    /// 从 here 沿足迹（从第 next 个点起）走到带路人还有多远。前面还有一道门没穿过时算无穷远：
    /// 带路人进了门，跟随的人要跟着穿过去，不能停在门外。
    fn length_from(&self, here: &Spot, next: usize) -> f64 {
        let mut last = here.clone();
        let mut total = 0.;
        for i in next.max(self.base)..self.base + self.points.len() {
            let p = &self.points[i - self.base];
            if p.space != last.space {
                return f64::INFINITY;
            }
            total += distance(last.position, p.position);
            last = p.clone();
        }
        total
    }

    /// 裁掉所有跟随者都走过的旧点。
    pub(crate) fn trim(&mut self, keep_from: usize) {
        let cut = keep_from
            .saturating_sub(self.base)
            .min(self.points.len().saturating_sub(1));
        self.points.drain(..cut);
        self.base += cut;
    }
}

/// 一次推进的结果：新位置（没动为空），以及是否被挡住走不动。
pub(crate) struct Step {
    pub moved: Option<Spot>,
    pub stuck: bool,
}

impl WalkMap {
    /// 沿足迹把跟随者往前推 metres 米，停在离带路人 gap 米（按足迹长度算）的地方。
    pub(crate) fn follow_trail(
        &self,
        here: &Spot,
        trail: &Trail,
        follower: &mut Follower,
        gap: f64,
        metres: f64,
        obstacles: &[Obstacle],
    ) -> Step {
        // 起身时身下那件家具（坐着的椅子、躺着的床，占地盖住站位）不算挡路，不然一步也迈不出去
        let obstacles: Vec<Obstacle> = obstacles
            .iter()
            .filter(|o| !o.covers(here))
            .cloned()
            .collect();
        let obstacles = obstacles.as_slice();
        let mut at = here.clone();
        let mut budget = metres;
        let mut moved = false;
        let mut stuck = false;
        follower.next = follower.next.max(trail.base);
        while budget > 1e-6 {
            let left = trail.length_from(&at, follower.next) - gap;
            if left <= 1e-6 {
                break;
            }
            let Some(target) = trail.get(follower.next).cloned() else {
                break;
            };
            if target.space != at.space {
                // 带路人在这里进出了门：跟着穿过去，落在门那边站得下的地方。
                match self.safe_near(&target, obstacles) {
                    Some(spot) => {
                        at = spot;
                        follower.next += 1;
                        follower.detour.clear();
                        moved = true;
                        continue;
                    }
                    None => {
                        stuck = true;
                        break;
                    }
                }
            }
            let allowed = budget.min(left);
            match self.walk_toward(&at, &target, allowed, follower, obstacles) {
                Some((spot, used, reached)) => {
                    moved |= used > 1e-9;
                    at = spot;
                    budget -= used.max(1e-6);
                    if reached {
                        follower.next += 1;
                    } else if used <= 1e-9 {
                        break;
                    }
                }
                None => {
                    stuck = true;
                    break;
                }
            }
        }
        Step {
            moved: moved.then_some(at),
            stuck,
        }
    }

    /// 朝足迹上的一点走至多 metres 米：直线通畅就直走；被挡就按绕行路线走，没有路线时先规划一条。
    /// 返回走到的位置、用掉的米数、是否到了这一点；绕不过去时为空。
    fn walk_toward(
        &self,
        here: &Spot,
        target: &Spot,
        metres: f64,
        follower: &mut Follower,
        obstacles: &[Obstacle],
    ) -> Option<(Spot, f64, bool)> {
        let d = distance(here.position, target.position);
        if follower.detour.is_empty() && self.segment_clear(here, target, obstacles) {
            return Some(if d <= metres {
                (self.spot_at(here, target.position), d, true)
            } else {
                (
                    self.spot_at(here, lerp(here.position, target.position, metres / d)),
                    metres,
                    false,
                )
            });
        }
        if follower.detour.is_empty() {
            follower.detour = self
                .detour(here, target.position, obstacles)
                .unwrap_or_default();
            if follower.detour.is_empty() {
                // 找不到绕行路线：很近就直接站过去，不然算被挡住
                return (d <= HOP_LIMIT
                    && self.clear(&target.space, target.position, obstacles, RADIUS))
                .then(|| (self.spot_at(here, target.position), d, true));
            }
        }
        let mut at = here.clone();
        let mut used = 0.;
        while let Some(&next) = follower.detour.first() {
            let step = distance(at.position, next);
            let next_spot = self.spot_at(&at, next);
            if !self.segment_clear(&at, &next_spot, obstacles) {
                follower.detour.clear();
                return (used > 0.).then_some((at, used, false));
            }
            if used + step > metres {
                let k = (metres - used) / step.max(1e-9);
                return Some((self.spot_at(&at, lerp(at.position, next, k)), metres, false));
            }
            used += step;
            at = next_spot;
            follower.detour.remove(0);
        }
        let reached = distance(at.position, target.position) <= DETOUR_REACH;
        Some((at, used, reached))
    }

    /// 同一空间里的一点：处所按这一点所在的区域算，落在区域外就沿用原来的处所。
    fn spot_at(&self, from: &Spot, p: Point) -> Spot {
        Spot {
            locale: self
                .locale_at(&from.space, p, &from.locale)
                .unwrap_or(&from.locale)
                .into(),
            space: from.space.clone(),
            position: p,
        }
    }

    /// 从 here 绕开障碍走到 target 附近的格点路线（不含起点），最多展开 MAX_EXPANSIONS 个格点。
    fn detour(&self, here: &Spot, target: Point, obstacles: &[Obstacle]) -> Option<Vec<Point>> {
        type Cell = (i32, i32);
        let point = |(x, y): Cell| -> Point {
            [
                here.position[0] + f64::from(x) * GRID_STEP,
                here.position[1] + f64::from(y) * GRID_STEP,
            ]
        };
        let spot = |cell: Cell| Spot {
            position: point(cell),
            ..here.clone()
        };
        let cost = |a: Point, b: Point| (distance(a, b) * 1000.) as u64;
        let mut queue = BinaryHeap::from([Reverse((cost(here.position, target), 0u64, (0, 0)))]);
        let mut best = BTreeMap::from([((0, 0), 0u64)]);
        let mut parents: BTreeMap<Cell, Cell> = BTreeMap::new();
        let mut expanded = 0;
        while let Some(Reverse((_, spent, cell))) = queue.pop() {
            if best[&cell] != spent {
                continue;
            }
            expanded += 1;
            if expanded > MAX_EXPANSIONS {
                return None;
            }
            let p = point(cell);
            if distance(p, target) <= DETOUR_REACH
                || (distance(p, target) <= GRID_STEP * 2.
                    && self.segment_clear(&spot(cell), &self.spot_at(here, target), obstacles))
            {
                let mut path = vec![target];
                let mut cursor = cell;
                path.push(point(cursor));
                while let Some(parent) = parents.get(&cursor) {
                    cursor = *parent;
                    path.push(point(cursor));
                }
                path.pop(); // 起点
                path.reverse();
                return Some(path);
            }
            for dx in -1..=1 {
                for dy in -1..=1 {
                    if dx == 0 && dy == 0 {
                        continue;
                    }
                    let next = (cell.0 + dx, cell.1 + dy);
                    let n = spent + cost(p, point(next));
                    if best.get(&next).is_some_and(|old| *old <= n)
                        || !self.segment_clear(&spot(cell), &spot(next), obstacles)
                    {
                        continue;
                    }
                    best.insert(next, n);
                    parents.insert(next, cell);
                    queue.push(Reverse((n + cost(point(next), target), n, next)));
                }
            }
        }
        None
    }
}

fn lerp(a: Point, b: Point, t: f64) -> Point {
    [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
}
