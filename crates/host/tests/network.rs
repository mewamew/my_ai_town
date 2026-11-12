//! 用真实 host 覆盖连接的握手：握手请求晚到的连接照样握得上，它还没握完的时候不挡住别的连接。
use crate::support::*;
use serde_json::json;
use std::{net::TcpStream, thread, time::Duration};

/// 一条连接连上以后隔了一阵才发握手请求（机器忙的时候，连上和发请求之间会隔开几十毫秒）：它照样握得上、
/// 问得到话；它还没发请求的这一阵，别的页面照常连上，不用等它。握手只等 5 毫秒的那阵子，这条连接会被
/// 直接丢掉，管理服务开镇时就报「无法连接世界服务」。
#[test]
fn a_late_handshake_request_still_connects_and_holds_up_nobody() {
    let mut town = Town::new();
    town.persistent = false;
    let first = town.start();
    let address = first.get_ref().peer_addr().unwrap();
    let ask = json!({"type":"get_world_settings"});

    // 连上，先不发握手请求。
    let late = TcpStream::connect(address).unwrap();
    late.set_read_timeout(Some(WAIT)).unwrap();
    thread::sleep(Duration::from_millis(100));
    // 这一阵另一个页面照常连上、问得到话。
    let mut other = connect_again(&first);
    reply(&mut other, ask.clone(), "world_settings");
    // 晚到的握手请求照样握得上，握上以后和别的连接一样用。
    let (mut late, _) =
        tungstenite::client(format!("ws://{address}"), late).expect("握手请求晚到的连接被丢掉了");
    reply(&mut late, ask, "world_settings");
}
