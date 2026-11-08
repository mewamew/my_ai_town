//! 移动是动作生命周期的一部分。路线由已校验的地图几何编译而来。
use crate::error::{KernelError, Result};
use crate::{avatar::WalkMap, intent::Intent, topology::Prop, World};
use protocol::{At, PlaceNear};
use space::{Override, PlacementRequest, MAX_OVERRIDES};

pub(crate) mod follow;
pub mod free;
pub mod space;

/// 新通路的时长按行走地图的步行速度核对；有空间地图的世界都带行走地图。
pub(crate) fn walk_speed(map: Option<&WalkMap>) -> Result<f64> {
    map.map(|m| m.metres_per_minute)
        .ok_or_else(|| KernelError::navigation("缺少行走地图，不能核对通路时长"))
}

/// 精确导航下，道具动作和停留要先走到落脚点；返回 (处所, 落脚点)。
pub(crate) fn approach_station(
    w: &World,
    id: &str,
    intent: &Intent,
    prop: Option<&str>,
) -> Option<(String, String)> {
    if !w.topo.precise_navigation || w.actors[id].player_controlled() {
        return None;
    }
    let actor = &w.actors[id];
    let station = match intent {
        Intent::Do { verb, station, .. } => {
            let prop = prop.map(str::to_owned).or_else(|| {
                w.affordances
                    .spot(&actor.locus.locale, verb)
                    .map(|s| s.prop.clone())
            });
            if prop.as_ref().is_some_and(|p| w.inventory.carried_by(p, id)) {
                return None;
            }
            prop.and_then(|p| w.inventory.item_station(&w.topo, id, &p))
                .or_else(|| station.clone())
        }
        Intent::Stay { station, .. } => station.clone(),
        Intent::Goto { .. }
        | Intent::Look
        | Intent::Force { .. }
        | Intent::Search
        | Intent::Hide => None,
    }?;
    let target = w.topo.stations.get(&station)?;
    Some((target.locale.clone(), station))
}

pub(crate) fn at_station(actor: &crate::actor::Actor, station: &str) -> bool {
    matches!(&actor.locus.at, At::Station { station: current } if current == station)
}

/// 新放置的道具在空间地图上的位置与通路：由 host 的放置器计算；没有空间地图时不需要。
/// 空间地图全图一个坐标系，near 的 space 不用看。
pub(crate) fn plan_override(
    w: &World,
    prop: &Prop,
    near: Option<&PlaceNear>,
) -> Result<Option<Override>> {
    let Some(s) = &w.topo.navigation else {
        return Ok(None);
    };
    if s.overrides.contains_key(&prop.id) {
        return Ok(None);
    }
    ensure!(
        s.overrides.len() < MAX_OVERRIDES,
        KernelError::navigation(format!("运行时空间道具已达 {MAX_OVERRIDES} 件上限"))
    );
    let placer = w
        .placer
        .as_ref()
        .ok_or_else(|| KernelError::navigation("缺少空间放置器，不能放置道具"))?;
    let stand = stand_check(w, &prop.locale);
    let request = PlacementRequest {
        prop,
        obstacles: obstacles(w, s, &prop.locale),
        occupied: w
            .actors
            .values()
            .filter_map(|a| w.topo.point(&a.locus.locale, &a.locus.at))
            .collect(),
        near: near.map(|n| n.position),
        stand: &stand,
    };
    placer.plan(s, &request).map(Some)
}

/// 人能不能站在 locale 里的这一点（水平面 x、z，米）：有行走地图时要落在可走格子上、人物半径内
/// 没有出界，没有行走地图时都能站。放置器用它挑操作锚点：锚点落在可走格子外，用道具的人走过去就
/// 停在区域外，之后哪儿也去不了（大逃杀第二局）。
fn stand_check<'a>(w: &'a World, locale: &str) -> impl Fn([f64; 2]) -> bool + 'a {
    let space = w.walk_map.as_ref().map(|m| m.space_of(locale).to_string());
    move |p| match (&w.walk_map, &space) {
        (Some(m), Some(space)) => m.clear(space, p, &[], crate::avatar::RADIUS),
        _ => true,
    }
}

/// 放东西时要让开的家具：同一地点里还摆在地图上的道具（收进背包或容器的不算）。
fn obstacles<'a>(w: &World, s: &'a space::Space, locale: &str) -> Vec<&'a protocol::PropPosition> {
    s.props
        .iter()
        .chain(s.overrides.values().map(|v| &v.prop))
        .filter(|p| {
            p.locale == locale
                && w.inventory.on_map(&w.props, &p.id)
                && w.inventory.location(&p.id).is_none()
        })
        .collect()
}

/// 各个能放东西的地点的格子，给摆道具界面画「哪里能放」；规则和真放时找空位是同一套。
/// 没有空间地图或放置器时为空。
pub(crate) fn placement_grids(w: &World) -> Vec<protocol::PlaceGrid> {
    let (Some(s), Some(placer)) = (&w.topo.navigation, &w.placer) else {
        return Vec::new();
    };
    s.floors
        .iter()
        .filter(|f| w.topo.is_dwell(&f.id))
        .filter_map(|f| placer.grid(s, &f.id, &obstacles(w, s, &f.id), &stand_check(w, &f.id)))
        .collect()
}
