//! host 集成测试的唯一入口：所有用例共用 support 夹具，起进程经同一把串行锁选端口。
//! 只有 content 读仓库里发布的地图、道具库与村民库，其余用例都用 tests/fixtures 下的夹具。
mod support;

mod agent_trace;
mod avatar;
mod commands;
mod content;
mod network;
mod persistence;
mod population;
mod possession;
mod recording;
mod resident_files;
mod resident_host;
mod world_settings;

mod weather;
