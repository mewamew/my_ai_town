//! 运行时放置道具的几何：在地点区域里找一个不挡人、不挡家具、不挡通路的位置，
//! 再铺一条从入口过去的通路。内核只拿结果做 `check_override`，不读场景包也不搜索。
//! 摆道具界面画的格子也在这里算：逐格判断（`Site::try_spot`）和找空位是同一段代码，
//! 界面上说能放的格子，点上去就落在那一格。
use super::manifest::{Manifest, ModelSpec};
use super::model::WALK_METRES_PER_MINUTE;
use kernel::navigation::space::{
    distance, footprint, intersects, route_length, too_steep, Bounds, Floor, PlacementRequest,
    Placer, Point, PropPosition, Route, Space, StationPosition,
};
use kernel::topology::Prop;
use kernel::KernelError;
use protocol::PlaceGrid;
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
/// 摆道具界面估「还能放几件」时数到几件为止。
const ROOM_LIMIT: u32 = 20;
/// 格子里「碰到或挡路的是第几件」用的字符。
const DIGITS: &[u8] = b"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

/// 按场景包模型表放置道具；没有场景包时全部用通用模型与默认占地。
#[derive(Clone, Default)]
pub struct ScenePlacer {
    models: BTreeMap<String, ModelSpec>,
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
        let site = Site::new(
            s,
            &prop.locale,
            &request.obstacles,
            &request.occupied,
            request.stand,
        )?;
        let (model, size) = self.model(prop);
        let item = Item {
            id: &prop.id,
            locale: &prop.locale,
            model,
            size,
        };
        let pp = find_free_position(s, &site, &item, request.near).ok_or_else(|| {
            KernelError::Navigation("没有不阻挡人物、家具和既有通路的放置位置".into())
        })?;
        let route = walk_route(s, site.floor, site.arrival, prop, &pp)?;
        Ok(kernel::navigation::space::Override { prop: pp, route })
    }

    fn grid(
        &self,
        s: &Space,
        locale: &str,
        obstacles: &[&PropPosition],
        stand: &dyn Fn([f64; 2]) -> bool,
    ) -> Option<PlaceGrid> {
        let mut site = Site::new(s, locale, obstacles, &[], stand).ok()?;
        let item = Item {
            id: "",
            locale,
            model: "generic".into(),
            size: [DEFAULT_FOOTPRINT, DEFAULT_FOOTPRINT],
        };
        let spots = Spots::new(&site.floor.bounds, item.size);
        let mut cells = String::with_capacity(spots.len());
        let mut by = String::with_capacity(spots.len());
        let mut free = Vec::new();
        for at in spots.iter() {
            let (code, who) = match site.try_spot(s, &item, at) {
                // 格子不算人（occupied 是空的）：人会走开，真放时放置器再让开站着的人
                Ok(_) | Err(Blocked::Person) => {
                    free.push(at);
                    ('.', None)
                }
                Err(Blocked::Entrance) => ('a', None),
                Err(Blocked::Prop(i)) => ('p', Some(i)),
                Err(Blocked::Route) => ('r', None),
                Err(Blocked::Path(i)) => ('b', i),
                Err(Blocked::Steep) => ('s', None),
                Err(Blocked::Stand) => ('w', None),
            };
            cells.push(code);
            by.push(who.and_then(|i| DIGITS.get(i)).map_or('-', |&d| d as char));
        }
        // 还能放几件：照不指定位置时的挑法从第一格起一件件放，每放一件就加上它和它从入口过来的路。
        // 放过的格子之前的格子都已经放不下，往后只会更挤，所以顺着扫一遍就够。
        let mut room = 0;
        for at in free {
            if room == ROOM_LIMIT {
                break;
            }
            if let Ok(pp) = site.try_spot(s, &item, at) {
                room += 1;
                site.obstacles.push(footprint(&pp, OBSTACLE_PAD));
                site.routes.push(vec![site.arrival.position, pp.anchor]);
            }
        }
        let entrance = site.arrival.position;
        Some(PlaceGrid {
            by,
            cells,
            columns: spots.columns as u32,
            entrance: [entrance[0], entrance[2]],
            entrance_clearance: MIN_ARRIVAL_DISTANCE,
            locale: locale.into(),
            origin: spots.origin,
            props: obstacles.iter().map(|p| p.id.clone()).collect(),
            room,
            room_capped: room == ROOM_LIMIT,
            rows: spots.rows as u32,
            size: item.size,
            step: GRID_STEP,
        })
    }
}

