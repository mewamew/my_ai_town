//! kernel 集成测试的唯一入口：所有用例共用 common 夹具，编成一个测试二进制。
mod common;

mod agent_actions;
mod avatar;
mod harm;
mod interactions;
mod inventory;
mod island;
mod physiology;
mod precise_navigation;
mod props;
mod readable_props;
mod temporal_integrity;
mod weather;
