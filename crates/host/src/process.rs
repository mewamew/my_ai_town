//! 同一存档只允许一个写入者；退出信号只设标记，由主循环完成保存。
//! 子进程和平台相关的几件事（看进程还在不在、不弹控制台、跟着本进程结束）也在这里。
use std::{
    fs::File,
    io::{self, Read},
    sync::atomic::{AtomicBool, Ordering},
};

static STOP: AtomicBool = AtomicBool::new(false);

pub fn stopping() -> bool {
    STOP.load(Ordering::Relaxed)
}

/// 由管理进程启动时使用：管理进程握着本进程 stdin 的写端且从不写入，它一旦退出（包括被
/// SIGKILL），管道关闭、这里读到 EOF，走与 SIGTERM 相同的保存退出流程，不留孤儿进程。
pub fn stop_when_stdin_closes() {
    std::thread::spawn(|| {
        let mut sink = [0u8; 256];
        let mut stdin = io::stdin().lock();
        while matches!(stdin.read(&mut sink), Ok(n) if n > 0) {}
        eprintln!("[host] 标准输入已关闭，按父进程退出处理：保存后退出");
        STOP.store(true, Ordering::Relaxed);
    });
}

#[cfg(unix)]
extern "C" fn stop_signal(_: libc::c_int) {
    STOP.store(true, Ordering::Relaxed);
}

#[cfg(unix)]
pub fn install_shutdown_handler() -> io::Result<()> {
    // 处理器只写 lock-free AtomicBool；不分配、不做文件 I/O、不取得锁。
    for signal in [libc::SIGINT, libc::SIGTERM] {
        if unsafe { libc::signal(signal, stop_signal as libc::sighandler_t) } == libc::SIG_ERR {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}

/// 独占一个锁文件，别的进程和本进程的其他线程（各自打开的句柄）都要等它放开。wait 为假时，
/// 别人占着就马上报错。
#[cfg(unix)]
pub(crate) fn lock_file(file: &File, wait: bool) -> io::Result<()> {
    use std::os::fd::AsRawFd;
    let operation = if wait {
        libc::LOCK_EX
    } else {
        libc::LOCK_EX | libc::LOCK_NB
    };
    // flock 随文件句柄释放；进程崩溃后不会留下无法恢复的占用。
    loop {
        if unsafe { libc::flock(file.as_raw_fd(), operation) } == 0 {
            return Ok(());
        }
        let error = io::Error::last_os_error();
        // 等锁的时候收到信号会提前返回，接着等
        if error.kind() != io::ErrorKind::Interrupted {
            return Err(error);
        }
    }
}

#[cfg(not(unix))]
pub fn install_shutdown_handler() -> io::Result<()> {
    Ok(())
}

#[cfg(windows)]
pub(crate) fn lock_file(file: &File, wait: bool) -> io::Result<()> {
    use std::os::windows::io::AsRawHandle;
    use windows_sys::Win32::Storage::FileSystem::{
        LockFileEx, LOCKFILE_EXCLUSIVE_LOCK, LOCKFILE_FAIL_IMMEDIATELY,
    };
    // 和 flock 一样随文件句柄释放。锁的是旁边单独的 .lock 文件，不挡读写存档和配置本身。
    // 句柄不是异步打开的，不带 LOCKFILE_FAIL_IMMEDIATELY 时一直等到拿到锁。
    let mut overlapped = unsafe { std::mem::zeroed() };
    let flags = if wait {
        LOCKFILE_EXCLUSIVE_LOCK
    } else {
        LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY
    };
    let handle = file.as_raw_handle() as isize;
    if unsafe { LockFileEx(handle, flags, 0, u32::MAX, u32::MAX, &mut overlapped) } == 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

/// 这个进程号还在运行（管理服务看占着数据目录的上一个自己退出没有）。
#[cfg(unix)]
pub fn still_running(pid: u32) -> bool {
    unsafe { libc::kill(pid as libc::pid_t, 0) == 0 }
}

/// Windows 回收进程号很快，断电重启后旧号多半已经给了别的程序：还要核对是不是同一个程序，
/// 不然会一直以为上一个还开着。
#[cfg(windows)]
pub fn still_running(pid: u32) -> bool {
    use std::{ffi::OsString, os::windows::ffi::OsStringExt, path::Path};
    use windows_sys::Win32::{
        Foundation::{CloseHandle, STILL_ACTIVE},
        System::Threading::{
            GetExitCodeProcess, OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
            PROCESS_QUERY_LIMITED_INFORMATION,
        },
    };
    let Ok(me) = std::env::current_exe() else {
        return false;
    };
    let process = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) };
    if process == 0 {
        return false;
    }
    let mut code = 0;
    let mut name = [0u16; 1024];
    let mut len = name.len() as u32;
    let running = unsafe {
        GetExitCodeProcess(process, &mut code) != 0
            && code == STILL_ACTIVE as u32
            && QueryFullProcessImageNameW(process, PROCESS_NAME_WIN32, name.as_mut_ptr(), &mut len)
                != 0
    };
    unsafe { CloseHandle(process) };
    let name = OsString::from_wide(&name[..len as usize]);
    let file = |path: &Path| path.file_name().map(|n| n.to_ascii_lowercase());
    running && file(Path::new(&name)) == file(&me)
}

/// 子进程不弹控制台窗口：Windows 版的应用壳没有控制台，它拉起的命令行程序默认会各开一个黑窗口。
pub fn no_console(command: &mut std::process::Command) -> &mut std::process::Command {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(windows_sys::Win32::System::Threading::CREATE_NO_WINDOW);
    }
    command
}

/// 把子进程放进一个作业：返回的句柄一关，里面的进程就被结束。本进程不管怎样退出（含被强杀），
/// 系统都会关掉这个句柄，子进程不会留下来。unix 上靠管道看父进程，Windows 用这个。
#[cfg(windows)]
pub fn end_with_handle(
    child: &std::process::Child,
) -> io::Result<std::os::windows::io::OwnedHandle> {
    use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
    use windows_sys::Win32::System::JobObjects::{
        AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
        SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
    };
    let job = unsafe { CreateJobObjectW(std::ptr::null(), std::ptr::null()) };
    if job == 0 {
        return Err(io::Error::last_os_error());
    }
    let owned = unsafe { OwnedHandle::from_raw_handle(job as _) };
    let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = unsafe { std::mem::zeroed() };
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    let set = unsafe {
        SetInformationJobObject(
            job,
            JobObjectExtendedLimitInformation,
            &limits as *const _ as *const _,
            std::mem::size_of_val(&limits) as u32,
        )
    };
    if set == 0 || unsafe { AssignProcessToJobObject(job, child.as_raw_handle() as isize) } == 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(owned)
}
