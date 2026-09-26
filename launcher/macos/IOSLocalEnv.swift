import Foundation

enum LocalEnvError: Error, Equatable {
    case invalid(key: String)
}

/// ios/local.env (untracked, sourced by the ios scripts). The launcher writes
/// only GOW2_IOS_TEAM / GOW2_IOS_DEVICE / GOW2_IOS_BUNDLE_ID and keeps every
/// other line (GOW2_WORK, GOW2_IOS_BUILD, comments).
struct LocalEnvFile {
    let url: URL

    static func at(repo: URL) -> LocalEnvFile { LocalEnvFile(url: IOSScripts.dir(repo: repo).appendingPathComponent("local.env")) }

    /// Values the launcher writes: bash-safe without quoting.
    static func valid(_ v: String) -> Bool { v.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil }

    /// KEY=value lines as bash reads them: the value ends at the first blank, "#…" is a comment.
    func read() -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            out[String(line[..<eq])] = String(line[line.index(after: eq)...].prefix { !$0.isWhitespace })
        }
        return out
    }

    func update(_ changes: [String: String]) throws {
        for (k, v) in changes where !LocalEnvFile.valid(v) { throw LocalEnvError.invalid(key: k) }
        var lines = (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: "\n") ?? []
        if lines.last == "" { lines.removeLast() }
        var pending = changes
        lines = lines.map { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { return line }
            let key = String(t[..<eq])
            guard let v = pending.removeValue(forKey: key) else { return line }
            return "\(key)=\(v)"
        }
        for k in pending.keys.sorted() { lines.append("\(k)=\(pending[k]!)") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
