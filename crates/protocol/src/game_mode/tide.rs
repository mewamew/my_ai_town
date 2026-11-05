//! 潮水圈（大逃杀式缩圈）的线上形状。坐标是行走地图上的米：x 和地面上的 z。
use serde::{Deserialize, Serialize};

/// 一个圈：圆心和半径（米）。半径为 0 表示缩成了一点。
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct TideCircle {
    pub center: [f64; 2],
    pub radius: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TidePhase {
    /// 刚打开，第一圈还没公布
    Waiting,
    /// 下一圈已公布，还没开始涨
    Announced,
    /// 水边正从上一圈推向下一圈
    Rising,
    /// 涨到了这一圈，等下一次公布
    Holding,
    /// 最后一圈涨完，整座岛没进水里
    Closed,
}

/// 名册里随时间广播的潮水状态，前端按它画水边和下一圈。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TideView {
    /// 此刻的水边：圈外的地被水盖住
    pub edge: TideCircle,
    /// 已公布、还没涨到的下一圈
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next: Option<TideCircle>,
    pub phase: TidePhase,
    /// 公布、上涨、停住时说的是第几圈；还没公布时是 0
    pub ring: u32,
    /// 一共几圈
    pub rings: u32,
}

/// 给模型看的潮水情况：一句公告，加上自己离水边多远、在不在圈里。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TideContext {
    pub notice: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub standing: Option<String>,
}
