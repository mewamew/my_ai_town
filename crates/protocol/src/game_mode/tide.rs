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
    /// 分出了结果：有人上了船，或者一个人也没剩下
    Over,
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
    /// 这一局的选手（打开时在岛上的人），按入住顺序；旧存档没有
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub players: Vec<TidePlayer>,
    /// 最近的战报，旧的在前
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub news: Vec<TideNews>,
    /// 上了船、活着离开的那个人的编号
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub winner: Option<String>,
    /// 信号弹在哪（船只认它）；这一局没有船票、铁皮匣还没冲上岸时没有
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub flare: Option<TideFlare>,
}

/// 信号弹在哪：全岛只有一枚，第 1 圈公布时装在铁皮匣里冲上岸，船只认它。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "at", rename_all = "snake_case")]
pub enum TideFlare {
    /// 还装在铁皮匣里，没人撬开
    Case,
    /// 在这个人身上；倒下了也还在他身上，等人来搜
    Held { id: String },
    /// 不在谁身上：放在了哪儿（「椰林」的地上、「储物箱」里）
    Left { place: String },
    /// 打出去了（登船时用掉），或者找不到了
    Gone,
}

/// 一位选手：倒下了就写怎么倒下的（「被骆川杀死」「病死」……）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TidePlayer {
    pub id: String,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fell: Option<String>,
}

/// 战报里的一条：世界分钟、哪一类、一句话。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TideNews {
    pub at: f64,
    pub kind: TideNewsKind,
    pub text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TideNewsKind {
    /// 有人对人动了手：推、抢、偷、搜身、拿道具伤人
    Clash,
    /// 有人倒下了
    Fell,
    /// 潮水冲上来一只木箱
    Crate,
    /// 船来了、有人上了船
    Boat,
    /// 信号弹：铁皮匣冲上岸、信号弹换了人
    Flare,
}

/// 给模型看的潮水情况：这一局怎么才算活下来，一句公告，加上自己离水边多远、在不在圈里。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TideContext {
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub goal: String,
    pub notice: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub standing: Option<String>,
    /// 信号弹在谁身上（船只认它）；这一局没有船票时没有
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub flare: Option<String>,
}
