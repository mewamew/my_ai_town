//! 米制二维行走区域。只处理几何；物品是否仍在地图上由 World 提供。
use protocol::{At, Locus};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

pub type Point = [f64; 2];
pub const RADIUS: f64 = 0.24;
pub const REACH: f64 = 1.6;
pub const TALK_REACH: f64 = 3.0;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Spot {
    pub locale: String,
    pub space: String,
    pub position: Point,
}
impl Spot {
    pub fn locus(&self) -> Locus {
        Locus {
            locale: self.locale.clone(),
            at: At::Free {
                space: self.space.clone(),
                position: self.position,
                elevation: None,
                yaw: None,
            },
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Area {
    Cells {
        size: f64,
        cells: BTreeSet<(i32, i32)>,
    },
    Rect {
        min: Point,
        max: Point,
    },
    Corridor {
        points: Vec<Point>,
        width: f64,
    },
}
impl Area {
    fn contains(&self, p: Point) -> bool {
        match self {
            Self::Cells { size, cells } => {
                cells.contains(&((p[0] / size).floor() as i32, (p[1] / size).floor() as i32))
            }
            Self::Rect { min, max } => (0..2).all(|i| p[i] >= min[i] && p[i] <= max[i]),
            Self::Corridor { points, width } => points
                .windows(2)
                .any(|s| segment_distance(p, s[0], s[1]) <= width / 2.),
        }
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Surface {
    pub locale: String,
    pub space: String,
    pub area: Area,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Obstacle {
    pub id: String,
    pub spot: Spot,
    pub half: Point,
}
impl Obstacle {
    /// 占地盖住这一点（同一空间里）：站在这里的人是坐在、躺在这件家具上。
    pub(crate) fn covers(&self, at: &Spot) -> bool {
        self.spot.space == at.space
            && (0..2).all(|i| (at.position[i] - self.spot.position[i]).abs() < self.half[i])
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Portal {
    pub id: String,
    pub label: String,
    pub from: Spot,
    pub to: Spot,
}
/// 行走地图。地图约定（室外空间编号、步行速度）由 host 编译地图时填入，内核不写死。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WalkMap {
    pub version: u32,
    pub svg_units_per_metre: f64,
    /// 步行速度（米/模拟分钟）：化身移动、接续行走、避雨耗时和新通路时长都按它算。
    pub metres_per_minute: f64,
    /// 室外空间的编号：地形高度只作用于这个空间，天气按它判断露天；
    /// 没有落在任何区域上的处所也归到这个空间。
    pub outdoor_space: String,
    pub surfaces: Vec<Surface>,
    pub stations: BTreeMap<String, Spot>,
    pub props: BTreeMap<String, Spot>,
    pub obstacles: Vec<Obstacle>,
    pub portals: Vec<Portal>,
    pub terrain: Option<crate::navigation::space::Terrain>,
    pub sea_level: f64,
}
pub fn distance(a: Point, b: Point) -> f64 {
    (a[0] - b[0]).hypot(a[1] - b[1])
}
/// 折线上按长度比例 t（0–1）取的点。
fn along(points: &[Point], t: f64) -> Point {
    let length: f64 = points.windows(2).map(|s| distance(s[0], s[1])).sum();
    let mut left = t.clamp(0., 1.) * length;
    for s in points.windows(2) {
        let d = distance(s[0], s[1]);
        if left <= d && d > 0. {
            let k = left / d;
            return [
                s[0][0] + (s[1][0] - s[0][0]) * k,
                s[0][1] + (s[1][1] - s[0][1]) * k,
            ];
        }
        left -= d;
    }
    points[points.len() - 1]
}
pub fn segment_distance(p: Point, a: Point, b: Point) -> f64 {
    let d = [b[0] - a[0], b[1] - a[1]];
    let t = (((p[0] - a[0]) * d[0] + (p[1] - a[1]) * d[1])
        / (d[0] * d[0] + d[1] * d[1]).max(1e-12))
    .clamp(0., 1.);
    distance(p, [a[0] + t * d[0], a[1] + t * d[1]])
}
impl WalkMap {
    /// 处所所在的行走空间；地图上没有这个处所的区域时算作室外。
    pub fn space_of(&self, locale: &str) -> &str {
        self.surfaces
            .iter()
            .find(|s| s.locale == locale)
            .map_or(&self.outdoor_space, |s| &s.space)
    }
    /// 人物在行走地图上的位置。站在房间到达点上的人算在门内，见 `inside_door`。
    pub fn station_locus(&self, locus: &Locus) -> Option<Spot> {
        match &locus.at {
            At::Free {
                space, position, ..
            } => Some(Spot {
                locale: locus.locale.clone(),
                space: space.clone(),
                position: *position,
            }),
            At::Station { station } => self.stations.get(station).map(|s| self.inside_door(s)),
            _ => None,
        }
    }
    /// 房间的到达点画在门外的空间里，处所却是房间。站在那里的人换到这扇门的门内一侧：
    /// 玩家进屋才和他同处一地、够得着说话；附身后的自由位置也落在自己的处所里。
    /// 站点本身不改，放东西仍按门外的点算；屋里没有站点时，接续行走走到门内这一点就算到了站点
    /// （navigation/free.rs 的 door_goals）。
    pub(crate) fn inside_door(&self, s: &Spot) -> Spot {
        let home = self.space_of(&s.locale);
        if s.space == home {
            return s.clone();
        }
        self.portals
            .iter()
            .filter(|p| p.from.space == s.space && p.to.locale == s.locale && p.to.space == home)
            .map(|p| (distance(p.from.position, s.position), p))
            .filter(|(d, _)| *d <= REACH)
            .min_by(|a, b| a.0.total_cmp(&b.0))
            .map_or_else(|| s.clone(), |(_, p)| p.to.clone())
    }
    /// 读档校验：自由位置必须落在所在处所的可走区域里。
    pub(crate) fn check_free_locus(
        &self,
        locus: &Locus,
        _topo: &crate::topology::Topology,
    ) -> crate::error::Result<()> {
        use crate::error::KernelError;
        let At::Free {
            space,
            position,
            elevation,
            yaw,
        } = &locus.at
        else {
            return Ok(());
        };
        ensure!(
            position.iter().all(|v| v.is_finite())
                && elevation.is_none()
                && yaw.is_none()
                && self.locale_at(space, *position, &locus.locale) == Some(locus.locale.as_str()),
            KernelError::snapshot("自由位置不属于所在区域")
        );
        Ok(())
    }
    pub fn locale_at(&self, space: &str, p: Point, preferred: &str) -> Option<&str> {
        self.surfaces
            .iter()
            .filter(|s| s.space == space && s.area.contains(p))
            .min_by_key(|s| usize::from(s.locale != preferred))
            .map(|s| s.locale.as_str())
    }
    /// 这一点落在这个空间的地面上：同 locale_at 有结果，但不用挑处所，找到一块就停。
    /// 走路每 0.1 米、看遮挡每 0.15 米都要问好几次，是每拍最费时的地方
    fn on_surface(&self, space: &str, p: Point) -> bool {
        self.surfaces
            .iter()
            .any(|s| s.space == space && s.area.contains(p))
    }
    pub fn clear(&self, space: &str, p: Point, obstacles: &[Obstacle], radius: f64) -> bool {
        self.clear_except(space, p, obstacles, &[], radius)
    }
    /// 同 clear，但 ignored 里的障碍不算（要够着的目标道具自己、两人身下的家具）。
    fn clear_except(
        &self,
        space: &str,
        p: Point,
        obstacles: &[Obstacle],
        ignored: &[&str],
        radius: f64,
    ) -> bool {
        // 半径为 0（看遮挡时逐点取样）八个方向都是这一点，查一次就够
        let rim = if radius > 0. { 8 } else { 1 };
        p.iter().all(|v| v.is_finite())
            && self.terrain_clear(space, p)
            && (0..rim).all(|i| {
                let a = i as f64 * std::f64::consts::TAU / 8.;
                self.on_surface(space, [p[0] + radius * a.cos(), p[1] + radius * a.sin()])
            })
            && !obstacles.iter().any(|o| {
                !ignored.contains(&o.id.as_str())
                    && o.spot.space == space
                    && (0..2).all(|i| (p[i] - o.spot.position[i]).abs() < o.half[i] + radius)
            })
    }
    fn terrain_clear(&self, space: &str, p: Point) -> bool {
        let Some(t) = &self.terrain else {
            return true;
        };
        if space != self.outdoor_space {
            return true;
        }
        if (0..2).any(|i| p[i] < t.origin[i])
            || p[0] > t.origin[0] + t.step * (t.columns - 1) as f64
            || p[1] > t.origin[1] + t.step * (t.rows - 1) as f64
        {
            return false;
        }
        let Some(h) = t.height(p[0], p[1]) else {
            return false;
        };
        h > self.sea_level + 0.05
            && (0..2).all(|axis| {
                let mut q = p;
                q[axis] += 0.2;
                t.height(q[0], q[1])
                    .is_some_and(|n| (n - h).abs() <= 0.2 * 0.8)
            })
    }
    /// 走在路段上的人（一维进度）此刻在行走地图上的位置：按进度比例在这条路的中线上取点，
    /// 和前端画他的位置一样（town-shared/spatial.ts 的 position）。不在路段上、地图上没有这条路时为空。
    pub fn transit_spot(&self, locus: &Locus) -> Option<Spot> {
        let At::Transit { elapsed, total, .. } = &locus.at else {
            return None;
        };
        self.surfaces.iter().find_map(|s| match &s.area {
            Area::Corridor { points, .. } if s.locale == locus.locale && !points.is_empty() => {
                Some(Spot {
                    locale: locus.locale.clone(),
                    space: s.space.clone(),
                    position: along(points, if *total > 0. { elapsed / total } else { 0. }),
                })
            }
            _ => None,
        })
    }
    /// 玩家和人说话够不够得着：同一空间、距离不超过 limit、中间没有遮挡。
    /// 不管是不是同一个处所：处所之间的分界在画面上看不出来。两人身下的家具（坐着的长椅、
    /// 躺着的床，占地盖住站位点）不算遮挡，不然坐着、躺着的人从哪个方向都够不着。
    pub(crate) fn within_talk<'o>(
        &self,
        from: &Spot,
        to: &Spot,
        limit: f64,
        obstacles: impl FnOnce() -> &'o [Obstacle],
    ) -> bool {
        if from.space != to.space || distance(from.position, to.position) > limit {
            return false;
        }
        let obstacles = obstacles();
        let under: Vec<&str> = obstacles
            .iter()
            .filter(|o| o.covers(from) || o.covers(to))
            .map(|o| o.id.as_str())
            .collect();
        self.visible_except(from, to, obstacles, &under)
    }
    /// 从 from 往 toward（对方的位置）走，第一个落在处所 locale 里、站得下的点：玩家和隔着处所分界的人
    /// 说上话时，往前挪这一步站进对方的处所，两人才在同一个地方。本来就在里面时就是原地；找不到为空。
    pub(crate) fn step_into(
        &self,
        locale: &str,
        from: &Spot,
        toward: Point,
        obstacles: &[Obstacle],
    ) -> Option<Spot> {
        let inside = |p: Point| {
            self.locale_at(&from.space, p, locale) == Some(locale)
                && self.clear(&from.space, p, obstacles, RADIUS)
        };
        let steps = (distance(from.position, toward) / 0.1).ceil().max(1.) as usize;
        (0..=steps)
            .map(|i| {
                let t = i as f64 / steps as f64;
                [
                    from.position[0] + (toward[0] - from.position[0]) * t,
                    from.position[1] + (toward[1] - from.position[1]) * t,
                ]
            })
            .find(|p| inside(*p))
            .map(|position| Spot {
                locale: locale.into(),
                space: from.space.clone(),
                position,
            })
    }
    /// 同一空间与处所、距离不超过 limit，且中间没有遮挡；目标道具自己可以忽略。
    pub(crate) fn reaches<'o>(
        &self,
        from: &Spot,
        to: &Spot,
        limit: f64,
        ignored: Option<&str>,
        obstacles: impl FnOnce() -> &'o [Obstacle],
    ) -> bool {
        if from.space != to.space || distance(from.position, to.position) > limit {
            return false;
        }
        if from.locale != to.locale {
            return false;
        }
        self.visible_except(from, to, obstacles(), ignored.as_slice())
    }
    pub fn visible(&self, a: &Spot, b: &Spot, obstacles: &[Obstacle]) -> bool {
        self.visible_except(a, b, obstacles, &[])
    }
    /// 两点之间看得见：按 0.15 米一步取样，中间每个点都不被挡（ignored 里的障碍不算）。
    fn visible_except(&self, a: &Spot, b: &Spot, obstacles: &[Obstacle], ignored: &[&str]) -> bool {
        if a.space != b.space {
            return false;
        }
        let steps = (distance(a.position, b.position) / 0.15).ceil().max(1.) as usize;
        (1..steps).all(|i| {
            let t = i as f64 / steps as f64;
            self.clear_except(
                &a.space,
                [
                    a.position[0] + (b.position[0] - a.position[0]) * t,
                    a.position[1] + (b.position[1] - a.position[1]) * t,
                ],
                obstacles,
                ignored,
                0.,
            )
        })
    }
    /// 最多在落点周围 2 米找安全位置，不把非法位置迁移到地图另一端。
    pub fn safe_near(&self, spot: &Spot, obstacles: &[Obstacle]) -> Option<Spot> {
        for ring in 0..=10 {
            for i in 0..16 {
                let a = i as f64 * std::f64::consts::TAU / 16.;
                let r = ring as f64 * 0.2;
                let p = [
                    spot.position[0] + r * a.cos(),
                    spot.position[1] + r * a.sin(),
                ];
                if self.clear(&spot.space, p, obstacles, RADIUS) {
                    return Some(Spot {
                        locale: self.locale_at(&spot.space, p, &spot.locale)?.into(),
                        space: spot.space.clone(),
                        position: p,
                    });
                }
            }
        }
        None
    }
    /// 连续扫掠拆成至多 0.1 米的小步；受阻时按偏转角从小到大找能走的方向滑开，
    /// 位移按偏转角的余弦缩短，相当于把原位移投影到滑动方向。斜路、墙角、圆形障碍都适用。
    pub fn advance(&self, start: &Spot, delta: Point, obstacles: &[Obstacle]) -> Spot {
        let steps = (delta[0].hypot(delta[1]) / 0.1).ceil().max(1.) as usize;
        let d = [delta[0] / steps as f64, delta[1] / steps as f64];
        let mut p = start.position;
        for _ in 0..steps {
            let both = [p[0] + d[0], p[1] + d[1]];
            if self.clear(&start.space, both, obstacles, RADIUS) {
                p = both;
                continue;
            }
            if let Some(next) = self.slide(&start.space, p, d, obstacles) {
                p = next;
            }
        }
        Spot {
            locale: self
                .locale_at(&start.space, p, &start.locale)
                .unwrap_or(&start.locale)
                .into(),
            space: start.space.clone(),
            position: p,
        }
    }
    /// 受阻时的滑动落点：依次试 ±15°、±30°…±75°；正对着墙时全部受阻，原地不动。
    fn slide(&self, space: &str, p: Point, d: Point, obstacles: &[Obstacle]) -> Option<Point> {
        (1..=5).find_map(|k| {
            let angle = f64::from(k) * std::f64::consts::PI / 12.;
            let scale = angle.cos();
            [1., -1.].into_iter().find_map(|sign: f64| {
                let (s, c) = (sign * angle).sin_cos();
                let next = [
                    p[0] + (d[0] * c - d[1] * s) * scale,
                    p[1] + (d[0] * s + d[1] * c) * scale,
                ];
                self.clear(space, next, obstacles, RADIUS).then_some(next)
            })
        })
    }
}
