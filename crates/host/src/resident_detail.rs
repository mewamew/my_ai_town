//! 角色卡细节的订阅。名册每拍整份广播，只带画面每拍要用的；一位村民的目标、动作结果、互动和记着的事
//! 有好几 KB，只发给说了在看他的连接（`WatchResident`）：说的那一拍发一份，之后每拍比一下，
//! 变了才再发。细节不是广播，不进录像。
use crate::{
    network::{send_to, Clients},
    runtime::{Outcome, Runtime},
};
use protocol::{ResidentDetailView, ServerMsg};
use std::collections::BTreeMap;

/// 各连接在看谁。不存档；连接断开时清掉，页面重连后自己再说一遍。
#[derive(Default)]
pub(crate) struct Watchers(BTreeMap<u64, Watch>);

struct Watch {
    resident: String,
    /// 上次发给这条连接的细节；还没发过是 None，发过「这位没有细节」是 Some(None)。
    sent: Option<Option<ResidentDetailView>>,
}

impl Watchers {
    /// 连接断了：不再给它算。
    pub(crate) fn forget(&mut self, connection: u64) {
        self.0.remove(&connection);
    }
}

impl Runtime {
    /// 这条连接改看这一位（重复说同一位会再发一份完整的）；不带编号是不看了。
    /// 镇上没有的编号不记，直接回一份没有细节的。
    pub(crate) fn watch_resident(&mut self, connection: u64, resident: Option<String>) -> Outcome {
        self.watchers.forget(connection);
        match resident {
            Some(resident) if self.population.residents.contains_key(&resident) => {
                let watch = Watch {
                    resident,
                    sent: None,
                };
                self.watchers.0.insert(connection, watch);
                // 第一份由这一拍的 publish_details 发出：命令都在同一拍的推进之前处理
                Outcome::none()
            }
            Some(resident_id) => Outcome::reply(ServerMsg::ResidentDetail {
                resident_id,
                detail: None,
            }),
            None => Outcome::none(),
        }
    }

    /// 每拍在名册之后：在看的连接各比一次，和上次发的不一样才发。
    pub(crate) fn publish_details(&mut self, clients: &Clients) {
        for (connection, watch) in &mut self.watchers.0 {
            let detail = self.driver.runtime.detail(&self.world, &watch.resident);
            if watch.sent.as_ref() == Some(&detail) {
                continue;
            }
            send_to(
                clients,
                *connection,
                &ServerMsg::ResidentDetail {
                    resident_id: watch.resident.clone(),
                    detail: detail.clone(),
                },
            );
            watch.sent = Some(detail);
        }
    }
}
