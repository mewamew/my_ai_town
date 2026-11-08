//! 精确导航地图上运行时放置的道具：位置、占地与从地点入口过去的通路。
//! 既写进存档，也随修订号发给客户端。
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

/// 米制三维坐标（x、高度、z）。
pub type Point3 = [f64; 3];

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PropPosition {
    pub id: String,
    pub locale: String,
    pub model: String,
    pub position: Point3,
    pub anchor: Point3,
    pub yaw: f64,
    pub footprint: [f64; 2],
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Route {
    pub id: String,
    pub from: String,
    pub to: String,
    pub from_locale: String,
    pub to_locale: String,
    pub width: f64,
    pub points: Vec<Point3>,
    pub length: f64,
    pub minutes: f64,
    pub indoor: bool,
    #[serde(default)]
    pub owner: Option<String>,
}

/// 一件运行时道具的位置与它的通路。
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SpatialOverride {
    pub prop: PropPosition,
    pub route: Route,
}

/// 运行期空间覆盖与已移除道具，随导航修订号一起给客户端。
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SpatialOverridesView {
    #[serde(serialize_with = "crate::sorted")]
    pub overrides: Vec<SpatialOverride>,
    pub removed: BTreeSet<String>,
    pub revision: u64,
}

/// 摆道具界面画「哪里能放」用的一个地点的格子：放置器找空位时逐个试的就是这些格点，
/// 这里按没有专门模型的道具的占地试过一遍。只回给发问的页面，不进存档。字段按字母序。
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct PlaceGrid {
    /// 和 cells 逐格对应：`p`、`b` 格碰到或挡了路的是 props 里第几件（`0-9a-zA-Z`），其余是 `-`。
    pub by: String,
    /// 逐行、每格一个字符：`.` 能放；`a` 离入口太近；`p` 碰到已有的东西；`r` 压着路；
    /// `b` 从入口走过来会被挡住；`s` 从入口过来的坡太陡；`w` 用的人站不到它跟前。
    pub cells: String,
    pub columns: u32,
    /// 地点入口（米：x 与地面上的 z）和入口周围不能放的半径。
    pub entrance: [f64; 2],
    pub entrance_clearance: f64,
    pub locale: String,
    /// 第一格（第一行第一个）的中心，米。
    pub origin: [f64; 2],
    /// by 里的序号对应的道具编号。
    pub props: Vec<String>,
    /// 照放置器不指定位置时的挑法一件件往里放，还能放几件；room_capped 时是算到这里就停了，实际更多。
    pub room: u32,
    pub room_capped: bool,
    pub rows: u32,
    /// 试格子用的占地（米）。
    pub size: [f64; 2],
    /// 相邻格点的间距（米）。
    pub step: f64,
}
