//! host 库侧：配置持久化与 LLM 调用通道（可被集成测试引用）。
//! 服务进程入口在 main.rs。

pub mod agent_trace;
pub mod application;
pub mod builtin;
pub mod builtin_store;
pub mod config;
mod error;
pub mod fnv;
pub mod library;
pub mod llm;
pub mod models;
pub mod persistence;
pub mod population;
pub mod process;
pub mod recording;
pub mod tasks;

pub mod agent_worker;

pub mod props;

pub mod world_settings;

pub use error::HostError;

pub mod maps;
