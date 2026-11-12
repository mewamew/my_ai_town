//! 内置模型的下载线程：玩家点了下载（或页面自己接着下）时起一个，下完、暂停或停在出错上就结束。
//! 下载本身在 host::builtin_store。
use crate::creation::load_app;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

#[derive(Default)]
pub struct Downloads {
    running: Arc<AtomicBool>,
}

impl Downloads {
    /// 没有下载线程在跑就起一个；已经有了就由它接着下（它每秒都重读要下哪一版）。
    pub fn ensure(&self, config: &Path) {
        if self.running.swap(true, Ordering::SeqCst) {
            return;
        }
        let running = self.running.clone();
        let config: PathBuf = config.to_path_buf();
        std::thread::spawn(move || {
            match load_app(&config) {
                Ok(app) => host::builtin_store::work(&app),
                Err(e) => eprintln!("[town-manager] 内置模型下载没能开始：{}", e.message),
            }
            running.store(false, Ordering::SeqCst);
        });
    }
}
