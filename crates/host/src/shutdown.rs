//! 管理进程专用的关闭通道，不进入玩家 WebSocket 协议。口令与玩家连接口令分开，
//! 每次启动都重建；请求到主循环后才保存。单字节回执只代表保存结果，管理方还必须等正常退出。
use std::{
    io::{self, Read, Write},
    net::{Ipv4Addr, SocketAddr, TcpListener, TcpStream},
    sync::mpsc::{self, Receiver},
    time::Duration,
};

const PREFIX: &[u8] = b"town-save-and-close-v1\n";
const IO_TIMEOUT: Duration = Duration::from_secs(1);

pub struct Control {
    pub port: u16,
    requests: Receiver<TcpStream>,
}

impl Control {
    pub fn listen(token: String) -> io::Result<Self> {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0))?;
        let port = listener.local_addr()?.port();
        // 至多一个待处理请求；主循环写盘卡住时不积攒线程或请求。
        let (send, requests) = mpsc::sync_channel(1);
        std::thread::spawn(move || {
            let expected = [PREFIX, token.as_bytes()].concat();
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { break };
                if stream.set_read_timeout(Some(IO_TIMEOUT)).is_err()
                    || stream.set_write_timeout(Some(IO_TIMEOUT)).is_err()
                {
                    continue;
                }
                let mut request = vec![0; expected.len()];
                if stream.read_exact(&mut request).is_ok() && request == expected {
                    let _ = send.try_send(stream);
                }
            }
        });
        Ok(Self { port, requests })
    }

    pub fn next(&self) -> Option<TcpStream> {
        self.requests.try_recv().ok()
    }
}

/// 连接、握手、回执都有界；超时后调用方保留连接，重试仍等同一次关闭，不能误收旧回执。
pub fn request(port: u16, token: &str) -> io::Result<TcpStream> {
    let address = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let mut stream = TcpStream::connect_timeout(&address, IO_TIMEOUT)?;
    stream.set_write_timeout(Some(IO_TIMEOUT))?;
    stream.set_read_timeout(Some(Duration::from_millis(50)))?;
    stream.write_all(&[PREFIX, token.as_bytes()].concat())?;
    Ok(stream)
}

pub fn reply(stream: &mut TcpStream, saved: bool) -> io::Result<()> {
    stream.write_all(if saved { b"S" } else { b"F" })
}

pub fn receive(stream: &mut TcpStream) -> io::Result<Option<bool>> {
    let mut byte = [0];
    match stream.read_exact(&mut byte) {
        Ok(()) => match byte[0] {
            b'S' => Ok(Some(true)),
            b'F' => Ok(Some(false)),
            _ => Err(io::Error::new(io::ErrorKind::InvalidData, "无效关闭回执")),
        },
        Err(e)
            if matches!(
                e.kind(),
                io::ErrorKind::TimedOut | io::ErrorKind::WouldBlock
            ) =>
        {
            Ok(None)
        }
        Err(e) => Err(e),
    }
}
