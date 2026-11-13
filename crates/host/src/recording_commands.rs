//! 录像的开关、列表和删除。怎么录、文件怎么写见 host::recording。
use crate::{
    network::{broadcast, broadcast_event, Clients},
    runtime::{Outcome, Runtime},
};
use host::{
    recording::{self, Reel},
    HostError,
};
use protocol::{EventInfo, ServerMsg};
use std::path::PathBuf;

/// 开新一卷要知道的：小镇目录、小镇编号、地图摘要和地图文件。世界不存档时没有，录不了像。
pub(crate) struct ReelSource {
    pub town_dir: PathBuf,
    pub town_id: Option<String>,
    pub map_hash: String,
    pub map_document: Option<PathBuf>,
}

const NOT_SAVED: &str = "这个世界不存档，录不了像";

impl Runtime {
    /// 世界打开时：先补上上次世界进程意外退出时没收尾的几卷，录像开着就开新的一卷。
    /// 开不了只记日志，世界照常跑。
    pub(crate) fn resume_recording(&self) {
        let Some(source) = &self.reels else {
            return;
        };
        recording::seal_unfinished(&source.town_dir);
        if self.world_settings.recording {
            if let Err(error) = self.start_reel() {
                eprintln!("[host] 录像开不了：{error}");
            }
        }
    }

    /// 收起正在录的一卷（如果有），开新的一卷：开头写上页面开局要的世界设定、道具、人口和名册。
    pub(crate) fn start_reel(&self) -> Result<(), HostError> {
        let Some(source) = &self.reels else {
            return Err(HostError::Rejected(NOT_SAVED.into()));
        };
        let opening = [
            self.world_settings_msg(),
            self.props_message(),
            self.population_msg(),
            self.roster(),
        ];
        self.tape.start(
            Reel {
                town_dir: &source.town_dir,
                town_id: source.town_id.as_deref(),
                world_id: &self.population.world_id,
                map_hash: &source.map_hash,
                map_document: source.map_document.as_deref(),
            },
            &opening,
        )
    }

    /// 打开或关掉录像：开关随存档保存（存不上就撤回），打开时开新的一卷，关掉时收起正在录的。
    /// 不暂停世界，不占世界设定的修订号。回执后广播世界设定和录像列表。
    pub(crate) fn save_recording(&mut self, request_id: String, enabled: bool) -> Outcome {
        let result = if self.reels.is_none() {
            Err(NOT_SAVED.to_string())
        } else {
            self.transact(|rt| {
                rt.world_settings.recording = enabled;
                Ok::<_, HostError>(())
            })
            .map_err(|aborted| aborted.to_string())
            .and_then(|()| {
                let live = self.tape.live().is_some();
                match (enabled, live) {
                    (true, false) => self.start_reel(),
                    (false, true) => self.tape.stop(),
                    _ => Ok(()),
                }
                .map_err(|error| format!("录像开关已保存，但{error}"))
            })
        };
        Outcome::none()
            .and_all(self.world_settings_msg())
            .and_all(self.recordings_msg())
            .and_reply(ServerMsg::WorldSettingsSaved {
                request_id,
                ok: result.is_ok(),
                message: result.err().unwrap_or_else(|| {
                    if enabled {
                        "录像已打开：从现在起录新的一卷".into()
                    } else {
                        "录像已关掉：这一卷收好了，之后发生的事不录".into()
                    }
                }),
            })
    }

    /// 删掉录完的一卷；正在录的删不了。回执后广播录像列表。
    pub(crate) fn delete_recording(&mut self, request_id: String, reel: &str) -> Outcome {
        let result = match (&self.reels, self.tape.live()) {
            (None, _) => Err(NOT_SAVED.to_string()),
            (Some(_), Some(live)) if live.id == reel => {
                Err("正在录的这一卷删不了，先关掉录像".to_string())
            }
            (Some(source), _) => {
                recording::delete(&source.town_dir, reel).map_err(|error| error.to_string())
            }
        };
        if result.is_ok() {
            println!("[host] 删掉一卷录像：{reel}");
        }
        Outcome::none()
            .and_all(self.recordings_msg())
            .and_reply(ServerMsg::WorldSettingsSaved {
                request_id,
                ok: result.is_ok(),
                message: result.err().unwrap_or_else(|| "这一卷录像已删掉".into()),
            })
    }

    /// 录下的几卷（新的在前）和正在录的那一卷。
    pub(crate) fn recordings_msg(&self) -> ServerMsg {
        let live = self.tape.live();
        let id = live.as_ref().map(|l| l.id.clone());
        let reels = match &self.reels {
            Some(source) => recording::list(&source.town_dir, live),
            None => Vec::new(),
        };
        ServerMsg::Recordings { reels, live: id }
    }

    /// 录像写不进去（磁盘满了之类）停下了：写进世界日志，录像列表也跟着更新。
    pub(crate) fn report_tape(&self, clients: &Clients) {
        if let Some(reason) = self.tape.take_failure() {
            broadcast_event(
                clients,
                &self.world,
                format!("录像停了：{reason}"),
                EventInfo::default(),
            );
            broadcast(clients, &self.recordings_msg());
        }
    }
}