/// 要放的东西：编号、地点、模型和占地；位置由 `Site::try_spot` 定。
struct Item<'a> {
    id: &'a str,
    locale: &'a str,
    model: String,
    size: [f64; 2],
}

/// 一格为什么放不下，按检查的先后取第一条。
enum Blocked {
    /// 离地点入口太近
    Entrance,
    /// 有人站在这里
    Person,
    /// 碰到第几件家具
    Prop(usize),
    /// 压着路
    Route,
    /// 从入口到操作点的路被第几件家具挡住；None 是要穿过这件自己
    Path(Option<usize>),
    /// 从入口过来的坡太陡
    Steep,
    /// 用道具的人站不到操作锚点上（落在行走地图的可走格子外）
    Stand,
}

/// 放置搜索的固定输入：区域、入口、既有障碍与人物位置，以及经过区域的路。
struct Site<'a> {
    floor: &'a Floor,
    arrival: &'a StationPosition,
    obstacles: Vec<Bounds>,
    occupied: &'a [Point],
    /// 和区域有交集的路的折点。道具连同留白都在区域里，碰不到区域的路也碰不到它，先筛掉。
    routes: Vec<Vec<Point>>,
    /// 人能不能站在这一点（见 `PlacementRequest::stand`）
    stand: &'a dyn Fn([f64; 2]) -> bool,
}

impl<'a> Site<'a> {
    fn new(
        s: &'a Space,
        locale: &str,
        obstacles: &[&PropPosition],
        occupied: &'a [Point],
        stand: &'a dyn Fn([f64; 2]) -> bool,
    ) -> Result<Self, KernelError> {
        let floor = s
            .floor(locale)
            .ok_or_else(|| KernelError::Navigation("缺少可放置区域".into()))?;
        let routes = s
            .all_routes()
            .filter(|r| touches(&r.points, &floor.bounds))
            .map(|r| r.points.clone())
            .collect();
        Ok(Self {
            floor,
            arrival: s
                .arrival(locale)
                .ok_or_else(|| KernelError::Navigation("地点没有空间入口".into()))?,
            obstacles: obstacles
                .iter()
                .map(|p| footprint(p, OBSTACLE_PAD))
                .collect(),
            occupied,
            routes,
            stand,
        })
    }

    /// 把这件放在格点 [x, z] 上试试。操作锚点默认在南边（正对镜头）；入口在北边时，走到南边的锚点
    /// 要穿过道具本身，就换到北边。两边都不行时给出南边那次的原因。
    fn try_spot(&self, s: &Space, item: &Item, [x, z]: [f64; 2]) -> Result<PropPosition, Blocked> {
        let [w, depth] = item.size;
        let y = s.height_at(x, z, self.arrival.position[1]);
        let mut first = None;
        for (side, yaw) in [(1., 0.), (-1., std::f64::consts::PI)] {
            let az = z + side * (depth / 2. + ANCHOR_OFFSET);
            let pp = PropPosition {
                id: item.id.into(),
                locale: item.locale.into(),
                model: item.model.clone(),
                position: [x, y, z],
                anchor: [x, s.height_at(x, az, y), az],
                yaw,
                footprint: [w, depth],
            };
            match self.check(s, &pp) {
                Ok(()) => return Ok(pp),
                Err(why) => {
                    first.get_or_insert(why);
                }
            }
        }
        Err(first.expect("两边都试过"))
    }

