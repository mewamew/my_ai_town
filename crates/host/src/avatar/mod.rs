//! 化身与附身：连接的控制租约、命令事务、方向输入、每拍的超时处理、发给控制者的状态。
//! 网络层不处理世界规则，世界规则在内核。
mod command;
mod input;
mod lease;
mod tick;
mod view;

use crate::{
    network::{self, Clients, NetworkEvent},
    runtime::Runtime,
};
use command::{AvatarFailure, AvatarRequest};
use lease::Lease;
use protocol::{ClientMsg, ServerMsg};
use std::time::{Duration, Instant};

/// 每个世界一份：谁在控制、最近的方向输入、交谈轮到玩家后等了多久。不存档。
#[derive(Clone, Default)]
pub(crate) struct Control {
    lease: Option<Lease>,
    direction: [f64; 2],
    /// 最近的方向输入按住了奔跑键。
    run: bool,
    input_sequence: u64,
    input_at: Option<Instant>,
    /// 化身已经按方向输入走到了哪一刻：下一段从这里算起（见 tick.rs 的 advance_avatar）。
    moved_at: Option<Instant>,
    /// 轮到玩家发言的聊天、当时的动作版本与已等待的时长。
    turn: Option<(String, u64, Duration)>,
    last_tick: Option<Instant>,
}

impl Control {
    fn halt(&mut self) {
        self.direction = [0., 0.];
    }
    /// 有人在控制化身或附身的村民（含断线后的恢复窗口）。
    pub(crate) fn held(&self) -> bool {
        self.lease.is_some()
    }
}

impl Runtime {
    pub(crate) fn network_command(&mut self, event: NetworkEvent, clients: &Clients) {
        match event {
            NetworkEvent::Disconnected(id) => {
                self.watchers.forget(id);
                if let Some(lease) = self
                    .avatar_control
                    .lease
                    .as_mut()
                    .filter(|l| l.connection == id)
                {
                    lease.disconnect(Instant::now());
                    self.avatar_control.halt();
                    // 存盘失败由检查点自己记日志；断线本身不需要回执。
                    let _ = self.checkpoint(true);
                }
            }
            NetworkEvent::Command {
                connection,
                message,
            } => match *message {
                ClientMsg::Avatar {
                    world_id,
                    request_id,
                    epoch,
                    sequence,
                    command,
                } => self.avatar_command(
                    connection,
                    AvatarRequest {
                        world_id,
                        request_id,
                        epoch,
                        sequence,
                        command,
                    },
                    clients,
                ),
                message @ ClientMsg::AvatarInput { .. } => {
                    self.avatar_input(connection, message, Instant::now())
                }
                other => self.command(connection, other, clients),
            },
        }
    }

    /// 命令或输入带的控制代次必须是这个连接当前在线的租约。
    fn check_control(&self, connection: u64, epoch: &str) -> Result<(), AvatarFailure> {
        if self
            .avatar_control
            .lease
            .as_ref()
            .is_some_and(|l| l.admits(connection, epoch))
        {
            Ok(())
        } else {
            Err(AvatarFailure::ControlLost("你离开了一会儿，已自动退出控制"))
        }
    }

    /// 授予新租约：之前的输入、位置上报与交谈等待都清掉，内核记下新的控制代次。
    fn grant_control(&mut self, connection: u64) {
        let lease = Lease::grant(connection);
        self.world.avatar_control_epoch(lease.epoch.clone());
        self.avatar_control = Control {
            lease: Some(lease),
            ..Default::default()
        };
    }

    /// 每拍给在线的控制者发一次化身状态。
    pub(crate) fn avatar_publish(&self, clients: &Clients) {
        if let Some(lease) = self.avatar_control.lease.as_ref().filter(|l| l.online()) {
            network::send_to(
                clients,
                lease.connection,
                &ServerMsg::AvatarState {
                    state: self.avatar_session(lease.connection),
                },
            );
        }
    }
}
