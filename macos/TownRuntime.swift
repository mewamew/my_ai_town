import Foundation
import Security

struct TownError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 本机小镇服务：启动包里的 Rust 管理服务（Contents/MacOS/town-manager，由它按需启动世界进程
/// town-host），页面从 127.0.0.1 打开。本类握着管理服务的 stdin：应用无论怎样结束，管道关闭，
/// 管理服务让各世界保存后退出。所有方法都在主线程调用。
final class TownRuntime {
    /// 固定端口：页面的本地存储按来源区分，端口变了偏好与提示状态就丢了。被占用时管理服务往后找。
    private static let port = 47821
    private static let startTimeout: TimeInterval = 20
    /// 退出时等世界保存的上限；超时也放行，管理服务会自己存完再退出
    private static let stopTimeout: TimeInterval = 15

    private var process: Process?
    private var input: FileHandle?
    /// 已经写出就绪文件、页面在用；启动途中退出的由 start 的回调报告，不算意外退出
    private var serving = false
    private var stopWaiters: [() -> Void] = []
    /// 管理服务意外退出（不是本类让它停的）时调用，参数是退出码
    var onUnexpectedExit: ((Int32) -> Void)?

    var running: Bool { process?.isRunning ?? false }

    /// 数据目录与电脑版相同（scripts/data-root.mjs）：两边看到同一批小镇和村民库。
    /// 同一个目录同时只能有一个管理服务，另一个在跑时这边启动会失败并说明原因。
    static var dataRoot: URL {
        if let home = ProcessInfo.processInfo.environment["AI_TOWN_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MyAiTown", isDirectory: true)
    }

    static var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AI小镇/manager.log")
    }

    /// 启动管理服务，等它写出就绪文件，回调带会话口令的首页地址；next 是进门后要去的页面
    func start(next: String? = nil, completion: @escaping (Result<URL, Error>) -> Void) {
        let launched: (Process, URL, String)
        do {
            launched = try launch()
        } catch {
            completion(.failure(error))
            return
        }
        let (process, ready, secret) = launched
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Self.waitReady(process, ready) }.map { port -> URL in
                var parts = URLComponents()
                parts.scheme = "http"
                parts.host = "127.0.0.1"
                parts.port = port
                parts.path = "/__session"
                parts.queryItems = [URLQueryItem(name: "k", value: secret)]
                if let next { parts.queryItems?.append(URLQueryItem(name: "next", value: next)) }
                return parts.url!
            }
            DispatchQueue.main.async { [weak self] in
                if case .success = result, process === self?.process { self?.serving = true }
                completion(result)
            }
        }
    }

    /// 关闭 stdin，管理服务让世界保存后自行退出；退出了（或等到上限）再回调
    func stop(completion: @escaping () -> Void) {
        guard let process, process.isRunning else {
            completion()
            return
        }
        stopWaiters.append(completion)
        if stopWaiters.count > 1 { return }
        try? input?.close()
        input = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopTimeout) { [weak self] in
            self?.finishStop()
        }
    }

    private func launch() throws -> (Process, URL, String) {
        let files = FileManager.default
        let root = Self.dataRoot
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let logURL = Self.logFile
        try files.createDirectory(
            at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !files.fileExists(atPath: logURL.path) {
            files.createFile(atPath: logURL.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logURL)
        log.seekToEndOfFile()
        let ready = files.temporaryDirectory.appendingPathComponent("ai-town-manager-ready.json")
        try? files.removeItem(at: ready)
        let secret = Self.randomHex()
        guard let bin = Bundle.main.executableURL?.deletingLastPathComponent(),
            let resources = Bundle.main.resourceURL
        else { throw TownError(message: "应用包不完整，请重新安装") }
        let process = Process()
        process.executableURL = bin.appendingPathComponent("town-manager")
        process.arguments = [
            "--root", root.path,
            "--app", resources.appendingPathComponent("app").path,
            "--web", resources.appendingPathComponent("web").path,
            "--host-bin", bin.appendingPathComponent("town-host").path,
            "--port", String(Self.port),
            "--ready-file", ready.path,
            "--session-secret", secret,
            "--max-running", "1",
            "--stop-on-stdin-close",
        ]
        let pipe = Pipe()
        process.standardInput = pipe
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async { self?.exited(ended) }
        }
        try process.run()
        self.process = process
        input = pipe.fileHandleForWriting
        return (process, ready, secret)
    }

    private func exited(_ ended: Process) {
        guard ended === process else { return }
        let wasServing = serving
        process = nil
        input = nil
        serving = false
        if !stopWaiters.isEmpty {
            finishStop()
        } else if wasServing {
            onUnexpectedExit?(ended.terminationStatus)
        }
    }

    private func finishStop() {
        let waiters = stopWaiters
        stopWaiters = []
        waiters.forEach { $0() }
    }

    /// 就绪文件是原子写入的；读到的 pid 不是这次启动的进程就继续等
    private static func waitReady(_ process: Process, _ ready: URL) throws -> Int {
        let deadline = Date().addingTimeInterval(startTimeout)
        while Date() < deadline {
            if !process.isRunning {
                throw TownError(message: lastLogLine() ?? "小镇服务启动失败（\(process.terminationStatus)）")
            }
            if let data = try? Data(contentsOf: ready),
                let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                info["pid"] as? Int == Int(process.processIdentifier),
                let port = info["port"] as? Int
            {
                return port
            }
            Thread.sleep(forTimeInterval: 0.06)
        }
        process.terminate()
        throw TownError(message: "小镇服务启动超时")
    }

    /// 管理服务启动失败时最后一行是原因（例如数据目录已被电脑版占用）
    private static func lastLogLine() -> String? {
        guard let handle = try? FileHandle(forReadingFrom: logFile) else { return nil }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        handle.seek(toFileOffset: size > 4096 ? size - 4096 : 0)
        let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
        guard let line = text.split(separator: "\n").last(where: { !$0.isEmpty }) else { return nil }
        return line.replacingOccurrences(of: "[town-manager] ", with: "")
    }

    private static func randomHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
