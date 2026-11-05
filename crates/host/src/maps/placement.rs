//! 运行时放置道具的几何：在地点区域里找一个不挡人、不挡家具、不挡通路的位置，
//! 再铺一条从入口过去的通路。内核只拿结果做 `check_override`，不读场景包也不搜索。
use super::manifest::{Manifest, ModelSpec};
use super::model::WALK_METRES_PER_MINUTE;
use kernel::navigation::space::{
    distance, footprint, intersects, route_length, too_steep, Floor, PlacementRequest, Placer,
    Point, PropPosition, Route, Space, StationPosition,
};
use kernel::topology::Prop;
use kernel::KernelError;
use std::collections::BTreeMap;

/// 新建通路的宽度和折点间距（米）。
const ROUTE_WIDTH: f64 = 0.7;
const ROUTE_POINT_SPACING: f64 = 0.7;
/// 场景包没给占地时的默认占地边长（米）。
const DEFAULT_FOOTPRINT: f64 = 0.65;
/// 放置搜索：离区域边缘的留白、格点间距、距地点入口的最小距离。
const FLOOR_MARGIN: f64 = 0.65;
const GRID_STEP: f64 = 0.4;
const MIN_ARRIVAL_DISTANCE: f64 = 1.8;
/// 与既有家具、人物的留白，以及入口到操作锚点那段路的留白。
const OBSTACLE_PAD: f64 = 0.31;
const PLACEMENT_PAD: f64 = 0.4;
const ANCHOR_PATH_PAD: f64 = 0.28;
/// 操作锚点在道具正面外多远。
const ANCHOR_OFFSET: f64 = 0.45;
/// 放置搜索的行列上限。
const GRID_CELLS: usize = 100;

/// 按场景包模型表放置道具；没有场景包时全部用通用模型与默认占地。
#[derive(Clone, Default)]
pub struct ScenePlacer {
    models: BTreeMap<String, ModelSpec>,
}

/// 放置搜索的固定输入：区域、入口、既有障碍与人物位置。
struct Site<'a> {
    floor: &'a Floor,
    arrival: &'a StationPosition,
    obstacles: Vec<kernel::navigation::space::Bounds>,
    occupied: &'a [Point],
}

impl ScenePlacer {
    pub fn new(manifest: Option<&Manifest>) -> Self {
        Self {
            models: manifest.map(|m| m.props.clone()).unwrap_or_default(),
        }
    }

    /// 场景包里这个定义对应的模型名与占地。
    fn model(&self, prop: &Prop) -> (String, [f64; 2]) {
        let key = prop
            .definition
            .as_deref()
            .unwrap_or("")
            .split('@')
            .next()
            .unwrap_or("");
        match self.models.get(key) {
            Some(m) => (m.model.clone(), m.footprint),
            None => ("generic".into(), [DEFAULT_FOOTPRINT, DEFAULT_FOOTPRINT]),
        }
    }
}

impl Placer for ScenePlacer {
    fn plan(
        &self,
        s: &Space,
        request: &PlacementRequest,
    ) -> Result<kernel::navigation::space::Override, KernelError> {
        let prop = request.prop;
        let site = Site {
            floor: s
                .floor(&prop.locale)
                .ok_or_else(|| KernelError::Navigation("缺少可放置区域".into()))?,
            arrival: s
                .arrival(&prop.locale)
                .ok_or_else(|| KernelError::Navigation("地点没有空间入口".into()))?,
            obstacles: request
                .obstacles
                .iter()
                .map(|p| footprint(p, OBSTACLE_PAD))
                .collect(),
            occupied: &request.occupied,
        };
        let (model, size) = self.model(prop);
        let pp =
            find_free_position(s, &site, prop, model, size, request.near).ok_or_else(|| {
                KernelError::Navigation("没有不阻挡人物、家具和既有通路的放置位置".into())
            })?;
        let route = walk_route(s, site.floor, site.arrival, prop, &pp)?;
        Ok(kernel::navigation::space::Override { prop: pp, route })
    }
}