    fn check(&self, s: &Space, pp: &PropPosition) -> Result<(), Blocked> {
        let r = footprint(pp, PLACEMENT_PAD);
        let arrival = self.arrival.position;
        if distance(arrival, pp.position) < MIN_ARRIVAL_DISTANCE {
            return Err(Blocked::Entrance);
        }
        if self.occupied.iter().any(|p| r.contains(*p)) {
            return Err(Blocked::Person);
        }
        if let Some(i) = self.obstacles.iter().position(|o| r.overlaps(o)) {
            return Err(Blocked::Prop(i));
        }
        if self
            .routes
            .iter()
            .any(|route| route.windows(2).any(|p| intersects(p[0], p[1], &r)))
        {
            return Err(Blocked::Route);
        }
        if !(self.stand)([pp.anchor[0], pp.anchor[2]]) {
            return Err(Blocked::Stand);
        }
        if let Some(i) = self
            .obstacles
            .iter()
            .position(|o| intersects(arrival, pp.anchor, o))
        {
            return Err(Blocked::Path(Some(i)));
        }
        if intersects(arrival, pp.anchor, &footprint(pp, ANCHOR_PATH_PAD)) {
            return Err(Blocked::Path(None));
        }
        if too_steep(&walk_points(s, self.arrival, pp)) {
            return Err(Blocked::Steep);
        }
        Ok(())
    }
}

/// 折点的外框和区域有没有交集（x/z 平面）。
fn touches(points: &[Point], b: &Bounds) -> bool {
    let (mut x0, mut x1, mut z0, mut z1) = (f64::MAX, f64::MIN, f64::MAX, f64::MIN);
    for p in points {
        x0 = x0.min(p[0]);
        x1 = x1.max(p[0]);
        z0 = z0.min(p[2]);
        z1 = z1.max(p[2]);
    }
    x0 <= b.x + b.w && x1 >= b.x && z0 <= b.y + b.h && z1 >= b.y
}

/// 区域里的候选格点，逐行排：离四边留白，最后一行离下边多留 1 米。
struct Spots {
    origin: [f64; 2],
    columns: usize,
    rows: usize,
}

impl Spots {
    fn new(b: &Bounds, [w, depth]: [f64; 2]) -> Self {
        let origin = [b.x + w / 2. + FLOOR_MARGIN, b.y + depth / 2. + FLOOR_MARGIN];
        let rows = (0..GRID_CELLS)
            .take_while(|&row| origin[1] + row as f64 * GRID_STEP <= b.y + b.h - depth / 2. - 1.)
            .count();
        let columns = (0..GRID_CELLS)
            .take_while(|&col| {
                origin[0] + col as f64 * GRID_STEP <= b.x + b.w - w / 2. - FLOOR_MARGIN
            })
            .count();
        Self {
            origin,
            columns,
            rows,
        }
    }

    fn len(&self) -> usize {
        self.columns * self.rows
    }

    fn iter(&self) -> impl Iterator<Item = [f64; 2]> + '_ {
        (0..self.len()).map(|i| {
            [
                self.origin[0] + (i % self.columns) as f64 * GRID_STEP,
                self.origin[1] + (i / self.columns) as f64 * GRID_STEP,
            ]
        })
    }
}

/// 在区域的格点里取第一个放得下的位置：玩家点了位置就从离它最近的格点试起，
/// 否则从区域一角一行行扫过去。
fn find_free_position(
    s: &Space,
    site: &Site,
    item: &Item,
    near: Option<[f64; 2]>,
) -> Option<PropPosition> {
    let mut spots: Vec<_> = Spots::new(&site.floor.bounds, item.size).iter().collect();
    if let Some([nx, nz]) = near {
        let away = |[x, z]: [f64; 2]| (x - nx).hypot(z - nz);
        spots.sort_by(|a, b| away(*a).total_cmp(&away(*b)));
    }
    spots
        .into_iter()
        .find_map(|at| site.try_spot(s, item, at).ok())
}

