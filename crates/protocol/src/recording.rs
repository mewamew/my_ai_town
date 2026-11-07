//! 录像：小镇目录里录下来的几卷。怎么录、文件怎么写见 host 的 recording.rs。
use serde::{Deserialize, Serialize};

/// 录下来的一卷：从开始录到停的一段。现实时刻是 Unix 毫秒，小镇时间写成时钟。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReelView {
    /// 卷的编号，也是目录名：开始录的 UTC 时刻，如 20261107T023105Z
    pub id: String,
    pub started_at: u64,
    /// 还在录时为空；进程意外退出、没来得及写结束时刻的，按最后写入的时刻算
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ended_at: Option<u64>,
    /// 录到的小镇时间：第一份和最后一份名册的时钟（如 "D2 05:42"）；还没录到名册时为空串
    pub from_clock: String,
    pub to_clock: String,
    /// 占用的字节数
    pub bytes: u64,
}
