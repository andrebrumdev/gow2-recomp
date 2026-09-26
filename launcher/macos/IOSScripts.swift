import Foundation

/// A finished script run: exit status and its combined output (the tail of the log).
struct ScriptResult: Equatable {
    let status: Int32
    let output: String

    /// The last "KEY=value" line (P1's scripts end with GOW2_IOS_APP=… and GOW2_IOS_INSTALL_OK).
    func value(_ key: String) -> String? {
        for line in output.split(separator: "\n").reversed() where line.hasPrefix(key + "=") {
            return String(line.dropFirst(key.count + 1))
        }
        return nil
    }

    /// "… (com.apple.dt.CoreDeviceError error 10002 (0x2712))" -> 10002.
    var deviceErrorCode: Int? {
        guard let r = output.range(of: "CoreDeviceError error [0-9]+", options: [.regularExpression, .backwards]) else { return nil }
        return output[r].split(separator: " ").last.flatMap { Int($0) }
    }
}

protocol ScriptRunning: AnyObject {
    func run(_ script: URL, _ args: [String], env: [String: String], log: URL) throws -> ScriptResult
}

/// /bin/bash <script> <args>, stdout+stderr into `log` (overwritten).
final class ProcessScriptRunner: ScriptRunning {
    func run(_ script: URL, _ args: [String], env: [String: String], log: URL) throws -> ScriptResult {
        let fm = FileManager.default
        try fm.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: log.path, contents: nil)
        let out = try FileHandle(forWritingTo: log)
        defer { try? out.close() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path] + args
        p.currentDirectoryURL = script.deletingLastPathComponent()
        p.environment = env
        p.standardOutput = out
        p.standardError = out
        try p.run()
        p.waitUntilExit()
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return ScriptResult(status: p.terminationStatus, output: String(text.suffix(256 * 1024)))
    }
}

enum IOSScripts {
    struct Config: Equatable {
        let team: String
        let device: String
        let bundle: String
        let app: String
    }

    static func dir(repo: URL) -> URL { repo.appendingPathComponent("ios") }

    /// A Finder-launched app has PATH=/usr/bin:/bin:/usr/sbin:/sbin: xcodegen and
    /// the build's python live in Homebrew; the system python3 is 3.9 (too old).
    static func environment(_ base: [String: String],
                            isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> [String: String] {
        var e = base
        let path = base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        e["PATH"] = path.split(separator: ":").contains("/opt/homebrew/bin") ? path : "/opt/homebrew/bin:/usr/local/bin:" + path
        if e["PY"] == nil, isExecutable("/opt/homebrew/bin/python3") { e["PY"] = "/opt/homebrew/bin/python3" }
        if e["DEVELOPER_DIR"] == nil { e["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer" }
        return e
    }

    /// print_config.sh's four lines.
    static func config(_ r: ScriptResult) -> Config? {
        guard r.status == 0, let t = r.value("GOW2_IOS_TEAM"), let d = r.value("GOW2_IOS_DEVICE"),
              let b = r.value("GOW2_IOS_BUNDLE"), let a = r.value("GOW2_IOS_APP") else { return nil }
        return Config(team: t, device: d, bundle: b, app: a)
    }

    /// Mirrors ios_env.sh: com.<team lowercase>.gow2recomp.
    static func defaultBundle(team: String) -> String { "com.\(team.lowercased()).gow2recomp" }
}