/// 入口到操作锚点的直线，折点贴地形。
fn walk_points(s: &Space, arrival: &StationPosition, pp: &PropPosition) -> Vec<Point> {
    let count = (distance(arrival.position, pp.anchor) / ROUTE_POINT_SPACING)
        .ceil()
        .max(1.) as usize;
    (0..=count)
        .map(|i| {
            let f = i as f64 / count as f64;
            let mut p: Point = std::array::from_fn(|j| {
                arrival.position[j] + (pp.anchor[j] - arrival.position[j]) * f
            });
            p[1] = s.height_at(p[0], p[2], p[1]);
            p
        })
        .collect()
}

/// 入口到操作锚点的直线通路；坡度超限则失败（找空位时已经避开了太陡的格子）。
fn walk_route(
    s: &Space,
    floor: &Floor,
    arrival: &StationPosition,
    prop: &Prop,
    pp: &PropPosition,
) -> Result<Route, KernelError> {
    let points = walk_points(s, arrival, pp);
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// 8×6 米的一块营地：东北角是入口，正中偏东有一只桶，南边横着一条路。
    fn camp() -> Space {
        serde_json::from_value(json!({
            "navigation_revision": 1,
            "floors": [{"id": "camp", "bounds": {"x": 0, "y": 0, "w": 8, "h": 6}, "indoor": false}],
            "props": [{"id": "barrel", "locale": "camp", "model": "generic",
                "position": [5.2, 0, 2.2], "anchor": [5.2, 0, 3], "yaw": 0, "footprint": [0.65, 0.65]}],
            "routes": [{"id": "path", "from": "a", "to": "b", "from_locale": "camp", "to_locale": "camp",
                "width": 1, "points": [[0, 0, 4.2], [8, 0, 4.2]], "length": 8, "minutes": 0.1, "indoor": false}],
            "stations": [{"id": "at_camp", "locale": "camp", "position": [7.4, 0, 0.6]}],
        }))
        .unwrap()
    }

    /// 摆道具界面靠这一条：格子说能放的格，点上去就落在那一格；说放不下的格，会落到别处。
    #[test]
    fn a_free_cell_on_the_grid_is_exactly_where_a_placement_near_it_lands() {
        let s = camp();
        let placer = ScenePlacer::default();
        let obstacles: Vec<_> = s.props.iter().collect();
        // 西边 1.6 米宽的一条不在可走格子上：操作锚点落在那里的格子放不下（w）
        let stand = |p: [f64; 2]| p[0] >= 1.6;
        let grid = placer.grid(&s, "camp", &obstacles, &stand).unwrap();
        for code in ['.', 'a', 'p', 'r', 'b', 'w'] {
            assert!(grid.cells.contains(code), "缺 {code}：{}", grid.cells);
        }
        assert!(grid.room > 0 && !grid.room_capped);
        let prop: Prop = serde_json::from_value(
            json!({"id": "user:box", "name": "箱子", "locale": "camp", "verbs": []}),
        )
        .unwrap();
        let columns = grid.columns as usize;
        for (i, code) in grid.cells.chars().enumerate() {
            let at = [
                grid.origin[0] + (i % columns) as f64 * grid.step,
                grid.origin[1] + (i / columns) as f64 * grid.step,
            ];
            let request = PlacementRequest {
                prop: &prop,
                obstacles: obstacles.clone(),
                occupied: Vec::new(),
                near: Some(at),
                stand: &stand,
            };
            let placed = placer.plan(&s, &request).unwrap().prop;
            let landed = [placed.position[0], placed.position[2]];
            assert_eq!(
                code == '.',
                landed == at,
                "第 {i} 格 {code}：落在 {landed:?}"
            );
            // 碰到桶的格子记着是桶；被挡路的记着是桶，或者是要穿过自己（'-'）
            match code {
                'p' => assert_eq!(grid.by.as_bytes()[i], b'0', "第 {i} 格"),
                'b' => assert!(b"0-".contains(&grid.by.as_bytes()[i]), "第 {i} 格"),
                _ => assert_eq!(grid.by.as_bytes()[i], b'-', "第 {i} 格"),
            }
        }
    }
}