/// 在区域的格点里取第一个满足全部留白的位置：玩家点了位置就从离它最近的格点试起，
/// 否则从区域一角一行行扫过去。每个格点先试操作锚点朝南，从入口走不过去再试朝北。
fn find_free_position(
    s: &Space,
    site: &Site,
    prop: &Prop,
    model: String,
    [w, depth]: [f64; 2],
    near: Option<[f64; 2]>,
) -> Option<PropPosition> {
    let b = &site.floor.bounds;
    let mut spots = Vec::new();
    for row in 0..GRID_CELLS {
        let z = b.y + depth / 2. + FLOOR_MARGIN + row as f64 * GRID_STEP;
        if z > b.y + b.h - depth / 2. - 1. {
            break;
        }
        for col in 0..GRID_CELLS {
            let x = b.x + w / 2. + FLOOR_MARGIN + col as f64 * GRID_STEP;
            if x > b.x + b.w - w / 2. - FLOOR_MARGIN {
                break;
            }
            spots.push([x, z]);
        }
    }
    if let Some([nx, nz]) = near {
        let away = |[x, z]: [f64; 2]| (x - nx).hypot(z - nz);
        spots.sort_by(|a, b| away(*a).total_cmp(&away(*b)));
    }
    spots.into_iter().find_map(|[x, z]| {
        let y = s.height_at(x, z, site.arrival.position[1]);
        // 操作锚点默认在南边（正对镜头）；入口在北边时，走到南边的锚点要穿过道具本身，就换到北边
        [(1., 0.), (-1., std::f64::consts::PI)]
            .into_iter()
            .find_map(|(side, yaw)| {
                let az = z + side * (depth / 2. + ANCHOR_OFFSET);
                let pp = PropPosition {
                    id: prop.id.clone(),
                    locale: prop.locale.clone(),
                    model: model.clone(),
                    position: [x, y, z],
                    anchor: [x, s.height_at(x, az, y), az],
                    yaw,
                    footprint: [w, depth],
                };
                position_is_free(s, site, &pp).then_some(pp)
            })
    })
}

fn position_is_free(s: &Space, site: &Site, pp: &PropPosition) -> bool {
    let r = footprint(pp, PLACEMENT_PAD);
    let arrival = site.arrival.position;
    distance(arrival, pp.position) >= MIN_ARRIVAL_DISTANCE
        && !site.occupied.iter().any(|p| r.contains(*p))
        && !site.obstacles.iter().any(|o| r.overlaps(o))
        && !s
            .all_routes()
            .any(|route| route.points.windows(2).any(|p| intersects(p[0], p[1], &r)))
        && !site
            .obstacles
            .iter()
            .any(|o| intersects(arrival, pp.anchor, o))
        && !intersects(arrival, pp.anchor, &footprint(pp, ANCHOR_PATH_PAD))
}

/// 入口到操作锚点的直线通路，折点贴地形；坡度超限则失败。
fn walk_route(
    s: &Space,
    floor: &Floor,
    arrival: &StationPosition,
    prop: &Prop,
    pp: &PropPosition,
) -> Result<Route, KernelError> {
    let count = (distance(arrival.position, pp.anchor) / ROUTE_POINT_SPACING)
        .ceil()
        .max(1.) as usize;
    let points = (0..=count)
        .map(|i| {
            let f = i as f64 / count as f64;
            let mut p: Point = std::array::from_fn(|j| {
                arrival.position[j] + (pp.anchor[j] - arrival.position[j]) * f
            });
            p[1] = s.height_at(p[0], p[2], p[1]);
            p
        })
        .collect::<Vec<_>>();
    if too_steep(&points) {
        return Err(KernelError::Navigation("新通路坡度超出可步行范围".into()));
    }
    let length = route_length(&points);
    Ok(Route {
        id: format!("walk_{}", prop.id),
        from: format!("arrival_{}", prop.locale),
        to: format!("node_{}", prop.id),
        from_locale: prop.locale.clone(),
        to_locale: prop.locale.clone(),
        width: ROUTE_WIDTH,
        points,
        length,
        minutes: length / WALK_METRES_PER_MINUTE,
        indoor: floor.indoor,
        owner: Some(prop.locale.clone()),
    })
}
