//! 空间数据与路线覆盖。放置位置由 host 通过 `Placer` 算出，内核只校验并接进拓扑。
use crate::error::{KernelError, Result};
use crate::topology::{Link, Locale, LocaleKind, Prop, Station, StationKind, Topology, Via};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
pub type Point = [f64; 3];

/// 运行时空间道具上限，也是一条通路的折点上限。
pub const MAX_OVERRIDES: usize = 256;
pub const MAX_ROUTE_POINTS: usize = 256;
/// 可步行的最大坡度（高差 / 水平距离）。
pub const MAX_SLOPE: f64 = 0.17;

/// 道具位置、通路与运行时空间覆盖；线上与存档共用 protocol 的定义。
pub use protocol::{PropPosition, Route, SpatialOverride as Override};
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StationPosition {
    pub id: String,
    pub locale: String,
    pub position: Point,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Bounds {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}
impl Bounds {
    pub fn overlaps(&self, o: &Bounds) -> bool {
        self.x < o.x + o.w && self.x + self.w > o.x && self.y < o.y + o.h && self.y + self.h > o.y
    }
    /// 点（x, z）是否在矩形内部。
    pub fn contains(&self, p: Point) -> bool {
        p[0] > self.x && p[0] < self.x + self.w && p[2] > self.y && p[2] < self.y + self.h
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Floor {
    pub id: String,
    pub bounds: Bounds,
    pub indoor: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Space {
    #[serde(default)]
    pub terrain: Option<Terrain>,
    pub navigation_revision: u64,
    pub floors: Vec<Floor>,
    pub props: Vec<PropPosition>,
    pub routes: Vec<Route>,
    pub stations: Vec<StationPosition>,
    #[serde(default)]
    pub overrides: BTreeMap<String, Override>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Terrain {
    pub origin: [f64; 2],
    pub step: f64,
    pub columns: usize,
    pub rows: usize,
    pub heights: Vec<f64>,
}
impl Terrain {
    pub fn height(&self, x: f64, z: f64) -> Option<f64> {
        if self.columns < 2
            || self.rows < 2
            || self.heights.len() != self.columns * self.rows
            || self.step <= 0.
        {
            return None;
        }
        let u = (x - self.origin[0]) / self.step;
        let v = (z - self.origin[1]) / self.step;
        let ix = u.floor().clamp(0., (self.columns - 2) as f64) as usize;
        let iz = v.floor().clamp(0., (self.rows - 2) as f64) as usize;
        let a = (u - ix as f64).clamp(0., 1.);
        let b = (v - iz as f64).clamp(0., 1.);
        let h = &self.heights;
        let n = self.columns;
        Some(
            (h[iz * n + ix] * (1. - a) + h[iz * n + ix + 1] * a) * (1. - b)
                + (h[(iz + 1) * n + ix] * (1. - a) + h[(iz + 1) * n + ix + 1] * a) * b,
        )
    }
}
pub fn distance(a: Point, b: Point) -> f64 {
    ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt()
}
/// 线段 a–b 是否穿过矩形（x/z 平面）。
pub fn intersects(a: Point, b: Point, r: &Bounds) -> bool {
    let mut lo: f64 = 0.;
    let mut hi: f64 = 1.;
    for (axis, start, size) in [(0, r.x, r.w), (2, r.y, r.h)] {
        let delta = b[axis] - a[axis];
        if delta.abs() < 1e-8 {
            if a[axis] <= start || a[axis] >= start + size {
                return false;
            }
        } else {
            let u = (start - a[axis]) / delta;
            let v = (start + size - a[axis]) / delta;
            lo = lo.max(u.min(v));
            hi = hi.min(u.max(v));
            if lo >= hi {
                return false;
            }
        }
    }
    hi > 0. && lo < 1.
}
/// 道具占地矩形，四边各外扩 pad。
pub fn footprint(p: &PropPosition, pad: f64) -> Bounds {
    Bounds {
        x: p.position[0] - p.footprint[0] / 2. - pad,
        y: p.position[2] - p.footprint[1] / 2. - pad,
        w: p.footprint[0] + pad * 2.,
        h: p.footprint[1] + pad * 2.,
    }
}
pub fn route_length(points: &[Point]) -> f64 {
    points.windows(2).map(|p| distance(p[0], p[1])).sum::<f64>()
}
/// 相邻折点之间是否有坡度超限。
pub fn too_steep(points: &[Point]) -> bool {
    points.windows(2).any(|p| {
        (p[1][1] - p[0][1]).abs() / ((p[1][0] - p[0][0]).hypot(p[1][2] - p[0][2])).max(1e-9)
            > MAX_SLOPE
    })
}
impl Space {
    pub fn prop(&self, id: &str) -> Option<&PropPosition> {
        self.overrides
            .get(id)
            .map(|v| &v.prop)
            .or_else(|| self.props.iter().find(|p| p.id == id))
    }
    pub fn all_routes(&self) -> impl Iterator<Item = &Route> {
        self.routes
            .iter()
            .chain(self.overrides.values().map(|v| &v.route))
    }
    pub fn height_at(&self, x: f64, z: f64, fallback: f64) -> f64 {
        self.terrain
            .as_ref()
            .and_then(|t| t.height(x, z))
            .unwrap_or(fallback)
    }
    pub fn floor(&self, locale: &str) -> Option<&Floor> {
        self.floors.iter().find(|f| f.id == locale)
    }
    /// 地点的空间入口（`at_{locale}` 落脚点）。
    pub fn arrival(&self, locale: &str) -> Option<&StationPosition> {
        self.stations
            .iter()
            .find(|st| st.id == format!("at_{locale}"))
    }
    /// 位置的空间坐标。`prop_station` 把运行时道具的编号换成它的操作点编号。
    fn point(
        &self,
        locale: &str,
        at: &protocol::At,
        prop_station: impl Fn(&str) -> Option<String>,
    ) -> Option<Point> {
        match at {
            protocol::At::Free {
                position,
                elevation,
                ..
            } => Some([
                position[0],
                elevation.unwrap_or_else(|| self.height_at(position[0], position[1], 0.)),
                position[1],
            ]),
            protocol::At::Station { station } => self
                .stations
                .iter()
                .find(|p| p.id == *station)
                .map(|p| p.position)
                .or_else(|| {
                    self.overrides
                        .values()
                        .find(|v| prop_station(&v.prop.id).as_deref() == Some(station))
                        .map(|v| v.prop.anchor)
                }),
            protocol::At::Transit { elapsed, total, .. } => {
                let route = self.all_routes().find(|r| r.id == locale)?;
                let mut left = route.length * (elapsed / total.max(1e-9)).clamp(0., 1.);
                for ps in route.points.windows(2) {
                    let len = distance(ps[0], ps[1]);
                    if left <= len {
                        let f = left / len.max(1e-9);
                        return Some(std::array::from_fn(|i| {
                            ps[0][i] + (ps[1][i] - ps[0][i]) * f
                        }));
                    }
                    left -= len
                }
                route.points.last().copied()
            }
            _ => None,
        }
    }
}

/// 放置一件道具时内核交给放置器的事实：道具本身、同地点仍在地图上的家具、在场人物位置，
/// 以及玩家在地图上点的位置（水平面 x、z，米），有它时取离它最近的空位。
pub struct PlacementRequest<'a> {
    pub prop: &'a Prop,
    pub obstacles: Vec<&'a PropPosition>,
    pub occupied: Vec<Point>,
    pub near: Option<[f64; 2]>,
    /// 人能不能站在这一点（水平面 x、z，米）：用道具的人要站到操作锚点上。有行走地图时按它的
    /// 可走格子判断，没有时哪里都能站（见 `navigation::stand_check`）。
    pub stand: &'a dyn Fn([f64; 2]) -> bool,
}

/// 空间放置的计算方。几何搜索与场景包读取都在 host；内核拿到结果后只做 `check_override`。
pub trait Placer: Send + Sync {
    fn plan(&self, space: &Space, request: &PlacementRequest) -> Result<Override>;

    /// 摆道具界面用的格子：按没有专门模型的道具的占地，把 `plan` 会试的格点逐个试一遍，记下
    /// 哪些能放、不能放的为什么。obstacles、stand 同 `PlacementRequest`；不算在场的人，人会走开。
    /// 地点没有可放置范围或入口时没有格子。
    fn grid(
        &self,
        _space: &Space,
        _locale: &str,
        _obstacles: &[&PropPosition],
        _stand: &dyn Fn([f64; 2]) -> bool,
    ) -> Option<protocol::PlaceGrid> {
        None
    }
}

impl Topology {
    pub fn navigation_revision(&self) -> Option<u64> {
        self.navigation.as_ref().map(|s| s.navigation_revision)
    }

    /// 道具的操作点编号：按 host 给出的前缀拼成；地图没有给出前缀时没有操作点。
    pub(crate) fn prop_station(&self, prop: &str) -> Option<String> {
        self.prop_station_prefix
            .as_ref()
            .map(|prefix| format!("{prefix}{prop}"))
    }

    /// 精确导航地图上一个位置的空间坐标；没有空间地图时为 None。
    pub(crate) fn point(&self, locale: &str, at: &protocol::At) -> Option<Point> {
        self.navigation
            .as_ref()?
            .point(locale, at, |prop| self.prop_station(prop))
    }

    /// 道具位置或可见性变化后，客户端要重新取空间数据。
    pub(crate) fn bump_navigation_revision(&mut self) {
        if let Some(s) = &mut self.navigation {
            s.navigation_revision += 1;
        }
    }

    /// 校验一条空间覆盖并接进拓扑：新增路段、节点、操作点。
    /// `metres_per_minute` 是行走地图的步行速度，用来核对路线时长。
    pub(crate) fn install_override(&mut self, v: Override, metres_per_minute: f64) -> Result<()> {
        let s = self
            .navigation
            .as_ref()
            .ok_or_else(|| KernelError::navigation("缺少空间地图"))?;
        check_override(s, &v, metres_per_minute)?;
        let id = self
            .prop_station(&v.prop.id)
            .ok_or_else(|| KernelError::navigation("地图没有给出道具操作点的编号规则"))?;
        ensure!(
            self.graph.contains_key(&v.route.from),
            KernelError::navigation("空间覆盖的起点不在节点图里")
        );
        let r = &v.route;
        self.locales.insert(
            r.id.clone(),
            Locale {
                id: r.id.clone(),
                name: "前往道具的通道".into(),
                kind: LocaleKind::Transit,
                minutes: Some(r.minutes),
                from_node: Some(r.from.clone()),
                to_node: Some(r.to.clone()),
            },
        );
        for (a, b) in [(&r.from, &r.to), (&r.to, &r.from)] {
            self.graph.entry(a.clone()).or_default().push(Link {
                to_node: b.clone(),
                minutes: r.minutes,
                via: Via::Edge {
                    locale: r.id.clone(),
                },
            })
        }
        self.node_locale.insert(r.to.clone(), v.prop.locale.clone());
        self.locale_nodes
            .entry(v.prop.locale.clone())
            .or_default()
            .push(r.to.clone());
        self.stations.insert(
            id.clone(),
            Station {
                id,
                name: "道具操作点".into(),
                locale: v.prop.locale.clone(),
                kind: StationKind::Slot,
                node: Some(r.to.clone()),
                activity_id: None,
                pose_family: None,
                role: None,
            },
        );
        if let Some(s) = &mut self.navigation {
            s.overrides.insert(v.prop.id.clone(), v);
            s.navigation_revision += 1;
        }
        Ok(())
    }

    /// 撤掉一条空间覆盖。修订号只增不减，客户端不会以同一号看到不同内容。
    pub(crate) fn remove_override(&mut self, id: &str) {
        let Some(s) = &mut self.navigation else {
            return;
        };
        let Some(v) = s.overrides.remove(id) else {
            return;
        };
        s.navigation_revision += 1;
        self.locales.remove(&v.route.id);
        if let Some(station) = self.prop_station(id) {
            self.stations.remove(&station);
        }
        self.graph.remove(&v.route.to);
        for links in self.graph.values_mut() {
            links.retain(|l| l.to_node != v.route.to)
        }
        self.node_locale.remove(&v.route.to);
        for nodes in self.locale_nodes.values_mut() {
            nodes.retain(|n| n != &v.route.to)
        }
    }
}

/// 空间覆盖的静态校验：编号约定、长度与时长一致、坡度、折点在区域内并连接入口与锚点。
pub fn check_override(s: &Space, v: &Override, metres_per_minute: f64) -> Result<()> {
    let f = s
        .floor(&v.prop.locale)
        .ok_or_else(|| KernelError::navigation("空间覆盖地点不存在"))?;
    let arrival = s
        .arrival(&v.prop.locale)
        .ok_or_else(|| KernelError::navigation("空间入口不存在"))?;
    let r = &v.route;
    ensure!(
        s.overrides.len() < MAX_OVERRIDES && !s.overrides.contains_key(&v.prop.id),
        KernelError::navigation("空间覆盖数量超限或编号重复")
    );
    ensure!(
        r.id == format!("walk_{}", v.prop.id)
            && r.to == format!("node_{}", v.prop.id)
            && r.from == format!("arrival_{}", v.prop.locale)
            && r.owner.as_deref() == Some(&v.prop.locale),
        KernelError::navigation("空间覆盖的路线编号与道具不对应")
    );
    ensure!(
        v.prop.position.iter().all(|n| n.is_finite())
            && v.prop.anchor.iter().all(|n| n.is_finite())
            && v.prop
                .footprint
                .iter()
                .all(|n| n.is_finite() && *n > 0. && *n <= 5.),
        KernelError::navigation("空间覆盖的道具位置或占地无效")
    );
    ensure!(
        (2..=MAX_ROUTE_POINTS).contains(&r.points.len())
            && r.points.iter().flatten().all(|n| n.is_finite()),
        KernelError::navigation("空间覆盖的折点数量或坐标无效")
    );
    ensure!(
        !too_steep(&r.points),
        KernelError::navigation("新通路坡度超出可步行范围")
    );
    let length = route_length(&r.points);
    ensure!(
        length.is_finite()
            && (length - r.length).abs() <= 1e-4
            && (length / metres_per_minute - r.minutes).abs() <= 1e-5
            && r.minutes > 0.,
        KernelError::navigation("空间覆盖的路线长度或时长不一致")
    );
    ensure!(
        r.points
            .first()
            .is_some_and(|p| distance(*p, arrival.position) <= 1e-3)
            && r.points
                .last()
                .is_some_and(|p| distance(*p, v.prop.anchor) <= 1e-3),
        KernelError::navigation("空间覆盖的路线没有连接入口和操作锚点")
    );
    ensure!(
        r.points.iter().all(|p| {
            p[0] >= f.bounds.x - 1e-3
                && p[0] <= f.bounds.x + f.bounds.w + 1e-3
                && p[2] >= f.bounds.y - 1e-3
                && p[2] <= f.bounds.y + f.bounds.h + 1e-3
        }),
        KernelError::navigation("空间覆盖的路线越出区域")
    );
    Ok(())
}
